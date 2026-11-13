local _, NS = ...
local listener, click
local itemKinds = { item = true, keystone = true, battlepet = true }

local function public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function call(func, ...)
    if type(func) ~= "function" then return end
    local ok, value = pcall(func, ...)
    if ok and public(value) then return value end
end

local function isItemLink(link)
    if not public(link) or type(link) ~= "string" or link:find("[%z\1-\31\127]") then return false end
    local markup = link:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("^|cn[%w_]+:", ""):gsub("|r$", "")
    local kind = markup:match("^|H([a-z]+):%d+[^|]*|h[^|]+|h$")
    return itemKinds[kind] == true
end

local function observeLink(link)
    local pressed = click
    if not pressed or pressed.link or call(IsModifiedClick, "CHATLINK") ~= true or not isItemLink(link) then return end
    if NS.GetNativeItemLinkTarget() ~= pressed.target then return end

    -- The stock handler retains priority for its own drafts and auction search.
    if call(ChatFrameUtil and ChatFrameUtil.GetActiveWindow)
        or (AuctionHouseFrame and call(AuctionHouseFrame.IsVisible, AuctionHouseFrame)) then return end

    local foci = call(GetMouseFoci)
    local owner = type(foci) == "table" and public(foci[1]) and foci[1]
    if NS.InsertNativeItemLink(link) then
        pressed.link, pressed.owner = link, owner
    end
end

local function dismissBagSplit(frame, _, owner)
    if not click or not click.link or not public(owner) or not owner or click.owner ~= owner
        or not C_Container or call(IsModifiedClick, "SPLITSTACK") ~= true
        or call(owner.IsForbidden, owner) == true then return end

    local bag = call(owner.GetBagID, owner)
    local slot = call(owner.GetID, owner)
    if type(bag) == "number" and type(slot) == "number"
        and call(C_Container.GetContainerItemLink, bag, slot) == click.link then
        -- The secure hook cannot alter InsertLink's return value. Dismiss only
        -- the split popup created by the very bag click that inserted a link.
        click.owner = nil
        frame:Hide()
    end
end

function NS.InstallItemLinkBridge()
    if listener or type(hooksecurefunc) ~= "function" or type(NS.InsertNativeItemLink) ~= "function"
        or type(NS.GetNativeItemLinkTarget) ~= "function"
        or not ChatFrameUtil or type(ChatFrameUtil.InsertLink) ~= "function" then return end

    listener = CreateFrame("Frame")
    listener:RegisterEvent("GLOBAL_MOUSE_DOWN")
    listener:RegisterEvent("GLOBAL_MOUSE_UP")
    listener:SetScript("OnEvent", function(_, event, button)
        if event == "GLOBAL_MOUSE_DOWN" then
            local target = public(button) and button == "LeftButton" and call(IsModifiedClick, "CHATLINK") == true
                and NS.GetNativeItemLinkTarget()
            click = target and { target = target } or nil
        elseif click and public(button) and button == "LeftButton" then
            local released = click
            -- Item buttons run on release. Keep this click valid through the
            -- native OnClick regardless of its order relative to this event.
            C_Timer.After(0, function()
                if click == released then click = nil end
            end)
        end
    end)
    hooksecurefunc(ChatFrameUtil, "InsertLink", observeLink)
    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", observeLink)
    end
    if StackSplitFrame and type(StackSplitFrame.OpenStackSplitFrame) == "function" then
        hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", dismissBagSplit)
    end
end
