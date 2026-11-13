local addonName, NS = ...

local eventDefinitions = {
    PLAYER_REGEN_DISABLED="restrictions", PLAYER_REGEN_ENABLED="restrictions",
    UNIT_SPELLCAST_START="player_cast", UNIT_SPELLCAST_STOP="player_cast",
    UNIT_SPELLCAST_SUCCEEDED="player_cast", UNIT_SPELLCAST_FAILED="player_cast",
    UNIT_SPELLCAST_INTERRUPTED="player_cast", UNIT_SPELLCAST_CHANNEL_START="player_cast",
    UNIT_SPELLCAST_CHANNEL_STOP="player_cast", UNIT_POWER_UPDATE="power", UNIT_HEALTH="health",
    SPELL_UPDATE_COOLDOWN="cooldown", SPELLS_CHANGED="spells", UNIT_AURA="auras",
    PLAYER_XP_UPDATE="xp", PLAYER_LEVEL_UP="xp", QUEST_ACCEPTED="quests",
    QUEST_TURNED_IN="quests", QUEST_LOG_UPDATE="quests", ZONE_CHANGED_NEW_AREA="position",
    PLAYER_DEAD="health", PLAYER_ALIVE="health", PLAYER_UNGHOST="health",
    PLAYER_TARGET_CHANGED="target_cast", ADDON_RESTRICTION_STATE_CHANGED="restrictions",
}
NS.CaptureEventDefinitions = eventDefinitions
local throttleAt = {}
local spellCache, auraFingerprint, loggingState
-- Forever reserves this event for Blizzard UI. pcall does not suppress the
-- client's ADDON_ACTION_FORBIDDEN dialog, so never attempt its registration.
local registrationResults = { COMBAT_LOG_EVENT_UNFILTERED="disabled_restricted" }

local function MarkRestrictedCombatLog()
    if not NS.session then return end
    NS.session.registrations.COMBAT_LOG_EVENT_UNFILTERED="disabled_restricted"
    NS.session.registrationChecks.COMBAT_LOG_EVENT_UNFILTERED="disabled_restricted"
    local cap=NS.session.capabilities.combat_log
    cap.disabled=true
    cap.status="restricted"
    cap.lastStatus="restricted"
    cap.reason="restricted_event_disabled"
end

local function Enabled()
    return NS.session and NS.db and NS.db.settings.enabled and not NS.stopped and not NS.safetyStopped
end

local function FilterDisabled()
    if NS.stopped then NS.Filter("stopped")
    elseif NS.safetyStopped then NS.Filter("safety_stopped")
    else NS.Filter("paused") end
end

local function Track(key, field, status, value)
    local cap = NS.Observe(key,status,value)
    if cap then
        cap.fields = cap.fields or {}
        local entry = cap.fields[field] or { readable=0, restricted=0, missing=0, error=0, observed=0 }
        cap.fields[field] = entry
        if entry[status] ~= nil then entry[status] = entry[status] + 1 end
        entry.lastStatus = status
        entry.contexts=entry.contexts or {}
        local context=NS.GetContext()
        local counts=entry.contexts[context] or {readable=0,restricted=0,missing=0,error=0,observed=0}
        entry.contexts[context]=counts
        if counts[status]~=nil then counts[status]=counts[status]+1 end
    end
    return value
end

local function Scalar(key, field, func, parser, ...)
    local status, raw = NS.Try(func,...)
    local value
    if status == "ok" then value,status = parser(raw) end
    Track(key,field,status,value)
    return value,status
end

local function NumberField(key, field, source, name)
    local raw,status = NS.Field(source,name)
    local value
    if status == "ok" then value,status = NS.Number(raw) end
    Track(key,field,status,value)
    return value,status
end

local function BoolField(key, field, source, name)
    local raw,status = NS.Field(source,name)
    local value
    if status == "ok" then value,status = NS.Bool(raw) end
    Track(key,field,status,value)
    return value,status
end

local function NumberValue(key,field,raw)
    local value,status=NS.Number(raw)
    Track(key,field,status,value)
    return value,status
end

local function Due(key, seconds)
    local now = NS.Elapsed()
    local previous = throttleAt[key]
    if previous and now-previous < seconds then NS.Filter("throttled"); return false end
    throttleAt[key] = now
    return true
end

local function ReadPosition(snapshot)
    local api = C_Map and C_Map.GetBestMapForUnit
    local mapID = Scalar("position","mapID",api,NS.Number,"player")
    snapshot.mapID = mapID
    if not mapID then return end
    local status, point = NS.Try(C_Map and C_Map.GetPlayerMapPosition,mapID,"player")
    if status ~= "ok" then Track("position","coordinates",status); return end
    if NS.IsSecret(point) then Track("position","coordinates","restricted"); return end
    if point == nil then Track("position","coordinates","missing"); return end
    local callStatus,x,y = NS.Try(function() return point:GetXY() end)
    if callStatus ~= "ok" then Track("position","coordinates",callStatus); return end
    local xValue,xStatus = NS.Number(x)
    local yValue,yStatus = NS.Number(y)
    Track("position","x",xStatus,xValue)
    Track("position","y",yStatus,yValue)
    if xValue and xValue >= 0 and xValue <= 1 then snapshot.x=xValue end
    if yValue and yValue >= 0 and yValue <= 1 then snapshot.y=yValue end
end

local function ReadQuests(snapshot)
    local api = C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries
    local status,entries,count = NS.Try(api)
    if status ~= "ok" then Track("quests","questCount",status); return end
    local countValue,countStatus = NS.Number(count)
    local entryValue,entryStatus = NS.Number(entries)
    if entryStatus=="restricted" then Track("quests","entryCount",entryStatus) end
    if countValue then
        Track("quests","questCount",countStatus,countValue)
        snapshot.questCount=countValue
    else
        Track("quests","entryCount",entryStatus,entryValue)
        snapshot.questCount=entryValue
    end
    if not entryValue or not (C_QuestLog and C_QuestLog.GetInfo) then return end
    local questIDs = {}
    for index=1,math.min(80,math.max(0,math.floor(entryValue))) do
        local readStatus,info = NS.Try(C_QuestLog.GetInfo,index)
        if readStatus ~= "ok" then Track("quests","questID",readStatus); break end
        if NS.IsSecret(info) then Track("quests","questID","restricted"); break end
        if type(info)=="table" then
            local raw,fieldStatus = NS.Field(info,"questID")
            if fieldStatus == "ok" then
                local id,idStatus = NS.Number(raw)
                if id and id > 0 then questIDs[#questIDs+1]=id; Track("quests","questID",idStatus,id)
                elseif idStatus == "restricted" then Track("quests","questID",idStatus) end
            elseif fieldStatus == "restricted" then Track("quests","questID",fieldStatus) end
        end
        if #questIDs >= 40 then break end
    end
    snapshot.questIDs=questIDs
end

local function ReadSpells()
    if NS.GetContext() == "combat" or NS.inCombat then return spellCache or {} end
    if spellCache then return spellCache end
    spellCache={}
    local api=C_SpellBook
    if not api or not Enum or not Enum.SpellBookSpellBank or not Enum.SpellBookItemType then
        Track("spells","spellID","missing"); return spellCache
    end
    local status,lineCount=NS.Try(api.GetNumSpellBookSkillLines)
    if status ~= "ok" then Track("spells","spellID",status); return spellCache end
    local count,countStatus=NS.Number(lineCount)
    if not count then Track("spells","spellID",countStatus); return spellCache end
    local seen={}
    local bank=Enum.SpellBookSpellBank.Player
    for line=1,math.min(20,math.max(0,math.floor(count))) do
        local skillStatus,skill=NS.Try(api.GetSpellBookSkillLineInfo,line)
        if skillStatus ~= "ok" then Track("spells","spellID",skillStatus); break end
        if NS.IsSecret(skill) then Track("spells","spellID","restricted"); break end
        if type(skill)=="table" then
            local offsetRaw,offsetStatus=NS.Field(skill,"itemIndexOffset")
            local numberRaw,numberStatus=NS.Field(skill,"numSpellBookItems")
            local offSpecRaw,offSpecStatus=NS.Field(skill,"offSpecID")
            local offset=NS.Number(offsetRaw)
            local number=NS.Number(numberRaw)
            local offSpec=NS.Number(offSpecRaw)
            local metadataRestricted=offsetStatus=="restricted" or numberStatus=="restricted" or offSpecStatus=="restricted"
            if metadataRestricted then Track("spells","skillLine","restricted") end
            if offset and number and not metadataRestricted and (not offSpec or offSpec==0) then
                for slot=math.max(0,math.floor(offset))+1,math.max(0,math.floor(offset))+math.min(256,math.max(0,math.floor(number))) do
                    local itemStatus,info=NS.Try(api.GetSpellBookItemInfo,slot,bank)
                    if itemStatus ~= "ok" then Track("spells","spellID",itemStatus); break end
                    if NS.IsSecret(info) then Track("spells","spellID","restricted"); break end
                    if type(info)=="table" then
                        local raw,idFieldStatus=NS.Field(info,"spellID")
                        local id,idStatus
                        if idFieldStatus=="ok" then id,idStatus=NS.Number(raw) else idStatus=idFieldStatus end
                        local itemTypeRaw,itemTypeStatus=NS.Field(info,"itemType")
                        local itemType=NS.Number(itemTypeRaw)
                        local passiveRaw,passiveStatus=NS.Field(info,"isPassive")
                        local hiddenRaw,hiddenStatus=NS.Field(info,"isHidden")
                        local otherSpecRaw,otherSpecStatus=NS.Field(info,"isOffSpec")
                        local passive=NS.Bool(passiveRaw)
                        local hidden=NS.Bool(hiddenRaw)
                        local otherSpec=NS.Bool(otherSpecRaw)
                        local descriptorRestricted=itemTypeStatus=="restricted" or passiveStatus=="restricted"
                            or hiddenStatus=="restricted" or otherSpecStatus=="restricted"
                        if descriptorRestricted then Track("spells","descriptor","restricted") end
                        if id and itemType==Enum.SpellBookItemType.Spell and not descriptorRestricted
                            and not passive and not hidden and not otherSpec then
                            local knownStatus,known
                            if type(api.IsSpellKnown)=="function" then knownStatus,known=NS.Try(api.IsSpellKnown,id,bank)
                            else knownStatus,known=NS.Try(IsSpellKnown,id) end
                            local knownValue,knownValueStatus=NS.Bool(known)
                            known=knownValue
                            if knownValueStatus=="restricted" then Track("spells","known","restricted") end
                            if knownStatus=="ok" and known and not seen[id] then
                                spellCache[#spellCache+1]=id; seen[id]=true
                                Track("spells","spellID","readable",id)
                            end
                        elseif idStatus=="restricted" then Track("spells","spellID",idStatus) end
                    end
                    if #spellCache>=128 then break end
                end
            end
        end
        if #spellCache>=128 then break end
    end
    if #spellCache==0 then Track("spells","spellID","missing") end
    NS.Record("spells",{spellIDs=spellCache,numSpells=#spellCache})
    return spellCache
end

local function ReadCooldown()
    local spells=ReadSpells()
    local selected,seen={},{}
    local recent=NS.Number(NS.lastPlayerSpellID)
    if recent then selected[1]=recent; seen[recent]=true end
    for _,id in ipairs(spells) do
        if id~=6603 and id~=75 and id~=5019 and not seen[id] then
            selected[#selected+1]=id; seen[id]=true
        end
        if #selected>=3 then break end
    end
    if #selected==0 then Track("cooldown","spellID","missing"); return end
    for _,id in ipairs(selected) do
        local status,info=NS.Try(C_Spell and C_Spell.GetSpellCooldown,id)
        if status ~= "ok" then Track("cooldown","startTime",status)
        elseif NS.IsSecret(info) then Track("cooldown","startTime","restricted")
        elseif type(info)~="table" then Track("cooldown","startTime","missing")
        else
            local start=NumberField("cooldown","startTime",info,"startTime")
            local duration=NumberField("cooldown","duration",info,"duration")
            local enabled=BoolField("cooldown","isEnabled",info,"isEnabled")
            local rate=NumberField("cooldown","modRate",info,"modRate")
            if start~=nil or duration~=nil or enabled~=nil or rate~=nil then
                NS.Record("cooldown",{spellID=id,startTime=start,duration=duration,isEnabled=enabled,modRate=rate})
            end
        end
    end
end

local function ReadAuras()
    local api=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if type(api)~="function" then Track("auras","spellID","missing"); return end
    local ids={}
    local restricted=false
    for index=1,20 do
        local status,info=NS.Try(api,"player",index,"HELPFUL")
        if status~="ok" then Track("auras","spellID",status); break end
        if NS.IsSecret(info) then Track("auras","spellID","restricted"); restricted=true; break end
        if info==nil then break end
        local id,idStatus=NumberField("auras","spellID",info,"spellId")
        if idStatus=="restricted" then restricted=true end
        if not id then id,idStatus=NumberField("auras","spellID",info,"spellID") end
        if id then ids[#ids+1]=id end
        if idStatus=="restricted" then restricted=true end
    end
    if #ids==0 and not restricted then Track("auras","spellID","missing") end
    local fingerprint=table.concat(ids,",") .. (restricted and ":partial" or ":complete")
    if fingerprint~=auraFingerprint then
        auraFingerprint=fingerprint
        NS.Record("aura",{spellIDs=ids,auraCount=#ids})
    end
end

local function ReadTarget()
    local existsCall,rawExists=NS.Try(UnitExists,"target")
    local exists,existsStatus=NS.Bool(rawExists)
    if existsCall~="ok" then Track("target_cast","targetExists",existsCall); return end
    if existsStatus~="readable" then Track("target_cast","targetExists",existsStatus); return end
    Track("target_cast","targetExists","observed")
    if not exists then return end
    -- A readable existence flag is not a readable cast; only spellID is cast evidence.
    local status,_,_,_,startMS,endMS,_,_,notInterruptible,spellID=NS.Try(UnitCastingInfo,"target")
    if status~="ok" then Track("target_cast","spellID",status); return end
    local id,idStatus=NS.Number(spellID)
    if not id then
        local initialStatus=idStatus
        local channelStatus,_,_,_,channelStart,channelEnd,_,channelNotInterruptible,channelID=NS.Try(UnitChannelInfo,"target")
        if channelStatus=="ok" then
            id,idStatus=NS.Number(channelID)
            if id then startMS,endMS,notInterruptible=channelStart,channelEnd,channelNotInterruptible end
        elseif idStatus~="restricted" then idStatus=channelStatus end
        if not id and initialStatus=="restricted" then idStatus="restricted" end
    end
    Track("target_cast","spellID",idStatus,id)
    if id then
        local start,startStatus=NumberValue("target_cast","startTime",startMS)
        local finish,endStatus=NumberValue("target_cast","endTime",endMS)
        local blocked,blockedStatus=NS.Bool(notInterruptible)
        local interruptible
        if blocked~=nil then interruptible=not blocked end
        Track("target_cast","interruptible",blockedStatus,interruptible)
        local duration=start and finish and math.max(0,(finish-start)/1000)
        Track("target_cast","duration",duration and "readable"
            or (startStatus=="restricted" or endStatus=="restricted") and "restricted" or "missing",duration)
        NS.Record("target_cast",{spellID=id,startTime=start and start/1000,
            duration=duration,interruptible=interruptible})
    end
end

local function ReadRestrictions()
    local api=C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
    local values=Enum and Enum.AddOnRestrictionType
    if type(api)~="function" or type(values)~="table" then
        Track("restrictions","state","missing"); return
    end
    local names={"Combat","Encounter","ChallengeMode","PvPMatch","Map","Chat"}
    for _,name in ipairs(names) do
        local id=NS.Number(values[name])
        if id then
            local state=Scalar("restrictions",name,api,NS.Number,id)
            if state then
                NS.session.restrictionStates=NS.session.restrictionStates or {}
                NS.session.restrictionStates[name]=state
            end
        end
    end
end

local function ReadLogging()
    local logging,status=Scalar("combat_logging","logging",LoggingCombat,NS.Bool)
    if logging~=nil and logging~=loggingState then
        loggingState=logging
        NS.Record("logging",{logging=logging})
    end
    if C_CombatLog and C_CombatLog.IsCombatLogRestricted then
        local callStatus,raw=NS.Try(C_CombatLog.IsCombatLogRestricted)
        local restricted,restrictedStatus=NS.Bool(raw)
        if callStatus~="ok" then Track("combat_log","restrictionState",callStatus)
        elseif restrictedStatus~="readable" then Track("combat_log","restrictionState",restrictedStatus)
        else
            NS.session.combatLogRestricted=restricted
            if restricted then NS.Observe("combat_log","restricted") end
        end
    end
    return logging,status
end

local function RegisterApiPresence()
    if not NS.session then return end
    MarkRestrictedCombatLog()
    local apis={
        UnitHealth=UnitHealth,UnitPower=UnitPower,UnitCastingInfo=UnitCastingInfo,
        UnitChannelInfo=UnitChannelInfo,UnitXP=UnitXP,LoggingCombat=LoggingCombat,
        CombatLogGetCurrentEventInfo=CombatLogGetCurrentEventInfo,
        GetPlayerMapPosition=C_Map and C_Map.GetPlayerMapPosition,
        GetNumQuestLogEntries=C_QuestLog and C_QuestLog.GetNumQuestLogEntries or GetNumQuestLogEntries,
        GetSpellBookItemInfo=C_SpellBook and C_SpellBook.GetSpellBookItemInfo,
        GetSpellCooldown=C_Spell and C_Spell.GetSpellCooldown,
        GetAuraDataByIndex=C_UnitAuras and C_UnitAuras.GetAuraDataByIndex,
        GetAddOnRestrictionState=C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState,
    }
    local names={"UnitHealth","UnitPower","UnitCastingInfo","UnitChannelInfo","UnitXP","LoggingCombat",
        "CombatLogGetCurrentEventInfo","GetPlayerMapPosition","GetNumQuestLogEntries","GetSpellBookItemInfo",
        "GetSpellCooldown","GetAuraDataByIndex","GetAddOnRestrictionState"}
    for _,name in ipairs(names) do NS.session.apis[name]=type(apis[name])=="function" end
    local capApis={health="UnitHealth",power="UnitPower",position="GetPlayerMapPosition",xp="UnitXP",
        quests="GetNumQuestLogEntries",spells="GetSpellBookItemInfo",cooldown="GetSpellCooldown",
        auras="GetAuraDataByIndex",combat_log="CombatLogGetCurrentEventInfo",target_cast="UnitCastingInfo",
        restrictions="GetAddOnRestrictionState",combat_logging="LoggingCombat"}
    for key,apiName in pairs(capApis) do NS.session.capabilities[key].apiPresent=NS.session.apis[apiName] end
    NS.session.capabilities.player_cast.apiPresent=registrationResults.UNIT_SPELLCAST_SUCCEEDED=="registered"
    for event,result in pairs(registrationResults) do NS.session.registrations[event]=result end
end

function NS.Sample(reason)
    if not Enabled() then FilterDisabled(); return nil end
    local eventCombat=NS.Bool(NS.inCombat)
    local lockdownCall,rawLockdown=NS.Try(InCombatLockdown)
    local lockdown,lockdownStatus
    if lockdownCall=="ok" then lockdown,lockdownStatus=NS.Bool(rawLockdown)
    else lockdownStatus=lockdownCall end
    local affectingCall,rawAffecting=NS.Try(UnitAffectingCombat,"player")
    local affectingCombat,affectingStatus
    if affectingCall=="ok" then affectingCombat,affectingStatus=NS.Bool(rawAffecting)
    else affectingStatus=affectingCall end
    local publicCombat
    if affectingStatus=="readable" then publicCombat=affectingCombat
    elseif lockdownStatus=="readable" then publicCombat=lockdown end
    if publicCombat~=nil then
        if eventCombat~=nil and publicCombat~=eventCombat then NS.Filter("combat_state_mismatch") end
        NS.inCombat=publicCombat
    end
    local snapshot={reason=NS.Token(reason) or "manual",combat=NS.Bool(NS.inCombat),
        eventCombat=eventCombat,lockdown=lockdown,lockdownStatus=lockdownStatus,
        affectingCombat=affectingCombat,affectingStatus=affectingStatus}
    local _,rawLevel=NS.Try(UnitLevel,"player")
    snapshot.level=NS.Number(rawLevel)
    snapshot.health=Scalar("health","health",UnitHealth,NS.Number,"player")
    snapshot.healthMax=Scalar("health","healthMax",UnitHealthMax,NS.Number,"player")
    snapshot.power=Scalar("power","power",UnitPower,NS.Number,"player")
    snapshot.powerMax=Scalar("power","powerMax",UnitPowerMax,NS.Number,"player")
    snapshot.powerType=Scalar("power","powerType",UnitPowerType,NS.Number,"player")
    snapshot.xp=Scalar("xp","xp",UnitXP,NS.Number,"player")
    snapshot.xpMax=Scalar("xp","xpMax",UnitXPMax,NS.Number,"player")
    snapshot.rested=Scalar("xp","rested",GetXPExhaustion,NS.Number)
    ReadPosition(snapshot)
    ReadQuests(snapshot)
    ReadCooldown()
    ReadAuras()
    ReadTarget()
    ReadRestrictions()
    ReadLogging()
    NS.Record("snapshot",snapshot)
    NS.session.lastSnapshot=NS.CleanData(snapshot)
    return snapshot
end

function NS.RefreshCapabilities()
    RegisterApiPresence()
    if not NS.inCombat then spellCache=nil end
    return NS.Sample("manual_probe")
end

function NS.RegisterCaptureEvents(frame)
    MarkRestrictedCombatLog()
    for event,key in pairs(eventDefinitions) do
        local status=NS.Try(frame and frame.RegisterEvent,frame,event)
        registrationResults[event]=status=="ok" and "registered" or status
        if NS.session then
            NS.session.registrations[event]=registrationResults[event]
            local checkStatus,rawRegistered=NS.Try(frame and frame.IsEventRegistered,frame,event)
            local registered,registeredStatus=NS.Bool(rawRegistered)
            if checkStatus~="ok" then NS.session.registrationChecks[event]=checkStatus
            elseif registeredStatus~="readable" then NS.session.registrationChecks[event]="error"
            else NS.session.registrationChecks[event]=registered and "confirmed" or "not_registered" end
            if status~="ok" then NS.Observe(key,"error"); NS.Error("register_"..event) end
        end
    end
    return registrationResults
end

local function CountEvent(event)
    NS.session.eventCounts[event]=(NS.session.eventCounts[event] or 0)+1
end

local function PlayerCast(event,unit,_,spellID,castBarID)
    local unitValue,unitStatus=NS.Text(unit)
    if unitStatus=="restricted" then NS.Filter("unit_restricted"); NS.Observe("player_cast","restricted"); return end
    if unitStatus~="readable" then NS.Filter("unit_missing"); NS.Observe("player_cast","missing"); return end
    if unitValue=="target" then
        NS.Filter("other_unit")
        if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" then ReadTarget() end
        return
    end
    if unitValue~="player" then NS.Filter("other_unit"); return end
    CountEvent(event)
    NS.Observe("player_cast","observed")
    local id,status=NS.Number(spellID)
    Track("player_cast","spellID",status,id)
    if not id then
        NS.Filter(status=="restricted" and "spell_id_restricted" or "spell_id_missing")
        return
    end
    NS.lastPlayerSpellID=id
    NS.Record("player_cast",{event=event,spellID=id,castBarID=NS.Number(castBarID)})
end

function NS.HandleEvent(event,...)
    -- Keep lifecycle state current while paused without retaining any samples.
    if event=="PLAYER_REGEN_DISABLED" then NS.inCombat=true
    elseif event=="PLAYER_REGEN_ENABLED" then NS.inCombat=false end
    if not Enabled() then FilterDisabled(); return end
    if not eventDefinitions[event] then NS.Filter("unknown_event"); return end
    if event:find("^UNIT_SPELLCAST_") then PlayerCast(event,...); return end
    if event=="UNIT_HEALTH" or event=="UNIT_POWER_UPDATE" or event=="UNIT_AURA" then
        local unit,status=NS.Text((...))
        if status=="restricted" then NS.Filter("unit_restricted"); NS.Observe(eventDefinitions[event],"restricted"); return end
        if status~="readable" then NS.Filter("unit_missing"); return end
        if unit~="player" then NS.Filter("other_unit"); return end
    end
    CountEvent(event)
    if event=="PLAYER_REGEN_DISABLED" then
        NS.inCombat=true
        NS.Record("combat",{phase="enter",combat=true})
        NS.Sample("combat_enter")
    elseif event=="PLAYER_REGEN_ENABLED" then
        NS.inCombat=false
        NS.Record("combat",{phase="leave",combat=false})
        NS.Sample("combat_leave")
    elseif event=="ADDON_RESTRICTION_STATE_CHANGED" then
        local rawType,rawState=...
        local restrictionType,typeStatus=NS.Number(rawType)
        local restrictionState,stateStatus=NS.Number(rawState)
        Track("restrictions","eventType",typeStatus,restrictionType)
        Track("restrictions","eventState",stateStatus,restrictionState)
        if restrictionType and restrictionState then
            NS.Record("restriction",{restrictionType=restrictionType,restrictionState=restrictionState})
        end
        -- IsAddOnRestrictionActive is deliberately not queried in this callback.
    elseif event=="QUEST_ACCEPTED" then
        -- Forever's generated API declares a single questID, unlike legacy two-argument clients.
        local rawID=...
        local id,status=NS.Number(rawID)
        Track("quests","acceptedID",status,id)
        if id then NS.Record("quest",{event=event,questID=id}) end
    elseif event=="QUEST_TURNED_IN" then
        local rawID,rawXP,rawMoney=...
        local id,status=NS.Number(rawID)
        Track("quests","turnedInID",status,id)
        if id then NS.Record("quest",{event=event,questID=id,xpReward=NS.Number(rawXP),moneyReward=NS.Number(rawMoney)}) end
        NS.Sample("quest_turned_in")
    elseif event=="PLAYER_LEVEL_UP" then
        local level,status=NS.Number((...))
        Track("xp","levelUp",status,level)
        if level then NS.Record("level",{level=level}); NS.session.character.level=level end
        spellCache=nil
        NS.Sample("level_up")
    elseif event=="PLAYER_DEAD" or event=="PLAYER_ALIVE" or event=="PLAYER_UNGHOST" then
        NS.Record("death",{event=event,dead=event=="PLAYER_DEAD"})
        NS.Sample("life_state")
    elseif event=="PLAYER_TARGET_CHANGED" then
        ReadTarget()
    elseif event=="SPELLS_CHANGED" then
        spellCache=nil
        if Due("spells",1) then ReadSpells() end
    elseif event=="UNIT_AURA" then
        if Due("auras",1) then ReadAuras() end
    elseif event=="SPELL_UPDATE_COOLDOWN" then
        if Due("cooldown",1) then ReadCooldown() end
    elseif event=="UNIT_HEALTH" or event=="UNIT_POWER_UPDATE" then
        if Due("unit_snapshot",2) then NS.Sample("unit_update") end
    elseif event=="PLAYER_XP_UPDATE" or event=="QUEST_LOG_UPDATE" or event=="ZONE_CHANGED_NEW_AREA" then
        if Due(event,2) then NS.Sample(event) end
    end
end

function NS.ResetCaptureState()
    throttleAt={}
    spellCache,auraFingerprint,loggingState=nil,nil,nil
    NS.lastPlayerSpellID=nil
end
