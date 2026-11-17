-- Plain visual roster contracts; no secure execution or game-world claim.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1;assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local secret={}
issecretvalue=function(value) return rawequal(value,secret) end
InCombatLockdown=function() return true end
local forbidden=0
for _,key in ipairs({"CreateFrame","TargetUnit","FocusUnit","CastSpellByName","SetRaidTarget","SetBinding","SetOverrideBindingClick","SetCVar"}) do
    _G[key]=function() forbidden=forbidden+1;error("visual roster called "..key) end
end
local NS={};local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
local live={}
NS.ReadUnit=function(unit,side)
    local value=live[unit]
    if value and value.side==side then return value end
end
UnitGUID=function(unit) return live[unit] and live[unit].guid end
assert(loadfile(root.."EnemyDisplay.lua"))("MyForeverTargets",NS)
local display=NS.EnemyDisplay
local function put(unit,guid)
    live[unit]={side="enemy",guid=guid,name="同名怪物"}
end
local function unique(limit)
    local seen={}
    for i=1,20 do
        local data=display.Get(i)
        if data then
            eq(i<=limit,true,"visual slot stays within the selected capacity")
            eq(seen[data.guid],nil,"one GUID occupies only one visual cell")
            seen[data.guid]=true
        end
    end
end
eq(display.active,false,"module stays inactive until combat roster update")
eq(display.Get(1),nil,"empty initial roster has no fabricated unit")
put("nameplate1","A");put("nameplate2","B");put("target","A")
display.Update({"nameplate1","target","nameplate2"},5,{})
eq(display.active,true,"combat update activates visual roster")
eq(display.Get(1).guid,"A","empty prepared roster admits first combat enemy")
eq(display.Get(2).guid,"B","two same-name creatures keep different GUIDs")
eq(display.Get(3),nil,"aliases do not create duplicate cells")
unique(5)
-- A still-visible prepared cell takes priority over newly sorted candidates.
display.Reset()
put("nameplate3","C")
local rows={{unit="nameplate2",expectedGUID="B"},{unit="nameplate1",expectedGUID="A"}}
local originalUnit,originalGUID=rows[1].unit,rows[1].expectedGUID
display.Update({"nameplate3","nameplate1","nameplate2"},5,rows)
eq(display.Get(1).guid,"B","first update preserves the prepared cell's live identity")
eq(display.Get(2).guid,"A","first update preserves the second prepared cell")
eq(display.Get(3).guid,"C","new enemy fills an empty cell")
eq(rows[1].unit,originalUnit,"visual update never changes the prepared unit")
eq(rows[1].expectedGUID,originalGUID,"visual update never changes the prepared GUID")
-- Sorting changes do not move existing visual cells. Alias reuse does not move
-- an old identity when it remains readable through another current alias.
put("nameplate2","D");put("boss1","B")
display.Update({"nameplate2","nameplate3","boss1","nameplate1"},5,rows)
eq(display.Get(1).guid,"B","old visual identity survives its original nameplate alias reuse")
eq(display.Get(1).unit,"boss1","retained identity uses a newly observed alias")
eq(display.Get(2).guid,"A","other visual identities keep their own slot")
eq(display.Get(4).guid,"D","replacement creature gets a separate empty slot")
unique(5)
-- Prefer the valid original display alias even when collection picked another.
put("nameplate4","B")
display.Update({"nameplate4","nameplate1","nameplate3","nameplate2"},5,rows)
eq(display.Get(1).unit,"boss1","live existing visual alias stays stable")
live.boss1=nil;live.nameplate4=nil
live.nameplate1=nil;live.target=nil
-- The two departed creatures disappear; no cached fake health card survives.
display.Update({"nameplate2","nameplate3"},5,rows)
eq(display.Get(1),nil,"a departed creature is removed from its visual cell")
eq(display.Get(2),nil,"a departed second identity leaves an empty cell")
eq(display.Get(3).guid,"C","a retained creature is not shuffled into earlier holes")
put("nameplate5","E")
display.Update({"nameplate2","nameplate3","nameplate5"},5,rows)
eq(display.Get(1).guid,"E","newly observed enemy fills the first available hole")
unique(5)
for _,limit in ipairs({5,10,20}) do
    display.Reset();local tokens={}
    for i=1,25 do local unit="nameplate"..i;put(unit,"GUID-"..i);tokens[i]=unit end
    display.Update(tokens,limit,{})
    local count=0;for i=1,20 do if display.Get(i) then count=count+1 end end
    eq(count,limit,"selected capacity bounds combat visuals")
    unique(limit)
end
-- Unreadable, malformed and raced identities fail closed without API writes.
do
    display.Reset();put("nameplate1","Held-A")
    local originalCombat=InCombatLockdown
    InCombatLockdown=function() return true end
    local activeIndex=1
    local heldRow={unit="nameplate1",expectedGUID="Held-A",GetAttribute=function(_,key)
        if key=="combat-row-index" or key=="mfch-index" then return 1 end
    end}
    local mode="public"
    local function ownerRead()
        if mode=="error" then error("restricted getter") end
        if mode=="secret" then return secret end
        return activeIndex
    end
    NS.CombatCast={owner={GetAttribute=ownerRead}}
    display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1).guid,"Held-A","active native name owner retains its own prepared identity")
    -- A shield show/non-motion leave only clears ordinary Lua hover state;
    -- the old native owner remains. A new identity must not occupy this cell.
    NS.HoveredTile=nil;put("nameplate1","Replacement-B")
    display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1),nil,"non-motion shield transition never displays another GUID under a retained native owner")
    put("boss1","Held-A")
    display.Update({"nameplate1","boss1"},1,{heldRow})
    eq(display.Get(1),nil,"a hot native owner with a reused prepared alias stays empty even if the old GUID has another alias")
    live.boss1=nil;activeIndex=nil
    display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1).guid,"Replacement-B","real native motion leave clearing owner releases the empty cell")
    for _,failure in ipairs({"error","secret"}) do
        display.Reset();mode=failure
        display.Update({"nameplate1"},1,{heldRow})
        eq(display.Get(1),nil,"unknown protected name-owner index conservatively reserves prepared cell")
    end
    mode="public";activeIndex=1;NS.CombatCast=nil
    NS.CombatHover={owner={GetAttribute=ownerRead}}
    display.Reset();display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1),nil,"fixed-unit protected hover owner also prevents replacement")
    activeIndex=nil;display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1).guid,"Replacement-B","public fixed-owner nil permits a new visual identity")
    activeIndex=1;heldRow.GetAttribute=function() error("row getter unavailable") end
    display.Reset();display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1),nil,"unknown prepared row index cannot disprove active ownership")
    heldRow.GetAttribute=function() return secret end
    display.Reset();display.Update({"nameplate1"},1,{heldRow})
    eq(display.Get(1),nil,"secret prepared row index cannot release native ownership")
    NS.CombatHover=nil
    InCombatLockdown=originalCombat
end
display.Reset();put("nameplate1",secret);put("nameplate2","");live.nameplate3={side="friendly",guid="F"}
display.Update({"nameplate1","nameplate2","nameplate3",secret,"bad;target"},5,{})
eq(display.Get(1),nil,"secret/empty/invalid/friendly identities never enter enemy cells")
put("nameplate1","Before")
local readGUID=UnitGUID
UnitGUID=function(unit) if unit=="nameplate1" then return "After" end return readGUID(unit) end
display.Update({"nameplate1"},5,{})
eq(display.Get(1),nil,"identity changing across the data read is rejected")
UnitGUID=readGUID
for _,index in ipairs({0,-1,1.5,21,secret}) do eq(display.Get(index),nil,"invalid slot lookup fails closed") end
display.Reset()
eq(display.active,false,"out-of-combat reset deactivates combat visuals")
eq(next(display.slots),nil,"reset removes all retained combat identity")
eq(forbidden,0,"visual roster has no frames, target, cast, marking, CVar or binding writes")

-- Restricted plate entries are addresses with a lifecycle, never GUIDs.
do
    display.Reset();display.OnEvent("PLAYER_ENTERING_WORLD")
    local restricted={nameplate70=true,nameplate71=true}
    local function opaque() return setmetatable({},{__tostring=function() error("raw identity serialized") end}) end
    local rawName,rawGUID=opaque(),opaque()
    NS.ReadRestrictedEnemyVisual=function(unit)
        if restricted[unit] then return {unit=unit,restrictedIdentity=true,healthCurrent=77,healthMax=100} end
    end
    local combat=false
    InCombatLockdown=function() return combat end
    put("nameplate1","Public-A")
    local prepared={{unit="nameplate1",expectedGUID="Public-A"}}
    display.Update({"nameplate1"},5,prepared,{"nameplate70","nameplate70","nameplate71"})
    eq(display.Get(1).guid,"Public-A","prepared public cell has priority outside combat")
    local first,second=display.Get(2),display.Get(3)
    eq(first.unit,"nameplate70","first restricted token fills a remaining cell")
    eq(first.restrictedIdentity,true,"restricted cell explicitly has no actionable identity")
    eq(first.guid,nil,"restricted token never becomes a synthetic GUID")
    eq(first.name,nil,"restricted token never caches a name")
    eq(first.nativeName,nil,"restricted token never caches a raw native name")
    eq(first.healthCurrent,nil,"restricted token never caches native health")
    eq(second.unit,"nameplate71","restricted dedup uses its own token addresses")
    eq(display.Get(4),nil,"repeated anonymous token occupies one cell")
    eq(display.IsCurrent(first),true,"created entry belongs to the current token lifecycle")
    display.Reset()
    eq(display.IsCurrent(first),true,"ordinary out-of-combat reset preserves lifecycle epochs")
    display.Update({},5,{}, {"nameplate70"})
    eq(display.Get(1).tokenEpoch,first.tokenEpoch,"reset does not forge a newer plate lifecycle")
    local previous=display.Get(1)
    put("nameplate2","Public-B")
    display.Update({"nameplate2","nameplate1"},5,{{unit="nameplate2",expectedGUID="Public-B"}}, {"nameplate70"})
    eq(display.Get(1).guid,"Public-B","new prepared public action displaces an old anonymous slot")
    eq(display.Get(1).restrictedIdentity,nil,"prepared public cell remains public")
    eq(display.Get(3).unit,"nameplate70","anonymous card moves behind both public identities")
    display.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate70")
    eq(display.IsCurrent(previous),false,"removed token invalidates previously captured entries")
    local removedMeta=display.LifecycleState("nameplate70")
    eq(removedMeta.validToken,true,"diagnostic metadata recognizes a plain plate address")
    eq(removedMeta.tombstoned,true,"metadata identifies the removed-token block")
    eq(removedMeta.currentEpoch>previous.tokenEpoch,true,"metadata exposes the advanced public epoch")
    display.Reset();display.Update({},5,{}, {"nameplate70"})
    eq(display.Get(1),nil,"OOC reset cannot resurrect a removed token while native existence lags")
    display.OnEvent("NAME_PLATE_UNIT_ADDED","nameplate70")
    display.Update({},5,{}, {"nameplate70"})
    local added=display.Get(1)
    eq(display.IsCurrent(added),true,"explicit added event permits a new lifecycle")
    eq(added.tokenEpoch>previous.tokenEpoch,true,"new address lifecycle has a larger public epoch")
    eq(display.IsCurrent(previous),false,"old entry stays invalid after the same token reappears")
    display.Update({},5,{}, {})
    eq(display.Get(1),nil,"empty current restricted candidates cannot retain stale anonymous entries")
    display.OnEvent("PLAYER_LEAVING_WORLD")
    eq(display.active,false,"leaving world clears the active display roster")
    eq(display.IsCurrent(added),false,"leaving world invalidates captured entries")
    eq(display.LifecycleState("nameplate70").worldActive,false,"metadata identifies leaving world")
    eq(display.LifecycleState("nameplate70").epochKnown,false,"world change clears address epochs")
    display.Reset();display.Update({},5,{}, {"nameplate70"})
    eq(display.Get(1),nil,"Reset cannot reopen restricted rendering while outside the world")
    display.OnEvent("PLAYER_ENTERING_WORLD");display.Update({},5,{}, {"nameplate70"})
    local world=display.Get(1)
    eq(display.IsCurrent(world),true,"new world permits a fresh address lifecycle")
    eq(world.tokenEpoch>added.tokenEpoch,true,"world change cannot reuse the old epoch")
    local restrictedReader=NS.ReadRestrictedEnemyVisual
    NS.ReadRestrictedEnemyVisual=function() error("metadata must not read native identity") end
    local meta=display.LifecycleState("nameplate70")
    eq(meta.currentEpoch,world.tokenEpoch,"metadata uses exactly the existing lifecycle generation")
    eq(meta.worldActive,true,"metadata reports current world state")
    eq(meta.tombstoned,false,"live address has no removed-token block")
    meta.currentEpoch=-1
    eq(display.LifecycleState("nameplate70").currentEpoch,world.tokenEpoch,"returned metadata is a detached copy")
    eq(display.IsCurrent(world),true,"diagnostic access never invalidates a live visual entry")
    eq(display.LifecycleState("nameplate999").epochKnown,false,"querying a new address does not initialize an epoch")
    eq(display.LifecycleState("nameplate999").currentEpoch,nil,"unknown epoch remains unknown after repeated reads")
    eq(display.LifecycleState("party1target").validToken,false,"compound unit aliases are excluded from lifecycle metadata")
    eq(display.LifecycleState(secret).validToken,false,"secret input is rejected without formatting")
    NS.ReadRestrictedEnemyVisual=restrictedReader
    -- In combat a native owner may retain its old key binding after a
    -- non-motion shield transition. Restricted entries may not fill that slot.
    combat=true;display.Reset();put("nameplate1","Reused")
    local ownerIndex=1
    local held={unit="nameplate1",expectedGUID="Before",GetAttribute=function() return 1 end}
    NS.CombatCast={owner={GetAttribute=function() return ownerIndex end}}
    display.Update({},5,{held},{"nameplate70"})
    eq(display.Get(1),nil,"hot protected owner reserves its reused cell against anonymous content")
    eq(display.Get(2).restrictedIdentity,true,"restricted enemy can use a different free cell")
    ownerIndex=nil;display.Update({},5,{held},{"nameplate70","nameplate71"})
    eq(display.Get(1).unit,"nameplate71","public owner nil releases the reserved empty cell")
    NS.CombatCast.owner.GetAttribute=function() return secret end
    display.Reset();display.Update({},5,{held},{"nameplate70"})
    eq(display.Get(1),nil,"secret protected owner still blocks anonymous replacement")
    NS.CombatCast=nil;combat=false
    NS.CombatCast={owner={GetAttribute=function() return 1 end}}
    local clearedRow={GetAttribute=function() return nil end}
    display.Reset();display.Update({},5,{clearedRow},{"nameplate70"})
    eq(display.Get(1).restrictedIdentity,true,"inactive out-of-combat owner index does not reserve a disarmed cell")
    NS.CombatCast=nil
    display.Reset();display.Update({},5,{held},{"nameplate70"})
    eq(display.Get(1),nil,"held stale prepared OOC row cannot receive anonymous content before stationary combat entry")
    eq(display.Get(2).restrictedIdentity,true,"anonymous content can use another actually empty cell")
    local armedEmpty={GetAttribute=function(_,key) if key=="combat-prepared" then return true end end}
    display.Reset();display.Update({},5,{armedEmpty},{"nameplate70"})
    eq(display.Get(1),nil,"combat-prepared true blocks anonymous OOC replacement even when ordinary fields were cleared")
    armedEmpty.GetAttribute=function(_,key) if key=="mfch-ready" then return true end end
    display.Reset();display.Update({},5,{armedEmpty},{"nameplate70"})
    eq(display.Get(1),nil,"fixed-unit readiness blocks anonymous OOC replacement")
    armedEmpty.GetAttribute=function() return secret end
    display.Reset();display.Update({},5,{armedEmpty},{"nameplate70"})
    eq(display.Get(1),nil,"secret safety attributes conservatively reserve OOC cell")
    armedEmpty.GetAttribute=function() error("attribute unavailable") end
    display.Reset();display.Update({},5,{armedEmpty},{"nameplate70"})
    eq(display.Get(1),nil,"failed safety attribute getter conservatively reserves OOC cell")
    put("nameplate2","New-Public")
    display.Reset();display.Update({"nameplate2"},5,{held},{"nameplate70"})
    eq(display.Get(1),nil,"held stale OOC action also cannot inherit a different public visual identity")
    display.Reset();display.Update({},5,{}, {"target","party1",secret,"nameplate0","bad"})
    eq(display.Get(1),nil,"restricted display accepts no general unit aliases or malformed tokens")
    for _,limit in ipairs({5,10,20}) do
        local tokens={};restricted={}
        for i=1,25 do local unit="nameplate"..(i+60);tokens[i]=unit;restricted[unit]=true end
        display.Reset();display.Update({},limit,{},tokens)
        local count=0
        for i=1,20 do
            local entry=display.Get(i)
            if entry then
                count=count+1;eq(entry.guid,nil,"anonymous capacity never fabricates an identity")
                for key,value in pairs(entry) do
                    eq(key=="unit" or key=="restrictedIdentity" or key=="tokenEpoch",true,"entry stores only public token lifecycle metadata")
                    eq(rawequal(value,rawName) or rawequal(value,rawGUID),false,"entry has no raw name/GUID cache")
                end
            end
        end
        eq(count,limit,"anonymous list obeys 5/10/20 capacity")
    end
    display.Reset();NS.ReadRestrictedEnemyVisual=nil
end
print("Targets enemy display simulated checks: "..checks.."; real combat visibility remains an in-game check")
