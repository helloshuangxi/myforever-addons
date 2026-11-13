local W = ...
GetCursorPosition = function() return 700, 400 end
IsMouseButtonDown = function() return false end
C_Item = { GetItemInfo = function(id) if id == 1 then return "宁神花", "|cffffffff|Hitem:1::::::::|h[宁神花]|h|r" end end }
local ns = {
    db = { shown = true, locked = false, scale = 1, point = "CENTER", relativePoint = "CENTER", x = 300, y = 0,
        gatherAlerts = true, gatherSound = true, gatherSparkles = false, collapsed = false },
    professions = {}, detectReady = true,
    OpenProfession = function() end, Refresh = function() end, GatherCommand = function() end, Print = function() end,
    Progress = function(p) return { text = p.rank .. "/" .. p.maxRank .. " · 距上限 " .. (p.maxRank - p.rank) .. " 点", nextPoint = p.rank < p.maxRank and p.rank + 1 or nil } end,
    GatheringAdvice = function() return "资源颜色以游戏显示为准。" end,
    GetNearbyTrainer = function() return { name = "训练师示例", mapName = "丹莫罗", mapID = 1426, x = 0.4767, y = 0.5231, distance = 80 } end,
    ShowTrainerOnMap = function() end,
}
local core = {}
assert(loadfile(ADDONS .. "MyForeverProfessions/Core.lua"))("MyForeverProfessions", core)
ns.PanelSize = core.PanelSize
PREVIEW_PROFESSIONS_NS = ns
if PREVIEW_STYLE_HOOK then PREVIEW_STYLE_HOOK("MyForeverProfessions", ns) end
assert(loadfile(ADDONS .. "MyForeverProfessions/ItemLinks.lua"))("MyForeverProfessions", ns)
assert(loadfile(ADDONS .. "MyForeverProfessions/UI.lua"))("MyForeverProfessions", ns)
local panel = ns.CreateUI()
ns.professions = {
    { id = 171, name = "炼金术", rank = 45, maxRank = 75, cacheState = "fresh", kind = "crafting", recipes = {
        { id = 1, name = "初级治疗药水", difficulty = "orange", craftable = 2, reagentsComplete = true, reagents = { { name = "宁神花", itemID = 1, required = 2, owned = 5, missing = 0 }, { name = "水晶瓶", required = 1, owned = 4, missing = 0 } } },
        { id = 2, name = "次级药剂", difficulty = "yellow", craftable = 0, reagentsComplete = true, reagents = { { name = "银叶草", required = 3, owned = 1, missing = 2 } } },
    } },
    { id = 182, name = "草药学", rank = 10, maxRank = 75, kind = "gathering", cacheState = "fresh", recipes = {
        { id = 3, name = "宁神花", difficulty = "orange", isGatheringRecipe = true, craftable = 9, currentRecipeExperience = 2, nextLevelRecipeExperience = 5, reagents = {} },
    } },
}
ns.RenderUI()
local header = panel.cards[1].header
if header.scripts.OnClick then header.scripts.OnClick(header, "LeftButton") end
ns.RenderUI()
return { { name = "商业技能助手", frame = panel } }
