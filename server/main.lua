local sessions, invitations, cooldowns, locks = {}, {}, {}, {}
local hires = ProtectJournal.load()
local serial = 0
local rates = {}
local protectedVehicles = {}
local core = ProtectBridge
local function allowed(source)
    local now=GetGameTimer()
    if (rates[source] or 0)>now then return false end
    rates[source]=now+500
    return true
end
local function saveHires() SetResourceKvp('hires', json.encode(hires)) end
local function player(source) return core:GetPlayer(source) end
local function president(source)
    local p = player(source)
    local job=p and p.PlayerData.job
    return job and job.name == Protect.presidentJob and job.grade.level>=Protect.access.minimumGrade
        and (not Protect.access.requireDuty or job.onduty==true)
end
-- Server-only attestation. State bags, license plates and client ownership are
-- never authority to bypass the blacklist. This export grants no permissions.
local function isProtectedEntity(handle)
    if type(handle)~='number' then return false end
    local record=protectedVehicles[handle]
    if not record or not DoesEntityExist(handle) or GetEntityType(handle)~=record.kind then return false end
    if record.net==0 then record.net=NetworkGetNetworkIdFromEntity(handle) end
    local session=sessions[record.session.owner]
    local owner=player(record.session.owner)
    return session==record.session and owner~=nil and president(session.owner)
        and owner.PlayerData.citizenid==session.citizenid
        and GetEntityModel(handle)==record.model
        and NetworkGetNetworkIdFromEntity(handle)==record.net
        and GetEntityRoutingBucket(handle)==session.bucket
        and GetPlayerRoutingBucket(session.owner)==session.bucket
end
exports('IsProtectedEntity',isProtectedEntity)
exports('IsProtectedVehicle',function(handle) return type(handle)=='number' and GetEntityType(handle)==2 and isProtectedEntity(handle) end)
AddEventHandler('entityRemoved',function(handle)
    protectedVehicles[handle]=nil
    for _,session in pairs(sessions) do if session.tactical then
        for id,record in pairs(session.tactical.threats) do if record.entity==handle then session.tactical.threats[id]=nil end end
    end end
end)
local visibility={}
local function publicIntent(intent)
    if not intent then return nil end
    local copy={};for k,v in pairs(intent) do copy[k]=v end
    copy.threats={}
    for id,r in pairs(intent.threats) do local threat={};for k,v in pairs(r) do if k~='entity' then threat[k]=v end end;copy.threats[id]=threat end
    return copy
end
local function visible(source,session)
    if GetPlayerRoutingBucket(source)~=session.bucket then return false end
    if source==session.owner then return true end
    local ped=GetPlayerPed(source)
    if ped~=0 and #(GetEntityCoords(ped)-GetEntityCoords(GetPlayerPed(session.owner)))<=600 then return true end
    for _,entry in ipairs(session.entities) do if DoesEntityExist(entry.handle) and NetworkGetEntityOwner(entry.handle)==source then return true end end
    return false
end
local function publicSession(s)
    return {id=s.id,owner=s.owner,bucket=s.bucket,guards=s.guards,vehicles=s.vehicles,air=s.air,
        mode=s.mode,detail=s.detail,agents=s.agents,deploying=s.deploying,tactical=publicIntent(s.tactical),
        airCooldown=math.max(0,(s.nextAir or 0)-os.time()),airDeploying=s.airDeploying~=nil}
end
local function sync(source,force)
    local snapshot,ids={},{}
    for owner,s in pairs(sessions) do if visible(source,s) then snapshot[owner]=publicSession(s);ids[#ids+1]=s.id end end
    table.sort(ids)
    local signature=GetPlayerRoutingBucket(source)..':'..table.concat(ids,',')
    if force or visibility[source]~=signature then
        visibility[source]=signature;TriggerClientEvent('dios_protect:sync',source,snapshot)
    end
end
local function emitIntent(session)
    local intent=publicIntent(session.tactical)
    for _,id in ipairs(GetPlayers()) do local source=tonumber(id);if visible(source,session) then
        TriggerClientEvent('dios_protect:tacticalSync',source,session.owner,session.id,intent)
    end end
end
local function publish()
    for _,session in pairs(sessions) do
        session.agents={}
        for id,record in pairs(hires) do
            if record.ownerSource==session.owner and record.owner==session.citizenid then
                local agent=core:GetPlayerByCitizenId(id)
                if agent then session.agents[#session.agents+1]=agent.PlayerData.source end
            end
        end
    end
    for _,id in ipairs(GetPlayers()) do sync(tonumber(id),true) end
end
local function notify(source, text, kind) core:Notify(source, text, kind or 'inform') end
local tactics=ProtectServerTactical.new({session=function(source) return sessions[source] end,player=player,emit=emitIntent,
    protected=isProtectedEntity,publish=publish,authorized=function(source,session)
        return president(source) and player(source).PlayerData.citizenid==session.citizenid and GetPlayerRoutingBucket(source)==session.bucket
    end})
RegisterNetEvent('dios_protect:tacticalReport',function(data) tactics.report(source,data) end)
RegisterNetEvent('dios_protect:extraction',function(data) tactics.extraction(source,data) end)
RegisterNetEvent('dios_protect:extractionFailed',function(data) tactics.extractionFailed(source,data) end)
RegisterNetEvent('dios_protect:stageResult',function(id,token,result)
    local s=sessions[source]
    if not s or not s.deploying or s.id~=id or s.stageToken~=token or s.stageAnswered
        or not president(source) or player(source).PlayerData.citizenid~=s.citizenid
        or GetPlayerRoutingBucket(source)~=s.bucket then return end
    s.stageAnswered=true
    s.stageReply=result==true and true or type(result)=='table' and type(result.error)=='string'
        and {error=result.error:sub(1,300)} or false
end)
local function destroy(session, convoyOnly)
    if not convoyOnly then session.cancelled=true;session.reserved=0;session.stageToken=nil end
    for i = #session.entities, 1, -1 do
        local entry = session.entities[i]
        if not convoyOnly or entry.convoy then
            protectedVehicles[entry.handle]=nil
            if DoesEntityExist(entry.handle) then DeleteEntity(entry.handle) end
            table.remove(session.entities, i)
        end
    end
    if convoyOnly then session.vehicles = {}; session.detail.driver=nil; session.detail.destination=nil
    else session.guards, session.vehicles, session.air = {}, {}, nil end
end
local function createEntity(session,model,pos,vehicleType,convoy,air)
    local function active()
        local p=player(session.owner)
        return not session.cancelled and sessions[session.owner]==session and p and president(session.owner)
            and p.PlayerData.citizenid==session.citizenid and GetPlayerRoutingBucket(session.owner)==session.bucket
            and (not air or (session.airDeploying and not session.airDeploying.cancelled))
    end
    assert(active(),ProtectText('Protection deployment was interrupted'))
    local ent
    if vehicleType then ent=CreateVehicleServerSetter(joaat(model),vehicleType,pos.x,pos.y,pos.z,pos.h)
    else ent=CreatePed(4,joaat(model),pos.x,pos.y,pos.z,pos.h,true,true) end
    if not ent or ent==0 then error(ProtectText('Entity creation failed')) end
    session.entities[#session.entities+1]={handle=ent,convoy=convoy,air=air}
    session.reserved=math.max(0,(session.reserved or 0)-1)
    protectedVehicles[ent]={session=session,model=joaat(model),net=NetworkGetNetworkIdFromEntity(ent),kind=vehicleType and 2 or 1}
    local bucketAssigned=false
    local function assignBucket()
        if not bucketAssigned and DoesEntityExist(ent) then
            SetEntityRoutingBucket(ent,session.bucket);SetEntityOrphanMode(ent,2);bucketAssigned=true
        end
    end
    assignBucket()
    local deadline=GetGameTimer()+8000
    while not DoesEntityExist(ent) or NetworkGetNetworkIdFromEntity(ent)==0 do
        assert(active(),ProtectText('Protection deployment was interrupted'))
        assignBucket()
        if GetGameTimer()>deadline then error(('Entity replication timed out: %s'):format(model)) end
        Wait(25)
    end
    assert(active(),ProtectText('Protection deployment was interrupted'))
    assert(protectedVehicles[ent],ProtectText('A deployment entity disappeared'))
    assignBucket()
    protectedVehicles[ent].net=NetworkGetNetworkIdFromEntity(ent)
    Entity(ent).state:set('diosProtection',session.id,true)
    if vehicleType then
        assert(core:GiveKeys(session.owner,ent),ProtectText('President vehicle keys could not be assigned'))
    end
    assert(active() and DoesEntityExist(ent),ProtectText('Protection deployment was interrupted'))
    if vehicleType then FreezeEntityPosition(ent,true) end
    return NetworkGetNetworkIdFromEntity(ent)
end
local function removeAir(session)
    if session.airDeploying then session.airDeploying.cancelled=true end
    for i=#session.entities,1,-1 do
        local e=session.entities[i]
        if e.air then protectedVehicles[e.handle]=nil;if DoesEntityExist(e.handle) then DeleteEntity(e.handle) end;table.remove(session.entities,i) end
    end
    session.air=nil
end
local function restoreRecord(citizenid)
    local record = hires[citizenid]
    if not record then return end
    local p = core:GetPlayerByCitizenId(citizenid) or core:GetOfflinePlayer(citizenid)
    if not p then return end
    if p.PlayerData.job.name == Protect.serviceJob then
        local ok = core:SetJob(citizenid, record.job, record.grade)
        if not ok then return end
        core:SetJobDuty(citizenid, record.duty)
    end
    if record.hadService then
        if core:RestoreMembership(citizenid,Protect.serviceJob,record.serviceGrade)==false then return end
    else if core:RemovePlayerFromJob(citizenid, Protect.serviceJob)==false then return end end
    hires[citizenid] = nil
    saveHires()
end
local restoreNotices={}
local function restore(citizenid)
    local ok,err=pcall(restoreRecord,citizenid)
    if not ok and (restoreNotices[citizenid] or 0)<os.time() then
        restoreNotices[citizenid]=os.time()+60
        print('[dios_protect] Appointment restoration retained for retry: '..tostring(err))
    end
end
local function stop(source, all)
    local session = sessions[source]
    local owner = player(source)
    local identity=session and session.citizenid or owner and owner.PlayerData.citizenid
    if session then destroy(session); sessions[source] = nil;if locks[source]==session then locks[source]=nil end end
    if all then
        for id, record in pairs(hires) do
            if identity and record.owner==identity then restore(id) end
        end
        for id, invite in pairs(invitations) do if invite.owner == source then TriggerClientEvent('dios_protect:inviteCancel',id,invite.token);invitations[id] = nil end end
    end
    publish()
end
local function nearby(source, target)
    if source == target or not player(target) or GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(target) then return false end
    return #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(target))) <= Protect.inviteRange
end
local function state(source)
    local owner = player(source)
    local agents, candidates, offers = {}, {}, {}
    local session=sessions[source]
    local counts={foot=0,crew=0,vehicles=0,air=0,airCrew=0,airPilot=0}
    local function alive(net) local e=NetworkGetEntityFromNetworkId(net or 0);return e~=0 and DoesEntityExist(e) and GetEntityHealth(e)>0 end
    if session then
        for _,net in ipairs(session.guards) do if alive(net) then counts.foot=counts.foot+1 end end
        for _,entry in ipairs(session.vehicles) do
            if alive(entry.net) then counts.vehicles=counts.vehicles+1 end
            for _,net in ipairs(entry.crew) do if alive(net) then counts.crew=counts.crew+1 end end
        end
        if session.air and alive(session.air.net) then counts.air=1;counts.airPilot=alive(session.air.crew[1]) and 1 or 0;for _,net in ipairs(session.air.crew) do if alive(net) then counts.airCrew=counts.airCrew+1 end end end
    end
    for target,offer in pairs(invitations) do
        if owner and offer.owner==source and offer.ownerCitizen==owner.PlayerData.citizenid and offer.expires>os.time() then
            offers[#offers+1]={name=GetPlayerName(target),remainingSeconds=offer.expires-os.time()}
        end
    end
    for id, record in pairs(hires) do
        if owner and record.owner == owner.PlayerData.citizenid then
            local p = core:GetPlayerByCitizenId(id)
            agents[#agents+1] = { citizenid=id, id=p and p.PlayerData.source, name=record.name, onDuty=p and p.PlayerData.job.onduty==true }
        end
    end
    for _, target in ipairs(GetPlayers()) do
        target = tonumber(target)
        local p = player(target)
        if p and nearby(source, target) and not hires[p.PlayerData.citizenid] then
            candidates[#candidates+1] = { id=target, name=GetPlayerName(target),distance=#(GetEntityCoords(GetPlayerPed(source))-GetEntityCoords(GetPlayerPed(target))),pending=invitations[target]~=nil }
        end
    end
    return { active = sessions[source] ~= nil, deploying=session and session.deploying==true or false, counts=counts, offers=offers, mode=session and session.mode,
        airCooldown=session and math.max(0,(session.nextAir or 0)-os.time()) or 0, airDeploying=session and session.airDeploying~=nil or false, agents=agents, nearby=candidates, vehicles=Protect.vehicles,
        maxGuards=Protect.maxGuards, maxVehicles=Protect.maxVehicles, longConvoyThreshold=Protect.longConvoyThreshold,
        detail=sessions[source] and sessions[source].detail, tactical=sessions[source] and publicIntent(sessions[source].tactical),tacticalEnabled=Protect.tactical.enabled,
        airActive=sessions[source] and sessions[source].air~=nil, modes=Protect.guards,
        locale=Protect.locale, translations=ProtectLocalePayload(), ui=Protect.ui, inviteRange=Protect.inviteRange,
        defaults={speed=Protect.defaultSpeedKph,gap=Protect.defaultGap,formation=Protect.tactical.formation,airModel=Protect.airModel,closeGuards=Protect.tactical.minimumCloseGuards}, framework=core.name,environment=ProtectEnvironment.snapshot() }
end
ProtectRPC.register('dios_protect:state', function(source)
    if not president(source) then return { error=ProtectText('Only the President can manage protection.') } end
    return state(source)
end)
local function entityCount()
    local total = 0
    for _, session in pairs(sessions) do total = total + #session.entities+(session.reserved or 0) end
    return total
end
ProtectRPC.register('dios_protect:deploy', function(source, data, positions)
    if not president(source) then return { error=ProtectText('President access required.') } end
    if locks[source] then return {error=ProtectText('Deployment already in progress.')} end
    local selected, err = ProtectPolicy.selection(data)
    if not selected then return {error=err} end
    local guardModels=ProtectPolicy.guardModels(type(positions)=='table' and positions.guardModels,selected.mode)
    if not guardModels then return {error=ProtectText('Choose a valid guard detail.')} end
    if sessions[source] then return {error=ProtectText('Stand down the current detail before changing its deployment.')} end
    if (cooldowns[source] or 0) > os.time() then return {error=ProtectText('Please wait before deploying another detail.')} end
    local ownerPed = GetPlayerPed(source)
    if ownerPed == 0 or GetEntityHealth(ownerPed) <= 0 then return {error=ProtectText('Cannot deploy while incapacitated.')} end
    local origin, needed = GetEntityCoords(ownerPed), selected.count
    for _, v in ipairs(selected.vehicles) do needed = needed + 1 + v.seats end
    if entityCount() + needed > Protect.globalEntityLimit then return {error=ProtectText('Server protection capacity reached.')} end
    if type(positions) ~= 'table' or type(positions.guards) ~= 'table' or type(positions.vehicles) ~= 'table'
        or #positions.guards ~= selected.count or #positions.vehicles ~= #selected.vehicles then return {error=ProtectText('Invalid deployment positions.')} end
    for _, pos in ipairs(positions.guards) do
        if not ProtectPolicy.position(pos, origin, Protect.footSpawnMin) then return {error=ProtectText('Guard deployment position is unsuitable.')} end
    end
    for _, pos in ipairs(positions.vehicles) do
        if not ProtectPolicy.position(pos, origin, Protect.vehicleSpawnMin) then return {error=ProtectText('Convoy deployment position is unsuitable.')} end
    end
    locks[source], cooldowns[source] = true, os.time()+Protect.deployCooldown
    serial = serial + 1
    local session = { id=serial, owner=source, citizenid=player(source).PlayerData.citizenid, bucket=GetPlayerRoutingBucket(source), guards={}, vehicles={}, entities={}, reserved=needed,mode=selected.mode,
        deploying=true, detail={speed=Protect.defaultSpeedKph,gap=Protect.defaultGap,style='normal',order='follow',air='off',revision=0} }
    session.tactical=ProtectTactical.new(GetGameTimer())
    if Protect.diagnostics.enabled then print(('[dios_protect] Deployment accepted: %d guards, %d vehicles.'):format(selected.count,#selected.vehicles)) end
    sessions[source]=session
    locks[source]=session
    local function create(model, pos, vehicle, convoy)
        return createEntity(session,model,pos,vehicle and 'automobile' or nil,convoy,false)
    end
    local ok, failure = pcall(function()
        local models=guardModels
        session.guardModels=models
        local cursor=0
        local function guardModel() cursor=cursor+1;return models[(cursor-1)%#models+1] end
        for i, pos in ipairs(positions.guards) do session.guards[i] = create(guardModel(), pos, false, false) end
        for i, definition in ipairs(selected.vehicles) do
            local pos = positions.vehicles[i]
            local entry = { net=create(definition.model, pos, true, true), crew={}, model=definition.model }
            for seat=1, definition.seats do entry.crew[seat] = create(guardModel(), pos, false, true) end
            session.vehicles[i] = entry
        end
        publish()
        session.stageToken=('%s:%s:%s'):format(os.time(),GetGameTimer(),math.random(1,2147483647))
        local deadline=GetGameTimer()+Protect.performance.stagingTimeout+2000
        TriggerClientEvent('dios_protect:stageRequest',source,publicSession(session),session.stageToken)
        if Protect.diagnostics.enabled then print('[dios_protect] Deployment entities created; waiting for owner crew staging.') end
        while not session.stageAnswered do
            assert(not session.cancelled and sessions[source]==session and president(source)
                and player(source).PlayerData.citizenid==session.citizenid and GetPlayerRoutingBucket(source)==session.bucket,
                ProtectText('Protection deployment was interrupted'))
            assert(GetGameTimer()<deadline,ProtectText('Not every selected convoy vehicle and driver became ready'))
            Wait(50)
        end
        local ready=session.stageReply
        session.stageToken=nil;session.stageReply=nil;session.stageAnswered=nil
        assert(ready==true,type(ready)=='table' and ready.error or ProtectText('Not every selected convoy vehicle and driver became ready'))
        assert(not session.cancelled and sessions[source]==session and president(source)
            and player(source).PlayerData.citizenid==session.citizenid and GetPlayerRoutingBucket(source)==session.bucket,
            ProtectText('Protection deployment was interrupted'))
        for _,entity in ipairs(session.entities) do assert(DoesEntityExist(entity.handle),ProtectText('A deployment entity disappeared')) end
        -- Retry plate-based key delivery after client staging has initialized every vehicle.
        for _,entry in ipairs(session.vehicles) do assert(core:GiveKeys(source,NetworkGetEntityFromNetworkId(entry.net),true)) end
        session.deploying=nil;session.reserved=0
    end)
    if locks[source]==session then locks[source] = nil end
    if not ok then destroy(session);if sessions[source]==session then sessions[source]=nil end;publish();print('[dios_protect] deployment rolled back: '..tostring(failure)); return {error=ProtectText('Dispatch could not complete: ')..tostring(failure):gsub('^.-:%d+: ','')} end
    sessions[source] = session
    publish()
    return state(source)
end)
ProtectRPC.register('dios_protect:control',function(source,action,data)
    local session=sessions[source]
    if not president(source) or not session or player(source).PlayerData.citizenid~=session.citizenid or GetPlayerRoutingBucket(source)~=session.bucket then return {error=ProtectText('Deploy your protection detail first.')} end
    data=type(data)=='table' and data or {}
    if not allowed(source) then return {error=ProtectText('Please wait before sending another order.')} end
    local detail=session.detail
    if session.deploying then return {error=ProtectText('Your detail is still staging. Wait for deployment to finish.')} end
    if action=='tactical' then
        if not tactics.control(session,data) then return {error=ProtectText('Invalid tactical order.')} end
    elseif action=='settings' then
        local settings,reason=ProtectPolicy.control(data)
        if not settings then return {error=reason} end
        for key,value in pairs(settings) do detail[key]=value end
        if detail.air=='off' then removeAir(session) end
    elseif action=='driver' then
        local driverNet,carNet=ProtectPolicy.networkId(data.driver),ProtectPolicy.networkId(data.vehicle)
        if not driverNet or not carNet then return {error=ProtectText('Invalid driver or vehicle ID.')} end
        local found=false
        for _,net in ipairs(session.guards) do if net==driverNet then found=true end end
        local convoyCar=false
        for _,entry in ipairs(session.vehicles) do
            if entry.net==carNet then convoyCar=true end
            for i,net in ipairs(entry.crew) do
                if net==driverNet and (i>1 or entry.net==carNet) then found=true end
            end
        end
        if not found then return {error=ProtectText('Select a guard from your detail; another convoy driver cannot be reassigned.')} end
        local car=NetworkGetEntityFromNetworkId(carNet or 0)
        local ped=NetworkGetEntityFromNetworkId(driverNet or 0)
        if car==0 or ped==0 or not isProtectedEntity(ped) or not DoesEntityExist(car) or not DoesEntityExist(ped) or GetEntityHealth(ped)<=0 or GetEntityType(car)~=2 then return {error=ProtectText('Driver or vehicle is unavailable.')} end
        if GetEntityRoutingBucket(car)~=session.bucket or #(GetEntityCoords(car)-GetEntityCoords(GetPlayerPed(source)))>30 then return {error=ProtectText('Bring your vehicle within 30 metres.')} end
        if not convoyCar and GetVehiclePedIsIn(GetPlayerPed(source),false)~=car then return {error=ProtectText('Sit in the passenger seat of the vehicle you want driven.')} end
        detail.driver={ped=driverNet,vehicle=carNet};detail.destination=nil
        session.tactical.extraction=nil;session.tactical.previousDriver=nil;session.tactical.restoringDriver=nil
    elseif action=='waypoint' then
        if not detail.driver then return {error=ProtectText('Assign your driver first.')} end
        local car=NetworkGetEntityFromNetworkId(detail.driver.vehicle)
        if car==0 or not DoesEntityExist(car) then return {error=ProtectText('Your chauffeur vehicle is unavailable.')} end
        if GetVehiclePedIsIn(GetPlayerPed(source),false)~=car then return {error=ProtectText('Board your chauffeur vehicle before starting the route.')} end
        local pos=data.destination
        if type(pos)~='table' then return {error=ProtectText('Set a waypoint on the map first.')} end
        for _,key in ipairs({'x','y','z'}) do
            if type(pos[key])~='number' or pos[key]~=pos[key] or math.abs(pos[key])>10000 then return {error=ProtectText('Invalid waypoint.')} end
        end
        detail.destination={x=pos.x,y=pos.y,z=pos.z}
        session.tactical.routePaused=nil
    elseif action=='stop' then detail.destination=nil;session.tactical.routePaused=true
    elseif action=='release' then
        if session.tactical.extraction or session.tactical.manualExtraction then tactics.control(session,{command='cancel'}) end
        detail.driver=nil;detail.destination=nil
    elseif action=='air' then
        if detail.air=='off' then return {error=ProtectText('Enable helicopter escort or automatic air support first.')} end
        if session.air or session.airDeploying then return state(source) end
        if (session.nextAir or 0)>os.time() then return {error=ProtectText('Air support is refuelling; wait before requesting it again.')} end
        if entityCount()+4>Protect.globalEntityLimit then return {error=ProtectText('Server protection capacity reached.')} end
        local origin=GetEntityCoords(GetPlayerPed(source))
        if not ProtectPolicy.airPosition(data.position,origin) then return {error=ProtectText('No suitable hidden aerial staging position.')} end
        local pos=data.position
        local airOperation={cancelled=false}
        session.airDeploying=airOperation;session.reserved=(session.reserved or 0)+4
        local ok,reason=pcall(function()
            local entry={net=createEntity(session,Protect.airModel,pos,'heli',false,true),crew={}}
            session.air=entry
            for i=1,3 do
                assert(not airOperation.cancelled and session.air==entry,'Air deployment was interrupted')
                local models=session.guardModels or Protect.guards[session.mode].models
                entry.crew[i]=createEntity(session,models[(i-1)%#models+1],pos,nil,false,true)
            end
            assert(core:GiveKeys(source,NetworkGetEntityFromNetworkId(entry.net),true))
            assert(not airOperation.cancelled and session.air==entry and sessions[source]==session and not session.cancelled,'Air deployment was interrupted')
        end)
        session.airDeploying=nil;session.reserved=0
        session.nextAir=os.time()+Protect.airCooldown
        if not ok then removeAir(session);print('[dios_protect] air deployment rolled back: '..tostring(reason));return {error=ProtectText('Air support could not be dispatched.')} end
    elseif action=='recallAir' then removeAir(session);detail.air='off'
    else return {error=ProtectText('Unknown detail control.')} end
    detail.revision=detail.revision+1
    publish()
    return state(source)
end)
RegisterNetEvent('dios_protect:arrived',function(owner,revision)
    owner=ProtectPolicy.networkId(owner)
    local session=owner and sessions[owner]
    local detail=session and session.detail
    if not detail or not detail.driver or not detail.destination or detail.revision~=revision or not president(owner) then return end
    local driver=NetworkGetEntityFromNetworkId(detail.driver.ped)
    if source~=owner and (driver==0 or NetworkGetEntityOwner(driver)~=source) then return end
    local car=NetworkGetEntityFromNetworkId(detail.driver.vehicle)
    if car==0 or not DoesEntityExist(car) then return end
    local p,d=GetEntityCoords(car),detail.destination
    if math.sqrt((p.x-d.x)^2+(p.y-d.y)^2)>20 then return end
    detail.destination=nil;detail.revision=detail.revision+1;publish()
    notify(owner,ProtectText('Your chauffeur has reached the waypoint.'),'success')
end)
ProtectRPC.register('dios_protect:action', function(source, action, target)
    if not president(source) then return {error=ProtectText('President access required.')} end
    if action == 'off' then stop(source, false)
    elseif action == 'disband' then
        if sessions[source] and sessions[source].deploying then stop(source,false);return state(source) end
        if sessions[source] then
            destroy(sessions[source], true)
            if #sessions[source].entities==0 then sessions[source]=nil end
            publish()
        end
    elseif action == 'dismissAll' then stop(source, true)
    elseif action == 'dismiss' then
        if type(target) ~= 'string' or not hires[target] or hires[target].owner ~= player(source).PlayerData.citizenid then return {error=ProtectText('Agent is not assigned to you.')} end
        restore(target); publish()
    elseif action == 'invite' then
        if not allowed(source) then return {error=ProtectText('Please wait before sending another invitation.')} end
        target = tonumber(target)
        if not target or not nearby(source,target) then return {error=ProtectText('invite_distance',{range=Protect.inviteRange})} end
        local p = player(target)
        if hires[p.PlayerData.citizenid] or invitations[target] then return {error=ProtectText('Player is already assigned or has a pending offer.')} end
        local total = #state(source).agents
        for _, invite in pairs(invitations) do if invite.owner == source then total=total+1 end end
        if total >= Protect.maxAgents then return {error=ProtectText('The player detail is full.')} end
        invitations[target] = {owner=source, ownerCitizen=player(source).PlayerData.citizenid,
            targetCitizen=p.PlayerData.citizenid, expires=os.time()+Protect.inviteExpiry,token=('%s:%s:%s'):format(GetGameTimer(),target,math.random(1,2147483647))}
        TriggerClientEvent('dios_protect:invite', target, GetPlayerName(source), Protect.inviteExpiry,invitations[target].token)
        notify(source, ProtectText('Protection invitation sent.'))
    else return {error=ProtectText('Unknown protection action.')} end
    return state(source)
end)
RegisterNetEvent('dios_protect:answer', function(accepted,token)
    local target = source
    local invite = invitations[target]
    if not invite or token~=invite.token then return end
    invitations[target] = nil
    if not invite or invite.expires < os.time() or not president(invite.owner) then return end
    local p, owner = player(target), player(invite.owner)
    if not p or p.PlayerData.citizenid ~= invite.targetCitizen or not owner or owner.PlayerData.citizenid ~= invite.ownerCitizen then return end
    if accepted ~= true then notify(invite.owner,ProtectText('Protection invitation declined.')); return end
    if not nearby(invite.owner, target) or hires[p.PlayerData.citizenid] then return end
    local previous = { owner=owner.PlayerData.citizenid, ownerSource=invite.owner, name=GetPlayerName(target),
        job=p.PlayerData.job.name, grade=p.PlayerData.job.grade.level, duty=p.PlayerData.job.onduty,
        hadService=p.PlayerData.jobs and p.PlayerData.jobs[Protect.serviceJob] ~= nil,
        serviceGrade=p.PlayerData.jobs and p.PlayerData.jobs[Protect.serviceJob],pending=true }
    hires[p.PlayerData.citizenid] = previous
    saveHires() -- Durable recovery journal before changing the job.
    if not core:SetJob(target, Protect.serviceJob, 0) then restore(p.PlayerData.citizenid); notify(target,ProtectText('Appointment could not be completed; your previous job was restored.'),'error'); return end
    previous.pending=nil
    saveHires()
    core:SetJobDuty(target,true)
    publish()
    notify(target, ProtectText('Assigned to Secret Service. Your previous job will be restored when dismissed.'), 'success')
    notify(invite.owner, ProtectText('agent_joined',{name=GetPlayerName(target)}), 'success')
end)
RegisterNetEvent('dios_protect:requestSync', function() if allowed(source) then sync(source,true);TriggerClientEvent('dios_protect:environment',source,ProtectEnvironment.snapshot()) end end)
AddEventHandler('playerDropped', function()
    local target=source
    tactics.cleanup(target)
    stop(target,true); invitations[target]=nil; cooldowns[target]=nil; rates[target]=nil;visibility[target]=nil
    for id,record in pairs(hires) do
        local p=core:GetPlayerByCitizenId(id)
        if p and p.PlayerData.source == target then restore(id) end
    end
end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then
        if core.name~='standalone' and name==Protect.integration.resources[core.name] then
            for source in pairs(sessions) do stop(source,true) end
            print('[dios_protect] Framework stopped. Details removed; appointment recovery remains journaled. Restart dios_protect after the framework.')
        end
        return
    end
    for _,session in pairs(sessions) do destroy(session) end
    for id in pairs(hires) do restore(id) end
end)
CreateThread(function()
    -- Restore interrupted assignments after a crash/restart; never overwrite an existing job definition.
    local jobs={}
    if not core:GetJob(Protect.presidentJob) then jobs[Protect.presidentJob]=Protect.jobs.president end
    if not core:GetJob(Protect.serviceJob) then jobs[Protect.serviceJob]=Protect.jobs.service end
    if next(jobs) then core:CreateJobs(jobs,false) end
    assert(core:GetJob(Protect.presidentJob) and core:GetJob(Protect.serviceJob),'[dios_protect] Missing configured jobs; follow README installation steps.')
    for id in pairs(hires) do restore(id) end
    while true do
        Wait(Protect.performance.maintenanceTick)
        for source,session in pairs(sessions) do
            local ped=GetPlayerPed(source)
            local p=player(source)
            local metadata=p and p.PlayerData.metadata or {}
            if not president(source) or p.PlayerData.citizenid~=session.citizenid or ped==0 or GetEntityHealth(ped)<=0 or metadata.isdead or metadata.inlaststand or GetPlayerRoutingBucket(source)~=session.bucket then stop(source,true)
            else tactics.maintenance(session) end
        end
        for target,invite in pairs(invitations) do if invite.expires<os.time() then invitations[target]=nil end end
        for id,record in pairs(hires) do
            local owner=core:GetPlayerByCitizenId(record.owner)
            local agent=core:GetPlayerByCitizenId(id)
            if not owner or not president(owner.PlayerData.source) or not agent or agent.PlayerData.job.name~=Protect.serviceJob then restore(id) end
        end
        for _,id in ipairs(GetPlayers()) do sync(tonumber(id),false) end
    end
end)
