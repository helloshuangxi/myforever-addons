local _, NS = ...

-- Only BattleTag message history is account-wide. Drafts, unread counts,
-- character whispers, public channels and presentation preferences stay local.
NS.ACCOUNT_HISTORY_LIMIT = 500
local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Table(value) return Public(value) and type(value) == "table" and value or nil end
local function Text(value, limit)
    return Public(value) and type(value) == "string" and #value <= limit and not value:find("[%z\1-\31\127]") and value or nil
end
local function Counter(value)
    if not Public(value) or type(value) ~= "number" or value ~= value or value < 0 or value > 9007199254740000 then return 0 end
    return math.floor(value)
end
local function Owner(value)
    value = Text(value, 240)
    if value and (value:match("^player:Player%-%d+%-%x+$") or value:match("^legacy:%x+$")) then return value end
end
local function Key(value)
    value = Text(value, 260)
    local target = value and value:match("^bnet:(.+)$")
    target = target and NS.BattleTag(target)
    return target and ("bnet:" .. target:gsub("[A-Z]", string.lower)) or nil
end
function NS.GetHistoryOwnerKey()
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    guid = ok and Text(guid, 160)
    return guid and Owner("player:" .. guid) or nil
end
local function Trim(history)
    table.sort(history.messages, function(a, b)
        if a.time ~= b.time then return a.time < b.time end
        local first = type(a.id) == "string" and tonumber(a.id:match("^bnmsg:(%d+)$"))
        local second = type(b.id) == "string" and tonumber(b.id:match("^bnmsg:(%d+)$"))
        if first and second then return first < second end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    while #history.messages > NS.ACCOUNT_HISTORY_LIMIT do table.remove(history.messages, 1) end
    history.updated = history.messages[#history.messages] and history.messages[#history.messages].time or 0
end
local function Record(conversation)
    return { id = conversation.id, kind = "bnet", target = conversation.target,
        title = conversation.title, messages = conversation.messages, updated = conversation.updated }
end
local function NextID(account)
    account.nextMessageID = account.nextMessageID + 1
    return "bnmsg:" .. account.nextMessageID
end
local function Import(account, owner, source)
    owner, source = Owner(owner), Table(source)
    if not owner or not source or account.importedOwners[owner] then return false end
    local conversations = Table(source.conversations) or {}
    for _, old in pairs(conversations) do
        old = Table(old)
        if old and Public(old.kind) and old.kind == "bnet" then
            local restored = NS.RestoreBattleNetHistory(old)
            if restored and not account.tombstones[restored.id] then
                local history = account.conversations[restored.id]
                if not history then
                    history = Record(restored); history.messages = {}
                    account.conversations[restored.id] = history
                end
                -- Import each owner's legacy snapshot once. Never deduplicate
                -- by text/time: two identical legitimate sends must both live.
                for _, message in ipairs(restored.messages) do
                    message.historyOriginalID, message.historyOwner = message.id, owner
                    message.id = NextID(account)
                    history.messages[#history.messages + 1] = message
                end
                Trim(history)
            end
        end
    end
    account.importedOwners[owner] = true
    return true
end

-- Pure-data entry point, usable by the private offline recovery tool. It does
-- not read files, invoke game APIs, bind UI, or change the current character DB.
function NS.NormalizeAccountHistory(value)
    local old = Table(value) or {}
    local account = { version = 1, conversations = {}, importedOwners = {}, tombstones = {}, nextMessageID = Counter(old.nextMessageID) }
    for key, marked in pairs(Table(old.tombstones) or {}) do
        key = Key(key)
        if key and Public(marked) and marked == true then account.tombstones[key] = true end
    end
    for key, marked in pairs(Table(old.importedOwners) or {}) do
        key = Owner(key)
        if key and Public(marked) and marked == true then account.importedOwners[key] = true end
    end
    for _, source in pairs(Table(old.conversations) or {}) do
        local restored = NS.RestoreBattleNetHistory(source)
        if restored then
            account.conversations[restored.id] = Record(restored)
            Trim(account.conversations[restored.id])
            for _, message in ipairs(restored.messages) do
                local sequence = type(message.id) == "string" and tonumber(message.id:match("^bnmsg:(%d+)$"))
                account.nextMessageID = math.max(account.nextMessageID, Counter(sequence))
            end
        end
    end
    -- A clear tombstone blocks stale legacy imports; a fresh conversation after
    -- a clear is still valid and remains readable above.
    for owner, source in pairs(Table(old.pendingImports) or {}) do Import(account, owner, source) end
    return account
end
function NS.ImportAccountHistory(account, owner, source)
    if not Table(account) or not Table(account.conversations) or not Table(account.importedOwners) or not Table(account.tombstones) then return false end
    return Import(account, owner, source)
end
function NS.AttachAccountHistory(value, owner)
    owner = Owner(owner)
    if not owner then return value, false end
    local account = NS.NormalizeAccountHistory(value)
    local db = NS.db
    if not Table(db) then return value, false end
    if not db.accountHistoryMigrated then Import(account, owner, db) end
    account.importedOwners[owner] = true
    NS.accountHistory, NS.historyOwner = account, owner
    for id, history in pairs(account.conversations) do
        local localConversation = db.conversations[id]
        if localConversation then
            localConversation.messages = history.messages
            localConversation.updated = math.max(localConversation.updated, history.updated)
            localConversation.unread = math.min(localConversation.unread, #history.messages)
        end
    end
    -- Remove stale legacy copies of a globally deleted conversation. For a
    -- cleared/reopened one, the account record above already owns its new list.
    for id, conversation in pairs(db.conversations) do
        if conversation.kind == "bnet" and account.tombstones[id] and not account.conversations[id] then
            if conversation.draft ~= "" then
                -- Deleting shared history must not discard another character's
                -- independent unsent draft. Its stale messages still vanish.
                conversation.messages, conversation.unread = {}, 0
            else
                db.conversations[id] = nil
                if db.selectedId == id then db.selectedId = "group" end
                if db.lastWhisperId == id then db.lastWhisperId = nil end
            end
        end
    end
    db.accountHistoryMigrated = true
    if NS.NotifyChanged then NS.NotifyChanged() end
    return account, true
end
function NS.GetSharedBattleNetHistory(target)
    local account = NS.accountHistory
    target = Text(target, 160)
    local key = target and Key("bnet:" .. target)
    local history = account and key and account.conversations[key]
    if not history then return nil end
    local conversation = NS.RestoreBattleNetHistory(history)
    conversation.messages = history.messages
    return conversation
end
function NS.HasSharedBattleNetHistory(target)
    target = Text(target, 160)
    local key = target and Key("bnet:" .. target)
    return NS.accountHistory and key and NS.accountHistory.conversations[key] ~= nil or false
end
function NS.RegisterSharedBattleNetHistory(conversation)
    if NS.accountHistory then NS.accountHistory.conversations[conversation.id] = Record(conversation) end
end
function NS.ClearSharedBattleNetHistory(conversation, deleted)
    local account = NS.accountHistory
    if not account then return end
    account.tombstones[conversation.id] = true
    account.conversations[conversation.id] = not deleted and Record(conversation) or nil
end
function NS.NewHistoryMessageID()
    return NS.accountHistory and NextID(NS.accountHistory) or nil
end
