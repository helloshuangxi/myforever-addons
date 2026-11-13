-- Simulated native object nameplates and CVar lifecycle. No game automation.
local source = "_forever_/Interface/AddOns/MyForeverProfessions/"
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local defaults = { SoftTargetInteract = "0", SoftTargetIconGameObject = "0",
    SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" }
local wanted = { SoftTargetInteract = "3", SoftTargetIconGameObject = "1",
    SoftTargetInteractArc = "2", SoftTargetInteractRange = "30" }
local function copy(input)
    if type(input) ~= "table" then return input end
    local result = {}
    for key, value in pairs(input) do result[key] = copy(value) end
    return result
end

local function client(raw, options)
    options = options or {}
    local env = setmetatable({}, {__index = _G})
    local state = { values = options.values or copy(defaults), writes = {}, frames = {}, effects = {},
        plates = {}, byUnit = {}, objects = {}, combat = options.combat == true, failedWrites = {},
        now = 0, soundAttempts = 0, sounds = 0, messages = {} }
    local methods = {}
    local function frame(kind, name, parent)
        local created = setmetatable({kind = kind, parent = parent, scripts = {}, children = {}, shown = true}, {__index = methods})
        if parent and parent.isPlate then state.effects[parent] = created end
        state.frames[#state.frames + 1] = created
        return created
    end
    function methods:SetScript(event, fn) self.scripts[event] = fn end
    function methods:Show()
        local wasShown = self.shown
        self.shown = true
        if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide() self.shown = false end
    function methods:SetScale(value) self.scale = value end
    function methods:SetAlpha(value) self.alpha = value end
    function methods:SetVertexColor(...) self.color = {...} end
    function methods:SetBlendMode(value) self.blend = value end
    function methods:SetColorTexture(...)
        self.fill = {...}
        self.paints = (self.paints or 0) + 1
        self.lastPaintAfterLayout = self.point ~= nil
    end
    function methods:SetPoint(...) self.point = {...} end
    function methods:CreateTexture()
        local texture = frame("Texture", nil, self)
        self.children[#self.children + 1] = texture
        return texture
    end
    for _, method in ipairs({"SetSize", "ClearAllPoints", "EnableMouse", "RegisterEvent"}) do
        methods[method] = function() end
    end
    env.CreateFrame = frame
    env.InCombatLockdown = function() return state.combat end
    env.UnitAffectingCombat = function() return state.combat end
    env.UnitIsDeadOrGhost = function() return state.dead end
    env.GetTime = function() return state.now end
    env.PlaySound = function(kit)
        assert(kit == 3175, "nearby notices use the established map ping sound")
        state.soundAttempts = state.soundAttempts + 1
        if state.failSound then return false end
        state.sounds = state.sounds + 1
        return true, state.sounds
    end
    env.issecretvalue = function(value) return value == "SECRET" end
    env.UnitIsGameObject = function(unit)
        assert(unit ~= "SECRET", "secret unit must never reach a native query")
        local object = state.objects[unit]
        return object and object.object or false
    end
    env.UnitName = function(unit)
        local object = state.objects[unit]
        return object and object.name
    end
    env.UnitGUID = function(unit)
        local object = state.objects[unit]
        return object and object.guid
    end
    env.C_NamePlate = {
        GetNamePlates = function()
            if state.plateFailure == "error" then error("native plates temporarily unavailable") end
            if state.plateFailure then return state.plateFailure end
            return state.plates
        end,
        GetNamePlateForUnit = function(unit) return state.byUnit[unit] end,
    }
    if options.noPlateAPI then env.C_NamePlate = false end
    if options.noPlateLookup then env.C_NamePlate.GetNamePlateForUnit = nil end
    env.C_CVar = {
        GetCVar = function(key) return state.values[key] end,
        SetCVar = function(key, value)
            state.writes[#state.writes + 1] = {key, value}
            if not state.failedWrites[key] then state.values[key] = value end
            if state.events then state.events.scripts.OnEvent(state.events, "CVAR_UPDATE", key) end
        end,
    }
    if options.unsupported then env.UnitIsGameObject = nil; env.C_NamePlate = false end
    local ns = {}
    local function load(name)
        local chunk = assert(loadfile(source .. name .. ".lua"))
        setfenv(chunk, env)
        chunk("MyForeverProfessions", ns)
    end
    load("Core")
    load("API")
    load("GatherResources")
    ns.db = ns.NormalizeDB(raw or {})
    ns.db.gatherSparkles = not raw or raw.gatherSparkles ~= false
    ns.db.gatherSparkleScale = raw and raw.gatherSparkleScale or 1
    ns.db.gatherSparkleCVars = raw and copy(raw.gatherSparkleCVars) or {}
    ns.db.gatherSparkleOverrides = raw and copy(raw.gatherSparkleOverrides) or {}
    ns.detectReady = true
    ns.professions = {{id = 186, rank = 3, modifier = 0}}
    ns.Print = function(message) state.messages[#state.messages + 1] = message end
    load("GatherSparkles")
    load("GatherAlerts")
    ns.CreateGatherSparkles()
    state.events = state.frames[1]
    function state.tick(seconds)
        state.now = state.now + (seconds or 0.21)
        state.events.scripts.OnUpdate(state.events, 0.21)
    end
    function state.event(event, unit)
        state.events.scripts.OnEvent(state.events, event, unit)
    end
    function state.add(unit, name, object, guid)
        local plate = { isPlate = true, UnitFrame = {unit = unit} }
        state.plates[#state.plates + 1], state.byUnit[unit] = plate, plate
        state.objects[unit] = { name = name, object = object ~= false, guid = guid }
        return plate
    end
    return ns, state
end

local ns, state = client()
eq(#state.writes, 4, "enable applies four needed settings once")
for key, value in pairs(wanted) do
    eq(state.values[key], value, "requested CVar applied " .. key)
    eq(ns.db.gatherSparkleCVars[key].before, defaults[key], "original CVar saved " .. key)
end
local writes = #state.writes
for _ = 1, 10 do state.tick() end
eq(#state.writes, writes, "periodic refresh never repeats settings writes")
local copper = state.add("nameplate1", "铜矿脉")
local tin = state.add("nameplate2", "锡矿脉")
local herb = state.add("nameplate3", "宁神花")
local npc = state.add("nameplate4", "铜矿脉", false)
local unknown = state.add("nameplate5", "陌生的石头")
state.tick()
eq(ns.gatherSparkleCount, 1, "only known resource with sufficient learned skill shines")
eq(state.effects[copper].shown, true, "copper effect is shown")
eq(state.effects[tin], nil, "skill too low creates no effect")
eq(state.effects[herb], nil, "unlearned herbalism creates no effect")
eq(state.effects[npc], nil, "same-named NPC creates no effect")
eq(state.effects[unknown], nil, "unknown object creates no effect")
local sparkle = state.effects[copper]
eq(sparkle.children[1].paints, 1, "creation initializes texture once")
sparkle.scripts.OnUpdate(sparkle, 0.1)
eq(sparkle.children[1].paints, 2, "first visible update repaints texture")
eq(sparkle.children[1].lastPaintAfterLayout, true, "first visible repaint follows texture layout")
sparkle.scripts.OnUpdate(sparkle, 0.1)
eq(sparkle.children[1].paints, 2, "normal animation does not repaint texture every frame")
eq(sparkle.children[1].alpha <= 0.28, true, "outer glow remains gentle")
eq(sparkle.children[2].blend, "BLEND", "dark outline does not use additive light")
eq(sparkle.children[2].alpha, 0.92, "outline remains visible through the pulse")
eq(sparkle.children[2].color, nil, "resource tint cannot recolor the dark outline")
eq(sparkle.children[3].alpha >= 0.65, true, "bright core remains legible between flashes")
ns.professions = {{id = 182, rank = 1, modifier = 0}}
state.tick()
eq(sparkle.shown, false, "forgetting mining hides the old effect")
eq(state.effects[herb].shown, true, "learned herbalism enables matching herb")
ns.professions = {{id = 186, rank = 3, modifier = 0}, {id = 182, rank = 1, modifier = 0}}
state.tick()
eq(sparkle.children[1].paints, 2, "show queues repaint until visible layout")
sparkle.scripts.OnUpdate(sparkle, 0.1)
eq(sparkle.children[1].paints, 3, "hidden then reshown effect repaints once")
eq(sparkle.children[2].fill[1], 0.035, "repaint preserves dark outline fill")
eq(sparkle.children[3].color[2], 0.74, "repaint preserves mining tint")
sparkle.scripts.OnUpdate(sparkle, 0.1)
eq(sparkle.children[1].paints, 3, "recovered effect resumes without repeated repaint")
state.byUnit.nameplate3 = nil
state.event("NAME_PLATE_UNIT_REMOVED", "nameplate3")
eq(state.effects[herb].shown, false, "removed plate is hidden even after native mapping is gone")
ns.professions = {{id = 186, rank = 60, modifier = 5}}
state.tick()
eq(state.effects[tin].shown, true, "skill modifier counts toward requirement")
state.objects.nameplate2 = {name = "陌生的石头", object = true}
state.tick()
eq(state.effects[tin].shown, false, "plate recycling cannot retain the old resource effect")
ns.professions = {{id = 186, rank = "SECRET", modifier = 0}}
state.tick()
eq(ns.gatherSparkleCount, 0, "secret skill is rejected")
ns.professions = {{id = 186, rank = 3, modifier = 0}}
state.objects.nameplate1.name = "SECRET"
state.tick()
eq(sparkle.shown, false, "secret resource name hides the prior effect")
state.objects.nameplate1.name = "铜矿脉"
state.objects.nameplate1.object = "SECRET"
state.tick()
eq(sparkle.shown, false, "secret game object flag is rejected")
state.objects.nameplate1.object = true
state.combat = true
state.event("PLAYER_REGEN_DISABLED")
eq(sparkle.shown, false, "combat immediately hides all effects")
local combatPlate = state.add("nameplate6", "铜矿脉")
state.tick()
eq(state.effects[combatPlate], nil, "combat creates no new effect")
state.combat = false
state.event("PLAYER_REGEN_ENABLED")
state.tick()
eq(state.effects[combatPlate].shown, true, "effects resume after combat")
ns.SparkleCommand("scale 1.4")
eq(state.effects[combatPlate].scale, 1.4, "effect size follows scale setting")
ns.SparkleCommand("off")
eq(state.effects[combatPlate].shown, false, "off hides existing effects")
for key, value in pairs(defaults) do eq(state.values[key], value, "off restores original " .. key) end
eq(next(ns.db.gatherSparkleCVars), nil, "successful restore clears ownership")

local user, live = client()
live.values.SoftTargetInteractArc = "1"
live.event("CVAR_UPDATE", "SoftTargetInteractArc")
live.tick()
eq(user.db.gatherSparkleOverrides.SoftTargetInteractArc, true, "user override suppresses reacquisition")
eq(user.db.gatherSparkleCVars.SoftTargetInteractArc, nil, "override releases ownership")
local reloaded, resumed = client(copy(user.db), {values = live.values})
eq(resumed.values.SoftTargetInteractArc, "1", "reload respects persisted user override")
reloaded.SparkleCommand("on")
eq(resumed.values.SoftTargetInteractArc, "1", "on without an off transition keeps user override")
reloaded.SparkleCommand("off")
reloaded.SparkleCommand("on")
eq(resumed.values.SoftTargetInteractArc, "2", "explicit off-on may reacquire settings")
resumed.event("PLAYER_LOGOUT")
eq(next(reloaded.db.gatherSparkleCVars), nil, "logout clears successfully restored records")
eq(resumed.values.SoftTargetInteractArc, "1", "logout restores the latest user baseline")
resumed.event("CVAR_UPDATE", "SoftTargetInteractArc")
eq(next(reloaded.db.gatherSparkleOverrides), nil, "delayed logout events do not mistake restoration for a user override")

local deferred, combat = client(nil, {combat = true})
eq(#combat.writes, 0, "combat initialization defers CVar changes")
deferred.SparkleCommand("off")
deferred.SparkleCommand("on")
eq(#combat.writes, 0, "combat toggles do not perform writes")
combat.combat = false
combat.tick()
eq(#combat.writes, 4, "combat transition applies only final desired state")
combat.combat = true
deferred.SparkleCommand("off")
eq(combat.values.SoftTargetInteract, "3", "restoration waits for combat to finish")
combat.combat = false
combat.tick()
eq(combat.values.SoftTargetInteract, "0", "deferred restoration finishes after combat")

local snapshot = { SoftTargetInteract = {before = "0", applied = "3"} }
local absent, unavailable = client({gatherSparkleCVars = snapshot}, {unsupported = true})
eq(#unavailable.writes, 0, "unsupported APIs cause no CVar mutations")
eq(absent.db.gatherSparkleCVars.SoftTargetInteract.before, "0", "missing API retains pending recovery record")
local aligned, alignedState = client(nil, {values = copy(wanted)})
eq(#alignedState.writes, 0, "already configured values are never claimed")
eq(next(aligned.db.gatherSparkleCVars), nil, "already matching preferences have no ownership")
alignedState.values.SoftTargetInteractRange = "12"
alignedState.event("CVAR_UPDATE", "SoftTargetInteractRange")
eq(aligned.db.gatherSparkleOverrides.SoftTargetInteractRange, true, "user changes to preexisting matching settings are respected")
local alignedReload, alignedReloadState = client(copy(aligned.db), {values = alignedState.values})
eq(alignedReloadState.values.SoftTargetInteractRange, "12", "reload does not recapture a user-changed unowned preference")
local numeric = copy(wanted)
numeric.SoftTargetInteractRange = "30.000000"
local decimals, decimalState = client(nil, {values = numeric})
eq(#decimalState.writes, 0, "numeric CVar formatting is equivalent")
local restore, failed = client()
failed.failedWrites.SoftTargetInteract = true
restore.SparkleCommand("off")
eq(restore.db.gatherSparkleCVars.SoftTargetInteract.before, "0", "failed restoration keeps original snapshot")
failed.failedWrites.SoftTargetInteract = nil
failed.tick()
eq(restore.db.gatherSparkleCVars.SoftTargetInteract, nil, "later successful restoration releases snapshot")

local audible, audio = client()
local firstOre = audio.add("nameplate1", "铜矿脉", true, "ore-a")
audio.tick()
eq(audio.sounds, 1, "first eligible nearby object automatically requests a sound")
eq(audible.gatherSparkleSoundCount, 1, "nearby success counter counts accepted playback")
for _ = 1, 50 do audio.tick() end
eq(audio.sounds, 1, "an uninterrupted node never repeats even beyond the quiet interval")
audio.plates, audio.byUnit.nameplate1 = {}, nil
audio.event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
audio.tick(2)
audio.add("nameplate8", "铜矿脉", true, "ore-a")
audio.tick()
eq(audio.sounds, 1, "a brief disappearance and new plate token retain GUID deduplication")
audio.objects.nameplate8.guid = "ore-b"
audio.tick(4)
eq(audio.sounds, 2, "a different same-name ore can notify after the shared cooldown")
audio.plates, audio.byUnit.nameplate8 = {}, nil
audio.tick(11)
audio.add("nameplate9", "铜矿脉", true, "ore-b")
audio.tick()
eq(audio.sounds, 3, "leaving a resource for ten seconds rearms its notice")

local muted, mute = client({gatherSound = false})
mute.add("nameplate1", "铜矿脉", true, "muted-ore")
mute.tick(5)
eq(mute.soundAttempts, 0, "existing mute setting prevents even a playback request")
muted.db.gatherSound = true
mute.tick()
eq(mute.sounds, 1, "unmuting can notify a node that was never successfully announced")
local disabled, off = client({gatherAlerts = false})
off.add("nameplate1", "铜矿脉", true, "disabled-ore")
off.tick()
eq(off.soundAttempts, 0, "gather off also mutes the nearby source")
disabled.db.gatherAlerts = true
disabled.SparkleCommand("off")
off.tick(5)
eq(off.soundAttempts, 0, "sparkle off stops the nearby detection source")
disabled.SparkleCommand("on")
off.tick()
eq(off.sounds, 1, "re-enabling the source permits its first notice")

local paused, pause = client(nil, {combat = true})
pause.add("nameplate1", "铜矿脉", true, "paused-ore")
pause.tick(5)
eq(pause.soundAttempts, 0, "combat cannot emit nearby notices")
pause.combat, pause.dead = false, true
pause.tick(5)
eq(pause.soundAttempts, 0, "dead characters cannot emit nearby notices")
pause.dead = "SECRET"
pause.tick()
eq(pause.soundAttempts, 0, "restricted death state fails closed without a boolean comparison")
pause.dead = false
pause.event("PLAYER_LEAVING_WORLD")
pause.tick(5)
eq(pause.soundAttempts, 0, "leaving the world pauses nearby playback")
pause.event("PLAYER_ENTERING_WORLD")
pause.tick()
eq(pause.sounds, 1, "returning to a live world can notify an unheard resource")
pause.event("PLAYER_LOGOUT")
pause.add("nameplate2", "铜矿脉", true, "logout-ore")
pause.tick(20)
eq(pause.sounds, 1, "logout cannot emit a sound from lingering nameplates")

local retry, failure = client()
failure.failSound = true
failure.add("nameplate1", "铜矿脉", true, "retry-ore")
failure.tick()
eq(failure.soundAttempts, 1, "failed playback is observed")
eq(retry.gatherSparkleSoundCount or 0, 0, "failure is not counted as accepted playback")
for _ = 1, 10 do failure.tick() end
eq(failure.soundAttempts, 1, "failed playback retries cannot flood each refresh")
failure.failSound = false
failure.tick(4)
eq(failure.sounds, 1, "a later successful request is not swallowed by the failed attempt")

local fallback, noGuid = client()
noGuid.add("nameplate1", "铜矿脉", true, "SECRET")
noGuid.tick()
noGuid.add("nameplate2", "铜矿脉", true, nil)
noGuid.tick(5)
eq(noGuid.sounds, 1, "unavailable or secret GUIDs conservatively deduplicate by resource name")
local identity, changingGuid = client()
changingGuid.add("nameplate1", "铜矿脉", true, nil)
changingGuid.tick()
changingGuid.objects.nameplate1.guid = "stable-ore"
changingGuid.tick(5)
eq(changingGuid.sounds, 1, "a newly readable GUID does not reannounce a continuously visible resource")
changingGuid.objects.nameplate1.guid = "SECRET"
changingGuid.tick(5)
eq(changingGuid.sounds, 1, "a temporarily restricted GUID retains the resource's known identity")
changingGuid.objects.nameplate1.guid = "different-ore"
changingGuid.tick(5)
eq(changingGuid.sounds, 2, "a different readable GUID is new after the prior GUID became unavailable")
local recycled, newUnit = client()
newUnit.add("nameplate1", "铜矿脉", true, "returning-ore")
newUnit.tick()
newUnit.plates, newUnit.byUnit.nameplate1 = {}, nil
newUnit.event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
newUnit.tick(2)
newUnit.add("nameplate9", "铜矿脉", true, nil)
newUnit.tick(3)
eq(newUnit.sounds, 1, "brief plate churn with an unreadable GUID conservatively retains the same-name notice")
newUnit.objects.nameplate9.guid = "returning-ore"
newUnit.tick()
eq(newUnit.sounds, 1, "the returning readable identity preserves its existing notice")
newUnit.add("nameplate10", "铜矿脉", true, "another-real-ore")
newUnit.tick()
eq(newUnit.sounds, 2, "name fallback receipts do not suppress a different readable GUID")
local herbs, herbAudio = client()
herbs.professions = {{id = 182, rank = 1, modifier = 0}}
herbAudio.add("nameplate1", "宁神花", true, "herb-a")
herbAudio.add("nameplate2", "铜矿脉", true, "ore-not-learned")
herbAudio.add("nameplate3", "宁神花", false, "npc-not-resource")
herbAudio.tick()
eq(herbAudio.sounds, 1, "only the learned and eligible gathering kind can notify")

local shared, both = client()
eq(shared.PlayGatherNotice("铜矿脉", "minimap"), true, "minimap can use the shared playback service")
both.add("nameplate1", "铜矿脉", true, "shared-ore")
both.tick()
eq(both.sounds, 1, "nearby discovery acknowledges the existing minimap notice")
both.tick(6)
eq(both.sounds, 1, "a suppressed duplicate is not replayed when the cooldown elapses")
eq(shared.gatherSparkleSoundCount or 0, 0, "cross-source acknowledgment is not counted as a nearby playback")
eq(shared.PlayGatherNotice("锡矿脉", "minimap"), true, "another resource can notify after the shared interval")
eq(shared.PlayGatherNotice("宁神花", "nearby"), false, "different resources still share the minimum playback interval")
local fromNearby, nearbyFirst = client()
nearbyFirst.add("nameplate1", "铜矿脉", true, "nearby-first")
nearbyFirst.tick()
eq(fromNearby.PlayGatherNotice("铜矿脉", "minimap"), true, "minimap also acknowledges a preceding nearby notice")
eq(nearbyFirst.sounds, 1, "reverse source order emits only one sound")
local sharedIdentity, newAfterShared = client()
sharedIdentity.PlayGatherNotice("铜矿脉", "minimap")
newAfterShared.add("nameplate1", "铜矿脉", true, "first-after-minimap")
newAfterShared.tick()
newAfterShared.objects.nameplate1.guid = "second-after-minimap"
newAfterShared.tick(5)
eq(newAfterShared.sounds, 2, "sharing the first minimap notice cannot silence later same-name resources")
-- Only fresh, eligible native observations can feed the non-positional HUD.
local publish, published = client()
published.add("nameplate1", "铜矿脉", true, "private-object-id")
published.add("nameplate2", "铜矿脉", true, "other-private-id")
published.add("nameplate3", "锡矿脉", true)
published.tick()
eq(#publish.gatherNearbyResources, 1, "same-name nearby HUD observations are deduplicated")
local observation = publish.gatherNearbyResources[1]
eq(observation.name, "铜矿脉", "nearby observation carries the resource name")
eq(observation.kind, "mining", "nearby observation carries the skill kind")
eq(observation.seenAt, published.now, "nearby observation carries a freshness timestamp")
eq(observation.guid, nil, "the shared HUD observation contains no object identity")
eq(observation.unit, nil, "the shared HUD observation contains no native unit token")
published.event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
eq(publish.gatherNearbyResources, nil, "plate removal invalidates the HUD snapshot before the next poll")
published.tick()
eq(#publish.gatherNearbyResources, 1, "a fresh poll republishes still available native resources")
published.plates, published.byUnit = {}, {}
published.tick()
eq(#publish.gatherNearbyResources, 0, "an empty native plate set clears old nearby observations")
published.add("nameplate4", "铜矿脉", true)
published.tick()
publish.SparkleCommand("off")
eq(publish.gatherNearbyResources, nil, "disabling the source clears nearby HUD observations")
publish.SparkleCommand("on")
published.tick()
published.event("PLAYER_REGEN_DISABLED")
eq(publish.gatherNearbyResources, nil, "combat entry clears nearby HUD observations immediately")
published.tick()
published.event("PLAYER_LEAVING_WORLD")
eq(publish.gatherNearbyResources, nil, "leaving the world clears nearby HUD observations immediately")
published.tick()
eq(publish.gatherNearbyResources, nil, "a stale plate list cannot republish while outside the world")
published.event("PLAYER_ENTERING_WORLD")
published.tick()
eq(#publish.gatherNearbyResources, 1, "fresh nearby observations resume after entering the world")

local soft, interaction = client()
interaction.objects.softinteract = {name = "铜矿脉", object = true, guid = "soft-only-ore"}
interaction.tick()
eq(soft.gatherNearbyCount, 1, "a valid soft target is recognized without any nameplate")
eq(soft.gatherNearbyResources[1].name, "铜矿脉", "soft target publishes the real resource name")
eq(soft.gatherNearbyResources[1].seenAt, interaction.now, "soft target observations stay fresh")
eq(soft.gatherNearbyResources[1].guid, nil, "soft target does not publish its identity")
eq(soft.gatherNearbyResources[1].unit, nil, "soft target does not publish its unit token")
eq(soft.gatherSparkleCount, 0, "soft target without a plate does not invent sparkles")
eq(next(interaction.effects), nil, "no synthetic plate or scene geometry is created")
eq(interaction.sounds, 1, "soft target can notify without a nameplate")
interaction.tick(6)
eq(interaction.sounds, 1, "continuous soft target does not repeat its notice")
local recoveredPlate = interaction.add("nameplate1", "铜矿脉", true, "soft-only-ore")
interaction.tick(5)
eq(soft.gatherNearbyCount, 1, "plate and soft target share one same-name HUD observation")
eq(soft.gatherSparkleCount, 1, "a recovered real plate enables sparkles")
eq(interaction.effects[recoveredPlate].shown, true, "recovered plate displays the existing effect")
eq(interaction.sounds, 1, "same readable identity does not notify twice during source handoff")
interaction.plates, interaction.byUnit = {}, {}
interaction.tick()
eq(soft.gatherNearbyCount, 1, "plate removal does not lose the still-present soft target")
eq(soft.gatherSparkleCount, 0, "plate removal clears only its sparkle")
interaction.objects.softinteract = nil
interaction.tick()
eq(soft.gatherNearbyCount, 0, "a missing soft target clears nearby count immediately")
eq(#soft.gatherNearbyResources, 0, "a missing soft target clears its stale HUD observation")
interaction.tick(11)
interaction.objects.softinteract = {name = "铜矿脉", object = true, guid = "soft-only-ore"}
interaction.tick()
eq(interaction.sounds, 2, "a soft target absent for the quiet interval can notify again")

local unnamed, identityHandoff = client()
identityHandoff.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
identityHandoff.tick()
identityHandoff.add("nameplate1", "铜矿脉", true, "newly-readable-ore")
identityHandoff.tick(5)
eq(identityHandoff.sounds, 1, "unreadable soft identity conservatively shares its same-name receipt with a new plate")
identityHandoff.objects.softinteract.guid = "newly-readable-ore"
identityHandoff.tick(5)
eq(identityHandoff.sounds, 1, "soft identity becoming readable after plate handoff stays deduplicated")
identityHandoff.add("nameplate2", "铜矿脉", true, "different-readable-ore")
identityHandoff.tick(5)
eq(identityHandoff.sounds, 2, "known different resource identities remain independently notifiable")
local simultaneous, identityTransition = client()
identityTransition.objects.softinteract = {name = "铜矿脉", object = true}
identityTransition.tick()
identityTransition.objects.softinteract.guid = "known-first-ore"
identityTransition.add("nameplate1", "铜矿脉", true, "known-first-ore")
identityTransition.add("nameplate2", "铜矿脉", true, "known-second-ore")
identityTransition.tick(5)
eq(identityTransition.sounds, 2, "newly readable soft identity cannot suppress a different plate in the same poll")

local singleAdoption, anonymous = client()
anonymous.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
anonymous.tick()
anonymous.add("nameplate1", "铜矿脉", true, "adopted-ore-a")
anonymous.tick(5)
eq(anonymous.sounds, 1, "one readable plate may inherit an anonymous soft target receipt")
anonymous.add("nameplate2", "铜矿脉", true, "distinct-ore-b")
anonymous.tick(5)
eq(anonymous.sounds, 2, "a second readable identity cannot inherit the same anonymous receipt")
anonymous.tick(5)
eq(anonymous.sounds, 2, "both continuously visible readable identities stay deduplicated")
anonymous.plates, anonymous.byUnit = {}, {}
anonymous.tick(2)
anonymous.add("nameplate8", "铜矿脉", true, "adopted-ore-a")
anonymous.add("nameplate9", "铜矿脉", true, "distinct-ore-b")
anonymous.tick()
eq(anonymous.sounds, 2, "same identities returning under new plate tokens do not repeat")
anonymous.objects.softinteract, anonymous.plates, anonymous.byUnit = nil, {}, {}
anonymous.tick(11)
anonymous.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
anonymous.tick()
eq(anonymous.sounds, 3, "a fully expired anonymous receipt can notify again")
anonymous.add("nameplate10", "铜矿脉", true, "distinct-ore-b")
anonymous.tick(5)
eq(anonymous.sounds, 3, "a fresh anonymous receipt may adopt a different returning identity")

local reverseAdoption, reverse = client()
reverse.add("nameplate1", "铜矿脉", true, "plate-first-a")
reverse.tick()
eq(reverse.sounds, 1, "readable plate can establish the initial named receipt")
reverse.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
reverse.tick(5)
eq(reverse.sounds, 1, "later anonymous soft target shares the plate-established receipt")
reverse.add("nameplate2", "铜矿脉", true, "plate-second-b")
reverse.tick(5)
eq(reverse.sounds, 2, "later distinct plate cannot adopt a receipt established by the first plate")
reverse.add("nameplate3", "铜矿脉", true, "plate-third-c")
reverse.tick(5)
eq(reverse.sounds, 3, "another readable identity also remains independently notifiable")
reverse.tick(5)
eq(reverse.sounds, 3, "continuous reverse-order observations stay deduplicated")
reverse.plates, reverse.byUnit = {}, {}
reverse.tick(2)
reverse.add("nameplate7", "铜矿脉", true, "plate-first-a")
reverse.add("nameplate8", "铜矿脉", true, "plate-second-b")
reverse.add("nameplate9", "铜矿脉", true, "plate-third-c")
reverse.tick()
eq(reverse.sounds, 3, "reverse-order identities returning under new plate tokens do not repeat")
reverse.objects.softinteract.guid = "plate-first-a"
reverse.tick(5)
eq(reverse.sounds, 3, "plate-first identity becoming readable on the soft target preserves its receipt")

for _, initialResult in ipairs({"failed", "cooldown"}) do
    local reversePending, pending = client()
    local initialSounds = 0
    if initialResult == "failed" then pending.failSound = true
    else
        reversePending.PlayGatherNotice("锡矿脉", "minimap")
        initialSounds = 1
    end
    pending.add("nameplate1", "铜矿脉", true, "reverse-pending-a")
    pending.tick()
    eq(pending.sounds, initialSounds, "plate-first " .. initialResult .. " leaves its notice pending")
    pending.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
    pending.tick()
    pending.failSound = false
    pending.tick(5)
    eq(pending.sounds, initialSounds + 1, "soft target retry shares its earlier pending plate receipt")
    pending.tick(5)
    eq(pending.sounds, initialSounds + 1, "plate cannot repeat a successful soft target retry after " .. initialResult)
    pending.add("nameplate2", "铜矿脉", true, "reverse-pending-b")
    pending.tick(5)
    eq(pending.sounds, initialSounds + 2, "new identity remains notifiable after the reverse " .. initialResult .. " handoff")
end

for _, initialResult in ipairs({"failed", "cooldown"}) do
    local pendingAdoption, pending = client()
    local initialSounds = 0
    if initialResult == "failed" then pending.failSound = true
    else
        pendingAdoption.PlayGatherNotice("锡矿脉", "minimap")
        initialSounds = 1
    end
    pending.objects.softinteract = {name = "铜矿脉", object = true, guid = "SECRET"}
    pending.tick()
    eq(pending.sounds, initialSounds, "initial " .. initialResult .. " leaves the anonymous notice pending")
    pending.add("nameplate1", "铜矿脉", true, "pending-adopted-a")
    pending.tick()
    pending.failSound = false
    pending.add("nameplate2", "铜矿脉", true, "pending-distinct-b")
    pending.tick(5)
    eq(pending.sounds, initialSounds + 1, "anonymous retry after " .. initialResult .. " shares only with its bound identity")
    pending.tick(5)
    eq(pending.sounds, initialSounds + 2, "different identity retries after cooldown despite earlier " .. initialResult)
    pending.tick(5)
    eq(pending.sounds, initialSounds + 2, "successful receipts after " .. initialResult .. " do not repeat")
end

for _, unavailableOptions in ipairs({{noPlateAPI = true}, {noPlateLookup = true}}) do
    local noPlates, native = client(nil, unavailableOptions)
    native.objects.softinteract = {name = "铜矿脉", object = true, guid = "no-plate-api-ore"}
    native.tick()
    eq(noPlates.gatherNearbyCount, 1, "missing plate APIs do not block native resource recognition")
    eq(noPlates.gatherSparkleCount, 0, "missing plate APIs cannot create visual effects")
    eq(native.sounds, 1, "missing plate APIs do not block the nearby sound source")
    eq(noPlates.gatherSparkleState, "nearby-only", "status identifies the text-only native path")
end
local transient, unavailablePlates = client()
unavailablePlates.objects.softinteract = {name = "铜矿脉", object = true, guid = "transient-ore"}
for _, failureKind in ipairs({"SECRET", "error", "unavailable"}) do
    unavailablePlates.plateFailure = failureKind
    unavailablePlates.tick(5)
    eq(transient.gatherNearbyCount, 1, "unavailable or restricted plate results preserve the soft target path")
end
eq(unavailablePlates.sounds, 1, "plate API failures do not repeat an existing soft target notice")
unavailablePlates.plateFailure = nil
unavailablePlates.add("nameplate1", "铜矿脉", true, "transient-ore")
unavailablePlates.tick(5)
eq(transient.gatherSparkleCount, 1, "plate API recovery restores real sparkles")
eq(unavailablePlates.sounds, 1, "plate API recovery preserves the existing notice receipt")

local filtered, badSoft = client()
for _, object in ipairs({
    {name = "铜矿脉", object = false}, {name = "陌生的石头", object = true},
    {name = "铜矿脉", object = "SECRET"}, {name = "SECRET", object = true},
    {name = "锡矿脉", object = true}, {name = "宁神花", object = true},
}) do
    badSoft.objects.softinteract = object
    badSoft.tick(5)
    eq(filtered.gatherNearbyCount, 0, "ineligible or restricted soft targets cannot publish a resource")
end
eq(badSoft.soundAttempts, 0, "ineligible soft targets never request playback")
filtered.detectReady = false
badSoft.objects.softinteract = {name = "铜矿脉", object = true}
badSoft.tick()
eq(filtered.gatherNearbyCount, 0, "soft targets wait for actual profession detection")

local softPaused, pausedSoft = client(nil, {combat = true})
pausedSoft.objects.softinteract = {name = "铜矿脉", object = true, guid = "paused-soft-ore"}
pausedSoft.tick()
eq(softPaused.gatherNearbyResources, nil, "combat cannot publish a soft target snapshot")
pausedSoft.combat, pausedSoft.dead = false, true
pausedSoft.tick()
eq(softPaused.gatherNearbyResources, nil, "death clears soft target HUD data")
pausedSoft.dead = "SECRET"
pausedSoft.tick()
eq(softPaused.gatherNearbyResources, nil, "restricted death state fails closed for soft target data")
pausedSoft.dead = false
pausedSoft.event("PLAYER_LEAVING_WORLD")
pausedSoft.tick()
eq(softPaused.gatherNearbyResources, nil, "leaving the world cannot republish a lingering soft target")
eq(pausedSoft.soundAttempts, 0, "all paused soft target states suppress sound requests")
pausedSoft.event("PLAYER_ENTERING_WORLD")
pausedSoft.tick()
eq(softPaused.gatherNearbyCount, 1, "live-world return refreshes the native soft target")
eq(pausedSoft.sounds, 1, "live-world return can notify an unheard soft target")
softPaused.SparkleCommand("off")
eq(softPaused.gatherNearbyCount, 0, "disabling the source clears the soft target count")
eq(softPaused.gatherNearbyResources, nil, "disabling the source clears the soft target snapshot")

local silentSoft, silent = client({gatherSound = false})
silent.objects.softinteract = {name = "铜矿脉", object = true}
silent.tick()
eq(silentSoft.gatherNearbyCount, 1, "muting sound keeps nearby text observations")
eq(silent.soundAttempts, 0, "muted soft target does not request a sound")
silentSoft.db.gatherSound = true
silentSoft.db.gatherAlerts = false
silent.tick(5)
eq(silent.soundAttempts, 0, "reminder-off also suppresses soft target sound")
silentSoft.SparkleCommand("status")
eq(silent.messages[1]:find("当前闪光 0 处", 1, true) ~= nil, true, "status labels the actual sparkle count")
eq(silent.messages[2]:find("近距离识别 1 种资源", 1, true) ~= nil, true, "status separately labels nearby resource recognition")

print("Gather sparkles: " .. checks .. " simulated checks passed")
