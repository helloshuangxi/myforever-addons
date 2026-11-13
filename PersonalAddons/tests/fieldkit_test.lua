-- Run from the World of Warcraft folder with Lua 5.1 (or lupa.lua51).
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local frames = {}
local Methods = {}
function Methods:SetScript(name, handler) self.scripts[name] = handler end
function Methods:RegisterEvent(name) self.events[name] = true end
function Methods:SetText(text) self.text = text end
function Methods:SetPoint(...) self.point = { ... } end
function Methods:GetPoint() return unpack(self.point or { "CENTER", UIParent, "CENTER", 0, 0 }) end
function Methods:IsShown() return self.shown end
function Methods:SetShown(value) self.shown = value end
function Methods:Show() self.shown = true end
function Methods:Hide() self.shown = false end
function Methods:StartMoving() self.moving = true end
function Methods:StopMovingOrSizing() self.moving = false end
local function MockFrame()
    local frame = { scripts = {}, events = {}, shown = true }
    setmetatable(frame, { __index = function(_, key) return Methods[key] or function() end end })
    frames[#frames + 1] = frame
    return frame
end
function Methods:CreateFontString() return MockFrame() end
CreateFrame = MockFrame
UIParent = MockFrame()
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local combat, queries = false, 0
local now, money = 100, 20123
InCombatLockdown = function() return combat end
GetTime = function() queries = queries + 1; return now end
GetMoney = function() queries = queries + 1; return money end
issecretvalue = function(value) return type(value) == "table" and value.secret == true end
NUM_BAG_SLOTS = 4
local bags = { [0] = { 10, 0 }, { 5, 0 }, { 12, 16 }, { 4, 0 }, { 3, 0 }, { 88, 0 } }
C_Container = { GetContainerNumFreeSlots = function(id) queries = queries + 1; return unpack(bags[id]) end }
local durability = { [1] = { 80, 100 }, [5] = { 0, 60 }, [7] = { 45, 90 } }
GetInventoryItemDurability = function(slot)
    queries = queries + 1
    if durability[slot] then return unpack(durability[slot]) end
end
GetRealZoneText = function() queries = queries + 1; return "艾尔文森林" end
C_Map = {
    GetBestMapForUnit = function() queries = queries + 1; return 37 end,
    GetPlayerMapPosition = function() queries = queries + 1; return { GetXY = function() return 0.452, 0.651 end } end,
}

local Kit = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverFieldKit/Main.lua"))("MyForeverFieldKit", Kit)
eq(Kit.ReadBagSpace(), 22, "exclude specialized bags and reagent slot")
NUM_BAG_SLOTS = nil
eq(Kit.ReadBagSpace(), 22, "four bag fallback")
NUM_BAG_SLOTS = 4
local savedContainers = C_Container
C_Container = nil
GetContainerNumFreeSlots = savedContainers.GetContainerNumFreeSlots
eq(Kit.ReadBagSpace(), 22, "legacy API fallback")
GetContainerNumFreeSlots = nil
eq(Kit.ReadBagSpace(), nil, "missing bag API")
C_Container = savedContainers

eq(Kit.ReadDurability(), 0, "broken equipment is zero")
durability[5] = nil
eq(Kit.ReadDurability(), 50, "minimum durability")
durability = {}
eq(Kit.ReadDurability(), nil, "no durable equipment")
durability = { [1] = { 12, 0 }, [2] = { { secret = true }, 100 } }
eq(Kit.ReadDurability(), nil, "ignore zero maximum and secret values")

eq(Kit.FormatMoney(-10203), "-1金 2银 3铜", "negative net money")
eq(Kit.FormatMoney(0), "+0金 0银 0铜", "zero money")
eq(Kit.FormatMoney(nil), "—", "missing money")
eq(Kit.FormatDuration(3661), "1小时 01分", "session duration")
local zone, coordinates = Kit.ReadLocation()
eq(zone, "艾尔文森林", "zone")
eq(coordinates, "45.2, 65.1", "coordinates")
C_Map.GetBestMapForUnit = function() return nil end
zone, coordinates = Kit.ReadLocation()
eq(coordinates, "—", "missing map")
C_Map.GetBestMapForUnit = function() error("API unavailable") end
zone, coordinates = Kit.ReadLocation()
eq(coordinates, "—", "failing map API")

local db = Kit.NormalizeDB(nil)
eq(db.shown, true, "default visibility")
eq(db.locked, false, "default movement")
eq(db.point, "CENTER", "default anchor")
db = Kit.NormalizeDB({ shown = false, locked = true, point = "INVALID", x = "bad", y = 12 })
eq(db.shown, false, "preserve hidden state")
eq(db.locked, true, "preserve lock")
eq(db.point, "CENTER", "repair anchor")
eq(db.x, 320, "repair offset")
eq(db.y, 12, "preserve offset")

local event = Kit.events.scripts.OnEvent
event(Kit.events, "ADDON_LOADED", "MyForeverFieldKit")
event(Kit.events, "PLAYER_LOGIN")
eq(Kit.panel:IsShown(), true, "initial panel visible")
now, money = 3761, 9910
Kit.Refresh()
assert(Kit.panel.body.text:find("%-1金 2银 13铜"), "integrated net change")
checks = checks + 1

combat = true
queries = 0
event(Kit.events, "PLAYER_REGEN_DISABLED")
Kit.Refresh()
Kit.ReadBagSpace()
Kit.ReadDurability()
Kit.ReadLocation()
eq(Kit.ResetSession(), false, "no reset during combat")
eq(queries, 0, "no data queries in combat")
eq(Kit.panel.status.text, "战斗中 · 数据暂停", "combat explanation")
combat = false
event(Kit.events, "PLAYER_REGEN_ENABLED")
assert(queries > 0, "resume data queries after combat")
checks = checks + 1

queries = 0
Kit.panel.scripts.OnUpdate(Kit.panel, 0.5)
eq(queries, 0, "throttle subinterval")
Kit.panel.scripts.OnUpdate(Kit.panel, 1.5)
assert(queries > 0, "refresh at two seconds")
checks = checks + 1
SlashCmdList.MYFOREVERFIELDKIT("")
eq(MyForeverFieldKitDB.shown, false, "toggle persists hidden state")
queries = 0
Kit.Refresh()
eq(queries, 0, "hidden panel skips rendering and queries")
SlashCmdList.MYFOREVERFIELDKIT("lock")
eq(MyForeverFieldKitDB.locked, true, "lock command persists")
SlashCmdList.MYFOREVERFIELDKIT("reset")
SlashCmdList.MYFOREVERFIELDKIT("")
assert(Kit.panel.body.text:find("%+0金 0银 0铜"), "manual reset creates zero baseline")
checks = checks + 1

print("fieldkit_test: " .. checks .. " checks passed")
