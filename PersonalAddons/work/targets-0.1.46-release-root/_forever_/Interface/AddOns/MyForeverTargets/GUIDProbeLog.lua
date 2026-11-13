local _, NS = ...
local Log={active=false,captures={},results={},attemptID=0,routes={}}
NS.GUIDProbeLog=Log
local frame,ownLog,lastAttempt
local WINDOW=5

local function safe(value)
    if NS.Diagnostics and NS.Diagnostics.Safe then return NS.Diagnostics.Safe(value) end
    if not NS.Public(value) then return "[restricted]" end
    if type(value)=="string" then return NS.Text(value):sub(1,256) end
    if type(value)=="boolean" or NS.Number(value) then return value end
    return "[unavailable]"
end

local function read(fn,...)
    if type(fn)~="function" then return "[unavailable]" end
    local ok,value=pcall(fn,...)
    if ok then return safe(value) end
    return "[api-error]"
end

local function guid(value)
    return NS.Public(value) and type(value)=="string" and value~=""
        and value:sub(1,1)~="[" and value or nil
end

local function now()
    local value=NS.Read(GetTime)
    return NS.Number(value) and value or nil
end

function Log.Record(kind,fields)
    if not Log.active or not NS.Diagnostics then return false end
    local ok,recorded=pcall(NS.Diagnostics.Record,kind,fields or {})
    local probe=NS.GUIDProbe
    if probe and type(probe.UpdateLabels)=="function" then pcall(probe.UpdateLabels) end
    return ok and recorded==true
end

local function result(slot,attempt,reason)
    local value={attemptID=attempt or 0,receiver="unproven",effect="none",reason=reason or "no_attempt"}
    if slot=="A" or slot=="B" then Log.results[slot]=value end
    return value
end

function Log.Status(slot)
    local saved=Log.results[slot]
    if not saved then return {attemptID=0,receiver="unproven",effect="none",reason="no_attempt"} end
    local copy={}
    for key,value in pairs(saved) do copy[key]=value end
    return copy
end

function Log.Capture(slot,record)
    if not Log.active or (slot~="A" and slot~="B") or type(record)~="table" then return false end
    local identity=guid(record.guid)
    if not identity then return false end
    Log.captures[slot]={guid=identity,name=safe(record.name)}
    Log.results={};lastAttempt=nil
    local fields={slot=slot,guid=identity,name=safe(record.name)}
    for _,key in ipairs({"unit","observedToken","resolvedToken","rawExists","roundTripGUID","range"}) do
        fields[key]=safe(record[key])
    end
    Log.Record("GUID_PROBE_CAPTURE",fields)
    return true
end

function Log.Attempt(fields)
    if not Log.active or type(fields)~="table" then return nil end
    Log.attemptID=Log.attemptID+1
    local slot=NS.Public(fields.slot) and fields.slot or nil
    local expected=guid(fields.expectedGUID)
    local captured=slot and Log.captures[slot]
    local executable=NS.Public(fields.execute) and fields.execute==true
    local valid=expected~=nil and captured~=nil and captured.guid==expected
    local mode=safe(fields.mode)
    if mode=="converted" and guid(fields.unitArgGUID)~=expected then valid=false end
    local requiresClear=mode=="integrated_macro"
    if requiresClear then
        valid=valid and NS.Public(fields.liveExists) and fields.liveExists==true
            and NS.Public(fields.liveDead) and fields.liveDead==false
            and guid(fields.liveGUID)==expected
            and NS.Public(fields.clearsCurrentTarget) and fields.clearsCurrentTarget==true
    end
    local configurationValid=valid
    local t=now()
    local overlap=executable and lastAttempt and lastAttempt.execute and t and lastAttempt.time
        and t>=lastAttempt.time and t-lastAttempt.time<=WINDOW
    if overlap then
        lastAttempt.ambiguous=true
        local previous=lastAttempt.result
        if previous then previous.receiver="unproven";previous.reason="ambiguous_attempt_window" end
        Log.Record("GUID_PROBE_AMBIGUOUS",{previousAttemptID=lastAttempt.id,attemptID=Log.attemptID,
            reason="attempts_within_5_seconds"})
    end
    local reason=not executable and "blocked_or_unreadable" or not configurationValid and "stale_or_unreadable_mapping"
        or overlap and "ambiguous_attempt_window" or requiresClear and "awaiting_clear_confirmation" or "awaiting_effect"
    local state=result(slot,Log.attemptID,reason)
    state.expectedGUID=expected
    if requiresClear then
        state.targetClearConfirmed=false
        if executable then state.targetClearReason="awaiting_clear_confirmation" end
    end
    -- A blocked extra key press cannot execute a new spell. Keep the preceding
    -- executable attempt's delayed events tied to its own ID, not the no-op.
    if executable then
        lastAttempt={id=Log.attemptID,slot=slot,expectedGUID=expected,execute=true,time=t,
            mode=mode,valid=configurationValid and not requiresClear,ambiguous=overlap==true,result=state,
            configurationValid=configurationValid,requiresClearConfirmation=requiresClear,
            beforeTargetGUID=guid(fields.targetGUID) or guid(fields.currenttargetGUID)}
    end
    local record={attemptID=Log.attemptID,expectedGUID=safe(expected),execute=executable,
        validConfiguration=configurationValid,requiresClearConfirmation=requiresClear,ambiguousWindow=overlap==true}
    for key,value in pairs(fields) do
        if key~="attemptID" and key~="expectedGUID" and key~="execute" then record[key]=value end
    end
    Log.Record("GUID_PROBE_PRECLICK",record)
    return Log.attemptID
end

function Log.PostAttempt(fields)
    if not Log.active then return end
    local record={attemptID=lastAttempt and lastAttempt.id or 0}
    if type(fields)=="table" then for key,value in pairs(fields) do record[key]=value end end
    Log.Record("GUID_PROBE_POSTCLICK",record)
    -- Only the matching executable action's own first PostClick may establish
    -- that /cleartarget took effect. A no-op or another mode cannot confirm it.
    if type(fields)~="table" or not lastAttempt or not lastAttempt.requiresClearConfirmation
        or lastAttempt.closed or lastAttempt.clearPostObserved
        or not NS.Number(fields.attemptID) or fields.attemptID~=lastAttempt.id
        or not NS.Public(fields.mode) or fields.mode~=lastAttempt.mode
        or not NS.Public(fields.slot) or fields.slot~=lastAttempt.slot
        or guid(fields.expectedGUID)~=lastAttempt.expectedGUID
        or not NS.Public(fields.execute) or fields.execute~=true then return end
    local postTime=now()
    if not postTime or not lastAttempt.time or postTime<lastAttempt.time or postTime-lastAttempt.time>WINDOW then return end
    local confirmed=NS.Public(fields.targetExistsAfter) and fields.targetExistsAfter==false
    lastAttempt.clearPostObserved=true
    lastAttempt.targetClearConfirmed=confirmed
    lastAttempt.valid=lastAttempt.configurationValid and confirmed
    local state=lastAttempt.result
    if state then
        state.targetClearConfirmed=confirmed
        state.targetClearReason=not confirmed and "target_clear_unconfirmed" or nil
        -- Preserve an early error/cast observation or another stronger limit.
        -- Confirming a clear never promotes a previously observed recipient.
        if state.reason=="awaiting_clear_confirmation" then
            state.reason=confirmed and "awaiting_effect" or "target_clear_unconfirmed"
        end
    end
    Log.Record("GUID_PROBE_TARGET_CLEAR",{attemptID=lastAttempt.id,mode=lastAttempt.mode,slot=lastAttempt.slot,
        expectedGUID=lastAttempt.expectedGUID,beforeTargetGUID=safe(lastAttempt.beforeTargetGUID),
        afterTargetGUID=safe(guid(fields.targetGUID)),targetExistsAfter=safe(fields.targetExistsAfter),
        confirmed=confirmed,configurationValid=lastAttempt.configurationValid,recipientProven=false})
end

local function recent()
    local t=now()
    return lastAttempt and lastAttempt.execute and t and lastAttempt.time
        and t>=lastAttempt.time and t-lastAttempt.time<=WINDOW
end

local function restricted()
    return read(C_CombatLog and C_CombatLog.IsCombatLogRestricted)
end

local function probeFocusConfirmed(slot)
    local probe=NS.GUIDProbe
    local block=probe and probe.blocks and probe.blocks[slot]
    if not block then return false end
    local foci=NS.Read(GetMouseFoci)
    if type(foci)~="table" then return false end
    for _,focus in ipairs(foci) do
        if NS.Public(focus) and focus==block then return true end
    end
    return false
end

local function combatEvent(event)
    if not Log.active or not recent() then return end
    local route=Log.routes[event]
    if not route or not route.registered or route.readFailed then return end
    local lock=restricted()
    if lock==true then
        if not route.warned then
            route.warned=true
            Log.Record("GUID_PROBE_COMBAT_LOG_UNREADABLE",{event=event,reason="restricted",attemptID=lastAttempt.id})
        end
        return
    end
    local values={pcall(route.getter)}
    if not values[1] then
        route.readFailed=true
        if not route.warned then
            route.warned=true
            Log.Record("GUID_PROBE_COMBAT_LOG_UNREADABLE",{event=event,reason="getter_error",attemptID=lastAttempt.id})
        end
        return
    end
    local kind,source,destination,spellID=values[3],values[5],values[9],values[13]
    if not route.observed then
        route.observed=true
        Log.Record("GUID_PROBE_COMBAT_LOG_OBSERVED",{event=event,route=route.label,
            subeventPublic=NS.Public(kind),sourcePublic=NS.Public(source),destinationPublic=NS.Public(destination),
            tupleShape=NS.Public(kind) and type(kind)=="string" and "legacy_header" or "unknown"})
    end
    if not NS.Public(kind) or (kind~="SPELL_DAMAGE" and kind~="SPELL_MISSED" and kind~="SPELL_CAST_SUCCESS") then return end
    if not NS.Public(spellID) or spellID~=679 then return end
    local player=guid(NS.Read(UnitGUID,"player"))
    local publicSource,publicDestination=guid(source),guid(destination)
    if not player or not publicSource then
        Log.Record("GUID_PROBE_EFFECT_UNREADABLE",{attemptID=lastAttempt.id,event=event,
            reason="source_identity_unreadable",sourceGUID=safe(source),destinationGUID=safe(destination)})
        return
    end
    if publicSource~=player then return end
    if not publicDestination then
        Log.Record("GUID_PROBE_EFFECT_UNREADABLE",{attemptID=lastAttempt.id,event=event,
            reason="destination_unreadable",destinationGUID=safe(destination)})
        return
    end
    local effect=kind=="SPELL_DAMAGE" and "damage" or kind=="SPELL_MISSED" and "miss" or "cast"
    local focus=probeFocusConfirmed(lastAttempt.slot)
    local proven=lastAttempt.valid and not lastAttempt.ambiguous and focus
    local receiver=proven and (publicDestination==lastAttempt.expectedGUID and "expected" or "other") or "unproven"
    local state=lastAttempt.result
    -- Keep the strongest evidence when CAST_SUCCESS and DAMAGE both arrive.
    -- For the integrated route, a post-confirmation event may replace an older
    -- unproven observation, using only the new event's own effect type.
    local laterProven=lastAttempt.requiresClearConfirmation and proven and state and state.receiver=="unproven"
    if state and (state.effect~="damage" or effect=="damage" or laterProven) then
        state.receiver,state.effect=receiver,effect
        state.reason=lastAttempt.ambiguous and "ambiguous_attempt_window"
            or lastAttempt.requiresClearConfirmation and not lastAttempt.targetClearConfirmed
                and (lastAttempt.clearPostObserved and "target_clear_unconfirmed" or "awaiting_clear_confirmation")
            or not lastAttempt.valid and "stale_or_unreadable_mapping"
            or not focus and "probe_focus_not_confirmed" or "public_destination_guid"
        state.observedGUID=publicDestination
    end
    Log.Record("GUID_PROBE_EFFECT",{attemptID=lastAttempt.id,slot=lastAttempt.slot,mode=lastAttempt.mode,
        event=event,subevent=kind,sourceGUID=publicSource,expectedGUID=lastAttempt.expectedGUID,
        observedGUID=publicDestination,receiver=receiver,effect=effect,spellID=679,
        amount=effect=="damage" and safe(values[16]) or "[not-damage]",
        association="player_spell_679_within_5_seconds",recipientProven=proven,
        ambiguousWindow=lastAttempt.ambiguous,validConfiguration=lastAttempt.configurationValid,
        requiresClearConfirmation=lastAttempt.requiresClearConfirmation,
        targetClearConfirmed=lastAttempt.targetClearConfirmed==true,
        probeFocusConfirmed=focus,
        damageEventProven=proven and effect=="damage",
        healthLossProven=proven and effect=="damage" and NS.Number(values[16]) and values[16]>0})
end

local function unitEvidence(event,unit,action,descriptor,amount,school)
    if not recent() or not NS.Public(unit) or type(unit)~="string" then return end
    local identity=guid(NS.Read(UnitGUID,unit))
    if not identity then return end
    local slot
    for key,value in pairs(Log.captures) do if value.guid==identity then slot=key end end
    if not slot then return end
    local fields={attemptID=lastAttempt.id,slot=slot,observedGUID=identity,unit=unit,
        recipientProven=false,note="Unit update has no spell/caster attribution"}
    if event=="UNIT_HEALTH" then
        fields.health=read(UnitHealth,unit)
    else fields.action=safe(action);fields.descriptor=safe(descriptor);fields.amount=safe(amount);fields.school=safe(school) end
    Log.Record(event=="UNIT_HEALTH" and "GUID_PROBE_HEALTH_UPDATE" or "GUID_PROBE_UNIT_COMBAT",fields)
end

local function onEvent(_,event,a,b,c,d,e)
    if not Log.active then return end
    if Log.routes[event] then combatEvent(event);return end
    if event=="UNIT_HEALTH" or event=="UNIT_COMBAT" then unitEvidence(event,a,b,c,d,e);return end
    if not recent() then return end
    if event=="UI_ERROR_MESSAGE" then
        Log.Record("GUID_PROBE_ERROR",{attemptID=lastAttempt.id,errorID=safe(a),errorText=safe(b)})
        local state=lastAttempt.result
        if state and state.receiver=="unproven" and lastAttempt.configurationValid and not lastAttempt.ambiguous then state.reason="game_error" end
    elseif event:match("^UNIT_SPELLCAST_") then
        if not NS.Public(a) or a~="player" then return end
        local spell=event=="UNIT_SPELLCAST_SENT" and d or c
        if not NS.Public(spell) or spell~=679 then return end
        Log.Record("GUID_PROBE_CAST",{attemptID=lastAttempt.id,event=event,spellID=679,
            sentTarget=event=="UNIT_SPELLCAST_SENT" and safe(b) or "[not-sent]",
            castGUID=event=="UNIT_SPELLCAST_SENT" and safe(c) or safe(b),recipientProven=false})
        local state=lastAttempt.result
        if state and state.receiver=="unproven" and lastAttempt.configurationValid and not lastAttempt.ambiguous then state.reason="cast_event_only" end
    end
end

local function registerRoute(event,getter,label)
    local route={getter=getter,label=label,registered=false}
    Log.routes[event]=route
    local callbackEvent=read(C_EventUtils and C_EventUtils.IsCallbackEvent,event)
    local valid=read(C_EventUtils and C_EventUtils.IsEventValid,event)
    local reason="getter_unavailable"
    if type(getter)=="function" and restricted()~=true and valid~=false then
        local ok,accepted
        if callbackEvent==true then
            if type(RegisterEventCallback)=="function" and type(UnregisterEventCallback)=="function" then
                route.callback=function() pcall(combatEvent,event) end
                ok,accepted=pcall(RegisterEventCallback,event,route.callback)
            end
        else ok,accepted=pcall(frame.RegisterEvent,frame,event) end
        route.registered=ok==true and accepted~=false
        reason=route.registered and "registered_not_yet_observed" or "registration_unavailable"
    elseif restricted()==true then reason="restricted" end
    Log.Record("GUID_PROBE_COMBAT_LOG_CAPABILITY",{event=event,route=label,
        getterAvailable=type(getter)=="function",callbackEvent=callbackEvent,eventValid=valid,
        registered=route.registered,restricted=restricted(),reason=reason})
end

function Log.Start()
    if Log.active then return true end
    local diagnostics=NS.Diagnostics
    if not diagnostics or type(diagnostics.Start)~="function" then return false end
    ownLog=not diagnostics.Enabled()
    if ownLog then diagnostics.Start() end
    Log.active=true;Log.captures={};Log.results={};lastAttempt=nil
    frame=frame or CreateFrame("Frame")
    Log.frame=frame
    frame:SetScript("OnEvent",function(...) pcall(onEvent,...) end)
    frame:SetScript("OnUpdate",function()
        if not Log.active or not lastAttempt or lastAttempt.closed then return end
        local t=now()
        if not t or not lastAttempt.time or t-lastAttempt.time<=WINDOW then return end
        lastAttempt.closed=true
        local state=lastAttempt.result
        if state and lastAttempt.requiresClearConfirmation and not lastAttempt.clearPostObserved then
            state.targetClearConfirmed=false
            state.targetClearReason="target_clear_unconfirmed"
            if state.reason=="awaiting_clear_confirmation" then state.reason="target_clear_unconfirmed" end
            Log.Record("GUID_PROBE_WINDOW_ENDED",{attemptID=lastAttempt.id,reason="target_clear_unconfirmed",recipientProven=false})
        elseif state and state.receiver=="unproven" and (state.reason=="awaiting_effect" or state.reason=="cast_event_only") then
            state.reason="no_public_effect"
            Log.Record("GUID_PROBE_WINDOW_ENDED",{attemptID=lastAttempt.id,reason="no_public_effect",recipientProven=false})
        end
    end)
    for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET","UI_ERROR_MESSAGE","UNIT_HEALTH","UNIT_COMBAT"}) do
        pcall(frame.RegisterEvent,frame,event)
    end
    local legacy=CombatLogGetCurrentEventInfo
    local public=C_CombatLog and C_CombatLog.GetCurrentEventInfo
    registerRoute("COMBAT_LOG_EVENT_UNFILTERED",type(legacy)=="function" and legacy or public,
        type(legacy)=="function" and "legacy" or "public")
    registerRoute("COMBAT_LOG_EVENT_INTERNAL_UNFILTERED",C_CombatLogInternal and C_CombatLogInternal.GetCurrentEventInfo,"internal_all")
    Log.Record("GUID_PROBE_START",{spellID=679,configuredKey="Z",windowSeconds=WINDOW,
        legacyGetter=type(legacy)=="function",publicGetter=type(public)=="function",
        internalGetter=type(C_CombatLogInternal and C_CombatLogInternal.GetCurrentEventInfo)=="function",
        note="No name fallback; SENT/SUCCEEDED alone never prove an individual recipient"})
    return true
end

function Log.Stop()
    if not Log.active then return end
    Log.Record("GUID_PROBE_STOP",{attempts=Log.attemptID})
    for event,route in pairs(Log.routes) do
        if route.callback and type(UnregisterEventCallback)=="function" then pcall(UnregisterEventCallback,event,route.callback) end
    end
    if frame and type(frame.UnregisterAllEvents)=="function" then pcall(frame.UnregisterAllEvents,frame) end
    Log.active=false;lastAttempt=nil;Log.routes={}
    if ownLog and NS.Diagnostics then NS.Diagnostics.Stop("guid_probe_finished") end
    ownLog=false
end
