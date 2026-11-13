local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "check") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(value, label) checks = checks + 1; assert(value, label) end
local secret = setmetatable({ secret = true }, { __tostring = function() error("secret coercion") end, __eq = function() error("secret comparison") end })
issecretvalue = function(value) return type(value) == "table" and rawget(value, "secret") == true end
Enum = { ClubType = { Character = 1, BattleNet = 0, Guild = 2 }, ClubRoleIdentifier = { Owner = 1, Leader = 2, Moderator = 3, Member = 4 }, ClubActionType = { ErrorClubActionCreateMessage = 24 } }
local clubId, streamId, epoch = "9007199254740993", 7, 1793940000123456
local clubs = {
    { clubId = clubId, name = "角色社区", clubType = 1, memberCount = 2 },
    { clubId = 2, name = "战网群", clubType = 0 },
    { clubId = 3, name = "公会", clubType = 2 },
}
local streams = { { streamId = streamId, name = "综合", leadersAndModeratorsOnly = false } }
local enabled, restriction, subscribed, muted, chatDisabled = true, 0, true, false, false
local privilege, role, rejectSend, requestsCached, rangeMissing, ignoreLatest = true, 4, false, false, false, false
local streamSecret, clubSecret, hasBeginning = false, false, false
local messages, calls, stored, upserts, timers = {}, {}, {}, {}, {}
local focusCount, requestCount, sendCount, notices = 0, 0, 0, 0
local function message(position, content, outgoing)
    return { messageId = { epoch = epoch, position = position }, content = content, destroyed = false, edited = false,
        author = { name = outgoing and "本人-服务器" or "队友-服务器", isSelf = outgoing == true, memberId = outgoing and 1 or 2, clubType = 1, level = 20 } }
end
local function same(a, b) return a.epoch == b.epoch and a.position == b.position end
local function before(a, b) return a.epoch < b.epoch or (a.epoch == b.epoch and a.position <= b.position) end
local function capture(name, ...) calls[#calls + 1] = { name, ... } end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_Club = {
    IsEnabled = function() return enabled end,
    IsRestricted = function() return restriction end,
    GetSubscribedClubs = function() return clubSecret and secret or clubs end,
    GetStreams = function(id) eq(id, clubId, "only Character communities enumerated"); return streamSecret and secret or streams end,
    IsSubscribedToStream = function(c, s) return subscribed end,
    FocusCommunityStreams = function() focusCount = focusCount + 1 end,
    GetStreamInfo = function(c, s) return streams[1] end,
    IsAccountMuted = function() return muted end,
    GetClubPrivileges = function() return { canCreateMessage = privilege } end,
    GetMemberInfoForSelf = function() return { role = role } end,
    GetMessageRanges = function(c, s)
        capture("ranges", c, s)
        if rangeMissing or #messages == 0 then return {} end
        return { { oldestMessageId = messages[1].messageId, newestMessageId = messages[#messages].messageId } }
    end,
    GetMessagesBefore = function(c, s, mid, count)
        capture("before", c, s, mid, count)
        local result = {}
        for _, item in ipairs(messages) do
            if before(item.messageId, mid) and not (ignoreLatest and same(item.messageId, mid)) then result[#result + 1] = item end
        end
        while #result > count do table.remove(result, 1) end
        return result
    end,
    GetMessageInfo = function(c, s, mid)
        capture("info", c, s, mid)
        for _, item in ipairs(messages) do if same(item.messageId, mid) then return item end end
    end,
    IsBeginningOfStream = function() return hasBeginning end,
    RequestMoreMessagesBefore = function(c, s, mid, count)
        requestCount = requestCount + 1; capture("request", c, s, mid, count); return requestsCached
    end,
    SendMessage = function(c, s, text)
        if rejectSend then error("send restricted") end
        sendCount = sendCount + 1; capture("send", c, s, text)
        -- Intentionally nil: native API documents no result.
    end,
}
C_SocialRestrictions = { IsChatDisabled = function() return chatDisabled end }
local NS = {
    NotifyChanged = function() notices = notices + 1 end,
    ValidateText = function(text)
        if type(text) ~= "string" or text == "" then return nil, "invalid" end
        return text
    end,
    UpsertCommunity = function(entry) upserts[entry.id] = entry; return entry end,
    StoreCommunityMessage = function(id, item, mode) stored[#stored + 1] = { id = id, message = item, mode = mode }; return true end,
    GetSelected = function() error("transport must not borrow selected conversation") end,
}
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Communities.lua"))("MyForeverChat", NS)
local C = NS.Communities
local id = "club:" .. clubId .. ":7"
eq(C.Key(clubId, streamId), id, "opaque decimal club identity preserves precision")
eq(C.Key(secret, streamId), nil, "secret club ID ignored")
eq(C.Key(clubId, 0), nil, "zero stream rejected")
eq(C.Key(clubId, 0/0), nil, "NaN stream rejected")
eq(C.Key(clubId, 1.5), nil, "fractional stream rejected")
eq(C.Key("a:7", streamId), nil, "injected ID rejected")
local list = C.Refresh()
eq(#list, 1, "only Character community listed")
eq(list[1].id, id, "stable stream identity")
eq(list[1].title, "角色社区 · 综合", "name and stream disambiguated")
eq(list[1].memberCount, 2, "known membership count exposed")
eq(list[1].available, true, "subscribed stream available")
eq(C.GetStatus(id).notice, nil, "available stream has no false unavailable notice")
eq(focusCount, 1, "live community streams focused")
C.Refresh(); eq(focusCount, 1, "refresh does not repeatedly focus")
eq(sendCount, 0, "enumeration never sends")
eq(requestCount, 0, "enumeration does not bulk-fetch history")

messages = { message(1, "old message", false), message(2, "same words", true) }
eq(C.Open(id), true, "open cached history")
eq(#stored, 2, "two server messages handed to Core")
eq(stored[1].mode, "history", "history mode explicit")
eq(stored[1].message.communityLive, false, "history cannot confirm sends")
eq(stored[1].message.communitySequence, nil, "history has no live sequence")
eq(C.GetLiveSequence(), 0, "history does not advance live sequence")
eq(stored[1].message.id, "clubmsg:1793940000123456:1", "message ID uses all digits not scientific notation")
eq(stored[1].message.time, 1793940000, "microseconds converted to seconds")
eq(stored[1].message.outgoing, false, "other member incoming")
eq(stored[2].message.outgoing, true, "self identified from native isSelf")
eq(requestCount, 0, "cached range needs no request")
eq(C.GetStatus(id).hasMore, true, "older history linked to native UI")
eq(C.LoadOlder(id), false, "no misleading pagination beyond local limit")
eq(sendCount, 0, "history never resends contents")

messages[#messages + 1] = message(3, "live message", false)
eq(C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[3].messageId), true, "live event consumed")
eq(stored[#stored].mode, "live", "real-time event mode")
eq(stored[#stored].message.communityLive, true, "real-time marker")
eq(stored[#stored].message.communitySequence, 1, "live sequence attaches to message")
eq(C.GetLiveSequence(), 1, "UI can capture live baseline before sending")
eq(stored[#stored].id, id, "event uses club and stream identity")
messages[3].content, messages[3].edited = "edited", true
C.HandleEvent("CLUB_MESSAGE_UPDATED", clubId, streamId, messages[3].messageId)
eq(stored[#stored].mode, "update", "edit never becomes new incoming")
eq(stored[#stored].message.communityEdited, true, "edit flag")
eq(stored[#stored].message.communityLive, false, "edit cannot confirm pending send")
eq(stored[#stored].message.communitySequence, nil, "edit loses live confirmation marker")
messages[3].destroyed = true
messages[3].content = secret
C.HandleEvent("CLUB_MESSAGE_UPDATED", clubId, streamId, messages[3].messageId)
eq(stored[#stored].message.text, "[消息已由原生社区删除]", "deleted body removed without reading secret content")
eq(stored[#stored].message.communityDeleted, true, "deletion marker")
local previous = #stored
ignoreLatest = true
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[3].messageId)
eq(#stored, previous, "ignored messages not surfaced through GetMessageInfo")
ignoreLatest = false
C.HandleEvent("CLUB_MESSAGE_ADDED", secret, streamId, messages[3].messageId)
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, secret)
eq(#stored, previous, "secret identities never persisted")
messages[#messages + 1] = message(4, secret, false)
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[4].messageId)
eq(#stored, previous, "secret content ignored")
messages[4].content, messages[4].author.isSelf = "readable", secret
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[4].messageId)
eq(#stored, previous, "secret direction ignored")
messages[4].author.isSelf, messages[4].author.name = false, nil
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[4].messageId)
eq(stored[#stored].message.author, "社区成员", "missing name has display fallback")
eq(stored[#stored].message.communityAuthorKnown, false, "fallback cannot become whisper recipient")
messages[4].content = "|Kw12|k"
C.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[4].messageId)
local nativeMessage = stored[#stored].message
eq(nativeMessage.communityNativeContent, true, "C_Club native body gets transient render authority")
eq(C.NativeContent(nativeMessage), "|Kw12|k", "native body returned unchanged for renderer, not decoded")
eq(C.NativeContent({text="|Kw12|k"}), nil, "text alone has no native render authority")
eq(C.NativeContent({text="|Kw12|k",communityNativeContent=secret}), nil, "secret render flag rejected")
eq(C.NativeContent({text=secret,communityNativeContent=true}), nil, "secret body never inspected")
for _, value in ipairs({"||Kw12||k", "prefix |Kw12|k", "|Kw12|k suffix", "|Kw12|k|Hitem:1|hbad|h", "|Kx12|k", "|Kw12.5|k", "|Kw|k"}) do
    eq(C.NativeContent({text=value,communityNativeContent=true}), nil, "unverified/literal/mixed token rejected")
end
messages[4].content = "readable"
eq(C.HandleEvent("CHAT_MSG_WHISPER", "test"), false, "unrelated event not consumed")

rangeMissing = true
eq(C.Open(id), true, "missing cache requests history")
eq(requestCount, 1, "single request")
eq(C.GetStatus(id).loading, true, "loading visible")
eq(calls[#calls][1], "request", "request API called")
eq(calls[#calls][4], nil, "latest history begins with nil cursor")
eq(calls[#calls][5], 60, "bounded request")
C.Open(id); eq(requestCount, 1, "concurrent opens deduplicated")
timers[#timers](); eq(C.GetStatus(id).loading, false, "timeout releases read request")
C.Open(id); eq(requestCount, 2, "manual retry possible after timeout")
rangeMissing = false
C.HandleEvent("CLUB_MESSAGE_HISTORY_RECEIVED", clubId, streamId, {})
eq(C.GetStatus(id).loading, false, "history completion clears loading")
eq(stored[#stored].mode, "history", "late history remains quiet")
timers[#timers](); eq(C.GetStatus(id).loading, false, "old timer cannot reset completed request")

local sendsBefore = sendCount
eq(C.Send(id, "hello"), true, "native nil result accepted as submitted")
eq(sendCount, sendsBefore + 1, "exactly one send")
eq(calls[#calls][2], clubId, "explicit club ID sent unchanged")
eq(calls[#calls][3], streamId, "explicit stream sent")
eq(calls[#calls][4], "hello", "body sent once")
eq(C.Send(id, ""), false, "invalid message rejected")
subscribed = false; eq(C.Send(id, "blocked"), false, "left stream cannot send"); subscribed = true
muted = true; eq(C.Send(id, "blocked"), false, "muted account cannot send"); muted = false
muted = secret; eq(C.Send(id, "blocked"), false, "unknown mute permission fails closed"); muted = false
privilege = false; eq(C.Send(id, "blocked"), false, "missing send privilege"); privilege = true
chatDisabled = true; eq(C.Send(id, "blocked"), false, "social restriction"); chatDisabled = false
streams[1].leadersAndModeratorsOnly = true
eq(C.Send(id, "blocked"), false, "member cannot send in moderator-only stream")
role = 3; eq(C.Send(id, "moderator"), true, "moderator allowed")
streams[1].leadersAndModeratorsOnly, role = false, 4
rejectSend = true; eq(C.Send(id, "blocked"), false, "native exception preserves failure"); rejectSend = false
eq(sendCount, sendsBefore + 2, "blocked sends do not reach API")
local beforeError = #stored
C.HandleEvent("CLUB_ERROR", 24, 15, 1)
eq(#stored, beforeError, "ambiguous CLUB_ERROR creates no fake record")
local _, errorNote = C.GetEntries(); check(errorNote:find("发送限制") ~= nil, "generic error notice")
eq(sendCount, sendsBefore + 2, "error never automatically retries")

clubSecret = true; C.Refresh(); eq(upserts[id].available, false, "secret list marks stale route unavailable"); clubSecret = false
C.Refresh(); eq(C.GetEntry(id).available, true, "service recovery restores route")
restriction = 1; eq(C.Send(id, "blocked"), false, "restricted service blocked"); restriction = 0
enabled = secret; C.Refresh(); eq(C.GetEntry(id).available, false, "secret enabled status fails closed"); enabled = true
C.Refresh()
clubs = {}; C.HandleEvent("CLUB_REMOVED", clubId)
eq(#C.GetEntries(), 0, "removed group disappears from joined list")
eq(upserts[id].available, false, "Core told to retain unavailable local conversation")
eq(C.Send(id, "blocked"), false, "cached group cannot send after leaving")

local shown, selectedClub, selectedStream, nativeCalls = false, nil, nil, 0
InCombatLockdown = function() return false end
CommunitiesFrame = { Show = function() shown = true end, SelectClub = function(_, c) selectedClub = c end, SelectStream = function(_, c, s) selectedStream = s end }
eq(C.OpenNative(), true, "native create/join entry opens")
eq(shown, true, "native frame shown")
eq(selectedClub, nil, "generic entry does not select unrelated community")
InCombatLockdown = function() return true end
shown = false; eq(C.OpenNative(), false, "native management deferred during combat"); eq(shown, false, "combat does not mutate native frame")
InCombatLockdown = function() return false end
CommunitiesFrame, C_AddOns = nil, { LoadAddOn = function(name) eq(name, "Blizzard_Communities", "native module name"); nativeCalls = nativeCalls + 1 end }
eq(C.OpenNative(), false, "missing native frame offers keyboard fallback")
eq(nativeCalls, 1, "only native UI addon loaded")
eq(sendCount, sendsBefore + 2, "management never sends or creates directly")

-- Invitation hands off to the real native button; its protected popup must
-- only open from a native click, never from this addon's tainted context.
do
    local oldClubInfo, oldPrivileges, oldCapacity = C_Club.GetClubInfo, C_Club.GetClubPrivileges, C_Club.GetClubCapacity
    local oldFrame, oldAddOns = CommunitiesFrame, C_AddOns
    local invitePrivilege, inviteCapacity = true, 1000
    local inviteClub = { clubId = clubId, clubType = 1, memberCount = 2 }
    local inviteShown, inviteEnabled, inviteCalls = true, true, 0
    local selectedClubOverride, selectedStreamOverride, frameHidden, selectionError
    clubs = { { clubId = clubId, name = "角色社区", clubType = 1, memberCount = 2 } }
    C_Club.GetClubInfo = function() return inviteClub end
    C_Club.GetClubPrivileges = function() return { canCreateMessage = privilege, canSendInvitation = invitePrivilege } end
    C_Club.GetClubCapacity = function() return inviteCapacity end
    local native = {
        Show = function() shown = true end,
        IsShown = function() return shown and not frameHidden end,
        SelectClub = function(_, value) if selectionError then error("selection unavailable") end; selectedClub = value end,
        SelectStream = function(_, c, s) selectedStream = s end,
        GetSelectedClubId = function() return selectedClubOverride or selectedClub end,
        GetSelectedStreamId = function() return selectedStreamOverride or selectedStream end,
    }
    local inviteButton = {
        IsShown = function() return inviteShown end,
        IsEnabled = function() return inviteEnabled end,
        Click = function() inviteCalls = inviteCalls + 1; error("addon cannot click native invitation") end,
    }
    native.InviteButton = inviteButton
    CommunitiesFrame = native
    CommunitiesUtil = { OpenInviteDialog = function()
        inviteCalls = inviteCalls + 1
        error("Dialog INVITE_COMMUNITY_MEMBER_WITH_INVITE_LINK cannot be shown from a tainted context")
    end }
    local beforeInviteSend, beforeInviteStored = sendCount, #stored
    local ok, note = C.OpenInvite(id)
    eq(ok, true, "visible enabled native invite button confirmed")
    check(note:find("请点原生窗口右下角") ~= nil, "handoff clearly requires the user's native invitation click")
    eq(selectedClub, clubId, "native community uses exact opaque requested club ID")
    eq(selectedStream, streamId, "native community selects requested stream")
    eq(shown, true, "native community stays visible for user click")
    eq(inviteCalls, 0, "successful handoff never invokes protected popup or native button click")
    eq(C.OpenInvite(secret), false, "secret invite identity rejected")
    eq(C.OpenInvite("club:unknown:7"), false, "unknown group cannot open invite")
    InCombatLockdown = function() return true end
    eq(C.OpenInvite(id), false, "combat cannot open invite")
    InCombatLockdown = function() return false end
    subscribed = false; eq(C.OpenInvite(id), false, "unsubscribed group cannot invite"); subscribed = true
    restriction = 1; eq(C.OpenInvite(id), false, "restricted service cannot invite"); restriction = 0
    for _, denied in ipairs({ false, secret }) do
        invitePrivilege = denied
        local deniedOK, deniedNote = C.OpenInvite(id)
        eq(deniedOK, false, "unknown or denied invitation rights fail closed")
        check(deniedNote:find("邀请权限") ~= nil, "permission failure is actionable")
    end
    invitePrivilege = nil; eq(C.OpenInvite(id), false, "missing invitation privilege rejected"); invitePrivilege = true
    inviteClub.clubId = "999"; eq(C.OpenInvite(id), false, "changed native club identity rejected"); inviteClub.clubId = clubId
    inviteClub.clubType = 0; eq(C.OpenInvite(id), false, "BattleNet group cannot masquerade as character community"); inviteClub.clubType = 1
    inviteClub.memberCount = inviteCapacity
    local fullOK, fullNote = C.OpenInvite(id)
    eq(fullOK, false, "full community cannot invite")
    check(fullNote:find("已满") ~= nil, "full-community reason displayed")
    inviteClub.memberCount = 2
    inviteCapacity = secret; eq(C.OpenInvite(id), false, "secret capacity not compared"); inviteCapacity = 1000
    local savedClub = inviteClub
    inviteClub = secret; eq(C.OpenInvite(id), false, "secret club metadata rejected"); inviteClub = savedClub
    eq(inviteCalls, 0, "identity and permission failures never open invitation")
    selectedClubOverride = "999"; eq(C.OpenInvite(id), false, "wrong native selected group cannot open invitation"); selectedClubOverride = nil
    selectedStreamOverride = 99; eq(C.OpenInvite(id), false, "wrong native selected stream cannot open invitation"); selectedStreamOverride = nil
    frameHidden = true; eq(C.OpenInvite(id), false, "hidden native panel is not invite success"); frameHidden = false
    selectionError = true; eq(C.OpenInvite(id), false, "native selection exception handled"); selectionError = false
    native.InviteButton = nil; eq(C.OpenInvite(id), false, "missing native invitation control cannot claim success"); native.InviteButton = inviteButton
    inviteShown = false; eq(C.OpenInvite(id), false, "hidden native invitation control rejected"); inviteShown = true
    inviteEnabled = false; eq(C.OpenInvite(id), false, "disabled native invitation control rejected"); inviteEnabled = true
    inviteEnabled = secret; eq(C.OpenInvite(id), false, "secret native invitation availability rejected"); inviteEnabled = true
    local isEnabled = inviteButton.IsEnabled
    inviteButton.IsEnabled = function() error("unreadable native state") end
    eq(C.OpenInvite(id), false, "unreadable native button state cannot claim success")
    inviteButton.IsEnabled = isEnabled
    CommunitiesFrame = nil
    C_AddOns = { LoadAddOn = function() CommunitiesFrame = native end }
    eq(C.OpenInvite(id), true, "native community loads on demand before invitation handoff")
    clubs = {}; eq(C.OpenInvite(id), false, "cached group cannot invite after leaving")
    eq(sendCount, beforeInviteSend, "invitation entry sends no chat messages")
    eq(#stored, beforeInviteStored, "invitation entry changes no message history")
    eq(inviteCalls, 0, "no success or failure path opens or clicks the protected invitation")
    C_Club.GetClubInfo, C_Club.GetClubPrivileges, C_Club.GetClubCapacity = oldClubInfo, oldPrivileges, oldCapacity
    CommunitiesFrame, C_AddOns, CommunitiesUtil = oldFrame, oldAddOns, nil
end

-- Integrate the real Core callbacks: overlap, reload, unread and clear semantics.
GetServerTime = function() return 1793940000 end
clubs = { { clubId = clubId, name = "角色社区", clubType = 1, memberCount = 2 } }
messages = { message(10, "same", false), message(11, "same", false) }
local actual = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Core.lua"))("MyForeverChat", actual)
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Communities.lua"))("MyForeverChat", actual)
local db = actual.InitDB(nil)
local live = actual.Communities
live.Refresh()
eq(db.conversations[id], nil, "listing a joined group does not admit an active conversation")
eq(live.Open(id), true, "explicit open admits group and reads history")
local conv = db.conversations[id]
check(conv ~= nil, "real Core admits club conversation")
eq(conv.kind, "club", "Core group kind")
eq(conv.available, true, "Core availability")
eq(conv.memberCount, 2, "Core member count")
eq(live.Open(id), true, "real Core reads history")
eq(#conv.messages, 2, "same text with different server IDs preserved")
eq(conv.unread, 0, "history has no unread")
eq(actual.lastIncoming, nil, "history has no popup source")
live.Open(id)
eq(#conv.messages, 2, "overlapping history deduplicated")
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[1].messageId)
eq(conv.messages[1].communityLive, false, "replayed historical ID is not a fresh echo")
eq(conv.messages[1].communitySequence, nil, "replayed history ID cannot acquire a new confirmation sequence")
messages[#messages + 1] = message(12, "incoming", false)
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[3].messageId)
eq(#conv.messages, 3, "live message inserted once")
eq(conv.unread, 1, "new live incoming increments unread")
eq(actual.lastIncoming.conversationId, id, "live notification belongs to correct group")
local firstLiveSequence = conv.messages[3].communitySequence
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[3].messageId)
eq(#conv.messages, 3, "duplicate live event not appended")
eq(conv.unread, 1, "duplicate live event no extra unread")
eq(conv.messages[3].communitySequence, firstLiveSequence, "duplicate live ID keeps original confirmation boundary")
messages[3].content, messages[3].edited = "changed", true
live.HandleEvent("CLUB_MESSAGE_UPDATED", clubId, streamId, messages[3].messageId)
eq(#conv.messages, 3, "update replaces same message")
eq(conv.messages[3].text, "changed", "updated content visible")
eq(conv.messages[3].communityLive, false, "Core clears live marker on edit")
eq(conv.messages[3].communitySequence, nil, "Core clears live sequence on edit")
eq(conv.unread, 1, "edit does not increment unread")
actual.ToggleMute(id)
eq(actual.UnreadTotal(), 0, "muted group excluded from launcher total")
eq(conv.unread, 1, "muting preserves conversation unread")
actual.Select(id)
eq(conv.unread, 0, "select marks locally read")
conv.draft = "draft stays"
local countBeforeSend = #conv.messages
eq(actual.Send("draft stays"), true, "Core routes group send to explicit transport")
eq(conv.draft, "draft stays", "transport does not clear draft on submission")
eq(#conv.messages, countBeforeSend, "no optimistic success record")
eq(calls[#calls][2], clubId, "Core routed correct opaque club ID")
messages[#messages + 1] = message(13, "draft stays", true)
local beforeSequence = live.GetLiveSequence()
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[4].messageId)
eq(conv.messages[4].communityLive, true, "native self echo marked live")
check(conv.messages[4].communitySequence > beforeSequence, "echo is newer than UI send baseline")
eq(conv.unread, 0, "self echo not unread")
live.Open(id)
eq(conv.messages[4].communityLive, false, "history overlap clears transient confirmation")
eq(conv.messages[4].communitySequence, nil, "history overlap cannot reconfirm future send")
actual.ClearSelected()
eq(#conv.messages, 0, "local history cleared")
eq(conv.communityClearBefore.position, 13, "clear waterline records latest server position")
live.Open(id)
eq(#conv.messages, 0, "automatic old history does not resurrect cleared content")
messages[#messages + 1] = message(14, "after clear", false)
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, streamId, messages[5].messageId)
eq(#conv.messages, 1, "new live after clear accepted")
eq(conv.messages[1].clubPosition, 14, "new message after clear uses correct position")
local previousDraft = conv.draft
db = actual.InitDB(db)
conv = db.conversations[id]
check(conv ~= nil, "club survives reload")
eq(conv.available, false, "saved membership not trusted after reload")
eq(conv.draft, previousDraft, "group draft survives reload")
eq(#conv.messages, 1, "group history survives reload")
eq(conv.messages[1].communityLive, nil, "live marker not restored")
eq(conv.messages[1].communitySequence, nil, "live sequence not restored")
eq(conv.communityClearBefore.position, 13, "clear waterline survives reload")
live.Refresh()
eq(conv.available, true, "fresh membership restores sending after reload")
messages = {}
for i = 1, 75 do messages[i] = message(i, "retained " .. i, false) end
live.Open(id)
eq(#conv.messages, 60, "actual Core bounds community history to 60")
eq(conv.messages[1].clubPosition, 16, "oldest retained history matches most recent 60")
eq(conv.messages[60].clubPosition, 75, "newest retained history survives trim")
live.Open(id)
eq(#conv.messages, 60, "overlapping bounded history does not duplicate")
clubs = {}; live.Refresh()
eq(conv.available, false, "left group retained as unavailable")
eq(conv.draft, previousDraft, "leaving group retains draft")
local beforeLeaveSend = sendCount
eq(actual.Send("cannot send"), false, "Core refuses group after leave")
eq(sendCount, beforeLeaveSend, "leave blocks native API call")

-- Many joined streams must not prune ordinary chats during passive refresh.
clubs = { { clubId = clubId, name = "角色社区", clubType = 1, memberCount = 2 } }
streams = {}
for i = 1, 35 do streams[i] = { streamId = i, name = "频道" .. i, leadersAndModeratorsOnly = false } end
db = actual.InitDB(nil)
local private = actual.OpenWhisper("朋友-角色")
private.draft = ""
actual.HandleEvent("CHAT_MSG_WHISPER", "keep my private history", "朋友-角色")
actual.Select("group")
local privateID, privateMessage = private.id, private.messages[1]
local many = live.Refresh()
eq(#many, 35, "all joined streams remain browsable")
eq(#actual.GetConversations(), 5, "35 discovered streams do not consume dynamic slots")
eq(db.conversations[privateID], private, "private conversation survives large refresh")
eq(private.messages[1], privateMessage, "private history identity preserved")
live.Refresh(); live.Refresh()
eq(#actual.GetConversations(), 5, "repeated group refresh does not churn active list")
local unopened = "club:" .. clubId .. ":2"
live.HandleEvent("CLUB_MESSAGE_HISTORY_RECEIVED", clubId, 2, {})
eq(db.conversations[unopened], nil, "background native history does not admit inactive group")
live.HandleEvent("CLUB_MESSAGE_ADDED", clubId, 2, messages[#messages].messageId)
check(db.conversations[unopened] ~= nil, "valid live message admits its own group")
eq(#actual.GetConversations(), 6, "only the live group consumes a slot")
eq(db.conversations[privateID], private, "live admission preserves other history below capacity")
local explicit = "club:" .. clubId .. ":3"
eq(live.Open(explicit), true, "explicit open admits only selected stream")
eq(#actual.GetConversations(), 7, "only selected group admitted on open")
live.Refresh()
eq(#actual.GetConversations(), 7, "subsequent refresh leaves active set stable")

print("Chat communities: " .. checks .. " checks passed")
