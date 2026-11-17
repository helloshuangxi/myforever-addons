-- Bounded observation contracts only; no game state, CVar or secure writes.
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local checks,clock=0,10
local secret=setmetatable({}, {__tostring=function() error("secret string conversion") end})
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
issecretvalue=function(value) return value==secret end
GetTime=function() return clock end
GetServerTime=function() return 456 end
InCombatLockdown=function() return true end
UnitExists=function() return false end
GetMouseFoci=function() return {} end
CreateFrame=function()
    return {events={},scripts={},RegisterEvent=function(self,event) self.events[event]=true end,
        SetScript=function(self,event,fn) self.scripts[event]=fn end}
end
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Diagnostics.lua"))("MyForeverTargets",NS)
local D=NS.Diagnostics
local observations=0
IsInInstance=function() observations=observations+1;return true,"party" end
local values={nameplateShowEnemies="1",nameplateShowAll="0"}
C_CVar={GetCVar=function(key) observations=observations+1;return values[key] end,
    SetCVar=function() error("diagnostics must never write CVars") end}
local summary={rawTokens=105,nameplateTokens=5,uniqueValid=3,displayed=3,actionable=1,limit=5,
    restrictedTokens=2,restrictedDisplayed=1,nameRenderErrors=0,
    rosterMode="combat_display",invalid_token=0,no_exists=98,exists_unknown=0,player_unknown=1,
    not_friendly=0,cannot_attack=1,attack_unknown=0,guid_unreadable=1,name_unreadable=0,visibility=0,duplicate=1}
local function snapshots()
    local result={}
    for _,event in ipairs(MyForeverTargetsLogDB.events) do
        if event.kind=="INSTANCE_ENEMY_ROSTER" then result[#result+1]=event end
    end
    return result
end
local function latest() local records=snapshots();return records[#records] end
D.Initialize()
eq(D.Enabled(),false,"diagnostics do not auto-enable for instance repair")
eq(D.EnemyRosterSnapshot(summary),false,"stopped logger does not create roster records")
eq(observations,0,"disabled roster logging does not call instance or CVar APIs")
D.Start()
eq(D.EnemyRosterSnapshot(summary),true,"first actual collection is logged")
local fields=latest().fields
eq(fields.inInstance,true,"instance state read from game API")
eq(fields.instanceType,"party","instance type does not guess from combat")
eq(fields.combat,true,"combat state is independent from instance state")
eq(fields.nameplateShowEnemies,"1","enemy visibility CVar observed without mutation")
eq(fields.nameplateShowAll,"0","all-nameplates CVar observed separately")
eq(fields.discovered,3,"discovered is accepted unique identities")
eq(fields.rawTokens,105,"raw attempts are kept separate from accepted identities")
eq(fields.displayed,3,"rendered count kept separate from discoveries")
eq(fields.actionable,1,"armed input count kept separate from displayed cells")
eq(fields.restrictedTokens,2,"restricted native addresses are not public GUID identities")
eq(fields.restrictedDisplayed,1,"actual native restricted display has its own count")
eq(fields.nameRenderErrors,0,"native name setter failure count is separate from discoveries")
eq(fields.guid_unreadable,1,"identity rejection count retained")
eq(fields.reason,"initial","first sample is labelled")
eq(fields.observationOnly,true,"snapshot does not assert a protected action")
eq(D.EnemyRosterSnapshot(summary),false,"identical state does not flood history")
clock=11;summary.displayed=2
eq(D.EnemyRosterSnapshot(summary),false,"quick state changes coalesce inside minimum interval")
clock=12
eq(D.EnemyRosterSnapshot(summary),true,"latest changed state is recorded after bounded delay")
eq(latest().fields.reason,"changed","changed sample is labelled")
eq(latest().fields.displayed,2,"coalescing retains latest actual display count")
clock=41.9
eq(D.EnemyRosterSnapshot(summary),false,"unchanged state has no early heartbeat")
clock=42
eq(D.EnemyRosterSnapshot(summary),true,"unchanged state gets finite heartbeat")
eq(latest().fields.reason,"heartbeat","heartbeat sample is labelled")
local before=#snapshots()
for i=1,1000 do
    clock=42+i*.01
    summary.displayed=i%2
    D.EnemyRosterSnapshot(summary)
end
eq(#snapshots()-before<=5,true,"thousand fast changes cannot fill the 5000-record history")
D.Stop("test")
local disabledCount,disabledReads=#snapshots(),observations
clock=1000;summary.displayed=3
eq(D.EnemyRosterSnapshot(summary),false,"explicit stop persists through later roster polls")
eq(#snapshots(),disabledCount,"stopped log history remains unchanged")
eq(observations,disabledReads,"stopped polling performs no diagnostic API reads")

-- Starting a new deliberate session resets rate state without enabling itself.
IsInInstance=function() return false,"none" end
InCombatLockdown=function() return false end
D.Start()
eq(D.EnemyRosterSnapshot(summary),true,"new session can record the same state immediately")
eq(latest().fields.inInstance,false,"false instance state remains false, not unknown")
eq(latest().fields.instanceType,"none","outdoor type is retained")
eq(latest().fields.combat,false,"false combat state is retained")
local beforeRestricted=#snapshots()
eq(D.EnemyRosterSnapshot(secret),false,"restricted summary is not indexed")
eq(#snapshots(),beforeRestricted,"restricted summary does not invent a record")

-- Restricted/throwing inputs are scalar markers. Unknown keys and raw text
-- cannot become a covert macro/chat/error serializer.
clock=1002
summary.rawTokens=secret;summary.guid_unreadable=secret;summary.displayed=30
summary.actionable=-1;summary.limit=5.5;summary.restrictedDisplayed=secret;summary.nameRenderErrors=30
summary.rosterMode="/cast 私有宏正文"
summary.chat="私聊内容";summary.macroBody="/cast 私有宏正文"
summary.name="角色私人名字";summary.guid="Creature-private"
IsInInstance=function() return secret,secret end
InCombatLockdown=function() return secret end
values.nameplateShowEnemies=secret;values.nameplateShowAll="私聊内容"
eq(D.EnemyRosterSnapshot(summary),true,"restricted fields do not abort observation")
fields=latest().fields
eq(fields.rawTokens,"[restricted]","secret counters are never compared or formatted")
eq(fields.guid_unreadable,"[restricted]","secret rejection counter is labelled")
eq(fields.displayed,"[invalid-count]","displayed count cannot exceed twenty")
eq(fields.actionable,"[invalid-count]","negative action count rejected")
eq(fields.limit,"[invalid-count]","fractional display capacity rejected")
eq(fields.restrictedDisplayed,"[restricted]","restricted counter value cannot be formatted into diagnostic state")
eq(fields.nameRenderErrors,"[invalid-count]","render failure count cannot exceed twenty cells")
eq(fields.rosterMode,"[unknown]","mode copies only predefined labels")
eq(fields.inInstance,"[restricted]","secret instance flag redacted")
eq(fields.instanceType,"[restricted]","secret instance type redacted")
eq(fields.combat,"[restricted]","secret combat flag redacted")
eq(fields.nameplateShowEnemies,"[restricted]","secret CVar redacted")
eq(fields.nameplateShowAll,"[unknown]","arbitrary CVar text never copied")
for _,key in ipairs({"chat","macroBody","name","guid"}) do
    eq(fields[key],nil,"unrecognized personal field excluded: "..key)
end
clock=1004
IsInInstance=function() error("private stack text must not enter log") end
C_CVar.GetCVar=function() error("private CVar error text") end
eq(D.EnemyRosterSnapshot(summary),true,"API exceptions are observed without throwing")
eq(latest().fields.inInstance,"[api-error]","instance error gets a fixed marker")
eq(latest().fields.instanceType,"[api-error]","instance type error gets a fixed marker")
eq(latest().fields.nameplateShowEnemies,"[api-error]","CVar error gets a fixed marker")
clock=1006
local hostile=setmetatable({}, {__index=function() error("arbitrary private details") end})
eq(D.EnemyRosterSnapshot(hostile),true,"metatable indexing failures are isolated")
eq(latest().fields.rawTokens,"[api-error]","summary indexing error gets a fixed marker")
eq(latest().fields.rosterMode,"[unknown]","bad summary cannot provide a mode")
clock=1008
local originalRecord=D.Record
D.Record=function() error("storage unavailable") end
eq(D.EnemyRosterSnapshot(summary),false,"logger exception cannot escape into Main")
D.Record=originalRecord

-- When the native clock is absent, the existing enabled logger timer advances
-- the finite heartbeat. No standalone timer or logging state is created.
GetTime=nil;IsInInstance=nil;C_CVar=nil;GetCVar=nil
InCombatLockdown=function() return false end
D.Start()
summary.rawTokens=105;summary.guid_unreadable=1;summary.displayed=3;summary.actionable=1
summary.limit=5;summary.rosterMode="bound"
eq(D.EnemyRosterSnapshot(summary),true,"missing APIs still allow bounded scalar snapshot")
eq(latest().fields.inInstance,"[unavailable]","missing instance API is not guessed")
eq(latest().fields.nameplateShowEnemies,"[unavailable]","missing CVar API is not guessed")
D.frame.scripts.OnUpdate(D.frame,30)
eq(D.EnemyRosterSnapshot(summary),true,"existing logger elapsed timer supplies heartbeat fallback")
eq(latest().fields.reason,"heartbeat","fallback clock still has finite heartbeat")
D.Stop("test")
print("Targets instance diagnostics simulated checks: "..checks)
