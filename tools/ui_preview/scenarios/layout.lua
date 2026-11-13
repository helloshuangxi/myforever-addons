-- Layout mode (/myui) over the target panels, with the enemy panel mid-drag
-- next to the friendly one so a smart guide is visible.
local W = ...
local focus = assert(loadfile("tools/ui_preview/scenarios/targets.lua"))(W)
local NS = PREVIEW_TARGETS_NS
local S = MyForeverStyle
local friendly, enemy = NS.UI.friendly.frame, NS.UI.enemy.frame
friendly:ClearAllPoints(); friendly:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 640, -300)
enemy:ClearAllPoints(); enemy:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 640 + friendly:GetWidth() + 14, -304)
S.SetLayoutMode(true)
local bar = S.layout.bar
local tick = bar and bar.GetScript and bar:GetScript("OnUpdate")
if tick then tick(bar, 1) end
S.BeginDrag(enemy, nil)
local g = S.layout.grid
local update = g and g.GetScript and g:GetScript("OnUpdate")
if update then update(g, 1) end
focus[#focus + 1] = { name = "布局条", frame = bar }
return focus
