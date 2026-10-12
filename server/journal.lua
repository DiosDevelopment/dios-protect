-- Reject damaged records individually, preserve the raw journal for manual recovery.
ProtectJournal = {}
local function integer(v,max) return type(v)=='number' and v==v and v%1==0 and v>=0 and v<=(max or 1000) end
function ProtectJournal.valid(id,r)
    return type(id)=='string' and #id>0 and #id<=256 and type(r)=='table'
        and type(r.owner)=='string' and #r.owner>0 and #r.owner<=256
        and type(r.name)=='string' and type(r.job)=='string' and #r.job>0
        and integer(r.grade) and (r.duty==nil or type(r.duty)=='boolean')
        and (r.ownerSource==nil or (integer(r.ownerSource,65535) and r.ownerSource>0))
        and (r.pending==nil or type(r.pending)=='boolean')
        and (r.hadService==nil or type(r.hadService)=='boolean')
        and (r.serviceGrade==nil or integer(r.serviceGrade))
end
function ProtectJournal.load()
    local raw=GetResourceKvpString('hires')
    if not raw then return {} end
    local ok,decoded=pcall(json.decode,raw)
    local result,damaged={},not ok or type(decoded)~='table'
    if not damaged then
        for id,r in pairs(decoded) do
            if ProtectJournal.valid(id,r) then result[id]=r else damaged=true end
        end
    end
    if damaged then
        -- Keep the first corrupt input even if a later restart finds another bad journal.
        if not GetResourceKvpString('hires-corrupt-backup') then SetResourceKvp('hires-corrupt-backup',raw) end
        print('[dios_protect] Invalid appointment journal data skipped. Original saved as KVP hires-corrupt-backup; review it before deleting server storage.')
    end
    return result
end
