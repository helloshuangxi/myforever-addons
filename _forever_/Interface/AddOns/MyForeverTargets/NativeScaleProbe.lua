local _, NS = ...
-- Explicit geometry/mouseover experiment. This does not cast, select a target,
-- set focus, change bindings, or implement combat GUID confirmation.
local P={MAX_SECONDS=15,SCALED_SECONDS=10,FACTOR=8}
NS.NativeScaleProbe=P
local state,observer,card,lastStatus
local hooks=setmetatable({}, {__mode="k"})
local request
local reasons={disabled="未运行",restored="已恢复",ownership_lost="检测到其他插件修改，已交还相应设置",
    configured_unverified="已配置，尚未验证",control_observation="原尺寸对照中，请保持鼠标",
    restore_waiting_for_combat="等待脱战恢复",restore_scale_unreadable="等待可读缩放后恢复",
    restore_scale_forbidden="等待框体恢复修改权限",restore_ownership_unconfirmed="恢复所有权尚未确认",
    restore_scale_pending="原缩放尚未恢复",restore_anchors_unreadable="等待可读命中区后恢复",
    restore_hit_not_permitted="等待命中区恢复修改权限",
    already_active_or_restoring="已有探针或恢复流程",out_of_combat_only="请先脱战",cursor_not_clear="请取消待施法或拖动物品光标",
    other_probe_active="其他原生或焦点实验正在运行",invalid_enemy_row="该敌方格子没有可用的姓名板单位",
    native_owner_unavailable="原生姓名板不可修改或已由其他界面接管",geometry_unreadable="无法读取公开几何或原始缩放",
    identity_unavailable="格子身份、存活状态或GUID暂不可核验",observer_unavailable="无法建立观察与恢复机制",
    visual_scale_refused="视觉补偿缩放未生效",native_scale_refused_or_clamped="原生缩放被拒绝或夹限",
    native_bounds_not_expanded="缩放读回成功但原生边界未扩大",no_isolated_probe_area="没有位于旧边界外的独立验证区域",
    card_unavailable="临时验证框未能创建",setup_identity_changed="准备期间单位身份已变化",
    hit_test_mapping_refused="原生命中区域映射未获确认",external_geometry_change="检测到外部几何修改",
    native_geometry_moved="姓名板或视口已移动，本次空间证据不确定",
    row_index_1_to_20_required="请输入敌方格子序号1到20",setup_error="准备过程发生错误，已请求恢复"}
local points={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,
    BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}

local function object(v) return NS.Public(v) and (type(v)=="table" or type(v)=="userdata") end
local function member(v,key)
    if not object(v) then return nil end
    return NS.Read(function() return v[key] end)
end
local function read(v,key,...) return NS.Read(member(v,key),v,...) end
local function idle() return NS.Read(InCombatLockdown)==false end
local function guid(unit)
    local g=NS.Read(UnitGUID,unit)
    return type(g)=="string" and g~="" and g or nil
end
local function close(a,b) return NS.Number(a) and NS.Number(b) and math.abs(a-b)<.00001 end
local function call(fn,...)
    if not idle() or type(fn)~="function" then return false end
    local ok,result=pcall(fn,...)
    return ok and NS.Public(result) and result~=false
end
local function write(v,key,...) return call(member(v,key),v,...) end
local function anchors(v)
    local a=read(v,"GetHitTestPoints")
    if not object(a) then return nil end
    local ok,copied=pcall(function()
        local count=#a
        if count>8 then return nil end
        for key in pairs(a) do
            if not NS.Number(key) or key%1~=0 or key<1 or key>count then return nil end
        end
        local out={}
        for i=1,count do
            local p=a[i]
            if not object(p) or not NS.Public(p.point) or not points[p.point]
                or not NS.Public(p.relativePoint) or not points[p.relativePoint]
                or not object(p.relativeTo) or not NS.Number(p.offsetX) or not NS.Number(p.offsetY) then return nil end
            out[i]={point=p.point,relativePoint=p.relativePoint,relativeTo=p.relativeTo,offsetX=p.offsetX,offsetY=p.offsetY}
        end
        return out
    end)
    return ok and copied or nil
end
local function sameAnchors(a,b)
    if not a or not b or #a~=#b then return false end
    for i,x in ipairs(a) do
        local y=b[i]
        if x.point~=y.point or x.relativePoint~=y.relativePoint or x.relativeTo~=y.relativeTo
            or x.offsetX~=y.offsetX or x.offsetY~=y.offsetY then return false end
    end
    return true
end
local function mappedTo(a,v)
    if not a or #a~=2 then return false end
    local seen={}
    for _,p in ipairs(a) do
        if p.relativeTo~=v or p.point~=p.relativePoint or p.offsetX~=0 or p.offsetY~=0
            or (p.point~="TOPLEFT" and p.point~="BOTTOMRIGHT") or seen[p.point] then return false end
        seen[p.point]=true
    end
    return seen.TOPLEFT and seen.BOTTOMRIGHT
end
local function geometry(v)
    local l,b,w,h=NS.Read(member(v,"GetRect"),v)
    local scale,rootScale=read(v,"GetEffectiveScale"),read(UIParent,"GetEffectiveScale")
    if not NS.Number(l) or not NS.Number(b) or not NS.Number(w) or not NS.Number(h) or w<=0 or h<=0
        or not NS.Number(scale) or scale<=0 or not NS.Number(rootScale) or rootScale<=0 then return nil end
    local ratio=scale/rootScale
    local g={left=l*ratio,bottom=b*ratio,width=w*ratio,height=h*ratio,effectiveScale=scale}
    g.right,g.top=g.left+g.width,g.bottom+g.height
    for _,key in ipairs({"left","bottom","width","height","right","top"}) do if not NS.Number(g[key]) then return nil end end
    return g
end
local function contains(g,x,y)
    return g and NS.Number(x) and NS.Number(y) and x>=g.left and x<=g.right and y>=g.bottom and y<=g.top or false
end
local function geometryCurrent(s)
    local g=geometry(s.plate)
    local before=s.phase=="control" and s.controlBounds or s.expandedBounds
    if not g or not before or not close(read(UIParent,"GetEffectiveScale"),s.rootScale)
        or not close(read(UIParent,"GetWidth"),s.screenWidth) or not close(read(UIParent,"GetHeight"),s.screenHeight) then return false end
    -- This experiment freezes screen-space geometry. Do not count a moving
    -- monster/camera carrying its ordinary hit area under the fixed test card.
    for _,key in ipairs({"left","bottom","width","height","effectiveScale"}) do
        if math.abs(g[key]-before[key])>.05 then return false end
    end
    return true
end
local function owner(plate)
    if not object(plate) or read(plate,"IsForbidden")~=false then return nil end
    local uf=member(plate,"UnitFrame")
    if not object(uf) or read(uf,"IsForbidden")~=false or read(uf,"GetNamePlateFrame")~=plate or not object(NamePlateUnitFrameMixin)
        or type(member(uf,"UpdateHitTestArea"))~="function"
        or member(uf,"UpdateHitTestArea")~=member(NamePlateUnitFrameMixin,"UpdateHitTestArea") then return nil end
    return uf
end
local function identity(s)
    return read(s.row,"IsShown")==true and read(s.row,"IsVisible")==true
        and member(s.row,"unit")==s.unit and member(s.row,"expectedGUID")==s.guid
        and NS.Read(UnitExists,s.unit)==true and NS.Read(UnitCanAttack,"player",s.unit)==true
        and NS.Read(UnitIsPlayer,s.unit)==false and NS.Read(UnitIsDeadOrGhost,s.unit)==false
        and guid(s.unit)==s.guid and NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,s.unit)==s.plate
        and owner(s.plate)==s.uf
end
local function otherActive()
    if member(NS.FocusAPIProbe,"active") then return true end
    if NS.Read(member(NS.FocusCycle,"IsActive"))==true then return true end
    for _,key in ipairs({"EnemyNativeHover","EnemyNativeTrial"}) do
        local status=NS.Read(member(NS[key],"Status"))
        if object(status) and (status.active==true or status.configured==true or status.restoring==true) then return true end
    end
    return false
end
local function log(kind,fields)
    local d=NS.Diagnostics
    if type(member(d,"Record"))=="function" then pcall(d.Record,"NATIVE_SCALE_"..kind,fields or {}) end
end
local function status()
    local s=state
    if not s then return lastStatus or {active=false,restoring=false,reason="disabled",matches=false} end
    local out={active=s.active==true,restoring=s.restoring==true,reason=s.reason,unit=s.unit,
        expectedGUID=s.guid,elapsed=s.elapsed or 0,nativeScale=read(s.plate,"GetScale"),
        visualScale=read(s.uf,"GetScale"),beforeNativeScale=s.native.before,beforeVisualScale=s.visual.before,
        nativePending=s.native.pending==true,visualPending=s.visual.pending==true,anchorsPending=s.hit.pending==true,
        actualMouseoverGUID=guid("mouseover"),targetGUID=guid("target"),focusGUID=guid("focus"),
        ownershipLost=s.ownershipLost==true,matches=false,observationOnly=true,stopReason=s.stopReason,
        phase=s.phase,scaleEffectProven=false,scaledMatchObserved=s.scaledPoint~=nil,
        samePointControlObserved=s.controlSeen==true,samePointControlMatched=s.controlMatched==true}
    out.mouseoverExists=NS.Read(UnitExists,"mouseover")
    out.mouseoverReadable=out.actualMouseoverGUID~=nil or out.mouseoverExists==false
    out.controlSettled=s.phase=="control" and s.controlStarted and s.elapsed-s.controlStarted>=.25 or false
    local physicalX,physicalY=NS.Read(GetCursorPosition)
    local rootScale=read(UIParent,"GetEffectiveScale")
    local x,y
    if NS.Number(physicalX) and NS.Number(physicalY) and NS.Number(rootScale) and rootScale>0 then
        x,y=physicalX/rootScale,physicalY/rootScale
    end
    out.cursorX,out.cursorY=x,y
    out.pointerOver=contains(s.cardBounds,x,y)
    out.outsideBefore=NS.Number(x) and NS.Number(y) and not contains(s.beforeBounds,x,y) or false
    out.insideExpanded=contains(s.expandedBounds,x,y)
    out.identityCurrent=identity(s)
    out.geometryCurrent=geometryCurrent(s)
    out.matches=out.active and out.pointerOver and out.outsideBefore and out.insideExpanded
        and out.identityCurrent and out.geometryCurrent and out.actualMouseoverGUID==s.guid
    return out
end
P.Status=status
local function recordStatus()
    local s=state
    if not s then return end
    local out=status()
    local parts={}
    for _,key in ipairs({"active","restoring","reason","nativeScale","visualScale","nativePending","visualPending",
        "anchorsPending","actualMouseoverGUID","targetGUID","focusGUID","ownershipLost","pointerOver","outsideBefore",
        "insideExpanded","identityCurrent","geometryCurrent","matches","phase","cursorX","cursorY","controlSettled","mouseoverReadable"}) do parts[#parts+1]=key.."="..tostring(out[key]) end
    local signature=table.concat(parts,";")
    if signature~=s.signature then s.signature=signature;log("STATUS",out) end
    if out.matches then s.matchedSeen=true end
    if s.phase=="scaled" and out.matches and not s.scaledPoint then s.scaledPoint={x=out.cursorX,y=out.cursorY} end
    if s.phase=="control" and out.controlSettled and out.mouseoverReadable and s.scaledPoint
        and out.pointerOver and out.geometryCurrent and out.identityCurrent
        and NS.Number(out.cursorX) and NS.Number(out.cursorY) then
        local dx,dy=out.cursorX-s.scaledPoint.x,out.cursorY-s.scaledPoint.y
        if dx*dx+dy*dy<=.25 then
            local changed=not s.controlSeen or out.matches and not s.controlMatched
            s.controlSeen=true
            if out.matches then s.controlMatched=true end
            if changed then log("CONTROL_SAMPLE",{phase="control",cursorX=out.cursorX,cursorY=out.cursorY,
                scaledCursorX=s.scaledPoint.x,scaledCursorY=s.scaledPoint.y,actualMouseoverGUID=out.actualMouseoverGUID,
                mouseoverExists=out.mouseoverExists,matches=out.matches,withinHalfUIUnit=true,
                scaleEffectProven=false,observationOnly=true}) end
        end
    end
    if card and card.label then
        pcall(card.label.SetText,card.label,s.phase=="control" and "原尺寸对照 · 保持鼠标" or
            out.matches and "GUID已匹配 · 不要点击" or "悬停这里 · 不要点击")
    end
end

-- Post-call observers distinguish our setter from nested or later writes. A
-- foreign write serial is never reset by our outer setter's trailing callback.
local function install(v,key,channel)
    hooks[v]=hooks[v] or {}
    if hooks[v][key] then return true end
    if type(hooksecurefunc)~="function" or type(member(v,key))~="function" then return false end
    local ok=pcall(hooksecurefunc,v,key,function(self,value)
        local s=state
        if not s or self~=(channel=="visual" and s.uf or s.plate) then return end
        local r=request
        if r and r.object==self and r.key==key and r.value==value and not r.seen then r.seen=true
        else s.foreign[channel]=s.foreign[channel]+1;s.ownershipLost=true end
    end)
    if ok then hooks[v][key]=true end
    return ok
end
local function mutate(s,part,object,key,value,channel,getter)
    if not idle() then return false end
    if s.phase=="preparing" and not part.attempted and s.foreign[channel]~=0 then
        s.ownershipLost=true;return false
    end
    part.attempted=true
    local serial=s.foreign[channel]
    local previous=request
    request={object=object,key=key,value=value}
    local ok=write(object,key,value)
    request=previous
    local after=getter()
    if s.foreign[channel]~=serial then part.pending=false;s.ownershipLost=true;return false end
    local same=channel=="hit" and sameAnchors(after,part.before) or channel~="hit" and close(after,part.before)
    part.pending=not same
    part.owned=after
    part.serial=serial
    return ok
end
local function restoreScale(s,part,object,channel)
    if not part.pending then return true end
    if s.foreign[channel]~=part.serial then part.pending=false;s.ownershipLost=true;return true end
    if read(object,"IsForbidden")~=false then s.reason="restore_scale_forbidden";return false end
    local now=read(object,"GetScale")
    if close(now,part.before) then part.pending=false;return true end
    if not NS.Number(now) then s.reason="restore_scale_unreadable";return false end
    if not NS.Number(part.owned) then s.reason="restore_ownership_unconfirmed";return false end
    if not close(now,part.owned) then part.pending=false;s.ownershipLost=true;return true end
    mutate(s,part,object,"SetScale",part.before,channel,function() return read(object,"GetScale") end)
    if part.pending then s.reason="restore_scale_pending" end
    return not part.pending
end
local function recover()
    local s=state
    if not s then return true end
    if not idle() then s.reason="restore_waiting_for_combat";recordStatus();return false end
    if s.hit.pending then
        local now=anchors(s.plate)
        if s.foreign.hit~=s.hit.serial then s.hit.pending=false;s.ownershipLost=true
        elseif sameAnchors(now,s.hit.before) then s.hit.pending=false
        elseif not now then s.reason="restore_anchors_unreadable"
        elseif s.hit.owned and not sameAnchors(now,s.hit.owned) then s.hit.pending=false;s.ownershipLost=true
        elseif not s.hit.owned then s.reason="restore_ownership_unconfirmed"
        elseif read(s.plate,"IsForbidden")~=false or read(s.plate,"CanChangeHitTestPoints")~=true then s.reason="restore_hit_not_permitted"
        else mutate(s,s.hit,s.plate,"SetHitTestPoints",s.hit.before,"hit",function() return anchors(s.plate) end) end
    end
    restoreScale(s,s.native,s.plate,"native")
    -- Keep the inverse visual scale while our enlarged native scale is still
    -- awaiting restoration, instead of briefly exposing a giant health bar.
    if not s.native.pending then restoreScale(s,s.visual,s.uf,"visual") end
    if s.hit.pending or s.native.pending or s.visual.pending then recordStatus();return false end
    local after=geometry(s.plate)
    local comparable=after~=nil
    if after then
        for _,key in ipairs({"left","bottom","width","height","effectiveScale"}) do
            if math.abs(after[key]-s.beforeBounds[key])>.05 then comparable=false end
        end
    end
    log("RESTORE_GEOMETRY",{unit=s.unit,expectedGUID=s.guid,
        beforeLeft=s.beforeBounds.left,beforeBottom=s.beforeBounds.bottom,beforeWidth=s.beforeBounds.width,beforeHeight=s.beforeBounds.height,
        afterLeft=after and after.left,afterBottom=after and after.bottom,afterWidth=after and after.width,afterHeight=after and after.height,
        finalGeometryComparable=comparable,geometryDriftObserved=s.geometryDrift==true,
        nativeMouseoverObserved=s.matchedSeen==true,ownershipLost=s.ownershipLost==true,
        scaledMatchObserved=s.scaledPoint~=nil,samePointControlObserved=s.controlSeen==true,
        samePointControlMatched=s.controlMatched==true,scaleEffectProven=false,
        focusTested=false,combatTested=false,observationOnly=true})
    if s.wantControl and comparable and not s.geometryDrift and not s.ownershipLost and s.elapsed<P.MAX_SECONDS then
        s.wantControl=false;s.phase="control";s.controlBounds=after;s.active=true;s.restoring=false;s.controlStarted=s.elapsed
        s.reason="control_observation";s.signature=nil
        log("PHASE",{phase="control",elapsed=s.elapsed,nativeScale=read(s.plate,"GetScale"),
            visualScale=read(s.uf,"GetScale"),scaledMatchObserved=s.scaledPoint~=nil,observationOnly=true})
        recordStatus()
        return true
    end
    s.active=false
    s.reason=s.ownershipLost and "ownership_lost" or "restored"
    s.restoring=false
    if card then pcall(card.Hide,card) end
    recordStatus();lastStatus=status();log("END",lastStatus)
    state=nil
    return true
end
function P.Stop(reason)
    if not state then return true end
    local s=state
    s.wantControl=false
    s.active=false;s.restoring=true;s.stopReason=s.stopReason or reason or "user"
    s.reason=s.stopReason
    if card then pcall(card.Hide,card) end -- private, unprotected presentation
    return recover()
end

local function tick(delta)
    local s=state
    if not s or not NS.Number(delta) or delta<0 then return end
    if s.restoring then
        s.restoreTick=(s.restoreTick or 0)+delta
        if s.restoreTick>=1 then s.restoreTick=0;recover() end
        return
    end
    s.elapsed=s.elapsed+delta;s.tick=s.tick+delta
    if not idle() then P.Stop("combat_or_unknown");return end
    if NS.Read(SpellIsTargeting)~=false or NS.Read(CursorHasItem)~=false then P.Stop("cursor_not_clear");return end
    if not identity(s) then P.Stop("identity_changed");return end
    if otherActive() then P.Stop("other_probe_active");return end
    if not geometryCurrent(s) then s.geometryDrift=true;P.Stop("native_geometry_moved");return end
    if s.elapsed>=P.MAX_SECONDS then P.Stop("timeout");return end
    if s.foreign.native~=s.native.serial or s.foreign.visual~=s.visual.serial or s.foreign.hit~=s.hit.serial
        or not close(read(s.plate,"GetScale"),s.native.owned) or not close(read(s.uf,"GetScale"),s.visual.owned)
        or not sameAnchors(anchors(s.plate),s.hit.owned) then P.Stop("external_geometry_change");return end
    if s.phase=="scaled" and s.elapsed>=P.SCALED_SECONDS then
        s.active=false;s.restoring=true;s.wantControl=true;s.reason="preparing_control"
        if not recover() then
            s.wantControl=false;s.stopReason="control_restore_pending"
            if card then pcall(card.Hide,card) end
        end
        return
    end
    if s.tick>=.1 then s.tick=0;recordStatus() end
end
local function ensureObserver()
    if observer then return true end
    local frame=NS.Read(CreateFrame,"Frame",nil,UIParent)
    if not frame then return false end
    frame:EnableMouse(false)
    frame:SetScript("OnUpdate",function(_,delta)
        local ok=pcall(tick,delta)
        if not ok then pcall(P.Stop,"observer_error") end
    end)
    frame:SetScript("OnEvent",function(_,event,unit)
        if not state then return end
        local ok=pcall(function()
            if event=="PLAYER_REGEN_ENABLED" then if state.restoring then recover() end
            elseif event=="GLOBAL_MOUSE_DOWN" then P.Stop("user_click")
            elseif event~="NAME_PLATE_UNIT_REMOVED" or NS.Public(unit) and unit==state.unit then P.Stop(event:lower()) end
        end)
        if not ok then pcall(P.Stop,"observer_error") end
    end)
    for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","NAME_PLATE_UNIT_REMOVED",
        "PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","GLOBAL_MOUSE_DOWN"}) do frame:RegisterEvent(event) end
    observer=frame
    return true
end
local function chooseCard(before,after)
    local w,h=read(UIParent,"GetWidth"),read(UIParent,"GetHeight")
    if not NS.Number(w) or not NS.Number(h) then return nil end
    local l,b=math.max(8,after.left+2),math.max(8,after.bottom+2)
    local r,t=math.min(w-8,after.right-2),math.min(h-8,after.top-2)
    local candidates={{l,b},{r-90,b},{l,t-32},{r-90,t-32},
        {math.max(l,before.right+4),b},{l,math.max(b,before.top+4)}}
    for _,xy in ipairs(candidates) do
        local x,y=xy[1],xy[2]
        if x>=l and y>=b and x+90<=r and y+32<=t
            and (x+90<before.left or x>before.right or y+32<before.bottom or y>before.top) then
            return {left=x,bottom=y,right=x+90,top=y+32,width=90,height=32}
        end
    end
end
local function ensureCard(g)
    if not card then
        card=NS.Read(CreateFrame,"Frame",nil,UIParent,"BackdropTemplate")
        if not card then return false end
        card:EnableMouse(false);card:SetFrameStrata("HIGH")
        card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        card:SetBackdropColor(.15,.22,.3,.96);card:SetBackdropBorderColor(.85,.72,.35,1)
        card.label=card:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        card.label:SetAllPoints(card)
    end
    card:ClearAllPoints();card:SetScale(1);card:SetSize(g.width,g.height)
    card:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",g.left,g.bottom)
    card.label:SetText("悬停这里 · 不要点击");card:Show()
    return true
end
local function refuse(reason)
    lastStatus={active=false,restoring=false,reason=reason,matches=false,observationOnly=true}
    log("REJECT",lastStatus);NS.Print("原生缩放探针未启动："..(reasons[reason] or reason).."。")
    return false,reason
end
local function start(index)
    if state then return refuse("already_active_or_restoring") end
    local d=NS.Diagnostics
    if type(member(d,"Start"))=="function" then pcall(d.Start) end
    if not idle() then return refuse("out_of_combat_only") end
    if NS.Read(SpellIsTargeting)~=false or NS.Read(CursorHasItem)~=false then return refuse("cursor_not_clear") end
    if otherActive() then return refuse("other_probe_active") end
    local row=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles and NS.UI.enemy.tiles[index]
    local unit,expected=member(row,"unit"),member(row,"expectedGUID")
    if member(row,"side")~="enemy" or type(unit)~="string" or not unit:match("^nameplate%d+$")
        or not NS.ValidToken(unit) or type(expected)~="string" or expected=="" then return refuse("invalid_enemy_row") end
    local plate=NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit)
    local uf=owner(plate)
    if not uf or read(plate,"CanChangeHitTestPoints")~=true then return refuse("native_owner_unavailable") end
    local ns,vs=read(plate,"GetScale"),read(uf,"GetScale")
    local a,b=anchors(plate),geometry(plate)
    if not NS.Number(ns) or ns<=0 or ns>8 or not NS.Number(vs) or vs<=0 or not a or not b then return refuse("geometry_unreadable") end
    local s={row=row,unit=unit,guid=expected,plate=plate,uf=uf,beforeBounds=b,
        rootScale=read(UIParent,"GetEffectiveScale"),screenWidth=read(UIParent,"GetWidth"),screenHeight=read(UIParent,"GetHeight"),
        native={before=ns,pending=false},visual={before=vs,pending=false},hit={before=a,pending=false},
        foreign={native=0,visual=0,hit=0},elapsed=0,tick=0,active=false,phase="preparing",reason="preparing"}
    if not identity(s) then return refuse("identity_unavailable") end
    if not ensureObserver() or not install(plate,"SetScale","native") or not install(uf,"SetScale","visual")
        or not install(plate,"SetAllHitTestPoints","hit") or not install(plate,"SetHitTestPoints","hit")
        or not install(plate,"ClearAllHitTestPoints","hit") then return refuse("observer_unavailable") end
    state=s
    local version,build,date,toc=NS.Read(GetBuildInfo)
    log("BEGIN",{version=NS.VERSION,clientVersion=version,clientBuild=build,clientDate=date,clientInterface=toc,
        unit=unit,expectedGUID=expected,factor=P.FACTOR,maxSeconds=P.MAX_SECONDS,
        beforeNativeScale=ns,beforeVisualScale=vs,beforeLeft=b.left,beforeBottom=b.bottom,beforeWidth=b.width,beforeHeight=b.height,
        targetGUID=guid("target"),focusGUID=guid("focus"),observationOnly=true})
    local function fail(reason) P.Stop(reason);NS.Print("原生缩放探针中止："..(reasons[reason] or reason).."；请 /reload 保存日志。");return false,reason end
    if s.ownershipLost or not close(read(plate,"GetScale"),ns) or not close(read(uf,"GetScale"),vs)
        or not sameAnchors(anchors(plate),a) then s.ownershipLost=true;return fail("external_geometry_change") end
    if not NS.Number(vs/P.FACTOR) or vs/P.FACTOR<=0 then return fail("geometry_unreadable") end
    local visualOK=mutate(s,s.visual,uf,"SetScale",vs/P.FACTOR,"visual",function() return read(uf,"GetScale") end)
    if s.ownershipLost then return fail("external_geometry_change") end
    if not visualOK or not close(s.visual.owned,vs/P.FACTOR) then return fail("visual_scale_refused") end
    local nativeOK=mutate(s,s.native,plate,"SetScale",ns*P.FACTOR,"native",function() return read(plate,"GetScale") end)
    if s.ownershipLost then return fail("external_geometry_change") end
    if not nativeOK or not close(s.native.owned,ns*P.FACTOR) then return fail("native_scale_refused_or_clamped") end
    s.expandedBounds=geometry(plate)
    local g=s.expandedBounds
    if not g or (g.width<=b.width+.01 and g.height<=b.height+.01) then return fail("native_bounds_not_expanded") end
    local selected=chooseCard(b,g)
    if not selected then return fail("no_isolated_probe_area") end
    if not geometryCurrent(s) then return fail("native_geometry_moved") end
    s.cardBounds=selected
    if not ensureCard(selected) then return fail("card_unavailable") end
    if not identity(s) or not idle() or read(plate,"CanChangeHitTestPoints")~=true then return fail("setup_identity_changed") end
    if not mutate(s,s.hit,plate,"SetAllHitTestPoints",card,"hit",function() return anchors(plate) end)
        or not mappedTo(s.hit.owned,card) then return fail("hit_test_mapping_refused") end
    if s.ownershipLost then return fail("external_geometry_change") end
    s.active=true;s.phase="scaled";s.reason="configured_unverified"
    log("GEOMETRY",{expandedLeft=g.left,expandedBottom=g.bottom,expandedWidth=g.width,expandedHeight=g.height,
        cardLeft=selected.left,cardBottom=selected.bottom,cardWidth=90,cardHeight=32,observationOnly=true})
    recordStatus()
    NS.Print("原生缩放探针15秒：请静止面对站立怪物，不转视角；悬停临时框不点击。前10秒缩放、后5秒原尺寸对照，保持鼠标。结束 /reload 保存。")
    return true,"configured_unverified"
end
function P.Command(argument)
    local value=NS.Text(argument):match("^%s*(.-)%s*$")
    if value=="stop" then
        local done=P.Stop("user")
        NS.Print(done and "原生缩放探针已停止。" or "探针停止，等待脱战或恢复许可；请勿启动其他实验。")
        return done
    elseif value=="status" then
        local s=status();NS.Print("原生缩放探针："..(reasons[s.reason] or s.reason).."；匹配="..tostring(s.matches).."。")
        return s
    end
    local index=tonumber(value)
    if not NS.Number(index) or index%1~=0 or index<1 or index>20 then return refuse("row_index_1_to_20_required") end
    local ok,result,reason=pcall(start,index)
    if not ok then pcall(P.Stop,"setup_error");return refuse("setup_error") end
    return result,reason
end
