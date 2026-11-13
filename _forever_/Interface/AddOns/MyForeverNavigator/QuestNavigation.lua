local _, NS = ...

local function validID(value)
    return NS.Number(value) and value > 0 and value % 1 == 0
end
local function clean(value, limit)
    return NS.CleanText(value, limit or 180)
end
local function tableValue(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "table"
end
local function truth(value)
    return not (issecretvalue and issecretvalue(value)) and value == true
end
local function falsehood(value)
    return not (issecretvalue and issecretvalue(value)) and value == false
end
local function titleFor(questID)
    local title = clean(NS.Call(C_QuestLog and C_QuestLog.GetTitleForQuestID, questID))
    return title ~= "" and title or ("任务 " .. questID)
end
local requests = {}
local function requestData(questID)
    local now = NS.Call(GetTime) or 0
    if requests[questID] and now >= requests[questID] and now - requests[questID] < 3 then return end
    requests[questID] = now
    NS.Call(C_QuestLog and C_QuestLog.RequestLoadQuestByID, questID)
end
local function objectiveRows(questID)
    local result = {}
    local rows = NS.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, questID)
    if tableValue(rows) then
        for _, row in ipairs(rows) do
            if tableValue(row) then
                local text = clean(row.text, 360)
                if text ~= "" then
                    local done = truth(row.finished)
                    if NS.Number(row.numRequired) and row.numRequired > 0 and NS.Number(row.numFulfilled)
                        and row.numFulfilled >= row.numRequired then done = true end
                    result[#result+1] = {text=text, type=clean(row.type, 40), finished=done}
                end
            end
        end
    end
    if #result > 0 then return result end
    local index = NS.Call(C_QuestLog and C_QuestLog.GetLogIndexForQuestID, questID)
    if not validID(index) then return result end
    local count = NS.Call(GetNumQuestLeaderBoards, index)
    if not NS.Number(count) then return result end
    for i=1, math.min(100, count) do
        local text, kind, finished = NS.Call(GetQuestLogLeaderBoard, i, index)
        text = clean(text, 360)
        if text ~= "" then result[#result+1] = {text=text, type=clean(kind, 40), finished=truth(finished)} end
    end
    return result
end
local function readyForTurnIn(questID)
    local ready = NS.Call(C_QuestLog and C_QuestLog.ReadyForTurnIn, questID)
    if truth(ready) then return true end
    -- Completed-history flags mean a previously handed-in quest, not a quest
    -- currently ready to deliver. Never use them for this decision.
    return truth(NS.Call(C_QuestLog and C_QuestLog.IsComplete, questID))
end
local kindTypes = {
    npc={monster=true, kill=true}, item={item=true}, object={object=true},
    area={event=true, log=true, area=true},
}
local function lower(text)
    return text:gsub("[A-Z]", string.lower)
end
local function matchLength(reference, row)
    local compatible = kindTypes[reference.kind]
    if row.type ~= "" and compatible and not compatible[row.type] then return 0 end
    local text, length = lower(row.text), 0
    for _, value in ipairs({reference.name or "", reference.english or ""}) do
        local name = lower(clean(value))
        if name ~= "" and text:find(name, 1, true) then length = math.max(length, #name) end
    end
    return length
end
local function progressFor(references, rows)
    local progress = {}
    for _, row in ipairs(rows) do
        local best, winners = 0, {}
        for i, reference in ipairs(references) do
            local length = matchLength(reference, row)
            if length > best then best, winners = length, {i}
            elseif length > 0 and length == best then winners[#winners+1] = i end
        end
        for _, index in ipairs(winners) do
            local old = progress[index]
            if not old then progress[index] = {finished=row.finished, text=row.text}
            elseif not row.finished then old.finished, old.text = false, row.text end
        end
    end
    return progress
end
local function nativePoint(questID)
    local mapID, x, y = NS.Call(C_QuestLog and C_QuestLog.GetNextWaypoint, questID)
    local function point(map, a, b)
        local p = {mapID=map, x=a, y=b}
        -- Both zero is commonly the client's unavailable-location sentinel.
        if NS.ValidPoint(p) and (a ~= 0 or b ~= 0) then return p end
    end
    local found = point(mapID, x, y)
    if found then return found end
    local maps, seen = {}, {}
    for _, id in ipairs({NS.Call(GetQuestUiMapID, questID) or false,
        NS.Call(C_Map and C_Map.GetBestMapForUnit, "player") or false}) do
        if validID(id) and not seen[id] then seen[id]=true;maps[#maps+1]=id end
    end
    for _, id in ipairs(maps) do
        x, y = NS.Call(C_QuestLog and C_QuestLog.GetNextWaypointForMap, questID, id)
        found = point(id, x, y)
        if found then return found end
        local pois = NS.Call(C_QuestLog and C_QuestLog.GetQuestsOnMap, id)
        if tableValue(pois) then
            for _, poi in ipairs(pois) do
                if tableValue(poi) and NS.Number(poi.questID) and poi.questID == questID
                    and not truth(poi.isQuestStart) then
                    found = point(validID(poi.mapID) and poi.mapID or id, poi.x, poi.y)
                    if found then return found end
                end
            end
        end
        if truth(NS.Call(C_TaskQuest and C_TaskQuest.IsActive, questID)) then
            x, y = NS.Call(C_TaskQuest and C_TaskQuest.GetQuestLocation, questID, id)
            found = point(id, x, y)
            if found then return found end
        end
    end
end
local function zoneFor(point)
    local map = NS.Call(C_Map and C_Map.GetMapInfo, point.mapID)
    local name = clean(tableValue(map) and map.name or point.zone, 90)
    return name ~= "" and name or ("地图 " .. point.mapID)
end
local function addReferenceTargets(state, references, rows, context)
    local progress = state.ready and {} or progressFor(references, rows)
    for index, reference in ipairs(references) do
        local status = progress[index]
        if state.ready or not status or not status.finished then
            local groups = {}
            for _, point in ipairs(tableValue(reference.points) and reference.points or {}) do
                if tableValue(point) and NS.ValidPoint(point) then
                    local key = point.mapID .. ":" .. tostring(point.sourceKind or reference.kind) .. ":" .. tostring(point.sourceID or reference.id or index)
                    local distance = NS.Call(NS.MeasurePoint, point, context)
                    if not NS.Number(distance) or distance < 0 then distance = nil end
                    local current = groups[key]
                    if not current or (distance and (not current.distance or distance < current.distance)) then
                        groups[key] = {point=point, distance=distance}
                    end
                end
            end
            local keys = {};for key in pairs(groups) do keys[#keys+1]=key end;table.sort(keys)
            for _, key in ipairs(keys) do
                local selected, uncertain = groups[key], not state.ready and not status
                local point = selected.point
                local kind = state.ready and "turnin" or reference.kind
                local name = clean(reference.name)
                if name == "" then name = "任务目标" end
                local sourceName = clean(point.sourceName)
                if kind == "item" and sourceName ~= "" then name = name .. " · " .. sourceName end
                local target = {
                    id="quest:" .. state.questID .. ":" .. tostring(kind) .. ":" .. tostring(reference.id or index) .. ":" .. key,
                    questID=state.questID, questPhase=state.ready and "turnin" or "objective",
                    name=name, kind=kind, category="quest", faction="Neutral",
                    mapID=point.mapID, x=point.x, y=point.y, zone=zoneFor(point),
                    source=point.source or "quest-reference", distance=selected.distance,
                    objectiveText=status and status.text or clean(reference.name), progressUncertain=uncertain,
                    note="离线任务参考点，非 NPC 或物品实时位置；同一目标在同区有多个位置时选择一个较近的已核对点。",
                }
                if kind == "item" then
                    target.note = target.note .. "物品位置表示掉落来源、容器或商人，不保证掉落、库存或取得条件。"
                end
                if uncertain then
                    target.note = target.note .. "未能与当前目标文字核对进度，请确认任务要求后再选择。"
                    state.hasUncertain = true
                end
                target.service = state.ready and "任务交付" or (kind == "item" and "任务物品来源" or "任务目标")
                state.targets[#state.targets+1] = target
            end
        end
    end
end

function NS.BuildQuestNavigation(questID)
    local state = {questID=questID, targets={}}
    if not validID(questID) then state.title="任务导航";state.invalid=true;state.message="没有有效的任务 ID。";return state end
    state.title = titleFor(questID)
    if falsehood(NS.Call(C_QuestLog and C_QuestLog.IsOnQuest, questID)) then
        state.invalid=true;state.message="该任务已不在任务日志中，请重新选择任务。";return state
    end
    state.ready = readyForTurnIn(questID)
    local rows = objectiveRows(questID)
    local reference = NS.Call(NS.GetQuestReference, questID)
    if tableValue(reference) and state.title == "任务 " .. questID and clean(reference.name) ~= "" then state.title=clean(reference.name) end
    local context = NS.Call(NS.GetLocationContext)
    if tableValue(reference) then
        addReferenceTargets(state, state.ready and (reference.turnin or {}) or (reference.objectives or {}), rows, context)
    end
    local native = nativePoint(questID)
    if native then
        native.id="quest:" .. questID .. ":native"
        native.questID, native.questPhase = questID, state.ready and "turnin" or "objective"
        native.kind, native.category, native.faction = state.ready and "turnin" or "area", "quest", "Neutral"
        native.name=state.ready and "交任务地点（客户端）" or "任务下一站（客户端）"
        native.zone, native.source = zoneFor(native), "client-quest-waypoint"
        native.service, native.nativeQuestTracking = "客户端任务航点", true
        native.objectiveText, native.note = state.title, "客户端提供的任务下一站；可能是任务区域或途中入口，不表示某个 NPC 或物品的实时位置。"
        native.distance=NS.Call(NS.MeasurePoint, native, context)
        if not NS.Number(native.distance) or native.distance < 0 then native.distance=nil end
        table.insert(state.targets, 1, native)
    end
    table.sort(state.targets, function(a,b)
        if (a.source=="client-quest-waypoint") ~= (b.source=="client-quest-waypoint") then return a.source=="client-quest-waypoint" end
        if a.progressUncertain ~= b.progressUncertain then return not a.progressUncertain end
        if (a.distance~=nil) ~= (b.distance~=nil) then return a.distance~=nil end
        if a.distance and a.distance~=b.distance then return a.distance<b.distance end
        if a.zone~=b.zone then return a.zone<b.zone end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    if #state.targets==0 then
        requestData(questID)
        state.message="暂时没有可靠的任务目标位置。可查看原生任务地图和说明，待任务数据载入后再双击；不会用玩家位置或任意地图中心代替。"
    elseif state.hasUncertain then
        state.message="请选择任务目标。部分离线参考未能匹配当前进度，请核对任务文字；已明确完成的目标已跳过。"
    else state.message=state.ready and "任务已完成，请选择交付地点。" or "请选择要导航的任务目标；已完成的目标已跳过。" end
    return state
end

local function startTarget(target)
    if type(NS.StartTransient) ~= "function" then return false, "任务导航尚未加载。" end
    local ok, reason = NS.StartTransient(target)
    if ok then NS.Call(NS.RefreshHUD);NS.Call(NS.RefreshUI) end
    return ok, reason
end
function NS.SelectQuestTarget(questID, target)
    if not tableValue(target) or target.questID ~= questID then return false, "任务目标已变化，请重新双击任务。" end
    local state = NS.BuildQuestNavigation(questID)
    for _, current in ipairs(state.targets) do
        if current.id == target.id then return startTarget(current) end
    end
    NS.Call(NS.ShowQuestTargets, questID, state.title, state.targets, "任务进度或目标已变化，请重新选择。")
    return false, "任务进度或目标已变化，请重新选择。"
end
function NS.OpenQuestNavigation(questID)
    local state = NS.BuildQuestNavigation(questID)
    if #state.targets == 1 and not state.targets[1].progressUncertain then
        local ok, reason = startTarget(state.targets[1])
        if ok then NS.Call(NS.HideQuestTargets);return true end
        state.message=reason or state.message
    end
    if NS.ShowQuestTargets then NS.ShowQuestTargets(questID, state.title, state.targets, state.message)
    else NS.Print(state.message) end
    return false, state.message
end
function NS.RefreshQuestSession()
    local point = NS.DB and NS.GetPoint(NS.DB.activeID)
    if not point or not validID(point.questID) then return end
    if falsehood(NS.Call(C_QuestLog and C_QuestLog.IsOnQuest, point.questID)) then
        NS.Stop();NS.Call(NS.RefreshHUD);NS.Call(NS.RefreshUI)
        return
    end
    local state = NS.BuildQuestNavigation(point.questID)
    for _, current in ipairs(state.targets) do
        if current.id == point.id and current.questPhase == point.questPhase then
            if point.source == "client-quest-waypoint" then
                -- Update the HUD's client-provided next stop without calling
                -- Start or reclaiming tracking changed by the player.
                for _, key in ipairs({"mapID","x","y","zone","name","kind","objectiveText","note"}) do point[key]=current[key] end
            end
            return
        end
    end
    NS.Stop();NS.Call(NS.RefreshHUD);NS.Call(NS.RefreshUI)
    NS.Call(NS.Print, "任务目标已完成或发生变化，请再次双击任务选择下一目标或交付地点。")
end
