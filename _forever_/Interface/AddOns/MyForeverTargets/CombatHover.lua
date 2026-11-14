local _, NS = ...
-- In-combat hover casting for tiles bound to a stable unit token.
--
-- The out-of-combat name bridge (NearbyCast) hands every key back when combat
-- starts, so an ordinary spell key then falls through to the current target.
-- This module follows the established click-cast pattern (Clique, HealBot,
-- VuhDo): out of combat it records which keys run which helpful/harmful spell
-- and prepares one SecureActionButton per spell; restricted OnEnter/OnLeave
-- wrappers then bind those keys to the proxies while the pointer is on a tile,
-- with the proxy's macro aimed at that tile's own unit token. Override bindings
-- may only change in combat through frame-handle methods in the restricted
-- environment, which is exactly what the wrappers use.
--
-- Only tokens that keep their meaning without addon intervention qualify:
-- player/pet, party/raid slots and their pets, target, focus, bossN and arenaN.
-- nameplateN and chained "...target" aliases are excluded: tiles are not rebound
-- in combat, those tokens may be reused for another unit, and this client
-- rejected native nameplate actions in earlier live checks. Such tiles keep the
-- existing behaviour (key goes to its original action).
--
-- No target change, no saved binding, no macro creation. User macros on the
-- action bars are never taken over; only plain spell actions found by
-- NearbyCast.DiscoverActions are used.
local Hover={rows={},installed=setmetatable({}, {__mode="k"}),proxies={friendly={},enemy={}},
    counts={friendly=0,enemy=0},keys={friendly=0,enemy=0}}
NS.CombatHover=Hover

local SIDES={"friendly","enemy"}
local RELATION={friendly="help",enemy="harm"}
local SIDE_OFFSET={friendly=0,enemy=100}
local MAX_KEYS=48
-- Main action bar paging (stances, forms, stealth, vehicles, override bars).
-- Keys from the main bar are only bound in combat while this state still
-- equals the state recorded when the spells were read.
local BAR_DRIVER="[vehicleui] v; [overridebar] o; [possessbar] p; "
    .."[bonusbar:5] b5; [bonusbar:4] b4; [bonusbar:3] b3; [bonusbar:2] b2; [bonusbar:1] b1; "
    .."[form:10] f10; [form:9] f9; [form:8] f8; [form:7] f7; [form:6] f6; "
    .."[form:5] f5; [form:4] f4; [form:3] f3; [form:2] f2; [form:1] f1; [form] unknown; "
    .."[actionbar:6] a6; [actionbar:5] a5; [actionbar:4] a4; [actionbar:3] a3; [actionbar:2] a2; a1"

local function idle()
    if type(InCombatLockdown)~="function" then return false end
    local ok,value=pcall(InCombatLockdown)
    return ok and NS.Public(value) and value==false
end

local function plain(value)
    return NS.Public(value) and type(value)=="string" and value~=""
        and not value:find("[%z\1-\31\127%[%]|;\\]")
        and not value:match("^%s") and not value:match("%s$") and value or nil
end

local FIXED={player=true,pet=true,target=true,focus=true}
local RANGES={party={1,4},partypet={1,4},raid={1,40},raidpet={1,40},boss={1,8},arena={1,5}}

function Hover.StableUnit(unit)
    if not NS.Public(unit) or type(unit)~="string" then return false end
    if FIXED[unit] then return true end
    local base,index=unit:match("^(%l+)(%d+)$")
    local range=base and RANGES[base]
    index=tonumber(index)
    return range~=nil and index~=nil and index%1==0 and index>=range[1] and index<=range[2]
end

local function enabled()
    if NS.GUIDProbeSuspended or not (NS.NearbyCast and NS.NearbyCast.legacyName==true) then return false end
    if NS.Public(NS.CombatHoverEnabled) and NS.CombatHoverEnabled==false then return false end
    return NS.DB and NS.Public(NS.DB.legacyNameBridgeEnabled) and NS.DB.legacyNameBridgeEnabled==true or false
end

-- Shared restricted body. Expects locals ctl (owner handle) and row (tile handle).
local BIND=[[
    if ctl:GetAttribute("mfch-enabled") and row:GetAttribute("mfch-ready") and row:IsVisible() then
        local unit = row:GetAttribute("unit")
        local side = row:GetAttribute("mfch-side")
        local relation = side and ctl:GetAttribute(side .. "-relation")
        if unit and relation and unit == row:GetAttribute("mfch-unit") then
            local bar = ctl:GetAttribute("state-mfchbar")
            local preparedBar = ctl:GetAttribute(side .. "-bar")
            local count = ctl:GetAttribute(side .. "-keys") or 0
            for i = 1, count do
                local key = ctl:GetAttribute(side .. "-key" .. i)
                local index = ctl:GetAttribute(side .. "-keyproxy" .. i)
                local paged = ctl:GetAttribute(side .. "-keypaged" .. i)
                local name = index and ctl:GetAttribute(side .. "-proxyname" .. index)
                local proxy = index and ctl:GetFrameRef(side .. "-proxy" .. index)
                local spell = proxy and proxy:GetAttribute("mfch-spell")
                if key and name and spell and (not paged or (bar and bar ~= "unknown" and bar == preparedBar)) then
                    proxy:SetAttribute("macrotext", "/cast [@" .. unit .. ",exists," .. relation .. "] " .. spell)
                    ctl:SetBindingClick(true, key, name, "LeftButton")
                end
            end
        end
    end
]]

local ENTER=[[
    -- Crossing between controllers may deliver the new Enter before the old
    -- Leave. Retire the previous owners before installing this row's route.
    control:ClearBindings()
    local nearby = control:GetFrameRef("mfch-nearbyOwner")
    if nearby then nearby:ClearBindings() end
    local names = control:GetFrameRef("mfch-nameOwner")
    if names then
        names:ClearBindings()
        names:SetAttribute("combat-hover-index", nil)
    end
    control:SetAttribute("mfch-hover", self:GetAttribute("mfch-index"))
    if control:GetAttribute("mfch-combat") then
        local ctl, row = control, self
]]..BIND..[[
    end
]]

local LEAVE=[[
    if control:GetAttribute("mfch-hover") == self:GetAttribute("mfch-index") then
        control:SetAttribute("mfch-hover", nil)
        control:ClearBindings()
        -- Native OnLeave wrappers share _wrapentered; an outer wrapper consumes
        -- it before inner pre-bodies run. Clear each participating owner here.
        local nearby = control:GetFrameRef("mfch-nearbyOwner")
        if nearby then nearby:ClearBindings() end
        local names = control:GetFrameRef("mfch-nameOwner")
        if names and names:GetAttribute("combat-hover-index") == self:GetAttribute("combat-row-index") then
            names:ClearBindings()
            names:SetAttribute("combat-hover-index", nil)
        end
    end
]]

local STATE=[[
    self:ClearBindings()
    self:SetAttribute("mfch-combat", newstate == "combat")
    if newstate == "combat" then
        local index = self:GetAttribute("mfch-hover")
        local row = index and self:GetFrameRef("mfch-row" .. index)
        if row and row:IsUnderMouse() then
            local ctl = self
]]..BIND..[[
        end
    end
]]
-- State drivers update even if the cursor does not move. Drop stale page keys
-- and only rebind those still valid for the current page and hovered row.
local PAGE=[[
    self:ClearBindings()
    if self:GetAttribute("mfch-combat") then
        local index = self:GetAttribute("mfch-hover")
        local row = index and self:GetFrameRef("mfch-row" .. index)
        if row and row:IsUnderMouse() then
            local ctl = self
]]..BIND..[[
        end
    end
]]
Hover.Snippets={BIND=BIND,ENTER=ENTER,LEAVE=LEAVE,STATE=STATE,PAGE=PAGE}

local function owner()
    if Hover.owner then return Hover.owner end
    if not idle() or type(SecureHandlerWrapScript)~="function" or type(RegisterStateDriver)~="function" then return nil end
    local frame=CreateFrame("Frame","MyForeverTargetsCombatHoverOwner",UIParent,"SecureHandlerStateTemplate")
    frame:SetAttribute("friendly-relation",RELATION.friendly)
    frame:SetAttribute("enemy-relation",RELATION.enemy)
    frame:SetAttribute("_onstate-mfchcombat",STATE)
    frame:SetAttribute("_onstate-mfchbar",PAGE)
    RegisterStateDriver(frame,"mfchbar",BAR_DRIVER)
    RegisterStateDriver(frame,"mfchcombat","[combat] combat; idle")
    Hover.owner=frame
    return frame
end

local function proxyFor(frame,side,index)
    local list=Hover.proxies[side]
    local proxy=list[index]
    if not proxy then
        proxy=CreateFrame("Button","MyForeverTargetsCombatHover"..side..index,frame,"SecureActionButtonTemplate")
        proxy:SetSize(1,1)
        proxy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10,10)
        proxy:EnableMouse(false)
        proxy:SetAttribute("type","macro")
        list[index]=proxy
    end
    return proxy
end

local function pagedCommand(command)
    return type(command)=="string" and (command:match("^ACTIONBUTTON%d+$")~=nil
        or command:match("^CLICK ActionButton%d+:")~=nil)
end

-- Read the action bars for one side and publish key -> proxy attributes.
local function prepareSide(frame,side)
    local nearby=NS.NearbyCast
    local actions={}
    if enabled() and nearby and type(nearby.DiscoverActions)=="function" then
        local ok,result=pcall(nearby.DiscoverActions,side,true)
        if ok and type(result)=="table" then actions=result end
    end
    local proxyCount,keyCount=0,0
    for _,entry in ipairs(actions) do
        local spell=entry.actionKind=="spell" and plain(entry.spell)
        if spell and type(entry.keys)=="table" and keyCount<MAX_KEYS then
            proxyCount=proxyCount+1
            local proxy=proxyFor(frame,side,proxyCount)
            proxy.entry=entry
            proxy:SetAttribute("mfch-spell",spell)
            proxy:SetAttribute("macrotext",nil)
            proxy:SetAttribute("useOnKeyDown",entry.useOnKeyDown==true)
            proxy:RegisterForClicks(entry.useOnKeyDown==true and "AnyDown" or "AnyUp")
            frame:SetFrameRef(side.."-proxy"..proxyCount,proxy)
            frame:SetAttribute(side.."-proxyname"..proxyCount,proxy:GetName())
            for _,key in ipairs(entry.keys) do
                if plain(key) and keyCount<MAX_KEYS then
                    keyCount=keyCount+1
                    frame:SetAttribute(side.."-key"..keyCount,key)
                    frame:SetAttribute(side.."-keyproxy"..keyCount,proxyCount)
                    frame:SetAttribute(side.."-keypaged"..keyCount,pagedCommand(entry.command) or nil)
                end
            end
        end
    end
    -- Retire stale entries from a previous, longer action list.
    for i=keyCount+1,Hover.keys[side] do
        frame:SetAttribute(side.."-key"..i,nil)
        frame:SetAttribute(side.."-keyproxy"..i,nil)
        frame:SetAttribute(side.."-keypaged"..i,nil)
    end
    for i=proxyCount+1,#Hover.proxies[side] do
        local proxy=Hover.proxies[side][i]
        proxy.entry=nil
        proxy:SetAttribute("mfch-spell",nil)
        proxy:SetAttribute("macrotext",nil)
        frame:SetAttribute(side.."-proxyname"..i,nil)
    end
    frame:SetAttribute(side.."-keys",keyCount)
    frame:SetAttribute(side.."-bar",frame:GetAttribute("state-mfchbar"))
    Hover.counts[side],Hover.keys[side]=proxyCount,keyCount
end

local function rowIndex(row)
    local offset=SIDE_OFFSET[row and row.side]
    if not offset or not NS.Number(row.index) then return nil end
    return offset+row.index
end

local function linkOwners(frame)
    local nearby=NS.NearbyCast and NS.NearbyCast.owner
    local names=NS.CombatCast and NS.CombatCast.owner
    if nearby then frame:SetFrameRef("mfch-nearbyOwner",nearby) end
    if names then frame:SetFrameRef("mfch-nameOwner",names) end
end

-- Publish one tile's eligibility. Tiles are only rebound out of combat, so the
-- unit recorded here is the unit the tile keeps showing during combat.
function Hover.BindRow(row)
    if not idle() or not Hover.installed[row] or not Hover.owner then return false end
    local unit=row.unit
    local ready=enabled() and Hover.StableUnit(unit) and NS.Read(row.GetAttribute,row,"unit")==unit
    row:SetAttribute("mfch-unit",ready and unit or nil)
    row:SetAttribute("mfch-ready",ready or nil)
    return ready
end

local function bridgeMode()
    local nearby=NS.NearbyCast
    return nearby~=nil and nearby.legacyName==true
end

function Hover.Install(row)
    if Hover.installed[row] then return true end
    if not idle() then Hover.dirty=true;return false end
    if not bridgeMode() then return false end
    if not row or not SIDE_OFFSET[row.side] then return false end
    local frame=owner()
    local index=frame and rowIndex(row)
    if not index then return false end
    linkOwners(frame)
    row:SetAttribute("mfch-index",index)
    row:SetAttribute("mfch-side",row.side)
    frame:SetFrameRef("mfch-row"..index,row)
    SecureHandlerWrapScript(row,"OnEnter",frame,ENTER)
    SecureHandlerWrapScript(row,"OnLeave",frame,LEAVE)
    SecureHandlerWrapScript(row,"OnHide",frame,LEAVE)
    Hover.installed[row]=true
    Hover.rows[#Hover.rows+1]=row
    Hover.BindRow(row)
    Hover.dirty=true
    return true
end

function Hover.Sync()
    if not idle() then Hover.dirty=true;return false end
    local frame=owner()
    if not frame then return false end
    linkOwners(frame)
    Hover.dirty=false
    -- Tiles created while combat blocked the owner are installed here.
    local ui=NS.UI
    if type(ui)=="table" then
        for _,side in ipairs(SIDES) do
            local section=ui[side]
            if type(section)=="table" and type(section.tiles)=="table" then
                for _,row in ipairs(section.tiles) do
                    if not Hover.installed[row] then Hover.Install(row) end
                end
            end
        end
    end
    frame:SetAttribute("mfch-enabled",enabled() or nil)
    for _,side in ipairs(SIDES) do prepareSide(frame,side) end
    for _,row in ipairs(Hover.rows) do Hover.BindRow(row) end
    return true
end

function Hover.Status(row)
    local status={enabled=enabled(),friendlyKeys=Hover.keys.friendly,enemyKeys=Hover.keys.enemy,
        friendlySpells=Hover.counts.friendly,enemySpells=Hover.counts.enemy}
    if row then
        status.unit=row.unit
        status.stable=Hover.StableUnit(row.unit)
        status.availableKeys=0
        local frame=Hover.owner
        local side=row.side
        if frame and SIDE_OFFSET[side] then
            local bar=NS.Read(frame.GetAttribute,frame,"state-mfchbar")
            local prepared=NS.Read(frame.GetAttribute,frame,side.."-bar")
            for i=1,Hover.keys[side] do
                local paged=NS.Read(frame.GetAttribute,frame,side.."-keypaged"..i)
                if paged~=true or plain(bar) and bar~="unknown" and bar==prepared then
                    status.availableKeys=status.availableKeys+1
                end
            end
        end
        status.ready=status.enabled and status.availableKeys>0 and Hover.installed[row]
            and NS.Read(row.GetAttribute,row,"mfch-ready")==true or false
    end
    return status
end

local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED","UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","UPDATE_BONUS_ACTIONBAR","UPDATE_OVERRIDE_ACTIONBAR","UPDATE_SHAPESHIFT_FORM",
    "SPELLS_CHANGED","UPDATE_MACROS","GROUP_ROSTER_UPDATE","CVAR_UPDATE"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function() Hover.dirty=true end)
local elapsed,lastEnabled=0,nil
events:SetScript("OnUpdate",function(_,delta)
    elapsed=elapsed+delta
    if elapsed<.5 then return end
    elapsed=0
    if not idle() then return end
    local now=enabled()
    if now~=lastEnabled then lastEnabled=now;Hover.dirty=true end
    if Hover.dirty then Hover.Sync() end
end)
