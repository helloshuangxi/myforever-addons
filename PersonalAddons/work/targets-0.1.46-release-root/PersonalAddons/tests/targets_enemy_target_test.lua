-- Display-data simulation only. Does not prove the client exposes every
-- nameplate target relationship or render native secret text.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function forbiddenSecretUse() error("secret value was operated on") end
local secret=setmetatable({}, {__tostring=forbiddenSecretUse,__concat=forbiddenSecretUse})
local secretNumber
issecretvalue=function(value) return rawequal(value,secret) or (secretNumber~=nil and value==secretNumber) end
local units,overrides,onNameRead,reads={},{},nil,{}
local function read(kind,unit,field)
    reads[#reads+1]={kind=kind,unit=unit}
    local override=overrides[kind]
    if type(override)=="function" then return override(unit) end
    if override~=nil then return override end
    return units[unit] and units[unit][field]
end
UnitGUID=function(unit) return read("guid",unit,"guid") end
UnitExists=function(unit)
    reads[#reads+1]={kind="exists",unit=unit}
    local override=overrides.exists
    if type(override)=="function" then return override(unit) end
    if override~=nil then return override end
    return units[unit]~=nil
end
UnitName=function(unit)
    local name=read("name",unit,"name")
    if onNameRead then onNameRead(unit) end
    return name
end
UnitIsPlayer=function(unit) return read("player",unit,"player") end
UnitClass=function(unit) return read("className",unit,"className"),read("class",unit,"classToken") end
UnitHealth=function(unit) return read("health",unit,"healthCurrent") end
UnitHealthMax=function(unit) return read("healthMax",unit,"healthMax") end
local writes={}
for _,api in ipairs({"TargetUnit","TargetByName","TargetNearestEnemy","ClearTarget","FocusUnit",
    "ClearFocus","CastSpellByName","CastSpellByID","CastSpell","UseAction","RunMacroText",
    "SetRaidTarget","SetBinding","SetOverrideBindingClick","CreateMacro","EditMacro"}) do
    writes[api]=0
    _G[api]=function()
        writes[api]=writes[api]+1
        error("enemy target display must not call "..api)
    end
end
local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Units.lua"))("MyForeverTargets",NS)
local function reset()
    units={nameplate1={guid="enemy-a"},
        nameplate1target={guid="victim-a",name="治疗者",player=true,className="牧师",classToken="PRIEST",
            healthCurrent=750,healthMax=1000}}
    overrides,onNameRead,reads,secretNumber={},nil,{},nil
end
local function inspect() return NS.ReadEnemyTarget("nameplate1","enemy-a") end
local function state(expected,why)
    local result=inspect()
    eq(type(result),"table",why.." returns a table")
    eq(result.state,expected,why)
    if expected~="known" then
        eq(result.name,nil,why.." clears the previous name")
        eq(result.color,nil,why.." clears the previous color")
        eq(result.healthCurrent,nil,why.." clears the previous health amount")
        eq(result.healthMax,nil,why.." clears the previous health maximum")
        eq(result.className,nil,why.." clears the previous class name")
    end
    return result
end
local function color(result,r,g,b,why)
    eq(result.color.r,r,why.." red")
    eq(result.color.g,g,why.." green")
    eq(result.color.b,b,why.." blue")
end

reset()
local result=state("known","an exposed player target is readable")
eq(result.name,"治疗者","target name is read from the child unit")
eq(result.player,true,"player target retains its public type")
eq(result.className,"牧师","target class name is exposed for its rectangle")
eq(result.classToken,"PRIEST","target class token matches the class color")
eq(result.health,.75,"target health fraction reflects the target's current amount")
eq(result.healthCurrent,750,"target health amount is preserved for the native bar")
eq(result.healthMax,1000,"target health maximum is preserved for the native bar")
eq(result.healthAvailable,true,"readable target health enables the native bar")
color(result,1,1,1,"priest target uses priest color")
eq(reads[1].unit,"nameplate1","owner is checked before relationship access")
eq(reads[#reads].unit,"nameplate1","owner is checked again after relationship access")
eq(reads[#reads].kind,"guid","last read revalidates owner identity")

units.nameplate1target={guid="victim-b",name="坦克",player=true,className="战士",classToken="WARRIOR",
    healthCurrent=1500,healthMax=3000}
result=state("known","a target change is read without cached victim data")
eq(result.name,"坦克","new victim name replaces old name")
eq(result.className,"战士","new target updates the displayed class")
eq(result.health,.5,"new target updates the displayed health")
color(result,.78,.61,.43,"warrior target uses warrior color")

for _,name in ipairs({"野猪","猎人的宠物"}) do
    units.nameplate1target={guid="npc-victim",name=name,player=false,classToken="WARRIOR"}
    result=state("known","NPC or pet targets are not filtered out")
    eq(result.name,name,"NPC or pet target name is retained")
    eq(result.player,false,"NPC or pet retains its non-player type")
    eq(result.className,"非玩家","NPC or pet does not invent a player class")
    eq(result.classToken,"","NPC or pet does not publish an irrelevant player class token")
    color(result,.82,.85,.9,"NPC or pet uses neutral color despite a class token")
end

units.nameplate1target=nil
state("absent","a disappeared target clears display data")
reset();overrides.exists=function() error("unavailable unit relation") end
state("unavailable","UnitExists API error is contained")
reset();overrides.exists=function() return nil end
state("unavailable","unknown existence is not reported absent")
reset();overrides.exists=secret
state("unavailable","secret existence is not reported absent")

for _,value in ipairs({secret,"", "\1\2|"}) do
    reset();overrides.name=value
    state("unavailable","unusable target names do not show stale text")
end
reset();overrides.name=function() return nil end
state("unavailable","missing target name is unavailable")
reset();overrides.name=function() error("name unavailable") end
state("unavailable","name API error is contained")
reset();overrides.name="|A\1B\127"
result=state("known","public names are sanitized")
eq(result.name,"AB","format and control delimiters are removed")

for _,value in ipairs({secret,"UNKNOWN_CLASS"}) do
    reset();overrides.class=value
    color(state("known","unknown or secret class keeps public target name"),.82,.85,.9,
        "unreadable class uses neutral color")
end
reset();overrides.class=function() error("class unavailable") end
color(state("known","class API error keeps public target name"),.82,.85,.9,
    "class error uses neutral color")
reset();overrides.player=secret
result=state("known","secret player identity does not block public name")
color(result,.82,.85,.9,
    "unknown player type uses neutral color")
eq(result.player,nil,"secret player type remains unknown")
eq(result.className,"未知","secret player type does not invent a class")
reset();overrides.className=secret
result=state("known","secret class name does not hide a public player")
eq(result.className,"玩家","unreadable class name uses a neutral player label")
eq(result.classToken,"PRIEST","public class token remains usable for color")

-- Health uses the same raw numeric path as main unit bars. Secret values may
-- reach StatusBar sinks, but never a calculated percentage or display string.
reset();secretNumber=750
result=state("known","secret numeric health is retained only for native rendering")
eq(result.health,nil,"secret current amount is never divided into a percentage")
eq(result.healthCurrent,750,"secret current amount is forwarded unchanged")
eq(result.healthMax,1000,"public maximum remains available")
eq(result.healthAvailable,true,"native StatusBar can receive secret numeric health")
reset();secretNumber=1000
result=state("known","secret numeric maximum is retained for native rendering")
eq(result.health,nil,"secret maximum is never divided")
eq(result.healthMax,1000,"secret maximum is forwarded unchanged")
eq(result.healthAvailable,true,"secret numeric maximum does not force a black bar")
for _,values in ipairs({{0,1000,0},{1500,1000,1},{300,1000,.3}}) do
    reset();units.nameplate1target.healthCurrent=values[1];units.nameplate1target.healthMax=values[2]
    result=inspect()
    eq(result.health,values[3],"public health percentage is clamped to the bar range")
    eq(result.healthAvailable,true,"zero or overfull current health is still a readable amount")
end
for _,entry in ipairs({{"health",-1},{"healthMax",0},{"healthMax",-1},{"health",math.huge},
    {"health",secret},{"healthMax",secret},{"health",function() return nil end},
    {"healthMax",function() error("restricted health") end}}) do
    reset();overrides[entry[1]]=entry[2]
    result=inspect()
    eq(result.state,"known","unavailable health does not hide the readable target identity")
    eq(result.healthAvailable,false,"invalid or missing health cannot render a false amount")
    eq(result.health,nil,"invalid health clears the previous percentage")
    eq(result.healthCurrent,nil,"invalid health clears the previous native amount")
    eq(result.healthMax,nil,"invalid health clears the previous native maximum")
end

reset();units.nameplate1.guid="enemy-b"
state("unavailable","an already reused owner is rejected")
eq(#reads,1,"wrong owner is rejected before reading its target")
reset();onNameRead=function() units.nameplate1.guid="enemy-b" end
state("unavailable","owner reuse during the relationship read rejects the new victim")
reset();onNameRead=function() units.nameplate1=nil end
state("unavailable","owner disappearance clears target data")
reset();overrides.guid=secret
state("unavailable","secret owner GUID cannot establish identity")
reset();overrides.guid=function() error("owner unavailable") end
state("unavailable","owner GUID API error is contained")
reset();overrides.exists=function() units.nameplate1.guid="enemy-b";return false end
state("unavailable","even an absent result belongs to the validated owner")

for _,badUnit in ipairs({"mouseover","nameplate1; /target player","nameplate1target",secret}) do
    reset()
    result=NS.ReadEnemyTarget(badUnit,"enemy-a")
    eq(result.state,"unavailable","unapproved source token is rejected")
    eq(#reads,0,"invalid source causes no unit API calls")
end
for _,badGUID in ipairs({"",false,secret}) do
    reset()
    result=NS.ReadEnemyTarget("nameplate1",badGUID)
    eq(result.state,"unavailable","missing or secret expected identity is rejected")
    eq(#reads,0,"invalid expected identity causes no unit API calls")
end
reset()
result=NS.ReadEnemyTarget("nameplate1",nil)
eq(result.state,"unavailable","nil expected identity is rejected")
eq(#reads,0,"nil expected identity causes no unit API calls")

reset()
units.target={guid="enemy-b"}
units.targettarget={name="既有目标的对象",player=false}
result=NS.ReadEnemyTarget("target","enemy-b")
eq(result.state,"known","existing action aliases use their own target chain")
eq(result.name,"既有目标的对象","target alias reads targettarget")
eq(NS.ValidToken("nameplate1target"),false,"display lookup does not expand secure binding tokens")
eq(NS.ValidToken("targettargettarget"),false,"display target chains remain outside secure binding whitelist")

reset()
UnitCanAssist=function(_,unit) return unit=="nameplate1target" end
UnitIsDeadOrGhost=function() return false end
result=inspect()
eq(result.guid,"victim-a","target hover receives the target's public identity")
eq(result.assist,true,"target hover receives only confirmed friendly eligibility")
eq(result.dead,false,"target hover receives confirmed living state")
UnitCanAssist=function() return secret end
UnitIsDeadOrGhost=function() return secret end
result=inspect()
eq(result.assist,false,"secret friendship cannot enable target hover")
eq(result.dead,nil,"secret death state cannot enable living target hover")
reset();onNameRead=function() units.nameplate1target.guid="victim-reused" end
result=state("unavailable","a victim change during name read rejects the entire mixed snapshot")
eq(result.guid,nil,"target identity change during read cannot arm a hover region")
reset();overrides.health=function(unit)
    local old=units[unit].healthCurrent
    units[unit]={guid="victim-reused",name="另一个人",player=true,className="法师",classToken="MAGE",
        healthCurrent=50,healthMax=100}
    return old
end
state("unavailable","a victim change between health and maximum reads rejects the mixed snapshot")
reset();overrides.healthMax=function(unit) units[unit]=nil;return 1000 end
state("unavailable","a victim disappearing during health read clears the entire snapshot")
reset();overrides.guid=function(unit) return unit=="nameplate1" and "enemy-a" or secret end
result=inspect()
eq(result.guid,nil,"secret target GUID cannot arm a hover region")
eq(result.name,"治疗者","public display name survives unavailable hover identity")

-- Name-based casting metadata is still read-only and carries a full player
-- name plus explicit online/relation evidence; unknown is never made online.
reset()
UnitCanAssist=function() return true end
UnitCanAttack=function() return false end
UnitIsDeadOrGhost=function() return false end
UnitIsConnected=function() return true end
UnitFullName=function() return "治疗者","异服" end
result=inspect()
eq(result.targetName,"治疗者-异服","player bridge receives the complete realm-qualified name")
eq(result.offline,false,"confirmed connected target is explicitly online")
eq(result.harm,false,"friendly target is not advertised as harmful")
NameUtil={GetUnmodifiedUnitFullName=function() return "原始姓名-原始服" end}
result=inspect()
eq(result.targetName,"原始姓名-原始服","canonical native full name wins over display name")
NameUtil.GetUnmodifiedUnitFullName=function() return secret end
result=inspect()
eq(result.targetName,"治疗者-异服","secret canonical name falls back to readable full name")
UnitIsConnected=function() return secret end
result=inspect()
eq(result.offline,nil,"unknown connected state cannot enable the bridge")
UnitIsConnected=function() return false end
eq(inspect().offline,true,"disconnected target is explicitly offline")
UnitIsConnected=function() return true end
units.nameplate1target.player=false
UnitCanAssist=function() return false end
UnitCanAttack=function() return true end
result=inspect()
eq(result.targetName,"治疗者","NPC targets use their exact exposed name without invented realm")
eq(result.harm,true,"hostile target relation is exposed to the child bridge")
UnitCanAttack=function() return secret end
eq(inspect().harm,false,"secret attack eligibility cannot admit a hostile bridge")
units.nameplate1target.player=true
NameUtil.GetUnmodifiedUnitFullName=function()
    units.nameplate1target.guid="changed-during-full-name"
    return "新的名字-异服"
end
state("unavailable","target identity changes during full-name lookup discard the snapshot")
for api,count in pairs(writes) do eq(count,0,"display never invokes "..api) end
print("Targets enemy target simulated checks: "..checks)
