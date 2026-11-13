local addonName, ns = ...
local pending, pendingScan, delay, retries, initialized = false, false, 0, 0, false
local periodic, absent = 0, {}
local events = CreateFrame("Frame")
ns.events = events

function ns.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffe8be75商业技能助手|r " .. message) end
end

local function initialize()
    if initialized then return end
    MyForeverProfessionsDB = ns.NormalizeDB(MyForeverProfessionsDB)
    ns.db = MyForeverProfessionsDB
    ns.professions, ns.detectReady = {}, false
    ns.CreateUI()
    if ns.CreateGatherAlerts then ns.CreateGatherAlerts() end
    if ns.CreateGatherSparkles then ns.CreateGatherSparkles() end
    initialized = true
end

function ns.QueueRefresh(wait, scan)
    pending, pendingScan = true, pendingScan or scan == true
    delay = math.max(delay, wait or 0.2)
end

function ns.Refresh(scan)
    if not initialized then return end
    if InCombatLockdown and InCombatLockdown() then
        ns.combatPaused = true
        ns.RenderUI()
        return
    end
    ns.combatPaused = false
    local professions, ready = ns.ReadProfessions()
    if ready then
        ns.professions, ns.detectReady = professions, true
        local known = {}
        for _, profession in ipairs(professions) do known[profession.id] = true end
        -- Unlearned professions cannot leave someone else's old recommendations.
        for id in pairs(ns.db.cache) do
            if known[id] then absent[id] = nil
            else
                absent[id] = (absent[id] or 0) + 1
                if absent[id] >= 2 then ns.db.cache[id] = nil end
            end
        end
    else
        ns.detectReady = false
    end
    if scan and ready then ns.ScanCurrentProfession() end
    ns.AttachRecommendations()
    if ns.RefreshGatherSparkles then ns.RefreshGatherSparkles() end
    ns.RenderUI()
end

events:SetScript("OnUpdate", function(_, elapsed)
    periodic = periodic + elapsed
    if initialized and periodic >= 5 then
        periodic = 0
        if ns.db.shown then ns.QueueRefresh(0, false) end
    end
    if not pending then return end
    delay = delay - elapsed
    if delay > 0 then return end
    local scan = pendingScan
    pending, pendingScan, delay = false, false, 0
    ns.Refresh(scan)
    if retries > 0 then retries = retries - 1; ns.QueueRefresh(1, true) end
end)

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then initialize() end
        return
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        initialize()
        retries = 3
        ns.QueueRefresh(0.3, true)
    elseif event == "PLAYER_LOGOUT" then
        -- Cache contains only profession recipe facts and per-character panel settings.
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.combatPaused = true
        if initialized then ns.RenderUI() end
    elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGING" then
        ns.dataSourceChanging = true
        ns.InvalidateRecipes()
    elseif event == "SKILL_LINES_CHANGED" or event == "NEW_RECIPE_LEARNED" or event == "SPELLS_CHANGED" then
        ns.InvalidateRecipes()
        retries = 2
        ns.QueueRefresh(0.3, true)
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        ns.dataSourceChanging = false
        retries = 3
        ns.QueueRefresh(0.2, true)
    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT"
        or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        ns.QueueRefresh(0.2, false)
    elseif event == "TRADE_SKILL_CLOSE" then
        ns.dataSourceChanging = false
        ns.QueueRefresh(0.2, false)
    else
        ns.QueueRefresh(0.2, true)
    end
end)

for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
    "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "NEW_RECIPE_LEARNED", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DETAILS_UPDATE",
    "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_ITEM_CRAFTED_RESULT",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA"}) do
    pcall(events.RegisterEvent, events, event)
end

SLASH_MYFOREVERPROFESSIONS1 = "/myprof"
SLASH_MYFOREVERPROFESSIONS2 = "/商业技能"
SlashCmdList.MYFOREVERPROFESSIONS = function(message)
    initialize()
    local command, arg = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "show" then
        ns.db.shown, ns.db.collapsed = true, false
    elseif command == "hide" then ns.db.shown = false
    elseif command == "gather" and ns.GatherCommand then ns.GatherCommand(arg:lower()); return
    elseif command == "sparkle" and ns.SparkleCommand then ns.SparkleCommand(arg:lower()); return
    elseif command == "lock" then ns.db.locked = not ns.db.locked
    elseif command == "scale" then
        local value = tonumber(arg)
        if not value then ns.Print("/myprof scale 1.2（范围 0.65–1.60）"); return end
        ns.SetScale(value)
    elseif command == "reset" then
        ns.db.point, ns.db.relativePoint, ns.db.x, ns.db.y = "CENTER", "CENTER", 300, 0
        ns.db.scale, ns.db.shown, ns.db.locked, ns.db.collapsed = 1, true, false, false
        ns.frame:ClearAllPoints()
        ns.frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        ns.SetScale(1)
    elseif command ~= "refresh" then
        ns.Print("/myprof 显示 · hide 隐藏 · lock 锁定 · scale 1.2 缩放 · reset 复位 · refresh 刷新 · gather 采集提醒 · sparkle 矿草闪光")
        return
    end
    ns.Refresh(true)
end
