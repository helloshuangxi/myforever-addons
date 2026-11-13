-- Native UI ownership model only; does not execute the C++ hit-test engine.
local checks=0
local function eq(a,b,why) checks=checks+1;assert(a==b,why..": "..tostring(a).." ~= "..tostring(b)) end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local secret={}
issecretvalue=function(v) return v==secret end
local forbiddenActions=0
local function forbidden() forbiddenActions=forbiddenActions+1;error("forbidden trial action") end
for _,name in ipairs({"CastSpellByID","CastSpellByName","TargetUnit","ClearTarget","RunMacroText","RunMacro",
    "SetOverrideBinding","SetOverrideBindingClick","ClearOverrideBindings","SetBinding","SetCVar","SetRaidTarget"}) do _G[name]=forbidden end
local function fixture()
    local ns={};assert(loadfile(root.."Core.lua"))("MyForeverTargets",ns)
    local c={combat=false,frames={},writes={},hooks={},sizeHooks={},records={},w=140,h=52,mouse=nil,reads=0}
    GetTime=nil;MouseIsOver=nil;GetCursorPosition=function() return c.cursorX,c.cursorY end
    local function mutate(key,obj,value)
        eq(c.combat,false,"no protected mutation in combat: "..key)
        c.writes[#c.writes+1]={key=key,obj=obj,value=value}
        if obj and obj.fail==key then return false end
        return true
    end
    local function frame(parent)
        local f={parent=parent,shown=true}
        function f:IsShown() return self.shown end
        function f:IsMouseOver() return self.pointer==true end
        function f:GetRect() if c.geometry then return 100,200,90,56 end end
        function f:GetEffectiveScale() return c.scale or 1 end
        function f:Hide() if not mutate("Hide",self) then return false end;self.shown=false end
        function f:Show() if not mutate("Show",self) then return false end;self.shown=true end
        function f:EnableMouse(v) if not mutate("EnableMouse",self,v) then return false end;self.mouse=v end
        function f:SetSize(w,h) if not mutate("SetSize",self) then return false end;self.w,self.h=w,h end
        function f:SetPoint(...) if not mutate("SetPoint",self) then return false end;self.points={...} end
        function f:SetAllPoints(p) if not mutate("SetAllPoints",self,p) then return false end;self.anchor=p end
        function f:ClearAllPoints() if not mutate("ClearAllPoints",self) then return false end;self.anchor=nil end
        function f:SetFrameStrata(v) if not mutate("SetFrameStrata",self) then return false end;self.strata=v end
        function f:SetColorTexture(...) self.color={...} end
        function f:SetText(v) self.text=v end
        function f:SetWidth(v) self.width=v end
        function f:CreateTexture() return frame(self) end
        function f:CreateFontString() if c.failFont then return nil end;return frame(self) end
        return f
    end
    UIParent=frame(nil)
    CreateFrame=function(kind,name,parent)
        eq(kind,"Frame","only mouse-disabled nonsecure frames created")
        eq(name,nil,"trial creates no action button")
        local f=frame(parent);c.frames[#c.frames+1]=f;return f
    end
    InCombatLockdown=function() c.reads=c.reads+1;return c.combat end
    GetPhysicalScreenSize=function() return 2560,1440 end
    NamePlateSetupOptions={healthBarHeight=12}
    NamePlateUnitFrameMixin={}
    function NamePlateUnitFrameMixin:UpdateHitTestArea(options)
        if not mutate("UpdateHitTestArea",self) then return false end
        eq(options,NamePlateSetupOptions,"native defaults use current public setup options")
        self.restores=(self.restores or 0)+1;self.plate.hit=self
    end
    function c.newPlate(unit,id)
        local p=frame(UIParent);p.unit=unit;p.guid=id;p.can=true;p.forbidden=false
        function p:IsForbidden() return self.forbidden end
        function p:CanChangeHitTestPoints() return self.can end
        function p:GetUnit() return self.unit end
        p.GetHitTestPoints=forbidden -- Measuring restricted native anchors is never attempted.
        function p:SetAllHitTestPoints(proxy)
            if not mutate("SetAllHitTestPoints",self,proxy) then return false end
            self.hit=proxy
            if self.throwAfterMap then error("partial native map") end
            if self.refuseEvent then c.T.OnEvent("ADDON_ACTION_FORBIDDEN","MyForeverTargets") end
            if self.combatAfterMap then c.combat=true end
        end
        function p:SetStackingBoundsFrame(box)
            if not mutate("SetStackingBoundsFrame",self,box) then return false end
            self.stack=box
        end
        local uf=frame(p);uf.plate=p
        function uf:GetNamePlateFrame() return self.plate end
        uf.UpdateHitTestArea=NamePlateUnitFrameMixin.UpdateHitTestArea
        p.UnitFrame=uf;p.hit=uf;uf.anchor=p
        return p
    end
    c.plate=c.newPlate("nameplate1","Creature-A")
    c.other=c.newPlate("nameplate2","Creature-B")
    c.plates={c.plate,c.other}
    c.units={nameplate1=c.plate,nameplate2=c.other}
    UnitGUID=function(unit) c.reads=c.reads+1;return unit=="mouseover" and c.mouse or c.units[unit] and c.units[unit].guid end
    UnitExists=function(unit) return c.units[unit]~=nil end
    UnitCanAttack=function(_,unit) return c.units[unit]~=nil end
    UnitIsDeadOrGhost=function(unit) return c.units[unit] and c.units[unit].dead==true or false end
    UnitName=function(unit) return c.units[unit] and "测试怪物" end
    C_NamePlate={GetNamePlateForUnit=function(unit) return c.units[unit] end,
        GetNamePlates=function() return c.plates end,
        GetNamePlateSize=function() if c.secretSize then return secret,secret end;return c.w,c.h end,
        SetNamePlateSize=function(w,h)
            if not mutate("SetNamePlateSize") then return false end
            if c.refuseSize then return false end
            c.w,c.h=c.clamp and math.min(w,512) or w,c.clamp and math.min(h,256) or h
            for _,fn in ipairs(c.hooks.UpdateNamePlateSize or {}) do fn(NamePlateDriverFrame) end
            if c.afterSize then local fn=c.afterSize;c.afterSize=nil;fn() end
            for _,fn in ipairs(c.sizeHooks) do fn(w,h) end
            if c.throwSize then c.throwSize=false;error("partial size mutation") end
        end}
    NamePlateDriverFrame={OnNamePlateAdded=function() end,OnNamePlateRemoved=function() end,
        UpdateNamePlateOptions=function() end,UpdateNamePlateSize=function() end}
    hooksecurefunc=function(target,key,fn)
        if target==C_NamePlate then
            eq(key,"SetNamePlateSize","only public global size setter is additionally observed")
            c.sizeHooks[#c.sizeHooks+1]=fn
        else
            eq(target,NamePlateDriverFrame,"only trusted native driver gets a passive post-hook")
            c.hooks[key]=c.hooks[key] or {};table.insert(c.hooks[key],fn)
        end
    end
    c.row={side="enemy",unit="nameplate1",expectedGUID="Creature-A",IsShown=function() return true end}
    ns.Diagnostics={Enabled=function() return true end,Record=function(kind,fields)
        c.records[#c.records+1]={kind=kind,fields=fields};return true
    end}
    assert(loadfile(root.."EnemyNativeTrial.lua"))("MyForeverTargets",ns)
    c.T=ns.EnemyNativeTrial;c.ns=ns
    function c.hook(key,unit) for _,fn in ipairs(c.hooks[key] or {}) do fn(NamePlateDriverFrame,unit) end end
    return c
end
local c=fixture()
eq(c.T.Status().active,false,"trial defaults to off")
local reads=c.reads
c.T.Tick(10);c.T.OnEvent("PLAYER_REGEN_ENABLED")
eq(c.reads,reads,"idle callback performs no native polling")
eq(#c.frames,0,"loading/idle creates no frame")
eq(c.T.Enable(c.row),true,"native owners allow an explicit trial")
eq(c.w,15360,"native global width is enlarged with public setter")
eq(c.h,15360,"native global height is enlarged with public setter")
eq(c.T.Status().reason,"accepted_unmeasured","setter acceptance is not treated as a measured hit")
eq(c.T.Status().matches,false,"no native mouseover is unconfirmed")
local card=c.frames[1]
eq(card.mouse,false,"the displayed card does not intercept input")
eq(c.plate.hit.parent,c.plate,"private native hit proxy is a real-plate child")
eq(c.plate.hit.anchor,card,"native hit proxy anchors to the separate top card")
eq(c.plate.UnitFrame.anchor.w,140,"world unit frame retains its normal width")
eq(c.other.UnitFrame.anchor.h,52,"all existing world frames retain normal height")
eq(c.plate.UnitFrame.anchor.points[1],"BOTTOM","normal box sits at native bottom")
card.pointer=true;c.mouse="Creature-A"
eq(c.T.Status().matches,true,"native GUID plus card geometry and current identity confirms mouseover")
card.pointer=false
eq(c.T.Status().matches,false,"body mouseover cannot confirm the separate card")
card.pointer=true;c.mouse="Creature-B"
eq(c.T.Status().matches,false,"different native mouseover never matches")
c.mouse=secret
eq(c.T.Status().actualMouseoverGUID,nil,"secret mouseover is not disclosed")
c.mouse="Creature-A"
c.geometry=true;c.scale=2;c.cursorX,c.cursorY=240,450;card.pointer=false
eq(c.T.Status().matches,true,"public physical geometry works even when disabled card has no engine mouse focus")
c.cursorX=500
eq(c.T.Status().matches,false,"physical pointer outside card cannot match the world unit")
c.geometry=false;card.pointer=true
c.row.unit="nameplate2";c.row.expectedGUID="Creature-B"
eq(c.T.Status().matches,true,"ordinary original-row rebinding does not alter the frozen trial identity")
local n=#c.records;c.T.Tick(.1);c.T.Tick(.1)
eq(#c.records,n+1,"unchanged live status logs once")
eq(c.T.Disable(),true,"native defaults can be restored")
eq(c.w,140,"original global size restored")
eq(c.plate.UnitFrame.anchor,c.plate,"native unit frame restored to native plate default")
eq(c.other.UnitFrame.anchor,c.other,"other world unit frame defaults restored too")
eq(c.plate.hit,c.plate.UnitFrame,"current native default hit area restored")
eq(c.plate.stack,c.plate.UnitFrame,"stock UF is used as default stacking bounds")
eq(card.shown,false,"temporary top card hidden after cleanup")
eq(c.T.Status().reason,"native_defaults_restored_unmeasured","restoration does not claim an exact old snapshot")
local writes=#c.writes;c.T.Disable();c.T.Tick(100)
eq(#c.writes,writes,"completed cleanup and idle are idempotent")

for _,case in ipairs({
    {"combat",function(x)x.combat=true end},
    {"secret size",function(x)x.secretSize=true end},
    {"wrong GUID",function(x)x.row.expectedGUID="Creature-else" end},
    {"wrong alias",function(x)x.row.unit="target" end},
    {"friendly",function(x)x.row.side="friendly" end},
    {"native owner missing",function(x)x.plate.UnitFrame=nil end},
    {"other native owner missing",function(x)x.other.UnitFrame=nil end},
    {"native method replaced",function(x)x.plate.UnitFrame.UpdateHitTestArea=function()end end},
    {"forbidden plate",function(x)x.plate.forbidden=true end},
    {"denied native write",function(x)x.plate.can=false end},
}) do
    c=fixture();case[2](c)
    eq(c.T.Enable(c.row),false,case[1].." refuses before mutation")
    eq(#c.writes,0,case[1].." leaves all UI geometry unchanged")
end
c=fixture();c.throwSize=true
eq(c.T.Enable(c.row),false,"partial global setter failure rejects setup")
eq(c.w,140,"partial global write rolls back")
eq(c.T.Status().restoring,false,"successful failure cleanup is complete")
-- Runtime regression: this client clamps the requested giant size to 512x256.
-- The clamped immediate result is still our write and must be restored.
for _,throwAfter in ipairs({false,true}) do
    c=fixture();c.w,c.h=142.5,53.150001525879;c.clamp=true;c.throwSize=throwAfter
    local ok,reason=c.T.Enable(c.row)
    eq(ok,false,"clamped size never proceeds to native hit mapping")
    eq(reason,"size_clamped","clamped dimensions have an explicit failure reason")
    eq(c.w,142.5,"clamped width is restored to the real original baseline")
    eq(c.h,53.150001525879,"clamped height is restored to the real original baseline")
    eq(c.T.Status().restoring,false,"restored clamp leaves no pending global geometry")
    eq(c.plate.hit,c.plate.UnitFrame,"clamp failure maps no native hit area")
    eq(c.plate.UnitFrame.anchor,c.plate,"clamp failure does not reanchor world bars")
    local result=c.records[#c.records]
    eq(result.kind,"ENEMY_NATIVE_TRIAL_SIZE_RESULT","size failure is recorded independently from status changes")
    eq(result.fields.requestedWidth,15360,"failure records requested size")
    eq(result.fields.actualWidth,512,"failure retains clamped immediate width")
    eq(result.fields.actualHeight,256,"failure retains clamped immediate height")
    eq(result.fields.setterAccepted,not throwAfter,"failure preserves setter acceptance separately from size result")
    eq(result.fields.restoredOriginal,true,"failure confirms original baseline was read back")
    eq(result.fields.cleanupComplete,true,"failure records cleanup completion")
    eq(result.fields.mappingAccepted,false,"failure never claims accepted native mapping")
end
c=fixture();c.clamp=true;c.afterSize=function()c.secretSize=true end
eq(c.T.Enable(c.row),false,"unreadable immediate setter result refuses setup")
eq(c.T.Status().restoring,true,"unreadable immediate result keeps cleanup pending")
c.secretSize=false;c.T.Tick(.1)
eq(c.w,512,"later public size is not silently claimed after missing immediate ownership readback")
eq(c.T.Status().reason,"restore_size_ownership_unreadable_or_reload","unknown initial ownership explicitly requires recovery or reload")
eq(c.T.Status().restoring,true,"unknown initial ownership cannot falsely complete cleanup")
c=fixture();c.clamp=true
c.afterSize=function()C_NamePlate.SetNamePlateSize(150,60)end
eq(c.T.Enable(c.row),false,"known nested external setter aborts setup")
eq(c.w,150,"immediate external setter width is not stolen as this trial's clamp")
eq(c.h,60,"immediate external setter height is preserved")
eq(c.records[#c.records].fields.externalSetterObserved,true,"nested external setter is explicit in size-failure evidence")
eq(c.records[#c.records].fields.restoredOriginal,false,"external settings are not called restored original settings")
c=fixture();c.plate.throwAfterMap=true
eq(c.T.Enable(c.row),false,"partial hit setter failure rejects setup")
eq(c.plate.hit,c.plate.UnitFrame,"partial native mapping returns to public defaults")
eq(c.w,140,"partial mapping cleanup restores global size")
c=fixture();c.plate.refuseEvent=true
eq(c.T.Enable(c.row),false,"synchronous action refusal is a failed write even with nil return")
eq(c.w,140,"synchronous refusal restores size")
c=fixture();c.failFont=true
eq(c.T.Enable(c.row),false,"incomplete card creation refuses setup")
eq(c.frames[1].shown,false,"incomplete private card remains hidden")
c.failFont=false
eq(c.T.Enable(c.row),true,"retry rebuilds a complete private card instead of reusing partial setup")
c.T.Disable()
c=fixture();c.plate.combatAfterMap=true
eq(c.T.Enable(c.row),false,"combat starting during native mapping cannot complete setup")
eq(c.T.Status().active,false,"combat-interrupted setup is not called active")
eq(c.T.Status().restoring,true,"combat-interrupted partial mutation remains pending")
c.combat=false;c.plate.combatAfterMap=false;c.T.Tick(.1)
eq(c.w,140,"combat-interrupted setup recovers after combat")

c=fixture();c.T.Enable(c.row);c.combat=true
local before=#c.writes;c.T.OnEvent("PLAYER_REGEN_DISABLED")
eq(#c.writes,before,"combat cleanup never performs native protected writes")
eq(c.T.Status().restoring,true,"combat cleanup remains pending")
eq(c.T.Status().active,false,"pending cleanup is not reported as active test")
c.combat=false;c.T.OnEvent("PLAYER_REGEN_ENABLED")
eq(c.T.Status().restoring,false,"cleanup resumes when known out of combat")
eq(c.w,140,"post-combat size restoration completed")
c=fixture();c.T.Enable(c.row);c.T.Tick(180)
eq(c.T.Status().active,false,"three-minute timeout stops the explicit trial")
eq(c.w,140,"timeout restores global size")
c=fixture();local wall=100;GetTime=function()return wall end;c.T.Enable(c.row)
c.T.Tick(1800)
eq(c.T.Status().active,true,"polling elapsed cannot inflate a valid wall-clock duration")
wall=280;c.T.Tick(.1)
eq(c.T.Status().active,false,"real wall-clock limit ends the trial")
c=fixture();c.T.Enable(c.row);c.w,c.h=150,60;c.T.Tick(.1)
eq(c.w,150,"external width replaces owned global width and is preserved")
eq(c.h,60,"external height is not overwritten during cleanup")
eq(c.T.Status().reason,"native_defaults_restored_external_size_kept","external ownership loss is explicit")
c=fixture();c.T.Enable(c.row);C_NamePlate.SetNamePlateSize(15360,15360);c.T.Tick(0)
eq(c.w,15360,"known later external setter is preserved even when equal to our prior owned value")
eq(c.T.Status().reason,"native_defaults_restored_external_size_kept","equal-value external ownership is not overwritten")

c=fixture();c.T.Enable(c.row)
local oldUF=c.plate.UnitFrame;local oldRestores=oldUF.restores or 0
c.plate.UnitFrame=c.newPlate("nameplate1","Creature-C").UnitFrame
c.plate.UnitFrame.plate=c.plate;c.plate.guid="Creature-C"
c.T.Tick(.1)
eq(c.T.Status().restoring,true,"unobserved native owner replacement waits for post-reset evidence")
eq(oldUF.restores or 0,oldRestores,"old UF is not restored onto replacement")
c.hook("OnNamePlateAdded","nameplate1")
c.T.Tick(0)
eq(c.T.Status().restoring,false,"trusted native addition releases retired old part")
eq(c.plate.UnitFrame.restores,nil,"new UF receives no old unit restoration write")
eq(c.plate.stack,c.plate.UnitFrame,"pool reuse releases old box stacking to the fresh native owner only")
c=fixture();c.T.Enable(c.row);local removedUF=c.plate.UnitFrame
c.plate.UnitFrame=nil;c.units.nameplate1=nil;c.hook("OnNamePlateRemoved","nameplate1");c.T.Tick(0)
eq(c.T.Status().restoring,true,"removed plate without a fresh owner keeps stacking cleanup pending")
eq(c.T.Status().reason,"restore_waiting_native_owner_or_reload","unresolved stacking cleanup is explicit")
c.plate.UnitFrame=c.newPlate("nameplate1","Creature-D").UnitFrame;c.plate.UnitFrame.plate=c.plate
c.units.nameplate1=c.plate;c.plate.guid="Creature-D";c.hook("OnNamePlateAdded","nameplate1");c.T.Tick(0)
eq(c.T.Status().restoring,false,"native owner arrival completes only deferred current stacking restoration")
eq(c.plate.stack,c.plate.UnitFrame,"deferred cleanup does not leave an old box in the native stacking engine")
eq(c.plate.UnitFrame.restores,nil,"deferred cleanup never applies an old hit area to a replacement")
c=fixture();c.T.Enable(c.row);c.hook("UpdateNamePlateOptions");c.T.Tick(0)
eq(c.T.Status().active,false,"native option reset invalidates the trial")
eq(c.w,140,"native options hook restores owned global dimensions")
c=fixture();c.T.Enable(c.row);c.plate.UnitFrame.fail="UpdateHitTestArea"
eq(c.T.Disable(),false,"native default restoration refusal remains pending")
eq(c.T.Status().restoring,true,"failed restoration is never called complete")
c.plate.UnitFrame.fail=nil
eq(c.T.Disable(),true,"a later permitted native default restoration completes cleanup")
c=fixture();local attempts=0;c.ns.Diagnostics.Record=function()attempts=attempts+1;return false end
c.T.Enable(c.row);local failedAttempts=attempts;c.T.Tick(.1)
eq(attempts,failedAttempts+1,"failed status logging is retried instead of being deduplicated")
c.T.Disable()
eq(forbiddenActions,0,"no restricted coordinate read, spell, target, macro, CVar or binding action occurred")
print("Targets enemy native trial simulated checks: "..checks.."; no native engine mouseover was executed")
