-- State/observation simulation only. No native targeting, focus or macro runs.
local checks=0
local function eq(actual,expected,message)
 checks=checks+1;assert(actual==expected,message)
end
local secret=setmetatable({}, {__tostring=function() error('formatted secret') end})

local function setup(combined)
 local c={units={},hooks={},records={},messages={},frames={},combat=false,spellCursor=false,itemCursor=false}
 issecretvalue=function(value) return rawequal(value,secret) end
 local function entity(id,name,player,harm,dead)
  return {guid=id,name=name,player=player==true,harm=harm==true,dead=dead==true,connected=true}
 end
 c.self=entity('Player-Self','自己',true,false)
 c.goal=entity('Creature-Goal','同名狼',false,true)
 c.wrong=entity('Creature-Wrong','同名狼',false,true)
 c.third=entity('Creature-Third','同名狼',false,true)
 c.original=entity('Creature-Original','原来的敌人',false,true)
 c.priorFocus=entity('Player-OldFocus','原焦点',true,false)
 c.units.player=c.self;c.units.nameplate1=c.goal;c.units.nameplate2=c.wrong
 c.units.nameplate3=c.third;c.units.nameplate4=c.original;c.units.focus=c.priorFocus
 local function resolve(unit)
  if type(unit)~='string' then return nil end
  if c.units[unit] then return c.units[unit] end
  for _,value in pairs(c.units) do
   if value.player and (value.name==unit or value.name..'-测试服务器'==unit) then return value end
  end
 end
 c.resolve=resolve
 InCombatLockdown=function() return c.combat end
 SpellIsTargeting=function() return c.spellCursor end
 CursorHasItem=function() return c.itemCursor end
 UnitExists=function(unit) return resolve(unit)~=nil end
 UnitGUID=function(unit) local value=resolve(unit);return value and value.guid end
 UnitName=function(unit) local value=resolve(unit);return value and value.name end
 UnitFullName=function(unit) local value=resolve(unit);if value then return value.name,'测试服务器' end end
 UnitIsPlayer=function(unit) local value=resolve(unit);return value and value.player end
 UnitIsDeadOrGhost=function(unit) local value=resolve(unit);return value and value.dead end
 UnitIsConnected=function(unit) local value=resolve(unit);return value and value.connected end
 UnitCanAttack=function(_,unit) local value=resolve(unit);return value and value.harm end
 UnitCanAssist=function(_,unit) local value=resolve(unit);return value and not value.harm end
 UnitIsFriend=UnitCanAssist
 UnitIsUnit=function(a,b) local aa,bb=resolve(a),resolve(b);return aa~=nil and bb~=nil and aa.guid==bb.guid end
 UnitClass=function() return '圣骑士','PALADIN' end
 UnitAffectingCombat=function() return false end
 UnitTokenFromGUID=function(id)
  for _,unit in ipairs({'player','party1','party2','raid1','boss1','arena1','nameplate1','nameplate2','nameplate3','nameplate4','target','focus'}) do
   if UnitGUID(unit)==id then return unit end
  end
 end
 GetNumGroupMembers=function() return c.units.party1 and 2 or 0 end
 GetNumSubgroupMembers=function() return c.units.party1 and 1 or 0 end
 IsInGroup=function() return c.units.party1~=nil end
 IsInRaid=function() return false end
 GetTime=function() return 100 end
 GetServerTime=function() return 1000 end
 local function forbiddenAction() error('test must not execute a native protected action') end
 TargetNearestEnemy=forbiddenAction;TargetUnit=forbiddenAction;FocusUnit=forbiddenAction
 ClearTarget=forbiddenAction;ClearFocus=forbiddenAction;RunMacroText=forbiddenAction
 C_Macro={RunMacroText=forbiddenAction}
 hooksecurefunc=function(name,callback)
  c.hooks[name]=callback;c.hookCount=(c.hookCount or 0)+1
 end
 local methods={}
 local function frame(kind,name,parent,template)
  local value=setmetatable({kind=kind,name=name,parent=parent,template=template or '',attrs={},scripts={},hooks={},shown=true}, {__index=methods})
  if value.template:find('SecureActionButtonTemplate',1,true) then value.scripts.OnClick=c.nativeClick end
  c.frames[#c.frames+1]=value;return value
 end
 c.nativeClick=function() end
 for _,name in ipairs({'SetSize','SetPoint','SetFrameStrata','SetFrameLevel','EnableMouse','RegisterForClicks',
  'SetBackdrop','SetBackdropColor','SetBackdropBorderColor','SetWidth','SetHeight','SetAllPoints','SetTextColor',
  'SetMovable','RegisterForDrag','SetClampedToScreen','SetJustifyH','SetFont','SetAlpha'}) do methods[name]=function() end end
 function methods:SetAttribute(key,value) assert(c.combat==false,'insecure combat attribute write');self.attrs[key]=value end
 function methods:GetAttribute(key) return self.attrs[key] end
 function methods:SetScript(key,callback) self.scripts[key]=callback end
 function methods:HookScript(key,callback) self.hooks[key]=callback end
 function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
 function methods:UnregisterEvent(event) if self.events then self.events[event]=nil end end
 function methods:CreateFontString() return frame('FontString') end
 function methods:CreateTexture() return frame('Texture') end
 function methods:SetColorTexture() end
 function methods:SetText(text) self.text=text end
 function methods:GetName() return self.name end
 function methods:IsVisible() return self.shown end
 function methods:IsShown() return self.shown end
 function methods:Show() assert(c.combat==false,'insecure combat show');self.shown=true end
 function methods:Hide() assert(c.combat==false,'insecure combat hide');self.shown=false end
 function methods:IsObjectType(kind) return self.kind==kind end
 CreateFrame=frame;UIParent=frame('Frame','UIParent')
 SecureHandlerWrapScript=function(button,event,owner,script)
  button.wrappers=button.wrappers or {};button.wrappers[event]=script
 end
 RegisterStateDriver=function(button,state,text) assert(c.combat==false);button.driver=text end
 UnregisterStateDriver=function(button) assert(c.combat==false);button.driver=nil end
 ClearOverrideBindings=function() end
 C_Timer={After=function(_,callback) c.timer=callback end}
 local NS={}
 assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/Core.lua'))('MyForeverTargets',NS)
 NS.DB={shown=true,enemyShown=true,enemyLimit=5}
 NS.Print=function(message) c.messages[#c.messages+1]=message end
 NS.Diagnostics={Start=function() c.logging=true end,Enabled=function() return c.logging==true end,
  Record=function(kind,fields) c.records[#c.records+1]={kind=kind,fields=fields};return true end}
 NS.RequestRefresh=function() end
 NS.SetGUIDProbeSuspended=function() return true end
 NS.NameplateTokens=function()
  local result={}
  for _,unit in ipairs({'nameplate1','nameplate2','nameplate3','nameplate4'}) do
   if c.units[unit] then result[#result+1]=unit end
  end
  return result
 end
 NS.ReadUnit=function(unit,side)
  local value=resolve(unit)
  if not value or not NS.Public(value.guid) or type(value.guid)~='string' then return nil end
  if side=='enemy' and not value.harm or side=='friendly' and (not value.player or value.harm) then return nil end
  return {unit=unit,guid=value.guid,name=value.name,targetName=value.player and value.name..'-测试服务器' or value.name,
   player=value.player,dead=value.dead,offline=not value.connected,health=1,healthCurrent=100,healthMax=100,
   className=value.player and '圣骑士' or '怪物',classToken='PALADIN',color={r=1,g=.5,b=.2}}
 end
 c.row=frame('Button','EnemyRow1');c.row.unit='nameplate1';c.row.expectedGUID=c.goal.guid;c.row.side='enemy';c.row.index=1
 c.otherRow=frame('Button','EnemyRow2');c.otherRow.unit='nameplate2';c.otherRow.expectedGUID=c.wrong.guid;c.otherRow.side='enemy'
 NS.UI={enemy={tiles={c.row,c.otherRow}},friendly={tiles={}}}
 c.NS=NS;c.data=NS.ReadUnit('nameplate1','enemy')
 local framesBefore=#c.frames
 assert(loadfile('_forever_/Interface/AddOns/MyForeverTargets/FocusCycle.lua'))('MyForeverTargets',NS)
 c.F=NS.FocusCycle
 eq(c.F.IsActive(),false,'new focus cycle is dormant')
 eq(c.F.button,nil,'dormant cycle creates no control button')
 eq(c.hookCount or 0,0,'dormant cycle installs no API hooks')
 eq(#c.frames,framesBefore,'loading the cycle creates no frames')
 eq(c.F.combineFocusRestore,true,'fresh flow defaults to combined focus and first restoration')
 if not combined then
  c.F.Command('staged')
  eq(c.F.combineFocusRestore,false,'staged command preserves the original separate-action regression mode')
 end
 return c
end

local function nativeLines(macro)
 local lines={}
 if macro then
  eq(type(macro),'string','prepared macro is text')
  for line in macro:gmatch('[^\r\n]+') do
   if not line:match('^/stopmacro') then lines[#lines+1]=line end
  end
 end
 return lines
end
local function oneAction(macro,command,message)
 local lines=nativeLines(macro)
 eq(#lines,1,message..' has exactly one native command')
 eq(lines[1]:match('^/'..command..'%f[%A]')~=nil,true,message..' uses the intended native command')
 eq(macro:find('/run',1,true),nil,message..' does not use ordinary Lua for a protected action')
 eq(macro:find('/cast',1,true),nil,message..' never casts')
 return lines[1]
end
local function noAction(macro,message) eq(#nativeLines(macro),0,message) end
local function prepare(c,command,cancel)
 local macro,reason=c.F.Prepare(c.row,c.data,cancel)
 if command then oneAction(macro,command,'prepared '..command) end
 return macro,reason
end
local function targetResult(c,value,reverse)
 c.units.target=value -- explicit fixture; not execution of the prepared macro
 eq(type(c.hooks.TargetNearestEnemy),'function','selection is observed through its passive hook')
 c.hooks.TargetNearestEnemy(reverse==true)
 c.F.AfterClick(c.row)
end
local function focusResult(c,value)
 c.units.focus=value or c.units.target -- explicit fixture; no native focus API call
 c.F.AfterClick(c.row)
end
local function clearResult(c)
 c.units.target=nil -- explicit fixture for a separate clear-target action
 c.F.AfterClick(c.row)
end
local function matchGoal(c)
 local macro=prepare(c,'targetenemy')
 eq(macro,'/stopmacro [combat]\n/targetenemy','search uses one forward targetenemy only')
 targetResult(c,c.goal)
 eq(c.F.session.state,'matched','a matching observed GUID enters the matched state')
end
local function commitGoal(c)
 prepare(c,'focus')
 focusResult(c,c.goal)
 eq(c.F.session.committed,true,'focus becomes committed only after matching readback')
end

-- Wrong same-name mobs may be searched, but may not become the focus.
local c=setup()
prepare(c,'targetenemy')
eq(c.F.Owns(c.row),true,'flow owns the initiating tile')
eq(c.F.Owns(c.otherRow),false,'flow does not own another same-name tile')
eq(c.F.session.goalGUID,c.goal.guid,'goal is frozen by GUID')
targetResult(c,c.wrong)
eq(c.F.session.state,'seek','wrong same-name mob does not satisfy the goal')
eq(c.F.session.committed,false,'wrong same-name mob is never committed')
eq(c.units.focus,c.priorFocus,'search preserves the original focus')
local macro=prepare(c,'targetenemy')
eq(macro:find('/focus',1,true),nil,'wrong GUID does not arm focus on the next click')
targetResult(c,c.goal)
eq(c.F.session.state,'matched','correct GUID is distinguished from its same-name sibling')
commitGoal(c)
prepare(c,'cleartarget')
clearResult(c)
eq(c.F.IsActive(),false,'empty-original-target flow finishes after its clear click')
eq(c.F.lastResult.kind,'complete','verified focus and target restoration report completion')
eq(c.F.lastResult.focusSet,true,'completed flow records verified focus')
eq(c.F.lastResult.targetRestored,true,'completed flow records the empty target restored')
eq(c.units.focus,c.goal,'clearing the test target preserves committed focus')

-- Pinned presentation keeps the frozen GUID while sorting or visibility can
-- change, and is released when the flow ends.
c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
eq(c.F.HoldRoster('enemy',5),true,'enemy roster is held during the flow')
eq(c.F.HoldRoster('friendly',5),false,'friendly roster is not frozen')
eq(c.F.PinnedData(c.row).guid,c.goal.guid,'initiating row presents the frozen goal')
eq(c.F.PinnedData(c.otherRow),nil,'another row does not receive pinned data')
eq(type(c.F.RowStatus(c.row)),'string','owned row receives progress text')
eq(c.F.RowStatus(c.otherRow),nil,'other rows do not receive this flow progress')
c.row.unit='nameplate2';c.row.expectedGUID=c.wrong.guid
prepare(c,'targetenemy')
eq(c.F.session.goalGUID,c.goal.guid,'row rebinding cannot replace the frozen goal')
targetResult(c,c.goal);commitGoal(c)
prepare(c,'cleartarget');clearResult(c)
eq(c.F.HoldRoster('enemy',5),false,'completed flow releases its held roster')
eq(c.F.PinnedData(c.row),nil,'completed flow releases pinned presentation')

-- A canonical alias is independently rechecked, and an ungrouped player may
-- use a frozen exact player name followed by actual GUID verification.
c=setup()
local groupOriginal={guid='Player-Party',name='队友原目标',player=true,harm=false,dead=false,connected=true}
c.units.target=groupOriginal;c.units.party1=groupOriginal
matchGoal(c);commitGoal(c)
macro=prepare(c,'target')
eq(macro:find('/target [@party1,exists]',1,true)~=nil,true,'canonical restoration uses the independently verified alias')
c.units.target=groupOriginal;c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'complete','canonical restoration is verified by original GUID')
eq(c.units.target.guid,'Player-Party','canonical restoration retains the intended original player')

c=setup()
local namedOriginal={guid='Player-Named',name='非队友原目标',player=true,harm=false,dead=false,connected=true}
c.units.target=namedOriginal
matchGoal(c);commitGoal(c)
macro=prepare(c,'targetexact')
eq(macro:find(namedOriginal.name..'-测试服务器',1,true)~=nil,true,'player-name restoration preserves the frozen realm-qualified name')
c.units.target=namedOriginal;c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'complete','player-name restoration completes after exact GUID readback')

c=setup();c.units.target=namedOriginal
matchGoal(c);commitGoal(c);prepare(c,'targetexact')
c.units.target={guid='Player-WrongNamed',name=namedOriginal.name,player=true,harm=false,dead=false}
c.F.AfterClick(c.row)
eq(c.F.session.state,'blocked','wrong GUID returned by a player name blocks restoration')
eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,'a successful name lookup alone cannot prove original restoration')

-- The standalone button preserves its native OnClick and prepares one action
-- per release; its callbacks consume the owning row's pending observation.
c=setup();matchGoal(c)
local stepButton=c.F.button
eq(stepButton.scripts.OnClick,c.nativeClick,'standalone step button preserves native action dispatch')
eq(stepButton.attrs.useOnKeyDown,false,'standalone step button uses the release event')
stepButton.hooks.PreClick(stepButton,'RightButton',false)
oneAction(stepButton.attrs['*macrotext2'],'focus','standalone focus click')
c.units.focus=c.goal;stepButton.hooks.PostClick(stepButton,'RightButton',false)
eq(c.F.session.committed,true,'standalone focus callback verifies its actual result')
eq(stepButton.attrs['*macrotext2'],'/stopmacro','standalone callback disarms its action after the click')
stepButton.hooks.PreClick(stepButton,'RightButton',false)
oneAction(stepButton.attrs['*macrotext2'],'cleartarget','standalone restore click')
c.units.target=nil;stepButton.hooks.PostClick(stepButton,'RightButton',false)
eq(c.F.lastResult.kind,'complete','standalone callbacks complete only after actual restoration')
eq(stepButton.shown,false,'standalone controls hide after completion')

-- A live hostile original without an independent alias must be restored by
-- GUID through separate reverse-cycle hardware events, never by nameplate ID.
c=setup();c.units.target=c.original
prepare(c,'targetenemy');targetResult(c,c.wrong)
prepare(c,'targetenemy');targetResult(c,c.third)
prepare(c,'targetenemy');targetResult(c,c.goal)
eq(c.F.session.seekSteps,3,'search records three observed forward steps')
commitGoal(c)
for _,value in ipairs({c.third,c.wrong,c.original}) do
 macro=prepare(c,'targetenemy')
 eq(macro:find('/targetenemy 1',1,true)~=nil,true,'hostile restoration uses reverse cycling')
 eq(macro:find('nameplate',1,true),nil,'restoration does not use a read-only nameplate as a canonical alias')
 targetResult(c,value,true)
end
eq(c.F.lastResult.kind,'complete','reverse cycling finishes only on the original GUID')
eq(c.F.lastResult.targetRestored,true,'reverse-cycle completion confirms original target identity')
eq(c.units.target,c.original,'three reverse fixtures reach the exact original enemy')
eq(c.units.focus,c.goal,'restoring an original enemy preserves committed focus')

-- A changed canonical alias cannot silently select the new unit behind it.
c=setup();c.units.target=c.original;c.units.boss1=c.original
matchGoal(c);commitGoal(c)
c.units.boss1=c.wrong
macro=prepare(c)
eq(macro and macro:find('[@boss1',1,true)~=nil,false,'changed canonical alias is not used for restoration')
if #nativeLines(macro)>0 then
 oneAction(macro,'targetenemy','changed-alias fallback')
 targetResult(c,c.original,true)
 eq(c.F.lastResult.targetRestored,true,'changed hostile alias may fall back to exact reverse restoration')
else
 eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,'refused alias restoration does not report completion')
end

-- Third-party target/focus changes terminate ownership without overwriting
-- the player's new selection or focus.
c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
c.units.target=c.third
macro=prepare(c)
noAction(macro,'manual target change prevents the next native action')
eq(c.units.target,c.third,'manual target is not overwritten by preparation')
eq(c.units.focus,c.priorFocus,'manual-target abort preserves the previous focus')
eq(c.F.lastResult.kind,'aborted','manual target change is an abort, not a completed restoration')
eq(c.F.lastResult.targetRestored,false,'manual-target abort does not claim restoration')

c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
c.units.focus=c.third
macro=prepare(c)
noAction(macro,'manual focus change prevents another native action')
eq(c.units.focus,c.third,'manual focus is not overwritten')
eq(c.F.lastResult.kind,'aborted','manual focus change aborts ownership')
eq(c.F.lastResult.focusSet,false,'manual focus change cannot count as this flow committing focus')

-- Native target-change events inside an observed click are expected; events
-- outside that window release ownership immediately.
c=setup();prepare(c,'targetenemy')
c.units.target=c.wrong;c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.IsActive(),true,'target-change event inside the pending click does not abort it')
c.hooks.TargetNearestEnemy(false);c.F.AfterClick(c.row)
eq(c.F.session.ownedTarget.guid,c.wrong.guid,'the matching API/Post observation owns the changed target')
c.units.target=c.third;c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.IsActive(),false,'manual target event outside a pending click ends ownership')
eq(c.F.lastResult.kind,'aborted','manual target event cannot be a successful completion')

c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
c.units.focus=c.third;c.F.OnEvent('PLAYER_FOCUS_CHANGED')
eq(c.F.IsActive(),false,'manual focus event ends the flow immediately')
eq(c.units.focus,c.third,'manual focus event preserves the newly selected focus')

c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
c.combat=true;c.F.OnEvent('PLAYER_REGEN_DISABLED')
eq(c.F.IsActive(),true,'entering combat pauses an owned flow')
eq(c.F.session.paused~=nil,true,'combat event records the paused presentation')
c.combat=false;c.F.OnEvent('PLAYER_REGEN_ENABLED')
prepare(c,'targetenemy')

c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
c.F.OnEvent('PLAYER_LEAVING_WORLD')
eq(c.F.IsActive(),false,'leaving the world ends the in-memory flow')
eq(c.F.lastResult.kind,'aborted','world transition is reported as an abort')
eq(c.F.lastResult.targetRestored,false,'world transition does not claim an unrecovered target')

-- Disappearance/death before committing focus restores rather than focusing a
-- recycled token or an invalid goal.
for _,cause in ipairs({'dead','gone'}) do
 c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
 if cause=='dead' then c.goal.dead=true else c.units.nameplate1=nil end
 macro=prepare(c,'cleartarget')
 eq(macro:find('/focus',1,true),nil,cause..' goal does not arm focus')
 clearResult(c)
 eq(c.F.lastResult.kind,'failed_restored',cause..' goal reports failure after restoration')
 eq(c.F.lastResult.focusSet,false,cause..' goal does not report a committed focus')
 eq(c.F.lastResult.targetRestored,true,cause..' goal still restores the original empty target')
 eq(c.units.focus,c.priorFocus,cause..' goal preserves the original focus')
end

-- Pauses consume no native action and do not turn a temporary read failure
-- into completion; removing the pause permits a later hardware step.
for _,pause in ipairs({'combat','spellCursor','itemCursor'}) do
 c=setup();prepare(c,'targetenemy');targetResult(c,c.wrong)
 c[pause]=true
 macro=prepare(c)
 noAction(macro,pause..' pauses without a native action')
 eq(c.units.target,c.wrong,pause..' pause leaves the owned target alone')
 eq(c.units.focus,c.priorFocus,pause..' pause leaves focus alone')
 eq(c.F.IsActive(),true,pause..' pause retains a resumable flow')
 c[pause]=false
 prepare(c,'targetenemy')
end

-- Cancelling before focus commit restores the target and preserves old focus.
c=setup();matchGoal(c)
prepare(c,'cleartarget',true);clearResult(c)
eq(c.F.lastResult.kind=='complete',false,'cancel does not claim a successful focus operation')
eq(c.F.lastResult.focusSet,false,'cancel before commit records no focus assignment')
eq(c.F.lastResult.targetRestored,true,'cancel verifies original target restoration')
eq(c.units.focus,c.priorFocus,'cancel preserves old focus')

-- A requested focus macro with no actual focus effect is a failed operation,
-- even when the subsequent target recovery succeeds.
c=setup();matchGoal(c);prepare(c,'focus')
c.F.AfterClick(c.row) -- no fixture focus change: the native action had no observed effect
eq(c.F.session.committed,false,'a prepared focus macro alone does not commit focus')
prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'failed_restored','failed focus readback remains failure after target restoration')
eq(c.F.lastResult.focusSet,false,'failed focus readback cannot count as an assignment')
eq(c.F.lastResult.targetRestored,true,'failed focus still reports the verified recovery separately')

-- An unexpected alias/name/clear result is recorded separately from owned
-- target state. A delayed native target event must retain that blocked result,
-- while only an explicit restore request may adopt it for another attempt.
local function blockedRestore(kind)
 local context=setup()
 local original
 if kind=='alias' then original=context.self
 elseif kind=='name' then
  original={guid='Player-BlockedOriginal',name='恢复原玩家',player=true,harm=false,dead=false,connected=true}
 end
 context.units.target=original
 matchGoal(context);commitGoal(context)
 local command=kind=='empty' and 'cleartarget' or kind=='alias' and 'target' or 'targetexact'
 prepare(context,command)
 context.units.target=context.wrong
 context.F.AfterClick(context.row)
 eq(context.F.session.state,'blocked',kind..' wrong restore result remains blocked')
 eq(context.F.session.ownedTarget.guid,context.goal.guid,kind..' wrong restore result is not automatically owned')
 eq(context.F.session.blockedTarget.guid,context.wrong.guid,kind..' blocked result has a separate snapshot')
 return context,original,command
end
for _,kind in ipairs({'empty','alias','name'}) do
 local original,command
 c,original,command=blockedRestore(kind)
 local blockedSession=c.F.session
 c.F.OnEvent('PLAYER_TARGET_CHANGED') -- delayed event generated by the failed restore
 eq(c.F.session,blockedSession,kind..' delayed target event does not destroy the blocked flow')
 macro=prepare(c)
 noAction(macro,kind..' blocked target cannot trigger another action without explicit restore')
 eq(c.F.session,blockedSession,kind..' blocked preparation preserves the diagnostic session')
 eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,kind..' mismatch never claims restoration')
 c.F.Command('restore')
 eq(c.F.session.ownedTarget.guid,c.wrong.guid,kind..' explicit restore adopts only its recorded blocked result')
 eq(c.F.session.blockedTarget,nil,kind..' explicit restore consumes the blocked result snapshot')
 prepare(c,command)
 c.units.target=original;c.F.AfterClick(c.row)
 eq(c.F.lastResult.kind,'complete',kind..' explicit retry completes only after original target readback')
 eq(c.F.lastResult.targetRestored,true,kind..' explicit retry confirms exact target restoration')
 eq(c.units.focus,c.goal,kind..' explicit retry preserves committed focus')
end

c=blockedRestore('name')
c.units.target=c.third
c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.IsActive(),false,'later unrelated target change aborts a blocked flow')
eq(c.F.lastResult.kind,'aborted','later unrelated target is not mistaken for a delayed native event')
eq(c.units.target,c.third,'aborting a blocked flow preserves the new manual target')

c=blockedRestore('name')
c.units.target=c.third
c.F.Command('restore') -- target changed before its event was delivered
eq(c.F.session.ownedTarget.guid,c.goal.guid,'explicit restore never adopts a target different from its blocked snapshot')
macro=prepare(c)
noAction(macro,'unrelated target cannot be overwritten by an explicit blocked retry')
eq(c.F.lastResult.kind,'aborted','unrelated target ends ownership before retry action')

local original
c,original=blockedRestore('name')
c.units.target=original;c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.lastResult.kind,'complete','manually restoring the exact original target resolves a blocked flow')
eq(c.F.lastResult.targetRestored,true,'manual recovery completion verifies the original GUID')

-- Duplicate preparation may not replace an in-flight observation window.
c=setup();prepare(c,'targetenemy')
local pending=c.F.current
local pendingReason
macro,pendingReason=prepare(c)
noAction(macro,'another preparation cannot issue a command while a click is pending')
eq(pendingReason,'click_pending','duplicate preparation reports the pending hardware step')
eq(c.F.current,pending,'duplicate preparation preserves the first observation identity')
targetResult(c,c.wrong)
eq(c.F.session.seekSteps,1,'only the original pending action is counted')

c=setup()
for i=1,4 do prepare(c,'targetenemy');targetResult(c,c.wrong) end
eq(c.F.session.state,'restore','three repeated unadvanced targets stop forward searching')
eq(c.F.session.reason,'cycle_stalled','stalled search is distinguished from exhausting the search budget')
prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'failed_restored','stalled search is failure after target recovery')
eq(c.F.lastResult.reason,'cycle_stalled','stalled search retains its actual failure reason')

c=setup();c.NS.Diagnostics.Start=function() error('simulated logger failure') end
macro=prepare(c)
noAction(macro,'logger startup exception prevents a protected action')
eq(c.F.IsActive(),false,'logger startup exception leaves no active flow')
eq(c.units.target,nil,'logger startup exception preserves the empty original target')
eq(c.units.focus,c.priorFocus,'logger startup exception preserves old focus')

-- Bounded search failure must restore, while exhausted restoration must remain
-- visibly blocked and never claim that the original target was recovered.
c=setup()
for i=1,20 do
 prepare(c,'targetenemy');targetResult(c,i%2==0 and c.third or c.wrong)
end
prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'failed_restored','search limit is failure with restoration, not success')
eq(c.F.lastResult.focusSet,false,'search limit never commits focus')
eq(c.F.lastResult.targetRestored,true,'search-limit failure confirms empty target recovery')

c=setup();c.units.target=c.original;matchGoal(c);commitGoal(c)
for i=1,40 do
 prepare(c,'targetenemy');targetResult(c,i%2==0 and c.third or c.wrong,true)
end
macro=prepare(c)
noAction(macro,'blocked restoration cannot keep issuing unbounded native actions')
eq(c.F.session.state,'blocked','exhausted restore budget blocks the next hardware action')
eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,'restore limit never reports completion')

-- An original NPC which cannot be safely restored must be refused before the
-- first selection. Existing targets/focuses with unreadable identity are also
-- refused rather than mistaken for an empty slot.
for _,original in ipairs({
 {guid='Creature-Friendly',name='友方NPC',player=false,harm=false,dead=false},
 {guid='Creature-Dead',name='死掉的NPC',player=false,harm=true,dead=true},
}) do
 c=setup();c.units.target=original
 macro=prepare(c)
 noAction(macro,'unrestorable original NPC is refused before targeting')
 eq(c.F.IsActive(),false,'unrestorable original NPC never starts a live cycle')
 eq(c.units.target,original,'unrestorable original NPC remains selected')
end
for _,slot in ipairs({'target','focus'}) do
 c=setup();c.units[slot]={guid=secret,name='不可读',player=false,harm=true,dead=false}
 macro=prepare(c)
 noAction(macro,'secret '..slot..' identity refuses startup')
 eq(c.F.IsActive(),false,'secret '..slot..' identity never starts a live flow')
end
c=setup();c.data.guid=secret
macro=prepare(c)
noAction(macro,'secret goal GUID refuses startup')
eq(c.F.IsActive(),false,'secret goal GUID is never frozen into a live flow')
for _,slot in ipairs({'target','focus'}) do
 c=setup()
 local readableExists=UnitExists
 UnitExists=function(unit) if unit==slot then return nil end;return readableExists(unit) end
 macro=prepare(c)
 noAction(macro,'unknown '..slot..' existence refuses startup')
 eq(c.F.IsActive(),false,'unknown '..slot..' existence cannot mean an empty slot')
 eq(c.F.button,nil,'unknown original identity refuses before creating action controls')
end
c=setup();c.combat=nil
macro=prepare(c)
noAction(macro,'unknown combat state refuses startup')
eq(c.F.IsActive(),false,'unknown combat state cannot start a flow')
c=setup();c.spellCursor=nil
macro=prepare(c)
noAction(macro,'unknown spell cursor state refuses startup')
eq(c.F.IsActive(),false,'unknown spell cursor state cannot start a flow')

c=setup();c.units.focus=nil
matchGoal(c);commitGoal(c);prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'complete','a positively absent original focus is a valid baseline')
eq(c.F.lastResult.focusSet,true,'empty original focus can receive the verified requested focus')

-- Only exactly one API-return observation, consistent with PostClick, may be
-- adopted as our target. Fixtures here deliberately model missing/interfered
-- observation, not native secure behavior.
for _,case in ipairs({'missing','double','changed_after_sample'}) do
 c=setup();prepare(c,'targetenemy')
 c.units.target=c.wrong
 if case~='missing' then c.hooks.TargetNearestEnemy(false) end
 if case=='double' then c.units.target=c.third;c.hooks.TargetNearestEnemy(false) end
 if case=='changed_after_sample' then c.units.target=c.third end
 c.F.AfterClick(c.row)
 eq(c.F.session~=nil and c.F.session.committed==true,false,case..' observation cannot commit focus')
 eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,case..' observation cannot report completion')
 eq(c.units.focus,c.priorFocus,case..' observation preserves focus')
end

-- Default optimization combines only the confirmed focus with the first
-- restoration action. Every outcome below is supplied by an explicit fixture;
-- observing two command lines is not proof that either native action ran.
local function latestRecord(context,kind)
 for i=#context.records,1,-1 do
  if context.records[i].kind==kind then return context.records[i].fields end
 end
 error('missing record '..kind)
end
local function combinedAction(context,restoreAction,command)
 local text=context.F.Prepare(context.row,context.data)
 local lines=nativeLines(text)
 eq(#lines,2,'combined click contains focus and exactly one restoration command')
 eq(lines[1],'/focus [@target,exists]','combined click focuses the already verified current goal first')
 eq(lines[2]:match('^/'..command..'%f[%A]')~=nil,true,'combined click uses the intended first restoration')
 eq(text,'/stopmacro [combat]\n'..lines[1]..'\n'..lines[2],'combined restoration is not conditional on the focus command succeeding')
 if restoreAction=='restore_cycle' then eq(lines[2],'/targetenemy 1','combined enemy restoration takes one reverse step') end
 eq(text:find('/run',1,true),nil,'combined click does not call protected actions through ordinary Lua')
 eq(text:find('/cast',1,true),nil,'combined click never casts')
 eq(context.F.current.action,'focus_restore','combined click has a distinct pending action')
 eq(context.F.current.restoreAction,restoreAction,'combined click preserves its restoration strategy')
 local pre=latestRecord(context,'FOCUS_CYCLE_PRE')
 eq(pre.combined,true,'combined click is identified explicitly in diagnostics')
 eq(pre.restoreAction,restoreAction,'diagnostics record the selected first restoration')
 return text,lines
end

c=setup(true);matchGoal(c)
combinedAction(c,'restore_empty','cleartarget')
c.units.focus=c.goal;c.units.target=nil;c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'complete','default combined empty-target flow completes on both actual readbacks')
eq(c.F.lastResult.focusSet,true,'combined empty-target flow verifies focus independently')
eq(c.F.lastResult.targetRestored,true,'combined empty-target flow verifies restored target independently')
eq(c.F.IsActive(),false,'successful combined empty-target flow needs no extra restore click')

c=setup(true);matchGoal(c)
combinedAction(c,'restore_empty','cleartarget')
c.units.target=nil -- focus deliberately remains old: only restoration took effect
c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'failed_restored','target recovery cannot hide a failed focus action')
eq(c.F.lastResult.focusSet,false,'failed combined focus is not reported as set')
eq(c.F.lastResult.targetRestored,true,'failed combined focus still reports actual target recovery')
eq(c.units.focus,c.priorFocus,'failed combined focus preserves the actual old focus')

c=setup(true);matchGoal(c)
combinedAction(c,'restore_empty','cleartarget')
c.units.focus=c.goal -- clear target deliberately has no observed effect
c.F.AfterClick(c.row)
eq(c.F.session.committed,true,'successful combined focus is retained when clear-target fails')
eq(c.F.session.state,'restore','unsuccessful first restoration retains the restoration phase')
eq(c.F.combineFocusRestore,false,'unobserved combined clear automatically falls back to separate restoration')
eq(latestRecord(c,'FOCUS_CYCLE_COMBINED_FALLBACK').reason,'restore_not_observed','fallback diagnostics identify the unobserved restoration')
eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,'focus alone does not complete a combined operation')
prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'complete','later standalone restoration may complete a verified combined focus')

for _,strategy in ipairs({'alias','name'}) do
 c=setup(true)
 local originalPlayer={guid='Player-Combined-'..strategy,name='合并恢复原目标',player=true,harm=false,dead=false,connected=true}
 c.units.target=originalPlayer
 if strategy=='alias' then c.units.party1=originalPlayer end
 matchGoal(c)
 local command=strategy=='alias' and 'target' or 'targetexact'
 local text=combinedAction(c,'restore_'..strategy,command)
 if strategy=='alias' then
  eq(text:find('/target [@party1,exists]',1,true)~=nil,true,'combined alias restoration uses the verified canonical token')
 else
  eq(text:find(originalPlayer.name..'-测试服务器',1,true)~=nil,true,'combined name restoration uses the frozen full player name')
 end
 c.units.focus=c.goal;c.units.target=originalPlayer;c.F.AfterClick(c.row)
 eq(c.F.lastResult.kind,'complete',strategy..' combined restoration completes only after exact original GUID readback')
 eq(c.F.lastResult.focusSet,true,strategy..' combined restoration verifies focus')
 eq(c.F.lastResult.targetRestored,true,strategy..' combined restoration verifies target')
end

c=setup(true);c.units.target=c.original;c.units.boss1=c.original
matchGoal(c)
c.units.boss1=c.wrong -- alias changed after capture, before combined preparation
local combinedText=combinedAction(c,'restore_cycle','targetenemy')
eq(combinedText:find('[@boss1',1,true),nil,'combined preparation revalidates a canonical alias before using it')
eq(combinedText:find('/targetenemy 1',1,true)~=nil,true,'changed hostile alias falls back to one reverse step')
c.units.focus=c.goal;c.units.target=c.original;c.hooks.TargetNearestEnemy(true);c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'complete','combined reverse fallback can verify an immediate return to original')

c=setup(true);c.units.target=c.original
matchGoal(c)
combinedAction(c,'restore_cycle','targetenemy')
c.units.focus=c.goal;c.units.target=c.wrong;c.hooks.TargetNearestEnemy(true);c.F.AfterClick(c.row)
eq(c.F.session.committed,true,'combined reverse step retains a verified focus commitment')
eq(c.F.session.state,'restore','one reverse step may leave more restoration work')
eq(c.F.session.restoreSteps,1,'combined reverse action counts its one observed restore step')
eq(c.F.session.ownedTarget.guid,c.wrong.guid,'combined reverse step owns only the actual matching sampled GUID')
macro=prepare(c,'targetenemy')
eq(macro:find('/focus',1,true),nil,'later reverse steps never repeat an already committed focus')
eq(macro:find('/targetenemy 1',1,true)~=nil,true,'later reverse step preserves reverse direction')
targetResult(c,c.original,true)
eq(c.F.lastResult.kind,'complete','combined reverse flow completes after later exact original recovery')

c=setup(true);c.units.target=c.original
matchGoal(c)
combinedAction(c,'restore_cycle','targetenemy')
c.units.target=c.original;c.hooks.TargetNearestEnemy(true);c.F.AfterClick(c.row)
eq(c.F.lastResult.kind,'failed_restored','combined reverse target recovery cannot make failed focus successful')
eq(c.F.lastResult.focusSet,false,'failed combined reverse focus remains uncommitted')
eq(c.F.lastResult.targetRestored,true,'failed combined reverse focus still acknowledges original target recovery')

-- An alias may change between preparation and execution. Its wrong result is
-- still blocked, and a delayed native event does not erase the recovery UI.
c=setup(true);c.units.target=c.original;c.units.boss1=c.original
matchGoal(c)
combinedAction(c,'restore_alias','target')
c.units.boss1=c.wrong;c.units.focus=c.goal;c.units.target=c.wrong;c.F.AfterClick(c.row)
eq(c.F.session.state,'blocked','combined wrong alias result is blocked')
eq(c.F.session.committed,true,'combined wrong alias result does not lose verified focus')
eq(c.F.session.blockedTarget.guid,c.wrong.guid,'combined wrong alias result keeps a recovery snapshot')
eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,'combined wrong alias result cannot complete')
local combinedBlocked=c.F.session
c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.session,combinedBlocked,'combined wrong alias delayed event preserves blocked recovery')
noAction(prepare(c),'combined blocked recovery cannot silently issue another action')

for _,observation in ipairs({'missing','double','changed_after_sample'}) do
 c=setup(true);c.units.target=c.original;matchGoal(c)
 combinedAction(c,'restore_cycle','targetenemy')
 c.units.focus=c.goal;c.units.target=c.wrong
 if observation~='missing' then c.hooks.TargetNearestEnemy(true) end
 if observation=='double' then c.units.target=c.third;c.hooks.TargetNearestEnemy(true) end
 if observation=='changed_after_sample' then c.units.target=c.third end
 c.F.AfterClick(c.row)
 eq(c.F.lastResult~=nil and c.F.lastResult.kind=='complete',false,observation..' combined reverse observation cannot prove completion')
 eq(c.F.session.committed,true,observation..' combined reverse observation retains independently verified focus')
 eq(c.F.session.ownedTarget.guid==c.units.target.guid,false,observation..' combined reverse result is not automatically owned')
end

-- If the original target already is the goal, focusing alone is sufficient;
-- the optimization must not rotate away from an already restored selection.
c=setup(true);c.units.target=c.goal
macro=prepare(c,'focus')
eq(#nativeLines(macro),1,'goal already selected uses only the native focus command')
eq(macro:find('/targetenemy',1,true),nil,'goal already selected does not rotate target')
eq(macro:find('/cleartarget',1,true),nil,'goal already selected does not clear the original target')
focusResult(c,c.goal)
eq(c.F.lastResult.kind,'complete','goal already selected completes without an unnecessary restore click')
eq(c.units.target,c.goal,'goal already selected remains selected')

c=setup(true);prepare(c,'targetenemy')
local activeCombinedSession=c.F.session
c.F.Command('staged')
eq(c.F.combineFocusRestore,true,'staged setting cannot change an active flow')
eq(c.F.session,activeCombinedSession,'attempting a mode change preserves the active flow')
c.F.Command('stop')
c.F.Command('staged')
eq(c.F.combineFocusRestore,false,'staged setting can be changed after the flow stops')

-- A skipped second command switches to restoration-only on the next click;
-- selecting original A must never focus A after goal B was already committed.
for _,strategy in ipairs({'alias','name','cycle'}) do
 c=setup(true)
 local originalTarget=strategy=='cycle' and c.original
  or {guid='Player-Fallback-'..strategy,name='回退原目标',player=true,harm=false,dead=false,connected=true}
 c.units.target=originalTarget
 if strategy=='alias' then c.units.party1=originalTarget end
 matchGoal(c)
 local restoreCommand=strategy=='alias' and 'target' or strategy=='name' and 'targetexact' or 'targetenemy'
 combinedAction(c,'restore_'..strategy,restoreCommand)
 c.units.focus=c.goal -- no restore fixture/hook: current target remains goal
 c.F.AfterClick(c.row)
 eq(c.F.combineFocusRestore,false,strategy..' skipped combined restoration disables the combined optimization')
 eq(c.F.session.committed,true,strategy..' skipped restore retains its successful focus result')
 eq(c.F.session.state,'restore',strategy..' skipped restore requires a later hardware restoration')
 eq(c.F.session.ownedTarget.guid,c.goal.guid,strategy..' skipped restore still owns the unchanged target')
 macro=prepare(c,restoreCommand)
 eq(macro:find('/focus',1,true),nil,strategy..' fallback never focuses the original target on its next click')
 c.units.target=originalTarget
 if strategy=='cycle' then c.hooks.TargetNearestEnemy(true) end
 c.F.AfterClick(c.row)
 eq(c.F.lastResult.kind,'complete',strategy..' fallback completes only after exact original recovery')
 eq(c.units.focus,c.goal,strategy..' fallback keeps goal B as focus when original A is selected')
end

-- Combat can begin between the two commands. Public completed work is still
-- adopted, while future protected work waits for another out-of-combat click.
c=setup(true);matchGoal(c)
combinedAction(c,'restore_empty','cleartarget')
c.units.focus=c.goal;c.combat=true;c.F.OnEvent('PLAYER_REGEN_DISABLED')
c.F.AfterClick(c.row) -- focus happened, restoration did not
eq(c.F.session.committed,true,'mid-combination combat retains a verified focus result')
eq(c.F.session.state,'restore','mid-combination combat keeps unfinished restoration')
eq(c.F.session.paused,'战斗中','mid-combination combat pauses further hardware preparation')
eq(c.F.combineFocusRestore,false,'mid-combination skipped restoration falls back without repeating focus')
noAction(prepare(c),'mid-combination combat does not prepare another native action')
c.combat=false;c.F.OnEvent('PLAYER_REGEN_ENABLED')
eq(c.F.session.paused,nil,'leaving combat clears the combat pause')
prepare(c,'cleartarget');clearResult(c)
eq(c.F.lastResult.kind,'complete','mid-combination interruption can finish on a later restoration click')
eq(c.units.focus,c.goal,'mid-combination recovery preserves the already committed focus')

c=setup(true);matchGoal(c)
combinedAction(c,'restore_empty','cleartarget')
c.units.focus=c.goal;c.units.target=nil;c.combat=true;c.F.OnEvent('PLAYER_REGEN_DISABLED')
c.F.AfterClick(c.row) -- both commands completed before/during the combat transition
eq(c.F.IsActive(),false,'mid-combination combat does not discard fully verified completion')
eq(c.F.lastResult.kind,'complete','mid-combination combat reports completion only when both states match')
eq(c.F.lastResult.focusSet,true,'mid-combination completion independently verifies focus')
eq(c.F.lastResult.targetRestored,true,'mid-combination completion independently verifies restored target')
c.combat=false;c.F.OnEvent('PLAYER_REGEN_ENABLED')
eq(c.row.attrs['focus-cycle-active'],nil,'completed-in-combat flow clears its deferred row flag out of combat')
eq(c.F.button.shown,false,'completed-in-combat controls hide safely after combat ends')

c=setup(true);c.units.target=c.original;matchGoal(c)
combinedAction(c,'restore_cycle','targetenemy')
c.units.focus=c.goal;c.units.target=c.wrong;c.hooks.TargetNearestEnemy(true)
c.combat=true;c.F.OnEvent('PLAYER_REGEN_DISABLED');c.F.AfterClick(c.row)
eq(c.F.session.committed,true,'mid-combination reverse action retains verified focus')
eq(c.F.session.ownedTarget.guid,c.wrong.guid,'mid-combination reverse action adopts its verified target result')
eq(c.F.session.restoreSteps,1,'mid-combination reverse action records its completed restoration step')
eq(c.F.session.paused,'战斗中','mid-combination reverse restoration pauses future steps')
c.F.OnEvent('PLAYER_TARGET_CHANGED')
eq(c.F.IsActive(),true,'delayed event for a verified in-combat reverse step keeps ownership')
c.combat=false;c.F.OnEvent('PLAYER_REGEN_ENABLED')
macro=prepare(c,'targetenemy')
eq(macro:find('/focus',1,true),nil,'reverse restoration after combat never refocuses the reached original target')
targetResult(c,c.original,true)
eq(c.F.lastResult.kind,'complete','verified partial reverse restoration resumes after combat')
eq(c.units.focus,c.goal,'resumed reverse restoration preserves committed goal focus')

print('Focus cycle simulated checks: '..checks..' passed; no native macro or protected action tested.')
