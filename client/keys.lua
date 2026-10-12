local K=ProtectKeys
local adapters={}
adapters.quasar=function(car,plate,r)
    local model=GetDisplayNameFromVehicleModel(GetEntityModel(car))
    assert(exports[r]:GiveKeys(plate,model,false)~=false,'Key grant refused')
    return function() return exports[r]:GetKey(plate,model) end
end
adapters.codesign=function(car,plate,r)
    TriggerEvent('cd_garage:AddKeys',plate)
    return function() return exports[r]:DoesPlayerHaveKeys(plate) end
end
adapters.okok=function(car,plate) TriggerServerEvent('okokGarage:GiveKeys',plate) end
adapters.t1ger=function(car,plate,r)
    local model=GetDisplayNameFromVehicleModel(GetEntityModel(car))
    local label=GetLabelText(model);if label=='NULL' then label=model end
    assert(exports[r]:GiveTemporaryKeys(plate,label,'Protection')~=false,'Key grant refused')
    exports[r]:SetVehicleLocked(car,1)
end
adapters.mk=function(car,plate,r) assert(exports[r]:AddKey(car)~=false,'Key grant refused') end
adapters.ak47=function(car,plate,r) assert(exports[r]:GiveKey(plate,false)~=false,'Key grant refused') end
ProtectRPC.register('dios_protect:keys',function(data)
    if type(data)~='table' or not adapters[data.adapter] or data.resource~=Protect.keyResources[data.adapter]
        or GetResourceState(data.resource)~='started' or not ProtectPolicy.networkId(data.net) then return {error='Unavailable key adapter'} end
    local deadline=GetGameTimer()+5000
    while not NetworkDoesEntityExistWithNetworkId(data.net) and GetGameTimer()<deadline do Wait(25) end
    local car=NetworkDoesEntityExistWithNetworkId(data.net) and NetToVeh(data.net) or 0
    if car==0 or not DoesEntityExist(car) or GetEntityModel(car)~=data.model or K.plate(GetVehicleNumberPlateText(car))~=data.plate then return {error='Key vehicle identity mismatch'} end
    local verify=adapters[data.adapter](car,data.plate,data.resource)
    if verify then
        local expires=GetGameTimer()+2000
        while not verify() do if GetGameTimer()>=expires then return {error='Key ownership could not be verified'} end;Wait(50) end
    end
    return {ok=true,verified=verify~=nil}
end)
