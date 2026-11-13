local _, ns = ...

local size = ns.PanelSize
local WIDTH, CONTENT_WIDTH = size.defaultWidth, size.defaultWidth - 42
local palette = {
    orange = { 1, 0.49, 0.18, "橙" }, yellow = { 1, 0.83, 0.25, "黄" },
    green = { 0.35, 0.84, 0.45, "绿" }, gray = { 0.58, 0.6, 0.62, "灰" },
    unknown = { 0.7, 0.72, 0.75, "?" },
}
local selected, cards = {}, {}
local expandedID, activeProfessionID
local trainerLookupID, trainerPinsHidden
local panel, collapsedIcon, scroll, content, bar, summary, footer, lockButton, resizeGrip
local resizing, titleDragging, rendering, hiding
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

local function fontSize(label, size)
    local font = label:GetFont()
    if font then label:SetFont(font, size, "") end
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
    b.label:SetTextColor(0.72, 0.76, 0.79)
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

local function restorePosition(frame, offsetScale)
    offsetScale = offsetScale or 1
    frame:ClearAllPoints()
    frame:SetPoint(ns.db.point or "CENTER", UIParent, ns.db.relativePoint or "CENTER",
        (ns.db.x or 300) * offsetScale, (ns.db.y or 0) * offsetScale)
end

local function savePosition(frame, offsetScale)
    local point, _, relativePoint, x, y = frame:GetPoint()
    if type(point) == "string" and type(relativePoint) == "string" and number(x) and number(y) then
        offsetScale = offsetScale or 1
        ns.db.point, ns.db.relativePoint = point, relativePoint
        ns.db.x, ns.db.y = x * offsetScale, y * offsetScale
    end
end

local function finishTitleDrag()
    if not titleDragging then return end
    panel:StopMovingOrSizing()
    titleDragging = false
    panel.drag:SetScript("OnUpdate", nil)
    savePosition(panel)
end

local function physicalTopLeft()
    local scale, left, top = panel:GetEffectiveScale(), panel:GetLeft(), panel:GetTop()
    if number(scale) and scale > 0 and number(left) and number(top) then return left * scale, top * scale end
end

local function retainTopLeft(left, top)
    if not number(left) or not number(top) then return end
    local point, relative, relativePoint, x, y = panel:GetPoint()
    local scale, newLeft, newTop = panel:GetEffectiveScale(), panel:GetLeft(), panel:GetTop()
    if scale > 0 and number(newLeft) and number(newTop) then
        panel:ClearAllPoints()
        panel:SetPoint(point, relative, relativePoint,
            x + (left - newLeft * scale) / scale, y + (top - newTop * scale) / scale)
        savePosition(panel)
    end
end

local function applyWindowSize(width, height)
    local scale = panel and panel:GetScale() or ns.db.scale or 1
    local maxWidth = math.min(size.maxWidth, UIParent:GetWidth() / scale)
    local maxHeight = math.min(size.maxHeight, UIParent:GetHeight() / scale)
    maxWidth, maxHeight = math.max(1, math.floor(maxWidth)), math.max(97, math.floor(maxHeight))
    width = math.floor(math.max(math.min(size.minWidth, maxWidth), math.min(maxWidth, width)) + 0.5)
    height = math.floor(math.max(math.min(size.minHeight, maxHeight), math.min(maxHeight, height)) + 0.5)
    local left, top
    if panel and (panel:GetWidth() ~= width or panel:GetHeight() ~= height) and (panel:IsShown() or resizing or hiding) then
        left, top = physicalTopLeft()
    end
    ns.db.windowWidth, ns.db.windowHeight = width, height
    WIDTH, CONTENT_WIDTH = width, width - 42
    if panel then
        panel:SetSize(width, height)
        retainTopLeft(left, top)
        if footer then footer:SetText(string.format("%d × %d", width, height)) end
    end
end

function ns.SetWindowSize(width, height)
    if not number(width) or not number(height) then return end
    applyWindowSize(width, height)
    if panel and not rendering and not hiding then ns.RenderUI() end
end

function ns.SetScale(value)
    if not number(value) then return end
    local previousScale = ns.db.scale
    ns.db.scale = math.floor(math.max(0.65, math.min(1.60, value)) * 100 + 0.5) / 100
    if panel then
        local left, top
        if previousScale ~= ns.db.scale and (panel:IsShown() or resizing) then
            local effectiveScale = panel:GetEffectiveScale()
            left, top = panel:GetLeft(), panel:GetTop()
            if number(left) and number(top) then left, top = left * effectiveScale, top * effectiveScale end
        end
        panel:SetScale(ns.db.scale)
        if previousScale ~= ns.db.scale and collapsedIcon:IsShown() then
            savePosition(collapsedIcon, 1 / ns.db.scale)
            restorePosition(panel)
        elseif number(left) and number(top) then
            -- Offsets remain in panel units, regardless of its saved anchor.
            -- Compensating after scaling fixes the physical upper-left corner.
            local point, relative, relativePoint, x, y = panel:GetPoint()
            local scale = panel:GetEffectiveScale()
            local newLeft, newTop = panel:GetLeft(), panel:GetTop()
            if scale > 0 and number(newLeft) and number(newTop) then
                panel:ClearAllPoints()
                panel:SetPoint(point, relative, relativePoint,
                    x + (left - newLeft * scale) / scale, y + (top - newTop * scale) / scale)
                savePosition(panel)
            end
        end
        footer:SetText(string.format("%d × %d", ns.db.windowWidth or size.defaultWidth, ns.db.windowHeight or size.defaultHeight))
    end
end

local function wheel(_, delta)
    if IsControlKeyDown and IsControlKeyDown() then
        ns.SetWindowSize((ns.db.windowWidth or size.defaultWidth) + delta * 32,
            (ns.db.windowHeight or size.defaultHeight) + delta * 32)
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

local function auxiliary(control, title, explanation)
    control.label:SetTextColor(0.68, 0.73, 0.77)
    control:SetScript("OnEnter", function(self)
        self.label:SetTextColor(0.96, 0.85, 0.63)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if explanation then GameTooltip:AddLine(explanation, 0.75, 0.79, 0.82, true) end
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.68, 0.73, 0.77)
        hideOwnedTooltip(self)
    end)
    control:SetScript("OnHide", hideOwnedTooltip)
end

local function resizeToCursor(state)
    state = state or resizing
    if not state then return end
    local x, y = GetCursorPosition()
    if not number(x) or not number(y) then return end
    ns.SetWindowSize(state.width + (x - state.x) / state.effectiveScale,
        state.height + (state.y - y) / state.effectiveScale)
end

local function finishResize()
    if not resizing then return end
    local state = resizing
    resizing = nil
    resizeGrip:SetScript("OnUpdate", nil)
    resizeToCursor(state)
    savePosition(panel)
end

function ns.ResetWindowSize()
    finishTitleDrag()
    finishResize()
    ns.SetWindowSize(size.defaultWidth, size.defaultHeight)
end

local function startResize()
    if resizing or not GetCursorPosition then return end
    local x, y = GetCursorPosition()
    local scale, effectiveScale = panel:GetScale(), panel:GetEffectiveScale()
    local width, height = panel:GetWidth(), panel:GetHeight()
    if not number(x) or not number(y) or not number(scale) or scale <= 0
        or not number(effectiveScale) or effectiveScale <= 0 or width <= 0 or height <= 0 then return end
    finishTitleDrag()
    panel:StopMovingOrSizing()
    hideOwnedTooltip(resizeGrip)
    resizing = { x = x, y = y, effectiveScale = effectiveScale, width = width, height = height }
    resizeGrip:SetScript("OnUpdate", function()
        if IsMouseButtonDown and IsMouseButtonDown("LeftButton") == false then finishResize()
        else resizeToCursor() end
    end)
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
    row:SetWidth(CONTENT_WIDTH - 32)
    row.label:SetWidth(CONTENT_WIDTH - 32)
    row.counts = text(row, CONTENT_WIDTH - 32)
    fontSize(row.counts, 13)
    row.counts:SetTextColor(0.91, 0.78, 0.63)
    row:SetScript("OnEnter", showMaterialTooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:SetScript("OnHide", hideOwnedTooltip)
    card.materialRows[index] = row
    return row
end

local function displayProfessions()
    return ns.DisplayProfessions and ns.DisplayProfessions(ns.professions, ns.detectReady) or ns.professions or {}
end

local function canHideTrainerPins(id)
    return trainerLookupID == id and ns.IsTrainerPinVisible and ns.IsTrainerPinVisible(id)
end

local function getCard(index)
    if cards[index] then return cards[index] end
    local card = CreateFrame("Frame", nil, content)
    card:SetWidth(CONTENT_WIDTH)
    card.header = button(card, "", CONTENT_WIDTH, function()
        activeProfessionID = card.professionID
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
    card.progress = text(card.details, CONTENT_WIDTH - 94)
    card.progress:SetPoint("TOPLEFT", 0, -2)
    card.progress:Hide()
    card.trainer = button(card.details, "", CONTENT_WIDTH - 94, function()
        if card.trainer.record and ns.ShowTrainerOnMap then
            local id, record = card.professionID, card.trainer.record
            if canHideTrainerPins(id) then
                trainerLookupID, trainerPinsHidden = nil, true
                ns.ClearTrainerPins()
                hideOwnedTooltip(card.trainer)
                return
            end
            if trainerPinsHidden then
                trainerPinsHidden = false
                if ns.UpdateTrainerPins and not ns.combatPaused then ns.UpdateTrainerPins(displayProfessions(), id) end
            end
            if ns.SelectTrainerPin then ns.SelectTrainerPin(id) end
            local ok, mode = ns.ShowTrainerOnMap(record, ns.HasTrainerPin and ns.HasTrainerPin(id))
            trainerLookupID = ok and mode == "icons" and id or nil
            if ns.Print and not ok then
                ns.Print(mode or "暂时无法打开地图")
            elseif ns.Print and mode == "map" then
                ns.Print(string.format("已打开%s地图，请按 %.1f, %.1f 查找训练师。", record.mapName or "", record.x * 100, record.y * 100))
            end
        end
    end)
    card.trainer.label:SetJustifyH("LEFT")
    card.trainer.label:SetJustifyV("TOP")
    card.trainer.label:ClearAllPoints()
    card.trainer.label:SetPoint("TOPLEFT", 24, -2)
    card.trainer.label:SetWidth(CONTENT_WIDTH - 118)
    card.trainer.label:SetTextColor(0.68, 0.73, 0.77)
    card.trainer.icon = card.trainer:CreateTexture(nil, "ARTWORK")
    card.trainer.icon:SetSize(18, 18)
    card.trainer.icon:SetPoint("TOPLEFT", 0, -1)
    card.trainer.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.trainer:SetScript("OnEnter", function(self)
        self.label:SetTextColor(0.96, 0.85, 0.63)
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
        local action = canHideTrainerPins(card.professionID) and "点击隐藏训练师图标" or "点击查看地图位置"
        GameTooltip:AddLine(action, 0.9, 0.78, 0.51)
        GameTooltip:AddLine("可学内容以训练师窗口为准。", 0.65, 0.7, 0.73)
        GameTooltip:Show()
    end)
    card.trainer:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.68, 0.73, 0.77)
        hideOwnedTooltip(self)
    end)
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
        row.label:SetJustifyV("TOP")
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 10, -24)
        row.label:SetWidth(CONTENT_WIDTH - 34)
        row.role = text(row, CONTENT_WIDTH - 34)
        row.role:SetPoint("TOPLEFT", 10, -6)
        row.role:SetTextColor(0.72, 0.79, 0.84)
        row.stock = text(row, CONTENT_WIDTH - 34)
        row.stock:SetTextColor(0.66, 0.72, 0.76)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.13, 0.20, 0.25, 0.8)
        row.marker = row:CreateTexture(nil, "ARTWORK")
        row.marker:SetPoint("TOPLEFT", 0, -3)
        row.marker:SetWidth(3)
        row.marker:SetColorTexture(0.76, 0.68, 0.44, 1)
        row:SetScript("OnEnter", function(self)
            if GameTooltip and self.recipeName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.recipeName)
                GameTooltip:AddLine("难度：" .. self.difficultyName .. "色", 0.75, 0.79, 0.82)
                GameTooltip:AddLine("点击查看这项训练的材料", 0.75, 0.78, 0.8)
                if self.isGatheringRecipe then
                    GameTooltip:AddLine("前往对应资源点采集；升级以游戏实际结果为准。", 0.7, 0.75, 0.78, true)
                end
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
    card.otherTitle = text(card.details, CONTENT_WIDTH - 12)
    card.otherTitle:SetText("其他可选")
    card.otherTitle:SetTextColor(0.59, 0.66, 0.71)
    card.auxRule = card.details:CreateTexture(nil, "ARTWORK")
    card.auxRule:SetSize(CONTENT_WIDTH - 12, 1)
    card.auxRule:SetColorTexture(0.4, 0.45, 0.49, 0.28)
    cards[index] = card
    return card
end

local function layoutCardWidths(card)
    card:SetWidth(CONTENT_WIDTH)
    card.header:SetWidth(CONTENT_WIDTH)
    card.header.label:SetWidth(CONTENT_WIDTH - 150)
    card.header.rule:SetWidth(CONTENT_WIDTH)
    card.details:SetWidth(CONTENT_WIDTH - 12)
    card.progress:SetWidth(CONTENT_WIDTH - 12)
    card.trainer:SetWidth(CONTENT_WIDTH - 12)
    card.trainer.label:SetWidth(CONTENT_WIDTH - 42)
    for _, label in ipairs({ card.note, card.materialTitle, card.materials, card.otherTitle }) do
        label:SetWidth(CONTENT_WIDTH - 12)
    end
    card.auxRule:SetWidth(CONTENT_WIDTH - 12)
    for _, row in ipairs(card.choices) do
        row:SetWidth(CONTENT_WIDTH - 12)
        row.label:SetWidth(CONTENT_WIDTH - 34)
        row.role:SetWidth(CONTENT_WIDTH - 34)
        row.stock:SetWidth(CONTENT_WIDTH - 34)
    end
    for _, row in ipairs(card.materialRows) do
        row:SetWidth(CONTENT_WIDTH - 32)
        row.label:SetWidth(CONTENT_WIDTH - 32)
        row.counts:SetWidth(CONTENT_WIDTH - 32)
    end
end

local function materialCount(required, owned, missing)
    if not number(missing) and number(required) and number(owned) then missing = math.max(0, required - owned) end
    local color = number(missing) and missing > 0 and "|cffffb080" or "|cffb9dfc1"
    return color .. "缺 " .. amount(missing) .. "|r   |cff9da7af需 " .. amount(required) .. " / 有 " .. amount(owned) .. "|r"
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
        row:SetPoint("TOPLEFT", 10, -y)
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

local function renderChoice(row, recipe, isCurrent, role, y)
    local color = palette[recipe.difficulty] or palette.unknown
    row.bg:SetShown(isCurrent)
    row.marker:SetShown(isCurrent)
    row.role:SetShown(isCurrent)
    row.role:SetText(role)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", 10, isCurrent and -25 or -6)
    row.label:SetText(recipe.name or "训练项目")
    fontSize(row.label, isCurrent and 14 or 12)
    local strength = isCurrent and 1 or 0.83
    row.label:SetTextColor(color[1] * strength, color[2] * strength, color[3] * strength)
    local height = (isCurrent and 25 or 6) + labelHeight(row.label)
    local stock = not recipe.isGatheringRecipe and number(recipe.craftable)
    row.stock:SetShown(stock)
    if stock then
        row.stock:ClearAllPoints()
        row.stock:SetPoint("TOPLEFT", 10, -height)
        row.stock:SetText("材料可做 " .. amount(recipe.craftable) .. " 次")
        height = height + labelHeight(row.stock)
    end
    height = height + 7
    row:SetHeight(height)
    row.marker:SetHeight(height - 6)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    return y + height + 6
end

local function renderCard(card, profession)
    layoutCardWidths(card)
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
    local trainer, trainerReason
    if ns.GetNearbyTrainer then trainer, trainerReason = ns.GetNearbyTrainer(profession.id) end
    card.trainer.record = trainer
    card.trainer.icon:SetTexture(ns.ProfessionIcon and ns.ProfessionIcon(profession.id, profession.icon) or profession.icon)
    card.trainer.icon:SetShown(trainer ~= nil)
    if trainer then
        card.trainer.label:SetText("训练师：" .. (trainer.name or "未知") .. "\n" .. (trainer.mapName or "地图")
            .. string.format(" %.1f, %.1f", trainer.x * 100, trainer.y * 100))
    else
        card.trainer.label:SetText(trainerReason or "训练师位置加载中")
    end
    card.trainer:SetHeight(labelHeight(card.trainer.label, 28) + 4)
    local y = 0
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
    local explicitlySelected = chosen ~= nil
    chosen = chosen or (count > 0 and 1 or nil)
    for index, row in ipairs(card.choices) do
        local recipe = index <= count and recipes[index] or nil
        row:SetShown(recipe ~= nil)
        if recipe then
            row.recipeKey, row.recipeName = recipe.id or recipe.name or index, recipe.name
            row.cacheState, row.scopeNote = profession.cacheState, profession.status
            row.isGatheringRecipe = recipe.isGatheringRecipe
            row.difficultyName = (palette[recipe.difficulty] or palette.unknown)[4]
        end
    end
    if chosen then
        y = renderChoice(card.choices[chosen], recipes[chosen], true, explicitlySelected and "当前选择" or "推荐训练", y)
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
        if not recipe.isGatheringRecipe then
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
    card.otherTitle:SetShown(count > 1)
    if count > 1 then
        y = y + 7
        card.otherTitle:ClearAllPoints()
        card.otherTitle:SetPoint("TOPLEFT", 10, -y)
        y = y + labelHeight(card.otherTitle) + 2
        -- Data indices retain the original orange/yellow/green ordering; only
        -- the current row is promoted above its material details.
        for index = 1, count do
            if index ~= chosen then y = renderChoice(card.choices[index], recipes[index], false, "", y) end
        end
    end
    y = y + 9
    card.auxRule:ClearAllPoints()
    card.auxRule:SetPoint("TOPLEFT", 0, -y)
    y = y + 10
    card.trainer:ClearAllPoints()
    card.trainer:SetPoint("TOPLEFT", 0, -y)
    y = y + math.max(25, card.trainer:GetHeight()) + 3
    card.details:SetHeight(y + 7)
    card:SetHeight(49 + y + 13)
    return 49 + y + 13
end

function ns.RenderUI()
    if not panel or rendering then return end
    rendering = true
    local visible, collapsed = ns.db.shown ~= false, ns.db.collapsed == true
    if not visible or collapsed then finishTitleDrag(); finishResize() end
    if visible and collapsed and not collapsedIcon:IsShown() then
        -- The launcher uses UIParent scale while the saved panel offsets use panel scale.
        restorePosition(collapsedIcon, ns.db.scale or 1)
    end
    panel:SetShown(visible and not collapsed)
    collapsedIcon:SetShown(visible and collapsed)
    lockButton.label:SetText(ns.db.locked and "解锁" or "锁定")
    ns.SetScale(ns.db.scale or 1)
    applyWindowSize(ns.db.windowWidth or size.defaultWidth, ns.db.windowHeight or size.defaultHeight)
    panel.drag:SetWidth(math.max(100, math.min(200, WIDTH - 172)))
    summary:SetWidth(WIDTH - 140)
    footer:SetWidth(WIDTH - 120)
    scroll:SetWidth(CONTENT_WIDTH)
    content:SetWidth(CONTENT_WIDTH)
    content.empty:SetWidth(CONTENT_WIDTH)
    for _, card in ipairs(cards) do layoutCardWidths(card) end
    local y = 0
    local professions = displayProfessions()
    local active
    for _, profession in ipairs(professions) do if profession.id == activeProfessionID then active = profession end end
    local open = panel.controls.open
    open.professionID = active and not active.unlearned and active.id or nil
    open.professionName = active and active.name
    open:SetEnabled(open.professionID ~= nil)
    open.label:SetTextColor(open.professionID and 0.68 or 0.48, open.professionID and 0.73 or 0.52, open.professionID and 0.77 or 0.56)
    open.explanation = not active and "先点击一个专业标题，再打开该专业的原生技能页。"
        or (active.unlearned and "尚未学习该专业，请先向训练师学习。" or "打开所选专业的原生技能页，更新已学项目与材料。")
    summary:SetText(ns.combatPaused and "战斗中 · 数据暂停"
        or (not active and "先点击一个专业" or (active.unlearned and "未学习：" or "当前：") .. (active.name or "商业技能")))
    if not trainerPinsHidden and ns.UpdateTrainerPins and not ns.combatPaused then
        ns.UpdateTrainerPins(professions, expandedID)
    end
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
    viewHeight = ns.db.windowHeight - 96
    content:SetHeight(contentHeight)
    scroll:SetHeight(viewHeight)
    bar:SetHeight(math.max(30, viewHeight - 4))
    settingScroll = true
    bar:SetMinMaxValues(0, math.max(0, contentHeight - viewHeight))
    settingScroll = false
    setScroll(scroll:GetVerticalScroll())
    bar:SetShown(contentHeight > viewHeight)
    rendering = false
end

local function createCollapsedIcon()
    local icon = CreateFrame("Button", "MyForeverProfessionsCollapsedIcon", UIParent, "BackdropTemplate")
    icon:SetSize(42, 42)
    icon:SetScale(1)
    icon:SetFrameStrata("MEDIUM")
    icon:SetClampedToScreen(true)
    icon:SetMovable(true)
    icon:EnableMouse(true)
    -- Match the chat launcher's default jade appearance without depending on it.
    icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    icon:SetBackdropColor(0.42, 0.82, 0.58, 0.98)
    icon:SetBackdropBorderColor(0.42, 0.82, 0.58, 0.98)
    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local font = icon.label:GetFont()
    if font then icon.label:SetFont(font, 12, "") end
    icon.label:SetPoint("CENTER")
    icon.label:SetJustifyH("CENTER")
    icon.label:SetTextColor(0.06, 0.16, 0.10, 1)
    icon.label:SetText("商")
    local dragging, dragged = false, false
    local function finishDrag(self)
        if not dragging then return end
        self:StopMovingOrSizing()
        dragging = false
        self:SetScript("OnUpdate", nil)
        savePosition(self, 1 / (ns.db.scale or 1))
        restorePosition(panel)
    end
    icon:SetScript("OnMouseDown", function(_, mouseButton)
        -- A new press must remain clickable even when the previous drag ended
        -- outside the window and never generated an OnClick.
        if mouseButton == "LeftButton" then dragged = false end
    end)
    icon:SetScript("OnClick", function(_, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if dragging or dragged then return end
        ns.db.collapsed = false
        ns.RenderUI()
    end)
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnDragStart", function(self)
        -- The title lock belongs to the expanded panel. Like the chat launcher,
        -- this compact entry can always be moved directly without a modifier.
        dragging, dragged = true, true
        hideOwnedTooltip(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function(frame)
            if IsMouseButtonDown and IsMouseButtonDown("LeftButton") == false then
                finishDrag(frame)
            end
        end)
    end)
    icon:SetScript("OnDragStop", finishDrag)
    icon:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "LeftButton" then finishDrag(self) end
    end)
    icon:SetScript("OnEnter", function(self)
        self:SetAlpha(0.82)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("商业技能助手")
        GameTooltip:AddLine("左键展开主面板", 0.9, 0.78, 0.51)
        GameTooltip:AddLine("按住左键可拖动图标", 0.75, 0.78, 0.8)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        self:SetAlpha(1)
        hideOwnedTooltip(self)
    end)
    icon:SetScript("OnHide", function(self)
        finishDrag(self)
        dragged = false
        self:SetAlpha(1)
        hideOwnedTooltip(self)
    end)
    icon:Hide()
    return icon
end

function ns.CreateUI()
    if panel then return panel end
    panel = CreateFrame("Frame", "MyForeverProfessionsPanel", UIParent, "BackdropTemplate")
    ns.frame = panel
    panel:SetSize(ns.db.windowWidth or size.defaultWidth, ns.db.windowHeight or size.defaultHeight)
    restorePosition(panel)
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
    drag:SetSize(200, 30)
    drag:EnableMouse(true)
    drag:EnableMouseWheel(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnMouseWheel", wheel)
    drag:SetScript("OnDragStart", function()
        if ns.db.locked then return end
        finishResize()
        titleDragging = true
        panel:StartMoving()
        drag:SetScript("OnUpdate", function()
            if IsMouseButtonDown and IsMouseButtonDown("LeftButton") == false then finishTitleDrag() end
        end)
    end)
    drag:SetScript("OnDragStop", finishTitleDrag)
    drag:SetScript("OnMouseUp", function(_, mouseButton) if mouseButton == "LeftButton" then finishTitleDrag() end end)
    drag:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("商业技能助手")
        GameTooltip:AddLine(ns.db.locked and "标题位置已锁定；右下角仍可调整窗口宽高。" or "拖动标题移动位置。", 0.75, 0.79, 0.82)
        GameTooltip:AddLine("Esc 收起为商字图标；点击专业标题展开项目。", 0.75, 0.79, 0.82)
        GameTooltip:Show()
    end)
    drag:SetScript("OnLeave", hideOwnedTooltip)
    drag:SetScript("OnHide", hideOwnedTooltip)
    local refresh = button(panel, "刷新", 39, function() if ns.Refresh then ns.Refresh(true) end end)
    refresh:SetPoint("TOPRIGHT", -84, -7)
    auxiliary(refresh, "刷新专业数据", "重新读取本角色专业；已学配方需打开原生专业窗口更新。")
    lockButton = button(panel, "锁定", 39, function()
        finishTitleDrag()
        panel:StopMovingOrSizing()
        ns.db.locked = not ns.db.locked
        ns.RenderUI()
    end)
    lockButton:SetPoint("TOPRIGHT", -44, -7)
    auxiliary(lockButton, "标题位置锁定", "只限制标题拖动；商字图标与窗口宽高调整不受影响。")
    local collapseButton = button(panel, "-", 26, function() ns.db.collapsed = true; ns.RenderUI() end)
    collapseButton:SetPoint("TOPRIGHT", -12, -7)
    auxiliary(collapseButton, "收起面板", "收起为商字图标，也可按 Esc 收起。")
    panel.controls = { refresh = refresh, lock = lockButton, collapse = collapseButton }
    if ns.GatherCommand then
        local gather = button(panel, "采集", 39, function() ns.GatherCommand("move") end)
        gather:SetPoint("TOPRIGHT", -125, -7)
        auxiliary(gather, "调整采集提示的位置和大小", "近距离矿草闪光：/myprof sparkle\n开启 on · 关闭 off · 大小 scale 1.2")
        panel.controls.gather = gather
    end
    local open = button(panel, "打开技能书", 104, function(self)
        if self.professionID and ns.OpenProfession then ns.OpenProfession(self.professionID) end
    end)
    open:SetPoint("TOPLEFT", 14, -33)
    open:SetScript("OnEnter", function(self)
        if self.professionID then self.label:SetTextColor(0.96, 0.85, 0.63) end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.professionName and "打开技能书：" .. self.professionName or "打开技能书")
        GameTooltip:AddLine(self.explanation or "先点击一个专业标题。", 0.75, 0.79, 0.82, true)
        GameTooltip:Show()
    end)
    open:SetScript("OnLeave", function(self)
        self.label:SetTextColor(self.professionID and 0.68 or 0.48, self.professionID and 0.73 or 0.52, self.professionID and 0.77 or 0.56)
        hideOwnedTooltip(self)
    end)
    open:SetScript("OnHide", hideOwnedTooltip)
    panel.controls.open = open
    summary = text(panel, WIDTH - 28)
    panel.summary = summary
    summary:SetPoint("TOPLEFT", 127, -39)
    summary:SetTextColor(0.58, 0.63, 0.68)
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 15, -68)
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
    bar:SetPoint("TOPRIGHT", -12, -70)
    bar:SetWidth(9)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 1)
    bar:SetValueStep(1)
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetThumbTexture():SetSize(7, 26)
    bar:GetThumbTexture():SetVertexColor(0.61, 0.53, 0.36, 0.7)
    bar:SetScript("OnValueChanged", function(_, value) if not settingScroll then setScroll(value) end end)
    footer = text(panel, WIDTH - 100)
    panel.footer = footer
    footer:SetPoint("BOTTOMLEFT", 15, 10)
    footer:SetTextColor(0.54, 0.6, 0.65)
    local minus = button(panel, "-", 24, function()
        ns.SetWindowSize(ns.db.windowWidth - 32, ns.db.windowHeight - 32)
    end)
    minus:SetPoint("BOTTOMRIGHT", -60, 4)
    auxiliary(minus, "缩小窗口", "减少窗口宽高，字号保持不变；也可直接拖动右下角手柄。")
    local plus = button(panel, "+", 24, function()
        ns.SetWindowSize(ns.db.windowWidth + 32, ns.db.windowHeight + 32)
    end)
    plus:SetPoint("BOTTOMRIGHT", -32, 4)
    auxiliary(plus, "放大窗口", "增加内容空间，字号保持不变；也可按 Ctrl + 滚轮调整窗口。")
    panel.controls.minus, panel.controls.plus = minus, plus
    resizeGrip = CreateFrame("Button", nil, panel)
    resizeGrip:SetSize(20, 20)
    resizeGrip:SetPoint("BOTTOMRIGHT", -3, 3)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnMouseDown", function(_, mouseButton) if mouseButton == "LeftButton" then startResize() end end)
    resizeGrip:SetScript("OnDragStart", startResize)
    resizeGrip:SetScript("OnDragStop", finishResize)
    resizeGrip:SetScript("OnMouseUp", function(_, mouseButton) if mouseButton == "LeftButton" then finishResize() end end)
    resizeGrip:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("拖动调整窗口宽高")
        GameTooltip:AddLine("向右增加宽度，向下增加高度；字号保持不变。", 0.75, 0.79, 0.82, true)
        GameTooltip:AddLine("也可用底部 − / + 或 Ctrl + 滚轮。", 0.75, 0.79, 0.82)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", hideOwnedTooltip)
    resizeGrip:SetScript("OnHide", function(self) finishResize(); hideOwnedTooltip(self) end)
    panel.controls.resize = resizeGrip
    panel.cards, panel.scroll, panel.content, panel.scrollbar = cards, scroll, content, bar
    collapsedIcon = createCollapsedIcon()
    panel.collapsedIcon = collapsedIcon
    panel:SetScript("OnHide", function(self)
        hiding = true
        finishTitleDrag()
        finishResize()
        -- Ancestor/UIParent hiding also fires OnHide, but leaves this frame's
        -- own shown flag intact. Only a direct Hide (including Esc) collapses.
        if not self:IsShown() and ns.db.shown ~= false and ns.db.collapsed ~= true then
            ns.db.shown, ns.db.collapsed = true, true
            restorePosition(collapsedIcon, ns.db.scale or 1)
            collapsedIcon:Show()
        end
        hiding = false
    end)
    UISpecialFrames = UISpecialFrames or {}
    local registered = false
    for _, name in ipairs(UISpecialFrames) do if name == "MyForeverProfessionsPanel" then registered = true end end
    if not registered then UISpecialFrames[#UISpecialFrames + 1] = "MyForeverProfessionsPanel" end
    ns.RenderUI()
    return panel
end
