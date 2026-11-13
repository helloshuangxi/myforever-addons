local _, NS = ...

local MAX_MESSAGES, MAX_DYNAMIC, MAX_PINNED, MAX_DELETED, MAX_RECENT = 60, 30, 10, 60, 60
local CAPACITY_NOTICE = "会话已满（30 个）；现有会话受置顶、草稿或当前选择保护。请先整理，再打开新会话。"
local seenLines = {}
local fixed = {
    { id = "guild", kind = "guild", title = "公会" },
    { id = "group", kind = "group", title = "小队" },
    { id = "raid", kind = "raid", title = "团队" },
    { id = "say", kind = "say", title = "附近" },
}
local routes = {
    CHAT_MSG_PARTY = "group", CHAT_MSG_PARTY_LEADER = "group",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_INSTANCE_CHAT = "group", CHAT_MSG_INSTANCE_CHAT_LEADER = "group",
    CHAT_MSG_GUILD = "guild", CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "say",
}

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function String(value, maxBytes)
    if not Public(value) or type(value) ~= "string" then return nil end
    if maxBytes and #value > maxBytes then return nil end
    return value
end

local chatTypes = {
    WHISPER = true, BN_WHISPER = true, PARTY = true, PARTY_LEADER = true,
    RAID = true, RAID_LEADER = true, INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true,
    GUILD = true, SAY = true, YELL = true, CHANNEL = true, COMMUNITIES_CHANNEL = true,
}
local function ChatType(value)
    local kind = String(value, 32)
    return kind and chatTypes[kind] and kind or nil
end

function NS.IsPriorityConversation(conversation)
    if not Public(conversation) or type(conversation) ~= "table" then return false end
    local kind = String(conversation.kind, 16)
    return kind == "guild" or kind == "group" or kind == "raid"
end

local function Number(value)
    if not Public(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function Trim(value)
    return (value:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

local function FoldCase(value)
    return (value:gsub("[A-Z]", function(character) return string.char(string.byte(character) + 32) end))
end

local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, a, b, c = pcall(func, ...)
    if ok then return a, b, c end
end

local function Yes(func, ...)
    local value = Call(func, ...)
    return Public(value) and value == true
end

local function Now()
    return Number(Call(GetServerTime)) or Number(Call(time)) or 0
end

local function Changed()
    if type(NS.NotifyChanged) == "function" then NS.NotifyChanged() end
end

local appearanceDefaults = {
    -- New installs start on the suite's "midnight" look. A saved theme,
    -- including an existing "jade", is the player's and is never migrated.
    fontSize = 14, opacity = 0.98, theme = "midnight",
    background = { 0.051, 0.067, 0.118 },
    accent = { 0.486, 0.576, 1.0 },
}
local appearanceThemes = { midnight = true, jade = true, ocean = true, violet = true, amber = true, custom = true }

function NS.NormalizeAppearance(value)
    local source = Public(value) and type(value) == "table" and value or {}
    local result = {
        fontSize = math.max(12, math.min(22, math.floor(Number(source.fontSize) or appearanceDefaults.fontSize))),
        opacity = math.max(0.25, math.min(1, Number(source.opacity) or appearanceDefaults.opacity)),
    }
    local theme = String(source.theme, 12)
    result.theme = theme and appearanceThemes[theme] and theme or appearanceDefaults.theme
    for _, field in ipairs({ "background", "accent" }) do
        local color = source[field]
        color = Public(color) and type(color) == "table" and color or {}
        result[field] = {}
        for component = 1, 3 do
            local channel = Number(color[component]) or appearanceDefaults[field][component]
            result[field][component] = math.max(0, math.min(1, channel))
        end
    end
    return result
end

local function CleanTarget(value)
    local target = String(value, 160)
    if not target then return nil end
    target = Trim(target)
    if target == "" or target:find("[%z\1-\31\127|/\\]") then return nil end
    -- Forever surnames may themselves contain spaces/hyphens. Do not split a
    -- name on '-' or guess a realm; preserve the complete target from the UI.
    return target
end

local function ChannelName(value)
    local name = String(value, 240)
    if not name then return nil end
    name = Trim(name)
    if name == "" or name:find("[%z\1-\31\127|]") then return nil end
    return name
end

function NS.BattleTag(value)
    local target = CleanTarget(value)
    if target and target:match("^[^#]+#%d+$") then return target end
end

local function DirectKind(kind)
    return kind == "whisper" or kind == "bnet"
end

local function DynamicKind(kind)
    return DirectKind(kind) or kind == "channel" or kind == "club"
end

local function CommunityTarget(value)
    local id = String(value, 100)
    if id and id:match("^club:[1-9]%d*:[1-9]%d*$") then return id end
end

local function Key(kind, target)
    return kind .. ":" .. FoldCase(target)
end

local function ChannelZoneID(value)
    value = Number(value)
    if value and value > 0 and value <= 2147483647 and value == math.floor(value) then return value end
end

-- Community streams also appear in the numbered native channel list. Their
-- CHAT_MSG_CHANNEL mirror must not become a second conversation beside C_Club.
-- Authenticate both name and slot through the game; a custom channel merely
-- named "Community:..." is still an ordinary custom channel.
local function NativeChannelType(name, channelIndex)
    name = ChannelName(name)
    if not name then return nil end
    local currentID, currentName = Call(GetChannelName, channelIndex or name)
    currentID, currentName = Number(currentID), ChannelName(currentName)
    if not currentID or currentID <= 0 or not currentName or FoldCase(currentName) ~= FoldCase(name)
        or (channelIndex and currentID ~= channelIndex) then return nil end
    local info = Call(C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier, tostring(currentID))
    if not Public(info) or type(info) ~= "table" or Number(info.localID) ~= currentID then return nil end
    local infoName = ChannelName(info.name)
    if not infoName or FoldCase(infoName) ~= FoldCase(name) then return nil end
    return Number(info.channelType)
end

local function CommunityChannelType()
    return Enum and Enum.PermanentChatChannelType and Enum.PermanentChatChannelType.Communities or 2
end
local function CustomChannelType()
    return Enum and Enum.PermanentChatChannelType and Enum.PermanentChatChannelType.Custom or 3
end

-- Numbered slots can change or be reused. Only the native permanent Zone type
-- establishes a built-in channel identity; never split custom names on '-'.
local function ChannelZone(name, channelIndex)
    if not channelIndex then
        local currentIndex, currentName = Call(GetChannelName, name)
        currentName = ChannelName(currentName)
        if not currentName or FoldCase(currentName) ~= FoldCase(name) then return nil end
        channelIndex = Number(currentIndex)
    end
    if not channelIndex or channelIndex <= 0 then return nil end
    local info = Call(C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier, tostring(channelIndex))
    if not Public(info) or type(info) ~= "table" then return nil end
    local zoneType = Enum and Enum.PermanentChatChannelType and Enum.PermanentChatChannelType.Zone or 1
    if Number(info.localID) ~= channelIndex or Number(info.channelType) ~= zoneType then return nil end
    return ChannelZoneID(info.zoneChannelID)
end

local function ChannelKey(name, zoneID)
    return zoneID and ("channel-zone:" .. zoneID) or Key("channel", name)
end

local classTokens = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
    DEATHKNIGHT = true, SHAMAN = true, MAGE = true, WARLOCK = true, MONK = true,
    DRUID = true, DEMONHUNTER = true, EVOKER = true,
}

local function ProfileText(value, limit)
    local text = String(value, limit)
    if not text or text == "" or text:find("[%z\1-\31\127|]") then return nil end
    return text
end

local function Integer(value, minimum, maximum)
    value = Number(value)
    if value and value >= minimum and value <= maximum and value == math.floor(value) then return value end
end

local function RestoreDeletedContacts(value)
    local source = Public(value) and type(value) == "table" and value or {}
    local valid = {}
    for rawID, rawStamp in pairs(source) do
        local id = String(rawID, 260)
        local stamp = Integer(rawStamp, 1, 9007199254740991)
        if id and stamp then
            local kind, rawTarget = id:match("^(%a+):(.*)$")
            local target = kind == "whisper" and CleanTarget(rawTarget) or kind == "bnet" and NS.BattleTag(rawTarget)
            if target then
                local canonicalID = Key(kind, target)
                valid[canonicalID] = math.max(valid[canonicalID] or 0, stamp)
            end
        end
    end
    local ordered = {}
    for id, stamp in pairs(valid) do ordered[#ordered + 1] = { id = id, stamp = stamp } end
    table.sort(ordered, function(a, b)
        if a.stamp ~= b.stamp then return a.stamp < b.stamp end
        return a.id < b.id
    end)
    local result, counter = {}, 0
    for index = math.max(1, #ordered - MAX_DELETED + 1), #ordered do
        counter = counter + 1
        result[ordered[index].id] = counter
    end
    return result, counter
end

local function RememberDeletedContact(db, id)
    db.deletedContactCounter = db.deletedContactCounter + 1
    db.deletedContacts[id] = db.deletedContactCounter
    -- Renumbering preserves deletion order and bounds both storage and counters.
    db.deletedContacts, db.deletedContactCounter = RestoreDeletedContacts(db.deletedContacts)
end

function NS.RestoreProfile(value)
    if not Public(value) or type(value) ~= "table" then return {} end
    local result = {}
    local guid = ProfileText(value.guid, 160)
    if guid and guid:match("^Player%-[A-Za-z0-9%-]+$") then result.guid = guid end
    local classToken = String(value.classToken, 24)
    if classToken and classTokens[classToken] then result.classToken = classToken end
    result.className = ProfileText(value.className, 64)
    result.raceName = ProfileText(value.raceName, 96)
    local raceToken = String(value.raceToken, 64)
    if raceToken and raceToken:match("^[A-Za-z][A-Za-z0-9_]*$") then result.raceToken = raceToken end
    result.level = Integer(value.level, 1, 1000)
    result.sex = Integer(value.sex, 1, 3)
    result.displayID = Integer(value.displayID, 1, 2147483647)
    result.seenAt = Integer(value.seenAt, 0, 9007199254740991)
    return result
end

local function MergeProfile(previous, incoming)
    local profile = NS.RestoreProfile(previous)
    incoming = NS.RestoreProfile(incoming)
    if profile.guid and incoming.guid and profile.guid ~= incoming.guid then return incoming end
    for field, value in pairs(incoming) do profile[field] = value end
    return profile
end

local function RecentPerson(kind, target, title, profile)
    return { id = Key(kind, target), kind = kind, target = target,
        title = ProfileText(title, 160) or target, profile = NS.RestoreProfile(profile) }
end

local function FindRecent(db, id)
    for index, person in ipairs(db.recentPeople) do
        if person.id == id then return person, index end
    end
end

local function RememberRecent(db, kind, target, title, profile)
    local old, index = FindRecent(db, Key(kind, target))
    local person = RecentPerson(kind, target, title, MergeProfile(old and old.profile, profile))
    if index then table.remove(db.recentPeople, index) end
    table.insert(db.recentPeople, 1, person)
    if #db.recentPeople > MAX_RECENT then table.remove(db.recentPeople) end
    return person
end

local function RestoreRecent(value)
    local people, seen = {}, {}
    if Public(value) and type(value) == "table" then
        for _, old in ipairs(value) do
            if Public(old) and type(old) == "table" then
                local kind = String(old.kind)
                local target = kind == "whisper" and CleanTarget(old.target) or kind == "bnet" and NS.BattleTag(old.target)
                if target then
                    local person = RecentPerson(kind, target, old.title, old.profile)
                    if not seen[person.id] then
                        people[#people + 1], seen[person.id] = person, true
                        if #people >= MAX_RECENT then break end
                    end
                end
            end
        end
    end
    return people
end

local function Activity(conversation)
    return math.max(conversation.updated or 0, conversation.profile and conversation.profile.seenAt or 0)
end

local function HasDraft(conversation)
    if not Public(conversation.draft) then return true end
    return type(conversation.draft) == "string" and conversation.draft ~= ""
end

local function RemoveConversation(db, id)
    db.conversations[id], seenLines[id] = nil, nil
    if db.lastWhisperId == id then db.lastWhisperId = nil end
    if db.selectedId == id then db.selectedId = "group" end
    if NS.lastIncoming and NS.lastIncoming.conversationId == id then NS.lastIncoming = nil end
end

local function Prune(db, keepID, protectedID)
    local dynamic = {}
    for _, conversation in pairs(db.conversations) do
        if DynamicKind(conversation.kind) then
            dynamic[#dynamic + 1] = conversation
        end
    end
    table.sort(dynamic, function(a, b)
        if a.updated ~= b.updated then return a.updated < b.updated end
        return a.id < b.id
    end)
    local excess = #dynamic - MAX_DYNAMIC
    for _, conversation in ipairs(dynamic) do
        if excess <= 0 then break end
        if not conversation.pinned and not HasDraft(conversation)
            and conversation.id ~= db.selectedId and conversation.id ~= keepID and conversation.id ~= protectedID then
            RemoveConversation(db, conversation.id)
            excess = excess - 1
        end
    end
    return excess <= 0
end

local function NewConversation(id, kind, title, target)
    return { id = id, kind = kind, title = title, target = target, messages = {}, unread = 0,
        updated = 0, draft = "", pinned = false, muted = false, profile = {} }
end

local function RestoreConversation(old, id, kind, title, target)
    local result = NewConversation(id, kind, title, target)
    if not Public(old) or type(old) ~= "table" then return result end
    result.updated = math.max(0, Number(old.updated) or 0)
    result.draft = String(old.draft, 4096) or ""
    result.pinned = DynamicKind(kind) and Public(old.pinned) and old.pinned == true or false
    result.muted = Public(old.muted) and old.muted == true or false
    if kind == "channel" then
        result.channelZoneID = ChannelZoneID(old.channelZoneID)
        result.channelBaseName = ChannelName(old.channelBaseName)
        result.channelArchive = Public(old.channelArchive) and old.channelArchive == true or false
        result.channelCommunity = Public(old.channelCommunity) and old.channelCommunity == true or false
        if result.channelArchive or result.channelCommunity then result.available = false end
    end
    if kind == "club" then
        result.clubId, result.streamId = target:match("^club:(%d+):(%d+)$")
        result.clubName = ProfileText(old.clubName, 240)
        result.streamName = ProfileText(old.streamName, 160)
        result.memberCount = Integer(old.memberCount, 0, 9007199254740991)
        result.available = false -- Membership must be revalidated each login.
        local watermark = Public(old.communityClearBefore) and type(old.communityClearBefore) == "table" and old.communityClearBefore
        local epoch = watermark and Integer(watermark.epoch, 0, 9007199254740991)
        local position = watermark and Integer(watermark.position, 0, 9007199254740991)
        if epoch and position then result.communityClearBefore = {epoch=epoch,position=position} end
        local submitted = Public(old.latestSubmission) and type(old.latestSubmission) == "table" and old.latestSubmission
        local submittedText = submitted and String(submitted.text, 4096)
        submittedText = submittedText and not submittedText:find("|K.-|k") and NS.ValidateText(submittedText)
        if submittedText then result.latestSubmission = {text=submittedText,time=math.max(0,Number(submitted.time) or 0)} end
    end
    if DirectKind(kind) then
        result.profile = NS.RestoreProfile(old.profile)
    end
    if Public(old.messages) and type(old.messages) == "table" then
        local list = old.messages
        local limit = kind == "bnet" and (NS.ACCOUNT_HISTORY_LIMIT or MAX_MESSAGES) or MAX_MESSAGES
        for index = math.max(1, #list - limit + 1), #list do
            local message = list[index]
            if Public(message) and type(message) == "table" then
                local text, author = String(message.text, 4096), String(message.author, 160)
                if text and author then
                    local staleNativeAuthor = kind == "club" and author:find("|K.-|k")
                    -- Native |K...|k strings are client-session handles, not
                    -- durable plaintext. Preserve community identity so a
                    -- fresh native cache lookup can replace this placeholder.
                    if kind == "club" and text:find("|K.-|k") then text = "[群消息待重新读取]" end
                    if staleNativeAuthor then author = "社区成员" end
                    result.messages[#result.messages + 1] = {
                        text = text, author = author,
                        outgoing = Public(message.outgoing) and message.outgoing == true or false,
                        time = math.max(0, Number(message.time) or 0),
                        id = String(message.id, 80) or Number(message.id),
                        chatType = ChatType(message.chatType),
                        profile = NS.RestoreProfile(message.profile),
                        historyOwner = String(message.historyOwner, 240),
                        historyOriginalID = String(message.historyOriginalID, 80) or Number(message.historyOriginalID),
                        clubEpoch = Integer(message.clubEpoch, 0, 9007199254740991),
                        clubPosition = Integer(message.clubPosition, 0, 9007199254740991),
                        communityAuthorKnown = not staleNativeAuthor and Public(message.communityAuthorKnown) and message.communityAuthorKnown == true or false,
                        communityEdited = Public(message.communityEdited) and message.communityEdited == true or false,
                        communityDeleted = Public(message.communityDeleted) and message.communityDeleted == true or false,
                    }
                end
            end
        end
    end
    result.unread = math.min(#result.messages, math.max(0, math.floor(Number(old.unread) or 0)))
    return result
end

function NS.RestoreBattleNetHistory(old)
    if not Public(old) or type(old) ~= "table" then return nil end
    if not Public(old.kind) or old.kind ~= "bnet" then return nil end
    local target = NS.BattleTag(old.target)
    if not target then return nil end
    return RestoreConversation(old, Key("bnet", target), "bnet", ProfileText(old.title, 160) or target, target)
end

local function MergeChannel(db, current, old, oldID)
    current.muted = current.muted or old.muted
    current.pinned = current.pinned or old.pinned
    current.updated = math.max(current.updated, old.updated)
    local conflict = HasDraft(current) and HasDraft(old) and current.draft ~= old.draft
    if not HasDraft(current) then current.draft = old.draft end
    local messages, seen = {}, {}
    for _, list in ipairs({ current.messages, old.messages }) do
        for _, message in ipairs(list) do
            if not message.id or not seen[message.id] then
                messages[#messages + 1] = message
                if message.id then seen[message.id] = true end
            end
        end
    end
    table.sort(messages, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    while #messages > MAX_MESSAGES do table.remove(messages, 1) end
    current.messages = messages
    current.unread = math.min(#messages, current.unread + old.unread)
    if conflict then
        -- A second unsent draft is never overwritten or silently sent to the
        -- new zone. Keep the old conversation as an explicitly marked archive.
        old.channelArchive, old.available, old.muted = true, false, current.muted
        old.channelZoneID, old.channelBaseName = nil, nil
        old.title = old.target .. "（旧草稿）"
        db.conversations[oldID] = old
    else
        db.conversations[oldID] = nil
        if db.selectedId == oldID then db.selectedId = current.id end
        if NS.lastIncoming and NS.lastIncoming.conversationId == oldID then NS.lastIncoming.conversationId = current.id end
        seenLines[oldID] = nil
        if type(NS.ChannelConversationMigrated) == "function" then NS.ChannelConversationMigrated(oldID, current.id) end
    end
end

function NS.InitDB(value)
    -- Blizzard chat line IDs can restart after a login/reload. Never deduplicate
    -- new events against persisted line IDs from a previous UI session.
    seenLines = {}
    NS.lastNotice = nil
    NS.lastIncoming = nil
    NS.accountHistory, NS.historyOwner = nil, nil
    local old = Public(value) and type(value) == "table" and value or {}
    local db = { conversations = {}, nextMessageID = math.max(0, math.floor(Number(old.nextMessageID) or 0)) }
    db.shown = not (Public(old.shown) and old.shown == false)
    db.channelsCollapsed = not (Public(old.channelsCollapsed) and old.channelsCollapsed == false)
    db.channelRemindersEnabled = Public(old.channelRemindersEnabled) and old.channelRemindersEnabled == true or false
    db.peopleCollapsed = Public(old.peopleCollapsed) and old.peopleCollapsed == true or false
    db.appearance = NS.NormalizeAppearance(old.appearance)
    db.accountHistoryMigrated = Public(old.accountHistoryMigrated) and old.accountHistoryMigrated == true or false
    db.deletedContacts, db.deletedContactCounter = RestoreDeletedContacts(old.deletedContacts)
    db.recentPeople = RestoreRecent(old.recentPeople)
    db.selectedId = String(old.selectedId, 260) or "group"
    db.lastWhisperId = String(old.lastWhisperId, 260)
    local validPoints = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
        TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
    local point, relativePoint = String(old.point), String(old.relativePoint)
    db.point = point and validPoints[point] and point or "CENTER"
    db.relativePoint = relativePoint and validPoints[relativePoint] and relativePoint or "CENTER"
    db.x, db.y = Number(old.x) or 0, Number(old.y) or 0
    local function Position(value, fallbackPoint, fallbackX, fallbackY)
        local saved = Public(value) and type(value) == "table" and value or {}
        local anchor, relative = String(saved.point), String(saved.relativePoint)
        return {
            point = anchor and validPoints[anchor] and anchor or fallbackPoint,
            relativePoint = relative and validPoints[relative] and relative or fallbackPoint,
            x = math.max(-10000, math.min(10000, Number(saved.x) or fallbackX)),
            y = math.max(-10000, math.min(10000, Number(saved.y) or fallbackY)),
        }, saved
    end
    local savedWindow
    db.window, savedWindow = Position(old.window, "CENTER", 0, 0)
    db.window.width = math.max(680, math.min(1080, Number(savedWindow.width) or 840))
    db.window.height = math.max(460, math.min(900, Number(savedWindow.height) or 560))
    db.launcher = Position(old.launcher, "TOPRIGHT", -30, -235)
    local previous = Public(old.conversations) and type(old.conversations) == "table" and old.conversations or {}
    for _, definition in ipairs(fixed) do
        db.conversations[definition.id] = RestoreConversation(previous[definition.id], definition.id, definition.kind, definition.title)
    end
    -- The old group conversation covered both party and raid. Carry its mute
    -- preference over only when introducing the separate raid conversation.
    if Public(previous.raid) and previous.raid == nil then
        db.conversations.raid.muted = db.conversations.group.muted
    end
    local discovered = {}
    for _, conversation in pairs(previous) do
        if Public(conversation) and type(conversation) == "table" then
            local kind = String(conversation.kind)
            local target = kind == "whisper" and CleanTarget(conversation.target)
                or kind == "bnet" and NS.BattleTag(conversation.target)
                or kind == "channel" and ChannelName(conversation.target)
                or kind == "club" and CommunityTarget(conversation.target)
            if target then
                local zoneID = kind == "channel" and ChannelZoneID(conversation.channelZoneID)
                local archived = kind == "channel" and Public(conversation.channelArchive) and conversation.channelArchive == true
                local id = kind == "club" and target or kind == "channel" and not archived and ChannelKey(target, zoneID) or Key(kind, target)
                local title = kind == "bnet" and ProfileText(conversation.title, 160) or target
                if kind == "club" then title = ProfileText(conversation.title, 512) or target end
                if kind == "channel" then title = archived and (target .. "（旧草稿）") or ChannelName(conversation.channelBaseName) or target end
                local restored = RestoreConversation(conversation, id, kind, title, target)
                local passiveOnly = kind == "whisper" and Public(conversation.autoDiscovered) and conversation.autoDiscovered == true
                    and #restored.messages == 0 and not HasDraft(restored) and not restored.pinned and not restored.muted
                    and id ~= db.selectedId and id ~= db.lastWhisperId
                if passiveOnly then
                    discovered[#discovered + 1] = restored
                else
                    db.conversations[id] = restored
                end
            end
        end
    end
    table.sort(discovered, function(a, b)
        if Activity(a) ~= Activity(b) then return Activity(a) < Activity(b) end
        return a.id < b.id
    end)
    for _, person in ipairs(discovered) do
        if not db.deletedContacts[person.id] then
            RememberRecent(db, person.kind, person.target, person.title, person.profile)
        end
    end
    -- Prefer an existing saved conversation if an externally edited save has
    -- both history and a deletion marker for the same person.
    for id in pairs(db.conversations) do db.deletedContacts[id] = nil end
    local pinned = {}
    for _, conversation in pairs(db.conversations) do
        if conversation.pinned then pinned[#pinned + 1] = conversation end
    end
    table.sort(pinned, function(a, b)
        if a.updated ~= b.updated then return a.updated > b.updated end
        return a.id < b.id
    end)
    for index = MAX_PINNED + 1, #pinned do pinned[index].pinned = false end
    if not Prune(db) then
        -- This can only occur in an externally enlarged/older save, because
        -- admission below never grows the live list beyond MAX_DYNAMIC.
        NS.lastNotice = "存档中的受保护会话超过 30 个，已保留草稿和置顶。请先整理会话后再新增。"
    end
    if not db.conversations[db.selectedId] then db.selectedId = "group" end
    if not db.conversations[db.lastWhisperId] then db.lastWhisperId = nil end
    NS.db = db
    Changed()
    return db
end

local function EnsureDB()
    if not NS.db then NS.InitDB({}) end
    return NS.db
end

function NS.UpdateAppearance(patch)
    local db = EnsureDB()
    local merged = NS.NormalizeAppearance(db.appearance)
    local source = Public(patch) and type(patch) == "table" and patch or {}
    for _, field in ipairs({ "fontSize", "opacity", "theme" }) do
        local value = source[field]
        if not Public(value) or value ~= nil then merged[field] = value end
    end
    for _, field in ipairs({ "background", "accent" }) do
        local color = source[field]
        if not Public(color) then
            merged[field] = color
        elseif color ~= nil then
            if type(color) == "table" then
                for component = 1, 3 do
                    local channel = color[component]
                    if not Public(channel) or channel ~= nil then merged[field][component] = channel end
                end
            else
                merged[field] = color
            end
        end
    end
    db.appearance = NS.NormalizeAppearance(merged)
    Changed()
    return db.appearance
end

function NS.ResetAppearance()
    local db = EnsureDB()
    db.appearance = NS.NormalizeAppearance(nil)
    Changed()
    return db.appearance
end

local function EnsureDynamic(kind, target, protectedID, identity)
    local db = EnsureDB()
    local id = identity or Key(kind, target)
    local conversation = db.conversations[id]
    if conversation then return conversation, false end
    conversation = kind == "bnet" and NS.GetSharedBattleNetHistory and NS.GetSharedBattleNetHistory(target)
        or NewConversation(id, kind, target, target)
    db.conversations[id] = conversation
    if not Prune(db, id, protectedID) then
        RemoveConversation(db, id)
        local note = CAPACITY_NOTICE
        if NS.lastNotice ~= note then NS.lastNotice = note; Changed() end
        return nil, false, note
    end
    if NS.lastNotice == CAPACITY_NOTICE then NS.lastNotice = nil end
    if kind == "bnet" and NS.RegisterSharedBattleNetHistory then NS.RegisterSharedBattleNetHistory(conversation) end
    return conversation, true
end

function NS.UpsertContact(name, profile, passive)
    local target = CleanTarget(name)
    if not target then return nil, "无法读取有效的完整角色名称。" end
    if not Public(passive) then return nil, "无法确认联系人发现方式，本次未修改联系人。" end
    local db, id = EnsureDB(), Key("whisper", target)
    if db.deletedContacts[id] then
        return nil, "此对话已删除；自动资料更新不会恢复它，请主动新建私聊。"
    end
    local conversation = db.conversations[id]
    if not conversation and passive ~= true then
        local _, note
        conversation, _, note = EnsureDynamic("whisper", target, db.lastWhisperId)
        if not conversation then return nil, note end
    end
    local incoming = NS.RestoreProfile(profile)
    if incoming.seenAt == nil then incoming.seenAt = math.max(0, math.floor(Now())) end
    local person = RememberRecent(db, "whisper", target, target, incoming)
    if conversation then conversation.profile = MergeProfile(conversation.profile, person.profile) end
    Changed()
    return conversation or person
end

function NS.GetRecentPeople()
    return EnsureDB().recentPeople
end

function NS.GetConversations()
    local db, result, dynamic = EnsureDB(), {}, {}
    for _, definition in ipairs(fixed) do result[#result + 1] = db.conversations[definition.id] end
    for _, conversation in pairs(db.conversations) do
        if DynamicKind(conversation.kind) then dynamic[#dynamic + 1] = conversation end
    end
    table.sort(dynamic, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if a.updated ~= b.updated then return a.updated > b.updated end
        return a.id < b.id
    end)
    for _, conversation in ipairs(dynamic) do result[#result + 1] = conversation end
    return result
end

function NS.GetSelected()
    local db = EnsureDB()
    return db.conversations[db.selectedId]
end

function NS.Select(id)
    id = String(id, 260)
    local db = EnsureDB()
    local conversation = id and db.conversations[id]
    if not conversation then return nil, "未找到会话。" end
    local changed = db.selectedId ~= id or conversation.unread ~= 0
    db.selectedId, conversation.unread = id, 0
    if changed then Changed() end
    return conversation
end

function NS.MarkRead(id)
    id = String(id, 260)
    local conversation = id and EnsureDB().conversations[id]
    if conversation and conversation.unread ~= 0 then conversation.unread = 0; Changed(); return true end
    return false
end

function NS.MarkAllRead()
    local changed = false
    for _, conversation in pairs(EnsureDB().conversations) do
        if conversation.unread ~= 0 then conversation.unread = 0; changed = true end
    end
    if changed then Changed() end
    return changed
end

function NS.TogglePin(id)
    id = String(id, 260)
    local db = EnsureDB()
    local conversation = id and db.conversations[id]
    if not conversation then return false, "未找到会话。" end
    if not DynamicKind(conversation.kind) then
        return false, "公会、小队和团队始终置顶；附近是固定会话。"
    end
    if not conversation.pinned then
        local count = 0
        for _, other in pairs(db.conversations) do if other.pinned then count = count + 1 end end
        if count >= MAX_PINNED then return false, "最多置顶 10 个会话，请先取消一个置顶。" end
    end
    conversation.pinned = not conversation.pinned
    Changed()
    return true, conversation.pinned and "会话已置顶。" or "已取消置顶。"
end

function NS.ToggleMute(id)
    id = String(id, 260)
    local conversation = id and EnsureDB().conversations[id]
    if not conversation then return false, "未找到会话。" end
    conversation.muted = not conversation.muted
    Changed()
    if conversation.kind == "channel" then
        if not NS.ChannelRemindersEnabled() then
            local setting = conversation.muted and "已设为屏蔽" or "已设为允许"
            return true, "「" .. conversation.title .. "」" .. setting .. "；开启频道提醒总开关后生效。"
        end
        return true, "「" .. conversation.title .. "」" .. (conversation.muted and "已屏蔽弹窗；消息和会话内未读仍保留。" or "已恢复弹窗；其他频道设置不变。")
    end
    return true, conversation.muted and "已免打扰；消息和会话内未读仍保留。" or "已恢复此会话的未读提醒。"
end

function NS.CloseConversation(id, force)
    id = String(id, 260)
    local db = EnsureDB()
    local conversation = id and db.conversations[id]
    if not conversation then return false, "未找到会话。" end
    if not DirectKind(conversation.kind) then return false, "这里只能关闭私聊；固定会话和频道会话会保留。" end
    if HasDraft(conversation) and not (Public(force) and force == true) then
        return false, "此会话还有草稿；请确认舍弃草稿后再关闭。"
    end
    RemoveConversation(db, id)
    if NS.lastNotice == CAPACITY_NOTICE then NS.lastNotice = nil end
    Changed()
    return true, "会话已关闭；收到新的私聊时会重新出现。"
end

function NS.DeleteConversation(id, confirmed)
    id = String(id, 260)
    local db = EnsureDB()
    local conversation = id and db.conversations[id]
    if not conversation then return false, "未找到对话。" end
    if not DirectKind(conversation.kind) then return false, "只能删除私聊；固定会话和频道会话会保留。" end
    if not (Public(confirmed) and confirmed == true) then
        return false, "删除会清除这条对话的本机记录和草稿，请先明确确认。"
    end
    RememberDeletedContact(db, id)
    if conversation.kind == "bnet" and NS.ClearSharedBattleNetHistory then NS.ClearSharedBattleNetHistory(conversation, true) end
    local _, recentIndex = FindRecent(db, id)
    if recentIndex then table.remove(db.recentPeople, recentIndex) end
    RemoveConversation(db, id)
    if NS.lastNotice == CAPACITY_NOTICE then NS.lastNotice = nil end
    Changed()
    return true, "已删除本机对话；再次主动私聊或收到私聊时会重新建立，旧记录不会恢复。"
end

local function OpenDirect(kind, target, title, profile)
    local conversation, _, note = EnsureDynamic(kind, target)
    if not conversation then return nil, note end
    local db = EnsureDB()
    local recent = FindRecent(db, conversation.id)
    conversation.title = ProfileText(title, 160) or conversation.title
    conversation.profile = MergeProfile(recent and recent.profile, MergeProfile(conversation.profile, profile))
    db.deletedContacts[conversation.id] = nil
    db.selectedId, conversation.unread = conversation.id, 0
    conversation.updated = Now()
    RememberRecent(db, kind, target, conversation.title, conversation.profile)
    Changed()
    return conversation
end

function NS.OpenWhisper(fullCharacterName, profile)
    local target = CleanTarget(fullCharacterName)
    if not target then return nil, "请填写完整角色名称；不要填写链接、控制字符或命令。" end
    return OpenDirect("whisper", target, target, profile)
end

function NS.OpenBattleNet(battleTag)
    local target = NS.BattleTag(battleTag)
    if not target then return nil, "通行证好友的完整标识暂不可读取。" end
    local friend = NS.GetBattleNetContact and NS.GetBattleNetContact(target)
    if not friend and not EnsureDB().conversations[Key("bnet", target)]
        and not (NS.HasSharedBattleNetHistory and NS.HasSharedBattleNetHistory(target)) then
        return nil, "暂时无法核对这位通行证好友。"
    end
    return OpenDirect("bnet", target, friend and friend.title, friend and friend.profile)
end

function NS.ClearSelected()
    local conversation = NS.GetSelected()
    if not conversation then return false end
    if conversation.kind == "club" then
        for _, message in ipairs(conversation.messages) do
            local epoch, position = message.clubEpoch, message.clubPosition
            local previous = conversation.communityClearBefore
            if epoch and position and (not previous or epoch > previous.epoch or epoch == previous.epoch and position > previous.position) then
                conversation.communityClearBefore = {epoch=epoch,position=position}
            end
        end
    end
    conversation.messages, conversation.unread = {}, 0
    if conversation.kind == "bnet" and NS.ClearSharedBattleNetHistory then NS.ClearSharedBattleNetHistory(conversation, false) end
    Changed()
    return true
end

function NS.ChannelRemindersEnabled()
    return EnsureDB().channelRemindersEnabled
end

function NS.SetChannelRemindersEnabled(enabled)
    local db = EnsureDB()
    enabled = Public(enabled) and enabled == true or false
    if db.channelRemindersEnabled == enabled then return end
    db.channelRemindersEnabled = enabled
    Changed()
end

function NS.CanNotifyConversation(conversation)
    return conversation and not conversation.muted and not conversation.channelCommunity
        and (conversation.kind ~= "channel" or NS.ChannelRemindersEnabled())
end

function NS.VisibleUnread(conversation)
    if not conversation or (conversation.kind == "channel" and not NS.ChannelRemindersEnabled()) then return 0 end
    return conversation.unread or 0
end

function NS.UnreadTotal()
    local total = 0
    for _, conversation in pairs(EnsureDB().conversations) do
        if NS.CanNotifyConversation(conversation) then total = total + conversation.unread end
    end
    return total
end

local function PlayerNames()
    -- Camelot's NameUtil understands first name + surname. Its own wrapper is
    -- authoritative; the second UnitNameUnmodified result is not guessed to be
    -- a realm here. A first-name-only comparison could merge different people.
    local fullName = NameUtil and String(Call(NameUtil.GetUnmodifiedUnitFullName, "player"), 160)
    if fullName and fullName ~= "" then return fullName, fullName end
    local first, surname = Call(UnitNameUnmodified, "player")
    first, surname = String(first, 120), String(surname, 120)
    if first and first ~= "" then
        if not surname or surname == "" then return first, first end
        local separator = Constants and Constants.CharacterNameSeparatorConsts
            and String(Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR, 8)
        if separator then
            fullName = first .. separator .. surname
            return fullName, fullName
        end
    end
    return nil, nil
end

local function IsOutgoing(author, guid)
    local playerGUID = String(Call(UnitGUID, "player"), 160)
    local senderGUID = String(guid, 160)
    if playerGUID and senderGUID and playerGUID ~= "" and senderGUID ~= "" then return playerGUID == senderGUID end
    local name, fullName = PlayerNames()
    return (fullName and FoldCase(author) == FoldCase(fullName)) or (name and FoldCase(author) == FoldCase(name)) or false
end

local function Pack(...) return { n = select("#", ...), ... } end

local function ReadChannels()
    if type(GetChannelList) == "function" then
        local list = Pack(pcall(GetChannelList))
        if list[1] then
            -- The list can expose a base name while GetChannelName returns
            -- the joined, zone-qualified name. Resolve by name and verify its
            -- slot rather than adopting whoever currently occupies a slot.
            for index = 2, list.n, 3 do
                local name, slot = ChannelName(list[index + 1]), Number(list[index])
                if name and slot and type(GetChannelName) == "function" then
                    local currentID, fullName = Call(GetChannelName, name)
                    fullName = ChannelName(fullName)
                    if Number(currentID) == slot and fullName then list[index + 1] = fullName
                    else list[index] = 0 end
                end
            end
            return list
        end
    end
    -- Native channel-list fallback when the legacy triple-list API is absent.
    -- Display rows also contain headers and non-text channels, so verify each
    -- active numbered row through GetChannelName before exposing it.
    local count = Number(Call(GetNumDisplayChannels))
    if not count or type(GetChannelDisplayInfo) ~= "function" then return nil end
    local list = { true, n = 1 }
    for index = 1, math.min(200, math.floor(count)) do
        local ok, _, header, _, channelID, _, active = pcall(GetChannelDisplayInfo, index)
        channelID = Number(channelID)
        if ok and Public(header) and header ~= true and Public(active) and active == true and channelID and channelID > 0 then
            local currentID, currentName = Call(GetChannelName, channelID)
            currentID, currentName = Number(currentID), ChannelName(currentName)
            if currentID and currentID == channelID and currentName then
                list[list.n + 1], list[list.n + 2], list[list.n + 3] = channelID, currentName, false
                list.n = list.n + 3
            end
        end
    end
    return list
end

local function EnsureChannel(name, channelIndex, eventZoneID, baseName)
    local db = EnsureDB()
    local zoneID = ChannelZoneID(eventZoneID) or ChannelZone(name, channelIndex)
    local id, legacyID = ChannelKey(name, zoneID), Key("channel", name)
    local conversation, changed = db.conversations[id], false
    local legacy = legacyID ~= id and db.conversations[legacyID]
    if legacy and not legacy.channelArchive then
        if conversation then
            MergeChannel(db, conversation, legacy, legacyID)
        else
            conversation = legacy
            db.conversations[legacyID], db.conversations[id] = nil, conversation
            conversation.id = id
            if db.selectedId == legacyID then db.selectedId = id end
            if NS.lastIncoming and NS.lastIncoming.conversationId == legacyID then NS.lastIncoming.conversationId = id end
            seenLines[id], seenLines[legacyID] = seenLines[legacyID], nil
            if type(NS.ChannelConversationMigrated) == "function" then NS.ChannelConversationMigrated(legacyID, id) end
        end
        changed = true
    end
    if not conversation then conversation, changed = EnsureDynamic("channel", name, nil, id) end
    if not conversation then return nil, changed end
    if conversation.channelCommunity and NativeChannelType(name, channelIndex) == CustomChannelType() then
        -- A newly authenticated custom channel can reuse an old name. Never
        -- revive a departed community mirror based on spelling alone.
        conversation.channelCommunity, changed = false, true
    end
    baseName = zoneID and ChannelName(baseName) or nil
    if zoneID and conversation.channelZoneID ~= zoneID then changed = true end
    conversation.channelZoneID = zoneID
    -- An event can identify the built-in channel while its current slot is
    -- unavailable. Keep the last verified full target until a list sync.
    if channelIndex or not conversation.target then
        if conversation.target ~= name then changed = true end
        conversation.target = name
    end
    if baseName then conversation.channelBaseName = baseName end
    local title = conversation.channelBaseName or name
    if conversation.title ~= title then conversation.title, changed = title, true end
    return conversation, changed
end

local function ArchiveCommunityChannel(db, name)
    local conversation = name and db.conversations[Key("channel", name)]
    if not conversation or conversation.kind ~= "channel" then return false end
    local changed = conversation.channelCommunity ~= true or conversation.available ~= false
    conversation.channelCommunity, conversation.available = true, false
    -- Keep records, draft and user preferences available for inspection/copy.
    return changed
end

local function IsCommunityMirror(db, name, channelIndex)
    if not name then return false end
    local nativeType = NativeChannelType(name, channelIndex)
    if nativeType == CommunityChannelType() then return true end
    local previous = db.conversations[Key("channel", name)]
    return previous and previous.channelCommunity == true and nativeType ~= CustomChannelType() or false
end

function NS.SyncChannels()
    local list = ReadChannels()
    if not list then return false end
    local db, changed, seen = EnsureDB(), false, {}
    for index = 2, list.n, 3 do
        local channelID, name, disabled = Number(list[index]), ChannelName(list[index + 1]), list[index + 2]
        if channelID and channelID > 0 and name then
            if IsCommunityMirror(db, name, channelID) then
                if ArchiveCommunityChannel(db, name) then changed = true end
            else
                local conversation, created = EnsureChannel(name, channelID)
                if conversation then
                    local available = not (Public(disabled) and disabled == true)
                    seen[conversation.id] = true
                    if created or conversation.available ~= available then changed = true end
                    conversation.available = available
                end
            end
        end
    end
    for _, conversation in pairs(db.conversations) do
        if conversation.kind == "channel" and not seen[conversation.id] and conversation.available ~= false then
            conversation.available, changed = false, true
        end
    end
    if changed then Changed() end
    return changed
end

function NS.HandleEvent(event, ...)
    if not String(event, 80) then return false end
    if event == "CHANNEL_UI_UPDATE" or event == "CHANNEL_COUNT_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
        return NS.SyncChannels()
    end
    local text, rawAuthor, _, channelDisplayName, _, _, zoneChannelID, channelIndex, channelBaseName, _, lineID, guid, bnetID = ...
    text, rawAuthor = String(text, 4096), String(rawAuthor, 160)
    -- Restricted chat values cannot be examined, compared, or persisted.
    if not text or not rawAuthor or text == "" or rawAuthor == "" then return false end
    local db, conversation, outgoing = EnsureDB(), nil, false
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        local target = CleanTarget(rawAuthor)
        if not target then return false end
        conversation = EnsureDynamic("whisper", target)
        outgoing = event == "CHAT_MSG_WHISPER_INFORM"
    elseif event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local accountID = Integer(bnetID, 1, 9007199254740991)
        local friend = accountID and NS.GetBattleNetContactByID and NS.GetBattleNetContactByID(accountID)
        if not friend then return false end
        conversation = EnsureDynamic("bnet", friend.target)
        if conversation then
            conversation.title = friend.title
            conversation.profile = MergeProfile(conversation.profile, friend.profile)
        end
        outgoing = event == "CHAT_MSG_BN_WHISPER_INFORM"
    elseif routes[event] then
        local route = routes[event]
        if (event == "CHAT_MSG_INSTANCE_CHAT" or event == "CHAT_MSG_INSTANCE_CHAT_LEADER")
            and Yes(IsInRaid, LE_PARTY_CATEGORY_INSTANCE or 2) then route = "raid" end
        conversation = db.conversations[route]
        outgoing = IsOutgoing(rawAuthor, guid)
    elseif event == "CHAT_MSG_CHANNEL" then
        local stableName, currentName, currentZone
        local eventZone = ChannelZoneID(zoneChannelID)
        local baseName = ChannelName(channelBaseName)
        channelIndex = Number(channelIndex)
        if channelIndex and channelIndex > 0 then
            local currentID, name = Call(GetChannelName, channelIndex)
            if Number(currentID) and currentID == channelIndex then
                currentName = ChannelName(name)
                if currentName then currentZone = ChannelZone(currentName, channelIndex) end
            end
        end
        -- The event's channel identity wins over a numbered slot that may now
        -- belong to another channel. Its display prefix is only a slot label.
        if eventZone and currentZone == eventZone then stableName = currentName end
        if not stableName then
            local displayName = ChannelName(channelDisplayName)
            stableName = displayName and ChannelName(displayName:match("^%d+%. (.+)$")) or baseName
        end
        -- Native community events can display a friendly short name while the
        -- base name remains the authenticated internal Community identifier.
        local communityName
        if IsCommunityMirror(db, baseName, channelIndex) then communityName = baseName
        elseif IsCommunityMirror(db, stableName, channelIndex) then communityName = stableName end
        if communityName then
            if ArchiveCommunityChannel(db, communityName) then Changed() end
            return false
        end
        if stableName then
            -- A zero/absent event zone ID is not permission to adopt a
            -- conflicting current slot. Exact custom names stay independent.
            local verifiedIndex = currentName and FoldCase(currentName) == FoldCase(stableName) and channelIndex or nil
            conversation = EnsureChannel(stableName, verifiedIndex, eventZone, baseName)
        else
            -- Missing/restricted event names must never borrow the name (or
            -- draft) of a different channel now occupying this numbered slot.
            conversation = eventZone and db.conversations[ChannelKey("", eventZone)]
            if not conversation then return false end
        end
        outgoing = IsOutgoing(rawAuthor, guid)
    else
        return false
    end
    if not conversation then return false, NS.lastNotice end
    lineID = Number(lineID)
    if lineID and lineID > 0 then
        local seen = seenLines[conversation.id]
        if not seen then seen = { order = {}, ids = {} }; seenLines[conversation.id] = seen end
        if seen.ids[lineID] then return false end
        seen.ids[lineID] = true
        seen.order[#seen.order + 1] = lineID
        if #seen.order > MAX_MESSAGES then
            seen.ids[table.remove(seen.order, 1)] = nil
        end
    end
    db.nextMessageID = db.nextMessageID + 1
    local messageID = "msg:" .. db.nextMessageID
    if conversation.kind == "bnet" and NS.NewHistoryMessageID then messageID = NS.NewHistoryMessageID() or messageID end
    local author = rawAuthor
    if conversation.kind == "bnet" then author = conversation.title end
    if outgoing and DirectKind(conversation.kind) then
        local playerName, fullName = PlayerNames()
        author = fullName or playerName or "我"
    end
    local stamp = Now()
    local eventType = event:gsub("^CHAT_MSG_", ""):gsub("_INFORM$", "")
    local profile
    if conversation.kind == "bnet" and not outgoing then
        profile = conversation.profile
    else
        -- A direct-message echo can carry the recipient's GUID. Its sender
        -- profile must describe the local player, including Battle.net echoes.
        local senderGUID = guid
        if outgoing then senderGUID = Call(UnitGUID, "player") end
        profile = Call(NS.GetMessageProfile, author, senderGUID)
    end
    local message = { text = text, author = author, outgoing = outgoing, time = stamp, id = messageID,
        chatType = ChatType(eventType), profile = NS.RestoreProfile(profile) }
    if conversation.kind == "bnet" then message.historyOwner = NS.historyOwner end
    conversation.messages[#conversation.messages + 1] = message
    if DirectKind(conversation.kind) then
        db.deletedContacts[conversation.id] = nil
        local recent = FindRecent(db, conversation.id)
        conversation.profile = MergeProfile(recent and recent.profile, conversation.profile)
        RememberRecent(db, conversation.kind, conversation.target, conversation.title, conversation.profile)
        if not outgoing then db.lastWhisperId = conversation.id end
    end
    local messageLimit = conversation.kind == "bnet" and (NS.ACCOUNT_HISTORY_LIMIT or MAX_MESSAGES) or MAX_MESSAGES
    if #conversation.messages > messageLimit then table.remove(conversation.messages, 1) end
    conversation.updated = stamp
    if conversation.kind == "bnet" and NS.RegisterSharedBattleNetHistory then NS.RegisterSharedBattleNetHistory(conversation) end
    if not outgoing and (conversation.kind ~= "channel" or db.channelRemindersEnabled)
        and (db.selectedId ~= conversation.id or not db.shown) then
        conversation.unread = math.min(messageLimit, conversation.unread + 1)
    end
    if not outgoing then NS.lastIncoming = { conversationId = conversation.id, message = message } end
    Changed()
    return true
end

function NS.UTF8Bytes(text)
    local value = String(text)
    return value and #value or nil
end

NS.CHAT_VISIBLE_BYTES, NS.CHAT_LINK_BYTES, NS.CHAT_DRAFT_BYTES = 255, 1023, 1280

function NS.ChatMessageBytes(text)
    text = String(text)
    if not text then return 0, 0 end
    local hidden = 0
    -- Mask escaped pipes without changing byte offsets or counting them as tags.
    local markup = text:gsub("||", "\1\1")
    for first, label, after in markup:gmatch("()|H[%a][%w_]*:[^|%z\1-\31\127]+|h([^|]+)|h()") do
        hidden = hidden + after - first - #label
        if markup:sub(after, after + 1) == "|r" then
            local prefix = markup:sub(1, first - 1)
            local color = prefix:match("(|c%x%x%x%x%x%x%x%x)$") or prefix:match("(|cn[%w_]+:)$")
            if color then hidden = hidden + #color + 2 end
        end
    end
    return #text - hidden, hidden
end

function NS.ValidateText(text)
    text = String(text)
    if not text then return nil, "消息不可读取，请重新输入。" end
    text = Trim(text)
    if text == "" then return nil, "请先输入消息。" end
    if text:sub(1, 1) == "/" then return nil, "此窗口只发送聊天文字；斜杠命令请在原生聊天框使用。" end
    if text:find("[%z\1-\31\127]") then return nil, "消息不能包含换行或控制字符。" end
    local visible, hidden = NS.ChatMessageBytes(text)
    if visible > NS.CHAT_VISIBLE_BYTES then return nil, "可见文字超过 255 字节，请手动分成几条。" end
    if hidden > NS.CHAT_LINK_BYTES then return nil, "这条消息的链接数据太长，请把链接分开发送。" end
    return text
end

function NS.Send(text)
    local body, errorText = NS.ValidateText(text)
    if not body then return false, errorText end
    local conversation = NS.GetSelected()
    if not conversation then return false, "请先选择会话。" end
    if conversation.kind == "whisper" or conversation.kind == "bnet" then
        -- Recheck at the actual hardware-triggered send, not only when the
        -- conversation opened. An unreadable/unknown status is not offline.
        local presence = String(Call(NS.GetContactPresence, conversation), 16)
        if presence == "offline" then
            return false, "对方离线，消息未发送。草稿已保留。"
        end
    end
    local chatType, target
    if conversation.kind == "group" then
        local instanceRaid = Call(IsInRaid, LE_PARTY_CATEGORY_INSTANCE or 2)
        -- Unknown/restricted raid state must not expand a party reply to an
        -- entire instance raid. Only a public false confirms an instance party.
        if Yes(IsInGroup, LE_PARTY_CATEGORY_INSTANCE or 2) and Public(instanceRaid) and instanceRaid == false then
            chatType = "INSTANCE_CHAT"
        elseif Yes(IsInGroup, LE_PARTY_CATEGORY_HOME or 1) then chatType = "PARTY"
        else return false, "当前没有可发送消息的小队。" end
    elseif conversation.kind == "raid" then
        if Yes(IsInRaid, LE_PARTY_CATEGORY_INSTANCE or 2) then chatType = "INSTANCE_CHAT"
        elseif Yes(IsInRaid, LE_PARTY_CATEGORY_HOME or 1) then chatType = "RAID"
        else return false, "当前没有可发送消息的团队。" end
    elseif conversation.kind == "guild" then
        if not Yes(IsInGuild) then return false, "当前角色尚未加入公会。" end
        chatType = "GUILD"
    elseif conversation.kind == "say" then
        chatType = "SAY"
    elseif conversation.kind == "whisper" then
        target = CleanTarget(conversation.target)
        if not target then return false, "私聊目标无效，请重新选择完整角色名。" end
        chatType = "WHISPER"
    elseif conversation.kind == "bnet" then
        local friend = NS.GetBattleNetContact and NS.GetBattleNetContact(conversation.target)
        if not friend or not (C_BattleNet and type(C_BattleNet.SendWhisper) == "function") then
            return false, "暂时无法核对通行证好友，请在游戏好友列表中确认。"
        end
        local ok, success = pcall(C_BattleNet.SendWhisper, friend.accountID, body)
        if not ok or not Public(success) or success ~= true then
            return false, "游戏未接受通行证私聊请求，请查看游戏好友状态。"
        end
        return true, "已提交，等待游戏回显；尚未确认送达。"
    elseif conversation.kind == "club" then
        if not NS.Communities or type(NS.Communities.Send) ~= "function" then return false, "角色社区接口暂不可用。" end
        local ok, note = NS.Communities.Send(conversation.id, body)
        if ok then
            conversation.latestSubmission = {text=body,time=Now()}
            Changed()
        end
        return ok, note
    elseif conversation.kind == "channel" then
        if conversation.channelCommunity or IsCommunityMirror(EnsureDB(), conversation.target) then
            if ArchiveCommunityChannel(EnsureDB(), conversation.target) then Changed() end
            return false, "这是保留的旧群频道记录，请在「群聊」中选择对应社区发送；草稿仍可复制。"
        end
        if conversation.channelArchive then return false, "这是迁移时保留的旧草稿，请复制到当前频道后发送。" end
        local channelID
        local channels = ReadChannels()
        if channels then
            for index = 2, channels.n, 3 do
                local currentID, joinedName = Number(channels[index]), ChannelName(channels[index + 1])
                if currentID and currentID > 0 and joinedName then
                    local zoneID = ChannelZone(joinedName, currentID)
                    if ChannelKey(joinedName, zoneID) == conversation.id then
                        local resolvedID, resolvedName = Call(GetChannelName, currentID)
                        resolvedName = ChannelName(resolvedName)
                        if Number(resolvedID) ~= currentID or not resolvedName or FoldCase(resolvedName) ~= FoldCase(joinedName) then
                            return false, "频道列表正在变化，请稍后重试。"
                        end
                        if not Public(channels[index + 2]) or channels[index + 2] == true then
                            return false, "当前频道暂不可用，请在原生频道列表中确认。"
                        end
                        channelID = currentID
                        break
                    end
                end
            end
        elseif not conversation.channelZoneID then
            local currentID, currentName = Call(GetChannelName, conversation.target)
            currentName = ChannelName(currentName)
            if Number(currentID) and currentID > 0 and currentName and FoldCase(currentName) == FoldCase(conversation.target) then channelID = currentID end
        end
        if not channelID then return false, "已离开此频道或暂时无法核对频道身份，请在频道提醒中查看当前频道。" end
        chatType, target = "CHANNEL", channelID
    else
        return false, "不支持此会话类型。"
    end
    if not (C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function") then
        return false, "当前客户端的聊天发送接口不可用，请使用原生聊天框。"
    end
    -- Must remain synchronous inside the user's Enter/click hardware handler.
    -- The API has no delivery result; only a real event appends the message.
    local ok = pcall(C_ChatInfo.SendChatMessage, body, chatType, nil, target)
    if not ok then return false, "游戏未接受发送请求，请使用原生聊天框查看限制或重试。" end
    return true, "已提交，等待游戏回显；尚未确认送达。"
end

function NS.UpsertCommunity(meta, passive)
    if not Public(meta) or type(meta) ~= "table" then return nil end
    local id = CommunityTarget(meta.id)
    local title = ProfileText(meta.title, 512)
    if not id or not title then return nil end
    if not Public(passive) then return nil end
    if passive == true and not EnsureDB().conversations[id] then return nil end
    local conversation, created = EnsureDynamic("club", id, nil, id)
    if not conversation then return nil end
    conversation.clubId, conversation.streamId = id:match("^club:(%d+):(%d+)$")
    conversation.title = title
    conversation.clubName, conversation.streamName = ProfileText(meta.clubName, 240), ProfileText(meta.streamName, 160)
    conversation.memberCount = Integer(meta.memberCount, 0, 9007199254740991)
    conversation.available = Public(meta.available) and meta.available == true or false
    if created then Changed() end
    return conversation
end

function NS.RestoreLastCommunitySubmission(id)
    id = CommunityTarget(id)
    local conversation = id and EnsureDB().conversations[id]
    if not conversation or conversation.kind ~= "club" then return false, "请先选择角色社区群聊。" end
    if not Public(conversation.draft) or conversation.draft ~= "" then return false, "当前已有草稿，未覆盖；请先处理当前输入。" end
    local previous = conversation.latestSubmission
    if not Public(previous) or type(previous) ~= "table" then return false, "此群尚无可找回的提交记录。" end
    local text = String(previous.text, 4096)
    text = text and not text:find("|K.-|k") and NS.ValidateText(text)
    if not text then return false, "上次提交内容不可恢复。" end
    conversation.draft = text
    Changed()
    return true, "已找回上次提交到草稿；没有自动重发。"
end

function NS.StoreCommunityMessage(id, value, mode)
    id = CommunityTarget(id)
    if not id or not Public(value) or type(value) ~= "table" then return false end
    if not Public(mode) or mode ~= "live" and mode ~= "history" and mode ~= "update" then return false end
    local conversation = EnsureDB().conversations[id]
    if not conversation or conversation.kind ~= "club" then return false end
    local epoch, position = Integer(value.clubEpoch, 0, 9007199254740991), Integer(value.clubPosition, 0, 9007199254740991)
    local text, author = String(value.text, 4096), String(value.author, 160)
    local outgoing = Public(value.outgoing) and type(value.outgoing) == "boolean" and value.outgoing
    if not epoch or not position or not text or not author or not Public(value.outgoing) or type(value.outgoing) ~= "boolean" then return false end
    local messageID = string.format("clubmsg:%.0f:%.0f", epoch, position)
    if String(value.id, 100) ~= messageID then return false end
    local watermark = conversation.communityClearBefore
    if watermark and (epoch < watermark.epoch or epoch == watermark.epoch and position <= watermark.position) then return false end
    local message
    for _, candidate in ipairs(conversation.messages) do if candidate.id == messageID then message = candidate; break end end
    local created = message == nil
    if not message then message = {}; conversation.messages[#conversation.messages+1] = message end
    local previousLive, previousSequence = message.communityLive, message.communitySequence
    message.id, message.text, message.author, message.outgoing = messageID, text, author, outgoing
    message.time = math.max(0, Number(value.time) or 0)
    message.chatType, message.profile = "COMMUNITIES_CHANNEL", NS.RestoreProfile(value.profile)
    message.clubEpoch, message.clubPosition = epoch, position
    message.communityAuthorKnown = Public(value.communityAuthorKnown) and value.communityAuthorKnown == true or false
    message.communityEdited = Public(value.communityEdited) and value.communityEdited == true or false
    message.communityDeleted = Public(value.communityDeleted) and value.communityDeleted == true or false
    message.communityNativeContent = Public(value.communityNativeContent) and value.communityNativeContent == true
        and text:match("^|Kw%d+|k$") ~= nil and not message.communityDeleted or false
    message.communityLive = mode == "live" and not message.communityEdited and not message.communityDeleted
        and (created or previousLive == true)
    message.communitySequence = message.communityLive and (created and Integer(value.communitySequence, 1, 9007199254740991) or previousSequence) or nil
    table.sort(conversation.messages, function(a,b)
        if (a.clubEpoch or 0) ~= (b.clubEpoch or 0) then return (a.clubEpoch or 0) < (b.clubEpoch or 0) end
        return (a.clubPosition or 0) < (b.clubPosition or 0)
    end)
    while #conversation.messages > MAX_MESSAGES do table.remove(conversation.messages, 1) end
    conversation.updated = math.max(conversation.updated, message.time)
    if created and mode == "live" and not outgoing then
        if EnsureDB().selectedId ~= id or not EnsureDB().shown then conversation.unread = math.min(MAX_MESSAGES, conversation.unread+1) end
        NS.lastIncoming = {conversationId=id,message=message}
    end
    Changed()
    return true
end

NS.MAX_MESSAGES, NS.MAX_DYNAMIC, NS.MAX_PINNED, NS.MAX_DELETED = MAX_MESSAGES, MAX_DYNAMIC, MAX_PINNED, MAX_DELETED
NS.MAX_RECENT = MAX_RECENT
