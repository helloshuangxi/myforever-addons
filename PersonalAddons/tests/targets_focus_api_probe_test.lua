-- Configuration/observation simulation only; does not emulate secure actions.
local checks=0
local function eq(a,b,message) checks=checks+1;assert(a==b,message) end
local secret=setmetatable({}, {__tostring=function() error("formatted secret") end})
issecretvalue=function(v) return rawequal(v,secret) end
local combat=false
InCombatLockdown=function() return combat end
local methods,frames={},{}
local nativeClick=function() end
local function frame(kind,name,parent,template)
    local b=setmetatable({kind=kind,name=name,parent=parent,attrs={},scripts={},hooks={},shown=true,template=template or ""},{__index=methods})
    if b.template:find("SecureActionButtonTemplate",1,true) then b.scripts.OnClick=nativeClick end
    frames[#frames+1]=b;return b
end
for _,k in ipairs({"SetSize","SetPoint","SetFrameStrata","EnableMouse","RegisterForClicks","SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetWidth"}) do methods[k]=function() end end
function methods:SetAttribute(k,v) assert(not combat,"insecure combat attribute write");self.attrs[k]=v end
function methods:GetAttribute(k) return self.attrs[k] end
function methods:CreateFontString() return frame("FontString") end
function methods:SetText(v) self.text=v end
function methods:HookScript(k,fn) self.hooks[k]=fn end
function methods:Show() assert(not combat);self.shown=true end
function methods:Hide() assert(not combat);self.shown=false end
function methods:IsVisible() return self.shown end
function methods:IsShown() return self.shown end
CreateFrame=frame;UIParent=frame("Frame")
local wrapped,driver={},nil
SecureHandlerWrapScript=function(b,event,owner,script) wrapped[event]=script end
RegisterStateDriver=function(b,state,text) assert(not combat);driver=text end
UnregisterStateDriver=function() assert(not combat);driver=nil end
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]=fn end}
local units={nameplate1={guid="Creature-A",name="同名狼",player=false,dead=false,harm=true},
 nameplate2={guid="Creature-B",name="同名狼",player=false,dead=false,harm=true},
 target={guid="Player-T",name="原目标",player=true,dead=false,harm=false}}
UnitExists=function(u) return units[u]~=nil end
UnitGUID=function(u) return units[u] and units[u].guid end
UnitName=function(u) return units[u] and units[u].name end
UnitIsPlayer=function(u) return units[u] and units[u].player end
UnitIsDeadOrGhost=function(u) return units[u] and units[u].dead end
UnitCanAttack=function(_,u) return units[u] and units[u].harm end
SpellIsTargeting=function() return false end
CursorHasItem=function() return false end
local apiHooks,apiHookCount={},0
TargetUnit=function() end
FocusUnit=function() end
TargetNearestEnemy=function() end
hooksecurefunc=function(name,callback) apiHooks[name]=callback;apiHookCount=apiHookCount+1 end
SecureButton_GetModifiedUnit=function(b) return b.attrs['*unit2'] or b.attrs.unit end
SecureButton_GetModifiedAttribute=function(b,name) return b.attrs['*'..name..'2'] end
local NS={}
assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/Core.lua'))('MyForeverTargets',NS)
local records={}
local diagnosticsEnabled,diagnosticsStarts=false,0
local respectLogEnabled=false
NS.Diagnostics={Record=function(kind,fields)
 if respectLogEnabled and not diagnosticsEnabled then return false end
 records[#records+1]={kind=kind,fields=fields};return true
 end,
 Enabled=function() return diagnosticsEnabled end,
 Start=function() diagnosticsEnabled=true;diagnosticsStarts=diagnosticsStarts+1 end}
local messages={}
NS.Print=function(message) messages[#messages+1]=message end
local r1,r2=frame("Button"),frame("Button")
r1.unit="nameplate1";r1.expectedGUID="Creature-A"
r2.unit="nameplate2";r2.expectedGUID="Creature-B"
NS.UI={enemy={tiles={r1,r2}}}
assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/FocusAPIProbe.lua'))('MyForeverTargets',NS)
local P=NS.FocusAPIProbe
eq(P.button,nil,"module must create no frame while dormant")
eq(apiHookCount,0,"dormant module installs no API hooks")
eq(P.Command('native 1'),true,"native prepare")
local b=P.button
eq(b.scripts.OnClick,nativeClick,"preserve native OnClick")
eq(b.attrs['*type2'],'focus',"native focus type")
eq(b.attrs['*unit2'],'nameplate1',"native exact token")
eq(b.attrs.unit,nil,"no base unit")
eq(b.attrs.useOnKeyDown,false,"release click matches original tiles")
eq(driver,'[combat] hide; show',"combat hide driver")
eq(wrapped.PreClick:find('[combat]',1,true)~=nil,true,"secure combat guard installed")
b.hooks.PreClick(b,'RightButton',false)
eq(records[#records].fields.prepared,true,"valid before click")
eq(records[#records].fields.rawGUIDExists,false,"false raw existence retained")
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.focusChangedToExpected,false,"no native effect is not success")
eq(records[#records].fields.targetUnchanged,true,"original target unchanged")
eq(records[#records].fields.afterFocusGUID,'[nil]',"nil focus distinguished")
units.focus={guid=secret}
b.hooks.PreClick(b,'RightButton',false)
units.focus=units.nameplate1
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.beforeFocusExists,true,"secret prior focus still recorded as existing")
eq(records[#records].fields.focusMatchesExpected,true,"after-focus identity is readable")
eq(records[#records].fields.focusChangedToExpected,false,"unknown prior focus is not proof of change")
units.focus=nil
units.target.guid=secret
b.hooks.PreClick(b,'RightButton',false)
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.targetUnchanged,false,"existing target with unreadable GUID is unknown")
local previousTarget=units.target
units.target=nil
b.hooks.PreClick(b,'RightButton',false)
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.targetUnchanged,true,"empty target before and after is unchanged")
units.target=previousTarget;units.target.guid='Player-T'
eq(P.Command('macro 2'),true,"guid macro prepare")
eq(b.attrs['*type2'],'macro',"macro focus type")
eq(b.attrs['*unit2'],nil,"macro must avoid unit preflight")
eq(b.attrs.unit,nil,"macro no base unit")
eq(b.attrs['*macrotext2'],'/stopmacro [combat]\n/focus [@Creature-B]',"macro only explicit GUID focus")
b.hooks.PreClick(b,'RightButton',false)
-- This explicit mock change tests observation only, not a native focus action.
units.focus=units.nameplate2
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.focusChangedToExpected,true,"matching changed focus observation")
eq(records[#records].fields.targetUnchanged,true,"target readback unchanged")
timers[#timers]()
eq(records[#records].kind,'FOCUS_API_PROBE_READBACK',"delayed readback")
eq(records[#records].fields.focusMatchesExpected,true,"delayed GUID comparison")
eq(P.Command('guid 1'),true,"raw guid prepare")
eq(b.attrs['*unit2'],'Creature-A',"raw guid direct unit")
units.nameplate1.guid='Creature-C'
b.hooks.PreClick(b,'RightButton',false)
eq(b.attrs['*type2'],'macro',"recycled token blocked")
eq(b.attrs['*macrotext2'],'/stopmacro',"invalid action noop")
eq(records[#records].fields.prepared,false,"mismatched GUID rejected")
units.nameplate1.guid='Creature-A'
eq(P.Command('native 1'),true,"rearm")
combat=true
eq(P.Command('macro 2'),false,"combat preparation refused")
eq(P.active,false,"rejected combat request disarms the prior capture")
local beforeRejectedClickRecords=#records
b.hooks.PreClick(b,'RightButton',false) -- secure wrapper handled native noop; no insecure writes here.
eq(#records,beforeRejectedClickRecords,"disarmed combat click creates no attempt")
eq(P.currentAttempt,nil,"disarmed combat click leaves no observation window")
combat=false
r1.expectedGUID=secret
eq(P.Command('native 1'),false,"secret expected identity refused")
eq(P.active,false,"failed prepare disarms prior test")
eq(b.shown,false,"failed prepare hides prior button")
r1.expectedGUID='Creature-A'
eq(P.Command('native 1'),true,"prepare after secret rejection")
units.nameplate1.guid=secret
b.hooks.PreClick(b,'RightButton',false)
eq(records[#records].fields.prepared,false,"secret live identity refused")
eq(b.attrs['*macrotext2'],'/stopmacro',"secret cannot retain focus action")
units.nameplate1.guid='Creature-A'
eq(P.Command('off'),true,"off succeeds")
eq(P.active,false,"off disarms")
eq(b.shown,false,"off hidden")
eq(driver,nil,"off unregisters driver")
eq(b.attrs['*unit2'],nil,"off clears unit")
eq(b.attrs['*macrotext2'],'/stopmacro',"off leaves noop")
eq(apiHookCount,3,"API hooks installed only once on first build")
local oldCount=#records
apiHooks.TargetUnit('nameplate1')
apiHooks.FocusUnit('nameplate1')
eq(#records,oldCount,"inactive API calls are not recorded")
eq(P.Command('target 1'),false,"target mode refuses nonempty original target")
eq(P.active,false,"refusal leaves dormant action")
units.target=nil
eq(P.Command('target 1'),true,"target mode prepares only from empty target")
eq(b.attrs['*type2'],'target',"native target action")
eq(b.attrs['*unit2'],'nameplate1',"target uses exact nameplate token")
eq(b.attrs['*macrotext2'],nil,"target mode has no focus or restoration macro")
b.hooks.PreClick(b,'RightButton',false)
eq(records[#records].fields.prepared,true,"target click rechecks empty target")
-- Execute only the observation snippet with an intentionally different secure
-- UnitExists result. This is not a simulation of native target selection.
local snippet=assert(loadstring(wrapped.OnClick))
setfenv(snippet,setmetatable({self=b,UnitExists=function() return false end,
 SecureCmdOptionParse=function() return nil end},{__index=_G}))
snippet()
eq(b.attrs['*type2'],'target',"secure observer does not alter the native action")
units.target=units.nameplate1 -- explicit test fixture, not a native API effect
apiHooks.TargetUnit('nameplate1')
eq(records[#records].kind,'FOCUS_API_PROBE_DISPATCH',"actual target API callback is recorded")
eq(records[#records].fields.api,'TargetUnit',"dispatch names the actual API")
eq(records[#records].fields.actualUnit,'nameplate1',"dispatch captures actual unit argument")
b.hooks.OnClick(b,'RightButton',false,false,true)
eq(records[#records].fields.resolvedType,'target',"OnClick observes resolved action")
eq(records[#records].fields.normalUnitExists,true,"normal Lua existence remains separate")
eq(records[#records].fields.secureUnitExists,false,"secure existence difference preserved")
eq(records[#records].fields.secureExistsCondition,'[nil]',"unmatched secure macro condition preserved")
eq(records[#records].fields.isSecureAction,true,"input security flag observed")
apiHooks.TargetUnit(secret)
eq(records[#records].fields.actualUnit,'[restricted]',"hook redacts secret arguments")
b.hooks.PostClick(b,'RightButton',false)
eq(records[#records].fields.targetMatchesExpected,true,"target result compares GUID")
eq(records[#records].fields.targetUnchanged,false,"target mode reports target changed")
eq(records[#records].fields.focusUnchanged,true,"target mode preserves existing focus observation")
oldCount=#records
apiHooks.FocusUnit('nameplate2')
eq(#records,oldCount,"after-click API calls outside the window are ignored")
units.target=nil
eq(P.Command('target 1'),true,"target reprepare")
units.target=units.nameplate2
b.hooks.PreClick(b,'RightButton',false)
eq(records[#records].fields.prepared,false,"target becoming nonempty before click refuses action")
eq(records[#records].fields.reason,'target_not_empty_or_unknown',"refusal identifies changed target state")
eq(b.attrs['*type2'],'macro',"nonempty target switches to noop")
eq(b.attrs['*macrotext2'],'/stopmacro',"no focus or target action after refusal")
eq(P.Command('off'),true,"target test closes")
units.target=nil
for _,api in ipairs({'SpellIsTargeting','CursorHasItem'}) do
 _G[api]=function() return true end
 eq(P.Command('target 1'),false,api..' active at prepare refuses target mode')
 _G[api]=nil
 eq(P.Command('target 1'),false,api..' missing at prepare refuses target mode')
 _G[api]=function() return false end
 eq(P.Command('target 1'),true,api..' explicit false permits preparation')
 _G[api]=function() return true end
 b.hooks.PreClick(b,'RightButton',false)
 eq(records[#records].fields.prepared,false,api..' active at click refuses target mode')
 eq(b.attrs['*macrotext2'],'/stopmacro',api..' active click leaves only noop')
 _G[api]=function() return false end
 eq(P.Command('target 1'),true,api..' reset permits preparation')
 _G[api]=function() return secret end
 b.hooks.PreClick(b,'RightButton',false)
 eq(records[#records].fields.prepared,false,api..' secret at click refuses target mode')
 eq(b.attrs['*macrotext2'],'/stopmacro',api..' secret click leaves only noop')
 _G[api]=function() return false end
end
eq(P.Command('off'),true,"cursor guard tests close")
eq(P.Command('target 1'),true,"prepare missing-PostClick observation test")
b.hooks.PreClick(b,'RightButton',false)
timers[#timers]() -- the next-frame fallback; native PostClick was skipped
eq(P.currentAttempt,nil,"aborted click window expires on the next frame")
oldCount=#records
apiHooks.TargetUnit('nameplate2')
eq(#records,oldCount,"aborted click does not capture later unrelated actions")
eq(P.Command('off'),true,"aborted click test closes")

-- Cycling tests observe callbacks and explicit fixtures. They do not execute
-- native slash commands or prove that one hardware event can retarget twice.
local function latest(kind)
 for i=#records,1,-1 do if records[i].kind==kind then return records[i].fields end end
 error('missing record '..kind)
end
local cycleMacro='/stopmacro [combat]\n/targetenemy\n/targetenemy\n/cleartarget'
local controlFirstMacro='/stopmacro [combat]\n/targetenemy'
local controlSecondMacro='/stopmacro [combat]\n/targetenemy\n/cleartarget'
local function beginCycle(mode)
 units.target=nil
 r1.unit='nameplate1';r1.expectedGUID='Creature-A'
 units.nameplate1.guid='Creature-A'
 eq(P.Command(mode..' 1'),true,mode..' prepares from an empty target')
 b.hooks.PreClick(b,'RightButton',false)
 eq(latest('FOCUS_API_PROBE_PRE').prepared,true,mode..' click passes guards')
end
local function cycleSample(unit,ordinal,phase)
 units.target=unit
 apiHooks.TargetNearestEnemy(false)
 local s=latest('FOCUS_API_PROBE_CYCLE_STEP')
 eq(s.ordinal,ordinal,'cycle sample keeps its ordinal')
 eq(s.phase,phase,'cycle sample keeps the current click phase')
 return s
end
local function finishCycle()
 units.target=nil -- explicit fixture for the final /cleartarget, not an API effect
 b.hooks.PostClick(b,'RightButton',false)
 return latest('FOCUS_API_PROBE_POST')
end

units.target=nil
local startsBeforeInitialCycle=diagnosticsStarts
eq(P.Command('cycle 1'),true,'double-command mode prepares')
eq(diagnosticsEnabled,true,'cycle preparation enables available diagnostics')
eq(diagnosticsStarts,startsBeforeInitialCycle+1,'cycle preparation renews diagnostics once')
eq(b.attrs['*type2'],'macro','cycle uses the native macro action')
eq(b.attrs['*unit2'],nil,'cycle avoids unit preflight')
eq(b.attrs.unit,nil,'cycle has no base unit')
eq(b.attrs['*macrotext2'],cycleMacro,'cycle contains only two targetenemy commands and cleanup')
eq(b.scripts.OnClick,nativeClick,'cycle preserves native OnClick')
eq(P.Command('off'),true,'configuration check disarms')
oldCount=#records
apiHooks.TargetNearestEnemy(false)
eq(#records,oldCount,'inactive nearest-enemy calls are ignored')

local startsBeforeCycle=diagnosticsStarts
beginCycle('cycle')
local sample=cycleSample(units.nameplate1,1,'cycle')
eq(sample.targetGUID,'Creature-A','first sample reads current target GUID')
eq(sample.targetExists,true,'first sample records existing target')
sample=cycleSample(units.nameplate2,2,'cycle')
eq(sample.targetGUID,'Creature-B','second sample reads a different target GUID')
local result=finishCycle()
eq(result.cycleDispatchCount,2,'cycle records two API returns')
eq(result.cycleAdvanced,true,'two valid different observed GUIDs are distinguished')
eq(result.controlAdvanced,false,'double-command observation is not a control result')
eq(result.targetUnchanged,true,'cleared target is read back against the empty baseline')
eq(result.focusUnchanged,true,'cycle observation preserves the baseline focus')
eq(diagnosticsStarts,startsBeforeCycle+1,'a successful cycle preparation renews diagnostics')
oldCount=#records
apiHooks.TargetNearestEnemy(false)
eq(#records,oldCount,'post-click nearest-enemy calls are outside the attempt')
eq(P.Command('off'),true,'different GUID observation closes')

beginCycle('cycle')
cycleSample(units.nameplate1,1,'cycle')
cycleSample(units.nameplate1,2,'cycle')
result=finishCycle()
eq(result.cycleDispatchCount,2,'same GUID still records both API returns')
eq(result.cycleAdvanced,false,'two calls alone do not prove target advancement')
eq(P.Command('off'),true,'same GUID observation closes')

beginCycle('cycle')
cycleSample({guid=secret},1,'cycle')
eq(latest('FOCUS_API_PROBE_CYCLE_STEP').targetGUID,'[nil]','Core.Read suppresses secret target identity')
eq(latest('FOCUS_API_PROBE_CYCLE_STEP').targetExists,true,'unreadable identity is not reported as an absent target')
cycleSample(units.nameplate2,2,'cycle')
result=finishCycle()
eq(result.cycleDispatchCount,2,'unreadable first sample retains its ordinal slot')
eq(result.cycleAdvanced,false,'unreadable first GUID cannot count as advancement')
eq(P.Command('off'),true,'secret GUID observation closes')

beginCycle('cycle')
cycleSample(units.nameplate1,1,'cycle')
cycleSample(nil,2,'cycle')
result=finishCycle()
eq(result.cycleDispatchCount,2,'missing second sample retains its ordinal slot')
eq(result.cycleAdvanced,false,'a missing second target is not an advancement')
eq(P.Command('off'),true,'missing GUID observation closes')

beginCycle('cycle')
cycleSample(units.nameplate1,1,'cycle')
result=finishCycle()
eq(result.cycleDispatchCount,1,'only one API return is reported honestly')
eq(result.cycleAdvanced,false,'one callback cannot prove a double retarget')
eq(P.Command('off'),true,'single callback observation closes')

for _,mode in ipairs({'cycle','cyclecontrol'}) do
 units.target=units.nameplate2
 eq(P.Command(mode..' 1'),false,mode..' refuses a nonempty original target')
 eq(P.active,false,mode..' failed preparation is not armed')
 units.target=nil
 eq(P.Command(mode..' 1'),true,mode..' prepares after target clears')
 units.target=units.nameplate2
 b.hooks.PreClick(b,'RightButton',false)
 eq(latest('FOCUS_API_PROBE_PRE').prepared,false,mode..' rechecks an intervening target')
 eq(b.attrs['*macrotext2'],'/stopmacro',mode..' refuses changed target before action')
 oldCount=#records
 apiHooks.TargetNearestEnemy(false)
 eq(#records,oldCount,mode..' denied attempt does not count nearest-enemy callbacks')
 b.hooks.PostClick(b,'RightButton',false)
 eq(P.Command('off'),true,mode..' changed-target test closes')
 units.target=nil
 combat=true
 eq(P.Command(mode..' 1'),false,mode..' refuses preparation in combat')
 combat=false
 eq(P.Command(mode..' 1'),true,mode..' prepares outside combat')
 combat=true
 b.hooks.PreClick(b,'RightButton',false)
 eq(latest('FOCUS_API_PROBE_PRE').prepared,false,mode..' rejects combat at click without insecure attribute writes')
 combat=false
 eq(P.Command('off'),true,mode..' combat test closes')
 for _,api in ipairs({'SpellIsTargeting','CursorHasItem'}) do
  _G[api]=function() return true end
  eq(P.Command(mode..' 1'),false,mode..' refuses active '..api..' during preparation')
  _G[api]=nil
  eq(P.Command(mode..' 1'),false,mode..' refuses unavailable '..api..' during preparation')
  _G[api]=function() return false end
  eq(P.Command(mode..' 1'),true,mode..' permits explicit false '..api)
  _G[api]=function() return secret end
  b.hooks.PreClick(b,'RightButton',false)
  eq(latest('FOCUS_API_PROBE_PRE').prepared,false,mode..' refuses secret '..api..' at click')
  eq(b.attrs['*macrotext2'],'/stopmacro',mode..' secret cursor state leaves noop')
  _G[api]=function() return false end
  eq(P.Command('off'),true,mode..' cursor test closes')
 end
end

-- First control click deliberately retains its observed target; the second
-- click must own exactly that GUID even if choosing it rebinds the tile.
beginCycle('cyclecontrol')
eq(b.attrs['*macrotext2'],controlFirstMacro,'first control click retains its selected target')
local capture=P.capture
cycleSample(units.nameplate1,1,'first')
b.hooks.PostClick(b,'RightButton',false)
result=latest('FOCUS_API_PROBE_POST')
eq(result.phase,'first','first control result is tagged first')
eq(result.cycleDispatchCount,1,'first control result has one API return')
eq(result.controlAdvanced,false,'first click alone is not a control advancement')
eq(capture.controlGUID,'Creature-A','first valid observed target is captured by GUID')
eq(capture.step,'second','valid first control click prepares the second phase')
eq(P.active,true,'first control phase remains available for a second hardware event')
r1.unit='target';r1.expectedGUID='Creature-B' -- intervening tile rebind, not a target change
b.hooks.PreClick(b,'RightButton',false)
eq(latest('FOCUS_API_PROBE_PRE').prepared,true,'second control permits changed row binding when target is still owned')
eq(b.attrs['*macrotext2'],controlSecondMacro,'second control click selects once then clears')
cycleSample(units.nameplate2,1,'second')
result=finishCycle()
eq(result.phase,'second','second control result is tagged second')
eq(result.controlAdvanced,true,'second independent click compares against captured control GUID')
eq(result.cycleAdvanced,false,'control advancement is not a one-click double-command result')
eq(result.afterTargetExists,false,'second control fixture records cleared target')
eq(result.focusUnchanged,true,'two-click control leaves focus unchanged')
eq(capture.step,'done','second control phase finishes')
eq(P.active,false,'completed control cannot accept another attempt')
eq(b.shown,false,'completed control hides its temporary button')
eq(b.attrs['*macrotext2'],'/stopmacro','completed control clears the action')
eq(P.Command('off'),true,'completed control cleanup succeeds')
r1.unit='nameplate1';r1.expectedGUID='Creature-A'

beginCycle('cyclecontrol')
capture=P.capture
cycleSample(units.nameplate1,1,'first')
b.hooks.PostClick(b,'RightButton',false)
units.target=units.nameplate2 -- player changed the retained target
b.hooks.PreClick(b,'RightButton',false)
eq(latest('FOCUS_API_PROBE_PRE').prepared,false,'second control rejects a manually changed target')
eq(latest('FOCUS_API_PROBE_PRE').reason,'control_target_changed','changed target has a specific refusal reason')
eq(b.attrs['*macrotext2'],'/stopmacro','changed control target cannot dispatch a command')
oldCount=#records
apiHooks.TargetNearestEnemy(false)
eq(#records,oldCount,'a denied second control does not record an API return')
b.hooks.PostClick(b,'RightButton',false)
eq(latest('FOCUS_API_PROBE_POST').controlAdvanced,false,'refused second control cannot report advancement')
eq(capture.controlGUID,'Creature-A','refusal never adopts the manually chosen target')
eq(P.Command('off'),true,'changed control target test closes')

beginCycle('cyclecontrol')
capture=P.capture
cycleSample({guid=secret},1,'first')
b.hooks.PostClick(b,'RightButton',false)
eq(capture.controlGUID,nil,'unreadable first control target is never adopted')
eq(capture.step~='second',true,'unreadable first control target cannot arm step two')
eq(b.attrs['*macrotext2'],'/stopmacro','unconfirmed first control stops at noop')
eq(P.active,false,'unconfirmed first control cannot rearm itself on another click')
eq(b.shown,false,'unconfirmed first control hides its button')
eq(P.Command('off'),true,'unreadable control test closes')

beginCycle('cyclecontrol')
capture=P.capture
cycleSample(units.nameplate1,1,'first')
units.target=units.nameplate2 -- another callback changed target after our API return
b.hooks.PostClick(b,'RightButton',false)
eq(capture.controlGUID,nil,'PostClick never adopts a target different from its API-return sample')
eq(capture.step~='second',true,'intervening first-click target change cannot arm the second phase')
eq(b.attrs['*macrotext2'],'/stopmacro','unowned first-click result stops at noop')
eq(P.active,false,'first control ownership mismatch disarms')
eq(b.shown,false,'first control ownership mismatch hides the button')
eq(P.Command('off'),true,'first control ownership mismatch test closes')

for _,case in ipairs({
 {name='same',unit=units.nameplate1},
 {name='unreadable',unit={guid=secret}},
 {name='missing'},
}) do
 beginCycle('cyclecontrol')
 capture=P.capture
 cycleSample(units.nameplate1,1,'first')
 b.hooks.PostClick(b,'RightButton',false)
 eq(capture.step,'second',case.name..' control fixture enters its second phase')
 b.hooks.PreClick(b,'RightButton',false)
 eq(latest('FOCUS_API_PROBE_PRE').prepared,true,case.name..' control second click owns its initial target')
 cycleSample(case.unit,1,'second')
 result=finishCycle()
 eq(result.cycleDispatchCount,1,case.name..' second control still reports one API return')
 eq(result.controlAdvanced,false,case.name..' second control sample cannot prove advancement')
 eq(capture.step,'done',case.name..' second control finishes without retrying')
 eq(P.active,false,case.name..' finished control disarms')
 eq(b.shown,false,case.name..' finished control hides its button')
 eq(P.Command('off'),true,case.name..' second control test closes')
end

beginCycle('cyclecontrol')
capture=P.capture
cycleSample(units.nameplate1,1,'first')
cycleSample(units.nameplate2,2,'first')
b.hooks.PostClick(b,'RightButton',false)
eq(capture.controlGUID,nil,'unexpected two returns cannot establish first-click ownership')
eq(P.active,false,'unexpected first-click dispatch count disarms the control')
eq(b.attrs['*macrotext2'],'/stopmacro','unexpected first-click dispatch count leaves noop')
eq(P.Command('off'),true,'unexpected first control dispatch test closes')

local normalUnitExists=UnitExists
for _,mode in ipairs({'cycle','cyclecontrol'}) do
 units.target=nil
 UnitExists=function(unit) if unit=='target' then return nil end;return normalUnitExists(unit) end
 eq(P.Command(mode..' 1'),false,mode..' refuses unknown original-target existence')
 UnitExists=normalUnitExists
end
local nearestHookInstalled=P.dispatchHooks.TargetNearestEnemy
P.dispatchHooks.TargetNearestEnemy=false
units.target=nil
eq(P.Command('cycle 1'),false,'cycle refuses to run without its API-return observation hook')
eq(P.active,false,'missing cycle hook leaves the probe disarmed')
eq(b.attrs['*macrotext2'],'/stopmacro','missing cycle hook leaves only noop')
P.dispatchHooks.TargetNearestEnemy=nearestHookInstalled

units.target=nil
eq(P.Command('cycle 1'),true,'cycle prepares fallback-window check')
b.hooks.PreClick(b,'RightButton',false)
timers[#timers]()
oldCount=#records
apiHooks.TargetNearestEnemy(false)
eq(#records,oldCount,'missing PostClick expires cycle sampling before unrelated calls')
eq(P.Command('off'),true,'cycle fallback-window check closes')

-- These regressions enforce the real logger's disabled behavior: a rejected
-- request must start diagnostics before any early return can be observed.
respectLogEnabled=true
local function loggedRejection(probe,command,reason,label)
 diagnosticsEnabled=false
 local beforeRecords,beforeMessages,beforeStarts=#records,#messages,diagnosticsStarts
 local ok,actualReason=probe.Command(command)
 eq(ok,false,label..' is rejected')
 if reason then eq(actualReason,reason,label..' returns its specific reason') end
 eq(diagnosticsStarts,beforeStarts+1,label..' starts diagnostics before rejecting')
 eq(diagnosticsEnabled,true,label..' leaves rejection logging enabled')
 local request,rejection,requestIndex,rejectionIndex
 for i=beforeRecords+1,#records do
  local item=records[i]
  if item.kind=='FOCUS_API_PROBE_COMMAND' then request=item.fields;requestIndex=i end
  if item.kind=='FOCUS_API_PROBE_REJECT' then rejection=item.fields;rejectionIndex=i end
 end
 eq(request~=nil,true,label..' logs the request even when preparation fails')
 eq(rejection~=nil,true,label..' logs the rejection even when preparation fails')
 eq(requestIndex<rejectionIndex,true,label..' logs request before rejection')
 eq(request.requestID~=nil,true,label..' assigns a request identity')
 eq(rejection.requestID,request.requestID,label..' correlates rejection to its request')
 eq(rejection.reason,actualReason,label..' logs the actual refusal reason')
 eq(#messages>beforeMessages,true,label..' prints an explanation')
 eq(type(messages[#messages])=='string' and messages[#messages]:find('[\128-\255]')~=nil,true,
  label..' prints a Chinese explanation')
 eq(probe.active,false,label..' leaves no armed action')
 if probe.button then eq(probe.button.shown,false,label..' leaves the cached button hidden') end
 return actualReason
end

units.target=nil
r1.expectedGUID=nil
loggedRejection(P,'native 1','invalid_row','empty tile native request')
r1.expectedGUID='Creature-A'
units.target=units.nameplate2
loggedRejection(P,'cycle 1','target_not_empty_or_unknown','occupied target request')
units.target=nil
SpellIsTargeting=function() return true end
loggedRejection(P,'cyclecontrol 1','spell_targeting_or_unknown','pending spell request')
SpellIsTargeting=function() return false end
combat=true
loggedRejection(P,'cycle 1','combat_or_unknown','combat request')
combat=false
nearestHookInstalled=P.dispatchHooks.TargetNearestEnemy
P.dispatchHooks.TargetNearestEnemy=false
loggedRejection(P,'cycle 1','cycle_hook_unavailable','unavailable cycle observer')
P.dispatchHooks.TargetNearestEnemy=nearestHookInstalled
loggedRejection(P,'cycle nope','invalid_command','invalid cycle argument')

local startsBeforeStatus=diagnosticsStarts
P.Command('status')
eq(diagnosticsStarts,startsBeforeStatus,'status does not renew diagnostics')
P.Command('off')
eq(diagnosticsStarts,startsBeforeStatus,'off does not renew diagnostics')

-- Fresh module instances avoid the already cached successful frame. Inject a
-- native frame setup failure after creation to exercise orphan-frame cleanup.
local function freshProbe()
 local isolated=setmetatable({}, {__index=NS})
 assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/FocusAPIProbe.lua'))('MyForeverTargets',isolated)
 return isolated.FocusAPIProbe
end
local rootCreateFrame=CreateFrame
local failedFrame,setupCalls=nil,0
CreateFrame=function(kind,name,parent,template)
 local created=rootCreateFrame(kind,name,parent,template)
 if name=='MyForeverFocusAPIProbe' then
  setupCalls=setupCalls+1;failedFrame=created
  created.SetBackdrop=function() error('simulated native backdrop failure\nsimulated stack line') end
 end
 return created
end
local failingProbe=freshProbe()
loggedRejection(failingProbe,'cycle 1','setup_error','native setup exception')
local setupRejection=latest('FOCUS_API_PROBE_REJECT')
eq(setupRejection.stage,'style','setup exception identifies the failing native API stage')
eq(type(setupRejection.error)=='string',true,'setup exception retains a readable error summary')
eq(setupRejection.error:find('\n',1,true),nil,'setup exception does not log a multiline error')
eq(setupRejection.error:find('simulated stack line',1,true),nil,'setup exception does not retain the injected stack line')
eq(setupCalls,1,'setup exception is exercised after one native frame creation')
eq(failingProbe.setupFailed,true,'native setup exception requires a fresh reload')
eq(failedFrame.shown,false,'partially created native frame is hidden after setup exception')
eq(failedFrame.attrs['*macrotext2'],'/stopmacro','partially created native frame has only a noop')
eq(failedFrame.attrs['*unit2'],nil,'partially created native frame has no target unit action')
eq(messages[#messages]:lower():find('reload',1,true)~=nil,true,'setup exception explains how to recover')
loggedRejection(failingProbe,'cycle 1',nil,'retry after native setup exception')
eq(setupCalls,1,'failed setup cannot create more frames before reload')
eq(failingProbe.active,false,'failed setup retry cannot arm an action')
CreateFrame=rootCreateFrame

local normalSecureWrap=SecureHandlerWrapScript
SecureHandlerWrapScript=nil
local unavailableProbe=freshProbe()
loggedRejection(unavailableProbe,'cycle 1','secure_api_unavailable','missing native setup API')
eq(unavailableProbe.button,nil,'missing native setup API does not create a button')
SecureHandlerWrapScript=normalSecureWrap

local showFailedFrame=nil
CreateFrame=function(kind,name,parent,template)
 local created=rootCreateFrame(kind,name,parent,template)
 if name=='MyForeverFocusAPIProbe' then
  showFailedFrame=created
  created.Show=function(self) self.shown=true;error('simulated native show failure') end
 end
 return created
end
local showFailingProbe=freshProbe()
loggedRejection(showFailingProbe,'cycle 1','setup_error','native show exception')
eq(latest('FOCUS_API_PROBE_REJECT').stage,'show','show failure identifies its setup stage')
eq(showFailedFrame.shown,false,'show failure hides a frame that became visible before throwing')
eq(showFailedFrame.attrs['*macrotext2'],'/stopmacro','show failure clears the already configured target macro')
eq(showFailingProbe.setupFailed,true,'show failure also requires reload before retrying')
CreateFrame=rootCreateFrame

diagnosticsEnabled=false
eq(P.Command('cycle 1'),true,'successful request prepares after failure-regression cases')
local ready=latest('FOCUS_API_PROBE_READY')
eq(ready.requestID,latest('FOCUS_API_PROBE_COMMAND').requestID,'ready result correlates to its setup request')
eq(ready.version,NS.VERSION,'ready result identifies the loaded addon version')
eq(ready.stage,'ready','ready result records completed setup')
eq(ready.shown,true,'ready result records actual frame shown state')
eq(ready.visible,true,'ready result records actual frame visibility')
eq(P.Command('off'),true,'observable setup tests leave the probe off')
print('Focus API probe simulated checks: '..checks..' passed; no native secure action tested.')
