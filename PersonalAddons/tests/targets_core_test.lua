-- Pure API/data behavior simulation. Secure casting and rendering require the game.
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, why .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function yes(value, why) eq(not not value, true, why) end
local NS, units, plates = {}, {}, {}
local function forbiddenSecretOperation() error("secret numeric value used in Lua calculation or formatting") end
local secret = setmetatable({}, {__add=forbiddenSecretOperation,__sub=forbiddenSecretOperation,
    __mul=forbiddenSecretOperation,__div=forbiddenSecretOperation,__lt=forbiddenSecretOperation,
    __le=forbiddenSecretOperation,__tostring=forbiddenSecretOperation})
local originalType=type
-- The sentinel has the same reported Lua type as the client's secret number.
type=function(value) if value==secret then return "number" end;return originalType(value) end
local combat, raid, grouped = false, false, false
issecretvalue = function(value) return value == secret end
InCombatLockdown = function() return combat end
IsInRaid = function() return raid end
IsInGroup = function() return grouped end
GetNumGroupMembers = function() return raid and 40 or grouped and 5 or 0 end
GetNumSubgroupMembers = function() return grouped and 4 or 0 end
UnitExists = function(unit) return units[unit] ~= nil end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitClass = function(unit)
    local u = units[unit]
    if u then return u.className or "法师", u.classToken or "MAGE", 8 end
end
UnitIsPlayer = function(unit) return units[unit] and units[unit].player or false end
UnitIsFriend = function(_, unit) return units[unit] and units[unit].friend or false end
UnitCanAssist = UnitIsFriend
UnitCanAttack = function(_, unit) return units[unit] and units[unit].attack or false end
UnitIsVisible = function(unit) return units[unit] and units[unit].visible ~= false or false end
UnitIsConnected = function(unit) return units[unit] and units[unit].connected ~= false or false end
UnitIsDeadOrGhost = function(unit) return units[unit] and units[unit].dead or false end
UnitIsDead = UnitIsDeadOrGhost
UnitHealth = function(unit) return units[unit] and units[unit].hp or 50 end
UnitHealthMax = function(unit) return units[unit] and units[unit].maxhp or 100 end
UnitPowerType = function(unit)
    local u=units[unit]
    if u then return u.powerType or 0,u.powerToken or "MANA" end
end
UnitPower = function(unit) return units[unit] and units[unit].power end
UnitPowerMax = function(unit) return units[unit] and units[unit].maxpower end
UnitIsUnit = function(a, b) return units[a] and units[b] and units[a].guid == units[b].guid or false end
UnitLevel = function() return 10 end
UnitCreatureType = function() return "野兽" end
GetRaidTargetIndex = function(unit) return units[unit] and units[unit].marker end
C_NamePlate = {GetNamePlates=function() return plates end}
RAID_CLASS_COLORS = {MAGE={r=.25,g=.78,b=.92}, WARRIOR={r=.78,g=.61,b=.43}}

local root = "_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root .. "Core.lua"))("MyForeverTargets", NS)
assert(loadfile(root .. "Distance.lua"))("MyForeverTargets", NS)
assert(loadfile(root .. "Detection.lua"))("MyForeverTargets", NS)
assert(loadfile(root .. "Quest.lua"))("MyForeverTargets", NS)
assert(loadfile(root .. "Units.lua"))("MyForeverTargets", NS)
local function add(token, id, player, friend, attack)
    units[token] = {guid=id, name="目标" .. id, player=player, friend=friend, attack=attack}
    return units[token]
end
local function reset()
    units, plates = {}, {}
    raid, grouped = false, false
end
local function includes(list, token)
    for _, value in ipairs(list) do if value == token then return true end end
    return false
end
NS.Initialize(nil)
eq(NS.DB.friendlyTab, "raid", "default friendly tab")
eq(NS.DB.nearbyLimit, 20, "default nearby capacity")
eq(NS.DB.enemyLimit, 20, "default enemy capacity")
eq(NS.DB.shown, true, "panels visible by default")
eq(NS.DB.scale, 1, "default scale")
eq(NS.DB.friendlyPosition.manual,false,"default position remains eligible for automatic fitting")
do
    eq(NS.DB.friendlyPosition.point,"LEFT","new friendly default follows the viewport left edge")
    eq(NS.DB.friendlyPosition.relativePoint,"LEFT","friendly default stays relative to viewport middle as ratio changes")
    local legacy=NS.NormalizeDB({friendlyPosition={point="CENTER",relativePoint="CENTER",x=-225,y=160},
        enemyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=1092,y=-844,manual=true}})
    eq(legacy.friendlyPosition.point,"LEFT","untouched old default adopts the new friendly position")
    eq(legacy.enemyPosition.x,1092,"friendly default migration preserves enemy placement")
    local manual=NS.NormalizeDB({friendlyPosition={point="CENTER",relativePoint="CENTER",x=-225,y=160,manual=true}})
    eq(manual.friendlyPosition.point,"CENTER","explicitly dragged old-default coordinates remain player owned")
    local custom=NS.NormalizeDB({friendlyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=630,y=-967}})
    eq(custom.friendlyPosition.y,-967,"nondefault saved positions are not silently moved")
    local saved=NS.NormalizeDB({friendlyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=120,y=-300,manual=true},
        enemyPosition={manual="true"}})
    local reloaded=NS.NormalizeDB(saved)
    eq(reloaded.friendlyPosition.manual,true,"explicit drag ownership survives normalization and reload")
    eq(reloaded.friendlyPosition.x,120,"saved drag horizontal coordinate survives reload")
    eq(reloaded.friendlyPosition.y,-300,"saved drag vertical coordinate survives reload")
    eq(reloaded.friendlyPosition.point,"TOPLEFT","saved drag anchor survives reload")
    eq(reloaded.enemyPosition.manual,false,"non-boolean drag ownership does not disable automatic fitting")
end
eq(NS.LegacyNameBridge,true,"ordinary-spell name bridge has explicit production authorization")
eq(NS.NativeMacroOnly,true,"ordinary-spell exception keeps user macros and old controllers on their existing policy")
eq(NS.PreserveCastTarget,true,"ordinary-spell exception leaves the global preservation guard enabled")
eq(NS.DB.legacyNameBridgeEnabled,true,"authorized ordinary-spell bridge defaults on")
eq(NS.NormalizeDB({legacyNameBridgeEnabled=false}).legacyNameBridgeEnabled,false,
    "player can keep the ordinary-spell bridge disabled across reloads")
eq(NS.NormalizeDB({mouseoverRequested=false}).legacyNameBridgeEnabled,true,
    "older native mouseover preference does not disable the separately authorized ordinary-spell bridge")
NS.Initialize({friendlyTab="bogus", nearbyLimit=999, enemyLimit=-1, scale=0/0,
    shown="false", locked="true", friendlyPosition={point="bad",x=math.huge,y="x"}})
eq(NS.DB.friendlyTab, "raid", "unknown tab sanitized")
yes(NS.DB.nearbyLimit == 5 or NS.DB.nearbyLimit == 10 or NS.DB.nearbyLimit == 20, "nearby capacity constrained")
yes(NS.DB.enemyLimit == 5 or NS.DB.enemyLimit == 10 or NS.DB.enemyLimit == 20, "enemy capacity constrained")
yes(NS.Number(NS.DB.scale), "scale finite after corrupted storage")
eq(NS.Number(math.huge), false, "infinity rejected")
eq(NS.Number(0/0), false, "NaN rejected")
eq(NS.Number(secret), false, "secret numeric value rejected")
eq(NS.Read(function() error("unavailable") end), nil, "API error contained")
eq(NS.Read(nil), nil, "missing API contained")
eq(NS.Read(function() return secret end), nil, "secret API result not exposed")
eq(NS.ValidToken("mouseover"),false,"mouseover token is never secure binding source")
eq(NS.ValidToken("target; /reload"),false,"macro text cannot enter unit token")
eq(NS.ValidToken("raid41"),false,"invalid raid unit excluded")
eq(NS.ValidToken("party5"),false,"invalid party unit excluded")
eq(NS.ValidToken("pet"),false,"friendly pet is not a player slot")
for _,token in ipairs({"targettarget","focustarget","party1target","party4target","raid1target","raid40target","boss1","boss8","arena1","arena5"}) do
    eq(NS.ValidToken(token),true,"bounded actionable unit alias accepted: "..token)
end
for _,token in ipairs({"targettargettarget","focustargettarget","party5target","raid41target","boss0","boss9","arena0","arena6","party1pettarget"}) do
    eq(NS.ValidToken(token),false,"unit alias outside whitelist rejected: "..token)
end
combat=true; eq(NS.InCombat(), true, "combat detected")
combat=false; eq(NS.InCombat(), false, "out of combat detected")

reset()
add("player", "self", true, true, false)
add("nameplate1", "friendlyNPC", false, true, false)
add("nameplate2", "friendPlayer", true, true, false)
add("nameplate3", "enemyPlayer", true, false, true)
add("nameplate4", "enemyMob", false, false, true)
add("nameplate5", "neutral", false, false, false)
for i=1,5 do plates[#plates+1] = {namePlateUnitToken="nameplate" .. i} end
eq(NS.ReadUnit("nameplate1", "friendly"), nil, "friendly NPC excluded")
yes(NS.ReadUnit("nameplate2", "friendly"), "friendly player accepted")
eq(NS.ReadUnit("nameplate3", "friendly"), nil, "hostile player excluded from friendly")
yes(NS.ReadUnit("nameplate3", "enemy"), "hostile player accepted")
yes(NS.ReadUnit("nameplate4", "enemy"), "hostile monster accepted")
eq(NS.ReadUnit("nameplate5", "enemy"), nil, "unattackable neutral excluded")
eq(NS.ReadUnit("missing", "enemy"), nil, "missing unit excluded")
local friendly = NS.Collect("friendly", "nearby", 20)
yes(includes(friendly, "nameplate2"), "nearby friendly player discovered")
eq(includes(friendly, "nameplate1"), false, "nearby friendly NPC absent")
units.party1=units.nameplate2
friendly=NS.Collect("friendly","nearby",20)
yes(includes(friendly,"party1"),"stable group token preferred over plate alias")
eq(includes(friendly,"nameplate2"),false,"player plate alias removed after stable group dedupe")
units.party1=nil
local enemy = NS.Collect("enemy", "nearby", 20)
yes(includes(enemy, "nameplate3"), "enemy player discovered")
yes(includes(enemy, "nameplate4"), "enemy monster discovered")
eq(includes(enemy, "nameplate5"), false, "neutral absent from enemy discovery")
units.target=units.nameplate4; units.focus=units.nameplate4
enemy=NS.Collect("enemy", "nearby", 20)
eq(#enemy, 2, "same GUID target/focus/nameplate deduplicated")
add("mouseover", "exclusive-mouseover", false, false, true)
enemy=NS.Collect("enemy", "nearby", 20)
eq(includes(enemy, "mouseover"), false, "volatile mouseover token never bound")
local data=NS.ReadUnit("nameplate2", "friendly")
eq(data.guid, "friendPlayer", "GUID read live")
eq(data.classToken, "MAGE", "class token retained")
eq(data.className, "法师", "localized class retained")
yes(data.health == nil or data.health >= 0 and data.health <= 1, "health normalized")
units.nameplate2.name="新名字"
eq(NS.ReadUnit("nameplate2", "friendly").name, "新名字", "name refreshed from live token")
units.nameplate2.player=false
eq(NS.ReadUnit("nameplate2", "friendly"), nil, "reused friendly player token now NPC rejected")
units.nameplate3.guid=secret
eq(NS.ReadUnit("nameplate3", "enemy"), nil, "secret identity excluded")
units.nameplate3.guid="enemyPlayer"
units.nameplate3.hp=secret
eq(NS.ReadUnit("nameplate3", "enemy").health, nil, "secret health has no Lua percentage")
local hiddenHealth=NS.ReadUnit("nameplate3","enemy")
eq(hiddenHealth.healthAvailable,true,"secret numeric health remains available to native status bar")
yes(hiddenHealth.healthCurrent==secret,"secret health current is preserved only as raw display data")
eq(hiddenHealth.healthMax,100,"public health maximum remains native display range")
units.nameplate3.hp,units.nameplate3.maxhp=25,secret
hiddenHealth=NS.ReadUnit("nameplate3","enemy")
eq(hiddenHealth.health,nil,"secret maximum never enters Lua health arithmetic")
yes(hiddenHealth.healthMax==secret,"secret maximum is preserved for native display range")
units.nameplate3.hp,units.nameplate3.maxhp=secret,nil

-- Resource type changes must not retain the previous class resource or invent
-- full mana when the client does not expose a usable current/max pair.
local resource=units.nameplate3
resource.powerType,resource.powerToken,resource.power,resource.maxpower=0,"MANA",40,100
local power=NS.ReadUnit("nameplate3","enemy")
eq(power.powerRatio,.4,"public current/max mana gives normalized resource fraction")
eq(power.powerToken,"MANA","mana type identified independently of class")
yes(power.powerColor and power.powerColor.b>power.powerColor.r,"mana color is predominantly blue")
resource.powerType,resource.powerToken,resource.power=1,"RAGE",0
power=NS.ReadUnit("nameplate3","enemy")
eq(power.powerRatio,0,"zero rage is a known empty resource rather than unknown")
eq(power.powerToken,"RAGE","runtime resource switch replaces old mana token")
yes(power.powerColor and power.powerColor.r>power.powerColor.b,"rage changes resource color to red")
resource.powerType,resource.powerToken,resource.power=3,"ENERGY",150
power=NS.ReadUnit("nameplate3","enemy")
eq(power.powerRatio,1,"over-max resource is clamped")
yes(power.powerColor and power.powerColor.r>.7 and power.powerColor.g>.7 and power.powerColor.b<.5,
    "energy resource uses yellow rather than stale mana color")
resource.power=-10
eq(NS.ReadUnit("nameplate3","enemy").powerAvailable,false,"negative resource is rejected as invalid")
resource.power=25;resource.maxpower=0
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"zero maximum resource is unavailable")
resource.maxpower=100;resource.power=secret
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"secret current resource has no Lua percentage")
power=NS.ReadUnit("nameplate3","enemy")
eq(power.powerAvailable,true,"secret numeric resource remains available to native display")
yes(power.powerCurrent==secret,"secret resource current is preserved without arithmetic")
resource.power=25;resource.maxpower=secret
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"secret maximum resource has no Lua percentage")
power=NS.ReadUnit("nameplate3","enemy")
eq(power.powerAvailable,true,"secret numeric maximum remains a valid native range")
yes(power.powerMax==secret,"secret resource maximum is preserved without comparison")
resource.maxpower=100;resource.power=0/0
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"NaN resource is unavailable")
resource.power=25;resource.maxpower=math.huge
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"infinite resource maximum is unavailable")
resource.maxpower=100;resource.powerType=secret
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"secret resource identity is unavailable")
resource.powerType,resource.powerToken=999,"MYSTERY"
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"unrecognized resource never borrows a class color or mana value")
local previousPowerType,previousPower=UnitPowerType,UnitPower
UnitPowerType=nil
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"missing resource identity API hides resource")
UnitPowerType=previousPowerType;resource.powerType,resource.powerToken=0,"MANA"
UnitPower=function() error("resource read blocked") end
eq(NS.ReadUnit("nameplate3","enemy").powerRatio,nil,"resource API exception is contained")
UnitPower=previousPower
resource.powerType,resource.powerToken,resource.power,resource.maxpower=nil,nil,nil,nil

-- Selection highlighting follows public identity even when UnitIsUnit is absent
-- or does not provide a useful public boolean on this client.
local originalIsUnit,originalTarget=UnitIsUnit,units.target
units.target=units.nameplate3
UnitIsUnit=function() return true end
eq(NS.ReadUnit("nameplate3","enemy").target,true,"public matching unit boolean selects tile")
UnitIsUnit=function() return false end
eq(NS.ReadUnit("nameplate3","enemy").target,true,"matching public GUID supplies selected-target fallback")
UnitIsUnit=function() return nil end
eq(NS.ReadUnit("nameplate3","enemy").target,true,"missing unit comparison boolean falls back to GUID")
UnitIsUnit=function() return secret end
eq(NS.ReadUnit("nameplate3","enemy").target,true,"secret unit comparison can use public matching GUID")
UnitIsUnit=nil
eq(NS.ReadUnit("nameplate3","enemy").target,true,"missing UnitIsUnit API falls back to GUID")
UnitIsUnit=function() return false end
units.target=units.nameplate4
eq(NS.ReadUnit("nameplate3","enemy").target,false,"different selected GUID never highlights old target")
units.target={guid=secret}
eq(NS.ReadUnit("nameplate3","enemy").target,false,"secret selected GUID never compares as a real identity")
units.target=nil
eq(NS.ReadUnit("nameplate3","enemy").target,false,"clearing target removes selection highlight")
UnitIsUnit,units.target=originalIsUnit,originalTarget

-- Read-only nameplate units need a clean exact-name action; player names keep
-- their server suffix so same-named characters on different realms differ.
local previousNameUtil,previousFullName=NameUtil,UnitFullName
NameUtil={GetUnmodifiedUnitFullName=function() return "玩家全名-远方服务器" end}
eq(NS.ReadUnit("nameplate3","enemy").targetName,"玩家全名-远方服务器","canonical player targeting name retains realm")
NameUtil.GetUnmodifiedUnitFullName=function() return "Windfury Emberbeard" end
eq(NS.ReadUnit("nameplate3","enemy").targetName,"Windfury Emberbeard","Forever canonical full name retains space-separated surname")
eq(NS.ReadUnit("nameplate4","enemy").targetName,units.nameplate4.name,"monster exact target name uses actual NPC name")
NameUtil.GetUnmodifiedUnitFullName=function() return secret end
UnitFullName=function() return "备用角色","测试服" end
eq(NS.ReadUnit("nameplate3","enemy").targetName,"备用角色-测试服","restricted canonical name falls back to public full name")
NameUtil.GetUnmodifiedUnitFullName=function() error("canonical name blocked") end
eq(NS.ReadUnit("nameplate3","enemy").targetName,"备用角色-测试服","canonical API exception uses public full-name fallback")
NameUtil=nil
UnitFullName=function() return "本服角色","" end
eq(NS.ReadUnit("nameplate3","enemy").targetName,"本服角色","empty realm does not add a trailing separator")
UnitFullName=function() return secret,secret end
eq(NS.ReadUnit("nameplate3","enemy").targetName,units.nameplate3.name,"restricted full-name fields safely fall back to public display name")
NameUtil={GetUnmodifiedUnitFullName=function() return "玩家\n/run 不执行\r" end}
local cleanTargetName=NS.ReadUnit("nameplate3","enemy").targetName
yes(type(cleanTargetName)=="string" and not cleanTargetName:find("[\r\n]"),"target name cannot insert additional macro lines")
NameUtil,UnitFullName=previousNameUtil,previousFullName

-- Quest badges require an active, incomplete objective belonging to this player.
local questTime,tooltipCalls=100,0
local questState={[101]={index=1,complete=false}}
local tooltipData
GetTime=function() return questTime end
C_QuestLog={GetLogIndexForQuestID=function(id) return questState[id] and questState[id].index end,
    IsComplete=function(id) return questState[id] and questState[id].complete end}
C_TooltipInfo={GetUnit=function() tooltipCalls=tooltipCalls+1;return tooltipData end}
Enum={TooltipDataLineType={QuestTitle=17,QuestObjective=8,QuestPlayer=18}}
local titleLine={type=17,questID=101,leftText="狩猎野狼"}
local objectiveLine={type=8,completed=false,leftText="野狼：1/3"}
local function questLines(lines)
    tooltipData={lines=lines};NS.InvalidateQuestCache()
end
questLines({titleLine,objectiveLine})
local questFlag,questTitle=NS.IsQuestTarget("nameplate4")
eq(questFlag,true,"active incomplete objective confirms hostile quest monster")
eq(questTitle,"狩猎野狼","confirmed quest title retained")
eq(NS.ReadUnit("nameplate4","enemy").questTarget,true,"unit data includes confirmed quest relationship")
eq(NS.ReadUnit("player","friendly").questTarget,false,"friendly player never gains quest monster flag")
eq(NS.IsQuestTarget("nameplate3"),false,"hostile player never gains quest monster flag")
questState[101].complete=true;NS.InvalidateQuestCache()
eq(NS.IsQuestTarget("nameplate4"),false,"completed quest is not an active target")
questState[101].complete=secret;NS.InvalidateQuestCache()
eq(NS.IsQuestTarget("nameplate4"),false,"secret quest completion cannot imply incomplete")
questState[101].complete=false
questLines({{type=17,questID=999,leftText="未接任务"},objectiveLine})
eq(NS.IsQuestTarget("nameplate4"),false,"unaccepted quest never marks a monster")
questLines({titleLine})
eq(NS.IsQuestTarget("nameplate4"),false,"quest title alone is not objective evidence")
questLines({titleLine,{type=8,completed=true,numFulfilled=1,numRequired=3}})
eq(NS.IsQuestTarget("nameplate4"),false,"completed objective cannot be inferred incomplete from counts")
questLines({titleLine,{type=8,numFulfilled=1,numRequired=3}})
eq(NS.IsQuestTarget("nameplate4"),true,"public incomplete objective counts confirm relationship")
questLines({titleLine,{type=8,numFulfilled=3,numRequired=3}})
eq(NS.IsQuestTarget("nameplate4"),false,"fulfilled objective counts do not mark target")
questLines({titleLine,{type=8,completed=secret,numFulfilled=1,numRequired=3}})
eq(NS.IsQuestTarget("nameplate4"),false,"secret objective completion remains unknown")
questLines({titleLine,{type=8,numFulfilled=secret,numRequired=3}})
eq(NS.IsQuestTarget("nameplate4"),false,"secret objective counts remain unknown")
questLines({titleLine,{type=8,completed=true},{type=secret,questID=999,leftText="不可读任务"},objectiveLine})
eq(NS.IsQuestTarget("nameplate4"),false,"opaque quest boundary cannot borrow prior own quest context")
local unreadableLine=setmetatable({}, {__index=function() error("restricted nested tooltip field") end})
questLines({titleLine,unreadableLine,objectiveLine})
local nestedOK,nestedResult=pcall(NS.IsQuestTarget,"nameplate4")
eq(nestedOK,true,"restricted nested tooltip data does not escape into UI")
eq(nestedResult,false,"restricted nested tooltip data never confirms a quest target")
questLines({titleLine,{type=18,leftText="另一玩家"},objectiveLine})
eq(NS.IsQuestTarget("nameplate4"),false,"other player objective section cannot mark own target")
questLines({titleLine,{type=18,leftText="|cffff0000"..UnitName("player").."|r"},objectiveLine})
eq(NS.IsQuestTarget("nameplate4"),true,"own named player section confirms objective")
local callsBefore=tooltipCalls
tooltipData={lines={titleLine,{type=8,completed=true}}};questTime=questTime+.5
eq(NS.IsQuestTarget("nameplate4"),true,"quest result uses bounded one-second identity cache")
eq(tooltipCalls,callsBefore,"cache avoids repeated tooltip reads inside TTL")
questTime=questTime+1
eq(NS.IsQuestTarget("nameplate4"),false,"expired quest cache refreshes objective completion")
questLines({titleLine,objectiveLine})
eq(NS.IsQuestTarget("nameplate4"),true,"quest invalidation allows updated objective")
local realTooltip=C_TooltipInfo
C_TooltipInfo=nil;NS.InvalidateQuestCache()
eq(NS.IsQuestTarget("nameplate4"),false,"missing quest tooltip API does not invent relationship")
C_TooltipInfo={GetUnit=function() error("tooltip blocked") end};NS.InvalidateQuestCache()
eq(NS.IsQuestTarget("nameplate4"),false,"blocked tooltip API does not invent relationship")
C_TooltipInfo=realTooltip

-- Nameplate discovery must still work when UnitIsVisible is restricted.
local originalVisible=UnitIsVisible
UnitIsVisible=function() return secret end
add("nameplate8","visible-friend",true,true,false)
add("party2","hidden-group-friend",true,true,false)
local visibleNearby=NS.Collect("friendly","nearby",20)
yes(includes(visibleNearby,"nameplate8"),"public live nameplate remains discoverable with secret visibility")
eq(includes(visibleNearby,"party2"),false,"group token without confirmed visibility is not called nearby")
UnitIsVisible=nil
visibleNearby=NS.Collect("friendly","nearby",20)
yes(includes(visibleNearby,"nameplate8"),"live nameplate remains discoverable without visibility API")
UnitIsVisible=originalVisible
units.party1=units.nameplate8
local matchingPlate={namePlateUnitToken="nameplate8",IsForbidden=function() return false end}
local oldPlateLookup,oldPlateList=C_NamePlate.GetNamePlateForUnit,C_NamePlate.GetNamePlates
C_NamePlate.GetNamePlateForUnit=function() return nil end
C_NamePlate.GetNamePlates=function() return {matchingPlate} end
eq(NS.FindUnitNameplate("party1"),matchingPlate,"group alias resolves world nameplate by exact public GUID")
matchingPlate.IsForbidden=function() return true end
eq(NS.FindUnitNameplate("party1"),nil,"forbidden alias nameplate is ignored")
matchingPlate.IsForbidden=function() return false end
units.nameplate8.guid=secret
eq(NS.FindUnitNameplate("party1"),nil,"secret alias GUID is never matched")
C_NamePlate.GetNamePlateForUnit,C_NamePlate.GetNamePlates=oldPlateLookup,oldPlateList

-- Actionable aliases win GUID dedupe over readable-but-read-only nameplates.
reset()
local aliases={"targettarget","party4target","raid40target","boss8","arena5"}
for i,alias in ipairs(aliases) do
    local token="nameplate"..i
    add(token,"actionable-enemy-"..i,false,false,true)
    units[alias]=units[token]
    plates[#plates+1]={namePlateUnitToken=token}
end
local actionList,actionTotal=NS.Collect("enemy","nearby",20)
eq(actionTotal,5,"native aliases and plates count once per GUID")
for i,alias in ipairs(aliases) do
    yes(includes(actionList,alias),"actionable alias retained before plate: "..alias)
    eq(includes(actionList,"nameplate"..i),false,"read-only plate alias removed by GUID dedupe")
end
units.target=units.raid40target
actionList=NS.Collect("enemy","nearby",20)
yes(includes(actionList,"target"),"direct current target preferred over another native alias")
eq(includes(actionList,"raid40target"),false,"duplicate native alias removed after direct target wins")
units.target=nil
add("nameplate6","actionable-enemy-6",false,false,true)
plates[#plates+1]={namePlateUnitToken="nameplate6"}
local previousMeasure=NS.MeasureDistance
NS.MeasureDistance=function(token)
    local distances={targettarget=50,party4target=40,raid40target=30,boss8=1,arena5=20,nameplate6=10}
    local distance=distances[token]
    return distance and {min=distance,max=distance,exact=true} or nil
end
actionList,actionTotal=NS.Collect("enemy","nearby",5)
eq(actionTotal,6,"alias expansion still counts all candidates before clipping")
eq(actionList[1],"boss8","nearest actionable alias sorts before capacity clipping")
eq(includes(actionList,"targettarget"),false,"far native alias does not displace a closer sixth candidate")
NS.MeasureDistance=previousMeasure

reset()
raid, grouped = true, true
for i=1,40 do add("raid"..i,"raid-guid"..i,true,true,false) end
local members=NS.Collect("friendly", "raid", 20)
eq(#members, 20, "raid limited to twenty of forty players")
eq(includes(members, "raid21"), false, "raid member beyond first twenty absent")
units.raid1.player=false
members=NS.Collect("friendly","raid",20)
eq(#members,19,"NPC never enters raid player list")
eq(includes(members,"raid21"),false,"first twenty raid unit scope is retained after filtering")
reset()
grouped=true
add("player", "self", true, true, false)
for i=1,4 do add("party"..i,"party-guid"..i,true,true,false) end
members=NS.Collect("friendly", "party", 20)
eq(#members, 5, "party always limited to five")
yes(includes(members, "player"), "party includes self")
reset()
add("player", "self", true, true, false)
members=NS.Collect("friendly", "party", 5)
eq(#members, 1, "solo party contains only self")

reset()
for i=1,40 do
    add("nameplate"..i,"mob-guid"..i,false,false,true)
    plates[#plates+1]={namePlateUnitToken="nameplate"..i}
end
for _,limit in ipairs({5,10,20}) do
    local list,total=NS.Collect("enemy", "nearby", limit)
    eq(#list,limit,"enemy configurable capacity "..limit)
    yes(total==nil or total>=#list,"eligible count never below visible slots")
end

-- Exact distance APIs are optional; invalid/restricted values remain unknown.
local squared,positions={},{}
UnitDistanceSquared=function(unit)
    local v=squared[unit]
    if v=="error" then error("distance unavailable") end
    if v then return v.value,v.valid end
end
UnitPosition=function(unit)
    local p=positions[unit]
    if p=="error" then error("position unavailable") end
    if p then return p.x,p.y,p.z,p.instance end
end
reset()
add("player","self",true,true,false)
add("nameplate1","distance-unit",false,false,true)
eq(NS.Distance("player"),0,"self has explicit zero distance")
squared.nameplate1={value=81,valid=true}
eq(NS.Distance("nameplate1"),9,"validated squared distance converted to yards")
squared.nameplate1={value=0,valid=true}
eq(NS.Distance("nameplate1"),0,"validated zero distance retained")
for _,invalid in ipairs({{value=81,valid=false},{value=81},{value=-1,valid=true},
    {value=math.huge,valid=true},{value=0/0,valid=true},{value=secret,valid=true},
    {value=81,valid=secret}}) do
    squared.nameplate1=invalid
    eq(NS.Distance("nameplate1"),nil,"invalid squared-distance result is unknown")
end
positions.player={x=0,y=0,z=0,instance=1}
positions.nameplate1={x=3,y=4,z=12,instance=1}
squared.nameplate1={value=999,valid=false}
eq(NS.Distance("nameplate1"),13,"same-instance position fallback uses all three axes")
squared.nameplate1={value=999}
eq(NS.Distance("nameplate1"),13,"unvalidated distance can fall back to public positions")
squared.nameplate1="error"
eq(NS.Distance("nameplate1"),13,"distance API exception can fall back to positions")
positions.nameplate1.instance=2
eq(NS.Distance("nameplate1"),nil,"different instances never compared")
positions.nameplate1.instance=secret
eq(NS.Distance("nameplate1"),nil,"secret instance never compared")
positions.nameplate1.instance=nil
eq(NS.Distance("nameplate1"),nil,"missing instance never implies same map")
positions.nameplate1={x=secret,y=4,z=12,instance=1}
eq(NS.Distance("nameplate1"),nil,"secret position is unknown")
positions.nameplate1={x=3,y=4,z=nil,instance=1}
eq(NS.Distance("nameplate1"),nil,"missing coordinate is not guessed")
positions.nameplate1="error"
eq(NS.Distance("nameplate1"),nil,"position API exception is contained")
local oldDistanceAPI,oldPositionAPI=UnitDistanceSquared,UnitPosition
UnitDistanceSquared,UnitPosition=nil,nil
eq(NS.Distance("nameplate1"),nil,"missing distance APIs remain unknown")
UnitDistanceSquared,UnitPosition=oldDistanceAPI,oldPositionAPI

-- Range-check intervals remain intervals, never exact fabricated yard counts.
squared,positions={},{}
local intervals,rangeArgs,rangeError={},nil,false
NS.RangeCheck={GetRange=function(self,unit,checkVisible,noCache,cacheAge)
    rangeArgs={unit,checkVisible,noCache,cacheAge}
    if rangeError then error("range checks restricted") end
    local interval=intervals[unit]
    if interval then return interval.min,interval.max end
end}
intervals.nameplate1={min=5,max=10}
local measured=NS.MeasureDistance("nameplate1")
eq(measured.min,5,"range checker lower bound retained")
eq(measured.max,10,"range checker upper bound retained")
eq(measured.exact,false,"range checker interval is never called exact")
eq(rangeArgs[1],"nameplate1","range checker measures requested unit")
eq(rangeArgs[2],true,"range checker requires visibility")
eq(rangeArgs[3],false,"range checker normal cache mode")
eq(rangeArgs[4],.1,"range checker cache bounded to tenth second")
eq(NS.Distance("nameplate1"),nil,"exact distance API does not return interval estimate")
squared.nameplate1={value=49,valid=true}
measured=NS.MeasureDistance("nameplate1")
eq(measured.min,7,"exact distance lower bound")
eq(measured.max,7,"exact distance upper bound")
eq(measured.exact,true,"public exact distance distinguished from interval")
squared.nameplate1=nil
for _,invalid in ipairs({{min=5},{max=10},{min=-1,max=10},{min=20,max=10},
    {min=secret,max=10},{min=5,max=secret},{min=0/0,max=10},{min=5,max=math.huge}}) do
    intervals.nameplate1=invalid
    eq(NS.MeasureDistance("nameplate1"),nil,"unbounded or invalid range-check result remains unknown")
end
rangeError=true
eq(NS.MeasureDistance("nameplate1"),nil,"range-check API exception is contained")
rangeError=false
intervals.nameplate1={min=5,max=10}
local intervalLabel=NS.DistanceText(NS.MeasureDistance("nameplate1"))
yes(type(intervalLabel)=="string" and intervalLabel:find("5",1,true) and intervalLabel:find("10",1,true),
    "interval label discloses both bounds")
local exactLabel=NS.DistanceText({min=7,max=7,exact=true})
yes(type(exactLabel)=="string" and exactLabel:find("7",1,true),"exact label includes public yard count")
yes(type(NS.DistanceText(nil))=="string","unknown distance has a display-safe label")
NS.RangeCheck=nil

-- Discover/dedupe all eligible candidates, sort, then clip to the chosen capacity.
reset();squared,positions={},{}
for i=1,40 do
    local token="nameplate"..i
    add(token,"sorted-enemy-"..i,false,false,true)
    plates[#plates+1]={namePlateUnitToken=token}
    squared[token]={value=(41-i)^2,valid=true}
end
for _,limit in ipairs({5,10,20}) do
    local list,total=NS.Collect("enemy","nearby",limit)
    eq(total,40,"enemy total counts candidates before distance clipping")
    eq(#list,limit,"distance sorting retains chosen capacity")
    for i=1,limit do
        eq(list[i],"nameplate"..(41-i),"nearest enemy selected before capacity clipping")
    end
end
reset();squared,positions={},{}
add("player","self",true,true,false)
for i=1,40 do
    local token="nameplate"..i
    add(token,"sorted-friendly-"..i,true,true,false)
    plates[#plates+1]={namePlateUnitToken=token}
    squared[token]={value=(41-i)^2,valid=true}
end
local nearby,total=NS.Collect("friendly","nearby",5)
eq(total,41,"nearby friendly total includes self and all exposed players")
eq(nearby[1],"player","self sorts first at zero distance")
for i=2,5 do eq(nearby[i],"nameplate"..(42-i),"nearby friendly clips after distance ordering") end

reset();squared,positions={},{}
for i=1,3 do
    local token="nameplate"..i
    add(token,"moving-enemy-"..i,false,false,true)
    plates[#plates+1]={namePlateUnitToken=token}
end
squared.nameplate1={value=100,valid=true}
squared.nameplate2={value=4,valid=true}
squared.nameplate3={value=25,valid=true}
local ordered=NS.Collect("enemy","nearby",5)
eq(table.concat(ordered,","),"nameplate2,nameplate3,nameplate1","near-to-far enemy order")
squared.nameplate1={value=1,valid=true}
ordered=NS.Collect("enemy","nearby",5)
eq(table.concat(ordered,","),"nameplate1,nameplate2,nameplate3","moving targets reorder on the next collection")
squared.nameplate1=nil
ordered=NS.Collect("enemy","nearby",5)
eq(table.concat(ordered,","),"nameplate2,nameplate3,nameplate1","unknown distance follows known distances")
squared.nameplate1={value=25,valid=true};squared.nameplate2={value=25,valid=true}
for i=1,3 do
    ordered=NS.Collect("enemy","nearby",5)
    eq(table.concat(ordered,","),"nameplate1,nameplate2,nameplate3","equal distances preserve deterministic discovery order")
end

reset();squared,positions={},{}
for i=1,4 do
    local token="nameplate"..i
    add(token,"interval-enemy-"..i,false,false,true)
    plates[#plates+1]={namePlateUnitToken=token}
end
intervals={nameplate1={min=0,max=20},nameplate2={min=10,max=15},nameplate3={min=5}}
NS.RangeCheck={GetRange=function(_,unit)
    local interval=intervals[unit]
    if interval then return interval.min,interval.max end
end}
ordered=NS.Collect("enemy","nearby",5)
eq(table.concat(ordered,","),"nameplate2,nameplate1,nameplate3,nameplate4",
    "bounded range intervals sort by upper bound; unbounded result stays unknown")
squared.nameplate4={value=16,valid=true}
ordered=NS.Collect("enemy","nearby",5)
eq(table.concat(ordered,","),"nameplate4,nameplate2,nameplate1,nameplate3",
    "exact distance and bounded intervals share conservative sorting while unknown stays last")
NS.RangeCheck=nil

reset();squared,positions={},{}
raid,grouped=true,true
for i=1,20 do
    local token="raid"..i
    add(token,"ordered-raid-"..i,true,true,false)
    squared[token]={value=(21-i)^2,valid=true}
end
ordered=NS.Collect("friendly","raid",20)
for i=1,20 do eq(ordered[i],"raid"..i,"raid uses original roster order despite distances") end
reset();squared,positions={},{}
grouped=true
add("player","self",true,true,false)
for i=1,4 do
    local token="party"..i
    add(token,"ordered-party-"..i,true,true,false)
    squared[token]={value=(5-i)^2,valid=true}
end
ordered=NS.Collect("friendly","party",5)
eq(table.concat(ordered,","),"player,party1,party2,party3,party4","party preserves roster order despite distances")
add("nameplate1","missing-api-enemy",false,false,true)
UnitGUID=nil
eq(NS.ReadUnit("nameplate1","enemy"),nil,"missing identity API fails closed")

-- Configuration regression only: this does not simulate the engine's spell
-- recipient selection or prove that a particular frame becomes mouseover.
do
    local Cast={}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",Cast)
    Cast.NativeMacroOnly=false -- Historical ownership/restoration configuration fixture.
    assert(loadfile(root.."Mouseover.lua"))("MyForeverTargets",Cast)
    local values,key,infoMode,denyAutoEnable,denyAutoRestore,denySave,hideAuto
    local autoWrites=0
    local function configure(initial)
        values={enableMouseoverCast="0",autoSelfCast=initial}
        key,infoMode="ALT","normal"
        denyAutoEnable,denyAutoRestore,denySave,hideAuto=false,false,false,false
        autoWrites=0;combat=false;Cast.PendingMouseover=nil
        Cast.Initialize(nil)
    end
    IsMouseoverCastSupported=function() return true end
    C_CVar={GetCVar=function(name)
            if name=="autoSelfCast" and hideAuto then return nil end
            return values[name]
        end,
        SetCVar=function(name,value)
            if name=="autoSelfCast" then
                autoWrites=autoWrites+1
                if (value=="1" and denyAutoEnable) or (value=="0" and denyAutoRestore) then return false end
            end
            values[name]=value;return true
        end,
        GetCVarInfo=function()
            if infoMode=="error" then error("CVar metadata restricted") end
            if infoMode=="table-readonly" then return {isReadOnly=true,isSecure=false,isLockedFromUser=false} end
            return values.autoSelfCast,"0",false,false,infoMode=="locked",infoMode=="secure",infoMode=="readonly"
        end}
    GetModifiedClick=function() return key end
    SetModifiedClick=function(_,value) key=value end
    GetCurrentBindingSet=function() return 1 end
    SaveBindings=function() return not denySave end

    configure("0")
    yes(Cast.SetMouseoverEnabled(true,true),"native hover configuration includes self-cast fallback")
    eq(values.autoSelfCast,"1","auto self cast enabled for native helpful-action fallback")
    eq(Cast.DB.mouseoverBackup.autoSelfCast,"0","original self-cast setting is owned and backed up")
    Cast.Initialize(Cast.DB)
    eq(Cast.DB.mouseoverBackup.autoSelfCast,"0","self-cast backup survives normalization and reload")
    yes(Cast.SetMouseoverEnabled(false,true),"hover off restores owned self-cast change")
    eq(values.autoSelfCast,"0","original self-cast setting restored")
    eq(Cast.DB.mouseoverBackup,nil,"complete restore clears backup")

    configure("1")
    Cast.SetMouseoverEnabled(true,true)
    eq(autoWrites,0,"preexisting self-cast enable is never claimed or rewritten")
    eq(Cast.DB.mouseoverBackup.autoSelfCast,nil,"preexisting self-cast enable has no owned backup")
    Cast.SetMouseoverEnabled(false,true)
    eq(values.autoSelfCast,"1","hover off preserves originally enabled auto self cast")

    for _,mode in ipairs({"readonly","secure","locked","table-readonly","error"}) do
        configure("0");infoMode=mode
        Cast.SetMouseoverEnabled(true,true)
        eq(values.autoSelfCast,"0","unwritable self-cast CVar remains untouched: "..mode)
        eq(autoWrites,0,"unwritable metadata prevents self-cast write: "..mode)
    end
    configure(nil)
    Cast.SetMouseoverEnabled(true,true)
    eq(autoWrites,0,"missing self-cast CVar is not created")
    configure(secret)
    Cast.SetMouseoverEnabled(true,true)
    eq(autoWrites,0,"secret self-cast value is not modified")

    configure("0");denyAutoEnable=true
    eq(Cast.SetMouseoverEnabled(true,true),false,"rejected self-cast write reports failed configuration")
    eq(values.enableMouseoverCast,"0","self-cast enable failure rolls mouseover CVar back")
    eq(key,"ALT","self-cast enable failure rolls modifier back")
    eq(values.autoSelfCast,"0","self-cast enable failure preserves original self-cast value")
    configure("0");denySave=true
    eq(Cast.SetMouseoverEnabled(true,true),false,"binding persistence failure reports failed configuration")
    eq(values.autoSelfCast,"0","binding persistence failure rolls self-cast enable back")

    configure("0");Cast.SetMouseoverEnabled(true,true)
    values.autoSelfCast="0"
    local writesBeforeOff=autoWrites
    Cast.SetMouseoverEnabled(false,true)
    eq(autoWrites,writesBeforeOff,"hover off preserves external self-cast edit without overwriting it")
    eq(values.autoSelfCast,"0","external self-cast edit remains in effect")

    configure("0");Cast.SetMouseoverEnabled(true,true);denyAutoRestore=true
    eq(Cast.SetMouseoverEnabled(false,true),false,"blocked self-cast restore reports incomplete restoration")
    eq(Cast.DB.mouseoverBackup.autoSelfCast,"0","blocked restore keeps owned original self-cast value")
    denyAutoRestore=false
    yes(Cast.SetMouseoverEnabled(false,true),"self-cast restoration can retry")
    eq(values.autoSelfCast,"0","restore retry restores original self-cast value")
    configure("0");Cast.SetMouseoverEnabled(true,true);hideAuto=true
    eq(Cast.SetMouseoverEnabled(false,true),false,"unknown self-cast readback does not pretend restored")
    eq(Cast.DB.mouseoverBackup.autoSelfCast,"0","unknown self-cast readback retains original backup")
    hideAuto=false
    yes(Cast.SetMouseoverEnabled(false,true),"restoration retries after self-cast readback returns")

    configure("0");combat=true
    eq(Cast.SetMouseoverEnabled(true,true),false,"self-cast configuration defers during combat")
    eq(autoWrites,0,"combat never writes self-cast CVar")
    combat=false
end
print("Targets core simulated checks: " .. checks)
