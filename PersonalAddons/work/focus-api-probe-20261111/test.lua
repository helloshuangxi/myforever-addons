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
CreateFrame=frame;UIParent=frame("Frame")
local wrapped,driver
SecureHandlerWrapScript=function(b,event,owner,script) wrapped=script end
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
local NS={}
assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/Core.lua'))('MyForeverTargets',NS)
local records={}
NS.Diagnostics={Record=function(kind,fields) records[#records+1]={kind=kind,fields=fields} end}
NS.Print=function() end
local r1,r2=frame("Button"),frame("Button")
r1.unit="nameplate1";r1.expectedGUID="Creature-A"
r2.unit="nameplate2";r2.expectedGUID="Creature-B"
NS.UI={enemy={tiles={r1,r2}}}
assert(loadfile('PersonalAddons/work/focus-api-probe-20261111/FocusAPIProbe.lua'))('MyForeverTargets',NS)
local P=NS.FocusAPIProbe
eq(P.button,nil,"module must create no frame while dormant")
eq(P.Command('native 1'),true,"native prepare")
local b=P.button
eq(b.scripts.OnClick,nativeClick,"preserve native OnClick")
eq(b.attrs['*type2'],'focus',"native focus type")
eq(b.attrs['*unit2'],'nameplate1',"native exact token")
eq(b.attrs.unit,nil,"no base unit")
eq(b.attrs.useOnKeyDown,false,"release click matches original tiles")
eq(driver,'[combat] hide; show',"combat hide driver")
eq(wrapped:find('[combat]',1,true)~=nil,true,"secure combat guard installed")
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
b.hooks.PreClick(b,'RightButton',false) -- secure wrapper handled native noop; no insecure writes here.
eq(records[#records].fields.prepared,false,"combat preclick refused")
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
print('Focus API probe simulated checks: '..checks..' passed; no native secure action tested.')
