-- In-combat stable-unit hover casting: configuration and restricted-snippet
-- simulation. The native secure engine, real key presses and spell recipients
-- are not executed here and still require the game client.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local function no(value,why) eq(not not value,false,why) end

local combat=false
InCombatLockdown=function() return combat end
issecretvalue=function() return false end

local methods,frames,wrappers,drivers={},{},{},{}
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",attrs={},refs={},
        scripts={},shown=true,under=false}, {__index=methods})
    frames[#frames+1]=f
    if name then _G[name]=f end
    return f
end
function methods:GetName() return self.name end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value) assert(not combat,"insecure attribute change in combat");self.attrs[key]=value end
function methods:SetFrameRef(key,f) assert(not combat,"insecure frame ref in combat");self.refs[key]=f end
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript() end
function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetPoint(...) self.point={...} end
CreateFrame=frame
UIParent=frame("Frame","UIParent")
SecureHandlerWrapScript=function(row,event,owner,pre)
    assert(not combat,"wrap in combat")
    wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre}
end
RegisterStateDriver=function(owner,state,condition)
    assert(not combat,"driver in combat")
    drivers[#drivers+1]={owner=owner,state=state,condition=condition}
end

-- Restricted environment model: handles may read/write attributes and
-- override bindings at any time; insecure code may not in combat.
local bindings={}
local handles=setmetatable({}, {__mode="k"})
local hmeta={}
hmeta.__index=hmeta
local function handle(f)
    if not f then return nil end
    local h=handles[f]
    if not h then h=setmetatable({frame=f},hmeta);handles[f]=h end
    return h
end
function hmeta:GetAttribute(key) return self.frame.attrs[key] end
function hmeta:SetAttribute(key,value) self.frame.attrs[key]=value end
function hmeta:GetFrameRef(key) return handle(self.frame.refs[key]) end
function hmeta:IsVisible() return self.frame.shown end
function hmeta:IsUnderMouse() return self.frame.under end
function hmeta:ClearBindings()
    for key,value in pairs(bindings) do if value.owner==self.frame then bindings[key]=nil end end
end
function hmeta:SetBindingClick(priority,key,name,button)
    assert(type(name)=="string","restricted SetBindingClick uses a frame name here")
    bindings[key]={owner=self.frame,priority=priority,name=name,button=button}
end

local function run(snippet,selfFrame,controlFrame,newstate)
    local chunk=assert(loadstring("local self, control, newstate = ...\n"..snippet))
    setfenv(chunk,{})
    chunk(handle(selfFrame),handle(controlFrame),newstate)
end
local function wrapperFor(row,event)
    for _,w in ipairs(wrappers) do if w.row==row and w.event==event then return w end end
end
local function enter(row) row.under=true;local w=wrapperFor(row,"OnEnter");run(w.pre,row,w.owner) end
local function leave(row) row.under=false;local w=wrapperFor(row,"OnLeave");run(w.pre,row,w.owner) end
local function setState(owner,name,value)
    owner.attrs["state-"..name]=value
    local snippet=owner.attrs["_onstate-"..name]
    if snippet then run(snippet,owner,nil,value) end
end

-- Addon namespace and the NearbyCast discovery it reuses.
local NS={}
function NS.Public() return true end
function NS.Number(v) return type(v)=="number" and v==v end
function NS.Read(fn,...) if type(fn)~="function" then return nil end local ok,a,b=pcall(fn,...) if ok then return a,b end end
NS.DB={legacyNameBridgeEnabled=true}
local actions={
    friendly={
        {actionKind="spell",spell="快速治疗(等级 2)",keys={"1","SHIFT-1"},command="ACTIONBUTTON1",useOnKeyDown=true},
        {actionKind="spell",spell="真言术：盾",keys={"F"},command="MULTIACTIONBAR1BUTTON3",useOnKeyDown=false},
    },
    enemy={
        {actionKind="spell",spell="暗言术：痛",keys={"2"},command="ACTIONBUTTON2",useOnKeyDown=true},
        {actionKind="macro",spell=nil,keys={"W"},command="ACTIONBUTTON4"},
    },
}
local discovered={}
NS.NearbyCast={legacyName=true,DiscoverActions=function(side,allowOwn)
    discovered[#discovered+1]={side=side,allowOwn=allowOwn}
    return actions[side]
end}

local chunk=assert(loadfile("_forever_/Interface/AddOns/MyForeverTargets/CombatHover.lua"))
chunk("MyForeverTargets",NS)
local Hover=NS.CombatHover
yes(Hover,"module published")

-- Stable token classification.
for _,unit in ipairs({"player","pet","target","focus","party1","party4","partypet2","raid1","raid40",
    "raidpet7","boss1","boss8","arena1","arena5"}) do yes(Hover.StableUnit(unit),"stable "..unit) end
for _,unit in ipairs({"nameplate1","nameplate40","targettarget","focustarget","party1target","raid3target",
    "party5","party0","raid41","boss9","arena6","mouseover","none","",nil,"party1 ","PARTY1"}) do
    no(Hover.StableUnit(unit),"volatile "..tostring(unit))
end

-- Tiles: one friendly party slot, one friendly nameplate, one enemy boss, one enemy nameplate.
local function tile(side,index,unit)
    local row=frame("Button","MyForeverTargets"..side..index,UIParent,"SecureActionButtonTemplate")
    row.side,row.index,row.unit=side,index,unit
    row.attrs.unit=unit
    return row
end
local fParty,fPlate=tile("friendly",1,"party1"),tile("friendly",2,"nameplate3")
local eBoss,ePlate=tile("enemy",1,"boss1"),tile("enemy",2,"nameplate5")
NS.UI={friendly={tiles={fParty,fPlate}},enemy={tiles={eBoss,ePlate}}}

-- Installing out of combat wraps the three scripts and registers the drivers.
yes(Hover.Install(fParty),"install out of combat")
local owner=Hover.owner
yes(owner and owner.template:find("SecureHandlerStateTemplate",1,true),"secure state owner")
eq(#wrappers,3,"three wrappers for first row")
yes(wrapperFor(fParty,"OnEnter") and wrapperFor(fParty,"OnLeave") and wrapperFor(fParty,"OnHide"),"enter/leave/hide wrapped")
local combatDriver,barDriver
for _,d in ipairs(drivers) do
    if d.state=="mfchcombat" then combatDriver=d elseif d.state=="mfchbar" then barDriver=d end
end
eq(combatDriver and combatDriver.condition,"[combat] combat; idle","combat driver")
yes(barDriver and barDriver.condition:find("%[bonusbar:1%]") and barDriver.condition:find("%[shapeshift%]"),"bar paging driver")
eq(fParty.attrs["mfch-index"],1,"friendly index")
eq(owner.refs["mfch-row1"],fParty,"row ref")
eq(Hover.Install(fParty),true,"install idempotent")
eq(#wrappers,3,"no duplicate wrappers")

-- Sync installs the remaining tiles and publishes key/proxy attributes.
owner.attrs["state-mfchbar"]="a1"
yes(Hover.Sync(),"sync out of combat")
eq(#wrappers,12,"all four tiles wrapped")
eq(eBoss.attrs["mfch-index"],101,"enemy index offset")
eq(fParty.attrs["mfch-ready"],true,"party tile ready")
eq(fParty.attrs["mfch-unit"],"party1","party unit recorded")
eq(fPlate.attrs["mfch-ready"],nil,"nameplate tile not ready")
eq(eBoss.attrs["mfch-ready"],true,"boss tile ready")
eq(ePlate.attrs["mfch-ready"],nil,"enemy nameplate tile not ready")
eq(owner.attrs["mfch-enabled"],true,"enabled attribute")
eq(owner.attrs["friendly-keys"],3,"friendly key count")
eq(owner.attrs["enemy-keys"],1,"enemy macro action skipped")
eq(owner.attrs["friendly-key1"],"1","key1")
eq(owner.attrs["friendly-key2"],"SHIFT-1","key2")
eq(owner.attrs["friendly-keyproxy2"],1,"modifier key shares proxy")
eq(owner.attrs["friendly-keypaged1"],true,"main bar key paged")
eq(owner.attrs["friendly-keypaged3"],nil,"multibar key not paged")
eq(owner.attrs["friendly-bar"],"a1","bar recorded")
local p1=_G[owner.attrs["friendly-proxyname1"]]
yes(p1 and p1.template:find("SecureActionButtonTemplate",1,true),"proxy is secure action button")
eq(p1.attrs.type,"macro","proxy type")
eq(p1.attrs["mfch-spell"],"快速治疗(等级 2)","proxy spell with rank")
eq(p1.attrs.useOnKeyDown,true,"key-down respected")
eq(p1.clicks[1],"AnyDown","clicks follow key-down")
eq(_G[owner.attrs["friendly-proxyname2"]].clicks[1],"AnyUp","key-up proxy")
eq(p1.mouse,false,"proxy ignores mouse")
for _,d in ipairs(discovered) do eq(d.allowOwn,true,"discovery tolerates own bridge overrides") end

-- Out of combat: entering records hover but never binds (bridge owns OOC).
enter(fParty)
eq(owner.attrs["mfch-hover"],1,"hover recorded OOC")
eq(next(bindings),nil,"no OOC bindings")

-- Entering combat while already on the party tile binds its keys.
combat=true
setState(owner,"mfchcombat","combat")
eq(owner.attrs["mfch-combat"],true,"combat flag")
eq(bindings["1"] and bindings["1"].name,owner.attrs["friendly-proxyname1"],"key 1 bound to heal proxy")
eq(bindings["1"].priority,true,"priority override")
eq(bindings["1"].button,"LeftButton","proxy clicked with left button")
eq(bindings["SHIFT-1"] and bindings["SHIFT-1"].name,owner.attrs["friendly-proxyname1"],"modifier key bound")
eq(bindings["F"] and bindings["F"].name,owner.attrs["friendly-proxyname2"],"multibar key bound")
eq(bindings["2"],nil,"enemy key not bound on friendly tile")
eq(p1.attrs.macrotext,"/cast [@party1,exists,help] 快速治疗(等级 2)","heal aimed at party1")

-- Leaving clears; a nameplate tile in combat binds nothing.
leave(fParty)
eq(next(bindings),nil,"leave clears bindings")
eq(owner.attrs["mfch-hover"],nil,"hover cleared")
enter(fPlate)
eq(next(bindings),nil,"nameplate tile unsupported in combat")
leave(fPlate)

-- Enemy boss tile in combat aims harmful spells at boss1.
enter(eBoss)
local e1=_G[owner.attrs["enemy-proxyname1"]]
eq(bindings["2"] and bindings["2"].name,e1.name,"enemy key bound")
eq(bindings["1"],nil,"friendly key not bound on enemy tile")
eq(bindings["W"],nil,"user macro key untouched")
eq(e1.attrs.macrotext,"/cast [@boss1,exists,harm] 暗言术：痛","harm aimed at boss1")
leave(eBoss)
enter(ePlate)
eq(next(bindings),nil,"enemy nameplate tile unsupported")
leave(ePlate)

-- Stance/form paging in combat: main-bar keys are skipped, multibar keys stay.
owner.attrs["state-mfchbar"]="s"
enter(fParty)
eq(bindings["1"],nil,"paged key skipped after bar change")
eq(bindings["F"] and bindings["F"].name,owner.attrs["friendly-proxyname2"],"unpaged key still bound")
leave(fParty)
owner.attrs["state-mfchbar"]="a1"

-- Moving between tiles: leave of the old tile must not clear the new hover.
enter(fParty)
local w=wrapperFor(eBoss,"OnEnter");eBoss.under=true;fParty.under=false
run(w.pre,eBoss,owner)
eq(owner.attrs["mfch-hover"],101,"new hover")
local wl=wrapperFor(fParty,"OnLeave");run(wl.pre,fParty,owner)
eq(owner.attrs["mfch-hover"],101,"stale leave ignored")
yes(bindings["2"],"enemy bindings kept after stale leave")
leave(eBoss)

-- Sync in combat defers without touching protected state.
Hover.dirty=false
eq(Hover.Sync(),false,"sync deferred in combat")
eq(Hover.dirty,true,"marked dirty")
eq(Hover.BindRow(fParty),false,"bindrow deferred in combat")

-- Leaving combat clears combat bindings so the OOC bridge takes over.
enter(fParty)
yes(bindings["1"],"bound before regen")
setState(owner,"mfchcombat","idle")
eq(owner.attrs["mfch-combat"],false,"combat flag off")
eq(next(bindings),nil,"combat bindings cleared on idle")
combat=false
leave(fParty)

-- Disabling the cast toggle disables combat binding.
NS.DB.legacyNameBridgeEnabled=false
yes(Hover.Sync(),"resync")
eq(owner.attrs["mfch-enabled"],nil,"disabled attribute")
eq(owner.attrs["friendly-keys"],0,"no keys when disabled")
eq(_G[owner.attrs["friendly-proxyname1"] or "MyForeverTargetsCombatHoverfriendly1"].attrs["mfch-spell"],nil,"stale proxy retired")
enter(fParty);combat=true;setState(owner,"mfchcombat","combat")
eq(next(bindings),nil,"no bindings when disabled")
setState(owner,"mfchcombat","idle");combat=false;leave(fParty)
NS.DB.legacyNameBridgeEnabled=true
Hover.Sync()

-- A tile rebound out of combat to a nameplate loses eligibility.
fParty.unit="nameplate9";fParty.attrs.unit="nameplate9"
Hover.BindRow(fParty)
eq(fParty.attrs["mfch-ready"],nil,"rebound nameplate not ready")
enter(fParty);combat=true;setState(owner,"mfchcombat","combat")
eq(next(bindings),nil,"rebound nameplate tile does not bind")
setState(owner,"mfchcombat","idle");combat=false;leave(fParty)

-- Unit attribute mismatch (row.unit vs secure attribute) is not trusted.
fParty.unit="party2";fParty.attrs.unit="party3"
Hover.BindRow(fParty)
eq(fParty.attrs["mfch-ready"],nil,"mismatched unit attribute not ready")

-- Bridge mode off: module installs nothing.
NS.NearbyCast.legacyName=false
local extra=tile("friendly",3,"party2")
eq(Hover.Install(extra),false,"no install without bridge mode")
NS.NearbyCast.legacyName=true

-- No snippet uses a global that the restricted environment lacks.
for name,snippet in pairs(Hover.Snippets) do
    yes(not snippet:find("UnitGUID") and not snippet:find("InCombatLockdown"),"restricted-safe "..name)
end

print("Targets combat-hover simulated checks: "..checks.."; native secure engine, key presses and spell recipients were not executed")
