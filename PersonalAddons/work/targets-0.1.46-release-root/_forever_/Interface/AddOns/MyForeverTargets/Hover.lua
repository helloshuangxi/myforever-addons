local _, NS = ...
local indicator, hoverUnit, hoverSide, hoverGUID

local function makeIndicator()
    if indicator then return indicator end
    indicator=CreateFrame("Frame",nil,UIParent)
    indicator:SetSize(60,68)
    indicator:SetScale(0.75)
    indicator:SetFrameStrata("HIGH")
    indicator:EnableMouse(false)
    -- Draw the chevron from the built-in solid white texture. This does not
    -- depend on optional minimap/particle texture files in a specific client.
    indicator.arrow=CreateFrame("Frame",nil,indicator)
    indicator.arrow:SetSize(60,56)
    indicator.arrow:EnableMouse(false)
    indicator.arrow:SetPoint("CENTER",0,4)
    indicator.arrow.strips={}
    for tier=1,2 do
        local y=tier==1 and 10 or -8
        for i=1,2 do
            local sign=i==1 and -1 or 1
            local shadow=indicator.arrow:CreateTexture(nil,"ARTWORK")
            shadow:SetTexture("Interface\\Buttons\\WHITE8X8")
            shadow:SetSize(38,10)
            shadow:SetPoint("CENTER",sign*11,y)
            shadow:SetRotation(sign*math.pi/4)
            shadow:SetVertexColor(.025,.012,0,.95)
            local strip=indicator.arrow:CreateTexture(nil,"OVERLAY")
            strip:SetTexture("Interface\\Buttons\\WHITE8X8")
            strip:SetSize(34,6)
            strip:SetPoint("CENTER",sign*11,y)
            strip:SetRotation(sign*math.pi/4)
            strip:SetVertexColor(1,.85,.22,1)
            indicator.arrow.strips[#indicator.arrow.strips+1]=strip
        end
    end
    indicator.glow=indicator:CreateTexture(nil,"ARTWORK")
    indicator.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    indicator.glow:SetBlendMode("ADD")
    indicator.glow:SetSize(40,5)
    indicator.glow:SetPoint("BOTTOM",0,1)
    indicator.glow:SetVertexColor(1,.77,.22,1)
    local elapsed=0
    indicator:SetScript("OnUpdate",function(self,delta)
        elapsed=elapsed+delta
        local wave=math.sin(elapsed*4.8)
        self.arrow:SetPoint("CENTER",0,4+wave*6)
        self.glow:SetAlpha(.65+.25*wave)
    end)
    indicator:Hide()
    NS.HoverIndicator=indicator
    return indicator
end

function NS.SetHoverUnit(unit,side)
    if not unit then NS.HoveredTile=nil end
    if unit and not side then
        side=NS.ReadUnit(unit,"friendly") and "friendly" or "enemy"
    end
    hoverUnit,hoverSide=unit,side
    local data=unit and NS.ReadUnit(unit,side) or nil
    hoverGUID=data and data.guid or nil
    if not data then
        if indicator then indicator:Hide() end
        return
    end
    makeIndicator()
    NS.UpdateHover()
end

function NS.UpdateHover()
    if not hoverUnit or not indicator then return end
    local data=NS.ReadUnit(hoverUnit,hoverSide)
    if not data or data.guid ~= hoverGUID then indicator:Hide();return end
    -- Group/target aliases do not always resolve directly to their rendered
    -- nameplate; the provider also matches the same live GUID against plate units.
    local plate=NS.FindUnitNameplate and NS.FindUnitNameplate(hoverUnit)
        or NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,hoverUnit)
    if not plate or NS.Read(plate.IsForbidden,plate) == true or NS.Read(plate.IsShown,plate) ~= true then
        indicator:Hide();return
    end
    -- No world-position guessing and no modification of native nameplates/CVars.
    -- The indicator is unprotected and click-through; only a genuine plate anchors it.
    local ok=pcall(function()
        indicator:ClearAllPoints()
        indicator:SetPoint("BOTTOM",plate,"TOP",0,8)
        indicator:Show()
    end)
    if not ok then indicator:Hide() end
end

function NS.HideHover() NS.SetHoverUnit(nil) end

-- The focus indicator is independent of the hover chevrons. Current targets
-- have no world marker. Native nameplates remain read-only anchor sources.
local worldIndicators={}
NS.WorldIndicators=worldIndicators
local WHITE="Interface\\Buttons\\WHITE8X8"

local function member(object,key)
    return NS.Read(function() return object[key] end)
end

local function publicGUID(unit)
    local value=NS.Read(UnitGUID,unit)
    return type(value)=="string" and value~="" and value or nil
end

local function livePlate(plate)
    if not NS.Public(plate) or (type(plate)~="table" and type(plate)~="userdata") then return false end
    if NS.Read(member(plate,"IsForbidden"),plate)~=false then return false end
    return NS.Read(member(plate,"IsVisible") or member(plate,"IsShown"),plate)==true
end

local function plateMatches(plate,token,expected)
    if not NS.ValidToken(token) or not token:match("^nameplate%d+$") or not livePlate(plate)
        or NS.Read(UnitExists,token)~=true or publicGUID(token)~=expected
        or NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,token)~=plate then return false end
    local ok,declared=pcall(function() return plate.namePlateUnitToken end)
    if not ok or not NS.Public(declared) then return false end
    -- A missing optional field is supported through the verified native reverse
    -- lookup above. A contradictory/reused declared token is never ignored.
    if declared~=nil and (not NS.ValidToken(declared) or not declared:match("^nameplate%d+$")
        or publicGUID(declared)~=expected) then return false end
    return publicGUID(token)==expected
end

local function findWorldPlate(unit,expected,tokens)
    local direct=NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit)
    local candidate=direct or NS.Read(NS.FindUnitNameplate,unit)
    if candidate then
        local declared=member(candidate,"namePlateUnitToken")
        if plateMatches(candidate,declared,expected) then return candidate,declared end
    end
    for _,token in ipairs(tokens()) do
        if publicGUID(token)==expected then
            local plate=NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,token)
            if plateMatches(plate,token,expected) then return plate,token end
        end
    end
end

local function coloredStrip(parent,x,y,width,height,rotation,color)
    local shadow=parent:CreateTexture(nil,"ARTWORK")
    shadow:SetTexture(WHITE);shadow:SetSize(width+2,height+2)
    shadow:SetPoint("CENTER",x,y);shadow:SetRotation(rotation or 0)
    shadow:SetVertexColor(.015,.01,.01,.95)
    local strip=parent:CreateTexture(nil,"OVERLAY")
    strip:SetTexture(WHITE);strip:SetSize(width,height)
    strip:SetPoint("CENTER",x,y);strip:SetRotation(rotation or 0)
    strip:SetVertexColor(color[1],color[2],color[3],1)
    return strip
end

local function makeFocusIndicator()
    if worldIndicators.focus then return worldIndicators.focus end
    local frame=CreateFrame("Frame","MyForeverTargetsFocusIndicator",UIParent)
    frame:SetSize(56,56);frame:SetScale(.75);frame:SetFrameStrata("HIGH");frame:EnableMouse(false)
    frame.kind="focus"
    frame.body=CreateFrame("Frame",nil,frame)
    frame.body:SetSize(44,44);frame.body:SetPoint("CENTER",0,5);frame.body:EnableMouse(false)
    local color={1,.75,.12}
    for _,point in ipairs({{-6,6,math.pi/4},{6,6,-math.pi/4},
        {-6,-6,-math.pi/4},{6,-6,math.pi/4}}) do
        coloredStrip(frame.body,point[1],point[2],17,3,point[3],color)
    end
    for _,sign in ipairs({-1,1}) do
        coloredStrip(frame.body,sign*20,0,3,24,0,color)
        coloredStrip(frame.body,sign*17.5,11,7,3,0,color)
        coloredStrip(frame.body,sign*17.5,-11,7,3,0,color)
    end
    frame.label=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    local font=frame.label:GetFont()
    if font then frame.label:SetFont(font,10,"OUTLINE") end
    frame.label:SetPoint("BOTTOM",0,-1);frame.label:SetSize(42,10)
    frame.label:SetTextColor(color[1],color[2],color[3],1)
    frame.label:SetText("焦点")
    frame:Hide();worldIndicators.focus=frame
    return frame
end

local function hideWorldIndicator(frame)
    if not frame then return end
    frame:Hide()
    frame.guid,frame.plate,frame.plateUnit=nil,nil,nil
end

function NS.HideWorldIndicators()
    for _,frame in pairs(worldIndicators) do hideWorldIndicator(frame) end
end

function NS.UpdateWorldIndicators()
    if not NS.DB or NS.DB.shown~=true then NS.HideWorldIndicators();return end
    local now=NS.Read(GetTime)
    if not NS.Number(now) then now=0 end
    local cachedTokens
    local function tokens()
        if cachedTokens then return cachedTokens end
        cachedTokens={}
        local seen={}
        local function add(token)
            if NS.ValidToken(token) and token:match("^nameplate%d+$") and not seen[token] then
                seen[token]=true;cachedTokens[#cachedTokens+1]=token
            end
        end
        local exposed=NS.Read(NS.NameplateTokens)
        if NS.Public(exposed) and type(exposed)=="table" then
            for _,token in ipairs(exposed) do add(token) end
        end
        if type(NS.Nameplates)=="table" then for token in pairs(NS.Nameplates) do add(token) end end
        -- Covers a missed Added event without depending on optional frame data.
        if #cachedTokens==0 then
            for i=1,40 do local token="nameplate"..i;if NS.Read(UnitExists,token)==true then add(token) end end
        end
        return cachedTokens
    end
    local expected=NS.Read(UnitExists,"focus")==true and publicGUID("focus") or nil
    if not expected then hideWorldIndicator(worldIndicators.focus);return end
    local plate,token=findWorldPlate("focus",expected,tokens)
    if not plate or publicGUID("focus")~=expected then hideWorldIndicator(worldIndicators.focus);return end
    local hovered=indicator and NS.Read(indicator.IsShown,indicator)==true and hoverGUID or nil
    local frame=makeFocusIndicator()
    local x=hovered==expected and 52 or 0
    local ok=pcall(function()
        if NS.Read(UnitExists,"focus")~=true or publicGUID("focus")~=expected
            or not plateMatches(plate,token,expected) then
            hideWorldIndicator(frame);return
        end
        frame:ClearAllPoints();frame:SetPoint("BOTTOM",plate,"TOP",x,10)
        local breath=(1+math.sin(now*2.2))*.5
        frame.body:SetAlpha(.72+.28*breath);frame.body:SetScale(.98+.04*breath)
        frame.guid,frame.plate,frame.plateUnit=expected,plate,token
        frame:Show()
    end)
    if not ok then hideWorldIndicator(frame) end
end
