local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "check") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function check(value, label) checks = checks + 1; assert(value, label) end
local secret = setmetatable({ secret=true }, {
    __tostring=function() error("secret coercion") end,
    __eq=function() error("secret comparison") end,
})
issecretvalue=function(value) return type(value)=="table" and rawget(value,"secret")==true end
local now, notifications, upserts, sends = 100, 0, 0, 0
GetTime=function() return now end
GetServerTime=function() return 5000+now end
local target = {name="Éloïse-龙 骑",guid="Player-Other",exists=true,player=true,self=false,
    className="牧师",classToken="PRIEST",level=23,raceName="人类",raceToken="Human",sex=3}
UnitExists=function() return target.exists end
UnitIsPlayer=function() return target.player end
UnitIsUnit=function() return target.self end
NameUtil={GetUnmodifiedUnitFullName=function() return target.name end}
UnitGUID=function() return target.guid end
UnitClass=function() return target.className,target.classToken end
UnitLevel=function() return target.level end
UnitRace=function() return target.raceName,target.raceToken end
UnitSex=function() return target.sex end
C_PlayerInfo={GetDisplayID=function() error("local-player-only API must not be used for another player") end}
local contacts, selected = {}, {id="group",kind="group",draft="保留原草稿"}
local NS={
    NotifyChanged=function() notifications=notifications+1 end,
    GetSelected=function() return selected end,
    Select=function() error("capture must not select") end,
    Send=function() sends=sends+1 end,
    UpsertContact=function(name,profile,passive)
        check(passive==true,"target discovery uses passive admission")
        upserts=upserts+1
        local conv=contacts[name] or {id="whisper:"..name,kind="whisper",target=name,messages={},unread=0,draft=""}
        conv.profile=profile; contacts[name]=conv
        return conv
    end,
}
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Profiles.lua"))("MyForeverChat",NS)
local first=NS.CaptureTarget()
eq(first.target,"Éloïse-龙 骑","complete UTF-8 surname retained")
eq(first.profile.classToken,"PRIEST","class token")
eq(first.profile.className,"牧师","localized class")
eq(first.profile.level,23,"visible level")
eq(first.profile.raceName,"人类","race")
eq(first.profile.sex,3,"sex")
eq(first.profile.guid,"Player-Other","GUID")
eq(first.profile.seenAt,5100,"public time captured")
eq(first.profile.displayID,nil,"local player's display ID not misused")
eq(#first.messages,0,"discovery needs no message")
eq(selected.id,"group","automatic discovery preserves selected conversation")
eq(selected.draft,"保留原草稿","automatic discovery preserves draft")
eq(sends,0,"capture sends nothing")
eq(NS.ResolvePortraitUnit(first),"target","current exact target portrait available")
target.guid="Player-Impostor"
eq(NS.ResolvePortraitUnit(first),nil,"same name with different GUID cannot reuse portrait")
target.guid="Player-Other"; target.name="另一个人"
eq(NS.ResolvePortraitUnit(first),nil,"different target name cannot reuse portrait")
target.name="Éloïse-龙 骑"; target.guid=secret
eq(NS.ResolvePortraitUnit(first),nil,"secret target GUID rejected for portrait")
target.guid="Player-Other"
target.exists=false
eq(NS.CaptureTarget(),nil,"missing target ignored")
target.exists=true; target.player=false
eq(NS.CaptureTarget(),nil,"NPC ignored")
target.player=true; target.self=true
eq(NS.CaptureTarget(),nil,"self ignored")
target.self=secret
eq(NS.CaptureTarget(),nil,"secret identity ignored")
target.self=false; target.name=secret
eq(NS.CaptureTarget(),nil,"secret full name ignored")
target.name="全名-玩家"
local nameAPI=NameUtil.GetUnmodifiedUnitFullName
NameUtil.GetUnmodifiedUnitFullName=function() error("restricted") end
eq(NS.CaptureTarget(),nil,"name wrapper error caught")
NameUtil.GetUnmodifiedUnitFullName=nameAPI
target.className=secret; target.classToken=secret; target.level=-1; target.sex=secret; target.raceName=secret
local unknown=NS.CaptureTarget()
eq(unknown.profile.className,nil,"secret class label omitted")
eq(unknown.profile.classToken,nil,"secret class token omitted")
eq(unknown.profile.level,nil,"unknown level omitted")
eq(unknown.profile.sex,nil,"secret sex omitted")
eq(unknown.profile.raceName,nil,"secret race omitted")
target.className="职业未知"; target.classToken="../../Injected"; target.level=0/0
unknown=NS.CaptureTarget()
eq(unknown.profile.classToken,nil,"unrecognized class cannot inject icon resource")
eq(unknown.profile.level,nil,"NaN level omitted")
local before=upserts
UnitIsUnit=nil
eq(NS.CaptureTarget(),nil,"missing identity API does not guess")
eq(upserts,before,"invalid captures never add contact")
UnitIsUnit=function() return false end
target.className="牧师"; target.classToken="PRIEST"; target.level=24; target.sex=3; target.raceName="人类"
local updated=NS.CaptureTarget()
eq(updated,unknown,"same complete name updates same contact")
eq(updated.profile.level,24,"level refresh")
CLASS_ICON_TCOORDS={PRIEST={0.5,0.75,0.25,0.5}}
local coords=NS.ClassIconCoords("PRIEST")
eq(coords[1],0.5,"known class icon coordinates")
coords[1]=0
eq(CLASS_ICON_TCOORDS.PRIEST[1],0.5,"coordinate return is an independent copy")
eq(NS.ClassIconCoords("Injected"),nil,"unknown class icon omitted")
CLASS_ICON_TCOORDS.PRIEST[1]=secret
eq(NS.ClassIconCoords("PRIEST"),nil,"secret icon coordinate omitted")
CLASS_ICON_TCOORDS.PRIEST[1]=0.5

local friends, requests, timers = {}, {}, {}
local function getFriend(name)
    for _,info in ipairs(friends) do if info.name==name then return info end end
end
C_FriendList={
    GetFriendInfo=getFriend,
    GetNumFriends=function() return #friends end,
    GetFriendInfoByIndex=function(index) return friends[index] end,
    AddFriend=function(name) requests[#requests+1]=name end,
}
C_Timer={After=function(delay,fn) eq(delay,8,"friend request timeout"); timers[#timers+1]=fn end}
eq(NS.GetFriendState(selected),"unavailable","fixed channel cannot add friend")
eq(NS.AddSelectedFriend(),false,"no private target refused")
selected=updated
eq(NS.GetFriendState(selected),"none","not a known friend")
local ok,note=NS.AddSelectedFriend()
eq(ok,true,"button submits friend request")
eq(requests[1],selected.target,"friend request uses full exact target")
check(note:find("等待",1,true),"submission does not claim success")
eq(NS.GetFriendState(selected),"pending","request pending until actual friend list")
eq(NS.AddSelectedFriend(),false,"duplicate pending request refused")
eq(#requests,1,"duplicate does not send a second request")
friends[1]={name=selected.target,guid=selected.profile.guid,level=24}
eq(NS.GetFriendState(selected),"friend","real friend list confirms success")
eq(NS.AddSelectedFriend(),false,"existing friend not re-added")
eq(#requests,1,"confirmed friend no duplicate request")
friends={}
now=109
eq(NS.GetFriendState(selected),"none","pending removed after confirmation")
eq(NS.AddSelectedFriend(),true,"new request can be submitted")
now=118
eq(NS.GetFriendState(selected),"none","unconfirmed request expires without declaring friendship")
eq(#requests,2,"expiry never automatically retries")
eq(NS.AddSelectedFriend(),true,"user may manually retry")
local newerCount=#requests
timers[1]()
eq(NS.GetFriendState(selected),"pending","stale timeout cannot clear new request")
eq(#requests,newerCount,"stale timeout never sends")
timers[#timers]()
eq(NS.GetFriendState(selected),"none","current timeout clears request")
local addAPI=C_FriendList.AddFriend
C_FriendList.AddFriend=function() error("not allowed") end
eq(NS.AddSelectedFriend(),false,"AddFriend exception surfaced")
eq(NS.GetFriendState(selected),"none","rejected request leaves no pending state")
C_FriendList.AddFriend=addAPI
C_FriendList.GetFriendInfo=function() return {name="全名",guid=selected.profile.guid} end
eq(NS.GetFriendState(selected),"none","fuzzy shorter friend name not accepted even with GUID")
C_FriendList.GetFriendInfo=function() return {name=selected.target,guid="Wrong-GUID"} end
eq(NS.GetFriendState(selected),"none","same name conflicting GUID not accepted")
C_FriendList.GetFriendInfo=function() return secret end
friends={{name=selected.target,guid=selected.profile.guid}}
eq(NS.GetFriendState(selected),"friend","indexed public friend list fallback confirms")
friends={}
C_FriendList.GetFriendInfo=getFriend
local original=C_FriendList
C_FriendList={}
eq(NS.GetFriendState(selected),"unavailable","missing API disables friend control")
eq(NS.AddSelectedFriend(),false,"missing API does not guess success")
C_FriendList=original
C_FriendList.IsLegacyFriendSystemEnabled=function() return false end
eq(NS.GetFriendState(selected),"unavailable","disabled legacy friend system cannot claim friend support")
eq(NS.AddSelectedFriend(),false,"disabled friend system does not submit")
C_FriendList.IsLegacyFriendSystemEnabled=nil
C_FriendList.GetFriendInfo=function() error("restricted") end
C_FriendList.GetNumFriends=function() error("restricted") end
eq(NS.GetFriendState(selected),"unavailable","restricted friend list treated unavailable")
eq(sends,0,"profile and friend code never sends chat")
check(notifications>0,"friend state transitions notify UI")

-- Verify discovery against the real Core admission/storage contract as well.
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Core.lua"))("MyForeverChat",NS)
NS.InitDB(nil)
local originalSelected=NS.GetSelected()
originalSelected.draft="不要挪动这份草稿"
target.name="叶 落-明月"; target.guid="Player-Other"; target.level=25
target.classToken="PRIEST"; target.className="牧师"; target.raceName="人类"; target.raceToken="Human"; target.sex=3
local discovered=NS.CaptureTarget()
check(discovered~=nil,"real Core remembers selected player without messaging")
eq(NS.GetSelected(),originalSelected,"real Core passive discovery does not select")
eq(originalSelected.draft,"不要挪动这份草稿","real Core preserves original draft")
eq(NS.db.conversations[discovered.id],nil,"real Core does not create a conversation")
eq(discovered.messages,nil,"real Core does not fabricate messages")
eq(discovered.unread,nil,"real Core discovery does not fabricate unread")
eq(discovered.profile.level,25,"real Core stores player profile")
eq(discovered.profile.classToken,"PRIEST","real Core stores class")
target.level=26
local refreshed=NS.CaptureTarget()
eq(refreshed.id,discovered.id,"real Core updates same recent identity")
discovered=refreshed
eq(discovered.profile.level,26,"real Core refreshes newer level")
local restored=NS.InitDB(NS.db)
eq(restored.conversations[discovered.id],nil,"saved recent person remains independent of conversations")
eq(restored.recentPeople[1].profile.level,26,"profile survives saved variable normalization")
eq(NS.ResolvePortraitUnit(restored.recentPeople[1]),"target","restored identity still supports current portrait")
local selectedBefore=NS.GetSelected()
local lastIncoming=NS.lastIncoming
local lookupCalls=0
GetPlayerInfoByGUID=function(guid)
    lookupCalls=lookupCalls+1
    eq(guid,"Player-Other","whisper lookup uses exact public GUID")
    return "法师","MAGE","侏儒","Gnome",2,"返回的短名","不应拼接的服务器",42
end
local opened=NS.OpenWhisper(discovered.target)
eq(opened.profile.level,26,"explicit open copies recent metadata")
NS.Select(selectedBefore.id)
local enriched=NS.CaptureWhisperProfile("叶 落-明月","Player-Other")
eq(enriched.target,"叶 落-明月","GUID details never rebuild original full author")
eq(enriched.profile.classToken,"MAGE","GUID supplies English class")
eq(enriched.profile.className,"法师","GUID supplies localized class")
eq(enriched.profile.level,42,"eighth GUID result supplies level")
eq(enriched.profile.raceName,"侏儒","GUID supplies race")
eq(NS.GetSelected(),selectedBefore,"whisper enrichment preserves selected conversation")
eq(NS.lastIncoming,lastIncoming,"whisper enrichment does not generate incoming notification")
local beforeLookup=lookupCalls
eq(NS.CaptureWhisperProfile("陌生人-尚无会话","Player-Other"),nil,"unknown contact is not created by GUID lookup")
eq(lookupCalls,beforeLookup,"unknown author does not trigger lookup")
eq(NS.CaptureWhisperProfile(secret,"Player-Other"),nil,"secret whisper author refused")
eq(NS.CaptureWhisperProfile("叶 落-明月",secret),nil,"secret whisper GUID refused")
GetPlayerInfoByGUID=nil
eq(NS.CaptureWhisperProfile("叶 落-明月","Player-Other"),nil,"missing GUID getter leaves existing data alone")
GetPlayerInfoByGUID=function() error("restricted") end
eq(NS.CaptureWhisperProfile("叶 落-明月","Player-Other"),nil,"restricted GUID getter safely refused")
GetPlayerInfoByGUID=function() return secret,secret,secret,secret,secret,secret,secret,secret end
eq(NS.CaptureWhisperProfile("叶 落-明月","Player-Other"),nil,"all-secret GUID details never enter saved profile")
eq(enriched.profile.level,42,"unavailable lookup preserves prior public level")
GetPlayerInfoByGUID=function() return secret,"PRIEST",secret,secret,secret,secret,secret,43 end
eq(NS.CaptureWhisperProfile("叶 落-明月","Player-Other"),enriched,"public partial GUID fields can refresh known contact")
eq(enriched.profile.classToken,"PRIEST","public class survives restricted localized fields")
eq(enriched.profile.level,43,"public eighth result survives restricted other fields")

-- Presence only uses current friend or exact unit state.
local contact={kind="whisper",target="完整 玩家-家族",profile={guid="Player-Contact"}}
local friend, friendListEnabled, unitReads, tokenReads=nil,true,0,0
C_FriendList={
    GetFriendInfo=function() return friend end,
    IsLegacyFriendSystemEnabled=function() return friendListEnabled end,
}
local units={}
UnitExists=function(unit) return units[unit]~=nil end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player==true end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
NameUtil.GetUnmodifiedUnitFullName=function(unit) return units[unit] and units[unit].name end
UnitIsConnected=function(unit) unitReads=unitReads+1; return units[unit] and units[unit].connected end
local resolvedUnit
UnitTokenFromGUID=function(guid)
    tokenReads=tokenReads+1
    eq(guid,"Player-Contact","visible lookup uses known GUID")
    return resolvedUnit
end
eq(NS.GetContactPresence({kind="group"}),"unknown","channel cannot have presence")
friend={name=contact.target,guid="Player-Contact",connected=true}
eq(NS.GetContactPresence(contact),"online","exact friend can report online")
friend.connected=false
eq(NS.GetContactPresence(contact),"offline","exact friend can report offline")
eq(unitReads,0,"definite friend status takes priority over units")
friend.connected=secret
eq(NS.GetContactPresence(contact),"unknown","secret friend status never maps to offline")
friend.connected="false"
eq(NS.GetContactPresence(contact),"unknown","friend connection must be a boolean")
friend.guid=secret; friend.connected=false
eq(NS.GetContactPresence(contact),"unknown","secret friend identity cannot establish offline")
friend.guid="Player-Impostor"
eq(NS.GetContactPresence(contact),"unknown","same-name friend with conflicting GUID ignored")
friend.guid="Player-Contact"; friend.name="完整 玩家"
eq(NS.GetContactPresence(contact),"unknown","short friend name ignored")
friend.name=contact.target; friend.connected=true; friendListEnabled=false
eq(NS.GetContactPresence(contact),"unknown","disabled friend system does not expose stale online status")
friendListEnabled=true; friend=nil
units.target={player=true,name=contact.target,guid="Player-Contact",connected=true}
eq(NS.GetContactPresence(contact),"online","exact selected non-friend can report online")
units.target.connected=false
eq(NS.GetContactPresence(contact),"offline","exact selected non-friend with public disconnected value")
units.target.connected=secret
eq(NS.GetContactPresence(contact),"unknown","secret unit connection is unknown")
units.target.connected=true; units.target.guid="Player-Impostor"
eq(NS.GetContactPresence(contact),"unknown","same-name selected unit with conflicting GUID ignored")
units.target=nil
eq(NS.GetContactPresence(contact),"unknown","leaving view clears live state")
resolvedUnit="party2"
units.party2={player=true,name=contact.target,guid="Player-Contact",connected=true}
eq(NS.GetContactPresence(contact),"online","known GUID resolves current teammate online state")
units.party2.connected=false
eq(NS.GetContactPresence(contact),"offline","known GUID resolves current teammate disconnected state")
units.party2.guid="Player-Impostor"
eq(NS.GetContactPresence(contact),"unknown","reused unit token with mismatched GUID ignored")
units.party2.guid="Player-Contact"; units.party2.name="另一个人-家族"
eq(NS.GetContactPresence(contact),"unknown","resolved unit must also match full name")
resolvedUnit=secret
eq(NS.GetContactPresence(contact),"unknown","secret unit token cannot establish presence")
local beforeTokenReads=tokenReads
contact.profile={}
eq(NS.GetContactPresence(contact),"unknown","absent friend and known GUID remains unknown")
eq(tokenReads,beforeTokenReads,"unknown identity never queries a guessed GUID")
eq(contact.presence,nil,"presence is computed live and never persisted")

-- Roster rows and recent players are independent of stored conversations.
local directory=NS.InitDB({})
LOCALIZED_CLASS_NAMES_MALE={ MAGE="法师", PRIEST="牧师" }
C_FriendList={ GetNumFriends=function() return 2 end, GetFriendInfoByIndex=function(index)
    if index==1 then return { name="游戏-好友", connected=true, guid="Player-friend", className="牧师", level=28 } end
    return secret
end }
local firstAccount={ bnetAccountID=41, battleTag="夜空#1234", accountName="同名",
    gameAccountInfo={ isOnline=true, className="法师", raceName="侏儒", characterLevel=30 } }
local otherAccount={ bnetAccountID=51, battleTag="暖光#4321", accountName="同名", gameAccountInfo={ isOnline=false } }
local titleFriend={ bnetAccountID=61, battleTag="", accountName="不用于发送的昵称", gameAccountInfo={ isOnline=true } }
local accounts={ firstAccount, otherAccount, titleFriend, { bnetAccountID=secret, battleTag="不可用#0101" } }
BNGetNumFriends=function() return #accounts end
local platformOnline=true
BNConnected=function() return platformOnline end
local accountSends={}
C_BattleNet={
    GetFriendAccountInfo=function(index) return accounts[index] end,
    GetAccountInfoByID=function(id)
        for _, item in ipairs(accounts) do
            if not issecretvalue(item.bnetAccountID) and item.bnetAccountID==id then return item end
        end
    end,
    GetDefaultTitleWhisperTarget=function(id) if id==61 then return "游戏-新好友" end end,
    SendWhisper=function(id, text) accountSends[#accountSends+1]={ id=id, text=text }; return true end,
}
local allies={
    { characterData={ fullName="新近-队友", guid="Player-ally", level=31, classID=8 }, stateData={ isOnline=false } },
    { characterData={ fullName="原有-好友", guid="Player-old", level=40 }, stateData={ isOnline=true, isConvertedLegacyFriend=true } },
}
C_RecentAllies={ GetRecentAllies=function() return allies end, GetRecentAllyByFullName=function(name)
    for _, item in ipairs(allies) do if item.characterData.fullName==name then return item end end
end }
local gameRequests, recentRequests=0,0
local legacyEnabled, recentEnabled, recentSupported=true,true,true
C_FriendList.IsLegacyFriendSystemEnabled=function() return legacyEnabled end
C_FriendList.ShowFriends=function() gameRequests=gameRequests+1 end
C_RecentAllies.IsSystemEnabled=function() return recentEnabled end
C_RecentAllies.IsSystemSupported=function() return recentSupported end
C_RecentAllies.TryRequestRecentAlliesData=function()
    recentRequests=recentRequests+1
    error("restricted native request must never be attempted, even inside pcall")
end
NS.RequestContactLists()
eq(gameRequests,1,"explicit contact view requests legacy game friends")
eq(recentRequests,0,"supported and enabled recent allies never invoke restricted refresh")
legacyEnabled, recentEnabled=false,false
NS.RequestContactLists()
eq(gameRequests,1,"disabled legacy friends are not requested")
eq(recentRequests,0,"disabled recent allies are not requested")
legacyEnabled, recentEnabled, recentSupported=true,true,false
NS.RequestContactLists()
eq(recentRequests,0,"unsupported recent allies are not requested")
recentSupported=true
GetClassInfo=function(id) if id==8 then return "法师", "MAGE" end end
NS.UpsertContact("新近-队友", { guid="Player-ally", raceName="人类" }, true)
NS.UpsertContact("路过-玩家", { level=15 }, true)
local gameFriends, bnFriends, recent=NS.GetContactLists()
eq(#gameFriends,3,"game directory includes legacy, title, and converted friends")
eq(gameFriends[1].profile.classToken,"PRIEST","game friend metadata yields class icon token")
eq(gameFriends[2].target,"游戏-新好友","native title-friend target stays a character whisper")
eq(gameFriends[3].target,"原有-好友","native converted friend remains in game directory")
eq(#bnFriends,2,"platform directory includes only readable stable identities")
eq(bnFriends[1].title,bnFriends[2].title,"same account display names can coexist")
check(bnFriends[1].id~=bnFriends[2].id,"BattleTags separate same-name accounts")
eq(bnFriends[1].profile.classToken,"MAGE","platform row can show game profile")
eq(bnFriends[2].presence,"offline","platform row exposes definite offline status")
eq(NS.GetBattleNetPresenceMap()[bnFriends[1].id],"online","one roster scan can provide platform presence")
eq(#recent,3,"recent list deduplicates native and plugin observations")
eq(recent[1].target,"路过-玩家","recent list shows selected players separately")
eq(recent[2].profile.raceName,"人类","native ally metadata preserves local known race")
eq(recent[2].profile.classToken,"MAGE","native ally metadata fills missing local class")
eq(recent[2].presence,"offline","recent ally presence comes from native data")
eq(recentRequests,0,"cached ally metadata and presence remain available without a restricted refresh")
eq(#NS.GetConversations(),4,"reading all contact lists creates no conversations")
eq(NS.lastIncoming,nil,"reading roster does not emit notifications")

local bn=NS.OpenBattleNet(firstAccount.battleTag)
eq(NS.GetSelected(),bn,"explicit platform opening selects a conversation")
eq(bn.accountID,nil,"session account IDs are not persisted in conversations")
firstAccount.bnetAccountID=42
eq(NS.Send("你好，通行证好友"),true,"platform send submits through native API")
eq(accountSends[1].id,42,"platform send resolves current account ID after rotation")
eq(#bn.messages,0,"platform send waits for actual game echo")
local function BNEvent(event, text, id, lineID)
    return NS.HandleEvent(event, text, "|Kq0|k", "", "", "", "", 0, 0, "", 0, lineID, "", id)
end
eq(BNEvent("CHAT_MSG_BN_WHISPER_INFORM","你好，通行证好友",42,81),true,"platform echo is accepted")
eq(#bn.messages,1,"platform echo appends only one message")
eq(bn.messages[1].outgoing,true,"platform echo direction retained")
eq(NS.lastIncoming,nil,"platform echo creates no notification")
eq(BNEvent("CHAT_MSG_BN_WHISPER","另一位好友来信",51,82),true,"incoming platform whisper creates a separate thread")
eq(directory.lastWhisperId,bnFriends[2].id,"recent-reply target supports platform whisper")
eq(NS.lastIncoming.conversationId,bnFriends[2].id,"platform notification uses exact identity")
eq(BNEvent("CHAT_MSG_BN_WHISPER","重复的回调",51,82),false,"platform event IDs deduplicate")
eq(BNEvent("CHAT_MSG_BN_WHISPER","受限账号",secret,83),false,"secret event identity is skipped")
eq(BNEvent("CHAT_MSG_BN_WHISPER","旧账号",41,84),false,"outdated account identity is not guessed")
platformOnline=false
eq(NS.Send("暂时不能发送"),false,"disconnected platform sends are refused")
eq(#accountSends,1,"disconnected send does not route to an unrelated identity")
platformOnline=true
C_BattleNet.SendWhisper=function() return false end
eq(NS.Send("游戏拒绝"),false,"native platform false result is respected")
local saved=NS.InitDB(directory)
eq(saved.conversations[bn.id].messages[1].text,"你好，通行证好友","platform history restores by stable BattleTag")
eq(saved.lastWhisperId,bnFriends[2].id,"platform reply identity survives reload")
eq(NS.TogglePin(bn.id),true,"platform chat can be pinned")
eq(NS.DeleteConversation(bn.id,true),true,"platform chat can be deleted")
eq(saved.conversations[bn.id],nil,"deleted platform chat is removed")

-- Sender metadata is read once per chat event and does not add roster entries.
local messageDB=NS.InitDB({})
local guidReads, rosterRequests=0,0
local sender="发言者-完整名字"
units={}
UnitExists=function(unit) return units[unit]~=nil end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
NameUtil.GetUnmodifiedUnitFullName=function(unit) return units[unit] and units[unit].name end
UnitClass=function(unit) local u=units[unit] or {}; return u.className,u.classToken end
UnitRace=function(unit) local u=units[unit] or {}; return u.raceName,u.raceToken end
UnitLevel=function(unit) return units[unit] and units[unit].level end
UnitSex=function(unit) return units[unit] and units[unit].sex end
UnitTokenFromGUID=function() return nil end
C_FriendList.ShowFriends=function() rosterRequests=rosterRequests+1 end
C_RecentAllies.TryRequestRecentAlliesData=function() rosterRequests=rosterRequests+1 end
GetPlayerInfoByGUID=function(guid)
    guidReads=guidReads+1
    return "牧师","PRIEST","人类","Human",3,"忽略的短名","忽略的服务器",43
end
local speaker=NS.GetMessageProfile(sender,"Player-Speaker")
eq(speaker.guid,"Player-Speaker","message metadata keeps event GUID")
eq(speaker.level,43,"Forever eighth GUID result provides level")
eq(speaker.className,"牧师","message metadata localized class")
eq(speaker.classToken,"PRIEST","message metadata class icon token")
eq(speaker.raceName,"人类","message metadata race")
eq(speaker.sex,3,"message metadata sex")
eq(speaker.name,nil,"API short name cannot replace full author")
local readsBefore=guidReads
eq(next(NS.GetMessageProfile(secret,"Player-Speaker")),nil,"secret sender identity has no metadata")
eq(next(NS.GetMessageProfile(sender,secret)),nil,"secret GUID has no metadata")
eq(next(NS.GetMessageProfile(sender,"Creature-Speaker")),nil,"non-player GUID has no metadata")
eq(next(NS.GetMessageProfile("|Hplayer:bad|h", "Player-Speaker")),nil,"marked-up sender identity refused")
eq(guidReads,readsBefore,"unreadable identity makes no GUID query")
GetPlayerInfoByGUID=function() return secret,secret,secret,secret,secret,secret,secret,secret end
speaker=NS.GetMessageProfile(sender,"Player-Speaker")
eq(speaker.level,nil,"secret level omitted")
eq(speaker.className,nil,"secret class omitted")
eq(speaker.raceName,nil,"secret race omitted")
GetPlayerInfoByGUID=function() error("not readable") end
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,nil,"GUID API error is handled")

local visible={name=sender,guid="Player-Speaker",player=true,level=44,className="法师",classToken="MAGE",raceName="侏儒",raceToken="Gnome",sex=2}
units.party2=visible
UnitTokenFromGUID=function() return "party2" end
speaker=NS.GetMessageProfile(sender,"Player-Speaker")
eq(speaker.level,44,"matching GUID unit supplies missing level")
eq(speaker.classToken,"MAGE","matching unit supplies class")
visible.guid="Player-Other"
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,nil,"same name with mismatching unit GUID ignored")
visible.guid="Player-Speaker"; visible.name="发言者-另一个名字"
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,nil,"same GUID token must also match full author")
visible.name=sender; visible.player=false
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,nil,"non-player unit ignored")
visible.player=true; visible.guid=secret
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,nil,"secret unit identity ignored")
visible.guid="Player-Speaker"; visible.level=-1; visible.classToken=secret; visible.className=secret
speaker=NS.GetMessageProfile(sender,"Player-Speaker")
eq(speaker.level,nil,"unknown unit level omitted")
eq(speaker.classToken,nil,"secret unit class token omitted")
visible.level=45; visible.classToken="MAGE"; visible.className="法师"
UnitTokenFromGUID=function() return secret end
speaker=NS.GetMessageProfile(sender,"Player-Speaker")
eq(speaker.level,45,"party fallback works when GUID token is restricted")
units.party2=nil; units.raid40=visible
UnitTokenFromGUID=nil
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,45,"bounded raid fallback includes final raid member")
units.raid40=nil; units.target=visible
eq(NS.GetMessageProfile(sender,nil).level,45,"exact full target name can resolve absent event GUID")
eq(NS.GetMessageProfile("发言者",nil).level,nil,"short name does not match complete unit identity")
units.target=nil; units.player=visible
eq(NS.GetMessageProfile(sender,"").level,45,"local player fallback supports empty event GUID")
GetPlayerInfoByGUID=function() return "牧师","PRIEST","人类","Human",3,"短名","",43 end
UnitTokenFromGUID=function() return "player" end
eq(NS.GetMessageProfile(sender,"Player-Speaker").level,45,"exact current unit refreshes GUID cached level")
eq(#NS.GetConversations(),4,"sender profile reads do not create chats")
eq(#NS.GetRecentPeople(),0,"sender profile reads do not create recent people")
eq(rosterRequests,0,"sender profile reads do not request rosters")

units={}
eq(NS.HandleEvent("CHAT_MSG_GUILD","来自公会的消息",sender,"","","","",0,0,"",0,900,"Player-Speaker"),true,"real profile helper integrated with incoming public event")
local publicMessage=messageDB.conversations.guild.messages[1]
eq(publicMessage.author,sender,"full public author retained")
eq(publicMessage.profile.level,43,"real public event records GUID level")
eq(publicMessage.profile.classToken,"PRIEST","real public event records GUID class")
eq(#NS.GetConversations(),4,"public event does not open private sender chat")
eq(#NS.GetRecentPeople(),0,"public event does not remember sender as contact")
local messageReload=NS.InitDB(messageDB)
eq(messageReload.conversations.guild.messages[1].profile.level,43,"real sender profile survives saved-variable restoration")
eq(rosterRequests,0,"public sender event never requests rosters")
print("chat_profiles_test: "..checks.." checks passed")
