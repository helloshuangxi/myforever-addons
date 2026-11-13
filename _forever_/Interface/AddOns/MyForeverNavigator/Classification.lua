local _, NS = ...

-- These groups describe the authored catalogue's service/tags. They do not
-- establish current NPC stock, prerequisites or in-game location verification.
local definitions = {
    trainers = {
        {"warrior", "战士"}, {"paladin", "圣骑士"}, {"hunter", "猎人"},
        {"rogue", "盗贼"}, {"priest", "牧师"}, {"shaman", "萨满祭司"},
        {"mage", "法师"}, {"warlock", "术士"}, {"druid", "德鲁伊"},
        {"other", "其他职业"},
    },
    reputation = {
        {"argent-dawn", "银色黎明"}, {"timbermaw", "木喉要塞"},
        {"cenarion-circle", "塞纳里奥议会"}, {"thorium-brotherhood", "瑟银兄弟会"},
        {"zandalar-tribe", "赞达拉部族"}, {"hydraxian-waterlords", "海达希亚水元素"},
        {"wintersaber-trainers", "冬刃豹训练师"}, {"ravenholdt", "拉文霍德"},
        {"silverwing-sentinels", "银翼要塞"}, {"warsong-outriders", "战歌氏族"},
        {"league-of-arathor", "阿拉索联军"}, {"defilers", "污染者"},
        {"stormpike-guard", "雷矛卫队"}, {"frostwolf-clan", "霜狼氏族"},
        {"other", "其他声望"},
    },
    materials = {
        {"alchemy", "炼金"}, {"enchanting", "附魔"}, {"tailoring", "裁缝"},
        {"engineering", "工程"}, {"leatherworking", "制皮"}, {"blacksmithing", "锻造"},
        {"reagents", "施法材料"}, {"trade", "商贸与杂货"}, {"other", "其他材料"},
    },
    special = {
        {"mount", "坐骑商人"}, {"weapon-training", "武器训练"},
        {"profession-advancement", "专业进阶"}, {"other", "其他任务"},
    },
    services = {
        {"flight-master", "飞行管理员"}, {"vendor", "其他商人"},
        {"innkeeper", "旅店老板"}, {"banker", "银行职员"},
        {"auctioneer", "拍卖师"}, {"stable-master", "兽栏管理员"},
        {"repair", "修理"}, {"trainer", "其他训练师"}, {"other", "其他服务"},
    },
    npcs = {{"quest-contact", "任务接洽"}, {"hostile", "怪物与敌对 NPC"}, {"other", "其他 NPC"}},
}

local serviceGroups = {
    trainers = {
        ["战士训练师"] = {"warrior"}, ["圣骑士训练师"] = {"paladin"},
        ["猎人训练师"] = {"hunter"}, ["盗贼训练师"] = {"rogue"},
        ["牧师训练师"] = {"priest"}, ["萨满祭司训练师"] = {"shaman"},
        ["法师训练师"] = {"mage"}, ["术士训练师"] = {"warlock"},
        ["德鲁伊训练师"] = {"druid"},
    },
    materials = {
        ["炼金材料商人"] = {"alchemy"}, ["附魔材料商人"] = {"enchanting"},
        ["裁缝材料商人"] = {"tailoring"}, ["工程材料商人"] = {"engineering"},
        ["制皮材料商人"] = {"leatherworking"}, ["锻造材料商人"] = {"blacksmithing"},
        ["施法材料商人"] = {"reagents"}, ["施法材料与草药"] = {"reagents"},
        ["商贸材料商人"] = {"trade"}, ["杂货与商贸材料"] = {"trade"},
        ["制皮与裁缝材料"] = {"leatherworking", "tailoring"},
    },
    special = {
        ["坐骑商人"] = {"mount"}, ["武器训练"] = {"weapon-training"},
        ["急救进阶训练与任务"] = {"profession-advancement"},
        ["急救训练与任务"] = {"profession-advancement"},
        ["钓鱼用品"] = {"profession-advancement"},
        ["钓鱼进阶任务"] = {"profession-advancement"},
        ["烹饪进阶任务与补给"] = {"profession-advancement"},
        ["侏儒工程任务"] = {"profession-advancement"},
        ["工程训练"] = {"profession-advancement"},
        ["武器锻造专精任务"] = {"profession-advancement"},
        ["护甲锻造训练与任务"] = {"profession-advancement"},
    },
    services = {["飞行管理员"] = {"flight-master"}},
}

-- Exact tag tokens can declare a second purpose. Never infer a profession
-- from incidental substrings such as "材料" or "武器锻造".
local tagGroups = {
    trainers = {
        warrior = {"战士"}, paladin = {"圣骑士"}, hunter = {"猎人"},
        rogue = {"盗贼"}, priest = {"牧师"}, shaman = {"萨满祭司"},
        mage = {"法师"}, warlock = {"术士"}, druid = {"德鲁伊"},
    },
    materials = {
        alchemy = {"炼金", "炼金材料商人"}, enchanting = {"附魔", "附魔材料商人"},
        tailoring = {"裁缝", "裁缝材料商人"}, engineering = {"工程", "工程材料商人"},
        leatherworking = {"制皮", "制皮材料商人"}, blacksmithing = {"锻造", "锻造材料商人"},
        reagents = {"施法材料", "施法材料商人", "施法材料与草药"},
        trade = {"商贸材料商人", "杂货与商贸材料"},
    },
    special = {
        mount = {"坐骑"}, ["weapon-training"] = {"武器大师"},
        ["profession-advancement"] = {"急救", "钓鱼", "烹饪", "工程", "侏儒工程", "锻造"},
    },
    services = {["flight-master"] = {"飞行管理员", "飞行点"}},
}

local function plain(value)
    if issecretvalue and issecretvalue(value) then return "" end
    return type(value) == "string" and value or ""
end
local function tagSet(value)
    local found = {}
    -- ASCII whitespace only: byte-oriented Lua locale classes can corrupt
    -- Chinese UTF-8 bytes on some hosts.
    for token in plain(value):gmatch("[^ \t\r\n]+") do found[token] = true end
    return found
end
local function prefix(service)
    -- A UTF-8 colon must be found literally, not inside a Lua byte class.
    local full, half = service:find("：", 1, true), service:find(":", 1, true)
    local index = full and half and math.min(full, half) or full or half
    return index and service:sub(1, index - 1) or service
end

local function memberships(point)
    if type(point) ~= "table" then return {"other"} end
    local category = point.category
    local groups = definitions[category]
    if not groups then return {"other"} end
    if point.catalogSubcategory then
        for _, group in ipairs(groups) do
            if point.catalogSubcategory == category .. ":" .. group[1] then return {point.catalogSubcategory} end
        end
    end
    local result, seen = {}, {}
    local function add(suffix)
        if not seen[suffix] then
            seen[suffix] = true
            result[#result + 1] = category .. ":" .. suffix
        end
    end
    local service, tags = plain(point.service), tagSet(point.tags)
    if category == "reputation" then
        local name = prefix(service)
        for _, group in ipairs(groups) do
            if group[1] ~= "other" and name == group[2] then add(group[1]) end
        end
        if #result == 0 then
            for _, group in ipairs(groups) do
                if group[1] ~= "other" and tags[group[2]] then add(group[1]) end
            end
        end
    else
        local exact = serviceGroups[category] and serviceGroups[category][service]
        for _, suffix in ipairs(exact or {}) do add(suffix) end
        local aliases = tagGroups[category] or {}
        for _, group in ipairs(groups) do
            for _, token in ipairs(aliases[group[1]] or {}) do
                if tags[token] then add(group[1]); break end
            end
        end
    end
    if #result == 0 then add("other") end
    return result
end

function NS.GetPointSubcategory(point)
    return memberships(point)[1]
end

function NS.PointMatchesSubcategory(point, id)
    if id == nil or id == "all" then return true end
    for _, member in ipairs(memberships(point)) do if member == id then return true end end
    return false
end

local countCache, countSource = {}, nil
local function copyGroups(groups)
    local copy = {}
    for i, group in ipairs(groups) do copy[i] = {id=group.id,label=group.label,count=group.count} end
    return copy
end
function NS.GetSubcategories(category)
    local points = NS.GetCatalogPoints and NS.GetCatalogPoints() or NS.Points or {}
    if points ~= countSource then countCache, countSource = {}, points end
    if countCache[category or "all"] then return copyGroups(countCache[category or "all"]) end
    local result = {{id="all", label="全部", count=0}}
    local byID = {}
    local groups = definitions[category]
    for _, group in ipairs(groups or {}) do
        local entry = {id=category .. ":" .. group[1], label=group[2], count=0}
        result[#result + 1] = entry
        byID[entry.id] = entry
    end
    -- Count catalogue NPCs, not favorites, custom places, faction-filtered
    -- results or the player's current zone. Composite purposes overlap.
    for _, point in ipairs(points) do
        if category == "all" or point.category == category then
            result[1].count = result[1].count + 1
            if groups then
                for _, id in ipairs(memberships(point)) do
                    if byID[id] then byID[id].count = byID[id].count + 1 end
                end
            end
        end
    end
    countCache[category or "all"] = result
    return copyGroups(result)
end

-- Read explicit titles and function flags from the ready, composed DB. These
-- labels describe roles, not current stock, friendliness or trainable spells.
local classTitles = {
    {"warrior", "战士", "Warrior"}, {"paladin", "圣骑士", "Paladin"},
    {"hunter", "猎人", "Hunter"}, {"rogue", "盗贼", "Rogue"},
    {"priest", "牧师", "Priest"}, {"shaman", "萨满祭司", "Shaman"},
    {"mage", "法师", "Mage"}, {"warlock", "术士", "Warlock"}, {"druid", "德鲁伊", "Druid"},
}
local materialTitles = {
    {"alchemy", "炼金材料商人", "炼金术供应商", "炼金术材料", "Alchemy Supplies"},
    {"enchanting", "附魔材料商人", "附魔供应商", "附魔材料", "Enchanting Supplies"},
    {"tailoring", "裁缝材料商人", "裁缝供应商", "裁缝材料", "Tailoring Supplies"},
    {"engineering", "工程材料商人", "工程学供应商", "工程学材料", "Engineering Supplies"},
    {"leatherworking", "制皮材料商人", "制皮供应商", "制皮材料", "Leatherworking Supplies"},
    {"blacksmithing", "锻造材料商人", "锻造供应商", "锻造材料", "Blacksmithing Supplies"},
    {"reagents", "施法材料商人", "施法材料", "Reagents"},
    {"trade", "商贸材料商人", "商贸供应商", "商贸材料", "Trade Supplies", "General Supplies"},
}
function NS.ClassifyQuestieNPC(raw, template)
    if template then
        return {category=template.category, service=template.service, tags=template.tags,
            catalogSubcategory=template.catalogSubcategory}
    end
    local title = NS.CleanText(raw.subName, 120)
    local flags = NS.Number(raw.flags) and raw.flags or 0
    local enum = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags or {}
    local function has(key)
        local flag = enum[key]
        return NS.Number(flag) and flag > 0 and math.floor(flags / flag) % 2 == 1
    end
    local function role(category, subgroup, fallback, tags)
        return {category=category, catalogSubcategory=category .. ":" .. subgroup,
            service=title ~= "" and title or fallback, tags=tags or fallback}
    end
    if has("TRAINER") then
        for _, class in ipairs(classTitles) do
            if title == class[2] .. "训练师" or title == "高级" .. class[2] .. "训练师"
                or title == class[3] .. " Trainer"
                or (class[1] == "rogue" and (title == "潜行者训练师" or title == "高级潜行者训练师")) then
                return role("trainers", class[1], class[2] .. "训练师", class[2] .. " 职业训练师 " .. class[3] .. " Trainer")
            end
        end
    end
    if has("TRAINER") and (title == "武器大师" or title == "Weapon Master") then
        return role("special","weapon-training","武器训练","武器大师 武器训练")
    end
    if title:find("军需官", 1, true) or title:find("Quartermaster", 1, true) then
        return {category="reputation", service=title, tags="军需官 声望 Quartermaster"}
    end
    if has("VENDOR") then
        for _, material in ipairs(materialTitles) do
            for i=2,#material do
                if title == material[i] then return role("materials",material[1],material[2],material[2]) end
            end
        end
    end
    for _, service in ipairs({
        {"FLIGHT_MASTER","flight-master","飞行管理员"}, {"INNKEEPER","innkeeper","旅店老板"},
        {"BANKER","banker","银行职员"}, {"AUCTIONEER","auctioneer","拍卖师"},
        {"STABLEMASTER","stable-master","兽栏管理员"}, {"TRAINER","trainer","其他训练师"},
        {"REPAIR","repair","修理"}, {"VENDOR","vendor","商人"},
    }) do
        if has(service[1]) then return role("services",service[2],service[3],service[3]) end
    end
    if type(raw.questStarts) == "table" and next(raw.questStarts)
        or type(raw.questEnds) == "table" and next(raw.questEnds) then
        return role("npcs","quest-contact","任务 NPC","任务 接取 交付")
    end
    if raw.friendly == nil then return role("npcs","hostile","怪物／敌对 NPC","怪物 敌对") end
    return role("npcs","other","其他 NPC","NPC")
end
