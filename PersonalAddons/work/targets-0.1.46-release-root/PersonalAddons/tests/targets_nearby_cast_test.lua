-- Lua configuration/preflight simulation. No secure macro or C++ spell action
-- is executed, and no actual recipient/target restoration is established here.
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
local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.NativeMacroOnly=false -- Explicit historical bridge coverage, never the production default.
eq(NS.PreserveCastTarget,true,"production default requires target-preserving cast configuration")
NS.PreserveCastTarget=false -- Historical name-bridge fixtures below are inert in production.
NS.Initialize(nil)
NS.ReadUnit=function(unit,side)
    local value=units[unit]
    if value and (value.side or "friendly")==side then return value end
end
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
local Cast=NS.NearbyCast
local withTarget="/stopmacro [combat]\n/cleartarget [nocombat]\n/targetexact [nocombat] Windfury Emberbeard\n/cast [nocombat,@target,help,nodead] 圣光术\n/targetlasttarget"
local withoutTarget="/stopmacro [combat]\n/cleartarget [nocombat]\n/targetexact [nocombat] Windfury Emberbeard\n/cast [nocombat,@target,help,nodead] 圣光术\n/cleartarget"
eq(Cast.BuildMacro("Windfury Emberbeard","圣光术",true),withTarget,"macro uses actual newlines and restores previous target")
eq(Cast.BuildMacro("Windfury Emberbeard","圣光术",false),withoutTarget,"original absence of target is restored by clearing")
eq(Cast.BuildFallback("圣光术"),"/cast [nocombat,@target,help,nodead][nocombat,@player] 圣光术","invalid hover fallback uses current friendly target then self")
for _,bad in ipairs({""," Name","Name ","Name\n/run x","Name\r/cast x","Name\0x","Name|Hitem","Name;other","Name[@player]"}) do
    eq(Cast.BuildMacro(bad,"圣光术",true),nil,"invalid name cannot inject or alter macro commands")
    eq(Cast.BuildMacro("Windfury Emberbeard",bad,true),nil,"invalid spell cannot inject or alter macro commands")
end
eq(Cast.BuildMacro("Windfury Emberbeard","圣光术",nil),nil,"target presence must be explicit boolean")
eq(Cast.BuildMacro(string.rep("N",1024),"圣光术",true),nil,"oversized secure macro is rejected")
eq(Cast.BuildFallback("圣光术\n/run x"),nil,"fallback rejects extra macro lines")

local row=frame("Button","TargetsNearbyTestRow",UIParent)
row.side,row.unit,row.expectedGUID="friendly","nameplate1","Player-nearby"
NS.HoveredTile=row
yes(Cast.Install(row),"row installs secure cleanup hooks")
local wrapperCount=#wrappers
Cast.Install(row)
eq(#wrappers,wrapperCount,"row install is idempotent")
eq(#drivers,1,"single secure combat state driver installed")
yes(drivers[1].condition:find("[combat] combat",1,true),"secure state responds to entering combat")
yes(Cast.owner:GetAttribute("_onstate-combat"):find("ClearBindings",1,true),"combat cleanup belongs to secure state handler")
local leaveGuard,hideGuard=false,false
for _,w in ipairs(wrappers) do
    if w.row==row and w.owner==Cast.owner and w.pre:find("ClearBindings",1,true) then
        leaveGuard=leaveGuard or w.event=="OnLeave";hideGuard=hideGuard or w.event=="OnHide"
    end
end
yes(leaveGuard and hideGuard,"secure leave and hide handlers clear the same override owner")
local discovered=Cast.DiscoverActions()
eq(#discovered,1,"only ordinary helpful spell action with original active keys is discovered")
eq(discovered[1].slot,13,"current paginated source.action determines spell slot")
eq(discovered[1].spellID,639,"paged helpful spell ID retained")
eq(#discovered[1].keys,2,"both native keyboard keys retained")
local calculatedButton
ActionButton1.CalculateAction=function(_,button) calculatedButton=button;return 61 end
discovered=Cast.DiscoverActions()
eq(discovered[1].slot,61,"CalculateAction takes precedence over cached action property")
eq(calculatedButton,"LeftButton","native page calculation receives correct hardware button")
for _,invalid in ipairs({{value=nil},{value=secret},{value=0},{value=241},{value=1.5},{throws=true}}) do
    ActionButton1.CalculateAction=function() if invalid.throws then error("page unavailable") end;return invalid.value end
    eq(#Cast.DiscoverActions(),0,"invalid native page calculation never uses stale cached slot")
end
ActionButton1.CalculateAction=nil
actions[4].neutral=true -- Auto-attack/neutral actions only count with allowNeutral=true.
C_ActionBar={IsHelpfulAction=function(slot,useNeutral)
    eq(useNeutral,false,"nearby bridge requests strict helpful actions")
    local a=actions[slot]
    return a and (a.helpful or useNeutral==true and a.neutral==true)
end}
discovered=Cast.DiscoverActions()
yes(#discovered>0,"current C_ActionBar helpful query is supported")
eq(#discovered,1,"neutral action accepted only with allowNeutral=true is never intercepted")
C_ActionBar=nil
C_Spell.GetSpellSubtext=function(id) return id==639 and "等级 2" or "" end
eq(Cast.DiscoverActions()[1].spell,"圣光术(等级 2)","rank text retained only with exact matching resolved spell ID")
resolvedSpellOverride=1459
eq(#Cast.DiscoverActions(),0,"rank resolving to different spell ID is not intercepted")
resolvedSpellOverride=false;C_Spell.GetSpellSubtext=function() return "" end
pressHold=true
eq(#Cast.DiscoverActions(),0,"press-hold release spells retain their original input path")
pressHold=false
local entered,count=Cast.Enter(row)
eq(entered,true,"eligible nearby friendly player enables temporary bridge")
eq(count,2,"only native helpful keyboard bindings overridden")
eq(baseBindings["1"],"ACTIONBUTTON1","original permanent binding unchanged")
eq(overrides["2"],nil,"user macro action not intercepted")
eq(overrides["3"],nil,"item action not intercepted")
eq(overrides["4"],nil,"harmful spell not intercepted")
eq(overrides["BUTTON1"],nil,"mouse click binding not intercepted")
eq(overrides["SHIFT-MOUSEWHEELUP"],nil,"wheel binding not intercepted")
eq(overrides["SHIFT-1"],nil,"other addon's active override is respected")
local proxy=_G[overrides["1"].button]
eq(proxy:GetAttribute("unit"),nil,"proxy has no read-only nameplate unit")
eq(proxy:GetAttribute("macrotext"),withTarget,"eligible key proxy uses exact-name spell and restoration macro")
eq(proxy.clicks[1],"AnyUp","native key-up action timing retained")
local function prepare() proxy:GetScript("PreClick")(proxy) end
units.target=nil;prepare()
eq(proxy:GetAttribute("macrotext"),withoutTarget,"target presence is checked at key press")
units.target={guid="Creature-original",name="原NPC",player=false}
units.nameplate1.guid="Player-reused";prepare()
eq(proxy:GetAttribute("macrotext"),Cast.BuildFallback("圣光术"),"GUID reuse never retargets a different hovered player")
units.nameplate1.guid="Player-nearby";units.nameplate1.dead=true;prepare()
eq(proxy:GetAttribute("macrotext"),Cast.BuildFallback("圣光术"),"dead hovered player falls back without changing current target")
units.nameplate1.dead=false;units.nameplate1.offline=true;prepare()
eq(proxy:GetAttribute("macrotext"),Cast.BuildFallback("圣光术"),"offline hovered player does not receive exact-name action")
units.nameplate1.offline=false
units.target=units.nameplate1;prepare()
eq(proxy:GetAttribute("macrotext"),Cast.BuildFallback("圣光术"),"already-selected hovered player avoids changing previous-target history again")
units.target={guid="Creature-original",name="原NPC",player=false}
actions[13]={kind="item",id=2,helpful=true};prepare()
eq(proxy:GetAttribute("type"),"action","action changed to item uses original slot without parsing it")
eq(proxy:GetAttribute("action"),13,"fallback forwards current source slot")
actions[13]={kind="macro",id=1,helpful=true};prepare()
eq(proxy:GetAttribute("type"),"action","action changed to user macro remains original native action")
actions[13]={kind="spell",id=639,helpful=true}
ActionButton1:SetAttribute("useOnKeyDown",true)
Cast.Enter(row)
eq(Cast.proxies[1].clicks[1],"AnyDown","original source key-down timing retained")
ActionButton1:SetAttribute("useOnKeyDown",nil)
emitBindingEvents=true
eq(pcall(Cast.Enter,row),true,"own override binding events do not recursively rebuild bridge")
yes(bindingEventCount>0 and bindingEventCount<20,"override UPDATE_BINDINGS is exercised and bounded")
emitBindingEvents=false
Cast.Refresh()
yes(overrides["1"],"refresh does not mistake its own override for another addon")
local other=frame("Button","TargetsOtherRow",UIParent)
Cast.Leave(other)
yes(overrides["1"],"leaving an unrelated row does not clear active row in Lua")
mouseOver=false;Cast.Refresh()
eq(overrides["1"],nil,"pointer leaving active row clears temporary keys")
mouseOver=true
NS.HoveredTile=row;Cast.Enter(row);Cast.Leave(row)
eq(overrides["1"],nil,"explicit leave restores original key resolution")
NS.HoveredTile=row;Cast.Enter(row)
combat=true
eq(pcall(Cast.Refresh),true,"combat refresh never performs insecure protected binding changes")
eq(Cast.Enter(row),false,"combat cannot install new bridge bindings")
eq(pcall(Cast.Leave,row),true,"combat leave relies on secure cleanup without insecure clear")
-- Restricted engine execution is intentionally not simulated. Check the secure
-- state/leave/hide configuration above, then model its resulting owner cleanup.
clearOwner(Cast.owner)
eq(overrides["1"],nil,"modeled secure owner cleanup leaves no temporary key")
combat=false
row.side="enemy";NS.HoveredTile=row
eq(Cast.Enter(row),false,"enemy row never installs helpful spell override")
row.side="friendly";row.unit="party1"
eq(Cast.Enter(row),false,"stable party row uses existing native path")
row.unit="nameplate1";NS.DB.mouseoverRequested=false
eq(Cast.Enter(row),false,"disabled hover setting prevents temporary bridge")
NS.DB.mouseoverRequested=true;NS.HoveredTile=nil
eq(Cast.Enter(row),false,"row not actually hovered cannot intercept keys")

-- Enemy support must never turn a harmful spell fallback into a self cast.
local enemyName="Opponent Emberbeard-OtherRealm"
local enemyFallback="/cast [nocombat,@target,harm,nodead] 火球术"
eq(Cast.BuildFallback("火球术","enemy"),enemyFallback,"harmful fallback only uses current hostile target")
local enemyMacro=Cast.BuildMacro(enemyName,"火球术",true,"enemy")
yes(enemyMacro:find("/targetexact [nocombat] "..enemyName,1,true),"hostile player retains full name and realm")
yes(enemyMacro:find("[@target,harm",1,true)==nil and enemyMacro:find("[nocombat,@target,harm,nodead]",1,true),
    "enemy named action has an explicit hostile target condition")
eq(enemyMacro:find("@player",1,true),nil,"harmful named action never adds self fallback")
eq(enemyMacro:match("([^\n]+)"),"/stopmacro [combat]","already-combat execution stops before any named-target side effect")
eq(enemyMacro:match("([^\n]+)$"),"/targetlasttarget","restoring original target is not suppressed if this cast starts combat")
eq(Cast.BuildMacro(enemyName,"火球术",false,"enemy"):match("([^\n]+)$"),"/cleartarget",
    "original absence of target is restored even if this cast starts combat")
eq(Cast.BuildMacro(enemyName,"火球术",true,"invalid"),nil,"unrecognized relation cannot enter generated macro")
eq(Cast.BuildFallback("火球术","invalid"),nil,"unrecognized fallback relation rejected")
eq(#Cast.DiscoverActions("invalid"),0,"unrecognized discovery relation does not intercept keys")

local originalW="#showtooltip\n/cast [mod:shift] 正义圣印; 审判"
local guardedW="#showtooltip\n/cast [nocombat,mod:shift] 正义圣印; [nocombat] 审判"
spellNames[21084],spellNames[20271]="正义圣印","审判"
C_Spell.IsSpellHarmful=function(spell) return spell=="审判" or spell=="火球术" end
eq(Cast.MacroHasHarmfulCast(originalW),true,"mixed self-buff/damage macro is classified from actual cast branches")
eq(Cast.MacroHasHarmfulCast("/cast 正义圣印"),false,"pure self-buff macro is never a hostile action")
eq(Cast.MacroHasHarmfulCast("#showtooltip 审判\n/cast 正义圣印"),false,"harmful tooltip spell cannot disguise harmless body")
local harmfulSpellCheck=C_Spell.IsSpellHarmful
C_Spell.IsSpellHarmful=function() return secret end
eq(Cast.MacroHasHarmfulCast(originalW),false,"secret harmful classification does not enable macro")
C_Spell.IsSpellHarmful=function(spell) if spell=="正义圣印" then error("classification unavailable") end;return true end
eq(Cast.MacroHasHarmfulCast(originalW),false,"unreadable modifier branch cannot borrow another branch's harmful result")
C_Spell.IsSpellHarmful=harmfulSpellCheck
eq(Cast.MacroHasHarmfulCast("/cast [mod:shift] 13; 审判"),false,
    "a cast branch that would fall through to an item is not reconstructed")
local spellExists=C_Spell.DoesSpellExist
C_Spell.DoesSpellExist=function(spell) return spell=="!攻击" or spellExists(spell) end
eq(Cast.MacroHasHarmfulCast("/cast !攻击; 审判"),false,"bang-prefixed auto/repeat branch is rejected even when spell lookup accepts it")
C_Spell.DoesSpellExist=spellExists
for _,method in ipairs({"IsAutoAttackSpell","IsRangedAutoAttackSpell","IsAutoRepeatSpell","IsPressHoldReleaseSpell"}) do
    local previous=C_Spell[method]
    C_Spell[method]=function(spell) return spell=="正义圣印" end
    eq(Cast.MacroHasHarmfulCast(originalW),false,"unsupported auto/hold branch is not copied: "..method)
    C_Spell[method]=previous
end
eq(Cast.GuardMacro(originalW),guardedW,"W macro preserves modifier seal and default judgement branches")
eq(Cast.FrozenUserMacro(originalW),originalW,"combat snapshot preserves the authored modifier and default spell branches")
eq(Cast.FrozenUserMacro("/cast [nocombat,mod:shift] 正义圣印; 审判"),
    "/cast [nocombat,mod:shift] 正义圣印; 审判","combat preparation never strips an authored nocombat condition")
eq(Cast.FrozenUserMacro("/run print(1)"),nil,"combat snapshot never expands supported macro commands")
eq(Cast.GuardMacro("/cast [mod:shift][@focus,harm] 火球术; [] 审判"),
    "/cast [nocombat,mod:shift][nocombat,@focus,harm] 火球术; [nocombat] 审判",
    "each OR group and semicolon branch receives its own combat guard")
eq(Cast.GuardMacro(originalW,"friendly"),nil,"friendly macro scope is not silently expanded")
eq(Cast.GuardMacro(originalW,"invalid"),nil,"macro guard rejects unknown relation")
eq(Cast.BuildUserFallback(originalW),guardedW,"user macro fallback preserves authored branches without retarget or injected self")
for _,body in ipairs({"/run print(1)","/say hello\n/cast 火球术","/use 13", "/castsequence 火球术,审判",
    "/cast 火球术\n/cast 审判","/targetenemy\n/cast 火球术","#showtooltip", "/cast [mod:shift] 正义圣印;",
    "/cast [[harm]] 火球术","/cast 火球术|Hitem:1"}) do
    eq(Cast.GuardMacro(body),nil,"unsupported macro commands or malformed branches retain native behavior")
end

Cast.Leave()
units.nameplate2={guid="Player-opponent",name="Opponent",targetName=enemyName,side="enemy",player=true,dead=false,offline=false}
units.nameplate3={guid="Creature-one",name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
units.nameplate4={guid="Creature-two",name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
local enemyRow=frame("Button","TargetsEnemyPlayerTestRow",UIParent)
enemyRow.side,enemyRow.unit,enemyRow.expectedGUID="enemy","nameplate2","Player-opponent"
Cast.Install(enemyRow)
actions[4].harmful=true
actions[61]={kind="macro",id=20271,subType="spell",helpful=false,harmful=false}
bindingKeys.MULTIACTIONBAR1BUTTON1={"W"};baseBindings.W="MULTIACTIONBAR1BUTTON1"
activeBindings["SHIFT-1"]=nil
local strictHarmful=true
IsHarmfulAction=function(slot,allowNeutral)
    if allowNeutral~=false then strictHarmful=false end
    local a=actions[slot];return a and a.harmful==true
end
local macros={[121]={name="正义审判",body=originalW}}
local unreadableMacro,secretMacroName,overrideMacroIndex,invalidMacroRead
local macroReadIndices={}
GetActionText=function(slot) return slot==61 and "正义审判" or nil end
GetMacroIndexByName=function(name)
    if overrideMacroIndex then return overrideMacroIndex end
    for i=1,150 do if macros[i] and macros[i].name==name then return i end end
    return 0
end
GetMacroInfo=function(index)
    macroReadIndices[index]=true
    if index<1 or index>150 then invalidMacroRead=true;error("not a macro index") end
    if index==unreadableMacro then error("macro lookup unavailable") end
    if index==secretMacroName then return secret end
    local m=macros[index];if m then return m.name,"icon",m.body end
end
local function findMacro(entries)
    for _,entry in ipairs(entries) do if entry.actionKind=="macro" then return entry end end
end
local enemyActions=Cast.DiscoverActions("enemy")
eq(#enemyActions,2,"enemy discovery finds harmful spell and supported W macro")
yes(strictHarmful,"enemy action discovery requests strict harmful classification")
local wEntry=findMacro(enemyActions)
eq(wEntry.macroIndex,121,"macro name resolves character slot rather than display spell ID")
eq(wEntry.spellID,20271,"resolved display spell ID remains separate from macro index")
yes(macroReadIndices[121] and not macroReadIndices[20271] and not invalidMacroRead,
    "macro scanning stays inside account and character index range")
eq(wEntry.guardedBody,guardedW,"discovered W action preserves original modifier branches")
local harmfulGlobal=IsHarmfulAction
C_ActionBar={IsHarmfulAction=harmfulGlobal,GetActionText=GetActionText};IsHarmfulAction=nil
eq(#Cast.DiscoverActions("enemy"),2,"modern harmful and action-text namespace works without legacy global")
C_ActionBar=nil;IsHarmfulAction=harmfulGlobal
macros[1]={name="正义审判",body="/cast 火球术"}
eq(findMacro(Cast.DiscoverActions("enemy")),nil,"duplicate account and character macro names are not guessed")
macros[1]=nil;unreadableMacro=70
eq(findMacro(Cast.DiscoverActions("enemy")),nil,"unknown macro slot prevents a false uniqueness claim")
unreadableMacro=nil;secretMacroName=145
eq(findMacro(Cast.DiscoverActions("enemy")),nil,"secret macro name prevents a false uniqueness claim")
secretMacroName=nil;overrideMacroIndex=20271
eq(findMacro(Cast.DiscoverActions("enemy")),nil,"out-of-range macro lookup index is rejected")
eq(invalidMacroRead,nil,"out-of-range index is rejected before GetMacroInfo")
overrideMacroIndex=nil
NS.HoveredTile=enemyRow
entered,count=Cast.Enter(enemyRow)
eq(entered,true,"hostile player enables out-of-combat casting bridge")
eq(count,2,"only harmful spell and supported macro keys are overridden for enemy")
eq(overrides["1"],nil,"helpful spell key is not hijacked over an enemy")
local fireProxy=_G[overrides["4"].button]
local wProxy=_G[overrides.W.button]
eq(fireProxy:GetAttribute("macrotext"),enemyMacro,"harmful spell proxy targets exact hostile player")
yes(wProxy:GetAttribute("macrotext"):find(guardedW,1,true),"W proxy contains guarded authored branches")
eq(wProxy:GetAttribute("macrotext"):find("@player",1,true),nil,"W proxy adds no automatic self target")
eq(macros[121].body,originalW,"original user macro body is never edited")
eq(baseBindings.W,"MULTIACTIONBAR1BUTTON1","original W binding is never saved or replaced")
units.nameplate2.guid="Player-reused"
fireProxy:GetScript("PreClick")(fireProxy);wProxy:GetScript("PreClick")(wProxy)
eq(fireProxy:GetAttribute("macrotext"),enemyFallback,"reused enemy GUID falls back only to current hostile target")
eq(wProxy:GetAttribute("macrotext"),guardedW,"reused enemy GUID preserves macro fallback without retargeting")
units.nameplate2.guid="Player-opponent";units.nameplate2.dead=true
fireProxy:GetScript("PreClick")(fireProxy)
eq(fireProxy:GetAttribute("macrotext"),enemyFallback,"dead hostile player never receives named action")
units.nameplate2.dead=false;units.target=units.nameplate2
fireProxy:GetScript("PreClick")(fireProxy)
eq(fireProxy:GetAttribute("macrotext"),enemyFallback,"already-selected hostile player avoids unnecessary target history change")
units.target={guid="Creature-original",name="原NPC",player=false}
macros[121].body="#showtooltip\n/cast [mod:shift] 正义圣印; 火球术"
wProxy:GetScript("PreClick")(wProxy)
yes(wProxy:GetAttribute("macrotext"):find("[nocombat] 火球术",1,true),"macro edit is re-read at hardware preflight")
macros[121].body="/run print(1)"
wProxy:GetScript("PreClick")(wProxy)
eq(wProxy:GetAttribute("type"),"action","unsupported edited macro is returned to original native slot")
eq(wProxy:GetAttribute("action"),61,"unsupported macro fallback keeps original slot")
macros[121].body=originalW
Cast.Leave(enemyRow)
units.focus=units.nameplate2
enemyRow.unit,enemyRow.expectedGUID="focus","Player-opponent";NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),true,"hostile player exposed as focus also supports original skill key")
yes(_G[overrides.W.button]:GetAttribute("macrotext"):find("/targetexact [nocombat] "..enemyName,1,true),
    "hostile player alias still keeps canonical target identity")
Cast.Leave(enemyRow)
units.target=units.nameplate2;enemyRow.unit="target";NS.HoveredTile=enemyRow
Cast.Enter(enemyRow)
eq(_G[overrides.W.button]:GetAttribute("macrotext"),guardedW,"already selected hostile-player alias preserves user macro without retargeting")
Cast.Leave(enemyRow)
units.target={unit="target",guid="Creature-original",name="原NPC",targetName="原NPC",side="enemy",player=false,dead=false,offline=false}
units.nameplate3.unit,units.nameplate4.unit="nameplate3","nameplate4"
local knownPlates={"nameplate2","nameplate3","nameplate4"}
NS.NameplateTokens=function() return knownPlates end
NS.Nameplates={}
NS.Collect=function() error("NPC uniqueness must not inspect a clipped display list") end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"known same-name NPC with different GUID prevents name bridge")
eq(select(2,Cast.KnownUniqueNPC(units.nameplate3)),"duplicate_name","known duplicate has a distinct diagnostic reason")
for _,unit in ipairs({"nameplate3","nameplate4"}) do
    enemyRow.unit,enemyRow.expectedGUID=unit,units[unit].guid
    NS.HoveredTile=enemyRow
    eq(Cast.Enter(enemyRow),true,"ambiguous NPC still receives explicit current-target fallback")
    eq(_G[overrides.W.button]:GetAttribute("macrotext"),guardedW,"same-name NPC never triggers exact-name macro retargeting")
    Cast.Leave(enemyRow)
end
enemyRow.unit="target";enemyRow.expectedGUID=units.target.guid;NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),true,"stable current NPC target keeps direct current-target spell path")
eq(_G[overrides["4"].button]:GetAttribute("macrotext"),enemyFallback,"current NPC target needs no name retarget")
Cast.Leave(enemyRow)

-- Enumerate all known candidates, including units outside the display cap, and
-- deduplicate aliases by GUID rather than counting aliases as extra monsters.
knownPlates={"nameplate3"}
units.nameplate9=units.nameplate3;units.focus=units.nameplate3
NS.Nameplates.nameplate9=true
eq(Cast.KnownUniqueNPC(units.nameplate3),true,"same-GUID target and plate aliases do not count as duplicate NPCs")
eq(select(2,Cast.KnownUniqueNPC(units.nameplate3)),"known_unique","same-GUID alias success is not reported as an unknown outcome")
units.nameplate30={unit="nameplate30",guid="Creature-outside-cap",name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
NS.Nameplates.nameplate30=true
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"same-name registered NPC outside twenty visible slots still blocks retargeting")
units.nameplate30.guid=secret
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"secret candidate identity cannot establish uniqueness")
eq(select(2,Cast.KnownUniqueNPC(units.nameplate3)),"identity_unreadable","secret identity is distinguished from confirmed duplicate names")
units.nameplate30.guid="Creature-outside-cap";units.nameplate30.name=secret
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"secret candidate name cannot establish uniqueness")
units.nameplate30.name="同名怪物";NS.Nameplates.nameplate30=nil
local enumerate=NS.NameplateTokens
NS.NameplateTokens=function() error("enumeration unavailable") end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"enumeration failure never claims NPC name uniqueness")
eq(select(2,Cast.KnownUniqueNPC(units.nameplate3)),"enumeration_unavailable","failed enumeration is distinguished from confirmed duplicate names")
NS.NameplateTokens=enumerate
local priorNativePlates=C_NamePlate
units.nameplate41={unit="nameplate41",guid="Creature-native-beyond-fallback",name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
C_NamePlate={GetNamePlates=function() return {{namePlateUnitToken="nameplate41",IsForbidden=function() return false end}} end}
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"native plate enumeration includes same-name NPC beyond fixed scan range")
C_NamePlate.GetNamePlates=function() error("native enumeration failed") end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"display enumeration fallback cannot hide a native scan error")
eq(select(2,Cast.KnownUniqueNPC(units.nameplate3)),"enumeration_unavailable","native enumeration errors retain an indeterminate reason")
C_NamePlate.GetNamePlates=function() return secret end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"secret native enumeration cannot establish known uniqueness")
C_NamePlate.GetNamePlates=function() return {{namePlateUnitToken="nameplate3",IsForbidden=function() return true end}} end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"forbidden native frame is not silently skipped for uniqueness")
local tokenlessPlate={IsForbidden=function() return false end}
C_NamePlate.GetNamePlates=function() return {tokenlessPlate} end
C_NamePlate.GetNamePlateForUnit=function(unit) if unit=="nameplate3" or unit=="nameplate9" then return tokenlessPlate end end
eq(Cast.KnownUniqueNPC(units.nameplate3),true,"public tokenless native frame can be covered by known unit reverse mapping")
C_NamePlate.GetNamePlateForUnit=nil
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"tokenless native frame with missing reverse API is indeterminate")
C_NamePlate.GetNamePlateForUnit=function() return nil end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"unmapped native frame is not dropped from completeness check")
C_NamePlate.GetNamePlateForUnit=function() return {} end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"wrong reverse-mapped frame cannot cover native enumeration")
C_NamePlate.GetNamePlateForUnit=function() return secret end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"secret reverse mapping cannot establish complete enumeration")
C_NamePlate.GetNamePlateForUnit=function() error("reverse mapping unavailable") end
eq(Cast.KnownUniqueNPC(units.nameplate3),false,"reverse mapping failure cannot establish complete enumeration")
C_NamePlate=priorNativePlates

-- The requested Z slot is an ordinary harmful spell, not the W user macro.
spellNames[679]="测试攻击"
actions[63]={kind="spell",id=679,helpful=false,harmful=true}
MultiBarBottomLeftButton3=frame("CheckButton","MultiBarBottomLeftButton3",UIParent)
MultiBarBottomLeftButton3.action=63
bindingKeys.MULTIACTIONBAR1BUTTON3={"Z"};baseBindings.Z="MULTIACTIONBAR1BUTTON3"
enemyRow.unit,enemyRow.expectedGUID="nameplate3","Creature-one";NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),true,"unique known NPC enables original harmful Z key bridge")
local zProxy=_G[overrides.Z.button]
yes(zProxy:GetAttribute("macrotext"):find("/targetexact [nocombat] 同名怪物",1,true),"unique known NPC uses actual NPC name")
yes(zProxy:GetAttribute("macrotext"):find("[nocombat,@target,harm,nodead] 测试攻击",1,true),"Z proxy retains hostile-only spell recipient")
eq(zProxy:GetAttribute("macrotext"):find("@player",1,true),nil,"NPC harmful path never injects self target")
NS.Nameplates.nameplate30=true
zProxy:GetScript("PreClick")(zProxy)
eq(zProxy:GetAttribute("macrotext"),Cast.BuildFallback("测试攻击","enemy"),"newly discovered duplicate at key press removes NPC name action")
NS.Nameplates.nameplate30=nil;units.nameplate3.guid="Creature-reused"
zProxy:GetScript("PreClick")(zProxy)
eq(zProxy:GetAttribute("macrotext"),Cast.BuildFallback("测试攻击","enemy"),"NPC token reuse falls back without retargeting reused creature")
units.nameplate3.guid="Creature-one"
Cast.Leave(enemyRow)
units.target=units.nameplate3;NS.Nameplates.nameplate30=true
NS.NameplateTokens=function() error("uniqueness scan should be bypassed for actual current target") end
NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),true,"matching current NPC GUID works even when uniqueness is indeterminate")
eq(_G[overrides.Z.button]:GetAttribute("macrotext"),Cast.BuildFallback("测试攻击","enemy"),"matching current NPC uses target directly without exact-name selection")
Cast.Leave(enemyRow);NS.NameplateTokens=enumerate
NS.GUIDProbeSuspended=true;NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),false,"isolated GUID experiment cannot be overwritten by the ordinary name bridge")
NS.GUIDProbeSuspended=nil
-- Production policy uses only a literal captured GUID on ordinary NPC spell
-- keys. No target-changing, name-selection, user-macro or fallback route may
-- participate; these checks configure actions without executing the engine.
Cast.Leave()
NS.PreserveCastTarget=true
local guidA="Creature-0-7121-0-2-525-2B600454CB"
local guidB="Creature-0-7121-0-2-525-15A9C066A1"
local guidOriginal="Creature-0-7121-0-2-735-46C7573C81"
eq(Cast.BuildGUIDMacro(guidA,"测试攻击"),"/cast [@"..guidA.."] 测试攻击","GUID helper emits exactly one explicit unit cast line")
for _,bad in ipairs({""," Name","Name ","Creature x","Creature-A\n/cleartarget","Creature-A\r/target x",
    "Creature-A\0x","Creature-A|Hitem","Creature-A;foo","Creature-A] [@target","Creature-A,harm","Creature-A/@target",
    "target","mouseover","Windfury-A","Creature-one","Creature--AA","Creature-AA-"}) do
    eq(Cast.BuildGUIDMacro(bad,"测试攻击"),nil,"malformed public GUID cannot alter the single cast condition")
end
eq(Cast.BuildGUIDMacro(secret,"测试攻击"),nil,"restricted GUID cannot enter a literal macro")
eq(Cast.BuildGUIDMacro(nil,"测试攻击"),nil,"missing GUID cannot become an implicit target")
eq(Cast.BuildGUIDMacro("Vehicle-0-7121-0-2-525-AABB","测试攻击"),
    "/cast [@Vehicle-0-7121-0-2-525-AABB] 测试攻击","actual vehicle GUID structure remains a literal cast candidate")
eq(Cast.BuildGUIDMacro(guidA,"测试攻击\n/target x"),nil,"spell text cannot append target-changing commands")
eq(Cast.BuildGUIDMacro(guidA,string.rep("N",1024)),nil,"oversized GUID cast macro is rejected")
eq(Cast.BuildMacro(enemyName,"火球术",true,"enemy"),nil,"production policy disables legacy name targeting helper")
eq(Cast.BuildFallback("测试攻击","enemy"),nil,"production policy disables implicit current-target fallback")
eq(Cast.BuildUserMacro(enemyName,originalW,true),nil,"production policy disables copied user-macro targeting")
eq(Cast.BuildUserFallback(originalW),nil,"production policy does not copy user macro fallbacks")
eq(Cast.FrozenUserMacro(originalW),nil,"production policy cannot freeze user macros into a new action")
units.nameplate3={unit="nameplate3",guid=guidA,name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
units.nameplate4={unit="nameplate4",guid=guidB,name="同名怪物",targetName="同名怪物",side="enemy",player=false,dead=false,offline=false}
units.target={unit="target",guid=guidOriginal,name="原目标",targetName="原目标",side="enemy",player=false,dead=false,offline=false}
enemyRow.unit,enemyRow.expectedGUID="nameplate3",guidA
NS.HoveredTile=enemyRow
local uniqueness=Cast.KnownUniqueNPC
Cast.KnownUniqueNPC=function() error("pure GUID path must never check NPC name uniqueness") end
local macroReads=0
local savedMacroInfo=GetMacroInfo
GetMacroInfo=function() macroReads=macroReads+1;error("production must not read or copy W") end
local pureActions=Cast.DiscoverActions("enemy")
eq(#pureActions,2,"production discovers only harmful simple-spell keys including Z")
eq(findMacro(pureActions),nil,"production action discovery excludes supported and unsupported user macros")
eq(macroReads,0,"production discovery does not inspect user macro bodies")
eq(#Cast.DiscoverActions("friendly"),0,"production name bridge never captures helpful or buff keys")
local snap,canGUID=Cast.SnapshotRow(enemyRow)
eq(snap,units.nameplate3,"combat snapshot keeps the actual public NPC identity")
eq(canGUID,true,"duplicate NPC names do not disable literal GUID preparation")
eq(Cast.Enter(enemyRow),true,"ordinary NPC hover enables original simple-spell key candidates")
eq(overrides.W,nil,"W macro keeps its original binding during NPC hover")
eq(GetBindingAction("W",true),baseBindings.W,"unsupported macro key resolves to its original action")
eq(macros[121].body,originalW,"production never edits the user's original macro")
eq(overrides["1"],nil,"nearby NPC hover does not intercept helpful spell keys")
local pureZ=_G[overrides.Z.button]
eq(pureZ:GetAttribute("macrotext"),"/cast [@"..guidA.."] 测试攻击","normal Z proxy casts only at the captured NPC GUID")
eq(pureZ:GetAttribute("unit"),nil,"GUID macro proxy has no implicit unit")
eq(pureZ:GetAttribute("checkmouseovercast"),nil,"GUID macro proxy cannot inherit native mouseover redirection")
eq(pureZ:GetAttribute("action"),nil,"GUID proxy cannot fall through to a native action slot")
for _,prepared in ipairs(Cast.proxies) do
    local body=prepared:GetAttribute("macrotext")
    if body then
        eq(body,"/cast [@"..guidA.."] "..prepared.entry.spell,"every prepared production macro has exactly one GUID cast")
        eq(body:find("\n",1,true),nil,"prepared production macro never chains another command")
        eq(body:find("/target",1,true),nil,"prepared production macro never selects or restores a target")
        eq(body:find("/clear",1,true),nil,"prepared production macro never clears the current target")
        eq(body:find("/stop",1,true),nil,"prepared production macro never stops attack or macro execution")
        eq(body:find("@target",1,true),nil,"prepared production macro never injects current-target fallback")
    end
end
local records={}
NS.Diagnostics={Enabled=function() return true end,Record=function(kind,fields)
    for _,value in pairs(fields) do yes(type(value)~="table","GUID diagnostic fields remain flat") end
    records[#records+1]={kind=kind,fields=fields}
end}
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(records[#records].kind,"KEY_PREPARE","real preflight records a bounded key preparation event")
eq(records[#records].fields.branch,"guid_hover","pure GUID candidate is explicitly distinguished from name or fallback routes")
eq(records[#records].fields.castGUID,guidA,"key diagnostic records the intended captured GUID")
eq(records[#records].fields.beforeTargetGUID,guidOriginal,"key diagnostic records the untouched prior target")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(records[#records].kind,"GUID_HOVER_POSTCLICK","pure GUID postflight has its own diagnostic event")
eq(records[#records].fields.afterTargetGUID,guidOriginal,"postflight reads the current target without restoring it")
eq(records[#records].fields.recipientProven,false,"unchanged target never becomes a claim of cast or recipient success")
eq(units.target.guid,guidOriginal,"configuration and observers leave the player's current target intact")
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
units.target=units.nameplate4 -- Model an external target change; never repair it.
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(records[#records].fields.beforeTargetGUID,guidOriginal,"post diagnostic keeps the separately captured prior target")
eq(records[#records].fields.afterTargetGUID,guidB,"post diagnostic observes an externally changed target")
eq(units.target.guid,guidB,"post diagnostic never restores even a mismatched current target")
eq(records[#records].fields.recipientProven,false,"changed target also cannot prove a cast recipient")
units.target=nil
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(pureZ:GetAttribute("macrotext"),"/cast [@"..guidA.."] 测试攻击","absence of current target does not change the pure GUID command")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(units.target,nil,"no-target pre/post leaves the player without a target")
NS.Diagnostics=nil
for _,case in ipairs({{field="guid",value="Creature-reused"},{field="guid",value=secret},
    {field="dead",value=true},{field="dead",value=secret},{field="offline",value=true},
    {field="offline",value=secret},{field="player",value=true},{field="player",value=secret}}) do
    local original=units.nameplate3[case.field]
    units.nameplate3[case.field]=case.value
    pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
    eq(pureZ:GetAttribute("type"),nil,"invalid or stale NPC row leaves the intercepted proxy inert")
    eq(pureZ:GetAttribute("macrotext"),nil,"invalid row never retains a prior GUID action or current-target fallback")
    units.nameplate3[case.field]=original
end
NS.HoveredTile=nil;pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(pureZ:GetAttribute("type"),nil,"no-longer-hovered NPC cannot dispatch a stored GUID action")
NS.HoveredTile=enemyRow;enemyRow.expectedGUID=secret
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(pureZ:GetAttribute("type"),nil,"restricted row identity never dispatches a GUID action")
enemyRow.expectedGUID=guidA
units.nameplate3.targetName=secret
eq(Cast.Enter(enemyRow),true,"GUID identity does not require a readable or unique target name")
units.nameplate3.targetName="同名怪物"
Cast.Leave()
enemyRow.unit,enemyRow.expectedGUID="nameplate4",guidB;NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),true,"another same-name NPC is independently hoverable by GUID")
eq(_G[overrides.Z.button]:GetAttribute("macrotext"),"/cast [@"..guidB.."] 测试攻击","same-name second NPC receives its own distinct literal GUID")
Cast.Leave()
enemyRow.unit,enemyRow.expectedGUID="nameplate3",guidA;NS.HoveredTile=enemyRow
Cast.Enter(enemyRow);pureZ=_G[overrides.Z.button]
actions[63]={kind="macro",id=20271,subType="spell",helpful=false,harmful=true}
records={}
NS.Diagnostics={Enabled=function() return true end,Record=function(kind,fields) records[#records+1]={kind=kind,fields=fields} end}
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(pureZ:GetAttribute("type"),"action","a Z slot changed to a user macro preserves its original native action")
eq(pureZ:GetAttribute("action"),63,"changed macro is dispatched only through its original native slot")
eq(pureZ:GetAttribute("macrotext"),nil,"changed user macro body is never copied into the GUID proxy")
eq(pureZ:GetAttribute("unit"),nil,"changed native action does not inherit a GUID unit override")
eq(records[#records].fields.branch,"original_action","native changed-slot dispatch is explicitly excluded from GUID attempts")
eq(records[#records].fields.castGUID,nil,"native changed-slot dispatch never claims an intended GUID recipient")
local originalActionRecords=#records
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(#records,originalActionRecords,"native changed-slot dispatch does not emit a GUID PostClick record")
NS.HoveredTile=nil;pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(pureZ:GetAttribute("type"),nil,"changed-slot passthrough still requires the valid hovered row")
NS.HoveredTile=enemyRow
NS.Diagnostics=nil
Cast.Refresh()
eq(overrides.Z,nil,"refresh leaves a now-macro Z key on its original binding")
eq(GetBindingAction("Z",true),baseBindings.Z,"now-macro Z keeps the user's authored native action")
eq(macroReads,0,"changed macro action is not copied or interpreted")
actions[63]={kind="spell",id=679,helpful=false,harmful=true}
for _,method in ipairs({"IsAutoAttackSpell","IsRangedAutoAttackSpell","IsAutoRepeatSpell","IsPressHoldReleaseSpell"}) do
    local previous=C_Spell[method]
    C_Spell[method]=function(id) return id==679 end
    local hasZ=false
    for _,entry in ipairs(Cast.DiscoverActions("enemy")) do if entry.spellID==679 then hasZ=true end end
    eq(hasZ,false,"production excludes non-single-cast spell action: "..method)
    C_Spell[method]=previous
end
local rankAPI=C_Spell.GetSpellSubtext
C_Spell.GetSpellSubtext=function(id) return id==679 and secret or "" end
local hasZ=false
for _,entry in ipairs(Cast.DiscoverActions("enemy")) do if entry.spellID==679 then hasZ=true end end
eq(hasZ,false,"secret exact-rank metadata cannot become an unranked replacement spell")
C_Spell.GetSpellSubtext=rankAPI
Cast.Leave()
row.side,row.unit,row.expectedGUID="friendly","nameplate1","Player-nearby";NS.HoveredTile=row
eq(Cast.Enter(row),false,"production disables arbitrary friendly-nameplate target switching")
eq(overrides["1"],nil,"friendly nearby hover leaves helpful key on its original native path")
row.unit="party1"
eq(Cast.Enter(row),false,"stable friendly party row remains on the native unit path")
eq(Cast.SnapshotRow(row),nil,"friendly stable row does not prepare a hidden GUID bridge")
enemyRow.unit,enemyRow.expectedGUID="nameplate2","Player-opponent";NS.HoveredTile=enemyRow
eq(Cast.Enter(enemyRow),false,"enemy players cannot accidentally enter the NPC GUID candidate")
units.target=units.nameplate3;enemyRow.unit,enemyRow.expectedGUID="target",guidA
local stableData,stableEligible=Cast.SnapshotRow(enemyRow)
eq(stableData,units.nameplate3,"already-eligible NPC target alias preserves its public identity")
eq(stableEligible,true,"existing NPC alias avoids all name uniqueness work")
Cast.Leave()
Cast.KnownUniqueNPC=uniqueness;GetMacroInfo=savedMacroInfo
-- Logging is passive: real installed callbacks correlate dispatch, state
-- transitions are deduplicated, and diagnostic failures cannot change actions.
enemyRow.unit,enemyRow.expectedGUID="nameplate3",guidA;NS.HoveredTile=enemyRow
units.target={unit="target",guid=guidOriginal,name="原目标",targetName="原目标",side="enemy",player=false,dead=false,offline=false}
local trace,begins,ends={},{},{}
local attemptSequence=0
local function traceRecord(kind,fields) trace[#trace+1]={kind=kind,fields=fields} end
NS.Diagnostics={Enabled=function() return true end,Record=traceRecord,
    BeginCastAttempt=function(fields)
        attemptSequence=attemptSequence+1;begins[#begins+1]={id=attemptSequence,fields=fields};return attemptSequence
    end,
    EndCastAttempt=function(id,fields) ends[#ends+1]={id=id,fields=fields} end}
local function traceCount(kind)
    local count=0
    for _,record in ipairs(trace) do if record.kind==kind then count=count+1 end end
    return count
end
local function traceLast(kind)
    for i=#trace,1,-1 do if trace[i].kind==kind then return trace[i] end end
end
eq(Cast.Enter(enemyRow),true,"logging-enabled hover preserves normal GUID configuration")
eq(traceLast("GUID_HOVER_ENTER").fields.reason,"prepared","hover transition records the actual preparation result")
eq(traceCount("GUID_HOVER_BINDING"),2,"each accepted simple-spell key records a binding readback")
eq(traceLast("GUID_HOVER_BINDING").fields.bindingMatches,true,"binding log confirms the observed effective override")
local enterCount,bindingCount,leaveCount=traceCount("GUID_HOVER_ENTER"),traceCount("GUID_HOVER_BINDING"),traceCount("GUID_HOVER_LEAVE")
Cast.Refresh();Cast.Refresh()
eq(traceCount("GUID_HOVER_ENTER"),enterCount,"unchanged periodic refresh does not repeat hover-result records")
eq(traceCount("GUID_HOVER_BINDING"),bindingCount,"unchanged periodic refresh does not repeat binding records")
eq(traceCount("GUID_HOVER_LEAVE"),leaveCount,"internal refresh rebuilding is not reported as a physical leave")
eq(#begins,0,"background prepare and refresh never invent hardware attempts")
pureZ=_G[overrides.Z.button]
local generated=pureZ:GetAttribute("macrotext")
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(#begins,1,"actual proxy PreClick starts one ordinary attempt association")
eq(begins[1].fields.route,"nearby","attempt source is separate from experimental probe routes")
eq(begins[1].fields.expectedGUID,guidA,"attempt association retains the hovered NPC GUID")
eq(begins[1].fields.generatedCommand,generated,"attempt records only the controlled generated GUID command")
eq(begins[1].fields.beforeTargetGUID,guidOriginal,"attempt association records the untouched pre-target")
eq(begins[1].fields.configuredKey1,"Z","configured key is recorded without pretending it is raw keyboard input")
eq(trace[#trace].kind,"KEY_PREPARE","existing preflight event remains present before correlation")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(#ends,1,"actual proxy PostClick closes its matching dispatch association")
eq(ends[1].id,begins[1].id,"PreClick and PostClick use the same numeric association ID")
eq(traceLast("GUID_HOVER_POSTCLICK").fields.attemptID,begins[1].id,"legacy PostClick event also carries the association ID")
eq(ends[1].fields.afterTargetGUID,guidOriginal,"EndCastAttempt observes the unchanged target")
eq(ends[1].fields.recipientProven,false,"EndCastAttempt never claims actual spell success")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(#ends,1,"a duplicate PostClick cannot reuse a stale attempt association")
units.nameplate3.guid="Creature-0-7121-0-2-525-ABCD"
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(trace[#trace].fields.branch,"disabled","invalid row still has an explicit preflight diagnostic")
eq(#begins,1,"disabled preflight does not begin a GUID cast association")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(#ends,1,"disabled preflight cannot reuse the last valid GUID association")
units.nameplate3.guid=guidA
actions[63]={kind="macro",id=20271,subType="spell",helpful=false,harmful=true}
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
eq(trace[#trace].fields.branch,"original_action","changed user macro remains distinctly logged as original action")
eq(#begins,1,"original action forwarding is excluded from GUID attempt correlation")
eq(pureZ:GetAttribute("action"),63,"logging does not alter original changed-slot forwarding")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(#ends,1,"original action forwarding cannot close a GUID dispatch")
actions[63]={kind="spell",id=679,helpful=false,harmful=true}
Cast.Enter(enemyRow);pureZ=_G[overrides.Z.button]
local beginFunction=NS.Diagnostics.BeginCastAttempt
NS.Diagnostics.BeginCastAttempt=function() error("diagnostics begin unavailable") end
eq(pcall(pureZ:GetScript("PreClick"),pureZ,"LeftButton",true),true,"BeginCastAttempt error cannot abort hardware preflight")
eq(pureZ:GetAttribute("macrotext"),generated,"BeginCastAttempt error cannot modify generated action")
eq(pureZ:GetAttribute("type"),"macro","BeginCastAttempt error cannot disable the original dispatch")
local postCount=traceCount("GUID_HOVER_POSTCLICK")
pureZ:GetScript("PostClick")(pureZ,"LeftButton",true)
eq(traceCount("GUID_HOVER_POSTCLICK"),postCount+1,"existing post diagnostic survives unavailable attempt correlation")
NS.Diagnostics.BeginCastAttempt=beginFunction
local endFunction=NS.Diagnostics.EndCastAttempt
NS.Diagnostics.EndCastAttempt=function() error("diagnostics end unavailable") end
pureZ:GetScript("PreClick")(pureZ,"LeftButton",true)
postCount=traceCount("GUID_HOVER_POSTCLICK")
eq(pcall(pureZ:GetScript("PostClick"),pureZ,"LeftButton",true),true,"EndCastAttempt error cannot interrupt PostClick")
eq(traceCount("GUID_HOVER_POSTCLICK"),postCount+1,"legacy PostClick still records when EndCastAttempt fails")
eq(units.target.guid,guidOriginal,"logging exceptions never clear or restore current target")
NS.Diagnostics.EndCastAttempt=endFunction
NS.Diagnostics.Record=function() error("diagnostic sink unavailable") end
eq(Cast.Enter(enemyRow),true,"binding and enter logging failures do not prevent normal hover activation")
eq(Cast.changing,false,"logging failures do not strand the controller's reentrancy guard")
pureZ=_G[overrides.Z.button]
eq(pureZ:GetAttribute("macrotext"),generated,"transition logging failures leave generated command untouched")
eq(pcall(pureZ:GetScript("PreClick"),pureZ,"LeftButton",true),true,"record sink error cannot abort real key preflight")
NS.Diagnostics.Record=traceRecord
Cast.Leave(enemyRow)
eq(traceLast("GUID_HOVER_LEAVE").fields.rowUnit,"nameplate3","real leave records the unit whose override was removed")
leaveCount=traceCount("GUID_HOVER_LEAVE")
Cast.Leave(enemyRow)
eq(traceCount("GUID_HOVER_LEAVE"),leaveCount,"repeated leave without an active row does not flood records")
enterCount=traceCount("GUID_HOVER_ENTER")
Cast.Enter(enemyRow)
eq(traceCount("GUID_HOVER_ENTER"),enterCount+1,"real reentry is observable even for the same previous NPC")
Cast.Leave()
local uninstalled=frame("Button","TargetsUninstalledDiagnosticRow",UIParent)
uninstalled.side,uninstalled.unit,uninstalled.expectedGUID="enemy","nameplate3",guidA
NS.HoveredTile=uninstalled
eq(Cast.Enter(uninstalled),false,"diagnostic failed-enter logging cannot change an uninstalled row result")
eq(traceLast("GUID_HOVER_ENTER").fields.reason,"not_installed","uninstalled row has a concrete enter failure reason")
NS.HoveredTile=enemyRow
units.nameplate3.guid="Creature-0-7121-0-2-525-ABCD"
eq(Cast.Enter(enemyRow),false,"stale GUID still rejects hover activation")
eq(traceLast("GUID_HOVER_ENTER").fields.reason,"guid_mismatch","stale GUID enter result is no longer silently rejected")
units.nameplate3.guid=guidA
local savedFireAction=actions[4]
actions[4]={kind="spell",id=133,helpful=false,harmful=false}
actions[63]={kind="macro",id=20271,subType="spell",helpful=false,harmful=true}
eq(Cast.Enter(enemyRow),false,"no-supported-action diagnostic preserves the original zero-key result")
eq(traceLast("GUID_HOVER_ENTER").fields.reason,"no_supported_spell","unsupported action set has an explicit no-binding reason")
actions[4]=savedFireAction;actions[63]={kind="spell",id=679,helpful=false,harmful=true}
local originalOverride=SetOverrideBindingClick
SetOverrideBindingClick=function(owner,priority,key,button,mouseButton)
    originalOverride(owner,priority,key,button,mouseButton)
    if key=="Z" then activeBindings.Z="CLICK AnotherAddon:LeftButton" end
end
Cast.Enter(enemyRow)
eq(traceLast("GUID_HOVER_BINDING").fields.bindingMatches,false,"binding readback reveals a competing effective override")
SetOverrideBindingClick=originalOverride;activeBindings.Z=nil
Cast.Leave()
NS.Diagnostics=nil
print("Targets nearby-cast simulated checks: "..checks.."; no secure macro or spell was executed")
