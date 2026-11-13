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
local VERSION = 3
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
local function call(object, method, ...)
    local fn = has(object, method)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, object, ...)
    if ok then return a, b, c end
    return nil
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
    return S.Round(frame, "outer", alpha, role == "hud" and 10 or S.metrics.radius)
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
