local _, NS = ...
-- Temporary, opt-in hardware-click comparison. Target/cycle modes start from
-- an empty target. The two-click cycle control only advances its own recorded
-- target. No cast, saved macro, binding or automatic focus is performed.
local P={active=false,serial=0}
NS.FocusAPIProbe=P
local modes={native=true,guid=true,macro=true,target=true,cycle=true,cyclecontrol=true}
local function cycling(mode) return mode=="cycle" or mode=="cyclecontrol" end
local function publicString(v)
    return NS.Public(v) and type(v)=="string" and v~="" and v or nil
end
local function guid(v)
    v=publicString(v)
    return v and #v<=128 and v:match("^[%w%-]+$") and v or nil
end
local function scalar(v)
    if not NS.Public(v) then return "[restricted]" end
    if v==nil then return "[nil]" end
    if type(v)=="string" or type(v)=="boolean" or NS.Number(v) then return v end
    return "[unsupported]"
end
local function read(fn,...) return NS.Read(fn,...) end
local function idle() return read(InCombatLockdown)==false end
local function record(kind,fields)
    if NS.Diagnostics and type(NS.Diagnostics.Record)=="function" then
        pcall(NS.Diagnostics.Record,kind,fields)
    end
end
local function say(message) if NS.Print then NS.Print(message) end end
local function emptyCursor()
    if read(SpellIsTargeting)~=false then return false,"spell_targeting_or_unknown" end
    if read(CursorHasItem)~=false then return false,"cursor_item_or_unknown" end
    return true
end
local function valid(c)
    if not idle() then return false,"combat_or_unknown" end
    if c and c.mode=="cyclecontrol" and c.step=="second" then
        -- Selecting the control target can legitimately rebind/sort the enemy
        -- tiles. This click depends only on the target owned by the first click.
        local allowed,reason=emptyCursor()
        if not allowed then return false,reason end
        if not guid(c.controlGUID) or read(UnitExists,"target")~=true
            or guid(read(UnitGUID,"target"))~=c.controlGUID then return false,"control_target_changed" end
        return true,"ready"
    end
    if not c or not NS.UI or not NS.UI.enemy or NS.UI.enemy.tiles[c.index]~=c.row
        or read(c.row.IsVisible,c.row)~=true then return false,"row_unavailable" end
    if not NS.Public(c.row.unit) or not NS.Public(c.row.expectedGUID)
        or c.row.unit~=c.unit or c.row.expectedGUID~=c.guid then return false,"binding_changed" end
    if read(UnitExists,c.unit)~=true or guid(read(UnitGUID,c.unit))~=c.guid then return false,"identity_changed" end
    if read(UnitIsPlayer,c.unit)~=false or read(UnitIsDeadOrGhost,c.unit)~=false
        or read(UnitCanAttack,"player",c.unit)~=true then return false,"not_living_enemy_npc" end
    if c.mode=="target" or cycling(c.mode) then
        if c.mode=="target" and not c.unit:match("^nameplate%d+$") then return false,"target_requires_nameplate" end
        -- Native type=target dispatches to SpellTargetUnit/DropItemOnUnit when
        -- the cursor carries a pending spell/item. This probe permits neither.
        local allowed,reason=emptyCursor()
        if not allowed then return false,reason end
        if read(UnitExists,"target")~=false or read(UnitGUID,"target")~=nil then
            return false,"target_not_empty_or_unknown"
        end
    end
    return true,"ready"
end
local function configure(button,c,allowed)
    button:SetAttribute("unit",nil)
    button:SetAttribute("*unit2",nil)
    button:SetAttribute("*type2","macro")
    button:SetAttribute("*macrotext2","/stopmacro")
    if not allowed then return end
    if cycling(c.mode) then
        local command="/stopmacro [combat]\n/targetenemy"
        if c.mode=="cycle" then command=command.."\n/targetenemy" end
        if c.mode=="cycle" or c.step=="second" then command=command.."\n/cleartarget" end
        button:SetAttribute("*macrotext2",command)
    elseif c.mode=="macro" then
        button:SetAttribute("*macrotext2","/stopmacro [combat]\n/focus [@"..c.guid.."]")
    else
        button:SetAttribute("*macrotext2",nil)
        button:SetAttribute("*unit2",(c.mode=="native" or c.mode=="target") and c.unit or c.guid)
        button:SetAttribute("*type2",c.mode=="target" and "target" or "focus")
    end
end
local function observation(kind,a)
    local focus,target=read(UnitGUID,"focus"),read(UnitGUID,"target")
    local targetExists=read(UnitExists,"target")
    local focusExists=read(UnitExists,"focus")
    local fields={attemptID=a.id,mode=a.mode,unit=a.unit,expectedGUID=a.guid,
        liveGUID=scalar(read(UnitGUID,a.unit)),beforeTargetGUID=scalar(a.beforeTarget),
        beforeTargetExists=scalar(a.beforeTargetExists),beforeFocusGUID=scalar(a.beforeFocus),
        beforeFocusExists=scalar(a.beforeFocusExists),
        afterTargetGUID=scalar(target),afterFocusGUID=scalar(focus),afterTargetExists=scalar(targetExists),
        afterFocusExists=scalar(focusExists),targetMatchesExpected=targetExists==true and guid(target)==a.guid,
        rawGUIDExists=scalar(read(UnitExists,a.guid)),combat=scalar(read(InCombatLockdown)),
        reason=a.reason,prepared=a.prepared,alreadyFocused=guid(a.beforeFocus)==a.guid,
        focusMatchesExpected=guid(focus)==a.guid,
        targetUnchanged=NS.Public(target) and NS.Public(a.beforeTarget)
            and type(targetExists)=="boolean" and type(a.beforeTargetExists)=="boolean"
            and targetExists==a.beforeTargetExists and target==a.beforeTarget
            and (targetExists and guid(target)~=nil and guid(a.beforeTarget)~=nil
                or not targetExists and target==nil and a.beforeTarget==nil),
        focusUnchanged=type(focusExists)=="boolean" and type(a.beforeFocusExists)=="boolean"
            and focusExists==a.beforeFocusExists and focus==a.beforeFocus
            and (focusExists and guid(focus)~=nil and guid(a.beforeFocus)~=nil
                or not focusExists and focus==nil and a.beforeFocus==nil)}
    if cycling(a.mode) then
        fields.phase=a.phase
        fields.cycleDispatchCount=a.cycleDispatchCount or 0
        local samples=a.cycleSamples or {}
        fields.cycleAdvanced=a.mode=="cycle" and #samples==2
            and guid(samples[1])~=nil and guid(samples[2])~=nil and samples[1]~=samples[2] or false
        fields.controlAdvanced=a.mode=="cyclecontrol" and a.phase=="second"
            and #samples==1 and guid(a.controlGUID)~=nil and guid(samples[1])~=nil
            and a.controlGUID~=samples[1] or false
        fields.controlGUID=scalar(a.controlGUID)
    end
    -- Matching before/after focus alone cannot prove a dispatched action.
    local beforeFocusKnown=a.beforeFocusExists==false and a.beforeFocus==nil
        or a.beforeFocusExists==true and guid(a.beforeFocus)~=nil
    fields.focusChangedToExpected=a.prepared and beforeFocusKnown
        and guid(a.beforeFocus)~=a.guid and guid(focus)==a.guid
    record(kind,fields)
end
local COMBAT_GUARD=[[
    if SecureCmdOptionParse("[combat] blocked") then
        self:SetAttribute("*unit2",nil)
        self:SetAttribute("*type2","macro")
        self:SetAttribute("*macrotext2","/stopmacro")
    end
]]
-- Read-only evidence from the restricted environment immediately before the
-- native OnClick. Only diagnostic attributes are written. Unit values were
-- prepared locally and revalidated in PreClick; no action attributes change.
local SECURE_CLICK_OBSERVATION=[[
    self:SetAttribute("probe-secure-complete",false)
    self:SetAttribute("probe-secure-unit",nil)
    self:SetAttribute("probe-secure-exists",nil)
    self:SetAttribute("probe-secure-condition",nil)
    local actual = self:GetAttribute("*unit2")
    self:SetAttribute("probe-secure-unit",actual)
    if type(actual)=="string" then
        self:SetAttribute("probe-secure-exists",UnitExists(actual))
        self:SetAttribute("probe-secure-condition",SecureCmdOptionParse("[@"..actual..",exists] exists"))
    end
    self:SetAttribute("probe-secure-complete",true)
]]
local function dispatchObservation(api,unit)
    local a=P.currentAttempt
    if not P.active or not a then return end
    if api=="TargetNearestEnemy" then
        if not cycling(a.mode) or not a.prepared then return end
        a.cycleDispatchCount=(a.cycleDispatchCount or 0)+1
        a.cycleSamples=a.cycleSamples or {}
        local current=read(UnitGUID,"target")
        local exists=read(UnitExists,"target")
        -- Preserve ordinal positions even if identity is missing/restricted.
        a.cycleSamples[a.cycleDispatchCount]=exists==true and guid(current) or false
        record("FOCUS_API_PROBE_CYCLE_STEP",{attemptID=a.id,mode=a.mode,phase=a.phase,
            ordinal=a.cycleDispatchCount,reverse=scalar(unit),targetGUID=scalar(current),
            targetExists=scalar(exists),expectedGUID=a.guid,controlGUID=scalar(a.controlGUID),
            targetMatchesExpected=exists==true and guid(current)==a.guid,
            focusGUID=scalar(read(UnitGUID,"focus")),combat=scalar(read(InCombatLockdown))})
        return
    end
    record("FOCUS_API_PROBE_DISPATCH",{attemptID=a.id,mode=a.mode,api=api,
        actualUnit=scalar(unit),expectedGUID=a.guid,prepared=a.prepared,
        actualUnitExists=scalar(publicString(unit) and read(UnitExists,unit)),
        actualUnitGUID=scalar(publicString(unit) and read(UnitGUID,unit)),
        afterTargetGUID=scalar(read(UnitGUID,"target")),afterFocusGUID=scalar(read(UnitGUID,"focus"))})
end
local function installDispatchHooks()
    P.dispatchHooks={}
    for _,name in ipairs({"TargetUnit","FocusUnit","TargetNearestEnemy"}) do
        local api=name
        local installed=false
        if type(hooksecurefunc)=="function" and type(_G[api])=="function" then
            installed=pcall(hooksecurefunc,api,function(unit)
                pcall(dispatchObservation,api,unit)
            end)
        end
        P.dispatchHooks[api]=installed
    end
    record("FOCUS_API_PROBE_HOOKS",{TargetUnit=P.dispatchHooks.TargetUnit,FocusUnit=P.dispatchHooks.FocusUnit,
        TargetNearestEnemy=P.dispatchHooks.TargetNearestEnemy})
end
local function clickObservation(self,button,down,isKeyPress,isSecureAction)
    local a=P.currentAttempt
    if not P.active or not a then return end
    local unit=read(SecureButton_GetModifiedUnit,self,button)
    local action=read(SecureButton_GetModifiedAttribute,self,"type",button)
    record("FOCUS_API_PROBE_ONCLICK",{attemptID=a.id,mode=a.mode,expectedGUID=a.guid,
        inputButton=scalar(button),down=scalar(down),isKeyPress=scalar(isKeyPress),isSecureAction=scalar(isSecureAction),
        resolvedUnit=scalar(unit),resolvedType=scalar(action),
        normalUnitExists=scalar(publicString(unit) and read(UnitExists,unit)),
        secureUnit=scalar(read(self.GetAttribute,self,"probe-secure-unit")),
        secureUnitExists=scalar(read(self.GetAttribute,self,"probe-secure-exists")),
        secureExistsCondition=scalar(read(self.GetAttribute,self,"probe-secure-condition")),
        secureObservationComplete=scalar(read(self.GetAttribute,self,"probe-secure-complete")),
        targetHookInstalled=P.dispatchHooks and P.dispatchHooks.TargetUnit or false,
        focusHookInstalled=P.dispatchHooks and P.dispatchHooks.FocusUnit or false})
end
local function build()
    if P.button then return P.button end
    if type(SecureHandlerWrapScript)~="function" or type(RegisterStateDriver)~="function"
        or type(UnregisterStateDriver)~="function" then return nil end
    P.setupStage="create"
    local b=CreateFrame("Button","MyForeverFocusAPIProbe",UIParent,"SecureActionButtonTemplate,SecureHandlerStateTemplate,BackdropTemplate")
    P.partialButton=b
    P.setupStage="style"
    b:SetSize(200,40);b:SetPoint("CENTER",UIParent,"CENTER",0,180)
    b:SetFrameStrata("DIALOG");b:EnableMouse(true);b:RegisterForClicks("RightButtonUp")
    b:SetAttribute("useOnKeyDown",false)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    b:SetBackdropColor(.04,.10,.22,.97);b:SetBackdropBorderColor(.4,.7,1,1)
    b.label=b:CreateFontString(nil,"OVERLAY","GameFontNormal")
    b.label:SetPoint("CENTER");b.label:SetWidth(188)
    configure(b,nil,false);b:Hide()
    P.setupStage="wrap"
    SecureHandlerWrapScript(b,"PreClick",b,COMBAT_GUARD)
    SecureHandlerWrapScript(b,"OnClick",b,SECURE_CLICK_OBSERVATION)
    P.setupStage="hook"
    installDispatchHooks()
    P.setupStage="scripts"
    b:HookScript("PreClick",function(self,button,down)
        self.probeAttempt=nil;P.currentAttempt=nil
        if button~="RightButton" or down or not P.active then return end
        local c=P.capture
        local allowed,reason=valid(c)
        if idle() then configure(self,c,allowed) end
        P.serial=P.serial+1
        local a={id=P.serial,mode=c.mode,unit=c.unit,guid=c.guid,reason=reason,prepared=allowed,
            phase=c.mode=="cycle" and "cycle" or c.step,controlGUID=c.controlGUID,
            beforeTarget=read(UnitGUID,"target"),beforeTargetExists=read(UnitExists,"target"),
            beforeFocus=read(UnitGUID,"focus"),beforeFocusExists=read(UnitExists,"focus")}
        self.probeAttempt=a;P.currentAttempt=a;observation("FOCUS_API_PROBE_PRE",a)
        -- If native handling aborts before PostClick, do not attribute later
        -- unrelated API calls to this attempt.
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(0,function()
                if P.currentAttempt==a then P.currentAttempt=nil end
                if self.probeAttempt==a then self.probeAttempt=nil end
            end)
        end
    end)
    b:HookScript("OnClick",function(...) pcall(clickObservation,...) end)
    b:HookScript("PostClick",function(self,button,down)
        local a=self.probeAttempt;self.probeAttempt=nil;P.currentAttempt=nil
        if button~="RightButton" or down or not a then return end
        observation("FOCUS_API_PROBE_POST",a)
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(.1,function() observation("FOCUS_API_PROBE_READBACK",a) end)
        end
        local c=P.capture
        if a.prepared and c and c.mode=="cyclecontrol" and idle() then
            if a.phase=="first" then
                local selected=guid(read(UnitGUID,"target"))
                -- Without an observed selection, do not arm the second step.
                if a.cycleDispatchCount==1 and a.cycleSamples and selected==a.cycleSamples[1]
                    and read(UnitExists,"target")==true and selected then
                    c.controlGUID=selected;c.step="second"
                    self.label:SetText("Tab 对照 2/2：右键\n再选一次，然后清空目标")
                    say("Tab 对照已选中第一只；再右键中央按钮，记录第二只并清空测试目标。")
                else
                    c.step="failed";P.active=false
                    UnregisterStateDriver(self,"visibility")
                    configure(self,nil,false)
                    self:Hide()
                    say("Tab 对照第一步未确认，测试已关闭；请取消测试目标后重新准备。")
                end
            elseif a.phase=="second" then
                c.step="done";P.active=false
                UnregisterStateDriver(self,"visibility");configure(self,nil,false);self:Hide()
                say("Tab 两次独立点击对照已记录；请 /reload 保存日志。")
            end
        end
    end)
    P.button=b;P.partialButton=nil
    return b
end

local reasons={
    invalid_command="命令格式有误。用 /mytargets focusprobe cycle 1 或 cyclecontrol 1。",
    combat_or_unknown="当前在战斗中，或无法确认已脱战。",
    invalid_row="指定的敌方格子为空或身份不可读。请打开敌方面板，靠近活怪，确认第1格有名字。",
    row_unavailable="敌方格子不可见。请先打开敌方面板。",
    binding_changed="格子的单位已换位，请保持位置不动后重新输入命令。",
    identity_changed="怪物身份已变化，请等名单刷新后重试。",
    not_living_enemy_npc="指定格子不是可攻击的活怪。",
    target_not_empty_or_unknown="当前目标未清空。请按 Esc 取消当前目标后重新输入命令。",
    spell_targeting_or_unknown="存在待施法光标，或无法读取其状态。请取消待施法状态后重试。",
    cursor_item_or_unknown="鼠标携带物品，或无法读取其状态。请放回物品后重试。",
    target_requires_nameplate="这个接口测试需要姓名板单位。",
    secure_api_unavailable="当前客户端缺少测试所需的安全框体接口。",
    cycle_hook_unavailable="无法安装 Tab 选择记录器，测试没有启动。",
    diagnostics_start_failed="启动测试日志时发生错误，测试没有启动。",
    setup_error="创建或显示测试按钮时发生错误，请 /reload 后重试。",
    reload_required="上次创建按钮时出错，需要先 /reload。",
}
local function disarm()
    P.active=false;P.capture=nil;P.currentAttempt=nil
    if not idle() then return end
    local b=P.button or P.partialButton
    if b then
        pcall(function() UnregisterStateDriver(b,"visibility") end)
        pcall(configure,b,nil,false)
        pcall(b.Hide,b)
    end
end
function P.Command(argument)
    local mode,index=NS.Text(argument):match("^%s*(%S+)%s*(%d*)%s*$")
    if mode=="status" then
        say(P.active and "焦点接口测试已准备："..P.capture.mode or "焦点接口测试未开启。")
        return P.active
    end
    if mode=="off" then
        if not idle() then say("焦点接口测试只在脱战时准备或关闭。");return false,"combat_or_unknown" end
        disarm()
        say("焦点接口测试已关闭。");return true
    end
    index=tonumber(index)
    P.requestSerial=(P.requestSerial or 0)+1
    local request=P.requestSerial
    disarm()
    -- Log the command before row/target validation or any frame construction.
    -- Otherwise a refused preparation leaves no evidence of why no UI appeared.
    local d=NS.Diagnostics
    local loggingOK,loggingError=true,nil
    if d and type(d.Start)=="function" then loggingOK,loggingError=pcall(d.Start) end
    P.setupStage="capture"
    record("FOCUS_API_PROBE_COMMAND",{requestID=request,mode=mode or "[none]",rowIndex=index or 0,
        version=NS.VERSION,combat=scalar(read(InCombatLockdown)),
        targetExists=scalar(read(UnitExists,"target")),targetGUID=scalar(read(UnitGUID,"target"))})
    local function reject(reason,err)
        disarm()
        local errorLine=err and (publicString(err) and err:match("^[^\r\n]*") or "[unreadable error]") or nil
        record("FOCUS_API_PROBE_REJECT",{requestID=request,mode=mode or "[none]",rowIndex=index or 0,
            version=NS.VERSION,reason=reason,stage=P.setupStage,error=errorLine})
        say("测试未启动："..(reasons[reason] or reason)..(errorLine and " 错误："..NS.Text(errorLine) or ""))
        return false,reason
    end
    if not loggingOK then return reject("diagnostics_start_failed",loggingError) end
    if not idle() then return reject("combat_or_unknown") end
    if not modes[mode] or not index or index<1 or index>20 then return reject("invalid_command") end
    if P.setupFailed then return reject("reload_required") end
    local row=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles[index]
    local unit=row and publicString(row.unit)
    local expected=row and guid(row.expectedGUID)
    if not unit or not NS.ValidToken(unit) or not expected then return reject("invalid_row") end
    local c={row=row,index=index,unit=unit,guid=expected,mode=mode,step=mode=="cyclecontrol" and "first" or nil}
    P.setupStage="validate"
    local allowed,reason=valid(c)
    if not allowed then return reject(reason) end
    P.setupStage="build"
    local built,b=pcall(build)
    if not built then P.setupFailed=true;return reject("setup_error",b) end
    if not b then return reject("secure_api_unavailable") end
    if cycling(mode) then
        if not P.dispatchHooks or not P.dispatchHooks.TargetNearestEnemy then return reject("cycle_hook_unavailable") end
    end
    local shown,showError=pcall(function()
        P.setupStage="configure"
        configure(b,c,true)
        b.label:SetText("右键测试 "..mode.."\n"..NS.Text(read(UnitName,unit)))
        if mode=="cycle" then b.label:SetText("Tab 双命令测试：右键\n只记录，结束清空目标")
        elseif mode=="cyclecontrol" then b.label:SetText("Tab 对照 1/2：右键\n暂留第一只；再点一次清空") end
        P.setupStage="driver"
        RegisterStateDriver(b,"visibility","[combat] hide; show")
        P.setupStage="show"
        b:Show()
    end)
    if not shown then P.setupFailed=true;return reject("setup_error",showError) end
    P.capture=c;P.active=true;P.setupStage="ready"
    record("FOCUS_API_PROBE_READY",{requestID=request,version=NS.VERSION,stage=P.setupStage,
        shown=scalar(read(b.IsShown,b)),visible=scalar(read(b.IsVisible,b)),mode=mode,unit=unit,expectedGUID=expected,
        rawGUIDExists=scalar(read(UnitExists,expected)),rowIndex=index})
    if cycling(mode) then
        say("已准备 "..mode.."；右键中央按钮。只检查Tab循环，不设置焦点或施法。")
    else say("已准备焦点接口 "..mode.."；右键中央测试按钮。准备成功不代表焦点成功。") end
    return true
end
