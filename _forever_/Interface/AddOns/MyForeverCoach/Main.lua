local addonName, NS = ...
local frame = CreateFrame("Frame")
local initialized, started, elapsedSample, elapsedUI = false, false, 0, 0
NS.frame = frame

local function initialize()
    if initialized then return end
    NS.Initialize()
    initialized = true
end

local function start()
    initialize()
    if started then return end
    started = true
    NS.StartSession()
    NS.RegisterCaptureEvents(frame)
    NS.CreateUI()
    NS.RefreshCapabilities()
    NS.RenderUI()
    NS.Print("玩家行为采集 " .. NS.VERSION .. " 已加载。/mybehavior 查看；pause 暂停。本机统计由我的无限软件展示。")
end

local function handlerError(event)
    local s = NS.session
    if not s then return end
    s.errors = s.errors or {}
    if #s.errors < 12 then s.errors[#s.errors + 1] = {code = "event_handler", event = event} end
    if NS.Filter then NS.Filter("handler_error") end
end

function NS.LoggingCommand(arg)
    local value
    if arg == "on" then value = true elseif arg == "off" then value = false end
    if type(LoggingCombat) ~= "function" then NS.Print("此客户端没有可调用的系统日志开关。") return end
    local ok, result
    if value == nil then ok, result = pcall(LoggingCombat) else ok, result = pcall(LoggingCombat, value) end
    if not ok then NS.Observe("combat_logging", "error"); NS.Print("系统日志开关调用失败。") return end
    if NS.IsSecret(result) then NS.Observe("combat_logging", "restricted"); NS.Print("系统日志状态受限。") return end
    if type(result) ~= "boolean" then NS.Observe("combat_logging", "missing"); NS.Print("系统日志没有返回可确认的状态。") return end
    NS.Observe("combat_logging", "readable", result)
    NS.Record("logging", {enabled = result})
    NS.Print(result and "系统战斗日志已开启；完整性需另验磁盘文件。" or "系统战斗日志已关闭。")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:SetScript("OnEvent", function(_, event, ...)
    local hadSession = NS.session ~= nil
    if hadSession and NS.CountReceived then NS.CountReceived(event) end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        local owner, action = ...
        if NS.Text(owner) ~= addonName then return end
        -- A pcall can return successfully while the client rejects the action.
        -- Stop the session's sampling rather than repeatedly probing that API.
        if NS.StopBehavior then NS.StopBehavior() end
        NS.safetyStopped = true
        if NS.db then NS.db.settings.enabled = false end
        local func = NS.Text(action)
        func = func and func:gsub("[^%w_:%.-]", "_"):sub(1, 80) or "unknown"
        if NS.session then
            NS.session.safetyStop = {event = event, func = func}
            NS.Error("blocked_" .. func)
        end
        NS.Print("客户端拦截了接口 " .. func .. "，已暂停采集。请更新修复并重载后再继续。")
        return
    end
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then initialize() end
        return
    end
    if event == "PLAYER_LOGIN" then
        start()
        if not hadSession and NS.CountReceived then NS.CountReceived(event) end
        return
    end
    if event == "PLAYER_LOGOUT" then if started then NS.StopSession("logout_or_reload") end return end
    if not started then if NS.Filter then NS.Filter("not_started") end return end
    local ok = pcall(NS.HandleEvent, event, ...)
    if not ok then handlerError(event) end
end)
frame:SetScript("OnUpdate", function(_, elapsed)
    if not started then return end
    elapsedSample, elapsedUI = elapsedSample + elapsed, elapsedUI + elapsed
    if elapsedSample >= 5 then
        elapsedSample = 0
        if NS.db.settings.enabled then
            local ok = pcall(NS.Sample, "periodic")
            if not ok then handlerError("PERIODIC_SAMPLE") end
        end
    end
    if elapsedUI >= 1 then
        elapsedUI = 0
        if NS.SettleBehavior then NS.SettleBehavior() end
        if NS.db.settings.shown then NS.RenderUI() end
    end
end)

SLASH_MYFOREVERCOACH1 = "/mycoach"
SLASH_MYFOREVERCOACH2 = "/mfcoach"
SLASH_MYFOREVERCOACH3 = "/mybehavior"
SLASH_MYFOREVERCOACH4 = "/mfbehavior"
SlashCmdList.MYFOREVERCOACH = function(message)
    if not started then start() end
    local command, arg = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command, arg = command:lower(), arg:lower()
    if command == "" or command == "show" then
        NS.db.settings.shown = true
        if NS.SetBehaviorView then NS.SetBehaviorView(false) end
    elseif command == "hide" then NS.db.settings.shown = false
    elseif command == "pause" then NS.SetEnabled(false)
    elseif command == "resume" then
        if NS.safetyStopped then NS.Print("本次加载已触发接口拦截，请更新并 /reload 后再恢复。") return end
        NS.SetEnabled(true)
    elseif command == "diagnostics" then
        NS.db.settings.shown = true
        if NS.SetBehaviorView then NS.SetBehaviorView(true) end
    elseif command == "sample" or command == "probe" then NS.RefreshCapabilities()
    elseif command == "export" then NS.ShowExport(false); return
    elseif command == "report" then NS.ShowExport(true); return
    elseif command == "new" then
        if InCombatLockdown and InCombatLockdown() then NS.Print("请脱战后开始新会话。") return end
        NS.StopSession("manual"); NS.StartSession(); NS.RegisterCaptureEvents(frame); NS.RefreshCapabilities()
    elseif command == "log" then NS.LoggingCommand(arg)
    else
        NS.Print("/mybehavior 显示统计；hide 隐藏；pause/resume 暂停/继续；diagnostics 能力检测；probe 检测；new 新会话；export JSON；report 摘要。旧 /mycoach 入口保留。")
        return
    end
    NS.RenderUI()
end
