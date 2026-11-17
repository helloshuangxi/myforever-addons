-- Integration model for the production friendly combat routes. It executes the
-- actual restricted snippets in ordinary Lua and models macro target changes.
-- It does not run WoW's restricted engine or prove a native cast/recipient.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local combat,restricted=false,false
local frames,wrappers,drivers={},{},{}
local methods={}
local hovered,serial=nil,0
local overrides={}
local function clear(owner) overrides[owner]={} end
local function bind(owner,key,name,button)
    serial=serial+1
    overrides[owner]=overrides[owner] or {}
    overrides[owner][key]={owner=owner,name=name,button=button,serial=serial}
end
local function active(key)
    local result
    for _,keys in pairs(overrides) do
        local candidate=keys[key]
        if candidate and (not result or candidate.serial>result.serial) then result=candidate end
    end
    return result
end
local function frame(kind,name,parent,template)
    local value=setmetatable({kind=kind,name=name,parent=parent,template=template,
        attrs={},refs={},scripts={},hooks={},shown=true,events={}}, {__index=methods})
    frames[#frames+1]=value
    if name then _G[name]=value end
    return value
end
function methods:GetName() return self.name end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value)
    assert(not combat or restricted,"ordinary Lua changed a protected combat attribute")
    self.attrs[key]=value
end
function methods:SetFrameRef(key,value)
    assert(not combat,"ordinary Lua changed a combat frame reference")
    self.refs[key]=value
end
function methods:GetFrameRef(key) return self.refs[key] end
function methods:IsVisible() return self.shown end
function methods:IsShown() return self.shown end
function methods:IsUnderMouse() return hovered==self end
function methods:SetSize() end
function methods:SetPoint() end
function methods:EnableMouse() end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event,fn)
    self.hooks[event]=self.hooks[event] or {}
    self.hooks[event][#self.hooks[event]+1]=fn
end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:ClearBindings()
    assert(restricted,"frame-handle binding API escaped the restricted model")
    clear(self)
end
function methods:SetBindingClick(_,key,name,button)
    assert(restricted,"frame-handle binding API escaped the restricted model")
    bind(self,key,name,button)
end
CreateFrame=frame
UIParent=frame("Frame","UIParent")
SecureHandlerWrapScript=function(row,event,owner,pre,post)
    wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre,post=post}
end
SecureHandlerSetFrameRef=function(owner,key,value) owner:SetFrameRef(key,value) end
RegisterStateDriver=function(owner,state,condition)
    assert(not combat,"driver setup must be out of combat")
    drivers[#drivers+1]={owner=owner,state=state,condition=condition}
    owner:SetAttribute("state-"..state,state=="mfchbar" and "a1" or "idle")
end
ClearOverrideBindings=function(owner)
    assert(not combat,"ordinary Lua cleared a combat binding")
    clear(owner)
end
SetOverrideBindingClick=function(owner,_,key,name,button)
    assert(not combat,"ordinary Lua installed a combat binding")
    bind(owner,key,name,button)
end
local function forbidden() error("route code may not change persistent bindings or player macros") end
SetBinding=forbidden;SetBindingClick=forbidden;SaveBindings=forbidden
CreateMacro=forbidden;EditMacro=forbidden
InCombatLockdown=function() return combat end
issecretvalue=function() return false end
GetMouseFoci=function() return hovered and {hovered} or {} end
MouseIsOver=function(row) return hovered==row end
local original={unit="target",guid="Creature-original",name="原敌人",targetName="原敌人",player=false,
    side="enemy",dead=false,offline=false}
local units={
    player={unit="player",guid="Player-self",name="自己",targetName="自己-测试服",player=true,side="friendly",dead=false,offline=false},
    party1={unit="party1",guid="Player-party",name="队友",targetName="队友-测试服",player=true,side="friendly",dead=false,offline=false},
    nameplate3={unit="nameplate3",guid="Player-nearby",name="附近玩家",targetName="附近玩家-测试服",player=true,side="friendly",dead=false,offline=false},
    nameplate5={unit="nameplate5",guid="Player-other",name="另一玩家",targetName="另一玩家-测试服",player=true,side="friendly",dead=false,offline=false},
    nameplate4={unit="nameplate4",guid="Creature-enemy",name="怪物",targetName="怪物",player=false,side="enemy",dead=false,offline=false},
    target=original,
}
UnitExists=function(unit) return units[unit]~=nil end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
UnitName=function(unit) return units[unit] and units[unit].name end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player end
UnitIsDeadOrGhost=function(unit) return units[unit] and units[unit].dead or false end
UnitIsConnected=function(unit) return units[unit] and not units[unit].offline end
UnitCanAssist=function(_,unit) return units[unit] and units[unit].side=="friendly" or false end
UnitCanAttack=function(_,unit) return units[unit] and units[unit].side=="enemy" or false end
GetBindingAction=function(key,useOverrides)
    local value=useOverrides and active(key)
    return value and "CLICK "..value.name..":"..value.button or "BASE_"..key
end
GetBindingKey=function() end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
-- The existing order/ownership matrix deliberately keeps the old alias policy;
-- the canonical-player bypass gets an explicit integrated case below.
NameUtil=nil
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
eq(NS.NativeMacroOnly,true,"fixture retains the production native-macro startup policy")
eq(NS.LegacyNameBridge,true,"fixture retains the production ordinary-skill bridge")
eq(NS.CombatNameBridge,true,"fixture retains the production combat name continuation")
NS.ReadUnit=function(unit,side)
    local value=units[unit]
    return value and value.side==side and value or nil
end
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
local Nearby=NS.NearbyCast
local helpful={{spell="圣光术",spellID=639,slot=61,command="MULTIACTIONBAR1BUTTON1",keys={"1"},
    actionKind="spell",side="friendly",useOnKeyDown=true},
    {spell="圣光术",spellID=639,slot=1,command="ACTIONBUTTON1",keys={"2"},
    actionKind="spell",side="friendly",useOnKeyDown=true}}
local harmful={{spell="惩击",spellID=585,slot=62,command="MULTIACTIONBAR1BUTTON2",keys={"Z"},
    actionKind="spell",side="enemy",useOnKeyDown=true}}
Nearby.DiscoverActions=function(side) return side=="friendly" and helpful or harmful end
Nearby.KnownUniqueNPC=function() return true end
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."CombatHover.lua"))("MyForeverTargets",NS)
local Names,Fixed=NS.CombatCast,NS.CombatHover
local rows={}
local function makeRow(name,side,unit,index)
    local row=frame("Button",name,UIParent,"SecureActionButtonTemplate")
    row.side,row.index=side,index
    -- Production creates the wrappers before a roster unit has been assigned.
    yes(Nearby.Install(row),"main row installs nearby/name cleanup while unit is still empty")
    yes(Fixed.Install(row),"main row installs fixed-token routing while unit is still empty")
    row.unit,row.expectedGUID=unit,units[unit].guid
    row:SetAttribute("unit",unit)
    Fixed.BindRow(row)
    rows[#rows+1]=row
    return row
end
local near=makeRow("FriendlyCombatNearby","friendly","nameplate3",1)
local party=makeRow("FriendlyCombatParty","friendly","party1",2)
local selfRow=makeRow("FriendlyCombatSelf","friendly","player",3)
local enemy=makeRow("FriendlyCombatEnemy","enemy","nameplate4",1)
local otherNear=makeRow("FriendlyCombatOtherNearby","friendly","nameplate5",4)
local sub=frame("Button","FriendlyCombatTargetSubbar",UIParent,"SecureActionButtonTemplate")
sub.side,sub.bridgeTarget,sub.unit="friendly",true,"nameplate4target"
eq(Names.Install(sub),false,"changing target subbars never install the frozen-name route")
Names.RefreshAll()
Fixed.Sync()
yes(Names.Status(near).prepared,"nearby friendly nameplate prepares its ordinary helpful keys")
eq(Names.Status(near).nameGuardPolicy,"alias","original ownership matrix explicitly exercises the retained alias policy")
eq(Names.Status(near).count,2,"all supported helpful keys are frozen before combat")
eq(Names.Status(party).reason,"native_unit","party unit stays off the name route")
eq(Names.Status(selfRow).reason,"native_unit","self unit stays off the name route")
yes(Names.Status(enemy).prepared,"existing enemy nameplate route remains prepared")
eq(Fixed.Status(near).stable,false,"nearby nameplate is excluded from direct token casting")
yes(Fixed.Status(party).ready,"party unit uses fixed-token direct casting")
yes(Fixed.Status(selfRow).ready,"self uses fixed-token direct casting")

local function run(snippet,env)
    if not snippet then return end
    env=setmetatable(env or {}, {__index=_G})
    local f=assert(loadstring(snippet))
    setfenv(f,env)
    local prior=restricted
    restricted=true
    local ok,errorText=pcall(f)
    restricted=prior
    assert(ok,errorText)
end
local function emit(row,event,order,outerOnly)
    local list={}
    for _,wrapper in ipairs(wrappers) do
        if wrapper.row==row and wrapper.event==event then list[#list+1]=wrapper end
    end
    if order=="newest" then
        local reverse={}
        for i=#list,1,-1 do reverse[#reverse+1]=list[i] end
        list=reverse
    end
    for i,wrapper in ipairs(list) do
        if not outerOnly or i==1 then run(wrapper.pre,{self=row,control=wrapper.owner}) end
    end
    if row.scripts[event] then row.scripts[event](row) end
    for _,fn in ipairs(row.hooks[event] or {}) do fn(row) end
end
local function enter(row,order)
    hovered=row
    NS.HoveredTile=row
    emit(row,"OnEnter",order)
end
local function leave(row,order,outerOnly)
    if hovered==row then hovered=nil;NS.HoveredTile=nil end
    emit(row,"OnLeave",order,outerOnly)
end
local function changeCombat(value,reverse)
    combat=value
    local list={}
    for _,driver in ipairs(drivers) do if driver.state~="mfchbar" then list[#list+1]=driver end end
    if reverse then
        local reversed={}
        for i=#list,1,-1 do reversed[#reversed+1]=list[i] end
        list=reversed
    end
    for _,driver in ipairs(list) do
        local state=value and "combat" or "idle"
        restricted=true
        driver.owner:SetAttribute("state-"..driver.state,state)
        restricted=false
        run(driver.owner:GetAttribute("_onstate-"..driver.state),{self=driver.owner,newstate=state})
    end
    for _,f in ipairs(frames) do
        local event=value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED"
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event) end
    end
end

-- Model only the guards inspected by the actual restricted preflight. This is
-- intentionally not a replacement for native macro execution or identity checks.
SecureCmdOptionParse=function(condition)
    if condition=="[@target,exists] present" then return units.target and "present" or nil end
    local unit=condition:match("^%[@([^,]+),")
    local value=unit and units[unit]
    if value and not value.dead and (condition:find(",harm",1,true) and value.side=="enemy"
        or condition:find(",help",1,true) and value.side=="friendly") then return "valid" end
end
local records,starts,ends={},{},{}
local logEnabled,logThrows=true,false
NS.Diagnostics={Enabled=function() return logEnabled end,
    Record=function(kind,fields)
        if logThrows then error("test logger unavailable") end
        records[#records+1]={kind=kind,fields=fields}
    end,
    BeginCastAttempt=function(fields) starts[#starts+1]=fields;return #starts end,
    EndCastAttempt=function(id,fields) ends[#ends+1]={id=id,fields=fields} end}
local function findLast(kind)
    for i=#records,1,-1 do if records[i].kind==kind then return records[i].fields end end
end
local function clickedProxy(key)
    local route=active(key)
    yes(route,"prepared key has an actual modeled owner")
    return _G[route.name],route
end
local modeledCasts={}
local function modelAction(proxy)
    if proxy:GetAttribute("type")~="macro" then return end
    local macro=proxy:GetAttribute("macrotext")
    if not macro then return end
    local previous
    for line in macro:gmatch("[^\n]+") do
        if line:match("^/stopmacro") then
            local unit=line:match("@([^,]+)")
            if unit and (not units[unit] or units[unit].dead) then return end
        elseif line=="/cleartarget" then
            if units.target then previous=units.target end
            units.target=nil
        elseif line:match("^/targetexact ") then
            local name=line:sub(14)
            for unit,value in pairs(units) do
                if unit~="target" and value.targetName==name then units.target=value;break end
            end
        elseif line=="/targetlasttarget" then
            units.target,previous=previous,units.target
        elseif line:match("^/cast ") then
            local unit=line:match("@([^,%]]+)")
            modeledCasts[#modeledCasts+1]={unit=unit,guid=units[unit] and units[unit].guid}
        end
    end
end
local function press(key,dispatch,down)
    if down==nil then down=true end
    local proxy=clickedProxy(key)
    for _,wrapper in ipairs(wrappers) do
        if wrapper.row==proxy and wrapper.event=="PreClick" then
            run(wrapper.pre,{self=proxy,control=wrapper.owner})
        end
    end
    if proxy.scripts.PreClick then proxy.scripts.PreClick(proxy,"LeftButton",down) end
    if dispatch~=false then modelAction(proxy) end
    if proxy.scripts.PostClick then proxy.scripts.PostClick(proxy,"LeftButton",down) end
    return proxy
end

-- A real client nests the newest wrapper around previous wrappers. Also run
-- the opposite pre-body order to ensure controller routing is order-independent.
for _,order in ipairs({"newest","oldest"}) do
    for _,reverseDrivers in ipairs({false,true}) do
        for _,initial in ipairs({"nonempty","empty"}) do
            if combat then changeCombat(false) end
            hovered=nil;NS.HoveredTile=nil
            units.target=initial=="nonempty" and original or nil
            Names.RefreshAll();Fixed.Sync()
            enter(near,order)
            eq(active("1").owner,Nearby.owner,"friendly ordinary key uses nearby owner before combat")
            local expected=UnitGUID("target")
            changeCombat(true,reverseDrivers)
            eq(active("1").owner,Names.owner,"stationary pointer transfers to friendly name owner in combat")
            local proxy=press("1")
            eq(proxy:GetAttribute("combat-branch"),initial=="nonempty" and "name_bridge_restore" or "name_bridge_clear",
                "secure preflight chooses the original-presence restoration branch")
            eq(UnitGUID("target"),expected,"modeled macro returns original target identity")
            eq(UnitExists("target"),initial=="nonempty","modeled macro returns original target existence")
            eq(modeledCasts[#modeledCasts].guid,units.nameplate3.guid,"macro model aims at the named nearby friend")
            local post=findLast("COMBAT_NAME_POST")
            yes(post,"legacy combat dispatch records a paired observation")
            eq(post.targetRestoredObserved,true,"restoration readback is recorded separately from cast success")
            eq(post.recipientProven,false,"legacy diagnostics never prove the spell recipient")
            eq(starts[#starts].route,"combat_name","name route opens a distinct spell observation window")
            eq(starts[#starts].generatedCommand,nil,"name-bridge macro text never enters diagnostics")
            leave(near,"newest",true)
            eq(active("1"),nil,"outer native leave cleanup retires the nested name owner")
            changeCombat(false)
        end
    end
end

-- Cross-controller Enter may arrive before the preceding row's Leave. Both
-- wrapper orders must preserve the new row and release every old owner.
for _,order in ipairs({"newest","oldest"}) do
    units.target=original
    hovered=nil;NS.HoveredTile=nil
    Names.RefreshAll();Fixed.Sync()
    changeCombat(true)
    enter(near,order)
    eq(active("1").owner,Names.owner,"friendly nameplate enters the name bridge during combat")
    enter(party,order)
    eq(active("1").owner,Fixed.owner,"party Enter transfers the key to fixed-token routing")
    leave(near,order)
    eq(active("1").owner,Fixed.owner,"late nearby Leave cannot clear the newly hovered party key")
    local fixedProxy=press("1")
    eq(fixedProxy:GetAttribute("macrotext"),"/cast [@party1,exists,help] 圣光术","party action targets the native party token")
    eq(UnitGUID("target"),original.guid,"fixed-token modeled cast leaves the enemy target untouched")
    eq(findLast("COMBAT_FIXED_POST").targetUnchangedObserved,true,"fixed route reads back unchanged original target")
    eq(starts[#starts].route,"combat_fixed","fixed route opens its own observation window")
    eq(starts[#starts].expectedGUID,units.party1.guid,"fixed route keeps expected recipient separate from original target")
    enter(selfRow,order)
    leave(party,order)
    eq(active("1").owner,Fixed.owner,"late party Leave preserves the newly hovered self row")
    local selfProxy=press("1")
    eq(selfProxy:GetAttribute("macrotext"),"/cast [@player,exists,help] 圣光术","fixed-to-fixed transfer updates the actual unit token")
    enter(near,order)
    eq(active("1").owner,Names.owner,"nearby Enter retains its name owner regardless of wrapper order")
    leave(party,order)
    eq(active("1").owner,Names.owner,"late party Leave cannot erase the new nearby key")
    enter(otherNear,order)
    leave(near,order)
    eq(active("1").owner,Names.owner,"late nameplate Leave preserves a second friendly nameplate")
    local otherProxy=press("1")
    yes(otherProxy:GetAttribute("macrotext"):find("/targetexact 另一玩家-测试服",1,true),"nameplate-to-nameplate transfer uses the new full player name")
    enter(enemy,order)
    eq(active("Z").owner,Names.owner,"existing enemy name bridge remains usable")
    leave(near,order)
    eq(active("Z").owner,Names.owner,"late friendly Leave cannot erase the new enemy key")
    local enemyProxy=press("Z")
    yes(enemyProxy:GetAttribute("macrotext"):find("/cast [@target,harm,nodead] 惩击",1,true),"enemy route retains hostile spell guard")
    enter(selfRow,order)
    local playerProxy=press("1")
    eq(playerProxy:GetAttribute("macrotext"),"/cast [@player,exists,help] 圣光术","self unit uses direct helpful action")
    leave(enemy,order)
    eq(active("1").owner,Fixed.owner,"old enemy Leave cannot erase new player key")
    selfRow.shown=false
    emit(selfRow,"OnHide","newest",true)
    eq(active("1"),nil,"outer hide wrapper clears the fixed owner")
    selfRow.shown=true
    changeCombat(false)
end

-- Layout/overlay changes may leave the cursor over a row without OnEnter. The
-- OOC focus reconciler seeds state-driver entry without a fresh mouse motion.
for _,row in ipairs({near,party,selfRow}) do
    hovered=row;NS.HoveredTile=row
    Names.owner:SetAttribute("combat-hover-index",nil)
    Fixed.owner:SetAttribute("mfch-hover",nil)
    Names.RefreshAll();Fixed.Sync()
    changeCombat(true,true)
    eq(active("1").owner,row==near and Names.owner or Fixed.owner,"stationary focus sampled before combat transfers its correct owner")
    leave(row,"newest",true)
    changeCombat(false)
end

-- Paging protection drops only affected fixed keys. Nameplate keys use their
-- own already prepared snapshots and are not cleared by the fixed page driver.
hovered=nil;NS.HoveredTile=nil;Names.RefreshAll();Fixed.Sync()
changeCombat(true)
enter(party,"newest")
yes(active("2"),"prepared main-bar key starts eligible")
restricted=true;Fixed.owner:SetAttribute("state-mfchbar","a2");restricted=false
run(Fixed.owner:GetAttribute("_onstate-mfchbar"),{self=Fixed.owner,newstate="a2"})
eq(active("2"),nil,"changed main-bar page no longer intercepts a stale fixed key")
yes(active("1"),"non-paged helpful key remains eligible")
enter(near,"newest")
local oldNameRoute=active("1")
run(Fixed.owner:GetAttribute("_onstate-mfchbar"),{self=Fixed.owner,newstate="a2"})
eq(active("1"),oldNameRoute,"fixed page refresh does not erase the nameplate owner")
leave(near,"newest",true)
changeCombat(false)
Fixed.owner:SetAttribute("state-mfchbar","a1")

-- A failed preflight/fallback records what happened, but does not open a window
-- that would attribute a fallback/self cast to the frozen nearby recipient.
hovered=nil;NS.HoveredTile=nil;Names.RefreshAll();Fixed.Sync();changeCombat(true)
enter(near,"newest")
units.nameplate3.dead=true
local startCount=#starts
local fallback=press("1",false)
eq(fallback:GetAttribute("combat-branch"),"fallback","unavailable nearby unit selects only the prepared fallback")
eq(#starts,startCount,"fallback never starts a hovered-recipient attempt")
eq(findLast("COMBAT_NAME_POST").targetRestoredObserved,nil,"fallback cannot claim name-bridge restoration")
units.nameplate3.dead=false
local proxy=clickedProxy("1")
run(Names.Snippets.preClick,{self=proxy,control=Names.owner})
proxy.scripts.PreClick(proxy,"LeftButton",false)
eq(proxy.guidHoverLogID,nil,"non-executing key edge does not create a cast attempt")
proxy.scripts.PostClick(proxy,"LeftButton",false)
eq(#starts,startCount,"non-executing edge does not claim a spell window")
units.target=original
run(Names.Snippets.preClick,{self=proxy,control=Names.owner})
proxy.scripts.PreClick(proxy,"LeftButton",true)
units.target=units.nameplate3
proxy.scripts.PostClick(proxy,"LeftButton",true)
eq(findLast("COMBAT_NAME_POST").targetRestoredObserved,false,"failed restoration remains an explicit false readback")
eq(findLast("COMBAT_NAME_POST").recipientProven,false,"failed restore readback never proves a recipient")
units.target=original
logThrows=true
yes(pcall(function() press("1") end),"throwing diagnostic sink never interrupts modeled name action")
logThrows=false
enter(party,"newest")
logThrows=true
yes(pcall(function() press("1") end),"throwing diagnostic sink never interrupts modeled fixed action")
logThrows=false
leave(party,"newest",true)
changeCombat(false)

-- A stale roster identity is not armed, and the saved user's off setting is
-- honored without installing alternate actions or editing permanent bindings.
hovered=nil;NS.HoveredTile=nil
local expectedGUID=near.expectedGUID
near.expectedGUID="Player-stale"
eq(Names.ArmRow(near),false,"identity mismatch before combat prevents a new name snapshot")
eq(Names.Status(near).reason,"invalid_row","stale identity has an explicit ineligible state")
near.expectedGUID=expectedGUID
NS.DB.legacyNameBridgeEnabled=false
Names.RefreshAll();Fixed.Sync()
changeCombat(true)
enter(near,"newest")
eq(active("1"),nil,"disabled saved setting does not route the nearby key")
enter(party,"newest")
eq(active("1"),nil,"disabled saved setting does not route the fixed party key")
eq(Fixed.Sync(),false,"ordinary Lua cannot resync secure fixed attributes in combat")
eq(Names.ArmRow(near),false,"ordinary Lua cannot rebuild name snapshots in combat")
leave(party,"newest",true)
changeCombat(false)
NS.DB.legacyNameBridgeEnabled=true

-- Key-up actions use the player's existing edge preference. A key-down callback
-- cannot start an attempt; the matching release observes the name cast/restore.
hovered=nil;NS.HoveredTile=nil;units.target=original
helpful[1].useOnKeyDown=false
Names.RefreshAll();Fixed.Sync();changeCombat(true)
enter(near,"newest")
local keyUpStarts,keyUpEnds,keyUpRecords=#starts,#ends,#records
local releaseProxy=press("1",false,true)
eq(releaseProxy:GetAttribute("useOnKeyDown"),false,"name proxy retains key-up preference")
eq(releaseProxy.clicks[1],"AnyUp","name proxy registers for the player's release edge")
eq(#starts,keyUpStarts,"press edge of a key-up action does not start an attempt")
eq(#ends,keyUpEnds,"press edge of a key-up action does not finish an attempt")
eq(#records,keyUpRecords,"non-executing press edge records no proxy PRE or POST")
press("1",nil,false)
eq(#starts,keyUpStarts+1,"matching key release starts exactly one name attempt")
eq(#ends,keyUpEnds+1,"matching key release finishes exactly one name attempt")
eq(findLast("COMBAT_KEY_PREPARE").down,false,"name release PRE records the actual release edge")
eq(findLast("COMBAT_NAME_POST").down,false,"name release POST records the same release edge")
eq(findLast("COMBAT_NAME_POST").targetRestoredObserved,true,"key-up name action observes original-target restoration")
eq(UnitGUID("target"),original.guid,"modeled key-up name action restores the original target")
eq(modeledCasts[#modeledCasts].guid,units.nameplate3.guid,"key-up macro model aims at the nearby friend")

-- Turning diagnostics off must only remove observations. The already prepared
-- secure name and fixed routes still execute their modeled actions unchanged.
logEnabled=false
local disabledRecords,disabledStarts,disabledEnds=#records,#starts,#ends
local castCount=#modeledCasts
press("1",nil,false)
eq(#modeledCasts,castCount+1,"disabled diagnostics do not prevent the modeled name cast")
eq(modeledCasts[#modeledCasts].guid,units.nameplate3.guid,"disabled diagnostics retain the named friend recipient in the model")
eq(UnitGUID("target"),original.guid,"disabled diagnostics do not prevent modeled name restoration")
enter(party,"newest")
local fixedRelease=press("1",nil,false)
eq(fixedRelease:GetAttribute("useOnKeyDown"),false,"fixed proxy also retains key-up preference")
eq(fixedRelease.clicks[1],"AnyUp","fixed proxy registers for release")
eq(#modeledCasts,castCount+2,"disabled diagnostics do not prevent the modeled fixed cast")
eq(modeledCasts[#modeledCasts].guid,units.party1.guid,"disabled diagnostics retain the fixed party recipient in the model")
eq(UnitGUID("target"),original.guid,"disabled diagnostics leave the fixed action's original target unchanged")
eq(#records,disabledRecords,"disabled diagnostics record no name or fixed PRE/POST")
eq(#starts,disabledStarts,"disabled diagnostics open no name or fixed observation windows")
eq(#ends,disabledEnds,"disabled diagnostics finish no name or fixed observation windows")
leave(party,"newest",true)
changeCombat(false)
logEnabled=true
helpful[1].useOnKeyDown=true

-- The same controllers also preserve the new canonical-player path when the
-- native nameplate parser rejects the alias while ordinary unit APIs see it.
NameUtil={GetUnmodifiedUnitFullName=function(unit) return units[unit] and units[unit].targetName end}
local aliasParser=SecureCmdOptionParse
SecureCmdOptionParse=function(condition)
    if condition:find("@nameplate",1,true) then return nil end
    return aliasParser(condition)
end
hovered=near;NS.HoveredTile=near;units.target=original
Names.RefreshAll();Fixed.Sync()
eq(Names.Status(near).nameGuardPolicy,"friendly_player_name","canonical player proof enables the new integrated route")
changeCombat(true,true)
eq(active("1").owner,Names.owner,"stationary canonical player retains the name controller despite false native alias conditions")
local canonicalProxy=press("1")
eq(canonicalProxy:GetAttribute("combat-branch"),"player_name_restore","integrated PRE chooses the player-specific restoration branch")
eq(UnitGUID("target"),original.guid,"integrated player-name macro model restores the original enemy")
eq(starts[#starts].route,"combat_player_name","integrated proxy logs the actual player-name route")
eq(findLast("COMBAT_KEY_PREPARE").aliasGuardPublicResult,"[nil]","integrated log retains the rejected alias result as observation")
leave(near,"newest",true)
changeCombat(false)
SecureCmdOptionParse=aliasParser
NameUtil=nil

for _,record in ipairs(records) do
    eq(record.fields.macrotext,nil,"passive diagnostic never stores a macro body")
    eq(record.fields.macroBody,nil,"passive diagnostic never stores user macro content")
end
print("Targets friendly combat route checks:",checks,"passed (Lua integration model; native game casting unverified)")
