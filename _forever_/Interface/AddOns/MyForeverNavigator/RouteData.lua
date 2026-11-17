local _, NS = ...

-- Forever world-map stop and entrance references. City and neighbouring outdoor
-- map coordinates describe distinct sides of the same entrance.
local stops, links = {}, {}
local function stop(key, name, zone, mapID, x, y, faction)
    local id = "route-stop:" .. key
    stops[id] = {id=id, name=name, zone=zone, mapID=mapID, x=x/100, y=y/100,
        faction=faction, category="services", service="交通站点", source="forever-transit"}
    return id
end
local function link(a, b, mode)
    links[#links + 1] = {a=a, b=b, mode=mode}
end
local function pair(mode, faction, a, b)
    link(stop(a[1], a[2], a[3], a[4], a[5], a[6], faction),
        stop(b[1], b[2], b[3], b[4], b[5], b[6], faction), mode)
end
pair("ship", "Neutral",
    {"booty-dock","藏宝海湾码头","荆棘谷",1434,25.7,73.1},
    {"ratchet-dock","棘齿城码头","贫瘠之地",1413,63.8,38.8})
pair("ship", "Alliance",
    {"wetlands-theramore","米奈希尔港塞拉摩航线码头","湿地",1437,4.7,63.8},
    {"theramore-dock","塞拉摩码头","尘泥沼泽",1445,71.7,56.7})
pair("ship", "Alliance",
    {"stormwind-dock","暴风港奥伯丁航线码头","暴风城",1453,21.8,56.9},
    {"auberdine-stormwind","奥伯丁暴风港航线码头","黑海岸",1439,30.5,40.9})
pair("ship", "Alliance",
    {"ruttheran-dock","鲁瑟兰村码头","泰达希尔",1438,54.8,97.2},
    {"auberdine-ruttheran","奥伯丁鲁瑟兰航线码头","黑海岸",1439,33.3,39.8})
pair("zeppelin", "Horde",
    {"durotar-tirisfal","奥格瑞玛城外幽暗城飞艇站","杜隆塔尔",1411,51.0,13.9},
    {"tirisfal-durotar","幽暗城外奥格瑞玛飞艇站","提瑞斯法林地",1420,60.6,58.9})
pair("zeppelin", "Horde",
    {"durotar-gromgol","奥格瑞玛城外格罗姆高飞艇站","杜隆塔尔",1411,50.5,12.7},
    {"gromgol-durotar","格罗姆高奥格瑞玛飞艇站","荆棘谷",1434,31.2,30.4})
pair("zeppelin", "Horde",
    {"tirisfal-gromgol","幽暗城外格罗姆高飞艇站","提瑞斯法林地",1420,61.9,58.9},
    {"gromgol-tirisfal","格罗姆高幽暗城飞艇站","荆棘谷",1434,31.5,29.1})
pair("tram", "Alliance",
    {"stormwind-tram","矮人区地铁入口","暴风城",1453,66.6,34.7},
    {"ironforge-tram","地铁镇地铁入口","铁炉堡",1455,73.0,50.2})
pair("gate", "Alliance",
    {"stormwind-gate","暴风城城门内","暴风城",1453,74.5,92.3},
    {"elwynn-gate","暴风城城门外","艾尔文森林",1429,32.2,49.7})
pair("gate", "Alliance",
    {"ironforge-gate","铁炉堡城门内","铁炉堡",1455,21.9,77.5},
    {"dunmorogh-gate","铁炉堡城门外","丹莫罗",1426,53.3,35.1})
pair("gate", "Horde",
    {"orgrimmar-gate","奥格瑞玛正门内","奥格瑞玛",1454,52.4,83.7},
    {"durotar-gate","奥格瑞玛正门外","杜隆塔尔",1411,45.5,12.3})
pair("gate", "Horde",
    {"undercity-gate","幽暗城北入口内","幽暗城",1458,66.2,5.2},
    {"tirisfal-gate","幽暗城北入口外","提瑞斯法林地",1420,61.9,65.0})
pair("gate", "Neutral",
    {"elwynn-westfall","前往西部荒野的路口","艾尔文森林",1429,21.0,79.6},
    {"westfall-elwynn","前往艾尔文森林的路口","西部荒野",1436,62.0,17.9})
pair("gate", "Neutral",
    {"elwynn-redridge","前往赤脊山的路口","艾尔文森林",1429,93.2,72.3},
    {"redridge-elwynn","前往艾尔文森林的路口","赤脊山",1433,3.3,73.1})
pair("gate", "Neutral",
    {"dunmorogh-loch","通往洛克莫丹的南隘口","丹莫罗",1426,82.2,53.5},
    {"loch-dunmorogh","通往丹莫罗的南隘口","洛克莫丹",1432,21.5,66.2})
pair("gate", "Neutral",
    {"loch-wetlands","通往湿地的山口","洛克莫丹",1432,25.4,10.9},
    {"wetlands-loch","通往洛克莫丹的山口","湿地",1437,56.0,70.3})
pair("gate", "Neutral",
    {"durotar-barrens","通往贫瘠之地的桥","杜隆塔尔",1411,35.1,42.4},
    {"barrens-durotar","通往杜隆塔尔的桥","贫瘠之地",1413,62.6,19.2})
pair("gate", "Neutral",
    {"barrens-mulgore","通往莫高雷的路口","贫瘠之地",1413,41.2,58.6},
    {"mulgore-barrens","通往贫瘠之地的路口","莫高雷",1412,64.9,64.0})

-- Direct pairs in the local Forever flight references. Coordinates and NPC
-- names resolve from the existing directory. Unlocks depend on this character.
local function flight(a,b)
    link("npc-" .. a, "npc-" .. b, "flight")
end
flight("352-1453","523-1436")
flight("352-1453","931-1433")
flight("352-1453","2409-1431")
flight("352-1453","2859-1434")
flight("1573-1455","1571-1437")
flight("1573-1455","1572-1432")
flight("3841-1439","3838-1438")
flight("4321-1445","7823-1446")
flight("3310-1454","3615-1413")
flight("3615-1413","2995-1456")
flight("3310-1454","2995-1456")
flight("16227-1413","3615-1413")
flight("4551-1458","2226-1421")
flight("4551-1458","2389-1424")

function NS.GetTransitPoint(id)
    return stops[id]
end
local orderedStops = {}
for _, point in pairs(stops) do orderedStops[#orderedStops+1] = point end
table.sort(orderedStops, function(a,b) return a.id < b.id end)
function NS.GetTransitStops()
    return orderedStops
end
NS.TransitLinks = links
