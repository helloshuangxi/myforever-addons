local _, NS = ...

-- Unit attributes and tooltips retain the real unit alias. Native mouseover
-- identity is read back from the client rather than inferred from tile hover.
-- Only the unprotected, UIParent-owned input shields change visibility in combat.
local TILE_WIDTH, TILE_HEIGHT, GAP, PAD, COLUMNS = 76, 58, 1, 4, 5
local GRID_TOP = 28
local function legacyBridge(side)
    return (side=="friendly" or side=="enemy") and NS.NativeMacroOnly==true
        and NS.Public(NS.LegacyNameBridge) and NS.LegacyNameBridge==true
end
local function focusCycleData(row)
    local module=NS.FocusCycle
    local data=module and type(module.PinnedData)=="function" and NS.Read(module.PinnedData,row)
    return type(data)=="table" and data or nil
end
local function focusCycleStatus(row)
    local module=NS.FocusCycle
    local status=module and type(module.RowStatus)=="function" and NS.Read(module.RowStatus,row)
    return NS.Public(status) and type(status)=="string" and status~="" and status or nil
end
local function cellHeight(side)
    local target=side=="enemy" and NS.EnemyTargetHover
    return TILE_HEIGHT+(target and (target.GAP+target.HEIGHT) or 0)
end
local WIDTH = PAD * 2 + TILE_WIDTH * COLUMNS + GAP * (COLUMNS - 1)
local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = {bgFile=WHITE, edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10,
    insets={left=3,right=3,top=3,bottom=3}}
local MODES = {{"raid","团队"},{"party","小队"},{"nearby","附近"}}
local MARK_NAMES = {"星星","圆圈","菱形","三角","月亮","方块","十字","骷髅"}

-- Passive UI diagnostics never replace a native action or write its attributes.
local markObservationID=0
local function observedValue(value)
    if not NS.Public(value) then return "[restricted]" end
    if value==nil then return "[nil]" end
    if type(value)=="string" then return NS.Text(value) end
    if type(value)=="boolean" or NS.Number(value) then return value end
    return "[unsupported]"
end
local function observedRead(fn,...)
    if type(fn)~="function" then return "[unavailable]" end
    local ok,value=pcall(fn,...)
    if not ok then return "[api-error]" end
    return observedValue(value)
end
local function observedGUID(value)
    return NS.Public(value) and type(value)=="string" and value~="" and value:sub(1,1)~="[" and value or nil
end
local function uiDiagnostics()
    local diagnostics=NS.Diagnostics
    if type(diagnostics)~="table" or type(diagnostics.Record)~="function"
        or type(diagnostics.Enabled)=="function" and NS.Read(diagnostics.Enabled)~=true then return nil end
    return diagnostics
end
local function uiObservation(kind,fields)
    pcall(function()
        local diagnostics=uiDiagnostics()
        if not diagnostics then return end
        local record=fields()
        if type(record)=="table" and next(record)~=nil then diagnostics.Record(kind,record) end
    end)
end
local function observedMarkGuard(unit,side)
    if not NS.Public(side) or (side~="friendly" and side~="enemy") then return "[invalid-side]" end
    if not NS.ValidToken(unit) then return "[invalid-unit]" end
    return observedRead(SecureCmdOptionParse,"[@"..unit..",exists,"..(side=="friendly" and "help" or "harm").."] yes")
end
local function menuObservation(menu)
    local unit=menu and NS.Read(menu.GetAttribute,menu,"unit")
    local side=menu and NS.Read(menu.GetAttribute,menu,"target-side")
    return {menuShown=menu and observedRead(menu.IsShown,menu),menuUnit=observedValue(unit),
        menuSide=observedValue(side),
        menuSourceGUID=observedValue(menu and menu.sourceGUID),menuLiveGUID=observedRead(UnitGUID,unit),
        menuMarker=observedRead(GetRaidTargetIndex,unit),menuDead=observedRead(UnitIsDeadOrGhost,unit),
        menuGuard=observedMarkGuard(unit,side),conditionOnlyDiagnostic=true,
        menuShieldShown=menu and menu.shield and observedRead(menu.shield.IsShown,menu.shield)}
end
local function rowObservation(row,button,down)
    local fields=menuObservation(NS.MarkerMenu)
    local unit=row and row.unit
    fields.row=observedRead(row and row.GetName,row)
    fields.unit,fields.expectedGUID=observedValue(unit),observedValue(row and row.expectedGUID)
    fields.liveGUID,fields.unitExists=observedRead(UnitGUID,unit),observedRead(UnitExists,unit)
    fields.unitHarm,fields.unitHelp=observedRead(UnitCanAttack,"player",unit),observedRead(UnitCanAssist,"player",unit)
    fields.unitDead=observedRead(UnitIsDeadOrGhost,unit)
    fields.button,fields.down=observedValue(button),observedValue(down)
    fields.side,fields.combat=observedValue(row and row.side),observedRead(InCombatLockdown)
    fields.targetGUID,fields.mouseoverGUID=observedRead(UnitGUID,"target"),observedRead(UnitGUID,"mouseover")
    fields.focusGUID,fields.ctrlDown=observedRead(UnitGUID,"focus"),observedRead(IsControlKeyDown)
    fields.zBinding,fields.wBinding=observedRead(GetBindingAction,"Z",true),observedRead(GetBindingAction,"W",true)
    fields.rightType=observedRead(row and row.GetAttribute,row,"*type2")
    fields.ctrlRightType=observedRead(row and row.GetAttribute,row,"ctrl-type2")
    fields.markUnit=observedRead(row and row.GetAttribute,row,"mark-unit")
    fields.markGUID=observedRead(row and row.GetAttribute,row,"mark-guid")
    fields.nativeOnClickIdentity=row and row.nativeClick~=nil and NS.Read(row.GetScript,row,"OnClick")==row.nativeClick
    local markUnit=fields.markUnit=="[nil]" and observedRead(row and row.GetAttribute,row,"unit") or fields.markUnit
    fields.openMarkGuard=observedMarkGuard(markUnit,row and row.side)
    local delegate=row and row.markController
    fields.rightController=observedRead(delegate and delegate.GetName,delegate)
    fields.controllerRestricted=observedRead(delegate and delegate.HasAccessConstraints,delegate)
    local aspect=Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput
    local aspectReader=NS.Public(aspect) and aspect~=nil and delegate and delegate.HasAnyForbiddenAspects or nil
    fields.controllerScriptedInputForbidden=observedRead(aspectReader,delegate,aspect)
    return fields
end
local function observeRow(kind,row,button,down)
    uiObservation(kind,function() return rowObservation(row,button,down) end)
end
local function observeShield(shield,row,kind,button)
    uiObservation("UI_SHIELD_BLOCKED",function()
        local fields=rowObservation(row,button)
        local key=table.concat({kind,tostring(fields.button),tostring(fields.unit),tostring(fields.expectedGUID),
            tostring(fields.liveGUID),tostring(fields.menuUnit),tostring(fields.menuSourceGUID),tostring(fields.menuLiveGUID)},":")
        local now=NS.Read(GetTime)
        if key==shield.observedBlockKey and (not NS.Number(now) or not NS.Number(shield.observedBlockTime)
            or now-shield.observedBlockTime<2) then return nil end
        shield.observedBlockKey,shield.observedBlockTime=key,now
        fields.shield,fields.phase=kind,"blocked"
        return fields
    end)
end
local function markerReadback(mark,menu,request,phase,delay)
    uiObservation(phase,function()
        local fields=menuObservation(menu)
        local current=observedRead(UnitGUID,request.unit)
        local expected,actual=observedGUID(request.expectedGUID),observedGUID(current)
        local matched=expected~=nil and actual~=nil and expected==actual
        fields.attemptID,fields.phase,fields.delay=request.id,phase,delay
        fields.unit,fields.expectedGUID,fields.liveGUID=observedValue(request.unit),request.expectedGUID,current
        fields.requestedMarker,fields.markerBefore,fields.markerAfter=request.marker,request.beforeMarker,
            observedRead(GetRaidTargetIndex,request.unit)
        fields.identityMatches,fields.stale=matched,not matched
        fields.readbackStatus=matched and "same_guid" or expected and actual and "stale" or "identity_unreadable"
        fields.beforeTargetGUID,fields.afterTargetGUID=request.beforeTargetGUID,observedRead(UnitGUID,"target")
        fields.button,fields.down=request.button,request.down
        fields.recipientProven=false
        fields.nativeOnClickIdentity=mark.nativeClick~=nil and NS.Read(mark.GetScript,mark,"OnClick")==mark.nativeClick
        fields.nativeHandlerWasPresent=mark.nativeHandlerWasPresent
        fields.note="Readback observation only; no mark, cast, target selection or restoration is performed"
        return fields
    end)
end
local function observeMarkerPre(mark,menu,button,down)
    uiObservation("MARKER_PRECLICK",function()
        markObservationID=markObservationID+1
        local unit=NS.Read(mark.GetAttribute,mark,"unit")
        local request={id=markObservationID,unit=unit,expectedGUID=observedValue(menu.sourceGUID),
            marker=observedRead(mark.GetAttribute,mark,"*marker1"),beforeMarker=observedRead(GetRaidTargetIndex,unit),
            beforeTargetGUID=observedRead(UnitGUID,"target"),button=observedValue(button),down=observedValue(down)}
        mark.observedRequest=request
        local fields=menuObservation(menu)
        fields.attemptID,fields.unit,fields.expectedGUID=request.id,observedValue(unit),request.expectedGUID
        fields.liveGUID,fields.markerBefore=observedRead(UnitGUID,unit),request.beforeMarker
        fields.requestedMarker,fields.beforeTargetGUID=request.marker,request.beforeTargetGUID
        fields.button,fields.down=request.button,request.down
        fields.actionType=observedRead(mark.GetAttribute,mark,"*type1")
        fields.nativeOnClickIdentity=mark.nativeClick~=nil and NS.Read(mark.GetScript,mark,"OnClick")==mark.nativeClick
        fields.nativeHandlerWasPresent=mark.nativeHandlerWasPresent
        fields.action=observedRead(mark.GetAttribute,mark,"*action1")
        fields.unitExists,fields.unitHarm,fields.unitHelp=observedRead(UnitExists,unit),
            observedRead(UnitCanAttack,"player",unit),observedRead(UnitCanAssist,"player",unit)
        fields.markGuard=observedMarkGuard(unit,NS.Read(menu.GetAttribute,menu,"target-side"))
        fields.inRaid,fields.inGroup=observedRead(IsInRaid),observedRead(IsInGroup)
        fields.playerLeader,fields.playerAssistant=observedRead(UnitIsGroupLeader,"player"),observedRead(UnitIsGroupAssistant,"player")
        fields.recipientProven=false
        return fields
    end)
end
local function observeMarkerPost(mark,menu,button,down)
    pcall(function()
        local request=mark.observedRequest
        mark.observedRequest=nil
        if not request or not uiDiagnostics() then return end
        markerReadback(mark,menu,request,"MARKER_POSTCLICK",0)
        if C_Timer and type(C_Timer.After)=="function" then
            for _,delay in ipairs({.2,.5}) do
                pcall(C_Timer.After,delay,function() markerReadback(mark,menu,request,"MARKER_READBACK",delay) end)
            end
        end
    end)
end

local function shown(frame, value)
    if value then frame:Show() else frame:Hide() end
end
local function nativeAmount(bar,current,maximum,available)
    if available~=true then
        pcall(bar.SetMinMaxValues,bar,0,1)
        pcall(bar.SetValue,bar,0)
        bar:Hide()
        return false
    end
    -- These C-implemented setters explicitly accept secret numeric arguments.
    -- Never compare, divide, format or read back the raw values in Lua.
    local ok=pcall(function()
        bar:SetMinMaxValues(0,maximum)
        bar:SetValue(current)
    end)
    shown(bar,ok)
    return ok
end
local function text(parent, size, color)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font = label:GetFont()
    if font then label:SetFont(font, size or 12, "OUTLINE") end
    label:SetTextColor(unpack(color or {0.88,0.9,0.93,1}))
    return label
end
local function background(frame, color, edge)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(color or {0.045,0.055,0.075,0.97}))
    frame:SetBackdropBorderColor(unpack(edge or {0.28,0.32,0.38,1}))
end
local function icon(texture, index)
    if SetRaidTargetIconTexture then
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        SetRaidTargetIconTexture(texture, index)
    else
        texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index)
    end
end
local function tooltip(frame, title, lines)
    if not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    for _, line in ipairs(lines or {}) do GameTooltip:AddLine(line, 0.82,0.85,0.9,true) end
    GameTooltip:Show()
end
local function unitTooltip(frame,title,lines,castInstruction)
    frame.unitTooltipReady=false
    if not GameTooltip then return false end
    GameTooltip:SetOwner(frame,"ANCHOR_RIGHT")
    local ok,hasUnit=false,nil
    local pinned=focusCycleData(frame)
    local liveIdentity=not pinned or observedGUID(NS.Read(UnitGUID,frame.unit))==observedGUID(frame.expectedGUID)
    if type(GameTooltip.SetUnit)=="function" and NS.ValidToken(frame.unit) and liveIdentity then
        ok,hasUnit=pcall(GameTooltip.SetUnit,GameTooltip,frame.unit)
    end
    local ready=ok and NS.Public(hasUnit) and hasUnit==true
    frame.unitTooltipReady=ready
    -- Retain the native unit payload on the shared tooltip instead of replacing
    -- it with a text-only tooltip after SetUnit succeeds.
    if not ready then
        GameTooltip:SetText(title)
        GameTooltip:AddLine(legacyBridge(frame.side) and "单位提示暂不可用；普通技能兼容的准备状态见下方。" or
            NS.NativeMacroOnly and "单位提示暂不可用；原生鼠标状态见下方。" or
            "原生鼠标单位未确认；兼容按键的准备状态见下方。",.82,.85,.9,true)
    end
    for _,line in ipairs(lines or {}) do GameTooltip:AddLine(line,.82,.85,.9,true) end
    GameTooltip:AddLine(castInstruction,.82,.85,.9,true)
    GameTooltip:Show()
    return ready
end
local function hideTooltip() if GameTooltip then GameTooltip:Hide() end end

local function readEnemyTarget(row)
    row.enemyTarget=nil
    if row.side=="enemy" and type(NS.ReadEnemyTarget)=="function" then
        row.enemyTarget=NS.ReadEnemyTarget(row.unit,row.expectedGUID)
    end
    return row.enemyTarget
end

local function enemyTargetTooltip(row)
    local target=row.enemyTarget
    if target and target.state=="known" then return "目标："..target.name end
    return "目标：暂未显示"
end

local function combatCastStatus(row)
    if legacyBridge(row.side) then
        local module=NS.NearbyCast
        local status=module and NS.Read(module.Status,row)
        status=type(status)=="table" and status or {}
        local count=NS.Number(status.count) and math.max(0,math.floor(status.count)) or 0
        local reason=NS.Text(status.reason)
        local state={legacyName=true,reason=reason,count=count,prepared=status.prepared==true}
        if not NS.DB.legacyNameBridgeEnabled or reason=="disabled" then
            state.nativeText="普通技能悬停兼容已关闭，可点上方“施法”开启。"
        elseif NS.InCombat() or reason=="out_of_combat_only" then
            state.nativeText="临时选目标施法仅支持脱战；战斗中交还原技能键。"
        elseif state.prepared then
            state.nativeText="已准备 "..count.." 个普通技能键；按键时短暂选中此单位，施法后恢复原目标。"
        elseif reason=="not_unique" then
            state.nativeText="同名目标无法确认唯一，未准备临时选目标施法。"
        elseif reason=="no_supported_spell" then
            state.nativeText="未找到适合此单位的普通技能键；宏和物品保持原行为。"
        else
            state.nativeText="正在检查单位和普通技能键；未准备时保留原技能行为。"
        end
        return state,table.concat({"legacy_name",reason,state.nativeText,tostring(count),
            NS.Text(status.unit),NS.Text(status.guid)},":")
    end
    if NS.NativeMacroOnly then
        local confirmed,message,details=NS.Read(NS.NativeMouseoverStatus,row)
        details=type(details)=="table" and details or {}
        local state={reason="native_macro",prepared=false,
            nativeConfirmed=NS.Public(confirmed) and confirmed==true,
            nativeText=NS.Text(message)}
        if state.nativeText=="" then
            state.nativeText="原生鼠标单位未确认；原宏可能回退当前目标。"
        end
        local key=table.concat({"native_macro",state.nativeConfirmed and "1" or "0",state.nativeText,
            NS.Text(details.expectedGUID),NS.Text(details.mouseoverGUID),NS.Text(details.unitGUID),
            NS.Text(details.condition),NS.Text(details.reason),
            NS.Public(details.identityMatches) and details.identityMatches==true and "1" or "0",
            NS.Public(details.conditionMatched) and details.conditionMatched==true and "1" or "0"},":")
        return state,key
    end
    local module=NS.CombatCast
    local status=module and NS.Read(module.Status,row)
    if type(status)~="table" then status={reason="unavailable"} end
    local state={reason=NS.Text(status.reason),name=NS.Text(status.name),
        unit=NS.Text(status.unit),guid=NS.Text(status.guid),
        count=NS.Number(status.count) and math.max(0,math.floor(status.count)) or 0}
    state.prepared=NS.Public(status.prepared) and status.prepared==true and state.count>0
        and state.guid~="" and state.guid==NS.Text(row.expectedGUID) and state.unit==NS.Text(row.unit)
    local key=table.concat({state.prepared and "1" or "0",state.reason,state.name,state.unit,state.guid,state.count},":")
    return state,key
end

local function combatPreparationLine(status)
    if status.legacyName then return status.nativeText end
    if NS.NativeMacroOnly then return status.nativeText end
    if NS.PreserveCastTarget then
        if status.reason=="native_unit" then
            return "自己／小队／团队等稳定友方单位使用原生悬停路径，需客户端识别鼠标单位。"
        elseif status.prepared then
            return "GUID直施尝试：已准备 "..status.count.." 个普通技能键；按悬停格 GUID，不切换当前目标。尚待游戏验证。"
        elseif status.reason=="disabled" then
            return "悬停施法已关闭。"
        elseif status.reason=="unsupported_guid_unit" then
            return "此目标未接入GUID直施尝试；原生悬停取决于客户端的鼠标单位识别。"
        elseif status.reason=="no_actions" or status.reason=="unsupported_macro" then
            return "未找到支持的普通技能键；已有宏和物品保持原行为，不接入GUID直施尝试。"
        end
        return "GUID直施尝试尚未准备；新目标与技能需脱战准备。当前目标保持。"
    end
    if status.prepared then
        return "已准备 "..status.count.." 个技能键；战斗中沿用战前的名称和动作，新目标需脱战准备。"
    elseif status.reason=="native_unit" then
        return "小队／团队等稳定友方单位使用原生悬停路径。"
    elseif status.reason=="not_unique" then
        return "此怪物有已知同名或唯一性未确认，未准备战斗按键。"
    elseif status.reason=="no_actions" then
        return "未找到支持的技能键；不支持的技能、宏和物品保留原动作。"
    elseif status.reason=="disabled" then
        return "悬停施法已关闭，未准备战斗按键。"
    end
    return "此目标未准备战斗悬停按键；战斗中不能临时建立。"
end

local function panelBounds(panel)
    if not panel or not panel:IsShown() then return nil end
    local left,right=NS.Read(panel.GetLeft,panel),NS.Read(panel.GetRight,panel)
    local top,bottom=NS.Read(panel.GetTop,panel),NS.Read(panel.GetBottom,panel)
    if NS.Number(left) and NS.Number(right) and NS.Number(top) and NS.Number(bottom) then
        return {left=left,right=right,top=top,bottom=bottom}
    end
end

local function shiftPanel(side,panel,deltaY)
    if not NS.Number(deltaY) then return false end
    if math.abs(deltaY)<.01 then return true end
    local point,relativeTo,relativePoint,x,y=panel:GetPoint()
    if type(point)~="string" or not NS.Number(x) or not NS.Number(y) then return false end
    y=y+deltaY
    panel:ClearAllPoints()
    panel:SetPoint(point,relativeTo,relativePoint,x,y)
    return true
end

local function screenSize()
    local width,height=NS.Read(UIParent.GetWidth,UIParent),NS.Read(UIParent.GetHeight,UIParent)
    if NS.Number(width) and width>0 and NS.Number(height) and height>0 then return width,height end
end

local function bottomSafeArea(height)
    -- Keep the enlarged cards above the player's bottom action bars.
    return math.min(160,height*.14)
end

local function canShiftPanel(panel,bounds,deltaY)
    local _,height=screenSize()
    local scale=NS.Read(panel.GetScale,panel)
    if not height or not NS.Number(scale) or scale<=0 then return false end
    local margin=8/scale
    return bounds.bottom+deltaY>=margin+bottomSafeArea(height)/scale and bounds.top+deltaY<=height/scale-margin
end

local function updateStack(side,grew)
    if not NS.UI or NS.InCombat() then return end
    local otherSide=side=="friendly" and "enemy" or "friendly"
    local upper=NS.UI[side].frame
    local lower=NS.UI[otherSide].frame
    if NS.DB[side.."Position"].manual or NS.DB[otherSide.."Position"].manual then
        upper.stackParent,lower.stackParent=nil,nil
        return
    end
    local a,b=panelBounds(upper),panelBounds(lower)
    if not a or not b then return end
    local horizontal=a.left<b.right and a.right>b.left
    -- Both panels share the same configured scale. Keep an automatically moved
    -- lower panel eight local UI units below its parent as row counts change.
    if lower.stackParent==upper then
        if not horizontal then lower.stackParent=nil;return end
        local delta=a.bottom-8-b.top
        if not lower.dragging and canShiftPanel(lower,b,delta) then shiftPanel(otherSide,lower,delta)
        else lower.stackParent=nil end
        return
    end
    if grew and not lower.dragging and upper.stackParent~=lower and horizontal
        and b.top<a.top and a.bottom<b.top and a.top>b.bottom then
        local delta=a.bottom-8-b.top
        if canShiftPanel(lower,b,delta) and shiftPanel(otherSide,lower,delta) then lower.stackParent=upper end
    end
end

local function panelSize(side,limit,columns)
    return PAD*2+TILE_WIDTH*columns+GAP*(columns-1),
        GRID_TOP+math.ceil(limit/columns)*(cellHeight(side)+GAP)-GAP+PAD
end

local function layoutLimit(side,section)
    if section.limit then return section.limit end
    if side=="enemy" then return NS.DB.enemyLimit or 20 end
    return NS.DB.friendlyTab=="party" and 5 or NS.DB.friendlyTab=="raid" and 20 or NS.DB.nearbyLimit or 20
end

local function choosePanelPair(friendlyLimit,enemyLimit,requested,width,height)
    local best
    for friendlyColumns=COLUMNS,math.max(COLUMNS,friendlyLimit) do
        local fw,fh=panelSize("friendly",friendlyLimit,friendlyColumns)
        for enemyColumns=COLUMNS,math.max(COLUMNS,enemyLimit) do
            local ew,eh=panelSize("enemy",enemyLimit,enemyColumns)
            for _,orientation in ipairs({"horizontal","vertical"}) do
                local totalWidth=orientation=="horizontal" and fw+8+ew or math.max(fw,ew)
                local totalHeight=orientation=="horizontal" and math.max(fh,eh) or fh+8+eh
                local scale=requested
                if width and height then
                    scale=math.min(scale,math.max(1,width-16)/totalWidth,
                        math.max(1,height-16-bottomSafeArea(height))/totalHeight)
                end
                local cost=friendlyColumns+enemyColumns+(orientation=="vertical" and .1 or 0)
                if not best or scale>best.scale+.000001 or math.abs(scale-best.scale)<.000001 and cost<best.cost then
                    best={scale=scale,cost=cost,orientation=orientation,
                        friendly={columns=friendlyColumns,width=fw,height=fh},enemy={columns=enemyColumns,width=ew,height=eh}}
                end
            end
        end
    end
    return best
end

local function viewportBounds(panel)
    local bounds=panelBounds(panel)
    local scale=NS.Read(panel.GetScale,panel)
    if not bounds or not NS.Number(scale) then return nil end
    for key,value in pairs(bounds) do bounds[key]=value*scale end
    return bounds
end

local function topLeftPosition(frame,manual,destinationScale)
    local bounds=viewportBounds(frame)
    local _,height=screenSize()
    local scale=destinationScale or NS.Read(frame.GetScale,frame)
    if not bounds or not height or not NS.Number(scale) or scale<=0 then return nil end
    return {point="TOPLEFT",relativePoint="TOPLEFT",x=bounds.left/scale,
        y=(bounds.top-height)/scale,manual=manual==true}
end

local function clampPanelToViewport(panel,width,height)
    local bounds=viewportBounds(panel)
    local scale=NS.Read(panel.GetScale,panel)
    if not bounds or not NS.Number(scale) or scale<=0 then return end
    local dx=bounds.left<0 and -bounds.left or bounds.right>width and width-bounds.right or 0
    local dy=bounds.bottom<0 and -bounds.bottom or bounds.top>height and height-bounds.top or 0
    if math.abs(dx)<.01 and math.abs(dy)<.01 then return end
    local point,relativeTo,relativePoint,x,y=panel:GetPoint()
    if type(point)~="string" or not NS.Number(x) or not NS.Number(y) then return end
    panel:ClearAllPoints()
    panel:SetPoint(point,relativeTo,relativePoint,x+dx/scale,y+dy/scale)
end

local function fitPanelPair(plan,width,height)
    if not width or not height or not NS.DB.shown then return end
    local friendly,enemy=NS.UI.friendly.frame,NS.UI.enemy.frame
    if friendly.dragging or enemy.dragging or not friendly:IsShown() or not enemy:IsShown() then return end
    if NS.DB.friendlyPosition.manual or NS.DB.enemyPosition.manual then
        -- A deliberate drag may overlap the other panel or the action bars.
        -- Respect that placement; only the actual screen edge remains a limit.
        clampPanelToViewport(friendly,width,height)
        clampPanelToViewport(enemy,width,height)
        friendly.stackParent,enemy.stackParent=nil,nil
        return
    end
    local a,b=viewportBounds(friendly),viewportBounds(enemy)
    local function fits(bounds)
        return bounds and bounds.left>=0 and bounds.bottom>=bottomSafeArea(height)
            and bounds.right<=width and bounds.top<=height
    end
    local overlap=a and b and a.left<b.right and a.right>b.left and a.bottom<b.top and a.top>b.bottom
    if fits(a) and fits(b) and not overlap then return end
    local margin=8/plan.scale
    friendly:ClearAllPoints();enemy:ClearAllPoints()
    friendly:SetPoint("TOPLEFT",UIParent,"TOPLEFT",margin,-margin)
    if plan.orientation=="horizontal" then
        enemy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",margin+plan.friendly.width+8,-margin)
    else
        enemy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",margin,-margin-plan.friendly.height-8)
    end
    -- This is a runtime fit. The player's saved positions and desired scale
    -- remain intact; explicit dragging still stores a new player preference.
    friendly.stackParent,enemy.stackParent=nil,nil
end

local function refreshPanelLayouts()
    if not NS.UI or NS.InCombat() then return end
    local width,height=screenSize()
    local viewportKey=width and height and table.concat({width,height},":")
    if viewportKey and NS.UI.viewportKey and NS.UI.viewportKey~=viewportKey
        and (NS.DB.friendlyPosition.manual or NS.DB.enemyPosition.manual) then
        -- UIParent can still have its startup dimensions during ADDON_LOADED.
        -- Undo only the temporary edge clamp when the real viewport arrives;
        -- neither that clamp nor the early geometry is a saved drag location.
        for _,side in ipairs({"friendly","enemy"}) do
            local panel,position=NS.UI[side].frame,NS.DB[side.."Position"]
            if not panel.dragging then
                panel:ClearAllPoints()
                panel:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
                panel.positionKey=table.concat({position.point,position.relativePoint,position.x,position.y},":")
                panel.stackParent=nil
            end
        end
    end
    NS.UI.viewportKey=viewportKey or NS.UI.viewportKey
    local requested=NS.Number(NS.DB.scale) and NS.DB.scale or 1
    local friendlyLimit=layoutLimit("friendly",NS.UI.friendly)
    local enemyLimit=layoutLimit("enemy",NS.UI.enemy)
    local planKey=table.concat({friendlyLimit,enemyLimit,requested,width or 0,height or 0},":")
    local plan=NS.UI.layoutPlan
    if not plan or NS.UI.layoutPlanKey~=planKey then
        plan=choosePanelPair(friendlyLimit,enemyLimit,requested,width,height)
        NS.UI.layoutPlan,NS.UI.layoutPlanKey=plan,planKey
    end
    NS.RuntimeScale=plan.scale
    for _,side in ipairs({"friendly","enemy"}) do
        local section=NS.UI[side]
        local layout=plan[side]
        local panel=section.frame
        local key=table.concat({layoutLimit(side,section),layout.columns,layout.width,layout.height,plan.scale},":")
        panel:SetScale(plan.scale)
        if section.layoutKey~=key and not panel.dragging then
            local oldWidth,oldHeight=panel:GetWidth(),panel:GetHeight()
            local resized=section.hasBound and (oldWidth~=layout.width or oldHeight~=layout.height)
            panel:SetSize(layout.width,layout.height)
            if resized then
                local point,relativeTo,relativePoint,x,y=panel:GetPoint()
                if type(point)=="string" and NS.Number(x) and NS.Number(y) then
                    local vertical=point:find("TOP",1,true) and 0 or point:find("BOTTOM",1,true) and 1 or .5
                    local horizontal=point:find("LEFT",1,true) and 0 or point:find("RIGHT",1,true) and 1 or .5
                    x=x+(layout.width-oldWidth)*horizontal
                    y=y-(layout.height-oldHeight)*vertical
                    panel:ClearAllPoints();panel:SetPoint(point,relativeTo,relativePoint,x,y)
                    local position=NS.DB[side.."Position"]
                    if position.manual and (position.point~="TOPLEFT" or position.relativePoint~="TOPLEFT") then
                        -- Keep legacy BOTTOM/CENTER anchors responsive while
                        -- UIParent finishes loading. Persist only the size delta
                        -- so changing capacity also retains the header on reload.
                        position.x=position.x+(layout.width-oldWidth)*horizontal
                        position.y=position.y-(layout.height-oldHeight)*vertical
                        panel.positionKey=table.concat({position.point,position.relativePoint,position.x,position.y},":")
                    end
                end
            end
            for i,row in ipairs(section.tiles) do
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",PAD+((i-1)%layout.columns)*(TILE_WIDTH+GAP),
                    -GRID_TOP-math.floor((i-1)/layout.columns)*(cellHeight(side)+GAP))
            end
            section.columns,section.layoutKey=layout.columns,key
            if resized then updateStack(side,layout.height>oldHeight) end
        end
    end
    fitPanelPair(plan,width,height)
end

local function button(parent, label, width, action)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetFrameLevel(parent:GetFrameLevel()+3)
    b:SetSize(width or 46, 20)
    background(b, {0.08,0.10,0.13,1}, {0.23,0.28,0.34,1})
    b.label = text(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b:SetScript("OnClick", action)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.65,0.72,0.8,1)
        if self.tipTitle then
            local lines=type(self.tipLines)=="function" and self.tipLines() or self.tipLines
            tooltip(self,self.tipTitle,lines)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(self.active and 0.78 or 0.23,self.active and 0.65 or 0.28,self.active and 0.35 or 0.34,1)
        hideTooltip()
    end)
    return b
end

local function inputShield(row)
    -- A sibling under UIParent remains unprotected even though it covers a secure
    -- button. Anchors and frame level are set once, outside combat lockdown.
    local shield = CreateFrame("Frame", nil, UIParent)
    shield:SetAllPoints(row)
    shield:SetFrameStrata("MEDIUM")
    shield:SetFrameLevel(row:GetFrameLevel() + 8)
    shield:EnableMouse(true)
    shield:SetScript("OnEnter", function()
        NS.HoveredTile=nil
        if NS.EnemyTargetHover then NS.EnemyTargetHover.Clear() end
        if NS.SetHoverUnit then NS.SetHoverUnit(nil) end
    end)
    shield:HookScript("OnEnter",function(self) observeShield(self,row,"target_tile") end)
    shield:HookScript("OnMouseUp",function(self,button) observeShield(self,row,"target_tile",button) end)
    if shield.IsProtected and shield:IsProtected() then
        error("MyForeverTargets input shield must remain unprotected")
    end
    return shield
end

local markSources={}
local OPEN_MARK_MENU = [[
    local menu = self:GetFrameRef("markMenu")
    if not menu then return end
    menu:Hide()
    menu:SetAttribute("unit", nil)
    menu:SetAttribute("source-guid", nil)
    menu:SetAttribute("target-side", nil)
    menu:SetAttribute("source-row", nil)
    menu:SetAttribute("source-owner-guid", nil)
    for i = 0, 8 do
        local mark = menu:GetFrameRef("mark" .. i)
        mark:SetAttribute("unit", nil)
        mark:SetAttribute("source-guid", nil)
        mark:SetAttribute("*type1", nil)
    end
    local row = self:GetFrameRef("row")
    if not row then return end
    local unit = row:GetAttribute("mark-unit") or row:GetAttribute("unit")
    local guid = row:GetAttribute("mark-guid")
    local side = row:GetAttribute("target-side")
    if type(unit) ~= "string" or unit == "" or type(guid) ~= "string" or guid == "" then return end
    menu:SetAttribute("unit", unit)
    menu:SetAttribute("source-guid", guid)
    menu:SetAttribute("target-side", side)
    menu:SetAttribute("source-row", row:GetName())
    menu:SetAttribute("source-owner-guid", row:GetAttribute("mark-owner-guid"))
    for i = 0, 8 do
        local mark = menu:GetFrameRef("mark" .. i)
        mark:SetAttribute("unit", unit)
        mark:SetAttribute("source-guid", guid)
    end
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 5)
    menu:Show()
]]
local MARK_GUARD = [[
    self:SetAttribute("*type1", nil)
    local unit = self:GetAttribute("unit")
    local guid = control:GetAttribute("source-guid")
    if not control:IsShown() or type(unit) ~= "string" or unit == "" or unit ~= control:GetAttribute("unit")
        or type(guid) ~= "string" or guid == ""
        or self:GetAttribute("source-guid") ~= guid then return end
    self:SetAttribute("*type1", "raidtarget")
]]
local MARK_CLOSE = [[control:Hide()]]

local function markSource(menu)
    local unit=NS.Read(menu.GetAttribute,menu,"unit")
    local side=NS.Read(menu.GetAttribute,menu,"target-side")
    local name=NS.Read(menu.GetAttribute,menu,"source-row")
    local row=NS.Public(name) and type(name)=="string" and markSources[name] or nil
    if not row or row.unit~=unit or row.side~=side
        or row.expectedGUID~=observedGUID(NS.Read(menu.GetAttribute,menu,"source-guid"))
        or NS.Read(row.IsVisible,row)~=true
        or not NS.DB or NS.DB.shown==false then return nil end
    if row.bridgeTarget then
        local ownerGUID=observedGUID(NS.Read(menu.GetAttribute,menu,"source-owner-guid"))
        if not ownerGUID or not row.owner or row.owner.expectedGUID~=ownerGUID
            or row.bindingOwnerGUID~=ownerGUID or type(NS.ReadBridgeTarget)~="function" then return nil end
        return NS.ReadBridgeTarget(row)
    end
    if not NS.ValidToken(unit) then return nil end
    return NS.ReadUnit(unit,side)
end

local RESTORE_FOCUS_CLICK = [[
    local command = self:GetAttribute("focus-click-command")
    if type(command) == "string" then
        if self:GetAttribute("*type2") == "macro"
            and self:GetAttribute("*macrotext2") == command then
            self:SetAttribute("*type2", self:GetAttribute("focus-click-type"))
            self:SetAttribute("*macrotext2", self:GetAttribute("focus-click-macro"))
            local unit = self:GetAttribute("focus-click-unit-override")
            if unit and self:GetAttribute("*unit2") == unit then
                self:SetAttribute("*unit2", self:GetAttribute("focus-click-unit"))
            end
        end
        self:SetAttribute("focus-click-command", nil)
        self:SetAttribute("focus-click-type", nil)
        self:SetAttribute("focus-click-macro", nil)
        self:SetAttribute("focus-click-unit", nil)
        self:SetAttribute("focus-click-unit-override", nil)
    end
    if self:GetAttribute("focus-cycle-active") and SecureCmdOptionParse("[combat] blocked") then
        if not self:GetAttribute("focus-cycle-combat-guard") then
            self:SetAttribute("focus-cycle-combat-type", self:GetAttribute("*type2"))
            self:SetAttribute("focus-cycle-combat-macro", self:GetAttribute("*macrotext2"))
            self:SetAttribute("focus-cycle-combat-guard", true)
        end
        self:SetAttribute("*type2", "macro")
        self:SetAttribute("*macrotext2", "/stopmacro")
    elseif self:GetAttribute("focus-cycle-combat-guard") then
        if self:GetAttribute("*type2") == "macro" and self:GetAttribute("*macrotext2") == "/stopmacro" then
            self:SetAttribute("*type2", self:GetAttribute("focus-cycle-combat-type"))
            self:SetAttribute("*macrotext2", self:GetAttribute("focus-cycle-combat-macro"))
        end
        self:SetAttribute("focus-cycle-combat-type", nil)
        self:SetAttribute("focus-cycle-combat-macro", nil)
        self:SetAttribute("focus-cycle-combat-guard", nil)
    end
]]

local focusClickID=0
local function focusRefusalNotice(row,reason)
    local message=reason=="duplicate_name" and "附近有同名怪物，无法确认要设为焦点的是哪一只。请先在场景中选中需要的怪物，再右键此格。"
        or (reason=="identity_unreadable" or reason=="enumeration_unavailable" or reason=="not_unique")
            and "目标信息暂不完整，未更改焦点。请稍后重试，或先选中需要的目标再右键此格。"
        or (reason=="relationship_changed" or reason=="identity_changed")
            and "目标身份已变化，未更改焦点。请等列表刷新后重试。"
    if not message then return end
    local now=NS.Read(GetTime)
    local key=reason..":"..(observedGUID(row.expectedGUID) or "[unreadable]")
    if row.focusNoticeKey==key and (not NS.Number(now) or not NS.Number(row.focusNoticeTime)
        or now-row.focusNoticeTime<3) then return end
    row.focusNoticeKey,row.focusNoticeTime=key,now
    NS.Print(message)
end
local function focusClickObservation(kind,attempt,delay)
    uiObservation(kind,function()
        local fields={attemptID=attempt.id,row=attempt.row,unit=attempt.unit,expectedGUID=attempt.expectedGUID,
            path=attempt.path,reason=attempt.reason,beforeFocusGUID=attempt.beforeFocusGUID,
            beforeTargetGUID=attempt.beforeTargetGUID,beforeTargetExists=attempt.beforeTargetExists,
            focusGUID=observedRead(UnitGUID,"focus"),targetGUID=observedRead(UnitGUID,"target"),
            combat=observedRead(InCombatLockdown),delay=delay or 0}
        fields.focusMatchesExpected=observedGUID(fields.focusGUID)~=nil
            and observedGUID(fields.focusGUID)==observedGUID(attempt.expectedGUID)
        fields.afterFocusGUID,fields.afterTargetGUID=fields.focusGUID,fields.targetGUID
        fields.afterTargetExists=observedRead(UnitExists,"target")
        fields.targetRestored=type(attempt.beforeTargetExists)=="boolean"
            and fields.afterTargetExists==attempt.beforeTargetExists
            and fields.targetGUID==attempt.beforeTargetGUID
            and (observedGUID(fields.targetGUID)~=nil or fields.targetGUID=="[nil]")
        return fields
    end)
end

local function focusName(value)
    if not NS.Public(value) or type(value)~="string" or value=="" or #value>255
        or value:find("[%z\1-\31\127%[%]|;/\\]")
        or value:match("^%s") or value:match("%s$") then return nil end
    return value
end

local function prepareFocusClick(row,button,down)
    if button~="RightButton" or down then return end
    local ctrl=NS.Read(IsControlKeyDown)
    local cycle=NS.FocusCycle
    local cycling=cycle and type(cycle.IsActive)=="function" and NS.Read(cycle.IsActive)==true
    local unit=row.unit
    local compatible=NS.Public(unit) and type(unit)=="string"
        and (unit:match("^nameplate%d+$") or unit:match("^nameplate%d+target$"))
    if (ctrl==true or not compatible or NS.InCombat()) and not uiDiagnostics() and not cycling then
        row.focusClickObservation=nil;return
    end
    focusClickID=focusClickID+1
    local attempt={id=focusClickID,row=observedRead(row.GetName,row),unit=observedValue(row.unit),expectedGUID=observedValue(row.expectedGUID),
        beforeFocusGUID=observedRead(UnitGUID,"focus"),beforeTargetGUID=observedRead(UnitGUID,"target"),
        beforeTargetExists=observedRead(UnitExists,"target"),path="native",reason="stable_unit"}
    row.focusClickObservation=attempt
    local function finish(path,reason,command)
        attempt.path,attempt.reason=path,reason
        if command then
            row:SetAttribute("focus-click-type",row:GetAttribute("*type2"))
            row:SetAttribute("focus-click-macro",row:GetAttribute("*macrotext2"))
            row:SetAttribute("focus-click-command",command)
            if path=="cycle" and cycle and type(cycle.Owns)=="function" and NS.Read(cycle.Owns,row)==true then
                row:SetAttribute("focus-click-unit",row:GetAttribute("*unit2"))
                row:SetAttribute("focus-click-unit-override","player")
                row:SetAttribute("*unit2","player")
            end
            row:SetAttribute("*macrotext2",command)
            row:SetAttribute("*type2","macro")
        end
        focusClickObservation("FOCUS_CLICK_PRE",attempt)
    end
    if ctrl==true then finish("marker","ctrl_right");return end
    if NS.InCombat() then finish("native","out_of_combat_only");return end
    if not row.focusRestoreReady then finish("native","restore_unavailable");return end
    local function refuse(reason)
        finish("blocked",reason,"/stopmacro")
        focusRefusalNotice(row,reason)
    end
    if ctrl~=false then refuse("modifier_unreadable");return end
    if cycling and type(cycle.Prepare)=="function" then
        local data=focusCycleData(row) or row.data
        local command,reason=cycle.Prepare(row,data)
        finish("cycle",reason,command);return
    end
    if not compatible then finish("native","stable_unit");return end
    if NS.Read(row.IsVisible,row)~=true or not NS.DB or NS.DB.shown==false then refuse("hidden");return end
    local expected=observedGUID(row.expectedGUID)
    if not expected or observedGUID(NS.Read(UnitGUID,unit))~=expected then refuse("identity_changed");return end
    local data
    if row.bridgeTarget then
        data=type(NS.ReadBridgeTarget)=="function" and NS.Read(NS.ReadBridgeTarget,row) or nil
    elseif NS.ValidToken(unit) then data=NS.Read(NS.ReadUnit,unit,row.side) end
    if type(data)~="table" or observedGUID(data.guid)~=expected then refuse("invalid_relationship");return end
    if observedGUID(attempt.beforeFocusGUID)==expected then finish("keep_focus","already_focus","/stopmacro");return end
    local targetGUID=observedGUID(attempt.beforeTargetGUID)
    local hasTarget=attempt.beforeTargetExists
    if type(hasTarget)~="boolean" or hasTarget and not targetGUID
        or not hasTarget and attempt.beforeTargetGUID~="[nil]" then refuse("target_state_unreadable");return end
    if targetGUID==expected then
        finish("current_target","prepared","/stopmacro [combat]\n/focus [@target,exists]");return
    end
    if not NS.Public(data.player) or type(data.player)~="boolean" then refuse("player_state_unreadable");return end
    if data.player==false then
        local cast=NS.NearbyCast
        local unique,reason=NS.Read(cast and cast.KnownUniqueNPC,data,row)
        if unique~=true then
            if row.side=="enemy" and not row.bridgeTarget and unit:match("^nameplate%d+$")
                and cycle and type(cycle.Prepare)=="function" then
                local command,cycleReason=cycle.Prepare(row,data)
                finish("cycle",cycleReason,command);return
            end
            refuse(NS.Public(reason) and type(reason)=="string" and reason or "not_unique");return
        end
    end
    local name=focusName(data.targetName)
    if not name then refuse("invalid_name");return end
    local command=table.concat({"/stopmacro [combat]","/cleartarget [nocombat]",
        "/targetexact [nocombat] "..name,"/focus [@target,exists]",
        hasTarget and "/targetlasttarget" or "/cleartarget"},"\n")
    if #command>1023 then refuse("macro_too_long");return end
    finish(hasTarget and "name_restore_target" or "name_restore_empty","prepared",command)
end

local function observeFocusPost(row,button,down)
    if button~="RightButton" or down then return end
    local attempt=row.focusClickObservation
    row.focusClickObservation=nil
    if attempt then
        focusClickObservation("FOCUS_CLICK_POST",attempt)
        if attempt.path~="marker" and attempt.path~="blocked"
            and uiDiagnostics() and C_Timer and type(C_Timer.After)=="function" then
            pcall(C_Timer.After,.1,function() focusClickObservation("FOCUS_CLICK_READBACK",attempt,.1) end)
        end
    end
    local cycle=NS.FocusCycle
    if cycle and type(cycle.AfterClick)=="function" then cycle.AfterClick(row) end
end

function NS.SetupClickActions(row,menu)
    menu=menu or NS.MarkerMenu
    if not row or not menu or row.markController then return end
    row:SetAttribute("*type2","focus")
    row:SetAttribute("*clickbutton2",nil)
    -- Keep native OnClick intact; only Ctrl-right clicks reach the old palette.
    local name=row:GetName()
    row.markController=CreateFrame("Button",name and name.."MarkController" or nil,row,"SecureHandlerClickTemplate")
    row.markController:SetSize(1,1)
    row.markController:SetPoint("TOPLEFT",0,0)
    row.markController:EnableMouse(false)
    row.markController:RegisterForClicks("AnyUp")
    SecureHandlerSetFrameRef(row.markController,"row",row)
    SecureHandlerSetFrameRef(row.markController,"markMenu",menu)
    row.markController:SetAttribute("_onclick",OPEN_MARK_MENU)
    row.markController:HookScript("OnClick",function(_,button,down) observeRow("MARK_CONTROLLER_CLICK",row,button,down) end)
    for _,modifier in ipairs({"ctrl-","alt-ctrl-","ctrl-shift-","alt-ctrl-shift-"}) do
        row:SetAttribute(modifier.."type2","click")
        row:SetAttribute(modifier.."clickbutton2",row.markController)
    end
    if type(SecureHandlerWrapScript)=="function" then
        SecureHandlerWrapScript(row,"PreClick",row,RESTORE_FOCUS_CLICK)
        SecureHandlerWrapScript(row,"PostClick",row,RESTORE_FOCUS_CLICK)
        row.focusRestoreReady=true
        row:HookScript("PreClick",prepareFocusClick)
        row:HookScript("PostClick",observeFocusPost)
    end
    if row.bridgeTarget then
        row:HookScript("PreClick",function(self,button,down) observeRow("UI_TILE_PRECLICK",self,button,down) end)
        row:HookScript("PostClick",function(self,button,down) observeRow("UI_TILE_POSTCLICK",self,button,down) end)
    end
    if name then markSources[name]=row end
end

local function createMarkMenu()
    local menu = CreateFrame("Frame", "MyForeverTargetsMarkMenu", UIParent, "SecureHandlerBaseTemplate,BackdropTemplate")
    menu:SetSize(292,96)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    background(menu, {0.045,0.055,0.075,0.99}, {0.7,0.59,0.33,1})
    menu.title = text(menu,12)
    menu.title:SetPoint("TOPLEFT",12,-12)
    menu.title:SetWidth(245)
    menu.title:SetJustifyH("LEFT")
    menu.title:SetText("为此目标打标记")
    menu.note = text(menu,10,{0.72,0.76,0.82,1})
    menu.note:SetPoint("BOTTOMLEFT",12,11)
    menu.note:SetText("团队标记由游戏检查权限")
    menu.markers = {}
    -- BackdropTemplate has its own OnLoad, so the helper methods installed by
    -- SecureHandler_OnLoad are not guaranteed on a multi-template frame.
    SecureHandlerSetFrameRef(menu,"markMenu",menu)
    for i=0,8 do
        local mark = CreateFrame("Button", "MyForeverTargetsMark" .. i, menu, "SecureActionButtonTemplate,BackdropTemplate")
        mark.nativeClick=mark:GetScript("OnClick")
        mark.nativeHandlerWasPresent=mark.nativeClick~=nil
        mark:SetSize(28,30)
        mark:SetPoint("TOPLEFT",12+i*30,-35)
        background(mark, {0.08,0.1,0.14,1})
        mark:RegisterForClicks("AnyUp")
        mark:SetAttribute("useOnKeyDown", false)
        mark:SetAttribute("*type1", nil)
        mark:SetAttribute("*marker1", i)
        mark:SetAttribute("*action1", i == 0 and "clear" or "set")
        mark:HookScript("PreClick",function(self,button,down) observeMarkerPre(self,menu,button,down) end)
        mark:HookScript("PostClick",function(self,button,down) observeMarkerPost(self,menu,button,down) end)
        if i == 0 then
            mark.label = text(mark,11)
            mark.label:SetPoint("CENTER")
            mark.label:SetText("清")
        else
            mark.icon = mark:CreateTexture(nil,"ARTWORK")
            mark.icon:SetSize(22,22)
            mark.icon:SetPoint("CENTER")
            icon(mark.icon,i)
        end
        local markName = i == 0 and "清除标记" or MARK_NAMES[i]
        mark:SetScript("OnEnter", function(self) tooltip(self,markName,{"对打开菜单时的目标操作，不切换当前目标。"}) end)
        mark:SetScript("OnLeave",hideTooltip)
        if SecureHandlerWrapScript then
            SecureHandlerWrapScript(mark,"PreClick",menu,MARK_GUARD)
            SecureHandlerWrapScript(mark,"PostClick",menu,MARK_CLOSE)
        end
        SecureHandlerSetFrameRef(menu,"mark" .. i,mark)
        menu.markers[i] = mark
    end
    local close = CreateFrame("Button", "MyForeverTargetsMarkClose", menu, "SecureHandlerClickTemplate")
    close:SetSize(22,22)
    close:SetPoint("TOPRIGHT",-6,-5)
    close.label=text(close,15);close.label:SetPoint("CENTER");close.label:SetText("×")
    close:SetAttribute("_onclick", [[self:GetParent():Hide()]])
    close:RegisterForClicks("AnyUp")
    menu.close=close
    -- Invalidating a menu does not mutate its protected visibility in combat.
    -- Its unprotected shield blocks the palette but leaves the secure close X free.
    menu.shield=CreateFrame("Frame",nil,UIParent)
    menu.shield:SetPoint("TOPLEFT",menu,"TOPLEFT",5,-29)
    menu.shield:SetPoint("BOTTOMRIGHT",menu,"BOTTOMRIGHT",-5,5)
    menu.shield:SetFrameStrata("DIALOG")
    menu.shield:SetFrameLevel(menu:GetFrameLevel()+10)
    menu.shield:EnableMouse(true)
    menu.shield:HookScript("OnEnter",function(self) observeShield(self,nil,"mark_menu") end)
    menu.shield:HookScript("OnMouseUp",function(self,button) observeShield(self,nil,"mark_menu",button) end)
    if menu.shield.IsProtected and menu.shield:IsProtected() then
        error("MyForeverTargets marker shield must remain unprotected")
    end
    menu.shield.cover=menu.shield:CreateTexture(nil,"BACKGROUND")
    menu.shield.cover:SetAllPoints(menu.shield)
    menu.shield.cover:SetTexture(WHITE)
    menu.shield.cover:SetVertexColor(.045,.055,.075,.98)
    menu.shield.message=text(menu.shield,12,{1,0.76,0.42,1})
    menu.shield.message:SetPoint("CENTER")
    menu.shield.message:SetText("目标已变化，请重新 Ctrl+右键")
    menu.shield:Hide()
    menu:SetScript("OnShow",function(self)
        local data=markSource(self)
        self.sourceGUID=observedGUID(NS.Read(self.GetAttribute,self,"source-guid"))
        local valid=data and self.sourceGUID and observedGUID(data.guid)==self.sourceGUID
        self.title:SetText(valid and ("标记 · " .. data.name) or "目标已失效")
        shown(self.shield, not valid)
    end)
    menu:SetScript("OnHide",function(self)self.sourceGUID=nil;self.shield:Hide();hideTooltip()end)
    menu:HookScript("OnShow",function(self)
        uiObservation("MARK_MENU_OPEN",function()
            local fields=menuObservation(self)
            local unit=NS.Read(self.GetAttribute,self,"unit")
            fields.unitExists,fields.unitHarm,fields.unitHelp=observedRead(UnitExists,unit),
                observedRead(UnitCanAttack,"player",unit),observedRead(UnitCanAssist,"player",unit)
            fields.inRaid,fields.inGroup=observedRead(IsInRaid),observedRead(IsInGroup)
            fields.playerLeader,fields.playerAssistant=observedRead(UnitIsGroupLeader,"player"),observedRead(UnitIsGroupAssistant,"player")
            fields.recipientProven=false
            return fields
        end)
    end)
    menu:Hide()
    NS.MarkerMenu=menu
    return menu
end

function NS.InvalidateMarkMenu()
    local menu=NS.MarkerMenu
    if not menu or not menu:IsShown() then return end
    local data=markSource(menu)
    local valid=data and menu.sourceGUID and observedGUID(data.guid) == menu.sourceGUID
    shown(menu.shield, not valid)
end

function NS.CloseMarkMenu()
    if NS.MarkerMenu and not NS.InCombat() then NS.MarkerMenu:Hide() end
end

function NS.StopDragging()
    if not NS.UI then return end
    for _,side in ipairs({"friendly","enemy"}) do
        local p=NS.UI[side].frame
        if p.dragProxy then p.dragProxy:StopMovingOrSizing();p.dragProxy:Hide() end
        p.dragging=false
    end
end

local function createTile(panel,side,index,menu)
    -- Leave the XML-installed native action handler untouched. TargetUnit in
    -- Forever requires this direct hardware-click path, without a Lua wrapper.
    local row=CreateFrame("Button","MyForeverTargets" .. side .. index,panel,
        "SecureActionButtonTemplate,BackdropTemplate")
    row:SetSize(TILE_WIDTH,TILE_HEIGHT)
    row.side,row.index=side,index
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown",false)
    row:SetAttribute("target-side",side)
    row:SetAttribute("*type1","target")
    row.nativeHandlerWasPresent=row:GetScript("OnClick")==SecureActionButton_OnClick
    NS.SetupClickActions(row,menu)
    background(row,{0.035,0.045,0.06,1},{0.24,0.29,0.35,1})
    row.health=CreateFrame("StatusBar",nil,row)
    row.health:EnableMouse(false)
    row.health:SetPoint("TOPLEFT",3,-3)
    row.health:SetPoint("BOTTOMRIGHT",-3,3)
    row.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.health:SetOrientation("HORIZONTAL")
    row.health:SetMinMaxValues(0,1)
    row.health:SetValue(0)
    -- Child frames draw above parent layers: keep the scrim, labels and accents
    -- together above the health child rather than behind its fill.
    row.labels=CreateFrame("Frame",nil,row)
    row.labels:SetAllPoints(row)
    row.labels:SetFrameLevel(row.health:GetFrameLevel()+1)
    row.labels:EnableMouse(false)
    row.scrim=row.labels:CreateTexture(nil,"BACKGROUND")
    row.scrim:SetPoint("TOPLEFT",4,-4)
    row.scrim:SetPoint("BOTTOMRIGHT",-4,4)
    row.scrim:SetTexture(WHITE)
    row.scrim:SetVertexColor(0.015,0.02,0.028,0.16)
    row.powerTrack=CreateFrame("Frame",nil,row.labels)
    row.powerTrack:SetPoint("BOTTOMLEFT",4,3)
    row.powerTrack:SetPoint("BOTTOMRIGHT",-4,3)
    row.powerTrack:SetHeight(4)
    row.powerTrack:EnableMouse(false)
    row.powerTrack.background=row.powerTrack:CreateTexture(nil,"BACKGROUND")
    row.powerTrack.background:SetAllPoints(row.powerTrack)
    row.powerTrack.background:SetTexture(WHITE)
    row.powerTrack.background:SetVertexColor(.015,.02,.03,.95)
    row.power=CreateFrame("StatusBar",nil,row.powerTrack)
    row.power:SetHeight(4)
    row.power:SetAllPoints(row.powerTrack)
    row.power:EnableMouse(false)
    row.power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.power:SetOrientation("HORIZONTAL")
    row.power:SetMinMaxValues(0,1)
    row.power:SetValue(0)
    row.power:Hide();row.powerTrack:Hide()
    row.topline=row.labels:CreateTexture(nil,"OVERLAY")
    row.topline:SetTexture(WHITE)
    row.topline:SetPoint("TOPLEFT",4,-1)
    row.topline:SetPoint("TOPRIGHT",-4,-1)
    row.topline:SetHeight(1)
    row.topline:SetVertexColor(0.24,0.29,0.35,1)
    row.nameText=text(row.labels,10)
    row.nameText:SetPoint("TOPLEFT",10,-3)
    row.nameText:SetPoint("TOPRIGHT",-10,-3)
    row.nameText:SetHeight(12)
    row.nameText:SetWordWrap(false)
    row.nameText:SetJustifyH("CENTER")
    row.classText=text(row.labels,9)
    row.classText:SetPoint("TOPLEFT",4,-31)
    row.classText:SetPoint("TOPRIGHT",-4,-31)
    row.classText:SetHeight(9)
    row.classText:SetJustifyH("CENTER")
    row.classText:SetWordWrap(false)
    row.statusText=text(row.labels,8,{0.85,0.88,0.92,1})
    row.statusText:SetPoint("TOPRIGHT",-4,-16)
    row.statusText:SetSize(24,8)
    row.statusText:SetJustifyH("RIGHT")
    if NS.Auras and type(NS.Auras.Create)=="function" then
        row.auras=NS.Auras.Create(row.labels,false)

    end
    row.indexText=text(row.labels,11,{0.35,0.4,0.47,1})
    row.indexText:SetPoint("CENTER")
    row.indexText:SetText(string.format("%02d",index))
    row.marker=row.labels:CreateTexture(nil,"OVERLAY")
    row.marker:SetSize(8,8)
    row.marker:SetPoint("TOPRIGHT",0,0)
    row.marker:Hide()
    row.targetFill=row.labels:CreateTexture(nil,"BACKGROUND",nil,1)
    row.targetFill:SetTexture(WHITE)
    row.targetFill:SetAllPoints(row)
    row.targetFill:SetVertexColor(1,.20,.10,.14)
    row.targetFill:Hide()
    NS.CreateIdentityBorders(row,row.labels)
    row.targetBadge=CreateFrame("Frame",nil,row.labels)
    row.targetBadge:SetSize(22,8)
    row.targetBadge:SetPoint("TOPLEFT",4,-16)
    row.targetBadge:EnableMouse(false)
    row.targetBadge.fill=row.targetBadge:CreateTexture(nil,"BACKGROUND")
    row.targetBadge.fill:SetAllPoints(row.targetBadge)
    row.targetBadge.fill:SetTexture(WHITE)
    row.targetBadge.fill:Hide()
    row.targetBadge.label=text(row.targetBadge,8,{1,.86,.40,1})
    local badgeFont=row.targetBadge.label:GetFont()
    if badgeFont then row.targetBadge.label:SetFont(badgeFont,8,"") end
    row.targetBadge.label:SetShadowColor(0,0,0,.45)
    row.targetBadge.label:SetShadowOffset(0,-1)
    row.targetBadge.label:SetPoint("CENTER")
    row.targetBadge.label:SetText("当前")
    row.targetBadge:Hide()
    row.questBadge=CreateFrame("Frame",nil,row.labels)
    row.questBadge:SetSize(8,8)
    row.questBadge:SetPoint("TOPLEFT",0,0)
    row.questBadge:EnableMouse(false)
    row.questBadge.fill=row.questBadge:CreateTexture(nil,"BACKGROUND")
    row.questBadge.fill:SetAllPoints(row.questBadge)
    row.questBadge.fill:SetTexture(WHITE)
    row.questBadge.fill:SetVertexColor(1,.79,.18,1)
    row.questBadge.label=text(row.questBadge,8,{.13,.08,.005,1})
    row.questBadge.label:SetPoint("CENTER",0,0)
    row.questBadge.label:SetText("!")
    row.questBadge:Hide()
    row.hover=row.labels:CreateTexture(nil,"OVERLAY")
    row.hover:SetTexture(WHITE)
    row.hover:SetPoint("TOPLEFT",4,-4)
    row.hover:SetPoint("BOTTOMRIGHT",-4,4)
    row.hover:SetVertexColor(1,0.9,0.5,0.13)
    row.hover:Hide()
    row.shield=inputShield(row)
    local function showUnitTooltip(self,data)
        local distance="距离未知"
        if NS.MeasureDistance and NS.DistanceText then distance=NS.DistanceText(NS.MeasureDistance(self.unit)) end
        self.tooltipDistance=distance
        self.tooltipName=data.name
        self.tooltipCombat=NS.InCombat()
        self.tooltipFocusCycle=focusCycleStatus(self)
        self.tooltipQuest=self.side == "enemy" and not data.player and data.questTarget == true
        self.tooltipQuestTitle=data.questTitle
        local combatStatus,combatStatusKey=combatCastStatus(self)
        self.tooltipCombatStatus=combatStatusKey
        local lines={data.player and (data.className or "玩家") or "怪物",distance}
        lines[#lines+1]="主格上排为本人施加的增益，下排为本人施加的减益及友方本人可驱散的减益；黄点为可驱散，效果过多时用滚轮浏览。"
        if self.side=="enemy" then
            readEnemyTarget(self)
            self.tooltipEnemyTarget=enemyTargetTooltip(self)
            lines[#lines+1]=self.tooltipEnemyTarget
            lines[#lines+1]=legacyBridge(self.side) and
                "下方长方形显示敌人的目标；脱战悬停该条，可按与目标敌友关系相符的普通技能键。" or
                "下方长方形显示敌人的目标姓名、职业和血量；目标为友方时，在该条使用自己的治疗悬停宏。"
        end
        if self.tooltipQuest then
            lines[#lines+1]="任务目标" .. (data.questTitle and data.questTitle ~= "" and (" · " .. data.questTitle) or "")
        end
        lines[#lines+1]="左键选中 · 右键设为焦点 · Ctrl+右键打标记"
        lines[#lines+1]="红框为当前目标，黄框为焦点。"
        if self.unit and self.unit:match("^nameplate%d+$") then
            lines[#lines+1]="附近目标的右键焦点兼容仅脱战：短暂选中后设焦点，再按进度恢复原目标。"
        end
        if self.side == "enemy" and not data.player and self.unit and self.unit:match("^nameplate%d+$") then
            lines[#lines+1]="同名怪物可重复右键同一格：每次查找一只，身份吻合后设焦点，再按提示继续恢复原目标。"
            lines[#lines+1]=NS.PreserveCastTarget and "左键名称选择不能保证同名怪物的具体个体。" or
                "按完整名称选中；同名怪物可能无法区分具体一只。"
        end
        if self.tooltipFocusCycle then lines[#lines+1]="焦点进度："..self.tooltipFocusCycle end
        lines[#lines+1]=combatPreparationLine(combatStatus)
        if not NS.PreserveCastTarget and self.side=="enemy" and not data.player and combatStatus.prepared then
            lines[#lines+1]="怪物准备只检查已发现目标，无法保证战斗中的GUID或新出现的同名怪物。"
        end
        local castInstruction
        if legacyBridge(self.side) then
            castInstruction="脱战悬停后按原普通技能键：友方接治疗／增益，敌方接攻击；内部临时选中此单位、施法并恢复原目标。移开或入战交还原键；已有宏和物品不接管。"
        elseif NS.NativeMacroOnly then
            castInstruction="悬停方块后，按原 @mouseover 宏的原按键。保留原宏写法与后备分支；插件不改变当前目标。鼠标单位未确认时，宏可能回退当前目标。"
        elseif NS.PreserveCastTarget then
            if self.side=="enemy" and not data.player then
                castInstruction="悬停此方块后按原普通伤害技能键，按该怪物 GUID 直施尝试；同名也按 GUID 区分，不切换当前目标。需满足技能距离、朝向及冷却。宏和物品不接入。"
            elseif combatStatus.reason=="native_unit" then
                castInstruction="悬停后按原治疗／增益技能键，使用客户端原生悬停施法；当前目标保持。"
            elseif self.side=="friendly" then
                castInstruction="附近玩家使用原生悬停路径，需客户端正确识别鼠标单位；实际施法仍待验证。当前目标保持。"
            else
                castInstruction="敌方玩家尚未接入GUID直施尝试；保留原生悬停路径，需客户端识别鼠标单位。当前目标保持。"
            end
        elseif self.tooltipCombat then
            if combatStatus.prepared then
                castInstruction="悬停后按战前已准备的原技能键；未准备或不支持的按键仍执行原动作。需满足技能距离、朝向及冷却。"
            elseif combatStatus.reason=="native_unit" then
                castInstruction="此单位使用原生悬停施法，需客户端正确识别鼠标单位。"
            else
                castInstruction="此格当前没有已准备的战斗按键；原按键仍执行原动作，可能作用于当前目标。新增目标与技能需脱战后准备。"
            end
        elseif self.targetByName and self.side == "friendly" then
            castInstruction="附近玩家：非战斗时，悬停后按原动作条治疗／增益技能键；内部短暂切换目标。用户宏和物品保持原行为。"
        elseif self.side=="enemy" then
            if data.player then
                castInstruction="敌方玩家：非战斗时支持原伤害技能键及单 /cast 宏，保留原修饰键；内部会短暂切换目标。需满足技能距离、朝向及冷却。"
            else
                castInstruction="非战斗时，已发现无重名的怪物可悬停后按原伤害技能键；同名怪物请先在游戏世界中选中对应目标，再悬停此块施法。需满足技能距离、朝向及冷却。"
            end
        else
            castInstruction=self.targetByName and "悬停施法需客户端支持此姓名板目标。"
                or "开启悬停施法后，悬停此块并按原有技能键。"
        end
        unitTooltip(self,data.name,lines,castInstruction)

    end
    row.showUnitTooltip=showUnitTooltip
    local function showUnitHover(self)
        local current=NS.ReadUnit(self.unit,self.side)
        local data=focusCycleData(self) or current
        if not data or data.guid ~= self.expectedGUID then return false end
        if NS.EnemyTargetHover then NS.EnemyTargetHover.Clear() end
        NS.HoveredTile=self
        self.hover:Show()
        if NS.SetHoverUnit then
            if current and current.guid==self.expectedGUID then NS.SetHoverUnit(self.unit,self.side)
            else NS.SetHoverUnit(nil) end
        end
        showUnitTooltip(self,data)
        return true
    end
    row.showUnitHover=showUnitHover
    row:SetScript("OnEnter",showUnitHover)
    row:SetScript("OnLeave",function(self)
        self.hover:Hide()
        if NS.HoveredTile == self then
            NS.HoveredTile=nil
            if NS.SetHoverUnit then NS.SetHoverUnit(nil) end
        end
        hideTooltip()
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel",function(self,delta)
        if self.auras and NS.Auras and type(NS.Auras.Scroll)=="function" then NS.Auras.Scroll(self.auras,delta) end
    end)
    row:HookScript("OnHide",function(self)
        self.shield:Hide()
        if self.auras and NS.Auras and type(NS.Auras.Update)=="function" then NS.Auras.Update(self.auras) end
    end)
    row:HookScript("OnEnter",function(self) observeRow("UI_TILE_ENTER",self) end)
    row:HookScript("OnLeave",function(self) observeRow("UI_TILE_LEAVE",self) end)
    row:HookScript("PreClick",function(self,button,down) observeRow("UI_TILE_PRECLICK",self,button,down) end)
    row:HookScript("PostClick",function(self,button,down) observeRow("UI_TILE_POSTCLICK",self,button,down) end)
    row.nativeClick=row:GetScript("OnClick")
    if side=="enemy" and NS.EnemyTargetHover then NS.EnemyTargetHover.Create(row) end
    if (not NS.NativeMacroOnly or legacyBridge(side)) and NS.NearbyCast then NS.NearbyCast.Install(row) end
    return row
end

local function makePanel(side,menu)
    local p=CreateFrame("Frame","MyForeverTargets" .. side .. "Panel",UIParent,"BackdropTemplate")
    p:SetFrameStrata("MEDIUM")
    p:SetSize(WIDTH,GRID_TOP+cellHeight(side)*4+GAP*3+PAD)
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    background(p)
    p.title=text(p,11,{0.93,0.85,0.65,1})
    p.title:SetPoint("TOPLEFT",PAD+2,-7)
    p.title:SetText(side == "friendly" and "友方" or "敌方")
    local section={side=side,frame=p,tiles={},tabs={},limits={}}
    -- Move only an unprotected outline during the gesture. If combat starts
    -- midway, cancelling this proxy never moves/stops a protected unit frame.
    local proxy=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    proxy:SetFrameStrata("DIALOG")
    proxy:SetMovable(true)
    proxy:SetClampedToScreen(true)
    proxy:EnableMouse(false)
    background(proxy,{.08,.1,.14,.24},{.95,.78,.4,1})
    proxy.caption=text(proxy,14,{1,.87,.57,1})
    proxy.caption:SetPoint("CENTER")
    proxy.caption:SetText("释放鼠标以移动")
    proxy:Hide()
    p.dragProxy=proxy
    p:SetScript("OnHide",function()
        if p.dragging then proxy:StopMovingOrSizing() end
        proxy:Hide()
        p.dragging=false
        hideTooltip()
    end)
    local drag=CreateFrame("Frame",nil,p)
    drag:SetFrameLevel(p:GetFrameLevel()+1)
    drag:SetPoint("TOPLEFT",0,0)
    drag:SetPoint("TOPRIGHT",0,0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function()
        if NS.InCombat() or NS.DB.locked then return end
        p.stackParent=nil
        local other=NS.UI and NS.UI[side=="friendly" and "enemy" or "friendly"]
        if other then other.frame.stackParent=nil end
        local point,relativeTo,relativePoint,x,y=p:GetPoint()
        proxy:SetScale(p:GetScale())
        proxy:SetSize(p:GetWidth(),p:GetHeight())
        proxy:ClearAllPoints()
        proxy:SetPoint(point,relativeTo,relativePoint,x,y)
        p.dragging=true
        proxy:Show()
        proxy:StartMoving()
    end)
    drag:SetScript("OnDragStop",function()
        if not p.dragging then return end
        proxy:StopMovingOrSizing()
        local position=not NS.InCombat() and topLeftPosition(proxy,true,NS.Read(p.GetScale,p)) or nil
        proxy:Hide()
        p.dragging=false
        if not position or NS.InCombat() then return end
        -- Native dragging can return CENTER/BOTTOM anchors. Persist the actual
        -- top-left corner so later capacity changes and reload agree on it.
        -- Snapshot the other real panel too: pair fitting may have moved it
        -- away from its old saved anchor before this first manual placement.
        local otherSide=side=="friendly" and "enemy" or "friendly"
        local other=NS.UI and NS.UI[otherSide]
        local otherPosition=other and not other.frame.dragging
            and topLeftPosition(other.frame,NS.DB[otherSide.."Position"].manual) or nil
        if otherPosition then
            NS.DB[otherSide.."Position"]=otherPosition
            other.frame.positionKey=nil
        end
        p:ClearAllPoints()
        p:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
        NS.DB[side .. "Position"]=position
        p.positionKey=nil
    end)
    section.drag=drag
    section.ShowHelp=function(anchor)
        local lines={side=="friendly" and "只显示玩家；团队20格，小队5格，附近可选5／10／20格。" or
            "显示敌对玩家与怪物，可选5／10／20格。",
            "当前可用 " .. (section.validCount or 0) .. " 个，最多 " .. (section.limit or 20) .. " 格。",
            "左键选中 · 右键设为焦点 · Ctrl+右键打标记 · 悬停后按原有技能键。",
            "红框为当前目标，黄框为焦点。",
            "附近目标的右键焦点兼容仅脱战，临时选中后恢复原目标；重复右键保留焦点。"}
        if side=="enemy" or NS.DB.friendlyTab=="nearby" then
            lines[#lines+1]="附近目标按距离由近到远；距离未知的排在后面。"
        end
        if legacyBridge(side) then
            lines[#lines+1]="仅脱战：悬停后按普通技能键，临时选中、施法，再恢复原目标。"
        elseif NS.PreserveCastTarget and side=="enemy" then
            lines[#lines+1]="悬停怪物后按原普通技能键做GUID直施尝试；不切换当前目标，实际施法待验证。"
        end
        lines[#lines+1]="整格填充是血量；底部细条显示法力、能量、怒气等资源。"
        lines[#lines+1]="只有主格显示本人的增益、减益及友方本人可驱散的减益；敌人的目标条不显示光环。"
        lines[#lines+1]=NS.InCombat() and "战斗中固定名单，设置会在脱战后应用。" or
            "拖动标题可移动窗口；点锁按钮固定位置。"
        tooltip(anchor or drag,side=="friendly" and "友方目标" or "敌方目标",lines)
    end
    -- Only the header's existing drag surface owns this tooltip. It ends above
    -- the grid and never intercepts mouse motion/clicks on the unit buttons.
    drag:SetScript("OnEnter",function(self) section.ShowHelp(self) end)
    drag:SetScript("OnLeave",hideTooltip)
    section.close=button(p,"×",20,function()
        NS.SetPanelShown(side,false)
    end)
    p.closeButton=section.close
    section.close:SetPoint("TOPRIGHT",-PAD,-3)
    section.close.tipTitle=side=="friendly" and "关闭友方面板" or "关闭敌方面板"
    section.close.tipLines={"只关闭这一侧面板；点击目标选择图标可重新打开。",
        "战斗中会记住设置，脱战后关闭。"}
    section.lock=button(p,"锁",22,function()
        NS.ApplySetting("locked",not NS.DB.locked)
    end)
    section.lock:SetPoint("TOPRIGHT",-(PAD+24),-3)
    section.lock.tipTitle="移动与锁定"
    section.lock.tipLines=function()
        return {NS.DB.locked and "窗口位置已锁定；点击后可拖动标题移动。" or
            "可拖动标题移动；点击后锁定位置。"}
    end
    if side == "friendly" then
        for i,entry in ipairs(MODES) do
            local mode,label=entry[1],entry[2]
            local b=button(p,label,28,function() NS.ApplySetting("friendlyTab",mode) end)
            b:SetPoint("TOPLEFT",34+(i-1)*30,-3)
            b.mode=mode;section.tabs[mode]=b
            b.tipTitle=label
            b.tipLines={mode=="raid" and "团队玩家，固定20格。" or mode=="party" and
                "自己与小队玩家，固定5格。" or "附近可见玩家，可选5／10／20格；按距离排序。"}
        end
    end
    for i,n in ipairs({5,10,20}) do
        local limit=n
        local b=button(p,tostring(n),22,function()
            NS.ApplySetting(side == "friendly" and "nearbyLimit" or "enemyLimit",limit)
        end)
        b:SetPoint("TOPLEFT",(side=="friendly" and 132 or 36)+(i-1)*24,-3)
        if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
        b.tipTitle=tostring(limit) .. "格"
        b.tipLines=function()
            if side=="friendly" and NS.DB.friendlyTab~="nearby" then
                return {NS.DB.friendlyTab=="raid" and "团队固定20格。" or "小队固定5格。",
                    "切到附近页后，可选择5／10／20格。"}
            end
            return {"最多显示" .. limit .. "个可见目标；附近目标按距离排序。"}
        end
        section.limits[n]=b
    end
    section.mouseover=button(p,NS.NativeMacroOnly and "宏" or "施法",38,function(self)
        if legacyBridge(side) then
            NS.ApplySetting("legacyNameBridgeEnabled",not NS.DB.legacyNameBridgeEnabled)
            return
        end
        if NS.NativeMacroOnly then
            tooltip(self,"原生悬停宏",self.tipLines())
            return
        end
        if NS.SetMouseoverEnabled and NS.MouseoverStatus then
            local enabled=NS.MouseoverStatus()
            NS.SetMouseoverEnabled(not enabled)
        end
    end)
    section.mouseover:SetPoint("TOPRIGHT",-(PAD+50),-3)
    section.mouseover.tipTitle="悬停施法"
    section.mouseover.tipLines=function()
        if legacyBridge(side) then
            return {"友方、敌方及下方目标条：脱战悬停后按原普通技能键。",
                "临时选中悬停单位、施法，再恢复原目标；原来无目标则恢复为空。",
                "友方接治疗／增益、敌方接伤害；已有宏、物品及其他插件占用的键保持原行为。",
                "移开、隐藏或入战会交还原键。同名怪物无法确认唯一时不准备名称施法。",
                NS.DB.legacyNameBridgeEnabled and "点击关闭普通技能悬停兼容。" or "点击开启普通技能悬停兼容。"}
        end
        if NS.NativeMacroOnly then
            return {"悬停目标方块，按原 @mouseover 宏的原按键；原宏和当前目标保持。",
                "敌对宏写法示例（将技能名换成角色已学且可用的技能）：",
                "/cast [@mouseover,nodead,harm] 恐惧术; 恐惧术;",
                "友方宏使用 help 条件；宏中的后备分支仍按原写法执行。",
                "目标浮层显示实际鼠标单位与宏条件。未确认时，宏可能回退当前目标。"}
        end
        local enabled,status=false,nil
        if NS.MouseoverStatus then enabled,status=NS.MouseoverStatus() end
        if NS.PreserveCastTarget then
            return {status or "悬停方块后，按原动作条技能键。",enabled and "点击关闭悬停施法。" or "点击开启悬停施法。",
                "普通敌方怪物方块：按原普通技能键做GUID直施尝试；同名按GUID区分，不切换当前目标。",
                "GUID直施尚待实测；宏和物品保持原行为。新目标或技能需脱战后准备。",
                "自己／小队／团队保留原生悬停路径；附近玩家和敌方玩家仍需客户端正确识别鼠标单位。"}
        end
        return {status or "悬停方块后，按原动作条技能键。",enabled and "点击关闭悬停施法。" or "点击开启悬停施法。",
            "附近玩家和敌方目标可在脱战时准备支持的原技能键；战斗中仅沿用战前名称和动作，新目标或不支持的技能不能临时接入。",
            "同名或唯一性未知的怪物不准备；未发现的重名和战斗中的GUID无法精确保证。具体准备状态见目标浮层；小队／团队仍使用原生悬停。"}
    end
    for i=1,20 do
        local row=createTile(p,side,i,menu)
        row:SetPoint("TOPLEFT",PAD+((i-1)%COLUMNS)*(TILE_WIDTH+GAP),-GRID_TOP-math.floor((i-1)/COLUMNS)*(cellHeight(side)+GAP))
        section.tiles[i]=row
    end
    return section
end

function NS.CreateUI()
    if NS.UI or NS.InCombat() then return end
    local menu=createMarkMenu()
    NS.UI={friendly=makePanel("friendly",menu),enemy=makePanel("enemy",menu)}
    NS.RefreshControls()
end

local function active(b,value)
    b.active=value
    b:SetBackdropColor(value and 0.22 or 0.08,value and 0.19 or 0.1,value and 0.12 or 0.13,1)
    b:SetBackdropBorderColor(value and 0.78 or 0.23,value and 0.65 or 0.28,value and 0.35 or 0.34,1)
    b.label:SetTextColor(value and 1 or 0.76,value and 0.88 or 0.8,value and 0.6 or 0.86,1)
end

function NS.RefreshControls()
    if not NS.UI or NS.InCombat() then return end
    for _,side in ipairs({"friendly","enemy"}) do
        local section=NS.UI[side]
        local position=NS.DB[side .. "Position"]
        local positionKey=table.concat({position.point,position.relativePoint,position.x,position.y},":")
        if not section.frame.dragging and section.frame.positionKey ~= positionKey then
            section.frame:ClearAllPoints()
            section.frame:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
            section.frame.positionKey=positionKey
        end
        section.frame:SetScale(NS.RuntimeScale or NS.DB.scale)
        shown(section.frame,NS.IsPanelShown(side))
        section.lock.label:SetText(NS.DB.locked and "锁" or "移")
        active(section.lock,NS.DB.locked)
        for mode,b in pairs(section.tabs) do active(b,NS.DB.friendlyTab == mode) end
        local nearby=side ~= "friendly" or NS.DB.friendlyTab == "nearby"
        for n,b in pairs(section.limits) do
            b:SetEnabled(nearby)
            local capacity=side=="enemy" and NS.DB.enemyLimit or NS.DB.friendlyTab=="raid" and 20
                or NS.DB.friendlyTab=="party" and 5 or NS.DB.nearbyLimit
            active(b,n==capacity)
        end
        if legacyBridge(side) then
            section.mouseover.label:SetText("施法")
            section.mouseover.tipTitle="普通技能悬停"
            active(section.mouseover,NS.DB.legacyNameBridgeEnabled)
            if section.mouseover.SetEnabled then section.mouseover:SetEnabled(true) end
        elseif NS.NativeMacroOnly then
            section.mouseover.label:SetText("宏")
            section.mouseover.tipTitle="原生悬停宏"
            active(section.mouseover,false)
            if section.mouseover.SetEnabled then section.mouseover:SetEnabled(true) end
        end
    end
    refreshPanelLayouts()
end

local function restoreFocusedTile(section)
    if NS.InCombat() or not NS.IsPanelShown(section.side) or not section.frame:IsShown() then return end
    local foci=NS.Read(GetMouseFoci)
    if type(foci)~="table" then return end
    for _,focus in ipairs(foci) do
        if NS.Public(focus) then
            for i,row in ipairs(section.tiles) do
                if focus==row and i <= section.limit and row:IsShown() then
                    -- Changing a target/nameplate alias does not necessarily
                    -- produce another OnEnter while the cursor stays on a row.
                    -- Re-read its new unit/GUID rather than retaining old state.
                    if row.showUnitHover(row) and (not NS.NativeMacroOnly or legacyBridge(row.side))
                        and NS.NearbyCast and type(NS.NearbyCast.Enter)=="function" then
                        NS.NearbyCast.Enter(row)
                    end
                    return
                end
            end
        end
    end
end

function NS.BindTiles(side,tokens,limit)
    if not NS.UI or NS.InCombat() then return end
    local section=NS.UI[side]
    section.limit=limit
    local panel=section.frame
    refreshPanelLayouts()
    for i,row in ipairs(section.tiles) do
        local token=tokens[i]
        row.unit=i <= limit and token or nil
        local data=row.unit and NS.ReadUnit(row.unit,side) or nil
        row.expectedGUID=data and data.guid or nil
        row:SetAttribute("unit",row.unit)
        row:SetAttribute("*unit1",nil)
        row:SetAttribute("mark-unit",row.unit)
        row:SetAttribute("mark-guid",row.expectedGUID)
        local targetName=data and data.targetName
        row.targetByName=row.unit ~= nil and row.unit:match("^nameplate%d+$") ~= nil
            and type(targetName) == "string" and targetName ~= ""
        if row.targetByName then
            -- Direct nameplate targeting failed in this client's live checks.
            -- A hardware click may instead select the exposed full name.
            -- Keep the live unit and its native existence guard; do not suppress
            -- the unit with a button-specific override during mouseover handling.
            row:SetAttribute("*type1","macro")
            row:SetAttribute("*macrotext1","/targetexact " .. targetName)
        else
            row:SetAttribute("*type1","target")
            row:SetAttribute("*macrotext1",nil)
        end
        shown(row,i <= limit)
        if side=="enemy" and NS.EnemyTargetHover then NS.EnemyTargetHover.Bind(row) end
        if i > limit or not NS.IsPanelShown(side) then row.shield:Hide() end
        if not NS.NativeMacroOnly and NS.CombatCast and type(NS.CombatCast.ArmRow)=="function" then NS.CombatCast.ArmRow(row) end
    end
    section.hasBound=true
    restoreFocusedTile(section)
end

function NS.RefreshTiles()
    if not NS.UI then return end
    for _,side in ipairs({"friendly","enemy"}) do
        local section=NS.UI[side]
        local validCount=0
        for i,row in ipairs(section.tiles) do
            local visible=i <= (section.limit or 20) and section.frame:IsShown()
            local pinned=visible and focusCycleData(row) or nil
            local data=visible and (pinned or NS.ReadUnit(row.unit,side)) or nil
            -- A reused nameplate/target alias must never silently become a new
            -- clickable unit in the same combat. A fresh OOC binding re-arms it.
            if data and data.guid ~= row.expectedGUID then data=nil end
            row.data=data
            local valid=data ~= nil and data ~= false
            shown(row.shield,visible and not valid)
            if row.auras and NS.Auras and type(NS.Auras.Update)=="function" then
                NS.Auras.Update(row.auras,valid and row.unit or nil,valid and row.expectedGUID or nil,side)
            end
            if data then
                validCount=validCount+1
                local color=data.color or {0.9,0.9,0.9}
                local r,g,b=color.r or color[1] or .9,color.g or color[2] or .9,color.b or color[3] or .9
                row.nameText:SetText(data.name)
                row.nameText:SetTextColor(r,g,b,1)
                if side=="enemy" then readEnemyTarget(row) end
                row.classText:SetText((side=="friendly" or row.auras) and "" or (data.player and (data.className or "玩家") or "怪物"))
                row.classText:SetTextColor(r,g,b,1)
                row.topline:SetVertexColor(r,g,b,1)
                if data.dead or data.offline then row.health:SetStatusBarColor(.18,.21,.24,1)
                elseif side=="friendly" then row.health:SetStatusBarColor(.10,.60,.27,1)
                else row.health:SetStatusBarColor(.66,.20,.15,1) end
                local healthCurrent=data.healthCurrent
                if data.dead then healthCurrent=0 end
                nativeAmount(row.health,healthCurrent,data.healthMax,data.healthAvailable)
                local powerColor=data.powerColor
                local showPower=not data.dead and not data.offline and data.powerAvailable==true
                    and type(powerColor)=="table" and NS.Number(powerColor.r)
                    and NS.Number(powerColor.g) and NS.Number(powerColor.b)
                if showPower then
                    row.power:SetStatusBarColor(powerColor.r,powerColor.g,powerColor.b,1)
                end
                local powerShown=nativeAmount(row.power,data.powerCurrent,data.powerMax,showPower)
                shown(row.powerTrack,powerShown)
                row.indexText:SetText("")
                local selected=data.target == true
                if pinned then
                    local guid=observedGUID(data.guid)
                    selected=guid~=nil and observedGUID(NS.Read(UnitGUID,"target"))==guid
                end
                NS.RefreshIdentityBorders(row,data.guid,selected)
                local status=data.offline and "离线" or data.dead and "死亡" or
                    (NS.Number(data.health) and (math.floor(data.health*100+.5) .. "%") or "")
                row.statusText:SetText(focusCycleStatus(row) or status)
                row:SetBackdropBorderColor(selected and 1 or .24,selected and .15 or .29,selected and .12 or .35,1)
                shown(row.targetFill,selected)
                shown(row.targetBadge,selected)
                shown(row.questBadge,side == "enemy" and not data.player and data.questTarget == true)
                if data.raidMarker and data.raidMarker >= 1 and data.raidMarker <= 8 then
                    icon(row.marker,data.raidMarker);row.marker:Show()
                else row.marker:Hide() end
                if NS.HoveredTile == row and not (NS.HoveredEnemyTarget and NS.HoveredEnemyTarget.owner==row) then
                    local distance=NS.MeasureDistance and NS.DistanceText and NS.DistanceText(NS.MeasureDistance(row.unit)) or "距离未知"
                    local _,combatStatusKey=combatCastStatus(row)
                    local quest=side == "enemy" and not data.player and data.questTarget == true
                    if distance ~= row.tooltipDistance or data.name ~= row.tooltipName
                        or quest ~= row.tooltipQuest or data.questTitle ~= row.tooltipQuestTitle
                        or side=="enemy" and enemyTargetTooltip(row)~=row.tooltipEnemyTarget
                        or focusCycleStatus(row)~=row.tooltipFocusCycle
                        or row.tooltipCombat ~= NS.InCombat() or row.tooltipCombatStatus ~= combatStatusKey then
                        row.showUnitTooltip(row,data)
                    end
                end
            else
                row.enemyTarget=nil
                row.tooltipEnemyTarget=nil
                row.hover:Hide()
                NS.RefreshIdentityBorders(row,nil,false)
                row.targetFill:Hide();row.targetBadge:Hide();row.questBadge:Hide()
                if NS.HoveredTile == row then
                    NS.HoveredTile=nil
                    if NS.SetHoverUnit then NS.SetHoverUnit(nil) end
                    hideTooltip()
                end
                row.nameText:SetText("");row.classText:SetText("");row.statusText:SetText("")
                row.indexText:SetText(string.format("%02d",i))
                nativeAmount(row.health,nil,nil,false)
                nativeAmount(row.power,nil,nil,false);row.powerTrack:Hide()
                row.topline:SetVertexColor(.24,.29,.35,1)
                row:SetBackdropBorderColor(.24,.29,.35,1)
                row.marker:Hide()
            end
            if side=="enemy" and NS.EnemyTargetHover then
                NS.EnemyTargetHover.Refresh(row,valid and row.enemyTarget or nil)
            end
        end
        section.validCount=validCount
        if section.mouseover and legacyBridge(side) then
            section.mouseover.label:SetText("施法")
            section.mouseover.tipTitle="普通技能悬停"
            active(section.mouseover,NS.DB.legacyNameBridgeEnabled)
            if section.mouseover.SetEnabled then section.mouseover:SetEnabled(true) end
        elseif section.mouseover and NS.NativeMacroOnly then
            section.mouseover.label:SetText("宏")
            section.mouseover.tipTitle="原生悬停宏"
            active(section.mouseover,false)
            if section.mouseover.SetEnabled then section.mouseover:SetEnabled(true) end
        elseif section.mouseover and NS.MouseoverStatus then
            local enabled,_,available=NS.MouseoverStatus()
            section.mouseover.label:SetText("施法")
            active(section.mouseover,enabled)
            if section.mouseover.SetEnabled then section.mouseover:SetEnabled(available ~= false) end
        end
    end
    NS.InvalidateMarkMenu()
    if NS.UpdateHover then NS.UpdateHover() end
end
