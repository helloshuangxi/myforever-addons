-- Lua 5.1 behavioral contracts; simulated APIs, not live game validation.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, label)
    checks = checks + 1
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.00001, label .. ": got " .. tostring(actual))
end
local function contains(actual, expected, label)
    checks = checks + 1
    assert(type(actual) == "string" and actual:find(expected, 1, true), label)
end
local NS = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/Core.lua"))("MyForeverNavigator", NS)
local function vector(x, y) return {x=x, y=y, GetXY=function(self) return self.x, self.y end} end
CreateVector2D = vector
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
local maps = {
    [1]={name="世界",mapType=1,parentMapID=0},
    [100]={name="东部王国",mapType=2,parentMapID=1},
    [200]={name="卡利姆多",mapType=2,parentMapID=1},
    [1426]={name="丹莫罗",mapType=3,parentMapID=100},
    [1455]={name="铁炉堡",mapType=3,parentMapID=100},
    [1454]={name="奥格瑞玛",mapType=3,parentMapID=200},
    [999]={name="副本",mapType=4,parentMapID=1426},
}
local currentMap, px, py, facing, instance, faction, combat = 1426, .5, .5, 0, false, "Alliance", false
local waypointCalls, cleared, supertracked, nativeOffCalls = 0, 0, 0, 0
local nativeWaypoint = "user-owned"
local nativeTracking = false
local function nativeWorld(mapID, position)
    if mapID == 1426 then return 0, vector(position.y * 500, -position.x * 1000) end
    if mapID == 1455 then return 0, vector(position.y * 500 + 1000, -position.x * 1000) end
    if mapID == 1454 then return 1, vector(position.y * 500, -position.x * 1000) end
    if mapID == 999 then return 30, vector(position.y * 500, -position.x * 1000) end
end
local rectangles = {
    [1426]={.2,.6,.1,.5}, [1455]={.3,.4,.4,.5},
    [100]={.1,.4,.2,.8}, [200]={.5,.9,.1,.8},
}
C_Map = {
    GetBestMapForUnit=function() return currentMap end,
    GetMapInfo=function(id) return maps[id] end,
    GetPlayerMapPosition=function() return vector(px,py) end,
    GetMapWorldSize=function() return 1000,500 end,
    GetWorldPosFromMapPos=nativeWorld,
    GetMapRectOnMap=function(id,parent)
        assert(parent == maps[id].parentMapID, "projection follows actual parent")
        if rectangles[id] then return unpack(rectangles[id]) end
    end,
    CanSetUserWaypointOnMap=function() return true end,
    SetUserWaypoint=function(p) waypointCalls=waypointCalls+1; nativeWaypoint=p; return true end,
    GetUserWaypoint=function() return nativeWaypoint end,
    ClearUserWaypoint=function() cleared=cleared+1; nativeWaypoint=nil end,
}
UnitFactionGroup=function() return faction end
IsInInstance=function() return instance end
GetPlayerFacing=function() return facing end
InCombatLockdown=function() return combat end
UiMapPoint={CreateFromCoordinates=function(id,x,y) return {uiMapID=id,position=vector(x,y)} end}
C_SuperTrack={SetSuperTrackedUserWaypoint=function(value)
    if value then supertracked=supertracked+1 else nativeOffCalls=nativeOffCalls+1 end
    nativeTracking=value
end, IsSuperTrackingUserWaypoint=function() return nativeTracking end}
NS.Points={
    {id="east",name="东边NPC",mapID=1426,x=.6,y=.5,zone="丹莫罗",faction="Neutral"},
    {id="north",name="北边NPC",mapID=1426,x=.5,y=.3,zone="丹莫罗",faction="Neutral"},
    {id="south",name="南边NPC",mapID=1426,x=.5,y=.7,zone="丹莫罗",faction="Neutral"},
    {id="west",name="西边NPC",mapID=1426,x=.4,y=.5,zone="丹莫罗",faction="Neutral"},
    {id="near",name="附近NPC",mapID=1426,x=.52,y=.5,zone="丹莫罗",faction="Neutral"},
    {id="city",name="城内NPC",mapID=1455,x=.5,y=.5,zone="铁炉堡",faction="Neutral"},
    {id="cross",name="跨大陆NPC",mapID=1454,x=.5,y=.5,zone="奥格瑞玛",faction="Neutral"},
    {id="dungeon",name="副本NPC",mapID=999,x=.5,y=.5,zone="副本",faction="Neutral"},
}
NS.Initialize({})
local hudRefresh, uiRefresh = 0, 0
NS.RefreshHUD=function() hudRefresh=hudRefresh+1 end
NS.RefreshUI=function() uiRefresh=uiRefresh+1 end

local methods = {}
local function frame(name,parent,width,height)
    return setmetatable({name=name,parent=parent,width=width or 0,height=height or 0,shown=true,scale=1}, {__index=methods})
end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:Hide() self.shown=false end
function methods:Show() self.shown=true end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetParent(value) self.parent=value end
function methods:SetScale(value) self.scale=value end
function methods:SetPoint(...) self.point={...} end
function methods:ClearAllPoints() self.point=nil end
function methods:GetFrameLevel() return 10 end
function methods:SetText(value) self.text=value end
function methods:CreateTexture() return frame(nil,self) end
function methods:CreateFontString() return frame(nil,self) end
function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function methods:SetScript(event,fn) self.scripts=self.scripts or {};self.scripts[event]=fn end
for _,name in ipairs({"EnableMouse","SetAllPoints","SetTexture","SetTexCoord","SetTextColor","SetFrameLevel"}) do methods[name]=function() end end
CreateFrame=function(_,name,parent) return frame(name,parent) end
UIParent=frame("UIParent")
local canvas=frame("canvas",nil,1000,600)
WorldMapFrame=frame("WorldMapFrame",UIParent)
WorldMapFrame.mapID=1426
WorldMapFrame.canvasScale=1
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:SetMapID(id) self.mapID=id end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetCanvasScale() return self.canvasScale end
OpenWorldMap=function(id) WorldMapFrame:Show(); WorldMapFrame.mapID=id end
assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/Navigation.lua"))("MyForeverNavigator",NS)

eq(NS.GetNavigation().point,nil,"no destination")
eq(NS.Start("missing"),false,"unknown destination")
eq(NS.Start(NS.Points[1]),true,"start accepts catalog record")
eq(NS.DB.activeID,"east","active id persisted")
eq(waypointCalls,1,"start sets native waypoint without opening map")
eq(nativeWaypoint.uiMapID,1426,"native waypoint targets destination map")
eq(nativeTracking,true,"start enables native supertracking")
eq(NS.GetNativeTrackingStatus(),"active","native status is confirmed by client getters")
eq(hudRefresh,1,"start refreshes HUD")
eq(uiRefresh,1,"start refreshes directory")
local id,x,y=NS.GetPlayerPosition()
eq(id,1426,"player tuple map")
near(x,.5,"player tuple x")
near(y,.5,"player tuple y")
local nav=NS.GetNavigation()
eq(nav.mode,"direction","same map direction")
near(nav.distance,91.44,"yards converted to metres")
near(nav.angle,-math.pi/2,"world axis swap still points east")
contains(nav.detail,"直线","route limitation is visible")
contains(nav.detail,"丹莫罗","destination zone included")
NS.Start("north"); near(NS.GetNavigation().angle,0,"north arrow")
NS.Start("south"); near(math.cos(NS.GetNavigation().angle),-1,"south arrow")
NS.Start("west"); near(NS.GetNavigation().angle,math.pi/2,"west arrow")
NS.Start("east"); facing=math.pi*1.5
near(math.cos(NS.GetNavigation().angle),1,"facing east points forward")
facing=math.pi/2
near(math.cos(NS.GetNavigation().angle),-1,"facing west points behind")
facing=nil
nav=NS.GetNavigation()
eq(nav.angle,nil,"no facing never keeps stale arrow")
eq(nav.mode,"unavailable","missing facing fallback")
near(nav.distance,91.44,"distance survives missing facing")
contains(nav.detail,"地图东侧","absolute compass hint without facing")
facing=0
NS.Start("near")
eq(NS.GetNavigation().mode,"arrived","arrival within thirty yards")
eq(NS.GetNavigation().angle,nil,"arrival hides arrow")
eq(NS.DB.activeID,"near","arrival does not silently stop")
NS.Start("city")
nav=NS.GetNavigation()
eq(nav.mode,"direction","cross-zone same world direction")
near(nav.distance,914.4,"cross-zone native world distance")
near(math.cos(nav.angle),-1,"city south in swapped world basis")
NS.Start("cross")
nav=NS.GetNavigation()
eq(nav.mode,"cross","different continent requires transport")
eq(nav.distance,nil,"no cross-continent imaginary distance")
eq(nav.angle,nil,"no cross-continent arrow")
contains(nav.detail,"联盟码头","Alliance transport hint avoids unverified route")
faction="Horde"
contains(NS.GetNavigation().detail,"飞艇","Horde transport hint")
faction=nil
contains(NS.GetNavigation().detail,"目标大陆","unknown faction general transport hint")
faction="Alliance"
NS.Start("dungeon")
eq(NS.GetNavigation().mode,"cross","different world frame not compared")
NS.Start("east"); instance=true
eq(NS.GetNavigation().angle,nil,"instance prevents world direction")
contains(NS.GetNavigation().status,"副本内","instance status")
instance=false
C_Map.GetWorldPosFromMapPos=nil
nav=NS.GetNavigation()
near(nav.distance,91.44,"same zone size fallback")
near(nav.angle,-math.pi/2,"same zone size fallback angle")
NS.Start("city")
eq(NS.GetNavigation().angle,nil,"cross-zone missing transform no angle")
eq(NS.GetNavigation().distance,nil,"cross-zone missing transform no fabricated distance")
NS.Start("east")
C_Map.GetMapWorldSize=function() return 0/0,math.huge end
eq(NS.GetNavigation().distance,nil,"bad map size rejected")
C_Map.GetMapWorldSize=function() return 1000,500 end
C_Map.GetWorldPosFromMapPos=function(id,p)
    if p.x==.6 and p.y==.5 then return nativeWorld(id,p) end
    if p.x==.5 and p.y==.5 then return nativeWorld(id,p) end
    return nil
end
eq(NS.GetNavigation().angle,nil,"partial basis no guessed world bearing")
near(NS.GetNavigation().distance,91.44,"distance does not require orientation basis")
C_Map.GetWorldPosFromMapPos=nativeWorld
px=0/0
eq(NS.GetPlayerPosition(),nil,"NaN player position rejected")
eq(NS.GetNavigation().distance,nil,"unavailable position clears old distance")
px={secret=true}
eq(NS.GetPlayerPosition(),nil,"secret coordinate rejected")
px=.5
C_Map.GetBestMapForUnit=function() error("API unavailable") end
eq(NS.GetNavigation().angle,nil,"failing native API degrades safely")
C_Map.GetBestMapForUnit=function() return currentMap end

WorldMapFrame.mapID=1426
eq(NS.UpdateMapPin(),true,"selected target map pin")
near(NS.MapPin.point[4],600,"target pin x")
near(NS.MapPin.point[5],-300,"target pin y")
WorldMapFrame.canvasScale=2
NS.UpdateMapPin()
near(NS.MapPin.scale,.5,"pin counter-scales with map zoom")
near(NS.MapPin.point[4],1200,"pin coordinate accounts for own scale")
WorldMapFrame.canvasScale=1
WorldMapFrame.mapID=100
eq(NS.UpdateMapPin(),true,"continent projection")
near(NS.MapPin.point[4],440,"continent x from ordered rectangle tuple")
near(NS.MapPin.point[5],-180,"continent y from rectangle")
WorldMapFrame.mapID=1
eq(NS.UpdateMapPin(),true,"world projection through ancestor chain")
near(NS.MapPin.point[4],232,"world projected x")
near(NS.MapPin.point[5],-228,"world projected y")
WorldMapFrame.mapID=1455
eq(NS.UpdateMapPin(),false,"unrelated map hides target")
eq(NS.MapPin:IsShown(),false,"unrelated map no stale pin")
WorldMapFrame.mapID=1426
WorldMapFrame:Hide()
eq(NS.UpdateMapPin(),false,"hidden world map no pin")
WorldMapFrame:Show()
UIParent:Hide()
eq(NS.UpdateMapPin(),false,"hidden map parent no pin")
UIParent:Show()
local originalRectangle=C_Map.GetMapRectOnMap
C_Map.GetMapRectOnMap=function() return 0,0,0,0 end
WorldMapFrame.mapID=100
eq(NS.UpdateMapPin(),false,"degenerate projection hidden")
C_Map.GetMapRectOnMap=function() error("no projection") end
eq(NS.UpdateMapPin(),false,"projection error hidden safely")
C_Map.GetMapRectOnMap=originalRectangle

local beforeStopPin=nativeWaypoint
NS.Stop()
eq(NS.DB.activeID,nil,"stop removes active destination")
eq(cleared,0,"stop never clears native waypoint")
eq(nativeWaypoint,beforeStopPin,"native user waypoint retained on stop")
waypointCalls,supertracked=0,0
local ok,mode=NS.ShowOnMap(NS.Points[6])
eq(ok,true,"show accepts catalog record")
eq(mode,"marker","actual native marker reported")
eq(waypointCalls,1,"only explicit map action sets waypoint")
eq(supertracked,1,"successful waypoint supertracked")
eq(WorldMapFrame.mapID,1455,"opens correct destination map")
eq(NS.MapPin:IsShown(),true,"browse target self pin without active navigation")
eq(NS.MapPin.label.text,"城内NPC","browse pin describes selected point")
eq(NS.DB.activeID,nil,"browsing does not start navigation")
NS.Start("east")
WorldMapFrame.mapID=1426
NS.UpdateMapPin()
eq(NS.MapPin.label.text,"东边NPC","starting navigation replaces browsing pin")
NS.Stop()
C_Map.CanSetUserWaypointOnMap=function() return false end
ok,mode=NS.ShowOnMap("north")
eq(ok,true,"unsupported native waypoint still opens map")
eq(mode,"map","map-only fallback not called native marker")
eq(NS.MapPin:IsShown(),true,"self pin survives native waypoint unavailable")
eq(NS.MapPin.label.text,"北边NPC","map-only pin identifies preview target")
combat=true
eq(NS.ShowOnMap("east"),false,"combat map action deferred")
combat=false
OpenWorldMap=function() WorldMapFrame:Hide() end
eq(NS.ShowOnMap("east"),false,"hidden map not called success")
OpenWorldMap=function(id) WorldMapFrame:Show(); WorldMapFrame.mapID=id end
C_Map.CanSetUserWaypointOnMap=function() return true end
C_Map.SetUserWaypoint=function() return false end
ok,mode=NS.ShowOnMap("east")
eq(ok,true,"waypoint failure still allows self map pin")
eq(mode,"map","waypoint failure represented honestly")
eq(NS.ShowOnMap("missing"),false,"unknown preview rejected")
local custom = assert(NS.AddCustom("待删除预览",1426,.5,.5))
assert(NS.ShowOnMap(custom))
assert(NS.RemoveCustom(custom.id))
eq(NS.UpdateMapPin(),false,"deleted custom preview does not leave stale pin")
eq(NS.MapPin:IsShown(),false,"deleted preview pin hidden")
NS.Stop()
eq(NS.MapPin:IsShown(),false,"stop clears own preview pin")
eq(cleared,0,"all workflows leave native clearing alone")

-- A whole directory search shares a single immutable player snapshot.
local positionCalls, worldCalls = 0, 0
C_Map.GetPlayerMapPosition=function() positionCalls=positionCalls+1;return vector(px,py) end
C_Map.GetWorldPosFromMapPos=function(id,p) worldCalls=worldCalls+1;return nativeWorld(id,p) end
local context=NS.GetLocationContext()
eq(positionCalls,1,"context captures player position once")
eq(worldCalls,4,"context calculates world position and basis once")
local distance,scope=NS.MeasurePoint(NS.Points[1],context)
near(distance,91.44,"measure distance in metres")
eq(scope,"same-map","same map measurement scope")
distance,scope=NS.MeasurePoint(NS.Points[6],context)
near(distance,914.4,"measure cross-zone same world")
eq(scope,"same-continent","cross-zone measurement scope")
distance,scope=NS.MeasurePoint(NS.Points[7],context)
eq(distance,nil,"measure does not fabricate cross-continent distance")
eq(scope,"other-continent","cross-continent measurement scope")
distance,scope=NS.MeasurePoint(NS.Points[8],context)
eq(distance,nil,"instance destination never yields outdoor distance")
eq(scope,"unknown","instance destination scope unknown")
eq(positionCalls,1,"all candidates reuse player position")
eq(worldCalls,6,"each measurable candidate adds only one world transform")
near(context.x,.5,"measurement leaves context coordinate intact")
near(context.basis.ex,0,"measurement leaves context orientation intact")
near(NS.Points[1].x,.6,"measurement leaves source point intact")
distance,scope=NS.MeasurePoint({mapID=1426,x=0/0,y=.5},context)
eq(distance,nil,"invalid measurement target rejected")
eq(scope,"unknown","invalid target has no scope")
instance=true
distance,scope=NS.MeasurePoint(NS.Points[1],NS.GetLocationContext())
eq(distance,nil,"instance player has no outdoor measurement")
eq(scope,"unknown","instance player has no outdoor scope")
instance=false
C_Map.GetWorldPosFromMapPos=nil
context=NS.GetLocationContext()
near(NS.MeasurePoint(NS.Points[1],context),91.44,"measurement uses map-size fallback")
distance,scope=NS.MeasurePoint(NS.Points[6],context)
eq(distance,nil,"no transform means no cross-zone measurement")
eq(scope,"same-continent","known continent retained when distance unavailable")
C_Map.GetWorldPosFromMapPos=function(id,p)
    if id==1455 then return 90,vector(1,2) end
    return nativeWorld(id,p)
end
distance,scope=NS.MeasurePoint(NS.Points[6],NS.GetLocationContext())
eq(distance,nil,"different world frames never compared")
eq(scope,"unknown","different world frame scope unknown")
C_Map.GetWorldPosFromMapPos=nativeWorld
C_Map.GetPlayerMapPosition=function() return vector(px,py) end

-- Native tracking is opt-in by Start, with ownership protection on Stop.
local function setNative(p) waypointCalls=waypointCalls+1;nativeWaypoint=p;return true end
local function getNative() return nativeWaypoint end
local function setTracking(value)
    if value then supertracked=supertracked+1 else nativeOffCalls=nativeOffCalls+1 end
    nativeTracking=value
end
C_Map.SetUserWaypoint=setNative
C_Map.GetUserWaypoint=getNative
C_SuperTrack.SetSuperTrackedUserWaypoint=setTracking
C_SuperTrack.IsSuperTrackingUserWaypoint=function() return nativeTracking end
WorldMapFrame:Hide()
NS.Start("east")
eq(WorldMapFrame:IsShown(),false,"native Start does not force world map open")
eq(NS.GetNavigation().nativeTracking,true,"HUD receives boolean confirmed tracking")
eq(NS.GetNavigation().nativeMode,"active","HUD can read confirmed native mode")
local stoppedBefore=nativeOffCalls
local retainedPin=nativeWaypoint
NS.Stop()
eq(nativeOffCalls,stoppedBefore+1,"Stop disables only its own active supertracking")
eq(nativeWaypoint,retainedPin,"Stop retains the shared map pin")
eq(NS.GetNativeTrackingStatus(),"hud","stopped status uses independent mode")
NS.Start("east")
assert(NS.ShowOnMap("north"))
eq(NS.DB.activeID,"east","map preview does not replace independent navigation target")
eq(NS.GetNavigation().nativeTracking,false,"previewing another pin does not falsely claim active target tracked")
eq(NS.GetNavigation().nativeMode,"external","preview mismatch is represented to HUD")

NS.Start("east")
nativeWaypoint={uiMapID=1426,position=vector(.7,.8)}
NS.OnNativeTrackingChanged()
eq(NS.GetNativeTrackingStatus(),"external","manual pin change releases ownership")
stoppedBefore=nativeOffCalls
NS.Stop()
eq(nativeOffCalls,stoppedBefore,"Stop leaves another feature's tracking alone")
near(nativeWaypoint.position.x,.7,"manual pin remains unchanged")
NS.Start("east")
nativeTracking=false
NS.OnNativeTrackingChanged()
eq(NS.GetNativeTrackingStatus(),"external","manual tracking change releases ownership")
nativeTracking=true -- Player selected the same user pin again: no longer ours.
stoppedBefore=nativeOffCalls
NS.Stop()
eq(nativeOffCalls,stoppedBefore,"tracking switched away and back is not reclaimed")

C_Map.GetUserWaypoint=nil
NS.Start("east")
eq(NS.GetNativeTrackingStatus(),"marker","no getter cannot claim verified native tracking")
stoppedBefore=nativeOffCalls
NS.Stop()
eq(nativeOffCalls,stoppedBefore,"missing getter prevents Stop touching shared tracking")
C_Map.GetUserWaypoint=getNative
C_Map.SetUserWaypoint=function() error("restricted") end
local activatedBefore=supertracked
eq(NS.Start("east"),true,"native error still starts independent HUD")
eq(NS.GetNativeTrackingStatus(),"hud","failed native mark is not called active")
eq(supertracked,activatedBefore,"failed mark never starts native tracking")
C_Map.SetUserWaypoint=function() return false end
NS.Start("east")
eq(NS.GetNativeTrackingStatus(),"hud","false mark return uses HUD fallback")
C_Map.SetUserWaypoint=setNative
C_Map.CanSetUserWaypointOnMap=function() return false end
local markedBefore=waypointCalls
NS.Start("east")
eq(waypointCalls,markedBefore,"unsupported maps skip native marking")
local nativeState,nativeMessage=NS.GetNativeTrackingStatus()
eq(nativeState,"hud","unsupported map falls back")
contains(nativeMessage,"不支持","fallback explains map limitation")
C_Map.CanSetUserWaypointOnMap=function() return true end
combat=true
NS.Start("east")
eq(waypointCalls,markedBefore,"combat does not change native point")
nativeState,nativeMessage=NS.GetNativeTrackingStatus()
eq(nativeState,"hud","combat retains independent HUD")
contains(nativeMessage,"战斗","combat reason is visible")
combat=false;instance=true
NS.Start("east")
eq(waypointCalls,markedBefore,"instance does not change native point")
instance=false
NS.Start("dungeon")
eq(waypointCalls,markedBefore,"instance target does not change native point")
local savedPointConstructor=UiMapPoint.CreateFromCoordinates
UiMapPoint.CreateFromCoordinates=nil
NS.Start("east")
eq(NS.GetNativeTrackingStatus(),"hud","missing point constructor uses HUD")
UiMapPoint.CreateFromCoordinates=savedPointConstructor
C_SuperTrack.SetSuperTrackedUserWaypoint=function() error("tracking unavailable") end
nativeTracking=false
NS.Start("east")
eq(NS.GetNativeTrackingStatus(),"marker","track setter failure reports map marker only")
eq(NS.GetNavigation().nativeTracking,false,"marker-only mode is not truthy native tracking")
eq(NS.GetNavigation().nativeMode,"marker","marker-only native mode remains distinguishable")
C_SuperTrack.SetSuperTrackedUserWaypoint=setTracking
C_SuperTrack.IsSuperTrackingUserWaypoint=nil
NS.Start("east")
eq(NS.GetNativeTrackingStatus(),"marker","missing tracking getter does not claim active")
stoppedBefore=nativeOffCalls
NS.Stop()
eq(nativeOffCalls,stoppedBefore,"unverified tracking never cancelled")
C_SuperTrack.IsSuperTrackingUserWaypoint=function() return nativeTracking end

-- Import only reads the native pin; duplicates reuse saved coordinates.
nativeWaypoint={uiMapID=1426,position=vector(.21,.32)}
local imported=assert(NS.ImportWaypoint())
eq(imported.name,"地图标记","import default label")
near(imported.x,.21,"import preserves native pin coordinate")
eq(imported.mapID,1426,"import preserves map identity")
eq(NS.DB.activeID,nil,"import does not silently start navigation")
local customCount=#NS.DB.custom
local duplicate=assert(NS.ImportWaypoint("另一个名称"))
eq(duplicate.id,imported.id,"duplicate pin reuses saved location")
eq(#NS.DB.custom,customCount,"import does not fill saved locations with duplicates")
nativeWaypoint=nil
eq(NS.ImportWaypoint(),nil,"no native pin import fails safely")
nativeWaypoint={uiMapID=1426,position=vector(1.1,.3)}
eq(NS.ImportWaypoint(),nil,"invalid native coordinate import rejected")
nativeWaypoint={uiMapID=99999,position=vector(.1,.3)}
eq(NS.ImportWaypoint(),nil,"unknown map import rejected")
nativeWaypoint={uiMapID=1426,position=vector(.31,.42)}
local named=assert(NS.ImportWaypoint("保存的图钉"))
eq(named.name,"保存的图钉","import accepts caller's label")
near(nativeWaypoint.position.x,.31,"import never mutates shared native pin")

-- Arrival notifications happen only from the explicit timer/UI update hook.
local notifications={}
NS.Print=function(text) notifications[#notifications+1]=text end
NS.Start("near")
local arrival=NS.GetNavigation()
eq(#notifications,0,"pure navigation measurement never prints arrival")
eq(NS.UpdateArrival(arrival),true,"explicit arrival update prints once")
contains(notifications[1],"附近NPC","arrival message identifies target")
eq(NS.UpdateArrival(arrival),false,"repeated frame suppresses arrival duplicate")
NS.GetNavigation()
eq(#notifications,1,"repeated measurements remain silent")
NS.Start("near")
eq(NS.UpdateArrival(NS.GetNavigation()),true,"starting same target begins a new arrival session")
eq(#notifications,2,"new session gets one arrival notification")
NS.Start("east")
eq(NS.UpdateArrival(arrival),false,"stale arrival does not announce another active target")
eq(NS.UpdateArrival(NS.GetNavigation()),false,"direction state does not announce arrival")
NS.Stop()
eq(NS.UpdateArrival(arrival),false,"stopped navigation never announces arrival")
eq(cleared,0,"new workflows never clear shared native pin")
-- Native task targets are temporary; only client-provided current quest-level
-- points opt into native quest tracking. Explicit candidates keep exact pins.
local nativeQuestID, questTracking, questSets, questClears = 0, false, 0, 0
local function getQuest() return nativeQuestID end
local function isQuest() return questTracking end
local function setQuest(id)
    if id == 0 then questClears=questClears+1 else questSets=questSets+1 end
    nativeQuestID,questTracking=id,id~=0
    if id~=0 then nativeTracking=false end
    NS.OnNativeTrackingChanged()
end
C_SuperTrack.GetSuperTrackedQuestID=getQuest
C_SuperTrack.IsSuperTrackingQuest=isQuest
C_SuperTrack.SetSuperTrackedQuestID=setQuest
C_SuperTrack.SetSuperTrackedUserWaypoint=function(value) setTracking(value);if value then questTracking=false end end
local questPoint={id="quest:101:objective:current",questID=101,mapID=1426,x=.63,y=.52,
    name="任务中的目标",service="任务目标",nativeQuestTracking=true,phase="objective"}
local persistentCount=#NS.DB.custom
local heldPin=nativeWaypoint
local markedBeforeQuest=waypointCalls
eq(NS.StartTransient(questPoint),true,"valid native quest point starts transient navigation")
eq(NS.GetActiveQuestID(),101,"active quest ID exposed")
eq(NS.DB.activeID,questPoint.id,"transient target participates in existing HUD lifecycle")
eq(NS.GetPoint(questPoint.id).transient,true,"transient point distinguished from saved locations")
eq(NS.GetPoint(questPoint.id).category,"quest","transient point has isolated category")
eq(NS.GetPoint(questPoint.id).phase,"objective","quest phase metadata retained")
eq(NS.GetNavigation().nativeTracking,true,"quest tracking verified by current quest getters")
eq(NS.GetNavigation().nativeKind,"quest","native tracking kind identifies quest")
eq(waypointCalls,markedBeforeQuest,"native quest tracking does not overwrite map pin")
eq(nativeWaypoint,heldPin,"existing shared pin remains unchanged")
eq(#NS.DB.custom,persistentCount,"task click does not add a personal location")
eq(NS.ToggleFavorite(questPoint.id),false,"transient quest point cannot become saved favorite")
questPoint.x=.99
near(NS.GetPoint(questPoint.id).x,.63,"snapshot resists later source coordinate mutation")
questPoint.x=.63
local clearBefore=questClears
NS.Stop()
eq(questClears,clearBefore+1,"Stop cancels only its still-active native quest")
eq(nativeQuestID,0,"native quest stop uses empty quest ID")
eq(NS.GetPoint(questPoint.id),nil,"Stop discards transient point")
eq(NS.TransientPoint,nil,"Stop releases session memory")
eq(NS.GetActiveQuestID(),nil,"stopped quest ID unavailable")
eq(nativeWaypoint,heldPin,"quest Stop preserves shared pin")

NS.StartTransient(questPoint)
nativeQuestID=202;questTracking=true;NS.OnNativeTrackingChanged()
eq(NS.GetNativeTrackingStatus(),"external","another quest releases ownership")
clearBefore=questClears
NS.Stop()
eq(questClears,clearBefore,"Stop cannot cancel another quest")
eq(nativeQuestID,202,"other quest remains tracked")
NS.StartTransient(questPoint)
questTracking=false;nativeTracking=true;NS.OnNativeTrackingChanged()
clearBefore=questClears;stoppedBefore=nativeOffCalls
NS.Stop()
eq(questClears,clearBefore,"switching to a user waypoint prevents quest cancellation")
eq(nativeOffCalls,stoppedBefore,"quest Stop cannot cancel another user waypoint")
NS.StartTransient(questPoint)
nativeQuestID=202;questTracking=true;NS.OnNativeTrackingChanged()
nativeQuestID=101;questTracking=true
clearBefore=questClears
NS.Stop()
eq(questClears,clearBefore,"quest switched away and back is not reclaimed")

NS.Start("east")
stoppedBefore=nativeOffCalls
NS.StartTransient(questPoint)
eq(nativeOffCalls,stoppedBefore+1,"switching waypoint to quest cancels owned waypoint only")
clearBefore=questClears
NS.Start("east")
eq(questClears,clearBefore+1,"switching quest to catalogue cancels owned quest only")
eq(NS.GetPoint(questPoint.id),nil,"catalogue navigation discards previous transient")
eq(NS.GetActiveQuestID(),nil,"catalogue point clears quest context")
eq(NS.GetNavigation().nativeKind,"waypoint","catalogue keeps waypoint owner")

local exactQuestPoint={id="quest:303:objective:npc:123",questID=303,mapID=1426,x=.66,y=.5,name="选中的任务 NPC",npcID=123}
local setBefore=questSets
NS.StartTransient(exactQuestPoint)
eq(questSets,setBefore,"explicit candidate does not activate entire quest tracking")
eq(NS.GetNavigation().nativeKind,"waypoint","explicit candidate uses exact waypoint")
eq(NS.GetNavigation().nativeTracking,true,"explicit coordinate tracking confirmed")
eq(NS.GetActiveQuestID(),303,"explicit candidate retains quest context")
eq(NS.GetPoint(questPoint.id),nil,"new transient replaces old slot")
NS.Stop()

C_SuperTrack.GetSuperTrackedQuestID=nil
setBefore=questSets
NS.StartTransient(questPoint)
eq(questSets,setBefore,"missing getter prevents unverified quest mutation")
eq(NS.GetNavigation().nativeKind,"waypoint","missing quest API falls back to waypoint")
eq(NS.GetNavigation().nativeTracking,true,"fallback confirms precise coordinate tracking")
C_SuperTrack.GetSuperTrackedQuestID=getQuest
C_SuperTrack.SetSuperTrackedQuestID=function() error("quest API unavailable") end
NS.StartTransient(questPoint)
eq(NS.GetNavigation().nativeKind,"waypoint","quest setter error falls back")
C_SuperTrack.SetSuperTrackedQuestID=function() return false end
NS.StartTransient(questPoint)
eq(NS.GetNavigation().nativeKind,"waypoint","false quest setter return falls back")
C_SuperTrack.SetSuperTrackedQuestID=function(id) nativeQuestID=id;questTracking=false end
NS.StartTransient(questPoint)
eq(NS.GetNavigation().nativeKind,"waypoint","quest ID alone cannot imply active tracking")
C_SuperTrack.SetSuperTrackedQuestID=setQuest
combat=true
setBefore=questSets;markedBefore=waypointCalls
NS.StartTransient(questPoint)
eq(questSets,setBefore,"combat task start never sets quest tracking")
eq(waypointCalls,markedBefore,"combat task start never sets fallback pin")
eq(NS.GetNavigation().nativeTracking,false,"combat task remains independent")
combat=false;instance=true
NS.StartTransient(questPoint)
eq(questSets,setBefore,"instance task start never sets quest tracking")
eq(NS.GetNavigation().nativeTracking,false,"instance task remains independent")
instance=false
NS.Stop()

NS.Start("east")
eq(NS.StartTransient({id="bad:101",questID=101,mapID=1426,x=.5,y=.5}),false,"temporary namespace required")
eq(NS.DB.activeID,"east","bad temporary ID leaves active point intact")
eq(NS.StartTransient({id="quest:bad",questID=0,mapID=1426,x=.5,y=.5}),false,"positive quest ID required")
eq(NS.StartTransient({id="quest:fractional",questID=2.5,mapID=1426,x=.5,y=.5}),false,"integer quest ID required")
eq(NS.StartTransient({id="quest:nocoordinate",questID=101}),false,"no invented coordinates")
eq(NS.StartTransient({id="quest:badxy",questID=101,mapID=1426,x=1.1,y=.5}),false,"bad coordinates rejected")
eq(NS.StartTransient({id="quest:"..string.rep("x",100),questID=101,mapID=1426,x=.5,y=.5}),false,"temporary ID length bounded")
eq(NS.DB.activeID,"east","invalid quest inputs cannot interrupt navigation")

local oldCustom=NS.DB.custom
NS.DB.custom={}
for i=1,500 do NS.DB.custom[i]={id="custom:"..(1000+i),name="保留地点"..i,mapID=1426,x=.1,y=.1,category="custom",faction="Neutral"} end
eq(NS.AddCustom("超出容量",1426,.2,.3),nil,"fixture reaches personal-location limit")
for i=1,12 do
    eq(NS.StartTransient({id="quest:"..(500+i)..":objective:1",questID=500+i,mapID=1426,x=.6,y=.5,name="任务目标"..i}),true,"task works with full saved locations "..i)
end
eq(#NS.DB.custom,500,"quest navigation never consumes saved places")
eq(NS.GetPoint("quest:501:objective:1"),nil,"old temporary points do not accumulate")
eq(NS.GetActiveQuestID(),512,"latest task replaces previous context")
local stored=NS.DB
NS.Initialize(stored)
eq(NS.TransientPoint,nil,"initialization clears temporary point")
eq(NS.DB.activeID,nil,"initialization clears unresolved temporary active ID")
eq(#NS.DB.custom,500,"initialization preserves saved locations")
NS.DB.custom=oldCustom
NS.Stop()
eq(cleared,0,"quest workflows never clear shared native pin")
print("navigator_navigation_test: " .. checks .. " checks passed")
