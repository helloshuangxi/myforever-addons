local _, ns = ...

local function public(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

local function member(object, key)
    if not public(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return end
    local ok, value = pcall(function() return object[key] end)
    if ok and public(value) then return value end
end

local function call(func, ...)
    if type(func) ~= "function" then return false end
    local ok, value = pcall(func, ...)
    if not ok or not public(value) then return false end
    return true, value
end

local function validLink(link)
    if not public(link) or type(link) ~= "string" or link:find("[%z\1-\31\127]") then return false end
    local markup, colors = link:gsub("^|c%x%x%x%x%x%x%x%x", "", 1)
    if colors == 0 then markup, colors = link:gsub("^|cn[%w_]+:", "", 1) end
    if colors > 0 then
        if markup:sub(-2) ~= "|r" then return false end
        markup = markup:sub(1, -3)
    end
    local id, suffix = markup:match("^|Hitem:(%d+)([^|]*)|h%[[^|]+%]|h$")
    return id ~= nil and tonumber(id) > 0 and (suffix == "" or suffix:match("^:[%d:%-]*$") ~= nil)
end

local function plainName(name)
    if not public(name) or type(name) ~= "string" or name:find("[|%z\1-\31\127]") then return end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or name:match("^物品%s*#?%d+$") or name:match("^[Ii]tem%s*#?%d+$") then return end
    return name
end

local function materialName(link, fallback)
    local _, name = call(member(C_Item, "GetItemInfo"), link)
    name = plainName(name)
    if name then return name end
    _, name = call(GetItemInfo, link)
    return plainName(name) or plainName(fallback)
end

local function activeChat()
    local _, edit = call(member(ChatFrameUtil, "GetActiveWindow"))
    if edit ~= nil then return edit end
    _, edit = call(ChatEdit_GetActiveWindow)
    return edit
end

local function usableEdit(edit)
    local forbidden = member(edit, "IsForbidden")
    if forbidden then
        local ok, value = call(forbidden, edit)
        if not ok or value ~= false then return false end
    end
    local isObjectType = member(edit, "IsObjectType")
    local ok, value
    if isObjectType then ok, value = call(isObjectType, edit, "EditBox")
    else
        ok, value = call(member(edit, "GetObjectType"), edit)
        value = value == "EditBox"
    end
    if not ok or value ~= true then return false end
    local visible, shown = member(edit, "IsVisible"), member(edit, "IsShown")
    if not visible and not shown then return false end
    for _, method in ipairs({visible or shown, shown or visible}) do
        ok, value = call(method, edit)
        if not ok or value ~= true then return false end
    end
    local enabled = member(edit, "IsEnabled")
    if enabled then
        ok, value = call(enabled, edit)
        if not ok or value ~= true then return false end
    end
    return type(member(edit, "Insert")) == "function"
end

local function isChat(edit, active)
    if edit == active or edit == member(CommunitiesFrame, "ChatEditBox")
        or edit == member(MyForeverChatWindow, "editor") then return true end
    -- A native chat edit can retain focus before the active-window pointer updates.
    return member(edit, "chatFrame") ~= nil and type(member(edit, "GetChatType")) == "function"
end

local function inputLimit(edit, methodName)
    local method = member(edit, methodName)
    if method == nil then return 0 end
    local ok, limit = call(method, edit)
    if not ok or type(limit) ~= "number" or limit ~= limit or limit < 0
        or limit == math.huge or limit ~= math.floor(limit) then return nil end
    return limit
end

local function fitsInput(edit, text)
    local bytes, letters = inputLimit(edit, "GetMaxBytes"), inputLimit(edit, "GetMaxLetters")
    if bytes == nil or letters == nil then return false end
    if bytes == 0 and letters == 0 then return true end
    local ok, current = call(member(edit, "GetText"), edit)
    if not ok or type(current) ~= "string" then return false end
    if bytes > 0 and #current + #text > bytes then return false end
    if letters > 0 then
        -- Count UTF-8 characters, including hyperlink markup. The latter is
        -- deliberately conservative when an input does not count hidden text.
        local _, currentLetters = current:gsub("[^\128-\191]", "")
        local _, addedLetters = text:gsub("[^\128-\191]", "")
        if currentLetters + addedLetters > letters then return false end
    end
    -- No selection getter is available on all supported clients. Do not change
    -- the selection to measure it: conservatively reserve room for both texts.
    return true
end

function ns.InsertMaterialLink(link, name)
    if not validLink(link) then return false end
    local active = activeChat()
    local ok, edit = call(GetCurrentKeyBoardFocus)
    if type(GetCurrentKeyBoardFocus) == "function" and not ok then return false end
    if edit == nil then
        local focused, hasFocus = call(member(active, "HasFocus"), active)
        if not focused or hasFocus ~= true then return false end
        edit = active
    end
    if not usableEdit(edit) then return false end
    local text
    if isChat(edit, active) then
        local lockdown = member(C_ChatInfo, "InChatMessagingLockdown")
        if lockdown then
            local checked, locked = call(lockdown)
            if not checked or locked ~= false then return false end
        end
        text = link
    else
        text = materialName(link, name)
        if not text then return false end
    end
    if not fitsInput(edit, text) then return false end
    -- Direct insertion keeps the cursor/selection and avoids chat-link hooks that
    -- can start an Auctionator search. Never open chat, send, or replace a draft.
    local inserted = call(member(edit, "Insert"), edit, text)
    return inserted
end
