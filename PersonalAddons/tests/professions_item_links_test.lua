local ns, checks = {}, 0
local base = PROFESSIONS_ITEM_LINKS_BASE or "_forever_/Interface/AddOns/MyForeverProfessions/"
assert(loadfile(base .. "ItemLinks.lua"))("MyForeverProfessions", ns)
local link = "|cffffffff|Hitem:2770::::::::80:72:::::|h[铜矿石]|h|r"
local function check(value, message) checks = checks + 1; assert(value, message) end
local function box(text)
    local edit = {text = text or "", visible = true, shown = true, enabled = true, focused = true,
        objectType = "EditBox", inserts = 0, forbidden = false}
    edit.cursor = #edit.text
    function edit:IsForbidden() return self.forbidden end
    function edit:IsObjectType(kind) return self.objectType == kind end
    function edit:IsVisible() return self.visible end
    function edit:IsShown() return self.shown end
    function edit:IsEnabled() return self.enabled end
    function edit:HasFocus() return self.focused end
    function edit:GetText() return self.text end
    function edit:GetMaxBytes() return self.maxBytes or 0 end
    function edit:GetMaxLetters() return self.maxLetters or 0 end
    function edit:Insert(value)
        self.inserts = self.inserts + 1
        self.last = value
        local first, last = self.selectionStart or self.cursor, self.selectionEnd or self.cursor
        self.text = self.text:sub(1, first) .. value .. self.text:sub(last + 1)
        self.cursor = first + #value
        self.selectionStart, self.selectionEnd = nil, nil
    end
    function edit:SetText() error("must preserve existing cursor/selection") end
    function edit:SetFocus() error("must not steal focus") end
    return edit
end
local function reset(focus, active)
    GetCurrentKeyBoardFocus = function() return focus end
    ChatFrameUtil = {GetActiveWindow = function() return active end,
        InsertLink = function() error("must not invoke Auctionator's hooked entry point") end}
    ChatEdit_GetActiveWindow = nil
    ChatEdit_InsertLink = function() error("must not invoke legacy link hooks") end
    ChatFrame_OpenChat = function() error("must not open chat") end
    SendChatMessage = function() error("must not send") end
    C_Item = {GetItemInfo = function(query) assert(query == link); return "铜矿石" end}
    GetItemInfo, C_ChatInfo, CommunitiesFrame, MyForeverChatWindow, issecretvalue = nil, nil, nil, nil, nil
end

local search, draft = box("查找 "), box("未发送草稿")
draft.focused = false
reset(search, draft)
check(ns.InsertMaterialLink(link, "错误的旧名称"), "focused anonymous auction edit accepts a material")
check(search.text == "查找 铜矿石" and draft.text == "未发送草稿", "search wins over stale native chat draft")
check(search.last == "铜矿石", "auction input receives cached plain item name, not hyperlink")

search = box("前缀 old 后缀")
search.selectionStart, search.selectionEnd = #"前缀 ", #"前缀 old"
reset(search)
check(ns.InsertMaterialLink(link), "material can replace the focused selection")
check(search.text == "前缀 铜矿石 后缀", "native Insert preserves surrounding search text")
search = box("AB")
search.cursor = 1
reset(search)
check(ns.InsertMaterialLink(link) and search.text == "A铜矿石B", "material is inserted at the actual cursor")

local chat = box("购买 ")
reset(chat, chat)
check(ns.InsertMaterialLink(link) and chat.text == "购买 " .. link, "modern active native chat receives the full item link")
chat = box()
reset(chat)
ChatFrameUtil = nil
ChatEdit_GetActiveWindow = function() return chat end
check(ns.InsertMaterialLink(link) and chat.last == link, "legacy active-window API identifies chat")
chat = box()
reset(chat)
ChatEdit_GetActiveWindow = function() return chat end
check(ns.InsertMaterialLink(link) and chat.last == link, "empty modern active window allows legacy identification")
chat = box()
chat.chatFrame, chat.GetChatType = {}, function() return "SAY" end
reset(chat)
check(ns.InsertMaterialLink(link) and chat.last == link, "focused native chat works while the active pointer is unset")
chat = box()
reset(chat)
CommunitiesFrame = {ChatEditBox = chat}
check(ns.InsertMaterialLink(link) and chat.last == link, "focused community chat receives the item link")
chat = box()
reset(chat)
MyForeverChatWindow = {editor = chat}
check(ns.InsertMaterialLink(link) and chat.last == link, "existing MyForeverChat editor receives the item link")

chat = box("draft")
reset(nil, chat)
check(ns.InsertMaterialLink(link) and chat.last == link, "active chat fallback requires actual keyboard focus")
chat.focused = false
check(not ns.InsertMaterialLink(link) and chat.inserts == 1, "inactive draft is never used as a fallback")
chat.focused = true
GetCurrentKeyBoardFocus = nil
check(ns.InsertMaterialLink(link) and chat.inserts == 2, "older clients can use a truly focused active chat")
chat.HasFocus = nil
check(not ns.InsertMaterialLink(link), "missing focus evidence cannot select an old draft")
reset(nil)
check(not ns.InsertMaterialLink(link), "no input target fails without opening or sending chat")

for _, property in ipairs({"visible", "shown", "enabled"}) do
    search, chat = box("kept"), box("draft")
    search[property] = false
    reset(search, chat)
    check(not ns.InsertMaterialLink(link) and search.text == "kept" and chat.text == "draft",
        "reject " .. property .. " target without redirecting to chat")
end
search = box("kept")
search.forbidden = true
reset(search)
check(not ns.InsertMaterialLink(link) and search.inserts == 0, "forbidden input is rejected")
search = box("kept")
search.objectType = "Button"
reset(search)
check(not ns.InsertMaterialLink(link) and search.inserts == 0, "focus must be an EditBox")
search = box("kept")
search.Insert = nil
reset(search)
check(not ns.InsertMaterialLink(link) and search.text == "kept", "missing Insert does not overwrite search with SetText")
search = box()
search.IsObjectType = nil
search.GetObjectType = function() return "EditBox" end
reset(search)
check(ns.InsertMaterialLink(link), "GetObjectType supports clients without IsObjectType")
search = box()
search.IsVisible = nil
reset(search)
check(ns.InsertMaterialLink(link), "IsShown guards an older input without IsVisible")
search.IsShown = nil
check(not ns.InsertMaterialLink(link), "cannot insert without visibility evidence")

for _, method in ipairs({"IsForbidden", "IsObjectType", "IsVisible", "IsEnabled", "Insert"}) do
    search = box()
    search[method] = function() error("unavailable frame method") end
    reset(search)
    local ok, inserted = pcall(ns.InsertMaterialLink, link)
    check(ok and inserted == false, method .. " error fails safely")
end
chat = box()
reset(nil, chat)
GetCurrentKeyBoardFocus = function() error("focus unavailable") end
check(not ns.InsertMaterialLink(link) and chat.inserts == 0, "failed focus API does not fall through to a different draft")
reset(setmetatable({}, {__index = function() error("inaccessible object") end}))
check(not ns.InsertMaterialLink(link), "inaccessible focus fails safely")

search = box()
reset(search)
C_Item.GetItemInfo = function() return nil end
check(ns.InsertMaterialLink(link, "铜矿石") and search.last == "铜矿石", "verified supplied name works before item cache is ready")
for _, placeholder in ipairs({"物品 #2770", "物品 2770", "Item #2770", "item 2770", "", "   "}) do
    check(not ns.InsertMaterialLink(link, placeholder), "unresolved name is not copied to auction: " .. placeholder)
end
check(not ns.InsertMaterialLink(link), "uncached missing name is not guessed from hyperlink label")
C_Item.GetItemInfo = function() error("cache unavailable") end
check(ns.InsertMaterialLink(link, "铜矿石"), "item API errors permit a trusted name fallback")
GetItemInfo = function() return "铜矿石" end
check(ns.InsertMaterialLink(link, "物品 #2770") and search.last == "铜矿石", "legacy item cache can resolve a placeholder")
C_Item = nil
check(ns.InsertMaterialLink(link), "global item API supports legacy clients")
GetItemInfo = nil
for _, invalid in ipairs({"|Hitem:2770|h[铜矿石]|h", "铜矿石\n/run anything", "铜|r矿石"}) do
    check(not ns.InsertMaterialLink(link, invalid), "plain input rejects item-name markup and control characters")
end

local invalidLinks = {"", "item:2770", "|Hspell:2770|h[铜矿石]|h", "|Hitem:0|h[铜矿石]|h",
    "|Hitem:2770oops|h[铜矿石]|h", "|Hitem:2770|h[]|h", link .. " extra",
    "|cffffffff|Hitem:2770|h[铜矿石]|h", "|Hitem:2770|h[铜矿石]|h|r", "|Hitem:2770|h[铜\n矿石]|h"}
reset(search)
for _, invalid in ipairs(invalidLinks) do
    check(not ns.InsertMaterialLink(invalid, "铜矿石"), "malformed or non-item link is rejected")
end
check(not ns.InsertMaterialLink(nil, "铜矿石") and not ns.InsertMaterialLink({}, "铜矿石"), "nonstring links are rejected")
chat = box()
reset(chat, chat)
C_Item = nil
check(ns.InsertMaterialLink(link, "物品 #2770") and chat.last == link, "chat can insert a valid item link before its name is cached")
C_ChatInfo = {InChatMessagingLockdown = function() return true end}
check(not ns.InsertMaterialLink(link) and chat.inserts == 1, "native chat lockdown is respected")
C_ChatInfo.InChatMessagingLockdown = function() error("restricted") end
check(not ns.InsertMaterialLink(link), "unreadable chat lockdown fails safely")
C_ChatInfo.InChatMessagingLockdown = function() return false end
check(ns.InsertMaterialLink(link), "unlocked native chat accepts material links")

search = box()
reset(search)
issecretvalue = function(value) return value == search end
check(not ns.InsertMaterialLink(link), "secret focus is never inspected")
issecretvalue = function(value) return value == link end
check(not ns.InsertMaterialLink(link), "secret item link is never parsed")
issecretvalue = nil

chat = box(string.rep("x", 1280 - #link + 1))
chat.maxBytes = 1280
reset(chat)
MyForeverChatWindow = {editor = chat}
local before = chat.text
check(not ns.InsertMaterialLink(link) and chat.text == before and chat.inserts == 0,
    "MyForeverChat near-full draft cannot receive a truncated link")
chat = box(string.rep("x", 1280 - #link))
chat.maxBytes = 1280
reset(chat, chat)
check(ns.InsertMaterialLink(link) and #chat.text == 1280 and chat.last == link,
    "byte limit permits a complete hyperlink that fits exactly")

search = box("购")
search.maxBytes, search.maxLetters = 12, 4
reset(search)
check(ns.InsertMaterialLink(link) and search.text == "购铜矿石",
    "Chinese material names obey independent UTF-8 byte and character limits")
search = box("购")
search.maxBytes, search.maxLetters = 11, 4
reset(search)
check(not ns.InsertMaterialLink(link) and search.text == "购" and search.inserts == 0,
    "multibyte material is rejected before a byte limit can truncate it")
search.maxBytes, search.maxLetters = 12, 3
check(not ns.InsertMaterialLink(link) and search.inserts == 0,
    "character limit is enforced even when byte capacity is sufficient")
search.maxBytes, search.maxLetters = 0, 0
check(ns.InsertMaterialLink(link), "zero byte and character limits mean unlimited input")

search = box("replace me")
search.maxBytes, search.selectionStart, search.selectionEnd = 10, 0, #search.text
reset(search)
check(not ns.InsertMaterialLink(link) and search.text == "replace me" and search.selectionStart == 0
    and search.selectionEnd == 10 and search.inserts == 0,
    "capacity refusal leaves a selection and draft untouched")
search.maxBytes = 30
check(ns.InsertMaterialLink(link) and search.text == "铜矿石",
    "capacity check keeps normal native selection-replacement behavior")

for _, method in ipairs({"GetMaxBytes", "GetMaxLetters", "GetText"}) do
    search = box("kept")
    search.maxBytes = 1280
    search[method] = function() error("restricted capacity") end
    reset(search)
    check(not ns.InsertMaterialLink(link) and search.text == "kept" and search.inserts == 0,
        "unreadable " .. method .. " cannot cause a partial insertion")
end
for _, invalid in ipairs({-1, 1.5, math.huge, "1280"}) do
    search = box("kept")
    search.GetMaxBytes = function() return invalid end
    reset(search)
    check(not ns.InsertMaterialLink(link) and search.inserts == 0, "invalid input limit fails safely")
end
search = box("kept")
search.maxBytes = 1280
reset(search)
issecretvalue = function(value) return value == "kept" end
check(not ns.InsertMaterialLink(link) and search.inserts == 0, "secret bounded draft is never measured")
issecretvalue = function(value) return value == 1280 end
check(not ns.InsertMaterialLink(link) and search.inserts == 0, "secret input limit is never compared")
issecretvalue = nil
search.GetMaxBytes, search.GetMaxLetters = nil, nil
check(ns.InsertMaterialLink(link), "older inputs without limit APIs retain direct insertion")

print("professions_item_links_test: " .. checks .. " checks passed")
