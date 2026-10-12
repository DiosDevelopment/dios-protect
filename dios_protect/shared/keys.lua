-- Editable provider catalog. Functions live on the appropriate client/server side.
ProtectKeys={}
ProtectKeys.order={'qbox','qbcore','wasabi','renewed','mrnewb','zrx','jaksam','quasar','codesign','okok','t1ger','mk','ak47','ak47qb'}
function ProtectKeys.detect()
    local selected=Protect.integration.keys
    if selected=='none' or selected=='custom' then return {selected} end
    if selected~='auto' then
        assert(GetResourceState(Protect.keyResources[selected])=='started','Selected key resource is not started: '..Protect.keyResources[selected])
        return {selected}
    end
    local result={}
    for _,id in ipairs(ProtectKeys.order) do if GetResourceState(Protect.keyResources[id])=='started' then result[#result+1]=id end end
    if #result==0 then result[1]='none' end
    return result
end
function ProtectKeys.plate(value)
    if type(value)~='string' then return nil end
    local plate=value:match('^%s*(.-)%s*$')
    if #plate==0 or #plate>16 then return nil end
    return plate
end
