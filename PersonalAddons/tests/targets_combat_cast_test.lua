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
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.NativeMacroOnly=false -- Explicit historical bridge coverage, never the production default.
NS.Initialize(nil)
eq(NS.PreserveCastTarget,true,"production defaults to preserving the current cast target")
-- Historical name-bridge coverage is explicitly isolated from production's
-- target-preserving default below.
NS.PreserveCastTarget=false
NS.ReadUnit=function(unit,side)
    local data=units[unit]
    if data and data.side==side then local copy={};for k,v in pairs(data) do copy[k]=v end;return copy end
end
local unique,uniqueCalls,entered,actions=true,0,{},{}
C_Spell={DoesSpellExist=function(spell) return spell=="测试攻击" or spell=="审判" or spell=="正义圣印" end,
    IsSpellHarmful=function(spell) return spell=="测试攻击" or spell=="审判" end}
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
local Nearby=NS.NearbyCast
Nearby.KnownUniqueNPC=function() uniqueCalls=uniqueCalls+1;return unique end
Nearby.DiscoverActions=function() return actions end
Nearby.Enter=function(row) entered[#entered+1]=row;return true end
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
local Cast=NS.CombatCast
for _,method in ipairs({"Install","ArmRow","RefreshAll","Reconcile","Status"}) do
    eq(type(Cast[method]),"function","combat compatibility exposes "..method)
end
local row=frame("Button","CombatTestEnemy",UIParent,"SecureActionButtonTemplate")
row.side,row.unit,row.expectedGUID="enemy","nameplate1","Creature-one"
local source=frame("CheckButton","CombatTestAction",UIParent)
source.action=63
local entry={source=source,slot=63,spellID=679,spell="测试攻击",side="enemy",actionKind="spell",
    command="MULTIACTIONBAR1BUTTON3",keys={"Z"},useOnKeyDown=true}
actions={entry}
local macros=Cast.BuildMacros(units.nameplate1,entry)
yes(macros.withTarget:find("/targetexact 测试怪物\n",1,true),"combat name action is built before lockdown")
yes(macros.withTarget:find("/cast [@target,harm,nodead] 测试攻击",1,true),"prepared harmful spell has hostile-only recipient")
yes(macros.withTarget:match("/targetlasttarget$"),"prepared original-target branch restores prior target")
yes(macros.withoutTarget:match("/cleartarget$"),"prepared absent-target branch restores no target")
eq(macros.withTarget:find("nocombat",1,true),nil,"combat action does not inherit the OOC bridge guard")
eq(macros.fallback:find("@player",1,true),nil,"harmful fallback never inserts self target")
local wBody="#showtooltip\n/cast [mod:shift] 正义圣印; 审判"
local wEntry={actionKind="macro",side="enemy",macroBody=wBody}
local wMacros=Cast.BuildMacros(units.nameplate1,wEntry)
yes(wMacros.withTarget:find(wBody,1,true),"prepared user macro preserves original Shift and default branches")
eq(wMacros.fallback,wBody,"combat fallback preserves original user macro without new self branch")
eq(Cast.BuildMacros(units.nameplate1,{actionKind="macro",side="enemy",macroBody="/run print(1)"}),nil,
    "unsupported user macro is never prepared")
yes(Nearby.Install(row),"NearbyCast installation also installs combat capability OOC")
local wrapperCount=#wrappers
yes(Cast.Install(row),"combat install is idempotent")
eq(#wrappers,wrapperCount,"idempotent install cannot double wrap native leave handlers")
local leaveWrappers,hideWrappers=0,0
for _,wrapped in ipairs(wrappers) do
    if wrapped.row==row and wrapped.event=="OnLeave" then leaveWrappers=leaveWrappers+1 end
    if wrapped.row==row and wrapped.event=="OnHide" then hideWrappers=hideWrappers+1 end
end
eq(leaveWrappers,1,"one unified secure leave wrapper handles both binding owners")
eq(hideWrappers,1,"one unified secure hide wrapper handles both binding owners")
eq(Cast.owner.refs.nearbyOwner,Nearby.owner,"unified cleanup references the independent OOC owner")
eq(Cast.Status().prepared,false,"no active secure hover has finite unprepared status")
unique=false;units.target=units.nameplate1
eq(Cast.ArmRow(row),false,"known same-name NPC is not armed even when currently selected")
eq(Cast.Status(row).reason,"not_unique","ambiguous NPC preparation states its actual limitation")
units.target=nil;unique=true
eq(Cast.ArmRow(row),true,"OOC known unique NPC prepares supported original key")
eq(Cast.Status(row).count,1,"prepared original key count recorded")
eq(Cast.Status(row).guid,"Creature-one","prepared snapshot retains public identity")
eq(row:GetAttribute("combat-key1"),"Z","secure row stores original configured key OOC")
local proxy=Cast.states[row].proxies[1]
eq(proxy:GetAttribute("snapshot-with-target"),macros.withTarget,"native proxy receives prebuilt target-restoring macro")
eq(proxy:GetAttribute("snapshot-without-target"),macros.withoutTarget,"native proxy receives prebuilt no-target macro")
eq(proxy:GetAttribute("type"),nil,"insecure preparation leaves combat action selection to restricted PreClick")
eq(proxy.clicks[1],"AnyDown","prepared proxy retains native key-down phase")
for name,snippet in pairs(Cast.Snippets) do yes(loadstring(snippet),"restricted "..name.." snippet has Lua syntax") end
yes(Cast.Snippets.state:find("IsUnderMouse",1,true),"combat state entry checks stored row cursor geometry")
yes(Cast.Snippets.state:find("SetBindingClick",1,true),"secure state can transfer a held hover into combat")
yes(Cast.Snippets.leave:find("nearby:ClearBindings()",1,true),"unified leave clears OOC bindings too")
yes(Cast.Snippets.preClick:find("SecureCmdOptionParse",1,true),"restricted preflight checks current unit and target existence")
yes(Cast.Snippets.preClick:find("snapshot-with-target",1,true) and Cast.Snippets.preClick:find("snapshot-without-target",1,true),
    "restricted preflight selects among both prebuilt target restoration branches")
for _,name in ipairs({"state","enter","preClick"}) do
    yes(Cast.Snippets[name]:find("guid-probe-suspended",1,true),"restricted "..name.." honors GUID experiment isolation")
end
local records={}
NS.Diagnostics={Enabled=function() return true end,Record=function(kind,fields) records[#records+1]={kind=kind,fields=fields} end}
Cast.owner:SetAttribute("combat-active",true)
combat=true
eq(Cast.ArmRow(row),false,"combat never rewrites protected preparation attributes")
eq(Cast.RefreshAll(),false,"combat never rebuilds secure actions through ordinary Lua")
eq(Cast.Reconcile(),false,"combat never clears or installs ordinary overrides")
eq(Cast.Status(row).prepared,true,"combat guards preserve the frozen prepared snapshot")
local originalMacro=proxy:GetAttribute("snapshot-with-target")
proxy:GetScript("PreClick")(proxy)
eq(#records,0,"automatic observation without a button is not a key event")
proxy:GetScript("PreClick")(proxy,"LeftButton",true)
eq(records[1].kind,"COMBAT_KEY_PREPARE","hardware PreClick observation has a distinct combat diagnostic kind")
eq(records[1].fields.button,"LeftButton","secure dispatch button is labelled as button")
eq(records[1].fields.configuredKey1,"Z","configured keyboard key is logged independently")
eq(records[1].fields.actualKey,nil,"configured key never claims to identify which key was physically pressed")
eq(records[1].fields.macroBody,nil,"combat key log never serializes user macro body")
eq(proxy:GetAttribute("snapshot-with-target"),originalMacro,"ordinary combat PreClick observer never mutates protected action")
NS.Diagnostics.Record=function() error("logger unavailable") end
eq(pcall(proxy:GetScript("PreClick"),proxy,"LeftButton",false),true,"diagnostic failure cannot abort combat preflight observer")
combat=false
NS.HoveredTile=nil;GetMouseFoci=function() return {row} end
eq(Cast.Reconcile(),true,"leaving combat with real row focus re-enters OOC bridge")
eq(entered[#entered],row,"OOC reconciliation uses actual focused row")
eq(NS.HoveredTile,row,"OOC reconciliation restores physical hover owner")
local before=#entered
GetMouseFoci=function() return {frame("Frame","OtherFocus",UIParent)} end
eq(Cast.Reconcile(),false,"focus on another frame cannot fabricate OOC hover")
eq(#entered,before,"unrelated focus never invokes OOC bridge")
GetMouseFoci=function() return {row} end
units.nameplate1.guid="Creature-reused"
eq(Cast.Reconcile(),false,"reused row unit GUID cannot inherit OOC bridge after combat")
eq(#entered,before,"GUID mismatch never re-enters OOC bridge")
units.nameplate1.guid="Creature-one";row.shown=false
eq(Cast.Reconcile(),false,"hidden focused row cannot restore OOC bridge")
row.shown=true;GetMouseFoci=function() error("native focus unavailable") end
eq(Cast.Reconcile(),false,"missing focus read is contained without guessing a hovered unit")
GetMouseFoci=function() return {row} end
emitBindingEvents=true
Cast.RefreshAll()
local clearAfterRefresh=clearCount
local combatEvents
for _,f in ipairs(frames) do
    if f.events and f.events.UPDATE_BINDINGS and not f.events.PLAYER_REGEN_DISABLED then combatEvents=f end
end
yes(combatEvents,"combat action refresh event frame is available")
for i=1,5 do combatEvents:GetScript("OnUpdate")(combatEvents,.11) end
eq(clearCount,clearAfterRefresh,"self-generated binding events never create a recurring rebuild loop")
emitBindingEvents=false
eq(Cast.owner:GetAttribute("combat-hover-index"),Cast.installed[row],"OOC focus tracking prepares the actual hovered row for combat state entry")
GetMouseFoci=function() return {} end
combatEvents:GetScript("OnUpdate")(combatEvents,.11)
eq(Cast.owner:GetAttribute("combat-hover-index"),nil,"OOC native focus leaving clears the prepared hover transfer index")
GetMouseFoci=function() return {row} end
combatEvents:GetScript("OnUpdate")(combatEvents,.11)
combat=true;GetMouseFoci=function() return {} end
eq(pcall(combatEvents:GetScript("OnUpdate"),combatEvents,.11),true,"combat polling performs no insecure protected attribute writes")
eq(Cast.owner:GetAttribute("combat-hover-index"),Cast.installed[row],"ordinary combat polling leaves secure focus ownership untouched")
combat=false
NS.DB.mouseoverRequested=false
eq(Cast.ArmRow(row),false,"disabled hover casting disarms prebuilt combat row")
eq(row:GetAttribute("combat-prepared"),false,"disarm clears secure row preparation flag")
eq(row:GetAttribute("combat-key-count"),0,"disarm leaves no secure combat key dispatch count")

-- Default candidate: only a literal GUID /cast is prebuilt. These checks model
-- configuration and branch selection, not the native macro or spell engine.
NS.PreserveCastTarget=true
NS.DB.mouseoverRequested=true
unique=false;uniqueCalls=0
local expectedGUID="Creature-0-7121-0-2-525-2B600454CB"
units.nameplate1.guid=expectedGUID
row.expectedGUID=expectedGUID
actions={entry}
local direct=Cast.BuildMacros(units.nameplate1,entry)
eq(direct.withTarget,"/cast [@"..expectedGUID.."] 测试攻击","default combat action names only the hovered GUID")
eq(direct.withoutTarget,direct.withTarget,"current target existence never changes the GUID action")
eq(direct.guidMacro,direct.withTarget,"direct GUID macro has a dedicated protected snapshot attribute")
eq(direct.fallback,nil,"invalid GUID hover has no current-target or self fallback")
eq(direct.preserveTarget,true,"prepared action marks the target-preserving policy")
eq(direct.guard,"[@nameplate1,exists,harm,nodead] valid","native alias condition is retained only for diagnostic readback")
for _,command in ipairs({"/target","/cleartarget","/stopattack","/stopmacro","\n"}) do
    eq(direct.guidMacro:find(command,1,true),nil,"GUID cast macro excludes "..command)
end
eq(Cast.BuildMacros(units.nameplate1,wEntry),nil,"default candidate never rewrites or intercepts a user's macro")
local badGUIDs={"","not a GUID","Creature-one\n/cleartarget",secret,41}
for _,guid in ipairs(badGUIDs) do
    local data={unit="nameplate1",guid=guid,player=false,targetName="测试怪物"}
    eq(Cast.BuildMacros(data,entry),nil,"unreadable or invalid GUID cannot build a combat cast")
end
eq(Cast.BuildMacros({unit="nameplate1",player=false},entry),nil,"missing GUID cannot build a combat cast")
eq(Cast.BuildMacros({unit="nameplate1",guid=expectedGUID,player=true},entry),nil,"enemy player is outside the NPC GUID candidate")
local friendEntry={actionKind="spell",side="friendly",spell="测试攻击"}
eq(Cast.BuildMacros(units.nameplate1,friendEntry),nil,"friendly name compatibility cannot run in default policy")
eq(Cast.ArmRow(row),true,"same-name NPC can prepare original Z without name uniqueness")
eq(uniqueCalls,0,"default GUID preparation never scans NPC name uniqueness")
eq(Cast.Status(row).castMode,"guid_hover","UI status names the actual GUID candidate")
eq(Cast.Status(row).preserveTarget,true,"UI status marks target-preserving preparation")
local directProxy=Cast.states[row].proxies[1]
eq(directProxy:GetAttribute("snapshot-preserve-target"),true,"protected proxy stores the immutable casting policy")
eq(directProxy:GetAttribute("snapshot-guid-macro"),direct.guidMacro,"protected GUID macro matches the OOC builder")
eq(directProxy:GetAttribute("snapshot-fallback"),nil,"old name or target fallback is cleared during re-arm")
eq(directProxy:GetAttribute("unit"),nil,"macro proxy never puts raw GUID in native unit dispatch precondition")
eq(row:GetAttribute("combat-key-count"),1,"only supported original spell keys are intercepted")
units.nameplate2={unit="nameplate2",guid="Creature-0-7121-0-2-525-15A9C066A1",name="测试怪物",targetName="测试怪物",player=false,side="enemy",dead=false,offline=false}
local duplicate=frame("Button","CombatTestDuplicate",UIParent,"SecureActionButtonTemplate")
duplicate.side,duplicate.unit,duplicate.expectedGUID="enemy","nameplate2",units.nameplate2.guid
eq(Cast.ArmRow(duplicate),true,"second NPC with identical name has its own GUID action")
yes(Cast.states[duplicate].proxies[1]:GetAttribute("snapshot-guid-macro"):find(units.nameplate2.guid,1,true),
    "duplicate-name NPC retains its distinct literal GUID")
eq(uniqueCalls,0,"arming two same-name NPCs still never consults uniqueness")
actions={wEntry}
eq(Cast.ArmRow(row),false,"user macro descriptors are not armed in default policy")
eq(Cast.Status(row).reason,"no_actions","unsupported macro leaves the original key unintercepted")
eq(row:GetAttribute("combat-key-count"),0,"unsupported macro cannot install a secure key dispatch")
actions={entry};Cast.ArmRow(row)
local friend=frame("Button","CombatTestFriend",UIParent,"SecureActionButtonTemplate")
friend.side,friend.unit,friend.expectedGUID="friendly","nameplate3","Player-friend"
eq(Cast.ArmRow(friend),false,"nearby friendly name-switch bridge is disabled in default policy")
eq(Cast.Status(friend).reason,"unsupported_guid_unit","friendly row reports native-only candidate scope")
friend.unit="party1"
eq(Cast.ArmRow(friend),false,"stable friendly units remain on their native casting path")
eq(Cast.Status(friend).reason,"native_unit","stable friendly status retains the native path")
units.nameplate1.guid=secret
eq(Cast.ArmRow(row),false,"secret live NPC GUID cannot re-arm a default proxy")
units.nameplate1.guid=expectedGUID
Cast.ArmRow(row)
directProxy=Cast.states[row].proxies[1]
Cast.owner:SetAttribute("combat-active",true)
Cast.owner:SetAttribute("combat-hover-index",Cast.installed[row])
local unrelated={guid="Creature-0-7121-0-2-735-1111111111",name="原当前目标",player=false,side="enemy"}
units.target=unrelated
local parsed={}
local guardValid=true
local environment={self=directProxy,control=Cast.owner,SecureCmdOptionParse=function(options)
    parsed[#parsed+1]=options
    assert(options==direct.guard,"GUID secure branch must never query current-target existence")
    return guardValid and "valid" or nil
end}
setmetatable(environment,{__index=_G})
local model=assert(loadstring(Cast.Snippets.preClick))
setfenv(model,environment)
local function runModel()
    restrictedModel=true
    local ok,err=pcall(model)
    restrictedModel=false
    assert(ok,err)
end
combat=true
runModel()
eq(directProxy:GetAttribute("combat-branch"),"guid_hover","valid readable row chooses literal GUID branch")
eq(directProxy:GetAttribute("type"),"macro","GUID branch dispatches its prepared macro")
eq(directProxy:GetAttribute("macrotext"),direct.guidMacro,"GUID branch has no restoration or current-target selection")
eq(directProxy:GetAttribute("unit"),nil,"restricted GUID branch keeps native macro unit nil")
eq(units.target,unrelated,"Lua branch model never changes the current target object")
eq(#parsed,0,"GUID action selection never asks the native alias parser to authorize the literal GUID")
guardValid=false
runModel()
eq(directProxy:GetAttribute("combat-branch"),"guid_hover","native parser returning nil cannot suppress the captured GUID action")
eq(directProxy:GetAttribute("type"),"macro","a native alias miss still selects the immutable GUID macro")
eq(directProxy:GetAttribute("macrotext"),direct.guidMacro,"native alias miss does not alter the exact GUID command")
eq(#parsed,0,"even a parser that would return nil remains outside the pure GUID action path")
eq(units.target,unrelated,"native alias miss never selects or clears the current target")
local preparedGUIDMacro=directProxy.attrs["snapshot-guid-macro"]
directProxy.attrs["snapshot-guid-macro"]=nil
runModel()
eq(directProxy:GetAttribute("combat-branch"),"guid_hover_invalid","missing immutable GUID macro still fails closed")
eq(directProxy:GetAttribute("type"),nil,"missing GUID macro performs no action")
eq(directProxy:GetAttribute("macrotext"),nil,"missing GUID macro cannot retain a previously selected command")
directProxy.attrs["snapshot-guid-macro"]=""
runModel()
eq(directProxy:GetAttribute("type"),nil,"empty GUID snapshot is not an executable command")
directProxy.attrs["snapshot-guid-macro"]=preparedGUIDMacro
row.attrs["combat-prepared"]=false
runModel()
eq(directProxy:GetAttribute("combat-branch"),"disabled","unprepared row still disables the pure GUID action")
eq(directProxy:GetAttribute("type"),nil,"unprepared row cannot execute its stored GUID")
row.attrs["combat-prepared"]=true
Cast.owner.attrs["combat-hover-index"]=Cast.installed[duplicate]
runModel()
eq(directProxy:GetAttribute("type"),nil,"a different actual hovered row disables the old GUID action")
eq(directProxy:GetAttribute("combat-branch"),"disabled","hover ownership remains a required secure guard")
Cast.owner.attrs["combat-hover-index"]=Cast.installed[row]
Cast.owner.attrs["combat-active"]=false
runModel()
eq(directProxy:GetAttribute("type"),nil,"inactive combat owner cannot dispatch a stored GUID")
eq(directProxy:GetAttribute("combat-branch"),"idle","inactive combat remains a distinct non-dispatch branch")
Cast.owner.attrs["combat-active"]=true
Cast.owner.attrs["guid-probe-suspended"]=true
runModel()
eq(directProxy:GetAttribute("type"),nil,"existing explicit suspension guard remains effective")
Cast.owner.attrs["guid-probe-suspended"]=false
environment.SecureCmdOptionParse=function() error("native alias parser must not select pure GUID actions") end
runModel()
eq(directProxy:GetAttribute("macrotext"),direct.guidMacro,"pure GUID action survives an unavailable native alias parser")
eq(units.target,unrelated,"all pure branch choices leave current target object untouched")
guardValid=true;runModel()
records={}
NS.Diagnostics.Record=function(kind,fields) records[#records+1]={kind=kind,fields=fields} end
SecureCmdOptionParse=function() return nil end
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(records[1].kind,"COMBAT_KEY_PREPARE","combat GUID preparation retains its separate diagnostic entry")
eq(records[1].fields.aliasGuardPublicResult,"[nil]","public native alias parse nil is explicitly logged as observation")
eq(records[1].fields.snapshotMacroPresent,true,"key log distinguishes existing immutable GUID command from missing macro")
eq(records[1].fields.selectedActionType,"macro","key log exposes the action actually selected by secure preflight")
eq(records[1].fields.selectedCommandMatches,true,"key log confirms selected command matches the immutable snapshot")
eq(records[2].kind,"GUID_HOVER_POSTCLICK","combat GUID completion logs its own target observations")
eq(records[2].fields.targetGUIDBefore,unrelated.guid,"pre-click target GUID is logged independently")
eq(records[2].fields.targetGUIDAfter,unrelated.guid,"post-click target GUID is logged independently")
eq(records[2].fields.targetChangedObserved,false,"matching public observations are labelled as observations only")
eq(records[2].fields.recipientProven,nil,"Lua observations never claim native recipient proof")
eq(records[2].fields.macrotext,nil,"post-click log does not serialize the macro")
local attemptStarts,attemptEnds={},{}
NS.Diagnostics.BeginCastAttempt=function(fields) attemptStarts[#attemptStarts+1]=fields;return 71 end
NS.Diagnostics.EndCastAttempt=function(id,fields) attemptEnds[#attemptEnds+1]={id=id,fields=fields} end
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(#attemptStarts,1,"valid combat GUID dispatch opens a normal-tile observation window")
eq(attemptStarts[1].route,"combat","combat attempt labels its actual route")
eq(attemptStarts[1].expectedGUID,units.nameplate1.guid,"window records prepared GUID independently of target")
eq(attemptStarts[1].generatedCommand,direct.guidMacro,"window receives only the generated single-line GUID command")
eq(attemptStarts[1].beforeTargetGUID,unrelated.guid,"window retains current target as an observation")
eq(attemptStarts[1].recipientProven,false,"attempt does not claim a recipient")
eq(#attemptEnds,1,"paired hardware Post is observed")
eq(attemptEnds[1].id,71,"Pre and Post share an attempt ID")
eq(directProxy.guidHoverLogID,nil,"Post clears pending log association")
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(#attemptEnds,1,"duplicate Post cannot reuse the preceding attempt")
guardValid=false;runModel()
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(#attemptStarts,2,"native alias parse nil still opens a real GUID dispatch observation window")
eq(#attemptEnds,2,"native alias parse nil still pairs the dispatched action's PostClick")
eq(attemptStarts[2].selectedCommandMatches,true,"alias miss window records the exact selected GUID command")
directProxy.attrs["snapshot-guid-macro"]=nil;runModel()
local missingLog=#records+1
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(#attemptStarts,2,"missing GUID snapshot cannot start a real dispatch observation window")
eq(records[missingLog].fields.snapshotMacroPresent,false,"missing command is explicitly distinguished in the key log")
eq(records[missingLog].fields.selectedActionType,"[nil]","missing command log confirms no action was selected")
eq(records[missingLog].fields.selectedCommandMatches,false,"missing command cannot be marked as a selected immutable macro")
directProxy.attrs["snapshot-guid-macro"]=preparedGUIDMacro
guardValid=true;runModel()
SecureCmdOptionParse=function() error("public parse unavailable") end
local parseErrorLog=#records+1
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
eq(records[parseErrorLog].fields.aliasGuardPublicResult,"[api-error]","diagnostic alias API error is retained without affecting dispatch")
eq(directProxy:GetAttribute("macrotext"),direct.guidMacro,"diagnostic alias API failure cannot suppress pure GUID dispatch")
SecureCmdOptionParse=function() return secret end
local restrictedParseLog=#records+1
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
eq(records[restrictedParseLog].fields.aliasGuardPublicResult,"[restricted]","restricted alias parse result is redacted rather than compared")
SecureCmdOptionParse=nil
NS.Diagnostics.BeginCastAttempt=function() error("logger failed") end
local commandBefore=directProxy:GetAttribute("macrotext")
eq(pcall(directProxy:GetScript("PreClick"),directProxy,"LeftButton",true),true,"window logger failure cannot abort secure dispatch")
eq(directProxy:GetAttribute("macrotext"),commandBefore,"logging does not mutate a prepared combat command")
eq(units.target,unrelated,"logging never changes current target")
NS.Diagnostics.BeginCastAttempt=nil;NS.Diagnostics.EndCastAttempt=nil
eq(Cast.ArmRow(row),false,"ordinary Lua still cannot rewrite GUID actions during combat")
combat=false
Cast.owner:SetAttribute("combat-active",false)
local logged=#records
directProxy:GetScript("PreClick")(directProxy,"LeftButton",true)
directProxy:GetScript("PostClick")(directProxy,"LeftButton",true)
eq(#records,logged,"inactive combat observer does not duplicate the NearbyCast OOC logs")
NS.PreserveCastTarget=nil
eq(Cast.BuildMacros(units.nameplate1,entry).guidMacro,direct.guidMacro,"missing policy flag also defaults to target preservation")
NS.PreserveCastTarget=true

print("Targets combat-cast simulated checks: "..checks.."; native secure engine and spell actions were not executed")
