local _, NS = ...
-- This is a plain Lua visual roster. It never retargets a secure button, moves a
-- frame, prepares a spell or writes an input binding while combat is active.
local Display={active=false,slots={}}
NS.EnemyDisplay=Display
local tokenEpochs,tombstones,epoch={}, {},0
local worldActive=true

local function plate(unit)
    return NS.ValidToken(unit) and unit:match("^nameplate%d+$")~=nil
end

local function nextEpoch(unit)
    epoch=epoch+1
    tokenEpochs[unit]=epoch
    return epoch
end

local function identity(value)
    return NS.Public(value) and type(value)=="string" and value~="" and value or nil
end

local function snapshot(unit,expected)
    if not NS.ValidToken(unit) then return nil end
    local data=NS.Read(NS.ReadUnit,unit,"enemy")
    local guid=NS.Public(data) and type(data)=="table" and identity(data.guid) or nil
    if not guid or expected and guid~=expected or NS.Read(UnitGUID,unit)~=guid then return nil end
    return {unit=unit,guid=guid}
end

local function heldBy(module,row,ownerKey,rowKey)
    local owner=module and module.owner
    if not owner then return false end
    local prepared=not NS.Public(row.expectedGUID) or identity(row.expectedGUID)~=nil
    local ok,index=pcall(function() return owner:GetAttribute(ownerKey) end)
    if not ok or not NS.Public(index) then return prepared end
    if index==nil then return false end
    if not NS.Number(index) or index%1~=0 then return prepared end
    local rowOK,rowIndex=pcall(function() return row:GetAttribute(rowKey) end)
    if not rowOK or not NS.Public(rowIndex) then return prepared end
    return rowIndex==index
end

local function emptyActionCell(row)
    if not NS.Public(row.unit) or not NS.Public(row.expectedGUID)
        or row.unit~=nil or row.expectedGUID~=nil then return false end
    for _,key in ipairs({"unit","combat-prepared","mfch-ready"}) do
        local ok,value=pcall(function() return row:GetAttribute(key) end)
        if not ok or not NS.Public(value) then return false end
        if key=="unit" then
            if value~=nil then return false end
        elseif value~=nil and value~=false then return false end
    end
    return true
end

function Display.IsCurrent(entry)
    return worldActive and NS.Public(entry) and type(entry)=="table" and NS.Public(entry.restrictedIdentity) and entry.restrictedIdentity==true
        and plate(entry.unit) and NS.Number(entry.tokenEpoch) and not tombstones[entry.unit]
        and tokenEpochs[entry.unit]==entry.tokenEpoch
end

-- Public metadata only: diagnostics may explain a frozen address without
-- reading its identity or changing/initializing any lifecycle bookkeeping.
function Display.LifecycleState(unit)
    local valid=plate(unit)
    local value=valid and tokenEpochs[unit] or nil
    local known=NS.Number(value) and value>0 and value%1==0
    return {validToken=valid==true,worldActive=worldActive==true,epochKnown=known,
        currentEpoch=known and value or nil,tombstoned=valid and tombstones[unit]==true or false}
end

local function restrictedSnapshot(unit)
    if not worldActive or not plate(unit) or tombstones[unit] then return nil end
    local payload=NS.Read(NS.ReadRestrictedEnemyVisual,unit)
    if not NS.Public(payload) or type(payload)~="table" or not NS.Public(payload.restrictedIdentity)
        or payload.restrictedIdentity~=true then return nil end
    return {unit=unit,restrictedIdentity=true,tokenEpoch=tokenEpochs[unit] or nextEpoch(unit)}
end

function Display.Update(tokens,limit,rows,restrictedTokens)
    limit=NS.Number(limit) and math.max(0,math.min(20,math.floor(limit))) or 20
    local ordered,byGUID={},{}
    if NS.Public(tokens) and type(tokens)=="table" then
        for _,unit in ipairs(tokens) do
            local data=snapshot(unit)
            if data and not byGUID[data.guid] then
                byGUID[data.guid]=data;ordered[#ordered+1]=data
            end
        end
    end
    local slots,used,reserved={},{},{}
    local combat=NS.InCombat()
    local function retain(index,unit,guid,allowAlias)
        guid=identity(guid)
        if not guid or used[guid] then return end
        local data=snapshot(unit,guid) or allowAlias~=false and byGUID[guid]
        if data then slots[index]=data;used[guid]=true end
    end
    local function retainPrepared(allowAlias)
        if not NS.Public(rows) or type(rows)~="table" then return end
        for i=1,limit do
            local row=rows[i]
            if not slots[i] and not reserved[i] and NS.Public(row) and type(row)=="table" then
                retain(i,row.unit,row.expectedGUID,allowAlias)
            end
        end
    end
    -- Showing an input shield may produce a non-motion OnLeave. The client's
    -- secure wrapper can then retain the old spell owner, so no different GUID
    -- may be displayed in that cell until its protected hover index is clear.
    if NS.Public(rows) and type(rows)=="table" then
        for i=1,limit do
            local row=rows[i]
            if NS.Public(row) and type(row)=="table" then
                if combat then
                    reserved[i]=heldBy(NS.CombatCast,row,"combat-hover-index","combat-row-index")
                        or heldBy(NS.CombatHover,row,"mfch-hover","mfch-index")
                else
                    -- A held OOC roster can still arm its old action on the
                    -- next combat state change using geometric IsUnderMouse.
                    -- Only an actually unbound cell may receive a new identity.
                    reserved[i]=not emptyActionCell(row)
                end
                if reserved[i] then retain(i,row.unit,row.expectedGUID,false) end
            end
        end
    end
    -- Outside combat the just-bound public action roster always owns its own
    -- cells. A previous visual entry must not displace a new prepared action.
    if not combat then retainPrepared(false) end
    -- Keep an established visual identity in its cell even if its alias changed.
    for i=1,limit do
        local old=Display.slots[i]
        if old and not old.restrictedIdentity and not slots[i] and not reserved[i] then retain(i,old.unit,old.guid) end
    end
    -- On the first combat refresh, prefer the still-live prepared cell identity.
    if combat then retainPrepared(true) end
    local free=1
    for _,data in ipairs(ordered) do
        if not used[data.guid] then
            while free<=limit and (slots[free] or reserved[free]) do free=free+1 end
            if free>limit then break end
            slots[free]=data;used[data.guid]=true
        end
    end
    -- Restricted names/GUIDs are not identities that Lua can compare. These
    -- entries are token addresses scoped by nameplate lifecycle only, with no
    -- synthetic GUID or names/amounts cached in the visual roster.
    local anonymous,byToken={},{}
    if NS.Public(restrictedTokens) and type(restrictedTokens)=="table" then
        for _,unit in ipairs(restrictedTokens) do
            local entry=restrictedSnapshot(unit)
            if entry and not byToken[entry.unit] then
                anonymous[#anonymous+1]=entry;byToken[entry.unit]=entry
            end
        end
    end
    local usedTokens={}
    for i=1,limit do
        local old=Display.slots[i]
        if not slots[i] and not reserved[i] and old and Display.IsCurrent(old)
            and byToken[old.unit] and not usedTokens[old.unit] then
            slots[i]=byToken[old.unit];usedTokens[old.unit]=true
        end
    end
    free=1
    for _,entry in ipairs(anonymous) do
        if not usedTokens[entry.unit] then
            while free<=limit and (slots[free] or reserved[free]) do free=free+1 end
            if free>limit then break end
            slots[free]=entry;usedTokens[entry.unit]=true
        end
    end
    Display.slots,Display.active=slots,true
end

function Display.OnEvent(event,unit)
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" then
        worldActive=event=="PLAYER_ENTERING_WORLD"
        epoch=epoch+1
        tokenEpochs,tombstones={},{}
        Display.Reset()
    elseif (event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED") and plate(unit) then
        nextEpoch(unit)
        tombstones[unit]=event=="NAME_PLATE_UNIT_REMOVED" or nil
        for i=1,20 do
            local entry=Display.slots[i]
            if entry and entry.unit==unit then Display.slots[i]=nil end
        end
    end
end

function Display.Get(index)
    if not NS.Number(index) or index%1~=0 or index<1 or index>20 then return nil end
    return Display.slots[index]
end

-- Native-action experiments keep an address fixed without inventing a GUID.
-- This only exposes the existing, lifecycle-checked read-only snapshot.
function Display.RestrictedEntry(unit)
    return restrictedSnapshot(unit)
end

function Display.Reset()
    Display.active,Display.slots=false,{}
end
