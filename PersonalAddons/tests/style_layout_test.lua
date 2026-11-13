-- MyForeverStyle layout: grid snap, smart guides (edge/centre magnet), Alt for
-- free placement, combat safety, and the /myui layout mode.
local checks = 0
local function ok(value, label) checks = checks + 1; if not value then error("FAIL " .. label, 2) end end
local function near(a, b) return math.abs(a - b) < 0.001 end

local alt, combat = false, false
function IsAltKeyDown() return alt end
function InCombatLockdown() return combat end

local function widget()
    local w = { shown = false, scripts = {} }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(v) self.shown = v and true or false end
    function w:IsVisible() return self.shown end
    function w:SetScript(n, f) self.scripts[n] = f end
    function w:SetText(t) self.text = t end
    function w:GetStringWidth() return 40 end
    function w:CreateTexture() return widget() end
    function w:CreateFontString() return widget() end
    return setmetatable(w, { __index = function() return function() end end })
end

-- UIParent: 1000 x 600 units, effective scale 1.
UIParent = widget(); UIParent.shown = true
function UIParent:GetWidth() return 1000 end
function UIParent:GetHeight() return 600 end
function UIParent:GetEffectiveScale() return 1 end

-- A panel positioned by its TOPLEFT against UIParent BOTTOMLEFT, in its own units.
local function panel(x, y, w, h, scale)
    local f = widget(); f.shown = true
    f.x, f.y, f.w, f.h, f.scale, f.point, f.protected = x, y, w, h, scale or 1, "TOPLEFT", false
    function f:GetPoint() return self.point, UIParent, "BOTTOMLEFT", self.x, self.y end
    function f:SetPoint(p, rel, rp, x2, y2) self.point, self.x, self.y = p, x2, y2 end
    function f:GetEffectiveScale() return self.scale end
    function f:GetLeft() return self.x end
    function f:GetRight() return self.x + self.w end
    function f:GetTop() return self.y end
    function f:GetBottom() return self.y - self.h end
    function f:IsProtected() return self.protected end
    return f
end

local slash
SlashCmdList = {}
function CreateFrame() return widget() end
dofile("PersonalAddons/shared/MyForeverStyle.lua")
local S = MyForeverStyle
ok(S.version >= 4 and S.SnapToGrid and S.BeginDrag and S.SetLayoutMode, "style v4 layout API")
ok(SLASH_MYFOREVERLAYOUT1 == "/myui" and type(SlashCmdList.MYFOREVERLAYOUT) == "function", "/myui registered")

-- Grid: measured from the screen centre (500, 300), step 8.
local a = panel(103, 397, 100, 50)
S.BeginDrag(a)
ok(S.layout.grid.shown, "grid shows while dragging")
ok(S.SnapToGrid(a) and near(a.x, 500 - 8 * 50) and near(a.y, 300 + 8 * 12), "snaps top-left to the 8-unit grid")
ok(not S.layout.grid.shown, "grid hides on release")
ok(a.point == "TOPLEFT", "keeps the frame's own anchor")

-- Scaled frame: offsets converted back into the frame's own units.
local scaled = panel(103, 397, 100, 50, 0.5)   -- rect in UIParent units: left 51.5, top 198.5
S.SnapToGrid(scaled)
ok(near(scaled.x * 0.5, 52) and near(scaled.y * 0.5, 196), "scale-aware grid snap")

-- Smart guides: B's left edge 5 units from A's right edge sticks to it,
-- even though that is off the grid.
S.RegisterLayout(a, "A")
S.RegisterLayout(a, "A again")
ok(#S.layout.frames == 1 and S.layout.frames[1].label == "A again", "register is idempotent")
local b = panel(a.x + 100 + 5, 251, 80, 40)
S.RegisterLayout(b, "B")
S.BeginDrag(b)
S.layout.grid.scripts.OnUpdate(S.layout.grid, 0.05)
ok(S.layout.guides.v and S.layout.guides.v.shown, "vertical guide shown while near an edge")
S.SnapToGrid(b)
ok(near(b.x, a.x + 100), "sticks to the other panel's right edge")
ok(near(b.y, 252), "other axis falls back to the grid")

-- Centre alignment with the screen centre wins over the grid.
local c = panel(500 - 30 + 3, 100, 60, 20)
S.SnapToGrid(c)
ok(near(c.x + 30, 500), "centres on the screen centre")

-- Hidden panels are not guide targets.
b.shown = false
local d = panel(a.x + 100 + 3, 151, 40, 40)
S.SnapToGrid(d)
ok(near(d.x, a.x + 100), "still sticks to visible A")
a.shown = false
local e = panel(203 + 3, 151, 40, 40)
S.SnapToGrid(e)
ok(near(e.x, 204), "invisible panels ignored, grid used")
a.shown, b.shown = true, true

-- The stand-in proxy case: the real panel being moved is excluded.
local real = panel(301, 500, 100, 50); S.RegisterLayout(real, "real")
local proxy = panel(305, 450, 100, 50)
S.BeginDrag(proxy, real)
S.SnapToGrid(proxy)
ok(near(proxy.x, 308), "proxy ignores the panel it stands in for and uses the grid")

-- Alt: free placement, nothing moves.
alt = true
local f = panel(123.4, 321.7, 50, 50)
ok(S.SnapToGrid(f) == false and near(f.x, 123.4) and near(f.y, 321.7), "Alt leaves the panel where dropped")
alt = false

-- Combat: protected frames are never touched; plain frames still snap.
combat = true
local prot = panel(123, 321, 50, 50); prot.protected = true
ok(S.SnapToGrid(prot) == false and prot.x == 123, "protected frame untouched in combat")
local plain = panel(123, 321, 50, 50)
ok(S.SnapToGrid(plain) == true, "plain frame snaps in combat")

-- Anchored to something other than UIParent: untouched.
local child = panel(123, 321, 10, 10)
function child:GetPoint() return "TOPLEFT", a, "BOTTOMLEFT", self.x, self.y end
ok(S.SnapToGrid(child) == false, "frames anchored elsewhere are left alone")

-- Layout mode cannot start in combat; entering combat closes it.
ok(S.SetLayoutMode(true) == false and not S.layout.active, "refused in combat")
combat = false
ok(S.SetLayoutMode(true) and S.layout.active and S.layout.bar.shown and S.layout.grid.shown, "layout mode opens")
local closedPanel = panel(0, 0, 10, 10); closedPanel.shown = false
S.RegisterLayout(closedPanel, "宏助手")
S.layout.bar.scripts.OnUpdate(S.layout.bar, 0.3)
ok(S.layout.bar.count.text:find("未打开：", 1, true) and S.layout.bar.count.text:find("宏助手", 1, true), "lists panels that are not open")
ok(S.layout.frames[1].tag and S.layout.frames[1].tag.shown, "open panels get a name tag")
local closedEntry
for _, entry in ipairs(S.layout.frames) do if entry.frame == closedPanel then closedEntry = entry end end
ok(closedEntry and not (closedEntry.tag and closedEntry.tag.shown), "closed panels get no tag")
S.ToggleLayoutMode()
ok(not S.layout.active and not S.layout.bar.shown and not S.layout.grid.shown, "toggle closes it")
for _, entry in ipairs(S.layout.frames) do ok(not (entry.tag and entry.tag.shown), "tag hidden after exit: " .. entry.label) end

print("style layout checks: " .. checks)
