-- MyForeverStyle: the shared look of the 我的无限 addon suite.
--
-- One identical copy is embedded in every MyForever* addon and listed first in
-- its TOC. The newest loaded copy wins, so the seven addons stay independent
-- but draw with the same surfaces, type scale, buttons and accent.
--
-- Source of truth: PersonalAddons/shared/MyForeverStyle.lua. Run
-- `python3 tools/sync_style.py` after editing; tools/check_addons.py fails when
-- an embedded copy differs.
--
-- Palette "Midnight" (direction B, chosen 2026-11-14): deep blue-black
-- translucent surfaces, electric-blue accent, borderless rounded panels,
-- tonal fills instead of outlines. Game-meaning colors (item quality, class,
-- recipe difficulty, target red, focus gold, chat channels) are NOT part of
-- this file and must stay with the code that owns that meaning.
--
-- Every widget call is guarded: a missing method is skipped instead of raising,
-- because a styling helper must never break an addon in a client variant.
local VERSION = 5
local existing = rawget(_G, "MyForeverStyle")
if type(existing) == "table" and (tonumber(existing.version) or 0) >= VERSION then return end

local S = { version = VERSION }
_G.MyForeverStyle = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
S.WHITE = WHITE

-- Surfaces go from the window itself (outer) up to raised/hover/selected.
S.colors = {
    outer = { 0.051, 0.067, 0.118 },      -- window body
    side = { 0.075, 0.094, 0.160 },       -- secondary column, wells
    surface = { 0.110, 0.133, 0.224 },    -- controls, cards, inputs (tonal fill)
    hover = { 0.141, 0.169, 0.282 },
    selected = { 0.161, 0.204, 0.373 },   -- chosen row
    line = { 0.200, 0.239, 0.380 },       -- rare hairlines and rules
    accent = { 0.486, 0.576, 1.000 },     -- #7C93FF primary action, active state
    accentSoft = { 0.141, 0.169, 0.337 }, -- selected pill fill
    onAccent = { 0.043, 0.063, 0.188 },   -- text on an accent fill
    text = { 0.933, 0.945, 1.000 },       -- primary content
    secondary = { 0.639, 0.671, 0.796 },  -- labels next to content
    muted = { 0.451, 0.486, 0.620 },      -- hints, captions, units
    disabled = { 0.330, 0.360, 0.470 },
    success = { 0.310, 0.827, 0.604 },
    warning = { 0.949, 0.702, 0.361 },
    danger = { 1.000, 0.392, 0.392 },
    info = { 0.486, 0.576, 1.000 },
    -- Ornament only (window corners, title rule, selection cursor). Never
    -- carries game meaning; focus gold in Targets is a separate constant.
    gold = { 0.890, 0.812, 0.596 },
    titleText = { 0.957, 0.918, 0.816 },
}

-- Background opacity by role. Only the backdrop is translucent; text and
-- icons stay opaque (never SetAlpha on the parent frame for this).
S.alpha = { window = 0.92, hud = 0.80, toast = 0.88, popup = 0.97 }

-- Type scale in UI units. "value" is for the one number a panel is about.
S.type = {
    title = { 15, "text" }, heading = { 13, "secondary" }, body = { 13, "text" },
    secondary = { 12, "secondary" }, caption = { 11, "muted" }, value = { 20, "text" },
    button = { 12, "text" },
}

S.metrics = { pad = 14, gap = 8, row = 26, button = 26, title = 36, icon = 42, radius = 12, control = 7 }

local function has(object, method)
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    local ok, value = pcall(function() return object[method] end)
    return ok and type(value) == "function" and value or nil
end
local function passOk(ok, ...)
    if ok then return ... end
    return nil
end
local function call(object, method, ...)
    local fn = has(object, method)
    if not fn then return nil end
    return passOk(pcall(fn, object, ...))
end
S.Call = call

function S.Color(name, alpha)
    local c = S.colors[name] or S.colors.text
    return c[1], c[2], c[3], alpha or 1
end
function S.Hex(name)
    local c = S.colors[name] or S.colors.text
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
-- Inline color for chat lines and mixed-emphasis labels.
function S.Paint(name, text) return "|cff" .. S.Hex(name) .. tostring(text) .. "|r" end
-- One chat prefix for the whole suite: brand, then the addon.
function S.Prefix(addonLabel)
    return S.Paint("accent", "我的无限") .. (addonLabel and (" " .. S.Paint("muted", "·") .. " " .. addonLabel) or "")
end

-- Rounded flat surface built from seven textures (a centre column, two side
-- strips and four quarter circles cut from Blizzard's round portrait mask), so
-- no texture overlaps another and a translucent fill stays even. Replaces any
-- backdrop on the frame. Re-calling only recolours.
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
S.CIRCLE = CIRCLE
local CORNERS = {
    { "TOPLEFT", 0, 0.5, 0, 0.5 }, { "TOPRIGHT", 0.5, 1, 0, 0.5 },
    { "BOTTOMLEFT", 0, 0.5, 0.5, 1 }, { "BOTTOMRIGHT", 0.5, 1, 0.5, 1 },
}
function S.Round(frame, fill, alpha, radius, layer)
    if not frame then return frame end
    local r, g, b = S.Color(fill or "surface")
    alpha = alpha or 1
    -- Some mocks answer every missing key with a function; only a table counts.
    local parts = frame.roundParts
    if type(parts) ~= "table" then
        if has(frame, "SetBackdrop") then call(frame, "SetBackdrop", nil) end
        radius = math.max(2, radius or S.metrics.control)
        parts = { radius = radius }
        local function tex() return call(frame, "CreateTexture", nil, layer or "BACKGROUND", nil, -7) end
        parts.center, parts.left, parts.right = tex(), tex(), tex()
        if not parts.center then return frame end
        call(parts.center, "SetPoint", "TOPLEFT", frame, "TOPLEFT", radius, 0)
        call(parts.center, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -radius, 0)
        call(parts.left, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 0, -radius)
        call(parts.left, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMLEFT", radius, radius)
        call(parts.right, "SetPoint", "TOPLEFT", frame, "TOPRIGHT", -radius, -radius)
        call(parts.right, "SetPoint", "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, radius)
        for i, spec in ipairs(CORNERS) do
            local t = tex()
            call(t, "SetTexture", CIRCLE)
            call(t, "SetTexCoord", spec[2], spec[3], spec[4], spec[5])
            call(t, "SetSize", radius, radius)
            call(t, "SetPoint", spec[1], frame, spec[1], 0, 0)
            parts[i] = t
        end
        frame.roundParts = parts
    end
    for _, key in ipairs({ "center", "left", "right" }) do call(parts[key], "SetColorTexture", r, g, b, alpha) end
    for i = 1, 4 do call(parts[i], "SetVertexColor", r, g, b, alpha) end
    local visible = alpha > 0
    for _, t in ipairs({ parts.center, parts.left, parts.right, parts[1], parts[2], parts[3], parts[4] }) do
        call(t, visible and "Show" or "Hide")
    end
    return frame
end

-- Square tonal surface for frames that also need a backdrop border later
-- (selection outlines, game-meaning colors). edge=false for no outline.
function S.Surface(frame, fill, alpha, edge, edgeAlpha)
    if not has(frame, "SetBackdrop") then return frame end
    local withEdge = edge ~= false
    call(frame, "SetBackdrop", { bgFile = WHITE, edgeFile = withEdge and WHITE or nil, edgeSize = withEdge and 1 or nil })
    local r, g, b = S.Color(fill or "surface")
    call(frame, "SetBackdropColor", r, g, b, alpha or 1)
    if withEdge then
        r, g, b = S.Color(edge or "line")
        call(frame, "SetBackdropBorderColor", r, g, b, edgeAlpha or 0.6)
    end
    return frame
end
-- Window, HUD, toast or popup: rounded, borderless, translucent.
function S.Panel(frame, role)
    local alpha = S.alpha[role or "window"] or S.alpha.window
    local result = S.Round(frame, "outer", alpha, role == "hud" and 10 or S.metrics.radius)
    -- 星辉: windows and popups get the gold corners, the open motion and the
    -- open/close sounds; HUD-role panels stay plain.
    if role == "window" or role == "popup" or role == nil then
        if S.Corners then S.Corners(frame) end
        if S.WindowMotion then S.WindowMotion(frame) end
    end
    return result
end

function S.SetType(fontString, level, colorName)
    local spec = S.type[level or "body"] or S.type.body
    local face = call(fontString, "GetFont")
    if type(face) == "string" and face ~= "" then call(fontString, "SetFont", face, spec[1], "") end
    call(fontString, "SetTextColor", S.Color(colorName or spec[2]))
    return fontString
end
-- Text with a role from the type scale. width is optional.
function S.Text(parent, level, width, message, layer)
    local fs = call(parent, "CreateFontString", nil, layer or "OVERLAY", "GameFontHighlightSmall")
    if not fs then return nil end
    S.SetType(fs, level)
    call(fs, "SetJustifyH", "LEFT")
    if width then call(fs, "SetWidth", width) end
    if message then call(fs, "SetText", message) end
    return fs
end
function S.Rule(parent, colorName, alpha)
    local t = call(parent, "CreateTexture", nil, "ARTWORK")
    if not t then return nil end
    local r, g, b = S.Color(colorName or "line")
    call(t, "SetColorTexture", r, g, b, alpha or 0.8)
    call(t, "SetHeight", 1)
    return t
end

local KINDS = {
    primary = { fill = "accent", text = "onAccent", hover = "accent" },
    default = { fill = "surface", text = "text", hover = "hover" },
    quiet = { fill = nil, text = "secondary", hover = "surface" },
    selected = { fill = "accentSoft", text = "accent", hover = "accentSoft" },
    danger = { fill = "surface", text = "danger", hover = "hover" },
}
-- Restyle a button in place. kind: primary (one per view), default, quiet
-- (toolbar/text actions), selected (active tab or pill), danger.
function S.SetButtonKind(button, kind)
    local spec = KINDS[kind or "default"] or KINDS.default
    button.styleKind = kind or "default"
    local height = call(button, "GetHeight")
    local radius = type(button.styleRadius) == "number" and button.styleRadius
        or (type(height) == "number" and height > 0 and math.min(S.metrics.control, height / 2)) or S.metrics.control
    S.Round(button, spec.fill or "surface", spec.fill and 1 or 0, radius, "BACKGROUND")
    if button.label then call(button.label, "SetTextColor", S.Color(spec.text)) end
    return button
end
local function hoverIn(self)
    local spec = KINDS[self.styleKind or "default"] or KINDS.default
    if self.IsEnabled and not self:IsEnabled() then return end
    if spec.hover then S.Round(self, spec.hover, spec.fill == "accent" and 0.85 or 1) end
end
local function hoverOut(self)
    local spec = KINDS[self.styleKind or "default"] or KINDS.default
    S.Round(self, spec.fill or "surface", spec.fill and 1 or 0)
end
S.HoverIn, S.HoverOut = hoverIn, hoverOut
function S.Button(parent, caption, width, height, onClick, kind)
    local b = CreateFrame("Button", nil, parent)
    call(b, "SetSize", width, height or S.metrics.button)
    b.label = S.Text(b, "button")
    if b.label then
        call(b.label, "SetPoint", "CENTER", b, "CENTER", 0, 0)
        call(b.label, "SetJustifyH", "CENTER")
        call(b.label, "SetText", caption or "")
    end
    S.SetButtonKind(b, kind)
    if onClick then call(b, "SetScript", "OnClick", onClick) end
    -- PostClick survives callers that replace OnClick later.
    call(b, "SetScript", "PostClick", function(self)
        if S.Sound then S.Sound(self.styleKind == "primary" and "confirm" or "select") end
    end)
    call(b, "SetScript", "OnEnter", hoverIn)
    call(b, "SetScript", "OnLeave", hoverOut)
    call(b, "SetScript", "OnDisable", function(self) call(self, "SetAlpha", 0.42) end)
    call(b, "SetScript", "OnEnable", function(self) call(self, "SetAlpha", 1) end)
    -- Blizzard buttons expose SetText/GetText; keep that contract for callers.
    b.SetText = function(self, value) if self.label then call(self.label, "SetText", value) end end
    b.GetText = function(self) return self.label and call(self.label, "GetText") or nil end
    return b
end
-- Rounded selectable chip. Use S.SetButtonKind(chip, chosen and "selected" or "quiet").
function S.Pill(parent, caption, width, onClick)
    local b = S.Button(parent, caption, width, 24, onClick, "quiet")
    b.styleRadius = 12
    S.SetButtonKind(b, "quiet")
    return b
end
function S.CloseButton(parent, onClick)
    local b = S.Button(parent, "×", 22, 22, onClick, "quiet")
    if b.label then S.SetType(b.label, "title", "muted") end
    return b
end

-- Title strip: name on the left, close on the right, the strip is the drag
-- handle. No rule under it: spacing separates it from the content.
-- Returns the bar; bar.title, bar.close and bar.handle are exposed.
function S.TitleBar(frame, title, onClose)
    local m = S.metrics
    local bar = CreateFrame("Frame", nil, frame)
    call(bar, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 0, 0)
    call(bar, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    call(bar, "SetHeight", m.title)
    bar.title = S.Text(bar, "title", nil, title)
    if bar.title then call(bar.title, "SetPoint", "LEFT", bar, "LEFT", m.pad, -1) end
    if S.WindowTitle then S.WindowTitle(bar.title, title) end
    if S.TitleRule then bar.rule = S.TitleRule(bar, m.pad, 0) end
    bar.close = S.CloseButton(bar, onClose or function() call(frame, "Hide") end)
    call(bar.close, "SetPoint", "RIGHT", bar, "RIGHT", -8, -1)
    bar.handle = CreateFrame("Frame", nil, bar)
    call(bar.handle, "SetPoint", "TOPLEFT", bar, "TOPLEFT", 0, 0)
    call(bar.handle, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -34, 0)
    return bar
end

-- Rounded tonal input behind a plain EditBox.
function S.Input(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent)
    call(holder, "SetSize", width, height or 28)
    S.Round(holder, "surface", 1, S.metrics.control)
    local box = CreateFrame("EditBox", nil, holder)
    call(box, "SetPoint", "TOPLEFT", holder, "TOPLEFT", 10, 0)
    call(box, "SetPoint", "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 0)
    call(box, "SetFontObject", "GameFontHighlightSmall")
    local face = call(box, "GetFont")
    if type(face) == "string" and face ~= "" then call(box, "SetFont", face, S.type.body[1], "") end
    call(box, "SetTextColor", S.Color("text"))
    call(box, "SetAutoFocus", false)
    call(box, "SetScript", "OnEscapePressed", function(self) call(self, "ClearFocus") end)
    call(box, "SetScript", "OnEditFocusGained", function() S.Round(holder, "hover", 1) end)
    call(box, "SetScript", "OnEditFocusLost", function() S.Round(holder, "surface", 1) end)
    box.holder = holder
    return box, holder
end

-- Thin rounded progress track. Returns the track; track:SetProgress(0..1, colorName).
function S.Progress(parent, width, height)
    local track = CreateFrame("Frame", nil, parent)
    height = height or 4
    call(track, "SetSize", width, height)
    S.Round(track, "surface", 1, height / 2)
    local fill = CreateFrame("Frame", nil, track)
    call(fill, "SetPoint", "TOPLEFT", track, "TOPLEFT", 0, 0)
    call(fill, "SetSize", 1, height)
    S.Round(fill, "accent", 1, height / 2)
    track.fill = fill
    function track:SetProgress(fraction, colorName)
        fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
        call(fill, "SetShown", fraction > 0)
        call(fill, "SetWidth", math.max(height, width * fraction))
        S.Round(fill, colorName or "accent", 1)
    end
    return track
end

-- Toast: short feedback shown where the player is already looking (next to
-- the panel they just used) instead of only in the chat log. Used for
-- "remembered, applies after combat" and the matching "applied" moment.
-- kind: "info" (accent), "pending" (warning), "success", "danger".
-- The colour stripe is a second cue; the text alone must carry the meaning.
-- Plain non-secure frame on UIParent, so it is safe to show in combat.
local TOAST_HOLD, TOAST_FADE = 2.6, 0.4
local toastStripe = { info = "accent", pending = "warning", success = "success", danger = "danger" }
function S.Toast(anchor, message, kind, seconds)
    if type(message) ~= "string" or message == "" or not CreateFrame then return nil end
    local t = S.toastFrame
    if not t then
        t = CreateFrame("Frame", nil, UIParent)
        if not t then return nil end
        S.toastFrame = t
        call(t, "SetFrameStrata", "DIALOG")
        call(t, "SetHeight", 30)
        S.Round(t, "outer", S.alpha.toast, 9)
        t.stripe = call(t, "CreateTexture", nil, "ARTWORK")
        call(t.stripe, "SetTexture", WHITE)
        call(t.stripe, "SetPoint", "TOPLEFT", t, "TOPLEFT", 6, -8)
        call(t.stripe, "SetPoint", "BOTTOMLEFT", t, "BOTTOMLEFT", 6, 8)
        call(t.stripe, "SetWidth", 3)
        t.text = S.Text(t, "secondary", nil, "")
        call(t.text, "SetPoint", "LEFT", t, "LEFT", 16, 0)
        call(t, "SetScript", "OnUpdate", function(self, elapsed)
            self.age = (self.age or 0) + (tonumber(elapsed) or 0)
            local hold = self.hold or TOAST_HOLD
            if self.age >= hold + TOAST_FADE then call(self, "Hide")
            elseif self.age > hold then call(self, "SetAlpha", 1 - (self.age - hold) / TOAST_FADE) end
        end)
    end
    call(t.text, "SetText", message)
    S.SetType(t.text, "secondary", "text")
    local width = tonumber(call(t.text, "GetStringWidth")) or (#message * 6)
    call(t, "SetWidth", math.min(420, math.max(120, width + 30)))
    call(t.stripe, "SetVertexColor", S.Color(toastStripe[kind] or "accent"))
    call(t, "ClearAllPoints")
    local visible = anchor and call(anchor, "IsVisible")
    if visible then call(t, "SetPoint", "BOTTOM", anchor, "TOP", 0, 8)
    else call(t, "SetPoint", "TOP", UIParent, "TOP", 0, -140) end
    t.age, t.hold = 0, tonumber(seconds) or TOAST_HOLD
    call(t, "SetAlpha", 1)
    call(t, "Show")
    return t
end

-- Layout: one way to place every 我的无限 panel, after the game's Edit Mode.
--   * While any panel is dragged a screen grid appears; on release the panel
--     snaps to it (S.metrics.grid UI units, measured from the screen centre).
--   * /myui (or /mylayout) opens layout mode: grid, a name tag on every open
--     panel, one "完成" button. Entering combat closes it.
-- Each addon keeps its own drag handle, lock and saved position. It calls
-- S.BeginDrag() when a move starts and S.SnapToGrid(frame) right after
-- StopMovingOrSizing and before it reads GetPoint to save. Snapping keeps the
-- frame's own anchor point and only nudges its offsets, never touches a
-- protected frame in combat, and does nothing for frames anchored elsewhere.
S.metrics.grid = 8
local GRID_LINE = 32
local layout = { frames = {}, active = false }
S.layout = layout

local function inCombat() return InCombatLockdown and InCombatLockdown() == true end
local function num(v) return type(v) == "number" and v == v and v > -1e9 and v < 1e9 end

local function gridFrame()
    if layout.grid then return layout.grid end
    if not CreateFrame or not UIParent then return nil end
    local g = CreateFrame("Frame", nil, UIParent)
    if not g then return nil end
    layout.grid = g
    call(g, "SetAllPoints", UIParent)
    call(g, "SetFrameStrata", "BACKGROUND")
    call(g, "EnableMouse", false)
    g.lines = {}
    g.hint = S.Text(g, "caption", nil, "")
    call(g.hint, "SetPoint", "TOP", g, "TOP", 0, -10)
    call(g, "Hide")
    return g
end

local function drawGrid(g)
    local w, h = tonumber(call(UIParent, "GetWidth")) or 0, tonumber(call(UIParent, "GetHeight")) or 0
    if w <= 0 or h <= 0 or (g.drawnW == w and g.drawnH == h) then return end
    g.drawnW, g.drawnH = w, h
    for _, line in ipairs(g.lines) do call(line, "Hide") end
    local used = 0
    local function line(vertical, offset, major)
        used = used + 1
        local t = g.lines[used]
        if not t then
            t = call(g, "CreateTexture", nil, "BACKGROUND")
            if not t then return end
            call(t, "SetTexture", WHITE)
            g.lines[used] = t
        end
        call(t, "ClearAllPoints")
        if vertical then
            call(t, "SetPoint", "TOP", g, "TOP", offset, 0); call(t, "SetPoint", "BOTTOM", g, "BOTTOM", offset, 0)
            call(t, "SetWidth", major and 1.5 or 1)
        else
            call(t, "SetPoint", "LEFT", g, "LEFT", 0, offset); call(t, "SetPoint", "RIGHT", g, "RIGHT", 0, offset)
            call(t, "SetHeight", major and 1.5 or 1)
        end
        local r, gg, b = S.Color(major and "accent" or "line")
        call(t, "SetVertexColor", r, gg, b, major and 0.45 or 0.22)
        call(t, "Show")
    end
    for i = 0, math.floor(w / 2 / GRID_LINE) do
        line(true, i * GRID_LINE, i == 0)
        if i > 0 then line(true, -i * GRID_LINE, false) end
    end
    for i = 0, math.floor(h / 2 / GRID_LINE) do
        line(false, i * GRID_LINE, i == 0)
        if i > 0 then line(false, -i * GRID_LINE, false) end
    end
end

local function showGrid(hint)
    local g = gridFrame()
    if not g then return end
    drawGrid(g)
    call(g.hint, "SetText", hint or "")
    call(g, "Show")
end
local function hideGrid()
    if layout.grid and not layout.active then call(layout.grid, "Hide") end
end

-- Rectangle of a frame in UIParent units, or nil.
local function rectOf(frame)
    local fs, us = call(frame, "GetEffectiveScale"), call(UIParent, "GetEffectiveScale")
    local l, r = call(frame, "GetLeft"), call(frame, "GetRight")
    local t, b = call(frame, "GetTop"), call(frame, "GetBottom")
    if not (num(fs) and num(us) and fs > 0 and us > 0 and num(l) and num(r) and num(t) and num(b)) then return nil end
    local k = fs / us
    return { l = l * k, r = r * k, t = t * k, b = b * k, cx = (l + r) / 2 * k, cy = (t + b) / 2 * k, k = k }
end

-- Smart guides (as in Figma / Keynote): the dragged panel's edges and centre
-- are compared with every other open panel's edges and centres and with the
-- screen centre. Within S.metrics.magnet units it "sticks" to the closest one.
S.metrics.magnet = 8
local function smartAlign(rect, moving, exclude)
    local w, h = tonumber(call(UIParent, "GetWidth")) or 0, tonumber(call(UIParent, "GetHeight")) or 0
    local xs, ys = { w / 2 }, { h / 2 }
    for _, entry in ipairs(layout.frames) do
        local f = entry.frame
        if f ~= moving and f ~= exclude and call(f, "IsVisible") == true then
            local o = rectOf(f)
            if o then
                xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = o.l, o.r, o.cx
                ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = o.t, o.b, o.cy
            end
        end
    end
    local function best(own, targets)
        local bestD, bestAt
        for _, mine in ipairs(own) do
            for _, at in ipairs(targets) do
                local d = at - mine
                if math.abs(d) <= S.metrics.magnet and (not bestD or math.abs(d) < math.abs(bestD)) then bestD, bestAt = d, at end
            end
        end
        return bestD, bestAt
    end
    local dx, gx = best({ rect.l, rect.r, rect.cx }, xs)
    local dy, gy = best({ rect.t, rect.b, rect.cy }, ys)
    return dx, dy, gx, gy
end

local function freePlacement() return IsAltKeyDown and IsAltKeyDown() == true end

-- Guide textures live in layout.guides (plain table), not as frame fields.
layout.guides = {}
local function guideLine(g, key, vertical)
    local t = layout.guides[key]
    if not t then
        t = call(g, "CreateTexture", nil, "OVERLAY")
        if not t then return nil end
        call(t, "SetTexture", WHITE)
        call(t, "SetVertexColor", S.Color("success", 0.95))
        layout.guides[key] = t
    end
    call(t, "ClearAllPoints")
    if vertical then call(t, "SetWidth", 1.5) else call(t, "SetHeight", 1.5) end
    return t
end

local function updateGuides(g)
    local drag = layout.drag
    local v, hz = layout.guides.v, layout.guides.h
    if v then call(v, "Hide") end
    if hz then call(hz, "Hide") end
    if not drag or freePlacement() then return end
    local rect = rectOf(drag.frame)
    if not rect then return end
    local dx, dy, gx, gy = smartAlign(rect, drag.frame, drag.exclude)
    if dx then
        v = guideLine(g, "v", true)
        call(v, "SetPoint", "TOP", g, "TOPLEFT", gx, 0); call(v, "SetPoint", "BOTTOM", g, "BOTTOMLEFT", gx, 0)
        call(v, "Show")
    end
    if dy then
        hz = guideLine(g, "h", false)
        call(hz, "SetPoint", "LEFT", g, "BOTTOMLEFT", 0, gy); call(hz, "SetPoint", "RIGHT", g, "BOTTOMRIGHT", 0, gy)
        call(hz, "Show")
    end
end

-- History, selection and per-panel tools (layout mode).
-- RegisterLayout(frame, label, opts) — every opts field is optional:
--   save(frame)  persist the frame's current position (after undo / nudge);
--                leave nil for panels whose position is not saved anyway
--   reset()      move the panel to its default position and persist it
--   scale        { get = fn() -> number, set = fn(number), min, max, step }
local HISTORY_MAX = 30
layout.history = {}

local function entryFor(frame)
    for _, entry in ipairs(layout.frames) do if entry.frame == frame then return entry end end
end

local function pointOf(frame)
    local point, relativeTo, relativePoint, x, y = call(frame, "GetPoint", 1)
    if type(point) ~= "string" or not num(x) or not num(y) then return nil end
    return { point, relativeTo or UIParent, relativePoint or point, x, y }
end

local function persist(entry)
    if entry and type(entry.opts.save) == "function" then pcall(entry.opts.save, entry.frame) end
end

local function pushHistory(entry, before)
    if not entry or not before then return end
    local h = layout.history
    h[#h + 1] = { entry = entry, before = before }
    if #h > HISTORY_MAX then table.remove(h, 1) end
end

local refreshTags

function S.SelectLayout(frame)
    layout.selected = frame and entryFor(frame) or nil
    layout.nudging = nil
    if refreshTags then refreshTags() end
end

-- Undo the most recent move (drag, nudge or reset), newest first.
function S.UndoLayout()
    if inCombat() then return false end
    local item = table.remove(layout.history)
    if not item then S.Toast(layout.bar, "没有可撤销的移动", "info") return false end
    local p = item.before
    call(item.entry.frame, "ClearAllPoints")
    call(item.entry.frame, "SetPoint", p[1], p[2], p[3], p[4], p[5])
    persist(item.entry)
    layout.nudging = nil
    S.Toast(layout.bar, "已撤销：" .. item.entry.label, "success", 1.6)
    if refreshTags then refreshTags() end
    return true
end

-- Move the selected panel by dx, dy UI units (arrow keys).
function S.NudgeLayout(dx, dy)
    local entry = layout.selected
    if not entry or inCombat() or call(entry.frame, "IsVisible") ~= true then return false end
    local p = pointOf(entry.frame)
    local rect = rectOf(entry.frame)
    if not p or not rect then return false end
    if layout.nudging ~= entry then pushHistory(entry, p); layout.nudging = entry end
    call(entry.frame, "ClearAllPoints")
    call(entry.frame, "SetPoint", p[1], p[2], p[3], p[4] + dx / rect.k, p[5] + dy / rect.k)
    persist(entry)
    return true
end

function S.ResetLayout()
    local entry = layout.selected
    if not entry or inCombat() or type(entry.opts.reset) ~= "function" then return false end
    pushHistory(entry, pointOf(entry.frame))
    layout.nudging = nil
    local ok = pcall(entry.opts.reset)
    if ok then S.Toast(layout.bar, "已还原默认位置：" .. entry.label, "success", 1.6) end
    if refreshTags then refreshTags() end
    return ok
end

function S.StepLayoutScale(direction)
    local entry = layout.selected
    local sc = entry and entry.opts.scale
    if not sc or inCombat() then return false end
    local okGet, value = pcall(sc.get)
    if not okGet or not num(value) then return false end
    local step = sc.step or 0.05
    local target = math.floor((value + direction * step) / step + 0.5) * step
    target = math.max(sc.min or 0.5, math.min(sc.max or 2, target))
    if math.abs(target - value) < 0.001 then return false end
    pcall(sc.set, target)
    if refreshTags then refreshTags() end
    return true
end

-- Call when a panel starts moving: frame is what the cursor moves, exclude is
-- the real panel when a stand-in outline is dragged. Shows grid and guides,
-- selects the panel and remembers where it was for undo.
function S.BeginDrag(frame, exclude)
    layout.drag = frame and { frame = frame, exclude = exclude } or nil
    local entry = entryFor(exclude or frame)
    if layout.drag then layout.drag.entry, layout.drag.before = entry, entry and pointOf(entry.frame) end
    if entry and layout.active then layout.selected = entry end
    layout.nudging = nil
    showGrid(layout.active and "" or "对齐边缘或网格 · 按住 Alt 自由放置 · /myui 摆放全部面板")
    local g = layout.grid
    if g and not layout.guidesHooked then
        layout.guidesHooked = true
        local elapsed = 0
        call(g, "SetScript", "OnUpdate", function(self, dt)
            elapsed = elapsed + (tonumber(dt) or 0)
            if elapsed >= 0.03 then elapsed = 0; updateGuides(self) end
        end)
    end
end

-- Call right after StopMovingOrSizing, before reading GetPoint to save.
-- Sticks to a smart guide when one is close, otherwise to the grid; with Alt
-- held it leaves the panel exactly where it was dropped. Returns true if moved.
function S.SnapToGrid(frame)
    local drag = layout.drag
    layout.drag = nil
    if drag and drag.entry then pushHistory(drag.entry, drag.before) end
    if layout.guides.v then call(layout.guides.v, "Hide") end
    if layout.guides.h then call(layout.guides.h, "Hide") end
    hideGrid()
    if not frame or freePlacement() then return false end
    if inCombat() and call(frame, "IsProtected") then return false end
    local point, relativeTo, relativePoint, x, y = call(frame, "GetPoint", 1)
    if relativeTo ~= nil and relativeTo ~= UIParent then return false end
    if type(point) ~= "string" or type(relativePoint) ~= "string" or not num(x) or not num(y) then return false end
    local rect = rectOf(frame)
    local w, h = call(UIParent, "GetWidth"), call(UIParent, "GetHeight")
    if not rect or not (num(w) and num(h)) then return false end
    local sdx, sdy = smartAlign(rect, frame, drag and drag.exclude)
    local step, cx, cy = S.metrics.grid, w / 2, h / 2
    local dx = sdx or (cx + math.floor((rect.l - cx) / step + 0.5) * step - rect.l)
    local dy = sdy or (cy + math.floor((rect.t - cy) / step + 0.5) * step - rect.t)
    dx, dy = dx / rect.k, dy / rect.k
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return false end
    call(frame, "ClearAllPoints")
    call(frame, "SetPoint", point, UIParent, relativePoint, x + dx, y + dy)
    return true
end
S.Snap = S.SnapToGrid

-- Panels announce themselves for layout mode. Re-registering updates them.
function S.RegisterLayout(frame, label, opts)
    if not frame or type(label) ~= "string" then return end
    opts = type(opts) == "table" and opts or {}
    local entry = entryFor(frame)
    if entry then entry.label, entry.opts = label, opts return end
    layout.frames[#layout.frames + 1] = { frame = frame, label = label, opts = opts }
end

local function tagFor(entry)
    if entry.tag then return entry.tag end
    local tag = CreateFrame("Frame", nil, UIParent)
    if not tag then return nil end
    entry.tag = tag
    call(tag, "SetFrameStrata", "TOOLTIP")
    call(tag, "EnableMouse", false)
    call(tag, "SetAllPoints", entry.frame)
    tag.edges = {}
    for i, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = call(tag, "CreateTexture", nil, "OVERLAY")
        call(t, "SetTexture", WHITE)
        call(t, "SetPoint", spec[1], tag, spec[1], 0, 0)
        call(t, "SetPoint", spec[2], tag, spec[2], 0, 0)
        tag.edges[i] = { texture = t, horizontal = spec[3] }
    end
    -- Only the name pill takes the mouse: the panel itself stays draggable.
    tag.name = CreateFrame("Button", nil, tag)
    call(tag.name, "SetPoint", "BOTTOMLEFT", tag, "TOPLEFT", 0, 4)
    call(tag.name, "SetHeight", 20)
    call(tag.name, "EnableMouse", true)
    call(tag.name, "RegisterForClicks", "LeftButtonUp")
    call(tag.name, "SetScript", "OnClick", function() S.SelectLayout(entry.frame) end)
    tag.text = S.Text(tag.name, "caption", nil, entry.label)
    call(tag.text, "SetPoint", "LEFT", tag.name, "LEFT", 8, 0)
    call(tag.name, "SetWidth", (tonumber(call(tag.text, "GetStringWidth")) or 60) + 16)
    return tag
end

local function paintTag(entry, selected)
    local tag = entry.tag
    local color = selected and "success" or "accent"
    for _, edge in ipairs(tag.edges) do
        call(edge.texture, "SetVertexColor", S.Color(color, 0.95))
        call(edge.texture, edge.horizontal and "SetHeight" or "SetWidth", selected and 2 or 1)
    end
    S.Round(tag.name, color, 1, 6)
    S.SetType(tag.text, "caption", "onAccent")
    call(tag.text, "SetText", entry.label .. (selected and "（已选）" or ""))
    call(tag.name, "SetWidth", (tonumber(call(tag.text, "GetStringWidth")) or 60) + 16)
end

local SELECT_HINT = "点面板上方的名字选中它：方向键微调（Shift 每次 8），Ctrl+Z 撤销，Esc 退出。"

local function refreshBar(shown, closed)
    local bar = layout.bar
    if not bar then return end
    local line = shown > 0 and ("已打开 " .. shown .. " 个：拖标题栏移动，靠近边缘自动吸附，按住 Alt 自由放置。")
        or "还没有打开的面板。先打开要摆放的面板，它会出现在这里。"
    if #closed > 0 then line = line .. "\n未打开：" .. table.concat(closed, "、") end
    call(bar.count, "SetText", line)
    call(bar.undo, "SetEnabled", #layout.history > 0)
    local entry = layout.selected
    local visible = entry and call(entry.frame, "IsVisible") == true
    if not visible then entry = nil end
    call(bar.selected, "SetText", entry and ("已选：" .. entry.label) or SELECT_HINT)
    S.SetType(bar.selected, "secondary", entry and "text" or "muted")
    local sc = entry and entry.opts.scale
    local value = sc and select(2, pcall(sc.get))
    for _, b in ipairs({ bar.smaller, bar.bigger, bar.size }) do call(b, "SetShown", sc ~= nil) end
    if sc and num(value) then call(bar.size, "SetText", "大小 " .. math.floor(value * 100 + 0.5) .. "%") end
    call(bar.reset, "SetShown", entry ~= nil and type(entry.opts.reset) == "function")
    call(bar, "SetHeight", 104 + (#closed > 0 and 18 or 0))
end

refreshTags = function()
    local shown, closed = 0, {}
    for _, entry in ipairs(layout.frames) do
        local visible = layout.active and call(entry.frame, "IsVisible") == true
        if visible then shown = shown + 1 end
        if layout.active and call(entry.frame, "IsVisible") ~= true then closed[#closed + 1] = entry.label end
        local tag = (visible or entry.tag) and tagFor(entry)
        if tag then
            call(tag, "SetShown", visible)
            if visible then paintTag(entry, entry == layout.selected) end
        end
    end
    refreshBar(shown, closed)
    return shown
end

local ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local function onKey(self, key)
    local consume = false
    if inCombat() then return end
    if key == "ESCAPE" then consume = true; S.SetLayoutMode(false)
    elseif key == "Z" and IsControlKeyDown and IsControlKeyDown() then consume = true; S.UndoLayout()
    elseif ARROWS[key] and layout.selected then
        consume = true
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and S.metrics.grid or 1
        S.NudgeLayout(ARROWS[key][1] * step, ARROWS[key][2] * step)
    end
    call(self, "SetPropagateKeyboardInput", not consume)
end

local function buildBar()
    local bar = CreateFrame("Frame", nil, UIParent)
    layout.bar = bar
    call(bar, "SetFrameStrata", "TOOLTIP")
    call(bar, "SetSize", 560, 104)
    call(bar, "SetPoint", "TOP", UIParent, "TOP", 0, -36)
    call(bar, "EnableMouse", true)
    S.Round(bar, "outer", S.alpha.popup, 12)
    bar.title = S.Text(bar, "title", nil, "布局模式")
    call(bar.title, "SetPoint", "TOPLEFT", bar, "TOPLEFT", 16, -12)
    bar.count = S.Text(bar, "secondary", 400, "")
    call(bar.count, "SetPoint", "TOPLEFT", bar, "TOPLEFT", 16, -34)
    bar.done = S.Button(bar, "完成", 64, 26, function() S.SetLayoutMode(false) end, "primary")
    call(bar.done, "SetPoint", "TOPRIGHT", bar, "TOPRIGHT", -14, -12)
    bar.undo = S.Button(bar, "撤销", 64, 26, function() S.UndoLayout() end, "default")
    call(bar.undo, "SetPoint", "RIGHT", bar.done, "LEFT", -8, 0)
    -- Selection row: what is selected and what can be done to it.
    bar.rule = S.Rule(bar, "line", 0.6)
    call(bar.rule, "SetPoint", "BOTTOMLEFT", bar, "BOTTOMLEFT", 16, 44)
    call(bar.rule, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -16, 44)
    bar.selected = S.Text(bar, "secondary", 300, "")
    call(bar.selected, "SetPoint", "BOTTOMLEFT", bar, "BOTTOMLEFT", 16, 18)
    bar.reset = S.Button(bar, "还原默认位置", 104, 24, function() S.ResetLayout() end, "quiet")
    call(bar.reset, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -14, 12)
    bar.bigger = S.Button(bar, "+", 26, 24, function() S.StepLayoutScale(1) end, "default")
    call(bar.bigger, "SetPoint", "RIGHT", bar.reset, "LEFT", -10, 0)
    bar.size = S.Text(bar, "secondary", 70, "")
    call(bar.size, "SetPoint", "RIGHT", bar.bigger, "LEFT", -6, 0)
    call(bar.size, "SetJustifyH", "CENTER")
    bar.smaller = S.Button(bar, "-", 26, 24, function() S.StepLayoutScale(-1) end, "default")
    call(bar.smaller, "SetPoint", "RIGHT", bar.size, "LEFT", -6, 0)
    local elapsed = 0
    call(bar, "SetScript", "OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed >= 0.25 then elapsed = 0; refreshTags() end
    end)
    -- Keyboard: only arrows, Ctrl+Z and Esc are taken; everything else
    -- (movement, spells, chat) passes through to the game.
    layout.keys = CreateFrame("Frame", nil, UIParent)
    call(layout.keys, "EnableKeyboard", true)
    call(layout.keys, "SetPropagateKeyboardInput", true)
    call(layout.keys, "SetScript", "OnKeyDown", onKey)
    call(layout.keys, "Hide")
end

function S.SetLayoutMode(on)
    on = on == true
    if on and inCombat() then
        S.Toast(nil, "战斗中不能进入布局模式", "pending")
        return false
    end
    layout.active = on
    layout.nudging = nil
    if on then
        showGrid("")
        if not layout.bar then buildBar() end
        call(layout.bar, "Show")
        call(layout.keys, "Show")
    else
        layout.selected = nil
        if layout.bar then call(layout.bar, "Hide") end
        if layout.keys then call(layout.keys, "Hide") end
        if layout.grid then call(layout.grid, "Hide") end
    end
    refreshTags()
    return true
end
function S.ToggleLayoutMode() return S.SetLayoutMode(not layout.active) end

if CreateFrame then
    local events = CreateFrame("Frame")
    if events then
        call(events, "RegisterEvent", "PLAYER_REGEN_DISABLED")
        call(events, "SetScript", "OnEvent", function()
            if layout.active then S.SetLayoutMode(false); S.Toast(nil, "进入战斗，已退出布局模式", "pending") end
            if layout.grid then call(layout.grid, "Hide") end
        end)
    end
end
if type(SlashCmdList) == "table" then
    SLASH_MYFOREVERLAYOUT1, SLASH_MYFOREVERLAYOUT2 = "/myui", "/mylayout"
    SlashCmdList.MYFOREVERLAYOUT = function(message)
        local word = type(message) == "string" and message:lower():match("^%s*(%S*)") or ""
        if word == "sound" or word == "音效" then
            local on = S.SetSoundEnabled(not S.SoundEnabled())
            S.Toast(nil, on and "我的无限：菜单音效已开启" or "我的无限：菜单音效已关闭", "success")
            return
        end
        S.ToggleLayoutMode()
    end
end


-- 星辉 (v5): the suite's own console-inspired layer on top of Midnight.
-- Menus may perform (corners, title rule, selection cursor, motion, sound);
-- combat panels stay plain. Nothing here runs or animates in combat.

local function now() return (GetTime and tonumber(GetTime())) or 0 end
S.loadedAt = now()

-- Gold L-shaped corners just outside a window (Final Fantasy style frames).
function S.Corners(frame)
    if not frame or type(frame.styleCorners) == "table" then return end
    local corners = {}
    frame.styleCorners = corners
    local size, thick, out = 12, 1.5, 4
    for _, spec in ipairs({ { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }) do
        local point, sx, sy = spec[1], spec[2], spec[3]
        for i = 1, 2 do
            local t = call(frame, "CreateTexture", nil, "OVERLAY")
            if t then
                call(t, "SetTexture", WHITE)
                call(t, "SetVertexColor", S.Color("gold", 0.75))
                call(t, "SetPoint", point, frame, point, sx * out, sy * out)
                if i == 1 then call(t, "SetSize", size, thick) else call(t, "SetSize", thick, size) end
                corners[#corners + 1] = t
            end
        end
    end
end

-- Window titles: classical face when the client has it, wider spacing, warm
-- white. Spacing is real spaces between characters (FontStrings have no
-- tracking); only for short titles.
S.titleFont = "Fonts\\ARKai_T.ttf"
local function spaced(text)
    if type(text) ~= "string" then return text end
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    -- Lua's %w/%p classes depend on LC_CTYPE and can classify UTF-8 bytes as
    -- ASCII text. Check the ASCII byte range explicitly in every locale.
    if #chars < 2 or #chars > 6 or text:find("[%z\1-\127]") then return text end
    return table.concat(chars, " ")
end
S.SpacedTitle = spaced
function S.WindowTitle(fontString, text)
    if not fontString then return end
    local face, size, flags = call(fontString, "GetFont")
    if type(size) == "number" and S.titleFont then
        local ok = call(fontString, "SetFont", S.titleFont, size + 1, flags or "")
        if ok == false and type(face) == "string" then call(fontString, "SetFont", face, size, flags or "") end
    end
    call(fontString, "SetTextColor", S.Color("titleText"))
    if type(text) == "string" then call(fontString, "SetText", spaced(text)) end
end

-- Thin gold rule under a title, fading out to the right.
-- top: when given, the rule sits that far below the parent's top edge.
function S.TitleRule(parent, left, bottom, width, top)
    local t = call(parent, "CreateTexture", nil, "ARTWORK")
    if not t then return nil end
    call(t, "SetTexture", WHITE)
    call(t, "SetHeight", 1)
    if top then call(t, "SetPoint", "TOPLEFT", parent, "TOPLEFT", left or 14, -top)
    else call(t, "SetPoint", "BOTTOMLEFT", parent, "BOTTOMLEFT", left or 14, bottom or 0) end
    local w = width or ((tonumber(call(parent, "GetWidth")) or 300) * 0.55)
    call(t, "SetWidth", math.max(60, w))
    local r, g, b = S.Color("gold")
    if CreateColor and has(t, "SetGradient") then
        call(t, "SetGradient", "HORIZONTAL", CreateColor(r, g, b, 0.85), CreateColor(r, g, b, 0))
    else
        call(t, "SetVertexColor", r, g, b, 0.5)
    end
    return t
end

-- Selection cursor for list rows (Persona-style slanted band + a breathing
-- gold diamond). Text must start at least 18 units in from the row's left.
function S.MarkSelected(row, on)
    if not row then return end
    local mark = type(row.styleMark) == "table" and row.styleMark or nil
    if not mark then
        if not on then return end
        mark = {}
        row.styleMark = mark
        mark.band = call(row, "CreateTexture", nil, "BACKGROUND", nil, 1)
        call(mark.band, "SetTexture", WHITE)
        call(mark.band, "SetPoint", "TOPLEFT", row, "TOPLEFT", 2, -4)
        call(mark.band, "SetPoint", "BOTTOMLEFT", row, "BOTTOMLEFT", 2, 4)
        call(mark.band, "SetWidth", math.max(40, (tonumber(call(row, "GetWidth")) or 200) * 0.7))
        local r, g, b = S.Color("accent")
        if CreateColor and has(mark.band, "SetGradient") then
            call(mark.band, "SetGradient", "HORIZONTAL", CreateColor(r, g, b, 0.5), CreateColor(r, g, b, 0))
        else
            call(mark.band, "SetVertexColor", r, g, b, 0.28)
        end
        mark.diamond = call(row, "CreateTexture", nil, "OVERLAY")
        call(mark.diamond, "SetTexture", WHITE)
        call(mark.diamond, "SetSize", 6, 6)
        call(mark.diamond, "SetPoint", "LEFT", row, "LEFT", 7, 0)
        call(mark.diamond, "SetVertexColor", S.Color("gold"))
        call(mark.diamond, "SetRotation", math.rad(45))
        local group = call(mark.diamond, "CreateAnimationGroup")
        if group then
            call(group, "SetLooping", "BOUNCE")
            local fade = call(group, "CreateAnimation", "Alpha")
            if fade then
                call(fade, "SetFromAlpha", 1); call(fade, "SetToAlpha", 0.45)
                call(fade, "SetDuration", 0.9); call(fade, "SetSmoothing", "IN_OUT")
            end
            mark.breath = group
        end
    end
    call(mark.band, "SetShown", on == true)
    call(mark.diamond, "SetShown", on == true)
    if mark.breath then
        if on and not inCombat() then call(mark.breath, "Play") else call(mark.breath, "Stop") end
    end
end

-- Menu sounds. Built-in sound kits only; off in combat, quiet for the first
-- seconds after login, and switchable with /myui sound.
S.sounds = {
    open = "IG_CHARACTER_INFO_OPEN", close = "IG_CHARACTER_INFO_CLOSE",
    select = "U_CHAT_SCROLL_BUTTON", confirm = "IG_MAINMENU_OPTION_CHECKBOX_ON",
}
function S.SoundEnabled()
    local db = rawget(_G, "MyForeverStyleDB")
    return not (type(db) == "table" and db.sound == false)
end
function S.SetSoundEnabled(on)
    local db = rawget(_G, "MyForeverStyleDB")
    if type(db) ~= "table" then db = {}; _G.MyForeverStyleDB = db end
    db.sound = on == true
    return db.sound
end
function S.Sound(kind)
    if not S.SoundEnabled() or inCombat() or not PlaySound then return false end
    if now() - (S.loadedAt or 0) < 4 then return false end
    local kits = rawget(_G, "SOUNDKIT")
    local id = type(kits) == "table" and kits[S.sounds[kind] or ""] or nil
    if type(id) ~= "number" then return false end
    return pcall(PlaySound, id, "SFX") and true or false
end

-- Window motion: 0.15 s fade and 6-unit rise on show, plus open/close sounds.
-- Skipped for protected frames and in combat.
function S.WindowMotion(frame)
    if not frame or frame.styleMotion == true then return end
    frame.styleMotion = true
    local group = call(frame, "CreateAnimationGroup")
    if group then
        local fade = call(group, "CreateAnimation", "Alpha")
        if fade then call(fade, "SetFromAlpha", 0); call(fade, "SetToAlpha", 1); call(fade, "SetDuration", 0.15) end
        local rise = call(group, "CreateAnimation", "Translation")
        if rise then
            call(rise, "SetOffset", 0, 6); call(rise, "SetDuration", 0.15); call(rise, "SetSmoothing", "OUT")
        end
        frame.styleOpen = group
    end
    local hook = has(frame, "HookScript") and "HookScript" or nil
    if not hook then return end
    call(frame, hook, "OnShow", function(self)
        if inCombat() or call(self, "IsProtected") then return end
        if self.styleOpen then call(self.styleOpen, "Stop"); call(self.styleOpen, "Play") end
        S.Sound("open")
    end)
    call(frame, hook, "OnHide", function() S.Sound("close") end)
end

-- Console-style key hints under a window: {{"左键","选择"},{"Esc","关闭"}}.
-- Sits just outside the bottom edge so no existing layout moves.
function S.HintBar(frame, items, trailing)
    if not frame or type(items) ~= "table" then return nil end
    local bar = CreateFrame("Frame", nil, frame)
    if not bar then return nil end
    call(bar, "SetPoint", "TOPLEFT", frame, "BOTTOMLEFT", 0, -10)
    call(bar, "SetPoint", "TOPRIGHT", frame, "BOTTOMRIGHT", 0, -10)
    call(bar, "SetHeight", 26)
    S.Round(bar, "outer", 0.78, 8)
    local x = 10
    bar.keys = {}
    for _, item in ipairs(items) do
        local cap = CreateFrame("Frame", nil, bar)
        call(cap, "SetHeight", 18)
        S.Round(cap, "line", 1, 5)
        local key = S.Text(cap, "caption", nil, item[1])
        S.SetType(key, "caption", "text")
        call(key, "SetPoint", "CENTER", cap, "CENTER", 0, 0)
        local kw = (tonumber(call(key, "GetStringWidth")) or 20) + 10
        call(cap, "SetWidth", math.max(20, kw))
        call(cap, "SetPoint", "LEFT", bar, "LEFT", x, 0)
        local label = S.Text(bar, "caption", nil, item[2])
        call(label, "SetPoint", "LEFT", cap, "RIGHT", 5, 0)
        x = x + math.max(20, kw) + 5 + ((tonumber(call(label, "GetStringWidth")) or 24)) + 14
        bar.keys[#bar.keys + 1] = { cap = cap, key = key, label = label }
    end
    if type(trailing) == "string" then
        bar.trailing = S.Text(bar, "caption", nil, trailing)
        call(bar.trailing, "SetPoint", "RIGHT", bar, "RIGHT", -10, 0)
    end
    return bar
end

-- Slim scroll bar for UIPanelScrollFrameTemplate-style frames: hides the
-- arrow buttons and track art, keeps a thin tonal thumb. Scrolling (wheel,
-- drag, the bar's value) is untouched; only looks change.
function S.SkinScroll(scroll)
    if not scroll or scroll.styleScroll == true then return end
    local bar = scroll.ScrollBar
    if type(bar) ~= "table" then
        local name = call(scroll, "GetName")
        bar = type(name) == "string" and rawget(_G, name .. "ScrollBar") or nil
    end
    if type(bar) ~= "table" then return end
    scroll.styleScroll = true
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton", "Top", "Bottom", "Middle", "Background", "Track" }) do
        local part = rawget(bar, key)
        if type(part) == "table" then call(part, "SetAlpha", 0); call(part, "EnableMouse", false) end
    end
    local regions = { call(bar, "GetRegions") }
    local thumb = call(bar, "GetThumbTexture")
    for _, region in ipairs(regions) do
        if region ~= thumb and call(region, "GetObjectType") == "Texture" then call(region, "SetAlpha", 0) end
    end
    if thumb then
        call(thumb, "SetTexture", WHITE)
        call(thumb, "SetVertexColor", S.Color("line", 0.9))
        call(thumb, "SetSize", 4, 36)
    end
    local track = call(bar, "CreateTexture", nil, "BACKGROUND")
    if track then
        call(track, "SetTexture", WHITE)
        call(track, "SetVertexColor", S.Color("surface", 0.6))
        call(track, "SetPoint", "TOP", bar, "TOP", 0, 0)
        call(track, "SetPoint", "BOTTOM", bar, "BOTTOM", 0, 0)
        call(track, "SetWidth", 2)
    end
    return bar
end
