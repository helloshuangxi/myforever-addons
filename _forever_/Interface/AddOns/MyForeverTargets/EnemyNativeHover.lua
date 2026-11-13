local _, NS = ...
-- Optional single-nameplate diagnostic. No global geometry, spell, binding or
-- target action belongs to this module. A successful setup is not a cast proof.
local H = {}
NS.EnemyNativeHover = H
local current, proxy, lastReason = nil, nil, "disabled"
local lastUnit, lastGUID, lastLogSignature
local probed=setmetatable({}, {__mode="k"})
local probeSession
local points={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,
    BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}

local function method(object,key)
    if not NS.Public(object) or (type(object)~="table" and type(object)~="userdata") then return nil end
    local ok,value=pcall(function() return object[key] end)
    return ok and NS.Public(value) and type(value)=="function" and value or nil
end
local function read(object,key,...) return NS.Read(method(object,key),object,...) end
local function write(object,key,...)
    if NS.Read(InCombatLockdown)~=false then return false end
    local fn=method(object,key)
    if not fn then return false end
    local ok,value=pcall(fn,object,...)
    return ok and NS.Public(value) and value~=false
end
local function bool(object,key)
    local value=read(object,key)
    if value==true or value==false then return value end
end
local function guid(unit)
    local value=NS.Read(UnitGUID,unit)
    return type(value)=="string" and value~="" and value or nil
end
local function ooc() return NS.Read(InCombatLockdown)==false end
local function plateFor(unit) return NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit) end
local function writable(plate)
    return bool(plate,"IsForbidden")==false and bool(plate,"CanChangeHitTestPoints")==true
end

local function anchors(plate)
    local value=read(plate,"GetHitTestPoints")
    if type(value)~="table" then return nil end
    local ok,result=pcall(function()
        local count=#value
        if count>8 then return nil end
        for key in pairs(value) do
            if not NS.Number(key) or key%1~=0 or key<1 or key>count then return nil end
        end
        local copied={}
        for i=1,count do
            local a=value[i]
            if not NS.Public(a) or type(a)~="table" then return nil end
            local point,relativeTo,relativePoint,x,y=a.point,a.relativeTo,a.relativePoint,a.offsetX,a.offsetY
            if not NS.Public(point) or type(point)~="string" or not points[point]
                or not NS.Public(relativePoint) or type(relativePoint)~="string" or not points[relativePoint]
                or not NS.Public(relativeTo) or (type(relativeTo)~="table" and type(relativeTo)~="userdata")
                or not NS.Number(x) or not NS.Number(y) then return nil end
            copied[i]={point=point,relativeTo=relativeTo,relativePoint=relativePoint,offsetX=x,offsetY=y}
        end
        return copied
    end)
    return ok and result or nil
end
local function sameAnchors(a,b)
    if not a or not b or #a~=#b then return false end
    for i,x in ipairs(a) do
        local y=b[i]
        if x.point~=y.point or x.relativeTo~=y.relativeTo or x.relativePoint~=y.relativePoint
            or x.offsetX~=y.offsetX or x.offsetY~=y.offsetY then return false end
    end
    return true
end
local function usesProxy(a,p)
    if not a then return false end
    for _,v in ipairs(a) do if v.relativeTo==p then return true end end
    return false
end
local function fullProxy(a,p)
    if not a or #a~=2 then return false end
    local seen={}
    for _,v in ipairs(a) do
        if v.relativeTo~=p or v.point~=v.relativePoint or v.offsetX~=0 or v.offsetY~=0
            or (v.point~="TOPLEFT" and v.point~="BOTTOMRIGHT") or seen[v.point] then return false end
        seen[v.point]=true
    end
    return seen.TOPLEFT and seen.BOTTOMRIGHT
end

local function rowIdentity(row,unit,expected)
    if not NS.Public(row) or (type(row)~="table" and type(row)~="userdata") then return false,"invalid_row" end
    local ok,side,rowUnit,rowGUID=pcall(function() return row.side,row.unit,row.expectedGUID end)
    if not ok or not NS.Public(side) or side~="enemy" or not NS.Public(rowUnit)
        or type(rowUnit)~="string" or not rowUnit:match("^nameplate%d+$") or not NS.ValidToken(rowUnit)
        or not NS.Public(rowGUID) or type(rowGUID)~="string" or rowGUID=="" then return false,"invalid_row" end
    if unit and (rowUnit~=unit or rowGUID~=expected) then return false,"row_rebound" end
    if bool(row,"IsShown")~=true then return false,"row_hidden" end
    if NS.Read(UnitExists,rowUnit)~=true or NS.Read(UnitCanAttack,"player",rowUnit)~=true
        or NS.Read(UnitIsDeadOrGhost,rowUnit)~=false then return false,"unit_unavailable" end
    if guid(rowUnit)~=rowGUID then return false,"identity_changed" end
    return true,rowUnit,rowGUID
end

function H.Status()
    local s=current
    local actual=guid("mouseover")
    local status={configured=s~=nil and s.configured==true,restoring=s~=nil and s.restoring==true,
        reason=s and s.reason or lastReason,unit=s and s.unit or lastUnit,
        expectedGUID=s and s.guid or lastGUID,actualMouseoverGUID=actual,matches=false}
    if s then
        status.inputClick=bool(s.row,"IsMouseClickEnabled")
        status.inputMotion=bool(s.row,"IsMouseMotionEnabled")
        status.pointerOver=bool(s.row,"IsMouseOver")
        status.anchorPending=s.anchorPending==true
        status.inputPending=s.motionPending==true
        status.identityCurrent=rowIdentity(s.row,s.unit,s.guid)==true and plateFor(s.unit)==s.plate and not s.retired
        status.matches=status.configured and status.identityCurrent and status.pointerOver==true and actual==s.guid
        if status.matches then status.reason="native_mouseover_matches" end
    end
    return status
end
local function record()
    local d=NS.Diagnostics
    if not d or NS.Read(d.Enabled)~=true or type(d.Record)~="function" then return end
    local status=H.Status()
    local fields={}
    for _,key in ipairs({"configured","restoring","reason","unit","expectedGUID","actualMouseoverGUID",
        "matches","inputClick","inputMotion","pointerOver","anchorPending","inputPending","identityCurrent"}) do
        local value=status[key]
        fields[#fields+1]=type(value)=="boolean" and (value and "1" or "0") or NS.Text(value)
    end
    local signature=table.concat(fields,"|")
    if signature==lastLogSignature then return end
    lastLogSignature=signature
    pcall(d.Record,"ENEMY_NATIVE_HOVER_STATUS",status)
end

local function recover()
    local s=current
    if not s then return true end
    if not ooc() then s.reason="restore_combat_or_unknown";return false end
    local reason
    -- Reverse the input change before releasing the engine hit-test mapping.
    if s.motionPending then
        local now=bool(s.row,"IsMouseMotionEnabled")
        if now==nil then reason="restore_input_unreadable"
        elseif now~=false then s.motionPending=false -- A different owner already changed it.
        elseif not write(s.row,"SetMouseMotionEnabled",s.motionBefore)
            or bool(s.row,"IsMouseMotionEnabled")~=s.motionBefore then reason="restore_input_refused"
        else s.motionPending=false end
    end
    if s.anchorPending then
        local now=anchors(s.plate)
        -- A previously unreadable setter result can later be verified through
        -- the unique private proxy, without guessing from a unit/GUID alone.
        if not s.owned and fullProxy(now,s.proxy) then s.owned=now end
        if not now then reason=reason or "restore_anchors_unreadable"
        elseif sameAnchors(now,s.before) then s.anchorPending=false
        elseif s.owned and not sameAnchors(now,s.owned) then
            -- Never overwrite an external replacement, including changes that
            -- still refer to our proxy. Do not reuse that proxy afterwards.
            s.anchorPending=false;s.external=true
            if usesProxy(now,s.proxy) then s.relinquished=true;proxy=nil end
        elseif not usesProxy(now,s.proxy) then s.anchorPending=false;s.external=true
        elseif not s.owned then reason=reason or "restore_anchor_ownership_unconfirmed"
        elseif s.retired or guid(s.unit)~=s.guid or plateFor(s.unit)~=s.plate then
            reason=reason or "restore_identity_changed_waiting_native_reset"
        elseif not writable(s.plate) then reason=reason or "restore_not_permitted"
        elseif not write(s.plate,"SetHitTestPoints",s.before) or not sameAnchors(anchors(s.plate),s.before) then
            reason=reason or "restore_anchors_refused"
        else s.anchorPending=false end
    end
    if s.motionPending or s.anchorPending then s.reason=reason or "restore_pending";return false end
    if not s.relinquished then write(s.proxy,"Hide") end
    lastReason=s.external and "disabled_external_anchor_change" or s.stopReason or "disabled"
    lastUnit,lastGUID=s.unit,s.guid
    current=nil
    return true
end
local function stop(reason)
    if not current then
        reason=reason or "disabled"
        if lastReason~=reason then lastReason=reason;record() end
        return true
    end
    current.configured=false;current.restoring=true;current.stopReason=reason or "disabled"
    local done=recover();record();return done
end

function H.Enable(row)
    if current then
        H.Tick()
    end
    if current then
        if current.configured and current.row==row then return true,current.reason end
        if not stop("disabled") then return false,"restore_pending" end
    end
    local function fail(reason) lastReason=reason;record();return false,reason end
    if not ooc() then return fail("combat_or_unknown") end
    local valid,unit,expected=rowIdentity(row)
    if not valid then return fail(unit) end
    lastUnit,lastGUID=unit,expected
    local plate=plateFor(unit)
    if not plate or bool(plate,"IsForbidden")~=false then return fail("native_plate_unavailable") end
    if not writable(plate) then return fail("hit_test_not_permitted") end
    if not method(plate,"SetAllHitTestPoints") or not method(plate,"SetHitTestPoints")
        or not method(row,"SetMouseMotionEnabled") then return fail("api_unavailable") end
    local before=anchors(plate)
    if not before then return fail("anchors_unreadable") end
    local click,motion=bool(row,"IsMouseClickEnabled"),bool(row,"IsMouseMotionEnabled")
    if click==nil or motion==nil then return fail("input_unreadable") end
    if not proxy then
        proxy=NS.Read(CreateFrame,"Frame",nil,UIParent)
        if not proxy then return fail("proxy_unavailable") end
    end
    if not write(proxy,"EnableMouse",false) or not write(proxy,"ClearAllPoints")
        or not write(proxy,"SetAllPoints",row) or not write(proxy,"Show") then return fail("proxy_setup_failed") end
    if not ooc() or not rowIdentity(row,unit,expected) or plateFor(unit)~=plate or not writable(plate)
        or not sameAnchors(anchors(plate),before) or bool(row,"IsMouseClickEnabled")~=click
        or bool(row,"IsMouseMotionEnabled")~=motion then return fail("setup_preconditions_changed") end
    current={row=row,plate=plate,proxy=proxy,unit=unit,guid=expected,before=before,
        clickBefore=click,motionBefore=motion,anchorPending=true,motionPending=false,
        configured=false,restoring=false,reason="preparing"}
    local mapped=write(plate,"SetAllHitTestPoints",proxy)
    local owned=anchors(plate)
    if fullProxy(owned,proxy) then current.owned=owned end
    if not mapped or not current.owned then
        stop(mapped and "anchor_readback_failed" or "anchor_write_failed")
        return false,lastReason=="disabled" and "anchor_write_failed" or (current and current.reason or lastReason)
    end
    local stillValid=rowIdentity(row,unit,expected)
    if not stillValid or plateFor(unit)~=plate or not ooc() then
        stop("identity_changed_during_setup");return false,current and current.reason or lastReason
    end
    if motion~=false then
        current.motionPending=true
        if not write(row,"SetMouseMotionEnabled",false) or bool(row,"IsMouseMotionEnabled")~=false then
            stop("input_write_failed");return false,current and current.reason or lastReason
        end
    end
    if not ooc() or not rowIdentity(row,unit,expected) or plateFor(unit)~=plate
        or bool(row,"IsMouseClickEnabled")~=click or not sameAnchors(anchors(plate),current.owned) then
        stop("setup_readback_changed");return false,current and current.reason or lastReason
    end
    current.configured=true;current.reason="configured_unverified"
    lastUnit,lastGUID=unit,expected
    record()
    return true,"configured_unverified"
end

function H.Disable()
    local done=stop("disabled")
    return done,current and current.reason or lastReason
end
function H.Tick()
    local s=current
    if not s then return end
    if s.restoring then recover();record();return end
    local valid,reason=rowIdentity(s.row,s.unit,s.guid)
    if not valid or plateFor(s.unit)~=s.plate then stop(not valid and reason or "native_plate_changed");return end
    local now=anchors(s.plate)
    if not now or not sameAnchors(now,s.owned) then stop(now and "external_anchor_change" or "anchors_unreadable");return end
    if bool(s.row,"IsMouseMotionEnabled")~=false then stop("external_input_change");return end
    record()
end
function H.OnEvent(event,unit)
    if not current then return end
    if event=="NAME_PLATE_UNIT_REMOVED" and NS.Public(unit) and unit==current.unit then
        current.retired=true;stop("nameplate_removed")
    elseif event=="PLAYER_LOGOUT" or event=="PLAYER_LEAVING_WORLD" or event=="DISPLAY_SIZE_CHANGED"
        or event=="UI_SCALE_CHANGED" then stop(event:lower())
    else H.Tick() end
end

-- Read-only capability sampling is separate from Enable's strict snapshot
-- transaction. Main invokes this from its file-defined normal OnUpdate; merely
-- delaying a /run-created closure would not establish the same call context.
-- Keep only the latest GUID for each weakly referenced plate. A new diagnostic
-- session starts a fresh cache, so native pooling cannot grow a history and a
-- reopened log still captures the same creature. Reset is also a read-free hook.
function H.ResetProbeReadback()
    probed=setmetatable({}, {__mode="k"})
    probeSession=nil
end
function H.ProbeReadback(row)
    local d=NS.Diagnostics
    if not d or NS.Read(d.Enabled)~=true or type(d.Record)~="function" then
        return false,{reason="logging_disabled"}
    end
    local session=NS.Read(d.Session)
    if not NS.Number(session) or session<0 or session%1~=0 then session=nil end
    if session~=probeSession then
        H.ResetProbeReadback()
        probeSession=session
    end
    if not NS.Public(row) or (type(row)~="table" and type(row)~="userdata") then
        return false,{reason="invalid_row"}
    end
    local ok,side,unit,expected=pcall(function() return row.side,row.unit,row.expectedGUID end)
    if not ok or not NS.Public(side) or side~="enemy" or not NS.ValidToken(unit)
        or not NS.Public(expected) or type(expected)~="string" or expected==""
        or bool(row,"IsShown")~=true then return false,{reason="invalid_row"} end
    if NS.Read(UnitExists,unit)~=true or NS.Read(UnitCanAttack,"player",unit)~=true
        or NS.Read(UnitIsVisible,unit)~=true or guid(unit)~=expected then
        return false,{reason="unit_unavailable"}
    end
    local plate=plateFor(unit)
    if not NS.Public(plate) or (type(plate)~="table" and type(plate)~="userdata") then
        return false,{reason="native_plate_unavailable"}
    end
    if probed[plate]==expected then return false,{reason="already_recorded"} end

    local function errorText(value)
        if not NS.Public(value) then return "[restricted-error]" end
        local text=NS.Text(value)
        return text~="" and text or "[api-error]"
    end
    local function call(key)
        local lookup,fn=pcall(function() return plate[key] end)
        if not lookup then return false,nil,errorText(fn) end
        if not NS.Public(fn) then return false,nil,"[restricted-method]" end
        if type(fn)~="function" then return false,nil,"[api-unavailable]" end
        local success,value=pcall(fn,plate)
        if not success then return false,nil,errorText(value) end
        return true,value
    end
    local fields={version=NS.Text(NS.VERSION),unit=unit,expectedGUID=expected,
        source="native_hover_probe_readback"}
    local function booleanCall(key,prefix)
        local success,value,err=call(key)
        fields[prefix.."CallOK"]=success
        local readable=success and NS.Public(value) and type(value)=="boolean"
        fields[prefix.."Readable"]=readable
        if readable then fields[prefix]=value end
        if err then fields[prefix.."Error"]=err end
    end
    booleanCall("IsForbidden","forbidden")
    booleanCall("CanChangeHitTestPoints","canChange")
    local got,value,err=call("GetHitTestPoints")
    fields.hitTestPointsCallOK=got
    fields.hitTestPointsReadable=false
    if got and NS.Public(value) and type(value)=="table" then
        local counted,count=pcall(function() return #value end)
        if counted and NS.Number(count) and count>=0 and count%1==0 then
            fields.hitTestPointsReadable=true;fields.anchorCount=count
        end
    end
    if err then fields.hitTestPointsError=err
    elseif got and not fields.hitTestPointsReadable then fields.hitTestPointsError="[restricted-or-invalid-result]" end
    local unitOK,plateUnit,unitErr=call("GetUnit")
    fields.plateUnitCallOK=unitOK
    if unitOK and NS.Public(plateUnit) and type(plateUnit)=="string" then fields.plateUnit=NS.Text(plateUnit) end
    if unitErr then fields.plateUnitError=unitErr end
    local frameOK,unitFrame=pcall(function() return plate.UnitFrame end)
    fields.unitFrameReadable=frameOK and NS.Public(unitFrame)
    if fields.unitFrameReadable then
        fields.hasUnitFrame=type(unitFrame)=="table" or type(unitFrame)=="userdata"
    elseif not frameOK then fields.unitFrameError=errorText(unitFrame) end
    local recorded,result=pcall(d.Record,"ENEMY_NATIVE_HOVER_CAPABILITY",fields)
    local saved=recorded and NS.Public(result) and result==true
    if saved then probed[plate]=expected end
    return saved,fields
end
