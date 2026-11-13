-- Complete Navigator modules with simulated client/Questie APIs. These checks
-- exercise shared state and ownership across modules, not a live WoW session.
local root="_forever_/Interface/AddOns/MyForeverNavigator/"
local checks=0
local function check(value, message) checks=checks+1; assert(value, message) end
local function near(actual, expected, message)
    check(type(actual)=="number" and math.abs(actual-expected)<1e-8, message)
end
local function vector(x,y) return {x=x,y=y,GetXY=function(self) return self.x,self.y end} end
local function waypoint(x,y) return {uiMapID=10,position=vector(x,y)} end
local px,py,phaseVisible=.1,.1,true
local nativeWaypoint,tracking,trackedQuest=nil,nil,0
local untrackCalls,waypointCalls=0,0
local maps={
    [1]={name="世界",mapType=1,parentMapID=0},
    [100]={name="东部王国",mapType=2,parentMapID=1},
    [10]={name="测试区域",mapType=3,parentMapID=100},
}
CreateFrame,WorldMapFrame,UIParent,debugprofilestop=nil,nil,nil,nil
CreateVector2D=vector
Enum={UIMapType={Continent=2,Zone=3}}
C_Map={
    GetBestMapForUnit=function() return 10 end,
    GetMapInfo=function(id) return maps[id] end,
    GetPlayerMapPosition=function() return vector(px,py) end,
    GetMapWorldSize=function() return 1000,1000 end,
    GetWorldPosFromMapPos=function(_,point) return 0,vector(point.x*1000,point.y*1000) end,
    CanSetUserWaypointOnMap=function() return true end,
    SetUserWaypoint=function(value) nativeWaypoint=value;waypointCalls=waypointCalls+1;return true end,
    GetUserWaypoint=function() return nativeWaypoint end,
}
UiMapPoint={CreateFromCoordinates=function(id,x,y) return {uiMapID=id,position=vector(x,y)} end}
C_SuperTrack={
    SetSuperTrackedUserWaypoint=function(value)
        if value then tracking="user" else untrackCalls=untrackCalls+1; tracking=nil end
    end,
    IsSuperTrackingUserWaypoint=function() return tracking=="user" end,
    SetSuperTrackedQuestID=function(id) trackedQuest=id;tracking=id>0 and "quest" or nil end,
    GetSuperTrackedQuestID=function() return trackedQuest end,
    IsSuperTrackingQuest=function() return tracking=="quest" end,
}
UnitFactionGroup=function() return "Alliance" end
GetPlayerFacing=function() return 0 end
IsInInstance=function() return false end
InCombatLockdown=function() return false end
GetTime=function() return 0 end
local records={
    [200]={n=7,[1]="多点商人",[2]="旅途补给商",[3]={[500]={{20,20,7},{20,20,8},{80,80}}},[4]=4,[5]="AH"},
    [201]={n=7,[1]="尖牙狼",[2]="夜行捕食者",[3]={[500]={{35,35}}}},
    [202]={n=7,[1]="职业导师",[2]="法师训练师",[3]={[500]={{90,10}}},[4]=16,[5]="A"},
    [203]={n=7,[1]="炼金导师",[2]="炼金术训练师",[3]={[500]={{65,65}}},[4]=16,[5]="A"},
    [204]={n=7,[1]="部落商人",[2]="杂货商",[3]={[500]={{10,90}}},[4]=4,[5]="H"},
}
LibQuestieDB={Enum={npcFlags={VENDOR=4,TRAINER=16}},Npc={
    GetAllIds=function() return {200,201,202,203,204} end,
    GetAll=function(id) return records[id] end,
    Get=function(id,field)
        local row=records[id]
        if not row then return nil end
        return field=="name" and row[1] or field=="spawns" and row[3] or nil
    end,
}}
local zones={GetUiMapIdByAreaId=function(_,id) return id==500 and 10 or nil end}
local phase={IsSpawnVisible=function(id) return (id==7 or id==8) and phaseVisible end}
QuestieLoader={ImportModule=function(_,name) return name=="ZoneDB" and zones or name=="Phasing" and phase or nil end}
Questie={API={isReady=false}}
local function loadNavigator(saved)
    local ns={}
    for _,name in ipairs({"Core","Classification","Provider","QuestieCatalog","Navigation"}) do
        assert(loadfile(root..name..".lua"))("MyForeverNavigator",ns)
    end
    ns.Points={{id="curated-999",npcID=999,name="原有接洽点",category="special",service="原有用途",tags="",faction="Neutral",mapID=10,x=.95,y=.95,zone="测试区域"}}
    ns.RefreshUI=function() end
    ns.RefreshHUD=function() ns.lastHUD=ns.GetNavigation() end
    ns.Initialize(saved)
    return ns
end
local function build(ns)
    Questie.API.isReady=true
    for _=1,10 do
        ns.UpdateQuestieCatalog(1)
        if ns.GetQuestieCatalogStatus().status=="ready" then return end
    end
    error("Questie catalogue failed to become ready")
end
local function find(ns,query,options)
    local found=ns.Search(query,options)
    check(#found==1,"fixture query must identify one destination: "..query)
    return found[1]
end
local id="questie-npc-200-10"
local ns=loadNavigator({activeID=id,favorites={[id]=true}})
check(ns.DB.activeID==id and ns.DB.favorites[id] and not ns.GetPoint(id), "reload retains saved Questie identity while optional catalogue is pending")
ns.UpdateQuestieCatalog(0)
check(ns.GetQuestieCatalogStatus().status=="waiting" and ns.DB.activeID==id, "Questie initialization delay does not discard active or favorite ID")
build(ns)
check(ns.GetPoint(id) and ns.GetPoint(id).name=="多点商人", "stable saved identity resolves after catalogue becomes ready")
check(find(ns,"多点商人",{category="favorites"}).id==id, "saved Questie favorite returns through normal favorites search")

local all=ns.Search("",{includeCustom=false})
check(all[1].id==id,"default search sorts actual nearest reference first")
check(find(ns,"夜行捕食者").faction=="Hostile", "hostile NPC title is searchable under default own-faction filter")
check(find(ns,"职业导师",{category="trainers",subcategory="trainers:mage"}).id=="questie-npc-202-10", "localized class title and flag feed existing class-trainer category")
check(#ns.Search("炼金导师",{category="trainers"})==0 and find(ns,"炼金导师",{category="services",subcategory="services:trainer"}), "profession trainers remain separate from class trainers")
check(#ns.Search("部落商人")==0 and find(ns,"部落商人",{faction="all"}), "own-faction filter excludes opposing friendly merchant without hiding hostile creatures")

local selected=find(ns,"多点商人")
near(selected.x,.2,"search picks nearer first spawn")
check(ns.Start(selected) and ns.QuestieDestination and ns.QuestieDestination~=selected,"start freezes chosen search reference in session memory")
check(tracking=="user" and nativeWaypoint.uiMapID==10,"chosen destination enables normal native user waypoint tracking")
near(nativeWaypoint.position.x,.2,"native waypoint uses chosen search coordinate")
near(ns.lastHUD.point.x,nativeWaypoint.position.x,"initial HUD and native waypoint point to same spawn")
px,py=.79,.79
near(find(ns,"多点商人").x,.8,"later searches can choose a newly nearer spawn")
local nav=ns.GetNavigation()
near(nav.point.x,.2,"active HUD keeps original chosen spawn after player walks")
near(ns.GetPoint(id).x,nativeWaypoint.position.x,"normal point lookup remains aligned with native waypoint")

local before=untrackCalls
phaseVisible=false
check(not ns.GetPoint(id),"hidden active coordinate has no fallback to another visible spawn")
nav=ns.GetNavigation()
check(nav.mode=="unavailable" and not nav.point and ns.DB.activeID==id,"hidden phase pauses active HUD while retaining stable identity")
check(untrackCalls==before+1 and tracking==nil,"hidden phase releases only still-owned native supertracking")
near(nativeWaypoint.position.x,.2,"pausing does not delete the shared native map pin")
phaseVisible=true
nav=ns.GetNavigation()
near(nav.point.x,.2,"visible phase resumes the same frozen coordinate")
check(nav.point.id==id and ns.QuestieDestination,"phase restoration retains frozen destination and identity")

-- A player/another addon's shared pin must survive even if the next refresh
-- discovers that our selected phase disappeared before an ownership event.
px,py=.1,.1
check(ns.Start(find(ns,"多点商人")),"restart confirmed phase destination")
local externalPin=waypoint(.45,.56)
nativeWaypoint,tracking=externalPin,"user"
before=untrackCalls
phaseVisible=false
ns.GetNavigation()
check(untrackCalls==before and tracking=="user" and nativeWaypoint==externalPin,"hidden phase preserves another owner's changed waypoint and tracking")

phaseVisible=true
check(ns.Start(find(ns,"多点商人")),"restart before another feature chooses quest tracking")
tracking,trackedQuest="quest",456
before=untrackCalls
phaseVisible=false
ns.GetNavigation()
check(untrackCalls==before and tracking=="quest" and trackedQuest==456,"hidden phase cannot revoke a later externally selected quest track")
ns.Stop()
check(ns.QuestieDestination==nil and ns.DB.activeID==nil and trackedQuest==456,"stop clears local frozen memory without touching external quest selection")

phaseVisible=true
check(ns.Start(find(ns,"多点商人")),"frozen navigation can be started again after stop")
ns.Initialize({favorites={[id]=true}})
check(ns.QuestieDestination==nil and ns.DB.activeID==nil and ns.DB.favorites[id],"initialize clears old session destination while preserving saved favorite IDs")

-- A full addon reload means new module-local indexes too, not merely calling
-- NormalizeDB against a catalogue that was already built in the old session.
Questie.API.isReady=false
local restored=loadNavigator(ns.NormalizeDB({activeID=id,favorites=ns.DB.favorites}))
check(restored.QuestieDestination==nil and restored.DB.activeID==id and restored.DB.favorites[id] and not restored.GetPoint(id),"full reload persists IDs only and waits for its new catalogue")
build(restored)
check(restored.GetPoint(id) and restored.GetPoint(id).id==id and find(restored,"多点商人",{category="favorites"}),"rebuilt catalogue restores both active ID and favorite lookup")
check(waypointCalls>0 and records[200][3][500][1][1]==20 and #records[200][3][500]==3,"complete navigation flow leaves Questie-owned spawn records unchanged")
print("Navigator Questie integration: "..checks.." behavioral checks passed (simulated client, not in-game tests)")
