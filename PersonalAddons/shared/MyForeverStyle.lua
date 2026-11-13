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
-- The palette is the published chat addon's default "jade" look (graphite
-- surface, green accent), so the suite matches the website and the launcher
-- icons players already know. Game-meaning colors (item quality, class,
-- recipe difficulty, target red, focus gold, chat channels) are NOT part of
-- this file and must stay with the code that owns that meaning.
--
-- Every widget call is guarded: a missing method is skipped instead of raising,
-- because a styling helper must never break an addon in a client variant.
local VERSION = 1
local existing = rawget(_G, "MyForeverStyle")
if type(existing) == "table" and (tonumber(existing.version) or 0) >= VERSION then return end

local S = { version = VERSION }
_G.MyForeverStyle = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
S.WHITE = WHITE

-- Surfaces go from the window itself (outer) up to raised/hover/selected.
S.colors = {
    outer = { 0.055, 0.067, 0.072 },      -- window body
    side = { 0.085, 0.101, 0.108 },       -- secondary column, title strip
    surface = { 0.12, 0.14, 0.15 },       -- controls, cards, inputs
    hover = { 0.16, 0.20, 0.20 },
    selected = { 0.16, 0.27, 0.24 },      -- chosen row or tab
    line = { 0.24, 0.29, 0.30 },          -- hairline borders and rules
    accent = { 0.42, 0.82, 0.58 },        -- brand green: primary action, active state
    onAccent = { 0.06, 0.16, 0.10 },      -- text on an accent fill
    text = { 0.91, 0.94, 0.93 },          -- primary content
    secondary = { 0.74, 0.79, 0.79 },     -- labels next to content
    muted = { 0.57, 0.65, 0.65 },         -- hints, captions, units
    disabled = { 0.40, 0.45, 0.46 },
    warning = { 0.95, 0.77, 0.43 },
    danger = { 0.95, 0.55, 0.51 },
    info = { 0.55, 0.75, 0.95 },
}

-- Background opacity by role. Only the backdrop is translucent; text and
-- icons stay opaque (never SetAlpha on the parent frame for this).
S.alpha = { window = 0.94, hud = 0.72, toast = 0.82, popup = 0.97 }

-- Type scale in UI units. "value" is for the one number a panel is about.
S.type = {
    title = { 15, "text" }, heading = { 13, "secondary" }, body = { 13, "text" },
    secondary = { 12, "secondary" }, caption = { 11, "muted" }, value = { 20, "text" },
    button = { 12, "text" },
}

S.metrics = { pad = 12, gap = 8, row = 24, button = 24, title = 30, icon = 42 }

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

-- Flat surface with a hairline edge. role: window | hud | toast | popup, or
-- pass fill/edge color names for inner surfaces.
function S.Surface(frame, fill, alpha, edge, edgeAlpha)
    if not has(frame, "SetBackdrop") then return frame end
    call(frame, "SetBackdrop", { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local r, g, b = S.Color(fill or "surface")
    call(frame, "SetBackdropColor", r, g, b, alpha or 1)
    r, g, b = S.Color(edge or "line")
    call(frame, "SetBackdropBorderColor", r, g, b, edgeAlpha or 1)
    return frame
end
function S.Panel(frame, role)
    local alpha = S.alpha[role or "window"] or S.alpha.window
    return S.Surface(frame, "outer", alpha, "line", role == "hud" and 0.35 or 0.9)
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
    primary = { fill = "accent", text = "onAccent", edge = "accent" },
    default = { fill = "surface", text = "text", edge = "line" },
    quiet = { fill = nil, text = "secondary", edge = nil },
    selected = { fill = "selected", text = "accent", edge = "accent" },
    danger = { fill = "surface", text = "danger", edge = "line" },
}
-- Restyle a button in place. kind: primary (one per view), default, quiet
-- (toolbar/text actions), selected (active tab), danger.
function S.SetButtonKind(button, kind)
    local spec = KINDS[kind or "default"] or KINDS.default
    button.styleKind = kind or "default"
    if has(button, "SetBackdrop") then
        if spec.fill then
            call(button, "SetBackdrop", { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            call(button, "SetBackdropColor", S.Color(spec.fill))
            call(button, "SetBackdropBorderColor", S.Color(spec.edge or "line"))
        else
            call(button, "SetBackdrop", nil)
        end
    end
    if button.label then call(button.label, "SetTextColor", S.Color(spec.text)) end
    return button
end
function S.Button(parent, caption, width, height, onClick, kind)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    call(b, "SetSize", width, height or S.metrics.button)
    b.label = S.Text(b, "button")
    if b.label then
        call(b.label, "SetPoint", "CENTER", b, "CENTER", 0, 0)
        call(b.label, "SetJustifyH", "CENTER")
        call(b.label, "SetText", caption or "")
    end
    S.SetButtonKind(b, kind)
    call(b, "SetHighlightTexture", WHITE)
    local highlight = call(b, "GetHighlightTexture")
    if highlight then call(highlight, "SetVertexColor", 1, 1, 1, 0.07) end
    if onClick then call(b, "SetScript", "OnClick", onClick) end
    call(b, "SetScript", "OnDisable", function(self) call(self, "SetAlpha", 0.42) end)
    call(b, "SetScript", "OnEnable", function(self) call(self, "SetAlpha", 1) end)
    -- Blizzard buttons expose SetText/GetText; keep that contract for callers.
    b.SetText = function(self, value) if self.label then call(self.label, "SetText", value) end end
    b.GetText = function(self) return self.label and call(self.label, "GetText") or nil end
    return b
end
function S.CloseButton(parent, onClick)
    local b = S.Button(parent, "×", 22, 22, onClick, "quiet")
    if b.label then S.SetType(b.label, "title", "muted") end
    return b
end

-- Title strip: name on the left, close on the right, the strip is the drag
-- handle. Returns the bar; bar.title, bar.close and bar.handle are exposed.
function S.TitleBar(frame, title, onClose)
    local m = S.metrics
    local bar = CreateFrame("Frame", nil, frame)
    call(bar, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 0, 0)
    call(bar, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    call(bar, "SetHeight", m.title)
    bar.title = S.Text(bar, "title", nil, title)
    if bar.title then call(bar.title, "SetPoint", "LEFT", bar, "LEFT", m.pad, 0) end
    bar.close = S.CloseButton(bar, onClose or function() call(frame, "Hide") end)
    call(bar.close, "SetPoint", "RIGHT", bar, "RIGHT", -5, 0)
    bar.rule = S.Rule(bar)
    if bar.rule then
        call(bar.rule, "SetPoint", "BOTTOMLEFT", bar, "BOTTOMLEFT", 1, 0)
        call(bar.rule, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    end
    bar.handle = CreateFrame("Frame", nil, bar)
    call(bar.handle, "SetPoint", "TOPLEFT", bar, "TOPLEFT", 0, 0)
    call(bar.handle, "SetPoint", "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -30, 0)
    return bar
end

-- Dark input surface behind a plain EditBox.
function S.Input(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    call(holder, "SetSize", width, height or 26)
    S.Surface(holder, "surface")
    local box = CreateFrame("EditBox", nil, holder)
    call(box, "SetPoint", "TOPLEFT", holder, "TOPLEFT", 8, 0)
    call(box, "SetPoint", "BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 0)
    call(box, "SetFontObject", "GameFontHighlightSmall")
    local face = call(box, "GetFont")
    if type(face) == "string" and face ~= "" then call(box, "SetFont", face, S.type.body[1], "") end
    call(box, "SetTextColor", S.Color("text"))
    call(box, "SetAutoFocus", false)
    call(box, "SetScript", "OnEscapePressed", function(self) call(self, "ClearFocus") end)
    call(box, "SetScript", "OnEditFocusGained", function() call(holder, "SetBackdropBorderColor", S.Color("accent")) end)
    call(box, "SetScript", "OnEditFocusLost", function() call(holder, "SetBackdropBorderColor", S.Color("line")) end)
    box.holder = holder
    return box, holder
end
