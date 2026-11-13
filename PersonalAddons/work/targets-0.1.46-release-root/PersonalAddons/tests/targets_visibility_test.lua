-- Real Core/Main state transitions with simulated protected panels.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS,combat={},false
InCombatLockdown=function() return combat end
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
for _,oldShown in ipairs({true,false}) do
    local d=NS.NormalizeDB({shown=oldShown})
    eq(d.friendlyShown,oldShown,"legacy friendly visibility migrates")
    eq(d.enemyShown,oldShown,"legacy enemy visibility migrates")
    eq(d.shown,oldShown,"legacy aggregate migrates")
end
local mixed=NS.NormalizeDB({shown=false,friendlyShown=true,enemyShown=false})
eq(mixed.shown,true,"explicit independent flags determine aggregate after reload")
eq(mixed.enemyShown,false,"closed enemy survives reload")
eq(NS.NormalizeDB({shown=true,friendlyShown="false"}).friendlyShown,true,"malformed flag uses legacy preference")
eq(NS.NormalizeDB(nil).launcherPosition.point,"LEFT","launcher starts on the left side")
eq(NS.NormalizeDB({launcherPosition={point="TOPRIGHT",relativePoint="TOPRIGHT",x=-280,y=-60}}).launcherPosition.point,
    "LEFT","untouched old default migrates to the new left-side location")
eq(NS.NormalizeDB({launcherPosition={point="TOPRIGHT",relativePoint="TOPRIGHT",x=-300,y=-100}}).launcherPosition.x,
    -300,"custom previous launcher location is preserved")
eq(NS.NormalizeDB({launcherPosition={point="TOPRIGHT",relativePoint="TOPRIGHT",x=-280,y=-60,manual=true}}).launcherPosition.point,
    "TOPRIGHT","explicitly dragged position is not mistaken for an old default")
eq(NS.NormalizeDB({launcherPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=450,y=-100}}).launcherPosition.x,450,
    "launcher position survives normalization")
eq(NS.IsPanelShown("invalid"),false,"invalid side cannot expose a panel")

local function panel()
    return {shown=true,scale=1,Show=function(self) assert(not combat,"protected show in combat");self.shown=true end,
        Hide=function(self) assert(not combat,"protected hide in combat");self.shown=false end,
        IsShown=function(self) return self.shown end,
        SetScale=function(self,value) assert(not combat,"protected scale in combat");self.scale=value end,
        ClearAllPoints=function(self) self.point=nil end,
        SetPoint=function(self,...) self.point={...} end}
end
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(self,k,v) self[k]=v end} end
SlashCmdList={}
local launcherCreates,launcherRefreshes,launcherResets,leaves,hoverClears,targetClears,menuCloses=0,0,0,0,0,0,0
NS.Print=function() end
NS.CreateUI=function() NS.UI={friendly={frame=panel()},enemy={frame=panel()}} end
NS.CreateLauncher=function() launcherCreates=launcherCreates+1 end
NS.RefreshLauncher=function() launcherRefreshes=launcherRefreshes+1 end
NS.ResetLauncherPosition=function() launcherResets=launcherResets+1 end
NS.Collect=function() return {},0 end
NS.ReadUnit=function() return nil end
NS.BindTiles=function() end
NS.RefreshTiles=function() end
NS.RefreshControls=function()
    assert(not combat,"protected refresh in combat")
    for _,side in ipairs({"friendly","enemy"}) do
        local f=NS.UI[side].frame
        if NS.IsPanelShown(side) then f:Show() else f:Hide() end
    end
end
NS.HideHover=function() hoverClears=hoverClears+1 end
NS.EnemyTargetHover={Clear=function() targetClears=targetClears+1;NS.HoveredEnemyTarget=nil end}
NS.NearbyCast={Leave=function() leaves=leaves+1;NS.NearbyCast.row=nil end}
NS.CloseMarkMenu=function() menuCloses=menuCloses+1 end
NS.SetDetectionEnabled=function() end
local canRelease=true
NS.EnemyNativeHover={Disable=function() return canRelease end}
MyForeverTargetsDB={shown=true,friendlyTab="nearby",nearbyLimit=5,enemyLimit=5}
assert(loadfile(root.."Main.lua"))("MyForeverTargets",NS)
NS.HandleEvent("ADDON_LOADED","MyForeverTargets")
eq(launcherCreates,1,"launcher created once alongside panels")
local function visible(friendly,enemy,why)
    eq(NS.IsPanelShown("friendly"),friendly,why.." friendly setting")
    eq(NS.IsPanelShown("enemy"),enemy,why.." enemy setting")
    eq(NS.UI.friendly.frame:IsShown(),friendly,why.." friendly frame")
    eq(NS.UI.enemy.frame:IsShown(),enemy,why.." enemy frame")
    eq(NS.DB.shown,friendly or enemy,why.." aggregate")
end
visible(true,true,"initial")
NS.HoveredTile={side="friendly"}
NS.NearbyCast.row=NS.HoveredTile
eq(NS.SetPanelShown("friendly",false),true,"independent close accepted")
visible(false,true,"friendly closed")
eq(NS.HoveredTile,nil,"closing hovered side clears stale roster hold")
eq(hoverClears,1,"closing side clears its world hover")
eq(leaves,1,"closing side releases temporary spell keys")
eq(menuCloses,1,"closing side dismisses the mark palette")
NS.RequestRefresh();visible(false,true,"periodic refresh")
NS.HoveredEnemyTarget={side="friendly",owner={side="enemy"}}
NS.SetPanelShown("enemy",false)
visible(false,false,"both closed")
eq(NS.HoveredEnemyTarget,nil,"friendly child in enemy panel clears using owner side")
eq(targetClears>0,true,"child cleanup performed")
NS.SetPanelShown("friendly",true)
visible(true,false,"only friendly reopened")
NS.DB=NS.NormalizeDB(NS.DB);NS.RequestRefresh()
visible(true,false,"independent flags survive reload normalization")
NS.SetShown();visible(false,false,"aggregate toggle hides open panels")
NS.SetShown();visible(true,true,"aggregate toggle reopens both")
local enemyCast={side="enemy"}
NS.NearbyCast.row=enemyCast
local preservedLeaves=leaves
NS.SetPanelShown("friendly",false)
eq(NS.NearbyCast.row,enemyCast,"closing friendly preserves hovered enemy spell keys")
eq(leaves,preservedLeaves,"closing unrelated side does not dispatch Leave")
NS.SetPanelShown("friendly",true)
local childCast={side="friendly",owner={side="enemy"},bridgeTarget=true}
NS.NearbyCast.row=childCast
NS.SetPanelShown("enemy",false)
eq(NS.NearbyCast.row,nil,"closing enemy clears friendly child spell keys by owner side")
NS.SetShown(true)

combat=true
local leavesBefore=leaves
eq(NS.SetPanelShown("friendly"),false,"combat toggle is queued")
visible(true,true,"combat keeps protected panels unchanged")
eq(NS.PendingSettings.friendlyShown,false,"first combat toggle requests hide")
NS.SetPanelShown("friendly")
eq(NS.PendingSettings.friendlyShown,true,"second toggle reads pending state")
NS.SetShown(false);NS.SetPanelShown("friendly",true)
eq(NS.PendingSettings.friendlyShown,true,"single open overrides earlier all hide")
eq(NS.PendingSettings.enemyShown,false,"other side retains all-hide request")
eq(leaves,leavesBefore,"queued setting does not alter active input early")
combat=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,false,"last queued choices applied atomically")
eq(NS.PendingSettings,nil,"applied queue cleared")
combat=true;NS.SetPanelShown("friendly",false);NS.SetShown(true);NS.SetPanelShown("enemy")
combat=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,false,"all-show overwrites earlier single close before next toggle")
combat=true;NS.SetShown();NS.SetShown()
combat=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,true,"repeated aggregate toggle uses pending state")

combat=true;NS.SetPanelShown("friendly",false)
combat=false;canRelease=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.PendingSettings.friendlyShown,false,"native restoration failure retains requested change")
canRelease=true;NS.SetPanelShown("friendly",true)
eq(NS.PendingSettings,nil,"successful new choice discards superseded pending close")
NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,true,"later regen cannot resurrect superseded close")
combat=true;NS.SetShown(false)
combat=false;canRelease=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
canRelease=true;NS.SetShown(true)
eq(NS.PendingSettings,nil,"successful global choice discards both stale flags")
NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,true,"global newer choice survives another regen")

canRelease=false
eq(NS.SetPanelShown("enemy",false),false,"failed native hit release blocks layout mutation")
visible(true,true,"failed native restoration preserves both panels")
canRelease=true
NS.HandleCommand("hide");visible(false,false,"legacy hide command")
NS.HandleCommand("show");visible(true,true,"legacy show command")
NS.SetPanelShown("friendly",false)
combat=true;NS.HandleCommand("reset")
combat=false;NS.HandleEvent("PLAYER_REGEN_ENABLED")
visible(true,true,"deferred reset reopens both panels")
eq(launcherResets,1,"reset also recovers a displaced launcher")
eq(NS.SetPanelShown("invalid",false),false,"invalid side rejected")
eq(launcherRefreshes>0,true,"launcher reflects live and queued settings")
print("Targets visibility simulated checks: "..checks.."; native combat protection and actual clicks still require the game")
