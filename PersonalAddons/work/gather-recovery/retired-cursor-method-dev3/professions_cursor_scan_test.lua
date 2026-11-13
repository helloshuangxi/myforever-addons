-- Native-frame contract simulations only; real mouse gestures need game acceptance.
local source = "_forever_/Interface/AddOns/MyForeverProfessions/"
local checks = 0
local function eq(a, b, why)
    checks = checks + 1
    assert(a == b, why .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local function yes(v, why) eq(not not v, true, why) end
local function near(a, b, why) yes(math.abs(a - b) < .011, why) end

local function client(options)
    options = options or {}
    local e = setmetatable({}, {__index = _G})
    local state = {now = 0, frames = {}, timers = {}, placements = {}, reads = 0, mouse = {},
        combat = false, dead = false, look = false, cx = 500, cy = 600, speed = 0,
        width = options.width or 198, height = options.height or 198, shape = options.shape or "ROUND",
        icon = options.icon or 1, iconWrites = {}, nativeConfigApplies = 0, trackingWrites = {},
        tracking = {{spellID = 2580, active = true}, {filterID = 65536, active = options.quest ~= false}, {spellID = 2383, active = false}}}
    e.issecretvalue = function(v) return type(v) == "table" and rawget(v, "secret") == true end
    e.GetTime = function() return state.now end
    e.InCombatLockdown = function() return state.combat end
    e.UnitAffectingCombat = function() return state.combat end
    e.UnitIsDeadOrGhost = function() return state.dead end
    e.IsMouselooking = function() return state.look end
    e.GetUnitSpeed = function() return state.speed end
    e.IsMouseButtonDown = function(button) return state.mouse[button] or false end
    e.GetCursorPosition = function() return state.cx, state.cy end
    e.GetMinimapShape = function() return state.shape end
    e.GetFramerate = function() return options.fps or 60 end
    e.WorldFrame = {}
    local methods = {}
    local function frame()
        local f = setmetatable({scripts = {}, events = {}, children = {}, shown = true, clicks = true, wheel = true,
            alpha = .8, scale = .64, width = state.width, height = state.height, zoom = 0,
            anchors = {{"BOTTOMLEFT", e.WorldFrame, "BOTTOMLEFT", 100, 200}}}, {__index = methods})
        state.frames[#state.frames + 1] = f
        return f
    end
    function methods:GetNumPoints() return #self.anchors end
    function methods:GetPoint(i) return unpack(self.anchors[i], 1, 5) end
    function methods:ClearAllPoints() self.anchors = {} end
    function methods:SetPoint(...) self.anchors[#self.anchors + 1] = {...} end
    function methods:AdjustPointsOffset(x, y)
        if state.failMoveBefore then error("move-before") end
        for _, a in ipairs(self.anchors) do a[4], a[5] = a[4] + x, a[5] + y end
        if self == e.Minimap then
            local px, py = state.cx / self.scale - self:GetLeft(), state.cy / self.scale - self:GetBottom()
            state.placements[#state.placements + 1] = {px, py, time = state.now}
            state.pointReads = 0
        end
        if state.failMoveAfter then error("move-after") end
    end
    function methods:GetLeft() return self.anchors[1][4] end
    function methods:GetBottom() return self.anchors[1][5] end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:GetEffectiveScale() return self.scale end
    function methods:GetParent() return self.parent end
    function methods:SetIconScale(v)
        if state.failIconBefore or (v ~= .05 and state.failIconRestore) then error("icon-before") end
        state.icon = v
        state.iconWrites[#state.iconWrites + 1] = v
        if state.onIcon then state.onIcon(v) end
        if state.failIconAfter then error("icon-after") end
    end
    function methods:GetZoom() return self.zoom end
    function methods:GetAlpha() return self.alpha end
    function methods:SetAlpha(v)
        if v ~= 0 and state.failRestoreAlpha then error("restore-alpha") end
        self.alpha = v
        if v == 0 and state.failAlphaAfter then error("alpha-after") end
    end
    function methods:IsMouseClickEnabled() return self.clicks end
    function methods:SetMouseClickEnabled(v) self.clicks = v; if self.failClick and not v then error("click-after") end end
    function methods:IsMouseWheelEnabled() return self.wheel end
    function methods:EnableMouseWheel(v) self.wheel = v end
    function methods:IsProtected() return self.protected or false end
    function methods:IsVisible() return self.shown end
    function methods:GetChildren() return unpack(self.children) end
    function methods:SetScript(k, v) self.scripts[k] = v end
    function methods:HookScript(k, v)
        local previous = self.scripts[k]
        self.scripts[k] = function(...) if previous then previous(...) end; v(...) end
    end
    function methods:RegisterEvent(k) self.events[k] = true end
    function methods:UnregisterAllEvents() self.events = {} end
    function methods:EnableMouse(v) self.mouseEnabled = v end
    function methods:SetFrameStrata(v) self.strata = v end
    function methods:SetSize(w, h) self.width, self.height = w, h end
    function methods:SetAllPoints() end
    function methods:SetColorTexture() end
    function methods:SetText(v) self.text = v end
    function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
    function methods:Hide() self.shown = false end
    function methods:GetOwner() return self.owner end
    function methods:SetMinimapMouseover() self.owner = e.Minimap; self:Show() end
    function methods:CreateTexture() return frame() end
    function methods:CreateFontString() return frame() end
    e.CreateFrame = frame
    e.UIParent = frame(); e.UIParent.scale = 1
    e.Minimap = frame()
    e.MinimapCluster = frame()
    e.MinimapCluster.MinimapContainer = {Minimap = e.Minimap}
    e.Minimap.parent = e.MinimapCluster
    e.MinimapCluster.PlayerCoords = frame()
    state.coords = e.MinimapCluster.PlayerCoords
    e.Enum = {EditModeMinimapSetting = {IconScale = 3}}
    e.MinimapCluster.IsInitialized = function() return not options.uninitialized end
    e.MinimapCluster.HasSetting = function(_, id) return id == 3 and not options.noIconSetting end
    e.MinimapCluster.GetSettingValue = function() return options.percent or 100 end
    e.MinimapCluster.UpdateSystemSettingIconScale = function(self)
        state.nativeConfigApplies = state.nativeConfigApplies + 1
        e.Minimap:SetIconScale(self:GetSettingValue(3) / 100)
    end
    e.GameTooltip = frame(); e.GameTooltip.shown = false
    e.hooksecurefunc = function(target, name, hook)
        local original = assert(target[name])
        target[name] = function(...)
            local result = {original(...)}
            hook(...)
            return unpack(result)
        end
    end
    e.C_Minimap = {
        GetNumTrackingTypes = function() return #state.tracking end,
        GetTrackingFilter = function(i)
            local t = state.tracking[i]
            if not t or t.secretFilter then return t and t.secretFilter end
            if t.filterID ~= nil then return {filterID = t.filterID} end
            return nil -- native spell tracking can have no filter object
        end,
        GetTrackingInfo = function(i)
            local t = state.tracking[i]
            return t and {active = t.active, spellID = t.spellID, name = t.name}
        end,
        SetTracking = function(i, value)
            if state.failTrackingBefore then error("tracking-before") end
            if state.combat then error("tracking-combat") end
            local changed = state.tracking[i].active ~= value
            state.tracking[i].active = value
            state.trackingWrites[#state.trackingWrites + 1] = {index = i, filterID = state.tracking[i].filterID, value = value}
            if state.onTracking then state.onTracking(i, value) end
            if not options.nativeMirror or changed then
                if state.asyncTracking then
                    state.timers[#state.timers + 1] = {at = state.now + state.asyncTracking, fn = function() state.event("MINIMAP_UPDATE_TRACKING") end}
                else state.event("MINIMAP_UPDATE_TRACKING") end
            end
            if state.failTrackingAfter then error("tracking-after") end
        end,
    }
    state.child = frame(); e.Minimap.children = {state.child}
    state.map = e.Minimap
    e.GetMouseFoci = function() return state.foci or {e.WorldFrame} end
    e.C_Timer = {After = function(delay, fn) state.timers[#state.timers + 1] = {at = state.now + delay, fn = fn} end}
    state.node = function(x, y)
        if (x - state.width / 2)^2 + (y - state.height / 2)^2 <= 10^2 then return "铜矿" end
    end
    e.C_TooltipInfo = {GetMinimapMouseover = function()
        state.reads = state.reads + 1
        state.pointReads = (state.pointReads or 0) + 1
        if state.readError then error("tooltip") end
        if state.tip ~= nil then return state.tip end
        if state.stale and state.pointReads == 1 then return {lines = {{leftText = "Silver Vein"}}} end
        return state.rendered
    end}
    local ns = {db = options.db or {}}
    for _, name in ipairs({"GatherResources", "GatherCursorScan"}) do
        local chunk = assert(loadfile(source .. name .. ".lua")); setfenv(chunk, e); chunk("MyForeverProfessions", ns)
    end
    state.scan, state.ns, state.env = ns.GatherCursorScan, ns, e
    function state.tick(dt, poll)
        state.now = state.now + (dt or 1 / 60)
        local x, y = state.cx / state.map.scale - state.map:GetLeft(), state.cy / state.map.scale - state.map:GetBottom()
        local text = state.node(x, y)
        state.rendered = text and {lines = {{leftText = text}}} or nil
        for _, f in ipairs(state.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt or 1 / 60) end end
        for _, t in ipairs(state.timers) do if not t.done and state.now >= t.at then t.done = true; t.fn() end end
        if poll ~= false then return state.scan.Poll(true) end
    end
    function state.event(name)
        local function nativeMirror()
            if name ~= "MINIMAP_UPDATE_TRACKING" or not options.nativeMirror then return end
            state.trackingEvents = (state.trackingEvents or 0) + 1
            -- TrackingButton's menu-closed handler calls SetSelected for all
            -- current entries, which calls SetTracking even if unchanged.
            for i = 1, #state.tracking do e.C_Minimap.SetTracking(i, state.tracking[i].active) end
        end
        if options.nativeMirror == "first" then nativeMirror() end
        local first, last, step = 1, #state.frames, 1
        if options.reverseEvents then first, last, step = last, first, -1 end
        for i = first, last, step do
            local f = state.frames[i]
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name) end
        end
        if options.nativeMirror == "last" then nativeMirror() end
    end
    function state.complete(dt, count)
        local target = (ns.gatherCursorPasses or 0) + (count or 1)
        for _ = 1, 8000 do
            local r = state.tick(dt)
            if ns.gatherCursorPasses >= target then return r end
        end
        error("coverage did not finish: " .. tostring(ns.gatherCursorState) .. "/" .. tostring(ns.gatherCursorLastReason))
    end
    return state, ns.GatherCursorScan, ns
end
local function restored(s, why)
    near(s.map:GetLeft(), 100, why .. " left")
    near(s.map:GetBottom(), 200, why .. " bottom")
    eq(s.map.alpha, .8, why .. " alpha")
    eq(s.map.clicks, true, why .. " map clicks")
    eq(s.map.wheel, true, why .. " wheel")
    eq(s.child.clicks, true, why .. " child clicks")
end

do
    local s, scan, ns = client()
    yes(scan.IsSupported(), "capabilities")
    eq(#scan.Poll(true), 0, "initial scan has no fabricated result")
    yes(scan.IsActive(), "first enabled poll starts immediately")
    eq(s.reads, 0, "start never reads same-frame tooltip")
    s.tick(); eq(s.reads, 0, "first frame places only")
    s.tick(); eq(#scan.Poll(true), 0, "first native read discarded")
    local r = s.tick(); eq(r[1].name, "铜矿", "second read publishes immediately")
    eq(r[1].kind, "mining", "catalog kind")
    eq(r[1].dx, nil, "no invented coordinates")
    eq(r[1].bearing, nil, "no invented direction")
    r[1].name = "consumer mutation"
    eq(scan.Poll(true)[1].name, "铜矿", "caller cannot corrupt evidence")
    r = s.complete(); restored(s, "full pass")
    eq(ns.gatherCursorPasses, 1, "complete count")
    eq(ns.gatherCursorCount, 1, "resource count")
    eq(scan.IsActive(), false, "completion restores before return")
    local before = #s.placements
    s.now = s.now + 2.9; scan.Poll(true); eq(#s.placements, before, "three-second interval")
    s.now = s.now + .11; scan.Poll(true); yes(scan.IsActive(), "next pass starts after interval")
    scan.Reset(); restored(s, "reset")
end

do
    local s, scan = client(); s.stale = true; scan.Poll(true)
    local r = s.complete(); eq(#r, 1, "stale first-read mine never retained")
    eq(r[1].name, "铜矿", "second read determines resource")
    s.now = s.now + 3.01; s.node = function() return "任务：收集铜矿\n铜矿：0/10\nSilver Vein required" end
    scan.Poll(true); r = s.complete(); eq(#r, 0, "complete empty scan clears old ore; quest prose rejected")
end
do
    local s, scan = client(); s.node = function() return "|cffffff00铜矿|r\n  Peacebloom  \n任务 铜矿" end
    scan.Poll(true); local r = s.complete(); eq(#r, 2, "exact newline catalog names only")
    eq(r[1].name, "Peacebloom", "localized exact name")
end

for _, reason in ipairs({"mouse", "look", "focus", "combat", "dead", "read", "cursor", "hidden"}) do
    local s, scan, ns = client(); scan.Poll(true); s.tick(); s.tick(); s.tick()
    yes(#scan.Poll(true) > 0, reason .. " has prior evidence")
    if reason == "mouse" then s.mouse.RightButton = true
    elseif reason == "look" then s.look = true
    elseif reason == "focus" then s.foci = {{} }
    elseif reason == "combat" then s.combat = true
    elseif reason == "dead" then s.dead = true
    elseif reason == "read" then s.readError = true
    elseif reason == "hidden" then s.map.shown = false
    else
        for _ = 1, 3 do s.cx = s.cx + 3; s.tick(nil, false) end
    end
    s.tick(nil, false); restored(s, reason)
    eq(scan.IsActive(), reason == "combat", reason .. " cancels scan; combat retains pending preference recovery")
    yes(#scan.Poll(true) > 0, reason .. " keeps fresh confirmed evidence")
    s.now = s.now + 8.1; eq(#scan.Poll(true), 0, reason .. " TTL still expires")
    s.combat = false; scan.Reset()
end
do
    local s, scan, ns = client(); scan.Poll(true); s.tick()
    local reads = s.reads; s.event("GLOBAL_MOUSE_DOWN")
    restored(s, "global mouse event")
    eq(scan.IsActive(), false, "mouse event cleans synchronously without another frame")
    eq(s.reads, reads, "mouse abort never reads again")
    eq(ns.gatherCursorLastReason, "mouse-button", "immediate input reason")
end
do
    local s, scan = client(); scan.Poll(true); s.tick(); s.cx = s.cx + 3
    local before = s.reads; s.tick(); eq(s.reads, before, "drift repositions instead of reading old location")
    s.tick(); eq(#scan.Poll(true), 0, "reposition first read discarded")
    s.tick(); yes(#scan.Poll(true) > 0, "stationary second read after reposition works")
    scan.Reset(); restored(s, "small drift")
end
for _, event in ipairs({"PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "MINIMAP_UPDATE_ZOOM", "MINIMAP_UPDATE_TRACKING", "ZONE_CHANGED_NEW_AREA"}) do
    local s, scan = client(); scan.Poll(true); s.tick(); s.tick(); s.tick()
    if event == "MINIMAP_UPDATE_TRACKING" then s.tracking[1].active = false end
    s.event(event); restored(s, event); eq(s.ns.gatherCursorCount, 0, event .. " clears old evidence")
    scan.Reset()
end
do
    local s, scan = client(); scan.Poll(true); s.tick(); s.map.scale = .8; s.tick(nil, false)
    restored(s, "scale change"); eq(s.ns.gatherCursorCount, 0, "geometry resets evidence")
end

for _, level in ipairs({"data", "lines", "line", "text"}) do
    local s, scan = client()
    local secret = setmetatable({secret = true}, {__index = function() error("restricted access") end})
    s.tip = level == "data" and secret or level == "lines" and {lines = secret}
        or level == "line" and {lines = {secret}} or {lines = {{leftText = secret}}}
    scan.Poll(true); eq(#s.complete(), 0, "secret " .. level .. " is not exposed or matched")
    restored(s, "secret " .. level)
end
for _, field in ipairs({"combat", "dead", "look"}) do
    local s, scan = client(); s[field] = {secret = true}
    eq(#scan.Poll(true), 0, "secret " .. field .. " preflight pauses")
    eq(scan.IsActive(), false, "secret " .. field .. " never mutates")
    restored(s, "secret preflight")
end
do
    local s, scan = client(); s.map.protected = {secret = true}
    local ok = pcall(scan.Poll, true); yes(ok, "secret protection does not escape Poll")
    restored(s, "secret protection")
end
for _, setting in ipairs({"protected", "child", "alpha", "before", "after"}) do
    local s, scan = client()
    if setting == "protected" then s.child.protected = true
    elseif setting == "child" then s.child.failClick = true
    elseif setting == "alpha" then s.failAlphaAfter = true
    elseif setting == "before" then s.failMoveBefore = true
    else s.failMoveAfter = true end
    scan.Poll(true); s.tick(nil, false); restored(s, setting)
    eq(scan.IsActive(), false, setting .. " rollback completes")
end
do
    local s, scan, ns = client(); scan.Poll(true); s.tick(); s.failRestoreAlpha = true
    scan.Reset("test"); eq(ns.gatherCursorState, "restore-failed", "failed restoration blocks restart")
    eq(scan.IsActive(), true, "recovery retains ownership")
    local placements = #s.placements
    s.now = s.now + 1; scan.Poll(true); eq(#s.placements, placements, "no new scan from mutated baseline")
    s.failRestoreAlpha = false; s.now = s.now + 1; scan.Poll(true); restored(s, "recover original baseline")
    eq(scan.IsActive(), false, "successful restoration exits recovery")
end
do
    local s, scan, ns = client(); scan.Poll(true); s.tick(); s.map.anchors[1][4] = 900
    s.tick(nil, false); eq(s.map:GetLeft(), 900, "foreign anchor never overwritten")
    eq(ns.gatherCursorState, "restore-failed", "foreign ownership blocks automatic rebasing")
    eq(s.map.alpha, .8, "independent alpha still restored")
end
do
    local s, scan = client(); scan.Poll(true); s.tick(); scan.Poll(false)
    restored(s, "disabled"); eq(#scan.Poll(false), 0, "disabled clears results")
end

-- Inspect actual placement coordinates, not a duplicate of the generator.
do
    local s, scan = client(); s.node = function() end; scan.Poll(true); s.complete()
    local points = {}
    for _, p in ipairs(s.placements) do
        if p[1] >= -.01 and p[1] <= 198.01 and p[2] >= -.01 and p[2] <= 198.01 then points[#points + 1] = p end
    end
    yes(#points > 80 and #points <= 256, "198 round grid is dense and bounded")
    local worst = 0
    local function observe(x, y)
        local best = math.huge
        for _, p in ipairs(points) do best = math.min(best, math.sqrt((x - p[1])^2 + (y - p[2])^2)) end
        worst = math.max(worst, best)
    end
    for y = 0, 198, 3 do for x = 0, 198, 3 do
        if (x - 99)^2 + (y - 99)^2 <= 99^2 then observe(x, y) end
    end end
    for i = 1, 720 do local a = i * 2 * math.pi / 720; observe(99 + 99 * math.cos(a), 99 + 99 * math.sin(a)) end
    yes(worst <= 12.5, "dense circle and perimeter within 12.5 UI of a real sample; worst " .. worst)
end
for _, options in ipairs({{fps = 15}, {width = 420, height = 420, fps = 30}, {width = 420, height = 300, shape = "SQUARE", fps = 60}}) do
    local s, scan, ns = client(options); s.node = function() end; scan.Poll(true)
    local dt, sawPause = 1 / options.fps, false
    for _ = 1, 10000 do
        local wasActive = scan.IsActive()
        s.tick(dt)
        if wasActive and not scan.IsActive() then sawPause = true; restored(s, "slice boundary") end
        if ns.gatherCursorPasses == 1 then break end
    end
    eq(ns.gatherCursorPasses, 1, "low FPS / large map eventually covers perimeter")
    yes(sawPause, "bounded slices restore between continuation")
    yes(s.now < 120, "coverage makes progress instead of repeating center")
    eq(#scan.Poll(true), 0, "partial slices never fabricate resources")
    restored(s, "coverage complete")
end

-- Long scans and their idle gaps must not age out a stationary, known edge node.
-- Rechecking a known sample is evidence only when its fresh second read matches.
for _, fps in ipairs({15, 30}) do
    local s, scan, ns = client({fps = fps})
    s.node = function(x, y) if (x - 185)^2 + (y - 99)^2 < 12.5^2 then return "铜矿" end end
    scan.Poll(true)
    local firstSeen, gap, newest
    for _ = 1, fps * 40 do
        local r = s.tick(1 / fps)
        if #r > 0 then firstSeen = firstSeen or s.now; newest = r[1].seenAt
        elseif firstSeen then gap = true end
    end
    yes(firstSeen, "edge node found at " .. fps .. " FPS")
    eq(gap, nil, "stationary edge node has no artificial TTL gaps at " .. fps .. " FPS")
    yes(ns.gatherCursorPasses >= 1, "priority rechecks still allow full coverage")
    s.node = function() end
    local lastRealObservation, renewed = newest, false
    for _ = 1, fps * 10 do
        local r = s.tick(1 / fps)
        if #r > 0 and r[1].seenAt ~= lastRealObservation then renewed = true end
    end
    eq(renewed, false, "empty known point cannot renew timestamp")
    eq(#scan.Poll(true), 0, "vanished edge node expires without false renewal")
    scan.Reset(); restored(s, "priority review")
end

-- Native icon/quest settings are observable writes, not fabricated getters.
do
    local s, scan, ns = client({percent = 140, icon = 1.7})
    scan.Poll(true)
    eq(s.nativeConfigApplies, 1, "one native layout application establishes baseline")
    eq(s.iconWrites[1], 1.4, "native display percent determines new baseline")
    eq(s.icon, .05, "scan hides native blips with small icon scale")
    eq(s.coords.alpha, 0, "sibling coordinates hidden")
    eq(s.tracking[2].active, false, "exact quest-area filter disabled")
    yes(ns.db.gatherCursorQuestRestore, "quest preference journal exists before cleanup")
    yes(scan.IsOwnTrackingUpdate(), "own tracking synchronous event recognized")
    yes(scan.IsOwnTrackingUpdate(), "second listener sees same non-consuming answer")
    scan.Reset()
    eq(s.icon, 1.4, "restores observed layout baseline, not guessed old native value")
    eq(s.coords.alpha, .8, "coordinates restored")
    eq(s.tracking[2].active, true, "quest preference restored")
    eq(ns.db.gatherCursorQuestRestore, nil, "confirmed restore clears journal")
    for _, write in ipairs(s.trackingWrites) do eq(write.filterID, 65536, "only QuestPOIs is changed") end
    scan.Poll(true); scan.Reset()
    eq(s.nativeConfigApplies, 1, "later scans never overwrite current layout preferences")
    eq(s.map.scale, .64, "no native map SetScale modification")
end
for _, options in ipairs({{uninitialized = true}, {noIconSetting = true}, {percent = 0}, {percent = 250}}) do
    local s, scan = client(options); scan.Poll(true)
    eq(s.nativeConfigApplies, 0, "unready or invalid native icon config never applied")
    eq(#s.iconWrites, 0, "no guessed icon baseline")
    eq(#s.trackingWrites, 0, "failed preflight never mutates tracking")
    restored(s, "native config preflight")
end
do
    local s, scan = client({percent = 140})
    s.env.MinimapCluster.UpdateSystemSettingIconScale = function()
        s.nativeConfigApplies = s.nativeConfigApplies + 1
        s.map:SetIconScale(1.3999999761581)
    end
    scan.Poll(true); eq(s.icon, .05, "float precision in native setter does not reject baseline")
    scan.Reset(); eq(s.icon, 1.3999999761581, "restores exact observed public setter argument")
end
do
    local s, scan = client(); scan.Poll(true); s.tick()
    s.map:SetIconScale(1.7)
    eq(s.icon, 1.7, "external icon change wins")
    eq(scan.IsActive(), false, "external icon change cancels scan")
    restored(s, "external icon ownership")
    s.now = s.now + 1; scan.Poll(true); scan.Reset()
    eq(s.icon, 1.7, "next scan restores newly observed external baseline")
    eq(s.nativeConfigApplies, 1, "external icon custom value not reset by native config")
end
do
    local s, scan = client()
    s.onIcon = function(value)
        if value == .05 then s.onIcon = nil; s.map:SetIconScale(1.8) end
    end
    scan.Poll(true)
    eq(s.icon, 1.8, "nested external icon write survives late own setter hook")
    eq(scan.IsActive(), false, "nested external icon invalidates write transaction")
    eq(s.coords.alpha, .8, "cancelled start does not continue hiding sibling frames")
    restored(s, "nested external icon")
end
do
    local s, scan, ns = client(); scan.Poll(true); s.failIconRestore = true
    scan.Reset(); eq(ns.gatherCursorState, "restore-failed", "icon restore error retains recovery")
    eq(s.icon, .05, "failed native restore remains known owned value")
    s.now = s.now + 1; local writes = #s.iconWrites; scan.Poll(true)
    eq(#s.iconWrites, writes, "no new scan when icon recovery pending")
    s.failIconRestore = false; s.now = s.now + 1; scan.Poll(true)
    eq(s.icon, 1, "icon recovery retries original observed value")
    eq(scan.IsActive(), false, "icon recovery completes")
end
do
    local s, scan = client()
    s.onIcon = function(value)
        if value == .05 then s.onIcon = nil; s.map:SetIconScale(.05) end
    end
    scan.Poll(true)
    eq(s.icon, .05, "same-value nested external icon write remains authoritative")
    eq(scan.IsActive(), false, "second identical setter observation revokes icon ownership")
    scan.Reset()
    eq(s.icon, .05, "cleanup does not restore over same-value nested external icon choice")
    restored(s, "same-value nested icon")
end
do
    local s, scan = client(); scan.Poll(true); s.coords:SetAlpha(.3); scan.Reset()
    eq(s.coords.alpha, .3, "external coordinate alpha choice preserved")
    restored(s, "coordinate external alpha")
end
do
    local s, scan = client(); scan.Poll(true)
    local tip, other = s.env.GameTooltip, {}
    tip.owner = other; tip:Show(); eq(tip.shown, true, "unrelated tooltip remains visible")
    tip:SetMinimapMouseover(); eq(tip.shown, false, "native minimap tooltip hidden after native setter")
    tip.owner = s.child; tip:Show(); eq(tip.shown, false, "minimap child tooltip hidden on show")
    tip.owner = other; tip:Show(); scan.Reset()
    eq(tip.shown, true, "cleanup never hides unrelated tooltip")
    tip:SetMinimapMouseover(); eq(tip.shown, false, "late native scan tooltip hidden briefly after cleanup")
    s.now = s.now + .11; tip:SetMinimapMouseover()
    eq(tip.shown, true, "normal minimap tooltip resumes after scan echo interval")
end
do
    local s, scan, ns = client({quest = false}); scan.Poll(true); scan.Reset()
    eq(#s.trackingWrites, 0, "already-disabled quest areas are never written")
    eq(s.tracking[2].active, false, "original false preference preserved")
    eq(ns.db.gatherCursorQuestRestore, nil, "no unnecessary preference journal")
end
do
    local s, scan = client(); s.asyncTracking = .1
    local hud = s.env.CreateFrame()
    hud:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    hud:SetScript("OnEvent", function()
        if not scan.IsOwnTrackingUpdate() then scan.Reset("hud-tracking") end
    end)
    scan.Poll(true)
    for _ = 1, 8 do s.tick(nil, false) end
    yes(scan.IsActive(), "asynchronous own hide events do not trigger a reset loop in either listener")
    scan.Reset(); s.tick(.12, false)
    eq(scan.IsActive(), false, "delayed restore event does not start a scan")
    yes(scan.IsOwnTrackingUpdate(), "restore echo recognized after active session cleared")
    yes(scan.IsOwnTrackingUpdate(), "restore echo non-consuming for HUD too")
    s.now = s.now + 1.01; eq(scan.IsOwnTrackingUpdate(), false, "own lease expires")
    eq(#s.trackingWrites, 2, "asynchronous own events require only hide and restore")
end
do
    local s, scan, ns = client(); scan.Poll(true); s.env.C_Minimap.SetTracking(2, false)
    eq(s.tracking[2].active, false, "identical QuestPOI write has no observable state change")
    yes(ns.db.gatherCursorQuestRestore, "identical QuestPOI mirror preserves temporary restoration record")
    yes(scan.IsOwnTrackingUpdate(), "identical QuestPOI mirror preserves own lease")
    yes(scan.IsActive(), "identical QuestPOI mirror does not cancel scan")
    scan.Reset(); eq(s.tracking[2].active, true, "unchanged native mirror still restores original preference")
    restored(s, "identical QuestPOI mirror")
end
do
    local value = true
    local s, scan, ns = client(); scan.Poll(true); s.env.C_Minimap.SetTracking(2, value)
    eq(s.tracking[2].active, value, "changed external QuestPOI choice preserved")
    eq(ns.db.gatherCursorQuestRestore, nil, "external QuestPOI setter revokes restoration ownership")
    eq(scan.IsOwnTrackingUpdate(), false, "external QuestPOI write invalidates lease")
    eq(scan.IsActive(), false, "external QuestPOI setter cancels scan")
    restored(s, "external QuestPOI")
end
do
    local s, scan = client(); scan.Poll(true); s.tracking[1].active = false
    eq(scan.IsOwnTrackingUpdate(), false, "real mineral tracking change not swallowed by one-second lease")
    s.event("MINIMAP_UPDATE_TRACKING")
    eq(scan.IsActive(), false, "real mineral event resets scan")
    eq(s.tracking[1].active, false, "mineral choice never overwritten")
    eq(s.tracking[2].active, true, "own quest preference restored during mineral reset")
end
do
    local s, scan, ns = client(); scan.Poll(true)
    s.tracking[2].active = true
    eq(scan.IsOwnTrackingUpdate(), false, "Quest state changed outside setter does not match own target")
    s.event("MINIMAP_UPDATE_TRACKING")
    eq(scan.IsActive(), false, "real Quest change event cancels even without setter hook")
    eq(s.tracking[2].active, true, "direct Quest change retained")
    eq(ns.db.gatherCursorQuestRestore, nil, "direct Quest change clears fulfilled restore journal")
    restored(s, "direct Quest event")
end
do
    local s, scan, ns = client(); scan.Poll(true); scan.Reset()
    s.tracking[2].active = false
    eq(scan.IsOwnTrackingUpdate(), false, "opposite state after restore is not a delayed own echo")
    s.event("MINIMAP_UPDATE_TRACKING")
    eq(s.tracking[2].active, false, "post-restore external false choice retained")
    eq(ns.db.gatherCursorQuestRestore, nil, "post-restore external choice never acquires old journal")
end
do
    local s, scan = client(); scan.Poll(true)
    s.tracking[2], s.tracking[3] = s.tracking[3], s.tracking[2]
    scan.Reset()
    eq(s.tracking[3].active, true, "quest restore re-finds filter after index reorder")
    eq(s.tracking[2].active, false, "reordered herb preference untouched")
    eq(s.trackingWrites[#s.trackingWrites].index, 3, "restore targets current QuestPOI index")
end
for _, value in ipairs({false, true}) do
    local s, scan = client()
    s.onTracking = function(i, ownValue)
        if i == 2 and not ownValue then s.onTracking = nil; s.env.C_Minimap.SetTracking(2, value) end
    end
    scan.Poll(true)
    eq(s.tracking[2].active, value, "nested QuestPOI setter preserves actual state")
    if value then
        eq(scan.IsActive(), false, "changed nested QuestPOI invalidates ownership")
        eq(s.icon, 1, "changed tracking cancellation prevents subsequent icon hide")
    else
        yes(scan.IsActive(), "unchanged nested QuestPOI mirror permits scan")
        eq(s.icon, .05, "unchanged nested mirror permits subsequent icon hide")
        scan.Reset(); eq(s.tracking[2].active, true, "unchanged nested mirror permits original preference restore")
    end
    restored(s, "nested external QuestPOI")
end
do
    local journal = {filterID = 65536, before = true, applied = false}
    local s, scan, ns = client({db = {gatherCursorQuestRestore = journal}, quest = false})
    s.combat = true; scan.Poll(false)
    eq(ns.db.gatherCursorQuestRestore, journal, "disabled in combat keeps pending persisted restore")
    eq(#s.trackingWrites, 0, "combat recovery never writes tracking")
    s.combat = false; s.env.C_TooltipInfo = nil; scan.Poll(false)
    eq(s.tracking[2].active, true, "disabled unsupported feature still restores preference after combat")
    eq(ns.db.gatherCursorQuestRestore, nil, "recovered persisted record cleared after confirmation")
    eq(s.nativeConfigApplies, 0, "preference recovery does not touch native layout")
end
do
    local s, scan, ns = client(); scan.Poll(true); s.failTrackingBefore = true; scan.Reset()
    eq(s.tracking[2].active, false, "failed quest restore keeps known disabled state")
    yes(ns.db.gatherCursorQuestRestore, "failed quest restore retains journal")
    eq(ns.gatherCursorState, "restore-failed", "quest restore failure blocks new scan")
    s.failTrackingBefore = false; s.now = s.now + .51; scan.Poll(false)
    eq(s.tracking[2].active, true, "disabled poll retries quest restoration")
    eq(ns.db.gatherCursorQuestRestore, nil, "quest retry clears journal")
end
do
    local s, scan, ns = client(); s.failTrackingAfter = true
    scan.Poll(true); yes(scan.IsActive(), "native tracking throw after applying uses confirmed readback")
    scan.Reset(); eq(s.tracking[2].active, true, "throw-after native restore readback accepted")
    eq(ns.db.gatherCursorQuestRestore, nil, "throw-after recovery does not strand preference")
end
for _, key in ipairs({"active", "spellID", "filter"}) do
    local s, scan = client()
    local secret = setmetatable({secret = true}, {__index = function() error("secret field access") end})
    if key == "filter" then s.tracking[1].secretFilter = secret else s.tracking[1][key] = secret end
    local ok = pcall(scan.Poll, true)
    yes(ok, "secret tracking " .. key .. " cannot escape Poll")
    eq(#s.trackingWrites, 0, "secret tracking prevents preference mutation")
    restored(s, "secret tracking " .. key)
end

for _, nativeOrder in ipairs({"first", "last"}) do
    for _, reverse in ipairs({false, true}) do
        local s, scan, ns = client({nativeMirror = nativeOrder, reverseEvents = reverse})
        s.asyncTracking = .05
        local hud = s.env.CreateFrame()
        hud:RegisterEvent("MINIMAP_UPDATE_TRACKING")
        hud:SetScript("OnEvent", function()
            if not scan.IsOwnTrackingUpdate() then scan.Reset("hud-tracking") end
        end)
        local observed, firstEvent
        scan.Poll(true)
        for i = 1, 60 * 25 do
            s.tick(1 / 60, false)
            if i % 6 == 0 then
                local r = scan.Poll(true)
                observed = observed or #r > 0
            end
            if s.trackingEvents and not firstEvent then
                firstEvent = true
                yes(scan.IsActive(), "native mirror event leaves scan active: " .. nativeOrder .. "/" .. tostring(reverse))
            end
            if ns.gatherCursorPasses >= 2 then break end
        end
        eq(ns.gatherCursorPasses, 2, "native mirror allows repeated complete passes in either listener order")
        yes(observed, "native mirror allows real tooltip resource publication")
        yes((s.trackingEvents or 0) <= 4, "native mirror does not create a cancel/restore event storm")
        restored(s, "native mirror completed passes")
        s.tick(.1, false)
        eq(ns.gatherCursorPasses, 2, "delayed restore mirror does not reset completed pass")
        yes(scan.IsOwnTrackingUpdate(), "restore mirror leaves non-consuming lease valid")
        eq(ns.db.gatherCursorQuestRestore, nil, "completed native restore clears journal")
        s.now = s.now + 3.01; scan.Poll(true)
        s.env.C_Minimap.SetTracking(1, false)
        eq(scan.IsActive(), false, "real mineral change still cancels amid native mirror model")
        eq(s.tracking[1].active, false, "real mineral selection preserved")
        eq(s.tracking[2].active, true, "own QuestPOI restored after real mineral change")
        s.tick(.2, false)
        scan.Poll(true); yes(scan.IsActive(), "new scan can start after real tracking reset")
        s.env.C_Minimap.SetTracking(2, true)
        eq(scan.IsActive(), false, "real QuestPOI change cancels amid native mirror model")
        eq(s.tracking[2].active, true, "real QuestPOI change remains preserved")
        eq(ns.db.gatherCursorQuestRestore, nil, "real QuestPOI change revokes restoration ownership")
        restored(s, "native mirror with external changes")
    end
end

print("Gather cursor scan: " .. checks .. " simulated checks passed")
