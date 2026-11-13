-- Simulated public client values only. None of these fixtures are game data.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function ok(value, label) checks = checks + 1; assert(value, label) end
local secret = setmetatable({}, {
    __tostring=function() error("secret stringification") end,
    __lt=function() error("secret comparison") end, __le=function() error("secret comparison") end,
    __add=function() error("secret arithmetic") end, __eq=function() error("secret equality") end,
})
issecretvalue = function(value) return rawequal(value, secret) end
issecrettable = issecretvalue
canaccesstable = function(value) return not rawequal(value, secret) end
local now, epoch, combat, dead, mapID, level, xp, xpMax, restrictedNames
GetTime = function() return now end
GetServerTime = function() return epoch + now end
time = GetServerTime
GetBuildInfo = function() return "1.60.1", "70862", "test", 16001 end
GetLocale = function() return "zhCN" end
UnitClass = function() return "圣骑士", "PALADIN" end
UnitRace = function() return "人类", "Human" end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return level end
UnitXP = function() return xp end
UnitXPMax = function() return xpMax end
UnitAffectingCombat = function() return combat end
InCombatLockdown = function() return combat end
UnitIsDeadOrGhost = function() return dead end
IsInInstance = function() return false, "none" end
GetSpellInfo = function() return restrictedNames and secret or "圣光术" end
C_Spell = {GetSpellInfo=function() return {name=restrictedNames and secret or "圣光术"} end}
C_Map = {GetBestMapForUnit=function() return mapID end,
    GetMapInfo=function() return {name=restrictedNames and secret or "丹莫罗"} end}
DEFAULT_CHAT_FRAME = {AddMessage=function() end}
local cleuReads = 0
CombatLogGetCurrentEventInfo = function() cleuReads=cleuReads+1; error("forbidden API") end
C_CombatLog = {IsCombatLogRestricted=function() return true end}

local methods = {}
CreateFrame = function(_, name, parent)
    local frame = {scripts={}, registered={}, shown=true, name=name, parent=parent}
    return setmetatable(frame, {__index=methods})
end
function methods:SetScript(key, value) self.scripts[key]=value end
function methods:RegisterEvent(event)
    assert(event ~= "COMBAT_LOG_EVENT_UNFILTERED", "restricted event must stay disabled")
    self.registered[event]=true
end
function methods:IsEventRegistered(event) return self.registered[event] == true end
function methods:CreateFontString() return CreateFrame("Frame") end
function methods:SetText(value) self.text=value end
function methods:SetShown(value) self.shown=value end
function methods:Show() self.shown=true end
function methods:Hide() self.shown=false end
function methods:IsShown() return self.shown end
for _, method in ipairs({"SetPoint","SetSize","SetWidth","SetHeight","SetJustifyH","SetTextColor",
    "SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetFrameStrata","SetClampedToScreen",
    "SetMovable","EnableMouse","RegisterForDrag","StartMoving","StopMovingOrSizing","SetMultiLine",
    "SetAutoFocus","SetFontObject","SetMaxLetters","SetScrollChild","SetVerticalScroll","SetFocus",
    "ClearFocus","HighlightText"}) do methods[method]=function() end end
UIParent = CreateFrame("Frame")
SlashCmdList = {}

local root = "_forever_/Interface/AddOns/MyForeverCoach/"
local function fresh(startEpoch, saved, fullRuntime)
    now, epoch = 0, startEpoch or 1794355200
    combat, dead, mapID, level, xp, xpMax, restrictedNames = false, false, 1426, 9, 900, 1000, false
    MyForeverCoachDB = saved
    local ns = {}
    for _, source in ipairs({"Core.lua","Behavior.lua","Capture.lua","Export.lua"}) do
        assert(loadfile(root..source))("MyForeverCoach", ns)
    end
    if fullRuntime then
        for _, source in ipairs({"UI.lua","Main.lua"}) do assert(loadfile(root..source))("MyForeverCoach", ns) end
        ns.frame.scripts.OnEvent(ns.frame,"ADDON_LOADED","MyForeverCoach")
        ns.frame.scripts.OnEvent(ns.frame,"PLAYER_LOGIN")
    else ns.Initialize(); ns.StartSession() end
    return ns
end
local function today(ns) return ns.GetBehaviorToday() end
local function tick(ns, seconds) now=now+seconds; ns.SettleBehavior() end
local function cast(ns, event, unit, spell) ns.HandleEvent(event,unit,"FORBIDDEN_CAST_GUID",spell or 639,1) end

local ns = fresh()
eq(ns.VERSION,"0.2.0","candidate version")
eq(ns.db.schema,1,"root schema remains compatible")
eq(ns.db.behavior.schema,1,"independent daily schema")
eq(ns.db.behavior.dayBasis,"UTC+08:00","fixed day basis")
eq(ns.session.behavior.daily,true,"session marker prevents legacy detail from being added twice")
eq(ns.session.behavior.schema,1,"session marker is explicitly versioned")
eq(ns.BehaviorDate(0),"1970-01-01","epoch conversion")
eq(ns.BehaviorDate(1794326399),"2026-11-10","before local midnight")
eq(ns.BehaviorDate(1794326400),"2026-11-11","exact local midnight")
eq(ns.BehaviorDate(951753600),"2000-02-29","Gregorian leap day")
tick(ns,10)
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player")
cast(ns,"UNIT_SPELLCAST_FAILED","player")
cast(ns,"UNIT_SPELLCAST_INTERRUPTED","player")
cast(ns,"UNIT_SPELLCAST_START","player")
cast(ns,"UNIT_SPELLCAST_STOP","player")
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","pet")
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","target")
cast(ns,"UNIT_SPELLCAST_SUCCEEDED",secret)
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player",secret)
local d = today(ns)
eq(d.counts.castsSucceeded,1,"only public player success events count")
eq(d.counts.castsFailed,1,"failure separated")
eq(d.counts.castsInterrupted,1,"interruption separated")
eq(d.counts.castsStarted,1,"start separated; stop is not success")
eq(d.spells[639].succeeded,1,"spell-ID summary")
eq(d.spells[639].name,"圣光术","public spell name")
eq(d.maps[1426].name,"丹莫罗","public map name")
eq(d.time.observedSeconds,10,"observed duration")
eq(d.time.nonCombatSeconds,10,"idle duration is not AFK")
eq(d.maps[1426].seconds,10,"public map dwell")
eq(d.maps[1426].visits,1,"first observed map visit")
combat=true; ns.HandleEvent("PLAYER_REGEN_DISABLED")
tick(ns,5); ns.HandleEvent("PLAYER_REGEN_DISABLED")
tick(ns,5); combat=false; ns.HandleEvent("PLAYER_REGEN_ENABLED")
ns.HandleEvent("PLAYER_REGEN_ENABLED")
eq(d.counts.combatsEntered,1,"duplicate enter deduplicated")
eq(d.counts.combatsCompleted,1,"duplicate leave deduplicated")
eq(d.time.combatSeconds,10,"combat interval follows transition")
dead=true; ns.HandleEvent("PLAYER_DEAD"); ns.HandleEvent("PLAYER_DEAD")
eq(d.counts.deaths,1,"death event deduplicated")
dead=false; ns.HandleEvent("PLAYER_ALIVE"); ns.HandleEvent("PLAYER_UNGHOST")
eq(d.counts.deaths,1,"life events never count deaths")
dead=true; ns.HandleEvent("PLAYER_DEAD")
eq(d.counts.deaths,2,"next life can have another death")
xp=950; ns.Sample("xp")
eq(d.counts.xpGained,50,"continuous XP delta")
level,xp,xpMax=10,30,1200; ns.Sample("level_up")
eq(d.counts.xpGained,130,"one level rollover includes previous remaining XP")
eq(d.counts.levelsGained,1,"level count follows same baseline")
ns.Sample("duplicate")
eq(d.counts.xpGained,130,"duplicate snapshot does not add XP")
xp=secret; ns.Sample("restricted")
eq(d.quality.xpGaps,1,"missing XP breaks continuity once")
xp=300; ns.Sample("new_baseline")
eq(d.counts.xpGained,130,"restoring XP cannot fill an unknown gap")
xp=350; ns.Sample("continuous")
eq(d.counts.xpGained,180,"new baseline supports later delta")
ns.HandleEvent("QUEST_ACCEPTED",101)
ns.HandleEvent("QUEST_TURNED_IN",101,9000,100)
eq(d.counts.questsAccepted,1,"accepted task")
eq(d.counts.questsTurnedIn,1,"turned in task")
eq(d.counts.xpGained,180,"quest reward not counted on top of XP delta")

tick(ns,7); ns.SetEnabled(false)
local observed, beforeXP, successes = d.time.observedSeconds,d.counts.xpGained,d.counts.castsSucceeded
tick(ns,30); xp=900; cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player")
combat=true; ns.HandleEvent("PLAYER_REGEN_DISABLED")
eq(d.time.observedSeconds,observed,"pause excludes observed time")
eq(d.time.pausedSeconds,30,"paused duration is separate")
eq(d.counts.castsSucceeded,successes,"pause excludes player actions")
eq(d.counts.xpGained,beforeXP,"pause excludes XP")
ns.SetEnabled(true)
xp=950; ns.Sample("resumed")
eq(d.counts.xpGained,beforeXP+50,"resume establishes new XP baseline")
eq(d.counts.combatsEntered,1,"paused combat entry not backfilled")
tick(ns,5)
eq(d.time.combatSeconds,15,"resume uses current public combat baseline")
mapID=1427; ns.Sample("map_changed"); tick(ns,4)
eq(d.maps[1427].seconds,4,"map dwell changes after public observation")
eq(d.maps[1427].visits,1,"new map visit")
while #ns.session.records<ns.LIMITS.records do ns.Record("control",{}) end
local before = d.counts.castsSucceeded
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player")
tick(ns,6)
eq(#ns.session.records,1200,"raw detail remains bounded")
eq(d.counts.castsSucceeded,before+1,"full detail cannot stop cumulative actions")
ok(d.quality.detailDropped>0,"full detail is disclosed in quality")
eq(d.maps[1427].seconds,10,"full detail cannot stop map dwell")
local previousGeneration=ns.db.behavior.generation
local saved=ns.db
saved.behavior.FORBIDDEN_PRIVATE_PAYLOAD="FORBIDDEN_PRIVATE_PAYLOAD"
d.spells[639].FORBIDDEN_PRIVATE_PAYLOAD="FORBIDDEN_PRIVATE_PAYLOAD"
d.counts.FORBIDDEN_PRIVATE_PAYLOAD=1234
local exported=assert(ns.ExportSession())
ok(not exported:find("FORBIDDEN_",1,true),"new export projection excludes arbitrary payloads and cast GUID")
ok(exported:find('"behavior"',1,true),"export includes daily cumulative layer")
ns.StopSession("logout")
local stoppedSeconds=d.time.observedSeconds
tick(ns,10)
eq(d.time.observedSeconds,stoppedSeconds,"logout settles once and stops all timers")
ns=fresh(nil,saved)
eq(ns.db.behavior.generation,previousGeneration,"generation remains stable across reload")
eq(ns.db.behavior.days["2026-11-11"].counts.castsSucceeded,before+1,"reload retains day totals")
eq(ns.db.behavior.FORBIDDEN_PRIVATE_PAYLOAD,nil,"migration strips unknown root behavior fields")
eq(ns.db.behavior.days["2026-11-11"].spells[639].FORBIDDEN_PRIVATE_PAYLOAD,nil,"migration strips arbitrary spell fields")
ok(#ns.db.sessions>=2,"legacy diagnostic sessions retained")

ns=fresh(1794326390); tick(ns,20)
eq(ns.db.behavior.days["2026-11-10"].time.observedSeconds,10,"pre-midnight interval")
eq(ns.db.behavior.days["2026-11-11"].time.observedSeconds,10,"post-midnight interval")
eq(ns.db.behavior.days["2026-11-10"].maps[1426].seconds,10,"map interval split before midnight")
eq(ns.db.behavior.days["2026-11-11"].maps[1426].seconds,10,"map interval split after midnight")
ns.SetEnabled(false); tick(ns,86400+4)
eq(ns.db.behavior.days["2026-11-11"].time.pausedSeconds,86390,"paused midnight split first day")
eq(ns.db.behavior.days["2026-11-12"].time.pausedSeconds,14,"paused midnight split next day")

ns=fresh(); level,xp,xpMax=12,10,1600; ns.Sample("skipped_levels")
d=today(ns)
eq(d.counts.xpGained,0,"multi-level gap does not invent intermediate experience")
eq(d.counts.levelsGained,3,"public multi-level difference remains countable")
eq(d.quality.xpGaps,1,"multi-level experience gap marked")
ns.StopSession("restart"); xp=secret; ns.StartSession(); ns.Sample("still_missing")
eq(d.quality.xpGaps,2,"unavailable initial XP baseline is disclosed once")
ns.Sample("still_missing_again")
eq(d.quality.xpGaps,2,"repeated unavailable XP does not inflate gap count")

ns=fresh(); ns.StopSession("reset")
combat,mapID,restrictedNames=secret,secret,true
ns.StartSession(); tick(ns,8); cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player")
d=today(ns)
eq(d.time.unknownCombatSeconds,8,"secret combat status remains unknown")
eq(d.quality.unknownMapSeconds,8,"secret map produces unknown dwell")
eq(d.spells[639].name,nil,"secret public spell name not stored")
eq(cleuReads,0,"restricted combat log API never called")

ns=fresh()
for index=1,140 do cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player",index) end
d=today(ns)
local entries=0; for _ in pairs(d.spells) do entries=entries+1 end
eq(entries,128,"spell distribution bounded per day")
eq(d.counts.castsSucceeded,140,"spell limit does not reduce success total")
eq(d.quality.spellOverflow,12,"omitted spell details disclosed separately")
eq(d.quality.detailDropped,0,"distribution overflow is not raw record loss")
for index=1,140 do mapID=10000+index; ns.Sample("zone"); tick(ns,1) end
entries=0; for _ in pairs(d.maps) do entries=entries+1 end
eq(entries,128,"map distribution bounded per day")
ok(d.quality.unknownMapSeconds>0,"map overflow discloses undistributed dwell")
ok(d.quality.mapOverflow>0,"map overflow is separately marked")
local beforeTime=d.time.observedSeconds
eq(beforeTime,140,"map limit does not reduce observed total")
tick(ns,91*86400)
local days=0; for _ in pairs(ns.db.behavior.days) do days=days+1 end
ok(days<=90,"daily retention remains bounded on long gap")
eq(ns.db.behavior.days["2026-11-11"],nil,"old day expires")

ns=fresh(nil,nil,true)
ok(ns.panel.overview:IsShown() and not ns.panel.diagnostics:IsShown(),"default game view is behavior overview")
eq(SLASH_MYFOREVERCOACH3,"/mybehavior","new command alias")
eq(SLASH_MYFOREVERCOACH1,"/mycoach","legacy command alias")
SlashCmdList.MYFOREVERCOACH("diagnostics")
ok(ns.panel.diagnostics:IsShown() and not ns.panel.overview:IsShown(),"capability matrix remains secondary view")
SlashCmdList.MYFOREVERCOACH("show")
ok(ns.panel.overview:IsShown(),"show returns to behavior overview")
tick(ns,10)
d=today(ns)
ns.frame.scripts.OnEvent(ns.frame,"ADDON_ACTION_FORBIDDEN","MyForeverCoach","SomeAPI()")
eq(ns.db.settings.enabled,false,"native forbidden event stops sampling")
local finalTime=d.time.observedSeconds
now=now+15; ns.frame.scripts.OnUpdate(ns.frame,15)
cast(ns,"UNIT_SPELLCAST_SUCCEEDED","player")
eq(d.time.observedSeconds,finalTime,"safety stop freezes behavioral time")
eq(d.counts.castsSucceeded,0,"safety stop excludes later actions")
eq(ns.SetEnabled(true),false,"safety stop cannot be resumed in same load")
eq(cleuReads,0,"full runtime preserves combat-log prohibition")

print("behavior_test: "..checks.." checks passed (simulated; not in-game validation)")
return exported
