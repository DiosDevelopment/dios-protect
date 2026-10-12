-- Shared validation is also executed by the server. Never trust the menu payload.
ProtectPolicy = {}
function ProtectPolicy.guardModels(models,mode)
    local definition=Protect.guards[mode]
    if not definition then return nil end
    if models==nil then return definition.models end
    if type(models)~='table' or #models==0 or #models>#definition.models then return nil end
    local known,seen={},{}
    for _,model in ipairs(definition.models) do known[model]=true end
    for _,model in ipairs(models) do
        if type(model)~='string' or not known[model] or seen[model] then return nil end
        seen[model]=true
    end
    return models
end
function ProtectPolicy.networkId(value)
    local number=tonumber(value)
    if not number or number~=number or number%1~=0 or number<1 or number>65535 then return nil end
    return number
end
function ProtectPolicy.selection(data)
    if type(data) ~= 'table' or not Protect.guards[data.mode] then return nil, ProtectText('Choose a valid guard detail.') end
    local count = tonumber(data.count)
    if not count or count ~= math.floor(count) or count < 0 or count > Protect.maxGuards then return nil, ProtectText('Invalid guard count.') end
    if type(data.vehicles) ~= 'table' or #data.vehicles > Protect.maxVehicles then return nil, ProtectText('Too many escort vehicles.') end
    local known, selected = {}, {}
    for _, vehicle in ipairs(Protect.vehicles) do known[vehicle.model] = vehicle end
    for _, item in ipairs(data.vehicles) do
        local model = type(item)=='table' and item.model or item
        local quantity = type(item)=='table' and tonumber(item.quantity) or 1
        if type(model) ~= 'string' or not known[model] then return nil, ProtectText('Invalid escort vehicle.') end
        if not quantity or quantity~=quantity or quantity%1~=0 or quantity<1 or quantity>Protect.maxVehicles then return nil,ProtectText('Invalid vehicle quantity.') end
        if #selected+quantity>Protect.maxVehicles then return nil,ProtectText('Too many escort vehicles.') end
        for _=1,quantity do selected[#selected + 1] = known[model] end
    end
    if count == 0 and #selected == 0 then return nil, ProtectText('Select guards or a convoy first.') end
    return { mode = data.mode, count = count, vehicles = selected }
end
function ProtectPolicy.control(data)
    if type(data)~='table' then return nil,ProtectText('Invalid detail controls.') end
    local speed,gap=tonumber(data.speed),tonumber(data.gap)
    if not speed or speed~=speed or speed<5 or speed>300 then return nil,ProtectText('Speed must be between 5 and 300 km/h.') end
    if not gap or gap~=gap or gap<4 or gap>20 then return nil,ProtectText('Convoy spacing must be between 4 and 20 metres.') end
    if data.style~='normal' and data.style~='urgent' then return nil,ProtectText('Invalid driving style.') end
    if data.order~='follow' and data.order~='hold' then return nil,ProtectText('Invalid guard order.') end
    if data.air~='off' and data.air~='escort' and data.air~='auto' then return nil,ProtectText('Invalid air support mode.') end
    return {speed=speed,gap=gap,style=data.style,order=data.order,air=data.air}
end
function ProtectPolicy.airPosition(pos,origin)
    if type(pos)~='table' then return false end
    for _,key in ipairs({'x','y','z','h'}) do if type(pos[key])~='number' or pos[key]~=pos[key] or math.abs(pos[key])>10000 then return false end end
    local horizontal=math.sqrt((pos.x-origin.x)^2+(pos.y-origin.y)^2)
    return horizontal>=90 and horizontal<=250 and pos.z-origin.z>=65 and pos.z-origin.z<=140
end
function ProtectPolicy.position(pos, origin, minimum)
    if type(pos) ~= 'table' then return false end
    for _, key in ipairs({'x', 'y', 'z', 'h'}) do
        if type(pos[key]) ~= 'number' or pos[key] ~= pos[key] or math.abs(pos[key]) > 10000 then return false end
    end
    local distance = math.sqrt((pos.x-origin.x)^2 + (pos.y-origin.y)^2 + (pos.z-origin.z)^2)
    return distance >= minimum and distance <= Protect.spawnMax and math.abs(pos.z-origin.z) < Protect.stagingHeightRange
end
