local _, ns = ...

local WIDTH, CONTENT_WIDTH, MAX_VIEW_HEIGHT = 372, 330, 378
local palette = {
    orange = { 1, 0.49, 0.18, "橙" }, yellow = { 1, 0.83, 0.25, "黄" },
    green = { 0.35, 0.84, 0.45, "绿" }, gray = { 0.58, 0.6, 0.62, "灰" },
    unknown = { 0.7, 0.72, 0.75, "?" },
}
local selected, cards = {}, {}
local panel, scroll, content, bar, summary, footer, collapseButton, lockButton
local contentHeight, viewHeight, settingScroll = 0, 0, false

local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function text(parent, width, template)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)
    label:SetSpacing(3)
    return label
end

local function labelHeight(label, minimum)
    return math.max(minimum or 14, (label:GetStringHeight() or 0) + 3)
end

local function button(parent, caption, width, action)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 23)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetVertexColor(0.9, 0.77, 0.48, 0.12)
    b.label = text(b, width, "GameFontNormalSmall")
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.label:SetText(caption)
    b:SetScript("OnClick", action)
    return b
end

local function setScroll(value)
    value = math.max(0, math.min(math.max(0, contentHeight - viewHeight), tonumber(value) or 0))
    scroll:SetVerticalScroll(value)
    if not settingScroll then
        settingScroll = true
        bar:SetValue(value)
        settingScroll = false
    end
end

local function savePosition()
    local point, _, relativePoint, x, y = panel:GetPoint()
    if type(point) == "string" and type(relativePoint) == "string" and number(x) and number(y) then
        ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = point, relativePoint, x, y
    end
end

function ns.SetScale(value)
    if not number(value) then return end
    ns.db.scale = math.floor(math.max(0.65, math.min(1.60, value)) * 100 + 0.5) / 100
    if panel then
        panel:SetScale(ns.db.scale)
        footer:SetText(string.format("%d%%  ·  Ctrl + 滚轮缩放", math.floor(ns.db.scale * 100 + 0.5)))
    end
end

local function wheel(_, delta)
    if IsControlKeyDown and IsControlKeyDown() then
        ns.SetScale((ns.db.scale or 1) + delta * 0.05)
    elseif not ns.db.collapsed then
        setScroll(scroll:GetVerticalScroll() - delta * 42)
    end
end

local function getCard(index)
    if cards[index] then return cards[index] end
    local card = CreateFrame("Frame", nil, content)
    card:SetWidth(CONTENT_WIDTH)
    card.line = card:CreateTexture(nil, "ARTWORK")
    card.line:SetColorTexture(0.56, 0.48, 0.32, 0.26)
    card.line:SetPoint("TOPLEFT", 0, 0)
    card.line:SetSize(CONTENT_WIDTH, 1)
    card.open = button(card, "", CONTENT_WIDTH, function()
        if ns.OpenProfession and card.professionID then ns.OpenProfession(card.professionID) end
    end)
    card.open:SetPoint("TOPLEFT", 0, -7)
    card.open.label:SetJustifyH("LEFT")
    card.open.label:SetTextColor(0.92, 0.81, 0.56)
    card.open.icon = card.open:CreateTexture(nil, "ARTWORK")
    card.open.icon:SetSize(18, 18)
    card.open.icon:SetPoint("LEFT", 0, 0)
    card.open.label:ClearAllPoints()
    card.open.label:SetPoint("LEFT", 24, 0)
    card.open.label:SetWidth(CONTENT_WIDTH - 24)
    card.progress = text(card, CONTENT_WIDTH)
    card.progress:SetPoint("TOPLEFT", 0, -34)
    card.note = text(card, CONTENT_WIDTH)
    card.note:SetTextColor(0.65, 0.69, 0.72)
    card.choices = {}
    for choice = 1, 3 do
        local row = button(card, "", CONTENT_WIDTH, function(self)
            selected[card.professionID] = self.recipeKey
            ns.RenderUI()
        end)
        row.label:SetJustifyH("LEFT")
        row.label:SetWidth(CONTENT_WIDTH - 8)
        row:SetScript("OnEnter", function(self)
            if GameTooltip and self.recipeName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.recipeName)
                GameTooltip:AddLine("点击查看这项训练的材料", 0.75, 0.78, 0.8)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        card.choices[choice] = row
    end
    card.materialTitle = text(card, CONTENT_WIDTH)
    card.materialTitle:SetTextColor(0.75, 0.79, 0.82)
    card.materials = text(card, CONTENT_WIDTH)
    cards[index] = card
    return card
end

local function amount(value)
    return number(value) and tostring(math.max(0, math.floor(value))) or "?"
end

local function materialText(recipe)
    local lines = {}
    for _, reagent in ipairs(recipe.reagents or {}) do
        local name = reagent.name or (reagent.itemID and "物品 " .. reagent.itemID) or "材料名称读取中"
        local required, owned = reagent.required, reagent.owned
        local missing = reagent.missing
        if not number(missing) and number(required) and number(owned) then missing = math.max(0, required - owned) end
        if reagent.options and #reagent.options > 1 then
            local options = {}
            for _, option in ipairs(reagent.options) do
                options[#options + 1] = option.name or (option.itemID and "物品 " .. option.itemID) or "备选材料"
            end
            lines[#lines + 1] = "|cffc8cdd2" .. table.concat(options, " / ") .. "|r\n  任选一种 × " .. amount(required) .. " · 库存请在专业窗口核对"
        else
            local color = number(missing) and missing > 0 and "|cffffb080" or "|cffb9dfc1"
            lines[#lines + 1] = "|cffc8cdd2" .. name .. "|r\n  需 " .. amount(required) .. " / 有 " .. amount(owned) .. " / " .. color .. "缺 " .. amount(missing) .. "|r"
        end
    end
    if #lines == 0 then
        lines[1] = recipe.reagentsComplete == true and "此项目没有需消耗的制造材料。" or "材料尚未读取完整，请打开该专业刷新。"
    elseif recipe.reagentsComplete == false then
        lines[#lines + 1] = "|cffdcb57b部分材料待读取，请在专业窗口核对。|r"
    end
    return table.concat(lines, "\n")
end

local function renderCard(card, profession)
    card:Show()
    card.professionID = profession.id
    card.open.icon:SetTexture(profession.icon or "Interface\\Icons\\INV_Misc_Book_09")
    card.open.label:SetText((profession.name or "商业技能") .. "   |cff8a9299打开 >|r")
    local progress = ns.Progress and ns.Progress(profession)
    local progressText = progress and progress.text or (amount(profession.rank) .. " / " .. amount(profession.maxRank))
    if progress and progress.nextPoint then progressText = progressText .. "\n下一点目标 " .. amount(progress.nextPoint) .. " · 实际训练次数不固定" end
    card.progress:SetText(progressText)
    local y = 34 + labelHeight(card.progress) + 4
    local recipes = profession.recipes or {}
    local capped = number(profession.rank) and number(profession.maxRank) and profession.maxRank > 0 and profession.rank >= profession.maxRank
    local notes = {}
    if profession.status and profession.status ~= "" then notes[#notes + 1] = profession.status end
    if capped then
        notes[#notes + 1] = "已到当前技能上限；可向训练师查看下一阶段。"
    elseif profession.cacheState == "stale" then
        notes[#notes + 1] = "上次记录 · 当前颜色待确认，打开该专业刷新。"
    elseif profession.cacheState == "missing" then
        notes[#notes + 1] = "首次使用请打开该专业，读取已学训练项目。"
    end
    if #recipes == 0 and not capped then
        if profession.kind == "gathering" and ns.GatheringAdvice then
            notes[#notes + 1] = ns.GatheringAdvice(profession)
        elseif profession.cacheState == "fresh" then
            notes[#notes + 1] = "没有可推荐的已学橙／黄／绿项目；可向训练师学习新项目。"
        end
    end
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", 0, -y)
    card.note:SetText(table.concat(notes, "\n"))
    if #notes > 0 then y = y + labelHeight(card.note) + 6 end
    local chosen, count = nil, capped and 0 or math.min(3, #recipes)
    for index = 1, count do
        local recipe = recipes[index]
        if selected[profession.id] == (recipe.id or recipe.name or index) then chosen = index end
    end
    chosen = chosen or (count > 0 and 1 or nil)
    for index, row in ipairs(card.choices) do
        local recipe = index <= count and recipes[index] or nil
        row:SetShown(recipe ~= nil)
        if recipe then
            local color = palette[recipe.difficulty] or palette.unknown
            local prefix = index == chosen and "> " or "  "
            local historical = profession.cacheState == "stale" and "上次" or ""
            local stock = not recipe.isGatheringRecipe and number(recipe.craftable) and (" · 材料可做 " .. amount(recipe.craftable) .. " 次") or ""
            row.label:SetText(prefix .. "[" .. historical .. color[4] .. "] " .. (recipe.name or "训练项目") .. stock)
            row.label:SetTextColor(color[1], color[2], color[3])
            row:SetHeight(labelHeight(row.label, 20) + 4)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.recipeKey, row.recipeName = recipe.id or recipe.name or index, recipe.name
            y = y + row:GetHeight() + 2
        end
    end
    card.materialTitle:SetShown(chosen ~= nil)
    card.materials:SetShown(chosen ~= nil)
    if chosen then
        local recipe = recipes[chosen]
        card.materialTitle:ClearAllPoints()
        card.materialTitle:SetPoint("TOPLEFT", 0, -y - 5)
        local current, target = recipe.currentRecipeExperience, recipe.nextLevelRecipeExperience
        local experience = number(current) and number(target) and target > 0 and current >= 0 and target >= current
            and ("项目升下一级还差 " .. amount(target - current) .. " 熟练度") or nil
        card.materialTitle:SetText(recipe.isGatheringRecipe and "采集训练" or "单次材料 · 仅统计随身背包")
        y = y + 5 + labelHeight(card.materialTitle) + 3
        card.materials:ClearAllPoints()
        card.materials:SetPoint("TOPLEFT", 0, -y)
        local details = recipe.isGatheringRecipe and "前往对应资源点进行采集；升级以游戏实际结果为准。" or materialText(recipe)
        if experience then details = experience .. "\n" .. details end
        card.materials:SetText(details)
        y = y + labelHeight(card.materials) + 5
    end
    card:SetHeight(y + 13)
    return y + 13
end

function ns.RenderUI()
    if not panel then return end
    panel:SetShown(ns.db.shown ~= false)
    lockButton.label:SetText(ns.db.locked and "解锁" or "锁定")
    collapseButton.label:SetText(ns.db.collapsed and "+" or "-")
    summary:SetText(ns.combatPaused and "战斗中 · 数据暂停" or (ns.db.locked and "位置已锁定 · 橙 > 黄 > 绿" or "拖动标题移动 · 橙 > 黄 > 绿"))
    ns.SetScale(ns.db.scale or 1)
    local y = 0
    local professions = ns.professions or {}
    for index, profession in ipairs(professions) do
        local card = getCard(index)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 0, -y)
        y = y + renderCard(card, profession)
    end
    for index = #professions + 1, #cards do cards[index]:Hide() end
    content.empty:SetShown(#professions == 0)
    if #professions == 0 then
        content.empty:SetText(ns.detectReady == false and "正在读取本角色的商业技能…\n进入世界后会自动刷新。" or "本角色尚未学习商业技能。\n向训练师学习后，会自动显示在这里。")
        y = labelHeight(content.empty) + 24
    end
    contentHeight = math.max(1, y)
    viewHeight = math.min(MAX_VIEW_HEIGHT, math.max(72, contentHeight))
    content:SetHeight(contentHeight)
    scroll:SetHeight(viewHeight)
    bar:SetHeight(math.max(30, viewHeight - 4))
    settingScroll = true
    bar:SetMinMaxValues(0, math.max(0, contentHeight - viewHeight))
    settingScroll = false
    setScroll(scroll:GetVerticalScroll())
    scroll:SetShown(not ns.db.collapsed)
    bar:SetShown(not ns.db.collapsed and contentHeight > viewHeight)
    panel:SetHeight(ns.db.collapsed and 78 or viewHeight + 88)
end

function ns.CreateUI()
    if panel then return panel end
    panel = CreateFrame("Frame", "MyForeverProfessionsPanel", UIParent, "BackdropTemplate")
    ns.frame = panel
    panel:SetWidth(WIDTH)
    panel:SetHeight(160)
    panel:SetPoint(ns.db.point or "CENTER", UIParent, ns.db.relativePoint or "CENTER", ns.db.x or 300, ns.db.y or 0)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", wheel)
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.035, 0.045, 0.055, 0.94)
    panel:SetBackdropBorderColor(0.53, 0.44, 0.28, 0.8)
    panel.title = text(panel, 176, "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 13, -13)
    panel.title:SetText("商业技能助手")
    panel.title:SetTextColor(0.94, 0.82, 0.57)
    local drag = CreateFrame("Frame", nil, panel)
    panel.drag = drag
    drag:SetPoint("TOPLEFT", 4, -4)
    drag:SetSize(220, 30)
    drag:EnableMouse(true)
    drag:EnableMouseWheel(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnMouseWheel", wheel)
    drag:SetScript("OnDragStart", function() if not ns.db.locked then panel:StartMoving() end end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing(); savePosition() end)
    local refresh = button(panel, "刷新", 39, function() if ns.Refresh then ns.Refresh(true) end end)
    refresh:SetPoint("TOPRIGHT", -84, -7)
    lockButton = button(panel, "锁定", 39, function()
        panel:StopMovingOrSizing()
        ns.db.locked = not ns.db.locked
        ns.RenderUI()
    end)
    lockButton:SetPoint("TOPRIGHT", -44, -7)
    collapseButton = button(panel, "-", 26, function() ns.db.collapsed = not ns.db.collapsed; ns.RenderUI() end)
    collapseButton:SetPoint("TOPRIGHT", -12, -7)
    panel.controls = { refresh = refresh, lock = lockButton, collapse = collapseButton }
    summary = text(panel, WIDTH - 28)
    panel.summary = summary
    summary:SetPoint("TOPLEFT", 14, -37)
    summary:SetTextColor(0.58, 0.63, 0.68)
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 15, -58)
    scroll:SetWidth(CONTENT_WIDTH)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(CONTENT_WIDTH)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    content.empty = text(content, CONTENT_WIDTH)
    content.empty:SetPoint("TOPLEFT", 0, -9)
    bar = CreateFrame("Slider", nil, panel)
    bar:SetPoint("TOPRIGHT", -12, -60)
    bar:SetWidth(9)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(1)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetThumbTexture():SetSize(7, 26)
    bar:GetThumbTexture():SetVertexColor(0.61, 0.53, 0.36, 0.7)
    bar:SetScript("OnValueChanged", function(_, value) if not settingScroll then setScroll(value) end end)
    footer = text(panel, WIDTH - 100)
    footer:SetPoint("BOTTOMLEFT", 15, 10)
    footer:SetTextColor(0.54, 0.6, 0.65)
    local minus = button(panel, "-", 24, function() ns.SetScale((ns.db.scale or 1) - 0.05) end)
    minus:SetPoint("BOTTOMRIGHT", -43, 4)
    local plus = button(panel, "+", 24, function() ns.SetScale((ns.db.scale or 1) + 0.05) end)
    plus:SetPoint("BOTTOMRIGHT", -15, 4)
    panel.controls.minus, panel.controls.plus = minus, plus
    panel.cards, panel.scroll, panel.content, panel.scrollbar = cards, scroll, content, bar
    ns.RenderUI()
    return panel
end
