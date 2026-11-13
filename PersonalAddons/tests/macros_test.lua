local NS = {}
local base = "_forever_/Interface/AddOns/MyForeverMacros/"
assert(loadfile(base .. "Templates.lua"))("MyForeverMacros", NS)
assert(loadfile(base .. "Core.lua"))("MyForeverMacros", NS)
assert(loadfile(base .. "Priest.lua"))("MyForeverMacros", NS)
local checks = 0
local function check(value, description)
    checks = checks + 1
    assert(value, description)
end
local combat = false
InCombatLockdown = function() return combat end
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
local macros, writes, cursor, cursorIndex = {}, 0
GetMacroInfo = function(index)
    local m = macros[index]
    if m then return m.name, 134400, m.body end
end
GetNumMacros = function()
    local a, c = 0, 0
    for index in pairs(macros) do if index <= 120 then a = a + 1 else c = c + 1 end end
    return a, c
end
local normalCreate = function(name, icon, body, perCharacter)
    check(perCharacter == true and icon == 134400, "creates a character macro with automatic icon")
    writes = writes + 1
    for index = 121, 150 do
        if not macros[index] then macros[index] = { name = name, body = body }; return index end
    end
end
CreateMacro = normalCreate
PickupMacro = function(index) cursor, cursorIndex = "macro", index end
GetCursorInfo = function() return cursor, cursorIndex end

local body = NS.Build(NS.templates[1], "火球术")
check(body == "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] 火球术", "localized mouseover body")
check(not NS.Build(NS.templates[1], ""), "empty spell rejected")
check(not NS.Build(NS.templates[1], "火球术\n/run x()"), "line injection rejected")
check(not NS.Build(NS.templates[1], "火球术; 炎爆术"), "conditional injection rejected")
check(not NS.Build(NS.templates[1], "|Hspell:1|h技能|h"), "link rejected with explanation")
local two = NS.Build(NS.templates[7], "火球术", "寒冰箭")
check(two == "#showtooltip\n/cast [mod:shift] 寒冰箭; 火球术", "shift chooses explicit second spell")
check(not NS.Build(NS.templates[7], "火球术", ""), "second spell required")
for _, t in ipairs(NS.templates) do
    local value = NS.Build(t, "火球术", "寒冰箭")
    check(value ~= nil and #value <= 255, "all templates fit: " .. t.id)
end
check(not NS.Build(NS.templates[3], string.rep("名", 40)), "conservative length refusal")
combat = true
check(not NS.Create("MF-测试", body) and writes == 0, "combat refuses write")
combat = false
check(not NS.Create(string.rep("名", 17), body), "name character limit")
check(NS.trim("  技能\t") == "技能", "ASCII trim preserves UTF-8")
local index = NS.Create("MF-测试", body)
check(index == 121 and writes == 1, "successful write verified")
check(NS.Create("MF-测试", body) == 121 and writes == 1, "exact duplicate reused")
check(not NS.Create("MF-测试", two) and writes == 1 and macros[121].body == body, "same-name conflict preserves original")
macros[1] = { name = "账户宏", body = body }
check(not NS.Create("账户宏", body), "account collision not reused or overwritten")
macros[1] = nil
check(NS.Pickup("MF-测试", body) and cursorIndex == 121, "verified pickup")
cursor = "item"
check(not NS.Pickup("MF-测试", body), "occupied cursor preserved")
cursor, cursorIndex = nil, nil
macros[125], macros[121] = macros[121], nil
check(NS.Pickup("MF-测试", body) and cursorIndex == 125, "pickup re-resolves reordered index")
cursor, cursorIndex = nil, nil
macros[125].body = "modified"
check(not NS.Pickup("MF-测试", body), "edited macro not silently picked up")
macros = {}
CreateMacro = function() error("blocked") end
check(not NS.Create("MF-测试", body), "protected API refusal surfaced")
CreateMacro = function(name, icon, b) macros[121] = {name = name, body = b:sub(1, 20)}; return 121 end
check(not NS.Create("MF-测试", body), "truncated write not called success")
check(macros[121] ~= nil, "uncertain write not deleted")
macros = {}
CreateMacro = normalCreate
for n = 121, 150 do macros[n] = { name = tostring(n), body = "test" } end
check(not NS.Create("满了", body), "capacity exhausted")
macros = {}
local savedConstants = Constants
Constants = nil
check(not NS.Create("MF-测试", body), "unknown capacity avoids unsafe assumption")
Constants = savedConstants

Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3 } }
local spellRows = {
    { name = "火球术", spellID = 1, itemType = 1 },
    { name = "火球术", spellID = 2, itemType = 1 },
    { name = "被动", spellID = 3, itemType = 1, isPassive = true },
    { name = "未学", spellID = 4, itemType = 1 },
    { name = "未来", spellID = 5, itemType = 2 },
    { name = "其他专精", spellID = 6, itemType = 1, isOffSpec = true },
    { name = "传送门", spellID = 7, itemType = 3 },
    { name = "替换法术", spellID = 8, actionID = 9, itemType = 1 },
}
local reads = 0
C_SpellBook = {
    GetNumSpellBookSkillLines = function() reads = reads + 1; return 2 end,
    GetSpellBookSkillLineInfo = function(line)
        if line == 1 then return {itemIndexOffset = 0, numSpellBookItems = #spellRows} end
        return {itemIndexOffset = 100, numSpellBookItems = 1, offSpecID = 12}
    end,
    GetSpellBookItemInfo = function(slot) return spellRows[slot] end,
    IsSpellKnown = function(id) return id == 1 or id == 2 or id == 9 end,
}
local spells = NS.ReadSpells()
check(#spells == 2, "dedupe ranks; exclude passive, future, unknown, flyout, other spec")
check(spells[1].name == "替换法术" or spells[2].name == "替换法术", "known base supports replacement")
combat = true
local before = reads
check(#NS.ReadSpells() == 0 and reads == before, "combat avoids spellbook API")
combat = false
local readLines = C_SpellBook.GetNumSpellBookSkillLines
C_SpellBook.GetNumSpellBookSkillLines = function() error("missing data") end
check(#NS.ReadSpells() == 0, "spellbook exception falls back to manual input")
C_SpellBook.GetNumSpellBookSkillLines = readLines

-- UI smoke test: actual event callbacks and user path, no game rendering simulation.
local frames = {}
local methods = {}
function methods:SetText(t) self.text = t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end end
function methods:GetText() return self.text or "" end
function methods:SetScript(k, fn) self.scripts[k] = fn end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:SetEnabled(v) self.enabled = v end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:SetFocus() self.focus = true end
function methods:ClearFocus() self.focus = false end
local noops = { "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetJustifyH", "SetJustifyV", "SetAutoFocus",
    "SetMaxLetters", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "SetMultiLine", "SetFontObject", "SetScrollChild", "HighlightText", "SetSpacing" }
for _, method in ipairs(noops) do methods[method] = function() end end
local function widget(kind, name, parent)
    local w = setmetatable({kind = kind, name = name, parent = parent, shown = true, enabled = true, scripts = {}, events = {}}, {__index = methods})
    frames[#frames + 1] = w
    if name then _G[name] = w end
    return w
end
function methods:CreateFontString() return widget("FontString", nil, self) end
CreateFrame = function(kind, name, parent, template)
    local w = widget(kind, name, parent)
    if template == "BasicFrameTemplateWithInset" then w.TitleText = widget("FontString", nil, w) end
    return w
end
UIParent = widget("Frame")
UISpecialFrames, SlashCmdList = {}, {}
dofile(base .. "MyForeverStyle.lua")
assert(loadfile(base .. "Main.lua"))("MyForeverMacros", NS)
SlashCmdList.MYFOREVERMACROS()
local ui = MyForeverMacrosFrame
check(ui and not ui.create.enabled and ui:IsShown(), "first open works with empty spell")
ui.first:SetText("火球术")
check(ui.create.enabled and ui.preview:GetText() == body, "spell entry generates visible preview")
ui.create.scripts.OnClick(ui.create)
check(ui.pickup.enabled and macros[121].body == body, "create button writes preview")
ui.name:SetText("MF-另名")
check(not ui.pickup.enabled, "renaming preview invalidates pickup")
ui.name:SetText("MF-指向")
ui.create.scripts.OnClick(ui.create)
check(ui.pickup.enabled, "exact duplicate can be picked again")
ui.first:SetText("寒冰箭")
check(not ui.pickup.enabled, "changing spell invalidates pickup")
ui.first:SetText("火球术")
ui.firstPick.scripts.OnClick(ui.firstPick)
check(MyForeverSpellPicker:IsShown(), "spell picker opens")
local pick = MyForeverSpellPicker
pick.rows[1].scripts.OnClick(pick.rows[1])
check(not pick:IsShown() and ui.first:GetText() ~= "", "spell picker populates field")
ui.templates[8].scripts.OnClick(ui.templates[8])
check(not ui.first.enabled and ui.create.enabled and ui.preview:GetText():find("/focus", 1, true), "universal template needs no spell")
combat = true
ui.scripts.OnEvent(ui, "PLAYER_REGEN_DISABLED")
check(not ui.create.enabled and not ui.pickup.enabled and not ui.firstPick.enabled, "combat disables writes and picker")
combat = false
ui.scripts.OnEvent(ui, "PLAYER_REGEN_ENABLED")
check(ui.create.enabled, "leaving combat resumes")
SlashCmdList.MYFOREVERMACROS()
check(not ui:IsShown(), "slash toggles window off")
SlashCmdList.MYFOREVERMACROS()
check(ui:IsShown(), "slash reopens window")
SlashCmdList.MYFOREVERPRIEST()
check(ui:IsShown() and not ui.priestTab.enabled and ui.generalTab.enabled, "priest shortcut selects priest page")
check(ui.first:GetText() == "" and not ui.create.enabled, "missing priest skill never becomes wrong existing spell")
ui.first:SetText("真言术：盾")
check(ui.body:find("真言术：盾", 1, true) and ui.body:find("[@mouseover,help,nodead]", 1, true), "manual spellbook input remains available")
ui.generalTab.scripts.OnClick(ui.generalTab)
check(not ui.generalTab.enabled and ui.priestTab.enabled and ui.first:GetText() == "", "category switch clears prior spell")
SlashCmdList.MYFOREVERMACROS("priest")
check(not ui.priestTab.enabled, "explicit priest argument opens preset page")
UnitClass = function() return "牧师", "PRIEST" end
spellRows = {
    { name = "真言术：盾", spellID = 17, itemType = 1 },
    { name = "恢复", spellID = 139, itemType = 1 },
}
C_SpellBook.IsSpellKnown = function(id) return id == 17 or id == 139 end
SlashCmdList.MYFOREVERPRIEST()
check(ui.first:GetText() == "真言术：盾" and ui.create.enabled, "priest shortcut resolves learned shield in live UI flow")
ui.templates[2].scripts.OnClick(ui.templates[2])
check(ui.first:GetText() == "恢复" and ui.name:GetText() == "MF-恢复", "switching preset changes actual spell and macro name together")
ui.create.scripts.OnClick(ui.create)
check(ui.pickup.enabled and ui.body:find("恢复", 1, true), "priest preset creates verified normal character macro")
ui.templates[4].scripts.OnClick(ui.templates[4])
check(ui.first:GetText() == "" and not ui.create.enabled and not ui.pickup.enabled, "unlearned preset cannot pick or create the previous learned spell")
print("MyForeverMacros: " .. checks .. " checks passed (Lua " .. _VERSION .. ")")
