-- Behavioral UI checks in a Lua 5.1 frame sandbox; these are not game screenshots.
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, needle, message)
    checks = checks + 1
    assert(type(value) == "string" and value:find(needle, 1, true), message)
end
local function near(actual, expected, message)
    checks = checks + 1
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.0001,
        message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function screenTopLeft(object)
    local scale = object:GetEffectiveScale()
    return object:GetLeft() * scale, object:GetTop() * scale
end

local methods = {}
local function frame(kind, name, parent)
    local created = setmetatable({ kind = kind, name = name, parent = parent, children = {}, scripts = {}, shown = true, width = 0, height = 0, scroll = 0, value = 0, fontSize = 12 }, { __index = methods })
    if parent then parent.children[#parent.children + 1] = created end
    if name then _G[name] = created end
    return created
end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if relative == nil or type(relative) == "number" then
        x, y, relative, relativePoint = relative or 0, relativePoint or 0, self.parent or UIParent, point
    elseif type(relativePoint) == "number" then
        x, y, relativePoint = relativePoint, x or 0, point
    end
    self.point = { point, relative, relativePoint or point, x or 0, y or 0 }
end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 300, 0 }) end
function methods:ClearAllPoints() self.point = nil end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetAllPoints() end
function methods:SetText(value) self.text = value end
function methods:GetFont() return "mock-font", self.fontSize end
function methods:SetFont(_, size) self.fontSize = size end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:GetStringHeight()
    local plain = (self.text or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local lines = 0
    for line in (plain .. "\n"):gmatch("(.-)\n") do
        local length = 0
        for byte in line:gmatch(".") do
            local code = byte:byte()
            if code < 128 then length = length + self.fontSize * 0.55
            elseif code >= 192 then length = length + self.fontSize end
        end
        lines = lines + math.max(1, math.ceil(length / math.max(1, self.width)))
    end
    return lines * self.fontSize + math.max(0, lines - 1) * (self.spacing or 0)
end
function methods:CreateFontString(_, _, template)
    local label = frame("FontString", nil, self)
    if template == "GameFontNormal" or template == "GameFontHighlight" then label.fontSize = 14 end
    return label
end
function methods:CreateTexture() return frame("Texture", nil, self) end
function methods:SetHighlightTexture() self.highlight = frame("Texture", nil, self) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetThumbTexture() self.thumb = frame("Texture", nil, self) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll end
function methods:SetScrollChild(child) self.child = child end
function methods:SetMinMaxValues(min, max) self.min, self.max = min, max end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:Show() self.shown = true end
local function ancestorHidden(self)
    if not self.shown then return end
    if self.scripts.OnHide then self.scripts.OnHide(self) end
    for _, child in ipairs(self.children) do ancestorHidden(child) end
end
function methods:Hide()
    if not self.shown then return end
    local visible = self:IsVisible()
    self.shown = false
    if visible then
        if self.scripts.OnHide then self.scripts.OnHide(self) end
        for _, child in ipairs(self.children) do ancestorHidden(child) end
    end
end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1) end
local function anchorFraction(point, low, high)
    if point:find(low, 1, true) then return 0 end
    if point:find(high, 1, true) then return 1 end
    return 0.5
end
local function leftBottom(self)
    if self == UIParent then return 0, 0 end
    local point, relative, relativePoint, x, y = self:GetPoint()
    local relativeLeft, relativeBottom = leftBottom(relative)
    local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
    return (relativeLeft + relative.width * anchorFraction(relativePoint, "LEFT", "RIGHT")) * ratio
            + x - self.width * anchorFraction(point, "LEFT", "RIGHT"),
        (relativeBottom + relative.height * anchorFraction(relativePoint, "BOTTOM", "TOP")) * ratio
            + y - self.height * anchorFraction(point, "BOTTOM", "TOP")
end
function methods:GetLeft() local left = leftBottom(self); return left end
function methods:GetBottom() local _, bottom = leftBottom(self); return bottom end
function methods:GetTop() return self:GetBottom() + self.height end
function methods:GetRight() return self:GetLeft() + self.width end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:SetSpacing(value) self.spacing = value end
function methods:SetTextColor(...) self.textColor = {...} end
function methods:SetColorTexture(...) self.colorTexture = {...} end
function methods:SetNormalTexture(value) self.normalTexture = value end
function methods:EnableKeyboard() error("profession panel must not capture the keyboard") end
for _, method in ipairs({ "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetVertexColor", "SetTexture", "SetMovable", "EnableMouseWheel", "SetFrameStrata", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "RegisterForDrag", "SetOrientation", "SetValueStep" }) do
    methods[method] = function() end
end
UIParent = frame("Frame")
UIParent:SetSize(1920, 1080)
UISpecialFrames = { "UnrelatedExistingPanel" }
CreateFrame = frame
local ctrl = false
IsControlKeyDown = function() return ctrl end
local leftMouseDown = true
local cursorX, cursorY = 700, 400
GetCursorPosition = function() return cursorX, cursorY end
IsMouseButtonDown = function(mouseButton) return mouseButton == "LeftButton" and leftMouseDown end
local opened, refreshed, itemRef, inserted, shift = nil, nil, nil, nil, false
local gatherAction
local activeEdit, mapped
GetCurrentKeyBoardFocus = function() return activeEdit end
C_Item = { GetItemInfo = function(id)
    if id == 1 then return "宁神花", "|cffffffff|Hitem:1::::::::|h[宁神花]|h|r" end
end }
IsShiftKeyDown = function() return shift end
ChatEdit_GetActiveWindow = function() return activeEdit end
ChatEdit_InsertLink = function(link) inserted = link end
SetItemRef = function(payload, link, mouseButton) itemRef = {payload, link, mouseButton} end
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, owner) return self.owner == owner end,
    SetHyperlink = function(self, link) self.link = link end,
    SetText = function(self, value) self.title = value; self.lines = {} end,
    AddLine = function(self, value) self.lines = self.lines or {}; self.lines[#self.lines + 1] = value end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false; self.owner = nil end,
}
local ns = {
    db = { shown = true, locked = false, scale = 1, point = "CENTER", relativePoint = "CENTER", x = 300, y = 0,
        gatherAlerts = false, gatherSound = true, gatherSparkles = false },
    professions = {}, detectReady = false,
    OpenProfession = function(id) opened = id end,
    Refresh = function(force) refreshed = force end,
    GatherCommand = function(action) gatherAction = action end,
    Progress = function(p) return { text = p.rank .. "/" .. p.maxRank .. " · 距上限 " .. (p.maxRank - p.rank) .. " 点", nextPoint = p.rank < p.maxRank and p.rank + 1 or nil } end,
    GatheringAdvice = function() return "资源颜色以游戏显示为准。" end,
    GetNearbyTrainer = function() return {name="训练师示例",mapName="丹莫罗",mapID=1426,x=0.4767,y=0.5231,distance=80} end,
    ShowTrainerOnMap = function(record, useIcon) mapped = record; mapped.useIcon = useIcon end,
}
local core = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/Core.lua"))("MyForeverProfessions", core)
ns.PanelSize = core.PanelSize
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/ItemLinks.lua"))("MyForeverProfessions", ns)
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/UI.lua"))("MyForeverProfessions", ns)
local panel = ns.CreateUI()
eq(ns.frame, panel, "expose root frame")
eq(ns.CreateUI(), panel, "creation is idempotent")
eq(panel.shown, true, "visible by default")
eq(panel.clamped, true, "panel stays on screen")
eq(panel.controls.open.enabled, false, "fixed skill-book button starts disabled without an explicit profession selection")
eq(panel.controls.open.label.text, "打开技能书", "fixed skill-book button keeps the requested caption")
contains(panel.summary.text, "先点击一个专业", "initial toolbar explains why no profession can open")
panel.controls.open.scripts.OnClick(panel.controls.open)
eq(opened, nil, "initial fixed action does not silently choose a profession")
panel.controls.open.scripts.OnEnter(panel.controls.open)
contains(table.concat(GameTooltip.lines, " "), "先点击一个专业标题", "disabled skill-book tooltip explains the initial selection requirement")
contains(panel.content.empty.text, "正在读取", "loading differs from unlearned")
ns.detectReady = true
ns.RenderUI()
contains(panel.content.empty.text, "尚未学习", "unlearned state")
panel.controls.refresh.scripts.OnClick()
eq(refreshed, true, "refresh requests forced scan")
panel.controls.gather.scripts.OnClick()
eq(gatherAction, "move", "header opens gather alert adjustment")

ns.professions = {
    { id = 171, name = "炼金术", rank = 45, maxRank = 75, cacheState = "fresh", kind = "crafting", recipes = {
        { id = 1, name = "初级治疗药水", difficulty = "orange", craftable = 2, reagentsComplete = true, reagents = { { name = "宁神花", itemID = 1, required = 2, owned = 5, missing = 0 } } },
        { id = 2, name = "次级药剂", difficulty = "yellow", craftable = 0, reagentsComplete = true, reagents = { { name = "银叶草", required = 3, owned = 1, missing = 2 } } },
    } },
    { id = 182, name = "草药学", rank = 10, maxRank = 75, kind = "gathering", cacheState = "fresh", recipes = {
        { id = 3, name = "宁神花", difficulty = "orange", isGatheringRecipe = true, craftable = 9, currentRecipeExperience = 2, nextLevelRecipeExperience = 5, reagents = {} },
    } },
}
ns.RenderUI()
eq(panel.content.empty.shown, false, "hide empty state when professions are known")
eq(panel.cards[1].details.shown, false, "initial profession details collapsed")
eq(panel.cards[1].header.rank.text, "45 / 75", "real skill ratio in header")
eq(math.abs(panel.cards[1].header.fill.width - 328 * 45 / 75) < 0.0001, true, "fill width follows actual skill ratio")
panel.cards[1].header.scripts.OnClick()
eq(opened, nil, "header does not open native profession")
eq(panel.cards[1].details.shown, true, "first profession expands")
eq(panel.cards[1].progress.shown, false, "duplicate progress removed from details")
eq(panel.cards[1].materialTitle.shown, false, "redundant material heading removed")
contains(panel.cards[1].trainer.label.text, "丹莫罗 47.7, 52.3", "trainer location displayed")
panel.cards[1].trainer.scripts.OnClick()
eq(mapped.mapID, 1426, "trainer button passes correct map record")
eq(mapped.useIcon, nil, "missing pin library retains native map fallback")
local pins, mapOpen, opens, clears = true, false, 0, 0
ns.HasTrainerPin = function(id) return pins and (id == 171 or id == 182) end
ns.IsTrainerPinVisible = function(id) return mapOpen and ns.HasTrainerPin(id) end
ns.ClearTrainerPins = function() pins = false; clears = clears + 1 end
ns.UpdateTrainerPins = function() pins = true end
ns.ShowTrainerOnMap = function(record, useIcon)
    mapped = record
    mapped.useIcon = useIcon
    mapOpen, opens = true, opens + 1
    return true, useIcon and "icons" or "map"
end
local findTrainer = panel.cards[1].trainer.scripts.OnClick
findTrainer()
eq(mapped.useIcon, true, "visible profession icon avoids overlapping waypoint")
findTrainer()
eq(clears, 1, "second lookup clears trainer icons")
eq(opens, 1, "second lookup leaves the map open")
ns.RenderUI()
eq(pins, false, "periodic rendering does not restore hidden trainer icons")
findTrainer()
eq(pins, true, "third lookup restores trainer icons")
eq(opens, 2, "third lookup returns to the trainer map")
mapOpen = false
findTrainer()
eq(opens, 3, "lookup reopens a closed map")
panel.cards[2].header.scripts.OnClick()
panel.cards[2].trainer.scripts.OnClick()
eq(opens, 4, "another profession retargets the map")
eq(clears, 1, "changing profession does not hide icons")
panel.cards[1].header.scripts.OnClick()
ns.HasTrainerPin, ns.IsTrainerPinVisible, ns.UpdateTrainerPins, ns.ClearTrainerPins = nil, nil, nil, nil
contains(panel.cards[1].materialRows[1].counts.text, "需 2 / 有 5", "show needs and owned")
panel.controls.open.scripts.OnClick(panel.controls.open)
eq(opened, 171, "separate open button opens correct skill")
local material = panel.cards[1].materialRows[1]
contains(material.label.text, "|Hitem:1:", "cached material uses complete item hyperlink")
eq(material.mouse, true, "link row accepts clicks")
material.scripts.OnEnter(material)
eq(GameTooltip.link, material.itemLink, "hover opens native item tooltip")
ns.RenderUI()
eq(GameTooltip.shown, true, "periodic render preserves current material tooltip")
material.scripts.OnClick(material, "LeftButton")
eq(itemRef[1], "item:1::::::::", "click passes raw item payload")
eq(itemRef[2], material.itemLink, "click also passes full colored link")
shift = true
material.scripts.OnClick(material, "LeftButton")
eq(inserted, nil, "shift with no active edit box does not open or send chat")
activeEdit = {IsObjectType=function(_,kind) return kind=="EditBox" end, IsShown=function() return true end,
    IsVisible=function() return true end, HasFocus=function() return true end, Insert=function(_,value) inserted=value end}
material.scripts.OnClick(material, "LeftButton")
eq(inserted, material.itemLink, "shift inserts full link into existing edit box")
shift, activeEdit = false, nil
local second = panel.cards[1].choices[2]
second.scripts.OnClick(second)
contains(panel.cards[1].materialRows[1].label.text, "银叶草", "select alternative materials")
eq(GameTooltip.shown, false, "changing hovered row to unknown ID hides stale tooltip")
eq(panel.cards[1].materialRows[1].mouse, false, "unknown item ID remains plain text")
contains(panel.cards[1].materialRows[1].counts.text, "缺 2", "show shortage")
eq(panel.cards[1].choices[3].shown, false, "hide unused candidates")
panel.cards[2].header.scripts.OnClick()
eq(panel.cards[1].details.shown, false, "expanding another profession collapses first")
eq(panel.cards[2].details.shown, true, "second profession expands")
eq(panel.cards[1].header.shown, true, "collapsed profession keeps header visible")
eq(panel.cards[2].materialTitle.shown, false, "gathering also avoids redundant heading")
contains(panel.cards[2].materials.text, "还差 3 熟练度", "native recipe experience")
eq(panel.cards[2].choices[1].label.text:find("可做", 1, true), nil, "gathering no fake craft count")
ns.combatPaused = true
ns.RenderUI()
eq(panel.summary.text, "战斗中 · 数据暂停", "combat explains paused data")
eq(panel.cards[1].shown, true, "combat preserves profession cards")
ns.combatPaused = false
ns.professions[2].cacheState = "missing"
ns.RenderUI()
contains(panel.cards[2].note.text, "首次使用请打开", "gathering also needs initial reading")
ns.professions[2].cacheState = "fresh"

panel.cards[1].header.scripts.OnClick()
ns.professions[1].cacheState = "stale"
ns.RenderUI()
eq(panel.cards[1].note.shown, false, "stale prose removed from main panel")
eq(panel.cards[1].choices[1].label.text:find("上次", 1, true), nil, "cached color label removed")
eq(panel.cards[1].choices[1].label.text:find("[橙]", 1, true), nil, "text difficulty label removed")
panel.cards[1].choices[1].scripts.OnEnter(panel.cards[1].choices[1])
contains(table.concat(GameTooltip.lines, " "), "上次记录", "cache accuracy available on hover")
ns.professions[1].rank = 75
ns.RenderUI()
eq(panel.cards[1].choices[1].shown, false, "cap stops training recommendation")
contains(panel.cards[1].note.text, "当前技能上限", "cap explains next step")
ns.professions[1].rank = 45
ns.RenderUI()
panel.cards[1].header.scripts.OnClick()
eq(panel.cards[1].details.shown, false, "clicking expanded header collapses it")
eq(panel.cards[2].details.shown, false, "accordion allows every item collapsed")
panel.cards[1].header.scripts.OnClick()
ns.professions[1].recipes[2].reagents = {{required=2, options={
    {itemID=2770, name="铜矿石", owned=1, missing=1},
    {itemID=2771, name="锡矿石", owned=4, missing=0}
}}}
ns.RenderUI()
eq(#panel.cards[1].materialRows, 2, "each alternative material gets its own link row")
contains(panel.cards[1].materialRows[1].itemLink, "|Hitem:2770|h[铜矿石]|h", "uncached item gets native ID fallback link")
contains(panel.cards[1].materialRows[1].label.text, "任选", "alternative requirement is explicit")
contains(panel.cards[1].materialRows[2].counts.text, "需 2 / 有 4", "alternative keeps its own inventory")
panel.cards[1].materialRows[1].scripts.OnEnter(panel.cards[1].materialRows[1])
panel.cards[2].header.scripts.OnClick()
eq(GameTooltip.shown, false, "collapsing old details hides its owned tooltip")
local unrelatedOwner = {}
GameTooltip:SetOwner(unrelatedOwner)
GameTooltip:Show()
ns.RenderUI()
eq(GameTooltip.shown, true, "render leaves unrelated tooltip alone")
ns.DisplayProfessions = function(real, ready)
    local out = {}; for i,p in ipairs(real or {}) do out[i]=p end
    if ready then out[#out+1]={id=185,name="烹饪",unlearned=true,recipes={}} end
    return out
end
ns.RenderUI()
local cooking = panel.cards[3]
eq(cooking.header.rank.text, "未学习", "unlearned secondary shown without fake rank")
eq(cooking.header.fill.shown, false, "unlearned secondary has no fabricated fill")
cooking.header.scripts.OnClick()
eq(panel.cards[2].details.shown, false, "unlearned header also follows accordion")
eq(panel.controls.open.enabled, false, "unlearned secondary cannot open native skill")
contains(cooking.note.text,"训练师", "unlearned detail explains training")
opened = nil
panel.controls.open.scripts.OnClick(panel.controls.open)
eq(opened,nil,"hidden unlearned action stays guarded")
ns.DisplayProfessions = nil
ns.RenderUI()

panel.drag.scripts.OnDragStart()
eq(panel.moving, true, "unlocked drag starts")
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -30)
panel.drag.scripts.OnDragStop()
eq(panel.moving, false, "drag stops")
eq(ns.db.point, "TOPLEFT", "persist anchor")
eq(ns.db.x, 12, "persist horizontal offset")
eq(ns.db.y, -30, "persist vertical offset")
panel.controls.lock.scripts.OnClick()
eq(ns.db.locked, true, "persist lock")
panel.drag.scripts.OnDragStart()
eq(panel.moving, false, "locked drag blocked")
panel.controls.refresh.scripts.OnClick()
eq(refreshed, true, "locked panel retains interactions")

ns.SetScale(5)
eq(ns.db.scale, 1.6, "scale upper bound")
ns.SetScale(0)
eq(ns.db.scale, 0.65, "scale lower bound")
ns.SetScale(0/0)
eq(ns.db.scale, 0.65, "ignore nonfinite scaling")
ns.SetScale(1)
ctrl = true
local shortcutWidth = ns.db.windowWidth
panel.scroll.scripts.OnMouseWheel(panel.scroll, 1)
eq(ns.db.windowWidth, shortcutWidth + 32, "control wheel adds window width")
eq(ns.db.scale, 1, "control wheel keeps the existing font scale")
ctrl = false
panel.controls.minus.scripts.OnClick()
eq(ns.db.windowWidth, shortcutWidth, "minus control reduces window size")
panel.controls.plus.scripts.OnClick()
eq(ns.db.windowWidth, shortcutWidth + 32, "plus control adds window size")

for i = 3, 10 do
    ns.professions[i] = { id = i + 1000, name = "专业" .. i, rank = 1, maxRank = 75, kind = "crafting", cacheState = "missing", recipes = {} }
end
ns.RenderUI()
eq(panel.scrollbar.shown, true, "overflow shows scrollbar")
panel.scroll.scripts.OnMouseWheel(panel.scroll, -1000)
eq(panel.scroll.scroll, panel.scrollbar.max, "scroll clamps to bottom")
panel.scroll.scripts.OnMouseWheel(panel.scroll, 1000)
eq(panel.scroll.scroll, 0, "scroll clamps to top")
ns.SetScale(0.65)
local beforeCollapseX = ns.db.x
panel.controls.collapse.scripts.OnClick()
eq(ns.db.collapsed, true, "collapse persists")
local icon = panel.collapsedIcon
eq(panel.shown, false, "collapse hides the entire main panel")
eq(icon.parent, UIParent, "icon remains visible independently of the panel")
eq(icon.shown, true, "collapse shows the single restore icon")
eq(icon.width, 42, "icon matches the chat launcher width")
eq(icon.height, 42, "icon matches the chat launcher height")
eq(icon.label.text, "商", "icon shows the profession launcher character")
eq(icon.label.fontSize, 12, "icon matches the chat launcher font size")
near(icon.point[4], beforeCollapseX * 0.65, "icon converts the saved panel anchor to screen units")
eq(icon.scale, 1, "icon stays full size with the panel at 65 percent")
icon.scripts.OnEnter(icon)
contains(GameTooltip.lines[1], "左键展开", "icon tooltip explains how to restore the panel")
contains(GameTooltip.lines[2], "拖动图标", "icon always explains direct dragging")
icon.scripts.OnDragStart(icon)
eq(icon.moving, true, "panel title lock does not block icon dragging")
eq(ns.db.locked, true, "icon dragging preserves the panel title lock")
icon.scripts.OnDragStop(icon)
icon.scripts.OnClick(icon)
eq(icon.shown, true, "drag release does not expand the panel")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon)
eq(icon.shown, false, "restore hides the icon")
eq(GameTooltip.shown, false, "restore hides the icon tooltip")
eq(panel.shown, true, "restore shows the full panel")
near(panel.point[4], beforeCollapseX, "restore preserves the panel position")

panel.controls.lock.scripts.OnClick()
panel.controls.collapse.scripts.OnClick()
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnDragStart(icon)
eq(icon.moving, true, "unlocked icon can move")
icon:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 110, -44)
ns.RenderUI()
eq(icon.point[4], 110, "refresh does not snap the icon back mid-drag")
icon.scripts.OnDragStop(icon)
eq(math.abs(ns.db.x * 0.65 - 110) < 0.0001, true, "save the moved icon position in panel units")
icon.scripts.OnClick(icon)
eq(ns.db.collapsed, true, "drag release stays collapsed when a click follows drag stop")
eq(icon.scripts.OnUpdate, nil, "finished drag removes its release watchdog")
ns.SetScale(1.25)
eq(icon.point[4], 110, "panel scale changes keep the icon at its moved location")
eq(icon.scale, 1, "scaling the hidden panel does not resize the icon")
ns.db.shown = false
ns.RenderUI()
eq(icon.shown, false, "hide removes the collapsed icon")
eq(panel.shown, false, "hide keeps the full panel out of view")
ns.db.shown = true
ns.RenderUI()
eq(icon.shown, true, "saved collapsed state restores the icon")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon)
eq(panel.point[4] * 1.25, 110, "expanded panel follows the moved icon at the new scale")
eq(ns.db.collapsed, false, "icon click clears collapsed state")

panel.controls.collapse.scripts.OnClick()
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnDragStart(icon)
icon:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 150, -60)
icon.scripts.OnMouseUp(icon, "RightButton")
eq(icon.moving, true, "unrelated button release does not stop left dragging")
icon.scripts.OnMouseUp(icon, "LeftButton")
eq(icon.moving, false, "mouse release recovers a missing drag-stop event")
eq(ns.db.x * 1.25, 150, "mouse release persists the final icon location")
icon.scripts.OnClick(icon, "LeftButton")
eq(ns.db.collapsed, true, "mouse-up fallback does not cause accidental expansion")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnMouseUp(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
eq(panel.shown, true, "the next normal click after dragging opens immediately")

panel.controls.collapse.scripts.OnClick()
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnDragStart(icon)
icon:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 175, -75)
icon.scripts.OnUpdate(icon)
eq(icon.moving, true, "watchdog leaves an active left drag alone")
leftMouseDown = false
icon.scripts.OnUpdate(icon)
eq(icon.moving, false, "release outside window ends drag without mouse events")
eq(ns.db.x * 1.25, 175, "outside release persists icon position")
eq(icon.scripts.OnUpdate, nil, "outside release stops polling")
leftMouseDown = true
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
eq(panel.shown, true, "normal click after outside release is not swallowed")

panel.controls.collapse.scripts.OnClick()
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnDragStart(icon)
icon:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -80)
ns.db.shown = false
ns.RenderUI()
eq(icon.moving, false, "hiding the launcher stops an active drag")
eq(ns.db.x * 1.25, 200, "hiding mid-drag preserves the last position")
eq(icon.scripts.OnUpdate, nil, "hiding removes drag recovery polling")
ns.db.shown = true
ns.RenderUI()
eq(icon.point[4], 200, "showing again retains the hidden-drag location")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
eq(panel.shown, true, "restored launcher remains clickable")
ns.professions = {}
ns.RenderUI()
eq(panel.cards[1].shown, false, "unlearned profession card removed")
eq(panel.scroll.scroll, 0, "shrinking content clamps previous scroll")
ns.db.shown = false
ns.RenderUI()
eq(panel.shown, false, "respect saved hidden state")

-- The original behavior checks above remain, with scaling assertions following
-- the fixed screen corner rather than assuming unchanged scaled offsets.
ns.db.shown, ns.db.collapsed = true, false
ns.RenderUI()
eq(_G.MyForeverProfessionsPanel, panel, "special-frame name resolves to the actual panel")
eq(UISpecialFrames[1], "UnrelatedExistingPanel", "existing Esc registrations are preserved")
local registrations = 0
for _, name in ipairs(UISpecialFrames) do if name == "MyForeverProfessionsPanel" then registrations = registrations + 1 end end
eq(registrations, 1, "profession panel registered for native Esc exactly once")
eq(panel.scripts.OnKeyDown, nil, "native Esc needs no panel key capture")
eq(panel.scripts.OnKeyUp, nil, "panel does not consume key releases")
eq(panel.controls.resize.normalTexture, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up", "resize uses the native diagonal grip")
eq(panel.controls.plus:GetRight() < panel.controls.resize:GetLeft(), true, "plus button does not overlap resize grip")
eq(panel.controls.minus:GetRight() < panel.controls.plus:GetLeft(), true, "minus and plus have separate hit targets")
eq(panel.footer.text:find("Ctrl", 1, true), nil, "footer displays dimensions without operation instructions")
eq(panel.summary.text:find("拖动", 1, true), nil, "persistent summary omits operation instructions")
panel.controls.refresh.scripts.OnEnter(panel.controls.refresh)
eq(panel.controls.refresh.label.textColor[1] > 0.9, true, "auxiliary action has a readable hover state")
panel.controls.refresh.scripts.OnLeave(panel.controls.refresh)
eq(panel.controls.refresh.label.textColor[1] < 0.8, true, "auxiliary action returns to its secondary color")
panel.controls.resize.scripts.OnEnter(panel.controls.resize)
contains(table.concat(GameTooltip.lines, " "), "字号保持不变", "resize tooltip explains constant font size")

UIParent:SetScale(0.8)
ns.SetScale(1)
ns.SetWindowSize(372, 474)
ns.db.locked = true
local grip = panel.controls.resize
panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -200, 220)
panel.drag.scripts.OnDragStop()
local left, top = screenTopLeft(panel)
local function moveResize(width, height)
    cursorX = cursorX + width * panel:GetEffectiveScale()
    cursorY = cursorY - height * panel:GetEffectiveScale()
end
grip.scripts.OnMouseDown(grip, "RightButton")
eq(grip.scripts.OnUpdate, nil, "right mouse button does not start resizing")
ctrl, leftMouseDown = false, true
grip.scripts.OnMouseDown(grip, "LeftButton")
moveResize(120, 80)
grip.scripts.OnUpdate(grip)
eq(ns.db.windowWidth, 492, "unmodified grip drag widens a locked panel")
eq(ns.db.windowHeight, 554, "unmodified grip drag increases its viewport height")
eq(ns.db.scale, 1, "grip dragging keeps the saved font scale unchanged")
eq(ns.db.locked, true, "resizing retains title lock preference")
eq(panel.moving, false, "resizing does not move the locked title")
local newLeft, newTop = screenTopLeft(panel)
near(newLeft, left, "resize preserves physical left at a nondefault UIParent scale")
near(newTop, top, "resize preserves physical top at a bottom-right anchor")
eq(ns.db.point, "BOTTOMRIGHT", "resize preserves the saved panel anchor convention")
eq(ns.db.relativePoint, "BOTTOMRIGHT", "resize preserves the saved relative anchor")
near(ns.db.x, panel.point[4], "resize saves offsets in panel units")
grip.scripts.OnMouseUp(grip, "RightButton")
eq(type(grip.scripts.OnUpdate), "function", "unrelated mouse release leaves resize active")
grip.scripts.OnMouseUp(grip, "LeftButton")
eq(grip.scripts.OnUpdate, nil, "mouse-up saves and stops when drag-stop is missing")

grip.scripts.OnDragStart(grip)
moveResize(10000, 10000)
grip.scripts.OnUpdate(grip)
eq(ns.db.windowWidth, ns.PanelSize.maxWidth, "grip drag clamps at the upper width bound")
eq(ns.db.windowHeight, ns.PanelSize.maxHeight, "grip drag clamps at the upper height bound")
grip.scripts.OnDragStop(grip)
eq(grip.scripts.OnUpdate, nil, "drag-stop removes resize polling")
grip.scripts.OnDragStart(grip)
moveResize(-10000, -10000)
grip.scripts.OnUpdate(grip)
eq(ns.db.windowWidth, ns.PanelSize.minWidth, "grip drag clamps at the lower width bound")
eq(ns.db.windowHeight, ns.PanelSize.minHeight, "grip drag clamps at the lower height bound")
grip.scripts.OnDragStop(grip)

ns.SetScale(1)
ns.SetWindowSize(372, 474)
panel:SetPoint("CENTER", UIParent, "CENTER", 180, -60)
panel.drag.scripts.OnDragStop()
left, top = screenTopLeft(panel)
ns.SetScale(1.25)
newLeft, newTop = screenTopLeft(panel)
near(newLeft, left, "button and wheel scaling also fix the physical left")
near(newTop, top, "button and wheel scaling also fix the physical top")
eq(ns.db.point, "CENTER", "center-anchor users retain their original anchor")
ns.SetScale(1)
grip.scripts.OnDragStart(grip)
moveResize(80, 60)
leftMouseDown = false
grip.scripts.OnUpdate(grip)
eq(ns.db.windowWidth, 452, "release outside the window saves the final cursor width")
eq(ns.db.windowHeight, 534, "release outside the window saves the final cursor height")
eq(grip.scripts.OnUpdate, nil, "outside-window release removes resize polling")
leftMouseDown = true
grip.scripts.OnDragStart(grip)
moveResize(40, 30)
left, top = screenTopLeft(panel)
panel:Hide()
eq(ns.db.windowWidth, 492, "direct hide saves an active width resize")
eq(ns.db.windowHeight, 564, "direct hide saves an active height resize")
eq(grip.scripts.OnUpdate, nil, "direct hide stops an active resize")
newLeft, newTop = screenTopLeft(panel)
near(newLeft, left, "hide fallback retains the resized physical left")
near(newTop, top, "hide fallback retains the resized physical top")
eq(ns.db.collapsed, true, "direct native Esc hide persists collapsed state")
eq(ns.db.shown, true, "Esc keeps the addon enabled")
eq(icon.shown, true, "Esc exposes the independent merchant launcher")
for _ = 1, 3 do ns.RenderUI() end
eq(panel.shown, false, "periodic rendering does not reopen an Esc-collapsed panel")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
eq(panel.shown, true, "merchant launcher reopens after native Esc")
eq(ns.db.collapsed, false, "launcher clears Esc collapse preference")

UIParent:Hide()
eq(panel:IsShown(), true, "ancestor hide preserves the panel's own shown flag")
eq(panel:IsVisible(), false, "ancestor hide actually makes panel invisible")
eq(ns.db.collapsed, false, "ancestor/UIParent hide does not turn into an Esc collapse")
UIParent:Show()
ns.RenderUI()
eq(panel.shown, true, "panel returns with UIParent after an ancestor hide")
grip.scripts.OnDragStart(grip)
moveResize(20, 20)
ns.db.shown = false
ns.RenderUI()
eq(grip.scripts.OnUpdate, nil, "programmatic hide stops an active resize")
eq(ns.db.collapsed, false, "programmatic full hide does not force collapsed state")
eq(panel.shown, false, "programmatic full hide hides the main panel")
eq(icon.shown, false, "programmatic full hide also hides the launcher")
ns.db.shown = true
ns.RenderUI()
eq(panel.shown, true, "programmatic show restores the prior expanded state")
eq(ns.db.gatherAlerts, false, "resize and Esc preserve the gather-alert switch")
eq(ns.db.gatherSound, true, "resize and Esc preserve the gather-sound switch")
eq(ns.db.gatherSparkles, false, "resize and Esc preserve the gather-sparkle switch")
UIParent:SetScale(1)

local longName = "精制的铜质符文护手与多层次魔法材料训练项目"
local longMaterial = "来自遥远山谷的经过精细处理的特殊草药与矿物混合材料"
ns.professions = {{ id = 171, name = "炼金术", rank = 45, maxRank = 75, cacheState = "fresh", recipes = {
    { id = 1, name = longName, difficulty = "orange", craftable = 128, reagentsComplete = true,
      reagents = {{itemID = 900001, name = longMaterial, required = 128, owned = 2, missing = 126}} },
    { id = 2, name = "第二个黄色配方", difficulty = "yellow", craftable = 0, reagentsComplete = true,
      reagents = {{itemID = 900002, name = "黄色配方材料", required = 5, owned = 1, missing = 4}} },
    { id = 3, name = "第三个绿色配方", difficulty = "green", craftable = 3, reagentsComplete = true,
      reagents = {{itemID = 900003, name = "绿色配方材料", required = 1, owned = 4, missing = 0}} },
}}}
ns.RenderUI()
local card = panel.cards[1]
if not card.details.shown then card.header.scripts.OnClick() end
card.choices[1].scripts.OnClick(card.choices[1])
eq(card.choices[1].label.text, longName, "full long recipe name remains separate from stock count")
eq(card.choices[1].stock.text, "材料可做 128 次", "craftable count has its own text line")
eq(card.choices[1].label.fontSize > card.choices[2].label.fontSize, true, "current recipe has a larger name font")
eq(card.choices[1].bg.shown and card.choices[1].marker.shown, true, "selection has background and marker beyond text/color")
eq(card.choices[2].bg.shown, false, "other candidate has secondary visual weight")
eq(card.choices[1].role.text, "当前选择", "user-selected recipe is identified as a selection")
local materialRow = card.materialRows[1]
contains(materialRow.label.text, longMaterial, "full long material link remains visible")
contains(materialRow.counts.text, "缺 126", "long materials retain the exact shortage")
eq(materialRow.counts.text:find("缺", 1, true) < materialRow.counts.text:find("需", 1, true), true, "shortage leads the quieter need/owned details")
eq(materialRow.counts:GetTop() <= materialRow.label:GetBottom() - 2, true, "wrapped material name cannot overlap shortage line")
eq(card.choices[1].stock:GetTop() <= card.choices[1].label:GetBottom() - 2, true, "wrapped recipe name cannot overlap craftable count")
eq(card.choices[1]:GetBottom() > materialRow:GetTop(), true, "current recipe precedes its materials")
eq(materialRow:GetBottom() > card.otherTitle:GetTop(), true, "materials precede other candidates")
eq(card.choices[2]:GetBottom() > card.choices[3]:GetTop(), true, "other candidates retain original difficulty order")
eq(card.choices[3]:GetBottom() > card.trainer:GetTop(), true, "trainer action follows all three candidates")
eq(panel.controls.open.parent, panel, "open profession action remains fixed outside scrolling content")
for index = 1, 3 do eq(card.choices[index].recipeKey, index, "all three recipe data indices remain available") end
card.choices[3].scripts.OnClick(card.choices[3])
eq(card.choices[3].role.text, "当前选择", "promoted third candidate is never called first recommendation")
eq(card.choices[3]:GetBottom() > card.materialRows[1]:GetTop(), true, "selected third candidate is promoted above its own materials")
eq(card.materialRows[1].itemName, "绿色配方材料", "promoted candidate still chooses its actual materials")
eq(card.choices[1]:GetBottom() > card.choices[2]:GetTop(), true, "remaining orange and yellow candidates retain their ordering")
card.choices[3].scripts.OnEnter(card.choices[3])
contains(table.concat(GameTooltip.lines, " "), "难度：绿色", "difficulty remains explicit in the candidate tooltip")
eq(card.materialTitle.shown, false, "new layout does not restore deleted material heading")
eq(card.choices[3].label.text:find(">", 1, true), nil, "selected marker does not require a text prefix")

-- Title movement must finish before Esc chooses the launcher position, even
-- when the game never delivers OnDragStop to the original title region.
ns.db.locked, ns.db.shown, ns.db.collapsed = false, true, false
ns.SetScale(1.25)
ns.RenderUI()
local titleDrag = panel.drag
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 94, -64)
panel:Hide()
eq(panel.moving, false, "Esc ends an active title move")
eq(titleDrag.scripts.OnUpdate, nil, "Esc clears the title release watchdog")
eq(ns.db.x, 94, "Esc saves the title's latest horizontal position before folding")
eq(ns.db.y, -64, "Esc saves the title's latest vertical position before folding")
eq(ns.db.collapsed, true, "Esc during title movement still persists a collapse")
near(icon.point[4], 94 * 1.25, "Esc places the launcher from the newly saved title position")
near(icon.point[5], -64 * 1.25, "Esc converts the newly saved vertical offset for the launcher")
ns.RenderUI()
near(icon.point[4], 94 * 1.25, "periodic rendering retains the title-drag Esc launcher position")
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
eq(panel.point[4], 94, "launcher restores the final title-drag position")
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 99, -64)
titleDrag.scripts.OnDragStop(titleDrag)
eq(ns.db.x, 94, "late drag-stop with no active title move does not overwrite saved position")

titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 122, -76)
titleDrag.scripts.OnUpdate(titleDrag)
eq(panel.moving, true, "title watchdog preserves an active left-button drag")
leftMouseDown = false
titleDrag.scripts.OnUpdate(titleDrag)
eq(panel.moving, false, "release outside the window ends title movement")
eq(ns.db.x, 122, "outside title release saves the last position")
eq(titleDrag.scripts.OnUpdate, nil, "outside title release removes polling")
leftMouseDown = true
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 134, -82)
ns.RenderUI()
eq(panel.moving, true, "ordinary rendering does not interrupt active title dragging")
titleDrag.scripts.OnMouseUp(titleDrag, "RightButton")
eq(panel.moving, true, "right-button release does not stop left-button title dragging")
titleDrag.scripts.OnMouseUp(titleDrag, "LeftButton")
eq(panel.moving, false, "left mouse-up recovers a missing title drag-stop")
eq(ns.db.x, 134, "left mouse-up persists the final title position")
eq(titleDrag.scripts.OnUpdate, nil, "left mouse-up removes title polling")

titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 148, -92)
UIParent:Hide()
eq(panel.moving, false, "ancestor hide ends title movement")
eq(ns.db.x, 148, "ancestor hide saves title movement")
eq(titleDrag.scripts.OnUpdate, nil, "ancestor hide removes title polling")
eq(ns.db.collapsed, false, "ancestor hide during movement does not force an Esc collapse")
UIParent:Show()
ns.RenderUI()
eq(panel.point[4], 148, "ancestor recovery keeps the final title location")
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 167, -110)
ns.db.shown = false
ns.RenderUI()
eq(panel.moving, false, "programmatic full hide ends title movement")
eq(ns.db.x, 167, "programmatic full hide saves title movement")
eq(titleDrag.scripts.OnUpdate, nil, "programmatic full hide removes title polling")
eq(ns.db.collapsed, false, "programmatic hide during movement preserves expanded preference")
eq(icon.shown, false, "programmatic hide during title movement keeps the launcher hidden")
ns.db.shown = true
ns.RenderUI()

titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 188, -126)
panel.controls.lock.scripts.OnClick()
eq(panel.moving, false, "locking finishes an active title move")
eq(ns.db.x, 188, "locking saves the final title location")
eq(titleDrag.scripts.OnUpdate, nil, "locking clears title drag state and polling")
titleDrag.scripts.OnDragStart(titleDrag)
eq(panel.moving, false, "a completed title drag cannot restart while locked")
eq(titleDrag.scripts.OnUpdate, nil, "blocked locked drag does not install a watchdog")
ns.db.locked = false
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 201, -145)
grip.scripts.OnDragStart(grip)
eq(panel.moving, false, "starting resize finishes title movement first")
eq(ns.db.x, 201, "resize handoff saves the final title location")
eq(titleDrag.scripts.OnUpdate, nil, "resize handoff clears the old title watchdog")
eq(type(grip.scripts.OnUpdate), "function", "resize handoff installs only the resize watchdog")
grip.scripts.OnMouseUp(grip, "LeftButton")
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 222, -150)
panel.controls.collapse.scripts.OnClick()
eq(panel.moving, false, "collapse control also ends an active title move")
eq(titleDrag.scripts.OnUpdate, nil, "collapse control clears title polling")
eq(ns.db.x, 222, "collapse control saves before RenderUI positions the launcher")
near(icon.point[4], 222 * ns.db.scale, "collapse control places the launcher at the latest title location")
near(icon.point[5], -150 * ns.db.scale, "collapse control preserves the latest vertical title location")

-- Window size is independent of font scale and controls a persistent viewport.
icon.scripts.OnMouseDown(icon, "LeftButton")
icon.scripts.OnClick(icon, "LeftButton")
ns.SetScale(1.25)
ns.SetWindowSize(340, 474)
card.choices[1].scripts.OnClick(card.choices[1])
local fontScale = ns.db.scale
local recipeFont, materialFont = card.choices[1].label.fontSize, card.materialRows[1].label.fontSize
local narrowRecipeHeight = card.choices[1].label:GetStringHeight()
local narrowMaterialWidth = card.materialRows[1].label:GetWidth()
local narrowCardHeight = card:GetHeight()
ns.SetWindowSize(700, 740)
eq(ns.db.scale, fontScale, "window-size API does not write the saved font scale")
eq(panel:GetScale(), fontScale, "window-size API leaves rendered font scale unchanged")
eq(card.choices[1].label.fontSize, recipeFont, "window resize preserves current-recipe font size")
eq(card.materialRows[1].label.fontSize, materialFont, "window resize preserves material font size")
eq(panel:GetWidth(), 700, "window-size API applies the requested width")
eq(panel:GetHeight(), 740, "window-size API applies the requested height")
eq(panel.scroll:GetHeight(), 644, "viewport height is saved window height minus the fixed toolbar/footer area")
eq(panel.content:GetWidth(), 658, "content width follows the enlarged window")
eq(card.header:GetWidth(), 658, "cached profession header width follows the enlarged window")
eq(card.details:GetWidth(), 646, "cached detail frame width follows the enlarged window")
eq(panel.cards[2].header:GetWidth(), 658, "hidden cached cards also receive the new width")
eq(card.choices[1].label:GetStringHeight() < narrowRecipeHeight, true, "wider recipe text reflows before row heights are measured")
eq(card.materialRows[1].label:GetWidth() > narrowMaterialWidth, true, "cached material links gain width")
eq(card:GetHeight() <= narrowCardHeight, true, "wider cached card recomputes its wrapped content height")
eq(card.materialRows[1].counts:GetTop() <= card.materialRows[1].label:GetBottom() - 2, true, "material shortage stays below its reflowed name")
eq(panel.footer.text, "700 × 740", "footer reports window dimensions")
local toolbarTop = panel.controls.open:GetTop()
panel.scroll.scripts.OnMouseWheel(panel.scroll, -1000)
eq(panel.controls.open:GetTop(), toolbarTop, "skill-book action stays fixed while content scrolls")
eq(panel.controls.open.parent, panel, "skill-book action belongs to the fixed panel rather than a card")
eq(card.open, nil, "scrolling card has no duplicate bottom skill-book entry")
card.header.scripts.OnClick()
eq(card.details.shown, false, "same profession header can collapse its details")
eq(panel.controls.open.professionID, 171, "collapsing a profession retains the explicit skill-book target")
eq(panel.controls.open.enabled, true, "collapsed selected profession remains openable from the toolbar")
opened = nil
panel.controls.open.scripts.OnClick(panel.controls.open)
eq(opened, 171, "fixed skill-book action opens the last explicitly selected profession")
card.header.scripts.OnClick()

ns.professions = {}
ns.RenderUI()
eq(panel:GetHeight(), 740, "short content leaves the saved tall window intact")
eq(panel.scroll:GetHeight(), 644, "short content retains blank viewport space")
eq(panel.controls.open.enabled, false, "removed profession disables the previously selected toolbar target")
opened = nil
panel.controls.open.scripts.OnClick(panel.controls.open)
eq(opened, nil, "missing selected profession cannot open a different profession implicitly")
for _ = 1, 3 do ns.RenderUI() end
eq(ns.db.windowWidth, 700, "periodic rendering preserves user window width")
eq(ns.db.windowHeight, 740, "periodic rendering preserves user window height")
eq(panel.scrollbar.shown, false, "short content hides the scrollbar while retaining its viewport")

ns.SetWindowSize(0/0, 300)
ns.SetWindowSize(500, math.huge)
eq(ns.db.windowWidth, 700, "invalid dimensions do not damage saved width")
eq(ns.db.windowHeight, 740, "invalid dimensions do not damage saved height")
UIParent:SetScale(0.75)
UIParent:SetSize(640, 400)
ns.SetWindowSize(900, 900)
eq(ns.db.windowWidth, 512, "maximum width accounts for saved panel scale and available UIParent width")
eq(ns.db.windowHeight, 320, "maximum height accounts for saved panel scale and available UIParent height")
eq(panel:GetWidth() * panel:GetEffectiveScale() <= UIParent:GetWidth() * UIParent:GetEffectiveScale(), true, "window physical width fits the available screen")
eq(panel:GetHeight() * panel:GetEffectiveScale() <= UIParent:GetHeight() * UIParent:GetEffectiveScale(), true, "window physical height fits the available screen")
UIParent:SetSize(1920, 1080)
UIParent:SetScale(1)
ns.SetWindowSize(372, 474)
local widthBeforeHorizontal, heightBeforeHorizontal = ns.db.windowWidth, ns.db.windowHeight
grip.scripts.OnDragStart(grip)
moveResize(75, 0)
grip.scripts.OnUpdate(grip)
eq(ns.db.windowWidth, widthBeforeHorizontal + 75, "horizontal grip movement changes only width")
eq(ns.db.windowHeight, heightBeforeHorizontal, "horizontal grip movement leaves height unchanged")
grip.scripts.OnMouseUp(grip, "LeftButton")
grip.scripts.OnDragStart(grip)
moveResize(0, 90)
grip.scripts.OnUpdate(grip)
eq(ns.db.windowHeight, heightBeforeHorizontal + 90, "vertical grip movement changes only height")
eq(ns.db.windowWidth, widthBeforeHorizontal + 75, "vertical grip movement leaves width unchanged")
eq(ns.db.scale, fontScale, "both independent grip axes preserve the existing font scale")
grip.scripts.OnMouseUp(grip, "LeftButton")
ns.db.locked = false
titleDrag.scripts.OnDragStart(titleDrag)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 199, -130)
ns.ResetWindowSize()
eq(panel.moving, false, "window reset ends active title movement")
eq(titleDrag.scripts.OnUpdate, nil, "window reset removes title drag polling")
eq(ns.db.windowWidth, ns.PanelSize.defaultWidth, "window reset restores default width")
eq(ns.db.windowHeight, ns.PanelSize.defaultHeight, "window reset restores default height")
eq(ns.db.scale, fontScale, "window reset leaves explicit font scale to the caller")
grip.scripts.OnDragStart(grip)
moveResize(100, 70)
ns.ResetWindowSize()
eq(grip.scripts.OnUpdate, nil, "window reset finishes pending grip movement")
eq(ns.db.windowWidth, ns.PanelSize.defaultWidth, "pending grip cannot overwrite reset width")
eq(ns.db.windowHeight, ns.PanelSize.defaultHeight, "pending grip cannot overwrite reset height")
eq(ns.db.gatherAlerts, false, "window sizing preserves the gather-alert switch")
eq(ns.db.gatherSound, true, "window sizing preserves the gather-sound switch")
eq(ns.db.gatherSparkles, false, "window sizing preserves the gather-sparkle switch")
print("professions_ui_test: " .. checks .. " checks passed")
