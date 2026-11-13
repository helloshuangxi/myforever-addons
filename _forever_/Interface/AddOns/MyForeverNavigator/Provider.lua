local _, NS = ...
local cache, lastProvider, lastZones, lastPhasing = {}, nil, nil, nil

-- Optional Forever data provider: the bundled directory always works without it.
-- Do not cache absent modules; they may initialize after ADDON_LOADED.
function NS.ResolvePoint(p, context)
    if p.questieSpawns and NS.ResolveQuestiePoint then return NS.ResolveQuestiePoint(p, context) end
    if not p.npcID or not LibQuestieDB or not QuestieLoader then return p end
    local db = LibQuestieDB
    if type(db.Npc) ~= "table" or type(db.Npc.Get) ~= "function" then return p end
    local zones = NS.Call(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
    if not zones or type(zones.GetUiMapIdByAreaId) ~= "function" then return p end
    local phasing = NS.Call(QuestieLoader.ImportModule, QuestieLoader, "Phasing")
    if db ~= lastProvider or zones ~= lastZones or phasing ~= lastPhasing then
        cache, lastProvider, lastZones, lastPhasing = {}, db, zones, phasing
    end
    local now = NS.Call(GetTime) or 0
    local stored = cache[p.id]
    if stored and now >= stored.time and now - stored.time < 2 then return stored.point end
    local spawns = NS.Call(db.Npc.Get, p.npcID, "spawns")
    if type(spawns) ~= "table" then return p end
    local chosen, score
    for areaID, locations in pairs(spawns) do
        local mapID = NS.Call(zones.GetUiMapIdByAreaId, zones, areaID)
        -- Keep each destination's intended zone (some NPCs have several spawns).
        if mapID == p.mapID and type(locations) == "table" then
            for _, loc in ipairs(locations) do
                if type(loc) == "table" and NS.Number(loc[1]) and NS.Number(loc[2])
                    and (loc[3] == nil or NS.Call(phasing and phasing.IsSpawnVisible, loc[3]) == true) then
                    local q = {mapID=mapID, x=loc[1]/100, y=loc[2]/100}
                    if NS.ValidPoint(q) then
                        local delta = (q.x-p.x)^2 + (q.y-p.y)^2
                        if not score or delta < score then chosen, score = q, delta end
                    end
                end
            end
        end
    end
    if not chosen then return p end
    local result = {}
    for k, v in pairs(p) do result[k] = v end
    result.x, result.y = chosen.x, chosen.y
    local name = NS.CleanText(NS.Call(db.Npc.Get, p.npcID, "name"), 90)
    if name ~= "" then result.name = name end
    result.note = "坐标已读取客户端 NPC 数据。" .. (p.note or "")
    result.provider = "QuestieDB"
    cache[p.id] = {time=now, point=result}
    return result
end
