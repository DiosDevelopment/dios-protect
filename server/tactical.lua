-- All management authorization stays in server/main.lua; this adapter validates tactical telemetry.
ProtectServerTactical={}
function ProtectServerTactical.new(api)
    local rates={}
    local function entity(net,session,kind)
        net=ProtectPolicy.networkId(net)
        local e=net and NetworkGetEntityFromNetworkId(net) or 0
        if e==0 or not DoesEntityExist(e) or GetEntityType(e)~=kind or GetEntityRoutingBucket(e)~=session.bucket then return nil end
        return e,net
    end
    local function friendly(e,session)
        if e==GetPlayerPed(session.owner) or api.protected(e) then return true end
        for _,id in ipairs(session.agents or {}) do if GetPlayerPed(id)==e then return true end end
        for _,id in ipairs(GetPlayers()) do
            id=tonumber(id)
            local p=api.player(id)
            if GetPlayerPed(id)==e and p and Protect.tactical.trustedJobs[p.PlayerData.job.name] then return true end
        end
        return false
    end
    local function live(net,session)
        local e=entity(net,session,1)
        return e and api.protected(e) and GetEntityHealth(e)>0
    end
    local function refresh(session,now)
        local intent=session.tactical
        intent.clock=now
        local liveGuards={}
        for _,net in ipairs(session.guards) do if live(net,session) then liveGuards[#liveGuards+1]=net end end
        for id,record in pairs(intent.threats) do
            local e=entity(id,session,1)
            if not e or GetEntityHealth(e)<=0 or friendly(e,session) or (record.entity and record.entity~=e)
                or (record.model and record.model~=GetEntityModel(e)) then intent.threats[id]=nil end
        end
        ProtectTactical.transition(intent,now,GetEntityHealth(GetPlayerPed(session.owner)))
        intent.airPosture=not session.air and 'off' or (intent.state=='NORMAL' or intent.state=='RECOVERY')
            and 'escort' or intent.state=='SUSPICIOUS' and 'observe' or intent.state=='EXTRACTION' and 'extraction' or 'cover'
        if intent.extraction then
            local car=entity(intent.extraction.vehicle,session,2)
            local driver=entity(intent.extraction.driver,session,1)
            if not car or not driver or GetEntityHealth(car)<=0 or GetEntityHealth(driver)<=0 then
                intent.extraction=nil;session.detail.driver=nil;session.detail.destination=nil
            end
        end
        if intent.state=='RECOVERY' or intent.state=='NORMAL' then
            if intent.extraction then
                if session.detail.destination then intent.restoringDriver=true
                else session.detail.driver=intent.previousDriver;intent.previousDriver=nil end
            end
            intent.extraction=nil
            if intent.restoringDriver and not session.detail.destination then
                session.detail.driver=intent.previousDriver;intent.previousDriver=nil;intent.restoringDriver=nil
            end
        end
        ProtectTactical.roles(intent,liveGuards,session.detail.driver and session.detail.driver.ped,now)
        for _,entry in ipairs(session.vehicles) do
            for i,net in ipairs(entry.crew) do if live(net,session) and not intent.roles[net] then
                local relieved=i==1 and session.detail.driver and session.detail.driver.vehicle==entry.net and session.detail.driver.ped~=net
                intent.roles[net]={role=i==1 and not relieved and 'driver' or 'vehiclecrew',vehicle=entry.net,seat=relieved and 0 or i-1}
            end end
        end
        if session.air then for i,net in ipairs(session.air.crew) do if live(net,session) then
            intent.roles[net]={role=i==1 and 'pilot' or 'airgunner',vehicle=session.air.net}
        end end end
    end
    local result={refresh=refresh}
    function result.maintenance(session)
        if not Protect.tactical.enabled or session.deploying then return end
        local now=GetGameTimer()
        ProtectTactical.observe(session.tactical,{},now)
        refresh(session,now)
        api.emit(session)
    end
    function result.report(source,data)
        local session=api.session(source)
        if not Protect.tactical.enabled or not session or session.deploying or not api.authorized(source,session)
            or type(data)~='table' or data.session~=session.id or type(data.observations)~='table' then return end
        local now=GetGameTimer()
        if now<(rates[source] or 0) then return end
        rates[source]=now+Protect.tactical.reportInterval*.8
        local observations,seen={},{}
        local principal=GetPlayerPed(source)
        for i,o in ipairs(data.observations) do
            if i>Protect.tactical.maxThreats then break end
            if type(o)=='table' then
                local e,id=entity(o.id,session,1)
                if e and not seen[id] and not friendly(e,session) and GetEntityHealth(e)>0
                    and #(GetEntityCoords(e)-GetEntityCoords(principal))<=Protect.tactical.attackRadius then
                    seen[id]=true
                    local p=GetEntityCoords(e)
                    local old=session.tactical.threats[id]
                    if old and (old.entity~=e or old.model~=GetEntityModel(e)) then session.tactical.threats[id]=nil end
                    observations[#observations+1]={id=id,x=p.x,y=p.y,distance=#(p-GetEntityCoords(principal)),damage=o.damage==true,combat=o.combat==true,
                        aim=o.aim==true,approach=o.approach==true,armed=o.armed==true,facing=o.facing==true,entity=e,model=GetEntityModel(e)}
                end
            end
        end
        -- OneSync's last damage source catches attackers outside the rotating client sample.
        session.tacticalHealth=session.tacticalHealth or {}
        local victims={principal}
        for _,net in ipairs(session.guards) do local e=entity(net,session,1);if e then victims[#victims+1]=e end end
        for _,entry in ipairs(session.vehicles) do for _,net in ipairs(entry.crew) do local e=entity(net,session,1);if e then victims[#victims+1]=e end end end
        for _,victim in ipairs(victims) do
            local health=GetEntityHealth(victim)
            local previous=session.tacticalHealth[victim]
            session.tacticalHealth[victim]=health
            if (not previous or health<previous) and GetPedSourceOfDamage then
                local attacker=GetPedSourceOfDamage(victim)
                if attacker and attacker~=0 and not friendly(attacker,session) and GetEntityType(attacker)==1 and GetEntityRoutingBucket(attacker)==session.bucket then
                    local net=NetworkGetNetworkIdFromEntity(attacker)
                    if ProtectPolicy.networkId(net) and #(GetEntityCoords(attacker)-GetEntityCoords(principal))<=Protect.tactical.attackRadius then
                        local p=GetEntityCoords(attacker);observations[#observations+1]={id=net,x=p.x,y=p.y,damage=true,entity=attacker,model=GetEntityModel(attacker)}
                    end
                end
            end
        end
        local validVictims={};for _,victim in ipairs(victims) do validVictims[victim]=true end
        for victim in pairs(session.tacticalHealth) do if not validVictims[victim] then session.tacticalHealth[victim]=nil end end
        ProtectTactical.observe(session.tactical,observations,now)
        for _,o in ipairs(observations) do local record=session.tactical.threats[o.id];if record then record.entity,record.model=o.entity,o.model end end
        refresh(session,now)
        -- Narrow intent packet; deployment snapshots are not rebroadcast on every sensor tick.
        api.emit(session)
    end
    function result.control(session,data)
        if not Protect.tactical.enabled then return false end
        local t=session.tactical
        if data.formation==nil and data.posture==nil and data.command==nil then return false end
        if data.formation~=nil and (type(data.formation)~='string' or not ProtectTactical.formations[data.formation]) then return false end
        if data.posture~=nil and (type(data.posture)~='string' or not ProtectTactical.postures[data.posture]) then return false end
        local command=data.command
        local commands={regroup=true,hold=true,resume=true,prepare=true,cancel=true,vehicles=true,recall=true,evacuate=true}
        if command and (type(command)~='string' or not commands[command]) then return false end
        if data.formation then t.formation=data.formation end
        if data.posture then t.posture=data.posture end
        if command=='prepare' or command=='evacuate' then t.manualExtraction=true;t.routePaused=nil
        elseif command=='cancel' then t.manualExtraction=nil;t.posture='normal';if t.extraction then session.detail.driver=t.previousDriver;session.detail.destination=nil end;t.extraction=nil;t.previousDriver=nil;t.contactSince=nil;t.lastDanger=0;t.state='RECOVERY';t.changedAt=GetGameTimer();t.suppressedUntil=GetGameTimer()+Protect.tactical.clearPeriod
        elseif command=='hold' then t.command='hold';session.detail.order='hold'
        elseif command then t.command=command;t.commandUntil=GetGameTimer()+Protect.tactical.clearPeriod;session.detail.order='follow' end
        t.revision=t.revision+1;refresh(session,GetGameTimer());return true
    end
    function result.extraction(source,data)
        local session=api.session(source)
        if not session or not api.authorized(source,session) or type(data)~='table' or data.session~=session.id
            or session.tactical.state~='EXTRACTION' then return end
        if session.tactical.extraction then return end -- Idempotent; preserve the readiness deadline.
        local now=GetGameTimer()
        if now<(session.nextExtraction or 0) then return end
        session.nextExtraction=now+1000
        if session.tactical.failedVehicle==data.vehicle and now<(session.tactical.failedUntil or 0) then return end
        local car,carNet=entity(data.vehicle,session,2)
        local ped,pedNet=entity(data.driver,session,1)
        if not car or not ped or not live(pedNet,session) or GetEntityHealth(car)<=0 or GetEntityModel(car)==joaat('rhino')
            or (GetVehicleType(car)~='automobile' and GetVehicleType(car)~='bike')
            or #(GetEntityCoords(car)-GetEntityCoords(GetPlayerPed(source)))>Protect.tactical.extractionRadius then return end
        local found,driver,model=false,false,'assigned_vehicle'
        if session.detail.driver and session.detail.driver.vehicle==carNet and session.detail.driver.ped==pedNet then found,driver=true,true end
        for _,entry in ipairs(session.vehicles) do
            if entry.net==carNet and entry.model~='rhino' and api.protected(car) then
                found=true
                model=entry.model
                if entry.crew[1]==pedNet then driver=true end
                local original=entity(entry.crew[1],session,1)
                if Protect.tactical.replaceDeadDriver and (not original or GetEntityHealth(original)<=0) then
                    for _,net in ipairs(session.guards) do if net==pedNet then
                        local role=session.tactical.roles[net]
                        if role and (role.role=='flank' or role.role=='engagement') then driver=true end
                    end end
                    for i=2,#entry.crew do if entry.crew[i]==pedNet then driver=true end end
                end
            end
        end
        if not found or not driver then return end
        if not session.tactical.extraction then session.tactical.previousDriver=session.detail.driver end
        session.tactical.extraction={vehicle=carNet,driver=pedNet,model=model,requestedAt=GetGameTimer()}
        session.detail.driver={vehicle=carNet,ped=pedNet}
        refresh(session,GetGameTimer());api.publish()
    end
    function result.extractionFailed(source,data)
        local s=api.session(source)
        if not s or not api.authorized(source,s) or type(data)~='table' or data.session~=s.id then return end
        local ex=s.tactical.extraction
        if not ex or ex.vehicle~=data.vehicle or GetGameTimer()-ex.requestedAt<Protect.tactical.driverReadinessTimeout then return end
        s.tactical.failedVehicle=ex.vehicle;s.tactical.failedUntil=GetGameTimer()+Protect.tactical.clearPeriod
        s.tactical.extraction=nil;s.detail.driver=s.tactical.previousDriver;s.detail.destination=nil
        api.publish()
    end
    function result.cleanup(source) rates[source]=nil end
    return result
end
