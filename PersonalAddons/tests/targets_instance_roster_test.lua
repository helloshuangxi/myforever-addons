-- Real collection/Main transitions; simulated rendering does not prove native
-- protected execution, mouse input or instance APIs in the game.
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local checks,combat,logging=0,false,true
local units,NS={},{}
local secret={}
local restrictedGUID,restrictedName="Restricted-native-guid","Restricted-native-name"
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
issecretvalue=function(value) return value==secret or value==restrictedGUID or value==restrictedName end
InCombatLockdown=function() return combat end
UnitExists=function(unit)
    local u=units[unit]
    if not u then return false end
    if u.exists~=nil then return u.exists end
    return true
end
UnitGUID=function(unit) local u=units[unit];return u and u.guid end
UnitName=function(unit) local u=units[unit];return u and u.name end
UnitIsPlayer=function(unit) local u=units[unit];if u then return u.player end end
UnitCanAttack=function(_,unit) local u=units[unit];if u then return u.attack end end
UnitCanAssist=function(_,unit) local u=units[unit];if u then return u.friend end end
UnitIsVisible=function(unit) local u=units[unit];if u then return u.visible end end
UnitIsDeadOrGhost=function() return false end
GetRaidTargetIndex=function() return nil end
CreateFrame=function()
    return {events={},scripts={},RegisterEvent=function(self,event) self.events[event]=true end,
        SetScript=function(self,event,fn) self.scripts[event]=fn end}
end
SlashCmdList={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Units.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."EnemyDisplay.lua"))("MyForeverTargets",NS)
NS.Print=function() end
NS.SetDetectionEnabled=function() end
local bound={friendly=0,enemy=0}
local function panel()
    return {Show=function() assert(not combat,"protected Show in combat") end,
        Hide=function() assert(not combat,"protected Hide in combat") end,
        IsShown=function() return true end,
        SetScale=function() assert(not combat,"protected SetScale in combat") end}
end
NS.CreateUI=function()
    NS.UI={}
    for _,side in ipairs({"friendly","enemy"}) do
        local section={frame=panel(),tiles={},limit=5}
        NS.UI[side]=section
        for i=1,20 do
            local shield={shown=true,IsShown=function(self) return self.shown end}
            section.tiles[i]={side=side,shield=shield,attributes={},
                GetAttribute=function(self,key) return self.attributes[key] end,
                SetAttribute=function(self,key,value)
                    assert(not combat,"protected attribute write in combat")
                    self.attributes[key]=value
                end,
                SetPoint=function() assert(not combat,"protected anchor write in combat") end,
                Show=function() assert(not combat,"protected row Show in combat") end}
        end
    end
end
NS.BindTiles=function(side,tokens,limit)
    assert(not combat,"secure BindTiles in combat")
    bound[side]=bound[side]+1
    local section=NS.UI[side];section.limit=limit
    for i,row in ipairs(section.tiles) do
        row.unit=tokens[i]
        assert(not row.unit or not NS.ReadRestrictedEnemyVisual
            or not NS.ReadRestrictedEnemyVisual(row.unit),"restricted token passed to secure BindTiles")
        local data=row.unit and NS.ReadUnit(row.unit,side)
        row.expectedGUID=data and data.guid
        row:SetAttribute("unit",row.unit)
    end
end
NS.RefreshControls=function() assert(not combat,"secure controls in combat") end
NS.RefreshTiles=function()
    for _,side in ipairs({"friendly","enemy"}) do
        local section=NS.UI[side]
        section.validCount,section.actionableCount,section.restrictedCount,section.nameRenderErrors=0,0,0,0
        for i,row in ipairs(section.tiles) do
            local visual=side=="enemy" and NS.EnemyDisplay.active
            local slot=visual and NS.EnemyDisplay.Get(i) or nil
            local unit=visual and slot and slot.unit or not visual and row.unit or nil
            local guid=visual and slot and slot.guid or not visual and row.expectedGUID or nil
            local data=unit and NS.ReadUnit(unit,side)
            local restricted=slot and slot.restrictedIdentity==true and NS.ReadRestrictedEnemyVisual(unit)
            row.data=i<=section.limit and data and data.guid==guid and data or nil
            row.displayActionReady=visual and row.data~=nil and row.data.guid==row.expectedGUID
                and UnitGUID(row.unit)==row.expectedGUID or nil
            row.shield.shown=not (row.data and (not visual or row.displayActionReady==true))
            if i<=section.limit and row.data then
                section.validCount=section.validCount+1
                if not row.shield.shown then section.actionableCount=section.actionableCount+1 end
            elseif i<=section.limit and restricted then
                -- Only a rendering-count model; the production UI suite checks
                -- actual label/native-bar sinks and both input shields.
                row.data,row.displayActionReady=nil,false
                row.shield.shown=true
                section.validCount=section.validCount+1
                section.restrictedCount=section.restrictedCount+1
            end
        end
    end
end
local snapshots={}
NS.Diagnostics={Initialize=function() end,Enabled=function() return logging end,
    EnemyRosterSnapshot=function(summary) snapshots[#snapshots+1]=summary end}
local collect=NS.Collect
local collected={friendly=0,enemy=0,diagnosed=0}
NS.Collect=function(side,mode,limit,diagnose)
    collected[side]=collected[side]+1
    if diagnose then collected.diagnosed=collected.diagnosed+1 end
    return collect(side,mode,limit,diagnose)
end
local function mob(token,guid,name)
    units[token]={guid=guid,name=name or "同名副本怪",player=false,attack=true,visible=true}
end
MyForeverTargetsDB={enemyLimit=5,friendlyTab="party"}
assert(loadfile(root.."Main.lua"))("MyForeverTargets",NS)
NS.HandleEvent("ADDON_LOADED","MyForeverTargets")
NS.HandleEvent("PLAYER_ENTERING_WORLD")
eq(NS.Totals.enemy,0,"pre-pull empty roster is real, not a retained enemy")
local initialBindings=bound.enemy
local initialFriendly=collected.friendly
combat=true
NS.HandleEvent("PLAYER_REGEN_DISABLED")
mob("nameplate7","Creature-instance-a")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate7")
eq(NS.EnemyDisplay.active,true,"enemy display activates while combat blocks secure binding")
eq(NS.EnemyDisplay.Get(1).guid,"Creature-instance-a","first enemy discovered after pull appears")
eq(NS.UI.enemy.validCount,1,"actual visual count updates after empty pre-pull roster")
eq(NS.UI.enemy.tiles[1].unit,nil,"new display identity does not rewrite protected unit")
eq(NS.UI.enemy.tiles[1].expectedGUID,nil,"new display does not invent protected GUID")
eq(NS.UI.enemy.tiles[1].shield:IsShown(),true,"new enemy is not an armed action")
eq(bound.enemy,initialBindings,"combat events never call BindTiles")
eq(collected.friendly,initialFriendly,"friendly combat roster retains its old path")
eq(snapshots[#snapshots].displayed,1,"diagnostics count actual rendered enemy")
eq(snapshots[#snapshots].actionable,0,"diagnostics distinguish display from actions")
eq(snapshots[#snapshots].rosterMode,"combat_display","diagnostics label combat display")
local beforeStatus=collected.enemy
NS.HandleEvent("UNIT_HEALTH","nameplate7")
eq(collected.enemy,beforeStatus,"high volume status event does not immediately recollect")
NS.EventFrame.scripts.OnUpdate(NS.EventFrame,.1)
eq(collected.enemy,beforeStatus,"10 Hz visual pass stays separate from roster pass")
mob("nameplate9","Creature-instance-b") -- Simulate a missed NAME_PLATE event.
NS.EventFrame.scripts.OnUpdate(NS.EventFrame,.4)
eq(NS.Totals.enemy,2,"half-second combat poll finds an exposed unit with missed event")
eq(NS.UI.enemy.validCount,2,"missed-event enemy reaches visible cells")
units.nameplate7=nil
NS.HandleEvent("NAME_PLATE_UNIT_REMOVED","nameplate7")
eq(NS.UI.enemy.validCount,1,"departed enemy is removed during the same combat")
mob("nameplate9","Creature-instance-c")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate9")
eq(NS.EnemyDisplay.Get(1).guid,"Creature-instance-c","reused token updates to fresh GUID")
eq(NS.UI.enemy.tiles[1].unit,nil,"reuse still never replaces protected identity")
mob("nameplate10","Creature-instance-d")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate10")
eq(NS.UI.enemy.validCount,2,"two same-name monsters remain separate by GUID")
for i=1,25 do mob("nameplate"..i,"Creature-many-"..i) end
NS.DB.enemyLimit=20 -- A pending request must not resize the prepared five-slot panel.
NS.RequestRefresh()
eq(NS.Totals.enemy,25,"combat totals count candidates before the display limit")
eq(NS.UI.enemy.validCount,5,"combat uses the actual prepared panel capacity")
eq(NS.EnemyDisplay.Get(6),nil,"no hidden sixth display slot under five-cell panel")
eq(NS.UI.enemy.limit,5,"combat display does not change section capacity")
eq(bound.enemy,initialBindings,"all repeated combat swaps keep secure bindings frozen")
local refresh=NS.RefreshTiles
NS.RefreshTiles=function()
    refresh()
    NS.UI.enemy.validCount,NS.UI.enemy.actionableCount=0,0
end
NS.RequestRefresh()
eq(snapshots[#snapshots].uniqueValid,25,"discovery total remains distinct from rendering")
eq(snapshots[#snapshots].displayed,0,"rendered count is authoritative even with candidate row data")
NS.RefreshTiles=refresh
logging=false
local previousSnapshots,previousDiagnosed=#snapshots,collected.diagnosed
NS.RequestRefresh()
eq(#snapshots,previousSnapshots,"disabled logger does not generate roster events")
eq(collected.diagnosed,previousDiagnosed,"disabled logger does not request collection statistics")
eq(NS.UI.enemy.validCount,5,"display continues while logging is disabled")
logging=true
local oldSnapshot=NS.Diagnostics.EnemyRosterSnapshot
NS.Diagnostics.EnemyRosterSnapshot=function() error("observer unavailable") end
eq(pcall(NS.RequestRefresh),true,"diagnostic exception cannot abort combat display")
NS.Diagnostics.EnemyRosterSnapshot=oldSnapshot
combat=false;NS.DB.enemyLimit=5
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.EnemyDisplay.active,false,"combat end clears the independent display roster")
eq(NS.EnemyDisplay.Get(1),nil,"no stale visual slot survives reset")
eq(bound.enemy>initialBindings,true,"combat end prepares normal secure bindings")
eq(NS.UI.enemy.tiles[1].expectedGUID~=nil,true,"out-of-combat cell gets its normal identity")
eq(NS.UI.enemy.actionableCount,5,"normal actions are counted only after preparation")
eq(snapshots[#snapshots].rosterMode,"bound","post-combat diagnostic reports normal bindings")

-- One collection supplies both the chosen roster and all rejection counters.
units={};NS.Nameplates={}
mob("nameplate1","Creature-good")
for i=1,8 do NS.Nameplates["nameplate"..i]=true end
mob("nameplate2","Creature-player-opaque");units.nameplate2.player=secret
mob("nameplate3","Creature-attack-opaque");units.nameplate3.attack=secret
mob("nameplate4",secret)
mob("nameplate5","Creature-name-opaque");units.nameplate5.name=secret
mob("nameplate6","Creature-exists-opaque");units.nameplate6.exists=secret
mob("nameplate7","Creature-not-attackable");units.nameplate7.attack=false
mob("nameplate8","Creature-not-existing");units.nameplate8.exists=false
mob("boss1","Creature-hidden-boss");units.boss1.visible=secret
units.target=units.nameplate1
local list,total,summary=collect("enemy","enemy",20,true)
eq(total,1,"same-round statistics do not relax any rejection filter")
eq(#list,1,"only the public attackable identity enters the roster")
eq(summary.uniqueValid,1,"statistics report accepted unique identities")
eq(summary.nameplateTokens,8,"raw nameplate count includes unavailable entries")
eq(summary.player_unknown,1,"unknown player flag is counted")
eq(summary.attack_unknown,1,"unknown attackability is counted")
eq(summary.guid_unreadable,1,"restricted GUID is counted without copying it")
eq(summary.name_unreadable,1,"restricted name is counted without copying it")
eq(summary.exists_unknown,1,"restricted existence is distinct from false")
eq(summary.cannot_attack,1,"known non-attackable unit is rejected")
eq(summary.visibility,1,"non-nameplate alias needs public visibility")
eq(summary.duplicate,1,"same GUID aliases are counted once")
eq(summary.no_exists>=1,true,"missing aliases are counted")
local rejected=0
for _,key in ipairs({"invalid_token","no_exists","exists_unknown","player_unknown","not_friendly",
    "cannot_attack","attack_unknown","guid_unreadable","name_unreadable","visibility","duplicate"}) do
    rejected=rejected+summary[key]
end
eq(rejected+summary.uniqueValid,summary.rawTokens,"every attempted token has exactly one result")
local _,_,off=collect("enemy","enemy",20,false)
eq(off,nil,"statistics remain optional for non-diagnostic callers")

-- Exact failure class from session61: party-instance NPC GUID/name restricted,
-- while the unit and its enemy classification remain publicly readable.
units={};NS.Nameplates={}
mob("nameplate1",restrictedGUID,restrictedName)
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
eq(NS.EnemyDisplay.active,true,"OOC restricted instance enemy activates only visual roster")
eq(NS.UI.enemy.validCount,1,"restricted enemy is displayed even before combat")
eq(NS.UI.enemy.restrictedCount,1,"restricted display counted separately")
eq(NS.UI.enemy.actionableCount,0,"restricted identity never becomes actionable")
eq(NS.UI.enemy.tiles[1].unit,nil,"anonymous address is not passed to secure binding")
eq(NS.UI.enemy.tiles[1].expectedGUID,nil,"token is not substituted for inaccessible GUID")
eq(NS.UI.enemy.tiles[1].data,nil,"secret payload stays outside public row data")
eq(NS.UI.enemy.tiles[1].shield:IsShown(),true,"restricted OOC input remains shielded")
eq(snapshots[#snapshots].uniqueValid,0,"opaque enemy does not invent public identity")
eq(snapshots[#snapshots].restrictedTokens,1,"observed native display address is counted")
eq(snapshots[#snapshots].restrictedDisplayed,1,"actual restricted display count is reported")
eq(snapshots[#snapshots].displayed,1,"total display includes native restricted visual")
units.target=units.nameplate1
NS.RequestRefresh()
eq(NS.UI.enemy.validCount,1,"target alias does not create an additional anonymous slot")
NS.HandleEvent("NAME_PLATE_UNIT_REMOVED","nameplate1") -- OOC Reset must keep its tombstone.
eq(NS.UI.enemy.validCount,0,"OOC removal cannot repopulate a lagging nameplate")
NS.RequestRefresh()
eq(NS.UI.enemy.validCount,0,"OOC roster Reset does not erase removed-token tombstone")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
eq(NS.UI.enemy.validCount,1,"OOC new addition reopens the removed display address")
local beforeRestrictedCombat=bound.enemy
combat=true
NS.HandleEvent("PLAYER_REGEN_DISABLED")
eq(NS.UI.enemy.validCount,1,"restricted visual persists in combat")
eq(bound.enemy,beforeRestrictedCombat,"restricted combat path never rebinds secure rows")
NS.HandleEvent("NAME_PLATE_UNIT_REMOVED","nameplate1") -- UnitExists deliberately lags.
eq(NS.UI.enemy.validCount,0,"removed address stays blank despite lagging native existence")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate1")
eq(NS.UI.enemy.validCount,1,"new addition opens a fresh anonymous visual lifecycle")
NS.HandleEvent("PLAYER_LEAVING_WORLD")
eq(NS.UI.enemy.validCount,0,"leaving world cannot repopulate anonymous stale addresses")
NS.HandleEvent("PLAYER_ENTERING_WORLD")
eq(NS.UI.enemy.validCount,1,"current exposed nameplate can repopulate after entering world")
combat=false
mob("nameplate1","Creature-public-after-instance","公开怪物")
units.target=nil
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.EnemyDisplay.active,false,"fully public roster returns to ordinary binding path")
eq(NS.UI.enemy.tiles[1].expectedGUID,"Creature-public-after-instance","public identity is normally revalidated")
eq(NS.UI.enemy.actionableCount,1,"public operation restored by full OOC binding")
mob("nameplate2",restrictedGUID,restrictedName)
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate2")
eq(NS.UI.enemy.tiles[1].data.guid,"Creature-public-after-instance","anonymous visual cannot displace prepared public action")
eq(NS.UI.enemy.actionableCount,1,"mixed roster retains original public operation")
eq(NS.UI.enemy.restrictedCount,1,"mixed roster fills a remaining visual cell")
local restrictedCollector=NS.RestrictedEnemyTokens
NS.RestrictedEnemyTokens=function() error("native read failure") end
eq(pcall(NS.RequestRefresh),true,"restricted discovery failure cannot abort ordinary bindings")
eq(NS.UI.enemy.actionableCount,1,"public row survives restricted discovery failure")
NS.RestrictedEnemyTokens=restrictedCollector
local beforeNativeHold=bound.enemy
NS.InstanceActions={Enabled=function() return true end}
mob("nameplate3","Creature-fresh-during-experiment","新增公开怪物")
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate3")
eq(bound.enemy,beforeNativeHold,"native experiment cannot acquire unrelated production actions below its cells")
NS.InstanceActions=nil;NS.RequestRefresh()
eq(bound.enemy>beforeNativeHold,true,"ending native experiment restores normal roster preparation")
-- Actual Main routes this read-only diagnostic without stealing ordinary
-- commands and invalidates its frozen addresses before Display advances epochs.
local commands,probeEvents,probeTicks,order={},{},{},{}
local beforeEpoch,afterEpoch,afterEvent,afterUnit
NS.UnitMatchProbe={Command=function(arg) commands[#commands+1]=arg end,
    OnEvent=function(event,unit)
        probeEvents[#probeEvents+1]={event,unit};order[#order+1]="probe"
        if event=="NAME_PLATE_UNIT_ADDED" then beforeEpoch=NS.EnemyDisplay.LifecycleState(unit).currentEpoch end
    end,
    OnAfterEvent=function(event,unit)
        order[#order+1]="probe_after";afterEvent,afterUnit=event,unit
        if event=="NAME_PLATE_UNIT_ADDED" then afterEpoch=NS.EnemyDisplay.LifecycleState(unit).currentEpoch end
    end,
    Tick=function(elapsed) probeTicks[#probeTicks+1]=elapsed end}
NS.HandleCommand("unitmatch on");NS.HandleCommand("unitmatch off")
NS.HandleCommand(" UNITMATCH   status ")
eq(commands[1],"on","Main forwards explicit probe start")
eq(commands[2],"off","Main forwards explicit probe stop")
eq(commands[3],"status","Main preserves diagnostic command parsing")
local displayEvent=NS.EnemyDisplay.OnEvent
NS.EnemyDisplay.OnEvent=function(event,unit) order[#order+1]="display";return displayEvent(event,unit) end
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate3")
eq(order[1],"probe","probe sees a reused address before Display can update its epoch")
eq(order[2],"display","normal visual lifecycle still receives the event")
eq(order[3],"probe_after","probe receives post-event metadata only after Display updates")
eq(afterEvent,"NAME_PLATE_UNIT_ADDED","post-event forwards original lifecycle event")
eq(afterUnit,"nameplate3","post-event forwards the same address")
eq(afterEpoch>beforeEpoch,true,"post-event sees the updated generation instead of old before-state")
eq(probeEvents[1][1],"NAME_PLATE_UNIT_ADDED","Main forwards lifecycle event name")
eq(probeEvents[1][2],"nameplate3","Main forwards original unit address")
NS.HandleEvent("PLAYER_TARGET_CHANGED")
eq(probeEvents[#probeEvents][1],"PLAYER_TARGET_CHANGED","manual target selection reaches probe")
NS.EventFrame.scripts.OnUpdate(NS.EventFrame,.11)
eq(#probeTicks>0,true,"Main drives the bounded read-only lifetime timer")
eq(probeTicks[#probeTicks]>=.1,true,"probe receives accumulated visual tick elapsed")
NS.EnemyDisplay.OnEvent=displayEvent;NS.UnitMatchProbe=nil
-- Production Main + Display + probe integration. Native APIs remain modeled;
-- this reproduces a possible failure class, not the unknown session64 cause.
units={};NS.Nameplates={}
for i=1,3 do mob("nameplate"..i,restrictedGUID,restrictedName) end
IsInInstance=function() return true,"party" end
SpellIsTargeting=function() return false end
CursorHasItem=function() return false end
UnitIsUnit=function(a,b) return units[a]~=nil and units[a]==units[b] end
C_Secrets={CanCompareUnitTokens=function() return true end,ShouldUnitComparisonBeSecret=function() return false end}
local diagnosticSession,probeRecords,probeStops=900,{},0
NS.Diagnostics.Start=function() diagnosticSession=diagnosticSession+1;logging=true end
NS.Diagnostics.Session=function() return diagnosticSession end
NS.Diagnostics.Stop=function() probeStops=probeStops+1;logging=false end
NS.Diagnostics.Record=function(kind,fields)
    local copy={};for k,v in pairs(fields) do copy[k]=v end
    probeRecords[#probeRecords+1]={kind=kind,fields=copy};return true
end
local function latestProbe(kind)
    for i=#probeRecords,1,-1 do if probeRecords[i].kind==kind then return probeRecords[i].fields end end
end
assert(loadfile(root.."UnitMatchProbe.lua"))("MyForeverTargets",NS)
NS.HandleEvent("PLAYER_ENTERING_WORLD")
for i=1,3 do NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate"..i) end
NS.HandleCommand("unitmatch on")
eq(NS.UnitMatchProbe.Enabled(),true,"real Main can start the production read-only probe")
eq(NS.UnitMatchProbe.Status().validUnits,3,"production Display supplies three valid frozen lifecycles")
local frozenThird=NS.EnemyDisplay.LifecycleState("nameplate3").currentEpoch
NS.EventFrame.scripts.OnUpdate(NS.EventFrame,.601)
eq(NS.UnitMatchProbe.Enabled(),true,"ordinary half-second Main refresh does not end the probe")
eq(NS.UnitMatchProbe.Status().validUnits,3,"ordinary refresh preserves all frozen epochs")
NS.HandleEvent("NAME_PLATE_UNIT_REMOVED","nameplate3") -- Native existence deliberately lags.
eq(NS.UnitMatchProbe.Enabled(),true,"one removed address cannot stop the entire production probe")
eq(logging,true,"per-address retirement retains the owned logger")
eq(probeStops,0,"address retirement never invokes Diagnostics.Stop")
eq(NS.UnitMatchProbe.Status().validUnits,2,"two stable addresses remain eligible")
eq(latestProbe("UNIT_MATCH_INVALIDATED").unit,"nameplate3","failure record identifies the exact removed address")
eq(latestProbe("UNIT_MATCH_INVALIDATED").triggerEvent,"NAME_PLATE_UNIT_REMOVED","failure record identifies the native event")
eq(latestProbe("UNIT_MATCH_LIFECYCLE").stage,"after","Main records post-Display lifecycle state")
eq(latestProbe("UNIT_MATCH_LIFECYCLE").currentEpoch>frozenThird,true,"post-event record shows the advanced epoch")
eq(latestProbe("UNIT_MATCH_LIFECYCLE").tombstoned,true,"post-event record shows the removed-token block")
units.target=units.nameplate1;NS.HandleEvent("PLAYER_TARGET_CHANGED")
eq(NS.UnitMatchProbe.Status().distinctMatches,1,"first surviving target is recorded in the production event path")
units.target=units.nameplate2;NS.HandleEvent("PLAYER_TARGET_CHANGED")
eq(NS.UnitMatchProbe.Status().twoUnitsObserved,true,"both surviving addresses can form a same-group comparison")
local cohort=NS.UnitMatchProbe.Status().cohort
NS.HandleEvent("NAME_PLATE_UNIT_ADDED","nameplate3")
eq(NS.UnitMatchProbe.Status().validUnits,2,"reused address never revives the frozen identity")
eq(NS.UnitMatchProbe.Status().cohort,cohort,"duplicate lifecycle on a retired address does not reset survivors")
NS.HandleCommand("unitmatch off")
eq(NS.UnitMatchProbe.Enabled(),false,"real Main off ends the probe")
eq(probeStops,1,"manual off stops its own diagnostic session exactly once")
eq(units.target,units.nameplate2,"all production diagnostic callbacks preserve the user's current target")
local maxFields,publicScalars=0,true
for _,record in ipairs(probeRecords) do
    local count=0
    for key,v in pairs(record.fields) do
        count=count+1
        if #key>48 or not NS.Public(v) or type(v)~="string" and type(v)~="number" and type(v)~="boolean" then
            publicScalars=false
        end
    end
    maxFields=math.max(maxFields,count)
end
eq(maxFields<=63,true,"real probe schemas fit Diagnostics' bounded field copy with margin")
eq(publicScalars,true,"integrated before/after and retired-row logs contain only supported public scalars")
print("Targets instance roster simulated checks: "..checks)
