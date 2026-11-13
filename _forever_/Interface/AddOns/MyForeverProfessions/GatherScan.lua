local _, ns = ...

-- Native minimap hit testing, not an object database. Coordinates are approximate
-- display offsets: x right / y up, with +/-1 at the corresponding minimap edge.
-- Call Scan regularly (about every 0.05 seconds); only a finished pass returns a
-- table plus a separate list of unlocated tooltip hints. Hints are not proof
-- of a nearby resource and must never supply a bearing or a discovery sound.
-- No tracking mode, visible tooltip, or player movement is changed here.
-- ScanNames uses the same footprint validation but returns only unique known
-- resource names. It neither calculates a resource centroid nor reads heading.
local scan = {}
ns.GatherScan = scan
local pass, grid, gridKey, nextBatch, suspendedUntil, pendingRestore
local PASS_SECONDS, MAX_BATCH, MIN_INTERVAL, MAX_PASS_SECONDS = 1.5, 96, 0.04, 10
local abs, min, max = math.abs, math.min, math.max
-- Passive, session-only diagnostics: retain the last completed names pass,
-- while state/reason describe the most recent scanner action.
local diagnostics = {state="idle",reason="not-started",sampleCount=0,
    rawKnownNames={},acceptedNames={},rejectedKnownNames={}}
local function restricted() return ns.gatherMinimapAccessRestricted==true end
local function markRestricted(reason)
    if not restricted() then ns.gatherMinimapRestrictionReason=reason end
    ns.gatherMinimapAccessRestricted=true
    pass,nextBatch=nil,nil
    diagnostics.sampleCount,diagnostics.completedAt=0,nil
    diagnostics.rawKnownNames,diagnostics.acceptedNames,diagnostics.rejectedKnownNames={},{},{}
end
local function secret(value,reason)
    if issecretvalue and issecretvalue(value) then markRestricted(reason);return true end
    return false
end

local function status(state, reason)
    if restricted() then state,reason="restricted",ns.gatherMinimapRestrictionReason or "minimap-restricted" end
    diagnostics.state, diagnostics.reason = state, reason
end

function scan.ScanDiagnostics()
    local blocked=restricted()
    local copy = {state=blocked and "restricted" or diagnostics.state,
        reason=blocked and (ns.gatherMinimapRestrictionReason or "minimap-restricted") or diagnostics.reason,
        minimapRestricted=blocked,restrictionReason=blocked and ns.gatherMinimapRestrictionReason or nil,
        recovering=pendingRestore~=nil,sampleCount=blocked and 0 or diagnostics.sampleCount,
        completedAt=not blocked and diagnostics.completedAt or nil}
    for _, key in ipairs({"rawKnownNames","acceptedNames","rejectedKnownNames"}) do
        copy[key] = {}
        if not blocked then for i, name in ipairs(diagnostics[key]) do copy[key][i] = name end end
    end
    return copy
end

local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end

local function legacySupported()
    return not restricted() and Minimap ~= nil and type(Minimap.SetUsingSoftCursor) == "function"
        and type(Minimap.UpdateMouseoverAtPoint) == "function"
        and C_TooltipInfo ~= nil and type(C_TooltipInfo.GetMinimapMouseover) == "function"
        and type(GetCursorPosition) == "function" and type(GetTime) == "function"
end
scan.IsSupported = legacySupported

local function restoreNative(g)
    local x, y = g.cursorX, g.cursorY
    local ok, currentX, currentY = pcall(GetCursorPosition)
    if ok and number(currentX) and number(currentY) then x, y = currentX, currentY end
    local restored = pcall(g.map.UpdateMouseoverAtPoint, g.map, x, y)
    local released = pcall(g.map.SetUsingSoftCursor, g.map, false)
    pendingRestore = not (restored and released) and g or nil
    return restored and released
end

function scan.Reset()
    pass, nextBatch = nil, nil
    if pendingRestore then restoreNative(pendingRestore) end
    status(pendingRestore and "native-error" or "idle", pendingRestore and "restore-failed" or "reset")
end

local function inputIdle()
    local function clear(fn, ...)
        local ok, value = pcall(fn, ...)
        if not ok then return false,"input-api-error" end
        if (issecretvalue and issecretvalue(value)) or type(value) ~= "boolean" then return false,"input-state-unavailable" end
        return not value
    end
    if type(IsMouseButtonDown) == "function" then
        for _, button in ipairs({"LeftButton", "RightButton", "MiddleButton", "Button4", "Button5"}) do
            local idle, reason = clear(IsMouseButtonDown, button)
            if not idle then return false,reason or "mouse-button" end
        end
    end
    if type(IsMouselooking) == "function" then
        local idle, reason = clear(IsMouselooking)
        if not idle then return false,reason or "mouselook" end
    end
    return true
end

-- A minimap addon's button may extend outside the map's rectangle. Inspect
-- real focus ancestry without changing that button's input or appearance.
local function focusAwayFromMap(map)
    if type(GetMouseFoci) ~= "function" then return true end
    local ok, foci = pcall(GetMouseFoci)
    if not ok then return false,"focus-api-error" end
    if (issecretvalue and issecretvalue(foci)) or type(foci) ~= "table" then
        return false,"focus-unavailable"
    end
    local function inspect()
        for i = 1, 33 do
            local frame, seen = foci[i], {}
            if issecretvalue and issecretvalue(frame) then return false,"focus-unavailable" end
            if frame == nil then return true end
            if i > 32 then return false,"focus-list-limit" end
            for depth = 1, 21 do
                if issecretvalue and issecretvalue(frame) then return false,"focus-unavailable" end
                if frame == nil then break end
                if type(frame) ~= "table" and type(frame) ~= "userdata" then return false,"focus-unavailable" end
                if frame == map then return false,"cursor-over-map-child" end
                if seen[frame] then return false,"focus-cycle" end
                if depth > 20 then return false,"focus-chain-limit" end
                seen[frame] = true
                local getParent = frame.GetParent
                if (issecretvalue and issecretvalue(getParent)) or type(getParent) ~= "function" then
                    return false,"focus-unavailable"
                end
                frame = getParent(frame)
            end
        end
    end
    local inspected, idle, reason = pcall(inspect)
    if not inspected then return false,"focus-api-error" end
    return idle, reason
end

local function geometry(namesOnly)
    local map = Minimap
    local idle, reason = inputIdle()
    if not idle then return nil,"paused-input",reason end
    if not map:IsVisible() then return nil,"paused-map","hidden" end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return nil,"paused-player","combat"
    end
    local cursorX, cursorY = GetCursorPosition()
    local cx, cy = map:GetCenter()
    local width, height, scale = map:GetWidth(), map:GetHeight(), map:GetEffectiveScale()
    if not (number(cursorX) and number(cursorY) and number(cx) and number(cy)
        and number(width) and number(height) and number(scale))
        or width <= 0 or height <= 0 or scale <= 0 then return nil,"paused-geometry","invalid-geometry" end
    cx, cy, width, height = cx * scale, cy * scale, width * scale, height * scale
    -- A rectangle is deliberately conservative: do not steal the real mouse
    -- from corner buttons even when the minimap mask itself is round.
    if abs(cursorX - cx) <= width / 2 and abs(cursorY - cy) <= height / 2 then return nil,"paused-input","cursor-over-map" end
    if MouseIsOver and MouseIsOver(map) then return nil,"paused-input","cursor-over-map" end
    local away, focusReason = focusAwayFromMap(map)
    if not away then return nil,"paused-input",focusReason end
    local rotate
    if C_CVar and type(C_CVar.GetCVarBool) == "function" then
        rotate = C_CVar.GetCVarBool("rotateMinimap") == true
    else
        local setting = GetCVar and GetCVar("rotateMinimap")
        rotate = setting == "1" or setting == 1 or setting == true
    end
    if rotate and C_Minimap and type(C_Minimap.IsRotateMinimapIgnored) == "function"
        and C_Minimap.IsRotateMinimapIgnored() then rotate = false end
    local facing
    if not namesOnly then
        facing = rotate and GetPlayerFacing and GetPlayerFacing() or nil
        if rotate and not number(facing) then return nil,"paused-geometry","heading-unavailable" end
    end
    local zoom = map:GetZoom()
    if not number(zoom) then return nil,"paused-geometry","zoom-unavailable" end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local mapID = C_Minimap and C_Minimap.GetUiMapID and C_Minimap.GetUiMapID() or nil
    return {map=map,cx=cx,cy=cy,width=width,height=height,scale=scale,zoom=zoom,
        shape=shape,mapID=mapID,rotate=rotate,facing=facing,cursorX=cursorX,cursorY=cursorY,namesOnly=namesOnly}
end

local function sameGeometry(a, b)
    return a.map == b.map and a.cx == b.cx and a.cy == b.cy and a.width == b.width
        and a.height == b.height and a.scale == b.scale and a.zoom == b.zoom
        and a.shape == b.shape and a.mapID == b.mapID and a.rotate == b.rotate and a.namesOnly == b.namesOnly
        -- Turning a rotating minimap changes all hit locations. A tiny tolerance
        -- avoids discarding a pass for floating point jitter while stationary.
        and (a.namesOnly or not a.rotate or abs(math.atan2(math.sin(a.facing-b.facing),
            math.cos(a.facing-b.facing))) < 0.02)
end

local function makeGrid(g)
    local spacing = max(3, 5 * g.scale)
    local nx = min(40, max(2, math.ceil(g.width / (2 * spacing))))
    local ny = min(40, max(2, math.ceil(g.height / (2 * spacing))))
    local key = nx .. ":" .. ny .. ":" .. tostring(g.shape)
    if gridKey == key then return grid end
    local points = {}
    for y = -ny, ny do
        for x = -nx, nx do
            local dx, dy = x / nx, y / ny
            local radius = dx * dx + dy * dy
            if g.shape ~= "ROUND" or radius <= 1 then
                points[#points+1] = {x=x,y=y,dx=dx,dy=dy,radius=radius}
            end
        end
    end
    table.sort(points, function(a,b)
        if a.radius ~= b.radius then return a.radius < b.radius end
        if a.y ~= b.y then return a.y < b.y end
        return a.x < b.x
    end)
    grid, gridKey = points, key
    return points
end

local function collect(data, point)
    if secret(data,"restricted-tooltip") then return false,"restricted-tooltip" end
    -- A public nil is the native no-tooltip result; a malformed or restricted
    -- container is not evidence of an empty map and invalidates this pass.
    if data == nil then return true end
    if type(data) ~= "table" then return false,"tooltip-data-unavailable" end
    local lines = data.lines
    if secret(lines,"restricted-lines") then return false,"restricted-lines" end
    if type(lines) ~= "table" then
        return false,"tooltip-lines-unavailable"
    end
    local count=0
    for key,line in pairs(lines) do
        if secret(key,"restricted-line-key") then return false,"restricted-line-key" end
        if not number(key) or key%1~=0 or key<1 or key>128 then return false,"tooltip-lines-unavailable" end
        if secret(line,"restricted-line") then return false,"restricted-line" end
        count=count+1
    end
    local seen = {}
    for i=1,count do
        local line=lines[i]
        if secret(line,"restricted-line") then return false,"restricted-line" end
        if type(line) ~= "table" then
            return false,"tooltip-line-unavailable"
        end
        local text = line.leftText
        if secret(text,"restricted-text") then return false,"restricted-text" end
        local right=line.rightText
        if secret(right,"restricted-text") then return false,"restricted-text" end
        if (text ~= nil and type(text) ~= "string") or (right~=nil and type(right)~="string") then
            return false,"tooltip-text-unavailable"
        end
        if type(text) == "string" then
            -- Several coincident blips can share one tooltip text field.
            for name in text:gmatch("[^\r\n]+") do
                name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    :gsub("|T.-|t", ""):gsub("|A.-|a", "")
                    :gsub("^%s+", ""):gsub("%s+$", "")
                if name ~= "" and not seen[name] and (not pass.namesOnly or ns.GatherResource(name)) then
                    seen[name] = true
                    local cells = pass.hits[name]
                    if not cells then cells = {}; pass.hits[name] = cells end
                    cells[point.x .. ":" .. point.y] = point
                end
            end
        end
    end
    return true
end

local function completed(namesOnly)
    local result, rejectedNames, unique, acceptedRaw = {}, {}, {}, {}
    local g = pass.geometry
    -- A native blip has a local hit footprint. Some client builds instead
    -- repeat stale tooltip text across the map; its average is near (0, 0),
    -- which would fabricate a nearby deposit. Keep these bounds generous for
    -- enlarged icons and overlapping blips, but do not locate a broad region
    -- by its centroid. This guards invalid data; it does not repair the API.
    local maxWidth, maxHeight = max(32 * g.scale, g.width / 4), max(32 * g.scale, g.height / 4)
    -- Connected hit cells describe one native dot's footprint. Keeping spatial
    -- components separate permits several nearby deposits with the same name.
    for name, cells in pairs(pass.hits) do
        local visited = {}
        for key, point in pairs(cells) do
            if not visited[key] then
                local queue, head, sx, sy = {point}, 1
                if not namesOnly then sx, sy = 0, 0 end
                local minX, maxX, minY, maxY = point.dx, point.dx, point.dy, point.dy
                visited[key] = true
                while head <= #queue do
                    local p = queue[head]
                    head = head + 1
                    if not namesOnly then sx, sy = sx + p.dx, sy + p.dy end
                    minX, maxX = min(minX, p.dx), max(maxX, p.dx)
                    minY, maxY = min(minY, p.dy), max(maxY, p.dy)
                    for y = -1, 1 do
                        for x = -1, 1 do
                            local neighbor = (p.x+x) .. ":" .. (p.y+y)
                            if cells[neighbor] and not visited[neighbor] then
                                visited[neighbor] = true
                                queue[#queue+1] = cells[neighbor]
                            end
                        end
                    end
                end
                if #queue <= #pass.points / 2 and (maxX-minX)*g.width/2 <= maxWidth
                    and (maxY-minY)*g.height/2 <= maxHeight then
                    if namesOnly then
                        acceptedRaw[name] = true
                        local key = ns.GatherResourceKey and ns.GatherResourceKey(name) or name
                        -- Keep a spelling actually observed in this pass, while
                        -- merging only explicitly catalogued aliases.
                        if not unique[key] or name < unique[key] then unique[key] = name end
                    else
                        result[#result+1] = {name=name,dx=sx/#queue,dy=sy/#queue,facing=g.facing}
                    end
                elseif not namesOnly then
                    rejectedNames[name] = true
                end
            end
        end
    end
    if namesOnly then
        for _, name in pairs(unique) do result[#result+1] = {name=name} end
        table.sort(result, function(a,b) return a.name < b.name end)
        local evidence = {sampleCount=#pass.points,rawKnownNames={},acceptedNames={},rejectedKnownNames={}}
        local function isGatheringName(name)
            local kind = ns.GatherResource(name)
            return kind == "mining" or kind == "herbalism"
        end
        for name in pairs(pass.hits) do
            if isGatheringName(name) then
                evidence.rawKnownNames[#evidence.rawKnownNames+1] = name
                -- A name with any valid component is not wholly rejected.
                if not acceptedRaw[name] then evidence.rejectedKnownNames[#evidence.rejectedKnownNames+1] = name end
            end
        end
        for _, item in ipairs(result) do
            if isGatheringName(item.name) then evidence.acceptedNames[#evidence.acceptedNames+1] = item.name end
        end
        table.sort(evidence.rawKnownNames)
        table.sort(evidence.rejectedKnownNames)
        return result,evidence
    end
    table.sort(result, function(a,b)
        local ar, br = a.dx*a.dx+a.dy*a.dy, b.dx*b.dx+b.dy*b.dy
        if ar ~= br then return ar < br end
        if a.name ~= b.name then return a.name < b.name end
        if a.dx ~= b.dx then return a.dx < b.dx end
        return a.dy < b.dy
    end)
    -- Retain only the text as an explicitly unconfirmed clue. Never average
    -- rejected geometry into a pretend position. A located dot of the same
    -- name is more useful than its ambiguous duplicate.
    for _, dot in ipairs(result) do rejectedNames[dot.name] = nil end
    local hints = {}
    for name in pairs(rejectedNames) do hints[#hints+1] = {name=name} end
    table.sort(hints, function(a,b) return a.name < b.name end)
    return result, hints
end

local function scanPass(namesOnly)
    -- A failed release is retried before either interface can start sampling.
    -- Reset also retries it when the HUD is disabled. Never publish that pass.
    if pendingRestore and not restoreNative(pendingRestore) then status("native-error","restore-failed");return end
    if restricted() then scan.Reset();status("restricted",ns.gatherMinimapRestrictionReason);return end
    if not legacySupported() then scan.Reset();status("unsupported","native-api");return end
    if namesOnly and type(ns.GatherResource) ~= "function" then scan.Reset();status("unsupported","resource-catalog");return end
    if pass and pass.namesOnly ~= namesOnly then scan.Reset() end
    local now = GetTime()
    if suspendedUntil and now < suspendedUntil then status("cooldown","previous-native-error");return end
    local ok, g, state, reason = pcall(geometry, namesOnly)
    if not ok or not g then
        scan.Reset()
        status(ok and state or "native-error", ok and reason or "geometry-call-failed")
        return
    end
    -- Large custom minimaps need more batches at a 0.1-second caller cadence;
    -- allow those to finish while still dropping genuinely stale observations.
    if pass and (not sameGeometry(pass.geometry, g) or now - pass.started > MAX_PASS_SECONDS) then scan.Reset() end
    if nextBatch and now < nextBatch then status("scanning","batch-wait");return end
    if not pass then
        pass = {geometry=g,points=makeGrid(g),index=1,hits={},started=now,lastBatch=now-0.05,namesOnly=namesOnly}
    end
    status("scanning","sampling")
    local elapsed = min(0.25, max(MIN_INTERVAL, now-pass.lastBatch))
    local budget = min(MAX_BATCH, max(1, math.ceil(#pass.points * elapsed / PASS_SECONDS)))
    local profiler = type(debugprofilestop) == "function" and debugprofilestop or nil
    local begin = profiler and profiler()
    pass.lastBatch, nextBatch = now, now + MIN_INTERVAL
    -- The native widget accepts physical screen pixels, just like
    -- GetCursorPosition. Always restore the real pointer, including on failure.
    local unavailable
    local batchOK = pcall(function()
        g.map:SetUsingSoftCursor(true)
        for _ = 1, budget do
            local point = pass.points[pass.index]
            if not point then break end
            g.map:UpdateMouseoverAtPoint(g.cx + point.dx*g.width/2, g.cy + point.dy*g.height/2)
            local data = C_TooltipInfo.GetMinimapMouseover()
            local readOK, readable, reason = pcall(collect, data, point)
            if not readOK or not readable then
                unavailable = readOK and reason or "tooltip-read-error"
                break
            end
            pass.index = pass.index + 1
            if profiler and profiler() - begin >= 2 then break end
        end
    end)
    local restored = restoreNative(g)
    if not batchOK or not restored then
        pass, nextBatch = nil, nil
        suspendedUntil = now + 10
        status("native-error",not restored and "restore-failed" or "sampling-failed")
        return
    end
    if unavailable then
        pass, nextBatch = nil, nil
        status("unavailable",unavailable)
        return
    end
    if pass.index > #pass.points then
        local resultOK, result, hints = pcall(completed, namesOnly)
        scan.Reset()
        if resultOK then
            status("ready",namesOnly and "completed" or "legacy-completed")
            if namesOnly then
                diagnostics.sampleCount = hints.sampleCount
                diagnostics.rawKnownNames, diagnostics.acceptedNames, diagnostics.rejectedKnownNames = hints.rawKnownNames,hints.acceptedNames,hints.rejectedKnownNames
                diagnostics.completedAt = number(now) and now or nil
                return result
            end
            return result, hints
        end
        suspendedUntil = now + 10
        status("error","classification-failed")
    end
end

function scan.Scan() return scanPass(false) end
function scan.ScanNames() return scanPass(true) end

-- Keep the original object: GatherAlerts captures it while its file loads.
-- The local experiment can therefore switch sources without replacing a live
-- reference or promoting old observations to a fresh discovery.
local legacyReset, legacyNames, legacyScan, legacyDiagnostics = scan.Reset, scan.ScanNames, scan.Scan, scan.ScanDiagnostics
local routedSource
local function cursorSelected() return ns.db and ns.db.gatherMethod == "cursor" end
local function route()
    local source = cursorSelected() and ns.GatherCursorScan or nil
    local key = cursorSelected() and "cursor" or "original"
    if key ~= routedSource then
        legacyReset()
        if ns.GatherCursorScan then ns.GatherCursorScan.Reset("source-change") end
        routedSource = key
    end
    return source
end
function scan.GetMethod() return cursorSelected() and "cursor" or "original" end
function scan.IsSupported()
    if restricted() then return false end
    if cursorSelected() then return ns.GatherCursorScan ~= nil and ns.GatherCursorScan.IsSupported() end
    return legacySupported()
end
function scan.Reset(reason)
    legacyReset()
    if ns.GatherCursorScan then ns.GatherCursorScan.Reset(reason or "reset") end
end
function scan.ScanNames()
    if restricted() then scan.Reset("minimap-restricted");return end
    local source = route()
    if cursorSelected() then
        if not source then return end
        -- A failed release of the old soft cursor cannot overlap a new source.
        if pendingRestore then legacyReset(); if pendingRestore then return end end
        return source.ScanNames()
    end
    if ns.GatherCursorScan and ns.GatherCursorScan.IsActive() then
        ns.GatherCursorScan.Reset("original-source")
        if ns.GatherCursorScan.IsActive() then return end
    end
    return legacyNames()
end
function scan.Scan()
    if restricted() then scan.Reset("minimap-restricted");return end
    if cursorSelected() then return scan.ScanNames() end
    route()
    if ns.GatherCursorScan and ns.GatherCursorScan.IsActive() then
        ns.GatherCursorScan.Reset("original-source")
        if ns.GatherCursorScan.IsActive() then return end
    end
    return legacyScan()
end
function scan.ScanDiagnostics()
    local selected = cursorSelected()
    local source = selected and ns.GatherCursorScan or nil
    local result
    if selected then
        result = source and source.ScanDiagnostics() or {state="unsupported",reason="cursor-module-unavailable"}
    else result = legacyDiagnostics() end
    if type(result) == "table" then
        result.method = selected and "cursor" or "original"
        if restricted() then
            result.state,result.reason="restricted",ns.gatherMinimapRestrictionReason or "minimap-restricted"
            result.minimapRestricted,result.restrictionReason=true,ns.gatherMinimapRestrictionReason
            result.rawKnownNames,result.acceptedNames,result.rejectedKnownNames={},{},{}
        end
    end
    return result
end
