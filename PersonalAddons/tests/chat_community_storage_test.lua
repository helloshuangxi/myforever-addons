local NS, checks = {}, 0
local function check(value, why) checks=checks+1;assert(value,why) end
local secret=setmetatable({}, {__tostring=function() error("secret coercion") end,__index=function() error("secret access") end})
issecretvalue=function(value) return rawequal(value,secret) end
GetServerTime=function() return 123 end
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Core.lua"))("MyForeverChat",NS)
NS.InitDB({})
local id="club:10:20"
local c=NS.UpsertCommunity({id=id,title="Test community",clubName="Test",streamName="General",available=true})
local function message(token)
    return {id="clubmsg:1000000:1",text=token,author="Member",outgoing=false,time=1,
        clubEpoch=1000000,clubPosition=1,communityNativeContent=true,communityAuthorKnown=true}
end
check(NS.StoreCommunityMessage(id,message("|Kw9|k"),"history"),"fresh native token accepted as display-only content")
check(c.messages[1].communityNativeContent and c.messages[1].text=="|Kw9|k","only current native result retains display permission")
local calls,accept=0,true
NS.Communities={Send=function(target,text)
    calls=calls+1;check(target==id,"submission keeps selected community identity")
    return accept,accept and "submitted" or "rejected"
end}
NS.Select(id);c.draft="successful submission"
check(NS.Send(c.draft),"native submission accepted")
check(c.latestSubmission.text=="successful submission" and c.latestSubmission.time==123,"accepted submission gets durable local backup")
check(c.draft=="successful submission","Core does not clear a draft before UI processes submission result")
accept=false;c.draft="new rejected draft"
check(not NS.Send(c.draft),"failed native submission remains failure")
check(c.latestSubmission.text=="successful submission" and c.draft=="new rejected draft","failure changes neither last accepted backup nor current draft")
local before=calls
check(not NS.RestoreLastCommunitySubmission(id),"restore refuses to overwrite a newer draft")
check(c.draft=="new rejected draft" and calls==before,"refused restore does not mutate or send")
c.draft=""
check(NS.RestoreLastCommunitySubmission(id),"empty composer can recover its own last submission")
check(c.draft=="successful submission" and calls==before,"restore is a draft operation and never retransmits")
check(not NS.RestoreLastCommunitySubmission("guild"),"restore cannot redirect a group backup into another kind")
c.messages[1].author="|Kq3|k"
local db=NS.InitDB(NS.db);c=db.conversations[id]
check(c.messages[1].text=="[群消息待重新读取]" and not c.messages[1].communityNativeContent,"reload never renders a saved session token")
check(c.messages[1].author=="社区成员" and not c.messages[1].communityAuthorKnown,"stale native author handle cannot become a private-message target")
check(c.messages[1].id=="clubmsg:1000000:1" and c.messages[1].clubEpoch==1000000,"server message identity survives for native cache refresh")
check(c.latestSubmission.text=="successful submission" and c.latestSubmission.time==123,"authored plaintext backup survives reload")
check(NS.StoreCommunityMessage(id,message("|Kw12|k"),"history"),"fresh native cache may replace saved placeholder")
check(#c.messages==1 and c.messages[1].text=="|Kw12|k" and c.messages[1].communityNativeContent,"refresh replaces handle without duplicating messages")
local bad=message("prefix |Kw12|k");NS.StoreCommunityMessage(id,bad,"history")
check(not c.messages[1].communityNativeContent,"prefix or mixed markup cannot receive native-content permission")
bad=message("|Kw12|k");bad.communityNativeContent=secret;NS.StoreCommunityMessage(id,bad,"history")
check(not c.messages[1].communityNativeContent,"restricted permission flag is ignored safely")
c.latestSubmission={text="|Kw12|k",time=123};c.draft=""
check(not NS.RestoreLastCommunitySubmission(id),"session handles cannot be recovered as authored text")
db=NS.InitDB(NS.db)
check(db.conversations[id].latestSubmission==nil,"saved native handles are not accepted as durable submission backups")
print("chat_community_storage_test: "..checks.." checks passed")
