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

local methods = {}
local function frame(kind, name, parent)
    return setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true, width = 0, height = 0, scroll = 0, value = 0 }, { __index = methods })
end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 300, 0 }) end
function methods:ClearAllPoints() self.point = nil end
function methods:EnableMouse(value) self.mouse = value end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetAllPoints() end
function methods:SetText(value) self.text = value end
function methods:GetStringHeight()
    local lines = 1
    for _ in (self.text or ""):gmatch("\n") do lines = lines + 1 end
    return lines * 14
end
function methods:CreateFontString() return frame("FontString", nil, self) end
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
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetScale(value) self.scale = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
for _, method in ipairs({ "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetSpacing", "SetTextColor", "SetVertexColor", "SetColorTexture", "SetTexture", "SetMovable", "EnableMouseWheel", "SetFrameStrata", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "RegisterForDrag", "SetOrientation", "SetValueStep" }) do
    methods[method] = function() end
end
UIParent = frame("Frame")
CreateFrame = frame
local ctrl = false
IsControlKeyDown = function() return ctrl end
local opened, refreshed, itemRef, inserted, shift = nil, nil, nil, nil, false
local activeEdit
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
    SetText = function() end, AddLine = function() end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false; self.owner = nil end,
}
local ns = {
    db = { shown = true, locked = false, scale = 1, point = "CENTER", relativePoint = "CENTER", x = 300, y = 0 },
    professions = {}, detectReady = false,
    OpenProfession = function(id) opened = id end,
    Refresh = function(force) refreshed = force end,
    Progress = function(p) return { text = p.rank .. "/" .. p.maxRank .. " · 距上限 " .. (p.maxRank - p.rank) .. " 点", nextPoint = p.rank < p.maxRank and p.rank + 1 or nil } end,
    GatheringAdvice = function() return "资源颜色以游戏显示为准。" end,
}
assert(loadfile("PersonalAddons/work/professions-progress-accordion/UI.lua"))("MyForeverProfessions", ns)
local panel = ns.CreateUI()
eq(ns.frame, panel, "expose root frame")
eq(ns.CreateUI(), panel, "creation is idempotent")
eq(panel.shown, true, "visible by default")
eq(panel.clamped, true, "panel stays on screen")
contains(panel.content.empty.text, "正在读取", "loading differs from unlearned")
ns.detectReady = true
ns.RenderUI()
contains(panel.content.empty.text, "尚未学习", "unlearned state")
panel.controls.refresh.scripts.OnClick()
eq(refreshed, true, "refresh requests forced scan")

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
contains(panel.cards[1].progress.text, "下一点目标 46", "next skill point visible")
contains(panel.cards[1].materialRows[1].counts.text, "需 2 / 有 5", "show needs and owned")
panel.cards[1].open.scripts.OnClick()
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
activeEdit = {}
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
eq(panel.cards[2].materialTitle.text, "采集训练", "gathering does not show manufacture materials")
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
contains(panel.cards[1].note.text, "当前颜色待确认", "stale color warning")
contains(panel.cards[1].choices[1].label.text, "上次橙", "cached color identified at recipe")
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
eq(cooking.open.shown, false, "unlearned secondary cannot open native skill")
contains(cooking.note.text,"训练师", "unlearned detail explains training")
opened = nil
cooking.open.scripts.OnClick()
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
panel.scroll.scripts.OnMouseWheel(panel.scroll, 1)
eq(ns.db.scale, 1.05, "control wheel scales")
ctrl = false
panel.controls.minus.scripts.OnClick()
eq(ns.db.scale, 1, "minus control scales")
panel.controls.plus.scripts.OnClick()
eq(ns.db.scale, 1.05, "plus control scales")

for i = 3, 10 do
    ns.professions[i] = { id = i + 1000, name = "专业" .. i, rank = 1, maxRank = 75, kind = "crafting", cacheState = "missing", recipes = {} }
end
ns.RenderUI()
eq(panel.scrollbar.shown, true, "overflow shows scrollbar")
panel.scroll.scripts.OnMouseWheel(panel.scroll, -1000)
eq(panel.scroll.scroll, panel.scrollbar.max, "scroll clamps to bottom")
panel.scroll.scripts.OnMouseWheel(panel.scroll, 1000)
eq(panel.scroll.scroll, 0, "scroll clamps to top")
panel.controls.collapse.scripts.OnClick()
eq(ns.db.collapsed, true, "collapse persists")
eq(panel.scroll.shown, false, "collapse hides content")
eq(panel.shown, true, "collapse retains persistent panel")
panel.controls.collapse.scripts.OnClick()
eq(panel.scroll.shown, true, "expand restores content")
ns.professions = {}
ns.RenderUI()
eq(panel.cards[1].shown, false, "unlearned profession card removed")
eq(panel.scroll.scroll, 0, "shrinking content clamps previous scroll")
ns.db.shown = false
ns.RenderUI()
eq(panel.shown, false, "respect saved hidden state")
print("profession accordion draft UI: " .. checks .. " checks passed")
