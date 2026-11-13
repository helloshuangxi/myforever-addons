local NS, checks = {}, 0
local function check(value, message) checks=checks+1; assert(value, message) end
local secret=setmetatable({}, {__index=function() error("secret access") end, __tostring=function() error("secret coercion") end})
issecretvalue=function(value) return rawequal(value,secret) end
GetServerTime=function() return 100 end
UnitGUID=function() return "Player-95-ABCD" end
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Core.lua"))("MyForeverChat",NS)
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/History.lua"))("MyForeverChat",NS)
local target,id="Friend#1234","bnet:friend#1234"
local function source(text, count)
    local messages={}
    for i=1,(count or 2) do messages[i]={id="msg:"..i,text=text,author="Owner",outgoing=i%2==1,time=20,
        profile={guid="Player-95-ABCD",classToken="MAGE"}} end
    return {conversations={[id]={kind="bnet",target=target,title="Friend",messages=messages,draft="local draft",muted=true,unread=1},
        ["whisper:character"]={kind="whisper",target="Character",messages={{id="msg:9",text="character only",author="Character",time=10}}}}}
end
local first=source("same legitimate repeated message")
NS.InitDB(first)
local account,attached=NS.AttachAccountHistory(nil,NS.GetHistoryOwnerKey())
check(attached and NS.historyOwner=="player:Player-95-ABCD","owner is stable player GUID")
check(#account.conversations[id].messages==2,"first owner imports both legitimate identical texts")
check(account.conversations[id].messages[1].id~=account.conversations[id].messages[2].id,"imported repeats have different durable IDs")
check(account.conversations[id].messages[1].historyOwner=="player:Player-95-ABCD","origin owner retained")
check(account.conversations[id].messages[1].profile.guid=="Player-95-ABCD","original sender profile retained")
check(account.conversations["whisper:character"]==nil,"character whisper never enters shared history")
check(account.conversations[id].draft==nil and account.conversations[id].muted==nil,"only message history is shared")
check(NS.db.conversations[id].draft=="local draft" and NS.db.conversations[id].muted,"local draft and mute survive binding")
check(NS.db.accountHistoryMigrated,"local database records completed migration")
local oldID=account.conversations[id].messages[1].id
NS.InitDB(first); account=NS.AttachAccountHistory(account,"player:Player-95-ABCD")
check(#account.conversations[id].messages==2 and account.conversations[id].messages[1].id==oldID,"repeat import of same owner is idempotent")
local second=source("same legitimate repeated message")
second.conversations[id].draft="second owner draft";second.conversations[id].muted=false
NS.InitDB(second); account=NS.AttachAccountHistory(account,"player:Player-95-DCBA")
check(#account.conversations[id].messages==4,"same per-character message IDs do not collide across owners")
check(NS.db.conversations[id].draft=="second owner draft" and not NS.db.conversations[id].muted,"other character has independent draft and preferences")
check(NS.db.conversations[id].messages==account.conversations[id].messages,"runtime shares just the canonical message list")
NS.GetBattleNetContactByID=function() return {target=target,title="Friend",profile={}} end
NS.HandleEvent("CHAT_MSG_BN_WHISPER","new reply","Friend",nil,nil,nil,nil,nil,nil,nil,nil,555,nil,77)
check(#account.conversations[id].messages==5,"fresh event is immediately added to account history")
check(account.conversations[id].messages[5].historyOwner=="player:Player-95-DCBA","new event retains current receiving character identity")
local latestID=account.conversations[id].messages[5].id
NS.InitDB(NS.db); account=NS.AttachAccountHistory(account,"player:Player-95-DCBA")
check(#account.conversations[id].messages==5 and account.conversations[id].messages[5].id==latestID,"reload does not import copies of shared messages again")

NS.Select(id); NS.ClearSelected()
check(#account.conversations[id].messages==0 and account.tombstones[id],"clear writes shared tombstone and clears history")
NS.InitDB(source("old third-owner copy")); account=NS.AttachAccountHistory(account,"player:Player-95-AAAA")
check(#account.conversations[id].messages==0,"unvisited character cannot resurrect cleared history")
NS.HandleEvent("CHAT_MSG_BN_WHISPER","new after clear","Friend",nil,nil,nil,nil,nil,nil,nil,nil,556,nil,77)
check(#account.conversations[id].messages==1,"fresh real message after clear remains allowed")
NS.DeleteConversation(id,true)
check(account.conversations[id]==nil and account.tombstones[id],"confirmed deletion removes account history and retains tombstone")
NS.InitDB(source("fourth old copy")); account=NS.AttachAccountHistory(account,"player:Player-95-BBBB")
check(account.conversations[id]==nil and #NS.db.conversations[id].messages==0,"old owner copy cannot revive deleted shared history")
check(NS.db.conversations[id].draft=="local draft","shared deletion preserves another character's independent draft")
NS.HandleEvent("CHAT_MSG_BN_WHISPER","new after delete","Friend",nil,nil,nil,nil,nil,nil,nil,nil,557,nil,77)
check(#account.conversations[id].messages==1,"new incoming after deletion starts a new valid conversation")
NS.CloseConversation(id,true)
check(account.conversations[id] and #account.conversations[id].messages==1,"closing active view does not erase shared archive")
NS.GetBattleNetContact=function() return {title="Friend",profile={}} end
local opened=NS.OpenBattleNet(target)
check(opened and #opened.messages==1,"reopening closed contact restores canonical history")

local seed=NS.NormalizeAccountHistory({pendingImports={["player:Player-95-CCCC"]=source("seed")}})
check(#seed.conversations[id].messages==2 and seed.pendingImports==nil,"private recovery seed is consumed into canonical data")
NS.ImportAccountHistory(seed,"player:Player-95-CCCC",source("seed"))
check(#seed.conversations[id].messages==2,"seed repeated after first import is inert")
local normalized=NS.NormalizeAccountHistory(seed)
check(#normalized.conversations[id].messages==2 and normalized.importedOwners["player:Player-95-CCCC"],"migration markers persist through serialization normalization")
local invalid=NS.NormalizeAccountHistory({conversations=secret,tombstones=secret,importedOwners=secret,pendingImports=secret,nextMessageID=secret})
check(next(invalid.conversations)==nil and invalid.nextMessageID==0,"secret account fields are ignored without comparison or coercion")
local malformed=NS.NormalizeAccountHistory({conversations={secret,{kind="whisper",target=target},{kind="bnet",target=secret},
    {kind="bnet",target=target,messages={{text=secret,author="x"},{text="x",author=secret}}}},
    tombstones={[id]=secret},importedOwners={["player:Player-95-CCCC"]=secret},pendingImports={bad=source("bad")}})
check(#malformed.conversations[id].messages==0 and not malformed.tombstones[id],"malformed and restricted records do not become history")
NS.InitDB(source("unknown owner"));local untouched=NS.db
local returned,ok=NS.AttachAccountHistory(seed,nil)
check(returned==seed and not ok and NS.db==untouched and not NS.db.accountHistoryMigrated,"unknown owner never imports into shared unknown identity")
UnitGUID=function() return secret end
check(NS.GetHistoryOwnerKey()==nil,"restricted player GUID has no fallback owner")
UnitGUID=function() error("not ready") end
check(NS.GetHistoryOwnerKey()==nil,"uninitialized player GUID has no fallback owner")
local many=NS.NormalizeAccountHistory({pendingImports={["player:Player-95-EEEE"]=source("repeated",510)}})
check(#many.conversations[id].messages==500,"shared contact retention is explicitly bounded at 500")
local archiveSource={conversations={}}
for i=1,50 do
    local tag="Archived"..i.."#1234"
    archiveSource.conversations["bnet:archived"..i.."#1234"]={kind="bnet",target=tag,messages={{id="msg:1",text="archive",author="Owner",time=i}}}
end
local archive=NS.NormalizeAccountHistory({pendingImports={["player:Player-95-FFFF"]=archiveSource}})
NS.InitDB({}); archive=NS.AttachAccountHistory(archive,"player:Player-95-ABCD")
check(#NS.GetConversations()==4,"account archive cannot bypass active conversation capacity")
for i=1,50 do NS.OpenBattleNet("Archived"..i.."#1234") end
check(#NS.GetConversations()==34,"opening archived contacts still observes thirty dynamic conversations")
local archiveCount=0;for _ in pairs(archive.conversations) do archiveCount=archiveCount+1 end
check(archiveCount==50,"active-view pruning preserves all account archives")
local closing=NS.GetSelected().id;NS.CloseConversation(closing,true)
NS.InitDB(NS.db);archive=NS.AttachAccountHistory(archive,"player:Player-95-ABCD")
check(NS.db.conversations[closing]==nil,"closed view stays closed after reload")
NS.GetBattleNetContact=nil
check(NS.OpenBattleNet("Archived50#1234")~=nil,"stored history can open read-only when current friend lookup is unavailable")
check(not NS.Send("cannot bypass recipient lookup"),"opening an archive cannot bypass fresh recipient validation")

-- A temporarily unavailable GUID at PLAYER_LOGIN must not merge characters;
-- the normal entering-world event retries safely once identity is available.
local events={}
function events:RegisterEvent() end
function events:SetScript(_,callback) self.callback=callback end
CreateFrame=function() return events end
SlashCmdList={}
for _,name in ipairs({"SyncChannels","CaptureTarget","RefreshEmotePacks","BuildUI","InstallNativeClicks","InstallItemLinkBridge","InstallQuickReplyShortcut","RefreshUI"}) do NS[name]=function() end end
MyForeverChatDB=source("late identity");MyForeverChatAccountDB=nil
UnitGUID=function() return nil end
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Main.lua"))("MyForeverChat",NS)
events.callback(events,"ADDON_LOADED","MyForeverChat");events.callback(events,"PLAYER_LOGIN")
check(NS.accountHistory==nil and not MyForeverChatDB.accountHistoryMigrated,"login without GUID keeps local records untouched")
UnitGUID=function() return "Player-95-1234" end
events.callback(events,"PLAYER_ENTERING_WORLD")
check(NS.accountHistory==MyForeverChatAccountDB and #MyForeverChatAccountDB.conversations[id].messages==2,"entering world retries delayed identity and imports once")
events.callback(events,"PLAYER_ENTERING_WORLD")
check(#MyForeverChatAccountDB.conversations[id].messages==2,"repeated world entry cannot reimport shared history")
print("chat_history_test: "..checks.." checks passed")
