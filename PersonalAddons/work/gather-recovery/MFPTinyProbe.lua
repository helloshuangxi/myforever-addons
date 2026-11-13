-- Private in-memory experiment. Keep gathering alerts OFF; never add to the TOC.
local P = MFPTinyProbe or {}
MFPTinyProbe = P
local M = Minimap
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function number(v) return public(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function need(v) if not v then error("tiny-probe", 0) end return v end
local function anchors()
    local n, out = M:GetNumPoints(), {}
    need(number(n) and n >= 1 and n <= 16 and n % 1 == 0)
    for i = 1, n do
        local a = {M:GetPoint(i)}
        need(public(a[1]) and public(a[2]) and public(a[3]) and number(a[4]) and number(a[5]))
        out[i] = a
    end
    return out
end
local function owns(s, x, y)
    local a = anchors()
    if #a ~= #s.anchors then return false end
    for i, p in ipairs(a) do
        local q = s.anchors[i]
        if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3]
            or math.abs(p[4]-q[4]-x) > .01 or math.abs(p[5]-q[5]-y) > .01 then return false end
    end
    return true
end
local function unplace(s)
    if owns(s, 0, 0) then s.ox, s.oy, s.pending = 0, 0, nil; return true end
    local x, y = s.ox, s.oy
    if not owns(s, x, y) then
        if not s.pending or not owns(s, s.pending.x, s.pending.y) then return false end
        x, y = s.pending.x, s.pending.y
    end
    pcall(M.AdjustPointsOffset, M, -x, -y)
    if not owns(s, 0, 0) then return false end
    s.ox, s.oy, s.pending = 0, 0, nil
    return true
end
local function safe(s)
    need(public(MyForeverProfessionsDB) and type(MyForeverProfessionsDB) == "table" and MyForeverProfessionsDB.gatherAlerts == false)
    for _, fn in ipairs({InCombatLockdown, UnitIsDeadOrGhost}) do
        local v = fn("player"); need(public(v) and v == false)
    end
    need(M:IsProtected() == false and M:IsVisible() == true)
    for _, b in ipairs({"LeftButton", "RightButton", "MiddleButton", "Button4", "Button5"}) do need(IsMouseButtonDown(b) == false) end
    if IsMouselooking then need(IsMouselooking() == false) end
    local f = GetMouseFoci()
    need(public(f) and type(f) == "table" and public(f[1]))
    need(f[1] == nil or f[1] == WorldFrame or f[1] == M or (s and s.frames[f[1]]))
end
function P:Cleanup(reason)
    local s = self.active or self.recovery
    if not s then return self.last and self.last.restored end
    self.active = nil
    local good = true
    local function attempt(fn) local ok, v = pcall(fn); if not ok or v == false then good = false end end
    attempt(function() self.frame:SetScript("OnUpdate", nil); self.frame:UnregisterAllEvents() end)
    -- Remove displacement in its current coordinate system, THEN restore scale.
    attempt(function() return unplace(s) end)
    attempt(function()
        local v = M:GetScale(); need(number(v))
        if v ~= s.localScale then
            if v ~= s.appliedScale and v ~= s.pendingScale then return false end
            pcall(M.SetScale, M, s.localScale)
        end
        return M:GetScale() == s.localScale
    end)
    for _, c in ipairs(s.changes) do
        if c.changed then attempt(function()
            local v = c.get(c.frame); need(public(v))
            if v == c.before then return true end
            if v ~= c.applied then return false end
            pcall(c.set, c.frame, c.before)
            return c.get(c.frame) == c.before
        end) end
    end
    attempt(function() return owns(s, 0, 0) end)
    self.recovery = not good and s or nil
    self.last = {reason = reason or "manual", restored = good, samples = s.results}
    print("MFPTinyProbe done", self.last.reason, "restored", good)
    return good
end
local minerals = {
    ["铜矿"]="铜矿", ["铜矿脉"]="铜矿", ["Copper Vein"]="铜矿",
    ["锡矿"]="锡矿", ["锡矿脉"]="锡矿", ["Tin Vein"]="锡矿",
    ["银矿"]="银矿", ["银矿脉"]="银矿", ["Silver Vein"]="银矿",
    ["铁矿"]="铁矿", ["铁矿脉"]="铁矿", ["Iron Deposit"]="铁矿",
    ["金矿"]="金矿", ["金矿脉"]="金矿", ["Gold Vein"]="金矿",
    ["秘银矿"]="秘银矿", ["秘银矿脉"]="秘银矿", ["Mithril Deposit"]="秘银矿",
    ["瑟银矿脉"]="瑟银矿", ["Small Thorium Vein"]="瑟银矿", ["富瑟银矿脉"]="富瑟银矿", ["Rich Thorium Vein"]="富瑟银矿",
}
local function read()
    local d, found, restricted = C_TooltipInfo.GetMinimapMouseover(), {}, false
    if not public(d) then restricted = true
    elseif type(d) == "table" then
        if not public(d.lines) then restricted = true
        elseif type(d.lines) == "table" then
            for i, line in ipairs(d.lines) do
                if i > 128 then break end
                if not public(line) then restricted = true
                elseif type(line) == "table" then
                    local text = line.leftText
                    if not public(text) then restricted = true
                    elseif type(text) == "string" and #text <= 8192 then
                        for name in text:gmatch("[^\r\n]+") do
                            name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if minerals[name] then found[minerals[name]] = true end
                        end
                    end
                end
            end
        end
    end
    local names = {}; for name in pairs(found) do names[#names+1] = name end; table.sort(names)
    return {mineral = #names > 0, names = table.concat(names, ","), restricted = restricted}
end
local stages = {{"full-before", .60, -.40, 1}, {"tiny-center", 0, 0, .05}, {"full-after", .60, -.40, 1}}
local function place(s, index)
    need(unplace(s))
    need(P.active == s) -- unplace may synchronously cancel via a native hook
    local q = stages[index]
    local value = M:GetScale(); need(number(value) and (value == s.localScale or value == s.appliedScale))
    s.pendingScale = s.localScale * q[4] -- preserve old AND pending ownership if a hook throws
    if value ~= s.pendingScale then M:SetScale(s.pendingScale) end
    need(P.active == s)
    s.appliedScale, s.pendingScale = s.pendingScale, nil
    need(M:GetScale() == s.appliedScale and owns(s, 0, 0))
    local left, bottom, width, height, scale = M:GetLeft(), M:GetBottom(), M:GetWidth(), M:GetHeight(), M:GetEffectiveScale()
    need(number(left) and number(bottom) and number(width) and number(height) and number(scale) and width > 0 and height > 0 and scale > 0)
    local cx, cy = GetCursorPosition(); need(number(cx) and number(cy))
    local x, y = cx/scale - (q[2]+1)*width/2 - left, cy/scale - (q[3]+1)*height/2 - bottom
    s.pending = {x=x, y=y}
    M:AdjustPointsOffset(x, y)
    need(P.active == s)
    s.ox, s.oy, s.pending = x, y, nil
    need(owns(s, x, y))
    s.at, s.reads, s.cx, s.cy = index, 0, cx, cy
end
local function step(s)
    if GetTime()-s.started >= 2 then return P:Cleanup("timeout") end
    safe(s)
    need(owns(s, s.ox, s.oy))
    need(M:GetScale() == s.appliedScale)
    if s.at then
        local cx, cy = GetCursorPosition()
        need(number(cx) and number(cy) and math.abs(cx-s.cx) <= 1 and math.abs(cy-s.cy) <= 1)
        s.reads = s.reads + 1
        if s.reads == 1 then C_TooltipInfo.GetMinimapMouseover(); return end
        local r = read(); s.results[s.at] = r
        print("MFPTinyProbe", stages[s.at][1], "mineral", r.mineral, "names", r.names, "restricted", r.restricted)
        if s.at == #stages then return P:Cleanup("complete") end
    end
    place(s, (s.at or 0)+1)
end
function P:Start()
    if self.active or self.recovery then if not self:Cleanup("restart") then return false end end
    local ok = pcall(function()
        need(not MFPProbe or not MFPProbe.active)
        need(M and M.GetScale and M.SetScale and C_Timer and C_Timer.After and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover)
        safe()
        local s = {anchors=anchors(), localScale=M:GetScale(), changes={}, frames={}, results={}, ox=0, oy=0, started=GetTime()}
        need(number(s.localScale) and s.localScale > 0 and number(s.started))
        s.appliedScale = s.localScale
        local function change(f, get, set, applied, kind)
            need(type(get)=="function" and type(set)=="function")
            local v=get(f); need(public(v) and type(v)==kind)
            if kind=="number" then need(number(v)) end
            if v~=applied then s.changes[#s.changes+1]={frame=f,get=get,set=set,before=v,applied=applied} end
        end
        local n=0
        local function walk(f, depth)
            need(public(f) and f and depth<=8 and not s.frames[f]); s.frames[f]=true
            n=n+1; need(n<=128)
            local v=f:IsMouseClickEnabled(); need(public(v) and type(v)=="boolean")
            if v then need(f:IsProtected()==false); change(f,f.IsMouseClickEnabled,f.SetMouseClickEnabled,false,"boolean") end
            for _, child in ipairs({f:GetChildren()}) do walk(child,depth+1) end
        end
        walk(M,0)
        change(M,M.IsMouseWheelEnabled,M.EnableMouseWheel,false,"boolean")
        change(M,M.GetAlpha,M.SetAlpha,0,"number")
        self.frame=self.frame or CreateFrame("Frame")
        self.active=s
        self.frame:SetScript("OnEvent",function() P:Cleanup("input-or-world") end)
        for _,e in ipairs({"GLOBAL_MOUSE_DOWN","PLAYER_LEAVING_WORLD","PLAYER_REGEN_DISABLED","PLAYER_DEAD","MINIMAP_UPDATE_ZOOM","MINIMAP_UPDATE_TRACKING"}) do self.frame:RegisterEvent(e) end
        C_Timer.After(math.max(0,2-(GetTime()-s.started)),function() if P.active==s then P:Cleanup("timeout") end end)
        for _,c in ipairs(s.changes) do
            need(self.active==s); c.changed=true; c.set(c.frame,c.applied)
            need(self.active==s and c.get(c.frame)==c.applied)
        end
        self.frame:SetScript("OnUpdate",function() if not pcall(step,s) then P:Cleanup("error-or-input") end end)
    end)
    if not ok then
        if self.active then self:Cleanup("error") else print("MFPTinyProbe cancelled before changes") end
    end
    return ok and self.active~=nil
end
print("MFPTinyProbe loaded; gathering alerts must be OFF")
