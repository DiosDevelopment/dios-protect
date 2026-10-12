ProtectClient={}
function ProtectClient.notify(text,kind)
    SendNUIMessage({action='notify',title=Protect.ui.brand,text=tostring(text),kind=kind or 'inform'})
end
RegisterNetEvent('dios_protect:notify',ProtectClient.notify)
