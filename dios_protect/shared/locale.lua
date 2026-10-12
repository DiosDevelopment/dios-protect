ProtectLocales = {}
local function loadLocale(code)
    local raw=LoadResourceFile(GetCurrentResourceName(),'locales/'..code..'.json')
    if not raw then return {} end
    local ok,strings=pcall(json.decode,raw)
    assert(ok and type(strings)=='table','Invalid protection locale: '..code)
    return strings
end
ProtectLocales.en=loadLocale('en')
ProtectLocales.selected=Protect.locale=='en' and ProtectLocales.en or loadLocale(Protect.locale)
function ProtectText(key,values)
    local text=ProtectLocales.selected[key] or ProtectLocales.en[key] or key
    return (text:gsub('{([%w_]+)}',function(token) return values and tostring(values[token] or '{'..token..'}') or '{'..token..'}' end))
end
function ProtectLocalePayload()
    local result={}
    for key,value in pairs(ProtectLocales.en) do result[key]=value end
    for key,value in pairs(ProtectLocales.selected) do result[key]=value end
    return result
end
