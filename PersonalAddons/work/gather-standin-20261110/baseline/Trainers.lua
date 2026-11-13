local _, ns = ...

-- Read the installed Forever provider instead of shipping a second, stale NPC
-- database. Questie owns profession membership; QuestieDB owns localized data.
local call = ns.SafeCall
local npcCache, providerToken, trainerToken, localeToken, readyToken = {}, nil, nil, nil, nil
local supported = {[171]=true, [164]=true, [333]=true, [202]=true, [165]=true, [197]=true,
    [182]=true, [186]=true, [393]=true, [185]=true, [129]=true, [356]=true}
local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end
local function point(x, y) return number(x) and number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 end
local function vectorXY(vector)
    if type(vector) ~= "table" then return nil end
    local x, y = call(vector.GetXY, vector)
    if not number(x) or not number(y) then x, y = vector.x, vector.y end
    if number(x) and number(y) then return x, y end
end
local function module(name)
    return call(QuestieLoader and QuestieLoader.ImportModule, QuestieLoader, name)
end
local function mapInfo(mapID)
    if number(mapID) and mapID > 0 then return call(C_Map and C_Map.GetMapInfo, mapID) end
end
local function continent(mapID)
    local seen = {}
    for _ = 1, 12 do
        if seen[mapID] then return nil end
        seen[mapID] = true
        local info = mapInfo(mapID)
        if type(info) ~= "table" then return nil end
        if info.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2) then return mapID end
        if not number(info.parentMapID) or info.parentMapID <= 0 then return nil end
        mapID = info.parentMapID
    end
end
local function outdoor(info)
    local dungeon = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
    return type(info) == "table" and number(info.mapType) and info.mapType < dungeon
end
local function dragons()
    if LibStub and type(LibStub.GetLibrary) == "function" then
        return call(LibStub.GetLibrary, LibStub, "HereBeDragons-2.0", true)
    end
end
local function worldPosition(hbd, mapID, x, y)
    if not point(x, y) then return nil end
    local wx, wy, world = call(hbd and hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
    if number(wx) and number(wy) and number(world) then return wx, wy, world, "hbd" end
    local vector = call(CreateVector2D, x, y)
    if not vector then return nil end
    local mapWorld, position = call(C_Map and C_Map.GetWorldPosFromMapPos, mapID, vector)
    wx, wy = vectorXY(position)
    if number(mapWorld) and number(wx) and number(wy) then return wx, wy, mapWorld, "native" end
end
local function playerPosition(hbd, mapID, x, y)
    local wx, wy, world = call(hbd and hbd.GetPlayerWorldPosition, hbd)
    if number(wx) and number(wy) and number(world) then return wx, wy, world, "hbd" end
    return worldPosition(hbd, mapID, x, y)
end

function ns.InvalidateTrainerCache()
    npcCache = {}
end

local function getNPC(provider, zones, npcID)
    if npcCache[npcID] then return npcCache[npcID] end
    local get = provider.Npc.Get
    local name = call(get, npcID, "name")
    local spawns = call(get, npcID, "spawns")
    if type(name) ~= "string" or name == "" or type(spawns) ~= "table" then return nil end
    local npc = {npcID = npcID, name = name, subName = call(get, npcID, "subName"),
        faction = call(get, npcID, "friendlyToFaction"), locations = {}}
    local resolvedMap = false
    for areaID, locations in pairs(spawns) do
        local mapID = call(zones.GetUiMapIdByAreaId, zones, areaID)
        local info = mapInfo(mapID)
        if type(info) == "table" and type(locations) == "table" then
            resolvedMap = true
            for _, location in ipairs(locations) do
                if type(location) == "table" and number(location[1]) and number(location[2]) then
                    local x, y = location[1] / 100, location[2] / 100
                    if point(x, y) then
                        npc.locations[#npc.locations + 1] = {mapID = mapID, mapName = info.name,
                            x = x, y = y, phase = location[3], outdoor = outdoor(info), continent = continent(mapID)}
                    end
                end
            end
        end
    end
    -- A zone module can exist before its asynchronous initialization finishes.
    -- Do not freeze missing map data in the session cache.
    if resolvedMap then npcCache[npcID] = npc end
    return npc
end

-- distance is straight-line metres (the client APIs return yards), never a
-- walking route. Same-zone points win; other zones require a shared world frame.
function ns.GetNearbyTrainer(professionID)
    if not supported[professionID] then return nil, "暂无该专业的训练师资料" end
    if not QuestieLoader or not LibQuestieDB then return nil, "需要启用 Questie 和 QuestieDB" end
    local provider = LibQuestieDB
    if not provider.Npc or type(provider.Npc.Get) ~= "function" then return nil, "训练师数据加载中" end
    local townsfolk, zones = module("Townsfolk"), module("ZoneDB")
    local trainers = townsfolk and townsfolk.professionTrainers
    local ids = type(trainers) == "table" and trainers[professionID]
    if type(ids) ~= "table" or not next(ids) or not zones or type(zones.GetUiMapIdByAreaId) ~= "function" then
        return nil, "训练师数据加载中"
    end
    local locale = provider.l10n and provider.l10n.currentLocale
    local ready = Questie and Questie.API and Questie.API.isReady
    if providerToken ~= provider or trainerToken ~= trainers or localeToken ~= locale or readyToken ~= ready then
        ns.InvalidateTrainerCache()
        providerToken, trainerToken, localeToken, readyToken = provider, trainers, locale, ready
    end
    local currentMap = call(C_Map and C_Map.GetBestMapForUnit, "player")
    local currentInfo = mapInfo(currentMap)
    if type(currentInfo) ~= "table" then return nil, "当前位置暂不可用" end
    if call(IsInInstance) == true then return nil, "副本内暂不推荐外部训练师" end
    local faction = call(UnitFactionGroup, "player")
    faction = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    if not faction then return nil, "角色阵营加载中" end
    local hbd, phasing = dragons(), module("Phasing")
    local px, py = vectorXY(call(C_Map and C_Map.GetPlayerMapPosition, currentMap, "player"))
    local wx, wy, world, system = playerPosition(hbd, currentMap, px, py)
    local currentContinent = continent(currentMap)
    local width, height = call(C_Map and C_Map.GetMapWorldSize, currentMap)
    if not number(width) or not number(height) or width <= 0 or height <= 0 then
        width, height = call(hbd and hbd.GetZoneSize, hbd, currentMap)
    end
    local hasSize = number(width) and number(height) and width > 0 and height > 0
    local candidates = {}
    for _, npcID in ipairs(ids) do
        local npc = number(npcID) and getNPC(provider, zones, npcID)
        if npc and (npc.faction == faction or npc.faction == "AH") then
            for _, location in ipairs(npc.locations) do
                local visible = location.phase == nil or call(phasing and phasing.IsSpawnVisible, location.phase) == true
                if visible then
                    local sameMap = location.mapID == currentMap
                    local distance, score, priority, scope
                    if sameMap then
                        priority, scope = 1, "当前区域"
                        if point(px, py) then
                            local dx, dy = (location.x - px) * (hasSize and width or 1), (location.y - py) * (hasSize and height or 1)
                            score = math.sqrt(dx * dx + dy * dy)
                            if hasSize then distance = score * 0.9144 end
                        end
                    elseif outdoor(currentInfo) and location.outdoor then
                        local tx, ty, targetWorld, targetSystem = worldPosition(hbd, location.mapID, location.x, location.y)
                        if number(wx) and number(wy) and world == targetWorld and system == targetSystem and number(tx) and number(ty) then
                            score = math.sqrt((tx - wx)^2 + (ty - wy)^2)
                            distance, priority, scope = score * 0.9144, 2, "附近区域"
                        elseif not (number(world) and number(targetWorld) and system == targetSystem and world ~= targetWorld)
                            and currentContinent and currentContinent == location.continent then
                            priority, scope = 3, "同大陆训练师"
                        end
                    end
                    if priority and (score == nil or number(score)) then
                        candidates[#candidates + 1] = {npcID = npc.npcID, name = npc.name, subName = npc.subName,
                            mapID = location.mapID, mapName = location.mapName, x = location.x, y = location.y,
                            distance = distance, sameMap = sameMap, scope = scope, priority = priority, score = score}
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.score ~= b.score then return (a.score or math.huge) < (b.score or math.huge) end
        if a.mapID ~= b.mapID then return a.mapID < b.mapID end
        if a.npcID ~= b.npcID then return a.npcID < b.npcID end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local result = candidates[1]
    if not result then return nil, "当前区域暂无可靠训练师位置" end
    result.priority, result.score = nil, nil
    return result
end

local function openMap(mapID)
    if not WorldMapFrame then call(UIParentLoadAddOn, "Blizzard_WorldMap") end
    local frame = WorldMapFrame
    if not frame or type(frame.SetMapID) ~= "function" then return false end
    -- Forever's OpenWorldMap -> HandleUserActionOpenSelf uses ShowUIPanel.
    -- Showing the child frame directly can leave its owning panel hidden.
    local shown = false
    if type(OpenWorldMap) == "function" then
        shown = pcall(OpenWorldMap, mapID)
    elseif type(ShowUIPanel) == "function" then
        shown = pcall(ShowUIPanel, frame)
    end
    if not shown then return false end
    local changed = pcall(frame.SetMapID, frame, mapID)
    if not changed then return false end
    if type(frame.IsVisible) == "function" then
        if call(frame.IsVisible, frame) ~= true then return false end
    elseif type(frame.IsShown) ~= "function" or call(frame.IsShown, frame) ~= true then
        return false
    end
    if type(frame.GetMapID) == "function" and call(frame.GetMapID, frame) ~= mapID then return false end
    return true
end

-- Success distinguishes an actual pin from merely opening the correct map.
-- The caller keeps the trainer's coordinates visible for the map-only fallback.
function ns.ShowTrainerOnMap(record, useProfessionIcon)
    if type(record) ~= "table" or not point(record.x, record.y) or not mapInfo(record.mapID) then
        return false, "训练师位置不可用"
    end
    -- The selected profession icon already identifies the destination. A native
    -- waypoint at the same position would cover its texture while it pulses.
    if useProfessionIcon then
        if openMap(record.mapID) then return true, "icons" end
        return false, "暂时无法打开地图"
    end
    local marked = false
    if call(C_Map and C_Map.CanSetUserWaypointOnMap, record.mapID) == true then
        local waypoint = call(UiMapPoint and UiMapPoint.CreateFromCoordinates, record.mapID, record.x, record.y)
        if waypoint then marked = call(C_Map and C_Map.SetUserWaypoint, waypoint) == true end
    end
    if marked then call(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
    local opened = openMap(record.mapID)
    if marked and not opened then return false, "已标记训练师，但地图暂时无法打开" end
    if marked then return true, "marker" end
    if opened then return true, "map" end
    return false, "暂时无法打开地图"
end
