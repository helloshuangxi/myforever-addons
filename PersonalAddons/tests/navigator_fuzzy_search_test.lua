local root, NS = "_forever_/Interface/AddOns/MyForeverNavigator/", {}
for _, file in ipairs({"Core.lua", "Classification.lua", "FuzzySearch.lua"}) do
    assert(loadfile(root..file))("MyForeverNavigator", NS)
end

local faction, map, locale = "Alliance", 1455, "zhCN"
UnitFactionGroup = function() return faction end
C_Map = {GetBestMapForUnit=function() return map end, GetMapInfo=function() return {name="铁炉堡"} end}
GetLocale = function() return locale end
local function point(id, name, english, service, category, mapID, side, profession)
    return {id=id,name=name,english=english,service=service,category=category,mapID=mapID,
        faction=side, zone=mapID==1455 and "铁炉堡" or "暴风城", x=.4,y=.6,professionKey=profession}
end
local miner = point("m","布洛克·寻石者","Brock Stoneseeker","采矿训练师","profession-trainers",1455,"Alliance","mining")
local minerSW = point("w","矮人矿工","Miner Newton","采矿训练师","profession-trainers",1453,"Alliance","mining")
local banker = point("b","巴尔瑟·铜腕","Barnum Stoneseeker","银行职员","services",1455,"Neutral")
local horde = point("h","矮人矿商","Fewer Stones","采矿材料商人","materials",1455,"Horde")
local hidden = point("questie-npc-45-1455","幽影银行家","Unknown","银行职员","services",1455,"Neutral")
hidden.questieSpawns = {{}}
local hiddenVisible = false
NS.Points = {miner, minerSW, banker, horde}
NS.GetCatalogPoints = function() return {miner,minerSW,banker,horde,hidden} end
NS.GetQuestiePoint = function(id) return id==hidden.id and hidden or nil end
NS.ResolvePoint = function(p) if p~=hidden or hiddenVisible then return p end end
NS.MeasurePoint = function(p) return p==miner and 42 or 66,"same-map" end
NS.Initialize(nil)
local n = 0
local function check(ok, message) n=n+1; assert(ok,message) end
local function only(query, options, id, kind)
    local hits = NS.FuzzySearch(query, options)
    check(#hits==1 and hits[1].id==id, "unexpected hits for "..query..": "..#hits)
    check(not kind or hits[1].matchKind==kind, "wrong match kind for "..query)
    return hits[1]
end
only("布洛克寻石者",nil,"m","exact")
only("布落克寻石者",nil,"m","fuzzy")
only("布洛寻石",nil,"m","fuzzy")
only("Brock SToneseker",nil,"m","fuzzy")
only("BrcoK",nil,"m","fuzzy")
only("Stoneseeker Brock",nil,"m","alias")
only("带我去铁炉学挖矿",nil,"m","alias")
only("请问哪里能学采矿 铁炉堡",nil,"m","alias")
only("学挖矿 暴风",nil,"w","alias")
only("铁炉堡哪里可以存钱", nil, "b", "alias")
only("附近的银行", nil, "b", "alias")
check(#NS.FuzzySearch("铁炉堡外星传送门")==0,"recognized city cannot erase unknown purpose")
check(#NS.FuzzySearch("附近的")==0,"filler is not an all-points query")
check(#NS.FuzzySearch("%[.*")==0,"pattern characters are literal")
check(#NS.FuzzySearch("采矿材料商人")==0,"opposing faction filtered")
only("采矿材料商人",{faction="all"},"h","exact")
only("采矿",{currentZone=true},"m","exact")
only("挖矿",{subcategory="profession-trainers:mining",currentZone=true},"m","alias")
check(#NS.FuzzySearch("挖矿",{category="materials"})==0,"aliases respect selected category")
only("最近的银行",{limit=1},"b","alias")
check(NS.FuzzySearch("采矿",{limit=0})[1]==nil,"bounded results")
check(NS.FuzzySearch(string.rep("中",70))[1]==nil,"oversized input does not silently navigate")
check(#NS.FuzzySearch("")==3 and NS.FuzzySearch("")[1].matchKind==nil,"empty query preserves browse behaviour")
check(miner.matchKind==nil and miner.matchScore==nil,"source records immutable")
check(#NS.FuzzySearch("幽影银行家")==0,"invisible phase suppressed")
hiddenVisible=true
only("幽影银行家",nil,hidden.id,"exact")
check(NS.RememberRoute("星星旅程",{hidden.id}),"can learn available phase")
hiddenVisible=false
check(NS.RecallRoute("星星旅程")==nil,"hidden phase makes cache miss")
hiddenVisible=true
check(NS.RecallRoute("星星旅程")[1]==hidden.id,"visible phase recovers exact learned entry")
hiddenVisible=false
check(NS.RememberRoute("my weekend tour",{"m","b"}),"learn verified stops")
local ids = NS.RecallRoute("MY   WEEKEND  TOUR")
check(ids and #ids==2 and ids[1]=="m" and ids[2]=="b","ordered and normalized")
ids[1]="wrong"
check(NS.RecallRoute("My weekend tour")[1]=="m","returned ID sequence is copied")
check(not NS.RememberRoute("my weekend tour",{"unknown"}),"invalid update rejected")
check(NS.RecallRoute("my weekend tour")[1]=="m","failed update leaves previous record")
check(not NS.RememberRoute("new",{"m",junk=1}),"not a dense ID array")
check(not NS.RememberRoute("new",{"m","m","m","m","m","m","m","m","m"}),"overlong itinerary")
check(not NS.RememberRoute("new",{"h"}),"opposing faction")
check(not NS.RememberRoute("new",{"quest:123"}),"transient quest")
local options={category="favorites",currentZone=true}
check(not NS.RememberRoute("帮我取钱",{"b"},options),"selection must match filters")
NS.DB.favorites.b=true
check(NS.RememberRoute("帮我取钱",{"b"},options),"save a favorite-scope alias")
only("帮我取钱",options,"b","alias")
check(not NS.RecallRoute("帮我取钱"),"scope isolation")
NS.DB.favorites.b=nil
check(not NS.RecallRoute("帮我取钱", options),"favorites revalidated")
check(not NS.RememberRoute("找最近的银行",{"b"}),"relative destination isn't frozen")
map=1453
check(not NS.RecallRoute("my weekend tour"),"different origin map")
map=1455; faction="Horde"
check(not NS.RecallRoute("my weekend tour"),"different faction")
faction="Alliance"; locale="enUS"
check(not NS.RecallRoute("my weekend tour"),"different locale")
locale="zhCN"
local learned = NS.DB
NS.Initialize(learned)
check(NS.RecallRoute("my weekend tour")[2]=="b","survives SavedVariables normalize/reload")
map=nil
check(not NS.RememberRoute("new",{"m"}) and not NS.RecallRoute("my weekend tour"),"unknown map")
map=1455
local custom=assert(NS.AddCustom("自己的航线",1455,.1,.3))
check(NS.RememberRoute("带我回家",{custom.id}),"own custom point")
check(not NS.RememberRoute("只能是NPC",{custom.id},{includeCustom=false}),"NPC-only excludes custom points")
NS.RemoveCustom(custom.id)
NS.Initialize(NS.DB)
local another=assert(NS.AddCustom("另一站",1455,.1,.4))
check(another.id~=custom.id and not NS.RecallRoute("带我回家"),"deleted custom ID never reused after reload")
for i=1,145 do check(NS.RememberRoute("alias "..i,{"m"}),"store bounded record "..i) end
check(#NS.DB.routeKnowledge.entries==128,"bounded per character")
check(NS.RecallRoute("alias 17")==nil and NS.RecallRoute("alias 18")[1]=="m","oldest entry evicted")
check(NS.RememberRoute("alias 140",{"b"}) and #NS.DB.routeKnowledge.entries==128,"updated alias consumes no extra slot")
check(NS.RecallRoute("alias 140")[1]=="b","new confirmed choice replaces previous alias")
local good=NS.DB.routeKnowledge.entries[1]
local clean=NS.NormalizeRouteKnowledge({version=1,entries={false,good,good,{scope="bad\n",query="x",ids={"m"}},
    {scope=good.scope,query="",ids={"m"}},{scope=good.scope,query="x",ids={"quest:1"}}}})
check(#clean.entries==1 and clean.entries[1].ids[1]=="b","malformed saved entries rejected and deduped")
check(#NS.NormalizeRouteKnowledge({version=9,entries={good}}).entries==0,"unknown schema ignored")
check(not NS.LookupRoutePhrase("我想学采矿"),"unloaded dictionary can arrive after search module")
assert(loadfile(root.."RoutePhrases.lua"))("MyForeverNavigator",NS)
for _, row in ipairs(NS.SharedRoutePhrases) do
    for _, alias in ipairs(row.aliases) do
        local terms=NS.LookupRoutePhrase("  "..alias.."？。 ")
        check(terms and #terms==#row.terms and terms~=row.terms,"shared ordered term copy for "..alias)
        for i, term in ipairs(row.terms) do check(terms[i]==term,"canonical term at stop "..i) end
        terms[1]="changed"
        check(NS.LookupRoutePhrase(alias)[1]==row.terms[1],"lookup cannot mutate source")
    end
end
check(not NS.LookupRoutePhrase("我要去一个新地方然后先修装备再绑炉石"),"shared aliases require a complete match")
check(not NS.LookupRoutePhrase("绑炉石再修装备"),"ordered actions cannot be reversed without a matching entry")
only("我想学挖矿",{currentZone=true},"m","alias")
print("Fuzzy query and learned route checks:",n)
