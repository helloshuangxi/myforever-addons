local _, NS = ...
local frame, picker
local selected = 1
local family = "general"
local lastCreated
local function templates()
    return family == "priest" and NS.priestTemplates or NS.templates
end

local function label(parent, text, x, y, width, font)
    local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    f:SetText(text)
    return f
end
local function button(parent, text, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 28)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end
local function edit(parent, x, y, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 26)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetMaxLetters(100)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end
local function status(message)
    frame.status:SetText(message or "")
end
local function refresh()
    local t = templates()[selected]
    frame.TitleText:SetText(family == "priest" and "MyForever · 牧师宏工坊" or "MyForever · 个人宏工坊")
    frame.generalTab:SetEnabled(family ~= "general")
    frame.priestTab:SetEnabled(family ~= "priest")
    frame.hint:SetText(t.hint)
    frame.first:SetEnabled(t.spells >= 1)
    frame.firstPick:SetEnabled(t.spells >= 1 and not NS.InCombat())
    frame.second:SetEnabled(t.spells == 2)
    frame.secondPick:SetEnabled(t.spells == 2 and not NS.InCombat())
    local body, err = NS.Build(t, frame.first:GetText(), frame.second:GetText())
    frame.body = body
    if lastCreated and (lastCreated.body ~= body or lastCreated.name ~= NS.trim(frame.name:GetText())) then
        lastCreated = nil
    end
    frame.preview:SetText(body or "")
    frame.length:SetText(body and ("预览 · " .. #body .. " / 255 字节（保守限制）") or "预览")
    frame.create:SetEnabled(body ~= nil and not NS.InCombat())
    frame.pickup:SetEnabled(lastCreated ~= nil and not NS.InCombat())
    for i, b in ipairs(frame.templates) do
        local entry = templates()[i]
        b:SetShown(entry ~= nil)
        b:SetText(entry and entry.label or "")
        b:SetEnabled(i ~= selected)
    end
    if NS.InCombat() then status("战斗中暂停法术本读取和宏创建；脱战后可继续。")
    elseif err then status(err)
    else status("确认预览后创建。宏须由你按键触发；技能仍受射程、资源和冷却限制。") end
end

local function selectTemplate(index)
    selected = index
    local t = templates()[selected]
    lastCreated = nil
    frame.name:SetText(t.name)
    local note
    if family == "priest" then
        local spell
        spell, note = NS.ResolvePriestPreset(t)
        frame.first:SetText(spell or "")
        frame.second:SetText("")
    end
    refresh()
    if note then status(note) end
end

local function selectFamily(kind)
    family = kind
    selected = 1
    lastCreated = nil
    frame.first:SetText("")
    frame.second:SetText("")
    selectTemplate(1)
end

local function showPicker(destination)
    if NS.InCombat() then status("请脱战后选择技能。") return end
    if not picker then
        picker = CreateFrame("Frame", "MyForeverSpellPicker", frame, "BasicFrameTemplateWithInset")
        picker:SetSize(350, 410)
        picker:SetPoint("CENTER", frame, "CENTER", 90, 0)
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true)
        picker.TitleText:SetText("选择本角色已学技能")
        picker.search = edit(picker, 22, -40, 305)
        picker.search:SetMaxLetters(60)
        picker.rows = {}
        picker.page = 1
        picker.note = label(picker, "", 18, -337, 310, "GameFontHighlightSmall")
        picker.note:SetHeight(45)
        local function update()
            local query = NS.trim(picker.search:GetText()):lower()
            local filtered = {}
            for _, spell in ipairs(picker.spells or {}) do
                if query == "" or spell.name:lower():find(query, 1, true) then filtered[#filtered + 1] = spell end
            end
            local pages = math.max(1, math.ceil(#filtered / 8))
            picker.page = math.min(picker.page, pages)
            for i, row in ipairs(picker.rows) do
                local spell = filtered[(picker.page - 1) * 8 + i]
                row.spell = spell
                row:SetText(spell and spell.name or "")
                row:SetShown(spell ~= nil)
            end
            picker.pageText:SetText(picker.page .. " / " .. pages)
            picker.previous:SetEnabled(picker.page > 1)
            picker.next:SetEnabled(picker.page < pages)
        end
        for i = 1, 8 do
            local row = button(picker, "", 18, -73 - (i - 1) * 28, 310, function(self)
                if NS.InCombat() then picker:Hide() return end
                if self.spell then picker.destination:SetText(self.spell.name); picker.destination:ClearFocus(); picker:Hide(); refresh() end
            end)
            picker.rows[i] = row
        end
        picker.previous = button(picker, "上一页", 18, -303, 90, function() picker.page = picker.page - 1; update() end)
        picker.next = button(picker, "下一页", 238, -303, 90, function() picker.page = picker.page + 1; update() end)
        picker.pageText = label(picker, "", 130, -311, 100)
        picker.search:SetScript("OnTextChanged", function() picker.page = 1; update() end)
        picker.update = update
        UISpecialFrames[#UISpecialFrames + 1] = "MyForeverSpellPicker"
    end
    picker.destination = destination
    local spells, note = NS.ReadSpells()
    picker.spells = spells
    picker.note:SetText(note)
    picker.page = 1
    picker.search:SetText("")
    picker.update()
    picker:Show()
    picker.search:SetFocus()
end

local function createUI()
    frame = CreateFrame("Frame", "MyForeverMacrosFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(780, 580)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function()
        frame.first:ClearFocus(); frame.second:ClearFocus(); frame.name:ClearFocus(); frame.preview:ClearFocus()
        if picker then picker:Hide() end
    end)
    frame.TitleText:SetText("MyForever · 个人宏工坊")
    frame.generalTab = button(frame, "通用", 16, -35, 82, function() selectFamily("general") end)
    frame.priestTab = button(frame, "牧师", 104, -35, 82, function() selectFamily("priest") end)
    frame.templates = {}
    for i = 1, math.max(#NS.templates, #NS.priestTemplates) do
        local templateIndex = i
        frame.templates[i] = button(frame, "", 16, -73 - (i - 1) * 35, 170, function()
            selectTemplate(templateIndex)
        end)
    end
    label(frame, "技能一（与游戏内名称一致）", 207, -42, 450, "GameFontNormal")
    frame.first = edit(frame, 212, -66, 405)
    frame.firstPick = button(frame, "从法术本选", 636, -65, 124, function() showPicker(frame.first) end)
    label(frame, "技能二（仅 Shift 双技能使用）", 207, -108, 450, "GameFontNormal")
    frame.second = edit(frame, 212, -132, 405)
    frame.secondPick = button(frame, "从法术本选", 636, -131, 124, function() showPicker(frame.second) end)
    label(frame, "角色宏名称", 207, -173, 100, "GameFontNormal")
    frame.name = edit(frame, 322, -167, 295)
    frame.name:SetMaxLetters(16)
    frame.name:SetText(templates()[selected].name)
    frame.hint = label(frame, "", 207, -208, 548)
    frame.hint:SetHeight(66)
    frame.hint:SetJustifyV("TOP")
    frame.length = label(frame, "预览", 207, -286, 548, "GameFontNormal")
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 210, -310)
    scroll:SetSize(523, 145)
    frame.preview = CreateFrame("EditBox", nil, scroll)
    frame.preview:SetMultiLine(true)
    frame.preview:SetAutoFocus(false)
    frame.preview:SetFontObject(ChatFontNormal)
    frame.preview:SetWidth(515)
    frame.preview:SetHeight(145)
    frame.preview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Preview can be selected/copied. Changes are reverted so creation always matches the visible preview.
    frame.preview:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(frame.body or "") end
    end)
    scroll:SetScrollChild(frame.preview)
    frame.create = button(frame, "创建角色宏", 207, -470, 170, function()
        local body, err = NS.Build(templates()[selected], frame.first:GetText(), frame.second:GetText())
        if not body then status(err) return end
        local name = NS.trim(frame.name:GetText())
        lastCreated = nil
        local index, message = NS.Create(name, body)
        if index then lastCreated = { name = name, body = body } end
        refresh()
        status(message)
    end)
    frame.pickup = button(frame, "取到鼠标", 389, -470, 148, function()
        if not lastCreated then return end
        local _, message = NS.Pickup(lastCreated.name, lastCreated.body)
        status(message)
    end)
    button(frame, "选中预览", 549, -470, 170, function() frame.preview:SetFocus(); frame.preview:HighlightText() end)
    frame.status = label(frame, "", 207, -513, 550, "GameFontHighlightSmall")
    frame.status:SetHeight(48)
    frame.status:SetJustifyV("TOP")
    label(frame, "/mypriest 打开牧师页\n/mymacro 打开宏工坊\n宏在 /macro 中管理", 22, -478, 163, "GameFontHighlightSmall")
    frame.first:SetScript("OnTextChanged", refresh)
    frame.second:SetScript("OnTextChanged", refresh)
    frame.name:SetScript("OnTextChanged", refresh)
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and picker then picker:Hide() end
        if frame:IsShown() then refresh() end
    end)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    UISpecialFrames[#UISpecialFrames + 1] = "MyForeverMacrosFrame"
    selectTemplate(1)
end

SLASH_MYFOREVERMACROS1 = "/mymacro"
SlashCmdList.MYFOREVERMACROS = function(message)
    local requested = NS.trim(message):lower()
    local kind = requested == "priest" and "priest" or (requested == "general" and "general" or nil)
    if not frame then
        local _, classToken
        if UnitClass then _, classToken = UnitClass("player") end
        family = kind or (classToken == "PRIEST" and "priest" or "general")
        createUI()
        return
    end
    if kind then selectFamily(kind); frame:Show(); return end
    if frame:IsShown() then frame:Hide() else frame:Show(); refresh() end
end
SLASH_MYFOREVERPRIEST1 = "/mypriest"
SlashCmdList.MYFOREVERPRIEST = function() SlashCmdList.MYFOREVERMACROS("priest") end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    print("|cff70d6ccMyForever|r 宏工坊已加载：/mypriest 牧师页，/mymacro 通用入口。")
end)
