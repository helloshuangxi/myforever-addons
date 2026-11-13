-- Lua 5.1 simulated client contracts. These checks do not constitute in-game validation.
local checks, failures = 0, {}
local function eq(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        failures[#failures + 1] = (label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
    end
end
local prefix = "_forever_/Interface/AddOns/MyForeverProfessions/"
local function loadNamespace()
    local ns = {}
    assert(loadfile(prefix .. "Core.lua"))("MyForeverProfessions", ns)
    assert(loadfile(prefix .. "API.lua"))("MyForeverProfessions", ns)
    ns.db = ns.NormalizeDB(nil)
    return ns
end
Enum = {
    TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 },
    CraftingReagentType = { Basic = 0, Modifying = 1, Finishing = 2 },
}
local now = 100
GetTime = function() return now end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
C_Spell = { GetSpellInfo = function(id) return id and { iconID = id + 1 } or nil end }
local allIDs = {171, 164, 333, 202, 165, 197, 182, 186, 393, 185, 129, 356}
local skillRecords = {}
for _, id in ipairs(allIDs) do skillRecords[id] = { name = "专业 " .. id, rank = 40, maxRank = 75, modifier = 0 } end
local indexToSkill = { [1] = 171, [3] = 129, [4] = 356, [5] = 185 }
GetProfessions = function() return 1, nil, 3, 4, 5 end
GetProfessionInfo = function(index)
    local id = indexToSkill[index]
    local record = skillRecords[id]
    return record.name, 10, record.rank, record.maxRank, 2, 100, id, record.modifier
end
C_SkillInfo = nil
local ns = loadNamespace()
local professions, ready = ns.ReadProfessions()
eq(ready, true, "profession enumeration ready")
eq(#professions, 4, "holes do not truncate secondary professions")
local detected = {}
for _, profession in ipairs(professions) do detected[profession.id] = profession end
eq(detected[129] and detected[129].rank, 40, "first aid after nil primary")
eq(detected[356] and detected[356].kind, "gathering", "fishing after nil primary")
eq(detected[185] and detected[185].kind, "crafting", "cooking after nil primary")

C_SkillInfo = { GetSkillLineInfoByID = function(id) return skillRecords[id] end }
professions, ready = ns.ReadProfessions()
eq(#professions, 12, "all twelve recognized profession skill lines")
for i, id in ipairs(allIDs) do eq(professions[i].id, id, "stable profession order " .. id) end
eq(professions[7].kind, "gathering", "herbalism classified")
eq(professions[8].kind, "gathering", "mining classified")
eq(professions[9].kind, "gathering", "skinning classified")
skillRecords[197].isHeader = true
eq(#ns.ReadProfessions(), 11, "skill headers excluded")
skillRecords[197].isHeader = nil
local savedProfessions, savedSkills = GetProfessions, C_SkillInfo
GetProfessions = function() error("not ready") end
C_SkillInfo = { GetSkillLineInfoByID = function() error("not ready") end }
professions, ready = ns.ReadProfessions()
eq(ready, false, "failed APIs not an authoritative empty character")
eq(#professions, 0, "no fabricated professions on failure")
GetProfessions, C_SkillInfo = savedProfessions, savedSkills
ns.professions = ns.ReadProfessions()

local inventory, countArgs, requests = { [1001] = 3, [1002] = 40, [1003] = 1 }, {}, {}
C_Item = {
    GetItemNameByID = function(id) return id ~= 9999 and ("材料 " .. id) or nil end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
    GetItemCount = function(id, bank, uses, reagentBank, accountBank)
        countArgs = { id, bank, uses, reagentBank, accountBank }
        return inventory[id] or 0
    end,
}
eq(ns.ItemCount(1001), 3, "live bag inventory")
for i = 2, 5 do eq(countArgs[i], false, "exclude non-bag count flag " .. i) end
eq(ns.ItemName(9999), "物品 #9999", "unloaded item gets explicit placeholder")
ns.ItemName(9999)
eq(requests[9999], 1, "item load request deduplicated")
eq(ns.ItemCount({secret = true}), nil, "secret inventory input ignored")

local infos = {
    [101] = { name = "橙色缺料", learned = true, canSkillUp = true, relativeDifficulty = 0 },
    [102] = { name = "黄色齐料", learned = true, canSkillUp = true, relativeDifficulty = 1 },
    [103] = { name = "绿色齐料", learned = true, canSkillUp = true, relativeDifficulty = 2 },
    [104] = { name = "灰色", learned = true, canSkillUp = false, relativeDifficulty = 3 },
    [105] = { name = "未学", learned = false, canSkillUp = true, relativeDifficulty = 0 },
    [106] = { name = "不可用", learned = true, canSkillUp = true, disabled = true, relativeDifficulty = 0 },
    [107] = { name = "采集项目", learned = true, canSkillUp = true, relativeDifficulty = 0,
        isGatheringRecipe = true, currentRecipeExperience = 45, nextLevelRecipeExperience = 100 },
    [108] = { name = "再造", learned = true, isRecraft = true, relativeDifficulty = 0 },
    [109] = { name = "占位", learned = true, isDummyRecipe = true, relativeDifficulty = 0 },
    [110] = { name = "冷却中", learned = true, canSkillUp = true, relativeDifficulty = 0 },
}
local schematics = {}
for id in pairs(infos) do schematics[id] = { reagentSlotSchematics = {
    { required = true, reagentType = 0, quantityRequired = id == 101 and 4 or 2,
      reagents = { { itemID = id == 101 and 1001 or 1002 } } },
} } end
local currentID, parentID, isReady, guardFlags = 171, nil, true, {}
local recipeIDs = { 101, 102, 103, 104, 105, 106, 108, 109, 110 }
local filteredIDs, readIDs = { 102 }, {}
C_TradeSkillUI = {
    IsTradeSkillReady = function() return isReady end,
    GetBaseProfessionInfo = function() return { professionID = currentID, parentProfessionID = parentID } end,
    GetRecipeInfo = function(id) readIDs[#readIDs + 1] = id; return infos[id] end,
    GetRecipeSchematic = function(id, recraft) eq(recraft, false, "normal craft schematic " .. id); return schematics[id] end,
    GetRecipeCooldown = function(id) if id == 110 then return 30, false, 0 end return 0 end,
    GetAllRecipeIDs = function() local out = {}; for i, id in ipairs(recipeIDs) do out[i] = id end; return out end,
    GetFilteredRecipeIDs = function() local out = {}; for i, id in ipairs(filteredIDs) do out[i] = id end; return out end,
}
for _, guard in ipairs({"IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting"}) do
    C_TradeSkillUI[guard] = function() return guardFlags[guard] or false end
end
eq(ns.CurrentProfessionID(), 171, "known current profession")
ns.dataSourceChanging = true
eq(ns.CurrentProfessionID(), nil, "source transition cannot be scanned")
eq(ns.ScanCurrentProfession(), false, "source transition cannot populate cache")
ns.dataSourceChanging = false
currentID = 999
eq(ns.CurrentProfessionID(), nil, "unknown current ID rejected")
currentID, parentID = 10000, 171
eq(ns.CurrentProfessionID(), 171, "child resolves known parent")
currentID, parentID = 171, nil
isReady = false
eq(ns.CurrentProfessionID(), nil, "not ready rejected")
eq(ns.ScanCurrentProfession(), false, "not ready scan deferred")
eq(ns.db.cache[171], nil, "not ready cannot create cache")
isReady = true
eq(ns.ScanCurrentProfession(), true, "own recipe scan succeeds")
local originalCache = ns.db.cache[171]
for guard in pairs(C_TradeSkillUI) do
    if guard:find("^Is") and guard ~= "IsTradeSkillReady" then
        guardFlags[guard] = true
        eq(ns.CurrentProfessionID(), nil, guard .. " external source rejected")
        eq(ns.ScanCurrentProfession(), false, guard .. " scan rejected")
        eq(ns.db.cache[171], originalCache, guard .. " original cache retained")
        guardFlags[guard] = false
    end
end

ns.AttachRecommendations()
local alchemy = ns.professions[1]
eq(alchemy.cacheState, "fresh", "newly read cache fresh")
eq(#alchemy.recipes, 3, "remove gray unlearned disabled dummy recraft cooldown")
eq(alchemy.recipes[1].id, 101, "orange still wins when missing materials")
eq(alchemy.recipes[1].reagents[1].missing, 1, "manufacturing exact material shortage")
eq(alchemy.recipes[2].id, 102, "yellow second")
eq(alchemy.recipes[2].craftable, 20, "manufacturing bag craft count")
eq(alchemy.recipes[3].id, 103, "green third")
now = 131
ns.AttachRecommendations()
eq(#alchemy.recipes, 4, "cooldown expires without needing open window")
eq(alchemy.recipes[1].id, 110, "ready orange preferred within orange")

-- A shared recipe list can contain a foreign skill-line entry. Explicit false
-- from the ownership API must not fall through to ReadRecipe via Lua's and/or.
infos[999] = { name = "另一专业配方", learned = true, canSkillUp = true, relativeDifficulty = 0 }
recipeIDs[#recipeIDs + 1] = 999
C_TradeSkillUI.IsRecipeInSkillLine = function(recipeID, skillLineID)
    eq(skillLineID, 171, "ownership check uses current profession")
    return recipeID ~= 999
end
readIDs = {}
eq(ns.ScanCurrentProfession(), true, "foreign entry does not block own scan")
local readForeign = false
for _, recipeID in ipairs(readIDs) do if recipeID == 999 then readForeign = true end end
eq(readForeign, false, "foreign recipe never read")
local cachedForeign = false
for _, recipe in ipairs(ns.db.cache[171].recipes) do if recipe.id == 999 then cachedForeign = true end end
eq(cachedForeign, false, "foreign recipe never cached")
table.remove(recipeIDs)
C_TradeSkillUI.IsRecipeInSkillLine = nil

local gathering = ns.ReadRecipe(107)
eq(gathering.reagentsComplete, true, "gathering needs no manufacturing materials")
eq(#gathering.reagents, 0, "gathering empty materials")
eq(gathering.currentRecipeExperience, 45, "gathering current XP retained")
eq(gathering.nextLevelRecipeExperience, 100, "gathering next-level XP retained")
eq(#ns.RankRecipes({ gathering }), 1, "gathering project recommended")

schematics[102].reagentSlotSchematics = {
    { required = true, reagentType = 0, quantityRequired = 2, slotInfo = { slotText = "选一种金属" },
      reagents = { { itemID = 1001 }, { itemID = 1002 } } },
    { required = false, reagentType = 1, quantityRequired = 1, reagents = { { itemID = 1003 } } },
}
local alternative = ns.ReadRecipe(102)
eq(#alternative.reagents, 1, "optional reagent slot excluded")
eq(#alternative.reagents[1].options, 2, "alternative slot retained as choices")
local summary = ns.MaterialSummary(alternative, ns.ItemCount)
eq(summary.craftable, 21, "alternative complete batches independent")
eq(summary.reagents[1].required, 2, "alternatives do not multiply required quantity")
schematics[102].reagentSlotSchematics[2].reagentType = 0
alternative = ns.ReadRecipe(102)
eq(#alternative.reagents, 1, "explicit optional false wins over basic enum")
schematics[102].reagentSlotSchematics[2].reagentType = 1
schematics[103].reagentSlotSchematics = {
    { required = true, reagentType = 0, quantityRequired = 3, reagents = { { currencyID = 456 } } },
}
eq(ns.ReadRecipe(103).reagentsComplete, false, "currency slot is transparently incomplete")

local allReader = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = nil
C_TradeSkillUI.GetFilteredRecipeIDs = function() return filteredIDs end
eq(ns.ScanCurrentProfession(), true, "filtered reader merges prior recipes")
eq(#filteredIDs, 1, "scan does not mutate API-owned filtered array")
eq(#ns.db.cache[171].recipes, #originalCache.recipes, "filter does not erase known recipes")
eq(ns.db.cache[171].scope, "filtered", "filtered scope retained")
ns.AttachRecommendations()
eq(alchemy.status ~= nil, true, "filtered recommendation limitation visible")
C_TradeSkillUI.GetAllRecipeIDs = function() return {} end
local beforeEmpty = ns.db.cache[171]
eq(ns.ScanCurrentProfession(), false, "transient empty result deferred")
eq(ns.db.cache[171], beforeEmpty, "transient empty does not erase cache")
ns.AttachRecommendations()
eq(alchemy.cacheState, "stale", "transient empty marks data stale")
C_TradeSkillUI.GetAllRecipeIDs = allReader
eq(ns.ScanCurrentProfession(), true, "recovered source can refresh")
local savedInfo = infos[101]
infos[101] = nil
local beforePartial = ns.db.cache[171]
eq(ns.ScanCurrentProfession(), false, "partial recipe load deferred")
eq(ns.db.cache[171], beforePartial, "partial recipe load retains previous cache")
infos[101] = savedInfo
ns.ScanCurrentProfession()
alchemy.rank = 41
ns.AttachRecommendations()
eq(alchemy.cacheState, "stale", "skill gain invalidates recorded difficulty")
alchemy.rank = 75
ns.AttachRecommendations()
eq(#alchemy.recipes, 0, "current skill cap suppresses pointless training")
alchemy.rank = 40
ns.ScanCurrentProfession()
alchemy.modifier = 5
ns.AttachRecommendations()
eq(alchemy.cacheState, "stale", "skill modifier invalidates difficulty")
alchemy.modifier = 0
ns.ScanCurrentProfession()
ns.InvalidateRecipes()
ns.AttachRecommendations()
eq(alchemy.cacheState, "stale", "explicit source invalidation")
local resumed = loadNamespace()
resumed.db = resumed.NormalizeDB(ns.db)
resumed.professions = resumed.ReadProfessions()
resumed.AttachRecommendations()
eq(resumed.professions[1].cacheState, "stale", "saved cache is not called fresh after reload")

-- Exercise actual Main event integration with lightweight UI stand-ins.
local main = loadNamespace()
local frame = { scripts = {}, events = {} }
function frame:SetScript(event, callback) self.scripts[event] = callback end
function frame:RegisterEvent(event) self.events[event] = true end
CreateFrame = function() return frame end
SlashCmdList = {}
local renders, uiCreates, paused = 0, 0, false
InCombatLockdown = function() return paused end
main.CreateUI = function() uiCreates = uiCreates + 1 end
main.RenderUI = function() renders = renders + 1 end
main.SetScale = function(scale) main.db.scale = scale end
MyForeverProfessionsDB = { shown = false, scale = 1.2, cache = ns.db.cache }
assert(loadfile(prefix .. "Main.lua"))("MyForeverProfessions", main)
frame.scripts.OnEvent(frame, "ADDON_LOADED", "OtherAddon")
eq(uiCreates, 0, "another addon load cannot initialize")
frame.scripts.OnEvent(frame, "ADDON_LOADED", "MyForeverProfessions")
eq(uiCreates, 1, "initialize once for own addon")
eq(main.db.shown, false, "per-character hidden setting retained")
eq(main.db.scale, 1.2, "per-character scale retained")
frame.scripts.OnEvent(frame, "PLAYER_LOGIN")
frame.scripts.OnUpdate(frame, 1)
eq(uiCreates, 1, "login does not recreate UI")
eq(#main.professions, 12, "main detects character professions")
paused = true
main.Refresh(true)
eq(main.combatPaused, true, "combat defers data scanning")
paused = false
frame.scripts.OnEvent(frame, "PLAYER_REGEN_ENABLED")
frame.scripts.OnUpdate(frame, 2)
eq(main.combatPaused, false, "post combat refresh resumes")
skillRecords[164] = nil
main.db.cache[164] = { recipes = { { id = 900, name = "old" } } }
frame.scripts.OnEvent(frame, "SKILL_LINES_CHANGED")
frame.scripts.OnUpdate(frame, 2)
eq(main.db.cache[164] ~= nil, true, "one missing skill read does not erase saved cache")
frame.scripts.OnUpdate(frame, 2)
eq(main.db.cache[164], nil, "unlearned character profession cache removed")
eq(#main.professions, 11, "unlearned profession removed from panel model")
eq(main.db == MyForeverProfessionsDB, true, "main uses per-character saved variable")

for _, failure in ipairs(failures) do print("FAIL: " .. failure) end
assert(#failures == 0, #failures .. " profession API test failures out of " .. checks .. " checks")
print("MyForeverProfessions API/events: " .. checks .. " simulated checks passed")
