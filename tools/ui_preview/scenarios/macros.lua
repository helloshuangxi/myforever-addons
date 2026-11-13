local W = ...
UnitClass = function() return "牧师", "PRIEST" end
local rows = { { name = "真言术：盾", spellID = 17, itemType = 1 }, { name = "恢复", spellID = 139, itemType = 1 },
    { name = "快速治疗", spellID = 2061, itemType = 1 }, { name = "惩击", spellID = 585, itemType = 1 } }
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 4 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #rows } end,
    GetSpellBookItemInfo = function(slot) return rows[slot] end,
    IsSpellKnown = function() return true end,
}
GetNumMacros = function() return 3, 2 end
GetMacroInfo = function() return nil end
GetMacroIndexByName = function() return 0 end
CreateMacro = function() return 121 end
local NS = LoadAddon("MyForeverMacros")
SlashCmdList.MYFOREVERPRIEST()
local frame = MyForeverMacrosFrame
return { { name = "宏工坊", frame = frame } }
