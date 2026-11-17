local _, ns = ...

-- Exact node names and minimum gathering skill, not spawn coordinates or
-- skill-up colour thresholds. Factual catalog checked against the installed
-- Forever GatherLite 8.2.3 node/localization tables on 2026-11-07.
-- Live tooltip requirements take precedence when the caller can read them.
-- This module has no GatherLite/Questie runtime dependency.
local resources = {}
local function add(kind, requiredRank, ...)
    local canonical = select(1, ...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        resources[name] = {kind, requiredRank, canonical}
    end
end

add("mining", 1, "铜矿", "铜矿脉", "Copper Vein")
add("mining", 1, "贫瘠的铜矿脉", "Weak Copper Vein")
add("mining", 1, "低劣的铜矿脉", "Poor Copper Vein")
add("mining", 65, "锡矿", "锡矿脉", "Tin Vein")
add("mining", 75, "银矿", "银矿脉", "Silver Vein")
add("mining", 125, "铁矿", "铁矿脉", "Iron Deposit")
add("mining", 155, "金矿", "金矿脉", "Gold Vein")
add("mining", 175, "秘银矿", "秘银矿脉", "Mithril Deposit")
add("mining", 230, "真银矿", "真银矿脉", "Truesilver Deposit")
add("mining", 230, "黑铁矿", "黑铁矿脉", "Dark Iron Deposit")
add("mining", 245, "瑟银矿", "瑟银矿脉", "Small Thorium Vein")
add("mining", 275, "富瑟银矿", "富瑟银矿脉", "Rich Thorium Vein")
add("mining", 75, "被软泥覆盖的银矿脉", "Ooze Covered Silver Vein")
add("mining", 155, "被软泥覆盖的金矿脉", "Ooze Covered Gold Vein")
add("mining", 175, "被软泥覆盖的秘银矿脉", "Ooze Covered Mithril Deposit")
add("mining", 230, "被软泥覆盖的真银矿脉", "Ooze Covered Truesilver Deposit")
add("mining", 245, "被软泥覆盖的瑟银矿脉", "Ooze Covered Thorium Vein")
add("mining", 275, "被软泥覆盖的富瑟银矿脉", "Ooze Covered Rich Thorium Vein")

-- Forever additions with recorded minimum skills. Keep English-only entries
-- English-only where the installed reference has no verified Chinese name.
add("mining", 125, "冷铁矿", "Cold Iron Deposit")
add("mining", 175, "愚人金矿脉", "Fool's Gold Vein")
add("mining", 245, "星银矿脉", "Starsilver Vein")
add("mining", 245, "大型月亮石矿脉", "Greater Moonstone Formation")
add("mining", 300, "Heavy Thorium Vein")
add("mining", 1, "Chunk of Amber", "Large Chunk of Amber")
add("mining", 65, "火岩矿脉", "Incendicite Mineral Vein")
add("mining", 75, "次级血石矿脉", "Lesser Bloodstone Deposit")
add("mining", 150, "精铁矿脉", "Indurium Mineral Vein")
add("mining", 275, "哈卡莱瑟银矿脉", "Hakkari Thorium Vein")
add("mining", 305, "小型黑曜石碎块", "Small Obsidian Chunk", "大型黑曜石碎块", "Large Obsidian Chunk")

add("herbalism", 1, "银叶草", "Silverleaf")
add("herbalism", 1, "宁神花", "Peacebloom")
add("herbalism", 1, "枯萎的宁神花", "Wilted Peacebloom")
add("herbalism", 1, "Stunted Silverleaf")
add("herbalism", 15, "地根草", "Earthroot")
add("herbalism", 50, "魔皇草", "Mageroyal")
add("herbalism", 70, "石南草", "Briarthorn")
add("herbalism", 85, "荆棘藻", "Stranglekelp")
add("herbalism", 100, "跌打草", "Bruiseweed")
add("herbalism", 115, "野钢花", "Wild Steelbloom")
add("herbalism", 120, "墓地苔", "Grave Moss")
add("herbalism", 125, "皇血草", "Kingsblood")
add("herbalism", 150, "活根草", "Liferoot")
add("herbalism", 160, "枯叶草", "Fadeleaf")
add("herbalism", 170, "金棘草", "Goldthorn")
add("herbalism", 185, "卡德加的胡须", "Khadgar's Whisker")
add("herbalism", 195, "冬刺草", "Wintersbite")
add("herbalism", 205, "火焰花", "Firebloom")
add("herbalism", 210, "紫莲花", "Purple Lotus")
add("herbalism", 220, "阿尔萨斯之泪", "Arthas' Tears")
add("herbalism", 230, "太阳草", "Sungrass")
add("herbalism", 235, "盲目草", "Blindweed")
add("herbalism", 245, "幽灵菇", "Ghost Mushroom")
add("herbalism", 250, "格罗姆之血", "Gromsblood")
add("herbalism", 260, "黄金参", "Golden Sansam")
add("herbalism", 270, "梦叶草", "Dreamfoil")
add("herbalism", 280, "山鼠草", "Mountain Silversage")
add("herbalism", 285, "瘟疫花", "Plaguebloom")
add("herbalism", 290, "冰盖草", "Icecap")
add("herbalism", 300, "黑莲花", "Black Lotus")
add("herbalism", 125, "梦魇苔", "Nightmare Moss")
add("herbalism", 205, "梦之根", "Dreamroot")
add("herbalism", 250, "月根草", "Moonroot")
add("herbalism", 250, "星莲", "Star Lotus")
add("herbalism", 1, "Hyjal Silphium", "Tomb Weed")

-- Schools/debris are recognizable tracking targets. No minimum fishing skill
-- is asserted here; the caller still needs to establish that fishing is learned.
add("fishing", nil, "漂浮的碎片", "Floating Debris")
add("fishing", nil, "漂浮的残骸", "Floating Wreckage")
add("fishing", nil, "黑口鱼群", "Oily Blackmouth School")
add("fishing", nil, "鼠尾鱼群", "Sagefish School")

function ns.GatherResource(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    local resource = resources[name]
    if resource then return resource[1], resource[2] end
    return nil
end

-- Explicit aliases share a notice receipt; unrelated nodes with the same rank
-- remain separate. Keep the client-provided spelling in the visible label.
-- Secret-name passthrough. In clients where the minimap tooltip text is a secret
-- value the addon can never read, compare or classify the name, but the official
-- API documentation for this build marks FontString:SetText as
-- SecretArguments = "AllowedWhenTainted": addon code may hand the secret back to
-- a font string and let the game draw it. A confirmed minimap hit is then
-- published under this placeholder key and its text is displayed, not inspected.
ns.GATHER_OPAQUE_NAME = "<加密名称>"
-- Saved settings turn it on by default (Core.NormalizeDB); without that explicit
-- setting the earlier rule holds and a secret name pauses minimap reading.
function ns.GatherOpaqueAllowed() return ns.db ~= nil and ns.db.gatherOpaque == true end

function ns.GatherResourceKey(name)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return nil end
    local resource = resources[name]
    return resource and resource[3] or name
end
