local _, NS = ...

local MAX_QUERY, MAX_ROUTES, MAX_STOPS = 180, 128, 6

local function lower(value)
    return value:gsub("[A-Z]", string.lower)
end

local function queryKey(query)
    if (issecretvalue and issecretvalue(query)) or type(query) ~= "string" or #query > MAX_QUERY then return "" end
    -- Locale-dependent %s may consume 0xa0 inside a multibyte glyph (e.g. 码).
    return lower(NS.CleanText(query, MAX_QUERY)):gsub("\194\160"," "):gsub(" +", " ")
end

local function sharedKey(value)
    local key = queryKey(value)
    local previous
    repeat
        previous = key
        key = key:gsub("[ ?.]+$", ""):gsub("？$", ""):gsub("。$", "")
    until key == previous
    return key
end

local indexedPhrases, phraseIndex
function NS.LookupRoutePhrase(query)
    local source = NS.SharedRoutePhrases
    if not source then return end
    if source ~= indexedPhrases then
        phraseIndex, indexedPhrases = {}, source
        for _, row in ipairs(source) do
            for _, spelling in ipairs(row.aliases) do phraseIndex[sharedKey(spelling)] = row.terms end
        end
    end
    local terms = phraseIndex[sharedKey(query)]
    if terms then
        local result = {}
        for i, term in ipairs(terms) do result[i] = term end
        return result
    end
end

local function stableIDs(ids)
    if type(ids) ~= "table" or #ids < 1 or #ids > MAX_STOPS then return end
    local result = {}
    for index in pairs(ids) do
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #ids then return end
    end
    for i = 1, #ids do
        local id = ids[i]
        if type(id) ~= "string" or #id > 100 or not id:match("^[a-zA-Z0-9:_%-]+$")
            or id:match("^quest:") then return end
        result[i] = id
    end
    return result
end

-- Save only confirmed query/ID associations. The catalogue owns all names,
-- positions and phase data, and the routing layer derives legs for each trip.
function NS.NormalizeRouteKnowledge(old)
    local result = {version=1, entries={}}
    if type(old) ~= "table" or old.version ~= 1 or type(old.entries) ~= "table" then return result end
    local seen = {}
    for i = 1, math.min(#old.entries, MAX_ROUTES) do
        local item = old.entries[i]
        if type(item) == "table" and type(item.scope) == "string" and #item.scope <= 220
            and item.scope:match("^[A-Za-z0-9/:_%-]+$") then
            local query, ids = queryKey(item.query), stableIDs(item.ids)
            local key = item.scope .. "\t" .. query
            if query ~= "" and ids and not seen[key] then
                result.entries[#result.entries+1] = {scope=item.scope, query=query, ids=ids}
                seen[key] = true
            end
        end
    end
    return result
end

local relative = {"最近","附近","就近","周围","身边","离我","closest","nearest","nearby","near me"}
local function lookupContext(query, options)
    local key = queryKey(query)
    if key == "" or not NS.DB or not NS.DB.routeKnowledge then return end
    for _, word in ipairs(relative) do if key:find(word, 1, true) then return end end
    local map = NS.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local faction = NS.Call(UnitFactionGroup, "player")
    if not NS.Number(map) or map <= 0 or map % 1 ~= 0 or (faction ~= "Alliance" and faction ~= "Horde") then return end
    local scope = table.concat({tostring(map), faction, NS.Call(GetLocale) or "default",
        options.category or "all", options.subcategory or "all", options.faction == "all" and "all" or "own",
        options.currentZone and "zone" or "world", options.includeCustom == false and "npc" or "places"}, "/")
    return key, scope, map, faction
end

local function validStops(ids, options, map, faction)
    for _, id in ipairs(ids) do
        local point = NS.GetPoint(id)
        if not NS.ValidPoint(point) or point.transient or (point.category == "custom" and options.includeCustom == false)
            or (options.currentZone and point.mapID ~= map) then return false end
        if options.faction ~= "all" and point.faction ~= faction and point.faction ~= "Neutral" and point.faction ~= "Hostile" then return false end
        local category = options.category or "all"
        if category ~= "all" and category ~= point.category and not (category == "favorites" and NS.DB.favorites[id])
            and not NS.Call(NS.PointMatchesCategory, point, category) then return false end
        if options.subcategory and options.subcategory ~= "all" and not NS.Call(NS.PointMatchesSubcategory, point, options.subcategory) then return false end
    end
    return true
end

function NS.RememberRoute(query, ids, options)
    options = options or {}
    local key, scope, map, faction = lookupContext(query, options)
    ids = stableIDs(ids)
    if not key or not ids or not validStops(ids, options, map, faction) then return false end
    local entries = NS.DB.routeKnowledge.entries
    for i, record in ipairs(entries) do
        if record.scope == scope and record.query == key then table.remove(entries, i); break end
    end
    table.insert(entries, 1, {query=key, scope=scope, ids=ids})
    if #entries > MAX_ROUTES then table.remove(entries) end
    return true
end

function NS.RecallRoute(query, options)
    options = options or {}
    local key, scope, map, faction = lookupContext(query, options)
    if not key then return end
    for _, record in ipairs(NS.DB.routeKnowledge.entries) do
        if record.scope == scope and record.query == key and validStops(record.ids, options, map, faction) then
            return stableIDs(record.ids)
        end
    end
end

-- Longest phrase first keeps phrases like 草药学 and 拍卖行 intact. Unknown
-- words survive tokenization, so a recognizable city alone cannot silently
-- satisfy a request for a service that the catalogue doesn't contain.
local vocabulary = {}
local function words(canonical, ...)
    for _, phrase in ipairs({...}) do
        vocabulary[#vocabulary+1] = {text=phrase, term=canonical}
    end
end
words("暴风城", "暴风城", "暴风", "sw")
words("铁炉堡", "铁炉堡", "铁炉")
words("奥格瑞玛", "奥格瑞玛", "奥格", "奥城")
words("雷霆崖", "雷霆崖", "雷霆")
words("幽暗城", "幽暗城", "幽暗")
words("达纳苏斯", "达纳苏斯", "达纳")
words("训练师", "训练师", "训练员", "训练导师", "老师", "师傅", "学", "学习", "想学")
words("采矿", "采矿", "挖矿")
words("草药", "采药", "采草药", "草药学", "草药")
words("烹饪", "做饭", "烹饪")
words("钓鱼", "钓鱼", "垂钓")
words("银行", "银行", "存东西", "存钱", "存取物品")
words("拍卖", "拍卖行", "拍卖师", "拍卖", "ah")
words("旅店", "旅馆", "旅店", "绑定炉石", "绑炉石")
words("飞行", "飞行点", "飞行管理员", "鸟点", "坐鸟", "坐飞机")
words("修理", "修装备", "修理装备", "修理", "修装")
words("军需官", "军需官", "军需")
words("", "我想去", "我想", "我要去", "我要", "带我去", "请帮我找", "帮我找", "帮我", "请问",
    "请带我去", "我想要", "哪里可以", "哪里能", "在哪里", "怎么去", "怎么走", "在哪儿",
    "在哪", "哪里", "附近的", "附近", "最近的", "最近", "找一下", "找到", "找", "前往",
    "导航到", "导航去", "的", "去", "可以", "请", "？", "?", "，", "。", "、", ",", "：", ":")
table.sort(vocabulary, function(a,b) return #a.text > #b.text end)

local function glyphs(value)
    local result = {}
    for ch in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do result[#result+1] = ch end
    return result
end

local function compact(value)
    return (lower(value):gsub("·", ""):gsub("’", ""):gsub("[ .'%-]", ""))
end

local function queryTerms(value)
    local terms, seen = {}, {}
    local function add(word)
        if word == "" or seen[word] then return end
        seen[word] = true
        local flat = compact(word)
        local chars = glyphs(flat)
        terms[#terms+1] = {word=word, flat=flat, chars=chars, approximate=#chars >= 3 and #chars <= 24 and not flat:match("^%d+$")}
    end
    local first = 1
    local at = 1
    while at <= #value do
        local ending, term
        if value:sub(at,at) == " " then
            ending = at
        else
            for _, rule in ipairs(vocabulary) do
                local last = at + #rule.text - 1
                if value:sub(at,last) == rule.text then
                    -- Keep ASCII shortcuts such as 'ah' out of full NPC names.
                    if not rule.text:match("^[a-z]") or (not value:sub(at-1,at-1):match("[a-z0-9]")
                        and not value:sub(last+1,last+1):match("[a-z0-9]")) then
                        ending, term = last, rule.term
                        break
                    end
                end
            end
        end
        if ending then
            add(value:sub(first,at-1))
            if term then add(term) end
            first, at = ending+1, ending+1
        else
            at = at+1
        end
    end
    add(value:sub(first))
    return terms
end

local function prefixAt(value, pos, text)
    return value:sub(pos, pos+#text-1) == text
end

-- Match a short ordered abbreviation or one inserted, omitted, substituted
-- or transposed character. Compare UTF-8 characters rather than bytes.
local function approximate(term, value)
    if value == "" or not term.approximate then return false end
    local chars = term.chars
    if not value:find(chars[1], 1, true) and not value:find(chars[#chars], 1, true) then return false end
    local start = value:find(chars[1], 1, true)
    if start then
        local pos, hits = start, 0
        for _, ch in ipairs(chars) do
            local nextAt = value:find(ch, pos, true)
            if not nextAt then break end
            pos, hits = nextAt + #ch, hits+1
        end
        if hits == #chars and pos-start <= #term.flat * 1.7 then return true end
    end
    -- Bound typo matching to the start of the name, avoiding unrelated
    -- three-character queries matching arbitrary pairs inside long names.
    local pos = 1
    for i, ch in ipairs(chars) do
        if not prefixAt(value, pos, ch) then
            local remaining = term.flat:sub(pos+#ch)
            local targetChar = value:match("^([%z\1-\127\194-\244][\128-\191]*)", pos) or ""
            if remaining == "" then return pos+#targetChar > #value end
            if prefixAt(value, pos, remaining) or prefixAt(value, pos+#targetChar, remaining) then return true end
            local nextChar = chars[i+1]
            return targetChar == nextChar and prefixAt(value, pos+#targetChar, ch .. remaining:sub(#nextChar+1))
        end
        pos = pos+#ch
    end
    return true
end

local names = setmetatable({}, {__mode="k"})
local function namesFor(point)
    local fields = names[point]
    if not fields then
        fields = {compact(point.name or ""), compact(point.english or "")}
        names[point] = fields
    end
    return fields
end

function NS.FuzzySearch(query, options)
    options = options or {}
    local key = queryKey(query)
    if key == "" then
        if type(query) == "string" and #query > MAX_QUERY then return {} end
        return NS.Search("", options)
    end
    local shared = NS.LookupRoutePhrase(key)
    local terms = queryTerms(shared and #shared == 1 and shared[1] or key)
    local whole = compact(key)
    local learned = NS.RecallRoute(key, options)
    local learnedID = learned and #learned == 1 and learned[1]
    local search = {}
    for k,v in pairs(options) do search[k]=v end
    search.rankPoint = function(point, haystack)
        if point.id == learnedID then return 110, "alias" end
        local fields = namesFor(point)
        if whole ~= "" and (fields[1] == whole or fields[2] == whole) then return 100, "exact" end
        if tostring(point.npcID) == key and point.npcID then return 100, "exact" end
        if haystack:find(key, 1, true) then return 90, "exact" end
        if #terms == 0 then return end
        local kind, score = "alias", 80
        for _, term in ipairs(terms) do
            if not haystack:find(term.word, 1, true) then
                if not approximate(term, fields[1]) and not approximate(term, fields[2]) then return end
                kind, score = "fuzzy", 50
            end
        end
        return score, kind
    end
    local results = NS.Search(key, search)
    if NS.Number(options.limit) and options.limit >= 0 then
        for i = #results, math.floor(options.limit)+1, -1 do results[i] = nil end
    end
    return results
end
