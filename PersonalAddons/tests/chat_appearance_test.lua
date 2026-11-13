local NS,checks={},0
local function check(value,label) checks=checks+1; assert(value,label) end
local function equal(actual,expected,label)
    checks=checks+1
    assert(actual==expected,(label or "equal")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local methods={}
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:SetText(value) self.text=value end
function methods:SetTextColor(...) self.textColor={...} end
function methods:GetText() return self.text end
function methods:SetPoint(...) self.point={...} end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetFrameLevel(value) self.level=value end
function methods:GetFrameLevel() return self.level or 0 end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetBackdropColor(...) self.color={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetMinMaxValues(low,high) self.min,self.max=low,high end
function methods:SetValueStep(value) self.step=value end
function methods:SetObeyStepOnDrag(value) self.obey=value end
function methods:EnableMouseWheel(value) self.wheel=value end
function methods:SetValue(value)
    self.value=value
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value) end
end
function methods:GetValue() return self.value end
function methods:IsShown() return self.shown end
function methods:Show() self.shown=true end
function methods:Hide()
    local old=self.shown; self.shown=false
    if old and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Raise() self.raised=(self.raised or 0)+1 end
for _,name in ipairs({"SetBackdrop","SetClampedToScreen"}) do methods[name]=function() end end
local function widget(kind,name,parent,template)
    local f=setmetatable({kind=kind,parent=parent,scripts={},shown=false,template=template},{__index=methods})
    if name then _G[name]=f end
    if template=="UISliderTemplateWithLabels" then
        f.Low=widget("FontString",nil,f); f.High=widget("FontString",nil,f); f.Text=widget("FontString",nil,f)
    end
    return f
end
CreateFrame=widget
UISpecialFrames={}
local palette={outer={0.055,0.067,0.072,0.25},surface={0.12,0.14,0.15,1},text={1,1,1,1},muted={0.6,0.6,0.6,1},green={0.42,0.82,0.58,1}}
local parent=widget("Frame"); parent.level=7
local registered=0
local function box(kind,p,color)
    local f=widget(kind or "Frame",nil,p); f:SetBackdropColor(unpack(color)); return f
end
local function text(p) return widget("FontString",nil,p) end
local function button(p,caption,w,h,fn)
    local f=widget("Button",nil,p); f.label=text(f); f.label:SetText(caption); f:SetSize(w,h); f:SetScript("OnClick",fn); return f
end
NS.GetAppearanceContext=function()
    return {parent=parent,palette=palette,box=box,text=text,button=button,registerSurface=function(_,_,opaque)
        check(opaque==true,"settings surface remains opaque"); registered=registered+1
    end}
end
local defaults={fontSize=14,opacity=0.98,theme="jade",background={0.055,0.067,0.072},accent={0.42,0.82,0.58}}
local function copy(value)
    local result={}
    for k,v in pairs(value) do
        if type(v)=="table" then result[k]={unpack(v)} else result[k]=v end
    end
    return result
end
local updates,resets=0,0
NS.db={appearance=copy(defaults),draft="原来的草稿",messages={"历史"}}
NS.UpdateAppearance=function(patch)
    updates=updates+1
    check(updates<100,"slider sync must not recurse")
    for k,v in pairs(patch) do NS.db.appearance[k]=type(v)=="table" and {unpack(v)} or v end
    if NS.SyncAppearanceSettings then NS.SyncAppearanceSettings() end
end
NS.ResetAppearance=function()
    resets=resets+1; NS.db.appearance=copy(defaults)
    if NS.SyncAppearanceSettings then NS.SyncAppearanceSettings() end
end
local picker=widget("Frame","ColorPickerFrame")
picker.setupCalls=0
function picker:GetExtraInfo() return self.extraInfo end
function picker:GetColorRGB() return self.r,self.g,self.b end
function picker:SetupColorPickerAndShow(info)
    self.setupCalls=self.setupCalls+1
    self.info=info; self.extraInfo=info.extraInfo; self.r,self.g,self.b=info.r,info.g,info.b
    self.shown=true
    info.swatchFunc() -- Matches native Setup's synchronous color-select possibility.
end
function picker:OnCancel()
    self.cancelCalls=(self.cancelCalls or 0)+1
    if self.info and self.info.cancelFunc then self.info.cancelFunc({r=self.r,g=self.g,b=self.b}) end
    self:Hide()
end
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/AppearanceUI.lua"))("MyForeverChat",NS)
local f=NS.OpenAppearanceSettings()
local ui=NS.appearanceUI
check(f==ui.frame and f:IsShown(),"settings window opens")
equal(f.level,27,"settings above conversation child frames")
equal(f.strata,"DIALOG","native picker compatible strata")
equal(f.mouse,true,"settings intercept mouse")
equal(f.color[4],0.94,"settings stay readable at low chat alpha")
equal(registered,1,"surface registered for later theme changes")
equal(updates,0,"initial controls sync does not write")
equal(ui.fontSlider.value,14,"initial font")
equal(ui.opacitySlider.value,98,"initial alpha in percent")
equal(ui.fontSlider.Text.textColor[1],palette.text[1],"native slider title uses current readable color")
equal(ui.opacitySlider.Low.textColor[1],palette.muted[1],"native slider range uses current muted color")
check(ui.fontSlider.obey and ui.fontSlider.wheel,"stepped dragging and wheel enabled")
ui.fontSlider:SetValue(18)
equal(NS.db.appearance.fontSize,18,"font slider applies immediately")
equal(updates,1,"font change writes once despite sync callback")
ui.fontSlider.scripts.OnMouseWheel(ui.fontSlider,1)
equal(NS.db.appearance.fontSize,19,"wheel increments one")
ui.opacitySlider.scripts.OnMouseWheel(ui.opacitySlider,-1)
equal(NS.db.appearance.opacity,0.97,"opacity wheel decrements percent")
ui.presets.ocean.scripts.OnClick()
equal(NS.db.appearance.theme,"ocean","preset theme saved")
equal(NS.db.appearance.background[1],0.04,"preset changes background")
equal(NS.db.appearance.accent[3],0.95,"preset changes accent")
equal(NS.db.appearance.fontSize,19,"preset preserves selected font")
equal(NS.db.appearance.opacity,0.97,"preset preserves selected alpha")
check(ui.presets.ocean.label:GetText():find("已选",1,true),"selected preset not conveyed solely by color")
ui.bgButton.scripts.OnClick()
equal(picker.setupCalls,1,"custom color opens native picker")
check(type(picker.info.swatchFunc)=="function" and type(picker.info.cancelFunc)=="function","required picker callbacks supplied")
equal(picker.info.hasOpacity,false,"color picker does not steal alpha setting")
equal(NS.db.appearance.theme,"custom","live preview marks custom")
picker.r,picker.g,picker.b=0.2,0.3,0.4; picker.info.swatchFunc()
equal(NS.db.appearance.background[2],0.3,"color preview applies")
picker:OnCancel()
equal(NS.db.appearance.background[1],0.04,"cancel restores original color, not picker previous args")
equal(NS.db.appearance.theme,"ocean","cancel restores original theme")
ui.accentButton.scripts.OnClick()
picker.r,picker.g,picker.b=0.9,0.8,0.7; picker.info.swatchFunc()
equal(NS.db.appearance.accent[1],0.9,"accent preview")
f:Hide()
equal(picker:IsShown(),false,"hiding settings cancels own open picker")
equal(NS.db.appearance.accent[1],0.32,"settings close restores unconfirmed accent")
equal(NS.db.appearance.theme,"ocean","settings close restores original theme")
NS.OpenAppearanceSettings()
local foreignToken={}
picker.extraInfo=foreignToken; picker.shown=true
local oldCalls=picker.setupCalls; local oldCancel=picker.cancelCalls
ui.bgButton.scripts.OnClick()
equal(picker.setupCalls,oldCalls,"another addon picker never overwritten")
check(f.note:GetText():find("先完成",1,true),"busy picker has clear feedback")
f:Hide()
equal(picker.cancelCalls,oldCancel,"closing settings does not cancel another addon's picker")
equal(picker.extraInfo,foreignToken,"foreign picker identity preserved")
picker.shown=false
NS.OpenAppearanceSettings(); ui.bgButton.scripts.OnClick()
local stale=picker.info
picker.extraInfo={}
local oldColor=NS.db.appearance.background[1]
picker.r=0.77; stale.swatchFunc(); stale.cancelFunc()
equal(NS.db.appearance.background[1],oldColor,"stale callbacks cannot affect another picker")
picker.shown=false
ui.reset.scripts.OnClick()
equal(resets,1,"reset uses appearance-only API")
equal(NS.db.appearance.fontSize,14,"reset font")
equal(NS.db.appearance.opacity,0.98,"reset alpha")
equal(NS.db.appearance.theme,"jade","reset palette")
equal(NS.db.draft,"原来的草稿","reset keeps draft")
equal(NS.db.messages[1],"历史","reset keeps history")
equal(ui.fontSlider.value,14,"reset synchronizes controls")
check(NS.OpenAppearanceSettings()==f,"settings window reused")
equal(registered,1,"reopen does not duplicate surface registration")
print("chat_appearance_test: "..checks.." checks passed")
