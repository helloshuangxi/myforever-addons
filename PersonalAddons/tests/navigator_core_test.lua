local NS = {}
local root = "_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root .. "Core.lua"))("MyForeverNavigator", NS)
NS.Points = {
    {id="a",name="联盟军需官",english="Alliance Quartermaster",zone="暴风城",service="声望 布匹",category="reputation",faction="Alliance",mapID=1453,x=.4,y=.5},
    {id="h",name="部落军需官",zone="奥格瑞玛",service="声望 布匹",category="reputation",faction="Horde",mapID=1454,x=.4,y=.5},
    {id="n",name="中立商人",zone="冬泉谷",service="符文线 材料",category="materials",faction="Neutral",mapID=1452,x=.4,y=.5},
}
UnitFactionGroup = function() return "Alliance" end
C_Map = {GetBestMapForUnit=function() return 1453 end,
    GetMapInfo=function(id) if id == 1453 then return {name="暴风城"} end end}
NS.GetPlayerPosition = function() return 1453,.3,.4 end
NS.Initialize(nil)
assert(#NS.Search("") == 2, "own faction includes neutral")
assert(#NS.Search("", {faction="all"}) == 3)
assert(#NS.Search("quartermaster 布匹") == 1, "English case insensitive, multiple AND terms")
assert(#NS.Search("%") == 0, "plain matching, no Lua patterns")
assert(#NS.Search("", {currentZone=true}) == 1)
assert(#NS.Search("", {category="materials"}) == 1)
NS.ToggleFavorite("a")
assert(#NS.Search("", {category="favorites"}) == 1)
NS.ToggleFavorite("a")
assert(#NS.Search("", {category="favorites"}) == 0)
assert(not NS.AddCustom("",1453,.1,.1))
assert(not NS.AddCustom("坏坐标",1453,1.01,.1))
assert(not NS.AddCustom("未知地图",99999,.1,.1))
assert(not NS.AddCustom("NaN",1453,0/0,.1))
local p = assert(NS.AddCustom("我的地点",1453,.25,.75))
assert(p.id == "custom:1" and #NS.Search("",{category="custom"}) == 1)
NS.ToggleFavorite(p.id)
NS.DB.activeID = p.id
NS.Stop = function() NS.DB.activeID = nil end
assert(NS.RemoveCustom(p.id) and NS.DB.activeID == nil and NS.DB.favorites[p.id] == nil)
local saved = assert(NS.SaveCurrent("站立位置"))
assert(saved.x == .3 and saved.y == .4 and saved.note:find("玩家站立位置",1,true))
GetSubZoneText = function() return "" end
assert(NS.SaveCurrent("").name == "我的地点", "empty subzone falls back to a usable name")
NS.GetPlayerPosition = function() return nil end
assert(not NS.SaveCurrent("不可用"))
local db = NS.NormalizeDB({custom={{id="custom:8",name="恢复的地点",mapID=1453,x=.1,y=.2},
    {id="custom:8",name="重复",mapID=1453,x=.1,y=.2},{id="a",name="冲突",mapID=1453,x=.1,y=.2}},
    panel={x=math.huge,y=0/0}, favorites={a=true,b="yes"},activeID="stale"})
assert(#db.custom == 1 and db.nextCustomID == 9 and db.panel.x == 0 and db.panel.y == 0)
assert(db.favorites.a and db.favorites.b == nil)
assert(NS.CleanText("|Tbad|t\nHello",90) == "Tbadt Hello")
assert(NS.CleanText(string.rep("中",50),90) == string.rep("中",30))
NS.Initialize(db)
assert(NS.DB.activeID == nil and NS.DB.nextCustomID == 9)
assert(#NS.Search("",{faction="all",includeCustom=false})==3,"NPC workspace excludes saved personal points")
NS.PointMatchesSubcategory=function(p,id) return id=="test-materials" and p.category=="materials" end
assert(#NS.Search("",{faction="all",subcategory="test-materials"})==1,"subcategory filters independently of query text")
assert(#NS.Search("",{faction="all",subcategory="missing"})==0,"unknown subcategory does not leak unrelated results")
NS.PointMatchesSubcategory=nil
local contextCount, context = 0, {mapID=1453}
NS.GetLocationContext = function() contextCount=contextCount+1;return context end
NS.MeasurePoint = function(p,c)
    assert(c==context,"one shared measurement context per search")
    if p.id=="a" then return 1200,"same-map" end
    if p.id=="n" then return 150,"same-continent" end
    return nil,"other-continent"
end
local results=NS.Search("",{faction="all"})
assert(contextCount==1 and results[1].id=="n" and results[1].distance==150,"nearer cross-zone point before farther same-map")
assert(results[#results].id=="h" and results[#results].distance==nil,"cross-continent distance unknown, placed last")
assert(NS.Points[1].distance==nil and NS.Points[3].scope==nil,"search never mutates catalogue")
results[1].name="edited result"
assert(NS.Points[3].name=="中立商人","results do not alias source records")
local names=NS.Search("",{sort="name",faction="all"})
for i=2,#names do assert(names[i-1].name<=names[i].name,"explicit name sorting") end
NS.MeasurePoint=function() return 0/0,"unexpected" end
assert(NS.Search("",{faction="all"})[1].distance==nil,"invalid measurement rejected")
NS.MeasurePoint=function() error("unavailable API") end
assert(#NS.Search("",{faction="all"})==4,"distance failure preserves catalogue and saved custom")
local input=assert(NS.ParseCoordinateInput("55.9,85.6 玛丽亚",1453))
assert(input.mapID==1453 and math.abs(input.x-.559)<1e-8 and input.name=="玛丽亚")
input=assert(NS.ParseCoordinateInput("55.9, 85.6 有空格的分隔",1453))
assert(math.abs(input.y-.856)<1e-8 and input.name=="有空格的分隔")
input=assert(NS.ParseCoordinateInput("/way #1453 55.9 85.6 目标",1426))
assert(input.mapID==1453 and input.name=="目标")
assert(NS.ParseCoordinateInput("0，100 角落",1453).y==1)
input=assert(NS.ParseCoordinateInput("45,2 67,8 小数逗号",1453))
assert(math.abs(input.x-.452)<1e-8 and math.abs(input.y-.678)<1e-8 and input.name=="小数逗号")
assert(not NS.ParseCoordinateInput("45,2,67,8",1453),"ambiguous four-value input rejected")
assert(not NS.ParseCoordinateInput("101 50 不合法",1453))
assert(not NS.ParseCoordinateInput("-1 50 不合法",1453))
C_Map.GetBestMapForUnit=function() return nil end
assert(not NS.ParseCoordinateInput("50 50"),"no current map means no silent map guessing")
local originalCustomCount = #NS.DB.custom
NS.TransientPoint = {id="quest:100:objective:1",questID=100,mapID=1453,x=.2,y=.3,name="临时任务目标",transient=true}
assert(NS.GetPoint("quest:100:objective:1") == NS.TransientPoint)
assert(NS.ToggleFavorite("quest:100:objective:1") == false and NS.DB.favorites["quest:100:objective:1"] == nil)
assert(#NS.Search("",{category="custom"}) == originalCustomCount, "transient points never enter personal places")
local persisted = NS.DB
persisted.activeID = "quest:100:objective:1"
persisted.favorites["quest:100:objective:1"] = true
NS.Initialize(persisted)
assert(NS.TransientPoint == nil and NS.DB.activeID == nil, "initialization discards session-only targets")
assert(NS.DB.favorites["quest:100:objective:1"] == nil and #NS.DB.custom == originalCustomCount)
print("Navigator core: search, factions, favorites, custom locations, invalid data and saved state passed")
