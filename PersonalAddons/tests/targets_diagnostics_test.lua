-- Diagnostics contracts only; these assertions do not execute a secure cast.
local checks, secret, clock = 0, {}, 10
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
function issecretvalue(value) return value==secret end
local methods={}
function methods:RegisterEvent(event) self.events[event]=true end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function CreateFrame() return setmetatable({events={},scripts={}},{__index=methods}) end
function GetTime() return clock end
function GetServerTime() return 123 end
function InCombatLockdown() return false end
function GetBindingAction() return "MULTIACTIONBAR1BUTTON3" end
function UnitExists() return false end
function GetMouseFoci() return {} end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local function loadAddon()
    local ns={}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",ns)
    ns.NativeMacroOnly=false -- Historical diagnostics contracts below are unchanged.
    assert(loadfile(root.."Diagnostics.lua"))("MyForeverTargets",ns)
    ns.Diagnostics.Initialize()
    return ns,ns.Diagnostics
end
local ns,D=loadAddon()
local function last() local events=MyForeverTargetsLogDB.events;return events[#events] end
eq(D.Enabled(),false,"default disabled")
eq(D.Session(),0,"public log session starts at zero")
eq(D.Record("OFF",{}),false,"disabled logger has no record")
eq(#MyForeverTargetsLogDB.events,0,"disabled logger has no events")
D.Start()
eq(D.Enabled(),true,"start enables logger")
eq(D.Session(),1,"starting a log advances the public capability session")
eq(last().kind,"START","start marker")
eq(last().fields.maxSeconds,14400,"start records the four-hour time limit")
eq(last().fields.maxEvents,5000,"start records the bounded event capacity")
D.Record("VALUES",{hidden=secret,flag=false,zero=0,nested={macroBody="private"}})
eq(last().fields.hidden,"[restricted]","secret is never saved")
eq(last().fields.flag,false,"false preserved")
eq(last().fields.zero,0,"zero preserved")
eq(last().fields.nested,"[unsupported]","no arbitrary table serialization")
eq(D.Safe(string.rep("中",100)),string.rep("中",85),"Chinese truncation keeps UTF8 boundaries")
for i=1,D.MAX_EVENTS+10 do D.Record("CAP",{index=i}) end
eq(D.MAX_EVENTS,5000,"increased log capacity")
eq(#MyForeverTargetsLogDB.events,5000,"bounded records")
eq(MyForeverTargetsLogDB.dropped>0,true,"eviction counted")
D.frame.scripts.OnEvent(D.frame,"UNIT_SPELLCAST_SENT","player",secret,"cast-1",679)
eq(last().kind,"UNIT_SPELLCAST_SENT","sent event")
eq(last().fields.sentTarget,"[restricted]","secret recipient redacted")
eq(last().fields.spellID,679,"sent spell mapped")
D.frame.scripts.OnEvent(D.frame,"UNIT_SPELLCAST_SUCCEEDED","player","cast-1",679)
eq(last().fields.spellID,679,"success spell mapped")
eq(last().fields.damage,nil,"cast success never invents damage")
local sequence=MyForeverTargetsLogDB.sequence
D.frame.scripts.OnEvent(D.frame,"UNIT_SPELLCAST_SUCCEEDED","party1","cast-other",679)
eq(MyForeverTargetsLogDB.sequence,sequence,"other casters excluded")
function UnitGUID() error("unavailable unit API") end
eq(D.Snapshot("API_ERROR"),true,"API error does not abort logging")
eq(last().fields.targetGUID,"[api-error]","API failure labelled")
-- Combat preparation is independent from the out-of-combat bridge count.
ns.HoveredTile={unit="nameplate1",side="enemy",expectedGUID="Creature-hover",GetName=function() return "TestRow" end,
    GetAttribute=function(_,key) if key=="unit" then return "nameplate1" end end}
SecureButton_GetUnit=function() return "target" end
ns.NearbyCast={count=0}
ns.CombatCast={Status=function() return {prepared=true,count=1,name="测试怪物",guid="Creature-hover",unit="nameplate1",reason="ready"} end}
local identities={nameplate1="Creature-hover",target="Creature-other",mouseover="Creature-other"}
function UnitGUID(unit) return identities[unit] end
identities.focus="Creature-hover"
D.frame.scripts.OnEvent(D.frame,"PLAYER_FOCUS_CHANGED")
eq(D.frame.events.PLAYER_FOCUS_CHANGED,true,"focus changes are observed without changing focus")
eq(last().kind,"PLAYER_FOCUS_CHANGED","focus event is preserved")
eq(last().fields.focusGUID,"Creature-hover","focus event records the actual focus")
eq(last().fields.targetGUID,"Creature-other","focus log distinguishes the unchanged current target")
eq(last().fields.focusMatchesHover,true,"focus identity is compared to hovered unit")
identities.focus=secret
D.Snapshot("RESTRICTED_FOCUS")
eq(last().fields.focusGUID,"[restricted]","restricted focus GUID is never exposed")
eq(last().fields.focusMatchesHover,"[unknown]","restricted focus cannot prove a match")
identities.focus=nil
D.Snapshot("COMBAT_STATUS")
eq(last().fields.frameUnitAttribute,"nameplate1","actual frame attribute is read independently from row data")
eq(last().fields.frameResolvedUnit,"target","secure unit resolution is observed independently, not assumed from the tile")
eq(last().fields.nativeMouseoverMatchesHover,false,"different public native mouseover GUID is explicitly false")
eq(last().fields.targetMatchesHover,false,"different public target GUID is explicitly false")
eq(last().fields.combatPrepared,true,"zero OOC bridge count does not erase prepared combat state")
eq(last().fields.combatPreparedCount,1,"combat preparation count recorded separately")
eq(last().fields.combatSnapshotMatchesHover,true,"prepared snapshot can match the live public hover GUID")
identities.target="Creature-hover";identities.mouseover="Creature-hover"
D.Snapshot("MATCHED_GUID")
eq(last().fields.nativeMouseoverMatchesHover,true,"same public native mouseover GUID is true")
eq(last().fields.targetMatchesHover,true,"same public target GUID is true")
identities.nameplate1=secret;identities.target=secret;identities.mouseover=secret
D.Snapshot("UNKNOWN_GUID")
eq(last().fields.nativeMouseoverMatchesHover,"[unknown]","two restricted labels never imply same native unit")
eq(last().fields.targetMatchesHover,"[unknown]","two restricted labels never imply same target")
eq(last().fields.combatSnapshotMatchesHover,"[unknown]","restricted hover cannot confirm combat snapshot identity")
local timeoutMessages={}
ns.Print=function(message) timeoutMessages[#timeoutMessages+1]=message end
D.frame.scripts.OnUpdate(D.frame,1201)
eq(D.Enabled(),true,"twenty minutes no longer stops a normal user test window")
D.frame.scripts.OnUpdate(D.frame,D.MAX_SECONDS-1202)
eq(D.Enabled(),true,"recording stays enabled immediately before four hours")
D.frame.scripts.OnUpdate(D.frame,1.01)
eq(D.Enabled(),false,"time limit stops recording")
eq(last().fields.reason,"4-hour-limit","timeout reason names the actual configured limit")
eq(last().fields.maxSeconds,14400,"stop records the actual configured limit")
eq(last().fields.activeSeconds>=14400,true,"timeout record retains accumulated logging duration")
eq(timeoutMessages[#timeoutMessages]:find("4小时",1,true)~=nil,true,"timeout notification names four hours")
D.Start()
D.Command("mark 中文步骤")
eq(last().fields.note,"中文步骤","mark records supplied step")
D.frame.scripts.OnUpdate(D.frame,10)
local accumulated=MyForeverTargetsLogDB.activeSeconds
local before=MyForeverTargetsLogDB.sequence
ns,D=loadAddon()
eq(D.Enabled(),true,"enabled state resumes after reload")
eq(last().kind,"RESUME","reload marker")
eq(MyForeverTargetsLogDB.sequence,before+1,"reload preserves sequence")
eq(#MyForeverTargetsLogDB.events,5000,"reload preserves bounded history")
eq(MyForeverTargetsLogDB.activeSeconds,accumulated,"reload preserves accumulated duration instead of silently resetting it")
D.Command("stop")
eq(D.Enabled(),false,"stop command")
eq(D.Record("AFTER_STOP",{}),false,"stopped log does not record")
eq(D.BeginCastAttempt({spellID=679}),nil,"disabled normal logger does not create an attempt")
local function find(kind,id)
    local events=MyForeverTargetsLogDB.events
    for i=#events,1,-1 do
        local e=events[i]
        if e.kind==kind and (id==nil or e.fields.attemptID==id) then return e end
    end
end
local function step(seconds)
    clock=clock+seconds
    D.frame.scripts.OnUpdate(D.frame,seconds)
end
local function emit(event,...)
    D.frame.scripts.OnEvent(D.frame,event,...)
end
local messages={}
ns.Print=function(message) messages[#messages+1]=message end
D.Command("start")
eq(messages[#messages]:find("5000",1,true)~=nil,true,"start reports current capacity")
eq(messages[#messages]:find("4小时",1,true)~=nil,true,"start reports the four-hour window")
eq(MyForeverTargetsLogDB.activeSeconds,0,"a deliberate new test start resets the duration")
D.MAX_EVENTS=5001;D.Command("status")
eq(messages[#messages]:find("/5001条",1,true)~=nil,true,"status reads dynamic capacity")
eq(messages[#messages]:find("4小时",1,true)~=nil,true,"status reports the actual time limit")
D.MAX_EVENTS=5000
-- Only idle focus is ignored for STATE deduplication. Saved event snapshots
-- remain complete, and active hover/bridge focus changes remain observable.
local minimap={GetName=function() return "Minimap" end}
local inventory={GetName=function() return "InventoryFrame" end}
local foci={minimap}
GetMouseFoci=function() return foci end
UnitGUID=function() return nil end
local stateStart=MyForeverTargetsLogDB.sequence
local function stateCount()
    local count=0
    for _,e in ipairs(MyForeverTargetsLogDB.events) do
        if e.sequence>stateStart and e.kind=="STATE" then count=count+1 end
    end
    return count
end
step(.25)
local idleStates=stateCount()
for i=1,20 do foci=i%2==0 and {minimap} or {};step(.25) end
eq(stateCount(),idleStates,"idle Minimap and empty focus alternation no longer floods STATE records")
foci={inventory}
emit("UNIT_SPELLCAST_SUCCEEDED","player","idle-full-snapshot",679)
eq(last().kind,"UNIT_SPELLCAST_SUCCEEDED","idle focus suppression never drops global spell events")
eq(last().fields.mouseFoci,"InventoryFrame","global spell event keeps the actual idle focus")
eq(last().fields.nativeMouseoverExists,false,"global spell event keeps the complete native-unit snapshot")
eq(last().fields.zBinding,"MULTIACTIONBAR1BUTTON3","global spell event keeps the original binding snapshot")
D.Snapshot("EXPLICIT_IDLE_SNAPSHOT")
eq(last().fields.mouseFoci,"InventoryFrame","explicit Snapshot also preserves actual idle focus")
eq(stateCount(),idleStates,"full event snapshots do not invent extra polling STATE records")
local hover={unit="nameplate1",side="enemy",expectedGUID="Creature-hover",GetName=function() return "ActiveHoverRow" end}
ns.HoveredTile=hover
foci={hover};step(.25)
local activeStates=stateCount()
eq(last().fields.focusOnHoveredRow,true,"active hover state retains matching mouse focus evidence")
foci={minimap};step(.25)
eq(stateCount(),activeStates+1,"focus leaving an active hover is still recorded")
eq(last().fields.mouseFoci,"Minimap","active hover focus change keeps its real frame name")
foci={};step(.25)
eq(stateCount(),activeStates+2,"empty focus during an active hover is also retained")
ns.HoveredTile=nil;ns.NearbyCast={count=1,row={unit="nameplate1"}}
foci={minimap};step(.25)
local bridgeStates=stateCount()
foci={};step(.25)
eq(stateCount(),bridgeStates+1,"an active bridge keeps focus changes even if the visual hover reference is missing")
ns.NearbyCast=nil
D.Command("start")
local command="/cast [@Creature-0-7121-0-2-525-2B600454CB] 神圣打击"
local id=D.BeginCastAttempt({spellID=679,expectedGUID="Creature-test",row="EnemyRow1",route="guid_hover",generatedCommand=command,
    slot=63,rowUnit="nameplate1",beforeTargetGUID="Player-self",beforeTargetExists=true,configuredKey1="Z",button="LeftButton",down=true,
    selectedActionType="macro",selectedCommandMatches=true,attemptID=999,recipientProven=true,macroBody="/run private"})
eq(type(id),"number","attempt has a public numeric identity")
local attempt=find("HOVER_CAST_ATTEMPT",id).fields
eq(attempt.attemptID,id,"caller cannot replace attempt identity")
eq(attempt.generatedCommand,command,"only the controlled generated command is retained")
eq(attempt.slot,63,"configured action slot is retained")
eq(attempt.beforeTargetGUID,"Player-self","before-target identity is retained independently")
eq(attempt.configuredKey1,"Z","configured key is retained without claiming actual keyboard identity")
eq(attempt.selectedCommandMatches,true,"read-only selected-command observation is retained")
eq(attempt.macroBody,nil,"arbitrary macro body is not copied")
eq(attempt.recipientProven,false,"begin never proves a recipient")
emit("UNIT_SPELLCAST_SENT","player","同名怪物","cast-1",679)
emit("UNIT_SPELLCAST_SUCCEEDED","player","cast-1",679)
emit("UNIT_SPELLCAST_FAILED","player","cast-2",679)
emit("UNIT_SPELLCAST_FAILED_QUIET","player","cast-3",679)
emit("UNIT_SPELLCAST_SUCCEEDED","party1","other",679)
emit("UNIT_SPELLCAST_SUCCEEDED","player","other-spell",20271)
emit("UNIT_SPELLCAST_SUCCEEDED","player","secret-spell",secret)
emit("UNIT_SPELLCAST_SUCCEEDED",secret,"secret-caster",679)
emit("UI_ERROR_MESSAGE",402,"距离太远。")
D.EndCastAttempt(id,{attemptID=999,spellID=20271,expectedGUID="Creature-wrong",recipientProven=true,
    afterTargetGUID="Player-self",generatedCommand="/cast spell\n/run private",macrotext="private",nested={private=true}})
local post=find("HOVER_CAST_POST",id).fields
eq(post.spellID,679,"post cannot replace the attempt spell")
eq(post.expectedGUID,"Creature-test","post cannot replace the attempt recipient identity")
eq(post.recipientProven,false,"post cannot claim proof")
eq(post.generatedCommand,nil,"post rejects multiline command instead of flattening macro body")
eq(post.macrotext,nil,"post drops macro text")
eq(post.nested,"[unsupported]","post never serializes an arbitrary table")
eq(find("HOVER_CAST_WINDOW_SUMMARY",id),nil,"post does not prematurely close the observation window")
step(5)
local summary=find("HOVER_CAST_WINDOW_SUMMARY",id).fields
eq(summary.sentCount,1,"window counts matching player SENT")
eq(summary.succeededCount,1,"window excludes other spell, other caster and restricted values")
eq(summary.failedCount,2,"window includes matching FAILED and FAILED_QUIET")
eq(summary.failedQuietCount,1,"quiet failure remains distinguishable")
eq(summary.uiErrorCount,1,"window counts temporally observed UI errors")
eq(summary.uiErrorsTimeOnly,true,"UI errors never claim spell-specific attribution")
eq(summary.recipientProven,false,"spell counts do not prove an individual recipient")
eq(summary.outcome,"cast_event_observed","summary describes only observed spell events")
local empty=D.BeginCastAttempt({spellID=679,expectedGUID="Creature-none"})
emit("UI_ERROR_MESSAGE",secret,secret)
step(5)
eq(find("HOVER_CAST_WINDOW_SUMMARY",empty).fields.outcome,"no_cast_event_observed","UI error alone does not invent a cast event")
local first=D.BeginCastAttempt({spellID=679})
step(1)
local second=D.BeginCastAttempt({spellID=679})
emit("UNIT_SPELLCAST_SUCCEEDED","player","overlap",679)
step(5)
eq(find("HOVER_CAST_WINDOW_SUMMARY",first).fields.ambiguous,true,"same-spell overlap marks the earlier attempt ambiguous")
eq(find("HOVER_CAST_WINDOW_SUMMARY",second).fields.ambiguous,true,"same-spell overlap also marks the later attempt ambiguous")
local invalid=D.BeginCastAttempt({spellID=secret,expectedGUID=secret,row={},route=secret,generatedCommand=secret})
eq(find("HOVER_CAST_ATTEMPT",invalid).fields.spellID,"[restricted]","restricted spell is redacted before comparison")
step(5)
eq(find("HOVER_CAST_WINDOW_SUMMARY",invalid).fields.outcome,"unreadable_spell_id","unknown spell matching is never inferred")
for _,bad in ipairs({"/cast 神圣打击","/cast [@target] 神圣打击","/cast [@Creature-123,harm] 神圣打击","/cast [@Creature-123] 神圣打击; 审判"}) do
    local rejected=D.BeginCastAttempt({spellID=679,generatedCommand=bad})
    eq(find("HOVER_CAST_ATTEMPT",rejected).fields.generatedCommand,nil,"uncontrolled cast text is rejected")
end
local stopped=D.BeginCastAttempt({spellID=679})
D.Stop("user")
eq(find("HOVER_CAST_WINDOW_SUMMARY",stopped).fields.outcome,"stopped","stop summarizes unfinished windows before disabling")
D.Start()
local prior=D.BeginCastAttempt({spellID=679})
emit("PLAYER_LOGOUT")
local savedSequence=MyForeverTargetsLogDB.sequence
ns,D=loadAddon()
local following=D.BeginCastAttempt({spellID=679})
eq(following>prior,true,"attempt IDs do not repeat across an enabled-log reload")
eq(MyForeverTargetsLogDB.sequence>savedSequence,true,"existing history remains and continues after reload")
function GetRaidTargetIndex(unit) return unit=="target" and 8 or 4 end
D.Snapshot("MARKER_READBACK")
eq(last().fields.hoverRaidMarker,4,"hover raid marker is read without changing it")
eq(last().fields.targetRaidMarker,8,"target raid marker is read without changing it")
eq(D.frame.events.RAID_TARGET_UPDATE,true,"native raid-marker updates have a diagnostic event")
local record=D.Record
D.Record=function() error("diagnostic sink failed") end
eq(pcall(D.BeginCastAttempt,{spellID=679}),true,"logging failure never escapes attempt creation")
eq(pcall(D.EndCastAttempt,following,{afterTargetGUID=secret}),true,"logging failure never escapes post observation")
D.Record=record

-- Native macro mode records public mouseover identity and the exact supported
-- condition, without treating an ordinary spell event as recipient evidence.
local nativeCalls=0
ns.NativeMouseoverStatus=function() nativeCalls=nativeCalls+1;error("must not run in historical mode") end
D.Snapshot("HISTORICAL_NATIVE_OFF")
eq(nativeCalls,0,"historical false policy does not call the native status reader")
eq(last().fields.nativeMacroOnly,nil,"historical snapshots do not gain a new policy field")
eq(last().fields.nativeMouseover,nil,"historical snapshots do not gain nested native details")
D.Stop("native-test")
ns.NativeMacroOnly=true
local nativeIDs={nameplate1="Creature-native",mouseover="Creature-native",target="Creature-current"}
UnitGUID=function(unit) return nativeIDs[unit] end
UnitExists=function(unit) return nativeIDs[unit]~=nil end
ns.HoveredTile={unit="nameplate1",side="enemy",expectedGUID="Creature-native",GetName=function() return "NativeRow" end}
local nativeDetails={expectedGUID="Creature-native",mouseoverGUID="Creature-native",unitGUID="Creature-native",
    identityMatches=true,conditionMatched=true,condition="[@mouseover,nodead,harm]",reason="confirmed",
    macroBody="/cast private",recipientProven=true,extra={private=true}}
ns.NativeMouseoverStatus=function(row)
    nativeCalls=nativeCalls+1
    eq(row,ns.HoveredTile,"native reader receives the actual hovered row")
    local copy={}
    for key,value in pairs(nativeDetails) do copy[key]=value end
    return true,"仅原生鼠标单位读回",copy
end
local actionCalls=0
for _,name in ipairs({"SetBinding","SetOverrideBindingClick","CreateMacro","EditMacro","GetMacroBody",
    "RunMacroText","TargetUnit","ClearTarget"}) do
    _G[name]=function() actionCalls=actionCalls+1;error("diagnostics cannot perform actions") end
end
D.Start()
eq(last().fields.nativeMacroOnly,true,"native START records the active policy")
D.Snapshot("NATIVE_READBACK")
local nativeRecord=last()
local native=nativeRecord.fields.nativeMouseover
eq(type(native),"table","native status has a bounded structured payload")
for _,key in ipairs({"expectedGUID","mouseoverGUID","unitGUID","identityMatches","conditionMatched","condition","reason"}) do
    eq(native[key],nativeDetails[key],"native payload retains public "..key)
end
eq(native.macroBody,nil,"native payload never includes user macro text")
eq(native.recipientProven,nil,"native confirmation does not claim recipient proof")
eq(native.extra,nil,"native payload excludes arbitrary nested fields")
nativeDetails.mouseoverGUID="Creature-other"
eq(native.mouseoverGUID,"Creature-native","saved native details are copied rather than retaining the reader's table")
nativeDetails.mouseoverGUID="Creature-native"
local nativeSequence=nativeRecord.sequence
-- Fresh tables with unchanged values must not create a state every poll.
stateStart=MyForeverTargetsLogDB.sequence
foci={ns.HoveredTile}
step(.25)
local nativeStates=stateCount()
for i=1,6 do step(.25) end
eq(stateCount(),nativeStates,"native table allocation alone never creates repeated STATE logs")
nativeDetails.mouseoverGUID="Creature-other";nativeDetails.identityMatches=false
step(.25)
eq(stateCount(),nativeStates+1,"native mouseover identity changes are recorded")
eq(last().fields.nativeMouseover.mouseoverGUID,"Creature-other","STATE retains the new native identity")
eq(last().fields.nativeMouseover.identityMatches,false,"STATE never converts an identity mismatch into confirmation")
nativeDetails.conditionMatched=false
step(.25)
eq(stateCount(),nativeStates+2,"condition changes are recorded even when the native identity is unchanged")
eq(last().fields.nativeMouseover.conditionMatched,false,"a false macro condition stays false")
step(.25)
eq(stateCount(),nativeStates+2,"unchanged failed conditions are deduplicated")
nativeDetails.condition="[@mouseover,nodead,help]"
D.Snapshot("NATIVE_HELP_CONDITION")
eq(last().fields.nativeMouseover.condition,"[@mouseover,nodead,help]","exact helpful native condition is supported")
nativeDetails.condition="[@mouseover,nodead,harm] 恐惧术; /run private"
D.Snapshot("NATIVE_INVALID_CONDITION")
eq(last().fields.nativeMouseover.condition,"[invalid-condition]","condition logging rejects any macro body or added command")
nativeDetails.condition="[@mouseover,nodead,harm]"
nativeDetails.mouseoverGUID=secret;nativeDetails.identityMatches=secret;nativeDetails.conditionMatched=secret
D.Snapshot("NATIVE_RESTRICTED")
eq(last().fields.nativeMouseover.mouseoverGUID,"[restricted]","restricted mouseover identity is redacted")
eq(last().fields.nativeMouseover.identityMatches,"[restricted]","restricted identity comparison is never a true match")
eq(last().fields.nativeMouseover.conditionMatched,"[restricted]","restricted condition result is never a true match")
nativeDetails.condition=secret
D.Snapshot("NATIVE_RESTRICTED_CONDITION")
eq(last().fields.nativeMouseover.condition,"[restricted]","restricted condition is not compared to public text")
ns.NativeMouseoverStatus=function() return nil,nil,secret end
D.Snapshot("NATIVE_RESTRICTED_DETAILS")
eq(last().fields.nativeMouseover.reason,"[restricted]","restricted status objects are not traversed")
ns.NativeMouseoverStatus=function() error("private helper error") end
emit("UNIT_SPELLCAST_SUCCEEDED","player","native-with-reader-error",679)
eq(last().kind,"UNIT_SPELLCAST_SUCCEEDED","native reader errors never swallow the ordinary spell event")
eq(last().fields.nativeMouseover.reason,"status_error","native reader failure is labelled without saving its error text")
eq(last().fields.spellID,679,"native reader failure preserves the original spell event fields")
eq(last().fields.recipientProven,nil,"ordinary native spell success never proves a macro recipient")
ns.NativeMouseoverStatus=nil
D.Snapshot("NATIVE_UNAVAILABLE")
eq(last().fields.nativeMouseover.reason,"status_unavailable","missing native reader remains an explicit unknown")
ns.NativeMouseoverStatus=function()
    return false,"未知",setmetatable({}, {__index=function() error("private field error") end})
end
D.Snapshot("NATIVE_FIELD_ERROR")
eq(last().fields.nativeMouseover.identityMatches,"[api-error]","a failing details getter does not abort a snapshot")
-- Idle Minimap changes remain suppressed with the native payload enabled.
ns.HoveredTile=nil
ns.NativeMouseoverStatus=function()
    return false,"未悬停",{reason="no_hover",condition="[@mouseover,nodead,harm]",identityMatches=false,conditionMatched=false}
end
foci={minimap};step(.25)
local nativeIdleStates=stateCount()
for i=1,12 do foci=i%2==0 and {minimap} or {};step(.25) end
eq(stateCount(),nativeIdleStates,"native status does not restore idle Minimap STATE flooding")
foci={inventory}
emit("UNIT_SPELLCAST_SENT","player","普通技能目标","native-sent",679)
eq(last().fields.mouseFoci,"InventoryFrame","native mode keeps full mouse focus on real skill events")
eq(last().fields.sentTarget,"普通技能目标","native mode preserves ordinary public spell event data")
eq(last().fields.nativeMouseover.reason,"no_hover","real skill events also retain the current native status")
eq(last().fields.nativeMouseover.recipientProven,nil,"a no-hover skill event cannot prove native macro targeting")
eq(actionCalls,0,"native diagnostics do not read macros, bind keys, cast, or change targets")
-- The one whitelisted structured payload survives SavedVariables reload.
ns,D=loadAddon()
local restored
for _,event in ipairs(MyForeverTargetsLogDB.events) do
    if event.sequence==nativeSequence then restored=event.fields.nativeMouseover;break end
end
eq(type(restored),"table","native detail payload survives the saved-history normalizer")
eq(restored.mouseoverGUID,"Creature-native","reload retains the saved original public identity")
eq(restored.condition,"[@mouseover,nodead,harm]","reload retains only the original exact condition")
eq(restored.macroBody,nil,"reload cannot introduce excluded user macro contents")

-- Global mouse events are passive observations, including clicks intercepted
-- by another addon above our visible panel. No input surface is installed.
eq(D.frame.events.GLOBAL_MOUSE_DOWN,true,"existing diagnostic frame registers native global down events")
eq(D.frame.events.GLOBAL_MOUSE_UP,true,"existing diagnostic frame registers native global up events")
local mouseReads={cursor=0,foci=0,bindings=0,unit=0,professions=0}
local cursorMode,cursorX,cursorY="valid",250,240
GetCursorPosition=function()
    mouseReads.cursor=mouseReads.cursor+1
    if cursorMode=="throw" then error("private cursor error") end
    if cursorMode=="secret" then return secret,secret end
    return cursorX,cursorY
end
local function region(name,left,bottom,width,height,scale)
    local value={name=name,shown=true,left=left,bottom=bottom,width=width,height=height,scale=scale or 1}
    function value:GetName() return self.name end
    function value:IsVisible() return self.shown end
    function value:IsForbidden() return false end
    function value:GetRect() return self.left,self.bottom,self.width,self.height end
    function value:GetEffectiveScale() return self.scale end
    function value:GetParent() return self.parent end
    function value:EnableMouse() actionCalls=actionCalls+1;error("diagnostics cannot enable mouse input") end
    function value:SetAttribute() actionCalls=actionCalls+1;error("diagnostics cannot change protected attributes") end
    return value
end
local panel=region("MyForeverTargetsEnemy",100,100,100,70,2)
local mouseRow=region("MyForeverTargetsEnemy1",110,110,30,20,2)
mouseRow.unit,mouseRow.side,mouseRow.expectedGUID="nameplate1","enemy","Creature-mouse"
mouseRow.parent=panel
local overlay=region("OtherAddonOverlay",0,0,1000,1000)
local child=region("PanelHeader",0,0,1,1);child.parent=panel
local mouseFoci={overlay}
local mouseHits={}
GetMouseFoci=function() mouseReads.foci=mouseReads.foci+1;return mouseFoci end
MouseIsOver=function(value) return mouseHits[value]==true end
UnitGUID=function(unit)
    mouseReads.unit=mouseReads.unit+1
    if unit=="nameplate1" or unit=="mouseover" then return "Creature-mouse" end
    if unit=="target" then return "Creature-original" end
end
GetBindingAction=function(key,active)
    mouseReads.bindings=mouseReads.bindings+1
    if key=="BUTTON2" then return active and "CLICK OtherAddon:RightButton" or "TURNORACTION" end
    if key=="BUTTON1" then return active and "CAMERAORSELECTORMOVE" or "INTERACTTARGET" end
    return "MULTIACTIONBAR1BUTTON3"
end
MyForeverProfessionsDB=setmetatable({}, {__index=function(_,key)
    mouseReads.professions=mouseReads.professions+1
    if key=="gatherMethod" then return "original" end
    error("must not inspect another professions setting")
end})
ns.UI={enemy={frame=panel,tiles={mouseRow}}}
ns.HoveredTile=nil
ns.NativeMacroOnly=true
ns.NativeMouseoverStatus=function(row)
    return false,"读回",{expectedGUID=row and row.expectedGUID,mouseoverGUID="Creature-mouse",unitGUID="Creature-mouse",
        identityMatches=false,conditionMatched=false,condition="[@mouseover,nodead,harm]",reason="not_hovered"}
end
D.Stop("off-mouse-test")
for key in pairs(mouseReads) do mouseReads[key]=0 end
local noMouseSequence=MyForeverTargetsLogDB.sequence
emit("GLOBAL_MOUSE_DOWN","RightButton")
emit("GLOBAL_MOUSE_UP","RightButton")
eq(MyForeverTargetsLogDB.sequence,noMouseSequence,"disabled mouse observer emits nothing")
for key,count in pairs(mouseReads) do eq(count,0,"disabled mouse observation performs zero "..key.." reads") end
D.Start()
local beforeRaw=MyForeverTargetsLogDB.sequence
emit("GLOBAL_MOUSE_DOWN","RightButton")
local raw=last()
eq(raw.kind,"GLOBAL_MOUSE_DOWN","a down event is recorded immediately without requiring Up")
eq(raw.fields.button,"RightButton","raw native button name is retained")
eq(raw.fields.phase,"down","raw down phase is explicit")
eq(raw.fields.down,true,"native Down boolean retained")
eq(raw.fields.up,false,"Down never invents an Up")
eq(raw.fields.mouseScope,"enemy_panel","screen geometry locates the visible addon panel")
eq(raw.fields.mouseScopeMethod,"screen_rect","occluding foci cannot hide an in-panel geometric click")
eq(raw.fields.mouseFocus1,"OtherAddonOverlay","the actual capturing overlay remains visible in the log")
eq(raw.fields.mouseFoci,"OtherAddonOverlay","raw input retains the full bounded focus snapshot")
eq(raw.fields.mouseBindingKey,"BUTTON2","right button maps to the actual binding token")
eq(raw.fields.mouseBindingActive,"CLICK OtherAddon:RightButton","effective override binding is observed")
eq(raw.fields.mouseBindingBase,"TURNORACTION","base binding is observed separately")
eq(raw.fields.expectedGUID,"Creature-mouse","underlying tile expected GUID is observed without synthetic hover")
eq(raw.fields.hoverGUID,"Creature-mouse","underlying tile live GUID is observed")
eq(raw.fields.targetGUID,"Creature-original","the preexisting current target is only read")
eq(raw.fields.nativeMacroOnly,true,"raw input records native macro policy")
eq(raw.fields.nativeMouseover.reason,"not_hovered","geometry never pretends that the tile received native hover")
eq(raw.fields.nativeMouseover.condition,"[@mouseover,nodead,harm]","raw input retains the public macro-condition readback")
eq(raw.fields.professionsGatherMethod,"original","raw input records the actual public scanner mode")
eq(raw.fields.observationOnly,true,"raw log explicitly identifies an observation")
eq(raw.fields.recipientProven,nil,"raw input cannot prove a spell recipient")
eq(MyForeverTargetsLogDB.sequence,beforeRaw+1,"Down alone creates exactly one event")
emit("GLOBAL_MOUSE_UP","RightButton")
eq(last().kind,"GLOBAL_MOUSE_UP","a later native Up is a separate actual observation")
eq(last().fields.phase,"up","Up phase is explicit")
eq(last().fields.down,false,"Up does not invent another Down")
eq(last().fields.up,true,"Up boolean is retained")
eq(MyForeverTargetsLogDB.sequence,beforeRaw+2,"a real Down and Up produce two records")
emit("GLOBAL_MOUSE_DOWN","LeftButton")
eq(last().fields.mouseBindingKey,"BUTTON1","left button is observed independently")
eq(last().fields.mouseBindingActive,"CAMERAORSELECTORMOVE","left effective binding is retained")
eq(last().fields.mouseBindingBase,"INTERACTTARGET","left base binding is retained")
local ignored=MyForeverTargetsLogDB.sequence
local oldFocusReads,oldCursorReads=mouseReads.foci,mouseReads.cursor
emit("GLOBAL_MOUSE_DOWN","MiddleButton");emit("GLOBAL_MOUSE_UP",secret)
eq(MyForeverTargetsLogDB.sequence,ignored,"unrequested or restricted mouse buttons are ignored")
eq(mouseReads.foci,oldFocusReads,"ignored buttons do not inspect focus")
eq(mouseReads.cursor,oldCursorReads,"ignored buttons do not inspect coordinates")
cursorX,cursorY=1600,1600
local oldUnitReads,oldBindingReads,oldProfessionReads=mouseReads.unit,mouseReads.bindings,mouseReads.professions
emit("GLOBAL_MOUSE_DOWN","RightButton")
eq(MyForeverTargetsLogDB.sequence,ignored,"outside camera clicks are not recorded")
eq(mouseReads.unit,oldUnitReads,"outside clicks do not inspect unit identities")
eq(mouseReads.bindings,oldBindingReads,"outside clicks do not inspect bindings")
eq(mouseReads.professions,oldProfessionReads,"outside clicks do not inspect professions settings")
-- If Up occurs outside after a panel Down, it is not fabricated into the log.
cursorX,cursorY=250,240;emit("GLOBAL_MOUSE_DOWN","RightButton")
local singleDown=MyForeverTargetsLogDB.sequence
cursorX,cursorY=1600,1600;emit("GLOBAL_MOUSE_UP","RightButton")
eq(MyForeverTargetsLogDB.sequence,singleDown,"leaving the panel does not synthesize an unseen Up")
-- Safe fallbacks identify their limits instead of adding an input catcher.
cursorMode="secret";mouseFoci={child}
emit("GLOBAL_MOUSE_DOWN","RightButton")
eq(last().fields.mouseScopeMethod,"focus_ancestry","known focus ancestry can locate a panel without public coordinates")
eq(last().fields.mouseScopeReason,"cursor_unreadable","fallback retains the unavailable-coordinate reason")
cursorMode="throw";mouseFoci={overlay};ns.HoveredTile=mouseRow
emit("GLOBAL_MOUSE_UP","RightButton")
eq(last().fields.mouseScopeMethod,"hovered_tile_fallback","an existing hovered tile is explicitly labelled as fallback evidence")
eq(last().fields.mouseScopeReason,"cursor_api_error","coordinate API failure is retained without its private error text")
cursorMode="valid";ns.HoveredTile=nil;mouseHits[panel]=true
panel.GetRect=function() error("private rectangle failure") end
emit("GLOBAL_MOUSE_DOWN","RightButton")
eq(last().fields.mouseScopeMethod,"mouse_is_over","public MouseIsOver remains a bounded fallback")
eq(last().fields.mouseScopeReason,"rectangle_unreadable","failed geometry is labelled rather than assumed valid")
mouseHits[panel]=nil
panel.GetRect=function(self) return self.left,self.bottom,self.width,self.height end
-- Marker-menu input retains its separate fixed source identity.
local menu=region("MyForeverTargetsMarkMenu",500,100,120,60)
menu.GetAttribute=function(_,key)
    if key=="unit" then return "nameplate1" end
    if key=="source-guid" then return "Creature-menu-source" end
end
ns.MarkerMenu=menu
cursorX,cursorY=530,120
emit("GLOBAL_MOUSE_DOWN","LeftButton")
eq(last().fields.mouseScope,"marker_menu","the marker menu is an allowed observation scope")
eq(last().fields.menuExpectedGUID,"Creature-menu-source","marker source identity is read without changing the marker")
eq(last().fields.menuLiveGUID,"Creature-mouse","marker live identity is read separately")
-- Compact raw fields stay below the serializer bound even with every focus.
cursorX,cursorY=250,240;mouseFoci={overlay,inventory,minimap,child,menu}
ns.CombatCast={Status=function() return {prepared=true,count=9,name="测试",guid="Creature-mouse",unit="nameplate1",reason="old"} end}
emit("GLOBAL_MOUSE_DOWN","RightButton")
local complete=last().fields
local fieldCount=0;for _ in pairs(complete) do fieldCount=fieldCount+1 end
eq(fieldCount<=64,true,"raw payload has room below the fixed field-copy capacity")
for _,key in ipairs({"button","phase","mouseScopeMethod","mouseFocus1","mouseFocus2","mouseFocus3","mouseFocus4",
    "mouseBindingActive","mouseBindingBase","nativeMouseover","professionsGatherMethod","targetGUID","expectedGUID","hoverGUID"}) do
    eq(complete[key]~=nil,true,"raw required field is retained: "..key)
end
eq(complete.mouseFocus5,nil,"raw focus list is bounded to four")
eq(complete.rangeProbeSpellID,nil,"unrelated range-probe fields cannot crowd raw input evidence")
local normalGetBindingAction,normalUnitGUID=GetBindingAction,UnitGUID
GetBindingAction=function(key,active) if key=="BUTTON2" then return secret end;return normalGetBindingAction(key,active) end
UnitGUID=function() error("private unit failure") end
emit("GLOBAL_MOUSE_DOWN","RightButton")
eq(last().fields.mouseBindingActive,"[restricted]","restricted effective button binding is redacted")
eq(last().fields.mouseBindingBase,"[restricted]","restricted base button binding is redacted")
eq(last().fields.targetGUID,"[api-error]","unit API errors do not escape a raw observation")
GetBindingAction,UnitGUID=normalGetBindingAction,normalUnitGUID
GetMouseFoci=function() error("private focus failure") end
emit("GLOBAL_MOUSE_DOWN","RightButton")
eq(last().kind,"GLOBAL_MOUSE_DOWN","geometry can still record an in-panel click when focus API fails")
eq(last().fields.mouseFoci,"[unavailable]","unavailable focus evidence remains explicit")
GetMouseFoci=function() return mouseFoci end
emit("UNIT_SPELLCAST_SUCCEEDED","player","unaffected-spell",679)
eq(last().kind,"UNIT_SPELLCAST_SUCCEEDED","new global observers do not intercept existing spell events")
eq(last().fields.spellID,679,"existing spell-event payload remains intact")
-- Only the allowed public MFP mode is stored, for direct UI records as well.
for _,mode in ipairs({"original","cursor"}) do
    MyForeverProfessionsDB={gatherMethod=mode,private="never-save"}
    D.Record("UI_TILE_INPUT",{button="RightButton"})
    eq(last().fields.professionsGatherMethod,mode,"direct UI records retain the public "..mode.." scanner mode")
    eq(last().fields.private,nil,"other professions settings never enter the log")
    D.Snapshot("PROFESSIONS_MODE")
    eq(last().fields.professionsGatherMethod,mode,"Snapshot retains the same "..mode.." scanner mode")
end
MyForeverProfessionsDB=nil;D.Record("MFP_MISSING",{})
eq(last().fields.professionsGatherMethod,"[unknown]","missing MFP settings are an explicit unknown")
MyForeverProfessionsDB=secret;D.Record("MFP_SECRET_DB",{})
eq(last().fields.professionsGatherMethod,"[restricted]","a restricted settings object is never traversed")
MyForeverProfessionsDB={gatherMethod=secret};D.Record("MFP_SECRET_MODE",{})
eq(last().fields.professionsGatherMethod,"[restricted]","a restricted scanner mode is never compared or saved")
MyForeverProfessionsDB={gatherMethod="other"};D.Record("MFP_UNKNOWN_MODE",{})
eq(last().fields.professionsGatherMethod,"[unknown]","unrecognized mode text is not serialized")
local previousChild,previousRow=ns.HoveredEnemyTarget,ns.HoveredTile
local child={unit="nameplate1target",side="friendly",expectedGUID="Player-child",
    GetName=function() return "EnemyTargetChild" end,GetAttribute=function() return "nameplate1target" end}
ns.HoveredEnemyTarget,ns.HoveredTile=child,nil
D.Snapshot("CHILD_CAST_CONTEXT")
eq(last().fields.hoveredRow,"EnemyTargetChild","child hover identifies the actual casting region")
eq(last().fields.hoverUnit,"nameplate1target","child hover snapshots its relationship token")
eq(last().fields.expectedGUID,"Player-child","child hover retains its own expected recipient")
ns.HoveredEnemyTarget,ns.HoveredTile=previousChild,previousRow
-- Layout observations use effective scales rather than assuming screen/UI or
-- addon coordinates are equal. These are getter-only geometry simulations.
do
    local geometryReads=0
    local function region(name,left,bottom,width,height,effectiveScale)
        local value={name=name,left=left,bottom=bottom,width=width,height=height,
            effectiveScale=effectiveScale,shown=true,visible=true}
        function value:GetName() return self.name end
        function value:IsShown() return self.shown end
        function value:IsVisible() return self.visible end
        function value:IsForbidden() return self.forbidden==true end
        function value:GetRect() geometryReads=geometryReads+1;return self.left,self.bottom,self.width,self.height end
        function value:GetWidth() return self.width end
        function value:GetHeight() return self.height end
        function value:GetEffectiveScale() return self.effectiveScale end
        function value:GetScale() return self.scale or self.effectiveScale end
        function value:GetPoint() return "LEFT",UIParent,"LEFT",24,80 end
        for _,method in ipairs({"SetPoint","ClearAllPoints","SetScale","SetSize","Show","Hide","EnableMouse"}) do
            value[method]=function() actionCalls=actionCalls+1;error("layout observation attempted a mutation") end
        end
        return value
    end
    local function layoutEvent(kind,key,value)
        for i=#MyForeverTargetsLogDB.events,1,-1 do
            local e=MyForeverTargetsLogDB.events[i]
            if e.kind==kind and (not key or e.fields[key]==value) then return e.fields end
        end
    end
    local function layoutCount()
        local count=0
        for _,e in ipairs(MyForeverTargetsLogDB.events) do
            if e.kind:match("^LAYOUT_") then count=count+1 end
        end
        return count
    end
    MyForeverTargetsLogDB=nil
    ns,D=loadAddon()
    UIParent=region("UIParent",0,0,1600,900,.8)
    GetPhysicalScreenSize=function() return 1280,720 end
    local friend=region("FriendlyPanel",50,20,100,60,1)
    friend.scale=1.25
    local enemy=region("EnemyPanel",500,400,100,60,1.2)
    ns.UI={friendly={frame=friend},enemy={frame=enemy}}
    ns.DB={friendlyPosition={point="LEFT",relativePoint="LEFT",x=24,y=80,manual=false},
        enemyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=500,y=-200,manual=true}}
    MainMenuBar=region("MainMenuBar",40,0,300,50,.8)
    local beforeReads=geometryReads
    eq(D.LayoutSnapshot("disabled"),false,"disabled layout logging does not collect geometry")
    eq(geometryReads,beforeReads,"disabled layout logging does not inspect frame getters")
    D.Start()
    eq(last().kind,"START","layout sampling preserves the public Start marker ordering")
    eq(D.LayoutSnapshot("initial"),true,"public layout snapshot succeeds")
    local screen=layoutEvent("LAYOUT_SCREEN")
    local friendly=layoutEvent("LAYOUT_PANEL","side","friendly")
    local bar=layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar")
    eq(screen.physicalWidth,1280,"layout records the actual physical screen width")
    eq(screen.physicalHeight,720,"layout records the actual physical screen height")
    eq(screen.uiWidth,1600,"layout distinguishes UIParent width from physical pixels")
    eq(screen.uiEffectiveScale,.8,"layout retains UIParent effective scale")
    eq(friendly.uiLeft,62.5,"panel left is converted through effectiveScale/UIParentScale")
    eq(friendly.uiBottom,25,"panel bottom uses the same UIParent coordinate space")
    eq(friendly.uiWidth,125,"panel width includes addon scale and parent scale")
    eq(friendly.uiHeight,75,"panel height includes addon scale and parent scale")
    eq(friendly.frameScale,1.25,"local panel scale is observed separately")
    eq(friendly.savedManual,false,"saved automatic ownership is preserved explicitly")
    eq(friendly.savedPoint,"LEFT","saved anchor is observed without rewriting it")
    eq(friendly.savedX,24,"saved x remains distinct from actual geometry")
    eq(friendly.point,"LEFT","actual point is observed independently")
    eq(friendly.x,24,"actual offset is retained")
    eq(friendly.actionbarOverlap,true,"converted overlapping panel and bar are correctly identified")
    eq(bar.friendlyOverlap,true,"bar evidence also identifies the overlapping friendly panel")
    eq(bar.enemyOverlap,false,"public disjoint geometry is explicitly false")
    eq(layoutEvent("LAYOUT_PANEL","side","enemy").actionbarOverlap,false,"a public disjoint panel remains distinguishable")
    eq(screen.coordinates,"UIParent","coordinate space is named explicitly")
    eq(screen.actionbarScope,"known_native_frames","overlap scope excludes unobserved third-party frames")
    eq(screen.overlapMeaning,"rectangle_intersection","geometry evidence does not claim rendered occlusion")
    eq(screen.visibleActionbars,1,"only visible observed bars count as visible")
    eq(friendly.observationOnly,true,"layout evidence cannot imply a frame movement")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MultiBar5"),nil,"missing bars do not invent geometry records")
    local initialCount=layoutCount()
    D.LayoutSnapshot("different_reason")
    eq(layoutCount(),initialCount,"unchanged layout deduplicates even when the caller reason changes")
    friend.left=50.00001;D.LayoutSnapshot("subpixel_noise")
    eq(layoutCount(),initialCount,"imperceptible subpixel noise does not flood the history")
    friend.left=500
    D.LayoutSnapshot("moved")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,false,"moving clear changes the overlap result")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").friendlyOverlap,false,"bar dedup includes the changed overlap state")
    UIParent.effectiveScale=1
    D.LayoutSnapshot("parent_scale")
    eq(layoutEvent("LAYOUT_SCREEN").uiEffectiveScale,1,"parent scale change is independently captured")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").uiLeft,500,"new effective-scale ratio changes normalized position")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").uiWidth,240,"bar geometry is normalized after parent scale change")
    MainMenuBar.width=secret
    D.LayoutSnapshot("restricted_bar")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").width,"[restricted]","restricted geometry is redacted before arithmetic")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").rectStatus,"rectangle_unreadable","restricted bar rectangle is explicitly unreadable")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","unreadable visible bar never implies no overlap")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").friendlyOverlap,"unknown","per-bar overlap also remains unknown")
    MainMenuBar.width=300;friend.effectiveScale=secret
    D.LayoutSnapshot("restricted_panel_scale")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").effectiveScale,"[restricted]","restricted panel scale is redacted")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").rectStatus,"scale_unreadable","restricted scale disables normalization")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","restricted panel scale cannot prove disjointness")
    friend.effectiveScale=1;MainMenuBar.visible=false;MainMenuBar.shown=false
    D.LayoutSnapshot("bar_hidden")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").visible,false,"bar hiding is recorded rather than losing previous evidence")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","no visible bar is not a fabricated all-clear")
    MainMenuBar=nil
    D.LayoutSnapshot("bar_removed")
    eq(layoutEvent("LAYOUT_ACTIONBAR","name","MainMenuBar").exists,false,"previously known bar removal is explicit")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","absent actionbar API leaves overlap unknown")
    ns.UI.friendly.frame=nil
    D.LayoutSnapshot("panel_missing")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").exists,false,"not-yet-built panels have no invented rectangle")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","missing panel overlap is unknown")
    ns.UI.friendly.frame=friend
    UIParent.effectiveScale=secret;GetPhysicalScreenSize=function() return secret,secret end
    D.LayoutSnapshot("restricted_parent")
    eq(layoutEvent("LAYOUT_SCREEN").uiEffectiveScale,"[restricted]","restricted UIParent scale is redacted")
    eq(layoutEvent("LAYOUT_SCREEN").physicalWidth,"[nil]","restricted physical size is unavailable rather than serialized")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").rectStatus,"scale_unreadable","unknown parent scale prevents panel normalization")
    UIParent.effectiveScale=1
    friend.GetRect=function() error("private getter error must not enter the log") end
    D.LayoutSnapshot("throwing_rect")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").rectStatus,"rectangle_api_error","getter error is labelled without its private text")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").actionbarOverlap,"unknown","failed geometry cannot claim no overlap")
    friend.forbidden=true
    D.LayoutSnapshot("forbidden_frame")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").rectStatus,"forbidden","forbidden frame is not inspected for geometry")
    -- The enemy getter may still be read; the forbidden friendly getter throws
    -- above, and a non-error status proves it was skipped.
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").width,nil,"forbidden geometry has no stale width")
    friend.forbidden=false
    friend.GetRect=function(self) return self.left,self.bottom,self.width,self.height end
    D.Start()
    local active=MyForeverTargetsLogDB.activeSeconds
    local beforeLayout=layoutCount()
    step(.5);step(.49)
    eq(layoutCount(),beforeLayout,"periodic layout reads wait for a full second")
    step(.01)
    eq(layoutCount()>beforeLayout,true,"periodic layout reads begin after one second")
    local stable=layoutCount()
    step(1);step(1)
    eq(layoutCount(),stable,"stable periodic layout does not evict focus evidence with duplicates")
    friend.left=42
    emit("PLAYER_LOGOUT")
    eq(last().kind,"PLAYER_LOGOUT","last layout read preserves the client's logout marker ordering")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").uiLeft,42,"logout captures changes since the last timed poll")
    eq(MyForeverTargetsLogDB.activeSeconds,active+3,"layout reads do not reset cumulative logging duration")
    for _,e in ipairs(MyForeverTargetsLogDB.events) do
        if e.kind:match("^LAYOUT_") then
            local count,scalarOnly=0,true
            for _,value in pairs(e.fields) do
                count=count+1
                if type(value)=="table" then scalarOnly=false end
            end
            eq(scalarOnly,true,"layout payload contains only scalar observations")
            eq(count<=64,true,"layout payload remains below the serializer field limit")
        end
    end
    friend.left=73
    D.Stop("layout_done")
    eq(last().kind,"STOP","final layout capture preserves the stop marker ordering")
    eq(layoutEvent("LAYOUT_PANEL","side","friendly").uiLeft,73,"stop captures movement before the next one-second poll")
    local stopped=MyForeverTargetsLogDB.sequence
    friend.left=99;step(2);D.LayoutSnapshot("disabled_again")
    eq(MyForeverTargetsLogDB.sequence,stopped,"stopped layout logging remains off")
end
eq(actionCalls,0,"global input observation never enables mouse, changes bindings, casts, or changes protected attributes")
print("Targets diagnostics simulated checks:",checks,"passed")
