-- Core integration tests with the documented Forever event argument order.
local checks = 0
local function eq(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function includes(text, fragment)
    checks = checks + 1
    assert(text:find(fragment, 1, true), "missing " .. fragment)
end
local stamp, notices, sends = 1000, 0, {}
GetServerTime = function() return stamp end
NameUtil = { GetUnmodifiedUnitFullName = function() return "晨星-苏晚青" end }
UnitGUID = function() return "Player-self" end
UnitNameUnmodified = function() return "晨星", "苏晚青" end
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = "-" } }
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
local party, raid, instance, guild, instanceRaid = false, false, false, false, false
IsInGroup = function(category) return category == 2 and instance or category == 1 and (party or raid) or false end
IsInRaid = function(category) return category == 2 and instanceRaid or category == 1 and raid or false end
IsInGuild = function() return guild end
C_ChatInfo = { SendChatMessage = function(text, kind, language, target)
    sends[#sends + 1] = { text = text, kind = kind, language = language, target = target }
end }
local channels = { { 1, "综合 - 艾尔文森林", false, 1 }, { 2, "交易 - 城市", false, 2 } }
GetChannelList = function()
    local result = {}
    for _, channel in ipairs(channels) do
        result[#result + 1] = channel[1]; result[#result + 1] = channel[2]; result[#result + 1] = channel[3]
    end
    return unpack(result)
end
GetChannelName = function(query)
    for _, channel in ipairs(channels) do
        if query == channel[1] or query == channel[2] then return channel[1], channel[2] end
    end
    return 0, nil
end
C_ChatInfo.GetChannelInfoFromIdentifier = function(identifier)
    assert(type(identifier) == "string", "native channel identifier must be a string")
    for _, channel in ipairs(channels) do
        if identifier == tostring(channel[1]) then
            return {localID=channel[1],name=channel[2],zoneChannelID=channel[4] or 0,channelType=channel[4] and 1 or 3}
        end
    end
end
local secret = setmetatable({ secret = true }, { __tostring = function() error("secret coercion") end,
    __index = function() error("secret access") end, __eq = function() error("secret comparison") end })
issecretvalue = function(value) return type(value) == "table" and rawget(value, "secret") == true end

local NS = { NotifyChanged = function() notices = notices + 1 end }
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Core.lua"))("MyForeverChat", NS)
local db = NS.InitDB(nil)
eq(NS.ChannelRemindersEnabled(), false, "new saves require explicit public-channel reminder opt-in")
eq(db.channelRemindersEnabled, false, "default channel reminder preference is persisted as false")
eq(#sends, 0, "initialization never sends")
eq(#NS.GetConversations(), 4, "four fixed conversations")
eq(NS.GetConversations()[1].id, "guild", "guild pinned first")
eq(NS.GetConversations()[2].id, "group", "party pinned second")
eq(NS.GetConversations()[3].id, "raid", "raid pinned third")
eq(NS.GetConversations()[4].id, "say", "nearby remains outside the priority three")
for _, id in ipairs({ "guild", "group", "raid" }) do
    eq(NS.IsPriorityConversation(db.conversations[id]), true, "priority category " .. id)
end
eq(NS.IsPriorityConversation(db.conversations.say), false, "nearby is not automatically prioritized")
eq(NS.IsPriorityConversation(secret), false, "restricted conversation rejected")
eq(NS.IsPriorityConversation({kind=secret}), false, "restricted kind rejected")
eq(NS.GetSelected().id, "group", "default selection")

local function incoming(event, text, author, lineID, guid, channelIndex, channelBaseName, zoneChannelID)
    if zoneChannelID == nil then
        for _, channel in ipairs(channels) do if channel[1] == channelIndex then zoneChannelID = channel[4] end end
    end
    return NS.HandleEvent(event, text, author, "通用语", "频道显示名", "", "", zoneChannelID or 0,
        channelIndex or 0, channelBaseName or "", 0, lineID, guid)
end
local before = notices
eq(incoming("CHAT_MSG_WHISPER", "你好", "小鱼-服务器甲", 1, "Player-other"), true, "incoming whisper")
local first = db.conversations["whisper:小鱼-服务器甲"]
eq(first.messages[1].text, "你好", "raw message retained")
eq(first.messages[1].outgoing, false, "incoming direction")
eq(first.unread, 1, "unselected incoming unread")
eq(db.lastWhisperId, first.id, "last whisper for reply shortcut")
eq(notices, before + 1, "callback after received message")
eq(NS.UnreadTotal(), 1, "total unread")
incoming("CHAT_MSG_WHISPER", "另一个人", "小鱼-服务器乙", 2, "Player-other2")
eq(#NS.GetConversations(), 6, "different realms never merged")
eq(db.conversations["whisper:小鱼-服务器乙"].messages[1].text, "另一个人", "second realm owns message")

local surname = NS.OpenWhisper("  家族 名-角色 姓  ")
eq(surname.target, "家族 名-角色 姓", "preserve internal surname spaces and hyphens")
eq(NS.GetSelected().id, surname.id, "open whisper selects")
eq(NS.OpenWhisper(""), nil, "empty target rejected")
eq(NS.OpenWhisper("角色\n命令"), nil, "control target rejected")
eq(NS.OpenWhisper("/reload"), nil, "command target rejected")
eq(NS.OpenWhisper(secret), nil, "secret target rejected without coercion")
local accented = NS.OpenWhisper("Éloïse-龙 骑")
eq(accented.id, "whisper:Éloïse-龙 骑", "high UTF-8 bytes remain exact")
local asciiCase = NS.OpenWhisper("Alice-Realm")
eq(asciiCase.id, "whisper:alice-realm", "only ASCII uppercase is folded")
eq(NS.OpenWhisper("ALICE-REALM"), asciiCase, "ASCII case variants share contact")

NS.Select(first.id)
eq(first.unread, 0, "select marks read")
incoming("CHAT_MSG_WHISPER", "还在吗", first.target, 3, "Player-other")
eq(first.unread, 0, "visible selected conversation read")
db.shown = false
incoming("CHAT_MSG_WHISPER", "新消息", first.target, 4, "Player-other")
eq(first.unread, 1, "hidden selected conversation unread")
eq(NS.MarkRead(first.id), true, "mark read")
db.shown = true

local count = #first.messages
incoming("CHAT_MSG_WHISPER_INFORM", "我在", first.target, 5, "Player-self")
eq(#first.messages, count + 1, "whisper inform appended once")
eq(first.messages[#first.messages].author, "晨星-苏晚青", "inform sender is player, not recipient")
eq(first.messages[#first.messages].outgoing, true, "inform direction")
eq(incoming("CHAT_MSG_WHISPER_INFORM", "我在", first.target, 5, "Player-self"), false, "duplicate lineID ignored")
eq(#first.messages, count + 1, "duplicate not appended")

for index, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    incoming(event, event, "队友-全名", 100 + index, "Player-other")
end
eq(#db.conversations.group.messages, 4, "party and instance party stay in party conversation")
eq(#db.conversations.raid.messages, 2, "raid events have a separate conversation")
eq(db.conversations.group.messages[1].chatType, "PARTY", "party category saved")
eq(db.conversations.raid.messages[2].chatType, "RAID_LEADER", "raid leader category saved")
instanceRaid = true
incoming("CHAT_MSG_INSTANCE_CHAT", "副本团队", "队友-全名", 110, "Player-other")
eq(#db.conversations.raid.messages, 3, "instance raid event reaches raid conversation")
eq(db.conversations.raid.messages[3].chatType, "INSTANCE_CHAT", "instance source type retained")
instanceRaid = false
incoming("CHAT_MSG_SAY", "附近文字", "路人-全名", 120, "Player-other")
incoming("CHAT_MSG_YELL", "大喊文字", "路人-全名", 121, "Player-other")
eq(#db.conversations.say.messages, 2, "say and yell grouped")
incoming("CHAT_MSG_GUILD", "公会文字", "朋友-全名", 122, "Player-other")
eq(#db.conversations.guild.messages, 1, "guild routed")
incoming("CHAT_MSG_PARTY", "自己", "别名显示", 123, "Player-self")
eq(db.conversations.group.messages[5].outgoing, true, "GUID identifies player regardless of display name")
incoming("CHAT_MSG_PARTY", "同名不同人", "晨星-苏晚青", 124, "Player-other")
eq(db.conversations.group.messages[6].outgoing, false, "different safe GUID overrides matching name")
incoming("CHAT_MSG_PARTY", "名称回退", "晨星-苏晚青", 125, nil)
eq(db.conversations.group.messages[7].outgoing, true, "full-name fallback without GUID")
incoming("CHAT_MSG_PARTY", "不能只看名", "晨星", 126, nil)
eq(db.conversations.group.messages[8].outgoing, false, "first name alone is not own identity")
NameUtil = nil
incoming("CHAT_MSG_PARTY", "原生分隔符回退", "晨星-苏晚青", 127, nil)
eq(db.conversations.group.messages[9].outgoing, true, "surname separator fallback")
NameUtil = { GetUnmodifiedUnitFullName = function() return "晨星-苏晚青" end }

local beforeSecret = #first.messages
eq(incoming("CHAT_MSG_WHISPER", secret, first.target, 130, "Player-other"), false, "secret text dropped")
eq(incoming("CHAT_MSG_WHISPER", "文字", secret, 131, "Player-other"), false, "secret author dropped")
eq(#first.messages, beforeSecret, "secret events not persisted")
eq(incoming("CHAT_MSG_WHISPER", "公开文字", first.target, secret, secret), true, "public text can survive unavailable IDs")
eq(NS.HandleEvent(secret, "text", "author"), false, "secret event guard")

eq(NS.SyncChannels(), true, "joined channels discovered")
eq(NS.SyncChannels(), false, "unchanged channel sync quiet")
local channel = db.conversations["channel-zone:1"]
eq(channel.target, "综合 - 艾尔文森林", "stable channel name stored")
incoming("CHAT_MSG_CHANNEL", "频道内容", "路人-全名", 140, "Player-other", 1, "综合")
eq(channel.messages[1].text, "频道内容", "event channel index resolves current full name")
NS.Select(channel.id)
channels[1][1] = 7
eq(NS.Send("切号后发送"), true, "current channel index resolved at send")
eq(sends[#sends].target, 7, "never cached channel index")
eq(sends[#sends].kind, "CHANNEL", "channel send type")
channels[1][3] = true
eq(NS.Send("频道已停用"), false, "disabled channel refuses send")
channels[1][3] = false
table.remove(channels, 1)
eq(NS.Send("已经离开"), false, "left channel refuses send")
eq(NS.SyncChannels(), true, "leave updates availability")
eq(channel.available, false, "left channel history preserved but unavailable")
local oldChannelList = GetChannelList
GetChannelList = nil
GetNumDisplayChannels = function() return 3 end
GetChannelDisplayInfo = function(index)
    if index == 1 then return "标题", true, false, 0, 0, true end
    if index == 2 then return "交易", false, false, 2, 20, true end
    return "语音队伍", false, false, 0, 5, true
end
eq(NS.SyncChannels(), false, "modern display-list fallback preserves already known active channel")
local trade = db.conversations["channel-zone:2"]
eq(trade.available, true, "native list discovers active numbered text channels")
eq(db.conversations["channel:标题"], nil, "native headers excluded")
eq(db.conversations["channel:语音队伍"], nil, "non-channel display rows excluded")
GetChannelList = oldChannelList

eq(NS.UTF8Bytes("你好"), 6, "UTF-8 byte length")
eq(NS.UTF8Bytes(secret), nil, "secret byte count refused")
eq(NS.ValidateText(string.rep("中", 85)), string.rep("中", 85), "255-byte Chinese text accepted intact")
eq(NS.ValidateText(string.rep("中", 86)), nil, "overlength Chinese not truncated")
eq(NS.ValidateText(" /reload"), nil, "slash command refused")
eq(NS.ValidateText("两行\n文字"), nil, "embedded newline refused")
eq(NS.ValidateText("   "), nil, "empty message refused")
eq(NS.ValidateText(secret), nil, "secret send text refused")
local longItemLink = "|cnIQ4:|Hitem:123:" .. string.rep("2:", 180) .. "|h[物品]|h|r"
local visibleBytes, linkBytes = NS.ChatMessageBytes("给你 " .. longItemLink)
eq(visibleBytes, #"给你 [物品]", "item link label and message count toward visible bytes")
eq(linkBytes, #longItemLink - #"[物品]", "item link payload and native color count toward link bytes")
eq(NS.ValidateText(longItemLink), longItemLink, "long item link is accepted intact")
eq(NS.ValidateText(string.rep("中", 85) .. longItemLink), nil, "valid links do not bypass the visible text limit")
eq(NS.ValidateText(string.rep(longItemLink, 3)), nil, "link markup has its own length limit")
eq(NS.ValidateText(longItemLink:gsub("|", "||")), nil, "escaped links are counted as literal text")

NS.Select("group")
eq(NS.Send("没有队伍"), false, "no group fails")
party = true
eq(NS.Send("队伍文字"), true, "party send")
eq(sends[#sends].kind, "PARTY", "party route")
raid = true
eq(NS.Send("团队中的小队文字"), true, "party subgroup send inside home raid")
eq(sends[#sends].kind, "PARTY", "party selection never switches to raid")
NS.Select("raid")
eq(NS.Send("团队文字"), true, "raid send")
eq(sends[#sends].kind, "RAID", "explicit raid selection uses raid")
instance = true
NS.Select("group")
eq(NS.Send("副本文字"), true, "instance party send")
eq(sends[#sends].kind, "INSTANCE_CHAT", "instance party priority")
NS.Select("raid")
eq(NS.Send("家乡团队文字"), true, "instance party does not replace home raid route")
eq(sends[#sends].kind, "RAID", "raid does not leak into instance party")
instanceRaid = true
eq(NS.Send("副本团队文字"), true, "instance raid send")
eq(sends[#sends].kind, "INSTANCE_CHAT", "instance raid routes to instance chat")
NS.Select("group")
eq(NS.Send("家乡小队文字"), true, "party selects home group while instance raid exists")
eq(sends[#sends].kind, "PARTY", "party never broadcasts to instance raid")
party, raid = false, false
local noSendCount = #sends
eq(NS.Send("不能误发团队"), false, "party unavailable with only instance raid")
eq(#sends, noSendCount, "unavailable party preserves audience")
instanceRaid = false
NS.Select("raid")
eq(NS.Send("不能误发小队"), false, "raid unavailable with only instance party")
eq(#sends, noSendCount, "unavailable raid preserves audience")
local knownRaidAPI = IsInRaid
NS.Select("group")
IsInRaid = function() return secret end
eq(NS.Send("不能猜测副本类型"), false, "restricted instance raid state cannot broadcast a party reply")
eq(#sends, noSendCount, "restricted group category sends nothing")
IsInRaid = function() return nil end
eq(NS.Send("没有副本类型"), false, "missing instance raid state cannot broadcast a party reply")
eq(#sends, noSendCount, "unknown group category sends nothing")
IsInRaid = knownRaidAPI
instance = false
NS.Select("guild")
eq(NS.Send("无公会"), false, "no guild fails")
guild = true
eq(NS.Send("公会发言"), true, "guild send")
eq(sends[#sends].kind, "GUILD", "guild route")
NS.Select("say")
eq(NS.Send("附近发言"), true, "nearby send")
eq(sends[#sends].kind, "SAY", "nearby uses say")

NS.Select(first.id)
first.draft = "待发送草稿"
local records = #first.messages
local ok, status = NS.Send(first.draft)
eq(ok, true, "whisper submission")
includes(status, "尚未确认送达")
eq(sends[#sends].target, "小鱼-服务器甲", "full whisper target unchanged")
eq(#first.messages, records, "send waits for real echo")
eq(first.draft, "待发送草稿", "submission keeps draft")
local presence, presenceCalls = "offline", 0
NS.GetContactPresence = function(conversation)
    eq(conversation, first, "send checks the currently selected recipient")
    presenceCalls = presenceCalls + 1
    return presence
end
local beforeOffline = #sends
ok, status = NS.Send(first.draft)
eq(ok, false, "known offline whisper is blocked before native send")
eq(status, "对方离线，消息未发送。草稿已保留。", "offline failure explains draft retention")
eq(#sends, beforeOffline, "offline whisper does not reach native API")
eq(first.draft, "待发送草稿", "offline rejection preserves draft")
presence = "online"
eq(NS.Send(first.draft), true, "recipient becoming online permits sending")
presence = "unknown"
eq(NS.Send(first.draft), true, "unknown presence permits a deliberate attempt")
eq(presenceCalls, 3, "presence is rechecked for every send attempt")
presence = secret
eq(NS.Send(first.draft), true, "restricted presence is not compared or coerced")
NS.GetContactPresence = function() error("restricted presence API") end
eq(NS.Send(first.draft), true, "failed presence lookup remains unknown")
NS.GetContactPresence = nil
eq(NS.Send(first.draft), true, "missing presence lookup preserves native sending")
local oldSender, oldChannelInfo = C_ChatInfo.SendChatMessage, C_ChatInfo.GetChannelInfoFromIdentifier
C_ChatInfo.SendChatMessage = function() error("restricted") end
eq(NS.Send("测试受限"), false, "restricted API error surfaced")
C_ChatInfo = nil
eq(NS.Send("接口缺失"), false, "missing modern API fails")
C_ChatInfo = { SendChatMessage = oldSender, GetChannelInfoFromIdentifier = oldChannelInfo }

NS.ClearSelected()
eq(#first.messages, 0, "clear selected history")
eq(first.draft, "待发送草稿", "clear preserves draft")
for index = 1, 65 do incoming("CHAT_MSG_WHISPER", tostring(index), first.target, 200 + index, "Player-other") end
eq(#first.messages, 60, "per-conversation retention limit")
eq(first.messages[1].text, "6", "oldest messages trimmed")
for index = 1, 40 do
    stamp = stamp + 1
    incoming("CHAT_MSG_WHISPER", "一条消息", "联系人-" .. index, 400 + index, "Player-" .. index)
end
eq(#NS.GetConversations(), 34, "30 dynamic contacts plus 4 fixed")
eq(db.conversations[first.id], first, "selected conversation survives contact pruning")
eq(NS.GetConversations()[5].target, "联系人-40", "dynamic conversations sorted newest first")

local restored = NS.InitDB(db)
eq(#NS.GetConversations(), 34, "reload bounded conversations")
eq(NS.GetSelected().draft, "待发送草稿", "draft survives reload")
eq(#NS.GetSelected().messages, 60, "history survives reload")
eq(restored.lastWhisperId, "whisper:联系人-40", "last whisper survives reload")
eq(incoming("CHAT_MSG_WHISPER", "重登后行号重新开始", first.target, 265, "Player-other"), true, "new session line IDs do not collide with persisted history")
eq(NS.GetSelected().messages[60].text, "重登后行号重新开始", "new session message retained")
restored.window = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 112, y = 58, width = 960, height = 640 }
restored.launcher = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 25, y = -60 }
local positioned = NS.InitDB(restored)
eq(positioned.window.point, "BOTTOMLEFT", "window anchor persists")
eq(positioned.window.x, 112, "window offset persists")
eq(positioned.window.width, 960, "window width persists")
eq(positioned.window.height, 640, "window height persists")
eq(positioned.launcher.point, "TOPLEFT", "launcher anchor persists")
eq(positioned.launcher.y, -60, "launcher offset persists")
local bad = NS.InitDB({ selectedId = secret, shown = false, x = "bad", point = "bad", conversations = {
    group = { messages = { { text = secret, author = "name" }, { text = "good", author = "name", outgoing = secret, time = secret } }, unread = -8 },
    invalid = { kind = "whisper", target = secret },
} })
eq(#NS.GetConversations(), 4, "malformed contact rejected")
eq(#bad.conversations.group.messages, 1, "secret saved message omitted")
eq(bad.conversations.group.messages[1].outgoing, false, "secret boolean not compared")
eq(bad.selectedId, "group", "invalid selected ID repaired")
eq(bad.shown, false, "visibility preserved")
eq(bad.point, "CENTER", "anchor repaired")
eq(bad.x, 0, "offset repaired")
eq(bad.conversations.group.unread, 0, "invalid unread repaired")
eq(bad.window.width, 840, "default window size")
eq(bad.launcher.y, -235, "default launcher location")

-- Contact-management behavior: visible unread counts survive mute, pinning is
-- bounded, and admission never destroys protected work to make room for spam.
local sendsBeforeManagement = #sends
db = NS.InitDB({})
eq(NS.TogglePin("group"), false, "fixed conversations cannot be pinned again")
eq(NS.TogglePin("missing"), false, "pin missing contact fails")
eq(NS.ToggleMute("missing"), false, "mute missing contact fails")
eq(NS.CloseConversation("guild"), false, "fixed conversation cannot close")
eq(NS.MarkAllRead(), false, "already read state unchanged")
local contacts = {}
for index = 1, 11 do
    stamp = stamp + 1
    contacts[index] = NS.OpenWhisper("好友-" .. index)
    if index <= 10 then eq(NS.TogglePin(contacts[index].id), true, "first ten pins allowed") end
end
local pinnedOK, pinNote = NS.TogglePin(contacts[11].id)
eq(pinnedOK, false, "eleventh pin refused")
includes(pinNote, "10")
eq(contacts[11].pinned, false, "refused pin leaves state untouched")
eq(NS.GetConversations()[5].id, contacts[10].id, "pinned conversations precede newer unpinned contacts")
stamp = stamp + 1
incoming("CHAT_MSG_WHISPER", "置顶联系人新消息", contacts[1].target, 900, "Player-friend")
eq(NS.GetConversations()[5].id, contacts[1].id, "pinned conversations still sort by recency")
eq(contacts[1].unread, 1, "unread message before mute")
eq(NS.ToggleMute(contacts[1].id), true, "mute contact")
eq(contacts[1].unread, 1, "mute does not mark contact read")
eq(NS.UnreadTotal(), 0, "muted contact excluded from global unread")
incoming("CHAT_MSG_WHISPER", "免打扰仍接收", contacts[1].target, 901, "Player-friend")
eq(contacts[1].unread, 2, "muted contact keeps accumulating local unread")
eq(NS.UnreadTotal(), 0, "new muted message still excluded")
eq(NS.ToggleMute(contacts[1].id), true, "unmute contact")
eq(NS.UnreadTotal(), 2, "unmute restores existing unread contribution")
NS.ToggleMute(contacts[1].id)
incoming("CHAT_MSG_GUILD", "固定会话提醒", "公会-朋友", 902, "Player-guild")
eq(NS.ToggleMute("guild"), true, "fixed conversation can be muted")
eq(NS.UnreadTotal(), 0, "muted fixed conversation excluded")
local markNotice = notices
eq(NS.MarkAllRead(), true, "mark all read includes muted contacts")
eq(contacts[1].unread, 0, "mark all cleared muted local badge")
eq(db.conversations.guild.unread, 0, "mark all cleared guild badge")
eq(notices, markNotice + 1, "mark all notifies once")
eq(NS.MarkAllRead(), false, "second mark all no change")

local contactID = contacts[1].id
contacts[1].draft = "保存中的草稿"
db = NS.InitDB(db)
eq(db.conversations[contactID].pinned, true, "pin persists across reload")
eq(db.conversations[contactID].muted, true, "mute persists across reload")
eq(db.conversations.guild.muted, true, "fixed mute persists")
eq(db.conversations[contactID].draft, "保存中的草稿", "draft persists beside contact flags")
NS.Select(contactID)
local closeOK, closeNote = NS.CloseConversation(contactID)
eq(closeOK, false, "draft blocks ordinary close")
includes(closeNote, "草稿")
eq(db.conversations[contactID].draft, "保存中的草稿", "refused close preserves draft")
eq(NS.CloseConversation(contactID, secret), false, "secret value cannot grant force-close")
eq(NS.CloseConversation(contactID, true), true, "explicit confirmed close may discard draft")
eq(db.conversations[contactID], nil, "confirmed close removes contact")
eq(db.selectedId, "group", "closing selection returns to fixed group")
eq(db.lastWhisperId, nil, "closing latest whisper clears quick-reply target")
incoming("CHAT_MSG_WHISPER", "关闭后再次联系", "好友-1", 903, "Player-friend")
eq(db.conversations[contactID].messages[1].text, "关闭后再次联系", "new message reopens closed contact")
eq(db.conversations[contactID].pinned, false, "reopened contact starts unpinned")
NS.SyncChannels()
eq(NS.CloseConversation("channel-zone:2", true), false, "channel cannot be closed even with force")

db = NS.InitDB({})
contacts = {}
for index = 1, 30 do
    stamp = stamp + 1
    contacts[index] = NS.OpenWhisper("保护联系人-" .. index)
    contacts[index].draft = "未发送草稿" .. index
    if index <= 10 then NS.TogglePin(contacts[index].id) end
end
local rejected, rejection = NS.OpenWhisper("新骚扰-角色")
eq(rejected, nil, "all protected contacts refuse new conversation")
includes(rejection, "30")
eq(#NS.GetConversations(), 34, "rejected admission preserves 30 dynamic cap")
local eventOK, eventNote = incoming("CHAT_MSG_WHISPER", "新陌生消息", "另一个-角色", 1001, "Player-stranger")
eq(eventOK, false, "unsolicited incoming cannot evict protected contacts")
includes(eventNote, "草稿")
eq(NS.lastNotice, rejection, "capacity rejection available to UI")
eq(NS.SyncChannels(), false, "channel discovery gracefully handles protected capacity")
eq(#NS.GetConversations(), 34, "channel sync cannot exceed capacity")
for index, contact in ipairs(contacts) do
    eq(db.conversations[contact.id].draft, "未发送草稿" .. index, "all existing drafts preserved under spam")
end
contacts[11].draft = ""
eq(incoming("CHAT_MSG_WHISPER", "现在有空位", "新的-联系人", 1002, "Player-new"), true, "unprotected slot permits new conversation")
eq(NS.lastNotice, nil, "successful admission clears stale capacity notice")
eq(db.conversations[contacts[11].id], nil, "oldest eligible contact evicted")
eq(#NS.GetConversations(), 34, "successful admission remains capped")
eq(db.conversations[contacts[1].id].pinned, true, "old pinned contact survives admission")
eq(db.conversations[contacts[30].id], contacts[30], "current contact survives admission")
eq(NS.TogglePin("whisper:新的-联系人"), false, "pin cap remains after pruning")
eq(NS.TogglePin(contacts[1].id), true, "unpin releases pin quota")
eq(NS.TogglePin("whisper:新的-联系人"), true, "released pin slot reusable")
eq(NS.CloseConversation(contacts[30].id), false, "current draft still blocks close")
eq(NS.CloseConversation(contacts[30].id, true), true, "confirmed current draft close")
eq(db.selectedId, "group", "confirmed close changes selection safely")
eq(#sends, sendsBeforeManagement, "contact management never sends chat")
for _, conversation in pairs(db.conversations) do
    if conversation.kind == "whisper" then conversation.pinned = true end
end
db = NS.InitDB(db)
local restoredPins = 0
for _, conversation in pairs(db.conversations) do if conversation.pinned then restoredPins = restoredPins + 1 end end
eq(restoredPins, 10, "oversized saved pin flags normalize to ten without deleting conversations")
eq(db.conversations[contacts[1].id].draft, "未发送草稿1", "normalizing saved pins preserves drafts")

-- Target discovery is metadata, never a synthetic message or selection.
local sendsBeforeDiscovery = #sends
db = NS.InitDB({})
eq(db.channelsCollapsed, true, "channels start collapsed")
eq(db.peopleCollapsed, false, "people start expanded")
eq(NS.lastIncoming, nil, "restore never creates an incoming notification")
local foundNotice = notices
local found = NS.UpsertContact("Éowyn-龙 骑", {
    guid = "Player-123-ABC", classToken = "PRIEST", className = "牧师", level = 18,
    raceName = "人类", raceToken = "Human", sex = 3, displayID = 1234, seenAt = 2000,
}, true)
eq(found.id, "whisper:Éowyn-龙 骑", "discovered Unicode identity preserved")
eq(#NS.GetConversations(), 4, "discovery does not open a conversation")
eq(#NS.GetRecentPeople(), 1, "discovery adds one recent person")
eq(NS.GetRecentPeople()[1], found, "recent person stored separately")
eq(found.messages, nil, "recent person has no chat history")
eq(db.selectedId, "group", "discovery leaves selected conversation")
eq(db.lastWhisperId, nil, "discovery leaves reply target")
eq(found.unread, nil, "recent person has no unread state")
eq(NS.lastIncoming, nil, "discovery has no incoming notification")
eq(notices, foundNotice + 1, "discovery refreshes UI")
eq(found.profile.classToken, "PRIEST", "class metadata stored")
eq(found.profile.seenAt, 2000, "last seen distinct from chat timestamp")
found = NS.OpenWhisper(found.target)
eq(found.profile.classToken, "PRIEST", "explicit open adopts recent metadata")
found.draft, found.unread = "原草稿", 3
stamp = stamp + 1
incoming("CHAT_MSG_WHISPER", "真正私聊", "真实-好友", 1200, "Player-real")
local lastReply, lastMessage = db.lastWhisperId, NS.lastIncoming
local updated = NS.UpsertContact("Éowyn-龙 骑", { level = 19, seenAt = 2100, classToken = secret }, true)
eq(updated, found, "same complete name updates same contact")
eq(found.profile.level, 19, "known level updated")
eq(found.profile.classToken, "PRIEST", "restricted new field preserves prior public data")
eq(found.draft, "原草稿", "metadata update keeps draft")
eq(found.unread, 3, "metadata update keeps unread")
eq(db.lastWhisperId, lastReply, "metadata update keeps last reply target")
eq(NS.lastIncoming, lastMessage, "metadata update cannot fake toast")
eq(NS.GetConversations()[5].id, lastReply, "new chat stays ahead of a target observation")
NS.TogglePin(found.id)
eq(NS.GetConversations()[5], found, "pinned chat remains ahead of newer chat")
local alternate = NS.UpsertContact("Éowyn-别 服", { level = 20 }, true)
eq(alternate == found, false, "different complete name never merged")
eq(db.conversations[alternate.id], nil, "another target does not open a chat")
eq(NS.UpsertContact(secret, {}, true), nil, "secret discovered name refused")
eq(NS.UpsertContact("不可判断-来源", {}, secret), nil, "restricted passive flag never becomes manual eviction permission")

local filtered = NS.RestoreProfile({
    guid = secret, classToken = "Interface\\Icons\\Bad", className = secret,
    raceName = "|Hplayer:injected", raceToken = "../Portrait", level = 0 / 0,
    sex = 99, displayID = math.huge, seenAt = secret, portrait = "arbitrary texture",
})
eq(next(filtered), nil, "secret invalid numeric and texture injection fields omitted")
filtered = NS.RestoreProfile({ level = -1, sex = 2.5, displayID = 1.5, seenAt = -1, raceToken = "Human" })
eq(filtered.level, nil, "unknown level not stored as real level")
eq(filtered.sex, nil, "fractional sex rejected")
eq(filtered.displayID, nil, "fractional portrait ID rejected")
eq(filtered.seenAt, nil, "negative last-seen timestamp rejected")
eq(filtered.raceToken, "Human", "safe race token retained")
eq(next(NS.RestoreProfile(secret)), nil, "secret profile table never indexed")
db.channelsCollapsed, db.peopleCollapsed = false, true
db = NS.InitDB(db)
found = db.conversations[found.id]
eq(found.profile.level, 19, "profile survives reload")
eq(NS.GetRecentPeople()[1].id, alternate.id, "recent ordering survives reload")
eq(db.channelsCollapsed, false, "expanded channels survives reload")
eq(db.peopleCollapsed, true, "collapsed people survives reload")
eq(NS.lastIncoming, nil, "saved message history does not replay notifications")
db = NS.InitDB({ channelsCollapsed = secret, peopleCollapsed = secret })
eq(db.channelsCollapsed, true, "restricted collapse input defaults safely")
eq(db.peopleCollapsed, false, "restricted people input defaults safely")

-- Full conversation history wins over passive target churn.
local historical = {}
for index = 1, 30 do
    stamp = stamp + 1
    incoming("CHAT_MSG_WHISPER", "真实聊天" .. index, "聊天好友-" .. index, 1300 + index, "Player-" .. index)
    historical[index] = db.conversations["whisper:聊天好友-" .. index]
end
local fullReply = db.lastWhisperId
local passiveFound = NS.UpsertContact("新选中-路人", { classToken = "MAGE" }, true)
eq(passiveFound.target, "新选中-路人", "recent people have independent capacity")
eq(db.conversations[passiveFound.id], nil, "full conversation history is untouched by discovery")
eq(#NS.GetConversations(), 34, "discovery preserves conversation cap")
eq(db.lastWhisperId, fullReply, "observation keeps reply target")
eq(db.conversations[historical[1].id].messages[1].text, "真实聊天1", "oldest real chat not evicted by target selection")
eq(NS.UpsertContact(historical[1].target, { level = 25 }, true), historical[1], "existing profile can update at capacity")
eq(historical[1].profile.level, 25, "full list accepts metadata update")
NS.ClearSelected() -- Selected fixed group; historical contacts remain untouched.

local legacy = {}
for index = 1, 7 do
    local target = "路人-" .. index
    legacy[index] = { kind = "whisper", target = target, autoDiscovered = true, profile = { seenAt = 3000 + index } }
end
legacy[1].pinned = true
legacy[2].draft = "保护草稿"
legacy[4].messages = { { text = "已经开始聊天", author = "路人-4", time = 1300 } }
legacy[6].autoDiscovered = false
legacy[7].muted = true
db = NS.InitDB({ conversations = legacy, selectedId = "whisper:路人-3", lastWhisperId = "whisper:路人-4" })
eq(db.conversations["whisper:路人-5"], nil, "legacy passive-only chat is moved into recent people")
eq(NS.GetRecentPeople()[1].target, "路人-5", "legacy recent target preserved")
eq(db.conversations["whisper:路人-1"].pinned, true, "legacy pinned chat preserved")
eq(db.conversations["whisper:路人-2"].draft, "保护草稿", "legacy draft preserved")
eq(db.selectedId, "whisper:路人-3", "legacy selected chat preserved")
eq(db.lastWhisperId, "whisper:路人-4", "legacy reply target preserved")
eq(db.conversations["whisper:路人-4"].messages[1].text, "已经开始聊天", "legacy real history preserved")
eq(db.conversations["whisper:路人-6"].target, "路人-6", "legacy deliberate empty chat preserved")
eq(db.conversations["whisper:路人-7"].muted, true, "legacy muted chat preserved")
eq(incoming("CHAT_MSG_WHISPER", "新消息", "路人-5", 1400, "Player-five"), true, "real message opens migrated person's chat")
eq(db.conversations["whisper:路人-5"].profile.seenAt, 3005, "real message adopts migrated profile")
incoming("CHAT_MSG_SAY", "真实新消息", "路人-发言", 1500, "Player-speaker")
local notice = NS.lastIncoming
eq(notice.conversationId, "say", "incoming notice identifies conversation")
eq(notice.message, db.conversations.say.messages[#db.conversations.say.messages], "notice carries exact appended message object")
incoming("CHAT_MSG_WHISPER_INFORM", "自己的回复", "路人-6", 1501, "Player-self")
eq(NS.lastIncoming, notice, "outgoing echo does not create incoming toast")
incoming("CHAT_MSG_SAY", secret, "路人-发言", 1502, "Player-speaker")
eq(NS.lastIncoming, notice, "restricted event does not create incoming toast")
eq(#sends, sendsBeforeDiscovery, "target discovery never sends chat")

-- Appearance settings are bounded independent values, never references into a
-- caller's patch, and restoring the palette must not touch conversation state.
local defaults = NS.NormalizeAppearance(nil)
eq(defaults.fontSize, 14, "default font size")
eq(defaults.opacity, 0.98, "default opacity")
eq(defaults.theme, "midnight", "default theme")
eq(defaults.background[1], 0.051, "default background red")
eq(defaults.background[2], 0.067, "default background green")
eq(defaults.background[3], 0.118, "default background blue")
eq(defaults.accent[1], 0.486, "default accent red")
eq(defaults.accent[2], 0.576, "default accent green")
eq(defaults.accent[3], 1.0, "default accent blue")
defaults.background[1], defaults.accent[2], defaults.fontSize = 1, 0, 22
local freshDefaults = NS.NormalizeAppearance(secret)
eq(freshDefaults.background[1], 0.051, "returned colors cannot mutate internal defaults")
eq(freshDefaults.accent[2], 0.576, "accent default table is private")
eq(freshDefaults.fontSize, 14, "secret settings fall back safely")
local appearance = NS.NormalizeAppearance({
    fontSize = 50, opacity = -3, theme = "untrusted/path",
    background = { -2, 0 / 0, secret }, accent = { 3, 0.4, math.huge },
})
eq(appearance.fontSize, 22, "font maximum")
eq(appearance.opacity, 0.25, "opacity minimum")
eq(appearance.theme, "midnight", "unknown palette rejected")
eq(appearance.background[1], 0, "color channels clamp below range")
eq(appearance.background[2], 0.067, "NaN color falls back to matching default component")
eq(appearance.background[3], 0.118, "secret color falls back to matching default component")
eq(appearance.accent[1], 1, "color channels clamp above range")
eq(appearance.accent[2], 0.4, "valid color component preserved")
eq(appearance.accent[3], 1.0, "infinite color falls back")
appearance = NS.NormalizeAppearance({ fontSize = 11, opacity = 8, background = secret, accent = "bad", theme = secret })
eq(appearance.fontSize, 12, "font minimum")
eq(appearance.opacity, 1, "opacity maximum")
eq(appearance.background[1], 0.051, "secret color table never indexed")
eq(appearance.accent[2], 0.576, "malformed color table defaults")
appearance = NS.NormalizeAppearance({ fontSize = 18.9, opacity = 0 / 0 })
eq(appearance.fontSize, 18, "font normalized to integer")
eq(appearance.opacity, 0.98, "NaN opacity defaults")

local originalDB, originalConversations = db, db.conversations
local selection = NS.GetSelected()
selection.draft = "切换外观保留这份草稿"
local originalMessages, originalUnread = selection.messages, selection.unread
db.window.x, db.launcher.y = 139, -311
local patch = {
    fontSize = 17, opacity = 0.75, theme = "ocean",
    background = { 0.1, 0.2, 0.3 }, accent = { 0.4, 0.5, 0.6 },
    conversations = {}, selectedId = "guild", window = { x = 0 },
}
local appearanceNotice = notices
appearance = NS.UpdateAppearance(patch)
eq(appearance, db.appearance, "update returns stored settings")
eq(notices, appearanceNotice + 1, "appearance update notifies once")
eq(db, originalDB, "appearance update leaves DB identity")
eq(db.conversations, originalConversations, "patch cannot overwrite conversations")
eq(NS.GetSelected(), selection, "patch cannot switch selected conversation")
eq(db.window.x, 139, "patch cannot change window location")
eq(patch.background[1], 0.1, "update leaves input color unchanged")
eq(appearance.background == patch.background, false, "stored color never aliases input")
appearance.background[1] = 0.15
eq(patch.background[1], 0.1, "mutating stored color cannot mutate caller patch")
local partial = { background = { [2] = 0.4 }, theme = "custom" }
appearance = NS.UpdateAppearance(partial)
eq(appearance.background[1], 0.15, "partial color patch retains previous red")
eq(appearance.background[2], 0.4, "partial color patch changes green")
eq(appearance.background[3], 0.3, "partial color patch retains previous blue")
eq(partial.background[1], nil, "partial input table not backfilled")
eq(appearance.accent[2], 0.5, "unpatched accent retained")
eq(NS.UpdateAppearance(secret).fontSize, 17, "secret whole patch preserves existing settings")
eq(NS.UpdateAppearance({ fontSize = secret }).fontSize, 14, "secret field normalizes to default")
appearance = NS.UpdateAppearance({ theme = "violet", opacity = 0.62 })
eq(appearance.theme, "violet", "allowed theme label stored")
eq(appearance.background[2], 0.4, "theme label does not select palette on its own")
db = NS.InitDB(db)
eq(db.appearance.opacity, 0.62, "opacity survives reload")
eq(db.appearance.theme, "violet", "theme survives reload")
eq(db.appearance.background[2], 0.4, "custom component survives reload")
selection = NS.GetSelected()
originalMessages, originalConversations = selection.messages, db.conversations
local resetNotice = notices
appearance = NS.ResetAppearance()
eq(notices, resetNotice + 1, "reset notifies once")
eq(appearance.fontSize, 14, "reset font")
eq(appearance.opacity, 0.98, "reset opacity")
eq(appearance.theme, "midnight", "reset theme")
eq(appearance.accent[3], 1.0, "reset palette")
eq(selection.draft, "切换外观保留这份草稿", "appearance reset preserves draft")
eq(selection.messages, originalMessages, "appearance reset preserves exact history objects")
eq(selection.unread, originalUnread, "appearance reset preserves unread")
eq(db.conversations, originalConversations, "appearance reset preserves all conversations")
eq(db.window.x, 139, "appearance reset preserves window location")
eq(db.launcher.y, -311, "appearance reset preserves launcher location")
eq(#sends, sendsBeforeDiscovery, "appearance actions never send chat")

-- Explicit deletion removes only local conversation state and suppresses
-- passive rediscovery until the user or an actual whisper reopens the contact.
local sendsBeforeDeletion = #sends
db = NS.InitDB({})
db.shown = false
local deleteTarget = "Éowyn-龙 骑"
incoming("CHAT_MSG_WHISPER", "旧聊天第一条", deleteTarget, 1700, "Player-delete")
local deletedID = "whisper:" .. deleteTarget
local deleting = db.conversations[deletedID]
local untouched = NS.OpenWhisper("保留-好友")
untouched.draft = "另一个人的草稿"
NS.Select(deletedID)
deleting.draft = "将被确认删除的草稿"
incoming("CHAT_MSG_WHISPER", "旧聊天第二条", deleteTarget, 1701, "Player-delete")
eq(deleting.unread, 1, "deletion fixture has unread")
eq(NS.lastIncoming.conversationId, deletedID, "deletion fixture has pending incoming notice")
eq(NS.DeleteConversation(deletedID), false, "delete always requires explicit confirmation")
eq(NS.DeleteConversation(deletedID, false), false, "false does not confirm deletion")
eq(NS.DeleteConversation(deletedID, "true"), false, "truthy string is not confirmation")
eq(NS.DeleteConversation(deletedID, secret), false, "secret confirmation rejected without comparison")
eq(#deleting.messages, 2, "unconfirmed delete preserves history")
eq(deleting.draft, "将被确认删除的草稿", "unconfirmed delete preserves draft")
eq(db.deletedContacts[deletedID], nil, "unconfirmed delete writes no suppression")
eq(NS.DeleteConversation("guild", true), false, "fixed conversation cannot be deleted")
NS.SyncChannels()
eq(NS.DeleteConversation("channel-zone:2", true), false, "channel cannot be deleted")
local deleteNotice = notices
eq(NS.DeleteConversation(deletedID, true), true, "confirmed delete")
eq(notices, deleteNotice + 1, "successful delete notifies once")
eq(db.conversations[deletedID], nil, "deleted conversation removed")
eq(db.selectedId, "group", "deleted selection cleared")
eq(db.lastWhisperId, nil, "deleted quick-reply target cleared")
eq(NS.lastIncoming, nil, "deleted incoming notice cannot reappear")
eq(db.conversations[untouched.id], untouched, "other conversation object preserved")
eq(untouched.draft, "另一个人的草稿", "other draft preserved")
eq(type(db.deletedContacts[deletedID]), "number", "successful deletion stores bounded stamp")
local rediscovered, rediscoverError = NS.UpsertContact(deleteTarget, { level = 20 }, true)
eq(rediscovered, nil, "target selection cannot immediately restore deleted conversation")
includes(rediscoverError, "已删除")
eq(NS.UpsertContact(deleteTarget, { level = 20 }, false), nil, "metadata-only update cannot bypass deletion intent")
db = NS.InitDB(db)
eq(db.conversations[deletedID], nil, "deleted history stays absent after reload")
eq(type(db.deletedContacts[deletedID]), "number", "suppression persists through reload")
eq(NS.UpsertContact(deleteTarget, {}, true), nil, "passive suppression survives reload")

local reopened = NS.OpenWhisper(deleteTarget)
eq(reopened.id, deletedID, "explicit open restores same complete identity")
eq(db.deletedContacts[deletedID], nil, "explicit open clears suppression")
eq(#reopened.messages, 0, "manual restoration starts with empty history")
eq(reopened.draft, "", "manual restoration does not resurrect deleted draft")
eq(reopened.unread, 0, "manual restoration has no old unread")
NS.DeleteConversation(deletedID, true)
eq(incoming("CHAT_MSG_WHISPER", "新的真实回信", deleteTarget, 1702, "Player-delete"), true, "real incoming whisper restores deleted contact")
reopened = db.conversations[deletedID]
eq(#reopened.messages, 1, "incoming restoration contains only new message")
eq(reopened.messages[1].text, "新的真实回信", "incoming restoration does not revive old text")
eq(db.deletedContacts[deletedID], nil, "real incoming clears suppression")
NS.DeleteConversation(deletedID, true)
eq(incoming("CHAT_MSG_WHISPER_INFORM", "原生窗口发出的私聊", deleteTarget, 1703, "Player-self"), true, "real outgoing echo restores deleted contact")
eq(#db.conversations[deletedID].messages, 1, "outgoing restoration contains only its real echo")
eq(db.conversations[deletedID].messages[1].outgoing, true, "outgoing restoration retains direction")
eq(db.deletedContacts[deletedID], nil, "real outgoing clears suppression")
eq(NS.lastIncoming, nil, "outgoing restoration has no false incoming notice")
eq(NS.CloseConversation(deletedID), true, "legacy close retains compatible semantics")
eq(db.deletedContacts[deletedID], nil, "legacy close does not create deletion suppression")

db = NS.InitDB({})
local mutedChat = NS.OpenWhisper("自动-联系人1")
NS.ToggleMute(mutedChat.id)
for index = 2, 65 do
    NS.UpsertContact("自动-联系人" .. index, { seenAt = 6000 + index }, true)
end
eq(#NS.GetRecentPeople(), 60, "recent contacts have bounded storage")
eq(NS.GetRecentPeople()[1].target, "自动-联系人65", "newest observation appears first")
eq(NS.GetRecentPeople()[60].target, "自动-联系人6", "oldest recent observations age out")
eq(#NS.GetConversations(), 5, "observations do not enter the chat list")
eq(db.conversations[mutedChat.id].muted, true, "muted preference survives target churn")
eq(next(db.deletedContacts), nil, "recent eviction never creates deletion suppression")

db = NS.InitDB({})
for index = 1, 65 do
    local contact = NS.OpenWhisper("删除联系人-" .. index)
    NS.DeleteConversation(contact.id, true)
end
local suppressionCount = 0
for _ in pairs(db.deletedContacts) do suppressionCount = suppressionCount + 1 end
eq(suppressionCount, 60, "deletion suppression bounded to sixty")
eq(db.deletedContacts["whisper:删除联系人-1"], nil, "oldest suppression ages out")
eq(db.deletedContacts["whisper:删除联系人-5"], nil, "all five oldest suppressions age out")
eq(type(db.deletedContacts["whisper:删除联系人-6"]), "number", "sixtieth newest suppression retained")
eq(type(db.deletedContacts["whisper:删除联系人-65"]), "number", "newest suppression retained")
eq(NS.UpsertContact("删除联系人-65", {}, true), nil, "latest deletion still suppressed")
eq(NS.UpsertContact("删除联系人-1", {}, true) ~= nil, true, "aged-out marker may be rediscovered")
db = NS.InitDB({ deletedContacts = {
    ["whisper:ALICE-Realm"] = 25,
    ["whisper:坏值-一"] = secret,
    ["whisper:坏值-二"] = 0 / 0,
    ["whisper:坏值-三"] = math.huge,
    ["whisper:坏值-四"] = -1,
    ["whisper:坏值-五"] = 1.5,
    ["whisper:/reload"] = 3,
    ["guild"] = 8,
    [secret] = 9,
} })
eq(db.deletedContacts["whisper:alice-realm"], 1, "suppression key safely canonicalized and stamp normalized")
suppressionCount = 0
for _ in pairs(db.deletedContacts) do suppressionCount = suppressionCount + 1 end
eq(suppressionCount, 1, "malformed and restricted suppression records rejected")
eq(#sends, sendsBeforeDeletion, "deletion and restoration never send messages")

-- Older releases did not store message source types. Keep their complete group
-- history and draft; never guess which older text belonged to a raid.
local legacy = NS.InitDB({selectedId="group", conversations={group={
    messages={{text="旧队伍历史",author="队友",id="old:1",time=20}},
    draft="旧队伍草稿", unread=1, muted=true,
}}})
eq(legacy.conversations.group.title, "小队", "legacy group ID gets party title")
eq(legacy.conversations.group.messages[1].text, "旧队伍历史", "legacy group history preserved")
eq(legacy.conversations.group.messages[1].chatType, nil, "legacy history source is not invented")
eq(legacy.conversations.group.draft, "旧队伍草稿", "legacy group draft preserved")
eq(legacy.conversations.group.unread, 1, "legacy unread preserved")
eq(legacy.conversations.group.muted, true, "legacy mute preserved")
eq(legacy.conversations.raid.muted, true, "legacy mixed-team mute inherited by first separate raid")
eq(#legacy.conversations.raid.messages, 0, "new raid history starts empty")
eq(legacy.conversations.raid.draft, "", "legacy group draft never copied into raid")
incoming("CHAT_MSG_RAID", "新团队历史", "队友", 2200, "Player-other")
incoming("CHAT_MSG_WHISPER_INFORM", "私聊回显", "私聊目标", 2201, "Player-self")
local typed = NS.InitDB(NS.db)
eq(typed.conversations.raid.messages[1].chatType, "RAID", "type survives reload")
eq(typed.conversations["whisper:私聊目标"].messages[1].chatType, "WHISPER", "inform normalized for type coloring")
local explicitRaid = NS.InitDB({conversations={group={muted=true},raid={muted=false,draft="团队草稿"}}})
eq(explicitRaid.conversations.raid.muted, false, "existing raid preference is not overwritten on reload")
eq(explicitRaid.conversations.raid.draft, "团队草稿", "existing raid draft preserved")
local safeTypes = NS.InitDB({conversations={guild={messages={
    {text="受限类型",author="队友",chatType=secret},
    {text="伪造类型",author="队友",chatType="ADDON"},
    {text="真实类型",author="队友",chatType="GUILD"},
}}}})
eq(safeTypes.conversations.guild.messages[1].chatType, nil, "secret persisted type safely omitted")
eq(safeTypes.conversations.guild.messages[2].chatType, nil, "unknown persisted type omitted")
eq(safeTypes.conversations.guild.messages[3].chatType, "GUILD", "whitelisted persisted type retained")

-- Store per-message sender metadata before notifying UI observers. Public
-- speakers must not be admitted into private conversations or recent contacts.
local profileCalls = {}
local providedProfile = {guid="Player-speaker",level=38,className="法师",classToken="MAGE",raceName="人类",
    sex=secret,displayID=-1,untrusted="ignored"}
NS.GetMessageProfile = function(author, guid)
    profileCalls[#profileCalls+1] = {author=author,guid=guid}
    return providedProfile
end
local profileDB = NS.InitDB({})
NS.NotifyChanged = function()
    notices = notices + 1
    if NS.lastIncoming then eq(NS.lastIncoming.message.profile.level,38,"profile present when UI is notified") end
end
for index, route in ipairs({ {"GUILD","guild"},{"PARTY","group"},{"RAID","raid"},{"CHANNEL","channel-zone:"..channels[1][4]} }) do
    eq(incoming("CHAT_MSG_"..route[1],"公共消息", "发言人-全名",2300+index,"Player-speaker",channels[1][1]),true,"public sender profile "..route[1])
    local message=profileDB.conversations[route[2]].messages[1]
    eq(message.author,"发言人-全名","public author remains full name")
    eq(message.profile.level,38,"public message level captured")
    eq(message.profile.classToken,"MAGE","public message class captured")
    eq(message.profile.sex,nil,"restricted live profile field omitted")
    eq(message.profile.untrusted,nil,"unknown live profile fields omitted")
end
eq(#NS.GetConversations(),5,"four fixed chats plus channel only")
eq(#NS.GetRecentPeople(),0,"public speakers never become recent contacts")
eq(profileCalls[1].author,"发言人-全名","profile lookup uses complete sender identity")
eq(profileCalls[1].guid,"Player-speaker","incoming profile lookup uses event GUID")
providedProfile.level=39
eq(profileDB.conversations.guild.messages[1].profile.level,38,"message owns a profile snapshot")
NS.NotifyChanged = function() notices=notices+1 end
incoming("CHAT_MSG_WHISPER_INFORM","外发私聊","接收者-全名",2310,"Player-recipient")
eq(profileCalls[#profileCalls].author,"晨星-苏晚青","outgoing whisper profile identifies local author")
eq(profileCalls[#profileCalls].guid,"Player-self","outgoing whisper ignores recipient event GUID")
NS.GetBattleNetContactByID = function() return {target="好友#1234",title="通行证好友",profile={guid="Player-bn",level=60,classToken="PRIEST"}} end
local beforeBNProfiles=#profileCalls
eq(NS.HandleEvent("CHAT_MSG_BN_WHISPER","通行证来信","好友","","","","",0,0,"",0,2311,"Player-irrelevant",1),true,"incoming Battle.net metadata")
local bnetMessage=profileDB.conversations["bnet:好友#1234"].messages[1]
eq(bnetMessage.profile.guid,"Player-bn","Battle.net profile comes from resolved account")
eq(bnetMessage.profile.level,60,"Battle.net level retained")
eq(#profileCalls,beforeBNProfiles,"Battle.net title not treated as character full name")
eq(NS.HandleEvent("CHAT_MSG_BN_WHISPER_INFORM","通行证发信","好友","","","","",0,0,"",0,2312,"Player-recipient",1),true,"outgoing Battle.net metadata")
eq(profileCalls[#profileCalls].guid,"Player-self","outgoing Battle.net profile uses player GUID")
eq(profileCalls[#profileCalls].author,"晨星-苏晚青","outgoing Battle.net profile uses player full name")
local profileReload=NS.InitDB(profileDB)
eq(profileReload.conversations.guild.messages[1].profile.level,38,"per-message level survives reload")
eq(profileReload.conversations.guild.messages[1].profile.classToken,"MAGE","per-message class survives reload")
local safeProfiles=NS.InitDB({conversations={guild={messages={
    {text="无资料",author="队友"},
    {text="受限资料",author="队友",profile=secret},
    {text="混合资料",author="队友",profile={guid=secret,level=-1,classToken=secret,raceName="人类",className="|Hbad|h"}},
}}}})
eq(next(safeProfiles.conversations.guild.messages[1].profile),nil,"legacy sender has no invented metadata")
eq(next(safeProfiles.conversations.guild.messages[2].profile),nil,"secret saved profile rejected")
eq(safeProfiles.conversations.guild.messages[3].profile.level,nil,"unknown saved sender level omitted")
eq(safeProfiles.conversations.guild.messages[3].profile.className,nil,"markup in saved sender class rejected")
eq(safeProfiles.conversations.guild.messages[3].profile.raceName,"人类","safe saved sender field retained")

-- Battle.net needs the same offline guard, independently of the native API's
-- boolean acceptance result. Neither route should erase a retained draft.
local bnSends, bnPresenceCalls = 0, 0
NS.GetBattleNetContact = function()
    return {target="状态好友#1234",title="状态好友",accountID=77}
end
C_BattleNet = {SendWhisper=function(id, body)
    bnSends = bnSends + 1
    eq(id, 77, "Battle.net send keeps fresh native account identity")
    eq(body, "离线草稿", "Battle.net guard keeps message unchanged")
    return true
end}
local bn = NS.OpenBattleNet("状态好友#1234")
bn.draft = "离线草稿"
local bnPresence = "offline"
NS.GetContactPresence = function(conversation)
    eq(conversation, bn, "Battle.net send checks selected recipient")
    bnPresenceCalls = bnPresenceCalls + 1
    return bnPresence
end
ok, status = NS.Send(bn.draft)
eq(ok, false, "known offline Battle.net recipient blocked")
eq(bnSends, 0, "offline Battle.net recipient never reaches native send")
eq(status, "对方离线，消息未发送。草稿已保留。", "Battle.net offline message is explicit")
eq(bn.draft, "离线草稿", "Battle.net offline rejection retains draft")
bnPresence = "unknown"
eq(NS.Send(bn.draft), true, "unknown Battle.net state permits native acceptance check")
bnPresence = "online"
eq(NS.Send(bn.draft), true, "online Battle.net recipient permits sending")
eq(bnPresenceCalls, 3, "Battle.net presence checked on each attempt")
eq(bnSends, 2, "only unknown and online Battle.net attempts reach native send")

-- Built-in channel identity survives zones/slot reuse; custom names are exact.
do
    NS.NotifyChanged = function() notices = notices + 1 end
    NS.GetMessageProfile = nil
    channels = {{1,"综合 - 艾尔文森林",false,1},{2,"交易 - 城市",false,2},
        {3,"zone:1",false},{4,"综合 - 自定义小圈",false}}
    local legacyID = "channel:综合 - 艾尔文森林"
    local oldOtherID = "channel:综合 - 未认证旧地区"
    local migrated = NS.InitDB({selectedId=legacyID,channelsCollapsed=true,conversations={
        [legacyID]={kind="channel",target="综合 - 艾尔文森林",muted=true,draft="保留的综合草稿",
            messages={{id=8001,text="综合旧记录",author="旧发言人",time=1}}},
        [oldOtherID]={kind="channel",target="综合 - 未认证旧地区",draft="不能猜着合并",muted=true},
    }})
    NS.SetChannelRemindersEnabled(true) -- This case exercises per-channel mute while reminders are enabled.
    NS.SyncChannels()
    local general = migrated.conversations["channel-zone:1"]
    local trade = migrated.conversations["channel-zone:2"]
    eq(general.muted,true,"exact joined legacy channel carries mute into authenticated identity")
    eq(general.draft,"保留的综合草稿","migration retains draft")
    eq(general.messages[1].text,"综合旧记录","migration retains history")
    eq(migrated.selectedId,general.id,"migration remaps selected channel")
    eq(migrated.conversations[legacyID],nil,"authenticated exact legacy channel is not duplicated")
    eq(migrated.conversations[oldOtherID].draft,"不能猜着合并","unverified old region is never merged by prefix")
    eq(trade.muted,false,"general mute does not mute trade")
    eq(migrated.conversations["channel:zone:1"].target,"zone:1","custom zone-like name has a disjoint identity namespace")
    eq(migrated.conversations["channel:综合 - 自定义小圈"].target,"综合 - 自定义小圈","custom hyphens and built-in-looking prefix remain exact")
    migrated.shown=false
    incoming("CHAT_MSG_CHANNEL","综合来信","甲",8002,"Player-A",1,"综合",1)
    incoming("CHAT_MSG_CHANNEL","交易来信","乙",8003,"Player-B",2,"交易",2)
    eq(general.title,"综合","event's native base name labels the exact system channel")
    eq(trade.title,"交易","trade has its own visible name")
    eq(general.unread,1,"muted channel still retains unread in its own conversation")
    eq(NS.UnreadTotal(),1,"entry unread excludes only muted general")
    channels[1][1],channels[1][2]=7,"综合 - 暴风城"
    NS.SyncChannels()
    eq(migrated.conversations["channel-zone:1"],general,"zone and slot changes reuse the same conversation")
    eq(general.muted,true,"zone change keeps mute")
    eq(general.draft,"保留的综合草稿","zone change keeps unsent draft")
    eq(general.title,"综合","list sync preserves known base-name label")
    NS.Select(general.id)
    eq(NS.Send("当前综合频道"),true,"built-in send resolves current authenticated identity")
    eq(sends[#sends].target,7,"built-in send targets new slot")
    local tradeCount=#trade.messages
    incoming("CHAT_MSG_CHANNEL","迟到的综合消息","甲",8004,"Player-A",2,"综合",1)
    eq(#trade.messages,tradeCount,"late event cannot enter trade after its numbered slot was reused")
    eq(general.messages[#general.messages].text,"迟到的综合消息","event's zone ID wins over current numbered slot")
    local infoAPI=C_ChatInfo.GetChannelInfoFromIdentifier
    C_ChatInfo.GetChannelInfoFromIdentifier=function() return nil end
    incoming("CHAT_MSG_CHANNEL","查询暂不可用","甲",8005,"Player-A",7,"综合",1)
    eq(migrated.conversations["channel:综合"],nil,"event's zone ID avoids a duplicate base-name conversation during API outage")
    eq(general.messages[#general.messages].text,"查询暂不可用","zone event still reaches existing history during API outage")
    local beforeSend=#sends
    eq(NS.Send("身份无法核对"),false,"unverifiable standard channel fails closed")
    eq(#sends,beforeSend,"no send while current channel identity is unverifiable")
    C_ChatInfo.GetChannelInfoFromIdentifier=infoAPI
    migrated=NS.InitDB(migrated); NS.SyncChannels()
    general=migrated.conversations["channel-zone:1"]
    eq(general.muted,true,"authenticated mute persists across reload")
    eq(general.draft,"保留的综合草稿","authenticated draft persists across reload")
    NS.Select("channel:zone:1")
    eq(NS.Send("自建频道内容"),true,"custom zone-like name remains independently sendable")
    eq(sends[#sends].target,3,"custom name cannot target built-in general slot")

    local fullList,fullName=GetChannelList,GetChannelName
    GetChannelList=function() return 7,"综合",false,2,"交易",false,3,"zone:1",false,4,"综合 - 自定义小圈",false end
    GetChannelName=function(query)
        if query=="综合" then query=7 elseif query=="交易" then query=2 end
        return fullName(query)
    end
    eq(NS.SyncChannels(),false,"base-name channel list resolves to the existing full-name identities")
    NS.Select(general.id)
    eq(NS.Send("列表基础名也能发送"),true,"base-name list and full-name lookup agree on authenticated send")
    eq(sends[#sends].target,7,"base-name lookup still sends only to the current verified slot")
    GetChannelList,GetChannelName=fullList,fullName

    -- When a previously unknown full name later becomes the joined system
    -- channel, its distinct draft remains recoverable instead of overwritten.
    channels={{1,"综合 - 甲地区",false,1},{2,"交易 - 城市",false,2}}
    local a,b="channel:综合 - 甲地区","channel:综合 - 乙地区"
    local conflicts=NS.InitDB({selectedId=a,conversations={
        [a]={kind="channel",target="综合 - 甲地区",draft="甲地区草稿",muted=false,
            messages={{id=8101,text="甲地区历史",author="甲",time=1}}},
        [b]={kind="channel",target="综合 - 乙地区",draft="乙地区草稿",muted=true,
            messages={{id=8102,text="乙地区历史",author="乙",time=2}}},
    }})
    NS.SyncChannels(); channels[1][2]="综合 - 乙地区"; NS.SyncChannels()
    local merged=conflicts.conversations["channel-zone:1"]
    eq(merged.muted,true,"merging authenticated histories preserves either existing mute")
    eq(#merged.messages,2,"authenticated histories combine without losing either region")
    eq(merged.draft,"甲地区草稿","existing active draft is not overwritten")
    eq(conflicts.conversations[b].draft,"乙地区草稿","conflicting legacy draft is preserved separately")
    eq(conflicts.conversations[b].channelArchive,true,"conflicting draft is explicitly archived")
    NS.Select(b); beforeSend=#sends
    eq(NS.Send("误发旧草稿"),false,"archived draft cannot send into a different current region")
    eq(#sends,beforeSend,"archive never invokes native chat send")
    conflicts=NS.InitDB(conflicts)
    eq(conflicts.conversations[b].draft,"乙地区草稿","archived draft survives reload")
    eq(conflicts.conversations[b].channelArchive,true,"archive status survives reload")

    channels={{1,"交易 - 城市",false,2}}
    local tradeID="channel:交易 - 城市"
    local restricted=NS.InitDB({conversations={
        [tradeID]={kind="channel",target="交易 - 城市",draft="交易私有草稿",muted=true},
    }})
    for _,name in ipairs({false,secret}) do
        eq(NS.HandleEvent("CHAT_MSG_CHANNEL","缺名的迟到综合","甲",nil,name or nil,nil,nil,1,1,name or nil,nil,8201,"Player-A"),false,
            "missing or restricted event name cannot borrow conflicting slot identity")
        eq(restricted.conversations[tradeID].draft,"交易私有草稿","conflicting slot's legacy draft remains in its own channel")
        eq(restricted.conversations["channel-zone:1"],nil,"missing-name event cannot create general from trade's name")
    end
    channels={{7,"综合 - 暴风城",false,1},{1,"交易 - 城市",false,2}}
    NS.SyncChannels()
    local known=restricted.conversations["channel-zone:1"]
    eq(NS.HandleEvent("CHAT_MSG_CHANNEL","缺名但类型确定","甲",nil,secret,nil,nil,1,1,secret,nil,8202,"Player-A"),true,
        "known built-in identity can receive without borrowing another slot's name")
    eq(known.messages[#known.messages].text,"缺名但类型确定","known identity receives only its own zone event")
    eq(restricted.conversations["channel-zone:2"].draft,"交易私有草稿","trade draft remains separate after later certification")
end

-- Native community streams are mirrored into numbered channels, but belong
-- only to C_Club conversations. Names alone never authenticate this exclusion.
do
    local previousInfo = C_ChatInfo.GetChannelInfoFromIdentifier
    local nativeName, customName = "Community:900801835:1", "Community:12345:2"
    channels={{5,nativeName,false},{6,customName,false},{7,"普通自建频道",false}}
    local nativeTypes={[5]=2,[6]=3,[7]=3}
    C_ChatInfo.GetChannelInfoFromIdentifier=function(identifier)
        for _,channel in ipairs(channels) do
            if identifier==tostring(channel[1]) then
                return {localID=channel[1],name=channel[2],channelType=nativeTypes[channel[1]],zoneChannelID=0}
            end
        end
    end
    local current=NS.InitDB({})
    NS.SyncChannels()
    eq(current.conversations["channel:community:900801835:1"],nil,"native community stream never creates numbered-channel duplicate")
    eq(current.conversations["channel:community:12345:2"].available,true,"custom Community-looking name remains ordinary channel")
    eq(current.conversations["channel:普通自建频道"].available,true,"unrelated custom channel remains available")
    eq(NS.HandleEvent("CHAT_MSG_CHANNEL","mirrored body","成员",nil,"5. 测试群",nil,nil,0,5,nativeName,nil,9001,"Player-other"),false,
        "friendly-display community mirror is not handled a second time")
    eq(current.conversations["channel:community:900801835:1"],nil,"mirrored event cannot create a duplicate conversation")
    eq(incoming("CHAT_MSG_CHANNEL","custom body","成员",9002,"Player-other",6,customName,0),true,
        "custom Community-looking event is not suppressed")
    local custom=current.conversations["channel:community:12345:2"]
    eq(custom.messages[#custom.messages].text,"custom body","custom channel stores its actual message")

    local oldID="channel:community:900801835:1"
    current=NS.InitDB({selectedId=oldID,conversations={
        [oldID]={kind="channel",target=nativeName,draft="旧群草稿",muted=false,pinned=true,unread=1,
            messages={{id=9003,text="旧群记录",author="成员",time=1}}},
    }})
    NS.SyncChannels()
    local old=current.conversations[oldID]
    eq(old.channelCommunity,true,"authenticated old mirror gains durable community marker")
    eq(old.available,false,"old mirror is unavailable for ordinary channel sends")
    eq(old.draft,"旧群草稿","classification keeps unsent draft")
    eq(old.messages[1].text,"旧群记录","classification keeps old history")
    eq(old.pinned,true,"classification keeps pin preference")
    eq(old.muted,false,"classification does not rewrite mute preference")
    eq(old.unread,1,"classification keeps old unread record")
    eq(NS.UnreadTotal(),0,"old mirrored unread does not duplicate live group badge")
    local sendCount=#sends
    eq(NS.Send("不得从旧镜像发出"),false,"classified mirror blocks ordinary SendChatMessage")
    eq(#sends,sendCount,"mirror guard never invokes ordinary native send")
    eq(incoming("CHAT_MSG_CHANNEL","duplicate late body","成员",9004,"Player-other",5,nativeName,0),false,
        "classified mirror does not receive repeated native channel events")
    eq(#old.messages,1,"mirror filtering leaves old records unchanged")
    current=NS.InitDB(current);old=current.conversations[oldID]
    eq(old.channelCommunity,true,"community mirror marker survives reload")
    eq(old.draft,"旧群草稿","mirror draft survives reload")
    channels={{5,"占用旧编号的新频道",false}};nativeTypes[5]=3
    NS.SyncChannels()
    eq(old.available,false,"departed mirror stays unavailable after slot reuse")
    NS.Select(oldID)
    eq(NS.Send("离群后不得误发新频道"),false,"persisted mirror cannot send after leaving community")
    eq(#sends,sendCount,"slot reuse cannot redirect old mirror draft")
    eq(incoming("CHAT_MSG_CHANNEL","stale mirror event","成员",9005,"Player-other",5,nativeName,0),false,
        "late community event remains excluded after slot reuse")
    eq(incoming("CHAT_MSG_CHANNEL","new slot body","成员",9006,"Player-other",5,"占用旧编号的新频道",0),true,
        "custom channel reusing mirror slot still receives its own messages")

    -- A real custom channel can later reuse the exact old spelling. Native
    -- Custom authentication, not its name, permits returning to normal use.
    channels={{5,nativeName,false}};nativeTypes[5]=3
    NS.SyncChannels()
    eq(old.channelCommunity,false,"native Custom authentication clears historical exclusion")
    eq(old.available,true,"authenticated same-name custom channel becomes available")
    eq(old.draft,"旧群草稿","same-name custom transition still preserves draft")
    eq(incoming("CHAT_MSG_CHANNEL","now custom body","成员",9007,"Player-other",5,nativeName,0),true,
        "same-name native Custom event is accepted")

    -- A stale or restricted native info result must not certify another slot
    -- as a community and accidentally silence unrelated custom chat.
    current=NS.InitDB({});channels={{8,"Community:67890:3",false}}
    C_ChatInfo.GetChannelInfoFromIdentifier=function() return {localID=9,name=channels[1][2],channelType=2} end
    NS.SyncChannels()
    eq(current.conversations["channel:community:67890:3"].available,true,"mismatched localID cannot falsely certify community type")
    current=NS.InitDB({})
    C_ChatInfo.GetChannelInfoFromIdentifier=function() return secret end
    NS.SyncChannels()
    eq(current.conversations["channel:community:67890:3"].available,true,"restricted channel metadata cannot falsely classify custom name")
    C_ChatInfo.GetChannelInfoFromIdentifier=previousInfo
end

-- The public-channel master preference is independent of history and per-channel choices.
do
    channels={{1,"综合 - 艾尔文森林",false,1},{2,"交易 - 城市",false,2}}
    local current=NS.InitDB({shown=false,conversations={
        ["channel:综合 - 艾尔文森林"]={kind="channel",target="综合 - 艾尔文森林",unread=1,muted=false,
            draft="保留频道草稿",messages={{id=12001,text="旧综合记录",author="甲",time=1}}},
        ["channel:交易 - 城市"]={kind="channel",target="交易 - 城市",unread=1,muted=true,
            messages={{id=12000,text="旧交易记录",author="乙",time=1}}},
    }})
    NS.SyncChannels()
    local general,trade=current.conversations["channel-zone:1"],current.conversations["channel-zone:2"]
    eq(NS.ChannelRemindersEnabled(),false,"legacy save without master preference starts with channel reminders off")
    eq(general.unread,1,"legacy unread record is retained rather than erased")
    eq(NS.VisibleUnread(general),0,"legacy channel badge is suppressed while master is off")
    eq(NS.UnreadTotal(),0,"legacy public unread is excluded from launcher total")
    incoming("CHAT_MSG_CHANNEL","关闭时的综合记录","甲",12002,"Player-A",1,"综合",1)
    incoming("CHAT_MSG_CHANNEL","关闭时的交易记录","乙",12003,"Player-B",2,"交易",2)
    eq(#general.messages,2,"master-off channel messages still append to history")
    eq(trade.messages[2].text,"关闭时的交易记录","muted channel also keeps new history while master is off")
    eq(general.unread,1,"master-off channel message does not accumulate new unread")
    eq(trade.unread,1,"master-off muted channel does not accumulate new unread")
    eq(general.draft,"保留频道草稿","master-off receipt does not change unsent draft")
    incoming("CHAT_MSG_WHISPER","私聊照常提醒","提醒测试-家族",12004,"Player-Private")
    eq(NS.UnreadTotal(),1,"private unread remains active while public master is off")
    NS.SetChannelRemindersEnabled(true)
    eq(current.channelRemindersEnabled,true,"explicit opt-in writes saved preference")
    eq(general.muted,false,"master-on retains allowed channel choice")
    eq(trade.muted,true,"master-on retains blocked channel choice")
    incoming("CHAT_MSG_CHANNEL","开启后综合","甲",12005,"Player-A",1,"综合",1)
    incoming("CHAT_MSG_CHANNEL","开启后交易","乙",12006,"Player-B",2,"交易",2)
    eq(general.unread,2,"opted-in channel accumulates only subsequent unread")
    eq(trade.unread,2,"per-channel mute retains established local unread behavior when master is on")
    eq(NS.UnreadTotal(),3,"enabled launcher excludes individually muted channel")
    current=NS.InitDB(current); NS.SyncChannels()
    eq(NS.ChannelRemindersEnabled(),true,"explicit opt-in survives reload")
    eq(current.conversations[trade.id].muted,true,"per-channel mute survives master preference reload")
    NS.SetChannelRemindersEnabled(false)
    current=NS.InitDB(current)
    eq(NS.ChannelRemindersEnabled(),false,"explicit opt-out survives reload")
    eq(current.conversations[trade.id].muted,true,"master-off preserves individual channel preference")
    eq(NS.VisibleUnread(current.conversations[general.id]),0,"turning master off hides existing channel badge")
    eq(NS.UnreadTotal(),1,"turning master off leaves private badge unchanged")
    for _,value in ipairs({false,1,"true",secret}) do
        NS.InitDB({channelRemindersEnabled=value})
        eq(NS.ChannelRemindersEnabled(),false,"only a public boolean true can restore channel opt-in")
    end
end

print("chat_core_test: " .. checks .. " checks passed")
