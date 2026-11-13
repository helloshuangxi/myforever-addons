-- Simulated contracts, not game validation or a substitute for provider data.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local ns = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/API.lua"))("MyForeverProfessions", ns)
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/Trainers.lua"))("MyForeverProfessions", ns)
local function vector(x, y) return {x = x, y = y, GetXY = function(self) return self.x, self.y end} end
CreateVector2D = vector
Enum = {UIMapType = {Continent = 2, Zone = 3, Dungeon = 4}}
local maps = {
    [100] = {name = "东部王国", mapType = 2},
    [200] = {name = "卡利姆多", mapType = 2},
    [1426] = {name = "丹莫罗", mapType = 3, parentMapID = 100},
    [1455] = {name = "铁炉堡", mapType = 3, parentMapID = 100},
    [1412] = {name = "莫高雷", mapType = 3, parentMapID = 200},
    [900] = {name = "副本", mapType = 4, parentMapID = 1426},
}
local currentMap, px, py, instance, faction = 1426, 0.47, 0.52, false, "Alliance"
UnitFactionGroup = function() return faction end
IsInInstance = function() return instance end
C_Map = {
    GetBestMapForUnit = function() return currentMap end,
    GetMapInfo = function(id) return maps[id] end,
    GetPlayerMapPosition = function() return vector(px, py) end,
    GetMapWorldSize = function() return 1000, 500 end,
}
local npcReads, rows = 0, {
    [1] = {name = "附近友好", friendlyToFaction = "A", spawns = {[1] = {{48,52}}}},
    [2] = {name = "更近敌方", friendlyToFaction = "H", spawns = {[1] = {{47,52}}}},
    [3] = {name = "远处中立", friendlyToFaction = "AH", spawns = {[1] = {{60,60}}}},
    [4] = {name = "阵营未知", spawns = {[1] = {{47,52}}}},
    [5] = {name = "铁炉堡", friendlyToFaction = "A", spawns = {[1537] = {{50,50}}}},
    [6] = {name = "另一大陆", friendlyToFaction = "AH", spawns = {[215] = {{50,50}}}},
    [7] = {name = "隐藏阶段", friendlyToFaction = "A", spawns = {[1] = {{47,52,9}}}},
    [8] = {name = "无效坐标", friendlyToFaction = "A", spawns = {[1] = {{-1,-1},{101,30},{0/0,50}}}},
    [9] = {name = "副本训练师", friendlyToFaction = "A", spawns = {[9] = {{50,50}}}},
}
local townsfolk, zones, phases = {professionTrainers = {}}, {}, {}
zones.GetUiMapIdByAreaId = function(_, id) return ({[1]=1426,[1537]=1455,[215]=1412,[9]=900})[id] end
phases.IsSpawnVisible = function(phase) return phase ~= 9 end
local modules = {Townsfolk = townsfolk, ZoneDB = zones, Phasing = phases}
local result, reason = ns.GetNearbyTrainer(186)
eq(result, nil, "missing provider")
eq(reason, "需要启用 Questie 和 QuestieDB", "missing reason")
QuestieLoader = {ImportModule = function(_, name) return modules[name] end}
LibQuestieDB = {Npc = {Get = function(id, key) npcReads = npcReads + 1; return rows[id] and rows[id][key] end}, l10n={currentLocale="zhCN"}}
result, reason = ns.GetNearbyTrainer(186)
eq(reason, "训练师数据加载中", "wait for asynchronous Questie init")
local allIDs = {171,164,333,202,165,197,182,186,393,185,129,356}
for _, id in ipairs(allIDs) do townsfolk.professionTrainers[id] = {1,2,3,4,5,6,7,8,9} end
for _, id in ipairs(allIDs) do eq(ns.GetNearbyTrainer(id).npcID, 1, "all twelve profession IDs " .. id) end
result = ns.GetNearbyTrainer(186)
eq(result.scope, "当前区域", "same-zone label")
eq(result.mapName, "丹莫罗", "localized map")
eq(result.x, 0.48, "percent converted once")
eq(math.floor(result.distance * 1000 + 0.5), 9144, "yards converted to metres")
local previousReads = npcReads
ns.GetNearbyTrainer(186)
eq(npcReads - previousReads, 0, "records reuse decoded data including rejected coordinates")
px = 0.6; py = 0.6
eq(ns.GetNearbyTrainer(186).npcID, 3, "moving changes recommendation without clearing NPC cache")
faction = "Horde"
eq(ns.GetNearbyTrainer(186).npcID, 3, "faction checked at selection time")
faction = "Alliance"; px = 0.47; py = 0.52
townsfolk.professionTrainers[186] = {2,4,7,8,9}
eq(ns.GetNearbyTrainer(186), nil, "enemy unknown hidden invalid and external dungeon rejected")
townsfolk.professionTrainers[186] = {5,6,9}
result = ns.GetNearbyTrainer(186)
eq(result.npcID, 5, "fallback remains on same continent")
eq(result.scope, "同大陆训练师", "fallback never claims nearest")
eq(result.distance, nil, "no fabricated cross-zone distance")

C_Map.GetWorldPosFromMapPos = function(id, pos)
    if id == 1426 then return 0, vector(pos.x * 1000, pos.y * 500) end
    if id == 1455 then return 0, vector(470, 261) end
    if id == 1412 then return 1, vector(470, 260) end
    if id == 900 then return 30, vector(470, 260) end
end
result = ns.GetNearbyTrainer(186)
eq(result.scope, "附近区域", "native world comparison")
eq(math.floor(result.distance * 10000 + 0.5), 9144, "native world distance")
local nativeWorld = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = function(id, pos)
    if id == 1455 then return 30, vector(470,260) end
    return nativeWorld(id, pos)
end
eq(ns.GetNearbyTrainer(186), nil, "known different world never falls back to same continent")
C_Map.GetWorldPosFromMapPos = nativeWorld
townsfolk.professionTrainers[186] = {1,5}
eq(ns.GetNearbyTrainer(186).npcID, 1, "same map preferred even if city point closer")
townsfolk.professionTrainers[186] = {6,9}
eq(ns.GetNearbyTrainer(186), nil, "different world instances do not compare")
townsfolk.professionTrainers[186] = {5}
local hbd = {
    GetPlayerWorldPosition = function() return 100, 200, 0 end,
    GetWorldCoordinatesFromZone = function(_, x, y, id) if id == 1455 then return 103,204,0 end end,
}
LibStub = {GetLibrary = function() return hbd end}
result = ns.GetNearbyTrainer(186)
eq(math.floor(result.distance * 1000 + 0.5), 4572, "HereBeDragons uses matching world coordinates")
hbd.GetWorldCoordinatesFromZone = function() return nil end
result = ns.GetNearbyTrainer(186)
eq(result.distance, nil, "HBD and native coordinate systems are not mixed")
instance = true
eq(ns.GetNearbyTrainer(186), nil, "no exterior routing from a dungeon")
instance = false
LibStub = nil
C_Map.GetWorldPosFromMapPos = nil
currentMap = nil
eq(ns.GetNearbyTrainer(186), nil, "nil player map is safe")
currentMap = 1426
local getPosition = C_Map.GetPlayerMapPosition
C_Map.GetPlayerMapPosition = function() return vector(0/0, math.huge) end
townsfolk.professionTrainers[186] = {1}
eq(ns.GetNearbyTrainer(186).distance, nil, "invalid player coordinates do not leak NaN")
C_Map.GetPlayerMapPosition = getPosition
local getter = LibQuestieDB.Npc.Get
LibQuestieDB.Npc.Get = function() error("provider starting") end
ns.InvalidateTrainerCache()
eq(ns.GetNearbyTrainer(186), nil, "provider failure contained")
LibQuestieDB.Npc.Get = getter
eq(ns.GetNearbyTrainer(186).npcID, 1, "provider recovers without reload")
rows[1].name = "更新后的名称"
LibQuestieDB.l10n.currentLocale = "enUS"
eq(ns.GetNearbyTrainer(186).name, "更新后的名称", "locale changes clear static cache")

local shown, parentVisible, mapID, pinned, superTracked = false, false, nil, nil, nil
local nativeOpens, panelOpens, directShows = 0, 0, 0
WorldMapFrame = {
    Show = function() shown = true; directShows = directShows + 1 end,
    IsShown = function() return shown end,
    IsVisible = function() return shown and parentVisible end,
    SetMapID = function(_, id) mapID = id end,
    GetMapID = function() return mapID end,
}
ShowUIPanel = function(frame)
    eq(frame, WorldMapFrame, "panel manager receives world map")
    panelOpens = panelOpens + 1
    shown, parentVisible = true, true
end
OpenWorldMap = function(id)
    nativeOpens = nativeOpens + 1
    ShowUIPanel(WorldMapFrame)
    WorldMapFrame:SetMapID(id)
end
UiMapPoint = {CreateFromCoordinates = function(id,x,y) return {uiMapID=id,position=vector(x,y)} end}
C_Map.CanSetUserWaypointOnMap = function() return true end
C_Map.SetUserWaypoint = function(value) pinned = value; return true end
C_SuperTrack = {SetSuperTrackedUserWaypoint = function(value) superTracked = value end}
result = ns.GetNearbyTrainer(186)
local ok, mode = ns.ShowTrainerOnMap(result)
eq(ok, true, "marker success")
eq(mode, "marker", "marker outcome explicit")
eq(pinned.uiMapID, 1426, "waypoint uses UI map ID")
eq(pinned.position.x, 0.48, "waypoint normalized coordinates")
eq(superTracked, true, "pin supertracking")
eq(mapID, 1426, "correct map shown")
eq(nativeOpens, 1, "native OpenWorldMap used")
eq(directShows, 0, "never shows child frame directly")
C_Map.SetUserWaypoint = function() return false end
ok, mode = ns.ShowTrainerOnMap(result)
eq(ok, true, "map fallback succeeds")
eq(mode, "map", "failed pin not represented as successful pin")
C_Map.CanSetUserWaypointOnMap = function() error("unavailable") end
ok, mode = ns.ShowTrainerOnMap(result)
eq(mode, "map", "guarded unsupported waypoint")
local nativeOpen = OpenWorldMap
OpenWorldMap = nil
local oldPanelOpens = panelOpens
ok, mode = ns.ShowTrainerOnMap(result)
eq(mode, "map", "ShowUIPanel fallback when global opener absent")
eq(panelOpens, oldPanelOpens + 1, "fallback uses panel manager")
OpenWorldMap = function() shown = true; parentVisible = false end
eq(ns.ShowTrainerOnMap(result), false, "shown child with hidden parent is failure")
OpenWorldMap = function() error("blocked") end
eq(ns.ShowTrainerOnMap(result), false, "map display failure reported")
C_Map.CanSetUserWaypointOnMap = function() return true end
C_Map.SetUserWaypoint = function() return true end
ok, mode = ns.ShowTrainerOnMap(result)
eq(ok, false, "successful pin cannot disguise failed map opening")
eq(mode, "已标记训练师，但地图暂时无法打开", "partial outcome explicit")
OpenWorldMap = nativeOpen
C_Map.SetUserWaypoint = function() return false end
WorldMapFrame.GetMapID = function() return 1455 end
eq(ns.ShowTrainerOnMap(result), false, "wrong map does not pass verification")
WorldMapFrame.GetMapID = function() return mapID end
local waypointCalls, trackingCalls = 0, 0
C_Map.SetUserWaypoint = function() waypointCalls = waypointCalls + 1; return true end
C_SuperTrack.SetSuperTrackedUserWaypoint = function() trackingCalls = trackingCalls + 1 end
ok, mode = ns.ShowTrainerOnMap(result, true)
eq(ok, true, "profession icon opens actual map")
eq(mode, "icons", "icon outcome explicit")
eq(waypointCalls, 0, "profession icon not covered by a new waypoint")
eq(trackingCalls, 0, "icon mode does not alter tracking")
OpenWorldMap = function() error("blocked") end
eq(ns.ShowTrainerOnMap(result, true), false, "icon mode still checks map failure")
OpenWorldMap = nativeOpen
result.x = 0/0
eq(ns.ShowTrainerOnMap(result), false, "invalid waypoint rejected")
print("MyForeverProfessions trainers: " .. checks .. " simulated checks passed")
