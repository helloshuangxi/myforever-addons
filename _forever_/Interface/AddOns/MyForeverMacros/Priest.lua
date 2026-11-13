local _, NS = ...

local friendly = "#showtooltip\n/cast [mod:alt,@player][@mouseover,help,nodead][help,nodead][@player] {1}"
local hostile = "#showtooltip\n/cast [@mouseover,harm,nodead][harm,nodead] {1}"
local friendlyHint = "Alt 对自己；否则依次选鼠标下存活友方、当前存活友方、自己。有效目标超出射程时不会继续回退。"

-- IDs and Chinese names are lookup candidates only. Never fill a spell until
-- the current character's learned, active spellbook confirms its actual name.
NS.priestTemplates = {
    { id = "priest_shield", label = "牧师 · 真言术：盾", name = "MF-牧盾", spells = 1,
      spellCandidates = { { id = 17, name = "真言术：盾" } },
      hint = friendlyHint .. "为友方套盾；技能仍受虚弱灵魂等游戏条件限制。", pattern = friendly },
    { id = "priest_renew", label = "牧师 · 恢复", name = "MF-恢复", spells = 1,
      spellCandidates = { { id = 139, name = "恢复" } },
      hint = friendlyHint .. "施放恢复。", pattern = friendly },
    { id = "priest_heal", label = "牧师 · 常规治疗", name = "MF-主疗", spells = 1,
      spellCandidates = { { id = 2060, name = "强效治疗术" }, { id = 2054, name = "治疗术" }, { id = 2050, name = "次级治疗术" } },
      hint = friendlyHint .. "创建时按已学技能选择强效治疗术、治疗术、次级治疗术；升级学会新技能后需重新选择预设。", pattern = friendly },
    { id = "priest_flash_heal", label = "牧师 · 快速治疗", name = "MF-快疗", spells = 1,
      spellCandidates = { { id = 2061, name = "快速治疗" } },
      hint = friendlyHint .. "不默认打断自己的当前读条。", pattern = friendly },
    { id = "priest_dispel_friendly", label = "牧师 · 友方驱散", name = "MF-友驱", spells = 1,
      spellCandidates = { { id = 527, name = "驱散魔法" } },
      hint = friendlyHint .. "只对友方使用驱散魔法；与敌方驱散分开，避免目标混淆。", pattern = friendly },
    { id = "priest_dispel_hostile", label = "牧师 · 敌方驱散", name = "MF-敌驱", spells = 1,
      spellCandidates = { { id = 527, name = "驱散魔法" } },
      hint = "优先鼠标下存活敌人，否则当前存活敌人。用于驱散敌方增益；不会自动改对自己施法。", pattern = hostile },
    { id = "priest_cure_disease", label = "牧师 · 祛病术", name = "MF-祛病", spells = 1,
      spellCandidates = { { id = 528, name = "祛病术" } },
      hint = friendlyHint .. "本预设固定使用已学的祛病术，不替换成驱除疾病。", pattern = friendly },
    { id = "priest_resurrection", label = "牧师 · 复活术", name = "MF-复活", spells = 1,
      spellCandidates = { { id = 2006, name = "复活术" } },
      hint = "脱战后，优先复活鼠标下死亡友方，否则当前死亡友方。战斗中不施放；不会对存活队友尝试。",
      pattern = "#showtooltip\n/cast [nocombat,@mouseover,help,dead][nocombat,help,dead] {1}" },
    { id = "priest_pain", label = "牧师 · 暗言术：痛", name = "MF-暗痛", spells = 1,
      spellCandidates = { { id = 589, name = "暗言术：痛" } },
      hint = "优先鼠标下存活敌人，否则当前存活敌人。施放暗言术：痛，不改变当前选中的目标。", pattern = hostile },
    { id = "priest_smite", label = "牧师 · 惩击", name = "MF-惩击", spells = 1,
      spellCandidates = { { id = 585, name = "惩击" } },
      hint = "优先鼠标下存活敌人，否则当前存活敌人。施放惩击，不默认打断自己的当前读条。", pattern = hostile },
    { id = "priest_fade", label = "牧师 · 渐隐术", name = "MF-渐隐", spells = 1,
      spellCandidates = { { id = 586, name = "渐隐术" } },
      hint = "手动施放渐隐术，不默认打断自己的当前读条。实际生效仍取决于冷却和当前施法状态。",
      pattern = "#showtooltip\n/cast {1}" },
}

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function NormalizeName(name)
    if not Public(name) or type(name) ~= "string" then return nil end
    -- Only formatting differences, never substrings or rank-number guessing.
    return (name:gsub("[ \t\r\n]", ""):gsub("　", ""):gsub("：", ":"))
end

local function LearnedName(entry)
    if type(entry) ~= "table" or not Public(entry.name) or type(entry.name) ~= "string" then return nil end
    return NS.ValidateSpell(entry.name)
end

function NS.ResolvePriestPreset(template)
    if NS.InCombat() then return "", "战斗中暂停读取牧师法术本，请脱战后重新选择预设。" end
    if type(UnitClass) ~= "function" then return "", "无法确认当前职业，未自动填写技能。" end
    local classOK, _, class = pcall(UnitClass, "player")
    if not classOK or not Public(class) or type(class) ~= "string" then
        return "", "无法确认当前职业，未自动填写技能。"
    end
    if class ~= "PRIEST" then return "", "牧师预设仅为牧师自动选择技能；当前角色不是牧师。" end
    if type(template) ~= "table" or type(template.spellCandidates) ~= "table" then
        return "", "此预设没有可核对的牧师技能。"
    end
    if type(NS.ReadSpells) ~= "function" then return "", "法术本读取功能不可用，未自动填写技能。" end
    local scanOK, spells, scanNote = pcall(NS.ReadSpells)
    if not scanOK or type(spells) ~= "table" then return "", "法术本读取失败，未自动填写技能。" end
    if #spells == 0 then
        return "", "未确认已学技能，未自动填写。" .. (type(scanNote) == "string" and scanNote or "")
    end

    for _, candidate in ipairs(template.spellCandidates) do
        local candidateName = NormalizeName(candidate.name)
        local localizedName
        if C_Spell and type(C_Spell.GetSpellName) == "function" then
            local ok, name = pcall(C_Spell.GetSpellName, candidate.id)
            if ok then localizedName = NormalizeName(name) end
        end
        for _, spell in ipairs(spells) do
            local name = LearnedName(spell)
            if name then
                local normalized = NormalizeName(name)
                local sameID = Public(spell.spellID) and type(spell.spellID) == "number" and spell.spellID == candidate.id
                if sameID or (localizedName and normalized == localizedName) or (candidateName and normalized == candidateName) then
                    return name, "已从本角色法术本选择：" .. name .. "。宏未指定技能等级。"
                end
            end
        end
    end
    return "", "未在本角色已学法术本中确认此预设技能，未自动填写；请先学习技能或核对法术本。"
end
