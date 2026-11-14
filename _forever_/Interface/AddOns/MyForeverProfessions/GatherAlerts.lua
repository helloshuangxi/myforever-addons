local _, ns = ...
-- Shared layout hooks (grid while dragging, snap on release, /myui tags).
local function mfLayout(name, ...)
    local S = rawget(_G, "MyForeverStyle")
    local fn = type(S) == "table" and rawget(S, name)
    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        return ok and result or nil
    end
end
local call = ns.SafeCall
local scanner = ns.GatherScan

local skills = { mining = 186, herbalism = 182, fishing = 356 }
local trackingSpells = { [2580] = "mining", [2383] = "herbalism", [43308] = "fishing" }
local trackingNames = {
    ["寻找矿物"] = "mining", ["寻找草药"] = "herbalism", ["寻找鱼群"] = "fishing",
    ["Find Minerals"] = "mining", ["Find Herbs"] = "herbalism", ["Find Fish"] = "fishing",
}
local colors = { mining = {1, 0.76, 0.36}, herbalism = {0.56, 0.9, 0.54}, fishing = {0.5, 0.82, 1} }
local pollInterval, targetLifetime, quietTime = 0.10, 3.5, 10
local HUD_WIDTH, HUD_HEIGHT = 244, 58
local hud, arrow, title, detail, doneButton
local target, targetUntil, previewUntil
local adjusting, moving, resize
local activeTracking
local announcements, nextSound = {}, 0
local heardResources = {}
local lastTrackingHint
local lastCapabilityHint

local function public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function plain(value, kind)
    return public(value) and type(value) == kind
end

local function number(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

local function readTracking()
    local minimap = C_Minimap
    local count = call(minimap and minimap.GetNumTrackingTypes)
    if not number(count) or count < 0 or count > 256 or count % 1 ~= 0
        or type(minimap.GetTrackingInfo) ~= "function" then return nil end
    local active = {}
    for index = 1, count do
        local info = call(minimap.GetTrackingInfo, index)
        if not public(info) then return nil end
        if info ~= nil and type(info) ~= "table" then return nil end
        if info then
            local enabled = info.active
            if not plain(enabled, "boolean") then return nil end
            local kind
            if enabled then
                local spellID = info.spellID
                if issecretvalue and issecretvalue(spellID) then return nil end
                if spellID == nil then
                    local filter = call(minimap.GetTrackingFilter, index)
                    if not public(filter) then return nil end
                    if filter ~= nil and type(filter) ~= "table" then return nil end
                    spellID = filter and filter.spellID
                    if issecretvalue and issecretvalue(spellID) then return nil end
                end
                kind = number(spellID) and trackingSpells[spellID]
                -- A public spell ID is sufficient; a restricted display name
                -- need not be read or compared just to identify its filter.
                if not kind then
                    local name = info.name
                    if not public(name) then return nil end
                    if plain(name, "string") then kind = trackingNames[name] end
                end
            end
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

local function updateTrackingHint(ranks)
    local missing = {}
    if ns.detectReady and activeTracking and not canScan(ranks) then
        for _, kind in ipairs({"mining", "herbalism", "fishing"}) do
            if ranks[skills[kind]] and not activeTracking[kind] then
                missing[#missing + 1] = kind == "mining" and "寻找矿物"
                    or kind == "herbalism" and "寻找草药" or "寻找鱼群"
            end
        end
    end
    local hint = #missing > 0 and "小地图检测暂停：请在小地图追踪中开启" .. table.concat(missing, "／") .. "。" or nil
    ns.gatherTrackingHint = hint
    if hint and hint ~= lastTrackingHint then ns.Print(hint) end
    lastTrackingHint = hint
end

local function capabilityHint()
    if ns.gatherMinimapAccessRestricted == true then
        return "客户端限制了小地图矿草名称读取，已暂停自动扫描；可确认的近处资源仍按现有提醒、声音与闪光设置处理。"
    end
end

local function updateCapabilityHint(ranks)
    local learned = next(ranks) ~= nil
    local hint = learned and capabilityHint() or nil
    ns.gatherCapabilityHint = hint
    if hint and hint ~= lastCapabilityHint then ns.Print(hint); lastCapabilityHint = hint end
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

local function resourceKey(name)
    return ns.GatherResourceKey and ns.GatherResourceKey(name) or name
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
    name = resourceKey(name)
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
    name = named and resourceKey(name) or name
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
    ns.gatherNoticeSoundCount = (ns.gatherNoticeSoundCount or 0) + 1
    return true, "played"
end

-- Fallback display for a secret name: Blizzard's tooltip renders the stored
-- tooltip record through its own secure path. Created on first use.
local nameTip
local function hideNameTip() if nameTip then pcall(nameTip.Hide, nameTip) end end
local function showNameTip(data)
    if not plain(data, "table") then return false end
    if not nameTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "MyForeverProfessionsGatherNameTip", UIParent, "GameTooltipTemplate")
        if not ok or not tip then return false end
        nameTip = tip
    end
    local ok = pcall(function()
        nameTip:SetOwner(hud, "ANCHOR_NONE")
        nameTip:ClearAllPoints()
        nameTip:SetPoint("TOPLEFT", hud, "BOTTOMLEFT", 0, -2)
        nameTip:ProcessInfo({ tooltipData = data })
    end)
    if not ok then hideNameTip() end
    return ok
end

local function clearTarget()
    target, targetUntil = nil, nil
    hideNameTip()
    hud:Hide()
    ns.gatherAlertLabel = nil
end

-- A secret-name hit cannot be matched against the resource catalogue. It is accepted
-- only while a gathering tracking mode the character has learned is active, and takes
-- that mode's kind for colour. Its skill requirement is unknown and is not claimed.
local function opaqueKind(ranks)
    if not activeTracking then return end
    for _, kind in ipairs({"mining", "herbalism", "fishing"}) do
        if activeTracking[kind] and ranks[skills[kind]] then return kind end
    end
end

local function eligibleResource(name, ranks, requireTracking)
    if not plain(name, "string") then return end
    if name == ns.GATHER_OPAQUE_NAME then
        return ns.GatherOpaqueAllowed and ns.GatherOpaqueAllowed() and opaqueKind(ranks) or nil
    end
    local kind, required = ns.GatherResource(name)
    local rank = kind and ranks[skills[kind]]
    if number(rank) and number(required) and rank >= required
        and (not requireTracking or not activeTracking or activeTracking[kind]) then return kind end
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
    for name, lastSeen in pairs(announcements) do
        if now - lastSeen >= quietTime then announcements[name] = nil end
    end
    local chosen
    for _, resource in ipairs(resources) do
        local kind = plain(resource, "table") and eligibleResource(resource.name, ranks, true)
        if kind and number(resource.seenAt) and now >= resource.seenAt and now - resource.seenAt <= 8 then
            ns.ObserveGatherResource(resource.name)
            local key = resourceKey(resource.name)
            if announcements[key] then announcements[key] = now end
            -- A compact sample can contain several real names. Give an
            -- unannounced fresh name a turn, rather than always selecting the
            -- first name and permanently starving the others.
            local chosenSeen=chosen and announcements[resourceKey(chosen.name)]
            local seen=announcements[key]
            if not chosen or (chosenSeen and not seen)
                or ((not chosenSeen)==(not seen) and resource.name<chosen.name) then
                chosen = {name = resource.name, kind = kind, minimap = true, text = resource.text, data = resource.data}
            end
        end
    end
    local key = chosen and resourceKey(chosen.name)
    if chosen and not announcements[key] then
        local heard, result = ns.PlayGatherNotice(chosen.name, "minimap")
        ns.gatherAlertSoundResult = result
        if heard then announcements[key] = now end
    end
    return chosen
end

local function render(current)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", hud, "TOPLEFT", 12, -10)
    title:SetWidth(HUD_WIDTH - 24)
    local opaque = current.name == ns.GATHER_OPAQUE_NAME
    local viaTip
    if opaque then
        -- Hand the game's own text straight back to the font string. Nothing here reads it.
        -- If this client refuses that, let Blizzard's tooltip draw the stored record.
        if not pcall(title.SetText, title, current.text) then
            title:SetText("小地图有追踪资源")
            viaTip = showNameTip(current.data)
        else hideNameTip() end
    else
        hideNameTip()
        title:SetText(current.layoutOnly and current.name or "附近有 " .. current.name)
    end
    title:SetTextColor(unpack(colors[current.kind]))
    arrow:Hide()
    detail:SetText(current.layoutOnly and "" or current.nearby and "就在附近"
        or viaTip and "名称见下方提示" or opaque and "小地图范围内 · 名称由游戏显示" or "小地图范围内")
    hud:Show()
    ns.gatherAlertLabel = current.layoutOnly and nil or opaque and "小地图范围内有追踪标记（名称由游戏显示）"
        or "附近有 " .. current.name
end

local function restorePlacement()
    local db = ns.db
    hud:SetScale(db.gatherScale)
    hud:ClearAllPoints()
    -- Saved offsets are in UIParent units so scaling keeps the anchor in place.
    hud:SetPoint(db.gatherPoint, UIParent, db.gatherRelativePoint,
        db.gatherX / db.gatherScale, db.gatherY / db.gatherScale)
end

-- Offsets are stored in UIParent units (see restorePlacement).
local function savePlacement()
    local point, _, relativePoint, x, y = hud:GetPoint()
    if type(point) == "string" and type(relativePoint) == "string" and number(x) and number(y) then
        local db = ns.db
        db.gatherPoint, db.gatherRelativePoint = point, relativePoint
        db.gatherX, db.gatherY = x * db.gatherScale, y * db.gatherScale
    end
end

local function stopMoving()
    if not moving then return end
    moving = false
    hud:StopMovingOrSizing()
    mfLayout("SnapToGrid", hud)
    savePlacement()
end

local function adjustmentLabel()
    detail:SetText(string.format("拖右下角缩放 · %d%%", math.floor(ns.db.gatherScale * 100 + 0.5)))
end

local function renderIdle()
    if adjusting then
        render({ name = "调整采集提示", kind = "mining", layoutOnly = true })
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
    -- Project the drag onto the frame diagonal to scale the notice together.
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
            mfLayout("BeginDrag", hud)
        end
    end)
    hud:SetScript("OnDragStop", finishInteraction)
    mfLayout("RegisterLayout", hud, "商业技能 · 采集提示", {
        save = function() savePlacement() end,
        reset = function()
            local db = ns.db
            db.gatherPoint, db.gatherRelativePoint, db.gatherX, db.gatherY = "CENTER", "CENTER", 0, 170
            restorePlacement()
        end,
        scale = {
            get = function() return ns.db.gatherScale end,
            set = function(value) ns.db.gatherScale = value; restorePlacement() end,
            min = 0.7, max = 1.3, step = 0.05,
        },
    })
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
        if event == "MINIMAP_UPDATE_TRACKING" then
            local current = readTracking()
            if current and activeTracking
                and current.mining == activeTracking.mining and current.herbalism == activeTracking.herbalism
                and current.fishing == activeTracking.fishing then return end
        end
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then ns.gatherSoundWorldPaused = true
        elseif event == "PLAYER_ENTERING_WORLD" then ns.gatherSoundWorldPaused = false end
        scanner.Reset()
        if event ~= "MINIMAP_UPDATE_ZOOM" then activeTracking = readTracking() end
        if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then announcements = {} end
        target, targetUntil = nil, nil
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
            resizeToCursor(); return
        end
        if moving then
            return
        end
        elapsedSincePoll = elapsedSincePoll + elapsed
        if elapsedSincePoll < pollInterval then return end
        elapsedSincePoll = 0
        local now = GetTime()
        if previewUntil and now < previewUntil then
            return
        end
        if previewUntil then previewUntil = nil; clearTarget() end

        local ranks = learnedGathering()
        if ns.gatherSoundWorldPaused or not ns.db.gatherAlerts or playerPaused() then
            ns.gatherTrackingHint = nil
            ns.gatherCapabilityHint = nil
            if not ns.db.gatherAlerts then lastTrackingHint = nil end
            scanner.Reset()
            target, targetUntil = nil, nil
            ns.gatherScanCount = 0
            renderIdle()
            return
        end
        if ns.gatherMinimapAccessRestricted == true then ns.gatherTrackingHint = nil
        else updateTrackingHint(ranks) end
        if ns.gatherMinimapAccessRestricted ~= true and scanner.IsSupported()
            and canScan(ranks) and Minimap and call(Minimap.IsVisible, Minimap) then
            -- The source router returns fresh confirmed names only: no resource
            -- position, heading or repeated cached tooltip hint.
            local names = scanner.ScanNames()
            if ns.gatherMinimapAccessRestricted == true then
                -- The source may discover a restricted name during this poll.
                -- Drop the previous minimap target and any same-call receipt.
                scanner.Reset("restricted")
                target, targetUntil = nil, nil
                ns.gatherScanCount = 0
            elseif plain(names, "table") then
                local resources = {}
                for _, item in ipairs(names) do
                    if plain(item, "table") and plain(item.name, "string") then
                        -- item.text may be a secret; it is carried, never examined.
                        resources[#resources + 1] = {name = item.name, seenAt = now, text = item.text, data = item.data}
                    end
                end
                target = minimapTarget(resources, ranks, now)
                targetUntil = target and now + targetLifetime or nil
                ns.gatherScanPasses = (ns.gatherScanPasses or 0) + 1
                ns.gatherScanCount = #resources
            end
        else
            scanner.Reset()
            target, targetUntil = nil, nil
            ns.gatherScanCount = 0
        end
        updateCapabilityHint(ranks)
        local nearby = nearbyTarget(ranks, now)
        if nearby then render(nearby)
        elseif target and now < targetUntil and eligibleResource(target.name, ranks, true) then render(target)
        else renderIdle() end
    end)
    activeTracking = readTracking()
end

function ns.GatherCommand(action)
    if action == "debug" then
        if ns.gatherTrackingHint then ns.Print(ns.gatherTrackingHint) end
        local hint = capabilityHint()
        if hint then ns.Print(hint) end
        local data = call(scanner.ScanDiagnostics)
        if not plain(data, "table") then
            ns.Print("当前没有可用的读取诊断。")
            return
        end
        local function names(items)
            local result = {}
            if plain(items, "table") then
                for _, name in ipairs(items) do
                    if plain(name, "string") and ns.GatherResource(name) then result[#result + 1] = name end
                end
            end
            return #result > 0 and table.concat(result, "、") or "无"
        end
        ns.Print((data.method == "cursor" and "替身地图实验" or "原方式") .. "读取状态："
            .. tostring(data.state or "unknown") .. " / " .. tostring(data.reason or "none"))
        ns.Print((data.method == "cursor" and "累计读取 " or "上轮采样 ") .. tostring(number(data.sampleCount) and data.sampleCount or 0)
            .. " 点；矿草原文名称：" .. names(data.rawKnownNames))
        ns.Print("上轮有效名称：" .. names(data.acceptedNames) .. "；过滤名称：" .. names(data.rejectedKnownNames))
        if data.method == "cursor" then
            local function count(key)
                local value = data[key]
                return tostring(number(value) and value >= 0 and math.floor(value) or 0)
            end
            ns.Print("累计原生提示：空返回 " .. count("tooltipNilCount") .. "，空表 " .. count("tooltipEmptyCount")
                .. "，非空 " .. count("tooltipNonemptyCount") .. "，已知矿草 " .. count("tooltipKnownCount")
                .. "，其他 " .. count("tooltipUnknownCount") .. "，异常 " .. count("tooltipInvalidCount"))
        end
        return
    end
    if action == "move" then
        setAdjusting(not adjusting)
        if adjusting then ns.Print("拖动采集提示框移动，拖右下角缩放，点「完成」退出预览。") end
        return
    end
    if action == "test" then
        if adjusting then setAdjusting(false) end
        previewUntil = GetTime() + 5
        scanner.Reset()
        render({name = "铜矿（测试）", kind = "mining", minimap = true})
        ns.PlayGatherNotice(nil, nil, true)
        return
    end
    if action == "original" or action == "cursor" or action == "experiment" then
        ns.db.gatherMethod = action == "original" and "original" or "cursor"
        scanner.Reset("source-change")
        target, targetUntil, previewUntil = nil, nil, nil
        setAdjusting(false)
        clearTarget()
    elseif action == "on" or action == "off" then
        ns.db.gatherAlerts = action == "on"
        setAdjusting(false)
    elseif action == "mute" or action == "unmute" then
        ns.db.gatherSound = action == "unmute"
    elseif action == "passthrough on" or action == "passthrough off" then
        -- Off restores the earlier rule: a secret name pauses minimap reading for the session.
        ns.db.gatherOpaque = action == "passthrough on"
        scanner.Reset()
    end
    ns.Print("采集提醒" .. (ns.db.gatherAlerts and "已开启" or "已关闭") .. "，声音" .. (ns.db.gatherSound and "开启" or "静音") .. "。")
    ns.Print("读取方式：" .. (ns.db.gatherMethod == "cursor" and "替身地图实验（仅本机）" or "原方式") .. "。")
    ns.Print("加密名称直显：" .. (ns.db.gatherOpaque == true and "开启" or "关闭") .. "（/myprof gather passthrough on / off）。")
    local hint = capabilityHint()
    if hint then
        ns.Print(hint)
    elseif not scanner.IsSupported() then
        ns.Print("当前客户端没有可用的小地图资源读取接口。")
    end
    if not hint and activeTracking and not next(activeTracking) then ns.Print("请先在小地图追踪中开启寻找矿物、草药或鱼群。") end
    ns.Print("小地图读取资源 " .. tostring(ns.gatherScanCount or 0) .. " 种，完成扫描 "
        .. tostring(ns.gatherScanPasses or 0) .. " 次；提示音调用成功 " .. tostring(ns.gatherNoticeSoundCount or 0) .. " 次。")
    if ns.gatherAlertLabel then ns.Print("当前提示：" .. ns.gatherAlertLabel) end
    ns.Print("/myprof gather on / off · mute / unmute · test 试听提示")
    ns.Print("/myprof gather move 调整位置与大小")
    ns.Print("/myprof gather original 回到原方式 · cursor 使用替身地图实验")
end
