local NS = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/QuestData.lua"))("MyForeverNavigator", NS)
assert(type(NS.GetQuestReference) == "function")
assert(NS.GetQuestReference(nil) == nil)
assert(NS.GetQuestReference("not a quest") == nil)
assert(NS.GetQuestReference(-1) == nil)
assert(NS.GetQuestReference(99999999) == nil)

local function size(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
local quests, withGoals, withTurnin, areaQuests, areaPoints, checkedPoints = 0, 0, 0, 0, 0, 0
local counts, maps = {}, {}
local entities = {npc={},object={}}
local entityPoints = {}
local allowedKinds = {npc=true,item=true,object=true,area=true}
local allowedSources = {npc=true,object=true,drop=true,container=true,vendor=true,area=true}
local sourceEntityKinds = {npc="npc",drop="npc",vendor="npc",object="object",container="object"}

for questID = 1, 100000 do
    local reference = NS.GetQuestReference(questID)
    if reference then
        quests = quests + 1
        assert(type(reference.name) == "string" and reference.name ~= "")
        assert(type(reference.objectives) == "table" and type(reference.turnin) == "table")
        if #reference.objectives > 0 then withGoals = withGoals + 1 end
        if #reference.turnin > 0 then withTurnin = withTurnin + 1 end
        for section, rows in pairs({objectives=reference.objectives,turnin=reference.turnin}) do
            for _, goal in ipairs(rows) do
                assert((section == "turnin" and goal.kind == "turnin") or (section == "objectives" and allowedKinds[goal.kind]))
                assert(type(goal.id) == "number" and goal.id > 0 and goal.id % 1 == 0)
                assert(type(goal.name) == "string" and goal.name ~= "")
                assert(type(goal.english) == "string" and goal.english ~= "")
                assert(type(goal.points) == "table" and #goal.points > 0)
                if section == "objectives" then counts[goal.kind] = (counts[goal.kind] or 0) + 1 end
                if goal.kind == "area" then
                    areaQuests = areaQuests + 1
                    areaPoints = areaPoints + #goal.points
                end
                local seen = {}
                for _, point in ipairs(goal.points) do
                    checkedPoints = checkedPoints + 1
                    assert(type(point.mapID) == "number" and point.mapID > 0 and point.mapID % 1 == 0)
                    assert(type(point.x) == "number" and point.x > 0 and point.x < 1)
                    assert(type(point.y) == "number" and point.y > 0 and point.y < 1)
                    assert(type(point.zone) == "string" and point.zone ~= "")
                    assert(point.source == "pfquest-104f356" and point.areaReference == true)
                    assert(type(point.sourceName) == "string" and point.sourceName ~= "")
                    assert(type(point.sourceID) == "number" and point.sourceID > 0)
                    assert(allowedSources[point.sourceKind], "unknown source kind")
                    assert(not point.faction or point.faction == "Alliance" or point.faction == "Horde" or point.faction == "Neutral")
                    if goal.kind == "npc" or goal.kind == "object" then
                        assert(point.sourceKind == goal.kind and point.sourceID == goal.id)
                        assert(point.sourceName == goal.name)
                    elseif goal.kind == "turnin" then
                        assert((point.sourceKind == "npc" or point.sourceKind == "object") and point.sourceID == goal.id)
                    elseif goal.kind == "item" then
                        assert(point.sourceKind == "drop" or point.sourceKind == "container" or point.sourceKind == "vendor")
                    else
                        assert(point.sourceKind == "area", "exploration must not become a turn-in")
                    end
                    local key = point.sourceKind .. ":" .. point.sourceID .. ":" .. point.mapID .. ":" .. point.x .. ":" .. point.y
                    assert(not seen[key], "duplicate point in the same goal")
                    seen[key], maps[point.mapID] = true, true
                    local kind = sourceEntityKinds[point.sourceKind]
                    if kind then
                        entities[kind][point.sourceID] = true
                        entityPoints[kind .. ":" .. point.sourceID .. ":" .. point.mapID .. ":" .. point.x .. ":" .. point.y] = true
                    end
                end
            end
        end
    end
end
assert(quests == 3817 and withGoals == 1365 and withTurnin == 3762)
assert(counts.npc == 504 and counts.item == 1411 and counts.object == 69 and counts.area == 29)
assert(areaQuests == 29 and areaPoints == 36)
assert(size(maps) == 46)
assert(size(entities.npc) == 4146 and size(entities.object) == 578)
assert(size(entityPoints) == 57775)

local function findGoal(questID, kind, id)
    local reference = assert(NS.GetQuestReference(questID))
    local rows = kind == "turnin" and reference.turnin or reference.objectives
    for _, goal in ipairs(rows) do if goal.kind == kind and goal.id == id then return goal end end
    error("missing known quest reference: " .. questID .. ":" .. kind .. ":" .. id)
end
local item = findGoal(6, "item", 182)
assert(item.name == "加瑞克的头颅")
local garrick = false
for _, point in ipairs(item.points) do
    if point.sourceID == 103 and point.sourceKind == "drop" then
        assert(point.sourceName == "加瑞克·帕德弗特" and point.mapID == 1429)
        garrick = true
    end
end
assert(garrick, "quest item navigates to its actual drop source")
assert(findGoal(7, "npc", 6).name ~= "")
assert(findGoal(498, "object", 1721).name == "坚固链球")
local area = findGoal(62, "area", 62)
assert(area.points[1].sourceID == 88 and area.points[1].mapID == 1429)
assert(math.abs(area.points[1].x - .406) < .00001 and math.abs(area.points[1].y - .823) < .00001)
assert(findGoal(7, "turnin", 197).points[1].sourceKind == "npc")
assert(findGoal(37, "turnin", 55).points[1].sourceKind == "object")

local first = NS.GetQuestReference(6)
local expectedX, expectedName = first.objectives[1].points[1].x, first.objectives[1].points[1].sourceName
first.name, first.objectives[1].name = "modified", "modified"
first.objectives[1].points[1].x, first.objectives[1].points[1].sourceName = .99999, "modified"
first.turnin[1].points[1].mapID = 1
first.objectives[2] = {kind="invalid"}
local second = NS.GetQuestReference("6")
assert(second ~= first and second.objectives ~= first.objectives and second.turnin ~= first.turnin)
assert(second.name ~= "modified" and second.objectives[1].name ~= "modified")
assert(second.objectives[1].points[1].x == expectedX and second.objectives[1].points[1].sourceName == expectedName)
assert(second.turnin[1].points[1].mapID == 1429 and #second.objectives == 1)
print("Navigator quest data: 3817 quests; all bounds, source ownership, representative goals and isolated copies passed (" .. checkedPoints .. " returned points checked)")
