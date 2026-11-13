local _, ns = ...

-- Forever 1.60.1: read the player's skill lines independently of the open
-- profession. Recipes belong to the current trade-skill data source only.
local definitions = {
    {171, "炼金术", "crafting", 2259}, {164, "锻造", "crafting", 2018},
    {333, "附魔", "crafting", 7411}, {202, "工程学", "crafting", 4036},
    {165, "制皮", "crafting", 2108}, {197, "裁缝", "crafting", 3908},
    {182, "草药学", "gathering", 9134}, {186, "采矿", "gathering", 2575},
    {393, "剥皮", "gathering", 8613}, {185, "烹饪", "crafting", 2550},
    {129, "急救", "crafting", 3273}, {356, "钓鱼", "gathering", 7620},
}
local byID, order = {}, {}
for i, definition in ipairs(definitions) do byID[definition[1]], order[definition[1]] = definition, i end
local sessionFresh, itemRequested = {}, {}

function ns.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
end
local call = ns.SafeCall
local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end
local function positive(value) return number(value) and value > 0 end
local function timeNow() return call(GetTime) or 0 end
local function copy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 6 then return nil end
    local out = {}
    for k, v in pairs(value) do
        if type(k) == "string" or type(k) == "number" then out[k] = copy(v, (depth or 0) + 1) end
    end
    return out
end

function ns.ReadProfessions()
    local found, ready = {}, false
    local function add(id, name, icon, rank, maximum, modifier)
        if not positive(id) or not positive(maximum) or not number(rank) then return end
        local definition = byID[id]
        local info = call(C_Spell and C_Spell.GetSpellInfo, definition and definition[4])
        found[id] = {id = id, name = name or (definition and definition[2]) or ("专业 " .. id),
            icon = icon or (info and info.iconID), rank = rank, maxRank = maximum,
            modifier = number(modifier) and modifier or 0,
            kind = definition and definition[3] or "crafting"}
    end
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local values = {pcall(GetProfessions)}
        if values[1] then
            ready = true
            -- Do not use ipairs: an unlearned primary profession leaves a hole.
            for i = 2, 8 do
                if positive(values[i]) then
                    local name, icon, rank, maximum, _, _, id, modifier = call(GetProfessionInfo, values[i])
                    add(id, name, icon, rank, maximum, modifier)
                end
            end
        end
    end
    if C_SkillInfo and type(C_SkillInfo.GetSkillLineInfoByID) == "function" then
        for _, definition in ipairs(definitions) do
            local ok, skill = pcall(C_SkillInfo.GetSkillLineInfoByID, definition[1])
            if ok then ready = true end
            if ok and type(skill) == "table" and not skill.isHeader then
                local existing = found[definition[1]]
                add(definition[1], skill.name, existing and existing.icon, skill.rank, skill.maxRank, skill.modifier)
            end
        end
    end
    local result = {}
    for _, profession in pairs(found) do result[#result + 1] = profession end
    -- An empty successful API response also occurs before character skills load.
    -- Weapon/language skill rows establish that an actually empty profession list
    -- is meaningful; never interpret the login placeholder as an unlearn event.
    if #result == 0 then
        local count = call(C_SkillInfo and C_SkillInfo.GetNumSkillLines or GetNumSkillLines)
        ready = ready and positive(count) or false
    end
    table.sort(result, function(a, b)
        local aa, bb = order[a.id] or 99, order[b.id] or 99
        if aa ~= bb then return aa < bb end
        return a.id < b.id
    end)
    return result, ready
end

-- Display-only secondary-skill entries must never be treated as learned skills
-- by recipe scanning, cache invalidation, or the forget-profession logic.
function ns.DisplayProfessions(professions, ready)
    professions = type(professions) == "table" and professions or {}
    local result, secondary = {}, {}
    local secondaryOrder = {185, 129, 356}
    local secondarySet = {[185] = true, [129] = true, [356] = true}
    for _, profession in ipairs(professions) do
        if secondarySet[profession.id] then secondary[profession.id] = profession
        else result[#result + 1] = profession end
    end
    for _, id in ipairs(secondaryOrder) do
        if secondary[id] then
            result[#result + 1] = secondary[id]
        elseif ready == true then
            local definition = byID[id]
            local info = call(C_Spell and C_Spell.GetSpellInfo, definition[4])
            result[#result + 1] = {id = id, name = definition[2], kind = definition[3],
                icon = info and info.iconID, unlearned = true, recipes = {}}
        end
    end
    return result
end

function ns.ItemName(id)
    if not positive(id) then return "材料信息待加载" end
    local name = call(C_Item and C_Item.GetItemNameByID, id) or call(GetItemInfo, id)
    if type(name) == "string" and name ~= "" then return name end
    if not itemRequested[id] then
        itemRequested[id] = true
        call(C_Item and C_Item.RequestLoadItemDataByID, id)
    end
    return "物品 #" .. id
end

function ns.ItemCount(id)
    if not positive(id) then return nil end
    -- Bags only, never present bank/warband reagents as available on the player.
    local value = call(C_Item and C_Item.GetItemCount or GetItemCount, id, false, false, false, false)
    return number(value) and math.max(0, value) or nil
end

function ns.ReadRecipe(id)
    local api = C_TradeSkillUI
    if not api then return nil end
    local info = call(api.GetRecipeInfo, id)
    if type(info) ~= "table" then return nil end
    if type(info.learned) ~= "boolean" then return nil end
    if info.learned ~= true or info.isRecraft or info.isDummyRecipe then return false end
    local recipe = {id = id, name = info.name or ("配方 #" .. id), learned = true,
        difficulty = ns.Difficulty(info.relativeDifficulty), canSkillUp = info.canSkillUp,
        available = not info.disabled, numSkillUps = info.numSkillUps,
        isGatheringRecipe = info.isGatheringRecipe == true, reagents = {}, reagentsComplete = false,
        currentRecipeExperience = info.currentRecipeExperience, nextLevelRecipeExperience = info.nextLevelRecipeExperience}
    local cooldown, _, charges = call(api.GetRecipeCooldown, id)
    recipe.cooldown = positive(cooldown) and not positive(charges) and cooldown or 0
    recipe.cooldownEnd = timeNow() + recipe.cooldown
    if recipe.isGatheringRecipe then
        recipe.reagentsComplete = true
        return recipe
    end
    local schematic = call(api.GetRecipeSchematic, id, false)
    if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then return recipe end
    recipe.reagentsComplete = true
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.required == true or (slot.required == nil and basic ~= nil and slot.reagentType == basic) then
            local material = {required = slot.quantityRequired, options = {}}
            if type(slot.reagents) == "table" then
                for _, reagent in ipairs(slot.reagents) do
                    if positive(reagent.itemID) then
                        material.options[#material.options + 1] = {itemID = reagent.itemID, name = ns.ItemName(reagent.itemID)}
                    else
                        recipe.reagentsComplete = false
                        material.name = reagent.currencyID and ("货币 #" .. reagent.currencyID) or "特殊材料（请查看专业）"
                    end
                end
            end
            if #material.options == 1 then
                material.itemID, material.name = material.options[1].itemID, material.options[1].name
                material.options = nil
            elseif #material.options > 1 then
                material.name = (slot.slotInfo and slot.slotInfo.slotText) or "可替代材料"
            else
                material.options = nil
                recipe.reagentsComplete = false
            end
            if not positive(material.required) then recipe.reagentsComplete = false end
            recipe.reagents[#recipe.reagents + 1] = material
        end
    end
    return recipe
end

function ns.CurrentProfessionID()
    local api = C_TradeSkillUI
    if not api or ns.dataSourceChanging then return nil end
    for _, guard in ipairs({"IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting"}) do
        if call(api[guard]) then return nil end
    end
    if type(api.IsTradeSkillReady) == "function" and call(api.IsTradeSkillReady) ~= true then return nil end
    local info = call(api.GetBaseProfessionInfo) or call(api.GetChildProfessionInfo)
    if type(info) ~= "table" then return nil end
    local id = info.parentProfessionID or info.professionID
    for _, profession in ipairs(ns.professions or {}) do
        if profession.id == id then return id, profession end
    end
end

function ns.ScanCurrentProfession()
    local id, profession = ns.CurrentProfessionID()
    if not id then return false end
    local api = C_TradeSkillUI
    local ids, scope
    if type(api.GetAllRecipeIDs) == "function" then ids = call(api.GetAllRecipeIDs); scope = "all" end
    if type(ids) ~= "table" then ids = call(api.GetFilteredRecipeIDs); scope = "filtered" end
    if type(ids) ~= "table" then return false end
    -- API-owned arrays may be reused by Blizzard; never append into that table.
    local input = ids
    ids = {}
    for _, recipeID in ipairs(input) do ids[#ids + 1] = recipeID end
    local cache = ns.db.cache[id]
    local entries, complete, seen = {}, true, {}
    -- Filtered lists must not erase recipes that were previously seen.
    if scope == "filtered" and type(cache) == "table" and type(cache.recipes) == "table" then
        for _, recipe in ipairs(cache.recipes) do
            if type(recipe) == "table" and positive(recipe.id) then seen[recipe.id] = true; ids[#ids + 1] = recipe.id end
        end
    end
    seen = {}
    for _, recipeID in ipairs(ids) do
        if positive(recipeID) and not seen[recipeID] then
            seen[recipeID] = true
            local belongs = call(api.IsRecipeInSkillLine, recipeID, id)
            local recipe
            if belongs == false then recipe = false else recipe = ns.ReadRecipe(recipeID) end
            if recipe == nil then complete = false
            elseif recipe then entries[#entries + 1] = recipe end
        end
    end
    if #ids == 0 and cache and type(cache.recipes) == "table" and #cache.recipes > 0 then
        sessionFresh[id] = nil
        return false
    end
    if not complete and cache then sessionFresh[id] = nil; return false end
    ns.db.cache[id] = {recipes = entries, rank = profession.rank, maxRank = profession.maxRank,
        modifier = profession.modifier, scope = scope, complete = complete}
    sessionFresh[id] = complete or nil
    return complete
end

function ns.InvalidateRecipes()
    for id in pairs(sessionFresh) do sessionFresh[id] = nil end
end

function ns.AttachRecommendations()
    for _, profession in ipairs(ns.professions or {}) do
        local cache = ns.db.cache[profession.id]
        profession.recipes, profession.cacheState = {}, "missing"
        if type(cache) == "table" and type(cache.recipes) == "table" then
            local fresh = sessionFresh[profession.id] and cache.rank == profession.rank
                and cache.maxRank == profession.maxRank and cache.modifier == profession.modifier
            profession.cacheState = fresh and "fresh" or "stale"
            profession.status = cache.scope == "filtered" and "根据已读取的配方推荐；原生筛选可能隐藏其他项目。" or nil
            local recipes = {}
            for _, stored in ipairs(cache.recipes) do
                if type(stored) == "table" and positive(stored.id) then
                    local recipe = copy(stored)
                    if fresh and number(recipe.cooldownEnd) then recipe.cooldown = math.max(0, recipe.cooldownEnd - timeNow()) end
                    for _, material in ipairs(recipe.reagents or {}) do
                        if material.itemID then material.name = ns.ItemName(material.itemID) end
                        for _, option in ipairs(material.options or {}) do option.name = ns.ItemName(option.itemID) end
                    end
                    local summary = ns.MaterialSummary(recipe, ns.ItemCount)
                    recipe.reagents, recipe.craftable, recipe.reagentsComplete = summary.reagents, summary.craftable, summary.complete
                    recipes[#recipes + 1] = recipe
                end
            end
            if profession.rank < profession.maxRank then profession.recipes = ns.RankRecipes(recipes) end
        end
    end
end

function ns.OpenProfession(id)
    if call(InCombatLockdown) then ns.Print("战斗结束后再打开专业。面板仍会保留。"); return false end
    local known
    for _, profession in ipairs(ns.professions or {}) do if profession.id == id then known = true; break end end
    if not known then return false end
    if type(ProfessionsFrame_LoadUI) == "function" then call(ProfessionsFrame_LoadUI)
    else call(C_AddOns and C_AddOns.LoadAddOn or LoadAddOn, "Blizzard_Professions") end
    local opened = call(C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill, id)
    if opened then
        ns.QueueRefresh(0.2, true)
        return true
    end
    ns.Print("请从游戏技能书打开该专业，助手会自动读取项目。")
    return false
end
