local _, NS = ...
local MAX_STEPS, MAX_CHOICES, MAX_CACHE = 6, 24, 64

local function plain(value, limit)
    return type(value) == "string" and #value <= limit and value ~= "" and value == NS.CleanText(value, limit)
end
local function integer(id)
    return NS.Number(id) and id > 0 and id < 2147483647 and id % 1 == 0
end
local function requestID(value)
    return type(value) == "string" and #value <= 64 and value:match("^[A-Za-z0-9_%-]+$")
end
local function referenceKey(value)
    return type(value) == "string" and (value == "turnin" or value == "native" or value:match("^[a-z]+:%d+$"))
end
local function locale()
    return NS.CleanText(NS.Call(GetLocale), 12):match("^[A-Za-z]+$") or "zhCN"
end
local function questionKey(s)
    return s:gsub("[A-Z]", string.lower):gsub(" +", " ")
end
local function relativeQuestion(question)
    local q=question:lower()
    for _,term in ipairs({"最近","附近","离我","离这","就近","身边","周边","从这","从我",
        "当前位置","这里","这儿","nearest","closest","near me","nearby","from here","my location"}) do
        if q:find(term,1,true) then return true end
    end
    return false
end
-- Never cache the destination chosen for a relative question. Until the
-- desktop returns, privately correlate that one request to its point of origin.
local function originFor(question)
    if not relativeQuestion(question) then return "" end
    local p=NS.Call(NS.GetLocationContext) or {}
    local map=NS.Number(p.mapID) and p.mapID or NS.Call(C_Map and C_Map.GetBestMapForUnit,"player") or 0
    local faction=NS.CleanText(NS.Call(UnitFactionGroup,"player"),16)
    if not NS.Number(p.x) or not NS.Number(p.y) then return tostring(map).."/"..faction end
    return string.format("%d/%s/%.4f/%.4f",map,faction,p.x,p.y)
end
local function cleanQuestion(s)
    if type(s) ~= "string" then return end
    s = s:match("^ *(.-) *$")
    return plain(s, 180) and s or nil
end
local function stepsArray(rows, allowEmpty)
    if type(rows) ~= "table" then return false end
    local n, high = 0, 0
    for key in pairs(rows) do
        if not integer(key) or key > MAX_STEPS then return false end
        n, high = n + 1, math.max(high, key)
    end
    return n == high and (allowEmpty or n > 0)
end
local function copyRecord(row)
    if type(row) ~= "table" or not plain(row.question,180) or not plain(row.locale,12)
        or not (row.questID == 0 or integer(row.questID) and plain(row.signature,16)) or not stepsArray(row.steps) then return end
    local copy = {question=row.question, locale=row.locale, questID=row.questID, signature=row.signature, message=NS.CleanText(row.message,360), steps={}}
    for i,step in ipairs(row.steps) do
        if type(step) ~= "table" or not plain(step.text,180) then return end
        if step.kind == "quest" and integer(row.questID) and referenceKey(step.ref) then
            copy.steps[i] = {kind="quest", ref=step.ref, text=step.text}
        elseif step.kind == "place" and plain(step.term,120) then
            copy.steps[i] = {kind="place", term=step.term, text=step.text}
        else return end
    end
    return copy
end
function NS.NormalizeClientAI(old)
    local db = {serial=0, cache={}}
    if type(old) ~= "table" then return db end
    db.serial = integer(old.serial) and old.serial or 0
    local ctx = old.context
    if type(ctx) == "table" and requestID(ctx.id) and type(ctx.refs) == "table" then
        db.context = {id=ctx.id, refs={}, signature=NS.CleanText(ctx.signature,16), expired=ctx.expired==true,
            wasActive=ctx.wasActive==true, hadRows=ctx.hadRows==true, origin=NS.CleanText(ctx.origin,96)}
        for i=1,MAX_CHOICES do
            local key = "q"..i
            if referenceKey(ctx.refs[key]) then db.context.refs[key] = ctx.refs[key] end
        end
    end
    for i,row in ipairs(type(old.cache) == "table" and old.cache or {}) do
        if i > MAX_CACHE then break end
        local copy = copyRecord(row)
        if copy then db.cache[#db.cache+1] = copy end
    end
    return db
end

local cachedFacts, logObserved = {},false
function NS.InvalidateClientQuestFacts(fromLog)
    cachedFacts = {}
    if fromLog then logObserved=true end
end
local function questFacts(id)
    if not integer(id) then return end
    local cached, now = cachedFacts[id], NS.Call(GetTime) or 0
    if not cached or now < cached.at or now - cached.at >= 15 then
        cached = {facts=NS.BuildClientQuestFacts(id),at=now}
        cachedFacts[id] = cached
    end
    return cached.facts
end
-- Hash quest meaning and log progress, ignoring player distance and the
-- choice of nearest spawn. The hash stays in this character's SavedVariables.
local function signature(facts)
    if not facts then return "" end
    if facts.signature then return facts.signature end
    local parts = {facts.title or "", tostring(facts.onQuest),tostring(facts.ready),tostring(facts.handedIn)}
    for _,row in ipairs(facts.rows or {}) do
        parts[#parts+1]=table.concat({row.type,row.text,tostring(row.finished)},"/")
    end
    for _,group in ipairs(facts.groups) do
        parts[#parts+1]=group.ref.."/"..tostring(group.done)
        for _,point in ipairs(group.points) do parts[#parts+1]=point.id end
    end
    table.sort(parts)
    local a,b=0,1
    for _,s in ipairs(parts) do
        for i=1,#s do
            a=(a+s:byte(i))%65521
            b=(b+a)%65521
        end
        a,b=(a+255)%65521,(b+a+255)%65521
    end
    facts.signature=string.format("%04x%04x",b,a)
    return facts.signature
end
function NS.GetClientQuestPoint(id)
    local facts = questFacts(tonumber(id:match("^askq:(%d+):")))
    return facts and facts.byID[id]
end
local function activeQuest(question)
    local api = C_QuestLog or {}
    local count = NS.Call(api.GetNumQuestLogEntries) or NS.Call(GetNumQuestLogEntries) or 0
    local best, length, tied = nil, 0, false
    for index=1,math.min(NS.Number(count) and count or 0,500) do
        local info = NS.Call(api.GetInfo,index)
        if not info and type(GetQuestLogTitle) == "function" then
            local ok,title,_,_,header,_,_,_,id = pcall(GetQuestLogTitle,index)
            if ok then info={title=title,isHeader=header,questID=id} end
        end
        if type(info) == "table" and not info.isHeader and integer(info.questID) then
            local title = NS.CleanText(info.title,180)
            if title ~= "" and question:find(title,1,true) then
                if #title > length then best,length,tied=info.questID,#title,false
                elseif #title == length and best ~= info.questID then tied=true end
            end
        end
    end
    return not tied and best or nil,tied
end
local function resolveQuest(question, explicit)
    if integer(explicit) then return explicit end
    local named = tonumber(question:match("任务 *#? *(%d+)") or question:lower():match("quest *#? *(%d+)"))
    if integer(named) then return named end
    local questLike = question:find("任务",1,true) or question:find("怎么做",1,true) or question:lower():find("quest",1,true)
    if not questLike then return 0 end
    local id,tied = activeQuest(question)
    if tied then return nil,"任务日志里有同名任务，请在问题中写出任务 ID。" end
    if id then return id end
    if question:find("这个任务",1,true) or question:find("当前任务",1,true) or question:find("这个怎么做",1,true) then
        local selected=NS.Call(C_QuestLog and C_QuestLog.GetSelectedQuest)
        if integer(selected) then return selected end
        return nil,"请在任务日志中选中任务，或输入任务名称。"
    end
    if NS.MatchReferenceQuest then id,tied=NS.MatchReferenceQuest(question) end
    if tied then return nil,"找到同名任务，请在问题中写出任务 ID。" end
    return id or 0
end
local function newID(db)
    db.serial = (db.serial % 2147483646) + 1
    local guid = NS.Call(UnitGUID,"player")
    guid = NS.CleanText(guid,100)
    local h = 5381
    for i=1,#guid do h = (h*33 + guid:byte(i)) % 4294967296 end
    return string.format("n-%x-%x-%x-%04x%04x", NS.Call(GetServerTime) or NS.Call(time) or 0,
        h, db.serial, math.random(0,65535), math.random(0,65535))
end
local function current()
    local db = NS.DB and NS.DB.clientAI
    local req,ctx = MyForeverNavigatorOutbox, db and db.context
    if type(req) == "table" and req.version == 1 and requestID(req.id) and ctx and ctx.id == req.id
        and plain(req.question,180) and (req.questID == 0 or integer(req.questID)) then return req,ctx end
end
function NS.CancelClientQuestion()
    MyForeverNavigatorOutbox = nil
    if NS.DB and NS.DB.clientAI then NS.DB.clientAI.context = nil end
end
function NS.SubmitClientQuestion(question, explicit, forceRetry)
    question = cleanQuestion(question)
    if not question then return nil,"请输入最多 180 字节的问题，去掉控制符和链接。" end
    local db = NS.DB and NS.DB.clientAI
    if not db then return nil,"世界向导尚未加载。" end
    local questID, why = resolveQuest(question,explicit)
    if not questID then return nil,why end
    local facts=questFacts(questID)
    local snapshot=signature(facts)
    local origin=originFor(question)
    local old,ctx = current()
    if old and not ctx.expired and (ctx.origin or "")==origin and ctx.signature==snapshot and old.questID == questID and questionKey(old.question) == questionKey(question)
        and (not forceRetry or NS.ClientQuestionStatus() ~= "error") then return old end
    local id = newID(db)
    local mapID = NS.Call(C_Map and C_Map.GetBestMapForUnit,"player")
    local faction = NS.Call(UnitFactionGroup,"player")
    local req = {version=1,id=id,question=question,locale=locale(),mapID=integer(mapID) and mapID or 0,
        faction=(faction=="Alliance" or faction=="Horde") and faction or "Neutral",questID=questID,questTitle="",choices={}}
    local refs = {}
    if facts then
        req.questTitle=NS.CleanText(facts.title,120)
        for _,group in ipairs(facts.groups) do
            if #req.choices >= MAX_CHOICES then break end
            if not group.done then
                local key="q"..(#req.choices+1)
                refs[key]=group.ref
                req.choices[#req.choices+1]={key=key,kind=group.kind,name=NS.CleanText(group.name,120),
                    detail=NS.CleanText(group.detail,240)}
            end
        end
    end
    db.context, MyForeverNavigatorOutbox={id=id,refs=refs,signature=snapshot,
        wasActive=facts and facts.onQuest or false,hadRows=facts and #facts.rows>0 or false,origin=origin},req
    return req
end

local function asksForWholeQuest(question)
    for _,word in ipairs({"这一步","这个步骤","最后一步","第一个","只问","只想","只要","交付怎么","交任务怎么",
        "物品怎么","NPC怎么","在哪","哪里","怎么去","怎么找"}) do
        if question:find(word,1,true) then return false end
    end
    if question:match("第.-步") then return false end
    for _,word in ipairs({"怎么做","如何做","怎么完成","如何完成","攻略","全流程","how do i complete","walkthrough"}) do
        if question:lower():find(word,1,true) then return true end
    end
    return false
end

-- Keys select game actions. Only the quest log/reference can say which
-- entity is a turn-in contact, a required item, or a destination.
local function questInstruction(choice,ref)
    local name=choice.name
    local detail=choice.detail~="" and choice.detail or name
    local text
    if ref=="turnin" then
        text=name=="客户端交付地点" and "到客户端标注的地点交付任务" or "向"..name.."交付任务"
    elseif ref:match("^item:") then text="收集任务物品 · "..detail
    elseif ref=="native" or ref:match("^area:") then text="前往任务地点 · "..detail
    else text="完成任务目标 · "..detail end
    return NS.CleanText(text,180)
end

-- A whole-quest answer is checked against the choices the game actually
-- supplied. Keep valid instructions, fill missing actions from local facts,
-- and never send the player to turn in a quest with omitted objectives.
local function completeQuestAnswer(record,req,ctx,seen,hasQuest)
    local actions,delivery,extras,added=0,nil,0,0
    local supplied={}
    for _,step in ipairs(record.steps) do
        if step.kind=="quest" then
            if step.ref=="turnin" then delivery=step else actions=actions+1 end
        end
    end
    for _,choice in ipairs(req.choices) do
        local ref=ctx.refs[choice.key]
        if ref and not seen[choice.key] then
            local step={kind="quest",ref=ref,text=questInstruction(choice,ref)}
            if ref=="turnin" then delivery=step else supplied[#supplied+1]=step;actions=actions+1 end
            added=added+1
        end
    end
    local maxExtras=math.max(0,MAX_STEPS-actions-(delivery and 1 or 0))
    local result={}
    for _,step in ipairs(record.steps) do
        if step.kind=="quest" and step.ref~="turnin" then
            result[#result+1]=step
        elseif step.kind=="place" and hasQuest and extras<maxExtras then
            result[#result+1]=step
            extras=extras+1
        end
    end
    for _,step in ipairs(supplied) do
        if #result==MAX_STEPS then break end
        result[#result+1]=step
    end
    if delivery and #result<MAX_STEPS then result[#result+1]=delivery end
    record.steps=result
    if actions+(delivery and 1 or 0)>MAX_STEPS then
        record.message=NS.CleanText("本次显示前 6 个任务步骤。完成后再问可继续剩余目标。 "..record.message,360)
    elseif added>0 then
        record.message=NS.CleanText("已按任务日志和本地资料补全步骤。 "..record.message,360)
    end
end

local function readReply()
    local req,ctx = current()
    if not req then return "none", "没有等待回答的问题。" end
    local origin=originFor(req.question)
    if (ctx.origin or "")~=origin then return "error","你已离开提问时的位置或阵营已变，请重新询问附近地点。" end
    local facts=questFacts(req.questID)
    if not ctx.expired and facts and ctx.wasActive and not facts.handedIn and not facts.ready
        and (not logObserved and not facts.onQuest or facts.onQuest and ctx.hadRows and #facts.rows==0) then
        return "pending","正在等待游戏载入任务日志。"
    end
    if ctx.expired or ctx.signature~=signature(facts) then
        return "error","任务进度已变化，请重新提问以获取当前步骤。"
    end
    local inbox=MyForeverNavigatorInbox
    local list=type(inbox)=="table" and inbox.version==1 and inbox.replies
    local row=type(list)=="table" and list[req.id]
    if row == nil or row == false then return "pending","等待我的无限客户端回答。" end
    local invalid="客户端回答格式无效，请重新提问。"
    if type(row)~="table" or row.id~=req.id or not stepsArray(row.steps,true)
        or (row.message~=nil and row.message~="" and not plain(row.message,360)) then return "error",invalid end
    if #row.steps==0 then return "error",plain(row.message,360) and row.message or "客户端没有给出可导航的步骤。" end
    local record={question=req.question,locale=req.locale,questID=req.questID,signature=ctx.signature,steps={},message=row.message or ""}
    local seen,hasQuest={},false
    local keysByName,choiceByKey={},{}
    for _,choice in ipairs(type(req.choices)=="table" and req.choices or {}) do
        if type(choice)=="table" and plain(choice.name,120) and ctx.refs[choice.key] then
            choiceByKey[choice.key]=choice
            local name=questionKey(choice.name)
            if keysByName[name]==nil then keysByName[name]=choice.key else keysByName[name]=false end
        end
    end
    for i,step in ipairs(row.steps) do
        if type(step)~="table" or not plain(step.text,180) then return "error",invalid end
        local key
        if step.kind=="quest" then
            if type(step.key)~="string" or not ctx.refs[step.key] then return "error",invalid end
            key=step.key
        elseif step.kind=="place" and plain(step.term,120) then
            key=keysByName[questionKey(step.term)]
        end
        if key then
            if seen[key] or not choiceByKey[key] then return "error",invalid end
            record.steps[i]={kind="quest",ref=ctx.refs[key],text=questInstruction(choiceByKey[key],ctx.refs[key])}
            seen[key],hasQuest=true,true
        elseif step.kind=="place" and plain(step.term,120) then
            record.steps[i]={kind="place",term=step.term,text=integer(req.questID) and NS.CleanText("前往"..step.term,180) or step.text}
        else return "error",invalid end
    end
    if next(ctx.refs) then
        record.message=NS.CleanText("按「"..req.questTitle.."」的任务日志和本地参考导航。",360)
    elseif integer(req.questID) then
        record.message="此任务还没有可核对的目标位置，请按任务日志确认，路线仅列出建议地点。"
    end
    if next(ctx.refs) and asksForWholeQuest(req.question) then
        completeQuestAnswer(record,req,ctx,seen,hasQuest)
    elseif next(ctx.refs) and not hasQuest then
        return "error","客户端回答没有对应到这项任务的已知目标，请重新提问。"
    end
    -- Keep the model's ordering within each phase; delivery follows all objectives.
    for i,step in ipairs(record.steps) do
        if step.kind=="quest" and step.ref=="turnin" and i<#record.steps then
            for j=i+1,#record.steps do
                if record.steps[j].kind=="quest" then
                    table.remove(record.steps,i)
                    record.steps[#record.steps+1]=step
                    break
                end
            end
            break
        end
    end
    record.requestID=req.id
    return "ready",nil,record
end
function NS.ClientQuestionStatus()
    local status,why=readReply()
    return status,why
end
function NS.ReadClientAnswer()
    local _,why,record=readReply()
    return record,why
end

local function phase(id)
    if type(id) ~= "string" then return end
    local q,kind,ref=id:match("^askq:(%d+):([a-z]+):([^:]+)")
    if not q then return end
    if kind=="turnin" or (kind=="native" and ref=="turnin") then return tonumber(q),"turnin" end
    return tonumber(q),kind=="native" and "native" or kind..":"..ref
end
function NS.ClientQuestHistory(id)
    local q=phase(id)
    local facts=q and questFacts(q)
    if facts then return facts.handedIn end
end
function NS.ClientQuestGate(id,step)
    local q,ref=phase(id)
    if not q then return end
    local facts=questFacts(q)
    if step and step.questTurnedIn then return true end
    if facts and facts.handedIn and not facts.onQuest and not (step and step.questPreviouslyDone) then return true end
    if not facts or not facts.onQuest then return false,"请先在任务日志中确认已接取该任务。" end
    if ref=="turnin" then return false,"请与任务 NPC 完成交付。" end
    if facts.ready or (facts.byRef[ref] and facts.byRef[ref].done) then return true end
    return false,"请继续当前任务目标，完成后会切换到下一步。"
end
function NS.ClientCanEnterStep(step)
    local q,ref=phase(step.questGoal or step.id)
    if not q then return true end
    local facts=questFacts(q)
    if facts and facts.handedIn and not facts.onQuest then return false,"该任务已交付，请重新查看路线。" end
    if not facts or not facts.onQuest then return false,"请先接取此任务再开始这一步。" end
    if ref=="turnin" and not facts.ready then return false,"任务日志仍有未完成目标，完成后才能前往交付。" end
    return true
end

-- An exact map name denotes arrival in that region, not an arbitrary NPC
-- whose search metadata happens to include its zone.
local function regionEntrances(term)
    local known,points=false,{}
    local faction=NS.Call(UnitFactionGroup,"player")
    local function usable(p) return p.faction=="Neutral" or p.faction==faction end
    for _,p in ipairs(NS.GetTransitStops and NS.GetTransitStops() or {}) do
        if p.zone==term then
            known=true
            if usable(p) then points[#points+1]=p end
        end
    end
    if #points>0 then return points end
    for _,p in ipairs(NS.Points or {}) do
        if p.zone==term then
            known=true
            if p.service=="飞行管理员" and usable(p) then points[#points+1]=p end
        end
    end
    if #points>0 then return points end
    if known then
        local landmarks=NS.FuzzySearch(term,{sort="distance",faction="own"})
        for _,p in ipairs(landmarks) do
            if p.zone==term then points[#points+1]=p end
        end
        return points,true
    end
end
local function nearbyPoints(input)
    local points={}
    local context=NS.Call(NS.GetLocationContext) or {}
    for _,target in ipairs(input) do
        local point={}
        for k,v in pairs(target) do point[k]=v end
        local d=NS.Call(NS.MeasurePoint,point,context)
        point.distance=NS.Number(d) and d>=0 and d or nil
        points[#points+1]=point
    end
    table.sort(points,function(a,b)
        if (a.mapID==context.mapID)~=(b.mapID==context.mapID) then return a.mapID==context.mapID end
        if (a.distance~=nil)~=(b.distance~=nil) then return a.distance~=nil end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.id<b.id
    end)
    return points
end

local capitals={Alliance={"暴风城","铁炉堡","达纳苏斯","埃索达"}, Horde={"奥格瑞玛","幽暗城","雷霆崖","银月城"}}
local function asksCapital(term,question)
    local compact=term:gsub(" ","")
    if compact=="主城" or compact=="最近的主城" or compact=="最近主城" or compact=="附近的主城" or compact=="附近主城"
        or compact=="本阵营主城" or compact=="本阵营的主城" or term:lower():find("capital city",1,true) then return true end
    if relativeQuestion(question) and question:find("主城",1,true) then
        for _,names in pairs(capitals) do
            for _,name in ipairs(names) do if term==name then return true end end
        end
    end
    return false
end
local function capitalStops()
    local points={}
    local faction=NS.Call(UnitFactionGroup,"player")
    for _,zone in ipairs(capitals[faction] or {}) do
        local entries,landmark=regionEntrances(zone)
        if entries then
            for i,p in ipairs(entries) do
                if not landmark or i==1 then points[#points+1]=p end
            end
        end
    end
    return nearbyPoints(points)
end
function NS.GetClientCandidates(state)
    state.candidateNotice=nil
    local step=state.clientSteps[state.index]
    if not step then return {},0 end
    local points={}
    if step.kind=="place" then
        local landmarks
        if asksCapital(step.term,state.question) then
            points=capitalStops()
            state.candidateNotice="当前主城优先。跨地图交通距离无法直接比较，请选择本阵营的城市和落点。"
        else points,landmarks=regionEntrances(step.term) end
        if not points then points=NS.FuzzySearch(step.term,{sort="distance",faction="own",includeTransit=true}) end
        if landmarks then state.candidateNotice="此区域没有已收录的入口，请选择一个已知地点作为落点。" end
    else
        local facts=questFacts(state.record.questID)
        local group=facts and facts.byRef[step.ref]
        if group and not group.done then
            points=nearbyPoints(group.points)
        end
    end
    local maps,n={},0
    for _,p in ipairs(points) do if not maps[p.mapID] then maps[p.mapID],n=true,n+1 end end
    return points,n
end
function NS.RebuildClientPlan(state,avoid)
    if #state.ids ~= #state.clientSteps or #state.ids == 0 then return nil,"请先选择每一步的地点。" end
    local plan,why=NS.BuildRoute(state.ids,nil,{noUnconfirmedFlights=avoid==true})
    if not plan then return nil,why end
    local index=1
    for _,leg in ipairs(plan.steps) do
        if leg.id==state.ids[index] then
            local instruction=state.clientSteps[index].text
            leg.label=NS.CleanText(instruction.." · "..leg.label,240)
            index=index+1
            -- Two actions can legitimately use one NPC. The route builder
            -- coalesces the point, so preserve the second instruction too.
            while state.ids[index] and state.ids[index]==leg.id do
                leg.label=NS.CleanText(leg.label.." · "..state.clientSteps[index].text,240)
                index=index+1
            end
        end
    end
    state.noUnconfirmedFlights,state.plan=avoid==true,plan
    return plan
end
local function fillSingleChoices(state)
    while state.index<=#state.clientSteps do
        local points=NS.GetClientCandidates(state)
        local first,second=points[1],points[2]
        if not first then break end
        local certain=state.clientSteps[state.index].kind=="quest" and not second
        if state.clientSteps[state.index].kind=="place" then
            certain=first.matchKind~="fuzzy" and not second
                or (first.matchScore or 0)>=100 and (not second or first.matchScore>(second.matchScore or 0))
        end
        if not certain or state.candidateNotice then break end
        state.ids[state.index],state.index=first.id,state.index+1
    end
    if state.index>#state.clientSteps then return NS.RebuildClientPlan(state,state.noUnconfirmedFlights) end
    return true
end
local function stateFor(record,source)
    local state={record=record, source=source, question=record.question, message=record.message, clientSteps={},terms={},ids={},index=1}
    local facts=questFacts(record.questID)
    for _,step in ipairs(record.steps) do
        local group=step.kind=="quest" and facts and facts.byRef[step.ref]
        local done=step.kind=="quest" and facts and (facts.handedIn and not facts.onQuest
            or (step.ref~="turnin" and facts.ready) or group and group.done)
        if not done then
            state.clientSteps[#state.clientSteps+1]=step
            state.terms[#state.terms+1]=step.term or (group and group.name) or step.text
        end
    end
    if #state.clientSteps==0 then return nil,"这些任务步骤已经完成。" end
    local ok,why=fillSingleChoices(state)
    if not ok then return nil,why end
    return state
end
function NS.BuildClientRouteState(reply)
    local currentReply,why=NS.ReadClientAnswer()
    if not currentReply then return nil,why end
    if reply and reply.requestID~=currentReply.requestID then return nil,"问题已经改变，请重新查看回答。" end
    return stateFor(currentReply,"client")
end
function NS.LookupClientRouteState(question,explicit)
    question=cleanQuestion(question)
    local db=NS.DB and NS.DB.clientAI
    if not question or not db or relativeQuestion(question) then return end
    local q=resolveQuest(question,explicit)
    for _,row in ipairs(db.cache) do
        if row.questID==q and row.locale==locale() and questionKey(row.question)==questionKey(question)
            and (q==0 or row.signature==signature(questFacts(q))) then
            return stateFor(row,"client-cache")
        end
    end
end
function NS.ResetClientRouteState(state)
    state.ids,state.index,state.plan={},1,nil
    return state
end
function NS.ChooseClientCandidate(state,id)
    if state.plan then return false,"请先重新选择地点。" end
    local points=NS.GetClientCandidates(state)
    local found=false
    for _,p in ipairs(points) do if p.id==id then found=true;break end end
    if not found then return false,"该地点不在这一步当前的候选中。" end
    state.ids[state.index],state.index=id,state.index+1
    local ok,why=fillSingleChoices(state)
    return not not ok,why
end
function NS.ConfirmClientRoute(state)
    if state.record.requestID then
        local req=current()
        if not req or req.id~=state.record.requestID then return false,"问题已经改变，请重新查看回答。" end
        if relativeQuestion(req.question) then
            local status,reason=NS.ClientQuestionStatus()
            if status~="ready" then return false,reason end
        end
    end
    if integer(state.record.questID) and state.record.signature~=signature(questFacts(state.record.questID)) then
        return false,"任务进度已变化，请重新提问。"
    end
    if not state.plan then return false,"请先选择各站并查看路线。" end
    local plan,why=NS.RebuildClientPlan(state,state.noUnconfirmedFlights)
    if not plan then return false,why end
    local ok,reason=NS.StartRoute(plan)
    if not ok then return false,reason end
    local row=copyRecord(state.record)
    if row and not relativeQuestion(row.question) then
        local cache=NS.DB.clientAI.cache
        for i=#cache,1,-1 do
            if cache[i].questID==row.questID and cache[i].locale==row.locale
                and questionKey(cache[i].question)==questionKey(row.question) then table.remove(cache,i) end
        end
        table.insert(cache,1,row)
        if #cache>MAX_CACHE then table.remove(cache) end
    end
    if state.record.requestID then NS.CancelClientQuestion() end
    return true
end


-- Repeatable quests can return to exactly the same objectives after reacquisition.
-- Invalidate records for that quest even if today's objective text is identical.
if type(CreateFrame)=="function" then
    local events=CreateFrame("Frame")
    if events.RegisterEvent and events.SetScript then
        events:RegisterEvent("QUEST_ACCEPTED")
        events:RegisterEvent("QUEST_TURNED_IN")
        events:SetScript("OnEvent",function(_,event,a,b)
            local q=event=="QUEST_ACCEPTED" and (b or a) or a
            if not integer(q) or not NS.DB or not NS.DB.clientAI then return end
            cachedFacts[q]=nil
            local route=NS.GetActiveRoute and NS.GetActiveRoute()
            if route and event=="QUEST_TURNED_IN" then
                -- Some repeatable quests never set a completion history flag.
                for _,step in ipairs(route.steps) do
                    if phase(step.questGoal or step.id)==q then step.questTurnedIn=true end
                end
                NS.Call(NS.UpdateRouteProgress)
            end
            local req,ctx=current()
            if req and req.questID==q then ctx.expired=true end
            local cache=NS.DB.clientAI.cache
            for i=#cache,1,-1 do
                if cache[i].questID==q then table.remove(cache,i) end
            end
        end)
    end
end
