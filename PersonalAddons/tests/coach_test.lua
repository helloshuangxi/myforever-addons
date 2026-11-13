-- Lua 5.1 simulated client checks. No record in this file is a game observation.
local checks = 0
local function ok(value, label)
    checks = checks + 1
    assert(value, label or "assertion failed")
end
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, (label or "assertion") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local secret = setmetatable({}, {
    __tostring = function() error("secret was stringified") end,
    __lt = function() error("secret was compared") end,
    __le = function() error("secret was compared") end,
    __add = function() error("secret was used in arithmetic") end,
})
issecretvalue = function(value) return rawequal(value, secret) end
issecrettable = issecretvalue
canaccessvalue = function(value) return not issecretvalue(value) end
local now, combat, instance, pvp = 100, false, false, false
local lockdownOverride, affectingOverride
local hp, power, castSpell, targetSpell, targetInterruptible = 125, 80, 585, nil, true
local cooldown = { startTime = 0, duration = 0, isEnabled = true, modRate = 1 }
GetTime = function() return now end
GetServerTime = function() return 1800000000 + math.floor(now) end
time = GetServerTime
GetBuildInfo = function() return "1.60.1", "70862", "Nov 7 2026", 16001 end
GetLocale = function() return "zhCN" end
InCombatLockdown = function() if lockdownOverride ~= nil then return lockdownOverride end; return combat end
UnitAffectingCombat = function() if affectingOverride ~= nil then return affectingOverride end; return combat end
IsInInstance = function() return instance, pvp and "pvp" or instance and "party" or "none" end
UnitClass = function() return "牧师", "PRIEST", 5 end
UnitRace = function() return "人类", "Human", 1 end
UnitFactionGroup = function() return "Alliance", "联盟" end
UnitLevel = function() return 10 end
UnitName = function() return "FORBIDDEN_CHARACTER_NAME", "FORBIDDEN_REALM_NAME" end
UnitGUID = function(unit) return unit == "player" and "Player-FORBIDDEN_GUID" or "Creature-FORBIDDEN_GUID" end
UnitExists = function(unit) return unit == "player" or unit == "target" end
UnitCanAttack = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitHealth = function() return hp end
UnitHealthMax = function() return 200 end
UnitPower = function() return power end
UnitPowerMax = function() return 100 end
UnitPowerType = function() return 0, "MANA" end
UnitXP = function() return 600 end
UnitXPMax = function() return 1000 end
GetXPExhaustion = function() return 100 end
GetNumQuestLogEntries = function() return 1, 1 end
GetInventoryItemDurability = function(slot) if slot == 1 then return 70, 100 end end
GetNumSpellTabs = function() return 1 end
GetSpellTabInfo = function() return "职业", 1, 0, 2 end
GetSpellBookItemInfo = function(index) return "SPELL", index == 1 and 585 or 589 end
IsSpellKnown = function() return true end
GetSpellInfo = function(id) return "TEST_SPELL", nil, 1, 1500, 0, 30, id end
UnitCastingInfo = function()
    if targetSpell == nil then return nil end
    return "TEST_CAST", "TEST_CAST", 1, 100000, 101500, false, 1, not targetInterruptible, targetSpell, 1
end
UnitChannelInfo = function() return nil end
local logging = false
LoggingCombat = function(value) if type(value) == "boolean" then logging = value end; return logging end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
NUM_BAG_SLOTS = 4
C_Container = { GetContainerNumFreeSlots = function() return 8, 0 end }
C_Map = {
    GetBestMapForUnit = function() return 37 end,
    GetPlayerMapPosition = function() return { GetXY = function() return .4, .6 end } end,
}
Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    SpellBookItemType = { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { name = "职业", itemIndexOffset = 0, numSpellBookItems = 2, isGuild = false, shouldHide = false } end,
    GetSpellBookItemInfo = function(index) return { itemType = 1, spellID = index == 1 and 585 or 589, isPassive = false, isOffSpec = false, isHidden = false } end,
    IsSpellInSpellBook = function() return true end,
    IsSpellKnown = function() return true end,
    IsSpellBookItemPassive = function() return false end,
}
C_Spell = {
    GetSpellCooldown = function() return cooldown end,
    GetSpellInfo = function(id) return { spellID = id, name = "TEST_SPELL", isPassive = false } end,
    IsSpellPassive = function() return false end,
}
C_QuestLog = {
    GetNumQuestLogEntries = function() return 1, 1 end,
    GetInfo = function() return { questID = 101, isHeader = false, isComplete = false } end,
    GetLogIndexForQuestID = function() return 1 end,
    IsComplete = function() return false end,
}
C_UnitAuras = {
    GetAuraDataByIndex = function(_, index) if index == 1 then return { spellId = 1243, applications = 1, duration = 1800, expirationTime = 1900, isHelpful = true } end end,
    GetPlayerAuraBySpellID = function() return nil end,
}
C_CombatLog = { IsCombatLogRestricted = function() return false end }
C_RestrictedActions = {
    GetAddOnRestrictionState = function() return 0 end,
    IsAddOnRestrictionActive = function() return false end,
}
local cleuReads = 0
CombatLogGetCurrentEventInfo = function()
    cleuReads = cleuReads + 1
    error("restricted combat log API must never be called")
end

local root = "_forever_/Interface/AddOns/MyForeverCoach/"
local ns = {}
assert(loadfile(root .. "Core.lua"))("MyForeverCoach", ns)
assert(loadfile(root .. "Capture.lua"))("MyForeverCoach", ns)
assert(loadfile(root .. "Export.lua"))("MyForeverCoach", ns)
ns.Initialize()
ns.StartSession()
ok(ns.session and ns.db and MyForeverCoachDB, "start creates own saved database")
eq(ns.db.schema, 1, "schema is explicit")
eq(ns.session.client.build, "70862", "client build is sampled")
eq(ns.session.character.class, "PRIEST", "class token is captured")

local value, status = ns.Number(secret)
eq(value, nil, "secret number discarded")
eq(status, "restricted", "secret number distinguished")
value, status = ns.Text(secret)
eq(value, nil, "secret text discarded")
eq(status, "restricted", "secret text distinguished")
value, status = ns.Bool(secret)
eq(value, nil, "secret boolean discarded")
eq(status, "restricted", "secret boolean distinguished")
eq(ns.Number(0), 0, "zero is valid")
eq(ns.Bool(false), false, "false is valid")
eq(ns.Number(0/0), nil, "NaN rejected")
eq(ns.Number(math.huge), nil, "infinity rejected")

ns.Observe("player_cast", "observed")
local cap = ns.session.capabilities.player_cast
eq(cap.contexts.idle.observed, 1, "event observation is counted separately")
eq(cap.contexts.idle.readable or 0, 0, "observing event is not readable evidence")
ns.Observe("player_cast", "restricted")
eq(cap.contexts.idle.restricted, 1, "restricted evidence separate")
combat = true
ns.Observe("player_cast", "missing")
eq(cap.contexts.combat.missing, 1, "combat context is distinct")
combat = false
ns.Sample("test")
ok(ns.session.capabilities.health, "health capability exists")
ok(ns.session.capabilities.position, "position capability exists")
ok((ns.session.capabilities.spells.contexts.idle.readable or 0) > 0, "known spell IDs are read")
ok((ns.session.capabilities.cooldown.contexts.idle.readable or 0) > 0, "actual cooldown fields are read")
local initialSnapshot
for index = #ns.session.records, 1, -1 do
    if ns.session.records[index].kind == "snapshot" then initialSnapshot = ns.session.records[index]; break end
end
ok(initialSnapshot and initialSnapshot.data.questIDs and initialSnapshot.data.questIDs[1] == 101,
    "task IDs survive the collection whitelist")
ns.HandleEvent("QUEST_ACCEPTED", 102)
eq(ns.session.records[#ns.session.records].data.questID, 102, "Forever QUEST_ACCEPTED uses its first payload argument")

ns.HandleEvent("PLAYER_TARGET_CHANGED")
eq(ns.session.capabilities.target_cast.contexts.idle.readable or 0, 0,
    "a readable target existence flag does not prove readable target casting")
targetSpell = secret
ns.HandleEvent("PLAYER_TARGET_CHANGED")
ok((ns.session.capabilities.target_cast.contexts.idle.restricted or 0) > 0,
    "restricted cast ID is not overwritten by a missing channel ID")
targetSpell, targetInterruptible = 585, false
ns.HandleEvent("PLAYER_TARGET_CHANGED")
eq(ns.session.records[#ns.session.records].kind, "target_cast", "public target spell creates cast record")
eq(ns.session.records[#ns.session.records].data.interruptible, false, "not-interruptible cast preserves false flag")
targetSpell = nil

local beforeCLEU = #ns.session.records
ns.HandleEvent("COMBAT_LOG_EVENT_UNFILTERED")
eq(cleuReads, 0, "manually forwarding CLEU never calls the restricted read API")
eq(#ns.session.records, beforeCLEU, "disabled CLEU produces no combat records")
eq(ns.session.eventCounts.COMBAT_LOG_EVENT_UNFILTERED, nil, "disabled CLEU is not counted as observed")
local savedActive = C_RestrictedActions.IsAddOnRestrictionActive
C_RestrictedActions.IsAddOnRestrictionActive = function() error("must use event payload") end
ok(pcall(ns.HandleEvent, "ADDON_RESTRICTION_STATE_CHANGED", 0, 2), "restriction callback does not query misleading active flag")
eq(ns.session.records[#ns.session.records].data.restrictionState, 2, "restriction event preserves payload state")
C_RestrictedActions.IsAddOnRestrictionActive = savedActive

local before = #ns.session.records
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "party1", "FORBIDDEN_CAST_GUID", 585, 1)
eq(#ns.session.records, before, "other players' casts are not captured")
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", secret, secret, secret, secret)
eq(#ns.session.records, before, "secret unit cannot be used as player discriminator")
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "FORBIDDEN_CAST_GUID", castSpell, 1)
ok(#ns.session.records > before, "public player spell event is captured")
before = #ns.session.records
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", secret, secret, 1)
ok(ns.session.capabilities.player_cast.contexts.idle.restricted > 1, "secret spell event is reported restricted")

local frame = { registered = {}, attempts = {} }
function frame:RegisterEvent(event)
    self.attempts[event] = (self.attempts[event] or 0) + 1
    if event == "UNIT_POWER_UPDATE" then error("single event registration forbidden") end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then error("restricted event registration must never be attempted") end
    if event == "UNIT_HEALTH" then return end -- pcall succeeds, but registration silently fails.
    self.registered[event] = true
end
function frame:IsEventRegistered(event) return self.registered[event] == true end
ok(pcall(ns.RegisterCaptureEvents, frame), "one blocked registration does not abort initialization")
ok(frame.registered.UNIT_SPELLCAST_SUCCEEDED, "other registrations survive")
eq(frame.attempts.COMBAT_LOG_EVENT_UNFILTERED, nil, "CLEU is skipped before any RegisterEvent call")
eq(ns.session.registrations.COMBAT_LOG_EVENT_UNFILTERED, "disabled_restricted", "disabled event has an explicit registration status")
eq(ns.session.registrations.UNIT_POWER_UPDATE, "error", "ordinary single registration failure remains diagnostic")
eq(ns.session.capabilities.combat_log.disabled, true, "restricted combat log feature is explicitly disabled")
eq(ns.session.capabilities.combat_log.reason, "restricted_event_disabled", "disabled combat log records its static reason")
eq(ns.session.registrationChecks.UNIT_HEALTH, "not_registered", "registration success is independently checked against actual registration")
eq(ns.session.registrationChecks.UNIT_SPELLCAST_SUCCEEDED, "confirmed", "working event registration is independently confirmed")
eq(ns.session.registrationChecks.COMBAT_LOG_EVENT_UNFILTERED, "disabled_restricted", "restricted event is never verified as registered")

before = #ns.session.records
ok(ns.CountReceived("UNIT_SPELLCAST_SUCCEEDED", "FORBIDDEN_DIAGNOSTIC_PAYLOAD"), "known event can be counted at entry without payload storage")
local receivedCast = ns.session.receivedEvents.UNIT_SPELLCAST_SUCCEEDED
eq(receivedCast.count, 1, "entry receipt is separate from processed-event counts")
local firstReceipt = receivedCast.firstAt
now = now + 1
ns.CountReceived("UNIT_SPELLCAST_SUCCEEDED", secret)
eq(receivedCast.count, 2, "entry count increments without touching secret arguments")
eq(receivedCast.firstAt, firstReceipt, "entry first time is preserved")
ok(receivedCast.lastAt > firstReceipt, "entry last time advances")
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", secret, "FORBIDDEN_CAST_GUID", 585, 1)
ok((ns.session.filterCounts.unit_restricted or 0) > 0, "a received event can be diagnosed as filtered by secret unit")
eq(#ns.session.records, before, "entry diagnostics and filtered event do not create gameplay records")
eq(ns.CountReceived("CHAT_MSG_WHISPER", "FORBIDDEN_CHAT"), false, "chat events are excluded from entry diagnostics")
eq(ns.Filter("FORBIDDEN_PRIVATE_REASON"), false, "arbitrary filter reasons cannot be persisted")

ns.SetEnabled(false)
before = #ns.session.records
ns.Sample("paused")
ns.HandleEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "FORBIDDEN_CAST_GUID", 585, 1)
ns.Record("snapshot", { health = 99 })
eq(#ns.session.records, before, "paused collector records no samples/events")
ns.SetEnabled(true)
now = now + 10
ns.Sample("resumed")
ok(#ns.session.records > before, "resume captures again")
combat = true
ns.HandleEvent("PLAYER_REGEN_DISABLED")
ns.SetEnabled(false)
before = #ns.session.records
combat = false
ns.HandleEvent("PLAYER_REGEN_ENABLED")
eq(#ns.session.records, before, "combat-state transitions during pause create no records")
ns.SetEnabled(true)
eq(ns.GetContext(), "idle", "pause does not leave combat state stuck after actual combat ends")
local resumedSnapshot = ns.Sample("after_paused_combat")
eq(resumedSnapshot.combat, false, "resumed snapshot uses current combat state")

ns.inCombat = false
lockdownOverride, affectingOverride = true, true
local healedCombat = ns.Sample("public_combat_heal")
eq(healedCombat.eventCombat, false, "snapshot preserves the previous event-based combat flag")
eq(healedCombat.lockdown, true, "public lockdown state is captured")
eq(healedCombat.affectingCombat, true, "public actual combat state is captured")
eq(healedCombat.combat, true, "public actual combat repairs a missed enter-combat event")
ok((ns.session.filterCounts.combat_state_mismatch or 0) > 0, "combat-state repair has a diagnostic reason")
lockdownOverride, affectingOverride = secret, false
local publicAffecting = ns.Sample("public_actual_priority")
eq(publicAffecting.combat, false, "public actual combat can repair a stale true event flag")
eq(publicAffecting.lockdown, nil, "secret lockdown is retained as unknown, not false")
eq(publicAffecting.lockdownStatus, "restricted", "secret lockdown includes its missingness reason")
ns.inCombat = nil
lockdownOverride, affectingOverride = secret, secret
local unknownCombat = ns.Sample("unknown_combat")
eq(unknownCombat.lockdown, nil, "unknown lockdown is not a false boolean")
eq(unknownCombat.affectingCombat, nil, "unknown actual combat is not a false boolean")
eq(unknownCombat.affectingStatus, "restricted", "unknown actual combat includes the restricted status")
eq(unknownCombat.eventCombat, nil, "missing event combat remains unknown")
eq(unknownCombat.combat, nil, "all-unknown combat state is not fabricated as out of combat")
lockdownOverride, affectingOverride, ns.inCombat = nil, nil, false

hp, power = secret, secret
now = now + 10
ok(pcall(ns.Sample, "restricted_test"), "restricted snapshot does not throw")
ok((ns.session.capabilities.health.contexts.idle.restricted or 0) > 0, "secret health recorded as restricted")
hp, power = 125, 80
cooldown = { startTime = secret, duration = secret, isEnabled = secret }
now = now + 10
ok(pcall(ns.Sample, "restricted_cooldown"), "secret cooldown fields do not throw")
ok((ns.session.capabilities.cooldown.contexts.idle.restricted or 0) > 0, "secret cooldown fields counted as restricted")

local injected = ns.Record("snapshot", { health = 123, name = "FORBIDDEN_CHARACTER_NAME", guid = "Player-FORBIDDEN_GUID", chat = "FORBIDDEN_CHAT", nested = { private = "FORBIDDEN_NESTED" } })
injected.data.health = secret -- Exercise export's independent guard, beyond capture cleaning.
ns.session.errors[#ns.session.errors + 1] = {code = secret, message = "FORBIDDEN_API_ERROR"}
ns.session.receivedEvents.UNIT_SPELLCAST_SUCCEEDED.payload = "FORBIDDEN_DIAGNOSTIC_PAYLOAD"
ns.session.receivedEvents.FORBIDDEN_PRIVATE_EVENT = {count = 1, payload = "FORBIDDEN_DIAGNOSTIC_PAYLOAD"}
local exported, exportError = ns.ExportSession()
ok(type(exported) == "string", "session exports JSON: " .. tostring(exportError))
ok(exported:sub(1, 1) == "{", "export is JSON object")
for _, forbidden in ipairs({ "FORBIDDEN_CHARACTER_NAME", "FORBIDDEN_CAST_GUID", "FORBIDDEN_GUID", "FORBIDDEN_CHAT", "FORBIDDEN_NESTED", "FORBIDDEN_REALM_NAME", "FORBIDDEN_API_ERROR", "FORBIDDEN_DIAGNOSTIC_PAYLOAD", "FORBIDDEN_PRIVATE_EVENT", "FORBIDDEN_PRIVATE_REASON" }) do
    ok(not exported:find(forbidden, 1, true), "private data is excluded: " .. forbidden)
end
ok(exported:find('"receivedEvents"', 1, true), "structured export includes entry diagnostics")
ok(exported:find('"registrationChecks"', 1, true), "structured export includes actual registration verification")
ok(exported:find('"filterCounts"', 1, true), "structured export includes controlled filter counts")
ok(not exported:find("secret was", 1, true), "export never stringifies secret")
local report = ns.ExportReport()
ok(type(report) == "string" and #report > 0, "human capability report is available")

for i = 1, ns.LIMITS.records + 10 do ns.Record("snapshot", { health = i }) end
ok(#ns.session.records <= 1200, "record storage is bounded")
ok(ns.session.dropped > 0, "overflow is explicit")
for i = 1, 20 do ns.Error("test_error") end
ok(#ns.session.errors <= 12, "error storage is bounded")
for i = 1, 12 do now = now + 1; ns.StartSession() end
ok(#ns.db.sessions <= 8, "session history is bounded")
ns.StopSession("test")
ok(ns.session.endedAt ~= nil, "session end is explicit")

-- Boot the full TOC, not just capture helpers, in a fresh simulated client.
local frameMethods, mockFrames = {}, {}
local function mockFrame(_, name)
    local frame = { scripts = {}, registered = {}, attempts = {}, shown = true, name = name }
    setmetatable(frame, {__index = frameMethods})
    mockFrames[#mockFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function frameMethods:SetScript(key, handler) self.scripts[key] = handler end
function frameMethods:RegisterEvent(key)
    self.attempts[key] = (self.attempts[key] or 0) + 1
    if key == "UNIT_POWER_UPDATE" then error("single event registration forbidden") end
    if key == "COMBAT_LOG_EVENT_UNFILTERED" then error("restricted event registration must never be attempted") end
    if key == "UNIT_HEALTH" then return end
    self.registered[key] = true
end
function frameMethods:IsEventRegistered(key) return self.registered[key] == true end
function frameMethods:CreateFontString() return mockFrame() end
function frameMethods:SetText(value) self.text = value end
function frameMethods:SetSize(width, height) self.width, self.height = width, height end
function frameMethods:SetWidth(value) self.width = value end
function frameMethods:SetHeight(value) self.height = value end
function frameMethods:SetPoint(...) self.point = {...} end
function frameMethods:GetPoint() return unpack(self.point or {"CENTER", UIParent, "CENTER", 0, 0}) end
function frameMethods:Show() self.shown = true end
function frameMethods:Hide() self.shown = false end
function frameMethods:IsShown() return self.shown end
function frameMethods:SetShown(value) self.shown = value end
function frameMethods:SetScrollChild(value) self.child = value end
function frameMethods:SetVerticalScroll(value) self.scroll = value end
function frameMethods:SetFocus() self.focused = true end
function frameMethods:ClearFocus() self.focused = false end
function frameMethods:HighlightText() self.selected = true end
for _, method in ipairs({"SetJustifyH", "SetTextColor", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving",
    "StopMovingOrSizing", "SetMultiLine", "SetAutoFocus", "SetFontObject", "SetMaxLetters"}) do
    frameMethods[method] = function() end
end
CreateFrame = mockFrame
UIParent = mockFrame()
SlashCmdList = {}
MyForeverCoachDB = nil
local boot = {}
dofile(root .. "MyForeverStyle.lua")
for _, source in ipairs({"Core.lua", "Capture.lua", "Export.lua", "UI.lua", "Main.lua"}) do
    assert(loadfile(root .. source))("MyForeverCoach", boot)
end
local eventFrame = boot.frame
ok(eventFrame.registered.ADDON_LOADED and eventFrame.registered.PLAYER_LOGIN, "full TOC registers startup events")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "SomeOtherAddon")
eq(boot.db, nil, "unrelated addon does not initialize Coach")
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "MyForeverCoach")
ok(boot.db and not boot.session, "own ADDON_LOADED initializes persistence before session")
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
ok(boot.session and boot.panel:IsShown(), "PLAYER_LOGIN starts capture and creates visible panel")
eq(eventFrame.attempts.COMBAT_LOG_EVENT_UNFILTERED, nil, "full startup never attempts restricted CLEU registration")
eq(boot.session.registrations.COMBAT_LOG_EVENT_UNFILTERED, "disabled_restricted", "full startup marks CLEU disabled")
eq(boot.session.registrations.UNIT_POWER_UPDATE, "error", "ordinary registration failure does not abort full startup")
eq(cleuReads, 0, "full startup never reads restricted combat event data")
eq(boot.session.registrationChecks.UNIT_HEALTH, "not_registered", "full startup detects silently unregistered event")
before = #boot.session.records
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", secret, "FORBIDDEN_CAST_GUID", 585, 1)
eq(boot.session.receivedEvents.UNIT_SPELLCAST_SUCCEEDED.count, 1, "Main entry sees an event before unit filtering")
ok((boot.session.filterCounts.unit_restricted or 0) > 0, "Main retains secret-unit filtering evidence")
eq(#boot.session.records, before, "Main secret-unit filtering leaves no gameplay record")
before = #boot.session.records
local pausedReceipts = boot.session.receivedEvents.UNIT_SPELLCAST_SUCCEEDED.count
now = now + 5
eventFrame.scripts.OnUpdate(eventFrame, 5)
ok(#boot.session.records > before, "periodic sampling runs after complete startup")
SlashCmdList.MYFOREVERCOACH("pause")
eq(boot.db.settings.enabled, false, "pause command applies")
before = #boot.session.records
now = now + 5
eventFrame.scripts.OnUpdate(eventFrame, 5)
eventFrame.scripts.OnEvent(eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "FORBIDDEN_CAST_GUID", 585, 1)
eq(#boot.session.records, before, "paused full runtime neither samples nor captures events")
eq(boot.session.receivedEvents.UNIT_SPELLCAST_SUCCEEDED.count, pausedReceipts + 1, "paused runtime still counts raw event entry")
ok((boot.session.filterCounts.paused or 0) > 0, "paused raw event has an explicit filtering reason")
SlashCmdList.MYFOREVERCOACH("resume")
eq(boot.db.settings.enabled, true, "resume command applies")
SlashCmdList.MYFOREVERCOACH("hide")
eq(boot.panel:IsShown(), false, "hide command changes panel state")
SlashCmdList.MYFOREVERCOACH("show")
eq(boot.panel:IsShown(), true, "show command changes panel state")
local previous = boot.session
combat = true
SlashCmdList.MYFOREVERCOACH("new")
eq(boot.session, previous, "new session is blocked during combat")
combat = false
now = now + 1
SlashCmdList.MYFOREVERCOACH("new")
ok(boot.session ~= previous and previous.endedAt, "new command closes old session before starting another")
SlashCmdList.MYFOREVERCOACH("export")
ok(boot.exportPanel:IsShown() and boot.exportPanel.box.text:sub(1, 1) == "{", "export command displays JSON in copyable panel")
ok(boot.exportPanel.box.focused and boot.exportPanel.box.selected, "export text receives focus and selection")
SlashCmdList.MYFOREVERCOACH("report")
ok(boot.exportPanel.box.text:find("本机能力报告", 1, true), "report command displays capability summary")
SlashCmdList.MYFOREVERCOACH("log on")
eq(logging, true, "log on enables native logging only when explicitly requested")
SlashCmdList.MYFOREVERCOACH("log off")
eq(logging, false, "log off restores native logging")
local previousHandler = boot.HandleEvent
boot.HandleEvent = function() error("simulated event failure") end
ok(pcall(eventFrame.scripts.OnEvent, eventFrame, "UNIT_HEALTH", "player"), "event handler error is isolated")
ok(#boot.session.errors > 0, "event handler failure leaves bounded diagnostics")
boot.HandleEvent = previousHandler
for _, safetyEvent in ipairs({"ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED"}) do
    -- A fresh Lua namespace represents a clean reload for each latched safety case.
    MyForeverCoachDB = nil
    local fresh = {}
    for _, source in ipairs({"Core.lua", "Capture.lua", "Export.lua", "UI.lua", "Main.lua"}) do
        assert(loadfile(root .. source))("MyForeverCoach", fresh)
    end
    local safetyFrame = fresh.frame
    ok(safetyFrame.registered[safetyEvent], safetyEvent .. " is monitored")
    safetyFrame.scripts.OnEvent(safetyFrame, "ADDON_LOADED", "MyForeverCoach")
    safetyFrame.scripts.OnEvent(safetyFrame, "PLAYER_LOGIN")
    safetyFrame.scripts.OnEvent(safetyFrame, safetyEvent, "SomeOtherAddon", "Frame:RegisterEvent()")
    eq(fresh.db.settings.enabled, true, "another addon's blocked action does not stop Coach")
    eq(fresh.session.safetyStop, nil, "another addon's blocked action is not attributed to Coach")
    safetyFrame.scripts.OnEvent(safetyFrame, safetyEvent, "MyForeverCoach", "Frame:RegisterEvent()")
    eq(fresh.db.settings.enabled, false, "own " .. safetyEvent .. " pauses collection")
    eq(fresh.safetyStopped, true, "own blocked action latches the session safety stop")
    eq(fresh.session.safetyStop.event, safetyEvent, "safety evidence retains the exact native event")
    eq(fresh.session.safetyStop.func, "Frame:RegisterEvent__", "safety evidence replaces unsafe function identifier characters")
    local safetyExport = fresh.ExportSession()
    ok(type(safetyExport) == "string" and safetyExport:find('"safetyStop"', 1, true), "safety evidence survives structured export")
    local stoppedCount = #fresh.session.records
    now = now + 5
    safetyFrame.scripts.OnUpdate(safetyFrame, 5)
    safetyFrame.scripts.OnEvent(safetyFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "FORBIDDEN_CAST_GUID", 585, 1)
    eq(#fresh.session.records, stoppedCount, "latched stop blocks periodic sampling and later event capture")
    SlashCmdList.MYFOREVERCOACH("resume")
    eq(fresh.db.settings.enabled, false, "resume command cannot clear a native blocked-action safety stop")
    eq(fresh.SetEnabled(true), false, "direct and UI resume cannot bypass a native blocked-action safety stop")
    eq(fresh.db.settings.enabled, false, "blocked-action latch is enforced by the central enable setter")
    eq(cleuReads, 0, "blocked-action handling never probes restricted combat log API")
end
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGOUT")
ok(boot.stopped and boot.session.endedAt, "logout closes complete runtime session")

print("coach_test: " .. checks .. " checks passed (simulated; not in-game validation)")
return exported
