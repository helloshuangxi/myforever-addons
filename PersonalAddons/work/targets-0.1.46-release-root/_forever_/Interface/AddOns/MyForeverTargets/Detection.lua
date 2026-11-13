local _, NS = ...
local groups={{"nameplateShowFriendlyPlayers","nameplateShowFriends"},{"nameplateShowEnemies"},{"nameplateShowAll"}}
local allowed={nameplateShowFriendlyPlayers=true,nameplateShowFriends=true,nameplateShowEnemies=true,nameplateShowAll=true}
local function getter() return C_CVar and C_CVar.GetCVar or GetCVar end
local function setter() return C_CVar and C_CVar.SetCVar or SetCVar end
local function settingNames()
    local names={}
    for _,group in ipairs(groups) do
        for _,name in ipairs(group) do
            local value=NS.Read(getter(),name)
            if value=="0" or value=="1" then names[#names+1]=name;break end
        end
    end
    return names
end

function NS.DetectionStatus()
    local names=settingNames()
    if #names<3 then return false,"客户端姓名板开关不可用",false end
    for _,name in ipairs(names) do
        if NS.Read(getter(),name)~="1" then return false,"附近识别需要开启友方玩家与敌方姓名板",true end
    end
    return true,"附近识别已开启",true
end

function NS.SetDetectionEnabled(enabled,quiet)
    enabled=enabled==true
    if NS.InCombat() then
        NS.PendingDetection=enabled
        if not quiet then NS.Print("附近识别设置将在脱战后应用。") end
        return false
    end
    NS.DB.detectionRequested=enabled
    NS.DB.nameplateBackup=NS.DB.nameplateBackup or {}
    local backup=NS.DB.nameplateBackup
    if enabled then
        local names=settingNames()
        if #names<3 or type(setter())~="function" then
            if not quiet then NS.Print("客户端姓名板开关不可用，附近列表仅能显示已提供的单位。") end
            return false
        end
        local changed={}
        for _,name in ipairs(names) do
            local previous=NS.Read(getter(),name)
            if previous~="1" then
                changed[name]=previous
                if backup[name]==nil then backup[name]=previous end
                NS.Read(setter(),name,"1")
                if NS.Read(getter(),name)~="1" then
                    local rolledBack=true
                    for key,value in pairs(changed) do
                        NS.Read(setter(),key,value)
                        if NS.Read(getter(),key)==value then
                            if backup[key]==value then backup[key]=nil end
                        else rolledBack=false end
                    end
                    if not quiet then NS.Print(rolledBack and "姓名板设置未生效，已恢复本次修改。" or "姓名板设置未生效，未恢复的原设置已保留备份，可关闭附近识别重试。") end
                    return false
                end
            end
        end
        for name,value in pairs(changed) do if backup[name]==nil then backup[name]=value end end
    else
        local failed=false
        for name,value in pairs(backup) do
            if allowed[name] then
                local current=NS.Read(getter(),name)
                if current=="1" then
                    NS.Read(setter(),name,value)
                    if NS.Read(getter(),name)~=value then failed=true else backup[name]=nil end
                elseif current=="0" then backup[name]=nil
                else failed=true end
            else backup[name]=nil end
        end
        if failed then
            if not quiet then NS.Print("姓名板原设置未完全恢复，已保留备份，可再次关闭附近识别重试。") end
            return false
        end
    end
    if not quiet then NS.Print(enabled and "已开启附近识别所需的玩家和敌方姓名板，原设置已保存。" or "已恢复原姓名板设置。") end
    if NS.RequestRefresh then NS.RequestRefresh() end
    return true
end

local function validPlate(plate,guid)
    if not NS.Public(plate) or (type(plate)~="table" and type(plate)~="userdata") then return nil end
    local ok,unit=pcall(function()
        if NS.Read(plate.IsForbidden,plate)==true then return nil end
        return plate.namePlateUnitToken
    end)
    if ok and NS.ValidToken(unit) and NS.Read(UnitGUID,unit)==guid then return plate end
end

function NS.FindUnitNameplate(unit)
    local guid=NS.Read(UnitGUID,unit)
    if type(guid)~="string" or guid=="" then return nil end
    local direct=NS.Read(C_NamePlate and C_NamePlate.GetNamePlateForUnit,unit)
    local plate=validPlate(direct,guid)
    if plate then return plate end
    local plates=NS.Read(C_NamePlate and C_NamePlate.GetNamePlates)
    if type(plates)=="table" then
        for _,candidate in ipairs(plates) do
            plate=validPlate(candidate,guid)
            if plate then return plate end
        end
    end
end
