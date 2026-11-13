local _, NS = ...

-- Explicit ASCII classes keep locale-sensitive Lua 5.1 patterns away from UTF-8 bytes.
local function trim(s) return (tostring(s or ""):gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")) end
NS.trim = trim
function NS.InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

function NS.ValidateSpell(value)
    local name = trim(value)
    if name == "" then return nil, "请填写技能名，或从本角色法术本选择。" end
    if name:find("[\r\n;%[%]|]") or name:sub(1, 1) == "/" then
        return nil, "技能栏只接受技能名称，不接受链接、换行或宏命令。"
    end
    if #name > 100 then return nil, "技能名称过长，请使用法术本中的名称。" end
    return name
end

function NS.Build(template, first, second)
    if type(template) ~= "table" then return nil, "请选择模板。" end
    local one, two, err
    if template.spells >= 1 then
        one, err = NS.ValidateSpell(first)
        if not one then return nil, err end
    end
    if template.spells == 2 then
        two, err = NS.ValidateSpell(second)
        if not two then return nil, err end
    end
    local body = template.pattern:gsub("{1}", function() return one or "" end)
    body = body:gsub("{2}", function() return two or "" end)
    -- Conservative byte limit: every accepted UTF-8 string also fits a 255-character limit.
    if #body > 255 then return nil, "宏超过本工具的 255 字节保守上限，请缩短技能名或拆成两个宏。" end
    return body
end

local function macroLimits()
    local c = Constants and Constants.MacroConsts
    local account = c and c.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS
    local character = c and c.MAX_CHARACTER_MACROS or MAX_CHARACTER_MACROS
    if type(account) ~= "number" or type(character) ~= "number" then return nil end
    return account, character
end

local function charLength(s)
    local _, count = s:gsub("[^\128-\191]", "")
    return count
end

function NS.Create(name, body)
    if NS.InCombat() then return nil, "战斗中不能创建宏，请脱战后重试。" end
    name = trim(name)
    if name == "" or charLength(name) > 16 or name:find("[%z\1-\31\127|]") then
        return nil, "宏名称须为 1–16 个字符，且不含控制字符或竖线。"
    end
    if type(body) ~= "string" or body == "" or #body > 255 then return nil, "请先生成有效的宏预览。" end
    if not (CreateMacro and GetNumMacros and GetMacroInfo) then
        return nil, "此客户端未提供宏创建接口，可复制预览到 /macro。"
    end
    local accountMax, charMax = macroLimits()
    if not accountMax then return nil, "未读取到客户端宏容量，请复制预览到 /macro。" end
    -- Search both scopes. Never edit or delete an existing macro, even one we created.
    for index = 1, accountMax + charMax do
        local ok, existingName, _, existingBody = pcall(GetMacroInfo, index)
        if not ok then return nil, "读取现有宏失败，请复制预览到 /macro。" end
        if existingName == name then
            if index > accountMax and existingBody == body then
                return index, "同名同内容的角色宏已存在，可直接取到鼠标。"
            end
            return nil, "已有同名宏，请改一个名称；本工具不会覆盖现有宏。"
        end
    end
    local countsOK, _, used = pcall(GetNumMacros)
    if not countsOK or type(used) ~= "number" then return nil, "读取角色宏数量失败。" end
    if used >= charMax then return nil, "角色宏已满，请在 /macro 自行整理后重试。" end
    local ok, index = pcall(CreateMacro, name, 134400, body, true)
    if not ok then return nil, "客户端拒绝创建宏；可复制预览到 /macro 手动新建。" end
    if type(index) == "number" and index > accountMax and index <= accountMax + charMax then
        local readOK, actualName, _, actualBody = pcall(GetMacroInfo, index)
        if readOK and actualName == name and actualBody == body then
            return index, "已创建角色宏。点击“取到鼠标”，再放到动作条；或在 /macro 中拖动。"
        end
    end
    return nil, "未确认宏写入成功。请先检查 /macro，避免重复创建。"
end

function NS.Pickup(name, body)
    if NS.InCombat() then return nil, "战斗中不能拾取宏。" end
    if not (PickupMacro and GetMacroInfo) then return nil, "请打开 /macro 手动拖动。" end
    if GetCursorInfo and GetCursorInfo() then return nil, "鼠标上已有物品或技能，请先放回。" end
    local accountMax, charMax = macroLimits()
    if not accountMax then return nil, "无法读取宏容量。" end
    -- Creation/removal can reorder macro indices. Resolve the exact identity again.
    for index = accountMax + 1, accountMax + charMax do
        local ok, macroName, _, macroBody = pcall(GetMacroInfo, index)
        if ok and macroName == name and macroBody == body then
            local picked = pcall(PickupMacro, index)
            if picked and GetCursorInfo then
                local kind, cursorIndex = GetCursorInfo()
                if kind == "macro" and cursorIndex == index then return true, "宏已在鼠标上，请点击空动作条位置。" end
            end
            return nil, "未确认拾取成功，请在 /macro 中拖动该宏。"
        end
    end
    return nil, "未找到刚才创建的宏；它可能已被改名或修改，请查看 /macro。"
end

function NS.ReadSpells()
    if NS.InCombat() then return {}, "战斗中暂停读取法术本。" end
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemInfo and C_SpellBook.IsSpellKnown
        and Enum and Enum.SpellBookSpellBank and Enum.SpellBookItemType) then
        return {}, "无法读取法术本，请手动填写游戏内技能名。"
    end
    local ok, result = pcall(function()
        local spells, seen = {}, {}
        local bank = Enum.SpellBookSpellBank.Player
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skill = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if skill and not skill.offSpecID then
                for slot = skill.itemIndexOffset + 1, skill.itemIndexOffset + skill.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                    if info and info.itemType == Enum.SpellBookItemType.Spell and info.spellID
                        and not info.isPassive and not info.isOffSpec and not info.isHidden
                        and (C_SpellBook.IsSpellKnown(info.spellID, bank)
                            or (info.actionID and C_SpellBook.IsSpellKnown(info.actionID, bank))) then
                        local name = info.name
                        if not name and info.spellID and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(info.spellID) end
                        if name and not seen[name] then
                            seen[name] = true
                            spells[#spells + 1] = { name = name, spellID = info.spellID }
                        end
                    end
                end
            end
        end
        table.sort(spells, function(a, b) return a.name < b.name end)
        return spells
    end)
    if not ok then return {}, "法术本接口读取失败，请手动填写游戏内技能名。" end
    if #result == 0 then return result, "暂无可选技能；可手动输入，宠物技能与折叠技能不在此列表中。" end
    return result, "只列普通主动玩家技能；同名等级合并，宠物及折叠技能可手动填写。"
end
