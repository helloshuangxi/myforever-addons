local _, NS = ...
local MAX_DESTINATIONS, MAX_STEPS, MAX_OFFERS = 6, 80, 100
local modes = {walk=true, gate=true, ship=true, zeppelin=true, tram=true, flight=true, region=true}
local flightPoints = {}
for _, point in ipairs(NS.Points or {}) do
    if point.service == "飞行管理员" then flightPoints[point.id] = point end
end

local function validID(id)
    return type(id) == "string" and #id > 0 and #id <= 100
        and id:match("^[%w:_%-]+$") ~= nil and not id:match("^quest:")
end
local function stationName(value)
    return NS.CleanText(value, 120):lower()
end
function NS.NormalizeTransit(saved)
    local result = {}
    if type(saved) ~= "table" then return result end
    -- Only flight masters in the curated directory can become station IDs.
    for id in pairs(flightPoints) do
        local row = saved[id]
        if type(row) == "table" and type(row.offers) == "table" then
            local name = stationName(row.name)
            if name ~= "" then
                local offers = {}
                for i = 1, math.min(#row.offers, MAX_OFFERS) do
                    local offer = stationName(row.offers[i])
                    if offer ~= "" then offers[#offers+1] = offer end
                end
                result[id] = {name=name, offers=offers}
            end
        end
    end
    return result
end

local function canUse(point, faction)
    return point and (point.faction == "Neutral" or point.faction == faction)
end
local function stationAtPlayer()
    local context = NS.GetLocationContext()
    if not context.mapID or context.inInstance then return end
    local guid = NS.Call(UnitGUID, "npc")
    if issecretvalue and issecretvalue(guid) then guid = nil end
    local npcID = type(guid) == "string" and tonumber(guid:match("^Creature%-[^-]+%-[^-]+%-[^-]+%-[^-]+%-(%d+)%-"))
    local faction = NS.Call(UnitFactionGroup, "player")
    local nearby
    for id, station in pairs(flightPoints) do
        if station.mapID == context.mapID and canUse(station, faction) then
            if npcID and npcID == station.npcID then return id end
            if not npcID then
                local distance = NS.MeasurePoint(NS.GetPoint(id), context)
                if NS.Number(distance) and distance <= 45 then
                    if nearby then return nil end
                    nearby = id
                end
            end
        end
    end
    return nearby
end
-- TAXIMAP_OPENED only reads the open flight map. A reachability observation is
-- directional and may include intermediate fly-throughs on the same ticket.
function NS.ObserveTaxiMap()
    if not NS.DB then return false end
    local count = NS.Call(NumTaxiNodes)
    if not NS.Number(count) or count % 1 ~= 0 or count < 1 or count > 256 then return false end
    local station = stationAtPlayer()
    if not station then return false end
    local name, offers = nil, {}
    for i = 1, count do
        local kind = NS.Call(TaxiNodeGetType, i)
        if issecretvalue and issecretvalue(kind) then return false end
        if kind == "CURRENT" or kind == "REACHABLE" then
            local value = stationName(NS.Call(TaxiNodeName, i))
            if value == "" then return false end
            if kind == "CURRENT" then
                if name then return false end
                name = value
            elseif #offers < MAX_OFFERS then
                offers[#offers+1] = value
            else
                return false
            end
        end
    end
    if not name then return false end
    NS.DB.transit = NS.DB.transit or {}
    NS.DB.transit[station] = {name=name, offers=offers}
    return true
end

local function graphForCharacter(noUnconfirmedFlights)
    local graph = {points={}, links={}, sizes={}}
    local faction = NS.Call(UnitFactionGroup, "player")
    local function add(a, b, mode, confirmed)
        if noUnconfirmedFlights and mode == "flight" and not confirmed then return end
        local origin = graph.points[a] or NS.GetPoint(a)
        local target = graph.points[b] or NS.GetPoint(b)
        if not canUse(origin, faction) or not canUse(target, faction) then return end
        graph.points[a], graph.points[b] = origin, target
        graph.links[a] = graph.links[a] or {}
        graph.links[a][b] = {mode=mode, confirmed=confirmed}
    end
    local seen = NS.DB and NS.DB.transit or {}
    local idsByName = {}
    for id,row in pairs(seen) do
        -- Ambiguous station labels must never merge two different locations.
        if idsByName[row.name] == nil then idsByName[row.name] = id
        else idsByName[row.name] = false end
    end
    for _, link in ipairs(NS.TransitLinks or {}) do
        local function include(a,b)
            if link.mode ~= "flight" or not seen[a] or not seen[b]
                or not idsByName[seen[b].name] then add(a,b,link.mode,false) end
        end
        include(link.a,link.b)
        include(link.b,link.a)
    end
    for id,row in pairs(seen) do
        for _,name in ipairs(row.offers) do
            local dest = idsByName[name]
            if dest and dest ~= id then add(id,dest,"flight",true) end
        end
    end
    return graph
end
local function groundCost(graph, a, b)
    local size = graph.sizes[a.mapID]
    if not size then
        local w, h = NS.Call(C_Map and C_Map.GetMapWorldSize, a.mapID)
        if not NS.Number(w) or not NS.Number(h) or w <= 0 or h <= 0 then w, h = 3600, 2400 end
        size = {w, h}
        graph.sizes[a.mapID] = size
    end
    local dx, dy = (a.x - b.x) * size[1], (a.y - b.y) * size[2]
    return 1 + math.sqrt(dx * dx + dy * dy) / 50
end
-- Costs rank walking and transfers. They are not travel times; we have no
-- verified schedules, terrain mesh or fares. Walk links are zone-local only.
local costs = {gate=1, tram=7, ship=10, zeppelin=10, flight=8}
local function findLeg(graph, origin, goal)
    if not NS.ValidPoint(origin) then return {{point=goal, mode="region"}} end
    if origin.mapID == goal.mapID then return {{point=goal, mode="walk"}} end
    local nodes = {["@origin"]=origin, ["@goal"]=goal}
    for id,point in pairs(graph.points) do nodes[id]=point end
    local distance, visited, previous = {["@origin"]=0}, {}, {}
    while true do
        local current, cost
        for id,value in pairs(distance) do
            if not visited[id] and (not cost or value < cost or (value == cost and id < current)) then
                current, cost = id, value
            end
        end
        if not current then return {{point=goal, mode="region"}} end
        if current == "@goal" then break end
        visited[current] = true
        for id,point in pairs(nodes) do
            if not visited[id] then
                local link = graph.links[current] and graph.links[current][id]
                local mode, weight
                if link then
                    mode, weight = link.mode, costs[link.mode]
                    if link.mode == "flight" and not link.confirmed then weight = weight + 12 end
                elseif point.mapID == nodes[current].mapID then
                    mode, weight = "walk", groundCost(graph, nodes[current], point)
                end
                if weight and (not distance[id] or cost + weight < distance[id]) then
                    distance[id], previous[id] = cost + weight, {from=current,mode=mode,confirmed=link and link.confirmed}
                end
            end
        end
    end
    local result, cursor = {}, "@goal"
    while cursor ~= "@origin" do
        local edge = previous[cursor]
        table.insert(result, 1, {point=nodes[cursor],mode=edge.mode,confirmed=edge.confirmed})
        cursor = edge.from
    end
    return result
end

local verbs = {walk="前往", gate="通过入口，前往", ship="乘船到", zeppelin="乘飞艇到", tram="乘地铁到",
    flight="乘飞行坐骑到", region="自行前往"}
local function makeStep(leg)
    local p = leg.point
    local place = (p.zone and p.zone ~= "") and (p.zone .. " · " .. p.name) or p.name
    local label = verbs[leg.mode] .. place
    if leg.mode == "flight" and not leg.confirmed then label = label .. "（需已开航点）" end
    if leg.mode == "region" then label = label .. "（交通待确认）" end
    return {id=p.id, mode=leg.mode, label=NS.CleanText(label, 240),
        confirmed=leg.mode == "flight" and leg.confirmed == true or nil}
end
function NS.BuildRoute(input, context, options)
    if type(input) == "string" then input = {input}
    elseif type(input) == "table" and input.id then input = {input.id} end
    if type(input) ~= "table" or #input == 0 or #input > MAX_DESTINATIONS then
        return nil, "请选择 1 至 6 个已收录的目的地。"
    end
    context = context or NS.GetLocationContext()
    local noUnconfirmedFlights = type(options) == "table" and options.noUnconfirmedFlights == true
    local graph = graphForCharacter(noUnconfirmedFlights)
    local plan = {steps={}, index=1, noUnconfirmedFlights=noUnconfirmedFlights}
    local origin, incomplete = context and not context.inInstance and context
    for i = 1, #input do
        local id = type(input[i]) == "table" and input[i].id or input[i]
        local goal = validID(id) and NS.GetPoint(id)
        if not NS.ValidPoint(goal) then return nil, "第 " .. i .. " 个目的地当前没有可用坐标。" end
        for _, leg in ipairs(findLeg(graph, origin, goal)) do
            local last = plan.steps[#plan.steps]
            if not last or last.id ~= leg.point.id then
                local step = makeStep(leg)
                if goal.bridgeQuest then step.questGoal=goal.id end
                if #plan.steps >= MAX_STEPS then return nil, "本次路线过长，请分两次规划。" end
                plan.steps[#plan.steps+1] = step
                if step.mode == "region" then incomplete = true end
                if step.mode == "flight" and not step.confirmed then plan.hasUnconfirmedFlights = true end
            end
        end
        origin, plan.destinationID = goal, id
    end
    plan.note = incomplete and "部分区域之间还没有收录交通衔接。抵达目标区域后可继续跟随箭头。" or ""
    return plan
end

function NS.NormalizeRoute(saved, activeID)
    if type(saved) ~= "table" or type(saved.steps) ~= "table" or #saved.steps < 1
        or #saved.steps > MAX_STEPS or not NS.Number(saved.index) or saved.index % 1 ~= 0
        or saved.index < 1 or saved.index > #saved.steps then return end
    local plan = {steps={}, index=saved.index, note=NS.CleanText(saved.note, 240),
        noUnconfirmedFlights=saved.noUnconfirmedFlights == true}
    for i = 1, #saved.steps do
        local step = saved.steps[i]
        if type(step) ~= "table" or not validID(step.id) or not modes[step.mode] then return end
        local label = NS.CleanText(step.label, 240)
        if label == "" then return end
        local confirmed = step.mode == "flight" and step.confirmed == true or nil
        plan.steps[i] = {id=step.id,mode=step.mode,label=label,confirmed=confirmed}
        if validID(step.questGoal) and step.questGoal:match("^askq:%d+:") then
            plan.steps[i].questGoal=step.questGoal
            plan.steps[i].questPreviouslyDone=step.questPreviouslyDone==true or nil
            plan.steps[i].questTurnedIn=step.questTurnedIn==true or nil
        end
        if step.mode == "flight" and not confirmed then
            if plan.noUnconfirmedFlights then return end
            plan.hasUnconfirmedFlights = true
        end
    end
    plan.destinationID = plan.steps[#plan.steps].id
    if saved.destinationID ~= plan.destinationID or plan.steps[plan.index].id ~= activeID then return end
    plan.complete = saved.complete == true and plan.index == #plan.steps or nil
    return plan
end
function NS.GetActiveRoute()
    local route = NS.DB and NS.DB.route
    if route and route.steps[route.index].id == NS.DB.activeID then return route end
end
function NS.StartRoute(plan)
    if type(plan) ~= "table" or type(plan.steps) ~= "table" or type(plan.steps[1]) ~= "table" then
        return false, "路线不可用。"
    end
    local route = NS.NormalizeRoute(plan, plan.steps[1].id)
    if not route or route.index ~= 1 then return false, "请重新规划路线。" end
    for _,step in ipairs(route.steps) do
        if not NS.ValidPoint(NS.GetPoint(step.id)) then return false, "路线站点暂不可用，请重新规划。" end
    end
    if NS.ClientCanEnterStep then
        local ok,why=NS.ClientCanEnterStep(route.steps[1])
        if not ok then return false,why end
    end
    if NS.ClientQuestHistory then
        for _,step in ipairs(route.steps) do
            if step.questGoal then step.questPreviouslyDone=NS.ClientQuestHistory(step.questGoal) or nil end
        end
    end
    route.complete = nil
    return NS.Start(route.steps[1].id, route)
end
local function nextStep(route, automatic)
    if route.index >= #route.steps then return false, "当前已是终点。" end
    local nextIndex = route.index + 1
    if NS.ClientQuestGate then
        local done,why=NS.ClientQuestGate(route.steps[route.index].id,route.steps[route.index])
        if done == false then return false,why end
        local ok,reason=NS.ClientCanEnterStep(route.steps[nextIndex])
        if not ok then return false,reason end
    end
    local id = route.steps[nextIndex].id
    -- Stage the new index. A late Questie catalogue or hidden next point must
    -- keep the old index and navigation target intact.
    local proposed = {index=nextIndex, steps=route.steps, note=route.note, destinationID=route.destinationID,
        noUnconfirmedFlights=route.noUnconfirmedFlights, hasUnconfirmedFlights=route.hasUnconfirmedFlights}
    local ok, reason = NS.Start(id, proposed, automatic)
    local step = proposed.steps[nextIndex]
    if ok and costs[step.mode] and step.mode ~= "gate" then
        NS.Print(string.format("第 %d/%d 步 · %s", nextIndex, #proposed.steps, step.label))
    end
    return ok, reason
end
function NS.NextRouteStep()
    local route = NS.GetActiveRoute()
    if not route then return false, "请先开始一条路线。" end
    return nextStep(route, false)
end
local retryAt = 0
function NS.UpdateRouteProgress()
    local route = NS.GetActiveRoute()
    if not route or route.complete or NS.Call(UnitOnTaxi, "player") then return end
    local now = NS.Call(GetTime) or 0
    if now > 0 and now < retryAt then return end
    local complete
    if NS.ClientQuestGate then complete=NS.ClientQuestGate(route.steps[route.index].id,route.steps[route.index]) end
    if complete == false then return end
    if complete == nil then
        local nav = NS.GetNavigation()
        if not nav.point or nav.mode ~= "arrived" then return end
        -- City gates can overlap in world space across two UI maps.
        if NS.Call(C_Map and C_Map.GetBestMapForUnit, "player") ~= nav.point.mapID then return end
    end
    if route.index == #route.steps then
        route.complete = true
        NS.Call(NS.RefreshUI)
        return true
    end
    local ok = nextStep(route, true)
    retryAt = not ok and now + 2 or 0
    return ok
end

if type(CreateFrame) == "function" then
    local listener = CreateFrame("Frame")
    if listener.RegisterEvent and listener.SetScript then
        listener:RegisterEvent("TAXIMAP_OPENED")
        listener:SetScript("OnEvent", NS.ObserveTaxiMap)
    end
end
