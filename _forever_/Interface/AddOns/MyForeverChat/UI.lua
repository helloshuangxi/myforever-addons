local _, NS = ...
-- Shared layout hooks (grid while dragging, snap on release, /myui tags).
local function mfLayout(name, ...)
    local S = rawget(_G, "MyForeverStyle")
    local fn = type(S) == "table" and rawget(S, name)
    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        return ok and result or nil
    end
end
local panel, launcher, copyWindow, emoteWindow, actionWindow, clearToasts, notifications
local toastFrames={}
local toastPrevious,toastNext,toastPage
local TOAST_GAP=6
local dirty, rendering, displayedId
local pendingById={}
local failedById={}
local eventArgument=select
local render
local lastNotice
local lastIncoming
local openedCommunityThisShow
local conversationRows, messageRows = {}, {}
local surfaceFrames, fontStrings, editFields = {}, {}, {}
local appliedAppearance
local sidebarView="conversations"
local channelSettings,refreshChannelSettings
local C = {
    outer={0.055,0.067,0.072,0.98}, side={0.085,0.101,0.108,1},
    surface={0.12,0.14,0.15,1}, hover={0.16,0.20,0.20,1}, selected={0.16,0.27,0.24,1},
    green={0.42,0.82,0.58,1}, incoming={0.20,0.23,0.25,1},
    text={0.91,0.94,0.93,1}, muted={0.57,0.65,0.65,1}, dark={0.06,0.16,0.10,1},
    accentText={0.42,0.82,0.58,1}, incomingText={0.91,0.94,0.93,1},
}
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function options() return NS.db and NS.db.appearance or {fontSize=14,opacity=0.98} end
local function toastHeight()
    -- Reserve two full preview lines even at the largest chat font.
    return 74+2*math.max(0,options().fontSize-14)
end
local function toastStep() return toastHeight()+TOAST_GAP end
local function shade(f, color)
    f.appearanceColor=color
    local alpha=f.appearanceOpaque and math.max(0.94,options().opacity) or options().opacity
    f:SetBackdropColor(color[1],color[2],color[3],alpha)
    f:SetBackdropBorderColor(color[1],color[2],color[3],math.max(alpha,0.65))
end
local function registerSurface(f,color,opaque)
    if not f.appearanceRegistered then surfaceFrames[#surfaceFrames+1]=f; f.appearanceRegistered=true end
    f.appearanceOpaque=opaque
    shade(f,color)
end
local function updateFont(f)
    local face=f:GetFont()
    if face then f:SetFont(face,math.max(10,f.appearanceBaseSize+(f.chatFont and options().fontSize-14 or 0)),"") end
end
local function box(kind, parent, color, rounded)
    local f = CreateFrame(kind or "Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=rounded and "Interface\\Tooltips\\UI-Tooltip-Border" or nil,
        edgeSize=rounded and 8 or 0, insets={left=rounded and 3 or 0,right=rounded and 3 or 0,top=rounded and 3 or 0,bottom=rounded and 3 or 0}})
    registerSurface(f,color)
    return f
end
local function text(parent,size,color)
    local f=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    f.appearanceBaseSize=size; f.appearanceTextColor=color or C.text
    fontStrings[#fontStrings+1]=f; updateFont(f)
    f:SetTextColor(unpack(color==C.green and C.accentText or color or C.text)); f:SetJustifyH("LEFT"); f:SetJustifyV("TOP")
    return f
end
local function button(parent,caption,width,height,callback,color)
    local b=box("Button",parent,color or C.surface,true); b:SetSize(width,height)
    b.label=text(b,12,color==C.green and C.dark or C.text); b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER"); b.label:SetText(caption); b:SetScript("OnClick",callback)
    b:SetScript("OnEnter",function(self) if self:IsEnabled() then self:SetAlpha(0.82) end end)
    b:SetScript("OnLeave",function(self) if self:IsEnabled() then self:SetAlpha(1) end end)
    return b
end
local function field(parent,width,height)
    local e=CreateFrame("EditBox",nil,parent); e:SetSize(width,height); e:SetFontObject(ChatFontNormal)
    editFields[#editFields+1]=e
    local face=e:GetFont()
    if face then e:SetFont(face,14,"") end
    e:SetTextColor(unpack(C.text))
    e:SetAutoFocus(false); e:SetTextInsets(8,8,5,5)
    if NS.HandleShortcutKey then e:SetScript("OnKeyDown",NS.HandleShortcutKey) end
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusGained",function(self) if self.focusSurface then shade(self.focusSurface,C.hover) end end)
    e:SetScript("OnEditFocusLost",function(self) if self.focusSurface then shade(self.focusSurface,C.surface) end end)
    return e
end
local function luminance(c)
    local sum=0
    for i,weight in ipairs({0.2126,0.7152,0.0722}) do
        local v=c[i]; sum=sum+weight*(v<=0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4)
    end
    return sum
end
local function contrast(a,b)
    local one,two=luminance(a),luminance(b)
    return (math.max(one,two)+0.05)/(math.min(one,two)+0.05)
end
local function readable(color,background)
    if contrast(color,background)>=4.5 then return color end
    return luminance(background)>0.179 and {0,0,0,1} or {1,1,1,1}
end
local function blend(a,b,amount)
    return {a[1]+(b[1]-a[1])*amount,a[2]+(b[2]-a[2])*amount,a[3]+(b[3]-a[3])*amount}
end
local chatStyles = {
    GUILD={label="公会",color={0.30,0.82,0.45,1}},
    PARTY={label="小队",color={0.38,0.62,1.00,1}},
    RAID={label="团队",color={1.00,0.58,0.22,1}},
    INSTANCE_CHAT={label="副本",color={0.26,0.83,0.74,1}},
    WHISPER={label="私聊",color={0.88,0.50,0.91,1}},
    BN_WHISPER={label="通行证",color={0.31,0.79,1.00,1}},
    SAY={label="附近",color={0.76,0.80,0.82,1}},
    YELL={label="喊话",color={1.00,0.36,0.34,1}},
    CHANNEL={label="频道",color={0.89,0.74,0.40,1}},
    COMMUNITIES_CHANNEL={label="群聊",color={0.64,0.65,1.00,1}},
}
local kindChatTypes={guild="GUILD",group="PARTY",raid="RAID",whisper="WHISPER",bnet="BN_WHISPER",say="SAY",channel="CHANNEL",club="COMMUNITIES_CHANNEL"}
local function chatStyle(conversation,message)
    local kind=message and message.chatType
    if not public(kind) or type(kind)~="string" then kind=nil end
    if kind then kind=kind:gsub("_LEADER$",""):gsub("_INFORM$","") end
    return chatStyles[kind] or chatStyles[kindChatTypes[conversation.kind]] or chatStyles.SAY
end
local function typeShade(conversation,message,outgoing)
    local style=chatStyle(conversation,message)
    return blend(C.surface,style.color,outgoing and 0.48 or 0.20),style
end
local function setTypeStripe(frame,color)
    if not frame.typeStripe then
        frame.typeStripe=box("Frame",frame,color,false)
        frame.typeStripe:SetWidth(3)
        frame.typeStripe:SetPoint("TOPLEFT",2,-3); frame.typeStripe:SetPoint("BOTTOMLEFT",2,3)
    end
    shade(frame.typeStripe,color)
end
local function assign(destination,color)
    for i=1,3 do destination[i]=color[i] end
    destination[4]=1
end
function NS.ApplyAppearance()
    if not NS.db or not NS.db.appearance then return end
    local setting=NS.db.appearance
    appliedAppearance=setting
    local background,accent=setting.background,setting.accent
    local light=luminance(background)>0.35
    local edge=light and {0,0,0} or {1,1,1}
    assign(C.outer,background); assign(C.side,blend(background,edge,0.035))
    assign(C.surface,blend(background,edge,0.07)); assign(C.incoming,blend(background,edge,0.16))
    assign(C.hover,blend(background,accent,0.18)); assign(C.selected,blend(background,accent,0.26))
    assign(C.green,accent)
    assign(C.text,light and {0.06,0.08,0.09} or {0.91,0.94,0.93})
    if contrast(C.text,background)<4.5 then assign(C.text,luminance(background)>0.179 and {0,0,0} or {1,1,1}) end
    assign(C.muted,light and {0.22,0.27,0.28} or {0.57,0.65,0.65})
    if contrast(C.muted,background)<4.5 then assign(C.muted,C.text) end
    assign(C.dark,{0.06,0.16,0.10})
    if contrast(C.dark,accent)<4.5 then assign(C.dark,luminance(accent)>0.179 and {0,0,0} or {1,1,1}) end
    assign(C.accentText,contrast(C.green,background)>=4.5 and C.green or C.text)
    assign(C.incomingText,contrast(C.text,C.incoming)>=4.5 and C.text or (luminance(C.incoming)>0.179 and {0,0,0} or {1,1,1}))
    for _,f in ipairs(surfaceFrames) do shade(f,f.appearanceColor) end
    for _,f in ipairs(fontStrings) do
        updateFont(f)
        local color=f.appearanceTextColor
        if color==C.green and contrast(C.green,background)<4.5 then color=C.text end
        f:SetTextColor(unpack(color))
    end
    for _,e in ipairs(editFields) do
        local face=e:GetFont()
        if face then e:SetFont(face,e.chatFont and setting.fontSize or 14,"") end
        e:SetTextColor(unpack(e.appearanceFixedTextColor or C.text))
    end
    if panel and panel.editor then panel.editor:SetHeight(math.max(52,setting.fontSize*2+10)) end
    dirty=true
    if NS.SyncAppearanceSettings then NS.SyncAppearanceSettings() end
end
local function short(value,chars)
    local offset,count=1,0
    while offset<=#value and count<chars do
        local byte=value:byte(offset)
        offset=offset+(byte<128 and 1 or (byte<224 and 2 or (byte<240 and 3 or 4))); count=count+1
    end
    return value:sub(1,offset-1)
end
local conversationLetters={group="队",raid="团",guild="会",say="近",club="群"}
local function conversationLetter(entry)
    if entry.kind=="channel" then
        if entry.channelCommunity then return "旧" end
        local name=entry.channelBaseName or entry.title or entry.target or "频道"
        if name:find("^副本") then return "本" end
        if name:find("^寻求组队") then return "组" end
        return short(name,1)
    end
    return conversationLetters[entry.kind] or "聊"
end
local function profileLabel(conv)
    local p=conv.profile or {}
    local parts={}
    if p.level then parts[#parts+1]=p.level.."级" end
    if p.className then parts[#parts+1]=p.className end
    if p.raceName then parts[#parts+1]=p.raceName end
    return #parts>0 and table.concat(parts," · ") or "资料待更新"
end
local function isPerson(entry)
    return entry and (entry.kind=="whisper" or entry.kind=="bnet")
end
local function communityMembers(entry)
    return entry.memberCount and (entry.memberCount.." 人") or "人数待更新"
end
local function senderDetails(message)
    local profile=message.profile or {}
    local details={}
    if profile.level then details[#details+1]=profile.level.."级" end
    if profile.className then details[#details+1]=profile.className end
    return table.concat(details," · ")
end
local function messageContact(conversation,message)
    if isPerson(conversation) then return conversation end
    if conversation.kind=="club" and message.communityAuthorKnown~=true then return nil end
    return {id="whisper:"..message.author:lower(),kind="whisper",title=message.author,target=message.author,profile=message.profile or {}}
end
local function showSenderTooltip(widget,message)
    if not message then return end
    GameTooltip:SetOwner(widget,"ANCHOR_TOP")
    local details=senderDetails(message)
    GameTooltip:SetText(message.author..(details~="" and "\n"..details or "")); GameTooltip:Show()
end
local presenceLabels={online="在线",offline="离线",unknown="在线状态未知"}
local function avatarState(holder,letter,conv,presence)
    if not holder.presenceBadge then
        holder.presenceBadge=holder:CreateTexture(nil,"OVERLAY",nil,7)
        holder.presenceBadge:SetSize(15,15); holder.presenceBadge:SetPoint("BOTTOMRIGHT",2,-2)
        holder.muteBadge=holder:CreateTexture(nil,"OVERLAY",nil,7)
        holder.muteBadge:SetSize(15,15); holder.muteBadge:SetPoint("TOPRIGHT",2,2)
        holder.muteBadge:SetTexture("Interface\\AddOns\\MyForeverChat\\Media\\Presence\\muted")
    end
    local status=isPerson(conv) and (presence or conv.presence or NS.GetContactPresence(conv))
    if status then
        holder.presenceBadge:SetTexture("Interface\\AddOns\\MyForeverChat\\Media\\Presence\\"..status)
    end
    holder.presenceBadge:SetShown(status~=nil and status~=false)
    holder.muteBadge:SetShown(conv~=nil and conv.muted==true)
    if holder.portrait and holder.portrait.SetDesaturated then holder.portrait:SetDesaturated(status=="offline") end
    letter:SetAlpha(status=="offline" and 0.68 or 1)
end
local function portrait(holder,letter,conv,selfPortrait)
    if not holder.portrait then
        holder.portrait=holder:CreateTexture(nil,"ARTWORK")
        holder.portrait:SetPoint("TOPLEFT",2,-2); holder.portrait:SetPoint("BOTTOMRIGHT",-2,2)
    end
    local texture=holder.portrait
    local unit=selfPortrait and "player" or (conv and NS.ResolvePortraitUnit(conv))
    if unit and type(SetPortraitTexture)=="function" then
        texture:SetTexCoord(0,1,0,1)
        local ok=pcall(SetPortraitTexture,texture,unit)
        if ok then texture:Show(); letter:Hide(); return end
    end
    local coords=conv and conv.profile and NS.ClassIconCoords(conv.profile.classToken)
    if coords then
        texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        texture:SetTexCoord(unpack(coords)); texture:Show(); letter:Hide()
    else texture:Hide(); letter:Show() end
end
local tooltipLinks={item=true,spell=true,quest=true,achievement=true,enchant=true,talent=true,currency=true,keystone=true}
-- Shareable game data links. Local UI action links are not chat content.
local gameLinks={
    player=true,trade=true,worldmap=true,battlepet=true,battlePetAbil=true,instancelock=true,journal=true,
    talentbuild=true,transmogappearance=true,transmogillusion=true,transmogset=true,customset=true,
    garrfollower=true,garrfollowerability=true,garrmission=true,azessence=true,dungeonScore=true,pvpRating=true,
    worldquest=true,eventpoi=true,housingdecor=true,housingblueprint=true,
}
local colorCode="|c%x%x%x%x%x%x%x%x"
local function stripMarkup(value)
    return (value:gsub("|T[^|]*|t",""):gsub("|A[^|]*|a",""):gsub(colorCode,"")
        :gsub("|cn[%w_]+:",""):gsub("|r",""):gsub("|","||"):gsub("\1","||"))
end
local function displayLinkColor(color,background)
    if color and color:sub(3,4):lower()=="ff" then
        local rgb={tonumber(color:sub(5,6),16)/255,tonumber(color:sub(7,8),16)/255,tonumber(color:sub(9,10),16)/255}
        if contrast(rgb,background)>=4.5 then return color end
    end
    local blue=luminance(background)>0.179 and {0.05,0.18,0.46} or {0.62,0.83,1}
    local r,g,b=unpack(readable(blue,background))
    return ("|cff%02x%02x%02x"):format(r*255+0.5,g*255+0.5,b*255+0.5)
end
local function clean(value,plain,background)
    if not public(value) or type(value)~="string" then return "[此消息暂不可显示]" end
    if not value:find("|",1,true) then return plain and value or NS.FormatEmotes(value) end
    -- Keep escaped pipes out of the markup parser so literal ||H text stays literal.
    value=value:gsub("\1",""):gsub("||","\1")
    local parts,links,offset={},{},1
    local function appendText(chunk)
        local stripped=stripMarkup(chunk)
        parts[#parts+1]=plain and stripped or NS.FormatEmotes(stripped)
    end
    for start,link,caption,after in value:gmatch("()|H([^|%z\1-\31\127]+)|h(.-)|h()") do
        local prefix=value:sub(offset,start-1)
        appendText(prefix)
        local kind=link:match("^([^:]+):.+$")
        if not plain and (tooltipLinks[kind] or gameLinks[kind]) then
            local token="|H"..link.."|h"..stripMarkup(caption).."|h"
            local color=prefix:match("("..colorCode..")$")
            links[link]=links[link] or (color and color..token.."|r" or token)
            if background then color=displayLinkColor(color,background) end
            parts[#parts+1]=color and color..token.."|r" or token
        else
            appendText(caption)
        end
        offset=after
    end
    appendText(value:sub(offset))
    return table.concat(parts),links
end
NS.DisplayText=clean
local function nativeCommunityContent(conversation,message)
    if conversation and conversation.kind=="club" and NS.Communities and NS.Communities.NativeContent then
        return NS.Communities.NativeContent(message)
    end
end
local function messagePreview(conversation,message,limit)
    -- Kstring handles must reach the game's renderer whole, without escaping
    -- pipes or truncating the handle. Only freshly validated community content
    -- is eligible; ordinary chat continues through the existing sanitizer.
    return nativeCommunityContent(conversation,message)
        or short(clean(message.text,true):gsub("[\r\n]"," "),limit)
end
local function status(message,good)
    if panel then panel.status:SetText(message or ""); panel.status:SetTextColor(unpack(good and C.accentText or C.muted)) end
end
local function current() return NS.GetSelected() end
function NS.GetNativeItemLinkTarget()
    if not panel or not panel:IsShown() or not panel.editor:HasFocus() then return end
    local selected=current()
    if selected and selected.id==displayedId then return selected.id end
end
function NS.InsertNativeItemLink(link)
    if not NS.GetNativeItemLinkTarget() or not public(link) or type(link)~="string" then return false end
    if #panel.editor:GetText()+#link>NS.CHAT_DRAFT_BYTES then
        status("草稿空间不足，请先发送或缩短现有文字，再插入物品链接。")
        return true
    end
    panel.editor:Insert(link)
    return true
end
local function contactPresence(conv)
    if not isPerson(conv) or type(NS.GetContactPresence)~="function" then return "unknown" end
    local ok,value=pcall(NS.GetContactPresence,conv)
    if ok and public(value) and (value=="online" or value=="offline") then return value end
    return "unknown"
end
local function updateDeliveryNotice(conv,presence,pending,failed)
    if not panel.deliveryNotice then return end
    local club=conv and conv.kind=="club"
    local unavailable=club and conv.available~=true
    local show=(isPerson(conv) and (presence~="online" or pending~=nil or failed~=nil))
        or (club and (pending~=nil or failed~=nil or unavailable))
    panel.deliveryNotice:SetShown(show)
    panel.history:SetPoint("BOTTOMRIGHT",-12,show and 202 or 148)
    panel.bottom:SetPoint("BOTTOMRIGHT",-22,show and 209 or 155)
    if not show then return end
    local title,detail,color,background
    local warning={1,0.76,0.36,1}
    local danger={1,0.60,0.53,1}
    if failed then
        title=failed.failureTitle
        detail=failed.failureDetail
        color=failed.failureKind=="offline" and danger or warning
        background={0.23,0.12,0.09,1}
    elseif unavailable then
        title="群频道暂不可用 · 草稿已保留"
        detail="可查看本机记录；请刷新群聊或在原生社区中确认成员资格。"
        color=warning; background={0.20,0.16,0.08,1}
    elseif presence=="offline" then
        title="对方离线 · 暂时无法发送"
        detail="可以查看记录、编辑草稿；对方上线后再发送。"
        color=danger; background={0.23,0.10,0.09,1}
    elseif pending then
        title="正在发送 · 等待游戏确认"
        detail="请勿重复发送；草稿在游戏确认后才会清空。"
        color={0.55,0.86,1,1}; background={0.08,0.16,0.22,1}
    else
        title="在线状态未知"
        detail="打开会话不代表对方在线；发送后请等待游戏确认。"
        color=warning; background={0.20,0.16,0.08,1}
    end
    shade(panel.deliveryNotice,background)
    panel.deliveryTitle:SetText(title); panel.deliveryTitle:SetTextColor(unpack(color))
    panel.deliveryDetail:SetText(detail); panel.deliveryDetail:SetTextColor(0.94,0.94,0.91,1)
    local retry=failed~=nil or presence=="offline" or unavailable
    panel.retrySend:SetShown(retry)
    panel.retrySend:SetEnabled(not pending)
    panel.retrySend.label:SetText(failed and failed.failureKind=="timeout" and "允许重试" or "重新检查")
    local width=panel:GetWidth()-247
    panel.deliveryTitle:SetWidth(width-(retry and 124 or 24))
    panel.deliveryDetail:SetWidth(width-(retry and 124 or 24))
end
local function updateComposer()
    if not panel or not panel.send then return end
    local content=panel.editor:GetText() or ""
    local visible,hidden=NS.ChatMessageBytes(content)
    local overLimit=visible>NS.CHAT_VISIBLE_BYTES or hidden>NS.CHAT_LINK_BYTES
    panel.counter:SetText(visible.."/"..NS.CHAT_VISIBLE_BYTES.." 字节 · Enter 发送")
    panel.counter:SetTextColor(unpack(overLimit and {1,0.48,0.44,1} or C.muted))
    local valid=NS.ValidateText(content)
    local selected=current()
    local pending=selected and pendingById[selected.id]
    local failed=selected and failedById[selected.id]
    local presence=contactPresence(selected)
    local unavailable=selected and selected.kind=="club" and selected.available~=true
    local legacyCommunity=selected and selected.kind=="channel" and selected.channelCommunity
    local allowed=valid~=nil and not pending and not failed and presence~="offline" and not unavailable and not legacyCommunity and not (selected and selected.channelArchive)
    panel.send:SetEnabled(allowed); panel.send:SetAlpha(allowed and 1 or 0.45)
    panel.send.label:SetText(legacyCommunity and "请用群聊" or selected and selected.channelArchive and "旧草稿" or pending and "发送中" or (failed or presence=="offline" or unavailable) and "暂不可发" or "发送")
    if legacyCommunity then panel.counter:SetText(visible.."/"..NS.CHAT_VISIBLE_BYTES.." 字节 · 草稿保留") end
    if isPerson(selected) and (failed or presence=="offline") then
        panel.counter:SetText(visible.."/"..NS.CHAT_VISIBLE_BYTES.." 字节 · 草稿保留")
    end
    updateDeliveryNotice(selected,presence,pending,failed)
end
local function checkEcho()
    for _,states in ipairs({pendingById,failedById}) do
    for id,pending in pairs(states) do
        local conv=NS.db.conversations[id]
        if not conv or conv.kind=="club" then states[id]=nil
        else
            local afterFailure=true
            for i=#conv.messages,1,-1 do
                local msg=conv.messages[i]
                if msg==pending.previousLast then break end
                if msg==pending.failedAfterMessage then afterFailure=false end
                if msg.outgoing and msg.text==pending.text then
                    if conv.draft==pending.original then conv.draft="" end
                    if displayedId==id and panel.editor:GetText()==pending.original then panel.editor:SetText("") end
                    states[id]=nil
                    if displayedId==id then status("已发送。",true) end
                    break
                elseif states==failedById and pending.failureKind=="offline" and afterFailure and not msg.outgoing and isPerson(conv) then
                    states[id]=nil
                    if displayedId==id then status("已收到对方消息，可以继续发送；草稿已保留。",true) end
                    break
                end
            end
            if states==failedById and states[id] and pending.failureKind=="offline" then
                local presence=contactPresence(conv)
                if presence=="offline" then pending.observedOffline=true end
                if presence=="online" and (pending.failedPresence~="online" or pending.observedOffline) then states[id]=nil end
            end
        end
    end
    end
    updateComposer()
end
local function failPending(id,kind,title,detail)
    local token=pendingById[id]
    if not token then return false end
    pendingById[id]=nil; failedById[id]=token
    token.failureKind,token.failureTitle,token.failureDetail=kind,title,detail
    local conv=NS.db.conversations[id]
    token.failedPresence=contactPresence(conv)
    token.failedAfterMessage=conv and conv.messages[#conv.messages]
    if displayedId==id then status(title.."；草稿已保留。") end
    updateComposer()
    return true
end
local function send()
    local conv=current(); if not conv then return end
    if conv.kind=="channel" and conv.channelCommunity then
        updateComposer(); status("这是旧群频道记录；请复制草稿到“群聊”中的对应会话发送。")
        return
    end
    if pendingById[conv.id] then return end
    if failedById[conv.id] then updateComposer(); status("尚未发送，请先查看输入区上方的提示；草稿已保留。"); return end
    if isPerson(conv) and contactPresence(conv)=="offline" then
        updateComposer(); status("对方离线，消息未发送。草稿已保留。"); return
    end
    if displayedId~=conv.id then
        if render then render() end
        status("会话已切换，请确认当前输入内容后再发送。")
        return
    end
    local original=panel.editor:GetText(); local content,err=NS.ValidateText(original)
    if not content then status(err); return end
    if conv.kind=="club" then
        local ok,message=NS.Send(content)
        if ok then
            if conv.draft==original then conv.draft="" end
            if displayedId==conv.id and panel.editor:GetText()==original then panel.editor:SetText("") end
            if render then render() end
            status("已提交，投递由游戏处理；可用“找回上次发送”恢复内容。",true)
        else
            updateComposer(); status(message)
        end
        return
    end
    local token={id=conv.id,text=content,original=original,previousLast=conv.messages[#conv.messages]}
    if conv.kind=="bnet" and NS.GetBattleNetContact then
        local friend=NS.GetBattleNetContact(conv.target)
        if friend and public(friend.accountID) and type(friend.accountID)=="number" then token.accountID=friend.accountID end
    end
    pendingById[conv.id]=token; updateComposer()
    local ok,message=NS.Send(content)
    if not ok then pendingById[conv.id]=nil; updateComposer(); status(message); return end
    if pendingById[conv.id]==token then
        status("正在发送，文字会在游戏确认后清空。")
        C_Timer.After(8,function()
            if pendingById[token.id]==token then
                local target=NS.db.conversations[token.id]
                if isPerson(target) then
                    failPending(token.id,"timeout","尚未确认送达 · 已保留草稿","重试可能造成重复消息；如需重发，先点“允许重试”。")
                    return
                end
                pendingById[token.id]=nil; updateComposer()
                if displayedId==token.id then status("尚未确认送达，文字已保留。请查看游戏提示后再决定是否重发。") end
            end
        end)
    end
end
local function savePosition()
    local point,_,relativePoint,x,y=panel:GetPoint()
    NS.db.window={point=point,relativePoint=relativePoint,x=x,y=y,width=panel:GetWidth(),height=panel:GetHeight()}
end
local function followCursor(scroll,_,y,_,height)
    local top=math.max(0,-y)
    local offset=scroll:GetVerticalScroll()
    if top<offset then scroll:SetVerticalScroll(top)
    elseif top+height>offset+scroll:GetHeight() then
        scroll:SetVerticalScroll(math.max(0,top+height-scroll:GetHeight()))
    end
end
local function showCopy(value,nativeContent)
    if not copyWindow then
        copyWindow=CreateFrame("Frame","MyForeverChatCopy",panel,"BasicFrameTemplateWithInset")
        copyWindow:SetSize(500,220); copyWindow:SetPoint("CENTER"); copyWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        copyWindow:EnableMouse(true)
        copyWindow.TitleText:SetText("复制消息 · Ctrl/Cmd+C")
        local scroll=CreateFrame("ScrollFrame",nil,copyWindow,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-40); scroll:SetSize(440,150)
        copyWindow.edit=field(scroll,430,150); copyWindow.edit:SetMultiLine(true); scroll:SetScrollChild(copyWindow.edit)
        copyWindow.edit.chatFont=true
        local copyFace=copyWindow.edit:GetFont()
        if copyFace then copyWindow.edit:SetFont(copyFace,options().fontSize,"") end
        copyWindow.edit.appearanceFixedTextColor={0.91,0.94,0.93,1}
        copyWindow.edit:SetTextColor(unpack(copyWindow.edit.appearanceFixedTextColor))
        copyWindow.edit:SetScript("OnCursorChanged",function(_,x,y,w,h) followCursor(scroll,x,y,w,h) end)
        UISpecialFrames[#UISpecialFrames+1]="MyForeverChatCopy"
    end
    copyWindow.TitleText:SetText(nativeContent and "受保护的群消息" or "复制消息 · Ctrl/Cmd+C")
    copyWindow.edit:SetText(nativeContent and "这条群消息由游戏保护。请点“原生社区”查看，并使用游戏提供的复制方式。" or clean(value,true))
    copyWindow:Show(); copyWindow.edit:SetFocus(); copyWindow.edit:HighlightText()
end
local function switchSidebar(view)
    if sidebarView==view then return end
    sidebarView=view
    panel.search:SetText("")
    panel.contacts:SetVerticalScroll(0)
    dirty=true
end
local function openNativeCommunity(id)
    if not (NS.Communities and NS.Communities.OpenNative) then status("请按 J 打开原生公会与社区。"); return end
    local ok,note=NS.Communities.OpenNative(id)
    if note then status(note) end
    if ok then NS.MinimizeUI() end
end
local function inviteCommunityFriend()
    local conv=current()
    if not conv or conv.kind~="club" then return end
    if not (NS.Communities and NS.Communities.OpenInvite) then
        status("邀请入口暂不可用，请点“原生社区”后选择“邀请成员”。")
        return
    end
    local ok,note=NS.Communities.OpenInvite(conv.id)
    if note then status(note) end
    if ok then NS.MinimizeUI() end
end
local function openSelectedCommunity()
    local conv=current()
    if not conv or conv.kind~="club" or openedCommunityThisShow==conv
        or not (NS.Communities and NS.Communities.Open) then return end
    -- Opening can synchronously refresh the UI. Mark it first, and never put
    -- history requests in render(), which runs again for edits and redraws.
    openedCommunityThisShow=conv
    local _,note=NS.Communities.Open(conv.id)
    if note then status(note) end
end
local function refreshCommunity(id)
    if not NS.Communities then status("群聊接口尚未就绪，请稍后重试。"); return end
    local result,note
    if id then result,note=NS.Communities.Open(id) else result,note=NS.Communities.Refresh() end
    if render then render() end
    if note then status(note) end
end
local function select(id)
    if copyWindow then copyWindow:Hide() end
    if emoteWindow then emoteWindow:Hide() end
    if actionWindow then actionWindow:Hide() end
    local entry=NS.Select(id)
    local note,opened,result
    if not entry and NS.Communities and NS.Communities.GetEntry(id) then
        result,note=NS.Communities.Open(id); opened=true; entry=NS.Select(id)
    end
    if entry then
        switchSidebar(entry.kind=="club" and "clubs" or "conversations")
        if entry.kind=="club" then
            if not opened and NS.Communities then result,note=NS.Communities.Open(id) end
        elseif isPerson(entry) then NS.db.peopleCollapsed=false else NS.db.channelsCollapsed=false end
        if notifications then notifications:DismissConversation(id) end
    end
    displayedId=nil; dirty=true
    if render then render() end
    if note then status(note) end
end
function NS.ChannelConversationMigrated(oldID,newID)
    if oldID==newID then return end
    if pendingById[oldID] and not pendingById[newID] then
        local token=pendingById[oldID]
        local conv=NS.db.conversations[newID]
        pendingById[newID]=token; token.id=newID
        -- Imported old history is not a new native send confirmation.
        if conv then token.previousLast=conv.messages[#conv.messages] end
    end
    if failedById[oldID] and not failedById[newID] then failedById[newID]=failedById[oldID]; failedById[newID].id=newID end
    pendingById[oldID],failedById[oldID]=nil,nil
    if displayedId==oldID then displayedId=nil end
    if notifications then notifications:DismissConversation(oldID) end
end
local function showEmotes()
    if actionWindow then actionWindow:Hide() end
    if emoteWindow and emoteWindow:IsShown() then emoteWindow:Hide(); return end
    if not emoteWindow then
        local menu=CreateFrame("Frame","MyForeverChatEmotes",panel,"BackdropTemplate")
        menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        menu:SetSize(384,220); menu:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",240,142)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:EnableMouse(true)
        registerSurface(menu,C.side,true)
        local heading=text(menu,12,C.text); heading:SetPoint("TOPLEFT",12,-11); heading:SetText("选择表情")
        button(menu,"×",24,22,function() menu:Hide() end):SetPoint("TOPRIGHT",-5,-5)
        local groupTitle=text(menu,12,C.text); groupTitle:SetPoint("TOP",0,-40)
        local pageLabel=text(menu,11,C.muted); pageLabel:SetPoint("BOTTOM",0,15)
        local groupID,page,perPage="builtin",1,12
        local previousGroup,nextGroup,previousPage,nextPage
        menu.buttons={}
        local function refresh(groupStep)
            local groups=NS.GetEmoteGroups()
            local index=1
            for i,group in ipairs(groups) do if group.id==groupID then index=i; break end end
            index=math.max(1,math.min(#groups,index+(groupStep or 0)))
            local group=groups[index]
            if group.id~=groupID then groupID,page=group.id,1 end
            local pages=math.max(1,math.ceil(#group.items/perPage))
            page=math.max(1,math.min(page,pages))
            groupTitle:SetText(short(group.title,19).."  "..index.."/"..#groups)
            previousGroup:SetEnabled(index>1); nextGroup:SetEnabled(index<#groups)
            previousPage:SetEnabled(page>1); nextPage:SetEnabled(page<pages)
            for _,control in ipairs({previousGroup,nextGroup,previousPage,nextPage}) do
                control:SetAlpha(control:IsEnabled() and 1 or 0.45)
            end
            pageLabel:SetText(#groups==1 and "可用制作器添加表情包" or ("第 "..page.." / "..pages.." 页"))
            for i,b in ipairs(menu.buttons) do
                b.emote=group.items[(page-1)*perPage+i]
                if b.emote then
                    b.icon:SetTexture(b.emote.texture)
                    b.label:SetText(short(b.emote.label,5))
                end
                b:SetShown(b.emote~=nil)
            end
        end
        previousGroup=button(menu,"‹",32,24,function() refresh(-1) end)
        previousGroup:SetPoint("TOPLEFT",12,-31)
        nextGroup=button(menu,"›",32,24,function() refresh(1) end)
        nextGroup:SetPoint("TOPRIGHT",-12,-31)
        for i=1,perPage do
            local b=button(menu,"",56,55,function(self)
                if not self.emote then return end
                panel.editor:Insert(self.emote.token); menu:Hide(); panel.editor:SetFocus()
            end)
            b:SetPoint("TOPLEFT",12+((i-1)%6)*60,-61-math.floor((i-1)/6)*59)
            b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetSize(29,29); b.icon:SetPoint("TOP",0,-4)
            b.label:ClearAllPoints(); b.label:SetPoint("BOTTOM",0,4); b.label:SetWidth(51); b.label:SetMaxLines(1)
            b:SetScript("OnEnter",function(self)
                if not self.emote then return end
                self:SetAlpha(0.82)
                GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText(self.emote.label); GameTooltip:Show()
            end)
            b:SetScript("OnLeave",function(self) self:SetAlpha(1); GameTooltip:Hide() end)
            menu.buttons[i]=b
        end
        previousPage=button(menu,"上一页",60,24,function() page=page-1; refresh() end)
        previousPage:SetPoint("BOTTOMLEFT",12,8)
        nextPage=button(menu,"下一页",60,24,function() page=page+1; refresh() end)
        nextPage:SetPoint("BOTTOMRIGHT",-12,8)
        menu.nextGroup,menu.nextPage,menu.refresh=nextGroup,nextPage,refresh
        menu:SetScript("OnHide",function() GameTooltip:Hide() end)
        emoteWindow=menu
        UISpecialFrames[#UISpecialFrames+1]="MyForeverChatEmotes"
    end
    emoteWindow.refresh()
    emoteWindow:Show()
    NS.ui.emotes=emoteWindow
end
function NS.RefreshEmotePicker()
    dirty=true
    if emoteWindow and emoteWindow:IsShown() then emoteWindow.refresh() end
end
local function openContact(kind,target,profile)
    if not panel then return end
    local open=kind=="bnet" and NS.OpenBattleNet or NS.OpenWhisper
    local conv,err=open(target,profile)
    if not conv then status(err or "请输入完整角色名。"); return end
    if not panel:IsShown() then panel:Show() end
    select(conv.id); panel.contact:SetText(""); panel.contact:ClearFocus(); panel.editor:SetFocus()
    return conv
end
function NS.OpenPlayerChat(name) return openContact("whisper",name) end
function NS.OpenBattleNetChat(battleTag) return openContact("bnet",battleTag) end
function NS.RunAction(token)
    local ok,note=NS.PerformAction(token)
    if panel and panel:IsShown() then status(note,ok)
    elseif not ok and note then print(note) end
    return ok
end
function NS.ShowActions()
    if not panel then return end
    if actionWindow and actionWindow:IsShown() then actionWindow:Hide(); return end
    if not panel:IsShown() then panel:Show(); render() end
    if emoteWindow then emoteWindow:Hide() end
    if not actionWindow then
        local menu=box("Frame",panel,C.side,true)
        menu:SetSize(398,245); menu:SetPoint("BOTTOMLEFT",panel,"BOTTOMLEFT",240,142)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:EnableMouse(true)
        registerSurface(menu,C.side,true)
        local heading=text(menu,12,C.text); heading:SetPoint("TOPLEFT",12,-12); heading:SetText("游戏动作")
        button(menu,"×",24,22,function() menu:Hide() end):SetPoint("TOPRIGHT",-4,-4)
        menu.search=field(menu,342,28); menu.search:SetPoint("TOPLEFT",12,-30)
        menu.search:SetMaxLetters(36)
        local hint=text(menu,11,C.muted); hint:SetPoint("LEFT",menu.search,"LEFT",8,0); hint:SetText("搜索动作，例如 跳舞")
        local page,perPage=1,12
        local pageLabel=text(menu,11,C.muted); pageLabel:SetPoint("BOTTOM",0,15)
        menu.buttons={}
        local previous,nextPage
        local function refresh()
            local query=menu.search:GetText():lower()
            local matches={}
            for _,item in ipairs(NS.GetActions()) do
                if query=="" or item.label:lower():find(query,1,true) or item.token:lower():find(query,1,true) then
                    matches[#matches+1]=item
                end
            end
            local pages=math.max(1,math.ceil(#matches/perPage))
            page=math.max(1,math.min(page,pages))
            for i,b in ipairs(menu.buttons) do
                b.action=matches[(page-1)*perPage+i]
                if b.action then b.label:SetText(short(b.action.label,14)) end
                b:SetShown(b.action~=nil)
            end
            pageLabel:SetText(#matches>0 and (page.." / "..pages) or "没有匹配动作")
            previous:SetEnabled(page>1); nextPage:SetEnabled(page<pages)
            hint:SetShown(query=="")
        end
        for i=1,perPage do
            local b=button(menu,"",121,28,function(self)
                if self.action and NS.RunAction(self.action.token) then menu:Hide() end
            end)
            b:SetPoint("TOPLEFT",12+((i-1)%3)*125,-64-math.floor((i-1)/3)*34)
            b.label:SetWidth(113); b.label:SetMaxLines(1)
            menu.buttons[i]=b
        end
        previous=button(menu,"上一页",60,24,function() page=page-1; refresh() end)
        previous:SetPoint("BOTTOMLEFT",12,8)
        nextPage=button(menu,"下一页",60,24,function() page=page+1; refresh() end)
        nextPage:SetPoint("BOTTOMRIGHT",-12,8)
        menu.search:SetScript("OnTextChanged",function() page=1; refresh() end)
        menu:SetScript("OnHide",function() menu.search:ClearFocus() end)
        menu.refresh=refresh
        actionWindow=menu
        NS.ui.actions=menu
    end
    actionWindow.refresh()
    actionWindow:Show()
end
local function requestDelete(conversation)
    if not isPerson(conversation) then
        status("这里只能删除私聊对话。"); return
    end
    if pendingById[conversation.id] then
        status("此对话仍在发送消息，请稍后再删除。"); return
    end
    StaticPopupDialogs.MYFOREVERCHAT_DELETE.text=conversation.kind=="bnet"
        and "删除与 %s 的对话？将移除此游戏账号下该战网好友的共享历史（含其他角色记录），以及当前角色的草稿。"
        or "删除与 %s 的对话？这会移除本机聊天记录和草稿。"
    StaticPopup_Show("MYFOREVERCHAT_DELETE",short(conversation.title,38),nil,conversation)
end
function NS.OpenTargetWhisper()
    local function safeBoolean(api,...)
        if type(api)~="function" then return nil end
        local ok,value=pcall(api,...)
        if not ok or not public(value) then return nil end
        return value==true
    end
    if safeBoolean(UnitExists,"target")~=true or safeBoolean(UnitIsPlayer,"target")~=true then
        status("先在游戏中选中一位玩家，再点击“目标”。"); return false
    end
    local same=safeBoolean(UnitIsUnit,"target","player")
    if same==nil then status("当前目标暂不可读取，请使用完整角色名。"); return false end
    if same then status("当前选中的是自己，请选择另一位玩家。"); return false end
    local api=NameUtil and NameUtil.GetUnmodifiedUnitFullName
    if type(api)~="function" then status("无法读取目标全名，请在左侧输入完整角色名。"); return false end
    local ok,name=pcall(api,"target")
    if not ok or not public(name) or type(name)~="string" or name=="" then
        status("目标全名暂不可读取，请手动输入。"); return false
    end
    NS.CaptureTarget()
    return NS.OpenPlayerChat(name)~=nil
end

local function makeConversationRow()
    local row=box("Button",panel.contactsChild,C.side,false); row:SetHeight(59)
    row.avatar=box("Frame",row,C.surface,true); row.avatar:SetSize(36,36); row.avatar:SetPoint("LEFT",9,0)
    row.letter=text(row.avatar,16,C.green); row.letter:SetPoint("CENTER"); row.letter:SetJustifyH("CENTER")
    row.name=text(row,13); row.name:SetPoint("TOPLEFT",54,-10); row.name:SetWidth(136)
    row.preview=text(row,11,C.muted); row.preview:SetPoint("TOPLEFT",54,-33); row.preview:SetWidth(136)
    row.detail=text(row,11,C.muted); row.detail:SetPoint("TOPLEFT",54,-29); row.detail:SetWidth(146); row.detail:SetMaxLines(1)
    for _,f in ipairs({row.name,row.preview,row.detail}) do f.chatFont=true; updateFont(f) end
    row.name:SetMaxLines(1); row.preview:SetMaxLines(1)
    row.badge=text(row,11,C.green); row.badge:SetPoint("TOPRIGHT",-7,-10); row.badge:SetJustifyH("RIGHT")
    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row:SetScript("OnClick",function(self,mouseButton)
        local entry=self.conversation
        if self.isContact then
            if NS.IsOpenContactGesture(self,entry.id,mouseButton,false) then openContact(entry.kind,entry.target,entry.profile) end
        elseif mouseButton=="RightButton" then
            requestDelete(entry)
        elseif mouseButton=="LeftButton" then
            select(entry.id)
        end
    end)
    row:SetScript("OnEnter",function(self) if current().id~=self.conversation.id then shade(self,C.hover) end end)
    row:SetScript("OnLeave",function(self) shade(self,current().id==self.conversation.id and C.selected or C.side) end)
    return row
end
local function makeMessageRow()
    local row=CreateFrame("Frame",nil,panel.historyChild)
    row.avatar=box("Button",row,C.surface,true); row.avatar:SetSize(32,32)
    row.avatarLetter=text(row.avatar,14,C.green); row.avatarLetter:SetPoint("CENTER")
    row.author=CreateFrame("Button",nil,row); row.author:SetHeight(32)
    row.meta=text(row.author,12,C.muted); row.meta:SetPoint("TOPLEFT"); row.meta:SetPoint("TOPRIGHT"); row.meta:SetHeight(16); row.meta:SetMaxLines(1)
    row.senderDetail=text(row.author,11,C.muted); row.senderDetail:SetPoint("TOPLEFT",0,-17); row.senderDetail:SetPoint("TOPRIGHT",0,-17)
    row.senderDetail:SetHeight(14); row.senderDetail:SetMaxLines(1)
    row.author:SetScript("OnEnter",function(self) showSenderTooltip(self,row.message) end)
    row.author:SetScript("OnLeave",function() GameTooltip:Hide() end)
    row.bubble=box("Button",row,C.incoming,true)
    row.bubble:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row.content=text(row.bubble,14); row.content:SetPoint("TOPLEFT",13,-10)
    row.content.chatFont=true; updateFont(row.content)
    row.content:SetWordWrap(true); row.content:SetNonSpaceWrap(true)
    row.bubble:SetHyperlinksEnabled(true)
    row.bubble:SetScript("OnHyperlinkClick",function(self,link,_,mouseButton)
        if mouseButton=="RightButton" then
            NS.IsOpenContactGesture(self,nil,mouseButton)
            if self.message then showCopy(self.message.text,nativeCommunityContent(row.conversation,self.message)) end
            return
        end
        if mouseButton~="LeftButton" or not public(link) or type(link)~="string" then return end
        local token=self.links and self.links[link]
        if not token then return end
        local name=link:match("^player:([^:]+)")
        local insertLink=IsModifiedClick and IsModifiedClick("CHATLINK")
        if insertLink or (not IsModifiedClick and IsShiftKeyDown and IsShiftKeyDown()) then
            NS.IsOpenContactGesture(self,nil,mouseButton,false)
            panel.editor:Insert(token); panel.editor:SetFocus(); return
        end
        if name and NS.IsOpenContactGesture(self,link,mouseButton,false) then NS.OpenPlayerChat(name); return end
        if not name and SetItemRef and not pcall(SetItemRef,link,token,mouseButton) then
            status("游戏暂时无法打开这个链接。")
        end
    end)
    row.bubble:SetScript("OnHyperlinkEnter",function(self,link)
        if public(link) and type(link)=="string" and self.links and self.links[link] and tooltipLinks[link:match("^([^:]+):")] then
            GameTooltip:SetOwner(self,"ANCHOR_CURSOR")
            local ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link)
            if ok then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    row.bubble:SetScript("OnHyperlinkLeave",function() GameTooltip:Hide() end)
    row.bubble:SetScript("OnClick",function(self,mouseButton)
        if mouseButton=="RightButton" and self.message then showCopy(self.message.text,nativeCommunityContent(row.conversation,self.message)) end
    end)
    local function onContactClick(widget,mouseButton)
        if not row.message or row.message.outgoing then return end
        if row.conversation.kind=="club" and row.message.communityAuthorKnown~=true then return end
        local kind=row.conversation.kind=="bnet" and "bnet" or "whisper"
        local target=kind=="bnet" and row.conversation.target or row.message.author
        if NS.IsOpenContactGesture(widget,kind..":"..target,mouseButton,false) then openContact(kind,target) end
    end
    for _,widget in ipairs({row.avatar,row.author}) do
        widget:RegisterForClicks("LeftButtonUp","RightButtonUp")
        widget:SetScript("OnClick",onContactClick)
    end
    return row
end
local routeLabels={
    whisper="角色私聊", bnet="通行证私聊", group="小队聊天 · 副本小队优先", raid="团队聊天 · 副本团队优先",
    guild="公会聊天", say="附近聊天 · 发送使用说话频道", channel="已加入的公共频道",club="角色社区群聊",
}
render=function()
    if not panel or not panel:IsShown() or rendering then return end
    rendering=true; dirty=false
    local conv=current()
    if not conv then rendering=false; return end
    local presenceCache,bnetPresence={}
    local function presenceFor(entry)
        if not isPerson(entry) then return nil end
        if entry.presence then return entry.presence end
        if entry.kind=="bnet" then
            if not bnetPresence then bnetPresence=NS.GetBattleNetPresenceMap() end
            return bnetPresence[entry.id] or "unknown"
        end
        if not presenceCache[entry.id] then presenceCache[entry.id]=NS.GetContactPresence(entry) end
        return presenceCache[entry.id]
    end
    local width=panel:GetWidth()-247
    panel.historyChild:SetWidth(width); panel.contactsChild:SetWidth(210)
    panel.editor:SetWidth(width-30)
    panel.title:SetText(conv.title); panel.title:SetTextColor(unpack(readable(chatStyle(conv).color,C.outer)))
    panel.subtitle:SetText(routeLabels[conv.kind] or "聊天")
    local clubState=conv.kind=="club" and NS.Communities and NS.Communities.GetStatus(conv.id)
    if conv.kind=="club" then
        panel.subtitle:SetText("角色社区 · "..communityMembers(conv).." · 最近 60 条"
            ..(conv.muted and " · 免打扰" or ""))
        panel.clubNotice:SetText(clubState and clubState.notice or "点“邀请朋友”拉人；管理/更早历史：原生社区。")
    end
    panel.clubNotice:SetShown(conv.kind=="club")
    panel.inviteClub:SetShown(conv.kind=="club")
    panel.restoreSubmission:SetShown(conv.kind=="club")
    local hasSubmission=conv.kind=="club" and type(conv.latestSubmission)=="table"
    panel.restoreSubmission:SetEnabled(hasSubmission); panel.restoreSubmission:SetAlpha(hasSubmission and 1 or 0.45)
    panel.history:SetPoint("TOPLEFT",231,conv.kind=="club" and -148 or -110)
    if conv.kind=="channel" then
        panel.subtitle:SetText(conv.channelCommunity and "旧群频道 · 记录与草稿已保留，请复制到“群聊”发送"
            or conv.channelArchive and "旧地区草稿已保留，请复制到当前频道后发送"
            or (conv.available==false and "当前未加入" or "公共频道").." · "
                ..(not NS.ChannelRemindersEnabled() and "频道提醒总开关已关闭，消息仍保留"
                    or conv.muted and "已屏蔽弹窗，消息仍保留" or "允许弹窗，可单独屏蔽此频道"))
    end
    if isPerson(conv) then
        local detail=conv.kind=="bnet" and "通行证私聊" or profileLabel(conv)
        panel.subtitle:SetText(detail.." · "..(presenceLabels[presenceFor(conv)] or presenceLabels.unknown)
            ..(conv.muted and " · 免打扰" or ""))
    end
    local friendState=NS.GetFriendState(conv)
    panel.addFriend.label:SetText(friendState=="friend" and "已是好友" or friendState=="pending" and "添加中" or "添加好友")
    panel.addFriend:SetEnabled(friendState=="none")
    panel.addFriend:SetAlpha(friendState=="none" and 1 or 0.45)
    panel.addFriend:SetShown(conv.kind~="club")
    panel.pin:SetEnabled(isPerson(conv) or conv.kind=="channel" or conv.kind=="club")
    panel.pin:SetAlpha(panel.pin:IsEnabled() and 1 or 0.45)
    panel.pin.label:SetText(NS.IsPriorityConversation(conv) and "固定置顶" or (conv.pinned and "取消置顶" or "置顶"))
    panel.mute.label:SetText(conv.kind=="channel" and (conv.muted and "恢复弹窗" or "屏蔽弹窗")
        or (conv.muted and "恢复提醒" or "免打扰"))
    panel.mute:SetEnabled(not conv.channelCommunity); panel.mute:SetAlpha(conv.channelCommunity and 0.45 or 1)
    panel.remove:SetEnabled(isPerson(conv))
    panel.remove:SetAlpha(isPerson(conv) and 1 or 0.45)
    panel.remove:SetShown(conv.kind~="club")
    panel.nativeClub:SetShown(conv.kind=="club"); panel.refreshClub:SetShown(conv.kind=="club")
    local changed=displayedId~=conv.id
    if changed then
        displayedId=conv.id; panel.editor:SetText(conv.draft or "")
        panel.editorScroll:SetVerticalScroll(0)
        status("Enter 发送 · 右键复制 · 双击头像或名字私聊")
    end
    updateComposer()
    local query=(panel.search:GetText() or ""):lower(); local count,offset=0,0
    local showContacts,showClubs=sidebarView=="contacts",sidebarView=="clubs"
    shade(panel.conversationsTab,sidebarView=="conversations" and C.selected or C.surface)
    shade(panel.contactsTab,showContacts and C.selected or C.surface)
    shade(panel.clubsTab,showClubs and C.selected or C.surface)
    panel.communityCreate:SetShown(showClubs); panel.communityRefresh:SetShown(showClubs)
    panel.contacts:SetPoint("TOPLEFT",5,showClubs and -214 or -179)
    panel.peopleHeader:SetShown(not showContacts and not showClubs); panel.channelsHeader:SetShown(not showContacts and not showClubs)
    for _,header in ipairs(panel.rosterHeaders) do header:SetShown(showContacts) end
    local clubUnread=0
    for _,entry in ipairs(NS.GetConversations()) do
        if entry.kind=="club" and not entry.muted then clubUnread=clubUnread+(entry.unread or 0) end
    end
    panel.clubsTab.label:SetText(clubUnread>0 and ("群聊 "..(clubUnread>99 and "99+" or clubUnread)) or "群聊")
    local function section(header,entries,title,collapsed,roster)
        if header then header:ClearAllPoints(); header:SetPoint("TOPLEFT",0,-offset) end
        local matches,unread={},0
        for _,entry in ipairs(entries) do
            if query=="" or entry.title:lower():find(query,1,true) or (entry.target and entry.target:lower():find(query,1,true)) then
                matches[#matches+1]=entry
                unread=unread+NS.VisibleUnread(entry)
            end
        end
        if header then
            header.label:SetText((collapsed and query=="" and "＋ " or "－ ")..title.." ("..#matches..")"..(unread>0 and " · "..unread or ""))
            offset=offset+32
        end
        if collapsed and query=="" then return end
        for _,entry in ipairs(matches) do
            count=count+1
            local row=conversationRows[count] or makeConversationRow(); conversationRows[count]=row
            row.conversation,row.isContact=entry,roster; row:ClearAllPoints()
            row:SetPoint("TOPLEFT",0,-offset); row:SetWidth(210)
            local person,club=isPerson(entry),entry.kind=="club"
            local detailed=person or club
            local live=club and NS.db.conversations[entry.id] or entry
            if roster then live=entry.conversation end
            local unreadCount=NS.VisibleUnread(live)
            local grow=math.max(0,options().fontSize-14)
            local rowHeight=detailed and 75+grow*3 or 59+grow*2
            row:SetHeight(rowHeight); offset=offset+rowHeight
            row.name:SetText(((NS.IsPriorityConversation(entry) or (live and live.pinned)) and "↑ " or "")
                ..(entry.channelCommunity and "旧群频道 · " or "")..short(club and entry.clubName or entry.title,entry.channelCommunity and 7 or 13))
            local style=chatStyle(entry)
            setTypeStripe(row,style.color)
            local color=person and entry.profile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.profile.classToken]
            local rowColor=entry.id==conv.id and C.selected or C.side
            row.name:SetTextColor(unpack(readable(color and {color.r,color.g,color.b,1} or (person and C.text or style.color),rowColor)))
            row.preview:SetTextColor(unpack(readable(C.muted,rowColor)))
            row.detail:SetTextColor(unpack(readable(C.muted,rowColor)))
            row.badge:SetTextColor(unpack(readable(C.green,rowColor)))
            local last=live and live.messages and live.messages[#live.messages]
            row.preview:ClearAllPoints(); row.preview:SetPoint("TOPLEFT",54,detailed and -51-grow*2 or -33-grow)
            row.detail:ClearAllPoints(); row.detail:SetPoint("TOPLEFT",54,-29-grow)
            row.detail:SetShown(detailed)
            local presence=presenceFor(entry)
            if person then
                local detail=profileLabel(entry)
                if entry.kind=="bnet" and detail=="资料待更新" then detail=presenceLabels[presence] or presenceLabels.unknown end
                row.detail:SetText(detail)
            elseif club then
                row.detail:SetText((entry.streamName or "群频道").." · "..communityMembers(entry))
            end
            local preview=roster and "双击头像或名字私聊" or (last and messagePreview(entry,last,32) or (person and "尚未聊天" or "暂无消息"))
            row.preview:SetText((club and entry.available~=true and "暂不可用 · " or "")
                ..(live and live.muted and (entry.kind=="channel" and "已屏蔽弹窗 · " or "免打扰 · ") or "")..preview)
            row.letter:SetText(person and short(entry.title,1) or conversationLetter(entry))
            row.letter:SetTextColor(unpack(readable(style.color,C.surface)))
            portrait(row.avatar,row.letter,person and entry or nil)
            avatarState(row.avatar,row.letter,live or entry,presence)
            row.badge:SetText(unreadCount>0 and (unreadCount>99 and "99+" or tostring(unreadCount)) or "")
            row.name:SetWidth(unreadCount>0 and 118 or 146)
            shade(row,rowColor); row:Show()
        end
    end
    local clubsNotice
    if showClubs then
        local clubs,seen={},{}
        if NS.Communities then
            local entries,note=NS.Communities.GetEntries(); clubsNotice=note
            for _,entry in ipairs(entries or {}) do
                clubs[#clubs+1]=NS.db.conversations[entry.id] or entry; seen[entry.id]=true
            end
        end
        for _,entry in ipairs(NS.GetConversations()) do
            if entry.kind=="club" and not seen[entry.id] then clubs[#clubs+1]=entry end
        end
        table.sort(clubs,function(a,b)
            local ap,bp=a.pinned==true,b.pinned==true
            if ap~=bp then return ap end
            if a.title~=b.title then return a.title<b.title end
            return a.id<b.id
        end)
        section(nil,clubs,"群聊",false)
    elseif showContacts then
        local friends,bnet,recent=NS.GetContactLists()
        section(panel.rosterHeaders[1],friends,"游戏好友",panel.rosterHeaders[1].collapsed,true)
        section(panel.rosterHeaders[2],bnet,"通行证好友",panel.rosterHeaders[2].collapsed,true)
        section(panel.rosterHeaders[3],recent,"最近的人",panel.rosterHeaders[3].collapsed,true)
    else
        local priority,people,channels={},{},{}
        for _,entry in ipairs(NS.GetConversations()) do
            if entry.kind~="club" then
                local list=NS.IsPriorityConversation(entry) and priority or (isPerson(entry) and people or channels)
                list[#list+1]=entry
            end
        end
        section(nil,priority,"固定置顶",false)
        section(panel.peopleHeader,people,"人物",NS.db.peopleCollapsed)
        section(panel.channelsHeader,channels,"频道 · 展开/收起",NS.db.channelsCollapsed)
    end
    panel.clubsEmpty:SetShown(showClubs and count==0)
    if showClubs and count==0 then
        panel.clubsEmpty:SetText(query~="" and "未找到匹配的群聊" or clubsNotice
            or "尚未加入角色社区。\n点上方“创建 / 加入”开始，或刷新已加入的群聊。")
    end
    for i=count+1,#conversationRows do conversationRows[i]:Hide() end
    panel.contactsChild:SetHeight(math.max(showClubs and count==0 and 140 or 1,offset))
    panel.contacts:SetVerticalScroll(math.min(panel.contacts:GetVerticalScroll(),math.max(0,offset-panel.contacts:GetHeight())))
    local oldScroll=panel.history:GetVerticalScroll()
    local wasBottom=oldScroll>=math.max(0,panel.history:GetVerticalScrollRange()-24)
    local anchor,anchorOffset,anchoredScroll
    if not changed and not wasBottom then
        for _,row in ipairs(messageRows) do
            if row:IsShown() and row.layoutY and row.layoutY+row:GetHeight()>oldScroll then
                anchor,anchorOffset=row.message,oldScroll-row.layoutY
                break
            end
        end
    end
    local y=10; local maxBubble=math.max(160,math.floor((width-82)*0.92))
    for i,msg in ipairs(conv.messages) do
        local row=messageRows[i] or makeMessageRow(); messageRows[i]=row
        row.message,row.bubble.message,row.conversation=msg,msg,conv
        row.layoutY=y
        if msg==anchor then anchoredScroll=y+anchorOffset end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:SetWidth(width)
        local right=msg.outgoing
        row.avatar:ClearAllPoints(); row.author:ClearAllPoints(); row.bubble:ClearAllPoints()
        row.avatar:SetPoint(right and "TOPRIGHT" or "TOPLEFT",right and -8 or 8,-34)
        row.avatarLetter:SetText(right and "我" or short(msg.author,1))
        local contact=not right and messageContact(conv,msg) or nil
        portrait(row.avatar,row.avatarLetter,contact,right)
        avatarState(row.avatar,row.avatarLetter,contact,presenceFor(contact))
        local timestamp=type(msg.time)=="number" and date("%H:%M",msg.time) or ""
        local bubbleColor,style=typeShade(conv,msg,right)
        row.meta:SetText("["..style.label.."] "..(right and "我 · " or "")..msg.author
            ..(msg.communityDeleted and " · 已删除" or msg.communityEdited and " · 已编辑" or ""))
        row.meta:SetTextColor(unpack(readable(style.color,C.outer)))
        local details=senderDetails(msg)
        row.senderDetail:SetText((details~="" and details.." · " or "")..timestamp)
        row.senderDetail:SetTextColor(unpack(readable(C.muted,C.outer)))
        row.meta:SetJustifyH(right and "RIGHT" or "LEFT"); row.senderDetail:SetJustifyH(right and "RIGHT" or "LEFT")
        row.author:SetWidth(math.min(width-100,math.max(row.meta:GetUnboundedStringWidth(),row.senderDetail:GetUnboundedStringWidth())+2))
        row.author:SetPoint(right and "TOPRIGHT" or "TOPLEFT",right and -50 or 50,0)
        local nativeContent=nativeCommunityContent(conv,msg)
        local content,links=nativeContent,nil
        if not content then content,links=clean(msg.text,false,bubbleColor) end
        row.bubble.links=links
        row.content:SetText(content); row.content:SetWidth(maxBubble-26)
        -- Native protected text can render correctly while reporting zero
        -- natural width. Give it the available bubble width so it can wrap;
        -- measuring the opaque handle would collapse it to one character.
        local bubbleWidth=maxBubble
        if not nativeContent then
            local natural=row.content:GetUnboundedStringWidth()
            bubbleWidth=math.min(maxBubble,math.max(54,natural+26))
        end
        row.content:SetWidth(bubbleWidth-26)
        local bubbleHeight=math.max(38,row.content:GetStringHeight()+21)
        row.bubble:SetSize(bubbleWidth,bubbleHeight)
        row.bubble:SetPoint(right and "TOPRIGHT" or "TOPLEFT",right and -50 or 50,-34)
        shade(row.bubble,bubbleColor)
        row.content:SetTextColor(unpack(readable(C.text,bubbleColor)))
        setTypeStripe(row.bubble,style.color)
        local height=bubbleHeight+51
        row:SetHeight(height); row:Show(); y=y+height
    end
    for i=#conv.messages+1,#messageRows do messageRows[i]:Hide() end
    panel.empty:SetShown(#conv.messages==0)
    panel.historyChild:SetHeight(math.max(y,1))
    local range=math.max(0,y-panel.history:GetHeight())
    panel.history:SetVerticalScroll((changed or wasBottom) and range or math.max(0,math.min(anchoredScroll or oldScroll,range)))
    panel.bottom:SetShown(not changed and not wasBottom and range>0)
    rendering=false
end
local function wheel(self,delta)
    self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*58)))
    if self==panel.history then panel.bottom:SetShown(self:GetVerticalScroll()<self:GetVerticalScrollRange()-24) end
end
local function makeScroll(parent)
    local scroll=CreateFrame("ScrollFrame",nil,parent)
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel",wheel)
    local child=CreateFrame("Frame",nil,scroll); child:SetSize(200,1); scroll:SetScrollChild(child)
    return scroll,child
end
local function showChannelSettings()
    if not channelSettings then
        local menu=CreateFrame("Frame","MyForeverChatChannelSettings",panel,"BackdropTemplate")
        menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        menu:SetSize(460,390); menu:SetPoint("CENTER",panel,"CENTER",0,0)
        menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:EnableMouse(true); menu:SetClampedToScreen(true)
        registerSurface(menu,C.side,true)
        local heading=text(menu,16,C.text); heading:SetPoint("TOPLEFT",16,-16); heading:SetText("公共频道提醒")
        button(menu,"×",26,24,function() menu:Hide() end):SetPoint("TOPRIGHT",-8,-8)
        local masterStatus=text(menu,14,C.text); masterStatus:SetPoint("TOPLEFT",16,-53)
        menu.masterToggle=button(menu,"",126,28,function()
            NS.SetChannelRemindersEnabled(not NS.ChannelRemindersEnabled()); render()
        end)
        menu.masterToggle:SetPoint("TOPRIGHT",-16,-44)
        local hint=text(menu,12,C.muted); hint:SetPoint("TOPLEFT",16,-80); hint:SetWidth(428); hint:SetHeight(38)
        hint:SetText("关闭后仍保存频道消息，私聊和群聊照常提醒。\n开启后按下方各频道的设置弹窗。")
        menu.scroll,menu.child=makeScroll(menu)
        menu.scroll:SetPoint("TOPLEFT",12,-125); menu.scroll:SetPoint("BOTTOMRIGHT",-12,18)
        menu.child:SetWidth(436); menu.rows={}
        menu.empty=text(menu,13,C.muted); menu.empty:SetPoint("CENTER"); menu.empty:SetText("尚未发现已加入的公共频道")
        channelSettings=menu
        refreshChannelSettings=function()
            if not menu:IsShown() then return end
            local enabled=NS.ChannelRemindersEnabled()
            masterStatus:SetText(enabled and "总开关 · 已开启" or "总开关 · 已关闭")
            menu.masterToggle.label:SetText(enabled and "关闭频道提醒" or "开启频道提醒")
            local entries={}
            for _,entry in ipairs(NS.GetConversations()) do
                if entry.kind=="channel" and not entry.channelCommunity then entries[#entries+1]=entry end
            end
            table.sort(entries,function(a,b)
                if (a.available~=false)~=(b.available~=false) then return a.available~=false end
                return a.title<b.title
            end)
            for index,entry in ipairs(entries) do
                local row=menu.rows[index]
                if not row then
                    row=box("Frame",menu.child,C.surface,true); row:SetSize(430,64)
                    row.name=button(row,"",302,27,function(self)
                        select(self.owner.conversation.id); menu:Hide(); panel:Show(); render()
                    end)
                    row.name.owner=row; row.name:SetPoint("TOPLEFT",8,-5)
                    row.name.label:ClearAllPoints(); row.name.label:SetPoint("LEFT",4,0)
                    row.name.label:SetWidth(292); row.name.label:SetMaxLines(1); row.name.label:SetJustifyH("LEFT")
                    row.note=text(row,11,C.muted); row.note:SetPoint("TOPLEFT",12,-38); row.note:SetWidth(294)
                    row.toggle=button(row,"",104,28,function(self)
                        local _,note=NS.ToggleMute(self.owner.conversation.id); status(note); refreshChannelSettings(); render()
                    end)
                    row.toggle.owner=row; row.toggle:SetPoint("RIGHT",-8,0)
                    menu.rows[index]=row
                end
                row.conversation=entry; row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(index-1)*70)
                row.name.label:SetText(entry.title)
                row.note:SetText(entry.channelArchive and "旧草稿 · 请复制到当前频道后发送"
                    or (entry.available==false and "当前未加入 · " or "")
                        ..(not enabled and "总开关已关 · " or "")
                        ..(entry.muted and "已设为屏蔽" or "已设为允许"))
                row.toggle.label:SetText(entry.muted and (enabled and "恢复弹窗" or "设为允许") or "屏蔽弹窗")
                row:Show()
            end
            for index=#entries+1,#menu.rows do menu.rows[index]:Hide() end
            menu.empty:SetShown(#entries==0); menu.child:SetHeight(math.max(1,#entries*70))
        end
        UISpecialFrames[#UISpecialFrames+1]="MyForeverChatChannelSettings"
        NS.ui.channelSettings=menu
    end
    NS.SyncChannels(); channelSettings:Show(); refreshChannelSettings()
end
local function scrollNotifications(_,delta)
    if notifications and delta~=0 then notifications:Scroll(delta>0 and -1 or 1) end
end
local function showToastTooltip(widget)
    local message=widget.item and widget.item.message
    if not message then return end
    local details=senderDetails(message)
    GameTooltip:SetOwner(widget,"ANCHOR_TOP")
    GameTooltip:SetText(widget.toastHeading.."\n"..message.author..(details~="" and "\n"..details or "")
        .."\nCtrl+X 回复 · 滚轮翻看 · 右键关闭"
        ..(widget.muteChannel:IsShown() and "\n屏蔽：仅关闭此频道的提醒" or ""))
    GameTooltip:Show()
end
local function makeToast()
    local f=button(UIParent,"",260,toastHeight(),nil)
    f:SetFrameStrata("HIGH"); f:SetClampedToScreen(true)
    f:RegisterForClicks("LeftButtonUp","RightButtonUp")
    f:EnableMouseWheel(true); f:SetScript("OnMouseWheel",scrollNotifications)
    f.avatar=box("Frame",f,C.surface,true); f.avatar:SetSize(18,18); f.avatar:SetPoint("TOPLEFT",8,-5); f.avatar:SetAlpha(0.75)
    f.letter=text(f.avatar,11,C.muted); f.letter:SetPoint("CENTER")
    f.title=text(f,10,C.muted); f.title:SetPoint("TOPRIGHT",-8,-8); f.title:SetWidth(70); f.title:SetMaxLines(1); f.title:SetJustifyH("RIGHT")
    f.muteChannel=button(f,"屏蔽",36,18,function()
        local item=f.item
        local conv=item and NS.db.conversations[item.conversationId]
        if conv and conv.kind=="channel" and not conv.muted then NS.ToggleMute(conv.id) end
    end)
    f.muteChannel.label.appearanceBaseSize=10; updateFont(f.muteChannel.label)
    f.muteChannel:SetPoint("TOPRIGHT",-8,-4); f.muteChannel:Hide()
    f.sender=text(f,11,C.muted); f.sender:SetPoint("TOPLEFT",32,-8); f.sender:SetWidth(140); f.sender:SetMaxLines(1)
    f.preview=text(f,14); f.preview:SetPoint("TOPLEFT",10,-30); f.preview:SetWidth(240); f.preview:SetMaxLines(2)
    f.preview.chatFont=true; updateFont(f.preview)
    f:SetScript("OnClick",function(self,mouseButton)
        local item=self.item
        if not item then return end
        if mouseButton=="RightButton" then notifications:Dismiss(item); return end
        if NS.db.conversations[item.conversationId] then
            select(item.conversationId); panel:Show(); render(); panel.editor:SetFocus()
        else notifications:Dismiss(item) end
    end)
    f:SetScript("OnEnter",function(self) self:SetAlpha(0.90); showToastTooltip(self) end)
    local function hideOwnTooltip(self)
        if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    f:SetScript("OnLeave",function(self) self:SetAlpha(1); hideOwnTooltip(self) end)
    f:SetScript("OnHide",hideOwnTooltip)
    f:Hide()
    return f
end
local function toastBase()
    return math.max(40,UIParent:GetHeight()*0.26)
end
local function paintNotifications(visible,queued,pageInfo)
    local base=toastBase()
    for i,item in ipairs(visible) do
        local f=toastFrames[i] or makeToast()
        toastFrames[i]=f
        local conv=NS.db.conversations[item.conversationId]
        f.item=item; f.conversationId=item.conversationId
        f:SetHeight(toastHeight())
        f:ClearAllPoints(); f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",35,-base-(i-1)*toastStep())
        local bubbleColor,style=typeShade(conv,item.message,false)
        shade(f,bubbleColor); setTypeStripe(f,style.color)
        local label=conv.kind=="channel" and conversationLetter(conv) or style.label
        f.toastHeading="["..label.."]"..((conv.kind=="channel" or conv.kind=="club") and " "..conv.title or "")
        f.title:SetText("["..label.."]")
        f.title:ClearAllPoints(); f.title:SetPoint("TOPRIGHT",conv.kind=="channel" and -50 or -8,-8)
        f.title:SetWidth(conv.kind=="channel" and 32 or 70)
        f.muteChannel:SetShown(conv.kind=="channel")
        f.sender:SetText(item.message.author)
        f.sender:SetTextColor(unpack(readable(C.muted,bubbleColor)))
        f.title:SetTextColor(unpack(readable(C.muted,bubbleColor)))
        f.preview:SetTextColor(unpack(readable(C.text,bubbleColor)))
        f.letter:SetTextColor(unpack(readable(C.muted,C.surface)))
        f.preview:SetText(messagePreview(conv,item.message,70))
        f.letter:SetText(short(item.message.author,1))
        local person=messageContact(conv,item.message)
        portrait(f.avatar,f.letter,person)
        avatarState(f.avatar,f.letter,person)
        f.avatar.presenceBadge:SetSize(8,8); f.avatar.muteBadge:SetSize(8,8)
        f:Show()
        -- Paging reuses this frame without another OnEnter event.
        if GameTooltip:IsShown() and GameTooltip.IsOwned and GameTooltip:IsOwned(f) then showToastTooltip(f) end
    end
    for i=#visible+1,#toastFrames do
        local f=toastFrames[i]
        f.item=nil; f.conversationId=nil; f:Hide()
    end
    clearToasts:ClearAllPoints(); clearToasts:SetPoint("BOTTOMLEFT",UIParent,"TOPLEFT",35,-base+8)
    local info=pageInfo or (notifications and notifications.GetPageInfo and notifications:GetPageInfo())
        or {first=1,last=#visible,total=#visible+#queued}
    clearToasts.label:SetText("清除泡泡 ("..info.total..")")
    clearToasts:SetShown(#visible>0)
    local paged=#visible>0 and (info.hasPrevious or info.hasNext)
    toastPrevious:ClearAllPoints(); toastPrevious:SetPoint("BOTTOMLEFT",UIParent,"TOPLEFT",159,-base+8)
    toastNext:ClearAllPoints(); toastNext:SetPoint("BOTTOMLEFT",UIParent,"TOPLEFT",231,-base+8)
    toastPrevious:SetEnabled(info.hasPrevious==true); toastNext:SetEnabled(info.hasNext==true)
    toastPrevious:SetAlpha(info.hasPrevious and 1 or 0.4); toastNext:SetAlpha(info.hasNext and 1 or 0.4)
    toastPrevious:SetShown(paged); toastNext:SetShown(paged)
    toastPage:ClearAllPoints(); toastPage:SetPoint("BOTTOMLEFT",UIParent,"TOPLEFT",35,-base+34)
    toastPage:SetText((info.first or 0).."–"..(info.last or 0).." / "..info.total)
    toastPage:SetShown(paged)
end
local function notifyIncoming()
    local incoming=NS.lastIncoming
    if not incoming or incoming.message==lastIncoming then return end
    lastIncoming=incoming.message
    if panel:IsShown() then return end
    return notifications:Push(incoming.conversationId,incoming.message)
end
function NS.RefreshUI()
    if not panel then return end
    if appliedAppearance~=NS.db.appearance then NS.ApplyAppearance() end
    checkEcho()
    local changed=notifications:Refresh()
    if not notifyIncoming() and not changed and #notifications.visible>0 then
        paintNotifications(notifications.visible,notifications.queued)
    end
    local unread=NS.UnreadTotal()
    launcher.badge:SetText(unread>0 and (unread>99 and "99+" or tostring(unread)) or "")
    panel.channelSettings.label:SetText(NS.ChannelRemindersEnabled() and "频道提醒 · 开" or "频道提醒 · 关")
    if NS.lastNotice and NS.lastNotice~=lastNotice then
        lastNotice=NS.lastNotice; status(NS.lastNotice)
    end
    dirty=true
    if refreshChannelSettings then refreshChannelSettings() end
end
function NS.ClearNotifications()
    if notifications then return notifications:DismissAll() end
end
function NS.MinimizeUI()
    if panel then panel:Hide() end
end
function NS.ShowAppearanceSettings()
    if not panel then return end
    panel:Show(); render()
    if NS.OpenAppearanceSettings then NS.OpenAppearanceSettings() end
end
function NS.ShowSystemNotice(message)
    if not public(message) or type(message)~="string" then return end
    -- Match Blizzard's localized, complete player-not-found message for an
    -- actual pending recipient. Another player's offline notice is unrelated.
    local template=ERR_CHAT_PLAYER_NOT_FOUND_S
    if public(template) and type(template)=="string" then
        for id in pairs(pendingById) do
            local conv=NS.db.conversations[id]
            if conv and conv.kind=="whisper" and public(conv.target) and type(conv.target)=="string" then
                local ok,expected=pcall(string.format,template,conv.target)
                if ok and message:lower()==expected:lower() then
                    failPending(id,"offline","对方不在线或角色名无效 · 未发送","请确认完整角色名或等待对方上线；草稿已保留。")
                    return
                end
            end
        end
    end
    -- Other system messages are not proof of delivery failure.
    status("游戏提示："..clean(message,true))
end
function NS.ShowWhisperOfflineNotice(...)
    local accountID=eventArgument(13,...)
    if not public(accountID) or type(accountID)~="number" then return end
    for id,token in pairs(pendingById) do
        local conv=NS.db.conversations[id]
        if conv and conv.kind=="bnet" and token.accountID==accountID then
            failPending(id,"offline","对方离线 · 通行证私聊未发送","游戏已返回离线提示；请等待上线，草稿已保留。")
        end
    end
end
function NS.ToggleUI()
    if not panel then return end
    if panel:IsShown() then panel:Hide() else panel:Show(); render(); panel.editor:SetFocus() end
end
function NS.ReplyRecent()
    if not panel then return end
    if NS.db.lastWhisperId and NS.db.conversations[NS.db.lastWhisperId] then select(NS.db.lastWhisperId) end
    panel:Show(); render(); panel.editor:SetFocus()
end
function NS.QuickReply()
    if not panel then return end
    if panel:IsShown() then NS.MinimizeUI(); return end
    if notifications then notifications:Refresh() end
    local target,newestOrder=nil,-1
    -- Priority changes screen order; arrival order still determines quick reply.
    for _,toast in ipairs(toastFrames) do
        if toast:IsShown() and toast.item and NS.db.conversations[toast.item.conversationId] then
            if toast.IsMouseOver and toast:IsMouseOver() then target=toast.item.conversationId; break end
            local order=toast.item.order or 0
            if order>newestOrder then target,newestOrder=toast.item.conversationId,order end
        end
    end
    if target then
        select(target); panel:Show(); render(); panel.editor:SetFocus()
    else
        NS.ReplyRecent()
    end
end
function NS.ResetPosition()
    if not panel then return end
    panel:ClearAllPoints(); panel:SetPoint("CENTER",UIParent,"CENTER",0,0); panel:SetSize(840,560)
    launcher:ClearAllPoints(); launcher:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-30,-235)
    NS.db.launcher={point="TOPRIGHT",relativePoint="TOPRIGHT",x=-30,y=-235}
    savePosition()
    panel:Show(); render()
end
function NS.BuildUI()
    if panel then return end
    NS.ApplyAppearance()
    panel=CreateFrame("Frame","MyForeverChatWindow",UIParent,"BackdropTemplate")
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); registerSurface(panel,C.outer)
    local saved=type(NS.db.window)=="table" and NS.db.window or {}
    local validPoints={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
    local function finite(value,fallback)
        return type(value)=="number" and value==value and math.abs(value)<10000 and value or fallback
    end
    panel:SetSize(math.max(680,math.min(1080,finite(saved.width,840))),math.max(460,math.min(900,finite(saved.height,560))))
    panel:SetPoint(validPoints[saved.point] and saved.point or "CENTER",UIParent,validPoints[saved.relativePoint] and saved.relativePoint or "CENTER",finite(saved.x,0),finite(saved.y,0))
    panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true); panel:EnableMouse(true)
    panel:SetMovable(true); panel:SetResizable(true); panel:SetResizeBounds(680,460,1080,900)
    local side=box("Frame",panel,C.side,false)
    side:SetPoint("TOPLEFT"); side:SetPoint("BOTTOMLEFT"); side:SetWidth(220)
    local brand=text(side,20,C.green); brand:SetPoint("TOPLEFT",16,-18); brand:SetText("我的聊天")
    panel.allRead=button(side,"已读",46,26,function()
        NS.MarkAllRead(); status("所有会话已标为已读。",true)
    end)
    panel.allRead:SetPoint("TOPRIGHT",-12,-16)
    local newLabel=text(side,11,C.muted); newLabel:SetPoint("TOPLEFT",14,-54); newLabel:SetText("新私聊 · 完整角色名")
    local contactBackground=box("Frame",side,C.surface,true)
    contactBackground:SetPoint("TOPLEFT",10,-72); contactBackground:SetSize(112,30)
    panel.contact=field(contactBackground,112,30); panel.contact:SetPoint("TOPLEFT"); panel.contact:SetMaxLetters(100)
    panel.contact.focusSurface=contactBackground
    panel.contact:SetScript("OnEnterPressed",function(self) NS.OpenPlayerChat(self:GetText()) end)
    panel.target=button(side,"目标",46,30,NS.OpenTargetWhisper)
    panel.target:SetPoint("TOPLEFT",128,-72)
    local newContact=button(side,"+",28,30,function() NS.OpenPlayerChat(panel.contact:GetText()) end,C.green)
    newContact:SetPoint("TOPLEFT",180,-72)
    local searchBackground=box("Frame",side,C.surface,true)
    searchBackground:SetPoint("TOPLEFT",10,-111); searchBackground:SetSize(198,28)
    panel.search=field(searchBackground,198,28); panel.search:SetPoint("TOPLEFT"); panel.search:SetMaxLetters(60)
    panel.search.focusSurface=searchBackground
    panel.searchHint=text(searchBackground,11,C.muted); panel.searchHint:SetPoint("LEFT",8,0); panel.searchHint:SetText("搜索")
    panel.search:SetScript("OnTextChanged",function(self)
        panel.searchHint:SetShown(self:GetText()=="")
        if panel.contacts then panel.contacts:SetVerticalScroll(0) end
        dirty=true
    end)
    panel.conversationsTab=button(side,"会话",64,25,function() switchSidebar("conversations"); render() end)
    panel.conversationsTab:SetPoint("TOPLEFT",10,-146)
    panel.contactsTab=button(side,"联系人",64,25,function()
        if sidebarView~="contacts" then NS.RequestContactLists() end
        switchSidebar("contacts"); render()
    end)
    panel.contactsTab:SetPoint("TOPLEFT",78,-146)
    panel.clubsTab=button(side,"群聊",64,25,function()
        switchSidebar("clubs"); refreshCommunity()
    end)
    panel.clubsTab:SetPoint("TOPLEFT",146,-146)
    panel.communityCreate=button(side,"创建 / 加入",140,26,function() openNativeCommunity() end)
    panel.communityCreate:SetPoint("TOPLEFT",10,-179)
    panel.communityRefresh=button(side,"刷新",54,26,function() refreshCommunity() end)
    panel.communityRefresh:SetPoint("TOPLEFT",156,-179)
    panel.contacts,panel.contactsChild=makeScroll(side)
    panel.contacts:SetPoint("TOPLEFT",5,-179); panel.contacts:SetPoint("BOTTOMRIGHT",-5,46)
    panel.clubsEmpty=text(panel.contactsChild,12,C.muted); panel.clubsEmpty:SetPoint("TOPLEFT",8,-12)
    panel.clubsEmpty:SetWidth(194); panel.clubsEmpty:SetHeight(120); panel.clubsEmpty:Hide()
    panel.about=button(side,"关于作者",88,25,function() if NS.ShowAbout then NS.ShowAbout() end end)
    panel.about:SetPoint("BOTTOMLEFT",10,10)
    panel.channelSettings=button(side,"频道提醒",104,25,showChannelSettings)
    panel.channelSettings:SetPoint("BOTTOMRIGHT",-10,10)
    panel.peopleHeader=button(panel.contactsChild,"人物",210,28,function()
        NS.db.peopleCollapsed=not NS.db.peopleCollapsed; render()
    end)
    panel.peopleHeader.label:ClearAllPoints(); panel.peopleHeader.label:SetPoint("LEFT",8,0)
    panel.channelsHeader=button(panel.contactsChild,"频道",210,28,function()
        NS.db.channelsCollapsed=not NS.db.channelsCollapsed; render()
    end)
    panel.channelsHeader.label:ClearAllPoints(); panel.channelsHeader.label:SetPoint("LEFT",8,0)
    panel.rosterHeaders={}
    for i=1,3 do
        local header=button(panel.contactsChild,"",210,28,function(self)
            self.collapsed=not self.collapsed; render()
        end)
        header.label:ClearAllPoints(); header.label:SetPoint("LEFT",8,0)
        header.collapsed=i<3
        panel.rosterHeaders[i]=header
    end
    panel.title=text(panel,19); panel.title:SetPoint("TOPLEFT",240,-19); panel.title:SetPoint("TOPRIGHT",-203,-19); panel.title:SetHeight(24)
    panel.subtitle=text(panel,11,C.muted); panel.subtitle:SetPoint("TOPLEFT",241,-48); panel.subtitle:SetWidth(430)
    panel.subtitle:SetMaxLines(1)
    panel.inviteClub=button(panel,"邀请朋友",104,26,inviteCommunityFriend,C.green)
    panel.inviteClub:SetPoint("TOPLEFT",240,-109); panel.inviteClub:Hide()
    panel.inviteClub:SetScript("OnEnter",function(self)
        self:SetAlpha(0.82)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("邀请朋友\n打开当前群后，再点原生窗口右下角“邀请成员”。\n随后选择朋友或复制邀请链接。",1,1,1,1,true)
        GameTooltip:Show()
    end)
    local function hideInviteTooltip(self)
        self:SetAlpha(1)
        if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    panel.inviteClub:SetScript("OnLeave",hideInviteTooltip)
    panel.inviteClub:SetScript("OnHide",hideInviteTooltip)
    panel.clubNotice=text(panel,11,C.muted); panel.clubNotice:SetPoint("TOPLEFT",354,-109); panel.clubNotice:SetPoint("TOPRIGHT",-146,-109)
    panel.clubNotice:SetHeight(30); panel.clubNotice:SetMaxLines(2); panel.clubNotice:Hide()
    panel.restoreSubmission=button(panel,"找回上次发送",122,26,function()
        local conv=current()
        if not conv or conv.kind~="club" or not NS.RestoreLastCommunitySubmission then return end
        local ok,note=NS.RestoreLastCommunitySubmission(conv.id)
        if ok and current()==conv then panel.editor:SetText(conv.draft or ""); panel.editor:SetFocus() end
        if render then render() end
        status(note)
    end)
    panel.restoreSubmission:SetPoint("TOPRIGHT",-14,-109); panel.restoreSubmission:Hide()
    panel.pin=button(panel,"置顶",78,26,function()
        local _,note=NS.TogglePin(current().id); status(note)
    end)
    panel.pin:SetPoint("TOPLEFT",240,-72)
    panel.mute=button(panel,"免打扰",88,26,function()
        local _,note=NS.ToggleMute(current().id); status(note)
    end)
    panel.mute:SetPoint("TOPLEFT",326,-72)
    panel.remove=button(panel,"删除对话",88,26,function() requestDelete(current()) end)
    panel.remove:SetPoint("TOPLEFT",422,-72)
    panel.addFriend=button(panel,"添加好友",92,26,function()
        local _,note=NS.AddSelectedFriend(); render(); status(note)
    end)
    panel.addFriend:SetPoint("TOPLEFT",518,-72)
    panel.nativeClub=button(panel,"原生社区",88,26,function() openNativeCommunity(current().id) end)
    panel.nativeClub:SetPoint("TOPLEFT",422,-72); panel.nativeClub:Hide()
    panel.refreshClub=button(panel,"刷新群消息",92,26,function() refreshCommunity(current().id) end)
    panel.refreshClub:SetPoint("TOPLEFT",518,-72); panel.refreshClub:Hide()
    StaticPopupDialogs.MYFOREVERCHAT_DELETE={
        text="删除与 %s 的对话？这会移除本机聊天记录和草稿。",button1="删除对话",button2="取消",timeout=0,whileDead=true,hideOnEscape=true,
        OnAccept=function(_,entry)
            if not entry or NS.db.conversations[entry.id]~=entry then status("对话已变化，请重新选择。"); return end
            if pendingById[entry.id] then status("消息正在发送，请稍后再删除。"); return end
            local ok,note=NS.DeleteConversation(entry.id,true)
            if ok and displayedId==entry.id then
                displayedId=nil
                if copyWindow then copyWindow:Hide() end
            end
            render(); status(note)
        end,
    }
    local close=button(panel,"×",30,28,function() panel:Hide() end); close:SetPoint("TOPRIGHT",-10,-12)
    panel.minimize=button(panel,"—",30,28,NS.MinimizeUI); panel.minimize:SetPoint("TOPRIGHT",-48,-12)
    local clear=button(panel,"清空",48,28,function()
        StaticPopupDialogs.MYFOREVERCHAT_CLEAR.text=current().kind=="bnet"
            and "清空此游戏账号下该战网好友的共享历史（含其他角色记录）？草稿保持不变。"
            or current().kind=="club" and "清空此群频道保存在本机的记录？原生社区历史不会被删除。"
            or "清空此会话保存在本机的聊天记录？"
        StaticPopup_Show("MYFOREVERCHAT_CLEAR",nil,nil,current().id)
    end)
    clear:SetPoint("TOPRIGHT",-86,-12)
    panel.settings=button(panel,"设置",48,28,function() NS.OpenAppearanceSettings() end)
    panel.settings:SetPoint("TOPRIGHT",-142,-12)
    StaticPopupDialogs.MYFOREVERCHAT_CLEAR={
        text="清空此会话保存在本机的聊天记录？",button1="清空",button2="取消",timeout=0,whileDead=true,hideOnEscape=true,
        OnAccept=function(_,id) if current() and current().id==id then NS.ClearSelected() end end,
    }
    local drag=CreateFrame("Frame",nil,panel)
    drag:SetPoint("TOPLEFT",220,0); drag:SetPoint("TOPRIGHT",-198,0); drag:SetHeight(65)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function() panel:StartMoving(); mfLayout("BeginDrag",panel) end)
    drag:SetScript("OnDragStop",function() panel:StopMovingOrSizing(); mfLayout("SnapToGrid",panel); savePosition() end)
    mfLayout("RegisterLayout",panel,"微信式聊天")
    panel.history,panel.historyChild=makeScroll(panel)
    panel.history:SetPoint("TOPLEFT",231,-110); panel.history:SetPoint("BOTTOMRIGHT",-12,148)
    panel.empty=text(panel.history,14,C.muted); panel.empty:SetPoint("CENTER"); panel.empty:SetText("选好会话，从这里开始聊天。")
    panel.bottom=button(panel,"回到最新 ↓",116,26,function() panel.history:SetVerticalScroll(panel.history:GetVerticalScrollRange()); panel.bottom:Hide() end)
    panel.bottom:SetPoint("BOTTOMRIGHT",-22,155); panel.bottom:Hide()
    local composeBackground=box("Frame",panel,C.surface,false)
    composeBackground:SetPoint("TOPLEFT",panel,"BOTTOMLEFT",232,140)
    composeBackground:SetPoint("BOTTOMRIGHT",-14,44)
    local editorScroll=CreateFrame("ScrollFrame",nil,composeBackground)
    panel.editorScroll=editorScroll
    editorScroll:SetPoint("TOPLEFT",4,-4); editorScroll:SetPoint("BOTTOMRIGHT",-4,34)
    editorScroll:EnableMouseWheel(true); editorScroll:SetScript("OnMouseWheel",wheel)
    panel.editor=field(editorScroll,560,52); panel.editor:SetMultiLine(true); panel.editor:SetMaxBytes(NS.CHAT_DRAFT_BYTES)
    panel.editor.chatFont=true
    panel.editor.focusSurface=composeBackground
    panel.editor:SetCountInvisibleLetters(true); editorScroll:SetScrollChild(panel.editor)
    -- An empty multiline EditBox can shrink to one text line. Capture the
    -- surrounding blank composer area too, so typing never reaches game actions.
    local function focusComposer(_,mouseButton)
        if mouseButton=="LeftButton" then panel.editor:SetFocus() end
    end
    editorScroll:EnableMouse(true); editorScroll:SetScript("OnMouseDown",focusComposer)
    composeBackground:EnableMouse(true); composeBackground:SetScript("OnMouseDown",focusComposer)
    panel.editor:SetScript("OnTextChanged",function(self)
        if displayedId and NS.db.conversations[displayedId] then NS.db.conversations[displayedId].draft=self:GetText() end
        updateComposer()
    end)
    panel.editor:SetScript("OnEnterPressed",send)
    panel.editor:SetScript("OnCursorChanged",function(_,x,y,w,h) followCursor(editorScroll,x,y,w,h) end)
    panel.send=button(composeBackground,"发送",86,27,send,C.green); panel.send:SetPoint("BOTTOMRIGHT",-8,6)
    panel.emoteButton=button(composeBackground,"表情",48,27,showEmotes); panel.emoteButton:SetPoint("BOTTOMLEFT",8,6)
    panel.actionButton=button(composeBackground,"动作",48,27,NS.ShowActions); panel.actionButton:SetPoint("BOTTOMLEFT",60,6)
    panel.counter=text(composeBackground,11,C.muted); panel.counter:SetPoint("BOTTOMLEFT",118,14)
    panel.status=text(panel,11,C.muted)
    panel.status:SetPoint("BOTTOMLEFT",241,12); panel.status:SetPoint("BOTTOMRIGHT",-32,12); panel.status:SetHeight(26)
    panel.deliveryNotice=box("Frame",panel,C.surface,false)
    panel.deliveryNotice.appearanceOpaque=true
    panel.deliveryNotice:SetPoint("BOTTOMLEFT",232,146); panel.deliveryNotice:SetPoint("BOTTOMRIGHT",-14,146)
    panel.deliveryNotice:SetHeight(50)
    panel.deliveryTitle=text(panel.deliveryNotice,13,C.text); panel.deliveryTitle:SetPoint("TOPLEFT",10,-6)
    panel.deliveryTitle:SetMaxLines(1)
    panel.deliveryDetail=text(panel.deliveryNotice,11,C.text); panel.deliveryDetail:SetPoint("TOPLEFT",10,-25)
    panel.deliveryDetail:SetMaxLines(2)
    panel.retrySend=button(panel.deliveryNotice,"重新检查",88,28,function()
        local conv=current(); if not conv or pendingById[conv.id] then return end
        failedById[conv.id]=nil
        if conv.kind=="club" and NS.Communities then NS.Communities.Refresh()
        elseif NS.RequestContactLists then NS.RequestContactLists() end
        if render then render() end
        if contactPresence(conv)=="offline" then status("对方仍然离线，草稿已保留。")
        else status("已重新检查状态；请确认提示后手动发送，插件不会自动重发。") end
    end)
    panel.retrySend:SetPoint("RIGHT",-8,0)
    local resize=button(panel,"◢",22,20,nil); resize:SetPoint("BOTTOMRIGHT",-2,2)
    resize:SetScript("OnMouseDown",function(_,mouse) if mouse=="LeftButton" then panel:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp",function() panel:StopMovingOrSizing(); savePosition() end)
    panel:SetScript("OnSizeChanged",function() dirty=true end)
    local elapsed=0
    panel:SetScript("OnUpdate",function(_,dt) elapsed=elapsed+dt; if dirty and elapsed>=0.05 then elapsed=0; render() end end)
    panel:SetScript("OnShow",function()
        NS.db.shown=true; NS.MarkRead(current().id); dirty=true
        if notifications then notifications:DismissConversation(current().id) end
        openSelectedCommunity()
    end)
    panel:SetScript("OnHide",function()
        openedCommunityThisShow=nil
        NS.db.shown=false; panel.editor:ClearFocus(); panel.contact:ClearFocus(); panel.search:ClearFocus()
        if copyWindow then copyWindow:Hide() end
        if emoteWindow then emoteWindow:Hide() end
        if actionWindow then actionWindow:Hide() end
        if channelSettings then channelSettings:Hide() end
        if NS.appearanceUI and NS.appearanceUI.frame then NS.appearanceUI.frame:Hide() end
        savePosition()
    end)
    launcher=button(UIParent,"聊",42,42,NS.ToggleUI,C.green)
    local launch=type(NS.db.launcher)=="table" and NS.db.launcher or {}
    launcher:SetPoint(validPoints[launch.point] and launch.point or "TOPRIGHT",UIParent,
        validPoints[launch.relativePoint] and launch.relativePoint or "TOPRIGHT",finite(launch.x,-30),finite(launch.y,-235))
    launcher:SetFrameStrata("MEDIUM")
    launcher.badge=text(launcher,12,{1,0.48,0.40,1}); launcher.badge:SetPoint("TOPRIGHT",3,4)
    launcher:SetMovable(true); launcher:SetClampedToScreen(true); launcher:RegisterForDrag("LeftButton")
    launcher:SetScript("OnDragStart",function() launcher:StartMoving(); mfLayout("BeginDrag",launcher) end)
    mfLayout("RegisterLayout",launcher,"微信式聊天 · 图标")
    launcher:SetScript("OnDragStop",function()
        launcher:StopMovingOrSizing()
        mfLayout("SnapToGrid",launcher)
        local p,_,rp,x,y=launcher:GetPoint()
        NS.db.launcher={point=p,relativePoint=rp,x=x,y=y}
    end)
    toastFrames[1]=makeToast()
    clearToasts=button(UIParent,"清除泡泡",116,22,NS.ClearNotifications,C.surface)
    clearToasts:SetFrameStrata("HIGH"); clearToasts:SetClampedToScreen(true); clearToasts:Hide()
    toastPrevious=button(UIParent,"上一组",64,22,function() notifications:Scroll(-1) end,C.surface)
    toastNext=button(UIParent,"下一组",64,22,function() notifications:Scroll(1) end,C.surface)
    for _,control in ipairs({clearToasts,toastPrevious,toastNext}) do
        control:SetFrameStrata("HIGH"); control:SetClampedToScreen(true); control:Hide()
        control.label.appearanceBaseSize=10; updateFont(control.label)
        control:EnableMouseWheel(true); control:SetScript("OnMouseWheel",scrollNotifications)
    end
    toastPage=text(clearToasts,10,C.muted); toastPage:Hide()
    notifications=NS.CreateNotifications({
        canShow=function(id)
            return NS.CanNotifyConversation(NS.db.conversations[id])
        end,
        priority=function(id) return NS.IsPriorityConversation(NS.db.conversations[id]) and 1 or 0 end,
        duration=function(id)
            local conv=NS.db.conversations[id]
            return conv and (isPerson(conv) or conv.kind=="group" or conv.kind=="raid" or conv.kind=="club") and 60 or 20
        end,
        maxVisible=function() return math.floor((UIParent:GetHeight()-toastBase()-120)/toastStep()) end,
        after=function(seconds,callback) C_Timer.After(seconds,callback) end,
        onChange=paintNotifications,
    })
    lastIncoming=NS.lastIncoming and NS.lastIncoming.message
    NS.ui={panel=panel,launcher=launcher,toast=toastFrames[1],toasts=toastFrames,clearToasts=clearToasts,
        conversationRows=conversationRows,messageRows=messageRows,render=render,send=send,
        toastPrevious=toastPrevious,toastNext=toastNext,toastPage=toastPage}
    NS.NotifyChanged=NS.RefreshUI
    NS.GetAppearanceContext=function()
        return {parent=panel,palette=C,box=box,text=text,button=button,registerSurface=registerSurface}
    end
    NS.ApplyAppearance()
    UISpecialFrames[#UISpecialFrames+1]="MyForeverChatWindow"
    if current() and current().kind=="club" then sidebarView="clubs" end
    panel:SetShown(NS.db.shown~=false)
    if panel:IsShown() then NS.MarkRead(current().id); openSelectedCommunity(); render() end
    NS.RefreshUI()
end
