-- Key grants are invoked only by server deployment/control code, never by a public grant event.
local K=ProtectKeys
local adapters={}
adapters.qbox=function(src,car,plate,r) if not exports[r]:HasKeys(src,car) then exports[r]:GiveKeys(src,car,true) end;assert(exports[r]:HasKeys(src,car),'Key verification failed') end
adapters.qbcore=function(src,car,plate,r) if not exports[r]:HasKeys(src,plate) then exports[r]:GiveKeys(src,plate) end;assert(exports[r]:HasKeys(src,plate),'Key verification failed') end
adapters.wasabi=function(src,car,plate,r) if not exports[r]:HasKey(src,plate) then exports[r]:GiveKey(src,plate) end;assert(exports[r]:HasKey(src,plate),'Key verification failed') end
adapters.renewed=function(src,car,plate,r)
    if not exports[r]:hasKey(src,plate) then exports[r]:addKey(src,plate) end;assert(exports[r]:hasKey(src,plate),'Key verification failed')
    Entity(car).state:set('vehicleLock',{lock=1,sound=false},true)
end
adapters.mrnewb=function(src,car,plate,r)
    local net=NetworkGetNetworkIdFromEntity(car)
    if not exports[r]:HaveKeys(src,net) then exports[r]:GiveKeys(src,net) end;assert(exports[r]:HaveKeys(src,net),'Key verification failed');exports[r]:SetVehicleLock(net,1)
end
adapters.zrx=function(src,car,plate,r) if not exports[r]:hasKey(src,plate,false) then exports[r]:giveKey(src,plate) end;assert(exports[r]:hasKey(src,plate,false),'Key verification failed') end
adapters.jaksam=function(src,car,plate,r) assert(exports[r]:giveVehicleKeysToPlayerId(src,plate,'temporary')~=false,'Key grant refused') end
adapters.ak47qb=function(src,car,plate,r) if not exports[r]:HasKey(src,plate) then exports[r]:GiveKey(src,plate,false) end;assert(exports[r]:HasKey(src,plate),'Key verification failed') end
local verified={qbox=true,qbcore=true,wasabi=true,renewed=true,mrnewb=true,zrx=true,ak47qb=true}
local delivered,warnings={},{}
function K.give(src,car,ready)
    assert(car~=0 and DoesEntityExist(car) and GetEntityType(car)==2,'Key vehicle is unavailable')
    SetVehicleDoorsLocked(car,1)
    if not ready then return true end -- Plate/client adapters run once the vehicle is staged and streamed.
    local providers=K.detect()
    -- Native unlocked doors need no key identity or plate replication.
    if #providers==1 and providers[1]=='none' then return true end
    local plate=K.plate(GetVehicleNumberPlateText(car))
    assert(plate,'Protection vehicle plate is unavailable')
    local net=NetworkGetNetworkIdFromEntity(car)
    delivered[car]=delivered[car] or {}
    for _,id in ipairs(providers) do
        local resource=Protect.keyResources[id]
        local generation=resource and (K.generations and K.generations[resource] or 0) or 0
        local stamp=src..':'..net..':'..plate..':'..generation
        if delivered[car][id]~=stamp then
            local ok,result=pcall(function()
                if id=='custom' then assert(ProtectIntegration.giveKeys(src,car)==true,'Custom key adapter must confirm success with true')
                elseif adapters[id] then
                    adapters[id](src,car,plate,resource)
                    if not verified[id] and not warnings[resource] then warnings[resource]=true;print(('[dios_protect] Keys: %s confirms API dispatch only; verify convoy entry/unlock with your installed version.'):format(resource)) end
                elseif id~='none' then
                    local answer=ProtectRPC.client(src,'dios_protect:keys',10000,{adapter=id,resource=resource,net=net,model=GetEntityModel(car),plate=plate})
                    assert(type(answer)=='table' and answer.ok==true,'Client key delivery failed: '..tostring(answer and answer.error))
                    if not answer.verified and not warnings[resource] then
                        warnings[resource]=true;print(('[dios_protect] Keys: %s confirms API dispatch only; verify convoy entry/unlock with your installed version.'):format(resource))
                    end
                end
                return true
            end)
            assert(ok,('Vehicle keys (%s/%s): %s'):format(id,resource or id,tostring(result)))
            delivered[car][id]=stamp
        elseif verified[id] then
            -- Verify existing grants again after a provider restart or revoked keys.
            adapters[id](src,car,plate,resource)
        end
    end
    return true
end
K.generations={}
AddEventHandler('onResourceStart',function(resource) warnings[resource]=nil;K.generations[resource]=(K.generations[resource] or 0)+1 end)
AddEventHandler('entityRemoved',function(car) delivered[car]=nil end)
AddEventHandler('playerDropped',function()
    local prefix=tostring(source)..':'
    for car,records in pairs(delivered) do for id,stamp in pairs(records) do if stamp:sub(1,#prefix)==prefix then records[id]=nil end end;if not next(records) then delivered[car]=nil end end
end)
