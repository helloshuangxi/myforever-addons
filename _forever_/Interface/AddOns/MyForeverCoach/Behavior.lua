local _, NS = ...

-- This cumulative layer is independent of the bounded diagnostic record list.
-- Only validated player records and public state baselines reach it.
local timeKeys = {"observedSeconds", "combatSeconds", "nonCombatSeconds", "pausedSeconds", "unknownCombatSeconds"}
local countKeys = {"combatsEntered", "combatsCompleted", "deaths", "castsStarted", "castsSucceeded",
    "castsFailed", "castsInterrupted", "questsAccepted", "questsTurnedIn", "levelsGained", "xpGained"}
local qualityKeys = {"xpGaps", "unknownMapSeconds", "detailDropped", "spellOverflow", "mapOverflow"}
local runtime
local OFFSET, DAY, RETAIN, ENTRIES = 28800, 86400, 90, 128

local function nonnegative(value)
    value = NS.Number(value)
    if value and value >= 0 then return value end
end
local function id(value)
    value = nonnegative(value)
    if value and value > 0 and value % 1 == 0 then return value end
end
local function clock()
    local _, value = NS.Try(GetTime)
    return NS.Number(value) or 0
end
local function empty(keys)
    local result = {}
    for _, key in ipairs(keys) do result[key] = 0 end
    return result
end
local function numbers(source, keys)
    local result = empty(keys)
    for _, key in ipairs(keys) do result[key] = nonnegative(NS.Field(source, key)) or 0 end
    return result
end
local function newDay()
    return {time=empty(timeKeys), counts=empty(countKeys), spells={}, maps={}, quality=empty(qualityKeys)}
end

-- Gregorian date from a UTC day index. Never uses the computer's timezone.
local function dateForIndex(index)
    local z = index + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe/1460) + math.floor(doe/36524) - math.floor(doe/146096))/365)
    local year = yoe + era * 400
    local doy = doe - (365*yoe + math.floor(yoe/4) - math.floor(yoe/100))
    local mp = math.floor((5*doy + 2)/153)
    local day = doy - math.floor((153*mp + 2)/5) + 1
    local month = mp + (mp < 10 and 3 or -9)
    if month <= 2 then year = year + 1 end
    return string.format("%04d-%02d-%02d", year, month, day)
end
function NS.BehaviorDate(epoch)
    epoch = NS.Number(epoch) or NS.Epoch()
    return dateForIndex(math.floor((epoch + OFFSET)/DAY))
end
local function prune(behavior, epoch)
    local today = math.floor((epoch + OFFSET)/DAY)
    local oldest, newest = dateForIndex(today - RETAIN + 1), dateForIndex(today)
    for key in pairs(behavior.days) do
        if key < oldest or key > newest then behavior.days[key] = nil end
    end
end
local function currentEpoch()
    return runtime and runtime.epoch or NS.Epoch()
end
local function dayAt(epoch)
    local behavior = NS.db and NS.db.behavior
    if not behavior then return nil end
    local key = NS.BehaviorDate(epoch)
    if not behavior.days[key] then behavior.days[key] = newDay() end
    return behavior.days[key]
end
local function countEntries(source)
    local total = 0
    for _ in pairs(source) do total = total + 1 end
    return total
end
local function publicName(kind, identifier)
    local value
    if kind == "map" then
        local _, info = NS.Try(C_Map and C_Map.GetMapInfo, identifier)
        value = NS.Field(info, "name")
    else
        local _, info = NS.Try(C_Spell and C_Spell.GetSpellInfo, identifier)
        value = NS.Field(info, "name")
        if NS.Text(value) == nil then
            local _, legacyName = NS.Try(GetSpellInfo, identifier)
            value = legacyName
        end
    end
    return NS.Text(value)
end
local function entry(day, kind, identifier)
    local list = kind == "map" and day.maps or day.spells
    if list[identifier] then return list[identifier] end
    if countEntries(list) >= ENTRIES then return nil end
    local result = kind == "map" and {seconds=0, visits=0} or {succeeded=0, failed=0, interrupted=0}
    result.name = publicName(kind, identifier)
    list[identifier] = result
    return result
end

-- Explicitly migrate only this schema. Arbitrary saved payloads never survive.
function NS.InitializeBehavior(source)
    local epoch = NS.Epoch()
    local valid = NS.Number(NS.Field(source, "schema")) == 1
    local generation = valid and NS.Text(NS.Field(source, "generation")) or nil
    local behavior = {schema=1, generation=generation or string.format("%.0f", epoch), dayBasis="UTC+08:00",
        createdAt=valid and nonnegative(NS.Field(source, "createdAt")) or epoch, updatedAt=epoch, days={}}
    local days = valid and NS.Field(source, "days") or nil
    if not NS.IsSecret(days) and type(days) == "table" then
        local today = math.floor((epoch + OFFSET)/DAY)
        -- Fixed 90-key lookup also bounds migration work on a corrupt source.
        for index=today-RETAIN+1,today do
            local key = dateForIndex(index)
            local old = NS.Field(days, key)
            if not NS.IsSecret(old) and type(old) == "table" then
                local day = newDay()
                day.time = numbers(NS.Field(old, "time"), timeKeys)
                day.counts = numbers(NS.Field(old, "counts"), countKeys)
                day.quality = numbers(NS.Field(old, "quality"), qualityKeys)
                for _, kind in ipairs({"spells", "maps"}) do
                    local list = NS.Field(old, kind)
                    if not NS.IsSecret(list) and type(list) == "table" then
                        local n = 0
                        for rawID, rawEntry in pairs(list) do
                            local identifier = id(rawID)
                            if identifier and not NS.IsSecret(rawEntry) and type(rawEntry) == "table" then
                                local keys = kind == "spells" and {"succeeded", "failed", "interrupted"} or {"seconds", "visits"}
                                local clean = numbers(rawEntry, keys)
                                clean.name = NS.Text(NS.Field(rawEntry, "name"))
                                day[kind][identifier] = clean
                                n = n + 1
                                if n >= ENTRIES then break end
                            end
                        end
                    end
                end
                behavior.days[key] = day
            end
        end
    end
    NS.db.behavior = behavior
    return behavior
end

local function readBaseline()
    local _, combat = NS.Try(UnitAffectingCombat, "player")
    combat = NS.Bool(combat)
    if combat == nil then local _, value = NS.Try(InCombatLockdown); combat = NS.Bool(value) end
    local _, dead = NS.Try(UnitIsDeadOrGhost, "player")
    local _, map = NS.Try(C_Map and C_Map.GetBestMapForUnit, "player")
    local _, level = NS.Try(UnitLevel, "player")
    local _, xp = NS.Try(UnitXP, "player")
    local _, xpMax = NS.Try(UnitXPMax, "player")
    return combat, NS.Bool(dead), id(map), {level=id(level), xp=nonnegative(xp), xpMax=id(xpMax)}
end
local function validXP(value)
    return value and value.level and value.xp and value.xpMax and value.xp <= value.xpMax
end
local function xpGap(day)
    local key = NS.BehaviorDate(currentEpoch())
    if runtime.xpGapDay ~= key then
        day.quality.xpGaps = day.quality.xpGaps + 1
        runtime.xpGapDay = key
    end
end
local function visit(map)
    if not map or map == runtime.lastVisitedMap then return end
    local day = dayAt(currentEpoch())
    local zone = entry(day, "map", map)
    if zone then zone.visits = zone.visits + 1 else day.quality.mapOverflow = day.quality.mapOverflow + 1 end
    runtime.lastVisitedMap = map
end
local function baseline()
    runtime.combat, runtime.dead, runtime.map, runtime.xp = readBaseline()
    runtime.xpGapDay = nil
    if not validXP(runtime.xp) then
        runtime.xp = nil
        if runtime.collecting then xpGap(dayAt(currentEpoch())) end
    end
    if runtime.collecting then visit(runtime.map) end
end

function NS.StartBehavior()
    if not NS.db.behavior then NS.InitializeBehavior(nil) end
    if NS.session then NS.session.behavior = {schema=1, daily=true} end
    runtime = {clock=clock(), epoch=NS.Epoch(), collecting=NS.db.settings.enabled == true}
    baseline()
    prune(NS.db.behavior, runtime.epoch)
end

function NS.SettleBehavior()
    if not runtime then return end
    local now = clock()
    local seconds = math.max(0, now - runtime.clock)
    local cursor, finish = runtime.epoch, runtime.epoch + seconds
    -- Long unscheduled gaps still retain only the last 90 days.
    if seconds > RETAIN*DAY then cursor = finish - RETAIN*DAY end
    while cursor < finish do
        local boundary = (math.floor((cursor + OFFSET)/DAY) + 1)*DAY - OFFSET
        local nextAt = math.min(finish, boundary)
        local span, day = nextAt - cursor, dayAt(cursor)
        if runtime.collecting then
            day.time.observedSeconds = day.time.observedSeconds + span
            local key = runtime.combat == true and "combatSeconds" or runtime.combat == false and "nonCombatSeconds" or "unknownCombatSeconds"
            day.time[key] = day.time[key] + span
            local zone = runtime.map and entry(day, "map", runtime.map)
            if zone then zone.seconds = zone.seconds + span
            else day.quality.unknownMapSeconds = day.quality.unknownMapSeconds + span end
        else day.time.pausedSeconds = day.time.pausedSeconds + span end
        cursor = nextAt
    end
    runtime.clock, runtime.epoch = now, finish
    NS.db.behavior.updatedAt = finish
    prune(NS.db.behavior, finish)
end

function NS.EnableBehavior(enabled)
    if not runtime then return end
    NS.SettleBehavior()
    runtime.collecting = enabled == true
    runtime.xp = nil
    -- Resume establishes new public baselines; no paused-period XP is recovered.
    if runtime.collecting then baseline() end
end
function NS.StopBehavior()
    NS.SettleBehavior()
    runtime = nil
end
function NS.BehaviorDropped()
    if not runtime or not runtime.collecting then return end
    local day = dayAt(currentEpoch())
    day.quality.detailDropped = day.quality.detailDropped + 1
end

local function xpSnapshot(day, data)
    local nextXP = {level=id(data.level), xp=nonnegative(data.xp), xpMax=id(data.xpMax)}
    if not validXP(nextXP) then
        xpGap(day)
        runtime.xp = nil
        return
    end
    local previous = runtime.xp
    if previous then
        local levels = nextXP.level - previous.level
        local gained
        if levels == 0 and nextXP.xp >= previous.xp then gained = nextXP.xp - previous.xp
        elseif levels == 1 then gained = previous.xpMax - previous.xp + nextXP.xp
        elseif levels == 0 and nextXP.xp < previous.xp then
            -- XP may reset before UnitLevel catches up. Preserve the old valid
            -- baseline until a coherent level snapshot arrives; never add a
            -- negative or guessed delta.
            return
        else day.quality.xpGaps = day.quality.xpGaps + 1 end
        if levels > 0 then day.counts.levelsGained = day.counts.levelsGained + levels end
        if gained then day.counts.xpGained = day.counts.xpGained + gained end
    end
    runtime.xp = nextXP
    runtime.xpGapDay = nil
end

function NS.RecordBehavior(kind, data)
    if not runtime or not runtime.collecting or NS.safetyStopped or NS.stopped then return end
    NS.SettleBehavior()
    local day = dayAt(currentEpoch())
    if kind == "combat" then
        local nextCombat = data.phase == "enter" and true or data.phase == "leave" and false
        if data.phase ~= "enter" and data.phase ~= "leave" then return end
        if runtime.combat ~= nextCombat then
            if nextCombat then day.counts.combatsEntered = day.counts.combatsEntered + 1
            elseif runtime.combat == true then day.counts.combatsCompleted = day.counts.combatsCompleted + 1 end
        end
        runtime.combat = nextCombat
    elseif kind == "death" then
        if data.event == "PLAYER_DEAD" then
            if runtime.dead ~= true then day.counts.deaths = day.counts.deaths + 1 end
            runtime.dead = true
        elseif data.event == "PLAYER_ALIVE" or data.event == "PLAYER_UNGHOST" then runtime.dead = false end
    elseif kind == "player_cast" then
        local identifier = id(data.spellID)
        if not identifier then return end
        local counter, spellKey
        if data.event == "UNIT_SPELLCAST_START" or data.event == "UNIT_SPELLCAST_CHANNEL_START" then counter = "castsStarted"
        elseif data.event == "UNIT_SPELLCAST_SUCCEEDED" then counter, spellKey = "castsSucceeded", "succeeded"
        elseif data.event == "UNIT_SPELLCAST_FAILED" then counter, spellKey = "castsFailed", "failed"
        elseif data.event == "UNIT_SPELLCAST_INTERRUPTED" then counter, spellKey = "castsInterrupted", "interrupted" end
        if counter then day.counts[counter] = day.counts[counter] + 1 end
        if spellKey then
            local spell = entry(day, "spell", identifier)
            if spell then spell[spellKey] = spell[spellKey] + 1 else day.quality.spellOverflow = day.quality.spellOverflow + 1 end
        end
    elseif kind == "quest" then
        if not id(data.questID) then return end
        local key = data.event == "QUEST_ACCEPTED" and "questsAccepted" or data.event == "QUEST_TURNED_IN" and "questsTurnedIn"
        if key then day.counts[key] = day.counts[key] + 1 end
    elseif kind == "snapshot" then
        xpSnapshot(day, data)
        runtime.combat = NS.Bool(data.combat)
        runtime.map = id(data.mapID)
        visit(runtime.map)
    end
end

function NS.GetBehaviorToday()
    if not NS.db or not NS.db.behavior then return newDay(), NS.BehaviorDate(NS.Epoch()) end
    local key = NS.BehaviorDate(currentEpoch())
    return NS.db.behavior.days[key] or newDay(), key
end

-- JSON uses string IDs, so empty/numeric-key maps remain objects. No generic
-- table copy is permitted for behavior data, even when a saved source is edited.
function NS.BuildBehaviorExport()
    local source = NS.db and NS.db.behavior
    if not source then return nil end
    local out = {schema=1, generation=NS.Text(NS.Field(source, "generation")), dayBasis="UTC+08:00",
        createdAt=nonnegative(NS.Field(source,"createdAt")), updatedAt=nonnegative(NS.Field(source,"updatedAt")), days={}}
    local days = NS.Field(source, "days")
    if NS.IsSecret(days) or type(days) ~= "table" then return out end
    local index = math.floor((currentEpoch() + OFFSET)/DAY)
    for dayIndex=index-RETAIN+1,index do
        local key = dateForIndex(dayIndex)
        local sourceDay = NS.Field(days, key)
        if not NS.IsSecret(sourceDay) and type(sourceDay) == "table" then
            local day = newDay()
            day.time = numbers(NS.Field(sourceDay,"time"),timeKeys)
            day.counts = numbers(NS.Field(sourceDay,"counts"),countKeys)
            day.quality = numbers(NS.Field(sourceDay,"quality"),qualityKeys)
            for _, kind in ipairs({"spells","maps"}) do
                local list = NS.Field(sourceDay,kind)
                if not NS.IsSecret(list) and type(list)=="table" then
                    local n=0
                    for rawID, value in pairs(list) do
                        local identifier=id(rawID)
                        if identifier and not NS.IsSecret(value) and type(value)=="table" then
                            local fields=kind=="spells" and {"succeeded","failed","interrupted"} or {"seconds","visits"}
                            local clean=numbers(value,fields)
                            clean.name=NS.Text(NS.Field(value,"name"))
                            day[kind][string.format("%.0f",identifier)]=clean
                            n=n+1
                            if n>=ENTRIES then break end
                        end
                    end
                end
            end
            out.days[key]=day
        end
    end
    return out
end
