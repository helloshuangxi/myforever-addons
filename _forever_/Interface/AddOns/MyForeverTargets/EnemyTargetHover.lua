local _, NS = ...
local H = {}
NS.EnemyTargetHover = H
H.WIDTH,H.HEIGHT,H.GAP=76,26,1
local WHITE = "Interface\\Buttons\\WHITE8X8"
local legacyMode=NS.NativeMacroOnly==true and NS.Public(NS.LegacyNameBridge) and NS.LegacyNameBridge==true

local function guid(value)
    return NS.Public(value) and type(value)=="string" and value~="" and value or nil
end

local function visible(frame)
    return frame and NS.Read(frame.IsVisible or frame.IsShown,frame)==true
end

function NS.CreateIdentityBorders(region,layer)
    for _,kind in ipairs({"target","focus"}) do
        local inset=kind=="focus" and 0 or 2
        local edges={}
        for i=1,4 do
            local edge=layer:CreateTexture(nil,"OVERLAY",nil,7)
            edge:SetTexture(WHITE)
            if kind=="focus" then edge:SetVertexColor(1,.82,.1,1)
            else edge:SetVertexColor(1,.15,.12,1) end
            if i==1 then
                edge:SetPoint("TOPLEFT",region,"TOPLEFT",inset,-inset)
                edge:SetPoint("TOPRIGHT",region,"TOPRIGHT",-inset,-inset);edge:SetHeight(2)
            elseif i==2 then
                edge:SetPoint("BOTTOMLEFT",region,"BOTTOMLEFT",inset,inset)
                edge:SetPoint("BOTTOMRIGHT",region,"BOTTOMRIGHT",-inset,inset);edge:SetHeight(2)
            elseif i==3 then
                edge:SetPoint("TOPLEFT",region,"TOPLEFT",inset,-inset-2)
                edge:SetPoint("BOTTOMLEFT",region,"BOTTOMLEFT",inset,inset+2);edge:SetWidth(2)
            else
                edge:SetPoint("TOPRIGHT",region,"TOPRIGHT",-inset,-inset-2)
                edge:SetPoint("BOTTOMRIGHT",region,"BOTTOMRIGHT",-inset,inset+2);edge:SetWidth(2)
            end
            edge:Hide();edges[i]=edge
        end
        region[kind.."Edges"]=edges
    end
end

function NS.RefreshIdentityBorders(region,identity,selected)
    local expected=guid(identity)
    local focus=guid(NS.Read(UnitGUID,"focus"))
    region.selected=expected~=nil and selected==true
    region.focused=expected~=nil and focus~=nil and expected==focus
    for _,kind in ipairs({"target","focus"}) do
        local show=kind=="target" and region.selected or kind=="focus" and region.focused
        for _,edge in ipairs(region[kind.."Edges"]) do
            if show then edge:Show() else edge:Hide() end
        end
    end
end

local function label(parent,size)
    local text=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    local font=text:GetFont()
    if font then text:SetFont(font,size,"OUTLINE") end
    text:SetWordWrap(false)
    return text
end

local function createDisplay(row)
    -- Visuals stay independent of the secure visibility driver:
    -- hostile, dead and unavailable target data still have a readable card.
    local display=CreateFrame("Frame",nil,row)
    display:SetSize(H.WIDTH,H.HEIGHT)
    display:SetPoint("TOPLEFT",row,"BOTTOMLEFT",0,-H.GAP)
    display:SetFrameLevel(row:GetFrameLevel()+1)
    display:EnableMouse(false)
    display.border=display:CreateTexture(nil,"BACKGROUND")
    display.border:SetAllPoints(display)
    display.border:SetTexture(WHITE)
    display.border:SetVertexColor(.3,.37,.43,1)
    display.background=display:CreateTexture(nil,"BORDER")
    display.background:SetPoint("TOPLEFT",1,-1)
    display.background:SetPoint("BOTTOMRIGHT",-1,1)
    display.background:SetTexture(WHITE)
    display.background:SetVertexColor(.035,.045,.06,1)
    display.health=CreateFrame("StatusBar",nil,display)
    display.health:SetPoint("TOPLEFT",1,-1)
    display.health:SetPoint("BOTTOMRIGHT",-1,1)
    display.health:SetFrameLevel(row:GetFrameLevel()+2)
    display.health:EnableMouse(false)
    display.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    display.health:SetOrientation("HORIZONTAL")
    display.health:SetMinMaxValues(0,1)
    display.health:SetValue(0)
    display.labels=CreateFrame("Frame",nil,display)
    display.labels:SetAllPoints(display)
    display.labels:SetFrameLevel(row:GetFrameLevel()+3)
    display.labels:EnableMouse(false)
    display.nameText=label(display.labels,10)
    display.nameText:SetPoint("TOPLEFT",4,-4)
    display.nameText:SetSize(68,10)
    display.nameText:SetJustifyH("CENTER")
    display.classText=label(display.labels,8)
    display.classText:SetPoint("TOPLEFT",4,-14)
    display.classText:SetSize(38,8)
    display.classText:SetJustifyH("LEFT")
    display.healthText=label(display.labels,8)
    display.healthText:SetPoint("TOPRIGHT",-4,-14)
    display.healthText:SetSize(24,8)
    display.healthText:SetJustifyH("RIGHT")
    display.healthText:SetTextColor(.95,.96,.98,1)
    NS.CreateIdentityBorders(display,display.labels)
    display:Hide()
    row.enemyTargetDisplay=display
end

local function refreshDisplay(row,data,rowVisible)
    local display=row.enemyTargetDisplay
    local ownerValid=rowVisible and row.data and row.data.guid==row.expectedGUID
        and NS.ValidToken(row.unit) and guid(row.expectedGUID)
        and NS.Read(UnitGUID,row.unit)==row.expectedGUID
    local known=ownerValid and data and data.state=="known"
    local identity=known and guid(data.guid) or nil
    if identity and guid(NS.Read(UnitGUID,row.unit.."target"))~=identity then identity=nil end
    NS.RefreshIdentityBorders(display,identity,identity~=nil and guid(NS.Read(UnitGUID,"target"))==identity)
    local color=known and data.color or nil
    local r,g,b=color and color.r or .82,color and color.g or .85,color and color.b or .9
    display.nameText:SetText(ownerValid and (known and data.name or "目标 —") or "")
    display.nameText:SetTextColor(r,g,b,1)
    display.classText:SetText(known and (data.className or (data.player and "玩家" or "非玩家")) or "")
    display.classText:SetTextColor(r,g,b,1)
    local healthText=""
    if ownerValid then
        healthText=known and data.dead==true and "死亡" or
            (known and NS.Number(data.health) and (math.floor(data.health*100+.5).."%") or "—")
    end
    display.healthText:SetText(healthText)
    if known and data.dead==true then display.health:SetStatusBarColor(.18,.21,.24,1)
    elseif known and data.assist==true then display.health:SetStatusBarColor(.08,.43,.20,1)
    else display.health:SetStatusBarColor(.48,.16,.12,1) end
    local available=known and data.healthAvailable==true
    if available then
        -- Native StatusBar setters accept secret amounts. Only the public
        -- ratio above is formatted; never compare or divide the raw amounts.
        available=pcall(function()
            local current=data.healthCurrent
            if data.dead==true then current=0 end
            display.health:SetMinMaxValues(0,data.healthMax)
            display.health:SetValue(current)
        end)
    end
    if available then display.health:Show()
    else
        display.health:SetMinMaxValues(0,1)
        display.health:SetValue(0)
        display.health:Hide()
    end
    if ownerValid then display:Show() else display:Hide() end
end

local function clearButton(button)
    if not button then return end
    if legacyMode and NS.NearbyCast and type(NS.NearbyCast.Leave)=="function" then
        NS.NearbyCast.Leave(button)
    end
    if NS.HoveredEnemyTarget==button then NS.HoveredEnemyTarget=nil end
    button.hoverFill:SetVertexColor(.3,1,.55,0)
    button.tooltipKey=nil
    button.status=nil
    if GameTooltip and NS.Read(GameTooltip.GetOwner,GameTooltip)==button then GameTooltip:Hide() end
end

function H.Clear()
    local button=NS.HoveredEnemyTarget
    if button and button.owner and button.owner.enemyTargetButton==button then clearButton(button) end
end

local function usable(row,data)
    local button=row.enemyTargetButton
    if not button or not button.bindingReady or not NS.ValidToken(row.unit)
        or not guid(row.expectedGUID) or button.bindingOwnerGUID~=row.expectedGUID
        or button.unit~=row.unit.."target" then return false end
    if NS.Read(UnitGUID,row.unit)~=row.expectedGUID then return false end
    if not NS.Public(data) or type(data)~="table" or not NS.Public(data.state)
        or data.state~="known" or not guid(data.guid)
        or not NS.Public(data.dead) or data.dead~=false then return false end
    if legacyMode then
        if not row.data or row.data.guid~=row.expectedGUID
            or not NS.Public(data.offline) or data.offline~=false
            or not NS.Public(data.player) or type(data.player)~="boolean"
            or NS.Text(data.name)=="" or NS.Text(data.targetName)=="" then return false end
        if not (NS.Public(data.assist) and data.assist==true)
            and not (NS.Public(data.harm) and data.harm==true) then return false end
    elseif not NS.Public(data.assist) or data.assist~=true then return false end
    return NS.Read(UnitGUID,button.unit)==data.guid
end

-- A target-of-enemy token is admitted only through its owning enemy row and
-- current relationship snapshot. It is never added to the global token list.
function NS.ReadBridgeTarget(button)
    if not legacyMode or not button or button.bridgeTarget~=true then return nil end
    local row=button.owner
    if not row or row.enemyTargetButton~=button or not visible(row) or not visible(button)
        or not NS.DB or NS.DB.shown==false or not guid(button.expectedGUID)
        or type(NS.ReadEnemyTarget)~="function" then return nil end
    local data=NS.ReadEnemyTarget(row.unit,row.expectedGUID)
    if not usable(row,data) or data.guid~=button.expectedGUID then return nil end
    local side=data.assist==true and "friendly" or data.harm==true and "enemy" or nil
    if not side or side~=button.side then return nil end
    if NS.Read(UnitGUID,row.unit)~=row.expectedGUID then return nil end
    return {unit=button.unit,side=side,guid=data.guid,name=data.name,targetName=data.targetName,
        player=data.player,dead=data.dead,offline=data.offline}
end

local function statusFor(button,data,valid)
    local expected=valid and guid(data.guid) or nil
    local actual=guid(NS.Read(UnitGUID,"mouseover"))
    local current=guid(NS.Read(UnitGUID,"target"))
    local identity=expected~=nil and actual==expected
    local condition=not legacyMode and identity and NS.Read(SecureCmdOptionParse,
        "[@mouseover,help,nodead] MFT_ENEMY_TARGET")=="MFT_ENEMY_TARGET" or false
    local status={expectedGUID=expected,actualMouseoverGUID=actual,currentTargetGUID=current,
        ownerGUID=button.bindingOwnerGUID,unit=button.unit,
        identityMatches=identity,conditionMatched=condition}
    if legacyMode then
        local cast=NS.NearbyCast
        status.legacy=true
        status.side=button.side
        status.enabled=NS.DB and NS.DB.legacyNameBridgeEnabled==true
        status.combat=NS.InCombat()
        status.count=cast and cast.row==button and NS.Number(cast.count) and cast.count or 0
        local bridgeStatus=cast and NS.Read(cast.Status,button)
        if type(bridgeStatus)=="table" then
            status.reason=NS.Text(bridgeStatus.reason)
            status.count=NS.Number(bridgeStatus.count) and math.max(0,math.floor(bridgeStatus.count)) or 0
        end
    end
    status.key=table.concat({expected or "",actual or "",current or "",status.ownerGUID or "",
        status.unit or "",identity and "1" or "0",condition and "1" or "0",
        status.side or "",status.enabled and "1" or "0",status.combat and "1" or "0",
        tostring(status.count or 0),status.reason or ""},":")
    button.status=status
    local diagnostics=NS.Diagnostics
    if type(diagnostics)=="table" and type(diagnostics.Record)=="function"
        and NS.Read(diagnostics.Enabled)==true then
        local session=NS.Read(diagnostics.Session)
        local sessionKey=NS.Number(session) and tostring(session) or ""
        local key=sessionKey..":"..status.key
        if button.diagnosticKey~=key then
            local ok,recorded=pcall(diagnostics.Record,legacyMode and "ENEMY_TARGET_BRIDGE_STATE" or "ENEMY_TARGET_MOUSEOVER",{
                expectedGUID=expected,actualMouseoverGUID=actual,currentTargetGUID=current,ownerGUID=status.ownerGUID,
                unit=status.unit,identityMatches=identity,conditionMatched=condition,
                route=legacyMode and "legacy_name" or "native_mouseover",side=status.side,
                enabled=status.enabled,combat=status.combat,preparedCount=status.count,reason=status.reason})
            if ok and NS.Public(recorded) and recorded==true then button.diagnosticKey=key end
        end
    else button.diagnosticKey=nil end
    return status
end

local function showTooltip(button,data,status)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
    local ok,hasUnit=false,nil
    if type(GameTooltip.SetUnit)=="function" and button.unit then
        ok,hasUnit=pcall(GameTooltip.SetUnit,GameTooltip,button.unit)
    end
    button.unitTooltipReady=ok and NS.Public(hasUnit) and hasUnit==true
    if not button.unitTooltipReady then
        GameTooltip:SetText(legacyMode and (NS.Text(data and data.name)~="" and data.name or "敌人的目标") or "友方目标未确认")
    end
    -- A successful SetUnit must keep its native payload: SetText/ClearLines
    -- afterwards cleared the native mouseover in this client's prior checks.
    if legacyMode then
        GameTooltip:AddLine("脱战悬停此条后按普通技能键：友方使用治疗／增益，敌方使用伤害技能。",.82,.85,.9,true)
        GameTooltip:AddLine("按键会短暂选中此目标、施法，再恢复原目标；原来无目标则恢复为空。",.82,.85,.9,true)
        GameTooltip:AddLine("宏和物品保持原行为；移开、隐藏或入战时交还原键。",.82,.85,.9,true)
        if not status.enabled then
            GameTooltip:AddLine("普通技能兼容已关闭，可点上方“施法”开启。",1,.76,.4,true)
        elseif status.combat then
            GameTooltip:AddLine("当前在战斗中；此兼容方案仅支持脱战。",1,.76,.4,true)
        elseif status.reason=="not_unique" then
            GameTooltip:AddLine("同名目标无法确认唯一，未准备临时选目标施法。",1,.76,.4,true)
        elseif status.reason=="no_supported_spell" then
            GameTooltip:AddLine("未找到适合此目标的普通技能键；宏和物品保持原行为。",1,.76,.4,true)
        elseif status.count>0 then
            GameTooltip:AddLine("已准备 "..status.count.." 个普通技能键。",.45,1,.6,true)
        else
            GameTooltip:AddLine("正在检查此目标和可用的普通技能键。",1,.76,.4,true)
        end
    else
        GameTooltip:AddLine("敌人的友方目标；在这里按自己的 @mouseover 治疗／增益宏。",.82,.85,.9,true)
    end
    GameTooltip:AddLine("左键选中 · 右键设为焦点 · Ctrl+右键打标记",.82,.85,.9,true)
    GameTooltip:AddLine("红框为当前目标，黄框为焦点。",.82,.85,.9,true)
    GameTooltip:AddLine("姓名板目标条的右键焦点兼容仅脱战，临时选中后恢复原目标；重复右键保留焦点。",.82,.85,.9,true)
    if not legacyMode and status.identityMatches and status.conditionMatched then
        GameTooltip:AddLine("游戏已确认鼠标单位及友方宏条件；施法仍由原宏处理。",.45,1,.6,true)
    elseif not legacyMode then
        GameTooltip:AddLine("原生鼠标单位尚未确认；原宏可能使用自己的后备分支。",1,.76,.4,true)
    end
    GameTooltip:Show()
    button.tooltipKey=status.key..":"..NS.Text(data and data.name)
end

function H.Create(row)
    if not row or row.side~="enemy" then return nil end
    if row.enemyTargetButton then return row.enemyTargetButton end
    createDisplay(row)
    local name=NS.Read(row.GetName,row)
    local button=CreateFrame("Button",type(name)=="string" and name.."FriendlyTarget" or nil,row,"SecureUnitButtonTemplate")
    button.owner=row
    button.bridgeTarget=true
    button.side="friendly"
    button:SetSize(H.WIDTH,H.HEIGHT)
    button:SetPoint("TOPLEFT",row,"BOTTOMLEFT",0,-H.GAP)
    button:SetFrameLevel(row:GetFrameLevel()+4)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useparent*",false)
    button:SetAttribute("useOnKeyDown",false)
    button:SetAttribute("*type1","target")
    button:SetAttribute("unit",nil)
    button.nativeClick=button:GetScript("OnClick")
    if type(NS.SetupClickActions)=="function" then NS.SetupClickActions(button) end
    button.hoverFill=button:CreateTexture(nil,"OVERLAY")
    button.hoverFill:SetPoint("TOPLEFT",4,-4)
    button.hoverFill:SetPoint("BOTTOMRIGHT",-4,4)
    button.hoverFill:SetTexture(WHITE)
    button.hoverFill:SetVertexColor(.3,1,.55,0)
    button:Hide()
    row.enemyTargetButton=button

    -- This UIParent sibling stays unprotected. Only this small shield changes
    -- ordinary Lua visibility in combat; the protected button has a driver.
    local shield=CreateFrame("Frame",nil,UIParent)
    shield:SetAllPoints(button)
    shield:SetFrameStrata(NS.Read(row.GetFrameStrata,row) or "MEDIUM")
    shield:SetFrameLevel(row:GetFrameLevel()+5)
    shield:EnableMouse(true)
    if NS.Read(shield.IsProtected,shield)==true then error("Enemy target shield must remain unprotected") end
    shield:SetScript("OnEnter",function() H.Clear() end)
    shield:SetScript("OnLeave",function() clearButton(button) end)
    shield:Hide()
    button.shield=shield
    button:SetScript("OnEnter",function()
        local data=row.enemyTarget
        if not visible(row) or not visible(button) or NS.Read(shield.IsShown,shield)==true
            or not usable(row,data) then clearButton(button);return end
        H.Clear()
        if NS.HoveredTile==row then
            NS.HoveredTile=nil
            if row.hover then row.hover:Hide() end
            if type(NS.SetHoverUnit)=="function" then NS.SetHoverUnit(nil) end
        end
        NS.HoveredEnemyTarget=button
        button.hoverFill:SetVertexColor(button.side=="enemy" and 1 or .3,button.side=="enemy" and .4 or 1,.55,.12)
        local status=statusFor(button,data,true)
        showTooltip(button,data,status)
    end)
    button:SetScript("OnLeave",function() clearButton(button) end)
    button:SetScript("OnHide",function() clearButton(button);shield:Hide() end)
    if legacyMode and NS.NearbyCast and type(NS.NearbyCast.Install)=="function" then
        NS.NearbyCast.Install(button)
    end
    return button
end

function H.Bind(row)
    local button=row and row.enemyTargetButton
    if not button or NS.InCombat() then return false end
    local ownerGUID=guid(row.expectedGUID)
    local unit=NS.ValidToken(row.unit) and ownerGUID and NS.Read(UnitGUID,row.unit)==ownerGUID
        and row.unit.."target" or nil
    if button.bindingReady and unit==button.unit and ownerGUID==button.bindingOwnerGUID then return true end
    clearButton(button)
    if type(UnregisterStateDriver)=="function" then UnregisterStateDriver(button,"visibility") end
    button.bindingReady=false
    button.unit,button.bindingOwnerGUID=nil,nil
    button:SetAttribute("unit",nil)
    button:SetAttribute("mark-unit",nil)
    button:SetAttribute("mark-guid",nil)
    button:SetAttribute("mark-owner-guid",nil)
    button:SetAttribute("target-side",nil)
    button:Hide()
    if not unit or type(RegisterStateDriver)~="function" then return false end
    button:SetAttribute("unit",unit)
    button.unit,button.bindingOwnerGUID=unit,ownerGUID
    local condition=legacyMode and ",exists] show; hide" or ",help,nodead] show; hide"
    local ok=pcall(RegisterStateDriver,button,"visibility","[@"..unit..condition)
    if not ok then
        if type(UnregisterStateDriver)=="function" then pcall(UnregisterStateDriver,button,"visibility") end
        button:SetAttribute("unit",nil)
        button:Hide()
        button.unit,button.bindingOwnerGUID=nil,nil
        return false
    end
    button.bindingReady=true
    return true
end

function H.Refresh(row,data)
    local button=row and row.enemyTargetButton
    if not button then return end
    local rowVisible=visible(row) and not (NS.DB and NS.DB.shown==false)
    refreshDisplay(row,data,rowVisible)
    local valid=rowVisible and usable(row,data)
    button.expectedGUID=valid and data.guid or nil
    button.data=valid and data or nil
    if legacyMode then button.side=valid and (data.assist==true and "friendly" or "enemy") or nil end
    if not NS.InCombat() then
        -- Target relationships may change while the owner's unit stays bound.
        -- Freeze the palette identity outside combat; stale menus stay shielded.
        local attributes={"mark-unit","mark-guid","mark-owner-guid","target-side"}
        local values={valid and button.unit or nil,valid and data.guid or nil,
            valid and button.bindingOwnerGUID or nil,valid and button.side or nil}
        for i,key in ipairs(attributes) do
            if button:GetAttribute(key)~=values[i] then button:SetAttribute(key,values[i]) end
        end
    end
    if rowVisible and visible(button) and not valid then button.shield:Show() else button.shield:Hide() end
    if NS.HoveredEnemyTarget==button then
        if not valid or not visible(button) then
            statusFor(button,data,false)
            clearButton(button)
            return
        end
        local status=statusFor(button,data,true)
        local key=status.key..":"..NS.Text(data.name)
        if key~=button.tooltipKey then showTooltip(button,data,status) end
    end
end
