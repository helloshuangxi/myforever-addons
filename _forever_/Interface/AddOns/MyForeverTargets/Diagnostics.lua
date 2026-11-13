local _, NS = ...
local D = {MAX_EVENTS=5000, MAX_SECONDS=14400, CAST_WINDOW_SECONDS=5}
NS.Diagnostics = D
local db, frame, tick, lastState = nil, nil, 0, nil
local layoutTick,layoutStates=0,{}
local castWindows,attemptSerial={},0

-- Keep diagnostics outside the settings normalizer. Never serialize a secret,
-- frame, arbitrary table, macro body, chat message, or Lua error stack.
local function safe(value)
    if not NS.Public(value) then return "[restricted]" end
    local kind=type(value)
    if kind=="string" then
        local text=NS.Text(value)
        local length=math.min(#text,256)
        -- Keep Chinese marks/errors valid UTF-8 when limiting saved strings.
        while length>0 and length<#text do
            local byte=text:byte(length+1)
            if byte<128 or byte>191 then break end
            length=length-1
        end
        return text:sub(1,length)
    end
    if kind=="boolean" then return value end
    if kind=="number" then return NS.Number(value) and value or "[invalid-number]" end
    if value==nil then return "[nil]" end
    return "[unsupported]"
end
D.Safe=safe

local nativeMouseoverFields={"expectedGUID","mouseoverGUID","unitGUID","identityMatches",
    "conditionMatched","condition","reason"}
local nativeConditionLabels={["[restricted]"]=true,["[api-error]"]=true,["[invalid-condition]"]=true}
local function nativeMouseoverCopy(details)
    if not NS.Public(details) or type(details)~="table" then return nil end
    local copied={}
    for _,key in ipairs(nativeMouseoverFields) do
        local ok,value=pcall(function() return details[key] end)
        if not ok then copied[key]="[api-error]"
        elseif not NS.Public(value) or value~=nil then
            if key=="condition" and NS.Public(value) and value~="[@mouseover,nodead,harm]"
                and value~="[@mouseover,nodead,help]" and not nativeConditionLabels[value] then copied[key]="[invalid-condition]"
            else copied[key]=safe(value) end
        end
    end
    return copied
end

local function nativeMouseoverDetails(row)
    if type(NS.NativeMouseoverStatus)~="function" then return {reason="status_unavailable"} end
    local ok,_,_,details=pcall(NS.NativeMouseoverStatus,row)
    if not ok then return {reason="status_error"} end
    if not NS.Public(details) then return {reason="[restricted]"} end
    return nativeMouseoverCopy(details) or {reason="status_unavailable"}
end

local function read(fn,...)
    if type(fn)~="function" then return "[unavailable]" end
    local ok,value=pcall(fn,...)
    if not ok then return "[api-error]" end
    return safe(value)
end

local function professionsGatherMethod()
    local settings=MyForeverProfessionsDB
    if not NS.Public(settings) then return "[restricted]" end
    if type(settings)~="table" then return "[unknown]" end
    local value=read(function() return settings.gatherMethod end)
    if value=="original" or value=="cursor" or value=="[restricted]" or value=="[api-error]" then return value end
    return "[unknown]"
end

local function fieldsCopy(fields)
    local result,count={},0
    if not NS.Public(fields) or type(fields)~="table" then return result end
    for key,value in pairs(fields) do
        if NS.Public(key) and type(key)=="string" and #key<=48 then
            -- This one bounded diagnostic payload is copied by field name;
            -- arbitrary nested tables and user macro contents remain excluded.
            if key=="nativeMouseover" and NS.Public(fields.nativeMacroOnly) and fields.nativeMacroOnly==true then
                result[key]=nativeMouseoverCopy(value) or safe(value)
            else result[key]=safe(value) end
            count=count+1
            if count>=64 then break end
        end
    end
    return result
end

local function append(kind,fields)
    if not db then return end
    db.sequence=db.sequence+1
    local record={sequence=db.sequence,session=db.session,time=read(GetTime),
        serverTime=read(GetServerTime),kind=safe(kind),fields=fieldsCopy(fields)}
    record.fields.professionsGatherMethod=professionsGatherMethod()
    if #db.events>=D.MAX_EVENTS then
        table.remove(db.events,1)
        db.dropped=db.dropped+1
    end
    db.events[#db.events+1]=record
end

function D.Enabled() return db~=nil and db.enabled==true end
function D.Session() return db and db.session end

function D.Record(kind,fields)
    if not D.Enabled() then return false end
    -- Logging must never abort the action it observes.
    return pcall(append,kind,fields)
end

local function now()
    local value=NS.Read(GetTime)
    return NS.Number(value) and value or nil
end

local function windowAge(window,current)
    local age=window.age
    if current and window.startedAt and current>=window.startedAt then age=math.max(age,current-window.startedAt) end
    return age
end

local function generatedCommand(value)
    if not NS.Public(value) or type(value)~="string" or #value>256
        or value:find("[%z\1-\31\127|;\\]") or not value:match("^/cast%s+")
        or value:sub(2):find("/",1,true) then return nil end
    local identity,spell=value:match("^/cast %[@([^%]]+)%] (.+)$")
    if not identity or not identity:match("^[%a]+%-%w[%w%-]*$") or not spell
        or spell:match("^%s") or spell:match("%s$") or spell:find("[%[%]]") then return nil end
    return value
end

local attemptFieldNames={"spellID","expectedGUID","row","route","slot","rowUnit","side","combat","actionKind",
    "beforeTargetGUID","beforeTargetExists","targetGUIDBefore","targetExistsBefore","targetGUID","targetExists",
    "configuredCommand","configuredKey1","configuredKey2","configuredKey3","configuredKey4","button","down",
    "selectedActionType","selectedCommandMatches","snapshotGUID","snapshotUnit","unitArg"}

local function finishWindow(id,window,reason,current)
    local castCount=window.sentCount+window.succeededCount+window.failedCount+window.otherCastEventCount
    local outcome=reason=="stopped" and "stopped" or not window.spellID and "unreadable_spell_id"
        or castCount==0 and "no_cast_event_observed" or "cast_event_observed"
    D.Record("HOVER_CAST_WINDOW_SUMMARY",{attemptID=id,spellID=window.fields.spellID,
        expectedGUID=window.fields.expectedGUID,row=window.fields.row,route=window.fields.route,
        windowSeconds=D.CAST_WINDOW_SECONDS,elapsedSeconds=windowAge(window,current),
        sentCount=window.sentCount,succeededCount=window.succeededCount,failedCount=window.failedCount,
        failedQuietCount=window.failedQuietCount,otherCastEventCount=window.otherCastEventCount,
        castEventCount=castCount,uiErrorCount=window.uiErrorCount,ambiguous=window.ambiguous,
        outcome=outcome,finishReason=reason,spellIDReadable=window.spellID~=nil,
        playerSpellEventsOnly=true,uiErrorsTimeOnly=true,recipientProven=false,
        note="Observed player spell events in a time window do not prove the recipient"})
    castWindows[id]=nil
end

local function finishWindows(reason)
    local current=now()
    for id,window in pairs(castWindows) do finishWindow(id,window,reason,current) end
end

function D.BeginCastAttempt(fields)
    if not D.Enabled() then return nil end
    local ok,id=pcall(function()
        if not NS.Public(fields) or type(fields)~="table" then return nil end
        local copied={}
        for _,key in ipairs(attemptFieldNames) do
            local value=fields[key]
            if not NS.Public(value) or value~=nil then copied[key]=safe(value) end
        end
        copied.generatedCommand=generatedCommand(fields.generatedCommand)
        local spell=fields.spellID
        if not NS.Number(spell) or spell<=0 or spell%1~=0 then spell=nil end
        local current=now()
        attemptSerial=math.max(attemptSerial,db.sequence)+1
        local serial=attemptSerial
        local window={fields=copied,spellID=spell,startedAt=current,age=0,ambiguous=false,
            sentCount=0,succeededCount=0,failedCount=0,failedQuietCount=0,otherCastEventCount=0,uiErrorCount=0}
        for _,previous in pairs(castWindows) do
            if spell and previous.spellID==spell and windowAge(previous,current)<D.CAST_WINDOW_SECONDS then
                previous.ambiguous,window.ambiguous=true,true
            end
        end
        castWindows[serial]=window
        local event={attemptID=serial,windowSeconds=D.CAST_WINDOW_SECONDS,ambiguous=window.ambiguous,
            spellIDReadable=spell~=nil,recipientProven=false}
        for key,value in pairs(copied) do event[key]=value end
        D.Record("HOVER_CAST_ATTEMPT",event)
        return serial
    end)
    if ok then return id end
end

local postReserved={attemptID=true,spellID=true,expectedGUID=true,row=true,route=true,recipientProven=true,
    windowSeconds=true,sentCount=true,succeededCount=true,failedCount=true,uiErrorCount=true,ambiguous=true}
function D.EndCastAttempt(id,fields)
    if not D.Enabled() then return false end
    return pcall(function()
        if not NS.Public(id) or not NS.Number(id) or id%1~=0 then return end
        local window=castWindows[id]
        local event={attemptID=id,recipientProven=false,windowOpen=window~=nil}
        if window then
            for _,key in ipairs({"spellID","expectedGUID","row","route"}) do event[key]=window.fields[key] end
        end
        local count=0
        if NS.Public(fields) and type(fields)=="table" then
            for key,value in pairs(fields) do
                if NS.Public(key) and type(key)=="string" and #key<=48 and not postReserved[key] then
                    local lower=key:lower()
                    if lower~="macro" and lower~="macrobody" and lower~="macrotext" and lower~="body" then
                        if key=="generatedCommand" then event[key]=generatedCommand(value)
                        else event[key]=safe(value) end
                        count=count+1
                        if count>=40 then break end
                    end
                end
            end
        end
        D.Record("HOVER_CAST_POST",event)
    end)
end

local function observeCastEvent(event,spell)
    if not NS.Number(spell) or spell<=0 or spell%1~=0 then return end
    local current=now()
    for _,window in pairs(castWindows) do
        if window.spellID==spell and windowAge(window,current)<D.CAST_WINDOW_SECONDS then
            if event=="UNIT_SPELLCAST_SENT" then window.sentCount=window.sentCount+1
            elseif event=="UNIT_SPELLCAST_SUCCEEDED" then window.succeededCount=window.succeededCount+1
            elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_FAILED_QUIET" then
                window.failedCount=window.failedCount+1
                if event=="UNIT_SPELLCAST_FAILED_QUIET" then window.failedQuietCount=window.failedQuietCount+1 end
            else window.otherCastEventCount=window.otherCastEventCount+1 end
        end
    end
end

local function observeUIError()
    local current=now()
    for _,window in pairs(castWindows) do
        if windowAge(window,current)<D.CAST_WINDOW_SECONDS then window.uiErrorCount=window.uiErrorCount+1 end
    end
end

local function updateCastWindows(delta)
    local current=now()
    for id,window in pairs(castWindows) do
        window.age=window.age+delta
        if windowAge(window,current)>=D.CAST_WINDOW_SECONDS then finishWindow(id,window,"elapsed",current) end
    end
end

local function unitFields(fields,prefix,unit)
    fields[prefix.."Unit"]=safe(unit)
    if not NS.Public(unit) or type(unit)~="string" then return end
    fields[prefix.."Exists"]=read(UnitExists,unit)
    fields[prefix.."GUID"]=read(UnitGUID,unit)
    fields[prefix.."Name"]=read(UnitName,unit)
    fields[prefix.."Player"]=read(UnitIsPlayer,unit)
    fields[prefix.."Harm"]=read(UnitCanAttack,"player",unit)
    fields[prefix.."Dead"]=read(UnitIsDeadOrGhost,unit)
end

local function samePublicGUID(a,b)
    if type(a)~="string" or type(b)~="string" or a=="" or b==""
        or a:sub(1,1)=="[" or b:sub(1,1)=="[" then return "[unknown]" end
    return a==b
end

local function snapshotFields(observedRow,observedFoci)
    local cast=NS.NearbyCast
    local row=observedRow or NS.HoveredEnemyTarget or NS.HoveredTile or (cast and cast.row)
    local fields={combat=read(InCombatLockdown),zBinding=read(GetBindingAction,"Z",true),
        wBinding=read(GetBindingAction,"W",true),bridgeCount=cast and cast.count or 0,
        bridgeUnit=cast and cast.row and cast.row.unit or "[none]",
        hoveredRow=row and read(row.GetName,row) or "[none]",
        side=row and safe(row.side) or "[none]",
        expectedGUID=row and safe(row.expectedGUID) or "[none]",
        frameUnitAttribute=row and read(row.GetAttribute,row,"unit") or "[none]",
        frameResolvedUnit=row and read(SecureButton_GetUnit,row) or "[none]",
        professionsGatherMethod=professionsGatherMethod()}
    unitFields(fields,"hover",row and row.unit)
    unitFields(fields,"target","target")
    unitFields(fields,"focus","focus")
    fields.focusMatchesHover=samePublicGUID(fields.focusGUID,fields.hoverGUID)
    fields.hoverRaidMarker=read(GetRaidTargetIndex,row and row.unit)
    fields.targetRaidMarker=read(GetRaidTargetIndex,"target")
    unitFields(fields,"nativeMouseover","mouseover")
    fields.nativeMouseoverMatchesHover=samePublicGUID(fields.nativeMouseoverGUID,fields.hoverGUID)
    fields.targetMatchesHover=samePublicGUID(fields.targetGUID,fields.hoverGUID)
    if NS.Public(NS.NativeMacroOnly) and NS.NativeMacroOnly==true then
        fields.nativeMacroOnly=true
        fields.nativeMouseover=nativeMouseoverDetails(row)
    end
    local combatCast=NS.CombatCast
    local prepared=combatCast and NS.Read(combatCast.Status,row)
    if type(prepared)=="table" then
        fields.combatPrepared=safe(prepared.prepared)
        fields.combatPreparedCount=safe(prepared.count)
        fields.combatSnapshotName=safe(prepared.name)
        fields.combatSnapshotGUID=safe(prepared.guid)
        fields.combatSnapshotUnit=safe(prepared.unit)
        fields.combatPrepareReason=safe(prepared.reason)
        fields.combatSnapshotMatchesHover=samePublicGUID(fields.combatSnapshotGUID,fields.hoverGUID)
    end
    if row and NS.Public(row.unit) and type(row.unit)=="string" then
        fields.rangeProbeSpellID=679
        fields.rangeProbe=read(C_Spell and C_Spell.IsSpellInRange,679,row.unit)
        local range=NS.Read(NS.MeasureDistance,row.unit)
        if type(range)=="table" then
            fields.distanceMin=safe(range.min)
            fields.distanceMax=safe(range.max)
            fields.distanceExact=safe(range.exact)
        else
            fields.distanceMin,fields.distanceMax,fields.distanceExact="[unknown]","[unknown]","[unknown]"
        end
    end
    local foci=observedFoci or NS.Read(GetMouseFoci)
    fields.focusOnHoveredRow=false
    if type(foci)=="table" then
        local names={}
        for i,focus in ipairs(foci) do
            if i>4 then break end
            if NS.Public(focus) then
                if focus==row then fields.focusOnHoveredRow=true end
                names[#names+1]=read(focus.IsForbidden,focus)==true and "[forbidden]" or read(focus.GetName,focus)
            end
        end
        fields.mouseFoci=table.concat(names,",")
    else fields.mouseFoci="[unavailable]" end
    return fields
end

local function object(value)
    local kind=type(value)
    return NS.Public(value) and (kind=="table" or kind=="userdata")
end

local function member(value,key)
    if not object(value) then return nil end
    return NS.Read(function() return value[key] end)
end

-- Keep layout evidence separate from the already bounded unit snapshot. All
-- coordinates below are converted into UIParent units; observation never
-- changes protected frames, even while the player is in combat.
local actionbarNames={"MainMenuBar","MainActionBar","MultiBarBottomLeft","MultiBarBottomRight",
    "MultiBarLeft","MultiBarRight","MultiBar5","MultiBar6","MultiBar7","PetActionBar",
    "StanceBar","PossessActionBar"}

local function layoutGeometry(region,rootScale)
    local fields={exists=object(region),rectStatus="unavailable"}
    if not fields.exists then return fields end
    fields.shown=read(member(region,"IsShown"),region)
    fields.visible=read(member(region,"IsVisible"),region)
    if read(member(region,"IsForbidden"),region)==true then
        fields.rectStatus="forbidden"
        return fields
    end
    fields.effectiveScale=read(member(region,"GetEffectiveScale"),region)
    local rect=member(region,"GetRect")
    if type(rect)~="function" then fields.rectStatus="rectangle_unavailable";return fields end
    local ok,left,bottom,width,height=pcall(rect,region)
    if not ok then fields.rectStatus="rectangle_api_error";return fields end
    fields.left,fields.bottom,fields.width,fields.height=safe(left),safe(bottom),safe(width),safe(height)
    if not NS.Number(left) or not NS.Number(bottom) or not NS.Number(width) or not NS.Number(height)
        or width<=0 or height<=0 then fields.rectStatus="rectangle_unreadable";return fields end
    if not NS.Number(fields.effectiveScale) or fields.effectiveScale<=0
        or not NS.Number(rootScale) or rootScale<=0 then fields.rectStatus="scale_unreadable";return fields end
    local ratio=fields.effectiveScale/rootScale
    local uiLeft,uiBottom,uiWidth,uiHeight=left*ratio,bottom*ratio,width*ratio,height*ratio
    if not NS.Number(uiLeft) or not NS.Number(uiBottom) or not NS.Number(uiWidth) or not NS.Number(uiHeight) then
        fields.rectStatus="rectangle_unreadable";return fields
    end
    fields.uiLeft,fields.uiBottom,fields.uiWidth,fields.uiHeight=uiLeft,uiBottom,uiWidth,uiHeight
    fields.rectStatus="public"
    return fields
end

local function layoutOverlap(a,b)
    if a.visible~=true or b.visible~=true or a.rectStatus~="public" or b.rectStatus~="public" then
        return "unknown"
    end
    return a.uiLeft<b.uiLeft+b.uiWidth and a.uiLeft+a.uiWidth>b.uiLeft
        and a.uiBottom<b.uiBottom+b.uiHeight and a.uiBottom+a.uiHeight>b.uiBottom
end

local function layoutKey(fields)
    local keys,parts={},{}
    for key in pairs(fields) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local value=fields[key]
        -- Ignore subpixel getter noise without discarding recorded geometry.
        if NS.Number(value) and math.abs(value)<10000000 then value=math.floor(value*100+.5)/100 end
        parts[#parts+1]=key.."="..tostring(safe(value))
    end
    return table.concat(parts,";")
end

local function recordLayout(kind,id,fields,reason)
    local key=layoutKey(fields)
    if layoutStates[id]==key then return end
    fields.reason,fields.observationOnly=reason or "poll",true
    if D.Record(kind,fields) then layoutStates[id]=key end
end

function D.LayoutSnapshot(reason)
    if not D.Enabled() then return false end
    return pcall(function()
        local parent=UIParent
        if not object(parent) then return end
        local rootScale=read(member(parent,"GetEffectiveScale"),parent)
        local physicalWidth,physicalHeight=NS.Read(GetPhysicalScreenSize)
        local screen={version=NS.VERSION,uiWidth=read(member(parent,"GetWidth"),parent),
            uiHeight=read(member(parent,"GetHeight"),parent),uiEffectiveScale=rootScale,
            physicalWidth=safe(physicalWidth),physicalHeight=safe(physicalHeight),coordinates="UIParent",
            actionbarScope="known_native_frames",overlapMeaning="rectangle_intersection"}
        local panels={}
        for _,side in ipairs({"friendly","enemy"}) do
            local section=member(NS.UI,side)
            local panel=member(section,"frame")
            local fields=layoutGeometry(panel,rootScale)
            fields.side,fields.uiEffectiveScale=side,rootScale
            fields.frameScale=read(member(panel,"GetScale"),panel)
            local position=member(NS.DB,side.."Position")
            for _,key in ipairs({"point","relativePoint","x","y","manual"}) do
                fields["saved"..key:sub(1,1):upper()..key:sub(2)]=safe(member(position,key))
            end
            local point=member(panel,"GetPoint")
            if type(point)=="function" then
                local ok,anchor,_,relativeAnchor,x,y=pcall(point,panel)
                if ok then
                    fields.point,fields.relativePoint,fields.x,fields.y=safe(anchor),safe(relativeAnchor),safe(x),safe(y)
                end
            end
            fields.actionbarOverlap="unknown"
            panels[side]=fields
        end
        local bars,visibleBars,unreadableBars={},0,0
        for _,name in ipairs(actionbarNames) do
            local region=member(_G,name)
            local fields=layoutGeometry(region,rootScale)
            fields.name,fields.uiEffectiveScale=name,rootScale
            if fields.exists then
                bars[#bars+1]=fields
                if fields.visible==true then
                    visibleBars=visibleBars+1
                    if fields.rectStatus~="public" then unreadableBars=unreadableBars+1 end
                elseif fields.visible~=false then unreadableBars=unreadableBars+1 end
            elseif layoutStates["bar:"..name] then
                -- A previously observed bar disappearing is evidence too.
                bars[#bars+1]=fields
            end
        end
        screen.visibleActionbars,screen.unreadableActionbars=visibleBars,unreadableBars
        for side,panel in pairs(panels) do
            local anyOverlap=false
            for _,bar in ipairs(bars) do
                local overlap=layoutOverlap(panel,bar)
                bar[side.."Overlap"]=overlap
                if overlap==true then anyOverlap=true end
            end
            if anyOverlap then panel.actionbarOverlap=true
            elseif visibleBars>0 and unreadableBars==0 and panel.visible==true and panel.rectStatus=="public" then
                panel.actionbarOverlap=false
            end
            recordLayout("LAYOUT_PANEL","panel:"..side,panel,reason)
        end
        recordLayout("LAYOUT_SCREEN","screen",screen,reason)
        for _,bar in ipairs(bars) do recordLayout("LAYOUT_ACTIONBAR","bar:"..bar.name,bar,reason) end
    end)
end

local function cursorPosition()
    if type(GetCursorPosition)~="function" then return nil,nil,"cursor_unavailable" end
    local ok,x,y=pcall(GetCursorPosition)
    if not ok then return nil,nil,"cursor_api_error" end
    if not NS.Number(x) or not NS.Number(y) then return nil,nil,"cursor_unreadable" end
    return x,y
end

local function focusWithin(foci,region)
    if type(foci)~="table" then return false end
    for i,focus in ipairs(foci) do
        if i>4 then break end
        for _=1,12 do
            if not object(focus) then break end
            if focus==region then return true end
            local parent=NS.Read(member(focus,"GetParent"),focus)
            if parent==focus then break end
            focus=parent
        end
    end
    return false
end

local function withinRegion(region,foci,x,y,cursorReason)
    if not object(region) then return false,nil,"region_unavailable" end
    if NS.Read(member(region,"IsForbidden"),region)==true then return false,nil,"region_forbidden" end
    local visible=member(region,"IsVisible") or member(region,"IsShown")
    if NS.Read(visible,region)~=true then return false,nil,"region_not_visible" end
    local reason=cursorReason or "rectangle_unreadable"
    if x and y then
        local left,bottom,width,height=NS.Read(member(region,"GetRect"),region)
        local scale=NS.Read(member(region,"GetEffectiveScale"),region)
        if NS.Number(left) and NS.Number(bottom) and NS.Number(width) and NS.Number(height)
            and NS.Number(scale) and width>0 and height>0 and scale>0 then
            local localX,localY=x/scale,y/scale
            if localX>=left and localX<=left+width and localY>=bottom and localY<=bottom+height then
                return true,"screen_rect","within_bounds"
            end
            reason="outside_bounds"
        end
    end
    if NS.Read(MouseIsOver,region)==true then return true,"mouse_is_over",reason end
    if focusWithin(foci,region) then return true,"focus_ancestry",reason end
    return false,nil,reason
end

local function mouseScope(foci)
    local x,y,cursorReason=cursorPosition()
    local ui=NS.UI
    local regions={{kind="marker_menu",frame=NS.MarkerMenu}}
    for _,side in ipairs({"friendly","enemy"}) do
        local section=member(ui,side)
        regions[#regions+1]={kind=side.."_panel",frame=member(section,"frame"),section=section}
    end
    local lastReason=cursorReason or "no_region_hit"
    for _,region in ipairs(regions) do
        local hit,method,reason=withinRegion(region.frame,foci,x,y,cursorReason)
        if hit then
            region.method,region.reason=method,reason
            local tiles=member(region.section,"tiles")
            if type(tiles)=="table" then
                for i,tile in ipairs(tiles) do
                    if i>20 then break end
                    local child=member(tile,"enemyTargetButton")
                    if withinRegion(child,foci,x,y,cursorReason) then region.row=child;break end
                    if withinRegion(tile,foci,x,y,cursorReason) then region.row=tile;break end
                end
            end
            return region
        end
        if reason~="region_unavailable" and reason~="region_not_visible" then lastReason=reason end
    end
    local hovered=NS.HoveredEnemyTarget or NS.HoveredTile
    if object(hovered) then
        return {kind="hovered_tile",row=hovered,frame=hovered,
            method="hovered_tile_fallback",reason=lastReason}
    end
end

local mouseSnapshotFields={"combat","zBinding","wBinding","hoveredRow","side","expectedGUID","frameUnitAttribute","frameResolvedUnit",
    "hoverUnit","hoverExists","hoverGUID","hoverPlayer","hoverHarm","hoverDead","hoverRaidMarker",
    "targetUnit","targetExists","targetGUID","targetMatchesHover","targetRaidMarker",
    "focusUnit","focusExists","focusGUID","focusMatchesHover",
    "nativeMouseoverUnit","nativeMouseoverExists","nativeMouseoverGUID","nativeMouseoverPlayer",
    "nativeMouseoverHarm","nativeMouseoverDead","nativeMouseoverMatchesHover","nativeMacroOnly","nativeMouseover",
    "mouseFoci","focusOnHoveredRow","professionsGatherMethod"}
local function observeGlobalMouse(event,button)
    if not NS.Public(button) or (button~="LeftButton" and button~="RightButton") then return end
    local foci=NS.Read(GetMouseFoci)
    local scope=mouseScope(foci)
    if not scope then return end
    local snapshot=snapshotFields(scope.row,foci)
    local fields={}
    for _,key in ipairs(mouseSnapshotFields) do fields[key]=snapshot[key] end
    local binding=button=="LeftButton" and "BUTTON1" or "BUTTON2"
    fields.button,fields.down,fields.up=button,event=="GLOBAL_MOUSE_DOWN",event=="GLOBAL_MOUSE_UP"
    fields.phase=fields.down and "down" or "up"
    fields.mouseBindingKey=binding
    fields.mouseBindingActive=read(GetBindingAction,binding,true)
    fields.mouseBindingBase=read(GetBindingAction,binding,false)
    fields.mouseScope,fields.mouseScopeMethod,fields.mouseScopeReason=scope.kind,scope.method,scope.reason
    fields.mouseScopeFrame=read(member(scope.frame,"GetName"),scope.frame)
    if type(foci)=="table" then
        for i,focus in ipairs(foci) do
            if i>4 then break end
            fields["mouseFocus"..i]=not NS.Public(focus) and "[restricted]"
                or read(member(focus,"GetName"),focus)
        end
    end
    if scope.kind=="marker_menu" then
        local unit=NS.Read(member(scope.frame,"GetAttribute"),scope.frame,"unit")
        fields.menuUnit=safe(unit)
        fields.menuExpectedGUID=read(member(scope.frame,"GetAttribute"),scope.frame,"source-guid")
        fields.menuLiveGUID=read(UnitGUID,unit)
    end
    fields.observationOnly=true
    D.Record(event,fields)
end

function D.Snapshot(kind,extra)
    if not D.Enabled() then return false end
    return pcall(function()
        local fields=snapshotFields()
        for key,value in pairs(fieldsCopy(extra)) do fields[key]=value end
        D.Record(kind or "SNAPSHOT",fields)
    end)
end

local function poll()
    local fields=fieldsCopy(snapshotFields())
    local cast=NS.NearbyCast
    local activeHover=NS.HoveredTile~=nil or NS.HoveredEnemyTarget~=nil or cast and cast.row~=nil
        or NS.Number(fields.bridgeCount) and fields.bridgeCount>0 or fields.combatPrepared==true
        or NS.Number(fields.combatPreparedCount) and fields.combatPreparedCount>0
    local keys={}
    for key in pairs(fields) do
        -- Idle focus noise must not fill the history. The real value remains
        -- in recorded snapshots, and active hover/bridge focus still matters.
        if key~="mouseFoci" or activeHover then keys[#keys+1]=key end
    end
    table.sort(keys)
    local parts={}
    for _,key in ipairs(keys) do
        local value=fields[key]
        if key=="nativeMouseover" and type(value)=="table" then
            local detailParts={}
            for _,name in ipairs(nativeMouseoverFields) do
                detailParts[#detailParts+1]=name.."="..tostring(value[name])
            end
            value=table.concat(detailParts,",")
        end
        parts[#parts+1]=key.."="..tostring(value)
    end
    local state=table.concat(parts,";")
    if state~=lastState then lastState=state;D.Record("STATE",fields) end
end

function D.Stop(reason)
    if not D.Enabled() then return end
    pcall(finishWindows,"stopped")
    D.LayoutSnapshot("stop")
    D.Snapshot("STOP",{reason=reason or "user",maxSeconds=D.MAX_SECONDS,activeSeconds=db.activeSeconds})
    db.enabled=false
end

function D.Start()
    if not db then D.Initialize() end
    if D.Enabled() then pcall(finishWindows,"stopped") end
    db.session=db.session+1
    db.enabled=true
    db.activeSeconds=0
    tick,lastState,layoutTick,layoutStates=0,nil,0,{}
    D.Snapshot("START",{version=NS.VERSION,maxSeconds=D.MAX_SECONDS,maxEvents=D.MAX_EVENTS,
        note="SUCCEEDED is a cast event, not proof of damage or exact recipient"})
end

local function onEvent(_,event,a,b,c,d)
    if not D.Enabled() then return end
    if event=="GLOBAL_MOUSE_DOWN" or event=="GLOBAL_MOUSE_UP" then observeGlobalMouse(event,a)
    elseif event:match("^UNIT_SPELLCAST_") then
        if not NS.Public(a) or a~="player" then return end
        if event=="UNIT_SPELLCAST_SENT" then
            D.Snapshot(event,{caster=a,sentTarget=b,castGUID=c,spellID=d})
            observeCastEvent(event,d)
        else D.Snapshot(event,{caster=a,castGUID=b,spellID=c});observeCastEvent(event,c) end
    elseif event=="UI_ERROR_MESSAGE" then
        D.Snapshot(event,{errorID=a,errorText=b})
        observeUIError()
    elseif event=="PLAYER_LOGOUT" then
        pcall(finishWindows,"stopped")
        D.LayoutSnapshot("logout")
        D.Snapshot(event,{note="SavedVariables flush requested by client"})
    elseif event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
        if not NS.Public(a) or a~="MyForeverTargets" then return end
        D.Snapshot(event,{addon=a,action=b})
    else D.Snapshot(event) end
end

function D.Initialize()
    if db then return end
    local old=MyForeverTargetsLogDB
    if type(old)~="table" or old.schema~=1 then old={} end
    db={schema=1,enabled=old.enabled==true,events={},
        sequence=NS.Number(old.sequence) and math.max(0,math.floor(old.sequence)) or 0,
        session=NS.Number(old.session) and math.max(0,math.floor(old.session)) or 0,
        dropped=NS.Number(old.dropped) and math.max(0,math.floor(old.dropped)) or 0,
        activeSeconds=NS.Number(old.activeSeconds) and math.max(0,old.activeSeconds) or 0}
    if type(old.events)=="table" then
        for i=math.max(1,#old.events-D.MAX_EVENTS+1),#old.events do
            local record=old.events[i]
            if type(record)=="table" then
                db.events[#db.events+1]={sequence=safe(record.sequence),session=safe(record.session),
                    time=safe(record.time),serverTime=safe(record.serverTime),
                    kind=safe(record.kind),fields=fieldsCopy(record.fields)}
            end
        end
    end
    MyForeverTargetsLogDB=db
    frame=CreateFrame("Frame")
    D.frame=frame
    for _,event in ipairs({"UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_FAILED_QUIET","UNIT_SPELLCAST_INTERRUPTED",
        "UI_ERROR_MESSAGE","PLAYER_TARGET_CHANGED","PLAYER_FOCUS_CHANGED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
        "PLAYER_LOGOUT","ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN","RAID_TARGET_UPDATE",
        "GLOBAL_MOUSE_DOWN","GLOBAL_MOUSE_UP"}) do
        local ok=pcall(frame.RegisterEvent,frame,event)
        if not ok then D.Record("UNSUPPORTED_EVENT",{event=event}) end
    end
    frame:SetScript("OnEvent",function(...) pcall(onEvent,...) end)
    frame:SetScript("OnUpdate",function(_,delta)
        if not D.Enabled() or not NS.Number(delta) or delta<0 then return end
        pcall(updateCastWindows,delta)
        db.activeSeconds=db.activeSeconds+delta
        if db.activeSeconds>=D.MAX_SECONDS then
            D.Stop(string.format("%g-hour-limit",D.MAX_SECONDS/3600))
            NS.Print("诊断日志已到"..string.format("%g",D.MAX_SECONDS/3600).."小时，自动停止；测试结束后 /reload 保存。")
            return
        end
        tick=tick+delta
        layoutTick=layoutTick+delta
        if layoutTick>=1 then layoutTick=0;D.LayoutSnapshot("poll") end
        if tick>=.25 then tick=0;pcall(poll) end
    end)
    if D.Enabled() then D.Snapshot("RESUME",{version=NS.VERSION}) end
end

function D.Command(argument)
    local command,note=NS.Text(argument):match("^%s*(%S*)%s*(.-)%s*$")
    command=command:lower()
    if command=="start" then
        D.Start()
        local action=NS.LegacyNameBridge and "脱战悬停方块并按原来的普通技能键" or
            NS.NativeMacroOnly and "悬停方块并按你原来的宏按键" or "照常悬停并按技能键"
        NS.Print("诊断日志已开启（最多"..tostring(D.MAX_EVENTS).."条、"..string.format("%g",D.MAX_SECONDS/3600).."小时）；"..action.."。测完 /mytargets log stop，再 /reload 保存。")
    elseif command=="stop" then
        D.Stop("user")
        NS.Print("诊断日志已停止；请 /reload 将本次记录保存到本地。")
    elseif command=="mark" then
        D.Snapshot("USER_MARK",{note=note})
        NS.Print(D.Enabled() and "已记录测试步骤。" or "日志未开启，先 /mytargets log start。")
    elseif command=="status" or command=="" then
        NS.Print("诊断日志："..(D.Enabled() and "记录中" or "已停止").."，"..
            tostring(db and #db.events or 0).."/"..tostring(D.MAX_EVENTS).."条，上限"..string.format("%g",D.MAX_SECONDS/3600).."小时；/mytargets log start 或 stop；测完 /reload 保存。")
    else NS.Print("日志命令：/mytargets log start / stop / status / mark 步骤说明。") end
end
