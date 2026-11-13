local addonName, NS = ...

-- This is a display-only reminder. It never changes a macro, binding, or secure action.
local Seal = {}
NS.PaladinSeal = Seal
local rankIDs = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }
local rankSet = {}
for _, id in ipairs(rankIDs) do rankSet[id] = true end
local spellName = "正义圣印"
local known, inWorld = false, false
local lastMissing, startedAt, isPreview = nil, nil, false
local FADE_IN, HOLD, FADE_OUT = 0.2, 2, 1.3
local DURATION = FADE_IN + HOLD + FADE_OUT
local alert

local function isPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

local function settings()
    if type(MyForeverSealDB) ~= "table" then MyForeverSealDB = {} end
    if MyForeverSealDB.enabled == nil then MyForeverSealDB.enabled = true end
    return MyForeverSealDB
end

local function refreshKnown()
    known = false
    if not isPaladin() then return end
    if C_Spell and C_Spell.GetSpellName then
        spellName = C_Spell.GetSpellName(21084) or spellName
    end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    for _, id in ipairs(rankIDs) do
        if (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, bank))
            or (IsPlayerSpell and IsPlayerSpell(id)) then
            known = true
            return
        end
    end
    -- Also accept any future rank with the same localized name from the player's book.
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo
        and C_SpellBook.IsSpellKnown and bank ~= nil) then return end
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skill = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if skill and not skill.offSpecID then
            for slot = skill.itemIndexOffset + 1, skill.itemIndexOffset + skill.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                if item and item.name == spellName and item.spellID
                    and C_SpellBook.IsSpellKnown(item.spellID, bank) then
                    known = true
                    return
                end
            end
        end
    end
end

local function hasSeal()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 255 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then return false end
            if rankSet[aura.spellId] or aura.name == spellName then return true end
        end
        return false
    end
    if UnitBuff then
        for i = 1, 255 do
            local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
            if not name then return false end
            if rankSet[id] or name == spellName then return true end
        end
        return false
    end
    -- An unavailable aura API must not be interpreted as a missing buff.
    return nil
end

local function makeAlert()
    if alert then return alert end
    alert = CreateFrame("Frame", "MyForeverSealAlert", UIParent)
    alert:SetSize(340, 70)
    alert:SetPoint("CENTER", UIParent, "CENTER", 0, 145)
    alert:SetFrameStrata("HIGH")
    alert:EnableMouse(false)
    -- A soft, narrow scrim keeps text legible without a bordered panel.
    local bg = alert:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 44, 0)
    bg:SetPoint("BOTTOMRIGHT", -44, 0)
    bg:SetColorTexture(0.025, 0.03, 0.04, 0.58)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local edge = alert:CreateTexture(nil, "BACKGROUND")
        edge:SetSize(44, 70)
        edge:SetPoint(side, alert, side, 0, 0)
        edge:SetColorTexture(0.025, 0.03, 0.04, 0.58)
        if edge.SetGradient and CreateColor then
            local clear = CreateColor(0.025, 0.03, 0.04, 0)
            local shade = CreateColor(0.025, 0.03, 0.04, 0.58)
            edge:SetColorTexture(1, 1, 1, 1)
            edge:SetGradient("HORIZONTAL", side == "LEFT" and clear or shade,
                side == "LEFT" and shade or clear)
        else
            edge:SetAlpha(0.4)
        end
    end
    local rim = alert:CreateTexture(nil, "BORDER")
    rim:SetSize(42, 42)
    rim:SetPoint("LEFT", 30, 0)
    rim:SetColorTexture(0.72, 0.58, 0.31, 0.8)
    local icon = alert:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("CENTER", rim, "CENTER")
    icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(21084)
        or "Interface\\Icons\\Ability_ThunderBolt")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    alert.title = alert:CreateFontString(nil, "OVERLAY")
    alert.title:SetFont(font, 24, "")
    alert.title:SetPoint("TOPLEFT", 86, -12)
    alert.title:SetTextColor(1, 0.91, 0.7)
    alert.title:SetShadowColor(0, 0, 0, 1)
    alert.title:SetShadowOffset(1, -1)
    alert.title:SetText("缺少正义圣印")
    local hint = alert:CreateFontString(nil, "OVERLAY")
    hint:SetFont(font, 14, "")
    hint:SetPoint("TOPLEFT", 87, -42)
    hint:SetTextColor(0.83, 0.82, 0.77)
    hint:SetShadowColor(0, 0, 0, 1)
    hint:SetShadowOffset(1, -1)
    hint:SetText("|cffffdf9aCtrl + 按键|r  补圣印")
    alert:Hide()
    return alert
end

local function hideAlert()
    startedAt, isPreview = nil, false
    if alert then
        alert:SetScript("OnUpdate", nil)
        alert:Hide()
        alert:SetAlpha(0)
    end
end

local function smoothstep(value)
    value = math.max(0, math.min(1, value))
    return value * value * (3 - 2 * value)
end

local function animate(self)
    if not startedAt then return end
    local elapsed = GetTime() - startedAt
    if elapsed >= DURATION then
        hideAlert()
    elseif elapsed < FADE_IN then
        self:SetAlpha(smoothstep(elapsed / FADE_IN))
    elseif elapsed < FADE_IN + HOLD then
        self:SetAlpha(1)
    else
        self:SetAlpha(1 - smoothstep((elapsed - FADE_IN - HOLD) / FADE_OUT))
    end
end

local function showAlert(preview)
    local frame = makeAlert()
    startedAt, isPreview = GetTime(), preview == true
    frame.title:SetText(isPreview and "圣印提醒预览" or "缺少正义圣印")
    frame:SetAlpha(0)
    frame:SetScript("OnUpdate", animate)
    frame:Show()
end

local function canRemind()
    return inWorld and isPaladin() and known and settings().enabled
        and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player")
end

function Seal.Refresh()
    if not canRemind() then
        lastMissing = nil
        hideAlert()
        return
    end
    local has = hasSeal()
    if has == nil then
        -- Unknown state neither fabricates a loss nor rearms a completed alert.
        hideAlert()
        return
    end
    local missing = not has
    if isPreview then
        lastMissing = missing
        return
    end
    if missing and lastMissing ~= true then
        showAlert(false)
    elseif not missing then
        hideAlert()
    end
    -- Stay latched after the fade: unrelated aura/flag events must not restart it.
    lastMissing = missing
end

local function message(text)
    print("|cffffc05a圣印提醒：|r" .. text)
end

SLASH_MYFOREVERSEAL1 = "/myseal"
SlashCmdList.MYFOREVERSEAL = function(command)
    command = (command or ""):lower():match("^%s*(.-)%s*$")
    if command == "off" then
        settings().enabled = false
        Seal.Refresh()
        message("已关闭；输入 /myseal on 重新开启。")
    elseif command == "on" then
        settings().enabled = true
        refreshKnown()
        Seal.Refresh()
        message("已开启。圣印缺失时短暂提示，3.5 秒后淡出；补上后再次消失才重新提醒。")
    elseif command == "test" then
        refreshKnown()
        if not (isPaladin() and known) then
            message("仅对已学会正义圣印的圣骑士生效。")
        elseif not settings().enabled then
            message("当前已关闭，请先输入 /myseal on。")
        elseif not inWorld or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then
            message("请在进入世界、存活且结束出租飞行后预览。")
        else
            local has = hasSeal()
            if has ~= nil then lastMissing = not has end
            showAlert(true)
            message("预览：淡入、停留 2 秒、淡出，共 3.5 秒。")
        end
    else
        message("/myseal on 开启；/myseal off 关闭；/myseal test 预览淡出提醒。")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_FLAGS", "player")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        if unit == addonName then settings() end
        return
    end
    if (event == "UNIT_AURA" or event == "UNIT_FLAGS") and unit ~= "player" then return end
    if event == "PLAYER_LEAVING_WORLD" then
        inWorld = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        inWorld = true
        refreshKnown()
    elseif event == "SPELLS_CHANGED" then
        refreshKnown()
    elseif event == "PLAYER_DEAD" then
        lastMissing = nil
        hideAlert()
        return
    end
    Seal.Refresh()
    -- Life/taxi flags can settle after their event; recheck once on the next frame.
    if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST"
        or event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
        C_Timer.After(0, Seal.Refresh)
    end
end)
