local _, NS = ...
local A = {}
NS.Auras = A

-- Native containers own aura filtering, ordering, secret data and rendering.
-- Each fixed viewport clips its full list instead of spilling into another tile.
local views = setmetatable({}, {__mode="k"})
local revision,worldActive = 0,true
local ICON,GAP,COLUMNS,WIDTH,HEIGHT = 10,1,6,65,10
local COUNT_SCAN_LIMIT = 1024
-- Confirmed tracking IDs, restored from the 0.1.31 native candidate filter.
local trackingSpellIDs = {[2580]=true,[2383]=true,[43308]=true}

local function publicGUID(value)
    return NS.Public(value) and type(value)=="string" and value~="" and value or nil
end

local function passthrough(frame)
    if type(frame.EnableMouse)=="function" then frame:EnableMouse(false) end
    frame:SetMouseClickEnabled(false)
    frame:SetMouseMotionEnabled(false)
end

local function iconParts(button,dispellable)
    button:SetSize(ICON,ICON)
    passthrough(button)
    local icon=button:CreateTexture(nil,"BACKGROUND")
    icon:SetAllPoints()
    button:SetIcon(icon)
    if ICON>=12 then
        local count=button:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT",0,0)
        count:SetJustifyH("RIGHT")
        local font=count:GetFont()
        if font then count:SetFont(font,8,"OUTLINE") end
        button:SetApplicationCount(count)
    end
    local border=button:CreateTexture(nil,"OVERLAY")
    border:SetAllPoints()
    button:AddDispelTypeTexture(border)
    local layer=CreateFrame("Frame",nil,button)
    layer:SetAllPoints()
    passthrough(layer)
    local cooldown=CreateFrame("Cooldown",nil,layer,"CooldownFrameTemplate")
    cooldown:SetAllPoints()
    passthrough(cooldown)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cooldown)
    if dispellable then
        -- Native HARMFUL|RAID membership supplies this fact; no Lua aura read.
        local mark=button:CreateTexture(nil,"OVERLAY")
        mark:SetColorTexture(1,0.85,0.15,1)
        mark:SetSize(3,3)
        mark:SetPoint("TOPRIGHT",0,0)
    end
end

local function resetOffsets(view)
    local ok=true
    for _,viewport in ipairs(view.viewports or {}) do
        if not pcall(viewport.SetVerticalScroll,viewport,0) then ok=false end
    end
    view.scrollOffset=0
    view.columnOffsets={0,0,0}
    return ok
end

local function hideView(view)
    for _,container in ipairs(view.containers or {}) do
        -- SetUnit(nil) is invalid on this client.
        pcall(container.SetEnabled,container,false)
        pcall(container.Hide,container)
    end
    for _,viewport in ipairs(view.viewports or {}) do pcall(viewport.Hide,viewport) end
    for _,label in ipairs(view.labels or {}) do pcall(label.Hide,label) end
end

local function clear(view)
    hideView(view)
    resetOffsets(view)
    view.unit,view.expectedGUID,view.side=nil,nil,nil
    view.ownerUnit,view.ownerGUID=nil,nil
    view.publicRanges,view.rangeRevision,view.scrollRangeCurrent=nil,nil,false
    view.bound=false
end

local function validIdentity(unit,expected,side,ownerUnit,ownerGUID)
    if not NS.Public(side) or not NS.Public(ownerUnit)
        or side~="friendly" and side~="enemy" or not publicGUID(expected) then return false end
    if ownerUnit~=nil then
        if not NS.ValidToken(ownerUnit) or not publicGUID(ownerGUID)
            or not NS.Public(unit) or unit~=ownerUnit.."target"
            or NS.Read(UnitGUID,ownerUnit)~=ownerGUID then return false end
    elseif not NS.ValidToken(unit) then return false end
    if NS.Read(UnitGUID,unit)~=expected then return false end
    return ownerUnit==nil or NS.Read(UnitGUID,ownerUnit)==ownerGUID
end

local function parentVisible(view)
    return NS.Read(view.parent.IsVisible or view.parent.IsShown,view.parent)==true
end

local function stillValid(view)
    return worldActive and view.bound and parentVisible(view)
        and validIdentity(view.unit,view.expectedGUID,view.side,view.ownerUnit,view.ownerGUID)
end

local function addGroup(container,key,filter,dispellable,order,candidateFilters)
    container:AddAuraGroup(key,filter,{
        -- Omitted maxFrameCount means the native unlimited default.
        sortMethod=AuraContainerSortMethod.ExpirationOnly,
        sortDirection=AuraContainerSortDirection.Normal,
        candidateFilters=candidateFilters,
        initializeFrame=function(button) iconParts(button,dispellable) end,
        layout={elementWidth=ICON,elementHeight=ICON,elementSpacing=GAP,lineSpacing=GAP,layoutIndex=order,
            forceNewLine=false,groupSpacing=0,groupLineSpacing=GAP},
    })
end

function A.Create(parent,compact)
    if not parent or not UIParent or NS.InCombat() or type(CreateFrame)~="function"
        or type(AuraContainerSortMethod)~="table" or type(AuraContainerSortDirection)~="table"
        or not AnchorUtil or not AnchorUtil.FlowDirection then return nil end
    local view={containers={},viewports={},labels={},ready=false,parent=parent,compact=compact==true,
        nameInset=4,scrollOffset=0,columnOffsets={0,0,0}}
    local buffY,debuffY=compact and -24 or -26,compact and -36 or -38
    local ok,err=pcall(function()
        for _,spec in ipairs({{buffY,"+",0.45,1,0.55},{debuffY,"-",1,0.45,0.4}}) do
            local label=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            label:SetPoint("TOPLEFT",2,spec[1]-1)
            label:SetSize(5,8)
            local font=label:GetFont()
            if font then label:SetFont(font,8,"") end
            label:SetJustifyH("LEFT")
            label:SetText(spec[2])
            label:SetTextColor(spec[3],spec[4],spec[5])
            label:Hide()
            view.labels[#view.labels+1]=label
        end
        local function column(y)
            -- A separate, unprotected visual frame keeps scrolling independent
            -- of the secure unit button. Parent OnHide explicitly closes it.
            local viewport=CreateFrame("ScrollFrame",nil,UIParent)
            view.viewports[#view.viewports+1]=viewport
            viewport:SetSize(WIDTH,HEIGHT)
            viewport:SetPoint("TOPLEFT",parent,"TOPLEFT",8,y)
            viewport:SetFrameLevel(parent:GetFrameLevel()+1)
            viewport:SetClipsChildren(true)
            passthrough(viewport)
            viewport:Hide()
            local container=CreateFrame("AuraContainer",nil,viewport,"CustomAuraContainerTemplate")
            view.containers[#view.containers+1]=container
            container:SetEnabled(false)
            container:Hide()
            passthrough(container)
            container:SetFlowLayoutAnchorPoint("TOPLEFT")
            container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,AnchorUtil.FlowDirection.Down)
            container:SetFlowLayoutMaximumLineSize(WIDTH)
            viewport:SetScrollChild(container)
            return container,viewport
        end
        view.helpful,view.helpfulViewport=column(buffY)
        view.harmful,view.harmfulViewport=column(debuffY)
        view.dispellable,view.dispellableViewport=column(debuffY)
        -- Native maxDuration excludes permanent effects for any non-nil value;
        -- infinity keeps every finite-duration related buff without a cutoff.
        addGroup(view.helpful,"buffs","HELPFUL|PLAYER",false,1,{excludeSpellIDs=trackingSpellIDs,maxDuration=math.huge})
        addGroup(view.harmful,"debuffs","HARMFUL|PLAYER",false,1)
        addGroup(view.dispellable,"dispels","HARMFUL|RAID",true,1)
        addGroup(view.dispellable,"otherDebuffs","HARMFUL|PLAYER|!RAID",false,2)
        parent:HookScript("OnHide",function() clear(view) end)
    end)
    if not ok then A.lastError=NS.Text(err);clear(view);return nil end
    view.ready=true
    views[view]=true
    return view
end

local function activeColumns(view)
    if view.side=="friendly" then
        return {view.helpful,view.dispellable},{view.helpfulViewport,view.dispellableViewport}
    end
    return {view.helpful,view.harmful},{view.helpfulViewport,view.harmfulViewport}
end

local function syncScale(view)
    local parentScale=NS.Read(view.parent.GetEffectiveScale,view.parent)
    local rootScale=NS.Read(UIParent.GetEffectiveScale,UIParent)
    if not NS.Number(parentScale) or parentScale<=0 or not NS.Number(rootScale) or rootScale<=0 then return false end
    local scale=parentScale/rootScale
    if scale~=view.scale then
        for _,viewport in ipairs(view.viewports) do
            if not pcall(viewport.SetScale,viewport,scale) then return false end
        end
        view.scale=scale
    end
    return true
end

function A.Update(view,unit,expectedGUID,side,ownerUnit,ownerGUID)
    if not view or not view.ready then return false end
    if not worldActive or not parentVisible(view) or not syncScale(view) or not validIdentity(unit,expectedGUID,side,ownerUnit,ownerGUID) then
        if view.bound then clear(view) end
        return false
    end
    local changed=unit~=view.unit or expectedGUID~=view.expectedGUID or side~=view.side
        or ownerUnit~=view.ownerUnit or ownerGUID~=view.ownerGUID or not view.bound
    if changed then
        clear(view)
        local harmful=side=="friendly" and view.dispellable or view.harmful
        local harmfulViewport=side=="friendly" and view.dispellableViewport or view.harmfulViewport
        local ok,err=pcall(function()
            if not resetOffsets(view) then error("aura viewport scroll reset failed") end
            for _,container in ipairs({view.helpful,harmful}) do
                container:SetUnit(unit)
                container:SetEnabled(true)
                container:Show()
            end
            view.helpfulViewport:Show()
            harmfulViewport:Show()
            for _,label in ipairs(view.labels) do label:Show() end
        end)
        if not ok or not parentVisible(view) or not validIdentity(unit,expectedGUID,side,ownerUnit,ownerGUID) then
            if not ok then view.error=NS.Text(err);A.lastError=view.error end
            clear(view);return false
        end
        view.unit,view.expectedGUID,view.side=unit,expectedGUID,side
        view.ownerUnit,view.ownerGUID=ownerUnit,ownerGUID
        view.bound=true
    end
    return true
end

-- This is only a public scroll-bound fallback. Native aura rendering never
-- depends on this enumeration, and protected/unknown data is not counted.
local function publicCount(unit,filter,excludeTracking)
    if NS.InCombat() or not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex)~="function" then return nil end
    local count=0
    for index=1,COUNT_SCAN_LIMIT do
        local ok,aura=pcall(C_UnitAuras.GetAuraDataByIndex,unit,index,filter)
        if not ok or not NS.Public(aura) then return nil end
        if aura==nil then return count end
        if type(aura)~="table" then return nil end
        if excludeTracking then
            local spellID,duration=aura.spellId,aura.duration
            local tracking=NS.Number(spellID) and trackingSpellIDs[spellID]
            if not tracking then
                -- Match the native permanent-effect filter without inspecting
                -- restricted data or guessing from localized spell names.
                if not NS.Number(duration) or duration<0 then return nil end
                if duration>0 then
                    if not NS.Number(spellID) then return nil end
                    count=count+1
                end
            end
        else count=count+1 end
    end
    return nil
end

local function publicRange(view,index)
    local count
    if index==1 then
        count=publicCount(view.unit,"HELPFUL|PLAYER",true)
    elseif view.side=="friendly" then
        local dispels=publicCount(view.unit,"HARMFUL|RAID")
        local ownOther=publicCount(view.unit,"HARMFUL|PLAYER|!RAID")
        if dispels==nil or ownOther==nil then return nil end
        -- The native groups are disjoint and explicitly continue on the same
        -- row, with no group spacing or forced line break.
        count=dispels+ownOther
    else
        count=publicCount(view.unit,"HARMFUL|PLAYER")
    end
    if count==nil then return nil end
    local rows=math.ceil(count/COLUMNS)
    return math.max(0,rows*(ICON+GAP)-GAP-HEIGHT)
end

local function scrollRanges(view,columns)
    local ranges,current={},true
    for i,viewport in ipairs(columns) do
        local range=NS.Read(viewport.GetVerticalScrollRange,viewport)
        if not NS.Number(range) or range<0 then
            if not NS.InCombat() and view.rangeRevision==revision and view.publicRanges then range=view.publicRanges[i]
            elseif not NS.InCombat() then range=publicRange(view,i)
            else range=nil end
        end
        if NS.Number(range) and range>=0 then ranges[i]=range
        else
            current=false
            ranges[i]=view.publicRanges and view.publicRanges[i] or 0
        end
    end
    if current then view.publicRanges={ranges[1],ranges[2]};view.rangeRevision=revision end
    view.scrollRangeCurrent=current
    return ranges
end

function A.Scroll(view,delta)
    if not view or not view.ready or not NS.Number(delta) then return false end
    if not stillValid(view) then clear(view);return false end
    local _,columns=activeColumns(view)
    local ranges=scrollRanges(view,columns)
    if not stillValid(view) then clear(view);return false end
    local offset=math.max(0,math.min(math.max(ranges[1],ranges[2]),view.scrollOffset-delta*(ICON+GAP)))
    local ok,err=pcall(function()
        for i,viewport in ipairs(columns) do
            local value=math.min(offset,ranges[i])
            viewport:SetVerticalScroll(value)
            view.columnOffsets[i]=value
        end
    end)
    if not ok then A.lastError=NS.Text(err);resetOffsets(view);return false end
    if not stillValid(view) then clear(view);return false end
    view.scrollOffset=offset
    return true
end

function A.ResetScroll(view)
    if not view or not view.ready then return false end
    return resetOffsets(view)
end

-- Compatibility only: aura content is permanently on each tile, not in a popup.
function A.Key() return "" end
function A.TooltipLines() return {},"" end

local refreshEvents={SPELLS_CHANGED=true,PLAYER_TALENT_UPDATE=true,PLAYER_SPECIALIZATION_CHANGED=true,
    UNIT_PET=true,PLAYER_ENTERING_WORLD=true,PLAYER_REGEN_DISABLED=true,PLAYER_REGEN_ENABLED=true}

function A.OnEvent(event)
    if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
        worldActive=false
        revision=revision+1
        for view in pairs(views) do clear(view) end
    elseif event=="UNIT_AURA" or refreshEvents[event] then
        if event=="PLAYER_ENTERING_WORLD" then worldActive=true end
        revision=revision+1
        for view in pairs(views) do
            if stillValid(view) then
                if refreshEvents[event] then
                    local active=activeColumns(view)
                    for _,container in ipairs(active) do
                        if not pcall(container.UpdateAllAuras,container) then clear(view);break end
                    end
                end
                if view.bound and view.scrollOffset>0 then A.Scroll(view,0) end
            elseif view.bound then clear(view) end
        end
    end
end
