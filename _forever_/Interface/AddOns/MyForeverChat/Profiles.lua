local _, NS = ...
local pendingFriends = {}
local FRIEND_TIMEOUT = 8
local validClasses = {
    WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true, DEATHKNIGHT=true,
    SHAMAN=true, MAGE=true, WARLOCK=true, MONK=true, DRUID=true, DEMONHUNTER=true, EVOKER=true,
}

local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function String(value, limit)
    if not Public(value) or type(value) ~= "string" or (limit and #value > limit) then return nil end
    return value
end
local function Number(value)
    if not Public(value) or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function Table(value)
    if Public(value) and type(value) == "table" then return value end
end
local function TargetName(value)
    local name = String(value, 160)
    if not name then return nil end
    name = name:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")
    if name == "" or name:find("[%z\1-\31\127|/\\]") then return nil end
    return name
end
local function Fold(value)
    return (value:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end
local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, a, b, c = pcall(func, ...)
    if ok then return a, b, c end
end
local function Boolean(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok or not Public(value) or type(value) ~= "boolean" then return nil end
    return value
end
local function Clock()
    return Number(Call(GetTime)) or Number(Call(GetServerTime)) or 0
end
local function Notify()
    if type(NS.NotifyChanged) == "function" then NS.NotifyChanged() end
end
local function FullUnitName(unit)
    local name = Call(NameUtil and NameUtil.GetUnmodifiedUnitFullName, unit)
    return TargetName(name)
end
local function IsPlayerUnit(unit)
    return Boolean(UnitExists, unit) == true and Boolean(UnitIsPlayer, unit) == true
end
local function ContactGUID(conversation)
    local profile = conversation.profile
    if not Public(profile) or type(profile) ~= "table" then return nil end
    return String(profile.guid, 160)
end

function NS.CaptureTarget()
    if not IsPlayerUnit("target") then return nil, "当前目标不是可读取的玩家。" end
    local same = Boolean(UnitIsUnit, "target", "player")
    if same == nil then return nil, "当前目标身份暂不可读取。" end
    if same then return nil, "当前目标是自己。" end
    local name = FullUnitName("target")
    if not name then return nil, "目标全名暂不可读取。" end
    if type(NS.UpsertContact) ~= "function" then return nil, "联系人资料功能不可用。" end
    local className, classToken = Call(UnitClass, "target")
    local raceName, raceToken = Call(UnitRace, "target")
    classToken = String(classToken, 20)
    if not classToken or not validClasses[classToken] then classToken = nil end
    local profile = {
        guid = String(Call(UnitGUID, "target"), 160),
        classToken = classToken, className = String(className, 80),
        raceName = String(raceName, 80), raceToken = String(raceToken, 80),
        seenAt = Number(Call(GetServerTime)),
    }
    local level, sex = Number(Call(UnitLevel, "target")), Number(Call(UnitSex, "target"))
    if level and level > 0 and level <= 1000 and level == math.floor(level) then profile.level = level end
    if sex and sex >= 1 and sex <= 3 and sex == math.floor(sex) then profile.sex = sex end
    -- GetDisplayID() has no unit parameter and describes the local player.
    -- Do not persist it as someone else's portrait.
    return NS.UpsertContact(name, profile, true)
end

function NS.CaptureWhisperProfile(author, guid)
    local name = TargetName(author)
    guid = String(guid, 160)
    if not name or not guid or not guid:match("^Player%-[A-Za-z0-9%-]+$") then
        return nil, "私聊玩家身份暂不可读取。"
    end
    local db = Public(NS.db) and type(NS.db) == "table" and NS.db or nil
    local conversations = db and Public(db.conversations) and type(db.conversations) == "table" and db.conversations or nil
    local existing = conversations and conversations["whisper:" .. Fold(name)]
    if not Public(existing) or type(existing) ~= "table" then return nil, "此玩家尚无已接收的私聊会话。" end
    local existingName = TargetName(existing.target)
    if String(existing.kind) ~= "whisper" or not existingName
        or Fold(existingName) ~= Fold(name) then return nil, "此玩家尚无已接收的私聊会话。" end
    if type(GetPlayerInfoByGUID) ~= "function" or type(NS.UpsertContact) ~= "function" then
        return nil, "玩家资料接口暂不可用。"
    end
    -- The returned name and realm are intentionally ignored. Forever's author
    -- is already a complete identity and must never be rebuilt as name-realm.
    local ok, className, classToken, raceName, raceToken, sex, _, _, level = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return nil, "玩家资料暂不可读取。" end
    className, classToken = String(className, 80), String(classToken, 20)
    raceName, raceToken = String(raceName, 80), String(raceToken, 80)
    if not classToken or not validClasses[classToken] then classToken = nil end
    sex, level = Number(sex), Number(level)
    if not sex or sex < 1 or sex > 3 or sex ~= math.floor(sex) then sex = nil end
    if not level or level <= 0 or level > 1000 or level ~= math.floor(level) then level = nil end
    if not className and not classToken and not raceName and not raceToken and not sex and not level then
        return nil, "玩家资料暂不可读取。"
    end
    return NS.UpsertContact(name, {
        guid=guid, className=className, classToken=classToken,
        raceName=raceName, raceToken=raceToken, sex=sex, level=level,
    }, true)
end

function NS.ResolvePortraitUnit(conversation)
    if not Public(conversation) or type(conversation) ~= "table" or String(conversation.kind) ~= "whisper" or not IsPlayerUnit("target") then return nil end
    local target = TargetName(conversation.target)
    local name = FullUnitName("target")
    if not target or not name or Fold(target) ~= Fold(name) then return nil end
    local storedGUID = ContactGUID(conversation)
    if storedGUID then
        local currentGUID = String(Call(UnitGUID, "target"), 160)
        if not currentGUID or currentGUID ~= storedGUID then return nil end
    end
    return "target"
end

function NS.ClassIconCoords(classToken)
    classToken = String(classToken, 20)
    if not classToken or not validClasses[classToken] then return nil end
    local coords = Public(CLASS_ICON_TCOORDS) and type(CLASS_ICON_TCOORDS) == "table" and CLASS_ICON_TCOORDS[classToken]
    if not Public(coords) or type(coords) ~= "table" then return nil end
    local result = {}
    for i = 1, 4 do
        local value = Number(coords[i])
        if not value or value < 0 or value > 1 then return nil end
        result[i] = value
    end
    return result
end

local function WhisperTarget(conversation)
    if not Public(conversation) or type(conversation) ~= "table" or String(conversation.kind) ~= "whisper" then return nil end
    return TargetName(conversation.target)
end
local function SameFriend(info, target, conversation)
    if not Public(info) or type(info) ~= "table" then return false end
    local name = TargetName(info.name)
    if not name or Fold(name) ~= Fold(target) then return false end
    local known, actual = ContactGUID(conversation), String(info.guid, 160)
    if known and actual and known ~= actual then return false end
    return true
end
local function FindFriend(target, conversation)
    local api = C_FriendList
    if not api then return nil, false end
    local readable = false
    if type(api.GetFriendInfo) == "function" then
        local ok, info = pcall(api.GetFriendInfo, target)
        if ok and Public(info) then
            readable = true
            if SameFriend(info, target, conversation) then return info, true end
            -- A successful direct lookup is authoritative, including nil.
            -- Do not rescan every friend on each chat redraw for a non-friend.
            return nil, true
        end
    end
    if type(api.GetNumFriends) == "function" and type(api.GetFriendInfoByIndex) == "function" then
        local count = Number(Call(api.GetNumFriends))
        if count and count >= 0 and count <= 2000 then
            readable = true
            for i = 1, math.floor(count) do
                local info = Call(api.GetFriendInfoByIndex, i)
                if SameFriend(info, target, conversation) then return info, true end
            end
        end
    end
    return nil, readable
end

local function LegacyFriendListDisabled()
    return C_FriendList and type(C_FriendList.IsLegacyFriendSystemEnabled) == "function"
        and Boolean(C_FriendList.IsLegacyFriendSystemEnabled) ~= true
end
local function Presence(connected)
    if not Public(connected) or type(connected) ~= "boolean" then return nil end
    return connected and "online" or "offline"
end

local function ClassToken(className)
    className = String(className, 64)
    if not className then return nil end
    local male, female = Table(LOCALIZED_CLASS_NAMES_MALE), Table(LOCALIZED_CLASS_NAMES_FEMALE)
    for token in pairs(validClasses) do
        if (male and String(male[token], 64) == className) or (female and String(female[token], 64) == className) then
            return token
        end
    end
end

local function MergeProfiles(previous, profile)
    local result = NS.RestoreProfile(previous)
    local latest = NS.RestoreProfile(profile)
    if result.guid and latest.guid and result.guid ~= latest.guid then result = {} end
    for field, value in pairs(latest) do result[field] = value end
    return result
end

function NS.GetMessageProfile(author, guid)
    local name = TargetName(author)
    if not name or not Public(guid) then return {} end
    local rawGUID = String(guid, 160)
    guid = NS.RestoreProfile({ guid = rawGUID }).guid
    if rawGUID and rawGUID ~= "" and not guid then return {} end
    local profile = NS.RestoreProfile({ guid = guid })
    if guid and type(GetPlayerInfoByGUID) == "function" then
        -- Forever returns a nullable level as the eighth result. The event's
        -- full author identity must not be rebuilt from the API's short name.
        local ok, className, classToken, raceName, raceToken, sex, _, _, level = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            profile = MergeProfiles(profile, { className=className, classToken=classToken,
                raceName=raceName, raceToken=raceToken, sex=sex, level=level })
        end
    end
    local checked = {}
    local function ReadUnit(unit)
        unit = String(unit, 32)
        if not unit or checked[unit] then return false end
        checked[unit] = true
        if not IsPlayerUnit(unit) then return false end
        local unitName = FullUnitName(unit)
        local unitGUID = NS.RestoreProfile({ guid=Call(UnitGUID, unit) }).guid
        if not unitName or Fold(unitName) ~= Fold(name) or not unitGUID
            or (guid and guid ~= unitGUID) then return false end
        local className, classToken = Call(UnitClass, unit)
        local raceName, raceToken = Call(UnitRace, unit)
        profile = MergeProfiles(profile, { guid=unitGUID, className=className, classToken=classToken,
            raceName=raceName, raceToken=raceToken, level=Call(UnitLevel, unit), sex=Call(UnitSex, unit) })
        return true
    end
    if guid then ReadUnit(Call(UnitTokenFromGUID, guid)) end
    if profile.level and profile.classToken then return profile end
    -- Read only currently available unit data, once at message receipt. This
    -- does not discover contacts, query /who, or request roster refreshes.
    if ReadUnit("target") or ReadUnit("player") then return profile end
    for index = 1, 4 do if ReadUnit("party" .. index) then return profile end end
    for index = 1, 40 do if ReadUnit("raid" .. index) then return profile end end
    return profile
end

local function ContactEntry(kind, target, title, profile, presence)
    local id = kind .. ":" .. Fold(target)
    local conversation = NS.db and NS.db.conversations[id]
    return { id = id, kind = kind, target = target, title = title or target,
        profile = MergeProfiles(conversation and conversation.profile, profile), presence = presence, conversation = conversation }
end

local function AccountID(value)
    value = Number(value)
    if value and value > 0 and value <= 9007199254740991 and value == math.floor(value) then return value end
end

local function AccountProfile(info)
    local game = Table(info.gameAccountInfo)
    if not game then return {}, nil end
    local class = String(game.className, 64)
    return { guid = String(game.playerGuid, 160), className = class, classToken = ClassToken(class),
        raceName = String(game.raceName, 96), level = Number(game.characterLevel) }, Presence(game.isOnline)
end

local function BattleNetContact(info)
    info = Table(info)
    if not info then return nil end
    local accountID, target = AccountID(info.bnetAccountID), NS.BattleTag(info.battleTag)
    if not accountID or not target then return nil end
    local profile, presence = AccountProfile(info)
    local title = TargetName(info.accountName) or target
    local entry = ContactEntry("bnet", target, title, profile, presence)
    entry.accountID = accountID -- Fresh native lookup only. Never written to SavedVariables.
    return entry
end

local function EachBattleNetFriend(visitor)
    if type(BNConnected) == "function" and Boolean(BNConnected) ~= true then return nil end
    local api = C_BattleNet
    local count = Number(Call(BNGetNumFriends))
    if not api or not count or count < 0 or count > 2000 then return nil end
    for index = 1, math.floor(count) do
        local info = Table(Call(api.GetFriendAccountInfo, index))
        if info then
            local result = visitor(info)
            if result then return result end
        end
    end
end

function NS.GetBattleNetContact(target)
    target = NS.BattleTag(target)
    if not target then return nil end
    local key = Fold(target)
    return EachBattleNetFriend(function(info)
        local tag = NS.BattleTag(info.battleTag)
        if tag and Fold(tag) == key then return BattleNetContact(info) end
    end)
end

function NS.GetBattleNetContactByID(id)
    id = AccountID(id)
    if not id then return nil end
    local info = Table(Call(C_BattleNet and C_BattleNet.GetAccountInfoByID, id))
    if info and AccountID(info.bnetAccountID) == id then return BattleNetContact(info) end
    return EachBattleNetFriend(function(friend)
        if AccountID(friend.bnetAccountID) == id then return BattleNetContact(friend) end
    end)
end

function NS.GetBattleNetPresenceMap()
    local result = {}
    EachBattleNetFriend(function(info)
        local tag, game = NS.BattleTag(info.battleTag), Table(info.gameAccountInfo)
        if tag and game then result["bnet:" .. Fold(tag)] = Presence(game.isOnline) end
    end)
    return result
end

local function RecentAllyEntry(info)
    info = Table(info)
    local character = info and Table(info.characterData)
    local target = character and TargetName(character.fullName)
    if not target then return nil end
    local state = Table(info.stateData)
    local classID = Number(character.classID)
    local className, classToken
    if classID and classID > 0 then className, classToken = Call(GetClassInfo, classID) end
    return ContactEntry("whisper", target, target, { guid = character.guid, level = character.level,
        className = className, classToken = classToken, sex = character.sex }, state and Presence(state.isOnline))
end

function NS.RequestContactLists()
    if C_FriendList and not LegacyFriendListDisabled() then Call(C_FriendList.ShowFriends) end
    -- Forever's RecentAlliesDocumentation marks TryRequestRecentAlliesData as
    -- HasRestrictions. Calling it from an addon raises ADDON_ACTION_FORBIDDEN
    -- even inside pcall. Read the native cache and its update events instead;
    -- Blizzard's own recent-allies panel owns requests for fresh server data.
end

function NS.GetContactLists()
    local friends, battleNet, recent = {}, {}, {}
    local gameSeen, battleNetSeen, recentSeen = {}, {}, {}
    local function Append(list, seen, entry)
        if entry and not seen[entry.id] then
            list[#list + 1], seen[entry.id] = entry, entry
        end
    end

    if C_FriendList and not LegacyFriendListDisabled() then
        local count = Number(Call(C_FriendList.GetNumFriends))
        if count and count >= 0 and count <= 2000 then
            for index = 1, math.floor(count) do
                local info = Table(Call(C_FriendList.GetFriendInfoByIndex, index))
                local target = info and TargetName(info.name)
                if target then
                    Append(friends, gameSeen, ContactEntry("whisper", target, target,
                        { guid = info.guid, className = info.className, classToken = ClassToken(info.className), level = info.level },
                        Presence(info.connected)))
                end
            end
        end
    end

    EachBattleNetFriend(function(info)
        local accountID = AccountID(info.bnetAccountID)
        local titleTarget = accountID and TargetName(Call(C_BattleNet.GetDefaultTitleWhisperTarget, accountID))
        if titleTarget then
            local profile, presence = AccountProfile(info)
            Append(friends, gameSeen, ContactEntry("whisper", titleTarget, titleTarget, profile, presence))
        else
            Append(battleNet, battleNetSeen, BattleNetContact(info))
        end
    end)

    local allies = Table(Call(C_RecentAllies and C_RecentAllies.GetRecentAllies)) or {}
    local allyList, allySeen = {}, {}
    for _, info in ipairs(allies) do
        local ally = RecentAllyEntry(info)
        if ally then
            Append(allyList, allySeen, ally)
            local state = Table(info.stateData)
            if state and Public(state.isConvertedLegacyFriend) and state.isConvertedLegacyFriend == true then
                Append(friends, gameSeen, ally)
            end
        end
    end

    for _, person in ipairs(NS.GetRecentPeople()) do
        local live = gameSeen[person.id] or battleNetSeen[person.id] or allySeen[person.id]
        local entry = ContactEntry(person.kind, person.target, live and live.title or person.title,
            MergeProfiles(person.profile, live and live.profile), live and live.presence)
        Append(recent, recentSeen, entry)
    end
    for _, ally in ipairs(allyList) do
        if #recent >= NS.MAX_RECENT then break end
        Append(recent, recentSeen, ally)
    end
    return friends, battleNet, recent
end

function NS.GetContactPresence(conversation)
    if Table(conversation) and String(conversation.kind) == "bnet" then
        local friend = NS.GetBattleNetContact(conversation.target)
        return friend and friend.presence or "unknown"
    end
    local target = WhisperTarget(conversation)
    if not target then return "unknown" end

    if not LegacyFriendListDisabled() then
        local info = FindFriend(target, conversation)
        if info and Public(info.guid) then
            local status = Presence(info.connected)
            if status then return status end
        end
    end

    local ally = Table(Call(C_RecentAllies and C_RecentAllies.GetRecentAllyByFullName, target))
    local state = ally and Table(ally.stateData)
    local character = ally and Table(ally.characterData)
    if state and character and Public(character.guid) then
        local known, actual = ContactGUID(conversation), String(character.guid, 160)
        local allyName = TargetName(character.fullName)
        if allyName and Fold(allyName) == Fold(target) and (not known or known == actual) then
            local status = Presence(state.isOnline)
            if status then return status end
        end
    end

    local targetUnit = NS.ResolvePortraitUnit(conversation)
    if targetUnit then
        local status = Presence(Boolean(UnitIsConnected, targetUnit))
        if status then return status end
    end

    local guid = ContactGUID(conversation)
    if not guid then return "unknown" end
    local unit = String(Call(UnitTokenFromGUID, guid), 80)
    if not unit or unit == targetUnit or not IsPlayerUnit(unit) then return "unknown" end
    if String(Call(UnitGUID, unit), 160) ~= guid then return "unknown" end
    local name = FullUnitName(unit)
    if not name or Fold(name) ~= Fold(target) then return "unknown" end
    return Presence(Boolean(UnitIsConnected, unit)) or "unknown"
end

function NS.GetFriendState(conversation)
    local target = WhisperTarget(conversation)
    if not target then return "unavailable" end
    if LegacyFriendListDisabled() then return "unavailable" end
    local key = Fold(target)
    local info, readable = FindFriend(target, conversation)
    if info then pendingFriends[key] = nil; return "friend" end
    local pending = pendingFriends[key]
    if pending and Clock() - pending.started < FRIEND_TIMEOUT then return "pending" end
    if pending then pendingFriends[key] = nil end
    if not readable or not (C_FriendList and type(C_FriendList.AddFriend) == "function") then return "unavailable" end
    return "none"
end

function NS.AddSelectedFriend()
    local conversation = type(NS.GetSelected) == "function" and NS.GetSelected() or nil
    local target = WhisperTarget(conversation)
    if not target then return false, "请先选择一位玩家的私聊。" end
    local state = NS.GetFriendState(conversation)
    if state == "friend" then return false, "对方已经是你的游戏好友。" end
    if state == "pending" then return false, "正在等待游戏确认，请稍后查看。" end
    if state == "unavailable" then return false, "好友接口暂不可用，请使用游戏好友列表。" end
    local key, token = Fold(target), { started = Clock() }
    pendingFriends[key] = token
    local ok = pcall(C_FriendList.AddFriend, target)
    if not ok then
        pendingFriends[key] = nil
        return false, "游戏未接受添加好友请求，请查看游戏提示。"
    end
    if NS.GetFriendState(conversation) == "friend" then Notify(); return true, "已在游戏好友列表中确认。" end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(FRIEND_TIMEOUT, function()
            if pendingFriends[key] == token then pendingFriends[key] = nil; Notify() end
        end)
    end
    Notify()
    return true, "已提交添加好友，等待游戏好友列表确认。"
end
