-- Resource-local request/reply transport. No framework/library is required.
ProtectRPC={}
local R=ProtectRPC
local server=IsDuplicityVersion()
local handlers,pending,inflight,rates,epochs={},{},{},{},{}
local sequence=0
local boot=('%s:%s'):format(GetGameTimer(),math.random(1,2147483647))
local function id() sequence=sequence+1;return boot..':'..sequence end
local function validId(value) return type(value)=='string' and #value>0 and #value<=96 end
local function payload(value,depth,budget)
    depth=depth or 0;budget=budget or {left=4096}
    budget.left=budget.left-1
    if budget.left<0 or depth>10 then return false end
    local kind=type(value)
    if kind=='nil' or kind=='boolean' then return true end
    if kind=='number' then return value==value and math.abs(value)<1e15 end
    if kind=='string' then return #value<=32768 end
    if kind~='table' then return false end
    for k,v in pairs(value) do if not payload(k,depth+1,budget) or not payload(v,depth+1,budget) then return false end end
    return true
end
local function arguments(args)
    if type(args)~='table' or type(args.n)~='number' or args.n%1~=0 or args.n<0 or args.n>8
        or type(args.values)~='table' or not payload(args) then return false end
    for key in pairs(args.values) do
        if type(key)~='number' or key%1~=0 or key<1 or key>args.n then return false end
    end
    return true
end
local function packArguments(...)
    -- FiveM's MessagePack codec drops named fields on nonempty array tables.
    -- Keep the explicit count outside the array to preserve trailing nils too.
    return {n=select('#',...),values={...}}
end
local function unavailable() return {error=ProtectText('Service unavailable.')} end
function R.register(route,handler) assert(type(route)=='string' and type(handler)=='function');handlers[route]=handler end
local function wait(record,key,timeout)
    local deadline=GetGameTimer()+timeout
    while not record.done and GetGameTimer()<deadline do Wait(25) end
    pending[key]=nil
    if record.done then return record.result end
    return unavailable()
end
if server then
    RegisterNetEvent('dios_protect:rpcRequest',function(key,route,args)
        local src=source
        if not validId(key) or type(route)~='string' or not handlers[route] or not arguments(args) then return end
        local now=GetGameTimer()
        local rate=rates[src]
        if not rate or now-rate.at>=5000 then rate={at=now,count=0};rates[src]=rate end
        rate.count=rate.count+1
        if rate.count>20 or (inflight[src] or 0)>=4 then TriggerClientEvent('dios_protect:rpcReply',src,key,unavailable());return end
        local epoch=epochs[src] or 0
        inflight[src]=(inflight[src] or 0)+1
        local ok,result=pcall(handlers[route],src,table.unpack(args.values,1,args.n))
        if (epochs[src] or 0)~=epoch then return end
        inflight[src]=math.max(0,(inflight[src] or 1)-1)
        if not ok then print('[dios_protect] Request failed ('..route..'): '..tostring(result));result=unavailable() end
        TriggerClientEvent('dios_protect:rpcReply',src,key,result or unavailable())
    end)
    function R.client(src,route,timeout,...)
        if not GetPlayerName(src) then return unavailable() end
        local key=id();local record={source=src,epoch=epochs[src] or 0};pending[key]=record
        TriggerClientEvent('dios_protect:rpcClient',src,key,route,packArguments(...))
        return wait(record,key,timeout or 10000)
    end
    RegisterNetEvent('dios_protect:rpcClientReply',function(key,result)
        local record=validId(key) and pending[key]
        if record and record.source==source and record.epoch==(epochs[source] or 0) and payload(result) then record.result=result;record.done=true end
    end)
    AddEventHandler('playerDropped',function()
        local src=source;epochs[src]=(epochs[src] or 0)+1;inflight[src]=nil;rates[src]=nil
        for _,record in pairs(pending) do if record.source==src then record.result=unavailable();record.done=true end end
    end)
else
    function R.await(route,_,...)
        local key=id();local record={};pending[key]=record
        TriggerServerEvent('dios_protect:rpcRequest',key,route,packArguments(...))
        return wait(record,key,route=='dios_protect:deploy' and 180000 or 30000)
    end
    RegisterNetEvent('dios_protect:rpcReply',function(key,result)
        if source~=65535 then return end
        local record=validId(key) and pending[key]
        if record then record.result=result;record.done=true end
    end)
    RegisterNetEvent('dios_protect:rpcClient',function(key,route,args)
        if source~=65535 or not validId(key) or not arguments(args) or not handlers[route] then return end
        local ok,result=pcall(handlers[route],table.unpack(args.values,1,args.n))
        if not ok then print('[dios_protect] Client request failed ('..tostring(route)..'): '..tostring(result));result=unavailable() end
        TriggerServerEvent('dios_protect:rpcClientReply',key,result or unavailable())
    end)
    function R.requestModel(model,timeout)
        local hash=type(model)=='string' and joaat(model) or model
        assert(IsModelInCdimage(hash) and IsModelValid(hash),'Unavailable model: '..tostring(model))
        local deadline=GetGameTimer()+(timeout or Protect.performance.modelTimeout)
        RequestModel(hash)
        while not HasModelLoaded(hash) do
            if GetGameTimer()>=deadline then SetModelAsNoLongerNeeded(hash);error('Model loading timed out: '..tostring(model)) end
            Wait(0)
        end
        return hash
    end
end
AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for _,record in pairs(pending) do record.result=unavailable();record.done=true end
end)
