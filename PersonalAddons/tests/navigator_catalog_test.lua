local NS = {}
local root = "_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root .. "Core.lua"))("MyForeverNavigator", NS)
assert(loadfile(root .. "Data.lua"))("MyForeverNavigator", NS)
local ids, npcs, maps, categories = {}, {}, {}, {}
for _, c in ipairs(NS.Categories) do assert(not categories[c.id]); categories[c.id] = 0 end
for _, p in ipairs(NS.Points) do
    assert(NS.ValidPoint(p), "invalid coordinates: " .. tostring(p.id))
    assert(not ids[p.id], "duplicate point: " .. p.id)
    ids[p.id], npcs[p.npcID], maps[p.mapID] = true, true, true
    assert(categories[p.category], "unknown category")
    categories[p.category] = categories[p.category] + 1
    assert(p.faction == "Alliance" or p.faction == "Horde" or p.faction == "Neutral")
    for _, key in ipairs({"name","english","zone","service","note","source"}) do assert(type(p[key])=="string" and p[key]~="",p.id.." missing "..key) end
    assert(p.note:find("尚待游戏实测",1,true),"verification caveat missing")
end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
assert(count(ids)==427 and count(npcs)==427 and count(maps)==45)
assert(categories.trainers==195)
assert(categories.reputation==40 and categories.materials==109 and categories.special==26 and categories.services==57)
NS.Initialize(nil)
assert(#NS.Search("",{faction="all"})==427)
assert(#NS.Search("木喉",{faction="all"})>0)
assert(#NS.Search("瑟银",{faction="all"})>0)
print("Navigator catalogue: 427 NPC points, 45 maps; categories, coordinates, identities and search passed")

assert(loadfile(root .. "Classification.lua"))("MyForeverNavigator", NS)
local classCounts={warrior=32,paladin=11,hunter=29,rogue=24,priest=28,shaman=11,mage=24,warlock=21,druid=15}
for class,total in pairs(classCounts) do
    local result=NS.Search("",{category="trainers",subcategory="trainers:"..class,faction="all"})
    assert(#result==total,"missing class trainer locations: "..class)
    local factions={}
    for _,p in ipairs(result) do
        assert(p.category=="trainers" and p.service:find("训练师",1,true))
        assert(p.tags:find("职业训练师",1,true))
        assert(not p.service:find("宠物",1,true))
        factions[p.faction]=true
    end
    if class=="paladin" then assert(factions.Alliance and not factions.Horde)
    elseif class=="shaman" then assert(factions.Horde and not factions.Alliance)
    else assert(factions.Alliance and factions.Horde,"both factions covered for "..class) end
end
assert(#NS.Search("牧师",{category="trainers",faction="all"})==28)
assert(#NS.Search("Priest Trainer",{category="trainers",faction="all"})==28)
assert(#NS.Search("牧师",{category="trainers",currentZone=true,faction="all"})==0,"zone filter does not invent player map")
UnitFactionGroup=function()return "Alliance"end
assert(#NS.Search("",{category="trainers",faction="mine"})==105)
UnitFactionGroup=function()return "Horde"end
assert(#NS.Search("",{category="trainers",faction="mine"})==90)
UnitFactionGroup=nil
print("Navigator trainers: nine classes, exact counts, faction coverage and bilingual search passed")
