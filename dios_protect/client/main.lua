local sessions, runtime, menuOpen, deploying = {}, {}, false, false
local group = joaat('DIOS_PROTECTION')
local environment={edition='Unknown',framework='unknown'}
RegisterNetEvent('dios_protect:environment',function(data) if type(data)=='table' then environment=data end end)
AddRelationshipGroup('DIOS_PROTECTION')
local function notice(text, kind) ProtectClient.notify(text,kind) end
local invitation
local uiEligible=true
local function closeMenu() menuOpen=false; SetNuiFocus(invitation~=nil,invitation~=nil); SendNUIMessage({action='close'}) end
local function nui(route,handler)
    RegisterNUICallback(route,function(data,callback)
        local replied=false
        local function reply(result)
            if replied then return end
            replied=true;callback(result or {ok=true})
        end
        local ok,err=pcall(handler,type(data)=='table' and data or {},reply)
        if not ok then
            print(('[dios_protect] NUI %s: %s'):format(route,tostring(err)))
            reply({error=ProtectText('Service unavailable.')})
        elseif not replied then reply({error=ProtectText('Service unavailable.')}) end
    end)
end
local function resolve(net)
    net=tonumber(net)
    if not net or not NetworkDoesEntityExistWithNetworkId(net) then return 0 end
    return NetToEnt(net)
end
local function owned(entity) return entity~=0 and DoesEntityExist(entity) and NetworkHasControlOfEntity(entity) end
local function context(entity, token)
    local record=runtime[entity]
    local net=entity~=0 and DoesEntityExist(entity) and NetworkGetNetworkIdFromEntity(entity) or 0
    if not record or record.token~=token or record.net~=net then record={token=token,net=net}; runtime[entity]=record end
    return record
end
local function configurePed(ped, principal, token, mode)
    local r=context(ped,token)
    if not r.initialized then
        SetEntityAsMissionEntity(ped,true,true)
        SetPedRelationshipGroupHash(ped,group)
        SetRelationshipBetweenGroups(0,group,GetPedRelationshipGroupHash(principal))
        SetRelationshipBetweenGroups(0,GetPedRelationshipGroupHash(principal),group)
        SetBlockingOfNonTemporaryEvents(ped,true)
        SetPedFleeAttributes(ped,0,false)
        SetPedCombatAttributes(ped,46,false) -- Do not fight armed attackers without a weapon.
        SetPedCombatAttributes(ped,5,true)
        SetPedCombatAttributes(ped,54,true) -- Select the best weapon for combat.
        SetPedCombatAttributes(ped,0,true)
        SetPedCombatAttributes(ped,2,true)
        SetPedCanSwitchWeapon(ped,true)
        SetPedCombatAbility(ped,2)
        SetPedCombatRange(ped,2)
        SetPedCombatMovement(ped,1)
        SetPedCombatAttributes(ped,50,false) -- Hold defensive firing positions rather than charge.
        SetPedAccuracy(ped,65)
        SetPedCanRagdoll(ped,true)
        SetPedDropsWeaponsWhenDead(ped,false)
        r.concealed=mode and Protect.guards[mode] and Protect.guards[mode].concealed
        -- Never heal an existing guard when network ownership changes.
        if not Entity(ped).state.diosEquipped then
            SetPedRandomComponentVariation(ped,0)
            SetPedRandomProps(ped)
            SetEntityMaxHealth(ped,Protect.guardHealth)
            SetEntityHealth(ped,Protect.guardHealth)
            SetPedArmour(ped,Protect.guardArmour)
            GiveWeaponToPed(ped,joaat(Protect.guardWeapon),500,false,not r.concealed)
            if r.concealed then SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true) end
            SetPedKeepTask(ped,true)
            Entity(ped).state:set('diosEquipped',true,true)
        end
        r.initialized=true
    end
    return r
end
local function armGuard(ped)
    local weapon=joaat(Protect.guardWeapon)
    if not HasPedGotWeapon(ped,weapon,false) then GiveWeaponToPed(ped,weapon,500,false,true) end
    if GetAmmoInPedWeapon(ped,weapon)<60 then SetPedAmmo(ped,weapon,500) end
    SetCurrentPedWeapon(ped,weapon,true)
end
local function ownSession() return sessions[GetPlayerServerId(PlayerId())] or sessions[tostring(GetPlayerServerId(PlayerId()))] end
local function speedLimit(session)
    local limit=300
    local function include(car)
        if car~=0 and DoesEntityExist(car) then
            local estimate=GetVehicleEstimatedMaxSpeed(car)*3.6
            if estimate>1 then limit=math.min(limit,estimate) end
        end
    end
    include(GetVehiclePedIsIn(PlayerPedId(),false))
    for _,entry in ipairs(session and session.vehicles or {}) do include(resolve(entry.net)) end
    if session and session.detail.driver then include(resolve(session.detail.driver.vehicle)) end
    return math.max(5,math.floor(limit))
end
local function task(r, key, fn)
    if r.task~=key then fn(); r.task=key; r.taskAt=GetGameTimer() end
end
local function hidden(pos,radius)
    return not IsSphereVisible(pos.x,pos.y,pos.z+1.0,radius or 3.0)
end
local function deploymentPositions(selection,preparationDeadline)
    local ped=PlayerPedId()
    if GetInteriorFromEntity(ped)~=0 then return nil,ProtectText('Go outside before deploying a protection detail.') end
    local origin=GetEntityCoords(ped)
    local camera=GetGameplayCamRot(2)
    local base=math.rad(camera.z+180)
    local used, result={}, {guards={},vehicles={}}
    local deadline=math.min(preparationDeadline or math.huge,GetGameTimer()+Protect.performance.stagingSearchTimeout)
    local queries,batchAt=0,GetGameTimer()
    local expired=false
    local function suitable(pos,minimum,radius)
        if not hidden(pos,radius) or #(pos-origin)<minimum or #(pos-origin)>Protect.spawnMax then return false end
        if math.abs(pos.z-origin.z)>=Protect.stagingHeightRange or IsPositionOccupied(pos.x,pos.y,pos.z,radius,false,true,true,false,false,0,false) then return false end
        for _,previous in ipairs(used) do if #(pos-previous.position)<radius+previous.radius+4 then return false end end
        return true
    end
    local function find(vehicle,index,model)
        local minimum=vehicle and Protect.vehicleSpawnMin or Protect.footSpawnMin
        local radius=2.0
        if vehicle then
            local low,high=GetModelDimensions(joaat(model))
            radius=math.max(math.abs(low.x),math.abs(high.x),math.abs(low.y),math.abs(high.y))+0.75
        end
        for ring=0,math.floor((Protect.spawnMax-minimum-15)/25) do
            for step=0,23 do
                if GetGameTimer()>=deadline then expired=true;return end
                local angle=base+math.rad((step%2==0 and 1 or -1)*math.ceil(step/2)*22+index*9)
                local distance=minimum+15+ring*25
                local guess=origin+vector3(-math.sin(angle)*distance,math.cos(angle)*distance,0)
                local ok,pos,heading
                if vehicle then ok,pos,heading=GetClosestVehicleNodeWithHeading(guess.x,guess.y,guess.z,1,3.0,0)
                else ok,pos=GetSafeCoordForPed(guess.x,guess.y,guess.z,false,14); heading=GetEntityHeading(ped) end
                if ok and suitable(pos,minimum,radius) then
                    used[#used+1]={position=pos,radius=radius}
                    return {x=pos.x,y=pos.y,z=pos.z,h=heading or 0,radius=radius}
                end
                -- Limit work per frame without stretching a large selection into
                -- thousands of frames. All units share the same search deadline.
                queries=queries+1
                if queries>=4 or GetGameTimer()-batchAt>=2 then
                    Wait(0);queries=0;batchAt=GetGameTimer()
                end
            end
        end
    end
    for i=1,selection.count do
        local pos=find(false,i)
        if not pos then return nil,ProtectText(expired and 'staging_search_timeout' or 'No hidden walkable guard staging point was found. Move to an open street and try again.') end
        result.guards[i]=pos
    end
    for i=1,#selection.vehicles do
        local pos=find(true,i,selection.vehicles[i].model)
        if not pos then return nil,ProtectText(expired and 'staging_search_timeout' or 'No hidden, clear road staging point was found for the convoy. Move to a wider road.') end
        result.vehicles[i]=pos
    end
    -- Recheck after the search in case the camera moved while looking for nodes.
    for _,list in pairs(result) do for _,p in ipairs(list) do if not hidden(p,p.radius) then return nil,ProtectText('Staging area entered your view. Keep looking ahead and try again.') end end end
    return result
end
-- Presentation-only telemetry. Existing validation, spawning and AI remain authoritative.
local function uiTelemetry(session)
    local result={active=session~=nil,convoy={},roles={},context={passenger=false,waypoint=false},airAvailable=false}
    local principal=PlayerPedId()
    local car=GetVehiclePedIsIn(principal,false)
    local occupant=car~=0 and GetPedInVehicleSeat(car,-1) or 0
    result.context.passenger=car~=0 and occupant~=principal and (occupant==0 or not IsPedAPlayer(occupant))
    result.context.waypoint=DoesBlipExist(GetFirstBlipInfoId(8))
    local hash=joaat(Protect.airModel)
    result.airAvailable=IsModelInCdimage(hash) and IsModelAVehicle(hash) and GetVehicleClassFromName(hash)==15
    result.airModel=Protect.airModel
    if result.airAvailable then result.airLabel=GetLabelText(GetDisplayNameFromVehicleModel(hash));if result.airLabel=='NULL' then result.airLabel=Protect.airModel end end
    if not session or not uiEligible or IsEntityDead(principal) then result.active=false;return result end
    result.deploying=session.deploying==true;result.mode=session.mode;result.detail=session.detail
    result.airCooldown=math.max(0,((session.uiAirDeadline or GetGameTimer())-GetGameTimer())/1000)
    result.counts={foot=0,crew=0,vehicles=0,air=0,airCrew=0,airPilot=0}
    local function alive(net) local e=resolve(net);return e~=0 and DoesEntityExist(e) and not IsEntityDead(e) end
    for _,net in ipairs(session.guards) do if alive(net) then result.counts.foot=result.counts.foot+1 end end
    for _,v in ipairs(session.vehicles) do if alive(v.net) then result.counts.vehicles=result.counts.vehicles+1 end;for _,net in ipairs(v.crew) do if alive(net) then result.counts.crew=result.counts.crew+1 end end end
    if session.air and alive(session.air.net) then result.counts.air=1;result.counts.airPilot=alive(session.air.crew[1]) and 1 or 0;for _,net in ipairs(session.air.crew) do if alive(net) then result.counts.airCrew=result.counts.airCrew+1 end end end
    local t=session.tactical
    if t then
        result.tactical={state=t.state,formation=t.formation,posture=t.posture,airPosture=t.airPosture,command=t.command,
            baseFormation=t.formation=='adaptive' and (GetInteriorFromEntity(principal)~=0 and 'column' or 'diamond') or t.formation}
        for net,role in pairs(t.roles or {}) do if alive(net) then result.roles[role.role]=(result.roles[role.role] or 0)+1 end end
        if t.extraction then
            local vehicle,driver=resolve(t.extraction.vehicle),resolve(t.extraction.driver)
            result.extraction={model=t.extraction.model,ready=alive(t.extraction.vehicle) and IsVehicleDriveable(vehicle,false) and alive(t.extraction.driver) and GetPedInVehicleSeat(vehicle,-1)==driver,
                distance=vehicle~=0 and math.floor(#(GetEntityCoords(vehicle)-GetEntityCoords(principal))+.5) or nil,
                boarded=vehicle~=0 and car==vehicle}
        end
    end
    result.airActive=session.air~=nil
    local designated=t and t.extraction and resolve(t.extraction.vehicle) or session.detail.driver and resolve(session.detail.driver.vehicle) or car
    if designated~=0 and DoesEntityExist(designated) then
        local model=GetEntityModel(designated)
        result.principalVehicle={label=GetLabelText(GetDisplayNameFromVehicleModel(model)),model=GetDisplayNameFromVehicleModel(model)}
        for _,definition in ipairs(Protect.vehicles) do if joaat(definition.model)==model then result.principalVehicle.label=ProtectText(definition.label);result.principalVehicle.model=definition.model;break end end
        if result.principalVehicle.label=='NULL' then result.principalVehicle.label=result.principalVehicle.model end
    end
    local driver=session.detail.driver and resolve(session.detail.driver.ped) or 0
    local chauffeur=session.detail.driver and resolve(session.detail.driver.vehicle) or 0
    result.driverReady=driver~=0 and chauffeur~=0 and not IsEntityDead(driver) and not IsEntityDead(chauffeur) and IsVehicleDriveable(chauffeur,false) and GetPedInVehicleSeat(chauffeur,-1)==driver
    result.context.chauffeurPassenger=chauffeur~=0 and car==chauffeur and result.context.passenger
    local escorts={}
    for _,entry in ipairs(session.vehicles) do local vehicle=resolve(entry.net);if vehicle~=0 and vehicle~=car and IsVehicleDriveable(vehicle,false) then escorts[#escorts+1]=vehicle end end
    for index,entry in ipairs(session.vehicles) do
        local vehicle=resolve(entry.net);local role='pending'
        if vehicle~=0 and vehicle==car then role='principal'
        else for rank,e in ipairs(escorts) do if e==vehicle then role=rank<=math.ceil(#escorts/2) and 'lead' or 'follow' end end end
        if alive(entry.net) then
            local crew=0;for _,net in ipairs(entry.crew) do if alive(net) then crew=crew+1 end end
            result.convoy[#result.convoy+1]={model=entry.model,order=index,crew=crew,role=role,principal=vehicle~=0 and vehicle==designated}
        end
    end
    return result
end
local function prepareState(state)
    if not state or state.error then return state end
    uiEligible=true
    if state.environment then environment=state.environment end
    state.environment=environment
    state.live=uiTelemetry(ownSession())
    state.unavailableVehicles=0
    if state.tactical and state.tactical.extraction then
        local ex=state.tactical.extraction
        local car,ped=resolve(ex.vehicle),resolve(ex.driver)
        state.tactical.driverReady=car~=0 and ped~=0 and not IsEntityDead(ped) and not IsEntityDead(car) and IsVehicleDriveable(car,false) and GetPedInVehicleSeat(car,-1)==ped
    end
    local available={}
    for _,vehicle in ipairs(state.vehicles or {}) do
        local hash=joaat(vehicle.model)
        if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
            local copy={};for k,v in pairs(vehicle) do copy[k]=v end
            copy.passengerCapacity=math.max(0,GetVehicleModelNumberOfSeats(hash)-vehicle.seats)
            available[#available+1]=copy
        else state.unavailableVehicles=state.unavailableVehicles+1 end
    end
    state.vehicles=available
    local modes={}
    for key,definition in pairs(state.modes or Protect.guards) do
        local models={}
        for _,model in ipairs(definition.models) do
            local hash=joaat(model)
            if IsModelInCdimage(hash) and IsModelValid(hash) and IsModelAPed(hash) then models[#models+1]=model end
        end
        if #models>0 then modes[key]={label=definition.label,concealed=definition.concealed} end
    end
    state.modes=modes
    return state
end
local function showState(state)
    if state and state.error then notice(state.error,'error'); return false end
    if state then prepareState(state);state.maxSpeed=speedLimit(ownSession());SendNUIMessage({action='state',state=state}) end
    return state~=nil
end
RegisterCommand(Protect.commands.menu,function()
    if menuOpen then closeMenu(); return end
    local state=ProtectRPC.await('dios_protect:state',false)
    if not state or state.error then notice(state and state.error or ProtectText('Protection service is unavailable.'),'error'); return end
    menuOpen=true
    SetNuiFocus(true,true)
    state.maxSpeed=speedLimit(ownSession())
    prepareState(state);SendNUIMessage({action='open',state=state,view='protect'})
end,false)
RegisterCommand(Protect.commands.controls,function()
    local state=ProtectRPC.await('dios_protect:state',false)
    if not state or state.error or not state.active then notice(state and state.error or ProtectText('Deploy your protection detail first.'),'error');return end
    state.maxSpeed=speedLimit(ownSession());menuOpen=true;SetNuiFocus(true,true)
    prepareState(state);SendNUIMessage({action='open',state=state,view='control'})
end,false)
local function airPosition()
    local p=GetEntityCoords(PlayerPedId())
    for i=0,11 do
        local a=math.rad(GetGameplayCamRot(2).z+180+i*30)
        local pos=p+vector3(-math.sin(a)*180,math.cos(a)*180,Protect.airHeight)
        if hidden(pos,15) and not IsPositionOccupied(pos.x,pos.y,pos.z,15,false,true,true,false,false,0,false) then return {x=pos.x,y=pos.y,z=pos.z,h=GetEntityHeading(PlayerPedId())} end
    end
end
local function requestAir()
    local hash=joaat(Protect.airModel)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) or GetVehicleClassFromName(hash)~=15 then
        return {error=ProtectText('Helicopter model is unavailable.')}
    end
    local pos=airPosition()
    if not pos then return {error=ProtectText('No hidden aerial staging point. Look ahead and try again.')} end
    return ProtectRPC.await('dios_protect:control',false,'air',{position=pos})
end
nui('control',function(data,cb)
    local session=ownSession()
    if not session then cb({error=ProtectText('Deploy your detail first.')});return end
    local action=data.action
    local response
    if action=='driver' then
        local car=GetVehiclePedIsIn(PlayerPedId(),false)
        if car==0 then notice(ProtectText('Sit in the passenger seat of your vehicle first.'),'error');cb({error=ProtectText('Enter a vehicle as passenger first.')});return end
        if GetPedInVehicleSeat(car,-1)==PlayerPedId() then cb({error=ProtectText('Move to a passenger seat before assigning a chauffeur.')});return end
        local occupant=GetPedInVehicleSeat(car,-1)
        if occupant~=0 and IsPedAPlayer(occupant) then cb({error=ProtectText('The driver seat is occupied by another player.')});return end
        local ped=0
        for _,entry in ipairs(session.vehicles) do if resolve(entry.net)==car then ped=resolve(entry.crew[1]) end end
        if ped~=0 and IsEntityDead(ped) then ped=0 end
        local nearest=math.huge
        if ped==0 then
            local candidates={}
            for _,net in ipairs(session.guards) do candidates[#candidates+1]=net end
            for _,entry in ipairs(session.vehicles) do for i=2,#entry.crew do candidates[#candidates+1]=entry.crew[i] end end
            for _,net in ipairs(candidates) do
                local entity=resolve(net)
                if entity~=0 and not IsEntityDead(entity) then
                    local distance=#(GetEntityCoords(entity)-GetEntityCoords(PlayerPedId()))
                    if distance<nearest then nearest=distance;ped=entity end
                end
            end
        end
        if ped==0 then cb({error=ProtectText('No living guard is available to drive.')});return end
        response=ProtectRPC.await('dios_protect:control',false,'driver',{driver=PedToNet(ped),vehicle=VehToNet(car)})
    elseif action=='air' then
        response=requestAir()
    elseif action=='waypoint' then
        local blip=GetFirstBlipInfoId(8)
        if not DoesBlipExist(blip) then cb({error=ProtectText('Set a waypoint on the map first.')});return end
        local pos=GetBlipInfoIdCoord(blip)
        local ok,node=GetClosestVehicleNode(pos.x,pos.y,pos.z,1,3.0,0)
        if ok then pos=node end
        response=ProtectRPC.await('dios_protect:control',false,'waypoint',{destination={x=pos.x,y=pos.y,z=pos.z}})
    else
        if action=='settings' then data.speed=math.min(tonumber(data.speed) or 60,speedLimit(session)) end
        response=ProtectRPC.await('dios_protect:control',false,action,data)
        if response and not response.error and action=='settings' and data.air=='escort' and not response.airActive then response=requestAir() end
    end
    showState(response);cb(response or {error=ProtectText('Detail control service unavailable.')})
end)
nui('ready',function(_,cb) cb({locale=Protect.locale,translations=ProtectLocalePayload(),fallback=ProtectLocales.en,ui=Protect.ui,defaults={formation=Protect.tactical.formation,airModel=Protect.airModel}}) end)
nui('close',function(_,cb) closeMenu(); cb({ok=true}) end)
nui('refresh',function(_,cb)
    local state=ProtectRPC.await('dios_protect:state',false)
    showState(state); cb(state or {error=ProtectText('Service unavailable.')})
end)
nui('action',function(data,cb)
    local state=ProtectRPC.await('dios_protect:action',false,data.action,data.target)
    showState(state); cb(state or {error=ProtectText('Service unavailable.')})
end)
nui('deploy',function(data,cb)
    if deploying then cb({error=ProtectText('Deployment in progress.')}); return end
    local selection,err=ProtectPolicy.selection(data)
    if not selection then cb({error=err}); return end
    deploying=true
    local started=GetGameTimer()
    local preparationDeadline=started+Protect.performance.deploymentPreparationTimeout
    local function progress(phase)
        SendNUIMessage({action='deploymentProgress',phase=phase})
        if Protect.diagnostics.enabled then print(('[dios_protect] Deployment phase: %s (%d ms; %d guards, %d vehicles)'):format(phase,GetGameTimer()-started,selection.count,#selection.vehicles)) end
    end
    local loaded={}
    local ok,response=pcall(function()
        progress('models')
        -- Preload bounded, known models so unavailable Enhanced assets cannot leave a partial detail.
        local models={}
        local guardModels={}
        for _,model in ipairs(Protect.guards[selection.mode].models) do
            local hash=joaat(model)
            if IsModelInCdimage(hash) and IsModelAPed(hash) then guardModels[#guardModels+1]=model;models[#models+1]=model end
        end
        if #guardModels==0 then return {error=ProtectText('Choose a valid guard detail.')} end
        for _,v in ipairs(selection.vehicles) do
            if not IsModelAVehicle(joaat(v.model)) then return {error=ProtectText('model_unavailable',{model=v.model})} end
            models[#models+1]=v.model
        end
        local seen={}
        for _,model in ipairs(models) do
            local hash=joaat(model)
            if not seen[hash] then
                if GetGameTimer()>=preparationDeadline then return {error=ProtectText('deploy_prepare_timeout')} end
                if not IsModelInCdimage(hash) or not IsModelValid(hash) then return {error=ProtectText('model_unavailable',{model=model})} end
                ProtectRPC.requestModel(hash,math.min(Protect.performance.modelTimeout,preparationDeadline-GetGameTimer()))
                loaded[#loaded+1]=hash
                seen[hash]=true
            end
        end
        progress('positions')
        local positions,reason=deploymentPositions(selection,preparationDeadline)
        if not positions then return {error=reason} end
        positions.guardModels=guardModels
        progress('dispatch')
        local state=ProtectRPC.await('dios_protect:deploy',false,data,positions)
        showState(state)
        if state and not state.error then notice(ProtectText('Protection detail dispatched. Units are approaching.'),'success') end
        return state or {error=ProtectText('Deployment service unavailable.')}
    end)
    for _,hash in ipairs(loaded) do SetModelAsNoLongerNeeded(hash) end
    deploying=false
    if not ok then response={error=ProtectText('Deployment could not be prepared. ')..tostring(response)} end
    cb(response)
end)
local function answerInvitation(accepted,token)
    if not invitation or invitation.token~=token then return end
    invitation=nil
    SendNUIMessage({action='inviteClose',token=token})
    SetNuiFocus(menuOpen,menuOpen)
    TriggerServerEvent('dios_protect:answer',accepted==true,token)
end
nui('inviteAnswer',function(data,cb) answerInvitation(data.accepted,data.token);cb({ok=true}) end)
RegisterNetEvent('dios_protect:invite',function(name,seconds,token)
    if source~=65535 or type(token)~='string' or type(seconds)~='number' then return end
    if invitation then answerInvitation(false,invitation.token) end
    invitation={token=token}
    SendNUIMessage({action='invite',token=token,title=ProtectText('invite_title'),text=ProtectText('invite_body',{name=name,seconds=seconds}),accept=ProtectText('accept'),decline=ProtectText('decline'),remainingMs=math.max(1,math.min(seconds,300))*1000,locale=Protect.locale,translations=ProtectLocalePayload()})
    SetNuiFocus(true,true)
    SetTimeout(math.max(1,math.min(seconds,300))*1000,function() answerInvitation(false,token) end)
end)
RegisterNetEvent('dios_protect:inviteCancel',function(token)
    if source==65535 and invitation and invitation.token==token then answerInvitation(false,token) end
end)
RegisterNetEvent('dios_protect:sync',function(data) sessions=data or {};for _,s in pairs(sessions) do if s.tactical then s.tactical.receivedAt=GetGameTimer() end;s.uiAirDeadline=GetGameTimer()+(s.airCooldown or 0)*1000 end end)
local function uiJobChanged(job)
    local grade=type(job.grade)=='table' and job.grade.level or job.grade or 0
    uiEligible=job.name==Protect.presidentJob and grade>=Protect.access.minimumGrade and (not Protect.access.requireDuty or job.onduty==true)
    if not uiEligible then SendNUIMessage({action='reset'});closeMenu() end
end
RegisterNetEvent('QBCore:Client:OnJobUpdate',uiJobChanged)
RegisterNetEvent('QBCore:Client:OnPlayerUnload',function() uiEligible=false;SendNUIMessage({action='reset'});closeMenu(); runtime={} end)
RegisterNetEvent('esx:setJob',uiJobChanged)
RegisterNetEvent('esx:onPlayerLogout',function() uiEligible=false;SendNUIMessage({action='reset'});closeMenu();runtime={} end)
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then SendNUIMessage({action='reset'});invitation=nil;SendNUIMessage({action='inviteClose'});closeMenu() end end)

local function threatFor(principal,friends)
    local p=GetEntityCoords(principal)
    local principalCar=GetVehiclePedIsIn(principal,false)
    for _,candidate in ipairs(GetGamePool('CPed')) do
        if candidate~=principal and not friends[candidate] and not IsEntityDead(candidate) and #(GetEntityCoords(candidate)-p)<150 then
            if HasEntityBeenDamagedByEntity(principal,candidate,true)
                or (principalCar~=0 and HasEntityBeenDamagedByEntity(principalCar,candidate,true))
                or (IsPedInCombat(candidate,principal) and HasEntityClearLosToEntity(candidate,principal,17)) then return candidate end
        end
    end
end
local function escortSeat(ped,principal,session)
    local options={GetVehiclePedIsIn(principal,false)}
    local reserved={}
    -- Front passenger is reserved for the President; crew use the rear seats.
    for _,v in ipairs(session.vehicles) do reserved[resolve(v.net)]=#v.crew end
    for _,v in ipairs(session.vehicles) do options[#options+1]=resolve(v.net) end
    for _,car in ipairs(options) do
        if car~=0 and DoesEntityExist(car) and #(GetEntityCoords(car)-GetEntityCoords(ped))<35 then
            local max=GetVehicleMaxNumberOfPassengers(car)
            for seat=0,max-1 do
                if seat>=(reserved[car] or 0) and IsVehicleSeatFree(car,seat,false) then return car,seat end
            end
        end
    end
end
local motion=ProtectMotion.new({resolve=resolve,owned=owned,context=context,configure=configurePed,task=task,arm=armGuard})
local tactics=ProtectClientTactical.new({resolve=resolve,owned=owned,context=context,task=task,arm=armGuard,notice=notice,motion=motion,
    waypoint=function()
        local pos=GetBlipInfoIdCoord(GetFirstBlipInfoId(8))
        local ok,node=GetClosestVehicleNode(pos.x,pos.y,pos.z,1,3.0,0);if ok then pos=node end
        return ProtectRPC.await('dios_protect:control',false,'waypoint',{destination={x=pos.x,y=pos.y,z=pos.z}})
    end})
AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then tactics.cleanup({}) end end)
RegisterNetEvent('dios_protect:tacticalSync',function(owner,id,intent)
    local session=sessions[owner] or sessions[tostring(owner)]
    if not session or session.id~=id then return end
    intent.receivedAt=GetGameTimer();session.tactical=intent
    if intent.extraction then local car,ped=resolve(intent.extraction.vehicle),resolve(intent.extraction.driver);intent.driverReady=car~=0 and ped~=0 and GetPedInVehicleSeat(car,-1)==ped end
    if tonumber(owner)==GetPlayerServerId(PlayerId()) then SendNUIMessage({action='live',live=uiTelemetry(session)}) end
end)
local function stage(session)
    local deadline=GetGameTimer()+Protect.performance.stagingTimeout
    while GetGameTimer()<deadline do
        local current=ownSession()
        if current and (current.id~=session.id or not current.deploying) then return {error=ProtectText('Protection deployment was interrupted')} end
        local complete=true
        local principal=PlayerPedId()
        for _,net in ipairs(session.guards) do
            local ped=resolve(net)
            if ped==0 then complete=false elseif owned(ped) then configurePed(ped,principal,session.id,session.mode) end
        end
        for _,entry in ipairs(session.vehicles) do
            if not motion.stage(entry,principal,session) then complete=false end
            for _,net in ipairs(entry.crew) do if resolve(net)==0 then complete=false end end
        end
        if complete then return true end
        Wait(100)
    end
    local failures={}
    for index,net in ipairs(session.guards) do if resolve(net)==0 then failures[#failures+1]=ProtectText('Foot guard ')..index..': not streamed' end end
    for _,entry in ipairs(session.vehicles) do
        local car,ped=resolve(entry.net),resolve(entry.crew[1])
        local reason=car==0 and 'vehicle not streamed' or ped==0 and 'driver not streamed'
            or context(car,session.id).blocked or context(ped,session.id).blocked
            or (GetPedInVehicleSeat(car,-1)~=ped and 'driver not seated') or 'passenger boarding incomplete'
        if car==0 or ped==0 or not Entity(car).state.diosGroundReady or GetPedInVehicleSeat(car,-1)~=ped then
            failures[#failures+1]=entry.model..': '..reason
        end
        for index=2,#entry.crew do
            local member=resolve(entry.crew[index])
            if member==0 or GetVehiclePedIsIn(member,false)~=car then
                failures[#failures+1]=entry.model..' crew '..index..': '..(member==0 and 'not streamed' or context(member,session.id).blocked or 'boarding incomplete')
            end
        end
    end
    local reason=table.concat(failures,'; ')
    print('[Dios detail] Deployment readiness timed out: '..reason)
    return {error=reason~='' and reason or ProtectText('Crew boarding did not complete in time.')}
end
RegisterNetEvent('dios_protect:stageRequest',function(session,token)
    if type(session)~='table' or tonumber(session.owner)~=GetPlayerServerId(PlayerId()) or type(token)~='string' then return end
    CreateThread(function()
        SendNUIMessage({action='deploymentProgress',phase='crew'})
        local ok,result=pcall(stage,session)
        TriggerServerEvent('dios_protect:stageResult',session.id,token,ok and result or false)
    end)
end)
local function guard(ped,principal,index,session,threat)
    if not owned(ped) or IsEntityDead(ped) then return end
    if motion.assigned(ped,principal,session) then return end
    local r=configurePed(ped,principal,session.id,session.mode)
    if tactics.guard(ped,principal,session) then return end
    if Protect.tactical.enabled and session.tactical then threat=nil;r.combatUntil=nil end
    if threat and DoesEntityExist(threat) and not IsEntityDead(threat) then
        r.combatUntil=GetGameTimer()+5000
        armGuard(ped)
        task(r,'combat:'..threat,function() ClearPedTasks(ped);armGuard(ped);TaskCombatPed(ped,threat,0,16) end)
        return
    end
    if r.combatUntil and r.combatUntil>GetGameTimer() then armGuard(ped);return end
    if r.concealed and not IsPedInCombat(ped,0) then SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true) end
    if session.detail.order=='hold' then
        if IsPedInAnyVehicle(ped,false) then return end
        if not r.holdPoint then r.holdPoint=GetEntityCoords(ped) end
        local point=r.holdPoint
        if #(GetEntityCoords(ped)-point)>2.0 then
            task(r,'return-to-post',function() TaskGoStraightToCoord(ped,point.x,point.y,point.z,2.0,-1,GetEntityHeading(ped),0.5) end)
        else task(r,'hold-post',function() ClearPedTasks(ped);TaskStartScenarioInPlace(ped,'WORLD_HUMAN_GUARD_STAND',0,true) end) end
        return
    end
    r.holdPoint=nil
    local principalCar=GetVehiclePedIsIn(principal,false)
    if r.task and (r.task:find('board:',1,true) or r.task=='driver-board') and GetGameTimer()-(r.taskAt or 0)>16000 then r.task=nil end
    if principalCar~=0 then
        local home,seat=motion.home(ped,session)
        if home then
            if seat==-1 then
                for index,entry in ipairs(session.vehicles) do if entry==home then motion.convoy(entry,principal,index,session);break end end
            else motion.crew(ped,resolve(home.net),seat,principal,session) end
            return
        end
        if IsPedInAnyVehicle(ped,false) then return end
        local car,seat=escortSeat(ped,principal,session)
        if car then task(r,'board:'..car..':'..seat,function() TaskEnterVehicle(ped,car,15000,seat,2.0,1,0) end); return end
    elseif IsPedInAnyVehicle(ped,false) then
        task(r,'exit',function() TaskLeaveVehicle(ped,GetVehiclePedIsIn(ped,false),0) end); return
    end
    local side=index%2==0 and 1 or -1
    local x,y=side*(1.8+math.floor((index-1)/2)*0.6),-1.8-math.floor((index-1)/2)*1.7
    tactics.follow(ped,principal,session,'follow:'..index,x,y)
end
local function convoy(entry,principal,index,session,threat)
    local car=resolve(entry.net)
    if car==0 then return end
    motion.convoy(entry,principal,index,session)
    local target=GetVehiclePedIsIn(principal,false)
    for crewIndex=2,#entry.crew do
        local ped=resolve(entry.crew[crewIndex])
        if owned(ped) and not IsEntityDead(ped) then
            if motion.assigned(ped,principal,session) then
                -- An appointed chauffeur is excluded from passenger AI.
            elseif threat or (target==0 and GetEntitySpeed(car)<0.7 and #(GetEntityCoords(car)-GetEntityCoords(principal))<45) then
                guard(ped,principal,Protect.maxGuards+index,session,threat)
            else motion.crew(ped,car,crewIndex-1,principal,session)
            end
        end
    end
end
local airPending,nextAirRequest=false,0
RegisterCommand(Protect.commands.diagnostics,function()
    print(('[Dios environment] GTA %s | client build %s | framework %s | keys %s'):format(environment.edition or 'Unknown',GetGameBuildNumber(),environment.framework or 'unknown',environment.keys or 'unknown'))
    local session=ownSession()
    if not session then notice(ProtectText('No active protection detail.'),'error');return end
    if session.tactical then
        local t=session.tactical
        print(('[Dios tactical] state=%s formation=%s posture=%s command=%s extraction=%s'):format(t.state,t.formation,t.posture,t.command,t.extraction and t.extraction.vehicle or 'none'))
        local principal=PlayerPedId();local origin=GetEntityCoords(principal)
        print(('[Dios tactical] President net=%s valid=%s bucket=%s threats=%s'):format(PedToNet(principal),tostring(DoesEntityExist(principal)),session.bucket,ProtectTactical.summary(t,(t.clock or GetGameTimer())+GetGameTimer()-(t.receivedAt or GetGameTimer())).count))
        for net,r in pairs(t.threats) do
            local entity=resolve(net);local distance=entity~=0 and #(GetEntityCoords(entity)-origin) or -1
            local bearing=math.deg(math.atan((r.y or origin.y)-origin.y,(r.x or origin.x)-origin.x))
            print(('[Dios tactical] threat=%s score=%.1f distance=%.1f bearing=%.1f LOS=%s confirmedUntil=%s'):format(net,r.score,distance,bearing,tostring(entity~=0 and HasEntityClearLosToEntity(principal,entity,17)),r.confirmedUntil or 0))
        end
        for net,role in pairs(t.roles) do local ped=resolve(tonumber(net));print(('[Dios tactical] guard=%s role=%s slot=%s target=%s owner=%s task=%s'):format(net,role.role,role.slot or '-',role.target or '-',tostring(owned(ped)),ped~=0 and context(ped,session.id).task or 'not streamed')) end
        for _,net in ipairs(session.guards) do
            local ped=resolve(net)
            if ped~=0 then
                local r=context(ped,session.id)
                if r.followNominalX then
                    local slot=GetOffsetFromEntityInWorldCoords(principal,r.followNominalX,r.followNominalY,0)
                    print(('[Dios formation] guard=%s slotError=%.2fm vipSpeed=%.2f guardSpeed=%.2f taskSpeed=%s offset=%.2f,%.2f'):format(net,#(GetEntityCoords(ped)-slot),GetEntitySpeed(principal),GetEntitySpeed(ped),r.followSpeed or '-',r.offsetX or 0,r.offsetY or 0))
                end
            end
        end
        if t.extraction then local car,ped=resolve(t.extraction.vehicle),resolve(t.extraction.driver);print(('[Dios tactical] extraction driver=%s ready=%s'):format(t.extraction.driver,tostring(car~=0 and ped~=0 and GetPedInVehicleSeat(car,-1)==ped))) end
    end
    print(('[Dios detail] speed cap=%s km/h; requested=%s; gap=%sm; air=%s'):format(speedLimit(session),session.detail.speed,session.detail.gap,session.detail.air))
    local roles,center=motion.formation(session,PlayerPedId())
    for _,entry in ipairs(session.vehicles) do
        local car,ped=resolve(entry.net),resolve(entry.crew[1])
        local role=car~=0 and car==center and 'President / center' or roles[car] and (roles[car].front and 'lead escort' or 'rear escort') or 'staging'
        print(('[Dios detail] %s role=%s'):format(entry.model,role))
        if car~=0 and ped~=0 then
            print(('[Dios detail] %s net=%s driverNet=%s groundReady=%s carControl=%s driverControl=%s seated=%s engine=%s speed=%.1f task=%s blocked=%s'):format(entry.model,entry.net,entry.crew[1],tostring(Entity(car).state.diosGroundReady),tostring(owned(car)),tostring(owned(ped)),tostring(GetPedInVehicleSeat(car,-1)==ped),tostring(GetIsVehicleEngineRunning(car)),GetEntitySpeed(car)*3.6,context(ped,session.id).task or 'pending',context(ped,session.id).blocked or 'none'))
        else print('[Dios detail] '..entry.model..' not yet streamed') end
    end
end,false)
CreateThread(function()
    Wait(1000); TriggerServerEvent('dios_protect:requestSync')
    while true do
        local active=false
        for _,session in pairs(sessions) do
            local owner=GetPlayerFromServerId(tonumber(session.owner))
            local principal=owner~=-1 and GetPlayerPed(owner) or 0
            if principal~=0 and DoesEntityExist(principal) and not IsEntityDead(principal) then
                active=true
                local friends={[principal]=true}
                -- Human Secret Service agents are never treated as hostile NPC targets.
                for _,source in ipairs(session.agents or {}) do
                    local peer=GetPlayerFromServerId(tonumber(source))
                    if peer~=-1 then friends[GetPlayerPed(peer)]=true end
                end
                for _,net in ipairs(session.guards) do friends[resolve(net)]=true end
                for _,v in ipairs(session.vehicles) do for _,net in ipairs(v.crew) do friends[resolve(net)]=true end end
                if session.air then for _,net in ipairs(session.air.crew) do friends[resolve(net)]=true end end
                local threat
                if Protect.tactical.enabled then threat=tactics.tick(session,principal,friends) else threat=threatFor(principal,friends) end
                tactics.extraction(session,principal)
                session=tactics.effective(session)
                -- Only current network owners issue tasks. Forget transient task caches on loss.
                for entity,record in pairs(runtime) do if record.token==session.id and not owned(entity) then record.task=nil;record.initialized=nil end end
                if session.deploying then
                    for _,entry in ipairs(session.vehicles) do motion.stage(entry,principal,session) end
                else
                    for index,net in ipairs(session.guards) do guard(resolve(net),principal,index,session,threat) end
                    for index,entry in ipairs(session.vehicles) do convoy(entry,principal,index,session,threat) end
                end
                motion.air(session,principal,threat)
                if tonumber(session.owner)==GetPlayerServerId(PlayerId()) and threat and session.detail.air=='auto' and not session.air and not airPending and GetGameTimer()>nextAirRequest then
                    airPending=true;nextAirRequest=GetGameTimer()+Protect.airCooldown*1000
                    CreateThread(function()
                        local ok,result=pcall(requestAir)
                        airPending=false
                        if ok and result and not result.error then notice(ProtectText('Air support dispatched to cover your detail.'),'success')
                        else notice(ok and result and result.error or ProtectText('Air support could not be dispatched.'),'error') end
                    end)
                end
                -- All guards see the damage state before it is cleared.
                if threat then
                    ClearEntityLastDamageEntity(principal)
                    local car=GetVehiclePedIsIn(principal,false)
                    if car~=0 then ClearEntityLastDamageEntity(car) end
                end
            end
        end
        tactics.cleanup(sessions)
        for entity in pairs(runtime) do if not DoesEntityExist(entity) then runtime[entity]=nil end end
        Wait(active and Protect.performance.aiTick or 1500)
    end
end)

-- Foot movement is supervised separately from convoy, scanning and report timers.
-- Only each ped's network owner issues tasks; native following handles motion
-- between these checks without sending player keypresses over the network.
CreateThread(function()
    while true do
        local active=false
        for _,session in pairs(sessions) do
            local owner=GetPlayerFromServerId(tonumber(session.owner))
            local principal=owner~=-1 and GetPlayerPed(owner) or 0
            if not session.deploying and principal~=0 and DoesEntityExist(principal) and not IsEntityDead(principal)
                and GetVehiclePedIsIn(principal,false)==0 and session.detail.order~='hold' then
                for index,net in ipairs(session.guards) do
                    local ped=resolve(net)
                    if ped~=0 and not IsEntityDead(ped) and not IsPedInAnyVehicle(ped,false) then
                        local role=session.tactical and (session.tactical.roles[net] or session.tactical.roles[tostring(net)])
                        if not role or role.role~='driver' then
                            active=true
                            if owned(ped) then guard(ped,principal,index,tactics.effective(session),nil)
                            else
                                local r=context(ped,session.id)
                                r.task=nil;r.followKey=nil;r.followSampleAt=nil
                            end
                        end
                    end
                end
            end
        end
        Wait(active and Protect.performance.formationTick or 500)
    end
end)

-- No extra server polling for the live HUD. Summarize the owner's existing scoped snapshot.
CreateThread(function()
    local last
    while true do
        local session=ownSession()
        local live=uiTelemetry(session)
        local payload=json.encode(live)
        if payload~=last then SendNUIMessage({action='live',live=live});last=payload end
        if menuOpen then SendNUIMessage({action='context',context=live.context,maxSpeed=speedLimit(session)}) end
        Wait(1000)
    end
end)
