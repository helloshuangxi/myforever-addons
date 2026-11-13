local NS, checks = {}, 0
local function check(value, description) checks=checks+1; assert(value,description) end
local methods, frames = {}, {}
local function luminance(c)
    local total=0
    for i,weight in ipairs({0.2126,0.7152,0.0722}) do
        local v=c[i]; total=total+weight*(v<=0.04045 and v/12.92 or ((v+0.055)/1.055)^2.4)
    end
    return total
end
local function contrast(a,b)
    local x,y=luminance(a),luminance(b)
    return (math.max(x,y)+0.05)/(math.min(x,y)+0.05)
end
local function distinct(a,b)
    return a[1]~=b[1] or a[2]~=b[2] or a[3]~=b[3]
end
local function widthChars(s)
    s=(s or ""):gsub("|H.-|h(.-)|h","%1"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    local _,n=s:gsub("[^\128-\191]","")
    return n
end
function methods:SetScript(name,fn) self.scripts[name]=fn end
function methods:RegisterEvent(name) self.events[name]=true end
function methods:SetText(value)
    self.value=tostring(value or "")
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
end
function methods:GetText() return self.value or "" end
function methods:Insert(value) self:SetText(self:GetText()..value) end
function methods:SetSize(w,h) self.w,self.h=w,h end
function methods:SetWidth(w) self.w=w end
function methods:SetHeight(h) self.h=h end
function methods:ClearAllPoints() self.points={} end
function methods:SetPoint(point,a,b,c,d)
    local parent,rp,x,y
    if type(a)=="table" then parent=a; rp=b or point; x=c or 0; y=d or 0
    else parent=self.parent; rp=point; x=a or 0; y=b or 0 end
    self.points[point]={parent=parent,relativePoint=rp,x=x,y=y}
end
function methods:GetPoint()
    local point,p=next(self.points)
    return point,p.parent,p.relativePoint,p.x,p.y
end
local function axis(point,horizontal)
    if horizontal then
        if point:find("LEFT",1,true) then return 0 elseif point:find("RIGHT",1,true) then return 1 else return 0.5 end
    else
        if point:find("BOTTOM",1,true) then return 0 elseif point:find("TOP",1,true) then return 1 else return 0.5 end
    end
end
local function dimension(self,horizontal)
    local explicit=horizontal and self.w or self.h
    if explicit then return explicit end
    local first,second
    for name,p in pairs(self.points) do
        local ratio=axis(name,horizontal)
        local parentSize=horizontal and p.parent:GetWidth() or p.parent:GetHeight()
        local pos=axis(p.relativePoint,horizontal)*parentSize+(horizontal and p.x or p.y)
        if ratio==0 then first=pos elseif ratio==1 then second=pos end
    end
    if first and second then return second-first end
    return horizontal and 200 or 30
end
function methods:GetWidth() return dimension(self,true) end
function methods:GetHeight() return dimension(self,false) end
function methods:GetFont() return "Font",self.fontSize or 14,"" end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:SetFrameLevel(n) self.frameLevel=n end
function methods:GetUnboundedStringWidth() return widthChars(self:GetText())*8 end
function methods:GetStringHeight() return math.max(1,math.ceil(self:GetUnboundedStringWidth()/math.max(1,self:GetWidth())))*16 end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetBackdropColor(...) self.color={...} end
function methods:SetEnabled(v) self.enabled=v end
function methods:IsEnabled() return self.enabled end
function methods:SetAlpha(v) self.alpha=v end
function methods:SetScrollChild(child) self.child=child end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetVerticalScrollRange() return math.max(0,(self.child and self.child:GetHeight() or 0)-self:GetHeight()) end
function methods:SetVerticalScroll(n) self.scroll=n end
function methods:SetFocus() self.focused=true end
function methods:ClearFocus() self.focused=false end
function methods:HasFocus() return self.focused end
function methods:SetMinMaxValues(low,high) self.minValue,self.maxValue=low,high end
function methods:SetValueStep(value) self.step=value end
function methods:SetObeyStepOnDrag(value) self.obeyStep=value end
function methods:GetValue() return self.sliderValue or self.minValue end
function methods:SetValue(value)
    self.sliderValue=value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end
end
function methods:IsShown() return self.shown end
function methods:Show()
    local old=self.shown; self.shown=true
    if not old and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local old=self.shown; self.shown=false
    if old and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
local noop={"SetBackdrop","SetBackdropBorderColor","SetFont","SetJustifyH","SetJustifyV","SetFontObject","SetAutoFocus","SetTextInsets",
    "SetMaxLines","SetWordWrap","SetNonSpaceWrap","SetHyperlinksEnabled","RegisterForClicks","SetFrameStrata","SetClampedToScreen",
    "EnableMouse","EnableMouseWheel","SetMovable","SetResizable","SetResizeBounds","SetMaxLetters","SetMultiLine","SetMaxBytes",
    "SetCountInvisibleLetters","RegisterForDrag","StartMoving","StopMovingOrSizing","StartSizing","HighlightText","SetOwner","SetHyperlink"}
for _,name in ipairs(noop) do methods[name]=function() end end
function methods:SetOwner(owner) self.owner=owner end
function methods:IsOwned(owner) return self.owner==owner end
function methods:SetFrameStrata(value) self.strata=value end
function methods:EnableMouse(value) self.mouseEnabled=value end
function methods:SetFont(face,size,flags) self.fontFace,self.fontSize,self.fontFlags=face,size,flags end
function methods:SetMaxLines(value) self.maxLines=value end
local function widget(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,scripts={},events={},points={},shown=true,enabled=true},{__index=methods})
    frames[#frames+1]=f
    if name then _G[name]=f end
    if template=="BasicFrameTemplateWithInset" then f.TitleText=setmetatable({scripts={},points={},shown=true,parent=f},{__index=methods}) end
    if template=="UISliderTemplateWithLabels" then
        f.Text=widget("FontString",nil,f); f.Low=widget("FontString",nil,f); f.High=widget("FontString",nil,f)
    end
    return f
end
function methods:CreateFontString() return widget("FontString",nil,self) end
function methods:CreateTexture() return widget("Texture",nil,self) end
function methods:SetTexture(value) self.texture=value end
function methods:SetDesaturated(value) self.desaturated=value end
function methods:SetTexCoord(...) self.coords={...} end
CreateFrame=widget
UIParent=widget("Frame","UIParent"); UIParent:SetSize(1600,1000)
GameTooltip=widget("Frame"); ChatFontNormal={}
SlashCmdList,UISpecialFrames,StaticPopupDialogs={},{},{}
local shownPopup
StaticPopup_Show=function(which,text1,_,data) shownPopup={which=which,text=text1,data=data} end
local timers={}
C_Timer={After=function(delay,fn) timers[#timers+1]={delay=delay,fn=fn} end}
local function expire() local copy=timers; timers={}; for _,timer in ipairs(copy) do timer.fn() end end
date=os.date
GetServerTime=function() return 100000 end
time=function() return 100000 end
local clickTime,control=100,false
GetTime=function() return clickTime end
IsControlKeyDown=function() return control end
GetLocale=function() return "zhCN" end
NameUtil={GetUnmodifiedUnitFullName=function() return "本人-家族" end}
UnitNameUnmodified=function() return "本人","家族" end
UnitGUID=function() return "Player-Self" end
GetChannelList=function() return 1,"综合",false end
GetChannelName=function(id) if id==1 or id=="综合" then return 1,"综合",false end return 0 end
IsInGroup=function() return false end
IsInRaid=function() return false end
IsInGuild=function() return true end
issecretvalue=function() return false end
local sent={}
C_ChatInfo={SendChatMessage=function(message,kind,language,target) sent[#sent+1]={message=message,kind=kind,target=target} end}
local base="_forever_/Interface/AddOns/MyForeverChat/"
assert(loadfile(base.."Core.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Communities.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Profiles.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Emotes.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Actions.lua"))("MyForeverChat",NS)
assert(loadfile(base.."NativeClicks.lua"))("MyForeverChat",NS)
assert(loadfile(base.."ItemLinks.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Notifications.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Keybindings.lua"))("MyForeverChat",NS)
assert(loadfile(base.."UI.lua"))("MyForeverChat",NS)
assert(loadfile(base.."AppearanceUI.lua"))("MyForeverChat",NS)
assert(loadfile(base.."Main.lua"))("MyForeverChat",NS)
local eventFrame
for _,f in ipairs(frames) do if f.events.PLAYER_LOGIN then eventFrame=f end end
eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","MyForeverChat")
eventFrame.scripts.OnEvent(eventFrame,"PLAYER_LOGIN")
local ui=NS.ui; local panel=ui.panel
local function visibleWidget(f)
    while f do
        if not f:IsShown() then return false end
        f=f.parent
    end
    return true
end
local function visibleText(fragment)
    for _,f in ipairs(frames) do
        if f.kind=="FontString" and visibleWidget(f) and f:GetText():find(fragment,1,true) then return f end
    end
end
local function clickNoticeButton(caption)
    for _,f in ipairs(frames) do
        if f.kind=="Button" and f.label and f.label:GetText()==caption and visibleWidget(f) and f:IsEnabled() then
            f.scripts.OnClick(f,"LeftButton"); ui.render(); return true
        end
    end
    error("missing visible enabled notice button: "..caption)
end
check(panel:IsShown() and panel.title:GetText()=="小队","fresh login builds and renders without chat sending")
check(#sent==0,"loading never sends chat")
check(panel.editor.parent.parent:GetHeight()==96,"composer anchor height stays positive")
check(panel.title.points.TOPRIGHT and panel.status.points.BOTTOMRIGHT,"title/status same-edge anchors")
check(panel.history:GetHeight()>200,"history retains visible height")
check(not panel.send.enabled,"empty editor cannot send")
local composerBackground=panel.editor.parent.parent
check(panel.editorScroll.mouseEnabled and composerBackground.mouseEnabled,"empty composer viewport and surrounding padding capture clicks")
panel.editor:ClearFocus(); panel.editorScroll.scripts.OnMouseDown(panel.editorScroll,"RightButton")
check(not panel.editor:HasFocus(),"right clicking composer blank area does not unexpectedly start editing")
panel.editorScroll.scripts.OnMouseDown(panel.editorScroll,"LeftButton")
check(panel.editor:HasFocus() and panel.editor:GetText()=="" and #sent==0,"left clicking blank multiline viewport focuses editor without modifying or sending")
panel.editor:ClearFocus(); composerBackground.scripts.OnMouseDown(composerBackground,"LeftButton")
check(panel.editor:HasFocus() and panel.send.scripts.OnClick and panel.emoteButton.scripts.OnClick and panel.actionButton.scripts.OnClick,
    "composer padding focuses editor while its action buttons retain their click handlers")
panel.editor:ClearFocus()
local function chat(event,msg,author,lineID,guid,channelIndex,channelBase,bnetID)
    eventFrame.scripts.OnEvent(eventFrame,event,msg,author,nil,nil,nil,nil,nil,channelIndex,channelBase,nil,lineID,guid,bnetID)
end
chat("CHAT_MSG_WHISPER","你好","苏氏集团-小王",1)
check(NS.UnreadTotal()==1 and ui.launcher.badge:GetText()=="1","inactive private conversation gains unread badge")
SlashCmdList.MYFOREVERCHAT("reply"); ui.render()
local recipient=NS.GetSelected()
check(recipient.target=="苏氏集团-小王" and NS.UnreadTotal()==0,"reply recent selects exact full recipient and reads conversation")
check(#ui.messageRows>=1 and ui.messageRows[1].content:GetText()=="你好","incoming message renders as bubble")
panel.editor:SetText("我来了")
check(panel.send.enabled and recipient.draft=="我来了","per-conversation draft updates")
panel.editor.scripts.OnEnterPressed(panel.editor)
check(#sent==1 and sent[1].kind=="WHISPER" and sent[1].target=="苏氏集团-小王","Enter uses current exact recipient")
check(panel.editor:GetText()=="我来了" and #recipient.messages==1 and not panel.send.enabled,"submitted text is retained without optimistic echo")
chat("CHAT_MSG_WHISPER_INFORM","我来了","苏氏集团-小王",2); ui.render()
check(panel.editor:GetText()=="" and recipient.draft=="" and #recipient.messages==2,"actual outgoing echo clears matching draft once")
check(contrast(ui.messageRows[2].content.textColor,ui.messageRows[2].bubble.color)>=4.5 and ui.messageRows[2].bubble.points.TOPRIGHT,"own typed bubble keeps readable text and outgoing alignment")
panel.editor:SetText("等一下"); ui.send(); expire()
check(panel.editor:GetText()=="等一下" and not panel.send.enabled,"private timeout preserves draft and blocks repeated Enter until deliberate retry")
panel.editor.scripts.OnEnterPressed(panel.editor); panel.editor.scripts.OnEnterPressed(panel.editor)
check(#sent==2,"timeout never auto-resends")
clickNoticeButton("允许重试")
check(panel.send.enabled and panel.editor:GetText()=="等一下" and #sent==2,"explicit retry acknowledgement preserves draft and does not itself send")
panel.editor:SetText("原稿"); ui.send(); panel.editor:SetText("已经改过的草稿")
chat("CHAT_MSG_WHISPER_INFORM","原稿","苏氏集团-小王",3)
check(panel.editor:GetText()=="已经改过的草稿","late echo never deletes new typing")
panel.editor:SetText("给小王的草稿")
ui.render()
local guildRow
if NS.db.channelsCollapsed then panel.channelsHeader.scripts.OnClick(panel.channelsHeader) end
for _,row in ipairs(ui.conversationRows) do if row.conversation.id=="guild" then guildRow=row end end
guildRow.scripts.OnClick(guildRow,"LeftButton")
check(panel.editor:GetText()=="" and recipient.draft=="给小王的草稿","switch synchronizes composer immediately, preserves previous draft")
panel.editor.scripts.OnEnterPressed(panel.editor)
check(#sent==3,"next-frame Enter never sends old recipient draft to guild")
panel.editor:SetText("公会消息"); ui.send()
check(sent[#sent].kind=="GUILD","guild uses own route")
chat("CHAT_MSG_GUILD","公会消息","本人-家族",4,"Player-Self"); ui.render()
check(panel.editor:GetText()=="","guild echo clears composer")
panel.editor:SetText("留在公会的草稿")
NS.Select("say")
ui.send()
check(#sent==4 and panel.editor:GetText()=="","external selection mismatch is refused, no wrong-target send")
NS.OpenWhisper("另一位-家族"); ui.render()
panel.editor:SetText(string.rep("中",86)); ui.send()
check(#sent==4 and not panel.send.enabled,"overlimit CJK rejected without silent truncation")
panel.editor:SetText("/g 不应作为指令"); ui.send()
check(#sent==4,"slash command cannot be accidentally executed or sent")
panel.editor:SetText("发送失败")
local sender=C_ChatInfo.SendChatMessage
C_ChatInfo.SendChatMessage=function() error("blocked") end
ui.send()
check(panel.editor:GetText()=="发送失败" and panel.send.enabled,"rejected API preserves text and reenables send")
C_ChatInfo.SendChatMessage=sender
NS.ToggleUI()
check(not panel:IsShown() and not NS.db.shown,"close marks visibility false")
chat("CHAT_MSG_WHISPER","还在吗","另一位-家族",5)
check(NS.GetSelected().unread==1,"hidden selected conversation still has unread")
NS.ToggleUI()
check(panel:IsShown() and NS.GetSelected().unread==0,"reopening marks current conversation read")
check(NS.db.window.width==840,"window geometry persisted on hide")
local incoming='|cffaabbcc|Hitem:123|h[物品]|h|r|Tbogus:99999|t'
local itemLink="|cffaabbcc|Hitem:123|h[物品]|h|r"
check(NS.DisplayText(incoming,false)==itemLink,"safe item link retains its native color and strips unrelated textures")
check(NS.DisplayText(incoming,true)=="[物品]","sidebar/copy strips hyperlink controls")
check(NS.DisplayText("|Hmalicious:command|h文字|h",false)=="文字","unknown hyperlink type rendered as plain label")
check(NS.DisplayText("||Hitem:123||h文字||h",false)=="||Hitem:123||h文字||h","escaped markup remains literal")
check(NS.DisplayText("|Hitem:123|h[微笑]|h",false)=="|Hitem:123|h[微笑]|h","emoji token in a link label stays part of the link")
chat("CHAT_MSG_WHISPER",incoming,"另一位-家族",6); ui.render()
local itemRow=ui.messageRows[#NS.GetSelected().messages]
local bubble=itemRow.bubble
check(itemRow.content:GetText()==itemLink,"readable native item color remains visible in the message")
bubble.scripts.OnClick(bubble,"RightButton")
check(MyForeverChatCopy:IsShown() and MyForeverChatCopy.edit:GetText()=="[物品]","right-click copies plain message without sending")
MyForeverChatCopy:Hide()
local mapTarget="worldmap:12:3456:7890"
local mapLink="|H"..mapTarget.."|h[地图坐标]|h"
local tradeLink="|cffffd000|Htrade:Player-123:2259:1:300|h[炼金术]|h|r"
local petLink="|Hbattlepet:42:1:3:160:11:10|h[宠物]|h"
local nativeLinks=mapLink.." "..tradeLink.." "..petLink.." |Haddon:command|h动作|h"
chat("CHAT_MSG_WHISPER",nativeLinks,"另一位-家族",61); ui.render()
local linkRow=ui.messageRows[#NS.GetSelected().messages]
local displayed=linkRow.content:GetText()
check(displayed:match("|cff%x%x%x%x%x%x|Hworldmap:") and displayed:find(tradeLink,1,true) and displayed:find(petLink,1,true),
    "one message can show multiple colored native links")
check(displayed:find("动作",1,true) and not displayed:find("|Haddon:",1,true),"local addon actions remain plain text")
local whiteLink="|cffffffff|Hitem:123|h[物品]|h|r"
local onLight=NS.DisplayText(whiteLink,false,{1,1,1})
check(onLight~=whiteLink and onLight:find("|Hitem:123|h[物品]|h",1,true),"light bubbles recolor low-contrast links without altering the target")
local opened
SetItemRef=function(link,token,mouseButton,frame) opened={link=link,token=token,button=mouseButton,frame=frame} end
linkRow.bubble.scripts.OnHyperlinkClick(linkRow.bubble,mapTarget,"地图坐标","LeftButton")
check(opened and opened.link==mapTarget and opened.token==mapLink and opened.button=="LeftButton" and opened.frame==nil,
    "map link click sends a full hyperlink to the native dispatcher")
IsModifiedClick=function(action) return action=="CHATLINK" end
local draftBeforeLink=panel.editor:GetText()
local sentBeforeLink=#sent
linkRow.bubble.scripts.OnHyperlinkClick(linkRow.bubble,"trade:Player-123:2259:1:300","炼金术","LeftButton")
check(panel.editor:GetText()==draftBeforeLink..tradeLink and panel.editor.focused and #sent==sentBeforeLink,
    "Shift-click inserts the original hyperlink into the draft without sending")
panel.editor:SetText(draftBeforeLink); panel.editor:ClearFocus()
IsModifiedClick=nil; SetItemRef=nil
NS.ShowSystemNotice("系统消息")
check(panel.status:GetText()=="游戏提示：系统消息","system rejection or status remains visible")
panel.editor.scripts.OnCursorChanged(panel.editor,0,-200,1,16)
check(panel.editorScroll:GetVerticalScroll()>0,"composer follows cursor below visible area")
panel.editor.scripts.OnCursorChanged(panel.editor,0,0,1,16)
check(panel.editorScroll:GetVerticalScroll()==0,"composer follows cursor back to first line")
panel.contacts:SetVerticalScroll(500)
panel.search:SetText("另一位"); ui.render()
check(panel.contacts:GetVerticalScroll()==0 and ui.conversationRows[1].conversation.title=="另一位-家族","search resets scrolled contact list and exposes match")
expire()
panel.search:SetText(""); ui.render()
local beforeTarget=#sent
UnitExists=function() return true end
UnitIsPlayer=function() return false end
UnitIsUnit=function() return false end
check(not NS.OpenTargetWhisper() and #sent==beforeTarget,"NPC target cannot become private conversation")
UnitIsPlayer=function() return true end
UnitIsUnit=function() return true end
check(not NS.OpenTargetWhisper(),"self target refused")
UnitIsUnit=function() return false end
NameUtil.GetUnmodifiedUnitFullName=function(unit) return unit=="target" and "叶 落-明月" or "本人-家族" end
SlashCmdList.MYFOREVERCHAT("target")
check(NS.GetSelected().target=="叶 落-明月" and #sent==beforeTarget,"target shortcut resolves full surname without sending")
panel.pin.scripts.OnClick(panel.pin); ui.render()
check(NS.GetSelected().pinned and panel.pin.label:GetText()=="取消置顶","pin management persists and updates label")
panel.mute.scripts.OnClick(panel.mute); ui.render()
check(NS.GetSelected().muted and panel.mute.label:GetText()=="恢复提醒","mute management updates selected state")
NS.ToggleUI()
chat("CHAT_MSG_WHISPER","不用提醒","叶 落-明月",7)
check(NS.GetSelected().unread==1 and ui.launcher.badge:GetText()=="","muted chat keeps unread while suppressing launcher count")
NS.ToggleUI()
panel.allRead.scripts.OnClick(panel.allRead)
check(NS.UnreadTotal()==0,"mark-all-read button clears remaining alert count")
local senderA=NS.GetSelected()
panel.editor:SetText("发给甲"); ui.send()
NS.OpenWhisper("乙-家族"); ui.render()
panel.editor:SetText("发给乙"); ui.send()
check(sent[#sent].target=="乙-家族" and not panel.send.enabled,"pending in A does not block B sending")
chat("CHAT_MSG_WHISPER_INFORM","发给甲","叶 落-明月",8)
check(senderA.draft=="" and panel.editor:GetText()=="发给乙" and not panel.send.enabled,"A echo clears only A pending and draft")
chat("CHAT_MSG_WHISPER_INFORM","发给乙","乙-家族",9)
check(panel.editor:GetText()=="","B echo confirms B independently")
chat("CHAT_MSG_WHISPER","|Hplayer:其他玩家|h玩家名字|h","乙-家族",10); ui.render()
local linkBubble=ui.messageRows[#NS.GetSelected().messages].bubble
local oldId=NS.GetSelected().id
linkBubble.scripts.OnHyperlinkClick(linkBubble,"player:其他玩家","玩家名字","RightButton")
check(NS.GetSelected().id==oldId and MyForeverChatCopy:IsShown(),"right-click player link copies without changing contact")
check(MyForeverChatCopy.strata=="FULLSCREEN_DIALOG" or MyForeverChatCopy.mouseEnabled==true,"copy overlay blocks underlying chat interaction")
-- A reader in the middle of a full history should keep the same message in view.
local conv=NS.GetSelected()
conv.messages={}
for i=1,60 do conv.messages[i]={id="stable"..i,text="消息"..i,author="乙-家族",outgoing=false,time=100000} end
ui.render(); panel.history:SetVerticalScroll(500); ui.render()
local anchor,offset
for _,row in ipairs(ui.messageRows) do
    if row:IsShown() and row.layoutY+row:GetHeight()>panel.history:GetVerticalScroll() then
        anchor=row.message; offset=row.layoutY-panel.history:GetVerticalScroll(); break
    end
end
chat("CHAT_MSG_WHISPER","第61条","乙-家族",1001); ui.render()
local newOffset
for _,row in ipairs(ui.messageRows) do if row.message==anchor then newOffset=row.layoutY-panel.history:GetVerticalScroll() end end
check(newOffset==offset,"history eviction preserves message and screen offset while reading")
panel.editor:SetText("未完草稿")
local refused=NS.DeleteConversation(conv.id)
check(not refused and NS.db.conversations[conv.id],"closing without confirmation preserves draft")
panel.remove.scripts.OnClick(panel.remove)
check(shownPopup.which=="MYFOREVERCHAT_DELETE" and shownPopup.text=="乙-家族" and NS.db.conversations[conv.id],"delete button shows named confirmation before removing anything")
StaticPopupDialogs[shownPopup.which].OnAccept(nil,shownPopup.data); ui.render()
check(not NS.db.conversations[conv.id] and panel.title:GetText()=="小队","confirmed deletion selects safe fallback")
SlashCmdList.MYFOREVERCHAT("reset")
check(panel:IsShown() and NS.db.window.width==840,"reset command restores usable window position")
-- Observing a selected passerby adds only a recent person and preserves the draft.
panel.search:SetText(""); ui.render()
local oldSelected=NS.GetSelected().id
panel.editor:SetText("仍在当前会话的草稿")
local sentBefore=#sent
NameUtil.GetUnmodifiedUnitFullName=function(unit) return unit=="target" and "路过 玩家-家族" or "本人-家族" end
UnitGUID=function(unit) return unit=="target" and "Player-Passerby" or "Player-Self" end
UnitExists=function() return true end; UnitIsPlayer=function() return true end; UnitIsUnit=function() return false end
UnitClass=function() return "牧师","PRIEST" end
UnitLevel=function() return 23 end
UnitRace=function() return "人类","Human" end
UnitSex=function() return 2 end
CLASS_ICON_TCOORDS={PRIEST={0.5,0.75,0.25,0.5}}
SetPortraitTexture=function(texture,unit) texture.portraitUnit=unit end
eventFrame.scripts.OnEvent(eventFrame,"PLAYER_TARGET_CHANGED"); ui.render()
local discovered
for _,entry in ipairs(NS.GetConversations()) do if entry.target=="路过 玩家-家族" then discovered=entry end end
check(not discovered and #sent==sentBefore,"selecting a player neither creates a conversation nor sends")
check(NS.GetSelected().id==oldSelected and panel.editor:GetText()=="仍在当前会话的草稿","discovery preserves selected conversation and draft")
panel.contactsTab.scripts.OnClick(panel.contactsTab)
check(panel.rosterHeaders[1].label:GetText():find("游戏好友",1,true) and panel.rosterHeaders[2].label:GetText():find("通行证好友",1,true)
    and panel.rosterHeaders[3].label:GetText():find("最近的人",1,true),"contacts tab shows three distinct lists")
local personRow
for _,row in ipairs(ui.conversationRows) do
    if row:IsShown() and row.isContact and row.conversation.target=="路过 玩家-家族" then personRow=row end
end
check(personRow and personRow.detail:GetText()=="23级 · 牧师 · 人类","person row displays level class and race")
check(personRow.avatar.portrait.portraitUnit=="target" and not personRow.letter:IsShown(),"matching target uses actual portrait")
UnitExists=function() return false end
ui.render()
check(personRow.avatar.portrait.texture=="Interface\\TargetingFrame\\UI-Classes-Circles","target departure falls back to correct class portrait")
personRow.scripts.OnClick(personRow,"LeftButton")
check(not NS.db.conversations[personRow.conversation.id] and NS.GetSelected().id==oldSelected,"single click on recent person leaves conversations alone")
check(not control,"addon contact double-click is tested without holding Ctrl")
clickTime=clickTime+0.2; personRow.scripts.OnClick(personRow,"LeftButton")
discovered=NS.GetSelected()
check(discovered.target=="路过 玩家-家族" and #discovered.messages==0 and #sent==sentBefore,"plain double-click deliberately opens the correct contact without sending")
if not NS.db.channelsCollapsed then panel.channelsHeader.scripts.OnClick(panel.channelsHeader) end
ui.render()
check(NS.db.channelsCollapsed and panel.channelsHeader.label:GetText():find("频道",1,true),"channels collapse under a single heading")
local hasPublic=false
for _,row in ipairs(ui.conversationRows) do
    if row:IsShown() and row.conversation.kind~="whisper" and not NS.IsPriorityConversation(row.conversation) then hasPublic=true end
end
check(not hasPublic,"folded public channels stay hidden while priority conversations remain")
check(ui.conversationRows[1]:IsShown() and ui.conversationRows[1].conversation.id=="guild"
    and ui.conversationRows[2]:IsShown() and ui.conversationRows[2].conversation.id=="group"
    and ui.conversationRows[3]:IsShown() and ui.conversationRows[3].conversation.id=="raid",
    "guild party and raid are independently fixed above folded channel and person sections")
local added,friendConfirmed=0,false
C_FriendList={
    GetFriendInfo=function(name) if friendConfirmed then return {name=name,guid="Player-Passerby"} end end,
    AddFriend=function(name) added=added+1; check(name=="路过 玩家-家族","friend button preserves complete name") end,
}
ui.render(); panel.addFriend.scripts.OnClick(panel.addFriend)
check(added==1 and panel.addFriend.label:GetText()=="添加中","friend button submits once and waits for actual confirmation")
friendConfirmed=true; eventFrame.scripts.OnEvent(eventFrame,"FRIENDLIST_UPDATE"); ui.render()
check(panel.addFriend.label:GetText()=="已是好友" and not panel.addFriend.enabled,"friend event confirms real friend state")
panel.editor:SetText(""); panel.emoteButton.scripts.OnClick(panel.emoteButton)
check(ui.emotes:IsShown() and #ui.emotes.buttons==12,"expression picker offers twelve faces")
ui.emotes.buttons[1].scripts.OnClick(ui.emotes.buttons[1])
check(panel.editor:GetText()=="[微笑]" and #sent==sentBefore,"choosing face inserts portable token without auto sending")
check(NS.DisplayText("[微笑]",false):find("Media\\Emotes\\smile:20:20",1,true),"received expression token displays approved local image")
check(NS.DisplayText("|Tbad:99999|t[微笑]",false):find("bad",1,true)==nil,"arbitrary received textures remain stripped")
panel.editor:SetText("")
panel.minimize.scripts.OnClick(panel.minimize)
check(not panel:IsShown() and not NS.db.shown,"explicit minimize hides chat while keeping receiver active")
chat("CHAT_MSG_WHISPER","看这里[微笑]","路过 玩家-家族",2001)
check(ui.toast:IsShown() and ui.toast.conversationId==discovered.id,"incoming message while minimized shows exact conversation toast")
check(ui.toast.preview:GetText()=="看这里[微笑]","toast previews incoming message")
ui.toast.scripts.OnClick(ui.toast,"LeftButton"); ui.render()
check(panel:IsShown() and NS.GetSelected().id==discovered.id and not ui.toast:IsShown() and discovered.unread==0,"clicking bubble opens correct chat and marks read")
NS.ToggleMute(discovered.id); NS.MinimizeUI()
chat("CHAT_MSG_WHISPER","不要弹泡泡","路过 玩家-家族",2002)
check(not ui.toast:IsShown() and discovered.unread==1,"muted new messages preserve unread without popup")
NS.ToggleMute(discovered.id)
chat("CHAT_MSG_WHISPER","新消息","路过 玩家-家族",2003)
check(ui.toast:IsShown(),"unmuted subsequent message shows notification")
ui.toast.scripts.OnClick(ui.toast,"RightButton")
check(not ui.toast:IsShown() and not panel:IsShown(),"right click dismisses only notification")
chat("CHAT_MSG_WHISPER_INFORM","出站不提醒","路过 玩家-家族",2004)
check(not ui.toast:IsShown(),"outgoing echo never creates notification bubble")
chat("CHAT_MSG_WHISPER","提醒会自然消失","路过 玩家-家族",2005)
local quiet=NS.OpenWhisper("静音联系人-家族")
NS.Select(discovered.id)
NS.ToggleMute(quiet.id)
chat("CHAT_MSG_WHISPER","静音消息","静音联系人-家族",2006)
check(ui.toast:IsShown() and ui.toast.conversationId==discovered.id,"muted message cannot replace existing unmuted toast")
expire()
check(not ui.toast:IsShown(),"muted incoming cannot cancel older toast expiry")
GetPlayerInfoByGUID=function() return "法师","MAGE","侏儒","Gnome",2,"不应使用的短名","不应拼接的服务器",31 end
chat("CHAT_MSG_WHISPER","带资料的私聊","陌生 完整名-家族",2010,"Player-Profile")
local incomingPerson
for _,entry in ipairs(NS.GetConversations()) do if entry.target=="陌生 完整名-家族" then incomingPerson=entry end end
check(incomingPerson and incomingPerson.profile.classToken=="MAGE" and incomingPerson.profile.level==31,"incoming GUID enriches person class and level without target selection")
check(ui.toast.conversationId==incomingPerson.id,"profile enrichment preserves exact incoming notification identity")
NS.ToggleUI(); ui.render()
local previousDraft=panel.editor:GetText()
local countBeforeAppearance=#sent
NS.UpdateAppearance({fontSize=22,opacity=0.4,theme="ocean",background={0.04,0.065,0.1},accent={0.32,0.65,0.95}}); ui.render()
check(panel.editor.fontSize==22 and ui.messageRows[1].content.fontSize==22,"font setting immediately updates composer and actual message text")
check(panel.contact.fontSize==14 and panel.search.fontSize==14,"compact search and name controls retain readable unclipped font")
check(panel.color[4]==0.4 and panel.editor.alpha==nil,"background opacity changes backdrop while text remains opaque")
check(panel.color[1]==0.04 and panel.color[3]==0.1,"custom window color applies immediately")
check(NS.db.appearance.fontSize==22 and NS.db.appearance.opacity==0.4,"appearance change persists in character DB")
check(panel.editor:GetText()==previousDraft and #sent==countBeforeAppearance,"appearance does not alter drafts or send chat")
local tallPerson
for _,row in ipairs(ui.conversationRows) do if row:IsShown() and row.conversation.kind=="whisper" then tallPerson=row; break end end
check(tallPerson and tallPerson:GetHeight()>75 and tallPerson.detail.fontSize==19,"larger list font grows person row to avoid clipping")
RAID_CLASS_COLORS={PRIEST={r=1,g=1,b=1}}
NS.UpdateAppearance({background={1,1,1},accent={0,0,0},theme="custom"}); ui.render()
check(panel.editor.textColor[1]<0.1,"light background switches input to readable dark text")
check(ui.messageRows[1].content.textColor[1]<0.1,"light incoming bubbles use readable text")
local readablePriest
for _,row in ipairs(ui.conversationRows) do
    if row:IsShown() and row.conversation.profile and row.conversation.profile.classToken=="PRIEST" then readablePriest=row; break end
end
check(readablePriest and readablePriest.name.textColor[1]<0.1,"priest class white cannot disappear against a custom white background")
NS.ResetAppearance(); ui.render()
check(panel.editor.fontSize==14 and NS.db.appearance.opacity==0.98 and panel.editor:GetText()==previousDraft,"reset restores appearance without clearing draft")
NS.MinimizeUI(); SlashCmdList.MYFOREVERCHAT("settings")
check(panel:IsShown() and NS.appearanceUI.frame:IsShown(),"settings shortcut opens real integrated settings panel from minimized state")
NS.appearanceUI.fontSlider:SetValue(18); ui.render()
check(panel.editor.fontSize==18 and NS.db.appearance.fontSize==18,"actual settings slider applies font through real styling pipeline")
NS.appearanceUI.opacitySlider:SetValue(30)
check(panel.color[4]==0.3 and NS.appearanceUI.frame.color[4]>=0.94,"transparent chat keeps settings dialog readable")
NS.appearanceUI.reset.scripts.OnClick(NS.appearanceUI.reset); ui.render()
check(panel.editor.fontSize==14 and panel.editor:GetText()==previousDraft,"integrated restore defaults preserves live draft")
NS.appearanceUI.frame:Hide()
-- Avatar online and do-not-disturb states are independent.
local online=true
C_FriendList.GetFriendInfo=function(name)
    if name==discovered.target then return {name=name,guid="Player-Passerby",connected=online} end
end
NS.Select(discovered.id); ui.render()
local function rowFor(id)
    for _,row in ipairs(ui.conversationRows) do if row:IsShown() and row.conversation.id==id then return row end end
end
local badgeRow=rowFor(discovered.id)
check(badgeRow.avatar.presenceBadge.texture:find("\\online",1,true) and panel.subtitle:GetText():find("在线",1,true),"known online friend has avatar marker and label")
NS.ToggleMute(discovered.id); ui.render()
check(badgeRow.avatar.muteBadge:IsShown() and badgeRow.avatar.presenceBadge.texture:find("\\online",1,true),"muted online contact keeps both independent indicators")
online=false; eventFrame.scripts.OnEvent(eventFrame,"FRIENDLIST_UPDATE"); ui.render()
check(badgeRow.avatar.presenceBadge.texture:find("\\offline",1,true) and badgeRow.avatar.portrait.desaturated,"verified offline contact grays avatar")
C_FriendList.GetFriendInfo=function() return nil end
UnitExists=function() return false end
eventFrame.scripts.OnEvent(eventFrame,"UNIT_CONNECTION","target",false); ui.render()
check(badgeRow.avatar.presenceBadge.texture:find("\\unknown",1,true) and not badgeRow.avatar.portrait.desaturated,"unknown presence does not gray avatar as if offline")
NS.ToggleMute(discovered.id)
-- Opening one toast leaves another contact's toast available.
NS.ClearNotifications(); NS.MinimizeUI()
chat("CHAT_MSG_WHISPER","第一条","路过 玩家-家族",2021)
chat("CHAT_MSG_WHISPER","第二条","陌生 完整名-家族",2022)
check(ui.toasts[1]:IsShown() and ui.toasts[2]:IsShown(),"multiple new messages have separate visible toasts")
check(timers[#timers].delay==60,"private toast remains available for sixty seconds")
ui.toasts[1].scripts.OnClick(ui.toasts[1],"LeftButton"); ui.render()
check(NS.GetSelected().id==discovered.id and ui.toasts[1]:IsShown() and ui.toasts[1].conversationId==incomingPerson.id,"opening one chat does not dismiss other conversation notification")
local unreadBeforeClear=NS.UnreadTotal()
ui.clearToasts.scripts.OnClick(ui.clearToasts)
check(not ui.toasts[1]:IsShown() and not ui.clearToasts:IsShown() and NS.UnreadTotal()==unreadBeforeClear,"clear all hides notifications without marking messages read")
expire()
check(not ui.toasts[1]:IsShown(),"old expiry timers cannot reopen cleared notifications")
local untouched=NS.GetSelected()
local otherRow=rowFor(incomingPerson.id)
otherRow.scripts.OnClick(otherRow,"RightButton")
check(shownPopup.data==incomingPerson and NS.GetSelected()==untouched,"right-click delete confirmation does not change current chat")
StaticPopupDialogs[shownPopup.which].OnAccept(nil,shownPopup.data); ui.render()
check(NS.GetSelected()==untouched and not NS.db.conversations[incomingPerson.id],"delete from list leaves another active conversation untouched")
local bnetAccount={bnetAccountID=82,battleTag="同名好友#1234",accountName="通行证好友",gameAccountInfo={isOnline=true}}
local battleNetSent
BNGetNumFriends=function() return 1 end
C_BattleNet={
    GetFriendAccountInfo=function() return bnetAccount end,
    GetAccountInfoByID=function(id) if id==82 then return bnetAccount end end,
    SendWhisper=function(id,body) battleNetSent={id=id,body=body}; return true end,
}
C_FriendList.GetNumFriends=function() return 1 end
C_FriendList.GetFriendInfoByIndex=function() return {name="角色好友-家族",connected=false} end
panel.contactsTab.scripts.OnClick(panel.contactsTab)
panel.rosterHeaders[1].scripts.OnClick(panel.rosterHeaders[1]); panel.rosterHeaders[2].scripts.OnClick(panel.rosterHeaders[2])
local bnetRow
for _,row in ipairs(ui.conversationRows) do
    if row:IsShown() and row.isContact and row.conversation.kind=="bnet" then bnetRow=row end
end
check(bnetRow and bnetRow.avatar.presenceBadge.texture:find("\\online",1,true)
    and rowFor("whisper:角色好友-家族"),"game and Battle.net friends display in separate contact sections")
local beforeBnetOpen=NS.GetSelected()
bnetRow.scripts.OnClick(bnetRow,"LeftButton")
check(NS.GetSelected()==beforeBnetOpen,"single click on Battle.net contact cannot create a chat")
clickTime=clickTime+0.2; bnetRow.scripts.OnClick(bnetRow,"LeftButton")
check(NS.GetSelected().kind=="bnet" and NS.GetSelected().target==bnetAccount.battleTag and not battleNetSent,
    "plain double-click opens only the corresponding Battle.net conversation")
panel.editor:SetText("通行证测试"); ui.send()
check(battleNetSent and battleNetSent.id==82 and battleNetSent.body=="通行证测试" and not panel.send.enabled,
    "Battle.net conversation sends through Battle.net API with current account ID")
chat("CHAT_MSG_BN_WHISPER_INFORM","通行证测试","通行证好友",3001,nil,nil,nil,82); ui.render()
check(panel.editor:GetText()=="" and #NS.GetSelected().messages==1,"Battle.net echo confirms and clears only that draft")
chat("CHAT_MSG_BN_WHISPER","你好","通行证好友",3002,nil,nil,nil,82); ui.render()
check(#NS.GetSelected().messages==2 and NS.db.lastWhisperId==NS.GetSelected().id,"Battle.net incoming is visible and available for reply")
local actionToken
C_ChatInfo.PerformEmote=function(token) actionToken=token end
panel.editor:SetText("保留这段草稿")
panel.actionButton.scripts.OnClick(panel.actionButton)
check(ui.actions:IsShown() and ui.actions.buttons[1].label:GetText()=="/跳舞","action menu opens with localized action shortcuts")
ui.actions.search:SetText("招手")
check(ui.actions.buttons[1].action.token=="WAVE" and not ui.actions.buttons[2]:IsShown(),"action menu search matches localized command")
ui.actions.buttons[1].scripts.OnClick(ui.actions.buttons[1])
check(actionToken=="WAVE" and not ui.actions:IsShown() and panel.editor:GetText()=="保留这段草稿",
    "action button calls native emote without consuming the chat draft")
MyForeverChat_Action("DANCE")
check(actionToken=="DANCE","registered action binding reaches the same native emote path")
NS.Select("say"); ui.render()
chat("CHAT_MSG_SAY","路过","附近 玩家-家族",4001); ui.render()
local speaker=ui.messageRows[#NS.GetSelected().messages].author
speaker.scripts.OnClick(speaker,"LeftButton")
check(NS.GetSelected().id=="say" and not NS.db.conversations["whisper:附近 玩家-家族"],"ordinary click on a message author leaves chats alone")
clickTime=clickTime+0.2; speaker.scripts.OnClick(speaker,"LeftButton")
check(NS.GetSelected().target=="附近 玩家-家族","plain double-click on a message author opens its exact player")
NS.Select("say"); ui.render()
local speakerAvatar=ui.messageRows[#NS.GetSelected().messages].avatar
speakerAvatar.scripts.OnClick(speakerAvatar,"LeftButton")
check(NS.GetSelected().id=="say","single message-avatar click preserves the selected conversation")
clickTime=clickTime+0.2; speakerAvatar.scripts.OnClick(speakerAvatar,"LeftButton")
check(not control and NS.GetSelected().target=="附近 玩家-家族","plain double-click on a message avatar opens its exact player")
local customItems={}
for i=1,13 do customItems[i]={id="face_"..i,label="表情 "..i} end
MyForeverChatEmotePacks={friend_set={title="好友表情",items=customItems}}
panel.emoteButton.scripts.OnClick(panel.emoteButton)
eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","MyForeverChatEmotes_friend_set")
check(ui.emotes.nextGroup:IsEnabled(),"pack loading refreshes the open picker")
ui.emotes.nextGroup.scripts.OnClick(ui.emotes.nextGroup)
check(ui.emotes.buttons[1].icon.texture:find("MyForeverChatEmotes_friend_set",1,true) and ui.emotes.nextPage:IsEnabled(),
    "installed pack has its own page and texture paths")
ui.emotes.nextPage.scripts.OnClick(ui.emotes.nextPage)
check(ui.emotes.buttons[1].emote.key=="face_13" and not ui.emotes.buttons[2]:IsShown(),"last page shows only the remaining custom emotes")
local sentBeforeEmote=#sent
panel.editor:SetText("")
ui.emotes.buttons[1].scripts.OnClick(ui.emotes.buttons[1])
check(panel.editor:GetText()=="[表情:friend_set:face_13]" and #sent==sentBeforeEmote,"selecting a custom emote only inserts its shareable token")
chat("CHAT_MSG_WHISPER","[表情:friend_set:face_13]","附近 玩家-家族",4002); ui.render()
check(ui.messageRows[#NS.GetSelected().messages].content:GetText():find("Media\\face_13:20:20",1,true),
    "incoming custom token renders as the matching local texture")
local nativeLink="|cnIQ4:|Hitem:123:"..string.rep("0:",150).."|h[装备]|h|r"
panel.editor:SetText("给你 "); panel.editor:ClearFocus()
check(not NS.InsertNativeItemLink(nativeLink) and panel.editor:GetText()=="给你 ","unfocused composer does not take a native item link")
panel.editor:SetFocus()
check(NS.InsertNativeItemLink(nativeLink) and panel.editor:GetText()=="给你 "..nativeLink and #sent==sentBeforeEmote,
    "focused composer inserts the entire native link without sending")
check(panel.send.enabled and panel.counter:GetText():find(#"给你 [装备]".."/255",1,true),"long link remains sendable and counter uses visible bytes")
ui.send()
check(sent[#sent].message=="给你 "..nativeLink and sent[#sent].target=="附近 玩家-家族","send delivers the whole native link to the selected contact")
chat("CHAT_MSG_WHISPER_INFORM","给你 "..nativeLink,"附近 玩家-家族",4003)
check(panel.editor:GetText()=="","exact native link echo confirms delivery and clears draft")
panel.editor:SetText(string.rep("a",NS.CHAT_DRAFT_BYTES-4)); panel.editor:SetFocus()
check(NS.InsertNativeItemLink(nativeLink) and #panel.editor:GetText()==NS.CHAT_DRAFT_BYTES-4,
    "composer consumes an over-capacity link without truncating the draft or hyperlink")
-- Ctrl-X selects a visible notification, never sends it, and preserves drafts.
NS.ClearNotifications(); NS.MinimizeUI()
local sentBeforeShortcut=#sent
chat("CHAT_MSG_WHISPER","较早的泡泡","快捷甲-家族",5001)
chat("CHAT_MSG_WHISPER","最新的泡泡","快捷乙-家族",5002)
check(ui.toasts[1]:IsShown() and ui.toasts[2]:IsShown(),"two new conversations have visible shortcut targets")
NS.QuickReply()
check(panel:IsShown() and NS.GetSelected().target=="快捷乙-家族" and panel.editor:HasFocus(),"shortcut opens newest visible bubble and focuses composer")
check(ui.toasts[1]:IsShown() and ui.toasts[1].conversationId=="whisper:快捷甲-家族" and not ui.toasts[2]:IsShown(),
    "shortcut dismisses only the opened conversation's bubbles")
panel.editor:SetText("不要剪切这段草稿"); panel.editor:SetFocus()
control=true; panel.editor.scripts.OnKeyDown(panel.editor,"X"); control=false
check(not panel:IsShown() and not panel.editor:HasFocus() and NS.GetSelected().draft=="不要剪切这段草稿",
    "focused composer Ctrl-X minimizes and preserves the draft")
check(panel.editor:GetText()=="不要剪切这段草稿","minimize does not alter editor text")
NS.QuickReply()
check(NS.GetSelected().target=="快捷甲-家族" and panel:IsShown(),"next shortcut replies to the remaining visible bubble")
NS.MinimizeUI()
chat("CHAT_MSG_WHISPER","悬停的泡泡","快捷甲-家族",5003)
chat("CHAT_MSG_WHISPER","更晚的泡泡","快捷乙-家族",5004)
ui.toasts[1].IsMouseOver=function() return true end
NS.QuickReply()
check(NS.GetSelected().target=="快捷甲-家族","hovered older bubble has priority over newest visible bubble")
ui.toasts[1].IsMouseOver=nil
NS.MinimizeUI(); NS.ClearNotifications(); NS.QuickReply()
check(NS.GetSelected().target=="快捷乙-家族" and panel.editor:GetText()=="不要剪切这段草稿",
    "no-bubble fallback restores recent private conversation's own draft")
NS.db.lastWhisperId="whisper:missing"; NS.MinimizeUI(); NS.QuickReply()
check(panel:IsShown() and NS.GetSelected().target=="快捷乙-家族","missing last private conversation safely reopens current conversation")
NS.QuickReply()
check(not panel:IsShown(),"shown window always minimizes even if bubbles remain")
check(#sent==sentBeforeShortcut,"all shortcut paths open or minimize without sending any chat")
-- Priority conversations remain discoverable independently of collapsed lists.
NS.ClearNotifications(); NS.ResetAppearance()
if not panel:IsShown() then NS.ToggleUI() end
panel.search:SetText(""); NS.db.peopleCollapsed=true; NS.db.channelsCollapsed=true; ui.render()
local priorityIDs={"guild","group","raid"}
for index,id in ipairs(priorityIDs) do
    local row=ui.conversationRows[index]
    check(row:IsShown() and row.conversation.id==id and not row.isContact,"priority category stays at top even with both sections folded: "..id)
    row.scripts.OnClick(row,"LeftButton")
    check(NS.GetSelected().id==id and panel.pin.label:GetText()=="固定置顶","priority row selects its own sending audience: "..id)
end
check(distinct(ui.conversationRows[1].typeStripe.color,ui.conversationRows[2].typeStripe.color)
    and distinct(ui.conversationRows[2].typeStripe.color,ui.conversationRows[3].typeStripe.color),"fixed categories have distinct visual color indicators")
local categoryColors={}
for index,case in ipairs({{"guild","CHAT_MSG_GUILD","公会"},{"group","CHAT_MSG_PARTY","小队"},{"raid","CHAT_MSG_RAID","团队"}}) do
    chat(case[2],itemLink,"类型测试-家族",7000+index)
    NS.Select(case[1]); ui.render()
    local row=ui.messageRows[#NS.GetSelected().messages]
    categoryColors[case[1]]=row.bubble.color
    check(row.meta:GetText():find("["..case[3].."]",1,true) and contrast(row.content.textColor,row.bubble.color)>=4.5,
        "category label and body remain readable: "..case[1])
    check(row.content:GetText()==itemLink,"category tint preserves readable native item link color: "..case[1])
end
check(distinct(categoryColors.guild,categoryColors.group) and distinct(categoryColors.group,categoryColors.raid)
    and distinct(categoryColors.guild,categoryColors.raid),"guild party and raid use different history bubble colors")
chat("CHAT_MSG_INSTANCE_CHAT","副本消息","类型测试-家族",7010); NS.Select("group"); ui.render()
local instanceRow=ui.messageRows[#NS.GetSelected().messages]
check(instanceRow.meta:GetText():find("[副本]",1,true) and distinct(instanceRow.bubble.color,categoryColors.group),
    "instance messages retain their own color inside the party conversation")
chat("CHAT_MSG_SAY","附近消息","类型测试-家族",7011)
chat("CHAT_MSG_YELL","喊话消息","类型测试-家族",7012); NS.Select("say"); ui.render()
local recentCount=#NS.GetSelected().messages
check(ui.messageRows[recentCount].meta:GetText():find("[喊话]",1,true)
    and distinct(ui.messageRows[recentCount-1].bubble.color,ui.messageRows[recentCount].bubble.color),
    "say and yell remain distinguishable within the shared nearby history")
NS.UpdateAppearance({background={1,1,1},accent={0.95,0.95,0.95},theme="custom"}); ui.render()
check(contrast(ui.messageRows[recentCount].content.textColor,ui.messageRows[recentCount].bubble.color)>=4.5,
    "typed history text stays readable on a custom light theme")
check(contrast(ui.conversationRows[1].name.textColor,ui.conversationRows[1].color)>=4.5,
    "fixed category heading stays readable on a custom light theme")
NS.ResetAppearance(); NS.ClearNotifications(); NS.MinimizeUI()
chat("CHAT_MSG_WHISPER","先到的私聊","颜色私聊-家族",7020)
chat("CHAT_MSG_GUILD","随后公会","类型测试-家族",7021)
check(ui.toasts[1].conversationId=="guild" and ui.toasts[2].conversationId=="whisper:颜色私聊-家族",
    "important message bubbles appear above existing ordinary chat")
check(ui.toasts[1].title:GetText():find("[公会]",1,true) and distinct(ui.toasts[1].color,ui.toasts[2].color)
    and contrast(ui.toasts[1].preview.textColor,ui.toasts[1].color)>=4.5,
    "notification bubbles carry a readable category label and distinct color")
NS.QuickReply()
check(NS.GetSelected().id=="guild","quick reply follows newest arrival even when priority puts it at the top")
check(#sent==sentBeforeShortcut,"category display and quick reply never send chat on their own")
-- Sender identity and available profile details belong to each message, not its channel.
local originalMessageProfile=NS.GetMessageProfile
NS.GetMessageProfile=function() return {level=32,className="法师",classToken="MAGE"} end
for index,case in ipairs({{"guild","CHAT_MSG_GUILD",20},{"group","CHAT_MSG_PARTY",60},
    {"raid","CHAT_MSG_RAID",60},{"channel:综合","CHAT_MSG_CHANNEL",20}}) do
    NS.SetChannelRemindersEnabled(case[2]=="CHAT_MSG_CHANNEL")
    NS.ClearNotifications(); NS.MinimizeUI()
    chat(case[2],"发言内容","发言家族 发言名字",7100+index,"Player-Speaker",1,"综合")
    local toast=ui.toasts[1]
    check(toast:IsShown() and toast.sender:GetText()=="发言家族 发言名字" and not toast.senderDetail and not toast.hint,
        "compact public/team bubble keeps sender visible without persistent detail or operation rows: "..case[1])
    toast.scripts.OnEnter(toast)
    check(GameTooltip:IsOwned(toast) and GameTooltip:GetText():find("发言家族 发言名字",1,true)
        and GameTooltip:GetText():find("32级 · 法师",1,true) and GameTooltip:GetText():find("Ctrl+X",1,true)
        and GameTooltip:GetText():find("滚轮",1,true) and GameTooltip:GetText():find("右键",1,true),
        "notification hover preserves full sender profile and reply/paging/dismiss instructions: "..case[1])
    toast.scripts.OnLeave(toast)
    check(timers[#timers].delay==case[3],"category notification has its requested lifetime: "..case[1])
    toast.scripts.OnClick(toast,"LeftButton"); ui.render()
    local row=ui.messageRows[#NS.GetSelected().messages]
    check(row.meta:GetText():find("发言家族 发言名字",1,true) and row.senderDetail:GetText():find("32级 · 法师",1,true),
        "history retains sender and level/class separately from content: "..case[1])
end
NS.SetChannelRemindersEnabled(false)
NS.GetMessageProfile=function() return {} end
NS.ClearNotifications(); NS.MinimizeUI()
chat("CHAT_MSG_GUILD","不猜等级","资料未知的玩家",7120)
ui.toasts[1].scripts.OnEnter(ui.toasts[1])
check(ui.toasts[1].sender:GetText()=="资料未知的玩家" and not GameTooltip:GetText():match("%d+级"),
    "unknown player level is omitted from compact notification hover rather than invented")
ui.toasts[1].scripts.OnLeave(ui.toasts[1])
NS.GetMessageProfile=originalMessageProfile
-- Paging works with the same clickable bubbles, without restarting active timers.
NS.ClearNotifications(); NS.MinimizeUI(); UIParent:SetSize(1600,560)
for index=1,6 do chat("CHAT_MSG_WHISPER","分页 "..index,"分页玩家-家族",7200+index) end
check(ui.toastPrevious:IsShown() and not ui.toastPrevious:IsEnabled() and ui.toastNext:IsEnabled()
    and ui.toastPage:GetText():find("1–3 / 6",1,true),"small screen exposes correct range and paging controls")
local timersBeforePage=#timers
ui.toasts[1].scripts.OnMouseWheel(ui.toasts[1],-1)
check(ui.toasts[1].item.message.text=="分页 4" and ui.toastPrevious:IsEnabled() and not ui.toastNext:IsEnabled()
    and ui.toastPage:GetText():find("4–6 / 6",1,true),"wheel down reaches later notification group")
check(#timers==timersBeforePage+3,"first viewing the next group starts each private bubble timer once")
ui.toastPrevious.scripts.OnClick(ui.toastPrevious)
check(ui.toasts[1].item.message.text=="分页 1" and #timers==timersBeforePage+3,
    "previous button restores earlier active bubbles without extending their timers")
ui.toastNext.scripts.OnClick(ui.toastNext)
check(ui.toasts[1].item.message.text=="分页 4","next button reaches the same later group")
ui.toasts[1].scripts.OnMouseWheel(ui.toasts[1],1)
check(ui.toasts[1].item.message.text=="分页 1","wheel up returns to earlier active bubbles")
ui.clearToasts.scripts.OnClick(ui.clearToasts)
check(not ui.toastPrevious:IsShown() and not ui.toastNext:IsShown() and not ui.toastPage:IsShown(),
    "clearing all bubbles also hides paging controls")
check(#sent==sentBeforeShortcut,"paging and sender display never send messages")
-- A hovered frame can be reused on page changes without firing OnEnter again.
NS.ClearNotifications(); NS.MinimizeUI()
NS.GetMessageProfile=function(author)
    return {level=30+tonumber(author:match("(%d+)$")),className="法师",classToken="MAGE"}
end
for index=1,6 do chat("CHAT_MSG_WHISPER","悬停分页 "..index,"浮层作者"..index,7300+index) end
local reusedToast=ui.toasts[1]
reusedToast.scripts.OnEnter(reusedToast)
check(GameTooltip:IsOwned(reusedToast) and GameTooltip:GetText():find("浮层作者1",1,true),"hover begins with the visible sender")
reusedToast.scripts.OnMouseWheel(reusedToast,-1)
check(reusedToast.sender:GetText()=="浮层作者4" and GameTooltip:GetText():find("浮层作者4",1,true)
    and GameTooltip:GetText():find("34级",1,true),"paging a hovered frame refreshes tooltip sender and level together")
reusedToast.scripts.OnLeave(reusedToast)
ui.toastPrevious.scripts.OnClick(ui.toastPrevious)
check(not GameTooltip:IsShown(),"repainting after mouse leave never reopens a hidden tooltip")
reusedToast.scripts.OnEnter(reusedToast)
NS.ClearNotifications()
check(not GameTooltip:IsShown(),"hiding the owning notification also hides its sender tooltip")
for index=1,4 do chat("CHAT_MSG_WHISPER","他人浮层 "..index,"浮层作者"..index,7400+index) end
local otherOwner=widget("Frame")
GameTooltip:SetOwner(otherOwner); GameTooltip:SetText("其他插件提示"); GameTooltip:Show()
ui.toasts[1].scripts.OnMouseWheel(ui.toasts[1],-1)
check(GameTooltip:IsOwned(otherOwner) and GameTooltip:GetText()=="其他插件提示" and GameTooltip:IsShown(),
    "notification repaints do not replace another widget's tooltip")
ui.toasts[1].scripts.OnLeave(ui.toasts[1]); NS.ClearNotifications()
check(GameTooltip:IsShown() and GameTooltip:IsOwned(otherOwner),"notification leave/hide does not close another widget's tooltip")
NS.GetMessageProfile=originalMessageProfile
UIParent:SetSize(1600,1000)
-- A conversation is not evidence that its recipient is online. Preserve drafts,
-- distinguish unknown presence, and keep native delivery failures in the UI.
do
    NS.ClearNotifications(); NS.ResetAppearance()
    if not panel:IsShown() then NS.ToggleUI() end
    local originalPresence=NS.GetContactPresence
    local controlledPresence={}
    NS.GetContactPresence=function(conv)
        return controlledPresence[conv.id] or originalPresence(conv)
    end
    local person=NS.OpenWhisper("离线回归 玩家-家族")
    controlledPresence[person.id]="offline"; ui.render()
    check(visibleText("对方离线"),"opening a known offline recipient displays a visible warning before any typing")
    panel.editor:SetText("离线时留下的草稿")
    local beforeSend=#sent
    check(not panel.send.enabled and person.draft=="离线时留下的草稿","offline recipient keeps editable draft but disables send")
    for _=1,3 do panel.editor.scripts.OnEnterPressed(panel.editor) end
    panel.send.scripts.OnClick(panel.send)
    check(#sent==beforeSend and panel.editor:GetText()=="离线时留下的草稿","repeated Enter and direct button callback cannot send to known offline recipient")
    NS.Select("guild"); ui.render(); NS.Select(person.id); ui.render()
    check(visibleText("对方离线") and person.draft=="离线时留下的草稿","switching away and back retains the offline warning and personal draft")
    controlledPresence[person.id]="online"
    eventFrame.scripts.OnEvent(eventFrame,"FRIENDLIST_UPDATE"); ui.render()
    check(panel.send.enabled and not visibleText("对方离线") and panel.editor:GetText()=="离线时留下的草稿",
        "fresh online status restores sending without consuming the offline draft")
    check(not panel.deliveryNotice:IsShown() and panel.history.points.BOTTOMRIGHT.y==148
        and panel.bottom.points.BOTTOMRIGHT.y==155 and not visibleText("在线状态由游戏提供"),
        "idle online conversation hides the status strip and returns its space to history")
    controlledPresence[person.id]="unknown"
    eventFrame.scripts.OnEvent(eventFrame,"UNIT_CONNECTION","target",false); ui.render()
    check(visibleText("在线状态未知") and panel.send.enabled,"unknown recipient is clearly labelled and is not falsely blocked as offline")
    check(panel.deliveryNotice:IsShown() and panel.history.points.BOTTOMRIGHT.y==202,
        "unknown presence retains its necessary warning and reserved layout space")
    ui.send(); panel.editor.scripts.OnEnterPressed(panel.editor)
    check(#sent==beforeSend+1 and not panel.send.enabled,"unknown recipient permits one attempt while pending prevents duplicate Enter")
    chat("CHAT_MSG_WHISPER_INFORM","离线时留下的草稿",person.target,9001); ui.render()
    check(panel.editor:GetText()=="" and person.draft=="","confirmed unknown-recipient delivery clears only the original draft")

    local originalNotFound=ERR_CHAT_PLAYER_NOT_FOUND_S
    ERR_CHAT_PLAYER_NOT_FOUND_S="没有名为“%s”的玩家在线。"
    panel.editor:SetText("等待离线结果"); ui.send()
    local sentWithPending=#sent
    local messageCount=#person.messages
    NS.ShowSystemNotice(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,"同名别人-家族")); ui.render()
    check(visibleText("正在发送") and not visibleText("对方不在线或角色名无效"),
        "another recipient's exact offline notice cannot fail the active pending message")
    local secretValue={}
    local originalSecretCheck=issecretvalue
    issecretvalue=function(value) return rawequal(value,secretValue) or originalSecretCheck(value) end
    NS.ShowSystemNotice(secretValue); ui.render()
    check(visibleText("正在发送") and #person.messages==messageCount,"restricted system text cannot be coerced or treated as recipient failure")
    issecretvalue=originalSecretCheck
    eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_SYSTEM",string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,person.target)); ui.render()
    check(visibleText("对方不在线或角色名无效") and not panel.send.enabled,
        "matching native player-not-found notice immediately exposes a prominent failure and blocks sending")
    check(person.draft=="等待离线结果" and panel.editor:GetText()=="等待离线结果" and #person.messages==messageCount,
        "native offline failure preserves draft without manufacturing a delivered message")
    expire(); ui.render()
    for _=1,3 do panel.editor.scripts.OnEnterPressed(panel.editor) end
    check(#sent==sentWithPending and visibleText("对方不在线或角色名无效"),
        "old timeout cannot hide confirmed offline failure or enable repeated Enter")
    NS.Select("guild"); ui.render(); panel.editor:SetText("另一个会话可写")
    check(panel.send.enabled and not visibleText("对方不在线或角色名无效"),"one recipient's failure does not disable an unrelated conversation")
    NS.Select(person.id); ui.render()
    check(visibleText("对方不在线或角色名无效") and not panel.send.enabled and panel.editor:GetText()=="等待离线结果",
        "returning to the failed recipient restores its warning and draft")
    clickNoticeButton("重新检查")
    check(panel.send.enabled and #sent==sentWithPending and panel.editor:GetText()=="等待离线结果",
        "rechecking an unknown recipient enables a deliberate new attempt without auto-sending")
    ui.send()
    check(#sent==sentWithPending+1,"explicit retry sends once after rechecking")
    chat("CHAT_MSG_WHISPER_INFORM","等待离线结果",person.target,9002); ui.render()
    check(panel.editor:GetText()=="","retry is cleared only by the matching native echo")

    panel.editor:SetText("迟到的确认"); ui.send(); expire(); ui.render()
    local timedOutSends=#sent
    check(not panel.send.enabled and panel.editor:GetText()=="迟到的确认","timeout retains the original text in an unconfirmed state")
    panel.editor.scripts.OnEnterPressed(panel.editor)
    check(#sent==timedOutSends,"unconfirmed timeout cannot be retried by another Enter")
    chat("CHAT_MSG_WHISPER","我刚刚回到电脑前",person.target,90030); ui.render()
    check(not panel.send.enabled and panel.editor:GetText()=="迟到的确认" and visibleText("尚未确认送达"),
        "unrelated incoming reply is not delivery confirmation and cannot unlock a timed-out outgoing attempt")
    panel.editor.scripts.OnEnterPressed(panel.editor)
    check(#sent==timedOutSends,"incoming reply after timeout cannot bypass explicit retry acknowledgement")
    chat("CHAT_MSG_WHISPER_INFORM","迟到的确认",person.target,9003); ui.render()
    check(panel.editor:GetText()=="" and person.draft=="" and not visibleText("尚未确认送达"),
        "late native echo reconciles a timed-out attempt and removes its warning")
    panel.editor:SetText("超时后改写的原稿"); ui.send(); expire(); ui.render()
    panel.editor:SetText("确认来之前的新草稿")
    chat("CHAT_MSG_WHISPER_INFORM","超时后改写的原稿",person.target,9004); ui.render()
    check(panel.editor:GetText()=="确认来之前的新草稿" and person.draft=="确认来之前的新草稿" and panel.send.enabled,
        "late confirmation after timeout clears failure but cannot erase new typing")
    panel.editor:SetText("收到拒绝后的迟到回显"); ui.send()
    eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_SYSTEM",string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,person.target)); ui.render()
    chat("CHAT_MSG_WHISPER_INFORM","收到拒绝后的迟到回显",person.target,9005); ui.render()
    check(panel.editor:GetText()=="" and not visibleText("对方不在线或角色名无效"),
        "a genuine late echo can reconcile a previously failed attempt")
    panel.editor:SetText("离线拒绝后等对方回来"); ui.send()
    eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_SYSTEM",string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,person.target)); ui.render()
    chat("CHAT_MSG_WHISPER","现在可以聊了",person.target,9006); ui.render()
    check(panel.send.enabled and panel.editor:GetText()=="离线拒绝后等对方回来" and not visibleText("对方不在线或角色名无效"),
        "fresh message from an offline-rejected recipient restores manual sending and preserves unsent draft")
    panel.editor:SetText("离线提示前已收到的来信"); ui.send()
    local beforeOldReplySends=#sent
    chat("CHAT_MSG_WHISPER","这是离线提示前的消息",person.target,9007); ui.render()
    eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_SYSTEM",string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,person.target)); ui.render()
    for _=1,3 do NS.RefreshUI(); ui.render() end
    eventFrame.scripts.OnEvent(eventFrame,"FRIENDLIST_UPDATE"); ui.render()
    check(not panel.send.enabled and visibleText("对方不在线或角色名无效") and panel.editor:GetText()=="离线提示前已收到的来信",
        "incoming received before the offline rejection cannot reopen sending during later UI or friend-list refreshes")
    panel.editor.scripts.OnEnterPressed(panel.editor)
    check(#sent==beforeOldReplySends,"pre-failure incoming cannot silently authorize a repeated Enter after native offline rejection")
    chat("CHAT_MSG_WHISPER","这是离线提示后重新上线的消息",person.target,9008); ui.render()
    check(panel.send.enabled and not visibleText("对方不在线或角色名无效") and person.draft=="离线提示前已收到的来信"
        and #sent==beforeOldReplySends,"only new incoming after the rejection restores manual sending, with draft preserved and no automatic resend")
    ERR_CHAT_PLAYER_NOT_FOUND_S=originalNotFound

    local nativeBattleNetSend=C_BattleNet.SendWhisper
    local bnetAttempts=0
    C_BattleNet.SendWhisper=function(id,body)
        bnetAttempts=bnetAttempts+1; return nativeBattleNetSend(id,body)
    end
    bnetAccount.gameAccountInfo.isOnline=false
    local bnet=NS.OpenBattleNet(bnetAccount.battleTag); ui.render()
    panel.editor:SetText("通行证离线草稿")
    check(visibleText("对方离线") and not panel.send.enabled,"Battle.net offline recipient receives the same prominent pre-send warning")
    panel.editor.scripts.OnEnterPressed(panel.editor)
    check(bnetAttempts==0 and bnet.draft=="通行证离线草稿","known offline Battle.net recipient never reaches native SendWhisper")
    bnetAccount.gameAccountInfo.isOnline=true
    eventFrame.scripts.OnEvent(eventFrame,"BN_FRIEND_ACCOUNT_ONLINE",82); ui.render()
    check(panel.send.enabled,"Battle.net account-online event restores sending")
    ui.send()
    check(bnetAttempts==1 and not panel.send.enabled,"online Battle.net recipient submits one native request")
    local bnetMessageCount=#bnet.messages
    chat("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE","未发送","通行证好友",9010,nil,nil,nil,999); ui.render()
    check(visibleText("正在发送") and #bnet.messages==bnetMessageCount,
        "same display name but different Battle.net account ID cannot fail this recipient or create history")
    issecretvalue=function(value) return rawequal(value,secretValue) or originalSecretCheck(value) end
    chat("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE","未发送","通行证好友",9011,nil,nil,nil,secretValue); ui.render()
    check(visibleText("正在发送") and #bnet.messages==bnetMessageCount,"secret Battle.net failure identity is ignored safely")
    issecretvalue=originalSecretCheck
    chat("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE","未发送","通行证好友",9012,nil,nil,nil,82); ui.render()
    check(not panel.send.enabled and (visibleText("离线") or visibleText("不在线"))
        and panel.editor:GetText()=="通行证离线草稿" and #bnet.messages==bnetMessageCount,
        "matching Battle.net offline event fails only that pending attempt while retaining draft and history")
    expire(); panel.editor.scripts.OnEnterPressed(panel.editor); ui.render()
    check(bnetAttempts==1 and not panel.send.enabled,"Battle.net offline failure remains blocked beyond original timeout")
    chat("CHAT_MSG_BN_WHISPER_INFORM","通行证离线草稿","通行证好友",9013,nil,nil,nil,82); ui.render()
    check(panel.editor:GetText()=="" and bnet.draft=="","late Battle.net echo resolves its matching failed attempt")
    C_BattleNet.SendWhisper=nativeBattleNetSend
    NS.Select(person.id); ui.render(); panel.editor:SetText("甲的并发消息"); ui.send()
    local otherPerson=NS.OpenWhisper("离线回归 另一位-家族")
    controlledPresence[otherPerson.id]="unknown"; ui.render()
    panel.editor:SetText("乙的并发消息"); ui.send()
    ERR_CHAT_PLAYER_NOT_FOUND_S="没有名为“%s”的玩家在线。"
    eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_SYSTEM",string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,person.target)); ui.render()
    check(NS.GetSelected()==otherPerson and panel.editor:GetText()=="乙的并发消息" and visibleText("正在发送")
        and not visibleText("对方不在线或角色名无效"),"late offline error for A cannot replace B's active pending status or draft")
    chat("CHAT_MSG_WHISPER_INFORM","乙的并发消息",otherPerson.target,9014); ui.render()
    check(panel.editor:GetText()=="" and otherPerson.draft=="","B can confirm independently of A's native offline failure")
    NS.Select(person.id); ui.render()
    check(panel.editor:GetText()=="甲的并发消息" and not panel.send.enabled and visibleText("对方不在线或角色名无效"),
        "off-screen recipient's native failure is retained for its own conversation")
    ERR_CHAT_PLAYER_NOT_FOUND_S=originalNotFound
    NS.GetContactPresence=originalPresence
end
-- Public-channel controls remain discoverable even while the list is folded.
do
    NS.ClearNotifications(); expire()
    local oldList,oldName,oldInfo=GetChannelList,GetChannelName,C_ChatInfo.GetChannelInfoFromIdentifier
    local joined={{1,"综合 - 艾尔文森林",1},{2,"交易 - 城市",2}}
    GetChannelList=function() return joined[1][1],joined[1][2],false,joined[2][1],joined[2][2],false end
    GetChannelName=function(query)
        for _,entry in ipairs(joined) do if query==entry[1] or query==entry[2] then return entry[1],entry[2] end end
        return 0
    end
    C_ChatInfo.GetChannelInfoFromIdentifier=function(identifier)
        for _,entry in ipairs(joined) do
            if identifier==tostring(entry[1]) then return {localID=entry[1],name=entry[2],zoneChannelID=entry[3],channelType=1} end
        end
    end
    NS.InitDB({shown=true,channelsCollapsed=true,conversations={
        ["channel-zone:1"]={kind="channel",target=joined[1][2],channelZoneID=1,unread=1,
            messages={{id=8990,text="旧综合记录",author="甲",time=1}}},
        ["channel-zone:2"]={kind="channel",target=joined[2][2],channelZoneID=2,unread=1,muted=true,
            messages={{id=8989,text="旧交易记录",author="乙",time=1}}},
    }}); NS.SyncChannels(); panel:Show(); ui.render()
    local general,trade=NS.db.conversations["channel-zone:1"],NS.db.conversations["channel-zone:2"]
    local function channelMessage(zone,content,line)
        local entry=joined[zone]
        eventFrame.scripts.OnEvent(eventFrame,"CHAT_MSG_CHANNEL",content,"频道测试玩家",nil,
            entry[1]..". "..entry[2],nil,nil,zone,entry[1],zone==1 and "综合" or "交易",nil,line,"Player-Channel")
    end
    panel.channelSettings.scripts.OnClick(panel.channelSettings)
    local menu=ui.channelSettings
    check(menu and menu:IsShown() and NS.db.channelsCollapsed,"channel reminders manager opens without expanding folded conversation list")
    local function setting(id)
        for _,row in ipairs(menu.rows) do if row:IsShown() and row.conversation.id==id then return row end end
        error("missing channel setting "..id)
    end
    check(not NS.ChannelRemindersEnabled() and menu.masterToggle.label:GetText()=="开启频道提醒"
        and panel.channelSettings.label:GetText()=="频道提醒 · 关","legacy save exposes an off master switch with a clear opt-in action")
    check(ui.launcher.badge:GetText()=="" and general.unread==1 and trade.unread==1,
        "master-off suppresses existing channel launcher badges without deleting old unread records")
    NS.db.channelsCollapsed=false; ui.render()
    for _,row in ipairs(ui.conversationRows) do
        if row:IsShown() and row.conversation.kind=="channel" then
            check(row.badge:GetText()=="","master-off hides old unread on each visible public-channel row")
        end
    end
    check(not panel.channelsHeader.label:GetText():match(" · %d+$"),"master-off channel section header omits old unread total")
    NS.MinimizeUI(); channelMessage(1,"关闭时仍保存",8991); channelMessage(2,"关闭时也保存交易",8992)
    check(#general.messages==2 and #trade.messages==2 and general.unread==1 and trade.unread==1
        and not ui.toasts[1]:IsShown(),"master-off stores channel history without new unread or bubbles")
    panel:Show(); ui.render(); panel.channelSettings.scripts.OnClick(panel.channelSettings)
    setting(general.id).toggle.scripts.OnClick(setting(general.id).toggle)
    check(general.muted and trade.muted and not NS.ChannelRemindersEnabled()
        and setting(general.id).toggle.label:GetText()=="设为允许","individual channel choices remain configurable while master is off")
    setting(general.id).toggle.scripts.OnClick(setting(general.id).toggle)
    local nativeSends=#sent
    menu.masterToggle.scripts.OnClick(menu.masterToggle)
    check(NS.db.channelRemindersEnabled and menu.masterToggle.label:GetText()=="关闭频道提醒"
        and not general.muted and trade.muted,"master opt-in persists and preserves distinct per-channel choices")
    check(not ui.toasts[1]:IsShown() and #sent==nativeSends,"enabling reminders neither replays suppressed messages nor sends chat")
    NS.InitDB(NS.db); NS.SyncChannels(); ui.render()
    check(NS.ChannelRemindersEnabled() and NS.db.conversations[trade.id].muted,
        "UI master opt-in and per-channel block survive saved-variable reload")
    menu.masterToggle.scripts.OnClick(menu.masterToggle)
    NS.InitDB(NS.db); NS.SyncChannels(); ui.render()
    check(not NS.ChannelRemindersEnabled() and menu.masterToggle.label:GetText()=="开启频道提醒"
        and NS.db.conversations[trade.id].muted,"UI master opt-out survives reload without resetting per-channel block")

    -- The existing per-channel tests intentionally exercise the opted-in mode.
    NS.InitDB({shown=true,channelsCollapsed=true,channelRemindersEnabled=true}); NS.SyncChannels(); ui.render()
    general,trade=NS.db.conversations["channel-zone:1"],NS.db.conversations["channel-zone:2"]
    check(setting(general.id).name.label:GetText():find("综合",1,true) and setting(trade.id).name.label:GetText():find("交易",1,true),
        "general and trade have separate named rows in channel controls")
    setting(general.id).toggle.scripts.OnClick(setting(general.id).toggle)
    check(general.muted and not trade.muted and setting(general.id).toggle.label:GetText()=="恢复弹窗",
        "general control mutes only general and clearly offers restoration")
    NS.MinimizeUI()
    check(not menu:IsShown(),"minimizing chat hides channel settings dialog")
    channelMessage(1,"综合仍保存",9001); channelMessage(2,"交易仍提醒",9002)
    check(#general.messages==1 and general.unread==1 and NS.UnreadTotal()==1,
        "muted channel preserves history and own unread without inflating launcher reminders")
    check(ui.toasts[1]:IsShown() and ui.toasts[1].conversationId==trade.id
        and ui.toasts[1].title:GetText():find("交",1,true) and ui.toasts[1].muteChannel:IsShown(),
        "folding does not mute trade and its compact bubble keeps a channel label and direct mute action")
    ui.toasts[1].scripts.OnEnter(ui.toasts[1])
    check(GameTooltip:GetText():find("交易",1,true),"compact public-channel hover retains its full channel name")
    ui.toasts[1].scripts.OnLeave(ui.toasts[1])
    local compact=ui.toasts[1]
    local senderRight=compact.sender.points.TOPLEFT.x+compact.sender:GetWidth()
    local titleRight=compact:GetWidth()+compact.title.points.TOPRIGHT.x
    local muteLeft=compact:GetWidth()+compact.muteChannel.points.TOPRIGHT.x-compact.muteChannel:GetWidth()
    check(senderRight+2<=titleRight-compact.title:GetWidth() and titleRight+2<=muteLeft
        and -compact.muteChannel.points.TOPRIGHT.y+compact.muteChannel:GetHeight()+2<=-compact.preview.points.TOPLEFT.y,
        "compact channel sender, category and mute control remain horizontally separate above the body")
    ui.toasts[1].muteChannel.scripts.OnClick(ui.toasts[1].muteChannel)
    check(trade.muted and not ui.toasts[1]:IsShown(),"bubble mute immediately removes that channel's reminder")
    panel:Show(); ui.render(); panel.channelSettings.scripts.OnClick(panel.channelSettings)
    setting(general.id).toggle.scripts.OnClick(setting(general.id).toggle)
    setting(trade.id).toggle.scripts.OnClick(setting(trade.id).toggle)
    check(not general.muted and not trade.muted and not ui.toasts[1]:IsShown(),"restoring channels never replays suppressed old bubbles")
    setting(trade.id).name.scripts.OnClick(setting(trade.id).name)
    check(NS.GetSelected().id==trade.id and panel.title:GetText()=="交易" and panel.mute.label:GetText()=="屏蔽弹窗",
        "named channel row opens its own conversation with channel-specific mute label")
    NS.db.channelsCollapsed=true; ui.render(); NS.MinimizeUI(); UIParent:SetSize(1600,1000)
    for index=1,3 do channelMessage(1,"综合排队"..index,9010+index); channelMessage(2,"交易排队"..index,9020+index) end
    check(ui.clearToasts.label:GetText()=="清除泡泡 (6)","both named channels can have visible and queued reminders")
    NS.ToggleMute(general.id)
    check(ui.clearToasts.label:GetText()=="清除泡泡 (3)","muting clears all visible and queued general reminders only")
    for _,toast in ipairs(ui.toasts) do if toast:IsShown() then check(toast.conversationId==trade.id,"trade reminders survive general mute") end end
    NS.ToggleMute(general.id)
    check(ui.clearToasts.label:GetText()=="清除泡泡 (3)","unmuting does not replay removed queue items")
    NS.ClearNotifications(); panel:Show(); ui.render()

    -- Certification can merge a legacy conversation while a send awaits echo.
    -- Its timeout must follow the migrated token, not the deleted old object.
    local infoAPI=C_ChatInfo.GetChannelInfoFromIdentifier
    C_ChatInfo.GetChannelInfoFromIdentifier=function() return nil end
    local legacyID="channel:"..joined[1][2]
    NS.InitDB({shown=true,selectedId=legacyID,conversations={
        [legacyID]={kind="channel",target=joined[1][2],draft="迁移中的发送"},
        ["channel-zone:1"]={kind="channel",target=joined[1][2],channelZoneID=1,
            messages={{id=9900,text="迁移中的发送",author="本人",outgoing=true,time=1}}},
    }})
    ui.render(); ui.send()
    check(not panel.send.enabled,"legacy channel send waits for native echo")
    C_ChatInfo.GetChannelInfoFromIdentifier=infoAPI; NS.SyncChannels(); ui.render()
    check(panel.editor:GetText()=="迁移中的发送" and not panel.send.enabled,"imported matching outgoing history cannot acknowledge a new pending send")
    expire(); ui.render()
    check(NS.GetSelected().id=="channel-zone:1" and panel.editor:GetText()=="迁移中的发送" and panel.send.enabled,
        "pending send timeout follows merged channel identity and retains its draft")
    GetChannelList,GetChannelName,C_ChatInfo.GetChannelInfoFromIdentifier=oldList,oldName,oldInfo
end
-- Certified community mirrors are readable archives, not public-channel routes.
do
    NS.ClearNotifications(); expire()
    local oldSync=NS.SyncChannels
    NS.SyncChannels=function() end -- Core certification is covered separately.
    local id="channel:旧社区镜像"
    NS.InitDB({shown=true,channelsCollapsed=false,channelRemindersEnabled=true,conversations={
        [id]={kind="channel",target="旧社区镜像",draft="保留待转移草稿",
            messages={{id=10901,text="旧群历史仍可复制",author="测试成员",time=1}}},
    }})
    local legacy=NS.db.conversations[id]
    panel:Show(); ui.render(); NS.MinimizeUI()
    NS.lastIncoming={conversationId=id,message=legacy.messages[1]}; NS.RefreshUI()
    check(ui.toasts[1]:IsShown(),"legacy mirror initially has an existing queued public-channel reminder")
    legacy.channelCommunity=true; legacy.available=false; NS.RefreshUI()
    check(not ui.toasts[1]:IsShown() and not legacy.muted,
        "certifying a community mirror removes stale reminders without changing mute preference")
    panel:Show(); ui.render(); panel.channelSettings.scripts.OnClick(panel.channelSettings)
    local listed=false
    for _,row in ipairs(ui.channelSettings.rows) do
        if row:IsShown() and row.conversation.id==id then listed=true end
    end
    check(not listed,"old community mirror is absent from public-channel reminder settings")
    ui.channelSettings:Hide()
    local legacyRow
    for _,row in ipairs(ui.conversationRows) do
        if row:IsShown() and row.conversation.id==id then legacyRow=row end
    end
    check(legacyRow and legacyRow.name:GetText():find("旧群频道",1,true) and legacyRow.letter:GetText()=="旧",
        "archived community remains discoverable with an explicit old-group label")
    legacyRow.scripts.OnClick(legacyRow,"LeftButton"); ui.render()
    check(panel.editor:GetText()=="保留待转移草稿" and panel.subtitle:GetText():find("旧群频道",1,true)
        and not panel.send.enabled and panel.send.label:GetText()=="请用群聊",
        "old group keeps an editable draft but visibly blocks public-channel sending")
    local sendCount=#sent
    ui.send()
    check(#sent==sendCount and legacy.draft=="保留待转移草稿" and panel.status:GetText():find("复制草稿",1,true),
        "Enter on an archived community cannot send or consume its draft")
    ui.messageRows[1].bubble.scripts.OnClick(ui.messageRows[1].bubble,"RightButton")
    check(MyForeverChatCopy.edit:GetText()=="旧群历史仍可复制","old community message history remains copyable")
    MyForeverChatCopy:Hide()
    NS.SyncChannels=oldSync
end
-- Channel initials are a presentation detail; names, drafts and histories stay exact.
do
    NS.ClearNotifications(); expire()
    local cases={{"综合 - 暴风城","综"},{"交易 - 城市","交"},{"副本","本"},
        {"寻求组队","组"},{"世界","世"},{"自建频道 - 甲","自"},{"😀茶话会","😀"}}
    local conversations={}
    for index,case in ipairs(cases) do
        conversations["channel:"..case[1]]={kind="channel",target=case[1],draft="原草稿 "..index,
            messages={{id=10000+index,text="原记录 "..index,author="测试玩家",time=1}}}
    end
    NS.InitDB({shown=true,channelsCollapsed=false,conversations=conversations}); panel:Show(); ui.render()
    local function rowFor(id)
        for _,row in ipairs(ui.conversationRows) do if row:IsShown() and row.conversation.id==id then return row end end
        error("missing visible conversation "..id)
    end
    for index,case in ipairs(cases) do
        local id="channel:"..case[1]
        local row=rowFor(id)
        check(row.letter:GetText()==case[2],"channel initial is recognizable and UTF-8-safe: "..case[1])
        check(row.conversation.target==case[1] and row.conversation.draft=="原草稿 "..index
            and row.conversation.messages[1].text=="原记录 "..index,"channel abbreviation never alters target, draft or history: "..case[1])
    end
    for _,case in ipairs({{"guild","会"},{"group","队"},{"raid","团"},{"say","近"}}) do
        check(rowFor(case[1]).letter:GetText()==case[2],"existing fixed conversation initial is preserved: "..case[1])
    end
    local oldPresence=NS.GetContactPresence
    NS.GetContactPresence=function() return "online" end
    local person=NS.OpenWhisper("在线提示回归玩家"); ui.render()
    check(not panel.deliveryNotice:IsShown(),"idle online contact has no persistent green strip")
    panel.editor:SetText("等待真实发送结果"); ui.send(); ui.render()
    check(panel.deliveryNotice:IsShown() and visibleText("正在发送") and not panel.send.enabled,
        "online contact still shows pending delivery feedback")
    expire(); ui.render()
    check(panel.deliveryNotice:IsShown() and visibleText("尚未确认送达") and not panel.send.enabled
        and person.draft=="等待真实发送结果","online contact still shows failed delivery feedback and keeps its draft")
    NS.GetContactPresence=oldPresence
end
-- Use the real community transport and Core together through the UI entrypoints.
do
    NS.ClearNotifications(); expire()
    local originalClub,originalSocial,originalNative,originalCombat=C_Club,C_SocialRestrictions,CommunitiesFrame,InCombatLockdown
    Enum=Enum or {}; Enum.ClubType={Character=1,BattleNet=0,Guild=2}; Enum.ClubRoleIdentifier={Owner=1,Leader=2,Moderator=3,Member=4}
    local joined,subscribed,missingRanges,rejectSend=false,true,false,false
    local clubSends,nativeSelections,requests={},{},0
    local epoch=1793940000000000
    local history={ ["10:101"]={},["20:202"]={} }
    local function raw(position,content,outgoing,unknown)
        return {messageId={epoch=epoch,position=position},content=content,destroyed=false,edited=false,
            author={name=not unknown and (outgoing and "发言角色-家族" or "群友-家族") or nil,isSelf=outgoing==true,level=25}}
    end
    local function key(c,s) return tostring(c)..":"..tostring(s) end
    C_Club={
        IsEnabled=function() return true end,IsRestricted=function() return 0 end,FocusCommunityStreams=function() end,
        GetSubscribedClubs=function() return joined and {{clubId=10,name="测试甲群",clubType=1,memberCount=2},
            {clubId=20,name="测试乙群",clubType=1,memberCount=3}} or {} end,
        GetStreams=function(c) return {{streamId=c==10 and 101 or 202,name=c==10 and "综合" or "战术",leadersAndModeratorsOnly=false}} end,
        IsSubscribedToStream=function(c) return c==10 or subscribed end,
        GetStreamInfo=function(c,s) return {streamId=s,name=c==10 and "综合" or "战术",leadersAndModeratorsOnly=false} end,
        IsAccountMuted=function() return false end,GetClubPrivileges=function() return {canCreateMessage=true} end,
        GetMemberInfoForSelf=function() return {role=4} end,
        GetMessageRanges=function(c,s)
            local list=history[key(c,s)]
            if missingRanges or #list==0 then return {} end
            return {{oldestMessageId=list[1].messageId,newestMessageId=list[#list].messageId}}
        end,
        GetMessagesBefore=function(c,s,mid,count)
            local result={}; for _,message in ipairs(history[key(c,s)]) do if message.messageId.position<=mid.position then result[#result+1]=message end end
            return result
        end,
        GetMessageInfo=function(c,s,mid)
            for _,message in ipairs(history[key(c,s)]) do if message.messageId.position==mid.position then return message end end
        end,
        IsBeginningOfStream=function() return true end,
        RequestMoreMessagesBefore=function() requests=requests+1; return false end,
        SendMessage=function(c,s,content)
            if rejectSend then error("native submission rejected") end
            clubSends[#clubSends+1]={clubId=c,streamId=s,text=content}
        end,
    }
    C_SocialRestrictions={IsChatDisabled=function() return false end}
    InCombatLockdown=function() return false end
    CommunitiesFrame=widget("Frame"); CommunitiesFrame:Hide()
    CommunitiesFrame.SelectClub=function(_,id) nativeSelections.club=id end
    CommunitiesFrame.SelectStream=function(_,c,s) nativeSelections.stream=s; nativeSelections.streamClub=c end
    NS.InitDB({shown=true}); panel:Show(); ui.render()
    panel.clubsTab.scripts.OnClick(panel.clubsTab)
    check(panel.clubsEmpty:IsShown() and panel.communityCreate:IsShown() and not panel.channelsHeader:IsShown(),
        "empty community tab is separate from public channels and offers native create/join")
    panel.communityCreate.scripts.OnClick(panel.communityCreate)
    check(CommunitiesFrame:IsShown() and not panel:IsShown() and #clubSends==0,
        "create/join exposes native community UI without overlay, sending or silently creating a group")
    NS.QuickReply(); ui.render()
    check(panel:IsShown(),"quick reply reopens the plugin after native create/join handoff")
    joined=true
    history["10:101"]={raw(1,"已有群历史",false),raw(2,"重复文本",true),raw(3,"未知作者消息",false,true)}
    history["20:202"]={raw(1,"乙群历史",false)}
    panel.communityRefresh.scripts.OnClick(panel.communityRefresh)
    local function clubRow(id)
        for _,row in ipairs(ui.conversationRows) do if row:IsShown() and row.conversation.id==id then return row end end
        error("missing community row "..id)
    end
    local a,b=NS.Communities.GetEntry("club:10:101"),NS.Communities.GetEntry("club:20:202")
    check(clubRow(a.id).name:GetText()=="测试甲群" and clubRow(a.id).detail:GetText()=="综合 · 2 人"
        and clubRow(b.id).detail:GetText()=="战术 · 3 人","community rows distinguish group, stream and actual member count")
    check(not NS.db.conversations[a.id] and not NS.db.conversations[b.id],"listing groups does not create empty conversations or prune existing chats")
    clubRow(a.id).scripts.OnClick(clubRow(a.id),"LeftButton"); ui.render(); a=NS.db.conversations[a.id]
    check(NS.GetSelected()==a and panel.title:GetText()=="测试甲群 · 综合" and panel.subtitle:GetText():find("2 人",1,true)
        and panel.nativeClub:IsShown() and not panel.addFriend:IsShown() and not panel.remove:IsShown(),
        "opening a group selects its exact stream and exposes native management instead of private-contact controls")
    check(#a.messages==3 and ui.messageRows[1].content:GetText()=="已有群历史" and not ui.toasts[1]:IsShown(),
        "cached community history appears without notification replay")
    local unknownRow=ui.messageRows[3]
    unknownRow.author.scripts.OnClick(unknownRow.author,"LeftButton"); clickTime=clickTime+0.1
    unknownRow.author.scripts.OnClick(unknownRow.author,"LeftButton")
    check(NS.GetSelected()==a and not NS.db.conversations["whisper:社区成员"],"unknown community author placeholder cannot open a false private conversation")
    panel.editor:SetText("管理前保留的群草稿")
    panel.nativeClub.scripts.OnClick(panel.nativeClub)
    check(nativeSelections.club==10 and nativeSelections.stream==101 and nativeSelections.streamClub==10,
        "native management selects the current community and stream")
    check(not panel:IsShown() and a.draft=="管理前保留的群草稿",
        "native community management removes plugin overlay while preserving the current draft")
    NS.QuickReply(); ui.render()
    check(panel:IsShown() and NS.GetSelected()==a and panel.editor:GetText()=="管理前保留的群草稿",
        "quick reply returns from native management to the selected group and its unchanged draft")
    InCombatLockdown=function() return true end
    panel.nativeClub.scripts.OnClick(panel.nativeClub)
    check(panel:IsShown() and panel.editor:GetText()=="管理前保留的群草稿" and panel.status:GetText():find("战斗结束",1,true),
        "failed native handoff leaves plugin and draft visible with its explanation")
    InCombatLockdown=function() return false end
    check(panel.inviteClub:IsShown() and panel.inviteClub.label:GetText()=="邀请朋友",
        "selected community has an explicit invite-friends action")
    panel.inviteClub.scripts.OnEnter(panel.inviteClub)
    check(GameTooltip:IsOwned(panel.inviteClub) and GameTooltip:GetText():find("再点原生窗口右下角“邀请成员”",1,true),
        "invite tooltip explains the required native invitation step before handing off")
    panel.inviteClub.scripts.OnLeave(panel.inviteClub)
    local originalInvite=NS.Communities.OpenInvite
    local invitationTarget,inviteAllowed=nil,false
    NS.Communities.OpenInvite=function(id)
        invitationTarget=id
        if not inviteAllowed then return false,"你没有邀请成员的权限。" end
        return true,"已打开此群，请点原生窗口右下角“邀请成员”。"
    end
    panel.inviteClub.scripts.OnClick(panel.inviteClub)
    check(invitationTarget==a.id and panel:IsShown() and panel.status:GetText():find("没有邀请成员的权限",1,true)
        and panel.editor:GetText()=="管理前保留的群草稿",
        "invite permission failure keeps selected group and draft visible with its reason")
    inviteAllowed=true; panel.inviteClub.scripts.OnClick(panel.inviteClub)
    check(invitationTarget==a.id and not panel:IsShown() and #clubSends==0 and a.draft=="管理前保留的群草稿",
        "successful invite handoff targets the current group, exposes native UI and preserves unsent text")
    NS.QuickReply(); ui.render()
    check(panel:IsShown() and NS.GetSelected()==a and panel.editor:GetText()=="管理前保留的群草稿",
        "quick reply returns to the group draft after invitation handoff")
    NS.Communities.OpenInvite=originalInvite
    local originalWidth=panel:GetWidth()
    panel:SetWidth(680); ui.render()
    local inviteRight=panel.inviteClub.points.TOPLEFT.x+panel.inviteClub:GetWidth()
    local noticeLeft=panel.clubNotice.points.TOPLEFT.x
    local restoreLeft=panel:GetWidth()+panel.restoreSubmission.points.TOPRIGHT.x-panel.restoreSubmission:GetWidth()
    check(inviteRight<noticeLeft and noticeLeft+panel.clubNotice:GetWidth()<restoreLeft
        and panel.inviteClub.points.TOPLEFT.y==panel.restoreSubmission.points.TOPRIGHT.y,
        "invite, community notice and restore controls do not overlap at minimum window width")
    panel:SetWidth(originalWidth); ui.render()
    local nativeChatSends=#sent
    panel.editor:SetText("重复文本"); ui.send(); ui.render()
    check(#clubSends==1 and clubSends[1].clubId==10 and clubSends[1].streamId==101 and #sent==nativeChatSends,
        "group send uses exact C_Club target and never numbered chat or whisper transport")
    check(panel.editor:GetText()=="" and a.draft=="" and a.latestSubmission.text=="重复文本"
        and panel.status:GetText():find("已提交，投递由游戏处理",1,true) and #a.messages==3,
        "successful group submission clears input, keeps a backup and does not invent delivery or a chat bubble")
    panel.restoreSubmission.scripts.OnClick(panel.restoreSubmission)
    check(panel.editor:GetText()=="重复文本" and #clubSends==1,"restore-last action recovers only a draft without resending")
    panel.editor:SetText("接着写的新草稿"); panel.restoreSubmission.scripts.OnClick(panel.restoreSubmission)
    check(panel.editor:GetText()=="接着写的新草稿" and panel.status:GetText():find("未覆盖",1,true),
        "restore-last action never overwrites an existing draft")
    history["10:101"][4]=raw(4,"重复文本",true)
    panel.refreshClub.scripts.OnClick(panel.refreshClub)
    check(panel.editor:GetText()=="接着写的新草稿" and panel.send.enabled,"historical outgoing message cannot clear the next group draft")
    history["10:101"][4].edited=true
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_UPDATED",10,101,history["10:101"][4].messageId); ui.render()
    check(panel.editor:GetText()=="接着写的新草稿","edited old group message never changes a new draft")
    history["10:101"][4].edited=false
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",10,101,history["10:101"][4].messageId); ui.render()
    check(panel.editor:GetText()=="接着写的新草稿","replayed existing history ID cannot change a new draft")
    history["10:101"][5]=raw(5,"重复文本",true)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",10,101,history["10:101"][5].messageId); ui.render()
    check(panel.editor:GetText()=="接着写的新草稿" and a.latestSubmission.text=="重复文本",
        "even a new self event is not used to confirm or clear unrelated current input")
    panel.editor:SetText("切群提交内容"); ui.send(); panel.editor:SetText("甲群未提交新草稿")
    clubRow(b.id).scripts.OnClick(clubRow(b.id),"LeftButton"); ui.render(); b=NS.db.conversations[b.id]; panel.editor:SetText("乙群独立草稿")
    history["20:202"][2]=raw(2,"切群提交内容",true)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][2].messageId); ui.render()
    check(a.draft=="甲群未提交新草稿" and panel.editor:GetText()=="乙群独立草稿",
        "same-text echo in another group cannot clear either group's unrelated draft")
    history["10:101"][6]=raw(6,"切群提交内容",true)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",10,101,history["10:101"][6].messageId); ui.render()
    check(a.draft=="甲群未提交新草稿" and b.draft=="乙群独立草稿" and NS.GetSelected()==b,
        "off-screen self events never consume either group's next draft")
    panel.editor:SetText("可以连续提交"); ui.send(); expire(); ui.render()
    check(panel.editor:GetText()=="" and b.latestSubmission.text=="可以连续提交" and not visibleText("尚未确认送达"),
        "group submission does not enter a false timeout waiting for opaque content equality")
    local submitted=#clubSends; ui.send(); ui.send()
    check(#clubSends==submitted,"repeated Enter on cleared group input does not resend the submission")
    panel.restoreSubmission.scripts.OnClick(panel.restoreSubmission)
    check(panel.editor:GetText()=="可以连续提交" and a.latestSubmission.text=="切群提交内容" and #clubSends==submitted,
        "restore-last uses only the selected group's own submission")
    panel.editor:SetText("接口拒绝草稿"); rejectSend=true; ui.send(); rejectSend=false
    check(panel.editor:GetText()=="接口拒绝草稿" and b.latestSubmission.text=="可以连续提交" and #clubSends==submitted,
        "native API failure keeps current draft and does not replace the previous successful submission")
    subscribed=false; panel.communityRefresh.scripts.OnClick(panel.communityRefresh); ui.render()
    check(not panel.send.enabled and visibleText("群频道暂不可用") and b.draft=="接口拒绝草稿",
        "lost subscription leaves local history and draft visible but blocks group sending")
    ui.send(); check(#clubSends==submitted,"unavailable group never reaches native SendMessage")
    subscribed=true; missingRanges=true; panel.refreshClub.scripts.OnClick(panel.refreshClub); ui.render()
    check(requests>0 and panel.clubNotice:GetText():find("正在读取群消息",1,true),"history request status is visible without pretending cached messages are current")
    expire(); ui.render()
    check(panel.clubNotice:GetText():find("群历史尚未返回",1,true),"history timeout provides a retry explanation")
    missingRanges=false; panel.refreshClub.scripts.OnClick(panel.refreshClub); ui.render()
    NS.ClearNotifications(); NS.MinimizeUI()
    history["20:202"][3]=raw(3,"新的乙群提醒",false)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][3].messageId)
    check(ui.toasts[1]:IsShown() and ui.toasts[1].title:GetText():find("群聊",1,true)
        and not ui.toasts[1].title:GetText():find("测试乙群",1,true),
        "live community notification uses a compact group category label")
    ui.toasts[1].scripts.OnEnter(ui.toasts[1])
    check(GameTooltip:GetText():find("测试乙群 · 战术",1,true),
        "compact community hover retains its full group and stream identity")
    ui.toasts[1].scripts.OnLeave(ui.toasts[1])
    ui.toasts[1].scripts.OnClick(ui.toasts[1],"LeftButton"); ui.render()
    check(NS.GetSelected()==b and panel.communityCreate:IsShown(),"group notification opens the matching independent group view")

    history["20:202"][4]=raw(4,"|Kw9|k",false)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][4].messageId); ui.render()
    local protectedRow=ui.messageRows[#b.messages]
    check(protectedRow.content:GetText()=="|Kw9|k" and clubRow(b.id).preview:GetText()=="|Kw9|k",
        "fresh native community content reaches body and sidebar FontStrings without escaping")
    local nativeWidthQueries=0
    protectedRow.content.GetUnboundedStringWidth=function()
        nativeWidthQueries=nativeWidthQueries+1
        return 0 -- The live engine hides protected text's natural width.
    end
    protectedRow.content.GetStringHeight=function(self)
        -- The renderer still wraps the actual long message at the given width.
        return math.ceil(720/math.max(1,self:GetWidth()))*16
    end
    ui.render()
    check(nativeWidthQueries==0 and protectedRow.bubble:GetWidth()>protectedRow:GetWidth()/2
        and protectedRow.bubble:GetWidth()<protectedRow:GetWidth(),
        "opaque native text remains readable at normal bubble width when natural width is unavailable")
    check(protectedRow.bubble:GetHeight()>protectedRow.content:GetStringHeight()
        and protectedRow:GetHeight()>protectedRow.bubble:GetHeight(),
        "protected text keeps wrapped content and author spacing inside its history row")
    check(ui.messageRows[3].bubble:GetWidth()<protectedRow.bubble:GetWidth(),
        "ordinary short text still uses a compact bubble beside protected full-width content")
    protectedRow.content.GetUnboundedStringWidth=nil
    protectedRow.content.GetStringHeight=nil
    protectedRow.bubble.scripts.OnClick(protectedRow.bubble,"RightButton")
    check(MyForeverChatCopy.edit:GetText():find("原生社区",1,true) and not MyForeverChatCopy.edit:GetText():find("|Kw",1,true),
        "protected-content copy explains native handling without exporting raw session handles")
    MyForeverChatCopy:Hide(); NS.ClearNotifications(); NS.MinimizeUI()
    local longHandle="|Kw"..string.rep("1",72).."|k"
    history["20:202"][5]=raw(5,longHandle,false)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][5].messageId)
    check(ui.toasts[1].preview:GetText()==longHandle,"native notification content remains whole rather than byte/character-truncating its handle")
    ui.toasts[1].scripts.OnClick(ui.toasts[1],"LeftButton"); ui.render()
    check(NS.DisplayText("|Kw9|k",false)=="||Kw9||k" and NS.DisplayText("||Kw9||k",false)=="||Kw9||k",
        "ordinary chat sanitizer still escapes arbitrary or literal native-looking handles")
    local saved=NS.db
    NS.InitDB(saved); ui.render(); b=NS.db.conversations[b.id]
    check(ui.messageRows[#b.messages].content:GetText()=="[群消息待重新读取]" and b.latestSubmission.text=="可以连续提交",
        "reload does not render stale session handles while retaining the local submission backup")
    local originalOpen=NS.Communities.Open
    local reopenReads=0
    NS.Communities.Open=function(id) reopenReads=reopenReads+1; return originalOpen(id) end
    NS.MinimizeUI(); NS.ToggleUI(); ui.render()
    check(ui.messageRows[#b.messages].content:GetText()==longHandle and reopenReads==1,
        "opening the remembered group after reload automatically reads fresh native history")
    ui.render(); ui.render(); panel.editor:SetText("重载后继续写"); ui.render()
    check(reopenReads==1 and b.draft=="重载后继续写" and b.latestSubmission.text=="可以连续提交",
        "redraws and composing do not repeat history reads or alter submission backup")
    NS.Communities.Open=originalOpen
    NS.Select("guild"); ui.render()
    check(not panel.inviteClub:IsShown(),"invite-friends control is only exposed for a community group")

    -- The public master removes both visible and queued public bubbles, while
    -- private messages and real community streams keep their independent alerts.
    NS.SyncChannels(); NS.SetChannelRemindersEnabled(true)
    local public=NS.db.conversations["channel:综合"]
    check(public~=nil,"mixed notification fixture has a joined public channel")
    if public.muted then NS.ToggleMute(public.id) end
    NS.ClearNotifications(); NS.MinimizeUI(); UIParent:SetSize(1600,1000)
    for index=1,6 do chat("CHAT_MSG_CHANNEL","公共排队 "..index,"频道成员",13000+index,"Player-Public",1,"综合") end
    chat("CHAT_MSG_WHISPER","私聊仍保留","总开关私聊-家族",13010,"Player-Private")
    history["20:202"][6]=raw(6,"群聊仍保留",false)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][6].messageId)
    check(ui.clearToasts.label:GetText()=="清除泡泡 (8)" and ui.toastNext:IsEnabled()
        and ui.toasts[1].conversationId==public.id,"mixed queue contains visible and queued public notifications alongside private and club messages")
    panel:Show(); ui.render(); panel.channelSettings.scripts.OnClick(panel.channelSettings)
    ui.channelSettings.masterToggle.scripts.OnClick(ui.channelSettings.masterToggle)
    check(not NS.ChannelRemindersEnabled() and ui.clearToasts.label:GetText()=="清除泡泡 (2)",
        "master-off removes all six visible and queued public notifications immediately")
    local kept={}
    for _,toast in ipairs(ui.toasts) do if toast:IsShown() then kept[toast.conversationId]=true end end
    check(kept["whisper:总开关私聊-家族"] and kept[b.id] and not kept[public.id],
        "master-off retains the private and community notification items")
    NS.MinimizeUI()
    local publicHistory,publicUnread=#public.messages,public.unread
    chat("CHAT_MSG_CHANNEL","关闭时继续存记录","频道成员",13011,"Player-Public",1,"综合")
    check(#public.messages==publicHistory+1 and public.unread==publicUnread
        and ui.clearToasts.label:GetText()=="清除泡泡 (2)","master-off new public receipt preserves history without unread or queued bubbles")
    chat("CHAT_MSG_WHISPER","关闭后新私聊","总开关私聊-家族",13012,"Player-Private")
    history["20:202"][7]=raw(7,"关闭后新群聊",false)
    eventFrame.scripts.OnEvent(eventFrame,"CLUB_MESSAGE_ADDED",20,202,history["20:202"][7].messageId)
    check(ui.clearToasts.label:GetText()=="清除泡泡 (4)","new private and community messages continue notifying while public master is off")
    panel:Show(); ui.render(); panel.channelSettings.scripts.OnClick(panel.channelSettings)
    ui.channelSettings.masterToggle.scripts.OnClick(ui.channelSettings.masterToggle)
    NS.RefreshUI(); NS.RefreshUI()
    check(NS.ChannelRemindersEnabled() and ui.clearToasts.label:GetText()=="清除泡泡 (4)",
        "reenabling master does not replay removed or suppressed public notifications")
    NS.ClearNotifications(); NS.MinimizeUI(); NS.RefreshUI()
    check(not ui.toasts[1]:IsShown(),"later redraw cannot replay the last suppressed public message")
    chat("CHAT_MSG_CHANNEL","重新开启后的新提醒","频道成员",13013,"Player-Public",1,"综合")
    check(ui.clearToasts.label:GetText()=="清除泡泡 (1)" and ui.toasts[1].conversationId==public.id,
        "reenabled public reminders start with the next new channel message only")
    NS.SetChannelRemindersEnabled(false); NS.ClearNotifications()
    C_Club,C_SocialRestrictions,CommunitiesFrame,InCombatLockdown=originalClub,originalSocial,originalNative,originalCombat
end
-- Compact notifications give the body two full lines while keeping metadata
-- smaller and clear of it, even when existing notifications change font size.
do
    NS.ClearNotifications(); expire(); NS.ResetAppearance(); NS.MinimizeUI()
    local originalWidth,originalHeight=UIParent:GetWidth(),UIParent:GetHeight()
    local originalPresence=NS.GetContactPresence
    NS.GetContactPresence=function() return "online" end
    UIParent:SetSize(1600,620)
    local sendsBefore,timersBefore=#sent,#timers
    for index=1,6 do
        chat("CHAT_MSG_WHISPER",string.rep("两行通知正文",14)..index,"紧凑泡泡测试-家族",14000+index,"Player-Compact")
    end
    local firstToast,firstMessage=ui.toasts[1],ui.toasts[1].item.message
    local function visibleCount()
        local count=0
        for _,toast in ipairs(ui.toasts) do if toast:IsShown() then count=count+1 end end
        return count
    end
    local function checkGeometry(description)
        local previousBottom
        for _,toast in ipairs(ui.toasts) do
            if toast:IsShown() then
                local bodyTop=-toast.preview.points.TOPLEFT.y
                -- Conservative native-font budget for two visible body lines.
                local bodyBottom=bodyTop+2*(toast.preview.fontSize+4)
                check(toast.preview.maxLines==2 and bodyBottom+8<=toast:GetHeight(),
                    description..": two full body lines retain at least eight pixels of bottom clearance")
                check(-toast.avatar.points.TOPLEFT.y+toast.avatar:GetHeight()<=bodyTop
                    and -toast.sender.points.TOPLEFT.y+toast.sender.fontSize+4<=bodyTop
                    and -toast.title.points.TOPRIGHT.y+toast.title.fontSize+4<=bodyTop,
                    description..": avatar, sender and category do not intrude into the body")
                check(toast.sender.fontSize<toast.preview.fontSize and toast.title.fontSize<toast.preview.fontSize
                    and toast.letter.fontSize<toast.preview.fontSize and not toast.hint and not toast.senderDetail,
                    description..": body is larger than visible metadata with no persistent detail or operation rows")
                check(toast.preview.points.TOPLEFT.x>=8
                    and toast.preview.points.TOPLEFT.x+toast.preview:GetWidth()+8<=toast:GetWidth(),
                    description..": full-width body retains padding within the narrow bubble")
                local senderRight=toast.sender.points.TOPLEFT.x+toast.sender:GetWidth()
                local titleLeft=toast:GetWidth()+toast.title.points.TOPRIGHT.x-toast.title:GetWidth()
                check(senderRight+2<=titleLeft,description..": long sender names stay clear of the right-aligned category")
                local top=-toast.points.TOPLEFT.y
                if previousBottom then check(top>=previousBottom+6,description..": stacked bubbles retain a visible gap") end
                previousBottom=top+toast:GetHeight()
                check(previousBottom<=UIParent:GetHeight(),description..": visible bubble stays on screen")
            end
        end
    end
    check(visibleCount()==4 and ui.toastPage:GetText():find("1–4 / 6",1,true),
        "compact default notifications fit four per page on a 620px screen")
    local bubbleLeft=firstToast.points.TOPLEFT.x
    local bubbleRight=bubbleLeft+firstToast:GetWidth()
    local clearLeft=ui.clearToasts.points.BOTTOMLEFT.x
    local previousLeft=ui.toastPrevious.points.BOTTOMLEFT.x
    local nextLeft=ui.toastNext.points.BOTTOMLEFT.x
    check(ui.clearToasts:IsShown() and ui.toastPrevious:IsShown() and ui.toastNext:IsShown()
        and clearLeft>=bubbleLeft and previousLeft>=bubbleLeft and nextLeft>=bubbleLeft
        and clearLeft+ui.clearToasts:GetWidth()<=bubbleRight
        and previousLeft+ui.toastPrevious:GetWidth()<=bubbleRight
        and nextLeft+ui.toastNext:GetWidth()<=bubbleRight,
        "clear and paging controls remain entirely within the narrow notification width")
    check(clearLeft+ui.clearToasts:GetWidth()+6<=previousLeft
        and previousLeft+ui.toastPrevious:GetWidth()+6<=nextLeft
        and ui.clearToasts:GetHeight()==22 and ui.toastPrevious:GetHeight()==22 and ui.toastNext:GetHeight()==22,
        "compact notification controls remain separated and use the same 22-pixel height")
    check(firstToast:GetWidth()<=260 and firstToast:GetHeight()<=74 and firstToast.preview.fontSize==14
        and distinct(firstToast.sender.textColor,firstToast.preview.textColor),
        "narrow notifications prioritize the configured body font over smaller muted metadata")
    check(firstToast.avatar:GetWidth()<=18 and firstToast.avatar:GetHeight()<=18
        and firstToast.avatar.presenceBadge:GetWidth()<=8 and firstToast.avatar.muteBadge:GetWidth()<=8
        and firstToast.avatar.presenceBadge.texture:find("\\online",1,true),
        "small avatar retains a compact online presence indicator without dominating the notification")
    check(#timers==timersBefore+4,"only the four initially displayed compact notifications start timers")
    checkGeometry("default notification font")
    local defaultHeight=firstToast:GetHeight()

    NS.UpdateAppearance({fontSize=22})
    check(firstToast:IsShown() and firstToast.item.message==firstMessage and firstToast.preview.fontSize==22
        and firstToast:GetHeight()>defaultHeight and firstToast:GetHeight()<=90 and firstToast:GetWidth()<=260,
        "font change immediately resizes and restyles an already visible notification without replacing its message")
    check(visibleCount()==3 and not ui.toasts[4]:IsShown() and ui.toastPage:GetText():find("1–3 / 6",1,true),
        "maximum font reduces page capacity to three and hides the former fourth visible frame")
    check(#timers==timersBefore+4,"enlarging existing notifications does not restart their lifetimes")
    checkGeometry("maximum notification font")
    NS.GetContactPresence=function() return "offline" end
    NS.RefreshUI()
    check(firstToast.avatar.presenceBadge.texture:find("\\offline",1,true) and firstToast.avatar.portrait.desaturated,
        "compact existing avatar still updates to verified offline styling")

    NS.UpdateAppearance({fontSize=14})
    check(visibleCount()==4 and firstToast:GetHeight()==defaultHeight and firstToast.preview.fontSize==14
        and ui.toastPage:GetText():find("1–4 / 6",1,true),
        "returning to default font restores four visible notifications and their compact height")
    check(#timers==timersBefore+4,"revealing a previously timed fourth notification does not renew its timer")
    ui.toastNext.scripts.OnClick(ui.toastNext)
    check(visibleCount()==4 and ui.toastPage:GetText():find("3–6 / 6",1,true) and #timers==timersBefore+6,
        "compact pagination starts timers only for the two never-before-visible queued messages")
    checkGeometry("compact second page")
    ui.toastPrevious.scripts.OnClick(ui.toastPrevious)
    check(firstToast.item.message==firstMessage and #timers==timersBefore+6,
        "returning to the compact first page preserves original message order and timers")
    NS.UpdateAppearance({fontSize=12})
    check(firstToast.preview.fontSize==12 and visibleCount()==4 and #timers==timersBefore+6,
        "minimum configured body font remains readable without changing active timer identity")
    checkGeometry("minimum notification font")
    check(#sent==sendsBefore,"notification resizing and paging never send chat")
    NS.GetContactPresence=originalPresence
    NS.ClearNotifications(); expire(); NS.ResetAppearance(); UIParent:SetSize(originalWidth,originalHeight)
end

print("chat_ui_test: "..checks.." checks passed")
