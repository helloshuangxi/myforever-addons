local _, NS = ...
local ui, state, candidates, mapCount, page, catalogue
local zones, byMap, selectedMap, choosingMap
local pageSize = 5
local pendingStatus, notice, submittedID
local function useState(nextState)
    state, candidates, page = nextState, {}, 1
end
local function stepLine(step, index)
    return string.format("%d. %s", index, step.label or step.id)
end

function NS.RouteStepSummary(plan, start, count)
    local lines = {}
    for i = start, math.min(start + count - 1, #plan.steps) do
        lines[#lines+1] = stepLine(plan.steps[i], i)
    end
    return table.concat(lines, "\n\n")
end

local function refreshCandidates()
    candidates, mapCount = NS.GetRouteCandidates(state)
    zones, byMap, selectedMap, choosingMap = {}, {}, nil, false
    for _, point in ipairs(candidates) do
        local group = byMap[point.mapID]
        if not group then
            group = {mapID=point.mapID, name=point.zone or tostring(point.mapID), points={}}
            byMap[point.mapID] = group
            zones[#zones+1] = group
        end
        group.points[#group.points+1] = point
    end
    catalogue = NS.GetCatalogPoints and NS.GetCatalogPoints()
    page = 1
end

function NS.RefreshRoutePlanner()
    if not ui or not ui.ground then return end
    if not state then selectedMap,choosingMap=nil,false end
    if state and not state.plan and NS.GetCatalogPoints and NS.GetCatalogPoints() ~= catalogue then refreshCandidates() end
    local plan = state and state.plan
    local group = selectedMap and byMap and byMap[selectedMap]
    local list = state and (choosingMap and zones or (group and group.points) or candidates) or {}
    local count = plan and #plan.steps or #list
    local canGroup = state and not plan and (mapCount or 0)>1
    ui.zones:SetShown(canGroup and true or false)
    ui.zones.label:SetText((choosingMap or group) and "全部地点" or "按地图选")
    ui.title:SetWidth(ui.width - (canGroup and 90 or 0))
    local pages = math.max(1, math.ceil(count / pageSize))
    page = math.max(1, math.min(page or 1, pages))
    if state then
        if plan then
            ui.title:SetText(((state.source=="cache" or state.source=="client-cache") and "已记住的路线" or "路线预览") .. " · " .. #plan.steps .. " 步")
            local detail=state.message or ""
            if plan.note and plan.note ~= "" then detail=detail ~= "" and detail.."\n"..plan.note or plan.note end
            ui.detail:SetText(detail)
        else
            ui.title:SetText(string.format("选择第 %d / %d 站 · %s", state.index, #state.terms, state.terms[state.index]))
            local instruction=state.clientSteps and state.clientSteps[state.index] and state.clientSteps[state.index].text
            local detail
            if choosingMap then detail="选择地图查看该区域的地点。"
            elseif group then detail=string.format("%s · %d 个候选地点",group.name,#group.points)
            elseif count==0 then detail="本地暂时找不到这一站。请检查任务进度、Questie 是否就绪，或换一个更具体的问法。"
            else detail=string.format("找到 %d 个地点，分布在 %d 张地图。",count,mapCount) end
            if state.candidateNotice and not choosingMap and not group then detail=state.candidateNotice end
            ui.detail:SetText(instruction and instruction ~= "" and instruction.."\n"..detail or detail)
        end
    else
        ui.title:SetText(pendingStatus == "pending" and "等待客户端答复" or pendingStatus == "error" and "问路需要处理" or "问任务或目的地")
        ui.detail:SetText(notice or "例如「这个任务怎么做」或「我要去铁炉堡」。在我的无限客户端开启游戏问路后即可提问。")
    end
    for i,row in ipairs(ui.rows) do
        local k = (page-1)*pageSize+i
        local entry = plan and plan.steps[k] or (not plan and list[k])
        row:SetShown(entry~=nil)
        row.pointID, row.mapKey = nil,nil
        if entry and plan then
            row.label:SetText(stepLine(entry,k));row:SetEnabled(false);row:SetAlpha(1)
        elseif entry and choosingMap then
            row.mapKey=entry.mapID;row:SetEnabled(true)
            row.label:SetText(entry.name .. "   ·   " .. #entry.points .. " 个地点")
        elseif entry then
            row.pointID=entry.id;row:SetEnabled(true)
            local where=entry.zone or tostring(entry.mapID)
            local info=entry.distance and string.format(" · 直线 %.0f 米",entry.distance) or ""
            row.label:SetText((entry.name or entry.id).."   ·   "..where..info)
        end
    end
    ui.prev:SetShown(pages>1);ui.more:SetShown(pages>1);ui.counter:SetShown(pages>1)
    ui.prev:SetEnabled(page>1);ui.more:SetEnabled(page<pages);ui.counter:SetText(page.." / "..pages)
    ui.start:SetShown(plan~=nil)
    ui.ground:SetShown(plan and (plan.hasUnconfirmedFlights or state.noUnconfirmedFlights) or false)
    ui.ground.label:SetText(state and state.noUnconfirmedFlights and "允许待开航点" or "避开待开航点")
    ui.repick:SetShown(state~=nil and ((state.index or 1)>1 or plan~=nil))
    ui.reload:SetShown(pendingStatus == "pending")
    local box = MyForeverNavigatorOutbox
    ui.reload.label:SetText(box and submittedID and box.id == submittedID and "重载发送" or "重载接收")
    ui.cancel:SetShown(pendingStatus == "pending" or pendingStatus == "error")
    ui.search.label:SetText(pendingStatus == "error" and "重新提问" or "问客户端")
end

local function begin(input, preferredID)
    local nextState, reason
    if preferredID then
        local plan
        plan,reason=NS.BuildRoute({preferredID})
        if plan then nextState={terms={input},ids={preferredID},index=2,source="selected",plan=plan} end
    else
        nextState,reason=NS.NewRouteQuery(input)
    end
    state,candidates,page=nextState,{},1
    pendingStatus, notice = nil, nil
    if state and not state.plan then refreshCandidates() end
    NS.RefreshRoutePlanner()
    if reason then ui.detail:SetText(reason) end
end

local function receive()
    local status, message = NS.ClientQuestionStatus()
    local nextState, reason
    if status == "ready" then
        nextState, reason = NS.BuildClientRouteState()
        if not nextState then status = "error" end
    end
    pendingStatus = status ~= "ready" and status or nil
    notice = reason or message
    if status == "pending" and message ~= "正在等待游戏载入任务日志。" then
        notice = submittedID and MyForeverNavigatorOutbox.id == submittedID
            and "点「重载发送」保存问题。请保持我的无限客户端开启。"
            or "请在我的无限客户端查看进度。客户端显示已答复后，点「重载接收」。"
    end
    useState(nextState)
    if state and not state.plan then refreshCandidates() end
    NS.RefreshRoutePlanner()
end

local function ask(input)
    ui.query:ClearFocus()
    local cached = NS.LookupClientRouteState(input)
    if cached then
        if MyForeverNavigatorOutbox then NS.CancelClientQuestion() end
        submittedID, pendingStatus, notice = nil, nil, nil
        useState(cached)
        if not state.plan then refreshCandidates() end
        NS.RefreshRoutePlanner()
        return
    end
    local oldID = MyForeverNavigatorOutbox and MyForeverNavigatorOutbox.id
    local request, err = NS.SubmitClientQuestion(input, nil, pendingStatus == "error")
    if not request then
        notice = err
        useState(nil)
        NS.RefreshRoutePlanner()
        return
    end
    if request.id ~= oldID then submittedID = request.id end
    receive()
end

function NS.RestoreClientQuestion()
    local request = MyForeverNavigatorOutbox
    if not ui or type(request) ~= "table" or not request.id or NS.ClientQuestionStatus() == "none" then return end
    NS.ToggleUI(true)
    ui.open("route")
    ui.query:SetText(request.question)
    receive()
end

-- Quest-log data can arrive after the first world-entry event.
function NS.RefreshClientQuestion()
    local box=MyForeverNavigatorOutbox
    if not ui or not ui.query:IsVisible() or type(box)~="table" or box.question~=ui.query:GetText() then return end
    if pendingStatus then
        if NS.ClientQuestionStatus()~=pendingStatus then receive() end
    elseif state and state.clientSteps and not state.plan and #(candidates or {})==0 then
        refreshCandidates()
        NS.RefreshRoutePlanner()
    end
end

function NS.OpenRoutePlanner(input, preferredID, askClient)
    NS.ToggleUI(true)
    if not ui then return end
    ui.open("route")
    if input and input~="" then
        ui.query:SetText(input)
        if preferredID or (not askClient and (input:match("^MFN%d") or input:match("^/mynav +route +MFN%d"))) then
            begin(input,preferredID)
        else
            ask(input)
        end
    elseif preferredID then
        local point=NS.GetPoint(preferredID)
        if point then ui.query:SetText(point.name);begin(point.name,preferredID) end
    end
end

function NS.CreateRoutePlanner(parent, widgets)
    local width=parent:GetWidth()
    ui={open=widgets.open, rows={},width=width}
    NS.RoutePlannerUI=ui
    local function caption(w,h,y,color,font)
        local f=widgets.label(parent,w,h,font or "GameFontHighlight",color)
        f:SetPoint("TOPLEFT",0,-y)
        return f
    end
    local function action(text,w,x,y,fn,kind)
        local b=widgets.button(parent,text,w,30,fn,kind)
        b:SetPoint("TOPLEFT",x,-y)
        return b
    end
    local function submit()
        ui.query:ClearFocus()
        ask(ui.query:GetText() or "")
    end
    ui.query=widgets.input(parent,width-172,"哪个任务怎么做，或想去哪里？",0,0,true)
    ui.query:SetMaxLetters(254)
    ui.query:SetScript("OnTextChanged",function(self)
        local value=self:GetText() or ""
        if self.hint then self.hint:SetShown(value=="") end
        if ui.detail then
            useState(nil)
            pendingStatus,notice=nil,nil
            NS.RefreshRoutePlanner()
        end
    end)
    ui.query:SetScript("OnEnterPressed",submit)
    ui.search=action("问客户端",80,width-166,0,submit,"primary")
    ui.localSearch=action("本地查找",80,width-80,0,function()
        ui.query:ClearFocus();begin(ui.query:GetText() or "")
    end,"quiet")
    ui.zones=action("按地图选",82,width-82,52,function()
        if selectedMap or choosingMap then selectedMap,choosingMap=nil,false else choosingMap=true end
        page=1;NS.RefreshRoutePlanner()
    end,"quiet")
    ui.title=caption(width,28,58,widgets.colors.title,"GameFontNormalLarge")
    ui.detail=caption(width,56,94,widgets.colors.muted)
    for i=1,pageSize do
        local row=action("",width,0,156+(i-1)*39,function(self)
            if self.mapKey then
                selectedMap,choosingMap,page=self.mapKey,false,1
                NS.RefreshRoutePlanner();return
            end
            if not self.pointID then return end
            local ok,err=NS.ChooseRouteCandidate(state,self.pointID)
            if not ok then ui.detail:SetText(err);return end
            if not state.plan then refreshCandidates() else page=1 end
            NS.RefreshRoutePlanner()
        end)
        row:SetHeight(36);row.label:SetHeight(32);row.label:SetWordWrap(true);row.label:SetJustifyH("LEFT")
        ui.rows[i]=row
    end
    ui.prev=action("上一页",72,0,355,function()page=page-1;NS.RefreshRoutePlanner()end,"quiet")
    ui.more=action("下一页",72,width-72,355,function()page=page+1;NS.RefreshRoutePlanner()end,"quiet")
    ui.counter=caption(width-150,20,361,widgets.colors.muted)
    ui.counter:ClearAllPoints();ui.counter:SetPoint("TOPLEFT",75,-361);ui.counter:SetJustifyH("CENTER")
    ui.start=action("按此路线导航",144,0,412,function()
        local ok,err=NS.ConfirmRouteQuery(state)
        if not ok then ui.detail:SetText(err);return end
        if state.clientSteps then
            useState(nil)
            submittedID,pendingStatus,notice=nil,nil,nil
            ui.query:SetText("")
        end
        NS.RefreshHUD();ui.open("navigation")
    end,"primary")
    ui.repick=action("重选地点",100,width-100,412,function()
        if not state then return end
        if state.clientSteps then NS.ResetClientRouteState(state)
        else state.index,state.plan,state.ids,state.source=1,nil,{},state.source=="cache" and "local" or state.source end
        state.noUnconfirmedFlights=nil
        refreshCandidates();NS.RefreshRoutePlanner()
    end,"quiet")
    ui.reload=action("重载发送",124,0,412,function()
        if NS.Call(InCombatLockdown) then ui.detail:SetText("请在战斗结束后重载。");return end
        local reload = C_UI and C_UI.Reload or ReloadUI
        if reload then reload() else ui.detail:SetText("请在游戏内输入 /reload。") end
    end,"primary")
    ui.cancel=action("取消问题",100,width-100,412,function()
        NS.CancelClientQuestion()
        submittedID,pendingStatus,notice=nil,nil,nil
        useState(nil);NS.RefreshRoutePlanner()
    end,"quiet")
    ui.ground=action("避开待开航点",132,154,412,function()
        if not state or not state.plan then return end
        local avoid=not state.noUnconfirmedFlights
        local plan,err
        if state.clientSteps then plan,err=NS.RebuildClientPlan(state,avoid)
        else plan,err=NS.BuildRoute(state.ids,nil,{noUnconfirmedFlights=avoid}) end
        if not plan then ui.detail:SetText(err);return end
        state.plan,state.noUnconfirmedFlights,page=plan,avoid,1
        NS.RefreshRoutePlanner()
    end,"quiet")
    NS.RefreshRoutePlanner()
end
