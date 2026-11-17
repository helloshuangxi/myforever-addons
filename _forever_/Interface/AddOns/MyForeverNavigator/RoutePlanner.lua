local _, NS = ...
local MAX_STOPS, MAX_QUERY = 6, 180
local plannerURL = "https://afabiaoge.xyz/navigator/planner/"
local pending
local function trim(s) return s:match("^ *(.-) *$") end

local function queryHash(value)
    local h = 5381
    for i = 1, #value do h = (h * 33 + value:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

function NS.RouteWebURL(query)
    if type(query) ~= "string" or #query > MAX_QUERY or trim(query) == "" then return nil end
    pending = query
    return plannerURL .. "#q=" .. query:gsub("([^A-Za-z0-9._~%-])", function(c)
        return string.format("%%%02X", c:byte())
    end)
end

local function splitStops(value, encoded)
    local result = {}
    for part in (value.."~"):gmatch("(.-)~") do
        local term = trim(part)
        if term == "" or #result >= MAX_STOPS then return nil end
        if encoded and (term ~= part or #term > 64 or term:find("[^%w \128-\255%-]") or term:match("^%d+$")) then return nil end
        result[#result+1] = term
    end
    return result
end

local function localeKey() return NS.Call(GetLocale) or "default" end

-- These entries remember what the user meant, independently from where the
-- character stood. Only the confirmed-route cache may remember specific IDs.
function NS.NormalizeRouteIntents(old)
    local result = {}
    if type(old) ~= "table" then return result end
    for i=1,math.min(#old,128) do
        local row=old[i]
        if type(row)=="table" and type(row.question)=="string" and row.question~=""
            and row.question==NS.CleanText(row.question,MAX_QUERY)
            and type(row.locale)=="string" and #row.locale<=12 and row.locale:match("^[a-zA-Z]+$")
            and type(row.body)=="string" and #row.body<=240 and splitStops(row.body,true) then
            result[#result+1]={question=row.question,locale=row.locale,body=row.body}
        end
    end
    return result
end

local function intentKey(s)
    return trim(s):gsub("[A-Z]",string.lower):gsub(" +"," ")
end

local function learnedTerms(question)
    local key,locale=intentKey(question),localeKey()
    for _,entry in ipairs(NS.DB and NS.DB.routeIntents or {}) do
        if entry.question==key and entry.locale==locale then return splitStops(entry.body,true) end
    end
end

local function rememberTerms(question,terms)
    local entries=NS.DB.routeIntents
    local key,locale=intentKey(question),localeKey()
    for i=#entries,1,-1 do
        if entries[i].question==key and entries[i].locale==locale then table.remove(entries,i) end
    end
    table.insert(entries,1,{question=key,locale=locale,body=table.concat(terms,"~")})
    if #entries>128 then table.remove(entries) end
end

-- The clipboard contains only search terms. Resolve against this character's
-- current local catalogue before accepting a stop or creating an itinerary.
function NS.NewRouteQuery(input)
    if type(input) ~= "string" then return nil, "请输入地点、NPC 或想做的事。" end
    input = trim(input)
    if #input > 254 or input:find("[%z\1-\31\127|]") then return nil, "问路内容过长或含有无效字符。" end
    local value = input:gsub("^/mynav +route +", "")
    if value == "" then return nil, "请输入地点、NPC 或想做的事。" end
    local source, question, terms = "local", value
    if value:match("^MFN%d") then
        local hash, body = value:match("^MFN1@(%x%x%x%x%x%x%x%x)~(.+)$")
        if not body then body = value:match("^MFN1~(.+)$") end
        if #value <= 240 and body then terms = splitStops(body, true) end
        if not terms then return nil, "问路码无效，请从网页重新复制完整命令。" end
        source = "import"
        question = pending and queryHash(pending) == hash and pending or nil
    else
        if #value > MAX_QUERY then return nil, "请缩短问题，最多 180 个字节。" end
        terms = learnedTerms(question) or (NS.LookupRoutePhrase and NS.LookupRoutePhrase(question))
        if not terms then
            local body = value:gsub("^先", ""):gsub("→","~"):gsub("%->","~"):gsub("[;>]","~"):gsub("；","~")
            for _, connector in ipairs({"然后","接着","顺便去","再去","再到","再找","再学"}) do
                body=body:gsub(connector, "~")
            end
            body=body:gsub("， *~","~"):gsub(", *~","~")
            terms=splitStops(body)
        end
        if not terms then return nil, "请用分号分隔 1 至 6 个目的地。" end
    end
    local state = {terms=terms, index=1, ids={}, source=source, question=question}
    -- A learned query still goes through BuildRoute at today's position and
    -- StartRoute on explicit confirmation. An imported answer is always reviewed.
    if source == "local" and NS.RecallRoute then
        local ids = NS.RecallRoute(question)
        local plan = ids and NS.BuildRoute(ids)
        if plan then state.ids, state.plan, state.source = ids, plan, "cache"; return state end
    end
    return state
end

function NS.GetRouteCandidates(state)
    if state and state.clientSteps then return NS.GetClientCandidates(state) end
    local term = state and state.terms[state.index]
    if not term then return {}, 0 end
    local points = NS.FuzzySearch(term, {sort="distance", faction="own", includeTransit=true})
    local maps, count = {}, 0
    for _, point in ipairs(points) do
        if not maps[point.mapID] then maps[point.mapID] = true; count = count + 1 end
    end
    return points, count
end

function NS.ChooseRouteCandidate(state, id)
    if state and state.clientSteps then return NS.ChooseClientCandidate(state,id) end
    if not state or state.plan or not state.terms[state.index] then return false, "请先查询路线。" end
    if not NS.GetPoint(id) then return false, "该地点目前不可用，请另选一站。" end
    local ids = {}
    for i, known in ipairs(state.ids) do ids[i] = known end
    ids[#ids+1] = id
    if state.index == #state.terms then
        local plan, err = NS.BuildRoute(ids)
        if not plan then return false, err end
        state.plan = plan
    end
    state.ids, state.index = ids, state.index + 1
    return true
end

function NS.ConfirmRouteQuery(state)
    if state and state.clientSteps then return NS.ConfirmClientRoute(state) end
    if not state or not state.plan then return false, "请先选择各站并查看路线。" end
    local plan, reason = NS.BuildRoute(state.ids,nil,{noUnconfirmedFlights=state.noUnconfirmedFlights})
    if not plan then return false, reason end
    local ok, err = NS.StartRoute(plan)
    if ok and state.question and NS.RememberRoute then
        NS.RememberRoute(state.question, state.ids)
        if state.source=="import" and NS.DB.routeIntents then rememberTerms(state.question,state.terms) end
    end
    return ok, err
end
