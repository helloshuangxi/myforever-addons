-- Protected-frame model only. The client must still verify native mouseover.
local checks,combat,secure=0,false,false
local protectedWrites,driverWrites=0,0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local secret={}
issecretvalue=function(value) return rawequal(value,secret) end
InCombatLockdown=function() return combat end
local methods={}
local builtinClick=function() end
local function guard(frame,operation)
    if frame.protected then
        if combat and not secure then error("protected "..operation.." in combat") end
        if not secure then protectedWrites=protectedWrites+1 end
    end
end
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",attrs={},scripts={},
        shown=true,level=1,protected=template and template:find("Secure",1,true)~=nil or false}, {__index=methods})
    if template and template:find("SecureUnitButtonTemplate",1,true) then f.scripts.OnClick=builtinClick end
    return f
end
CreateFrame=frame
function methods:GetName() return self.name end
function methods:GetFrameLevel() return self.level end
function methods:GetFrameStrata() return self.strata or "MEDIUM" end
function methods:IsProtected() return self.protected end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:GetScript(key) return self.scripts[key] end
function methods:SetScript(key,callback)
    if key=="OnClick" and self.template:find("SecureUnitButtonTemplate",1,true) then error("native OnClick replaced") end
    self.scripts[key]=callback
end
function methods:HookScript(key,callback)
    self.hooks=self.hooks or {}
    local prior=self.hooks[key]
    self.hooks[key]=prior and function(...) prior(...);callback(...) end or callback
end
function methods:SetAttribute(key,value) guard(self,"SetAttribute");self.attrs[key]=value end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetSize(w,h) guard(self,"SetSize");self.width,self.height=w,h end
function methods:SetWidth(value) guard(self,"SetWidth");self.width=value end
function methods:SetHeight(value) guard(self,"SetHeight");self.height=value end
function methods:SetPoint(...) guard(self,"SetPoint");self.point={...} end
function methods:ClearAllPoints() guard(self,"ClearAllPoints");self.point=nil end
function methods:SetAllPoints(other) guard(self,"SetAllPoints");self.anchor=other end
function methods:SetFrameLevel(value) guard(self,"SetFrameLevel");self.level=value end
function methods:SetFrameStrata(value) guard(self,"SetFrameStrata");self.strata=value end
function methods:EnableMouse(value) guard(self,"EnableMouse");self.mouse=value end
function methods:EnableMouseWheel(value) guard(self,"EnableMouseWheel");self.wheel=value end
function methods:RegisterForClicks(...) guard(self,"RegisterForClicks");self.clicks={...} end
function methods:Show() guard(self,"Show");self.shown=true end
function methods:Hide()
    guard(self,"Hide")
    local was=self.shown;self.shown=false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:CreateTexture() return frame("Texture",nil,self) end
function methods:CreateFontString() return frame("FontString",nil,self) end
function methods:SetTexture(value) self.texture=value end
function methods:SetVertexColor(...) self.color={...} end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF",12,"" end
function methods:SetFont(...) self.font={...} end
function methods:SetWordWrap(value) self.wrap=value end
function methods:SetJustifyH(value) self.justify=value end
function methods:SetTextColor(...) self.color={...} end
function methods:SetStatusBarTexture(value) self.statusTexture=value end
function methods:SetOrientation(value) self.orientation=value end
function methods:SetMinMaxValues(low,high) self.minimum,self.maximum=low,high end
function methods:SetValue(value) self.value=value end
function methods:SetStatusBarColor(...) self.statusColor={...} end

UIParent=frame("Frame","UIParent")
GameTooltip=frame("GameTooltip","GameTooltip",UIParent)
local tooltipResult,tooltipThrows=true,false
local operations,lines={},{}
function methods:SetOwner(owner) self.owner=owner;operations[#operations+1]="SetOwner" end
function methods:GetOwner() return self.owner end
function methods:SetUnit(unit)
    operations[#operations+1]="SetUnit";self.unit=unit
    if tooltipThrows then error("restricted tooltip") end
    return tooltipResult
end
function methods:SetText(value)
    if self==GameTooltip then operations[#operations+1]="SetText" end
    self.title=value
end
function methods:AddLine(value) operations[#operations+1]="AddLine";lines[#lines+1]=value end
local function resetTooltip() operations,lines={},{} end
local function operated(name) for _,value in ipairs(operations) do if value==name then return true end end return false end

local units={nameplate1="enemy-a",nameplate1target="friend-a",mouseover="enemy-z",target="selected-enemy"}
UnitGUID=function(unit) return units[unit] end
local friendly,dead=true,false
local macroMatch=true
SecureCmdOptionParse=function(condition)
    eq(condition,"[@mouseover,help,nodead] MFT_ENEMY_TARGET","status uses friendly native macro conditions")
    return macroMatch and "MFT_ENEMY_TARGET" or nil
end
local drivers={}
local registrationThrows=false
RegisterStateDriver=function(button,key,condition)
    guard(button,"RegisterStateDriver");driverWrites=driverWrites+1
    if registrationThrows then error("driver unavailable") end
    drivers[button]={key=key,condition=condition}
end
UnregisterStateDriver=function(button,key)
    guard(button,"UnregisterStateDriver");driverWrites=driverWrites+1
    drivers[button]=nil
end
local function runDrivers()
    secure=true
    for button,driver in pairs(drivers) do
        local eligible=units[button.unit] and (driver.condition:find(",exists]",1,true) or friendly and not dead)
        if eligible then button:Show() else button:Hide() end
    end
    secure=false
end
local forbiddenWrites=0
for _,name in ipairs({"TargetUnit","FocusUnit","ClearTarget","CastSpellByName","RunMacroText","SetRaidTarget","SetBinding","SetOverrideBindingClick"}) do
    _G[name]=function() forbiddenWrites=forbiddenWrites+1;error("unexpected action "..name) end
end

local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.LegacyNameBridge=false -- Keep the original native-only lifecycle as a regression fixture.
NS.DB={shown=true}
local clickSetup={}
NS.SetupClickActions=function(button)
    clickSetup[#clickSetup+1]=button
    eq(button:GetScript("OnClick"),builtinClick,"shared click setup receives the native child handler")
    -- UI integration tests execute the real setup and all secure menu snippets.
    button:SetAttribute("*type2","focus")
    button:SetAttribute("ctrl-type2","click")
end
assert(loadfile(root.."EnemyTargetHover.lua"))("MyForeverTargets",NS)
local H=NS.EnemyTargetHover
local logged,enabled,session={},true,1
NS.Diagnostics={Enabled=function() return enabled end,Session=function() return session end,
    Record=function(kind,data) logged[#logged+1]={kind=kind,data=data};return true end}
local panel=frame("Frame","EnemyPanel",UIParent)
local row=frame("Button","EnemyOne",panel,"SecureActionButtonTemplate")
row.side,row.unit,row.expectedGUID="enemy","nameplate1","enemy-a"
row.data={guid="enemy-a"}
row.hover=frame("Texture",nil,row)
local clearedParentHover=0
NS.SetHoverUnit=function(unit) eq(unit,nil,"child entry only clears the parent's world indicator");clearedParentHover=clearedParentHover+1 end
local data={state="known",guid="friend-a",name="治疗者",className="牧师",player=true,
    assist=true,dead=false,health=.5,healthCurrent=50,healthMax=100,healthAvailable=true}
row.enemyTarget=data
local unrelatedHover={}
NS.HoveredTile=unrelatedHover
eq(H.Create({side="friendly"}),nil,"friendly main tiles get no enemy target child")
local child=H.Create(row)
eq(H.Create(row),child,"Create is idempotent")
eq(child:GetScript("OnClick"),builtinClick,"native click handler remains unchanged")
eq(child:GetAttribute("*type1"),"target","explicit left click selects the friendly target")
eq(clickSetup[1],child,"child delegates focus and marking setup to the shared UI helper")
eq(#clickSetup,1,"idempotent Create installs shared click actions once")
eq(child:GetAttribute("*type2"),"focus","child receives the native focus action")
eq(child:GetAttribute("ctrl-type2"),"click","child receives the Ctrl-right marker action")
eq(child:GetAttribute("useparent*"),false,"child does not inherit enemy click actions")
eq(child.width,76,"target rectangle matches the enemy width")
eq(child.height,26,"small target card has only two text rows")
eq(child.point[3],"BOTTOMLEFT","target rectangle anchors below the square")
eq(child.point[4],0,"target rectangle aligns with its owner")
eq(child.point[5],-1,"target rectangle leaves a one pixel gap")
eq(child:GetFrameLevel(),row:GetFrameLevel()+4,"native hit region sits above the target text")
local display=row.enemyTargetDisplay
eq(display.parent,row,"display follows its owner's visibility and scale")
eq(display.mouse,false,"display never intercepts the native unit button")
eq(display.labels.mouse,false,"labels never intercept native hover")
eq(display.health.mouse,false,"health bar never intercepts native hover")
eq(display.width,child.width,"display and hit region cover the same width")
eq(display.height,child.height,"display and hit region cover the same height")
eq(child.shield.parent,UIParent,"small shield has an independent unprotected owner")
eq(child.shield:IsProtected(),false,"small shield remains unprotected")
eq(child.shield:GetFrameLevel(),row:GetFrameLevel()+5,"small shield covers only the target child")
eq(H.Bind(row),true,"out-of-combat binding succeeds")
eq(child:GetAttribute("unit"),"nameplate1target","child has a fixed relationship unit")
eq(drivers[child].key,"visibility","friendly gate uses the native visibility driver")
eq(drivers[child].condition,"[@nameplate1target,help,nodead] show; hide","driver is help/nodead gated")
local oldDriverWrites=driverWrites
eq(H.Bind(row),true,"same binding remains usable")
eq(driverWrites,oldDriverWrites,"same owner and relation do not rewrite driver")
runDrivers();H.Refresh(row,data)
eq(child:GetAttribute("mark-unit"),"nameplate1target","child marker retains the controlled relation token")
eq(child:GetAttribute("mark-guid"),"friend-a","child marker freezes its target identity outside combat")
eq(child:GetAttribute("mark-owner-guid"),"enemy-a","child marker freezes its owner identity outside combat")
eq(child:GetAttribute("target-side"),"friendly","child marker binds its own relation rather than the parent enemy side")
eq(display:IsShown(),true,"valid enemy displays its separate target card")
eq(display.nameText.title,"治疗者","rectangle displays target name")
eq(display.classText.title,"牧师","rectangle displays target class")
eq(display.healthText.title,"50%","rectangle displays target health percentage")
eq(display.health.value,50,"health fill uses target current health")
eq(display.health.maximum,100,"health fill uses target maximum health")
eq(child.shield:IsShown(),false,"valid friendly target removes the supplemental shield")
eq(NS.HoveredEnemyTarget,nil,"refresh never fakes mouse entry")
do
    local originalTarget=units.target
    units.focus,units.target="friend-a","friend-a"
    combat=true
    local writes=protectedWrites
    H.Refresh(row,data)
    eq(display.focused,true,"target rectangle shows its own focus identity")
    eq(display.selected,true,"target rectangle also highlights current target")
    for i=1,4 do
        eq(display.focusEdges[i]:IsShown(),true,"child outer gold focus edge is visible")
        eq(display.targetEdges[i]:IsShown(),true,"child inner red target edge is simultaneously visible")
    end
    eq(display.focusEdges[1].point[4],0,"child gold border remains at rectangle boundary")
    eq(display.targetEdges[1].point[4],-2,"child red border is inset from its right edge")
    eq(display.nameText.point[2],4,"target name stays inside the dual border")
    eq(display.classText.point[2],4,"target class stays inside the left dual border")
    eq(display.healthText.point[2],-4,"target health stays inside the dual border")
    eq(child.hoverFill.anchor,nil,"child hover fill does not cover the outline")
    eq(display.width,76,"dual child border leaves rectangle width unchanged")
    eq(display.height,26,"dual child border leaves small rectangle height unchanged")
    units.focus,units.target=secret,secret;H.Refresh(row,data)
    eq(display.focused,false,"secret child focus identity fails closed")
    eq(display.selected,false,"secret child current-target identity fails closed")
    units.focus,units.target="friend-b","friend-b";H.Refresh(row,data)
    eq(display.focused,false,"a different unit never highlights the child focus")
    units.focus,units.target=nil,nil;H.Refresh(row,data)
    for i=1,4 do
        eq(display.focusEdges[i]:IsShown(),false,"cleared child focus hides every yellow edge")
        eq(display.targetEdges[i]:IsShown(),false,"cleared child target hides every red edge")
    end
    eq(protectedWrites,writes,"combat identity visuals never write protected frame state")
    units.target=originalTarget;combat=false
end

resetTooltip();child:GetScript("OnEnter")(child)
eq(NS.HoveredEnemyTarget,child,"real enter records the child hover")
eq(NS.HoveredTile,unrelatedHover,"child never replaces parent tile hover")
eq(GameTooltip:GetOwner(),child,"tooltip belongs to the child")
eq(GameTooltip.unit,"nameplate1target","tooltip preserves the relation unit")
eq(operated("SetUnit"),true,"native unit tooltip is used")
eq(operated("SetText"),false,"successful SetUnit is not overwritten with text")
eq(child.status.identityMatches,false,"different native mouseover does not confirm the child")
eq(child.status.conditionMatched,false,"mismatched identity cannot confirm friendly conditions")
eq(#logged,1,"initial hovered status is logged")
eq(logged[1].kind,"ENEMY_TARGET_MOUSEOVER","separate read-only diagnostic kind")
eq(child.status.currentTargetGUID,"selected-enemy","status observes the player's existing target")
eq(logged[1].data.currentTargetGUID,"selected-enemy","diagnostics records the current target without changing it")
H.Refresh(row,data)
eq(#logged,1,"unchanged native status is not spammed")
units.mouseover="friend-a"
H.Refresh(row,data)
eq(child.status.identityMatches,true,"actual matching native mouseover confirms identity")
eq(child.status.conditionMatched,true,"matching native friendly condition is recorded")
eq(#logged,2,"status transition is logged")
macroMatch=false;H.Refresh(row,data)
eq(child.status.conditionMatched,false,"identity alone does not confirm the macro condition")
macroMatch=true

combat=true
local beforeProtected,beforeDriver=protectedWrites,driverWrites
eq(H.Bind(row),false,"combat Bind refuses protected changes")
units.nameplate1target,units.mouseover="friend-b","friend-b"
data={state="known",guid="friend-b",name="新的友方",assist=true,dead=false};row.enemyTarget=data
resetTooltip();H.Refresh(row,data)
eq(child:GetAttribute("unit"),"nameplate1target","target change retains the original relationship binding")
eq(child:GetAttribute("mark-guid"),"friend-a","combat relationship changes cannot rewrite the prepared marker GUID")
eq(child.status.expectedGUID,"friend-b","hover status follows the current relationship target")
eq(GameTooltip.unit,"nameplate1target","changed target refreshes native unit tooltip")
eq(operated("SetText"),false,"combat target change retains native payload")
eq(protectedWrites,beforeProtected,"combat Refresh performs no protected writes")
eq(driverWrites,beforeDriver,"combat target change does not replace the driver")
eq(#logged>2,true,"target change records a new status")

data.assist=false;friendly=false
H.Refresh(row,data);runDrivers()
eq(display:IsShown(),true,"hostile target stays visible without a friendly hit region")
eq(child.shield:IsShown(),false,"hidden hostile child releases the parent row click region")
eq(child:IsShown(),false,"secure driver hides non-friendly relationships")
eq(NS.HoveredEnemyTarget,nil,"invalid target clears child hover")
eq(child.status,nil,"invalid target clears status confirmation")
eq(GameTooltip:IsShown(),false,"owned tooltip is cleared")
friendly=true;data.assist=true;data.dead=true;dead=true
H.Refresh(row,data);runDrivers()
eq(display:IsShown(),true,"dead target remains readable")
eq(display.healthText.title,"死亡","dead target has a clear status")
eq(child.shield:IsShown(),false,"hidden dead child leaves the parent row clickable")
eq(child:IsShown(),false,"driver hides dead target")
data.dead=false;dead=false
units.nameplate1target=nil;H.Refresh(row,{state="absent"});runDrivers()
eq(display.nameText.title,"目标 —","missing target clears the previous name")
eq(display.classText.title,"","missing target clears the previous class")
eq(display.healthText.title,"—","missing health never claims zero health")
eq(display.health:IsShown(),false,"missing target hides old health fill")
eq(child.shield:IsShown(),false,"hidden absent child does not retain an input shield")
units.nameplate1target="friend-b";runDrivers()
units.nameplate1="enemy-reused";H.Refresh(row,data)
eq(display:IsShown(),false,"reused enemy owner hides stale target card")
eq(child.shield:IsShown(),true,"reused owner blocks a still-friendly new victim")
eq(child:GetAttribute("unit"),"nameplate1target","owner invalidation does not mutate protected binding in combat")
units.nameplate1="enemy-a"
data.guid=secret;H.Refresh(row,data)
eq(child.shield:IsShown(),true,"secret victim identity stays blocked")
data.guid="friend-b";data.assist=secret;H.Refresh(row,data)
eq(child.shield:IsShown(),true,"secret friend relation stays blocked")
data.assist=true;data.dead=nil;H.Refresh(row,data)
eq(child.shield:IsShown(),true,"unknown death state stays blocked")
data.dead=false
data.healthCurrent,data.healthMax,data.healthAvailable=secret,secret,true
data.health=nil
eq(pcall(H.Refresh,row,data),true,"secret health reaches native sinks without formatting")
eq(display.health.value,secret,"secret current health reaches native StatusBar")
eq(display.health.maximum,secret,"secret maximum health reaches native StatusBar")
eq(display.healthText.title,"—","unreadable percentage has an honest placeholder")
eq(protectedWrites,beforeProtected,"all combat invalidation paths avoid protected writes")

NS.DB.shown=false;H.Refresh(row,data)
eq(display:IsShown(),false,"hidden addon clears the display")
eq(child.shield:IsShown(),false,"hidden addon never leaves the independent shield on screen")
NS.DB.shown=true
combat=false;panel:Hide();H.Refresh(row,data)
eq(child.shield:IsShown(),false,"hidden parent panel never leaves its shield")
panel:Show();row:Hide();H.Refresh(row,data)
eq(display:IsShown(),false,"hidden owner clears the display")
eq(child.shield:IsShown(),false,"hidden tile never leaves its shield")
row:Show();H.Refresh(row,data);runDrivers()
eq(child:GetAttribute("mark-guid"),"friend-b","out-of-combat refresh updates marker GUID without rebinding the owner")
NS.HoveredTile=row
child:GetScript("OnEnter")(child)
eq(NS.HoveredTile,nil,"child entry clears only its own parent tile hover")
eq(clearedParentHover,1,"child entry clears the parent world indicator once")
eq(row.hover:IsShown(),false,"child entry removes the parent tile hover highlight")
child:GetScript("OnLeave")(child)

tooltipResult=false;resetTooltip();child:GetScript("OnEnter")(child)
eq(child.unitTooltipReady,false,"failed native tooltip is explicitly unconfirmed")
eq(operated("SetText"),true,"failed SetUnit may show an unconfirmed text explanation")
child:GetScript("OnLeave")(child)
tooltipResult=true;tooltipThrows=true
eq(pcall(child:GetScript("OnEnter"),child),true,"SetUnit errors are contained")
eq(child.unitTooltipReady,false,"SetUnit errors do not claim a native tooltip")
tooltipThrows=false;child:GetScript("OnLeave")(child)
resetTooltip();child:GetScript("OnEnter")(child)
local other=frame("Button","OtherOwner",UIParent)
GameTooltip:SetOwner(other);GameTooltip:Show();H.Clear()
eq(GameTooltip:IsShown(),true,"Clear never hides another owner's tooltip")
eq(NS.HoveredEnemyTarget,nil,"Clear releases only this module's active hover")

enabled=false;units.mouseover="other";H.Refresh(row,data);child:GetScript("OnEnter")(child)
local oldLogs=#logged
units.mouseover="friend-b";H.Refresh(row,data)
eq(#logged,oldLogs,"disabled diagnostics records nothing")
enabled=true;session=2;H.Refresh(row,data)
eq(#logged,oldLogs+1,"new log session captures current hover status")
child.shield:GetScript("OnEnter")()
eq(NS.HoveredEnemyTarget,nil,"shield entry clears active child hover")

units.nameplate1="enemy-new";row.expectedGUID="enemy-new"
eq(H.Bind(row),true,"fresh out-of-combat owner identity can be rebound")
eq(child.bindingOwnerGUID,"enemy-new","new binding stores fresh owner identity")
yes(driverWrites>beforeDriver,"owner identity change replaces the state driver")
row.unit=nil
eq(H.Bind(row),false,"missing row unit clears the child binding")
eq(child:GetAttribute("unit"),nil,"missing owner clears protected unit out of combat")
eq(child:GetAttribute("mark-guid"),nil,"missing owner clears marker GUID out of combat")
eq(child:GetAttribute("mark-owner-guid"),nil,"missing owner clears marker owner snapshot out of combat")
eq(drivers[child],nil,"missing owner unregisters visibility driver")
eq(child:IsShown(),false,"missing owner hides protected child out of combat")
row.unit="nameplate1";registrationThrows=true
eq(H.Bind(row),false,"registration error fails closed")
eq(child:GetAttribute("unit"),nil,"registration error clears protected unit")
eq(child.bindingReady,false,"registration error does not claim binding success")
eq(child:IsShown(),false,"registration error leaves child hidden")
eq(forbiddenWrites,0,"module never performs targeting, casting, marking or binding actions")
eq(units.target,"selected-enemy","all hover and cleanup paths preserve the player's current target")

-- The newly authorized ordinary-skill bridge covers the full target rectangle
-- for either relation, without changing its protected unit in combat.
NS.LegacyNameBridge=true
NS.DB.legacyNameBridgeEnabled=true
registrationThrows=false
units.nameplate2,units.nameplate2target="enemy-owner-two","enemy-victim"
local fresh={state="known",guid="enemy-victim",name="野猪",targetName="野猪",player=false,
    assist=false,harm=true,dead=false,offline=false,health=.7,healthCurrent=70,healthMax=100,healthAvailable=true}
local owner=frame("Button","EnemyTwo",panel,"SecureActionButtonTemplate")
owner.side,owner.unit,owner.expectedGUID="enemy","nameplate2","enemy-owner-two"
owner.data={guid=owner.expectedGUID};owner.enemyTarget=fresh
NS.ReadEnemyTarget=function(unit,expected)
    eq(unit,owner.unit,"child snapshot rereads only its owning enemy relation")
    eq(expected,owner.expectedGUID,"child snapshot carries the owner's expected identity")
    return fresh
end
local installs,leaves,enters=0,0,0
local Cast={count=0}
local bridgeReason
NS.NearbyCast=Cast
function Cast.Status(button)
    return {reason=bridgeReason,count=Cast.row==button and Cast.count or 0}
end
function Cast.Leave(button)
    leaves=leaves+1
    if Cast.row==button then Cast.row=nil;Cast.count=0 end
end
function Cast.Enter(button)
    enters=enters+1
    eq(NS.HoveredEnemyTarget,button,"native entry sets child hover before bridge hook")
    local snapshot=NS.ReadBridgeTarget(button)
    if snapshot then Cast.row=button;Cast.count=2 end
end
function Cast.Install(button)
    installs=installs+1
    button:HookScript("OnEnter",function(self) Cast.Enter(self) end)
    button:HookScript("OnLeave",function(self) Cast.Leave(self) end)
    button:HookScript("OnHide",function(self) Cast.Leave(self) end)
    return true
end
assert(loadfile(root.."EnemyTargetHover.lua"))("MyForeverTargets",NS)
H=NS.EnemyTargetHover
local card=H.Create(owner)
eq(installs,1,"legacy mode installs the bridge on the child once")
eq(card.bridgeTarget,true,"child is explicitly identified as a controlled relationship target")
H.Create(owner);eq(installs,1,"repeated create does not duplicate bridge hooks")
H.Bind(owner);runDrivers();H.Refresh(owner,fresh)
eq(drivers[card].condition,"[@nameplate2target,exists] show; hide","legacy mode exposes both relations via existence driver")
eq(card.side,"enemy","hostile child is classified for harmful ordinary skills")
eq(card.expectedGUID,"enemy-victim","child stores the current target identity")
eq(card.shield:IsShown(),false,"valid hostile relation exposes its own input region")
eq(card:GetAttribute("unit"),"nameplate2target","child retains a fixed protected relation token")
local snapshot=NS.ReadBridgeTarget(card)
eq(snapshot.unit,"nameplate2target","bridge snapshot carries the controlled relation token")
eq(snapshot.side,"enemy","bridge snapshot matches the child's action side")
eq(snapshot.targetName,"野猪","bridge snapshot has a complete exact target name")
eq(snapshot.guid,"enemy-victim","bridge snapshot has the displayed victim identity")
eq(NS.ValidToken("nameplate2target"),false,"child bridge never broadens global unit tokens")
local function emit(f,event)
    if f.scripts[event] then f.scripts[event](f) end
    if f.hooks and f.hooks[event] then f.hooks[event](f) end
end
resetTooltip();emit(card,"OnEnter");H.Refresh(owner,fresh)
eq(Cast.row,card,"child native hover activates only its own ordinary-skill bridge")
eq(card.status.count,2,"child status displays prepared ordinary-skill keys")
local help=table.concat(lines,"\n")
yes(help:find("短暂选中",1,true),"child tooltip explains temporary targeting")
yes(help:find("恢复原目标",1,true),"child tooltip explains restoration")
yes(help:find("普通技能键",1,true),"child tooltip uses the ordinary-skill contract")
eq(help:find("@mouseover",1,true),nil,"legacy child does not claim to require a native macro")
eq(logged[#logged].kind,"ENEMY_TARGET_BRIDGE_STATE","new child mode has its own diagnostic kind")
Cast.count=0;bridgeReason="not_unique";resetTooltip();H.Refresh(owner,fresh)
help=table.concat(lines,"\n")
yes(help:find("同名目标无法确认唯一",1,true),"ambiguous child explains why name casting was refused")
eq(logged[#logged].data.reason,"not_unique","child diagnostics preserve the actual bridge refusal")
bridgeReason="no_supported_spell";resetTooltip();H.Refresh(owner,fresh)
help=table.concat(lines,"\n")
yes(help:find("未找到适合此目标的普通技能键",1,true),"child explains when no compatible ordinary keys exist")
yes(help:find("脱战",1,true),"unprepared child still explains the out-of-combat restriction")
bridgeReason=nil;Cast.count=2
local priorLeaves=leaves
H.Clear()
eq(Cast.row,nil,"clearing a child hover releases its owned temporary keys")
yes(leaves>priorLeaves,"clear calls the bridge cleanup")

units.nameplate2target="friendly-victim"
fresh={state="known",guid="friendly-victim",name="队友",targetName="队友-异服",player=true,
    assist=true,harm=false,dead=false,offline=false}
owner.enemyTarget=fresh
H.Refresh(owner,fresh)
eq(card.side,"friendly","the same child switches to helpful skills for a friendly target")
eq(NS.ReadBridgeTarget(card).targetName,"队友-异服","friendly snapshot preserves the full realm-qualified name")
resetTooltip();emit(card,"OnEnter")
local bindingBefore=card:GetAttribute("unit")
combat=true;beforeProtected,beforeDriver=protectedWrites,driverWrites
H.Refresh(owner,fresh)
eq(card:GetAttribute("unit"),bindingBefore,"combat refresh never rewrites the child's protected relation")
eq(protectedWrites,beforeProtected,"legacy child combat refresh uses no protected writes")
eq(driverWrites,beforeDriver,"legacy child combat refresh does not replace the driver")
fresh.offline=nil;H.Refresh(owner,fresh)
eq(card.shield:IsShown(),true,"unknown connection blocks a still-shown child")
eq(NS.ReadBridgeTarget(card),nil,"unknown connection cannot return a cast snapshot")
eq(Cast.row,nil,"invalid relation releases the active bridge")
fresh.offline=false;fresh.dead=true;H.Refresh(owner,fresh);runDrivers()
eq(card:IsShown(),true,"existence driver keeps dead information visible")
eq(card.shield:IsShown(),true,"dead target still blocks interaction")
fresh.dead=false;fresh.assist=false;fresh.harm=false;H.Refresh(owner,fresh)
eq(card.shield:IsShown(),true,"neither-helpful-nor-hostile targets cannot receive a bridge")
fresh.assist=true;H.Refresh(owner,fresh)
units.nameplate2target="raced-victim"
eq(NS.ReadBridgeTarget(card),nil,"a victim changed before key preparation fails closed")
units.nameplate2target=fresh.guid
units.nameplate2="raced-owner"
eq(NS.ReadBridgeTarget(card),nil,"a reused enemy owner cannot authorize the child's cast")
H.Refresh(owner,fresh)
eq(card.shield:IsShown(),true,"reused owner blocks the complete external rectangle")
eq(protectedWrites,beforeProtected,"all legacy invalidation paths avoid combat protected writes")
combat=false;units.nameplate2=owner.expectedGUID;H.Refresh(owner,fresh)
local savedOwnerData=owner.data;owner.data=nil
eq(NS.ReadBridgeTarget(card),nil,"unbound parent data cannot authorize a child")
owner.data=savedOwnerData
card.side="enemy"
eq(NS.ReadBridgeTarget(card),nil,"an action side changed since the snapshot is rejected")
card.side="friendly"
NS.DB.shown=false
eq(NS.ReadBridgeTarget(card),nil,"a hidden addon cannot yield a cast snapshot")
NS.DB.shown=true
eq(forbiddenWrites,0,"child module does not itself target, cast or override keys")
eq(units.target,"selected-enemy","all read-only child paths retain the user's current target")
-- The small child deliberately has no aura views or wheel interception, even
-- when the main-card aura module is present. Unit actions remain available.
;(function()
    combat=false
    local function noChildAuras() error("small target strip must not access aura rendering") end
    NS.Auras={Create=noChildAuras,Update=noChildAuras,Scroll=noChildAuras,
        TooltipLines=noChildAuras,ShowAll=noChildAuras,HideAll=noChildAuras,Key=noChildAuras}
    local smallOwner=frame("Button","SmallOwner",panel,"SecureActionButtonTemplate")
    smallOwner.side,smallOwner.unit,smallOwner.expectedGUID="enemy","nameplate3","Small-Owner"
    smallOwner.data={guid="Small-Owner"};smallOwner.hover=frame("Texture",nil,smallOwner)
    local smallData={state="known",guid="Small-Victim",name="目标同伴",targetName="目标同伴",className="牧师",
        player=true,assist=true,harm=false,dead=false,offline=false,health=.6,healthCurrent=60,healthMax=100,healthAvailable=true}
    smallOwner.enemyTarget=smallData
    units.nameplate3,units.nameplate3target="Small-Owner","Small-Victim"
    NS.ReadEnemyTarget=function() return smallData end
    local smallButton=H.Create(smallOwner)
    H.Bind(smallOwner);runDrivers();H.Refresh(smallOwner,smallData)
    local visual=smallOwner.enemyTargetDisplay
    eq(visual.auras,nil,"small strip creates no aura views")
    eq(visual.height,26,"strip reserves no space for removed aura rows")
    eq(visual.nameText.width,68,"small strip keeps readable first-row name width")
    eq(visual.classText.title,"牧师","small strip keeps the class label")
    eq(visual.healthText.title,"60%","small strip keeps health percentage")
    resetTooltip();emit(smallButton,"OnEnter")
    yes(operated("SetUnit"),"small strip retains native unit tooltip setup")
    eq(operated("SetText"),false,"small strip retains native tooltip payload")
    eq(table.concat(lines,"\n"):find("滚轮",1,true),nil,"small strip has no obsolete aura wheel instruction")
    emit(smallButton,"OnLeave")
    eq(smallButton:GetScript("OnMouseWheel"),nil,"small strip does not intercept the wheel")
    visual:Hide();H.Refresh(smallOwner,smallData)
    combat=true
    local writes=protectedWrites
    units.nameplate3target="Small-ReusedVictim";H.Refresh(smallOwner,smallData)
    eq(smallButton.shield:IsShown(),true,"small strip still blocks a reused victim")
    units.nameplate3target="Small-Victim";units.nameplate3="Small-ReusedOwner";H.Refresh(smallOwner,smallData)
    eq(smallButton.shield:IsShown(),true,"small strip still blocks a reused owner")
    eq(protectedWrites,writes,"small strip refresh avoids protected state writes in combat")
    combat=false;units.nameplate3="Small-Owner";smallOwner:Hide();H.Refresh(smallOwner,smallData)
    eq(visual:IsShown(),false,"hidden owner hides the small strip")
    eq(smallButton:GetScript("OnClick"),builtinClick,"removing child auras preserves native clicks")
    NS.Auras=nil
end)()
print("Targets enemy target hover simulated checks: "..checks.."; actual spell dispatch remains an in-game check")
