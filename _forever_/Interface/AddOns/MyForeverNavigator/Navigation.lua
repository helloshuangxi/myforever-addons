local _, NS = ...

local call, number = NS.Call, NS.Number
local YARDS_TO_METRES, ARRIVAL_YARDS = 0.9144, 30
local pin, viewedID
local nativeOwned, nativeTracked, nativeMutation
local nativeMode, nativeReason = "hud", "使用独立方向指引"
local arrivalNotified

local function coord(x, y)
    return number(x) and number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end
local function xy(value)
    if (issecretvalue and issecretvalue(value)) or type(value) ~= "table" then return end
    local x, y = call(value.GetXY, value)
    if not number(x) or not number(y) then x, y = value.x, value.y end
    if number(x) and number(y) then return x, y end
end
local function info(mapID)
    if number(mapID) and mapID > 0 then return call(C_Map and C_Map.GetMapInfo, mapID) end
end
local function continent(mapID)
    local seen = {}
    for _ = 1, 16 do
        if not number(mapID) or seen[mapID] then return end
        seen[mapID] = true
        local map = info(mapID)
        if type(map) ~= "table" then return end
        if map.mapType == (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2) then return mapID end
        mapID = map.parentMapID
    end
end
local function activePoint()
    return NS.DB and NS.GetPoint(NS.DB.activeID)
end
local function destination(point)
    local map = info(point.mapID)
    return string.format("%s · %.1f, %.1f", point.zone or point.mapName or (map and map.name) or "目标地图", point.x * 100, point.y * 100)
end

function NS.GetPlayerPosition()
    local mapID = call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not number(mapID) or mapID <= 0 then return end
    local x, y = xy(call(C_Map and C_Map.GetPlayerMapPosition, mapID, "player"))
    if not coord(x, y) then return end
    return mapID, x, y
end

local function worldPosition(mapID, x, y)
    local vector = call(CreateVector2D, x, y)
    if not vector then return end
    local world, position = call(C_Map and C_Map.GetWorldPosFromMapPos, mapID, vector)
    local wx, wy = xy(position)
    if number(world) and number(wx) and number(wy) then return world, wx, wy end
end

-- One immutable player snapshot is shared by a whole search. Map orientation
-- is calculated once here rather than once for every NPC in the directory.
function NS.GetLocationContext()
    local context = {inInstance = call(IsInInstance) == true}
    local mapID, x, y = NS.GetPlayerPosition()
    context.mapID, context.x, context.y = mapID, x, y
    if not mapID or context.inInstance then return context end
    context.continent = continent(mapID)
    context.width, context.height = call(C_Map and C_Map.GetMapWorldSize, mapID)
    context.world, context.worldX, context.worldY = worldPosition(mapID, x, y)
    local baseWorld, bx, by = worldPosition(mapID, 0.5, 0.5)
    local eastWorld, ex, ey = worldPosition(mapID, 0.6, 0.5)
    local northWorld, nx, ny = worldPosition(mapID, 0.5, 0.4)
    if not context.world or baseWorld ~= context.world or eastWorld ~= context.world or northWorld ~= context.world then return context end
    ex, ey, nx, ny = ex - bx, ey - by, nx - bx, ny - by
    local eastLength, northLength = math.sqrt(ex * ex + ey * ey), math.sqrt(nx * nx + ny * ny)
    if not number(eastLength) or not number(northLength) or eastLength < 0.0001 or northLength < 0.0001 then return context end
    ex, ey, nx, ny = ex / eastLength, ey / eastLength, nx / northLength, ny / northLength
    local determinant = ex * ny - ey * nx
    if math.abs(determinant) >= 0.99 then context.basis = {ex=ex, ey=ey, nx=nx, ny=ny, determinant=determinant} end
    return context
end
local function sameMapDelta(context, target)
    if context.mapID ~= target.mapID then return end
    local width, height = context.width, context.height
    if not number(width) or not number(height) or width <= 0 or height <= 0 then return end
    local east, north = (target.x - context.x) * width, (context.y - target.y) * height
    local yards = math.sqrt(east * east + north * north)
    if number(yards) then return yards, east, north end
end
local function measureDelta(point, context)
    if not NS.ValidPoint(point) or type(context) ~= "table" or context.inInstance or not NS.ValidPoint(context) then return nil, nil, nil, "unavailable", "unknown" end
    local targetContinent = continent(point.mapID)
    if context.continent and targetContinent and context.continent ~= targetContinent then return nil, nil, nil, "other-continent", "other-continent" end
    local scope = context.mapID == point.mapID and "same-map" or (context.continent and context.continent == targetContinent and "same-continent" or "unknown")
    local map = info(point.mapID)
    if type(map) == "table" and number(map.mapType) and map.mapType >= 4 then return nil, nil, nil, "different-world", "unknown" end
    local targetWorld, tx, ty = worldPosition(point.mapID, point.x, point.y)
    if context.world and targetWorld then
        if context.world ~= targetWorld then return nil, nil, nil, "different-world", "unknown" end
        local dx, dy = tx - context.worldX, ty - context.worldY
        local yards = math.sqrt(dx * dx + dy * dy)
        if not number(yards) then return nil, nil, nil, "unavailable", scope end
        local b = context.basis
        if b then return yards, (dx*b.ny-dy*b.nx)/b.determinant, (b.ex*dy-b.ey*dx)/b.determinant, nil, scope end
        return yards, nil, nil, nil, scope
    end
    local yards, east, north = sameMapDelta(context, point)
    return yards, east, north, yards and nil or "unavailable", scope
end
function NS.MeasurePoint(point, context)
    local yards, _, _, _, scope = measureDelta(point, context or NS.GetLocationContext())
    return yards and yards * YARDS_TO_METRES or nil, scope
end

local function waypointRecord(value)
    if type(value) ~= "table" or (issecretvalue and issecretvalue(value)) then return end
    local x, y = xy(value.position)
    local record = {mapID=value.uiMapID, x=x, y=y}
    if NS.ValidPoint(record) then return record end
end
local function sameWaypoint(a, b)
    return a and b and a.mapID == b.mapID and math.abs(a.x-b.x) <= 0.0000001 and math.abs(a.y-b.y) <= 0.0000001
end
local function readWaypoint()
    return waypointRecord(call(C_Map and C_Map.GetUserWaypoint))
end
local function relinquishNative(reason)
    nativeOwned, nativeTracked = nil, false
    nativeMode, nativeReason = "external", reason
end
function NS.GetNativeTrackingStatus()
    if nativeOwned then
        if nativeOwned.kind == "quest" then
            local questID = call(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
            local tracking = call(C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest)
            if questID ~= nativeOwned.questID or tracking == false then
                relinquishNative("原生任务追踪已由玩家或其他插件更改；独立方向指引继续")
            elseif tracking ~= true then
                nativeMode, nativeReason = "marker", "任务追踪状态暂不可确认，使用独立方向指引"
            end
        else
            local tracking = call(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)
            if not sameWaypoint(nativeOwned, readWaypoint()) then
                relinquishNative("原生航点已由玩家或其他插件更改；独立方向指引继续")
            elseif nativeTracked and tracking == false then
                relinquishNative("原生追踪已切换；独立方向指引继续")
            elseif nativeTracked and tracking ~= true then
                nativeMode, nativeReason = "marker", "已设置原生航点，追踪状态暂不可确认"
            end
        end
    end
    return nativeMode, nativeReason
end
local function releaseOwnedTracking()
    -- GetUserWaypoint and the current tracking state are both needed before
    -- touching shared tracking. Never clear the user's map pin itself.
    if nativeOwned and nativeTracked and not call(InCombatLockdown) and not call(IsInInstance) then
        local setter, value
        if nativeOwned.kind == "quest" then
            if call(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) == nativeOwned.questID
                and call(C_SuperTrack and C_SuperTrack.IsSuperTrackingQuest) == true then
                setter, value = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID, 0
            end
        elseif sameWaypoint(nativeOwned, readWaypoint())
            and call(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint) == true then
            setter, value = C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint, false
        end
        if type(setter) == "function" then
            nativeMutation = true
            pcall(setter, value)
            nativeMutation = false
        end
    end
    nativeOwned, nativeTracked = nil, false
end
function NS.SetNativeWaypoint(point)
    releaseOwnedTracking()
    nativeMode, nativeReason = "hud", "使用独立方向指引"
    if not NS.ValidPoint(point) then nativeReason = "目的地坐标不可用"; return false, nativeReason end
    if call(IsInInstance) == true then nativeReason = "副本内不启用原生追踪"; return false, nativeReason end
    local map = info(point.mapID)
    if type(map) == "table" and number(map.mapType) and map.mapType >= 4 then nativeReason = "副本地点暂不启用原生追踪"; return false, nativeReason end
    if call(InCombatLockdown) == true then nativeReason = "战斗中使用独立指引；脱战后可再次开始导航"; return false, nativeReason end
    if call(C_Map and C_Map.CanSetUserWaypointOnMap, point.mapID) ~= true then nativeReason = "此地图暂不支持原生航点，使用独立方向指引"; return false, nativeReason end
    local waypoint = call(UiMapPoint and UiMapPoint.CreateFromCoordinates, point.mapID, point.x, point.y)
    if not waypoint then nativeReason = "原生航点接口暂不可用，使用独立方向指引"; return false, nativeReason end
    nativeMutation = true
    local marked = call(C_Map and C_Map.SetUserWaypoint, waypoint) == true
    if not marked then nativeMutation = false; nativeReason = "原生航点设置未成功，使用独立方向指引"; return false, nativeReason end
    local actual = readWaypoint()
    if sameWaypoint(point, actual) then nativeOwned = {kind="waypoint",mapID=actual.mapID,x=actual.x,y=actual.y} end
    local setter = C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint
    local ok, returned = false, false
    if type(setter) == "function" then ok, returned = pcall(setter, true) end
    nativeMutation = false
    nativeTracked = nativeOwned ~= nil and ok and returned ~= false and call(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint) == true
    if nativeTracked then nativeMode, nativeReason = "active", "原生航点追踪已启用"
    else nativeMode, nativeReason = "marker", "已设置原生航点；方向继续使用独立指引" end
    return true, nativeReason
end
function NS.SetNativeQuest(point)
    releaseOwnedTracking()
    nativeMode, nativeReason = "hud", "使用独立任务目标指引"
    if not NS.ValidPoint(point) or not number(point.questID) or point.questID <= 0 or point.questID % 1 ~= 0 then return false, nativeReason end
    if call(IsInInstance) == true or call(InCombatLockdown) == true then return false, nativeReason end
    local setter = C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID
    if type(setter) ~= "function" or type(C_SuperTrack.GetSuperTrackedQuestID) ~= "function"
        or type(C_SuperTrack.IsSuperTrackingQuest) ~= "function" then
        nativeReason = "客户端任务追踪接口暂不可用"
        return false, nativeReason
    end
    nativeMutation = true
    local ok, returned = pcall(setter, point.questID)
    local active = ok and returned ~= false and call(C_SuperTrack.GetSuperTrackedQuestID) == point.questID
        and call(C_SuperTrack.IsSuperTrackingQuest) == true
    nativeMutation = false
    if not active then nativeReason = "原生任务追踪未确认，使用坐标指引"; return false, nativeReason end
    nativeOwned, nativeTracked = {kind="quest",questID=point.questID}, true
    nativeMode, nativeReason = "active", "原生任务追踪已启用"
    return true, nativeReason
end
local function setNativeTarget(point)
    if point.nativeQuestTracking == true and NS.SetNativeQuest(point) then return true end
    return NS.SetNativeWaypoint(point)
end
function NS.OnNativeTrackingChanged()
    if not nativeMutation then NS.GetNativeTrackingStatus() end
end
function NS.ImportWaypoint(name)
    local point = readWaypoint()
    if not point then return nil, "请先在世界地图上放置一个有效的原生标记。" end
    for _, existing in ipairs(NS.DB and NS.DB.custom or {}) do
        if sameWaypoint(existing, point) then return existing end
    end
    name = NS.CleanText(name, 90)
    return NS.AddCustom(name ~= "" and name or "地图标记", point.mapID, point.x, point.y)
end
function NS.UpdateArrival(nav)
    if type(nav) ~= "table" or nav.mode ~= "arrived" or not nav.point or not NS.DB
        or nav.point.id ~= NS.DB.activeID or arrivalNotified == nav.point.id then return false end
    arrivalNotified = nav.point.id
    call(NS.Print, "已到达「" .. (nav.point.name or "目的地") .. "」的目标坐标附近，请在附近寻找。")
    return true
end
local function crossingHint()
    local faction = call(UnitFactionGroup, "player")
    if faction == "Alliance" then return "先查看联盟码头、船只或可用传送，前往目标大陆；抵达后继续查看方向。" end
    if faction == "Horde" then return "先查看部落飞艇塔、船只或可用传送，前往目标大陆；抵达后继续查看方向。" end
    return "先通过船只、飞艇或传送前往目标大陆，再继续查看方向。"
end

function NS.GetNavigation()
    local point = activePoint()
    if not point or not NS.ValidPoint(point) then
        if NS.DB and type(NS.DB.activeID) == "string" and NS.DB.activeID:match("^questie%-npc%-") then
            releaseOwnedTracking()
            nativeMode, nativeReason = "hud", "该 NPC 当前没有可见的参考位置"
            return {mode="unavailable",status=nativeReason,detail="等待 Questie 目录或目标相位就绪；可重新选择目的地。"}
        end
        return {mode = "unavailable", status = "尚未选择目的地", detail = "打开导航目录，选择 NPC 或添加自定义坐标。"}
    end
    local result = {point = point, mode = "unavailable", status = "当前位置暂不可用", detail = destination(point)}
    result.nativeMode, result.nativeReason = NS.GetNativeTrackingStatus()
    result.nativeKind = nativeOwned and nativeOwned.kind or nil
    local matchingOwner = nativeOwned and ((nativeOwned.kind == "quest" and point.nativeQuestTracking == true and point.questID == nativeOwned.questID)
        or (nativeOwned.kind == "waypoint" and sameWaypoint(point, nativeOwned)))
    result.nativeTracking = result.nativeMode == "active" and matchingOwner == true
    if result.nativeMode == "active" and not result.nativeTracking then
        result.nativeMode, result.nativeReason = "external", "原生航点当前标记其他地点；独立方向指引继续"
    end
    local context = NS.GetLocationContext()
    if context.inInstance then
        result.status, result.detail = "副本内暂停方向指引", "离开副本后恢复；" .. destination(point)
        return result
    end
    if not context.mapID then return result end
    local yards, east, north, reason, scope = measureDelta(point, context)
    result.scope = scope
    if reason == "other-continent" then
        result.mode, result.status = "cross", "需要跨大陆交通"
        result.detail = crossingHint() .. "\n" .. destination(point)
        return result
    end
    if reason == "different-world" then
        result.mode, result.status = "cross", "目标位于另一地图空间"
        result.detail = "请先前往目标区域；当前无法计算可靠直线方向。\n" .. destination(point)
        return result
    end
    if not yards then
        result.status = context.mapID == point.mapID and "地图尺寸暂不可用" or "跨区域坐标暂不可用"
        result.detail = "请打开目标地图查看坐标；方向数据恢复后自动继续。\n" .. destination(point)
        return result
    end
    result.distance = yards * YARDS_TO_METRES
    if yards <= ARRIVAL_YARDS then
        result.mode, result.status = "arrived", "已到目标坐标附近"
        result.detail = (point.questID and "请核对任务要求；到达参考坐标附近不代表任务已完成。\n" or "请在附近寻找 NPC；坐标不代表 NPC 当前实时位置。\n") .. destination(point)
        return result
    end
    local facing = call(GetPlayerFacing)
    if not number(facing) or not number(east) or not number(north) then
        result.status = "方向数据暂不可用"
        local absolute = ""
        if number(east) and number(north) then
            local directions = {"北", "东北", "东", "东南", "南", "西南", "西", "西北"}
            local index = math.floor(math.atan2(east, north) / (math.pi / 4) + 0.5) % 8 + 1
            absolute = "目标位于地图" .. directions[index] .. "侧。"
        end
        result.detail = absolute .. "直线距离可用；方向数据恢复后自动继续。\n" .. destination(point)
        return result
    end
    local bearing = math.atan2(east, north)
    result.angle = -(bearing + facing)
    result.mode, result.status = "direction", "朝目标坐标前进"
    result.detail = "箭头与距离为直线参考，请自行绕开山体、建筑及水域。\n" .. destination(point)
    return result
end

-- GetMapRectOnMap returns minX,maxX,minY,maxY in Forever's generated API docs.
-- Project only through actual parent relationships, never onto unrelated maps.
local function projectedPoint(point, mapID)
    local source, x, y, seen = point.mapID, point.x, point.y, {}
    for _ = 1, 16 do
        if source == mapID then if coord(x, y) then return x, y end; return end
        if seen[source] then return end
        seen[source] = true
        local map = info(source)
        local parent = type(map) == "table" and map.parentMapID
        if not number(parent) or parent <= 0 or type(C_Map and C_Map.GetMapRectOnMap) ~= "function" then return end
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, source, parent)
        if not ok or not number(minX) or not number(maxX) or not number(minY) or not number(maxY)
            or maxX <= minX or maxY <= minY then return end
        x, y = minX + x * (maxX - minX), minY + y * (maxY - minY)
        source = parent
    end
end

function NS.UpdateMapPin()
    local point, map = (viewedID and NS.GetPoint(viewedID)) or activePoint(), WorldMapFrame
    local visible = map and call(map.IsVisible or map.IsShown, map)
    if not point or not NS.ValidPoint(point) or not map or visible ~= true then
        if pin then pin:Hide() end
        return false
    end
    local canvas = call(map.GetCanvas, map)
    local mapID = call(map.GetMapID, map)
    local x, y = projectedPoint(point, mapID)
    local width, height = call(canvas and canvas.GetWidth, canvas), call(canvas and canvas.GetHeight, canvas)
    local scale = call(map.GetCanvasScale, map)
    if not canvas or not coord(x, y) or not number(width) or not number(height) or width <= 0 or height <= 0 then
        if pin then pin:Hide() end
        return false
    end
    if not number(scale) or scale <= 0 then scale = 1 end
    if not pin then
        pin = CreateFrame("Frame", "MyForeverNavigatorMapPin", canvas)
        pin:EnableMouse(false)
        pin:SetSize(28, 28)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints()
        pin.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        pin.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pin.label:SetPoint("TOP", pin, "BOTTOM", 0, -3)
        pin.label:SetTextColor(1, 0.83, 0.36)
        NS.MapPin = pin
    end
    pin:SetParent(canvas)
    pin:SetFrameLevel((call(canvas.GetFrameLevel, canvas) or 0) + 30)
    local inverseScale = 1 / scale
    pin:SetScale(inverseScale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", width * x / inverseScale, -height * y / inverseScale)
    pin.label:SetText(point.name or "导航目的地")
    pin:Show()
    return true
end

local function refresh()
    NS.UpdateMapPin()
    call(NS.RefreshHUD)
    call(NS.RefreshUI)
end

function NS.Start(id)
    local selected = type(id) == "table" and id or nil
    if selected then id = selected.id end
    local point
    if selected and selected.questie and NS.FreezeQuestiePoint then
        point = NS.FreezeQuestiePoint(selected)
    else
        point = NS.GetPoint(id)
        if point and point.questie and NS.FreezeQuestiePoint then point = NS.FreezeQuestiePoint(point) end
    end
    if not NS.DB or not point or not NS.ValidPoint(point) then return false, "目的地坐标不可用" end
    if NS.TransientPoint and NS.TransientPoint.id ~= id then NS.TransientPoint = nil end
    NS.DB.activeID = id
    NS.QuestieDestination = point.questie and point or nil
    viewedID = nil
    arrivalNotified = nil
    setNativeTarget(point)
    refresh()
    return true
end

function NS.StartTransient(point)
    if not NS.DB or type(point) ~= "table" or type(point.id) ~= "string" or #point.id > 100
        or not point.id:match("^quest:") or not number(point.questID) or point.questID <= 0
        or point.questID % 1 ~= 0 or not NS.ValidPoint(point) then return false, "任务目标坐标不可用" end
    local copy = {}
    for key, value in pairs(point) do copy[key] = value end
    for _, key in ipairs({"name","zone","service","note","tags","english"}) do
        if copy[key] ~= nil then copy[key] = NS.CleanText(copy[key], key == "note" and 600 or 180) end
    end
    if not copy.name or copy.name == "" then copy.name = "任务目标" end
    copy.transient, copy.category = true, "quest"
    copy.nativeQuestTracking = point.nativeQuestTracking == true
    NS.TransientPoint = copy
    return NS.Start(copy.id)
end
function NS.GetActiveQuestID()
    local point = activePoint()
    return point and point.transient and point.questID or nil
end

function NS.Stop()
    releaseOwnedTracking()
    nativeMode, nativeReason = "hud", "导航已停止"
    if NS.DB then NS.DB.activeID = nil end
    NS.TransientPoint = nil
    NS.QuestieDestination = nil
    viewedID = nil
    arrivalNotified = nil
    if pin then pin:Hide() end
    -- Native user waypoints may belong to the player or another addon.
    -- Stopping our HUD must never clear that shared state.
    call(NS.RefreshHUD)
    call(NS.RefreshUI)
    return true
end

function NS.ShowOnMap(id)
    if type(id) == "table" then id = id.id end
    local point = id and NS.GetPoint(id) or activePoint()
    if not point or not NS.ValidPoint(point) then return false, "目的地坐标不可用" end
    if call(InCombatLockdown) == true then return false, "战斗结束后再打开目标地图" end
    if not WorldMapFrame then
        call(UIParentLoadAddOn, "Blizzard_WorldMap")
        if not WorldMapFrame then call(C_AddOns and C_AddOns.LoadAddOn, "Blizzard_WorldMap") end
    end
    local map = WorldMapFrame
    if not map or type(map.SetMapID) ~= "function" then return false, "世界地图暂不可用" end
    local opened = false
    if type(OpenWorldMap) == "function" then opened = pcall(OpenWorldMap, point.mapID)
    elseif type(C_Map and C_Map.OpenWorldMap) == "function" then opened = pcall(C_Map.OpenWorldMap, point.mapID)
    elseif type(ShowUIPanel) == "function" then opened = pcall(ShowUIPanel, map) end
    if not opened or not pcall(map.SetMapID, map, point.mapID)
        or call(map.IsVisible or map.IsShown, map) ~= true or call(map.GetMapID, map) ~= point.mapID then
        return false, "暂时无法打开目标地图"
    end
    local marked = setNativeTarget(point)
    viewedID = point.id
    NS.UpdateMapPin()
    return true, marked and "marker" or "map"
end

-- Release ownership as soon as another feature changes the shared pin/track,
-- including switching away and back between our regular HUD refreshes.
if type(CreateFrame) == "function" then
    local listener = CreateFrame("Frame")
    if type(listener.RegisterEvent) == "function" and type(listener.SetScript) == "function" then
        listener:RegisterEvent("USER_WAYPOINT_UPDATED")
        listener:RegisterEvent("SUPER_TRACKING_CHANGED")
        listener:SetScript("OnEvent", NS.OnNativeTrackingChanged)
    end
end
