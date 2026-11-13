local W = ...
issecretvalue = function() return false end
UnitName = function() return "玩家" end
UnitExists = function() return false end
GetCursorPosition = function() return 500, 500 end
SecureHandlerSetFrameRef = function(frame, key, reference) frame.refs = frame.refs or {}; frame.refs[key] = reference end
SecureHandlerWrapScript = function() end
SecureHandlerUnwrapScript = function() end
RegisterUnitWatch = function() end
UnregisterUnitWatch = function() end
RegisterStateDriver = function() end
UnregisterStateDriver = function() end
SetRaidTargetIconTexture = function() end
SecureUnitButton_OnLoad = function(button, unit) button:SetAttribute("unit", unit) end
local NS = {}
PREVIEW_TARGETS_NS = NS
local root = ADDONS .. "MyForeverTargets/"
local function load(file) assert(loadfile(root .. file))("MyForeverTargets", NS) end
if PREVIEW_STYLE_HOOK then PREVIEW_STYLE_HOOK("MyForeverTargets", NS) end
load("Core.lua")
for _, file in ipairs({ "Distance.lua", "Detection.lua", "Quest.lua" }) do load(file) end
NS.Initialize(nil)
local live = {}
UnitGUID = function(unit) return live[unit] and live[unit].guid end
NS.ReadUnit = function(unit, side)
    local value = live[unit]
    if value and value.side == side and (side ~= "friendly" or value.player) then return value end
end
NS.ApplySetting = function(key, value) NS.DB[key] = value end
NS.RequestRefresh = function() end
NS.SetShown = function(value) NS.DB.shown = value; NS.DB.friendlyShown = value; NS.DB.enemyShown = value end
NS.SetPanelShown = function(side, value) NS.DB[side .. "Shown"] = value; NS.DB.shown = NS.DB.friendlyShown or NS.DB.enemyShown end
NS.SetLocked = function(value) NS.DB.locked = value end
NS.SetScale = function(value) NS.DB.scale = value end
load("Hover.lua"); load("EnemyTargetHover.lua"); load("UI.lua")
if pcall(load, "Launcher.lua") then end
NS.CreateUI()
local function data(unit, guid, name, side, player, class, token, color, health, extra)
    local d = { unit = unit, guid = guid, name = name, targetName = name, side = side, player = player, className = class,
        classToken = token, color = color, health = health, healthCurrent = math.floor(health * 100), healthMax = 100,
        healthAvailable = true, dead = false, offline = false, target = false }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end
live.party1 = data("party1", "Player-1", "圣光行者", "friendly", true, "圣骑士", "PALADIN", { r = .96, g = .55, b = .73 }, .82)
live.party2 = data("party2", "Player-2", "林间游侠", "friendly", true, "猎人", "HUNTER", { r = .67, g = .83, b = .45 }, .46)
live.party3 = data("party3", "Player-3", "寒冰法师", "friendly", true, "法师", "MAGE", { r = .25, g = .78, b = .92 }, 1)
live.nameplate1 = data("nameplate1", "Creature-1", "迪菲亚强盗", "enemy", false, "人型生物", nil, { r = .82, g = .85, b = .9 }, .64, { target = true })
live.nameplate2 = data("nameplate2", "Creature-2", "迪菲亚强盗", "enemy", false, "人型生物", nil, { r = .82, g = .85, b = .9 }, 1)
live.nameplate3 = data("nameplate3", "Creature-3", "森林狼", "enemy", false, "野兽", nil, { r = .82, g = .85, b = .9 }, .3)
live.target = { guid = "Creature-1" }
NS.BindTiles("friendly", { "party1", "party2", "party3" }, 5)
NS.BindTiles("enemy", { "nameplate1", "nameplate2", "nameplate3" }, 5)
NS.RefreshTiles()
NS.RefreshControls()
local out = { { name = "友方面板", frame = NS.UI.friendly.frame }, { name = "敌方面板", frame = NS.UI.enemy.frame } }
return out
