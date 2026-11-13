local _, NS = ...
-- Each prepared native macro is executed by a real click. A matched focus may
-- share that click with one restoration action; no macro cycles multiple mobs.
-- Ordinary Lua only prepares the next click and verifies public identities.
local F={MAX_SEEK=20,MAX_RESTORE=40,serial=0,attemptSerial=0,combineFocusRestore=true}
NS.FocusCycle=F
local STOP="/stopmacro"
local PREFIX="/stopmacro [combat]\n"
local reasonText={cancelled="已取消",not_found="未找到指定怪物",cycle_stalled="选敌未继续推进",
    goal_unavailable="指定怪物已消失或死亡",focus_failed="焦点设置未生效",focus_not_verified="焦点读回不匹配",
    focus_changed="焦点已变化",invalid_goal="格子中的怪物身份暂不可用",
    unreadable_original_state="原目标或原焦点身份不可读",combat_or_cursor="请脱战并取消待施法或物品光标",
    setup_reload_required="初始化未完成，请先重载",setup_failed="无法创建操作按钮，请重载后重试",
    diagnostics_failed="无法开启诊断日志，请重载后重试"}
local function read(fn,...) return NS.Read(fn,...) end
local function idle() return read(InCombatLockdown)==false end
local function guid(v)
    return NS.Public(v) and type(v)=="string" and #v<=128 and v:match("^[%w%-]+$") and v or nil
end
local function safe(v)
    if not NS.Public(v) then return "[restricted]" end
    if v==nil then return "[nil]" end
    if type(v)=="string" or type(v)=="boolean" or NS.Number(v) then return v end
    return "[unsupported]"
end
local function state(unit)
    local exists,raw=read(UnitExists,unit),read(UnitGUID,unit)
    if exists==false and raw==nil then return {exists=false} end
    local g=guid(raw)
    if exists==true and g then return {exists=true,guid=g} end
end
local function equal(a,b)
    return a~=nil and b~=nil and a.exists==b.exists and a.guid==b.guid
end
local function say(s) if NS.Print then NS.Print(s) end end
local function log(kind,c,extra)
    if not NS.Diagnostics or type(NS.Diagnostics.Record)~="function" then return end
    local target,focus=state("target"),state("focus")
    local fields={flowID=c and c.id,phase=c and c.state,goalGUID=c and c.goalGUID,
        originalTargetGUID=safe(c and c.originalTarget.guid),originalTargetExists=c and c.originalTarget.exists,
        targetGUID=safe(target and target.guid),targetExists=target and target.exists,
        focusGUID=safe(focus and focus.guid),focusExists=focus and focus.exists,
        focusMatchesGoal=c~=nil and focus~=nil and focus.guid==c.goalGUID or false,
        targetRestored=c~=nil and equal(target,c.originalTarget) or false,
        committed=c and c.committed,seekSteps=c and c.seekSteps,restoreSteps=c and c.restoreSteps,
        reason=c and c.reason,combat=safe(read(InCombatLockdown))}
    for k,v in pairs(extra or {}) do fields[k]=v end
    pcall(NS.Diagnostics.Record,kind,fields)
end
local function cursorClear()
    return read(SpellIsTargeting)==false and read(CursorHasItem)==false
end
local independentUnits={"player"}
local independentSet={player=true}
for _,group in ipairs({{"party",4},{"raid",40},{"boss",8},{"arena",5}}) do
    for i=1,group[2] do
        local u=group[1]..i
        independentUnits[#independentUnits+1]=u;independentSet[u]=true
    end
end
local function independentAlias(g,preferred)
    if independentSet[preferred] then
        local s=state(preferred)
        if s and s.exists and s.guid==g then return preferred end
    end
    for _,u in ipairs(independentUnits) do
        local s=state(u)
        if s and s.exists and s.guid==g then return u end
    end
end
local function nameCommand(v)
    return NS.Public(v) and type(v)=="string" and v~="" and #v<=255
        and not v:find("[%z\1-\31\127%[%]|;/\\]")
        and not v:match("^%s") and not v:match("%s$") and v or nil
end
local function goalUnit(c)
    local function matches(u)
        return type(u)=="string" and guid(read(UnitGUID,u))==c.goalGUID and read(UnitExists,u)==true
    end
    if matches("target") then return "target" end
    if matches(c.goalUnit) then return c.goalUnit end
    for _,u in ipairs(independentUnits) do if matches(u) then return u end end
    local plates=read(NS.NameplateTokens)
    if type(plates)=="table" then
        for _,u in ipairs(plates) do if matches(u) then c.goalUnit=u;return u end end
    end
end
local function goalAlive(c)
    local u=goalUnit(c)
    return u and read(UnitCanAttack,"player",u)==true and read(UnitIsDeadOrGhost,u)==false
end
function F.IsActive() return F.session~=nil end
function F.Owns(row) return F.session~=nil and F.session.row==row end
function F.HoldRoster(side) return F.session~=nil and side=="enemy" end
function F.RowStatus(row)
    local c=F.session
    if not c or c.row~=row then return nil end
    if c.paused then return "暂停" end
    if c.state=="matched" then return "右键确认" end
    if c.state=="restore" then return "右键恢复" end
    if c.state=="blocked" then return "未恢复" end
    return "寻找 "..c.seekSteps.."/"..F.MAX_SEEK
end
function F.PinnedData(row)
    local c=F.session
    if not c or c.row~=row then return nil end
    local u=goalUnit(c)
    local data=u and read(NS.ReadUnit,u,"enemy")
    if type(data)=="table" and guid(data.guid)==c.goalGUID then return data end
    -- Keep the frozen name visible without pretending stale health is current.
    return {guid=c.goalGUID,name=c.name,targetName=c.name,player=false,dead=false,
        offline=false,color={r=1,g=.4,b=.34},healthAvailable=false,powerAvailable=false}
end
local function setRowFlag(row,value)
    if not row or type(row.SetAttribute)~="function" then return end
    if idle() then row:SetAttribute("focus-cycle-active",value)
    else F.deferredRow=row end
end
local function buttonNoop()
    local b=F.button
    if not b or not idle() then return end
    b:SetAttribute("unit",nil)
    for _,n in ipairs({1,2}) do
        b:SetAttribute("*type"..n,"macro");b:SetAttribute("*macrotext"..n,STOP)
        b:SetAttribute("*unit"..n,nil)
    end
end
local function render()
    if not F.button or not idle() then return end
    local c=F.session
    if not c then
        buttonNoop()
        if F.visibilityRegistered then UnregisterStateDriver(F.button,"visibility");F.visibilityRegistered=false end
        F.button:Hide();return
    end
    local text=c.state=="seek" and ("正在寻找「"..c.name.."」 "..c.seekSteps.."/"..F.MAX_SEEK)
        or c.state=="matched" and (F.combineFocusRestore and "已找到：右键设置焦点并恢复目标" or "已找到：右键设置焦点")
        or c.state=="blocked" and "原目标尚未恢复，请手动选回或停止"
        or (c.committed and "尚未完成：右键继续恢复原目标" or "已停止寻找：右键恢复原目标")
    if c.paused then text="已暂停："..c.paused end
    F.button.label:SetText(text.."\n右键执行下一步 · 左键取消并恢复\n窗口关闭并提示完成，才算全部结束")
    if not F.visibilityRegistered then
        RegisterStateDriver(F.button,"visibility","[combat] hide; show");F.visibilityRegistered=true
    end
    if read(F.button.IsShown,F.button)~=true then F.button:Show() end
end
local function finish(c,kind,reason)
    if F.session~=c then return end
    local target,focus=state("target"),state("focus")
    F.lastResult={kind=kind,reason=reason,focusSet=focus~=nil and focus.guid==c.goalGUID,
        targetRestored=equal(target,c.originalTarget),goalGUID=c.goalGUID}
    log("FOCUS_CYCLE_END",c,{result=kind,endReason=reason,
        focusSet=F.lastResult.focusSet,targetRestored=F.lastResult.targetRestored})
    F.session=nil;F.current=nil;setRowFlag(c.row,nil)
    render()
    if kind=="complete" then say("焦点已按GUID设为「"..c.name.."」，原目标已恢复。")
    elseif kind=="failed_restored" then say("未完成焦点设置（"..(reasonText[reason] or reason).."）；原目标已恢复。")
    else say("焦点流程已停止；"..(F.lastResult.targetRestored and "当前目标是原目标。" or "原目标尚未恢复，当前目标保持。")) end
    if type(NS.RequestRefresh)=="function" and idle() then NS.RequestRefresh() end
end
local function restored(c)
    if not equal(state("target"),c.originalTarget) then return false end
    local focus=state("focus")
    if not focus then return false end
    if c.committed then
        if focus.guid==c.goalGUID then finish(c,"complete",c.cancelled and "cancel_after_focus" or "verified")
        else finish(c,"failed_restored","focus_not_verified") end
    elseif equal(focus,c.oldFocus) then finish(c,"failed_restored",c.reason or "cancelled")
    else finish(c,"failed_restored","focus_changed") end
    return true
end
local function beginRestore(c,reason)
    c.state="restore";c.reason=reason;c.paused=nil
    log("FOCUS_CYCLE_RESTORE",c)
end
local function nearestReturned(reverse)
    local a=F.current
    if not a or (a.action~="seek" and a.action~="restore_cycle"
        and not (a.action=="focus_restore" and a.restoreAction=="restore_cycle")) then return end
    a.calls=a.calls+1;a.sample=state("target")
    log("FOCUS_CYCLE_STEP",a.session,{attemptID=a.id,action=a.action,restoreAction=a.restoreAction,ordinal=a.calls,
        reverse=safe(reverse),sampleGUID=safe(a.sample and a.sample.guid)})
end
local COMBAT_GUARD=[[
    if SecureCmdOptionParse("[combat] blocked") then
        self:SetAttribute("*type1","macro");self:SetAttribute("*macrotext1","/stopmacro")
        self:SetAttribute("*type2","macro");self:SetAttribute("*macrotext2","/stopmacro")
    end
]]
local function build()
    if F.button then return true end
    if type(CreateFrame)~="function" or type(SecureHandlerWrapScript)~="function"
        or type(RegisterStateDriver)~="function" or type(UnregisterStateDriver)~="function"
        or type(hooksecurefunc)~="function" or type(TargetNearestEnemy)~="function" then return false end
    local b=CreateFrame("Button","MyForeverFocusCycleStep",UIParent,"SecureActionButtonTemplate,SecureHandlerStateTemplate,BackdropTemplate")
    F.button=b
    b:SetSize(270,68);b:SetPoint("CENTER",UIParent,"CENTER",0,180)
    b:SetFrameStrata("DIALOG");b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b:SetAttribute("useOnKeyDown",false)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    b:SetBackdropColor(.05,.10,.16,.96);b:SetBackdropBorderColor(.85,.7,.2,1)
    b.label=b:CreateFontString(nil,"OVERLAY","GameFontNormal")
    b.label:SetPoint("CENTER");b.label:SetWidth(254)
    buttonNoop();b:Hide()
    SecureHandlerWrapScript(b,"PreClick",b,COMBAT_GUARD)
    b:HookScript("PreClick",function(self,button,down)
        if down or (button~="RightButton" and button~="LeftButton") then return end
        if not idle() then return end
        buttonNoop()
        local c=F.session
        if not c then return end
        local command=F.Prepare(c.row,nil,button=="LeftButton")
        local n=button=="LeftButton" and 1 or 2
        self:SetAttribute("*macrotext"..n,command)
    end)
    b:HookScript("PostClick",function(_,button,down)
        if down or (button~="RightButton" and button~="LeftButton") then return end
        local a=F.current
        if a then F.AfterClick(a.session.row) end
        buttonNoop()
    end)
    local ok=pcall(hooksecurefunc,"TargetNearestEnemy",function(reverse) pcall(nearestReturned,reverse) end)
    F.hookInstalled=ok
    return ok
end
local function start(row,data)
    if not idle() or not cursorClear() then return nil,"combat_or_cursor" end
    local expected=row and guid(row.expectedGUID)
    if not expected or type(data)~="table" or guid(data.guid)~=expected or data.player~=false
        or not row.unit or guid(read(UnitGUID,row.unit))~=expected
        or read(UnitCanAttack,"player",row.unit)~=true or read(UnitIsDeadOrGhost,row.unit)~=false then
        return nil,"invalid_goal"
    end
    local original,oldFocus=state("target"),state("focus")
    if not original or not oldFocus then return nil,"unreadable_original_state" end
    local originalAlias=original.exists and independentAlias(original.guid) or nil
    local hostile=original.exists and read(UnitCanAttack,"player","target")==true
        and read(UnitIsDeadOrGhost,"target")==false
    local originalName
    if original.exists and read(UnitIsPlayer,"target")==true and not originalAlias then
        local side=read(UnitCanAttack,"player","target")==true and "enemy" or "friendly"
        local originalData=read(NS.ReadUnit,"target",side)
        originalName=type(originalData)=="table" and nameCommand(originalData.targetName) or nil
    end
    if original.exists and original.guid~=expected and not originalAlias and not originalName and not hostile then
        return nil,"original_unrestorable"
    end
    if F.setupFailed then return nil,"setup_reload_required" end
    local ok,ready=pcall(build)
    if not ok or not ready then
        F.setupFailed=true;buttonNoop()
        if F.button and idle() then F.button:Hide() end
        return nil,"setup_failed"
    end
    if NS.FocusAPIProbe and NS.FocusAPIProbe.active then NS.FocusAPIProbe.Command("off") end
    if NS.Diagnostics and type(NS.Diagnostics.Start)=="function" then
        local started=pcall(NS.Diagnostics.Start)
        if not started then return nil,"diagnostics_failed" end
    end
    F.serial=F.serial+1
    local c={id=F.serial,row=row,goalGUID=expected,goalUnit=row.unit,name=NS.Text(data.name),
        originalTarget=original,oldFocus=oldFocus,ownedTarget=original,originalAlias=originalAlias,
        originalName=originalName,restoreByCycle=hostile,committed=false,seekSteps=0,restoreSteps=0,
        state=original.guid==expected and "matched" or "seek",seen={}}
    F.session=c;setRowFlag(row,true);log("FOCUS_CYCLE_BEGIN",c)
    return c
end
local function restoreCommand(c)
    if not c.originalTarget.exists then return "restore_empty","/cleartarget" end
    local u=independentAlias(c.originalTarget.guid,c.originalAlias)
    if u then
        c.originalAlias=u
        return "restore_alias","/target [@"..u..",exists]"
    end
    if c.originalName then return "restore_name","/targetexact "..c.originalName end
    if c.restoreByCycle then return "restore_cycle","/targetenemy 1" end
end
function F.Prepare(row,data,cancel)
    local c=F.session
    if c and c.row~=row then say("同名怪焦点流程正在处理，请继续原格或中央按钮。");return STOP,"busy" end
    if not c then
        local reason;c,reason=start(row,data)
        if not c then
            say(reason=="original_unrestorable" and "原目标无法可靠恢复；请先清空当前目标再设置同名怪焦点。"
                or "焦点流程未启动："..(reasonText[reason] or "状态暂不可用，请重载后重试"))
            return STOP,reason
        end
    end
    if F.current then return STOP,"click_pending" end
    if not idle() then c.paused="战斗中";return STOP,"combat" end
    if not cursorClear() then c.paused="请先取消待施法或物品光标";render();return STOP,"cursor" end
    c.paused=nil
    local actual,focus=state("target"),state("focus")
    if not equal(actual,c.ownedTarget) then
        if c.state=="restore" or c.state=="blocked" then
            if restored(c) then return STOP,"restored_manually" end
        end
        if c.state=="blocked" and equal(actual,c.blockedTarget) then
            render();return STOP,"restore_mismatch"
        end
        finish(c,"aborted","target_changed");return STOP,"target_changed"
    end
    local expectedFocus=c.committed and {exists=true,guid=c.goalGUID} or c.oldFocus
    if not equal(focus,expectedFocus) then finish(c,"aborted","focus_changed");return STOP,"focus_changed" end
    if cancel then c.cancelled=true;beginRestore(c,"cancelled") end
    if (c.state=="seek" or c.state=="matched") and not goalAlive(c) then beginRestore(c,"goal_unavailable") end
    if c.state=="seek" and actual.guid==c.goalGUID then c.state="matched" end
    if c.state=="seek" and c.seekSteps>=F.MAX_SEEK then beginRestore(c,"not_found") end
    if c.state=="restore" or c.state=="blocked" then
        if restored(c) then return STOP,"restored" end
        if c.restoreSteps>=F.MAX_RESTORE or c.state=="blocked" then
            c.state="blocked";c.reason="restore_limit";render();return STOP,"restore_limit"
        end
    end
    local action,command,restoreAction
    if c.state=="seek" then action="seek";command=PREFIX.."/targetenemy"
    elseif c.state=="matched" then
        if actual.guid~=c.goalGUID then finish(c,"aborted","goal_not_current");return STOP,"goal_not_current" end
        action="focus";command=PREFIX.."/focus [@target,exists]"
        if F.combineFocusRestore and not equal(actual,c.originalTarget) then
            local line;restoreAction,line=restoreCommand(c)
            if restoreAction then action="focus_restore";command=command.."\n"..line end
        end
    else
        local line;action,line=restoreCommand(c)
        if not action then c.state="blocked";c.reason="restore_unavailable";render();return STOP,"restore_unavailable" end
        command=PREFIX..line
    end
    F.attemptSerial=F.attemptSerial+1
    local a={id=F.attemptSerial,session=c,action=action,restoreAction=restoreAction,
        calls=0,beforeTarget=actual,focusRequested=action=="focus" or action=="focus_restore"}
    F.current=a
    log("FOCUS_CYCLE_PRE",c,{attemptID=a.id,action=action,restoreAction=restoreAction,
        combined=action=="focus_restore"})
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(0,function()
            if F.current==a then
                F.current=nil;c.paused="本次点击未完成，请停止后重新准备"
                log("FOCUS_CYCLE_INTERRUPTED",c,{attemptID=a.id,action=action});render()
            end
        end)
    end
    render()
    return command,action
end
function F.AfterClick(row)
    local a=F.current
    if not a or a.session~=F.session or a.session.row~=row then return end
    F.current=nil
    local c=a.session
    local actual,focus=state("target"),state("focus")
    if not actual or not focus then c.paused="单位身份暂不可读";log("FOCUS_CYCLE_POST",c,{attemptID=a.id,action=a.action});render();return end
    if a.action=="seek" or a.action=="restore_cycle" then
        if a.calls~=1 or not equal(a.sample,actual) then
            c.paused="无法确认本次选敌结果";log("FOCUS_CYCLE_POST",c,{attemptID=a.id,action=a.action,calls=a.calls});render();return
        end
        local previous=c.ownedTarget
        c.ownedTarget=actual
        if a.action=="seek" then
            c.seekSteps=c.seekSteps+1
            c.stalled=equal(actual,previous) and (c.stalled or 0)+1 or 0
            if actual.guid==c.goalGUID then c.state="matched"
            elseif c.stalled>=3 then beginRestore(c,"cycle_stalled")
            elseif c.seekSteps>=F.MAX_SEEK or not actual.exists then beginRestore(c,"not_found") end
        else c.restoreSteps=c.restoreSteps+1 end
    elseif a.action=="focus_restore" then
        -- A successful focus must never be repeated on the target reached by
        -- restoration. Verify the two parts independently, including partial
        -- execution when the second native command is skipped or restricted.
        c.committed=focus.exists and focus.guid==c.goalGUID
        if not c.committed and not equal(focus,c.oldFocus) then
            finish(c,"aborted","external_focus_during_combined");return
        end
        beginRestore(c,c.committed and "focus_set" or "focus_failed")
        if a.restoreAction=="restore_cycle" then
            if a.calls==1 and equal(a.sample,actual) then
                c.ownedTarget=actual;c.restoreSteps=c.restoreSteps+1
            elseif a.calls==0 and equal(actual,a.beforeTarget) then
                F.combineFocusRestore=false
                log("FOCUS_CYCLE_COMBINED_FALLBACK",c,{attemptID=a.id,reason="restore_not_observed"})
            else
                c.state="blocked";c.blockedTarget=actual;c.paused="无法确认恢复结果，请手动选回原目标"
            end
        elseif equal(actual,c.originalTarget) then
            c.ownedTarget=actual;c.restoreSteps=c.restoreSteps+1
        elseif equal(actual,a.beforeTarget) then
            F.combineFocusRestore=false
            log("FOCUS_CYCLE_COMBINED_FALLBACK",c,{attemptID=a.id,reason="restore_not_observed"})
        else
            c.state="blocked";c.blockedTarget=actual;c.paused="恢复结果不匹配，请手动选回原目标"
        end
    elseif a.action=="focus" then
        if not equal(actual,a.beforeTarget) then finish(c,"aborted","target_changed_during_focus");return end
        c.committed=focus.exists and focus.guid==c.goalGUID
        beginRestore(c,c.committed and "focus_set" or "focus_failed")
    else
        c.restoreSteps=c.restoreSteps+1
        if equal(actual,c.originalTarget) then c.ownedTarget=actual
        elseif not equal(actual,a.beforeTarget) then
            c.paused="恢复结果不匹配，请手动选回原目标";c.state="blocked";c.blockedTarget=actual
        end
    end
    if not idle() then c.paused="战斗中" end
    log("FOCUS_CYCLE_POST",c,{attemptID=a.id,action=a.action,restoreAction=a.restoreAction,
        combined=a.action=="focus_restore",calls=a.calls})
    if c.state=="restore" and restored(c) then
        -- Completion is based on actual focus and target, never step counts.
    else render() end
    if C_Timer and type(C_Timer.After)=="function" then
        C_Timer.After(.1,function() log("FOCUS_CYCLE_READBACK",c,{attemptID=a.id,action=a.action,
            restoreAction=a.restoreAction,combined=a.action=="focus_restore"}) end)
    end
end
function F.OnEvent(event)
    if event=="PLAYER_REGEN_ENABLED" then
        if F.deferredRow then setRowFlag(F.deferredRow,nil);F.deferredRow=nil end
        if F.session and F.session.paused=="战斗中" then F.session.paused=nil end
        render()
    end
    local c=F.session
    if not c then return end
    if event=="PLAYER_REGEN_DISABLED" then c.paused="战斗中";log("FOCUS_CYCLE_PAUSED",c);return end
    if event=="PLAYER_LOGOUT" or event=="PLAYER_LEAVING_WORLD" then finish(c,"aborted","world_left");return end
    if F.current then return end
    if event=="PLAYER_TARGET_CHANGED" and not equal(state("target"),c.ownedTarget) then
        if (c.state=="restore" or c.state=="blocked") and restored(c) then return end
        if c.state=="blocked" and equal(state("target"),c.blockedTarget) then return end
        finish(c,"aborted","manual_target_change")
    elseif event=="PLAYER_FOCUS_CHANGED" then
        local expected=c.committed and {exists=true,guid=c.goalGUID} or c.oldFocus
        if not equal(state("focus"),expected) then finish(c,"aborted","manual_focus_change") end
    end
end
function F.Command(argument)
    local c=F.session
    local command=NS.Text(argument):lower()
    if command=="staged" or command=="combined" then
        if c then say("请完成或停止当前流程后，再切换操作模式。");return false end
        F.combineFocusRestore=command=="combined"
        say(F.combineFocusRestore and "已启用焦点与首步恢复合并。" or "已切回分步确认焦点与恢复。")
        return true
    elseif command=="stop" then if c then finish(c,"aborted","user_stop") else say("没有进行中的焦点流程。") end
    elseif command=="restore" and c then
        -- Explicit recovery may resume from this exact failed-action result;
        -- unrelated later target choices are never silently adopted.
        if c.blockedTarget and equal(state("target"),c.blockedTarget) then
            c.ownedTarget=c.blockedTarget;c.blockedTarget=nil
        end
        c.cancelled=true;c.restoreSteps=0;beginRestore(c,"cancelled");render()
        say("已准备恢复原目标；请右键中央按钮，恢复动作需要真实点击。")
    else
        say(c and ("焦点流程："..c.name.."，"..(F.RowStatus(c.row) or c.state).."；右键中央按钮继续。")
            or "没有进行中的焦点流程。")
    end
end
