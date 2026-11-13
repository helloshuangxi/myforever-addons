local _, NS = ...
-- The explicitly authorized name bridge uses temporary hardware-key routing
-- outside combat. User macros, items and the disabled GUID routes stay separate.
local Cast = {proxies={}, installed=setmetatable({}, {__mode="k"})}
NS.NearbyCast = Cast
local legacyNameOnly=NS.Public(NS.NativeMacroOnly) and NS.NativeMacroOnly==true
    and NS.Public(NS.LegacyNameBridge) and NS.LegacyNameBridge==true
Cast.legacyName=legacyNameOnly

-- This startup policy requires a UI reload. Native mouseover macros keep their
-- original action slots and keys; no bridge frame, event, or action is installed.
if not legacyNameOnly and (not NS.Public(NS.NativeMacroOnly) or NS.NativeMacroOnly~=false) then
    local function unused() return nil end
    local function disabled() return false,0 end
    Cast.native,Cast.count=true,0
    Cast.BuildGUIDMacro=unused
    Cast.BuildFallback=unused
    Cast.BuildMacro=unused
    Cast.GuardMacro=unused
    Cast.BuildUserMacro=unused
    Cast.BuildUserFallback=unused
    Cast.FrozenUserMacro=unused
    Cast.MacroHasHarmfulCast=function() return false end
    Cast.DiscoverActions=function() return {} end
    Cast.KnownUniqueNPC=function() return false end
    Cast.SnapshotRow=function() return nil,false end
    Cast.Install=disabled
    Cast.Enter=disabled
    Cast.Refresh=disabled
    Cast.Reconcile=disabled
    Cast.Leave=function() Cast.row=nil;Cast.count=0 end
    Cast.Status=function()
        return {native=true,prepared=false,count=0,reason="native_macro_only",castMode="native_mouseover"}
    end
    return
end

local function plain(value)
    if not NS.Public(value) or type(value)~="string" or value==""
        or value:find("[%z\1-\31\127%[%]|;\\]") then return nil end
    if value:match("^%s") or value:match("%s$") then return nil end
    return value
end

local function plainGUID(value)
    value=plain(value)
    if not value then return nil end
    local prefix,identity=value:match("^(%a+)%-([%x%-]+)$")
    if not prefix or not ({Creature=true,Vehicle=true,Pet=true,GameObject=true,Player=true})[prefix]
        or identity:sub(1,1)=="-" or identity:sub(-1)=="-" or identity:find("--",1,true) then return nil end
    return value
end

function Cast.BuildGUIDMacro(guid,spell)
    if legacyNameOnly then return nil end
    guid,spell=plainGUID(guid),plain(spell)
    if not guid or not spell then return nil end
    local macro="/cast [@"..guid.."] "..spell
    return #macro<=1023 and macro or nil
end

local function sideName(side)
    if not NS.Public(side) then return nil end
    if side==nil then return "friendly" end
    if side=="friendly" or side=="enemy" then return side end
end

function Cast.BuildFallback(spell,side)
    if not legacyNameOnly and NS.PreserveCastTarget==true then return nil end
    side=sideName(side)
    spell=plain(spell)
    if not spell or not side then return nil end
    if side=="enemy" then return (legacyNameOnly and "/stopmacro [dead]\n" or "")
        .."/cast [nocombat,@target,harm,nodead] "..spell end
    return (legacyNameOnly and "/stopmacro [dead]\n" or "")
        .."/cast [nocombat,@target,help,nodead][nocombat,@player] "..spell
end

local function namedAction(name,body,hasTarget)
    name=plain(name)
    if not name or type(body)~="string" or type(hasTarget)~="boolean" then return nil end
    -- Refuse a call that starts in combat. Once admitted, target restoration
    -- must still run if this cast itself begins combat before the last line.
    local macro=table.concat({legacyNameOnly and "/stopmacro [combat][dead]" or "/stopmacro [combat]","/cleartarget [nocombat]",
        "/targetexact [nocombat] "..name,body,
        hasTarget and "/targetlasttarget" or "/cleartarget"},"\n")
    if #macro>1023 then return nil end
    return macro
end

function Cast.BuildMacro(name,spell,hasTarget,side)
    if not legacyNameOnly and NS.PreserveCastTarget==true then return nil end
    side=sideName(side)
    name,spell=plain(name),plain(spell)
    if not name or not spell or not side or type(hasTarget)~="boolean" then return nil end
    local relation=side=="enemy" and "harm" or "help"
    return namedAction(name,"/cast [nocombat,@target,"..relation..",nodead] "..spell,hasTarget)
end

local function trim(value) return value:match("^%s*(.-)%s*$") end

local function guardClause(clause,combatGuard)
    clause=trim(clause)
    if clause=="" then return nil end
    if clause:sub(1,1)~="[" then
        if clause:find("[%[%]]") then return nil end
        return combatGuard==false and clause or ("[nocombat] "..clause),clause
    end
    local groups,position={},1
    while clause:sub(position,position)=="[" do
        local closing=clause:find("]",position+1,true)
        if not closing then return nil end
        local condition=clause:sub(position+1,closing-1)
        if condition:find("[%[%]]") then return nil end
        groups[#groups+1]=combatGuard==false and ("["..condition.."]")
            or ("[nocombat"..(condition~="" and (","..condition) or "").."]")
        position=closing+1
        -- The native condition parser accepts whitespace between OR groups.
        local rest=clause:sub(position)
        local spaces=rest:match("^%s*")
        if rest:sub(#spaces+1,#spaces+1)=="[" then position=position+#spaces else break end
    end
    local spell=trim(clause:sub(position))
    if spell=="" or spell:find("[%[%]]") then return nil end
    return table.concat(groups).." "..spell,spell
end

-- Allow only a single /cast line plus display metadata. In particular, never
-- copy /run, /use, chat, click chaining, targeting commands or cast sequences.
-- Each original OR/semicolon alternative gets its own combat condition; the
-- original modifier/unit conditions and spell text otherwise remain intact.
local function validateMacro(body,side,combatGuard)
    if legacyNameOnly then return nil end
    if not NS.Public(side) then return nil end
    side=side==nil and "enemy" or sideName(side)
    if side~="enemy" or not NS.Public(body) or type(body)~="string" or body==""
        or #body>1023 or body:find("[%z\1-\8\11\12\14-\31\127|\\]") then return nil end
    body=body:gsub("\r\n","\n"):gsub("\r","\n")
    local result,castCount={},0
    for line in (body.."\n"):gmatch("(.-)\n") do
        line=trim(line)
        if line~="" then
            local lower=line:lower()
            if lower=="#showtooltip" or lower:match("^#showtooltip%s+") then
                result[#result+1]=line
            elseif lower:match("^/cast%s+") then
                castCount=castCount+1
                if castCount>1 then return nil end
                local args=line:match("^/%S+%s+(.+)$")
                local alternatives={}
                for clause in (args..";"):gmatch("(.-);") do
                    local guarded=guardClause(clause,combatGuard)
                    if not guarded then return nil end
                    alternatives[#alternatives+1]=guarded
                end
                result[#result+1]="/cast "..table.concat(alternatives,"; ")
            else return nil end
        end
    end
    if castCount~=1 then return nil end
    local guarded=table.concat(result,"\n")
    if #guarded>1023 then return nil end
    return guarded
end

function Cast.GuardMacro(body,side)
    return validateMacro(body,side,true)
end

function Cast.MacroHasHarmfulCast(body)
    local guarded=Cast.GuardMacro(body)
    if not guarded then return false end
    local harmful=false
    for line in (guarded.."\n"):gmatch("(.-)\n") do
        local args=line:match("^/cast%s+(.+)$")
        if args then
            for clause in (args..";"):gmatch("(.-);") do
                local _,spell=guardClause(clause)
                if not spell then return false end
                -- Native /cast falls through to item use when the text is not
                -- a known spell. Do not copy such branches into this bridge.
                -- Also reject ! toggles rather than misclassifying auto-repeat.
                if spell:sub(1,1)=="!" or NS.Read(C_Spell and C_Spell.DoesSpellExist,spell)~=true then return false end
                -- Slot-level IsHarmfulAction can report false for a macro
                -- mixing a self-buff and damage. Classify its actual branches,
                -- while retaining the entire original macro for execution.
                if NS.Read(C_Spell and C_Spell.IsAutoAttackSpell,spell)==true
                    or NS.Read(C_Spell and C_Spell.IsRangedAutoAttackSpell,spell)==true
                    or NS.Read(C_Spell and C_Spell.IsAutoRepeatSpell,spell)==true
                    or NS.Read(C_Spell and C_Spell.IsPressHoldReleaseSpell,spell)==true then return false end
                local isHarmful=NS.Read(C_Spell and C_Spell.IsSpellHarmful or IsHarmfulSpell,spell)
                if type(isHarmful)~="boolean" then return false end
                if isHarmful then harmful=true end
            end
        end
    end
    return harmful
end

function Cast.BuildUserMacro(name,body,hasTarget)
    if legacyNameOnly or NS.PreserveCastTarget==true then return nil end
    local guarded=Cast.GuardMacro(body)
    if not guarded then return nil end
    return namedAction(name,guarded,hasTarget)
end

function Cast.BuildUserFallback(body)
    if legacyNameOnly or NS.PreserveCastTarget==true then return nil end
    -- No target change and no injected self-cast alternative. An explicit
    -- original self-buff/modifier branch is preserved as the user wrote it.
    return Cast.GuardMacro(body)
end

function Cast.FrozenUserMacro(body)
    if legacyNameOnly or NS.PreserveCastTarget==true then return nil end
    -- Validate the original branches before copying them. Never strip guards
    -- from GuardMacro output: a user may have written [nocombat] themselves.
    if not Cast.MacroHasHarmfulCast(body) then return nil end
    return validateMacro(body,"enemy",false)
end

local function idle()
    if type(InCombatLockdown)~="function" then return false end
    local ok,value=pcall(InCombatLockdown)
    return ok and NS.Public(value) and not value
end

local function currentSlot(source)
    if not source or NS.Read(source.IsForbidden,source)==true then return nil end
    local slot
    if type(source.CalculateAction)=="function" then
        slot=NS.Read(source.CalculateAction,source,"LeftButton")
        if not NS.Number(slot) then return nil end
    else
        local ok,value=pcall(function() return source.action end)
        if ok then slot=value end
        if not NS.Number(slot) then slot=NS.Read(source.GetAttribute,source,"action") end
    end
    if not NS.Number(slot) or slot%1~=0 or slot<1 or slot>240 then return nil end
    return slot
end

local function readSimpleMacro(slot)
    local name=NS.Read(C_ActionBar and C_ActionBar.GetActionText or GetActionText,slot)
    if not plain(name) then return nil end
    local index=NS.Read(GetMacroIndexByName,name)
    local constants=Constants and Constants.MacroConsts
    local account=constants and constants.MAX_ACCOUNT_MACROS or 120
    local character=constants and constants.MAX_CHARACTER_MACROS or 30
    if not NS.Number(account) or not NS.Number(character) or account%1~=0 or character%1~=0
        or account<1 or account>1000 or character<1 or character>1000
        or not NS.Number(index) or index%1~=0 or index<1 or index>account+character
        or type(GetMacroInfo)~="function" then return nil end
    local ok,actual,_,body=pcall(GetMacroInfo,index)
    if not ok or not NS.Public(actual) or actual~=name or not NS.Public(body) then return nil end
    local guarded=Cast.GuardMacro(body)
    if not guarded then return nil end
    local matches=0
    for i=1,account+character do
        local readable,candidate=pcall(GetMacroInfo,i)
        if not readable or not NS.Public(candidate)
            or candidate~=nil and type(candidate)~="string" then return nil end
        if candidate==name then matches=matches+1;if matches>1 then return nil end end
    end
    if matches~=1 then return nil end
    return {macroBody=body,guardedBody=guarded,macroName=name,macroIndex=index}
end

local function spellAt(source,side)
    side=sideName(side)
    if not side then return nil end
    if not legacyNameOnly and NS.PreserveCastTarget==true and side~="enemy" then return nil end
    local slot=currentSlot(source)
    if not slot then return nil end
    local kind,id,subType=NS.Read(GetActionInfo,slot)
    if not NS.Number(id) or id<1 then return nil,slot end
    if (legacyNameOnly or NS.PreserveCastTarget==true) and kind~="spell" then return nil,slot end
    if side=="enemy" and kind=="macro" and subType=="spell" then
        -- id is the macro's resolved/display spell ID, not its macro index.
        -- Do not use the slot's strict harmful flag for mixed macros, and do
        -- not replace a conditional macro with only this display spell.
        local macro=readSimpleMacro(slot)
        if not macro or not Cast.MacroHasHarmfulCast(macro.macroBody) then return nil,slot end
        macro.actionKind="macro";macro.slot=slot;macro.spellID=id
        return macro,slot,id
    end
    -- Neutral actions (auto-attack, tracking, self-only stances) keep their
    -- original behavior; only genuinely helpful/harmful actions are eligible.
    local check=side=="enemy" and (C_ActionBar and C_ActionBar.IsHarmfulAction or IsHarmfulAction)
        or (C_ActionBar and C_ActionBar.IsHelpfulAction or IsHelpfulAction)
    if NS.Read(check,slot,false)~=true then return nil,slot end
    if NS.Read(C_Spell and C_Spell.IsPressHoldReleaseSpell,id)==true then return nil,slot end
    if (legacyNameOnly or NS.PreserveCastTarget==true) and (NS.Read(C_Spell and C_Spell.IsAutoAttackSpell,id)==true
        or NS.Read(C_Spell and C_Spell.IsRangedAutoAttackSpell,id)==true
        or NS.Read(C_Spell and C_Spell.IsAutoRepeatSpell,id)==true) then return nil,slot end
    if kind~="spell" then return nil,slot end
    local spell=plain(NS.Read(C_Spell and C_Spell.GetSpellName,id))
    if not spell then return nil,slot end
    local rankAPI=C_Spell and C_Spell.GetSpellSubtext or GetSpellSubtext
    local rank=NS.Read(rankAPI,id)
    if (legacyNameOnly or NS.PreserveCastTarget==true) and type(rankAPI)=="function" then
        local ok,raw=pcall(rankAPI,id)
        if not ok or not NS.Public(raw) then return nil,slot end
        rank=raw
    end
    if rank~=nil and rank~="" then
        rank=plain(rank)
        if not rank then return nil,slot end
        spell=spell.."("..rank..")"
    end
    -- Match the same resolution check used by the native /cast handler.
    if NS.Read(C_Spell and C_Spell.DoesSpellExist,spell)~=true then return nil,slot end
    local info=NS.Read(C_Spell and C_Spell.GetSpellInfo,spell)
    local resolved=type(info)=="table" and NS.Read(function() return info.spellID end)
    -- A not-yet-loaded rank must not silently become the highest rank.
    if resolved~=id then return nil,slot end
    return {actionKind="spell",spell=spell,slot=slot,spellID=id},slot,id
end

local bars={
    {"ACTIONBUTTON","ActionButton"},
    {"MULTIACTIONBAR1BUTTON","MultiBarBottomLeftButton"},
    {"MULTIACTIONBAR2BUTTON","MultiBarBottomRightButton"},
    {"MULTIACTIONBAR3BUTTON","MultiBarRightButton"},
    {"MULTIACTIONBAR4BUTTON","MultiBarLeftButton"},
    {"MULTIACTIONBAR5BUTTON","MultiBar5Button"},
    {"MULTIACTIONBAR6BUTTON","MultiBar6Button"},
    {"MULTIACTIONBAR7BUTTON","MultiBar7Button"},
}

local function keyAllowed(key,command,allowOwn)
    if not plain(key) or key:find("BUTTON",1,true) or key:find("WHEEL",1,true) then return false end
    -- Respect both permanent bindings and another addon's active override.
    if NS.Read(GetBindingAction,key)~=command then return false end
    local effective=NS.Read(GetBindingAction,key,true)
    if effective==command then return true end
    if allowOwn then
        for _,proxy in ipairs(Cast.proxies) do
            local entry=proxy.entry
            if entry and entry.command==command then
                local name=NS.Read(proxy.GetName,proxy)
                if plain(name) and effective=="CLICK "..name..":LeftButton" then
                    for _,configured in ipairs(entry.keys) do if configured==key then return true end end
                end
            end
        end
    end
    return false
end

function Cast.DiscoverActions(side,allowOwn)
    side=sideName(side)
    if not side then return {} end
    local result,seen={},{}
    for _,bar in ipairs(bars) do
        for i=1,12 do
            local source=_G[bar[2]..i]
            local action,slot,id=spellAt(source,side)
            if action then
                local commands={bar[1]..i,"CLICK "..bar[2]..i..":LeftButton"}
                for _,command in ipairs(commands) do
                    local keys={NS.Read(GetBindingKey,command)}
                    local accepted={}
                    for _,key in ipairs(keys) do
                        if not seen[key] and keyAllowed(key,command,allowOwn) then
                            accepted[#accepted+1]=key;seen[key]=true
                        end
                    end
                    if #accepted>0 then
                        local down=NS.Read(source.GetAttribute,source,"useOnKeyDown")
                        if type(down)~="boolean" then
                            down=NS.Read(C_CVar and C_CVar.GetCVarBool or GetCVarBool,"ActionButtonUseKeyDown")==true
                        end
                        local entry={source=source,command=command,keys=accepted,
                            slot=slot,spell=action.spell,spellID=id,useOnKeyDown=down,side=side,
                            actionKind=action.actionKind,macroBody=action.macroBody,guardedBody=action.guardedBody,
                            macroName=action.macroName,macroIndex=action.macroIndex}
                        result[#result+1]=entry
                    end
                end
            end
        end
    end
    return result
end

-- This proves uniqueness only among the units the client has exposed to us.
-- /targetexact cannot select by GUID, so an undiscovered same-name NPC remains
-- a client limitation. Never infer uniqueness from the clipped visible grid.
local function bridgeTargetData(row)
    if not legacyNameOnly or not row or row.bridgeTarget~=true or not row.owner
        or not NS.ValidToken(row.owner.unit) or not plain(row.owner.expectedGUID)
        or row.unit~=row.owner.unit.."target" or NS.Read(UnitGUID,row.owner.unit)~=row.owner.expectedGUID
        or type(NS.ReadBridgeTarget)~="function" then return nil end
    local data=NS.Read(NS.ReadBridgeTarget,row)
    if type(data)~="table" or not plain(data.guid) or data.guid~=row.expectedGUID
        or data.unit~=row.unit or data.side~=row.side or NS.Read(UnitGUID,row.unit)~=data.guid
        or NS.Read(UnitGUID,row.owner.unit)~=row.owner.expectedGUID then return nil end
    return data
end

-- Name enumeration needs identity, not spell eligibility. A visible enemy's
-- target can be dead, offline or neutral and still be a same-name candidate.
-- Its action snapshot may therefore be cleared while this fixed relationship
-- remains readable. Never use this snapshot to authorize a spell or a click.
local function bridgeTargetIdentity(row)
    local owner=row and row.owner
    if not legacyNameOnly or not owner or row.bridgeTarget~=true
        or owner.enemyTargetButton~=row or row.bindingReady~=true
        or not NS.ValidToken(owner.unit) or not plain(owner.expectedGUID)
        or row.bindingOwnerGUID~=owner.expectedGUID or row.unit~=owner.unit.."target"
        or NS.Read(UnitGUID,owner.unit)~=owner.expectedGUID then
        return nil,"relationship_changed"
    end
    local ownerUnit,ownerGUID,unit=owner.unit,owner.expectedGUID,row.unit
    if NS.Read(UnitExists,unit)~=true then return nil,"identity_unreadable" end
    local guid,name,player=NS.Read(UnitGUID,unit),NS.Read(UnitName,unit),NS.Read(UnitIsPlayer,unit)
    if not plain(guid) or not plain(name) or not NS.Public(player) or type(player)~="boolean" then
        return nil,"identity_unreadable"
    end
    if not NS.Public(row.expectedGUID) then return nil,"identity_unreadable" end
    if row.expectedGUID~=nil and row.expectedGUID~=guid then return nil,"relationship_changed" end
    if row.owner~=owner or owner.enemyTargetButton~=row or row.bindingReady~=true
        or owner.unit~=ownerUnit or owner.expectedGUID~=ownerGUID or row.unit~=unit
        or row.bindingOwnerGUID~=ownerGUID or NS.Read(UnitGUID,unit)~=guid
        or NS.Read(UnitGUID,ownerUnit)~=ownerGUID then
        return nil,"relationship_changed"
    end
    return {unit=unit,guid=guid,name=name,player=player}
end

function Cast.KnownUniqueNPC(data,row)
    if not NS.Public(data) or type(data)~="table" then return false,"invalid_candidate" end
    local controlled=legacyNameOnly and bridgeTargetData(row)
    local controlledUnit=controlled and controlled.guid==data.guid and controlled.unit or nil
    if type(data)~="table" or not NS.Public(data.player) or data.player~=false or not plain(data.guid)
        or not plain(data.targetName) or not (NS.ValidToken(data.unit) or controlledUnit==data.unit)
        then return false,"invalid_candidate" end
    if type(NS.NameplateTokens)~="function" then return false,"enumeration_unavailable" end
    local controlledUnits={}
    if legacyNameOnly then
        -- A displayed target rectangle exposes a candidate even when that NPC
        -- has no nameplate or ordinary action alias of its own. Every admitted
        -- relationship keeps its own validated owner, identity and name.
        for candidate in pairs(Cast.installed) do
            if candidate.bridgeTarget==true and candidate.unit~=nil then
                local visible=NS.Read(candidate.IsVisible or candidate.IsShown,candidate)
                if visible~=false then
                    if visible~=true then return false,"identity_unreadable" end
                    local snapshot,reason=bridgeTargetIdentity(candidate)
                    if not snapshot then return false,reason end
                    local previous=controlledUnits[snapshot.unit]
                    if previous and (previous.guid~=snapshot.guid or previous.name~=snapshot.name
                        or previous.player~=snapshot.player) then return false,"relationship_changed" end
                    controlledUnits[snapshot.unit]={row=candidate,guid=snapshot.guid,
                        name=snapshot.name,player=snapshot.player}
                end
            end
        end
        if controlledUnit and not controlledUnits[controlledUnit] then return false,"relationship_changed" end
    end
    local tokens,known={},{}
    local function add(unit)
        if not NS.ValidToken(unit) and not controlledUnits[unit] then return false end
        if not known[unit] then known[unit]=true;tokens[#tokens+1]=unit end
        return true
    end
    local function checked(fn,...)
        if type(fn)~="function" then return false end
        local readable,value=pcall(fn,...)
        if not readable or not NS.Public(value) then return false end
        return true,value
    end
    add(data.unit)
    for unit in pairs(controlledUnits) do add(unit) end
    for _,unit in ipairs({"target","focus","targettarget","focustarget"}) do add(unit) end
    for i=1,4 do add("party"..i.."target") end
    for i=1,40 do add("raid"..i.."target") end
    for i=1,8 do add("boss"..i) end
    for i=1,5 do add("arena"..i) end
    local ok,plates=pcall(NS.NameplateTokens)
    if not ok or not NS.Public(plates) or type(plates)~="table" then return false,"enumeration_unavailable" end
    -- Retain the complete discovered/registered token set before trying to
    -- associate native plates, including plates without a public token field.
    local enumerated,complete=pcall(function()
        for _,unit in pairs(plates) do if not add(unit) then return false end end
        if type(NS.Nameplates)=="table" then
            for unit in pairs(NS.Nameplates) do if not add(unit) then return false end end
        end
        return true
    end)
    if not enumerated or not complete then return false,"enumeration_unavailable" end
    -- NameplateTokens intentionally tolerates unavailable discovery fields for
    -- display. A name-based cast must instead reject an incomplete enumeration.
    if C_NamePlate and type(C_NamePlate.GetNamePlates)=="function" then
        local readable,nativePlates=pcall(C_NamePlate.GetNamePlates)
        if not readable or not NS.Public(nativePlates) or type(nativePlates)~="table" then return false,"enumeration_unavailable" end
        local inspected,complete=pcall(function()
            for _,plate in pairs(nativePlates) do
                if not NS.Public(plate) or (type(plate)~="table" and type(plate)~="userdata") then return false end
                if type(plate.IsForbidden)=="function" then
                    local allowed,forbidden=pcall(plate.IsForbidden,plate)
                    if not allowed or not NS.Public(forbidden) or forbidden~=false then return false end
                end
                local nativeToken=plate.namePlateUnitToken
                if not NS.Public(nativeToken) then return false end
                if nativeToken~=nil then
                    if not add(nativeToken) then return false end
                else
                    -- Forever exposes some plates without this optional Lua
                    -- field. Associate them only through the native reverse
                    -- lookup of already known, live public nameplate tokens.
                    local associated=false
                    for _,unit in ipairs(tokens) do
                        if unit:match("^nameplate%d+$") then
                            local existsOK,exists=checked(UnitExists,unit)
                            if not existsOK then return false end
                            if exists==true then
                                local mappedOK,mapped=checked(C_NamePlate.GetNamePlateForUnit,unit)
                                if not mappedOK then return false end
                                if mapped==plate then associated=true end
                            elseif exists~=nil and exists~=false then return false end
                        end
                    end
                    if not associated then return false end
                end
            end
            return true
        end)
        if not inspected or not complete then return false,"enumeration_unavailable" end
    end
    local identities,matched={},false
    for _,unit in ipairs(tokens) do
        local readable,exists=checked(UnitExists,unit)
        if not readable then return false,"identity_unreadable" end
        local expected=controlledUnits[unit]
        if expected and exists~=true then return false,"relationship_changed" end
        if exists==true then
            local playerOK,player=checked(UnitIsPlayer,unit)
            if not playerOK or type(player)~="boolean" then return false,"identity_unreadable" end
            if expected and (player~=expected.player or NS.Read(UnitGUID,unit)~=expected.guid
                or NS.Read(UnitName,unit)~=expected.name) then return false,"relationship_changed" end
            if not player then
                local guidOK,guid=checked(UnitGUID,unit)
                local nameOK,name=checked(UnitName,unit)
                if not guidOK or not nameOK or not plain(guid) or not plain(name) then return false,"identity_unreadable" end
                if identities[guid] and identities[guid]~=name then return false,"identity_changed" end
                identities[guid]=name
                if name==data.targetName then
                    if guid~=data.guid then return false,"duplicate_name" end
                    matched=true
                end
            end
        elseif exists~=nil and exists~=false then return false,"identity_unreadable" end
    end
    for _,expected in pairs(controlledUnits) do
        local snapshot,reason=bridgeTargetIdentity(expected.row)
        if not snapshot then return false,reason end
        if snapshot.guid~=expected.guid or snapshot.name~=expected.name
            or snapshot.player~=expected.player then return false,"relationship_changed" end
    end
    return matched,matched and "known_unique" or "candidate_missing"
end

local function legacyEnabled()
    return NS.DB and NS.Public(NS.DB.legacyNameBridgeEnabled) and NS.DB.legacyNameBridgeEnabled==true
end

local function legacyContext(row)
    if not row or (row.side~="friendly" and row.side~="enemy") then return "unsupported_side" end
    if not legacyEnabled() then return "disabled" end
    if not idle() then return "out_of_combat_only" end
    if not NS.Public(NS.DB.shown) or NS.DB.shown~=true
        or NS.Read(row.IsVisible or row.IsShown,row)~=true then return "hidden" end
    local dead=NS.Read(UnitIsDeadOrGhost,"player")
    if dead~=false then return dead==true and "player_dead" or "player_unavailable" end
end

local function readRow(row,requireHovered,skipUnique)
    local hovered=row and (NS.HoveredTile==row or legacyNameOnly and NS.HoveredEnemyTarget==row)
    if not row or requireHovered and not hovered or not sideName(row.side) or type(row.unit)~="string"
        or not NS.DB then return nil end
    local targetData=legacyNameOnly and row.bridgeTarget==true and bridgeTargetData(row) or nil
    if legacyNameOnly and row.bridgeTarget==true and not targetData then return nil end
    if not NS.ValidToken(row.unit) and not targetData then return nil end
    if legacyNameOnly then
        if legacyContext(row) then return nil end
    elseif not NS.DB.mouseoverRequested then return nil end
    if not legacyNameOnly and NS.PreserveCastTarget==true and row.side~="enemy" then return nil end
    -- Helpful stable units retain the native path. Hostile player macros need
    -- the bridge for focus/target aliases too: user macros do not inherit the
    -- action bar's implicit mouseover target.
    if not legacyNameOnly and row.side=="friendly" and not row.unit:match("^nameplate%d+$") then return nil end
    local data=targetData or NS.ReadUnit(row.unit,row.side)
    if legacyNameOnly then
        if not NS.Public(data) or type(data)~="table" or not NS.Public(data.player) or type(data.player)~="boolean"
            or not plain(data.guid) or not NS.Public(row.expectedGUID) or data.guid~=row.expectedGUID
            or not plain(data.targetName) or not NS.Public(data.dead) or data.dead~=false
            or not NS.Public(data.offline) or data.offline~=false
            or NS.Read(UnitGUID,row.unit)~=data.guid
            or NS.Read(row.side=="friendly" and UnitCanAssist or UnitCanAttack,"player",row.unit)~=true
            or NS.Read(UnitIsDeadOrGhost,row.unit)~=false
            or data.player and NS.Read(UnitIsConnected,row.unit)~=true then return nil end
        if data.player or NS.Read(UnitGUID,"target")==data.guid then return data,true end
        return data,Cast.KnownUniqueNPC(data,row)
    end
    if not NS.Public(data) or type(data)~="table" or not NS.Public(data.player) or type(data.player)~="boolean"
        or not plain(data.guid) or not NS.Public(row.expectedGUID)
        or data.guid~=row.expectedGUID or NS.PreserveCastTarget~=true and (data.dead or data.offline)
        or NS.PreserveCastTarget~=true and not plain(data.targetName) then return nil end
    if NS.PreserveCastTarget==true then
        if data.player~=false or not plainGUID(data.guid) or not plainGUID(row.expectedGUID)
            or not NS.Public(data.dead) or data.dead~=false or not NS.Public(data.offline) or data.offline~=false then return nil end
        return data,true
    end
    if not data.player then
        if row.side~="enemy" then return nil end
        if not skipUnique then
            local targetGUID=NS.Read(UnitGUID,"target")
            -- A stable current target needs no name lookup and stays usable even
            -- when another known NPC shares its name. Otherwise recheck all known
            -- candidates on Enter and immediately before every hardware key press.
            if targetGUID~=data.guid then return data,Cast.KnownUniqueNPC(data) end
        end
    end
    return data,true
end
Cast.ReadRow=readRow

local function usableRow(row) return readRow(row,true) end

function Cast.SnapshotRow(row)
    if legacyNameOnly then return nil,false end
    if not idle() then return nil end
    local data=readRow(row,false,true)
    if not data then return nil end
    if NS.PreserveCastTarget==true then return data,true end
    -- Combat snapshots may not assume that today's current target will remain
    -- selected. NPC names must be independently unique before arming.
    return data,data.player or Cast.KnownUniqueNPC(data)
end

local function owner()
    if Cast.owner then return Cast.owner end
    if not idle() or type(SecureHandlerWrapScript)~="function" or type(RegisterStateDriver)~="function"
        or type(SetOverrideBindingClick)~="function" or type(ClearOverrideBindings)~="function" then return nil end
    local frame=CreateFrame("Frame","MyForeverTargetsNearbyCastOwner",UIParent,"SecureHandlerStateTemplate")
    frame:SetAttribute("_onstate-combat",legacyNameOnly
        and [[if newstate ~= "idle" then self:ClearBindings() end]]
        or [[if newstate == "combat" then self:ClearBindings() end]])
    RegisterStateDriver(frame,"combat",legacyNameOnly and "[combat] combat; [dead] dead; idle" or "[combat] combat; idle")
    Cast.owner=frame
    return frame
end

local function recordPrepare(proxy,button,down,fields)
    -- Enter/Refresh call prepare without a button. Only a real PreClick is a
    -- key preparation event; its mouse-button argument is not the keyboard key.
    -- Logging must never interrupt an action, including while combat blocks it.
    pcall(function()
        if NS.Public(button) and button==nil then return end
        local diagnostics=NS.Diagnostics
        if type(diagnostics)~="table" or type(diagnostics.Record)~="function" then return end
        if type(diagnostics.Enabled)=="function" and NS.Read(diagnostics.Enabled)~=true then return end
        local entry,row=proxy.entry,Cast.row
        local rowUnit=row and row.unit
        local rangeProbe
        if NS.ValidToken(rowUnit) then rangeProbe=NS.Read(C_Spell and C_Spell.IsSpellInRange,679,rowUnit) end
        local event={button=button,down=down,combat=NS.Read(InCombatLockdown),
            activeZBinding=NS.Read(GetBindingAction,"Z",true),
            rowUnit=rowUnit,expectedGUID=row and row.expectedGUID,
            targetGUID=NS.Read(UnitGUID,"target"),targetName=NS.Read(UnitName,"target"),
            nativeMouseoverGUID=NS.Read(UnitGUID,"mouseover"),facing=NS.Read(GetPlayerFacing),
            rangeProbeSpellID=679,rangeProbe=rangeProbe,
            eligible=false,canNameBridge=false,eligibilityChecked=false}
        if entry then
            event.slot,event.spellID,event.actionKind,event.side=entry.slot,entry.spellID,entry.actionKind,entry.side
            event.configuredCommand,event.configuredSlot=entry.command,entry.slot
            event.configuredSpellID,event.configuredActionKind=entry.spellID,entry.actionKind
            for i,key in ipairs(entry.keys or {}) do event["configuredKey"..i]=key end
        end
        for key,value in pairs(fields or {}) do event[key]=value end
        if event.branch=="original_action" then
            local kind,id,subType=NS.Read(GetActionInfo,event.slot)
            event.actionKind,event.actionID=kind,id
            event.spellID=(kind=="spell" or kind=="macro" and subType=="spell") and id or nil
        elseif event.reason=="missing_slot" then
            event.slot,event.spellID,event.actionKind=nil,nil,nil
        end
        diagnostics.Record("KEY_PREPARE",event)
        if event.branch=="guid_hover" and type(diagnostics.BeginCastAttempt)=="function"
            and type(event.generatedCommand)=="string"
            and NS.Read(proxy.GetAttribute,proxy,"macrotext")==event.generatedCommand then
            local ok,id=pcall(diagnostics.BeginCastAttempt,{route="nearby",expectedGUID=event.castGUID,
                spellID=event.spellID,slot=event.slot,generatedCommand=event.generatedCommand,
                row=row and NS.Read(row.GetName,row),rowUnit=rowUnit,beforeTargetGUID=event.beforeTargetGUID,
                configuredCommand=event.configuredCommand,configuredKey1=event.configuredKey1,
                button=button,down=down,recipientProven=false})
            if ok and NS.Number(id) then proxy.castLogAttemptID=id end
        end
    end)
end

local function inert(proxy)
    proxy:SetAttribute("type",nil)
    proxy:SetAttribute("macrotext",nil)
    proxy:SetAttribute("unit",nil)
    proxy:SetAttribute("action",nil)
    proxy:SetAttribute("checkmouseovercast",nil)
    proxy.guidDispatch=nil
    proxy.castLogAttemptID=nil
end

local function recordNamePre(proxy,button,down,fields)
    if not NS.Public(button) or button==nil then return end
    -- Keep the attempt on its proxy until PostClick, even if target-change
    -- events invalidate the hovered alias while the native macro is running.
    local row=Cast.row
    Cast.nameAttempt=(Cast.nameAttempt or 0)+1
    local event={attemptID=Cast.nameAttempt,route="legacy_name_bridge",button=button,down=down,
        row=row and NS.Read(row.GetName,row),rowUnit=row and row.unit,side=row and row.side,
        expectedGUID=row and row.expectedGUID,beforeTargetExists=NS.Read(UnitExists,"target"),
        beforeTargetGUID=NS.Read(UnitGUID,"target"),recipientProven=false}
    for key,value in pairs(fields or {}) do event[key]=value end
    proxy.nameDispatch=event
    pcall(function()
        local d=NS.Diagnostics
        if type(d)~="table" or type(d.Record)~="function" or NS.Read(d.Enabled)~=true then return end
        local copy={}
        for key,value in pairs(event) do copy[key]=value end
        d.Record("NAME_BRIDGE_PRE",copy)
    end)
end

local function recordNamePost(proxy,button,down)
    if not NS.Public(button) or button==nil then return end
    local event=proxy.nameDispatch
    proxy.nameDispatch=nil
    if not event then return end
    pcall(function()
        local d=NS.Diagnostics
        if type(d)~="table" or type(d.Record)~="function" or NS.Read(d.Enabled)~=true then return end
        event.afterTargetExists=NS.Read(UnitExists,"target")
        event.afterTargetGUID=NS.Read(UnitGUID,"target")
        event.targetRestorationObserved=(event.beforeTargetExists==false and event.afterTargetExists==false)
            or (event.beforeTargetExists==true and event.afterTargetExists==true
                and plain(event.beforeTargetGUID)~=nil and event.beforeTargetGUID==event.afterTargetGUID)
        event.note="Native action readback only; no proof of spell success or recipient. Name selection may change last-target history."
        d.Record("NAME_BRIDGE_POST",event)
    end)
end

local function recordGUIDPost(proxy,button,down)
    if legacyNameOnly then recordNamePost(proxy,button,down);return end
    if NS.PreserveCastTarget~=true or not NS.Public(button) or button==nil then return end
    local event=proxy.guidDispatch
    local attemptID=proxy.castLogAttemptID
    proxy.guidDispatch=nil
    proxy.castLogAttemptID=nil
    if not event then return end
    pcall(function()
        local diagnostics=NS.Diagnostics
        if type(diagnostics)~="table" or type(diagnostics.Record)~="function" then return end
        event.button,event.down=button,down
        event.afterTargetGUID=NS.Read(UnitGUID,"target")
        event.targetGUID=event.afterTargetGUID
        event.recipientProven=false
        event.note="Action dispatch is not proof of cast success, damage or exact recipient; no target restoration"
        if NS.Number(attemptID) then
            event.attemptID=attemptID
            if type(diagnostics.EndCastAttempt)=="function" then pcall(diagnostics.EndCastAttempt,attemptID,event) end
        end
        diagnostics.Record("GUID_HOVER_POSTCLICK",event)
    end)
end

local function prepareName(proxy,button,down)
    if NS.Public(button) and button~=nil then proxy.nameDispatch=nil end
    local function record(fields) recordNamePre(proxy,button,down,fields) end
    if not idle() then
        record({branch="disabled",reason="out_of_combat_only",actionPrepared=false})
        return -- The stored macro's combat guard and secure driver remain authoritative.
    end
    inert(proxy)
    local row=Cast.row
    local reason=legacyContext(row)
    if reason then record({branch="disabled",reason=reason,actionPrepared=false});return end
    if NS.GUIDProbeSuspended then record({branch="disabled",reason="suspended",actionPrepared=false});return end
    local entry=proxy.entry
    if not entry then record({branch="disabled",reason="missing_entry",actionPrepared=false});return end
    local active=false
    for _,key in ipairs(entry.keys or {}) do
        if NS.Read(GetBindingAction,key)==entry.command then
            local effective=NS.Read(GetBindingAction,key,true)
            if effective==entry.command or effective=="CLICK "..proxy:GetName()..":LeftButton" then active=true;break end
        end
    end
    if not active then record({branch="disabled",reason="binding_changed",actionPrepared=false});return end
    local action,slot=spellAt(entry.source,entry.side)
    if not action then
        -- The player's slot changed after discovery. Forward its current native
        -- action without reading a user macro body or synthesizing an item cast.
        proxy:SetAttribute("type",slot and "action" or nil)
        proxy:SetAttribute("action",slot)
        record({branch=slot and "original_action" or "disabled",reason=slot and "unsupported_action" or "missing_slot",
            slot=slot,actionPrepared=slot~=nil})
        return
    end
    local data,canNameBridge=usableRow(row)
    if not data or row.side~=entry.side then
        record({branch="disabled",reason="invalid_row",slot=slot,spellID=action.spellID,actionPrepared=false});return
    end
    if not canNameBridge then
        record({branch="disabled",reason="not_unique",slot=slot,spellID=action.spellID,actionPrepared=false});return
    end
    local beforeExists=NS.Read(UnitExists,"target")
    if type(beforeExists)~="boolean" then
        record({branch="disabled",reason="target_presence_unknown",slot=slot,spellID=action.spellID,actionPrepared=false});return
    end
    local current=NS.Read(UnitGUID,"target")==data.guid
    local macro=current and Cast.BuildFallback(action.spell,row.side)
        or Cast.BuildMacro(data.targetName,action.spell,beforeExists,row.side)
    proxy:SetAttribute("type",macro and "macro" or nil)
    proxy:SetAttribute("macrotext",macro)
    record({branch=macro and (current and "current_target" or "name_bridge") or "disabled",
        reason=not macro and "macro_rejected" or nil,slot=slot,spellID=action.spellID,actionKind="spell",
        dataGUID=data.guid,actionPrepared=macro~=nil,beforeTargetExists=beforeExists,
        rangeProbe=NS.Read(C_Spell and C_Spell.IsSpellInRange,action.spellID,row.unit)})
end

local function prepare(proxy,button,down)
    if legacyNameOnly then return prepareName(proxy,button,down) end
    if NS.Public(button) and button~=nil then proxy.castLogAttemptID=nil end
    if not idle() then
        recordPrepare(proxy,button,down,{branch="disabled",reason="idle_guard"})
        return -- All stored macros also carry [nocombat].
    end
    if NS.GUIDProbeSuspended then
        if NS.PreserveCastTarget==true then inert(proxy) else proxy:SetAttribute("type",nil) end
        recordPrepare(proxy,button,down,{branch="disabled",reason="guid_probe_suspended"})
        return
    end
    local entry=proxy.entry
    if not entry then
        if NS.PreserveCastTarget==true then inert(proxy) else proxy:SetAttribute("type",nil) end
        recordPrepare(proxy,button,down,{branch="disabled",reason="missing_entry"})
        return
    end
    local active=false
    for _,key in ipairs(entry.keys) do
        if NS.Read(GetBindingAction,key)==entry.command then active=true;break end
    end
    if not active then
        if NS.PreserveCastTarget==true then inert(proxy) else proxy:SetAttribute("type",nil) end
        recordPrepare(proxy,button,down,{branch="disabled",reason="binding_changed"})
        return
    end
    local side=entry.side or "friendly"
    local action,slot=spellAt(entry.source,side)
    if NS.PreserveCastTarget==true then
        local data,canBridge=usableRow(Cast.row)
        if Cast.row and Cast.row.side~=side then data=nil end
        local macro=data and canBridge and side=="enemy" and data.player==false and action
            and action.actionKind=="spell" and Cast.BuildGUIDMacro(data.guid,action.spell) or nil
        inert(proxy)
        if not action and slot and data and canBridge and side=="enemy" then
            -- The native slot changed after this override was discovered. Pass
            -- through the user's own action without reading/copying its body;
            -- this is not a GUID attempt or a generated fallback cast.
            proxy:SetAttribute("type","action")
            proxy:SetAttribute("action",slot)
            recordPrepare(proxy,button,down,{branch="original_action",slot=slot,reason="unsupported_action"})
            return
        end
        proxy:SetAttribute("type",macro and "macro" or nil)
        proxy:SetAttribute("macrotext",macro)
        local beforeTarget=NS.Read(UnitGUID,"target")
        if macro and NS.Public(button) and button~=nil then
            proxy.guidDispatch={branch="guid_hover",unitArg=data.guid,castGUID=data.guid,
                expectedGUID=data.guid,spellID=action.spellID,slot=slot,actionKind="spell",side="enemy",
                beforeTargetGUID=beforeTarget}
        end
        recordPrepare(proxy,button,down,{slot=slot,spellID=action and action.spellID,actionKind=action and action.actionKind,side=side,
            dataGUID=data and data.guid,eligible=macro~=nil,canNameBridge=false,canGUIDBridge=macro~=nil,eligibilityChecked=true,
            unitArg=macro and data.guid or nil,castGUID=macro and data.guid or nil,beforeTargetGUID=beforeTarget,
            generatedCommand=macro,
            branch=macro and "guid_hover" or "disabled",reason=not macro and (not action and "unsupported_action" or "invalid_row") or nil,
            note="Pure GUID dispatch candidate; no target change and no cast or recipient proof"})
        return
    end
    if not action then
        -- An action changed to a macro/item between refresh and key press:
        -- execute its original slot, without interpreting or rewriting it.
        proxy:SetAttribute("type",slot and "action" or nil)
        proxy:SetAttribute("action",slot)
        proxy:SetAttribute("unit",nil)
        recordPrepare(proxy,button,down,{branch=slot and "original_action" or "disabled",slot=slot,
            reason=slot and "unsupported_action" or "missing_slot"})
        return
    end
    local data,canNameBridge=usableRow(Cast.row)
    if Cast.row and Cast.row.side~=side then data=nil end
    local macro,branch
    if data and canNameBridge then
        local targetGUID=NS.Read(UnitGUID,"target")
        branch=targetGUID==data.guid and "current_target" or "name_bridge"
        if action.actionKind=="macro" then
            if targetGUID==data.guid then macro=Cast.BuildUserFallback(action.macroBody)
            else macro=Cast.BuildUserMacro(data.targetName,action.macroBody,NS.Read(UnitExists,"target")==true) end
        elseif targetGUID==data.guid then macro=Cast.BuildFallback(action.spell,side)
        else macro=Cast.BuildMacro(data.targetName,action.spell,NS.Read(UnitExists,"target")==true,side) end
    else
        branch="fallback"
        if action.actionKind=="macro" then macro=Cast.BuildUserFallback(action.macroBody)
        else macro=Cast.BuildFallback(action.spell,side) end
    end
    proxy:SetAttribute("type",macro and "macro" or nil)
    proxy:SetAttribute("macrotext",macro)
    proxy:SetAttribute("unit",nil)
    proxy:SetAttribute("action",nil)
    recordPrepare(proxy,button,down,{slot=slot,spellID=action.spellID,actionKind=action.actionKind,side=side,
        dataGUID=data and data.guid,dataName=data and data.targetName,eligible=data~=nil,
        canNameBridge=data~=nil and canNameBridge==true,eligibilityChecked=true,
        branch=macro and branch or "disabled",reason=not macro and "macro_rejected" or nil})
end

local function loggingEnabled()
    local diagnostics=NS.Diagnostics
    return type(diagnostics)=="table" and type(diagnostics.Record)=="function"
        and (type(diagnostics.Enabled)~="function" or NS.Read(diagnostics.Enabled)==true)
end

local function logTransition(kind,channel,fields)
    pcall(function()
        local diagnostics=NS.Diagnostics
        if not loggingEnabled() then return end
        local keys,parts={},{}
        for key in pairs(fields) do keys[#keys+1]=key end
        table.sort(keys)
        for _,key in ipairs(keys) do
            local value=fields[key]
            if not NS.Public(value) then value="[restricted]"
            elseif type(value)~="string" and type(value)~="number" and type(value)~="boolean" and value~=nil then value="[unsupported]" end
            parts[#parts+1]=key.."="..tostring(value)
        end
        local session=NS.Read(function() return MyForeverTargetsLogDB and MyForeverTargetsLogDB.session end)
        local signature=tostring(session)..";"..table.concat(parts,";")
        Cast.logStates=Cast.logStates or {}
        if Cast.logStates[channel]==signature then return end
        diagnostics.Record(kind,fields)
        Cast.logStates[channel]=signature
    end)
end

local function rowLogFields(row,data)
    local unit=row and row.unit
    if not data and row then data=legacyNameOnly and row.bridgeTarget and bridgeTargetData(row) or NS.Read(NS.ReadUnit,unit,row.side) end
    return {route=legacyNameOnly and "legacy_name_bridge" or "nearby",row=row and NS.Read(row.GetName,row),rowUnit=unit,side=row and row.side,
        expectedGUID=row and row.expectedGUID,observedGUID=type(data)=="table" and NS.Read(function() return data.guid end),
        player=type(data)=="table" and NS.Read(function() return data.player end),
        dead=type(data)=="table" and NS.Read(function() return data.dead end),
        offline=type(data)=="table" and NS.Read(function() return data.offline end),
        hovered=row~=nil and (NS.HoveredTile==row or legacyNameOnly and NS.HoveredEnemyTarget==row),installed=row~=nil and Cast.installed[row]==true,
        legacyNameBridgeEnabled=legacyNameOnly and legacyEnabled() or nil,
        mouseoverRequested=NS.DB and NS.DB.mouseoverRequested,combat=NS.Read(InCombatLockdown),
        activeZBinding=NS.Read(GetBindingAction,"Z",true),baseZBinding=NS.Read(GetBindingAction,"Z")}
end

local function enterLog(row,reason,count,data)
    if not loggingEnabled() then return end
    pcall(function()
        local fields=rowLogFields(row,data)
        fields.reason,fields.boundKeys=reason,count or 0
        logTransition(legacyNameOnly and "NAME_BRIDGE_ENTER" or "GUID_HOVER_ENTER","enter",fields)
    end)
end

local function bindingLog(row,data,key,entry,proxy)
    if not loggingEnabled() then return end
    pcall(function()
        local fields=rowLogFields(row,data)
        fields.key,fields.command,fields.slot,fields.spellID=key,entry.command,entry.slot,entry.spellID
        fields.proxy=NS.Read(proxy.GetName,proxy)
        fields.effectiveBinding=NS.Read(GetBindingAction,key,true)
        fields.bindingMatches=fields.effectiveBinding=="CLICK "..proxy:GetName()..":LeftButton"
        logTransition(legacyNameOnly and "NAME_BRIDGE_BINDING" or "GUID_HOVER_BINDING","binding:"..key,fields)
    end)
end

local function invalidRowReason(row)
    if not row then return "missing_row" end
    if legacyNameOnly then
        local reason=legacyContext(row)
        if reason then return reason end
        if NS.HoveredTile~=row and NS.HoveredEnemyTarget~=row then return "not_hovered" end
        if not Cast.installed[row] then return "not_installed" end
        if not NS.ValidToken(row.unit) and not bridgeTargetData(row) then return "invalid_unit" end
        return "unit_unavailable"
    end
    if not NS.DB or not NS.DB.mouseoverRequested then return "mouseover_disabled" end
    if NS.HoveredTile~=row then return "not_hovered" end
    if not Cast.installed[row] then return "not_installed" end
    if not NS.ValidToken(row.unit) then return "invalid_unit" end
    local side=sideName(row.side)
    if not side then return "invalid_side" end
    if NS.PreserveCastTarget==true and side~="enemy" then return "native_friendly_path" end
    local data=NS.Read(NS.ReadUnit,row.unit,row.side)
    if type(data)~="table" then return "unit_unreadable" end
    if not plainGUID(data.guid) or not plainGUID(row.expectedGUID) then return "guid_unreadable" end
    if data.guid~=row.expectedGUID then return "guid_mismatch" end
    if not NS.Public(data.player) then return "player_type_unreadable" end
    if NS.PreserveCastTarget==true and data.player~=false then return "not_npc" end
    if not NS.Public(data.dead) or data.dead~=false then return "dead_or_unreadable" end
    if not NS.Public(data.offline) or data.offline~=false then return "offline_or_unreadable" end
    return "row_ineligible"
end

function Cast.Leave(row,logReason)
    if row and Cast.row~=row then return end
    local previous=Cast.row
    local changing=Cast.changing
    Cast.changing=true
    Cast.row=nil
    Cast.count=0
    -- In combat the secure OnLeave/OnHide wrapper and state driver clear these.
    if idle() and Cast.owner then ClearOverrideBindings(Cast.owner) end
    if idle() and (legacyNameOnly or NS.PreserveCastTarget==true) then
        for _,proxy in ipairs(Cast.proxies) do inert(proxy) end
    end
    Cast.changing=changing
    if previous and logReason~="rebuild" and loggingEnabled() then
        Cast.logStates={}
        pcall(function()
            local fields=rowLogFields(previous)
            fields.reason=logReason or "leave"
            logTransition(legacyNameOnly and "NAME_BRIDGE_LEAVE" or "GUID_HOVER_LEAVE","leave",fields)
        end)
    end
end

function Cast.Enter(row)
    if Cast.changing then return false,0 end
    if not idle() then enterLog(row,"combat_owner",0);return false,0 end
    if NS.GUIDProbeSuspended then enterLog(row,"guid_probe_suspended",0);return false,0 end
    Cast.changing=true
    Cast.Leave(nil,"rebuild")
    local data,canBridge=usableRow(row)
    if legacyNameOnly and data and not canBridge then
        Cast.lastRow,Cast.lastReason=row,"not_unique"
        Cast.changing=false
        enterLog(row,"not_unique",0,data)
        return false,0
    end
    local frame=data and owner()
    if not frame or not Cast.installed[row] then
        Cast.changing=false
        if legacyNameOnly then
            Cast.lastRow,Cast.lastReason=row,not data and (NS.Read(invalidRowReason,row) or "unit_unavailable")
                or not Cast.installed[row] and "not_installed" or "owner_unavailable"
        end
        if loggingEnabled() then
            enterLog(row,not data and (NS.Read(invalidRowReason,row) or "row_unreadable")
                or not Cast.installed[row] and "not_installed" or "owner_unavailable",0,data)
        end
        return false,0
    end
    Cast.row=row
    local count=0
    local actions=Cast.DiscoverActions(row.side)
    for i,entry in ipairs(actions) do
        local proxy=Cast.proxies[i]
        if not proxy then
            proxy=CreateFrame("Button","MyForeverTargetsNearbyCast"..i,frame,"SecureActionButtonTemplate")
            proxy:SetSize(1,1)
            proxy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10,10)
            proxy:EnableMouse(false)
            proxy:SetScript("PreClick",prepare)
            proxy:SetScript("PostClick",recordGUIDPost)
            Cast.proxies[i]=proxy
        end
        proxy.entry=entry
        proxy:SetAttribute("unit",nil)
        proxy:SetAttribute("useOnKeyDown",entry.useOnKeyDown)
        proxy:RegisterForClicks(entry.useOnKeyDown and "AnyDown" or "AnyUp")
        prepare(proxy)
        for _,key in ipairs(entry.keys) do
            SetOverrideBindingClick(frame,true,key,proxy:GetName(),"LeftButton")
            count=count+1
            bindingLog(row,data,key,entry,proxy)
        end
    end
    Cast.count=count
    if legacyNameOnly then Cast.lastRow,Cast.lastReason=row,#actions==0 and "no_supported_spell" or "prepared" end
    Cast.changing=false
    enterLog(row,#actions==0 and "no_supported_spell" or "prepared",count,data)
    return count>0,count
end

function Cast.Refresh()
    if Cast.changing or not idle() then return end
    if NS.GUIDProbeSuspended then Cast.Leave();return end
    local row=Cast.row
    if not row then return end
    if type(MouseIsOver)=="function" and NS.Read(MouseIsOver,row)~=true then Cast.Leave(nil,"pointer_left");return end
    return Cast.Enter(row)
end

function Cast.Reconcile()
    if not idle() or Cast.changing then return false end
    Cast.Leave()
    if NS.GUIDProbeSuspended then return false end
    local foci=NS.Read(GetMouseFoci)
    if type(foci)~="table" then return false end
    for _,focus in ipairs(foci) do
        if NS.Public(focus) and Cast.installed[focus] and NS.Read(focus.IsVisible,focus)==true then
            local data=readRow(focus,false)
            if data then
                if legacyNameOnly and focus.bridgeTarget then NS.HoveredEnemyTarget=focus
                else NS.HoveredTile=focus end
                return Cast.Enter(focus)
            end
        end
    end
    return false
end

function Cast.Install(row)
    if legacyNameOnly and (not row or row.bridgeTarget~=true and row.side~="friendly" and row.side~="enemy") then return false end
    if Cast.installed[row] then return true end
    local frame=owner()
    if not frame then return false end
    -- Restricted ClearBindings uses the same owner as SetOverrideBindingClick.
    -- It remains callable after combat begins; no insecure combat mutation.
    local combatInstalled=NS.CombatCast and NS.CombatCast.Install(row)
    if not combatInstalled then
        SecureHandlerWrapScript(row,"OnLeave",frame,[[control:ClearBindings()]])
        SecureHandlerWrapScript(row,"OnHide",frame,[[control:ClearBindings()]])
    end
    row:HookScript("OnEnter",function(self) Cast.Enter(self) end)
    row:HookScript("OnLeave",function(self) Cast.Leave(self) end)
    row:HookScript("OnHide",function(self) Cast.Leave(self) end)
    Cast.installed[row]=true
    return true
end

if legacyNameOnly then
    function Cast.Status(row)
        local status={legacyName=true,prepared=false,count=0,reason="not_hovered",castMode="legacy_name_bridge",
            unit=row and row.unit,guid=row and row.expectedGUID,enabled=legacyEnabled()==true}
        local reason=legacyContext(row)
        if reason then status.reason=reason;return status end
        local data,canBridge=readRow(row,false)
        if not data then status.reason=invalidRowReason(row);return status end
        if not canBridge then status.reason="not_unique";return status end
        if NS.HoveredTile~=row and NS.HoveredEnemyTarget~=row then return status end
        if Cast.row==row and (Cast.count or 0)>0 then
            status.prepared=true;status.count=Cast.count;status.reason="prepared"
        else status.reason=Cast.lastRow==row and Cast.lastReason or "not_prepared" end
        return status
    end
end

local events=CreateFrame("Frame")
local elapsed=0
for _,event in ipairs({"UPDATE_BINDINGS","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR","UPDATE_OVERRIDE_ACTIONBAR","UPDATE_SHAPESHIFT_FORM",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","NAME_PLATE_UNIT_REMOVED","CVAR_UPDATE","SPELL_TEXT_UPDATE","UPDATE_MACROS"}) do
    pcall(events.RegisterEvent,events,event)
end
if legacyNameOnly then
    for _,event in ipairs({"PLAYER_DEAD","PLAYER_ALIVE","PLAYER_UNGHOST"}) do pcall(events.RegisterEvent,events,event) end
end
events:SetScript("OnEvent",function(_,event,unit)
    if Cast.changing then return end
    if legacyNameOnly and event=="PLAYER_DEAD" then Cast.Leave(nil,"player_dead")
    elseif event=="PLAYER_REGEN_DISABLED" then Cast.row=nil;Cast.count=0
    elseif event=="PLAYER_REGEN_ENABLED" or legacyNameOnly and (event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST") then Cast.Reconcile()
    elseif event=="NAME_PLATE_UNIT_REMOVED" and Cast.row and Cast.row.unit==unit then Cast.Leave()
    else Cast.Refresh() end
end)
events:SetScript("OnUpdate",function(_,delta)
    if not Cast.row then return end
    elapsed=elapsed+delta
    if elapsed>=.2 then elapsed=0;Cast.Refresh() end
end)
