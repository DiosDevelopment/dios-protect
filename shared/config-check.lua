-- Fail early with a readable installation error instead of starting a partial detail.
local function integer(value,low,high,label)
    assert(type(value)=='number' and value==value and value%1==0 and value>=low and value<=high,
        '[dios_protect] Invalid config: '..label)
end
assert(({auto=true,falcon=true,qbox=true,qbcore=true,esx=true,standalone=true})[Protect.integration.framework],'[dios_protect] Invalid framework selection')
assert(type(Protect.standalone.presidentAce)=='string' and Protect.standalone.presidentAce~='','[dios_protect] Configure standalone.presidentAce')
assert(type(Protect.diagnostics.enabled)=='boolean' and type(Protect.diagnostics.scanScripts)=='boolean' and type(Protect.diagnostics.resources)=='table','[dios_protect] Invalid diagnostics configuration')
assert(({auto=true,none=true,custom=true})[Protect.integration.keys] or Protect.keyResources[Protect.integration.keys],'[dios_protect] Invalid keys selection')
for id,resource in pairs(Protect.keyResources) do assert(type(id)=='string' and type(resource)=='string' and resource:match('^[%w_-]+$'),'[dios_protect] Invalid key resource name') end
assert(type(Protect.locale)=='string' and Protect.locale:match('^[%w_-]+$'),'[dios_protect] Invalid locale name')
for _,command in pairs(Protect.commands) do assert(type(command)=='string' and command:match('^[%w_-]+$'),'[dios_protect] Invalid command name') end
integer(Protect.maxGuards,0,12,'maxGuards')
integer(Protect.maxVehicles,1,40,'maxVehicles')
integer(Protect.maxAgents,0,32,'maxAgents')
integer(Protect.globalEntityLimit,1,300,'globalEntityLimit')
integer(Protect.longConvoyThreshold,1,40,'longConvoyThreshold')
integer(Protect.access.minimumGrade,0,100,'minimumGrade')
integer(Protect.performance.aiTick,100,2000,'aiTick')
Protect.performance.formationTick=Protect.performance.formationTick or 50
integer(Protect.performance.formationTick,25,250,'formationTick')
integer(Protect.performance.maintenanceTick,500,10000,'maintenanceTick')
integer(Protect.performance.stagingTimeout,5000,120000,'stagingTimeout')
Protect.performance.deploymentPreparationTimeout=Protect.performance.deploymentPreparationTimeout or 30000
Protect.performance.stagingSearchTimeout=Protect.performance.stagingSearchTimeout or 10000
integer(Protect.performance.deploymentPreparationTimeout,5000,120000,'deploymentPreparationTimeout')
integer(Protect.performance.stagingSearchTimeout,1000,30000,'stagingSearchTimeout')
integer(Protect.performance.modelTimeout,1000,30000,'modelTimeout')
assert(Protect.defaultSpeedKph>=5 and Protect.defaultSpeedKph<=300,'[dios_protect] Default speed must be 5–300 km/h')
assert(Protect.defaultGap>=4 and Protect.defaultGap<=20,'[dios_protect] Default gap must be 4–20 metres')
assert(Protect.spawnMax>Protect.vehicleSpawnMin and Protect.vehicleSpawnMin>0 and Protect.footSpawnMin>0,'[dios_protect] Invalid staging distances')
local models={}
for _,vehicle in ipairs(Protect.vehicles) do
    assert(type(vehicle.model)=='string' and not models[vehicle.model],'[dios_protect] Vehicle model missing or duplicated')
    models[vehicle.model]=true
    integer(vehicle.seats,1,8,'vehicle crew seats')
end
assert(next(Protect.guards),'[dios_protect] Configure at least one guard mode')
for _,definition in pairs(Protect.guards) do assert(type(definition.models)=='table' and #definition.models>0,'[dios_protect] Guard mode needs models') end

local t=Protect.tactical
assert(type(t)=='table' and type(t.enabled)=='boolean','[dios_protect] Configure tactical.enabled')
t.formationLookAhead=t.formationLookAhead or .45
assert(type(t.formationLookAhead)=='number' and t.formationLookAhead==t.formationLookAhead and t.formationLookAhead>=0 and t.formationLookAhead<=1,'[dios_protect] Invalid tactical.formationLookAhead')
for name,range in pairs({scanInterval={250,5000},reportInterval={500,5000},maxScanPeds={8,256},maxThreats={1,32},clearPeriod={1000,30000},recoveryPeriod={1000,30000},aimSustain={500,10000},minimumCloseGuards={1,12},driverReadinessTimeout={5000,60000},taskRefresh={1000,10000},forgetAfter={2000,60000},extractionSustain={1000,30000}}) do integer(t[name],range[1],range[2],'tactical.'..name) end
for _,name in ipairs({'awarenessRadius','attackRadius','decayPerSecond','spacing','looseSpacing','movementTolerance','extractionRadius','vehicleApproachSpeed','extractionHealth'}) do assert(type(t[name])=='number' and t[name]==t[name] and t[name]>0 and t[name]<1000,'[dios_protect] Invalid tactical.'..name) end
assert(t.awarenessRadius<=t.attackRadius and t.extractionRadius<=Protect.spawnMax,'[dios_protect] Invalid tactical radius ordering')
assert(t.suspicionThreshold>0 and t.suspicionThreshold<t.threatThreshold and t.threatThreshold<t.contactThreshold and t.contactThreshold<=100,'[dios_protect] Invalid tactical thresholds')
assert(({adaptive=true,diamond=true,box=true,column=true,close=true,loose=true,left=true,right=true})[t.formation],'[dios_protect] Invalid default formation')
for _,name in ipairs({'automaticExtraction','replaceDeadDriver','extractionBlip'}) do assert(type(t[name])=='boolean','[dios_protect] Invalid tactical.'..name) end
assert(type(t.trustedJobs)=='table' and type(t.preferredVehicle)=='string','[dios_protect] Invalid tactical trust/vehicle configuration')
assert(type(t.radii)=='table','[dios_protect] Configure tactical radii')
for _,name in ipairs({'inner','close','observation','outer'}) do integer(t.radii[name],1,200,'tactical.radii.'..name) end
assert(t.radii.inner<t.radii.close and t.radii.close<t.radii.observation and t.radii.observation<t.radii.outer and t.radii.outer<=t.awarenessRadius,'[dios_protect] Invalid perimeter ordering')
integer(t.airSupportHeight,50,200,'tactical.airSupportHeight')
integer(t.emergencyHeliSpeed,10,80,'tactical.emergencyHeliSpeed')
for job,enabled in pairs(t.trustedJobs) do assert(type(job)=='string' and type(enabled)=='boolean','[dios_protect] Invalid tactical trusted job') end
