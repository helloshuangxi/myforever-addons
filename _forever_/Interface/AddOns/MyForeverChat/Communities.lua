local _, NS = ...

-- Character communities use C_Club identities, never transient /1 channel slots.
-- This module transports data; Core owns conversations, drafts and read state.
local Communities = {}
NS.Communities = Communities
local entries, byID, states = {}, {}, {}
local serviceNotice, focusRequested
local liveSequence = 0
local PAGE_SIZE, REQUEST_TIMEOUT = 60, 12
local MAX_INTEGER = 9007199254740991

local function Public(value) return not (issecretvalue and issecretvalue(value)) end
local function Table(value) if Public(value) and type(value) == "table" then return value end end
local function String(value, maximum)
    if not Public(value) or type(value) ~= "string" or (maximum and #value > maximum) then return nil end
    return value
end
local function NativeToken(value)
    local text = String(value, 80)
    -- This is an opaque native rendering handle observed from C_Club, not
    -- plaintext. Do not resolve it, enumerate handles, or persist its authority.
    if text and text:match("^|Kw%d+|k$") then return text end
end
local function Number(value)
    if not Public(value) or type(value) ~= "number" or value ~= value or value < 0 or value > MAX_INTEGER then return nil end
    return value
end
local function Integer(value)
    local number = Number(value)
    if number and number == math.floor(number) then return number end
end
local function Identifier(value)
    local number = Integer(value)
    if number and number > 0 then return string.format("%.0f", number), value end
    local text = String(value, 40)
    if text and text:match("^[1-9]%d*$") then return text, value end
end
local function Key(clubId, streamId)
    local club, stream = Identifier(clubId), Identifier(streamId)
    if club and stream then return "club:" .. club .. ":" .. stream end
end
Communities.Key = Key
local function Call(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if ok then return value end
end
local function Boolean(func, ...)
    local value = Call(func, ...)
    if Public(value) and type(value) == "boolean" then return value end
end
local function Notify()
    if type(NS.NotifyChanged) == "function" then NS.NotifyChanged() end
end
local function State(id)
    if not states[id] then states[id] = { loading = false, hasMore = false } end
    return states[id]
end
local function APIReady()
    if not C_Club or type(C_Club.GetSubscribedClubs) ~= "function" or type(C_Club.GetStreams) ~= "function" then
        return false, "当前客户端没有可用的角色社区接口，请使用原生公会与社区。"
    end
    if Boolean(C_Club.IsEnabled) ~= true then return false, "角色社区服务尚未就绪，请稍后刷新或打开原生公会与社区。" end
    if type(C_Club.IsRestricted) == "function" then
        local restriction = Integer(Call(C_Club.IsRestricted))
        if restriction ~= 0 then return false, "角色社区当前受限，请在原生公会与社区中查看。" end
    end
    return true
end
local function Upsert(entry, passive)
    if type(NS.UpsertCommunity) == "function" then return NS.UpsertCommunity(entry, passive) end
    return nil, "社区会话尚未初始化。"
end
local function DisabledEntries(note)
    for _, entry in ipairs(entries) do
        entry.available = false
        State(entry.id).notice = note
        Upsert(entry, true)
    end
end

function Communities.Refresh()
    local ready, note = APIReady()
    serviceNotice = note
    if not ready then DisabledEntries(note); Notify(); return entries, note end
    local clubs = Table(Call(C_Club.GetSubscribedClubs))
    if not clubs then
        serviceNotice = "群列表暂不可读取，请稍后刷新。"
        DisabledEntries(serviceNotice); Notify(); return entries, serviceNotice
    end
    if not focusRequested and type(C_Club.FocusCommunityStreams) == "function" then
        focusRequested = true
        local ok = pcall(C_Club.FocusCommunityStreams)
        if not ok then focusRequested = nil end
    end
    local found, list = {}, {}
    local characterType = Enum and Enum.ClubType and Enum.ClubType.Character or 1
    for _, rawClub in ipairs(clubs) do
        local club = Table(rawClub)
        if club and Integer(club.clubType) == characterType and Identifier(club.clubId) then
            local streams = Table(Call(C_Club.GetStreams, club.clubId))
            if streams then
                for _, rawStream in ipairs(streams) do
                    local stream = Table(rawStream)
                    local id = stream and Key(club.clubId, stream.streamId)
                    local clubName, streamName = String(club.name, 240), stream and String(stream.name, 160)
                    if id and clubName and streamName then
                        local entry = {
                            id = id, kind = "club", target = id, title = clubName .. " · " .. streamName,
                            clubId = club.clubId, streamId = stream.streamId, clubName = clubName, streamName = streamName,
                            memberCount = Integer(club.memberCount),
                            available = Boolean(C_Club.IsSubscribedToStream, club.clubId, stream.streamId) == true,
                        }
                        found[id], list[#list + 1] = entry, entry
                        if entry.available then State(id).notice = nil
                        else State(id).notice = "此群频道暂不可用，请在原生社区中确认订阅状态。" end
                        Upsert(entry, true)
                    end
                end
            end
        end
    end
    for id, old in pairs(byID) do
        if not found[id] then
            old.available = false
            State(id).notice = "已离开此群或频道暂不可读取；本机记录和草稿仍保留。"
            Upsert(old, true)
        end
    end
    table.sort(list, function(a, b)
        if a.clubName ~= b.clubName then return a.clubName < b.clubName end
        if a.streamName ~= b.streamName then return a.streamName < b.streamName end
        return a.id < b.id
    end)
    entries, byID = list, found
    Notify()
    return entries, serviceNotice
end

function Communities.GetEntries() return entries, serviceNotice end
function Communities.GetLiveSequence() return liveSequence end
function Communities.NativeContent(message)
    message = Table(message)
    if message and Public(message.communityNativeContent) and message.communityNativeContent == true then
        return NativeToken(message.text)
    end
end
function Communities.GetEntry(id) return String(id, 260) and byID[id] or nil end
function Communities.GetStatus(id)
    id = String(id, 260)
    if not id then return { loading = false, hasMore = false, notice = serviceNotice } end
    return states[id] or { loading = false, hasMore = false, notice = serviceNotice }
end

local function MessageID(value)
    value = Table(value)
    local epoch, position = value and Integer(value.epoch), value and Integer(value.position)
    if epoch and position then return { epoch = epoch, position = position } end
end
local function SameMessage(a, b)
    return a and b and a.epoch == b.epoch and a.position == b.position
end
local function Later(a, b)
    return a.epoch > b.epoch or (a.epoch == b.epoch and a.position > b.position)
end
local function Message(raw, mode)
    raw = Table(raw)
    local mid = raw and MessageID(raw.messageId)
    local author = raw and Table(raw.author)
    if not mid or not author or not Public(raw.destroyed) or not Public(raw.edited) then return nil end
    local text = raw.destroyed == true and "[消息已由原生社区删除]" or String(raw.content, 4096)
    if not text or text == "" or not Public(author.isSelf) or type(author.isSelf) ~= "boolean" then return nil end
    local name = String(author.name, 160)
    local profile = { guid = String(author.guid, 160), level = Integer(author.level) }
    local classID = Integer(author.classID)
    local class = classID and Table(Call(C_CreatureInfo and C_CreatureInfo.GetClassInfo, classID))
    if class then profile.className, profile.classToken = String(class.className, 80), String(class.classFile, 24) end
    return {
        id = string.format("clubmsg:%.0f:%.0f", mid.epoch, mid.position),
        text = text, author = name or "社区成员", outgoing = author.isSelf,
        time = math.floor(mid.epoch / 1000000), chatType = "COMMUNITIES_CHANNEL", profile = profile,
        clubEpoch = mid.epoch, clubPosition = mid.position, communityLive = mode == "live",
        communityAuthorKnown = name ~= nil, communityEdited = raw.edited == true, communityDeleted = raw.destroyed == true,
        communityNativeContent = raw.destroyed ~= true and NativeToken(text) ~= nil,
    }
end
local function Store(entry, raw, mode)
    local message = Message(raw, mode)
    if not message or type(NS.StoreCommunityMessage) ~= "function" then return false end
    if mode == "live" then
        -- Merely discovering a stream must not consume the 30-conversation
        -- budget. Only explicit Open or a readable live arrival admits it.
        if not Upsert(entry) then return false end
        liveSequence = liveSequence + 1
        message.communitySequence = liveSequence
    end
    return NS.StoreCommunityMessage(entry.id, message, mode)
end
local function ReadHistory(entry)
    local ranges = Table(Call(C_Club.GetMessageRanges, entry.clubId, entry.streamId))
    local latest = ranges and Table(ranges[#ranges])
    local newest, oldest = latest and MessageID(latest.newestMessageId), latest and MessageID(latest.oldestMessageId)
    if not newest or not oldest or Later(oldest, newest) then return false end
    local messages = Table(Call(C_Club.GetMessagesBefore, entry.clubId, entry.streamId, newest, PAGE_SIZE))
    if not messages then return false end
    local first
    for _, raw in ipairs(messages) do
        local mid = Table(raw) and MessageID(raw.messageId)
        if mid and (not first or Later(first, mid)) then first = mid end
        Store(entry, raw, "history")
    end
    local state = State(entry.id)
    state.oldest = first
    state.hasMore = first ~= nil and Boolean(C_Club.IsBeginningOfStream, entry.clubId, entry.streamId, first) ~= true
    state.notice = #messages == 0 and "此群频道暂无可读取的消息。" or (state.hasMore and "已读取最近消息；更早历史可在原生社区中查看。" or nil)
    return true
end

function Communities.Open(id)
    id = String(id, 260)
    if not id then return false, "群会话无效。" end
    Communities.Refresh()
    local entry = byID[id]
    if not entry or not entry.available then return false, State(id).notice or serviceNotice or "此群频道暂不可用。" end
    local conv, note = Upsert(entry)
    if not conv then return false, note or "群会话已满，请先整理会话。" end
    local state = State(id)
    if state.loading then return true, "正在读取群消息。" end
    if ReadHistory(entry) then Notify(); return true, state.notice end
    if type(C_Club.RequestMoreMessagesBefore) ~= "function" then return false, "当前客户端无法读取群历史，请使用原生社区。" end
    local request = {}
    state.request, state.loading, state.notice = request, true, "正在读取群消息。"
    local ok, cached = pcall(C_Club.RequestMoreMessagesBefore, entry.clubId, entry.streamId, nil, PAGE_SIZE)
    if not ok then state.loading, state.request, state.notice = false, nil, "群消息读取失败，请稍后重试。"
    elseif Public(cached) and cached == true then
        state.loading, state.request = false, nil
        if not ReadHistory(entry) then state.notice = "群历史暂不可读取，请稍后重试。" end
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(REQUEST_TIMEOUT, function()
            if state.request == request and state.loading then
                state.loading, state.request, state.notice = false, nil, "群历史尚未返回，可再次打开群聊重试。"
                Notify()
            end
        end)
    end
    Notify()
    return ok, state.notice
end

function Communities.LoadOlder(id)
    return false, "当前窗口保留最近 60 条群消息；更早历史请点「原生社区」查看。"
end

function Communities.Send(id, text)
    id = String(id, 260)
    if not id then return false, "群会话无效，草稿已保留。" end
    local body, note
    if type(NS.ValidateText) == "function" then body, note = NS.ValidateText(text) end
    if not body then return false, note or "群消息不可读取，请重新输入。" end
    -- Re-resolve membership at the actual click/Enter, never by selectedId later.
    Communities.Refresh()
    local entry = byID[id]
    if not entry or not entry.available then return false, "已离开此群或尚未订阅此频道，消息未发送。" end
    local stream = Table(Call(C_Club.GetStreamInfo, entry.clubId, entry.streamId))
    if not stream or not Key(entry.clubId, stream.streamId) or Key(entry.clubId, stream.streamId) ~= id then
        return false, "无法核对群频道身份，消息未发送。"
    end
    if Boolean(C_Club.IsAccountMuted, entry.clubId) ~= false then return false, "无法确认社区发言权限，请在原生社区中检查。" end
    if C_SocialRestrictions and Boolean(C_SocialRestrictions.IsChatDisabled) ~= false then
        return false, "当前聊天受到限制，消息未发送。"
    end
    local privileges = Table(Call(C_Club.GetClubPrivileges, entry.clubId))
    if not privileges or not Public(privileges.canCreateMessage) or privileges.canCreateMessage ~= true then
        return false, "当前没有可确认的群发言权限，消息未发送。"
    end
    if not Public(stream.leadersAndModeratorsOnly) then return false, "此群频道的发言权限暂不可读取。" end
    if stream.leadersAndModeratorsOnly == true then
        local selfInfo = Table(Call(C_Club.GetMemberInfoForSelf, entry.clubId))
        local role = selfInfo and Integer(selfInfo.role)
        local roles = Enum and Enum.ClubRoleIdentifier
        if not roles or not role or (role ~= roles.Owner and role ~= roles.Leader and role ~= roles.Moderator) then
            return false, "此群频道只允许群主、管理员和主持人发言。"
        end
    end
    if type(C_Club.SendMessage) ~= "function" then return false, "当前客户端的群消息发送接口不可用。" end
    -- SendMessage has no return value. A pcall success is submission, not delivery.
    local ok = pcall(C_Club.SendMessage, entry.clubId, entry.streamId, body)
    if not ok then return false, "游戏未接受群消息请求，草稿已保留。" end
    return true, "已提交至角色社区，等待原生消息回显；尚未确认送达。"
end

function Communities.OpenNative(id)
    if Boolean(InCombatLockdown) == true then return false, "请在战斗结束后打开原生公会与社区。" end
    if not CommunitiesFrame and C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Communities")
    end
    local frame = CommunitiesFrame
    if not frame or type(frame.Show) ~= "function" then return false, "请按 J 打开原生公会与社区，再选择「加入或创建社区」。" end
    local ok = pcall(function()
        if type(ShowUIPanel) == "function" then ShowUIPanel(frame) else frame:Show() end
        local entry = String(id, 260) and byID[id]
        if entry and entry.available then
            if type(frame.SelectClub) == "function" then frame:SelectClub(entry.clubId) end
            if type(frame.SelectStream) == "function" then frame:SelectStream(entry.clubId, entry.streamId) end
        end
    end)
    if not ok then return false, "请按 J 打开原生公会与社区。" end
    return true, "请在原生窗口创建、加入或邀请成员；新建时选择《魔兽世界》角色社区。"
end

function Communities.OpenInvite(id)
    id = String(id, 260)
    if not id then return false, "请先选择要邀请朋友加入的角色社区。" end
    if Boolean(InCombatLockdown) == true then return false, "请在战斗结束后邀请朋友。" end
    Communities.Refresh()
    local entry = byID[id]
    if not entry or not entry.available then return false, "已离开此群或频道暂不可用，无法邀请朋友。" end
    local club = Table(Call(C_Club.GetClubInfo, entry.clubId))
    local stream = Table(Call(C_Club.GetStreamInfo, entry.clubId, entry.streamId))
    local characterType = Enum and Enum.ClubType and Enum.ClubType.Character or 1
    if not club or Integer(club.clubType) ~= characterType or Identifier(club.clubId) ~= Identifier(entry.clubId)
        or not stream or Key(club.clubId, stream.streamId) ~= id then
        return false, "无法核对当前角色社区身份，请刷新群聊后重试。"
    end
    local privileges = Table(Call(C_Club.GetClubPrivileges, entry.clubId))
    if not privileges or not Public(privileges.canSendInvitation) or privileges.canSendInvitation ~= true then
        return false, "当前没有可确认的邀请权限，请联系群主或管理员。"
    end
    local count, capacity = Integer(club.memberCount), Integer(Call(C_Club.GetClubCapacity))
    if not count or not capacity or capacity == 0 then return false, "暂时无法确认社区人数上限，请在原生社区中邀请。" end
    if count >= capacity then return false, "此社区成员已满，暂时无法邀请新朋友。" end

    local opened, note = Communities.OpenNative(id)
    if not opened then return false, note end
    local frame = CommunitiesFrame
    if not frame or Boolean(frame.IsShown, frame) ~= true
        or Key(Call(frame.GetSelectedClubId, frame), Call(frame.GetSelectedStreamId, frame)) ~= id then
        return false, "原生窗口未能选中此群，请在原生社区中选择后邀请。"
    end
    local invite = frame.InviteButton
    if not invite or Boolean(invite.IsShown, invite) ~= true or Boolean(invite.IsEnabled, invite) ~= true then
        return false, "原生邀请按钮暂不可用，请在原生社区中检查权限和群状态。"
    end
    -- Forever marks the invite popup editBoxSecureText: StaticPopup_Show
    -- rejects addon/tainted calls. Hand off to the visible native button;
    -- only the user's own native click may open that protected dialog.
    return true, "已打开此群，请点原生窗口右下角「邀请成员」。"
end

Communities.Events = {
    "INITIAL_CLUBS_LOADED", "CLUB_ADDED", "CLUB_REMOVED", "CLUB_UPDATED", "CLUB_STREAMS_LOADED",
    "CLUB_STREAM_ADDED", "CLUB_STREAM_REMOVED", "CLUB_STREAM_UPDATED", "CLUB_STREAM_SUBSCRIBED",
    "CLUB_STREAM_UNSUBSCRIBED", "CLUB_SELF_MEMBER_ROLE_UPDATED", "CLUB_MESSAGE_ADDED",
    "CLUB_MESSAGE_HISTORY_RECEIVED", "CLUB_MESSAGE_UPDATED", "CLUB_ERROR",
}
local eventSet = {}
for _, event in ipairs(Communities.Events) do eventSet[event] = true end
function Communities.HandleEvent(event, clubId, streamId, messageId)
    if not String(event, 80) or not eventSet[event] then return false end
    if event == "CLUB_ERROR" then
        local action = Integer(clubId)
        local sendAction = Enum and Enum.ClubActionType and Enum.ClubActionType.ErrorClubActionCreateMessage or 24
        if action == sendAction then
            -- CLUB_ERROR has action/error/type, but no club or stream identity.
            -- Do not blame a specific pending send or retry it automatically.
            serviceNotice = "原生社区报告发送限制，请查看原生提示；未确认的草稿仍保留。"
            Notify()
        end
        return true
    end
    if event ~= "CLUB_MESSAGE_ADDED" and event ~= "CLUB_MESSAGE_UPDATED" and event ~= "CLUB_MESSAGE_HISTORY_RECEIVED" then
        Communities.Refresh()
        return true
    end
    local id = Key(clubId, streamId)
    if not id then return true end
    local entry = byID[id]
    if not entry then Communities.Refresh(); entry = byID[id] end
    if not entry or not entry.available then return true end
    if event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        local state = State(id)
        state.loading, state.request = false, nil
        ReadHistory(entry)
        Notify()
    else
        local mid = MessageID(messageId)
        if not mid then return true end
        -- GetMessagesBefore honors the game's ignored-player filtering.
        local filtered = Table(Call(C_Club.GetMessagesBefore, clubId, streamId, mid, 1))
        local allowed = false
        if filtered then
            for _, raw in ipairs(filtered) do
                if Table(raw) and SameMessage(MessageID(raw.messageId), mid) then allowed = true; break end
            end
        end
        if allowed then
            local raw = Call(C_Club.GetMessageInfo, clubId, streamId, mid)
            Store(entry, raw, event == "CLUB_MESSAGE_ADDED" and "live" or "update")
        end
    end
    return true
end
