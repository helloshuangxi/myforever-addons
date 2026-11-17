-- Authorized out-of-combat name-bridge configuration and preflight simulation.
-- Native macro execution, spell recipients and real restoration need game checks.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local combat,secret=false,{}
issecretvalue=function(value) return value==secret end
InCombatLockdown=function() return combat end
local methods,frames,wrappers,drivers={},{},{},{}
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",attrs={},scripts={},hooks={},shown=true}, {__index=methods})
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
function methods:GetName() return self.name end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:IsForbidden() return self.forbidden or false end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value) assert(not combat,"protected attribute changed in combat");self.attrs[key]=value end
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key,fn) self.hooks[key]=fn end
function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetPoint(...) self.point={...} end
CreateFrame=frame
UIParent=frame("Frame","UIParent")
SecureHandlerWrapScript=function(row,event,owner,pre) wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre} end
RegisterStateDriver=function(owner,state,condition) drivers[#drivers+1]={owner=owner,state=state,condition=condition} end
local overrides,baseBindings,activeBindings={}, {}, {}
local emitBindingEvents,bindingEventCount=false,0
local function bindingEvent()
    if not emitBindingEvents then return end
    bindingEventCount=bindingEventCount+1
    assert(bindingEventCount<20,"override UPDATE_BINDINGS recursed")
    for _,f in ipairs(frames) do
        if f.events and f.events.UPDATE_BINDINGS and f.scripts.OnEvent then f.scripts.OnEvent(f,"UPDATE_BINDINGS") end
    end
end
local function clearOwner(owner)
    for key,value in pairs(overrides) do if value.owner==owner then overrides[key]=nil end end
end
ClearOverrideBindings=function(owner) assert(not combat,"insecure override clear in combat");clearOwner(owner);bindingEvent() end
SetOverrideBindingClick=function(owner,priority,key,button,mouseButton)
    assert(not combat,"insecure override installed in combat")
    overrides[key]={owner=owner,priority=priority,button=button,mouseButton=mouseButton}
    bindingEvent()
end
SaveBindings=function() error("nearby cast must not persist key bindings") end
SetBinding=function() error("nearby cast must not replace permanent key bindings") end
SetBindingClick=SetBinding
CreateMacro=function() error("nearby cast must not create user macros") end
EditMacro=CreateMacro
local bindingKeys={ACTIONBUTTON1={"1","CTRL-1"},ACTIONBUTTON2={"2"},ACTIONBUTTON3={"3"},
    ACTIONBUTTON4={"4"},ACTIONBUTTON5={"BUTTON1"},ACTIONBUTTON6={"SHIFT-MOUSEWHEELUP"},MULTIACTIONBAR1BUTTON1={"SHIFT-1"}}
GetBindingKey=function(command) return unpack(bindingKeys[command] or {}) end
GetBindingAction=function(key,active)
    if active then
        if activeBindings[key] then return activeBindings[key] end
        if overrides[key] then return "CLICK "..overrides[key].button..":"..overrides[key].mouseButton end
    end
    return baseBindings[key] or ""
end
for command,keys in pairs(bindingKeys) do for _,key in ipairs(keys) do baseBindings[key]=command end end
activeBindings["SHIFT-1"]="CLICK AnotherAddon:LeftButton"
GetCVarBool=function() return false end
local spellNames={[639]="圣光术",[1459]="奥术智慧",[133]="火球术"}
local resolvedSpellOverride,pressHold=false,false
local actions={[1]={kind="spell",id=133,helpful=false},[13]={kind="spell",id=639,helpful=true},
    [2]={kind="macro",id=1,helpful=true},[3]={kind="item",id=2,helpful=true},
    [4]={kind="spell",id=133,helpful=false},[5]={kind="spell",id=1459,helpful=true},
    [6]={kind="spell",id=1459,helpful=true},[61]={kind="spell",id=1459,helpful=true}}
GetActionInfo=function(slot) local a=actions[slot];if a then return a.kind,a.id,a.subType end end
IsHelpfulAction=function(slot,allowNeutral)
    local a=actions[slot]
    return a and (a.helpful or allowNeutral==true and a.neutral==true)
end
C_Spell={GetSpellName=function(id) return spellNames[id] end,
    GetSpellSubtext=function() return "" end,
    GetSpellInfo=function(name)
        if resolvedSpellOverride then return {spellID=resolvedSpellOverride} end
        for id,spell in pairs(spellNames) do if name==spell or name==spell.."(等级 2)" then return {spellID=id} end end
    end,
    IsPressHoldReleaseSpell=function() return pressHold end,
    DoesSpellExist=function(name)
        for _,spell in pairs(spellNames) do if name==spell or name==spell.."(等级 2)" then return true end end
        return false
    end}
for i=1,6 do
    local b=frame("CheckButton","ActionButton"..i,UIParent)
    b.action=i==1 and 13 or i
    b:SetAttribute("action",i) -- current paginated .action must win over stale attribute
end
MultiBarBottomLeftButton1=frame("CheckButton","MultiBarBottomLeftButton1",UIParent)
MultiBarBottomLeftButton1.action=61
local units={nameplate1={guid="Player-nearby",name="Windfury Emberbeard",targetName="Windfury Emberbeard",player=true,dead=false,offline=false},
    target={guid="Creature-original",name="原NPC",player=false,dead=false,offline=false}}
UnitGUID=function(unit) return units[unit] and units[unit].guid end
UnitName=function(unit) return units[unit] and units[unit].name end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player end
UnitExists=function(unit) return units[unit]~=nil end
local mouseOver=true
MouseIsOver=function() return mouseOver end
units.player={guid="Player-self",name="自己",targetName="自己",player=true,side="friendly",dead=false,offline=false,unit="player"}
units.nameplate1.side,units.nameplate1.unit="friendly","nameplate1"
units.target.side,units.target.unit="enemy","target"
local originalTarget=units.target
local targetExistsOverride
local exists=UnitExists
UnitExists=function(unit)
    if unit=="target" and targetExistsOverride~=nil then
        if targetExistsOverride=="unknown" then return nil end
        return targetExistsOverride
    end
    return exists(unit)
end
UnitIsDeadOrGhost=function(unit) return units[unit] and units[unit].dead end
local deathConditionOverride
SecureCmdOptionParse=function(condition)
    if deathConditionOverride~=nil then
        if deathConditionOverride=="error" then error("diagnostic parser unavailable") end
        if deathConditionOverride=="nil" then return nil end
        return deathConditionOverride
    end
    local unit=condition:match("^%[@(player),dead%] dead; alive$")
        or condition:match("^%[@(target),dead%] dead; alive$")
    assert(unit,"only fixed scoped death expressions may be inspected")
    return units[unit] and units[unit].dead==true and "dead" or "alive"
end
UnitIsConnected=function(unit) local value=units[unit];return value and not value.offline end
UnitCanAssist=function(_,unit) return units[unit] and units[unit].side=="friendly" end
UnitCanAttack=function(_,unit) return units[unit] and units[unit].side=="enemy" end
IsHarmfulAction=function(slot,allowNeutral)
    eq(allowNeutral,false,"harmful discovery excludes neutral actions")
    local action=actions[slot];return action and action.kind=="spell" and action.id==133
end
local foci={}
GetMouseFoci=function() return foci end
GetMacroInfo=function() error("authorized name bridge must never read user macros") end
GetMacroIndexByName=GetMacroInfo
GetActionText=GetMacroInfo
SetCVar=function() error("name bridge does not change global native mouseover settings") end
local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.NativeMacroOnly=true
NS.PreserveCastTarget=true
NS.LegacyNameBridge=true
NS.Initialize(nil)
NS.DB.mouseoverRequested=false
NS.DB.legacyNameBridgeEnabled=true
NS.DB.shown=true
NS.ReadUnit=function(unit,side)
    local value=units[unit]
    return value and value.side==side and value or nil
end
NS.NameplateTokens=function()
    local result={}
    for unit in pairs(units) do if unit:match("^nameplate%d+$") then result[#result+1]=unit end end
    return result
end
C_NamePlate={GetNamePlates=function()
    local result={}
    for _,unit in ipairs(NS.NameplateTokens()) do result[#result+1]={namePlateUnitToken=unit} end
    return result
end}
local records={}
NS.Diagnostics={Enabled=function() return true end,Record=function(kind,data)
    records[#records+1]={kind=kind,data=data};return true
end}
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
local Cast=NS.NearbyCast
eq(Cast.legacyName,true,"explicit authorization enables only the name-bridge startup exception")
eq(NS.NativeMacroOnly,true,"native policy remains enabled for other disabled modules")
eq(NS.PreserveCastTarget,true,"global legacy fixture policy is not changed")
eq(Cast.BuildGUIDMacro("Creature-0-1-2-3-4-5","火球术"),nil,"GUID macro generation stays disabled")
eq(Cast.GuardMacro("/cast 火球术"),nil,"user macro parsing stays disabled")
eq(Cast.BuildUserMacro("敌人","/cast 火球术",true),nil,"user macros are not copied")
eq(Cast.BuildUserFallback("/cast 火球术"),nil,"user macro fallback stays native")
eq(Cast.FrozenUserMacro("/cast 火球术"),nil,"combat macro preparation stays disabled")
eq(Cast.MacroHasHarmfulCast("/cast 火球术"),false,"no user macro is parsed for harmful branches")
eq(Cast.SnapshotRow({}),nil,"combat snapshots remain disabled")
local restoreMacro=Cast.BuildMacro("Windfury Emberbeard","圣光术",true,"friendly")
yes(restoreMacro:find("/stopmacro [combat][@player,dead]",1,true),"name action scopes native death guard to the player")
yes(restoreMacro:find("/targetexact [nocombat] Windfury Emberbeard",1,true),"complete player name survives")
yes(restoreMacro:match("/targetlasttarget$"),"existing current target has a restoration command")
yes(Cast.BuildMacro("Windfury Emberbeard","圣光术",false,"friendly"):match("/cleartarget$"),"original lack of target is restored")
eq(Cast.BuildMacro("Windfury Emberbeard","圣光术",nil,"friendly"),nil,"unknown original target presence is rejected")
for _,bad in ipairs({"", "bad\n/run x", "bad;extra", "bad[@player]", " bad"}) do
    eq(Cast.BuildMacro(bad,"圣光术",true,"friendly"),nil,"name cannot inject commands")
end

local row=frame("Button","LegacyAlly",UIParent)
row.side,row.unit,row.expectedGUID="friendly","nameplate1",units.nameplate1.guid
NS.HoveredTile=row;foci={row}
yes(Cast.Install(row),"friendly row installs the authorized path")
local wrapperCount=#wrappers
Cast.Install(row)
eq(#wrappers,wrapperCount,"installation is idempotent")
eq(drivers[1].condition,"[combat] combat; [@player,dead] dead; idle","secure driver clears for player death rather than a dead current target")
yes(Cast.owner:GetAttribute("_onstate-combat"):find('newstate ~= "idle"',1,true),"combat and death share safe binding cleanup")
eq(#Cast.DiscoverActions("friendly"),1,"only plain helpful spell with available keys is found")
local entered,count=Cast.Enter(row)
eq(entered,true,"nameplate player can be prepared despite global mouseoverRequested=false")
eq(count,2,"both original helpful keyboard keys are temporarily routed")
eq(overrides["2"],nil,"macro key is untouched")
eq(overrides["3"],nil,"item key is untouched")
eq(overrides["SHIFT-1"],nil,"other addon override is not claimed")
local proxy=_G[overrides["1"].button]
eq(proxy:GetAttribute("macrotext"),restoreMacro,"prepared action matches the approved name bridge")
eq(proxy:GetAttribute("unit"),nil,"proxy does not execute against a read-only nameplate token")
local status=Cast.Status(row)
eq(status.prepared,true,"status reports prepared names only for the active valid row")
eq(status.count,2,"status exposes actual routed key count")
eq(status.unit,"nameplate1","status exposes current source token")
eq(status.guid,units.nameplate1.guid,"status exposes the identity being prepared")

local function press(buttonProxy)
    buttonProxy:GetScript("PreClick")(buttonProxy,"LeftButton",false)
    buttonProxy:GetScript("PostClick")(buttonProxy,"LeftButton",false)
end
press(proxy)
eq(records[#records-1].kind,"NAME_BRIDGE_PRE","hardware preparation has its own log event")
eq(records[#records].kind,"NAME_BRIDGE_POST","post-click observation has its own log event")
eq(records[#records].data.beforeTargetGUID,originalTarget.guid,"attempt records original target identity")
eq(records[#records].data.afterTargetGUID,originalTarget.guid,"attempt reads the target after the hardware callback")
eq(records[#records].data.targetRestorationObserved,true,"unchanged public target identity is recorded as observation")
eq(records[#records].data.recipientProven,false,"target readback never claims the spell recipient")
eq(records[#records].data.spellID,639,"diagnostics records the helpful spell")
eq(records[#records-1].data.version,NS.VERSION,"pre records the currently loaded candidate version")
eq(records[#records-1].data.deathGuardUnit,"player","pre labels the player-only death policy")
eq(records[#records-1].data.configuredCommand,"ACTIONBUTTON1","pre records the configured action binding")
eq(records[#records-1].data.configuredKey1,"1","pre records the first configured key")
eq(records[#records-1].data.configuredKey2,"CTRL-1","pre records the alternate configured key")
eq(records[#records-1].data.playerDead,false,"pre distinguishes a living player")
eq(records[#records-1].data.playerDeadState,"public","pre distinguishes public false from an unreadable state")
eq(records[#records-1].data.targetDead,false,"pre records the original target's separate death state")
eq(records[#records-1].data.nativePlayerDead,false,"pre observes the fixed native player-death condition")
eq(records[#records-1].data.nativeTargetDead,false,"pre observes the fixed native target-death condition")
eq(records[#records-1].data.generatedDeathGuardMatches,true,"pre checks the actual internal proxy macro guard")
eq(records[#records].data.afterGeneratedDeathGuardMatches,true,"post repeats the actual internal guard observation")
eq(records[#records].data.afterPlayerDeadState,"public","post records its own death-read state")
for _,event in ipairs(records) do yes(not event.kind:find("GUID",1,true),"name bridge emits no GUID-attempt events") end

-- Interpret only the first generated stop condition and the driver condition.
-- This is an offline rule model, not a client macro or secure-engine execution.
local function firstLineStops(macro,playerDead,targetDead,inCombat)
    local first=macro:match("^([^\n]+)")
    if not first:find("/stopmacro",1,true) then return false end
    for clause in first:gmatch("%[([^%]]+)%]") do
        if clause=="combat" and inCombat then return true end
        if clause=="@player,dead" and playerDead then return true end
        if clause=="dead" and targetDead then return true end
    end
    return false
end
eq(firstLineStops("/stopmacro [combat][dead]\n/cast 旧版",false,true,false),true,"model reproduces the old corpse-current-target guard defect")
eq(firstLineStops(restoreMacro,false,true,false),false,"living hovered friend remains admissible with a corpse current target")
eq(firstLineStops(restoreMacro,false,false,false),false,"live current targets retain the same admission rule")
eq(firstLineStops(restoreMacro,false,nil,false),false,"empty original target does not trigger player death")
eq(firstLineStops(restoreMacro,true,false,false),true,"player death still blocks the generated name action")
eq(firstLineStops(restoreMacro,false,false,true),true,"combat still blocks the out-of-combat name action")
local function modelDriver(condition,playerDead,targetDead,inCombat)
    if inCombat then return "combat" end
    if condition:find("[@player,dead] dead",1,true) and playerDead
        or condition:find("[dead] dead",1,true) and targetDead then return "dead" end
    return "idle"
end
eq(modelDriver("[combat] combat; [dead] dead; idle",false,true,false),"dead","driver model reproduces old corpse-target binding cleanup")
eq(modelDriver(drivers[1].condition,false,true,false),"idle","corrected driver keeps bindings when only the old target is dead")
eq(modelDriver(drivers[1].condition,true,false,false),"dead","corrected driver still clears bindings for a dead player")
eq(modelDriver(drivers[1].condition,false,false,true),"combat","corrected driver still clears outside-combat bindings on combat entry")
for _,side in ipairs({"friendly","enemy"}) do
    local fallback=Cast.BuildFallback(side=="friendly" and "圣光术" or "火球术",side)
    yes(fallback:match("^/stopmacro %[@player,dead%]\n"),side.." fallback scopes death to player")
    eq(firstLineStops(fallback,false,true,false),false,side.." fallback does not stop because another target is a corpse")
    eq(firstLineStops(fallback,true,false,false),true,side.." fallback still blocks a dead player")
    yes(fallback:find("nodead",1,true),side.." fallback retains recipient living-state eligibility")
end
originalTarget.dead=true
yes(overrides["1"],"corpse-state driver comparison starts with an owned friendly key")
local corpseDriverState=modelDriver(drivers[1].condition,units.player.dead,originalTarget.dead,combat)
if corpseDriverState~="idle" then clearOwner(Cast.owner) end
eq(corpseDriverState,"idle","corpse original target does not enter driver cleanup state")
yes(overrides["1"],"modeled secure driver preserves the friendly key when only target is dead")
press(proxy)
eq(proxy:GetAttribute("macrotext"),restoreMacro,"a corpse original target still prepares the guarded friend-and-restore command")
eq(records[#records-1].data.playerDead,false,"corpse-target pre records player alive separately")
eq(records[#records-1].data.targetDead,true,"corpse-target pre records the corpse")
eq(records[#records-1].data.nativePlayerDead,false,"native player condition does not match the corpse target")
eq(records[#records-1].data.nativeTargetDead,true,"native target condition explains the old guard failure")
eq(records[#records-1].data.generatedDeathGuardMatches,true,"corpse-target pre confirms the corrected proxy guard")
eq(records[#records].data.afterTargetDead,true,"post preserves the separate current-target death readback")
eq(records[#records].data.targetRestorationObserved,true,"unchanged corpse readback remains an observation only")
row.unit,row.expectedGUID="player",units.player.guid
Cast.Enter(row);press(proxy)
yes(proxy:GetAttribute("macrotext"):find("/targetexact [nocombat] 自己",1,true),"self hover also prepares while the original target is a corpse")
eq(records[#records-1].data.playerDead,false,"self hover explicitly records the player alive")
eq(records[#records-1].data.targetDead,true,"self hover keeps the separate corpse-target diagnostic")
row.unit,row.expectedGUID="nameplate1",units.nameplate1.guid
Cast.Enter(row)
originalTarget.dead=false

for _,bad in ipairs({"error","nil",secret,"unexpected",27}) do
    deathConditionOverride=bad
    press(proxy)
    eq(proxy:GetAttribute("macrotext"),restoreMacro,"diagnostic condition failures cannot alter the prepared action")
    local expected=bad=="error" and "error" or bad=="nil" and "nil" or bad==secret and "restricted" or "invalid_result"
    eq(records[#records-1].data.nativePlayerDeadState,expected,"pre preserves parser failure type without inferring alive")
    eq(records[#records-1].data.nativePlayerDead,nil,"unknown native death result has no invented boolean")
    eq(records[#records].data.afterNativeTargetDeadState,expected,"post preserves its own parser read state")
end
deathConditionOverride=nil
local parser=SecureCmdOptionParse
SecureCmdOptionParse=nil;press(proxy)
eq(records[#records-1].data.nativePlayerDeadState,"unavailable","missing native parser is explicit")
eq(proxy:GetAttribute("macrotext"),restoreMacro,"missing diagnostic parser does not disable the action")
SecureCmdOptionParse=parser

local deathAPI=UnitIsDeadOrGhost
for _,bad in ipairs({"error","nil",secret,"not_boolean"}) do
    UnitIsDeadOrGhost=function(unit)
        if unit~="target" then return deathAPI(unit) end
        if bad=="error" then error("target diagnostic unavailable") end
        if bad=="nil" then return nil end
        return bad
    end
    press(proxy)
    eq(proxy:GetAttribute("macrotext"),restoreMacro,"target-death diagnostic failure cannot change live hovered eligibility")
    eq(records[#records-1].data.targetDeadState,bad=="not_boolean" and "nonboolean" or bad==secret and "restricted" or bad,"target-death API state stays explicit")
    eq(records[#records-1].data.targetDead,nil,"unreadable current-target death never becomes false")
end
UnitIsDeadOrGhost=deathAPI

local getter=proxy.GetAttribute
for _,bad in ipairs({"error","nil",secret,27,"/stopmacro [combat][dead]\n/cast stale"}) do
    proxy.GetAttribute=function(self,key)
        if key~="macrotext" then return getter(self,key) end
        if bad=="error" then error("diagnostic getter unavailable") end
        if bad=="nil" then return nil end
        return bad
    end
    press(proxy)
    eq(proxy.attrs.macrotext,restoreMacro,"failed or mismatched diagnostic macro read does not rewrite the prepared action")
    local expected=bad=="error" and "error" or bad=="nil" and "nil" or bad==secret and "restricted"
        or type(bad)~="string" and "nonstring" or "public"
    eq(records[#records-1].data.generatedDeathGuardMatchesState,expected,"actual proxy guard read state stays explicit")
    local expectedMatch
    if expected=="public" then expectedMatch=false end
    eq(records[#records-1].data.generatedDeathGuardMatches,expectedMatch,"mismatched guard is false only for a public macro read")
end
proxy.GetAttribute=getter

local logger=NS.Diagnostics
local diagnosticReads=0
SecureCmdOptionParse=function(condition) diagnosticReads=diagnosticReads+1;return parser(condition) end
NS.Diagnostics={Enabled=function() return false end,Record=function() error("disabled logger must not receive records") end}
eq(pcall(press,proxy),true,"disabled logging cannot abort the action")
eq(diagnosticReads,0,"disabled logging performs no extra macro-condition reads")
eq(proxy:GetAttribute("macrotext"),restoreMacro,"disabled logging leaves generated action unchanged")
NS.Diagnostics={Enabled=function() error("logging status unavailable") end,Record=function() error("status failure must stop observation") end}
eq(pcall(press,proxy),true,"logger status failure cannot abort the action")
eq(diagnosticReads,0,"failed logging status performs no extra condition reads")
NS.Diagnostics={Enabled=function() return true end,Record=function() error("disk observer failure") end}
eq(pcall(press,proxy),true,"logging record failure cannot abort the action")
eq(proxy:GetAttribute("macrotext"),restoreMacro,"record failure does not alter action attributes")
NS.Diagnostics=nil
eq(pcall(press,proxy),true,"missing logger remains optional")
eq(proxy:GetAttribute("macrotext"),restoreMacro,"missing logger leaves generated action unchanged")
SecureCmdOptionParse=parser;NS.Diagnostics=logger
local clearedByObserver=false
NS.Diagnostics={Enabled=function() return true end,Record=function(kind,data)
    if kind=="NAME_BRIDGE_PRE" and not clearedByObserver then
        clearedByObserver=true;Cast.Leave(row)
    end
end}
eq(pcall(press,proxy),true,"observer callback cleanup does not cause a preparation error")
eq(next(overrides),nil,"observer-requested cleanup is not undone by later logging")
eq(proxy:GetAttribute("type"),nil,"diagnostics never reinstall an action after cleanup")
eq(proxy:GetAttribute("macrotext"),nil,"post diagnostic reads do not restore a cleared macro")
NS.Diagnostics=logger;NS.HoveredTile=row;Cast.Enter(row)

units.target=nil;press(proxy)
yes(proxy:GetAttribute("macrotext"):match("/cleartarget$"),"each key press rechecks absent original target")
eq(records[#records].data.beforeTargetExists,false,"absence of original target is recorded explicitly")
eq(records[#records].data.targetRestorationObserved,true,"observed empty target can be reported separately")
eq(records[#records-1].data.playerDead,false,"empty original target retains the separate living player diagnosis")
eq(records[#records-1].data.targetDeadState,"nil","empty original target is not invented as public false")
eq(records[#records-1].data.nativeTargetDead,false,"explicit native target-death condition is false with no target")
units.target=originalTarget
targetExistsOverride="unknown";press(proxy)
eq(proxy:GetAttribute("type"),nil,"unknown prior target existence cannot trigger a name switch")
eq(records[#records].data.reason,"target_presence_unknown","unknown presence has a distinct reason")
targetExistsOverride=secret;press(proxy)
eq(proxy:GetAttribute("type"),nil,"secret prior target existence cannot trigger a name switch")
targetExistsOverride=nil
units.target=units.nameplate1;press(proxy)
yes(not proxy:GetAttribute("macrotext"):find("targetexact",1,true),"already-current exact GUID does not touch target history again")
units.target=originalTarget
units.nameplate1.guid="Player-reused";press(proxy)
eq(proxy:GetAttribute("type"),nil,"reused source token does not cast or switch targets")
units.nameplate1.guid=row.expectedGUID
units.nameplate1.dead=true;press(proxy)
eq(proxy:GetAttribute("type"),nil,"dead target does not get a generated name action")
units.nameplate1.dead=false;units.nameplate1.offline=true;press(proxy)
eq(proxy:GetAttribute("type"),nil,"offline player does not get a generated name action")
units.nameplate1.offline=false
units.player.dead=true;press(proxy)
eq(proxy:GetAttribute("type"),nil,"player death is rechecked immediately before a key action")
eq(Cast.Status(row).reason,"player_dead","status explains player death")
eq(records[#records-1].data.playerDead,true,"blocked request logs actual player death")
eq(records[#records-1].data.generatedDeathGuardMatchesState,"not_applicable","blocked request does not claim a prepared internal macro")
local deadDriverState=modelDriver(drivers[1].condition,units.player.dead,originalTarget.dead,combat)
if deadDriverState~="idle" then clearOwner(Cast.owner) end
eq(deadDriverState,"dead","driver recognizes player death even with a live current target")
eq(overrides["1"],nil,"modeled secure driver clears the temporary key when the player is dead")
for _,f in ipairs(frames) do if f.events and f.events.PLAYER_DEAD then f.scripts.OnEvent(f,"PLAYER_DEAD") end end
eq(overrides["1"],nil,"death event immediately returns owned keys outside combat")
units.player.dead=false

NS.HoveredTile=row;Cast.Enter(row)
actions[13]={kind="macro",id=133,subType="spell",helpful=true};press(proxy)
eq(proxy:GetAttribute("type"),"action","an action changed into a macro executes its original native slot")
eq(proxy:GetAttribute("action"),13,"changed macro is forwarded without inspecting its text")
actions[13]={kind="item",id=2,helpful=true};press(proxy)
eq(proxy:GetAttribute("type"),"action","changed item keeps its original native action")
actions[13]={kind="spell",id=639,helpful=true}
ActionButton1.CalculateAction=function() return 61 end
press(proxy)
eq(records[#records].data.spellID,1459,"hardware preflight uses current action-page resolution")
ActionButton1.CalculateAction=function() return secret end
press(proxy)
eq(proxy:GetAttribute("type"),nil,"restricted action-page result does not reuse a stale action")
ActionButton1.CalculateAction=nil
activeBindings["1"]="CLICK AnotherAddon:LeftButton"
activeBindings["CTRL-1"]="CLICK AnotherAddon:LeftButton"
press(proxy)
eq(proxy:GetAttribute("type"),nil,"a newly claimed third-party key is not used by a stale proxy")
activeBindings["1"],activeBindings["CTRL-1"]=nil,nil
pressHold=true;eq(#Cast.DiscoverActions("friendly"),0,"press-hold spell is not intercepted");pressHold=false
pressHold=true
eq(Cast.Enter(row),false,"no supported spell leaves zero routed keys")
eq(Cast.Status(row).reason,"no_supported_spell","status distinguishes an empty action set")
pressHold=false;NS.HoveredTile=row;Cast.Enter(row)
C_Spell.GetSpellSubtext=function() return secret end
eq(#Cast.DiscoverActions("friendly"),0,"restricted rank cannot become the wrong spell rank")
C_Spell.GetSpellSubtext=function() return "等级 2" end
resolvedSpellOverride=1459
eq(#Cast.DiscoverActions("friendly"),0,"rank must resolve back to the original spell ID")
resolvedSpellOverride=false;C_Spell.GetSpellSubtext=function() return "" end

Cast.Enter(row);row.shown=false;press(proxy)
eq(proxy:GetAttribute("type"),nil,"hidden row cannot dispatch a stale prepared action")
eq(Cast.Status(row).reason,"hidden","hidden row reports no preparation")
row.shown=true;NS.DB.shown=false
eq(Cast.Enter(row),false,"hidden addon cannot claim keys")
NS.DB.shown=true;NS.DB.legacyNameBridgeEnabled=false
eq(Cast.Enter(row),false,"independent bridge switch blocks entry")
eq(Cast.Status(row).reason,"disabled","independent disabled status is distinct")
NS.DB.legacyNameBridgeEnabled=true
units.player.dead=secret
eq(Cast.Enter(row),false,"unreadable player death state cannot prepare a switch")
units.player.dead=false

-- Every normal unit type can use the approved name path, including stable
-- player and party aliases. Enemy discovery still excludes user macros/items.
local selfRow=frame("Button","LegacySelf",UIParent)
selfRow.side,selfRow.unit,selfRow.expectedGUID="friendly","player",units.player.guid
Cast.Install(selfRow);NS.HoveredTile=selfRow
yes(Cast.Enter(selfRow),"stable player alias uses authorized plain-spell bridge")
units.party1={guid="Player-party",name="队友",targetName="队友-服务器",player=true,side="friendly",dead=false,offline=false,unit="party1"}
local party=frame("Button","LegacyParty",UIParent)
party.side,party.unit,party.expectedGUID="friendly","party1",units.party1.guid
Cast.Install(party);NS.HoveredTile=party
yes(Cast.Enter(party),"stable party alias also uses the name path")
yes(Cast.proxies[1]:GetAttribute("macrotext"):find("队友-服务器",1,true),"cross-realm complete name is retained")

units.nameplate2={guid="Player-enemy",name="敌方玩家",targetName="敌方玩家-服务器",player=true,side="enemy",dead=false,offline=false,unit="nameplate2"}
local enemy=frame("Button","LegacyEnemy",UIParent)
enemy.side,enemy.unit,enemy.expectedGUID="enemy","nameplate2",units.nameplate2.guid
Cast.Install(enemy);NS.HoveredTile=enemy
yes(Cast.Enter(enemy),"enemy player ordinary harmful spells can be routed")
eq(overrides["1"],nil,"enemy does not reuse helpful spell keys")
yes(overrides["4"],"enemy binds the ordinary harmful spell key")
local enemyProxy=_G[overrides["4"].button]
yes(enemyProxy:GetAttribute("macrotext"):find("@target,harm,nodead",1,true),"enemy uses the harmful relation")
yes(enemyProxy:GetAttribute("macrotext"):find("敌方玩家-服务器",1,true),"enemy player has its complete name")

units.nameplate2={guid="Creature-wolf",name="狼",targetName="狼",player=false,side="enemy",dead=false,offline=false,unit="nameplate2"}
enemy.expectedGUID=units.nameplate2.guid
NS.HoveredTile=enemy;yes(Cast.Enter(enemy),"confirmed unique visible NPC can use name selection")
units.nameplate3={guid="Creature-another-wolf",name="狼",targetName="狼",player=false,side="enemy",dead=false,offline=false,unit="nameplate3"}
press(enemyProxy)
eq(enemyProxy:GetAttribute("type"),nil,"newly discovered same-name NPC stops the pending name action")
eq(records[#records].data.reason,"not_unique","ambiguity is reported without GUID precision claims")
eq(Cast.Enter(enemy),false,"ambiguous NPC does not install new name-key overrides")
eq(Cast.Status(enemy).reason,"not_unique","ambiguous NPC remains unprepared")
units.target=units.nameplate2
yes(Cast.Enter(enemy),"already-current matching GUID needs no name selection even with a duplicate")
yes(not enemyProxy:GetAttribute("macrotext"):find("targetexact",1,true),"same-current NPC uses its original target directly")
units.target=originalTarget;units.nameplate3=nil
local plateReader=C_NamePlate.GetNamePlates
C_NamePlate.GetNamePlates=function() error("unreadable candidate list") end
eq(Cast.Enter(enemy),false,"incomplete NPC enumeration stays unprepared")
C_NamePlate.GetNamePlates=plateReader

-- The new rectangle is permitted only through its controlled parent-relation
-- callback. Global ValidToken remains unchanged.
units.nameplate2target={guid="Player-victim",name="受击队友",targetName="受击队友-服务器",player=true,
    side="friendly",dead=false,offline=false,unit="nameplate2target"}
local child=frame("Button","LegacyVictim",enemy)
child.owner,child.bridgeTarget=enemy,true
child.side,child.unit,child.expectedGUID="friendly","nameplate2target",units.nameplate2target.guid
enemy.enemyTargetButton=child
child.bindingReady,child.bindingOwnerGUID=true,enemy.expectedGUID
local callbackEnabled=true
NS.ReadBridgeTarget=function(candidate)
    local value=callbackEnabled and candidate==child and units[candidate.unit] or nil
    if value and value.dead==false and value.offline==false
        and (value.side=="friendly" or value.side=="enemy") then return value end
end
eq(NS.ValidToken(child.unit),false,"relationship token is not added to global allowed units")
yes(Cast.Install(child),"controlled child gets independent leave/hide cleanup")
NS.HoveredTile=nil;NS.HoveredEnemyTarget=child;foci={child}
yes(Cast.Enter(child),"friendly child target can route its own helpful keys")
yes(Cast.proxies[1]:GetAttribute("macrotext"):find("受击队友-服务器",1,true),"child uses victim name rather than enemy parent name")
eq(Cast.Status(child).prepared,true,"child status refers to the actual hovered recipient")
callbackEnabled=false
eq(Cast.Enter(child),false,"unverified relationship callback cannot be replaced by a guessed unit")
callbackEnabled=true
local targetCallback=NS.ReadBridgeTarget
NS.ReadBridgeTarget=function(candidate)
    local value=targetCallback(candidate)
    if not value then return end
    local copy={};for key,field in pairs(value) do copy[key]=field end
    copy.unit="nameplate9target"
    return copy
end
eq(Cast.Enter(child),false,"controlled callback must resolve the exact parent relationship token")
NS.ReadBridgeTarget=targetCallback
enemy.expectedGUID="Creature-stale"
eq(Cast.Enter(child),false,"changed enemy owner blocks its child even with a matching victim")
enemy.expectedGUID=units.nameplate2.guid
local aliasOwner=frame("Button","LegacyTargetAlias",UIParent)
aliasOwner.side,aliasOwner.unit,aliasOwner.expectedGUID="enemy","target","Creature-stale"
local aliasChild=frame("Button","LegacyTargetTarget",aliasOwner)
units.targettarget={guid="Player-alias-victim",name="关系目标",targetName="关系目标",player=true,
    side="friendly",dead=false,offline=false,unit="targettarget"}
aliasChild.owner,aliasChild.bridgeTarget=aliasOwner,true
aliasChild.side,aliasChild.unit,aliasChild.expectedGUID="friendly","targettarget",units.targettarget.guid
aliasOwner.enemyTargetButton=aliasChild
aliasChild.bindingReady,aliasChild.bindingOwnerGUID=true,aliasOwner.expectedGUID
Cast.Install(aliasChild);NS.HoveredEnemyTarget=aliasChild
eq(NS.ValidToken("targettarget"),true,"regression uses a globally valid relationship alias")
eq(Cast.Enter(aliasChild),false,"invalid child owner cannot fall back to ordinary ReadUnit even for targettarget")
units.targettarget=nil;aliasChild.shown=false;NS.HoveredEnemyTarget=child
units.nameplate2target={guid="Creature-pet",name="友方宠物",targetName="友方宠物",player=false,
    side="friendly",dead=false,offline=false,unit="nameplate2target"}
child.expectedGUID=units.nameplate2target.guid
yes(Cast.Enter(child),"confirmed unique friendly NPC child can use helpful name action")
units.nameplate3={guid="Creature-pet-duplicate",name="友方宠物",targetName="友方宠物",player=false,
    side="friendly",dead=false,offline=false,unit="nameplate3"}
eq(Cast.Enter(child),false,"same-name pet child is rejected conservatively")
eq(Cast.Status(child).reason,"not_unique","same-name child clearly reports the limitation")
units.nameplate3=nil
-- Two visible rectangles can expose two same-name NPCs without either victim
-- having a nameplate or target/focus alias. Both must prevent name selection.
units.nameplate4={guid="Creature-other-owner",name="另一个敌人",targetName="另一个敌人",player=false,
    side="enemy",dead=false,offline=false,unit="nameplate4"}
units.nameplate4target={guid="Creature-other-pet",name="友方宠物",targetName="友方宠物",player=false,
    side="friendly",dead=false,offline=false,unit="nameplate4target"}
local otherOwner=frame("Button","LegacyOtherOwner",UIParent)
otherOwner.side,otherOwner.unit,otherOwner.expectedGUID="enemy","nameplate4",units.nameplate4.guid
local otherChild=frame("Button","LegacyOtherVictim",otherOwner)
otherChild.owner,otherChild.bridgeTarget=otherOwner,true
otherChild.side,otherChild.unit,otherChild.expectedGUID="friendly","nameplate4target",units.nameplate4target.guid
otherOwner.enemyTargetButton=otherChild
otherChild.bindingReady,otherChild.bindingOwnerGUID=true,otherOwner.expectedGUID
Cast.Install(otherChild)
local otherReadable=true
NS.ReadBridgeTarget=function(candidate)
    if candidate==otherChild then
        local value=otherReadable and units[candidate.unit] or nil
        if value and value.dead==false and value.offline==false
            and (value.side=="friendly" or value.side=="enemy") then return value end
        return nil
    end
    return targetCallback(candidate)
end
eq(NS.ValidToken(otherChild.unit),false,"other rectangle does not expand global allowed units")
NS.HoveredEnemyTarget=child
eq(Cast.Enter(child),false,"first rectangle sees same-name different-GUID victim in the other rectangle")
NS.HoveredEnemyTarget=otherChild
eq(Cast.Enter(otherChild),false,"second rectangle also sees the first known victim")
units.nameplate5={guid="Creature-third-pet",name="友方宠物",targetName="友方宠物",player=false,
    side="enemy",dead=false,offline=false,unit="nameplate5"}
local sameNameMain=frame("Button","LegacySameNameMain",UIParent)
sameNameMain.side,sameNameMain.unit,sameNameMain.expectedGUID="enemy","nameplate5",units.nameplate5.guid
Cast.Install(sameNameMain);NS.HoveredEnemyTarget=nil;NS.HoveredTile=sameNameMain
eq(Cast.Enter(sameNameMain),false,"normal NPC tile also considers victims exposed only by target rectangles")
units.nameplate5=nil;NS.HoveredTile=nil;NS.HoveredEnemyTarget=child
units.nameplate4target.guid=units.nameplate2target.guid
otherChild.expectedGUID=units.nameplate4target.guid
yes(Cast.Enter(child),"two validated relationships to the same GUID count as one NPC")
otherReadable=false
yes(Cast.Enter(child),"another rectangle's unavailable spell callback alone does not hide its readable identity")
units.nameplate4target.guid=secret
eq(Cast.Enter(child),false,"visible bound rectangle with unreadable identity prevents a uniqueness claim")
otherChild.shown=false
yes(Cast.Enter(child),"explicitly hidden unreadable rectangle is outside displayed candidate coverage")
otherChild.shown=true;otherReadable=true;units.nameplate4target.guid=units.nameplate2target.guid
otherOwner.expectedGUID="Creature-stale-owner"
eq(Cast.Enter(child),false,"visible rectangle with a stale owning enemy fails closed")
otherOwner.expectedGUID=units.nameplate4.guid

-- Refresh clears a dead/offline/neutral child's action identity and side, but
-- the secure existence driver still shows its relationship rectangle. Name
-- enumeration must not mistake that ineligibility for an unreadable identity.
local otherVictim=units.nameplate4target
otherVictim.guid,otherVictim.name,otherVictim.targetName="Creature-dead-victim","另一只怪物","另一只怪物"
otherVictim.dead=true
otherChild.expectedGUID,otherChild.side=nil,nil
eq(NS.ReadBridgeTarget(otherChild),nil,"dead rectangle has no eligible action snapshot")
local unique,reason=Cast.KnownUniqueNPC(units.nameplate2,enemy)
eq(unique,true,"unrelated dead target rectangle does not block a unique main NPC")
eq(reason,"known_unique","successful uniqueness observation has a precise reason")
NS.HoveredTile=enemy;NS.HoveredEnemyTarget=nil
yes(Cast.Enter(enemy),"real name-bridge preflight admits unique main NPC with an unrelated dead child")
Cast.Leave(enemy)
otherVictim.name,otherVictim.targetName="狼","狼"
unique,reason=Cast.KnownUniqueNPC(units.nameplate2,enemy)
eq(unique,false,"same-name dead NPC exposed only by a child rectangle still blocks selection")
eq(reason,"duplicate_name","dead same-name rejection is not an unknown-identity report")
otherVictim.name,otherVictim.targetName="另一只怪物","另一只怪物"
otherVictim.dead=false;otherVictim.offline=true
eq(Cast.KnownUniqueNPC(units.nameplate2,enemy),true,"unrelated offline identity still participates in name enumeration")
otherVictim.offline=false;otherVictim.side=nil
eq(Cast.KnownUniqueNPC(units.nameplate2,enemy),true,"unrelated neutral identity does not require spell eligibility")
otherVictim.guid=secret
unique,reason=Cast.KnownUniqueNPC(units.nameplate2,enemy)
eq(unique,false,"unknown child identity remains fail closed even without an action snapshot")
eq(reason,"identity_unreadable","unknown child GUID is logged distinctly")
otherVictim.guid="Creature-dead-victim"
local oldName=UnitName
UnitName=function(unit)
    if unit==otherChild.unit then units.nameplate4.guid="Creature-reused-owner" end
    return oldName(unit)
end
unique,reason=Cast.KnownUniqueNPC(units.nameplate2,enemy)
eq(unique,false,"owner change during identity reads rejects the entire relationship snapshot")
eq(reason,"relationship_changed","owner replacement is distinguishable from duplicate names")
UnitName=oldName;units.nameplate4.guid=otherOwner.expectedGUID
otherChild.shown=false;NS.HoveredTile=nil;NS.HoveredEnemyTarget=child
units.nameplate2target.side,child.side="enemy","enemy"
yes(Cast.Enter(child),"hostile child receives ordinary harmful spell routing")
yes(overrides["4"],"child enemy uses harmful keys")

-- Cleanup and re-entry do not rely on a new physical OnEnter after combat.
mouseOver=false;Cast.Refresh()
eq(next(overrides),nil,"moving away returns only owned bindings")
mouseOver=true;NS.HoveredEnemyTarget=child;Cast.Enter(child)
clearOwner(Cast.owner) -- Model the registered secure driver, not insecure combat writes.
combat=true
for _,f in ipairs(frames) do if f.events and f.events.PLAYER_REGEN_DISABLED then f.scripts.OnEvent(f,"PLAYER_REGEN_DISABLED") end end
eq(Cast.Status(child).reason,"out_of_combat_only","combat never claims a prepared name bridge")
eq(pcall(press,Cast.proxies[1]),true,"combat PreClick only logs and relies on stored native guards")
eq(Cast.Enter(child),false,"combat does not install a new override")
eq(next(overrides),nil,"combat leaves ordinary original keys active")
combat=false;NS.HoveredEnemyTarget=nil;foci={child}
yes(Cast.Reconcile(),"same child focus is restored after combat without targeting anything")
eq(NS.HoveredEnemyTarget,child,"reconcile restores child hover slot rather than parent hover")
Cast.Leave(child)
eq(next(overrides),nil,"child leave returns owned keyboard bindings")
eq(activeBindings["SHIFT-1"],"CLICK AnotherAddon:LeftButton","third-party binding ownership survives all cleanup")
-- Ordinary OnHide uses both the native secure wrapper and the Lua owner cleanup.
NS.HoveredTile=row;NS.HoveredEnemyTarget=nil;Cast.Enter(row)
yes(overrides["1"],"hide test starts with a prepared friendly key")
row.hooks.OnHide(row)
eq(next(overrides),nil,"hiding the row returns its temporary keys")
-- No global flag can enable the mode through an unreadable authorization.
local isolated={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",isolated)
isolated.NativeMacroOnly=true;isolated.LegacyNameBridge=secret
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",isolated)
eq(isolated.NearbyCast.Enter(row),false,"secret authorization remains disabled")
eq(isolated.NearbyCast.BuildGUIDMacro("Creature-0-1-2-3-4-5","火球术"),nil,"disabled policy does not expose a GUID helper")
for _,event in ipairs(records) do
    if event.kind=="NAME_BRIDGE_POST" then eq(event.data.recipientProven,false,"all post-click records remain observations") end
end
local maxNameFields=0
local publicNameFields=true
for _,event in ipairs(records) do
    if event.kind=="NAME_BRIDGE_PRE" or event.kind=="NAME_BRIDGE_POST" then
        local count=1 -- Diagnostics adds professionsGatherMethod after copying.
        for key,value in pairs(event.data) do
            count=count+1
            local kind=type(value)
            if type(key)~="string" or #key>48 or value==secret
                or kind~="string" and kind~="boolean" and kind~="number" then publicNameFields=false end
            if key=="macro" or key=="macrotext" or key=="macroBody" or key=="generatedCommand" then publicNameFields=false end
        end
        maxNameFields=math.max(maxNameFields,count)
    end
end
yes(maxNameFields<=64,"all pre/post fields including added diagnostic context fit the logger field budget")
yes(publicNameFields,"name diagnostics contain public scalars without command text or secret values")
print("Targets authorized name-bridge simulated checks: "..checks.."; maximum diagnostic fields "..maxNameFields.."; no native macro, spell or restoration was executed")
