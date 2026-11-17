-- Runs the real read-only probe against an event/API model. No native target
-- action, real game selection, nameplate identity or restricted C++ is tested.
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local checks=0
local fixtures={}
local function eq(actual,expected,why)
    checks=checks+1;assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local secret=setmetatable({},{__tostring=function() error("secret formatted") end,
    __eq=function() error("secret compared") end})
local function fixture()
    local f={units={nameplate1={},nameplate2={}},tokens={"nameplate1","nameplate2"},epochs={nameplate1=1,nameplate2=2},
        inside=true,kind="party",combat=false,spell=false,item=false,worldActive=true,tombstones={},reads=0,mutations=0,overrides={},timers={},
        records={},messages={},session=0,enabled=false,starts=0,stops=0}
    fixtures[#fixtures+1]=f
    issecretvalue=function(value) return rawequal(value,secret) end
    local function invoke(name,normal,...)
        f.reads=f.reads+1
        if f.overrides[name] then return f.overrides[name](...) end
        return normal(...)
    end
    IsInInstance=function() return invoke("instance",function() return f.inside,f.kind end) end
    InCombatLockdown=function() return invoke("combat",function() return f.combat end) end
    SpellIsTargeting=function() return invoke("spell",function() return f.spell end) end
    CursorHasItem=function() return invoke("item",function() return f.item end) end
    UnitExists=function(unit) return invoke("exists",function(u)
        if u=="target" then return f.target~=nil end
        return f.units[u]~=nil
    end,unit) end
    UnitCanAttack=function(_,unit) return invoke("harm",function(u) return f.units[u]~=nil end,unit) end
    UnitIsPlayer=function(unit) return invoke("player",function() return false end,unit) end
    UnitIsUnit=function(unit,other) return invoke("same",function(u,b)
        assert(b=="target","probe comparison must use target")
        return f.units[u]~=nil and f.units[u]==f.target
    end,unit,other) end
    C_Secrets={
        CanCompareUnitTokens=function(a,b) return invoke("can",function() return true end,a,b) end,
        ShouldUnitComparisonBeSecret=function(a,b) return invoke("secrecy",function() return false end,a,b) end,
    }
    for _,name in ipairs({"CreateFrame","hooksecurefunc","TargetUnit","FocusUnit","ClearTarget","SetRaidTarget",
        "TargetNearestEnemy","CastSpellByName","CastSpellByID","SetOverrideBindingClick","SetBinding",
        "RegisterStateDriver","RunMacroText","UnitName","UnitGUID"}) do
        _G[name]=function() f.mutations=f.mutations+1;error("forbidden probe side effect: "..name) end
    end
    C_Timer={After=function(delay,fn) assert(delay==.15);f.timers[#f.timers+1]=fn end}
    local NS={};assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
    f.NS=NS
    NS.Print=function(text) f.messages[#f.messages+1]=text end
    NS.RestrictedEnemyTokens=function() return f.tokens end
    f.sourceEntries={}
    NS.EnemyDisplay={
        RestrictedEntry=function(unit)
            if not f.sourceEntries[unit] then f.sourceEntries[unit]={unit=unit,tokenEpoch=f.epochs[unit],restrictedIdentity=true} end
            return f.sourceEntries[unit]
        end,
        IsCurrent=function(entry)
            if f.lifecycleHook then local hook=f.lifecycleHook;f.lifecycleHook=nil;hook(entry) end
            return invoke("lifecycle",function(e)
                return f.worldActive and not f.tombstones[e.unit] and f.epochs[e.unit]==e.tokenEpoch
            end,entry)
        end,
        LifecycleState=function(unit)
            return invoke("metadata",function(u)
                return {validToken=true,worldActive=f.worldActive,epochKnown=f.epochs[u]~=nil,
                    currentEpoch=f.epochs[u],tombstoned=f.tombstones[u]==true}
            end,unit)
        end,
    }
    NS.Diagnostics={Start=function() f.starts=f.starts+1;f.session=f.session+1;f.enabled=true end,
        Session=function() return f.session end,Enabled=function() return f.enabled end,
        Stop=function() f.stops=f.stops+1;f.enabled=false end,
        Record=function(kind,fields)
            if f.recordFail==kind then return false end
            if f.recordError==kind then error(secret) end
            local copied={};for k,v in pairs(fields) do copied[k]=v end
            f.records[#f.records+1]={kind=kind,fields=copied}
            if f.recordHook then f.recordHook(kind,fields) end
            return true
        end}
    assert(loadfile(root.."UnitMatchProbe.lua"))("MyForeverTargets",NS)
    f.P=NS.UnitMatchProbe
    function f:begin() return self.P.Command("on") end
    function f:select(unit) self.target=self.units[unit];self.P.OnEvent("PLAYER_TARGET_CHANGED") end
    function f:flush()
        local timers=self.timers;self.timers={};for _,fn in ipairs(timers) do fn() end
    end
    function f:last(kind)
        for i=#self.records,1,-1 do if self.records[i].kind==kind then return self.records[i].fields end end
    end
    function f:count(kind)
        local n=0;for _,r in ipairs(self.records) do if r.kind==kind then n=n+1 end end;return n
    end
    return f
end

local f=fixture()
eq(f.reads,0,"default load never reads unit APIs")
eq(f.P.Enabled(),false,"default off")
f.P.OnEvent("PLAYER_TARGET_CHANGED");f.P.Tick(.5);f.P.Command("status")
eq(f.reads,0,"inactive event tick status stay passive")
eq(f.starts,0,"inactive status never starts a log")
eq(f.mutations,0,"default module creates no UI/hooks/actions")
eq(f:begin(),true,"explicit on starts comparison observation")
eq(f.starts,1,"on starts one fresh bounded diagnostic session")
eq(f.P.Status().samples,1,"baseline is automatically sampled")
eq(f:last("UNIT_MATCH_ROW").same,false,"public false survives baseline logging")
eq(f:last("UNIT_MATCH_SAMPLE").targetExists,false,"empty target is distinct from unknown")
eq(f.P.Status().distinctMatches,0,"empty target is not a positive")
eq(f.messages[#f.messages]:find(f.NS.VERSION,1,true)~=nil,true,"start identifies the loaded version")
eq(f:begin(),true,"repeated on keeps an active observation")
eq(f.starts,1,"repeated on does not replace its log session")
f:select("nameplate1")
eq(f:last("UNIT_MATCH_SAMPLE").matchedIndex,1,"model target1 has one public match")
eq(f.P.Status().distinctMatches,1,"first positive contributes one frozen address")
local row1,row2=f.records[#f.records-2].fields,f.records[#f.records-1].fields
eq(row1.same,true,"positive comparison is preserved")
eq(row2.same,false,"different address is independently false")
eq(row1.canCompare,true,"comparison permission is recorded")
eq(row1.comparisonSecret,false,"comparison secrecy false is preserved")
f:flush()
eq(f.P.Status().distinctMatches,1,"delayed repeat never counts as another unit")
f:select("nameplate2");f:flush()
eq(f.P.Status().distinctMatches,2,"second uniquely matching address is independently counted")
eq(f:last("UNIT_MATCH_SAMPLE").twoUnitsObserved,true,"two addresses observed is explicit")
local notices=0
for _,m in ipairs(f.messages) do if m:find("两个不同测试编号",1,true) then notices=notices+1 end end
eq(notices,1,"two-address notice is emitted once")
eq(f.mutations,0,"selection observations never act on target/focus/spells/UI")
local target=f.target
eq(f.P.Command("off"),true,"off saves an owned log end")
eq(f.target,target,"off preserves the user's current target")
eq(f.enabled,false,"off stops its own diagnostic session")
eq(f.stops,1,"one session stop")
eq(f:last("UNIT_MATCH_END").twoUnitsObserved,true,"end preserves qualified two-address evidence")
local reads=f.reads;f:flush();f.P.Tick(.5);f.P.Command("status")
eq(f.reads,reads,"stale delayed work and stopped status read no units")

-- Admission failures leave logging and the live UI alone.
for _,case in ipairs({
    {"outside",function(x)x.inside=false end},
    {"non dungeon instance",function(x)x.kind="pvp" end},
    {"secret instance",function(x)x.inside=secret end},
    {"secret instance kind",function(x)x.kind=secret end},
    {"combat",function(x)x.combat=true end},
    {"existing target",function(x)x.target=x.units.nameplate1 end},
    {"spell cursor",function(x)x.spell=true end},
    {"item cursor",function(x)x.item=true end},
    {"only one plate",function(x)x.tokens={"nameplate1"} end},
    {"duplicate plate",function(x)x.tokens={"nameplate1","nameplate1"} end},
    {"negative epoch",function(x)x.epochs.nameplate2=-1 end},
    {"fractional epoch",function(x)x.epochs.nameplate2=.5 end},
    {"unknown NPC classification",function(x)x.overrides.player=function(u)if u=="nameplate2"then return secret end;return false end end},
    {"active focus probe",function(x)x.NS.FocusAPIProbe={active=true}end},
    {"focus cycle session",function(x)x.NS.FocusCycle={session={}}end},
    {"configured native hover",function(x)x.NS.EnemyNativeHover={Status=function()return {configured=true}end}end},
    {"scale restoring",function(x)x.NS.NativeScaleProbe={Status=function()return {restoring=true}end}end},
}) do
    local x=fixture();case[2](x)
    eq(x:begin(),false,case[1].." refused")
    eq(x.starts,0,case[1].." does not start logging")
end
f=fixture();f.NS.NearbyCast={Enabled=function()return true end};f.NS.CombatCast={Enabled=function()return true end}
eq(f:begin(),true,"normal friendly casting controllers do not block read-only diagnostics");f.P.Command("off")

-- Every raw API state stays distinguishable; none is converted into false or
-- a claimed positive merely because another row matched.
for _,case in ipairs({
    {"restricted",function()return secret end},
    {"nil",function()return nil end},
    {"error",function()error(secret)end},
    {"nonboolean",function()return "true"end},
}) do
    local x=fixture();eq(x:begin(),true,"state fixture starts")
    x.overrides.same=function(u)if u=="nameplate2"then return case[2]()end;return x.units[u]==x.target end
    x:select("nameplate1")
    eq(x:last("UNIT_MATCH_ROW").sameStatus,case[1],case[1].." reason remains explicit")
    eq(x:last("UNIT_MATCH_ROW").same,nil,case[1].." has no fabricated boolean")
    eq(x.P.Status().distinctMatches,0,case[1].." on another address blocks uniqueness")
    x.P.Command("off")
end
f=fixture();f:begin();UnitIsUnit=nil;f:select("nameplate1")
eq(f:last("UNIT_MATCH_ROW").sameStatus,"unavailable","missing comparison API is distinct")
eq(f.P.Status().distinctMatches,0,"missing comparison never matches");f.P.Command("off")
for _,which in ipairs({"CanCompareUnitTokens","ShouldUnitComparisonBeSecret"}) do
    local x=fixture();x:begin();C_Secrets[which]=nil;x:select("nameplate1")
    eq(x.P.Status().distinctMatches,0,"missing "..which.." cannot qualify")
    local field=which=="CanCompareUnitTokens" and "canCompareStatus" or "secrecyStatus"
    eq(x:last("UNIT_MATCH_ROW")[field],"unavailable","missing guard explicitly logged")
    x.P.Command("off")
end
f=fixture();f:begin();f.overrides.can=function()return false end;f:select("nameplate1")
eq(f:last("UNIT_MATCH_ROW").canCompare,false,"denied permission preserved")
eq(f.P.Status().distinctMatches,0,"denied permission cannot qualify");f.P.Command("off")
f=fixture();f:begin();f.overrides.secrecy=function()return true end;f:select("nameplate1")
eq(f:last("UNIT_MATCH_ROW").comparisonSecret,true,"secret guard true preserved")
eq(f.P.Status().distinctMatches,0,"comparison-secrecy restriction cannot qualify");f.P.Command("off")
f=fixture();f:begin();f.overrides.same=function()return true end;f:select("nameplate1")
eq(f:last("UNIT_MATCH_SAMPLE").trueCount,2,"two simultaneous positive aliases are visible as ambiguous")
eq(f.P.Status().distinctMatches,0,"ambiguous matches are not distinct creature proof");f.P.Command("off")

-- Target-generation changes cancel the older pending sample.
f=fixture();f:begin();f:select("nameplate1");f:select("nameplate2")
local before=f.P.Status().samples;f:flush()
eq(f.P.Status().samples,before+1,"only the latest target generation gets a delayed sample")
f.P.Command("off")

f=fixture();f:begin();f.overrides.same=function(u)
    f.overrides.same=nil;f:select("nameplate2");return u=="nameplate1"
end
f:select("nameplate1")
eq(f.P.Enabled(),true,"a newer target generation supersedes an older reentrant sample")
eq(f.P.Status().distinctMatches,1,"superseded target's result never contributes a match")
eq(f:last("UNIT_MATCH_SAMPLE").matchedIndex,2,"only the newer target generation is summarized")
f.P.Command("off")

-- Frozen lifecycle data is copied and cannot silently adopt a replacement.
f=fixture();f:begin();f.sourceEntries.nameplate1.tokenEpoch=100
f:select("nameplate1")
eq(f.P.Enabled(),true,"mutating external source entry does not mutate frozen epoch")
eq(f:last("UNIT_MATCH_ROW").tokenEpoch,2,"other entry epoch stays original")
local stable=false
for _,r in ipairs(f.records)do if r.kind=="UNIT_MATCH_ROW" and r.fields.unit=="nameplate1" then stable=r.fields.tokenEpoch==1 end end
eq(stable,true,"first frozen epoch remains one")
f.P.Command("off")
for _,event in ipairs({"NAME_PLATE_UNIT_REMOVED","NAME_PLATE_UNIT_ADDED"}) do
    local x=fixture();x:begin();x.P.OnEvent(event,"nameplate1")
    eq(x.P.Enabled(),true,event.." retires one address without stopping all observation")
    local invalid=x:last("UNIT_MATCH_INVALIDATED")
    eq(invalid.reason,event=="NAME_PLATE_UNIT_REMOVED" and "nameplate_removed" or "nameplate_added","event reason is exact")
    eq(invalid.triggerEvent,event,"triggering event is retained")
    eq(invalid.unit,"nameplate1","triggering address is retained")
    eq(invalid.currentEpoch,1,"before-event epoch has not advanced yet")
    x.epochs.nameplate1=9;x.tombstones.nameplate1=event=="NAME_PLATE_UNIT_REMOVED"
    x.P.OnAfterEvent(event,"nameplate1")
    eq(x:last("UNIT_MATCH_LIFECYCLE").stage,"after","after-event view is separate")
    eq(x:last("UNIT_MATCH_LIFECYCLE").currentEpoch,9,"after-event view sees the new epoch")
    eq(x:last("UNIT_MATCH_LIFECYCLE").frozenEpoch,1,"after-event view never rewrites the frozen epoch")
    x.P.Command("off")
end
for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT"}) do
    local x=fixture();x:begin();x.P.OnEvent(event)
    eq(x.P.Enabled(),false,event.." stops read-only observation")
end
f=fixture();f:begin();f.epochs.nameplate1=9;f.P.Tick(.5)
eq(f.P.Status().lastInvalidReason,"epoch_changed","missed lifecycle event is precisely caught by periodic validation")
eq(f:last("UNIT_MATCH_INVALIDATED").trigger,"periodic","missed event records the periodic source")
eq(f:last("UNIT_MATCH_INVALIDATED").currentEpoch,9,"changed epoch is recorded")
eq(f.P.Enabled(),true,"missed event does not end logging")
f.P.Command("off")
f=fixture();f:begin();f.units.nameplate2=nil;f.P.Tick(.5)
eq(f.P.Status().lastInvalidReason,"unit_missing","lost existence retires its address with exact reason")
eq(f.P.Enabled(),true,"lost existence preserves remaining observation")
f.P.Command("off")
f=fixture();f:begin();f.overrides.harm=function()return secret end;f.P.Command("sample")
eq(f.P.Status().lastInvalidReason,"attack_restricted","qualification secrecy has its exact API state")
eq(f:last("UNIT_MATCH_SAMPLE").twoUnitsObserved,false,"retired unknown qualifications never become positives")
f.P.Command("off")

-- Logger ownership and actual return values guard success and cleanup.
f=fixture();f:begin();local n=#f.records;f.session=f.session+1;f.P.Tick(.5)
eq(f.P.Status().reason,"log_changed","replaced session ends this observer")
eq(#f.records,n,"old observer never appends to the new log session")
eq(f.stops,0,"new session is never stopped")
eq(f.enabled,true,"new logger stays enabled")
f=fixture();f:begin();f.session=f.session+1
eq(f:begin(),false,"repeated on validates log ownership before claiming it is recording")
eq(f.stops,0,"repeated on does not stop a replacement log")
f=fixture();f:begin();f.enabled=false;f.P.Tick(.5)
eq(f.P.Status().reason,"log_off","external log stop ends observation")
eq(f.stops,0,"already stopped logger is not restarted or stopped again")
for _,kind in ipairs({"UNIT_MATCH_ROW","UNIT_MATCH_SAMPLE"}) do
    local x=fixture();x:begin();x.recordFail=kind;x:select("nameplate1")
    eq(x.P.Enabled(),false,kind.." false return terminates observer")
    eq(x.P.Status().distinctMatches,0,"failed write cannot update seen matches")
    eq(x.P.Status().twoUnitsObserved,false,"failed write cannot claim two-address evidence")
end
f=fixture();f:begin();f.recordError="UNIT_MATCH_ROW";f:select("nameplate1")
eq(f.P.Status().reason,"record_failed","record exception is contained")
f=fixture();f:begin();f:select("nameplate1")
f.recordFail="UNIT_MATCH_SAMPLE";f:select("nameplate2")
eq(f.P.Status().twoUnitsObserved,false,"second-address summary failure cannot claim completion")
f=fixture();f.recordFail="UNIT_MATCH_START"
eq(f:begin(),false,"start logging false is not a successful start")
eq(f.P.Enabled(),false,"failed start leaves no active probe")
f=fixture();f:begin();f.recordHook=function(kind)
    if kind=="UNIT_MATCH_ROW" then f.recordHook=nil;f.session=f.session+1 end
end
f:select("nameplate1")
eq(f.P.Status().reason,"log_changed","session change during a write is detected")
eq(f.P.Status().distinctMatches,0,"changed-session write cannot update matches")
eq(f.stops,0,"reentrant new logger is preserved")
f=fixture();f:begin();f.overrides.same=function(u)
    f.overrides.same=nil;f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate2");return true
end
local previous=f:count("UNIT_MATCH_SAMPLE");f:select("nameplate1")
eq(f.P.Enabled(),true,"lifecycle reentry retires an address and preserves the probe")
eq(f:count("UNIT_MATCH_SAMPLE"),previous,"stale API result produces no matching summary")
eq(f.P.Status().distinctMatches,0,"stale API result cannot become success")
f.P.Command("off")
f=fixture();f:begin();f.recordHook=function(kind)
    if kind=="UNIT_MATCH_ROW" then f.recordHook=nil;f.P.Command("off") end
end
f:select("nameplate1")
eq(f.P.Enabled(),false,"stop reentry during logging remains stopped")
eq(f.P.Status().distinctMatches,0,"stopped write cannot commit seen result")

f=fixture();f:begin();f.P.Tick(180)
eq(f.P.Status().reason,"timeout","elapsed bound stops automatically")
f=fixture();f:begin();for _=2,40 do f.P.Command("sample") end
eq(f.P.Status().samples,40,"sample bound records at most forty")
eq(f.P.Status().reason,"sample_limit","sample bound stops automatically")
f=fixture()
for i=3,25 do local u="nameplate"..i;f.tokens[#f.tokens+1]=u;f.units[u]={};f.epochs[u]=i end
eq(f:begin(),true,"large exposed roster can start")
eq(f.P.Status().units,20,"at most twenty native addresses are frozen")
f.P.Command("off")

-- Reproduce the observed failure class: an extra third address becomes
-- invalid 0.601 seconds after baseline, while the intended pair remains stable.
-- This is a model of the failure class, not a claim about session64's trigger.
local function addUnits(x,first,last)
    for i=first,last do local u="nameplate"..i;x.tokens[#x.tokens+1]=u;x.units[u]={};x.epochs[u]=i end
end
local function rowFor(x,unit)
    for i=#x.records,1,-1 do local r=x.records[i]
        if r.kind=="UNIT_MATCH_ROW" and r.fields.unit==unit then return r.fields end
    end
end
f=fixture();addUnits(f,3,3);f:begin();f.epochs.nameplate3=33;f.P.Tick(.601)
eq(f.P.Enabled(),true,"one changed address no longer stops the entire diagnostic")
eq(f.enabled,true,"one changed address leaves owned logging on")
eq(f.stops,0,"lifecycle retirement is not a logger stop")
eq(f.P.Status().validUnits,2,"the unaffected pair remains eligible")
local invalid=f:last("UNIT_MATCH_INVALIDATED")
eq(invalid.unit,"nameplate3","failed address is explicit")
eq(invalid.index,3,"failed test index is explicit")
eq(invalid.frozenEpoch,3,"frozen epoch remains original")
eq(invalid.currentEpoch,33,"observed changed epoch is explicit")
eq(invalid.reason,"epoch_changed","periodic epoch change has a precise reason")
eq(invalid.trigger,"periodic","failure source records periodic validation")
eq(invalid.lifecycleStatus,"public","IsCurrent public false is distinct from read errors")
eq(invalid.lifecycleCurrent,false,"actual false is preserved")
eq(f.P.Status().cohort,2,"first retirement advances the cohort")
f:select("nameplate1");f:select("nameplate2");f:flush()
eq(f.P.Status().twoUnitsObserved,true,"the unaffected pair can be observed in one new cohort")
eq(f:last("UNIT_MATCH_SAMPLE").validUnits,2,"summary describes the remaining set")
eq(f:last("UNIT_MATCH_SAMPLE").invalidUnits,1,"summary describes the retired set")
eq(rowFor(f,"nameplate3").qualifiedComparison,false,"retired address cannot contribute a match")
eq(rowFor(f,"nameplate3").retired,true,"retirement is explicit in every row")
f.P.Command("off")
eq(f:last("UNIT_MATCH_END").reason,"user","real stop cause remains separate from retirement")
eq(f:last("UNIT_MATCH_END").stopTrigger,"command_off","end records the actual stop trigger")
eq(f:last("UNIT_MATCH_END").lastInvalidUnit,"nameplate3","end retains the failing address")
eq(f:last("UNIT_MATCH_END").lastInvalidReason,"epoch_changed","end retains the failure reason")

-- Retired addresses do not revive when the API later appears healthy, and their
-- raw positive/unknown results cannot block or qualify a stable surviving pair.
f=fixture();addUnits(f,3,3);f:begin();f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate3")
f:select("nameplate1")
f.overrides.same=function(u) if u=="nameplate3" then return secret end;return f.units[u]==f.target end
f:select("nameplate2")
eq(f.P.Status().twoUnitsObserved,true,"retired unknown result does not block the stable remaining pair")
eq(f:last("UNIT_MATCH_SAMPLE").unknownCount,0,"qualified unknown count excludes retired addresses")
eq(f:last("UNIT_MATCH_SAMPLE").rawUnknownCount,1,"raw unknown remains recorded independently")
f.overrides.same=function(u) if u=="nameplate3" then return true end;return f.units[u]==f.target end
f.P.Command("sample")
eq(f:last("UNIT_MATCH_SAMPLE").rawTrueCount,2,"raw retired true remains observable")
eq(f:last("UNIT_MATCH_SAMPLE").qualifiedTrueCount,1,"retired true never enters qualified truth count")
eq(rowFor(f,"nameplate3").same,true,"raw positive of a retired current address is retained")
eq(rowFor(f,"nameplate3").qualifiedComparison,false,"a readable retired positive is still not an identity proof")
f.P.OnEvent("NAME_PLATE_UNIT_ADDED","nameplate3");f.epochs.nameplate3=303
f.P.OnAfterEvent("NAME_PLATE_UNIT_ADDED","nameplate3")
eq(f.P.Status().cohort,2,"repeated events on a retired address do not reset observation")
eq(f.P.Status().validUnits,2,"a reused address never becomes eligible again")
eq(f:count("UNIT_MATCH_INVALIDATED"),1,"one frozen address is retired only once")
eq(f:last("UNIT_MATCH_LIFECYCLE").currentEpoch,303,"reuse metadata stays visible")
eq(f:last("UNIT_MATCH_LIFECYCLE").frozenEpoch,3,"reuse does not replace frozen identity")
f.P.Command("off")

-- Each IsCurrent failure mode has its exact status. All-unknown addresses stay
-- in raw observation, rather than closing the log or claiming a positive.
for _,case in ipairs({
    {"error",function()error(secret)end},
    {"restricted",function()return secret end},
    {"nil",function()return nil end},
    {"nonboolean",function()return "true"end},
    {"public",function()return false end},
    {"unavailable",false},
}) do
    local x=fixture();x:begin()
    if case[2] then x.overrides.lifecycle=case[2] else x.NS.EnemyDisplay.IsCurrent=nil end
    x.P.Tick(.601)
    local failed=x:last("UNIT_MATCH_INVALIDATED")
    eq(failed.lifecycleStatus,case[1],case[1].." lifecycle status is preserved")
    eq(failed.reason,case[1]=="public" and "lifecycle_public_false" or "lifecycle_"..case[1],case[1].." lifecycle reason is exact")
    eq(x.P.Enabled(),true,case[1].." lifecycle read cannot prematurely stop observation")
    eq(x.P.Status().validUnits,0,case[1].." unreadable addresses are excluded")
    x:select("nameplate1")
    eq(x:last("UNIT_MATCH_SAMPLE").insufficientValidUnits,true,"all-retired sample explains insufficient valid units")
    eq(x:last("UNIT_MATCH_SAMPLE").rawTrueCount,1,"all-retired native raw comparison is still captured")
    eq(x.P.Status().twoUnitsObserved,false,"all-retired observations never become qualified evidence")
    x.P.Command("off")
end

-- Metadata failures cannot be mistaken for an actual epoch change.
for _,case in ipairs({
    {"error",function()error(secret)end},
    {"restricted",function()return secret end},
    {"nil",function()return nil end},
    {"nontable",function()return 7 end},
    {"unavailable",false},
}) do
    local x=fixture();x:begin();x.overrides.lifecycle=function()return false end
    if case[2] then x.overrides.metadata=case[2] else x.NS.EnemyDisplay.LifecycleState=nil end
    x.P.Tick(.5)
    eq(x:last("UNIT_MATCH_INVALIDATED").metadataStatus,case[1],case[1].." metadata status is explicit")
    eq(x:last("UNIT_MATCH_INVALIDATED").reason,"lifecycle_public_false","missing metadata never invents an epoch change")
    x.P.Command("off")
end
for _,case in ipairs({
    {"world_inactive",function(x)x.worldActive=false end},
    {"tombstoned",function(x)x.tombstones.nameplate2=true end},
    {"epoch_missing",function(x)x.epochs.nameplate2=nil end},
}) do
    local x=fixture();x:begin();case[2](x);x.P.Tick(.5)
    eq(x:last("UNIT_MATCH_INVALIDATED").reason,case[1],"metadata explains "..case[1])
    eq(x.P.Enabled(),true,"metadata failure retires rather than stops")
    x.P.Command("off")
end
f=fixture();f:begin();f.overrides.lifecycle=function()return false end
f.overrides.metadata=function()return {validToken=true,worldActive=secret,epochKnown=true,currentEpoch=secret,tombstoned=false}end
f.P.Tick(.5)
eq(f:last("UNIT_MATCH_INVALIDATED").worldActiveStatus,"restricted","secret metadata member is classified")
eq(f:last("UNIT_MATCH_INVALIDATED").worldActive,nil,"secret metadata member is not emitted")
eq(f:last("UNIT_MATCH_INVALIDATED").currentEpochStatus,"restricted","secret epoch member is classified")
eq(f:last("UNIT_MATCH_INVALIDATED").currentEpoch,nil,"secret epoch member is not emitted")
f.P.Command("off")

-- Qualification reads identify their exact failing API, without changing the
-- logger ownership or falsely treating unknown values as public false.
for _,case in ipairs({
    {"exists", "exists_error", function()error(secret)end},
    {"harm", "attack_nil", function()return nil end},
    {"player", "player_restricted", function()return secret end},
    {"harm", "not_attackable", function()return false end},
    {"player", "is_player", function()return true end},
}) do
    local x=fixture();x:begin();x.overrides[case[1]]=case[3];x.P.Tick(.5)
    eq(x:last("UNIT_MATCH_INVALIDATED").reason,case[2],"qualification reason "..case[2].." is retained")
    eq(x.P.Enabled(),true,"qualification failure remains an observed retirement")
    x.P.Command("off")
end

-- Group changes clear previous evidence and cancel old delayed reads. A pair
-- must be observed again under the stable survivor set.
f=fixture();addUnits(f,3,3);f:begin();f:select("nameplate1")
local sampleBefore=f.P.Status().samples
f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate3");f:flush()
eq(f.P.Status().samples,sampleBefore,"old-cohort delayed sample is discarded")
eq(f.P.Status().distinctMatches,0,"retirement resets the old cohort's positive history")
f:select("nameplate2")
eq(f.P.Status().distinctMatches,1,"new cohort does not combine its first match with old evidence")
f:select("nameplate1")
eq(f.P.Status().twoUnitsObserved,true,"new cohort can independently observe the pair")
f.P.Command("off")

for _,kind in ipairs({"UNIT_MATCH_ROW","UNIT_MATCH_SAMPLE"}) do
    local x=fixture();addUnits(x,3,3);x:begin();local n=x.P.Status().samples
    x.recordHook=function(k)
        if k==kind then x.recordHook=nil;x.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate3")end
    end
    x:select("nameplate1")
    eq(x.P.Enabled(),true,kind.." stale-cohort write is not a logger failure")
    eq(x.stops,0,"stale cohort never stops logging")
    eq(x.P.Status().samples,n,"stale sample cannot commit its sample counter")
    eq(x.P.Status().distinctMatches,0,"stale sample cannot commit its positive")
    x:select("nameplate1");x:select("nameplate2")
    eq(x.P.Status().twoUnitsObserved,true,"logging recovers in the new cohort")
    x.P.Command("off")
end

-- Repeated events have a separate bounded detail budget, while first retirement
-- records remain mandatory even after that budget has been used.
f=fixture();f:begin()
for _=1,100 do
    f.P.OnEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
    f.P.OnAfterEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
end
eq(f:count("UNIT_MATCH_LIFECYCLE"),120,"detail records are bounded")
eq(f:count("UNIT_MATCH_LIFECYCLE_LIMIT"),1,"limit has one explicit marker")
eq(f.P.Status().cohort,2,"duplicate events are idempotent")
f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate2")
eq(f:count("UNIT_MATCH_INVALIDATED"),2,"new first invalidation is retained beyond detail budget")
eq(f.P.Status().validUnits,0,"late retirement still takes effect")
eq(f.P.Enabled(),true,"detail budget does not end the comparison observer")
f.P.Command("off")

f=fixture();f:begin();f.P.MAX_LIFECYCLE_LOGS=1
f.P.OnEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
f.recordHook=function(kind)
    if kind=="UNIT_MATCH_LIFECYCLE_LIMIT" then f.recordHook=nil;f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate2")end
end
f.P.OnAfterEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
eq(f.P.Enabled(),true,"cohort change inside detail limit logging is not record failure")
eq(f.stops,0,"limit reentry preserves logging")
eq(f.P.Status().validUnits,0,"nested first retirement is still committed")
eq(f:count("UNIT_MATCH_INVALIDATED"),2,"nested mandatory invalidation is logged")
f.P.Command("off")

f=fixture();addUnits(f,3,4);f:begin()
f.recordHook=function(kind)
    if kind=="UNIT_MATCH_INVALIDATED" then f.recordHook=nil;f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate2")end
end
f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate1")
eq(f.P.Enabled(),true,"nested retirement inside an invalidation logger preserves observation")
eq(f.P.Status().cohort,3,"each distinct address advances the group once")
eq(f.P.Status().validUnits,2,"unaffected pair survives nested retirement")
f:select("nameplate3");f:select("nameplate4")
eq(f.P.Status().twoUnitsObserved,true,"nested retirement cannot prevent the remaining pair's proof")
f.P.Command("off")

for _,kind in ipairs({"UNIT_MATCH_INVALIDATED","UNIT_MATCH_LIFECYCLE","UNIT_MATCH_LIFECYCLE_LIMIT"})do
    local x=fixture();x:begin()
    if kind=="UNIT_MATCH_LIFECYCLE_LIMIT"then x.P.MAX_LIFECYCLE_LOGS=0 end
    x.recordFail=kind;x.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate1")
    eq(x.P.Enabled(),false,kind.." real write failure still terminates observation")
    eq(x.P.Status().reason,"record_failed","real diagnostic write failure is explicit")
    eq(x.P.Status().distinctMatches,0,"write failure leaves no qualified match")
end
f=fixture();f.recordHook=function(kind)
    if kind=="UNIT_MATCH_START"then f.recordHook=nil;f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate2")end
end
eq(f:begin(),true,"registration can survive a reentrant address retirement")
eq(f.P.Enabled(),true,"startup retirement keeps its owned observer running")
eq(f.P.Status().validUnits,1,"startup retirement is not silently revived")
f.P.Command("off")

f=fixture();local restarted
f.recordHook=function(kind)
    if kind=="UNIT_MATCH_START"then
        f.recordHook=nil;f.P.Command("off");restarted=f:begin()
    end
end
eq(f:begin(),false,"superseded startup does not claim to own the new observer")
eq(restarted,true,"startup record may explicitly start a newer observer")
eq(f.P.Enabled(),true,"older startup failure preserves the newer observer")
eq(f.session,2,"newer observer owns a distinct log session")
eq(f.enabled,true,"older startup cannot close the new log")
eq(f.stops,1,"only the explicit old observer stop ran")
eq(f.P.Status().logSession,2,"new observer ownership stays current")
f.P.Command("off")

f=fixture();f:begin();local recordsBefore=#f.records
f.P.OnEvent("NAME_PLATE_UNIT_REMOVED","nameplate9");f.P.OnAfterEvent("NAME_PLATE_UNIT_REMOVED","nameplate9")
eq(#f.records,recordsBefore,"untracked lifecycle events are ignored")
eq(f.P.Status().cohort,1,"untracked addresses do not reset the group")
f.P.Command("off")

-- The test sentinel cannot be stringified or compared; every recorded value
-- must instead be one bounded public scalar with no raw identity payload.
local publicOnly,identityFree,mutations=true,true,0
for _,scenario in ipairs(fixtures) do
    mutations=mutations+scenario.mutations
    for _,r in ipairs(scenario.records) do
        for k,v in pairs(r.fields) do
            if rawequal(v,secret) or type(v)=="table" or type(v)=="function" then publicOnly=false end
            if k=="name" or k=="guid" or k=="rawError" or k=="macroBody" then identityFree=false end
        end
    end
end
eq(publicOnly,true,"saved events contain only public scalars")
eq(identityFree,true,"probe never emits raw identity, macro or error fields")
eq(mutations,0,"all tested event paths remain free of protected or identity API calls")
print("Targets unit-match probe simulated checks: "..checks.."; real dungeon identity matching remains UNVERIFIED")
