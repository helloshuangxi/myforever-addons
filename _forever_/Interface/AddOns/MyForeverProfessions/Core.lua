local _, ns = ...

local function number(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function integer(value)
    value = number(value)
    if value and value >= 0 then return math.floor(value) end
end

local function clamp(value, minimum, maximum, fallback)
    value = number(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

ns.PanelSize = {
    defaultWidth = 372, defaultHeight = 474,
    minWidth = 340, maxWidth = 900,
    minHeight = 260, maxHeight = 900,
}

-- SavedVariables can be hand edited. Copy plain serializable values only, and
-- bound damaged/cyclic caches without changing the caller's original table.
local function cleanCache(source)
    local seen, budget = {}, 30000
    local function copy(value, depth)
        local kind = type(value)
        if kind == "number" then return number(value) end
        if kind == "boolean" then return value end
        if kind == "string" then return #value <= 4096 and value or nil end
        if kind ~= "table" or depth > 10 or seen[value] then return nil end
        local result = {}
        seen[value] = true
        for key, child in pairs(value) do
            budget = budget - 1
            if budget < 0 then break end
            if (type(key) == "string" and #key <= 128) or number(key) then
                result[key] = copy(child, depth + 1)
            end
        end
        seen[value] = nil
        return result
    end
    return type(source) == "table" and copy(source, 0) or {}
end

local anchors = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Only these interaction settings belong to the nearby resource effect. Keep
-- the original value across reloads so switching it off can restore our edits.
local sparkleCVars = {
    SoftTargetInteract = true, SoftTargetIconGameObject = true,
    SoftTargetInteractArc = true, SoftTargetInteractRange = true,
}

local function cleanSparkleSettings(snapshots, overrides)
    local saved, suppressed = {}, {}
    for name in pairs(sparkleCVars) do
        local entry = type(snapshots) == "table" and snapshots[name]
        if type(entry) == "table" then
            local before, applied = entry.before, entry.applied
            if type(before) == "string" and #before <= 64 and number(tonumber(before))
                and type(applied) == "string" and #applied <= 64 and number(tonumber(applied)) then
                saved[name] = { before = before, applied = applied }
            end
        end
        if type(overrides) == "table" and overrides[name] == true then suppressed[name] = true end
    end
    return saved, suppressed
end

-- The only native tracking preference this scanner temporarily owns. Retain
-- an unfinished restoration across reloads without admitting arbitrary filters.
local function cleanQuestRestore(entry)
    local function public(v) return not (issecretvalue and issecretvalue(v)) end
    if not public(entry) or type(entry) ~= "table" then return nil end
    local id, before, applied = entry.filterID, entry.before, entry.applied
    if public(id) and public(before) and public(applied) and id == 65536 and before == true and applied == false then
        return {filterID = 65536, before = true, applied = false}
    end
end

function ns.NormalizeDB(raw)
    raw = type(raw) == "table" and raw or {}
    local sparkleSaved, sparkleOverrides = cleanSparkleSettings(raw.gatherSparkleCVars, raw.gatherSparkleOverrides)
    return {
        version = 1,
        shown = raw.shown ~= false,
        locked = raw.locked == true,
        collapsed = raw.collapsed == true,
        gatherAlerts = raw.gatherAlerts ~= false,
        gatherSound = raw.gatherSound ~= false,
        gatherSparkles = raw.gatherSparkles ~= false,
        gatherMethod = raw.gatherMethod == "original" and "original" or "cursor",
        gatherSparkleScale = clamp(raw.gatherSparkleScale, 0.6, 1.6, 1),
        gatherSparkleCVars = sparkleSaved,
        gatherSparkleOverrides = sparkleOverrides,
        gatherCursorQuestRestore = cleanQuestRestore(raw.gatherCursorQuestRestore),
        gatherPoint = anchors[raw.gatherPoint] and raw.gatherPoint or "CENTER",
        gatherRelativePoint = anchors[raw.gatherRelativePoint] and raw.gatherRelativePoint or "CENTER",
        gatherX = clamp(raw.gatherX, -10000, 10000, 0),
        gatherY = clamp(raw.gatherY, -10000, 10000, 170),
        gatherScale = clamp(raw.gatherScale, 0.7, 1.3, 1),
        scale = clamp(raw.scale, 0.65, 1.6, 1),
        windowWidth = math.floor(clamp(raw.windowWidth, ns.PanelSize.minWidth, ns.PanelSize.maxWidth, ns.PanelSize.defaultWidth) + 0.5),
        windowHeight = math.floor(clamp(raw.windowHeight, ns.PanelSize.minHeight, ns.PanelSize.maxHeight, ns.PanelSize.defaultHeight) + 0.5),
        point = anchors[raw.point] and raw.point or "CENTER",
        relativePoint = anchors[raw.relativePoint] and raw.relativePoint or "CENTER",
        x = clamp(raw.x, -10000, 10000, 300),
        y = clamp(raw.y, -10000, 10000, 0),
        cache = cleanCache(raw.cache),
    }
end

local difficulties = {
    optimal = "orange", orange = "orange",
    difficult = "red", red = "red",
    medium = "yellow", yellow = "yellow",
    easy = "green", green = "green",
    trivial = "gray", gray = "gray", grey = "gray",
}

function ns.Difficulty(value)
    if type(value) == "string" then return difficulties[string.lower(value)] or "unknown" end
    local enum = Enum and Enum.TradeskillRelativeDifficulty
    if number(value) and type(enum) == "table" then
        for key, enumValue in pairs(enum) do
            if value == enumValue and type(key) == "string" then
                return difficulties[string.lower(key)] or "unknown"
            end
        end
    end
    return "unknown"
end

local priorities = { orange = 1, yellow = 2, green = 3 }

function ns.RankRecipes(recipes)
    local ordered = {}
    for index, recipe in ipairs(type(recipes) == "table" and recipes or {}) do
        if type(recipe) == "table" and recipe.learned == true and recipe.canSkillUp ~= false
            and recipe.available ~= false and (not number(recipe.cooldown) or recipe.cooldown <= 0)
            and priorities[ns.Difficulty(recipe.difficulty)] then
            ordered[#ordered + 1] = { recipe = recipe, index = index }
        end
    end
    table.sort(ordered, function(a, b)
        local left, right = a.recipe, b.recipe
        local leftColor, rightColor = priorities[ns.Difficulty(left.difficulty)], priorities[ns.Difficulty(right.difficulty)]
        if leftColor ~= rightColor then return leftColor < rightColor end
        local leftCount, rightCount = integer(left.craftable) or 0, integer(right.craftable) or 0
        if (leftCount > 0) ~= (rightCount > 0) then return leftCount > 0 end
        if leftCount ~= rightCount then return leftCount > rightCount end
        local leftName, rightName = tostring(left.name or ""), tostring(right.name or "")
        if leftName ~= rightName then return leftName < rightName end
        local leftID, rightID = tostring(left.id or ""), tostring(right.id or "")
        if leftID ~= rightID then return leftID < rightID end
        return a.index < b.index
    end)
    local result = {}
    for index, entry in ipairs(ordered) do result[index] = entry.recipe end
    return result
end

local function readCount(itemID, fallback, countFn)
    if type(countFn) == "function" and itemID then
        local ok, value = pcall(countFn, itemID)
        if ok then return integer(value) end
        return nil
    end
    return integer(fallback)
end

function ns.MaterialSummary(recipe, countFn)
    recipe = type(recipe) == "table" and recipe or {}
    local result = { reagents = {}, complete = recipe.reagentsComplete ~= false }
    local materials = recipe.reagents
    if type(materials) ~= "table" then result.complete = false; return result end
    local perItem, optionsUsed, singleRows, craftable = {}, {}, {}, nil
    local function cap(value)
        if value ~= nil then craftable = craftable and math.min(craftable, value) or value end
    end
    for _, reagent in ipairs(materials) do
        if type(reagent) ~= "table" then
            result.complete = false
        else
            local required = integer(reagent.required)
            local row = { name = reagent.name, itemID = reagent.itemID, required = required }
            result.reagents[#result.reagents + 1] = row
            if not required or required == 0 then
                row.unknown = true
                result.complete = false
            end
            local options = type(reagent.options) == "table" and reagent.options or nil
            if options and #options > 0 then
                row.options = {}
                local optionIDs, totalCrafts, bestOwned, allKnown = {}, 0, 0, true
                for _, option in ipairs(options) do
                    local id = type(option) == "table" and integer(option.itemID)
                    if id and id > 0 and not optionIDs[id] then
                        optionIDs[id] = true
                        local owned = readCount(id, option.owned, countFn)
                        row.options[#row.options + 1] = { itemID = id, name = option.name, owned = owned,
                            missing = owned and required and math.max(0, required - owned) or nil }
                        if owned then
                            bestOwned = math.max(bestOwned, owned)
                            if required and required > 0 then totalCrafts = totalCrafts + math.floor(owned / required) end
                        else allKnown = false end
                        if optionsUsed[id] or perItem[id] then row.ambiguous = true; result.complete = false end
                        optionsUsed[id] = true
                    elseif not id or id == 0 then
                        allKnown = false
                    end
                end
                if #row.options == 0 then allKnown = false end
                -- One craft must use one choice; two partial choices do not
                -- silently become enough material for a single operation.
                row.owned = allKnown and bestOwned or nil
                row.missing = row.owned and required and math.max(0, required - row.owned) or nil
                if not allKnown then row.unknown = true; result.complete = false end
                if allKnown then cap(totalCrafts) end
            else
                local id = integer(reagent.itemID)
                row.owned = readCount(id and id > 0 and id or nil, reagent.owned, countFn)
                row.missing = row.owned and required and math.max(0, required - row.owned) or nil
                if id and id > 0 and required and required > 0 then
                    if optionsUsed[id] then row.ambiguous = true; result.complete = false end
                    local item = perItem[id] or { required = 0, owned = row.owned }
                    item.required = item.required + required
                    if item.owned ~= row.owned then item.owned = nil end
                    perItem[id] = item
                    local existing = singleRows[id]
                    if existing then
                        existing.required = existing.required + required
                        if existing.owned ~= row.owned then existing.owned = nil end
                        existing.missing = existing.owned and math.max(0, existing.required - existing.owned) or nil
                        existing.ambiguous = existing.ambiguous or row.ambiguous
                        existing.mergedSlots = true
                        table.remove(result.reagents)
                    else
                        singleRows[id] = row
                    end
                elseif required and required > 0 then
                    -- A missing item ID prevents safe de-duplication across
                    -- slots even if the API supplied an owned count.
                    row.unknown = true
                    result.complete = false
                end
                if row.owned == nil then row.unknown = true; result.complete = false end
            end
        end
    end
    for _, item in pairs(perItem) do
        if item.owned == nil then result.complete = false
        else cap(math.floor(item.owned / item.required)) end
    end
    result.craftable = result.complete and craftable or nil
    result.noMaterials = #materials == 0 and result.complete
    return result
end

function ns.Progress(profession)
    profession = type(profession) == "table" and profession or {}
    local rank = integer(profession.rank)
    local maxRank = integer(profession.maxRank)
    if not rank or not maxRank or maxRank == 0 then
        return { rank = rank, maxRank = maxRank, text = "技能点数暂不可用" }
    end
    local remaining = math.max(0, maxRank - rank)
    local text = string.format("当前 %d/%d · 距上限 %d 点", rank, maxRank, remaining)
    if remaining == 0 then text = text .. "（已达当前上限）" end
    return { rank = rank, maxRank = maxRank, remaining = remaining,
        nextPoint = remaining > 0 and rank + 1 or nil, text = text }
end

function ns.GatheringAdvice(profession)
    profession = type(profession) == "table" and profession or {}
    if profession.id == 182 then
        return "采集草药时优先橘红色，再选黄色、绿色目标；以游戏显示的采集难度为准。"
    elseif profession.id == 186 then
        return "优先采集橘红色矿脉，其次黄色、绿色；也可打开采矿查看能提升技能的熔炼配方。"
    elseif profession.id == 393 then
        return "选择可剥皮的野兽，优先橘红色，其次黄色、绿色；以目标显示的剥皮难度为准。"
    elseif profession.id == 356 then
        return "打开钓鱼专业读取可训练项目；在可垂钓水域成功钓获继续练习，升 1 点所需次数不固定。"
    elseif profession.kind == "gathering" then
        return "优先选择可采集的橘红色目标，其次黄色、绿色；具体难度以游戏显示为准。"
    end
    return "请先打开一次本角色的原生专业窗口，读取已学配方与材料。"
end
