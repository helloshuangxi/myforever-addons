local _, NS = ...
local cache={}
function NS.InvalidateQuestCache() cache={} end
local function publicTable(value)
    return NS.Public(value) and type(value)=="table"
end
local function ownQuest(id)
    if not NS.Number(id) or id<=0 or id%1~=0 then return false end
    local index=NS.Read(C_QuestLog and C_QuestLog.GetLogIndexForQuestID,id)
    return NS.Number(index) and index>0 and NS.Read(C_QuestLog and C_QuestLog.IsComplete,id)==false
end
local function cleanName(value)
    if not NS.Public(value) or type(value)~="string" then return "" end
    return value:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("^%s+",""):gsub("%s+$","")
end
local function inspect(unit)
    local tooltip=NS.Read(C_TooltipInfo and C_TooltipInfo.GetUnit,unit)
    if not publicTable(tooltip) or not publicTable(tooltip.lines) then return false end
    local types=Enum and Enum.TooltipDataLineType or {}
    local titleType,objectiveType,playerType=types.QuestTitle or 17,types.QuestObjective or 8,types.QuestPlayer or 18
    local ownName,realm=NS.Read(UnitName,"player")
    ownName=cleanName(ownName)
    local ownFull=ownName~="" and type(realm)=="string" and realm~="" and ownName.."-"..realm or ownName
    local id,title,active,mine=nil,nil,false,true
    for _,line in ipairs(tooltip.lines) do
        if publicTable(line) and NS.Number(line.type) then
            if line.type==titleType then
                id=line.questID
                active=ownQuest(id)
                title=NS.Text(line.leftText)
                mine=true
            elseif line.type==playerType then
                local owner=cleanName(line.leftText)
                mine=ownName~="" and (owner==ownName or owner==ownFull)
            elseif line.type==objectiveType and active and mine then
                local done=line.completed
                local fulfilled,required=line.numFulfilled,line.numRequired
                if NS.Public(done) and done~=true then
                    if done==false or (NS.Number(fulfilled) and NS.Number(required) and required>0 and fulfilled<required) then
                        return true,title
                    end
                end
            end
        else
            -- An unreadable boundary may belong to another quest or player.
            id,title,active,mine=nil,nil,false,false
        end
    end
    return false
end

function NS.IsQuestTarget(unit)
    if NS.Read(UnitExists,unit)~=true or NS.Read(UnitIsPlayer,unit)~=false
        or NS.Read(UnitCanAttack,"player",unit)~=true then return false end
    local guid=NS.Read(UnitGUID,unit)
    if type(guid)~="string" or guid=="" then return false end
    local now=NS.Read(GetTime)
    local previous=cache[guid]
    if previous and NS.Number(now) and now>=previous.time and now-previous.time<1 then return previous.value,previous.title end
    local ok,value,title=pcall(inspect,unit)
    if not ok then value,title=false,nil end
    if NS.Number(now) then cache[guid]={time=now,value=value,title=title} end
    return value,title
end
