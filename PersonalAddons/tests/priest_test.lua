-- Run from the World of Warcraft folder with Lua 5.1 (or lupa.lua51).
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(text, fragment, message)
    checks = checks + 1
    assert(text:find(fragment, 1, true), message or ("missing " .. fragment))
end

local combat, class = false, "PRIEST"
local reads, entries = 0, {}
InCombatLockdown = function() return combat end
UnitClass = function() return "牧师", class end
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
local localizedNames = {
    [17] = "真言术：盾", [139] = "恢复", [2060] = "强效治疗术", [2054] = "治疗术", [2050] = "次级治疗术",
    [2061] = "快速治疗", [527] = "驱散魔法", [528] = "祛病术", [2006] = "复活术", [589] = "暗言术：痛",
    [585] = "惩击", [586] = "渐隐术",
}
C_Spell = { GetSpellName = function(id) return localizedNames[id] end }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() reads = reads + 1; return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #entries } end,
    GetSpellBookItemInfo = function(slot) return entries[slot] end,
    IsSpellKnown = function(id)
        for _, entry in ipairs(entries) do
            if entry.spellID == id then return entry.learned ~= false end
        end
        return false
    end,
}
local function spell(id, name, learned)
    return { spellID = id, name = name or localizedNames[id], itemType = 1, learned = learned }
end
local NS = {}
for _, file in ipairs({ "Templates.lua", "Core.lua", "Priest.lua" }) do
    assert(loadfile("_forever_/Interface/AddOns/MyForeverMacros/" .. file))("MyForeverMacros", NS)
end
local templates = {}
for _, template in ipairs(NS.priestTemplates) do templates[template.id] = template end
eq(#NS.priestTemplates, 11, "eleven priest presets")

entries = { spell(17) }
eq(NS.ResolvePriestPreset(templates.priest_shield), "真言术：盾", "known exact ID")
entries = { spell(592, "真言术：盾"), spell(600, "真言术：盾") }
eq(#NS.ReadSpells(), 1, "merge ranks with same name")
eq(NS.ResolvePriestPreset(templates.priest_shield), "真言术：盾", "higher rank name match")
entries = { spell(592, "真言术 : 盾") }
eq(NS.ResolvePriestPreset(templates.priest_shield), "真言术 : 盾", "normalize spaces and colon, return actual spelling")
entries = { spell(592, "真言术：韧") }
eq(NS.ResolvePriestPreset(templates.priest_shield), "", "do not fuzzy match another spell")

entries = { spell(2050), spell(2054), spell(2060) }
eq(NS.ResolvePriestPreset(templates.priest_heal), "强效治疗术", "prefer learned greater heal")
entries = { spell(2050), spell(2054) }
eq(NS.ResolvePriestPreset(templates.priest_heal), "治疗术", "fallback heal")
entries = { spell(2050), spell(2060, nil, false) }
eq(NS.ResolvePriestPreset(templates.priest_heal), "次级治疗术", "exclude unlearned higher priority")
entries = { spell(2050) }
eq(NS.ResolvePriestPreset(templates.priest_flash_heal), "", "do not confuse normal and flash heal")

entries = { spell(552, "驱除疾病") }
eq(NS.ResolvePriestPreset(templates.priest_cure_disease), "", "do not substitute abolish disease")
entries = { spell(17, nil, false) }
local name, note = NS.ResolvePriestPreset(templates.priest_shield)
eq(name, "", "unlearned ID is not autofilled")
contains(note, "未确认", "explain missing learned spell")

entries = { spell(17) }
class, reads = "MAGE", 0
name, note = NS.ResolvePriestPreset(templates.priest_shield)
eq(name, "", "non-priest rejected")
contains(note, "不是牧师", "explain class mismatch")
eq(reads, 0, "non-priest does not scan")
class, combat, reads = "PRIEST", true, 0
name, note = NS.ResolvePriestPreset(templates.priest_shield)
eq(name, "", "combat refuses resolve")
contains(note, "战斗", "explain combat")
eq(reads, 0, "combat does not scan")
combat = false

local oldScan = NS.ReadSpells
NS.ReadSpells = function() error("no API") end
name, note = NS.ResolvePriestPreset(templates.priest_shield)
eq(name, "", "failed scan does not autofill")
contains(note, "读取失败", "explain failed scan")
NS.ReadSpells = oldScan

-- Localization resolves higher ranks even when Chinese candidate text differs.
localizedNames[17] = "Power Word: Shield"
entries = { spell(592, "Power Word: Shield") }
eq(NS.ResolvePriestPreset(templates.priest_shield), "Power Word: Shield", "localized higher rank")
localizedNames[17] = "真言术：盾"

local names = {}
entries = {}
for id in pairs(localizedNames) do entries[#entries + 1] = spell(id) end
for _, template in ipairs(NS.priestTemplates) do
    eq(names[template.name], nil, "unique macro name")
    names[template.name] = true
    local selected, reason = NS.ResolvePriestPreset(template)
    assert(selected ~= "", reason)
    local body, err = NS.Build(template, selected)
    checks = checks + 1
    assert(body and #body <= 255, err or "macro fits byte limit")
    eq(body:find("/stopcasting", 1, true), nil, "no default interrupted casting")
end

local friendly = NS.Build(templates.priest_dispel_friendly, "驱散魔法")
local hostile = NS.Build(templates.priest_dispel_hostile, "驱散魔法")
contains(friendly, "[mod:alt,@player][@mouseover,help,nodead][help,nodead][@player]", "friendly dispel target rules")
contains(hostile, "[@mouseover,harm,nodead][harm,nodead]", "hostile dispel target rules")
eq(hostile:find("@player", 1, true), nil, "hostile dispel never self casts")
local resurrection = NS.Build(templates.priest_resurrection, "复活术")
contains(resurrection, "[nocombat,@mouseover,help,dead][nocombat,help,dead]", "resurrection requires dead friendly out of combat")
eq(resurrection:find("nodead", 1, true), nil, "resurrection does not use living condition")
eq(NS.Build(templates.priest_fade, "渐隐术"), "#showtooltip\n/cast 渐隐术", "fade has no targeting or stopcasting additions")

print("priest_test: " .. checks .. " checks passed")
