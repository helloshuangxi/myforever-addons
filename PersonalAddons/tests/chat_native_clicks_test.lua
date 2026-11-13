local NS, checks = {}, 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

local clock, control, mouse, listener = 1, false, nil, nil
local callback, callbackOwner, callbackCount
local opened, timers = {}, {}
local secret = {}
issecretvalue = function(value) return value == secret end
GetTime = function() return clock end
IsControlKeyDown = function() return control end
GetMouseFoci = function() return {mouse} end
C_Timer = {After = function(_, callbackFn) timers[#timers + 1] = callbackFn end}
EventRegistry = {RegisterCallback = function(_, event, callbackFn, owner)
    assert(event == "ChatFrame.OnHyperlinkClick")
    callback, callbackOwner = callbackFn, owner
    callbackCount = (callbackCount or 0) + 1
end}
CreateFrame = function()
    listener = {events = {}}
    listener.RegisterEvent = function(self, event) self.events[event] = true end
    listener.SetScript = function(self, script, callbackFn) self[script] = callbackFn end
    return listener
end

local names = {
    player = "本人-家族", target = "路过 玩家-双姓", focus = "焦点玩家",
    targettarget = "目标的目标", party2 = "队友-蓝龙", raid7 = "团队队友",
}
local playerUnits = {target = true, focus = true, targettarget = true, party2 = true, raid7 = true}
NameUtil = {GetUnmodifiedUnitFullName = function(unit) return names[unit] end}
UnitExists = function(unit) return names[unit] ~= nil end
UnitIsPlayer = function(unit) return playerUnits[unit] end
UnitIsUnit = function(unit, other) return unit == other or names[unit] == names[other] end
NS.OpenPlayerChat = function(name) opened[#opened + 1] = {kind = "whisper", name = name} end
NS.OpenBattleNetChat = function(tag) opened[#opened + 1] = {kind = "bnet", name = tag} end
NS.GetBattleNetContactByID = function(id)
    if id == 7 then return {target = "朋友#1042"} end
    if id == 8 then return {target = secret} end
end

local function frame(name, unit, parent)
    local widget = {
        GetName = function() return name end,
        GetAttribute = function(_, key) if key == "unit" then return unit end end,
        GetParent = function() return parent end,
    }
    if name then _G[name] = widget end
    return widget
end
TargetFrame = frame("TargetFrame", "target")
FocusFrame = frame("FocusFrame", "focus")
TargetFrameToT = frame("TargetFrameToT", "targettarget", TargetFrame)
PartyFrame = frame("PartyFrame")
PartyFrame.MemberFrame2 = frame(nil, "party2", PartyFrame)
local raid = frame("CompactRaidGroup2Member3", "raid7")
local unknown = frame("ThirdPartyFrame", "target")
local forbidden = frame("ForbiddenFrame", "target")
forbidden.IsForbidden = function() return true end
forbidden.GetName = function() error("forbidden frame should not be read") end
local chatFrame = frame("ChatFrame1")

assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/NativeClicks.lua"))("MyForeverChat", NS)
NS.InstallNativeClicks()
NS.InstallNativeClicks()
check(callbackCount == 1 and listener.events.GLOBAL_MOUSE_UP and listener.events.GLOBAL_MOUSE_DOWN,
    "the addon installs one passive native click listener")

local function click(widget, button)
    mouse = widget
    clock = clock + 0.1
    listener.OnEvent(listener, "GLOBAL_MOUSE_DOWN", button or "LeftButton")
    listener.OnEvent(listener, "GLOBAL_MOUSE_UP", button or "LeftButton")
end
local function clickLink(link, button)
    click(nil, button)
    callback(callbackOwner, chatFrame, link, "label", button or "LeftButton")
end

click(TargetFrame)
click(TargetFrame)
check(#opened == 0, "normal clicks on native portraits do not open addon conversations")
control = true
click(TargetFrame)
check(#opened == 0, "a single Ctrl click does not open a conversation")
click(TargetFrame)
check(#opened == 1 and opened[1].name == names.target, "Ctrl double click uses the complete native target name")
click(TargetFrame)
check(#opened == 1, "a third click starts a fresh gesture")
clock = clock + 1
click(TargetFrame)
check(#opened == 1, "stale clicks expire")
click(FocusFrame)
check(#opened == 1, "clicks on two different frames cannot form a gesture")
click(FocusFrame)
check(#opened == 2 and opened[2].name == names.focus, "native focus opens the exact player")

click(TargetFrame)
local formerTarget = names.target
names.target = "另一个目标"
click(TargetFrame)
check(#opened == 2, "a native frame retargeted between clicks does not open a conversation")
names.target = formerTarget
click(TargetFrame, "RightButton")
click(TargetFrame)
check(#opened == 2, "a right click breaks the gesture")
control = false
listener.OnEvent(listener, "MODIFIER_STATE_CHANGED", "LCTRL")
control = true
click(TargetFrame)
check(#opened == 2, "releasing and pressing Ctrl breaks the gesture")
click(TargetFrameToT)
click(TargetFrameToT)
click(PartyFrame.MemberFrame2)
click(PartyFrame.MemberFrame2)
click(raid)
click(raid)
check(opened[3].name == names.targettarget and opened[4].name == names.party2 and opened[5].name == names.raid7,
    "target of target and stock party or raid portraits resolve the proper units")

playerUnits.target = false
click(TargetFrame)
click(TargetFrame)
playerUnits.target = true
names.target = names.player
click(TargetFrame)
click(TargetFrame)
names.target = secret
click(TargetFrame)
click(TargetFrame)
click(unknown)
click(unknown)
click(forbidden)
click(forbidden)
check(#opened == 5, "NPCs, self, unreadable identities, unknown frames, and forbidden frames do not open chats")
names.target = formerTarget

clickLink("player:其他 玩家-家族:12:SAY:")
callback(callbackOwner, chatFrame, "player:其他 玩家-家族:12:SAY:", "label", "LeftButton")
check(#timers == 0, "duplicate native callbacks do not count as separate mouse clicks")
click(nil)
clickLink("player:其他 玩家-家族:12:SAY:")
check(#timers == 0, "a click between two native chat links breaks the gesture without needing mouse focus")
clickLink("player:其他 玩家-家族:13:SAY:")
check(#opened == 5 and #timers == 1, "native name links defer opening until the original click has run")
table.remove(timers, 1)()
check(#opened == 6 and opened[6].name == "其他 玩家-家族", "native chat hyperlinks keep the complete character name")
clickLink("player:本人-家族:12:SAY:")
clickLink("player:本人-家族:12:SAY:")
check(#timers == 0, "clicking one's native name does not open a conversation")

clickLink("BNplayer:朋友:7:17:BN_WHISPER:")
clickLink("BNplayer:同名朋友:7:18:BN_WHISPER:")
check(#timers == 1, "the native BN click gesture uses the account ID and not the mutable display name")
table.remove(timers, 1)()
check(#opened == 7 and opened[7].kind == "bnet" and opened[7].name == "朋友#1042", "native BN links resolve to a stable BattleTag")
clickLink("BNplayer:朋友:8:17:BN_WHISPER:")
clickLink("BNplayer:朋友:8:17:BN_WHISPER:")
check(#timers == 0, "an unavailable BattleTag does not fall back to a display name")

local addonRow, otherControl = frame(), frame()
control = false
click(addonRow)
check(not NS.IsOpenContactGesture(addonRow, "whisper:甲", "LeftButton", false), "one plain addon row click does not open a conversation")
click(otherControl)
click(addonRow)
check(not NS.IsOpenContactGesture(addonRow, "whisper:甲", "LeftButton", false), "clicking an unrelated control interrupts an addon row gesture")
click(addonRow)
check(NS.IsOpenContactGesture(addonRow, "whisper:甲", "LeftButton", false), "two plain clicks on the same addon row are recognized")
local openedBefore = #opened
click(TargetFrame)
click(TargetFrame)
clickLink("player:其他 玩家-家族:20:SAY:")
clickLink("player:其他 玩家-家族:20:SAY:")
check(#opened == openedBefore and #timers == 0, "addon plain double-click support never relaxes native portrait or name-link Ctrl requirements")

print(("chat_native_clicks_test: %d checks passed"):format(checks))
