-- Shared, native-free tactical intent. Times are monotonic milliseconds.
ProtectTactical = {}
local T=ProtectTactical
T.formations={adaptive=true,diamond=true,box=true,column=true,close=true,loose=true,left=true,right=true}
T.postures={normal=true,alert=true,emergency=true}
function T.new(now)
    return {state='NORMAL',formation=Protect.tactical.formation,posture='normal',threats={},roles={},
        changedAt=now or 0,lastDanger=0,contactSince=nil,extraction=nil,command='follow',revision=0}
end
function T.observe(intent,observations,now,config)
    local c=config or Protect.tactical
    for id,r in pairs(intent.threats) do
        r.score=math.max(0,r.score-(now-(r.updated or now))/1000*c.decayPerSecond)
        r.updated=now
        if now-r.seen>c.reportInterval*2 then r.aimSince=nil end
        if now-r.seen>c.forgetAfter or r.score==0 then intent.threats[id]=nil end
    end
    for _,o in ipairs(observations or {}) do
        if not o.friendly and type(o.id)=='number' then
            local r=intent.threats[o.id] or {score=0,aimSince=nil}
            if o.aim then r.aimSince=r.aimSince or now else r.aimSince=nil end
            local confirmed=o.damage or o.combat or (o.aim and now-(r.aimSince or now)>=c.aimSustain)
            local distance=o.distance or c.radii.observation
            local armedWeight=distance<=c.radii.inner and 35 or distance<=c.radii.close and 24
                or distance<=c.radii.observation and 18 or distance<=c.radii.outer and 8 or 4
            local evidence=o.damage and 100 or o.combat and 90 or confirmed and 80
                or math.min(70,(o.aim and 35 or 0)+(o.armed and (o.aim and 8 or armedWeight) or 0)+(o.facing and o.armed and 10 or 0)+(o.approach and 22 or 0))
            r.score=math.max(r.score,evidence)
            if confirmed then r.confirmedUntil=now+c.clearPeriod end
            r.confirmed=(r.confirmedUntil or 0)>now
            r.x,r.y=o.x,o.y;r.seen=now;r.updated=now
            intent.threats[o.id]=r
        end
    end
    local ordered={}
    for id,r in pairs(intent.threats) do ordered[#ordered+1]={id=id,record=r} end
    table.sort(ordered,function(a,b) return a.record.score==b.record.score and a.id<b.id or a.record.score>b.record.score end)
    for i=c.maxThreats+1,#ordered do intent.threats[ordered[i].id]=nil end
end
function T.summary(intent,now)
    local count,confirmed,score,primary=0,0,0,nil
    for id,r in pairs(intent.threats) do
        if r.score>0 then count=count+1 end
        if (r.confirmedUntil or 0)>now then confirmed=confirmed+1 end
        if r.score>score or (r.score==score and (not primary or id<primary)) then score,primary=r.score,id end
    end
    return {count=count,confirmed=confirmed,score=score,primary=primary}
end
function T.transition(intent,now,health,config)
    local c=config or Protect.tactical
    local s=T.summary(intent,now)
    local desired=s.score>=c.contactThreshold and s.confirmed>0 and 'CONTACT'
        or s.score>=c.threatThreshold and 'THREAT' or s.score>=c.suspicionThreshold and 'SUSPICIOUS' or 'NORMAL'
    if desired=='CONTACT' then intent.contactSince=intent.contactSince or now else intent.contactSince=nil end
    if desired=='CONTACT' or desired=='THREAT' then intent.lastDanger=now end
    local extraction=intent.manualExtraction or intent.posture=='emergency' or (c.automaticExtraction and now>(intent.suppressedUntil or -1) and s.confirmed>0
        and ((health or 200)<=c.extractionHealth or s.confirmed>=2 or now-(intent.contactSince or now)>=c.extractionSustain))
    if extraction then desired='EXTRACTION'
    elseif intent.state=='EXTRACTION' or (intent.state=='CONTACT' and desired~='CONTACT')
        or (intent.state=='THREAT' and desired~='CONTACT' and desired~='THREAT') then
        if now-intent.lastDanger<c.clearPeriod then desired=intent.state
        else desired='RECOVERY' end
    elseif intent.state=='RECOVERY' and (desired=='NORMAL' or desired=='SUSPICIOUS') and now-intent.changedAt<c.recoveryPeriod then desired='RECOVERY' end
    if desired=='NORMAL' and intent.posture=='alert' then desired='SUSPICIOUS' end
    if desired~=intent.state then intent.state=desired;intent.changedAt=now;intent.revision=intent.revision+1 end
    return s
end
function T.roles(intent,guards,driver,now,config)
    local c=config or Protect.tactical
    local live,targets={},{}
    for _,net in ipairs(guards) do if net~=driver then live[#live+1]=net end end
    for id,r in pairs(intent.threats) do if (r.confirmedUntil or 0)>now then targets[#targets+1]={id=id,score=r.score} end end
    table.sort(targets,function(a,b) return a.score==b.score and a.id<b.id or a.score>b.score end)
    local close=math.min(#live,c.minimumCloseGuards)
    local recalling=(intent.command=='regroup' or intent.command=='recall') and now<(intent.commandUntil or 0) or intent.command=='vehicles'
    local engage=not recalling and (intent.state=='CONTACT' or intent.state=='EXTRACTION') and (#targets>0 and math.max(0,#live-close) or 0) or 0
    intent.roles={}
    local protectionCount=#live-engage
    for i,net in ipairs(live) do
        if i>protectionCount then intent.roles[net]={role='engagement',target=targets[(i-protectionCount-1)%#targets+1].id,slot=i}
        else intent.roles[net]={role=i==1 and 'principal' or i<=close and 'close' or 'flank',slot=i,count=protectionCount} end
    end
    if driver then intent.roles[driver]={role='driver'} end
    return intent.roles
end
function T.offset(formation,slot,count,spacing,loose)
    local s=formation=='loose' and loose or formation=='close' and spacing*.65 or spacing
    if formation=='column' then return (slot%2==0 and .35 or -.35),-slot*s end
    if formation=='left' or formation=='right' then return (formation=='left' and -1 or 1)*s,-(slot-(count+1)/2)*s end
    if formation=='box' then local ring=1+math.floor((slot-1)/4);return (slot%2==0 and 1 or -1)*s*ring,((slot-1)%4<2 and 1 or -1)*s*ring end
    local points={{0,s},{-s,0},{s,0},{0,-s}}
    local p=points[(slot-1)%4+1];local ring=1+math.floor((slot-1)/4)
    return p[1]*ring,p[2]*ring
end
function T.world(x,y,heading,ox,oy)
    local r=math.rad(heading)
    return x+ox*math.cos(r)-oy*math.sin(r),y+ox*math.sin(r)+oy*math.cos(r)
end
-- Feed forward the moving slot, including its rotation around the VIP. Bound
-- prediction so sharp turns or noisy remote velocities cannot fling the target.
function T.pursuit(x,y,heading,vx,vy,angular,seconds)
    local angle=math.rad(heading)
    local wx,wy=x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle)
    local dx,dy=(vx-wy*angular)*seconds,(vy+wx*angular)*seconds
    local length=math.sqrt(dx*dx+dy*dy)
    if length>1.25 then dx,dy=dx*1.25/length,dy*1.25/length end
    return x+dx*math.cos(angle)+dy*math.sin(angle),y-dx*math.sin(angle)+dy*math.cos(angle)
end
function T.shield(x,y,tx,ty,slot,count,spacing)
    local dx,dy=tx-x,ty-y;local length=math.sqrt(dx*dx+dy*dy)
    if length<.01 then return x,y end
    dx,dy=dx/length,dy/length
    local lateral=(slot-(count+1)/2)*spacing
    return x+dx*spacing-dy*lateral,y+dy*spacing+dx*lateral
end
function T.direction(previous,dx,dy)
    if dx*dx+dy*dy<.01 then return previous or {x=0,y=1} end
    local angle=math.atan(dy,dx)
    if previous then
        local start=math.atan(previous.y,previous.x)
        local delta=math.atan(math.sin(angle-start),math.cos(angle-start))
        angle=start+math.max(-math.pi/4,math.min(math.pi/4,delta))
    end
    return {x=math.cos(angle),y=math.sin(angle)}
end
-- Every owner uses the same ordered guards/vehicles to reserve distinct seats.
function T.seats(guards,vehicles,driver)
    local assignments,cursor={},1
    for _,v in ipairs(vehicles) do
        for _,seat in ipairs(v.freeSeats) do
            while guards[cursor]==driver do cursor=cursor+1 end
            if not guards[cursor] then return assignments end
            assignments[guards[cursor]]={vehicle=v.net,seat=seat};cursor=cursor+1
        end
    end
    return assignments
end
-- Client candidates contain only measured facts; the server independently validates IDs/membership.
function T.vehicle(candidates)
    local chosen
    for _,v in ipairs(candidates) do
        if v.alive and v.ground and v.seat and v.sameSession and v.sameBucket and v.model~='rhino' then
            if not chosen or v.priority<chosen.priority or (v.priority==chosen.priority and v.distance<chosen.distance) then chosen=v end
        end
    end
    return chosen
end
