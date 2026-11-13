local _, NS = ...
local panel, exportPanel
local diagnostics = false
local colors = {
    readable = {0.44, 0.88, 0.69}, partial = {1, 0.78, 0.35}, restricted = {1, 0.65, 0.37},
    error = {1, 0.42, 0.42}, missing = {0.70, 0.74, 0.80}, observed = {0.57, 0.76, 1}, none = {0.52, 0.58, 0.65},
}
local Style = MyForeverStyle
local WIDTH, OVERVIEW_HEIGHT, DIAGNOSTICS_HEIGHT = 452, 338, 464
local function label(parent, level, x, y, width, message)
    local v = Style.Text(parent, level or "secondary", width, message)
    v:SetPoint("TOPLEFT", x, y)
    return v
end
local function button(parent, x, width, caption, handler, kind)
    local b = Style.Button(parent, caption, width, 24, handler, kind)
    b:SetPoint("BOTTOMLEFT", x, 12)
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
        panel:SetHeight(diagnostics and DIAGNOSTICS_HEIGHT or OVERVIEW_HEIGHT)
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
        exportPanel:SetSize(560, 400)
        exportPanel:SetPoint("CENTER", 0, 0)
        exportPanel:SetFrameStrata("DIALOG")
        exportPanel:SetClampedToScreen(true)
        Style.Panel(exportPanel, "popup")
        local box
        local function close() box:ClearFocus(); exportPanel:Hide() end
        local bar = Style.TitleBar(exportPanel, "导出采集数据", close)
        exportPanel.title = bar.title
        label(exportPanel, "caption", 12, -40, 536, "点击文本后 Ctrl+C / ⌘C 复制。仅在本机展示，不会发送到任何服务。")
        local well = CreateFrame("Frame", nil, exportPanel, "BackdropTemplate")
        well:SetPoint("TOPLEFT", 12, -62)
        well:SetPoint("BOTTOMRIGHT", -12, 48)
        Style.Surface(well, "side")
        local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -8)
        scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlightSmall")
        box:SetWidth(490)
        box:SetHeight(280)
        box:SetMaxLetters(0)
        box:SetScript("OnEscapePressed", close)
        scroll:SetScrollChild(box)
        exportPanel.box, exportPanel.scroll = box, scroll
        button(exportPanel, 12, 96, "全选", function() box:SetFocus(); box:HighlightText() end, "primary")
        button(exportPanel, 116, 96, "关闭", close)
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
    panel:SetSize(WIDTH, OVERVIEW_HEIGHT)
    panel:SetPoint("CENTER", 0, 10)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    Style.Panel(panel, "window")
    local bar = Style.TitleBar(panel, "玩家行为", function() NS.db.settings.shown = false; panel:Hide() end)
    -- What is happening now (status) reads first; when and how it is counted (meta) is a caption.
    panel.status = label(panel, "body", 12, -40, 428)
    panel.meta = label(panel, "caption", 12, -60, 428)
    local drag = bar.handle
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not combat() then panel:StartMoving() end end)
    drag:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

    panel.overview = CreateFrame("Frame", nil, panel)
    panel.overview:SetPoint("TOPLEFT", 0, 0)
    panel.overview:SetSize(WIDTH, 250)
    panel.metrics = {}
    local metrics = {{"observedSeconds", "采集时长"}, {"combatsEntered", "战斗次数"}, {"castsSucceeded", "施法成功"},
        {"xpGained", "获得经验"}, {"questsTurnedIn", "完成任务"}, {"deaths", "死亡"}}
    for index, item in ipairs(metrics) do
        -- The number is the content; its name is a caption above it.
        local x, y = 12 + ((index-1)%3)*146, -86 - math.floor((index-1)/3)*56
        label(panel.overview, "caption", x, y, 136, item[2])
        panel.metrics[item[1]] = label(panel.overview, "value", x, y-15, 136, "0")
    end
    panel.activity = label(panel.overview, "secondary", 12, -204, 428)
    panel.actions = label(panel.overview, "caption", 12, -224, 428)

    panel.diagnostics = CreateFrame("Frame", nil, panel)
    panel.diagnostics:SetPoint("TOPLEFT", 0, 0)
    panel.diagnostics:SetSize(WIDTH, 380)
    label(panel.diagnostics, "caption", 12, -86, 150, "采集项目")
    for i, name in ipairs({"脱战", "战斗", "副本", "PvP"}) do
        label(panel.diagnostics, "caption", 168 + (i - 1) * 70, -86, 66, name)
    end
    panel.rows = {}
    for i, key in ipairs(NS.CapabilityKeys) do
        local y = -106 - (i - 1) * 20
        local row = {title = label(panel.diagnostics, "secondary", 12, y, 150, NS.CapabilityLabels[key]), cells = {}}
        for j = 1, 4 do row.cells[j] = label(panel.diagnostics, "secondary", 168 + (j - 1) * 70, y, 66) end
        panel.rows[key] = row
    end
    panel.note = Style.Text(panel, "caption", 428)
    panel.note:SetPoint("BOTTOMLEFT", 12, 46)
    -- Everyday actions carry a surface; export and diagnostics are occasional, so they are quiet text actions.
    panel.pause = button(panel, 12, 84, "暂停采集", function()
        NS.SetEnabled(not NS.db.settings.enabled); NS.RenderUI()
    end)
    panel.view = button(panel, 102, 84, "能力检测", function()
        NS.SetBehaviorView(not diagnostics); NS.RenderUI()
    end)
    button(panel, 192, 72, "新会话", function()
        if combat() then NS.Print("请脱战后开始新会话。") return end
        NS.StopSession("manual"); NS.StartSession(); NS.RegisterCaptureEvents(NS.frame); NS.RefreshCapabilities(); NS.RenderUI()
    end)
    button(panel, 296, 72, "导出 JSON", function() NS.ShowExport(false) end, "quiet")
    button(panel, 368, 72, "诊断摘要", function() NS.ShowExport(true) end, "quiet")
    panel:Hide()
    NS.panel = panel
    NS.SetBehaviorView(false)
    return panel
end

function NS.RenderUI()
    if not panel or not NS.db or not NS.session then return end
    local s = NS.session
    local enabled = NS.db.settings.enabled
    panel.status:SetText(NS.safetyStopped and Style.Paint("danger", "● 接口拦截 · 已安全停采")
        or enabled and (Style.Paint("accent", "●") .. " 正在采集公开游戏行为") or Style.Paint("warning", "● 已暂停采集"))
    local client = s.client or {}
    local day, dateKey
    if NS.GetBehaviorToday then day, dateKey = NS.GetBehaviorToday() else day, dateKey = {time={}, counts={}, quality={}}, "本日" end
    panel.meta:SetText(diagnostics and ("客户端 " .. (NS.Text(client.version) or "未知") .. " / " ..
        (NS.Text(client.build) or (NS.Number(client.build) and tostring(client.build)) or "未知") ..
        "  ·  当前：" .. ({idle = "脱战", combat = "战斗", instance = "副本", pvp = "PvP"})[NS.GetContext()]) or
        (dateKey .. " · UTC+08:00 日统计 · 保留 90 天 · 采集插件 " .. NS.VERSION))
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
        "失败事件不等于误操作，静止不等于挂机。按日趋势与分布在我的无限软件“行为统计”查看；/reload 或登出后写盘。")
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
