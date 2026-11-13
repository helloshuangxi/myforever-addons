local addonName, NS = ...
local initialized, tick, mapTick = false, 0, 0

function NS.HandleCommand(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = string.lower(command)
    if command == "stop" then NS.Stop(); return end
    if command == "reset" then
        NS.DB.panel, NS.DB.hud = {x=0,y=0}, {x=0,y=0}
        if NS.Panel then NS.Panel:ClearAllPoints(); NS.Panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        if NS.HUD then NS.HUD:ClearAllPoints(); NS.HUD:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
        NS.DB.launcher = {point="TOPRIGHT",relativePoint="TOPRIGHT",x=-30,y=-287}
        if NS.Launcher then
            NS.Launcher:ClearAllPoints()
            NS.Launcher:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-30,-287)
        end
        NS.ToggleUI(true)
        NS.Print("已重置窗口位置。")
        return
    end
    if command == "help" then
        NS.Print("双击原生任务列表可导航任务目标；/mynav quest [任务ID]；/mynav 打开目录或搜索；/mynav way X Y 名称；/mynav way #地图ID X Y 名称；/mynav go 地图ID X Y 名称；/mynav pin；/mynav save 名称；/mynav stop。坐标填 0–100。")
        return
    end
    if command == "quest" then
        local questID
        if rest ~= "" then questID = tonumber(rest)
        else questID = NS.Call(C_QuestLog and C_QuestLog.GetSelectedQuest) end
        if not NS.Number(questID) or questID <= 0 or questID % 1 ~= 0 then
            NS.Print("请先选择任务，或输入 /mynav quest 任务ID。")
        elseif NS.OpenQuestNavigation then NS.OpenQuestNavigation(questID) end
        return
    end
    if command == "way" or command == "/way" then
        local input, err = NS.ParseCoordinateInput(rest)
        local p
        if input then p, err = NS.AddCustom(input.name, input.mapID, input.x, input.y) end
        if p then
            local ok, reason = NS.Start(p)
            if not ok then NS.Print(reason) end
            NS.RefreshUI()
        else NS.Print(err) end
        return
    end
    if command == "pin" then
        local p, err = NS.Call(NS.ImportWaypoint, rest ~= "" and rest or nil)
        if p then
            local ok, reason = NS.Start(p)
            if not ok then NS.Print(reason) end
            NS.RefreshUI()
        else NS.Print(err or "当前没有可用的地图标记。") end
        return
    end
    if command == "save" then
        local p, err = NS.SaveCurrent(rest)
        NS.Print(p and ("已保存当前位置：" .. p.name) or err)
        NS.RefreshUI()
        return
    end
    if command == "go" then
        local map, x, y, label = rest:match("^(%d+)%s+([%d%.]+)%s+([%d%.]+)%s*(.-)$")
        map, x, y = tonumber(map), tonumber(x), tonumber(y)
        local p, err = NS.AddCustom(label and label ~= "" and label or "坐标目标", map, x and x/100, y and y/100)
        if p then NS.Start(p); NS.RefreshUI() else NS.Print(err) end
        return
    end
    NS.ToggleUI(command ~= "" and true or nil)
    if command ~= "" then
        if NS.SetSearch then NS.SetSearch(message) end
    end
end

local function makeLauncher()
    if not UIParent then return end
    local b = CreateFrame("Button", "MyForeverNavigatorLauncher", UIParent, "BackdropTemplate")
    b:SetSize(42, 42)
    b:SetScale(1)
    b:SetFrameStrata("MEDIUM")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize=8,insets={left=3,right=3,top=3,bottom=3}})
    b:SetBackdropColor(0.42,0.82,0.58,0.98)
    b:SetBackdropBorderColor(0.42,0.82,0.58,0.98)
    b.label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    local font=b.label:GetFont()
    if font then b.label:SetFont(font,12,"") end
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetTextColor(0.06,0.16,0.10,1)
    b.label:SetText("导")
    local saved=NS.DB.launcher
    b:SetPoint(saved.point,UIParent,saved.relativePoint,saved.x,saved.y)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then NS.Stop() else NS.ToggleUI() end
    end)
    b:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point,_,relativePoint,x,y=self:GetPoint()
        NS.DB.launcher={point=point,relativePoint=relativePoint,x=x,y=y}
    end)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(0.82)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("我的无限 · 世界向导")
        GameTooltip:AddLine("左键打开 · 右键停止导航", 1, 0.9, 0.7)
        GameTooltip:AddLine("按住左键拖动 · /mynav", 0.85, 0.88, 0.9)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(1); if GameTooltip then GameTooltip:Hide() end end)
    NS.Launcher=b
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName and not initialized then
        MyForeverNavigatorDB = NS.Initialize(MyForeverNavigatorDB)
        initialized = true
        NS.CreateUI()
        if NS.InitializeQuestUI then NS.InitializeQuestUI() end
        makeLauncher()
        SLASH_MYFOREVERNAVIGATOR1 = "/mynav"
        SlashCmdList.MYFOREVERNAVIGATOR = NS.HandleCommand
        NS.Print("世界向导 "..NS.VERSION.." 试用版已加载，点击绿色「导」或 /mynav 打开。Questie 就绪后扩展 NPC 目录，坐标是参考位置。")
    elseif initialized and event ~= "ADDON_LOADED" then
        if event == "QUEST_LOG_UPDATE" and NS.RefreshQuestSession then NS.RefreshQuestSession() end
        NS.RefreshHUD()
        if not NS.Panel or NS.Panel:IsShown() then NS.RefreshUI() end
        if NS.UpdateMapPin then NS.UpdateMapPin() end
    end
end)
frame:SetScript("OnUpdate", function(_, elapsed)
    if not initialized then return end
    if NS.UpdateQuestieCatalog then NS.UpdateQuestieCatalog(elapsed) end
    tick, mapTick = tick + elapsed, mapTick + elapsed
    if tick >= 0.2 then
        tick = 0
        if NS.DB.activeID then NS.RefreshHUD() end
    end
    if mapTick >= 0.2 then
        mapTick = 0
        if NS.UpdateMapPin then NS.UpdateMapPin() end
    end
end)
