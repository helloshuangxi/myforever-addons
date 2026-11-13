local addonName, NS = ...
NS = NS or {}
_G.MyForeverCoach = NS

NS.VERSION = "0.2.0"
NS.SCHEMA = 1
NS.LIMITS = { sessions = 8, records = 1200, errors = 12 }
NS.CAPABILITIES = {
    health = "生命值", power = "资源值", position = "地图坐标", xp = "经验值",
    quests = "任务进度", spells = "已学技能", cooldown = "技能冷却", auras = "玩家光环",
    player_cast = "玩家施法", combat_log = "战斗日志", target_cast = "目标读条",
    restrictions = "限制状态", combat_logging = "磁盘日志开关",
}

-- Do not compare, format, index, or store values until their secrecy is checked.
function NS.IsSecret(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return true end
    end
    if type(value) == "table" and type(issecrettable) == "function" then
        local ok, secret = pcall(issecrettable, value)
        if not ok or secret then return true end
    end
    if type(value) == "table" and type(canaccesstable) == "function" then
        local ok, accessible = pcall(canaccesstable, value)
        if not ok or accessible == false then return true end
    end
    return false
end

function NS.Number(value)
    if NS.IsSecret(value) then return nil, "restricted" end
    if type(value) ~= "number" then return nil, "missing" end
    if value ~= value or value == math.huge or value == -math.huge then return nil, "missing" end
    return value, "readable"
end

function NS.Text(value)
    if NS.IsSecret(value) then return nil, "restricted" end
    if type(value) ~= "string" then return nil, "missing" end
    if #value > 128 then return nil, "missing" end
    return value, "readable"
end

function NS.Bool(value)
    if NS.IsSecret(value) then return nil, "restricted" end
    if type(value) ~= "boolean" then return nil, "missing" end
    return value, "readable"
end

function NS.Try(func, ...)
    if type(func) ~= "function" then return "missing" end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r = pcall(func, ...)
    if not ok then return "error" end
    return "ok", a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r
end

function NS.Field(value, key)
    if NS.IsSecret(value) then return nil, "restricted" end
    if type(value) ~= "table" then return nil, "missing" end
    local status, field = NS.Try(function() return value[key] end)
    if status ~= "ok" then return nil, status end
    if NS.IsSecret(field) then return nil, "restricted" end
    return field, field == nil and "missing" or "ok"
end

local function Token(value)
    local text = NS.Text(value)
    if text and text:match("^[%w_%.:%-]+$") then return text end
end
NS.Token = Token

local function Clock()
    local _, value = NS.Try(GetTime)
    return NS.Number(value) or 0
end

local function Epoch()
    local _, value = NS.Try(GetServerTime)
    value = NS.Number(value)
    if value then return value end
    local _, fallback = NS.Try(time)
    return NS.Number(fallback) or 0
end
NS.Epoch = Epoch

function NS.Elapsed()
    return math.max(0, Clock() - (NS.startedMonotonic or Clock()))
end

function NS.GetContext()
    local status, inside, instanceType = NS.Try(IsInInstance)
    inside = NS.Bool(inside)
    instanceType = NS.Text(instanceType)
    if status == "ok" and inside then
        if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
        return "instance"
    end
    if NS.inCombat == true then return "combat" end
    local _, lockdown = NS.Try(InCombatLockdown)
    if NS.Bool(lockdown) == true then return "combat" end
    return "idle"
end

function NS.Print(message)
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage((MyForeverStyle and MyForeverStyle.Prefix("玩家行为") or "玩家行为") .. " " .. message)
    end
end

local numericFields = {
    level=true, health=true, healthMax=true, power=true, powerMax=true, powerType=true,
    mapID=true, x=true, y=true, xp=true, xpMax=true, rested=true, bagFree=true, durability=true,
    spellID=true, extraSpellID=true, amount=true, absorbed=true, overkill=true, overhealing=true, school=true,
    startTime=true, duration=true, modRate=true, charges=true, maxCharges=true, questID=true,
    xpReward=true, moneyReward=true, questCount=true, completedCount=true, auraCount=true,
    restrictionType=true, restrictionState=true, castBarID=true, castTimeMS=true,
    numSpells=true, elapsed=true, count=true, entryID=true, targetLevel=true,
}
local booleanFields = {
    enabled=true, isEnabled=true, combat=true, dead=true, targetExists=true, targetEnemy=true,
    targetDead=true, interruptible=true, logging=true, critical=true, isBoss=true,
    selfSource=true, selfTarget=true,
    eventCombat=true, lockdown=true, affectingCombat=true,
}
local tokenFields = { reason=true, event=true, phase=true, action=true, unit=true, auraType=true,
    lockdownStatus=true, affectingStatus=true }
local statusFields = {lockdownStatus=true,affectingStatus=true}
local statusTokens = {readable=true,restricted=true,missing=true,error=true}
local kinds = {
    snapshot=true, combat=true, player_cast=true, combat_log=true, target_cast=true,
    quest=true, level=true, death=true, restriction=true, logging=true, control=true,
    session=true, spells=true, pause=true, target=true, cooldown=true, aura=true,
}

local diagnosticEvents = {
    ADDON_LOADED=true, PLAYER_LOGIN=true, PLAYER_LOGOUT=true,
    ADDON_ACTION_FORBIDDEN=true, ADDON_ACTION_BLOCKED=true,
}
local filterReasons = {
    paused=true, stopped=true, full=true, invalid_kind=true, written=true,
    unit_restricted=true, unit_missing=true, other_unit=true,
    spell_id_restricted=true, spell_id_missing=true, combat_state_mismatch=true,
    safety_stopped=true, unknown_event=true, throttled=true, handler_error=true,
}
NS.FilterReasons = filterReasons
NS.FILTER_REASONS = filterReasons

-- Entry diagnostics intentionally run even while sampling is paused. They only
-- retain known event names/counts/times, never any event arguments.
function NS.CountReceived(event)
    if not NS.session then return false end
    event=Token(event)
    if not event or not (diagnosticEvents[event] or (NS.CaptureEventDefinitions and NS.CaptureEventDefinitions[event])) then
        return false
    end
    local entries=NS.session.receivedEvents
    if type(entries)~="table" then entries={}; NS.session.receivedEvents=entries end
    local now=NS.Elapsed()
    local entry=entries[event]
    if not entry then entry={count=0,firstAt=now,lastAt=now}; entries[event]=entry end
    entry.count=entry.count+1
    entry.lastAt=now
    return true
end

function NS.Filter(reason)
    if not NS.session then return false end
    reason=Token(reason)
    if not reason or not filterReasons[reason] then return false end
    local counts=NS.session.filterCounts
    if type(counts)~="table" then counts={}; NS.session.filterCounts=counts end
    counts[reason]=(counts[reason] or 0)+1
    return true
end

function NS.CleanData(data)
    local clean = {}
    if NS.IsSecret(data) or type(data) ~= "table" then return clean end
    for key in pairs(numericFields) do
        local value = NS.Field(data, key)
        clean[key] = NS.Number(value)
    end
    for key in pairs(booleanFields) do
        local value = NS.Field(data, key)
        clean[key] = NS.Bool(value)
    end
    for key in pairs(tokenFields) do
        local value = NS.Field(data, key)
        local token=Token(value)
        if not statusFields[key] or (token and statusTokens[token]) then clean[key]=token end
    end
    -- Only numeric spell IDs are accepted; never copy arbitrary tables or names.
    for _,arrayKey in ipairs({"spellIDs","questIDs"}) do
        local ids = NS.Field(data, arrayKey)
        if not NS.IsSecret(ids) and type(ids) == "table" then
            clean[arrayKey] = {}
            for index=1,128 do
                local value = NS.Field(ids, index)
                local id = NS.Number(value)
                if not id then break end
                clean[arrayKey][#clean[arrayKey]+1] = id
            end
        end
    end
    return clean
end

function NS.Record(kind, data)
    if not NS.session then return nil end
    if NS.stopped then NS.Filter("stopped"); return nil end
    if NS.safetyStopped then NS.Filter("safety_stopped"); return nil end
    if not NS.db or not NS.db.settings.enabled then NS.Filter("paused"); return nil end
    kind = Token(kind)
    if not kind or not kinds[kind] then NS.Filter("invalid_kind"); return nil end
    local session = NS.session
    session.duration = NS.Elapsed()
    local cleanData = NS.CleanData(data)
    cleanData.combat = NS.Bool(NS.inCombat)
    if NS.RecordBehavior then NS.RecordBehavior(kind, cleanData) end
    if #session.records >= NS.LIMITS.records then
        session.dropped = session.dropped + 1
        if NS.BehaviorDropped then NS.BehaviorDropped() end
        NS.Filter("full")
        return nil
    end
    local record = { kind=kind, t=session.duration, context=NS.GetContext(), data=cleanData }
    session.records[#session.records+1] = record
    NS.Filter("written")
    return record
end

function NS.Error(code)
    if not NS.session then return end
    code = Token(code)
    if not code then code = "unknown_error" end
    local errors = NS.session.errors
    if #errors >= NS.LIMITS.errors then return end
    for _, item in ipairs(errors) do
        if item.code == code then item.count = (item.count or 1) + 1; return end
    end
    errors[#errors+1] = { code=code, t=NS.Elapsed(), context=NS.GetContext(), count=1 }
end

local statuses = { readable=true, restricted=true, missing=true, error=true, observed=true }
function NS.Observe(key, status, value)
    if not NS.session or not NS.db or not NS.db.settings.enabled or NS.stopped
        or not NS.CAPABILITIES[key] or not statuses[status] then return nil end
    local capability = NS.session.capabilities[key]
    if not capability then
        capability = { label=NS.CAPABILITIES[key], contexts={}, lastStatus="unobserved" }
        NS.session.capabilities[key] = capability
    end
    local context = NS.GetContext()
    local counts = capability.contexts[context]
    if not counts then
        counts = { readable=0, restricted=0, missing=0, error=0, observed=0 }
        capability.contexts[context] = counts
    end
    counts[status] = counts[status] + 1
    capability.lastStatus = status
    capability.lastAt = NS.Elapsed()
    capability.lastValue = nil
    if status == "readable" then
        local number = NS.Number(value)
        local boolean = NS.Bool(value)
        if number ~= nil then capability.lastValue = number
        elseif boolean ~= nil then capability.lastValue = boolean
        else capability.lastValue = Token(value) end
    end
    return capability
end

function NS.SetEnabled(enabled)
    if not NS.db then NS.Initialize() end
    enabled = NS.Bool(enabled) == true
    if enabled and NS.safetyStopped then
        NS.db.settings.enabled = false
        return false
    end
    if enabled == NS.db.settings.enabled then return enabled end
    if not enabled and NS.db.settings.enabled then NS.Record("pause", { enabled=false }) end
    if NS.EnableBehavior then NS.EnableBehavior(enabled) end
    NS.db.settings.enabled = enabled
    if enabled then
        local _, lockdown = NS.Try(InCombatLockdown)
        NS.inCombat = NS.Bool(lockdown)
        NS.Record("pause", { enabled=true })
    end
    return enabled
end

function NS.Initialize()
    local source = MyForeverCoachDB
    if NS.IsSecret(source) or type(source) ~= "table" then source = {} end
    local settings = NS.Field(source, "settings")
    if NS.IsSecret(settings) or type(settings) ~= "table" then settings = {} end
    local db = {
        schema=NS.SCHEMA, version=NS.VERSION,
        settings={ enabled=NS.Field(settings,"enabled") ~= false, shown=NS.Field(settings,"shown") ~= false },
        sessions={}, nextSession=math.max(0,math.floor(NS.Number(NS.Field(source,"nextSession")) or 0)),
    }
    local oldSessions = NS.Field(source, "sessions")
    if not NS.IsSecret(oldSessions) and type(oldSessions) == "table" then
        -- Existing own records are already schema controlled; retain bounded history.
        local count = math.min(#oldSessions, NS.LIMITS.sessions)
        local first = math.max(1, #oldSessions - count + 1)
        for index=first,#oldSessions do
            local item = NS.Field(oldSessions,index)
            if not NS.IsSecret(item) and type(item)=="table" and NS.Number(NS.Field(item,"schema"))==NS.SCHEMA then
                db.sessions[#db.sessions+1] = item
                local records = NS.Field(item,"records")
                if not NS.IsSecret(records) and type(records)=="table" then
                    while #records > NS.LIMITS.records do table.remove(records) end
                else item.records = {} end
                local errors = NS.Field(item,"errors")
                item.errors = not NS.IsSecret(errors) and type(errors)=="table" and errors or {}
                while #item.errors > NS.LIMITS.errors do table.remove(item.errors) end
            end
        end
    end
    MyForeverCoachDB, NS.db = db, db
    if NS.InitializeBehavior then NS.InitializeBehavior(NS.Field(source,"behavior")) end
    return db
end

function NS.StartSession()
    if not NS.db then NS.Initialize() end
    NS.startedMonotonic, NS.stopped = Clock(), false
    local _, lockdown = NS.Try(InCombatLockdown)
    NS.inCombat = NS.Bool(lockdown)
    if NS.ResetCaptureState then NS.ResetCaptureState() end
    NS.db.nextSession = NS.db.nextSession + 1
    local startedAt = Epoch()
    local _, version, build, _, interface = NS.Try(GetBuildInfo)
    local _, _, class = NS.Try(UnitClass,"player")
    local _, _, race = NS.Try(UnitRace,"player")
    local _, level = NS.Try(UnitLevel,"player")
    local _, faction = NS.Try(UnitFactionGroup,"player")
    local _, locale = NS.Try(GetLocale)
    local session = {
        id=string.format("%d-%d", startedAt, NS.db.nextSession), version=NS.VERSION, schema=NS.SCHEMA,
        startedAt=startedAt, duration=0,
        client={ version=NS.Text(version), build=NS.Text(build), interface=NS.Number(interface), locale=NS.Text(locale) },
        character={ class=Token(class), race=Token(race), level=NS.Number(level), faction=Token(faction) },
        records={}, capabilities={}, eventCounts={}, registrations={}, apis={}, errors={}, dropped=0,
        receivedEvents={}, filterCounts={}, registrationChecks={},
    }
    NS.session = session
    for key,label in pairs(NS.CAPABILITIES) do
        session.capabilities[key] = { label=label, contexts={}, lastStatus="unobserved" }
    end
    NS.db.sessions[#NS.db.sessions+1] = session
    while #NS.db.sessions > NS.LIMITS.sessions do table.remove(NS.db.sessions,1) end
    if NS.StartBehavior then NS.StartBehavior() end
    NS.Record("session", { phase="start" })
    return session
end

function NS.StopSession(reason)
    if not NS.session then return nil end
    if NS.Sample and not NS.stopped then NS.Sample("session_stop") end
    if NS.StopBehavior then NS.StopBehavior() end
    NS.session.endedAt = Epoch()
    NS.session.duration = NS.Elapsed()
    NS.session.endReason = Token(reason) or "logout"
    NS.stopped = true
    return NS.session
end
