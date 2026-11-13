local _, NS = ...

-- Read QuestieDB's composed, localized API after Questie has applied its own
-- corrections. No upstream database or player data is copied into this addon.
local fields = {"name", "subName", "spawns", "npcFlags", "friendlyToFaction", "questStarts", "questEnds"}
local state = {status="unavailable", count=0, npcs=0, maps=0, processed=0, total=0, progress=0}
local published, byID, work, retry = nil, {}, nil, 0
local provider, zoneProvider, phaseProvider, phaseLoader

local function refresh()
    NS.Call(NS.RefreshUI)
end

local function status(value)
    if state.status ~= value then state.status = value; refresh() end
end

local function phaseModule()
    if phaseLoader ~= QuestieLoader or not phaseProvider then
        phaseLoader = QuestieLoader
        phaseProvider = QuestieLoader and NS.Call(QuestieLoader.ImportModule, QuestieLoader, "Phasing")
    end
    return phaseProvider
end

local function visible(spawn)
    if spawn[3] == nil then return true end
    local phase = phaseModule()
    return phase and NS.Call(phase.IsSpawnVisible, spawn[3]) == true or false
end

local function validSpawn(spawn)
    return type(spawn) == "table" and NS.Number(spawn[1]) and NS.Number(spawn[2])
        and spawn[1] >= 0 and spawn[1] <= 100 and spawn[2] >= 0 and spawn[2] <= 100
        and not (spawn[1] == 0 and spawn[2] == 0)
        and (spawn[3] == nil or NS.Number(spawn[3]) or type(spawn[3]) == "string")
end

function NS.GetCatalogPoints()
    return published or NS.Points or {}
end

function NS.GetQuestiePoint(id)
    return type(id) == "string" and byID[id] or nil
end

function NS.GetQuestieCatalogStatus()
    local result = {}
    for key, value in pairs(state) do result[key] = value end
    result.totalCount = #(published or NS.Points or {})
    return result
end

function NS.ResolveQuestiePoint(point, context)
    if type(point) ~= "table" or not point.questie or type(point.questieSpawns) ~= "table" then return nil end
    if type(context) ~= "table" then
        context = NS.Call(NS.GetLocationContext)
        if type(context) ~= "table" then
            local mapID, x, y = NS.Call(NS.GetPlayerPosition)
            context = {mapID=mapID, x=x, y=y}
        end
    end
    local nearby = context.mapID == point.mapID and NS.Number(context.x) and NS.Number(context.y)
    local width = NS.Number(context.width) and context.width > 0 and context.width or 1
    local height = NS.Number(context.height) and context.height > 0 and context.height or 1
    local chosen, score
    for _, spawn in ipairs(point.questieSpawns) do
        if validSpawn(spawn) and visible(spawn) then
            local distance = nearby and ((spawn[1]/100-context.x)*width)^2
                + ((spawn[2]/100-context.y)*height)^2 or 0
            if not chosen or distance < score then chosen, score = spawn, distance end
        end
    end
    if not chosen then return nil end
    if point.x == chosen[1]/100 and point.y == chosen[2]/100 then return point end
    local resolved = {}
    for key, value in pairs(point) do resolved[key] = value end
    resolved.x, resolved.y = chosen[1]/100, chosen[2]/100
    return resolved
end

-- Starting a navigation chooses one reference coordinate. Keep every phase
-- variant at that coordinate so visibility can still change, but never let
-- player movement choose a different spawn behind the native map waypoint.
function NS.FreezeQuestiePoint(point)
    if type(point) ~= "table" or not point.questie or not NS.ValidPoint(point)
        or type(point.questieSpawns) ~= "table" then return nil end
    local spawns = {}
    for _, spawn in ipairs(point.questieSpawns) do
        if validSpawn(spawn) and spawn[1]/100 == point.x and spawn[2]/100 == point.y then
            spawns[#spawns+1] = spawn
        end
    end
    if #spawns == 0 then return nil end
    local frozen = {}
    for key, value in pairs(point) do frozen[key] = value end
    frozen.questieSpawns = spawns
    return NS.ResolveQuestiePoint(frozen, {})
end

local function mapInfo(job, areaID)
    if job.areaMaps[areaID] ~= nil then return job.areaMaps[areaID] or nil end
    -- Some dungeon areas have aliases that map back to an outdoor zone.
    -- Their interior percentages cannot be used on that zone's world map.
    if type(job.zones.IsDungeonZone) == "function" and job.zones.IsDungeonZone(areaID) == true then
        job.areaMaps[areaID] = false
        return nil
    end
    local mapID = job.zones:GetUiMapIdByAreaId(areaID)
    local info = NS.Number(mapID) and mapID > 0 and mapID % 1 == 0
        and NS.Call(C_Map and C_Map.GetMapInfo, mapID)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if type(info) ~= "table" or info.mapType ~= zoneType
        or NS.CleanText(info.name, 90) == "" then
        job.areaMaps[areaID] = false
        return nil
    end
    local result = {id=mapID, name=NS.CleanText(info.name, 90)}
    job.areaMaps[areaID] = result
    return result
end

local function collectNPC(job, npcID)
    if not NS.Number(npcID) or npcID <= 0 or npcID % 1 ~= 0 or job.seenIDs[npcID] then return end
    job.seenIDs[npcID] = true
    local row = job.db.Npc.GetAll(npcID, fields)
    if type(row) ~= "table" then return end
    local name, subName, spawns = NS.CleanText(row[1], 90), NS.CleanText(row[2], 120), row[3]
    if name == "" or type(spawns) ~= "table" then return end
    local english = NS.CleanText(NS.Call(job.db.Npc.GetRaw, npcID, "name"), 90)
    local raw = {npcID=npcID, name=name, subName=subName, flags=row[4], friendly=row[5], questStarts=row[6], questEnds=row[7]}
    local template = job.templates[npcID]
    local role = NS.Call(NS.ClassifyQuestieNPC, raw, template)
    if type(role) ~= "table" then role = {category="npcs", service=subName ~= "" and subName or "其他 NPC", tags=""} end
    if role.professionKey then job.professionRoles[npcID] = role.professionKey end
    local areas = {}
    for areaID in pairs(spawns) do if NS.Number(areaID) and areaID > 0 then areas[#areas+1] = areaID end end
    table.sort(areas)
    local maps = {}
    for _, areaID in ipairs(areas) do
        local info, locations = mapInfo(job, areaID), spawns[areaID]
        if info and type(locations) == "table" and not job.curated[npcID .. ":" .. info.id] then
            local entry = maps[info.id]
            if not entry then entry={info=info, spawns={}, seen={}}; maps[info.id]=entry end
            for _, spawn in ipairs(locations) do
                if validSpawn(spawn) then
                    local key = spawn[1] .. ":" .. spawn[2] .. ":" .. tostring(spawn[3])
                    if not entry.seen[key] then
                        entry.seen[key] = true
                        entry.spawns[#entry.spawns+1] = spawn
                    end
                end
            end
        end
    end
    local mapIDs = {}
    for mapID in pairs(maps) do mapIDs[#mapIDs+1] = mapID end
    table.sort(mapIDs)
    for _, mapID in ipairs(mapIDs) do
        local entry = maps[mapID]
        local first = entry.spawns[1]
        if first then
            for _, spawn in ipairs(entry.spawns) do if visible(spawn) then first=spawn; break end end
            local point = {
                id="questie-npc-" .. npcID .. "-" .. mapID, npcID=npcID, name=name, english=english,
                category=NS.CleanText(role.category, 40), service=NS.CleanText(role.service, 180),
                catalogSubcategory=role.catalogSubcategory,
                professionKey=role.professionKey,
                tags=NS.CleanText((role.tags or "") .. " " .. subName, 360),
                faction=raw.friendly=="A" and "Alliance" or raw.friendly=="H" and "Horde"
                    or raw.friendly=="AH" and "Neutral" or "Hostile",
                mapID=mapID, x=first[1]/100, y=first[2]/100, zone=entry.info.name,
                note="QuestieDB 参考刷新位置，非 NPC 实时位置。多刷新点按同地图可见位置选择参考点；实际站位、相位与可达性以游戏为准。",
                source="QuestieDB", provider="QuestieDB", questie=true, questieSpawns=entry.spawns,
            }
            job.points[#job.points+1] = point
            job.index[point.id] = point
            job.npcs[npcID], job.maps[mapID] = true, true
        end
    end
end

local function count(values)
    local result=0
    for _ in pairs(values) do result=result+1 end
    return result
end

local function finish(job)
    published, byID = job.points, job.index
    NS.QuestieProfessionRoles = job.professionRoles
    provider, zoneProvider = job.db, job.zones
    state.count, state.npcs, state.maps = #job.points-job.curatedCount, count(job.npcs), count(job.maps)
    state.processed, state.progress, state.error = state.total, 1, nil
    work, retry = nil, 1
    state.status="ready"
    local activeID = NS.DB and NS.DB.activeID
    if type(activeID) == "string" and activeID:match("^questie%-npc%-") and not byID[activeID] then
        if NS.Stop then NS.Call(NS.Stop) else NS.DB.activeID=nil end
    end
    refresh()
end

local function begin(db, zones)
    local ids = db.Npc.GetAllIds()
    if type(ids) ~= "table" then error("QuestieDB NPC ID list unavailable") end
    local points, curated, templates = {}, {}, {}
    for _, point in ipairs(NS.Points or {}) do
        points[#points+1] = point
        if NS.Number(point.npcID) and NS.Number(point.mapID) then
            curated[point.npcID .. ":" .. point.mapID] = true
            templates[point.npcID] = templates[point.npcID] or point
        end
    end
    work = {db=db, zones=zones, ids=ids, cursor=1, points=points, index={}, curated=curated,
        curatedCount=#points, templates=templates, seenIDs={}, areaMaps={}, npcs={}, maps={}, professionRoles={}}
    state.processed, state.total, state.progress, state.error = 0, #ids, 0, nil
    phaseLoader, phaseProvider = nil, nil
    phaseModule()
    status("loading")
end

local function update(elapsed)
    if work and (work.db ~= LibQuestieDB or type(Questie) ~= "table"
        or type(Questie.API) ~= "table" or Questie.API.isReady ~= true) then
        work=nil
        retry=0
    end
    if not work then
        retry = retry - (NS.Number(elapsed) and math.max(0, elapsed) or 0)
        if retry > 0 then return end
        retry=1
        if type(Questie) ~= "table" or type(LibQuestieDB) ~= "table" then status("unavailable"); return end
        if type(Questie.API) ~= "table" or Questie.API.isReady ~= true then status("waiting"); return end
        local db = LibQuestieDB
        if type(db.Npc) ~= "table" or type(db.Npc.GetAllIds) ~= "function" or type(db.Npc.GetAll) ~= "function"
            or not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
            status("unavailable"); return
        end
        local zones = QuestieLoader:ImportModule("ZoneDB")
        if not zones or type(zones.GetUiMapIdByAreaId) ~= "function" then status("waiting"); return end
        if provider == db and zoneProvider == zones then state.error=nil; status("ready"); return end
        begin(db, zones)
    end
    local job, started, batch = work, NS.Call(debugprofilestop), 0
    while job.cursor <= #job.ids and batch < 40 do
        collectNPC(job, job.ids[job.cursor])
        job.cursor, batch = job.cursor+1, batch+1
        state.processed=job.cursor-1
        state.progress=state.total>0 and state.processed/state.total or 1
        local now = NS.Call(debugprofilestop)
        if NS.Number(started) and NS.Number(now) and now-started >= 2 then break end
    end
    if job.cursor > #job.ids then finish(job) end
end

function NS.UpdateQuestieCatalog(elapsed)
    local ok, reason = pcall(update, elapsed)
    if not ok then
        -- Publish only a complete catalogue. A failing provider never replaces
        -- the last good snapshot or leaks a half-filled directory into search.
        work, retry = nil, 10
        state.error=NS.CleanText(tostring(reason), 180)
        status("error")
    end
end
