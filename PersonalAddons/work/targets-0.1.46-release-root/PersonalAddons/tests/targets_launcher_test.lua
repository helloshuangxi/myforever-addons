-- Launcher interaction simulation; actual hardware drag and clicks need WoW.
local checks,now,combat=0,10,false
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local methods={}
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template,shown=true,scripts={},
        width=0,height=0,children={},textures={}}, {__index=methods})
    if name then _G[name]=f end
    if parent then parent.children[#parent.children+1]=f end
    return f
end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point={...} end
function methods:GetPoint() return unpack(self.point) end
function methods:ClearAllPoints() self.point=nil end
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:Show() self.shown=true end
function methods:Hide()
    local was=self.shown;self.shown=false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:SetFrameStrata(value) self.strata=value end
function methods:SetFrameLevel(value) self.level=value end
function methods:SetBackdrop(value) self.backdrop=value end
function methods:SetBackdropColor(...) self.background={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetMovable(value) self.movable=value end
function methods:SetClampedToScreen(value) self.clamped=value end
function methods:EnableMouse(value) self.mouse=value end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:RegisterForDrag(...) self.drags={...} end
function methods:StartMoving() self.moving=true end
function methods:StopMovingOrSizing() self.moving=false end
function methods:CreateTexture()
    local t=frame("Texture",nil,self);self.textures[#self.textures+1]=t;return t
end
function methods:CreateFontString() return frame("FontString",nil,self) end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetFont(...) self.font={...} end
function methods:SetText(text) self.text=text end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetJustifyH(value) self.justifyH=value end
function methods:SetAlpha(value) self.alpha=value end
function methods:SetOwner(owner,anchor) self.owner,self.anchor=owner,anchor end
function methods:ClearLines() self.lines={} end
function methods:AddLine(text) self.lines[#self.lines+1]=text end
local fractions={TOPLEFT={0,1},TOPRIGHT={1,1},BOTTOMLEFT={0,0},BOTTOMRIGHT={1,0},
    TOP={.5,1},BOTTOM={.5,0},LEFT={0,.5},RIGHT={1,.5},CENTER={.5,.5}}
local function bounds(f)
    if f==UIParent then return 0,0,f.width,f.height end
    if f.overrideBounds then return unpack(f.overrideBounds) end
    local p=f.point
    local relative,relativePoint,x,y
    if type(p[2])=="number" then relative,relativePoint,x,y=f.parent,p[1],p[2],p[3]
    else relative,relativePoint,x,y=p[2] or f.parent,p[3] or p[1],p[4] or 0,p[5] or 0 end
    local l,b,w,h=bounds(relative)
    local a,r=fractions[p[1]],fractions[relativePoint]
    return l+w*r[1]+x-f.width*a[1],b+h*r[2]+y-f.height*a[2],f.width,f.height
end
function methods:GetLeft() local l=bounds(self);return l end
function methods:GetTop() local _,b,_,h=bounds(self);return b+h end
UIParent=frame("Frame","UIParent");UIParent:SetSize(1920,1080)
GameTooltip=frame("GameTooltip","GameTooltip");GameTooltip:ClearLines()
CreateFrame=frame
GetTime=function() return now end
STANDARD_TEXT_FONT="Fonts\\FRIZQT__.TTF"
local NS={DB={shown=true,friendlyShown=true,enemyShown=true,
    launcherPosition={point="LEFT",relativePoint="LEFT",x=24,y=0}}}
NS.Number=function(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
NS.Read=function(fn,...) if type(fn)=="function" then local ok,v=pcall(fn,...);if ok then return v end end end
NS.InCombat=function() return combat end
NS.IsPanelShown=function(side) return NS.DB[side.."Shown"]==true end
local calls={}
NS.SetPanelShown=function(side,value)
    local pending=NS.PendingSettings and NS.PendingSettings[side.."Shown"]
    if value==nil then
        if pending~=nil then value=not pending else value=not NS.IsPanelShown(side) end
    end
    calls[#calls+1]={kind="side",side=side,value=value}
    if combat then NS.PendingSettings=NS.PendingSettings or {};NS.PendingSettings[side.."Shown"]=value
    else NS.DB[side.."Shown"]=value;NS.DB.shown=NS.DB.friendlyShown or NS.DB.enemyShown end
end
NS.SetShown=function(value)
    if value==nil then value=not (NS.IsPanelShown("friendly") or NS.IsPanelShown("enemy")) end
    calls[#calls+1]={kind="all",value=value}
    if combat then NS.PendingSettings={friendlyShown=value,enemyShown=value}
    else NS.DB.friendlyShown=value;NS.DB.enemyShown=value;NS.DB.shown=value end
end
assert(loadfile("_forever_/Interface/AddOns/MyForeverTargets/Launcher.lua"))("MyForeverTargets",NS)
NS.CreateLauncher()
local icon=NS.Launcher
local menu=icon.menu
local function click(widget,button) widget:GetScript("OnClick")(widget,button or "LeftButton") end
eq(icon,MyForeverTargetsLauncher,"launcher has a discoverable global frame name")
eq(menu,MyForeverTargetsLauncherMenu,"menu has a discoverable global frame name")
eq(icon.parent,UIParent,"icon is independent of secure panels")
eq(menu.parent,UIParent,"menu is independent of icon and secure panels")
eq(icon.width,42,"launcher matches the shared addon size")
eq(icon.height,42,"launcher has the shared square hit area")
eq(menu.width,168,"menu has room for pending state without growing panels")
eq(icon.template,"BackdropTemplate","launcher never inherits a secure template")
eq(menu.template,"BackdropTemplate","menu never inherits a secure template")
eq(icon.label.text,"目","launcher uses the target label in the shared single-character style")
eq(icon.background[1],.42,"launcher uses the shared jade background")
eq(menu:IsShown(),false,"menu starts closed")
eq(menu.buttons.friendly.label.text,"友方面板：开","menu reflects initial friendly state")
eq(menu.buttons.enemy.label.text,"敌方面板：开","menu reflects initial enemy state")
local initialPosition=NS.DB.launcherPosition
NS.CreateLauncher();eq(NS.Launcher,icon,"creating launcher twice does not create another icon")
click(icon)
yes(menu:IsShown(),"left click opens the controls")
eq(menu.point[2],UIParent,"menu layout anchors only to unprotected UIParent")
local l,b,w,h=bounds(menu)
yes(l>=0 and b>=0 and l+w<=UIParent.width and b+h<=UIParent.height,"initial menu is fully on screen")
click(menu.buttons.friendly)
eq(calls[#calls].kind,"side","friendly control routes through visibility API")
eq(calls[#calls].side,"friendly","friendly control changes the intended side")
eq(NS.IsPanelShown("friendly"),false,"friendly control hides friendly panel")
eq(NS.IsPanelShown("enemy"),true,"friendly control preserves enemy visibility")
eq(menu:IsShown(),false,"a menu selection closes the menu")
eq(icon:IsShown(),true,"closing one side leaves icon visible")
click(icon);click(menu.buttons.enemy)
eq(NS.IsPanelShown("enemy"),false,"enemy control hides enemy panel")
eq(icon:IsShown(),true,"closing both sides leaves a recovery entry")
eq(menu.buttons.friendly.label.text,"友方面板：关","closed friendly state is explicit")
click(icon);click(menu.buttons.friendly)
eq(NS.IsPanelShown("friendly"),true,"menu can reopen just friendly panel")
eq(NS.IsPanelShown("enemy"),false,"reopening friendly does not open enemy")
click(icon);click(menu.buttons.show)
yes(NS.IsPanelShown("friendly") and NS.IsPanelShown("enemy"),"all-open action opens both panels")
click(icon);click(menu.buttons.hide)
eq(NS.DB.shown,false,"all-close action hides both panels")
eq(icon:IsShown(),true,"all-close never hides launcher")
click(icon,"RightButton")
yes(NS.IsPanelShown("friendly") and NS.IsPanelShown("enemy"),"right click restores both hidden panels")
click(icon,"RightButton")
eq(NS.DB.shown,false,"right click hides visible panels")
click(icon);click(icon)
eq(menu:IsShown(),false,"clicking icon again dismisses its menu")
click(icon);click(menu.close)
eq(menu:IsShown(),false,"menu close button dismisses only the menu")
eq(icon:IsShown(),true,"menu close does not remove launcher")

-- Queue handling is owned by Main; the launcher only requests and reports it.
combat=true
click(icon);click(menu.buttons.friendly)
eq(NS.IsPanelShown("friendly"),false,"combat request does not directly show a panel")
eq(NS.PendingSettings.friendlyShown,true,"combat click routes a pending open through the API")
eq(menu.buttons.friendly.label.text,"友方面板：关（待开）","pending open is visible in menu")
eq(icon:IsShown(),true,"launcher remains usable in combat")
click(icon);click(menu.buttons.friendly)
eq(NS.PendingSettings.friendlyShown,false,"second combat click cancels the pending open")
eq(menu.buttons.friendly.label.text,"友方面板：关","cancelled pending open does not leave a stale label")
click(icon);click(menu.buttons.show)
yes(NS.PendingSettings.friendlyShown and NS.PendingSettings.enemyShown,"all-open combat intent is sent atomically")
NS.DB.friendlyShown=true;NS.DB.enemyShown=true;NS.DB.shown=true
NS.PendingSettings=nil;combat=false;NS.RefreshLauncher()
eq(menu.buttons.enemy.label.text,"敌方面板：开","refresh after application removes pending labels")

icon:GetScript("OnEnter")(icon)
eq(GameTooltip:IsShown(),true,"launcher explains its controls on hover")
eq(GameTooltip.owner,icon,"tooltip is owned by launcher")
yes(table.concat(GameTooltip.lines," "):find("右键",1,true),"tooltip explains the right click shortcut")
icon:GetScript("OnLeave")(icon)
eq(GameTooltip:IsShown(),false,"leaving icon clears its tooltip")
combat=true;icon:GetScript("OnEnter")(icon)
yes(table.concat(GameTooltip.lines," "):find("脱战",1,true),"combat tooltip explains queued visibility")
combat=false

-- Native dragging changes the anchor; preserve that returned anchor verbatim.
click(icon)
icon:GetScript("OnDragStart")(icon)
eq(icon.dragging,true,"drag starts an explicit gesture")
eq(icon.moving,true,"drag moves the unprotected icon")
eq(menu:IsShown(),false,"drag dismisses menu")
eq(GameTooltip:IsShown(),false,"drag dismisses tooltip")
icon:SetPoint("BOTTOM",UIParent,"BOTTOM",-170,46)
icon:GetScript("OnDragStop")(icon)
eq(icon.dragging,false,"drag stop ends gesture")
eq(icon.moving,false,"drag stop releases native moving state")
eq(NS.DB.launcherPosition.point,"BOTTOM","drag preserves the native anchor rather than converting early screen geometry")
eq(NS.DB.launcherPosition.x,-170,"drag saves horizontal offset")
eq(NS.DB.launcherPosition.y,46,"drag saves vertical offset")
click(icon)
eq(menu:IsShown(),false,"drag-release click does not accidentally open the menu")
now=11;click(icon)
eq(menu:IsShown(),true,"next deliberate click still opens the menu")
local saved=NS.DB.launcherPosition
NS.RefreshLauncher();eq(NS.DB.launcherPosition,saved,"routine refresh does not rewrite saved position")
icon:GetScript("OnDragStart")(icon)
icon:SetPoint("BOTTOMRIGHT",nil,"BOTTOMRIGHT",-70,82)
icon:GetScript("OnDragStop")(icon)
eq(NS.DB.launcherPosition.x,-70,"native nil-relative screen anchor still saves the drag")
eq(NS.DB.launcherPosition.y,82,"native nil-relative screen anchor keeps vertical offset")
eq(icon.point[2],UIParent,"native screen anchor is explicitly normalized to UIParent")
icon:GetScript("OnDragStart")(icon)
icon:Hide()
eq(icon.dragging,false,"hidden launcher cancels drag state")
eq(icon.moving,false,"hidden launcher stops moving")
eq(menu:IsShown(),false,"hidden launcher dismisses detached menu")
NS.RefreshLauncher();eq(icon:IsShown(),true,"refresh keeps recovery entry available")

for _,corner in ipairs({{0,0,28,28},{1892,0,28,28},{0,1052,28,28},{1892,1052,28,28}}) do
    icon.overrideBounds=corner
    menu:Hide();now=now+1;click(icon)
    local x,y,mw,mh=bounds(menu)
    yes(x>=0 and y>=0 and x+mw<=1920 and y+mh<=1080,"menu remains on screen at every icon corner")
end
icon.overrideBounds=nil
NS.ResetLauncherPosition()
eq(NS.DB.launcherPosition.point,"LEFT","reset restores the left-side default anchor")
eq(NS.DB.launcherPosition.x,24,"reset restores default left margin")
eq(NS.DB.launcherPosition.y,0,"reset restores default vertical centre")
yes(NS.DB.launcherPosition~=initialPosition,"reset does not share a mutable defaults table")
-- A temporary native edge clamp must not overwrite the stored position.
NS.DB.launcherPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=1400,y=-900}
UIParent:SetSize(1365,768);NS.RefreshLauncher()
icon:SetPoint("TOPLEFT",UIParent,"TOPLEFT",1300,-700)
UIParent:SetSize(2133,1200);NS.RefreshLauncher()
eq(icon.point[4],1400,"final viewport reapplies saved x after a temporary clamp")
eq(icon.point[5],-900,"final viewport reapplies saved y after a temporary clamp")
eq(NS.DB.launcherPosition.y,-900,"temporary viewport never rewrites saved position")
print("Targets launcher simulated checks: "..checks.."; actual game clicks and icon dragging remain in-game checks")
