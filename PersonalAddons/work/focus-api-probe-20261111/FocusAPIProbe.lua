local _, NS = ...
-- Temporary, opt-in hardware-click comparison. This module never selects a
-- target, casts, creates a macro, or changes a binding. Remove after diagnosis.
local P={active=false,serial=0}
NS.FocusAPIProbe=P
local modes={native=true,guid=true,macro=true}
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
local function valid(c)
    if not idle() then return false,"combat_or_unknown" end
    if not c or not NS.UI or not NS.UI.enemy or NS.UI.enemy.tiles[c.index]~=c.row
        or read(c.row.IsVisible,c.row)~=true then return false,"row_unavailable" end
    if not NS.Public(c.row.unit) or not NS.Public(c.row.expectedGUID)
        or c.row.unit~=c.unit or c.row.expectedGUID~=c.guid then return false,"binding_changed" end
    if read(UnitExists,c.unit)~=true or guid(read(UnitGUID,c.unit))~=c.guid then return false,"identity_changed" end
    if read(UnitIsPlayer,c.unit)~=false or read(UnitIsDeadOrGhost,c.unit)~=false
        or read(UnitCanAttack,"player",c.unit)~=true then return false,"not_living_enemy_npc" end
    return true,"ready"
end
local function configure(button,c,allowed)
    button:SetAttribute("unit",nil)
    button:SetAttribute("*unit2",nil)
    button:SetAttribute("*type2","macro")
    button:SetAttribute("*macrotext2","/stopmacro")
    if not allowed then return end
    if c.mode=="macro" then
        button:SetAttribute("*macrotext2","/stopmacro [combat]\n/focus [@"..c.guid.."]")
    else
        button:SetAttribute("*macrotext2",nil)
        button:SetAttribute("*unit2",c.mode=="native" and c.unit or c.guid)
        button:SetAttribute("*type2","focus")
    end
end
local function observation(kind,a)
    local focus,target=read(UnitGUID,"focus"),read(UnitGUID,"target")
    local targetExists=read(UnitExists,"target")
    local fields={attemptID=a.id,mode=a.mode,unit=a.unit,expectedGUID=a.guid,
        liveGUID=scalar(read(UnitGUID,a.unit)),beforeTargetGUID=scalar(a.beforeTarget),
        beforeTargetExists=scalar(a.beforeTargetExists),beforeFocusGUID=scalar(a.beforeFocus),
        beforeFocusExists=scalar(a.beforeFocusExists),
        afterTargetGUID=scalar(target),afterFocusGUID=scalar(focus),afterTargetExists=scalar(targetExists),
        rawGUIDExists=scalar(read(UnitExists,a.guid)),combat=scalar(read(InCombatLockdown)),
        reason=a.reason,prepared=a.prepared,alreadyFocused=guid(a.beforeFocus)==a.guid,
        focusMatchesExpected=guid(focus)==a.guid,
        targetUnchanged=NS.Public(target) and NS.Public(a.beforeTarget)
            and type(targetExists)=="boolean" and type(a.beforeTargetExists)=="boolean"
            and targetExists==a.beforeTargetExists and target==a.beforeTarget
            and (targetExists and guid(target)~=nil and guid(a.beforeTarget)~=nil
                or not targetExists and target==nil and a.beforeTarget==nil)}
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
local function build()
    if P.button then return P.button end
    if type(SecureHandlerWrapScript)~="function" or type(RegisterStateDriver)~="function"
        or type(UnregisterStateDriver)~="function" then return nil end
    local b=CreateFrame("Button","MyForeverFocusAPIProbe",UIParent,"SecureActionButtonTemplate,SecureHandlerStateTemplate,BackdropTemplate")
    b:SetSize(200,40);b:SetPoint("CENTER",UIParent,"CENTER",0,180)
    b:SetFrameStrata("DIALOG");b:EnableMouse(true);b:RegisterForClicks("RightButtonUp")
    b:SetAttribute("useOnKeyDown",false)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    b:SetBackdropColor(.04,.10,.22,.97);b:SetBackdropBorderColor(.4,.7,1,1)
    b.label=b:CreateFontString(nil,"OVERLAY","GameFontNormal")
    b.label:SetPoint("CENTER");b.label:SetWidth(188)
    configure(b,nil,false);b:Hide()
    SecureHandlerWrapScript(b,"PreClick",b,COMBAT_GUARD)
    b:HookScript("PreClick",function(self,button,down)
        self.probeAttempt=nil
        if button~="RightButton" or down or not P.active then return end
        local c=P.capture
        local allowed,reason=valid(c)
        if idle() then configure(self,c,allowed) end
        P.serial=P.serial+1
        local a={id=P.serial,mode=c.mode,unit=c.unit,guid=c.guid,reason=reason,prepared=allowed,
            beforeTarget=read(UnitGUID,"target"),beforeTargetExists=read(UnitExists,"target"),
            beforeFocus=read(UnitGUID,"focus"),beforeFocusExists=read(UnitExists,"focus")}
        self.probeAttempt=a;observation("FOCUS_API_PROBE_PRE",a)
    end)
    b:HookScript("PostClick",function(self,button,down)
        local a=self.probeAttempt;self.probeAttempt=nil
        if button~="RightButton" or down or not a then return end
        observation("FOCUS_API_PROBE_POST",a)
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(.1,function() observation("FOCUS_API_PROBE_READBACK",a) end)
        end
    end)
    P.button=b
    return b
end
function P.Command(argument)
    local mode,index=NS.Text(argument):match("^%s*(%S+)%s*(%d*)%s*$")
    if mode=="status" then
        say(P.active and "焦点接口测试已准备："..P.capture.mode or "焦点接口测试未开启。")
        return P.active
    end
    if not idle() then say("焦点接口测试只在脱战时准备或关闭。");return false,"combat_or_unknown" end
    if mode=="off" then
        P.active=false;P.capture=nil
        if P.button then UnregisterStateDriver(P.button,"visibility");configure(P.button,nil,false);P.button:Hide() end
        say("焦点接口测试已关闭。");return true
    end
    index=tonumber(index)
    if not modes[mode] or not index or index<1 or index>20 then return false,"invalid_command" end
    -- A failed re-prepare must not leave an earlier test armed.
    P.active=false;P.capture=nil
    if P.button then UnregisterStateDriver(P.button,"visibility");configure(P.button,nil,false);P.button:Hide() end
    local row=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles[index]
    local unit=row and publicString(row.unit)
    local expected=row and guid(row.expectedGUID)
    if not unit or not NS.ValidToken(unit) or not expected then return false,"invalid_row" end
    local c={row=row,index=index,unit=unit,guid=expected,mode=mode}
    local allowed,reason=valid(c)
    if not allowed then say("焦点接口测试未准备："..reason);return false,reason end
    local b=build()
    if not b then return false,"secure_api_unavailable" end
    P.capture=c;P.active=true;configure(b,c,true)
    b.label:SetText("右键测试 "..mode.."\n"..NS.Text(read(UnitName,unit)))
    RegisterStateDriver(b,"visibility","[combat] hide; show")
    b:Show()
    record("FOCUS_API_PROBE_READY",{mode=mode,unit=unit,expectedGUID=expected,
        rawGUIDExists=scalar(read(UnitExists,expected)),rowIndex=index})
    say("已准备焦点接口 "..mode.."；右键中央测试按钮。准备成功不代表焦点成功。")
    return true
end
