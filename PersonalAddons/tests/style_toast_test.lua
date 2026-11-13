-- MyForeverStyle.Toast and MyForeverTargets NS.Notify: feedback appears next
-- to the panel in use, carries its meaning in text, fades out by itself, and
-- never breaks the caller when the style module or the anchor is missing.
local checks = 0
local function ok(value, label) checks = checks + 1; if not value then error("FAIL " .. label, 2) end end

local function widget()
    local w = { shown = false, alpha = 1, points = {}, scripts = {} }
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsVisible() return self.shown end
    function w:SetAlpha(a) self.alpha = a end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:SetText(t) self.text = t end
    function w:GetStringWidth() return #(self.text or "") * 6 end
    function w:CreateTexture() return widget() end
    function w:CreateFontString() return widget() end
    function w:SetWidth(v) self.width = v end
    return setmetatable(w, { __index = function() return function() end end })
end
UIParent = widget(); UIParent.shown = true
function CreateFrame() return widget() end

dofile("PersonalAddons/shared/MyForeverStyle.lua")
local S = MyForeverStyle
ok(S.version >= 3 and type(S.Toast) == "function", "style v3 exposes Toast")

ok(S.Toast(nil, "") == nil and S.Toast(nil, nil) == nil, "empty message shows nothing")

local panel = widget(); panel.shown = true
local t = S.Toast(panel, "已记住，脱战后应用", "pending")
ok(t and t.shown and t.text.text == "已记住，脱战后应用", "toast shows its text")
ok(t.points[1][1] == "BOTTOM" and t.points[1][2] == panel and t.points[1][3] == "TOP", "anchored above the visible panel")
ok(t.width >= 120 and t.width <= 420, "width bounded")

local hidden = widget()
S.Toast(hidden, "x", "info")
ok(t.points[1][2] == UIParent, "falls back to screen top when the anchor is hidden")

local update = t.scripts.OnUpdate
update(t, 1.0); ok(t.shown and t.alpha == 1, "holds fully visible first")
update(t, 1.8); ok(t.shown and t.alpha < 1, "fades after the hold")
update(t, 0.5); ok(not t.shown, "hides itself")
S.Toast(panel, "again", "success")
ok(t.shown and t.alpha == 1 and t.age == 0, "reuses one frame and restarts")

-- Targets NS.Notify: chat record + short toast at the visible enemy panel.
local printed = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) printed[#printed + 1] = m end }
local NS = {}
local chunk = assert(loadfile("_forever_/Interface/AddOns/MyForeverTargets/Core.lua"))
chunk("MyForeverTargets", NS)
ok(type(NS.Notify) == "function", "Targets exposes Notify")
local enemy, friendly = widget(), widget()
enemy.shown, friendly.shown = true, true
NS.UI = { enemy = { frame = enemy }, friendly = { frame = friendly } }
NS.Notify("已记住设置，脱战后应用；战斗中名单与位置保持固定。", "已记住，脱战后应用", "pending")
ok(printed[#printed]:find("脱战后应用；战斗中", 1, true), "full message kept in chat")
ok(S.toastFrame.text.text == "已记住，脱战后应用" and S.toastFrame.points[1][2] == enemy, "short text beside enemy panel")
enemy.shown = false
NS.Notify("设置已应用。", nil, "success")
ok(S.toastFrame.points[1][2] == friendly and S.toastFrame.text.text == "设置已应用。", "next visible panel, message reused when no short text")

local saved = MyForeverStyle; MyForeverStyle = nil
NS.Notify("无样式时只写聊天。")
ok(printed[#printed]:find("无样式时", 1, true), "works without the style module")
MyForeverStyle = saved
MyForeverStyle.Toast = function() error("boom") end
NS.Notify("样式出错也不影响调用者。")
ok(printed[#printed]:find("样式出错", 1, true), "a failing toast never breaks the caller")

print("style toast checks: " .. checks)
