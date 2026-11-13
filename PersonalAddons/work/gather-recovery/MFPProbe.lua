-- Standalone, in-memory experiment. Do not add to an addon TOC.
-- Start accepts 2 or 3 points, each {x,y} in minimap radii (-1..1), north up.
local P = MFPProbe or {}
MFPProbe = P
local M = Minimap
local unpack = unpack
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function number(v) return public(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function need(v) if not v then error("probe-preflight") end return v end
local function points()
    local out = {}
    for i = 1, M:GetNumPoints() do out[i] = { M:GetPoint(i) } end
    need(#out > 0)
    for _, a in ipairs(out) do need(public(a[1]) and public(a[2]) and public(a[3]) and number(a[4]) and number(a[5])) end
    return out
end
local function owns(s, ox, oy)
    ox, oy = ox or s.ox, oy or s.oy
    local now = points()
    if #now ~= #s.anchors then return false end
    for i, a in ipairs(now) do
        local b = s.anchors[i]
        if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3]
            or math.abs(a[4] - b[4] - ox) > .01 or math.abs(a[5] - b[5] - oy) > .01 then return false end
    end
    return true
end
local function allowedFocus()
    local f = GetMouseFoci()
    need(type(f) == "table" and public(f))
    need(public(f[1]))
    return f[1] == nil or f[1] == WorldFrame or f[1] == M or (P.active and P.active.frames[f[1]])
end
local function inputSafe()
    return not InCombatLockdown() and not M:IsProtected() and not IsMouseButtonDown("LeftButton")
        and not IsMouseButtonDown("RightButton") and not IsMouseButtonDown("MiddleButton")
        and not IsMouseButtonDown("Button4") and not IsMouseButtonDown("Button5")
        and not (IsMouselooking and IsMouselooking()) and allowedFocus() and M:IsVisible()
end

function P:Cleanup(reason)
    local s = self.active
    if not s then return self.last and self.last.restored end
    self.active = nil
    local good = true
    local function restore(fn) local ok, result = pcall(fn); if not ok or result == false then good = false end end
    restore(function() self.frame:SetScript("OnUpdate", nil); self.frame:UnregisterAllEvents() end)
    if s.moved then
        restore(function()
            if not owns(s) and not (s.pending and owns(s, s.pending.x, s.pending.y)) then return false end
            M:ClearAllPoints()
            for _, a in ipairs(s.anchors) do M:SetPoint(unpack(a, 1, 5)) end
            s.ox, s.oy = 0, 0
            s.pending = nil
            return owns(s)
        end)
    end
    if s.alphaChanged then restore(function()
        local v = M:GetAlpha()
        if v == 0 then M:SetAlpha(s.alpha) elseif v ~= s.alpha then return false end
        return M:GetAlpha() == s.alpha
    end) end
    for _, item in ipairs(s.clicks) do
        if item.changed then restore(function()
            local v = item.f:IsMouseClickEnabled()
            if v == false then item.f:SetMouseClickEnabled(item.value) elseif v ~= item.value then return false end
            return item.f:IsMouseClickEnabled() == item.value
        end) end
    end
    if s.wheelChanged then restore(function()
        local v = M:IsMouseWheelEnabled()
        if v == false then M:EnableMouseWheel(s.wheel) elseif v ~= s.wheel then return false end
        return M:IsMouseWheelEnabled() == s.wheel
    end) end
    self.last = { reason = reason or "manual", restored = good, samples = s.results }
    print("MFPProbe done", self.last.reason, "restored", good)
    return good
end

local known = { "铜矿", "锡矿", "铁矿", "银矿", "金矿", "秘银", "瑟银", "宁神花", "银叶草",
    "Copper Vein", "Tin Vein", "Iron Deposit", "Silver Vein", "Gold Vein", "Mithril Deposit", "Thorium Vein", "Peacebloom", "Silverleaf" }
local function excerpt(text)
    local out = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        out[#out + 1] = char
        if #out == 80 then break end
    end
    return table.concat(out)
end
local function read()
    local d = C_TooltipInfo.GetMinimapMouseover()
    local count, hit, firstText = 0, false, nil
    if not public(d) or (type(d) == "table" and not public(d.lines)) then firstText = "secret" end
    if public(d) and type(d) == "table" and public(d.lines) and type(d.lines) == "table" then
        for _, line in ipairs(d.lines) do
            if firstText == nil and (not public(line) or (type(line) == "table" and not public(line.leftText))) then firstText = "secret" end
            if public(line) and type(line) == "table" and public(line.leftText) and type(line.leftText) == "string" then
                if firstText == nil then firstText = excerpt(line.leftText) end
                count = count + 1
                for _, name in ipairs(known) do if line.leftText:find(name, 1, true) then hit = true end end
            end
        end
    end
    return { lines = count, resource = hit, firstText = firstText or "" }
end

local function step(s)
    if GetTime() - s.started >= 2 then return P:Cleanup("timeout") end
    if not inputSafe() then return P:Cleanup("input-or-window") end
    if not owns(s) then return P:Cleanup("anchor-changed") end
    local cx, cy = GetCursorPosition()
    need(number(cx) and number(cy))
    if s.at then
        -- A moving cursor invalidates this tiny experiment; do not guess a location.
        if math.abs(cx - s.cx) > 1 or math.abs(cy - s.cy) > 1 then return P:Cleanup("cursor-moved") end
        local result = read()
        s.reads = s.reads + 1
        if s.reads == 1 then return end -- discard the first answer after each placement
        s.results[s.at] = result
        print("MFPProbe sample", s.at, "lines", result.lines, "resource", result.resource, "firstText", result.firstText)
        if s.at == #s.samples then return P:Cleanup("complete") end
    end
    s.at = (s.at or 0) + 1
    local q = s.samples[s.at]
    local x, y = cx / s.scale - (q[1] + 1) * s.width / 2 - s.left, cy / s.scale - (q[2] + 1) * s.height / 2 - s.bottom
    s.moved = true
    s.pending = { x = x, y = y }
    M:AdjustPointsOffset(x - s.ox, y - s.oy)
    s.ox, s.oy, s.cx, s.cy = x, y, cx, cy
    s.reads = 0
    s.pending = nil
    need(owns(s))
end

function P:Start(samples)
    if self.active then self:Cleanup("restart") end
    local ok = pcall(function()
        need(M and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and C_Timer and C_Timer.After)
        need(GetMouseFoci and IsMouseButtonDown and inputSafe())
        samples = samples or { { -.57, -.15 }, { .60, -.40 }, { -.57, -.15 } }
        need(type(samples) == "table" and (#samples == 2 or #samples == 3))
        local copy = {}
        for i, q in ipairs(samples) do
            need(type(q) == "table" and number(q[1]) and number(q[2]) and math.abs(q[1]) <= 1 and math.abs(q[2]) <= 1)
            copy[i] = { q[1], q[2] }
        end
        local s = { anchors = points(), alpha = M:GetAlpha(), wheel = M:IsMouseWheelEnabled(),
            left = M:GetLeft(), bottom = M:GetBottom(), width = M:GetWidth(), height = M:GetHeight(), scale = M:GetEffectiveScale(),
            clicks = {}, samples = copy, results = {}, ox = 0, oy = 0, started = GetTime() }
        need(number(s.alpha) and public(s.wheel) and type(s.wheel) == "boolean")
        for _, v in ipairs({ s.left, s.bottom, s.width, s.height, s.scale }) do need(number(v)) end
        need(s.width > 0 and s.height > 0 and s.scale > 0)
        local seen, n = {}, 0
        local function collect(f, depth)
            need(depth <= 8 and not seen[f]); seen[f] = true
            n = n + 1; need(n <= 128)
            local value = f:IsMouseClickEnabled()
            need(public(value) and type(value) == "boolean")
            if value then need(not f:IsProtected()); s.clicks[#s.clicks + 1] = { f = f, value = value } end
            for _, child in ipairs({ f:GetChildren() }) do collect(child, depth + 1) end
        end
        collect(M, 0)
        s.frames = seen
        self.frame = self.frame or CreateFrame("Frame")
        self.active = s -- every following mutation is covered by Cleanup
        self.frame:SetScript("OnEvent", function() P:Cleanup("world-or-combat") end)
        self.frame:RegisterEvent("PLAYER_LEAVING_WORLD")
        self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        C_Timer.After(math.max(0, 2 - (GetTime() - s.started)), function() if P.active == s then P:Cleanup("timeout") end end)
        for _, item in ipairs(s.clicks) do item.changed = true; item.f:SetMouseClickEnabled(false); need(item.f:IsMouseClickEnabled() == false) end
        if s.wheel then s.wheelChanged = true; M:EnableMouseWheel(false); need(M:IsMouseWheelEnabled() == false) end
        s.alphaChanged = true; M:SetAlpha(0); need(M:GetAlpha() == 0)
        self.frame:SetScript("OnUpdate", function()
            local success = pcall(step, s)
            if not success then P:Cleanup("error") end
        end)
        -- First OnUpdate places a point. Next reads and discards; second read is retained.
    end)
    if not ok then
        if self.active then self:Cleanup("error") else print("MFPProbe cancelled before changes") end
    end
    return ok and self.active ~= nil
end

print("MFPProbe loaded; Start/ Cleanup available")
