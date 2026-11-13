local NS, checks = {}, 0
local function eq(actual, expected, message)
    checks=checks+1
    assert(actual==expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function contains(text, value, message)
    checks=checks+1;assert(text:find(value,1,true),message)
end
local root="_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root.."Core.lua"))("MyForeverNavigator",NS)
NS.Initialize(nil)
local reference, rows, ready, complete, onQuest, native = nil, {}, false, false, true, nil
local now, requested, contextCalls, started, shown, stopped=10,0,0,nil,nil,0
GetTime=function()return now end
C_Map={GetBestMapForUnit=function()return 1453 end,GetMapInfo=function(id)return {name="区域"..id}end}
C_QuestLog={
    GetTitleForQuestID=function()return "检查任务"end,
    IsOnQuest=function()return onQuest end,
    ReadyForTurnIn=function()return ready end,
    IsComplete=function()return complete end,
    GetQuestObjectives=function()return rows end,
    GetNextWaypoint=function()if native then return native.mapID,native.x,native.y end end,
    RequestLoadQuestByID=function()requested=requested+1 end,
}
NS.GetQuestReference=function()return reference end
NS.GetLocationContext=function()contextCalls=contextCalls+1;return {marker="shared"}end
NS.MeasurePoint=function(point,context)
    eq(context.marker,"shared","candidate distances share context")
    return point.mapID==1453 and point.x*1000 or nil
end
NS.StartTransient=function(point)started=point;NS.DB.activeID=point.id;return true end
NS.ShowQuestTargets=function(id,title,targets,message)shown={id=id,title=title,targets=targets,message=message}end
NS.HideQuestTargets=function()shown=nil end
NS.RefreshHUD=function()end;NS.RefreshUI=function()end
NS.Stop=function()stopped=stopped+1;NS.DB.activeID=nil end
assert(loadfile(root.."QuestNavigation.lua"))("MyForeverNavigator",NS)
local function point(x,map,id,name)return {mapID=map or 1453,x=x,y=.5,sourceID=id,sourceName=name,source="reference"}end
local function ref(kind,id,name,points)return {kind=kind,id=id,name=name,english=name,points=points or {point(.4)}}end
local function build()return NS.BuildQuestNavigation(100)end
local state=NS.BuildQuestNavigation(nil)
eq(state.invalid,true,"reject missing quest ID")
eq(NS.BuildQuestNavigation(-2).invalid,true,"reject negative quest ID")
eq(NS.BuildQuestNavigation(1.5).invalid,true,"reject fractional quest ID")
onQuest=false;eq(build().invalid,true,"abandoned quest cannot navigate")
onQuest=true;state=build()
eq(#state.targets,0,"no coordinates never invent player position")
contains(state.message,"没有可靠", "missing location explained")
eq(requested,1,"request missing quest data")
build();eq(requested,1,"throttle repeated data requests")
now=14;build();eq(requested,2,"retry after bounded delay")

native=point(.6);state=build()
eq(#state.targets,1,"native quest waypoint")
eq(state.targets[1].nativeQuestTracking,true,"native point uses quest ownership")
eq(state.targets[1].kind,"area","native quest point is a general destination")
eq(NS.OpenQuestNavigation(100),true,"single reliable destination starts immediately")
eq(started.questID,100,"active point has quest association")
eq(#NS.DB.custom,0,"quest navigation does not consume personal places")
native=point(1.1);eq(#build().targets,0,"reject out-of-range native point")
native={mapID=1453,x=0,y=0};eq(#build().targets,0,"reject native zero sentinel")
native={mapID=1453,x=0/0,y=.2};eq(#build().targets,0,"reject native NaN")
native=nil
C_QuestLog.GetNextWaypoint=function()error("unavailable")end
eq(#build().targets,0,"native API exceptions fall back safely")
C_QuestLog.GetNextWaypoint=function()end
GetQuestUiMapID=function()return 1426 end
C_QuestLog.GetNextWaypointForMap=function(_,map)if map==1426 then return .2,.3 end end
state=build();eq(state.targets[1].mapID,1426,"quest map fallback can differ from player map")
C_QuestLog.GetNextWaypointForMap=nil
C_QuestLog.GetQuestsOnMap=function(map)return {{questID=99,mapID=map,x=.1,y=.1},{questID=100,mapID=map,x=.3,y=.4,isQuestStart=true}}end
eq(#build().targets,0,"ignore another quest and quest-start POI")
C_QuestLog.GetQuestsOnMap=function(map)return {{questID=100,mapID=map,x=.3,y=.4}}end
eq(build().targets[1].x,.3,"matching current quest POI")
C_QuestLog.GetQuestsOnMap=nil;GetQuestUiMapID=nil
C_TaskQuest={IsActive=function()return false end,GetQuestLocation=function()return .2,.3 end}
eq(#build().targets,0,"task location ignored for non-task quests")
C_TaskQuest.IsActive=function()return true end
eq(build().targets[1].x,.2,"active task location fallback")
C_TaskQuest=nil

reference={objectives={ref("npc",1,"野猪"),ref("npc",2,"被感染的野猪"),ref("item",3,"坚硬的肉",{
    point(.8,1453,10,"野狼"),point(.2,1453,10,"野狼"),point(.5,1426,10,"野狼"),point(.1,1453,11,"箱子"),
})},turnin={ref("turnin",90,"交付联系人")}}
rows={{text="被感染的野猪：4/4",type="monster",finished=true},{text="坚硬的肉：0/3",type="item",finished=false}}
state=build()
local ids={};for _,target in ipairs(state.targets)do ids[target.id]=target end
local foundItem,foundLong,foundShort=0,false,false
for _,target in ipairs(state.targets)do
    if target.kind=="item"then foundItem=foundItem+1;contains(target.name,"坚硬的肉", "item named distinctly from source");contains(target.note,"不保证", "item drops not promised")end
    if target.name=="被感染的野猪"then foundLong=true end
    if target.name=="野猪"then foundShort=true;eq(target.progressUncertain,true,"shorter name does not inherit longer-name progress")end
end
eq(foundItem,3,"nearest actual sample per entity and zone; distinct sources retained")
eq(foundLong,false,"completed goal removed")
eq(foundShort,true,"unmatched goal remains explicitly selectable")
eq(state.hasUncertain,true,"uncertain progress must be disclosed")
eq(NS.OpenQuestNavigation(100),false,"multiple destinations show picker")
eq(shown.id,100,"picker belongs to clicked quest")
local itemTarget
for _,target in ipairs(state.targets)do if target.kind=="item"and target.mapID==1453 and target.name:find("野狼",1,true)then itemTarget=target end end
eq(itemTarget.x,.2,"select closest verified sample rather than averaging spawn positions")
eq(itemTarget.nativeQuestTracking,nil,"specific offline target uses point tracking")
eq(NS.SelectQuestTarget(100,itemTarget),true,"valid picker selection starts")
eq(started.id,itemTarget.id,"selected candidate identity retained")
eq(NS.SelectQuestTarget(101,itemTarget),false,"reject cross-quest stale selection")
rows[2].finished=true
eq(NS.SelectQuestTarget(100,itemTarget),false,"do not start objective completed after popup opened")
contains(shown.message,"已变化", "stale picker refresh explained")

ready=true;state=build()
eq(#state.targets,1,"completed quest only offers delivery location")
eq(state.targets[1].kind,"turnin","turn-in destination distinct from objective")
eq(state.targets[1].name,"交付联系人","delivery NPC name")
eq(state.targets[1].progressUncertain,false,"confirmed completion needs no objective text match")
ready=false;complete=true
eq(build().ready,true,"active completion API can establish delivery phase")
complete=false
IsQuestFlaggedCompleted=function()return true end
eq(build().ready,false,"completed history cannot mark current quest ready")
IsQuestFlaggedCompleted=nil

reference={objectives={ref("item",3,"坚硬的肉")},turnin={}}
rows={{text="坚硬的肉：3/3",type="item",finished=false,numFulfilled=3,numRequired=3}}
eq(#build().targets,0,"fulfilled quantity marks goal complete")
rows={{text="坚硬的肉：0/3",type="monster",finished=false}}
eq(build().targets[1].progressUncertain,true,"different objective type is not matched by name alone")
rows={};started=nil
eq(NS.OpenQuestNavigation(100),false,"single unverified-progress reference requires explicit choice")
eq(started,nil,"uncertain reference never auto-starts")
eq(#shown.targets,1,"uncertain point still available with explanation")

C_QuestLog.GetLogIndexForQuestID=function()return 5 end
GetNumQuestLeaderBoards=function(index)eq(index,5,"legacy log index passed");return 1 end
GetQuestLogLeaderBoard=function()return "坚硬的肉：0/3","item",false end
eq(build().targets[1].progressUncertain,false,"legacy objectives can establish progress")
GetNumQuestLeaderBoards=nil;GetQuestLogLeaderBoard=nil;C_QuestLog.GetLogIndexForQuestID=nil

local savedLog=C_QuestLog;C_QuestLog=nil
eq(#build().targets,1,"offline references survive missing namespace")
C_QuestLog=savedLog
local secret={}
issecretvalue=function(value)return value==secret end
C_QuestLog.IsOnQuest=function()return secret end
eq(build().invalid,nil,"secret status is not treated as abandoned")
issecretvalue=nil;C_QuestLog.IsOnQuest=function()return onQuest end
NS.GetPoint=function(id)if id then return {questID=100}end end
NS.DB.activeID="quest:100:test";onQuest=false
NS.RefreshQuestSession();eq(stopped,1,"abandoned or handed-in active quest stops temporary navigation")
NS.DB.activeID="npc:1";NS.GetPoint=function()return {npcID=1}end
NS.RefreshQuestSession();eq(stopped,1,"quest updates never stop unrelated NPC navigation")

-- The actual shipped offline reference must resolve with live-style progress,
-- not only synthetic fixtures or table-order assumptions.
assert(loadfile(root.."QuestData.lua"))("MyForeverNavigator",NS)
onQuest=true;ready=false;complete=false
C_QuestLog.GetTitleForQuestID=function()end
rows={{text="探索法戈第矿洞：0/1",type="event",finished=false}}
state=NS.BuildQuestNavigation(62)
eq(state.title,"法戈第矿洞","real quest title fallback")
eq(#state.targets,1,"real exploration destination")
eq(state.targets[1].kind,"area","location quest is not NPC or item")
eq(state.targets[1].progressUncertain,false,"exploration name matches actual progress wording")
eq(state.targets[1].mapID,1429,"actual exploration map")
rows={{text="菲利克斯的盒子：1/1",type="item",finished=true},
    {text="菲利克斯的箱子：0/1",type="item",finished=false},
    {text="菲利克斯的螺钉桶：0/1",type="item",finished=false}}
state=NS.BuildQuestNavigation(3361)
eq(#state.targets,2,"real three-item quest skips only completed item")
for _,target in ipairs(state.targets)do eq(target.kind,"item","actual container item source");eq(target.progressUncertain,false,"actual item progress matched")end
ready=true;state=NS.BuildQuestNavigation(3361)
eq(#state.targets,1,"real completed quest delivery")
eq(state.targets[1].name,"菲利克斯","real delivery NPC")
eq(state.targets[1].kind,"turnin","delivery phase after completion")
ready=false;rows={{text="霜鬃巨魔幼崽：0/14",type="monster",finished=false}}
state=NS.BuildQuestNavigation(182)
eq(#state.targets,1,"real kill quest selects an actual nearby sample")
eq(state.targets[1].name,"霜鬃巨魔幼崽","actual kill target NPC")
eq(state.targets[1].mapID,1426,"actual kill target zone")
eq(state.targets[1].progressUncertain,false,"actual kill goal matched")
local potion=NS.GetQuestReference(715)
local potionGoal
for _,goal in ipairs(potion.objectives)do if goal.kind=="item"and goal.id==929 then potionGoal=goal end end
assert(potionGoal,"reference includes shared numeric source IDs")
rows={{text=potionGoal.name.."：0/1",type="item",finished=false}}
state=NS.BuildQuestNavigation(715)
local container,drop
for _,target in ipairs(state.targets)do
    if target.id:find("1439:container:3660",1,true) then container=target end
    if target.id:find("1439:drop:3660",1,true) then drop=target end
end
eq(container~=nil,true,"real item container namespace retained")
eq(drop~=nil,true,"real item drop namespace retained with same source ID")
eq(container.id~=drop.id,true,"NPC and object source IDs cannot collide")
rows={{text="霜鬃巨魔幼崽：0/14",type="monster",finished=false}}
state=NS.BuildQuestNavigation(182)
local active=state.targets[1]
NS.GetPoint=function()return active end;NS.DB.activeID=active.id
local before=stopped
NS.RefreshQuestSession();eq(stopped,before,"unfinished active goal stays navigable")
rows[1].finished=true
NS.RefreshQuestSession();eq(stopped,before+1,"completed active objective stops old direction")
rows[1].finished=false;ready=false
active=NS.BuildQuestNavigation(182).targets[1];NS.DB.activeID=active.id
ready=true;NS.RefreshQuestSession()
eq(stopped,before+2,"delivery phase stops previous objective")
ready=false;reference=nil
C_QuestLog.GetNextWaypoint=function()return 1453,.2,.3 end
active=NS.BuildQuestNavigation(999999).targets[1];NS.DB.activeID=active.id
C_QuestLog.GetNextWaypoint=function()return 1426,.4,.6 end
NS.RefreshQuestSession()
eq(active.mapID,1426,"native next-stop HUD follows latest client coordinates")
eq(active.x,.4,"native next-stop coordinate updated without Start")
eq(stopped,before+2,"same-phase native update does not stop or reclaim tracking")
print("Navigator quest navigation: "..checks.." checks passed (simulated)")
