-- Offline layout mock of the WoW widget API for UI previews.
-- It resolves anchors, sizes, scales, visibility and colors so real addon UI
-- code can be drawn outside the game. It is NOT the game client: font metrics,
-- Blizzard template art and textures are approximations. See README.md.
local M = { frames = {}, seq = 0, unknown = {}, timers = {}, now = 1000 }

local FONT = {
    GameFontNormal = { 14, { 1, 0.82, 0 } }, GameFontNormalSmall = { 12, { 1, 0.82, 0 } },
    GameFontNormalLarge = { 17, { 1, 0.82, 0 } }, GameFontNormalHuge = { 22, { 1, 0.82, 0 } },
    GameFontHighlight = { 14, { 1, 1, 1 } }, GameFontHighlightSmall = { 12, { 1, 1, 1 } },
    GameFontHighlightLarge = { 17, { 1, 1, 1 } }, GameFontHighlightHuge = { 22, { 1, 1, 1 } },
    GameFontDisable = { 14, { 0.5, 0.5, 0.5 } }, GameFontDisableSmall = { 12, { 0.5, 0.5, 0.5 } },
    GameFontDisableLarge = { 17, { 0.5, 0.5, 0.5 } },
    GameFontWhite = { 14, { 1, 1, 1 } }, GameFontWhiteSmall = { 12, { 1, 1, 1 } },
    GameFontGreen = { 14, { 0.1, 1, 0.1 } }, GameFontRed = { 14, { 1, 0.1, 0.1 } },
    GameTooltipText = { 13, { 1, 1, 1 } }, ChatFontNormal = { 14, { 1, 1, 1 } }, ChatFontSmall = { 12, { 1, 1, 1 } },
    NumberFontNormal = { 13, { 1, 1, 1 } }, NumberFontNormalSmall = { 11, { 1, 1, 1 } },
    SystemFont_Shadow_Small = { 12, { 1, 1, 1 } }, SystemFont_Shadow_Med1 = { 14, { 1, 1, 1 } },
}
M.FONT = FONT
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local FX = { LEFT = 0, TOPLEFT = 0, BOTTOMLEFT = 0, RIGHT = 1, TOPRIGHT = 1, BOTTOMRIGHT = 1, CENTER = 0.5, TOP = 0.5, BOTTOM = 0.5 }
local FY = { TOP = 1, TOPLEFT = 1, TOPRIGHT = 1, BOTTOM = 0, BOTTOMLEFT = 0, BOTTOMRIGHT = 0, CENTER = 0.5, LEFT = 0.5, RIGHT = 0.5 }

local methods = {}
local VERBS = { "Set", "Enable", "Disable", "Register", "Unregister", "Clear", "Hook", "Raise", "Lower", "Start", "Stop",
    "Play", "Pause", "Finish", "Add", "Remove", "Reset", "Apply", "Update", "Lock", "Unlock", "Insert", "Highlight",
    "Toggle", "Release", "Refresh", "Mark" }
local function fallback(_, key)
    local m = methods[key]
    if m then return m end
    if type(key) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
        if key:sub(1, #verb) == verb and (#key == #verb or key:sub(#verb + 1, #verb + 1):match("%u")) then
            M.unknown[key] = true
            return function() end
        end
    end
    if key:match("^Get%u") or key:match("^Is%u") or key:match("^Has%u") or key:match("^Can%u") then
        M.unknown[key] = true
        return function() return nil end
    end
    return nil
end
local META = { __index = fallback }

local function new(kind, name, parent)
    M.seq = M.seq + 1
    local o = setmetatable({ kind = kind, name = name, parent = parent, seq = M.seq, points = {}, shown = true,
        alpha = 1, scale = 1, scripts = {}, children = {}, regions = {}, enabled = true, attributes = {} }, META)
    if name and name ~= "" then _G[name] = o end
    return o
end

-- ---------------------------------------------------------------- text
local function plain(text)
    text = tostring(text or "")
    text = text:gsub("||", "\1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
    text = text:gsub("|T.-|t", "\2"):gsub("|A.-|a", "\2")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    return (text:gsub("\1", "|"))
end
M.plain = plain
local function lineWidth(line, size)
    local w, i, n = 0, 1, #line
    while i <= n do
        local c = line:byte(i)
        if c == 2 then w = w + size; i = i + 1
        elseif c < 128 then
            w = w + size * ((c == 32 and 0.3) or (c >= 48 and c <= 57 and 0.56) or (c >= 65 and c <= 90 and 0.66) or 0.52)
            i = i + 1
        elseif c < 224 then w = w + size * 0.6; i = i + 2
        elseif c < 240 then w = w + size; i = i + 3
        else w = w + size; i = i + 4 end
    end
    return w
end
local function measure(self, limit)
    local size = self.fontSize or 14
    local spacing = self.spacing or 0
    local widest, lines = 0, 0
    for line in (plain(self.text) .. "\n"):gmatch("(.-)\n") do
        local w = lineWidth(line, size)
        if w > widest then widest = w end
        if limit and limit > 0 and self.wordWrap ~= false then lines = lines + math.max(1, math.ceil(w / limit - 0.001))
        else lines = lines + 1 end
    end
    if self.maxLines and self.maxLines > 0 and lines > self.maxLines then lines = self.maxLines end
    return widest, lines * size * 1.3 + math.max(0, lines - 1) * spacing, lines
end

-- ---------------------------------------------------------------- geometry
local function owner(self) return (self.kind == "Texture" or self.kind == "FontString") and self.parent or self end
local function effScale(self)
    local f, s = owner(self), 1
    while f do s = s * (f.scale or 1); f = f.parent end
    return s
end
M.effScale = effScale
local function rect(self)
    if self.isScreen then return { l = 0, b = 0, r = self.width, t = self.height } end
    if self.resolving then return nil end
    self.resolving = true
    local es = effScale(self)
    local hx, vy = {}, {}
    if self.scrollOwner then
        local pr = rect(self.scrollOwner)
        if pr then
            local so = self.scrollOwner
            local ses = effScale(so)
            hx[0] = pr.l - (so.hscroll or 0) * ses
            vy[1] = pr.t + (so.vscroll or 0) * ses
        end
    else
        for _, p in ipairs(self.points) do
            local target = p.relativeTo
            if type(target) == "string" then target = _G[target] end
            if target == nil then target = (self.kind == "Texture" or self.kind == "FontString") and self.parent or (self.parent or M.screen) end
            local tr = rect(target)
            if tr then
                local rp = p.relativePoint or p.point
                local ax = tr.l + (tr.r - tr.l) * (FX[rp] or 0.5)
                local ay = tr.b + (tr.t - tr.b) * (FY[rp] or 0.5)
                local fx, fy = FX[p.point] or 0.5, FY[p.point] or 0.5
                hx[fx] = ax + (p.x or 0) * es
                vy[fy] = ay + (p.y or 0) * es
            end
        end
    end
    local out = {}
    local w = self.width and self.width > 0 and self.width * es or nil
    if hx[0] and hx[1] then out.l, out.r = hx[0], hx[1]
    else
        if not w and self.kind == "FontString" then w = measure(self) * es end
        w = w or 0
        if hx[0] then out.l, out.r = hx[0], hx[0] + w
        elseif hx[1] then out.l, out.r = hx[1] - w, hx[1]
        elseif hx[0.5] then out.l, out.r = hx[0.5] - w / 2, hx[0.5] + w / 2 end
    end
    local h = self.height and self.height > 0 and self.height * es or nil
    if vy[0] and vy[1] then out.b, out.t = vy[0], vy[1]
    else
        if not h and self.kind == "FontString" and out.l then
            local _, th = measure(self, (out.r - out.l) / es)
            h = th * es
        end
        h = h or 0
        if vy[1] then out.t, out.b = vy[1], vy[1] - h
        elseif vy[0] then out.b, out.t = vy[0], vy[0] + h
        elseif vy[0.5] then out.b, out.t = vy[0.5] - h / 2, vy[0.5] + h / 2 end
    end
    self.resolving = nil
    if not out.l or not out.b then return nil end
    return out
end
M.rect = rect

function methods:SetPoint(point, a, b, c, d)
    local p = { point = point }
    if type(a) == "number" then p.x, p.y = a, b
    else
        p.relativeTo = a
        if type(b) == "number" then p.x, p.y = b, c else p.relativePoint, p.x, p.y = b, c, d end
    end
    for i, existing in ipairs(self.points) do
        if existing.point == point then self.points[i] = p; return end
    end
    self.points[#self.points + 1] = p
end
function methods:ClearAllPoints() self.points = {} end
function methods:SetAllPoints(target)
    self.points = { { point = "TOPLEFT", relativeTo = target, relativePoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", relativeTo = target, relativePoint = "BOTTOMRIGHT", x = 0, y = 0 } }
end
function methods:GetPoint(index)
    local p = self.points[index or 1]
    if not p then return nil end
    local target = p.relativeTo
    if target == nil then target = self.parent or M.screen end
    return p.point, target, p.relativePoint or p.point, p.x or 0, p.y or 0
end
function methods:GetNumPoints() return #self.points end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
local function derived(self, horizontal)
    local r = rect(self)
    if not r then return 0 end
    return (horizontal and (r.r - r.l) or (r.t - r.b)) / effScale(self)
end
function methods:GetWidth() if self.width and self.width > 0 then return self.width end return derived(self, true) end
function methods:GetHeight() if self.height and self.height > 0 then return self.height end return derived(self, false) end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
local function edge(self, key) local r = rect(self); return r and r[key] / effScale(self) or nil end
function methods:GetLeft() return edge(self, "l") end
function methods:GetRight() return edge(self, "r") end
function methods:GetTop() return edge(self, "t") end
function methods:GetBottom() return edge(self, "b") end
function methods:GetCenter()
    local r = rect(self); if not r then return nil end
    local s = effScale(self); return (r.l + r.r) / 2 / s, (r.b + r.t) / 2 / s
end
function methods:GetRect()
    local r = rect(self); if not r then return nil end
    local s = effScale(self); return r.l / s, r.b / s, (r.r - r.l) / s, (r.t - r.b) / s
end
function methods:SetScale(v) self.scale = v end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return effScale(self) end
function methods:SetAlpha(v) self.alpha = v end
function methods:GetAlpha() return self.alpha end
function methods:GetEffectiveAlpha() local a, f = 1, self; while f do a = a * (f.alpha or 1); f = f.parent end return a end

-- ---------------------------------------------------------------- common
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:SetParent(p) self.parent = p end
function methods:GetObjectType() return self.kind end
function methods:IsObjectType(kind) return self.kind == kind or (kind == "Frame" and self.kind ~= "Texture" and self.kind ~= "FontString") end
function methods:Show()
    if self.shown then return end
    self.shown = true
    if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() local f = self; while f do if not f.shown then return false end f = f.parent end return true end
function methods:IsMouseOver() return false end
function methods:IsForbidden() return false end
function methods:IsProtected() return false end
function methods:SetScript(k, fn) self.scripts[k] = fn end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k, fn)
    local old = self.scripts[k]
    self.scripts[k] = old and function(...) old(...); fn(...) end or fn
end
function methods:HasScript() return true end
function methods:RegisterEvent(e) self.events = self.events or {}; self.events[e] = true end
function methods:UnregisterEvent(e) if self.events then self.events[e] = nil end end
function methods:IsEventRegistered(e) return self.events and self.events[e] or false end
function methods:SetAttribute(k, v) self.attributes[k] = v end
function methods:GetAttribute(k) return self.attributes[k] end
function methods:SetFrameStrata(v) self.strata = v end
function methods:GetFrameStrata() local f = self; while f do if f.strata then return f.strata end f = f.parent end return "MEDIUM" end
function methods:SetFrameLevel(v) self.level = v end
function methods:GetFrameLevel() if self.level then return self.level end return self.parent and self.parent.GetFrameLevel and self.parent:GetFrameLevel() + 1 or 1 end
function methods:SetID(v) self.id = v end
function methods:GetID() return self.id or 0 end
function methods:EnableMouse(v) self.mouse = v end
function methods:IsMouseEnabled() return self.mouse and true or false end
function methods:SetMovable(v) self.movable = v end
function methods:IsMovable() return self.movable end
function methods:SetResizable(v) self.resizable = v end
function methods:SetClipsChildren(v) self.clips = v end
function methods:StartMoving() end
function methods:StartSizing() end
function methods:StopMovingOrSizing() end
function methods:GetChildren() return unpack(self.children) end
function methods:GetNumChildren() return #self.children end
function methods:GetRegions() return unpack(self.regions) end
function methods:GetNumRegions() return #self.regions end
function methods:SetEnabled(v) self.enabled = v and true or false
    local s = self.scripts[self.enabled and "OnEnable" or "OnDisable"]; if s then s(self) end end
function methods:Enable() self:SetEnabled(true) end
function methods:Disable() self:SetEnabled(false) end
function methods:IsEnabled() return self.enabled end
function methods:Click(button)
    if self.enabled and self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton", false) end
end
function methods:SetBackdrop(b) self.backdrop = b end
function methods:GetBackdrop() return self.backdrop end
function methods:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a or 1 } end
function methods:GetBackdropColor() return unpack(self.backdropColor or { 1, 1, 1, 1 }) end
function methods:SetBackdropBorderColor(r, g, b, a) self.backdropBorderColor = { r, g, b, a or 1 } end
function methods:GetBackdropBorderColor() return unpack(self.backdropBorderColor or { 1, 1, 1, 1 }) end

local function region(self, kind, name, layer, sub)
    local r = new(kind, name, self)
    r.layer = layer or (kind == "FontString" and "ARTWORK" or "ARTWORK")
    r.sub = sub or 0
    self.regions[#self.regions + 1] = r
    return r
end
function methods:CreateTexture(name, layer, _, sub) return region(self, "Texture", name, layer, sub) end
function methods:CreateFontString(name, layer, template)
    local r = region(self, "FontString", name, layer)
    r.text = ""
    r:SetFontObject(template or "GameFontNormal")
    return r
end
function methods:CreateAnimationGroup()
    local group = setmetatable({ kind = "AnimationGroup", scripts = {} }, META)
    return group
end
function methods:CreateAnimation() return setmetatable({ kind = "Animation", scripts = {} }, META) end
function methods:IsPlaying() return false end
function methods:SetDrawLayer(layer, sub) self.layer = layer; self.sub = sub or 0 end
function methods:GetDrawLayer() return self.layer, self.sub end

-- ---------------------------------------------------------------- texture
function methods:SetTexture(a, b, c, d)
    if type(a) == "number" and b then self.color = { a, b, c, d or 1 }; self.file = nil
    else self.file = a; self.color = nil end
end
function methods:GetTexture() return self.file end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a or 1 }; self.file = nil end
function methods:SetAtlas(a) self.file = "atlas:" .. tostring(a) end
function methods:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a or 1 } end
function methods:GetVertexColor() return unpack(self.vertex or { 1, 1, 1, 1 }) end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:SetRotation(v) self.rotation = v end
function methods:SetDesaturated(v) self.desaturated = v end
function methods:SetGradient(orientation, a, b) self.gradient = { orientation, a, b } end

-- ---------------------------------------------------------------- font string
function methods:SetFontObject(obj)
    local name = type(obj) == "table" and obj.fontName or obj
    local spec = FONT[name] or FONT.GameFontNormal
    self.fontName = name
    self.fontSize = spec[1]
    if self.kind == "FontString" or self.kind == "EditBox" then self.textColor = self.textColor or { spec[2][1], spec[2][2], spec[2][3], 1 } end
    self.template = name
end
function methods:GetFontObject() return _G[self.fontName or "GameFontNormal"] end
function methods:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size or self.fontSize, flags; return true end
function methods:GetFont() return self.fontPath or "Fonts\\ARKai_T.ttf", self.fontSize or 14, self.fontFlags or "" end
function methods:SetText(text)
    if self.kind == "FontString" or self.kind == "EditBox" then
        self.text = text == nil and "" or tostring(text)
        if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
        return
    end
    if not self.fontString then
        self.fontString = self:CreateFontString(nil, "OVERLAY", self.normalFont or "GameFontNormal")
        self.fontString:SetPoint("CENTER", self, "CENTER", 0, 0)
        self.fontString.justifyH = "CENTER"
    end
    self.fontString:SetText(text)
end
function methods:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function methods:GetText()
    if self.kind == "FontString" or self.kind == "EditBox" then return self.text or "" end
    return self.fontString and self.fontString.text or nil
end
function methods:GetFontString() if not self.fontString then self:SetText("") end return self.fontString end
function methods:SetNormalFontObject(obj) self.normalFont = type(obj) == "table" and obj.fontName or obj
    if self.fontString then self.fontString:SetFontObject(self.normalFont) end end
function methods:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function methods:GetTextColor() return unpack(self.textColor or { 1, 1, 1, 1 }) end
function methods:SetJustifyH(v) self.justifyH = v end
function methods:GetJustifyH() return self.justifyH or "CENTER" end
function methods:SetJustifyV(v) self.justifyV = v end
function methods:SetWordWrap(v) self.wordWrap = v end
function methods:SetNonSpaceWrap() end
function methods:SetSpacing(v) self.spacing = v end
function methods:GetSpacing() return self.spacing or 0 end
function methods:SetMaxLines(v) self.maxLines = v end
function methods:GetStringWidth() local w = measure(self); if self.width and self.width > 0 then return math.min(w, self.width) end return w end
function methods:GetUnboundedStringWidth() return (measure(self)) end
function methods:GetWrappedWidth() return self:GetStringWidth() end
function methods:GetStringHeight() local _, h = measure(self, self:GetWidth()); return h end
function methods:GetNumLines() local _, _, n = measure(self, self:GetWidth()); return n end
function methods:GetLineHeight() return (self.fontSize or 14) * 1.3 end
function methods:IsTruncated() return false end
function methods:CanWordWrap() return self.wordWrap ~= false end

-- ---------------------------------------------------------------- buttons
local function slot(key)
    return function(self, file)
        local t = self[key]
        if not t then t = region(self, "Texture", nil, key == "highlightTexture" and "HIGHLIGHT" or "BACKGROUND"); t:SetAllPoints(self); self[key] = t end
        if type(file) == "table" then self[key] = file else t.file = file end
    end
end
methods.SetNormalTexture, methods.SetPushedTexture = slot("normalTexture"), slot("pushedTexture")
methods.SetHighlightTexture, methods.SetDisabledTexture = slot("highlightTexture"), slot("disabledTexture")
methods.SetCheckedTexture = slot("checkedTexture")
function methods:GetNormalTexture() return self.normalTexture end
function methods:GetPushedTexture() if not self.pushedTexture then self:SetPushedTexture(nil) end self.pushedTexture.shown = false return self.pushedTexture end
function methods:GetHighlightTexture() return self.highlightTexture end
function methods:GetDisabledTexture() return self.disabledTexture end
function methods:GetCheckedTexture() return self.checkedTexture end
function methods:SetChecked(v) self.checked = v and true or false end
function methods:GetChecked() return self.checked or false end
function methods:RegisterForClicks() end
function methods:RegisterForDrag() end
function methods:GetButtonState() return "NORMAL" end
function methods:LockHighlight() end
function methods:UnlockHighlight() end

-- ---------------------------------------------------------------- edit box / scroll / bars
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HasFocus() return self.focused or false end
function methods:SetMultiLine(v) self.multiLine = v end
function methods:IsMultiLine() return self.multiLine end
function methods:GetNumLetters() return #(self.text or "") end
function methods:GetCursorPosition() return #(self.text or "") end
function methods:GetNumber() return tonumber(self.text) or 0 end
function methods:SetNumber(v) self:SetText(tostring(v)) end
function methods:Insert(text) self:SetText((self.text or "") .. tostring(text)) end
function methods:SetTextInsets(l, r, t, b) self.insets = { l, r, t, b } end
function methods:GetTextInsets() return unpack(self.insets or { 0, 0, 0, 0 }) end
function methods:SetScrollChild(child)
    self.scrollChild = child
    child.scrollOwner = self
    if child.parent ~= self then
        child.parent = self
        self.children[#self.children + 1] = child
    end
end
function methods:GetScrollChild() return self.scrollChild end
function methods:SetVerticalScroll(v) self.vscroll = v end
function methods:GetVerticalScroll() return self.vscroll or 0 end
function methods:SetHorizontalScroll(v) self.hscroll = v end
function methods:GetHorizontalScroll() return self.hscroll or 0 end
function methods:GetVerticalScrollRange()
    local c = self.scrollChild
    if not c then return 0 end
    return math.max(0, c:GetHeight() - self:GetHeight())
end
function methods:GetHorizontalScrollRange() return 0 end
function methods:UpdateScrollChildRect() end
function methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function methods:GetMinMaxValues() return self.min or 0, self.max or 1 end
function methods:SetValue(v)
    local changed = self.value ~= v
    self.value = v
    if changed and self.kind == "Slider" and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
end
function methods:GetValue() return self.value or 0 end
function methods:SetValueStep(v) self.step = v end
function methods:GetValueStep() return self.step or 1 end
function methods:SetObeyStepOnDrag() end
function methods:SetOrientation(v) self.orientation = v end
function methods:GetOrientation() return self.orientation or "HORIZONTAL" end
function methods:SetStatusBarTexture(file)
    if not self.barTexture then self.barTexture = region(self, "Texture", nil, "ARTWORK"); self.barTexture.isBarFill = true end
    if type(file) == "table" then file.isBarFill = true; self.barTexture = file else self.barTexture.file = file end
end
function methods:GetStatusBarTexture() if not self.barTexture then self:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end return self.barTexture end
function methods:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a or 1 } end
function methods:GetStatusBarColor() return unpack(self.barColor or { 1, 1, 1, 1 }) end
function methods:SetThumbTexture(file)
    if not self.thumbTexture then self.thumbTexture = region(self, "Texture", nil, "OVERLAY"); self.thumbTexture.isThumb = true end
    if type(file) == "table" then file.isThumb = true; self.thumbTexture = file else self.thumbTexture.file = file end
end
function methods:GetThumbTexture() if not self.thumbTexture then self:SetThumbTexture("Interface\\Buttons\\WHITE8X8") end return self.thumbTexture end
-- tooltip-like
function methods:SetOwner() end
function methods:AddLine() end
function methods:AddDoubleLine() end
function methods:ClearLines() end
function methods:NumLines() return 0 end

-- ---------------------------------------------------------------- templates
local function applyTemplate(f, template)
    for name in tostring(template or ""):gmatch("[^,%s]+") do
        if name == "UIPanelButtonTemplate" or name == "UIPanelButtonNoTooltipTemplate" or name == "GameMenuButtonTemplate" then
            f.look = "blizzButton"; f.normalFont = "GameFontNormal"; f.width, f.height = 80, 22
        elseif name == "UIPanelCloseButton" or name == "UIPanelCloseButtonNoScripts" then
            f.look = "blizzClose"; f.width, f.height = 32, 32
            f.scripts.OnClick = function(self) if self.parent then self.parent:Hide() end end
        elseif name == "BasicFrameTemplateWithInset" or name == "BasicFrameTemplate" or name == "ButtonFrameTemplate" then
            f.look = "blizzFrame"
            f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.TitleText:SetPoint("TOP", f, "TOP", 0, -5)
            f.CloseButton = M.CreateFrame("Button", nil, f, "UIPanelCloseButton")
            f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 5)
            f.Inset = M.CreateFrame("Frame", nil, f)
            f.Inset:SetPoint("TOPLEFT", 4, -24); f.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
        elseif name == "InputBoxTemplate" or name == "SearchBoxTemplate" then
            f.look = "blizzInput"; f.fontSize = 14; f.textColor = { 1, 1, 1, 1 }
            if name == "SearchBoxTemplate" then f.Instructions = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall") end
        elseif name == "UIPanelScrollFrameTemplate" then
            f.ScrollBar = M.CreateFrame("Slider", nil, f)
            f.ScrollBar.look = "blizzScrollBar"
            f.ScrollBar:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, -16); f.ScrollBar:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 6, 16)
            f.ScrollBar:SetWidth(16)
        elseif name == "UICheckButtonTemplate" or name == "InterfaceOptionsCheckButtonTemplate" or name == "ChatConfigCheckButtonTemplate" then
            f.look = "blizzCheck"; f.width, f.height = 26, 26
            f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            f.Text:SetPoint("LEFT", f, "RIGHT", 2, 0); f.text = f.Text
        elseif name == "OptionsSliderTemplate" or name == "UISliderTemplate" or name == "UISliderTemplateWithLabels" then
            f.look = "blizzSlider"; f.width, f.height = 144, 17
            f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); f.Text:SetPoint("BOTTOM", f, "TOP", 0, 2)
            f.Low = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); f.Low:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -1)
            f.High = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"); f.High:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -1)
        elseif name == "UIDropDownMenuTemplate" then
            f.look = "blizzDropdown"; f.width, f.height = 150, 28
        end
    end
end

function M.CreateFrame(kind, name, parent, template)
    local f = new(kind or "Frame", name, parent)
    f.template = template
    if parent then parent.children[#parent.children + 1] = f end
    if kind == "EditBox" then f.text = ""; f.fontSize = 14; f.textColor = { 1, 1, 1, 1 } end
    if kind == "GameTooltip" then f.shown = false end
    applyTemplate(f, template)
    M.frames[#M.frames + 1] = f
    return f
end

-- ---------------------------------------------------------------- globals
function M.install(width, height)
    M.screen = new("Frame", "UIParent", nil)
    M.screen.isScreen, M.screen.width, M.screen.height = true, width, height
    _G.CreateFrame = M.CreateFrame
    _G.WorldFrame = M.screen
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.GameTooltip = M.CreateFrame("GameTooltip", "GameTooltip", M.screen)
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) M.chat = M.chat or {}; M.chat[#M.chat + 1] = text end }
    for name in pairs(FONT) do _G[name] = setmetatable({ fontName = name, kind = "Font", scripts = {} }, META) end
    _G.STANDARD_TEXT_FONT = "Fonts\\ARKai_T.ttf"
    _G.GetTime = function() return M.now end
    _G.GetScreenWidth = function() return width end
    _G.GetScreenHeight = function() return height end
    _G.GetCursorPosition = function() return 0, 0 end
    _G.InCombatLockdown = function() return false end
    _G.UnitAffectingCombat = function() return false end
    _G.IsShiftKeyDown = function() return false end
    _G.IsControlKeyDown = function() return false end
    _G.IsAltKeyDown = function() return false end
    _G.PlaySound = function() end
    _G.PlaySoundFile = function() end
    _G.hooksecurefunc = function() end
    _G.issecurevariable = function() return true end
    _G.geterrorhandler = function() return function(e) error(e, 0) end end
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.tinsert, _G.tremove, _G.tContains = table.insert, table.remove, function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
    _G.format, _G.strfind, _G.strsub, _G.strlen, _G.strlower, _G.strupper, _G.gsub, _G.strmatch, _G.strrep, _G.strtrim =
        string.format, string.find, string.sub, string.len, string.lower, string.upper, string.gsub, string.match, string.rep,
        function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    _G.floor, _G.ceil, _G.min, _G.max, _G.abs = math.floor, math.ceil, math.min, math.max, math.abs
    _G.strsplit = function(sep, text) local out = {}; for part in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end return unpack(out) end
    _G.time, _G.date = os.time, os.date
    _G.debugstack = function() return "" end
    _G.securecallfunction = function(fn, ...) return fn(...) end
    _G.C_Timer = {
        After = function(delay, fn) M.timers[#M.timers + 1] = { at = M.now + delay, fn = fn } end,
        NewTicker = function(interval, fn) local t = { cancelled = false }; function t:Cancel() self.cancelled = true end; function t:IsCancelled() return self.cancelled end; return t end,
        NewTimer = function(delay, fn) local t = { cancelled = false }; function t:Cancel() self.cancelled = true end; return t end,
    }
    return M.screen
end
function M.fire(event, ...)
    for _, f in ipairs(M.frames) do
        if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
function M.advance(seconds)
    M.now = M.now + seconds
    local due = M.timers; M.timers = {}
    for _, t in ipairs(due) do if t.at <= M.now then t.fn() else M.timers[#M.timers + 1] = t end end
end

M.STRATA, M.LAYER, M.measure = STRATA, LAYER, measure
return M
