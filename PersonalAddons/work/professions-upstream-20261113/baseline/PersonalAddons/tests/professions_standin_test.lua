-- Native-terrain and native-widget simulation, not actual game acceptance.
local checks = 0
local function eq(actual, expected, label)
    checks=checks+1
    assert(actual == expected, label..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function near(actual, expected, label)
    checks=checks+1
    assert(math.abs(actual-expected) < .00001,label..": "..tostring(actual))
end
local SECRET={}
issecretvalue=function(v) return v == SECRET end
local frames, nativeWrites, settingWrites = {}, 0, 0
local badFile, throwFile, badAtlas, badMask, legacyMaskNil, maskAtlasFile
-- The native client keeps an independent atlas transform: GetTexCoord is
-- local to the selected sprite, not the sprite's rectangle in its sheet.
local chromeAtlas="MFPTestNativeChrome"
local atlasFiles={[chromeAtlas]=324001}
local atlasRects={[chromeAtlas]={.6357421875,.6669921875,.435546875,.466796875}}
C_Texture={GetAtlasInfo=function(name)
    local file,rect=atlasFiles[name],atlasRects[name]
    if file then return {file=file,leftTexCoord=rect[1],rightTexCoord=rect[2],topTexCoord=rect[3],bottomTexCoord=rect[4]} end
end}
local methods={}
function methods:Hide() self.shown=false end
function methods:Show() self.shown=true end
function methods:IsShown() return self.shown end
function methods:SetShown(value) self.shown=value end
function methods:EnableMouse(value) self.mouse=value end
function methods:EnableMouseWheel(value) self.wheel=value end
function methods:SetMouseClickEnabled(value) self.click=value end
function methods:SetMouseMotionEnabled(value) self.motion=value end
function methods:SetScript(key,value) self.scripts[key]=value end
function methods:SetScale(value) self.scale=value end
function methods:GetEffectiveScale()
    local inherited=self.parent and self.parent:GetEffectiveScale() or 1
    return (self.scale or 1)*inherited
end
function methods:GetScale() return self.scale or 1 end
function methods:GetFrameLevel() return self.level end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetFrameLevel(value) self.level=value end
function methods:SetAllPoints(value) self.all=value end
function methods:SetPoint(...) self.point={...} end
function methods:ClearAllPoints() self.point=nil end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetDrawLayer(layer,sub) self.layer,self.sublevel=layer,sub end
function methods:SetRotation(value) self.rotation=value end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetTexCoord(...) self.uv={...} end
function methods:SetTexture(file,wrapX,wrapY,filter)
    self.filter=filter
    if file == throwFile then error("texture denied") end
    if legacyMaskNil and file == "Textures\\MinimapMask" then self.texture=nil return true end
    if file == badFile or (badMask and file == "Textures\\MinimapMask") then self.texture=nil return false end
    self.texture=file
    self.atlas=nil
    return true
end
function methods:GetTexture() return self.texture end
function methods:SetSnapToPixelGrid(value) self.snap=value end
function methods:SetTexelSnappingBias(value) self.snappingBias=value end
function methods:SetBlockingLoadsRequested(value) self.blocking=value end
function methods:SetAtlas(value)
    self.atlas=not badAtlas and value or nil
    if atlasFiles[value] then
        self.texture=not badAtlas and atlasFiles[value]~=badFile and atlasFiles[value] or nil
        self.uv={0,0,0,1,1,0,1,1}
    end
    if value == "ui-hud-minimap-frame-generic-mask" then self.texture=not badAtlas and maskAtlasFile or nil end
end
function methods:GetAtlas() return self.atlas end
function methods:AddMaskTexture(value)
    self.mask=value
    self.maskAdds=(self.maskAdds or 0)+1
end
function methods:RemoveMaskTexture(value)
    assert(self.mask == value,"only own mask removed")
    self.mask=nil
end
local function widget()
    return setmetatable({shown=true,scripts={},textures={}}, {__index=methods})
end
function methods:CreateTexture(_,layer,_,sub)
    local t=widget()
    t.layer,t.sublevel,t.parent=layer,sub,self
    self.textures[#self.textures+1]=t
    return t
end
function methods:CreateMaskTexture()
    self.mask=widget()
    return self.mask
end
function methods:GetObjectType() return self.kind or "Texture" end
function methods:GetParent() return self.parent end
function methods:IsVisible() return self.shown end
function methods:GetRect()
    if self.rect then return unpack(self.rect) end
    local w,h=self.width or 0,self.height or 0
    if not self.point then return 0,0,w,h end
    local p=self.point
    local l,b,pw,ph=p[2]:GetRect()
    if p[1]=="BOTTOMLEFT" then return l+(p[4] or 0),b+(p[5] or 0),w,h end
    if p[1]=="TOPLEFT" then return l+(p[4] or 0),b+ph+(p[5] or 0)-h,w,h end
    if p[1]=="CENTER" then return l+pw/2+(p[4] or 0)-w/2,b+ph/2+(p[5] or 0)-h/2,w,h end
    return l,b,w,h
end
function methods:GetDrawLayer() return self.layer or "ARTWORK", self.sublevel or 0 end
function methods:GetTexCoord()
    local uv=self.sourceUV or self.uv or {0,0,0,1,1,0,1,1}
    if #uv==4 then return uv[1],uv[3],uv[1],uv[4],uv[2],uv[3],uv[2],uv[4] end
    return unpack(uv)
end
function methods:GetNumMaskTextures() return self.mask and 1 or 0 end
function methods:GetMaskTexture(index) assert(index==1,"native mask index supplied") return self.mask end
function methods:GetVertexColor() return unpack(self.vertex or {1,1,1,1}) end
function methods:GetAlpha() return self.alpha or 1 end
function methods:GetBlendMode() return self.blend or "BLEND" end
function methods:GetRotation() return self.rotation or 0 end
function methods:SetAlpha(value) self.alpha=value end
function methods:SetBlendMode(value) self.blend=value end
function methods:SetVertexColor(...) self.vertex={...} end
CreateFrame=function(kind,name,parent)
    local f=widget()
    f.kind,f.name,f.parent=kind,name,parent
    frames[#frames+1]=f
    return f
end
UIParent=widget()
UIParent.scale=1
local nativeLevel=2
local native=setmetatable({}, {__index=function(_,key)
    if key == "GetFrameStrata" then return function() return "MEDIUM" end end
    if key == "GetFrameLevel" then return function() return nativeLevel end end
    return function() nativeWrites=nativeWrites+1 error("native mutation: "..key) end
end, __newindex=function() nativeWrites=nativeWrites+1 error("native property mutation") end})
Minimap=native
SetCVar=function() settingWrites=settingWrites+1 end
SetBinding=function() settingWrites=settingWrites+1 end
local rotating, mapID, north, west, continent, radius, facing = "0",1426,0,0,0,1600/6,0
local indoors, unitUnavailable, unitRestricted, conversionUnavailable, conversionMismatch, positionError
local normRestricted, worldRestricted, artReads, unitThrows, indoorThrows = false,false,0,false,false
local worldContinent
C_CVar={GetCVar=function() return rotating end}
GetPlayerFacing=function() return facing end
C_Minimap={GetViewRadius=function() return radius end}
IsIndoors=function() if indoorThrows then error("private indoor") end if indoors==nil then return false end return indoors end
UnitPosition=function(unit)
    eq(unit,"player","only player position read")
    if unitThrows then error("private position") end
    if unitUnavailable then return nil end
    return unitRestricted and SECRET or north,west,4,continent
end
C_Map={
    GetBestMapForUnit=function() return mapID end,
    GetPlayerMapPosition=function(id,unit)
        if positionError then error("private position") end
        return {GetXY=function()
            return normRestricted and SECRET or (500-west)/1000,(500-north)/1000
        end}
    end,
    -- Independent zone transform: east/south normalized coordinates become
    -- north/west world coordinates. An accidental axis swap cannot pass.
    GetWorldPosFromMapPos=function(id,pos)
        if conversionUnavailable then return nil end
        local x,y=pos:GetXY()
        return worldContinent or continent,{GetXY=function()
            return worldRestricted and SECRET or 500-y*1000+(conversionMismatch or 0),500-x*1000
        end}
    end,
    GetMapArtLayers=function() artReads=artReads+1 error("illustration forbidden") end,
    GetMapArtLayerTextures=function() artReads=artReads+1 error("illustration forbidden") end,
}
local ns={}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/GatherTerrainTiles.lua"))("MyForeverProfessions",ns)
local realData=ns.GatherTerrainTiles
local counts={}
for c,data in pairs(realData) do
    eq(c==0 or c==1,true,"only supported native continents")
    local count=0
    for key,file in pairs(data) do
        eq(type(key)=="number" and key%1==0 and key>=0 and key<4096,true,"bounded ADT key")
        eq(type(file)=="number" and file%1==0 and file>0 and file<2147483648,true,"native terrain file ID")
        count=count+1
    end
    counts[c]=count
end
eq(counts[0],736,"Eastern Kingdoms static fact count")
eq(counts[1],988,"Kalimdor static fact count")
eq(realData[0][1526],5313057,"known source fact retained")
eq(realData[2991],nil,"later-build island excluded")
local dataFile=assert(io.open("_forever_/Interface/AddOns/MyForeverProfessions/GatherTerrainTiles.lua")):read("*a")
eq(dataFile:find("MIT License",1,true)~=nil,true,"MIT attribution retained")
eq(dataFile:find("Copyright (c) 2026 OpenMap contributors",1,true)~=nil,true,"OpenMap copyright retained")
eq(dataFile:find("https://www.curseforge.com/wow/addons/node-sight/files/9550390",1,true)~=nil,true,"immutable source provenance retained")
local fixtures={[0]={},[1]={}}
for c=0,1 do
    for x=27,36 do for y=27,36 do fixtures[c][x*64+y]=100000+c*10000+x*100+y end end
end
ns.GatherTerrainTiles=fixtures
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/GatherStandIn.lua"))("MyForeverProfessions",ns)
local stand=ns.GatherStandIn
local snapshot={map=native,left=800,bottom=500,width=200,height=200,scale=1,shape="ROUND"}
local function freshSnapshot()
    return {map=native,left=800,bottom=500,width=200,height=200,scale=1,shape="ROUND"}
end
local function current() return frames[1] end
local function arrow()
    for _,t in ipairs(current().textures) do if t.atlas == "MinimapArrow" then return t end end
end
local function visibleTiles()
    local result={}
    for _,t in ipairs(current().textures) do
        if type(t.texture)=="number" and t.shown then result[#result+1]=t end
    end
    return result
end
local function tick(seconds)
    local fn=current().scripts.OnUpdate
    if fn then fn(current(),seconds or .06) end
end
local function denied(reason,label,snap)
    local ok,actual=stand.Show(snap or snapshot)
    eq(ok,false,label.." rejected")
    eq(actual,reason,label.." reason")
    eq(stand.IsShown(),false,label.." hidden")
    eq(stand.Diagnostics().visibleTiles,0,label.." no placeholder")
end
local function tileByID(file)
    for _,t in ipairs(visibleTiles()) do if t.texture==file then return t end end
end

eq(stand.IsShown(),false,"starts hidden")
eq(stand.Show(snapshot),true,"native terrain prepared")
local f=current()
eq(#frames,1,"one owned frame")
eq(f.parent,UIParent,"own root parent")
for _,key in ipairs({"mouse","wheel","click","motion"}) do eq(f[key],false,key.." passes through") end
eq(f.level,2,"preserve native frame level without lifting proxy")
eq(f.strata,"MEDIUM","read native strata")
near(f.width,200,"original width")
near(f.height,200,"original height")
near(f.point[4],800,"original left")
near(f.point[5],500,"original bottom")
eq(f.mask.all,f,"full native circle mask")
local drawn=visibleTiles()
eq(#drawn,4,"origin at native terrain seam")
local northwest=tileByID(fixtures[0][31*64+31])
local northeast=tileByID(fixtures[0][32*64+31])
local southwest=tileByID(fixtures[0][31*64+32])
local southeast=tileByID(fixtures[0][32*64+32])
for i,t in ipairs(drawn) do
    near(t.width,100,"half tile width "..i)
    near(t.height,100,"half tile height "..i)
    eq(t.mask,f.mask,"round mask "..i)
    eq(t.filter,"TRILINEAR","native terrain filter "..i)
    near(t.vertex[1],.87,"terrain calibration red "..i)
    near(t.vertex[2],.84,"terrain calibration green "..i)
    near(t.vertex[3],.80,"terrain calibration blue "..i)
    near(t.vertex[4],1,"terrain remains fully opaque "..i)
    eq(t.snap,false,"pixel snapping disabled "..i)
    eq(t.snappingBias,0,"texel snapping disabled "..i)
    eq(t.blocking,true,"resource verified synchronously "..i)
    for j=1,4 do eq(t.uv[j]>=0 and t.uv[j]<=1,true,"bounded UV "..i.."/"..j) end
end
near(northwest.uv[1],.5,"northwest west half clipped")
near(northwest.uv[3],.5,"northwest north half clipped")
near(northeast.point[4],100,"east tile joins at center")
near(southwest.point[5],-100,"south tile joins at center")
near(southeast.uv[2],.5,"southeast east half clipped")
near(southeast.uv[4],.5,"southeast south half clipped")
near(northwest.point[4]+northwest.width,northeast.point[4],"horizontal seam exact")
near(northwest.point[5]-northwest.height,southwest.point[5],"vertical seam exact")
eq(arrow().point[1],"CENTER","player arrow stays centered")
eq(arrow().shown,true,"player arrow visible")
near(arrow().rotation,0,"initial player heading")
eq(stand.Diagnostics().positionSource,"unit","public unit position used")
eq(stand.Diagnostics().terrainContinent,0,"correct native continent")
eq(artReads,0,"no illustrated world-map fallback")

-- Tint is reapplied to pooled terrain, without tinting arrow or decoration.
local pooled=visibleTiles()[1]
pooled:SetVertexColor(1,.1,.2,.3)
arrow():SetVertexColor(.95,.94,.93,.92)
nativeLevel=7
eq(stand.Show(snapshot),true,"reused terrain and changed native frame level")
eq(f.level,7,"new native level remains unchanged on reuse")
for i,t in ipairs(visibleTiles()) do
    near(t.vertex[1],.87,"reused terrain red "..i)
    near(t.vertex[2],.84,"reused terrain green "..i)
    near(t.vertex[3],.80,"reused terrain blue "..i)
    near(t.vertex[4],1,"reused terrain opacity "..i)
end
near(arrow().vertex[1],.95,"terrain tint leaves arrow red unchanged")
near(arrow().vertex[2],.94,"terrain tint leaves arrow green unchanged")
near(arrow().vertex[3],.93,"terrain tint leaves arrow blue unchanged")
near(arrow().vertex[4],.92,"terrain tint leaves arrow alpha unchanged")
nativeLevel=2
eq(stand.Show(snapshot),true,"native level returns with another lease")
eq(f.level,2,"no frame level inflation over successive leases")

-- A northward player move moves the ground south; eastward moves it west.
north=50
facing=1.7
local renders=stand.Diagnostics().renders
tick(.02)
eq(stand.Diagnostics().renders,renders,"bounded redraw interval")
tick(.04)
northwest=tileByID(fixtures[0][31*64+31])
near(northwest.height,118.75,"north axis moves seam south")
near(northwest.width,100,"north move does not rotate axes")
near(arrow().rotation,1.7,"heading updated independently")
west=-50
tick()
northwest=tileByID(fixtures[0][31*64+31])
near(northwest.width,81.25,"east axis moves seam west")
near(northwest.height,118.75,"east move leaves north crop unchanged")
north,west,facing=0,0,0

stand.Hide()
eq(stand.IsShown(),false,"hide removes stand-in")
eq(f.scripts.OnUpdate,nil,"hide removes update callback")
eq(f.shown,false,"frame hidden")
stand.Hide()
eq(stand.Show(snapshot),true,"show can restart")
eq(#frames,1,"show reuses frame")
local copy=stand.Diagnostics()
copy.reason="external"
eq(stand.Diagnostics().reason,"ready","diagnostics copied")
UIParent.scale=.8
snapshot.scale=1.2
eq(stand.Show(snapshot),true,"physical scale conversion")
near(f.width,300,"logical width converted")
near(f.width*UIParent.scale,snapshot.width*snapshot.scale,"same physical width")
near(f.point[4]*UIParent.scale,snapshot.left*snapshot.scale,"same physical left")
near(tileByID(fixtures[0][31*64+31]).uv[1],.5,"scale leaves world crop unchanged")
UIParent.scale=1
snapshot=freshSnapshot()
snapshot.shape="SQUARE"
eq(stand.Show(snapshot),true,"square native shape")
for i,t in ipairs(visibleTiles()) do eq(t.mask,nil,"square removes circle mask "..i) end
for _,t in ipairs(f.textures) do eq(t.color,nil,"no invented gold border") end
snapshot.shape="ROUND"
eq(stand.Show(snapshot),true,"round restored")

-- View radius is the native zoom authority; a rectangular minimap keeps yard
-- scale equal in X and Y instead of stretching the background.
radius=1600/12
eq(stand.Show(snapshot),true,"native zoom in")
near(tileByID(fixtures[0][31*64+31]).uv[1],.75,"zoom crops closer terrain")
snapshot.height=100
eq(stand.Show(snapshot),true,"rectangular viewport")
near(tileByID(fixtures[0][31*64+31]).height,50,"rectangular pixel height")
near(tileByID(fixtures[0][31*64+31]).uv[3],.875,"rectangular yard aspect ratio")
snapshot=freshSnapshot()
radius=1600/6
-- Exactly one tile: adjacent missing tiles that do not intersect are not needed.
north,west=1600/6,1600/6
local saved=fixtures[0][32*64+32]
fixtures[0][32*64+32]=nil
eq(stand.Show(snapshot),true,"exact tile boundary does not need outside neighbor")
eq(#visibleTiles(),1,"exactly one native tile covers viewport")
fixtures[0][32*64+32]=saved
north,west=0,0
fixtures[0][32*64+32]=nil
denied("terrain-tile-unavailable","missing visible corner")
fixtures[0][32*64+32]=saved
fixtures[0][31*64+31]=SECRET
denied("terrain-tile-unavailable","restricted tile ID")
fixtures[0][31*64+31]=103131
continent=1
eq(stand.Show(snapshot),true,"Kalimdor native data")
eq(tileByID(fixtures[1][31*64+31])~=nil,true,"Kalimdor file selected")
continent=2991
denied("terrain-continent-unavailable","unsupported later island")
continent=0
local all=ns.GatherTerrainTiles
ns.GatherTerrainTiles=nil
denied("terrain-continent-unavailable","missing static data")
ns.GatherTerrainTiles=all
north,west=30000,30000
denied("terrain-edge-uncovered","outside native ADT extent")
north,west=0,0
radius=100000
denied("terrain-edge-uncovered","extreme radius unsupported")
radius=2500
denied("terrain-tile-budget","bounded terrain enumeration")
radius=1600/6

-- A separately public map conversion can supply coordinates when UnitPosition
-- is unavailable; conflicting public observations must fail closed.
unitUnavailable=true
eq(stand.Show(snapshot),true,"public map conversion independent fallback")
eq(stand.Diagnostics().positionSource,"public-map","conversion source reported without coordinates")
unitUnavailable=false
conversionMismatch=30
denied("world-position-mismatch","axes mismatch detected")
conversionMismatch=nil
worldContinent=1
denied("world-position-mismatch","continent mismatch detected")
worldContinent=nil
unitRestricted=true
eq(stand.Show(snapshot),true,"restricted unit reading ignored in favor of public conversion")
worldRestricted=true
denied("player-position-unavailable","both coordinate sources restricted")
unitRestricted,worldRestricted=false,false
unitUnavailable,conversionUnavailable=true,true
denied("player-position-unavailable","both coordinate sources missing")
unitUnavailable,conversionUnavailable=false,false
conversionUnavailable=true
eq(stand.Show(snapshot),true,"public UnitPosition does not require map conversion API")
conversionUnavailable=false
unitThrows=true
eq(stand.Show(snapshot),true,"unit API exception can use independent public conversion")
unitThrows=false

indoors=true
denied("indoor-terrain-unavailable","indoor map cannot use outdoor ground")
indoors=SECRET
denied("indoor-state-unavailable","restricted indoor status")
indoors=nil
indoorThrows=true
denied("indoor-state-unavailable","indoor API failure")
indoorThrows=false
rotating="1"
denied("rotating-minimap","rotated minimap unsupported")
rotating=SECRET
denied("rotation-unavailable","restricted rotation")
rotating="0"
mapID=SECRET
denied("player-map-unavailable","restricted map ID")
mapID=1426
facing=SECRET
denied("player-facing-unavailable","restricted heading")
facing=0
radius=SECRET
denied("minimap-radius-unavailable","restricted view radius")
radius=1600/6
local badSnap=freshSnapshot()
badSnap.left=SECRET
denied("snapshot-unavailable","restricted geometry",badSnap)
badSnap=freshSnapshot()
badSnap.shape="CORNER-TOPLEFT"
denied("snapshot-unavailable","unknown shape",badSnap)
badFile=103131
denied("render-prepare-tile-texture","missing native terrain asset")
badFile=nil
throwFile=103231
denied("render-prepare-tile-texture","native texture exception")
throwFile=nil
badMask=true
denied("render-prepare-mask-texture","missing round mask")
badMask=false
badAtlas=true
denied("render-prepare-arrow-verify","missing arrow asset")
badAtlas=false

-- When any public source disappears during a lease the scanner sees false and
-- restores the real map. No partial replacement survives an update failure.
eq(stand.Show(snapshot),true,"runtime transaction ready")
mapID=1427
tick()
eq(stand.IsShown(),false,"map epoch invalidates renderer")
eq(stand.Diagnostics().reason,"player-map-changed","map epoch reason")
mapID=1426
eq(stand.Show(snapshot),true,"map recovery")
indoors=true
tick()
eq(stand.IsShown(),false,"indoor change cancels renderer")
indoors=nil
eq(stand.Show(snapshot),true,"outdoor recovery")
rotating="1"
tick()
eq(stand.IsShown(),false,"runtime rotation cancels renderer")
rotating="0"
eq(stand.Show(snapshot),true,"rotation recovery")
UIParent.scale=.9
tick()
eq(stand.Diagnostics().reason,"parent-scale-changed","runtime UI scale invalidates geometry")
UIParent.scale=1
eq(stand.Show(snapshot),true,"scale recovery")
tick(SECRET)
eq(stand.Diagnostics().reason,"update-time-unavailable","restricted elapsed rejected")
eq(stand.Show(snapshot),true,"elapsed recovery")
fixtures[0][31*64+31]=nil
tick()
eq(stand.IsShown(),false,"runtime missing tile hides stand-in")
fixtures[0][31*64+31]=103131
eq(stand.Show(snapshot),true,"tile recovery")
local originalLayer=methods.SetDrawLayer
methods.SetDrawLayer=function() error("PRIVATE_PLAYER_TEXT") end
denied("render-prepare-tile-draw-layer","native texture operation error")
for _,value in pairs(stand.Diagnostics()) do
    if type(value)=="string" then eq(value:find("PRIVATE_PLAYER_TEXT",1,true),nil,"private error not retained") end
end
methods.SetDrawLayer=originalLayer

-- Off-center samples independently check that each pixel is covered once and
-- decodes to the requested world's east/south position, including tile seams.
for _,r in ipairs({100,200,300,500}) do
    for _,n in ipairs({-350,-40,0,160}) do
        for _,w in ipairs({-310,-20,0,210}) do
            north,west,radius=n,w,r
            eq(stand.Show(snapshot),true,"varied terrain crop")
            local area=0
            for _,t in ipairs(visibleTiles()) do area=area+t.width*t.height end
            near(area,40000,"complete terrain coverage")
            for _,p in ipairs({{13,27},{51,179},{99,99},{151,71},{197,197}}) do
                local sx,sy=p[1],p[2]
                local hit=0
                for _,t in ipairs(visibleTiles()) do
                    local l,top=t.point[4],-t.point[5]
                    if sx>=l and sx<l+t.width and sy>=top and sy<top+t.height then
                        hit=hit+1
                        local file=t.texture
                        local index=file-100000
                        local x,y=math.floor(index/100),index%100
                        local u=t.uv[1]+(sx-l)/t.width*(t.uv[2]-t.uv[1])
                        local v=t.uv[3]+(sy-top)/t.height*(t.uv[4]-t.uv[3])
                        local sampleWest=(32-x-u)*(1600/3)
                        local sampleNorth=(32-y-v)*(1600/3)
                        near(sampleWest,w-(sx-100)*(2*r/200),"world west at sampled pixel")
                        near(sampleNorth,n-(sy-100)*(2*r/200),"world north at sampled pixel")
                    end
                end
                eq(hit,1,"one terrain tile at interior pixel")
            end
        end
    end
end
north,west,radius=0,0,1600/6
-- Fixed native decoration snapshots contain pixels only. Native regions
-- remain read-only; their later scan-time movement cannot pull clones away.
local border=widget()
border.texture=324001
border.atlas=chromeAtlas
border.rect={796,496,208,208}
border.layer,border.sublevel="OVERLAY",1
border.vertex,border.alpha,border.blend={.8,.9,1,.95},.7,"BLEND"
local borderParent=widget()
borderParent.alpha=.5
border.parent=borderParent
border.sourceUV={.1,.2,.1,.8,.9,.2,.9,.8}
local text=widget()
text.kind="FontString"
text.GetText=function() error("PRIVATE_TEXT_MUST_NOT_BE_READ") end
local bg=widget()
bg.layer="BACKGROUND"
bg.GetTexture=function() error("opaque native backing must not be cloned") end
local hidden=widget()
hidden.shown=false
hidden.GetTexture=function() error("hidden pixel must not be read") end
_G.MinimapCompassTexture=border
local dynamicPin=widget()
dynamicPin.texture=324999
dynamicPin.rect={850,550,16,16}
snapshot.parts={border,text,bg,hidden,dynamicPin}
eq(stand.Show(snapshot),true,"fixed native border clone prepared")
eq(stand.Diagnostics().visibleDecorations,1,"only allowlisted native fixed texture cloned")
for _,t in ipairs(f.textures) do eq(t.texture==324999,false,"third-party marker texture never copied") end
local cloned
for _,t in ipairs(f.textures) do if t.texture==324001 then cloned=t end end
eq(cloned~=nil,true,"native border file reused")
local function fileUV(texture,u,v)
    local rect=atlasRects[texture.atlas]
    if rect then return rect[1]+u*(rect[2]-rect[1]),rect[3]+v*(rect[4]-rect[3]) end
    return u,v
end
local sx,sy=fileUV(border,border.sourceUV[1],border.sourceUV[2])
local cx,cy=fileUV(cloned,cloned.uv[1],cloned.uv[2])
near(cx,sx,"native atlas crop survives local UV")
near(cy,sy,"native atlas vertical crop survives local UV")
eq(cloned:GetAtlas(),chromeAtlas,"native atlas identity retained")
near(cloned.point[4],-4,"native border x retained")
near(cloned.point[5],-4,"native border y retained")
near(cloned.width,208,"native border width retained")
near(cloned.height,208,"native border height retained")
near(cloned.alpha,.35,"native effective alpha includes parent")
near(cloned.vertex[1],.8,"native region tint retained")
near(cloned.vertex[2],.9,"terrain tint leaves decoration green unchanged")
near(cloned.vertex[3],1,"terrain tint leaves decoration blue unchanged")
near(cloned.vertex[4],.95,"terrain tint leaves decoration alpha unchanged")
eq(#cloned.uv,8,"native quadrilateral UV preserved")
for i=1,8 do near(cloned.uv[i],border.sourceUV[i],"native decoration UV "..i) end
eq(cloned.blend,"BLEND","native blending retained")
-- The live 70862 probe confirmed SetRotation(0) leaves eight local UVs
-- intact; the regression model preserves that behavior rather than inventing
-- a rotation-reset cause for the dev17 sheet failure.
local uvProbe=widget()
uvProbe:SetAtlas(chromeAtlas)
uvProbe:SetTexCoord(.2,.3,.2,.5,.4,.3,.4,.5)
local before={uvProbe:GetTexCoord()}
uvProbe:SetRotation(0)
local after={uvProbe:GetTexCoord()}
for i=1,8 do near(after[i],before[i],"70862 zero rotation preserves local UV "..i) end
-- A pooled clone must drop its previous atlas when the next source is plain.
border.atlas=nil
border.texture=324002
eq(stand.Show(snapshot),true,"atlas clone reused for ordinary texture")
eq(cloned:GetAtlas(),nil,"pooled atlas cleared for ordinary source")
eq(cloned:GetTexture(),324002,"plain native file copied")
local plainU,plainV=fileUV(cloned,cloned.uv[1],cloned.uv[2])
near(plainU,border.sourceUV[1],"plain source uses raw file U")
near(plainV,border.sourceUV[2],"plain source uses raw file V")
border.atlas,border.texture=chromeAtlas,324001
eq(stand.Show(snapshot),true,"ordinary clone reused for atlas source")
eq(cloned:GetAtlas(),chromeAtlas,"atlas restored on pooled clone")
-- Resource identity and public atlas reads are required before cloning.
local atlasInfoGetter=C_Texture.GetAtlasInfo
C_Texture.GetAtlasInfo=function() return {file=999999} end
denied("native-decoration-unavailable","atlas file mismatch")
C_Texture.GetAtlasInfo=atlasInfoGetter
local atlasGetter=border.GetAtlas
border.GetAtlas=function() return SECRET end
denied("native-decoration-unavailable","restricted atlas identity")
border.GetAtlas=function() error("PRIVATE_ATLAS") end
denied("native-decoration-unavailable","atlas identity API error")
border.GetAtlas=atlasGetter
eq(stand.Show(snapshot),true,"atlas identity recovery")
local allocation=stand.Diagnostics().allocatedDecorations
border.rect={200,200,208,208}
tick()
near(cloned.point[4],-4,"moved source cannot move snapshot clone")
eq(stand.Diagnostics().allocatedDecorations,allocation,"decoration pool reused")
near(border.rect[1],200,"native source never repositioned")
near(border.alpha,.7,"native alpha never written")
border.rect={796,496,208,208}
local parentGetter=borderParent.GetParent
borderParent.GetParent=function() error("PRIVATE_PARENT") end
denied("native-decoration-unavailable","parent alpha traversal error")
borderParent.GetParent=parentGetter
border.texture=SECRET
denied("native-decoration-unavailable","restricted native decoration")
border.texture=324001
border.sourceUV[3]=SECRET
denied("native-decoration-unavailable","restricted decoration UV")
border.sourceUV[3]=.1
border.rect[3]=900
denied("native-decoration-unavailable","oversize anchored decoration")
border.rect[3]=208
badFile=324001
denied("render-prepare-decoration-resource","missing cloned resource")
badFile=nil
snapshot.parts={{GetObjectType=function() error("PRIVATE_FRAME") end}}
denied("native-decoration-unavailable","unreadable native object kind")
snapshot.parts={}
eq(stand.Show(snapshot),true,"decoration removal recovers")
eq(stand.Diagnostics().visibleDecorations,0,"old decoration removed")
eq(cloned.shown,false,"old clone hidden")
snapshot.parts=nil
_G.MinimapCompassTexture=nil
-- Dirty rendering: safe reads continue while stationary, without rewriting
-- texture bindings, masks, frame anchors, sizes, or fixed chrome every tick.
local observedSetters={"SetTexture","SetAtlas","ClearAllPoints","SetPoint","SetSize","SetTexCoord","SetRotation","SetVertexColor"}
local function countWrites()
    local counts,originals={},{}
    for _,key in ipairs(observedSetters) do
        local name=key
        originals[name]=methods[name]
        methods[name]=function(self,...)
            counts[name]=(counts[name] or 0)+1
            return originals[name](self,...)
        end
    end
    return counts,function()
        for name,method in pairs(originals) do methods[name]=method end
    end
end
local function writes(counts,key) return counts[key] or 0 end
north,west,radius,facing=0,0,1600/6,0
eq(stand.Show(snapshot),true,"cache transaction initialized")
local cacheRenders=stand.Diagnostics().renders
local counts,stop=countWrites()
for i=1,100 do tick(.06) end
for _,key in ipairs(observedSetters) do eq(writes(counts,key),0,"stationary no repeated "..key) end
eq(stand.Diagnostics().renders,cacheRenders,"stationary cache does not repaint")
eq(stand.IsShown(),true,"stationary reads keep valid picture available")
stop()
counts,stop=countWrites()
facing=.3
tick()
eq(writes(counts,"SetRotation"),1,"heading changes rotate arrow once")
for _,key in ipairs({"SetTexture","SetAtlas","ClearAllPoints","SetPoint","SetSize","SetTexCoord","SetVertexColor"}) do
    eq(writes(counts,key),0,"heading leaves terrain and chrome "..key)
end
stop()
counts,stop=countWrites()
north=20
tick()
eq(writes(counts,"SetTexture"),0,"within-tile movement preserves loaded files")
eq(writes(counts,"SetAtlas"),0,"movement preserves mask and chrome atlases")
eq(writes(counts,"SetRotation"),0,"movement without turn preserves arrow angle")
eq(writes(counts,"SetTexCoord")>0,true,"movement updates terrain crop")
eq(writes(counts,"SetSize")>0,true,"movement updates clipped extents")
stop()
local oldID=fixtures[0][31*64+31]
fixtures[0][31*64+31]=203131
counts,stop=countWrites()
tick()
eq(writes(counts,"SetTexture"),1,"changed terrain fact loads only changed slot")
eq(tileByID(203131)~=nil,true,"fresh terrain ID displayed")
eq(writes(counts,"SetAtlas"),0,"resource change does not rebind chrome")
stop()
fixtures[0][31*64+31]=oldID
badFile=oldID
tick()
eq(stand.IsShown(),false,"dirty resource loading failure closes renderer")
eq(stand.Diagnostics().reason,"render-update-tile-texture","dirty resource error stage")
badFile=nil
north,west,facing=0,0,0
eq(stand.Show(snapshot),true,"new lease recovers resource")
stand.Hide()
badFile=oldID
denied("render-prepare-tile-texture","hidden cache cannot bypass new Show load validation")
badFile=nil

-- Reads detect changes to cached owned graphics rather than silently painting
-- over a different owner's write. A new Show is a fresh private transaction.
eq(stand.Show(snapshot),true,"tamper test ready")
local tampered=visibleTiles()[1]
tampered:SetTexture(888888)
tick()
eq(stand.IsShown(),false,"external tile resource change fails closed")
eq(stand.Diagnostics().reason,"render-update-cache-verify","resource tamper readback stage")
eq(tampered:GetTexture(),888888,"renderer does not rewrite external change")
eq(stand.Show(snapshot),true,"resource tamper recovery")
tampered=visibleTiles()[1]
tampered:SetTexCoord(0,1,0,1)
tick()
eq(stand.IsShown(),false,"external crop change fails closed")
eq(stand.Show(snapshot),true,"crop tamper recovery")
f:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",900,500)
tick()
eq(stand.IsShown(),false,"external private-frame geometry change fails closed")
eq(stand.Show(snapshot),true,"geometry tamper recovery")
tampered=visibleTiles()[1]
tampered:RemoveMaskTexture(f.mask)
tick()
eq(stand.IsShown(),false,"external mask removal fails closed")
eq(stand.Show(snapshot),true,"mask tamper recovery")
tampered=visibleTiles()[1]
local originalTextureGetter=tampered.GetTexture
tampered.GetTexture=function() return SECRET end
tick()
eq(stand.IsShown(),false,"restricted cached resource getter fails closed")
tampered.GetTexture=originalTextureGetter
eq(stand.Show(snapshot),true,"restricted resource read recovery")
tampered=visibleTiles()[1]
originalTextureGetter=tampered.GetTexture
tampered.GetTexture=function() error("PRIVATE_RESOURCE_READ") end
tick()
eq(stand.IsShown(),false,"cached resource API error fails closed")
tampered.GetTexture=originalTextureGetter
eq(stand.Show(snapshot),true,"resource API error recovery")

-- Opacity is controlled independently of readiness: a prepared transparent
-- stand-in is still available for scanner-owned transitions, without timers.
eq(stand.Show(snapshot,0),true,"transparent initial picture prepared")
near(f:GetAlpha(),0,"initial zero opacity applied")
eq(stand.IsShown(),true,"zero opacity remains an available picture")
tick()
eq(stand.IsShown(),true,"zero opacity passes stationary safety checks")
eq(stand.SetOpacity(.5),true,"scanner can set half opacity")
near(f:GetAlpha(),.5,"half opacity only on owned frame")
tick()
eq(stand.IsShown(),true,"opacity changes update cache baseline")
eq(stand.SetOpacity(1),true,"scanner can finish opacity")
stand.Hide()
near(f:GetAlpha(),1,"Hide resets opacity")
eq(stand.Show(snapshot),true,"default next lease is opaque")
near(f:GetAlpha(),1,"default Show cannot inherit transparent cache")
for _,value in ipairs({SECRET,-.01,1.01,0/0,math.huge,-math.huge,"0.5"}) do
    eq(stand.SetOpacity(value),false,"invalid opacity rejected")
    eq(stand.IsShown(),false,"invalid opacity closes owned frame")
    eq(stand.Diagnostics().reason,"invalid-opacity","invalid opacity literal reason")
    eq(stand.Show(snapshot),true,"invalid opacity recovery starts fresh")
end
local opacityOK,opacityReason=stand.Show(snapshot,SECRET)
eq(opacityOK,false,"restricted initial opacity rejected")
eq(opacityReason,"invalid-opacity","restricted initial opacity reason")
eq(stand.IsShown(),false,"invalid initial opacity stays hidden")
eq(stand.SetOpacity(.5),false,"inactive opacity call cannot create a picture")
local alphaSetter=methods.SetAlpha
methods.SetAlpha=function(self,value)
    if self==f and value==.25 then error("PRIVATE_OPACITY_WRITE") end
    return alphaSetter(self,value)
end
eq(stand.Show(snapshot),true,"opacity write failure test ready")
eq(stand.SetOpacity(.25),false,"opacity setter exception rejected")
eq(stand.IsShown(),false,"opacity setter exception hides frame")
opacityOK,opacityReason=stand.Show(snapshot,.25)
eq(opacityOK,false,"initial opacity setter exception rejected")
eq(opacityReason,"render-prepare-frame-opacity","initial opacity failure literal stage")
methods.SetAlpha=alphaSetter
eq(stand.Show(snapshot,0),true,"opacity API recovers")
local alphaGetter=methods.GetAlpha
methods.GetAlpha=function(self)
    if self==f and self.alpha==.3 then return SECRET end
    return alphaGetter(self)
end
eq(stand.SetOpacity(.3),false,"restricted opacity readback rejected")
eq(stand.IsShown(),false,"restricted opacity readback hides picture")
methods.GetAlpha=alphaGetter
eq(stand.Show(snapshot),true,"opacity readback recovery")
for _,value in pairs(stand.Diagnostics()) do
    if type(value)=="string" then eq(value:find("PRIVATE_",1,true),nil,"renderer diagnostics contain no native errors") end
end
-- Optional native integrity getters do not become new hard client gates.
local rectGetter=methods.GetRect
methods.GetRect=nil
eq(stand.Show(snapshot),true,"optional rectangle getter unavailable remains supported")
tick()
eq(stand.IsShown(),true,"cache supports absent optional rectangle getter")
methods.GetRect=rectGetter
stand.Hide()
C_Texture={GetAtlasInfo=function() return {file=8187590,width=256,height=256} end}
legacyMaskNil,maskAtlasFile=true,8187590
eq(stand.Show(snapshot),true,"native circle atlas works without legacy path")
eq(stand.Diagnostics().maskSource,"atlas","native mask atlas used")
maskAtlasFile=nil
denied("render-prepare-mask-verify","unloaded atlas and path rejected")
legacyMaskNil=false
stand.Hide()
eq(artReads,0,"no world-map illustration queried in any branch")
eq(nativeWrites,0,"native map never written")
eq(settingWrites,0,"input and settings never written")
eq(#frames,1,"bounded owned frame allocation")
eq(stand.Diagnostics().allocatedTiles<=64,true,"bounded owned terrain pool")
print("professions_standin_test: "..checks.." checks passed (simulated, not game acceptance)")
