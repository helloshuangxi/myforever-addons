local NS, checks = {}, 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

local listener, focused, modifier, activeNative, auction, mouseOwner = nil, true, true
local selected = "chat1"
local timers, inserted, hooks = {}, {}, {}
local nativeCalls, hideCalls = 0, 0
local secret = {}
local item = "|cffa335ee|Hitem:123:4:0:0|h[物品]|h|r"
local keystone = "|cnIQ4:|Hkeystone:765:10:2|h[钥石]|h|r"
local function stockInsert()
    nativeCalls = nativeCalls + 1
    return activeNative ~= nil or auction == true
end

ChatFrameUtil = {
    InsertLink = stockInsert,
    GetActiveWindow = function() return activeNative end,
}
ChatEdit_InsertLink = stockInsert
AuctionHouseFrame = {IsVisible = function() return auction end}
StackSplitFrame = {
    OpenStackSplitFrame = function() end,
    Hide = function() hideCalls = hideCalls + 1 end,
}
C_Container = {GetContainerItemLink = function(bag, slot)
    if bag == 2 and slot == 5 then return item end
end}
GetMouseFoci = function() return {mouseOwner} end
issecretvalue = function(value) return value == secret end
IsModifiedClick = function(action)
    return modifier and (action == "CHATLINK" or action == "SPLITSTACK")
end
C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
CreateFrame = function()
    listener = {events = {}}
    listener.RegisterEvent = function(self, event) self.events[event] = true end
    listener.SetScript = function(self, script, callback) self[script] = callback end
    return listener
end
hooksecurefunc = function(target, key, callback)
    if type(target) == "string" then target, key, callback = _G, target, key end
    hooks[key] = (hooks[key] or 0) + 1
    local native = target[key]
    target[key] = function(...)
        local result = native(...)
        callback(...)
        return result
    end
end
NS.InsertNativeItemLink = function(link)
    if not focused then return false end
    inserted[#inserted + 1] = link
    return true
end
NS.GetNativeItemLinkTarget = function() if focused then return selected end end

local function mouse(event, button)
    listener.OnEvent(listener, "GLOBAL_MOUSE_" .. event, button or "LeftButton")
end
local function flushTimers()
    for _, callback in ipairs(timers) do callback() end
    timers = {}
end

assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/ItemLinks.lua"))("MyForeverChat", NS)
NS.InstallItemLinkBridge()
NS.InstallItemLinkBridge()
check(listener.events.GLOBAL_MOUSE_DOWN and listener.events.GLOBAL_MOUSE_UP and hooks.InsertLink == 1,
    "one secure bridge observes one left click")
ChatFrameUtil.InsertLink(item)
mouse("DOWN", "RightButton")
ChatFrameUtil.InsertLink(item)
modifier = false
mouse("DOWN")
ChatFrameUtil.InsertLink(item)
check(#inserted == 0 and nativeCalls == 3, "programmatic, right and unmodified clicks keep stock handling")

modifier = true
mouse("DOWN")
mouse("UP")
check(ChatFrameUtil.InsertLink(item) == false and inserted[1] == item,
    "full native link is copied synchronously without changing the original result")
ChatEdit_InsertLink(item)
check(#inserted == 1, "native and legacy hooks cannot duplicate one click")
flushTimers()
ChatFrameUtil.InsertLink(item)
check(#inserted == 1, "released clicks expire before subsequent non-click activity")
mouse("DOWN")
ChatEdit_InsertLink(item)
check(#inserted == 2, "same item may be inserted by two intentional clicks")

mouse("DOWN")
selected = "chat2"
ChatFrameUtil.InsertLink(item)
check(#inserted == 2, "switching the conversation during a click cannot insert into a different draft")

focused = false
mouse("DOWN")
ChatFrameUtil.InsertLink(item)
focused, activeNative = true, {}
mouse("DOWN")
check(ChatFrameUtil.InsertLink(item) and #inserted == 2, "stock active chat retains its original route")
activeNative, auction = nil, true
mouse("DOWN")
check(ChatFrameUtil.InsertLink(item) and #inserted == 2, "native auction search keeps its link handling")
auction = nil
mouse("DOWN")
ChatFrameUtil.InsertLink(secret)
ChatFrameUtil.InsertLink("|Hquest:3|h[任务]|h")
ChatFrameUtil.InsertLink("|Hitem:123|h[missing closing tag]")
ChatFrameUtil.InsertLink("|Hitem:123|h[" .. string.char(1) .. "]|h")
check(#inserted == 2, "restricted or invalid item tokens are ignored")
ChatFrameUtil.InsertLink(keystone)
check(#inserted == 3 and inserted[3] == keystone, "a caged or keystone-style inventory link keeps native color markup")

local bagButton = {GetBagID = function() return 2 end, GetID = function() return 5 end}
local otherButton = {GetBagID = function() return 2 end, GetID = function() return 6 end}
mouseOwner = bagButton
mouse("DOWN")
ChatFrameUtil.InsertLink(item)
StackSplitFrame:OpenStackSplitFrame(5, otherButton)
check(hideCalls == 0, "another native stack popup is untouched")
StackSplitFrame:OpenStackSplitFrame(5, bagButton)
check(hideCalls == 1, "successful link insertion dismisses the fallback popup from the same bag slot")
focused = false
mouse("DOWN")
ChatFrameUtil.InsertLink(item)
StackSplitFrame:OpenStackSplitFrame(5, bagButton)
check(hideCalls == 1, "native bag stack split works with the addon composer unfocused")

print("chat_item_links_test: " .. checks .. " checks passed")
