-- Lua 5.1 native-widget contract simulations, NOT live game acceptance.
local source="_forever_/Interface/AddOns/MyForeverProfessions/"
local checks=0
local function eq(a,b,why) checks=checks+1; assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a)) end
local function yes(v,why) eq(not not v,true,why) end
local function near(a,b,why) yes(math.abs(a-b)<.011,why) end

local function client(options)
    options=options or {}
    local e=setmetatable({}, {__index=_G}); e._G=e
    local s={now=0,frame=0,frames={},timers={},placements={},events={},mouse={},cx=500,cy=600,combat=false,dead=false,
        look=false,speed=0,shape=options.shape or "ROUND",icon=1,mask="Textures\\MinimapMask",reads=0,
        showCount=0,hideCount=0,mutations={},nativeConfig=0,rendered=nil,tooltipFrames={},blockingRequests=0}
    local methods={}
    local function frame()
        local f=setmetatable({scripts={},events={},children={},regions={},shown=true,alpha=1,clicks=true,wheel=true,motion=true,
            scale=1,width=options.width or 48,height=options.height or 48,zoom=0,
            anchors={{"BOTTOMLEFT",e.WorldFrame,"BOTTOMLEFT",100,200}}},{__index=methods})
        s.frames[#s.frames+1]=f
        return f
    end
    function methods:GetNumPoints() return #self.anchors end
    function methods:GetPoint(i) return unpack(self.anchors[i],1,5) end
    function methods:ClearAllPoints() self.anchors={} end
    function methods:SetPoint(...) self.anchors[#self.anchors+1]={...} end
    function methods:AdjustPointsOffset(x,y)
        if s.failMoveBefore or (s.failRestore and x<0) then error("move-before") end
        for _,p in ipairs(self.anchors) do p[4],p[5]=p[4]+x,p[5]+y end
        if self==e.Minimap then
            yes(s.standShown,"movement requires visible stand-in")
            yes(s.frame>s.showFrame,"stand-in has earlier frame than mutation")
            local px,py=s.cx/self.scale-self:GetLeft(),s.cy/self.scale-self:GetBottom()
            s.placements[#s.placements+1]={px,py,frame=s.frame}
            s.lastPlace=s.frame
        end
        if s.failMoveAfter then error("move-after") end
    end
    function methods:GetLeft() return self.anchors[1] and self.anchors[1][4] end
    function methods:GetBottom() return self.anchors[1] and self.anchors[1][5] end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:GetEffectiveScale() return self.scale end
    function methods:GetZoom() return self.zoom end
    function methods:GetParent() return self.parent end
    function methods:GetAlpha() return self.alpha end
    function methods:SetAlpha(v)
        if s.failAlphaRestore and v~=0 then error("alpha-restore") end
        self.alpha=v
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
    function methods:SetIconScale(v) s.icon=v; s.mutations[#s.mutations+1]={kind="icon",value=v,frame=s.frame} end
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
    e.WorldFrame={}
    e.UIParent=frame(); e.Minimap=frame(); e.MinimapCluster=frame(); e.Minimap.parent=e.MinimapCluster
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
    e.GetTime=function() return s.now end
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
    e.GetCursorPosition=function() return s.cx,s.cy end
    e.GetMinimapShape=function() return s.shape end
    e.GetMouseFoci=function() return s.foci or {e.WorldFrame} end
    e.hooksecurefunc=function(target,key,hook)
        local old=assert(target[key]); target[key]=function(...)
            local result={old(...)}; hook(...); return unpack(result)
        end
    end
    e.C_Minimap={GetUiMapID=function() return s.mapID or 1426 end,SetTracking=function() error("must not write tracking") end}
    e.C_AddOns={IsAddOnLoaded=function(name)
        return (name=="NodeSight" and options.conflict) or name==options.conflictName or false
    end}
    e.C_Timer={After=function(delay,fn) s.timers[#s.timers+1]={at=s.now+delay,fn=fn} end}
    s.node=function(x,y)
        if (x-e.Minimap.width/2)^2+(y-e.Minimap.height/2)^2<6^2 then return "铜矿" end
    end
    e.C_TooltipInfo={GetMinimapMouseover=function()
        s.reads=s.reads+1; s.tooltipFrames[#s.tooltipFrames+1]=s.frame
        yes(s.frame>s.lastPlace,"tooltip read occurs after a native render frame")
        if s.readError then error("native-read") end
        if s.override then return s.override(s) end
        return s.rendered
    end}
    local ns={GatherStandIn={
        Show=function(snapshot)
            s.showCount=s.showCount+1; s.snapshot=snapshot; s.showFrame=s.frame
            if options.noStand then return false,"map-art-unavailable" end
            s.standShown=true; return true
        end,
        Hide=function()
            eq(e.Minimap.clicks,true,"input returned before stand-in hidden")
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
        local x,y=s.cx/s.map.scale-(s.map:GetLeft() or 0),s.cy/s.map.scale-(s.map:GetBottom() or 0)
        local name=s.node(x,y)
        s.rendered=name and {lines={{leftText=name}}} or nil
        for _,f in ipairs(s.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt or 1/60) end end
        for _,t in ipairs(s.timers) do if not t.done and s.now>=t.at then t.done=true; t.fn() end end
        if poll~=false then return s.scan.ScanNames() end
    end
    function s.event(name)
        for _,f in ipairs(s.frames) do if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name) end end
    end
    function s.result(limit)
        s.scan.ScanNames()
        for _=1,limit or 2000 do local r=s.tick(); if r then return r end end
        error("no result: "..s.scan.ScanDiagnostics().reason)
    end
    function s.moving()
        s.scan.ScanNames()
        for _=1,20 do s.tick(nil,false); if #s.placements>0 then return end end
        error("did not begin moving: "..s.scan.ScanDiagnostics().reason)
    end
    return s,s.scan
end
local function restored(s,why,x,y,keepPicture)
    near(s.map:GetLeft(),x or 100,why.." left"); near(s.map:GetBottom(),y or 200,why.." bottom")
    eq(s.map.alpha,1,why.." native terrain alpha never changed")
    eq(s.map.clicks,true,why.." map clicks"); eq(s.map.wheel,true,why.." map wheel")
    eq(s.child.clicks,true,why.." child clicks"); eq(s.child.motion,true,why.." child hover")
    near(s.child.alpha,.75,why.." child alpha"); near(s.region.alpha,.4,why.." region alpha")
    eq(s.icon,1,why.." blip scale"); eq(s.standShown,keepPicture==true,why.." stand picture state")
end

do
    local s,scan=client()
    yes(scan.IsSupported(),"supported native contract")
    eq(scan.ScanNames(),nil,"initial poll does not invent observation")
    eq(#s.placements,0,"Show precedes native mutation")
    s.tick(nil,false); eq(#s.placements,0,"one complete stand-in render before native move")
    s.tick(nil,false); eq(#s.placements,1,"next update places sample")
    eq(s.reads,0,"placement never synchronously reads tooltip")
    s.tick(nil,false); eq(s.reads,1,"first sample is read next frame")
    eq(scan.ScanNames(),nil,"candidate waits for control and recheck")
    s.tick(nil,false); eq(scan.ScanNames(),nil,"outside-map control is not a resource observation")
    local r=s.tick(); eq(r[1].name,"铜矿","fresh confirmed resource")
    eq(r[1].kind,"mining","catalog kind")
    eq(r[1].dx,nil,"no resource coordinates"); eq(r[1].bearing,nil,"no resource direction")
    restored(s,"successful positive",nil,nil,true)
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
        if (x-s.map.width/2)^2+(y-s.map.height/2)^2<6^2 then return text end
    end
    eq(s.result()[1].name,"铜矿","inline art and color codes leave exact known resource name")
    eq(scan.ScanDiagnostics().rawKnownNames[1],"铜矿","diagnostics retain only clean known resource names")
    restored(s,"inline resource name",nil,nil,true)
end
for _,case in ipairs({{value={lines={}},field="Empty"},{value={lines={{leftText="unrelated private tooltip text"}}},field="Unknown"},
    {value={secret=true},field="Invalid"},{value={lines={{leftText=7}}},field="Invalid"}}) do
    local s,scan=client(); s.override=function() return case.value end
    scan.ScanNames()
    for _=1,3 do s.tick(nil,false) end
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
    restored(s,"all empty",nil,nil,true)
end
do
    local s,scan=client(); s.override=function() return {lines={{leftText="铜矿"}}} end
    for _=1,180 do eq(s.tick(),nil,"global stale resource text rejected") end
    eq(scan.ScanDiagnostics().acceptedNames[1],nil,"stale text never accepted")
    eq(scan.ScanDiagnostics().rejectedKnownNames[1],"铜矿","stale known name exposed without raw tooltip")
end
for _,options in ipairs({{noStand=true},{noAsset=true},{noBaseline=true},{shape="CORNER-TOPLEFT"},{conflict=true},{conflictName="Lueur"}}) do
    local s,scan=client(options)
    for _=1,12 do eq(s.tick(),nil,"failed preflight does not emit resource") end
    eq(#s.placements,0,"failed preflight leaves native position")
    eq(s.mask,"Textures\\MinimapMask","failed preflight leaves native mask")
    eq(s.map.clicks,true,"failed preflight leaves clicks")
end
do
    local s,scan=client({textureResult=-469,requireBlocking=true})
    local r=s.result()
    eq(r[1].name,"铜矿","actual client negative local texture file ID is accepted")
    eq(s.blockingRequests,1,"private asset probe requests blocking once")
    restored(s,"negative local file ID",nil,nil,true)
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
    for _=1,12 do eq(s.tick(),nil,"invalid or missing custom texture cannot emit observations") end
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
do
    local s,scan=client(); s.moving(); s.map:SetIconScale(1.7)
    eq(s.icon,1.7,"external icon scale retained")
    near(s.map:GetLeft(),100,"icon conflict returns native anchors")
    eq(s.map.clicks,true,"icon conflict returns clicks")
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
    scan.ScanNames()
    for _=1,5 do s.tick(.06,false) end
    restored(s,"cross setter "..target,target=="anchor" and 320 or 100,target=="anchor" and 420 or 200)
    if target=="mask" then eq(s.mask,"cross-setter-mask","cross-setter external mask kept") end
    eq(scan.ScanNames(),nil,"cross-setter cancellation cannot publish")
end
for _,failure in ipairs({"failMoveBefore","failMoveAfter","failClickAfter"}) do
    local s,scan=client(); s[failure]=true
    for _=1,10 do s.tick(nil,false); scan.ScanNames() end
    s[failure]=false; scan.Reset("fault-cleared"); s.tick(.2,false)
    restored(s,failure)
    eq(scan.ScanNames(),nil,failure.." cannot leak candidate")
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
    for _=1,40 do s.tick(nil,false) end
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
    local s,scan=client(); s.moving(); s.now=s.now+1
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
    scan.ScanNames(); for _=1,5 do s.tick(nil,false) end
    eq(scan.ScanNames(),nil,"node disappearing before confirmation is not published")
    eq(scan.ScanDiagnostics().acceptedNames[1],nil,"unconfirmed node is not retained")
    restored(s,"disappearing node")
end
do
    local s,scan=client(); scan.ScanNames()
    for _=1,5 do s.tick(nil,false) end
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
    local s,scan=client(); s.node=function() end
    scan.ScanNames()
    local gaps=0
    for _=1,180 do
        s.tick()
        if not scan.IsActive() and scan.ScanDiagnostics().standInRetained then
            gaps=gaps+1
            restored(s,"safe native gap",nil,nil,true)
        end
    end
    yes(gaps>10,"several completed native leases keep a continuous picture")
    eq(s.showCount,1,"safe subsequent leases reuse already rendered stand-in")
    eq(s.hideCount,0,"safe slices never expose alternating native-map colors")
    scan.Reset("disabled")
    restored(s,"disabled between leases")
    eq(scan.ScanDiagnostics().standInRetained,false,"disabled clears retained-only state")
end
for _,kind in ipairs({"RightButton","LeftButton","Button8","mouselook","combat","dead","window","map-hover",
    "geometry","shape","zoom","mapid","anchor","renderer-loss"}) do
    local s,scan=client(); s.result()
    yes(scan.ScanDiagnostics().standInRetained,"completed positive picture is retained")
    eq(scan.IsActive(),false,"retained picture owns no native lease")
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
    eq(scan.ScanDiagnostics().standInRetained,false,kind.." ends retained-only picture")
    eq(#s.placements,moves,kind.." gap guard never touches already restored map position")
    restored(s,kind.." between leases",x,y)
end
for _,event in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_REGEN_DISABLED","PLAYER_DEAD","PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","MINIMAP_UPDATE_ZOOM","ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED"}) do
    local s,scan=client(); s.result(); local moves=#s.placements
    s.event(event)
    restored(s,event.." retained-only cleanup")
    eq(scan.ScanDiagnostics().standInRetained,false,event.." cannot leave retained picture")
    eq(#s.placements,moves,event.." returns picture without another native move")
end
for _,reason in ipairs({"reset","source-change","original-source","disabled"}) do
    local s,scan=client(); s.result()
    eq(scan.IsActive(),false,"source reset exercises no-active retained state")
    scan.Reset(reason)
    restored(s,"retained reset "..reason)
    eq(scan.ScanDiagnostics().standInRetained,false,"source reset drops retained state")
    for _=1,10 do s.tick(nil,false) end
    eq(s.standShown,false,"source change cannot resurrect old picture without source polling")
end
do
    local s,scan=client(); s.result()
    for _=1,20 do s.tick(.02,false); scan.ScanDiagnostics() end
    eq(s.standShown,true,"short ordinary polling gap keeps picture")
    for _=1,16 do s.tick(.02,false); scan.ScanDiagnostics() end
    restored(s,"HUD heartbeat expiry")
    eq(scan.ScanDiagnostics().reason,"poll-heartbeat","diagnostic reads do not renew source heartbeat")
    eq(scan.ScanDiagnostics().standInRetained,false,"expired source polling releases picture")
end
do
    local s,scan=client(); s.result()
    local receipt=s.now
    for _=1,8 do
        s.now=s.now+.02
        eq(scan.ScanNames(),nil,"retaining picture does not replay previously consumed names")
    end
    eq(scan.ScanDiagnostics().publications,1,"picture reuse does not invent a new publication")
    yes(s.now-receipt<.6,"fresh receipt check stays within old TTL")
end
print("professions cursor scan: "..checks.." simulated checks passed (not in-game verification)")
