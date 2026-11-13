-- Usage (from repo root): lua tools/ui_preview/run.lua <scenario> <out.html> [width height]
-- Loads real addon Lua against the layout mock and writes an HTML drawing.
local here = "tools/ui_preview/"
local scenario, out, width, height = arg[1], arg[2], tonumber(arg[3]) or 1920, tonumber(arg[4]) or 1080
local W = dofile(here .. "wow_mock.lua")
local R = dofile(here .. "render.lua")
W.install(width, height)
ADDONS = "_forever_/Interface/AddOns/"
-- Scenarios that load a hand-picked file list still need the shared style.
do local f = loadfile("PersonalAddons/shared/MyForeverStyle.lua"); if f then f() end end
function LoadAddon(name, NS, files)
    NS = NS or {}
    local list = files
    if not list then
        list = {}
        for line in io.lines(ADDONS .. name .. "/" .. name .. ".toc") do
            line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" and line:sub(1, 1) ~= "#" then list[#list + 1] = line:gsub("\\", "/") end
        end
    end
    for _, file in ipairs(list) do assert(loadfile(ADDONS .. name .. "/" .. file))(name, NS) end
    return NS
end
local focus = assert(loadfile(here .. "scenarios/" .. scenario .. ".lua"))(W)
local caption = "布局模拟（非游戏截图）· " .. scenario .. " · UIParent " .. width .. "×" .. height
local f = assert(io.open(out, "w"))
f:write(R.page(W, caption))
f:close()
-- machine-readable bounds of the focus frames for cropping and footprint numbers
local meta = assert(io.open(out:gsub("%.html$", ".json"), "w"))
local parts = {}
for _, item in ipairs(focus or {}) do
    local b = R.bounds(W, item.frame)
    if b then parts[#parts + 1] = string.format('{"name":"%s","x":%.1f,"y":%.1f,"w":%.1f,"h":%.1f}', item.name, b.x, b.y, b.w, b.h) end
end
meta:write('{"width":' .. width .. ',"height":' .. height .. ',"frames":[' .. table.concat(parts, ",") .. "]}")
meta:close()
local unknown = {}
for k in pairs(W.unknown) do unknown[#unknown + 1] = k end
table.sort(unknown)
if os.getenv("UI_PREVIEW_DEBUG") then io.stderr:write("lenient methods: " .. table.concat(unknown, " ") .. "\n") end
