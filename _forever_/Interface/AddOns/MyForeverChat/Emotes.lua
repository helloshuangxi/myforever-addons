local _,NS=...
NS.emotes={
    {key="smile",label="微笑"}, {key="laugh",label="大笑"}, {key="wink",label="眨眼"},
    {key="love",label="喜欢"}, {key="sad",label="难过"}, {key="cry",label="流泪"},
    {key="angry",label="生气"}, {key="surprise",label="惊讶"}, {key="cool",label="酷"},
    {key="sweat",label="汗"}, {key="sleep",label="困"}, {key="heart",label="爱心"},
}
for _,item in ipairs(NS.emotes) do
    item.token="["..item.label.."]"
    item.texture="Interface\\AddOns\\MyForeverChat\\Media\\Emotes\\"..item.key
end

local builtin={id="builtin",title="内置表情",items=NS.emotes}
local groups,byToken

local function public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function validID(value,minLength)
    return public(value) and type(value)=="string" and #value>=minLength and #value<=24
        and value:match("^[a-z0-9_]+$")~=nil
end

local function validLabel(value)
    if not public(value) or type(value)~="string" or #value>48 or not value:find("[^ ]")
        or value:find("[%z\1-\31\127|%[%]]") then return false end

    -- Reject truncated, overlong, surrogate, and out-of-range UTF-8 sequences.
    local remaining,low,high=0,0x80,0xBF
    for index=1,#value do
        local byte=value:byte(index)
        if remaining>0 then
            if byte<low or byte>high then return false end
            remaining,low,high=remaining-1,0x80,0xBF
        elseif byte>=0xC2 and byte<=0xDF then
            remaining=1
        elseif byte>=0xE0 and byte<=0xEF then
            remaining=2
            if byte==0xE0 then low=0xA0 end
            if byte==0xED then high=0x9F end
        elseif byte>=0xF0 and byte<=0xF4 then
            remaining=3
            if byte==0xF0 then low=0x90 end
            if byte==0xF4 then high=0x8F end
        elseif byte>=0x80 then
            return false
        end
    end
    return remaining==0
end

local function loadPack(registry,packID,tokens)
    local pack=rawget(registry,packID)
    if not public(pack) or type(pack)~="table" then return end
    local title,items=rawget(pack,"title"),rawget(pack,"items")
    if not validLabel(title) or not public(items) or type(items)~="table" then return end

    local group={id="pack:"..packID,title=title,items={}}
    local textureRoot="Interface\\AddOns\\MyForeverChatEmotes_"..packID.."\\Media\\"
    for index=1,48 do
        local entry=rawget(items,index)
        if public(entry) and type(entry)=="table" then
            local id,label=rawget(entry,"id"),rawget(entry,"label")
            if validID(id,1) and validLabel(label) then
                local token="[表情:"..packID..":"..id.."]"
                if not tokens[token] then
                    local item={key=id,label=label,token=token,texture=textureRoot..id}
                    group.items[#group.items+1]=item
                    tokens[token]=item
                end
            end
        end
    end
    if #group.items>0 then return group end
end

function NS.RefreshEmotePacks()
    local nextGroups,tokens={builtin},{}
    for _,item in ipairs(NS.emotes) do tokens[item.token]=item end

    local registry=MyForeverChatEmotePacks
    if public(registry) and type(registry)=="table" then
        local packIDs={}
        for packID in next,registry do
            if validID(packID,3) then packIDs[#packIDs+1]=packID end
        end
        table.sort(packIDs)
        for _,packID in ipairs(packIDs) do
            local group=loadPack(registry,packID,tokens)
            if group then nextGroups[#nextGroups+1]=group end
        end
    end
    groups,byToken=nextGroups,tokens
end

function NS.GetEmoteGroups() return groups end

function NS.FormatEmotes(text)
    return (text:gsub("%[[^%[%]\r\n]+%]",function(token)
        local item=byToken[token]
        if item then return "|T"..item.texture..":20:20|t" end
        return token
    end))
end

NS.RefreshEmotePacks()
