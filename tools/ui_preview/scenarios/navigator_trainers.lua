local W = ...
C_Map = { GetBestMapForUnit = function() return 1455 end,
    GetMapInfo = function(id) return { name = id == 1455 and "铁炉堡" or ("地图" .. id), mapType = 3, parentMapID = 100 } end }
UnitFactionGroup = function() return "Alliance" end
local NS = {}
local root = ADDONS .. "MyForeverNavigator/"
for _, file in ipairs({ "Core.lua", "Data.lua", "Classification.lua" }) do assert(loadfile(root .. file))("MyForeverNavigator", NS) end
NS.Initialize(nil)
NS.DB.panel = { point = "CENTER", relativePoint = "CENTER", x = -300, y = 0 }
NS.DB.hud = { point = "CENTER", relativePoint = "CENTER", x = 320, y = 160 }
NS.GetPlayerPosition = function() return 1455, .3, .4 end
NS.GetLocationContext = function() return { mapID = 1455, x = .3, y = .4 } end
NS.MeasurePoint = function(p)
    if p.mapID == 1455 then return 60 + (p.npcID or 0) % 240, "same-map" end
    if p.mapID == 1452 then return nil, "other-continent" end
    return 400 + (p.npcID or 0) % 3000, "same-continent"
end
NS.Print = function() end
NS.Start = function(p) NS.DB.activeID = p.id; return true end
NS.Stop = function() NS.DB.activeID = nil end
NS.ShowOnMap = function() return true end
NS.ImportWaypoint = function() return nil, "没有地图标记" end
NS.UpdateArrival = function() end
NS.GetNavigation = function()
    if NS.DB.activeID then return { point = NS.GetPoint(NS.DB.activeID), mode = "direction", angle = .7, distance = 286,
        status = "导航状态", detail = "室外直线方位", nativeTracking = false, nativeReason = "未启用原生追踪" } end
    return { mode = "unavailable", status = "没有目标" }
end
assert(loadfile(root .. "UI.lua"))("MyForeverNavigator", NS)
NS.CreateUI()
if NS.ToggleUI then NS.ToggleUI() end
local panel = MyForeverNavigatorPanel or NS.Panel
if panel and not panel:IsShown() then panel:Show() end
local first
for _, p in ipairs(NS.Points) do if p.mapID == 1455 then first = p break end end
if first then NS.Start(first) end
for _, b in ipairs(NS.UI.npcCategories) do if b.category == "trainers" then b:Click() end end
if NS.RefreshUI then NS.RefreshUI() end
NS.RefreshHUD()
return { { name = "世界向导主窗", frame = panel }, { name = "导航HUD", frame = MyForeverNavigatorHUD } }
