local _, NS = ...
local classColors = {
    WARRIOR={r=0.78,g=0.61,b=0.43},PALADIN={r=0.96,g=0.55,b=0.73},
    HUNTER={r=0.67,g=0.83,b=0.45},ROGUE={r=1,g=0.96,b=0.41},PRIEST={r=1,g=1,b=1},
    SHAMAN={r=0,g=0.44,b=0.87},MAGE={r=0.25,g=0.78,b=0.92},
    WARLOCK={r=0.53,g=0.53,b=0.93},DRUID={r=1,g=0.49,b=0.04},
    DEATHKNIGHT={r=0.77,g=0.12,b=0.23},MONK={r=0,g=1,b=0.60},
    DEMONHUNTER={r=0.64,g=0.19,b=0.79},EVOKER={r=0.20,g=0.58,b=0.50},
}
local powerTypes = {[0]="MANA",[1]="RAGE",[2]="FOCUS",[3]="ENERGY",[4]="COMBO_POINTS",
    [5]="RUNES",[6]="RUNIC_POWER",[7]="SOUL_SHARDS",[8]="LUNAR_POWER",[9]="HOLY_POWER",
    [11]="MAELSTROM",[12]="CHI",[13]="INSANITY",[16]="ARCANE_CHARGES",[17]="FURY",
    [18]="PAIN",[19]="ESSENCE"}
local powerColors = {
    MANA={r=.12,g=.38,b=1},RAGE={r=1,g=.18,b=.12},FOCUS={r=1,g=.52,b=.18},
    ENERGY={r=1,g=.87,b=.12},COMBO_POINTS={r=1,g=.87,b=.25},RUNES={r=.55,g=.65,b=.72},
    RUNIC_POWER={r=0,g=.82,b=1},SOUL_SHARDS={r=.72,g=.35,b=.92},
    LUNAR_POWER={r=.30,g=.55,b=.95},HOLY_POWER={r=.95,g=.90,b=.60},
    MAELSTROM={r=0,g=.55,b=1},CHI={r=.45,g=1,b=.78},INSANITY={r=.66,g=.25,b=.88},
    ARCANE_CHARGES={r=.30,g=.65,b=1},FURY={r=.79,g=.26,b=.99},PAIN={r=1,g=.61,b=0},
    ESSENCE={r=.25,g=.85,b=.70},
}

local function rawNumber(fn,...)
    if type(fn)~="function" then return nil,false end
    local ok,value=pcall(fn,...)
    if not ok or type(value)~="number" then return nil,false end
    if NS.Public(value) and not NS.Number(value) then return nil,false end
    return value,true
end

local function readAmounts(currentAPI,maximumAPI,...)
    local current,hasCurrent=rawNumber(currentAPI,...)
    local maximum,hasMaximum=rawNumber(maximumAPI,...)
    if not hasCurrent or not hasMaximum then return nil,nil,nil,false end
    -- Secret numeric amounts may only flow into the native StatusBar sinks.
    -- Validate and divide only values explicitly known to be public.
    local currentPublic,maximumPublic=NS.Public(current),NS.Public(maximum)
    if currentPublic and current<0 or maximumPublic and maximum<=0 then return nil,nil,nil,false end
    local ratio
    if currentPublic and maximumPublic then ratio=math.max(0,math.min(1,current/maximum)) end
    return ratio,current,maximum,true
end

local function readPower(unit)
    local kind,token=NS.Read(UnitPowerType,unit)
    if not NS.Number(kind) or kind<0 or kind%1~=0 then return nil,nil,nil,nil,nil,false end
    token=NS.Text(token)
    if token=="" then token=powerTypes[kind] end
    local color=token and powerColors[token]
    if not color then return nil,nil,nil,nil,nil,false end
    local ratio,current,maximum,available=readAmounts(UnitPower,UnitPowerMax,unit,kind)
    if not available then return nil,nil,nil,nil,nil,false end
    return ratio,token,color,current,maximum,true
end

local function targetName(unit,player,name)
    if player then
        local canonical=NS.Text(NS.Read(NameUtil and NameUtil.GetUnmodifiedUnitFullName,unit))
        if canonical~="" then return canonical end
        local first,realm=NS.Read(UnitFullName or UnitName,unit)
        first,realm=NS.Text(first),NS.Text(realm)
        if first~="" then return realm~="" and (first.."-"..realm) or first end
    end
    return name
end

-- Public relationship labels plus numeric health for native StatusBar sinks.
-- The secure target rectangle binds a fixed relationship token; these snapshots
-- never rewrite its unit during combat.
function NS.ReadEnemyTarget(unit, expectedGUID)
    if not NS.ValidToken(unit) or not NS.Public(expectedGUID)
        or type(expectedGUID)~="string" or expectedGUID=="" then
        return {state="unavailable"}
    end
    if NS.Read(UnitGUID,unit)~=expectedGUID then return {state="unavailable"} end

    local targetUnit=unit.."target"
    local exists=NS.Read(UnitExists,targetUnit)
    local result={state="unavailable"}
    if exists==false then
        -- An absent exposed token does not establish that the enemy itself has
        -- no target: some clients do not expose nameplate target relationships.
        result.state="absent"
    elseif exists==true then
        local guid=NS.Read(UnitGUID,targetUnit)
        local name=NS.Text(NS.Read(UnitName,targetUnit))
        if name~="" then
            local player=NS.Read(UnitIsPlayer,targetUnit)
            local className,classToken="",""
            if player==true then
                className,classToken=NS.Read(UnitClass,targetUnit)
                className,classToken=NS.Text(className),NS.Text(classToken)
            end
            local color=player==true and classColors[classToken] or nil
            local ratio,healthCurrent,healthMax,healthAvailable=readAmounts(UnitHealth,UnitHealthMax,targetUnit)
            local connected=NS.Read(UnitIsConnected,targetUnit)
            local offline
            if connected==true then offline=false elseif connected==false then offline=true end
            result={state="known",name=name,color=color or {r=.82,g=.85,b=.9},
                targetName=targetName(targetUnit,player==true,name),offline=offline,
                player=player,classToken=classToken,
                className=player==true and (className~="" and className or "玩家")
                    or player==false and "非玩家" or "未知",
                health=ratio,healthCurrent=healthCurrent,healthMax=healthMax,healthAvailable=healthAvailable,
                assist=NS.Read(UnitCanAssist,"player",targetUnit)==true,
                harm=NS.Read(UnitCanAttack,"player",targetUnit)==true,
                dead=NS.Read(UnitIsDeadOrGhost,targetUnit)}
            -- Reject a victim change across any of the name/class/health reads,
            -- not just its hover identity: all displayed fields belong together.
            local afterGUID=NS.Read(UnitGUID,targetUnit)
            if afterGUID~=guid then
                result={state="unavailable"}
            elseif type(guid)=="string" and guid~="" then
                result.guid=guid
            end
        end
    end

    -- A volatile nameplate or target alias may have been reused while its
    -- relationship was read. Never publish that result for the old row owner.
    if NS.Read(UnitGUID,unit)~=expectedGUID then return {state="unavailable"} end
    return result
end

function NS.ReadUnit(unit, side)
    if not NS.ValidToken(unit) or (side ~= "friendly" and side ~= "enemy") then return nil end
    if NS.Read(UnitExists,unit) ~= true then return nil end
    local player = NS.Read(UnitIsPlayer,unit)
    if player~=true and player~=false then return nil end
    if side == "friendly" then
        local friend = NS.Read(UnitCanAssist or UnitIsFriend,"player",unit)
        if player ~= true or friend ~= true then return nil end
    elseif NS.Read(UnitCanAttack,"player",unit) ~= true then return nil end
    local guid, name = NS.Read(UnitGUID,unit), NS.Text(NS.Read(UnitName,unit))
    if type(guid) ~= "string" or guid == "" or name == "" then return nil end
    local className, classToken = NS.Read(UnitClass,unit)
    className, classToken = NS.Text(className), NS.Text(classToken)
    local color = player == true and classColors[classToken] or nil
    local ratio,healthCurrent,healthMax,healthAvailable=readAmounts(UnitHealth,UnitHealthMax,unit)
    local powerRatio,powerToken,powerColor,powerCurrent,powerMax,powerAvailable=readPower(unit)
    local marker = NS.Read(GetRaidTargetIndex,unit)
    if not NS.Number(marker) or marker < 1 or marker > 8 or marker % 1 ~= 0 then marker = nil end
    local targetGUID=NS.Read(UnitGUID,"target")
    local selected=NS.Read(UnitIsUnit,unit,"target")==true
        or (type(targetGUID)=="string" and targetGUID~="" and targetGUID==guid)
    local questTarget,questTitle=false,nil
    if side=="enemy" and player==false and NS.IsQuestTarget then questTarget,questTitle=NS.IsQuestTarget(unit) end
    return {unit=unit,guid=guid,name=name,targetName=targetName(unit,player==true,name),classToken=classToken,
        className=player == true and (className ~= "" and className or "玩家") or "怪物",
        player=player == true,color=color or (side == "enemy" and {r=1,g=0.40,b=0.34} or {r=.75,g=.80,b=.85}),
        health=ratio, dead=NS.Read(UnitIsDeadOrGhost,unit)==true,
        healthCurrent=healthCurrent,healthMax=healthMax,healthAvailable=healthAvailable,
        powerRatio=powerRatio,powerToken=powerToken,powerColor=powerColor,
        powerCurrent=powerCurrent,powerMax=powerMax,powerAvailable=powerAvailable,
        offline=NS.Read(UnitIsConnected,unit)==false,raidMarker=marker,
        target=selected,questTarget=questTarget==true,questTitle=questTitle}
end

local function addGroup(tokens, all)
    tokens[#tokens+1]="player"
    for i=1,(all and 40 or 20) do tokens[#tokens+1]="raid"..i end
    for i=1,4 do tokens[#tokens+1]="party"..i end
end

local function addActionUnits(tokens)
    -- HealBot uses these native unit aliases for enemy bars. Prefer an exposed
    -- alias before a read-only nameplate for the same GUID, so a real unit can
    -- keep the client's native targeting and casting path.
    tokens[#tokens+1]="target"
    tokens[#tokens+1]="focus"
    tokens[#tokens+1]="targettarget"
    tokens[#tokens+1]="focustarget"
    for i=1,4 do tokens[#tokens+1]="party"..i.."target" end
    for i=1,40 do tokens[#tokens+1]="raid"..i.."target" end
    for i=1,8 do tokens[#tokens+1]="boss"..i end
    for i=1,5 do tokens[#tokens+1]="arena"..i end
end

function NS.NameplateTokens()
    local found = {}
    for unit in pairs(NS.Nameplates) do if NS.ValidToken(unit) then found[unit]=true end end
    local plates = NS.Read(C_NamePlate and C_NamePlate.GetNamePlates)
    if type(plates)=="table" then
        for _,plate in ipairs(plates) do
            if NS.Public(plate) and (type(plate)=="table" or type(plate)=="userdata") then
                -- Some client-owned frames reject field access as well as method calls.
                local ok, unit=pcall(function()
                    if NS.Read(plate.IsForbidden,plate)==true then return nil end
                    return plate.namePlateUnitToken
                end)
                if ok and NS.ValidToken(unit) then found[unit]=true end
            end
        end
    end
    -- Also discover plates that existed before ADDON_LOADED or whose event was missed.
    for i=1,40 do
        local unit="nameplate"..i
        if NS.Read(UnitExists,unit)==true then found[unit]=true end
    end
    local tokens={}
    for unit in pairs(found) do tokens[#tokens+1]=unit end
    table.sort(tokens,function(a,b)
        return (tonumber(a:match("(%d+)$")) or 0)<(tonumber(b:match("(%d+)$")) or 0)
    end)
    return tokens
end

function NS.Collect(side, mode, limit)
    local tokens, visibleOnly={},false
    if side=="friendly" and mode=="raid" then
        limit=20
        for i=1,20 do tokens[#tokens+1]="raid"..i end
    elseif side=="friendly" and mode=="party" then
        limit=5
        tokens={"player","party1","party2","party3","party4"}
    else
        if limit~=5 and limit~=10 and limit~=20 then limit=20 end
        visibleOnly=true
        -- Prefer stable group tokens over volatile target/nameplate aliases for the same player.
        if side=="friendly" then addGroup(tokens,true) end
        addActionUnits(tokens)
        for _,unit in ipairs(NS.NameplateTokens()) do tokens[#tokens+1]=unit end
    end
    local result, seen, candidates={}, {}, {}
    for _,unit in ipairs(tokens) do
        local data=NS.ReadUnit(unit,side)
        -- A live nameplate already proves the client exposed this nearby unit.
        -- UnitIsVisible can be restricted even when the plate token is readable.
        local visible=not visibleOnly or unit=="player" or NS.Read(UnitIsVisible,unit)==true or unit:match("^nameplate")
        if data and visible and not seen[data.guid] then
            seen[data.guid]=true
            candidates[#candidates+1]={unit=unit,index=#candidates+1,
                range=visibleOnly and NS.MeasureDistance and NS.MeasureDistance(unit) or nil}
        end
    end
    if visibleOnly then
        table.sort(candidates,function(a,b)
            if a.range and not b.range then return true end
            if b.range and not a.range then return false end
            -- Upper bounds give a deterministic order for estimated ranges. No
            -- exact ordering is claimed between units inside the same range band.
            if a.range and b.range and a.range.max~=b.range.max then return a.range.max<b.range.max end
            return a.index<b.index
        end)
    end
    -- Rank all eligible units before clipping; a late-discovered near unit must
    -- displace a farther unit when the player chooses five or ten slots.
    for i=1,math.min(limit,#candidates) do result[i]=candidates[i].unit end
    return result,#candidates
end
