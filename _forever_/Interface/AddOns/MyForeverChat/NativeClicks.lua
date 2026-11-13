local _, NS = ...
local DOUBLE_CLICK_SECONDS = 0.45
local lastSource, lastIdentity, lastClickAt
local mousePress, lastLinkPress = 0, nil
local listener

local function public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function call(func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok and public(value) then return value end
end

local function resetGesture()
    lastSource, lastIdentity, lastClickAt, lastLinkPress = nil, nil, nil, nil
end

function NS.IsOpenContactGesture(source, identity, mouseButton, requireControl)
    -- Addon-owned contact controls opt out; native game frames keep Ctrl.
    if not public(mouseButton) or mouseButton ~= "LeftButton" or (requireControl ~= false and call(IsControlKeyDown) ~= true)
        or not public(source) or not source or not public(identity)
        or (type(identity) ~= "string" and type(identity) ~= "number") or identity == "" then
        resetGesture()
        return false
    end
    local now = call(GetTime)
    if type(now) ~= "number" then
        resetGesture()
        return false
    end
    if source == lastSource and identity == lastIdentity and now >= lastClickAt and now - lastClickAt <= DOUBLE_CLICK_SECONDS then
        resetGesture()
        return true
    end
    lastSource, lastIdentity, lastClickAt, lastLinkPress = source, identity, now, nil
    return false
end

local function cleanName(value)
    if public(value) and type(value) == "string" and value ~= "" and #value <= 160
        and not value:find("[%z\1-\31\127|/\\]") then
        return value
    end
end

local function unitName(unit)
    return cleanName(call(NameUtil and NameUtil.GetUnmodifiedUnitFullName, unit))
end

local function topMouseFocus()
    local foci = call(GetMouseFoci)
    if type(foci) == "table" and public(foci[1]) then return foci[1] end
end

local function parentOf(region)
    if call(region.IsForbidden, region) ~= true then return call(region.GetParent, region) end
end

local function isUnderMouse(source)
    local region = topMouseFocus()
    for _ = 1, 12 do
        if not region then return false end
        if region == source then return true end
        region = parentOf(region)
    end
    return false
end

local function unitForFrame(frame)
    if frame == TargetFrame then return "target" end
    if frame == FocusFrame then return "focus" end
    if frame == TargetFrameToT then return "targettarget" end
    if frame == FocusFrameToT then return "focustarget" end
    if PartyFrame then
        for i = 1, 4 do
            if PartyFrame["MemberFrame" .. i] == frame then return "party" .. i end
        end
    end
    local name = call(frame.GetName, frame)
    if type(name) == "string" and _G[name] == frame and (name:match("^CompactPartyFrameMember%d+$")
        or name:match("^CompactRaidFrame%d+$") or name:match("^CompactRaidGroup%d+Member%d+$")) then
        local unit = call(frame.GetAttribute, frame, "unit")
        if type(unit) == "string" and (unit:match("^party%d+$") or unit:match("^raid%d+$")) then return unit end
    end
end

local function handleUnitClick(button)
    if not public(button) or button ~= "LeftButton" or call(IsControlKeyDown) ~= true then return end
    local frame = topMouseFocus()
    if not frame or call(frame.IsForbidden, frame) == true then return end
    -- Native portraits and unit names are drawn on these buttons. Reading the
    -- mouse focus keeps the secure targeting and right-click scripts intact.
    local unit = unitForFrame(frame)
    if not unit then return end
    local name
    if call(UnitExists, unit) == true and call(UnitIsPlayer, unit) == true
        and call(UnitIsUnit, unit, "player") == false then
        name = unitName(unit)
    end
    if NS.IsOpenContactGesture(frame, name, button) and type(NS.OpenPlayerChat) == "function" then
        NS.OpenPlayerChat(name)
    end
end

local function openAfterNativeClick(openChat, identity)
    if type(openChat) ~= "function" then return end
    -- The original chat hyperlink script sets focus after its registry event.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() openChat(identity) end)
    else
        openChat(identity)
    end
end

local function linkGesture(frame, identity, button)
    -- Hyperlinks can receive clicks even when their text frame has no mouse focus.
    -- Use consecutive physical clicks to track those links instead.
    if lastLinkPress == mousePress then return false end
    if lastLinkPress and mousePress ~= lastLinkPress + 1 then resetGesture() end
    local open = NS.IsOpenContactGesture(frame, identity, button)
    if lastSource then lastLinkPress = mousePress end
    return open
end

local function handlePlayerLink(_, frame, link, _, button)
    if not public(link) or type(link) ~= "string" then resetGesture(); return end
    local kind, target, accountId = link:match("^([^:]+):([^:]+):?([^:]*)")
    if kind == "player" or kind == "playerCommunity" then
        local name = cleanName(target)
        local selfName = name and unitName("player")
        if not selfName or name == selfName then name = nil end
        if linkGesture(frame, name, button) then openAfterNativeClick(NS.OpenPlayerChat, name) end
    elseif kind == "BNplayer" or kind == "BNplayerCommunity" then
        local id = accountId:match("^%d+$") and tonumber(accountId)
        if linkGesture(frame, id and id > 0 and id < math.huge and ("bnet:" .. id), button) then
            local contact = call(NS.GetBattleNetContactByID, id)
            local battleTag = type(contact) == "table" and cleanName(contact.target)
            if battleTag then openAfterNativeClick(NS.OpenBattleNetChat, battleTag) end
        end
    else
        resetGesture()
    end
end

function NS.InstallNativeClicks()
    if listener then return end
    listener = CreateFrame("Frame")
    listener:RegisterEvent("GLOBAL_MOUSE_DOWN")
    listener:RegisterEvent("GLOBAL_MOUSE_UP")
    listener:RegisterEvent("MODIFIER_STATE_CHANGED")
    listener:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_UP" then
            handleUnitClick(button)
        elseif event == "GLOBAL_MOUSE_DOWN" then
            mousePress = mousePress + 1
            if lastSource and (not public(button) or button ~= "LeftButton"
                or (not lastLinkPress and not isUnderMouse(lastSource))) then
                resetGesture()
            end
        elseif call(IsControlKeyDown) ~= true then
            resetGesture()
        end
    end)
    if EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", handlePlayerLink, listener)
    end
end
