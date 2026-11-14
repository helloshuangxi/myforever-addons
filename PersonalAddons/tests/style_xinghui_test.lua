-- MyForeverStyle v5 "星辉": window ornaments, selection cursor, menu sounds,
-- window motion, key-hint bar and the /myui sound switch.
local checks = 0
local function ok(value, label) checks = checks + 1; if not value then error("FAIL " .. label, 2) end end

local clock, combat = 100, false
function GetTime() return clock end
function InCombatLockdown() return combat end
local played = {}
function PlaySound(id, channel) played[#played + 1] = { id, channel } end
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840,
    U_CHAT_SCROLL_BUTTON = 1115, IG_MAINMENU_OPTION_CHECKBOX_ON = 856 }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local function widget()
    local w = { shown = true, scripts = {}, hooks = {}, textures = {}, anims = {} }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(v) self.shown = v and true or false end
    function w:IsShown() return self.shown end
    function w:SetScript(n, f) self.scripts[n] = f end
    function w:HookScript(n, f) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], f) end
    function w:SetText(t) self.text = t end
    function w:GetText() return self.text end
    function w:GetStringWidth() return 30 end
    function w:GetWidth() return 400 end
    function w:IsProtected() return false end
    function w:GetFont() return "Fonts\\Default.ttf", 15, "" end
    function w:SetFont(face, size) self.face, self.size = face, size; return true end
    function w:SetTextColor(r, g, b) self.color = { r, g, b } end
    function w:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
    function w:SetGradient(dir, a, b) self.gradient = { dir, a, b } end
    function w:SetRotation(r) self.rotation = r end
    function w:CreateTexture() local t = widget(); table.insert(self.textures, t); return t end
    function w:CreateFontString() return widget() end
    function w:CreateAnimationGroup()
        local g = { playing = false, anims = {} }
        function g:Play() self.playing = true end
        function g:Stop() self.playing = false end
        function g:SetLooping(v) self.looping = v end
        function g:CreateAnimation(kind)
            local a = setmetatable({ kind = kind }, { __index = function() return function() end end })
            table.insert(self.anims, a)
            return a
        end
        table.insert(self.anims, g)
        return g
    end
    return setmetatable(w, { __index = function() return function() end end })
end
UIParent = widget()
function UIParent:GetWidth() return 1000 end
function UIParent:GetHeight() return 600 end
SlashCmdList = {}
function CreateFrame() return widget() end

dofile("PersonalAddons/shared/MyForeverStyle.lua")
local S = MyForeverStyle
ok(S.version >= 5 and S.colors.gold and S.colors.titleText, "v5 palette has the ornament gold")

-- Titles: spaced when short and Chinese only.
ok(S.SpacedTitle("世界向导") == "世 界 向 导", "short Chinese title is spaced")
ok(S.SpacedTitle("选择本角色已学技能") == "选择本角色已学技能", "long title untouched")
ok(S.SpacedTitle("宏工坊 v2") == "宏工坊 v2", "mixed title untouched")
local fs = widget()
S.WindowTitle(fs, "宏工坊")
ok(fs.text == "宏 工 坊" and fs.face == S.titleFont and fs.size == 16, "title font, size and spacing")
local failing = widget()
function failing:SetFont(face, size) self.face, self.size = face, size; return face ~= S.titleFont end
S.WindowTitle(failing, "宏工坊")
ok(failing.face == "Fonts\\Default.ttf" and failing.size == 15, "falls back when the title font is missing")

-- Windows get corners and motion; HUD panels stay plain.
local window = widget()
S.Panel(window, "window")
ok(type(window.styleCorners) == "table" and #window.styleCorners == 8, "window has four L corners")
ok(window.styleOpen and window.hooks.OnShow and window.hooks.OnHide, "window has open motion and sound hooks")
local hud = widget()
S.Panel(hud, "hud")
ok(hud.styleCorners == nil or type(hud.styleCorners) ~= "table", "hud has no corners")
ok(not hud.hooks.OnShow, "hud has no motion")
S.Panel(window, "window")
ok(#window.styleCorners == 8, "corners are not duplicated")

-- Sounds: quiet right after load, then on; off in combat; switchable.
window.hooks.OnShow[1](window)
ok(#played == 0, "no sound in the first seconds after login")
ok(window.styleOpen.playing, "open motion still plays")
clock = clock + 10
window.styleOpen:Stop()
window.hooks.OnShow[1](window)
ok(#played == 1 and played[1][1] == 839 and played[1][2] == "SFX", "open sound on the SFX channel")
window.hooks.OnHide[1](window)
ok(played[#played][1] == 840, "close sound")
combat = true
window.styleOpen:Stop()
window.hooks.OnShow[1](window)
ok(#played == 2 and not window.styleOpen.playing, "no sound or motion in combat")
combat = false
local b = S.Button(UIParent, "确定", 60, 24, nil, "primary")
b.scripts.PostClick(b)
ok(played[#played][1] == 856, "primary button confirms")
local q = S.Button(UIParent, "取消", 60, 24, nil, "quiet")
q.scripts.PostClick(q)
ok(played[#played][1] == 1115, "other buttons select")
SlashCmdList.MYFOREVERLAYOUT("sound")
ok(MyForeverStyleDB and MyForeverStyleDB.sound == false and not S.SoundEnabled(), "/myui sound turns sound off")
local before = #played
q.scripts.PostClick(q)
ok(#played == before, "silent when switched off")
SlashCmdList.MYFOREVERLAYOUT(" 音效 ")
ok(S.SoundEnabled(), "/myui 音效 turns it back on")
local savedKits = SOUNDKIT; SOUNDKIT = nil
ok(S.Sound("open") == false, "missing sound kits never error")
SOUNDKIT = savedKits

-- Selection cursor: band + diamond, breathing, hidden when deselected.
local row = widget()
S.MarkSelected(row, false)
ok(row.styleMark == nil or type(row.styleMark) ~= "table", "nothing created for an unselected row")
S.MarkSelected(row, true)
local mark = row.styleMark
ok(mark.band.shown and mark.diamond.shown and mark.breath.playing, "selected: band, diamond, breathing")
ok(math.abs(mark.diamond.rotation - math.rad(45)) < 1e-9, "diamond is a rotated square")
ok(mark.band.gradient and mark.band.gradient[1] == "HORIZONTAL" and mark.band.gradient[3].a == 0, "band fades out to the right")
S.MarkSelected(row, false)
ok(not mark.band.shown and not mark.diamond.shown and not mark.breath.playing, "deselected: hidden and still")
combat = true
S.MarkSelected(row, true)
ok(mark.diamond.shown and not mark.breath.playing, "no breathing in combat")
combat = false

-- Hint bar: one key cap per item, trailing note, under the window.
local bar = S.HintBar(window, { { "左键", "选择" }, { "Esc", "关闭" } }, "/myui 摆放面板")
ok(bar and #bar.keys == 2 and bar.keys[1].key.text == "左键" and bar.keys[2].label.text == "关闭", "hint items")
ok(bar.trailing and bar.trailing.text == "/myui 摆放面板", "trailing note")
ok(S.HintBar(window, nil) == nil, "no items, no bar")

-- Title bar carries the title treatment and a rule.
local tb = S.TitleBar(window, "玩家行为")
ok(tb.title.text == "玩 家 行 为" and tb.rule and tb.rule.gradient, "title bar: spaced title and gold rule")

print("style xinghui checks: " .. checks)
