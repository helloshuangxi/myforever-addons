-- Lua 5.1 native-widget contract simulations, NOT live game acceptance.
local source="_forever_/Interface/AddOns/MyForeverProfessions/"
local checks=0
local function eq(a,b,why) checks=checks+1; assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a)) end
local function yes(v,why) eq(not not v,true,why) end
local function near(a,b,why) yes(math.abs(a-b)<.011,why) end

local function float32(value)
    if value==0 or value~=value or math.abs(value)==math.huge then return value end
    local sign=value<0 and -1 or 1
    local magnitude=math.abs(value)
    local fraction,exponent=math.frexp(magnitude)
    if exponent>128 then return sign*math.huge end
    local scaled=exponent < -125 and math.ldexp(magnitude,149) or math.ldexp(fraction,24)
    local rounded=math.floor(scaled)
    local remainder=scaled-rounded
    if remainder>.5 or (remainder==.5 and rounded%2==1) then rounded=rounded+1 end
    local result=exponent < -125 and math.ldexp(rounded,-149) or math.ldexp(rounded,exponent-24)
    return sign*(result>=math.ldexp(1,128) and math.huge or result)
end

local function client(options)
    options=options or {}
    local function native(value) return options.float32 and float32(value) or value end
    -- A separate stand-in backend models the observed native Frame alpha:
    -- nearest 8-bit value, returned as float32. This is still an interface
    -- contract stub; the real renderer/readback check has its own tests.
    local function alpha8(value) return float32(math.floor(value*255+.5)/255) end
    local e=setmetatable({}, {__index=_G}); e._G=e
    local s={now=0,frame=0,frames={},timers={},placements={},events={},mouse={},cx=options.cursorX or 500,cy=options.cursorY or 600,combat=false,dead=false,
        look=false,speed=0,shape=options.shape or "ROUND",icon=1,mask="Textures\\MinimapMask",reads=0,
        showCount=0,hideCount=0,shows={},hides={},mutations={},nativeConfig=0,rendered=nil,tooltipFrames={},blockingRequests=0,
        samples={},viewRadius=100,viewRadiusReads={},nativeWrites={},nativeReturns={},exposedUnreadyFrames={},
        opacities={},nativeLeaseStarts={},opacity=0}
    local methods={}
    local function frame()
        local f=setmetatable({scripts={},events={},children={},regions={},shown=true,alpha=1,clicks=true,wheel=true,motion=true,
            scale=1,width=native(options.width or 48),height=native(options.height or 48),zoom=0,clamped=options.clamped==true,
            anchors={{"BOTTOMLEFT",e.WorldFrame,"BOTTOMLEFT",100,200}}},{__index=methods})
        s.frames[#s.frames+1]=f
        return f
    end
    function methods:GetNumPoints() return #self.anchors end
    function methods:GetPoint(i) return unpack(self.anchors[i],1,5) end
    function methods:ClearAllPoints() self.anchors={} end
    function methods:SetPoint(...)
        local p={...}; p[4],p[5]=native(p[4]),native(p[5])
        self.anchors[#self.anchors+1]=p
    end
    function methods:AdjustPointsOffset(x,y)
        if s.failMoveBefore or (s.failRestore and x<0) then error("move-before") end
        for _,p in ipairs(self.anchors) do p[4],p[5]=native(p[4]+x),native(p[5]+y) end
        if self==e.Minimap then
            yes(s.standShown,"movement requires visible stand-in")
            yes(s.frame>s.showFrame,"stand-in has earlier frame than mutation")
            local scale=self:GetEffectiveScale()
            local px,py=s.cx/scale-self:GetLeft(),s.cy/scale-self:GetBottom()
            s.placements[#s.placements+1]={px,py,frame=s.frame,scale=scale,physicalX=px*scale,physicalY=py*scale}
            s.lastPlace=s.frame
        end
        if s.failMoveAfter then error("move-after") end
    end
    local fractions={BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0},LEFT={0,.5},CENTER={.5,.5},RIGHT={1,.5},
        TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1}}
    local function edge(self,axis)
        local p=self.anchors[1]; if not p then return end
        local relative=p[2] or self.parent or e.WorldFrame
        local relativeScale=relative:GetEffectiveScale()
        local scale=self:GetEffectiveScale()
        local relativeEdge=axis==1 and relative:GetLeft() or relative:GetBottom()
        local relativeSize=axis==1 and relative:GetWidth() or relative:GetHeight()
        local size=axis==1 and self.width or self.height
        return (relativeEdge+relativeSize*fractions[p[3]][axis])*relativeScale/scale
            +p[axis+3]-size*fractions[p[1]][axis]
    end
    function methods:GetLeft()
        local value=edge(self,1)
        if value and self==e.Minimap and self.clamped then
            value=math.max(0,math.min(value,e.WorldFrame:GetWidth()/self:GetEffectiveScale()-self.width))
        end
        if value and options.displacementError and self==e.Minimap and self.anchors[1]
            and math.abs(self.anchors[1][4]-100)>.001 then
            value=value+options.displacementError/self:GetEffectiveScale()
        end
        return value and native(value)
    end
    function methods:GetBottom() local value=edge(self,2); return value and native(value) end
    function methods:GetWidth() return native(self.width) end
    function methods:GetHeight() return native(self.height) end
    function methods:GetScale() return native(self.scale) end
    function methods:IsClampedToScreen()
        if self==e.Minimap and s.clampGetterError then error("clamp-getter") end
        if self==e.Minimap and s.clampGetterSecret then return {secret=true} end
        return self.clamped
    end
    function methods:SetClampedToScreen(value)
        if self==e.Minimap then
            if s.failClampBefore and value==false then error("clamp-before") end
            if s.failClampRestore and value==true then error("clamp-restore") end
        end
        self.clamped=value
        if self==e.Minimap and s.failClampAfter and value==false then error("clamp-after") end
    end
    function methods:GetEffectiveScale() return native(self:GetScale()*(self.parent and self.parent:GetEffectiveScale() or 1)) end
    function methods:SetScale(value)
        if self==e.Minimap then
            if s.failScaleBefore and value~=s.initialLocalScale then error("scale-write-before") end
            if s.failScaleRestore and value==s.initialLocalScale then error("scale-restore") end
        end
        self.scale=native(value)
        if self==e.Minimap then
            s.mutations[#s.mutations+1]={kind="scale",value=value,actual=self.scale,frame=s.frame}
            if s.onScale then s.onScale(self,value) end
            if s.failScaleAfter and value~=s.initialLocalScale then error("scale-write-after") end
            if s.failScaleRestoreAfter and value==s.initialLocalScale then error("scale-restore-after") end
        end
    end
    function methods:SetSize() error("must not resize native map") end
    function methods:SetWidth() error("must not resize native map") end
    function methods:SetHeight() error("must not resize native map") end
    function methods:SetZoom() error("must not change map zoom") end
    function methods:GetZoom() return self.zoom end
    function methods:GetParent() return self.parent end
    function methods:GetAlpha() return native(self.alpha) end
    function methods:SetAlpha(v)
        if s.failAlphaRestore and v~=0 then error("alpha-restore") end
        self.alpha=native(v)
        if s.onAlpha then s.onAlpha(self,v) end
    end
    function methods:IsMouseClickEnabled() return self.clicks end
    function methods:SetMouseClickEnabled(v) self.clicks=v; if s.failClickAfter and not v then error("click-after") end end
    function methods:IsMouseWheelEnabled() return self.wheel end
    function methods:EnableMouseWheel(v) self.wheel=v end
    function methods:IsMouseMotionEnabled() return self.motion end
    function methods:SetMouseMotionEnabled(v) self.motion=v end
    function methods:IsProtected() return self.protected or false end
    function methods:IsVisible() return self.shown end
    function methods:GetChildren() return unpack(self.children) end
    function methods:GetRegions() return unpack(self.regions) end
    function methods:SetMaskTexture(v)
        if s.failMaskRestore and v~="Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask" then error("mask-restore") end
        s.mask=v; s.mutations[#s.mutations+1]={kind="mask",value=v,frame=s.frame}
        if s.maskOverride and v:find("EmptyMask",1,true) then self:SetMaskTexture("external-mask") end
    end
    function methods:SetIconScale(v)
        if s.failIconBefore and v==0 then error("icon-zero-before") end
        if s.failIconRestore and v~=0 then error("icon-restore") end
        s.icon=v; s.mutations[#s.mutations+1]={kind="icon",value=v,frame=s.frame}
        if s.failIconAfter and v==0 then error("icon-zero-after") end
    end
    function methods:SetScript(k,v) self.scripts[k]=v end
    function methods:RegisterEvent(k) self.events[k]=true end
    function methods:CreateTexture() return frame() end
    function methods:SetTexture(v) if options.noAsset then return false end; self.texture=v; return true end
    function methods:GetTexture()
        if options.missingAsset or (options.requireBlocking and not self.blocking) then return nil end
        if options.textureResult~=nil then return options.textureResult end
        return self.texture
    end
    if not options.noBlockingAPI then
        function methods:SetBlockingLoadsRequested(value)
            s.blockingRequests=s.blockingRequests+1
            if options.failBlocking then error("blocking-load-request") end
            self.blocking=value
        end
    end
    e.CreateFrame=frame
    e.WorldFrame={GetEffectiveScale=function() return 1 end,GetLeft=function() return 0 end,GetBottom=function() return 0 end,
        GetWidth=function() return 1920 end,GetHeight=function() return 1080 end}
    e.UIParent=frame(); e.Minimap=frame(); e.MinimapCluster=frame(); e.Minimap.parent=e.MinimapCluster
    if options.noClamp then e.Minimap.IsClampedToScreen=false;e.Minimap.SetClampedToScreen=false end
    e.UIParent.scale=native(options.parentScale or 1)
    e.MinimapCluster.parent=e.UIParent
    e.Minimap.scale=native(options.scale or 1)
    s.initialLocalScale=e.Minimap:GetScale()
    s.initialEffectiveScale=e.Minimap:GetEffectiveScale()
    s.initialLeft,s.initialBottom=e.Minimap:GetLeft(),e.Minimap:GetBottom()
    s.child=frame(); s.child.alpha=.75; e.Minimap.children={s.child}
    s.region=frame(); s.region.alpha=.4; e.Minimap.regions={s.region}
    e.MinimapCluster.PlayerCoords=frame(); e.MinimapCluster.PlayerCoords.alpha=.6
    e.MinimapCluster.MinimapContainer={Minimap=e.Minimap}
    e.MinimapCluster.IsInitialized=function() return not options.noBaseline end
    e.MinimapCluster.HasSetting=function() return not options.noBaseline end
    e.MinimapCluster.GetSettingValue=function() return 100 end
    e.MinimapCluster.UpdateSystemSettingIconScale=function() s.nativeConfig=s.nativeConfig+1; e.Minimap:SetIconScale(1) end
    e.Enum={EditModeMinimapSetting={IconScale=3}}
    e.issecretvalue=function(v) return type(v)=="table" and rawget(v,"secret")==true end
    e.GetTime=function() if s.clockError then error("public-clock") end; return s.now end
    e.InCombatLockdown=function() return s.combat end
    e.UnitAffectingCombat=function() return s.combat end
    e.UnitIsDeadOrGhost=function() return s.dead end
    e.IsMouselooking=function() return s.look end
    e.GetUnitSpeed=function() return s.speed end
    e.IsMouseButtonDown=function(button)
        if button then return s.mouse[button] or false end
        for _,v in pairs(s.mouse) do if v then return true end end
        return false
    end
    e.GetCursorPosition=function() if s.cursorError then error("public-cursor") end; return s.cx,s.cy end
    e.GetMinimapShape=function() return s.shape end
    e.GetMouseFoci=function() return s.foci or {e.WorldFrame} end
    e.hooksecurefunc=function(target,key,hook)
        local old=assert(target[key]); target[key]=function(...)
            local result={old(...)}; hook(...); return unpack(result)
        end
    end
    e.C_Minimap={GetUiMapID=function() return s.mapID or 1426 end,SetTracking=function() error("must not write tracking") end,
        GetViewRadius=function()
            local value=s.viewRadius
            if s.radiusChangesWithScale and e.Minimap:GetScale()~=s.initialLocalScale then value=value+(s.radiusScaleDelta or 1) end
            s.viewRadiusReads[#s.viewRadiusReads+1]=value
            return value
        end}
    e.C_AddOns={IsAddOnLoaded=function(name)
        return (name=="NodeSight" and options.conflict) or name==options.conflictName or false
    end}
    e.C_Timer={After=function(delay,fn)
        if s.failHandoffTimer and delay<.4 then error("handoff-timer") end
        if s.failSamplingTimer and delay>.94 and delay<.96 then error("sampling-timer") end
        s.timers[#s.timers+1]={at=s.now+delay,delay=delay,fn=fn}
    end}
    function s.hit(x,y,nx,ny,radius)
        -- Resource positions follow map scale; the modeled native hit radius
        -- stays fixed in physical screen pixels, not map-local coordinates.
        local scale=e.Minimap:GetEffectiveScale()
        return ((x-nx)^2+(y-ny)^2)*scale^2<(radius or 6)^2
    end
    s.node=function(x,y)
        if s.hit(x,y,e.Minimap.width/2,e.Minimap.height/2) then return "铜矿" end
    end
    e.C_TooltipInfo={GetMinimapMouseover=function()
        s.reads=s.reads+1; s.tooltipFrames[#s.tooltipFrames+1]=s.frame
        local scale=e.Minimap:GetEffectiveScale()
        local x,y=s.cx/scale-e.Minimap:GetLeft(),s.cy/scale-e.Minimap:GetBottom()
        s.samples[#s.samples+1]={x=x,y=y,scale=scale,physicalX=x*scale,physicalY=y*scale,frame=s.frame}
        yes(s.frame>s.lastPlace,"tooltip read occurs after a native render frame")
        if s.readError then error("native-read") end
        if s.override then return s.override(s) end
        return s.rendered
    end}
    if options.tooltip then
        local tip={hooks={},shown=false,hides=0,ownerReads=0,textReads=0}
        function tip:HookScript(event,fn) self.hooks[event]=fn end
        function tip:GetOwner()
            self.ownerReads=self.ownerReads+1
            if s.ownerError then error("restricted-owner") end
            return s.tooltipOwner
        end
        function tip:Show()
            self.shown=true
            if self.hooks.OnShow then self.hooks.OnShow(self) end
        end
        function tip:Hide() self.hides=self.hides+1; self.shown=false end
        function tip:SetMinimapMouseover() self.shown=true end
        function tip:GetText() self.textReads=self.textReads+1; error("must not read native tooltip text") end
        s.tooltip,e.GameTooltip=tip,tip
        if options.noTooltipOwner then tip.GetOwner=nil end
        if options.noTooltipMethod then tip.SetMinimapMouseover=nil end
    end
    local nativeFrames={[e.Minimap]=true,[s.child]=true,[s.region]=true,[e.MinimapCluster.PlayerCoords]=true}
    for _,method in ipairs({"ClearAllPoints","SetPoint","AdjustPointsOffset","SetScale","SetAlpha",
        "SetMouseClickEnabled","EnableMouseWheel","SetMouseMotionEnabled","SetMaskTexture","SetIconScale","SetClampedToScreen"}) do
        local old=methods[method]
        methods[method]=function(self,...)
            if nativeFrames[self] then
                s.nativeWrites[#s.nativeWrites+1]={method=method,frame=s.frame,value=(...)}
                if s.standShown and method=="SetMaskTexture" and (...)=="Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask" then
                    s.nativeLeaseStarts[#s.nativeLeaseStarts+1]={frame=s.frame,at=s.now}
                end
                if s.onNativeWrite then s.onNativeWrite(self,method,...) end
            end
            return old(self,...)
        end
    end
    -- This independent renderer model assumes restored pixels become visible
    -- after two frame presentations. It is a regression oracle, not evidence
    -- that the real game's GPU finishes repainting within two frames.
    s.nativeGPUReady,s.gpuWasOriginal=true,true
    local function nativeOriginal()
        return e.Minimap:GetScale()==s.initialLocalScale
            and math.abs((e.Minimap:GetLeft() or -1)-s.initialLeft)<.001
            and math.abs((e.Minimap:GetBottom() or -1)-s.initialBottom)<.001
            and s.icon==1 and s.mask=="Textures\\MinimapMask"
            and e.Minimap.clicks and e.Minimap.wheel and s.child.clicks and s.child.motion
            and math.abs(s.child.alpha-.75)<.001 and math.abs(s.region.alpha-.4)<.001
    end
    local function observePresentation()
        if not options.presentNativeAfterFrames then return end
        local original=nativeOriginal()
        if not original then s.nativeGPUReady=false
        elseif not s.gpuWasOriginal then
            local returned={frame=s.frame,at=s.now}
            s.nativeReturns[#s.nativeReturns+1]=returned
            s.nativeReturn=returned
        end
        s.gpuWasOriginal=original
        if original and s.nativeReturn and s.frame>=s.nativeReturn.frame+options.presentNativeAfterFrames then
            s.nativeGPUReady=true
            s.presentedNativeFrame=s.frame
        end
    end
    local ns={GatherStandIn={
        Show=function(snapshot,initialOpacity)
            s.showCount=s.showCount+1; s.snapshot=snapshot; s.showFrame=s.frame
            if options.noStand then return false,"map-art-unavailable" end
            if not s.standShown then s.shows[#s.shows+1]=s.now end
            s.opacity=initialOpacity==nil and 1 or initialOpacity
            if options.nativeAlpha8 then s.opacity=alpha8(s.opacity) end
            s.initialOpacity=s.opacity
            s.opaqueFrame=s.opacity==1 and s.frame or nil
            s.standShown=true; return true
        end,
        SetOpacity=function(value)
            s.opacities[#s.opacities+1]={value=value,at=s.now,frame=s.frame,nativeWrites=#s.nativeWrites}
            if s.failOpacity=="before" then error("opacity-before") end
            if s.failOpacity=="false" then return false end
            local actual=options.nativeAlpha8 and alpha8(value) or value
            if options.nativeAlpha8 and s.lowerOpaqueEndpoint and value==1 then actual=alpha8(254/255) end
            if options.nativeAlpha8 and math.abs(actual-alpha8(value))>1e-6 then
                s.opacity=actual
                return false -- Renderer must reject a wrong native endpoint.
            end
            if s.opacity<1 and actual==1 then s.opaqueFrame=s.frame end
            s.opacity=actual
            if s.failOpacity=="after" then error("opacity-after") end
            return true
        end,
        Hide=function()
            eq(e.Minimap.clicks,true,"input returned before stand-in hidden")
            if s.standShown then s.hides[#s.hides+1]=s.now end
            s.standShown=false; s.hideCount=s.hideCount+1
        end,
        IsShown=function() return s.standShown or false end,
    }}
    for _,name in ipairs({"GatherResources","GatherCursorScan"}) do
        local chunk=assert(loadfile(source..name..".lua")); setfenv(chunk,e); chunk("MyForeverProfessions",ns)
    end
    s.scan,s.ns,s.env,s.map=ns.GatherCursorScan,ns,e,e.Minimap
    function s.tick(dt,poll)
        s.now=s.now+(dt or 1/60); s.frame=s.frame+1
        observePresentation()
        local scale=s.map:GetEffectiveScale()
        local x,y=s.cx/scale-(s.map:GetLeft() or 0),s.cy/scale-(s.map:GetBottom() or 0)
        local names=s.node(x,y)
        s.rendered=names and {lines={}} or nil
        if type(names)=="string" then names={names} end
        for _,name in ipairs(names or {}) do s.rendered.lines[#s.rendered.lines+1]={leftText=name} end
        for _,f in ipairs(s.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt or 1/60) end end
        for _,t in ipairs(s.timers) do if not t.done and s.now>=t.at then t.done=true; t.fn() end end
        local result
        if poll~=false then result=s.scan.ScanNames() end
        observePresentation()
        if options.presentNativeAfterFrames and nativeOriginal() and (not s.standShown or s.opacity<1) and not s.nativeGPUReady then
            s.exposedUnreadyFrames[#s.exposedUnreadyFrames+1]=s.frame
        end
        return result
    end
    function s.event(name)
        for _,f in ipairs(s.frames) do if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name) end end
    end
    function s.result(limit)
        s.scan.ScanNames()
        for _=1,limit or 6000 do local r=s.tick(); if r then return r end end
        error("no result: "..s.scan.ScanDiagnostics().reason)
    end
    function s.start()
        s.scan.ScanNames()
        for _=1,180 do
            if s.standShown then return end
            s.tick()
        end
        error("did not begin stand-in: "..s.scan.ScanDiagnostics().reason)
    end
    function s.moving()
        local before=#s.placements
        s.start()
        for _=1,20 do s.tick(nil,false); if #s.placements>before then return end end
        error("did not begin moving: "..s.scan.ScanDiagnostics().reason)
    end
    function s.opaque()
        s.start()
        for _=1,40 do
            if s.opacity==1 then return end
            s.tick(nil,false)
        end
        error("did not finish fade-in: "..s.scan.ScanDiagnostics().reason)
    end
    function s.attemptDisguise()
        s.opaque()
        s.tick(nil,false); s.tick(nil,false)
    end
    function s.endDisplay(dt)
        for _=1,60 do
            if not s.standShown then return end
            s.tick(dt,false)
        end
        error("display transition did not end")
    end
    function s.confirmed()
        local before=s.scan.ScanDiagnostics().publications
        s.start()
        for _=1,40 do
            s.tick(nil,false)
            if s.scan.ScanDiagnostics().publications>before then return end
        end
        error("did not publish fresh receipt: "..s.scan.ScanDiagnostics().reason)
    end
    function s.unconsumed()
        s.confirmed()
        s.endDisplay()
    end
    return s,s.scan
end
local function nativeRestored(s,why,x,y,icon,scale)
    near(s.map:GetLeft(),x or s.initialLeft,why.." left"); near(s.map:GetBottom(),y or s.initialBottom,why.." bottom")
    near(s.map:GetScale(),scale or s.initialLocalScale,why.." local scale")
    eq(s.map.alpha,1,why.." native terrain alpha never changed")
    eq(s.map.clicks,true,why.." map clicks"); eq(s.map.wheel,true,why.." map wheel")
    eq(s.child.clicks,true,why.." child clicks"); eq(s.child.motion,true,why.." child hover")
    near(s.child.alpha,.75,why.." child alpha"); near(s.region.alpha,.4,why.." region alpha")
    eq(s.icon,icon or 1,why.." blip scale")
end
local function restored(s,why,x,y,icon,scale)
    nativeRestored(s,why,x,y,icon,scale)
    eq(s.standShown,false,why.." original picture exposed")
    eq(s.scan.ScanDiagnostics().standInRetained,false,why.." no retained stand-in state")
end

do
    local s,scan=client()
    yes(scan.IsSupported(),"supported native contract")
    eq(scan.ScanNames(),nil,"initial poll does not invent observation")
    eq(#s.placements,0,"Show precedes native mutation")
    eq(s.showCount,0,"initial poll waits for stable pointer")
    s.tick(.1); eq(s.showCount,0,"one tenth second is too short for stable pointer")
    s.tick(.07); eq(s.showCount,0,"less than .18 seconds never hides native map")
    s.start()
    yes(s.shows[1]>=.18,"first stand-in waits for .18 seconds stable pointer")
    eq(s.initialOpacity,0,"replacement starts transparent over untouched native map")
    s.opaque()
    s.tick(nil,false); eq(#s.placements,0,"one complete opaque render before native move")
    s.tick(nil,false); eq(#s.placements,1,"next update places sample")
    eq(s.icon,0,"private native-map lease fully suppresses its icon layer")
    eq(s.reads,0,"placement never synchronously reads tooltip")
    s.tick(nil,false); eq(s.reads,1,"first sample is read next frame")
    eq(scan.ScanNames(),nil,"candidate waits for control and recheck")
    s.tick(nil,false); eq(scan.ScanNames(),nil,"outside-map control is not a resource observation")
    eq(s.tick(),nil,"F0 receipt waits for display handoff after native restoration")
    eq(scan.ScanDiagnostics().publications,1,"F0 publication records pending receipt, not HUD delivery")
    eq(s.tick(),nil,"F+1 still protects native repaint")
    eq(s.tick(),nil,"F+2 starts display fade-out without consuming the receipt")
    s.endDisplay()
    local r=scan.ScanNames(); eq(r[1].name,"铜矿","completed fade-out delivers fresh confirmed resource")
    eq(r[1].kind,"mining","catalog kind")
    eq(r[1].dx,nil,"no resource coordinates"); eq(r[1].bearing,nil,"no resource direction")
    restored(s,"successful positive")
    eq(scan.ScanNames(),nil,"confirmed result consumed once")
    eq(scan.ScanNames(),nil,"second poll cannot renew old cache")
    local d=scan.ScanDiagnostics(); eq(d.acceptedNames[1],"铜矿","bounded known-name diagnostics")
    eq(d.tooltipNilCount,1,"outside control counts public nil separately")
    eq(d.tooltipEmptyCount,0,"nil is not an empty public lines table")
    eq(d.tooltipNonemptyCount,2,"candidate and confirmation count nonempty tooltips")
    eq(d.tooltipKnownCount,2,"known resource tooltip reads counted")
    eq(d.tooltipUnknownCount,0,"known resources do not count as unknown")
    eq(d.roundTooltipKnownCount,2,"last completed native lease retains numeric counts")
    eq(d.tooltipInvalidCount,0,"valid tooltip reads do not count as invalid")
    d.acceptedNames[1]="caller mutation"
    d.tooltipKnownCount=999
    eq(scan.ScanDiagnostics().acceptedNames[1],"铜矿","diagnostic copy protects internal state")
    eq(scan.ScanDiagnostics().tooltipKnownCount,2,"numeric diagnostics are read-only copies")
    local before=s.reads; scan.ScanDiagnostics(); eq(s.reads,before,"diagnostic does not sample")
    local freshAt,renewed=s.now,false
    for _=1,180 do
        local result=s.tick()
        if result and #result>0 then yes(s.now-freshAt<3.5,"stationary true recheck stays within HUD lifetime"); renewed=true; break end
    end
    yes(renewed,"stationary previously found point is truly sampled again")
    eq(s.speed,0,"standing scan does not require movement")
end
for _,text in ipairs({"|A:MinimapArrow:12:12|a 铜矿", "|TInterface\\Icons\\INV_Misc_Stone_01:12|t 铜矿",
    "|cffffff00|TInterface\\Icons\\INV_Misc_Stone_01:12|t 铜矿|r |A:MinimapArrow:12:12|a"}) do
    local s,scan=client()
    s.node=function(x,y)
        if s.hit(x,y,s.map.width/2,s.map.height/2) then return text end
    end
    eq(s.result()[1].name,"铜矿","inline art and color codes leave exact known resource name")
    eq(scan.ScanDiagnostics().rawKnownNames[1],"铜矿","diagnostics retain only clean known resource names")
    restored(s,"inline resource name")
end
for _,case in ipairs({{value={lines={}},field="Empty"},{value={lines={{leftText="unrelated private tooltip text"}}},field="Unknown"},
    {value={secret=true},field="Invalid"},{value={lines={{leftText=7}}},field="Invalid"}}) do
    local s,scan=client(); s.override=function() return case.value end
    s.moving(); s.tick(nil,false)
    local d=scan.ScanDiagnostics()
    eq(d["tooltip"..case.field.."Count"],1,"native tooltip category counted separately")
    eq(d["roundTooltip"..case.field.."Count"],1,"native lease category counted separately")
    eq(d.tooltipNilCount,0,"non-nil tooltip is not a nil read")
    eq(d.rawKnownNames[1],nil,"unrelated or invalid raw tooltip is not retained")
    eq(d.acceptedNames[1],nil,"unrelated or invalid tooltip cannot become resource")
    if case.field=="Unknown" then eq(d.tooltipNonemptyCount,1,"unknown lines still count as nonempty") end
    for _,value in pairs(d) do
        eq(value=="unrelated private tooltip text",false,"diagnostics do not expose unrelated tooltip")
    end
end
do
    local s,scan=client(); s.node=function() end
    eq(scan.ScanNames(),nil,"nil no-hit starts pass")
    for _=1,10 do eq(s.tick(),nil,"partial public nil samples never clear HUD") end
    local r=s.result(); eq(#r,0,"all-empty complete coverage returns empty observation")
    yes(scan.ScanDiagnostics().passes>0,"coverage completed")
    restored(s,"all empty")
end
do
    local s,scan=client(); s.override=function() return {lines={{leftText="铜矿"}}} end
    for _=1,180 do eq(s.tick(),nil,"global stale resource text rejected") end
    eq(scan.ScanDiagnostics().acceptedNames[1],nil,"stale text never accepted")
    eq(scan.ScanDiagnostics().rejectedKnownNames[1],"铜矿","stale known name exposed without raw tooltip")
end
for _,options in ipairs({{noStand=true},{noAsset=true},{noBaseline=true},{shape="CORNER-TOPLEFT"},{conflict=true},{conflictName="Lueur"}}) do
    local s,scan=client(options)
    for _=1,90 do eq(s.tick(),nil,"failed preflight does not emit resource") end
    eq(#s.placements,0,"failed preflight leaves native position")
    eq(s.mask,"Textures\\MinimapMask","failed preflight leaves native mask")
    eq(s.map.clicks,true,"failed preflight leaves clicks")
end
do
    local s,scan=client({textureResult=-469,requireBlocking=true})
    local r=s.result()
    eq(r[1].name,"铜矿","actual client negative local texture file ID is accepted")
    eq(s.blockingRequests,1,"private asset probe requests blocking once")
    restored(s,"negative local file ID")
end
do
    local s=client({noBlockingAPI=true})
    eq(s.result()[1].name,"铜矿","blocking API remains optional when texture is already readable")
    eq(s.blockingRequests,0,"missing optional blocking API is not called")
end
for _,options in ipairs({{missingAsset=true},{textureResult=0},{textureResult=-.5},{textureResult=1.5},
    {textureResult=math.huge},{textureResult=-math.huge},{textureResult=0/0},{textureResult={secret=true}},
    {failBlocking=true}}) do
    local s,scan=client(options)
    for _=1,90 do eq(s.tick(),nil,"invalid or missing custom texture cannot emit observations") end
    eq(#s.placements,0,"invalid or missing custom texture never moves native map")
    eq(s.showCount,0,"invalid or missing custom texture never starts stand-in transaction")
    eq(s.mask,"Textures\\MinimapMask","invalid or missing custom texture leaves native mask")
    eq(s.map.clicks,true,"invalid or missing custom texture preserves native clicks")
    eq(scan.ScanDiagnostics().reason,"empty-mask-unavailable","asset failure has explicit diagnostic")
end
for _,event in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_REGEN_DISABLED","PLAYER_DEAD","PLAYER_UNGHOST","PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","MINIMAP_UPDATE_ZOOM","ZONE_CHANGED","ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
    local s,scan=client(); s.moving(); s.event(event)
    restored(s,event)
    eq(scan.ScanNames(),nil,event.." invalidates pending")
end
for _,kind in ipairs({"RightButton","LeftButton","Button8","mouselook","combat","dead","window","map-hover","geometry","shape","zoom","mapid","stand","read-error","secret","malformed"}) do
    local s,scan=client(); s.moving()
    if kind:find("Button",1,true) then s.mouse[kind]=true
    elseif kind=="mouselook" then s.look=true
    elseif kind=="combat" then s.combat=true
    elseif kind=="dead" then s.dead=true
    elseif kind=="window" then s.foci={{}}
    elseif kind=="map-hover" then s.cx,s.cy=110,210
    elseif kind=="geometry" then s.map.width=49
    elseif kind=="shape" then s.shape="SQUARE"
    elseif kind=="zoom" then s.map.zoom=1
    elseif kind=="mapid" then s.mapID=1427
    elseif kind=="stand" then s.standShown=false
    elseif kind=="read-error" then s.readError=true
    elseif kind=="secret" then s.override=function() return {secret=true} end
    elseif kind=="malformed" then s.override=function() return {lines={{leftText=42}}} end end
    s.tick(nil,false)
    restored(s,kind)
    eq(scan.ScanNames(),nil,kind.." yields no observation")
end
do
    local s,scan=client(); s.moving()
    local before=s.frame; s.event("GLOBAL_MOUSE_DOWN")
    eq(s.frame,before,"mouse event restores synchronously without wait")
    eq(s.map.clicks,true,"right click input returned on mouse event")
    eq(s.map.scripts.OnMouseDown,nil,"scanner does not install click handler")
    eq(s.map.scripts.OnMouseUp,nil,"scanner does not install release handler")
end
do
    local s,scan=client(); s.moving()
    s.map:ClearAllPoints(); s.map:SetPoint("BOTTOMLEFT",s.env.WorldFrame,"BOTTOMLEFT",300,400)
    eq(scan.IsActive(),true,"external grouped anchor update waits one frame")
    s.tick(.12,false)
    restored(s,"external anchors",300,400)
    eq(scan.IsActive(),false,"external anchor ownership cannot lock recovery forever")
    eq(scan.ScanNames(),nil,"external anchor change discards candidate")
end
do
    local s,scan=client(); s.moving()
    s.map:AdjustPointsOffset(10,20)
    restored(s,"external relative delta",110,220)
    eq(scan.IsActive(),false,"relative move restores without locking recovery")
    eq(scan.ScanNames(),nil,"relative external move cannot publish candidate")
end
do
    local s,scan=client(); s.moving(); s.child:SetAlpha(.9)
    eq(s.child.alpha,.9,"external appearance kept")
    near(s.map:GetLeft(),100,"external alpha still returns native position")
    eq(s.map.clicks,true,"external alpha returns owned input")
    eq(s.standShown,false,"external alpha releases stand-in")
end
do
    local s,scan=client(); s.moving(); s.map:SetMaskTexture("external-mask")
    eq(s.mask,"external-mask","external mask setter retains ownership")
    near(s.map:GetLeft(),100,"mask conflict returns native anchors")
    eq(s.map.clicks,true,"mask conflict returns clicks")
end
for _,scale in ipairs({1.7,0}) do
    local s,scan=client(); s.moving(); s.map:SetIconScale(scale)
    restored(s,"external icon scale "..scale,nil,nil,scale)
    eq(scan.IsActive(),false,"external icon setter ends private lease even for the same zero value")
    eq(scan.ScanNames(),nil,"external icon ownership discards unfinished candidate")
    if scale==0 then
        local nativeConfig,shows=s.nativeConfig,s.showCount
        for _=1,120 do eq(s.tick(),nil,"external zero scale cannot produce a later scan receipt") end
        eq(s.nativeConfig,nativeConfig,"explicit external zero never reapplies Blizzard icon settings")
        eq(s.showCount,shows,"external zero blocks later private leases")
        eq(scan.ScanDiagnostics().reason,"unknown-icon-scale","explicit external zero remains an unavailable baseline")
        restored(s,"external zero across later scan attempts",nil,nil,0)
    end
end
for _,target in ipairs({"mask","anchor"}) do
    local s,scan=client()
    s.onAlpha=function(frame,value)
        if frame==s.child and value==0 then
            s.onAlpha=nil
            if target=="mask" then s.map:SetMaskTexture("cross-setter-mask")
            else s.map:ClearAllPoints(); s.map:SetPoint("BOTTOMLEFT",s.env.WorldFrame,"BOTTOMLEFT",320,420) end
        end
    end
    s.attemptDisguise(); s.tick(.12,false)
    restored(s,"cross setter "..target,target=="anchor" and 320 or 100,target=="anchor" and 420 or 200)
    if target=="mask" then eq(s.mask,"cross-setter-mask","cross-setter external mask kept") end
    eq(scan.ScanNames(),nil,"cross-setter cancellation cannot publish")
end
for _,failure in ipairs({"failMoveBefore","failMoveAfter","failClickAfter"}) do
    local s,scan=client(); s[failure]=true
    s.start()
    for _=1,20 do s.tick(nil,false); scan.ScanNames() end
    s[failure]=false; scan.Reset("fault-cleared"); s.tick(.2,false)
    restored(s,failure)
    eq(scan.ScanNames(),nil,failure.." cannot leak candidate")
end
for _,failure in ipairs({"failIconBefore","failIconAfter"}) do
    local s,scan=client(); s[failure]=true
    s.attemptDisguise()
    restored(s,failure)
    eq(scan.ScanDiagnostics().reason,"icon-conflict",failure.." rejects unusable zero scale")
    eq(#s.placements,0,failure.." returns mask before moving native map")
    eq(s.reads,0,failure.." cannot collect a resource")
    eq(scan.ScanDiagnostics().publications,0,failure.." cannot publish a receipt")
    eq(scan.ScanNames(),nil,failure.." cannot leak a candidate")
end
do
    local s,scan=client(); s.moving(); s.failIconRestore=true; s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"icon restore failure retains recovery")
    near(s.map:GetLeft(),100,"icon restore failure still returns native position")
    eq(s.icon,0,"failed restore does not pretend the original icon scale returned")
    eq(s.standShown,true,"failed icon restore keeps protective stand-in")
    for _=1,5 do eq(scan.ScanNames(),nil,"icon recovery cannot start scan or publish") end
    s.failIconRestore=false; s.tick(.2,false)
    restored(s,"recovered zero icon lease")
    eq(scan.IsActive(),false,"driver retries original icon scale without HUD polling")
end
do
    local s,scan=client(); s.moving(); s.failAlphaRestore=true; s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"partial restore failure retains recovery")
    near(s.map:GetLeft(),100,"position returned despite decoration restore failure")
    eq(s.standShown,true,"stand-in retained until owned restoration complete")
    for _=1,5 do eq(scan.ScanNames(),nil,"recovery cannot start scan or publish") end
    s.failAlphaRestore=false; s.tick(.2,false)
    restored(s,"recovered decoration")
    eq(scan.IsActive(),false,"driver alone retries restore without HUD polling")
end
do
    local s,scan=client(); s.moving()
    local original=s.map.AdjustPointsOffset
    s.map.AdjustPointsOffset=function() error("temporary restore denial") end
    s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"native inverse failure retains recovery")
    eq(s.standShown,true,"inverse failure keeps stand-in")
    eq(scan.ScanNames(),nil,"inverse failure blocks new scan")
    s.map.AdjustPointsOffset=original; s.tick(.2,false)
    restored(s,"native inverse retry")
end
do
    local s,scan=client(); s.moving(); s.node=function() end
    -- No HUD polls: independent native OnUpdate still returns the map on budget.
    for _=1,60 do s.tick(nil,false) end
    restored(s,"independent timeout/slice driver")
end
do
    local s,scan=client({shape="SQUARE"}); local r=s.result()
    eq(r[1].name,"铜矿","square resource scan")
    eq(s.mask,"Interface\\BUTTONS\\WHITE8X8","known square baseline restored")
end
do
    local s,scan=client(); s.map:SetMaskTexture("known-custom-mask"); s.map:SetIconScale(1.4)
    local r=s.result(); eq(r[1].name,"铜矿","observed public mask baseline permitted")
    eq(s.mask,"known-custom-mask","observed custom mask restored")
    eq(s.icon,1.4,"observed icon scale restored")
end
do
    local s,scan=client(); s.moving(); s.now=s.now+1.6
    for _,t in ipairs(s.timers) do if not t.done and s.now>=t.at then t.done=true; t.fn() end end
    restored(s,"timer fallback without frame callback")
    eq(scan.ScanNames(),nil,"timeout cannot publish")
end
do
    local s,scan=client()
    s.override=function(state)
        if state.reads==1 then return {lines={{leftText="铜矿"}}} end
        return nil
    end
    s.moving(); for _=1,3 do s.tick(nil,false) end
    eq(scan.ScanNames(),nil,"node disappearing before confirmation is not published")
    eq(scan.ScanDiagnostics().acceptedNames[1],nil,"unconfirmed node is not retained")
    restored(s,"disappearing node")
end
do
    local s,scan=client(); s.unconsumed()
    s.now=s.now+1
    eq(scan.ScanNames(),nil,"unconsumed completed result expires instead of freshening cache")
end
do
    local f=assert(io.open(source.."Textures/EmptyMask.tga","rb")); local bytes=f:read("*a"); f:close()
    eq(#bytes,18+8*8*4,"empty mask has exact TGA size")
    eq(bytes:byte(3),2,"empty mask is uncompressed true-color TGA")
    eq(bytes:byte(17),32,"empty mask has alpha channel")
    eq(bytes:sub(19),string.rep(string.char(0),8*8*4),"empty mask pixels all transparent")
end
do
    local s,scan=client()
    scan.ScanNames()
    for _=1,12 do
        s.cx=s.cx+1
        eq(s.tick(.1),nil,"moving pointer never fabricates an observation")
        eq(s.showCount,0,"moving pointer never covers the original minimap")
    end
    local stopped=s.now
    s.tick(.17)
    eq(s.showCount,0,"stopping for less than .18 seconds still preserves native map")
    s.start()
    yes(s.shows[1]-stopped>=.18,"new lease waits after the latest physical movement")
    scan.Reset("disabled")
    restored(s,"stable-pointer wait reset")
    local shows=s.showCount
    s.tick(1.6,false) -- The original-map interval has passed, without source polls.
    eq(scan.ScanNames(),nil,"reset starts a new pointer-rest observation")
    s.tick(.17)
    eq(s.showCount,shows,"reset does not reuse an old pointer-rest timestamp")
    s.start()
    yes(s.showCount>shows,"reset can scan again after a fresh rest period")
    scan.Reset("disabled")
end
for _,phase in ipairs({"stand","sample","control","confirm"}) do
    local s,scan=client()
    s.start()
    if phase~="stand" then
        s.moving()
        if phase=="control" or phase=="confirm" then s.tick(nil,false) end
        if phase=="confirm" then s.tick(nil,false) end
    end
    local moves,reads,frame=#s.placements,s.reads,s.frame
    s.cx=s.cx+.6
    s.tick(nil,false)
    eq(s.frame,frame+1,phase.." motion returns native map on first update")
    restored(s,phase.." immediate pointer motion")
    eq(scan.IsActive(),false,phase.." motion ends native lease immediately")
    eq(s.reads,reads,phase.." motion does not read another tooltip")
    eq(#s.placements,moves+(phase=="stand" and 0 or 1),phase.." motion only restores, never retargets")
    eq(scan.ScanNames(),nil,phase.." interrupted A-B-A emits no receipt")
    local hidden=s.hides[#s.hides]
    for _=1,14 do s.tick(.1); eq(s.standShown,false,phase.." interrupted lease preserves 1.5 second native interval") end
    s.start()
    yes(s.shows[#s.shows]-hidden>=1.5-1e-8,phase.." next lease waits a complete native interval")
    scan.Reset("disabled")
end
do
    local s,scan=client(); s.node=function() end
    s.moving(); s.tick(nil,false)
    local covered=scan.ScanDiagnostics().coverage
    yes(covered>0,"motion regression begins with completed grid samples")
    s.cy=s.cy+.6
    s.tick(nil,false)
    restored(s,"partial grid motion")
    eq(scan.ScanDiagnostics().coverage,covered,"pointer motion preserves already covered grid points")
    local passes=scan.ScanDiagnostics().passes
    local completed=false
    for _=1,6000 do
        local result=s.tick()
        eq(result,nil,"interrupted grid cannot produce an empty-map conclusion")
        if scan.ScanDiagnostics().passes>passes then completed=true; break end
    end
    yes(completed,"partial grid still reaches its end after pointer settles")
    local result=s.result()
    eq(#result,0,"a later fully uninterrupted empty grid may clear the HUD")
    restored(s,"uninterrupted follow-up grid")
end
do
    local s,scan=client({presentNativeAfterFrames=2}); s.node=function() end
    scan.ScanNames()
    local gaps=0
    for _=1,600 do
        s.tick()
        if #s.hides>0 and not scan.IsActive() then
            gaps=gaps+1
            eq(s.standShown,false,"completed lease exposes native terrain and blips")
            eq(s.map.clicks,true,"native gap permits clicks")
            eq(s.map.wheel,true,"native gap permits wheel")
        end
        eq(scan.ScanDiagnostics().standInRetained,false,"no polling path retains replacement picture")
    end
    yes(gaps>100,"normal source polling leaves substantial native-map time")
    yes(#s.shows>2,"scanner starts more than one bounded lease")
    yes(#s.hides>2,"every completed lease hides its own stand-in")
    for i=2,#s.shows do
        yes(s.shows[i]-s.hides[i-1]>=1.5-1e-8,"native map remains visible for at least 1.5 seconds between leases")
    end
    for i=1,#s.hides do
        local returned=s.nativeReturns[i]
        yes(returned,"each completed display has an independently observed native return")
        yes(returned.at-s.nativeLeaseStarts[i].at<=.9+1/60,"sampling lease starts at native disguise and respects hard deadline")
        yes(s.hides[i]-returned.at<=.33+1/60,"display-only settle and fade end by first frame after their deadline")
    end
    eq(#s.exposedUnreadyFrames,0,"two-frame native repaint model never exposes an unready normal gap")
    scan.Reset("disabled")
    restored(s,"disabled between leases")
end
for _,kind in ipairs({"RightButton","LeftButton","Button8","mouselook","combat","dead","window","map-hover",
    "geometry","shape","zoom","mapid","anchor","renderer-loss"}) do
    local s,scan=client(); s.result()
    eq(s.standShown,false,"consumable result exposes native map after handoff")
    eq(scan.IsActive(),false,"successful result owns no native lease")
    local x,y=100,200
    if kind:find("Button",1,true) then s.mouse[kind]=true
    elseif kind=="mouselook" then s.look=true
    elseif kind=="combat" then s.combat=true
    elseif kind=="dead" then s.dead=true
    elseif kind=="window" then s.foci={{}}
    elseif kind=="map-hover" then s.cx,s.cy=110,210
    elseif kind=="geometry" then s.map.width=49
    elseif kind=="shape" then s.shape="SQUARE"
    elseif kind=="zoom" then s.map.zoom=1
    elseif kind=="mapid" then s.mapID=1427
    elseif kind=="anchor" then
        s.map:ClearAllPoints(); s.map:SetPoint("BOTTOMLEFT",s.env.WorldFrame,"BOTTOMLEFT",300,400); x,y=300,400
    elseif kind=="renderer-loss" then s.standShown=false end
    local moves=#s.placements
    s.tick(nil,false)
    eq(scan.ScanDiagnostics().standInRetained,false,kind.." cannot leave a retained replacement")
    eq(#s.placements,moves,kind.." native gap never touches restored map position")
    restored(s,kind.." between leases",x,y)
end
for _,event in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_REGEN_DISABLED","PLAYER_DEAD","PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","MINIMAP_UPDATE_ZOOM","ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED"}) do
    local s,scan=client(); s.result(); local moves=#s.placements
    s.event(event)
    restored(s,event.." native-gap cleanup")
    eq(scan.ScanDiagnostics().standInRetained,false,event.." cannot leave retained picture")
    eq(#s.placements,moves,event.." returns picture without another native move")
end
for _,reason in ipairs({"reset","source-change","original-source","disabled"}) do
    local s,scan=client(); s.result()
    eq(scan.IsActive(),false,"source reset exercises native-map gap")
    scan.Reset(reason)
    restored(s,"native-gap reset "..reason)
    for _=1,10 do s.tick(nil,false) end
    eq(s.standShown,false,"source change cannot resurrect old picture without source polling")
end
do
    local s,scan=client(); s.result()
    local shows=s.showCount
    for _=1,60 do s.tick(.02,false); scan.ScanDiagnostics() end
    restored(s,"no HUD polling leaves original map")
    eq(s.showCount,shows,"diagnostics and driver alone never start another lease")
end
do
    local s,scan=client(); s.result()
    local receipt=s.now
    for _=1,8 do
        s.now=s.now+.02
        eq(scan.ScanNames(),nil,"native-map gap does not replay previously consumed names")
    end
    eq(scan.ScanDiagnostics().publications,1,"native-map gap does not invent a new publication")
    yes(s.now-receipt<.6,"fresh receipt check stays within old TTL")
end
for _,target in ipairs({"map","part"}) do
    local s,scan=client()
    s.confirmed()
    s.foci={target=="map" and s.map or s.child}
    eq(scan.ScanNames(),nil,"F0 cached native focus waits for display handoff")
    eq(s.standShown,true,"F0 cached native focus does not remove repaint protection")
    s.foci={s.env.WorldFrame}
    eq(s.tick(),nil,"next frame clears cached focus but still waits for native presentation")
    eq(s.tick(),nil,"F+2 starts fade without consuming confirmed name")
    s.endDisplay()
    local result=scan.ScanNames()
    eq(result and result[1].name,"铜矿","fresh focus after F0 preserves confirmed receipt")
    eq(scan.ScanDiagnostics().standInRetained,false,"receipt consumption never retains replacement picture")
    eq(scan.ScanNames(),nil,"cached-focus allowance never repeats resource receipt")
    s.foci={target=="map" and s.map or s.child}
    local moves=#s.placements
    for _=1,90 do eq(s.tick(),nil,"old native focus cannot start a new lease") end
    eq(scan.ScanDiagnostics().standInRetained,false,"next frame native focus remains strict")
    eq(#s.placements,moves,"stale-focus cleanup does not move already restored map")
    restored(s,"next-frame strict focus")
end
for _,target in ipairs({"map","part"}) do
    local s,scan=client(); s.confirmed()
    s.foci={target=="map" and s.map or s.child}
    local writes=#s.nativeWrites
    s.tick(nil,false)
    restored(s,"cached focus beyond restored frame")
    eq(#s.nativeWrites,writes,"F+1 stale focus cancels only display, without native restoration")
    eq(scan.ScanNames(),nil,"same-frame focus exception never extends into F+1")
end
for _,target in ipairs({"map","part"}) do
    local s,scan=client(); s.confirmed()
    s.foci={target=="map" and s.map or s.child}
    local frame,observedAt=s.frame,s.now
    s.now=s.now+.34
    for _,timer in ipairs(s.timers) do if not timer.done and timer.at<=s.now then timer.done=true; timer.fn() end end
    eq(s.frame,frame,"same-frame focus exception is tested without inventing another rendered frame")
    local result=scan.ScanNames()
    eq(result and result[1].name,"铜矿","F0 cached native focus still permits a fresh deadline-finished receipt")
    eq(result[1].seenAt,observedAt,"F0 cached focus exception does not refresh observation time")
    restored(s,"same-frame cached focus and deadline")
end
for _,kind in ipairs({"window","map-hover","button-hover","RightButton","mouselook","geometry","anchor"}) do
    local s,scan=client()
    s.confirmed()
    s.foci={s.map}
    local x,y=100,200
    if kind=="window" then s.foci={{}}
    elseif kind=="map-hover" then s.cx,s.cy=110,210
    elseif kind=="button-hover" then s.cx,s.cy=170,220
    elseif kind=="RightButton" then s.mouse.RightButton=true
    elseif kind=="mouselook" then s.look=true
    elseif kind=="geometry" then s.map.width=49
    elseif kind=="anchor" then
        s.map:ClearAllPoints(); s.map:SetPoint("BOTTOMLEFT",s.env.WorldFrame,"BOTTOMLEFT",310,410); x,y=310,410
    end
    eq(scan.ScanNames(),nil,kind.." overrides same-frame stale-focus exception")
    s.tick(nil,false)
    eq(scan.ScanDiagnostics().standInRetained,false,kind.." drops retained picture immediately")
    restored(s,kind.." same-frame guard",x,y)
end
do
    -- Native focus is cached before OnUpdate. At 25 FPS the .1s HUD cadence
    -- sometimes polls in the same frame a short lease is returned. An ore on
    -- the outer map must remain reachable across those completed slices.
    local s,scan=client({width=198,height=198})
    s.node=function(x,y) if s.hit(x,y,179,99) then return "铜矿" end end
    scan.ScanNames()
    local elapsed,positive,maxCoverage=0,0,0
    for _=1,9000 do
        local x=s.cx/s.map:GetEffectiveScale()-(s.map:GetLeft() or 0)
        local y=s.cy/s.map:GetEffectiveScale()-(s.map:GetBottom() or 0)
        s.foci=(x>=0 and x<=s.map.width and y>=0 and y<=s.map.height) and {s.map} or {s.env.WorldFrame}
        s.tick(1/25,false)
        elapsed=elapsed+1/25
        if elapsed>=.1 then
            elapsed=0
            local result=scan.ScanNames()
            if result and #result>0 then
                eq(result[1].name,"铜矿","cached native focus still reports fresh outer-map ore")
                positive=positive+1
            end
        end
        local d=scan.ScanDiagnostics()
        maxCoverage=math.max(maxCoverage,d.total>0 and d.coverage/d.total or 0)
    end
    yes(positive>0,"25fps native cached-focus regression reaches peripheral resource")
    yes(maxCoverage>=.9,"cached focus cannot keep restarting before full-map coverage")
    yes(scan.ScanDiagnostics().passes>0,"cached focus still permits complete grid pass")
    scan.Reset("disabled")
    restored(s,"cached-focus long run")
end
do
    -- Two frequently due center rechecks must leave room for new grid work.
    -- The peripheral ore appears only after both persistent near ores are known.
    local s,scan=client({width=198,height=198})
    local counts,edgeVisible,maxCoverage={},false,0
    s.node=function(x,y)
        if s.hit(x,y,99,99) then return "铜矿" end
        if s.hit(x,y,117,99) then return "锡矿" end
        if edgeVisible and s.hit(x,y,179,99) then return "银矿" end
    end
    scan.ScanNames()
    local elapsed=0
    for _=1,9000 do
        local x=s.cx/s.map:GetEffectiveScale()-(s.map:GetLeft() or 0)
        local y=s.cy/s.map:GetEffectiveScale()-(s.map:GetBottom() or 0)
        s.foci=(x>=0 and x<=s.map.width and y>=0 and y<=s.map.height) and {s.map} or {s.env.WorldFrame}
        s.tick(1/25,false)
        elapsed=elapsed+1/25
        if elapsed>=.1 then
            elapsed=0
            local result=scan.ScanNames()
            for _,entry in ipairs(result or {}) do counts[entry.name]=(counts[entry.name] or 0)+1 end
            if counts["铜矿"] and counts["锡矿"] then edgeVisible=true end
        end
        local d=scan.ScanDiagnostics()
        maxCoverage=math.max(maxCoverage,d.total>0 and d.coverage/d.total or 0)
    end
    yes((counts["铜矿"] or 0)>1,"first persistent near ore is freshly rechecked")
    yes((counts["锡矿"] or 0)>1,"second persistent near ore is freshly rechecked")
    yes((counts["银矿"] or 0)>0,"two due near-ore rechecks cannot starve a new peripheral ore")
    yes(maxCoverage>=.9,"multiple known ores preserve full-map grid progress")
    for i=2,#s.shows do
        yes(s.shows[i]-s.hides[i-1]>=1.5-1e-9,"multi-ore rechecks preserve original-map gap")
    end
    scan.Reset("disabled")
    restored(s,"multiple known ores long run")
end
for _,options in ipairs({{width=198,height=198},{width=198,height=144,parentScale=1.25,scale=.9}}) do
    local s,scan=client(options)
    s.map.anchors={{"TOPRIGHT",s.env.WorldFrame,"TOPRIGHT",-40,-50}}
    s.initialLeft,s.initialBottom=s.map:GetLeft(),s.map:GetBottom()
    s.onScale=function(frame,value)
        if value==s.initialLocalScale then
            local _,_,_,x,y=frame:GetPoint(1)
            near(x,-40,"original horizontal anchor restored before local scale")
            near(y,-50,"original vertical anchor restored before local scale")
        end
    end
    local width,height,zoom=s.map:GetWidth(),s.map:GetHeight(),s.map:GetZoom()
    s.moving()
    local scale=s.map:GetEffectiveScale()
    yes(math.max(width,height)*scale<=64+1e-8,"private map fits within 64 physical pixels")
    yes(scale<s.initialEffectiveScale,"large native map is temporarily compressed")
    near(s.snapshot.scale,s.initialEffectiveScale,"stand-in snapshot retains original physical scale")
    eq(s.snapshot.width,width,"stand-in keeps original width")
    eq(s.snapshot.height,height,"stand-in keeps original height")
    near(s.placements[1][1],width/2,"scaled real cursor still samples map center first")
    near(s.placements[1][2],height/2,"scaled anchor projection preserves vertical sample position")
    eq(s.result()[1].name,"铜矿","scaled native map produces a fresh confirmed name")
    restored(s,"scaled anchored map")
    eq(s.map:GetWidth(),width,"sampling never changes native width")
    eq(s.map:GetHeight(),height,"sampling never changes native height")
    eq(s.map:GetZoom(),zoom,"sampling never changes native zoom")
    yes(#s.viewRadiusReads>=3,"view radius checked before and during private lease")
    for _,radius in ipairs(s.viewRadiusReads) do eq(radius,100,"private scale preserves native world-view radius") end
end
for _,delta in ipairs({1,.0001}) do
    local s,scan=client({width=198,height=198})
    s.radiusChangesWithScale,s.radiusScaleDelta=true,delta
    s.attemptDisguise()
    restored(s,"scale changed view radius by "..delta)
    eq(s.reads,0,"any radius change aborts before native tooltip sampling")
    eq(#s.placements,0,"radius mismatch never moves native map to sample")
    eq(scan.ScanNames(),nil,"changed world-view radius cannot publish resource")
end
do
    local s,scan=client({width=198,height=198}); s.moving()
    local reads=s.reads
    s.viewRadius=s.viewRadius+.0001; s.tick(nil,false)
    restored(s,"live radius change")
    eq(s.reads,reads,"live radius change stops before another tooltip read")
    eq(scan.ScanNames(),nil,"live radius change invalidates the whole candidate")
end
for _,failure in ipairs({"failScaleBefore","failScaleAfter"}) do
    local s,scan=client({width=198,height=198}); s[failure]=true
    s.attemptDisguise()
    restored(s,failure)
    eq(s.reads,0,failure.." cannot read native tooltip")
    eq(#s.placements,0,failure.." cannot move native map")
    eq(scan.ScanDiagnostics().publications,0,failure.." cannot publish receipt")
end
do
    local s,scan=client({width=198,height=198}); s.moving()
    local privateScale=s.map:GetScale()
    s.failScaleRestore=true; s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"scale restore failure retains recovery")
    near(s.map:GetLeft(),s.initialLeft,"anchors return before failed scale restore")
    near(s.map:GetScale(),privateScale,"failed scale restore remains visibly unfinished")
    eq(s.standShown,true,"scale restore failure keeps replacement protection")
    eq(scan.ScanNames(),nil,"scale recovery cannot publish candidate")
    s.failScaleRestore=false; s.tick(.2,false)
    restored(s,"scale restore retried by driver")
    eq(scan.IsActive(),false,"successful retry releases all scale ownership")
end
for _,sameValue in ipairs({false,true}) do
    local s,scan=client({width=198,height=198}); s.moving()
    local externalScale=sameValue and s.map:GetScale() or .6
    s.map:SetScale(externalScale)
    restored(s,"external explicit scale",nil,nil,nil,externalScale)
    eq(scan.IsActive(),false,"external scale setter cancels even when its value matches private scale")
    eq(scan.ScanNames(),nil,"external scale takeover cannot publish unfinished name")
    for _=1,20 do s.tick(nil,false) end
    near(s.map:GetScale(),externalScale,"passive cleanup never overwrites external scale owner")
end
do
    local s,scan=client({width=198,height=198})
    s.node=function(x,y)
        local names={}
        if s.hit(x,y,91,99) then names[#names+1]="铜矿" end
        if s.hit(x,y,107,99) then names[#names+1]="锡矿" end
        return #names>0 and names or nil
    end
    local result=s.result()
    eq(#result,2,"compressed overlapping physical hit areas preserve both resource names")
    local names={}; for _,item in ipairs(result) do names[item.name]=true; eq(item.dx,nil,"aggregate carries no navigation") end
    yes(names["铜矿"] and names["锡矿"],"both A-blank-A names reach the result")
    eq(scan.ScanDiagnostics().tooltipKnownCount,2,"two names still require two separate native hit frames")
    eq(scan.ScanDiagnostics().tooltipNilCount,1,"aggregate also requires outside blank control")
    restored(s,"overlapping resource names")
end
do
    local s,scan=client({width=198,height=198})
    s.override=function(state)
        if state.reads==1 then return {lines={{leftText="铜矿"},{leftText="锡矿"}}} end
        if state.reads==3 then return {lines={{leftText="铜矿"}}} end
    end
    local result=s.result()
    eq(#result,1,"name lost during A-blank-A is not inherited from aggregate candidate")
    eq(result[1].name,"铜矿","only freshly reconfirmed aggregate name is accepted")
end
for _,point in ipairs({{94,194},{187.3,104.7},{67.1,12.7}}) do
    local s,scan=client({width=198,height=198})
    s.node=function(x,y) if s.hit(x,y,point[1],point[2]) then return "铜矿" end end
    eq(s.result()[1].name,"铜矿","non-grid peripheral position "..point[1]..","..point[2].." is reachable")
    restored(s,"peripheral physical hit footprint")
end
for _,options in ipairs({{width=198,height=198},{width=198,height=198,shape="SQUARE"},{width=198,height=144}}) do
    local s,scan=client(options); s.node=function() end
    eq(#s.result(),0,"complete empty map coverage produces negative result")
    yes(scan.ScanDiagnostics().passes>0,"physical-coverage measurement finishes a full pass")
    local scale=s.samples[1].scale
    local width,height=options.width*scale,options.height*scale
    near(s.samples[1].physicalX,width/2,"full-map sequence starts at horizontal center")
    near(s.samples[1].physicalY,height/2,"full-map sequence starts at vertical center")
    local quadrants,angles={},{}
    for i,p in ipairs(s.samples) do
        local dx,dy=(p.physicalX-width/2)/(width/2),(p.physicalY-height/2)/(height/2)
        if i<=16 and dx*dx+dy*dy>=.65^2 and math.abs(dx)>.01 and math.abs(dy)>.01 then
            quadrants[(dx<0 and "L" or "R")..(dy<0 and "B" or "T")]=true
        end
        if math.abs(dx*dx+dy*dy-1)<1e-7 then angles[#angles+1]=math.atan2(dy,dx) end
    end
    for _,quadrant in ipairs({"LB","LT","RB","RT"}) do yes(quadrants[quadrant],"early sample prefix reaches peripheral "..quadrant) end
    local worst=0
    local function measure(x,y)
        local nearest=math.huge
        for _,p in ipairs(s.samples) do nearest=math.min(nearest,(p.physicalX-x)^2+(p.physicalY-y)^2) end
        worst=math.max(worst,math.sqrt(nearest))
    end
    for x=0,width,.5 do for y=0,height,.5 do
        if options.shape=="SQUARE" or ((x-width/2)/(width/2))^2+((y-height/2)/(height/2))^2<=1 then measure(x,y) end
    end end
    if options.shape~="SQUARE" then
        for i=0,359 do local a=i*math.pi/180; measure(width/2*(1+math.cos(a)),height/2*(1+math.sin(a))) end
        table.sort(angles)
        yes(#angles>2,"circle perimeter has explicitly sampled native positions")
        local maximumArc=0
        for i,a in ipairs(angles) do
            local nextAngle=angles[i+1] or angles[1]+2*math.pi
            maximumArc=math.max(maximumArc,(nextAngle-a)*math.max(width,height)/2)
        end
        yes(maximumArc<=6+1e-7,"boundary arc gaps never exceed six physical pixels")
    end
    yes(worst<6,"actual sampled physical points leave no six-pixel hit-radius holes")
    restored(s,"full physical coverage")
end
do
    local s,scan=client({width=198,height=198,tooltip=true}); s.moving()
    local tip=s.tooltip
    tip:SetMinimapMouseover()
    eq(tip.shown,false,"explicit minimap tooltip is hidden only while native map is displaced")
    s.tooltipOwner=s.env.WorldFrame; tip:Show()
    eq(tip.shown,true,"unrelated visible tooltip is preserved during scan")
    s.tooltipOwner=s.map; tip:Show()
    eq(tip.shown,false,"displaced native map owner proves tooltip belongs to private scan")
    s.child.parent=s.map
    s.tooltipOwner={GetParent=function() return s.child end}; tip:Show()
    eq(tip.shown,false,"known minimap descendant proves displaced tooltip ownership")
    local traversals=0
    local chain=s.map
    for _=1,12 do local parent=chain; chain={GetParent=function() traversals=traversals+1; return parent end} end
    s.tooltipOwner=chain
    local boundedHides=tip.hides; tip:Show()
    eq(tip.hides,boundedHides,"owner beyond bounded ancestry cannot authorize tooltip hiding")
    yes(traversals<=8,"tooltip ancestry traversal remains bounded")
    local parentReads=0
    s.tooltipOwner={secret=true,GetParent=function() parentReads=parentReads+1 end}
    local hides=tip.hides; tip:Show()
    eq(tip.hides,hides,"restricted owner cannot authorize tooltip hiding")
    eq(parentReads,0,"restricted owner is not traversed")
    s.ownerError=true; tip:Show()
    eq(tip.hides,hides,"unreadable owner cannot authorize tooltip hiding")
    s.ownerError=false; s.tooltipOwner=s.map
    local inverse=s.map.AdjustPointsOffset
    s.map.AdjustPointsOffset=function() error("temporary inverse failure") end
    s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"tooltip test reaches displaced recovery")
    tip:SetMinimapMouseover()
    eq(tip.shown,false,"still-displaced recovery also hides only its native minimap tooltip")
    s.map.AdjustPointsOffset=inverse; s.tick(.2,false)
    tip:Show(); eq(tip.shown,true,"original map tooltip remains visible after restoration")
    tip:SetMinimapMouseover(); eq(tip.shown,true,"native minimap method is untouched outside displaced scan")
    eq(tip.textReads,0,"visual suppression never reads native tooltip text")
    restored(s,"tooltip ownership")
end
for _,options in ipairs({{tooltip=true,noTooltipOwner=true},{tooltip=true,noTooltipMethod=true}}) do
    local s,scan=client(options)
    s.moving(); s.tooltip:Show()
    if options.noTooltipOwner then eq(s.tooltip.shown,true,"missing owner API is not permission to hide tooltip") end
    eq(s.result()[1].name,"铜矿","optional visual tooltip API is not required for name source")
    restored(s,"optional tooltip capabilities")
end
-- Native frame setters/readbacks round to float32. Lua-only doubles concealed
-- a real dev16 failure that left the private compressed scale as the next
-- baseline. These tests model that boundary; they do not establish live range.
eq(float32(1+2^-24),1,"float32 midpoint rounds to the even mantissa")
eq(float32(1+3*2^-24),1+2^-22,"float32 odd-mantissa midpoint rounds upward")
eq(float32(-1-3*2^-24),-1-2^-22,"float32 rounding is symmetric for negative coordinates")
eq(float32(198.00006103516),198.00006103515625,"float32 model reproduces native width precision")
eq(float32(.63999998569489),.63999998569488525390625,"float32 model reproduces native parent scale precision")
for _,options in ipairs({
    {width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,scale=1,float32=true},
    {width=173.21973,height=201.12503,parentScale=.68333334,scale=.91327189,float32=true},
    {width=64.000061,height=64.000061,parentScale=1,scale=1,float32=true},
}) do
    local s,scan=client(options)
    local width,height=s.map:GetWidth(),s.map:GetHeight()
    local originalPixels=width*s.initialEffectiveScale
    for round=1,12 do
        local result=s.result()
        eq(result[1].name,"铜矿","float32 round "..round.." confirms a fresh native name")
        eq(s.map:GetScale(),s.initialLocalScale,"float32 round "..round.." returns exact original local scale")
        eq(s.map:GetEffectiveScale(),s.initialEffectiveScale,"float32 round "..round.." returns original effective scale")
        eq(s.snapshot.width,width,"repeat stand-in snapshot never adopts a smaller width")
        eq(s.snapshot.height,height,"repeat stand-in snapshot never adopts a smaller height")
        eq(s.snapshot.scale,s.initialEffectiveScale,"repeat stand-in snapshot never adopts private scale")
        eq(s.snapshot.width*s.snapshot.scale,originalPixels,"stand-in physical width remains original across scans")
        restored(s,"float32 round "..round)
    end
    local roundedWrites=0
    for _,write in ipairs(s.mutations) do
        if write.kind=="scale" and write.value~=write.actual then roundedWrites=roundedWrites+1 end
    end
    yes(roundedWrites>=12,"each repeated lease crosses a real requested-versus-native float boundary")
end
for _,failure in ipairs({"failScaleBefore","failScaleAfter"}) do
    local s,scan=client({width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,float32=true})
    s[failure]=true; s.attemptDisguise()
    eq(s.map:GetScale(),s.initialLocalScale,failure.." preserves original scale despite float32 write behavior")
    eq(scan.IsActive(),false,failure.." completes float32 rollback")
    restored(s,"float32 "..failure)
    eq(s.reads,0,"failed float32 scale write never starts a tooltip read")
    eq(scan.ScanDiagnostics().publications,0,"failed float32 scale write never publishes")
    s[failure]=false
    eq(s.result()[1].name,"铜矿","float32 write failure does not poison the next original-size scan")
    eq(s.map:GetScale(),s.initialLocalScale,"successful retry does not adopt failed private scale")
end
for _,failure in ipairs({"failScaleRestore","failScaleRestoreAfter"}) do
    local s,scan=client({width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,float32=true})
    s.moving(); s[failure]=true; s.event("GLOBAL_MOUSE_DOWN")
    eq(scan.IsActive(),true,"float32 "..failure.." retains explicit recovery")
    eq(s.standShown,true,"float32 restoration error keeps protection until confirmed")
    eq(scan.ScanNames(),nil,"float32 recovery cannot publish or start another lease")
    s[failure]=false; s.tick(.2,false)
    eq(s.map:GetScale(),s.initialLocalScale,"float32 restore retry returns exact original scale")
    restored(s,"float32 "..failure.." recovered")
    eq(s.result()[1].name,"铜矿","recovered float32 original permits the next real scan")
    eq(s.snapshot.scale,s.initialEffectiveScale,"recovered stand-in keeps original size")
end
for _,fraction in ipairs({0,3e-7}) do
    local s,scan=client({width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,float32=true})
    s.moving()
    local requested=s.map:GetScale()*(1+fraction)
    s.map:SetScale(requested)
    eq(s.map:GetScale(),float32(requested),"explicit external float32 scale setter retains its own value")
    eq(scan.IsActive(),false,"external same or near numeric value still cancels ownership")
    eq(scan.ScanNames(),nil,"external float32 scale takeover cannot publish a candidate")
    for _=1,20 do s.tick(nil,false) end
    eq(s.map:GetScale(),float32(requested),"float readback tolerance never authorizes overwriting an external setter")
    restored(s,"float32 external scale",nil,nil,nil,float32(requested))
end
do
    local s,scan=client({width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,
        float32=true,displacementError=.25})
    s.moving(); s.tick(nil,false)
    eq(scan.ScanDiagnostics().reason,"sample-alignment","inconsistent native projection is diagnosed before reading")
    eq(s.reads,0,"misaligned native projection cannot read an apparent empty sample")
    eq(scan.ScanDiagnostics().publications,0,"misalignment cannot certify a completed empty map")
    eq(scan.ScanNames(),nil,"misalignment cannot deliver a resource receipt")
    restored(s,"misaligned native projection")
    eq(s.map:GetScale(),s.initialLocalScale,"misalignment recovery retains original native size")
end
-- Native leases and replacement display now end at different moments. Normal
-- restoration F0 leaves only a display token; unsafe input still removes it at
-- once. The independent two-frame renderer below is deliberately a hypothesis.
for _,fps in ipairs({60,25}) do
    for _,reason in ipairs({"positive","slice","complete"}) do
        local s,scan=client({width=198,height=198,presentNativeAfterFrames=2})
        if reason~="positive" then s.node=function() end end
        scan.ScanNames()
        local found=false
        for _=1,6000 do
            s.tick(1/fps,false)
            local d=scan.ScanDiagnostics()
            if d.handoff and d.reason==reason then found=true; break end
            scan.ScanNames()
        end
        yes(found,fps.."fps reaches normal "..reason.." native return")
        local returnedAt,returnedFrame=s.now,s.frame
        local writes,moves,reads,shows=#s.nativeWrites,#s.placements,s.reads,s.showCount
        nativeRestored(s,reason.." F0")
        local d=scan.ScanDiagnostics()
        eq(d.active,false,"handoff owns no active native scan")
        eq(d.recovering,false,"handoff owns no native restoration")
        eq(scan.IsActive(),true,"public source lifecycle includes unfinished display handoff")
        eq(s.standShown,true,"F0 preserves replacement while original pixels are pending")
        eq(s.nativeGPUReady,false,"independent native pixel model is not ready at restoration F0")
        for _=1,5 do eq(scan.ScanNames(),nil,"same-frame HUD polls cannot bypass display handoff") end
        eq(s.tick(1/fps),nil,"F+1 does not expose or consume pending native result")
        eq(s.standShown,true,"F+1 replacement covers modeled native repaint")
        eq(s.tick(1/fps),nil,"F+2 starts fade-out without consuming a pending result")
        eq(s.standShown,true,"F+2 retains the stand-in for gradual fade-out")
        yes(s.presentedNativeFrame>=returnedFrame+2,"modeled native pixels have been presented before reveal")
        s.endDisplay(1/fps)
        local result=scan.ScanNames()
        eq(s.standShown,false,"completed fade-out reveals restored native picture")
        eq(#s.exposedUnreadyFrames,0,"normal handoffs leave no gap under two-frame presentation assumption")
        eq(#s.nativeWrites,writes,"display-only handoff performs no native setter or restoration")
        eq(#s.placements,moves,"display-only handoff does not move native map")
        eq(s.reads,reads,"display-only handoff does not sample tooltips")
        eq(s.showCount,shows,"display-only handoff does not start another scan")
        if reason=="positive" then
            eq(result and result[1].name,"铜矿","positive receipt is consumed only after presentation")
            eq(result[1].seenAt,returnedAt,"handoff preserves original observation timestamp")
        elseif reason=="complete" then eq(result and #result,0,"complete negative receipt waits for presentation")
        else eq(result,nil,"incomplete slice never becomes a negative receipt") end
        local hidden=s.hides[#s.hides]
        while s.now-hidden<1.5-1/fps-1e-8 do
            s.tick(1/fps)
            eq(s.showCount,shows,"native-view interval begins at actual replacement Hide")
        end
        scan.Reset("disabled")
        restored(s,"normal handoff "..reason)
    end
end
for _,kind in ipairs({"reset","source-change","original-source","disabled","RightButton","LeftButton","Button8",
    "pointer","window","mouselook","combat","dead","geometry","shape","zoom","mapid","radius","stand",
    "cursor-error","clock-error"}) do
    local s,scan=client(); s.confirmed()
    eq(scan.ScanDiagnostics().handoff,true,kind.." begins after all native leases returned")
    local writes,moves,reads=#s.nativeWrites,#s.placements,s.reads
    if kind=="reset" or kind=="source-change" or kind=="original-source" or kind=="disabled" then scan.Reset(kind)
    elseif kind:find("Button",1,true) then s.mouse[kind]=true
    elseif kind=="pointer" then s.cx=s.cx+.6
    elseif kind=="window" then s.foci={{}}
    elseif kind=="mouselook" then s.look=true
    elseif kind=="combat" then s.combat=true
    elseif kind=="dead" then s.dead=true
    elseif kind=="geometry" then s.map.width=49
    elseif kind=="shape" then s.shape="SQUARE"
    elseif kind=="zoom" then s.map.zoom=1
    elseif kind=="mapid" then s.mapID=1427
    elseif kind=="radius" then s.viewRadius=100.0001
    elseif kind=="stand" then s.standShown=false
    elseif kind=="cursor-error" then s.cursorError=true
    elseif kind=="clock-error" then s.clockError=true end
    if scan.ScanDiagnostics().handoff then s.tick(nil,false) end
    eq(s.standShown,false,kind.." clears replacement on first observable handoff interruption")
    eq(scan.ScanDiagnostics().handoff,false,kind.." clears independent display token")
    eq(#s.nativeWrites,writes,kind.." does not restore already returned native state")
    eq(#s.placements,moves,kind.." does not move native map")
    eq(s.reads,reads,kind.." does not sample another name")
    s.cursorError,s.clockError=false,false
    eq(scan.ScanNames(),nil,kind.." discards pending receipt")
end
for _,event in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_REGEN_DISABLED","PLAYER_DEAD","PLAYER_UNGHOST","PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","MINIMAP_UPDATE_ZOOM","ZONE_CHANGED","ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
    local s,scan=client(); s.confirmed()
    local writes,frame=#s.nativeWrites,s.frame
    s.event(event)
    eq(s.frame,frame,event.." clears handoff synchronously")
    restored(s,event.." display-only cancellation")
    eq(#s.nativeWrites,writes,event.." cancellation never repeats native restoration")
    eq(scan.ScanNames(),nil,event.." clears pending receipt")
end
do
    local s,scan=client(); s.confirmed()
    local writes,reads,frame,observedAt=#s.nativeWrites,s.reads,s.frame,s.now
    s.now=s.now+.34
    for _,timer in ipairs(s.timers) do if not timer.done and timer.at<=s.now then timer.done=true; timer.fn() end end
    eq(s.frame,frame,"deadline fallback can finish without another OnUpdate frame")
    restored(s,"handoff deadline fallback")
    eq(#s.nativeWrites,writes,"deadline callback owns no native restoration")
    eq(s.reads,reads,"deadline callback does not read a new resource")
    local result=scan.ScanNames()
    eq(result and result[1].seenAt,observedAt,"deadline completion never refreshes observation time")
end
do
    local s,scan=client(); s.confirmed()
    local writes=#s.nativeWrites
    s.tick(.7,false)
    restored(s,"delayed first runnable frame")
    eq(#s.nativeWrites,writes,"low-FPS completion does not retry native restoration")
    eq(scan.ScanNames(),nil,"blocked callbacks cannot renew a receipt beyond its original TTL")
end
do
    local s,scan=client(); s.confirmed()
    local oldTimers={}; for _,timer in ipairs(s.timers) do oldTimers[#oldTimers+1]=timer.fn end
    scan.Reset("source-change")
    s.moving()
    local hides,writes,reads=s.hideCount,#s.nativeWrites,s.reads
    for _,callback in ipairs(oldTimers) do callback() end
    eq(s.hideCount,hides,"obsolete deadlines cannot hide a later active scan's replacement")
    eq(#s.nativeWrites,writes,"obsolete deadlines cannot restore a later native lease")
    eq(s.reads,reads,"obsolete callbacks do not sample")
    for _=1,20 do s.tick(nil,false); if scan.ScanDiagnostics().handoff then break end end
    eq(scan.ScanDiagnostics().handoff,true,"later scan reaches its own display token")
    hides,writes=s.hideCount,#s.nativeWrites
    for _,callback in ipairs(oldTimers) do callback() end
    eq(s.hideCount,hides,"obsolete handoff token cannot hide a later display token")
    eq(#s.nativeWrites,writes,"obsolete callback cannot write into later handoff")
    s.endDisplay()
    eq(scan.ScanNames()[1].name,"铜矿","later token retains its own fresh receipt")
end
do
    local s,scan=client(); s.failHandoffTimer=true
    s.confirmed()
    restored(s,"handoff timer scheduling failure")
    eq(scan.ScanDiagnostics().handoff,false,"failed handoff timer cannot strand a display token")
    eq(scan.ScanDiagnostics().reason,"handoff-timer","timer scheduling failure retains its actual diagnostic")
    eq(scan.ScanNames(),nil,"failed handoff timer clears pending receipt")
    s.failHandoffTimer=false
    eq(s.result()[1].name,"铜矿","failed timer does not leave cleanup locked against later scans")
    restored(s,"scan after handoff timer failure")
end
for _,failure in ipairs({"failScaleRestore","failScaleRestoreAfter"}) do
    for _,writeError in ipairs({false,true}) do
        local s,scan=client({width=198.00006103516,height=198.00006103516,parentScale=.63999998569489,float32=true})
        local earlyReveals={}
        s.onNativeWrite=function(frame,method,value)
            local revealing=(method=="SetMaskTexture" and value~="Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask")
                or (method=="SetIconScale" and value~=0) or (method=="SetAlpha" and value>0)
                or ((method=="SetMouseClickEnabled" or method=="EnableMouseWheel" or method=="SetMouseMotionEnabled") and value)
            if revealing and s.map:GetScale()~=s.initialLocalScale then earlyReveals[#earlyReveals+1]=method end
        end
        if writeError then
            s.failScaleAfter,s[failure]=true,true
            s.attemptDisguise()
        else s.moving(); s[failure]=true; s.event("GLOBAL_MOUSE_DOWN") end
        eq(#earlyReveals,0,"failed scale restoration never attempts to reveal compact native decoration or input")
        eq(scan.ScanDiagnostics().recovering,true,"scale restore error retains explicit recovery")
        eq(s.mask,"Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask","failed scale restoration does not expose compact native mask")
        eq(s.icon,0,"failed scale restoration does not expose compact native icons")
        eq(s.child.alpha,0,"failed scale restoration keeps native chrome hidden")
        eq(s.map.clicks,false,"failed scale restoration keeps leased native clicks quiet")
        eq(s.standShown,true,"failed scale restoration retains replacement protection")
        eq(scan.ScanNames(),nil,"failed scale restoration cannot publish")
        s.failScaleAfter,s[failure]=false,false
        s.tick(.2,false)
        eq(#earlyReveals,0,"scale retry returns original geometry before every visible or input setter")
        restored(s,"ordered scale restoration retry")
        eq(s.map:GetScale(),s.initialLocalScale,"ordered scale recovery returns exact float32 baseline")
        eq(s.result()[1].name,"铜矿","ordered scale recovery leaves future scans usable")
    end
end
-- Fade opacity follows elapsed time, not a fixed number of update callbacks.
-- Only the addon artwork changes before a fully opaque frame is presented.
do
    local s,scan=client({width=198,height=198}); s.node=function() end
    s.start()
    local shownAt,writes=s.now,#s.nativeWrites
    eq(s.opacity,0,"fade-in begins transparent")
    eq(s.standShown,true,"transparent prepared artwork still has a shown lifecycle")
    for _,dt in ipairs({.03,.05,.04,.03,.04}) do
        s.tick(dt,false)
        near(s.opacity,math.min(1,(s.now-shownAt)/.18),"fade-in follows irregular real time")
        nativeRestored(s,"fade-in leaves native state intact")
        eq(#s.nativeWrites,writes,"fade-in does not mutate native map, parts or inputs")
        eq(s.reads,0,"preparation never reads resource names")
    end
    local opaqueFrame=s.frame
    s.tick(.12,false)
    eq(s.frame,opaqueFrame+1,"first opaque presentation completes a full native frame")
    eq(#s.nativeWrites,writes,"first opaque presentation still leaves native map untouched")
    s.tick(.04,false)
    yes(#s.placements>0,"native sampling begins only after the opaque frame")
    eq(s.placements[1].frame,opaqueFrame+2,"native move waits until F+2 after reaching opacity one")
    eq(s.opacity,1,"sampling is covered by opaque replacement")
    local leaseAt=s.nativeLeaseStarts[1].at
    yes(leaseAt-shownAt>.3,"test spends a substantial preparation interval before native lease")
    for _=1,30 do s.tick(.04,false); if scan.ScanDiagnostics().handoff then break end end
    eq(scan.ScanDiagnostics().reason,"slice","prepared empty map uses a full sampling slice")
    yes(s.now-leaseAt>=.65,"fade preparation does not consume the sampling budget")
    yes(s.now-leaseAt<=.65+.04+1e-8,"sampling budget stays bounded independently of preparation")
    s.endDisplay(); restored(s,"time-based preparation and sampling")
end
do
    local s,scan=client(); s.start()
    local writes=#s.nativeWrites
    s.tick(.51,false)
    restored(s,"preparation timeout")
    eq(scan.ScanDiagnostics().reason,"prepare-timeout","late preparation frame fails closed")
    eq(#s.nativeWrites,writes,"preparation timeout performs no native rollback because nothing was leased")
    eq(s.reads,0,"preparation timeout has no samples")
    eq(scan.ScanNames(),nil,"preparation timeout has no receipt")
end
for _,phase in ipairs({"fade-in","fade-out"}) do
    for _,failure in ipairs({"before","after","false"}) do
        local s,scan=client()
        if phase=="fade-in" then s.start(); s.tick(.05,false)
        else s.confirmed(); s.tick(nil,false); s.tick(nil,false); s.tick(.04,false) end
        yes(s.opacity>0 and s.opacity<1,"opacity failure occurs inside "..phase)
        local writes,reads=#s.nativeWrites,s.reads
        s.failOpacity=failure; s.tick(.02,false)
        restored(s,phase.." SetOpacity "..failure)
        eq(#s.nativeWrites,writes,"opacity error returns display without another native write")
        eq(s.reads,reads,"opacity error does not read names")
        eq(scan.ScanNames(),nil,"opacity error discards pending or unfinished receipt")
        eq(scan.ScanDiagnostics().reason,phase=="fade-in" and "stand-in-opacity" or "handoff-opacity","opacity error has explicit diagnostic")
        s.failOpacity=nil
        eq(s.result()[1].name,"铜矿","opacity failure does not prevent later fresh scan")
    end
end
for _,fps in ipairs({60,25}) do
    local s,scan=client({width=198,height=198,presentNativeAfterFrames=2})
    s.confirmed()
    local observedAt,writes,reads,moves=s.now,#s.nativeWrites,s.reads,#s.placements
    local opacityCount=#s.opacities
    s.tick(1/fps,false); s.tick(1/fps,false)
    local fadeAt,previous=s.now,s.opacity
    eq(previous,1,"settled original starts fade-out at full opacity")
    local intermediate=0
    for _=1,40 do
        s.tick(1/fps,false)
        nativeRestored(s,"fade-out retains fully restored native geometry and input")
        eq(#s.nativeWrites,writes,"fade-out writes only addon opacity")
        eq(s.reads,reads,"fade-out does not sample another tooltip")
        eq(#s.placements,moves,"fade-out never moves original map")
        yes(s.opacity<=previous,"fade-out opacity is monotonic")
        near(s.opacity,math.max(0,1-(s.now-fadeAt)/.18),"fade-out follows elapsed time")
        if s.opacity>0 and s.opacity<1 then intermediate=intermediate+1 end
        previous=s.opacity
        if not s.standShown then break end
        eq(scan.ScanNames(),nil,"partially faded display cannot consume receipt")
    end
    yes(intermediate>=3,"fade-out has multiple intermediate opacity presentations at "..fps.."fps")
    yes(#s.opacities>opacityCount+3,"fade-out uses actual opacity updates")
    yes(s.now-fadeAt>=.18,"normal fade-out is not replaced with immediate Hide")
    yes(s.now-fadeAt<=.18+1/fps+1e-8,"normal fade-out completes on first frame after duration")
    eq(#s.exposedUnreadyFrames,0,"fade never reveals unready native pixels in independent two-frame model")
    local result=scan.ScanNames()
    eq(result and result[1].seenAt,observedAt,"fade-out preserves original confirmed-name time")
    eq(scan.ScanNames(),nil,"fade completion is consumed once")
    restored(s,"normal fade-out at "..fps.."fps")
end
for _,phase in ipairs({"fade-in","fade-out"}) do
    for _,kind in ipairs({"reset","source-change","mouse-event","world-event","RightButton","pointer","window","combat","geometry","clock-error"}) do
        local s,scan=client()
        if phase=="fade-in" then s.start(); s.tick(.05,false)
        else s.confirmed(); s.tick(nil,false); s.tick(nil,false); s.tick(.04,false) end
        yes(s.opacity>0 and s.opacity<1,kind.." interrupts an actual partial "..phase)
        local writes,reads,frame=#s.nativeWrites,s.reads,s.frame
        local synchronous=true
        if kind=="reset" or kind=="source-change" then scan.Reset(kind)
        elseif kind=="mouse-event" then s.event("GLOBAL_MOUSE_DOWN")
        elseif kind=="world-event" then s.event("PLAYER_LEAVING_WORLD")
        else
            synchronous=false
            if kind=="RightButton" then s.mouse.RightButton=true
            elseif kind=="pointer" then s.cx=s.cx+.6
            elseif kind=="window" then s.foci={{}}
            elseif kind=="combat" then s.combat=true
            elseif kind=="geometry" then s.map.width=49
            elseif kind=="clock-error" then s.clockError=true end
            s.tick(.001,false)
        end
        eq(s.frame,frame+(synchronous and 0 or 1),kind.." ends fade at first observation without waiting duration")
        restored(s,kind.." interrupts "..phase)
        eq(#s.nativeWrites,writes,"fade cancellation does not restore already native state")
        eq(s.reads,reads,"fade interruption never reads another tooltip")
        s.clockError=false
        eq(scan.ScanNames(),nil,"fade interruption discards pending observation")
    end
end
do
    local s,scan=client(); s.confirmed()
    s.tick(.25,false)
    yes(s.standShown,"slow first callback starts late fade without changing native state")
    local writes=#s.nativeWrites
    s.tick(.09,false)
    restored(s,"final display deadline on first runnable frame")
    eq(#s.nativeWrites,writes,"final deadline never repeats native restoration")
    local result=scan.ScanNames()
    yes(result and result[1].seenAt<s.now-.3,"late fade fallback does not freshen receipt time")
end
do
    local s,scan=client(); s.start()
    local writes=#s.nativeWrites
    s.now=s.now+1.46
    for _,timer in ipairs(s.timers) do if not timer.done and s.now>=timer.at then timer.done=true; timer.fn() end end
    restored(s,"outer preparation watchdog without frame callbacks")
    eq(#s.nativeWrites,writes,"outer watchdog does not mutate untouched native state")
    eq(s.reads,0,"outer preparation watchdog does not sample")
end
do
    local s,scan=client(); s.moving()
    local leaseAt=s.nativeLeaseStarts[1].at
    s.now=leaseAt+.96
    for _,timer in ipairs(s.timers) do if not timer.done and s.now>=timer.at then timer.done=true; timer.fn() end end
    restored(s,"sampling watchdog without OnUpdate")
    eq(scan.ScanDiagnostics().reason,"timeout","independent sampling watchdog restores by own lease budget")
    eq(scan.ScanNames(),nil,"sampling watchdog cannot publish unfinished name")
    yes(s.now-s.shows[1]<1.45,"sampling watchdog returns before outer preparation deadline")
end
do
    local s,scan=client(); s.failSamplingTimer=true
    s.attemptDisguise()
    restored(s,"sampling watchdog scheduling failure")
    eq(scan.ScanDiagnostics().reason,"scan-timer","sampling timer scheduling failure has explicit diagnostic")
    eq(s.reads,0,"failed sampling timer cannot read resource")
    eq(scan.ScanNames(),nil,"failed sampling timer cannot publish")
    s.failSamplingTimer=false
    eq(s.result()[1].name,"铜矿","sampling timer failure does not lock later scans")
end
-- Restricted-name capability is a per-UI-session latch, not an empty map.
-- These hostile public shells throw if the implementation indexes, compares
-- as strings, or stringifies the secret values themselves.
for _,kind in ipairs({"data","lines","line","key","left","right"}) do
    local s,scan=client()
    eq(s.result()[1].name,"铜矿","secret test starts with an actual prior public receipt")
    s.moving()
    local accesses=0
    local value=setmetatable({secret=true},{__index=function() accesses=accesses+1;error("secret indexed") end,
        __tostring=function() accesses=accesses+1;error("secret stringified") end})
    local data
    if kind=="data" then data=value
    elseif kind=="lines" then data={lines=value}
    elseif kind=="line" then data={lines={value}}
    elseif kind=="key" then data={lines={[value]={leftText="铜矿"}}}
    elseif kind=="left" then data={lines={{leftText=value}}}
    else data={lines={{leftText="铜矿",rightText=value}}} end
    s.override=function() return data end
    s.tick(nil,false)
    restored(s,"secret "..kind)
    local d=scan.ScanDiagnostics()
    eq(d.state,"restricted",kind.." records restricted capability")
    eq(d.minimapRestricted,true,kind.." capability diagnostic")
    eq(s.ns.gatherMinimapAccessRestricted,true,kind.." shared latch set")
    eq(scan.IsSupported(),false,kind.." capability no longer reports supported")
    eq(#d.rawKnownNames,0,kind.." clears old raw names")
    eq(#d.acceptedNames,0,kind.." clears old accepted names")
    eq(scan.ScanNames(),nil,kind.." discards pending resource")
    local reads,writes,shows=s.reads,#s.nativeWrites,s.showCount
    s.override=nil
    for _=1,60 do
        scan.Reset("source-change")
        eq(s.tick(1),nil,kind.." cannot retry by resetting or waiting")
    end
    eq(s.reads,reads,kind.." restriction prevents all further native reads")
    eq(#s.nativeWrites,writes,kind.." restored map is not repeatedly changed")
    eq(s.showCount,shows,kind.." restriction never reopens stand-in")
    eq(accesses,0,kind.." secret contents never inspected or logged")
end
do
    local s,scan=client({clamped=true,width=198,height=198,cursorX=10})
    eq(s.result()[1].name,"铜矿","unclamping permits actual edge-of-screen name confirmation")
    restored(s,"edge scan")
    eq(s.map:IsClampedToScreen(),true,"clamp baseline returned")
    local unclamp,scaleRestore,reclamp,maskRestore
    for i,w in ipairs(s.nativeWrites) do
        if w.method=="SetClampedToScreen" and w.value==false then unclamp=unclamp or i end
        if w.method=="SetScale" and w.value==s.initialLocalScale then scaleRestore=i end
        if w.method=="SetClampedToScreen" and w.value==true then reclamp=i end
        if w.method=="SetMaskTexture" and w.value=="Textures\\MinimapMask" then maskRestore=i end
    end
    yes(unclamp~=nil,"clamped baseline is temporarily disabled")
    yes(scaleRestore<reclamp,"local scale restored before reclamp")
    yes(reclamp<maskRestore,"clamp returned before exposing original native mask")
end
do
    local s,scan=client({noClamp=true})
    eq(s.result()[1].name,"铜矿","optional clamp API absence preserves legacy public client")
    restored(s,"no clamp API")
end
for _,flag in ipairs({"failClampBefore","failClampAfter","clampGetterError","clampGetterSecret"}) do
    local s,scan=client({clamped=true})
    s[flag]=true;s.attemptDisguise()
    restored(s,flag)
    eq(s.map.clamped,true,flag.." leaves original clamp")
    eq(scan.ScanNames(),nil,flag.." cannot publish incomplete scan")
    s[flag]=false
    eq(s.result()[1].name,"铜矿",flag.." later valid scan can recover")
end
do
    local s,scan=client({clamped=true,width=198,height=198});s.moving()
    s.failClampRestore=true;s.override=function() return {lines={{leftText={secret=true}}}} end
    s.tick(nil,false)
    eq(scan.IsSupported(),false,"secret restriction survives a failed native cleanup")
    eq(scan.IsActive(),true,"failed clamp restoration remains active for recovery")
    eq(scan.ScanDiagnostics().recovering,true,"cleanup failure is explicit")
    eq(s.map.clicks,false,"failed clamp restore keeps hidden map input protected")
    eq(s.mask,"Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask","failed clamp restore does not expose native map")
    local reads=s.reads
    s.failClampRestore=false;s.tick(.2,false)
    restored(s,"restricted recovery")
    eq(s.map.clamped,true,"recovery returns clamp even though reading remains disabled")
    eq(scan.IsActive(),false,"recovery finishes without re-enabling scanner")
    eq(scan.IsSupported(),false,"successful native cleanup does not unlock secret names")
    eq(s.reads,reads,"recovery never samples secret names again")
end
for _,external in ipairs({false,true}) do
    local s,scan=client({clamped=true,width=198,height=198});s.moving()
    s.map:SetClampedToScreen(external)
    eq(scan.IsActive(),false,"explicit external clamp setter cancels own lease")
    eq(s.map.clamped,external,"external clamp owner keeps its exact choice")
    eq(scan.ScanNames(),nil,"external clamp takeover cannot publish old candidate")
    local writes=#s.nativeWrites
    scan.Reset()
    eq(s.map.clamped,external,"later reset never reclaims external clamp setting")
    eq(#s.nativeWrites,writes,"later cleanup has no remaining property lease")
end
-- The native alpha observation (.5 -> float32(128/255)) is modeled only at
-- the renderer contract boundary here. Stand-in tests exercise the actual
-- production renderer. This verifies that the scanner respects its handshake
-- despite quantization, rather than treating a rounded 1 as early permission.
do
    local s,scan=client({nativeAlpha8=true,float32=true,width=198,height=198})
    s.start()
    local writes=#s.nativeWrites
    s.tick(.05,false)
    local requested=s.opacities[#s.opacities].value
    yes(math.abs(s.opacity-requested)>1e-5,
        "native alpha fixture exercises readback differences larger than the old tolerance")
    yes(math.abs(s.opacity-float32(math.floor(requested*255+.5)/255))<1e-7,
        "stand-in contract accepts the actual 8-bit/float32 value")
    nativeRestored(s,"quantized partial fade leaves original intact")
    eq(#s.nativeWrites,writes,"partially opaque quantized proxy cannot lease the map")
    s.tick(.1299,false)
    eq(s.opacity,1,"native rounding can reach opacity one before requested fade completes")
    yes(s.opacities[#s.opacities].value<1,"rounded opacity one is not the explicit full-opacity request")
    eq(#s.nativeWrites,writes,"early quantized one does not start native sampling")
    s.tick(.00005,false)
    eq(#s.nativeWrites,writes,"remaining fractional fade does not spend a native lease")
    s.tick(.0001,false)
    local requestedFullFrame=s.frame
    eq(s.opacities[#s.opacities].value,1,"scanner explicitly requests the exact opaque endpoint")
    yes(requestedFullFrame>s.opaqueFrame,"explicit endpoint follows the earlier rounded-up value")
    eq(#s.nativeWrites,writes,"successful full-opacity request still waits a complete frame")
    s.tick(.01,false)
    eq(#s.nativeWrites,writes,"first complete opaque presentation does not move original")
    s.tick(.01,false)
    yes(#s.placements>0,"accepted exact endpoint eventually allows native sampling")
    eq(s.placements[1].frame,requestedFullFrame+2,"native move follows explicit opacity handshake by two frames")
    eq(s.opacity,1,"sampling uses the exact native opaque endpoint")
    eq(s.result()[1].name,"铜矿","quantized fade still permits fresh confirmed resource results")
    restored(s,"quantized alpha scan")
end
do
    local s,scan=client({nativeAlpha8=true,float32=true,width=198,height=198})
    s.lowerOpaqueEndpoint=true
    s.start()
    local writes=#s.nativeWrites
    for _=1,30 do
        s.tick(nil,false)
        if scan.ScanDiagnostics().reason=="stand-in-opacity" then break end
    end
    eq(scan.ScanDiagnostics().reason,"stand-in-opacity","254/255 at a requested one is a renderer failure")
    yes(math.abs(s.opacity-float32(254/255))<1e-7,"failed endpoint is genuinely below fully opaque")
    eq(#s.nativeWrites,writes,"rejected opaque endpoint never changes native map or input")
    eq(#s.placements,0,"rejected opaque endpoint cannot start movement")
    eq(s.reads,0,"rejected opaque endpoint cannot read a resource")
    eq(scan.ScanNames(),nil,"rejected opaque endpoint cannot leak a resource receipt")
    eq(s.ns.gatherMinimapAccessRestricted,nil,"alpha failure is not mislabeled as restricted resource data")
    restored(s,"rejected quantized opaque endpoint")
    s.lowerOpaqueEndpoint=false
    eq(s.result()[1].name,"铜矿","later valid opaque handshake recovers without unlocking a data restriction")
    restored(s,"opaque endpoint recovery")
end
-- Secret-name passthrough (explicit setting). The hostile shell throws if the
-- implementation indexes, compares or stringifies the secret; the scanner may
-- only carry it to the caller for display.
do
    local s,scan=client()
    s.ns.db=s.ns.db or {}
    s.ns.db.gatherOpaque=true
    local accesses=0
    local value=setmetatable({secret=true},{__index=function() accesses=accesses+1;error("secret indexed") end,
        __tostring=function() accesses=accesses+1;error("secret stringified") end,
        __eq=function() accesses=accesses+1;error("secret compared") end,
        __len=function() accesses=accesses+1;error("secret measured") end,
        __concat=function() accesses=accesses+1;error("secret concatenated") end})
    s.override=function(state)
        local scale=state.env.Minimap:GetEffectiveScale()
        local x,y=state.cx/scale-state.env.Minimap:GetLeft(),state.cy/scale-state.env.Minimap:GetBottom()
        if state.hit(x,y,state.env.Minimap.width/2,state.env.Minimap.height/2) then return {lines={{leftText=value}}} end
    end
    local r=s.result()
    eq(#r,1,"passthrough publishes one confirmed hit")
    eq(r[1].name,s.ns.GATHER_OPAQUE_NAME,"passthrough hit uses the placeholder key, not a readable name")
    eq(r[1].kind,"opaque","passthrough hit is not given a catalogue kind")
    eq(r[1].opaque,true,"passthrough hit is flagged")
    yes(rawequal(r[1].text,value),"the secret itself is carried for display")
    eq(r[1].dx,nil,"passthrough gives no coordinates"); eq(r[1].bearing,nil,"passthrough gives no direction")
    eq(accesses,0,"the secret was never indexed, compared, measured, concatenated or stringified")
    eq(s.ns.gatherMinimapAccessRestricted,nil,"a secret name no longer latches the session when passthrough is on")
    eq(scan.IsSupported(),true,"scanner stays available")
    yes(type(r[1].data)=="table" and rawequal(r[1].data.lines[1].leftText,value),"the whole tooltip record is carried for the fallback")
    restored(s,"passthrough positive")
    eq(scan.ScanNames(),nil,"passthrough receipt is consumed once")
    -- People and creature blips are dropped by their public type or GUID, not by text.
    for _,shape in ipairs({{guid="Player-1234-00000001"},{guid="Creature-0-1-2-3-4-5"},{lineType=2},{lineType=16}}) do
        s.moving()
        s.override=function(state)
            local scale=state.env.Minimap:GetEffectiveScale()
            local x,y=state.cx/scale-state.env.Minimap:GetLeft(),state.cy/scale-state.env.Minimap:GetBottom()
            if state.hit(x,y,state.env.Minimap.width/2,state.env.Minimap.height/2) then
                return {guid=shape.guid,lines={{leftText=value,type=shape.lineType}}}
            end
        end
        local published=false
        for _=1,1500 do
            local res=s.tick()
            for _,item in ipairs(res or {}) do if item.name==s.ns.GATHER_OPAQUE_NAME then published=true end end
        end
        eq(published,false,"unit blip is not published: "..tostring(shape.guid or shape.lineType))
        eq(s.ns.gatherMinimapAccessRestricted,nil,"unit blip does not latch the session")
        scan.Reset("next-shape")
    end
    -- A gathering node GUID is not filtered.
    s.override=function(state)
        local scale=state.env.Minimap:GetEffectiveScale()
        local x,y=state.cx/scale-state.env.Minimap:GetLeft(),state.cy/scale-state.env.Minimap:GetBottom()
        if state.hit(x,y,state.env.Minimap.width/2,state.env.Minimap.height/2) then
            return {guid="GameObject-0-1-2-3-4-5",lines={{leftText=value,type=0}}}
        end
    end
    eq(s.result()[1].name,s.ns.GATHER_OPAQUE_NAME,"a GameObject blip is still published")
    -- Other secret containers still latch: only the text field has a display path.
    s.moving()
    s.override=function() return {lines=value} end
    s.tick(nil,false)
    eq(s.ns.gatherMinimapAccessRestricted,true,"secret line container still latches with passthrough on")
    eq(accesses,0,"latching did not touch the secret")
end
-- With the setting off the earlier contract holds (covered by the latch cases above).
do
    local s,scan=client()
    s.ns.db=s.ns.db or {}
    s.ns.db.gatherOpaque=false
    eq(s.result()[1].name,"铜矿","off case starts from a public receipt")
    s.moving()
    s.override=function() return {lines={{leftText={secret=true}}}} end
    s.tick(nil,false)
    eq(s.ns.gatherMinimapAccessRestricted,true,"passthrough off: secret name pauses minimap reading")
end
print("professions cursor scan: "..checks.." simulated checks passed (not in-game verification)")
