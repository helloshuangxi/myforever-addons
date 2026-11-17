-- Restricted visual data contracts. The sinks below model supported native
-- calls; passing this test does not prove real client rendering or input.
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function forbidden() error("restricted value used outside native sink") end
local secretMeta={__tostring=forbidden,__concat=forbidden,__eq=forbidden,
    __lt=forbidden,__le=forbidden,__len=forbidden,__index=forbidden,
    __add=forbidden,__sub=forbidden,__mul=forbidden,__div=forbidden,__mod=forbidden,__pow=forbidden}
local hiddenName=setmetatable({},secretMeta)
local hiddenGUID=setmetatable({},secretMeta)
local hiddenCurrent=setmetatable({},secretMeta)
local hiddenMaximum=setmetatable({},secretMeta)
local originalType=type
type=function(value)
    if rawequal(value,hiddenCurrent) or rawequal(value,hiddenMaximum) then return "number" end
    return originalType(value)
end
local function isHidden(value)
    return rawequal(value,hiddenName) or rawequal(value,hiddenGUID)
        or rawequal(value,hiddenCurrent) or rawequal(value,hiddenMaximum)
end
issecretvalue=isHidden
local units,hooks,reads={},{},{}
local function api(key,unit,default)
    reads[key]=(reads[key] or 0)+1
    local u=units[unit]
    if hooks[key] then return hooks[key](u,unit,reads[key]) end
    if u and u[key]~=nil then return u[key] end
    return default
end
UnitExists=function(unit) return api("exists",unit,false) end
UnitGUID=function(unit) return api("guid",unit) end
UnitName=function(unit) return api("name",unit) end
UnitIsPlayer=function(unit) return api("player",unit) end
UnitCanAttack=function(_,unit) return api("attack",unit) end
UnitCanAssist=function(_,unit) return api("assist",unit,false) end
UnitIsVisible=function(unit) return api("visible",unit,true) end
UnitClass=function(unit) return api("className",unit,"法师"),api("classToken",unit,"MAGE") end
UnitHealth=function(unit) return api("health",unit,50) end
UnitHealthMax=function(unit) return api("maximum",unit,100) end
UnitPowerType=function(unit) return api("powerType",unit,0),api("powerToken",unit,"MANA") end
UnitPower=function(unit) return api("power",unit,20) end
UnitPowerMax=function(unit) return api("powerMax",unit,100) end
UnitIsDeadOrGhost=function(unit) return api("dead",unit,false) end
UnitIsConnected=function(unit) return api("connected",unit,true) end
InCombatLockdown=function() return true end
SetCVar=function() error("visual reader must not write settings") end
TargetUnit=function() error("visual reader must not target") end
FocusUnit=function() error("visual reader must not set focus") end
SetRaidTarget=function() error("visual reader must not mark") end
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Units.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
local function setup(values)
    hooks,reads={},{}
    local u={exists=true,guid=hiddenGUID,name=hiddenName,player=false,attack=true,
        health=hiddenCurrent,maximum=hiddenMaximum,power=hiddenCurrent,powerMax=hiddenMaximum}
    for key,value in pairs(values or {}) do u[key]=value end
    units={nameplate1=u}
    return u
end
local forbiddenFields={name=true,nativeName=true,guid=true,targetName=true,target=true,
    expectedGUID=true,displayGUID=true,rawName=true,rawGUID=true}
local function assertPayload(data,why)
    eq(type(data),"table",why.." payload exists")
    eq(data.unit,"nameplate1",why.." unit remains display address")
    eq(data.restrictedIdentity,true,why.." restricted identity is explicit")
    for key in pairs(forbiddenFields) do eq(data[key],nil,why.." excludes "..key) end
    for key,value in pairs(data) do
        if isHidden(value) then
            eq(key=="healthCurrent" or key=="healthMax" or key=="powerCurrent" or key=="powerMax",true,
                why.." only numeric sink fields may contain restricted values")
            eq(rawequal(value,hiddenName) or rawequal(value,hiddenGUID),false,why.." identity never escapes")
        end
    end
end

setup()
local data=NS.ReadRestrictedEnemyVisual("nameplate1")
assertPayload(data,"two restricted identity fields")
eq(data.player,false,"false player classification is a valid NPC")
eq(data.className,"怪物","NPC classification is a fixed public label")
eq(data.color.r,1,"NPC color is public fixed enemy color")
eq(data.health,nil,"restricted numbers never become Lua health percentages")
eq(data.healthAvailable,true,"restricted numbers remain available to native status bar")
eq(rawequal(data.healthCurrent,hiddenCurrent),true,"raw health preserved for native sink")
eq(rawequal(data.healthMax,hiddenMaximum),true,"raw maximum preserved for native sink")
eq(data.powerRatio,nil,"restricted power does not enter Lua arithmetic")
eq(data.powerAvailable,true,"restricted power remains available to native sink")
eq(data.powerToken,"MANA","resource kind uses public API metadata")
eq(data.offline,false,"public connected state preserves false offline")
eq(data.dead,false,"public alive state preserves false dead")
local rejected,reason=NS.ReadUnit("nameplate1","enemy")
eq(rejected,nil,"normal action data still rejects restricted identity")
eq(reason,"guid_unreadable","normal GUID guard was not changed")
NS.Nameplates={nameplate1=true}
local normal=NS.Collect("enemy","enemy",20)
eq(#normal,0,"normal collection never receives a restricted visual record")

for _,identity in ipairs({{guid=hiddenGUID,name="公开怪物名"},
    {guid="Creature-public",name=hiddenName},{guid=hiddenGUID,name=hiddenName}}) do
    setup(identity)
    assertPayload(NS.ReadRestrictedEnemyVisual("nameplate1"),"proven restricted identity combination")
end
setup({guid="Creature-public",name="公开怪物名"})
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"fully public units use the existing normal path")
for _,missing in ipairs({"guid","name"}) do
    local u=setup();u[missing]=nil
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"ordinary missing "..missing.." is not a drawable restricted identity")
    u=setup();u[missing]=""
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"empty public "..missing.." does not masquerade as restricted")
    setup();hooks[missing]=function() error("identity API failure") end
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"throwing "..missing.." API is rejected")
end
for _,bad in ipairs({false,1,{}}) do
    setup({guid=bad})
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"invalid public GUID rejected")
    setup({name=bad})
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"invalid public name rejected")
end
for _,key in ipairs({"exists","player","attack"}) do
    local u=setup();u[key]=nil
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"missing public qualification rejected: "..key)
    setup({[key]=hiddenGUID})
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"restricted qualification rejected: "..key)
    setup();hooks[key]=function() error("qualification failed") end
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"throwing qualification rejected: "..key)
end
setup({exists=false})
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"absent units rejected")
setup({attack=false,assist=true})
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"friendly units rejected")
for _,token in ipairs({"target","focus","boss1","party1target","nameplate0","nameplate01",
    "nameplate1001","nameplate1target","forbiddennameplate1","nameplate1\n","nameplate+1"}) do
    local u=setup();units[token]=u
    eq(NS.ReadRestrictedEnemyVisual(token),nil,"only tight native nameplate tokens accepted: "..token)
    eq(reads.exists,nil,"invalid token rejected before any unit API call")
end
setup()
eq(NS.ReadRestrictedEnemyVisual(nil),nil,"nil token rejected")
eq(NS.ReadRestrictedEnemyVisual(hiddenName),nil,"restricted token rejected without string operations")

setup({player=true,className="法师",classToken="MAGE"})
data=NS.ReadRestrictedEnemyVisual("nameplate1")
eq(data.player,true,"hostile players remain eligible when attackable")
eq(data.className,"法师","public class name can be displayed")
eq(data.classToken,"MAGE","public class token can choose color")
eq(data.color.b,.92,"player uses the public class palette")
setup({player=true,className=hiddenName,classToken=hiddenGUID,dead=hiddenGUID,connected=hiddenGUID})
data=NS.ReadRestrictedEnemyVisual("nameplate1")
eq(data.className,"玩家","restricted class name uses a fixed fallback")
eq(data.classToken,"","restricted class token is not returned")
eq(data.color.r,1,"restricted class cannot index class colors")
eq(data.dead,nil,"unknown death state is not falsely called alive")
eq(data.offline,nil,"unknown connection is not falsely called online")
setup({health=25,maximum=100,power=35,powerMax=100})
data=NS.ReadRestrictedEnemyVisual("nameplate1")
eq(data.health,.25,"existing helper may compute a public ratio")
eq(data.powerRatio,.35,"existing helper may compute a public power ratio")
setup({powerType=hiddenCurrent})
eq(NS.ReadRestrictedEnemyVisual("nameplate1").powerAvailable,false,"unknown resource kind never guesses mana")
for _,key in ipairs({"health","maximum","power","powerMax"}) do
    setup();hooks[key]=function() error("numeric API unavailable") end
    data=NS.ReadRestrictedEnemyVisual("nameplate1")
    eq(data~=nil,true,"missing numeric data does not invent an identity failure")
    local available
    if key=="health" or key=="maximum" then available=data.healthAvailable else available=data.powerAvailable end
    eq(available,false,"numeric API error clears the appropriate display availability")
end

-- Qualification is rechecked after status/class APIs, without comparing any
-- raw secret GUID or name. Epoch checks remain the display caller's job.
for _,key in ipairs({"exists","attack"}) do
    setup();hooks.health=function(u) u[key]=false;return hiddenCurrent end
    eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"qualification change during status read rejected: "..key)
end
setup();hooks.health=function(u) u.player=true;return hiddenCurrent end
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"player classification change rejects mixed visual metadata")
setup();hooks.health=function(u) u.guid="Creature-public";u.name="公开名字";return hiddenCurrent end
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"restriction disappearing during read does not return stale restricted metadata")
setup();hooks.health=function(u) u.name=nil;return hiddenCurrent end
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"name disappearing during status read rejected")

-- The only string出口 is native SetText. No getter, formatter, logger,
-- arbitrary table or caller receives the raw restricted name.
local sinkCalls,sinkLast=0,nil
local sink={SetText=function(_,value) sinkCalls=sinkCalls+1;sinkLast=value end,
    GetText=function() error("restricted text must not be read back") end,
    GetStringWidth=function() error("restricted text must not size layout") end}
setup();sinkCalls=0
eq(NS.SetRestrictedEnemyName(sink,"nameplate1"),true,"supported native sink accepts the raw restricted name")
eq(sinkCalls,1,"successful paint performs one native text write")
eq(rawequal(sinkLast,hiddenName),true,"raw name reaches native sink unchanged")
setup({name="公开名字"});sinkCalls=0
eq(NS.SetRestrictedEnemyName(sink,"nameplate1"),true,"restricted GUID can accompany a public name")
eq(sinkLast,"公开名字","public name also flows directly to the native sink")
setup({guid="Creature-public",name="公开名字"});sinkCalls=0
eq(NS.SetRestrictedEnemyName(sink,"nameplate1"),false,"newly public unit does not paint through restricted path")
eq(sinkLast,"","failed qualification clears stale text")
eq(sinkCalls,1,"rejection only performs fixed safe clear")
setup();hooks.name=function() error("private identity error text") end;sinkCalls=0
eq(NS.SetRestrictedEnemyName(sink,"nameplate1"),false,"name API failure cannot escape to UI")
eq(sinkLast,"","API error clears text without copying its error")
setup();sinkCalls=0
local rejectingSink={SetText=function(_,value)
    sinkCalls=sinkCalls+1
    if isHidden(value) then error("native renderer rejected secret input") end
    sinkLast=value
end}
eq(NS.SetRestrictedEnemyName(rejectingSink,"nameplate1"),false,"native sink rejection reports failure")
eq(sinkLast,"","native sink rejection is followed by fixed empty text")
eq(sinkCalls,2,"failed paint performs only the raw attempt and safe clear")
setup();sinkCalls=0
local changingSink={SetText=function(_,value)
    sinkCalls=sinkCalls+1;sinkLast=value
    if isHidden(value) then units.nameplate1.attack=false end
end}
eq(NS.SetRestrictedEnemyName(changingSink,"nameplate1"),false,"post-paint public qualification is rechecked")
eq(sinkLast,"","post-paint failure clears the painted secret")
eq(sinkCalls,2,"qualification change does not leave old text on screen")
setup()
eq(NS.SetRestrictedEnemyName(nil,"nameplate1"),false,"missing sink fails safely")
eq(NS.SetRestrictedEnemyName(hiddenName,"nameplate1"),false,"restricted sink object is not indexed")
eq(NS.SetRestrictedEnemyName({},"nameplate1"),false,"missing native method fails safely")
eq(NS.SetRestrictedEnemyName(setmetatable({}, {__index=function() error("blocked frame") end}),"nameplate1"),false,
    "throwing native method access fails safely")
eq(NS.SetRestrictedEnemyName({SetText=function() error("write always denied") end},"nameplate1"),false,
    "failure of both raw write and safe clear does not throw")

local checker=issecretvalue
setup();issecretvalue=nil
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"missing secret predicate is not positive restriction proof")
issecretvalue=function(value) if isHidden(value) then error("restriction check failed") end;return false end
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"predicate exception is not positive restriction proof")
issecretvalue=function(value) if isHidden(value) then return 1 end;return false end
eq(NS.ReadRestrictedEnemyVisual("nameplate1"),nil,"nonboolean predicate result is not positive proof")
issecretvalue=checker

-- Discovery only filters the existing engine-derived provider; it neither
-- invents aliases nor attempts to deduplicate unknown monster identities.
setup()
units.nameplate2={exists=true,guid=hiddenGUID,name=hiddenName,player=false,attack=true}
units.nameplate3={exists=true,guid="Creature-public",name="公开名字",player=false,attack=true}
local originalProvider=NS.NameplateTokens
NS.NameplateTokens=function()
    return {"target","nameplate1","nameplate1","nameplate2","nameplate3","nameplate0",hiddenName}
end
local tokens=NS.RestrictedEnemyTokens()
eq(#tokens,2,"only proven restricted real nameplate tokens are returned")
eq(tokens[1],"nameplate1","provider order is retained")
eq(tokens[2],"nameplate2","same opaque GUID/name does not merge different display addresses")
NS.NameplateTokens=function() error("engine plate list unavailable") end
eq(#NS.RestrictedEnemyTokens(),0,"provider failure is isolated")
NS.NameplateTokens=function() return hiddenName end
eq(#NS.RestrictedEnemyTokens(),0,"restricted provider result is not iterated")
NS.NameplateTokens=originalProvider
print("Targets restricted enemy data simulated checks: "..checks)
