local _, ns = ...

-- Local experimental name source. Only the native widget is moved; the real
-- pointer, tracking choices, zoom and key bindings are never changed. Every
-- published name has survived an outside-map control and a fresh recheck.
local scan = {}
ns.GatherCursorScan = scan
local abs, max = math.abs, math.max
local EMPTY_MASK = "Interface\\AddOns\\MyForeverProfessions\\Textures\\EmptyMask"
local SLICE, DEADLINE, GAP, RECHECK, RECEIPT_TTL, HEARTBEAT = .24, .55, .12, 1.2, .6, .6
local active, recovery, retained, lastPoll, driver, pending, coverage, probe, probePrepared
local nextScan, frames, worldPaused, cleaning, mutating, batching = 0, 0, false, false, false, false
local anchorWrite, restoringSession
local lastReason, lastState, passes, reads, publications = "init", "idle", 0, 0, 0
local rawNames, acceptedNames, rejectedNames = {}, {}, {}
local maskHooked, maskObserved, maskWrite, maskOwner
local iconHooked, iconObserved, iconWrite, iconOwner, iconCapture
local properties, anchorHooked = {}, false
local finish
local tooltipCategories={"Nil","Empty","Nonempty","Unknown","Known","Invalid"}
local function newTooltipCounts()
    local out={}
    for _,key in ipairs(tooltipCategories) do out[key]=0 end
    return out
end
local tooltipTotals,lastTooltipCounts=newTooltipCounts(),newTooltipCounts()

local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function plain(v, t) return public(v) and type(v) == t end
local function boolean(v, expected) return plain(v,"boolean") and v==expected end
local function number(v) return plain(v, "number") and v == v and abs(v) < math.huge end
local function same(a, b) return number(a) and number(b) and abs(a-b) <= .001 end
local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
local function need(v, why) if not v then error(why, 0) end return v end
local function clock() local n = call(GetTime); return number(n) and n or nil end
local function status(state, reason)
    lastState, lastReason = state, reason or lastReason
    ns.gatherCursorState, ns.gatherCursorLastReason = state, lastReason
end
local function renderer() return ns.GatherStandIn end
local function standShown()
    local r = renderer()
    return r and call(r.IsShown) == true
end

local function anchors(m)
    local n = m:GetNumPoints()
    need(number(n) and n >= 1 and n <= 16 and n % 1 == 0, "anchors")
    local out = {}
    for i = 1, n do
        local p = {m:GetPoint(i)}
        need(plain(p[1], "string") and public(p[2]) and plain(p[3], "string")
            and number(p[4]) and number(p[5]), "anchors")
        out[i] = p
    end
    return out
end
local function owns(s, ox, oy)
    local now = anchors(s.map)
    if #now ~= #s.anchors then return false end
    for i, p in ipairs(now) do
        local q = s.anchors[i]
        if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3]
            or not same(p[4], q[4]+ox) or not same(p[5], q[5]+oy) then return false end
    end
    return true
end

local function external(reason)
    local s = active or recovery or restoringSession
    if s then s.invalid = reason end
    if s and not cleaning and not mutating and not batching then finish(reason) end
end

local function prepareHooks(m)
    if not maskHooked then
        hooksecurefunc(m, "SetMaskTexture", function(_, value)
            if maskWrite and not maskWrite.seen and public(value) and value == maskWrite.value then maskWrite.seen = true; return end
            if maskWrite then maskWrite.invalid = true end
            maskObserved = (plain(value, "string") and #value > 0 and #value <= 1024) and value
                or (number(value) and value > 0 and value) or false
            if maskOwner then maskOwner.maskOwned = false; maskOwner = nil end
            external("external-mask")
        end)
        maskHooked = true
    end
    if not iconHooked then
        hooksecurefunc(m, "SetIconScale", function(_, value)
            if iconWrite and not iconWrite.seen and same(value, iconWrite.value) then iconWrite.seen = true; return end
            if iconWrite then iconWrite.invalid = true end
            iconObserved = number(value) and value > 0 and value <= 10 and value or nil
            if iconCapture then iconCapture.count = iconCapture.count + 1; iconCapture.value = iconObserved; return end
            if iconOwner then iconOwner.iconOwned = false; iconOwner = nil end
            external("external-icon")
        end)
        iconHooked = true
    end
    if not anchorHooked then
        for _, method in ipairs({"SetPoint", "ClearAllPoints", "AdjustPointsOffset"}) do
            if type(m[method]) == "function" then
                local setter=method
                hooksecurefunc(m, setter, function(_,x,y)
                    if anchorWrite and setter=="AdjustPointsOffset" and not anchorWrite.seen
                        and same(x,anchorWrite.x) and same(y,anchorWrite.y) then
                        anchorWrite.seen=true; return
                    end
                    if active or recovery or restoringSession then
                        local s=active or recovery or restoringSession
                        if setter=="AdjustPointsOffset" and number(x) and number(y) then
                            -- A relative external move keeps its own delta; only
                            -- our temporary translation is later subtracted.
                            s.externalDX=(s.externalDX or 0)+x
                            s.externalDY=(s.externalDY or 0)+y
                        else
                            s.anchorExternalFrame=frames
                        end
                        external("external-anchor")
                    end
                end)
            end
        end
        anchorHooked = true
    end
end

local function maskBaseline(shape)
    if maskObserved ~= nil then return maskObserved or nil end
    if shape == "SQUARE" then return "Interface\\BUTTONS\\WHITE8X8" end
    if shape ~= "ROUND" then return nil end
    if C_Texture and call(C_Texture.GetAtlasExists, "ui-hud-minimap-frame-generic-mask") == true then
        return "ui-hud-minimap-frame-generic-mask"
    end
    return "Textures\\MinimapMask"
end
local function iconBaseline(m)
    if iconObserved then return iconObserved end
    -- There is no native icon-scale getter on this client. An authoritative
    -- initialized Blizzard Edit Mode setting may reapply its own unchanged value
    -- once to establish a witnessed baseline. No third-party setting is written.
    local c = MinimapCluster
    local setting = Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.IconScale
    if not c or not number(setting) or setting ~= 3 or call(c.IsInitialized, c) ~= true
        or call(c.HasSetting, c, setting) ~= true or not c.MinimapContainer or c.MinimapContainer.Minimap ~= m
        or type(c.UpdateSystemSettingIconScale) ~= "function" then return nil end
    local value = call(c.GetSettingValue, c, setting)
    if not number(value) or value < 50 or value > 200 then return nil end
    iconCapture = {count = 0}
    local ok = pcall(c.UpdateSystemSettingIconScale, c)
    local capture = iconCapture
    iconCapture = nil
    if ok and capture.count == 1 and same(capture.value, value/100) then return capture.value end
    iconObserved = nil
    return nil
end
local function setMask(s, value)
    local t = {value = value}
    maskWrite = t
    local ok = pcall(s.map.SetMaskTexture, s.map, value)
    maskWrite = nil
    return ok and t.seen and not t.invalid
end
local function setIcon(s, value)
    local t = {value = value}
    iconWrite = t
    local ok = pcall(s.map.SetIconScale, s.map, value)
    iconWrite = nil
    return ok and t.seen and not t.invalid
end

local function property(s, f, getter, setter, applied)
    need(active==s and not s.invalid,"cancelled")
    local before = f[getter](f)
    need(public(before) and type(before) == type(applied), "property-baseline")
    local per = properties[f]
    if not per then per = {}; properties[f] = per end
    local hook = per[setter]
    if not hook then
        hook = {}
        per[setter] = hook
        hooksecurefunc(f, setter, function(_, value)
            local item = hook.owner
            if hook.writing and public(value) and value == hook.writing.value and not hook.writing.seen then
                hook.writing.seen = true; return
            end
            if hook.writing then hook.writing.invalid = true end
            if item then item.owned = false; hook.owner = nil; external("external-appearance") end
        end)
    end
    need(not hook.owner, "property-conflict")
    local item = {frame = f, getter = getter, setter = setter, before = before, applied = applied, owned = true, hook = hook}
    s.changes[#s.changes+1], hook.owner = item, item
    if before == applied then return end
    local t = {value = applied}
    hook.writing = t
    local ok = pcall(f[setter], f, applied)
    hook.writing = nil
    need(ok and t.seen and not t.invalid and public(f[getter](f)) and f[getter](f) == applied, "property-write")
    need(active==s and not s.invalid,"cancelled")
end

local function parts(m)
    local list, seen, children = {}, {}, {}
    local function add(f)
        need(public(f), "restricted-frame")
        if f and f ~= m and not seen[f] then
            need(#list < 256 and type(f.GetAlpha) == "function" and type(f.SetAlpha) == "function", "map-parts")
            seen[f], list[#list+1] = true, f
        end
    end
    local function descend(parent, depth)
        if type(parent.GetChildren) ~= "function" then return end
        local current = {parent:GetChildren()}
        for _, child in ipairs(current) do
            add(child); children[child] = true
            if depth < 5 then descend(child, depth+1) end
        end
        if type(parent.GetRegions) == "function" then
            for _, region in ipairs({parent:GetRegions()}) do add(region) end
        end
    end
    descend(m, 0)
    local parent = call(m.GetParent, m)
    if parent and public(parent) then add(parent.PlayerCoords) end
    -- Native frames sometimes use the map as an anchor without being children.
    for _, name in ipairs({"MinimapBorder", "MinimapBorderTop", "MinimapBackdrop", "MinimapZoomIn", "MinimapZoomOut",
        "MiniMapWorldMapButton", "MiniMapMailFrame", "MiniMapTracking", "QueueStatusButton"}) do
        local f = _G[name]
        if f then
            local anchored = false
            if type(f.GetNumPoints) == "function" and type(f.GetPoint) == "function" then
                local n = f:GetNumPoints()
                need(number(n) and n <= 16 and n >= 0, "map-parts")
                for i = 1, n do
                    local _, relative = f:GetPoint(i)
                    need(public(relative), "restricted-frame")
                    if relative == m or seen[relative] then anchored = true end
                end
            end
            if anchored then add(f) end
        end
    end
    return list, seen, children
end

local function currentMapID()
    local id = C_Minimap and call(C_Minimap.GetUiMapID)
    if not number(id) then id = C_Map and call(C_Map.GetBestMapForUnit, "player") end
    return number(id) and id or nil
end
local function shape()
    if type(GetMinimapShape) ~= "function" then return "ROUND" end
    local v = call(GetMinimapShape)
    return plain(v, "string") and v or nil
end
local function geometrySame(s)
    if Minimap ~= s.map or shape() ~= s.shape or currentMapID() ~= s.mapID then return false end
    for _, p in ipairs({{"GetWidth",s.width},{"GetHeight",s.height},{"GetEffectiveScale",s.scale},{"GetZoom",s.zoom}}) do
        if not same(call(s.map[p[1]], s.map), p[2]) then return false end
    end
    return true
end
local function restoredGeometrySame(s)
    return geometrySame(s) and same(call(s.map.GetLeft,s.map),s.left)
        and same(call(s.map.GetBottom,s.map),s.bottom) and owns(s,0,0)
end
local function inputSafe(s)
    if worldPaused or ns.gatherSoundWorldPaused then return false, "world" end
    local combat, dead = call(InCombatLockdown), call(UnitIsDeadOrGhost, "player")
    if not plain(combat,"boolean") or combat or not plain(dead,"boolean") or dead then return false,"player-state" end
    if type(UnitAffectingCombat) == "function" and not boolean(call(UnitAffectingCombat,"player"),false) then return false,"combat" end
    local any = call(IsMouseButtonDown)
    if not plain(any,"boolean") or any then return false,"mouse-button" end
    for _, button in ipairs({"LeftButton","RightButton","MiddleButton","Button4","Button5"}) do
        if not boolean(call(IsMouseButtonDown,button),false) then return false,"mouse-button" end
    end
    if type(IsMouselooking) ~= "function" or not boolean(call(IsMouselooking),false) then return false,"mouselook" end
    local m = s and s.map or Minimap
    if not boolean(call(m.IsVisible,m),true) or not boolean(call(m.IsProtected,m),false) then return false,"map-state" end
    local cx,cy = call(GetCursorPosition)
    if not number(cx) or not number(cy) then return false,"cursor" end
    if s then
        -- Also protect controls surrounding the original map, not just its circle.
        local pad = 28*s.scale
        if cx >= s.left*s.scale-pad and cx <= (s.left+s.width)*s.scale+pad
            and cy >= s.bottom*s.scale-pad and cy <= (s.bottom+s.height)*s.scale+pad then return false,"map-hover" end
    end
    local foci = call(GetMouseFoci)
    if not plain(foci,"table") then return false,"focus" end
    local f = foci[1]
    if not public(f) then return false,"focus" end
    local mapFocus=s and (f==m or (s.partSet and s.partSet[f]))
    -- GetMouseFoci is refreshed by the native frame loop. A HUD poll directly
    -- after our inverse move can still see that frame's previous map focus.
    -- All input/hover gates above remain strict, and this exception lasts only
    -- the very frame in which every native lease was successfully returned.
    local justRestored=mapFocus and not s.moved and s.restoredFrame==frames
        and call(restoredGeometrySame,s)==true
    if f ~= nil and f ~= WorldFrame and not (mapFocus and (s.moved or justRestored)) then return false,"window" end
    return true
end

local function dropRetained(reason)
    if not retained then return end
    retained=nil
    pending,coverage=nil,nil
    local r=renderer()
    if r and type(r.Hide)=="function" then pcall(r.Hide) end
    status("paused",reason)
end
local function guardRetained(now)
    if not retained then return end
    local ok,safe,reason=pcall(function()
        if not now or not lastPoll or now<lastPoll or now-lastPoll>HEARTBEAT then return false,"poll-heartbeat" end
        if not standShown() then return false,"stand-in-lost" end
        if not restoredGeometrySame(retained) then return false,"geometry" end
        return inputSafe(retained)
    end)
    if not ok or not safe then dropRetained(ok and reason or "retained-check-error") end
end

local function grid(width,height,scale,kind)
    local spacing = 12/scale
    local rows,cols = max(1,math.ceil(height/(spacing*.8660254))),max(1,math.ceil(width/spacing))
    need(rows*cols <= 4096,"map-too-large")
    local points = {{width/2,height/2}}
    for row = 0,rows do
        local y = height*row/rows
        for col = 0,cols do
            local x = width*(col+(row%2)*.5)/cols
            local dx,dy = (x-width/2)/(width/2),(y-height/2)/(height/2)
            if x <= width and (kind ~= "ROUND" or dx*dx+dy*dy <= 1)
                and (abs(dx)>.001 or abs(dy)>.001) then points[#points+1] = {x,y} end
        end
    end
    if kind == "ROUND" then
        local count = math.ceil(math.pi*max(width,height)*scale/10)
        for i = 1,count do
            local angle = i*2*math.pi/count
            points[#points+1] = {width/2*(1+math.cos(angle)),height/2*(1+math.sin(angle))}
        end
    end
    table.sort(points,function(a,b)
        local ar,br = (a[1]-width/2)^2+(a[2]-height/2)^2,(b[1]-width/2)^2+(b[2]-height/2)^2
        if ar ~= br then return ar < br end
        return a[1] == b[1] and a[2] < b[2] or a[1] < b[1]
    end)
    return points
end

local function restore(s)
    local good = true
    local function attempt(fn) local ok,done = pcall(fn); if not ok or not done then good=false end end
    if s.anchorExternalFrame then
        -- A different layout owner supplied new anchors. Allow its grouped
        -- ClearAllPoints/SetPoint calls to finish, then return every other lease
        -- without overwriting that explicit new position. This is distinct from
        -- a failure of our own native inverse move, which must keep retrying.
        if frames<=s.anchorExternalFrame then return false end
        s.moved,s.pendingMove,s.anchorExternalFrame=false,nil,nil
    end
    -- Position is returned before any visible decoration/input is restored.
    if s.moved then attempt(function()
        local ex,ey=s.externalDX or 0,s.externalDY or 0
        if owns(s,ex,ey) then s.moved=false; return true end
        local ox,oy = s.ox,s.oy
        if not owns(s,ox+ex,oy+ey) then
            if not s.pendingMove or not owns(s,s.pendingMove[1]+ex,s.pendingMove[2]+ey) then return false end
            ox,oy=s.pendingMove[1],s.pendingMove[2]
        end
        mutating=true
        anchorWrite={x=-ox,y=-oy}
        pcall(s.map.AdjustPointsOffset,s.map,-ox,-oy)
        anchorWrite=nil
        mutating=false
        if not owns(s,ex,ey) then return false end
        s.moved,s.pendingMove,s.ox,s.oy=false,nil,0,0
        return true
    end) end
    -- A failed/external anchor means visible parts stay hidden and inputs quiet
    -- until the map really returns. Never force another addon's unknown anchors.
    if s.moved then return false end
    if s.iconOwned then attempt(function()
        local ok=setIcon(s,s.iconBefore)
        if not s.iconOwned then return true end
        if not ok then return false end
        s.iconOwned=false; if iconOwner==s then iconOwner=nil end
        return true
    end) end
    if s.maskOwned then attempt(function()
        local ok=setMask(s,s.maskBefore)
        if not s.maskOwned then return true end
        if not ok then return false end
        s.maskOwned=false; if maskOwner==s then maskOwner=nil end
        return true
    end) end
    for i=#s.changes,1,-1 do
        local item=s.changes[i]
        if item.owned then attempt(function()
            local current=item.frame[item.getter](item.frame)
            if not public(current) then return false end
            if current~=item.before and current~=item.applied then
                item.owned=false; item.hook.owner=nil; return true
            end
            if current~=item.before then
                local t={value=item.before}; item.hook.writing=t
                local ok=pcall(item.frame[item.setter],item.frame,item.before)
                item.hook.writing=nil
                if not item.owned then return true end
                if not ok or not t.seen or t.invalid then return false end
                current=item.frame[item.getter](item.frame)
                if not public(current) or current~=item.before then return false end
            end
            item.owned=false; item.hook.owner=nil; return true
        end) end
    end
    return good
end

finish=function(reason,result,normal)
    if cleaning then return end
    cleaning=true
    local s=active or recovery
    if s then lastTooltipCounts=s.tooltipCounts end
    active=nil
    local now=clock() or 0
    pending=nil
    if s then
        restoringSession=s
        local ok,done=pcall(restore,s)
        restoringSession=nil
        mutating=false
        if not ok or not done then
            recovery=s; s.nextRestore=now+.1
            status("restore-failed",reason)
            cleaning=false
            return
        end
        recovery=nil
        s.restoredFrame=frames
        local r=renderer()
        local reusable=normal and (reason=="slice" or reason=="positive" or reason=="complete") and not s.invalid
            and lastPoll and now>=lastPoll and now-lastPoll<=HEARTBEAT and standShown()
        local ok,sameSnapshot=pcall(restoredGeometrySame,s)
        if reusable and ok and sameSnapshot then
            -- The native map is fully restored underneath. The independent
            -- renderer keeps only its own picture alive across the short gap.
            retained=s
        else
            retained=nil
            if r and type(r.Hide)=="function" then pcall(r.Hide) end
        end
        if result and not s.invalid and geometrySame(s) and now>=s.observedAt and now-s.observedAt<=RECEIPT_TTL then
            pending={items=result,at=s.observedAt,session=s}
            publications=publications+1
        end
    elseif retained then
        -- Reset/source changes must also release a picture with no native lease.
        dropRetained(reason)
    end
    nextScan=now+GAP
    if reason~="slice" and reason~="positive" and reason~="complete" then coverage=nil end
    status(result and "ready" or "paused",reason)
    cleaning=false
end

local function observeNames()
    local d=C_TooltipInfo.GetMinimapMouseover()
    need(public(d),"restricted-tooltip")
    if d==nil then return {},"Nil" end -- Public nil is a legitimate no-hit sample.
    need(plain(d,"table") and plain(d.lines,"table"),"malformed-tooltip")
    local count=0
    for k,line in pairs(d.lines) do
        need(number(k) and k%1==0 and k>=1 and k<=128 and plain(line,"table"),"malformed-lines")
        count=count+1
    end
    local found={}
    for i=1,count do
        local line=d.lines[i]
        need(plain(line,"table"),"malformed-lines")
        for _,field in ipairs({"leftText","rightText"}) do
            local text=line[field]
            need(public(text) and (text==nil or (plain(text,"string") and #text<=8192)),"restricted-text")
            if text then
                for part in text:gmatch("[^\r\n]+") do
                    part=part:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
                        :gsub("|T.-|t",""):gsub("|A.-|a","")
                        :gsub("^%s+",""):gsub("%s+$","")
                    local kind=ns.GatherResource(part)
                    if kind=="mining" or kind=="herbalism" then found[part]=kind end
                end
            end
        end
    end
    return found,count==0 and "Empty" or "Nonempty"
end
local function readNames()
    reads=reads+1
    local function bump(key)
        -- Only bounded numeric counters survive; unrelated tooltip text is
        -- neither retained nor exposed by diagnostics.
        if tooltipTotals[key]<2147483647 then tooltipTotals[key]=tooltipTotals[key]+1 end
        local counts=active and active.tooltipCounts
        if counts and counts[key]<2147483647 then counts[key]=counts[key]+1 end
    end
    local ok,found,category=pcall(observeNames)
    if not ok then bump("Invalid"); error(found,0) end
    bump(category)
    if category=="Nonempty" then bump(next(found) and "Known" or "Unknown") end
    return found
end

local function place(s,point,cx,cy)
    local x,y=cx/s.scale-point[1]-s.left,cy/s.scale-point[2]-s.bottom
    s.moved,s.pendingMove=true,{x,y}
    mutating=true
    anchorWrite={x=x-s.ox,y=y-s.oy}
    local ok=pcall(s.map.AdjustPointsOffset,s.map,x-s.ox,y-s.oy)
    anchorWrite=nil
    mutating=false
    need(ok,"move")
    s.ox,s.oy,s.pendingMove,s.cx,s.cy=x,y,nil,cx,cy
    s.placedFrame,s.point=frames,point
    need(owns(s,x,y),"anchor-changed")
end
local function selectPoint(s,now)
    local c=coverage
    local due
    for _,k in pairs(c.known) do
        if now-k.checkedAt>=RECHECK and (not due or k.checkedAt<due.checkedAt) then due=k end
    end
    if due then s.pointIndex,s.rechecking=due.index,true
    else s.pointIndex,s.rechecking=c.next,false end
    s.phase="sample"
    local cx,cy=GetCursorPosition()
    need(number(cx) and number(cy),"cursor")
    place(s,c.points[s.pointIndex],cx,cy)
end
local function recordMiss(s,now)
    local c=coverage
    for name,k in pairs(c.known) do if k.index==s.pointIndex then c.known[name]=nil end end
    if not s.rechecking then c.next=s.pointIndex+1; c.count=c.count+1 end
    if c.next>#c.points then
        passes=passes+1
        s.observedAt=now
        local complete=not c.partial and not c.hadPositive
        coverage=nil
        return finish("complete",complete and {} or nil,true)
    end
    if now-s.started>=SLICE then return finish("slice",nil,true) end
    return selectPoint(s,now)
end

local function hideParts(s)
    s.maskOwned,maskOwner=true,s
    need(setMask(s,EMPTY_MASK),"mask-conflict")
    s.iconOwned,iconOwner=true,s
    need(setIcon(s,.05),"icon-conflict")
    property(s,s.map,"IsMouseClickEnabled","SetMouseClickEnabled",false)
    property(s,s.map,"IsMouseWheelEnabled","EnableMouseWheel",false)
    for _,f in ipairs(s.parts) do
        need(type(f.IsProtected)~="function" or call(f.IsProtected,f)==false,"protected-part")
        property(s,f,"GetAlpha","SetAlpha",0)
        if type(f.IsMouseClickEnabled)=="function" and type(f.SetMouseClickEnabled)=="function" then
            property(s,f,"IsMouseClickEnabled","SetMouseClickEnabled",false)
        end
        if type(f.IsMouseMotionEnabled)=="function" and type(f.SetMouseMotionEnabled)=="function" then
            property(s,f,"IsMouseMotionEnabled","SetMouseMotionEnabled",false)
        end
        if type(f.IsMouseWheelEnabled)=="function" and type(f.EnableMouseWheel)=="function" then
            property(s,f,"IsMouseWheelEnabled","EnableMouseWheel",false)
        end
    end
end

local function step(s)
    if active~=s then return end
    local now=need(clock(),"clock")
    if s.invalid then return finish(s.invalid) end
    if now-s.started>=DEADLINE then return finish("timeout") end
    if not standShown() then return finish("stand-in-lost") end
    local safe,reason=inputSafe(s)
    if not safe then return finish(reason) end
    if not geometrySame(s) then return finish("geometry") end
    need(owns(s,s.ox,s.oy),"anchor-changed")
    local speed=call(GetUnitSpeed,"player")
    if not number(speed) or speed~=0 then coverage.partial=true end
    -- Detect newly created map controls before moving the next sample.
    local _,current=parts(s.map)
    for f in pairs(current) do if not s.partSet[f] then return finish("map-parts-changed") end end
    local cx,cy=GetCursorPosition()
    need(number(cx) and number(cy),"cursor")
    if s.phase=="stand" then
        if frames<=s.shownFrame+1 then return end
        batching=true
        local ok,why=pcall(hideParts,s)
        batching=false
        need(ok,plain(why,"string") and why or "disguise")
        need(not s.invalid,"cancelled")
        return selectPoint(s,now)
    end
    if frames<=s.placedFrame then return end
    if abs(cx-s.cx)>.5 or abs(cy-s.cy)>.5 then
        s.drift=s.drift+1
        if s.drift>=3 then return finish("cursor-moving") end
        return place(s,s.point,cx,cy)
    end
    local found=readNames()
    need(active==s and not s.invalid,"cancelled")
    if s.phase=="sample" then
        if next(found)==nil then return recordMiss(s,now) end
        rawNames={}
        for name in pairs(found) do if #rawNames<24 then rawNames[#rawNames+1]=name end end
        table.sort(rawNames)
        s.candidate,s.candidatePoint=found,s.point
        s.phase="control"
        return place(s,{s.width*3,s.height*3},cx,cy)
    elseif s.phase=="control" then
        if next(found)~=nil then
            rejectedNames={}
            for name in pairs(s.candidate) do if #rejectedNames<24 then rejectedNames[#rejectedNames+1]=name end end
            table.sort(rejectedNames)
            return finish("stale-control")
        end
        s.phase="confirm"
        return place(s,s.candidatePoint,cx,cy)
    elseif s.phase=="confirm" then
        local result={}
        for name,kind in pairs(s.candidate) do
            if found[name]==kind then result[#result+1]={name=name,kind=kind,seenAt=now} end
        end
        if #result==0 then return finish("unconfirmed") end
        table.sort(result,function(a,b) return a.name<b.name end)
        acceptedNames={}
        for i,item in ipairs(result) do if i<=24 then acceptedNames[#acceptedNames+1]=item.name end end
        for _,item in ipairs(result) do coverage.known[item.name]={index=s.pointIndex,checkedAt=now} end
        coverage.hadPositive=true
        if not s.rechecking then coverage.next=s.pointIndex+1; coverage.count=coverage.count+1 end
        if coverage.next>#coverage.points then coverage=nil; passes=passes+1 end
        s.observedAt=now
        return finish("positive",result,true)
    end
end

local function createDriver()
    if driver then return end
    driver=CreateFrame("Frame")
    driver:SetScript("OnUpdate",function()
        frames=frames+1
        if recovery then
            if (clock() or 0)>=(recovery.nextRestore or 0) then finish("restore-retry") end
        elseif active then
            local ok,reason=pcall(step,active)
            if not ok then mutating=false; finish(plain(reason,"string") and reason or "error") end
        elseif retained then
            guardRetained(clock())
        end
    end)
    driver:SetScript("OnEvent",function(_,event)
        if event=="PLAYER_ENTERING_WORLD" then worldPaused=false; scan.Reset("world")
        elseif event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then worldPaused=true; scan.Reset("world")
        else scan.Reset(event=="GLOBAL_MOUSE_DOWN" and "mouse-button" or "map-or-player-change") end
    end)
    for _,event in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_REGEN_DISABLED","PLAYER_DEAD","PLAYER_UNGHOST",
        "PLAYER_LEAVING_WORLD","PLAYER_ENTERING_WORLD","PLAYER_LOGOUT","MINIMAP_UPDATE_ZOOM",
        "ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do driver:RegisterEvent(event) end
end

function scan.IsSupported()
    local m,r=Minimap,renderer()
    if not public(m) or not m or not UIParent or not r or type(r.Show)~="function" or type(r.Hide)~="function"
        or type(r.IsShown)~="function" or type(ns.GatherResource)~="function" or type(CreateFrame)~="function"
        or type(GetTime)~="function" or type(GetCursorPosition)~="function" or type(GetMouseFoci)~="function"
        or type(IsMouseButtonDown)~="function" or type(IsMouselooking)~="function" or type(InCombatLockdown)~="function"
        or type(UnitIsDeadOrGhost)~="function" or type(hooksecurefunc)~="function"
        or not C_Timer or type(C_Timer.After)~="function" or not C_TooltipInfo
        or type(C_TooltipInfo.GetMinimapMouseover)~="function" then return false end
    for _,method in ipairs({"GetNumPoints","GetPoint","AdjustPointsOffset","GetLeft","GetBottom","GetWidth","GetHeight",
        "GetEffectiveScale","GetZoom","GetAlpha","GetChildren","GetRegions","IsProtected","IsVisible","GetParent",
        "SetMaskTexture","SetIconScale","IsMouseClickEnabled","SetMouseClickEnabled","IsMouseWheelEnabled","EnableMouseWheel"}) do
        if type(m[method])~="function" then return false end
    end
    return true
end

local function start(now)
    need(scan.IsSupported(),"unsupported")
    createDriver()
    prepareHooks(Minimap)
    if C_AddOns then
        for _,name in ipairs({"NodeSight","Lueur"}) do
            if boolean(call(C_AddOns.IsAddOnLoaded,name),true) then
                dropRetained("conflict-"..name)
                return status("paused","conflict-"..name)
            end
        end
    end
    local safe,reason=inputSafe()
    if not safe then dropRetained(reason); return status("paused",reason) end
    local m=Minimap
    local s={map=m,left=m:GetLeft(),bottom=m:GetBottom(),width=m:GetWidth(),height=m:GetHeight(),scale=m:GetEffectiveScale(),
        zoom=m:GetZoom(),shape=shape(),mapID=currentMapID(),anchors=anchors(m),ox=0,oy=0,changes={},started=now,drift=0,
        tooltipCounts=newTooltipCounts()}
    need(number(s.left) and number(s.bottom) and number(s.width) and number(s.height) and number(s.scale)
        and number(s.zoom) and s.width>=24 and s.height>=24 and s.scale>0 and s.scale<=8
        and (s.shape=="ROUND" or s.shape=="SQUARE"),"geometry")
    safe,reason=inputSafe(s)
    if not safe then dropRetained(reason); return status("paused",reason) end
    need(same(m:GetAlpha(),1),"native-alpha")
    s.maskBefore=need(maskBaseline(s.shape),"unknown-mask")
    s.iconBefore=need(iconBaseline(m),"unknown-icon-scale")
    s.parts,s.partSet=parts(m)
    if not probe then
        local f=CreateFrame("Frame")
        need(f and type(f.CreateTexture)=="function","texture-probe")
        probe=f:CreateTexture(nil,"BACKGROUND")
    end
    if not probePrepared then
        if probe and type(probe.SetBlockingLoadsRequested)=="function" then
            need(pcall(probe.SetBlockingLoadsRequested,probe,true),"empty-mask-unavailable")
        end
        probePrepared=true
    end
    need(probe and type(probe.SetTexture)=="function" and probe:SetTexture(EMPTY_MASK)==true,"empty-mask-unavailable")
    local texture=call(probe.GetTexture,probe)
    -- This client assigns negative local file IDs to loaded loose addon art.
    -- Missing files still return nil, despite SetTexture itself returning true.
    need((plain(texture,"string") and #texture>0)
        or (number(texture) and texture~=0 and texture%1==0),"empty-mask-unavailable")
    local key=table.concat({s.width,s.height,s.scale,s.zoom,s.shape,s.mapID or "-"},":")
    if not coverage or coverage.key~=key or coverage.next>#coverage.points then
        coverage={key=key,points=grid(s.width,s.height,s.scale,s.shape),next=1,count=0,known={},partial=false,hadPositive=false}
    end
    local reuse=retained and standShown() and restoredGeometrySame(retained)
        and same(retained.left,s.left) and same(retained.bottom,s.bottom)
    retained=nil
    active=s
    s.phase,s.shownFrame="stand",frames
    if not reuse then
        local shown,why=renderer().Show(s)
        need(shown==true and standShown(),plain(why,"string") and why or "stand-in-unavailable")
    end
    status("scanning","stand-in-ready")
    C_Timer.After(DEADLINE+.05,function()
        if active==s then finish("timeout") elseif recovery==s then finish("restore-retry") end
    end)
end

function scan.ScanNames()
    local now=clock()
    if not now then return nil end
    guardRetained(now)
    lastPoll=now -- Only source polling renews the retained-picture heartbeat.
    if recovery then return nil end
    if pending then
        local receipt=pending
        pending=nil
        if not active and geometrySame(receipt.session) and inputSafe(receipt.session)
            and now>=receipt.at and now-receipt.at<=RECEIPT_TTL then
            ns.gatherCursorCount=#receipt.items
            return receipt.items
        end
    end
    if active or now<nextScan then return nil end
    nextScan=now+GAP
    local ok,reason=pcall(start,now)
    if not ok then mutating=false; finish(plain(reason,"string") and reason or "error") end
    return nil
end
function scan.Reset(reason)
    pending=nil
    coverage=nil
    finish(reason or "reset")
    ns.gatherCursorCount=0
    if not recovery then status(reason=="disabled" and "disabled" or "idle",reason or "reset") end
end
function scan.IsActive() return active~=nil or recovery~=nil end
function scan.ScanDiagnostics()
    local function copy(t) local out={}; for i,v in ipairs(t) do out[i]=v end; return out end
    local result={method="cursor",state=lastState,reason=lastReason,active=active~=nil,recovering=recovery~=nil,
        reads=reads,passes=passes,publications=publications,coverage=coverage and coverage.count or 0,
        total=coverage and #coverage.points or 0,standIn=standShown(),freshOnly=true,navigation=false,
        sampleCount=reads,rawKnownNames=copy(rawNames),acceptedNames=copy(acceptedNames),rejectedKnownNames=copy(rejectedNames),
        standInRetained=retained~=nil}
    local session=active or recovery
    local round=session and session.tooltipCounts or lastTooltipCounts
    for _,key in ipairs(tooltipCategories) do
        result["tooltip"..key.."Count"]=tooltipTotals[key]
        -- A round is one native-map lease (slice), not an entire grid pass.
        result["roundTooltip"..key.."Count"]=round[key]
    end
    return result
end

-- Install getter-less property witnesses early, before normal login layout work.
if scan.IsSupported() then pcall(prepareHooks,Minimap); pcall(createDriver) end
