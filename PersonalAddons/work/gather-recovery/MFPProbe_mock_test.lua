local source = assert(io.open("PersonalAddons/work/gather-recovery/MFPProbe.lua")):read("*a")
local passed = 0
local function check(v, why) assert(v, why); passed = passed + 1 end
local function env()
    local e = setmetatable({}, { __index = _G })
    e.MFPProbe = nil
    e.now, e.mouse, e.combat, e.covered, e.timers, e.logs = 0, false, false, false, {}, {}
    e.cx, e.cy = 500, 600
    e.print = function(...) e.logs[#e.logs + 1] = {...} end
    e.GetTime = function() return e.now end
    e.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    e.InCombatLockdown = function() return e.combat end
    e.IsMouseButtonDown = function() return e.mouse end
    e.GetCursorPosition = function() return e.cx, e.cy end
    e.WorldFrame = {}
    local function frame()
        local f = { clicks = true, wheel = true, alpha = .8, children = {}, scripts = {}, events = {}, anchors = {{"BOTTOMLEFT", e.WorldFrame, "BOTTOMLEFT", 100, 200}} }
        function f:GetNumPoints() return #self.anchors end
        function f:GetPoint(i) return unpack(self.anchors[i], 1, 5) end
        function f:SetPoint(...) self.anchors[#self.anchors + 1] = {...} end
        function f:ClearAllPoints() self.anchors = {} end
        function f:AdjustPointsOffset(x, y) for _, a in ipairs(self.anchors) do a[4], a[5] = a[4] + x, a[5] + y end end
        function f:GetLeft() return self.anchors[1][4] end
        function f:GetBottom() return self.anchors[1][5] end
        function f:GetWidth() return 198 end
        function f:GetHeight() return 198 end
        function f:GetEffectiveScale() return .64 end
        function f:GetAlpha() return self.alpha end
        function f:SetAlpha(v) self.alpha = v; if e.alphaError and v == 0 then error("alpha") end end
        function f:IsMouseWheelEnabled() return self.wheel end
        function f:EnableMouseWheel(v) self.wheel = v end
        function f:IsMouseClickEnabled() return self.clicks end
        function f:SetMouseClickEnabled(v) self.clicks = v; if self.failClick and not v then error("click") end end
        function f:IsProtected() return self.protected == true end
        function f:IsVisible() return true end
        function f:GetChildren() return unpack(self.children) end
        function f:SetScript(k, v) self.scripts[k] = v end
        function f:RegisterEvent(k) self.events[k] = true end
        function f:UnregisterAllEvents() self.events = {} end
        return f
    end
    e.Minimap = frame()
    e.child = frame(); e.Minimap.children = {e.child}
    e.CreateFrame = function() return frame() end
    e.GetMouseFoci = function() return {e.focus or (e.covered and {} or (e.MFPProbe and e.MFPProbe.active and e.Minimap or e.WorldFrame))} end
    e.C_Timer = { After = function(_, f) e.timers[#e.timers + 1] = f end }
    e.C_TooltipInfo = {GetMinimapMouseover = function()
        if e.readError then error("read") end
        if e.secretTip then return {secret = true} end
        if e.forceText then return {lines={{leftText=e.forceText}}} end
        return e.rendered
    end}
    function e.tick()
        e.now = e.now + .016
        local m = e.Minimap
        local x = (e.cx / .64 - m:GetLeft()) / 99 - 1
        local y = (e.cy / .64 - m:GetBottom()) / 99 - 1
        local name
        if (math.abs(x + .32) < .001 and math.abs(y - .10) < .001)
            or (math.abs(x + .57) < .001 and math.abs(y + .15) < .001) then name = "铜矿"
        elseif math.abs(x - .30) < .001 and math.abs(y - .65) < .001 then name = "Tin Vein" end
        e.rendered = name and {lines = {{leftText = name}}} or nil
        local f = e.MFPProbe.frame and e.MFPProbe.frame.scripts.OnUpdate
        if f then f() end
    end
    function e.finish() for _=1,7 do e.tick() end end
    local f = assert(loadstring(source)); setfenv(f, e); f()
    return e, e.MFPProbe
end
local function restored(e, p, why)
    check(not p.active, why .. " inactive")
    check(e.Minimap:GetLeft() == 100 and e.Minimap:GetBottom() == 200, why .. " anchors")
    check(e.Minimap.alpha == .8 and e.Minimap.clicks and e.Minimap.wheel and e.child.clicks, why .. " input/alpha")
    check(p.last and p.last.restored == true, why .. " receipt")
end
do
    local e,p=env(); check(p:Start(),"start"); check(not e.Minimap.clicks and not e.child.clicks and not e.Minimap.wheel and e.Minimap.alpha == 0,"hidden")
    e.finish(); restored(e,p,"normal")
    check(p.last.samples[1].resource and not p.last.samples[2].resource and p.last.samples[3].resource,"A blank A")
    check(p.last.samples[1].lines == 1 and p.last.samples[2].lines == 0,"counts")
end
for _, mode in ipairs({"read", "mouse", "covered", "cursor", "timeout", "world", "combat", "manual", "alpha", "child"}) do
    local e,p=env()
    if mode == "alpha" then e.alphaError=true elseif mode == "child" then e.child.failClick=true end
    p:Start(); e.tick()
    if mode == "read" then e.readError=true; e.tick()
    elseif mode == "mouse" then e.mouse=true; e.tick()
    elseif mode == "covered" then e.covered=true; e.tick()
    elseif mode == "cursor" then e.cx=e.cx+5; e.tick()
    elseif mode == "timeout" then e.now=2; for _,f in ipairs(e.timers) do f() end
    elseif mode == "world" or mode == "combat" then p.frame.scripts.OnEvent(nil, mode == "world" and "PLAYER_LEAVING_WORLD" or "PLAYER_REGEN_DISABLED")
    elseif mode == "manual" then p:Cleanup("manual"); check(p:Cleanup("twice"),"idempotent") end
    restored(e,p,mode)
end
for _, mode in ipairs({"protected", "combat", "covered", "invalid"}) do
    local e,p=env()
    if mode == "protected" then e.child.protected=true elseif mode == "combat" then e.combat=true elseif mode == "covered" then e.covered=true end
    check(not p:Start(mode == "invalid" and {{2,0},{0,0}} or nil),mode .. " rejected")
    check(e.Minimap:GetLeft()==100 and e.Minimap.alpha==.8 and e.Minimap.clicks and e.child.clicks,mode .. " untouched")
end
do
    local e,p=env(); e.secretTip=true; p:Start(); e.finish()
    restored(e,p,"secret"); check(not p.last.samples[1].resource and p.last.samples[1].lines==0,"secret no hit")
end
do
    local e,p=env(); p:Start(); e.tick(); e.Minimap.anchors[1][4]=900; e.tick()
    check(not p.active and p.last.restored==false,"foreign anchor reported")
    check(e.Minimap:GetLeft()==900 and e.Minimap.alpha==.8 and e.Minimap.clicks and e.child.clicks,"foreign anchor kept, owned input restored")
end
do
    local e,p=env(); e.Minimap.anchors[2]={"TOPRIGHT",nil,"TOPRIGHT",298,398}; p:Start(); e.finish()
    restored(e,p,"multi-anchor")
    check(#e.Minimap.anchors==2 and e.Minimap.anchors[2][2]==nil and e.Minimap.anchors[2][5]==398,"nil relative frame restored")
end
do
    local e,p=env(); p:Start(); e.Minimap.alpha=.45; p:Cleanup("external-alpha")
    check(e.Minimap.alpha==.45 and not p.last.restored,"external alpha preserved")
    check(e.Minimap.clicks and e.Minimap.wheel and e.child.clicks,"other input restored")
end
do
    local e,p=env(); p:Start(); e.child.clicks=true
    e.child.SetMouseClickEnabled=function() error("should not rewrite external true") end
    p:Cleanup("external-child"); restored(e,p,"external child already restored")
end
do
    local e,p=env(); e.rendered={lines={{leftText="Copper Vein"}}}; p:Start()
    check(not p.active.at and #p.active.results==0,"Start never reads or places synchronously")
    p.frame.scripts.OnUpdate()
    check(p.active.at==1 and #p.active.results==0,"same frame callback only places, ignores old tooltip")
    e.finish(); restored(e,p,"same-frame")
end
do
    local e,p=env(); p:Start(); e.focus=e.child
    e.finish(); restored(e,p,"known descendant focus")
end
do
    local e,p=env(); p:Start(); e.focus={secret=true}; e.tick(); restored(e,p,"secret focus")
end
for _, mode in ipairs({"before-layout", "after-layout"}) do
    local e,p=env(); local original=e.Minimap.AdjustPointsOffset
    e.Minimap.AdjustPointsOffset=function(self,x,y)
        if mode=="after-layout" then original(self,x,y) end
        error("layout-hook")
    end
    p:Start(); e.tick(); restored(e,p,mode)
end
do
    local e,p=env(); local original=e.Minimap.AdjustPointsOffset
    e.Minimap.AdjustPointsOffset=function(self,x,y)
        original(self,x,y); self.anchors[1][4]=900; error("foreign-layout")
    end
    p:Start(); e.tick()
    check(not p.active and p.last.restored==false,"pending does not own foreign coordinates")
    check(e.Minimap:GetLeft()==900 and e.Minimap.alpha==.8 and e.Minimap.clicks and e.Minimap.wheel and e.child.clicks,"foreign layout retained, input restored")
end
do
    local e,p=env(); p:Start({{-.32,.10},{.30,.65},{-.60,-.50}}); e.finish()
    restored(e,p,"explicit points")
    check(p.last.samples[1].resource and p.last.samples[2].resource and not p.last.samples[3].resource,"explicit A B blank")
end
do
    local e,p=env(); p:Start(); e.tick()
    e.rendered={lines={{leftText="Stale quest marker"}}}; p.frame.scripts.OnUpdate()
    check(#p.active.results==0,"first read discarded")
    e.tick(); check(p.active.results[1].firstText=="铜矿","second read retained")
    e.rendered={lines={{leftText="Copper Vein"}}}; p.frame.scripts.OnUpdate()
    e.tick(); check(p.active.results[2].firstText=="" and not p.active.results[2].resource,"blank second read clears stale mine")
    e.rendered=nil; p.frame.scripts.OnUpdate(); e.tick()
    restored(e,p,"delayed A blank A")
    check(p.last.samples[3].firstText=="铜矿","last A returns mine")
    for _, log in ipairs(e.logs) do for _, v in ipairs(log) do check(v~="Stale quest marker","discarded text never printed") end end
end
do
    local e,p=env(); e.forceText=string.rep("铜",81); p:Start(); e.finish()
    check(p.last.samples[1].firstText==string.rep("铜",80),"truncate at 80 UTF8 characters")
end
do
    local e,p=env(); e.forceText={secret=true}; p:Start(); e.finish()
    check(p.last.samples[1].firstText=="secret" and p.last.samples[1].lines==0,"secret text labelled safely")
end
print("MFPProbe Lua 5.1 mock checks passed:", passed)
