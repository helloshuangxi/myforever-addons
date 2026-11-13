-- Readback and startup policy simulation; the native mouseover engine is not run.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
local secret={}
issecretvalue=function(value) return value==secret end
local combat=false
InCombatLockdown=function() return combat end
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.LegacyNameBridge=false -- Explicit pure-native startup policy fixture.
assert(loadfile(root.."Mouseover.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
NS.DB.mouseoverRequested=false
eq(NS.SetMouseoverEnabled(true,true),false,"even direct legacy API calls cannot enable global auto-cast")
eq(NS.DB.mouseoverRequested,false,"rejected enabling does not alter the saved native policy")
combat=true
eq(NS.SetMouseoverEnabled(true,true),false,"combat cannot queue a legacy enable request")
eq(NS.PendingMouseover,nil,"native mode never queues an enable request")
combat=false
local guids,expressions={},{}
UnitGUID=function(unit) return guids[unit] end
local parsed
SecureCmdOptionParse=function(expression)
    expressions[#expressions+1]=expression
    return parsed
end
local row={unit="nameplate1",side="enemy",expectedGUID="Creature-A"}
local function status(reason,confirmed)
    local result,text,details=NS.NativeMouseoverStatus(row)
    eq(result,confirmed or false,reason.." confirmation")
    eq(details.reason,reason,reason.." reason")
    eq(type(text),"string",reason.." explanation")
    return details
end
status("not_hovered")
NS.HoveredTile=row
status("stale_unit")
guids.nameplate1="Creature-A"
status("no_mouseover")
guids.mouseover="Creature-B"
status("different_mouseover")
guids.mouseover="Creature-A"
local details=status("condition_unconfirmed")
eq(details.identityMatches,true,"native identity may match without macro conditions")
eq(details.conditionMatched,false,"missing native condition is never assumed true")
eq(expressions[#expressions],"[@mouseover,nodead,harm] MFT_MOUSEOVER","enemy uses the user's exact native condition")
parsed="MFT_MOUSEOVER"
details=status("matched",true)
eq(details.expectedGUID,"Creature-A","expected identity is explicit")
eq(details.mouseoverGUID,"Creature-A","actual mouseover identity is explicit")
eq(details.unitGUID,"Creature-A","live alias still matches the tile")
row.side="friendly"
status("matched",true)
eq(expressions[#expressions],"[@mouseover,nodead,help] MFT_MOUSEOVER","friendly uses helpful macro conditions")
guids.nameplate1="Creature-B"
status("stale_unit")
guids.nameplate1="Creature-A";guids.mouseover=secret
details=status("no_mouseover")
eq(details.mouseoverGUID,nil,"secret native identity stays undisclosed")
guids.mouseover="Creature-A";parsed=secret
status("condition_unconfirmed")
SecureCmdOptionParse=function() error("client API unavailable") end
status("condition_unconfirmed")
guids.mouseover="Creature-A";row.expectedGUID=secret
details=status("stale_unit")
eq(details.expectedGUID,nil,"secret expected identity stays undisclosed")
row.expectedGUID="Creature-A"
UnitGUID=function() error("unit API unavailable") end
status("stale_unit")
UnitGUID=function(unit) return guids[unit] end
NS.HoveredTile={unit="nameplate2",expectedGUID="Creature-A",side="enemy"}
status("not_hovered")

-- Exercise the actual Main routes/events without a live UI. Previous addon
-- changes are restored through the owned backup, never enabled for this mode.
local restoreCalls,messages=0,{}
NS.Print=function(message) messages[#messages+1]=message end
NS.SetMouseoverEnabled=function(enabled)
    eq(enabled,false,"startup only requests owned-setting restoration")
    restoreCalls=restoreCalls+1
    return true
end
local frame={}
function frame:RegisterEvent() end
function frame:SetScript(event,fn) self[event]=fn end
CreateFrame=function() return frame end
NS.CreateUI=function() end
NS.Collect=function() return {},0 end
NS.BindTiles=function() end
NS.RefreshTiles=function() end
NS.SetDetectionEnabled=function() return true end
NS.NativeMouseoverStatus=function() return false,"native readback",{reason="no_mouseover"} end
local function forbidden() error("native macro policy must not enter a casting bridge") end
NS.NearbyCast={DiscoverActions=forbidden,Leave=forbidden,Reconcile=forbidden}
NS.CombatCast={RefreshAll=function() end,Reconcile=function() end}
NS.GUIDProbe={Command=forbidden,Stop=forbidden}
ClearOverrideBindings=forbidden
SlashCmdList={}
MyForeverTargetsDB={mouseoverRequested=true,mouseoverBackup={enabled="0",modifiers={[1]="SHIFT"}}}
assert(loadfile(root.."Main.lua"))("MyForeverTargets",NS)
NS.HandleEvent("ADDON_LOADED","MyForeverTargets")
eq(NS.DB.mouseoverRequested,false,"persisted auto-cast request cannot enable interception")
eq(restoreCalls,0,"addon load does not modify settings inside UI creation")
NS.PendingMouseover=true
NS.HandleEvent("PLAYER_ENTERING_WORLD")
eq(restoreCalls,1,"world entry restores an old owned setting")
eq(NS.PendingMouseover,nil,"old pending enable request is discarded")
eq(NS.MouseoverApplied,true,"native startup has applied its policy")
NS.HandleEvent("UPDATE_BINDINGS")
eq(restoreCalls,2,"other binding-profile backups are eligible for restoration")
combat=true
NS.PendingMouseover=true
NS.HandleEvent("PLAYER_ENTERING_WORLD")
eq(restoreCalls,2,"combat postpones setting restoration")
combat=false
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(restoreCalls,3,"restoration resumes outside combat")
eq(NS.PendingMouseover,nil,"queued legacy enable is discarded after combat too")
NS.DB.mouseoverBackup=nil
NS.HandleEvent("UPDATE_BINDINGS")
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(restoreCalls,3,"no owned backup means no setting or binding save")
for _,command in ipairs({"macro","hover on","hover off","guid integrated_macro","debug enemy","debug enemyunit","help"}) do
    NS.HandleCommand(command)
end
eq(restoreCalls,3,"help and old commands cannot enable or alter global mouseover options")
eq(NS.SetGUIDProbeSuspended(false),false,"old suspension route cannot reactivate a bridge")
eq(NS.DB.mouseoverRequested,false,"all command paths preserve native macro policy")
eq(type(SlashCmdList.MYFOREVERTARGETS),"function","normal slash entry remains available")
local probeRow={unit="nameplate2",expectedGUID="Creature-probe",side="enemy"}
local enabledRow,disables,ticks,forwarded=nil,0,0,{}
local canRelease=true
NS.EnemyNativeHover={Enable=function(value) enabledRow=value;return value~=nil,"test" end,
    Disable=function() disables=disables+1;return canRelease end,
    Status=function() return {reason="test",unit="nameplate2",matches=false} end,
    Tick=function() ticks=ticks+1 end,
    OnEvent=function(event,unit) forwarded[#forwarded+1]={event,unit} end}
NS.HoveredTile=nil
NS.UI={enemy={tiles={{unit="target",expectedGUID="Creature-target"},probeRow}}}
NS.HandleCommand("native on")
eq(enabledRow,probeRow,"native probe selects an actual enemy nameplate cell, skipping stable target aliases")
NS.HandleCommand("native off")
eq(disables,1,"native off asks the controller to restore its own state")
local scaleBefore=NS.DB.scale
canRelease=false
eq(NS.SetScale(1.2),false,"pending native recovery postpones panel changes")
eq(NS.DB.scale,scaleBefore,"failed recovery cannot move or scale a mapped cell")
local enemyPosition=NS.DB.enemyPosition
NS.HandleCommand("reset")
eq(NS.DB.enemyPosition,enemyPosition,"reset cannot move a mapped cell before recovery")
eq(NS.PendingReset,true,"reset remains queued while recovery is pending")
NS.PendingSettings={scale=1.3}
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.DB.scale,scaleBefore,"post-combat settings cannot bypass native recovery")
eq(NS.PendingSettings.scale,1.3,"pending layout settings are retained for retry")
eq(NS.PendingReset,true,"pending reset is retained for retry")
NS.PendingSettings=nil;NS.PendingReset=nil
canRelease=true
NS.HandleEvent("NAME_PLATE_UNIT_REMOVED","nameplate2")
eq(forwarded[#forwarded][1],"NAME_PLATE_UNIT_REMOVED","native lifecycle receives nameplate removal")
eq(forwarded[#forwarded][2],"nameplate2","native lifecycle retains the exact removed alias")
frame.OnUpdate(frame,.11)
eq(ticks,1,"native identity and cleanup polling runs independently from hover scripts")
eq(restoreCalls,3,"native probe help and lifecycle do not reenable global automatic casting")
local samples={}
NS.EnemyNativeHover.ProbeReadback=function(value) samples[#samples+1]=value end
NS.Diagnostics={Enabled=function() return false end}
frame.OnUpdate(frame,1)
eq(#samples,0,"stopped diagnostics perform no capability sampling")
NS.Diagnostics.Enabled=function() return true end
frame.OnUpdate(frame,.4)
eq(#samples,0,"normal callback bounds capability sampling cadence")
frame.OnUpdate(frame,.6)
eq(#samples,2,"normal callback samples visible enemy rows including stable aliases")
eq(samples[2],probeRow,"capability callback receives the actual row")
combat=true
frame.OnUpdate(frame,1)
eq(#samples,2,"combat cannot consume the out-of-combat capability sample")
combat=false
NS.DB.shown=false
frame.OnUpdate(frame,1)
eq(#samples,2,"hidden panels do not perform capability sampling")
NS.DB.shown=true
local savedCombat=InCombatLockdown
InCombatLockdown=function() return nil end
frame.OnUpdate(frame,1)
eq(#samples,2,"unknown combat state does not perform capability sampling")
InCombatLockdown=savedCombat
frame.OnUpdate(frame,1)
eq(#samples,4,"out-of-combat observation resumes on the normal callback")
local trialRow,trialDisables,trialDelta,trialEvents=nil,0,0,{}
local trialCanRestore=true
NS.EnemyNativeTrial={Enable=function(value) trialRow=value;return true,"accepted_unmeasured" end,
    Disable=function() trialDisables=trialDisables+1;return trialCanRestore end,
    Status=function() return {reason="accepted_unmeasured",unit="nameplate2",matches=false} end,
    Tick=function(delta) trialDelta=trialDelta+delta end,
    OnEvent=function(event,unit) trialEvents[#trialEvents+1]={event,unit} end}
NS.HandleCommand("native trial")
eq(trialRow,nil,"known incompatible native expansion cannot be enabled in production")
eq(trialDisables,0,"disabled trial command performs no engine or recovery mutation")
NS.NativeTrialUnavailable=nil -- Explicit historical trial integration fixture.
NS.HandleCommand("native trial")
eq(trialRow,probeRow,"explicit native trial receives an existing enemy nameplate row")
local trialsBefore=trialRow
canRelease=false;trialRow=nil
NS.HandleCommand("native trial")
eq(trialRow,nil,"old pending hit-test recovery prevents concurrent trial")
canRelease=true
trialCanRestore=false;enabledRow=nil
NS.HandleCommand("native on")
eq(enabledRow,nil,"pending trial recovery prevents concurrent old mapping")
trialCanRestore=true
NS.HandleCommand("native off")
eq(trialDisables,2,"native off also restores the independent temporary trial")
NS.HandleCommand("native trialstatus")
eq(trialRow,nil,"trialstatus reads status without enabling a trial")
NS.HandleEvent("ADDON_ACTION_FORBIDDEN","MyForeverTargets")
eq(trialEvents[#trialEvents][1],"ADDON_ACTION_FORBIDDEN","trial receives public refusal events")
eq(trialEvents[#trialEvents][2],"MyForeverTargets","trial receives the refused addon identity")
frame.OnUpdate(frame,.12)
eq(trialDelta,.12,"trial gets accumulated elapsed time for bounded lifetime")
print("Targets macro-policy simulated checks: "..checks.."; real native mouseover still requires the client")
