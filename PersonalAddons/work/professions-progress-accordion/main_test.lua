-- Real Core/API/UI/Main integration with fake game APIs. No game automation.
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, needle, message)
    checks = checks + 1
    assert(type(value) == "string" and value:find(needle, 1, true), message)
end

local methods = {}
local function frame(kind, name, parent)
    return setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, shown = true,
        width = 0, height = 0, scroll = 0, value = 0 }, { __index = methods })
end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 300, 0 }) end
function methods:ClearAllPoints() self.point = nil end
function methods:SetText(value) self.text = value end
function methods:GetStringHeight()
    local lines = 1
    for _ in (self.text or ""):gmatch("\n") do lines = lines + 1 end
    return lines * 14
end
function methods:CreateFontString() return frame("FontString", nil, self) end
function methods:CreateTexture() return frame("Texture", nil, self) end
function methods:SetHighlightTexture() self.highlight = frame("Texture", nil, self) end
function methods:GetHighlightTexture() return self.highlight end
function methods:SetThumbTexture() self.thumb = frame("Texture", nil, self) end
function methods:GetThumbTexture() return self.thumb end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScroll() return self.scroll end
function methods:SetScrollChild(child) self.child = child end
function methods:SetMinMaxValues(min, max) self.min, self.max = min, max end
function methods:SetValue(value)
    self.value = value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetScale(value) self.scale = value end
function methods:SetClampedToScreen(value) self.clamped = value end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
for _, method in ipairs({ "SetAllPoints", "SetTexCoord", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetSpacing", "SetTextColor", "SetVertexColor", "SetColorTexture", "SetTexture", "SetMovable", "EnableMouse", "EnableMouseWheel", "SetFrameStrata", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "RegisterForDrag", "SetOrientation", "SetValueStep" }) do methods[method] = function() end end

UIParent = frame("Frame")
CreateFrame = frame
SlashCmdList = {}
local messages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
local now, combat, scanCalls, recipeCalls, countCalls = 0, false, 0, 0, 0
GetTime = function() return now end
InCombatLockdown = function() return combat end
IsControlKeyDown = function() return false end
Enum = { CraftingReagentType = { Basic = 0 } }
local skills = {
    [171] = { name = "炼金术", rank = 45, maxRank = 75, modifier = 0 },
    [129] = { name = "急救", rank = 10, maxRank = 75, modifier = 0 },
}
local skillLineCount, currentID = 5, 171
C_SkillInfo = {
    GetSkillLineInfoByID = function(id) return skills[id] end,
    GetNumSkillLines = function() return skillLineCount end,
}
C_Spell = { GetSpellInfo = function() return { iconID = 123 } end }
local inventory = { [1001] = 4, [1002] = 9 }
C_Item = {
    GetItemNameByID = function(id) return id == 1001 and "宁神花" or "亚麻布" end,
    GetItemCount = function(id, bank) eq(bank, false, "inventory query excludes bank"); countCalls = countCalls + 1; return inventory[id] or 0 end,
}
local recipeInfo = {
    [101] = { name = "初级药水", learned = true, canSkillUp = true, relativeDifficulty = "optimal" },
    [102] = { name = "训练药剂", learned = true, canSkillUp = true, relativeDifficulty = "medium" },
    [201] = { name = "亚麻绷带", learned = true, canSkillUp = true, relativeDifficulty = "optimal" },
}
local recipeIDs = { [171] = { 101, 102 }, [129] = { 201 } }
local recipeReady = true
C_TradeSkillUI = {
    IsTradeSkillReady = function() return recipeReady end,
    IsTradeSkillLinked = function() return false end,
    GetBaseProfessionInfo = function() return { professionID = currentID } end,
    GetAllRecipeIDs = function() scanCalls = scanCalls + 1; return recipeIDs[currentID] end,
    GetRecipeInfo = function(id) recipeCalls = recipeCalls + 1; return recipeInfo[id] end,
    GetRecipeCooldown = function() return 0 end,
    GetRecipeSchematic = function(id)
        return { reagentSlotSchematics = { { required = true, quantityRequired = id == 101 and 2 or 1,
            reagentType = 0, reagents = { { itemID = id == 201 and 1002 or 1001 } } } } }
    end,
    IsRecipeInSkillLine = function(id, professionID) return professionID == 129 and id == 201 or professionID == 171 and (id == 101 or id == 102) end,
}
MyForeverProfessionsDB = { shown = true, locked = true, collapsed = false, scale = 1.25,
    point = "TOPLEFT", relativePoint = "TOPLEFT", x = 27, y = -48, cache = {} }
local ns = {}
local base = PROFESSIONS_MAIN_BASE or "PersonalAddons/work/professions-progress-accordion/"
for _, file in ipairs({ "Core.lua", "API.lua", "UI.lua", "Main.lua" }) do assert(loadfile(base .. file))("MyForeverProfessions", ns) end
local function event(name, argument) ns.events.scripts.OnEvent(ns.events, name, argument) end
local function tick(elapsed) now = now + elapsed; ns.events.scripts.OnUpdate(ns.events, elapsed) end
local function settle() for _ = 1, 8 do tick(1) end end
local function profession(id) for _, value in ipairs(ns.professions) do if value.id == id then return value end end end

event("ADDON_LOADED", "AnotherAddon")
eq(ns.db, nil, "ignore unrelated addon loading")
event("ADDON_LOADED", "MyForeverProfessions")
eq(ns.db, MyForeverProfessionsDB, "uses character SavedVariables")
eq(ns.db.scale, 1.25, "restores character scale")
eq(ns.frame.scale, 1.25, "restores rendered scale")
eq(ns.db.locked, true, "restores character position lock")
eq(ns.frame.point[4], 27, "restores character position")
eq(ns.detectReady, false, "initial data marked pending")
local originalFrame = ns.frame
event("PLAYER_LOGIN")
settle()
eq(ns.frame, originalFrame, "login does not duplicate frame")
eq(ns.detectReady, true, "login recognizes loaded skill lines")
eq(#ns.professions, 2, "primary and secondary profession detected")
eq(profession(171).cacheState, "fresh", "current profession scanned")
eq(profession(129).cacheState, "missing", "unopened secondary profession not invented")
eq(profession(171).recipes[1].id, 101, "orange recommendation precedes yellow")
eq(profession(171).recipes[1].craftable, 2, "materials propagate to recommendation")
ns.frame.cards[1].header.scripts.OnClick()
contains(ns.frame.cards[1].materialRows[1].label.text, "宁神花", "recipe data reaches real clickable material row")

local beforeScan, beforeRecipe = scanCalls, recipeCalls
inventory[1001] = 1
event("BAG_UPDATE_DELAYED")
tick(0.3)
eq(scanCalls, beforeScan, "bag change avoids full recipe scan")
eq(recipeCalls, beforeRecipe, "bag change avoids recipe info reread")
eq(profession(171).recipes[1].craftable, 0, "bag change recalculates craft count")
eq(profession(171).recipes[1].reagents[1].missing, 1, "bag change recalculates shortage")

skills[171].rank = 46
event("SKILL_LINES_CHANGED")
ns.AttachRecommendations()
eq(profession(171).cacheState, "stale", "skill event invalidates immediately")
settle()
eq(profession(171).rank, 46, "skill event reads new rank")
eq(profession(171).cacheState, "fresh", "skill event rescans current recipes")
eq(ns.db.cache[171].rank, 46, "fresh cache tracks rank used for difficulty")

event("TRADE_SKILL_DATA_SOURCE_CHANGING")
beforeScan, beforeRecipe = scanCalls, recipeCalls
currentID = 129
event("TRADE_SKILL_LIST_UPDATE")
tick(0.3)
eq(scanCalls, beforeScan, "source transition blocks recipe ID read")
eq(recipeCalls, beforeRecipe, "source transition blocks recipe details")
eq(ns.db.cache[129], nil, "transition cannot assign old recipes to new profession")
event("TRADE_SKILL_DATA_SOURCE_CHANGED")
settle()
eq(profession(129).cacheState, "fresh", "new source scans after ready event")
eq(profession(129).recipes[1].id, 201, "new source owns its recipe")
eq(profession(171).cacheState, "stale", "other profession remains explicitly stale")
event("TRADE_SKILL_CLOSE")
tick(0.3)
eq(ns.frame.shown, true, "closing native profession keeps panel visible")
eq(profession(129).recipes[1].id, 201, "closing native profession retains recommendation")

beforeScan, beforeRecipe = scanCalls, recipeCalls
local beforeCount = countCalls
combat = true
event("PLAYER_REGEN_DISABLED")
eq(ns.combatPaused, true, "combat immediately marks pause")
contains(ns.frame.summary.text, "战斗中", "combat pause visible")
inventory[1002] = 2
event("BAG_UPDATE_DELAYED")
tick(0.3)
eq(scanCalls, beforeScan, "combat does not scan recipes")
eq(recipeCalls, beforeRecipe, "combat does not reread recipes")
eq(countCalls, beforeCount, "combat does not query materials")
eq(ns.frame.shown, true, "combat leaves panel visible")
combat = false
event("PLAYER_REGEN_ENABLED")
tick(0.3)
eq(ns.combatPaused, false, "combat end resumes")
eq(profession(129).recipes[1].craftable, 2, "combat end updates inventory")

local savedSkills, savedCache = skills, ns.db.cache[171]
skills, skillLineCount = {}, 0
ns.Refresh(true)
ns.Refresh(true)
eq(ns.detectReady, false, "empty pre-load skill API is not authoritative")
eq(ns.db.cache[171], savedCache, "transient empty skill API preserves character cache")
eq(#ns.professions, 2, "transient empty skill API keeps prior known professions")
skills, skillLineCount = savedSkills, 5
ns.Refresh(true)
eq(ns.detectReady, true, "loaded skills recover")

local savedIDs = recipeIDs[129]
recipeIDs[129] = {}
ns.Refresh(true)
eq(ns.db.cache[129].recipes[1].id, 201, "empty transient recipe list preserves cached recipes")
eq(profession(129).cacheState, "stale", "empty recipe list labels cache stale")
recipeIDs[129] = savedIDs
ns.Refresh(true)
eq(profession(129).cacheState, "fresh", "nonempty recipes recover from placeholder")

SlashCmdList.MYFOREVERPROFESSIONS("hide")
eq(ns.db.shown, false, "hide persists")
eq(ns.frame.shown, false, "hide affects real UI")
SlashCmdList.MYFOREVERPROFESSIONS("show")
eq(ns.db.shown, true, "show persists")
eq(ns.frame.shown, true, "show affects real UI")
SlashCmdList.MYFOREVERPROFESSIONS("scale 1.4")
eq(ns.db.scale, 1.4, "slash scale persists")
eq(ns.frame.scale, 1.4, "slash scale applies")
SlashCmdList.MYFOREVERPROFESSIONS("scale nonsense")
eq(ns.db.scale, 1.4, "invalid scale preserves setting")
contains(messages[#messages], "scale", "invalid scale explains syntax")
ns.db.collapsed = true
SlashCmdList.MYFOREVERPROFESSIONS("reset")
eq(ns.db.scale, 1, "reset restores scale")
eq(ns.db.locked, false, "reset unlocks position")
eq(ns.db.collapsed, false, "reset expands")
eq(ns.frame.point[1], "CENTER", "reset reanchors real frame")
eq(ns.frame.point[4], 300, "reset restores horizontal offset")
eq(ns.db.cache[129].recipes[1].id, 201, "reset preserves recipe data")

-- A confirmed, stable unlearn removes cache only after two authoritative reads.
skills[171] = nil
ns.Refresh(false)
eq(profession(171), nil, "unlearn removes visible profession")
eq(ns.db.cache[171] ~= nil, true, "first absent read preserves cache defensively")
ns.Refresh(false)
eq(ns.db.cache[171], nil, "second authoritative absent read clears cache")
eq(ns.db.cache[129] ~= nil, true, "other profession cache preserved")
print("professions_main_test: " .. checks .. " checks passed")
