local _, NS = ...
local Style = MyForeverStyle
local function C(name,alpha) return Style.Color(name,alpha) end

local WHITE="Interface\\Buttons\\WHITE8X8"
local BACKDROP={bgFile=WHITE,edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10,
    insets={left=3,right=3,top=3,bottom=3}}
local ICON_BACKDROP={bgFile=WHITE,edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,
    insets={left=3,right=3,top=3,bottom=3}}
local DEFAULT_POSITION={point="LEFT",relativePoint="LEFT",x=24,y=0}
local MENU_WIDTH,MENU_HEIGHT=168,130

local function hideTip()
    if GameTooltip then GameTooltip:Hide() end
end

local function label(parent,size)
    local text=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    if text.SetFont and STANDARD_TEXT_FONT then text:SetFont(STANDARD_TEXT_FONT,size or 11,"") end
    text:SetTextColor(C("text"))
    return text
end

local function positionKey(position)
    return table.concat({position.point,position.relativePoint,position.x,position.y},":")
end

local function applyPosition(icon)
    local position=NS.DB.launcherPosition or DEFAULT_POSITION
    local key=positionKey(position)
    -- Preserve the anchor through startup UI scale changes. Only a completed
    -- user drag writes a new location; temporary screen clamps never do.
    local width,height=NS.Read(UIParent.GetWidth,UIParent),NS.Read(UIParent.GetHeight,UIParent)
    local viewport=NS.Number(width) and NS.Number(height) and table.concat({width,height},":") or nil
    if not icon.dragging and (icon.positionKey~=key or icon.viewportKey~=viewport) then
        icon:ClearAllPoints()
        icon:SetPoint(position.point,UIParent,position.relativePoint,position.x,position.y)
        icon.positionKey=key
    end
    icon.viewportKey=viewport
end

local function placeMenu(icon,menu)
    local width,height=NS.Read(UIParent.GetWidth,UIParent),NS.Read(UIParent.GetHeight,UIParent)
    local left,top=NS.Read(icon.GetLeft,icon),NS.Read(icon.GetTop,icon)
    if not NS.Number(width) or not NS.Number(height) or not NS.Number(left) or not NS.Number(top) then
        menu:ClearAllPoints();menu:SetPoint("CENTER",UIParent,"CENTER",0,0)
        return
    end
    local x=math.max(4,math.min(left,width-MENU_WIDTH-4))
    local y=top-icon:GetHeight()-4
    if y-MENU_HEIGHT<4 then y=math.min(height-4,top+MENU_HEIGHT+4) end
    y=math.max(MENU_HEIGHT+4,math.min(y,height-4))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",x,y)
end

local function menuButton(menu,key,y,action)
    local button=CreateFrame("Button",nil,menu,"BackdropTemplate")
    button:SetSize(MENU_WIDTH-12,22)
    button:SetPoint("TOPLEFT",6,-y)
    button:SetBackdrop(BACKDROP)
    button:SetBackdropColor(C("surface"))
    button:SetBackdropBorderColor(C("line"))
    button.label=label(button,11)
    button.label:SetPoint("CENTER")
    button:SetScript("OnEnter",function(self) self:SetBackdropBorderColor(C("accent")) end)
    button:SetScript("OnLeave",function(self) self:SetBackdropBorderColor(C("line")) end)
    button:SetScript("OnClick",function()
        action()
        NS.RefreshLauncher()
        menu:Hide()
    end)
    menu.buttons[key]=button
    return button
end

function NS.RefreshLauncher()
    local icon=NS.Launcher
    if not icon or not NS.DB then return end
    applyPosition(icon)
    icon:Show()
    for _,side in ipairs({"friendly","enemy"}) do
        local shown=NS.IsPanelShown(side)
        local pending=NS.PendingSettings and NS.PendingSettings[side.."Shown"]
        local suffix=type(pending)=="boolean" and pending~=shown and (pending and "（待开）" or "（待关）") or ""
        icon.menu.buttons[side].label:SetText((side=="friendly" and "友方面板：" or "敌方面板：")..
            (shown and "开" or "关")..suffix)
    end
    if icon.menu:IsShown() then placeMenu(icon,icon.menu) end
end

function NS.ResetLauncherPosition()
    if not NS.DB then return end
    NS.DB.launcherPosition={point=DEFAULT_POSITION.point,relativePoint=DEFAULT_POSITION.relativePoint,
        x=DEFAULT_POSITION.x,y=DEFAULT_POSITION.y,manual=false}
    NS.RefreshLauncher()
end

function NS.CreateLauncher()
    if NS.Launcher or not NS.DB then return end
    local icon=CreateFrame("Button","MyForeverTargetsLauncher",UIParent,"BackdropTemplate")
    icon:SetSize(42,42)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(30)
    -- Match the shared Chat / Professions / Navigator launcher appearance.
    icon:SetBackdrop(ICON_BACKDROP)
    icon:SetBackdropColor(.42,.82,.58,.98)
    icon:SetBackdropBorderColor(.42,.82,.58,.98)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:RegisterForClicks("LeftButtonUp","RightButtonUp")
    icon:RegisterForDrag("LeftButton")
    icon.label=icon:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    if icon.label.SetFont and STANDARD_TEXT_FONT then icon.label:SetFont(STANDARD_TEXT_FONT,12,"") end
    icon.label:SetPoint("CENTER")
    icon.label:SetJustifyH("CENTER")
    icon.label:SetTextColor(.06,.16,.10,1)
    icon.label:SetText("目")

    -- Independent UIParent ownership avoids inheriting protected unit buttons.
    local menu=CreateFrame("Frame","MyForeverTargetsLauncherMenu",UIParent,"BackdropTemplate")
    menu:SetSize(MENU_WIDTH,MENU_HEIGHT)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(30)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop(BACKDROP)
    menu:SetBackdropColor(C("outer",.98))
    menu:SetBackdropBorderColor(C("line"))
    menu.buttons={}
    menu.title=label(menu,11)
    menu.title:SetPoint("TOPLEFT",9,-8)
    menu.title:SetText("目标选择")
    menu.close=CreateFrame("Button",nil,menu)
    menu.close:SetSize(20,20)
    menu.close:SetPoint("TOPRIGHT",-4,-3)
    menu.close.label=label(menu.close,14)
    menu.close.label:SetPoint("CENTER")
    menu.close.label:SetText("×")
    menu.close:SetScript("OnClick",function() menu:Hide() end)
    menuButton(menu,"friendly",28,function() NS.SetPanelShown("friendly") end)
    menuButton(menu,"enemy",52,function() NS.SetPanelShown("enemy") end)
    menuButton(menu,"show",76,function() NS.SetShown(true) end).label:SetText("全部打开")
    menuButton(menu,"hide",100,function() NS.SetShown(false) end).label:SetText("全部关闭")
    menu:Hide()
    icon.menu=menu
    NS.Launcher=icon
    icon:SetScript("OnEnter",function(self)
        self:SetAlpha(.82)
        if self.dragging or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("目标选择",.93,.85,.65)
        GameTooltip:AddLine("左键打开面板菜单；右键全部显示／隐藏。",.85,.88,.92,true)
        GameTooltip:AddLine("拖动图标可移动；关闭面板后图标仍保留。",.85,.88,.92,true)
        if NS.InCombat() then GameTooltip:AddLine("战斗中记住开关，脱战后应用。",1,.8,.35,true) end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave",function(self) self:SetAlpha(1);hideTip() end)
    icon:SetScript("OnClick",function(self,button)
        local now=NS.Read(GetTime)
        if self.dragging or NS.Number(now) and self.suppressClickUntil and now<self.suppressClickUntil then return end
        hideTip()
        if button=="RightButton" then
            menu:Hide();NS.SetShown();NS.RefreshLauncher()
        elseif menu:IsShown() then menu:Hide()
        else NS.RefreshLauncher();placeMenu(self,menu);menu:Show() end
    end)
    icon:SetScript("OnDragStart",function(self)
        menu:Hide();hideTip()
        self.dragging=true
        self:StartMoving()
    end)
    icon:SetScript("OnDragStop",function(self)
        if not self.dragging then return end
        self:StopMovingOrSizing()
        self.dragging=false
        local point,relativeTo,relativePoint,x,y=self:GetPoint()
        if (relativeTo==nil or relativeTo==UIParent) and type(point)=="string" and type(relativePoint)=="string"
            and NS.Number(x) and NS.Number(y) then
            NS.DB.launcherPosition={point=point,relativePoint=relativePoint,x=x,y=y,manual=true}
            if relativeTo==nil then
                self:ClearAllPoints()
                self:SetPoint(point,UIParent,relativePoint,x,y)
            end
            self.positionKey=positionKey(NS.DB.launcherPosition)
        end
        local now=NS.Read(GetTime)
        self.suppressClickUntil=NS.Number(now) and now+.2 or nil
    end)
    icon:SetScript("OnHide",function(self)
        if self.dragging then self:StopMovingOrSizing() end
        self.dragging=false
        menu:Hide();hideTip()
    end)
    NS.RefreshLauncher()
end
