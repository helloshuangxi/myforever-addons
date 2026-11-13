-- Configuration/preflight simulation only. Snippet text is exercised in a plain
-- Lua branch model, not the restricted engine; no native spell action is run.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local combat,secret,restrictedModel=false,{},false
issecretvalue=function(value) return value==secret end
InCombatLockdown=function() return combat end
local methods,frames,wrappers,drivers={},{},{},{}
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",attrs={},scripts={},refs={},shown=true}, {__index=methods})
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
function methods:GetName() return self.name end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:IsForbidden() return self.forbidden or false end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value) assert(not combat or restrictedModel,"insecure attribute write in combat");self.attrs[key]=value end
function methods:SetFrameRef(key,value) assert(not combat,"insecure frame ref write in combat");self.refs[key]=value end
function methods:GetFrameRef(key) return self.refs[key] end
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key,fn) self.hooks=self.hooks or {};self.hooks[key]=fn end
function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetPoint(...) self.point={...} end
function methods:Execute(snippet) assert(not combat,"insecure secure-environment initialization in combat");self.execute=snippet end
function methods:WrapScript(row,event,pre,post) wrappers[#wrappers+1]={row=row,event=event,owner=self,pre=pre,post=post} end
CreateFrame=frame
UIParent=frame("Frame","UIParent")
SecureHandlerWrapScript=function(row,event,owner,pre,post) wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre,post=post} end
SecureHandlerSetFrameRef=function(owner,key,value) owner:SetFrameRef(key,value) end
RegisterStateDriver=function(owner,state,condition)
    assert(not combat,"insecure state driver install in combat")
    drivers[#drivers+1]={owner=owner,state=state,condition=condition}
end
local emitBindingEvents,clearCount=false,0
ClearOverrideBindings=function()
    assert(not combat,"insecure override clear in combat")
    clearCount=clearCount+1
    if emitBindingEvents then
        for _,f in ipairs(frames) do
            if f.events and f.events.UPDATE_BINDINGS and f.scripts.OnEvent then f.scripts.OnEvent(f,"UPDATE_BINDINGS") end
        end
    end
end
SetOverrideBindingClick=function() assert(not combat,"insecure override install in combat") end
SaveBindings=function() error("combat compatibility must not persist bindings") end
SetBinding=SaveBindings;SetBindingClick=SaveBindings;CreateMacro=SaveBindings;EditMacro=SaveBindings
local units={nameplate1={unit="nameplate1",guid="Creature-one",name="测试怪物",targetName="测试怪物",player=false,side="enemy",dead=false,offline=false}}
UnitExists=function(unit) return units[unit]~=nil end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
UnitName=function(unit) return units[unit] and units[unit].name end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player end
GetBindingAction=function(key) return key=="Z" and "MULTIACTIONBAR1BUTTON3" or "" end
GetBindingKey=function(command) if command=="MULTIACTIONBAR1BUTTON3" then return "Z" end end
GetCVarBool=function() return false end
GetMouseFoci=function() return {} end
-- Production configuration: the out-of-combat name bridge continues into
-- combat for units confirmed unique before combat (2026-11-14 authorization).
UnitCanAttack=function(_,unit) return units[unit]~=nil and units[unit].side=="enemy" end
UnitCanAssist=function(_,unit) return units[unit]~=nil and units[unit].side=="friendly" end
UnitIsDeadOrGhost=function(unit) if unit=="player" then return false end return units[unit] and units[unit].dead or false end
UnitIsConnected=function() return true end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
eq(NS.NativeMacroOnly,true,"production keeps native macros")
eq(NS.LegacyNameBridge,true,"production keeps the name bridge")
eq(NS.CombatNameBridge,true,"production enables the combat continuation")
NS.Initialize(nil)
NS.DB.shown=true
eq(NS.DB.legacyNameBridgeEnabled,true,"bridge is on by default")
NS.ReadUnit=function(unit,side)
    local data=units[unit]
    if data and data.side==side then local copy={};for k,v in pairs(data) do copy[k]=v end;return copy end
end
local unique,actions=true,{}
C_Spell={DoesSpellExist=function(spell) return spell=="测试攻击" end,IsSpellHarmful=function(spell) return spell=="测试攻击" end}
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
local Nearby=NS.NearbyCast
eq(Nearby.legacyName,true,"NearbyCast runs the legacy name bridge")
eq(Nearby.combatName,true,"NearbyCast exposes the combat continuation")
Nearby.KnownUniqueNPC=function() return unique end
Nearby.DiscoverActions=function() return actions end
Nearby.Enter=function() return true end
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
local Cast=NS.CombatCast
eq(Cast.legacy,true,"CombatCast is active under the production policy")
eq(Cast.native,nil,"CombatCast is not the disabled stub")

local row=frame("Button","NameBridgeEnemy",UIParent,"SecureActionButtonTemplate")
row.side,row.unit,row.expectedGUID="enemy","nameplate1","Creature-one"
local entry={slot=63,spellID=679,spell="测试攻击",side="enemy",actionKind="spell",
    command="MULTIACTIONBAR1BUTTON3",keys={"Z"},useOnKeyDown=false}
actions={entry}

-- Snapshot: an NPC needs independent uniqueness, even when it is the current target.
units.target={guid="Creature-one"}
unique=false
local data,ok=Nearby.SnapshotRow(row)
yes(data,"snapshot reads the row out of combat")
eq(ok,false,"current-target exemption does not apply to a combat snapshot")
unique=true
data,ok=Nearby.SnapshotRow(row)
eq(ok,true,"independently unique NPC is accepted")
combat=true
eq(Nearby.SnapshotRow(row),nil,"no snapshot is taken in combat")
combat=false
NS.DB.legacyNameBridgeEnabled=false
eq(Nearby.SnapshotRow(row),nil,"bridge switched off: no snapshot")
NS.DB.legacyNameBridgeEnabled=true

-- Macros: the name route, never the unverified GUID route.
local macros=Cast.BuildMacros(units.nameplate1,entry)
yes(macros,"name macros are built")
eq(macros.guidMacro,nil,"no GUID macro in the name continuation")
eq(macros.preserveTarget,nil,"name continuation does not claim to preserve the target")
yes(macros.withTarget:find("/targetexact 测试怪物\n",1,true),"frozen name is selected")
yes(macros.withTarget:find("/cast [@target,harm,nodead] 测试攻击",1,true),"hostile-only cast")
yes(macros.withTarget:match("/targetlasttarget$"),"previous target is restored")
yes(macros.withoutTarget:match("/cleartarget$"),"absent previous target is restored as none")
eq(macros.withTarget:find("nocombat",1,true),nil,"combat macro is not limited to out of combat")
eq(macros.withTarget:find("Creature-one",1,true),nil,"GUID never appears in the macro")
eq(Cast.BuildMacros(units.nameplate1,{actionKind="macro",side="enemy",macroBody="#showtooltip\n/cast 测试攻击"}),nil,
    "user macros keep their original behavior")

-- Arming.
yes(Nearby.Install(row),"installing the bridge also installs the combat owner")
eq(Cast.owner.refs.nearbyOwner,Nearby.owner,"one leave wrapper clears both owners")
eq(Cast.ArmRow(row),true,"a unique NPC is armed out of combat")
eq(Cast.Status(row).prepared,true,"armed status")
eq(row:GetAttribute("combat-key1"),"Z","original key stored on the row")
local proxy=Cast.states[row].proxies[1]
eq(proxy:GetAttribute("snapshot-preserve-target"),false,"proxy is in name mode")
eq(proxy:GetAttribute("snapshot-guid-macro"),nil,"proxy has no GUID macro")
eq(proxy:GetAttribute("snapshot-with-target"),macros.withTarget,"proxy holds the target-restoring macro")
unique=false
eq(Cast.ArmRow(row),false,"same-name NPC is not armed")
eq(Cast.Status(row).reason,"not_unique","same-name reason")
eq(row:GetAttribute("combat-prepared"),false,"disarm clears the secure flag")
unique=true
NS.DB.legacyNameBridgeEnabled=false
eq(Cast.ArmRow(row),false,"switching the bridge off disarms")
eq(Cast.Status(row).reason,"disabled","disabled reason")
NS.DB.legacyNameBridgeEnabled=true
NS.DB.mouseoverRequested=false
eq(Cast.ArmRow(row),true,"the old GUID toggle does not control the name continuation")

-- An enemy's target bar follows a live relationship and is never armed for combat.
local bar=frame("Button","NameBridgeEnemyTarget",UIParent,"SecureActionButtonTemplate")
bar.side,bar.unit,bar.expectedGUID,bar.bridgeTarget="friendly","nameplate1target","Player-two",true
eq(Cast.Install(bar),false,"enemy target bar is not taken over by the combat module")
eq(Cast.ArmRow(bar),false,"target bar is not armed")

-- Friendly tiles: the original out-of-combat bridge must stay exactly as it was.
-- The combat module never installs on them, so NearbyCast keeps its own wrappers.
for _,spec in ipairs({{"NameBridgeParty","party1","Player-three"},{"NameBridgeNearbyFriend","nameplate2","Player-four"}}) do
    local friend=frame("Button",spec[1],UIParent,"SecureActionButtonTemplate")
    friend.side,friend.unit,friend.expectedGUID="friendly",spec[2],spec[3]
    eq(Cast.Install(friend),false,spec[2].." friendly tile is not installed in the combat module")
    eq(Cast.ArmRow(friend),false,spec[2].." friendly tile is never armed for combat")
    local before=#wrappers
    yes(Nearby.Install(friend),spec[2].." friendly tile installs in the original bridge")
    local own={}
    for i=before+1,#wrappers do
        local w=wrappers[i]
        if w.row==friend then own[w.event]=w end
    end
    yes(own.OnLeave and own.OnLeave.owner==Nearby.owner and own.OnLeave.pre=="control:ClearBindings()",
        spec[2].." original leave wrapper, owned by the original bridge")
    yes(own.OnHide and own.OnHide.owner==Nearby.owner and own.OnHide.pre=="control:ClearBindings()",
        spec[2].." original hide wrapper, owned by the original bridge")
    eq(own.OnEnter,nil,spec[2].." no combat enter wrapper on a friendly tile")
    eq(friend:GetAttribute("combat-row-index"),nil,spec[2].." no combat attributes on a friendly tile")
end

-- Reconcile in the continuation never clears or re-enters the original bridge.
local nearbyReconciles=0
Nearby.Reconcile=function() nearbyReconciles=nearbyReconciles+1;return true end
GetMouseFoci=function() return {row} end
eq(Cast.Reconcile(),true,"combat module records its own hovered enemy tile")
eq(Cast.owner:GetAttribute("combat-hover-index"),Cast.installed[row],"own hover index set")
Cast.RefreshAll()
eq(nearbyReconciles,0,"the original bridge is not re-entered by the combat module")

-- In combat nothing protected is rewritten from ordinary Lua.
combat=true
eq(Cast.ArmRow(row),false,"no arming in combat")
eq(Cast.RefreshAll(),false,"no rebuild in combat")
eq(Cast.Status(row).prepared,true,"the pre-combat preparation stays in place")
combat=false

-- Restricted snippets are unchanged and still syntactically valid.
for name,snippet in pairs(Cast.Snippets) do yes(loadstring(snippet),"restricted "..name.." snippet compiles") end
yes(Cast.Snippets.preClick:find("snapshot-with-target",1,true),"PreClick selects the prebuilt macro")
print("Targets combat name bridge: "..checks.." simulated checks (secure engine, real casting and target restore remain in-game checks)")
