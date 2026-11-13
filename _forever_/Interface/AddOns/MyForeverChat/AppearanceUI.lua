local _, NS = ...
local frame, context, syncing, ownedPickerToken
local presets = {
    -- Suite default since 2026-11-14 (UX-001 direction B).
    { id="midnight", label="午夜", background={0.051,0.067,0.118}, accent={0.486,0.576,1.0} },
    { id="jade", label="青玉", background={0.055,0.067,0.072}, accent={0.42,0.82,0.58} },
    { id="ocean", label="海蓝", background={0.04,0.065,0.10}, accent={0.32,0.65,0.95} },
    { id="violet", label="紫晶", background={0.065,0.05,0.095}, accent={0.70,0.52,0.94} },
    { id="amber", label="暖金", background={0.09,0.065,0.04}, accent={0.95,0.68,0.28} },
}
local function copyColor(color) return {color[1],color[2],color[3]} end
local function appearance() return NS.db and NS.db.appearance end
local function status(message)
    if frame and frame.note then frame.note:SetText(message or "") end
end
local function ownsPicker(token)
    local picker=ColorPickerFrame
    return picker and type(picker.GetExtraInfo)=="function" and picker:GetExtraInfo()==token
end
local function cancelOwnPicker()
    local token=ownedPickerToken
    local picker=ColorPickerFrame
    if token and picker and picker:IsShown() and ownsPicker(token) and type(picker.OnCancel)=="function" then
        picker:OnCancel()
    end
    ownedPickerToken=nil
end
local function apply(patch)
    NS.UpdateAppearance(patch)
    NS.SyncAppearanceSettings()
end
local function openColor(field)
    local picker=ColorPickerFrame
    if not picker or type(picker.SetupColorPickerAndShow)~="function"
        or type(picker.GetExtraInfo)~="function" or type(picker.GetColorRGB)~="function" then
        status("当前客户端的调色窗口不可用。")
        return
    end
    if picker:IsShown() then
        if picker.Raise then picker:Raise() end
        status("请先完成已打开的调色窗口，再选择其他颜色。")
        return
    end
    local app=appearance()
    local original, originalTheme=copyColor(app[field]),app.theme
    local token={owner="MyForeverChatAppearance",field=field}
    ownedPickerToken=token
    local function updateSwatch()
        if not ownsPicker(token) then return end
        local r,g,b=picker:GetColorRGB()
        apply({[field]={r,g,b},theme="custom"})
        status("颜色已即时预览；调色窗口点“取消”可恢复。")
    end
    local function cancelSwatch()
        if not ownsPicker(token) then return end
        apply({[field]=copyColor(original),theme=originalTheme})
        if ownedPickerToken==token then ownedPickerToken=nil end
        status("已恢复调色前的颜色。")
    end
    -- Setup can synchronously call swatchFunc. Baseline and token exist first.
    picker:SetupColorPickerAndShow({
        r=original[1],g=original[2],b=original[3],hasOpacity=false,
        swatchFunc=updateSwatch,cancelFunc=cancelSwatch,extraInfo=token,
    })
    if ownsPicker(token) and picker.Raise then picker:Raise() end
end

function NS.SyncAppearanceSettings()
    if not frame then return end
    local app=appearance()
    if not app then return end
    syncing=true
    frame.fontSlider:SetValue(app.fontSize)
    frame.fontSlider.Text:SetText("聊天字号："..app.fontSize)
    local percent=math.floor(app.opacity*100+0.5)
    frame.opacitySlider:SetValue(percent)
    frame.opacitySlider.Text:SetText("背景不透明度："..percent.."%")
    for _,slider in ipairs({frame.fontSlider,frame.opacitySlider}) do
        slider.Text:SetTextColor(unpack(context.palette.text))
        slider.Low:SetTextColor(unpack(context.palette.muted))
        slider.High:SetTextColor(unpack(context.palette.muted))
    end
    for _,definition in ipairs(presets) do
        local b=frame.presets[definition.id]
        b.label:SetText(definition.label..(app.theme==definition.id and " · 已选" or ""))
    end
    for _,field in ipairs({"background","accent"}) do
        local swatch=frame.swatches[field]
        local color=app[field]
        swatch:SetBackdropColor(color[1],color[2],color[3],1)
        swatch:SetBackdropBorderColor(color[1],color[2],color[3],1)
    end
    syncing=false
end

local function makeSlider(parent,x,y,minValue,maxValue,onValue)
    local slider=CreateFrame("Slider",nil,parent,"UISliderTemplateWithLabels")
    slider:SetPoint("TOPLEFT",x,y)
    slider:SetSize(420,18)
    slider:SetMinMaxValues(minValue,maxValue)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText(tostring(minValue))
    slider.High:SetText(tostring(maxValue))
    slider:SetScript("OnValueChanged",function(_,value)
        if syncing then return end
        onValue(math.max(minValue,math.min(maxValue,math.floor(value+0.5))))
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel",function(self,delta)
        local direction=delta>0 and 1 or (delta<0 and -1 or 0)
        self:SetValue(math.max(minValue,math.min(maxValue,self:GetValue()+direction)))
    end)
    return slider
end

function NS.OpenAppearanceSettings()
    if not frame then
        if type(NS.GetAppearanceContext)~="function" then return nil,"聊天外观界面尚未就绪。" end
        context=NS.GetAppearanceContext()
        if not context or not context.parent then return nil,"聊天窗口尚未就绪。" end
        local palette=context.palette
        frame=CreateFrame("Frame","MyForeverChatSettings",context.parent,"BackdropTemplate")
        frame:SetSize(480,420)
        frame:SetPoint("CENTER",context.parent,"CENTER",0,0)
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(context.parent:GetFrameLevel()+20)
        frame:EnableMouse(true)
        frame:SetClampedToScreen(true)
        frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,
            insets={left=3,right=3,top=3,bottom=3}})
        frame:SetBackdropColor(palette.outer[1],palette.outer[2],palette.outer[3],math.max(0.94,palette.outer[4] or 1))
        frame:SetBackdropBorderColor(palette.outer[1],palette.outer[2],palette.outer[3],1)
        if context.registerSurface then context.registerSurface(frame,palette.outer,true) end
        local title=context.text(frame,20,palette.text)
        title:SetPoint("TOPLEFT",24,-18); title:SetText("聊天外观")
        local help=context.text(frame,12,palette.muted)
        help:SetPoint("TOPLEFT",24,-50); help:SetText("修改即时保存；可单独恢复默认外观。")
        local close=context.button(frame,"×",30,28,function() frame:Hide() end)
        close:SetPoint("TOPRIGHT",-12,-12)
        frame.fontSlider=makeSlider(frame,30,-99,12,22,function(value)
            apply({fontSize=value})
        end)
        frame.opacitySlider=makeSlider(frame,30,-173,25,100,function(value)
            apply({opacity=value/100})
        end)
        local themeLabel=context.text(frame,13,palette.text)
        themeLabel:SetPoint("TOPLEFT",24,-216); themeLabel:SetText("配色")
        frame.presets={}
        for i,definition in ipairs(presets) do
            local data=definition
            local b=context.button(frame,data.label,100,28,function()
                cancelOwnPicker()
                local app=appearance()
                apply({fontSize=app.fontSize,opacity=app.opacity,theme=data.id,
                    background=copyColor(data.background),accent=copyColor(data.accent)})
                status("已使用"..data.label.."配色。")
            end)
            b:SetPoint("TOPLEFT",24+(i-1)*110,-241)
            frame.presets[data.id]=b
        end
        frame.bgButton=context.button(frame,"自定义背景色",208,32,function() openColor("background") end)
        frame.bgButton:SetPoint("TOPLEFT",24,-288)
        frame.accentButton=context.button(frame,"自定义强调色",208,32,function() openColor("accent") end)
        frame.accentButton:SetPoint("TOPLEFT",248,-288)
        frame.swatches={}
        for field,button in pairs({background=frame.bgButton,accent=frame.accentButton}) do
            local swatch=context.box("Frame",button,palette.surface,true)
            swatch:SetSize(16,16); swatch:SetPoint("LEFT",12,0)
            frame.swatches[field]=swatch
        end
        frame.reset=context.button(frame,"恢复默认",120,28,function()
            cancelOwnPicker()
            NS.ResetAppearance()
            NS.SyncAppearanceSettings()
            status("已恢复默认外观，聊天记录和草稿保留。")
        end)
        frame.reset:SetPoint("TOPLEFT",24,-344)
        local done=context.button(frame,"完成",112,28,function() frame:Hide() end,palette.green)
        done:SetPoint("TOPRIGHT",-24,-344)
        frame.note=context.text(frame,12,palette.muted)
        frame.note:SetPoint("TOPLEFT",24,-386); frame.note:SetWidth(432); frame.note:SetHeight(24)
        frame:SetScript("OnHide",cancelOwnPicker)
        UISpecialFrames[#UISpecialFrames+1]="MyForeverChatSettings"
        NS.appearanceUI={
            frame=frame,fontSlider=frame.fontSlider,opacitySlider=frame.opacitySlider,
            presets=frame.presets,bgButton=frame.bgButton,accentButton=frame.accentButton,reset=frame.reset,
        }
    end
    frame:Show()
    NS.SyncAppearanceSettings()
    status("拖动滑块或使用鼠标滚轮调整。")
    return frame
end
