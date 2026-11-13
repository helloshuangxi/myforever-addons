-- Lua 5.1; run from the World of Warcraft installation root.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local ns = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/Core.lua"))("MyForeverProfessions", ns)

local db = ns.NormalizeDB(nil)
eq(db.shown, true, "default visible")
eq(db.scale, 1, "default scale")
eq(db.gatherMethod, "cursor", "local candidate defaults to the explicitly authorized stand-in experiment")
eq(ns.NormalizeDB({gatherMethod="original"}).gatherMethod, "original", "original reader remains an explicit fallback")
eq(ns.NormalizeDB({gatherMethod="cursor"}).gatherMethod, "cursor", "experiment mode persists")
eq(ns.NormalizeDB({gatherMethod={}}).gatherMethod, "cursor", "invalid reader preference repaired")
eq(db.windowWidth, 372, "default window width")
eq(db.windowHeight, 474, "default window height")
eq(db.collapsed, false, "default expanded")
eq(ns.NormalizeDB({ collapsed = true }).collapsed, true, "saved collapse")
eq(db.x, 300, "default x")
local cache = { [164] = { recipes = { { name = "铜质护腕", id = 2663 } } } }
cache.loop = cache
db = ns.NormalizeDB({ shown = false, locked = true, scale = 0 / 0, x = math.huge,
    y = -20000, point = "BAD", relativePoint = "TOPRIGHT", cache = cache })
eq(db.shown, false, "saved hidden")
eq(db.locked, true, "saved lock")
eq(db.scale, 1, "NaN repaired")
eq(db.x, 300, "infinity repaired")
eq(db.y, -10000, "position bounded")
eq(db.point, "CENTER", "bad anchor repaired")
eq(db.relativePoint, "TOPRIGHT", "relative anchor retained")
eq(db.cache.loop, nil, "cyclic cache removed")
eq(db.cache[164].recipes[1].name, "铜质护腕", "recipe cache retained")
eq(db.cache == cache, false, "cache copied")
eq(ns.NormalizeDB({ scale = 100 }).scale, 1.6, "maximum scale")
eq(ns.NormalizeDB({ scale = 0 }).scale, 0.65, "minimum scale")
local window = ns.NormalizeDB({ windowWidth = 699.6, windowHeight = 799.2, scale = 1.25,
    gatherAlerts = false, gatherSound = false, gatherSparkles = false })
eq(window.windowWidth, 700, "window width saved as pixels")
eq(window.windowHeight, 799, "window height saved as pixels")
eq(window.scale, 1.25, "window dimensions independent of saved font scale")
eq(window.gatherAlerts, false, "window migration preserves alert preference")
eq(window.gatherSound, false, "window migration preserves sound preference")
eq(window.gatherSparkles, false, "window migration preserves sparkle preference")
eq(ns.NormalizeDB({ windowWidth = 1 }).windowWidth, 340, "window minimum width")
eq(ns.NormalizeDB({ windowHeight = 1 }).windowHeight, 260, "window minimum height")
eq(ns.NormalizeDB({ windowWidth = 10000 }).windowWidth, 900, "window maximum width")
eq(ns.NormalizeDB({ windowHeight = 10000 }).windowHeight, 900, "window maximum height")
eq(ns.NormalizeDB({ windowWidth = 0/0 }).windowWidth, 372, "NaN window width repaired")
eq(ns.NormalizeDB({ windowHeight = math.huge }).windowHeight, 474, "infinite window height repaired")
eq(ns.NormalizeDB({ windowWidth = "700" }).windowWidth, 372, "invalid window width type repaired")
eq(ns.NormalizeDB(window).windowHeight, 799, "window dimensions survive reload normalization")
local gather = ns.NormalizeDB({ gatherPoint = "TOPRIGHT", gatherRelativePoint = "invalid",
    gatherX = 22, gatherY = -60, gatherScale = 4 })
eq(gather.gatherPoint, "TOPRIGHT", "saved alert anchor")
eq(gather.gatherRelativePoint, "CENTER", "invalid alert anchor repaired")
eq(gather.gatherX, 22, "saved alert x")
eq(gather.gatherY, -60, "saved alert y")
eq(gather.gatherScale, 1.3, "saved alert scale capped")
eq(db.gatherY, 170, "old settings keep the original alert placement")

local originalSparkle = { SoftTargetInteractRange = { before = "10.000000", applied = "30" },
    SoftTargetInteract = { before = "1", applied = "3" },
    Sound_EnableAllSound = { before = "1", applied = "0" },
    SoftTargetIconGameObject = { before = {}, applied = "1" },
    SoftTargetInteractArc = { before = "0", applied = "nan" } }
local sparkle = ns.NormalizeDB({ gatherSparkles = false, gatherSparkleScale = 9,
    gatherSparkleCVars = originalSparkle,
    gatherSparkleOverrides = { SoftTargetInteractRange = true, SoftTargetInteract = "true", Sound_EnableAllSound = true } })
eq(ns.NormalizeDB(nil).gatherSparkles, true, "sparkles default enabled")
eq(sparkle.gatherSparkles, false, "saved sparkle off")
eq(sparkle.gatherSparkleScale, 1.6, "sparkle scale bounded")
eq(ns.NormalizeDB({gatherSparkleScale=0/0}).gatherSparkleScale, 1, "invalid sparkle scale repaired")
eq(sparkle.gatherSparkleCVars.SoftTargetInteractRange.before, "10.000000", "original CVar survives reload normalization")
eq(sparkle.gatherSparkleCVars.SoftTargetInteractRange.applied, "30", "ownership survives reload normalization")
eq(sparkle.gatherSparkleCVars.Sound_EnableAllSound, nil, "unowned CVar cannot enter recovery")
eq(sparkle.gatherSparkleCVars.SoftTargetIconGameObject, nil, "malformed CVar removed")
eq(sparkle.gatherSparkleCVars.SoftTargetInteractArc, nil, "non-finite CVar removed")
eq(sparkle.gatherSparkleOverrides.SoftTargetInteractRange, true, "user override survives reload")
eq(sparkle.gatherSparkleOverrides.SoftTargetInteract, nil, "override requires boolean")
eq(sparkle.gatherSparkleOverrides.Sound_EnableAllSound, nil, "override CVar whitelist")
sparkle.gatherSparkleCVars.SoftTargetInteract.before = "0"
eq(originalSparkle.SoftTargetInteract.before, "1", "normalization copies recovery records")

local questOriginal = {filterID = 65536, before = true, applied = false, unexpected = "ignored"}
local questRecovery = ns.NormalizeDB({gatherCursorQuestRestore = questOriginal}).gatherCursorQuestRestore
eq(questRecovery.filterID, 65536, "quest tracking recovery survives reload")
eq(questRecovery.before, true, "quest recovery original setting retained")
eq(questRecovery.applied, false, "quest recovery applied setting retained")
eq(questRecovery == questOriginal, false, "quest recovery copied")
eq(questRecovery.unexpected, nil, "quest recovery excludes other data")
eq(ns.NormalizeDB({gatherCursorQuestRestore = {filterID=2580,before=true,applied=false}}).gatherCursorQuestRestore, nil, "mineral tracking cannot enter quest restoration")
eq(ns.NormalizeDB({gatherCursorQuestRestore = {filterID=65536,before=false,applied=true}}).gatherCursorQuestRestore, nil, "inverse ownership rejected")
eq(ns.NormalizeDB({gatherCursorQuestRestore = true}).gatherCursorQuestRestore, nil, "malformed quest recovery rejected")

Enum = nil
eq(ns.Difficulty(1), "unknown", "no guessed enum values")
eq(ns.Difficulty("OPTIMAL"), "orange", "orange difficulty")
eq(ns.Difficulty("difficult"), "red", "red is unavailable difficulty")
eq(ns.Difficulty("medium"), "yellow", "yellow difficulty")
eq(ns.Difficulty("easy"), "green", "green difficulty")
eq(ns.Difficulty("trivial"), "gray", "gray difficulty")
eq(ns.Difficulty({}), "unknown", "bad difficulty")
Enum = { TradeskillRelativeDifficulty = { Optimal = 77, Medium = 88, Easy = 99, Trivial = 111, Difficult = 55 } }
eq(ns.Difficulty(77), "orange", "read current client enum")
eq(ns.Difficulty(1), "unknown", "unknown enum still excluded")

local recipes = {
    { id = 1, name = "黄配方", difficulty = "yellow", learned = true, craftable = 100 },
    { id = 2, name = "缺料橙配方", difficulty = "orange", learned = true, craftable = 0 },
    { id = 3, name = "齐料橙配方", difficulty = 77, learned = true, craftable = 2 },
    { id = 4, name = "绿色", difficulty = "green", learned = true },
    { id = 5, difficulty = "orange", learned = false },
    { id = 6, difficulty = "red", learned = true },
    { id = 7, difficulty = "orange", learned = true, canSkillUp = false },
    { id = 8, difficulty = "orange", learned = true, available = false },
    { id = 9, difficulty = "orange", learned = true, cooldown = 1 },
    { id = 10, difficulty = "gray", learned = true },
    { id = 11, difficulty = "unknown", learned = true },
}
local ranked = ns.RankRecipes(recipes)
eq(#ranked, 4, "only usable known skill-up recipes")
eq(ranked[1].id, 3, "same color prefers materials ready")
eq(ranked[2].id, 2, "color takes priority over materials")
eq(ranked[3].id, 1, "yellow before green")
eq(ranked[4].id, 4, "green last")
eq(recipes[1].id, 1, "input order unchanged")
eq(ns.RankRecipes(nil)[1], nil, "empty input")
local tied = ns.RankRecipes({
    { id = 3, name = "B", difficulty = "orange", learned = true, craftable = 1 },
    { id = 2, name = "A", difficulty = "orange", learned = true, craftable = 1 },
    { id = 1, name = "Z", difficulty = "orange", learned = true, craftable = 5 },
})
eq(tied[1].id, 1, "more craftable within color")
eq(tied[2].id, 2, "name tie-break")

local inventory = { [100] = 10, [200] = 3, [300] = 1 }
local function count(id) return inventory[id] end
local recipe = { reagentsComplete = true, reagents = {
    { name = "铜锭", itemID = 100, required = 2, owned = 999 },
    { name = "助熔剂", itemID = 200, required = 2 },
} }
local result = ns.MaterialSummary(recipe, count)
eq(result.complete, true, "complete material data")
eq(result.craftable, 1, "limiting reagent")
eq(result.reagents[1].owned, 10, "live inventory beats cached count")
eq(result.reagents[2].missing, 0, "enough materials")
eq(recipe.reagents[1].owned, 999, "do not mutate cache")
inventory[200] = 1
result = ns.MaterialSummary(recipe, count)
eq(result.craftable, 0, "missing reagent prevents craft")
eq(result.reagents[2].missing, 1, "exact missing quantity")
result = ns.MaterialSummary({ reagentsComplete = false, reagents = recipe.reagents }, count)
eq(result.craftable, nil, "partial schematic has no craft count")
eq(result.complete, false, "partial schematic remains partial")
result = ns.MaterialSummary(recipe, function() error("API not ready") end)
eq(result.complete, false, "count failure not zero inventory")
eq(result.reagents[1].owned, nil, "unknown count shown unknown")
eq(result.craftable, nil, "failed count not craftable")
result = ns.MaterialSummary({ reagents = { { itemID = 100, required = 2 }, { itemID = 100, required = 4 } } }, count)
eq(result.craftable, 1, "duplicate slots share one inventory pool")
eq(#result.reagents, 1, "duplicate material display aggregated")
eq(result.reagents[1].required, 6, "duplicate material requirements combined")
inventory[100] = 5
result = ns.MaterialSummary({ reagents = { { itemID = 100, required = 2 }, { itemID = 100, required = 4 } } }, count)
eq(result.reagents[1].missing, 1, "combined missing quantity")
eq(result.craftable, 0, "combined requirements prevent false ready")
result = ns.MaterialSummary({ reagents = { { name = "unknown", required = 2, owned = 4 } } })
eq(result.craftable, nil, "unknown material id conservative")
result = ns.MaterialSummary({ reagents = { { itemID = 100, required = 0 } } }, count)
eq(result.complete, false, "bad quantity conservative")
eq(result.craftable, nil, "zero quantity cannot divide by zero")

inventory[100], inventory[200] = 1, 1
local alternatives = { reagents = { { name = "任一材料", required = 2, options = {
    { itemID = 100, name = "低品级" }, { itemID = 200, name = "高品级" },
} } } }
result = ns.MaterialSummary(alternatives, count)
eq(result.craftable, 0, "cannot combine partial alternatives")
eq(result.reagents[1].missing, 1, "best single choice is short")
eq(result.reagents[1].options[2].owned, 1, "all alternatives retained")
inventory[100], inventory[200] = 5, 4
result = ns.MaterialSummary(alternatives, count)
eq(result.craftable, 4, "independent complete alternative batches")
alternatives.reagents[2] = { itemID = 100, required = 1 }
result = ns.MaterialSummary(alternatives, count)
eq(result.complete, false, "overlapping options require allocation")
eq(result.craftable, nil, "never double count overlapping options")
eq(result.reagents[2].ambiguous, true, "mark ambiguous material")
result = ns.MaterialSummary({ reagents = {} }, count)
eq(result.noMaterials, true, "zero reagent actions")
eq(result.craftable, nil, "no invented unlimited count")

local progress = ns.Progress({ rank = 74, maxRank = 75 })
eq(progress.remaining, 1, "distance to skill cap")
eq(progress.nextPoint, 75, "next skill point")
eq(progress.text, "当前 74/75 · 距上限 1 点", "progress text")
progress = ns.Progress({ rank = 75, maxRank = 75 })
eq(progress.remaining, 0, "cap reached")
eq(progress.nextPoint, nil, "no next point past current cap")
progress = ns.Progress({ rank = 80, maxRank = 75 })
eq(progress.remaining, 0, "no negative remaining")
eq(ns.Progress({ rank = 10 }).remaining, nil, "unknown maximum")
eq(ns.Progress({ rank = 0 / 0, maxRank = 75 }).rank, nil, "bad rank")
eq(ns.GatheringAdvice({ id = 356 }):find("次数不固定", 1, true) ~= nil, true, "fishing no guaranteed count")
eq(ns.GatheringAdvice({ id = 182 }):find("草药", 1, true) ~= nil, true, "herbalism advice")
eq(ns.GatheringAdvice({ id = 186 }):find("熔炼", 1, true) ~= nil, true, "mining includes smelting")
eq(ns.GatheringAdvice({ id = 393 }):find("剥皮", 1, true) ~= nil, true, "skinning advice")
eq(ns.GatheringAdvice({ id = 164 }):find("原生专业窗口", 1, true) ~= nil, true, "crafting initialization advice")

print("MyForeverProfessions core: " .. checks .. " simulated checks passed")
