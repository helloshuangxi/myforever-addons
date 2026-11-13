-- Native quest click hooks and candidate popup in a Lua 5.1 frame sandbox.
-- These checks do not establish real-client click routing or quest coordinates.
local checks=0
local function eq(actual,expected,message)
    checks=checks+1
    assert(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function contains(actual,needle,message)
    checks=checks+1
    assert(type(actual)=="string" and actual:find(needle,1,true),message)
end
local methods,frames={},{}
local function frame(kind,name,parent)
    local f=setmetatable({kind=kind,name=name,parent=parent,scripts={},events={},shown=true,enabled=true,text="",width=0,height=0},{__index=methods})
    frames[#frames+1]=f;if name then _G[name]=f end;return f
end
function methods:SetScript(key,fn)self.scripts[key]=fn end
function methods:GetScript(key)return self.scripts[key]end
function methods:HookScript(key,fn)
    local original=self.scripts[key]
    self.scripts[key]=function(...)if original then original(...)end;fn(...)end
end
function methods:IsProtected()return self.protected==true end
function methods:RegisterEvent(event)self.events[event]=true end
function methods:SetSize(w,h)self.width,self.height=w,h end
function methods:SetWidth(w)self.width=w end
function methods:SetHeight(h)self.height=h end
function methods:GetWidth()return self.width end
function methods:GetHeight()return self.height end
function methods:SetPoint(...)self.point={...}end
function methods:ClearAllPoints()self.point=nil end
function methods:CreateFontString()return frame("FontString",nil,self)end
function methods:SetText(text)self.text=text end
function methods:GetStringHeight()
    local n=0;for line in (self.text.."\n"):gmatch("(.-)\n")do n=n+math.max(1,math.ceil(#line/math.max(1,self.width/8)))end;return n*14
end
function methods:SetHighlightTexture()self.highlight=frame("Texture",nil,self)end
function methods:GetHighlightTexture()return self.highlight end
function methods:SetEnabled(v)self.enabled=v end
function methods:SetAlpha(v)self.alpha=v end
function methods:Show()
    local was=self.shown;self.shown=true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self)end
end
function methods:Hide()
    local was=self.shown;self.shown=false
    if was and self.scripts.OnHide then self.scripts.OnHide(self)end
end
function methods:SetShown(v)if v then self:Show()else self:Hide()end end
function methods:IsShown()return self.shown end
function methods:IsVisible()return self.shown and(not self.parent or self.parent:IsVisible())end
function methods:SetScale(v)self.scale=v end
function methods:Click(button,...)
    if self.enabled and self:IsVisible() and self.scripts.OnClick then return self.scripts.OnClick(self,button or "LeftButton",...)end
end
for _,key in ipairs({"SetJustifyH","SetJustifyV","SetWordWrap","SetTextColor","SetSpacing","SetFrameStrata","SetClampedToScreen",
    "SetMovable","EnableMouse","SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetVertexColor","RegisterForDrag","StartMoving","StopMovingOrSizing"})do methods[key]=function()end end
CreateFrame=frame;UIParent=frame("Frame");UIParent:SetSize(1920,1080);UISpecialFrames={}
local NS={}
local root="_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root.."Core.lua"))("MyForeverNavigator",NS)
local now,cx,cy=0,100,100
local shift,ctrl,alt,meta,chat,watch=false,false,false,false,false,false
local combat=false
local active={[1]=true,[2]=true,[10]=true}
GetTime=function()return now end
GetCursorPosition=function()return cx,cy end
IsShiftKeyDown=function()return shift end
IsControlKeyDown=function()return ctrl end
IsAltKeyDown=function()return alt end
IsMetaKeyDown=function()return meta end
IsModifiedClick=function(key)return key=="CHATLINK"and chat or key=="QUESTWATCHTOGGLE"and watch end
InCombatLockdown=function()return combat end
C_QuestLog={GetLogIndexForQuestID=function(id)return active[id]and id or nil end,IsQuestDisabledForSession=function(id)return id==10 end}
local timers={}
C_Timer={After=function(delay,fn)
    assert(type(delay)=="number"and delay>=0,"nonnegative timer delay")
    timers[#timers+1]={at=now+delay,fn=fn}
end}
local function flush()
    while true do
        local ready,waiting={},{}
        for _,timer in ipairs(timers)do
            if timer.at<=now+1e-9 then ready[#ready+1]=timer else waiting[#waiting+1]=timer end
        end
        timers=waiting
        if #ready==0 then return end
        for _,timer in ipairs(ready)do timer.fn()end
    end
end
local function advance(value)now=value;flush()end
local hookCount=0
hooksecurefunc=function(owner,key,callback)
    if type(owner)=="string"then callback=key;key=owner;owner=_G end
    local original=owner[key];assert(type(original)=="function")
    hookCount=hookCount+1
    owner[key]=function(...)
        local result=original(...)
        callback(...)
        return result
    end
end
local opened={}
NS.OpenQuestNavigation=function(id)opened[#opened+1]=id end
NS.Print=function(message)NS.message=message end
assert(loadfile(root.."QuestUI.lua"))("MyForeverNavigator",NS)
NS.InitializeQuestUI()
eq(hookCount,0,"missing native modules are safe")
local event
for _,f in ipairs(frames)do if f.events.ADDON_LOADED then event=f end end
assert(event)
eq(event.events.PLAYER_LOGIN,true,"login retries hook installation")
eq(event.events.PLAYER_ENTERING_WORLD,true,"world entry retries hook installation")
eq(event.events.PLAYER_REGEN_ENABLED,true,"combat end retries button installation")
eq(event.events.PLAYER_REGEN_DISABLED,true,"combat entry invalidates delayed clicks")
local frameCount=#frames
NS.InitializeQuestUI();eq(#frames,frameCount,"initialization does not duplicate event frame or popup")
eq(#UISpecialFrames,1,"popup Escape registration is idempotent")
local normalClicks,shiftClicks,rightClicks,plainClicks=0,0,0,0
local nativeQuest,nativeExtra
local function nativeTitleClick(self,button,extra)
    normalClicks=normalClicks+1;nativeQuest=self.questID;nativeExtra=extra
    if shift then shiftClicks=shiftClicks+1 elseif button=="RightButton"then rightClicks=rightClicks+1 else plainClicks=plainClicks+1 end
    if self.hideOnNative then self:Hide()end
    return "native-result"
end
local function title(id)
    local b=frame("Button");b.questID=id;b:SetScript("OnClick",nativeTitleClick);return b
end
local pooled=title(1)
local poolButtons={pooled}
local poolEnumerations,updates=0,0
QuestScrollFrame={titleFramePool={EnumerateActive=function()
    poolEnumerations=poolEnumerations+1
    local i=0;return function()i=i+1;return poolButtons[i]end
end}}
QuestLogQuests_Update=function()updates=updates+1;return "updated"end
QuestMapLogTitleButton_OnClick=nativeTitleClick
local originalGlobal=QuestMapLogTitleButton_OnClick
event.scripts.OnEvent(event,"ADDON_LOADED","Blizzard_UIPanels_Game")
eq(hookCount,1,"late journal list update hooked once")
eq(QuestMapLogTitleButton_OnClick,originalGlobal,"global native click handler untouched")
eq(pooled:GetScript("OnClick")~=nativeTitleClick,true,"unprotected title gets local wrapper")
local wrapper=pooled:GetScript("OnClick")
pooled.hideOnNative=true
pooled:Click("LeftButton","payload")
eq(normalClicks,0,"plain first click waits for double-click interval")
eq(pooled:IsShown(),true,"first click leaves journal title visible for second physical click")
eq(#opened,0,"single click does not open navigator")
advance(.34);eq(normalClicks,0,"single-click delay does not end early")
advance(.35);eq(normalClicks,1,"single click eventually invokes native handler once")
eq(nativeExtra,"payload","delayed native call preserves extra arguments")
eq(pooled:IsShown(),false,"native single-click list hiding still happens after delay")
pooled:Show();advance(1);pooled:Click();advance(1.2);pooled:Click()
eq(normalClicks,1,"double click suppresses both native detail-open actions")
eq(pooled:IsShown(),true,"double click keeps native title available until navigation opens")
eq(#opened,0,"navigation callback deferred after double-click wrapper")
flush();eq(opened[#opened],1,"journal double click resolves current quest")
advance(1.6);eq(normalClicks,1,"cancelled single-click timers stay cancelled")
pooled.hideOnNative=false
local before=#opened
shift=true;advance(2);eq(pooled:Click(),"native-result","modified clicks retain native return value")
advance(2.1);pooled:Click();flush()
eq(shiftClicks,2,"Shift keeps immediate original quest-watch behavior")
eq(#opened,before,"Shift does not navigate")
shift=false;advance(3);pooled:Click("RightButton");advance(3.1);pooled:Click("RightButton");flush()
eq(rightClicks,2,"right-click menu remains immediate")
eq(#opened,before,"right clicks do not navigate")
-- A modifier introduced during the delay cancels the stale plain action.
for i,name in ipairs({"shift","ctrl","alt","meta","chat","watch"})do
    advance(4+i);pooled:Click();local count=normalClicks
    shift=name=="shift";ctrl=name=="ctrl";alt=name=="alt";meta=name=="meta";chat=name=="chat";watch=name=="watch"
    advance(4+i+.35);eq(normalClicks,count,"late modifier cancels delayed original: "..name)
    shift,ctrl,alt,meta,chat,watch=false,false,false,false,false,false
    advance(4+i+.5);eq(normalClicks,count,"cancelled late-modifier click cannot revive: "..name)
end
advance(11);pooled:Click();local count=normalClicks;advance(11.35)
eq(normalClicks,count+1,"next plain click works after modifier cancellation")
-- Refreshes install newly acquired frames once, without changing protected ones.
local protected=title(1);protected.protected=true
local combatTitle=title(1)
poolButtons={pooled,protected,combatTitle};combat=true
QuestLogQuests_Update();eq(combatTitle:GetScript("OnClick"),nativeTitleClick,"combat prevents new script mutations")
eq(protected:GetScript("OnClick"),nativeTitleClick,"protected title untouched")
combat=false;event.scripts.OnEvent(event,"PLAYER_REGEN_ENABLED")
eq(combatTitle:GetScript("OnClick")~=nativeTitleClick,true,"out-of-combat retry installs title wrapper")
eq(protected:GetScript("OnClick"),nativeTitleClick,"protected title still untouched after retry")
eq(pooled:GetScript("OnClick"),wrapper,"pool refresh never stacks wrappers")
local later=title(2);poolButtons[#poolButtons+1]=later
local oldEnums=poolEnumerations
advance(12);flush();eq(poolEnumerations,oldEnums,"timers do not scan title pools")
eq(QuestLogQuests_Update(),"updated","native list update result preserved")
eq(poolEnumerations,oldEnums+1,"one title enumeration per native list rebuild")
eq(later:GetScript("OnClick")~=nativeTitleClick,true,"newly pooled title hooked after rebuild")
-- Pool reuse/hiding/combat cannot run an old action against a new target.
advance(13);pooled:Click();count=normalClicks;pooled.questID=2;advance(13.35)
eq(normalClicks,count,"reused button discards old delayed single click")
eq(nativeQuest~=2,true,"old single click never adopts recycled quest ID")
advance(14);pooled:Click();advance(14.1);pooled:Click();flush()
eq(opened[#opened],2,"recycled button double click resolves new quest")
advance(15);pooled:Click();count=normalClicks;pooled:Hide();pooled:Show();advance(15.35)
eq(normalClicks,count,"pool hide cancels pending original even if same ID reused")
advance(16);pooled:Click();count=normalClicks;combat=true;event.scripts.OnEvent(event,"PLAYER_REGEN_DISABLED")
combat=false;advance(16.35);eq(normalClicks,count,"combat transition cancels delayed action")
advance(17);combat=true;eq(pooled:Click(),"native-result","combat click uses original immediately")
eq(normalClicks,count+1,"combat click does not defer native behavior");combat=false
local external=title(1);poolButtons[#poolButtons+1]=external;QuestLogQuests_Update()
advance(18);external:Click();count=normalClicks
local replacement=function()end;external:SetScript("OnClick",replacement);advance(18.35)
eq(normalClicks,count,"another addon replacing script invalidates delayed native call")
local missingTimer=title(1);poolButtons[#poolButtons+1]=missingTimer
local savedTimers=C_Timer;C_Timer=nil;QuestLogQuests_Update()
eq(missingTimer:GetScript("OnClick"),nativeTitleClick,"no timer capability leaves native click unchanged")
C_Timer=savedTimers;QuestLogQuests_Update()
eq(missingTimer:GetScript("OnClick")~=nativeTitleClick,true,"timer capability can install on later refresh")
-- Tracker-only helper preserves original handlers through post-hooks.
for _,name in ipairs({"ctrl","alt","meta","chat","watch"})do
    now=now+1;NS.HandleQuestClick(1,"LeftButton","modifier")
    ctrl=name=="ctrl";alt=name=="alt";meta=name=="meta";chat=name=="chat";watch=name=="watch"
    now=now+.1;eq(NS.HandleQuestClick(1,"LeftButton","modifier"),false,"modifier click ignored: "..name)
    ctrl,alt,meta,chat,watch=false,false,false,false,false
    now=now+.1;eq(NS.HandleQuestClick(1,"LeftButton","modifier"),false,"modifier breaks click pair: "..name)
end
NS.HandleQuestClick(1,"RightButton","reset")
now=30;NS.HandleQuestClick(1,"LeftButton","timing");now=30.36
eq(NS.HandleQuestClick(1,"LeftButton","timing"),false,"slow repeated clicks are separate")
NS.HandleQuestClick(1,"RightButton","reset")
now=0;NS.HandleQuestClick(1,"LeftButton","timing");now=.35
eq(NS.HandleQuestClick(1,"LeftButton","timing"),true,"double-click threshold included")
flush();eq(opened[#opened],1,"threshold click navigates")
NS.HandleQuestClick(1,"RightButton","reset")
now=32;NS.HandleQuestClick(1,"LeftButton","clock");now=31.9
eq(NS.HandleQuestClick(1,"LeftButton","clock"),false,"backward clock is not a double click")
NS.HandleQuestClick(1,"RightButton","reset")
now=33;cx=100;NS.HandleQuestClick(1,"LeftButton","position");now=33.1;cx=130
eq(NS.HandleQuestClick(1,"LeftButton","position"),false,"distant mouse positions cannot pair")
now=33.2;cx=138
eq(NS.HandleQuestClick(1,"LeftButton","position"),true,"nearby mouse clicks pair")
flush()
for _,id in ipairs({0,-1,1.2,999,10})do eq(NS.HandleQuestClick(id,"LeftButton","invalid"),false,"invalid or disabled quest ignored")end
local nativeTrackerClicks=0
CampaignQuestObjectiveTracker={OnBlockHeaderClick=function()nativeTrackerClicks=nativeTrackerClicks+1 end,EnumerateActiveBlocks=function()error("must not scan tracker pools")end}
event.scripts.OnEvent(event,"ADDON_LOADED","Blizzard_ObjectiveTracker")
eq(hookCount,2,"campaign tracker can hook while regular tracker is absent")
QuestObjectiveTracker={OnBlockHeaderClick=function()nativeTrackerClicks=nativeTrackerClicks+1 end,EnumerateActiveBlocks=function()error("must not scan tracker pools")end}
event.scripts.OnEvent(event,"PLAYER_LOGIN")
eq(hookCount,3,"late regular tracker hooked once")
event.scripts.OnEvent(event,"ADDON_LOADED","OtherAddon");NS.InitializeQuestUI()
eq(hookCount,3,"repeated events do not duplicate native hooks")
local block={id=1}
now=50;QuestObjectiveTracker:OnBlockHeaderClick(block,"LeftButton")
now=50.1;block.id=2;QuestObjectiveTracker:OnBlockHeaderClick(block,"LeftButton")
before=#opened;flush();eq(#opened,before,"pooled tracker blocks read current ID")
now=50.2;QuestObjectiveTracker:OnBlockHeaderClick(block,"LeftButton");flush()
eq(opened[#opened],2,"tracker second click opens current quest")
eq(nativeTrackerClicks,3,"tracker native click count retained")
now=60;NS.HandleQuestClick(1,"LeftButton","questlog");now=60.1
eq(NS.HandleQuestClick(1,"LeftButton",QuestObjectiveTracker),false,"distinct surfaces cannot pair")
event.scripts.OnEvent(event,"PLAYER_ENTERING_WORLD");now=60.2
eq(NS.HandleQuestClick(1,"LeftButton",QuestObjectiveTracker),false,"world change resets pending click")
now=60.3;eq(NS.HandleQuestClick(1,"LeftButton",QuestObjectiveTracker),true,"fresh world click can pair")
before=#opened;active[1]=nil;flush();eq(#opened,before,"quest removed before deferred callback is ignored");active[1]=true
for _,f in ipairs(frames)do eq(f:GetScript("OnUpdate"),nil,"no per-frame pool scanning")end

-- Selected quest details footer adds one sibling button, never per-row buttons.
local function detailsFrame()
    local d=frame("Frame",nil,UIParent);d:SetSize(308,502);d:Hide()
    d.AbandonButton=frame("Button",nil,d);d.AbandonButton:SetSize(105,22)
    d.ShareButton=frame("Button",nil,d);d.ShareButton:SetSize(103,22)
    d.TrackButton=frame("Button",nil,d);d.TrackButton:SetSize(105,22)
    return d
end
local details=detailsFrame()
local nativeTracks=0
local nativeTrackHandler=function()nativeTracks=nativeTracks+1 end
details.TrackButton:SetScript("OnClick",nativeTrackHandler)
details.ShareButton:SetEnabled(false)
QuestMapFrame={QuestsFrame={DetailsFrame=details},DetailsFrame=details}
QuestMapFrame_GetDetailQuestID=function()return QuestMapFrame.DetailsFrame.questID end
local detailShows,detailUpdates=0,0
QuestMapFrame_ShowQuestDetails=function(id)
    detailShows=detailShows+1;details.questID=id;details:Show();return "shown"
end
QuestMapFrame_UpdateQuestDetailsButtons=function()detailUpdates=detailUpdates+1;return "buttons-updated"end
combat=true;event.scripts.OnEvent(event,"ADDON_LOADED","Blizzard_UIPanels_Game")
eq(hookCount,5,"detail-show and native-button updates hooked once when loaded late")
eq(NS.QuestMapNavigationButton,nil,"combat postpones details button creation")
eq(details.AbandonButton.width,105,"combat does not mutate native footer widths")
combat=false;event.scripts.OnEvent(event,"PLAYER_REGEN_ENABLED")
local navigation=NS.QuestMapNavigationButton
eq(navigation~=nil,true,"out-of-combat retry creates detail navigation")
eq(navigation.parent,details,"navigation button is details footer sibling")
eq(NS.QuestUI.detailNavigationButton,navigation,"details button exposed through popup controls too")
eq(NS.QuestUI.detailsFrame,details,"details frame exposed for validation")
eq(navigation.label.text,"导航","requested navigation caption retained")
eq(navigation:IsShown(),false,"hidden details do not leave floating mouse target")
eq(navigation.enabled,false,"no selected quest disables navigation")
eq(details.TrackButton:GetScript("OnClick"),nativeTrackHandler,"native tracking script unchanged")
eq(details.ShareButton.enabled,false,"native disabled state untouched")
local cells={details.AbandonButton,details.ShareButton,details.TrackButton,navigation}
local span=0
for i,b in ipairs(cells)do
    eq(b.width,74,"equal footer cell width")
    eq(b.height,22,"footer height unchanged")
    if i==1 then
        eq(b.point[1],"BOTTOMLEFT","footer begins at bottom left")
        eq(b.point[2],details,"footer anchored to native details parent")
        eq(b.point[4],0,"footer left inset within details")
        eq(b.point[5],-2,"native footer bottom line retained")
    else
        eq(b.point[2],cells[i-1],"footer cells form ordered sibling chain")
        eq(b.point[4],4,"four-pixel sibling gap")
        span=span+4
    end
    span=span+b.width
end
eq(span,details.width,"four-cell horizontal span exactly fits 308px details")
eq(navigation.point[2],details.TrackButton,"navigation directly follows tracking button")
eq(details.height,502,"detail panel height and scroll area unchanged")
local createdFrames=#frames
local sameButton=navigation
event.scripts.OnEvent(event,"ADDON_LOADED","OtherAddon");NS.InitializeQuestUI()
eq(#frames,createdFrames,"repeat initialization never creates another detail button")
eq(hookCount,5,"repeat initialization does not stack detail hooks")
eq(NS.QuestMapNavigationButton,sameButton,"one navigation button reused")
eq(QuestMapFrame_ShowQuestDetails(1),"shown","native detail-show result retained")
eq(navigation:IsShown(),true,"selected details show navigation")
eq(navigation.enabled,true,"active quest enables navigation")
before=#opened;navigation:Click();eq(#opened,before,"detail navigation waits until click processing ends")
flush();eq(opened[#opened],1,"detail navigation resolves active selected quest")
QuestMapFrame_ShowQuestDetails(2);navigation:Click();flush()
eq(opened[#opened],2,"detail switch reads new quest rather than captured ID")
details.questID=1;QuestMapFrame_UpdateQuestDetailsButtons();details.questID=2
navigation:Click();flush();eq(opened[#opened],2,"click rereads quest even when native refresh is pending")
details.TrackButton:Click();eq(nativeTracks,1,"native track remains usable alongside navigation")
eq(QuestMapFrame_UpdateQuestDetailsButtons(),"buttons-updated","native refresh result preserved")
for _,id in ipairs({0,-1,1.2,999,10})do
    details.questID=id;QuestMapFrame_UpdateQuestDetailsButtons()
    eq(navigation.enabled,false,"invalid, non-log or disabled quest disables footer")
end
details.questID=1;QuestMapFrame_UpdateQuestDetailsButtons();details.questID=999
before=#opened;navigation:Click();flush()
eq(#opened,before,"click-time validation rejects stale enabled quest")
eq(navigation.enabled,false,"stale enabled button refreshes disabled state")
details.questID=1;QuestMapFrame_UpdateQuestDetailsButtons();navigation:Click();active[1]=nil;flush()
eq(#opened,before,"quest removed after footer click cannot start deferred navigation")
active[1]=true
details:Hide();eq(navigation:IsShown(),false,"details hide clears owned button visibility")
eq(navigation:IsVisible(),false,"hidden details navigation cannot intercept mouse")
before=#opened;navigation:Click();flush();eq(#opened,before,"hidden footer cannot navigate")
details:Show();eq(navigation:IsShown(),true,"show hook refreshes footer without extra global call")
local sizes=details.AbandonButton.width;combat=true;details:SetWidth(320)
QuestMapFrame_UpdateQuestDetailsButtons()
eq(details.AbandonButton.width,sizes,"combat refresh skips native layout")
eq(navigation.enabled,false,"combat refresh disables owned navigation button")
combat=false;event.scripts.OnEvent(event,"PLAYER_REGEN_ENABLED")
eq(details.AbandonButton.width,77,"combat end reapplies current details width")
eq(navigation.enabled,true,"combat end restores valid navigation action")
span=0;for _,b in ipairs(cells)do span=span+b.width end;span=span+12
eq(span<=details.width,true,"resized four-button row stays within parent")
details:SetWidth(308);details.scripts.OnSizeChanged(details,308,502)
eq(navigation.width,74,"native size callback recalculates footer")
-- Capability/protection checks do not partially rearrange another native panel.
local guarded=detailsFrame();guarded.TrackButton.protected=true
QuestMapFrame.DetailsFrame=guarded;event.scripts.OnEvent(event,"ADDON_LOADED","OtherAddon")
eq(guarded.AbandonButton.width,105,"protected sibling prevents any native geometry changes")
eq(NS.QuestMapNavigationButton,sameButton,"protected details never creates a second navigation button")
QuestMapFrame.DetailsFrame=details;event.scripts.OnEvent(event,"PLAYER_LOGIN")
eq(NS.QuestMapNavigationButton,sameButton,"original details controls still reuse original button")

-- Candidate popup: navigation always goes through the resolver's current-state guard.
local selectedCalls,selectedQuest,selectedTarget=0,nil,nil
local reject=false
NS.Start=function()error("QuestUI must not bypass SelectQuestTarget")end
NS.SelectQuestTarget=function(qid,target)
    selectedCalls=selectedCalls+1;selectedQuest,selectedTarget=qid,target
    if reject then return false,"任务状态已经变化，请重新选择。"end
    return true
end
local targets={}
for i=1,8 do targets[i]={id="candidate:"..i,name="目标"..i,mapID=1455,x=.1*i,y=.5,zone="铁炉堡",kind=i==1 and "npc"or(i==2 and "item"or"turnin"),objectiveText="对应任务要求",note="坐标来源说明"}end
targets[9]={id="unknown",name="待核实的地点",kind="location",objectiveText="需要任务物品",note="没有可靠坐标"}
eq(NS.ShowQuestTargets(1,"任务一",targets),true,"popup accepts quest candidate list")
local ui=NS.QuestUI
eq(MyForeverNavigatorQuestTargets.controls,ui,"popup controls exposed on named frame")
eq(ui.frame:IsShown(),true,"popup visible")
eq(ui.rows[1].target,targets[1],"first candidate page")
eq(ui.rows[6].target,targets[6],"six candidates per page")
eq(ui.rows[1].kind.text,"任务 NPC","NPC type labeled")
eq(ui.rows[2].kind.text,"物品来源","item-source type labeled")
eq(ui.rows[3].kind.text,"交付地点","turn-in object or NPC labeled as place")
eq(ui.rows[1].summary.text:sub(1,#"铁炉堡"),"铁炉堡","candidate summary puts location before progress")
ui.rows[3].target.kind="area";NS.ShowQuestTargets(1,"任务一",targets)
eq(ui.rows[3].kind.text,"任务地点","native area type labeled")
eq(ui.previous.enabled,false,"first page disables previous")
eq(ui.next.enabled,true,"second page available")
ui.next:Click();eq(ui.rows[1].target,targets[7],"second page first candidate")
eq(ui.rows[3].enabled,false,"candidate with no coordinates cannot navigate")
contains(ui.rows[3].summary.text,"暂无可靠坐标","missing coordinates explicit")
local previousCalls=selectedCalls;ui.rows[3]:Click();eq(selectedCalls,previousCalls,"missing point never reaches navigation")
eq(ui.rows[4]:IsShown(),false,"unused candidate rows hidden")
eq(ui.next.enabled,false,"last page disables next")
reject=true;ui.rows[1]:Click()
eq(ui.frame:IsShown(),true,"stale candidate rejection keeps popup open")
contains(ui.message.text,"任务状态已经变化","resolver rejection shown")
eq(selectedQuest,1,"resolver receives originating quest ID")
eq(selectedTarget,targets[7],"resolver receives selected candidate")
reject=false;ui.rows[1]:Click();eq(ui.frame:IsShown(),false,"successful resolver selection closes popup")
eq(NS.ShowQuestTargets(0,"invalid",targets),false,"invalid quest ID cannot show popup")
eq(NS.ShowQuestTargets(2,"暂无地点",{},"任务目标暂无可靠坐标。"),true,"empty lookup has useful popup")
for _,row in ipairs(ui.rows)do eq(row:IsShown(),false,"no fake targets for empty lookup")end
eq(ui.map.enabled,true,"native quest-map action retained for empty lookup")
local nativeMapQuest
QuestMapFrame_OpenToQuestDetails=function(qid)nativeMapQuest=qid end
ui.map:Click();eq(nativeMapQuest,2,"empty lookup opens original quest map")
eq(ui.frame:IsShown(),false,"native map is not covered by popup")
QuestMapFrame_OpenToQuestDetails=nil
local logOpened,detailQuest=0,nil
OpenQuestLog=function()logOpened=logOpened+1 end
QuestMapFrame_ShowQuestDetails=function(qid)detailQuest=qid end
NS.ShowQuestTargets(1,"备用地图",{})
ui.map:Click();eq(logOpened,1,"fallback opens native quest log")
eq(detailQuest,1,"fallback shows correct quest details")
OpenQuestLog,QuestMapFrame_ShowQuestDetails=nil,nil
NS.ShowQuestTargets(1,"无地图接口",{});ui.map:Click()
eq(ui.frame:IsShown(),true,"map API failure leaves explanatory popup")
contains(ui.message.text,"原生任务地图暂不可用","map API fallback fails honestly")
NS.ShowQuestTargets(1,"长说明",targets,string.rep("任务资料尚未给出可靠坐标。",12))
local bottom=-ui.rows[6].point[3]+ui.rows[6].height
local hintTop=ui.frame.height-54-ui.hint.height
eq(bottom+6<=hintTop,true,"long message does not overlap rows and footer hint")
eq(ui.frame.height>540,true,"long explanation expands popup")
NS.HideQuestTargets();eq(ui.frame:IsShown(),false,"explicit hide closes popup")
eq(targets[1].name,"目标1","popup does not mutate candidate records")
print("Navigator quest UI: "..checks.." behavior checks passed (simulated)")
