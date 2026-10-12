-- Editable integration boundary. Framework IDs always identify a character, not a license.
ProtectBridge = {}
local backend, object, name
local resources = Protect.integration.resources
local standaloneJobs={}
local function standaloneId(source)
    if not GetPlayerName(source) then return nil end
    local id=GetPlayerIdentifierByType(source,'license') or GetPlayerIdentifierByType(source,'fivem')
    return id and 'standalone:'..id or nil
end
local function standalonePlayer(source)
    local id=standaloneId(source)
    if not id then return nil end
    local job=IsPlayerAceAllowed(source,Protect.standalone.presidentAce) and {name=Protect.presidentJob,grade={level=Protect.access.minimumGrade},onduty=true}
        or standaloneJobs[id] or {name='unemployed',grade={level=0},onduty=false}
    return {PlayerData={source=source,citizenid=id,job=job,metadata={}}}
end
function ProtectBridge:init()
    if name then return self end
    for _, candidate in ipairs({'falcon','qbox','qbcore','esx'}) do
        if (Protect.integration.framework=='auto' or Protect.integration.framework==candidate)
            and GetResourceState(resources[candidate])=='started' then
            name=candidate
            backend=exports[resources[candidate]]
            if candidate=='qbcore' then object=backend:GetCoreObject() end
            if candidate=='esx' then object=backend:getSharedObject() end
            break
        end
    end
    if not backend then
        assert(Protect.integration.framework=='auto' or Protect.integration.framework=='standalone',
            '[dios_protect] The explicitly selected framework is not started; check integration.resources and resource order.')
        name='standalone'
    end
    self.name=name
    return self
end
local function wrap(p)
    if not p then return nil end
    if name~='esx' then return p end
    local job=p.getJob()
    return {native=p,PlayerData={source=p.source,citizenid=p.getIdentifier(),
        job={name=job.name,grade={level=tonumber(job.grade) or 0},onduty=job.onDuty},
        metadata={isdead=p.get and p.get('isDead') or false}}}
end
function ProtectBridge:GetPlayer(id)
    self:init()
    if name=='standalone' then return standalonePlayer(tonumber(id)) end
    if GetResourceState(resources[name])~='started' then return nil end
    if name=='esx' then return wrap(object.GetPlayerFromId(tonumber(id))) end
    if name=='qbcore' then return object.Functions.GetPlayer(tonumber(id)) end
    return backend:GetPlayer(tonumber(id))
end
function ProtectBridge:GetPlayerByCitizenId(id)
    self:init()
    if name=='standalone' then
        for _,source in ipairs(GetPlayers()) do local p=standalonePlayer(tonumber(source));if p and p.PlayerData.citizenid==id then return p end end
        return nil
    end
    if GetResourceState(resources[name])~='started' then return nil end
    if name=='esx' then return wrap(object.GetPlayerFromIdentifier(id)) end
    if name=='qbcore' then return object.Functions.GetPlayerByCitizenId(id) end
    return backend:GetPlayerByCitizenId(id)
end
function ProtectBridge:GetOfflinePlayer(id)
    self:init()
    if name=='standalone' then
        if type(id)~='string' or id:sub(1,11)~='standalone:' then return nil end
        return {PlayerData={citizenid=id,job=standaloneJobs[id] or {name='unemployed',grade={level=0},onduty=false}}}
    end
    if GetResourceState(resources[name])~='started' then return nil end
    -- ESX restoration stays journaled until this exact character logs back in.
    if name=='esx' then return nil end
    if name=='qbcore' then return object.Functions.GetOfflinePlayerByCitizenId(id) end
    return backend:GetOfflinePlayer(id)
end
local function lookup(self,id)
    return type(id)=='number' and self:GetPlayer(id) or self:GetPlayerByCitizenId(id) or self:GetOfflinePlayer(id)
end
function ProtectBridge:SetJob(id,job,grade)
    self:init()
    if name=='standalone' then
        local p=lookup(self,id)
        if not p then return false end
        -- Office is exclusively an ACE decision. Recovery must never cache presidency.
        standaloneJobs[p.PlayerData.citizenid]=job==Protect.serviceJob and {name=job,grade={level=grade},onduty=true} or nil
        return true
    end
    if name=='falcon' or name=='qbox' then
        local ok=backend:SetJob(id,job,grade)
        if ok==false then return false end
        local current=lookup(self,id)
        return current and current.PlayerData.job.name==job and current.PlayerData.job.grade.level==grade or false
    end
    local p=lookup(self,id)
    if not p then return false end
    if name=='esx' then
        if not object.DoesJobExist(job,tostring(grade)) then return false end
        p.native.setJob(job,grade)
        return p.native.getJob().name==job and tonumber(p.native.getJob().grade)==grade
    end
    local ok=p.Functions.SetJob(job,grade)
    if ok and p.Offline and p.Functions.Save then p.Functions.Save() end
    return ok
end
function ProtectBridge:SetJobDuty(id,duty)
    self:init()
    if name=='standalone' then
        local p=lookup(self,id)
        if p and standaloneJobs[p.PlayerData.citizenid] then standaloneJobs[p.PlayerData.citizenid].onduty=not not duty end
        return
    end
    if name=='falcon' or name=='qbox' then
        backend:SetJobDuty(id,duty)
        if type(id)=='string' and not self:GetPlayerByCitizenId(id) then
            local offline=self:GetOfflinePlayer(id)
            if offline then offline.PlayerData.job.onduty=not not duty;backend:SaveOffline(offline.PlayerData) end
        end
        return
    end
    local p=lookup(self,id)
    if not p then return end
    if name=='esx' then
        p.native.setJob(p.PlayerData.job.name,p.PlayerData.job.grade.level,duty)
    else
        p.Functions.SetJobDuty(duty)
        if p.Offline and p.Functions.Save then p.Functions.Save() end
    end
end
function ProtectBridge:RemovePlayerFromJob(id,job)
    self:init()
    if name=='falcon' or name=='qbox' then return backend:RemovePlayerFromJob(id,job) end
    return true -- Single-job frameworks have no extra membership to remove.
end
function ProtectBridge:RestoreMembership(id,job,grade)
    self:init()
    if name=='falcon' or name=='qbox' then return backend:AddPlayerToJob(id,job,tonumber(grade) or 0) end
    return true
end
function ProtectBridge:GetJob(job)
    self:init()
    if name=='standalone' then return job==Protect.presidentJob and Protect.jobs.president or job==Protect.serviceJob and Protect.jobs.service or nil end
    if name=='esx' then return object.GetJobs()[job] end
    if name=='qbcore' then return object.Shared.Jobs[job] end
    return backend:GetJob(job)
end
function ProtectBridge:CreateJobs(jobs)
    self:init()
    if name=='standalone' then return end
    if not Protect.integration.createJobs then return end
    if name=='esx' then
        -- ESX jobs are persistent SQL definitions; import install/esx.sql first.
        assert(not next(jobs),'[dios_protect] Missing ESX jobs. Import install/esx.sql or define configured jobs in ESX.')
    elseif name=='qbcore' then assert(backend:AddJobs(jobs),'[dios_protect] QBCore job registration failed')
    else backend:CreateJobs(jobs,false) end
end
function ProtectBridge:Notify(source,text,kind)
    TriggerClientEvent('dios_protect:notify',source,text,kind or 'inform')
end
function ProtectBridge:KeysAdapter()
    return table.concat(ProtectKeys.detect(), ',')
end
function ProtectBridge:GiveKeys(source,vehicle,ready)
    return ProtectKeys.give(source,vehicle,ready)
end
