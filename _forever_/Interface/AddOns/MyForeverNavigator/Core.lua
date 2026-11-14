local _, NS = ...
NS.VERSION = "0.5.0"

function NS.Number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end
function NS.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
function NS.ValidPoint(p)
    return type(p) == "table" and NS.Number(p.mapID) and p.mapID > 0 and p.mapID % 1 == 0
        and NS.Number(p.x) and NS.Number(p.y) and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1
end
local function text(value, maximum)
    if type(value) ~= "string" or (issecretvalue and issecretvalue(value)) then return "" end
    -- Never allow imported labels to inject chat links, textures or colour escapes.
    value = value:gsub("|", ""):gsub("[%z\1-\31\127]", " "):gsub("^ +", ""):gsub(" +$", "")
    if #value > maximum then
        value = value:sub(1, maximum)
        -- Remove an incomplete final UTF-8 code point after byte limiting.
        local head = #value
        while head > 0 and value:byte(head) >= 128 and value:byte(head) < 192 do head = head - 1 end
        local b = value:byte(head)
        local length = b and (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1) or 1
        if head + length - 1 > #value then value = value:sub(1, head - 1) end
    end
    return value
end
NS.CleanText = text
local function position(p)
    p = type(p) == "table" and p or {}
    local anchors = {CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    return {point = anchors[p.point] and p.point or "CENTER", relativePoint = anchors[p.relativePoint] and p.relativePoint or "CENTER",
        x = NS.Number(p.x) and math.max(-3000, math.min(3000, p.x)) or 0,
        y = NS.Number(p.y) and math.max(-2000, math.min(2000, p.y)) or 0}
end
function NS.NormalizeDB(value)
    local old = type(value) == "table" and value or {}
    local db = {version = 1, favorites = {}, custom = {}, nextCustomID = 1,
        panel = position(old.panel), hud = position(old.hud or {y=180}),
        minimapAngle = NS.Number(old.minimapAngle) and old.minimapAngle or 210}
    db.launcher = position(old.launcher or {point="TOPRIGHT",relativePoint="TOPRIGHT",x=-30,y=-287})
    if type(old.favorites) == "table" then
        for id, yes in pairs(old.favorites) do
            if type(id) == "string" and #id <= 100 and not id:match("^quest:") and yes == true then db.favorites[id] = true end
        end
    end
    local used = {}
    for _, p in ipairs(type(old.custom) == "table" and old.custom or {}) do
        if #db.custom >= 500 then break end
        if NS.ValidPoint(p) and type(p.id) == "string" and p.id:match("^custom:%d+$") and not used[p.id] then
            local name = text(p.name, 90)
            if name ~= "" then
                used[p.id] = true
                db.custom[#db.custom + 1] = {id=p.id, name=name, mapID=p.mapID, x=p.x, y=p.y,
                    category="custom", faction="Neutral", zone=text(p.zone, 90), service="自定义地点",
                    note=text(p.note, 360), tags="自定义 收藏 地点", source="user"}
                db.nextCustomID = math.max(db.nextCustomID, tonumber(p.id:match("(%d+)$")) + 1)
            end
        end
    end
    if type(old.activeID) == "string" and #old.activeID <= 100 then db.activeID = old.activeID end
    return db
end
function NS.GetPoint(id)
    if type(id) ~= "string" then return nil end
    if NS.TransientPoint and NS.TransientPoint.id == id then return NS.TransientPoint end
    if NS.GetQuestiePoint then
        local p = NS.GetQuestiePoint(id)
        if p then
            if NS.DB and NS.DB.activeID == id and NS.FreezeQuestiePoint then
                if not NS.QuestieDestination or NS.QuestieDestination.id ~= id then
                    local resolved = p
                    if NS.ResolvePoint then resolved = NS.ResolvePoint(p) end
                    NS.QuestieDestination = resolved and NS.FreezeQuestiePoint(resolved)
                end
                p = NS.QuestieDestination
                if not p then return nil end
            end
            if NS.ResolvePoint then return NS.ResolvePoint(p) end
            return p
        end
    end
    for _, p in ipairs(NS.Points or {}) do if p.id == id then return NS.ResolvePoint and NS.ResolvePoint(p) or p end end
    for _, p in ipairs(NS.DB and NS.DB.custom or {}) do if p.id == id then return p end end
end
function NS.Initialize(value)
    NS.TransientPoint = nil
    NS.QuestieDestination = nil
    NS.DB = NS.NormalizeDB(value)
    -- Questie builds after its locale and Forever corrections are ready.
    -- Keep a stable catalogue ID pending; never persist third-party records.
    if not NS.GetPoint(NS.DB.activeID) and not (type(NS.DB.activeID) == "string"
        and NS.DB.activeID:match("^questie%-npc%-%d+%-%d+$")) then NS.DB.activeID = nil end
    return NS.DB
end
function NS.Print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage((MyForeverStyle and MyForeverStyle.Prefix("世界向导") or "世界向导") .. " " .. tostring(message)) end
end
function NS.ToggleFavorite(id)
    local point = NS.GetPoint(id)
    if not NS.DB or not point or point.transient or id:match("^quest:") then return false end
    NS.DB.favorites[id] = not NS.DB.favorites[id] or nil
    return NS.DB.favorites[id] == true
end
function NS.AddCustom(name, mapID, x, y)
    if not NS.DB then return nil, "世界向导尚未加载。" end
    name = text(name, 90)
    if name == "" then return nil, "请输入地点名称。" end
    if not NS.ValidPoint({mapID=mapID, x=x, y=y}) then return nil, "请输入有效地图 ID 和 0–100 范围内的坐标。" end
    local info = NS.Call(C_Map and C_Map.GetMapInfo, mapID)
    if type(info) ~= "table" then return nil, "客户端不认识这个地图 ID。" end
    if #NS.DB.custom >= 500 then return nil, "已保存 500 个地点，请先删除不用的地点。" end
    local p = {id="custom:" .. NS.DB.nextCustomID, name=name, mapID=mapID, x=x, y=y,
        category="custom", faction="Neutral", zone=info.name or "自定义地图", service="自定义地点",
        note="玩家保存的地点；位置与可达性请自行确认。", tags="自定义 地点", source="user"}
    NS.DB.nextCustomID = NS.DB.nextCustomID + 1
    NS.DB.custom[#NS.DB.custom + 1] = p
    return p
end
function NS.RemoveCustom(id)
    if not NS.DB then return false end
    for i, p in ipairs(NS.DB.custom) do
        if p.id == id then
            if NS.DB.activeID == id and NS.Stop then NS.Stop() end
            table.remove(NS.DB.custom, i)
            NS.DB.favorites[id] = nil
            return true
        end
    end
    return false
end
function NS.SaveCurrent(name)
    local mapID, x, y = NS.GetPlayerPosition()
    if not mapID or not NS.ValidPoint({mapID=mapID, x=x, y=y}) then return nil, "当前位置暂不可用，请到室外再试。" end
    local target = text(NS.Call(UnitName, "target"), 90)
    local subzone = text(NS.Call(GetSubZoneText), 90)
    if text(name, 90) == "" then name = target ~= "" and target or (subzone ~= "" and subzone or "我的地点") end
    local p, err = NS.AddCustom(name, mapID, x, y)
    if p then p.note = "保存的是玩家站立位置。若以目标命名，不代表目标 NPC 的精确坐标。" end
    return p, err
end

-- Accept familiar /way-style percentages without claiming another addon's /way.
function NS.ParseCoordinateInput(input, currentMapID)
    local value = text(input, 300):gsub("，", ",")
    value = value:gsub("^/[wW][aA][yY] +", "")
    local mapID, body = value:match("^#(%d+) +(.*)$")
    mapID = mapID and tonumber(mapID) or currentMapID or NS.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    body = body or value
    local function percent(token)
        if not token or not token:match("^%d*[.,]?%d+$") then return nil end
        local normalized = token:gsub(",", ".")
        return tonumber(normalized)
    end
    -- Two whitespace-separated numeric tokens may each use a decimal comma.
    -- A single token X,Y is the alternate coordinate-pair format. Never split
    -- 45,2 67,8 into the wrong destination 45,2 with a numeric-looking name.
    local a, b, name = body:match("^([^ ]+) +([^ ]+) *(.-)$")
    local x, y = percent(a), percent(b)
    if not x or not y then
        a, b, name = body:match("^([%d%.]+), *([%d%.]+) +(.-)$")
        if not a then a, b = body:match("^([%d%.]+), *([%d%.]+)$"); name = "" end
        x, y = percent(a), percent(b)
    end
    local p = {mapID=mapID, x=x and x/100, y=y and y/100, name=name and name ~= "" and name or "坐标目标"}
    if not NS.ValidPoint(p) then return nil, "格式：/mynav way X Y 名称，或 /mynav way #地图ID X Y 名称；坐标填 0–100。" end
    return p
end
local searchText = setmetatable({}, {__mode="k"})
local function matches(p, terms)
    if #terms == 0 then return true end
    local haystack = searchText[p]
    if not haystack then
    local values = {p.name or "", p.english or "", p.zone or "", p.service or "", p.note or "", p.tags or "", tostring(p.npcID or "")}
    haystack = table.concat(values, " "):gsub("[A-Z]", string.lower)
    searchText[p] = haystack
    end
    local aliases = NS.Call(NS.GetPointSearchAliases, p)
    if type(aliases) == "string" and aliases ~= "" then haystack = haystack .. " " .. aliases:gsub("[A-Z]", string.lower) end
    for _, word in ipairs(terms) do if not haystack:find(word, 1, true) then return false end end
    return true
end
local scopeOrder = {["same-map"]=1,["same-continent"]=2,unknown=3,["other-continent"]=4}
function NS.Search(query, options)
    options = type(options) == "table" and options or {}
    local terms, result = {}, {}
    for word in text(query, 180):gsub("[A-Z]", string.lower):gmatch("[^ ]+") do terms[#terms+1] = word end
    local faction = NS.Call(UnitFactionGroup, "player")
    local mapID = NS.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local category = options.category or "all"
    local favorites = NS.DB and NS.DB.favorites or {}
    local context = NS.Call(NS.GetLocationContext)
    local function append(points)
        for _, original in ipairs(points) do
            local p = original
            if not p.questieSpawns and NS.ResolvePoint then p = NS.ResolvePoint(p) or p end
            local categoryOK = category == "all" or category == p.category or (category == "favorites" and favorites[p.id])
                or (NS.PointMatchesCategory and NS.PointMatchesCategory(p, category) == true)
            local factionOK = options.faction == "all" or not faction or p.faction == "Neutral" or p.faction == "Hostile" or p.faction == faction
            local subcategoryOK = not options.subcategory or options.subcategory == "all"
                or NS.Call(NS.PointMatchesSubcategory, p, options.subcategory) == true
            if NS.ValidPoint(p) and categoryOK and subcategoryOK and factionOK and (not options.currentZone or p.mapID == mapID) and matches(p, terms) then
                -- Dynamic records already contain localized search fields.
                -- Resolve only matches; querying every DB entity on each key
                -- press would stall a world-sized catalogue.
                if p.questieSpawns and NS.ResolvePoint then p = NS.ResolvePoint(p, context) end
                if p then
                local entry = {}
                for k, v in pairs(p) do entry[k] = v end
                local distance, scope = NS.Call(NS.MeasurePoint, p, context)
                if NS.Number(distance) and distance >= 0 then entry.distance = distance else entry.distance = nil end
                entry.scope = scopeOrder[scope] and scope or (p.mapID == mapID and "same-map" or "unknown")
                result[#result + 1] = entry
                end
            end
        end
    end
    append(NS.GetCatalogPoints and NS.GetCatalogPoints() or NS.Points or {})
    if options.includeCustom ~= false then append(NS.DB and NS.DB.custom or {}) end
    table.sort(result, function(a, b)
        if options.sort ~= "name" then
            -- Comparable world distances may cross a zone border. Do not put a
            -- distant same-zone vendor before a nearer vendor just over it.
            if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
            if a.distance ~= nil and a.distance ~= b.distance then return a.distance < b.distance end
            if scopeOrder[a.scope] ~= scopeOrder[b.scope] then return scopeOrder[a.scope] < scopeOrder[b.scope] end
            if a.zone ~= b.zone then return (a.zone or "") < (b.zone or "") end
        end
        if a.name ~= b.name then return a.name < b.name end
        if a.zone ~= b.zone then return (a.zone or "") < (b.zone or "") end
        return a.id < b.id
    end)
    return result
end
