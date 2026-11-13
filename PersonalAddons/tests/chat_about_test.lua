local NS, checks, created = {}, 0, 0
local function check(value, label) checks=checks+1; assert(value, label) end
local function eq(actual, expected, label) checks=checks+1; assert(actual==expected, label) end
local methods = {}
function methods:SetScript(name, callback) self.scripts[name]=callback end
function methods:SetText(value)
    self.text=value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:SetSize(width,height) self.width,self.height=width,height end
function methods:SetWidth(width) self.width=width end
function methods:GetHeight() return self.height or 490 end
function methods:SetScrollChild(child) self.child=child end
function methods:SetVerticalScroll(offset) self.offset=offset end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:GetVerticalScrollRange() return 800 end
function methods:SetFocus() self.focus=true end
function methods:ClearFocus() self.focus=false end
function methods:HighlightText() self.selected=true end
function methods:SetCursorPosition(position) self.cursor=position end
function methods:Show() self.shown=true end
function methods:Hide()
    self.shown=false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:Raise() self.raised=true end
for _, name in ipairs({"SetPoint","SetFrameStrata","SetClampedToScreen","EnableMouse","SetMovable",
    "RegisterForDrag","StartMoving","StopMovingOrSizing","EnableMouseWheel","SetMultiLine",
    "SetAutoFocus","SetFontObject","SetTextInsets"}) do methods[name]=function() end end
local function widget(kind,name,parent,template)
    created=created+1
    local frame=setmetatable({kind=kind,name=name,parent=parent,scripts={},shown=true},{__index=methods})
    if name then _G[name]=frame end
    if template=="BasicFrameTemplateWithInset" then frame.TitleText=widget("FontString",nil,frame) end
    return frame
end
function methods:CreateFontString() return widget("FontString",nil,self) end
CreateFrame=widget
UIParent=widget("Frame")
UISpecialFrames={}
tinsert=table.insert
local version="0.8.1"
C_AddOns={GetAddOnMetadata=function(addon, field)
    eq(addon,"MyForeverChat","version lookup uses owning addon")
    eq(field,"Version","version lookup requests version metadata")
    return version
end}
local secret=setmetatable({secret=true},{__tostring=function() error("restricted value must not be formatted") end})
issecretvalue=function(value) return type(value)=="table" and rawget(value,"secret")==true end
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/About.lua"))("MyForeverChat",NS)
local before=created
local frame=NS.ShowAbout()
check(created>before and frame:IsShown(),"about window constructed and shown")
local ui=NS.aboutUI
eq(frame,ui.frame,"public handle points to current about window")
eq(ui.scroll.child,ui.text,"text is the scroll child")
local about=ui.text:GetText()
for _, fragment in ipairs({"MyForeverChat","版本 0.8.1","作者：Hyder","邮箱：267500@qq.com",
    "官网：https://afabiaoge.xyz/","服务器：PVE普通","阵营：联盟","公会：炉边余客","角色：苏氏集团苏晚晴",
    "允许使用、修改、分发和商用","须保留版权声明与许可文本","软件按现状提供","本窗口不会在游戏内打开外部网页"}) do
    check(about:find(fragment,1,true),"expected public author/license detail: "..fragment)
end
local licenseFile=assert(io.open("_forever_/Interface/AddOns/MyForeverChat/LICENSE.txt","r"))
local license=licenseFile:read("*a"):gsub("\n$",""); licenseFile:close()
check(about:sub(-#license)==license,"complete on-screen MIT text matches shipped license")
check(not about:find("mashuangxi",1,true),"local account name not disclosed")
eq(#UISpecialFrames,1,"escape registration created once")
eq(UISpecialFrames[1],"MyForeverChatAboutFrame","escape registration uses window name")
ui.selectAll.scripts.OnClick()
check(ui.text.focus and ui.text.selected,"select all permits native copying")
ui.text:SetText("accidental edit")
eq(ui.text:GetText(),about,"typing cannot modify author info or license")
ui.close.scripts.OnClick()
check(not frame:IsShown() and not ui.text.focus,"close button hides frame and clears edit focus")
local afterBuild=created
eq(NS.ShowAbout(),frame,"reopening reuses existing frame")
eq(created,afterBuild,"reopening does not create duplicate controls")
eq(#UISpecialFrames,1,"reopening does not duplicate escape registration")
ui.text:SetFocus()
ui.text.scripts.OnEscapePressed()
check(not frame:IsShown() and not ui.text.focus,"escape closes about and releases keyboard focus")
NS.ShowAbout()
ui.scroll.scripts.OnMouseWheel(ui.scroll,-1)
eq(ui.scroll:GetVerticalScroll(),36,"license can scroll down")
ui.scroll.scripts.OnMouseWheel(ui.scroll,100)
eq(ui.scroll:GetVerticalScroll(),0,"scroll clamps at beginning")
version="0.9.0"
NS.ShowAbout()
check(ui.text:GetText():find("版本 0.9.0",1,true),"reopen reads current addon version metadata")
version=secret
NS.ShowAbout()
check(ui.text:GetText():find("版本 0.9.0",1,true),"restricted metadata safely falls back")
C_AddOns.GetAddOnMetadata=function() error("metadata unavailable") end
NS.ShowAbout()
check(frame:IsShown(),"unavailable metadata does not prevent about panel opening")
print("chat_about_test: "..checks.." checks passed")
