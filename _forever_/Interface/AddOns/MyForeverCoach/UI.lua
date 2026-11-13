local _, NS = ...
local panel, exportPanel
local diagnostics = false
local colors = {
    readable = {0.44, 0.88, 0.69}, partial = {1, 0.78, 0.35}, restricted = {1, 0.65, 0.37},
    error = {1, 0.42, 0.42}, missing = {0.70, 0.74, 0.80}, observed = {0.57, 0.76, 1}, none = {0.52, 0.58, 0.65},
}
local function label(parent, font, x, y, width, message)
    local v = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    v:SetPoint("TOPLEFT", x, y)
    v:SetWidth(width)
    v:SetJustifyH("LEFT")
    v:SetText(message or "")
    return v
end
local function backdrop(frame)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = {left = 3, right = 3, top = 3, bottom = 3}})
    frame:SetBackdropColor(0.035, 0.055, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.30, 0.39, 0.48, 1)
end
local function button(parent, x, y, width, caption, handler)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 26)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(caption)
    b:SetScript("OnClick", handler)
    return b
end
local function combat()
    local _, value = NS.Try(InCombatLockdown)
    return NS.Bool(value) == true
end

function NS.SetBehaviorView(value)
    diagnostics = value == true
    if panel then
        panel.overview:SetShown(not diagnostics)
        panel.diagnostics:SetShown(diagnostics)
        panel.view:SetText(diagnostics and "行为概览" or "能力检测")
    end
end

local function duration(value)
    value = math.floor(NS.Number(value) or 0)
    return string.format("%d分%02d秒", math.floor(value/60), value%60)
end

function NS.ShowExport(report)
    if combat() then NS.Print("请脱战后导出，采集仍会继续。") return end
    if not exportPanel then
        exportPanel = CreateFrame("Frame", "MyForeverCoachExportPanel", UIParent, "BackdropTemplate")
        exportPanel:SetSize(690, 480)
        exportPanel:SetPoint("CENTER", 0, 0)
        exportPanel:SetFrameStrata("DIALOG")
        exportPanel:SetClampedToScreen(true)
        backdrop(exportPanel)
        exportPanel.title = label(exportPanel, "GameFontNormalLarge", 18, -18, 630, "导出采集数据")
        label(exportPanel, nil, 18, -48, 640, "点击文本后 Ctrl+C / ⌘C 复制。仅在本机展示，不会发送到任何服务。")
        local close = CreateFrame("Button", nil, exportPanel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", nil, exportPanel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -80)
        scroll:SetPoint("BOTTOMRIGHT", -38, 54)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetWidth(620)
        box:SetHeight(330)
        box:SetMaxLetters(0)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); exportPanel:Hide() end)
        scroll:SetScrollChild(box)
        exportPanel.box, exportPanel.scroll = box, scroll
        button(exportPanel, 18, -436, 110, "全选", function() box:SetFocus(); box:HighlightText() end)
        button(exportPanel, 550, -436, 110, "关闭", function() box:ClearFocus(); exportPanel:Hide() end)
    end
    local data, err
    if report then data = NS.ExportReport() else data, err = NS.ExportSession() end
    if not data then NS.Print(err or "尚无可导出的数据。") return end
    exportPanel.title:SetText(report and "能力检测摘要" or "导出会话 JSON")
    exportPanel.box:SetText(data)
    exportPanel.scroll:SetVerticalScroll(0)
    exportPanel:Show()
    exportPanel.box:SetFocus()
    exportPanel.box:HighlightText()
    NS.exportPanel = exportPanel
end

function NS.CreateUI()
    if panel then return panel end
    panel = CreateFrame("Frame", "MyForeverCoachPanel", UIParent, "BackdropTemplate")
    panel:SetSize(664, 518)
    panel:SetPoint("CENTER", 0, 10)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    backdrop(panel)
    label(panel, "GameFontNormalLarge", 18, -18, 590, "我的无限 · 玩家行为")
    label(panel, nil, 18, -46, 620, "本机统计由我的无限软件展示 · 采集插件 " .. NS.VERSION .. " 本机候选")
    panel.status = label(panel, "GameFontHighlight", 18, -74, 620)
    panel.meta = label(panel, nil, 18, -98, 620)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() NS.db.settings.shown = false; panel:Hide() end)
    local drag = CreateFrame("Frame", nil, panel)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", -32, 0)
    drag:SetHeight(62)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not combat() then panel:StartMoving() end end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    panel.overview = CreateFrame("Frame", nil, panel)
    panel.overview:SetPoint("TOPLEFT", 0, 0)
    panel.overview:SetSize(664, 430)
    panel.metrics = {}
    local metrics = {{"observedSeconds", "采集时长"}, {"combatsEntered", "战斗次数"}, {"castsSucceeded", "施法成功"},
        {"xpGained", "获得经验"}, {"questsTurnedIn", "完成任务"}, {"deaths", "死亡"}}
    for index, item in ipairs(metrics) do
        local x, y = 22 + ((index-1)%3)*213, -141 - math.floor((index-1)/3)*89
        label(panel.overview, "GameFontNormal", x, y, 195, item[2])
        panel.metrics[item[1]] = label(panel.overview, "GameFontNormalLarge", x, y-28, 195, "0")
    end
    panel.activity = label(panel.overview, "GameFontHighlight", 22, -332, 615)
    panel.actions = label(panel.overview, nil, 22, -359, 615)
    label(panel.overview, nil, 22, -390, 615, "在我的无限软件中打开“行为统计”，查看按日趋势、技能和地图分布。")
    label(panel.overview, nil, 22, -414, 615, "数据在 /reload 或登出后由客户端写盘；暂停期间不累计游戏行为。")

    panel.diagnostics = CreateFrame("Frame", nil, panel)
    panel.diagnostics:SetPoint("TOPLEFT", 0, 0)
    panel.diagnostics:SetSize(664, 430)
    label(panel.diagnostics, "GameFontNormal", 20, -136, 210, "采集项目")
    for i, name in ipairs({"脱战", "战斗", "副本", "PvP"}) do
        label(panel.diagnostics, "GameFontNormal", 236 + (i - 1) * 101, -136, 95, name)
    end
    panel.rows = {}
    for i, key in ipairs(NS.CapabilityKeys) do
        local y = -162 - (i - 1) * 21
        local row = {title = label(panel.diagnostics, nil, 20, y, 210, NS.CapabilityLabels[key]), cells = {}}
        for j = 1, 4 do row.cells[j] = label(panel.diagnostics, nil, 236 + (j - 1) * 101, y, 95) end
        panel.rows[key] = row
    end
    panel.note = label(panel, nil, 18, -443, 625,
        "“已读到”仅说明采到部分公开字段；“待观察”需触发相应场景。")
    panel.pause = button(panel, 18, -475, 96, "暂停采集", function()
        NS.SetEnabled(not NS.db.settings.enabled); NS.RenderUI()
    end)
    panel.view = button(panel, 122, -475, 96, "能力检测", function()
        NS.SetBehaviorView(not diagnostics); NS.RenderUI()
    end)
    button(panel, 226, -475, 96, "新会话", function()
        if combat() then NS.Print("请脱战后开始新会话。") return end
        NS.StopSession("manual"); NS.StartSession(); NS.RegisterCaptureEvents(NS.frame); NS.RefreshCapabilities(); NS.RenderUI()
    end)
    button(panel, 330, -475, 96, "导出 JSON", function() NS.ShowExport(false) end)
    button(panel, 434, -475, 96, "诊断摘要", function() NS.ShowExport(true) end)
    button(panel, 538, -475, 104, "隐藏", function() NS.db.settings.shown = false; panel:Hide() end)
    panel:Hide()
    NS.panel = panel
    NS.SetBehaviorView(false)
    return panel
end

function NS.RenderUI()
    if not panel or not NS.db or not NS.session then return end
    local s = NS.session
    local enabled = NS.db.settings.enabled
    panel.status:SetText(NS.safetyStopped and "|cffff9166接口拦截 · 已安全停采|r" or enabled and "|cff70e0b0正在采集公开游戏行为|r" or "|cffffc75c已暂停采集|r")
    local client = s.client or {}
    local day, dateKey
    if NS.GetBehaviorToday then day, dateKey = NS.GetBehaviorToday() else day, dateKey = {time={}, counts={}, quality={}}, "本日" end
    panel.meta:SetText(diagnostics and ("客户端 " .. (NS.Text(client.version) or "未知") .. " / " ..
        (NS.Text(client.build) or (NS.Number(client.build) and tostring(client.build)) or "未知") ..
        "  ·  当前：" .. ({idle = "脱战", combat = "战斗", instance = "副本", pvp = "PvP"})[NS.GetContext()]) or
        (dateKey .. " · UTC+08:00 日统计 · 保留最近 90 天"))
    for key, view in pairs(panel.metrics) do
        view:SetText(key == "observedSeconds" and duration(day.time[key]) or tostring(math.floor(NS.Number(day.counts[key]) or 0)))
    end
    panel.activity:SetText("战斗 " .. duration(day.time.combatSeconds) .. "    非战斗 " .. duration(day.time.nonCombatSeconds) ..
        "    状态未知 " .. duration(day.time.unknownCombatSeconds))
    panel.actions:SetText("施法失败事件 " .. (day.counts.castsFailed or 0) .. " · 中断事件 " .. (day.counts.castsInterrupted or 0) ..
        " · 明细省略 " .. (day.quality.detailDropped or 0) .. " · 分布省略 " ..
        ((day.quality.spellOverflow or 0)+(day.quality.mapOverflow or 0)))
    panel.pause:SetText(enabled and "暂停采集" or "继续采集")
    local received = s.receivedEvents or {}
    local casts, transitions = 0, 0
    for event, entry in pairs(received) do
        local count = NS.Number(entry.count) or 0
        if event:find("^UNIT_SPELLCAST_") then casts = casts + count end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then transitions = transitions + count end
    end
    panel.note:SetText(diagnostics and ("事件收件：施法 " .. casts .. " / 战斗 " .. transitions .. " · 本会话明细 " .. #s.records .. " 条") or
        "仅统计实际读到的公开事件；失败事件不等于误操作，静止不等于挂机。")
    for _, key in ipairs(NS.CapabilityKeys) do
        for j, context in ipairs({"idle", "combat", "instance", "pvp"}) do
            local caption, status = NS.CapabilitySummary(key, context)
            local cell = panel.rows[key].cells[j]
            cell:SetText(caption)
            cell:SetTextColor(unpack(colors[status] or colors.none))
        end
    end
    panel:SetShown(NS.db.settings.shown)
end
