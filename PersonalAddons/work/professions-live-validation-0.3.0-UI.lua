local _, ns = ...

local WIDTH, CONTENT_WIDTH, MAX_VIEW_HEIGHT = 372, 330, 378
local palette = {
    orange = { 1, 0.49, 0.18, "橙" }, yellow = { 1, 0.83, 0.25, "黄" },
    green = { 0.35, 0.84, 0.45, "绿" }, gray = { 0.58, 0.6, 0.62, "灰" },
    unknown = { 0.7, 0.72, 0.75, "?" },
}
local selected, cards = {}, {}
local expandedID
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

local function amount(value)
    return number(value) and tostring(math.max(0, math.floor(value))) or "?"
end

local function itemLink(reagent)
    local id = reagent and reagent.itemID
    local name = type(reagent and reagent.name) == "string" and reagent.name:gsub("|", "") or nil
    if not number(id) or id <= 0 or id ~= math.floor(id) then
        return nil, name or "材料名称读取中"
    end
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    if info then
        local ok, cachedName, link = pcall(info, id)
        if ok and type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) == id then
            return link, cachedName or name
        end
    end
    -- item:<id> is a valid native link even before the item cache is populated.
    name = name or ("物品 " .. id)
    return "|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r", name
end

local function hideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

local function hideOwnedTooltip(self)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function showMaterialTooltip(self)
    if not self.itemLink or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
    if ok then
        GameTooltip:AddLine("Shift + 左键：填入当前输入框", 0.9, 0.78, 0.51)
        GameTooltip:Show()
    else GameTooltip:Hide() end
end

local function clickMaterial(self, mouseButton)
    if mouseButton ~= "LeftButton" or not self.itemLink then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        if ns.InsertMaterialLink and not ns.InsertMaterialLink(self.itemLink, self.itemName) then
            if ns.Print then ns.Print("请先选中输入框并留出足够空间，再 Shift 点击材料。") end
        end
        return
    end
    if SetItemRef then
        local payload = self.itemLink:match("|H(item:[^|]+)|h")
        if payload then pcall(SetItemRef, payload, self.itemLink, mouseButton, self) end
    end
end

local function getMaterialRow(card, index)
    if card.materialRows[index] then return card.materialRows[index] end
    local row = button(card.details, "", CONTENT_WIDTH - 12, clickMaterial)
    row.label:SetJustifyH("LEFT")
    row.label:SetJustifyV("TOP")
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 0, 0)
    row.label:SetWidth(CONTENT_WIDTH - 18)
    row.counts = text(row, CONTENT_WIDTH - 18)
    row.counts:SetTextColor(0.69, 0.74, 0.77)
    row:SetScript("OnEnter", showMaterialTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnHide", hideOwnedTooltip)
    card.materialRows[index] = row
    return row
end

local function getCard(index)
    if cards[index] then return cards[index] end
    local card = CreateFrame("Frame", nil, content)
    card:SetWidth(CONTENT_WIDTH)
    card.header = button(card, "", CONTENT_WIDTH, function()
        if expandedID == card.professionID then expandedID = nil
        else expandedID = card.professionID end
        ns.RenderUI()
    end)
    local header = card.header
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetHeight(42)
    header.bg = header:CreateTexture(nil, "BACKGROUND", nil, 0)
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0.075, 0.09, 0.11, 0.96)
    header.fill = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    header.fill:SetPoint("TOPLEFT", 1, -1)
    header.fill:SetHeight(40)
    header.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    header.fill:SetVertexColor(0.2, 0.48, 0.7, 0.56)
    header.rule = header:CreateTexture(nil, "ARTWORK")
    header.rule:SetPoint("BOTTOMLEFT", 0, 0)
    header.rule:SetSize(CONTENT_WIDTH, 1)
    header.rule:SetColorTexture(0.55, 0.48, 0.33, 0.35)
    header.icon = header:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(24, 24)
    header.icon:SetPoint("LEFT", 9, 0)
    header.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    header.label:ClearAllPoints()
    header.label:SetPoint("LEFT", 43, 0)
    header.label:SetWidth(CONTENT_WIDTH - 150)
    header.label:SetJustifyH("LEFT")
    header.label:SetTextColor(0.93, 0.86, 0.7)
    header.rank = text(header, 82)
    header.rank:SetPoint("RIGHT", -27, 0)
    header.rank:SetJustifyH("RIGHT")
    header.rank:SetJustifyV("MIDDLE")
    header.rank:SetTextColor(0.81, 0.86, 0.9)
    header.toggle = text(header, 16)
    header.toggle:SetPoint("RIGHT", -7, 0)
    header.toggle:SetJustifyH("CENTER")
    header.toggle:SetJustifyV("MIDDLE")
    header.toggle:SetTextColor(0.77, 0.68, 0.48)
    card.details = CreateFrame("Frame", nil, card)
    card.details:SetPoint("TOPLEFT", 6, -49)
    card.details:SetWidth(CONTENT_WIDTH - 12)
    card.open = button(card.details, "打开专业", 72, function()
        if not card.unlearned and ns.OpenProfession and card.professionID then
            ns.OpenProfession(card.professionID)
        end
    end)
    card.open:SetPoint("TOPRIGHT", 0, 0)
    card.progress = text(card.details, CONTENT_WIDTH - 94)
    card.progress:SetPoint("TOPLEFT", 0, -2)
    card.progress:Hide()
    card.trainer = button(card.details, "", CONTENT_WIDTH - 94, function()
        if card.trainer.record and ns.ShowTrainerOnMap then
            local record = card.trainer.record
            local ok, mode = ns.ShowTrainerOnMap(record)
            if ns.Print and not ok then
                ns.Print(mode or "暂时无法打开地图")
            elseif ns.Print and mode == "map" then
                ns.Print(string.format("已打开%s地图，请按 %.1f, %.1f 查找训练师。", record.mapName or "", record.x * 100, record.y * 100))
            end
        end
    end)
    card.trainer:SetPoint("TOPLEFT", 0, 0)
    card.trainer.label:SetJustifyH("LEFT")
    card.trainer.label:SetJustifyV("TOP")
    card.trainer.label:ClearAllPoints()
    card.trainer.label:SetPoint("TOPLEFT", 0, -2)
    card.trainer:SetScript("OnEnter", function(self)
        local record = self.record
        if not GameTooltip or not record then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record.name or "专业训练师")
        if record.subName then GameTooltip:AddLine(record.subName, 0.8, 0.8, 0.8) end
        if record.scope then GameTooltip:AddLine(record.scope, 0.7, 0.75, 0.78) end
        GameTooltip:AddLine(string.format("%s %.1f, %.1f", record.mapName or "地图", record.x * 100, record.y * 100), 1, 0.85, 0.55)
        if number(record.distance) then
            GameTooltip:AddLine(string.format("直线距离约 %d 米", math.floor(record.distance + 0.5)), 0.75, 0.8, 0.84)
        end
        GameTooltip:AddLine("点击查看地图位置", 0.9, 0.78, 0.51)
        GameTooltip:AddLine("可学内容以训练师窗口为准。", 0.65, 0.7, 0.73)
        GameTooltip:Show()
    end)
    card.trainer:SetScript("OnLeave", hideTooltip)
    card.trainer:SetScript("OnHide", hideOwnedTooltip)
    card.note = text(card.details, CONTENT_WIDTH - 12)
    card.note:SetTextColor(0.65, 0.69, 0.72)
    card.choices = {}
    for choice = 1, 3 do
        local row = button(card.details, "", CONTENT_WIDTH - 12, function(self)
            selected[card.professionID] = self.recipeKey
            ns.RenderUI()
        end)
        row.label:SetJustifyH("LEFT")
        row.label:SetWidth(CONTENT_WIDTH - 20)
        row:SetScript("OnEnter", function(self)
            if GameTooltip and self.recipeName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.recipeName)
                GameTooltip:AddLine("点击查看这项训练的材料", 0.75, 0.78, 0.8)
                if self.cacheState == "stale" then
                    GameTooltip:AddLine("上次记录，打开专业可更新难度。", 0.75, 0.7, 0.6)
                end
                if self.scopeNote then GameTooltip:AddLine(self.scopeNote, 0.7, 0.72, 0.75) end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", hideTooltip)
        card.choices[choice] = row
    end
    card.materialTitle = text(card.details, CONTENT_WIDTH - 12)
    card.materialTitle:SetTextColor(0.75, 0.79, 0.82)
    card.materials = text(card.details, CONTENT_WIDTH - 12)
    card.materials:SetTextColor(0.7, 0.75, 0.78)
    card.materialRows = {}
    cards[index] = card
    return card
end

local function materialCount(required, owned, missing)
    if not number(missing) and number(required) and number(owned) then missing = math.max(0, required - owned) end
    local color = number(missing) and missing > 0 and "|cffffb080" or "|cffb9dfc1"
    return "需 " .. amount(required) .. " / 有 " .. amount(owned) .. " / " .. color .. "缺 " .. amount(missing) .. "|r"
end

local function renderMaterials(card, recipe, y)
    local count = 0
    local function add(reagent, required, option)
        count = count + 1
        local row = getMaterialRow(card, count)
        local oldLink = row.itemLink
        local hovered = GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row)
        row.itemLink, row.itemName = itemLink(reagent)
        row.label:SetText((option and "任选  " or "") .. (row.itemLink or row.itemName))
        row.counts:SetText(materialCount(required, reagent.owned, reagent.missing))
        row.counts:ClearAllPoints()
        row.counts:SetPoint("TOPLEFT", 0, -labelHeight(row.label))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        local height = labelHeight(row.label) + labelHeight(row.counts) + 6
        row:SetHeight(height)
        row:SetShown(true)
        row:EnableMouse(row.itemLink ~= nil)
        if hovered and oldLink ~= row.itemLink then
            if row.itemLink then showMaterialTooltip(row) else hideOwnedTooltip(row) end
        end
        y = y + height + 3
    end
    for _, reagent in ipairs(recipe.reagents or {}) do
        if reagent.options and #reagent.options > 0 then
            for _, option in ipairs(reagent.options) do add(option, reagent.required, #reagent.options > 1) end
        else
            add(reagent, reagent.required, false)
        end
    end
    for index = count + 1, #card.materialRows do card.materialRows[index]:Hide() end
    return y, count
end

local function renderCard(card, profession)
    card:Show()
    card.professionID, card.unlearned = profession.id, profession.unlearned == true
    local header = card.header
    header.icon:SetTexture(profession.icon or "Interface\\Icons\\INV_Misc_Book_09")
    header.label:SetText(profession.name or "商业技能")
    local rank, maximum = profession.rank, profession.maxRank
    local valid = not card.unlearned and number(rank) and rank >= 0 and number(maximum) and maximum > 0
    local fraction = valid and math.max(0, math.min(1, rank / maximum)) or 0
    header.fill:SetShown(fraction > 0)
    header.fill:SetWidth(math.max(1, (CONTENT_WIDTH - 2) * fraction))
    header.fill:SetVertexColor(valid and rank >= maximum and 0.68 or 0.2,
        valid and rank >= maximum and 0.52 or 0.48, valid and rank >= maximum and 0.2 or 0.7, 0.56)
    header.rank:SetText(card.unlearned and "未学习" or (valid and amount(rank) .. " / " .. amount(maximum) or "读取中"))
    header.label:SetTextColor(card.unlearned and 0.63 or 0.93, card.unlearned and 0.66 or 0.86, card.unlearned and 0.69 or 0.7)
    local expanded = expandedID == profession.id
    header.toggle:SetText(expanded and "-" or "+")
    card.details:SetShown(expanded)
    if not expanded then
        for _, row in ipairs(card.materialRows) do row:Hide() end
        card:SetHeight(48)
        return 48
    end
    card.progress:Hide()
    card.open:SetShown(not card.unlearned)
    local trainer, trainerReason
    if ns.GetNearbyTrainer then trainer, trainerReason = ns.GetNearbyTrainer(profession.id) end
    card.trainer.record = trainer
    if trainer then
        card.trainer.label:SetText("训练师：" .. (trainer.name or "未知") .. "\n" .. (trainer.mapName or "地图")
            .. string.format(" %.1f, %.1f", trainer.x * 100, trainer.y * 100))
    else
        card.trainer.label:SetText(trainerReason or "训练师位置加载中")
    end
    card.trainer:SetHeight(labelHeight(card.trainer.label, 23) + 4)
    local y = math.max(25, card.trainer:GetHeight()) + 7
    local recipes = profession.recipes or {}
    local capped = valid and rank >= maximum
    local notes = {}
    if card.unlearned then
        notes[#notes + 1] = "尚未学习" .. (profession.name or "该专业") .. "，请向对应训练师学习。学习后自动显示真实技能点与可用项目。"
    else
        if capped then
            notes[#notes + 1] = "已到当前技能上限；可向训练师查看下一阶段。"
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
    end
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", 0, -y)
    card.note:SetText(table.concat(notes, "\n"))
    card.note:SetShown(#notes > 0)
    if #notes > 0 then y = y + labelHeight(card.note) + 6 end
    local chosen, count = nil, (capped or card.unlearned) and 0 or math.min(3, #recipes)
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
            local stock = not recipe.isGatheringRecipe and number(recipe.craftable) and (" · 材料可做 " .. amount(recipe.craftable) .. " 次") or ""
            row.label:SetText(prefix .. (recipe.name or "训练项目") .. stock)
            row.label:SetTextColor(color[1], color[2], color[3])
            row:SetHeight(labelHeight(row.label, 20) + 4)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.recipeKey, row.recipeName = recipe.id or recipe.name or index, recipe.name
            row.cacheState, row.scopeNote = profession.cacheState, profession.status
            y = y + row:GetHeight() + 2
        end
    end
    card.materialTitle:Hide()
    card.materials:SetShown(chosen ~= nil)
    if not chosen or recipes[chosen].isGatheringRecipe then
        for _, row in ipairs(card.materialRows) do row:Hide() end
    end
    if chosen then
        local recipe = recipes[chosen]
        y = y + 5
        local current, target = recipe.currentRecipeExperience, recipe.nextLevelRecipeExperience
        local experience = number(current) and number(target) and target > 0 and current >= 0 and target >= current
            and ("项目升下一级还差 " .. amount(target - current) .. " 熟练度") or nil
        local details = {}
        if experience then details[#details + 1] = experience end
        if recipe.isGatheringRecipe then
            details[#details + 1] = "前往对应资源点进行采集；升级以游戏实际结果为准。"
        else
            local rows
            y, rows = renderMaterials(card, recipe, y)
            if rows == 0 then
                details[#details + 1] = recipe.reagentsComplete == true and "此项目没有需消耗的制造材料。" or "材料尚未读取完整，请打开该专业刷新。"
            elseif recipe.reagentsComplete == false then
                details[#details + 1] = "部分材料待读取，请在专业窗口核对。"
            end
        end
        card.materials:ClearAllPoints()
        card.materials:SetPoint("TOPLEFT", 0, -y)
        card.materials:SetText(table.concat(details, "\n"))
        card.materials:SetShown(#details > 0)
        if #details > 0 then y = y + labelHeight(card.materials) + 5 end
    end
    card.details:SetHeight(y + 7)
    card:SetHeight(49 + y + 13)
    return 49 + y + 13
end

function ns.RenderUI()
    if not panel then return end
    panel:SetShown(ns.db.shown ~= false)
    lockButton.label:SetText(ns.db.locked and "解锁" or "锁定")
    collapseButton.label:SetText(ns.db.collapsed and "+" or "-")
    summary:SetText(ns.combatPaused and "战斗中 · 数据暂停" or (ns.db.locked and "位置已锁定 · 橙 > 黄 > 绿" or "拖动标题移动 · 橙 > 黄 > 绿"))
    ns.SetScale(ns.db.scale or 1)
    local y = 0
    local professions = ns.DisplayProfessions and ns.DisplayProfessions(ns.professions, ns.detectReady) or ns.professions or {}
    local stillPresent = false
    for _, profession in ipairs(professions) do if profession.id == expandedID then stillPresent = true end end
    if not stillPresent then expandedID = nil end
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
