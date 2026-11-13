local NS = {}
local root = "_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root .. "Core.lua"))("MyForeverNavigator", NS)
assert(loadfile(root .. "Provider.lua"))("MyForeverNavigator", NS)
local p = {id="npc:1",npcID=1,name="目录名称",mapID=1453,x=.2,y=.3,zone="暴风城",category="materials",faction="Neutral"}
assert(NS.ResolvePoint(p) == p, "independent of provider")
local spawns = {[1519]={{55.9,85.64},{20,30,"hidden"}}, [1]={{1,1}}}
LibQuestieDB = {Npc={Get=function(id,field)
    if field == "spawns" then return spawns end
    if field == "name" then return "当前客户端名称" end
end}}
local zones = {GetUiMapIdByAreaId=function(_,id) return id == 1519 and 1453 or 1411 end}
local phase = {IsSpawnVisible=function() return false end}
QuestieLoader = {ImportModule=function(_,name) return name=="ZoneDB" and zones or phase end}
local t = 1
GetTime = function() return t end
local q = NS.ResolvePoint(p)
assert(q ~= p and p.x == .2, "provider does not mutate bundled data")
assert(math.abs(q.x-.559) < 1e-10 and math.abs(q.y-.8564) < 1e-10 and q.name == "当前客户端名称")
assert(q.provider == "QuestieDB")
spawns = {[1519]={{50,60,"hidden"}}}
t = 4
assert(NS.ResolvePoint(p) == p, "hidden spawn never marked visible")
spawns = {[1]={{50,60}}}
t = 7
assert(NS.ResolvePoint(p) == p, "different zone not silently substituted")
QuestieLoader.ImportModule = function() return nil end
assert(NS.ResolvePoint(p) == p, "loading provider retains offline fallback")
print("Navigator provider: optional data, phases, map matching, immutable fallback passed")
