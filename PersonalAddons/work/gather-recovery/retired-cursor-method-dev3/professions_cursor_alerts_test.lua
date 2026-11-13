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
function methods:Show() self.shown = true end
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

local now, facing, soundCount, scans, facingReads = 0, 0, 0, 0, 0
local supported, tracking, combat, mouseHeld = true, true, false, false
local cursorX, cursorY = 0, 0
local dots, hints = {}, {}
local mapVisible, dead = true, false
local affectingCombat = false
GetTime = function() return now end
GetPlayerFacing = function() facingReads = facingReads + 1; return facing end
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
    Scan = function() scans = scans + 1; return dots, hints end,
    Reset = function() end,
}
ns.db = ns.NormalizeDB({})
ns.detectReady = true
ns.professions = {{ id = 186, rank = 3, modifier = 0 }}
ns.Print = function() end
local cursorResources, cursorEnabled, cursorResets = {}, nil, 0
local ownTrackingUpdate = false
ns.GatherCursorScan = {
    IsSupported = function() return true end,
    Poll = function(enabled) cursorEnabled = enabled; return enabled and cursorResources or {} end,
    Reset = function() cursorResets = cursorResets + 1; cursorResources = {} end,
    IsActive = function() return false end,
    IsOwnTrackingUpdate = function() return ownTrackingUpdate end,
}
assert(loadfile(base .. "GatherAlerts.lua"))("MyForeverProfessions", ns)
ns.CreateGatherAlerts()

local hud, done, grip, ticker = unpack(frames)
local arrow, title, detail = unpack(hud.children)
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
-- Confirmed minimap names use the user's concise wording, no angle or lead.
cursorResources = {{name = "铜矿", kind = "mining", seenAt = now}}
tick()
check(cursorEnabled and hud.shown and title.text == "附近有 铜矿" and detail.text == "小地图范围内" and not arrow.shown,
    "confirmed mineral gets nearby wording without an arrow")
check(scans == 0, "legacy soft cursor never runs beside native cursor scanner")
check(facingReads == 0, "name-only notices do not query player facing")
check(soundCount == 1 and ns.gatherAlertSoundResult == "played", "first confirmed mineral sounds")
for i=1,10 do cursorResources[1].seenAt = now; tick() end
check(soundCount == 1, "continued mineral observation does not repeat the notice")
check(ns.GatherResourceKey("铜矿") == ns.GatherResourceKey("Copper Vein"), "explicit language aliases share a receipt")
check(ns.GatherResourceKey("贫瘠的铜矿脉") ~= ns.GatherResourceKey("铜矿"), "same skill rank does not merge distinct node names")
-- Scanner-owned Quest POI events must not erase a still-confirmed mineral.
local resetBeforeQuestEvent = cursorResets
ownTrackingUpdate = true
ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
tick()
check(cursorResets == resetBeforeQuestEvent and hud.shown and title.text == "附近有 铜矿",
    "scanner-owned quest tracking change leaves its mineral snapshot and HUD intact")
ownTrackingUpdate = false
-- A new native plate adopts the minimap sound receipt.
local heard, result = ns.PlayGatherNotice("铜矿脉", "nearby")
check(heard and result == "shared" and soundCount == 1, "explicit mineral alias handoff shares the sound")
cursorResources = {}
ns.gatherNearbyResources = {{name="铜矿脉",seenAt=now}}
tick()
check(title.text == "附近有 铜矿脉" and detail.text == "就在附近", "native nearby resource uses consistent nearby wording")
ns.gatherNearbyResources = nil
tick()
check(not hud.shown, "completed empty snapshot removes the minimap HUD")
cursorResources = {{name="铜矿",seenAt=now-9}}
tick()
check(not hud.shown, "polling old cache never refreshes its seenAt")
cursorResources = {{name="锡矿",seenAt=now},{name="宁神花",seenAt=now},{name="铜矿石",seenAt=now}}
tick()
check(not hud.shown, "underlevel, unlearned and item names do not produce resource alerts")
cursorResources = {{name="铜矿",seenAt=now}}
tracking = false; ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
cursorResources = {{name="铜矿",seenAt=now}}; tick()
check(not cursorEnabled and not hud.shown, "turning off mineral tracking disables scanning and stale names")
tracking = true; ticker.scripts.OnEvent(ticker, "MINIMAP_UPDATE_TRACKING")
cursorResources = {{name="铜矿",seenAt=now}}; tick(11)
cursorResources = {{name="铜矿",seenAt=now}}; tick()
check(hud.shown and cursorEnabled, "tracking reenable resumes a stationary scan")
combat = true; tick()
check(not cursorEnabled and not hud.shown, "combat disables the scanner and HUD")
combat = false; ns.GatherCommand("off"); tick()
check(not cursorEnabled and not hud.shown, "master off disables native scanning")
ns.GatherCommand("on"); cursorResources = {{name="铜矿",seenAt=now}}; tick()
check(hud.shown, "master on resumes without movement")
local before = cursorResets
ticker.scripts.OnEvent(ticker, "PLAYER_LEAVING_WORLD"); tick()
check(cursorResets > before and not cursorEnabled and not hud.shown, "world transition resets native results")
ticker.scripts.OnEvent(ticker, "PLAYER_ENTERING_WORLD")
cursorResources = {{name="铜矿",seenAt=now}}; tick()
ns.professions = {{id=182,rank=1,modifier=0}}; tick()
check(not hud.shown, "cached confirmed copper is revalidated after profession removal")
ns.professions = {{id=186,rank=3,modifier=0}}
cursorResources = {{name="铜矿",seenAt=now}}; tick()
mouseHeld = true; hud.scripts.OnDragStart(hud); tick()
check(not cursorEnabled, "moving the alert stops native minimap scanning")
mouseHeld = false; hud.scripts.OnMouseUp(hud,"LeftButton")
ns.GatherCommand("test"); tick()
check(not cursorEnabled, "preview does not scan under the cursor")
check(facingReads == 0, "name-only lifecycle never reads a navigation heading")
print("Native cursor alert integration: " .. checks .. " checks passed")
