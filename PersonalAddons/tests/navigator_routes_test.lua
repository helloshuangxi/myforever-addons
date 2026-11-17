local base = "_forever_/Interface/AddOns/MyForeverNavigator/"
local NS, checks = {}, 0
local function check(value, message)
    checks = checks + 1
    assert(value, message or ("route check " .. checks))
end
local function load(name) assert(loadfile(base .. name .. ".lua"))("MyForeverNavigator", NS) end
local faction, player, pin, tracking, pinWrites, taxiRide = "Alliance", {}, nil, false, 0, false
UnitFactionGroup = function() return faction end
UnitOnTaxi = function() return taxiRide end
local function move(p) player = {mapID=p.mapID,x=p.x,y=p.y} end
local function vec(x,y) return {x=x,y=y} end
CreateVector2D = vec
UiMapPoint = {CreateFromCoordinates=function(id,x,y) return {uiMapID=id,position=vec(x,y)} end}
C_Map = {
    GetBestMapForUnit=function() return player.mapID end,
    GetPlayerMapPosition=function(id) if id == player.mapID then return vec(player.x,player.y) end end,
    GetMapInfo=function(id) return {mapID=id,name=tostring(id),mapType=3} end,
    GetMapWorldSize=function() return 3000,2000 end,
    GetUserWaypoint=function() return pin end,
    CanSetUserWaypointOnMap=function() return true end,
    SetUserWaypoint=function(value) pin=value; pinWrites=pinWrites+1; return true end,
}
C_SuperTrack = {
    IsSuperTrackingUserWaypoint=function() return tracking end,
    SetSuperTrackedUserWaypoint=function(value) tracking=value end,
}
GetPlayerFacing = function() return 0 end
GetTime = function() return 5 end
load("Core"); load("Data"); load("Navigation"); load("RouteData"); load("Routes")
NS.Initialize({})
local function location(mapID,x,y) return {mapID=mapID,x=x or 0.5,y=y or 0.5} end
local function custom(name,mapID,x,y)
    return assert(NS.AddCustom(name,mapID,x or 0.5,y or 0.5))
end
local function has(plan,mode)
    for _,step in ipairs(plan.steps) do if step.mode == mode then return true end end
end
local stormwind = custom("暴风城图书馆",1453)
local ironforge = custom("铁炉堡目标",1455)
local crossroads = custom("十字路口目标",1413)
local wetlands = custom("港口目标",1437)
local unknown = custom("其他区域",9999)
local auberdine = custom("奥伯丁目标",1439)
local function build(ids) return assert(NS.BuildRoute(ids)) end
move(location(1453))
local direct = build(stormwind)
check(#direct.steps == 1 and direct.steps[1].mode == "walk")
local route = build({ironforge.id, auberdine.id})
check(has(route,"tram") and has(route,"ship") and not has(route,"region"),"walk -> tram -> walk -> ship -> destination")
check(route.destinationID == auberdine.id and route.steps[#route.steps].id == auberdine.id)
local visited = {}
for _,step in ipairs(route.steps) do
    check(NS.ValidPoint(NS.GetPoint(step.id)) and #step.label > 0)
    visited[#visited+1]=step.id
end
check(table.concat(visited, ","):find(ironforge.id,1,true))
check(build(unknown).note ~= "" and has(build(unknown),"region"))
check(not NS.BuildRoute({"not-in-directory"}))
check(not NS.BuildRoute({ironforge.id, ironforge.id,ironforge.id,ironforge.id,ironforge.id,ironforge.id,ironforge.id}))
-- An unlocked-flight alternative must contain only public transit, ground or a
-- flight observed as reachable. Stormwind-to-Westfall has both ground and air.
local sentinel = NS.GetPoint("npc-523-1436")
move(NS.GetPoint("npc-352-1453"))
local provisional=build(sentinel)
check(provisional.hasUnconfirmedFlights and has(provisional,"flight"))
local ground=assert(NS.BuildRoute(sentinel,nil,{noUnconfirmedFlights=true}))
check(has(ground,"gate") and not has(ground,"region") and not ground.hasUnconfirmedFlights)
check(NS.StartRoute(ground) and NS.GetActiveRoute().noUnconfirmedFlights)
NS.Initialize(NS.DB)
check(NS.GetActiveRoute().noUnconfirmedFlights and not NS.GetActiveRoute().hasUnconfirmedFlights)
NS.Stop()
move(stormwind)
local fake = {id="no-id",name="假坐标",mapID=1453,x=0.1,y=0.5}
check(not NS.BuildRoute(fake))
local copied = build({id=ironforge.id,mapID=9999,x=0.1,y=0.5})
check(has(copied,"tram"),"map and coordinate supplied by a model must not create a destination")
local old = build({stormwind.id,ironforge.id})
check(NS.StartRoute(old) and NS.GetActiveRoute().index == 1)
local oldTarget = NS.DB.activeID
check(not NS.StartRoute({steps={{id="no-place",mode="walk",label="x"}},index=1,destinationID="no-place"}))
check(NS.DB.activeID == oldTarget and NS.GetActiveRoute().index == 1)
-- A player replaced the published pin before the next automatic leg.
pin = UiMapPoint.CreateFromCoordinates(1453,0.12,0.14)
local before = pinWrites
check(NS.UpdateRouteProgress() and NS.GetActiveRoute().index == 2)
check(pinWrites == before and pin.position.x == 0.12 and tracking)
local second = NS.DB.activeID
local saved = NS.DB
NS.Initialize(saved)
check(NS.GetActiveRoute().index == 2 and NS.DB.activeID == second)
check(NS.NextRouteStep() and NS.GetActiveRoute().index == 3)
while NS.GetActiveRoute().index < #NS.GetActiveRoute().steps do check(NS.NextRouteStep()) end
check(not NS.NextRouteStep() and not NS.GetActiveRoute().complete)
move(ironforge)
taxiRide = true
check(not NS.UpdateRouteProgress() and not NS.GetActiveRoute().complete)
taxiRide = false
check(NS.UpdateRouteProgress() and NS.GetActiveRoute().complete)
check(not NS.UpdateRouteProgress())
NS.Initialize(NS.DB)
check(NS.GetActiveRoute().complete and NS.GetActiveRoute().destinationID == ironforge.id)
check(NS.Stop() and not NS.GetActiveRoute() and not NS.DB.activeID)
check(NS.StartRoute(build({ironforge.id,stormwind.id})))
check(NS.Start(wetlands.id) and not NS.GetActiveRoute() and NS.DB.activeID == wetlands.id)
check(not NS.NormalizeRoute({index=1,steps={{id=ironforge.id,mode="teleport",label="x"}}},ironforge.id))
check(not NS.NormalizeRoute(old,"different-active-id"))
faction = "Horde"
move(location(1454))
local under = custom("幽暗城目标",1458)
check(has(build(under),"zeppelin") and has(build(under),"gate"))
check(not has(build(ironforge),"tram"))
-- Off-network routes do not invent connections, even when two maps are on the same continent.
move(unknown); check(has(build(crossroads),"region"))
-- Observed reachable destinations are directional; a closed return is not inferred.
local fromID, toID = "npc-3310-1454", "npc-2995-1456"
local org,thunder = NS.GetPoint(fromID),NS.GetPoint(toID)
move(org)
check(has(build(thunder),"flight"))
local rows,guid = {},nil
UnitGUID=function() return guid end
NumTaxiNodes=function() return #rows end
TaxiNodeGetType=function(i) return rows[i][1] end
TaxiNodeName=function(i) return rows[i][2] end
local function observe(station,name,offers)
    move(station)
    guid = "Creature-0-1-2-3-" .. station.npcID .. "-ABC"
    rows = {{"CURRENT",name}}
    for _,offer in ipairs(offers) do rows[#rows+1]={"REACHABLE",offer} end
    rows[#rows+1]={"DISTANT","未开放"}
    return NS.ObserveTaxiMap()
end
check(observe(org,"奥格瑞玛，杜隆塔尔",{"雷霆崖，莫高雷"}))
check(observe(thunder,"雷霆崖，莫高雷",{}))
NS.Initialize(NS.DB)
check(NS.DB.transit[toID].name == "雷霆崖，莫高雷" and #NS.DB.transit[toID].offers == 0)
move(org)
local openRoute = build(thunder)
local confirmed
for _,step in ipairs(openRoute.steps) do
    if step.mode == "flight" and step.id == toID then confirmed = not step.label:find("需已开航点",1,true) end
end
check(confirmed,"native observation should replace provisional flight on this leg")
local avoid=assert(NS.BuildRoute(thunder,nil,{noUnconfirmedFlights=true}))
check(has(avoid,"flight") and not avoid.hasUnconfirmedFlights)
move(thunder)
local returnRoute = build(org)
for _,step in ipairs(returnRoute.steps) do
    check(step.mode ~= "flight" or step.id ~= fromID or step.label:find("需已开航点",1,true),
        "observing an outbound flight must not verify the reverse")
end
-- The character can learn a flight outside the seeded graph.
local remoteID="npc-11139-1452"
local remote=NS.GetPoint(remoteID)
check(observe(org,"奥格瑞玛，杜隆塔尔",{"冬泉谷航点"}))
check(observe(remote,"冬泉谷航点",{}))
move(org)
local learned=build(remote)
check(has(learned,"flight") and not has(learned,"region"))
rows={{"CURRENT","奥格瑞玛，杜隆塔尔"}}
guid="Creature-0-1-2-3-999999-ABC"
check(not NS.ObserveTaxiMap())
issecretvalue=function(v) return v == "sensitive-guid" or v == "sensitive-node-type" end
guid="sensitive-guid"
rows={{"sensitive-node-type","private"}}
check(not NS.ObserveTaxiMap())
issecretvalue=nil
check(#NS.DB.transit[fromID].offers == 1)
rows={{"CURRENT","奥格瑞玛，杜隆塔尔"},{"CURRENT","其他"}}
guid="Creature-0-1-2-3-3310-ABC"
check(not NS.ObserveTaxiMap())
local sanitized=NS.NormalizeTransit({[fromID]={name="|x",offers={"|a",false}} ,unknown={name="unknown",offers={}}})
check(sanitized[fromID].name == "x" and sanitized[fromID].offers[1] == "a" and not sanitized.unknown)
load("FuzzySearch"); load("RoutePlanner")
NS.Initialize({})
faction = "Alliance"
local stops = NS.GetTransitStops()
check(#stops > 0)
for i,stop in ipairs(stops) do
    check(NS.GetTransitPoint(stop.id) == stop and (i == 1 or stops[i-1].id < stop.id))
    local found
    for _,result in ipairs(NS.FuzzySearch(stop.name,{includeTransit=true,faction="all"})) do
        if result.id == stop.id and result.matchKind == "exact" then found=true end
    end
    check(found,"missing transit stop " .. stop.name)
end
move(NS.GetTransitPoint("route-stop:booty-dock"))
check(#NS.Search("",{faction="all"}) == #NS.Points, "NPC catalogue gains no transit rows")
check(#NS.FuzzySearch("藏宝海湾码头") == 0, "NPC search excludes stops by default")
local ownStops = NS.FuzzySearch("码头",{includeTransit=true,currentZone=true})
check(#ownStops == 1 and ownStops[1].id == "route-stop:booty-dock")
check(#NS.FuzzySearch("格罗姆高奥格瑞玛飞艇站",{includeTransit=true}) == 0, "Alliance excludes Horde-only tower")
local travel = assert(NS.NewRouteQuery("带我去棘齿城码头"))
local destinations,maps = NS.GetRouteCandidates(travel)
check(maps == 1 and destinations[1].id == "route-stop:ratchet-dock")
check(NS.ChooseRouteCandidate(travel,destinations[1].id) and has(travel.plan,"ship"))
check(NS.ConfirmRouteQuery(travel) and NS.GetActiveRoute().destinationID == "route-stop:ratchet-dock")
local cached = assert(NS.NewRouteQuery("带我去棘齿城码头"))
check(cached.source == "cache" and cached.plan.destinationID == "route-stop:ratchet-dock")
local road = assert(NS.NewRouteQuery("前往艾尔文森林的路口"))
local crossings, regions = NS.GetRouteCandidates(road)
check(regions >= 2 and #crossings >= 2, "same-name stops on different maps stay selectable")
print("Navigator routes: " .. checks .. " checks passed")
