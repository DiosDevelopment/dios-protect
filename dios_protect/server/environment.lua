-- Server-owned runtime identity; DLC build numbers do not identify the edition.
ProtectEnvironment = {}
local E=ProtectEnvironment
local notices={}
function E.snapshot()
    -- Legacy can omit the convar until it is explicitly set. GTA5 is FXServer's
    -- documented default (also used by txAdmin); Enhanced publishes gta5enhanced.
    -- Never infer the edition from a DLC/build number.
    local game=GetConvar('gamename','gta5'):lower()
    local build=GetConvar('sv_enforceGameBuild','default');if build=='' then build='default' end
    return {edition=game=='gta5enhanced' and 'Enhanced' or game=='gta5' and 'Legacy' or 'Unknown',
        game=game,build=build,framework=ProtectBridge:init().name,
        keys=ProtectBridge:KeysAdapter(),version=GetResourceMetadata(GetCurrentResourceName(),'version',0)}
end
local function warn(resource,reason)
    if notices[resource]==reason then return end
    notices[resource]=reason
    print(('[dios_protect] Potential spawn conflict: %s: %s Review its configuration and install/blacklist-example.lua; presence alone does not prove a conflict.'):format(resource,reason))
end
function E.inspect(resource)
    if not Protect.diagnostics.enabled or resource==GetCurrentResourceName() or GetResourceState(resource)~='started' then return end
    local reason=Protect.diagnostics.resources[resource]
    if reason then warn(resource,reason);return end
    if not Protect.diagnostics.scanScripts then return end
    -- Only inspect bounded, readable manifest-listed scripts. Do not execute foreign code.
    local paths,seen={},{}
    for _,key in ipairs({'server_script','client_script','shared_script'}) do
        for i=0,math.min(GetNumResourceMetadata(resource,key),64)-1 do
            local path=GetResourceMetadata(resource,key,i)
            if path and not path:find('[@*?]') and not seen[path] then paths[#paths+1]=path;seen[path]=true end
        end
    end
    -- Common paths cover wildcard manifests without enumerating private files.
    for _,path in ipairs({'server/entities.lua','client/ignore.lua','client/blacklist.lua','server/blacklist.lua'}) do
        if not seen[path] then paths[#paths+1]=path;seen[path]=true end
    end
    for i,path in ipairs(paths) do
        if i>128 then break end
        local ok,code=pcall(LoadResourceFile,resource,path)
        if ok and type(code)=='string' and #code<=262144 then
            local lower=code:lower()
            if (lower:find('entitycreating',1,true) and lower:find('cancelevent',1,true))
                or lower:find('setvehiclemodelissuppressed',1,true) or lower:find('setpedmodelissuppressed',1,true)
                or ((lower:find('blacklist',1,true) or lower:find('blacklisted',1,true))
                    and (lower:find('deleteentity',1,true) or lower:find('deletevehicle',1,true) or lower:find('deleteped',1,true))) then
                warn(resource,'Readable spawn-blocking/suppression code in '..path..'.');return
            end
        end
    end
end
function E.scan()
    for i=0,GetNumResources()-1 do local resource=GetResourceByFindIndex(i);if resource then E.inspect(resource) end;Wait(0) end
end
function E.log()
    local e=E.snapshot()
    print(('[dios_protect] v%s | GTA %s (%s; build %s) | framework: %s | keys: %s'):format(e.version or '?',e.edition,e.game,e.build,e.framework,e.keys))
    if e.framework=='standalone' then print('[dios_protect] No supported framework selected. Standalone access requires ACE '..Protect.standalone.presidentAce..'; appointments have no framework salary.') end
end
AddEventHandler('onResourceStart',function(resource)
    if resource~=GetCurrentResourceName() then SetTimeout(500,function()
        E.inspect(resource)
        for _,core in pairs(Protect.integration.resources) do if resource==core then
            print('[dios_protect] Framework resource started: '..resource..'. Restart dios_protect after framework start/restart to refresh the adapter safely.')
        end end
    end) end
end)
AddEventHandler('onResourceStop',function(resource) notices[resource]=nil end)
RegisterCommand(Protect.commands.environment,function(source)
    if source~=0 then return end
    notices={};E.log();CreateThread(E.scan)
end,true)
CreateThread(function() Wait(0);E.log();E.scan() end)
