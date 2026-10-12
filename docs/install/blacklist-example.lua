-- Copy this guard into your existing SERVER entityCreating blacklist handler,
-- before CancelEvent(). Do not trust entity state or allow a model globally.
local function authorizedProtectionEntity(entity)
    if GetResourceState('dios_protect')~='started' then return false end
    local ok,allowed=pcall(function()
        return exports.dios_protect:IsProtectedEntity(entity)
    end)
    return ok and allowed==true
end
-- Example inside your handler:
-- if modelIsBlacklisted and not authorizedProtectionEntity(entity) then CancelEvent() end
-- Keep your existing modelIsBlacklisted check and all other security policies.
