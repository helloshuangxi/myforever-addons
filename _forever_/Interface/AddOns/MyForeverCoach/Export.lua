local _, NS = ...

local function secret(v)
    if issecretvalue and issecretvalue(v) then return true end
    if type(v) == "table" then
        if issecrettable and issecrettable(v) then return true end
        if canaccesstable and not canaccesstable(v) then return true end
    end
    return false
end

local function number(v)
    if secret(v) then return nil end
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
end

local function text(v)
    if secret(v) then return nil end
    if type(v) == "string" and #v <= 160 then return v end
end

local function scalar(v)
    if secret(v) then return nil end
    if type(v) == "boolean" then return v end
    return number(v) or text(v)
end

local function project(source, keys)
    local result = {}
    if secret(source) or type(source) ~= "table" then return result end
    for _, key in ipairs(keys) do result[key] = scalar(source[key]) end
    return result
end

local capKeys = {"health", "power", "position", "xp", "quests", "spells", "cooldown", "auras",
    "player_cast", "combat_log", "target_cast", "restrictions", "combat_logging"}
NS.CapabilityKeys = capKeys
NS.CapabilityLabels = {
    health = "生命值", power = "职业资源", position = "地图与坐标", xp = "经验进度",
    quests = "任务进度", spells = "已学技能", cooldown = "技能冷却", auras = "自身增益",
    player_cast = "玩家施法事件", combat_log = "战斗日志事件", target_cast = "目标读条",
    restrictions = "限制状态", combat_logging = "系统日志开关",
}

-- Only these data fields can leave the capture layer. Names, GUIDs, chat and
-- arbitrary API tables are intentionally absent. New fields require review.
local allowed = {}
for key in string.gmatch([[reason event spellID spellId spellIDs castBarID success failed interrupted
    level health maxHealth healthMax power maxPower powerMax powerType xp xpMax maxXP rested restedXP
    mapID x y inCombat combat instance instanceType isPvP targetExists exists dead isDead alive
    questID questId questIDs questXP moneyReward objectiveIndex numFulfilled numRequired isFinished
    completed isComplete numEntries numQuests quests objectives snapshot value current maximum
    startTime duration isEnabled enabled modRate charges currentCharges maxCharges chargeStart chargeDuration
    spellCooldownInfo cooldowns auras auraInstanceID applications expirationTime sourceUnit unit
    amount damage overkill absorbed resisted blocked critical school spellSchool extraSpellID extraSchool
    subevent action type state restrictionType restrictionState active restricted readable apiPresent
    registered observed missing error status code count total healthPercent powerPercent
    bagFree durability rank rankID known spells skills index finished time elapsed unitToken
    cooldown auraCount spellCount questCount questXPReward xpReward xpGained
    logging loggingEnabled difficultyID sampled durationSeconds available at
    spellbook powerToken healing spellSource spellTarget selfSource selfTarget
    limit truncated numCompleted numObjectives objectiveType pvp castGUIDReadable
    cooldownEnabled cooldownDuration cooldownStartTime enabledState phase interruptible castTimeMS
    completedCount numSpells entryID targetLevel targetDead targetEnemy isBoss auraType overhealing
    eventCombat lockdown lockdownStatus affectingCombat affectingStatus]], "%S+") do allowed[key] = true end

local fieldNames = {}
for _, key in ipairs({"health", "healthMax", "power", "powerMax", "powerType", "mapID", "coordinates", "x", "y",
    "level", "xp", "xpMax", "rested", "questCount", "entryCount", "questID", "spellID", "startTime", "duration",
    "isEnabled", "modRate", "targetExists", "interruptible", "castTimeMS", "state", "Combat", "Encounter",
    "ChallengeMode", "PvPMatch", "Map", "Chat", "logging", "restrictionState", "eventType", "eventState",
    "acceptedID", "turnedInID", "levelUp", "amount", "extraSpellID", "selfSource", "selfTarget",
    "endTime", "school", "overkill", "overhealing"}) do fieldNames[key] = true end
local apiNames = {"UnitHealth", "UnitPower", "UnitCastingInfo", "UnitChannelInfo", "UnitXP", "LoggingCombat",
    "CombatLogGetCurrentEventInfo", "GetPlayerMapPosition", "GetNumQuestLogEntries", "GetSpellBookItemInfo",
    "GetSpellCooldown", "GetAuraDataByIndex", "GetAddOnRestrictionState"}
local exportEvents = {ADDON_LOADED=true, PLAYER_LOGIN=true, PLAYER_LOGOUT=true,
    ADDON_ACTION_FORBIDDEN=true, ADDON_ACTION_BLOCKED=true}
for event in pairs(NS.CaptureEventDefinitions or {}) do exportEvents[event] = true end

local function dataCopy(source, depth, seen)
    if secret(source) then return nil end
    local v = scalar(source)
    if v ~= nil then return v end
    if type(source) ~= "table" or depth > 5 or seen[source] then return nil end
    seen[source] = true
    local out, n = {}, 0
    for k, item in pairs(source) do
        if not secret(k) then
            local key = text(k)
            local numeric = number(k)
            if (key and allowed[key]) or (numeric and numeric >= 1 and numeric <= 128 and numeric % 1 == 0) then
                local clean = dataCopy(item, depth + 1, seen)
                if clean ~= nil then out[k] = clean; n = n + 1 end
                if n >= 128 then break end
            end
        end
    end
    seen[source] = nil
    return out
end

local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
        local short = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
        return short[c] or string.format("\\u%04x", string.byte(c))
    end) .. '"'
end

local function encode(value, arrays)
    local kind = type(value)
    if kind == "string" then return quote(value) end
    if kind == "number" then return string.format("%.14g", value) end
    if kind == "boolean" then return value and "true" or "false" end
    local parts = {}
    local isArray = arrays[value] or (#value > 0)
    if isArray then
        for i = 1, #value do parts[#parts + 1] = encode(value[i], arrays) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = quote(key) .. ":" .. encode(value[key], arrays) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function NS.BuildExport()
    local session = NS.session
    if secret(session) or type(session) ~= "table" then return nil, "尚无会话" end
    local out = project(session, {"id", "schema", "version", "startedAt", "endedAt", "endReason", "duration", "dropped"})
    out.source = "client-observation"
    if NS.BuildBehaviorExport then out.behavior = NS.BuildBehaviorExport() end
    out.behaviorCoverage = project(session.behavior, {"schema", "daily"})
    out.safetyStop = project(session.safetyStop, {"event", "func"})
    out.client = project(session.client, {"version", "build", "interface", "locale"})
    out.character = project(session.character, {"class", "level", "race", "faction"})
    out.records, out.capabilities, out.eventCounts, out.errors, out.registrations = {}, {}, {}, {}, {}
    out.registrationChecks, out.receivedEvents, out.filterCounts = {}, {}, {}
    out.apis = project(session.apis, apiNames)
    out.restrictionStates = project(session.restrictionStates, {"Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat"})
    out.combatLogRestricted = scalar(session.combatLogRestricted)
    if type(session.records) == "table" and not secret(session.records) then
        for i = 1, math.min(#session.records, 1200) do
            local record = session.records[i]
            local clean = project(record, {"kind", "t", "context"})
            if clean.kind then
                clean.data = dataCopy(record.data, 0, {}) or {}
                out.records[#out.records + 1] = clean
            end
        end
    end
    if type(session.capabilities) == "table" and not secret(session.capabilities) then
        for _, key in ipairs(capKeys) do
            local cap = session.capabilities[key]
            if type(cap) == "table" and not secret(cap) then
                local clean = project(cap, {"lastStatus", "apiPresent", "disabled", "status", "reason"})
                clean.contexts, clean.fields = {}, {}
                if type(cap.contexts) == "table" and not secret(cap.contexts) then
                    for _, context in ipairs({"idle", "combat", "instance", "pvp"}) do
                        local state = cap.contexts[context]
                        if type(state) == "table" and not secret(state) then
                            clean.contexts[context] = project(state, {"readable", "restricted", "missing", "error", "observed"})
                        end
                    end
                end
                if type(cap.fields) == "table" and not secret(cap.fields) then
                    for field in pairs(fieldNames) do
                        local state = cap.fields[field]
                        if type(state) == "table" and not secret(state) then
                            local detail = project(state, {"readable", "restricted", "missing", "error", "observed", "lastStatus"})
                            detail.contexts = {}
                            if type(state.contexts) == "table" and not secret(state.contexts) then
                                for _, context in ipairs({"idle", "combat", "instance", "pvp"}) do
                                    local counts = state.contexts[context]
                                    if type(counts) == "table" and not secret(counts) then
                                        detail.contexts[context] = project(counts, {"readable", "restricted", "missing", "error", "observed"})
                                    end
                                end
                            end
                            clean.fields[field] = detail
                        end
                    end
                end
                out.capabilities[key] = clean
            end
        end
    end
    for _, field in ipairs({"eventCounts", "registrations", "registrationChecks"}) do
        local source = session[field]
        if type(source) == "table" and not secret(source) then
            local n = 0
            for k, v in pairs(source) do
                local key = text(k)
                if key and (exportEvents[key] or (field ~= "eventCounts" and key == "COMBAT_LOG_EVENT_UNFILTERED")) then
                    local clean = scalar(v)
                    if clean ~= nil then out[field][key] = clean; n = n + 1 end
                    if n >= 80 then break end
                end
            end
        end
    end
    local received = session.receivedEvents
    if type(received) == "table" and not secret(received) then
        local n = 0
        for k, v in pairs(received) do
            local key = text(k)
            if key and exportEvents[key] then
                out.receivedEvents[key] = project(v, {"count", "firstAt", "lastAt"})
                n = n + 1
                if n >= 80 then break end
            end
        end
    end
    local filtered = session.filterCounts
    if type(filtered) == "table" and not secret(filtered) then
        for key in pairs(NS.FILTER_REASONS or {}) do out.filterCounts[key] = number(filtered[key]) end
    end
    if type(session.errors) == "table" and not secret(session.errors) then
        for i = 1, math.min(#session.errors, 12) do
            out.errors[#out.errors + 1] = project(session.errors[i], {"code", "key", "context", "event", "t", "count"})
        end
    end
    return out
end

function NS.ExportSession()
    local ok, result, err = pcall(function()
        local out, why = NS.BuildExport()
        if not out then return nil, why end
        return encode(out, {[out.records] = true, [out.errors] = true})
    end)
    if not ok then return nil, "导出失败，未输出不完整数据" end
    return result, err
end

function NS.CapabilitySummary(key, context)
    local session = NS.session
    local cap = session and session.capabilities and session.capabilities[key]
    if cap and cap.disabled == true then return "已停用", "restricted" end
    local c = cap and cap.contexts and cap.contexts[context]
    if not c then return "待观察", "none" end
    local r, s, e, m, o = number(c.readable) or 0, number(c.restricted) or 0,
        number(c.error) or 0, number(c.missing) or 0, number(c.observed) or 0
    if r > 0 and s > 0 then return "部分受限", "partial" end
    if r > 0 then return "已读到", "readable" end
    if s > 0 then return "受限", "restricted" end
    if e > 0 then return "报错", "error" end
    if m > 0 then return "无数据", "missing" end
    if o > 0 then return "仅见事件", "observed" end
    return "待观察", "none"
end

function NS.ExportReport()
    if not NS.session then return "尚未开始采集。" end
    local s = NS.session
    local lines = {"我的无限 · 玩家行为 " .. NS.VERSION .. " · 本机能力报告",
        "客户端 " .. (text(s.client.version) or "未知") .. " / " .. tostring(number(s.client.build) or text(s.client.build) or "未知"),
        "记录 " .. tostring(#s.records) .. " · 达到上限后丢弃 " .. tostring(number(s.dropped) or 0),
        "每格表示本会话观察；无数据和待观察不等于不支持。", ""}
    for _, key in ipairs(capKeys) do
        local parts = {}
        for i, context in ipairs({"idle", "combat", "instance", "pvp"}) do
            parts[#parts + 1] = ({"脱战", "战斗", "副本", "PvP"})[i] .. ":" .. NS.CapabilitySummary(key, context)
        end
        lines[#lines + 1] = NS.CapabilityLabels[key] .. "  " .. table.concat(parts, " / ")
    end
    lines[#lines + 1] = "\n副本/PvP 列按所在场景归类，包含其中的战斗与脱战；记录内 combat 字段另作区分。"
    lines[#lines + 1] = "玩家施法事件不代表完整按键记录；技能空档不能直接认定为操作失误。"
    lines[#lines + 1] = "系统日志开关可读不代表磁盘战斗日志完整，需独立检查实际文件。"
    lines[#lines + 1] = "\n事件链路（仅本会话）"
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED"}) do
        local entry = s.receivedEvents and s.receivedEvents[event] or {}
        lines[#lines + 1] = event .. "  注册:" .. (s.registrationChecks and s.registrationChecks[event] or "待核实") ..
            "  收件:" .. tostring(number(entry.count) or 0)
    end
    lines[#lines + 1] = "过滤与写入："
    for key, count in pairs(s.filterCounts or {}) do
        if text(key) and number(count) then lines[#lines + 1] = key .. ": " .. tostring(count) end
    end
    lines[#lines + 1] = "收到事件不等于字段可读；暂停时只维护事件诊断计数，不保存操作内容。"
    return table.concat(lines, "\n")
end
