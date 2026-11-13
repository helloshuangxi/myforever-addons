local _, ns = ...

-- Observe native minimap tooltips after moving the widget beneath the existing
-- pointer. This module never moves the pointer/player or supplies a bearing.
local scan = {}
ns.GatherCursorScan = scan
local active, recovery, driver, stand, label
local resources, nextScan, worldPaused, coverage = {}, 0, false, nil
local TTL, DEADLINE, RETRY, INTERVAL = 8, 8, 0.5, 3
local abs, min, max = math.abs, math.min, math.max
local cleanup, cleaning, lastFailure
local iconHooked, iconReady, iconAttempted, iconBaseline, iconWrite, iconOwner, iconCapture
local questLease, questWrite, questHooked, tooltipMethodHooked, tooltipShowHooked, recentTooltip
local QUEST_POIS = 65536

local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function plain(v, kind) return public(v) and type(v) == kind end
local function number(v) return plain(v, "number") and v == v and abs(v) < math.huge end
local function call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
end
local function need(v, why) if not v then lastFailure = why or "preflight"; error(lastFailure, 0) end return v end
local function clock() local n = call(GetTime); return number(n) and n or nil end
local function same(a, b) return number(a) and number(b) and abs(a - b) <= 0.000001 * max(1, abs(a), abs(b)) end
local function status(state, reason)
    ns.gatherCursorState = state
    if reason then ns.gatherCursorLastReason = reason end
end

-- The only persisted mutation is this exact tracking preference. The rest is
-- runtime frame state, which the native UI rebuilds on reload.
local function pendingQuest()
    local r = plain(ns.db, "table") and ns.db.gatherCursorQuestRestore
    if plain(r, "table") and number(r.filterID) and r.filterID == QUEST_POIS
        and plain(r.before, "boolean") and r.before and plain(r.applied, "boolean") and not r.applied then return r end
end
local function tracking()
    local api = C_Minimap
    if not api or type(api.GetNumTrackingTypes) ~= "function" or type(api.GetTrackingFilter) ~= "function"
        or type(api.GetTrackingInfo) ~= "function" or type(api.SetTracking) ~= "function" then return end
    local count = call(api.GetNumTrackingTypes)
    if not number(count) or count < 1 or count > 128 or count % 1 ~= 0 then return end
    local out, fingerprint = {}, {}
    for i = 1, count do
        local filter, info = call(api.GetTrackingFilter, i), call(api.GetTrackingInfo, i)
        if not public(filter) or (filter ~= nil and not plain(filter, "table"))
            or not plain(info, "table") or not plain(info.active, "boolean") then return end
        if filter and (not public(filter.filterID) or not public(filter.spellID)) then return end
        if not public(info.spellID) then return end
        local id, spell = filter and filter.filterID, info.spellID or (filter and filter.spellID)
        if id ~= nil and not number(id) then return end
        if spell ~= nil and not number(spell) then return end
        if id == QUEST_POIS then
            if out.index then return end
            out.index, out.active = i, info.active
        else
            local key
            if id ~= nil or spell ~= nil then key = tostring(id or "-") .. ":" .. tostring(spell or "-")
            elseif plain(info.name, "string") and #info.name <= 256 then key = "name:" .. info.name
            else return end
            fingerprint[#fingerprint + 1] = key .. "=" .. tostring(info.active)
        end
    end
    if not out.index then return end
    table.sort(fingerprint)
    out.fingerprint = table.concat(fingerprint, "\n")
    return out
end

local function prepareTracking()
    if questHooked then return end
    need(C_Minimap and type(C_Minimap.SetTracking) == "function" and type(hooksecurefunc) == "function", "quest-api")
    hooksecurefunc(C_Minimap, "SetTracking", function(index, value)
        if questWrite and not questWrite.seen and number(index) and index == questWrite.index
            and plain(value, "boolean") and value == questWrite.value then
            questWrite.seen = true
            return
        end
        local current = tracking()
        if questLease and current and current.active == questLease.target
            and current.fingerprint == questLease.fingerprint then
            -- Blizzard's tracking menu mirrors every current value through
            -- SetTracking on MINIMAP_UPDATE_TRACKING. A readable, unchanged
            -- complete state is not an external change, even on a second call.
            -- The API cannot distinguish other callers' identical intentions.
            return
        end
        if questWrite then questWrite.invalid = true end
        questLease = nil
        local filter = number(index) and call(C_Minimap.GetTrackingFilter, index)
        if plain(filter, "table") and number(filter.filterID) and filter.filterID == QUEST_POIS then
            -- A changed external Quest choice takes ownership. Do not later
            -- undo that choice while restoring our temporary scan settings.
            if plain(ns.db, "table") then ns.db.gatherCursorQuestRestore = nil end
        end
        if not cleaning and (active or recovery) then scan.Reset("external-tracking") end
    end)
    questHooked = true
end

function scan.IsOwnTrackingUpdate()
    local now = clock()
    if not questLease or not now or now < questLease.at or now - questLease.at > 1 then return false end
    local current = tracking()
    return current ~= nil and current.fingerprint == questLease.fingerprint
        and current.active == questLease.target
end

local function writeQuest(current, value)
    local now = clock()
    if not now then return false end
    -- Install before SetTracking: both this frame and the HUD can receive a
    -- synchronous event, then an asynchronous echo after cleanup has finished.
    questLease = {at = now, before = true, applied = false, target = value, fingerprint = current.fingerprint}
    local previous = questWrite
    local transaction = {index = current.index, value = value}
    questWrite = transaction
    pcall(C_Minimap.SetTracking, current.index, value)
    questWrite = previous
    local after = tracking()
    return not transaction.invalid and after ~= nil and after.active == value
end
local function restoreQuest()
    if not pendingQuest() then return true end
    if not questHooked then
        local ok = pcall(prepareTracking)
        if not ok then return false end
    end
    local current = tracking()
    if not current then return false end
    if current.active then ns.db.gatherCursorQuestRestore = nil; return true end
    local combat = call(InCombatLockdown)
    if not plain(combat, "boolean") or combat then return false end
    local now = clock()
    if questLease and questLease.target == true and now and now - questLease.at < RETRY then return false end
    if writeQuest(current, true) then ns.db.gatherCursorQuestRestore = nil; return true end
    return false
end
local function hideQuest()
    need(plain(ns.db, "table") and not pendingQuest(), "quest-recovery")
    local current = need(tracking(), "quest-tracking")
    prepareTracking()
    if not current.active then return end
    ns.db.gatherCursorQuestRestore = {filterID = QUEST_POIS, before = true, applied = false}
    need(writeQuest(current, false), "quest-hide")
end

local function iconSet(s, value)
    local transaction = {expected = value, seen = false}
    iconWrite = transaction
    local ok = pcall(s.map.SetIconScale, s.map, value)
    iconWrite = nil
    return ok and transaction.seen and not transaction.invalid
end
local function prepareIcons(m)
    if not iconHooked then
        need(type(hooksecurefunc) == "function" and type(m.SetIconScale) == "function", "icon-api")
        hooksecurefunc(m, "SetIconScale", function(_, value)
            if iconWrite and not iconWrite.seen and same(value, iconWrite.expected) then iconWrite.seen = true; return end
            if iconWrite then iconWrite.invalid = true end
            iconBaseline = number(value) and value > 0 and value or nil
            if iconCapture then
                iconCapture.count = iconCapture.count + 1
                iconCapture.value = iconBaseline
                return
            end
            iconReady = iconAttempted and iconBaseline ~= nil
            if iconOwner then
                iconOwner.iconOwned = false
                iconOwner = nil
                if not cleaning then cleanup("external-icon") end
            end
        end)
        iconHooked = true
    end
    if iconReady then return end
    need(not iconAttempted, "icon-baseline")
    local cluster = MinimapCluster
    local setting = Enum and Enum.EditModeMinimapSetting and Enum.EditModeMinimapSetting.IconScale
    local initialized = cluster and call(cluster.IsInitialized, cluster)
    local hasSetting = cluster and number(setting) and call(cluster.HasSetting, cluster, setting)
    need(cluster and number(setting) and setting == 3 and type(cluster.UpdateSystemSettingIconScale) == "function"
        and plain(initialized, "boolean") and initialized and plain(hasSetting, "boolean") and hasSetting, "icon-config")
    local percent = call(cluster.GetSettingValue, cluster, setting)
    need(number(percent) and percent >= 50 and percent <= 200, "icon-config")
    need(cluster.MinimapContainer and cluster.MinimapContainer.Minimap == m, "icon-instance")
    -- This deliberately reapplies the user's native layout configuration once.
    -- It establishes a new observed baseline; it does not read the old native value.
    iconAttempted, iconCapture = true, {count = 0}
    local ok = pcall(cluster.UpdateSystemSettingIconScale, cluster)
    local captured = iconCapture
    iconCapture = nil
    need(ok and captured.count == 1 and same(captured.value, percent / 100), "icon-baseline")
    iconBaseline, iconReady = captured.value, true
end

local function tooltipSession()
    if active then return active end
    local now = clock()
    if recentTooltip and now and now <= recentTooltip.untilTime then return recentTooltip.session end
end
local function mapTooltip(tip, s)
    local owner = call(tip.GetOwner, tip)
    for _ = 1, 8 do
        if not public(owner) or not owner then return false end
        if owner == s.map or s.frames[owner] or owner == s.coords then return true end
        owner = call(owner.GetParent, owner)
    end
    return false
end
local function prepareTooltip()
    local tip = GameTooltip
    need(tip and type(tip.Hide) == "function" and type(tip.GetOwner) == "function"
        and type(tip.HookScript) == "function" and type(tip.SetMinimapMouseover) == "function", "tooltip-api")
    if not tooltipMethodHooked then
        hooksecurefunc(tip, "SetMinimapMouseover", function(t)
            if tooltipSession() then call(t.Hide, t) end
        end)
        tooltipMethodHooked = true
    end
    if not tooltipShowHooked then
        tip:HookScript("OnShow", function(t)
            local s = tooltipSession()
            if s and mapTooltip(t, s) then call(t.Hide, t) end
        end)
        tooltipShowHooked = true
    end
end

function scan.IsSupported()
    local m = Minimap
    if not public(m) or not m or not UIParent or type(ns.GatherResource) ~= "function"
        or type(CreateFrame) ~= "function" or type(GetTime) ~= "function"
        or type(GetCursorPosition) ~= "function" or type(GetMouseFoci) ~= "function"
        or type(IsMouseButtonDown) ~= "function" or type(InCombatLockdown) ~= "function" or type(hooksecurefunc) ~= "function"
        or type(UnitIsDeadOrGhost) ~= "function" or not C_Timer or type(C_Timer.After) ~= "function"
        or not C_TooltipInfo or type(C_TooltipInfo.GetMinimapMouseover) ~= "function" then return false end
    for _, key in ipairs({ "GetNumPoints", "GetPoint", "AdjustPointsOffset", "GetLeft", "GetBottom",
        "GetWidth", "GetHeight", "GetEffectiveScale", "GetZoom", "GetAlpha", "SetAlpha",
        "IsProtected", "IsVisible", "GetChildren", "IsMouseClickEnabled", "SetMouseClickEnabled",
        "IsMouseWheelEnabled", "EnableMouseWheel", "SetIconScale", "GetParent" }) do
        if type(m[key]) ~= "function" then return false end
    end
    return true
end

local function prune(now)
    for name, r in pairs(resources) do
        if not now or now < r.seenAt or now - r.seenAt > TTL then resources[name] = nil end
    end
end
local function snapshot(now)
    prune(now)
    local out = {}
    for _, r in pairs(resources) do out[#out + 1] = {name = r.name, kind = r.kind, seenAt = r.seenAt} end
    table.sort(out, function(a, b) return a.name < b.name end)
    ns.gatherCursorCount = #out
    return out
end

local function anchors(m)
    local count = m:GetNumPoints()
    need(number(count) and count >= 1 and count <= 16 and count % 1 == 0, "anchors")
    local out = {}
    for i = 1, count do
        local a = {m:GetPoint(i)}
        need(plain(a[1], "string") and public(a[2]) and plain(a[3], "string")
            and number(a[4]) and number(a[5]), "anchors")
        out[i] = a
    end
    return out
end
local function owns(s, ox, oy)
    local current = anchors(s.map)
    if #current ~= #s.anchors then return false end
    for i, a in ipairs(current) do
        local b = s.anchors[i]
        if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3]
            or abs(a[4] - b[4] - ox) > .01 or abs(a[5] - b[5] - oy) > .01 then return false end
    end
    return true
end

local function safeInput(s)
    if worldPaused or ns.gatherSoundWorldPaused then return false, "world" end
    for _, fn in ipairs({InCombatLockdown, UnitIsDeadOrGhost}) do
        local value = call(fn, "player")
        if not plain(value, "boolean") or value then return false, "player-state" end
    end
    if type(UnitAffectingCombat) == "function" then
        local value = call(UnitAffectingCombat, "player")
        if not plain(value, "boolean") or value then return false, "combat" end
    end
    for _, button in ipairs({"LeftButton", "RightButton", "MiddleButton", "Button4", "Button5"}) do
        local down = call(IsMouseButtonDown, button)
        if not plain(down, "boolean") or down then return false, "mouse-button" end
    end
    if type(IsMouselooking) == "function" then
        local value = call(IsMouselooking)
        if not plain(value, "boolean") or value then return false, "mouselook" end
    end
    local m = s and s.map or Minimap
    local visible, protected = call(m.IsVisible, m), call(m.IsProtected, m)
    if not plain(visible, "boolean") or not visible or not plain(protected, "boolean") or protected then return false, "map-state" end
    local foci = call(GetMouseFoci)
    if not plain(foci, "table") or not public(foci[1]) then return false, "focus" end
    local f = foci[1]
    if f ~= nil and f ~= WorldFrame and f ~= m and not (s and s.frames[f]) then return false, "window" end
    return true
end

local function restore(s)
    local good = true
    local function attempt(fn) local ok, done = pcall(fn); if not ok or not done then good = false end end
    if s.moved then attempt(function()
        if owns(s, 0, 0) then s.moved = false; return true end
        local ox, oy = s.ox, s.oy
        if not owns(s, ox, oy) then
            if not s.pending or not owns(s, s.pending.x, s.pending.y) then return false end
            ox, oy = s.pending.x, s.pending.y
        end
        -- Inverse adjustment preserves all anchor identities. Verify even if a
        -- native hook throws after applying the change; retain the baseline on failure.
        pcall(s.map.AdjustPointsOffset, s.map, -ox, -oy)
        if not owns(s, 0, 0) then return false end
        s.moved, s.pending, s.ox, s.oy = false, nil, 0, 0
        return true
    end) end
    if s.iconOwned then attempt(function()
        local ok = iconSet(s, s.iconBefore)
        if not s.iconOwned then return true end -- an external setter owns the current value
        if not ok then return false end
        s.iconOwned = false
        if iconOwner == s then iconOwner = nil end
        return true
    end) end
    for _, item in ipairs(s.changes) do
        if item.changed then attempt(function()
            local value = item.get(item.frame)
            if not public(value) then return false end
            if value == item.before then item.changed = false; return true end
            if value ~= item.applied then
                if item.preserveExternal then item.changed = false; return true end
                return false
            end
            pcall(item.set, item.frame, item.before)
            value = item.get(item.frame)
            if public(value) and value == item.before then item.changed = false; return true end
            return false
        end) end
    end
    return good
end

cleanup = function(reason, completed)
    if cleaning then return end
    cleaning = true
    local s = active or recovery
    active = nil
    local now = clock()
    if s then
        recentTooltip = {session = s, untilTime = (now or 0) + .1}
        if GameTooltip and mapTooltip(GameTooltip, s) then call(GameTooltip.Hide, GameTooltip) end
    end
    nextScan = (now or 0) + (completed and INTERVAL or RETRY)
    if s then
        if not completed and coverage then coverage.partial = true end
        if restore(s) then
            recovery = nil
            if stand then stand:Hide() end
        else
            recovery = s
            if label then label:SetText("恢复小地图…") end
        end
    end
    local questRestored = restoreQuest()
    if completed and s and coverage then
        -- Across pauses/movement there was no single complete view of the map.
        -- Keep existing evidence only to its original TTL in that case.
        if not coverage.partial then resources = coverage.found end
        ns.gatherCursorPasses = (ns.gatherCursorPasses or 0) + 1
        coverage.visited, coverage.count, coverage.found, coverage.next, coverage.partial = {}, 0, {}, 1, false
    end
    snapshot(now)
    status((recovery or not questRestored) and "restore-failed" or completed and "ready" or "paused", reason)
    cleaning = false
end

function scan.Reset(reason)
    cleanup(reason or "reset", false)
    resources = {}
    ns.gatherCursorCount = 0
    coverage = nil
    nextScan = clock() or 0
    if not recovery and not pendingQuest() then status(reason == "disabled" and "disabled" or "idle", reason or "reset") end
end
function scan.IsActive() return active ~= nil or recovery ~= nil or pendingQuest() ~= nil end

local function grid(width, height, shape)
        -- Density is independent of frame rate. Slow clients continue the same
        -- coverage in later slices; they must not skip small native blips.
        local spacing = 20
        local out = {{width / 2, height / 2}}
        local rows = max(1, math.ceil(height / (spacing * .8660254)))
        local cols = max(1, math.ceil(width / spacing))
        for row = 0, rows do
            local y = height * row / rows
            for col = 0, cols do
                local x = width * (col + (row % 2) * .5) / cols
                local dx, dy = (x - width / 2) / (width / 2), (y - height / 2) / (height / 2)
                if x <= width and (shape ~= "ROUND" or dx * dx + dy * dy <= 1)
                    and (abs(dx) > .001 or abs(dy) > .001) then out[#out + 1] = {x, y} end
            end
        end
        if shape == "ROUND" then
            -- Clipping a triangular lattice removes its outside neighbours.
            -- Sample the perimeter too, so edge blips retain a nearby sample.
            local count = math.ceil(math.pi * max(width, height) / 18)
            for i = 1, count do
                local angle = i * 2 * math.pi / count
                out[#out + 1] = {width / 2 * (1 + math.cos(angle)), height / 2 * (1 + math.sin(angle))}
            end
        end
        table.sort(out, function(a, b)
                local ar = (a[1] - width / 2)^2 + (a[2] - height / 2)^2
                local br = (b[1] - width / 2)^2 + (b[2] - height / 2)^2
                if ar ~= br then return ar < br end
                if a[2] ~= b[2] then return a[2] < b[2] end
                return a[1] < b[1]
        end)
        return out
end

local function collect(s, now)
    local d = C_TooltipInfo.GetMinimapMouseover()
    need(active == s, "cancelled")
    local matched = {}
    for _, known in pairs(coverage.known) do
        if known.index == s.pointIndex then known.checkedAt = now end
    end
    local valid = public(d) and (d == nil or (plain(d, "table") and (plain(d.lines, "nil") or plain(d.lines, "table"))))
    local lines = plain(d, "table") and plain(d.lines, "table") and d.lines or {}
    for i, line in ipairs(lines) do
        if i > 128 then break end
        if plain(line, "table") and plain(line.leftText, "string") and #line.leftText <= 8192 then
            for text in line.leftText:gmatch("[^\r\n]+") do
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local kind = ns.GatherResource(text)
                if kind == "mining" or kind == "herbalism" then
                    local r = {name = text, kind = kind, seenAt = now}
                    coverage.found[text], resources[text] = r, r
                    coverage.known[text] = {index = s.pointIndex, seenAt = now, checkedAt = now}
                    matched[text] = true
                end
            end
        end
    end
    if valid then
        for name, known in pairs(coverage.known) do
            if known.index == s.pointIndex and not matched[name] then coverage.known[name] = nil end
        end
    end
end

local function duePoint(now)
    local selected, oldest
    for _, known in pairs(coverage.known) do
        local checkedAt = known.checkedAt or known.seenAt
        if now - checkedAt >= 3 and (not oldest or checkedAt < oldest) then
            selected, oldest = known.index, checkedAt
        end
    end
    return selected
end

local function geometrySame(s)
    for _, item in ipairs({{"GetWidth", s.width}, {"GetHeight", s.height}, {"GetEffectiveScale", s.scale}, {"GetZoom", s.zoom}}) do
        local n = call(s.map[item[1]], s.map)
        if not number(n) or abs(n - item[2]) > .001 then return false end
    end
    return true
end
local function place(s, cx, cy)
    local q = s.points[s.pointIndex]
    local x, y = cx / s.scale - q[1] - s.left, cy / s.scale - q[2] - s.bottom
    s.moved, s.pending = true, {x = x, y = y}
    s.map:AdjustPointsOffset(x - s.ox, y - s.oy)
    need(active == s, "cancelled")
    s.ox, s.oy, s.cx, s.cy, s.reads = x, y, cx, cy, 0
    s.pending = nil
    need(owns(s, x, y), "anchor-changed")
end
local function step(s)
    if active ~= s then return end
    local now = need(clock(), "clock")
    if now - s.started >= DEADLINE then return cleanup("timeout") end
    local safe, reason = safeInput(s)
    if not safe then return cleanup(reason) end
    if not owns(s, s.ox, s.oy) then return cleanup("anchor-changed") end
    if not geometrySame(s) then return scan.Reset("geometry") end
    local speed = call(GetUnitSpeed, "player")
    if not number(speed) or speed ~= 0 then coverage.partial = true end
    local cx, cy = call(GetCursorPosition)
    need(number(cx) and number(cy), "cursor")
    if s.placed then
        if abs(cx - s.cx) > 2 or abs(cy - s.cy) > 2 then
            s.drift = s.drift + 1
            if s.drift >= 3 then
                if not s.recheck then coverage.next = s.pointIndex % #s.points + 1 end
                return cleanup("cursor-moving")
            end
            return place(s, cx, cy)
        end
        s.reads = s.reads + 1
        if s.reads == 1 then C_TooltipInfo.GetMinimapMouseover(); return end
        collect(s, now)
        s.done = s.done + 1
        if not s.recheck and not coverage.visited[s.pointIndex] then
            coverage.visited[s.pointIndex], coverage.count = true, coverage.count + 1
        end
        if not s.recheck then coverage.next = s.pointIndex % #s.points + 1 end
        local due = duePoint(now)
        if coverage.count == #s.points and not due then return cleanup("complete", true) end
        if s.done >= 256 then return cleanup("slice") end
        if due then
            s.pointIndex, s.recheck = due, true
        else
            while coverage.visited[coverage.next] do coverage.next = coverage.next % #s.points + 1 end
            s.pointIndex, s.recheck = coverage.next, false
        end
        s.drift = 0
    end
    s.placed = true
    place(s, cx, cy)
end

local function showStand(s)
    if not stand then
        stand = CreateFrame("Frame", nil, UIParent)
        stand:EnableMouse(false)
        stand:EnableMouseWheel(false)
        stand:SetFrameStrata("MEDIUM")
        local bg = stand:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(stand)
        bg:SetColorTexture(.055, .065, .075, .94)
        label = stand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("CENTER", stand, "CENTER")
    end
    local scale = call(UIParent.GetEffectiveScale, UIParent)
    need(number(scale) and scale > 0, "ui-scale")
    stand:ClearAllPoints()
    stand:SetSize(s.width * s.scale / scale, s.height * s.scale / scale)
    stand:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", s.left * s.scale / scale, s.bottom * s.scale / scale)
    label:SetText("扫描矿草…")
    stand:Show()
end

local function createDriver()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
            worldPaused = true; scan.Reset("world")
        elseif event == "PLAYER_ENTERING_WORLD" then worldPaused = false; scan.Reset("world")
        elseif event == "MINIMAP_UPDATE_TRACKING" then
            if not scan.IsOwnTrackingUpdate() then scan.Reset("map-change") end
        elseif event == "MINIMAP_UPDATE_ZOOM" or event == "ZONE_CHANGED_NEW_AREA" then scan.Reset("map-change")
        elseif event == "GLOBAL_MOUSE_DOWN" then cleanup("mouse-button")
        elseif event == "PLAYER_REGEN_DISABLED" then cleanup("combat")
        elseif event == "PLAYER_DEAD" then cleanup("dead") end
    end)
    for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA",
        "MINIMAP_UPDATE_ZOOM", "MINIMAP_UPDATE_TRACKING", "GLOBAL_MOUSE_DOWN", "PLAYER_REGEN_DISABLED", "PLAYER_DEAD"}) do
        need(pcall(driver.RegisterEvent, driver, event), "events")
    end
    driver:SetScript("OnUpdate", function()
        if active then
            lastFailure = nil
            local ok = pcall(step, active)
            if not ok then cleanup(lastFailure or "error") end
        end
    end)
end

local function start(now)
    local m = Minimap
    local s = {map = m, anchors = anchors(m), left = m:GetLeft(), bottom = m:GetBottom(), width = m:GetWidth(),
        height = m:GetHeight(), scale = m:GetEffectiveScale(), zoom = m:GetZoom(), started = now,
        changes = {}, frames = {}, ox = 0, oy = 0, done = 0, drift = 0}
    for _, key in ipairs({"left", "bottom", "width", "height", "scale", "zoom"}) do need(number(s[key]), "geometry") end
    need(s.width > 0 and s.height > 0 and s.width <= 2048 and s.height <= 2048 and s.scale > 0, "geometry")
    local shape = call(GetMinimapShape)
    shape = plain(shape, "string") and shape or "ROUND"
    local key = table.concat({s.width, s.height, s.scale, s.zoom, shape}, ":")
    if not coverage or coverage.key ~= key then
        coverage = {key = key, points = grid(s.width, s.height, shape), visited = {}, count = 0, found = {}, known = {}, next = 1}
    end
    s.points = coverage.points
    local due = duePoint(now)
    if due then s.pointIndex, s.recheck = due, true
    elseif coverage.count == #s.points then
        -- A final refresh can be interrupted after coverage finished. Preserve
        -- that pass; do not search forever for an unvisited point.
        active = s; cleanup("complete", true); return
    else
        while coverage.visited[coverage.next] do coverage.next = coverage.next % #s.points + 1 end
        s.pointIndex = coverage.next
    end
    local function change(f, get, set, applied, kind, preserveExternal)
        need(type(get) == "function" and type(set) == "function", "methods")
        local before = get(f)
        need(kind == "number" and number(before) or kind == "boolean" and plain(before, "boolean"), "state")
        if before ~= applied then s.changes[#s.changes + 1] = {frame = f, get = get, set = set, before = before, applied = applied, preserveExternal = preserveExternal} end
    end
    local n = 0
    local function children(f, depth)
        need(public(f) and f and depth <= 8 and not s.frames[f], "children")
        n = n + 1; need(n <= 128, "children")
        s.frames[f] = true
        local clicks = f:IsMouseClickEnabled()
        need(plain(clicks, "boolean"), "click-state")
        if clicks then
            need(call(f.IsProtected, f) == false, "protected-child")
            change(f, f.IsMouseClickEnabled, f.SetMouseClickEnabled, false, "boolean")
        end
        for _, child in ipairs({f:GetChildren()}) do children(child, depth + 1) end
    end
    children(m, 0)
    change(m, m.IsMouseWheelEnabled, m.EnableMouseWheel, false, "boolean")
    change(m, m.GetAlpha, m.SetAlpha, 0, "number")
    local parent = call(m.GetParent, m)
    local coords = public(parent) and parent and parent.PlayerCoords
    if public(coords) and coords then
        s.coords = coords
        change(coords, coords.GetAlpha, coords.SetAlpha, 0, "number", true)
    end
    prepareTooltip()
    prepareIcons(m)
    createDriver()
    active = s -- all subsequent mutations have an owned restoration record
    C_Timer.After(DEADLINE, function() if active == s then cleanup("timeout") end end)
    hideQuest()
    need(active == s, "cancelled")
    s.iconBefore, s.iconOwned, iconOwner = iconBaseline, true, s
    need(iconSet(s, .05), "icon-hide")
    need(active == s and s.iconOwned, "cancelled")
    showStand(s)
    if mapTooltip(GameTooltip, s) then call(GameTooltip.Hide, GameTooltip) end
    for _, item in ipairs(s.changes) do
        need(active == s, "cancelled")
        item.changed = true
        item.set(item.frame, item.applied)
        need(active == s, "cancelled")
        local value = item.get(item.frame)
        need(public(value) and value == item.applied, "write")
    end
    status("scanning", "started")
end

function scan.Poll(enabled)
    local now = clock()
    if not plain(enabled, "boolean") or not enabled or not now then scan.Reset(now and "disabled" or "clock"); return {} end
    -- A reload may leave the native preference disabled while our feature is
    -- now off or its APIs are not yet ready. Never make that the new baseline.
    if not active and not restoreQuest() then status("restore-failed", "quest-recovery"); return snapshot(now) end
    if recovery then
        if now >= nextScan then
            if restore(recovery) then recovery = nil; if stand then stand:Hide() end; status("paused", "restored") end
            nextScan = now + RETRY
        end
        return snapshot(now)
    end
    if not scan.IsSupported() then scan.Reset("unsupported"); status("unsupported"); return {} end
    if active or now < nextScan then return snapshot(now) end
    local safe, reason = safeInput()
    if not safe then nextScan = now + RETRY; status("paused", reason); return snapshot(now) end
    lastFailure = nil
    local ok = pcall(start, now)
    if not ok then cleanup(lastFailure or "preflight-or-error") end
    return snapshot(now)
end

ns.gatherCursorCount, ns.gatherCursorPasses = 0, 0
status("idle")
