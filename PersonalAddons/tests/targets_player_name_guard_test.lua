-- OOC preparation and restricted-snippet model only. Native nameplate macro
-- conditions deliberately fail while ordinary unit APIs succeed. Macro target
-- changes below are a Lua model, not native selection/casting or recipient proof.
local checks=0
local function eq(actual,expected,message)
    checks=checks+1
    assert(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,message) eq(not not value,true,message) end
local combat,restricted,secret=false,false,{}
local methods,frames,wrappers={},{},{}
local function createFrame(kind,name,parent,template)
    local f=setmetatable({name=name,parent=parent,template=template,attrs={},refs={},scripts={},events={},shown=true},{__index=methods})
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
function methods:GetName() return self.name end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value)
    assert(not combat or restricted,"ordinary Lua attempted a protected combat write")
    self.attrs[key]=value
end
function methods:SetFrameRef(key,value) assert(not combat,"frame references must be prepared OOC");self.refs[key]=value end
function methods:GetFrameRef(key) return self.refs[key] end
function methods:IsVisible() return self.shown end
function methods:IsUnderMouse() return true end
function methods:SetSize() end
function methods:SetPoint() end
function methods:EnableMouse() end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:RegisterEvent(event) self.events[event]=true end
CreateFrame=createFrame
UIParent=createFrame("Frame","UIParent")
SecureHandlerWrapScript=function(row,event,owner,pre)
    wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre}
end
SecureHandlerSetFrameRef=function(owner,key,value) owner:SetFrameRef(key,value) end
RegisterStateDriver=function() assert(not combat,"no combat driver mutation") end
ClearOverrideBindings=function() assert(not combat,"ordinary Lua cannot clear combat overrides") end
local function forbidden() error("player macros and permanent bindings must not be modified") end
SetBinding=forbidden;SaveBindings=forbidden;SetBindingClick=forbidden
CreateMacro=forbidden;EditMacro=forbidden
InCombatLockdown=function() return combat end
issecretvalue=function(value) return value==secret end
local units={
    nameplate1={unit="nameplate1",guid="Player-fixture-b",name="测试",targetName="测试 姓氏",player=true,side="friendly",dead=false},
    nameplate2={unit="nameplate2",guid="Creature-fixture",name="怪物",targetName="怪物",player=false,side="enemy",dead=false},
    player={unit="player",guid="Player-fixture-self",name="自己",targetName="自己 姓氏",player=true,side="friendly",dead=false},
    party1={unit="party1",guid="Player-fixture-a",name="队员",targetName="队员 姓氏",player=true,side="friendly",dead=false},
}
local enemyOriginal={guid="Creature-original",name="原敌人",player=false,side="enemy",dead=false}
UnitExists=function(unit) return units[unit]~=nil end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
UnitName=function(unit) return units[unit] and units[unit].name end
UnitCanAssist=function(_,unit) return units[unit] and units[unit].side=="friendly" or false end
UnitCanAttack=function(_,unit) return units[unit] and units[unit].side=="enemy" or false end
GetBindingAction=function() return "BASE" end
GetMouseFoci=function() return {} end
local canonicalMode,canonicalCalls="normal",0
NameUtil={GetUnmodifiedUnitFullName=function(unit)
    canonicalCalls=canonicalCalls+1
    if canonicalMode=="nil" then return nil end
    if canonicalMode=="secret" then return secret end
    if canonicalMode=="mismatch" then return "另一 全名" end
    if canonicalMode=="error" then error("native name read unavailable") end
    if canonicalMode=="changed_guid" then units[unit].guid="Player-reused" end
    return units[unit] and units[unit].targetName
end}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
eq(NS.NativeMacroOnly,true,"production macro policy remains enabled")
eq(NS.LegacyNameBridge,true,"production ordinary-skill bridge remains enabled")
eq(NS.CombatNameBridge,true,"production combat continuation remains enabled")
local downEntry={side="friendly",spell="治疗术",spellID=639,slot=61,command="MULTIACTIONBAR1BUTTON1",
    actionKind="spell",keys={"9"},useOnKeyDown=true}
local upEntry={side="friendly",spell="祝福术",spellID=19742,slot=62,command="MULTIACTIONBAR1BUTTON2",
    actionKind="spell",keys={"0"},useOnKeyDown=false}
local enemyEntry={side="enemy",spell="伤害术",spellID=585,slot=63,command="MULTIACTIONBAR1BUTTON3",
    actionKind="spell",keys={"Z"},useOnKeyDown=true}
NS.NearbyCast={combatName=true,
    SnapshotRow=function(row) return units[row.unit],true end,
    DiscoverActions=function(side) return side=="friendly" and {downEntry,upEntry} or {enemyEntry} end}
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
local Cast=NS.CombatCast
local function row(name,side,unit)
    local f=createFrame("Button",name,UIParent,"SecureActionButtonTemplate")
    f.side,f.unit,f.expectedGUID=side,unit,units[unit].guid
    yes(Cast.Install(f),"main row installs the prepared name controller")
    return f
end
local friend=row("PlayerNameGuardFriend","friendly","nameplate1")
local npc=row("PlayerNameGuardNPC","enemy","nameplate2")
yes(UnitExists("nameplate1"),"ordinary unit API sees the friendly nameplate")
yes(UnitCanAssist("player","nameplate1"),"ordinary assist API admits the friendly nameplate")
canonicalCalls=0
yes(Cast.ArmRow(friend),"canonical friendly player prepares both spell edges")
eq(canonicalCalls,1,"native full name is verified once per row preparation, not per spell")
eq(units.nameplate1.trustedPlayerName,nil,"arming does not modify the provider's shared data table")
eq(Cast.Status(friend).nameGuardPolicy,"friendly_player_name","status identifies the player-specific policy")
local snapshot=Cast.states[friend].data
yes(snapshot.trustedPlayerName,"frozen copy keeps the internal canonical trust decision")
local proxy=Cast.states[friend].proxies[1]
local releaseProxy=Cast.states[friend].proxies[2]
eq(proxy:GetAttribute("snapshot-player-name-route"),true,"protected player route flag is prepared out of combat")
local expectedPrefix="/cleartarget\n/targetexact 测试 姓氏\n/cast [@target,exists,help,nodead] 治疗术\n"
eq(proxy:GetAttribute("snapshot-with-target"),expectedPrefix.."/targetlasttarget","internal surname space remains in the exact name")
eq(proxy:GetAttribute("snapshot-without-target"),expectedPrefix.."/cleartarget","empty original uses a final clear")
eq(proxy:GetAttribute("snapshot-fallback"),nil,"trusted player route has no original-target or self fallback")
eq(proxy:GetAttribute("snapshot-with-target"):find("nameplate",1,true),nil,"player macro has no rejected nameplate guard")
eq(proxy:GetAttribute("snapshot-with-target"):find("/stopmacro",1,true),nil,"no post-clear stop can swallow restoration")
eq(proxy:GetAttribute("snapshot-with-target"):find("@player",1,true),nil,"name-selection failure cannot auto-self cast")

local restrictedAliasCalls,publicAliasCalls=0,0
SecureCmdOptionParse=function(condition)
    if condition:find("@nameplate",1,true) then
        if restricted then restrictedAliasCalls=restrictedAliasCalls+1 else publicAliasCalls=publicAliasCalls+1 end
        return nil -- Native macro condition disagrees with the ordinary unit API.
    end
    if condition=="[@target,exists] present" then return units.target and "present" or nil end
end
local function run(snippet,self,control)
    local f=assert(loadstring(snippet))
    setfenv(f,setmetatable({self=self,control=control},{__index=_G}))
    restricted=true
    local ok,errorText=pcall(f)
    restricted=false
    assert(ok,errorText)
end
local records,starts,ends={},{},{}
local logging=true
NS.Diagnostics={Enabled=function() return logging end,
    Record=function(kind,fields) records[#records+1]={kind=kind,fields=fields} end,
    BeginCastAttempt=function(fields) starts[#starts+1]=fields;return #starts end,
    EndCastAttempt=function(id,fields) ends[#ends+1]={id=id,fields=fields} end}
local function last(kind)
    for i=#records,1,-1 do if records[i].kind==kind then return records[i].fields end end
end
local function combatOn(f)
    Cast.owner:SetAttribute("combat-active",true)
    Cast.owner:SetAttribute("combat-hover-index",Cast.installed[f])
    combat=true
end
local function combatOff()
    combat=false
    Cast.owner:SetAttribute("combat-active",false)
end
local attempts,successes=0,0
local selectedMode,castFailure="success",false
local function modelMacro(p)
    if p:GetAttribute("type")~="macro" then return end
    local previous
    for line in p:GetAttribute("macrotext"):gmatch("[^\n]+") do
        if line=="/cleartarget" then
            if units.target then previous=units.target end
            units.target=nil
        elseif line:match("^/targetexact ") then
            local name=line:sub(14)
            if selectedMode~="missing" and name==units.nameplate1.targetName then
                units.target=units.nameplate1
                if selectedMode=="dead" then units.target={guid=units.nameplate1.guid,side="friendly",dead=true} end
                if selectedMode=="hostile" then units.target=enemyOriginal end
            end
        elseif line:match("^/cast ") then
            if units.target and units.target.side=="friendly" and not units.target.dead then
                attempts=attempts+1
                if not castFailure then successes=successes+1 end
            end
        elseif line=="/targetlasttarget" then
            units.target,previous=previous,units.target
        end
    end
end
local function press(p,down)
    run(Cast.Snippets.preClick,p,Cast.owner)
    p:GetScript("PreClick")(p,"LeftButton",down)
    if down==(p.entry.useOnKeyDown==true) then modelMacro(p) end
    p:GetScript("PostClick")(p,"LeftButton",down)
end

-- Each original-target class is exercised with successful selection, no match,
-- dead/unhelpful selection, and a native cast rejection after successful select.
for _,initial in ipairs({"enemy","empty","friendly","self","already_hovered"}) do
    for _,failure in ipairs({"success","missing","dead","hostile","range","gcd"}) do
        units.target=initial=="enemy" and enemyOriginal or initial=="friendly" and units.party1
            or initial=="self" and units.player or initial=="already_hovered" and units.nameplate1 or nil
        local beforeGUID,beforeExists=UnitGUID("target"),UnitExists("target")
        local beforeAttempts,beforeSuccesses=attempts,successes
        selectedMode=(failure=="range" or failure=="gcd") and "success" or failure
        castFailure=failure=="range" or failure=="gcd"
        restrictedAliasCalls=0
        combatOn(friend)
        press(proxy,true)
        eq(proxy:GetAttribute("combat-branch"),beforeExists and "player_name_restore" or "player_name_clear",
            "trusted player chooses presence branch without a nameplate condition")
        eq(restrictedAliasCalls,0,"player dispatch does not evaluate the rejected native nameplate guard")
        eq(UnitGUID("target"),beforeGUID,"model restores original GUID even when selection/cast fails")
        eq(UnitExists("target"),beforeExists,"model restores original absence or existence")
        local selected=failure=="success" or failure=="range" or failure=="gcd"
        eq(attempts,beforeAttempts+(selected and 1 or 0),"missing/dead/hostile selection cannot cast on original friend or self")
        eq(successes,beforeSuccesses+(failure=="success" and 1 or 0),"range/GCD failure does not count as a successful modeled cast")
        local pre,post=last("COMBAT_KEY_PREPARE"),last("COMBAT_NAME_POST")
        eq(pre.aliasGuardPublicResult,"[nil]","legacy PRE explicitly reports the failed native alias guard")
        eq(pre.aliasExistsPublicResult,"[nil]","native alias exists condition is an independent observation")
        eq(pre.aliasHelpPublicResult,"[nil]","native alias help condition is an independent observation")
        eq(pre.aliasNodeadPublicResult,"[nil]","native alias nodead condition is an independent observation")
        eq(pre.spellName,"治疗术","plain spell name is logged independently of macro text")
        eq(pre.nameGuardPolicy,"friendly_player_name","PRE identifies the exact guard bypass policy")
        eq(pre.selectedCommandMatches,true,"PRE observes the newly selected prepared macro")
        eq(post.targetRestoredObserved,true,"POST reports restoration readback only")
        eq(post.recipientProven,false,"even a modeled cast never proves a native recipient")
        eq(starts[#starts].route,"combat_player_name","attempt uses its distinct player-name route")
        eq(starts[#starts].generatedCommand,nil,"name macro contents never enter the attempt logger")
        combatOff()
    end
end
yes(publicAliasCalls>0,"diagnostics may read native guard results without controlling dispatch")

-- Release preferences and disabled logging change observations only.
units.target=enemyOriginal;selectedMode="success";castFailure=false
combatOn(friend)
local countRecords,countStarts,countEnds,countAttempts=#records,#starts,#ends,attempts
press(releaseProxy,true)
eq(#records,countRecords,"non-executing key-down edge creates no release-action records")
eq(#starts,countStarts,"non-executing key-down edge creates no release-action window")
eq(attempts,countAttempts,"non-executing edge dispatches no modeled spell")
press(releaseProxy,false)
eq(#starts,countStarts+1,"matching release starts one player-name observation window")
eq(#ends,countEnds+1,"matching release pairs the post observation")
eq(last("COMBAT_KEY_PREPARE").down,false,"release PRE labels the actual edge")
eq(last("COMBAT_NAME_POST").down,false,"release POST labels the actual edge")
eq(UnitGUID("target"),enemyOriginal.guid,"release-action model restores the original enemy")
logging=false
countRecords,countStarts,countEnds,countAttempts=#records,#starts,#ends,attempts
press(proxy,true);press(releaseProxy,false)
eq(#records,countRecords,"disabled logger records neither action edge")
eq(#starts,countStarts,"disabled logger creates no windows")
eq(#ends,countEnds,"disabled logger finishes no windows")
eq(attempts,countAttempts+2,"both prepared edges still execute in the model without logging")
eq(UnitGUID("target"),enemyOriginal.guid,"disabled logger has no restoration side effect")
eq(Cast.ArmRow(friend),false,"ordinary Lua cannot re-arm player policy during combat")
combatOff();logging=true

-- No canonical proof means the old alias policy remains intact; never infer a
-- surname/realm from display text or reuse a prior true marker on shared data.
for _,mode in ipairs({"nil","secret","mismatch","error","changed_guid"}) do
    canonicalMode=mode
    units.nameplate1.guid=friend.expectedGUID
    units.nameplate1.trustedPlayerName=true -- A provider's stale marker is untrusted.
    yes(Cast.ArmRow(friend),"old alias route remains available when canonical proof fails")
    local p=Cast.states[friend].proxies[1]
    eq(p:GetAttribute("snapshot-player-name-route"),false,mode.." canonical proof cannot bypass guard")
    eq(Cast.Status(friend).nameGuardPolicy,"alias","status exposes retained alias policy")
    units.target=enemyOriginal
    combatOn(friend)
    run(Cast.Snippets.preClick,p,Cast.owner)
    eq(p:GetAttribute("combat-branch"),"fallback","untrusted player still obeys the native alias guard")
    p:GetScript("PreClick")(p,"LeftButton",true)
    eq(last("COMBAT_KEY_PREPARE").aliasGuardPublicResult,"[nil]","old alias fallback also logs the native guard failure")
    combatOff()
end
units.nameplate1.guid=friend.expectedGUID
units.nameplate1.trustedPlayerName=nil
canonicalMode="normal"
yes(Cast.ArmRow(friend),"valid canonical preparation can be rebuilt outside combat")

-- NPCs, enemy players, subbars and historical routes never gain player trust.
canonicalCalls=0
yes(Cast.ArmRow(npc),"existing enemy NPC snapshot still prepares")
eq(canonicalCalls,0,"NPC preparation does not query native player full-name proof")
local npcProxy=Cast.states[npc].proxies[1]
eq(npcProxy:GetAttribute("snapshot-player-name-route"),false,"NPC proxy cannot use the player bypass")
yes(npcProxy:GetAttribute("snapshot-with-target"):find("/stopmacro [@nameplate2",1,true),"NPC macro retains its native alias guard")
combatOn(npc)
run(Cast.Snippets.preClick,npcProxy,Cast.owner)
eq(npcProxy:GetAttribute("combat-branch"),"fallback","NPC dispatch still fails closed on native alias mismatch")
combatOff()
units.nameplate2.player=true
units.nameplate2.targetName="敌方 姓氏"
canonicalCalls=0
yes(Cast.ArmRow(npc),"enemy player retains the existing preparation route")
eq(canonicalCalls,0,"enemy player never queries friendly canonical trust")
eq(Cast.states[npc].proxies[1]:GetAttribute("snapshot-player-name-route"),false,"enemy player cannot use the friendly bypass")
eq(Cast.Status(npc).nameGuardPolicy,"alias","enemy-player status retains alias policy")
units.nameplate2.player=false
units.nameplate2.targetName="怪物"
local sub=createFrame("Button","PlayerNameGuardSubbar",UIParent)
sub.side,sub.bridgeTarget="friendly",true
eq(Cast.Install(sub),false,"enemy-target child never joins player-name route")
local historic={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",historic)
historic.NativeMacroOnly=false;historic.PreserveCastTarget=false
historic.NearbyCast={}
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",historic)
local historicalData={guid="Player-history",unit="nameplate1",targetName="旧 全名",player=true,trustedPlayerName=true}
local historical=historic.CombatCast.BuildMacros(historicalData,downEntry)
eq(historical.playerNameRoute,nil,"historical non-production policy cannot take the player bypass")
yes(historical.withTarget:find("/stopmacro [@nameplate1",1,true),"historical macro keeps its original guard")

for _,record in ipairs(records) do
    eq(record.fields.macrotext,nil,"new observer never stores macro text")
    eq(record.fields.macroBody,nil,"new observer never stores existing player macro bodies")
end
print("Targets trusted player-name guard checks:",checks,"passed (Lua model; native selection/casting unverified)")
