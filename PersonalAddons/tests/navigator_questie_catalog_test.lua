local root = "_forever_/Interface/AddOns/MyForeverNavigator/"
local checks=0
local function check(value, message) checks=checks+1; assert(value, message) end
local function loadCatalog()
    Questie, LibQuestieDB, QuestieLoader, C_Map, Enum, debugprofilestop = nil, nil, nil, nil, nil, nil
    local ns={}
    assert(loadfile(root .. "Core.lua"))("MyForeverNavigator", ns)
    ns.Points={{id="curated-1",npcID=1,mapID=10,name="精选",category="trainers",service="牧师训练师",tags="牧师",x=.1,y=.1}}
    ns.refreshes=0
    ns.RefreshUI=function() ns.refreshes=ns.refreshes+1 end
    assert(loadfile(root .. "QuestieCatalog.lua"))("MyForeverNavigator", ns)
    return ns
end
local rows, calls, ids
local zones={GetUiMapIdByAreaId=function(_, id)
    return ({[100]=10,[101]=10,[200]=20,[300]=30,[400]=40,[500]=50,[600]=60,[700]=70,[800]=10})[id]
end, IsDungeonZone=function(id) return id==800 end}
local phaseVisible=false
local phase={IsSpawnVisible=function(value) return value==7 and phaseVisible end}
local function install(fixtureIDs, fixtureRows)
    rows, calls, ids=fixtureRows or {}, 0, fixtureIDs or {}
    Questie={API={isReady=true}}
    LibQuestieDB={Npc={GetAllIds=function() return ids end, GetAll=function(id, requested)
        calls=calls+1
        check(requested[1]=="name" and requested[7]=="questEnds", "requested fields use explicit packed positions")
        return rows[id]
    end}}
    QuestieLoader={ImportModule=function(_, name) return name=="ZoneDB" and zones or name=="Phasing" and phase or nil end}
    C_Map={GetMapInfo=function(id)
        return ({[10]={name="区域十",mapType=3},[20]={name="区域二十",mapType=3},[30]={name="副本",mapType=4},
            [40]={name="大陆",mapType=2},[50]={name="城内区",mapType=5},[60]={name="未知类型"}})[id]
    end}
end
local function drain(ns)
    for _=1,100 do
        ns.UpdateQuestieCatalog(1)
        local s=ns.GetQuestieCatalogStatus()
        if s.status=="ready" or s.status=="error" then return s end
    end
    error("catalogue did not settle")
end

local ns=loadCatalog()
check(ns.GetCatalogPoints()==ns.Points, "no optional provider retains authored catalogue")
ns.UpdateQuestieCatalog(0)
check(ns.GetQuestieCatalogStatus().status=="unavailable", "missing Questie is explicit")
install({1,2,3,4,5,6,7,8,9,10,11}, {
    [1]={n=7,[1]="精选的新名字",[3]={[100]={{10,10}},[200]={{20,20}}},[5]="A"},
    [2]={n=7,[1]="|cabcdef材料商|r",[2]="材料\n补给",[3]={[100]={{20,30},{20,30},{80,90},{-1,-1},{101,10},{0/0,0}},[101]={{60,70}}},[4]=4,[5]="AH"},
    [3]={n=7,[1]="敌对怪物",[3]={[200]={{50,50}}}},
    [4]={n=7,[1]="相位目标",[3]={[100]={{5,6,7}}},[5]="H"},
    [5]={n=7,[1]="非法地图",[3]={[300]={{10,20}},[400]={{10,20}},[600]={{10,20}},[700]={{10,20}},[999]={{10,20}}}},
    [6]={n=7,[1]="室内区",[3]={[500]={{100,0}}},[5]="AH"},
    [7]={n=7,[3]={[100]={{10,20}}}},
    [8]={n=7,[1]="无坐标",[3]={[100]={{-1,-1},{0,0}}}},
    [9]={n=7,[1]="非法相位",[3]={[100]={{10,20,{}}}}},
    [10]={n=7,[1]="多个可见相位",[3]={[100]={{30,40,7},{90,80}}},[5]="AH"},
    [11]={n=7,[1]="副本地图别名",[3]={[800]={{50,50}}},[5]="AH"},
})
Questie.API.isReady=false
ns.UpdateQuestieCatalog(2)
check(calls==0 and ns.GetQuestieCatalogStatus().status=="waiting", "wait for Questie locale and corrections readiness")
Questie.API.isReady=true
local s=drain(ns)
check(s.status=="ready" and s.count==5 and s.npcs==5 and s.maps==2, "one NPC record per world map, filtered map and coordinate coverage")
check(#ns.GetCatalogPoints()==6 and ns.GetCatalogPoints()[1]==ns.Points[1], "curated list retained without mutation")
check(ns.GetQuestiePoint("questie-npc-11-10")==nil,"dungeon area alias never uses an outdoor map's coordinates")
check(ns.Points[1].name=="精选" and ns.GetQuestiePoint("questie-npc-1-10")==nil, "same NPC/map keeps curated identity")
local extra=ns.GetQuestiePoint("questie-npc-1-20")
check(extra and extra.faction=="Alliance", "other map for same NPC remains available")
local target=ns.GetQuestiePoint("questie-npc-2-10")
check(target and target.faction=="Neutral" and #target.questieSpawns==3, "duplicate positions deduplicated across area aliases")
check(target.name=="cabcdef材料商r" and target.tags:find("材料 补给",1,true), "localized names and titles sanitized")
check(target.questie and target.provider=="QuestieDB" and target.source=="QuestieDB", "runtime source marked")
check(target.note:find("非 NPC 实时位置",1,true), "reference location not live tracking")
check(ns.GetQuestiePoint("questie-npc-3-20").faction=="Hostile", "nil friend faction remains hostile, not fake neutral")
check(ns.GetQuestiePoint("questie-npc-4-10").faction=="Horde", "Horde metadata preserved")
check(not ns.GetQuestiePoint("questie-npc-5-30") and not ns.GetQuestiePoint("questie-npc-5-40"), "dungeon and continent coordinates excluded")
check(not ns.GetQuestiePoint("questie-npc-6-50"), "micro maps excluded while navigation cannot direct within them")
check(not ns.GetQuestiePoint("questie-npc-7-10") and not ns.GetQuestiePoint("questie-npc-8-10"), "missing names, zero origins and sentinel locations excluded")
check(not ns.GetQuestiePoint("questie-npc-9-10"), "invalid phase data excluded")
check(ns.GetQuestieCatalogStatus().processed==#ids and ns.GetQuestieCatalogStatus().progress==1, "build progress completes")
local snapshot=ns.GetCatalogPoints()
for _=1,5 do ns.UpdateQuestieCatalog(2) end
check(calls==#ids and ns.GetCatalogPoints()==snapshot, "completed API index stable and not rebuilt every frame")
local copy=ns.GetQuestieCatalogStatus();copy.status="edited"
check(ns.GetQuestieCatalogStatus().status=="ready", "status caller cannot mutate internal state")

local resolved=ns.ResolveQuestiePoint(target,{mapID=10,x=.78,y=.89})
check(resolved and resolved.x==.8 and resolved.y==.9, "closest visible reference chosen for same-map player")
check(target.x==.2 and target.y==.3 and resolved~=target, "resolved reference never edits catalogue source")
check(ns.ResolveQuestiePoint(target,{mapID=20,x=.78,y=.89})==target, "different map cannot choose proximity by incompatible coordinates")
ns.GetPlayerPosition=function() return 10,.59,.69 end
check(ns.ResolveQuestiePoint(target).x==.6, "point lookup without context still uses current-map player")
check(ns.ResolveQuestiePoint(ns.GetQuestiePoint("questie-npc-4-10"))==nil, "hidden phase has no navigation reference")
phaseVisible=true
check(ns.ResolveQuestiePoint(ns.GetQuestiePoint("questie-npc-4-10")).x==.05, "late-visible phase does not require rebuilding catalogue")
phaseVisible=false
check(ns.ResolveQuestiePoint(ns.GetQuestiePoint("questie-npc-10-10"),{mapID=10,x=.3,y=.4}).x==.9, "invisible nearest spawn cannot override visible farther one")
local oldLoader=QuestieLoader
QuestieLoader={ImportModule=function(_,name) return name=="ZoneDB" and zones or nil end}
check(ns.ResolveQuestiePoint(ns.GetQuestiePoint("questie-npc-4-10"))==nil, "missing phase module fails closed")
QuestieLoader=oldLoader
phaseVisible=true
check(ns.ResolveQuestiePoint(ns.GetQuestiePoint("questie-npc-4-10"))~=nil, "replaced phase provider can recover")
check(rows[2][1]=="|cabcdef材料商|r" and rows[2][3][100][1][1]==20 and #rows[2][3][100]==6, "Questie-owned records remain untouched")
check(ns.ResolveQuestiePoint(nil)==nil and ns.GetQuestiePoint(nil)==nil, "invalid point identity fails safely")

-- A new provider is fully staged and only replaces the published list on success.
local oldProvider=LibQuestieDB
LibQuestieDB={Npc={GetAllIds=function() return {20,21} end,GetAll=function(id)
    if id==21 then error("provider loading error") end
    return {[1]="新条目",[3]={[100]={{10,20}}}}
end}}
ns.UpdateQuestieCatalog(2)
check(ns.GetQuestieCatalogStatus().status=="error" and ns.GetCatalogPoints()==snapshot, "provider error cannot publish partial catalogue")
check(not ns.GetQuestiePoint("questie-npc-20-10"), "half-built index remains private")
local errors=ns.GetQuestieCatalogStatus().error
check(type(errors)=="string" and errors:find("provider loading error",1,true), "error is recorded for diagnosis")
for _=1,9 do ns.UpdateQuestieCatalog(.5) end
check(ns.GetQuestieCatalogStatus().status=="error", "errors do not trigger an unthrottled retry loop")
LibQuestieDB=oldProvider
ns.UpdateQuestieCatalog(10)
check(ns.GetQuestieCatalogStatus().status=="ready", "original good provider recovers without rebuilding needlessly after temporary error")

-- Every OnUpdate has both a record-count cap and an optional profiling budget.
ns=loadCatalog()
local manyIDs, manyRows={},{}
for id=100,200 do
    manyIDs[#manyIDs+1]=id
    manyRows[id]={[1]="NPC "..id,[3]={[100]={{10,20}}},[5]="AH"}
end
install(manyIDs,manyRows)
ns.ClassifyQuestieNPC=function(raw, template)
    return {category="services",service="服务 "..raw.npcID,tags="服务标签"}
end
ns.UpdateQuestieCatalog(0)
check(calls==40 and ns.GetQuestieCatalogStatus().status=="loading", "at most forty NPCs per frame")
check(ns.GetCatalogPoints()==ns.Points and not ns.GetQuestiePoint("questie-npc-100-10"), "no partial results during loading")
ns.UpdateQuestieCatalog(.001)
check(calls==80, "next frame continues a bounded batch")
s=drain(ns)
check(calls==101 and s.count==101 and s.npcs==101, "incremental indexing reaches all IDs")
check(ns.GetQuestiePoint("questie-npc-100-10").category=="services" and ns.GetQuestiePoint("questie-npc-100-10").service=="服务 100", "caller service classification retained")
local prior=ns.GetQuestiePoint("questie-npc-100-10").id
LibQuestieDB={Npc={GetAllIds=function() return {101,100} end,GetAll=function(id) return manyRows[id] end}}
s=drain(ns)
check(s.status=="ready" and s.count==2 and ns.GetQuestiePoint("questie-npc-100-10").id==prior, "stable identity survives ID order and provider changes")
check(ns.GetQuestiePoint("questie-npc-200-10")==nil, "new complete index removes unavailable former IDs")

ns=loadCatalog()
install(manyIDs,manyRows)
local clock=0
debugprofilestop=function() clock=clock+1; return clock end
ns.UpdateQuestieCatalog(0)
check(calls==2 and ns.GetQuestieCatalogStatus().processed==2, "profiling budget limits a frame before record cap")
debugprofilestop=nil
check(drain(ns).status=="ready", "profiling clock is optional")

ns=loadCatalog()
install({}, {})
check(drain(ns).status=="ready" and ns.GetCatalogPoints()[1]==ns.Points[1], "empty valid upstream list retains authored points")
ns=loadCatalog()
install({1}, {[1]={[1]="模板目标",[3]={[200]={{10,20}}}}})
local templateSeen
ns.ClassifyQuestieNPC=function(raw, template)
    templateSeen=template
    return {category=template.category,service=template.service,tags=template.tags}
end
drain(ns)
check(templateSeen==ns.Points[1] and ns.GetQuestiePoint("questie-npc-1-20").service=="牧师训练师", "curated role template follows an NPC to additional maps")

ns=loadCatalog()
install({2}, {[2]={[1]="边界位置",[2]="服务",[3]={[100]={{0,100}}}}})
ns.DB={activeID="questie-npc-999-10", favorites={["questie-npc-999-10"]=true}}
local stopped=0
ns.Stop=function() stopped=stopped+1; ns.DB.activeID=nil end
ns.ClassifyQuestieNPC=function() return {category="npcs",service="其他 NPC",tags="",catalogSubcategory="npcs:other"} end
drain(ns)
local edge=ns.GetQuestiePoint("questie-npc-2-10")
check(edge and edge.x==0 and edge.y==1, "real map boundary is valid when it is not the unknown zero origin")
check(edge.catalogSubcategory=="npcs:other", "explicit classifier subcategory retained")
check(stopped==1 and not ns.DB.activeID and ns.DB.favorites["questie-npc-999-10"], "missing active runtime NPC stops only after complete indexing, favorite retained")

ns=loadCatalog()
install({2}, {[2]={[1]="暂隐目标",[3]={[100]={{10,20,7}}}}})
phaseVisible=false
ns.DB={activeID="questie-npc-2-10"}
drain(ns)
check(ns.DB.activeID=="questie-npc-2-10" and not ns.ResolveQuestiePoint(ns.GetQuestiePoint(ns.DB.activeID)), "existing hidden phase keeps saved identity for later visibility")

ns=loadCatalog()
install(manyIDs,manyRows)
ns.UpdateQuestieCatalog(0)
check(ns.GetQuestieCatalogStatus().status=="loading", "large provider begins staging")
Questie.API.isReady=false
ns.UpdateQuestieCatalog(.1)
check(calls==40 and ns.GetCatalogPoints()==ns.Points and ns.GetQuestieCatalogStatus().status=="waiting", "readiness loss abandons partial work without publishing")
Questie.API.isReady=true
LibQuestieDB={Npc={GetAllIds=function() return {999} end,GetAll=function() return {[1]="替代目标",[3]={[100]={{10,20}}}} end}}
drain(ns)
check(ns.GetQuestieCatalogStatus().count==1 and ns.GetQuestiePoint("questie-npc-999-10") and not ns.GetQuestiePoint("questie-npc-100-10"), "changed provider cannot publish former partially read IDs")

ns=loadCatalog()
install({2}, {[2]={[1]="可见目标",[3]={[100]={{10,20}}}}})
LibQuestieDB.Npc.GetAllIds=function() error("ID provider failed") end
check(drain(ns).status=="error" and ns.GetCatalogPoints()==ns.Points, "ID discovery errors preserve independent offline catalogue")

ns=loadCatalog()
install({2}, {[2]={[1]="可见目标",[3]={[100]={{10,20}}}}})
QuestieLoader={ImportModule=function() return nil end}
ns.UpdateQuestieCatalog(0)
check(calls==0 and ns.GetQuestieCatalogStatus().status=="waiting", "late ZoneDB module waits without empty successful build")
QuestieLoader={ImportModule=function(_,name) return name=="ZoneDB" and zones or nil end}
check(drain(ns).status=="ready", "late ZoneDB readiness recovers")

-- The map waypoint and active HUD must share the one spawn chosen at start.
ns=loadCatalog()
install({2}, {[2]={[1]="多处刷新目标",[3]={[100]={{10,20,7},{10,20,8},{80,90}}},[5]="AH"}})
phaseVisible=true
drain(ns)
local original=ns.GetQuestiePoint("questie-npc-2-10")
local selected=ns.ResolveQuestiePoint(original,{mapID=10,x=.1,y=.2})
local frozen=ns.FreezeQuestiePoint(selected)
check(frozen and frozen~=selected and #frozen.questieSpawns==2, "start freezes a new point with all phase variants at selected coordinate")
check(frozen.questieSpawns~=original.questieSpawns and #original.questieSpawns==3, "freezing does not edit search snapshot spawn list")
ns.GetPlayerPosition=function() return 10,.8,.9 end
check(ns.ResolveQuestiePoint(frozen).x==.1 and ns.ResolveQuestiePoint(frozen).y==.2, "walking near a different spawn cannot move frozen active destination")
check(ns.ResolveQuestiePoint(original).x==.8 and ns.ResolveQuestiePoint(original).y==.9, "independent directory search can still choose nearest spawn")
phaseVisible=false
check(ns.ResolveQuestiePoint(frozen)==nil and ns.FreezeQuestiePoint(selected)==nil, "invisible selected spawn does not switch active destination to another visible coordinate")
check(ns.ResolveQuestiePoint(original).x==.8, "hidden active spawn does not remove other visible search references")
check(ns.FreezeQuestiePoint({questie=true,mapID=10,x=.4,y=.4,questieSpawns=original.questieSpawns})==nil, "a coordinate absent from source cannot be frozen")
check(ns.FreezeQuestiePoint(nil)==nil and ns.FreezeQuestiePoint({mapID=10,x=.1,y=.2})==nil, "freezing rejects absent and non-Questie points")
phaseVisible=true
check(ns.ResolveQuestiePoint(frozen).x==.1, "restored phase resumes original frozen coordinate")
local normalVisibility=phase.IsSpawnVisible
phase.IsSpawnVisible=function(value) return value==8 end
check(ns.ResolveQuestiePoint(frozen).x==.1, "alternate visible phase at the selected coordinate remains usable")
phase.IsSpawnVisible=normalVisibility

-- A late-created phase module may appear on the same QuestieLoader object.
local latePhase
QuestieLoader={ImportModule=function(_,name) return name=="ZoneDB" and zones or name=="Phasing" and latePhase or nil end}
check(ns.ResolveQuestiePoint(frozen)==nil, "late phase module unavailable initially fails closed")
latePhase=phase
check(ns.ResolveQuestiePoint(frozen).x==.1, "same loader late phase module is rechecked after nil result")
print("Navigator Questie catalogue: "..checks.." checks passed (simulated provider, not in-game tests)")
