local _, NS = ...
-- Shared layout hooks (grid while dragging, snap on release, /myui tags).
local function mfLayout(name, ...)
    local S = rawget(_G, "MyForeverStyle")
    local fn = type(S) == "table" and rawget(S, name)
    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        return ok and result or nil
    end
end

local call, number = NS.Call, NS.Number
local DOUBLE_CLICK_SECONDS, CURSOR_TOLERANCE, PAGE_SIZE = 0.35, 12, 6
local pending, eventFrame, ui
local logUpdateHooked = false
local trackerHooks = setmetatable({}, {__mode="k"})
local titleWrappers = setmetatable({}, {__mode="k"})
local detailsHooks, detailsStates = {}, setmetatable({}, {__mode="k"})
local refreshDetailsNavigation
local Style = MyForeverStyle
local function token(name, alpha) local r, g, b = Style.Color(name); return {r, g, b, alpha} end
local colors = {surface=token("outer",Style.alpha.window), raised=token("surface",1),
    border=token("line",1), gold=token("text"), white=token("text"), muted=token("muted")}
local kindNames = {npc="任务 NPC",item="物品来源",object="任务物件",location="任务地点",area="任务地点",
    turnin="交付地点",turnIn="交付地点",["turn-in"]="交付地点",finish="交付地点",giver="任务 NPC"}

local function clean(value, limit)
    return NS.CleanText(type(value)=="string" and value or "",limit or 180)
end
local function printMessage(message)
    if type(message)=="string" and message~="" then call(NS.Print,message) end
end
local function validQuestID(id)
    return number(id) and id>0 and id%1==0
end
local function hasModifier()
    return call(IsShiftKeyDown)==true or call(IsControlKeyDown)==true or call(IsAltKeyDown)==true
        or call(IsMetaKeyDown)==true or call(IsModifiedClick,"QUESTWATCHTOGGLE")==true
        or call(IsModifiedClick,"CHATLINK")==true
end
local function resetClick()
    pending=nil
end
local function activeQuest(id)
    local getter=C_QuestLog and C_QuestLog.GetLogIndexForQuestID
    if type(getter)=="function" then
        local index=call(getter,id)
        if not number(index) or index<=0 then return false end
    end
    return call(C_QuestLog and C_QuestLog.IsQuestDisabledForSession,id)~=true
end
local function openQuestDeferred(questID)
    local function open()
        if not activeQuest(questID) then return end
        if type(NS.OpenQuestNavigation)~="function" then printMessage("任务导航尚未加载，请稍后再试。");return end
        local ok=pcall(NS.OpenQuestNavigation,questID)
        if not ok then printMessage("任务导航暂不可用，请稍后再试。") end
    end
    if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(0,open) else open() end
end

-- Tracker clicks use secure post-hooks; the journal titles below defer only
-- plain left clicks because their native first click hides the title list.
function NS.HandleQuestClick(questID, mouseButton, source)
    if mouseButton~="LeftButton" or hasModifier() or not validQuestID(questID) or not activeQuest(questID) then
        resetClick()
        return false
    end
    local now=call(GetTime)
    if not number(now) then resetClick();return false end
    local x,y=call(GetCursorPosition)
    if not number(x) or not number(y) then x,y=nil,nil end
    source=source or "quest"
    local previous=pending
    local elapsed=previous and (now-previous.time)
    local closeEnough=not (previous and previous.x and x) or ((x-previous.x)^2+(y-previous.y)^2<=CURSOR_TOLERANCE^2)
    if previous and previous.id==questID and previous.source==source and elapsed>=0 and elapsed<=DOUBLE_CLICK_SECONDS and closeEnough then
        resetClick()
        openQuestDeferred(questID)
        return true
    end
    pending={id=questID,source=source,time=now,x=x,y=y}
    return false
end

local function cancelTitleClick(state)
    state.token=state.token+1
    state.pending=nil
end
local function safeLogButton(button)
    return button and type(button.GetScript)=="function" and type(button.SetScript)=="function"
        and type(button.IsProtected)=="function" and call(button.IsProtected,button)==false
end
local function installTitleButton(button)
    if titleWrappers[button] or not safeLogButton(button) or call(InCombatLockdown)==true
        or not C_Timer or type(C_Timer.After)~="function" then return end
    local original=button:GetScript("OnClick")
    if type(original)~="function" then return end
    local state={original=original,token=0}
    titleWrappers[button]=state
    state.wrapper=function(self,mouseButton,...)
        local id=self.questID
        if mouseButton~="LeftButton" or hasModifier() or call(InCombatLockdown)==true
            or not safeLogButton(self) or not validQuestID(id) or not activeQuest(id) then
            cancelTitleClick(state)
            return original(self,mouseButton,...)
        end
        local now=call(GetTime)
        if not number(now) then cancelTitleClick(state);return original(self,mouseButton,...)end
        local x,y=call(GetCursorPosition)
        if not number(x) or not number(y)then x,y=nil,nil end
        local previous=state.pending
        local elapsed=previous and now-previous.time
        local closeEnough=not (previous and previous.x and x)or((x-previous.x)^2+(y-previous.y)^2<=CURSOR_TOLERANCE^2)
        if previous and previous.id==id and elapsed>=0 and elapsed<=DOUBLE_CLICK_SECONDS and closeEnough then
            cancelTitleClick(state)
            openQuestDeferred(id)
            return
        end
        cancelTitleClick(state)
        local token=state.token
        local extra={n=select("#",...),...}
        state.pending={id=id,time=now,x=x,y=y}
        local function finishSingleClick()
            if state.token~=token or not state.pending then return end
            if not safeLogButton(self) or self:GetScript("OnClick")~=state.wrapper or self.questID~=id or not activeQuest(id)
                or call(InCombatLockdown)==true or call(self.IsVisible or self.IsShown,self)==false then
                cancelTitleClick(state)
                return
            end
            -- Native handlers read modifier globals when invoked. A key pressed
            -- during the delay must not turn a plain click into tracking/chat.
            if hasModifier()then cancelTitleClick(state);return end
            cancelTitleClick(state)
            original(self,mouseButton,unpack(extra,1,extra.n))
        end
        C_Timer.After(DOUBLE_CLICK_SECONDS,finishSingleClick)
    end
    button:SetScript("OnClick",state.wrapper)
    if type(button.HookScript)=="function"then button:HookScript("OnHide",function()cancelTitleClick(state)end)end
end
local function installQuestLogButtons()
    if call(InCombatLockdown)==true then return end
    local pool=QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool or type(pool.EnumerateActive)~="function"then return end
    -- Once per native list rebuild or module load, never from OnUpdate. Pool
    -- acquisition rewrites questID; every delayed action revalidates that ID.
    for button in pool:EnumerateActive()do installTitleButton(button)end
end

local function tryHooks()
    if type(hooksecurefunc)~="function" then return end
    if not logUpdateHooked and type(QuestLogQuests_Update)=="function" then
        local ok=pcall(hooksecurefunc,"QuestLogQuests_Update",installQuestLogButtons)
        if ok then logUpdateHooked=true end
    end
    installQuestLogButtons()
    for _,name in ipairs({"QuestMapFrame_ShowQuestDetails","QuestMapFrame_UpdateQuestDetailsButtons"})do
        if not detailsHooks[name] and type(_G[name])=="function"then
            local ok=pcall(hooksecurefunc,name,function()refreshDetailsNavigation()end)
            if ok then detailsHooks[name]=true end
        end
    end
    refreshDetailsNavigation()
    for _, name in ipairs({"QuestObjectiveTracker","CampaignQuestObjectiveTracker"}) do
        local module=_G[name]
        if module and not trackerHooks[module] and type(module.OnBlockHeaderClick)=="function" then
            local ok=pcall(hooksecurefunc,module,"OnBlockHeaderClick",function(self,block,mouseButton)
                NS.HandleQuestClick(block and block.id,mouseButton,self)
            end)
            if ok then trackerHooks[module]=true end
        end
    end
end

local function label(parent,width,height,font,color)
    local text=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    text:SetSize(width,height);text:SetJustifyH("LEFT");text:SetJustifyV("TOP");text:SetWordWrap(true)
    text:SetTextColor(unpack(color or colors.white));text:SetSpacing(3)
    return text
end
local function backdrop(frame,fill)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    frame:SetBackdropColor(unpack(fill or colors.raised));frame:SetBackdropBorderColor(unpack(colors.border))
end
local function button(parent,caption,width,height,callback)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
    b:SetSize(width,height);backdrop(b)
    b.label=label(b,width-8,height-4,"GameFontNormalSmall",colors.gold)
    b.label:SetPoint("CENTER");b.label:SetJustifyH("CENTER");b.label:SetJustifyV("MIDDLE");b.label:SetText(caption)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8");b:GetHighlightTexture():SetVertexColor(.9,.8,.6,.12)
    b:SetScript("OnClick",callback)
    return b
end
local function currentDetailsFrame()
    return QuestMapFrame and (QuestMapFrame.DetailsFrame or (QuestMapFrame.QuestsFrame and QuestMapFrame.QuestsFrame.DetailsFrame))
end
local function detailQuestID(details)
    if type(QuestMapFrame_GetDetailQuestID)=="function"then return call(QuestMapFrame_GetDetailQuestID)end
    return details and details.questID
end
local function safeDetailsRegion(region)
    return region and type(region.IsProtected)=="function" and call(region.IsProtected,region)==false
        and type(region.SetWidth)=="function" and type(region.SetPoint)=="function" and type(region.ClearAllPoints)=="function"
end
refreshDetailsNavigation=function()
    local details=currentDetailsFrame()
    if not details then return end
    local state=detailsStates[details]
    if call(InCombatLockdown)==true then
        if state then state.navigation:SetEnabled(false)end
        return
    end
    local native={details.AbandonButton,details.ShareButton,details.TrackButton}
    if not safeDetailsRegion(details) or type(details.HookScript)~="function"
        or not details.AbandonButton or not details.ShareButton or not details.TrackButton then return end
    for _,region in ipairs(native)do if not safeDetailsRegion(region)then return end end
    local width=call(details.GetWidth,details)
    if not number(width)or width<268 then
        if state then state.navigation:Hide()end
        return
    end
    if not state then
        state={frame=details}
        local navigation=button(details,"导航",74,22,function()
            local id=detailQuestID(details)
            if currentDetailsFrame()~=details or call(details.IsVisible or details.IsShown,details)~=true
                or not validQuestID(id)or not activeQuest(id)then
                refreshDetailsNavigation()
                return
            end
            openQuestDeferred(id)
        end)
        state.navigation=navigation
        detailsStates[details]=state
        NS.QuestMapNavigationButton=navigation
        if ui then ui.detailNavigationButton,ui.detailsFrame=navigation,details end
        details:HookScript("OnShow",function()refreshDetailsNavigation()end)
        details:HookScript("OnHide",function()navigation:Hide()end)
        details:HookScript("OnSizeChanged",function()refreshDetailsNavigation()end)
    end
    -- The native 308px footer already uses all its width. Four equal cells
    -- reuse that same 22px strip, preserving the scroll/rewards content above.
    local gap=4
    local cell=math.floor((width-gap*3)/4)
    local left=(width-(cell*4+gap*3))/2
    for i,region in ipairs(native)do
        region:SetWidth(cell)
        region:ClearAllPoints()
        if i==1 then region:SetPoint("BOTTOMLEFT",details,"BOTTOMLEFT",left,-2)
        else region:SetPoint("LEFT",native[i-1],"RIGHT",gap,0)end
    end
    local navigation=state.navigation
    navigation:SetSize(cell,22);navigation.label:SetSize(cell-8,18)
    navigation:ClearAllPoints();navigation:SetPoint("LEFT",native[3],"RIGHT",gap,0)
    local id=detailQuestID(details)
    navigation:SetEnabled(validQuestID(id)and activeQuest(id)or false)
    navigation:SetShown(call(details.IsShown,details)==true)
end
local function openNativeMap()
    if not ui or not validQuestID(ui.questID) then return false,"任务已失效，请重新双击任务。" end
    if type(QuestMapFrame_OpenToQuestDetails)=="function" then
        local ok=pcall(QuestMapFrame_OpenToQuestDetails,ui.questID)
        if ok then return true end
    elseif type(OpenQuestLog)=="function" and type(QuestMapFrame_ShowQuestDetails)=="function" then
        local opened=pcall(OpenQuestLog)
        if opened and pcall(QuestMapFrame_ShowQuestDetails,ui.questID) then return true end
    end
    return false,"原生任务地图暂不可用，请先打开游戏任务日志。"
end

local render
local function setMessage(message)
    ui.message:SetText(clean(message,450))
end
local function createPopup()
    if ui or type(CreateFrame)~="function" or not UIParent then return end
    local frame=CreateFrame("Frame","MyForeverNavigatorQuestTargets",UIParent,"BackdropTemplate")
    frame:SetSize(560,540);frame:SetPoint("CENTER");frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true);frame:SetMovable(true);frame:EnableMouse(true);backdrop(frame,colors.surface)
    -- 星辉 window treatment (corners, motion, sounds) and console hints.
    if Style.Panel then Style.Panel(frame,"popup") end
    if Style.TitleRule then Style.TitleRule(frame,18,nil,240,60) end
    if Style.HintBar then Style.HintBar(frame,{{"左键","选择"},{"Esc","关闭"}},"/myui 摆放面板") end
    ui={frame=frame,rows={},targets={},page=1}
    NS.QuestUI=ui
    frame.controls=ui
    local drag=CreateFrame("Frame",nil,frame)
    drag:SetPoint("TOPLEFT");drag:SetPoint("TOPRIGHT",-36,0);drag:SetHeight(58)
    drag:EnableMouse(true);drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function()frame:StartMoving();mfLayout("BeginDrag",frame)end)
    drag:SetScript("OnDragStop",function()frame:StopMovingOrSizing();mfLayout("SnapToGrid",frame)end)
    mfLayout("RegisterLayout",frame,"世界向导 · 任务目标")
    ui.title=label(frame,496,44,"GameFontNormalLarge",colors.gold);ui.title:SetPoint("TOPLEFT",18,-14)
    if Style.SetType then Style.SetType(ui.title,"title","titleText") end
    ui.message=label(frame,524,44,"GameFontHighlightSmall",colors.muted);ui.message:SetPoint("TOPLEFT",18,-68)
    ui.close=button(frame,"×",24,24,function()NS.HideQuestTargets()end);ui.close:SetPoint("TOPRIGHT",-6,-6)
    for i=1,PAGE_SIZE do
        local row=CreateFrame("Button",nil,frame,"BackdropTemplate")
        row:SetSize(528,50);backdrop(row)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8");row:GetHighlightTexture():SetVertexColor(.7,.9,.85,.1)
        if type(row.SetMotionScriptsWhileDisabled)=="function" then row:SetMotionScriptsWhileDisabled(true) end
        row.name=label(row,390,20,"GameFontNormal",colors.white);row.name:SetPoint("TOPLEFT",10,-6);row.name:SetWordWrap(false)
        row.kind=label(row,100,18,"GameFontHighlightSmall",colors.muted);row.kind:SetPoint("TOPRIGHT",-10,-7);row.kind:SetJustifyH("RIGHT");row.kind:SetWordWrap(false)
        row.summary=label(row,508,18,"GameFontHighlightSmall",colors.muted);row.summary:SetPoint("TOPLEFT",10,-29);row.summary:SetWordWrap(false)
        row:SetScript("OnClick",function(self)
            local target=self.target
            if not target or not NS.ValidPoint(target) then return end
            if type(NS.SelectQuestTarget)~="function" then setMessage("任务目标尚未就绪，请重新双击任务。");render();return end
            local ok,selected,reason=pcall(NS.SelectQuestTarget,ui.questID,target)
            if not ok or selected~=true then
                setMessage(type(reason)=="string" and reason or "任务目标已变化，请重新双击任务后选择。")
                render()
                return
            end
            NS.HideQuestTargets()
        end)
        row:SetScript("OnEnter",function(self)
            if not self.target or not GameTooltip then return end
            local target=self.target
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(clean(target.name,180))
            if target.objectiveText then GameTooltip:AddLine(clean(target.objectiveText,360),.92,.94,.95,true) end
            if target.note then GameTooltip:AddLine(clean(target.note,450),.7,.76,.8,true) end
            if NS.ValidPoint(target) then
                GameTooltip:AddLine(string.format("%s · %.1f, %.1f",target.zone or "目标地图",target.x*100,target.y*100),.94,.78,.48,true)
            else GameTooltip:AddLine("暂无可靠坐标，可查看原生任务地图。",.94,.78,.48,true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave",function(self)
            if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
        end)
        ui.rows[i]=row
    end
    ui.previous=button(frame,"上一页",78,28,function()ui.page=math.max(1,ui.page-1);render()end)
    ui.previous:SetPoint("BOTTOMLEFT",16,16)
    ui.next=button(frame,"下一页",78,28,function()
        ui.page=math.min(math.max(1,math.ceil(#ui.targets/PAGE_SIZE)),ui.page+1);render()
    end)
    ui.next:SetPoint("BOTTOMLEFT",104,16)
    ui.pageLabel=label(frame,154,22,"GameFontHighlightSmall",colors.muted);ui.pageLabel:SetPoint("BOTTOMLEFT",198,19);ui.pageLabel:SetJustifyH("CENTER")
    ui.map=button(frame,"原生任务地图",174,28,function()
        local ok,reason=openNativeMap()
        if ok then NS.HideQuestTargets()else setMessage(reason);render()end
    end)
    ui.map:SetPoint("BOTTOMRIGHT",-16,16)
    ui.hint=label(frame,528,32,"GameFontHighlightSmall",colors.muted);ui.hint:SetPoint("BOTTOMLEFT",16,54)
    ui.hint:SetText("选择目标后开始导航；没有可靠坐标的资料不会生成导航点。")
    UISpecialFrames=UISpecialFrames or {};table.insert(UISpecialFrames,"MyForeverNavigatorQuestTargets")
    frame:Hide()
end

render=function()
    if not ui then return end
    local maximum=math.max(1,math.ceil(#ui.targets/PAGE_SIZE))
    ui.page=math.max(1,math.min(maximum,ui.page))
    local messageHeight=math.max(36,ui.message:GetStringHeight() or 36)
    ui.message:SetHeight(messageHeight)
    local rowTop=80+messageHeight
    local height=math.max(540,rowTop+PAGE_SIZE*56+88)
    ui.frame:SetHeight(height)
    local scale=math.min(1,(UIParent:GetWidth()-30)/560,(UIParent:GetHeight()-30)/height)
    ui.frame:SetScale(math.max(.55,scale))
    for i,row in ipairs(ui.rows)do
        local target=ui.targets[(ui.page-1)*PAGE_SIZE+i]
        row.target=target;row:SetShown(target~=nil)
        row:ClearAllPoints();row:SetPoint("TOPLEFT",16,-rowTop-(i-1)*56)
        if target then
            local valid=NS.ValidPoint(target)
            row:SetEnabled(valid);row:SetAlpha(valid and 1 or .55)
            row.name:SetText(clean(target.name,180)~="" and clean(target.name,180) or "任务目标")
            row.kind:SetText(kindNames[target.kind] or "任务目标")
            local context=clean(target.objectiveText,240)
            local location=valid and string.format("%s %.1f, %.1f",target.zone or "地图",target.x*100,target.y*100) or "暂无可靠坐标"
            row.summary:SetText(context~="" and (location.." · "..context) or location)
        end
    end
    ui.previous:SetEnabled(ui.page>1);ui.next:SetEnabled(ui.page<maximum)
    ui.pageLabel:SetText(ui.page.." / "..maximum.." 页 · "..#ui.targets.." 项")
end

function NS.ShowQuestTargets(questID,title,targets,message)
    if not validQuestID(questID) then return false,"任务 ID 无效。" end
    createPopup()
    if not ui then return false,"任务导航窗口暂不可用。" end
    ui.questID,ui.page=questID,1
    ui.targets={}
    for _,target in ipairs(type(targets)=="table" and targets or {})do
        if type(target)=="table" then ui.targets[#ui.targets+1]=target end
    end
    local heading=clean(title,180)
    ui.title:SetText("任务导航 · "..(heading~="" and heading or "选择目标"))
    setMessage(message or (#ui.targets>0 and "按任务要求选择目标。点击有坐标的一项开始导航。" or "暂时没有可靠目标坐标。可以打开原生任务地图查看任务说明。"))
    render();ui.frame:Show()
    return true
end
function NS.HideQuestTargets()
    if ui then ui.frame:Hide()end
end
function NS.InitializeQuestUI()
    createPopup()
    tryHooks()
    if eventFrame or type(CreateFrame)~="function" then return end
    eventFrame=CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED");eventFrame:RegisterEvent("PLAYER_LOGIN");eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_ENTERING_WORLD"or event=="PLAYER_REGEN_DISABLED"then
            resetClick()
            for _,state in pairs(titleWrappers)do cancelTitleClick(state)end
        end
        tryHooks()
    end)
end
