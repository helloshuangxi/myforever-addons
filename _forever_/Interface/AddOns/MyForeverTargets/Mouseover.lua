local _, NS = ...

-- This is a readback of the client's real mouseover, not a synthetic unit or
-- a cast. In particular, a readable nameplate GUID/tooltip is not sufficient.
function NS.NativeMouseoverStatus(row)
    row=row or NS.HoveredTile
    local details={identityMatches=false,conditionMatched=false,reason="not_hovered"}
    local function publicGUID(unit)
        local value=NS.Read(UnitGUID,unit)
        return type(value)=="string" and value~="" and value or nil
    end
    details.mouseoverGUID=publicGUID("mouseover")
    if not row or row~=NS.HoveredTile then
        return false,"请悬停一个目标方块，使用原来的宏和按键。",details
    end
    local expected=NS.Public(row.expectedGUID) and row.expectedGUID
    if type(expected)=="string" and expected~="" then details.expectedGUID=expected end
    local unit=NS.Public(row.unit) and row.unit
    if NS.ValidToken(unit) then details.unitGUID=publicGUID(unit) end
    if not details.expectedGUID or details.unitGUID~=details.expectedGUID then
        details.reason="stale_unit"
        return false,"方块单位已变化，尚未确认鼠标单位。",details
    end
    details.identityMatches=details.mouseoverGUID==details.expectedGUID
    if not details.identityMatches then
        details.reason=details.mouseoverGUID and "different_mouseover" or "no_mouseover"
        local message=details.mouseoverGUID and "客户端鼠标单位是另一目标；本格未确认，原宏可能对另一目标生效。" or
            "客户端尚未将此方块识别为鼠标单位；宏可能回退当前目标。"
        return false,message,details
    end
    local enemy=row.side=="enemy"
    details.condition=enemy and "[@mouseover,nodead,harm]" or "[@mouseover,nodead,help]"
    details.conditionMatched=NS.Read(SecureCmdOptionParse,details.condition.." MFT_MOUSEOVER")=="MFT_MOUSEOVER"
    if not details.conditionMatched then
        details.reason="condition_unconfirmed"
        return false,"鼠标身份一致，但存活及敌友宏条件尚未确认。",details
    end
    details.reason="matched"
    return true,"客户端已确认鼠标单位及宏条件；施法仍由原宏和游戏处理。",details
end

local function getter()
    return C_CVar and C_CVar.GetCVar or GetCVar
end
local function setter()
    return C_CVar and C_CVar.SetCVar or SetCVar
end

local function autoSelfCastValue()
    local value=NS.Read(getter(),"autoSelfCast")
    return (value=="0" or value=="1") and value or nil
end

local function autoSelfCastWritable(value)
    if not value or type(setter())~="function" then return false end
    local info=C_CVar and C_CVar.GetCVarInfo or GetCVarInfo
    if type(info)~="function" then return true end
    local ok,current,_,_,_,locked,secure,readOnly=pcall(info,"autoSelfCast")
    if not ok or not NS.Public(current) or current==nil then return false end
    if type(current)=="table" then
        local readable
        readable,locked,secure,readOnly=pcall(function()
            return current.isLockedFromUser,current.isSecure,current.isReadOnly
        end)
        if not readable then return false end
    end
    return NS.Public(locked) and NS.Public(secure) and NS.Public(readOnly)
        and locked~=true and secure~=true and readOnly~=true
end

local function restoreAutoSelfCast(backup)
    local original=backup.autoSelfCast
    if original~="0" and original~="1" then return true end
    local current=autoSelfCastValue()
    if current==nil then return false end
    -- Only undo the enabled value this module owns. A player edit to zero wins.
    if current=="1" and current~=original then
        NS.Read(setter(),"autoSelfCast",original)
        if autoSelfCastValue()~=original then return false end
    end
    backup.autoSelfCast=nil
    return true
end
local function support()
    if type(IsMouseoverCastSupported)=="function" and NS.Read(IsMouseoverCastSupported)~=true then return false end
    local value=NS.Read(getter(),"enableMouseoverCast")
    return type(value)=="string" and type(setter())=="function"
        and type(GetModifiedClick)=="function" and type(SetModifiedClick)=="function"
end

local function save(bindingSet)
    if bindingSet~=1 and bindingSet~=2 then return false end
    if type(SaveBindings)~="function" then return false end
    NS.ChangingMouseover=true
    local ok,result=pcall(SaveBindings,bindingSet)
    NS.ChangingMouseover=false
    return ok and NS.Public(result) and result~=false
end

function NS.MouseoverStatus()
    if not support() then return false,"客户端未开放原生悬停施法",false end
    local enabled=NS.Read(getter(),"enableMouseoverCast")=="1"
        and NS.Read(GetModifiedClick,"MOUSEOVERCAST")=="NONE"
    return enabled,enabled and "悬停方块后按技能键" or "原生悬停施法未开启",true
end

function NS.SetMouseoverEnabled(enabled, quiet)
    enabled=enabled==true
    if NS.NativeMacroOnly and enabled then
        if not quiet then NS.Print("请使用自己的 @mouseover 宏；当前模式不启用全局自动悬停施法。") end
        return false
    end
    if NS.InCombat() then
        NS.PendingMouseover=enabled
        if not quiet then (NS.Notify or NS.Print)("悬停施法设置将在脱战后应用。","悬停施法：脱战后应用","pending") end
        return false
    end
    NS.DB.mouseoverRequested=enabled
    if not support() then
        if not quiet then NS.Print("客户端当前未开放原生鼠标指向施法，请在游戏设置中核实。") end
        return false
    end
    local oldValue=NS.Read(getter(),"enableMouseoverCast")
    local oldKey=NS.Read(GetModifiedClick,"MOUSEOVERCAST")
    local bindingSet=NS.Read(GetCurrentBindingSet)
    local oldAutoSelfCast=autoSelfCastValue()
    if enabled then
        if type(oldKey)~="string" then
            if not quiet then NS.Print("无法读取原生悬停修饰键，已保留原设置。") end
            return false
        end
        local freshBackup=not NS.DB.mouseoverBackup
        if not NS.DB.mouseoverBackup then
            NS.DB.mouseoverBackup={enabled=oldValue,key=oldKey,bindingSet=bindingSet,modifiers={},pendingSaves={}}
        end
        local backup=NS.DB.mouseoverBackup
        backup.modifiers=backup.modifiers or {}
        local newModifier=backup.modifiers[bindingSet]==nil
        if bindingSet~=1 and bindingSet~=2 then
            if freshBackup then NS.DB.mouseoverBackup=nil end
            return false
        end
        if newModifier then backup.modifiers[bindingSet]=oldKey end
        if backup.enabled==nil then backup.enabled=oldValue end
        NS.Read(setter(),"enableMouseoverCast","1")
        if oldKey~="NONE" then
            NS.Read(SetModifiedClick,"MOUSEOVERCAST","NONE")
        end
        -- Native helpful-action fallback after mouseover/current target. This
        -- cannot make an otherwise unrecognized unit-frame mouseover exist.
        local changedAuto=oldAutoSelfCast=="0" and autoSelfCastWritable(oldAutoSelfCast)
        if changedAuto then
            if backup.autoSelfCast==nil then backup.autoSelfCast=oldAutoSelfCast end
            NS.Read(setter(),"autoSelfCast","1")
        end
        if not NS.MouseoverStatus() or (changedAuto and autoSelfCastValue()~="1")
            or (oldKey~="NONE" and not save(bindingSet)) then
            -- A read-only CVar or rejected modifier must not leave a half-applied change.
            NS.Read(setter(),"enableMouseoverCast",oldValue)
            NS.Read(SetModifiedClick,"MOUSEOVERCAST",oldKey)
            if changedAuto and autoSelfCastValue()==oldAutoSelfCast then backup.autoSelfCast=nil
            elseif changedAuto then restoreAutoSelfCast(backup) end
            if freshBackup and backup.autoSelfCast==nil then NS.DB.mouseoverBackup=nil end
            if not freshBackup and newModifier then backup.modifiers[bindingSet]=nil end
            if not quiet then NS.Print("原生悬停施法设置未生效，已恢复本次修改。") end
            return false
        end
    else
        local backup=NS.DB.mouseoverBackup
        if backup then
            local failed=not restoreAutoSelfCast(backup)
            if type(backup.enabled)=="string" then
                if oldValue=="1" then
                    NS.Read(setter(),"enableMouseoverCast",backup.enabled)
                    if NS.Read(getter(),"enableMouseoverCast")~=backup.enabled then failed=true
                    else backup.enabled=nil end
                else backup.enabled=nil end -- An external CVar edit belongs to the player.
            end
            backup.modifiers=backup.modifiers or {}
            backup.pendingSaves=backup.pendingSaves or {}
            local key=backup.modifiers[bindingSet]
            if not key and backup.bindingSet==bindingSet then key=backup.key end
            if type(key)=="string" then
                if oldKey=="NONE" or (oldKey==key and backup.pendingSaves[bindingSet]) then
                    NS.Read(SetModifiedClick,"MOUSEOVERCAST",key)
                    if NS.Read(GetModifiedClick,"MOUSEOVERCAST")~=key then failed=true
                    elseif not save(bindingSet) then failed=true;backup.pendingSaves[bindingSet]=true
                    else
                        backup.modifiers[bindingSet]=nil;backup.pendingSaves[bindingSet]=nil
                        if backup.bindingSet==bindingSet then backup.key=nil;backup.bindingSet=nil end
                    end
                else
                    backup.modifiers[bindingSet]=nil
                    backup.pendingSaves[bindingSet]=nil
                    if backup.bindingSet==bindingSet then backup.key=nil;backup.bindingSet=nil end
                end
            end
            if not failed and not backup.enabled and not backup.autoSelfCast and not next(backup.modifiers) then NS.DB.mouseoverBackup=nil end
            if failed then
                if not quiet then NS.Print("原设置尚未完全恢复，已保留备份；请再次关闭悬停施法重试。") end
                return false
            end
        end
    end
    local active=NS.MouseoverStatus()
    if enabled and not active then
        if not quiet then NS.Print("原生悬停施法设置未生效，请检查客户端设置。") end
        return false
    end
    if NS.RefreshControls then NS.RefreshControls() end
    if not quiet then NS.Print(enabled and "已开启原生悬停施法：指向方块后按原来的技能键，无需切换目标。" or
        (NS.DB.mouseoverBackup and "已恢复当前按键方案；其他方案切回后恢复。" or "已恢复开启前的鼠标指向设置。")) end
    return true
end
