local _, NS = ...
-- Production leaves native mouseover macros and action keys untouched. The
-- historical generated-action controller below is disabled at startup.
local Combat={rows={},proxies={},installed=setmetatable({}, {__mode="k"}),states=setmetatable({}, {__mode="k"})}
NS.CombatCast=Combat

-- Evaluated once at startup; changing this policy requires a UI reload.
-- Native mouseover macros never need a generated action or key override.
local legacy=NS.NearbyCast and NS.NearbyCast.combatName==true
Combat.legacy=legacy
if not legacy and (not NS.Public(NS.NativeMacroOnly) or NS.NativeMacroOnly~=false) then
    local function disabled() return false,0 end
    Combat.native=true
    Combat.Snippets={}
    Combat.BuildMacros=function() return nil end
    Combat.Install=disabled
    Combat.ArmRow=disabled
    Combat.Reconcile=disabled
    Combat.RefreshAll=disabled
    Combat.Status=function()
        return {native=true,prepared=false,count=0,preparedCount=0,active=false,
            reason="native_macro_only",castMode="native_mouseover"}
    end
    return
end

local function idle()
    return type(InCombatLockdown)=="function" and NS.Read(InCombatLockdown)==false
end

local function plain(value)
    return NS.Public(value) and type(value)=="string" and value~=""
        and not value:find("[%z\1-\31\127%[%]|;\\]")
        and not value:match("^%s") and not value:match("%s$") and value or nil
end

local function preserveTarget()
    -- The name-bridge continuation never uses the unverified GUID route.
    if legacy then return false end
    local value=NS.PreserveCastTarget
    return not NS.Public(value) or value~=false
end

function Combat.BuildMacros(data,entry)
    local nearby=NS.NearbyCast
    if type(data)~="table" or type(entry)~="table" or not nearby
        or not plain(data.guid) or not NS.ValidToken(data.unit)
        or (entry.side~="friendly" and entry.side~="enemy") then return nil end
    if preserveTarget() then
        if not NS.Public(data.player) or data.player~=false or entry.side~="enemy" or entry.actionKind~="spell"
            or not plain(entry.spell) or type(nearby.BuildGUIDMacro)~="function" then return nil end
        local macro=nearby.BuildGUIDMacro(data.guid,entry.spell)
        if not NS.Public(macro) or type(macro)~="string"
            or #macro>1023 or macro~="/cast [@"..data.guid.."] "..entry.spell then return nil end
        return {withTarget=macro,withoutTarget=macro,guidMacro=macro,preserveTarget=true,
            guard="[@"..data.unit..",exists,harm,nodead] valid"}
    end
    if not plain(data.targetName) then return nil end
    local relation=entry.side=="enemy" and "harm" or "help"
    local body,fallback
    if entry.actionKind=="macro" and entry.side=="enemy" then
        body=nearby.FrozenUserMacro(entry.macroBody)
        fallback=body
    elseif entry.actionKind=="spell" and plain(entry.spell) then
        body="/cast [@target,"..relation..",nodead] "..entry.spell
        fallback=entry.side=="enemy" and body
            or ("/cast [@target,help,nodead][@player] "..entry.spell)
    end
    if not body then return nil end
    local guard="[@"..data.unit..",exists,"..relation..",nodead] valid"
    local prefix="/stopmacro [@"..data.unit..",noexists][@"..data.unit..",dead][@"..data.unit..",no"..relation.."]\n"
        .."/cleartarget\n/targetexact "..data.targetName.."\n"..body.."\n"
    local withTarget,withoutTarget=prefix.."/targetlasttarget",prefix.."/cleartarget"
    if #withTarget>1023 or #withoutTarget>1023 or #fallback>1023 then return nil end
    return {withTarget=withTarget,withoutTarget=withoutTarget,fallback=fallback,guard=guard}
end

-- These snippets read only protected, OOC-populated attributes. Each controller
-- clears its own overrides; the old OOC owner cannot erase combat bindings.
local BIND=[[
    local count = row:GetAttribute("combat-key-count") or 0
    for i = 1, count do
        local key = row:GetAttribute("combat-key" .. i)
        local name = row:GetAttribute("combat-proxy" .. i)
        if key and name then self:SetBindingClick(true, key, name, "LeftButton") end
    end
]]
local STATE=[[
    self:ClearBindings()
    self:SetAttribute("combat-active", newstate == "combat")
    if newstate == "combat" and not self:GetAttribute("guid-probe-suspended") then
        local index = self:GetAttribute("combat-hover-index")
        local row = index and self:GetFrameRef("row" .. index)
        if row and row:GetAttribute("combat-prepared") and not row:GetAttribute("mfch-ready")
            and row:IsVisible() and row:IsUnderMouse() then
]]..BIND..[[
        end
    end
]]
local ENTER=[[
    control:ClearBindings()
    control:SetAttribute("combat-hover-index", self:GetAttribute("combat-row-index"))
    if control:GetAttribute("combat-active") and not control:GetAttribute("guid-probe-suspended")
        and self:GetAttribute("combat-prepared") and not self:GetAttribute("mfch-ready") then
        local count = self:GetAttribute("combat-key-count") or 0
        for i = 1, count do
            local key = self:GetAttribute("combat-key" .. i)
            local name = self:GetAttribute("combat-proxy" .. i)
            if key and name then control:SetBindingClick(true, key, name, "LeftButton") end
        end
    end
]]
local LEAVE=[[
    if control:GetAttribute("combat-hover-index") == self:GetAttribute("combat-row-index") then
        control:ClearBindings()
        control:SetAttribute("combat-hover-index", nil)
    end
    local nearby = control:GetFrameRef("nearbyOwner")
    if nearby then nearby:ClearBindings() end
]]
local PRECLICK=[[
    if control:GetAttribute("guid-probe-suspended") then
        self:SetAttribute("type", nil)
        self:SetAttribute("combat-branch", "guid_probe_suspended")
        return
    end
    if not control:GetAttribute("combat-active") then
        self:SetAttribute("type", nil)
        self:SetAttribute("combat-branch", "idle")
        return
    end
    local row = self:GetFrameRef("row")
    if not row or not row:GetAttribute("combat-prepared")
        or control:GetAttribute("combat-hover-index") ~= row:GetAttribute("combat-row-index") then
        self:SetAttribute("type", nil)
        self:SetAttribute("combat-branch", "disabled")
        return
    end
    if self:GetAttribute("snapshot-preserve-target") then
        self:SetAttribute("unit", nil)
        local macro = self:GetAttribute("snapshot-guid-macro")
        if macro and macro ~= "" then
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", macro)
            self:SetAttribute("combat-branch", "guid_hover")
        else
            self:SetAttribute("type", nil)
            self:SetAttribute("macrotext", nil)
            self:SetAttribute("combat-branch", "guid_hover_invalid")
        end
        return
    end
    local macro
    if not SecureCmdOptionParse(self:GetAttribute("snapshot-guard")) then
        macro = self:GetAttribute("snapshot-fallback")
        self:SetAttribute("combat-branch", "fallback")
    elseif SecureCmdOptionParse("[@target,exists] present") then
        macro = self:GetAttribute("snapshot-with-target")
        self:SetAttribute("combat-branch", "name_bridge_restore")
    else
        macro = self:GetAttribute("snapshot-without-target")
        self:SetAttribute("combat-branch", "name_bridge_clear")
    end
    self:SetAttribute("type", macro and "macro" or nil)
    self:SetAttribute("macrotext", macro)
]]
Combat.Snippets={state=STATE,enter=ENTER,leave=LEAVE,preClick=PRECLICK}

local function owner()
    if Combat.owner then return Combat.owner end
    if not idle() or type(SecureHandlerWrapScript)~="function" or type(SecureHandlerSetFrameRef)~="function"
        or type(RegisterStateDriver)~="function" or type(ClearOverrideBindings)~="function" then return nil end
    local frame=CreateFrame("Frame","MyForeverTargetsCombatCastOwner",UIParent,"SecureHandlerStateTemplate")
    frame:SetAttribute("_onstate-combat",STATE)
    frame:SetAttribute("combat-active",false)
    frame:SetAttribute("guid-probe-suspended",NS.GUIDProbeSuspended==true)
    if NS.NearbyCast and NS.NearbyCast.owner then
        SecureHandlerSetFrameRef(frame,"nearbyOwner",NS.NearbyCast.owner)
    end
    RegisterStateDriver(frame,"combat","[combat] combat; idle")
    Combat.owner=frame
    return frame
end

local function observedAliasGuard(proxy)
    if type(SecureCmdOptionParse)~="function" then return "[unavailable]" end
    local guard=NS.Read(proxy.GetAttribute,proxy,"snapshot-guard")
    if type(guard)~="string" then return "[guard-unreadable]" end
    local ok,value=pcall(SecureCmdOptionParse,guard)
    if not ok then return "[api-error]" end
    if not NS.Public(value) then return "[restricted]" end
    if value==nil then return "[nil]" end
    if type(value)=="string" or type(value)=="boolean" or NS.Number(value) then return value end
    return "[unsupported]"
end

local function observe(proxy,button,down)
    pcall(function()
        proxy.guidHoverLogID=nil
        if NS.Public(button) and button==nil then return end
        if not Combat.owner or NS.Read(Combat.owner.GetAttribute,Combat.owner,"combat-active")~=true then return end
        local diagnostics=NS.Diagnostics
        if type(diagnostics)~="table" or type(diagnostics.Record)~="function"
            or type(diagnostics.Enabled)=="function" and NS.Read(diagnostics.Enabled)~=true then return end
        local entry,data,row=proxy.entry,proxy.snapshot,proxy.row
        if not entry or not data then return end
        local preserving=NS.Read(proxy.GetAttribute,proxy,"snapshot-preserve-target")==true
        local targetGUID,targetExists=NS.Read(UnitGUID,"target"),NS.Read(UnitExists,"target")
        if preserving then proxy.guidHoverBefore={guid=targetGUID,exists=targetExists} end
        local fields={button=button,down=down,combat=NS.Read(InCombatLockdown),
            snapshotName=data.targetName,snapshotGUID=data.guid,snapshotUnit=data.unit,
            rowUnit=row and row.unit,rowGUID=row and NS.Read(UnitGUID,row.unit),expectedGUID=row and row.expectedGUID,
            targetGUID=targetGUID,targetGUIDBefore=targetGUID,targetExistsBefore=targetExists,targetName=NS.Read(UnitName,"target"),
            nativeMouseoverGUID=NS.Read(UnitGUID,"mouseover"),activeZBinding=NS.Read(GetBindingAction,"Z",true),
            slot=entry.slot,spellID=entry.spellID,actionKind=entry.actionKind,side=entry.side,
            configuredCommand=entry.command,branch=NS.Read(proxy.GetAttribute,proxy,"combat-branch"),
            preserveTarget=preserving,castMode=preserving and "guid_hover" or "legacy_name",
            frozenNameSnapshot=not preserving,frozenGUIDSnapshot=preserving}
        local snapshotMacro
        if preserving then
            snapshotMacro=NS.Read(proxy.GetAttribute,proxy,"snapshot-guid-macro")
            fields.snapshotMacroPresent=type(snapshotMacro)=="string" and snapshotMacro~=""
            fields.aliasGuardPublicResult=observedAliasGuard(proxy)
            fields.selectedActionType=NS.Read(proxy.GetAttribute,proxy,"type") or "[nil]"
            fields.selectedCommandMatches=fields.snapshotMacroPresent
                and NS.Read(proxy.GetAttribute,proxy,"macrotext")==snapshotMacro
        end
        for i,key in ipairs(entry.keys) do fields["configuredKey"..i]=key end
        diagnostics.Record("COMBAT_KEY_PREPARE",fields)
        if preserving and fields.branch=="guid_hover" and type(diagnostics.BeginCastAttempt)=="function" then
            local attempt={route="combat",row=NS.Read(row and row.GetName,row),rowUnit=row and row.unit,
                expectedGUID=data.guid,spellID=entry.spellID,slot=entry.slot,
                generatedCommand=snapshotMacro,selectedActionType=fields.selectedActionType,
                beforeTargetGUID=targetGUID,beforeTargetExists=targetExists,
                button=button,down=down,recipientProven=false}
            attempt.selectedCommandMatches=fields.selectedCommandMatches
            for i,key in ipairs(entry.keys) do attempt["configuredKey"..i]=key end
            proxy.guidHoverLogID=NS.Read(diagnostics.BeginCastAttempt,attempt)
        end
    end)
end

local function observePost(proxy,button,down)
    local attemptID=proxy.guidHoverLogID
    proxy.guidHoverLogID=nil
    pcall(function()
        if NS.Public(button) and button==nil then return end
        if not Combat.owner or NS.Read(Combat.owner.GetAttribute,Combat.owner,"combat-active")~=true
            or NS.Read(proxy.GetAttribute,proxy,"snapshot-preserve-target")~=true then return end
        local diagnostics=NS.Diagnostics
        if type(diagnostics)~="table" or type(diagnostics.Record)~="function"
            or type(diagnostics.Enabled)=="function" and NS.Read(diagnostics.Enabled)~=true then return end
        local entry,data,before=proxy.entry,proxy.snapshot,proxy.guidHoverBefore
        if not entry or not data then return end
        local afterGUID,afterExists=NS.Read(UnitGUID,"target"),NS.Read(UnitExists,"target")
        local changed
        if before then
            if type(before.guid)=="string" and type(afterGUID)=="string" then changed=before.guid~=afterGUID
            elseif type(before.exists)=="boolean" and type(afterExists)=="boolean" then
                if before.exists~=afterExists then changed=true
                elseif before.exists==false then changed=false end
            end
        end
        local fields={button=button,down=down,combat=NS.Read(InCombatLockdown),castMode="guid_hover",preserveTarget=true,
            snapshotGUID=data.guid,snapshotUnit=data.unit,expectedGUID=data.guid,slot=entry.slot,spellID=entry.spellID,
            targetGUIDBefore=before and before.guid,targetExistsBefore=before and before.exists,
            targetGUIDAfter=afterGUID,targetExistsAfter=afterExists,targetChangedObserved=changed,
            beforeAvailable=before~=nil,branch=NS.Read(proxy.GetAttribute,proxy,"combat-branch"),
            nativeMouseoverGUID=NS.Read(UnitGUID,"mouseover"),activeZBinding=NS.Read(GetBindingAction,"Z",true)}
        for i,key in ipairs(entry.keys) do fields["configuredKey"..i]=key end
        diagnostics.Record("GUID_HOVER_POSTCLICK",fields)
        if attemptID and type(diagnostics.EndCastAttempt)=="function" then
            diagnostics.EndCastAttempt(attemptID,fields)
        end
        proxy.guidHoverBefore=nil
    end)
end

function Combat.Install(row)
    if Combat.installed[row] then return true end
    -- Name continuation: enemy tiles only. Friendly tiles and enemy-target bars
    -- are never installed here, so NearbyCast keeps its own original leave/hide
    -- wrappers for them and their out-of-combat behavior is unchanged.
    if legacy and (row.side~="enemy" or row.bridgeTarget==true) then return false end
    local frame=owner()
    if not frame then return false end
    local index=#Combat.rows+1
    Combat.rows[index]=row
    Combat.installed[row]=index
    Combat.states[row]={prepared=false,count=0,reason="no_unit",proxies={}}
    row:SetAttribute("combat-row-index",index)
    row:SetAttribute("combat-prepared",false)
    row:SetAttribute("combat-key-count",0)
    SecureHandlerSetFrameRef(frame,"row"..index,row)
    -- Use one Leave wrapper for both owners: nested native OnLeave wrappers
    -- share _wrapentered, so the outer wrapper would suppress the inner one.
    SecureHandlerWrapScript(row,"OnEnter",frame,ENTER)
    SecureHandlerWrapScript(row,"OnLeave",frame,LEAVE)
    SecureHandlerWrapScript(row,"OnHide",frame,LEAVE)
    return true
end

local function disarm(row,state,reason)
    row:SetAttribute("combat-prepared",false)
    row:SetAttribute("combat-key-count",0)
    state.prepared,state.count,state.reason=false,0,reason
    state.data=nil
    state.preserveTarget=preserveTarget()
end

function Combat.ArmRow(row,actions)
    if not idle() then return false end
    if not Combat.Install(row) then return false end
    local state=Combat.states[row]
    local enabled=NS.DB and (legacy and NS.DB.legacyNameBridgeEnabled or not legacy and NS.DB.mouseoverRequested)
    if not enabled then disarm(row,state,"disabled");return false end
    -- An enemy's target bar follows that enemy's live target, which changes
    -- during combat; a name frozen before combat would no longer describe it.
    if legacy and row.bridgeTarget==true then disarm(row,state,"out_of_combat_only");return false end
    if row.side=="friendly" and type(row.unit)=="string" and not row.unit:match("^nameplate%d+$") then
        disarm(row,state,"native_unit");return false
    end
    if preserveTarget() and row.side~="enemy" then disarm(row,state,"unsupported_guid_unit");return false end
    if not row.unit then disarm(row,state,"no_unit");return false end
    if NS.Read(row.IsVisible,row)~=true then disarm(row,state,"invalid_row");return false end
    local data,unique=NS.NearbyCast.SnapshotRow(row)
    if not data then disarm(row,state,"invalid_row");return false end
    if preserveTarget() then
        if not NS.Public(data.player) or data.player~=false then disarm(row,state,"unsupported_guid_unit");return false end
        if not plain(data.guid) then disarm(row,state,"invalid_guid");return false end
    elseif not unique then disarm(row,state,"not_unique");return false end
    local entries=actions or NS.NearbyCast.DiscoverActions(row.side,true)
    local count=0
    for i,entry in ipairs(entries) do
        local macros=Combat.BuildMacros(data,entry)
        if macros then
            local proxy=state.proxies[i]
            if not proxy then
                proxy=CreateFrame("Button","MyForeverTargetsCombatCast"..Combat.installed[row].."_"..i,Combat.owner,"SecureActionButtonTemplate")
                proxy:SetSize(1,1)
                proxy:SetPoint("TOPLEFT",UIParent,"TOPLEFT",-10,10)
                proxy:EnableMouse(false)
                proxy:SetScript("PreClick",observe)
                proxy:SetScript("PostClick",observePost)
                SecureHandlerSetFrameRef(proxy,"row",row)
                SecureHandlerWrapScript(proxy,"PreClick",Combat.owner,PRECLICK)
                state.proxies[i]=proxy
                Combat.proxies[#Combat.proxies+1]=proxy
            end
            proxy.entry,proxy.snapshot,proxy.row=entry,data,row
            proxy:SetAttribute("type",nil)
            proxy:SetAttribute("unit",nil)
            proxy:SetAttribute("action",nil)
            proxy:SetAttribute("macrotext",nil)
            proxy:SetAttribute("snapshot-guard",macros.guard)
            proxy:SetAttribute("snapshot-preserve-target",macros.preserveTarget==true)
            proxy:SetAttribute("snapshot-guid-macro",macros.guidMacro)
            proxy:SetAttribute("snapshot-with-target",macros.withTarget)
            proxy:SetAttribute("snapshot-without-target",macros.withoutTarget)
            proxy:SetAttribute("snapshot-fallback",macros.fallback)
            proxy:SetAttribute("useOnKeyDown",entry.useOnKeyDown)
            proxy:RegisterForClicks(entry.useOnKeyDown and "AnyDown" or "AnyUp")
            for _,key in ipairs(entry.keys) do
                count=count+1
                row:SetAttribute("combat-key"..count,key)
                row:SetAttribute("combat-proxy"..count,proxy:GetName())
            end
        end
    end
    if count==0 then disarm(row,state,"no_actions");return false end
    state.prepared,state.count,state.reason,state.data=true,count,"prepared",data
    state.preserveTarget=preserveTarget()
    row:SetAttribute("combat-key-count",count)
    row:SetAttribute("combat-prepared",true)
    return true,count
end

function Combat.Status(row)
    local state=row and Combat.states[row]
    if row then
        local data=state and state.data
        local preserving=state and state.preserveTarget
        if preserving==nil then preserving=preserveTarget() end
        return {prepared=state and state.prepared or false,count=state and state.count or 0,
            name=data and data.targetName,guid=data and data.guid,unit=data and data.unit,
            reason=state and state.reason or "not_installed",
            preserveTarget=preserving,castMode=preserving and "guid_hover" or "legacy_name"}
    end
    local preparedCount=0
    for _,value in pairs(Combat.states) do if value.prepared then preparedCount=preparedCount+1 end end
    local index=Combat.owner and NS.Read(Combat.owner.GetAttribute,Combat.owner,"combat-hover-index")
    local current=NS.Number(index) and Combat.rows[index]
    local result=current and Combat.Status(current) or {prepared=false,count=0,reason="no_hover"}
    result.preparedCount=preparedCount
    result.active=Combat.owner and NS.Read(Combat.owner.GetAttribute,Combat.owner,"combat-active")==true or false
    if not result.active then result.count=0 end
    return result
end

function Combat.Reconcile()
    if not idle() or Combat.reconciling then return false end
    if legacy then
        -- Track only this module's own hover index. The out-of-combat bridge
        -- (NearbyCast) reconciles itself; it is not cleared or re-entered here.
        Combat.reconciling=true
        if Combat.owner then ClearOverrideBindings(Combat.owner) end
        local foci,index=NS.Read(GetMouseFoci),nil
        if type(foci)=="table" then
            for _,focus in ipairs(foci) do
                if NS.Public(focus) and Combat.installed[focus] and NS.Read(focus.IsVisible,focus)==true then
                    index=Combat.installed[focus];break
                end
            end
        end
        if Combat.owner then Combat.owner:SetAttribute("combat-hover-index",index) end
        Combat.reconciling=false
        return index~=nil
    end
    Combat.reconciling=true
    if Combat.owner then ClearOverrideBindings(Combat.owner) end
    local foci=NS.Read(GetMouseFoci)
    local index
    if type(foci)=="table" then
        for _,focus in ipairs(foci) do
            if NS.Public(focus) and Combat.installed[focus] and NS.Read(focus.IsVisible,focus)==true then
                local data=NS.NearbyCast.SnapshotRow(focus)
                if data then index=Combat.installed[focus];break end
            end
        end
    end
    if Combat.owner then Combat.owner:SetAttribute("combat-hover-index",index) end
    local restored=NS.NearbyCast.Reconcile and NS.NearbyCast.Reconcile() or false
    Combat.reconciling=false
    return restored
end

function Combat.RefreshAll()
    if not idle() or Combat.refreshing then return false end
    Combat.refreshing=true
    if Combat.owner then ClearOverrideBindings(Combat.owner) end
    local entries={friendly=NS.NearbyCast.DiscoverActions("friendly",true),enemy=NS.NearbyCast.DiscoverActions("enemy",true)}
    for _,row in ipairs(Combat.rows) do Combat.ArmRow(row,entries[row.side]) end
    Combat.refreshing=false
    return Combat.Reconcile()
end

local events=CreateFrame("Frame")
local pending,elapsed=false,0
for _,event in ipairs({"UPDATE_BINDINGS","ACTIONBAR_SLOT_CHANGED","ACTIONBAR_PAGE_CHANGED","UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR","UPDATE_SHAPESHIFT_FORM","CVAR_UPDATE","SPELL_TEXT_UPDATE","UPDATE_MACROS",
    "NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_REGEN_ENABLED"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function()
    if not Combat.refreshing and not Combat.reconciling
        and not (NS.NearbyCast and NS.NearbyCast.changing) then pending=true end
end)
events:SetScript("OnUpdate",function(_,delta)
    if not idle() then return end
    elapsed=elapsed+delta
    if elapsed>=.1 then
        elapsed=0
        if pending then pending=false;Combat.RefreshAll() end
        -- Record actual OOC focus even when a Lua layout/overlay change did
        -- not produce a motion-qualified secure OnEnter/OnLeave notification.
        if Combat.owner then
            local foci=NS.Read(GetMouseFoci)
            local index
            if type(foci)=="table" then
                for _,focus in ipairs(foci) do
                    if NS.Public(focus) and Combat.installed[focus] and NS.Read(focus.IsVisible,focus)==true then
                        local data=NS.ReadUnit(focus.unit,focus.side)
                        if data and NS.Public(focus.expectedGUID) and data.guid==focus.expectedGUID then
                            index=Combat.installed[focus];break
                        end
                    end
                end
            end
            if NS.Read(Combat.owner.GetAttribute,Combat.owner,"combat-hover-index")~=index then
                Combat.owner:SetAttribute("combat-hover-index",index)
            end
        end
    end
end)
