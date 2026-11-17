local _,NS=...
-- Read-only diagnostic. Frozen addresses are retired, never rebound or revived.
-- The user supplies every real target selection; no protected action is issued.
local P={serial=0,MAX_SECONDS=180,MAX_SAMPLES=40,MAX_LIFECYCLE_LOGS=120}
NS.UnitMatchProbe=P
local current,last

local function public(value)
    local ok,result=pcall(NS.Public,value)
    return ok and result==true
end
local function value(fn,...)
    if type(fn)~="function" then return "unavailable" end
    local ok,result=pcall(fn,...)
    if not ok then return "error" end
    if not public(result) then return "restricted" end
    if result==nil then return "nil" end
    return "public",result
end
local function boolean(fn,...)
    local state,result=value(fn,...)
    if state=="public" and type(result)~="boolean" then return "nonboolean" end
    return state,result
end
local function call(fn,...)
    local state,result=value(fn,...)
    return state=="public" or state=="nil",result
end
local function say(message) if type(NS.Print)=="function" then NS.Print(message) end end
local function plate(unit)
    return public(unit) and type(unit)=="string" and unit:match("^nameplate%d+$")~=nil
end
local function active(p) return p~=nil and current==p end
local function idle()
    local state,result=boolean(InCombatLockdown)
    return state=="public" and result==false
end
local function logger(p)
    local d=p.diagnostics
    local ok,session=call(d and d.Session)
    if not ok or not NS.Number(session) then return "error" end
    if session~=p.logSession then return "changed" end
    local state,on=boolean(d.Enabled)
    if state~="public" then return "error" end
    return on and "owned" or "off"
end
local function stampCurrent(p,fields,terminal)
    if terminal then return true end
    if fields.generation~=nil and (not active(p) or p.generation~=fields.generation) then return false end
    if fields.cohort~=nil and (not active(p) or p.cohort~=fields.cohort) then return false end
    return true
end
local function record(p,kind,fields,terminal)
    if logger(p)~="owned" then return false end
    fields=fields or {}
    if not stampCurrent(p,fields,terminal) then return false end
    fields.version,fields.probeID,fields.logSession=NS.VERSION,p.id,p.logSession
    fields.readOnly,fields.nativeActionsVerified=true,false
    local ok,result=pcall(p.diagnostics.Record,"UNIT_MATCH_"..kind,fields)
    return ok and result==true and logger(p)=="owned" and stampCurrent(p,fields,terminal)
end
local function otherActive()
    for _,module in pairs({actions=NS.InstanceActions,cycle=NS.FocusCycle,focus=NS.FocusAPIProbe,
        scale=NS.NativeScaleProbe,native=NS.EnemyNativeHover,trial=NS.EnemyNativeTrial,guid=NS.GUIDProbe}) do
        for _,method in ipairs({"Enabled","IsActive","Active"}) do
            if type(module[method])=="function" then
                local state,result=boolean(module[method])
                if state=="error" or state=="restricted" or state=="nonboolean" or state=="public" and result then return true end
            end
        end
        if type(module.Status)=="function" then
            local ok,status=call(module.Status)
            if not ok then return true end
            if type(status)=="table" then
                for _,key in ipairs({"active","restoring","configured"}) do
                    local readable,result=pcall(function() return status[key] end)
                    if not readable or not public(result) or result==true then return true end
                end
            end
        end
        for _,key in ipairs({"active","session","restoring"}) do
            local ok,result=pcall(function() return module[key] end)
            if not ok or not public(result) or result~=nil and result~=false then return true end
        end
    end
    return false
end
local function member(object,key,kind)
    local state,result=value(function() return object[key] end)
    if state=="public" and (kind=="boolean" and type(result)~="boolean" or kind=="number" and not NS.Number(result)) then
        return kind=="boolean" and "nonboolean" or "nonnumber"
    end
    return state,result
end
local function diagnose(entry)
    local display=NS.EnemyDisplay
    local ls,lc=boolean(display and display.IsCurrent,entry)
    local ms,metadata=value(display and display.LifecycleState,entry.unit)
    if ms=="public" and type(metadata)~="table" then ms="nontable";metadata=nil end
    local fields={lifecycleStatus=ls,lifecycleCurrent=lc,metadataStatus=ms}
    if ms=="public" then
        fields.validTokenStatus,fields.validToken=member(metadata,"validToken","boolean")
        fields.worldActiveStatus,fields.worldActive=member(metadata,"worldActive","boolean")
        fields.epochKnownStatus,fields.epochKnown=member(metadata,"epochKnown","boolean")
        fields.currentEpochStatus,fields.currentEpoch=member(metadata,"currentEpoch","number")
        fields.tombstonedStatus,fields.tombstoned=member(metadata,"tombstoned","boolean")
    end
    fields.existsStatus,fields.exists=boolean(UnitExists,entry.unit)
    fields.attackStatus,fields.attackable=boolean(UnitCanAttack,"player",entry.unit)
    fields.playerStatus,fields.isPlayer=boolean(UnitIsPlayer,entry.unit)
    local reason
    if ls~="public" then reason="lifecycle_"..ls
    elseif fields.worldActiveStatus=="public" and fields.worldActive==false then reason="world_inactive"
    elseif fields.tombstonedStatus=="public" and fields.tombstoned==true then reason="tombstoned"
    elseif fields.currentEpochStatus=="public" and fields.currentEpoch~=entry.tokenEpoch then reason="epoch_changed"
    elseif fields.epochKnownStatus=="public" and fields.epochKnown==false then reason="epoch_missing"
    elseif lc~=true then reason="lifecycle_public_false"
    elseif fields.existsStatus~="public" then reason="exists_"..fields.existsStatus
    elseif fields.exists~=true then reason="unit_missing"
    elseif fields.attackStatus~="public" then reason="attack_"..fields.attackStatus
    elseif fields.attackable~=true then reason="not_attackable"
    elseif fields.playerStatus~="public" then reason="player_"..fields.playerStatus
    elseif fields.isPlayer~=false then reason="is_player" end
    fields.currentFailureReason=reason
    return reason==nil,reason,fields
end
local reasons={user="手动结束",combat="进入战斗",world="切换地图或退出",timeout="达到三分钟时限",
    sample_limit="达到样本上限",log_changed="日志会话已改变",log_off="日志已关闭",log_error="日志不可读",
    record_failed="日志写入失败",other_experiment="其他目标试验已启动",tick_error="计时状态异常"}
local function finish(reason,trigger)
    local p=current
    if not p then return false end
    current=nil;p.generation=p.generation+1
    local state=logger(p)
    local saved=false
    if state=="owned" then
        saved=record(p,"END",{reason=reason,stopTrigger=trigger or reason,samples=p.samples,distinctMatches=p.seenCount,
            twoUnitsObserved=p.seenCount>=2,elapsed=p.elapsed,units=#p.entries,validUnits=p.validCount,
            invalidUnits=#p.entries-p.validCount,cohort=p.cohort,lastInvalidUnit=p.lastInvalidUnit,
            lastInvalidIndex=p.lastInvalidIndex,lastInvalidReason=p.lastInvalidReason,lastInvalidTrigger=p.lastInvalidTrigger,
            lifecycleDetails=p.lifecycleLogs},true)
        if logger(p)=="owned" and type(p.diagnostics.Stop)=="function" then
            local ok=pcall(p.diagnostics.Stop,"unitmatch_"..reason)
            if not ok or logger(p)=="owned" or logger(p)=="error" then saved=false end
        else saved=false end
    end
    last={active=false,probeID=p.id,logSession=p.logSession,samples=p.samples,distinctMatches=p.seenCount,
        twoUnitsObserved=p.seenCount>=2,reason=reason,stopTrigger=trigger or reason,units=#p.entries,
        validUnits=p.validCount,invalidUnits=#p.entries-p.validCount,cohort=p.cohort,elapsed=p.elapsed,logSaved=saved,
        lastInvalidUnit=p.lastInvalidUnit,lastInvalidReason=p.lastInvalidReason}
    if state=="changed" then say("单位匹配测试已结束：日志会话已改变；保留新日志继续运行。")
    elseif saved then say("单位匹配测试已结束（"..(reasons[reason] or "状态变化").."），请 /reload 保存日志。")
    else say("单位匹配测试已结束（"..(reasons[reason] or "状态变化").."）；日志可能不完整，请 /reload 保存。") end
    return saved
end
local function failedWrite(p,trigger)
    if active(p) then finish(logger(p)=="changed" and "log_changed" or "record_failed",trigger) end
    return false
end
local function checkGlobal(p,trigger)
    if not active(p) then return false end
    local state=logger(p)
    if state~="owned" then finish(state=="changed" and "log_changed" or state=="off" and "log_off" or "log_error",trigger);return false end
    if not idle() then finish("combat",trigger);return false end
    if otherActive() then finish("other_experiment",trigger);return false end
    return active(p)
end
local function entryFields(entry,index,fields,trigger,event,stage)
    fields.index,fields.unit,fields.tokenEpoch,fields.frozenEpoch=index,entry.unit,entry.tokenEpoch,entry.tokenEpoch
    fields.retired,fields.invalidReason=entry.retired==true,entry.invalidReason
    fields.trigger,fields.triggerEvent,fields.stage=trigger,event,stage
    return fields
end
local function detail(p,entry,index,fields,trigger,event,stage)
    if not active(p) then return false end
    if p.lifecycleLogs>=P.MAX_LIFECYCLE_LOGS then
        if not p.lifecycleLimitLogged then
            p.lifecycleLimitLogged=true
            local cohort=p.cohort
            if not record(p,"LIFECYCLE_LIMIT",{limit=P.MAX_LIFECYCLE_LOGS,cohort=cohort}) then
                if not active(p) or p.cohort~=cohort then return false end
                return failedWrite(p,trigger)
            end
        end
        return active(p)
    end
    p.lifecycleLogs=p.lifecycleLogs+1
    entryFields(entry,index,fields,trigger,event,stage);fields.cohort=p.cohort
    local cohort=p.cohort
    if not record(p,"LIFECYCLE",fields) then
        if not active(p) or p.cohort~=cohort then return false end
        return failedWrite(p,trigger)
    end
    return active(p)
end
local function invalidate(p,entry,index,fields,reason,trigger,event,stage)
    if not active(p) or entry.retired then return active(p) end
    -- Commit retirement before calling the possibly reentrant logger. The old
    -- epoch is immutable, and repeated events cannot reset the group again.
    entry.retired,entry.invalidReason,entry.invalidTrigger=true,reason,trigger
    entry.invalidEvent,entry.invalidElapsed=event,p.elapsed
    local previousSeen,previousCohort=p.seenCount,p.cohort
    p.validCount=p.validCount-1;p.cohort=p.cohort+1
    p.seen,p.seenCount,p.notifiedTwo={},0,false
    p.lastInvalidUnit,p.lastInvalidIndex,p.lastInvalidReason,p.lastInvalidTrigger=entry.unit,index,reason,trigger
    entryFields(entry,index,fields,trigger,event,stage)
    fields.reason,fields.elapsed=reason,p.elapsed
    fields.previousCohort,fields.cohort,fields.previousSeenCount=previousCohort,p.cohort,previousSeen
    fields.remainingValid,fields.observationReset=p.validCount,true
    local cohort=p.cohort
    if not record(p,"INVALIDATED",fields) then
        if not active(p) or p.cohort~=cohort then return false end
        return failedWrite(p,trigger)
    end
    if not active(p) or p.cohort~=cohort then return false end
    local suffix=p.validCount>=2 and "请在新组内重新各选一次。" or "可用地址不足两个，继续记录原始比较供排查。"
    say("单位匹配：测试编号 "..index.."（"..entry.unit.."）已失效，原因="..reason.."；剩余 "..p.validCount.." 个地址，组号 "..p.cohort.."。"..suffix)
    return true
end
local function check(p,trigger)
    trigger=trigger or "validation"
    if not checkGlobal(p,trigger) then return false end
    for index,entry in ipairs(p.entries) do
        if not entry.retired then
            local ok,reason,fields=diagnose(entry)
            if not active(p) then return false end
            if not ok then invalidate(p,entry,index,fields,reason,trigger,nil,"check") end
            if not active(p) then return false end
        end
    end
    return active(p)
end
local function still(p,generation,cohort,trigger)
    return active(p) and p.generation==generation and p.cohort==cohort and check(p,trigger)
        and active(p) and p.generation==generation and p.cohort==cohort
end
local function snapshot(phase)
    local p=current
    if not p or not check(p,phase) then return false end
    if p.samples>=P.MAX_SAMPLES then finish("sample_limit",phase);return false end
    local generation,cohort=p.generation,p.cohort
    local es,targetExists=boolean(UnitExists,"target")
    local candidate,truths,rawTruths,unknown,rawUnknown,rows=nil,0,0,0,0,{}
    local secrets=C_Secrets
    for index,entry in ipairs(p.entries) do
        local eligible,reason,fields=diagnose(entry)
        if not active(p) then return false end
        if not entry.retired and not eligible then invalidate(p,entry,index,fields,reason,phase,nil,"sample") end
        if not active(p) or p.generation~=generation or p.cohort~=cohort then return false end
        local cs,canCompare=boolean(secrets and secrets.CanCompareUnitTokens,entry.unit,"target")
        local ss,comparisonSecret=boolean(secrets and secrets.ShouldUnitComparisonBeSecret,entry.unit,"target")
        local ms,same=boolean(UnitIsUnit,entry.unit,"target")
        local rawKnown=cs=="public" and canCompare==true and ss=="public" and comparisonSecret==false and ms=="public"
        local known=not entry.retired and eligible and rawKnown
        if ms=="public" and same then rawTruths=rawTruths+1 end
        if not rawKnown then rawUnknown=rawUnknown+1 end
        if not entry.retired then
            if known and same then truths=truths+1;candidate=index elseif not known then unknown=unknown+1 end
        end
        entryFields(entry,index,fields,phase,nil,"sample")
        fields.sampleID,fields.phase,fields.generation,fields.cohort=p.samples+1,phase,generation,cohort
        fields.canCompareStatus,fields.canCompare,fields.secrecyStatus,fields.comparisonSecret=cs,canCompare,ss,comparisonSecret
        fields.sameStatus,fields.same,fields.rawComparisonReadable,fields.qualifiedComparison=ms,same,rawKnown,known
        fields.targetExistsStatus,fields.targetExists=es,targetExists
        rows[#rows+1]=fields
    end
    if not still(p,generation,cohort,phase) then return false end
    local match=p.validCount>=2 and es=="public" and targetExists==true and unknown==0 and truths==1 and candidate or nil
    local unit=match and p.entries[match].unit
    local nextSeen=p.seenCount+(unit and not p.seen[unit] and 1 or 0)
    local sampleID=p.samples+1
    for _,fields in ipairs(rows) do
        if not active(p) or p.generation~=generation or p.cohort~=cohort then return false end
        if not record(p,"ROW",fields) then
            if not active(p) or p.generation~=generation or p.cohort~=cohort then return false end
            return failedWrite(p,phase)
        end
    end
    if not still(p,generation,cohort,phase) then return false end
    if not record(p,"SAMPLE",{sampleID=sampleID,phase=phase,generation=generation,cohort=cohort,units=#p.entries,
        validUnits=p.validCount,invalidUnits=#p.entries-p.validCount,insufficientValidUnits=p.validCount<2,
        trueCount=truths,qualifiedTrueCount=truths,rawTrueCount=rawTruths,unknownCount=unknown,rawUnknownCount=rawUnknown,
        targetExistsStatus=es,targetExists=targetExists,uniquePublicMatch=match~=nil,matchedIndex=match,
        distinctMatches=nextSeen,twoUnitsObserved=nextSeen>=2}) then
        if active(p) and p.generation==generation and p.cohort==cohort then return failedWrite(p,phase) end
        return false
    end
    if not still(p,generation,cohort,phase) then return false end
    p.samples=sampleID
    if unit and not p.seen[unit] then p.seen[unit]=true;p.seenCount=nextSeen end
    if p.seenCount>=2 and not p.notifiedTwo then
        p.notifiedTwo=true
        say("单位匹配：已记录同组两个不同测试编号各自唯一的公开正匹配。请 /mytargets unitmatch off 后 /reload 保存；这不代表焦点或施法已通过。")
    elseif phase~="baseline" and phase~="delayed" then
        if p.validCount<2 then say("单位匹配：可用地址不足两个，原始比较已记录，未确认有效匹配。")
        elseif match then say("单位匹配：当前目标对应测试编号 "..match.."；其余有效地址均为公开 false，组号 "..cohort.."。")
        elseif unknown>0 or es~="public" then say("单位匹配：本次存在受限、不可用或读取错误，已记录，未确认匹配。")
        else say("单位匹配：本次没有唯一公开匹配，已记录。") end
    end
    if p.samples>=P.MAX_SAMPLES then finish("sample_limit",phase) end
    return true
end
function P.Enabled() return current~=nil end
function P.Status()
    local p=current
    if p then return {active=true,probeID=p.id,logSession=p.logSession,samples=p.samples,
        distinctMatches=p.seenCount,twoUnitsObserved=p.seenCount>=2,units=#p.entries,elapsed=p.elapsed,
        validUnits=p.validCount,invalidUnits=#p.entries-p.validCount,cohort=p.cohort,
        lastInvalidUnit=p.lastInvalidUnit,lastInvalidReason=p.lastInvalidReason} end
    local result={active=false};for k,v in pairs(last or {}) do result[k]=v end;return result
end
local function start()
    if current then
        if not check(current,"repeat_on") then return false end
        say("单位匹配测试正在记录；可用 "..current.validCount.." 个地址，请正常选择两只怪物。");return true
    end
    local ok,inside,kind
    if type(IsInInstance)=="function" then ok,inside,kind=pcall(IsInInstance) end
    if not ok or not public(inside) or not public(kind) or inside~=true or (kind~="party" and kind~="raid") then
        say("单位匹配测试请在副本内开启。");return false
    end
    if not idle() then say("请脱战后开启单位匹配测试。");return false end
    local ts,hasTarget=boolean(UnitExists,"target")
    if ts~="public" or hasTarget~=false then say("请先手动清空当前目标，再开启单位匹配测试。");return false end
    local ss,spell=boolean(SpellIsTargeting)
    local cs,item=boolean(CursorHasItem)
    if ss~="public" or cs~="public" or spell or item then say("请取消待施法或物品光标后再开启。");return false end
    if otherActive() then say("请先结束其他目标试验，再开启单位匹配测试。");return false end
    local readable,tokens=call(NS.RestrictedEnemyTokens)
    local display=NS.EnemyDisplay
    if not readable or type(tokens)~="table" or not display or type(display.RestrictedEntry)~="function" then
        say("单位匹配测试无法读取姓名板，请 /reload 后重试。");return false
    end
    local entries,seen={},{}
    for _,unit in ipairs(tokens) do
        if #entries>=20 then break end
        if plate(unit) and not seen[unit] then
            local entryOK,entry=call(display.RestrictedEntry,unit)
            local fieldsOK,entryUnit,epoch,restricted=false
            if entryOK and type(entry)=="table" then
                fieldsOK,entryUnit,epoch,restricted=pcall(function() return entry.unit,entry.tokenEpoch,entry.restrictedIdentity end)
            end
            if fieldsOK and public(entryUnit) and entryUnit==unit and NS.Number(epoch) and epoch>0 and epoch%1==0
                and public(restricted) and restricted==true then
                local frozen={unit=unit,tokenEpoch=epoch,restrictedIdentity=true}
                if diagnose(frozen) then entries[#entries+1]=frozen;seen[unit]=true end
            end
        end
    end
    if #entries<2 then say("至少需要两个可测敌方姓名板；请靠近两只怪物并保持头顶血条可见。");return false end
    local d=NS.Diagnostics
    if not d or type(d.Start)~="function" or type(d.Session)~="function" or type(d.Enabled)~="function"
        or type(d.Record)~="function" or type(d.Stop)~="function" then say("单位匹配日志模块未加载，请 /reload。");return false end
    local started=pcall(d.Start)
    local sessionOK,session=call(d.Session)
    local ds,on=boolean(d.Enabled)
    if not started or not sessionOK or not NS.Number(session) or ds~="public" or not on then
        say("单位匹配日志未能开启，请 /reload 后重试。");return false
    end
    P.serial=P.serial+1
    local p={id=P.serial,entries=entries,seen={},seenCount=0,generation=0,cohort=1,samples=0,elapsed=0,
        pulse=0,diagnostics=d,logSession=session,validCount=#entries,lifecycleLogs=0}
    current=p
    -- Registration remains valid if a logged lifecycle event retires an
    -- address reentrantly; only samples are bound to one unchanged cohort.
    if not record(p,"START",{units=#entries,maxSeconds=P.MAX_SECONDS,maxSamples=P.MAX_SAMPLES,
        lifecycleDetailLimit=P.MAX_LIFECYCLE_LOGS,originalTargetEmpty=true,manualSelection=true,cohort=1},true) then
        if active(p) then finish("record_failed","start") end
        return false
    end
    if not snapshot("baseline") then return false end
    say("单位匹配测试 "..NS.VERSION.." 已开启，固定 "..#entries.." 个测试地址（可用 "..p.validCount.."）。请依次选中两只同名怪各停一秒；/mytargets unitmatch off 结束，再 /reload 保存。")
    return true
end
local function eventEntry(p,event,unit,stage)
    if not plate(unit) then return end
    for index,entry in ipairs(p.entries) do
        if entry.unit==unit then
            local _,_,fields=diagnose(entry)
            if not active(p) then return end
            if stage=="before" and not entry.retired then
                local reason=event=="NAME_PLATE_UNIT_REMOVED" and "nameplate_removed" or "nameplate_added"
                if not invalidate(p,entry,index,fields,reason,"event",event,stage) then return end
                local _,_,fresh=diagnose(entry);fields=fresh
            end
            if not active(p) then return end
            detail(p,entry,index,fields,"event",event,stage)
            return
        end
    end
end
function P.OnEvent(event,unit)
    local p=current;if not p then return end
    if event=="PLAYER_REGEN_DISABLED" then finish("combat",event);return end
    if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LOGOUT" then finish("world",event);return end
    if event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED" then eventEntry(p,event,unit,"before")
    elseif event=="PLAYER_TARGET_CHANGED" then
        p.generation=p.generation+1
        local generation=p.generation
        if not snapshot("target_changed") or not active(p) or p.generation~=generation then return end
        local cohort=p.cohort
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(.15,function()
                if active(p) and p.generation==generation and p.cohort==cohort then snapshot("delayed") end
            end)
        end
    end
end
function P.OnAfterEvent(event,unit)
    local p=current;if not p then return end
    if event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED" then eventEntry(p,event,unit,"after") end
end
function P.Tick(elapsed)
    local p=current;if not p then return end
    if not NS.Number(elapsed) or elapsed<0 then finish("tick_error","periodic");return end
    p.elapsed=p.elapsed+elapsed;p.pulse=p.pulse+elapsed
    if p.elapsed>=P.MAX_SECONDS then finish("timeout","periodic");return end
    if p.pulse>=.5 then p.pulse=0;check(p,"periodic") end
end
function P.Command(argument)
    local arg=NS.Text(argument):lower()
    if arg=="on" then return start() end
    if arg=="off" then
        if not current then say("单位匹配测试未运行；已有记录可用 /reload 保存。");return true end
        return finish("user","command_off")
    end
    if arg=="sample" then
        if not current then say("请先 /mytargets unitmatch on。");return false end
        return snapshot("manual")
    end
    local status=P.Status()
    say("单位匹配测试 "..NS.VERSION.." "..(status.active and "运行中" or "未运行").."；采样 "..(status.samples or 0)..
        " 次，可用地址 "..(status.validUnits or 0).."，组号 "..(status.cohort or 0).."；本组公开匹配 "..(status.distinctMatches or 0)..
        " 个。/mytargets unitmatch on / off。")
    return status.active
end
