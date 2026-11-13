local _, ns = ...

local settings = {
    SoftTargetInteract = "3",
    SoftTargetIconGameObject = "1",
    SoftTargetInteractArc = "2",
    SoftTargetInteractRange = "30",
}
local skillIDs = { mining = 186, herbalism = 182 }
local colors = { mining = {1, 0.74, 0.25}, herbalism = {0.44, 0.95, 0.48} }
local effects, unitPlates = {}, {}
local observedCVars = {}
local initialized, configured, recovering, writing, loggingOut = false, false, true, false, false
local lastEnabled
local pending = true
local soundResources, soundUnits = {}, {}
local soundQuietTime = 10

local function plain(value, kind)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == kind
end

local function number(value)
    return plain(value, "number") and value == value and math.abs(value) < math.huge
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, first = pcall(fn, ...)
    if ok then return first end
end

local function supported()
    return type(CreateFrame) == "function" and type(UnitIsGameObject) == "function" and type(UnitName) == "function"
        and type(ns.GatherResource) == "function"
end

local function plateAPI()
    if C_NamePlate and type(C_NamePlate.GetNamePlates) == "function"
        and type(C_NamePlate.GetNamePlateForUnit) == "function" then return C_NamePlate end
end

local function inCombat()
    local lockdown = call(InCombatLockdown)
    local fighting = call(UnitAffectingCombat, "player")
    return (plain(lockdown, "boolean") and lockdown) or (plain(fighting, "boolean") and fighting)
end

local function cvarAPI()
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if type(get) == "function" and type(set) == "function" then return get, set end
end

local function equivalent(a, b)
    if not plain(a, "string") or not plain(b, "string") then return false end
    if a == b then return true end
    local left, right = tonumber(a), tonumber(b)
    return number(left) and number(right) and left == right
end

local function ownTables()
    local db = ns.db
    if not plain(db.gatherSparkleCVars, "table") then db.gatherSparkleCVars = {} end
    if not plain(db.gatherSparkleOverrides, "table") then db.gatherSparkleOverrides = {} end
    return db.gatherSparkleCVars, db.gatherSparkleOverrides
end

local function writeCVar(set, key, value)
    writing = true
    pcall(set, key, value)
    writing = false
end

local function restoreCVars(get, set)
    local owned, overrides = ownTables()
    for key in pairs(settings) do
        local record = owned[key]
        if plain(record, "table") and plain(record.before, "string") and plain(record.applied, "string") then
            local current = call(get, key)
            if plain(current, "string") then
                if equivalent(current, record.applied) then
                    writeCVar(set, key, record.before)
                    current = call(get, key)
                    if equivalent(current, record.before) then
                        owned[key] = nil
                    elseif plain(current, "string") and not equivalent(current, record.applied) then
                        overrides[key], owned[key] = true, nil
                    end
                else
                    overrides[key], owned[key] = true, nil
                end
            end
        end
    end
    return not next(owned)
end

local function checkOverrides(get)
    if not configured then return end
    local owned, overrides = ownTables()
    for key in pairs(settings) do
        local record = owned[key]
        local expected = plain(record, "table") and record.applied or observedCVars[key]
        local current = call(get, key)
        if expected and plain(current, "string") and not equivalent(current, expected) then
            overrides[key], owned[key] = true, nil
        end
    end
end

local function applyCVars(get, set)
    local owned, overrides = ownTables()
    for key, desired in pairs(settings) do
        local before = call(get, key)
        if not overrides[key] and not owned[key] and plain(before, "string") and not equivalent(before, desired) then
            owned[key] = { before = before, applied = desired }
            writeCVar(set, key, desired)
            local current = call(get, key)
            if plain(current, "string") and not equivalent(current, desired) then
                owned[key] = nil
                if plain(current, "string") and not equivalent(current, before) then overrides[key] = true end
            end
        end
        local current = call(get, key)
        if not overrides[key] and plain(current, "string") then observedCVars[key] = current end
    end
end

local function syncCVars(enabled)
    local get, set = cvarAPI()
    if not get then return false end
    if lastEnabled ~= nil and enabled ~= lastEnabled then
        configured = false
        if enabled then
            ns.db.gatherSparkleOverrides = {}
            observedCVars = {}
        end
    end
    lastEnabled = enabled
    if inCombat() then return false end
    if recovering then
        recovering = not restoreCVars(get, set)
        if recovering then return false end
    end
    if not enabled or loggingOut then
        configured = false
        return restoreCVars(get, set)
    end
    if not configured then
        applyCVars(get, set)
        configured = true
    else
        checkOverrides(get)
    end
    return true
end

local function hideEffect(effect)
    effect.frame:Hide()
    if effect.unit then unitPlates[effect.unit] = nil end
    effect.unit, effect.kind = nil, nil
end

local function hideAll()
    for _, effect in pairs(effects) do hideEffect(effect) end
    ns.gatherSparkleCount = 0
    ns.gatherNearbyCount = 0
    ns.gatherNearbyResources = nil
end

local function learnedRanks()
    local ranks = {}
    if not plain(ns.detectReady, "boolean") or not ns.detectReady or not plain(ns.professions, "table") then return ranks end
    for _, profession in ipairs(ns.professions) do
        if plain(profession, "table") and number(profession.id) and number(profession.rank)
            and number(profession.modifier) then
            ranks[profession.id] = profession.rank + profession.modifier
        end
    end
    return ranks
end

local function eligible(unit, ranks)
    if not plain(unit, "string") then return nil end
    local object = call(UnitIsGameObject, unit)
    if not plain(object, "boolean") or not object then return nil end
    local name = call(UnitName, unit)
    if not plain(name, "string") then return nil end
    local kind, required = ns.GatherResource(name)
    if not plain(kind, "string") then return nil end
    local id = skillIDs[kind]
    if not id or not number(required) or not number(ranks[id]) or ranks[id] < required then return nil end
    return kind, name
end

local function noticeResource(unit, name, now, softObservation)
    if not number(now) or type(ns.PlayGatherNotice) ~= "function" then return end
    local guid = call(UnitGUID, unit)
    guid = plain(guid, "string") and guid ~= "" and guid or nil
    local previous = soundUnits[unit]
    if previous and (previous.name ~= name or now - previous.lastSeen >= soundQuietTime) then previous = nil end
    -- A soft target can be recognized before the client creates its nameplate.
    -- With no readable identity, conservatively carry its same-name receipt
    -- into a newly available plate instead of announcing the handoff twice.
    if not previous and softObservation and not softObservation.guid
        and softObservation.name == name and now - softObservation.lastSeen < soundQuietTime then
        previous = softObservation
    end
    -- A resource's GUID can temporarily become unreadable without its plate
    -- disappearing. Keep that identity, but a different readable GUID is new.
    local key = guid and ("guid:" .. guid) or previous and previous.key or ("name:" .. name)
    local record = soundResources[key]
    if not record then
        record = {lastSeen = now}
        soundResources[key] = record
    end
    if guid and previous and not previous.guid then
        local fallback = soundResources[previous.key]
        -- An anonymous receipt can explain only one subsequently readable
        -- object. Bind even while playback is pending, so a later successful
        -- anonymous notice cannot be inherited by every same-name plate.
        if fallback and (not fallback.adoptedGuid or fallback.adoptedGuid == guid) then
            fallback.adoptedGuid = guid
        end
    end
    if guid then
        local fallback = soundResources["name:" .. name]
        if fallback and fallback.adoptedGuid == guid and fallback.announced then
            record.announced = true
        end
    end
    record.lastSeen = now
    soundUnits[unit] = {name = name, guid = guid or previous and previous.guid, key = key, lastSeen = now}
    if type(ns.ObserveGatherResource) == "function" then ns.ObserveGatherResource(name) end
    if not record.announced then
        local heard, result = ns.PlayGatherNotice(name, "nearby")
        ns.gatherSparkleSoundResult = result
        if heard then
            record.announced = true
            if result == "played" then ns.gatherSparkleSoundCount = (ns.gatherSparkleSoundCount or 0) + 1 end
        end
    end
    -- If a plate returns under another unit token with no readable GUID, its
    -- name still remembers the notice. Reserve this handoff even while sound
    -- is pending, so a soft target that appears during cooldown stays tied to
    -- the same readable object.
    if guid then
        local fallbackKey = "name:" .. name
        local fallback = soundResources[fallbackKey] or {}
        -- Receipts created in the reverse order (plate before soft target)
        -- already belong to this readable identity. Do not leave them free
        -- for another plate to adopt, or replace an earlier binding.
        fallback.adoptedGuid = fallback.adoptedGuid or guid
        if fallback.adoptedGuid == guid then
            if record.announced then fallback.announced = true end
            fallback.lastSeen = now
        end
        soundResources[fallbackKey] = fallback
    end
end

local function plateUnit(plate)
    local unit = plate.namePlateUnitToken
    if plain(unit, "string") then return unit end
    local frame = plate.UnitFrame
    if not (issecretvalue and issecretvalue(frame)) and frame and plain(frame.unit, "string") then return frame.unit end
end

local function createEffect(plate)
    local frame = CreateFrame("Frame", nil, plate)
    frame:SetSize(80, 62)
    frame:SetPoint("BOTTOM", plate, "BOTTOM", 0, 0)
    frame:EnableMouse(false)
    frame:Hide()
    local effect = { frame = frame, sparks = {}, phase = 0, elapsed = 0, needsPaint = true }
    for index = 1, 4 do
        local spark = { glow = {}, outline = {}, core = {} }
        for arm = 1, 2 do
            local horizontal = arm == 1
            local function cross(layer, length, width, blend, r, g, b)
                local texture = frame:CreateTexture(nil, layer)
                texture:SetBlendMode(blend)
                texture:SetSize(horizontal and length or width, horizontal and width or length)
                texture:SetColorTexture(r, g, b, 1)
                return texture
            end
            -- The opaque dark edge keeps the marker visible against snow and
            -- bright rocks; additive light alone disappears on those surfaces.
            spark.glow[arm] = cross("BACKGROUND", 24, 10, "ADD", 1, 1, 1)
            spark.outline[arm] = cross("ARTWORK", 18, 7.5, "BLEND", 0.035, 0.025, 0.015)
            spark.core[arm] = cross("OVERLAY", 14, 3.5, "BLEND", 1, 1, 1)
        end
        effect.sparks[index] = spark
    end
    frame:SetScript("OnShow", function() effect.needsPaint = true end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        effect.elapsed = effect.elapsed + elapsed
        if effect.elapsed < 0.05 then return end
        effect.phase = effect.phase + effect.elapsed
        effect.elapsed = 0
        for index, spark in ipairs(effect.sparks) do
            local phase = effect.phase * 1.8 + index * math.pi / 2
            local x = math.cos(phase * 0.55) * (12 + index * 2)
            local y = 9 + index * 8 + math.sin(phase * 0.7) * 3
            local pulse = (math.sin(phase) + 1) / 2
            for layer, textures in pairs(spark) do
                local alpha = layer == "outline" and 0.92
                    or layer == "core" and (0.65 + pulse * 0.35)
                    or (0.12 + pulse * 0.16)
                for _, texture in ipairs(textures) do
                    texture:ClearAllPoints()
                    texture:SetPoint("CENTER", frame, "BOTTOM", x, y)
                    texture:SetAlpha(alpha)
                end
            end
        end
        -- Native object plates can be reused during reload. Repaint once after
        -- the first visible layout, when their texture geometry is ready.
        if effect.needsPaint then
            for _, spark in ipairs(effect.sparks) do
                for layer, textures in pairs(spark) do
                    for _, texture in ipairs(textures) do
                        if layer == "outline" then
                            texture:SetColorTexture(0.035, 0.025, 0.015, 1)
                        else
                            texture:SetColorTexture(1, 1, 1, 1)
                            if colors[effect.kind] then texture:SetVertexColor(unpack(colors[effect.kind])) end
                        end
                    end
                end
            end
            effect.needsPaint = false
        end
    end)
    effects[plate] = effect
    return effect
end

local function showEffect(plate, unit, kind, scale)
    local effect = effects[plate] or createEffect(plate)
    if effect.unit and effect.unit ~= unit then unitPlates[effect.unit] = nil end
    effect.unit, effect.kind = unit, kind
    unitPlates[unit] = plate
    effect.frame:SetScale(scale)
    for _, spark in ipairs(effect.sparks) do
        for _, texture in ipairs(spark.glow) do texture:SetVertexColor(unpack(colors[kind])) end
        for _, texture in ipairs(spark.core) do texture:SetVertexColor(unpack(colors[kind])) end
    end
    effect.frame:Show()
end

function ns.RefreshGatherSparkles()
    if not initialized or loggingOut or not ns.db then return end
    if ns.gatherSoundWorldPaused then
        hideAll()
        return
    end
    if not supported() or not cvarAPI() then
        ns.gatherSparkleState = "unsupported"
        hideAll()
        return
    end
    local enabled = plain(ns.db.gatherSparkles, "boolean") and ns.db.gatherSparkles
    local ready = syncCVars(enabled)
    if inCombat() then
        ns.gatherSparkleState = "combat"
        hideAll()
        return
    end
    local dead = call(UnitIsDeadOrGhost, "player")
    if (issecretvalue and issecretvalue(dead)) or (plain(dead, "boolean") and dead) then
        ns.gatherSparkleState = "paused"
        hideAll()
        return
    end
    if not enabled or not ready then
        ns.gatherSparkleState = enabled and "recovery" or "disabled"
        hideAll()
        return
    end
    local nativePlates = plateAPI()
    local plates = call(nativePlates and nativePlates.GetNamePlates)
    local platesReady = plain(plates, "table")
    if not platesReady then plates = {} end
    local scale = ns.db.gatherSparkleScale
    if not number(scale) then scale = 1 end
    scale = math.max(0.6, math.min(1.6, scale))
    local now = call(GetTime)
    if number(now) then
        for key, record in pairs(soundResources) do
            if now - record.lastSeen >= soundQuietTime then soundResources[key] = nil end
        end
        for unit, record in pairs(soundUnits) do
            if now - record.lastSeen >= soundQuietTime then soundUnits[unit] = nil end
        end
    end
    local ranks, seen, count = learnedRanks(), {}, 0
    local nearby, nearbyNames = {}, {}
    local softKind, softName = eligible("softinteract", ranks)
    local function publish(unit, name, kind, softObservation)
        noticeResource(unit, name, now, softObservation)
        if number(now) and not nearbyNames[name] then
            nearbyNames[name] = true
            nearby[#nearby + 1] = {name = name, kind = kind, seenAt = now}
        end
    end
    -- A real, eligible interaction target is sufficient evidence for nearby
    -- text and sound even when no resource nameplate exists. Refresh its sound
    -- identity before plate handoffs so a newly readable GUID is respected.
    -- No position is inferred; sparkles still require a real native plate.
    if softKind then publish("softinteract", softName, softKind) end
    for _, plate in pairs(plates) do
        if not (issecretvalue and issecretvalue(plate)) and (type(plate) == "table" or type(plate) == "userdata") then
            local unit = plateUnit(plate)
            local current = unit and call(nativePlates.GetNamePlateForUnit, unit)
            if not (issecretvalue and issecretvalue(current)) and current and current == plate then
                local kind, name = eligible(unit, ranks)
                if kind then
                    showEffect(plate, unit, kind, scale)
                    publish(unit, name, kind, softName == name and soundUnits.softinteract or nil)
                    seen[plate], count = true, count + 1
                end
            end
        end
    end
    for plate, effect in pairs(effects) do if not seen[plate] then hideEffect(effect) end end
    ns.gatherSparkleCount = count
    ns.gatherNearbyCount = #nearby
    ns.gatherNearbyResources = nearby
    ns.gatherSparkleState = platesReady and "enabled" or "nearby-only"
end

function ns.CreateGatherSparkles()
    if initialized then return end
    initialized = true
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SKILL_LINES_CHANGED",
        "PLAYER_LOGOUT", "CVAR_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then ns.gatherSoundWorldPaused = true
        elseif event == "PLAYER_ENTERING_WORLD" then ns.gatherSoundWorldPaused = false end
        if event == "PLAYER_LOGOUT" then
            loggingOut = true
            hideAll()
            if supported() and not inCombat() then
                local get, set = cvarAPI()
                if get then restoreCVars(get, set) end
            end
            return
        end
        if event == "NAME_PLATE_UNIT_REMOVED" and plain(unit, "string") then
            local plate = unitPlates[unit]
            if plate and effects[plate] then hideEffect(effects[plate]) end
            ns.gatherNearbyResources = nil
        elseif event == "PLAYER_LEAVING_WORLD" then
            hideAll()
        elseif event == "PLAYER_REGEN_DISABLED" then
            ns.gatherSparkleState = "combat"
            hideAll()
        elseif event == "CVAR_UPDATE" and not writing and not loggingOut then
            local get = cvarAPI()
            if get then checkOverrides(get) end
        end
        pending = true
    end)
    local elapsedSinceRefresh = 0
    events:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceRefresh = elapsedSinceRefresh + elapsed
        if not pending and elapsedSinceRefresh < 0.2 then return end
        pending, elapsedSinceRefresh = false, 0
        ns.RefreshGatherSparkles()
    end)
    if type(hooksecurefunc) == "function" and NamePlateDriverFrame then
        for _, method in ipairs({ "OnNamePlateAdded", "OnSoftTargetUpdate" }) do
            if type(NamePlateDriverFrame[method]) == "function" then
                pcall(hooksecurefunc, NamePlateDriverFrame, method, function() pending = true end)
            end
        end
    end
    ns.RefreshGatherSparkles()
end

function ns.SparkleCommand(argument)
    local command, value = (argument or ""):match("^%s*(%S*)%s*(.-)%s*$")
    if command == "on" or command == "off" then
        ns.db.gatherSparkles = command == "on"
    elseif command == "scale" then
        local scale = tonumber(value)
        if not number(scale) or scale < 0.6 or scale > 1.6 then
            ns.Print("/myprof sparkle scale 1.2（范围 0.6–1.6）")
            return
        end
        ns.db.gatherSparkleScale = scale
    end
    ns.RefreshGatherSparkles()
    ns.Print("附近矿草闪光" .. (ns.db.gatherSparkles and "已开启" or "已关闭") .. "，当前闪光 " .. tostring(ns.gatherSparkleCount or 0) .. " 处。")
    if ns.gatherSparkleState == "unsupported" then ns.Print("当前客户端缺少原生资源识别接口。") end
    if command == "status" then
        ns.Print("近距离识别 " .. tostring(ns.gatherNearbyCount or 0) .. " 种资源；文字和声音不要求资源姓名板。")
        ns.Print("附近采集声音" .. (ns.db.gatherSparkles and ns.db.gatherAlerts and ns.db.gatherSound and "已开启" or "已关闭")
            .. "，本次会话播放成功 " .. tostring(ns.gatherSparkleSoundCount or 0) .. " 次。")
    end
    ns.Print("/myprof sparkle on / off · scale 1.2 · status")
end
