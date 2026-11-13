local _, ns = ...
local call = ns.SafeCall
local scanner = ns.GatherScan
local cursorScanner = ns.GatherCursorScan

local skills = { mining = 186, herbalism = 182, fishing = 356 }
local trackingSpells = { [2580] = "mining", [2383] = "herbalism", [43308] = "fishing" }
local trackingNames = {
    ["寻找矿物"] = "mining", ["寻找草药"] = "herbalism", ["寻找鱼群"] = "fishing",
    ["Find Minerals"] = "mining", ["Find Herbs"] = "herbalism", ["Find Fish"] = "fishing",
}
local directions = { "前方", "右前方", "右侧", "右后方", "后方", "左后方", "左侧", "左前方" }
local colors = { mining = {1, 0.76, 0.36}, herbalism = {0.56, 0.9, 0.54}, fishing = {0.5, 0.82, 1} }
local pollInterval, targetLifetime, quietTime = 0.10, 3.5, 10
local HUD_WIDTH, HUD_HEIGHT = 244, 58
local hud, arrow, title, detail, doneButton
local target, targetUntil, previewUntil
local hintTarget, hintUntil
local adjusting, moving, resize
local activeTracking
local announcements, nextSound = {}, 0
local heardResources = {}

local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

local function readTracking()
    local minimap = C_Minimap
    local count = call(minimap and minimap.GetNumTrackingTypes)
    if not number(count) or type(minimap.GetTrackingInfo) ~= "function" then return nil end
    local active = {}
    for index = 1, count do
        local info = call(minimap.GetTrackingInfo, index)
        if type(info) == "table" and info.active == true then
            local filter = not info.spellID and call(minimap.GetTrackingFilter, index)
            local spellID = info.spellID or (filter and filter.spellID)
            local kind = trackingSpells[spellID] or trackingNames[info.name]
            if kind then active[kind] = true end
        end
    end
    return active
end

local function learnedGathering()
    local ranks = {}
    if ns.detectReady then
        for _, profession in ipairs(ns.professions) do
            if number(profession.rank) and profession.rank > 0 then
                ranks[profession.id] = profession.rank + (profession.modifier or 0)
            end
        end
    end
    return ranks
end

local function canScan(ranks)
    for kind, id in pairs(skills) do
        if ranks[id] and (not activeTracking or activeTracking[kind]) then return true end
    end
    return false
end

local function plain(value, kind)
    return not (issecretvalue and issecretvalue(value)) and type(value) == kind
end

local function playerPaused()
    for index = 1, 3 do
        local query = index == 1 and InCombatLockdown or index == 2 and UnitAffectingCombat or UnitIsDeadOrGhost
        local blocked = call(query, "player")
        if issecretvalue and issecretvalue(blocked) then return true end
        if plain(blocked, "boolean") and blocked then return true end
    end
    return false
end

local function pruneHeard(now)
    for name, record in pairs(heardResources) do
        if now - record.lastSeen >= quietTime then heardResources[name] = nil end
    end
end

-- The two detectors share playback and acknowledge an existing notice from
-- the other source, rather than sounding twice for the same nearby resource.
function ns.ObserveGatherResource(name)
    local now = call(GetTime)
    if not number(now) or not plain(name, "string") then return end
    pruneHeard(now)
    if heardResources[name] then heardResources[name].lastSeen = now end
end

function ns.PlayGatherNotice(name, source, preview)
    if not ns.db or ns.db.gatherSound ~= true then return false, "muted" end
    if not preview and ns.db.gatherAlerts ~= true then return false, "disabled" end
    if ns.gatherSoundWorldPaused or playerPaused() then return false, "paused" end
    local now = call(GetTime)
    if not number(now) then return false, "no-clock" end
    pruneHeard(now)
    local named = plain(name, "string") and plain(source, "string")
    local record = named and heardResources[name]
    if record and not record.sources[source] then
        record.sources[source] = true
        return true, "shared"
    end
    if now < nextSound then return false, "cooldown" end
    nextSound = now + 4 -- Limit retries too, including a muted client channel.
    local played = call(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
    if not plain(played, "boolean") or not played then return false, "failed" end
    if named then heardResources[name] = {sources = {[source] = true}, lastSeen = now} end
    return true, "played"
end

local function clearTarget()
    target, targetUntil, hintTarget, hintUntil = nil, nil, nil, nil
    hud:Hide()
end

local function eligibleResource(name, ranks, requireTracking)
    if not plain(name, "string") then return end
    local kind, required = ns.GatherResource(name)
    local rank = kind and ranks[skills[kind]]
    if number(rank) and number(required) and rank >= required
        and (not requireTracking or not activeTracking or activeTracking[kind]) then return kind end
end

local function updateTarget(dots, ranks, now)
    local nearest, nearestKind, nearestDistance
    for _, dot in ipairs(dots) do
        local kind = plain(dot, "table") and eligibleResource(dot.name, ranks, true)
        if kind and number(dot.dx) and number(dot.dy) and (plain(dot.facing, "nil") or number(dot.facing)) then
            ns.ObserveGatherResource(dot.name)
            local distance = dot.dx * dot.dx + dot.dy * dot.dy
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestKind, nearestDistance = dot, kind, distance
            end
            if announcements[dot.name] then announcements[dot.name] = now end
        end
    end
    for name, lastSeen in pairs(announcements) do
        if now - lastSeen >= quietTime then announcements[name] = nil end
    end
    if not nearest then target, targetUntil = nil, nil; return end

    target = {
        name = nearest.name, kind = nearestKind, nearby = nearestDistance < 0.0016,
        bearing = math.atan2(nearest.dx, nearest.dy) - (nearest.facing or 0),
    }
    targetUntil = now + targetLifetime
    if not announcements[target.name] and ns.PlayGatherNotice(target.name, "minimap") then
        announcements[target.name] = now
    end
end

local function updateHint(hints, ranks, now)
    hintTarget, hintUntil = nil, nil
    if not plain(hints, "table") then return end
    for _, hint in ipairs(hints) do
        local kind = plain(hint, "table") and eligibleResource(hint.name, ranks, true)
        if kind and (not hintTarget or hint.name < hintTarget.name) then
            hintTarget = {name = hint.name, kind = kind, hint = true}
            hintUntil = now + targetLifetime
        end
    end
    -- Unlocated text may be stale. It is a visual lead only, never a sound
    -- acknowledgement or a reason to extend a confirmed resource's receipt.
end

local function nearbyTarget(ranks, now)
    if not ns.db.gatherSparkles or not plain(ns.gatherNearbyResources, "table") then return end
    local nearest
    for _, resource in ipairs(ns.gatherNearbyResources) do
        local kind = plain(resource, "table") and eligibleResource(resource.name, ranks, false)
        if kind and number(resource.seenAt) and now >= resource.seenAt and now-resource.seenAt <= 0.6
            and (not nearest or resource.name < nearest.name) then
            nearest = {name = resource.name, kind = kind, nearby = true}
        end
    end
    return nearest
end

local function minimapTarget(resources, ranks, now)
    if not plain(resources, "table") then return end
    local chosen
    for _, resource in ipairs(resources) do
        local kind = plain(resource, "table") and eligibleResource(resource.name, ranks, true)
        if kind and number(resource.seenAt) and now >= resource.seenAt and now - resource.seenAt <= 8 then
            ns.ObserveGatherResource(resource.name)
            if announcements[resource.name] then announcements[resource.name] = now end
            if not chosen or resource.name < chosen.name then
                chosen = {name = resource.name, kind = kind, minimap = true}
            end
        end
    end
    for name, lastSeen in pairs(announcements) do
        if now - lastSeen >= quietTime then announcements[name] = nil end
    end
    if chosen and not announcements[chosen.name] then
        local heard, result = ns.PlayGatherNotice(chosen.name, "minimap")
        ns.gatherAlertSoundResult = result
        if heard then announcements[chosen.name] = now end
    end
    return chosen
end

local function render(current, facing, preview)
    title:SetText(current.minimap and "附近有 " .. current.name or current.hint and "采集线索：" .. current.name or current.name)
    title:SetTextColor(unpack(colors[current.kind]))
    arrow:SetVertexColor(unpack(colors[current.kind]))
    if current.minimap then
        arrow:Hide()
        detail:SetText("小地图范围内")
    elseif current.hint then
        arrow:Hide()
        detail:SetText("位置待确认 · 暂无方向")
    elseif current.nearby then
        arrow:Hide()
        detail:SetText("就在附近")
    elseif not number(facing) or not number(current.bearing) then
        arrow:Hide()
        detail:SetText("小地图范围内")
    else
        local relative = current.bearing + facing
        arrow:SetRotation(-relative)
        arrow:Show()
        local sector = math.floor(relative / (math.pi / 4) + 0.5) % 8 + 1
        detail:SetText(preview and "提示试听 · " .. directions[sector] or directions[sector])
    end
    hud:Show()
end

local function restorePlacement()
    local db = ns.db
    hud:SetScale(db.gatherScale)
    hud:ClearAllPoints()
    -- Saved offsets are in UIParent units so scaling keeps the anchor in place.
    hud:SetPoint(db.gatherPoint, UIParent, db.gatherRelativePoint,
        db.gatherX / db.gatherScale, db.gatherY / db.gatherScale)
end

local function stopMoving()
    if not moving then return end
    moving = false
    hud:StopMovingOrSizing()
    local point, _, relativePoint, x, y = hud:GetPoint()
    if type(point) == "string" and type(relativePoint) == "string" and number(x) and number(y) then
        local db = ns.db
        db.gatherPoint, db.gatherRelativePoint = point, relativePoint
        db.gatherX, db.gatherY = x * db.gatherScale, y * db.gatherScale
    end
end

local function adjustmentLabel()
    detail:SetText(string.format("拖右下角缩放 · %d%%", math.floor(ns.db.gatherScale * 100 + 0.5)))
end

local function renderIdle()
    if adjusting then
        render({ name = "调整采集提示", kind = "mining", bearing = math.pi / 4 }, 0)
        adjustmentLabel()
    else
        clearTarget()
    end
end

local function startResizing()
    if moving or resize then return end
    local x, y = GetCursorPosition()
    local left, top = hud:GetLeft(), hud:GetTop()
    local parentScale = UIParent:GetEffectiveScale()
    if not left or not top or not parentScale or parentScale <= 0 then return end
    local scale = hud:GetEffectiveScale() / parentScale
    resize = {
        cursorX = x, cursorY = y, parentScale = parentScale, startScale = ns.db.gatherScale,
        left = left * scale - (UIParent:GetLeft() or 0),
        top = top * scale - (UIParent:GetBottom() or 0),
    }
end

local function resizeToCursor()
    local x, y = GetCursorPosition()
    local dx = (x - resize.cursorX) / resize.parentScale
    local dy = (resize.cursorY - y) / resize.parentScale
    -- Project the drag onto the frame diagonal to scale the arrow and text together.
    local delta = (dx * HUD_WIDTH + dy * HUD_HEIGHT) / (HUD_WIDTH^2 + HUD_HEIGHT^2)
    local scale = math.floor(math.max(0.7, math.min(1.3, resize.startScale + delta)) * 100 + 0.5) / 100
    local db = ns.db
    if scale == db.gatherScale then return end
    db.gatherPoint, db.gatherRelativePoint = "TOPLEFT", "BOTTOMLEFT"
    db.gatherX, db.gatherY, db.gatherScale = resize.left, resize.top, scale
    restorePlacement()
    if adjusting then adjustmentLabel() end
end

local function finishInteraction()
    if resize then resizeToCursor(); resize = nil end
    stopMoving()
    scanner.Reset()
end

local function setAdjusting(enabled)
    stopMoving()
    adjusting, previewUntil, resize = enabled, nil, nil
    scanner.Reset()
    clearTarget()
    doneButton:SetShown(enabled)
    if enabled then renderIdle() end
end

function ns.CreateGatherAlerts()
    hud = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    hud:SetSize(HUD_WIDTH, HUD_HEIGHT)
    restorePlacement()
    hud:SetFrameStrata("HIGH")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function()
        if not resize then
            hud:StartMoving()
            moving = true
        end
    end)
    hud:SetScript("OnDragStop", finishInteraction)
    hud:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then finishInteraction() end
    end)
    hud:SetScript("OnHide", function()
        stopMoving()
        resize = nil
    end)
    hud:EnableMouse(true)
    hud:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    hud:SetBackdropColor(0.05, 0.07, 0.08, 0.92)
    hud:SetBackdropBorderColor(0.48, 0.39, 0.24, 0.95)

    arrow = hud:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(38, 38)
    arrow:SetPoint("LEFT", hud, "LEFT", 10, 0)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", hud, "TOPLEFT", 56, -10)
    title:SetWidth(178)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    detail = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)

    doneButton = CreateFrame("Button", nil, hud)
    doneButton:SetSize(40, 20)
    doneButton:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -8, -7)
    doneButton:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    doneButton:GetHighlightTexture():SetVertexColor(0.9, 0.77, 0.48, 0.16)
    local doneLabel = doneButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    doneLabel:SetPoint("CENTER")
    doneLabel:SetText("完成")
    doneButton:SetScript("OnClick", function() setAdjusting(false) end)
    doneButton:Hide()

    local resizeGrip = CreateFrame("Button", nil, hud)
    resizeGrip:SetSize(18, 18)
    resizeGrip:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetScript("OnDragStart", startResizing)
    resizeGrip:SetScript("OnDragStop", finishInteraction)
    resizeGrip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then finishInteraction() end
    end)
    hud:Hide()

    local ticker = CreateFrame("Frame", nil, UIParent)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA", "MINIMAP_UPDATE_TRACKING",
        "MINIMAP_UPDATE_ZOOM", "SPELLS_CHANGED" }) do
        pcall(ticker.RegisterEvent, ticker, event)
    end
    ticker:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then ns.gatherSoundWorldPaused = true
        elseif event == "PLAYER_ENTERING_WORLD" then ns.gatherSoundWorldPaused = false end
        scanner.Reset()
        if cursorScanner then cursorScanner.Reset(event) end
        if event ~= "MINIMAP_UPDATE_ZOOM" then activeTracking = readTracking() end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then announcements = {} end
        target, targetUntil, hintTarget, hintUntil = nil, nil, nil, nil
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" or event == "ZONE_CHANGED_NEW_AREA" then
            ns.gatherNearbyResources = nil
        end
        if not adjusting and not previewUntil and not moving and not resize then clearTarget() end
    end)

    local elapsedSincePoll = 0
    ticker:SetScript("OnUpdate", function(_, elapsed)
        -- Mouse-up can be lost when the pointer leaves the window or focus changes.
        if (moving or resize) and call(IsMouseButtonDown, "LeftButton") == false then finishInteraction() end
        if resize then
            if cursorScanner then cursorScanner.Poll(false) end
            resizeToCursor(); return
        end
        if moving then
            if cursorScanner then cursorScanner.Poll(false) end
            return
        end
        elapsedSincePoll = elapsedSincePoll + elapsed
        if elapsedSincePoll < pollInterval then return end
        elapsedSincePoll = 0
        local now = GetTime()
        if previewUntil and now < previewUntil then
            if cursorScanner then cursorScanner.Poll(false) end
            return
        end
        if previewUntil then previewUntil = nil; clearTarget() end

        local ranks = learnedGathering()
        local facing = call(GetPlayerFacing)
        if ns.gatherSoundWorldPaused or not ns.db.gatherAlerts or playerPaused() then
            scanner.Reset()
            if cursorScanner then cursorScanner.Poll(false) end
            target, targetUntil, hintTarget, hintUntil = nil, nil, nil, nil
            renderIdle()
            return
        end
        local confirmed
        if cursorScanner then
            -- The native-cursor scan owns minimap hit testing while it runs.
            -- Never run the legacy soft-cursor scanner alongside it.
            scanner.Reset()
            target, targetUntil, hintTarget, hintUntil = nil, nil, nil, nil
            local resources = cursorScanner.Poll(canScan(ranks))
            confirmed = minimapTarget(resources, ranks, now)
        elseif scanner.IsSupported() and canScan(ranks) and Minimap and call(Minimap.IsVisible, Minimap) then
            local dots, hints = scanner.Scan()
            if plain(dots, "table") then
                updateTarget(dots, ranks, now)
                updateHint(hints, ranks, now)
            end
        else
            scanner.Reset()
            target, targetUntil, hintTarget, hintUntil = nil, nil, nil, nil
        end
        local nearby = nearbyTarget(ranks, now)
        if target and now < targetUntil and eligibleResource(target.name, ranks, true) then render(target, facing)
        elseif nearby then render(nearby, nil)
        elseif confirmed then render(confirmed, nil)
        elseif hintTarget and now < hintUntil and eligibleResource(hintTarget.name, ranks, true) then render(hintTarget, nil)
        else renderIdle() end
    end)
    activeTracking = readTracking()
end

function ns.GatherCommand(action)
    if action == "move" then
        setAdjusting(not adjusting)
        if adjusting then ns.Print("拖动采集提示框移动，拖右下角缩放，点「完成」退出预览。") end
        return
    end
    if action == "test" then
        if adjusting then setAdjusting(false) end
        previewUntil = GetTime() + 5
        render({ name = "采集提醒测试", kind = "mining", bearing = math.pi / 4 }, 0, true)
        ns.PlayGatherNotice(nil, nil, true)
        return
    end
    if action == "on" or action == "off" then
        ns.db.gatherAlerts = action == "on"
        setAdjusting(false)
    elseif action == "mute" or action == "unmute" then
        ns.db.gatherSound = action == "unmute"
    end
    ns.Print("采集提醒" .. (ns.db.gatherAlerts and "已开启" or "已关闭") .. "，声音" .. (ns.db.gatherSound and "开启" or "静音") .. "。")
    if cursorScanner and not cursorScanner.IsSupported() or not cursorScanner and not scanner.IsSupported() then
        ns.Print("当前客户端没有可用的小地图资源读取接口。")
    end
    if activeTracking and not next(activeTracking) then ns.Print("请先在小地图追踪中开启寻找矿物、草药或鱼群。") end
    ns.Print("/myprof gather on / off · mute / unmute · test 试箭头和声音")
    ns.Print("/myprof gather move 调整位置与大小")
end
