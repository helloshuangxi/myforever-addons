local _, NS = ...
-- The production policy uses the player's own @mouseover macros. Do not even
-- create the historical experiment's event frame or secure binding owners.
if not NS.Public(NS.NativeMacroOnly) or NS.NativeMacroOnly~=false then
    local Probe={active=false,captures={},blocks={},proxies={},prepared={}}
    NS.GUIDProbe=Probe
    function Probe.Active() return false end
    function Probe.GetAttempt() return nil end
    function Probe.Resolve() return nil end
    function Probe.Capture() return false end
    function Probe.SetMode() return false end
    function Probe.UpdateLabels() end
    function Probe.Prepare() return false end
    function Probe.Stop() return true end
    function Probe.Command()
        if NS.Print then NS.Print("GUID施法实验已停用，请使用自己的 @mouseover 宏。") end
        return false
    end
    return
end
-- Isolated, user-operated GUID experiment. No name targeting, automatic cast,
-- saved key binding or normal target-grid unit button participates in the probe.
local Probe={captures={},blocks={},proxies={},prepared={},feedback={},statusFloor={},mode="converted",active=false}
NS.GUIDProbe=Probe

local function idle()
    if type(InCombatLockdown)~="function" then return false end
    local ok,value=pcall(InCombatLockdown)
    return ok and NS.Public(value) and not value
end

local function plain(value)
    if not NS.Public(value) or type(value)~="string" or value==""
        or value:find("[%z\1-\31\127%[%]|;\\]")
        or value:match("^%s") or value:match("%s$") then return nil end
    return value
end

local function read(fn,...)
    if type(fn)~="function" then return nil,"unavailable" end
    local ok,value=pcall(fn,...)
    if not ok then return nil,"api_error" end
    if not NS.Public(value) then return nil,"restricted" end
    return value,"public"
end

local function log(method,...)
    local arguments={...}
    local ok,value=pcall(function()
        local target=NS.GUIDProbeLog
        if type(target)~="table" or type(target[method])~="function" then return nil end
        return target[method](unpack(arguments))
    end)
    if ok and NS.Public(value) then return value end
end

local function say(message) if NS.Print then pcall(NS.Print,message) end end
function Probe.Active() return Probe.active end
function Probe.GetAttempt() return Probe.lastAttempt end

local function liveToken(guid)
    local tokens={"target","focus","mouseover","targettarget","focustarget"}
    for i=1,4 do tokens[#tokens+1]="party"..i.."target" end
    for i=1,40 do tokens[#tokens+1]="raid"..i.."target" end
    for i=1,8 do tokens[#tokens+1]="boss"..i end
    for i=1,5 do tokens[#tokens+1]="arena"..i end
    local plates=NS.Read(NS.NameplateTokens)
    if type(plates)=="table" then
        for _,unit in ipairs(plates) do if plain(unit) then tokens[#tokens+1]=unit end end
    end
    for _,unit in ipairs(tokens) do
        local candidate=NS.Read(UnitGUID,unit)
        if type(candidate)=="string" and candidate==guid then return unit end
    end
end

function Probe.Resolve(record)
    if type(record)~="table" or not plain(record.guid) then return nil end
    local converted,reason=read(UnitTokenFromGUID,record.guid)
    local mapped=plain(converted)
    local roundtrip=mapped and NS.Read(UnitGUID,mapped)
    local readable=mapped~=nil and type(roundtrip)=="string" and roundtrip==record.guid
    local found=liveToken(record.guid)
    local rawExists,rawExistsReason=read(UnitExists,record.guid)
    return {converted=readable and mapped or nil,readableMap=readable,
        mapReason=readable and "roundtrip" or (reason~="public" and reason or "unmapped_or_mismatch"),
        liveToken=found,liveGUID=found and NS.Read(UnitGUID,found),
        liveRange=found and NS.Read(C_Spell and C_Spell.IsSpellInRange,679,found),
        rawGUIDReadback=NS.Read(UnitGUID,record.guid),rawExists=rawExists,rawExistsReason=rawExistsReason}
end

local function exactSpell()
    local name=plain(NS.Read(C_Spell and C_Spell.GetSpellName,679))
    if not name then return nil end
    local rank,reason=read(C_Spell and C_Spell.GetSpellSubtext or GetSpellSubtext,679)
    if reason~="public" and reason~="unavailable" then return nil end
    if rank~=nil and rank~="" then
        rank=plain(rank)
        if not rank then return nil end
        name=name.."("..rank..")"
    end
    if NS.Read(C_Spell and C_Spell.DoesSpellExist,name)~=true then return nil end
    local info=NS.Read(C_Spell and C_Spell.GetSpellInfo,name)
    if type(info)~="table" or NS.Read(function() return info.spellID end)~=679 then return nil end
    return name
end

function Probe.Capture(slot)
    if not idle() or not Probe.active or (slot~="A" and slot~="B") then return false end
    local guid,name=NS.Read(UnitGUID,"target"),NS.Read(UnitName,"target")
    if not plain(guid) or not plain(name) or NS.Read(UnitExists,"target")~=true
        or NS.Read(UnitIsDeadOrGhost,"target")==true or NS.Read(UnitIsPlayer,"target")~=false
        or NS.Read(UnitCanAttack,"player","target")~=true then
        say("请在游戏中选中要记录的敌方怪物，再记 A／B。")
        return false
    end
    local other=Probe.captures[slot=="A" and "B" or "A"]
    if slot=="B" and (not other or other.name~=name or other.guid==guid) then
        say("B 必须与 A 同名、GUID 不同；请在游戏世界中手动选择另一只。")
        return false
    end
    if slot=="A" and other and (other.name~=name or other.guid==guid) then Probe.captures.B=nil end
    local record={guid=guid,name=name,capturedUnit="target",time=NS.Read(GetTime)}
    Probe.captures[slot]=record
    log("Capture",slot,record)
    if Probe.Prepare then Probe.Prepare(true) end
    return true
end

local modes={converted=true,guid_button=true,guid_macro=true,integrated_macro=true,baseline=true}
function Probe.SetMode(mode)
    if not idle() or not Probe.active or not modes[mode] then return false end
    Probe.mode=mode
    if Probe.Prepare then Probe.Prepare(true) end
    return true
end

local ENTER=[[
    control:ClearBindings()
    if control:GetAttribute("probe-active") then
        local proxy = self:GetFrameRef("probeProxy")
        if proxy then proxy:SetAttribute("probe-armed", true) end
        control:SetAttribute("probe-hover-slot", self:GetAttribute("probe-slot"))
        control:SetBindingClick(true, "Z", self:GetAttribute("probe-proxy"), "LeftButton")
    end
]]
local LEAVE=[[
    if control:GetAttribute("probe-hover-slot") == self:GetAttribute("probe-slot") then
        control:ClearBindings()
        control:SetAttribute("probe-hover-slot", nil)
    end
]]
local PRECLICK=[[
    self:SetAttribute("type", nil)
    self:SetAttribute("probe-execute", false)
    if not control:GetAttribute("probe-active") then
        self:SetAttribute("probe-branch", "stopped")
    elseif not self:GetAttribute("probe-enabled") then
        self:SetAttribute("probe-branch", "disabled")
    elseif not self:GetAttribute("probe-armed") then
        self:SetAttribute("probe-branch", "consumed_noop")
    elseif self:GetAttribute("probe-mode") == "integrated_macro"
        and SecureCmdOptionParse("[@mouseover,harm] blocked") then
        self:SetAttribute("probe-branch", "blocked_hostile_mouseover")
    elseif self:GetAttribute("probe-mode") ~= "baseline" and self:GetAttribute("probe-mode") ~= "integrated_macro"
        and (SecureCmdOptionParse("[@target,harm] blocked") or SecureCmdOptionParse("[@mouseover,harm] blocked")) then
        self:SetAttribute("probe-branch", "blocked_hostile_fallback")
    else
        self:SetAttribute("probe-armed", false)
        self:SetAttribute("spell", 679)
        if self:GetAttribute("probe-type") == "macro" then
            self:SetAttribute("unit", nil)
        else
            self:SetAttribute("unit", self:GetAttribute("probe-unit"))
        end
        self:SetAttribute("macrotext", self:GetAttribute("probe-macro"))
        self:SetAttribute("type", self:GetAttribute("probe-type"))
        self:SetAttribute("probe-branch", "execute")
        self:SetAttribute("probe-execute", true)
    end
]]
Probe.Snippets={enter=ENTER,leave=LEAVE,preClick=PRECLICK}

local function attemptFields(proxy,button,down)
    local state=proxy.probeState
    if not state then return nil end
    local targetGUID=NS.Read(UnitGUID,"target")
    local unitArgGUID=state.unitArg and NS.Read(UnitGUID,state.unitArg)
    return {slot=state.slot,mode=state.mode,expectedGUID=state.expectedGUID,expectedName=state.expectedName,
        unitArg=state.unitArg,configuredKey="Z",spellID=679,button=button,down=down,
        branch=NS.Read(proxy.GetAttribute,proxy,"probe-branch"),execute=NS.Read(proxy.GetAttribute,proxy,"probe-execute")==true,
        currenttargetGUID=targetGUID,targetGUID=targetGUID,targetName=NS.Read(UnitName,"target"),
        nativeGUID=NS.Read(UnitGUID,"mouseover"),nativeMouseoverGUID=NS.Read(UnitGUID,"mouseover"),
        selectedMatchesExpected=type(targetGUID)=="string" and targetGUID==state.expectedGUID,
        unitArgGUID=unitArgGUID,
        convertedRoundtripAtPress=state.mode=="converted" and type(unitArgGUID)=="string" and unitArgGUID==state.expectedGUID,
        staleMapping=state.mode=="converted" and unitArgGUID~=state.expectedGUID,
        liveToken=state.liveToken,liveGUID=state.liveToken and NS.Read(UnitGUID,state.liveToken),
        liveExists=state.liveToken and NS.Read(UnitExists,state.liveToken),
        liveDead=state.liveToken and NS.Read(UnitIsDeadOrGhost,state.liveToken),
        clearsCurrentTarget=state.mode=="integrated_macro",targetExistsAfter=NS.Read(UnitExists,"target"),
        readableMap=state.readableMap,mapReason=state.mapReason,disabledReason=state.reason,
        range=state.unitArg and NS.Read(C_Spell and C_Spell.IsSpellInRange,679,state.unitArg),
        liveRange=state.liveToken and NS.Read(C_Spell and C_Spell.IsSpellInRange,679,state.liveToken),
        combat=NS.Read(InCombatLockdown),facing=NS.Read(GetPlayerFacing)}
end

local function sameConfiguration(value,state,record)
    return value and state and value.slot==state.slot and value.mode==state.mode and state.mode==Probe.mode
        and value.expectedGUID==state.expectedGUID and value.expectedGUID==(record and record.guid)
end

local function rememberInput(fields)
    local slot=fields.slot
    local state,record=Probe.prepared[slot],Probe.captures[slot]
    if not sameConfiguration(fields,state,record) then return end
    local feedback=Probe.feedback[slot]
    if not sameConfiguration(feedback,state,record) then
        feedback={slot=slot,mode=fields.mode,expectedGUID=fields.expectedGUID,inputs=0,executed=0}
        Probe.feedback[slot]=feedback
    end
    feedback.inputs=feedback.inputs+1
    if fields.execute==true then feedback.executed=feedback.executed+1 end
    feedback.last=fields
end

local function observePre(proxy,button,down)
    pcall(function()
        if NS.Public(button) and button==nil then return end
        local fields=attemptFields(proxy,button,down)
        if not fields then return end
        local attemptID=log("Attempt",fields)
        if NS.Number(attemptID) then fields.attemptID=attemptID end
        Probe.lastAttempt=fields
        proxy.lastAttempt=fields
        rememberInput(fields)
    end)
end

local function observePost(proxy,button,down)
    pcall(function()
        if NS.Public(button) and button==nil then return end
        local fields=attemptFields(proxy,button,down)
        if not fields then return end
        fields.attemptID=proxy.lastAttempt and proxy.lastAttempt.attemptID
        log("PostAttempt",fields)
        if Probe.UpdateLabels then Probe.UpdateLabels() end
    end)
end

local modeNames={converted="转换",guid_button="GUID 按钮",guid_macro="GUID 指令",integrated_macro="内部指令",baseline="目标对照"}
local disabledMessages={no_pair="先记两只同名怪 A/B",unavailable="转换接口不可用",
    api_error="转换接口读取失败",restricted="转换引用不可读",unmapped_or_mismatch="引用失效，重选转换",
    unmapped="没有可用引用",exact_rank_unavailable="无法确认测试技能等级",no_live_sample="怪物不在可读范围或已死亡"}
local function inputMessage(fields)
    if fields.branch=="blocked_hostile_fallback" then return "未执行：先选自己头像或清空敌方目标" end
    if fields.branch=="blocked_hostile_mouseover" then return "未执行：请先移入中央 A/B 测试块" end
    if fields.branch=="consumed_noop" then return "未执行：本次已用过，移出再进入" end
    if fields.branch=="stopped" then return "未执行：测试已停止" end
    if fields.branch=="disabled" then return "未执行："..(disabledMessages[fields.disabledReason] or "路线未准备") end
    if fields.execute==true and fields.branch=="execute" then return "已发起动作；施法与受术结果见下方" end
    return "未执行：未取得明确动作分支"
end

function Probe.UpdateLabels()
    if not Probe.panel then return end
    Probe.modeLabel:SetText("模式："..(modeNames[Probe.mode] or Probe.mode).." · 每次只按一次 Z，鼠标留在该块 5 秒；两次至少间隔 5 秒，再移出重进。")
    if Probe.help then
        Probe.help:SetText(Probe.mode=="integrated_macro"
            and "内部指令：Z 会停止自动攻击、清空当前目标，再尝试 GUID 施法；不会恢复旧目标。请悬停中央 A／B 按 Z。"
            or "记好 A／B 后，前三路先选自己头像，再悬停中央 A／B 按 Z；当前目标或原生悬停仍是敌人时不执行。目标对照须先选对应怪。")
    end
    for _,slot in ipairs({"A","B"}) do
        local record,state=Probe.captures[slot],Probe.prepared[slot]
        local label=slot.." · 未记录"
        if record then label=slot.." · "..record.name.."\nGUID …"..record.guid:sub(-12) end
        if state then
            label=label.."\n"..(state.enabled and "已准备" or "未准备："..(disabledMessages[state.reason] or "请重选方式或检查记录"))
        end
        local feedback=Probe.feedback[slot]
        if not sameConfiguration(feedback,state,record) then feedback=nil end
        label=label.."\n本方式按键 "..(feedback and feedback.inputs or 0).." · 已发起动作 "..(feedback and feedback.executed or 0)
        if feedback and sameConfiguration(feedback.last,state,record) then label=label.."\n"..inputMessage(feedback.last) end
        local status=log("Status",slot)
        local resultGUID=type(status)=="table" and plain(status.expectedGUID)
        local currentStatus=type(status)=="table" and record and resultGUID==record.guid
            and NS.Number(status.attemptID) and status.attemptID>(Probe.statusFloor[slot] or 0)
        if currentStatus then
            local reason=plain(status.reason)
            local observedReceiver,observedEffect=plain(status.receiver),plain(status.effect)
            local receiver=observedReceiver=="expected" and record and resultGUID==record.guid and ("匹配 "..slot)
                or observedReceiver=="other" and "观察到另一只" or "个体未证实"
            local effects={damage="伤害",miss="未命中",cast="施法事件",none="无效果记录"}
            if plain(status.targetClearReason)=="target_clear_unconfirmed" then receiver="清空目标未确认，个体未证实"
            elseif plain(status.targetClearReason)=="awaiting_clear_confirmation" then receiver="等待清空目标确认"
            elseif reason=="ambiguous_attempt_window" then receiver="间隔不足5秒"
            elseif reason=="probe_focus_not_confirmed" then receiver="鼠标已移开，个体未证实"
            elseif reason=="awaiting_effect" then receiver="等待公开受术记录"
            elseif reason=="no_public_effect" then receiver="未取得公开受术记录"
            elseif reason=="awaiting_clear_confirmation" then receiver="等待清空目标确认"
            elseif reason=="target_clear_unconfirmed" then receiver="清空目标未确认，个体未证实"
            elseif reason=="stale_or_unreadable_mapping" or record and resultGUID and resultGUID~=record.guid then
                receiver="引用已变需重新检查"
            end
            label=label.."\n"..receiver.." · "..(effects[observedEffect] or "无效果记录")
        elseif state then label=label.."\n个体未证实 · 无效果记录" end
        Probe.blocks[slot].label:SetText(label)
    end
end

function Probe.Prepare(rearm)
    if not idle() or not Probe.active or not Probe.owner then return false end
    if rearm~=false then
        Probe.feedback,Probe.statusFloor={},{}
        Probe.lastAttempt=nil
        for slot,proxy in pairs(Probe.proxies) do
            proxy.lastAttempt=nil
            local status=log("Status",slot)
            Probe.statusFloor[slot]=type(status)=="table" and NS.Number(status.attemptID) and status.attemptID or 0
        end
    end
    -- Keep an existing hover binding aimed at the same proxy while replacing
    -- its OOC configuration. Even a disabled mode must continue consuming Z.
    local a,b=Probe.captures.A,Probe.captures.B
    local pair=a and b and a.name==b.name and a.guid~=b.guid
    for _,slot in ipairs({"A","B"}) do
        local record,proxy=Probe.captures[slot],Probe.proxies[slot]
        local state={slot=slot,mode=Probe.mode,configuredKey="Z",spellID=679,enabled=false,reason="no_pair"}
        if record then
            state.expectedGUID,state.expectedName=record.guid,record.name
            local resolved=Probe.Resolve(record)
            if resolved then
                for key,value in pairs(resolved) do state[key]=value end
            end
            if pair then
                if Probe.mode=="converted" then
                    state.unitArg=resolved and resolved.converted
                    state.enabled=state.unitArg~=nil
                    state.reason=state.enabled and "ready" or (state.mapReason or "unmapped")
                    state.kind="spell"
                elseif Probe.mode=="guid_button" then
                    state.unitArg,state.kind,state.enabled,state.reason=record.guid,"spell",true,"ready"
                elseif Probe.mode=="guid_macro" or Probe.mode=="integrated_macro" then
                    local spell=exactSpell()
                    state.unitArg,state.kind=record.guid,"macro"
                    state.enabled=spell~=nil
                    state.reason=state.enabled and "ready" or "exact_rank_unavailable"
                    if Probe.mode=="integrated_macro" then
                        local sample=resolved and resolved.liveToken
                        local live=sample and NS.Read(UnitExists,sample)==true
                            and NS.Read(UnitGUID,sample)==record.guid and NS.Read(UnitIsDeadOrGhost,sample)==false
                        if not live then state.enabled,state.reason=false,"no_live_sample" end
                        state.macro=state.enabled and ("/stopattack\n/cleartarget\n/stopmacro [@target,exists][@mouseover,harm]\n/cast [@"..record.guid.."] "..spell) or nil
                    else
                        -- The original GUID route deliberately has no target-switch logic.
                        state.macro=spell and ("/cast [@"..record.guid.."] "..spell)
                    end
                    state.parseResult=NS.Read(SecureCmdOptionParse,"[@"..record.guid.."] probe")
                else
                    state.unitArg,state.kind,state.enabled,state.reason="target","spell",true,"ready"
                end
            end
        end
        proxy.probeState=state
        proxy:SetAttribute("type",nil)
        proxy:SetAttribute("unit",nil)
        proxy:SetAttribute("macrotext",nil)
        proxy:SetAttribute("probe-enabled",state.enabled)
        proxy:SetAttribute("probe-type",state.kind)
        proxy:SetAttribute("probe-unit",state.unitArg)
        proxy:SetAttribute("probe-macro",state.macro)
        proxy:SetAttribute("probe-mode",state.mode)
        proxy:SetAttribute("probe-branch","prepared")
        proxy:SetAttribute("probe-execute",false)
        if rearm~=false then proxy:SetAttribute("probe-armed",true) end
        Probe.prepared[slot]=state
        log("Record","MODE_PREPARED",{slot=slot,mode=state.mode,expectedGUID=state.expectedGUID,
            guidA=a and a.guid,guidB=b and b.guid,
            expectedName=state.expectedName,configuredKey="Z",spellID=679,unitArg=state.unitArg,
            readableMap=state.readableMap,mapReason=state.mapReason,liveToken=state.liveToken,
            liveGUID=state.liveGUID,liveRange=state.liveRange,enabled=state.enabled,reason=state.reason,
            parseResult=state.parseResult,rawGUIDReadback=state.rawGUIDReadback,
            rawExists=state.rawExists,rawExistsReason=state.rawExistsReason})
    end
    Probe.UpdateLabels()
    return true
end

local STOP=[[
    control:ClearBindings()
    control:SetAttribute("probe-active", false)
    control:SetAttribute("probe-hover-slot", nil)
    local panel = control:GetFrameRef("panel")
    if panel then panel:Hide() end
]]
Probe.Snippets.stop=STOP

local function finishStop()
    if not idle() then Probe.pendingStop=true;return false end
    if Probe.owner then
        ClearOverrideBindings(Probe.owner)
        Probe.owner:SetAttribute("probe-active",false)
        Probe.owner:SetAttribute("probe-hover-slot",nil)
    end
    if Probe.panel then Probe.panel:Hide() end
    Probe.active,Probe.pendingStop=false,false
    log("Stop")
    if type(NS.SetGUIDProbeSuspended)=="function" then pcall(NS.SetGUIDProbeSuspended,false) end
    return true
end

function Probe.Stop()
    if not Probe.active then return true end
    if not idle() then
        Probe.pendingStop=true
        say("战斗中请点面板的“停止”按钮；安全脚本会立即停止 Z 转接，脱战后恢复普通框体。")
        return false
    end
    return finishStop()
end

local function button(panel,label,x,fn,secure)
    local template=secure and "SecureHandlerClickTemplate,UIPanelButtonTemplate" or "UIPanelButtonTemplate"
    local value=CreateFrame("Button",nil,panel,template)
    value:SetSize(80,25)
    value:SetPoint("TOPLEFT",panel,"TOPLEFT",x,-40)
    value:SetText(label)
    value:SetScript("OnClick",fn)
    return value
end

local function createPanel()
    if Probe.panel then return true end
    if not idle() or type(SecureHandlerWrapScript)~="function" or type(SecureHandlerSetFrameRef)~="function"
        or type(ClearOverrideBindings)~="function" then return false end
    local panel=CreateFrame("Frame","MyForeverTargetsGUIDProbePanel",UIParent,"BackdropTemplate")
    panel:SetSize(724,244)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    panel:SetBackdropColor(.035,.045,.065,.98)
    panel:SetBackdropBorderColor(.65,.75,.88,1)
    local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",14,-13)
    title:SetText("GUID 隔离测试 · 两只同名怪物")
    local owner=CreateFrame("Frame","MyForeverTargetsGUIDProbeOwner",panel,"SecureHandlerBaseTemplate")
    owner:SetAttribute("probe-active",false)
    SecureHandlerSetFrameRef(owner,"panel",panel)
    Probe.owner,Probe.panel=owner,panel
    button(panel,"记 A",14,function() Probe.Capture("A") end)
    button(panel,"记 B",100,function() Probe.Capture("B") end)
    button(panel,"转换",186,function() Probe.SetMode("converted") end)
    button(panel,"GUID 按钮",272,function() Probe.SetMode("guid_button") end)
    button(panel,"GUID 指令",358,function() Probe.SetMode("guid_macro") end)
    button(panel,"内部指令",444,function() Probe.SetMode("integrated_macro") end)
    button(panel,"目标对照",530,function() Probe.SetMode("baseline") end)
    local stop=button(panel,"停止",616,function()
        if idle() then finishStop() else Probe.pendingStop=true;log("Record","STOP_DEFERRED",{combat=true}) end
    end,true)
    SecureHandlerWrapScript(stop,"OnClick",owner,STOP)
    Probe.stopButton=stop
    local modeLabel=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    modeLabel:SetPoint("TOPLEFT",14,-76)
    modeLabel:SetWidth(696)
    modeLabel:SetWordWrap(true)
    Probe.modeLabel=modeLabel
    local help=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    help:SetPoint("BOTTOMLEFT",14,14)
    help:SetWidth(696)
    help:SetWordWrap(true)
    Probe.help=help
    for i,slot in ipairs({"A","B"}) do
        local block=CreateFrame("Frame","MyForeverTargetsGUIDProbeBlock"..slot,panel,"SecureHandlerEnterLeaveTemplate,BackdropTemplate")
        block:SetSize(336,104)
        block:SetPoint("TOPLEFT",panel,"TOPLEFT",14+(i-1)*350,-99)
        block:EnableMouse(true)
        block:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        block:SetBackdropColor(.10,.16,.23,1)
        block:SetBackdropBorderColor(.35,.68,.95,1)
        block:SetAttribute("probe-slot",slot)
        local label=block:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        label:SetPoint("CENTER")
        block.label=label
        local proxy=CreateFrame("Button","MyForeverTargetsGUIDProbeProxy"..slot,owner,"SecureActionButtonTemplate")
        proxy:SetSize(1,1)
        proxy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10,10)
        proxy:EnableMouse(false)
        proxy:SetAttribute("useOnKeyDown",true)
        proxy:RegisterForClicks("AnyDown")
        proxy:SetScript("PreClick",observePre)
        proxy:SetScript("PostClick",observePost)
        SecureHandlerWrapScript(proxy,"PreClick",owner,PRECLICK)
        block:SetAttribute("probe-proxy",proxy:GetName())
        SecureHandlerSetFrameRef(block,"probeProxy",proxy)
        -- Blocks deliberately have no unit attribute; only the offscreen action
        -- proxy carries the unit argument whose behavior is being tested.
        SecureHandlerWrapScript(block,"OnEnter",owner,ENTER)
        SecureHandlerWrapScript(block,"OnLeave",owner,LEAVE)
        SecureHandlerWrapScript(block,"OnHide",owner,LEAVE)
        Probe.blocks[slot],Probe.proxies[slot]=block,proxy
    end
    panel:Hide()
    return true
end

local function open()
    if not idle() then say("GUID 测试需要先脱战打开。") return false end
    if not createPanel() then return false end
    if not Probe.active then
        if type(NS.SetGUIDProbeSuspended)~="function" then say("GUID 隔离暂停接口不可用，未开始测试。") return false end
        local ok,paused=pcall(NS.SetGUIDProbeSuspended,true)
        if not ok or paused==false then say("未能暂停普通框体施法，未开始 GUID 测试。") return false end
        Probe.active=true
        if log("Start")~=true then
            finishStop()
            say("日志未能启动，GUID 测试已退出并恢复普通框体。")
            return false
        end
        -- The logger starts a fresh capture session too. Never carry a stale
        -- A/B pair into a session that has no matching capture evidence.
        Probe.captures,Probe.prepared={},{}
        Probe.lastAttempt=nil
        Probe.mode="converted"
        for _,proxy in pairs(Probe.proxies) do proxy.lastAttempt=nil end
    end
    Probe.owner:SetAttribute("probe-active",true)
    Probe.panel:Show()
    return Probe.Prepare(true)
end

function Probe.Command(argument)
    argument=NS.Text(argument):lower():match("^%s*(.-)%s*$")
    if argument=="" or argument=="open" then return open() end
    if argument=="stop" then return Probe.Stop() end
    if not Probe.active and not open() then return false end
    if argument=="a" or argument=="b" then return Probe.Capture(argument:upper()) end
    if modes[argument] then return Probe.SetMode(argument) end
    say("GUID 测试：/mytargets guid；记 A／B 后选择测试模式，悬停块按 Z；停止请点按钮。")
    return false
end

local events=CreateFrame("Frame")
pcall(events.RegisterEvent,events,"PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent,events,"PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent",function(_,event)
    if Probe.pendingStop then finishStop() end
    if (event=="PLAYER_TARGET_CHANGED" or event=="PLAYER_REGEN_ENABLED") and Probe.active and idle()
        and Probe.mode=="converted" then Probe.Prepare(false) end
end)
