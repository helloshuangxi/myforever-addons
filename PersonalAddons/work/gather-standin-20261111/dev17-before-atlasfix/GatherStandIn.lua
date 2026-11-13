local _, ns = ...

-- Local experimental replacement while the native minimap is being sampled.
-- Only native outdoor terrain tiles are drawn, with the player arrow.
-- There is no world-map illustration fallback and no invented resource blips.
-- Nothing here writes to the real minimap, configuration, or input.
local stand = {}
ns.GatherStandIn = stand
local frame, mask, arrow, tiles, decorations = nil, nil, nil, {}, {}
local active, elapsed = nil, 0
local MAX_TILES, TILE_YARDS = 64, 1600 / 3
local diag = {shown=false, reason="not-started", visibleTiles=0, renders=0}
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs

-- Only fixed labels from this module enter diagnostics. Never retain or expose
-- a native error string: it can contain unrelated UI or character text.
local renderStage = "idle"
local function stage(label)
    renderStage, diag.stage = label, label
end

local function public(value)
    if type(issecretvalue) ~= "function" then return true end
    local ok, hidden = pcall(issecretvalue, value)
    return ok and not hidden
end

local function number(value, low, high)
    return public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
        and (not low or value >= low) and (not high or value <= high)
end

local function tableValue(value)
    return public(value) and type(value) == "table"
end

local function call(fn, ...)
    if not public(fn) or type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function fail(reason)
    stand.Hide()
    diag.reason = reason
    return false, reason
end

local function rotating()
    local fn = C_CVar and C_CVar.GetCVar or GetCVar
    if type(fn) ~= "function" then return nil end
    local value = call(fn, "rotateMinimap")
    if not public(value) then return nil end
    if value == "0" or value == 0 or value == false then return false end
    if value == "1" or value == 1 or value == true then return true end
end

local function vector(value)
    if not public(value) or (type(value) ~= "table" and type(value) ~= "userdata") then return nil end
    local x, y = call(value.GetXY, value)
    if number(x, -100000, 100000) and number(y, -100000, 100000) then return x, y end
end

local function position()
    local indoors = call(IsIndoors)
    if not public(indoors) or type(indoors) ~= "boolean" then return nil, "indoor-state-unavailable" end
    if indoors then return nil, "indoor-terrain-unavailable" end
    if not C_Map or not C_Minimap then return nil, "map-api-unavailable" end
    local id = call(C_Map.GetBestMapForUnit, "player")
    if not number(id, 1, 10000000) or id ~= floor(id) then return nil, "player-map-unavailable" end
    -- UnitPosition and GetWorldPosFromMapPos both use north-positive X and
    -- west-positive Y, unlike the east/south tile indices. Independently
    -- available public readings must agree; never infer a resource position.
    local north, west, _, continent = call(UnitPosition, "player")
    local unitValid = number(north, -100000, 100000) and number(west, -100000, 100000)
        and number(continent, 0, 100000) and continent == floor(continent)
    local mapPos = call(C_Map.GetPlayerMapPosition, id, "player")
    local mx, my = vector(mapPos)
    local mapContinent, worldPos
    if number(mx, 0, 1) and number(my, 0, 1) then
        mapContinent, worldPos = call(C_Map.GetWorldPosFromMapPos, id, mapPos)
    end
    local mapNorth, mapWest = vector(worldPos)
    local mapValid = number(mapContinent, 0, 100000) and mapContinent == floor(mapContinent)
        and number(mapNorth) and number(mapWest)
    if unitValid and mapValid then
        if continent ~= mapContinent or abs(north-mapNorth) > 2 or abs(west-mapWest) > 2 then
            return nil, "world-position-mismatch"
        end
    elseif not unitValid then
        if not mapValid then return nil, "player-position-unavailable" end
        north, west, continent = mapNorth, mapWest, mapContinent
    end
    local all = ns.GatherTerrainTiles
    local terrain = tableValue(all) and all[continent]
    if not tableValue(terrain) or (continent ~= 0 and continent ~= 1) then return nil, "terrain-continent-unavailable" end
    local radius, facing = call(C_Minimap.GetViewRadius), call(GetPlayerFacing)
    if not number(radius, 1, 100000) then return nil, "minimap-radius-unavailable" end
    if not number(facing, -1000, 1000) then return nil, "player-facing-unavailable" end
    return {id=id, north=north, west=west, continent=continent, terrain=terrain,
        radius=radius, facing=facing, source=unitValid and "unit" or "public-map"}
end

local function fileID(value)
    return number(value, 1, 2147483647) and value == floor(value)
end

local function geometry(snapshot)
    if not tableValue(snapshot) then return nil end
    local left, bottom, w, h, scale = snapshot.left, snapshot.bottom, snapshot.width, snapshot.height, snapshot.scale
    local parentScale = UIParent and call(UIParent.GetEffectiveScale, UIParent)
    if not number(left, -100000, 100000) or not number(bottom, -100000, 100000)
        or not number(w, 16, 4096) or not number(h, 16, 4096)
        or not number(scale, .01, 10) or not number(parentScale, .01, 10) then return nil end
    local shape = snapshot.shape
    if not public(shape) or (shape ~= "ROUND" and shape ~= "SQUARE") then return nil end
    local ratio = scale / parentScale
    local native = snapshot.map
    local strata = native and call(native.GetFrameStrata, native) or "MEDIUM"
    local level = native and call(native.GetFrameLevel, native) or 1
    local validStrata = {BACKGROUND=true, LOW=true, MEDIUM=true, HIGH=true, DIALOG=true,
        FULLSCREEN=true, FULLSCREEN_DIALOG=true, TOOLTIP=true}
    if not public(strata) or not validStrata[strata] then strata="MEDIUM" end
    if not number(level, 0, 10000) then level=1 end
    return {left=left*ratio, bottom=bottom*ratio, width=w*ratio, height=h*ratio,
        parentScale=parentScale, shape=shape, strata=strata, level=level+1}
end

local function effectiveAlpha(source)
    local alpha, depth = 1, 0
    while source do
        if not public(source) or depth >= 16 then return nil end
        local value = call(source.GetAlpha,source)
        if not number(value,0,1) then return nil end
        alpha, depth = alpha*value, depth+1
        local getter=source.GetParent
        if not public(getter) or type(getter)~="function" then return nil end
        local ok,parent=pcall(getter,source)
        if not ok or not public(parent) then return nil end
        source=parent
    end
    return alpha
end

-- This is an identity allowlist of native fixed chrome, not a descendant
-- search. Third-party resource/quest/trainer pins under Minimap must not become
-- frozen substitute markers. Only a known border or a known button's immediate
-- Texture regions qualify; no source names or text are inspected.
local function chromeSources(snapshot)
    local direct, owners = {}, {}
    local function add(list,value)
        if public(value) and (type(value)=="table" or type(value)=="userdata") then list[value]=true end
    end
    for _,name in ipairs({"MinimapBorder","MinimapBorderTop","MinimapCompassTexture","MinimapCompassTextureUnderlay"}) do
        add(direct,_G[name])
    end
    for _,name in ipairs({"MinimapZoomIn","MinimapZoomOut","MiniMapWorldMapButton","MiniMapMailFrame","MiniMapTracking","QueueStatusButton"}) do
        add(owners,_G[name])
    end
    local map=snapshot.map
    if public(map) and map then
        add(owners,map.ZoomIn)
        add(owners,map.ZoomOut)
    end
    local cluster=_G.MinimapCluster
    if public(cluster) and cluster then
        local tracking=cluster.Tracking
        add(owners,tracking)
        if public(tracking) and tracking then add(owners,tracking.Button) end
    end
    return direct,owners
end

-- Snapshot public fixed texture pixels only. No text, frame scripts, tooltips,
-- names, anchors, or resource markers are copied, saved, or logged.
local function decorationSnapshot(snapshot, geo)
    if snapshot.parts == nil then return {} end
    if not tableValue(snapshot.parts) or #snapshot.parts > 256 then return nil end
    local result, seen = {}, {}
    local direct,owners=chromeSources(snapshot)
    local layerOrder = {BORDER=1, ARTWORK=2, OVERLAY=3, HIGHLIGHT=4}
    for i=1,#snapshot.parts do
        local source = snapshot.parts[i]
        if not public(source) or not source then return nil end
        stage("decoration-kind")
        local kind = call(source.GetObjectType,source)
        if not public(kind) or type(kind)~="string" then return nil end
        local fixed=direct[source]
        if kind=="Texture" and not fixed then
            local parent=call(source.GetParent,source)
            fixed=public(parent) and owners[parent]
        end
        if kind == "Texture" and fixed and not seen[source] then
            seen[source] = true
            stage("decoration-visible")
            local visible = call(source.IsVisible,source)
            if not public(visible) or type(visible) ~= "boolean" then return nil end
            if visible then
                stage("decoration-layer")
                local layer, sub = call(source.GetDrawLayer,source)
                if not public(layer) then return nil end
                -- A BACKGROUND may be the solid backing below the actual map;
                -- copying it over terrain would conceal the whole replacement.
                if layer ~= "BACKGROUND" then
                    if not layerOrder[layer] or not number(sub,-8,7) then return nil end
                    stage("decoration-rect")
                    local l,b,w,h = call(source.GetRect,source)
                    local scale = call(source.GetEffectiveScale,source)
                    if not number(l) or not number(b) or not number(w,0,4096) or not number(h,0,4096)
                        or not number(scale,.01,10) then return nil end
                    local ratio = scale/geo.parentScale
                    l,b,w,h = l*ratio,b*ratio,w*ratio,h*ratio
                    if w>0 and h>0 and l+w>geo.left-96 and l<geo.left+geo.width+96
                        and b+h>geo.bottom-96 and b<geo.bottom+geo.height+96 then
                        if w>geo.width+192 or h>geo.height+192 or #result>=96 then return nil end
                        stage("decoration-source")
                        local file = call(source.GetTexture,source)
                        if not (fileID(file) or (public(file) and type(file)=="string" and #file>0 and #file<=512)) then return nil end
                        stage("decoration-uv")
                        local ok,a,buv,c,d,e,f,g,hUV = pcall(source.GetTexCoord,source)
                        local uv={a,buv,c,d,e,f,g,hUV}
                        if not ok or #uv~=8 then return nil end
                        for j=1,8 do if not number(uv[j],-8,8) then return nil end end
                        stage("decoration-appearance")
                        local r,gc,bc,ac=call(source.GetVertexColor,source)
                        local alpha=effectiveAlpha(source)
                        local blend=call(source.GetBlendMode,source)
                        local blends={BLEND=true,ADD=true,MOD=true,ALPHAKEY=true,DISABLE=true}
                        if not number(r,0,1) or not number(gc,0,1) or not number(bc,0,1) or not number(ac,0,1)
                            or not number(alpha,0,1) or not public(blend) or not blends[blend] then return nil end
                        local rotation=0
                        if type(source.GetRotation)=="function" then rotation=call(source.GetRotation,source) end
                        if not number(rotation,-1000,1000) then return nil end
                        result[#result+1]={file=file,left=l-geo.left,bottom=b-geo.bottom,width=w,height=h,uv=uv,
                            r=r,g=gc,b=bc,a=ac,alpha=alpha,blend=blend,rotation=rotation,order=layerOrder[layer]*16+sub,index=#result+1}
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b) return a.order==b.order and a.index<b.index or a.order<b.order end)
    return result
end

-- ADT terrain is an east/south grid. Crop every intersecting tile directly
-- into our viewport. Require complete rectangular coverage even for a circle;
-- missing edge tiles leave the native minimap untouched rather than show holes.
local function layout(pos, geo)
    local perYard = geo.width / (2 * pos.radius)
    local size = TILE_YARDS * perYard
    local gx, gy = 32 - pos.west / TILE_YARDS, 32 - pos.north / TILE_YARDS
    local hx, hy = geo.width / (2*size), geo.height / (2*size)
    local x0, x1, y0, y1 = floor(gx-hx), ceil(gx+hx)-1, floor(gy-hy), ceil(gy+hy)-1
    if x0 < 0 or y0 < 0 or x1 >= 64 or y1 >= 64 then return nil, "terrain-edge-uncovered" end
    if (x1-x0+1)*(y1-y0+1) > MAX_TILES then return nil, "terrain-tile-budget" end
    local draw, area = {}, 0
    for y=y0,y1 do
        for x=x0,x1 do
            local file = pos.terrain[x*64+y]
            if not fileID(file) then return nil, "terrain-tile-unavailable" end
            local tileLeft, tileTop = (x-gx)*size+geo.width/2, (y-gy)*size+geo.height/2
            local l, r = max(0,tileLeft), min(geo.width,tileLeft+size)
            local t, b = max(0,tileTop), min(geo.height,tileTop+size)
            if l < r and t < b then
                draw[#draw+1] = {file=file, level=0, left=l, top=-t, width=r-l, height=b-t,
                    u0=(l-tileLeft)/size, u1=(r-tileLeft)/size,
                    v0=(t-tileTop)/size, v1=(b-tileTop)/size}
                area = area + (r-l)*(b-t)
            end
        end
    end
    if #draw == 0 or abs(area-geo.width*geo.height) > geo.width*geo.height*.000001 then
        return nil, "terrain-edge-uncovered"
    end
    return draw
end

local function create(round)
    if not frame then
        stage("frame-create")
        frame = CreateFrame("Frame", "MyForeverProfessionsGatherStandIn", UIParent)
        stage("frame-hide")
        frame:Hide()
        stage("frame-input")
        frame:EnableMouse(false)
        frame:EnableMouseWheel(false)
        if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
        if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
    end
    if round then
        if not mask then
            stage("mask-create")
            mask = frame:CreateMaskTexture()
        end
        stage("mask-position")
        mask:SetAllPoints(frame)
        -- The current client's legacy path can report SetTexture success while
        -- GetTexture remains nil. Prefer its verified native atlas and keep a
        -- strict loaded-resource check for either route. Only our art is masked.
        stage("mask-atlas-info")
        local atlas = "ui-hud-minimap-frame-generic-mask"
        local info = C_Texture and call(C_Texture.GetAtlasInfo,atlas)
        local loaded = false
        if tableValue(info) and fileID(info.file) and type(mask.SetAtlas) == "function" then
            stage("mask-atlas")
            local ok = pcall(mask.SetAtlas,mask,atlas)
            stage("mask-atlas-verify")
            local actual = call(mask.GetTexture,mask)
            loaded = ok and fileID(actual) and actual == info.file and call(mask.GetAtlas,mask) == atlas
        end
        if not loaded then
            stage("mask-texture")
            if mask:SetTexture("Textures\\MinimapMask") == false then error("map-mask-unavailable") end
            stage("mask-verify")
            local actual = call(mask.GetTexture,mask)
            if not public(actual) or (not fileID(actual) and (type(actual) ~= "string" or actual == "")) then
                error("map-mask-unavailable")
            end
        end
        diag.maskSource = loaded and "atlas" or "texture"
    else
        diag.maskSource = "none"
    end
    -- Do not invent a different border. Native fixed decoration may be
    -- preserved by the scanner; this renderer owns terrain and arrow only.
    if not arrow then
        stage("arrow-create")
        arrow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    end
    stage("arrow-atlas")
    arrow:SetAtlas("MinimapArrow")
    stage("arrow-verify")
    if arrow.GetAtlas and arrow:GetAtlas() ~= "MinimapArrow" then error("player-arrow-unavailable") end
    stage("arrow-position")
    arrow:SetPoint("CENTER", frame, "CENTER", 0, 0)
end

local function renderDecorations(pieces)
    for i=1,#pieces do
        local p,t=pieces[i],decorations[i]
        if not t then
            t=frame:CreateTexture(nil,"OVERLAY",nil,1)
            decorations[i]=t
        end
        stage("decoration-resource")
        if t.SetBlockingLoadsRequested then t:SetBlockingLoadsRequested(true) end
        if t:SetTexture(p.file)==false or call(t.GetTexture,t)~=p.file then error("decoration-resource-unavailable") end
        stage("decoration-geometry")
        t:SetDrawLayer("OVERLAY",1)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",p.left,p.bottom)
        t:SetSize(p.width,p.height)
        t:SetTexCoord(unpack(p.uv))
        t:SetRotation(p.rotation)
        t:SetVertexColor(p.r,p.g,p.b,p.a)
        t:SetAlpha(p.alpha)
        t:SetBlendMode(p.blend)
        t:Show()
    end
    for i=#pieces+1,#decorations do decorations[i]:Hide() end
    diag.visibleDecorations=#pieces
end

local function render(draw, geo, facing, decor)
    local round = geo.shape == "ROUND"
    create(round)
    stage("frame-scale")
    frame:SetScale(1)
    stage("frame-position")
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", geo.left, geo.bottom)
    stage("frame-size")
    frame:SetSize(geo.width, geo.height)
    stage("frame-strata")
    frame:SetFrameStrata(geo.strata)
    stage("frame-level")
    frame:SetFrameLevel(geo.level)
    for i=1,#draw do
        local p, tile = draw[i], tiles[i]
        if not tile then
            stage("tile-create")
            tile=frame:CreateTexture(nil,"BACKGROUND")
            tiles[i]=tile
        end
        if tile.standMasked ~= round then
            stage("tile-mask")
            if tile.standMasked then tile:RemoveMaskTexture(mask) end
            if round then tile:AddMaskTexture(mask) end
            tile.standMasked = round
        end
        stage("tile-draw-layer")
        tile:SetDrawLayer("BACKGROUND", p.level)
        stage("tile-sampling")
        if tile.SetSnapToPixelGrid then tile:SetSnapToPixelGrid(false) end
        if tile.SetTexelSnappingBias then tile:SetTexelSnappingBias(0) end
        if tile.SetBlockingLoadsRequested then tile:SetBlockingLoadsRequested(true) end
        stage("tile-texture")
        if tile:SetTexture(p.file, nil, nil, "TRILINEAR") == false then error("map-texture-unavailable") end
        stage("tile-verify")
        if not tile.GetTexture or call(tile.GetTexture,tile) ~= p.file then error("map-texture-unavailable") end
        stage("tile-uv")
        tile:SetTexCoord(p.u0, p.u1, p.v0, p.v1)
        stage("tile-size")
        tile:SetSize(p.width, p.height)
        stage("tile-position")
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", frame, "TOPLEFT", p.left, p.top)
        stage("tile-show")
        tile:Show()
    end
    stage("unused-tiles-hide")
    for i=#draw+1,#tiles do tiles[i]:Hide() end
    renderDecorations(decor or {})
    stage("arrow-size")
    arrow:SetSize(min(32,max(16,geo.width*.11)),min(32,max(16,geo.height*.11)))
    stage("arrow-rotation")
    arrow:SetRotation(facing)
    stage("arrow-show")
    arrow:Show()
    diag.visibleTiles, diag.renders = #draw, diag.renders+1
end

local function update()
    if not active then return false, "inactive" end
    stage("rotation-read")
    local rotation = rotating()
    if rotation ~= false then return false, rotation and "rotating-minimap" or "rotation-unavailable" end
    stage("position-read")
    local pos, reason = position()
    if not pos then return false, reason end
    if pos.id ~= active.id or pos.continent ~= active.continent then return false, "player-map-changed" end
    stage("parent-scale-read")
    local parentScale = UIParent and call(UIParent.GetEffectiveScale, UIParent)
    if not number(parentScale) or parentScale ~= active.geo.parentScale then return false, "parent-scale-changed" end
    local draw
    stage("layout")
    draw, reason = layout(pos,active.geo)
    if not draw then return false, reason end
    render(draw, active.geo, pos.facing, active.decor)
    return true
end

local function onUpdate(_, seconds)
    if not number(seconds, 0, 10000) then fail("update-time-unavailable") return end
    elapsed=elapsed+seconds
    if elapsed < .05 then return end
    elapsed=0
    local ok, success, reason = pcall(update)
    if not ok or not success then fail(ok and reason or "render-update-"..renderStage) end
end

function stand.Show(snapshot)
    stand.Hide()
    local ok, success, reason = pcall(function()
        stage("snapshot-read")
        local geo = geometry(snapshot)
        if not geo then return false, "snapshot-unavailable" end
        stage("rotation-read")
        local rotation = rotating()
        if rotation ~= false then return false, rotation and "rotating-minimap" or "rotation-unavailable" end
        stage("position-read")
        local pos, why = position()
        if not pos then return false, why end
        local draw
        stage("layout")
        draw, why = layout(pos,geo)
        if not draw then return false, why end
        stage("decoration-read")
        local decor=decorationSnapshot(snapshot,geo)
        if not decor then return false,"native-decoration-unavailable" end
        render(draw,geo,pos.facing,decor)
        active={id=pos.id,continent=pos.continent,geo=geo,decor=decor}
        diag.mapID, diag.width, diag.height = pos.id, geo.width, geo.height
        diag.terrainContinent, diag.positionSource = pos.continent, pos.source
        stage("frame-update-hook")
        frame:SetScript("OnUpdate",onUpdate)
        stage("frame-show")
        frame:Show()
        diag.shown, diag.reason = true, "ready"
        return true
    end)
    if not ok or not success then return fail(ok and reason or "render-prepare-"..renderStage) end
    return true
end

function stand.Hide()
    active, elapsed = nil, 0
    diag.shown, diag.visibleTiles, diag.visibleDecorations, diag.reason = false, 0, 0, "hidden"
    if frame then
        pcall(frame.SetScript,frame,"OnUpdate",nil)
        pcall(frame.Hide,frame)
    end
end

function stand.IsShown()
    return active ~= nil and frame ~= nil and frame:IsShown() and diag.shown
end

function stand.Diagnostics()
    local result={allocatedTiles=#tiles,allocatedDecorations=#decorations}
    for key,value in pairs(diag) do result[key]=value end
    return result
end
