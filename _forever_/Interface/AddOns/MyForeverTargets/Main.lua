local addonName, NS = ...
local initialized, ready, dirty=false,false,true
local visualTick, rosterTick, probeTick=0,0,0
local worldActive=true
NS.Bindings={}
NS.Totals={friendly=0,enemy=0}
local settingValues={friendlyTab={raid=true,party=true,nearby=true},
    nearbyLimit={[5]=true,[10]=true,[20]=true},enemyLimit={[5]=true,[10]=true,[20]=true}}

local function releaseNativeHit()
    local scaleProbe=NS.NativeScaleProbe
    if scaleProbe and type(scaleProbe.Stop)=="function" and scaleProbe.Stop("layout_or_binding_change")~=true then return false end
    local module=NS.EnemyNativeHover
    return not module or type(module.Disable)~="function" or module.Disable()
end

local function sameBinding(previous,tokens,side,limit,mode)
    if not previous or previous.limit~=limit or previous.mode~=mode or #previous.tokens~=#tokens then return false end
    for i,unit in ipairs(tokens) do
        local data=NS.ReadUnit(unit,side)
        if previous.tokens[i]~=unit or not data or previous.guids[i]~=data.guid
            or (previous.targetNames or {})[i]~=data.targetName then return false end
    end
    return true
end

local function holdHoveredSide(previous,side,limit,mode)
    local scaleProbe=NS.NativeScaleProbe
    local scaleStatus=scaleProbe and type(scaleProbe.Status)=="function" and NS.Read(scaleProbe.Status)
    if side=="enemy" and previous and previous.limit==limit and previous.mode==mode
        and type(scaleStatus)=="table" and scaleStatus.active==true then return true end
    local cycle=NS.FocusCycle
    if cycle and type(cycle.HoldRoster)=="function" and cycle.HoldRoster(side,limit)==true then return true end
    local row=NS.HoveredEnemyTarget and NS.HoveredEnemyTarget.owner or NS.HoveredTile
    if not previous or previous.limit~=limit or previous.mode~=mode or not row or row.side~=side then return false end
    local current=NS.ReadUnit(row.unit,side)
    return current~=nil and current.guid==row.expectedGUID
end

function NS.RequestRefresh()
    dirty=true
    if not ready or NS.InCombat() then return end
    local friendlyLimit=NS.DB.friendlyTab=="raid" and 20 or NS.DB.friendlyTab=="party" and 5 or NS.DB.nearbyLimit
    for _,side in ipairs({"friendly","enemy"}) do
        local limit=side=="friendly" and friendlyLimit or NS.DB.enemyLimit
        local mode=side=="friendly" and NS.DB.friendlyTab or "enemy"
        local tokens,total=NS.Collect(side,mode,limit)
        NS.Totals[side]=total
        if not sameBinding(NS.Bindings[side],tokens,side,limit,mode) and not holdHoveredSide(NS.Bindings[side],side,limit,mode) then
            -- A live native hit area must be released before reusing its cell.
            if side=="enemy" and not releaseNativeHit() then return end
            local guids,targetNames={},{}
            for i,unit in ipairs(tokens) do
                local data=NS.ReadUnit(unit,side);guids[i]=data and data.guid;targetNames[i]=data and data.targetName
            end
            NS.Bindings[side]={tokens=tokens,guids=guids,targetNames=targetNames,limit=limit,mode=mode}
            NS.BindTiles(side,tokens,limit)
        end
    end
    if NS.RefreshControls then NS.RefreshControls() end
    if NS.RefreshTiles then NS.RefreshTiles() end
    dirty=false
end

local function applyVisualSettings()
    if not NS.UI then return end
    local becameShown=false
    for _,side in ipairs({"friendly","enemy"}) do
        local frame=NS.UI[side] and NS.UI[side].frame
        if frame then
            frame:SetScale(NS.DB.scale)
            if NS.IsPanelShown(side) then
                becameShown=not frame:IsShown() or becameShown
                frame:Show()
            else
                frame:Hide()
                if NS.HoveredTile and NS.HoveredTile.side==side then
                    NS.HoveredTile=nil
                    if NS.HideHover then NS.HideHover() end
                end
                local hoveredTarget=NS.HoveredEnemyTarget
                if hoveredTarget and hoveredTarget.owner and hoveredTarget.owner.side==side
                    and NS.EnemyTargetHover then NS.EnemyTargetHover.Clear() end
            end
        end
    end
    if not NS.DB.shown then
        if NS.HideHover then NS.HideHover() end
        if NS.HideWorldIndicators then NS.HideWorldIndicators() end
        if NS.EnemyTargetHover then NS.EnemyTargetHover.Clear() end
    elseif worldActive and NS.UpdateWorldIndicators then
        NS.UpdateWorldIndicators()
    end
    if becameShown and not NS.InCombat() and NS.CombatCast
        and type(NS.CombatCast.RefreshAll)=="function" then NS.CombatCast.RefreshAll() end
    if NS.RefreshLauncher then NS.RefreshLauncher() end
end

local function saveSettings(values)
    for key,value in pairs(values) do NS.DB[key]=value end
    if values.shown~=nil then
        NS.DB.friendlyShown,NS.DB.enemyShown=values.shown,values.shown
    end
    NS.DB.shown=NS.DB.friendlyShown~=false or NS.DB.enemyShown~=false
end

local function requestedPanelShown(side)
    local pending=NS.PendingSettings
    if pending and pending[side.."Shown"]~=nil then return pending[side.."Shown"] end
    return NS.IsPanelShown(side)
end

local function leaveHiddenCast(values)
    local cast=NS.NearbyCast
    if not cast then return end
    if values.legacyNameBridgeEnabled~=nil or values.shown==false then cast.Leave();return end
    local row=cast.row
    local side=row and (row.owner and row.owner.side or row.side)
    if (side=="friendly" or side=="enemy") and values[side.."Shown"]==false then cast.Leave(row) end
end

local function clearSupersededSetting(key)
    local pending=NS.PendingSettings
    if not pending then return end
    if key=="shown" then pending.friendlyShown,pending.enemyShown=nil,nil
    else pending[key]=nil end
    if next(pending)==nil then NS.PendingSettings=nil end
end

function NS.ApplySetting(key,value)
    if settingValues[key] then
        if not settingValues[key][value] then return false end
    elseif key=="scale" then
        if not NS.Number(value) then return false end
        value=math.max(.7,math.min(1.4,value))
    elseif key=="shown" or key=="friendlyShown" or key=="enemyShown"
        or key=="locked" or key=="legacyNameBridgeEnabled" then value=value==true
    else return false end
    if NS.InCombat() then
        NS.PendingSettings=NS.PendingSettings or {}
        if key=="shown" then
            NS.PendingSettings.friendlyShown,NS.PendingSettings.enemyShown=value,value
        else NS.PendingSettings[key]=value end
        if NS.RefreshLauncher then NS.RefreshLauncher() end
        NS.Print("已记住设置，脱战后应用；战斗中名单与位置保持固定。")
        return false
    end
    if not releaseNativeHit() then
        NS.Print("原生命中区仍在恢复，暂缓改变面板；/mytargets native off 可重试。")
        return false
    end
    clearSupersededSetting(key)
    saveSettings({[key]=value})
    leaveHiddenCast({[key]=value})
    if NS.CloseMarkMenu then NS.CloseMarkMenu() end
    applyVisualSettings()
    NS.RequestRefresh()
    if key=="legacyNameBridgeEnabled" and NS.NearbyCast and NS.NearbyCast.Reconcile then
        NS.NearbyCast.Reconcile()
    end
    return true
end

function NS.SetShown(value)
    if value==nil then value=not (requestedPanelShown("friendly") or requestedPanelShown("enemy")) end
    return NS.ApplySetting("shown",value)
end
function NS.SetPanelShown(side,value)
    if side~="friendly" and side~="enemy" then return false end
    if value==nil then value=not requestedPanelShown(side) end
    return NS.ApplySetting(side.."Shown",value)
end
function NS.SetLocked(value) return NS.ApplySetting("locked",value) end
function NS.SetScale(value) return NS.ApplySetting("scale",value) end

local function resetPositions()
    local defaults=NS.NormalizeDB(nil)
    for _,side in ipairs({"friendly","enemy"}) do
        local key=side.."Position"
        NS.DB[key]=defaults[key]
        local frame=NS.UI and NS.UI[side] and NS.UI[side].frame
        if frame then
            local p=NS.DB[key]
            frame:ClearAllPoints();frame:SetPoint(p.point,UIParent,p.relativePoint,p.x,p.y)
        end
    end
    if NS.ResetLauncherPosition then NS.ResetLauncherPosition() end
end

local function macroHelp()
    NS.Print("使用你原来的鼠标指向宏及按键，例如：/cast [@mouseover,nodead,harm] 恐惧术; 恐惧术;")
    NS.Print("先匹配存活敌方鼠标单位，否则走原宏后续分支；已有宏保持原内容及原按键。")
    if NS.LegacyNameBridge==true then
        NS.Print("普通技能使用已授权的临时选目标兼容方式；已有宏不接入该方式。/mytargets legacycast on 或 off")
    end
    if type(NS.NativeMouseoverStatus)=="function" then
        local _,status=NS.NativeMouseoverStatus()
        NS.Print(status)
    end
end

local function nativeProbe(argument)
    local scaleProbe=NS.NativeScaleProbe
    local scaleStatus=scaleProbe and type(scaleProbe.Status)=="function" and NS.Read(scaleProbe.Status)
    if (argument=="on" or argument=="trial") and type(scaleStatus)=="table"
        and (scaleStatus.active or scaleStatus.restoring) then
        NS.Print("缩放探针尚未恢复，请先 /mytargets platescale stop。");return
    end
    local module=NS.EnemyNativeHover
    if not module then NS.Print("原生姓名板映射模块尚未加载，请 /reload。");return end
    local trial=NS.EnemyNativeTrial
    if argument=="trial" or argument=="trialstatus" then
        if not trial then NS.Print("顶部原生验证模块尚未加载，请 /reload。");return end
        if argument=="trial" and NS.NativeTrialUnavailable then
            NS.Print("此客户端的姓名板尺寸被限制为512×256，顶部映射试验已停用；尚未实现固定敌方格的原生mouseover。")
            return
        end
        if argument=="trial" and not module.Disable() then NS.Print("旧命中映射仍待恢复，暂不启动顶部验证。");return end
        module=trial
    end
    if argument=="on" and trial and not trial.Disable() then NS.Print("顶部验证仍待恢复，暂不启用另一映射。");return end
    if argument=="on" or argument=="trial" then
        local row=NS.HoveredTile
        if not row or row.side~="enemy" or not NS.ValidToken(row.unit) or not row.unit:match("^nameplate%d+$") then
            row=nil
            local tiles=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles or {}
            for _,candidate in ipairs(tiles) do
                if candidate.expectedGUID and NS.ValidToken(candidate.unit) and candidate.unit:match("^nameplate%d+$") then row=candidate;break end
            end
        end
        local ok,reason=module.Enable(row)
        NS.Print(ok and (argument=="trial" and "顶部临时方块已准备。只需悬停，不用点击或施法；绿色表示真正鼠标GUID匹配。" or "已设置单格原生命中区候选。只需悬停此敌方格，不用施法；设置成功不等于鼠标身份已匹配。") or
            "原生命中区未启用："..NS.Text(reason))
    elseif argument=="off" then
        local trialRestored=not trial or trial.Disable()
        local restored=module.Disable() and trialRestored
        NS.Print(restored and "单格原生命中区已恢复。" or "原生命中区仍待恢复，脱战后重试。")
        if restored and (NS.PendingSettings or NS.PendingReset) and type(NS.HandleEvent)=="function" then
            NS.HandleEvent("PLAYER_REGEN_ENABLED")
        end
    end
    local status=module.Status()
    if type(status)=="table" then
        NS.Print("原生映射："..NS.Text(status.reason).."；单位="..NS.Text(status.unit)..
            "；真实鼠标身份="..(NS.Public(status.matches) and status.matches==true and "匹配" or "尚未匹配")..
            "。/mytargets native on / off / status")
    end
end

-- Explicit @mouseover macros do not need the global mouseover-cast option.
-- Undo only changes recorded as owned by older addon versions. The restoration
-- retains its backup when another binding profile or a failed save remains.
local function restoreLegacyMouseover()
    NS.PendingMouseover=nil
    NS.DB.mouseoverRequested=false
    if NS.DB.mouseoverBackup then NS.SetMouseoverEnabled(false,true) end
    NS.MouseoverApplied=true
end

function NS.HandleCommand(message)
    local command,argument=NS.Text(message):match("^%s*(%S*)%s*(.-)%s*$")
    command=command:lower()
    if command=="platescale" then
        if NS.NativeScaleProbe and type(NS.NativeScaleProbe.Command)=="function" then NS.NativeScaleProbe.Command(argument)
        else NS.Print("缩放诊断模块未加载，请 /reload 后重试。") end
        return
    end
    if command=="focuscycle" then
        if NS.FocusCycle and type(NS.FocusCycle.Command)=="function" then NS.FocusCycle.Command(argument)
        else NS.Print("焦点查找模块未加载，请 /reload 后重试。") end
        return
    end
    if command=="focusprobe" then
        local scaleProbe=NS.NativeScaleProbe
        local scaleStatus=scaleProbe and type(scaleProbe.Status)=="function" and NS.Read(scaleProbe.Status)
        if type(scaleStatus)=="table" and (scaleStatus.active or scaleStatus.restoring) then
            NS.Print("缩放探针尚未恢复，请先 /mytargets platescale stop。");return
        end
        if NS.FocusAPIProbe and type(NS.FocusAPIProbe.Command)=="function" then NS.FocusAPIProbe.Command(argument)
        else NS.Print("测试模块未加载，请 /reload；若仍提示此消息，请保留游戏错误供排查。") end
        return
    end
    if command=="legacycast" or command=="friendlycast" then
        if argument=="on" or argument=="off" then
            NS.ApplySetting("legacyNameBridgeEnabled",argument=="on")
        end
        NS.Print("普通技能悬停兼容："..(NS.DB.legacyNameBridgeEnabled and "开启" or "关闭")..
            "；仅脱战，按键时临时选中悬停单位、施法并恢复原目标。/mytargets legacycast on 或 off")
        return
    end
    if command=="debug" then
        if NS.NativeMacroOnly then
            macroHelp()
            return
        end
        if argument=="enemyunit" and NS.NearbyCast then
            if NS.InCombat() then NS.Print("敌方单位诊断请在脱战后执行。");return end
            local row=NS.HoveredTile
            if not row or row.side~="enemy" then row=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles[1] end
            local data=row and row.unit and NS.ReadUnit(row.unit,"enemy")
            if NS.PreserveCastTarget then
                local eligible=data and not data.player and NS.Public(data.guid) and type(data.guid)=="string"
                    and data.guid~="" and data.guid==row.expectedGUID
                NS.Print("敌方 GUID直施尝试="..(eligible and "身份已读，待验证" or "此单位未接入")..
                    "；Z绑定="..NS.Text(NS.Read(GetBindingAction,"Z",true))..
                    "；悬停接管键="..tostring(NS.NearbyCast.count or 0).."；当前目标保持。这不是施法成功记录。")
                return
            end
            local eligible=data and (data.player or NS.NearbyCast.KnownUniqueNPC(data))
            NS.Print("敌方单位兼容="..(eligible and "可用" or "未确认唯一")..
                "；Z绑定="..NS.Text(NS.Read(GetBindingAction,"Z",true))..
                "；悬停接管键="..tostring(NS.NearbyCast.count or 0).."。这不是施法成功记录。")
            return
        end
        if argument=="enemy" and NS.NearbyCast then
            if NS.InCombat() then NS.Print("敌方按键诊断请在脱战后执行。");return end
            local entries=NS.NearbyCast.DiscoverActions("enemy")
            local keyCount,wKind=0,"未接管"
            for _,entry in ipairs(entries) do
                for _,key in ipairs(entry.keys) do
                    if not NS.PreserveCastTarget or entry.actionKind=="spell" then keyCount=keyCount+1 end
                    if key=="W" then
                        wKind=entry.actionKind=="macro" and (NS.PreserveCastTarget and "原宏保持，未接入" or "保留原宏分支") or "普通技能"
                    end
                end
            end
            if NS.PreserveCastTarget then
                NS.Print("敌方 GUID直施尝试："..keyCount.."个普通技能键；W="..wKind..
                    "；不切换当前目标。准备状态不代表施法成功，仍待游戏验证。")
                return
            end
            NS.Print("敌方非战斗兼容："..keyCount.."个可用技能键；W="..wKind.."。尚不代表实际施法成功。")
            return
        end
        local row=NS.UI and NS.UI.friendly and NS.UI.friendly.tiles[1]
        if row then
            NS.Print("点击诊断 native="..tostring(row.nativeClick==SecureActionButton_OnClick).." inherited="..tostring(row.nativeHandlerWasPresent)..
                " unit="..tostring(row:GetAttribute("unit")).." type="..tostring(row:GetAttribute("*type1")))
        end
    elseif command=="help" then
        if NS.NativeMacroOnly then
            NS.Print("/mytargets 显隐；raid 团队；party 小队；nearby 5/10/20；enemy 5/10/20；legacycast on/off 普通技能兼容；macro 原生宏说明；plates on/off 附近识别与原设置恢复；scale 0.7–1.4；lock/unlock；reset；log start/stop/status/mark。")
            return
        end
        local guidHelp=NS.PreserveCastTarget and "guid 查看GUID直施尝试说明。悬停正常敌方方块后按普通技能键，当前目标保持。" or
            "guid 打开两只同名怪的 GUID 隔离测试。悬停后按原技能键，左键选中，右键设焦点，Ctrl+右键标记。"
        NS.Print("/mytargets 显隐；raid 团队；party 小队；nearby 附近；enemy 5/10/20；nearby 5/10/20；hover on/off 悬停施法；plates on/off 附近识别与原设置恢复；scale 0.7–1.4；lock/unlock；reset；log start/stop/status/mark；"..guidHelp)
    elseif command=="guid" then
        if NS.NativeMacroOnly then
            NS.Print("GUID施法与旧实验已停用。")
            macroHelp()
        elseif NS.PreserveCastTarget then
            if NS.GUIDProbe and type(NS.GUIDProbe.Stop)=="function" then pcall(NS.GUIDProbe.Stop) end
            NS.Print("已停用A/B切目标测试；直接悬停正常敌方方块按普通技能键。GUID施法待验证，当前目标保持。")
        elseif NS.GUIDProbe and type(NS.GUIDProbe.Command)=="function" then NS.GUIDProbe.Command(argument)
        else NS.Print("GUID 测试模块尚未加载，请完整重启游戏。") end
    elseif command=="log" then
        if NS.Diagnostics and type(NS.Diagnostics.Command)=="function" then NS.Diagnostics.Command(argument)
        else NS.Print("日志模块尚未就绪。") end
    elseif command=="raid" or command=="party" or command=="nearby" then
        if command=="nearby" and argument~="" then NS.ApplySetting("nearbyLimit",tonumber(argument)) end
        NS.ApplySetting("friendlyTab",command)
    elseif command=="enemy" then NS.ApplySetting("enemyLimit",tonumber(argument))
    elseif command=="scale" then NS.SetScale(tonumber(argument))
    elseif command=="lock" or command=="unlock" then NS.SetLocked(command=="lock")
    elseif command=="show" then NS.SetShown(true)
    elseif command=="hide" then NS.SetShown(false)
    elseif command=="hover" then
        if NS.LegacyNameBridge==true and NS.NativeMacroOnly==true then
            NS.HandleCommand("legacycast "..argument)
        elseif NS.NativeMacroOnly then macroHelp()
        elseif argument=="on" or argument=="off" then NS.SetMouseoverEnabled(argument=="on")
        else local _,status=NS.MouseoverStatus();NS.Print(status.."；/mytargets hover on 或 off。") end
    elseif command=="macro" then macroHelp()
    elseif command=="native" then nativeProbe(argument)
    elseif command=="plates" then
        if argument=="on" or argument=="off" then NS.SetDetectionEnabled(argument=="on")
        else local _,status=NS.DetectionStatus();NS.Print(status.."；/mytargets plates on 或 off。") end
    elseif command=="reset" then
        if NS.InCombat() then NS.PendingReset=true;NS.Print("脱战后重置位置。")
        elseif not releaseNativeHit() then NS.PendingReset=true;NS.Print("原生命中区恢复后再重置位置。")
        else resetPositions();NS.SetShown(true) end
    elseif command=="" then NS.SetShown()
    else NS.Print("未知命令。输入 /mytargets help 查看用法。") end
end

-- An isolated probe must not accidentally pass through the normal name-based
-- targeting bridge. These changes happen only outside combat; secure combat
-- handlers also read their own protected suspension attribute on every entry.
function NS.SetGUIDProbeSuspended(value)
    if NS.NativeMacroOnly then return false end
    if NS.InCombat() then return false end
    NS.GUIDProbeSuspended=value==true
    if NS.NearbyCast then NS.NearbyCast.Leave() end
    local combatCast=NS.CombatCast
    if combatCast and combatCast.owner then
        combatCast.owner:SetAttribute("guid-probe-suspended",NS.GUIDProbeSuspended)
        ClearOverrideBindings(combatCast.owner)
    end
    if not NS.GUIDProbeSuspended then
        if combatCast and combatCast.RefreshAll then combatCast.RefreshAll()
        elseif NS.NearbyCast and NS.NearbyCast.Reconcile then NS.NearbyCast.Reconcile() end
    end
    return true
end

local function create()
    if ready or not initialized or NS.InCombat() then return end
    NS.CreateUI()
    if NS.CreateLauncher then NS.CreateLauncher() end
    ready=true
    applyVisualSettings()
    NS.RequestRefresh()
end

function NS.HandleEvent(event,unit)
    if event=="ADDON_LOADED" then
        if unit~=addonName or initialized then return end
        MyForeverTargetsDB=NS.Initialize(MyForeverTargetsDB)
        if NS.Diagnostics and type(NS.Diagnostics.Initialize)=="function" then NS.Diagnostics.Initialize() end
        initialized=true
        SLASH_MYFOREVERTARGETS1="/mytargets"
        SLASH_MYFOREVERTARGETS2="/mytarget"
        SlashCmdList.MYFOREVERTARGETS=NS.HandleCommand
        create()
        if NS.NativeMacroOnly then
            NS.DB.mouseoverRequested=false
            if NS.LegacyNameBridge==true then
                NS.Print("目标选择 "..NS.VERSION.." 已加载；全部目标普通技能兼容"..
                    (NS.DB.legacyNameBridgeEnabled and "已开启" or "已关闭").."，仅脱战，施法时临时选人并恢复原目标。")
            else
                NS.Print("目标选择 "..NS.VERSION.." 本机试用版已加载；使用自己的 @mouseover 宏和原按键，/mytargets macro 查看识别状态。")
            end
        else
            NS.Print("目标选择 "..NS.VERSION.." 本机试用版已加载，/mytargets。悬停方块后按技能键；首次开启会保存原生悬停设置。")
        end
        return
    end
    if not initialized then return end
    if NS.FocusCycle and type(NS.FocusCycle.OnEvent)=="function" then NS.FocusCycle.OnEvent(event,unit) end
    if NS.Auras and type(NS.Auras.OnEvent)=="function" then NS.Auras.OnEvent(event,unit) end
    if event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" then
        worldActive=false
        if NS.HideWorldIndicators then NS.HideWorldIndicators() end
    elseif event=="PLAYER_ENTERING_WORLD" then
        worldActive=true
    end
    if NS.EnemyNativeHover and type(NS.EnemyNativeHover.OnEvent)=="function" then
        NS.EnemyNativeHover.OnEvent(event,unit)
    end
    if NS.EnemyNativeTrial and type(NS.EnemyNativeTrial.OnEvent)=="function" then
        NS.EnemyNativeTrial.OnEvent(event,unit)
    end
    if (event=="UNIT_TARGET" or event=="NAME_PLATE_UNIT_REMOVED" or event=="PLAYER_TARGET_CHANGED"
        or event=="PLAYER_FOCUS_CHANGED" or event=="UNIT_NAME_UPDATE" or event=="UNIT_FACTION"
        or event=="GROUP_ROSTER_UPDATE") and type(NS.InvalidateMarkMenu)=="function" then
        -- Recheck only the unprotected input shield before the next visual tick.
        NS.InvalidateMarkMenu()
    end
    if event=="QUEST_LOG_UPDATE" or event=="UNIT_QUEST_LOG_CHANGED" or event=="QUEST_ACCEPTED"
        or event=="QUEST_REMOVED" or event=="QUEST_TURNED_IN" or event=="QUEST_WATCH_UPDATE" then
        if NS.InvalidateQuestCache then NS.InvalidateQuestCache() end
        visualTick=.1
        return
    end
    if event=="UNIT_AURA" or event=="UNIT_HEALTH" or event=="UNIT_MAXHEALTH" or event=="UNIT_FLAGS" or event=="UNIT_CONNECTION" or event=="RAID_TARGET_UPDATE" or event=="UNIT_TARGET"
        or event=="UNIT_POWER_UPDATE" or event=="UNIT_POWER_FREQUENT" or event=="UNIT_MAXPOWER" or event=="UNIT_DISPLAYPOWER" then
        -- Coalesce high-volume status events into the 10 Hz visual refresh.
        visualTick=.1
        return
    end
    if event=="UPDATE_BINDINGS" and not NS.ChangingMouseover
        and not (NS.NearbyCast and NS.NearbyCast.changing) and not NS.InCombat() then
        if NS.NativeMacroOnly then restoreLegacyMouseover()
        else NS.SetMouseoverEnabled(NS.DB.mouseoverRequested,true) end
    end
    if event=="NAME_PLATE_UNIT_ADDED" and NS.ValidToken(unit) then NS.Nameplates[unit]=true end
    if event=="NAME_PLATE_UNIT_REMOVED" and NS.ValidToken(unit) then NS.Nameplates[unit]=nil end
    if event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" then
        create()
        if not NS.InCombat() then
            if NS.PendingDetection~=nil then
                local enabled=NS.PendingDetection;NS.PendingDetection=nil;NS.SetDetectionEnabled(enabled,true)
                NS.DetectionApplied=true
            elseif not NS.DetectionApplied then
                NS.SetDetectionEnabled(NS.DB.detectionRequested,true)
                NS.DetectionApplied=true
            end
            local canApplyLayout=not (NS.PendingSettings or NS.PendingReset) or releaseNativeHit()
            if NS.PendingSettings and canApplyLayout then
                local settings=NS.PendingSettings
                saveSettings(NS.PendingSettings)
                NS.PendingSettings=nil
                if NS.CloseMarkMenu then NS.CloseMarkMenu() end
                leaveHiddenCast(settings)
                applyVisualSettings()
            end
            if NS.PendingReset and canApplyLayout then
                NS.PendingReset=nil;resetPositions();saveSettings({shown=true});applyVisualSettings()
            end
            if NS.NativeMacroOnly then
                restoreLegacyMouseover()
            elseif NS.PendingMouseover~=nil then
                local enabled=NS.PendingMouseover;NS.PendingMouseover=nil;NS.SetMouseoverEnabled(enabled,true)
            elseif not NS.MouseoverApplied then
                NS.SetMouseoverEnabled(NS.DB.mouseoverRequested,true)
                NS.MouseoverApplied=true
            end
        end
    end
    if event=="PLAYER_REGEN_DISABLED" then
        -- Cancel the unprotected drag preview; no protected panel move occurs here.
        if NS.StopDragging then NS.StopDragging() end
    end
    if ready then
        if NS.RefreshTiles then NS.RefreshTiles() end
        NS.RequestRefresh()
        if worldActive and (event=="PLAYER_TARGET_CHANGED" or event=="PLAYER_FOCUS_CHANGED"
            or event=="NAME_PLATE_UNIT_ADDED" or event=="NAME_PLATE_UNIT_REMOVED"
            or event=="PLAYER_ENTERING_WORLD") and NS.UpdateWorldIndicators then NS.UpdateWorldIndicators() end
        if event=="PLAYER_REGEN_ENABLED" and not NS.InCombat()
            and NS.CombatCast and type(NS.CombatCast.Reconcile)=="function" then NS.CombatCast.Reconcile() end
        if NS.RefreshLauncher and (event=="PLAYER_ENTERING_WORLD" or event=="DISPLAY_SIZE_CHANGED"
            or event=="UI_SCALE_CHANGED") then NS.RefreshLauncher() end
    else dirty=true end
end

local events=CreateFrame("Frame")
NS.EventFrame=events
for _,event in ipairs({"ADDON_LOADED","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED","UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_NAME_UPDATE","UNIT_FACTION",
    "UNIT_POWER_UPDATE","UNIT_POWER_FREQUENT","UNIT_MAXPOWER","UNIT_DISPLAYPOWER",
    "UNIT_CONNECTION","UNIT_FLAGS","UNIT_TARGET","UNIT_AURA","RAID_TARGET_UPDATE","UPDATE_BINDINGS","CVAR_UPDATE",
    "SPELLS_CHANGED","PLAYER_TALENT_UPDATE","PLAYER_SPECIALIZATION_CHANGED","UNIT_PET",
    "QUEST_LOG_UPDATE","UNIT_QUEST_LOG_CHANGED","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_WATCH_UPDATE",
    "PLAYER_LOGOUT","PLAYER_LEAVING_WORLD","DISPLAY_SIZE_CHANGED","UI_SCALE_CHANGED",
    "ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    pcall(events.RegisterEvent,events,event)
end
events:SetScript("OnEvent",function(_,event,unit) NS.HandleEvent(event,unit) end)
events:SetScript("OnUpdate",function(_,elapsed)
    if not ready then return end
    visualTick,rosterTick,probeTick=visualTick+elapsed,rosterTick+elapsed,probeTick+elapsed
    if visualTick>=.1 then
        local delta=visualTick
        visualTick=0
        if NS.EnemyNativeHover and type(NS.EnemyNativeHover.Tick)=="function" then NS.EnemyNativeHover.Tick() end
        if NS.EnemyNativeTrial and type(NS.EnemyNativeTrial.Tick)=="function" then NS.EnemyNativeTrial.Tick(delta) end
        if NS.DB.shown and NS.RefreshTiles then NS.RefreshTiles() end
        if worldActive and NS.UpdateWorldIndicators then NS.UpdateWorldIndicators(delta) end
    end
    if rosterTick>=.5 then
        rosterTick=0
        if NS.DB.shown and not NS.InCombat() then NS.RequestRefresh() end
    end
    if probeTick>=1 then
        probeTick=0
        local module,d=NS.EnemyNativeHover,NS.Diagnostics
        if NS.DB.shown and module and type(module.ProbeReadback)=="function"
            and d and NS.Read(d.Enabled)==true and NS.Read(InCombatLockdown)==false then
            -- Run the passive observation in the addon's installed callback,
            -- independent from chat-created /run closures and the hit-test toggle.
            local tiles=NS.UI and NS.UI.enemy and NS.UI.enemy.tiles
            for i=1,math.min(20,tiles and #tiles or 0) do module.ProbeReadback(tiles[i]) end
        end
    end
end)
