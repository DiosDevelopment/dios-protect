-- Vehicle tasks run only on the NPC owner. Confirm seats and vehicle control
-- before assigning missions; a networked warp request is not a seating result.
ProtectMotion={}
function ProtectMotion.new(api)
    local resolve,owned,context,configure,task=api.resolve,api.owned,api.context,api.configure,api.task
    local motion={}
    local formations={}
    function motion.home(ped,session)
        for _,entry in ipairs(session.vehicles) do
            for index,net in ipairs(entry.crew) do
                if resolve(net)==ped then return entry,index==1 and -1 or index-1 end
            end
        end
    end
    function motion.capacity(session,principal)
        local limit=300
        local function include(car)
            if car~=0 and DoesEntityExist(car) and IsVehicleDriveable(car,false) then
                local maximum=GetVehicleEstimatedMaxSpeed(car)*3.6
                if maximum>1 then limit=math.min(limit,maximum) end
            end
        end
        include(GetVehiclePedIsIn(principal,false))
        for _,entry in ipairs(session.vehicles) do include(resolve(entry.net)) end
        if session.detail.driver then include(resolve(session.detail.driver.vehicle)) end
        return math.max(5,math.floor(limit))
    end
    local function speed(session,principal) return math.min(session.detail.speed,motion.capacity(session,principal))/3.6 end
    local function style(session) return session.detail.style=='urgent' and 786468 or 786603 end
    local function driveTo(driver,car,point,pace,session,stopRange,recovery)
        ClearPedTasks(driver)
        if owned(car) then SetVehicleHandbrake(car,false);SetVehicleEngineOn(car,true,true,false) end
        if GetEntityModel(car)==joaat('rhino') or recovery then
            TaskVehicleMissionCoorsTarget(driver,car,point.x,point.y,point.z,4,pace,style(session),stopRange,3.0,false)
        else TaskVehicleDriveToCoordLongrange(driver,car,point.x,point.y,point.z,pace,style(session),stopRange) end
    end
    local function brake(driver,car,r,key)
        if r.task==key and GetGameTimer()-(r.taskAt or 0)>1500 then r.task=nil end
        task(r,key,function() TaskVehicleTempAction(driver,car,27,2200) end)
    end
    function motion.ground(car,session)
        if car==0 or not DoesEntityExist(car) then return false end
        local state=Entity(car).state
        if state.diosProtection~=session.id then return true end
        if state.diosGroundReady then
            local driver=GetPedInVehicleSeat(car,-1)
            if owned(car) and driver~=0 and not IsPedAPlayer(driver) then
                FreezeEntityPosition(car,false)
                SetVehicleEngineOn(car,true,true,false);SetVehicleHandbrake(car,false)
            end
            return true
        end
        if not owned(car) then NetworkRequestControlOfEntity(car);return false end
        local pos=GetEntityCoords(car)
        local r=context(car,session.id)
        r.groundAt=r.groundAt or GetGameTimer()
        RequestCollisionAtCoord(pos.x,pos.y,pos.z)
        if GetGameTimer()-r.groundAt<3000 and (IsEntityWaitingForWorldCollision(car) or not HasCollisionLoadedAroundEntity(car)) then r.blocked='loading road collision';return false end
        if not SetVehicleOnGroundProperly(car) then r.blocked='ground placement pending';return false end
        -- Preserve the generated plate: QBCore key resources use it as their identifier.
        SetVehicleDoorsLocked(car,1);SetVehicleDirtLevel(car,0.0)
        FreezeEntityPosition(car,false)
        state:set('diosGroundReady',true,true)
        r.blocked=nil
        return true
    end
    local function prepare(driver,car,seat,session,principal,vehicleControl,staging)
        local r=context(driver,session.id)
        if not owned(driver) then
            if staging then NetworkRequestControlOfEntity(driver) end
            r.blocked='driver control pending';return nil
        end
        if car==0 or not DoesEntityExist(car) or IsEntityDead(driver) or (not staging and not IsVehicleDriveable(car,false)) then r.blocked='vehicle or driver unavailable';return nil end
        r.blocked=nil
        configure(driver,principal,session.id,session.mode)
        local occupiedCar=GetVehiclePedIsIn(driver,false)
        if occupiedCar~=0 and occupiedCar~=car then
            r.blocked='returning to assigned vehicle'
            task(r,'leave-wrong-car:'..car,function() TaskLeaveVehicle(driver,occupiedCar,0) end)
            r.seatAt=nil
            return nil
        end
        -- Boarding has priority over NPC seating. Never jack a player out of a seat.
        local occupant=GetPedInVehicleSeat(car,seat)
        if GetVehiclePedIsTryingToEnter(principal)==car and GetSeatPedIsTryingToEnter(principal)==seat then
            if occupant==driver then
                task(r,'yield-seat',function() TaskLeaveVehicle(driver,car,0) end)
            end
            return nil
        end
        if occupant~=0 and occupant~=driver and IsPedAPlayer(occupant) then
            task(r,'player-seat-priority',function() ClearPedTasks(driver) end)
            return nil
        end
        if seat==-1 and occupant~=0 and occupant~=driver then
            r.blocked='assigned driver seat occupied'
            if owned(occupant) and GetGameTimer()-(r.clearSeatAt or -6000)>5000 then
                TaskLeaveVehicle(occupant,car,0);r.clearSeatAt=GetGameTimer()
            end
            return nil
        end
        if GetPedInVehicleSeat(car,seat)~=driver then
            r.blocked='boarding seat '..seat
            local pedPos,carPos=GetEntityCoords(driver),GetEntityCoords(car)
            local hiddenBoarding=not Entity(driver).state.diosSeated and not IsSphereVisible(carPos.x,carPos.y,carPos.z,8.0)
                and not IsSphereVisible(pedPos.x,pedPos.y,pedPos.z,1.5)
            local retry=hiddenBoarding and 1500 or 13000
            if not r.seatAt or GetGameTimer()-r.seatAt>retry then
                r.seatAt=GetGameTimer();r.task=nil
                FreezeEntityPosition(driver,false)
                if hiddenBoarding then
                    SetPedIntoVehicle(driver,car,seat)
                else TaskEnterVehicle(driver,car,12000,seat,2.0,1,0) end
            end
            return nil
        end
        Entity(driver).state:set('diosSeated',true,true)
        if vehicleControl and not owned(car) then
            if GetGameTimer()-(r.controlAt or -2000)>1500 then NetworkRequestControlOfEntity(car);r.controlAt=GetGameTimer() end
            r.blocked='vehicle control pending';return nil
        end
        if seat==-1 then
            if r.drivingStyle and (r.drivingStyle~=session.detail.style or r.drivingGap~=session.detail.gap) then r.task=nil end
            r.drivingStyle,r.drivingGap=session.detail.style,session.detail.gap
        end
        if vehicleControl and owned(car) then
            SetVehicleEngineOn(car,true,true,false)
            SetVehicleHandbrake(car,false)
            SetDriverAbility(driver,1.0);SetDriverAggressiveness(driver,0.0)
        end
        return r
    end
    function motion.stage(entry,principal,session)
        local car=resolve(entry.net)
        if car==0 then return false end
        local driver=resolve(entry.crew[1])
        -- Seat first: the NPC driver can establish vehicle ownership while the
        -- vehicle is still frozen. Waiting for ground readiness first deadlocks.
        if driver~=0 then prepare(driver,car,-1,session,principal,false,true) end
        if not motion.ground(car,session) then return false end
        local ready=true
        for i=2,#entry.crew do if not motion.crew(resolve(entry.crew[i]),car,i-1,principal,session) then ready=false end end
        return ready and driver~=0 and GetPedInVehicleSeat(car,-1)==driver
    end
    -- Rebuild around the President's current car, regardless of its original slot.
    function motion.formation(session,principal)
        local target=GetVehiclePedIsIn(principal,false)
        local cached=formations[session.id]
        if cached and cached.target==target and cached.vehicleCount==#session.vehicles and GetGameTimer()-(cached.cachedAt or -1000)<100 then
            return cached.roles,target,cached
        end
        local escorts={}
        for _,entry in ipairs(session.vehicles) do
            local car=resolve(entry.net)
            if car~=0 and car~=target and DoesEntityExist(car) and IsVehicleDriveable(car,false) then escorts[#escorts+1]=car end
        end
        local frontCount=math.ceil(#escorts/2)
        local long=#session.vehicles>Protect.longConvoyThreshold
        local roles={}
        for i,car in ipairs(escorts) do
            if i<=frontCount then roles[car]={front=true,rank=frontCount-i+1,preceding=long and (i==frontCount and target or escorts[i+1]) or target,long=long}
            else roles[car]={front=false,rank=i-frontCount,preceding=i==frontCount+1 and target or escorts[i-1],long=long} end
        end
        local signature=tostring(target)..':'..table.concat(escorts,',')
        local plan=formations[session.id]
        if not plan or plan.signature~=signature then
            plan={signature=signature,changedAt=GetGameTimer(),target=target,long=long}
            formations[session.id]=plan
            local cleared={}
            local function reset(ped)
                if ped==0 or cleared[ped] then return end
                cleared[ped]=true
                local r=context(ped,session.id)
                if owned(ped) then ClearPedTasks(ped) end
                r.task=nil;r.leadPoint=nil;r.tankPoint=nil;r.catchupAt=nil;r.routeStalledAt=nil;r.routeRecovery=nil
                r.assemblyRevision=nil;r.assemblyAt=nil;r.assemblyDone=nil
            end
            for _,entry in ipairs(session.vehicles) do reset(resolve(entry.crew[1])) end
            if session.detail.driver then reset(resolve(session.detail.driver.ped)) end
        end
        plan.roles=roles;plan.cachedAt=GetGameTimer();plan.vehicleCount=#session.vehicles
        return roles,target,plan
    end
    function motion.formed(session,principal)
        local roles,target,plan=motion.formation(session,principal)
        if target==0 then return true,plan end
        local origin=GetEntityCoords(target)
        local forward=GetOffsetFromEntityInWorldCoords(target,0.0,1.0,0.0)-origin
        for car,role in pairs(roles) do
            if role.front and (not plan.long or role.rank==1) then
                local delta=GetEntityCoords(car)-origin
                local ahead=delta.x*forward.x+delta.y*forward.y
                if ahead<session.detail.gap+3 or #(delta)>80 then return false,plan end
            end
        end
        return true,plan
    end
    function motion.assigned(ped,principal,session)
        motion.formation(session,principal)
        local driver=session.detail.driver
        local r=context(ped,session.id)
        if not driver or resolve(driver.ped)~=ped then
            if r.wasDriver and owned(ped) then ClearPedTasks(ped);r.task=nil;r.wasDriver=nil end
            return false
        end
        r.wasDriver=true
        local car=resolve(driver.vehicle)
        if not motion.ground(car,session) then return true end
        r=prepare(ped,car,-1,session,principal,true)
        if not r then return true end
        local destination=session.detail.destination
        if session.tactical and session.tactical.state=='EXTRACTION' and session.tactical.extraction and GetVehiclePedIsIn(principal,false)~=car then
            local p=GetEntityCoords(principal)
            if #(GetEntityCoords(car)-p)>9 then
                if not r.extractionPoint or #(r.extractionPoint-p)>5 or GetGameTimer()-(r.taskAt or 0)>6000 then
                    local ok,node=GetClosestVehicleNode(p.x,p.y,p.z,1,3.0,0)
                    if ok then r.task=nil;task(r,'extraction-approach',function() driveTo(ped,car,node,math.min(10,speed(session,principal)),session,7);r.extractionPoint=p end) end
                end
            else brake(ped,car,r,'extraction-board') end
            return true
        end
        if not destination or GetVehiclePedIsIn(principal,false)~=car then brake(ped,car,r,'chauffeur-hold');return true end
        local point=vector3(destination.x,destination.y,destination.z)
        local current=GetEntityCoords(car)
        if math.sqrt((current.x-point.x)^2+(current.y-point.y)^2)<12 then
            brake(ped,car,r,'arrived')
            if r.arrivalRevision~=session.detail.revision then TriggerServerEvent('dios_protect:arrived',session.owner,session.detail.revision);r.arrivalRevision=session.detail.revision end
            return true
        end
        local pace=speed(session,principal)
        local formed=motion.formed(session,principal)
        if r.assemblyRevision~=session.detail.revision then
            r.assemblyRevision=session.detail.revision;r.assemblyAt=GetGameTimer();r.assemblyDone=nil
        end
        if formed then r.assemblyDone=true end
        if not formed and not r.assemblyDone then
            local elapsed=GetGameTimer()-r.assemblyAt
            if elapsed<3000 and GetEntitySpeed(car)<3 then brake(ped,car,r,'assembling-convoy');return true end
            if elapsed<12000 then pace=pace*0.75 else r.assemblyDone=true end
        end
        local largestGap=0
        local roles,_,plan=motion.formation(session,principal)
        for _,entry in ipairs(session.vehicles) do
            local escort=resolve(entry.net)
            if escort~=0 and escort~=car and IsVehicleDriveable(escort,false) then
                local link=plan.long and roles[escort] and roles[escort].preceding or car
                if link and link~=0 then largestGap=math.max(largestGap,#(GetEntityCoords(escort)-GetEntityCoords(link))) end
            end
        end
        if largestGap>100 then
            r.catchupAt=r.catchupAt or GetGameTimer()
            if GetGameTimer()-r.catchupAt<8000 then brake(ped,car,r,'wait-for-convoy');return true end
        else r.catchupAt=nil end
        if largestGap>50 then
            r.lagAt=r.lagAt or GetGameTimer()
            if GetGameTimer()-r.lagAt<12000 then pace=pace*0.75 end
        else r.lagAt=nil end
        local key='route:'..session.detail.revision
        if GetEntitySpeed(car)<0.3 then
            r.routeStalledAt=r.routeStalledAt or GetGameTimer()
            if GetGameTimer()-r.routeStalledAt>6000 then r.task=nil;r.routeRecovery=true;r.routeStalledAt=GetGameTimer() end
        else r.routeStalledAt=nil;r.routeRecovery=nil end
        task(r,key,function() driveTo(ped,car,point,pace,session,10.0,r.routeRecovery) end)
        SetDriveTaskCruiseSpeed(ped,pace);SetDriveTaskMaxCruiseSpeed(ped,pace)
        return true
    end
    function motion.convoy(entry,principal,index,session)
        local car,driver=resolve(entry.net),resolve(entry.crew[1])
        if car==0 or driver==0 then return end
        if not motion.ground(car,session) then return end
        motion.formation(session,principal)
        if session.detail.driver and resolve(session.detail.driver.vehicle)==car and resolve(session.detail.driver.ped)~=driver then
            if owned(driver) then
                if GetPedInVehicleSeat(car,-1)==driver then
                    task(context(driver,session.id),'relieved-driver-exit',function() TaskLeaveVehicle(driver,car,0) end)
                else motion.crew(driver,car,0,principal,session) end
            end
            return
        end
        if motion.assigned(driver,principal,session) then return end
        local r=prepare(driver,car,-1,session,principal,true)
        if not r then return end
        local target=GetVehiclePedIsIn(principal,false)
        if target==car then brake(driver,car,r,'principal-onboard');return end
        if session.detail.order=='hold' then brake(driver,car,r,'convoy-hold');return end
        if target~=0 then
            local roles,_,plan=motion.formation(session,principal)
            local role=roles[car]
            if not role then return end
            local preceding=role.preceding
            local a,b=GetModelDimensions(GetEntityModel(car))
            local c,d=GetModelDimensions(GetEntityModel(preceding))
            local gap=math.max(session.detail.gap,role.long and Protect.longConvoyGap or 0)+(b.y-a.y+d.y-c.y)/2
            if role.long and GetGameTimer()-plan.changedAt<(role.rank-1)*Protect.longDepartureInterval then
                brake(driver,car,r,'staged-departure');return
            end
            if role.front then
                local cap=speed(session,principal)
                local pace=math.min(cap,math.max(6,GetEntitySpeed(target)+6))
                local key='lead:'..preceding..':'..role.rank..':'..session.detail.revision
                -- Escort mode 0 maintains an ahead position against a moving
                -- vehicle. Coordinate missions brake at each moving destination.
                task(r,key,function()
                    ClearPedTasks(driver)
                    TaskVehicleEscort(driver,car,preceding,0,pace,style(session)|4|524288,gap*(role.long and 1 or role.rank),0,0.0)
                end)
                SetDriveTaskCruiseSpeed(driver,pace)
                SetDriveTaskMaxCruiseSpeed(driver,cap)
                return
            end
            local distance=#(GetEntityCoords(car)-GetEntityCoords(preceding))
            local cap=speed(session,principal)
            local pace=math.min(cap,math.max(5,GetEntitySpeed(preceding)+(distance>gap+12 and 8 or 1)))
            local key='follow:'..preceding..':'..session.detail.revision
            if GetEntityModel(car)==joaat('rhino') then
                local point=GetOffsetFromEntityInWorldCoords(preceding,0.0,-gap,0.0)
                local ok,node=GetClosestVehicleNode(point.x,point.y,point.z,1,3.0,0)
                if not ok then brake(driver,car,r,'tank-no-road');return end
                if distance<gap+3 and GetEntitySpeed(preceding)<0.3 then brake(driver,car,r,'tank-hold');return end
                if not r.tankPoint or #(r.tankPoint-node)>6 or GetGameTimer()-(r.taskAt or 0)>6000 then r.task=nil end
                task(r,key,function() driveTo(driver,car,node,pace,session,3.0);r.tankPoint=node end)
                SetDriveTaskCruiseSpeed(driver,pace);SetDriveTaskMaxCruiseSpeed(driver,cap)
                return
            end
            -- Ordinary escorts follow their assigned vehicle. Reissue only for
            -- target/config changes, or a genuinely stalled vehicle.
            if GetEntitySpeed(car)<0.3 and distance>gap+10 then
                r.stalledAt=r.stalledAt or GetGameTimer()
                if GetGameTimer()-r.stalledAt>6000 then r.task=nil;r.stalledAt=GetGameTimer() end
            else r.stalledAt=nil end
            task(r,key,function() ClearPedTasks(driver);TaskVehicleFollow(driver,car,preceding,pace,style(session),math.floor(gap)) end)
            SetDriveTaskCruiseSpeed(driver,pace);SetDriveTaskMaxCruiseSpeed(driver,cap)
        else
            local p=GetEntityCoords(principal)
            local parkingGap=10+index*5
            if #(GetEntityCoords(car)-p)>parkingGap+5 then
                if not r.destination or #(r.destination-p)>7 or r.task~='approach' then
                    local ok,node=GetClosestVehicleNode(p.x,p.y,p.z,1,3.0,0)
                    if ok then driveTo(driver,car,node,math.min(12,speed(session,principal)),session,parkingGap);r.task='approach';r.destination=p;r.taskAt=GetGameTimer() end
                end
                if GetEntitySpeed(car)<0.3 and GetGameTimer()-(r.taskAt or 0)>6000 then r.task=nil end
            else brake(driver,car,r,'convoy-parked') end
        end
    end
    function motion.crew(ped,car,seat,principal,session)
        if ped==0 or car==0 or not DoesEntityExist(ped) or not DoesEntityExist(car) then return false end
        local maximum=GetVehicleMaxNumberOfPassengers(car)
        seat=math.min(seat,maximum-1)
        if seat<0 then return false end
        for occupiedSeat=0,maximum-1 do
            if GetPedInVehicleSeat(car,occupiedSeat)==ped then seat=occupiedSeat;break end
        end
        local occupant=GetPedInVehicleSeat(car,seat)
        local boarding=GetVehiclePedIsTryingToEnter(principal)==car and GetSeatPedIsTryingToEnter(principal)==seat
        if boarding or (occupant~=0 and occupant~=ped) then
            if boarding and occupant==ped and owned(ped) then
                task(context(ped,session.id),'yield-seat',function() TaskLeaveVehicle(ped,car,0) end)
                return false
            end
            local available
            for alternative=0,maximum-1 do
                if GetPedInVehicleSeat(car,alternative)==0 and not (GetVehiclePedIsTryingToEnter(principal)==car and GetSeatPedIsTryingToEnter(principal)==alternative) then available=alternative;break end
            end
            if not available then return false end
            seat=available
        end
        return prepare(ped,car,seat,session,principal,false)~=nil
    end
    function motion.air(session,principal,threat)
        local entry=session.air
        if not entry then return end
        local heli,pilot=resolve(entry.net),resolve(entry.crew[1])
        if heli==0 then return end
        if owned(heli) and not Entity(heli).state.diosAirborne then FreezeEntityPosition(heli,true) end
        for _,net in ipairs(entry.crew) do
            local ped=resolve(net)
            if owned(ped) and not Entity(ped).state.diosSeated then FreezeEntityPosition(ped,true) end
        end
        for i=2,#entry.crew do
            local gunner=resolve(entry.crew[i])
            local r=prepare(gunner,heli,i-1,session,principal,false)
            if r then
                if threat and DoesEntityExist(threat) and not IsEntityDead(threat) and #(GetEntityCoords(threat)-GetEntityCoords(heli))<140 and HasEntityClearLosToEntity(gunner,threat,17) then
                    api.arm(gunner)
                    if GetGameTimer()-(r.burstAt or -2000)>2000 then TaskShootAtEntity(gunner,threat,1500,joaat('FIRING_PATTERN_BURST_FIRE'));r.burstAt=GetGameTimer();r.airTarget=threat end
                elseif r.airTarget then ClearPedTasks(gunner);r.airTarget=nil end
            end
        end
        local r=prepare(pilot,heli,-1,session,principal,true)
        if not r then return end
        for i=2,#entry.crew do
            local crew=resolve(entry.crew[i])
            if crew~=0 and not IsEntityDead(crew) and GetPedInVehicleSeat(heli,i-1)~=crew then return end
        end
        FreezeEntityPosition(heli,false)
        Entity(heli).state:set('diosAirborne',true,true)
        SetHeliBladesFullSpeed(heli)
        local phase=session.tactical and Protect.tactical.enabled and session.tactical.state or 'NORMAL'
        local supporting=phase=='THREAT' or phase=='CONTACT' or phase=='EXTRACTION'
        local targetCar=phase=='EXTRACTION' and GetVehiclePedIsIn(principal,false) or 0
        local key='air-cover:'..principal..':'..session.detail.revision..':'..phase..':'..targetCar
        task(r,key,function() TaskHeliMission(pilot,heli,targetCar,targetCar==0 and principal or 0,0.0,0.0,0.0,23,
            phase=='EXTRACTION' and Protect.tactical.emergencyHeliSpeed or 30.0,30.0,-1.0,
            supporting and Protect.tactical.airSupportHeight or Protect.airHeight,45.0,45.0,4480) end)
    end
    return motion
end
