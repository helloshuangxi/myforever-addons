-- Native-unit dispatch configuration and fail-closed observations only. The
-- client C++ may refuse every action below; this model does not prove support.
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local checks,combat,secure=0,false,false
local function eq(a,b,why) checks=checks+1;assert(a==b,why) end
local secret=setmetatable({},{__tostring=function()error("secret escaped")end})
issecretvalue=function(v)return rawequal(v,secret)end
InCombatLockdown=function()return combat end
SpellIsTargeting=function()return false end
CursorHasItem=function()return false end
local ctrl,guard,rejectCompare=false,true,false
IsControlKeyDown=function()return ctrl end
SecureCmdOptionParse=function()return guard and "ready" or nil end
GetActionInfo=function()return "spell",9 end
local A={marker=nil},B
B={}
local C={}
local units={nameplate1=A,nameplate2=B,target=B}
UnitExists=function(u)return units[u]~=nil end
UnitGUID=function()error("test requires no readable GUID")end
UnitName=function()error("no name fetch in action module")end
UnitCanAttack=function(_,u)return units[u]~=nil end
UnitIsUnit=function(a,b)
 if rejectCompare then return secret end
 return units[a]~=nil and units[a]==units[b]
end
GetRaidTargetIndex=function(u)return units[u] and units[u].marker end
SecureButton_GetModifiedUnit=function(f)return f.attrs.unit end
local apiHooks,apiHookCount={},0
for _,n in ipairs({"TargetUnit","FocusUnit","SetRaidTarget","CastSpellByName","CastSpellByID"})do _G[n]=function()end end
hooksecurefunc=function(n,f)apiHooks[n]=f;apiHookCount=apiHookCount+1 end
local frames,byName={},{}
local methods={}
local function mutation()assert(not combat or secure,"ordinary protected mutation in combat")end
local function frame(kind,name,parent,template)
 local f=setmetatable({kind=kind,name=name,parent=parent,template=template,attrs={},refs={},hooks={},wrap={},shown=true,bindings={}},{__index=methods})
 frames[#frames+1]=f;if name then assert(not byName[name],"duplicate frame name");byName[name]=f end;return f
end
for _,name in ipairs({"SetSize","SetPoint","SetAllPoints","SetFrameStrata","SetFrameLevel","RegisterForClicks","ClearAllPoints"}) do
 methods[name]=function()mutation()end
end
function methods:SetAttribute(k,v)mutation();self.attrs[k]=v end
function methods:GetAttribute(k)return self.attrs[k]end
function methods:SetFrameRef(k,v)mutation();self.refs[k]=v end
function methods:GetFrameRef(k)return self.refs[k]end
function methods:GetFrameLevel()return 1 end
function methods:CreateFontString()return frame("FontString")end
function methods:SetText(v)assert(not issecretvalue(v),"secret label text escaped into action UI");self.text=v end
function methods:Show()mutation();self.shown=true end
function methods:Hide()mutation();self.shown=false end
function methods:IsShown()return self.shown end
function methods:IsVisible()return self.shown and (not self.parent or self.parent:IsVisible())end
function methods:HookScript(k,f)self.hooks[k]=f end
function methods:ClearBindings()self.bindings={}end
function methods:SetBindingClick(_,key,name)self.bindings[key]=name end
newtable=function(...)return {...}end
local function run(body,self,control,newstate)
 secure=true
 local fn=assert(loadstring("return function(self,control,newstate) "..body.." end"))()
 local ok,err=pcall(fn,self,control,newstate);secure=false;assert(ok,err)
end
function methods:RunAttribute(name)return run(self.attrs[name],self,self)end
SecureHandlerWrapScript=function(f,kind,owner,body)f.wrap[kind]={owner=owner,body=body}end
RegisterStateDriver=function(f,key,body)mutation();f.driver=body end
ClearOverrideBindings=function(owner)mutation();owner:ClearBindings()end
CreateFrame=frame;UIParent=frame("Frame")
local timers={};C_Timer={After=function(_,fn)timers[#timers+1]=fn end}
local NS={};assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
local records,messages={},{}
NS.Print=function(s)messages[#messages+1]=s end
local logEnabled=false
NS.Diagnostics={Enabled=function()return logEnabled end,Start=function()logEnabled=true end,
 Record=function(k,f)records[#records+1]={kind=k,fields=f};return true end}
local row=frame("Button");row.side="enemy";row.attrs["combat-prepared"]=false;row.attrs["mfch-ready"]=false
local panel=frame("Frame");row.parent=panel;NS.UI={enemy={frame=panel,tiles={row},limit=5}}
local epoch=1
local originalEntry={unit="nameplate1",restrictedIdentity=true,tokenEpoch=epoch}
NS.EnemyDisplay={Get=function(i)return i==1 and originalEntry or nil end,
 IsCurrent=function(e)return e.tokenEpoch==epoch end,
 RestrictedEntry=function(u)
  if units[u] then return {unit=u,restrictedIdentity=true,tokenEpoch=epoch}end
 end}
NS.ReadUnit=function()return nil end
local source=frame("Button")
NS.NearbyCast={owner=frame("Frame"),DiscoverActions=function()
 return {{actionKind="spell",spell="测试伤害技能",spellID=9,slot=1,keys={"Z"},useOnKeyDown=false,source=source},
 {actionKind="macro",spellID=10,slot=2,keys={"X"}}}
end}
NS.CombatCast={owner=frame("Frame")};NS.CombatHover={owner=frame("Frame")}
local refreshes=0;NS.RequestRefresh=function()refreshes=refreshes+1 end
NS.RefreshTiles=function()end
local initial=#frames
assert(loadfile(root.."InstanceActions.lua"))("MyForeverTargets",NS)
local P=NS.InstanceActions
eq(#frames,initial,"default load never creates action frames")
eq(apiHookCount,0,"default load never hooks action APIs")
eq(P.Enabled(),nil,"default is off")
eq(P.VisualEntry(row),false,"default does not override accepted rendering")
eq(P.Command("status"),nil,"status does not activate")
eq(#frames,initial,"status does not create frames")
combat=true
eq(P.On(),false,"cannot prepare native actions during combat")
eq(#frames,initial,"combat command creates nothing")
combat=false
NS.NativeScaleProbe={Status=function()return {active=true}end}
eq(P.On(),false,"other native experiments remain mutually exclusive despite nil module holes")
NS.NativeScaleProbe=nil
row.attrs["combat-prepared"]=true
eq(P.On(),false,"cannot overlay a pre-existing armed row")
row.attrs["combat-prepared"]=false
row.attrs.unit="nameplate2"
eq(P.On(),false,"native and ordinary empty state must both be empty")
row.attrs.unit=nil
eq(P.On(),true,"explicit on prepares the four native action routes")
eq(logEnabled,true,"explicit experiment starts bounded existing diagnostics")
eq(apiHookCount,5,"native API observers install once and only on explicit use")
eq(P.Enabled(),true,"owner explicitly enabled")
local s=P.rows[1];local overlay=s.overlay
local owned,e=P.VisualEntry(row)
eq(owned,true,"original visual cell is owned while enabled")
eq(e.unit,"nameplate1","visual entry retains exact native unit address")
eq(e.guid,nil,"no synthetic GUID")
eq(row.unit,nil,"underlying production secure unit remains untouched")
eq(row.expectedGUID,nil,"production GUID remains untouched")
eq(overlay.attrs.unit,"nameplate1","native unit not a name/GUID guess")
eq(overlay.attrs["*type1"],"target","left target uses native action")
eq(overlay.attrs["*type2"],"focus","right focus uses native action")
eq(overlay.attrs["ctrl-type2"],"click","ctrl-right opens native prepared palette")
eq(overlay.attrs["keys"],1,"only the plain spell is prepared")
eq(#s.proxies,1,"macros are never converted")
local proxy=s.proxies[1]
eq(overlay.template:find("SecureUnitButtonTemplate",1,true),nil,"click-cast configuration cannot replace explicit grid interactions")
eq(proxy.attrs.unit,"nameplate1","spell proxy owns explicit native unit")
eq(proxy.attrs.spell,"测试伤害技能","spell action uses the discovered plain skill")
eq(proxy.attrs.guard,"[@nameplate1,exists,harm,nodead] ready","spell guard names only its own unit")
local function wrapped(f,event,motion)
 if motion==false then return end
 local w=f.wrap[event];if w then run(w.body,f,w.owner)end
end
local function last(kind)
 for i=#records,1,-1 do if records[i].kind==kind then return records[i].fields end end
end
local function click(f,mouse,accepted)
 wrapped(f,"PreClick")
 if f.hooks.PreClick then f.hooks.PreClick(f,mouse,false)end
 local action=mouse=="RightButton" and f.attrs["*type2"] or f.attrs["*type1"] or f.attrs.type
 if ctrl and mouse=="RightButton" then action=f.attrs["ctrl-type2"]end
 local u=f.attrs.unit
 if action=="target" then apiHooks.TargetUnit(u)
 elseif action=="focus" then apiHooks.FocusUnit(u)
 elseif action=="raidtarget" then apiHooks.SetRaidTarget(u,f.attrs.marker)
 elseif action=="spell" then apiHooks.CastSpellByName(f.attrs.spell,u)end
 if accepted then
  if action=="target" then units.target=units[u]
  elseif action=="focus" then units.focus=units[u]
  elseif action=="raidtarget" and f.attrs.action=="set" then units[u].marker=f.attrs.marker
  elseif action=="click" then local opener=f.attrs["ctrl-clickbutton2"];run(opener.attrs._onclick,opener,opener)
  elseif action=="spell" then _G.modelCast={unit=u,spell=f.attrs.spell}end
 end
 if f.hooks.PostClick then f.hooks.PostClick(f,mouse,false)end
end
-- Rejected calls are observed as rejected/unmatched, not fabricated successes.
click(overlay,"LeftButton",false)
eq(units.target,B,"native rejection leaves the other selected target intact")
eq(last("INSTANCE_ACTION_POST").targetMatches,false,"rejected target action is not reported matched")
eq(last("INSTANCE_ACTION_POST").targetChangedToGoal,false,"dispatch alone is not a successful change")
eq(last("INSTANCE_ACTION_API").api,"TargetUnit","native handler call distinguished from an input click")
eq(last("INSTANCE_ACTION_API").effectProven,false,"called-but-refused action is never success")
click(overlay,"LeftButton",true)
eq(units.target,A,"model native target uses this exact unit")
eq(last("INSTANCE_ACTION_POST").targetChangedToGoal,true,"public UnitIsUnit can verify native result")
click(overlay,"RightButton",false)
eq(last("INSTANCE_ACTION_POST").focusMatches,false,"failed focus never reported succeeded")
click(overlay,"RightButton",true)
eq(units.focus,A,"model native focus uses exact unit")
eq(last("INSTANCE_ACTION_POST").focusChangedToGoal,true,"focus readback distinguishes a change")
ctrl=true;click(overlay,"RightButton",true);ctrl=false
eq(s.palette.shown,true,"ctrl-right native click opens this row's palette")
local marker
for _,f in ipairs(frames)do if f.parent==s.palette and f.attrs.marker==8 then marker=f end end
assert(marker)
eq(marker.attrs.unit,"nameplate1","marker keeps explicit unit instead of current target")
eq(marker.attrs.action,"set","native raidtarget requires the action name and a separate marker attribute")
click(marker,"LeftButton",false)
eq(last("INSTANCE_ACTION_POST").markerMatches,"[unknown]","missing marker readback remains unknown")
click(marker,"LeftButton",true)
eq(A.marker,8,"model marker affects only prepared unit")
eq(last("INSTANCE_ACTION_POST").markerMatches,true,"public marker index independently confirms result")
-- Existing controllers are retired only by the explicit overlay's secure Enter.
NS.CombatCast.owner.attrs["combat-hover-index"]=7
NS.CombatHover.owner.attrs["mfch-hover"]=8
wrapped(overlay,"OnEnter")
eq(P.owner.bindings.Z,proxy.name,"hover owns only temporary binding")
eq(NS.CombatCast.owner.attrs["combat-hover-index"],nil,"name owner cannot silently rearm on combat state")
eq(NS.CombatHover.owner.attrs["mfch-hover"],nil,"fixed owner cannot silently rearm on combat state")
units.target=B;guard=false;_G.modelCast=nil
click(proxy,"LeftButton",true)
eq(proxy.attrs.type,nil,"unsupported native macro condition is a no-op")
eq(_G.modelCast,nil,"failed guard never attacks original target")
eq(units.target,B,"failed spell guard never changes selected target")
eq(last("INSTANCE_ACTION_POST").reason,"native_macro_condition_rejected","quiet failure has an exact reason")
guard=true;click(proxy,"LeftButton",true)
eq(_G.modelCast.unit,"nameplate1","model direct native spell never substitutes current target")
eq(units.target,B,"direct native spell preserves selected other target")
eq(last("INSTANCE_ACTION_POST").recipientProven,false,"dispatch is not recipient proof")
local actionInfo=GetActionInfo;GetActionInfo=function()return "spell",55 end
_G.modelCast=nil;click(proxy,"LeftButton",true)
eq(_G.modelCast,nil,"changed source skill not cast via stale key")
eq(last("INSTANCE_ACTION_POST").reason,"action_changed","source changes explicitly recorded")
GetActionInfo=actionInfo
panel:Hide();_G.modelCast=nil
click(proxy,"LeftButton",true)
eq(_G.modelCast,nil,"hidden panel cannot cast through a stale proxy")
eq(last("INSTANCE_ACTION_POST").reason,"native_macro_condition_rejected","native visibility guard blocks hidden host")
wrapped(overlay,"OnHide")
eq(next(P.owner.bindings),nil,"hiding the overlay releases temporary keys")
eq(s.palette.shown,false,"hiding the overlay closes its detached palette")
panel:Show();wrapped(overlay,"OnEnter")
rejectCompare=true;click(overlay,"LeftButton",false)
eq(last("INSTANCE_ACTION_POST").targetMatches,"[unknown]","restricted comparison is not false or a match")
rejectCompare=false
units.nameplate1=nil;click(overlay,"LeftButton",true)
eq(overlay.attrs["*type1"],nil,"removed unit cannot fall through nil unit targeting")
eq(last("INSTANCE_ACTION_POST").allowed,false,"unavailable reference is blocked")
units.nameplate1=C;epoch=2
local liveOwned,live=P.VisualEntry(row)
eq(liveOwned,true,"native cell cannot be reused by an unrelated roster entry")
eq(live.unit,"nameplate1","live native address retained after lifecycle change")
eq(live.tokenEpoch,2,"fresh visual lifecycle, no old-GUID promise")
wrapped(overlay,"OnLeave",true)
eq(next(P.owner.bindings),nil,"real Leave hands back temporary keys")
wrapped(overlay,"OnEnter")
combat=true
run(P.owner.attrs["_onstate-combat"],P.owner,P.owner,"combat")
eq(P.Enabled(),false,"native combat state suspends the experiment without ordinary writes")
eq(next(P.owner.bindings),nil,"native suspension clears spell bindings")
eq(overlay.shown,false,"combat suspension hides input layer")
eq(s.palette.shown,false,"combat suspension hides marker palette")
eq(P.stop.shown,false,"native stop button does not remain after suspension")
click(proxy,"LeftButton",true)
eq(proxy.attrs.type,nil,"combat cannot perform experiment spell even via stale direct click")
combat=false;P.OnEvent("PLAYER_REGEN_ENABLED")
eq(#P.rows,0,"OOC cleanup drops experiment references")
eq(P.VisualEntry(row),false,"default rendering and input restored")
originalEntry.tokenEpoch=epoch
eq(P.On(),true,"a new explicit activation can rebuild after suspension")
eq(apiHookCount,5,"reopening does not accumulate API hooks")
wrapped(P.rows[1].overlay,"OnEnter")
run(P.stop.attrs._onclick,P.stop,P.stop)
eq(P.Enabled(),false,"native stop button disables the experiment")
eq(next(P.owner.bindings),nil,"native stop returns temporary keys immediately")
eq(P.rows[1].overlay.shown,false,"native stop hides all experimental input")
P.Off()
for _,fn in ipairs(timers)do fn()end
-- Raw identity APIs throw in this fixture; the action module never needed them.
local secretFree,identityFree=true,true
for _,r in ipairs(records)do
 for k,v in pairs(r.fields)do
  if rawequal(v,secret)then secretFree=false end
  if k=="name" or k=="guid" or k=="macroBody"then identityFree=false end
 end
end
eq(secretFree,true,"all observed fields remain free of raw secrets")
eq(identityFree,true,"entire action history excludes raw identity and macro fields")
print("Targets instance native action simulated checks: "..checks.."; real native actions remain UNVERIFIED")
