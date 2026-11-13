-- Run from the World of Warcraft folder with Lua 5.1 (or lupa.lua51).
local base = "_forever_/Interface/AddOns/MyForeverMacros/PaladinSeal.lua"
local checks = 0
local function check(value, description)
    checks = checks + 1
    assert(value, description)
end

local function setup(options)
    options = options or {}
    local state = { class = options.class or "PALADIN", known = options.known ~= false,
        auras = options.auras or {}, dead = false, taxi = false, now = 0, timers = {}, auraReads = 0, prints = {} }
    local frames = {}
    local function region()
        local object = {}
        local noops = { "SetSize", "SetPoint", "SetFrameStrata", "SetAllPoints", "SetHeight", "SetWidth",
            "SetColorTexture", "SetTexture", "SetTexCoord", "SetFont", "SetTextColor", "SetVertexColor",
            "SetBlendMode", "SetShadowColor", "SetShadowOffset", "SetJustifyH", "SetJustifyV" }
        for _, method in ipairs(noops) do object[method] = function() end end
        function object:SetText(text) self.text = text end
        function object:SetAlpha(alpha) self.alpha = alpha end
        function object:GetAlpha() return self.alpha == nil and 1 or self.alpha end
        function object:EnableMouse(enabled) self.mouse = enabled end
        function object:Show() self.shown = true end
        function object:Hide() self.shown = false end
        function object:IsShown() return self.shown or false end
        function object:CreateTexture() return region() end
        function object:CreateFontString() return region() end
        function object:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
        function object:RegisterUnitEvent(event, unit) self:RegisterEvent(event); self.unitFilter = unit end
        function object:SetScript(script, callback) self[script] = callback end
        function object:GetScript(script) return self[script] end
        return object
    end
    CreateFrame = function(_, name)
        local frame = region()
        frames[#frames + 1] = frame
        if name then state.alert = frame end
        return frame
    end
    UnitClass = function() return "圣骑士", state.class end
    UnitIsDeadOrGhost = function() return state.dead end
    UnitOnTaxi = function() return state.taxi end
    GetTime = function() return state.now end
    Enum = { SpellBookSpellBank = { Player = 0 } }
    C_Spell = {
        GetSpellName = function() return "正义圣印" end,
        GetSpellTexture = function() return 135932 end,
    }
    C_SpellBook = { IsSpellKnown = function(id) return state.known and id == (state.knownID or 21084) end }
    IsPlayerSpell, UnitBuff = nil, nil
    C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
        check(unit == "player" and filter == "HELPFUL", "only reads player buffs")
        state.auraReads = state.auraReads + 1
        return state.auras[index]
    end }
    C_Timer = { After = function(delay, callback)
        state.timers[#state.timers + 1] = { at = state.now + delay, callback = callback }
    end }
    MyForeverSealDB = options.settings
    SlashCmdList = {}
    print = function(text) state.prints[#state.prints + 1] = text end
    local ns = {}
    assert(loadfile(base))("MyForeverMacros", ns)
    state.events = frames[1]
    function state:fire(event, unit) self.events.OnEvent(self.events, event, unit) end
    function state:visible() return self.alert and self.alert.shown or false end
    function state:advance(seconds)
        self.now = self.now + seconds
        local timers = self.timers
        self.timers = {}
        for _, timer in ipairs(timers) do
            if timer.at <= self.now then timer.callback() else self.timers[#self.timers + 1] = timer end
        end
        -- WoW only ticks visible frames, and a handler may remove itself while ticking.
        for _, frame in ipairs(frames) do
            local update = frame.OnUpdate
            if frame.shown and update then update(frame, seconds) end
        end
    end
    function state:advanceTo(time) self:advance(time - self.now) end
    state:fire("ADDON_LOADED", "MyForeverMacros")
    state:fire("PLAYER_ENTERING_WORLD")
    return state, ns
end

local originalPrint = print
local activeSeal = { { name = "正义圣印", spellId = 21084 } }
local function hidden(state, description)
    check(not state:visible(), description)
    check(not state.alert or state.alert.OnUpdate == nil, description .. " removes OnUpdate")
end
local function near(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) < 0.001
end

local s = setup()
check(s:visible(), "missing seal reminds immediately outside combat")
check(s.alert.mouse == false, "reminder does not intercept mouse")
check(MyForeverSealDB.enabled == true, "enabled by default")
check(s.alert.title.text:find("正义圣印", 1, true), "missing-buff reminder names the seal")
s:advanceTo(0.1)
check(s:visible() and s.alert.alpha > 0 and s.alert.alpha < 1, "first 0.2 seconds fade in")
s:advanceTo(0.2)
check(near(s.alert.alpha, 1), "fade in reaches full opacity at 0.2 seconds")
s:advanceTo(1.2)
check(s:visible() and near(s.alert.alpha, 1), "reminder remains fully visible during hold")
s:advanceTo(2.2)
check(s:visible() and near(s.alert.alpha, 1), "two second hold ends at 2.2 seconds")
s:advanceTo(2.85)
check(s:visible() and s.alert.alpha > 0 and s.alert.alpha < 1, "remaining 1.3 seconds fade out")
local middleFadeAlpha = s.alert.alpha
s:advanceTo(3.3)
check(s:visible() and s.alert.alpha > 0 and s.alert.alpha < middleFadeAlpha, "fade out opacity decreases smoothly")
s:advanceTo(3.5)
hidden(s, "one reminder ends after 3.5 seconds")
for _ = 1, 3 do
    s:fire("UNIT_AURA", "player")
    s:fire("UNIT_FLAGS", "player")
    s:fire("SPELLS_CHANGED")
end
hidden(s, "continued missing buff does not replay after expiration")
s:advance(10)
hidden(s, "missing buff remains quiet after its one reminder")

-- A stream of player events must neither replay the banner nor extend its deadline.
s = setup()
s:advanceTo(1.0)
for _ = 1, 4 do
    s:fire("UNIT_AURA", "player")
    s:fire("UNIT_FLAGS", "player")
    s:fire("SPELLS_CHANGED")
end
s:advanceTo(2.85)
check(s:visible() and s.alert.alpha > 0 and s.alert.alpha < 1, "event storm cannot restart the hold interval")
s:fire("UNIT_AURA", "player")
s:advanceTo(3.5)
hidden(s, "event storm cannot extend the original 3.5-second deadline")

s.auras = { { name = "力量祝福", spellId = 19740 }, { name = "正义圣印", spellId = 20291 } }
s:fire("UNIT_AURA", "player")
hidden(s, "higher rank seal keeps reminder hidden")
s.auras = {}
local reads = s.auraReads
s:fire("UNIT_AURA", "target")
check(not s:visible() and reads == s.auraReads, "other units cannot trigger player alert")
s:fire("UNIT_AURA", "player")
check(s:visible(), "reapplying then losing seal starts a new reminder")
s:advance(0.5)
s.auras = { { name = "正义圣印", spellId = 999999 } }
s:fire("UNIT_AURA", "player")
hidden(s, "new rank detected by localized name immediately cancels active reminder")
s:advance(5)
hidden(s, "cancelled reminder cannot reappear after its old deadline")
s.auras = {}
s:fire("UNIT_AURA", "player")
check(s:visible(), "a later separate seal loss is eligible again")
s.dead = true
s:fire("PLAYER_DEAD")
hidden(s, "death cancels reminder immediately")
s:fire("UNIT_AURA", "player")
hidden(s, "dead or ghost cannot redisplay reminder")
s:advance(5)
hidden(s, "death cancellation survives old animation deadline")
s.dead = false
s:fire("PLAYER_UNGHOST")
check(s:visible(), "resurrection permits one missing-buff reminder")
s.taxi = true
s:fire("PLAYER_CONTROL_LOST")
hidden(s, "taxi cancels reminder")
s:fire("UNIT_FLAGS", "player")
hidden(s, "unit flags cannot redisplay reminder during taxi")
s.taxi = false
s:fire("PLAYER_CONTROL_GAINED")
check(s:visible(), "landing permits one missing-buff reminder")
s:fire("PLAYER_LEAVING_WORLD")
hidden(s, "loading screen cancels reminder")
s:fire("UNIT_AURA", "player")
s:advance(5)
hidden(s, "aura updates and queued callbacks during loading remain hidden")
s:fire("PLAYER_ENTERING_WORLD")
check(s:visible(), "world entry permits one missing-buff reminder")
SlashCmdList.MYFOREVERSEAL("off")
hidden(s, "off immediately cancels reminder")
check(MyForeverSealDB.enabled == false, "off persists disabled state")
s:fire("UNIT_AURA", "player")
hidden(s, "off survives aura update")
check(s.prints[#s.prints]:find("已关闭", 1, true), "off gives clear feedback")
SlashCmdList.MYFOREVERSEAL("on")
check(s:visible(), "off-to-on permits one missing-buff reminder")
local onTime = s.now
s:advance(1)
SlashCmdList.MYFOREVERSEAL("on")
s:advanceTo(onTime + 3.5)
hidden(s, "repeated on does not extend active reminder")
SlashCmdList.MYFOREVERSEAL("on")
hidden(s, "repeated on does not replay expired reminder")

-- Preview uses the same animation but remains independent from the actual buff.
s = setup({ auras = activeSeal })
hidden(s, "logging in with active seal does not warn")
SlashCmdList.MYFOREVERSEAL("test")
check(s:visible(), "preview displays despite an active seal")
s:advanceTo(0.1)
check(s.alert.alpha > 0 and s.alert.alpha < 1, "preview uses same fade-in animation")
s:fire("UNIT_AURA", "player")
check(s:visible(), "an active buff does not cancel explicit preview")
s:advanceTo(2.85)
check(s.alert.alpha > 0 and s.alert.alpha < 1, "preview uses same fade-out animation")
s:advanceTo(3.5)
hidden(s, "preview automatically ends after 3.5 seconds")

s = setup()
s:advance(3.5)
hidden(s, "initial missing reminder finishes before preview")
SlashCmdList.MYFOREVERSEAL("test")
check(s:visible(), "explicit preview replays even after missing reminder was already shown")
s:advance(3.5)
hidden(s, "preview with missing seal ends without chaining a fresh reminder")
s:fire("UNIT_AURA", "player")
s:fire("UNIT_FLAGS", "player")
hidden(s, "events after preview cannot replay same missing-buff episode")
SlashCmdList.MYFOREVERSEAL("test")
s.auras = activeSeal
s:fire("UNIT_AURA", "player")
check(s:visible(), "reapplying seal does not interrupt explicit preview")
s:advance(3.5)
hidden(s, "independent preview ends with buff active")
s.auras = {}
s:fire("UNIT_AURA", "player")
check(s:visible(), "fresh seal loss after preview can remind again")

-- Previews must consume a missing episode even if it starts while preview is active.
s = setup({ auras = activeSeal })
SlashCmdList.MYFOREVERSEAL("test")
s:advance(1)
s.auras = {}
s:fire("UNIT_AURA", "player")
s:advanceTo(3.5)
hidden(s, "seal loss during preview does not extend or chain the preview")
s:fire("UNIT_AURA", "player")
hidden(s, "seal lost during preview stays quiet after preview")

s = setup()
SlashCmdList.MYFOREVERSEAL("test")
local cancelledUpdate = s.alert.OnUpdate
s:fire("PLAYER_CONTROL_GAINED") -- This may queue a deferred refresh in the runtime.
SlashCmdList.MYFOREVERSEAL("off")
hidden(s, "off cancels active preview")
if cancelledUpdate then cancelledUpdate(s.alert, 0.1) end
hidden(s, "a stale animation callback cannot revive a cancelled preview")
s:advance(10)
hidden(s, "old queued callbacks cannot revive a disabled reminder")

s = setup()
C_UnitAuras = nil
s:fire("UNIT_AURA", "player")
hidden(s, "missing API is not mistaken for missing seal")
UnitBuff = function(_, index) if index == 1 then return "正义圣印", nil, nil, nil, nil, nil, nil, nil, nil, 20287 end end
s:fire("UNIT_AURA", "player")
hidden(s, "legacy aura API recognizes seal")
UnitBuff = function() end
s:fire("UNIT_AURA", "player")
check(s:visible(), "legacy aura API detects a new missing-seal episode")

s = setup({ class = "PRIEST" })
check(not s:visible() and not s.alert and s.auraReads == 0, "non-paladin never creates an alert or scans auras")
SlashCmdList.MYFOREVERSEAL("test")
check(not s:visible(), "preview does not bypass class restriction")
s = setup({ known = false })
check(not s:visible(), "unlearned seal does not warn")
s.known, s.knownID = true, 20293
s:fire("SPELLS_CHANGED")
check(s:visible(), "learning a higher rank enables reminder")
s = setup({ settings = { enabled = false } })
check(not s:visible(), "saved disabled setting survives reload")
SlashCmdList.MYFOREVERSEAL("test")
check(not s:visible() and MyForeverSealDB.enabled == false, "preview does not silently turn on disabled reminder")

print = originalPrint
print("paladin_seal_test: " .. checks .. " checks passed")
