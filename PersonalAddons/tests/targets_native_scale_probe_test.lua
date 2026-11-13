-- Transaction/geometry simulation only; does not simulate C++ hit testing.
local checks=0
local function eq(a,b,why)
    checks=checks+1
    assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a))
end
local function yes(v,why) eq(not not v,true,why) end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local secret=setmetatable({}, {__add=function() error("secret math") end,__mul=function() error("secret math") end})
local function clone(a)
    local out={}
    for i,x in ipairs(a) do out[i]={point=x.point,relativePoint=x.relativePoint,relativeTo=x.relativeTo,offsetX=x.offsetX,offsetY=x.offsetY} end
    return out
end
local function edges(v)
    return {{point="TOPLEFT",relativePoint="TOPLEFT",relativeTo=v,offsetX=0,offsetY=0},
        {point="BOTTOMRIGHT",relativePoint="BOTTOMRIGHT",relativeTo=v,offsetX=0,offsetY=0}}
end
local function loadCase(options)
    local cfg=options or {}
    local combat=false
    local calls={frames=0,hooks=0,mutations=0,protectedInCombat=0,actions=0,records={},messages={}}
    local function protectedWrite()
        calls.mutations=calls.mutations+1
        if combat then calls.protectedInCombat=calls.protectedInCombat+1;error("native write in combat") end
    end
    local function action() calls.actions=calls.actions+1;error("probe attempted a gameplay action") end
    for _,key in ipairs({"FocusUnit","ClearFocus","TargetUnit","ClearTarget","TargetNearestEnemy","RunMacroText","RunMacro",
        "CastSpellByID","CastSpellByName","SetOverrideBinding","SetOverrideBindingClick","ClearOverrideBindings","SetBinding","SetCVar"}) do _G[key]=action end
    issecretvalue=function(v) return v==secret end
    InCombatLockdown=function() return combat end
    SpellIsTargeting=function() return cfg.cursorSpell or false end
    CursorHasItem=function() return cfg.cursorItem or false end
    GetBuildInfo=function() return "1.60.1","70888","Nov 9 2026",16001 end
    UIParent={}
    function UIParent:GetEffectiveScale() return cfg.rootScale or .5 end
    function UIParent:GetWidth() return cfg.screenWidth or 800 end
    function UIParent:GetHeight() return cfg.screenHeight or 600 end
    local row={side="enemy",unit="nameplate1",expectedGUID="Creature-A",shown=true,visible=true}
    function row:IsShown() return self.shown end
    function row:IsVisible() return self.visible end
    row.SetAttribute,row.SetMouseMotionEnabled,row.SetMouseClickEnabled=action,action,action
    local unit={exists=true,harm=true,dead=false,player=false,guid="Creature-A"}
    local mouseover,mouseX,mouseY
    UnitGUID=function(token) return token=="nameplate1" and unit.guid or token=="mouseover" and mouseover or nil end
    UnitExists=function(token) return token=="nameplate1" and unit.exists or token=="mouseover" and mouseover~=nil or false end
    UnitCanAttack=function(_,token) return token=="nameplate1" and unit.harm or false end
    UnitIsPlayer=function(token) return token=="nameplate1" and unit.player or false end
    UnitIsDeadOrGhost=function(token) return token=="nameplate1" and unit.dead or false end
    GetCursorPosition=function() return mouseX,mouseY end
    local region={}
    local plate={scale=1,hit=edges(region),can=true,forbidden=false}
    local uf={scale=1,forbidden=false}
    plate.UnitFrame=uf
    local updateHit=function() end
    NamePlateUnitFrameMixin={UpdateHitTestArea=updateHit}
    uf.UpdateHitTestArea=updateHit
    function uf:GetNamePlateFrame() return plate end
    function uf:IsForbidden() return self.forbidden end
    function uf:GetScale() return self.scale end
    function uf:SetScale(v)
        protectedWrite();self.scale=v
        if v<1 and cfg.crossNative then cfg.crossNative=false;plate:SetScale(3) end
        if v<1 and cfg.crossHit then cfg.crossHit=false;plate:SetHitTestPoints(edges(cfg.foreignRegion)) end
        if cfg.childThrowOnce then cfg.childThrowOnce=false;error("partial child scale failure") end
    end
    function plate:IsForbidden() return self.forbidden end
    function plate:GetScale() return self.scale end
    function plate:GetEffectiveScale() return UIParent:GetEffectiveScale()*self.scale end
    function plate:SetScale(v)
        protectedWrite()
        self.scale=cfg.scaleClamp and math.min(v,cfg.scaleClamp) or v
        if v>1 and cfg.nestedExternal then cfg.nestedExternal=false;self:SetScale(3) end
        if v>1 and cfg.nativeThrowOnce then cfg.nativeThrowOnce=false;error("partial native scale failure") end
    end
    function plate:GetRect()
        if cfg.secretGeometry then return secret,200,80,40 end
        local w,h=cfg.largeBefore and 900 or 80,cfg.largeBefore and 700 or 40
        if cfg.noExpansion then return (400-w/2)/self.scale,(300-h/2)/self.scale,w/self.scale,h/self.scale end
        return (400+(cfg.nativeMoveX or 0))/self.scale-w/2,300/self.scale-h/2,w,h
    end
    function plate:CanChangeHitTestPoints() return self.can end
    function plate:GetHitTestPoints() return clone(self.hit) end
    function plate:SetAllHitTestPoints(v)
        protectedWrite();self.hit=edges(v)
        if cfg.nestedClear then cfg.nestedClear=false;self:ClearAllHitTestPoints() end
        if cfg.mapThrowOnce then cfg.mapThrowOnce=false;table.remove(self.hit,2);error("partial map failure") end
    end
    function plate:SetHitTestPoints(v) protectedWrite();self.hit=clone(v) end
    function plate:ClearAllHitTestPoints() protectedWrite();self.hit={} end
    local actualPlate=plate
    C_NamePlate={GetNamePlateForUnit=function(token) return token=="nameplate1" and actualPlate or nil end,SetNamePlateSize=action}
    hooksecurefunc=function(v,key,hook)
        calls.hooks=calls.hooks+1
        if cfg.hookRefused then error("hook unavailable") end
        local old=v[key]
        v[key]=function(self,...)
            local result={old(self,...)}
            hook(self,...)
            return unpack(result)
        end
    end
    local frames={}
    CreateFrame=function(kind,name,parent)
        calls.frames=calls.frames+1
        eq(kind,"Frame","probe creates no action buttons")
        eq(name,nil,"probe creates only private frames")
        local f={shown=true,scripts={},events={},scale=1}
        function f:EnableMouse(v) self.mouse=v end
        function f:SetScript(k,v) self.scripts[k]=v end
        function f:RegisterEvent(k) self.events[k]=true end
        function f:SetFrameStrata(v) self.strata=v end
        function f:SetBackdrop(v) self.backdrop=v end
        function f:SetBackdropColor() end
        function f:SetBackdropBorderColor() end
        function f:CreateFontString()
            local text={}
            function text:SetAllPoints() end
            function text:SetText(v) self.text=v end
            return text
        end
        function f:ClearAllPoints() end
        function f:SetScale(v) self.scale=v end
        function f:SetSize(w,h) self.width,self.height=w,h end
        function f:SetPoint(_,_,_,x,y) self.left,self.bottom=x,y end
        function f:Show() self.shown=true end
        function f:Hide() self.shown=false end
        frames[#frames+1]=f
        return f
    end
    local NS={UI={enemy={tiles={row}}}}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
    NS.Print=function(v) calls.messages[#calls.messages+1]=v end
    NS.Diagnostics={Start=function() calls.started=(calls.started or 0)+1 end,
        Record=function(kind,fields) calls.records[#calls.records+1]={kind=kind,fields=fields} end}
    NS.FocusAPIProbe={active=false};NS.FocusCycle={IsActive=function() return cfg.cycleActive==true end}
    NS.EnemyNativeHover={Status=function() return {configured=cfg.hoverActive==true} end}
    NS.EnemyNativeTrial={Status=function() return {active=cfg.trialActive==true} end}
    assert(loadfile(root.."NativeScaleProbe.lua"))("MyForeverTargets",NS)
    local function tick(delta) frames[1].scripts.OnUpdate(frames[1],delta) end
    local function event(e,u) frames[1].scripts.OnEvent(frames[1],e,u) end
    local function hover(g,offset)
        local card=frames[2]
        mouseX=(card.left+card.width/2+(offset or 0))*UIParent:GetEffectiveScale()
        mouseY=(card.bottom+card.height/2)*UIParent:GetEffectiveScale()
        mouseover=g
    end
    local function restored(label)
        eq(plate.scale,1,label.." restores original native scale")
        eq(uf.scale,1,label.." restores original visual scale")
        eq(plate.hit[1].relativeTo,region,label.." restores original hit area")
        eq(#plate.hit,2,label.." restores complete original anchors")
        eq(NS.NativeScaleProbe.Status().restoring,false,label.." finishes restoration")
        eq(calls.actions,0,label.." executes no gameplay action")
        eq(calls.protectedInCombat,0,label.." performs no protected combat writes")
    end
    return {P=NS.NativeScaleProbe,NS=NS,cfg=cfg,calls=calls,row=row,unit=unit,plate=plate,uf=uf,frames=frames,
        region=region,tick=tick,event=event,hover=hover,restored=restored,setCombat=function(v) combat=v end,
        setActualPlate=function(v) actualPlate=v end}
end

do
    local c=loadCase()
    eq(c.calls.frames,0,"inactive import creates no frame")
    eq(c.calls.hooks,0,"inactive import installs no hook")
    eq(c.P.Status().active,false,"inactive status is disabled")
    eq(c.P.Stop("unused"),true,"inactive stop is a harmless success")
    eq(c.calls.mutations,0,"inactive status/stop never touches native geometry")
end
for _,option in ipairs({{cursorSpell=true},{cursorItem=true},{hoverActive=true},{trialActive=true},{cycleActive=true},{secretGeometry=true}}) do
    local c=loadCase(option)
    eq(c.P.Command("1"),false,"preflight rejects unsupported or occupied state")
    eq(c.calls.mutations,0,"preflight refusal does not alter native geometry")
end
do
    local c=loadCase();c.setCombat(true)
    eq(c.P.Command("1"),false,"start is restricted to confirmed out of combat")
    eq(c.calls.frames,0,"combat refusal creates no presentation")
    eq(c.calls.mutations,0,"combat refusal writes nothing")
end
do
    local c=loadCase();c.NS.FocusAPIProbe.active=true
    eq(c.P.Command("1"),false,"existing FocusAPIProbe activity is mutually exclusive")
    c.NS.FocusAPIProbe.active=false;c.unit.guid="Creature-B"
    eq(c.P.Command("1"),false,"stale row GUID cannot prepare native mapping")
    c.unit.guid="Creature-A";c.unit.player=true
    eq(c.P.Command("1"),false,"probe accepts only NPCs")
end
do
    local c=loadCase()
    yes(c.P.Command("1"),"public native scale expansion can prepare an observation")
    eq(c.plate.scale,8,"probe changes native base scale")
    eq(c.uf.scale,.125,"inverse child scale preserves native visual size")
    eq(c.P.Status().matches,false,"configured geometry alone is not a native hit success")
    c.hover("Creature-B");c.tick(.1)
    eq(c.P.Status().matches,false,"wrong native mouseover identity is not accepted")
    c.hover("Creature-A");c.tick(.1)
    local s=c.P.Status()
    yes(s.pointerOver and s.outsideBefore and s.insideExpanded,"cursor is in isolated expanded-only area in root UI units")
    eq(s.matches,true,"only exact native mouseover GUID in the isolated area is accepted")
    local count=#c.calls.records;c.tick(.1)
    eq(#c.calls.records,count,"unchanged hover samples are deduplicated")
    c.tick(15)
    eq(c.frames[2].shown,false,"deadline hides temporary card")
    c.restored("deadline")
end
do
    local c=loadCase({rootScale=.8})
    yes(c.P.Command("1"),"non-default UIParent scale is supported")
    c.hover("Creature-A");c.tick(.1)
    eq(c.P.Status().matches,true,"physical pointer and native bounds use the same UIParent scale conversion")
    c.P.Stop("test");c.restored("scale conversion")
end
for _,option in ipairs({{noExpansion=true},{largeBefore=true},{scaleClamp=2},{nativeThrowOnce=true},{childThrowOnce=true},{mapThrowOnce=true}}) do
    local c=loadCase(option)
    eq(c.P.Command("1"),false,"failed or uninformative setup is not reported as prepared")
    c.restored("setup failure")
end
do
    local c=loadCase({nestedExternal=true})
    eq(c.P.Command("1"),false,"nested external scale update aborts preparation")
    eq(c.plate.scale,3,"outer own setter does not reclaim nested external write")
    eq(c.uf.scale,1,"independently owned child scale still restores")
    eq(c.P.Status().ownershipLost,true,"external ownership loss remains explicit")
    eq(c.P.Status().restoring,false,"external ownership is relinquished without an endless restore")
end
do
    local c=loadCase({nestedClear=true})
    eq(c.P.Command("1"),false,"nested external ClearAll aborts mapping")
    eq(#c.plate.hit,0,"external ClearAll anchors are not overwritten by old anchors")
    eq(c.plate.scale,1,"owned native scale restores after external clear")
    eq(c.uf.scale,1,"owned visual scale restores after external clear")
    eq(c.P.Status().ownershipLost,true,"external ClearAll is explicitly recorded")
end
do
    local c=loadCase({crossNative=true})
    eq(c.P.Command("1"),false,"cross-channel external native update aborts preparation")
    eq(c.plate.scale,3,"native change during child setup is never overwritten or reclaimed")
    eq(c.uf.scale,1,"owned child compensation still restores after cross-channel write")
end
do
    local foreign={}
    local c=loadCase({crossHit=true,foreignRegion=foreign})
    eq(c.P.Command("1"),false,"cross-channel hit area update aborts preparation")
    eq(c.plate.hit[1].relativeTo,foreign,"foreign anchors written during child setup remain owned by their writer")
    eq(c.plate.scale,1,"native scale is not enlarged after foreign hit area update")
    eq(c.uf.scale,1,"owned child scale restores after foreign hit area update")
end
do
    local c=loadCase();yes(c.P.Command("1"),"external ownership case starts")
    c.plate:SetScale(3);c.tick(.1)
    eq(c.plate.scale,3,"later external native scale is preserved")
    eq(c.uf.scale,1,"owned inverse visual scale restores after foreign base scale")
    eq(c.plate.hit[1].relativeTo,c.region,"owned hit area restores despite foreign scale")
    eq(c.P.Status().ownershipLost,true,"foreign write is logged as ownership loss")
end
do
    local c=loadCase();yes(c.P.Command("1"),"external anchors case starts")
    local foreign={};c.plate:SetHitTestPoints(edges(foreign));c.tick(.1)
    eq(c.plate.hit[1].relativeTo,foreign,"external replacement anchors are never overwritten")
    eq(c.plate.scale,1,"other owned native scale restores")
    eq(c.uf.scale,1,"other owned visual scale restores")
end
do
    local c=loadCase();yes(c.P.Command("1"),"combat restore case starts")
    c.setCombat(true);local writes=c.calls.mutations;c.event("PLAYER_REGEN_DISABLED")
    eq(c.calls.mutations,writes,"combat interruption defers native restoration")
    eq(c.P.Status().active,false,"combat immediately ends observation")
    eq(c.P.Status().restoring,true,"deferred native restoration remains explicit")
    eq(c.frames[2].shown,false,"combat hides only private unprotected card")
    c.setCombat(false);c.event("PLAYER_REGEN_ENABLED");c.restored("combat end")
end
for _,change in ipairs({"guid","plate","hidden","dead","focusprobe","focuscycle","click"}) do
    local c=loadCase();yes(c.P.Command("1"),"interruption case starts: "..change)
    if change=="guid" then c.unit.guid="Creature-B"
    elseif change=="plate" then c.setActualPlate({})
    elseif change=="hidden" then c.row.visible=false
    elseif change=="dead" then c.unit.dead=true
    elseif change=="focusprobe" then c.NS.FocusAPIProbe.active=true
    elseif change=="focuscycle" then c.cfg.cycleActive=true
    elseif change=="click" then c.event("GLOBAL_MOUSE_DOWN","RightButton") end
    c.tick(.1);c.restored(change)
end
for _,e in ipairs({"PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","NAME_PLATE_UNIT_REMOVED"}) do
    local c=loadCase();yes(c.P.Command("1"),"world lifecycle case starts")
    c.event(e,"nameplate1");c.restored(e)
end
for _,change in ipairs({"nativeMoveX","rootScale","screenWidth"}) do
    local c=loadCase();yes(c.P.Command("1"),"geometry drift case starts")
    c.hover("Creature-A")
    c.cfg[change]=change=="nativeMoveX" and -250 or change=="rootScale" and .8 or 1200
    eq(c.P.Status().matches,false,"moving geometry cannot produce an isolated hit success")
    c.tick(.1);c.restored("geometry drift")
end
do
    local c=loadCase();yes(c.P.Command("1"),"sampling error case starts")
    c.row.IsVisible=function() error("unexpected observer failure") end
    c.tick(.1);c.restored("observer error")
end
for _,mode in ipairs({"absent","present","moved"}) do
    local c=loadCase();yes(c.P.Command("1"),"two-phase case starts")
    c.hover("Creature-A");c.tick(.1)
    c.tick(9.9)
    eq(c.P.Status().phase,"control","ten seconds transitions to original-size control")
    eq(c.P.Status().active,true,"control keeps the same explicit experiment active")
    eq(c.plate.scale,1,"control restores native scale before observing")
    eq(c.uf.scale,1,"control restores visual scale before observing")
    eq(c.plate.hit[1].relativeTo,c.region,"control restores original hit anchors")
    eq(c.frames[2].shown,true,"control retains the same inert card")
    local writes=c.calls.mutations
    if mode=="absent" then c.hover(nil) else c.hover("Creature-A",mode=="moved" and .75 or 0) end
    c.tick(.3);c.tick(5)
    eq(c.calls.mutations,writes,"control and completion do not perform another native mutation")
    local s=c.P.Status()
    eq(s.scaledMatchObserved,true,"scaled identity sample is retained separately")
    eq(s.samePointControlObserved,mode~="moved","only same-point control samples qualify")
    eq(s.samePointControlMatched,mode=="present","persistent native identity in control is distinguished")
    eq(s.scaleEffectProven,false,"two-phase observations are never declared a scale bypass proof")
    c.restored("control completion")
end
print("Native scale probe simulated checks: "..checks.." passed; C++ hit testing and live mouseover remain untested.")
