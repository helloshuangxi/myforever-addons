local NS = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Notifications.lua"))("MyForeverChat", NS)
local checks = 0
local function check(condition, description) checks=checks+1; assert(condition,description) end

local function scenario(limit, priorities, durations)
    local state={now=0,limit=limit,blocked={},timers={},changes=0,priorities=priorities,durations=durations}
    state.manager=NS.CreateNotifications({
        canShow=function(id) return not state.blocked[id] end,
        maxVisible=function() return state.limit end,
        priority=priorities and function(id) return state.priorities[id] end,
        duration=durations and function(id) return state.durations[id] end,
        after=function(seconds,callback) state.timers[#state.timers+1]={at=state.now+seconds,delay=seconds,run=callback} end,
        onChange=function(_,_,page) state.changes=state.changes+1; state.page=page end,
    })
    function state:advance(untilTime)
        while true do
            local nextIndex,nextTimer
            for index,timer in ipairs(self.timers) do
                if timer.at<=untilTime and (not nextTimer or timer.at<nextTimer.at) then nextIndex,nextTimer=index,timer end
            end
            if not nextTimer then break end
            table.remove(self.timers,nextIndex); self.now=nextTimer.at; nextTimer.run()
        end
        self.now=untilTime
    end
    return state,state.manager
end

local function push(manager,id,text) local message={text=text or id}; manager:Push(id,message); return message end
local function visible(manager) local ids={}; for _,item in ipairs(manager.visible) do ids[#ids+1]=item.conversationId end; return table.concat(ids,",") end
local function contains(manager,message) for _,item in ipairs(manager.items) do if item.message==message then return item end end end
local function validLists(manager)
    local seen={}
    for _,list in ipairs({manager.visible,manager.queued}) do
        for _,item in ipairs(list) do if seen[item] or not contains(manager,item.message) then return false end; seen[item]=true end
    end
    return #manager.visible+#manager.queued==#manager.items and #manager.visible<=4 and #manager.queued<=12
end

do
    local clock,manager=scenario(4)
    local first=push(manager,"alice"); clock:advance(5); push(manager,"bob"); push(manager,"alice")
    check(visible(manager)=="alice,bob,alice","separate same-person messages preserve chronological order")
    check(not manager:Push("alice",first) and #manager.visible==3,"same message object is shown once")
    check(not manager:Push("",{}) and not manager:Push("alice","bad"),"invalid inputs do not enter stack")
    local timers,changes=#clock.timers,clock.changes
    manager:Refresh(); check(#clock.timers==timers and clock.changes==changes,"unchanged refresh does not redraw or restart timers")
    clock:advance(19); check(#manager.visible==3,"default notification remains visible before twenty seconds")
    clock:advance(20); check(visible(manager)=="bob,alice","twenty-second expiration removes only its own notification")
    check(not manager:Push("alice",first),"expired message cannot replay")
    clock:advance(25); check(#manager.visible==0 and #manager.items==0,"later arrivals retain independent twenty-second deadlines")
end

do
    local clock,manager=scenario(2)
    for index=1,15 do push(manager,"alice",tostring(index)) end
    check(#manager.visible==2 and #manager.queued==12 and #clock.timers==2,"only visible items start timers and hidden backlog is capped")
    check(manager.queued[1].message.text=="4" and manager.queued[12].message.text=="15","overflow removes oldest waiting item of lowest priority")
    clock:advance(10); local dismissed=manager.visible[1]; manager:Dismiss(dismissed)
    check(manager.visible[1].message.text=="2" and manager.visible[2].message.text=="4","single dismissal promotes next unseen item")
    check(not manager:Dismiss(dismissed),"repeated dismissal cannot remove replacement")
    clock:advance(20)
    check(manager.visible[1].message.text=="4" and manager.visible[2].message.text=="5","stale dismissed callback leaves replacement intact")
    clock:advance(29); check(manager.visible[1].message.text=="4","unseen item receives full duration on first display")
    clock:advance(30); check(manager.visible[1].message.text=="5" and manager.visible[2].message.text=="6","first displayed queued item expires twenty seconds later")
    check(validLists(manager),"visible and queued form a nonduplicated partition of active reminders")
end

do
    local clock,manager=scenario(2)
    push(manager,"alice"); push(manager,"bob"); push(manager,"alice"); push(manager,"carol"); push(manager,"deleted")
    clock.blocked.alice=true; clock.blocked.deleted=true; manager:Refresh()
    check(visible(manager)=="bob,carol" and #manager.queued==0,"muted and deleted conversations leave visible and hidden lists")
    push(manager,"bob"); push(manager,"dave"); manager:DismissConversation("bob")
    check(visible(manager)=="carol,dave","opening a conversation removes only its reminders")
    local muted={text="quiet"}; check(not manager:Push("alice",muted),"muted message is not enqueued")
    clock.blocked.alice=false; check(not manager:Push("alice",muted),"unmuting does not replay suppressed messages")
end

do
    local clock,manager=scenario(2)
    push(manager,"first"); clock:advance(2); push(manager,"second"); local second=manager.visible[2]
    clock:advance(5); clock.limit=0; manager:Refresh()
    check(#manager.visible==1 and manager.queued[1]==second,"small viewport retains hidden reminder")
    clock:advance(6); clock.limit=10; manager:Refresh()
    check(manager.visible[2]==second and #clock.timers==2,"viewport expansion does not restart already-seen timer")
    clock:advance(20); check(visible(manager)=="second","seen reminder keeps original first-display deadline")
    clock:advance(22); check(#manager.visible==0,"resized reminder expires without an extended lifetime")
    for index=1,6 do push(manager,"alice",tostring(index)) end
    check(#manager.visible==4 and #manager.queued==2,"large screen still caps visible stack at four")
end

do
    local clock,manager=scenario(2)
    local first=push(manager,"alice"); push(manager,"bob"); push(manager,"alice")
    local changes=clock.changes
    check(manager:DismissAll() and #manager.items==0 and #manager.visible==0 and #manager.queued==0,"clear all removes every page")
    check(clock.changes==changes+1 and clock.page.total==0 and clock.page.first==0,"clear redraws once with empty pagination")
    check(not manager:DismissAll() and not manager:Push("alice",first),"empty clear is inert and cleared messages stay suppressed")
    clock:advance(2); local fresh=push(manager,"carol"); clock:advance(20)
    check(manager.visible[1].message==fresh and #manager.items==1,"cleared timers cannot revive old pages or remove fresh bubble")
    clock:advance(22); check(#manager.items==0,"new message retains own full lifetime")
end

do
    local clock,manager=scenario(4,{guild=1,group=1,raid=1})
    for index=1,4 do push(manager,"world",tostring(index)) end
    local displaced=manager.visible[4]
    clock:advance(5); local important=push(manager,"guild")
    check(manager.visible[1].message==important and manager.visible[2].message.text=="1" and manager.visible[4].message.text=="3"
        and manager.queued[1]==displaced,"priority immediately replaces newest low-priority visible bubble at first page")
    check(manager.visible[1].order==5 and displaced.order==4 and important.order==nil and important.priority==nil,
        "monotonic arrival metadata never mutates chat message objects")
    local timers=#clock.timers; manager:Refresh()
    check(#clock.timers==timers,"priority sort does not reset displayed timers")
    clock:advance(20)
    check(visible(manager)=="guild" and #manager.queued==0,"preempted seen message still expires at original deadline offscreen")
    clock:advance(25); check(#manager.items==0,"priority does not pin notifications forever")
end

do
    local clock,manager=scenario(2,{guild=1,group=1,raid=1})
    push(manager,"guild"); push(manager,"world","early"); clock:advance(1); push(manager,"group")
    clock:advance(2); push(manager,"world","later"); clock:advance(3); push(manager,"raid")
    check(visible(manager)=="guild,group","same-priority displayed messages retain chronological order")
    check(manager.queued[1].conversationId=="raid" and manager.queued[2].message.text=="early","priority queue sorts ahead while preserving equal-priority order")
    clock:advance(20); check(visible(manager)=="group,raid","oldest important unseen message fills next vacant slot")
    clock:advance(21); check(visible(manager)=="raid,world" and manager.visible[2].message.text=="later","ordinary unseen item eventually displays after finite important stream")
    clock:advance(60); check(#manager.items==0,"finite mixed-priority backlog drains completely")
end

do
    local clock,manager=scenario(1,{guild=1})
    push(manager,"guild","visible")
    for index=1,3 do push(manager,"guild","important"..index) end
    for index=1,15 do push(manager,"world","ordinary"..index) end
    check(#manager.visible==1 and #manager.queued==12 and #clock.timers==1,"priority does not increase bounded queue size")
    check(manager.queued[1].message.text=="important1" and manager.queued[3].message.text=="important3"
        and manager.queued[4].message.text=="ordinary7","overflow retains important items before oldest ordinary items")
    manager:Dismiss(manager.visible[1]); check(manager.visible[1].message.text=="important1","dismissal promotes oldest highest-priority item")
    manager:DismissAll(); clock:advance(100); check(#manager.items==0,"clearing prioritized pages invalidates every callback")
end

do
    local clock,manager=scenario(2,{})
    push(manager,"first"); push(manager,"second"); push(manager,"third")
    clock.priorities.third=1; manager:Refresh()
    check(visible(manager)=="third,first" and manager.queued[1].conversationId=="second","priority change promotes existing queued item without new chat")
    clock.blocked.third=true; manager:Refresh()
    check(visible(manager)=="first,second" and #manager.queued==0,"muting high-priority item frees its slot")
    local timers=#clock.timers; clock.limit=1; manager:Refresh(); clock.limit=2; manager:Refresh()
    check(visible(manager)=="first,second" and #clock.timers==timers,"priority plus viewport changes preserve order and timer identity")
end

do
    local clock,manager=scenario(4,{first="bad",second=0/0,third=math.huge,fourth=-math.huge})
    for _,id in ipairs({"first","second","third","fourth"}) do push(manager,id) end
    check(visible(manager)=="first,second,third,fourth" and manager.visible[1].priority==0,"invalid priority values safely use ordinary ordering")
end

-- Duration comes from conversation type; it is fixed when first shown.
do
    local clock,manager=scenario(4,nil,{guild=20,channel=20,whisper=60,bnet=60,group=60,raid=60})
    push(manager,"guild"); push(manager,"channel"); push(manager,"whisper"); push(manager,"group")
    check(clock.timers[1].delay==20 and clock.timers[2].delay==20 and clock.timers[3].delay==60
        and clock.timers[4].delay==60,"guild/channel use twenty seconds and private/group use sixty")
    clock:advance(19); check(#manager.visible==4,"all categories remain before first deadline")
    clock:advance(20); check(visible(manager)=="whisper,group","twenty-second messages expire while sixty-second messages remain")
    push(manager,"bnet"); push(manager,"raid")
    check(clock.timers[3].delay==60 and clock.timers[4].delay==60,"Battle.net private and raid messages also use sixty seconds")
    clock.durations.whisper=20; manager:Refresh(); clock:advance(59)
    check(#manager.visible==4,"later policy changes do not shorten or restart existing notification lifetime")
    clock:advance(60); check(visible(manager)=="bnet,raid","original sixty-second deadlines remain exact")
    clock:advance(80); check(#manager.items==0,"later sixty-second arrivals expire at their own deadline")
end

-- Paging retains previously viewed reminders and never extends their timers.
do
    local clock,manager=scenario(2,nil,{private=60})
    for index=1,6 do push(manager,"private",tostring(index)) end
    local page=manager:GetPageInfo()
    check(page.first==1 and page.last==2 and page.total==6 and not page.hasPrevious and page.hasNext,"initial page metadata reports range and directions")
    check(not manager:Scroll(-1) and not manager:Scroll(0) and not manager:Scroll("bad"),"previous boundary and invalid scroll are harmless")
    clock:advance(5); check(manager:Scroll(1),"next-group scroll changes viewport")
    page=manager:GetPageInfo()
    check(page.first==3 and page.last==4 and page.hasPrevious and page.hasNext and manager.visible[1].message.text=="3",
        "next group exposes middle range while previous reminders remain retained")
    check(#clock.timers==4 and #manager.queued==4 and validLists(manager),"paging starts only newly seen timers without duplicating queue entries")
    clock:advance(10); manager:Scroll(-1)
    check(manager.visible[1].message.text=="1" and #clock.timers==4,"returning to previously viewed group preserves its timer")
    manager:Scroll(1); manager:Scroll(1); page=manager:GetPageInfo()
    check(page.first==5 and page.last==6 and not page.hasNext and page.hasPrevious,"last group has accurate boundary metadata")
    local changes=clock.changes; check(not manager:Scroll(1) and clock.changes==changes,"scrolling beyond last page does not redraw")
    clock:advance(60)
    check(#manager.items==4 and manager.visible[1].message.text=="5" and #clock.timers==4,"first page expires even while reader is on last page")
    clock:advance(65)
    check(#manager.items==2 and manager.visible[1].message.text=="5","middle page also expires offscreen at first-display deadline")
    clock:advance(70); check(#manager.items==0,"paging back and forward cannot keep reminders alive indefinitely")
end

-- Arrivals keep a browsed page anchored, including a new priority item.
do
    local clock,manager=scenario(2,{guild=1},{private=60,guild=20})
    for index=1,6 do push(manager,"private",tostring(index)) end
    manager:Scroll(1); local anchor=manager.visible[1]
    push(manager,"guild")
    check(manager.visible[1]==anchor and manager.offset==3 and manager:GetPageInfo().total==7,"new priority arrival does not jump away from a browsed page")
    manager:Dismiss(manager.items[2])
    check(manager.visible[1]==anchor and manager.offset==2,"deleting a preceding item preserves current first-visible anchor")
    local nextAnchor=manager.visible[2]; manager:Dismiss(anchor)
    check(manager.visible[1]==nextAnchor,"removing first-visible item preserves next surviving viewed reminder")
    manager:Scroll(-1)
    check(manager.visible[1].conversationId=="guild","scrolling back exposes priority messages at beginning")
    manager:Scroll(1); manager:DismissAll()
    check(manager.offset==0 and manager:GetPageInfo().total==0 and not manager:GetPageInfo().hasPrevious,"clear while browsing resets pagination")
    push(manager,"private","fresh"); check(manager.visible[1].message.text=="fresh" and manager.offset==0,"fresh stack after clear begins at first page")
end

-- Pruning an offscreen seen item invalidates its original timer too.
do
    local clock,manager=scenario(1,nil,{private=60})
    local first=push(manager,"private","1"); local firstItem=manager.visible[1]
    push(manager,"private","2"); manager:Scroll(1)
    local current=manager.visible[1]
    for index=3,15 do push(manager,"private",tostring(index)) end
    check(manager.visible[1]==current and not contains(manager,first) and #manager.items==13,"overflow protects current viewed item and prunes oldest offscreen item")
    check(manager.timers[firstItem]==nil and manager.timers[current] and validLists(manager),"pruning invalidates removed timer and preserves current timer and bounded partition")
    clock:advance(59); check(manager.visible[1]==current,"pruned item's stale callback cannot affect another reminder")
    clock:advance(60); check(not contains(manager,first) and not contains(manager,current.message),"pruned and expired items do not reappear")
end

print("chat_notifications_test: "..checks.." checks passed")
