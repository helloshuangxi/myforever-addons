-- Native-frame behavior simulation. This does not establish in-game layout or arrow accuracy.
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, needle, message)
    checks = checks + 1
    assert(type(value) == "string" and value:find(needle, 1, true), message)
end

local methods = {}
local frames = {}
local function frame(kind, name, parent)
    local f = setmetatable({kind=kind,name=name,parent=parent,scripts={},shown=true,enabled=true,text="",width=0,height=0}, {__index=methods})
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function methods:SetScript(k, fn)
    self.scripts[k] = fn
    -- A search handler must tolerate an initial template callback during construction.
    if k == "OnTextChanged" and fn then fn(self) end
end
function methods:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:GetStringHeight()
    local count=0
    for line in (self.text .. "\n"):gmatch("(.-)\n") do count=count+math.max(1,math.ceil(#line/math.max(1,self.width/8))) end
    return count*14
end
function methods:SetPoint(...) self.point={...} end
function methods:GetPoint() return unpack(self.point or {"CENTER",UIParent,"CENTER",0,0}) end
function methods:ClearAllPoints() self.point=nil end
function methods:CreateFontString(name,layer,template)
    local t=frame("FontString",name,self);t.template=template;return t
end
function methods:CreateTexture() return frame("Texture",nil,self) end
function methods:SetHighlightTexture() self.highlight=frame("Texture",nil,self) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetEnabled(v) self.enabled=v end
function methods:Click()
    if self.enabled and self:IsVisible() and self.scripts.OnClick then self.scripts.OnClick(self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:Show()
    local previous=self.shown
    self.shown=true
    if not previous and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() self.shown=false end
function methods:ClearFocus() self.focus=false end
function methods:SetFocus() self.focus=true end
function methods:SetRotation(v) self.rotation=v end
function methods:StartMoving() self.moving=true end
function methods:StopMovingOrSizing() self.moving=false end
function methods:SetScale(v) self.scale=v end
for _, key in ipairs({"SetJustifyH","SetJustifyV","SetWordWrap","SetSpacing","SetTextColor","SetBackdrop","SetBackdropColor",
    "SetBackdropBorderColor","SetVertexColor","SetAutoFocus","SetMaxLetters","SetMovable","SetClampedToScreen","EnableMouse",
    "RegisterForDrag","SetFrameStrata","SetTexture","EnableMouseWheel"}) do methods[key]=function() end end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetTextColor(...) self.color={...} end
function methods:SetBackdropBorderColor(...) self.borderColor={...} end
function methods:SetBackdropColor(...) self.backgroundColor={...} end
function methods:SetWordWrap(value) self.wordWrap=value end
function methods:SetJustifyV(value) self.justifyV=value end
function methods:SetJustifyH(value) self.justifyH=value end
function methods:SetAlpha(value) self.alpha=value end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetAllPoints(parent) self.allPoints=parent end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:SetVerticalScroll(value) self.scroll=value end

CreateFrame=frame
UIParent=frame("Frame");UIParent:SetSize(1920,1080)
UISpecialFrames={}
C_Map={GetBestMapForUnit=function()return 1455 end,GetMapInfo=function(id)return {name=id==1455 and "铁炉堡"or("地图"..id),mapType=3,parentMapID=100}end}
UnitFactionGroup=function()return "Alliance"end
local NS={}
local root="_forever_/Interface/AddOns/MyForeverNavigator/"
for _,file in ipairs({"Core.lua","Data.lua","Classification.lua"})do assert(loadfile(root..file))("MyForeverNavigator",NS)end
local trainerGroups={"warrior","paladin","hunter","rogue","priest","shaman","mage","warlock","druid"}
assert(NS.Categories[1].id=="trainers","class trainers must be present in real catalogue")
NS.Initialize(nil)
NS.GetPlayerPosition=function()return 1455,.3,.4 end
NS.GetLocationContext=function()return {mapID=1455,x=.3,y=.4}end
NS.MeasurePoint=function(p)
    if p.mapID==1455 then return 100+(p.npcID or 0)%100,"same-map"end
    if p.mapID==1452 then return nil,"other-continent"end
    return nil,"unknown"
end
local coreSearch=NS.Search
local searchCalls,lastOptions,lastQuery=0,nil,nil
NS.Search=function(query,options)
    searchCalls=searchCalls+1;lastOptions=options;lastQuery=query
    return coreSearch(query,options)
end
local mode,distance,detailText,nativeTracking,nativeReason="direction",1250,"室外直线方位",false,"未启用原生追踪"
local angle,statusText=.7,"导航状态"
local importError,arrivalCalls=nil,0
NS.Print=function(message)NS.message=message end
NS.Start=function(p)NS.DB.activeID=p.id;return true end
NS.Stop=function()NS.DB.activeID=nil end
NS.ShowOnMap=function(p)NS.mappedID=p.id;return true end
NS.ImportWaypoint=function()
    if importError then return nil,importError end
    return NS.AddCustom("地图标记",1455,.2,.4)
end
NS.UpdateArrival=function(nav)arrivalCalls=arrivalCalls+1;NS.arrivalMode=nav.mode end
NS.GetNavigation=function()
    if NS.DB.activeID then return {point=NS.GetPoint(NS.DB.activeID),mode=mode,angle=angle,distance=distance,status=statusText,detail=detailText,nativeTracking=nativeTracking,nativeReason=nativeReason}end
    return {mode="unavailable",status="没有目标"}
end
assert(loadfile(root.."UI.lua"))("MyForeverNavigator",NS)
NS.CreateUI()
local ui=NS.UI
local function category(id)
    for _,b in ipairs(ui.npcCategories)do if b.category==id then return b end end
    error("Missing category "..id)
end
local function shownResults(browser)
    local n=0;for _,row in ipairs(browser.rows)do if row:IsVisible()then n=n+1 end end;return n
end
local enemy
for _,p in ipairs(NS.Points)do if p.faction=="Horde"then enemy=p;break end end
assert(enemy)
local custom=assert(NS.AddCustom("家门口",1455,.1,.2))
NS.ToggleFavorite(enemy.id)
eq(ui.workspace,"npc","default workspace is NPC search")
eq(NS.Panel.controls,ui,"named panel exposes controls for native verification")
eq(NS.Panel:IsShown(),false,"directory initially closed")
eq(NS.HUD.mouse,false,"HUD body permits world clicks")
eq(NS.HUD.helpTarget.mouse,true,"HUD title remains interactive")
eq(#UISpecialFrames,1,"Escape registered once")
NS.ToggleUI(true);NS.ToggleUI(true)
eq(NS.Panel:IsShown(),true,"force show does not toggle closed")
eq(NS.Panel.width,900,"organized directory width")
eq(NS.Panel.height,600,"organized directory height")
eq(#ui.npcCategories,#NS.Categories+1,"NPC sidebar adapts to all registered purposes")
eq(ui.npcCategories[2].category,"trainers","class trainers immediately follow all NPCs")
for _,b in ipairs(ui.npcCategories)do eq(b.category~="favorites"and b.category~="custom",true,"personal places excluded from NPC purposes")end
local function top(control)return -control.point[3]end
local previousBottom=0
for _,b in ipairs(ui.npcCategories)do
    eq(top(b)>=previousBottom,true,"purpose buttons do not overlap")
    previousBottom=top(b)+b.height
end
eq(top(ui.subTitle)>=previousBottom+8,true,"subcategory heading below all purposes")
previousBottom=top(ui.subTitle)+ui.subTitle.height
for _,b in ipairs(ui.subcategories)do
    eq(top(b)>=previousBottom+4,true,"subcategory rows do not overlap heading or each other")
    previousBottom=top(b)+b.height
end
eq(top(ui.subNext)>=previousBottom+8,true,"subcategory pager clears the final row")
eq(top(ui.subNext)+ui.subNext.height<=ui.npcPage.height-ui.sidebarHint.height-4,true,"pager clears bottom Escape hint")
NS.RefreshUI()
eq(lastOptions.includeCustom,false,"NPC search excludes custom coordinates")
eq(lastOptions.sort,"distance","NPC search defaults to nearest")
for _,p in ipairs(ui.npcBrowser.results)do eq(p.category~="custom",true,"NPC results contain no custom place")end
eq(ui.form:IsShown(),false,"custom form not shown on NPC page")
eq(ui.createToggle:IsVisible(),false,"new-place actions absent from NPC page")
eq(ui.import:IsVisible(),false,"import action absent from NPC page")
eq(ui.npcBrowser.filterBar:IsShown(),false,"advanced NPC filters initially folded")
eq(ui.npcBrowser.details.extra:IsShown(),false,"extended NPC data initially folded")
eq(ui.npcBrowser.rows[1].distance.text~="距离未知",true,"nearby rows expose measured distance")
ui.npcBrowser.sort:Click();eq(lastOptions.sort,"name","name sort selectable")
ui.npcBrowser.sort:Click();eq(lastOptions.sort,"distance","nearest sort restored")
ui.filterToggle:Click();eq(ui.npcBrowser.filterBar:IsShown(),true,"advanced filters expand on demand")
ui.zone:Click();eq(lastOptions.currentZone,true,"zone filter applied within NPC page")
ui.filterToggle:Click();eq(ui.npcBrowser.filterBar:IsShown(),false,"advanced filters fold again")
-- Nine class facets are reachable over two pages, without using the query as a filter.
ui.npcBrowser.search:SetText("训练")
category("trainers"):Click()
eq(lastOptions.category,"trainers","trainer purpose applied")
eq(lastOptions.subcategory,"all","trainer purpose initially shows every class")
local trainerVisited={}
while true do
    for _,b in ipairs(ui.subcategories)do if b.entry then trainerVisited[b.entry.id]=true end end
    if not ui.subNext.enabled then break end
    ui.subNext:Click()
end
for _,token in ipairs(trainerGroups)do eq(trainerVisited["trainers:"..token],true,"class facet reachable: "..token)end
local druid
for _,b in ipairs(ui.subcategories)do if b.entry and b.entry.id=="trainers:druid"then druid=b end end
assert(druid);druid:Click()
eq(lastOptions.subcategory,"trainers:druid","second-page class can be selected")
eq(ui.npcBrowser.search:GetText(),"训练","class facet preserves independent query")
-- NPC categories use a real hierarchical taxonomy without changing the search query.
ui.npcBrowser.search:SetText("声望")
category("reputation"):Click()
eq(ui.npcBrowser.search:GetText(),"声望","purpose change preserves search text")
eq(lastOptions.category,"reputation","purpose selection reaches Core.Search")
local expected={};for _,c in ipairs(NS.GetSubcategories("reputation"))do expected[c.id]=true end
local visited={}
while true do
    for _,b in ipairs(ui.subcategories)do if b.entry then visited[b.entry.id]=true end end
    if not ui.subNext.enabled then break end
    ui.subNext:Click()
end
for id in pairs(expected)do eq(visited[id],true,"every reputation subcategory reachable: "..id)end
local lastSub
for _,b in ipairs(ui.subcategories)do if b.entry and b.entry.id~="all"then lastSub=b end end
assert(lastSub);lastSub:Click()
eq(lastOptions.subcategory,lastSub.entry.id,"subcategory stays separate from query")
eq(lastQuery,"声望","subcategory does not replace query")
-- Navigation workspace is based on active navigation, not a selected result.
ui.workspaceTabs.navigation:Click()
eq(ui.workspace,"navigation","navigation workspace selected")
eq(ui.nav.empty:IsVisible(),true,"clear empty navigation state")
eq(ui.nav.active:IsVisible(),false,"no stale active navigation card")
ui.nav.find:Click();eq(ui.workspace,"npc","empty-state action returns to NPC page")
-- Places is independent from NPC faction, zone and taxonomy conditions.
ui.workspaceTabs.places:Click()
eq(ui.workspace,"places","personal places workspace selected")
eq(lastOptions.category,"favorites","places initially shows favorites")
eq(lastOptions.faction,"all","favorites includes all factions")
eq(not lastOptions.currentZone,true,"places does not inherit NPC zone filter")
eq(not lastOptions.subcategory or lastOptions.subcategory=="all",true,"places does not inherit taxonomy filter")
eq(ui.placeBrowser.rows[1].point.id,enemy.id,"enemy NPC favorite stays visible")
eq(ui.form:IsShown(),false,"new-place form starts folded")
eq(ui.npcPage:IsVisible(),false,"NPC sidebar not visible on places page")
ui.placeTabs.custom:Click();eq(lastOptions.category,"custom","custom places subtab")
eq(ui.placeBrowser.rows[1].point.id,custom.id,"custom list displayed separately")
ui.createToggle:Click();eq(ui.form:IsShown(),true,"form appears only after New place")
eq(ui.placeBrowser.visibleRows,4,"expanded form reduces rows to fit")
ui.mapInput:SetText("1455");ui.xInput:SetText("12.4");ui.yInput:SetText("34.6");ui.nameInput:SetText("自建地点")
ui.save:Click()
eq(ui.form:IsShown(),false,"successful save folds form")
local saved=NS.GetPoint(ui.placeBrowser.state.selectedID)
eq(saved.name,"自建地点","new custom point selected")
eq(saved.x,.124,"coordinate percent converted")
eq(ui.placeBrowser.details.delete:IsVisible(),true,"custom deletion belongs to places page")
eq(ui.placeBrowser.visibleRows,6,"folding form restores six rows")
ui.placeBrowser.details.more:Click();eq(ui.placeBrowser.details.extra:IsShown(),true,"extra data explicitly expanded")
contains(ui.placeBrowser.details.info.text,"地图 ID","technical IDs are in extra data")
ui.placeBrowser.details.more:Click();eq(ui.placeBrowser.details.extra:IsShown(),false,"extra data folded")
ui.placeBrowser.details.start:Click();NS.RefreshHUD()
eq(NS.DB.activeID,saved.id,"place detail starts matching navigation")
eq(NS.HUD:IsShown(),true,"active target shows HUD")
eq(NS.HUD.arrow.rotation,.7,"direction arrow rotation retained")
eq(NS.HUD.arrow.width,50,"large navigation arrow retained")
contains(NS.HUD.distance.text,"1.2 公里","distance separate from status")
eq(NS.HUD.title.template,"GameFontNormalLarge","target name uses prominent type")
eq(NS.HUD.distance.template,"GameFontNormalHuge","distance uses independent larger type")
local h=NS.HUD
eq(h.width,300,"HUD is a compact fixed-width strip")
eq(h.height,84,"HUD starts at fixed compact height")
eq(h.backgroundColor[4],.56,"only background has requested transparency")
eq(h.alpha,nil,"parent alpha never fades primary text")
for _,key in ipairs({"location","region","status","detail","marker"})do eq(h[key],nil,"HUD has no auxiliary field: "..key)end
eq(h.helpTarget.scripts.OnEnter,nil,"drag handle has no hover explanation")
eq(h.helpTarget.scripts.OnLeave,nil,"drag handle has no tooltip machinery")
eq(h.helpTarget.scripts.OnDragStart~=nil,true,"compact title remains draggable")
eq(h.helpTarget.scripts.OnDragStop~=nil,true,"drag release still saves position")
eq(h.map.label.text,"地图","map action shows explicit Chinese caption")
eq(h.close.label.text,"关闭","stop action shows explicit Chinese caption")
for _,control in ipairs({h.map,h.close})do
    eq(control.width,48,"two Chinese action characters have sufficient width")
    eq(control.height,28,"action button accommodates Chinese font height")
    eq(control.label.width,40,"label width fits both Chinese characters without ellipsis")
    eq(control.label.height,24,"label height clears 15px Chinese native small font")
    eq(control.label.wordWrap,false,"action text never wraps or clips into second line")
    eq(control.label.justifyH,"CENTER","action text horizontally centered")
    eq(control.label.justifyV,"MIDDLE","action text vertically centered")
    eq(control.label.color[4]or 1,1,"action caption itself is opaque")
    eq(control.backgroundColor[4],.16,"action background stays faint")
end
for _,primary in ipairs({h.title,h.distance,h.direction})do eq(primary.color[4]or 1,1,"primary text stays opaque")end
eq(h.map.label.color[1]<h.title.color[1],true,"operation text has lower contrast than target")
eq(h.close.borderColor[4]<.3,true,"operation borders recede")
eq(h.direction.text,"左前方","positive texture angle means target to character left")
local directions={{0,"前方"},{-math.pi/4,"右前方"},{-math.pi/2,"右侧"},{-3*math.pi/4,"右后方"},
    {-math.pi,"后方"},{3*math.pi/4,"左后方"},{math.pi/2,"左侧"},{math.pi/4,"左前方"}}
for _,sample in ipairs(directions)do
    angle=sample[1];NS.RefreshHUD()
    eq(h.direction.text,sample[2],"eight directions are relative to player facing")
    eq(h.direction:IsShown(),true,"relative direction visible in direction mode")
    eq(h.arrow.rotation,angle,"arrow keeps original rotation sign")
    eq(h.height,84,"direction updates never expand compact HUD")
end
for _,sample in ipairs({{-math.pi/2-8*math.pi,"右侧"},{math.pi/2+8*math.pi,"左侧"},
    {6*math.pi,"前方"},{-6*math.pi,"前方"},{math.pi,"后方"}})do
    angle=sample[1];NS.RefreshHUD();eq(h.direction.text,sample[2],"negative and multiple-turn angles wrap")
end
angle=-math.pi/8+.0001;NS.RefreshHUD();eq(h.direction.text,"前方","front sector extends up to half octant")
angle=-math.pi/8-.0001;NS.RefreshHUD();eq(h.direction.text,"右前方","clockwise sector starts beyond half octant")
for _,sample in ipairs({math.huge,-math.huge,0/0,"0",false})do
    angle=sample;NS.RefreshHUD()
    eq(h.direction.text,"暂无朝向","unusable direction uses short honest state")
    eq(h.arrow:IsShown(),false,"unusable angle never reaches texture rotation")
    eq(h.height,84,"invalid angles cannot expand HUD")
end
angle=nil;NS.RefreshHUD();eq(h.direction.text,"暂无朝向","nil angle never invents direction")
angle=0;NS.RefreshHUD()
local function bounds(region)
    local anchor,x,y=region.point[1],region.point[2]or 0,region.point[3]or 0
    if anchor=="TOPRIGHT"then x=h.width+x-region.width end
    return {left=x,right=x+region.width,top=-y,bottom=-y+region.height}
end
local a,d,dist,t,m,c=bounds(h.arrow),bounds(h.direction),bounds(h.distance),bounds(h.title),bounds(h.map),bounds(h.close)
eq(a.bottom+4<=d.top,true,"direction label is below arrow with clear gap")
eq(math.max(a.right,d.right)+4<=dist.left,true,"arrow and direction clear central text")
eq(t.bottom+6<=dist.top,true,"target name clears distance")
eq(math.max(t.right,dist.right)+4<=m.left,true,"primary text clears operation column")
eq(m.bottom+6<=c.top,true,"map and close controls are vertically separate")
for _,region in ipairs({h.arrow,h.direction,h.distance,h.title,h.map,h.close})do
    local box=bounds(region)
    eq(box.left>=0 and box.right<=h.width,true,"compact HUD element stays within horizontal bounds")
    eq(box.top>=0 and box.bottom<=h.height,true,"compact HUD element stays within vertical bounds")
end
h.helpTarget.scripts.OnDragStart(h.helpTarget);eq(h.moving,true,"title drag still moves HUD")
h:SetPoint("TOPLEFT",UIParent,"TOPLEFT",125,-64)
h.helpTarget.scripts.OnDragStop(h.helpTarget)
eq(h.moving,false,"drag release ends movement")
eq(NS.DB.hud.x,125,"drag saves horizontal position")
eq(NS.DB.hud.y,-64,"drag saves vertical position")
nativeTracking=true;NS.RefreshHUD()
eq(h.status,nil,"native tracking adds no HUD status element")
eq(h.height,84,"native tracking adds no HUD height")
nativeTracking=false;angle=.7
NS.HUD.map:Click();eq(NS.mappedID,saved.id,"HUD map uses active target")
NS.ToggleUI(true)
ui.workspaceTabs.navigation:Click()
eq(ui.nav.point.id,saved.id,"navigation page follows active target")
local beforeSearch=searchCalls
distance=85;NS.RefreshHUD()
eq(searchCalls,beforeSearch,"live navigation refresh does not search catalogue")
contains(ui.nav.distance.text,"85 米","navigation page distance updates with HUD sample")
-- Browsing another NPC never swaps the active navigation card.
ui.workspaceTabs.npc:Click();NS.SetSearch("")
ui.npcBrowser.rows[2]:Click()
ui.workspaceTabs.navigation:Click()
eq(ui.nav.point.id,saved.id,"navigation ignores another selected NPC")
ui.nav.map:Click();eq(NS.mappedID,saved.id,"navigation map shortcut")
NS.ToggleUI(true)
ui.nav.resume:Click();eq(NS.DB.activeID,saved.id,"resume uses active destination")
mode="cross";distance=nil;detailText=string.rep("跨大陆交通说明",80);statusText=string.rep("需要跨大陆交通",20);NS.RefreshHUD()
eq(h.arrow:IsShown(),false,"cross-space hides false arrow")
eq(h.direction.text,"跨区","cross-space uses only short direction-slot state")
eq(h.distance.text,"距离未知","cross-space distance remains honest")
eq(h.height,84,"cross-space never expands HUD")
eq(h.detail,nil,"transport explanation has no HUD text element")
mode="arrived";distance=16;NS.RefreshHUD()
eq(h.direction.text,"已到达","arrival uses short direction-slot state")
eq(h.distance.text,"16 米","arrival screenshot distance remains visible")
eq(h.height,84,"arrival remains the same compact size")
eq(NS.arrivalMode,"arrived","arrival hook receives active sample")
mode="unavailable";angle=0;statusText="副本内暂停方向指引";detailText=string.rep("离开副本后恢复方向指引。",100);NS.RefreshHUD()
eq(h.direction.text,"暂无朝向","unavailable mode never invents relative direction")
eq(h.arrow:IsShown(),false,"unavailable mode never shows misleading forward arrow")
eq(h.height,84,"long exceptional guidance cannot enlarge HUD")
eq(h.status,nil,"exceptional status has no additional HUD text")
contains(ui.nav.status.text,statusText,"current navigation workspace retains full status")
contains(ui.nav.status.text,"离开副本后恢复方向指引","current navigation workspace retains full explanation")
mode="direction";distance=85;NS.RefreshHUD()
eq(h.height,84,"resumed navigation keeps fixed size")
h.close:Click()
eq(NS.DB.activeID,nil,"explicit close action stops navigation")
eq(h:IsShown(),false,"explicit close hides HUD")
NS.Start(saved);NS.RefreshHUD()
ui.nav.stop:Click()
eq(NS.DB.activeID,nil,"stop clears active navigation")
eq(ui.nav.empty:IsVisible(),true,"stop restores clear empty state")
eq(NS.HUD:IsShown(),false,"stop hides HUD")
-- The forms and each workspace's text do not leak across tabs.
ui.workspaceTabs.places:Click()
ui.placeBrowser.search:SetText("家")
ui.createToggle:Click();eq(ui.form:IsShown(),true,"place form can be reopened")
ui.workspaceTabs.npc:Click()
eq(ui.form:IsShown(),false,"leaving places hides its form completely")
eq(ui.import:IsVisible(),false,"import action does not leak onto NPC page")
ui.workspaceTabs.places:Click()
eq(ui.placeBrowser.search:GetText(),"家","places search preserved across workspace changes")
ui.createToggle:Click()
ui.placeBrowser.search:SetText("")
ui.current:Click()
eq(NS.GetPoint(ui.placeBrowser.state.selectedID).x,.3,"save current retains player position behavior")
local oldActive=NS.DB.activeID
importError="请先在地图上放置标记。";ui.import:Click()
eq(NS.DB.activeID,oldActive,"invalid import preserves active target")
eq(NS.message,importError,"invalid import reason visible")
importError=nil;ui.import:Click()
eq(NS.GetPoint(NS.DB.activeID).name,"地图标记","valid import starts navigation from places toolbar")
NS.SetSearch("木喉")
eq(ui.workspace,"npc","slash search switches to NPC workspace")
eq(lastOptions.category,"all","slash search resets purpose")
eq(lastOptions.subcategory,"all","slash search resets subcategory")
eq(lastOptions.currentZone,false,"slash search covers world again")
eq(lastOptions.includeCustom,false,"slash search does not pull in own coordinates")
eq(ui.npcBrowser.search:GetText(),"木喉","slash search content retained")
ui.npcBrowser.search:SetFocus();ui.npcBrowser.search.scripts.OnEscapePressed(ui.npcBrowser.search)
eq(ui.npcBrowser.search.focus,false,"Escape clears input focus")
eq(NS.Panel:IsShown(),true,"input Escape keeps directory visible")
-- Result pagination and expanded detail geometry remain inside browser bounds.
NS.SetSearch("")
local first=ui.npcBrowser.rows[1].point.id
ui.npcBrowser.next:Click()
eq(ui.npcBrowser.rows[1].point.id~=first,true,"NPC result pagination remains available")
eq(shownResults(ui.npcBrowser),6,"six NPC rows shown")
for _,browser in ipairs({ui.npcBrowser,ui.placeBrowser})do
    local y=-browser.next.point[3]
    eq(y+browser.next.height<=browser.height,true,"pager within browser height")
    eq(-browser.details.extra.point[3]+browser.details.extra.height<=browser.details.height,true,"expanded details within card")
end
print("Navigator UI: "..checks.." behavior checks passed (simulated)")
