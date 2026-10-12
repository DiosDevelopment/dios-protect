ProtectClientTactical={}
function ProtectClientTactical.new(api)
    local caches={}
    local c=Protect.tactical
    local function cache(session)
        local r=caches[session.id]
        if not r then r={nextScan=0,nextReport=0,nextExtraction=0,cursor=1,observations={},pending={}};caches[session.id]=r end
        return r
    end
    local function confirmed(session,now)
        local t=session.tactical
        if not t then return nil end
        now=(t.clock or now)+GetGameTimer()-(t.receivedAt or GetGameTimer())
        local s=ProtectTactical.summary(t,now)
        local r=s.primary and (t.threats[s.primary] or t.threats[tostring(s.primary)])
        local ped=r and (r.confirmedUntil or 0)>now and api.resolve(s.primary) or 0
        return ped~=0 and not IsEntityDead(ped) and ped or nil
    end
    local function scan(session,principal,friends)
        local r,now=cache(session),GetGameTimer()
        if now<r.nextScan then return r.observations end
        r.nextScan=now+c.scanInterval
        local origin=GetEntityCoords(principal)
        local pool=GetGamePool('CPed')
        local observations={}
        local victims={principal}
        local car=GetVehiclePedIsIn(principal,false);if car~=0 then victims[#victims+1]=car end
        for _,net in ipairs(session.guards) do local e=api.resolve(net);if e~=0 then victims[#victims+1]=e end end
        for _,entry in ipairs(session.vehicles) do for _,net in ipairs(entry.crew) do local e=api.resolve(net);if e~=0 then victims[#victims+1]=e end end end
        local visited={}
        local function assess(ped)
            if ped==0 or visited[ped] or friends[ped] or not DoesEntityExist(ped) or IsEntityDead(ped) or not NetworkGetEntityIsNetworked(ped) then return end
            visited[ped]=true
            local p=GetEntityCoords(ped);local distance=#(p-origin)
            if distance>c.attackRadius then return end
            local damage=false
            for _,victim in ipairs(victims) do if HasEntityBeenDamagedByEntity(victim,ped,true) then damage=true;break end end
            local los=HasEntityClearLosToEntity(ped,principal,17)
            local combat=IsPedInCombat(ped,principal) and los
            local player=IsPedAPlayer(ped) and NetworkGetPlayerIndexFromPed(ped) or -1
            local aim=player~=-1 and distance<c.awarenessRadius and los and IsPlayerFreeAimingAtEntity(player,principal)
            local armed=distance<c.awarenessRadius and IsPedArmed(ped,4) and los
            local facing=armed and IsPedFacingPed(ped,principal,25)
            local velocity=GetEntityVelocity(ped);local toward=origin-p
            local approaching=armed and distance<c.radii.observation and distance>1 and GetEntitySpeed(ped)>2.5
                and (velocity.x*toward.x+velocity.y*toward.y)/distance>1.5
            local vehicle=GetVehiclePedIsIn(ped,false)
            if vehicle~=0 and GetPedInVehicleSeat(vehicle,-1)==ped and distance<30 and distance>1 then
                local velocity=GetEntityVelocity(vehicle);local toward=origin-p
                approaching=GetEntitySpeed(vehicle)>c.vehicleApproachSpeed and (velocity.x*toward.x+velocity.y*toward.y)/distance>c.vehicleApproachSpeed*.7
            end
            if damage or combat or aim or armed or approaching then
                observations[#observations+1]={id=PedToNet(ped),damage=damage,combat=combat,aim=aim,armed=armed,facing=facing,approach=approaching}
            end
        end
        -- Known attackers are refreshed first, then rotate through a bounded ambient sample.
        for net in pairs(session.tactical and session.tactical.threats or {}) do assess(api.resolve(tonumber(net))) end
        -- Damage from unsampled actors is corroborated by OneSync on the server.
        for i=1,math.min(#pool,c.maxScanPeds) do assess(pool[(r.cursor+i-2)%#pool+1]) end
        r.cursor=#pool>0 and (r.cursor+c.maxScanPeds-1)%#pool+1 or 1
        table.sort(observations,function(a,b) local x=a.damage and 4 or a.combat and 3 or a.aim and 2 or 1;local y=b.damage and 4 or b.combat and 3 or b.aim and 2 or 1;return x==y and a.id<b.id or x>y end)
        while #observations>c.maxThreats do table.remove(observations) end
        r.observations=observations
        -- Keep one-shot damage/combat until the next report, even when reporting is slower than scanning.
        for _,o in pairs(r.pending) do o.aim=false;o.armed=false;o.facing=false;o.approach=false end
        for _,o in ipairs(observations) do
            local old=r.pending[o.id]
            if old then o.damage=o.damage or old.damage;o.combat=o.combat or old.combat end
            r.pending[o.id]=o
        end
        local queued={};for _,o in pairs(r.pending) do queued[#queued+1]=o end
        table.sort(queued,function(a,b) local x=a.damage and 4 or a.combat and 3 or a.aim and 2 or 1;local y=b.damage and 4 or b.combat and 3 or b.aim and 2 or 1;return x==y and a.id<b.id or x>y end)
        r.pending={};for i=1,math.min(#queued,c.maxThreats) do r.pending[queued[i].id]=queued[i] end
        -- Clear only after every candidate has sampled every victim.
        for _,victim in ipairs(victims) do ClearEntityLastDamageEntity(victim) end
        return observations
    end
    local result={}
    local followTask=joaat('SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY')
    function result.follow(ped,principal,session,key,x,y)
        local r=api.context(ped,session.id)
        if not api.owned(ped) then r.task=nil;r.followKey=nil;r.followHeading=nil;r.followSampleAt=nil;return false end
        local now=GetGameTimer()
        local point=GetOffsetFromEntityInWorldCoords(principal,x,y,0)
        local distance=#(GetEntityCoords(ped)-point)
        local speed=GetEntitySpeed(principal)
        local velocity=GetEntityVelocity(principal)
        local heading=GetEntityHeading(principal)
        local angular=0
        if r.followSampleAt==now then angular=r.followAngular or 0
        elseif r.followSampleAt and now>r.followSampleAt and now-r.followSampleAt<=250 then
            local delta=math.rad(heading-r.followHeading)
            angular=math.max(-2.5,math.min(2.5,math.atan(math.sin(delta),math.cos(delta))/((now-r.followSampleAt)/1000)))
        end
        r.followSampleAt,r.followHeading=now,heading
        r.followAngular=angular
        r.followNominalX,r.followNominalY=x,y
        local moving=speed>.15 or math.abs(angular)>.1
        local ox,oy=x,y
        if moving then ox,oy=ProtectTactical.pursuit(x,y,heading,velocity.x,velocity.y,angular,c.formationLookAhead) end
        -- Hysteresis prevents repeatedly replacing the task at the catch-up boundary.
        local sprint=speed>3 or distance>8 or r.followSpeed==4.5 and (speed>2.6 or distance>4)
        local movement=sprint and 4.5 or 2.5
        -- A guard outside its moving slot must outrun it, rather than matching
        -- the VIP's speed and preserving the same positional error indefinitely.
        if moving then movement=math.max(movement,math.min(4.5,speed+distance*1.2+.4)) end
        movement=math.floor(movement*4+.5)/4
        local followKey=key..':'..principal..':'..movement
        local stopping=moving and .1 or math.min(c.movementTolerance,c.spacing*.2)
        if r.task==followKey then
            if not r.offsetX or math.abs(ox-r.offsetX)+math.abs(oy-r.offsetY)>.15 or r.followStopping~=stopping then r.task=nil end
            if now>=(r.nextFollowCheck or 0) then
                r.nextFollowCheck=now+500
                local status=GetScriptTaskStatus(ped,followTask)
                if status==3 or status==7 then r.task=nil end
            end
            if distance<math.min(c.movementTolerance,c.spacing*.2)+.5 or GetEntitySpeed(ped)>.2 then
                r.followProgressAt=now
            elseif now-(r.followProgressAt or now)>c.taskRefresh then
                -- Retry normal navigation if a task was interrupted or stopped progressing.
                r.task=nil;r.followProgressAt=now
            end
        end
        -- Retarget a healthy follow task without clearing locomotion. Limit
        -- adjustments to 5 Hz, while initial tasks and stop transitions are immediate.
        local following=r.followKey and r.task==r.followKey
        if r.task~=followKey and r.followKey and r.followBase==key and now-(r.lastFollowIssue or 0)<200
            and moving and r.followMoving and not (speed>3 and r.followSpeed<4.5) then return true end
        api.task(r,followKey,function()
            if not following then
                -- Offset updates invalidate the cache, not the native task.
                if not r.followKey or GetScriptTaskStatus(ped,followTask)~=1 then ClearPedTasks(ped) end
            end
            TaskFollowToOffsetOfEntity(ped,principal,ox,oy,0,movement,-1,stopping,true)
            r.offsetX,r.offsetY=ox,oy;r.followSpeed=movement;r.followStopping=stopping
            r.followKey=followKey;r.lastFollowIssue=now
            r.followBase=key
            r.followMoving=moving
            r.nextFollowCheck=now+500;r.followProgressAt=now
        end)
        return true
    end
    local function board(ped,principal,session)
        if IsPedInAnyVehicle(ped,false) then return true end
        local r=cache(session)
        local now=GetGameTimer()
        if not r.seatPlan or now>(r.nextSeatPlan or 0) then
            r.nextSeatPlan=now+1000
            local cars,seen,guards={}, {}, {}
            for _,net in ipairs(session.guards) do guards[api.resolve(net)]=true end
            local principalCar=GetVehiclePedIsIn(principal,false)
            local function include(net,reserved)
                local car=api.resolve(net)
                if car==0 or seen[car] or not IsVehicleDriveable(car,false) then return end
                seen[car]=true
                local seats={}
                for seat=0,GetVehicleMaxNumberOfPassengers(car)-1 do
                    local occupant=GetPedInVehicleSeat(car,seat)
                    if (seat==0 and car~=principalCar or seat>=reserved) and (occupant==0 or guards[occupant])
                        and not (GetVehiclePedIsTryingToEnter(principal)==car and GetSeatPedIsTryingToEnter(principal)==seat) then seats[#seats+1]=seat end
                end
                cars[#cars+1]={net=net,freeSeats=seats}
            end
            for _,v in ipairs(session.vehicles) do if api.resolve(v.net)==principalCar then include(v.net,#v.crew) end end
            if session.detail.driver then include(session.detail.driver.vehicle,1) end
            for _,v in ipairs(session.vehicles) do include(v.net,#v.crew) end
            local available={}
            for _,net in ipairs(session.guards) do
                local role=session.tactical.roles[net] or session.tactical.roles[tostring(net)]
                if role and role.role~='driver' then available[#available+1]=net end
            end
            r.seatPlan=ProtectTactical.seats(available,cars,session.detail.driver and session.detail.driver.ped)
        end
        local assignment=r.seatPlan[PedToNet(ped)]
        local car=assignment and api.resolve(assignment.vehicle) or 0
        if car==0 or #(GetEntityCoords(car)-GetEntityCoords(ped))>55 then return false end
        if not IsVehicleSeatFree(car,assignment.seat,false) then return false end
        local ctx=api.context(ped,session.id)
        if now-(ctx.taskAt or 0)>13000 then ctx.task=nil end
        api.task(ctx,'tactical-board:'..car..':'..assignment.seat,function() ClearPedTasks(ped);TaskEnterVehicle(ped,car,12000,assignment.seat,2.0,1,0) end)
        return true
    end
    function result.tick(session,principal,friends)
        if not c.enabled or not session.tactical then return nil end
        local r,now=cache(session),GetGameTimer()
        r.friends=friends
        if tonumber(session.owner)==GetPlayerServerId(PlayerId()) and not session.deploying then
            if r.lastState~=session.tactical.state then
                local state=session.tactical.state
                if state=='THREAT' or state=='CONTACT' or state=='EXTRACTION' or state=='RECOVERY' then
                    -- The resource-local live UI announces transitions once, with semantic priority.
                end
                r.lastState=state
            end
            local observations=scan(session,principal,friends)
            if now>=r.nextReport then
                r.nextReport=now+c.reportInterval
                local pending={};for _,o in pairs(r.pending) do pending[#pending+1]=o end
                table.sort(pending,function(a,b) return a.id<b.id end)
                TriggerServerEvent('dios_protect:tacticalReport',{session=session.id,observations=pending})
                r.pending={}
            end
        end
        local target=confirmed(session,now)
        local primary=ProtectTactical.summary(session.tactical,(session.tactical.clock or now)+now-(session.tactical.receivedAt or now)).primary
        local e=primary and api.resolve(primary) or 0
        if e~=0 then local a,b=GetEntityCoords(principal),GetEntityCoords(e);r.direction=ProtectTactical.direction(r.direction,b.x-a.x,b.y-a.y) else r.direction=nil end
        return target and not friends[target] and target or nil
    end
    function result.guard(ped,principal,session)
        if not api.owned(ped) then return false end
        local t=session.tactical
        if not c.enabled or not t then return false end
        local r=api.context(ped,session.id)
        local role=t.roles[PedToNet(ped)] or t.roles[tostring(PedToNet(ped))]
        if not role then return false end
        if role.role=='vehiclecrew' then api.motion.crew(ped,api.resolve(role.vehicle),role.seat,principal,session);return true end
        if GetVehiclePedIsIn(principal,false)~=0 then
            if t.state=='CONTACT' or t.state=='EXTRACTION' then api.arm(ped) end
            if (t.state=='NORMAL' or t.state=='RECOVERY') and api.context(ped,session.id).concealed then SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true) end
            if board(ped,principal,session) then return true end
        end
        local now=GetGameTimer()
        if r.tacticalRevision~=t.revision then r.tacticalRevision=t.revision;r.task=nil;r.offsetX=nil;ClearPedTasks(ped) end
        local target=role.target and api.resolve(role.target) or 0
        local record=role.target and (t.threats[role.target] or t.threats[tostring(role.target)])
        local serverNow=(t.clock or now)+now-(t.receivedAt or now)
        if not record or (record.confirmedUntil or 0)<=serverNow or (cache(session).friends or {})[target] then target=0 end
        if r.tacticalState~=t.state then
            if r.tacticalState=='CONTACT' or r.tacticalState=='EXTRACTION' then ClearPedTasks(ped);r.task=nil;r.combatUntil=nil end
            r.tacticalState=t.state
        end
        if role.role=='engagement' and target~=0 and not IsPedInAnyVehicle(ped,false) and not IsEntityDead(target) and #(GetEntityCoords(ped)-GetEntityCoords(principal))<c.awarenessRadius and HasEntityClearLosToEntity(ped,target,17) then
            api.arm(ped)
            api.task(r,'tactical-engage:'..target,function() ClearPedTasks(ped);TaskCombatPed(ped,target,0,16) end)
            return true
        end
        if t.command=='vehicles' and role.role~='principal' and role.role~='close' and IsPedInAnyVehicle(ped,false) then return true end
        if GetVehiclePedIsIn(principal,false)~=0 or IsPedInAnyVehicle(ped,false) or session.detail.order=='hold' then return false end
        r.holdPoint=nil
        local f=t.formation=='adaptive' and (GetInteriorFromEntity(principal)~=0 and 'column' or 'diamond') or t.formation
        local x,y=ProtectTactical.offset(f,role.slot or 1,role.count or 1,c.spacing,c.looseSpacing)
        local principalPos=GetEntityCoords(principal)
        local summary=ProtectTactical.summary(t,(t.clock or now)+now-(t.receivedAt or now))
        local threat=summary.primary and api.resolve(summary.primary) or 0
        if threat~=0 and (t.state=='THREAT' or t.state=='CONTACT' or t.state=='EXTRACTION') then
            local p=GetEntityCoords(threat)
            local direction=cache(session).direction
            if direction then p=vector3(principalPos.x+direction.x*20,principalPos.y+direction.y*20,principalPos.z) end
            local wx,wy=ProtectTactical.shield(principalPos.x,principalPos.y,p.x,p.y,role.slot or 1,role.count or 1,c.spacing)
            local heading=math.rad(GetEntityHeading(principal));local dx,dy=wx-principalPos.x,wy-principalPos.y
            x,y=dx*math.cos(heading)+dy*math.sin(heading),-dx*math.sin(heading)+dy*math.cos(heading)
        end
        if t.command=='vehicles' and role.role~='principal' and role.role~='close' and board(ped,principal,session) then return true end
        local point=GetOffsetFromEntityInWorldCoords(principal,x,y,0)
        if t.formation=='adaptive' then
            if r.slotRay then
                local status,hit=GetShapeTestResult(r.slotRay)
                if status~=1 then r.slotRay=nil;r.slotBlocked=hit==1 or hit==true end
            end
            if now>(r.nextSlotRay or 0) and not r.slotRay then
                r.nextSlotRay=now+1500
                r.slotRay=StartShapeTestRay(principalPos.x,principalPos.y,principalPos.z+.8,point.x,point.y,point.z+.8,17,principal,7)
            end
            if r.slotBlocked then
                f='column';x,y=ProtectTactical.offset(f,role.slot or 1,role.count or 1,c.spacing,c.looseSpacing)
                point=GetOffsetFromEntityInWorldCoords(principal,x,y,0)
            end
        end
        local distance=#(GetEntityCoords(ped)-point)
        local emergency=t.state=='CONTACT' or t.state=='EXTRACTION'
        if emergency or t.state=='THREAT' or t.posture~='normal' then api.arm(ped)
        elseif r.concealed then SetCurrentPedWeapon(ped,joaat('WEAPON_UNARMED'),true) end
        if distance<=c.movementTolerance and GetEntitySpeed(principal)<=.5 and emergency and threat~=0 and confirmed(session,now)==threat and not (cache(session).friends or {})[threat] and HasEntityClearLosToEntity(ped,threat,17) then
            api.arm(ped)
            if now-(r.fireAt or 0)>2500 then
                r.task=nil;r.fireAt=now
                api.task(r,'tactical-shield-fire:'..threat,function() ClearPedTasks(ped);TaskShootAtEntity(ped,threat,1500,joaat('FIRING_PATTERN_BURST_FIRE')) end)
            end
        else
            -- Do not replace a settled follow task with an idle scenario: the
            -- native keeps its moving entity-relative slot between Lua updates.
            result.follow(ped,principal,session,('tactical-slot:%s:%s'):format(f,role.slot),x,y)
            if threat~=0 then TaskLookAtEntity(ped,threat,1500,2048,2) end
        end
        return true
    end
    function result.extraction(session,principal)
        if not c.enabled or tonumber(session.owner)~=GetPlayerServerId(PlayerId()) then return end
        local t,r,now=session.tactical,cache(session),GetGameTimer()
        if not t then return end
        if t.state~='EXTRACTION' then
            if r.blip then RemoveBlip(r.blip);r.blip=nil end
            r.notified=nil;r.routeSent=nil
            return
        end
        if not t.extraction then
            if r.vehicle then
                if r.blip then RemoveBlip(r.blip);r.blip=nil end
                r.vehicle=nil;r.notified=nil;r.routeSent=nil
            end
            if now<r.nextExtraction then return end;r.nextExtraction=now+2000
            local candidates={}
            local function candidate(carNet,driverNet,model,priority)
                local serverNow=(t.clock or now)+now-(t.receivedAt or now)
                if t.failedVehicle==carNet and serverNow<(t.failedUntil or 0) then return end
                local car,ped=api.resolve(carNet),api.resolve(driverNet)
                if car==0 or GetEntityModel(car)==joaat('rhino') then return end
                if ped==0 or IsEntityDead(ped) then
                    if not c.replaceDeadDriver then return end
                    driverNet=nil
                    for _,v in ipairs(session.vehicles) do if v.net==carNet then
                        for i=2,#v.crew do local e=api.resolve(v.crew[i]);if e~=0 and not IsEntityDead(e) then driverNet=v.crew[i];break end end
                    end end
                    if not driverNet then for _,net in ipairs(session.guards) do
                        local e=api.resolve(net);local role=t.roles[net] or t.roles[tostring(net)]
                        if e~=0 and not IsEntityDead(e) and role and (role.role=='flank' or role.role=='engagement') then driverNet=net;break end
                    end end
                    if not driverNet then return end
                end
                local seat=false
                for i=0,GetVehicleMaxNumberOfPassengers(car)-1 do if IsVehicleSeatFree(car,i,false) or GetPedInVehicleSeat(car,i)==principal then seat=true;break end end
                candidates[#candidates+1]={net=carNet,driver=driverNet,model=model,priority=priority,distance=#(GetEntityCoords(car)-GetEntityCoords(principal)),
                    alive=IsVehicleDriveable(car,false),ground=not IsThisModelAHeli(GetEntityModel(car)) and not IsThisModelAPlane(GetEntityModel(car)),
                    seat=seat,sameSession=Entity(car).state.diosProtection==session.id or (session.detail.driver and session.detail.driver.vehicle==carNet),sameBucket=true}
            end
            if session.detail.driver then candidate(session.detail.driver.vehicle,session.detail.driver.ped,'assigned',1) end
            for _,v in ipairs(session.vehicles) do candidate(v.net,v.crew[1],v.model,v.model==c.preferredVehicle and 2 or 3) end
            local chosen=ProtectTactical.vehicle(candidates)
            if chosen and chosen.distance<=c.extractionRadius then TriggerServerEvent('dios_protect:extraction',{session=session.id,vehicle=chosen.net,driver=chosen.driver})
            elseif not r.notified then api.notice(ProtectText('No suitable extraction vehicle. Remain with your close protection.'),'inform');r.notified=true end
            return
        end
        local car,driver=api.resolve(t.extraction.vehicle),api.resolve(t.extraction.driver)
        if r.vehicle~=t.extraction.vehicle then
            if r.blip then RemoveBlip(r.blip);r.blip=nil end
            r.notified=nil;r.routeSent=nil;r.vehicle=t.extraction.vehicle
        end
        if car==0 or driver==0 or IsEntityDead(driver) or not IsVehicleDriveable(car,false) then return end
        local ready=GetPedInVehicleSeat(car,-1)==driver
        if not ready and (t.clock or now)+now-(t.receivedAt or now)-t.extraction.requestedAt>c.driverReadinessTimeout and now>r.nextExtraction then
            r.nextExtraction=now+2000
            TriggerServerEvent('dios_protect:extractionFailed',{session=session.id,vehicle=t.extraction.vehicle})
            api.notice(ProtectText('Extraction driver could not become ready. Selecting another suitable vehicle.'),'inform')
            return
        end
        if c.extractionBlip and not r.blip then r.blip=AddBlipForEntity(car);SetBlipSprite(r.blip,225);SetBlipColour(r.blip,5) end
        if not r.notified then api.notice(ProtectText('Extraction vehicle prepared. Board a passenger seat; your driver will use your waypoint.'),'inform');r.notified=true end
        if session.detail.driver and session.detail.driver.vehicle==t.extraction.vehicle and session.detail.driver.ped==t.extraction.driver
            and not t.routePaused and GetVehiclePedIsIn(principal,false)==car and GetPedInVehicleSeat(car,-1)==driver and not session.detail.destination and not r.routeSent and IsWaypointActive() then
            r.routeSent=true
            CreateThread(function() local ok,res=pcall(api.waypoint);if not ok or (res and res.error) then r.routeSent=nil end end)
        end
    end
    function result.effective(session)
        if not c.enabled or not session.tactical then return session end
        local t=session.tactical
        if t.state~='EXTRACTION' and t.state~='CONTACT' then return session end
        local copy={};for k,v in pairs(session) do copy[k]=v end
        copy.detail={};for k,v in pairs(session.detail) do copy.detail[k]=v end
        copy.detail.style='urgent';copy.detail.order='follow';copy.detail.gap=math.max(4,session.detail.gap-1)
        return copy
    end
    function result.cleanup(sessions)
        local live={};for _,s in pairs(sessions) do live[s.id]=true end
        for id,r in pairs(caches) do if not live[id] then if r.blip then RemoveBlip(r.blip) end;caches[id]=nil end end
    end
    return result
end
