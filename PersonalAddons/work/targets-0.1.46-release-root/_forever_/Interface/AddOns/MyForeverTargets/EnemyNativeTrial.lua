local addonName, NS = ...
-- Explicit, temporary native-hit trial. Restoration uses Blizzard's CURRENT
-- default layout; it is not an unreadable snapshot of another addon's layout.
-- No restricted frame measurements, target, spell, macro or binding operations.
local T={MAX_SECONDS=180}
NS.EnemyNativeTrial=T
local state,card,lastReason,lastSignature
local hooksInstalled=false
local writing,refused=false,false
local ownSizeRequest

local function object(v) return NS.Public(v) and (type(v)=="table" or type(v)=="userdata") end
local function member(v,key)
    if not object(v) then return nil end
    local ok,value=pcall(function() return v[key] end)
    return ok and NS.Public(value) and value or nil
end
local function read(v,key,...) return NS.Read(member(v,key),v,...) end
local function ooc() return NS.Read(InCombatLockdown)==false end
local function call(fn,...)
    if not ooc() or type(fn)~="function" then return false end
    local previous=writing;writing=true;refused=false
    local ok,value=pcall(fn,...)
    local denied=refused;writing=previous
    return ok and not denied and NS.Public(value) and value~=false
end
local function write(v,key,...) return call(member(v,key),v,...) end
local function guid(unit)
    local value=NS.Read(UnitGUID,unit)
    return type(value)=="string" and value~="" and value or nil
end
local function plateFor(unit) return NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit) end
local function size()
    local w,h=NS.Read(C_NamePlate and C_NamePlate.GetNamePlateSize)
    if NS.Number(w) and NS.Number(h) and w>0 and h>0 then return w,h end
end
local function setSize(w,h)
    local previous=ownSizeRequest;ownSizeRequest={w,h}
    local ok=call(C_NamePlate and C_NamePlate.SetNamePlateSize,w,h)
    ownSizeRequest=previous
    return ok
end
local function owner(plate)
    if not object(plate) or read(plate,"IsForbidden")~=false then return nil end
    local uf=member(plate,"UnitFrame")
    if not object(uf) or read(uf,"GetNamePlateFrame")~=plate
        or not object(NamePlateSetupOptions) or not object(NamePlateUnitFrameMixin)
        or type(member(uf,"UpdateHitTestArea"))~="function"
        or member(uf,"UpdateHitTestArea")~=member(NamePlateUnitFrameMixin,"UpdateHitTestArea") then return nil end
    return uf
end
local function identity(s)
    return NS.Read(UnitExists,s.unit)==true and NS.Read(UnitCanAttack,"player",s.unit)==true
        and NS.Read(UnitIsDeadOrGhost,s.unit)==false and guid(s.unit)==s.guid
        and plateFor(s.unit)==s.plate and owner(s.plate)==s.uf
end
local function setupCard(name)
    if not card then
        local candidate=NS.Read(CreateFrame,"Frame",nil,UIParent)
        if not candidate then return false end
        local function failed() write(candidate,"Hide");return false end
        if not write(candidate,"Hide") or not write(candidate,"SetSize",90,56)
            or not write(candidate,"SetPoint","TOP",UIParent,"TOP",0,-100)
            or not write(candidate,"SetFrameStrata","HIGH") or not write(candidate,"EnableMouse",false) then return failed() end
        candidate.background=read(candidate,"CreateTexture",nil,"BACKGROUND")
        candidate.title=read(candidate,"CreateFontString",nil,"OVERLAY","GameFontNormalSmall")
        candidate.nameText=read(candidate,"CreateFontString",nil,"OVERLAY","GameFontNormalSmall")
        candidate.statusText=read(candidate,"CreateFontString",nil,"OVERLAY","GameFontNormalSmall")
        if not candidate.background or not candidate.title or not candidate.nameText or not candidate.statusText then return failed() end
        if not write(candidate.background,"SetAllPoints",candidate) or not write(candidate.background,"SetColorTexture",.32,.06,.04,.94)
            or not write(candidate.title,"SetPoint","BOTTOM",candidate,"TOP",0,5)
            or not write(candidate.title,"SetText","临时鼠标验证 · 3分钟")
            or not write(candidate.nameText,"SetPoint","TOP",candidate,"TOP",0,-9)
            or not write(candidate.nameText,"SetWidth",86)
            or not write(candidate.statusText,"SetPoint","BOTTOM",candidate,"BOTTOM",0,8) then return failed() end
        card=candidate
    end
    return write(card.nameText,"SetText",name) and write(card,"Show")
end
local function pointerOver()
    local x,y=NS.Read(GetCursorPosition)
    local left,bottom,width,height=read(card,"GetRect")
    local scale=read(card,"GetEffectiveScale")
    if NS.Number(x) and NS.Number(y) and NS.Number(left) and NS.Number(bottom)
        and NS.Number(width) and NS.Number(height) and NS.Number(scale) and scale>0 then
        return x>=left*scale and x<=(left+width)*scale and y>=bottom*scale and y<=(bottom+height)*scale
    end
    local over=NS.Read(MouseIsOver,card)
    if over==true or over==false then return over end
    return read(card,"IsMouseOver")==true
end
local function decorate(status)
    if not card then return end
    -- These are private, non-protected presentation objects, including while
    -- cleanup waits for combat to end. They never capture mouse input.
    local text=status.restoring and "等待恢复" or status.matches and "鼠标已匹配" or "等待悬停"
    pcall(function()
        card.statusText:SetText(text)
        card.background:SetColorTexture(status.matches and .03 or .32,status.matches and .42 or .06,.04,.94)
    end)
end
function T.Status()
    local s=state
    local status={active=s~=nil and s.active==true,restoring=s~=nil and s.stopping==true,
        reason=s and s.reason or lastReason or "disabled",restoreMode="native_default",matches=false}
    if s then
        status.unit,status.expectedGUID=s.unit,s.guid
        status.actualMouseoverGUID=guid("mouseover")
        status.identityCurrent=identity(s)
        status.pointerOver=pointerOver()
        status.matches=status.active and s.mappingAccepted==true and status.identityCurrent and status.pointerOver
            and status.actualMouseoverGUID==s.guid
        status.sizePending=s.sizePending==true
        status.mappingAccepted=s.mappingAccepted==true
        if status.matches then status.reason="native_mouseover_matches" end
    end
    return status
end
local function record()
    local status=T.Status();decorate(status)
    local d=NS.Diagnostics
    if not d or NS.Read(d.Enabled)~=true or type(d.Record)~="function" then return end
    local values={}
    for _,key in ipairs({"active","restoring","reason","unit","expectedGUID","actualMouseoverGUID",
        "identityCurrent","pointerOver","matches","sizePending","mappingAccepted"}) do
        local value=status[key];values[#values+1]=type(value)=="boolean" and tostring(value) or NS.Text(value)
    end
    local signature=table.concat(values,"|")
    if signature~=lastSignature then
        local ok,accepted=pcall(d.Record,"ENEMY_NATIVE_TRIAL_STATUS",status)
        if ok and NS.Public(accepted) and accepted==true then lastSignature=signature end
    end
end

local function cleanup()
    local s=state
    if not s then return true end
    if not ooc() then s.reason="restore_waiting_combat";record();return false end
    local pending=false
    if s.sizePending then
        local w,h=size()
        if not w then pending=true;s.reason="restore_size_unreadable"
        elseif s.externalSizeObserved then s.sizePending=false;s.externalSize=true
        elseif w==s.width and h==s.height then s.sizePending=false;s.sizeRestored=true
        elseif not s.ownedWidth or not s.ownedHeight then
            pending=true;s.reason="restore_size_ownership_unreadable_or_reload"
        elseif w==s.ownedWidth and h==s.ownedHeight then
            s.restoreSetterAccepted=setSize(s.width,s.height)
            local rw,rh=size()
            if s.externalSizeObserved then s.sizePending=false;s.externalSize=true
            elseif rw==s.width and rh==s.height then s.sizePending=false;s.sizeRestored=true
            else
                -- A restore setter may also clamp or partially mutate before
                -- failing. Own only its immediate public readback, not the
                -- requested dimensions, and retain unknown ownership on error.
                s.ownedWidth,s.ownedHeight=rw,rh
                pending=true;s.reason=rw and "restore_size_refused" or "restore_size_ownership_unreadable_or_reload"
            end
        else s.sizePending=false;s.externalSize=true end -- A newer setting belongs to its new owner.
    end
    for _,part in ipairs(s.parts) do
        if part.touched then
            local uf=owner(part.plate)
            if part.retired then
                -- Native removal/addition rebuilt the unit. Do not apply an old
                -- UF or old unit's hit configuration to its replacement. The
                -- engine does NOT reset stacking on pool reuse: restore only
                -- that field to its fresh, verified current native owner.
                if uf and write(part.plate,"SetStackingBoundsFrame",uf) then
                    part.touched=false;write(part.box,"Hide")
                else pending=true;s.reason="restore_waiting_native_owner_or_reload" end
            elseif uf~=part.uf then pending=true;s.reason="restore_waiting_native_reset"
            elseif read(part.plate,"CanChangeHitTestPoints")~=true then pending=true;s.reason="restore_not_permitted"
            elseif write(uf,"ClearAllPoints") and write(uf,"SetAllPoints",part.plate)
                and write(part.plate,"SetStackingBoundsFrame",uf)
                and write(uf,"UpdateHitTestArea",NamePlateSetupOptions) then
                part.touched=false
                write(part.box,"Hide")
            else pending=true;s.reason="restore_default_refused" end
        end
    end
    if pending then record();return false end
    lastReason=s.externalSize and "native_defaults_restored_external_size_kept" or "native_defaults_restored_unmeasured"
    if not write(card,"Hide") then s.reason="restore_card_hide_refused";record();return false end
    if s.proxy then write(s.proxy,"Hide") end
    state=nil;record();return true
end
local function stop(reason)
    if not state then return true end
    state.active=false;state.stopping=true;state.reason=reason or "disabled"
    return cleanup()
end
local function deferStop(reason)
    if not state then return end
    state.active=false;state.stopping=true;state.reason=reason;record()
end
local function retire(plate,unit)
    if not state then return end
    for _,part in ipairs(state.parts) do
        if part.plate==plate or (unit and part.unit==unit) then part.retired=true end
    end
end
local function installHooks()
    if hooksInstalled then return true end
    if type(hooksecurefunc)~="function" or not object(NamePlateDriverFrame) then return false end
    for _,key in ipairs({"OnNamePlateAdded","OnNamePlateRemoved","UpdateNamePlateOptions","UpdateNamePlateSize"}) do
        if type(member(NamePlateDriverFrame,key))~="function" then return false end
    end
    for _,key in ipairs({"OnNamePlateAdded","OnNamePlateRemoved","UpdateNamePlateOptions","UpdateNamePlateSize"}) do
        local callback=(key=="OnNamePlateAdded" or key=="OnNamePlateRemoved") and function(_,unit)
            if state and not writing then retire(plateFor(unit),unit);deferStop("native_plate_reset") end
        end or function()
            if state and not writing then deferStop("native_options_changed") end
        end
        if not pcall(hooksecurefunc,NamePlateDriverFrame,key,callback) then return false end
    end
    if type(C_NamePlate and C_NamePlate.SetNamePlateSize)~="function" then return false end
    if not pcall(hooksecurefunc,C_NamePlate,"SetNamePlateSize",function(w,h)
        if not state then return end
        local own=ownSizeRequest and NS.Number(w) and NS.Number(h)
            and w==ownSizeRequest[1] and h==ownSizeRequest[2]
        if not own then
            state.externalSizeObserved=true
            if not writing then deferStop("external_size_setter") end
        end
    end) then return false end
    hooksInstalled=true;return true
end

local function sizeFailure(s,reason)
    stop(reason)
    local d=NS.Diagnostics
    if d and NS.Read(d.Enabled)==true and type(d.Record)=="function" then
        local w,h=size()
        pcall(d.Record,"ENEMY_NATIVE_TRIAL_SIZE_RESULT",{reason=reason,version=NS.Text(NS.VERSION),
            unit=s.unit,expectedGUID=s.guid,requestedWidth=s.giant,requestedHeight=s.giant,
            baselineWidth=s.width,baselineHeight=s.height,actualWidth=s.actualWidth,actualHeight=s.actualHeight,
            immediateReadbackReadable=s.actualWidth~=nil,setterAccepted=s.sizeSetterAccepted==true,
            finalWidth=w,finalHeight=h,restorationReadbackReadable=w~=nil,
            restoredOriginal=w==s.width and h==s.height,restoreSetterAccepted=s.restoreSetterAccepted==true,
            externalSetterObserved=s.externalSizeObserved==true,cleanupComplete=state~=s,
            mappingAccepted=false})
    end
    return false,reason
end

function T.Enable(row)
    if state and not stop("restarting") then return false,"restore_pending" end
    local function fail(reason) lastReason=reason;return false,reason end
    if not ooc() then return fail("combat_or_unknown") end
    local unit,expected=member(row,"unit"),member(row,"expectedGUID")
    if member(row,"side")~="enemy" or not NS.ValidToken(unit) or not unit:match("^nameplate%d+$")
        or type(expected)~="string" or expected=="" or read(row,"IsShown")~=true then return fail("invalid_row") end
    local plate=plateFor(unit);local uf=owner(plate)
    local s={unit=unit,guid=expected,plate=plate,uf=uf,parts={},active=false,age=0,reason="preparing"}
    local started=NS.Read(GetTime);s.startedAt=NS.Number(started) and started or nil
    if not uf or not identity(s) or read(plate,"CanChangeHitTestPoints")~=true then return fail("native_owner_unavailable") end
    s.width,s.height=size()
    local w,h=NS.Read(GetPhysicalScreenSize)
    if not s.width or not NS.Number(w) or not NS.Number(h) or w<=0 or h<=0 then return fail("size_unavailable") end
    s.giant=6*math.max(w,h)
    local plates=NS.Read(C_NamePlate.GetNamePlates)
    if not object(plates) or type(plates)~="table" then return fail("plates_unavailable") end
    local found=false
    for _,p in ipairs(plates) do
        local f=owner(p)
        if not f or read(p,"CanChangeHitTestPoints")~=true then return fail("other_native_owner_unavailable") end
        s.parts[#s.parts+1]={plate=p,uf=f,unit=read(p,"GetUnit"),touched=false}
        found=found or p==plate
        if #s.parts>100 then return fail("too_many_plates") end
    end
    if not found then return fail("native_plate_not_listed") end
    if not installHooks() then return fail("native_hooks_unavailable") end
    if not setupCard(NS.Text(NS.Read(UnitName,unit))) then return fail("card_unavailable") end
    state=s
    -- Each potentially partial mutation is owned before calling it, so a
    -- throwing or synchronously refused setter still enters cleanup.
    s.sizePending=true
    local sized=setSize(s.giant,s.giant)
    local rw,rh=size()
    s.sizeSetterAccepted=sized;s.actualWidth,s.actualHeight=rw,rh
    if not s.externalSizeObserved then s.ownedWidth,s.ownedHeight=rw,rh end
    if s.externalSizeObserved then return sizeFailure(s,"external_size_during_setup") end
    if not rw then return sizeFailure(s,"size_readback_unavailable") end
    if rw~=s.giant or rh~=s.giant then return sizeFailure(s,"size_clamped") end
    if not sized then return sizeFailure(s,"size_write_refused") end
    for _,part in ipairs(s.parts) do
        if owner(part.plate)~=part.uf then stop("native_owner_changed");return false,s.reason end
        part.box=NS.Read(CreateFrame,"Frame",nil,part.plate)
        if not part.box or not write(part.box,"EnableMouse",false)
            or not write(part.box,"SetSize",s.width,s.height)
            or not write(part.box,"SetPoint","BOTTOM",part.plate,"BOTTOM",0,0) then
            stop("normal_box_failed");return false,s.reason
        end
        part.touched=true
        if not write(part.uf,"ClearAllPoints") or not write(part.uf,"SetAllPoints",part.box)
            or not write(part.plate,"SetStackingBoundsFrame",part.box) then
            stop("normal_layout_refused");return false,s.reason
        end
    end
    if not identity(s) or read(plate,"CanChangeHitTestPoints")~=true then stop("identity_changed");return false,s.reason end
    local proxy=NS.Read(CreateFrame,"Frame",nil,plate)
    s.proxy=proxy
    if not proxy or not write(proxy,"EnableMouse",false) or not write(proxy,"SetAllPoints",card)
        or not write(plate,"SetAllHitTestPoints",proxy) then stop("hit_test_refused");return false,s.reason end
    if not ooc() or not identity(s) then stop("setup_identity_or_combat_changed");return false,s.reason end
    s.mappingAccepted=true;s.active=true;s.reason="accepted_unmeasured"
    record();return true,s.reason
end
function T.Disable() return stop("disabled") end
function T.Tick(elapsed)
    local s=state
    if not s then return end
    if s.stopping then cleanup();return end
    local now=NS.Read(GetTime)
    if s.startedAt and NS.Number(now) and now>=s.startedAt then s.age=math.max(s.age,now-s.startedAt)
    else s.age=s.age+(NS.Number(elapsed) and math.max(0,elapsed) or 0) end
    if s.age>=T.MAX_SECONDS then stop("timeout");return end
    if not ooc() then stop("combat_or_unknown");return end
    if not identity(s) then stop("identity_changed");return end
    local w,h=size()
    if w~=s.giant or h~=s.giant then stop("external_size_changed");return end
    record()
end
function T.OnEvent(event,unit)
    if (event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN") and unit==addonName and writing then
        refused=true;return
    end
    if not state or writing then return end
    if event=="NAME_PLATE_UNIT_REMOVED" and NS.ValidToken(unit) then
        stop("native_plate_removed")
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        -- The secure post-hook observes the completed native reset. A raw event
        -- can precede Blizzard and is not accepted as reset proof.
    elseif event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT"
        or event=="DISPLAY_SIZE_CHANGED" or event=="UI_SCALE_CHANGED" then stop(event:lower())
    elseif event=="CVAR_UPDATE" and type(unit)=="string" and unit:lower():find("nameplate",1,true) then stop("native_options_changed")
    elseif event=="PLAYER_REGEN_ENABLED" then T.Tick(0) end
end
