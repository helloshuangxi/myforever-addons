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
local hoverEvents=frames[#frames]
yes(Hover,"module published")
yes(hoverEvents.events.CVAR_UPDATE,"key-down setting changes invalidate preparation")
yes(hoverEvents.events.UPDATE_OVERRIDE_ACTIONBAR,"override-bar changes invalidate preparation")

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
yes(barDriver and barDriver.condition:find("%[bonusbar:1%]") and barDriver.condition:find("%[form:1%]")
    and barDriver.condition:find("%[form:2%]"),"bar paging driver distinguishes forms")
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
eq(Hover.Status(fParty).availableKeys,3,"status counts available prepared keys")
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

-- A page change while the pointer remains on the tile must release the old
-- main-bar action immediately, without requiring another OnEnter.
enter(fParty)
yes(bindings["1"],"main-bar key initially bound while hovering")
setState(owner,"mfchbar","b1")
eq(bindings["1"],nil,"page change while hovering releases old-page key")
yes(bindings["F"],"page change keeps independent multibar key")
setState(owner,"mfchbar","a1")
yes(bindings["1"],"return to prepared page rebinds without pointer motion")
leave(fParty)

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
local late=tile("friendly",6,"party3")
eq(Hover.Install(late),false,"new installation defers in combat")

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
eq(Hover.Status(fParty).ready,false,"disabled status never claims readiness")
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

-- Form changes while already hovering and conservative unknown-form fallback.
fParty.unit="party1";fParty.attrs.unit="party1"
owner.attrs["state-mfchbar"]="f1";Hover.Sync()
enter(fParty);combat=true;setState(owner,"mfchcombat","combat")
yes(bindings["1"],"prepared form main key is initially available")
setState(owner,"mfchbar","f2")
eq(bindings["1"],nil,"form-to-form change releases previous spell")
eq(Hover.Status(fParty).availableKeys,1,"status excludes invalidated main-bar keys")
setState(owner,"mfchcombat","idle");combat=false;leave(fParty)
owner.attrs["state-mfchbar"]="unknown";Hover.Sync()
enter(fParty);combat=true;setState(owner,"mfchcombat","combat")
eq(bindings["1"],nil,"unknown form never acquires main-bar key")
yes(bindings["F"],"unknown form retains independent multibar key")
setState(owner,"mfchcombat","idle");combat=false;leave(fParty)
owner.attrs["state-mfchbar"]="a1";Hover.Sync()

-- Integration with the released controllers. Native Wrapped_OnLeave consumes
-- one shared _wrapentered flag, so only the outer wrapper's pre-body runs.
-- Model that dispatch rule rather than incorrectly running every leave body.
local function nativeEvent(row,event)
    if event=="OnEnter" then row.under=true;row.attrs._wrapentered=true end
    if event=="OnLeave" then row.under=false end
    for i=#wrappers,1,-1 do
        local w=wrappers[i]
        if w.row==row and w.event==event then
            if event~="OnLeave" or row.attrs._wrapentered then
                if event=="OnLeave" then row.attrs._wrapentered=nil end
                run(w.pre,row,w.owner)
            end
        end
    end
end
local originalOwner=frame("Frame","OriginalNearbyOwner",UIParent,"SecureHandlerStateTemplate")
NS.NearbyCast.owner=originalOwner
local sharedFriend=tile("friendly",4,"party2")
SecureHandlerWrapScript(sharedFriend,"OnLeave",originalOwner,"control:ClearBindings()")
SecureHandlerWrapScript(sharedFriend,"OnHide",originalOwner,"control:ClearBindings()")
yes(Hover.Install(sharedFriend),"install alongside original OOC leave wrapper")
Hover.Sync()
handle(originalOwner):SetBindingClick(true,"OLD","OriginalNearbyProxy","LeftButton")
nativeEvent(sharedFriend,"OnEnter")
nativeEvent(sharedFriend,"OnLeave")
eq(bindings.OLD,nil,"outer leave also clears original OOC owner's override")

-- Load the actual released name controller, not a duplicate binding model.
SecureHandlerSetFrameRef=function(f,k,v) f:SetFrameRef(k,v) end
ClearOverrideBindings=function() end
NS.NearbyCast.combatName=true
assert(loadfile("_forever_/Interface/AddOns/MyForeverTargets/CombatCast.lua"))("MyForeverTargets",NS)
local names=NS.CombatCast
local sharedEnemy=tile("enemy",4,"boss2")
yes(names.Install(sharedEnemy),"released enemy name controller installed")
yes(Hover.Install(sharedEnemy),"fixed-token controller installed on same row")
Hover.Sync()
sharedEnemy.attrs["combat-prepared"]=true
sharedEnemy.attrs["combat-key-count"]=1
sharedEnemy.attrs["combat-key1"]="2"
sharedEnemy.attrs["combat-proxy1"]="OldNameProxy"
names.owner.attrs["combat-active"]=true
combat=true;setState(owner,"mfchcombat","combat")
nativeEvent(sharedEnemy,"OnEnter")
eq(bindings["2"] and bindings["2"].name,e1.name,"fixed-token direct route wins over name continuation")
setState(names.owner,"combat","combat")
eq(bindings["2"] and bindings["2"].name,e1.name,"name combat-state callback also defers fixed tokens")
nativeEvent(sharedEnemy,"OnLeave")
eq(next(bindings),nil,"native leave clears all participating owners")
setState(owner,"mfchcombat","idle");combat=false

-- Nameplate tiles still use the released unique-name continuation; the new
-- outer leave must clear that owner even though its inner wrapper is skipped.
local sharedPlate=tile("enemy",5,"nameplate7")
yes(names.Install(sharedPlate),"nameplate name controller installed")
yes(Hover.Install(sharedPlate),"outer cleanup installed on nameplate")
Hover.Sync()
sharedPlate.attrs["combat-prepared"]=true
sharedPlate.attrs["combat-key-count"]=1
sharedPlate.attrs["combat-key1"]="2"
sharedPlate.attrs["combat-proxy1"]="OldNameProxy"
combat=true;setState(owner,"mfchcombat","combat")
nativeEvent(sharedPlate,"OnEnter")
eq(bindings["2"] and bindings["2"].name,"OldNameProxy","nameplate keeps released name route")
nativeEvent(sharedPlate,"OnLeave")
eq(next(bindings),nil,"outer native leave clears released name owner")
nativeEvent(sharedPlate,"OnEnter")
yes(bindings["2"],"old enemy route bound before crossing controllers")
nativeEvent(sharedFriend,"OnEnter")
eq(bindings["2"],nil,"entering friendly fixed row releases previous enemy owner")
yes(bindings["1"],"new friendly owner acquires its own keys")
nativeEvent(sharedPlate,"OnLeave")
yes(bindings["1"],"late old enemy leave preserves new friendly binding")
nativeEvent(sharedFriend,"OnLeave")
eq(next(bindings),nil,"leaving new friendly row clears remaining binding")
setState(owner,"mfchcombat","idle");combat=false

-- Disabling only the new module must restore the pre-existing enemy route.
NS.CombatHoverEnabled=false;Hover.Sync()
eq(sharedEnemy.attrs["mfch-ready"],nil,"disabled direct module does not reserve a stable enemy row")
combat=true;setState(owner,"mfchcombat","combat")
nativeEvent(sharedEnemy,"OnEnter")
eq(bindings["2"] and bindings["2"].name,"OldNameProxy","disabled direct module leaves old name route available")
nativeEvent(sharedEnemy,"OnLeave")
eq(next(bindings),nil,"disabled module cleanup still releases old owner")
setState(owner,"mfchcombat","idle");combat=false
NS.CombatHoverEnabled=true;Hover.Sync()

-- No snippet uses a global that the restricted environment lacks.
for name,snippet in pairs(Hover.Snippets) do
    yes(not snippet:find("UnitGUID") and not snippet:find("InCombatLockdown"),"restricted-safe "..name)
end

print("Targets combat-hover simulated checks: "..checks.."; native secure engine, key presses and spell recipients were not executed")
