local _, ns = ...

local call = ns.SafeCall
local definitions = {
    [171] = {2259, "trade_alchemy", "炼金"},
    [164] = {2018, "trade_blacksmithing", "锻造"},
    [333] = {7411, "trade_engraving", "附魔"},
    [202] = {4036, "trade_engineering", "工程"},
    [165] = {2108, "trade_leatherworking", "制皮"},
    [197] = {3908, "trade_tailoring", "裁缝"},
    [182] = {9134, "trade_herbalism", "草药"},
    [186] = {2575, "trade_mining", "采矿"},
    [393] = {8613, "inv_misc_pelt_wolf_01", "剥皮"},
    [185] = {2550, "inv_misc_food_15", "烹饪"},
    [129] = {3273, "spell_holy_sealofsacrifice", "急救"},
    [356] = {7620, "trade_fishing", "钓鱼"},
}
local owner, pool, active, buttonsByID = {}, {}, {}, {}
local activeLibrary, signature, selectedID, panelSelectedID
local MAX_PROFESSIONS, CLUSTER_RADIUS, SPACING = 5, 0.025, 40
-- HBD: 1 = parent zones, 2 = continent, 3 = continent and world.
local SHOW_ZONE_AND_CONTINENT = 2

local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end
local function texture(value)
    return (number(value) and value > 0) or (type(value) == "string" and value ~= "")
end
function ns.ProfessionIcon(id, supplied)
    if texture(supplied) then return supplied end
    local definition = definitions[id]
    if not definition then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local info = call(C_Spell and C_Spell.GetSpellInfo, definition[1])
    if type(info) == "table" and texture(info.iconID) then return info.iconID end
    return "Interface\\Icons\\" .. definition[2]
end

local function libraries()
    if not LibStub or type(LibStub.GetLibrary) ~= "function" then return nil end
    for _, names in ipairs({{"HereBeDragons-Pins-2.0", "HereBeDragons-2.0"},
        {"HereBeDragonsQuestie-Pins-2.0", "HereBeDragonsQuestie-2.0"}}) do
        local pins = call(LibStub.GetLibrary, LibStub, names[1], true)
        local coordinates = call(LibStub.GetLibrary, LibStub, names[2], true)
        if pins and coordinates and type(pins.AddWorldMapIconMap) == "function"
            and type(pins.RemoveAllWorldMapIcons) == "function"
            and type(coordinates.GetWorldCoordinatesFromZone) == "function" then
            return pins, coordinates
        end
    end
end
local function hideTooltip(button)
    if GameTooltip and call(GameTooltip.IsOwned, GameTooltip, button) then call(GameTooltip.Hide, GameTooltip) end
end
local function style(button)
    local selected = button.professionID == selectedID
    button:SetSize(28, 28)
    local visible = call(button.IsVisible, button) == true
    if selected and visible and button.blink then
        if not button.blink:IsPlaying() then button:SetAlpha(1); button.blink:Play() end
    else
        if button.blink then button.blink:Stop() end
        button:SetAlpha(1)
    end
end
function ns.SelectTrainerPin(id)
    selectedID = definitions[id] and id or nil
    for _, button in pairs(buttonsByID) do style(button) end
end
function ns.HasTrainerPin(id)
    return buttonsByID[id] ~= nil
end
function ns.IsTrainerPinVisible(id)
    local button = buttonsByID[id]
    return button ~= nil and call(button.IsVisible, button) == true
end

local function makeButton(anchor)
    local button = CreateFrame("Button", nil, anchor)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints(button)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if type(button.CreateAnimationGroup) == "function" then
        button.blink = button:CreateAnimationGroup()
        button.blink:SetLooping("REPEAT")
        local fadeOut = button.blink:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.45)
        fadeOut:SetDuration(0.8)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = button.blink:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.45)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.8)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("IN_OUT")
        button.blink:SetScript("OnStop", function() button:SetAlpha(1) end)
    end
    button:SetScript("OnEnter", function(self)
        local record = self.record
        if not record or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((self.professionName or "专业") .. "训练师")
        GameTooltip:AddLine(record.name or "训练师", 1, 0.87, 0.55)
        GameTooltip:AddLine(string.format("%s %.1f, %.1f", record.mapName or "地图", record.x * 100, record.y * 100), 0.85, 0.9, 0.95)
        if self.unlearned then GameTooltip:AddLine("尚未学习该专业", 0.75, 0.78, 0.82) end
        GameTooltip:AddLine("点击闪烁定位", 0.9, 0.78, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnShow", style)
    button:SetScript("OnHide", function(self)
        hideTooltip(self)
        if self.blink then self.blink:Stop() end
        self:SetAlpha(1)
    end)
    button:SetScript("OnClick", function(self)
        ns.SelectTrainerPin(self.professionID)
        local record = self.record
        if record then
            local ok, mode = call(ns.ShowTrainerOnMap, record, true)
            if not ok then
                call(ns.Print, mode or "暂时无法打开地图")
            elseif mode == "map" then
                call(ns.Print, string.format("已打开%s地图，请按 %.1f, %.1f 查找训练师。",
                    record.mapName or "", record.x * 100, record.y * 100))
            end
        end
    end)
    return button
end
local function anchorAt(index)
    if not pool[index] then
        local anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetSize(1, 1)
        anchor:EnableMouse(false)
        anchor.buttons = {}
        anchor:Hide()
        pool[index] = anchor
    end
    return pool[index]
end
function ns.ClearTrainerPins()
    if activeLibrary then call(activeLibrary.RemoveAllWorldMapIcons, activeLibrary, owner) end
    for _, anchor in ipairs(active) do
        anchor:Hide()
        for _, button in ipairs(anchor.buttons) do button:Hide() end
    end
    active, buttonsByID, signature = {}, {}, nil
end

local function readRecords(professions)
    local records, seen = {}, {}
    for _, profession in ipairs(type(professions) == "table" and professions or {}) do
        local id = type(profession) == "table" and profession.id
        if definitions[id] and not seen[id] then
            seen[id] = true
            local record = call(ns.GetNearbyTrainer, id)
            if type(record) == "table" and number(record.mapID) and record.mapID > 0
                and number(record.x) and record.x >= 0 and record.x <= 1
                and number(record.y) and record.y >= 0 and record.y <= 1 then
                records[#records + 1] = {id = id, name = profession.name or definitions[id][3],
                    icon = ns.ProfessionIcon(id, profession.icon), unlearned = profession.unlearned == true, record = record}
                if #records >= MAX_PROFESSIONS then break end
            end
        end
    end
    table.sort(records, function(a, b) return a.id < b.id end)
    return records
end
local function recordSignature(records)
    local keys = {}
    for _, entry in ipairs(records) do
        local record = entry.record
        keys[#keys + 1] = table.concat({entry.id, entry.name, tostring(entry.icon), tostring(entry.unlearned),
            record.npcID or "", record.name or "", record.mapID, record.mapName or "",
            string.format("%.6f", record.x), string.format("%.6f", record.y)}, "\031")
    end
    return table.concat(keys, "\030")
end
local function clusters(records)
    local parents = {}
    local function root(i)
        while parents[i] ~= i do i = parents[i] end
        return i
    end
    for i = 1, #records do parents[i] = i end
    for i = 1, #records do
        for j = i + 1, #records do
            local a, b = records[i].record, records[j].record
            if a.mapID == b.mapID and (a.x - b.x)^2 + (a.y - b.y)^2 <= CLUSTER_RADIUS^2 then
                parents[root(j)] = root(i)
            end
        end
    end
    local result, byRoot = {}, {}
    for i, entry in ipairs(records) do
        local key = root(i)
        if not byRoot[key] then byRoot[key] = {}; result[#result + 1] = byRoot[key] end
        byRoot[key][#byRoot[key] + 1] = entry
    end
    return result
end

-- Supply DisplayProfessions: learned primary skills plus the three secondary
-- skills. Repainting highlights does not rebuild or replace map pins.
function ns.UpdateTrainerPins(professions, selectedProfessionID)
    -- A periodic panel refresh must not undo a direct click on a map icon.
    if selectedProfessionID ~= panelSelectedID then
        panelSelectedID, selectedID = selectedProfessionID, selectedProfessionID
    end
    local pins, coordinates = libraries()
    if not pins or type(CreateFrame) ~= "function" then
        ns.ClearTrainerPins()
        activeLibrary = nil
        return false, 0
    end
    local records = readRecords(professions)
    local nextSignature = recordSignature(records)
    if pins == activeLibrary and signature == nextSignature then
        for _, entry in ipairs(records) do
            local button = buttonsByID[entry.id]
            if button then button.record = entry.record; style(button) end
        end
        return true, #records
    end
    ns.ClearTrainerPins()
    activeLibrary = pins
    local complete, count = true, 0
    for index, group in ipairs(clusters(records)) do
        local record = group[1].record
        -- The anchor stays at a real trainer location. Only its child buttons
        -- receive display offsets; every button retains its own exact position.
        local wx, wy, instance = call(coordinates.GetWorldCoordinatesFromZone, coordinates, record.x, record.y, record.mapID)
        if number(wx) and number(wy) and number(instance) then
            local anchor = anchorAt(index)
            local strata = call(WorldMapFrame and WorldMapFrame.GetFrameStrata, WorldMapFrame)
            if strata then anchor:SetFrameStrata(strata) end
            local columns = math.min(3, #group)
            for i, entry in ipairs(group) do
                local button = anchor.buttons[i] or makeButton(anchor)
                anchor.buttons[i] = button
                button.professionID, button.professionName, button.unlearned, button.record = entry.id, entry.name, entry.unlearned, entry.record
                button.icon:SetTexture(entry.icon)
                local row, column = math.floor((i - 1) / columns), (i - 1) % columns
                local rowColumns = math.min(columns, #group - row * columns)
                button:ClearAllPoints()
                button:SetPoint("CENTER", anchor, "CENTER", (column - (rowColumns - 1) / 2) * SPACING, -row * (SPACING + 12))
                button:Show()
                style(button)
            end
            active[#active + 1] = anchor
            local ok, added = pcall(pins.AddWorldMapIconMap, pins, owner, anchor, record.mapID, record.x, record.y, SHOW_ZONE_AND_CONTINENT)
            -- Questie's fork returns nil on success; the standard library returns
            -- a boolean. Valid coordinates were checked with the matching HBD.
            if ok and added ~= false then
                for i, entry in ipairs(group) do
                    buttonsByID[entry.id] = anchor.buttons[i]
                    style(anchor.buttons[i])
                end
                count = count + #group
            else
                anchor:Hide()
                complete = false
            end
        else
            complete = false -- HBD may still be initializing; retry next update.
        end
    end
    if complete then signature = nextSignature end
    return complete, count
end
