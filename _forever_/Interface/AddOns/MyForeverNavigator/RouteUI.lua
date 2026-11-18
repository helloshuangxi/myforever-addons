local _, NS = ...
local ui, state, candidates, mapCount, page, catalogue
local zones, byMap, selectedMap, choosingMap
local pageSize = 5
local pendingStatus, notice, submittedQuestion
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
    ui.question:SetText(submittedQuestion and ("我的问题 · "..submittedQuestion) or "")
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
        ui.title:SetText(pendingStatus == "pending" and "交给我的无限客户端" or pendingStatus == "error" and "问路需要处理" or "问任务或目的地")
        ui.detail:SetText(notice or "例如「这个任务怎么做」或「我要去铁炉堡」。复杂问题可交给我的无限客户端，已确认的路线可直接复用。")
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
    local waiting = pendingStatus == "pending"
    ui.copy:SetShown(waiting)
    ui.exchange.holder:SetShown(waiting)
    ui.outgoing.holder:SetShown(waiting)
    ui.cancel:SetShown(pendingStatus == "pending" or pendingStatus == "error")
    ui.search.label:SetText(pendingStatus == "error" and "重新提问" or "问路")
end

local function begin(input, preferredID)
    NS.CancelClientQuestion()
    submittedQuestion=NS.CleanText(input,180)
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
        notice = "复制下方问题码，在客户端「游戏问路」点「粘贴问题并询问」。答复就绪后，复制并粘到下框。"
    end
    useState(nextState)
    if state and not state.plan then refreshCandidates() end
    NS.RefreshRoutePlanner()
end

local function ask(input,forceClient)
    ui.query:ClearFocus()
    local cached = NS.LookupClientRouteState(input) or (not forceClient and NS.KnownPlaceRoute(input))
    if cached then
        if MyForeverNavigatorOutbox then NS.CancelClientQuestion() end
        submittedQuestion, pendingStatus, notice = cached.question or input, nil, nil
        useState(cached)
        if not state.plan then refreshCandidates() end
        NS.RefreshRoutePlanner()
        return
    end
    local request, err = NS.SubmitClientQuestion(input, nil, pendingStatus == "error")
    if not request then
        NS.RefreshRoutePlanner()
        ui.detail:SetText(err)
        return
    end
    ui.outgoing:SetText(NS.ExportClientQuestion() or "")
    request.delivery="clipboard"
    submittedQuestion=request.question
    ui.exchange:SetText("")
    receive()
end

function NS.RestoreClientQuestion()
    local request = MyForeverNavigatorOutbox
    if not ui or type(request) ~= "table" or not request.id or NS.ClientQuestionStatus() == "none" then return end
    NS.ToggleUI(true)
    ui.open("route")
    submittedQuestion=request.question
    ui.outgoing:SetText(NS.ExportClientQuestion() or "")
    ui.query:SetText(request.question)
    receive()
end

-- Quest-log data can arrive after the first world-entry event.
function NS.RefreshClientQuestion()
    local box=MyForeverNavigatorOutbox
    if not ui or not ui.query:IsVisible() or type(box)~="table" or box.question~=submittedQuestion then return end
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
            ask(input,askClient)
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

    end)
    ui.query:SetScript("OnEnterPressed",submit)
    ui.search=action("问路",80,width-166,0,submit,"primary")
    ui.localSearch=action("本地查找",80,width-80,0,function()
        ui.query:ClearFocus();begin(ui.query:GetText() or "")
    end,"quiet")
    ui.zones=action("按地图选",82,width-82,83,function()
        if selectedMap or choosingMap then selectedMap,choosingMap=nil,false else choosingMap=true end
        page=1;NS.RefreshRoutePlanner()
    end,"quiet")
    ui.question=caption(width,48,34,widgets.colors.title)
    ui.question:SetWordWrap(true)
    ui.title=caption(width,28,84,widgets.colors.title,"GameFontNormalLarge")
    ui.detail=caption(width,64,113,widgets.colors.muted)
    for i=1,pageSize do
        local row=action("",width,0,179+(i-1)*34,function(self)
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
        row:SetHeight(32);row.label:SetHeight(30);row.label:SetWordWrap(true);row.label:SetJustifyH("LEFT")
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
            pendingStatus,notice=nil,nil
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
    ui.outgoing=widgets.input(parent,width-136,"问题码",136,-180,true)
    ui.outgoing:SetMaxLetters(36864)
    ui.exchange=widgets.input(parent,width,"把客户端答复粘贴在这里",0,-222,true)
    ui.exchange:SetMaxLetters(36864)
    local function importReply()
        local ok,why=NS.ImportClientReply(ui.exchange:GetText() or "")
        if not ok then ui.detail:SetText(why);return end
        ui.exchange:ClearFocus()
        ui.exchange:SetText("")
        receive()
    end
    ui.exchange:SetScript("OnEnterPressed",importReply)
    ui.exchange:SetScript("OnTextChanged",function(self)
        local value=self:GetText() or ""
        if self.hint then self.hint:SetShown(value=="") end
        if value:sub(1,6)=="MFNA1~" and value:sub(-4)=="~END" then importReply() end
    end)
    ui.copy=action("选中问题码",124,0,180,function()
        local code=NS.ExportClientQuestion()
        if not code then return end
        ui.outgoing:SetText(code)
        ui.outgoing:SetFocus()
        ui.outgoing:HighlightText()
        ui.detail:SetText("按 Ctrl+C（Mac 可用 ⌘C）复制。客户端答复后，粘贴到下方答复框。")
    end,"primary")
    ui.cancel=action("取消问题",100,width-100,412,function()
        NS.CancelClientQuestion()
        submittedQuestion,pendingStatus,notice=nil,nil,nil
        ui.exchange:ClearFocus();ui.exchange:SetText("")
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
