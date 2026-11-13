-- A model of ownership/transactions, not the C++ nameplate hit-test engine.
local checks=0
local function eq(a,b,why)
    checks=checks+1
    assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a))
end
local function yes(a,why) eq(not not a,true,why) end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local secret={}
issecretvalue=function(v) return v==secret end
local combat=false
InCombatLockdown=function() return combat end
local spellActions=0
local function forbidden() spellActions=spellActions+1;error("native hover must not execute an action") end
for _,key in ipairs({"CastSpellByID","CastSpellByName","TargetUnit","ClearTarget","RunMacroText","RunMacro",
    "SetOverrideBinding","SetOverrideBindingClick","ClearOverrideBindings","SetBinding","SetCVar","SetRaidTarget"}) do _G[key]=forbidden end
UIParent={}
local function clone(a)
    local r={}
    for i,v in ipairs(a) do
        r[i]={point=v.point,relativeTo=v.relativeTo,relativePoint=v.relativePoint,offsetX=v.offsetX,offsetY=v.offsetY}
    end
    return r
end
local function bounds(region)
    return {{point="TOPLEFT",relativeTo=region,relativePoint="TOPLEFT",offsetX=0,offsetY=0},
        {point="BOTTOMRIGHT",relativeTo=region,relativePoint="BOTTOMRIGHT",offsetX=0,offsetY=0}}
end
local function loadCase()
    combat=false
    local NS={}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
    local calls={map=0,restore=0,motion=0,click=0,proxy=0,forbiddenCombat=0,guid={},records={}}
    local row={unit="nameplate4",expectedGUID="Creature-A",side="enemy",shown=true,click=true,motion=true,pointer=true}
    function row:IsShown() return self.shown end
    function row:IsMouseClickEnabled() return self.clickSecret and secret or self.click end
    function row:IsMouseMotionEnabled() return self.motionSecret and secret or self.motion end
    function row:IsMouseOver() return self.pointer end
    local function mutation()
        if combat then calls.forbiddenCombat=calls.forbiddenCombat+1;error("protected mutation in combat") end
    end
    function row:SetMouseMotionEnabled(v)
        mutation();calls.motion=calls.motion+1
        if self.motionRefuse then return false end
        self.motion=v
        if self.afterMotion then self.afterMotion(self,v) end
        if self.motionThrow then error("motion failure after mutation") end
    end
    function row:SetMouseClickEnabled() mutation();calls.click=calls.click+1;error("click state must stay untouched") end
    row.SetAttribute=forbidden
    local originalRegion={name="native health"}
    local plate={hit=bounds(originalRegion),can=true,forbidden=false}
    function plate:IsForbidden() return self.forbidden end
    function plate:CanChangeHitTestPoints() return self.can end
    function plate:GetHitTestPoints()
        if self.getThrow then error("getter refused") end
        if self.getSecret or self.afterMapSecret and calls.map>0 then return secret end
        return self.hit
    end
    function plate:SetAllHitTestPoints(p)
        mutation();calls.map=calls.map+1
        if self.mapRefuse then return false end
        self.hit=bounds(p)
        if self.onMap then self.onMap(self,p) end
        if self.mapThrow then error("map failure after mutation") end
    end
    function plate:SetHitTestPoints(a)
        mutation();calls.restore=calls.restore+1
        if self.restoreRefuse then return false end
        self.hit=clone(a)
        if self.onRestore then self.onRestore(self) end
    end
    local unit={guid="Creature-A",exists=true,harm=true,dead=false}
    local mouseover
    UnitGUID=function(token)
        calls.guid[token]=(calls.guid[token] or 0)+1
        return token=="mouseover" and mouseover or token=="nameplate4" and unit.guid or nil
    end
    UnitExists=function(token) return token=="nameplate4" and unit.exists end
    UnitCanAttack=function(_,token) return token=="nameplate4" and unit.harm end
    UnitIsDeadOrGhost=function(token) if token=="nameplate4" then return unit.dead end end
    local actualPlate=plate
    C_NamePlate={GetNamePlateForUnit=function(token) return token=="nameplate4" and actualPlate or nil end,
        SetNamePlateSize=forbidden,GetNamePlateSize=function() return 110,40 end}
    local proxyFrames={}
    CreateFrame=function(kind,name,parent)
        mutation();calls.proxy=calls.proxy+1
        eq(kind,"Frame","prototype creates only an inert geometry frame")
        eq(name,nil,"prototype creates no public test button")
        eq(parent,UIParent,"proxy is owned by UIParent")
        local p={shown=true}
        function p:EnableMouse(v) mutation();self.mouse=v end
        function p:ClearAllPoints() mutation();self.row=nil end
        function p:SetAllPoints(anchor) mutation();self.row=anchor end
        function p:Show() mutation();self.shown=true end
        function p:Hide() mutation();self.shown=false end
        p.SetSize,p.SetParent,p.SetFrameStrata,p.SetFrameLevel=forbidden,forbidden,forbidden,forbidden
        proxyFrames[#proxyFrames+1]=p
        return p
    end
    local logging=false
    NS.Diagnostics={Enabled=function() return logging end,Record=function(kind,status)
        calls.records[#calls.records+1]={kind=kind,status=status}
        return true
    end}
    assert(loadfile(root.."EnemyNativeHover.lua"))("MyForeverTargets",NS)
    return {H=NS.EnemyNativeHover,NS=NS,row=row,plate=plate,unit=unit,calls=calls,original=originalRegion,
        proxies=proxyFrames,setMouse=function(v) mouseover=v end,setPlate=function(v) actualPlate=v end,
        logging=function(v) logging=v end}
end

local c=loadCase()
eq(c.H.Status().configured,false,"prototype is off when loaded")
eq(c.H.Status().reason,"disabled","default status is explicitly disabled")
eq(c.calls.map,0,"loading never writes a native hit box")
c.H.Tick();c.H.OnEvent("PLAYER_REGEN_ENABLED")
eq(c.calls.proxy,0,"idle polling creates no frame")
yes(c.H.Enable(c.row),"public enemy native plate can be configured")
eq(c.calls.map,1,"setup maps exactly one native plate")
eq(c.calls.motion,1,"setup changes only motion input once")
eq(c.calls.click,0,"setup never changes click input")
eq(c.row.click,true,"original click input remains true")
eq(c.row.motion,false,"motion input can reach the native plate")
eq(c.proxies[1].mouse,false,"proxy never intercepts mouse input")
eq(c.proxies[1].row,c.row,"proxy follows the selected original row")
eq(c.plate.hit[1].relativeTo,c.proxies[1],"native readback identifies the module's own proxy")
eq(c.H.Status().reason,"configured_unverified","configuration is not native mouseover success")
eq(c.H.Status().matches,false,"no engine mouseover means no match")
c.setMouse("Creature-A")
yes(c.H.Status().matches,"public actual mouseover and pointer geometry may match")
eq(c.H.Status().reason,"native_mouseover_matches","native match is explicit")
c.row.pointer=false
eq(c.H.Status().matches,false,"hovering the same monster in the world does not prove row hover")
c.row.pointer=true;c.setMouse("Creature-other")
eq(c.H.Status().matches,false,"another native mouseover is not accepted")
c.setMouse(secret)
eq(c.H.Status().actualMouseoverGUID,nil,"secret mouseover GUID is never exposed")
c.row.pointer=secret
eq(c.H.Status().pointerOver,nil,"secret geometric hover is not accepted")
c.row.pointer=true
local writes=c.calls.map+c.calls.restore+c.calls.motion
c.H.Status();c.H.Status()
eq(c.calls.map+c.calls.restore+c.calls.motion,writes,"Status is pure readback")
yes(c.H.Disable(),"normal disable fully restores owned state")
eq(c.row.motion,true,"original motion state is restored")
eq(c.calls.restore,1,"owned native anchors are restored once")
eq(c.plate.hit[1].relativeTo,c.original,"original anchor region is restored")
eq(c.H.Status().restoring,false,"successful restore has no pending claim")
eq(c.proxies[1].shown,false,"released proxy is hidden")
local allWrites=c.calls.map+c.calls.restore+c.calls.motion
c.H.Disable();c.H.Tick()
eq(c.calls.map+c.calls.restore+c.calls.motion,allWrites,"disable and idle tick are idempotent")

-- Every unknown capability, identity or snapshot fails before plate/input writes.
local invalidCases={
    {"combat",function() combat=true end},
    {"unknown combat",function() InCombatLockdown=function() return secret end end},
    {"friendly",function(x) x.row.side="friendly" end},
    {"stable target alias",function(x) x.row.unit="target" end},
    {"hidden row",function(x) x.row.shown=false end},
    {"secret side",function(x) x.row.side=secret end},
    {"secret unit",function(x) x.row.unit=secret end},
    {"secret expected identity",function(x) x.row.expectedGUID=secret end},
    {"different live identity",function(x) x.unit.guid="Creature-B" end},
    {"secret live identity",function(x) x.unit.guid=secret end},
    {"nonexistent unit",function(x) x.unit.exists=false end},
    {"unknown existence",function(x) x.unit.exists=secret end},
    {"not hostile",function(x) x.unit.harm=false end},
    {"dead",function(x) x.unit.dead=true end},
    {"unknown death",function(x) x.unit.dead=secret end},
    {"no native plate",function(x) x.setPlate(nil) end},
    {"forbidden plate",function(x) x.plate.forbidden=true end},
    {"unknown forbidden",function(x) x.plate.forbidden=secret end},
    {"restricted tick",function(x) x.plate.can=false end},
    {"unknown permission",function(x) x.plate.can=secret end},
    {"unreadable anchors",function(x) x.plate.getSecret=true end},
    {"throwing anchors",function(x) x.plate.getThrow=true end},
    {"secret anchor member",function(x) x.plate.hit[1]=secret end},
    {"secret relative frame",function(x) x.plate.hit[1].relativeTo=secret end},
    {"secret offset",function(x) x.plate.hit[1].offsetX=secret end},
    {"invalid anchor",function(x) x.plate.hit[1].point="BAD" end},
    {"sparse anchor list",function(x) x.plate.hit[4]=x.plate.hit[1] end},
    {"secret click input",function(x) x.row.clickSecret=true end},
    {"secret motion input",function(x) x.row.motionSecret=true end},
    {"no motion setter",function(x) x.row.SetMouseMotionEnabled=nil end},
    {"no restore API",function(x) x.plate.SetHitTestPoints=nil end},
}
for _,case in ipairs(invalidCases) do
    InCombatLockdown=function() return combat end
    c=loadCase();case[2](c)
    eq(c.H.Enable(c.row),false,case[1].." rejects setup")
    eq(c.calls.map,0,case[1].." has no native map mutation")
    eq(c.calls.motion,0,case[1].." has no input mutation")
    eq(c.H.Status().configured,false,case[1].." never advertises configured")
end
InCombatLockdown=function() return combat end

c=loadCase();c.row.click=false;c.row.motion=false;c.plate.hit={}
yes(c.H.Enable(c.row),"empty public native anchors and disabled original input are valid snapshots")
eq(c.row.click,false,"preexisting disabled click input is preserved")
eq(c.calls.motion,0,"preexisting motion=false needs no input write")
yes(c.H.Disable(),"empty original anchors restore successfully")
eq(#c.plate.hit,0,"empty anchor snapshot is restored faithfully")
eq(c.row.motion,false,"original motion=false is retained")

-- Setter failures may occur after mutating; inverse recovery uses readback.
c=loadCase();c.plate.mapRefuse=true
eq(c.H.Enable(c.row),false,"refused map is not configured")
eq(c.calls.restore,0,"refusal before mapping does not rewrite unchanged anchors")
eq(c.calls.motion,0,"map refusal never disables motion")
c=loadCase();c.plate.mapThrow=true
eq(c.H.Enable(c.row),false,"throw after map is a failed transaction")
eq(c.calls.restore,1,"throw after map rolls back the owned native anchors")
eq(c.H.Status().restoring,false,"successful rollback completes")
c=loadCase();c.row.motionRefuse=true
eq(c.H.Enable(c.row),false,"input refusal fails setup")
eq(c.calls.restore,1,"input failure restores the mapped native anchors")
eq(c.row.motion,true,"input refusal leaves original input")
c=loadCase();c.row.motionThrow=true
eq(c.H.Enable(c.row),false,"throwing input mutation never configures")
eq(c.row.motion,true,"input mutation is reversed even when its setter threw")
eq(c.calls.restore,1,"anchor inverse still runs after input failure")
c.row.motionThrow=false;c.H.Tick()
eq(c.H.Status().restoring,false,"readback resolves a restore that threw after restoring input")

c=loadCase();c.plate.afterMapSecret=true
eq(c.H.Enable(c.row),false,"unreadable map result cannot configure")
yes(c.H.Status().restoring,"unreadable owned map keeps a recovery record")
eq(c.calls.restore,0,"unreadable map ownership is never blindly overwritten")
c.plate.afterMapSecret=false;c.H.Tick()
eq(c.H.Status().restoring,false,"late complete private-proxy readback permits verified inverse recovery")
eq(c.calls.restore,1,"late readable owned mapping is restored only after verification")
c=loadCase();c.plate.onMap=function(p) p.hit[2]=nil end
eq(c.H.Enable(c.row),false,"partial proxy anchors do not prove a fully configured map")
yes(c.H.Status().restoring,"partial map ownership remains explicit")
eq(c.calls.restore,0,"partial map ownership is not blindly overwritten")
c.plate.hit={};c.H.Tick()
eq(c.H.Status().restoring,false,"native reset resolves partial ownership without an old-anchor write")

-- Pending recovery is retained across combat and permission failures.
c=loadCase();yes(c.H.Enable(c.row),"configure for combat recovery")
combat=true;local motionWrites=c.calls.motion
eq(c.H.Disable(),false,"combat disable reports pending recovery")
yes(c.H.Status().restoring,"combat recovery remains visible")
c.H.Tick();c.H.OnEvent("PLAYER_REGEN_DISABLED")
eq(c.calls.motion,motionWrites,"combat cleanup makes no protected input write")
eq(c.calls.restore,0,"combat cleanup makes no protected native write")
eq(c.calls.forbiddenCombat,0,"no attempted protected combat mutation")
combat=false;c.H.OnEvent("PLAYER_REGEN_ENABLED")
eq(c.H.Status().restoring,false,"regen retries and completes recovery")
eq(c.row.motion,true,"regen restores original input")

c=loadCase();yes(c.H.Enable(c.row),"configure for combat beginning during restore")
c.row.afterMotion=function(_,v) if v then combat=true end end
eq(c.H.Disable(),false,"combat starting during input restoration leaves anchors pending")
eq(c.calls.restore,0,"each protected native write rechecks current combat state")
eq(c.calls.forbiddenCombat,0,"synchronous combat transition cannot cause a forbidden mutation attempt")
c.row.afterMotion=nil;combat=false;c.H.Tick()
eq(c.H.Status().restoring,false,"post-transition recovery can complete later")

c=loadCase();c.plate.onMap=function() combat=true end
eq(c.H.Enable(c.row),false,"combat beginning during map setup cannot complete configuration")
eq(c.calls.motion,0,"no input write is attempted after setup enters combat")
eq(c.calls.forbiddenCombat,0,"map-stage combat transition has no protected combat attempt")
combat=false;c.H.Tick()
eq(c.H.Status().restoring,false,"partially configured map recovers after combat")

c=loadCase();yes(c.H.Enable(c.row),"configure for temporary native restriction")
c.plate.can=false
eq(c.H.Disable(),false,"native refusal retains pending anchors")
eq(c.row.motion,true,"input can restore while native-anchor recovery is restricted")
eq(c.H.Status().reason,"restore_not_permitted","pending native permission is explicit")
eq(c.H.Enable(c.row),false,"new setup cannot replace an unfinished recovery")
c.plate.can=true;c.H.Tick()
eq(c.H.Status().restoring,false,"later permission completes the same recovery")

c=loadCase();yes(c.H.Enable(c.row),"configure for unavailable restore input")
c.row.motionSecret=true
eq(c.H.Disable(),false,"unknown owned input cannot be falsely marked restored")
yes(c.H.Status().inputPending,"unreadable input pending flag remains")
c.row.motionSecret=false;c.H.Tick()
eq(c.H.Status().restoring,false,"public input readback permits retry")

-- Another addon/player's changes win; their anchors and click state stay put.
c=loadCase();yes(c.H.Enable(c.row),"configure for external native-anchor change")
local foreign={};c.plate.hit=bounds(foreign);c.row.click=false
c.H.Tick()
eq(c.H.Status().configured,false,"external mapping removes configured claim")
eq(c.calls.restore,0,"external mapping is never overwritten")
eq(c.plate.hit[1].relativeTo,foreign,"external anchor owner is retained")
eq(c.row.click,false,"unowned click changes are not reverted")
eq(c.H.Status().reason,"disabled_external_anchor_change","external ownership is stated")
c=loadCase();yes(c.H.Enable(c.row),"configure for external proxy-relative edit")
local oldProxy=c.proxies[1];c.plate.hit[1].offsetX=9
yes(c.H.Disable(),"external proxy-relative changes release local ownership")
eq(c.calls.restore,0,"external offset change is not overwritten")
eq(oldProxy.shown,true,"relinquished proxy geometry is not hidden underneath another owner")
c.plate.hit=bounds(c.original)
yes(c.H.Enable(c.row),"new setup can use a fresh proxy")
eq(c.proxies[2]~=oldProxy,true,"relinquished proxy is never reused for a different mapping")
c.H.Disable()

c=loadCase();yes(c.H.Enable(c.row),"configure for external input change")
c.row.motion=true;local writesBefore=c.calls.motion
c.H.Tick()
eq(c.H.Status().configured,false,"external motion change deactivates the mapping")
eq(c.calls.motion,writesBefore,"already changed input is not written back")
eq(c.calls.restore,1,"owned anchors can still restore after an external input change")

-- Reordering restores only the saved mapping; a pooled new GUID never gets it.
c=loadCase();yes(c.H.Enable(c.row),"configure for row reorder")
c.row.expectedGUID="Creature-B"
eq(c.H.Status().matches,false,"pure Status notices a rebound row before the next tick")
c.H.Tick()
eq(c.calls.restore,1,"row rebound restores old anchors while native unit identity is still the original")
eq(c.H.Status().configured,false,"row rebound deactivates setup")
c=loadCase();yes(c.H.Enable(c.row),"configure for native unit reuse")
c.unit.guid="Creature-B";c.H.Tick()
eq(c.calls.restore,0,"a reused NPC never receives the old GUID's anchor snapshot")
yes(c.H.Status().restoring,"reuse waits for native reset rather than claiming restoration")
eq(c.row.motion,true,"reused identity still permits restoring owned row input")
c.plate.hit=bounds({});c.H.Tick()
eq(c.H.Status().restoring,false,"native pool reset releases obsolete mapping ownership")
eq(c.calls.restore,0,"pool reset is observed rather than overwritten")

c=loadCase();yes(c.H.Enable(c.row),"configure for plate removal")
c.H.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate99")
yes(c.H.Status().configured,"unrelated nameplate removal does not stop the mapping")
c.H.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate4")
yes(c.H.Status().restoring,"removed plate awaits engine reset even if a stale unit read still matches")
eq(c.calls.restore,0,"removal does not restore a potentially pooled native plate")
c.plate.hit={};c.H.Tick()
eq(c.H.Status().restoring,false,"empty native reset clears removal recovery")

for _,event in ipairs({"PLAYER_LOGOUT","PLAYER_LEAVING_WORLD","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED"}) do
    c=loadCase();yes(c.H.Enable(c.row),"configure before "..event)
    c.H.OnEvent(event)
    eq(c.H.Status().configured,false,event.." stops the one-block prototype")
    eq(c.H.Status().restoring,false,event.." restores immediately when permitted")
end

-- Snapshot copying and deduplicated logging never add an action or global edit.
c=loadCase();local original=c.plate.hit
yes(c.H.Enable(c.row),"configure for snapshot independence")
original[1].offsetX=123
c.H.Disable()
eq(c.plate.hit[1].offsetX,0,"restore uses an independent snapshot, not a mutated API table")
c=loadCase();c.logging(true)
yes(c.H.Enable(c.row),"configure with passive diagnostics")
eq(c.calls.records[1].kind,"ENEMY_NATIVE_HOVER_STATUS","prototype uses its dedicated passive event")
local records=#c.calls.records
c.H.Tick();c.H.Tick()
eq(#c.calls.records,records,"stable polling does not flood diagnostic events")
c.setMouse("Creature-A");c.H.Tick()
eq(#c.calls.records,records+1,"real native mouseover changes are logged")
yes(c.calls.records[#c.calls.records].status.matches,"logged match uses native GUID and row geometry")
c.row.pointer=false;c.H.Tick()
eq(c.calls.records[#c.calls.records].status.matches,false,"pointer departure removes logged row match")
c.logging(false);c.calls.guid.mouseover=0;c.H.Tick()
eq(c.calls.guid.mouseover,0,"disabled diagnostics add no native-mouseover read")
c.logging(true);c.NS.Diagnostics.Record=function() error("logger unavailable") end
eq(pcall(c.H.Tick),true,"logger failure cannot interrupt mapping observation")
c.H.Disable()
local stoppedReads=c.calls.guid.mouseover or 0;c.H.Tick();c.H.Tick()
eq(c.calls.guid.mouseover,stoppedReads,"disabled prototype has no ongoing diagnostic polling")
c.H.Disable();c.H.Disable()
eq(c.calls.guid.mouseover,stoppedReads,"idempotent idle layout cleanup adds no diagnostic mouseover reads")

-- ProbeReadback models a caller from a file-defined normal callback. It only
-- records API outcomes; the model does not emulate Strong taint or certify
-- whether a native client permits measurement in that callback context.
local function probeCase()
    local x=loadCase()
    x.logging(true);x.unit.visible=true
    x.session=1
    x.NS.Diagnostics.Session=function() return x.session end
    local getGUID,getExists,getHarm,getPlate=UnitGUID,UnitExists,UnitCanAttack,C_NamePlate.GetNamePlateForUnit
    x.probeReads={plate=0,anchors=0}
    UnitGUID=function(token) return getGUID(token=="target" and "nameplate4" or token) end
    UnitExists=function(token) return getExists(token=="target" and "nameplate4" or token) end
    UnitCanAttack=function(player,token) return getHarm(player,token=="target" and "nameplate4" or token) end
    UnitIsVisible=function(token) if token=="target" or token=="nameplate4" then return x.unit.visible end end
    C_NamePlate.GetNamePlateForUnit=function(token)
        x.probeReads.plate=x.probeReads.plate+1
        return getPlate(token=="target" and "nameplate4" or token)
    end
    local getHit=x.plate.GetHitTestPoints
    x.plate.GetHitTestPoints=function(p)
        x.probeReads.anchors=x.probeReads.anchors+1
        return getHit(p)
    end
    x.plate.GetUnit=function(p) return p.reportedUnit or "nameplate4" end
    x.plate.UnitFrame={nativeVisual=true}
    return x
end
local function noProbeWrites(x,why)
    eq(x.calls.map,0,why.." maps no native plate")
    eq(x.calls.restore,0,why.." changes no native anchors")
    eq(x.calls.motion,0,why.." changes no motion input")
    eq(x.calls.click,0,why.." changes no click input")
    eq(x.calls.proxy,0,why.." creates no geometry proxy")
    eq(x.H.Status().configured,false,why.." never enables mapping")
end
c=probeCase()
local sampled,capability=c.H.ProbeReadback(c.row)
eq(sampled,true,"capability probe records a public native sample")
eq(#c.calls.records,1,"capability sampling appends one event")
eq(c.calls.records[1].kind,"ENEMY_NATIVE_HOVER_CAPABILITY","capability has a distinct diagnostic event")
eq(capability.version,c.NS.VERSION,"capability sample identifies the loaded addon version")
eq(capability.unit,"nameplate4","capability sample reports the actual supplied alias")
eq(capability.expectedGUID,"Creature-A","capability sample pins the public row identity")
eq(capability.forbiddenCallOK,true,"forbidden API call success is separate from its value")
eq(capability.forbidden,false,"a public false forbidden result is preserved")
eq(capability.canChangeCallOK,true,"CanChange API call success is explicit")
eq(capability.canChange,true,"CanChange's actual public boolean is preserved")
eq(capability.hitTestPointsCallOK,true,"native anchor read call success is explicit")
eq(capability.hitTestPointsReadable,true,"a public anchor array may be counted")
eq(capability.anchorCount,2,"only the anchor count is retained")
eq(capability.plateUnit,"nameplate4","public GetUnit strings are recorded")
eq(capability.unitFrameReadable,true,"public UnitFrame presence can be observed")
eq(capability.hasUnitFrame,true,"native visual frame existence is boolean only")
for key,value in pairs(capability) do
    yes(type(value)=="string" or type(value)=="number" or type(value)=="boolean",
        "capability field "..key.." contains no anchor table, frame or function")
end
noProbeWrites(c,"successful capability read")
sampled,capability=c.H.ProbeReadback(c.row)
eq(sampled,false,"the same GUID and native plate is sampled only once")
eq(capability.reason,"already_recorded","duplicate sample result is explicit")
eq(c.probeReads.anchors,1,"duplicate sampling performs no additional native measurement")
eq(#c.calls.records,1,"duplicate polling cannot flood the log")
c.unit.guid="Creature-B";c.row.expectedGUID="Creature-B"
yes(c.H.ProbeReadback(c.row),"a pooled different GUID on the same plate gets its own sample")
eq(#c.calls.records,2,"new identity is not confused with its earlier sample")
c.unit.guid="Creature-A";c.row.expectedGUID="Creature-A"
yes(c.H.ProbeReadback(c.row),"a returning GUID can be sampled after the native plate was reused")
eq(#c.calls.records,3,"deduplication retains only the most recent identity per native plate")
local another={hit=bounds(c.original),can=true,forbidden=false}
for _,key in ipairs({"IsForbidden","CanChangeHitTestPoints","GetHitTestPoints","GetUnit"}) do another[key]=c.plate[key] end
c.setPlate(another)
yes(c.H.ProbeReadback(c.row),"the same GUID on another actual native plate gets a new sample")
eq(#c.calls.records,4,"deduplication uses both public GUID and actual native object")
noProbeWrites(c,"pooled capability reads")

c=probeCase()
yes(c.H.ProbeReadback(c.row),"first log session records the native identity")
eq(c.H.ProbeReadback(c.row),false,"first log session suppresses its duplicate")
c.logging(false)
c.session=2
eq(#c.calls.records,1,"changing session itself adds no capability event")
c.logging(true)
yes(c.H.ProbeReadback(c.row),"new log session records the same native identity again")
eq(#c.calls.records,2,"each explicit log session retains its own capability sample")
eq(c.probeReads.anchors,2,"reopened log session performs a fresh API measurement")
eq(c.H.ProbeReadback(c.row),false,"new log session still suppresses repeated samples")
noProbeWrites(c,"reopened log session")

for _,sessionMode in ipairs({"missing","restricted"}) do
    c=probeCase()
    if sessionMode=="missing" then c.NS.Diagnostics.Session=nil
    else c.NS.Diagnostics.Session=function() return secret end end
    yes(c.H.ProbeReadback(c.row),sessionMode.." session getter does not prevent capability sampling")
    eq(c.H.ProbeReadback(c.row),false,sessionMode.." session getter preserves per-plate deduplication")
    c.H.ResetProbeReadback()
    yes(c.H.ProbeReadback(c.row),sessionMode.." session getter can use the explicit cache reset hook")
    noProbeWrites(c,sessionMode.." session getter")
end

for _,failure in ipairs({"throw","false","nil","secret"}) do
    c=probeCase()
    local originalRecord=c.NS.Diagnostics.Record
    c.NS.Diagnostics.Record=function()
        if failure=="throw" then error("diagnostic record failure") end
        if failure=="false" then return false end
        if failure=="secret" then return secret end
    end
    eq(c.H.ProbeReadback(c.row),false,failure.." recording does not count as a saved sample")
    c.NS.Diagnostics.Record=originalRecord
    yes(c.H.ProbeReadback(c.row),failure.." recording can be retried for the same native identity")
    eq(#c.calls.records,1,failure.." recording leaves no false deduplication marker")
    eq(c.probeReads.anchors,2,failure.." retry performs the measurement again")
    eq(c.H.ProbeReadback(c.row),false,failure.." retry is deduplicated only after success")
    noProbeWrites(c,failure.." diagnostic retry")
end

c=probeCase();c.row.unit="target";c.plate.reportedUnit="target"
sampled,capability=c.H.ProbeReadback(c.row)
yes(sampled,"target aliases accepted by the real native lookup can be inspected read-only")
eq(capability.unit,"target","read-only target sample remains accurately labelled")
eq(capability.plateUnit,"target","safe native GetUnit target result is retained")
noProbeWrites(c,"target capability read")
eq(c.H.Enable(c.row),false,"capability support does not widen strict nameplate-only Enable")
eq(c.calls.map,0,"target alias inspection still cannot become a mapping transaction")

c=probeCase();c.plate.can=false;c.plate.UnitFrame=nil
sampled,capability=c.H.ProbeReadback(c.row)
yes(sampled,"a refused mutation permission remains useful read-only evidence")
eq(capability.canChangeCallOK,true,"false CanChange is a successful call")
eq(capability.canChange,false,"false CanChange is never reported as API absence")
eq(capability.canChangeReadable,true,"public false permission remains readable")
eq(capability.unitFrameReadable,true,"publicly absent UnitFrame can be observed")
eq(capability.hasUnitFrame,false,"nil UnitFrame is not invented as a visual fallback")
noProbeWrites(c,"refused capability read")

c=probeCase();c.plate.can=secret;c.plate.forbidden=secret;c.plate.UnitFrame=secret
c.plate.GetUnit=function() return secret end
sampled,capability=c.H.ProbeReadback(c.row)
yes(sampled,"secret capability fields do not abort the safe diagnostic")
eq(capability.canChangeCallOK,true,"a call returning a secret may itself have succeeded")
eq(capability.canChangeReadable,false,"secret permission is not assumed public")
eq(capability.canChange,nil,"secret permission value is not recorded")
eq(capability.forbiddenReadable,false,"secret forbidden state is not disclosed")
eq(capability.forbidden,nil,"secret forbidden value is not recorded")
eq(capability.plateUnit,nil,"secret native unit is not serialized")
eq(capability.unitFrameReadable,false,"secret visual frame is not inspected")
eq(capability.hasUnitFrame,nil,"secret presence is not guessed")
noProbeWrites(c,"secret capability read")

for _,outcome in ipairs({"measurement_error","secret_array","invalid_array","empty_array","missing_method"}) do
    c=probeCase()
    if outcome=="measurement_error" then
        c.plate.GetHitTestPoints=function()
            error("NamePlate1:GetHitTestPoints(): Action[FrameMeasurement] failed because[Can't measure restricted regions!] Lua Taint ***ForceTaint_Strong***")
        end
    elseif outcome=="secret_array" then c.plate.getSecret=true
    elseif outcome=="invalid_array" then c.plate.GetHitTestPoints=function() return "invalid" end
    elseif outcome=="empty_array" then c.plate.hit={}
    else c.plate.GetHitTestPoints=nil end
    sampled,capability=c.H.ProbeReadback(c.row)
    yes(sampled,outcome.." still yields one capability record")
    eq(capability.hitTestPointsCallOK,outcome~="measurement_error" and outcome~="missing_method",
        outcome.." preserves call success independently from result access")
    eq(capability.hitTestPointsReadable,outcome=="empty_array",outcome.." has the correct readability result")
    if outcome=="measurement_error" then
        yes(capability.hitTestPointsError:find("FrameMeasurement",1,true),"native measurement failure reason is retained")
        yes(capability.hitTestPointsError:find("ForceTaint_Strong",1,true),"reported taint label is retained as evidence")
    elseif outcome=="empty_array" then eq(capability.anchorCount,0,"a successful empty native result is recorded as zero")
    else eq(capability.anchorCount,nil,outcome.." records no invented count") end
    noProbeWrites(c,outcome)
end
c=probeCase();c.plate.GetHitTestPoints=function() error(secret) end
sampled,capability=c.H.ProbeReadback(c.row)
eq(capability.hitTestPointsError,"[restricted-error]","secret thrown errors remain undisclosed")
eq(capability.anchorCount,nil,"secret errors do not yield a count")
noProbeWrites(c,"secret error read")

for _,case in ipairs({
    {"hidden",function(x) x.row.shown=false end},
    {"friendly",function(x) x.row.side="friendly" end},
    {"secret expected GUID",function(x) x.row.expectedGUID=secret end},
    {"secret alias",function(x) x.row.unit=secret end},
    {"different live GUID",function(x) x.unit.guid="Creature-B" end},
    {"invisible unit",function(x) x.unit.visible=false end},
    {"secret visibility",function(x) x.unit.visible=secret end},
    {"non-hostile unit",function(x) x.unit.harm=false end},
    {"no live unit",function(x) x.unit.exists=false end},
}) do
    c=probeCase();case[2](c)
    eq(c.H.ProbeReadback(c.row),false,case[1].." cannot supply a native capability identity")
    eq(c.probeReads.plate,0,case[1].." is rejected before reading the native object")
    eq(#c.calls.records,0,case[1].." does not append misleading native evidence")
    noProbeWrites(c,case[1].." capability request")
end

c=probeCase();c.logging(false)
local extraReads=0
local function unexpectedRead() extraReads=extraReads+1;error("logging-off read") end
UnitGUID,UnitExists,UnitCanAttack,UnitIsVisible=unexpectedRead,unexpectedRead,unexpectedRead,unexpectedRead
C_NamePlate.GetNamePlateForUnit=unexpectedRead
c.row.IsShown=unexpectedRead;c.plate.GetHitTestPoints=unexpectedRead
c.NS.Diagnostics.Session=unexpectedRead
c.H.ResetProbeReadback()
eq(c.H.ProbeReadback(c.row),false,"logging disabled bypasses capability observation")
eq(extraReads,0,"logging-off capability calls perform no session, unit, frame or geometry reads")
eq(#c.calls.records,0,"logging-off capability calls append no record")
eq(c.calls.map+c.calls.restore+c.calls.motion+c.calls.click+c.calls.proxy,0,"logging-off calls create or mutate nothing")
c=probeCase();c.NS.Diagnostics.Record=function() error("diagnostic record failure") end
eq(pcall(c.H.ProbeReadback,c.row),true,"logging failure cannot escape the read-only callback")
noProbeWrites(c,"logging failure")
eq(spellActions,0,"no spell, target, macro, binding, global size, marker or unrelated geometry action was executed")
print("Targets enemy native hover simulated checks: "..checks.."; native hit testing and mouseover remain in-game checks")
