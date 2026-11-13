local addonName, Kit = ...
Kit = Kit or {}

local panel, db
local startedAt, startedMoney
local inCombat = false
local elapsedSinceRefresh = 0
local DASH = "—"

local function IsNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function IsText(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "string"
end

local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, a, b = pcall(func, ...)
    if ok then return a, b end
end

local function InCombat()
    return inCombat or (InCombatLockdown and InCombatLockdown()) or false
end

function Kit.FormatMoney(copper)
    if not IsNumber(copper) then return DASH end
    local sign = copper < 0 and "-" or "+"
    local amount = math.floor(math.abs(copper))
    local gold = math.floor(amount / 10000)
    local silver = math.floor(amount / 100) % 100
    local coin = amount % 100
    return string.format("%s%d金 %d银 %d铜", sign, gold, silver, coin)
end

function Kit.FormatDuration(seconds)
    if not IsNumber(seconds) then return DASH end
    local minutes = math.floor(math.max(0, seconds) / 60)
    return string.format("%d小时 %02d分", math.floor(minutes / 60), minutes % 60)
end

function Kit.ReadBagSpace()
    if InCombat() then return nil end
    local api = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    local lastBag = IsNumber(NUM_BAG_SLOTS) and NUM_BAG_SLOTS or 4
    lastBag = math.min(8, math.max(0, math.floor(lastBag)))
    local total, found = 0, false
    for bag = 0, lastBag do
        local free, family = Call(api, bag)
        -- A specialized bag cannot hold arbitrary loot. Count only ordinary bags.
        if IsNumber(free) and IsNumber(family) and family == 0 and free >= 0 then
            total, found = total + free, true
        end
    end
    if found then return total end
end

function Kit.ReadDurability()
    if InCombat() then return nil end
    local minimum
    for slot = 1, 19 do
        local current, maximum = Call(GetInventoryItemDurability, slot)
        if IsNumber(current) and IsNumber(maximum) and maximum > 0 then
            local percent = math.max(0, math.min(100, current / maximum * 100))
            minimum = minimum and math.min(minimum, percent) or percent
        end
    end
    return minimum and math.floor(minimum + 0.5)
end

function Kit.ReadLocation()
    if InCombat() then return nil, nil end
    local zone = Call(GetRealZoneText)
    if not IsText(zone) or zone == "" then zone = DASH end
    if not C_Map then return zone, DASH end
    local mapID = Call(C_Map.GetBestMapForUnit, "player")
    if not IsNumber(mapID) then return zone, DASH end
    local position = Call(C_Map.GetPlayerMapPosition, mapID, "player")
    if not position then return zone, DASH end
    local x, y = Call(position.GetXY, position)
    if not IsNumber(x) or not IsNumber(y) then return zone, DASH end
    return zone, string.format("%.1f, %.1f", x * 100, y * 100)
end

function Kit.NormalizeDB(value)
    if type(value) ~= "table" then value = {} end
    value.shown = value.shown ~= false
    value.locked = value.locked == true
    local validPoints = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    if type(value.point) ~= "string" or not validPoints[value.point] then value.point = "CENTER" end
    if type(value.relativePoint) ~= "string" or not validPoints[value.relativePoint] then value.relativePoint = "CENTER" end
    if not IsNumber(value.x) then value.x = 320 end
    if not IsNumber(value.y) then value.y = 0 end
    return value
end

local function Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff73d9bd随身手册|r " .. message) end
end

local function InitializeDB()
    MyForeverFieldKitDB = Kit.NormalizeDB(MyForeverFieldKitDB)
    db = MyForeverFieldKitDB
end

function Kit.ResetSession()
    if InCombat() then
        Print("战斗结束后再重置旅途统计。")
        return false
    end
    startedAt = Call(GetTime)
    startedMoney = Call(GetMoney)
    return true
end

function Kit.Refresh()
    if not panel or not panel:IsShown() then return end
    if InCombat() then
        panel.status:SetText("战斗中 · 数据暂停")
        panel.body:SetText("脱离战斗后继续更新。\n\n旅途统计起点保留。")
        return
    end
    if not IsNumber(startedAt) or not IsNumber(startedMoney) then Kit.ResetSession() end
    local zone, coordinates = Kit.ReadLocation()
    local free = Kit.ReadBagSpace()
    local durability = Kit.ReadDurability()
    local money, now = Call(GetMoney), Call(GetTime)
    local change = IsNumber(money) and IsNumber(startedMoney) and money - startedMoney or nil
    local duration = IsNumber(now) and IsNumber(startedAt) and now - startedAt or nil
    panel.status:SetText(db.locked and "已锁定 · /myfield lock 解锁" or "拖动标题移动 · /myfield 隐藏")
    panel.body:SetText(string.format("%s  ·  %s\n普通背包 %s 空格 · 耐久 %s\n本次净收支  %s\n本次旅途  %s", zone or DASH, coordinates or DASH,
        free ~= nil and tostring(free) or DASH, durability ~= nil and tostring(durability) .. "%" or DASH,
        Kit.FormatMoney(change), Kit.FormatDuration(duration)))
end

local function MakePanel()
    if panel then return end
    panel = CreateFrame("Frame", "MyForeverFieldKitPanel", UIParent, "BackdropTemplate")
    panel:SetSize(304, 150)
    panel:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    panel:SetBackdropColor(0.035, 0.055, 0.065, 0.92)
    panel:SetBackdropBorderColor(0.3, 0.5, 0.48, 0.8)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("我的无限 · 随身手册")

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.status:SetPoint("TOPLEFT", 12, -33)
    panel.status:SetWidth(278)
    panel.status:SetJustifyH("LEFT")

    panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.body:SetPoint("TOPLEFT", 12, -54)
    panel.body:SetWidth(278)
    panel.body:SetJustifyH("LEFT")
    panel.body:SetWordWrap(false)
    panel.body:SetSpacing(7)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() db.shown = false; panel:Hide() end)

    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -28, 0)
    drag:SetHeight(31)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        if not db.locked and not InCombat() then panel:StartMoving() end
    end)
    drag:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        if InCombat() then return end
        local point, _, relativePoint, x, y = panel:GetPoint()
        if IsText(point) and IsText(relativePoint) and IsNumber(x) and IsNumber(y) then
            db.point, db.relativePoint, db.x, db.y = point, relativePoint, x, y
        end
    end)
    panel:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if elapsedSinceRefresh >= 2 then
            elapsedSinceRefresh = 0
            Kit.Refresh()
        end
    end)
    panel:SetShown(db.shown)
    Kit.panel = panel
end

local events = CreateFrame("Frame")
Kit.events = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        InitializeDB()
    elseif event == "PLAYER_LOGIN" then
        if not db then InitializeDB() end
        Kit.ResetSession()
        MakePanel()
        Kit.Refresh()
        Print("已载入。/myfield 开关，/myfield reset 重置收支，/myfield lock 锁定位置。")
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if panel then panel:StopMovingOrSizing() end
        Kit.Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        Kit.Refresh()
    end
end)

SLASH_MYFOREVERFIELDKIT1 = "/myfield"
SlashCmdList.MYFOREVERFIELDKIT = function(message)
    if not db then InitializeDB() end
    MakePanel()
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "reset" then
        if Kit.ResetSession() then Print("已从现在重新统计旅途时间和金币净变化。") end
    elseif command == "lock" then
        db.locked = not db.locked
        Print(db.locked and "已锁定面板位置。" or "已解锁，拖动标题可移动。")
    elseif command == "" then
        db.shown = not panel:IsShown()
        panel:SetShown(db.shown)
    else
        Print("/myfield 开关；/myfield reset 重置本次统计；/myfield lock 锁定或解锁。")
    end
    Kit.Refresh()
end
