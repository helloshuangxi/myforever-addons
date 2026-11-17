local NS, checks={},0
local function check(value, label)
    checks=checks+1
    assert(value,label or "client bridge check "..checks)
end
local function load(name)
    assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/"..name..".lua"))("MyForeverNavigator", NS)
end
local onQuest,ready,handedIn,finished,now=true,false,false,false,100
local multiple=false
local location={mapID=1453,x=.5,y=.5}
GetTime=function() return now end
GetServerTime=function() return 1795000000 end
UnitGUID=function() return "Player-private-ID" end
UnitFactionGroup=function() return "Alliance" end
GetLocale=function() return "zhCN" end
C_Map={GetBestMapForUnit=function() return location.mapID end,GetMapInfo=function(id) return {name="地图"..id} end}
C_QuestLog={
    GetInfo=function() return {questID=61,title="测试包裹",isHeader=false} end,
    GetNumQuestLogEntries=function() return 1 end,
    GetSelectedQuest=function() return 61 end,
    GetTitleForQuestID=function() return "测试包裹" end,
    GetQuestObjectives=function() return {{type="item",text="包裹 "..(finished and "1/1" or "0/1"),finished=finished}} end,
    IsOnQuest=function() return onQuest end, ReadyForTurnIn=function() return ready end,
    IsQuestFlaggedCompleted=function() return handedIn end,
}
load("Core");load("Data");load("RouteData");load("Routes");load("FuzzySearch");load("RoutePlanner");load("QuestData")
load("QuestNavigation")
local lifecycle
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,_,handler) lifecycle=handler end} end
load("GameBridge")
CreateFrame=nil
local realReference=NS.GetQuestReference
local lookup=NS.MatchReferenceQuest
check(lookup("狗头人的蜡烛任务怎么做")==60,"真实离线任务标题匹配")
local function point(map,id,kind,x)
    return {mapID=map,x=x or .5,y=.5,sourceKind=kind,sourceID=id,sourceName="来源",source="reference",faction="Neutral"}
end
NS.GetQuestReference=function(id)
    if id~=61 then return end
    local points={point(1453,7,"drop")}
    if multiple then points[#points+1]=point(1455,8,"drop") end
    return {name="测试包裹",objectives={{kind="item",id=4,name="包裹",points=points}},
        turnin={{kind="turnin",id=93,name="送件人",points={point(1453,93,"npc",.6)}}}}
end
NS.GetLocationContext=function() return location end
NS.MeasurePoint=function() return 8 end
NS.GetNavigation=function() return {point=NS.GetPoint(NS.DB.activeID),mode="arrived"} end
NS.Start=function(id,route) NS.DB.activeID,NS.DB.route=id,route;return true end
NS.Initialize({})
local function submit(q) return assert(NS.SubmitClientQuestion(q)) end
local function respond(req,steps)
    MyForeverNavigatorInbox={version=1,replies={[req.id]={id=req.id,steps=steps,message="操作说明"}}}
end
local function questReply(req)
    respond(req,{{kind="quest",key="q2",text="交给送件人"},{kind="quest",key="q1",text="收集一个包裹"}})
end
local q="测试包裹任务怎么做"
local req=submit(q)
check(req.questID==61 and req.questTitle=="测试包裹" and #req.choices==2)
check(req.choices[1].kind=="objective" and req.choices[2].kind=="turnin" and req.choices[1].detail:find("0/1",1,true))
check(not req.id:find("private",1,true) and not req.character and not req.account and not req.guid)
check(NS.ClientQuestionStatus()=="pending" and not NS.ReadClientAnswer())
check(NS.SubmitClientQuestion(q,nil,true).id==req.id,"重复点击不重复发问")
local saved=NS.DB
NS.Initialize(saved)
check(NS.SubmitClientQuestion(q).id==req.id and NS.ClientQuestionStatus()=="pending","重载后继续同一个请求")
questReply(req)
onQuest=false;NS.InvalidateClientQuestFacts()
check(NS.ClientQuestionStatus()=="pending" and select(2,NS.ClientQuestionStatus()):find("日志",1,true),"角色载入前保留已返回的答案")
onQuest=true;NS.RefreshQuestSession()
check(NS.ClientQuestionStatus()=="ready","日志就绪后同ID的答复可重读")
MyForeverNavigatorInbox={version=1,replies={another={id="another",steps={}}}}
check(NS.ClientQuestionStatus()=="pending","其他角色的回答不能被消费")
respond(req,{{kind="quest",key="wrong",text="猜位置"}})
check(NS.ClientQuestionStatus()=="error","拒绝未知任务引用")
local retried=NS.SubmitClientQuestion(q,nil,true)
check(retried.id~=req.id and NS.ClientQuestionStatus()=="pending","显式重试生成新关联 ID")
req=retried
respond(req,{{kind="quest",key="q1",text="1"},{kind="quest",key="q1",text="2"}})
check(NS.ClientQuestionStatus()=="error","同一任务动作不得重复")
respond(req,{{kind="place",term="x",text="|Htest"}})
check(NS.ClientQuestionStatus()=="error","显示文本拒绝游戏转义")
respond(req,{})
check(NS.ClientQuestionStatus()=="error" and select(2,NS.ClientQuestionStatus())=="操作说明")
respond(req,{{kind="place",term="铁炉堡",text="去取包裹"}})
local grounded=assert(NS.ReadClientAnswer())
check(#grounded.steps==2 and grounded.steps[1].ref=="item:4" and grounded.steps[2].ref=="turnin"
    and grounded.message:find("补全",1,true),"整项已知任务的泛化地址重新落到日志目标和交付人")
respond(req,{{kind="place",term="包裹",text="取得任务包裹"}})
grounded=assert(NS.ReadClientAnswer())
check(grounded.steps[1].ref=="item:4" and grounded.steps[1].text:find("包裹 0/1",1,true) and grounded.steps[2].ref=="turnin",
    "具名步骤保留说明，本地补上遗漏交付")
respond(req,{{kind="quest",key="q2",text="杀死送件人"}})
MyForeverNavigatorInbox.replies[req.id].message="杀死送件人并结束任务"
grounded=assert(NS.ReadClientAnswer())
check(#grounded.steps==2 and grounded.steps[1].ref=="item:4" and grounded.steps[2].text=="向送件人交付任务" and not grounded.message:find("杀死",1,true),"仅交付的模型答案补全前置目标")
questReply(req)
local reply=assert(NS.ReadClientAnswer())
check(reply.requestID==req.id and reply.steps[1].ref=="item:4" and reply.steps[2].ref=="turnin","交付排在目标之后")
local state=assert(NS.BuildClientRouteState(reply))
check(state.plan and #state.ids==2 and state.index==3,"明确的本地候选直接变成分段预览")
check(state.plan.steps[1].label:find("包裹 0/1",1,true) and state.plan.steps[2].label:find("向送件人交付任务",1,true))
check(NS.RebuildClientPlan(state,true).noUnconfirmedFlights and state.plan.steps[2].questGoal==state.ids[2])
check(not NS.LookupClientRouteState(q),"未确认语义不写入缓存")
check(NS.ConfirmRouteQuery(state) and not MyForeverNavigatorOutbox)
check(NS.ClientQuestionStatus()=="none" and #NS.DB.clientAI.cache==1)
check(NS.LookupClientRouteState(q).plan and #NS.DB.clientAI.cache==1)
local objective=NS.DB.activeID
check(NS.GetPoint(objective).questPhase=="objective")
check(not NS.UpdateRouteProgress() and NS.DB.activeID==objective,"抵达掉落点不算取得物品")
check(not NS.NextRouteStep(),"不能手动跨过未完成的采集任务")
NS.Initialize(NS.DB)
check(NS.DB.activeID==objective and NS.GetActiveRoute().index==1,"分段状态和任务语义可跨重载")
finished=true;NS.RefreshQuestSession()
check(NS.GetActiveRoute().index==1 and not NS.NextRouteStep(),"一个目标已完成但整项任务还不能交付")
check(not NS.LookupClientRouteState(q),"旧任务进度的缓存不能挡住新问题")
ready=true;now=103;NS.RefreshQuestSession()
check(NS.GetActiveRoute().index==2 and NS.GetPoint(NS.DB.activeID).questPhase=="turnin","日志允许交付后才切到 NPC")
check(not NS.UpdateRouteProgress() and not NS.GetActiveRoute().complete,"抵达交付 NPC 不等于交付")
onQuest=false;handedIn=true;now=105;NS.RefreshQuestSession()
check(NS.GetActiveRoute().complete,"实际交付后才完成路线")
onQuest,handedIn,ready,finished,multiple=true,false,false,false,true
NS.InvalidateClientQuestFacts()
req=submit("测试包裹任务的物品在哪里")
respond(req,{{kind="quest",key="q1",text="查看包裹来源"}})
check(#NS.ReadClientAnswer().steps==1,"只问某个物品时保留该环节")
req=submit("这个任务怎么做")
check(req.questID==61 and #req.choices==2,"获取当前选中任务，不枚举全部日志内容")
questReply(req)
state=assert(NS.BuildClientRouteState())
check(not state.plan and state.index==1 and #state.clientSteps==2)
local points,maps=NS.GetRouteCandidates(state)
check(#points==2 and maps==2,"不同地图的真实来源保留选择")
check(not NS.ChooseRouteCandidate(state,"made-up-id"))
check(NS.ChooseRouteCandidate(state,points[2].id) and state.plan and #state.plan.steps>=2)
NS.ResetClientRouteState(state)
check(state.index==1 and not state.plan and #state.ids==0)
local previous=req.id
finished=true;NS.InvalidateClientQuestFacts()
check(NS.ClientQuestionStatus()=="error" and not NS.BuildClientRouteState())
req=submit("这个任务怎么做")
check(req.id~=previous and #req.choices==1 and req.choices[1].kind=="turnin")
respond(req,{{kind="quest",key="q1",text="去交付"}})
state=assert(NS.BuildClientRouteState())
check(not NS.ConfirmRouteQuery(state),"单独建议交付也不能绕开日志就绪门槛")
local city=submit("我要去铁炉堡")
check(city.id~=req.id and city.questID==0 and city.questTitle=="" and #city.choices==0)
respond(city,{{kind="place",term="铁炉堡",text="前往铁炉堡"}})
state=assert(NS.BuildClientRouteState())
points,maps=NS.GetRouteCandidates(state)
check(#points==2 and maps==1 and not state.plan)
for _,p in ipairs(points) do check(p.id:match("^route%-stop:ironforge") and p.faction=="Alliance","整座城市只列出当前阵营可用交通点") end
check(NS.ChooseRouteCandidate(state,points[1].id) and state.plan)
check(NS.ConfirmRouteQuery(state) and NS.LookupClientRouteState("我要去铁炉堡"),"确认后再问同一目的地可本地查找")
for _,zone in ipairs({"达纳苏斯","奥特兰克山脉"}) do
    local visit=submit("我要去"..zone)
    respond(visit,{{kind="place",term=zone,text="进入该区域"}})
    local region=assert(NS.BuildClientRouteState())
    local entries,count=NS.GetRouteCandidates(region)
    check(not region.plan and region.candidateNotice and #entries>0 and count>0,"缺少入口的"..zone.."允许手选已知落点")
    for _,p in ipairs(entries) do assert(p.zone==zone) end
    check(NS.ChooseRouteCandidate(region,entries[1].id) and region.plan,"经玩家选择才对"..zone.."地标导航")
end
local place=submit("我要去测试据点")
local dest=assert(NS.AddCustom("测试据点",1453,.7,.7))
respond(place,{{kind="place",term="测试据点",text="前往据点",x=.1,y=.1,mapID=1234}})
state=assert(NS.BuildClientRouteState())
check(state.plan and state.ids[1]==dest.id and NS.GetPoint(dest.id).mapID==1453,"忽略外部坐标，只解析本地站点")
NS.CancelClientQuestion()
check(not NS.ConfirmRouteQuery(state) and NS.ClientQuestionStatus()=="none","已取消回答不得启动")
check(not NS.SubmitClientQuestion(string.rep("问",61)) and not NS.SubmitClientQuestion("问|Hlink"))
local relative="我要去离我最近的主城"
local beforeCount=#NS.DB.clientAI.cache
local sameLocation=submit(relative)
respond(sameLocation,{{kind="place",term="最近的主城",text="前往最近的城市"}})
check(submit(relative).id==sameLocation.id,"同一位置、同一待答请求幂等")
state=assert(NS.BuildClientRouteState())
local cities,cityMaps=NS.GetRouteCandidates(state)
check(cityMaps>=3 and cities[1].mapID==1453 and state.candidateNotice and not state.plan,"最近主城列出本阵营城市，当前城市优先而非误定最短")
for _,p in ipairs(cities) do assert(p.faction=="Alliance" or p.faction=="Neutral") end
check(NS.ChooseRouteCandidate(state,cities[1].id))
location.x=location.x+.03
check(NS.ClientQuestionStatus()=="error" and not NS.ConfirmRouteQuery(state),"同地图移动也不会启动原来的最近主城")
local newLocation=submit(relative)
check(newLocation.id~=sameLocation.id,"换位置重新提问生成新 ID")
respond(newLocation,{{kind="place",term="铁炉堡",text="前往铁炉堡"}})
state=assert(NS.BuildClientRouteState())
check(NS.ChooseRouteCandidate(state,NS.GetRouteCandidates(state)[1].id) and NS.ConfirmRouteQuery(state))
check(not NS.LookupClientRouteState(relative) and #NS.DB.clientAI.cache==beforeCount,"相对地点不进入游戏持久缓存")
local moved=submit(relative)
location.mapID=1413
check(NS.ClientQuestionStatus()=="error" and submit(relative).id~=moved.id,"已换大陆的待答问题必须刷新")
location.mapID=1453
local bank=assert(NS.AddCustom("北区银行",1453,.2,.2))
local bankAsk=submit("告诉我最近的银行")
respond(bankAsk,{{kind="place",term="最近 银行",text="查找附近的银行"}})
state=assert(NS.BuildClientRouteState())
local bankPoints=NS.GetRouteCandidates(state)
check(state.plan and state.ids[1]==bank.id or bankPoints[1] and bankPoints[1].id==bank.id,"最近加空格的服务名走现有模糊查询")
local pending=submit("我要去不存在的地点")
respond(pending,{{kind="place",term="不存在的地点",text="去那里"}})
state=assert(NS.BuildClientRouteState())
check(not state.plan and #NS.GetRouteCandidates(state)==0 and NS.ClientQuestionStatus()=="ready","没有可靠地点时保留回答以便数据就绪后重建")
-- Real Northshire quest 33 has many wolf sources across zones. A player in
-- Elwynn should see local wolves first; retain Dun Morogh for manual selection.
NS.GetQuestReference=realReference
location={mapID=1429,x=.49,y=.41}
C_QuestLog.GetQuestObjectives=function() return {{type="item",text="硬狼肉 0/8",finished=false}} end
NS.MeasurePoint=function(p,ctx)
    if p.mapID==ctx.mapID then return ((p.x-ctx.x)^2+(p.y-ctx.y)^2)^.5*4000 end
end
NS.InvalidateClientQuestFacts()
req=assert(NS.SubmitClientQuestion("林中的群狼怎么做",33))
respond(req,{{kind="quest",key="q1",text="取得硬狼肉"}})
state=assert(NS.BuildClientRouteState())
points,maps=NS.GetRouteCandidates(state)
check(not state.plan and maps>1 and points[1].mapID==1429,"任务33优先本地艾尔文狼")
local other,dist=false,-1
for _,p in ipairs(points) do
    if p.mapID~=1429 then other=true
    else
        check(not other and p.distance>=dist,"本地候选按可比较距离排序")
        dist=p.distance
    end
end
check(other and NS.ChooseRouteCandidate(state,points[1].id) and state.plan.steps[1].mode=="walk" and state.plan.steps[1].id==points[1].id,
    "本地狼可直接步行，远区没有被删掉")
-- Split long quest chains into a bounded chunk that withholds the turn-in.
NS.GetQuestReference=function()
    local r={name="测试包裹",objectives={},turnin={{kind="turnin",id=93,name="送件人",points={point(1453,93,"npc")}}}}
    for i=1,7 do
        r.objectives[i]={kind="item",id=i,name="目标"..i,points={point(1453,i,"drop")}}
    end
    return r
end
NS.InvalidateClientQuestFacts()
req=assert(NS.SubmitClientQuestion(q,61))
respond(req,{{kind="quest",key="q8",text="交付"}})
local longer=assert(NS.ReadClientAnswer())
check(#longer.steps==6 and longer.message:find("前 6 个",1,true) and longer.steps[6].ref=="item:6",
    "超过6个动作时本次限前6项并按后续任务进度续问，暂缓交付")
-- Repeatable quest histories may remain true while the new attempt is active.
-- A real turn-in event works even for quests with no persistent completion flag.
NS.GetQuestReference=function() return {name="测试包裹",objectives={},turnin={
    {kind="turnin",id=93,name="送件人",points={point(1453,93,"npc")}}}} end
location={mapID=1453,x=.5,y=.5}
onQuest,ready,handedIn=true,true,true
NS.InvalidateClientQuestFacts()
req=assert(NS.SubmitClientQuestion(q,61))
respond(req,{{kind="quest",key="q1",text="交付这个重复任务"}})
state=assert(NS.BuildClientRouteState())
check(NS.ConfirmClientRoute(state) and NS.GetActiveRoute().steps[1].questPreviouslyDone)
onQuest=false;ready=false;NS.RefreshQuestSession()
check(not NS.UpdateRouteProgress() and not NS.GetActiveRoute().complete,"放弃重复任务不能因为历史完成过而显示交付")
handedIn=false;now=120
lifecycle(nil,"QUEST_TURNED_IN",61,100,100)
check(NS.GetActiveRoute().complete,"重复任务可以用当前真实交付事件完成")
print("Navigator client question bridge and quest itinerary: "..checks.." checks passed")
