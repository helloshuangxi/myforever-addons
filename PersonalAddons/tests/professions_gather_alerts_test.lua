-- Exercise the alert controller with simulated completed scans and WoW frames.
local base = "_forever_/Interface/AddOns/MyForeverProfessions/"
local ns = {}
for _, file in ipairs({"Core", "API", "GatherResources"}) do
    assert(loadfile(base .. file .. ".lua"))("MyForeverProfessions", ns)
end

local frames, methods = {}, {}
local function frame()
    return setmetatable({ scripts = {}, children = {} }, { __index = methods })
end
UIParent = frame()
UIParent.width, UIParent.height, UIParent.scale = 1400, 900, 0.8
function CreateFrame(frameType, _, parent)
    local created = frame()
    created.parent = parent
    created.shown = true
    created.mouse = frameType == "Button"
    frames[#frames + 1] = created
    return created
end
function methods:CreateTexture()
    local child = frame()
    self.children[#self.children + 1] = child
    return child
end
methods.CreateFontString = methods.CreateTexture
function methods:SetScript(event, script) self.scripts[event] = script end
function methods:Show()
    if self.forbidShow then self.forbiddenShows = (self.forbiddenShows or 0) + 1; error("direction arrow must stay hidden") end
    self.shown = true
end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown == true end
function methods:SetText(value) self.text = value end
function methods:SetRotation(value) self.rotation = value end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return unpack(self.point) end
function methods:ClearAllPoints() self.point = nil end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(value) self.scale = value end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale()
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
local function anchorFraction(point, low, high)
    if point:find(low, 1, true) then return 0 end
    if point:find(high, 1, true) then return 1 end
    return 0.5
end
local function leftBottom(self)
    if self == UIParent then return 0, 0 end
    local point, relative, relativePoint, x, y = self:GetPoint()
    local relativeLeft, relativeBottom = leftBottom(relative)
    local ratio = relative:GetEffectiveScale() / self:GetEffectiveScale()
    local left = (relativeLeft + relative.width * anchorFraction(relativePoint, "LEFT", "RIGHT")) * ratio
        + x - self.width * anchorFraction(point, "LEFT", "RIGHT")
    local bottom = (relativeBottom + relative.height * anchorFraction(relativePoint, "BOTTOM", "TOP")) * ratio
        + y - self.height * anchorFraction(point, "BOTTOM", "TOP")
    return left, bottom
end
function methods:GetLeft() local left = leftBottom(self); return left end
function methods:GetBottom() local _, bottom = leftBottom(self); return bottom end
function methods:GetTop() return self:GetBottom() + self.height end
function methods:EnableMouse(enabled) self.mouse = enabled end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:SetNormalTexture(texture) self.normal = texture end
function methods:SetHighlightTexture() self.highlight = frame() end
function methods:GetHighlightTexture() return self.highlight end
for _, method in ipairs({"SetFrameStrata", "SetClampedToScreen", "SetMovable", "RegisterForDrag",
    "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetTexture", "RegisterEvent", "SetTextColor", "SetVertexColor", "SetWidth",
    "SetJustifyH", "SetWordWrap"}) do
    methods[method] = function() end
end

local now, soundCount, scans, facingReads, positionScans, resets = 0, 0, 0, 0, 0, 0
local supported, tracking, combat, mouseHeld = true, true, false, false
local cursorX, cursorY = 0, 0
local dots, hints = {}, {}
local mapVisible, dead = true, false
local affectingCombat = false
GetTime = function() return now end
GetPlayerFacing = function() facingReads = facingReads + 1; error("names-only HUD must not request player facing") end
InCombatLockdown = function() return combat end
UnitIsDeadOrGhost = function() return dead end
UnitAffectingCombat = function() return affectingCombat end
issecretvalue = function(value) return value == "SECRET" end
GetCursorPosition = function() return cursorX, cursorY end
IsMouseButtonDown = function(button) assert(button == "LeftButton"); return mouseHeld end
Minimap = { IsVisible = function() return mapVisible end }
PlaySound = function(kit) assert(kit == 3175); soundCount = soundCount + 1; return true, soundCount end
C_Minimap = {
    GetNumTrackingTypes = function() return 1 end,
    GetTrackingInfo = function() return { active = tracking } end,
    GetTrackingFilter = function() return { spellID = 2580 } end,
}
ns.GatherScan = {
    IsSupported = function() return supported end,
    ScanNames = function() scans = scans + 1; return dots, hints end,
    Scan = function() positionScans = positionScans + 1; error("names-only HUD must not use positional scanning") end,
    Reset = function() resets = resets + 1 end,
}
ns.db = ns.NormalizeDB({})
ns.detectReady = true
ns.professions = {{ id = 186, rank = 3, modifier = 0 }}
ns.Print = function() end
assert(loadfile(base .. "GatherAlerts.lua"))("MyForeverProfessions", ns)
ns.CreateGatherAlerts()

local hud, done, grip, ticker = unpack(frames)
local arrow, title, detail = unpack(hud.children)
arrow.forbidShow = true
local function nameOnly(name)
    return setmetatable({name = name}, {__index = function(_, key)
        if key == "dx" or key == "dy" or key == "facing" or key == "bearing" then
            error("names-only result has no position: " .. key)
        end
    end})
end
local function tick(seconds)
    now = now + (seconds or 0.2)
    ticker.scripts.OnUpdate(ticker, seconds or 0.2)
end
local function near(a, b) return math.abs(a - b) < 0.0001 end
local function topLeftPixels()
    local scale = hud:GetEffectiveScale()
    return hud:GetLeft() * scale, hud:GetTop() * scale
end
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
check(hud.scale == 1 and hud.point[1] == "CENTER" and hud.point[5] == 170,
    "old saves keep the original alert placement and size")
dots = {
    nameOnly("铜矿石"), -- Item text, no live vein of this name.
    nameOnly("锡矿脉"), -- Rank 65 required.
    nameOnly("宁神花"), -- Unlearned profession.
    nameOnly("铜矿脉"),
}
tick()
check(hud.shown and title.text == "附近有 铜矿脉" and detail.text == "小地图范围内")
check(not arrow.shown and soundCount == 1, "confirmed names show text and sound without an arrow")
local beforeSameTracking = resets
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
check(resets == beforeSameTracking and hud.shown,
    "unchanged gathering filters do not starve scans or clear a fresh notice")
dots = nil
tick()
check(hud.shown and detail.text == "小地图范围内" and soundCount == 1, "incomplete pass retains fresh name without a repeated sound")
dots = {nameOnly("铜矿脉")}
tick()
check(detail.text == "小地图范围内" and facingReads == 0 and positionScans == 0,
    "names-only scans never request positions or facing")
combat = true
local previous = scans
tick()
check(not hud.shown and scans == previous, "combat suspends scans")
combat = false
tracking = false
local beforeChangedTracking = resets
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
check(resets == beforeChangedTracking + 1,
    "a real gathering filter change resets the active source")
tick()
check(not hud.shown and scans == previous, "inactive resource tracking suspends scans")
tracking = true
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
dots = {}
tick(11)
check(not hud.shown and soundCount == 1, "a complete empty scan removes the HUD")
dots = {nameOnly("铜矿脉")}
tick()
check(hud.shown and soundCount == 2, "a reappearing eligible target can sound again")

check(hud.mouse and grip.mouse and grip:IsShown() and grip.normal and not done.shown and not hud.scripts.OnMouseWheel,
    "live alerts expose direct move and resize without adjustment mode or Ctrl-wheel")
hud.scripts.OnDragStart(hud)
check(hud.moving, "dragging starts directly on a live alert")
hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -125, -80)
hud.scripts.OnDragStop(hud)
check(not hud.moving and ns.db.gatherPoint == "TOPRIGHT" and ns.db.gatherRelativePoint == "TOPRIGHT"
    and ns.db.gatherX == -125 and ns.db.gatherY == -80, "live dragging saves the new anchor")

local left, top = topLeftPixels()
local scale = hud:GetEffectiveScale()
cursorX = left + hud:GetWidth() * scale - 4
cursorY = top - hud:GetHeight() * scale + 4
mouseHeld = true
grip.scripts.OnDragStart(grip)
cursorX = cursorX + 24.4 * UIParent:GetEffectiveScale()
cursorY = cursorY - 5.8 * UIParent:GetEffectiveScale()
tick()
local resizedLeft, resizedTop = topLeftPixels()
check(near(hud.scale, 1.1) and near(resizedLeft, left) and near(resizedTop, top),
    "live resize grows proportionally around a fixed physical top-left")
check(hud.shown and title.text == "附近有 铜矿脉" and detail.text == "小地图范围内" and soundCount == 2,
    "sizing does not replace a live alert with a preview or trigger a sound")
cursorX = cursorX + 300
cursorY = cursorY - 300
tick()
check(hud.scale == 1.3, "dragging cannot exceed 130 percent")
cursorX = cursorX - 600
cursorY = cursorY + 600
tick()
check(hud.scale == 0.7, "dragging cannot go below 70 percent")
grip.scripts.OnDragStop(grip)
mouseHeld = false
local saved = ns.NormalizeDB(ns.db)
check(saved.gatherPoint == "TOPLEFT" and saved.gatherRelativePoint == "BOTTOMLEFT"
    and near(saved.gatherX * UIParent:GetEffectiveScale(), left)
    and near(saved.gatherY * UIParent:GetEffectiveScale(), top) and saved.gatherScale == 0.7,
    "release saves the resized alert's physical anchor and scale in UIParent units")

local beforeInteraction = scans
mouseHeld = true
hud.scripts.OnDragStart(hud)
tick(5)
check(hud.moving and scans == beforeInteraction, "holding the drag keeps the live alert stable")
mouseHeld = false
tick()
check(not hud.moving and scans > beforeInteraction and title.text == "附近有 铜矿脉",
    "a missed body drag-stop event is recovered after the mouse is released")

beforeInteraction = scans
mouseHeld = true
cursorX, cursorY = 0, 0
grip.scripts.OnDragStart(grip)
cursorX = 24.4 * UIParent:GetEffectiveScale()
cursorY = -5.8 * UIParent:GetEffectiveScale()
tick()
check(scans == beforeInteraction, "resizing remains paused while the button is held")
local duringResize = hud.scale
mouseHeld = false
tick()
check(scans > beforeInteraction and hud.shown and hud.scale == duringResize and title.text == "附近有 铜矿脉",
    "a missed grip drag-stop event finalizes the size and resumes resource scans")

mouseHeld = true
hud.scripts.OnDragStart(hud)
mouseHeld = false
hud.scripts.OnMouseUp(hud, "LeftButton")
check(not hud.moving, "body mouse-up also ends moving")
beforeInteraction = scans
mouseHeld = true
grip.scripts.OnDragStart(grip)
local beforeMouseUp = hud.scale
cursorX = cursorX + 12.2 * UIParent:GetEffectiveScale()
cursorY = cursorY - 2.9 * UIParent:GetEffectiveScale()
mouseHeld = false
grip.scripts.OnMouseUp(grip, "LeftButton")
check(near(hud.scale, beforeMouseUp + 0.05), "mouse-up saves the final cursor position before the next update")
tick()
check(scans > beforeInteraction, "grip mouse-up also allows scanning to resume")

mouseHeld = true
grip.scripts.OnDragStart(grip)
hud:Hide()
mouseHeld = false
beforeInteraction = scans
tick()
check(scans > beforeInteraction and hud.shown and title.text == "附近有 铜矿脉",
    "hiding the HUD during resize clears interaction state before the next resource scan")

ns.GatherCommand("mute")
ns.GatherCommand("test")
check(hud.shown and title.text == "附近有 铜矿（测试）" and not arrow.shown and soundCount == 2,
    "test preview is names-only and respects mute")
ns.GatherCommand("off")
tick()
check(not hud.shown and ns.NormalizeDB(ns.db).gatherAlerts == false and ns.NormalizeDB(ns.db).gatherSound == false)
supported = false
ns.GatherCommand("on")
previous = scans
tick()
check(not hud.shown and scans == previous, "unsupported clients do not scan")

ns.GatherCommand("move")
check(hud.shown and hud.mouse and grip:IsShown() and done.shown and title.text == "调整采集提示" and not arrow.shown,
    "adjustment preview is interactive without a resource or supported scanner")
tick(10)
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
check(hud.shown and scans == previous and soundCount == 2, "adjustment stays visible and quiet through tracking events")
supported = true
previous = scans
tick()
check(scans > previous and hud.shown and done.shown and title.text == "附近有 铜矿脉",
    "an open preview keeps scanning and shows a real nearby vein")
dots = {}
tick()
check(hud.shown and done.shown and title.text == "调整采集提示",
    "an empty live scan returns to the preview placeholder")
tracking = false
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
previous = scans
tick()
check(hud.shown and scans == previous and title.text == "调整采集提示",
    "the preview stays available when gathering tracking is disabled")
tracking = true
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
done.scripts.OnClick(done)
check(not hud.shown and not done.shown, "completing adjustment closes the preview")
ns.GatherCommand("move")
ns.GatherCommand("move")
check(not hud.shown, "the command can also close adjustment")

-- The manual preview keeps working with automatic notices off. It still
-- observes mute, the shared playback interval, and the live player state.
ns.GatherCommand("unmute")
ns.GatherCommand("off")
now = now + 5
ns.GatherCommand("test")
check(soundCount == 3, "manual sound preview remains available with automatic alerts off")
ns.GatherCommand("mute")
now = now + 5
ns.GatherCommand("test")
check(soundCount == 3, "manual preview still respects mute")
ns.GatherCommand("unmute")
ns.GatherCommand("on")
tick(6)
dots = {nameOnly("铜矿脉")}
check(ns.PlayGatherNotice("铜矿脉", "nearby"), "nearby source can first claim the common sound")
local sharedCount = soundCount
tick()
check(soundCount == sharedCount, "real minimap controller does not duplicate a nearby-source notice")
tick(5)
check(soundCount == sharedCount, "minimap does not defer a duplicate until the shared cooldown ends")

dots = {}
tick(11)
local attempts, shouldFail = 0, true
PlaySound = function()
    attempts = attempts + 1
    if shouldFail then return false end
    soundCount = soundCount + 1
    return true
end
dots = {nameOnly("铜矿脉")}
tick()
tick()
check(attempts == 1, "minimap failed playback is rate-limited too")
shouldFail = false
tick(4)
check(attempts == 2 and soundCount == sharedCount + 1, "minimap failure does not consume the announcement")
ticker.scripts.OnEvent(ticker, "PLAYER_LEAVING_WORLD")
local beforeLeaving = soundCount
now = now + 5
check(not ns.PlayGatherNotice("锡矿脉", "nearby") and soundCount == beforeLeaving,
    "shared playback pauses after leaving the world")
-- Rejected positional/old-tooltip hints are deliberately not a source. A
-- completed names-only pass and a fresh native nearby snapshot are sources.
ticker.scripts.OnEvent(ticker, "PLAYER_ENTERING_WORLD")
ns.db.gatherAlerts, ns.db.gatherSound, ns.db.gatherSparkles = true, true, true
supported, tracking, mapVisible, combat, dead = true, true, true, false, false
hints, dots = {{name = "铜矿脉"}}, {}
local noHintSound = soundCount
tick(11)
check(not hud.shown and not arrow.shown, "rejected old tooltip hints never produce a nearby notice")
check(soundCount == noHintSound, "rejected tooltip text does not sound")
tick(11)
check(not hud.shown and soundCount == noHintSound, "repeated rejected hints remain invisible and silent")

ns.gatherNearbyResources = {{name = "铜矿脉", kind = "mining", seenAt = now}}
tick()
check(hud.shown and title.text == "附近有 铜矿脉" and detail.text == "就在附近" and not arrow.shown,
    "a confirmed native nearby resource supplies text independently")
check(soundCount == noHintSound, "the HUD does not duplicate the nearby detector's own sound")
supported, tracking, mapVisible = false, false, false
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
ns.gatherNearbyResources[1].seenAt = now
tick()
check(hud.shown and title.text == "附近有 铜矿脉" and detail.text == "就在附近",
    "nearby text works without a scanner, tracking, a visible minimap or facing")
tick(1)
check(not hud.shown, "a stalled producer cannot leave a stale nearby resource on screen")
ns.gatherNearbyResources = {{name = "锡矿脉", seenAt = now}, {name = "宁神花", seenAt = now}}
tick()
check(not hud.shown, "nearby text is independently filtered by learned skill and resource threshold")
ns.gatherNearbyResources = {{name = "铜矿脉", seenAt = now}}
ns.db.gatherSparkles = false
tick()
check(not hud.shown, "turning off the nearby source drops its cached HUD immediately")
ns.db.gatherSparkles = true
ns.gatherNearbyResources[1].seenAt = now
ns.GatherCommand("off")
tick()
check(not hud.shown, "the master switch suppresses the nearby HUD too")
ns.GatherCommand("on")
ns.gatherNearbyResources[1].seenAt = now
combat = true
tick()
check(not hud.shown, "combat suppresses the nearby HUD")
combat, dead = false, true
ns.gatherNearbyResources[1].seenAt = now
tick()
check(not hud.shown, "death suppresses the nearby HUD")
dead = false
ns.gatherNearbyResources[1].seenAt = now
ticker.scripts.OnEvent(ticker, "PLAYER_LEAVING_WORLD")
tick()
check(not hud.shown and ns.gatherNearbyResources == nil, "leaving the world clears the nearby snapshot")
ticker.scripts.OnEvent(ticker, "PLAYER_ENTERING_WORLD")
supported, tracking, mapVisible = true, true, true
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
ns.gatherNearbyResources = {{name = "铜矿脉", seenAt = now}}
dots, hints = {nameOnly("铜矿脉")}, {{name = "铜矿脉"}}
tick(5)
check(hud.shown and title.text == "附近有 铜矿脉" and detail.text == "小地图范围内" and not arrow.shown,
    "confirmed names replace expired nearby evidence without any navigation")
check(soundCount == noHintSound + 1, "rejected hints did not consume a later confirmed-name announcement")
ns.gatherNearbyResources[1].seenAt = now
tick()
check(detail.text == "就在附近" and not arrow.shown, "fresh nearby evidence takes priority over minimap names")
ns.gatherNearbyResources[1].seenAt = now
dots = {}
tick()
check(hud.shown and detail.text == "就在附近", "empty minimap scan does not erase independent nearby evidence")
ns.gatherNearbyResources = nil
tick()
check(not hud.shown, "empty completed scan clears the HUD after nearby evidence disappears")

dots = {nameOnly("铜矿脉")}
tick()
dots, hints = nil, nil
tick(3.4)
check(hud.shown and detail.text == "小地图范围内", "unfinished pass retains a confirmed name for up to 3.5 seconds")
tick(.2)
check(not hud.shown, "unfinished pass cannot renew an expired 3.5-second name")
dots = {nameOnly("铜矿脉")}
tick()
dots = nil
tick()
check(hud.shown, "nil result means unfinished rather than empty")
dots, hints = {}, {{name = "铜矿脉"}}
tick()
check(not hud.shown, "empty result clears a fresh cache immediately and ignores rejected hints")
dots = {nameOnly("锡矿脉"), nameOnly("宁神花"), nameOnly("陌生矿点"), nameOnly("铜矿石")}
tick()
check(not hud.shown, "names must be known resources with a learned profession and sufficient rank")
dots, hints = {nameOnly("铜矿脉")}, {{name = "铜矿脉"}}
ns.GatherCommand("mute")
tick()
check(hud.shown and title.text == "附近有 铜矿脉", "mute leaves confirmed names visible")
ns.GatherCommand("off")
tick()
check(not hud.shown, "the master switch suppresses confirmed-name notices")

-- Restricted player-state results fail closed rather than being coerced.
ns.GatherCommand("on")
dots, hints = {nameOnly("铜矿脉")}, nil
affectingCombat = "SECRET"
local beforeSecretScans = scans
tick()
check(not hud.shown and scans == beforeSecretScans,
    "a restricted combat result pauses the HUD and scan safely")
affectingCombat, dead = false, "SECRET"
tick()
check(not hud.shown and scans == beforeSecretScans,
    "a restricted death result also pauses the HUD safely")
dead, combat = false, "SECRET"
tick()
check(not hud.shown and scans == beforeSecretScans,
    "a restricted lockdown result also pauses the HUD safely")
combat = false
tick()
check(hud.shown and title.text == "附近有 铜矿脉", "plain live player state resumes confirmed names")
-- Pending scans must not keep information for a profession that was removed.
dots = nil
ns.professions = {{id = 186, rank = 0, modifier = 0}}
tick()
check(not hud.shown, "cached names are revalidated against the current profession rank")
ns.professions = {{id = 186, rank = 3, modifier = 0}}
dots = {nameOnly("铜矿脉")}
tick()
dots = nil
ns.professions = {{id = 182, rank = 1, modifier = 0}}
tick()
check(not hud.shown, "cached names are revalidated after the gathering profession changes")
check(facingReads == 0 and positionScans == 0, "entire controller lifecycle never reads facing or requests positional scans")
check(not arrow.shown and not arrow.forbiddenShows and arrow.rotation == nil,
    "live, preview, resize, event and empty-result paths never display or rotate the arrow")
ns.db.gatherAlerts, ns.db.gatherSound, ns.db.gatherSparkles = true, true, true
local beforeDebugScans, beforeDebugSounds = scans, soundCount
ns.GatherScan.ScanDiagnostics = function()
    return {state = "scanning", sampleCount = 120, rawKnownNames = {"铜矿"},
        acceptedNames = {}, rejectedKnownNames = {"铜矿"}}
end
ns.GatherCommand("debug")
check(ns.db.gatherAlerts and ns.db.gatherSound and ns.db.gatherSparkles
    and scans == beforeDebugScans and soundCount == beforeDebugSounds,
    "reading diagnostics leaves every notice enabled without scanning or sounding")
local beforeModeScans, beforeModeSounds, beforeModeResets = scans, soundCount, resets
ns.GatherCommand("original")
check(ns.db.gatherMethod == "original" and resets > beforeModeResets,
    "original-reader command resets a pending experiment before changing sources")
ns.GatherCommand("cursor")
check(ns.db.gatherMethod == "cursor" and not hud.shown,
    "experiment command clears the previous source target without a preview")
check(ns.db.gatherAlerts and ns.db.gatherSound and ns.db.gatherSparkles
    and scans == beforeModeScans and soundCount == beforeModeSounds,
    "source switching preserves notice settings and never simulates a discovery")

-- A disabled native filter must explain a zero-read session without pretending
-- that a resource was found, playing a sound, or changing the native filter.
local oldPrint, printed = ns.Print, {}
ns.Print = function(message) printed[#printed + 1] = message end
local function hintCount()
    local count = 0
    for _, message in ipairs(printed) do
        if message:find("小地图检测暂停", 1, true) then count = count + 1 end
    end
    return count
end
ns.professions = {{id = 186, rank = 3, modifier = 0}}
ns.gatherNearbyResources = nil
tracking, dots = false, {nameOnly("铜矿脉")}
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
local pausedScans, pausedSounds = scans, soundCount
tick()
check(ns.gatherTrackingHint and ns.gatherTrackingHint:find("寻找矿物", 1, true)
    and hintCount() == 1, "a known inactive mining filter explains why the scanner is paused")
check(scans == pausedScans and soundCount == pausedSounds and not hud.shown,
    "tracking instructions do not simulate an ore notice or change the filter")
tick()
check(hintCount() == 1, "unchanged inactive tracking does not spam the chat each poll")
ns.GatherCommand("debug")
check(hintCount() == 2 and scans == pausedScans and soundCount == pausedSounds,
    "explicit diagnostics repeat the tracking reason without sampling or sounding")
tracking = true
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
tick()
check(ns.gatherTrackingHint == nil and scans > pausedScans,
    "enabling native tracking clears the hint and resumes real scans")
tracking = false
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
ns.detectReady = false
tick()
check(ns.gatherTrackingHint == nil and hintCount() == 2,
    "unresolved profession data does not claim that a known filter is disabled")
ns.detectReady = true
tick()
check(hintCount() == 3, "a newly confirmed disabled filter can issue one instruction")
combat = true
tick()
check(ns.gatherTrackingHint == nil and hintCount() == 3,
    "combat hides tracking instructions without adding another warning")
combat = false
tick()
check(ns.gatherTrackingHint ~= nil and hintCount() == 3,
    "combat ending does not repeat an unchanged disabled-filter warning")
ns.gatherSoundWorldPaused = true
tick()
check(ns.gatherTrackingHint == nil and hintCount() == 3,
    "world suspension also remains quiet")
ns.gatherSoundWorldPaused = false
tick()
check(ns.gatherTrackingHint ~= nil and hintCount() == 3,
    "world resumption preserves the disabled-filter warning deduplication")
ns.GatherCommand("off")
tick()
check(ns.gatherTrackingHint == nil and hintCount() == 3,
    "disabled addon notices clear tracking instructions and remain quiet")
ns.Print = oldPrint

-- A compact native sample may contain several eligible names. Exercise the
-- real HUD and playback service, without inspecting their private dedup tables.
ns.db.gatherAlerts, ns.db.gatherSound, ns.db.gatherSparkles = true, true, true
ns.professions = {{id=186,rank=75,modifier=0},{id=182,rank=150,modifier=0}}
ns.gatherNearbyResources = nil
tracking, supported, mapVisible = true, true, true
ticker.scripts.OnEvent(ticker,"MINIMAP_UPDATE_TRACKING")
dots, hints = {}, nil
tick(11)
local aggregateSounds = soundCount
dots = {nameOnly("铜矿"),nameOnly("锡矿")}
tick()
check(title.text=="附近有 铜矿" and detail.text=="小地图范围内" and soundCount==aggregateSounds+1,
    "first aggregate receipt shows and sounds one eligible ore")
tick()
check(title.text=="附近有 锡矿" and hud.shown and soundCount==aggregateSounds+1,
    "unannounced second ore remains visible during the shared sound cooldown")
check(ns.gatherAlertSoundResult=="cooldown",
    "cooldown does not falsely mark a successful second-ore announcement")
tick(4.1)
check(title.text=="附近有 锡矿" and soundCount==aggregateSounds+2 and ns.gatherAlertSoundResult=="played",
    "third fresh aggregate receipt can successfully announce the second ore")
tick(4.1)
check(title.text=="附近有 铜矿" and soundCount==aggregateSounds+2,
    "once both aggregate names were announced, repeated fresh receipts stay silent")
dots={nameOnly("锡矿")}
tick(4.1)
check(title.text=="附近有 锡矿" and soundCount==aggregateSounds+2,
    "the second ore also remains deduplicated when it is the only fresh name")

-- The character knows herbalism here, but the only active native tracking
-- entry is mining. Eligibility is applied before choosing an aggregate name.
local eligibleSounds=soundCount
dots={nameOnly("金矿脉")}
tick()
check(not hud.shown and soundCount==eligibleSounds,
    "an ore above the current mining rank cannot become the aggregate target")
dots={nameOnly("宁神花")}
tick()
check(not hud.shown and soundCount==eligibleSounds,
    "learned and sufficient herbalism still requires herb tracking for minimap names")
dots={nameOnly("金矿脉"),nameOnly("宁神花"),nameOnly("铜矿")}
tick()
check(hud.shown and title.text=="附近有 铜矿",
    "ineligible aggregate names never displace a currently eligible name")

-- An unannounced name blocked by cooldown must disappear with its receipt.
-- There is no later queue to fill from that earlier aggregate.
dots={}
tick(11)
local beforeDisappearance=soundCount
dots={nameOnly("铜矿"),nameOnly("锡矿")}
tick()
tick()
check(title.text=="附近有 锡矿" and soundCount==beforeDisappearance+1,
    "disappearance regression begins with a visible but not-yet-sounded second ore")
dots={nameOnly("铜矿")}
tick(4.1)
check(title.text=="附近有 铜矿" and soundCount==beforeDisappearance+1,
    "a missing second ore is never announced or rendered from an old aggregate")
dots={}
tick()
check(not hud.shown and soundCount==beforeDisappearance+1,
    "empty fresh receipt does not drain a historical name queue")

-- A stalled source returns nil, so no empty result visits minimapTarget while
-- the announcement ages. Expiry must happen before the reappearance renews it.
dots={nameOnly("铜矿")}
tick()
local beforeQuietReturn=soundCount
dots=nil
tick(11)
check(not hud.shown and soundCount==beforeQuietReturn,
    "a long period without new receipts stays quiet and lets the old HUD expire")
dots={nameOnly("铜矿")}
tick()
check(hud.shown and title.text=="附近有 铜矿" and soundCount==beforeQuietReturn+1
    and ns.gatherAlertSoundResult=="played",
    "same ore with a fresh receipt after long silence can be announced again")
tick()
check(soundCount==beforeQuietReturn+1,
    "reappearance renews normal deduplication instead of sounding every fresh poll")
check(facingReads==0 and positionScans==0 and not arrow.shown and not arrow.forbiddenShows,
    "aggregate selection and reappearance never introduce resource navigation")

-- A runtime restriction can be discovered inside a poll. Even if an old
-- source returns a receipt in that call, it must not keep the minimap HUD or
-- sound alive. Only the minimap detector is suspended, not user settings.
local restrictionMessages = {}
local savedPrint, savedNames = ns.Print, ns.GatherScan.ScanNames
ns.Print = function(message) restrictionMessages[#restrictionMessages + 1] = message end
ns.gatherNearbyResources = nil
ns.GatherScan.ScanNames = function()
    scans = scans + 1
    ns.gatherMinimapAccessRestricted = true
    ns.gatherMinimapRestrictionReason = "restricted-text"
    return {nameOnly("铜矿")}
end
local restrictionSounds = soundCount
tick()
check(not hud.shown and ns.gatherAlertLabel == nil and ns.gatherScanCount == 0,
    "same-poll restricted receipt immediately clears the old minimap HUD")
check(soundCount == restrictionSounds and ns.db.gatherAlerts and ns.db.gatherSound and ns.db.gatherSparkles,
    "restriction neither sounds a stale receipt nor changes any notice setting")
local function restrictionHintCount()
    local count = 0
    for _, message in ipairs(restrictionMessages) do
        if message:find("客户端限制了小地图", 1, true) then count = count + 1 end
    end
    return count
end
check(restrictionHintCount() == 1 and ns.gatherCapabilityHint,
    "new restriction gives one bounded explanation")
local restrictedScans = scans
for _=1,20 do tick() end
check(scans == restrictedScans and restrictionHintCount() == 1,
    "restricted minimap is not polled repeatedly or reported as a new failure each frame")
ns.GatherCommand("original")
tick()
check(scans == restrictedScans and ns.gatherMinimapAccessRestricted == true,
    "switching sources cannot bypass the shared restriction")
ns.GatherCommand("debug")
check(restrictionHintCount() == 3 and scans == restrictedScans,
    "explicit source status and diagnostics explain the restriction without scanning")
tracking = false
ticker.scripts.OnEvent(ticker,"MINIMAP_UPDATE_TRACKING"); tick()
check(ns.gatherTrackingHint == nil and scans == restrictedScans,
    "restricted capability does not suggest that enabling tracking would restore unavailable names")
tracking = true
ticker.scripts.OnEvent(ticker,"MINIMAP_UPDATE_TRACKING")

-- The fresh nearby feed and shared playback service remain usable. The feed
-- still expires rather than becoming a substitute for minimap coverage.
tick(11)
ns.gatherNearbyResources = {{name="银矿",seenAt=now}}
tick()
check(hud.shown and title.text == "附近有 银矿" and detail.text == "就在附近",
    "a fresh nearby resource is shown with nearby scope while minimap access is blocked")
local nearbyHeard, nearbyResult = ns.PlayGatherNotice("银矿", "nearby")
check(nearbyHeard and nearbyResult == "played" and soundCount == restrictionSounds + 1,
    "restricted minimap does not mute a confirmed nearby resource notice")
tick(.7)
check(not hud.shown and scans == restrictedScans,
    "nearby evidence expires normally with no historical minimap fallback")
ns.GatherCommand("off"); tick(); ns.GatherCommand("on"); tick()
check(restrictionHintCount() == 5 and not hud.shown and ns.db.gatherSound and ns.db.gatherSparkles,
    "explicit off/on preserves sound and sparkle settings without automatic warning spam")

-- Tracking can also contain restricted values on a newer client. Never
-- dereference a restricted container or claim its unknown filter is off.
local oldInfo, oldFilter, oldCount, oldSecret = C_Minimap.GetTrackingInfo,
    C_Minimap.GetTrackingFilter, C_Minimap.GetNumTrackingTypes, issecretvalue
local opaque = setmetatable({}, {
    __index=function() error("restricted tracking container dereferenced") end,
    __tostring=function() error("restricted tracking value formatted") end,
})
issecretvalue = function(value) return rawequal(value,opaque) or oldSecret(value) end
local cases = {
    {info=opaque},
    {info={active=opaque,spellID=2580}},
    {info={active=true,spellID=opaque}},
    {info={active=true},filter=opaque},
    {info={active=true},filter={spellID=opaque}},
    {info={active=true,name=opaque}},
}
for index, case in ipairs(cases) do
    C_Minimap.GetTrackingInfo = function() return case.info end
    C_Minimap.GetTrackingFilter = function() return case.filter end
    local ok = pcall(ticker.scripts.OnEvent,ticker,"MINIMAP_UPDATE_TRACKING")
    if ok then ok = pcall(tick) end
    check(ok and ns.gatherTrackingHint == nil and scans == restrictedScans,
        "restricted tracking case "..index.." stays unknown without parsing, warning or scan")
end
C_Minimap.GetNumTrackingTypes = function() return opaque end
C_Minimap.GetTrackingInfo = function() error("restricted tracking count must not enter enumeration") end
local countOK = pcall(ticker.scripts.OnEvent,ticker,"MINIMAP_UPDATE_TRACKING")
check(countOK,"restricted tracking count does not enter enumeration")
C_Minimap.GetTrackingInfo, C_Minimap.GetTrackingFilter, C_Minimap.GetNumTrackingTypes = oldInfo,oldFilter,oldCount
issecretvalue, ns.Print, ns.GatherScan.ScanNames = oldSecret,savedPrint,savedNames
check(facingReads==0 and positionScans==0 and not arrow.shown and not arrow.forbiddenShows,
    "restriction fallback does not introduce navigation or resource position reads")

print("Gather alert integration: " .. checks .. " checks passed")
