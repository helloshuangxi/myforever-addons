local _, NS = ...
-- Shared layout hooks (grid while dragging, snap on release, /myui tags).
local function mfLayout(name, ...)
    local S = rawget(_G, "MyForeverStyle")
    local fn = type(S) == "table" and rawget(S, name)
    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        return ok and result or nil
    end
end
local frame, picker
local selected = 1
local family = "general"
local lastCreated
local function templates()
    return family == "priest" and NS.priestTemplates or NS.templates
end

local Style = MyForeverStyle
local function label(parent, text, x, y, width, level)
    local f = Style.Text(parent, level or "secondary", width, text)
    f:SetPoint("TOPLEFT", x, y)
    return f
end
local function button(parent, text, x, y, width, callback, kind)
    local b = Style.Button(parent, text, width, 24, callback, kind)
    b:SetPoint("TOPLEFT", x, y)
    return b
end
-- A choice in a list or tab row. The chosen one is marked, not greyed out:
-- it is disabled only so a second click does nothing.
local function choice(parent, text, x, y, width, callback, row)
    local b = button(parent, text, x, y, width, callback, "quiet")
    if row then
        -- List rows read left to right; tabs stay centred.
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b, "LEFT", 20, 0)
        b.isRow = true
        b.label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        b.label:SetJustifyH("LEFT")
    else
        b.styleRadius = 12
    end
    b:SetScript("OnDisable", nil)
    b:SetScript("OnEnable", nil)
    return b
end
local function mark(b, chosen)
    if b.isRow and Style.MarkSelected then
        -- 星辉 cursor for list rows; tabs keep the selected pill.
        Style.SetButtonKind(b, "quiet")
        Style.MarkSelected(b, chosen)
        if b.label then Style.SetType(b.label, "button", chosen and "text" or "secondary") end
    else
        Style.SetButtonKind(b, chosen and "selected" or "quiet")
    end
    b:SetEnabled(not chosen)
end
local function edit(parent, x, y, width)
    local e, holder = Style.Input(parent, width, 26)
    holder:SetPoint("TOPLEFT", x, y)
    e:SetMaxLetters(100)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end
local function status(message)
    frame.status:SetText(message or "")
end
local function refresh()
    local t = templates()[selected]
    mark(frame.generalTab, family == "general")
    mark(frame.priestTab, family == "priest")
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
        -- The tab already says which family; the row shows only what differs.
        b:SetText(entry and (family == "priest" and entry.label:gsub("^牧师%s*·%s*", "") or entry.label) or "")
        mark(b, i == selected)
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
        picker = CreateFrame("Frame", "MyForeverSpellPicker", frame, "BackdropTemplate")
        picker:SetSize(300, 372)
        picker:SetPoint("CENTER", frame, "CENTER", 90, 0)
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true)
        picker:EnableMouse(true)
        Style.Panel(picker, "popup")
        Style.TitleBar(picker, "选择本角色已学技能")
        picker.search = edit(picker, 12, -40, 276)
        picker.search:SetMaxLetters(60)
        picker.rows = {}
        picker.page = 1
        picker.note = label(picker, "", 12, -326, 276, "caption")
        picker.note:SetHeight(40)
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
            local row = choice(picker, "", 12, -74 - (i - 1) * 26, 276, function(self)
                if NS.InCombat() then picker:Hide() return end
                if self.spell then picker.destination:SetText(self.spell.name); picker.destination:ClearFocus(); picker:Hide(); refresh() end
            end, true)
            picker.rows[i] = row
        end
        picker.previous = button(picker, "上一页", 12, -290, 80, function() picker.page = picker.page - 1; update() end)
        picker.next = button(picker, "下一页", 208, -290, 80, function() picker.page = picker.page + 1; update() end)
        picker.pageText = label(picker, "", 100, -295, 100, "caption")
        picker.pageText:SetJustifyH("CENTER")
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
    frame = CreateFrame("Frame", "MyForeverMacrosFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 458)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Style.Panel(frame, "window")
    frame.bar = Style.TitleBar(frame, "宏工坊")
    if Style.HintBar then Style.HintBar(frame, { { "Esc", "关闭" } }, "/myui 摆放面板") end
    frame.bar.handle:EnableMouse(true)
    frame.bar.handle:RegisterForDrag("LeftButton")
    frame.bar.handle:SetScript("OnDragStart", function() frame:StartMoving(); mfLayout("BeginDrag", frame) end)
    frame.bar.handle:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); mfLayout("SnapToGrid", frame) end)
    mfLayout("RegisterLayout", frame, "宏助手")
    frame:SetScript("OnHide", function()
        frame.first:ClearFocus(); frame.second:ClearFocus(); frame.name:ClearFocus(); frame.preview:ClearFocus()
        if picker then picker:Hide() end
    end)
    -- Left column: what kind of macro. Right column: fill in, preview, create.
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 8, -36)
    side:SetPoint("BOTTOMLEFT", 8, 8)
    side:SetWidth(160)
    Style.Round(side, "side", 1, 10)
    frame.generalTab = choice(frame, "通用", 16, -44, 68, function() selectFamily("general") end)
    frame.priestTab = choice(frame, "牧师", 88, -44, 68, function() selectFamily("priest") end)
    frame.templates = {}
    for i = 1, math.max(#NS.templates, #NS.priestTemplates) do
        local templateIndex = i
        frame.templates[i] = choice(frame, "", 14, -78 - (i - 1) * 26, 148, function()
            selectTemplate(templateIndex)
        end, true)
    end
    -- Owned by the column frame: text on the window itself would sit under this child frame.
    local help = label(side, "/mymacro 打开宏工坊\n/mypriest 打开牧师页\n宏在 /macro 中管理", 10, -356, 140, "caption")
    help:SetSpacing(3)
    label(frame, "技能一（与游戏内名称一致）", 182, -42, 300, "caption")
    frame.first = edit(frame, 182, -58, 300)
    frame.firstPick = button(frame, "从法术本选", 490, -59, 96, function() showPicker(frame.first) end)
    label(frame, "技能二（仅 Shift 双技能使用）", 182, -92, 300, "caption")
    frame.second = edit(frame, 182, -108, 300)
    frame.secondPick = button(frame, "从法术本选", 490, -109, 96, function() showPicker(frame.second) end)
    label(frame, "角色宏名称", 182, -142, 200, "caption")
    frame.name = edit(frame, 182, -158, 200)
    frame.name:SetMaxLetters(16)
    frame.name:SetText(templates()[selected].name)
    frame.hint = label(frame, "", 182, -194, 404)
    frame.hint:SetHeight(50)
    frame.hint:SetJustifyV("TOP")
    frame.length = label(frame, "预览", 182, -250, 404, "caption")
    local well = CreateFrame("Frame", nil, frame)
    well:SetPoint("TOPLEFT", 182, -266)
    well:SetSize(404, 104)
    Style.Round(well, "side", 1, 8)
    local scroll = CreateFrame("ScrollFrame", nil, well, "UIPanelScrollFrameTemplate")
    if Style.SkinScroll then Style.SkinScroll(scroll) end
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    frame.preview = CreateFrame("EditBox", nil, scroll)
    frame.preview:SetMultiLine(true)
    frame.preview:SetAutoFocus(false)
    frame.preview:SetFontObject(ChatFontNormal)
    frame.preview:SetWidth(366)
    frame.preview:SetHeight(88)
    frame.preview:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Preview can be selected/copied. Changes are reverted so creation always matches the visible preview.
    frame.preview:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(frame.body or "") end
    end)
    scroll:SetScrollChild(frame.preview)
    -- One primary action per view: creating the macro is why the window is open.
    frame.create = button(frame, "创建角色宏", 182, -382, 120, function()
        local body, err = NS.Build(templates()[selected], frame.first:GetText(), frame.second:GetText())
        if not body then status(err) return end
        local name = NS.trim(frame.name:GetText())
        lastCreated = nil
        local index, message = NS.Create(name, body)
        if index then lastCreated = { name = name, body = body } end
        refresh()
        status(message)
    end, "primary")
    frame.pickup = button(frame, "取到鼠标", 310, -382, 96, function()
        if not lastCreated then return end
        local _, message = NS.Pickup(lastCreated.name, lastCreated.body)
        status(message)
    end)
    button(frame, "选中预览", 414, -382, 84, function() frame.preview:SetFocus(); frame.preview:HighlightText() end, "quiet")
    frame.status = label(frame, "", 182, -416, 404, "caption")
    frame.status:SetHeight(32)
    frame.status:SetJustifyV("TOP")
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
    print(Style.Prefix("宏工坊") .. " 已加载：/mypriest 牧师页，/mymacro 通用入口。")
end)
