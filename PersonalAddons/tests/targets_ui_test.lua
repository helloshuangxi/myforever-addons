-- Drags here check exact saved offsets; hold "Alt" so the shared grid/guide
-- snapping (covered by style_layout_test.lua) leaves drops where they land.
IsAltKeyDown = function() return true end
dofile("_forever_/Interface/AddOns/MyForeverTargets/MyForeverStyle.lua")
-- Native frame simulation. Restricted snippets and secure mouseover are NOT emulated.
local checks, combat, secureModel = 0, false, false
local function eq(actual, expected, why)
    checks=checks+1
    assert(actual==expected, why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local methods, frames = {}, {}
local unitTooltipResult,unitTooltipThrows=true,false
local function tooltipOperation(frame,operation)
    if frame.kind~="GameTooltip" then return end
    frame.tooltipOperations=frame.tooltipOperations or {}
    frame.tooltipOperations[#frame.tooltipOperations+1]=operation
end
-- Model object-specific APIs instead of making every mock object a universal
-- widget. In particular, SecureHandlerBaseTemplate does not add SetFrameRef.
local function isKind(...)
    local kinds={}
    for _,kind in ipairs({...}) do kinds[kind]=true end
    return function(frame) return kinds[frame.kind] end
end
local capabilities={}
local function restrict(names,available)
    for _,name in ipairs(names) do capabilities[name]=available end
end
restrict({"SetTexture","SetTexCoord","SetVertexColor","SetColorTexture","SetRotation","SetBlendMode"},isKind("Texture"))
restrict({"SetFont","GetFont","SetTextColor","SetJustifyH","SetJustifyV","SetWordWrap","SetSpacing",
    "SetShadowColor","SetShadowOffset"},isKind("FontString"))
restrict({"SetText"},isKind("FontString","Button","GameTooltip"))
restrict({"GetText"},isKind("FontString","Button"))
restrict({"SetStatusBarTexture","SetStatusBarColor","SetValue","SetMinMaxValues","SetOrientation","SetReverseFill"},isKind("StatusBar"))
restrict({"SetHighlightTexture","GetHighlightTexture","SetEnabled","IsEnabled","RegisterForClicks"},isKind("Button"))
restrict({"SetAttribute","GetAttribute","SetFrameLevel","GetFrameLevel","SetFrameStrata","EnableMouse",
    "SetMovable","SetClampedToScreen","RegisterForDrag","StartMoving","StopMovingOrSizing",
    "CreateTexture","CreateFontString","RegisterEvent","RegisterUnitEvent","UnregisterEvent"},
    isKind("Frame","Button","StatusBar","GameTooltip"))
restrict({"SetOwner","AddLine","ClearLines","SetUnit"},isKind("GameTooltip"))
restrict({"SetBackdrop","SetBackdropColor","SetBackdropBorderColor"},function(frame)
    return frame.template:find("BackdropTemplate",1,true)~=nil
end)
local builtinUnitClick=function() end
local nativeActionClicks=0
local builtinActionClick=function() nativeActionClicks=nativeActionClicks+1 end
SecureActionButton_OnClick=builtinActionClick
local function guard(self, operation)
    assert(not (combat and self.protected and not secureModel), "Protected "..operation.." in combat on "..tostring(self.name))
end
local function newFrame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",shown=true,
        scripts={},hooks={},attrs={},refs={},children={},width=0,height=0,level=1,scale=1,alpha=1}, {__index=function(self,key)
            if capabilities[key] and not capabilities[key](self) then return nil end
            return methods[key]
        end})
    frames[#frames+1]=f
    if parent then parent.children[#parent.children+1]=f end
    if name then _G[name]=f end
    if f.template:find("Secure",1,true) then
        f.protected=true
        local p=parent
        while p and p~=UIParent do p.protected=true;p=p.parent end
    end
    for templateName in f.template:gmatch("[^,]+") do
        if templateName=="SecureUnitButtonTemplate" then f.scripts.OnClick=builtinUnitClick end
        if templateName=="SecureActionButtonTemplate" then f.scripts.OnClick=builtinActionClick end
    end
    return f
end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:IsProtected() return self.protected or false end
function methods:IsForbidden() return self.forbidden or false end
function methods:SetScript(key,fn)
    if key=="OnClick" and self.side and self.template:find("SecureActionButtonTemplate",1,true) then
        guard(self,"SetScript OnClick")
        error("Target row must keep its XML-installed native OnClick untouched")
    end
    self.scripts[key]=fn
end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key,fn)
    local previous=self.hooks[key]
    self.hooks[key]=previous and function(...) previous(...);fn(...) end or fn
end
function methods:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function methods:RegisterUnitEvent(event) self:RegisterEvent(event) end
function methods:UnregisterEvent(event) if self.events then self.events[event]=nil end end
function methods:SetAttribute(key,value) guard(self,"SetAttribute");self.attrs[key]=value end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:RegisterForClicks(...) guard(self,"RegisterForClicks");self.clicks={...} end
function methods:SetPoint(...)
    guard(self,"SetPoint");self.point={...}
    self.points=self.points or {};self.points[#self.points+1]=self.point
end
function methods:GetPoint() return unpack(self.point or {"CENTER",UIParent,"CENTER",0,0}) end
function methods:ClearAllPoints() guard(self,"ClearAllPoints");self.point=nil;self.points={} end
function methods:SetAllPoints(anchor) guard(self,"SetAllPoints");self.allPoints=anchor end
function methods:SetSize(w,h) guard(self,"SetSize");self.width,self.height=w,h end
function methods:SetWidth(w) guard(self,"SetWidth");self.width=w end
function methods:SetHeight(h) guard(self,"SetHeight");self.height=h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetScale(scale) guard(self,"SetScale");self.scale=scale end
function methods:GetScale() return self.scale end
function methods:GetEffectiveScale() return self.scale end
function methods:SetFrameLevel(level) guard(self,"SetFrameLevel");self.level=level end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameStrata(strata) guard(self,"SetFrameStrata");self.strata=strata end
function methods:EnableMouse(value) guard(self,"EnableMouse");self.mouse=value end
function methods:EnableMouseWheel(value) guard(self,"EnableMouseWheel");self.wheel=value end
function methods:SetMouseClickEnabled(value) guard(self,"SetMouseClickEnabled");self.mouse=value end
function methods:SetMovable(value) guard(self,"SetMovable");self.movable=value end
function methods:SetClampedToScreen(value) self.clamped=value end
function methods:RegisterForDrag(...) self.drag={...} end
function methods:StartMoving() guard(self,"StartMoving");self.moving=true end
function methods:StopMovingOrSizing() guard(self,"StopMovingOrSizing");self.moving=false end
function methods:Show()
    tooltipOperation(self,"Show")
    guard(self,"Show");local old=self.shown;self.shown=true
    if not old and self.scripts.OnShow then self.scripts.OnShow(self) end
    if not old and self.hooks.OnShow then self.hooks.OnShow(self) end
end
function methods:Hide()
    guard(self,"Hide");local old=self.shown;self.shown=false
    if old and self.scripts.OnHide then self.scripts.OnHide(self) end
    if old and self.hooks.OnHide then self.hooks.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetAlpha(value) self.alpha=value end
function methods:GetAlpha() return self.alpha end
function methods:SetText(text) tooltipOperation(self,"SetText");self.text=text end
function methods:GetText() return self.text end
function methods:SetTextColor(...) self.color={...} end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetTexture(texture) self.texture=texture end
function methods:SetTexCoord(...) self.texcoord={...} end
function methods:SetFont(...) self.font={...};return true end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF",12,"" end
function methods:SetRotation(value) self.rotation=value end
function methods:SetBackdrop(value) self.backdrop=value end
function methods:SetBackdropColor(...) self.backdropColor={...} end
function methods:SetBackdropBorderColor(...) self.borderColor={...} end
function methods:SetHighlightTexture(value) self.highlight=newFrame("Texture",nil,self);self.highlight.texture=value end
function methods:GetHighlightTexture() return self.highlight end
function methods:CreateTexture(name,layer,template,sublevel)
    local texture=newFrame("Texture",nil,self)
    texture.drawLayer,texture.sublevel=layer,sublevel
    return texture
end
function methods:CreateFontString() return newFrame("FontString",nil,self) end
function methods:SetMinMaxValues(low,high) self.minimum,self.maximum=low,high end
function methods:SetValue(value) self.value=value end
function methods:SetStatusBarTexture(texture) self.statusTexture=texture end
function methods:SetStatusBarColor(...) self.statusColor={...} end
function methods:SetOrientation(value) self.orientation=value end
function methods:CreateAnimationGroup() return newFrame("AnimationGroup",nil,self) end
function methods:CreateAnimation() return newFrame("Animation",nil,self) end
function methods:Play() self.playing=true end
function methods:Stop() self.playing=false end
function methods:IsPlaying() return self.playing or false end
function methods:SetOwner(owner) tooltipOperation(self,"SetOwner");self.owner=owner end
function methods:AddLine(...) tooltipOperation(self,"AddLine");self.lines=self.lines or {};self.lines[#self.lines+1]={...} end
function methods:ClearLines() tooltipOperation(self,"ClearLines");self.lines={} end
function methods:SetUnit(unit)
    tooltipOperation(self,"SetUnit")
    if unitTooltipThrows then error("native unit tooltip unavailable") end
    self.unit=unit
    return unitTooltipResult
end
function methods:SetEnabled(value) self.enabled=value end
function methods:IsEnabled() return self.enabled~=false end
for _,key in ipairs({"SetJustifyH","SetJustifyV","SetWordWrap","SetSpacing","SetShadowColor","SetShadowOffset",
    "SetBlendMode","SetDrawLayer","SetReverseFill","SetHitRectInsets","SetClipsChildren",
    "SetLooping","SetDuration","SetOrder","SetSmoothing","SetFromAlpha","SetToAlpha","SetDegrees",
    "SetOrigin","SetStartDelay","SetEndDelay","SetOffset","SetMotionScriptsWhileDisabled"}) do
    methods[key]=function() end
end
CreateFrame=newFrame
UIParent=newFrame("Frame","UIParent");UIParent:SetSize(1920,1080)
GameTooltip=newFrame("GameTooltip","GameTooltip")
SlashCmdList={}
InCombatLockdown=function() return combat end
issecretvalue=function() return false end
GetTime=function() return 20 end
UnitName=function() return "玩家" end
UnitExists=function() return false end
GetCursorPosition=function() return 500,500 end
local wrapped={}
SecureHandlerSetFrameRef=function(frame,key,reference)
    guard(frame,"SecureHandlerSetFrameRef")
    assert(type(key)=="string" and type(reference)=="table","secure frame reference needs a named frame")
    frame.refs[key]=reference
end
SecureHandlerWrapScript=function(button,script,owner,pre,post)
    wrapped[#wrapped+1]={button=button,script=script,owner=owner,pre=pre,post=post}
end
SecureHandlerUnwrapScript=function() end
RegisterUnitWatch=function(frame) frame.unitWatch=true end
UnregisterUnitWatch=function(frame) frame.unitWatch=false end
RegisterStateDriver=function(frame,key,value) frame.driver=frame.driver or {};frame.driver[key]=value end
UnregisterStateDriver=function(frame,key) if frame.driver then frame.driver[key]=nil end end
SetRaidTargetIconTexture=function(texture,index) texture.raidIcon=index end
SecureUnitButton_OnLoad=function(button,unit)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("*type1","target")
    button:SetAttribute("*type2","menu")
    button:SetAttribute("unit",unit)
end
DEFAULT_CHAT_FRAME={AddMessage=function() end}

local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
eq(NS.PreserveCastTarget,true,"production casting policy preserves the current target by default")
eq(NS.NativeMacroOnly,true,"production UI defaults to original native mouseover macros")
eq(NS.LegacyNameBridge,true,"production UI separately enables the authorized ordinary-spell bridge")
-- Earlier UI contracts below retain their historical presentation fixture;
-- the production policy and command entry are exercised explicitly at the end.
NS.PreserveCastTarget=false
NS.NativeMacroOnly=false
NS.LegacyNameBridge=false
assert(loadfile(root.."Distance.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Detection.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Quest.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
local live={}
UnitGUID=function(unit) return live[unit] and live[unit].guid end
NS.ReadUnit=function(unit,side)
    local value=live[unit]
    if value and value.side==side and (side~="friendly" or value.player) then return value end
end
NS.ApplySetting=function(key,value) if not combat then NS.DB[key]=value end end
NS.RequestRefresh=function() end
NS.SetShown=function(value)
    if not combat then NS.DB.shown=value;NS.DB.friendlyShown=value;NS.DB.enemyShown=value end
end
NS.SetPanelShown=function(side,value)
    if not combat then
        NS.DB[side.."Shown"]=value
        NS.DB.shown=NS.DB.friendlyShown or NS.DB.enemyShown
        if NS.RefreshControls then NS.RefreshControls() end
    end
end
NS.SetLocked=function(value) if not combat then NS.DB.locked=value end end
NS.SetScale=function(value) if not combat then NS.DB.scale=value end end
assert(loadfile(root.."Hover.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."EnemyTargetHover.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."UI.lua"))("MyForeverTargets",NS)
local ordinary=newFrame("Frame",nil,UIParent,"SecureHandlerBaseTemplate")
eq(ordinary.SetFrameRef,nil,"secure-handler template does not invent an insecure SetFrameRef method")
eq(ordinary.GetFrameRef,nil,"GetFrameRef belongs to restricted snippets, not an ordinary frame method")
eq(pcall(function() ordinary:SetFrameRef("regression",ordinary) end),false,"former live crash reproduced by the mock")
NS.CreateUI()
eq(NS.MarkerMenu.refs.markMenu,NS.MarkerMenu,"mark-menu reference installed through global secure handler API")
for i=0,8 do
    eq(NS.MarkerMenu.refs["mark"..i],NS.MarkerMenu.markers[i],"marker reference installed through global secure handler API")
end
yes(NS.UI and NS.UI.friendly and NS.UI.enemy,"both target panels exist")
eq(#NS.UI.friendly.tiles,20,"friendly pool has twenty tiles")
eq(#NS.UI.enemy.tiles,20,"enemy pool has twenty tiles")
eq(NS.UI.friendly.tiles[1].nativeHandlerWasPresent,true,"action-only template installs native handler")
eq(NS.UI.friendly.tiles[1]:GetScript("OnClick"),SecureActionButton_OnClick,"XML-installed native target handler remains untouched")
eq(NS.UI.friendly.tiles[2].nativeHandlerWasPresent,true,"already present native handler path also exercised")
eq(NS.UI.friendly.tiles[1].nativeClick,SecureActionButton_OnClick,"diagnostic captures untouched native function")
eq(pcall(function() NS.UI.friendly.tiles[1]:SetScript("OnClick",function() end) end),false,
    "mock still rejects addon closures replacing secure native handler")
for _,side in ipairs({"friendly","enemy"}) do
    local section=NS.UI[side]
    eq(section.tiles[1]:GetWidth(),76,"permanent aura card width")
    eq(section.tiles[1]:GetHeight(),58,"permanent aura card height")
    local bounds,valid={},true
    for _,tile in ipairs(section.tiles) do
        local anchor=tile.point
        local x,y=anchor[2],anchor[3]
        if type(x)~="number" then x,y=anchor[4],anchor[5] end
        local b={x=x,y=y,w=tile:GetWidth(),h=tile:GetHeight()}
        if x<0 or x+b.w>section.frame:GetWidth() or y>0 then valid=false end
        for _,other in ipairs(bounds) do
            if x<other.x+other.w and x+b.w>other.x and y>other.y-other.h and y-b.h<other.y then valid=false end
        end
        bounds[#bounds+1]=b
    end
    yes(valid,"compact grid has no overlapping tiles and fits panel width")
end
-- Solve the simple point anchors used by the header, including buttons anchored
-- to a sibling; raw point y=0 alone does not mean two buttons share a row.
local anchorFraction={TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1},LEFT={0,.5},CENTER={.5,.5},
    RIGHT={1,.5},BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0}}
local function localBounds(widget,panel)
    if widget==panel then return {x=0,y=0,w=panel:GetWidth(),h=panel:GetHeight()} end
    local p=widget.point
    assert(p,"layout widget has no point")
    local relative,relativePoint,x,y
    if type(p[2])=="number" then relative,relativePoint,x,y=widget.parent,p[1],p[2],p[3]
    else relative,relativePoint,x,y=p[2] or widget.parent,p[3] or p[1],p[4] or 0,p[5] or 0 end
    local reference=localBounds(relative,panel)
    local selfAnchor,otherAnchor=anchorFraction[p[1]],anchorFraction[relativePoint]
    return {x=reference.x+reference.w*otherAnchor[1]+x-widget:GetWidth()*selfAnchor[1],
        y=reference.y+reference.h*otherAnchor[2]+y-widget:GetHeight()*selfAnchor[2],
        w=widget:GetWidth(),h=widget:GetHeight()}
end
local function rootViewportBounds(widget)
    local p=widget.point
    if widget.parent~=UIParent or not p or type(p[2])~="table" or p[2]~=UIParent then return nil end
    local own,relative=anchorFraction[p[1]],anchorFraction[p[3]]
    local scale=widget:GetScale()
    local width,height=widget:GetWidth()*scale,widget:GetHeight()*scale
    local left=UIParent:GetWidth()*relative[1]+p[4]*scale-width*own[1]
    local bottom=UIParent:GetHeight()*relative[2]+p[5]*scale-height*own[2]
    return {left=left,bottom=bottom,right=left+width,top=bottom+height}
end
function methods:GetLeft() local b=rootViewportBounds(self);return b and b.left/self:GetScale() or localBounds(self,UIParent).x end
function methods:GetBottom() local b=rootViewportBounds(self);return b and b.bottom/self:GetScale() or localBounds(self,UIParent).y end
function methods:GetRight() local b=rootViewportBounds(self);if b then return b.right/self:GetScale() end;local r=localBounds(self,UIParent);return r.x+r.w end
function methods:GetTop() local b=rootViewportBounds(self);if b then return b.top/self:GetScale() end;local r=localBounds(self,UIParent);return r.y+r.h end
local initialSavedY,initialAnchorY=NS.DB.friendlyPosition.y,NS.UI.friendly.frame.point[5]
NS.BindTiles("friendly",{},20)
eq(NS.DB.friendlyPosition.y,initialSavedY,"first bind never rewrites saved position")
eq(NS.UI.friendly.frame.point[5],initialAnchorY,"first bind retains saved anchor even when initial height changes")
NS.BindTiles("enemy",{},20)
for _,side in ipairs({"friendly","enemy"}) do
    local section=NS.UI[side]
    yes(section.frame:GetWidth()*section.frame:GetScale()<=UIParent:GetWidth(),"panel fits the public viewport width")
    local controls={section.lock,section.close}
    if section.mouseover then controls[#controls+1]=section.mouseover end
    for _,widget in pairs(section.tabs) do controls[#controls+1]=widget end
    for _,widget in pairs(section.limits) do controls[#controls+1]=widget end
    local bounds,valid,center={},true,nil
    local aboveDrag,aboveGrid=true,true
    local firstTile=localBounds(section.tiles[1],section.frame)
    for _,widget in ipairs(controls) do
        local b=localBounds(widget,section.frame)
        if widget:GetFrameLevel()<=section.drag:GetFrameLevel() then aboveDrag=false end
        if b.y<firstTile.y+firstTile.h then aboveGrid=false end
        center=center or b.y+b.h/2
        if b.x<0 or b.x+b.w>section.frame:GetWidth() or math.abs(b.y+b.h/2-center)>1 then valid=false end
        for _,other in ipairs(bounds) do
            if b.x<other.x+other.w and b.x+b.w>other.x and b.y<other.y+other.h and b.y+b.h>other.y then valid=false end
        end
        bounds[#bounds+1]=b
    end
    yes(valid,"all header buttons fit one row without overlap")
    yes(aboveDrag,"header controls receive clicks above the overlapping drag surface")
    yes(aboveGrid,"header controls end above the first target row")
    local function noResidentCopy(label)
        return not label or not label:IsShown() or label:GetText()==""
    end
    yes(noResidentCopy(section.hint) and noResidentCopy(section.footer),"sorting and operation instructions leave resident panel")
    for _,limit in ipairs({5,10,20}) do
        NS.BindTiles(side,{},limit)
        local first=localBounds(section.tiles[1],section.frame)
        local lastTile=section.tiles[limit]
        local last=localBounds(side=="enemy" and lastTile.enemyTargetDisplay or lastTile,section.frame)
        yes(first.y+first.h<=section.frame:GetHeight() and last.y>=0 and last.y<=8,
            "panel height tightly contains "..limit.." complete "..side.." cells")
        local expectedHeight=side=="enemy" and ({[5]=117,[10]=203,[20]=375})[limit]
            or ({[5]=90,[10]=149,[20]=267})[limit]
        eq(section.frame:GetHeight(),expectedHeight,side.." capacity includes its full cell height")
    end
end
do
    local friend,enemy=NS.UI.friendly,NS.UI.enemy
    friend.close:GetScript("OnClick")()
    eq(friend.frame:IsShown(),false,"friendly close hides only its own panel")
    eq(enemy.frame:IsShown(),true,"friendly close preserves the enemy panel")
    NS.RefreshControls()
    eq(friend.frame:IsShown(),false,"routine controls refresh does not reopen the closed friendly panel")
    NS.SetPanelShown("friendly",true)
    enemy.close:GetScript("OnClick")()
    eq(friend.frame:IsShown(),true,"enemy close preserves the friendly panel")
    eq(enemy.frame:IsShown(),false,"enemy close hides only its own panel")
    NS.SetPanelShown("enemy",true)
    friend.frame.dragging=true;friend.frame.dragProxy:Show();friend.frame.dragProxy:StartMoving()
    friend.close:GetScript("OnClick")()
    eq(friend.frame.dragging,false,"closing a panel cancels its drag gesture")
    eq(friend.frame.dragProxy:IsShown(),false,"closing a panel hides its detached drag outline")
    eq(friend.frame.dragProxy.moving,false,"closing a panel stops only the unprotected outline")
    NS.SetPanelShown("friendly",true)
end
-- A target card belongs below its enemy, rather than overlapping its owner or
-- the next grid row. Inspect the complete geometry, including empty slots.
do
local enemySection=NS.UI.enemy
local completeBounds={}
for i,tile in ipairs(enemySection.tiles) do
    local card=tile.enemyTargetDisplay
    yes(card~=nil,"every enemy slot owns a separate target display")
    eq(card:GetWidth(),76,"target card matches the unchanged enemy width")
    eq(card:GetHeight(),26,"target card has room for name class and health")
    eq(card.mouse,false,"target display does not intercept the native unit button")
    local enemyBounds=localBounds(tile,enemySection.frame)
    local cardBounds=localBounds(card,enemySection.frame)
    eq(cardBounds.x,enemyBounds.x,"target card aligns with its enemy left edge")
    eq(cardBounds.y+cardBounds.h,enemyBounds.y-1,"target card is separated from its enemy by one pixel")
    yes(cardBounds.y>=0 and cardBounds.x+cardBounds.w<=enemySection.frame:GetWidth(),
        "complete enemy cell fits the panel")
    local combined={x=enemyBounds.x,y=cardBounds.y,w=enemyBounds.w,h=85}
    eq(enemyBounds.y+enemyBounds.h-cardBounds.y,combined.h,"enemy and target footprint remains 85 pixels")
    for _,other in ipairs(completeBounds) do
        yes(not (combined.x<other.x+other.w and combined.x+combined.w>other.x
            and combined.y<other.y+other.h and combined.y+combined.h>other.y),
            "independent target card never overlaps another enemy cell")
    end
    completeBounds[#completeBounds+1]=combined
    if i>enemySection.columns then
        local above=localBounds(enemySection.tiles[i-enemySection.columns],enemySection.frame)
        eq(above.y-enemyBounds.y,86,"enemy grid reserves a full target card in each row")
    end
end
end
-- Enlarged full-aura cards must fit as a pair, including old saved positions
-- that were safe for 56px tiles. Runtime fitting never overwrites preferences.
do
    local originalFriendlyPosition,originalEnemyPosition=NS.DB.friendlyPosition,NS.DB.enemyPosition
    local originalScale=NS.DB.scale
    local function pairFits(label)
        local a,b=rootViewportBounds(NS.UI.friendly.frame),rootViewportBounds(NS.UI.enemy.frame)
        for _,bounds in ipairs({a,b}) do
            yes(bounds.left>=-.001 and bounds.bottom>=math.min(160,UIParent:GetHeight()*.14)-.001
                and bounds.right<=UIParent:GetWidth()+.001 and bounds.top<=UIParent:GetHeight()+.001,
                label.." keeps both panels above the bottom action-bar safe area")
        end
        yes(not (a.left<b.right and a.right>b.left and a.bottom<b.top and a.top>b.bottom),label.." keeps both panels disjoint")
        eq(NS.UI.friendly.frame:GetScale(),NS.UI.enemy.frame:GetScale(),label.." uses one runtime scale")
    end
    for _,viewport in ipairs({{1920,1080,1},{1280,720,1},{2560,1440,1.4},{2560,1440,1.2},{1024,768,1.4}}) do
        UIParent:SetSize(viewport[1],viewport[2]);NS.DB.scale=viewport[3]
        NS.DB.friendlyPosition={point="CENTER",relativePoint="CENTER",x=-180,y=-350}
        NS.DB.enemyPosition={point="CENTER",relativePoint="CENTER",x=180,y=-350}
        NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
        NS.BindTiles("friendly",{},20);NS.BindTiles("enemy",{},20);NS.RefreshControls()
        pairFits(viewport[1].."x"..viewport[2].." twenty-card pair")
        if viewport[1]==2560 and viewport[3]==1.2 then
            eq(NS.UI.enemy.columns,5,"compact twenty-enemy panel keeps five columns above the action-bar reserve")
        end
        eq(NS.DB.scale,viewport[3],"auto-fit keeps requested scale intact")
        eq(NS.DB.friendlyPosition.x,-180,"auto-fit preserves saved friendly x")
        eq(NS.DB.friendlyPosition.y,-350,"auto-fit preserves saved friendly y")
        eq(NS.DB.enemyPosition.x,180,"auto-fit preserves saved enemy x")
        eq(NS.DB.enemyPosition.y,-350,"auto-fit preserves saved enemy y")
        local left,top=NS.UI.enemy.frame:GetLeft(),NS.UI.enemy.frame:GetTop()
        NS.RefreshControls()
        eq(NS.UI.enemy.frame:GetLeft(),left,"repeated public refresh does not drift the fitted panel")
        eq(NS.UI.enemy.frame:GetTop(),top,"repeated public refresh retains the fitted top")
        for _,limit in ipairs({5,10,20}) do
            NS.BindTiles("friendly",{},limit);NS.BindTiles("enemy",{},limit);NS.RefreshControls()
            pairFits("capacity "..limit.." on "..viewport[1])
        end
    end
    local priorWidth,priorScale=NS.UI.enemy.frame:GetWidth(),NS.UI.enemy.frame:GetScale()
    combat=true;UIParent:SetSize(800,600);NS.RefreshControls()
    eq(NS.UI.enemy.frame:GetWidth(),priorWidth,"screen resize during combat never reanchors protected cards")
    eq(NS.UI.enemy.frame:GetScale(),priorScale,"screen resize during combat keeps protected scale")
    combat=false;NS.RefreshControls();pairFits("deferred viewport adaptation")
    UIParent:SetSize(1920,1080);NS.DB.scale=originalScale
    NS.DB.friendlyPosition,NS.DB.enemyPosition=originalFriendlyPosition,originalEnemyPosition
    NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
end
-- The revised friendly default must also work beside an enemy panel whose
-- manual placement disables automatic pair fitting. Keep the unchanged tiles
-- above the existing bottom reserve across short and wide viewports.
do
    local savedDB=NS.DB
    local savedWidth,savedHeight=UIParent:GetWidth(),UIParent:GetHeight()
    for _,viewport in ipairs({{1280,720},{1920,1080},{2560,1080},{1024,768}}) do
        UIParent:SetSize(viewport[1],viewport[2])
        for _,limit in ipairs({5,10,20}) do
            for _,scale in ipairs({.7,1,1.4}) do
                NS.DB=NS.NormalizeDB({friendlyTab="nearby",nearbyLimit=limit,enemyLimit=5,scale=scale,
                    enemyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=1092,y=-844,manual=true}})
                NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
                NS.BindTiles("friendly",{},limit);NS.BindTiles("enemy",{},5);NS.RefreshControls()
                local bounds=rootViewportBounds(NS.UI.friendly.frame)
                yes(bounds.left>=0 and bounds.right<=viewport[1] and bounds.top<=viewport[2],
                    "friendly default stays fully on screen for capacity "..limit.." at "..viewport[1])
                yes(bounds.bottom>=math.min(160,viewport[2]*.14),
                    "friendly default clears the bottom reserve beside a manually placed enemy panel")
                -- Current launcher is independently scaled: LEFT x26.17, 42px
                -- wide. Reserve its right edge even at the minimum panel scale.
                yes(bounds.left>=26.1667+42+8,"friendly default leaves the existing launcher accessible")
                eq(NS.DB.enemyPosition.x,1092,"new friendly default leaves enemy saved position intact")
            end
        end
    end
    UIParent:SetSize(savedWidth,savedHeight);NS.DB=savedDB
    NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
end
-- Explicit drags outrank automatic pair fitting. Overlap and the bottom
-- action-bar region are valid user choices; only actual screen edges clamp.
do
    local originalDB=NS.DB
    NS.DB=NS.NormalizeDB(NS.DB)
    NS.DB.scale=1;NS.DB.locked=false;NS.DB.friendlyTab="nearby";NS.DB.nearbyLimit=5;NS.DB.enemyLimit=5
    NS.DB.friendlyPosition={point="CENTER",relativePoint="CENTER",x=-50,y=-400,manual=false}
    NS.DB.enemyPosition={point="CENTER",relativePoint="CENTER",x=50,y=-400,manual=false}
    NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    local function drop(side,point,x,y)
        local section=NS.UI[side]
        section.drag:GetScript("OnDragStart")(section.drag)
        local proxy=section.frame.dragProxy
        proxy:ClearAllPoints();proxy:SetPoint(point,UIParent,point,x,y)
        section.drag:GetScript("OnDragStop")(section.drag)
    end
    local function stable(side,label)
        local frame=NS.UI[side].frame
        local before=rootViewportBounds(frame)
        for _=1,4 do NS.RefreshControls();NS.BindTiles(side,{},5);NS.RefreshControls() end
        local after=rootViewportBounds(frame)
        eq(after.left,before.left,label.." keeps the dropped horizontal position")
        eq(after.top,before.top,label.." keeps the dropped vertical position")
    end
    local otherBefore=rootViewportBounds(NS.UI.enemy.frame)
    drop("friendly","TOPLEFT",otherBefore.left+12,-(UIParent:GetHeight()-otherBefore.top+12))
    eq(NS.DB.friendlyPosition.manual,true,"successful drag records explicit placement ownership")
    eq(NS.DB.enemyPosition.point,"TOPLEFT","first explicit drop snapshots the other panel's runtime anchor")
    eq(NS.DB.enemyPosition.manual,false,"snapshot does not claim the other panel was manually dragged")
    eq(NS.DB.enemyPosition.x,otherBefore.left,"other-panel snapshot uses its actual position after pair fitting")
    stable("friendly","overlapping drag after repeated roster refresh")
    local overlap=rootViewportBounds(NS.UI.friendly.frame)
    yes(overlap.left<otherBefore.right and overlap.right>otherBefore.left and overlap.bottom<otherBefore.top
        and overlap.top>otherBefore.bottom,"explicitly overlapping panels remain overlapped")
    local otherAfter=rootViewportBounds(NS.UI.enemy.frame)
    eq(otherAfter.left,otherBefore.left,"dragging one panel does not move the other panel horizontally")
    eq(otherAfter.top,otherBefore.top,"dragging one panel does not move the other panel vertically")
    drop("friendly","TOPLEFT",400,-300)
    NS.BindTiles("friendly",{},20);NS.BindTiles("enemy",{},20);NS.RefreshControls()
    eq(rootViewportBounds(NS.UI.friendly.frame).left,400,"capacity growth keeps a manual header's horizontal position")
    eq(rootViewportBounds(NS.UI.friendly.frame).top,UIParent:GetHeight()-300,
        "capacity growth keeps a manual header instead of forcing pair arrangement")
    eq(NS.DB.friendlyPosition.x,400,"capacity growth retains the saved manual x")
    eq(NS.DB.friendlyPosition.y,-300,"capacity growth retains the saved manual y")
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    drop("friendly","BOTTOMLEFT",100,10)
    stable("friendly","drag into the bottom action-bar area")
    eq(rootViewportBounds(NS.UI.friendly.frame).bottom,10,"user may deliberately use the action-bar safe area")
    local otherBeforeReload=rootViewportBounds(NS.UI.enemy.frame)
    local saved=NS.DB
    NS.Initialize(saved);NS.UI=nil;NS.CreateUI()
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    eq(NS.DB.friendlyPosition.manual,true,"manual placement survives saved-variable normalization")
    eq(rootViewportBounds(NS.UI.friendly.frame).left,100,"reload restores the manually chosen horizontal position")
    eq(rootViewportBounds(NS.UI.friendly.frame).bottom,10,"reload preserves the chosen bottom region")
    eq(rootViewportBounds(NS.UI.enemy.frame).left,otherBeforeReload.left,"reload retains the undragged panel's fitted horizontal position")
    eq(rootViewportBounds(NS.UI.enemy.frame).top,otherBeforeReload.top,"reload retains the undragged panel's fitted vertical position")
    stable("friendly","reloaded manual placement")
    for _,anchor in ipairs({{"BOTTOMLEFT",100,400},{"CENTER",-250,100}}) do
        NS.DB.nearbyLimit=5;NS.BindTiles("friendly",{},5);NS.RefreshControls()
        drop("friendly",anchor[1],anchor[2],anchor[3])
        local expected=rootViewportBounds(NS.UI.friendly.frame)
        eq(NS.DB.friendlyPosition.point,"TOPLEFT",anchor[1].." native drag is normalized to top-left")
        eq(NS.DB.friendlyPosition.relativePoint,"TOPLEFT",anchor[1].." native drag uses an absolute screen anchor")
        NS.DB.nearbyLimit=20;NS.BindTiles("friendly",{},20);NS.RefreshControls()
        eq(rootViewportBounds(NS.UI.friendly.frame).left,expected.left,anchor[1].." capacity change retains header x")
        eq(rootViewportBounds(NS.UI.friendly.frame).top,expected.top,anchor[1].." capacity change retains header top")
        NS.Initialize(NS.DB);NS.UI=nil;NS.CreateUI()
        NS.BindTiles("friendly",{},20);NS.BindTiles("enemy",{},5);NS.RefreshControls()
        eq(rootViewportBounds(NS.UI.friendly.frame).left,expected.left,anchor[1].." reload after capacity change retains header x")
        eq(rootViewportBounds(NS.UI.friendly.frame).top,expected.top,anchor[1].." reload after capacity change retains header top")
        NS.DB.nearbyLimit=5;NS.BindTiles("friendly",{},5);NS.RefreshControls()
        eq(rootViewportBounds(NS.UI.friendly.frame).top,expected.top,anchor[1].." return to five cells retains the same header")
    end
    drop("friendly","TOPLEFT",-100,100);NS.RefreshControls()
    local clamped=rootViewportBounds(NS.UI.friendly.frame)
    yes(clamped.left>=0 and clamped.top<=UIParent:GetHeight(),"explicit placement still clamps actual screen edges")
    eq(NS.DB.friendlyPosition.x,-100,"runtime screen clamping does not overwrite the saved preference")
    drop("friendly","BOTTOMLEFT",100,10)
    local frame,drag=NS.UI.friendly.frame,NS.UI.friendly.drag
    local beforeUnavailable=NS.DB.friendlyPosition
    drag:GetScript("OnDragStart")(drag)
    frame.dragProxy.GetLeft=function() error("unavailable public geometry") end
    drag:GetScript("OnDragStop")(drag)
    eq(NS.DB.friendlyPosition,beforeUnavailable,"unavailable drag geometry cannot overwrite saved placement")
    frame.dragProxy.GetLeft=nil
    local beforeCombat=rootViewportBounds(frame)
    local savedBeforeCombat=NS.DB.friendlyPosition
    drag:GetScript("OnDragStart")(drag)
    frame.dragProxy:ClearAllPoints();frame.dragProxy:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",450,250)
    combat=true;NS.StopDragging();drag:GetScript("OnDragStop")(drag);NS.RefreshControls()
    eq(frame.dragProxy:IsShown(),false,"combat entry hides the unprotected drag preview")
    eq(frame.dragging,false,"combat entry cancels the unfinished drag")
    eq(NS.DB.friendlyPosition,savedBeforeCombat,"combat-interrupted drag never persists the preview position")
    eq(rootViewportBounds(frame).left,beforeCombat.left,"combat-interrupted drag does not move the protected panel")
    eq(rootViewportBounds(frame).bottom,beforeCombat.bottom,"combat-interrupted drag retains its original height")
    combat=false;NS.RefreshControls();stable("friendly","placement after interrupted drag")
    local legacySave=NS.NormalizeDB(NS.DB)
    legacySave.friendlyTab,legacySave.nearbyLimit,legacySave.enemyLimit="nearby",5,5
    legacySave.friendlyPosition={point="BOTTOM",relativePoint="BOTTOM",x=-300,y=250,manual=true}
    legacySave.enemyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=1100,y=-100,manual=false}
    NS.Initialize(legacySave)
    local untouchedOther=NS.DB.enemyPosition
    NS.UI=nil;NS.CreateUI();NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    local legacyFrame=NS.UI.friendly.frame
    local legacyCorner=rootViewportBounds(legacyFrame)
    eq(legacyCorner.left,UIParent:GetWidth()/2-300-legacyFrame:GetWidth()/2,
        "legacy BOTTOM save keeps the initially visible horizontal corner")
    eq(legacyCorner.top,250+legacyFrame:GetHeight(),"legacy BOTTOM save keeps the initial five-cell header")
    eq(NS.DB.friendlyPosition.point,"BOTTOM","legacy manual BOTTOM save is not converted using startup geometry")
    eq(NS.DB.friendlyPosition.relativePoint,"BOTTOM","legacy manual save retains its relative viewport anchor")
    eq(legacyFrame.point[1],"BOTTOM","legacy manual runtime anchor follows the viewport")
    eq(NS.DB.enemyPosition,untouchedOther,"legacy initialization does not rewrite a nonmanual saved position")
    local legacyPosition=NS.DB.friendlyPosition
    NS.RefreshControls();NS.RefreshControls()
    eq(NS.DB.friendlyPosition,legacyPosition,"legacy manual save is not replaced on routine refresh")
    eq(NS.DB.friendlyPosition.y,250,"routine refresh does not rewrite the legacy offset")
    NS.DB.nearbyLimit=20;NS.BindTiles("friendly",{},20);NS.RefreshControls()
    eq(rootViewportBounds(legacyFrame).top,legacyCorner.top,"legacy manual save preserves its header when capacity grows")
    eq(NS.DB.friendlyPosition.y,250-(267-90),"legacy capacity growth saves only the panel-height delta")
    NS.Initialize(NS.DB);NS.UI=nil;NS.CreateUI()
    NS.BindTiles("friendly",{},20);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    eq(rootViewportBounds(NS.UI.friendly.frame).left,legacyCorner.left,"legacy manual save survives reload horizontally")
    eq(rootViewportBounds(NS.UI.friendly.frame).top,legacyCorner.top,"legacy BOTTOM five-to-twenty capacity change does not jump on reload")
    -- The real client's UIParent grows after ADDON_LOADED as the UI scale is
    -- applied. Do not freeze those early 1365x768 coordinates into the save.
    local liveLegacy=NS.NormalizeDB(NS.DB)
    liveLegacy.nearbyLimit,liveLegacy.enemyLimit=5,5
    liveLegacy.friendlyPosition={point="BOTTOM",relativePoint="BOTTOM",x=-240.6667175292969,y=142.8335571289063,manual=true}
    liveLegacy.enemyPosition={point="BOTTOM",relativePoint="BOTTOM",x=165.8332061767578,y=121.8331832885742,manual=true}
    UIParent:SetSize(1365.3334960938,768)
    NS.Initialize(liveLegacy);NS.UI=nil;NS.CreateUI()
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    local earlyLeft=rootViewportBounds(NS.UI.friendly.frame).left
    UIParent:SetSize(2133.3334960938,1200);NS.RefreshControls()
    for _,side in ipairs({"friendly","enemy"}) do
        local panel,position=NS.UI[side].frame,liveLegacy[side.."Position"]
        local bounds=rootViewportBounds(panel)
        eq(bounds.left,UIParent:GetWidth()/2+position.x-panel:GetWidth()/2,
            side.." legacy anchor follows the final viewport width instead of the startup width")
        eq(bounds.top,position.y+panel:GetHeight(),side.." legacy anchor keeps its original bottom offset after UI scale settles")
        eq(NS.DB[side.."Position"].point,"BOTTOM",side.." startup viewport resize never rewrites the legacy anchor")
        eq(NS.DB[side.."Position"].x,position.x,side.." startup viewport resize does not persist early geometry")
    end
    eq(rootViewportBounds(NS.UI.friendly.frame).left-earlyLeft,384,"real startup resize applies the missing horizontal half-width offset")
    -- A newer TOPLEFT save can be below the temporary startup viewport. Its
    -- early edge clamp must be undone when the real viewport becomes available.
    local topSave=NS.NormalizeDB(NS.DB)
    topSave.friendlyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=630,y=-967,manual=true}
    topSave.enemyPosition={point="TOPLEFT",relativePoint="TOPLEFT",x=1036,y=-961,manual=false}
    UIParent:SetSize(1365.3334960938,768)
    NS.Initialize(topSave);NS.UI=nil;NS.CreateUI()
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
    yes(rootViewportBounds(NS.UI.friendly.frame).bottom>=0,"manual TOPLEFT save is temporarily clamped into the startup viewport")
    eq(NS.DB.friendlyPosition.y,-967,"startup clamp does not modify the manual TOPLEFT save")
    UIParent:SetSize(2133.3334960938,1200);NS.RefreshControls()
    for _,side in ipairs({"friendly","enemy"}) do
        local bounds=rootViewportBounds(NS.UI[side].frame)
        eq(bounds.left,topSave[side.."Position"].x,side.." final viewport restores saved horizontal position after the early clamp")
        eq(bounds.top,1200+topSave[side.."Position"].y,side.." final viewport restores saved vertical position after the early clamp")
    end
    NS.RefreshControls();NS.RefreshControls()
    eq(rootViewportBounds(NS.UI.friendly.frame).top,233,"routine refresh after the viewport settles does not repeat the temporary clamp")
    UIParent:SetSize(1920,1080)
    NS.DB=originalDB
    NS.UI.friendly.frame.positionKey=nil;NS.UI.enemy.frame.positionKey=nil
    NS.BindTiles("friendly",{},5);NS.BindTiles("enemy",{},5);NS.RefreshControls()
end
for _,side in ipairs({"friendly","enemy"}) do
    local section=NS.UI[side]
    local enter=section.drag:GetScript("OnEnter")
    eq(type(enter),"function","compact header retains a hover-help entry point")
    GameTooltip.lines={}
    if enter then enter(section.drag) end
    local lines={}
    for _,line in ipairs(GameTooltip.lines) do if type(line[1])=="string" then lines[#lines+1]=line[1] end end
    local help=table.concat(lines,"\n")
    yes(help:find("左键",1,true) and help:find("右键",1,true) and help:find("悬停",1,true),
        "removed resident mouse instructions remain reachable in header tooltip")
    GameTooltip:Hide()
end
for _,side in ipairs({"friendly","enemy"}) do
    for _,tile in ipairs(NS.UI[side].tiles) do
        yes(tile.template:find("SecureActionButtonTemplate",1,true) and not tile.template:find("SecureUnitButtonTemplate",1,true),
            "tile uses action-only native click template")
        eq(tile:GetScript("OnClick"),builtinActionClick,"native action OnClick wins over global click binding override")
        eq(tile:GetAttribute("useOnKeyDown"),false,"tile up-click independent of action-button key-down CVar")
        eq(tile:GetAttribute("*type1"),"target","left click uses native target action")
        yes(tile.shield and not tile.shield:IsProtected(),"invalid unit shield is unprotected")
    end
end
local function data(unit,guid,name,side,player)
    return {unit=unit,guid=guid,name=name,targetName=name,side=side,player=player,className=player and "法师" or "野兽",
        classToken=player and "MAGE" or nil,color={r=.25,g=.78,b=.92},health=.5,
        healthCurrent=50,healthMax=100,healthAvailable=true,dead=false,offline=false,target=false}
end
live.party1=data("party1","Player-1","同伴","friendly",true)
live.nameplate1=data("nameplate1","Creature-1","野狼","enemy",false)
NS.UI.enemy.tiles[1]:SetAttribute("*unit1","") -- stale override from an older candidate
NS.BindTiles("friendly",{"party1"},5)
NS.BindTiles("enemy",{"nameplate1"},5)
NS.RefreshTiles()
local friend,enemy=NS.UI.friendly.tiles[1],NS.UI.enemy.tiles[1]
eq(friend.health.orientation,"HORIZONTAL","whole-square health empties left to right")
local healthStart,healthEnd=friend.health.points[1],friend.health.points[2]
yes(healthStart and healthEnd and healthStart[1]=="TOPLEFT" and healthEnd[1]=="BOTTOMRIGHT"
    and friend:GetWidth()+healthEnd[2]-healthStart[2]>=44
    and friend:GetHeight()+healthStart[3]-healthEnd[3]>=44,
    "health fill spans the square instead of becoming another narrow bar")
eq(friend.health.value,50,"whole-square fill receives live health current")
eq(friend.health.maximum,100,"whole-square fill receives live health maximum")
eq(friend.power:IsShown(),false,"unknown resource has no fabricated mana bar")
eq(friend.powerTrack:IsShown(),false,"unknown resource does not show an empty-looking valid resource slot")
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=.4,"MANA",{r=0,g=.3,b=1}
live.party1.powerCurrent,live.party1.powerMax,live.party1.powerAvailable=40,100,true
NS.RefreshTiles()
eq(friend.power.value,40,"bottom strip receives live resource current")
eq(friend.power.maximum,100,"bottom strip receives live resource maximum")
eq(friend.power:IsShown(),true,"valid resource strip is visible")
eq(friend.powerTrack:IsShown(),true,"valid resource has a dark empty remainder")
eq(friend.power.statusColor[3],1,"mana strip uses resource color independently of class color")
yes(friend.power:GetHeight()>0 and friend.power:GetHeight()<=6,"resource stays a thin strip inside compact square")
eq(friend.power.allPoints,friend.powerTrack,"resource fill stays inside its bottom track")
local powerTop=friend.powerTrack.point[3]+friend.powerTrack:GetHeight()
yes(friend.powerTrack.point[1]:find("BOTTOM",1,true) and powerTop<=friend:GetHeight()+friend.statusText.point[3]-friend.statusText:GetHeight(),
    "bottom resource strip ends below status text")
yes(powerTop<=friend:GetHeight()+friend.nameText.point[3]-friend.nameText:GetHeight()
    and powerTop<=friend:GetHeight()+friend.classText.point[3]-friend.classText:GetHeight(),
    "resource strip does not cover name or class")
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=0,"ENERGY",{r=1,g=1,b=0}
live.party1.powerCurrent=0
NS.RefreshTiles()
eq(friend.power.value,0,"known zero resource stays zero")
eq(friend.powerTrack:IsShown(),true,"known empty resource retains its visible slot")
eq(friend.power.statusColor[1],1,"resource switch repaints former mana strip")
live.party1.dead=true;live.party1.health=.8
NS.RefreshTiles()
eq(friend.health.value,0,"dead unit does not retain stale full-square health")
eq(friend.power:IsShown(),false,"dead unit resource strip hides")
live.party1.dead=false;live.party1.offline=true
NS.RefreshTiles()
eq(friend.powerTrack:IsShown(),false,"offline resource is not presented as live")
live.party1.offline=false;live.party1.health=.5
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=nil,nil,nil
live.party1.powerCurrent,live.party1.powerMax,live.party1.powerAvailable=nil,nil,false
NS.RefreshTiles()
eq(friend.power:IsShown(),false,"losing resource data clears an earlier visible bar")
-- Model a secret number's type and prohibited Lua operations, but allow the
-- native status-bar sink to receive it untouched. No C++ normalization is run.
local function secretArithmetic() error("raw secret resource used in Lua") end
local uiResourceSecret=setmetatable({}, {__div=secretArithmetic,__mul=secretArithmetic,
    __add=secretArithmetic,__sub=secretArithmetic,__lt=secretArithmetic,__le=secretArithmetic,
    __tostring=secretArithmetic})
local priorType,priorSecret=type,issecretvalue
type=function(value) if value==uiResourceSecret then return "number" end;return priorType(value) end
issecretvalue=function(value) return value==uiResourceSecret or priorSecret(value) end
live.party1.health,live.party1.healthCurrent,live.party1.healthMax,live.party1.healthAvailable=nil,uiResourceSecret,100,true
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=nil,"MANA",{r=0,g=.3,b=1}
live.party1.powerCurrent,live.party1.powerMax,live.party1.powerAvailable=uiResourceSecret,100,true
NS.RefreshTiles()
yes(friend.health.value==uiResourceSecret,"secret health goes unchanged into native SetValue")
yes(friend.power.value==uiResourceSecret,"secret resource goes unchanged into native SetValue")
eq(friend.powerTrack:IsShown(),true,"secret resource is displayed rather than mistaken for missing data")
eq(friend.statusText:GetText(),"","secret health does not add a fabricated percentage or resident placeholder")
live.party1.healthCurrent,live.party1.healthMax=25,uiResourceSecret
live.party1.powerCurrent,live.party1.powerMax=40,uiResourceSecret
NS.RefreshTiles()
yes(friend.health.maximum==uiResourceSecret,"secret health max goes only to native range")
yes(friend.power.maximum==uiResourceSecret,"secret resource max goes only to native range")
type,issecretvalue=priorType,priorSecret
live.party1.health,live.party1.healthCurrent,live.party1.healthMax,live.party1.healthAvailable=.5,50,100,true
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=nil,nil,nil
live.party1.powerCurrent,live.party1.powerMax,live.party1.powerAvailable=nil,nil,false
NS.RefreshTiles()
eq(friend:GetAttribute("unit"),"party1","friendly native mouseover unit set")
eq(enemy.unit,"nameplate1","nameplate display and GUID tracking retains original Lua token")
eq(enemy:GetAttribute("unit"),"nameplate1","generic unit remains available to native mouseover lookup")
eq(enemy:GetAttribute("*unit1"),nil,"nameplate rebind clears stale override and retains native unit existence guard")
eq(enemy:GetAttribute("mark-unit"),"nameplate1","right-click controller retains original mark token")
eq(friend:GetAttribute("*macrotext1"),nil,"friendly left click does not depend on nested macro execution")
eq(enemy:GetAttribute("*type1"),"macro","read-only nameplate left click uses internal exact-name action")
eq(enemy:GetAttribute("*macrotext1"),"/targetexact 野狼","monster nameplate action uses actual exact NPC name")
live.nameplate9=data("nameplate9","Player-realm","同伴","friendly",true)
live.nameplate9.targetName="同伴-远方服务器"
NS.BindTiles("friendly",{"nameplate9"},5)
eq(friend:GetAttribute("*macrotext1"),"/targetexact 同伴-远方服务器","nearby player action retains canonical realm suffix")
eq(friend:GetAttribute("unit"),"nameplate9","friendly fallback retains generic mouseover unit")
eq(friend:GetAttribute("*unit1"),nil,"friendly name action keeps normal modified-unit lookup")
friend:SetAttribute("*unit1","") -- stable rebind must also clean older candidate state
NS.BindTiles("friendly",{"party1"},5)
eq(friend:GetAttribute("*type1"),"target","rebinding to stable party unit restores native target action")
eq(friend:GetAttribute("*macrotext1"),nil,"stable-unit rebind clears old name macro")
eq(friend:GetAttribute("*unit1"),nil,"stable-unit rebind clears nameplate left-click NOOP")
live.target=data("target","Creature-target","当前敌人","enemy",false)
NS.BindTiles("enemy",{"target"},5)
eq(enemy:GetAttribute("*type1"),"target","current target token keeps native target action")
eq(enemy:GetAttribute("*macrotext1"),nil,"current target rebind clears nameplate macro")
eq(enemy:GetAttribute("*unit1"),nil,"current target rebind restores normal modified-unit lookup")
live.boss1=data("boss1","Creature-boss","首领","enemy",false)
NS.BindTiles("enemy",{"boss1"},5)
eq(enemy:GetAttribute("unit"),"boss1","actionable boss alias retains native secure unit")
eq(enemy:GetAttribute("*macrotext1"),nil,"actionable boss alias does not use read-only-nameplate macro")
NS.BindTiles("enemy",{},5)
eq(enemy:GetAttribute("*macrotext1"),nil,"empty rebind cannot leave an executable exact-name macro")
NS.BindTiles("enemy",{"nameplate1"},5)
combat=true
NS.BindTiles("enemy",{"target"},5)
eq(enemy.unit,"nameplate1","combat does not replace frozen nameplate display binding")
eq(enemy:GetAttribute("unit"),"nameplate1","combat preserves generic nameplate unit")
eq(enemy:GetAttribute("*unit1"),nil,"combat retains native unit lookup without reintroducing override")
eq(enemy:GetAttribute("*macrotext1"),"/targetexact 野狼","combat does not rewrite frozen internal name action")
combat=false
for _,row in ipairs({friend,enemy}) do
    eq(row:GetAttribute("*type2"),"focus","right click uses the native focus action")
    eq(row:GetAttribute("*clickbutton2"),nil,"plain right click never forwards to marking")
    for _,modifier in ipairs({"ctrl-","alt-ctrl-","ctrl-shift-","alt-ctrl-shift-"}) do
        eq(row:GetAttribute(modifier.."type2"),"click","Ctrl-right combinations open the marking palette")
        eq(row:GetAttribute(modifier.."clickbutton2"),row.markController,"Ctrl-right combinations use the owned controller")
    end
    eq(row:GetAttribute("ctrl-clickbutton2"),row.markController,"right-click action points to its own controller")
    yes(row.markController.refs.row==row and row.markController.refs.markMenu==NS.MarkerMenu,
        "right-click controller references its source row and marking menu")
    eq(row.markController.mouse,false,"right-click controller cannot cover native left-click hit area")
end
local menuScript=enemy.markController:GetAttribute("_onclick")
local menuShow=menuScript:find("menu:Show()",1,true)
local menuHide=menuScript:find("menu:Hide()",1,true)
yes(menuHide and menuShow and menuHide<menuShow,"right click clears the old menu before validating the new source")
eq(menuScript:find("SecureCmdOptionParse",1,true),nil,"public macro-condition limitation is not an extra marking gate")
yes(menuScript:find('GetAttribute("mark-unit")',1,true),"mark controller reads retained token when action unit is nil")
local markPre,markPost
for _,entry in ipairs(wrapped) do
    if entry.button==NS.MarkerMenu.markers[8] then
        eq(entry.script~="OnClick",true,"marker native OnClick is never wrapped")
        if entry.script=="PreClick" then markPre=entry.pre end
        if entry.script=="PostClick" then markPost=entry.pre end
    end
end
yes(markPre and markPost,"marker has independent secure preflight and close phases")
local secureViews={}
local function secureView(frame)
    if not frame then return nil end
    if secureViews[frame] then return secureViews[frame] end
    local view={_frame=frame}
    secureViews[frame]=view
    return setmetatable(view,{__index=function(_,key)
        if key=="GetFrameRef" then return function(_,name) return secureView(frame.refs[name]) end end
        local value=frame[key]
        if type(value)~="function" then return value end
        return function(_,...)
            local args={...}
            for i,item in ipairs(args) do if type(item)=="table" and rawget(item,"_frame") then args[i]=item._frame end end
            return value(frame,unpack(args))
        end
    end})
end
local function modelSecure(source,self,control,combatCondition)
    local environment={self=secureView(self),control=secureView(control),button="LeftButton",
        SecureCmdOptionParse=function(options)
            if combatCondition and combat and options=="[combat] blocked" then return "blocked" end
        end}
    setmetatable(environment,{__index=_G})
    local model=assert(loadstring(source))
    setfenv(model,environment)
    secureModel=true
    local ok,err=pcall(model)
    secureModel=false
    assert(ok,err)
end
eq(friend.nameText:GetText(),"同伴","friendly label from live unit")
eq(enemy.nameText:GetText(),"野狼","monster label from live unit")
eq(friend.shield:IsShown(),false,"valid friendly tile accepts mouse input")
yes(NS.UI.friendly.tiles[2].shield:IsShown(),"empty tile blocks mouse input")
-- Check native tooltip API usage only. This mock does not reproduce or prove
-- any C++ mouseover side effect from SetText, SetUnit, or tooltip ownership.
local function resetTooltipOperations()
    GameTooltip.tooltipOperations={};GameTooltip.lines={}
end
local function hasTooltipOperation(operation)
    for _,value in ipairs(GameTooltip.tooltipOperations) do if value==operation then return true end end
    return false
end
local function tooltipContains(text)
    for _,line in ipairs(GameTooltip.lines) do if line[1]:find(text,1,true) then return true end end
    return false
end
resetTooltipOperations()
enemy:GetScript("OnEnter")(enemy)
eq(enemy.unitTooltipReady,true,"native successful unit tooltip is explicitly ready")
eq(GameTooltip.unit,"nameplate1","unit tooltip binds actual displayed live token")
eq(GameTooltip.tooltipOperations[1],"SetOwner","unit tooltip establishes owner first")
eq(GameTooltip.tooltipOperations[2],"SetUnit","unit tooltip binds native unit before added details")
eq(hasTooltipOperation("SetText"),false,"successful unit tooltip never replaces payload with SetText")
eq(hasTooltipOperation("ClearLines"),false,"successful unit tooltip never clears native payload")
yes(hasTooltipOperation("AddLine"),"unit details append to native tooltip")
local npcHelp={}
for _,line in ipairs(GameTooltip.lines) do npcHelp[#npcHelp+1]=line[1] end
local npcHelpText=table.concat(npcHelp,"\n")
yes(npcHelpText:find("已发现无重名",1,true) and npcHelpText:find("游戏世界",1,true),
    "NPC hover help explains known-name scope and world selection for duplicate names")
yes(npcHelpText:find("距离",1,true) and npcHelpText:find("朝向",1,true) and npcHelpText:find("冷却",1,true),
    "NPC hover help retains ordinary spell range facing and cooldown requirements")
resetTooltipOperations()
live.nameplate1.name="野狼更新提示"
NS.RefreshTiles()
eq(hasTooltipOperation("SetUnit"),true,"live tooltip refresh rebinds real unit")
eq(hasTooltipOperation("SetText"),false,"live tooltip refresh keeps native payload")
live.nameplate1.name="野狼"
enemy:GetScript("OnLeave")(enemy)
local uiSecret={}
local previousSecretCheck=issecretvalue
issecretvalue=function(value) return value==uiSecret end
for _,case in ipairs({{value=false},{value=nil},{value=uiSecret},{throws=true}}) do
    unitTooltipResult,unitTooltipThrows=case.value,case.throws==true
    resetTooltipOperations()
    eq(pcall(enemy:GetScript("OnEnter"),enemy),true,"unavailable native tooltip does not crash row hover")
    eq(enemy.unitTooltipReady,false,"unavailable native tooltip never claims confirmed unit")
    yes(hasTooltipOperation("SetText"),"unavailable unit tooltip may use plain-text fallback")
    yes(tooltipContains("原生鼠标单位未确认"),"fallback reports native mouse unit unconfirmed")
    yes(tooltipContains("未准备战斗悬停按键"),"unavailable native tooltip still exposes preparation state")
    enemy:GetScript("OnLeave")(enemy)
end
issecretvalue=previousSecretCheck
unitTooltipResult,unitTooltipThrows=true,false
GameTooltip.SetUnit=false
eq(pcall(enemy:GetScript("OnEnter"),enemy),true,"missing native SetUnit API degrades without crashing")
eq(enemy.unitTooltipReady,false,"missing native SetUnit API is not ready")
enemy:GetScript("OnLeave")(enemy)
GameTooltip.SetUnit=nil
resetTooltipOperations()
local ordinaryTooltipButton=NS.MarkerMenu.markers[8]
ordinaryTooltipButton:GetScript("OnEnter")(ordinaryTooltipButton)
eq(hasTooltipOperation("SetText"),true,"ordinary control tooltip may still use text title")
ordinaryTooltipButton:GetScript("OnLeave")(ordinaryTooltipButton)
NS.RefreshTiles()
live.nameplate1.target,live.nameplate1.questTarget,live.nameplate1.raidMarker=true,true,8
live.party1.target,live.party1.questTarget=true,true
NS.RefreshTiles()
eq(enemy.targetBadge:IsShown(),true,"current enemy has explicit current-target badge")
eq(enemy.targetBadge.label:GetText(),"当前","current target is identified by text as well as color")
eq(enemy.targetFill:IsShown(),true,"current target has visible fill")
for _,edge in ipairs(enemy.targetEdges) do eq(edge:IsShown(),true,"current-target border edge visible") end
eq(enemy.targetEdges[1]:GetHeight(),2,"selected top border is two pixels thick")
eq(enemy.targetEdges[2]:GetHeight(),2,"selected bottom border is two pixels thick")
eq(enemy.targetEdges[3]:GetWidth(),2,"selected left border is two pixels thick")
eq(enemy.targetEdges[4]:GetWidth(),2,"selected right border is two pixels thick")
eq(enemy.targetEdges[1].color[1],1,"selected border red channel")
eq(enemy.targetEdges[1].color[2],.15,"selected border green channel")
eq(enemy.targetEdges[1].color[3],.12,"selected border blue channel")
eq(enemy.questBadge:IsShown(),true,"confirmed quest monster has quest badge")
eq(enemy.marker:IsShown(),true,"raid marker remains visible beside quest and current-target badges")
eq(enemy.marker.raidIcon,8,"raid marker still matches actual marker index")
eq(enemy.statusText:GetText(),"50%","current-target badge above the square preserves readable bottom health text")
eq(friend.targetBadge:IsShown(),true,"friendly current target also highlighted")
eq(friend.questBadge:IsShown(),false,"quest monster badge never shown on friendly player")
local second=data("nameplate2","Creature-second","第二目标","enemy",false)
live.nameplate2=second
NS.BindTiles("enemy",{"nameplate1","nameplate2"},5)
live.nameplate1.target=false;second.target=true
NS.RefreshTiles()
eq(enemy.targetBadge:IsShown(),false,"target switch clears previous current-target badge")
eq(NS.UI.enemy.tiles[2].targetBadge:IsShown(),true,"target switch highlights new current target")
eq(enemy.questBadge:IsShown(),true,"quest relationship remains independent of selection")
second.player,second.questTarget=true,true
NS.RefreshTiles()
eq(NS.UI.enemy.tiles[2].questBadge:IsShown(),false,"hostile player never gets monster quest badge")
live.nameplate2=nil
NS.RefreshTiles()
eq(NS.UI.enemy.tiles[2].targetBadge:IsShown(),false,"empty tile clears current-target badge")
eq(NS.UI.enemy.tiles[2].targetFill:IsShown(),false,"empty tile clears current-target fill")
eq(NS.UI.enemy.tiles[2].questBadge:IsShown(),false,"empty tile clears quest badge")
live.nameplate1.target,live.nameplate1.questTarget,live.nameplate1.raidMarker=false,false,nil
live.party1.target,live.party1.questTarget=false,false
NS.RefreshTiles()
eq(enemy.questBadge:IsShown(),false,"completed quest relationship clears quest badge")
eq(enemy.marker:IsShown(),false,"cleared raid marker does not leave cached icon")
combat=true
live.party1.name="同伴新名"
NS.RefreshTiles()
eq(friend.nameText:GetText(),"同伴新名","combat labels refresh from bound unit")
live.party1.player=false
NS.RefreshTiles()
yes(friend.shield:IsShown(),"combat token reused for NPC blocks input")
yes(friend.nameText:GetText()~="同伴新名","reused token never leaves cached player label")
live.nameplate1=nil
NS.RefreshTiles()
yes(enemy.shield:IsShown(),"removed enemy blocks input in combat")
live.nameplate1=data("nameplate1","Creature-2","新敌人","enemy",false)
NS.RefreshTiles()
eq(enemy.nameText:GetText(),"","new GUID never inherits an old combat click binding")
eq(enemy.shield:IsShown(),true,"replacement GUID stays blocked until out-of-combat rebind")
combat=false
NS.BindTiles("enemy",{"nameplate1"},20)
NS.RefreshTiles()
eq(enemy.nameText:GetText(),"新敌人","out-of-combat rebind displays replacement identity")
eq(enemy.shield:IsShown(),false,"out-of-combat rebind rearms eligible tile")
eq(NS.UI.enemy.tiles[20]:IsShown(),true,"enemy twenty capacity exposes final tile")
NS.BindTiles("enemy",{"nameplate1"},5)
eq(NS.UI.enemy.tiles[6]:IsShown(),false,"five capacity hides extra tiles out of combat")
local rowWasWrapped=false
for _,entry in ipairs(wrapped) do if entry.button.side and entry.script=="OnClick" then rowWasWrapped=true end end
eq(rowWasWrapped,false,"native tile OnClick remains unwrapped")
yes(#wrapped>=9,"marker palette still uses secure action guards")
-- World hover is shown only when the exact live unit has a real visible plate.
local plate=newFrame("Frame","TargetsTestPlate");plate:SetSize(100,20)
plate.namePlateUnitToken="nameplate1"
C_NamePlate={GetNamePlateForUnit=function(unit) return unit=="nameplate1" and plate or nil end}
NS.SetHoverUnit("nameplate1","enemy")
yes(NS.HoverIndicator and NS.HoverIndicator:IsShown(),"world hover attaches to exposed matching nameplate")
eq(NS.HoverIndicator.mouse,false,"world indicator cannot intercept mouse input")
live.nameplate1.guid="Creature-3"
NS.UpdateHover()
eq(NS.HoverIndicator:IsShown(),false,"hover indicator rejects token identity reuse")
NS.SetHoverUnit("nameplate1","enemy")
plate:Hide();NS.UpdateHover()
eq(NS.HoverIndicator:IsShown(),false,"hidden nameplate never gets guessed world position")
plate:Show();plate.forbidden=true;NS.UpdateHover()
eq(NS.HoverIndicator:IsShown(),false,"forbidden nameplate is ignored")
plate.forbidden=false
NS.SetHoverUnit(nil)
eq(NS.HoverIndicator:IsShown(),false,"leaving unit clears world indicator")
-- Marker UI keeps the original source identity and blocks a reused unit alias.
local menu=NS.MarkerMenu
NS.BindTiles("enemy",{"nameplate1"},5)
for i=0,8 do
    eq(menu.markers[i]:GetAttribute("useOnKeyDown"),false,"marker palette uses explicit up-click")
end
menu:SetAttribute("unit","nameplate1")
menu:SetAttribute("target-side","enemy")
menu:SetAttribute("source-guid",live.nameplate1.guid)
menu:SetAttribute("source-row",enemy:GetName())
menu:Show()
eq(menu.sourceGUID,"Creature-3","mark palette snapshots original source identity")
eq(menu.shield:IsShown(),false,"valid marker source accepts palette input")
combat=true
live.nameplate1.guid="Creature-4"
NS.InvalidateMarkMenu()
eq(menu.shield:IsShown(),true,"marker palette blocks reused source GUID during combat")
if NS.CloseMarkMenu then NS.CloseMarkMenu() end
eq(menu:IsShown(),true,"insecure close does not mutate protected palette in combat")
combat=false
if NS.CloseMarkMenu then NS.CloseMarkMenu() else menu:Hide() end
eq(menu:IsShown(),false,"palette can close out of combat")

-- Execute the secure snippets as a Lua model, without invoking the native
-- SetRaidTarget action. Nameplate macro-condition parsing deliberately fails.
NS.BindTiles("enemy",{"nameplate1"},5)
local markTarget,markSource=menu.markers[8],live.nameplate1.guid
local nativeClicksBeforeMarkModel=nativeActionClicks
modelSecure(menuScript,enemy.markController,menu)
eq(menu:IsShown(),true,"nameplate menu opens from a prepared source even if macro conditions cannot resolve it")
eq(menu:GetAttribute("unit"),"nameplate1","menu retains the actual clicked nameplate token")
eq(menu:GetAttribute("source-guid"),markSource,"secure menu retains the OOC prepared GUID snapshot")
eq(menu.sourceGUID,markSource,"ordinary menu identity is pinned to the prepared source")
eq(menu.shield:IsShown(),false,"matching public source GUID enables the palette")
for i=0,8 do
    eq(menu.markers[i]:GetScript("OnClick"),menu.markers[i].nativeClick,"marker retains its original XML-installed click handler")
    yes(menu.markers[i].nativeClick~=nil,"marker native handler existed before any observer was installed")
    eq(menu.markers[i]:GetAttribute("unit"),"nameplate1","each marker receives the clicked token")
    eq(menu.markers[i]:GetAttribute("source-guid"),markSource,"each marker receives the same source GUID")
    eq(menu.markers[i]:GetAttribute("*type1"),nil,"opening menu leaves action type gated until secure PreClick")
end
modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),"raidtarget","secure PreClick enables only the existing native raidtarget action")
eq(nativeActionClicks,nativeClicksBeforeMarkModel,"guard model never manually calls native OnClick")
markTarget:SetAttribute("unit",nil);modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"nil unit cannot fall through to native current-target default")
markTarget:SetAttribute("unit","");modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"empty unit cannot enable a native marker action")
markTarget:SetAttribute("unit","target");modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"another token cannot be combined with this menu's source")
markTarget:SetAttribute("unit","nameplate1")
markTarget:SetAttribute("source-guid","Creature-stale-marker");modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"stale marker snapshot cannot use a different menu identity")
markTarget:SetAttribute("source-guid",markSource)
menu:SetAttribute("source-guid",nil);modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"missing menu source snapshot keeps the native action inert")
menu:SetAttribute("source-guid",markSource)
modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),"raidtarget","restored matching source can be prepared again")
modelSecure(markPost,markTarget,menu)
eq(menu:IsShown(),false,"secure PostClick only closes the palette")
modelSecure(markPre,markTarget,menu)
eq(markTarget:GetAttribute("*type1"),nil,"hidden marker button cannot execute a retained source")
live.nameplate1.guid="Creature-marker-live-reused"
menu:Show()
eq(menu.sourceGUID,markSource,"showing an old menu never adopts a replacement live GUID")
eq(menu.shield:IsShown(),true,"public live identity mismatch shields the stale palette")
NS.InvalidateMarkMenu()
eq(menu.shield:IsShown(),true,"ongoing menu validation keeps replacement GUID blocked")
live.nameplate1.guid=markSource
modelSecure(menuScript,enemy.markController,menu)
eq(menu.shield:IsShown(),false,"a fresh matching open restores the palette after a stale source")
enemy:SetAttribute("mark-unit",nil);enemy:SetAttribute("unit",nil)
modelSecure(menuScript,enemy.markController,menu)
eq(menu:IsShown(),false,"failed empty-source open closes the previously visible menu")
eq(menu:GetAttribute("unit"),nil,"failed open clears the previous menu token")
eq(menu:GetAttribute("source-guid"),nil,"failed open clears the previous protected GUID snapshot")
eq(menu.sourceGUID,nil,"failed open also clears the ordinary menu identity")
for i=0,8 do
    eq(menu.markers[i]:GetAttribute("unit"),nil,"failed open clears every old marker token")
    eq(menu.markers[i]:GetAttribute("source-guid"),nil,"failed open clears every old marker identity")
    eq(menu.markers[i]:GetAttribute("*type1"),nil,"failed open disarms every old marker action")
end
enemy:SetAttribute("mark-unit","nameplate1");enemy:SetAttribute("unit","nameplate1")
enemy:SetAttribute("mark-guid",nil)
modelSecure(menuScript,enemy.markController,menu)
eq(menu:IsShown(),false,"a token without an OOC prepared GUID cannot open a menu")
NS.BindTiles("enemy",{"nameplate1"},5)
eq(enemy:GetAttribute("mark-guid"),enemy.expectedGUID,"OOC tile binding prepares marker identity independently of casting")
combat=true
NS.BindTiles("enemy",{"target"},5)
eq(enemy:GetAttribute("mark-guid"),markSource,"combat binding cannot replace the prepared marker identity")
combat=false

-- Native keyboard hover casting settings must be reversible, including /reload.
local nativeValue,nativeKey,bindingSet,saves="0","ALT",1,0
local supported,failValue,failKey,failSave=true,false,false,false
local plateValues={nameplateShowFriendlyPlayers="0",nameplateShowFriends="0",nameplateShowEnemies="0",nameplateShowAll="1",
    nameplateShowFriendlyNPCs="0",nameplateShowFriendlyPets="0"}
local failPlateKey,unknownPlateKey,simulateRollbackFailure,rollbackBlocked
IsMouseoverCastSupported=function() return supported end
C_CVar={GetCVar=function(key)
        if key==unknownPlateKey then return nil end
        return key=="enableMouseoverCast" and nativeValue or plateValues[key]
    end,
    SetCVar=function(key,value)
        if failValue then error("CVar setter blocked") end
        if key=="enableMouseoverCast" then nativeValue=value
        elseif key=="nameplateShowFriendlyPlayers" or key=="nameplateShowFriends" or key=="nameplateShowEnemies" or key=="nameplateShowAll" then
            if key==failPlateKey then error("plate CVar blocked") end
            if simulateRollbackFailure and key=="nameplateShowEnemies" and value=="1" then
                rollbackBlocked=true;error("enable interrupted before rollback")
            end
            if rollbackBlocked and key=="nameplateShowFriendlyPlayers" and value=="0" then error("rollback blocked") end
            assert(plateValues[key]~=nil,"unsupported CVar must not be created")
            plateValues[key]=value
        else error("unrelated CVar must remain untouched") end
    end}
GetModifiedClick=function() return nativeKey end
SetModifiedClick=function(_,key) if failKey then error("binding setter blocked") end;nativeKey=key end
GetCurrentBindingSet=function() return bindingSet end
SaveBindings=function(set)
    eq(set,bindingSet,"only active binding set saved");saves=saves+1
    if failSave then return false end
end
assert(loadfile(root.."Mouseover.lua"))("MyForeverTargets",NS)
eq(NS.MouseoverStatus(),false,"native hover initially disabled")
yes(NS.SetMouseoverEnabled(true,true),"native hover can be enabled")
eq(nativeValue,"1","native hover CVar enabled")
eq(nativeKey,"NONE","native hover requires no modifier")
eq(NS.DB.mouseoverBackup.enabled,"0","prior CVar stored")
eq(NS.DB.mouseoverBackup.key,"ALT","prior modifier stored")
NS.Initialize(NS.DB)
eq(NS.DB.mouseoverBackup.bindingSet,1,"backup binding profile survives saved-variable normalization")
yes(NS.SetMouseoverEnabled(false,true),"native hover restore after reload succeeds")
eq(nativeValue,"0","prior CVar restored")
eq(nativeKey,"ALT","prior modifier restored")
eq(NS.DB.mouseoverBackup,nil,"backup cleared after restoration")
yes(NS.SetMouseoverEnabled(true,true),"native hover reenables")
nativeValue,nativeKey="0","SHIFT"
NS.SetMouseoverEnabled(false,true)
eq(nativeValue,"0","user-edited native value preserved on restore")
eq(nativeKey,"SHIFT","user-edited modifier preserved on restore")
nativeValue,nativeKey="0","ALT"
failKey=true
eq(NS.SetMouseoverEnabled(true,true),false,"partial enable reports failure")
eq(nativeValue,"0","failed modifier enable rolls CVar back")
eq(nativeKey,"ALT","failed modifier enable keeps prior modifier")
failKey=false
failValue=true
eq(NS.SetMouseoverEnabled(true,true),false,"blocked CVar enable reports failure")
eq(nativeValue,"0","blocked CVar enable preserves old value")
eq(nativeKey,"ALT","blocked CVar enable rolls modifier back")
failValue=false
yes(NS.SetMouseoverEnabled(true,true),"native hover enables for restore failure check")
failValue=true
eq(NS.SetMouseoverEnabled(false,true),false,"blocked CVar restoration reports failure")
yes(NS.DB.mouseoverBackup,"failed CVar restoration retains original settings")
failValue=false
yes(NS.SetMouseoverEnabled(false,true),"CVar restoration can retry")
eq(nativeValue,"0","CVar retry restores original value")
yes(NS.SetMouseoverEnabled(true,true),"native hover enables for modifier restore failure")
failKey=true
eq(NS.SetMouseoverEnabled(false,true),false,"blocked modifier restoration reports failure")
yes(NS.DB.mouseoverBackup,"failed modifier restoration retains original settings")
failKey=false
yes(NS.SetMouseoverEnabled(false,true),"modifier restoration can retry")
eq(nativeKey,"ALT","modifier retry restores original value")
yes(NS.SetMouseoverEnabled(true,true),"first binding scheme enables with backup")
bindingSet,nativeKey=2,"SHIFT"
yes(NS.SetMouseoverEnabled(true,true),"second binding scheme enables with independent backup")
NS.Initialize(NS.DB)
eq(NS.DB.mouseoverBackup.modifiers[1],"ALT","first binding scheme backup survives reload")
eq(NS.DB.mouseoverBackup.modifiers[2],"SHIFT","second binding scheme backup survives reload")
yes(NS.SetMouseoverEnabled(false,true),"active second scheme restores")
eq(nativeKey,"SHIFT","second scheme restores its own modifier")
yes(NS.DB.mouseoverBackup,"inactive scheme backup is retained")
bindingSet,nativeKey=1,"NONE"
yes(NS.SetMouseoverEnabled(false,true),"first scheme restores after switching back")
eq(nativeKey,"ALT","first scheme restores its own modifier")
eq(NS.DB.mouseoverBackup,nil,"all scheme backups clear after both restore")
yes(NS.SetMouseoverEnabled(true,true),"enable for failed persistence check")
failSave=true
eq(NS.SetMouseoverEnabled(false,true),false,"failed persistence reports incomplete restore")
yes(NS.DB.mouseoverBackup,"failed persistence retains restoration backup")
failSave=false
local savedBeforeRetry=saves
yes(NS.SetMouseoverEnabled(false,true),"failed persistence can retry")
yes(saves>savedBeforeRetry,"restoration retry persists modifier even when already restored in memory")
-- Nearby discovery enables the current client's actual nameplate switches and
-- preserves the user's original settings; it does not expose NPCs as players.
local detection,_,detectionAvailable=NS.DetectionStatus()
eq(detection,false,"nearby detection initially disabled by current client CVars")
eq(detectionAvailable,true,"current friendly-player CVar is recognized")
yes(NS.SetDetectionEnabled(true,true),"nearby detection enables required native plates")
eq(plateValues.nameplateShowFriendlyPlayers,"1","current friendly-player switch enabled")
eq(plateValues.nameplateShowFriends,"0","legacy friendly switch untouched when current switch exists")
eq(plateValues.nameplateShowEnemies,"1","hostile plate switch enabled")
eq(plateValues.nameplateShowAll,"1","preexisting always-show switch preserved")
eq(plateValues.nameplateShowFriendlyNPCs,"0","friendly NPC visibility is not enabled")
eq(plateValues.nameplateShowFriendlyPets,"0","friendly pet visibility is not enabled")
NS.Initialize(NS.DB)
yes(NS.SetDetectionEnabled(false,true),"nearby plate settings restore after saved-variable reload")
eq(plateValues.nameplateShowFriendlyPlayers,"0","original friendly-player switch restored")
eq(plateValues.nameplateShowEnemies,"0","original hostile plate switch restored")
eq(plateValues.nameplateShowAll,"1","original always-show setting unchanged")
plateValues.nameplateShowFriendlyPlayers=nil
yes(NS.SetDetectionEnabled(true,true),"legacy client falls back to old friendly switch")
eq(plateValues.nameplateShowFriends,"1","legacy friendly plate switch enabled only as fallback")
NS.SetDetectionEnabled(false,true)
eq(plateValues.nameplateShowFriends,"0","legacy friendly plate switch restores")
plateValues.nameplateShowFriendlyPlayers="0"
failPlateKey="nameplateShowEnemies"
eq(NS.SetDetectionEnabled(true,true),false,"failed plate switch reports unsuccessful detection setup")
eq(plateValues.nameplateShowFriendlyPlayers,"0","partial detection setup rolls friendly switch back")
eq(plateValues.nameplateShowEnemies,"0","failed hostile switch stays original")
failPlateKey=nil
NS.SetDetectionEnabled(true,true)
failPlateKey="nameplateShowFriendlyPlayers"
eq(NS.SetDetectionEnabled(false,true),false,"blocked plate restoration reports incomplete restore")
eq(NS.DB.nameplateBackup.nameplateShowFriendlyPlayers,"0","blocked restoration retains prior plate value")
failPlateKey=nil
yes(NS.SetDetectionEnabled(false,true),"plate restoration can retry")
eq(plateValues.nameplateShowFriendlyPlayers,"0","plate restoration retry restores friendly switch")
simulateRollbackFailure=true
eq(NS.SetDetectionEnabled(true,true),false,"interrupted enable with blocked rollback reports failure")
eq(plateValues.nameplateShowFriendlyPlayers,"1","failed rollback leaves actual live value visible to caller")
eq(NS.DB.nameplateBackup.nameplateShowFriendlyPlayers,"0","original value staged before write survives failed rollback")
simulateRollbackFailure,rollbackBlocked=false,false
yes(NS.SetDetectionEnabled(false,true),"failed rollback can later restore through retained backup")
eq(plateValues.nameplateShowFriendlyPlayers,"0","retained original value restores after rollback becomes possible")
NS.SetDetectionEnabled(true,true)
unknownPlateKey="nameplateShowFriendlyPlayers"
eq(NS.SetDetectionEnabled(false,true),false,"unknown restore readback reports incomplete restoration")
eq(NS.DB.nameplateBackup.nameplateShowFriendlyPlayers,"0","unknown restore readback keeps original backup")
unknownPlateKey=nil
yes(NS.SetDetectionEnabled(false,true),"unknown restore readback can retry when readable")
eq(plateValues.nameplateShowFriendlyPlayers,"0","readback recovery restores original plate value")
local savedPlateValues=plateValues
plateValues={}
local _,_,unavailableDetection=NS.DetectionStatus()
eq(unavailableDetection,false,"missing plate CVars are reported unavailable")
eq(NS.SetDetectionEnabled(true,true),false,"missing plate CVars never pretend to enable detection")
plateValues=savedPlateValues
supported=false
eq(NS.SetMouseoverEnabled(true,true),false,"unsupported native API reports unavailable")
eq(nativeValue,"0","unavailable API never changes CVar")
eq(nativeKey,"ALT","unavailable API never changes modifier")
supported=true

-- Drive the actual Main.lua queue through combat without protected mutations.
live.party1=data("party1","Player-1","同伴","friendly",true)
live.party2=data("party2","Player-2","另一同伴","friendly",true)
live.nameplate2=data("nameplate2","Creature-next","第二敌人","enemy",false)
local enemyOrder={"nameplate1","nameplate2"}
local friendlyOrder={"party1","party2"}
NS.Collect=function(side,mode,limit)
    local result=side=="friendly" and friendlyOrder or enemyOrder
    return result,#result
end
MyForeverTargetsDB=nil
assert(loadfile(root.."Main.lua"))("MyForeverTargets",NS)
NS.HandleEvent("ADDON_LOADED","MyForeverTargets")
NS.HandleEvent("PLAYER_ENTERING_WORLD")
eq(nativeValue,"1","world entry activates requested native hover")
eq(nativeKey,"NONE","world entry enables keyboard hover without modifier")
eq(plateValues.nameplateShowFriendlyPlayers,"1","world entry enables current friendly-player discovery switch")
eq(plateValues.nameplateShowEnemies,"1","world entry enables enemy discovery switch")
eq(type(SlashCmdList.MYFOREVERTARGETS),"function","slash command registered")
eq(NS.UI.enemy.tiles[1].unit,"nameplate1","initial enemy order bound")
for _,event in ipairs({"UNIT_POWER_UPDATE","UNIT_POWER_FREQUENT","UNIT_MAXPOWER","UNIT_DISPLAYPOWER"}) do
    eq(NS.EventFrame.events[event],true,"resource event registered: "..event)
end
combat=true
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=.65,"MANA",{r=0,g=.3,b=1}
live.party1.powerCurrent,live.party1.powerMax,live.party1.powerAvailable=65,100,true
NS.HandleEvent("UNIT_POWER_UPDATE","party1")
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,.01)
eq(NS.UI.friendly.tiles[1].power.value,65,"combat resource update reaches visual throttle without rebinding")
eq(NS.UI.friendly.tiles[1].unit,"party1","combat resource refresh keeps secure unit identity")
live.party1.powerRatio,live.party1.powerToken,live.party1.powerColor=.25,"ENERGY",{r=1,g=1,b=0}
live.party1.powerCurrent=25
NS.HandleEvent("UNIT_DISPLAYPOWER","party1")
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,.01)
eq(NS.UI.friendly.tiles[1].power.statusColor[1],1,"display-power event replaces old mana color in combat")
combat=false
local hovered=NS.UI.enemy.tiles[1]
hovered:GetScript("OnEnter")(hovered)
eq(NS.HoveredTile,hovered,"valid tile enter records pointer owner")
enemyOrder={"nameplate2","nameplate1"}
friendlyOrder={"party2","party1"}
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,1)
eq(NS.UI.enemy.tiles[1].unit,"nameplate1","distance reorder holds the side currently under pointer")
eq(NS.UI.friendly.tiles[1].unit,"party2","other side can refresh while one side is hovered")
hovered:GetScript("OnLeave")(hovered)
eq(NS.HoveredTile,nil,"leaving tile releases pointer hold")
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,1)
eq(NS.UI.enemy.tiles[1].unit,"nameplate2","periodic out-of-combat refresh applies distance order changes")
combat=true
enemyOrder={"nameplate1","nameplate2"}
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,1)
eq(NS.UI.enemy.tiles[1].unit,"nameplate2","distance changes do not move secure tile bindings in combat")
combat=false
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.UI.enemy.tiles[1].unit,"nameplate1","combat-end refresh applies current distance order")
local previous=NS.DB.enemyLimit
local drag=NS.UI.friendly.drag
drag:GetScript("OnDragStart")(drag)
eq(NS.UI.friendly.frame.dragProxy:IsShown(),true,"drag starts an unprotected proxy")
eq(NS.UI.friendly.frame.moving,nil,"secure panel does not move while proxy is dragged")
combat=true
NS.HandleEvent("PLAYER_REGEN_DISABLED")
eq(NS.UI.friendly.frame.dragProxy:IsShown(),false,"combat entry cancels drag proxy")
eq(NS.UI.friendly.frame.dragging,false,"combat entry clears drag state")
eq(NS.ApplySetting("enemyLimit",5),false,"capacity change defers during combat")
eq(NS.DB.enemyLimit,previous,"combat keeps current capacity")
NS.ApplySetting("friendlyTab","nearby")
NS.ApplySetting("scale",1.2)
NS.SetMouseoverEnabled(false,true)
eq(NS.SetDetectionEnabled(false,true),false,"nearby detection changes defer in combat")
eq(nativeValue,"1","native settings unchanged during combat")
eq(plateValues.nameplateShowFriendlyPlayers,"1","plate settings unchanged during combat")
NS.HandleEvent("UNIT_NAME_UPDATE","party1")
NS.RequestRefresh()
eq(NS.DB.friendlyTab,"raid","combat keeps current tab")
combat=false
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(NS.DB.enemyLimit,5,"pending capacity applied after combat")
eq(NS.DB.friendlyTab,"nearby","pending friendly tab applied after combat")
eq(NS.DB.scale,1.2,"pending scale applied after combat")
eq(nativeValue,"0","queued native hover disable restores CVar")
eq(nativeKey,"ALT","queued native hover disable restores modifier")
eq(plateValues.nameplateShowFriendlyPlayers,"0","queued detection disable restores friendly plates after combat")
eq(plateValues.nameplateShowEnemies,"0","queued detection disable restores hostile plates after combat")
eq(NS.ApplySetting("enemyLimit",7),false,"unsupported capacity rejected")
eq(NS.DB.enemyLimit,5,"invalid capacity cannot change current setting")
NS.HandleCommand("nearby 10")
eq(NS.DB.nearbyLimit,10,"nearby slash capacity works")
-- A tab switch with unchanged bindings must not leave stale hover-hold mode.
NS.ApplySetting("friendlyTab","party")
NS.ApplySetting("nearbyLimit",5)
NS.ApplySetting("friendlyTab","nearby")
eq(NS.Bindings.friendly.mode,"nearby","tab mode updates even when tokens and capacity are unchanged")
hovered=NS.UI.friendly.tiles[1]
local hoveredUnit=hovered.unit
hovered:GetScript("OnEnter")(hovered)
friendlyOrder=friendlyOrder[1]=="party2" and {"party1","party2"} or {"party2","party1"}
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,1)
eq(hovered.unit,hoveredUnit,"same-binding tab change still protects current hover from distance reorder")
hovered:GetScript("OnLeave")(hovered)
NS.EventFrame:GetScript("OnUpdate")(NS.EventFrame,1)
eq(NS.UI.friendly.tiles[1].unit,friendlyOrder[1],"nearby reorder resumes after pointer leaves")
NS.HandleCommand("enemy 20")
eq(NS.DB.enemyLimit,20,"enemy slash capacity works")
NS.HandleCommand("hide")
eq(NS.UI.friendly.frame:IsShown(),false,"hide command hides friendly panel")
eq(NS.UI.enemy.frame:IsShown(),false,"hide command hides enemy panel")
NS.HandleCommand("show")
eq(NS.UI.friendly.frame:IsShown(),true,"show command restores friendly panel")
eq(NS.UI.enemy.frame:IsShown(),true,"show command restores enemy panel")

-- Clearing a selected target can rebind the same physical row from target to
-- nameplate without another native OnEnter. Replay the Main event ordering,
-- not a synthetic mouse leave/re-enter, and never dispatch a click.
local priorFoci,priorMouseIsOver,priorCast=GetMouseFoci,MouseIsOver,NS.NearbyCast
local priorRequested=NS.DB.mouseoverRequested
local restoredEntries,restoredRow=0,nil
NS.NearbyCast={Enter=function(row) restoredEntries=restoredEntries+1;restoredRow=row end}
NS.DB.mouseoverRequested=true
MouseIsOver=nil -- This legacy global is absent in the actual client.
live.target=live.nameplate1
enemyOrder={"target","nameplate2"}
NS.RequestRefresh()
local rebound=NS.UI.enemy.tiles[1]
rebound:GetScript("OnEnter")(rebound)
local physicalFocus={rebound}
GetMouseFoci=function() return physicalFocus end
local clickCountBefore=nativeActionClicks
live.target=nil
enemyOrder={"nameplate1","nameplate2"}
NS.HandleEvent("PLAYER_TARGET_CHANGED")
eq(rebound.unit,"nameplate1","clearing target rebinds the same physical row to its nameplate alias")
eq(NS.HoveredTile,rebound,"physical focus restores hover owner without mouse re-entry")
eq(restoredRow,rebound,"restored native focus re-enters nearby cast for the rebound row")
eq(restoredEntries,1,"rebind restores nearby cast exactly once")
eq(GameTooltip.unit,"nameplate1","restored tooltip binds the new live alias")
eq(rebound.hover:IsShown(),true,"rebind restores local hover highlight")
eq(NS.HoverIndicator:IsShown(),true,"rebind restores world hover indicator on exposed plate")
eq(nativeActionClicks,clickCountBefore,"hover recovery never selects a target by dispatching a click")

local function clearRestoredHover()
    rebound:GetScript("OnLeave")(rebound)
    restoredEntries,restoredRow=0,nil
end
clearRestoredHover();physicalFocus={NS.UI.enemy.drag}
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"header focus does not fabricate unit hover")
physicalFocus={rebound.shield}
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"input shield focus does not restore underlying unit hover")
physicalFocus={NS.UI.enemy.tiles[2]}
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"empty physical slot never restores cast state")
physicalFocus={rebound};GetMouseFoci=nil
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"missing native focus API does not guess mouse position")
GetMouseFoci=function() error("mouse focus unavailable") end
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"focus API failure is contained without restoring cast state")
GetMouseFoci=function() return physicalFocus end
local originalReadUnit,reads=NS.ReadUnit,0
NS.ReadUnit=function(unit,side)
    local value=originalReadUnit(unit,side)
    if unit=="nameplate1" and side=="enemy" then
        reads=reads+1
        if reads>1 and value then
            local changed={};for key,item in pairs(value) do changed[key]=item end
            changed.guid="Creature-changed-during-rebind";return changed
        end
    end
    return value
end
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"GUID changed after binding cannot inherit restored hover")
NS.ReadUnit=originalReadUnit
NS.UI.enemy.frame:Hide()
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"hidden panel never restores mouse hover")
NS.UI.enemy.frame:Show()
combat=true
NS.BindTiles("enemy",{"nameplate1"},5)
eq(restoredEntries,0,"combat binding guard never restores hover with insecure changes")
combat=false
GetMouseFoci,MouseIsOver,NS.NearbyCast=priorFoci,priorMouseIsOver,priorCast
NS.DB.mouseoverRequested=priorRequested
-- Prepared combat capability remains visible even when the native tooltip does
-- not confirm a mouse unit. This is presentation/wiring, not a cast simulation.
local oldCombatCast=NS.CombatCast
local preparedStatus={prepared=true,count=2,name="野狼",unit=enemy.unit,guid=enemy.expectedGUID,reason="ready"}
local armCount,armComplete,reconcileCount=0,true,0
local refreshCompleted,requestCompleted,reconciledAfterRefresh=false,false,false
NS.CombatCast={Status=function() return preparedStatus end,
    ArmRow=function(row)
        armCount=armCount+1
        armComplete=armComplete and row:GetAttribute("unit")==row.unit
            and (row.unit==nil or row.expectedGUID~=nil)
    end,
    Reconcile=function() reconcileCount=reconcileCount+1;reconciledAfterRefresh=refreshCompleted and requestCompleted end}
unitTooltipResult=false
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
yes(tooltipContains("原生鼠标单位未确认"),"native tooltip failure is still stated with prepared combat capability")
yes(tooltipContains("已准备 2 个技能键"),"prepared matching snapshot is shown independently of native tooltip")
yes(tooltipContains("无法保证战斗中的GUID"),"prepared NPC tooltip retains snapshot identity limitation")
combat=true
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
yes(tooltipContains("战前已准备的原技能键"),"combat hover explains the prepared key path")
preparedStatus.guid="Creature-old-snapshot"
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
yes(tooltipContains("此格当前没有已准备的战斗按键"),"stale GUID snapshot never advertises prepared capability")
eq(tooltipContains("已准备 2 个技能键"),false,"stale combat preparation is not shown as ready")
NS.BindTiles("enemy",{"nameplate1"},5)
eq(armCount,0,"combat BindTiles never invokes insecure preparation")
combat=false;unitTooltipResult=true
NS.BindTiles("enemy",{"nameplate1"},5)
eq(armCount,20,"OOC bind prepares every row including clearing unused rows")
eq(armComplete,true,"combat preparation runs after each row unit and GUID are bound")
armCount=0
local realRefreshTiles,realRequestRefresh=NS.RefreshTiles,NS.RequestRefresh
NS.RefreshTiles=function(...) realRefreshTiles(...);refreshCompleted=true end
NS.RequestRefresh=function(...) realRequestRefresh(...);requestCompleted=true end
NS.HandleEvent("PLAYER_REGEN_ENABLED")
eq(reconcileCount,1,"leaving combat reconciles the secure hover owner once")
eq(reconciledAfterRefresh,true,"combat reconciliation follows OOC visual and binding refresh")
NS.RefreshTiles,NS.RequestRefresh=realRefreshTiles,realRequestRefresh
NS.CombatCast=oldCombatCast
-- Exercise the real preparation module with the real visibility and Main
-- settings path. The unchanged roster deliberately avoids another BindTiles.
local savedNearby,savedClear,savedRequested=NS.NearbyCast,ClearOverrideBindings,NS.DB.mouseoverRequested
ClearOverrideBindings=function(owner) guard(owner,"ClearOverrideBindings") end
NS.NearbyCast={SnapshotRow=function(row)
    local value=NS.ReadUnit(row.unit,row.side)
    if value and value.guid==row.expectedGUID then return value,true end
end,DiscoverActions=function(side)
    return side=="enemy" and {{side="enemy",actionKind="spell",spell="测试攻击",spellID=679,
        command="MULTIACTIONBAR1BUTTON3",slot=63,keys={"Z"},useOnKeyDown=true}} or {}
end,Reconcile=function() return false end,Leave=function() end}
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
local visibilityCast=NS.CombatCast
NS.DB.mouseoverRequested=true;NS.HoveredTile=nil
NS.RequestRefresh()
local visibilityRow=NS.UI.enemy.tiles[1]
visibilityCast.ArmRow(visibilityRow)
eq(visibilityCast.Status(visibilityRow).prepared,true,"visible row starts with combat actions prepared")
local bindCalls,refreshCalls=0,0
local savedBind,savedRefresh=NS.BindTiles,visibilityCast.RefreshAll
NS.BindTiles=function(...) bindCalls=bindCalls+1;return savedBind(...) end
visibilityCast.RefreshAll=function(...) refreshCalls=refreshCalls+1;return savedRefresh(...) end
NS.SetShown(false)
visibilityCast.RefreshAll()
eq(visibilityCast.Status(visibilityRow).prepared,false,"hidden panel action refresh really disarms its row")
eq(visibilityCast.Status(visibilityRow).reason,"invalid_row","hidden row is not silently left prepared")
local hiddenRefreshes=refreshCalls
NS.SetShown(true)
eq(bindCalls,0,"same roster show does not rely on another unit binding")
eq(visibilityCast.Status(visibilityRow).prepared,true,"showing the same roster re-prepares combat actions")
eq(refreshCalls,hiddenRefreshes+1,"one hidden-to-visible edge refreshes preparation once")
NS.RequestRefresh();NS.RequestRefresh();NS.SetShown(true)
eq(refreshCalls,hiddenRefreshes+1,"visible roster polling and repeated show do not rescan combat actions")
NS.BindTiles=savedBind
NS.CombatCast,NS.NearbyCast=oldCombatCast,savedNearby
ClearOverrideBindings=savedClear;NS.DB.mouseoverRequested=savedRequested

-- Production policy keeps normal target tiles and native left/right actions,
-- while presenting the GUID route as an unverified direct-cast attempt.
local explicitNameSelection=NS.UI.enemy.tiles[1]:GetAttribute("*macrotext1")
NS.PreserveCastTarget=true
local policyCombatCast,policyNearby=NS.CombatCast,NS.NearbyCast
local policyStatus={prepared=true,count=1,name="野狼",unit="nameplate1",guid=live.nameplate1.guid,
    reason="prepared",castMode="guid_hover",preserveTarget=true}
NS.CombatCast={Status=function() return policyStatus end}
NS.NearbyCast=nil
NS.BindTiles("enemy",{"nameplate1"},5)
enemy=NS.UI.enemy.tiles[1]
local function currentTooltipText()
    local parts={}
    for _,line in ipairs(GameTooltip.lines or {}) do parts[#parts+1]=line[1] end
    return table.concat(parts,"\n")
end
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
local policyHelp=currentTooltipText()
yes(policyHelp:find("GUID直施尝试",1,true),"production NPC tooltip names the experimental GUID route")
yes(policyHelp:find("原普通伤害技能键",1,true),"production NPC tooltip uses the original ordinary spell key")
yes(policyHelp:find("同名也按 GUID 区分",1,true),"same-name NPC casting identity is GUID-based")
yes(policyHelp:find("不切换当前目标",1,true),"production tooltip states current-target preservation")
yes(policyHelp:find("尚待游戏验证",1,true),"prepared keys are not advertised as successful gameplay casts")
eq(policyHelp:find("先在游戏世界",1,true),nil,"production tooltip never asks to preselect the NPC")
eq(policyHelp:find("先选自己",1,true),nil,"production tooltip never asks to select the player")
eq(policyHelp:find("A/B",1,true),nil,"normal target tooltip has no A/B experiment instructions")
eq(policyHelp:find("短暂切换",1,true),nil,"production tooltip has no name-switch casting route")
eq(enemy:GetAttribute("*type1"),"macro","preserve casting policy keeps explicit nameplate left selection")
eq(enemy:GetAttribute("*macrotext1"),explicitNameSelection,"explicit left selection retains its existing exact-name action")
eq(enemy:GetAttribute("*type2"),"focus","right click retains native focus")
eq(enemy:GetAttribute("ctrl-type2"),"click","Ctrl-right click forwards the secure mark menu")
eq(enemy:GetScript("OnClick"),SecureActionButton_OnClick,"production policy preserves the XML native click handler")
combat=true
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
yes(tooltipContains("不切换当前目标"),"combat tooltip keeps the same target-preserving instruction")
eq(tooltipContains("战前的名称"),false,"production combat tooltip does not describe legacy name snapshots")
combat=false
policyStatus.prepared=false;policyStatus.reason="no_actions"
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
yes(tooltipContains("已有宏和物品保持原行为"),"unsupported macro and item behavior is disclosed")
policyStatus.prepared=true;policyStatus.reason="prepared";policyStatus.guid="Creature-stale-policy"
resetTooltipOperations();enemy:GetScript("OnEnter")(enemy)
eq(tooltipContains("已准备 1 个普通技能键"),false,"stale policy identity never advertises prepared direct-cast keys")
policyStatus.prepared=false;policyStatus.reason="native_unit";policyStatus.unit="party1";policyStatus.guid=live.party1.guid
NS.BindTiles("friendly",{"party1"},5)
friend=NS.UI.friendly.tiles[1]
resetTooltipOperations();friend:GetScript("OnEnter")(friend)
yes(tooltipContains("原生悬停"),"stable friendly units retain native hover wording")
eq(tooltipContains("GUID 直施尝试"),false,"native friendly tooltip does not advertise an NPC GUID cast route")
eq(friend:GetAttribute("*type1"),"target","stable friendly explicit left selection remains native")
local policyButtonHelp=table.concat(NS.UI.enemy.mouseover.tipLines(),"\n")
yes(policyButtonHelp:find("不切换当前目标",1,true),"global hover settings explain target preservation")
eq(policyButtonHelp:find("唯一性",1,true),nil,"production settings no longer require name uniqueness")

local policyPrint,policyProbe=NS.Print,NS.GUIDProbe
local notices,probeStops,probeOpens={},0,0
NS.Print=function(message) notices[#notices+1]=message end
NS.GUIDProbe={Stop=function() probeStops=probeStops+1 end,Command=function() probeOpens=probeOpens+1 end}
local frameCount=#frames
for _,argument in ipairs({"","open","integrated_macro","a","stop"}) do NS.HandleCommand("guid "..argument) end
eq(probeStops,5,"legacy GUID entry attempts stop the prior test instead of opening it")
eq(probeOpens,0,"no legacy GUID subcommand can open the old A/B experiment in production")
eq(#frames,frameCount,"legacy GUID entry does not create an A/B panel")
yes(notices[#notices]:find("已停用A/B切目标测试",1,true),"legacy command explains that the old switching experiment is stopped")
yes(notices[#notices]:find("GUID施法待验证，当前目标保持",1,true),"legacy command states the actual verification boundary")
NS.HandleCommand("help")
eq(notices[#notices]:find("打开两只同名怪",1,true),nil,"production help does not advertise the old A/B test")
NS.HoveredTile=enemy
NS.NearbyCast={count=1,KnownUniqueNPC=function() error("production diagnostics must not use name uniqueness") end,
    DiscoverActions=function() return {
        {actionKind="spell",keys={"Z"}},{actionKind="macro",keys={"W"}}
    } end}
NS.HandleCommand("debug enemyunit")
yes(notices[#notices]:find("GUID直施尝试",1,true),"unit diagnostics identify the experimental GUID route")
eq(notices[#notices]:find("唯一",1,true),nil,"production unit diagnostics do not report name uniqueness")
NS.HandleCommand("debug enemy")
yes(notices[#notices]:find("1个普通技能键",1,true),"production diagnostics count only supported ordinary spells")
yes(notices[#notices]:find("原宏保持，未接入",1,true),"production diagnostics do not imply the existing W macro was rebound")
NS.Print,NS.GUIDProbe=policyPrint,policyProbe
NS.CombatCast,NS.NearbyCast=policyCombatCast,policyNearby

-- Run passive UI callbacks, including delayed public marker readback. The
-- action engine is deliberately not simulated and no mark is applied here.
local oldDiagnostics,oldTimer=NS.Diagnostics,C_Timer
local oldExists,oldHarm,oldHelp,oldDead,oldRaidIndex=UnitExists,UnitCanAttack,UnitCanAssist,UnitIsDeadOrGhost,GetRaidTargetIndex
local oldParse,oldRaid,oldGroup,oldLeader,oldAssistant=SecureCmdOptionParse,IsInRaid,IsInGroup,UnitIsGroupLeader,UnitIsGroupAssistant
local oldSetRaid,oldTarget=SetRaidTarget,TargetUnit
local oldObservedGUID,oldObservedBinding=UnitGUID,GetBindingAction
local diagnosticTime,observedAPICalls=100,0
local diagnosticMutations=0
local oldTime=GetTime
GetTime=function() observedAPICalls=observedAPICalls+1;return diagnosticTime end
UnitGUID=function(...) observedAPICalls=observedAPICalls+1;return oldObservedGUID(...) end
GetBindingAction=function(...) observedAPICalls=observedAPICalls+1;return oldObservedBinding(...) end
local function readLive(unit,field,default)
    observedAPICalls=observedAPICalls+1
    local value=live[unit]
    if value and value[field]~=nil then return value[field] end
    return default
end
UnitExists=function(unit) observedAPICalls=observedAPICalls+1;return live[unit]~=nil end
UnitCanAttack=function(_,unit) observedAPICalls=observedAPICalls+1;return live[unit] and live[unit].side=="enemy" or false end
UnitCanAssist=function(_,unit) observedAPICalls=observedAPICalls+1;return live[unit] and live[unit].side=="friendly" or false end
UnitIsDeadOrGhost=function(unit) return readLive(unit,"dead",false) end
GetRaidTargetIndex=function(unit) return readLive(unit,"raidMarker",nil) end
IsInRaid=function() observedAPICalls=observedAPICalls+1;return false end
IsInGroup=function() observedAPICalls=observedAPICalls+1;return false end
UnitIsGroupLeader=function() observedAPICalls=observedAPICalls+1;return false end
UnitIsGroupAssistant=function() observedAPICalls=observedAPICalls+1;return false end
SecureCmdOptionParse=function(condition)
    observedAPICalls=observedAPICalls+1
    return condition=="[@nameplate1,exists,harm] yes" and "yes" or nil
end
SetRaidTarget=function() diagnosticMutations=diagnosticMutations+1 end
TargetUnit=function() diagnosticMutations=diagnosticMutations+1 end
live.nameplate1.dead=false;live.nameplate1.raidMarker=2
NS.BindTiles("enemy",{"nameplate1"},5)
enemy=NS.UI.enemy.tiles[1]
local logMenu,logMark=NS.MarkerMenu,NS.MarkerMenu.markers[8]
logMenu:Hide();logMenu:SetAttribute("unit","nameplate1");logMenu:SetAttribute("target-side","enemy")
logMenu:SetAttribute("source-guid",live.nameplate1.guid)
logMenu:SetAttribute("source-row",enemy:GetName())
logMark:SetAttribute("unit","nameplate1")
logMark:SetAttribute("source-guid",live.nameplate1.guid)
local logEnabled,uiEvents,timers=true,{},{}
NS.Diagnostics={Enabled=function() return logEnabled end,Record=function(kind,fields)
    for _,value in pairs(fields) do assert(type(value)~="table","UI diagnostic records must contain flat public fields") end
    uiEvents[#uiEvents+1]={kind=kind,fields=fields}
end}
C_Timer={After=function(delay,callback) timers[#timers+1]={delay=delay,callback=callback} end}
local function emitUI(frame,event,...)
    if frame:GetScript(event) then frame:GetScript(event)(frame,...) end
    if frame.hooks[event] then frame.hooks[event](frame,...) end
end
local function lastUI(kind)
    for i=#uiEvents,1,-1 do if uiEvents[i].kind==kind then return uiEvents[i].fields end end
end
emitUI(enemy,"OnEnter")
yes(lastUI("UI_TILE_ENTER"),"real normal-tile enter callback leaves a diagnostic")
eq(lastUI("UI_TILE_ENTER").expectedGUID,enemy.expectedGUID,"hover diagnostic captures the displayed GUID")
eq(lastUI("UI_TILE_ENTER").liveGUID,live.nameplate1.guid,"hover diagnostic separately reads the live GUID")
IsControlKeyDown=function() return true end
emitUI(enemy,"PreClick","RightButton",false)
eq(lastUI("UI_TILE_PRECLICK").rightType,"focus","right-click diagnostic reads native focus")
eq(lastUI("UI_TILE_PRECLICK").ctrlRightType,"click","diagnostic distinguishes Ctrl-right marker action")
eq(lastUI("UI_TILE_PRECLICK").focusGUID,"[nil]","diagnostic safely records absent focus")
eq(lastUI("UI_TILE_PRECLICK").ctrlDown,true,"diagnostic reads control modifier without mutation")
eq(lastUI("UI_TILE_PRECLICK").openMarkGuard,"yes","right-click diagnostic evaluates the same public unit-token guard")
eq(lastUI("UI_TILE_PRECLICK").menuShown,false,"right-click preflight records that the palette was initially hidden")
live.nameplate1.dead=true
emitUI(enemy,"PreClick","RightButton",false)
eq(lastUI("UI_TILE_PRECLICK").unitDead,true,"dead target state is visible in the actual right-click diagnostic")
live.nameplate1.dead=false
emitUI(enemy.markController,"OnClick","RightButton",false)
yes(lastUI("MARK_CONTROLLER_CLICK"),"actual controller callback distinguishes delegation arrival")
logMenu:Show()
eq(lastUI("MARK_MENU_OPEN").menuSourceGUID,live.nameplate1.guid,"real palette OnShow pins its source identity before logging")
eq(lastUI("MARK_MENU_OPEN").playerLeader,false,"public false permission observations are preserved")
emitUI(enemy,"PostClick","RightButton",false)
eq(lastUI("UI_TILE_POSTCLICK").menuShown,true,"row postflight observes the changed palette visibility")
emitUI(logMark,"PreClick","LeftButton",false)
eq(lastUI("MARKER_PRECLICK").requestedMarker,8,"marker preflight records the requested index")
eq(lastUI("MARKER_PRECLICK").markerBefore,2,"marker preflight reads the actual prior marker")
local targetBeforeLogging=UnitGUID("target")
emitUI(logMark,"PostClick","LeftButton",false)
eq(lastUI("MARKER_POSTCLICK").markerAfter,2,"marker postflight never pretends the requested mark was applied")
eq(lastUI("MARKER_POSTCLICK").identityMatches,true,"marker postflight requires the original public GUID")
eq(lastUI("MARKER_POSTCLICK").recipientProven,false,"readback never declares action or recipient success")
eq(#timers,2,"enabled marker postflight schedules only two bounded reads")
eq(timers[1].delay,.2,"first deferred read occurs at 0.2 seconds")
eq(timers[2].delay,.5,"second deferred read occurs at 0.5 seconds")
live.nameplate1.raidMarker=8 -- Model a public client update, not an executed action.
timers[1].callback()
eq(lastUI("MARKER_READBACK").markerAfter,8,"deferred callback reads the newly observed marker value")
eq(lastUI("MARKER_READBACK").stale,false,"unchanged public identity is accepted as a readback observation")
local loggingGUID=live.nameplate1.guid
live.nameplate1.guid="Creature-diagnostic-reused"
timers[2].callback()
eq(lastUI("MARKER_READBACK").stale,true,"reused token is explicitly stale at deferred readback")
eq(lastUI("MARKER_READBACK").readbackStatus,"stale","stale readback is distinguished from an unreadable identity")
eq(lastUI("MARKER_READBACK").recipientProven,false,"a marker on a replacement GUID cannot prove the requested operation")
eq(UnitGUID("target"),targetBeforeLogging,"all UI callbacks and timers leave the current target unchanged")
live.nameplate1.guid=loggingGUID
timers={};emitUI(logMark,"PreClick","LeftButton",false);emitUI(logMark,"PostClick","LeftButton",false)
local diagnosticSecret={}
local logSecretAPI=issecretvalue
issecretvalue=function(value) return value==diagnosticSecret or logSecretAPI(value) end
live.nameplate1.guid=diagnosticSecret
timers[1].callback()
eq(lastUI("MARKER_READBACK").liveGUID,"[restricted]","secret identity is recorded only as a restriction marker")
eq(lastUI("MARKER_READBACK").identityMatches,false,"secret identity never confirms the original marked individual")
live.nameplate1.guid=loggingGUID;issecretvalue=logSecretAPI
local beforeBlocks=#uiEvents
enemy.shield.hooks.OnEnter(enemy.shield)
enemy.shield.hooks.OnEnter(enemy.shield)
eq(#uiEvents,beforeBlocks+1,"identical shield observations are actually deduplicated")
enemy.shield.hooks.OnMouseUp(enemy.shield,"RightButton")
eq(lastUI("UI_SHIELD_BLOCKED").button,"RightButton","shield click is distinguishable from pointer entry")
local afterShieldClick=#uiEvents
enemy.shield.hooks.OnMouseUp(enemy.shield,"RightButton")
eq(#uiEvents,afterShieldClick,"rapid repeated blocked clicks do not flood the log")
logEnabled=false;observedAPICalls=0
local timerCount=#timers
enemy.hooks.PreClick(enemy,"RightButton",false)
logMark.hooks.PreClick(logMark,"LeftButton",false)
logMark.hooks.PostClick(logMark,"LeftButton",false)
logMenu.hooks.OnShow(logMenu)
timers[1].callback()
eq(observedAPICalls,0,"disabled UI logging performs no additional unit, permission or guard reads")
eq(#timers,timerCount,"disabled UI logging schedules no timers")
logEnabled=true;emitUI(logMark,"PreClick","LeftButton",false)
logEnabled=false;timerCount=#timers
emitUI(logMark,"PostClick","LeftButton",false)
eq(#timers,timerCount,"stopping logging between marker phases schedules no new timers")
NS.Diagnostics={Enabled=function() return true end,Record=function() error("logger failure") end}
eq(pcall(enemy.hooks.PreClick,enemy,"RightButton",false),true,"logger failure cannot interrupt native row action processing")
eq(pcall(logMark.hooks.PreClick,logMark,"LeftButton",false),true,"logger failure cannot interrupt native marker preflight")
eq(pcall(logMark.hooks.PostClick,logMark,"LeftButton",false),true,"logger failure cannot interrupt native marker postflight")
eq(enemy:GetScript("OnClick"),SecureActionButton_OnClick,"logging hooks never replace native row OnClick")
eq(logMark:GetScript("OnClick"),SecureActionButton_OnClick,"logging hooks never replace native marker OnClick")
eq(enemy.markController:GetAttribute("_onclick"),menuScript,"logging hooks never alter the secure opening snippet")
eq(diagnosticMutations,0,"all diagnostic callbacks and delayed reads perform no marking or target-selection call")
emitUI(enemy,"OnLeave")
NS.Diagnostics,C_Timer=oldDiagnostics,oldTimer
UnitExists,UnitCanAttack,UnitCanAssist,UnitIsDeadOrGhost,GetRaidTargetIndex=oldExists,oldHarm,oldHelp,oldDead,oldRaidIndex
SecureCmdOptionParse,IsInRaid,IsInGroup,UnitIsGroupLeader,UnitIsGroupAssistant=oldParse,oldRaid,oldGroup,oldLeader,oldAssistant
SetRaidTarget,TargetUnit,GetTime=oldSetRaid,oldTarget,oldTime
UnitGUID,GetBindingAction=oldObservedGUID,oldObservedBinding

-- Native-macro presentation consumes the read-only client identity result.
-- This model does not implement or prove the engine's mouseover assignment.
NS.NativeMacroOnly=true
NS.LegacyNameBridge=false -- Pure native-macro presentation remains independently testable.
local savedNativeStatus,savedMouseoverStatus,savedMouseoverSetter=NS.NativeMouseoverStatus,NS.MouseoverStatus,NS.SetMouseoverEnabled
local savedNativeCombat,savedNativeNearby,savedNativeFoci=NS.CombatCast,NS.NearbyCast,GetMouseFoci
local nativeStatus={confirmed=false,text="原生鼠标单位未确认；宏条件未命中；原宏可能回退当前目标。",
    details={expectedGUID=live.nameplate1.guid,unitGUID=live.nameplate1.guid,reason="missing_mouseover",conditionMatched=false}}
local nativeStatusCalls,nativeSettingCalls=0,0
NS.NativeMouseoverStatus=function(row)
    nativeStatusCalls=nativeStatusCalls+1
    eq(row,NS.HoveredTile,"native tooltip status reads the actual hovered row")
    return nativeStatus.confirmed,nativeStatus.text,nativeStatus.details
end
NS.SetMouseoverEnabled=function() nativeSettingCalls=nativeSettingCalls+1;error("native macro help must not change client settings") end
NS.MouseoverStatus=function() error("native macro help must not depend on automatic spell-cast settings") end
NS.CombatCast={Status=function() error("native macro UI must not read legacy preparation") end,
    ArmRow=function() error("native macro UI must not arm cast proxies") end}
NS.NearbyCast={Install=function() error("native macro UI must not install cast proxies") end,
    Enter=function() error("native macro UI must not enter the legacy cast bridge") end}
NS.UI=nil;NS.HoveredTile=nil;NS.DB.shown=true
GetMouseFoci=function() return {} end
NS.CreateUI()
NS.BindTiles("enemy",{"nameplate1"},5)
NS.BindTiles("friendly",{"party1"},5)
local nativeEnemy,nativeFriend=NS.UI.enemy.tiles[1],NS.UI.friendly.tiles[1]
local nativeLeftAction,nativeMarkAction=nativeEnemy:GetAttribute("*macrotext1"),nativeEnemy:GetAttribute("*type2")
local nativeMarkController=nativeEnemy:GetAttribute("ctrl-clickbutton2")
eq(nativeEnemy.template,"SecureActionButtonTemplate,BackdropTemplate","native macro mode retains the existing target-row template")
eq(nativeEnemy:GetScript("OnClick"),SecureActionButton_OnClick,"native macro mode retains original XML OnClick")
eq(nativeEnemy:GetAttribute("unit"),"nameplate1","native macro mode retains the actual unit attribute")
eq(nativeEnemy:GetAttribute("*type1"),"macro","native macro mode retains explicit nameplate selection")
yes(nativeLeftAction and nativeLeftAction:find("/targetexact ",1,true),"native macro mode retains the existing explicit left-click command")
eq(nativeMarkAction,"focus","native macro mode retains native right-click focus")
eq(nativeMarkController,nativeEnemy.markController,"native macro mode retains the original mark controller")
eq(nativeFriend:GetAttribute("*type1"),"target","native macro mode retains friendly target selection")
resetTooltipOperations();nativeEnemy:GetScript("OnEnter")(nativeEnemy)
eq(nativeEnemy.unitTooltipReady,true,"a successful native unit tooltip remains available")
yes(tooltipContains("原生鼠标单位未确认"),"tooltip success does not falsely confirm native mouseover identity")
yes(tooltipContains("宏条件未命中"),"native row tooltip displays the actual condition result")
yes(tooltipContains("原 @mouseover 宏的原按键"),"native row tooltip keeps the original macro and key")
eq(tooltipContains("GUID"),false,"native row tooltip has no GUID-casting claim")
eq(tooltipContains("已准备"),false,"native row tooltip has no legacy prepared-key status")
eq(tooltipContains("原普通伤害技能键"),false,"native row tooltip does not promise automatic ordinary spells")
eq(hasTooltipOperation("SetText"),false,"native macro help preserves successful unit-tooltip payload")
eq(GameTooltip.unit,"nameplate1","native tooltip still uses the displayed alias")
nativeStatus.confirmed=true;nativeStatus.text="原生鼠标单位与此格一致；宏条件已命中。"
nativeStatus.details={expectedGUID=nativeEnemy.expectedGUID,unitGUID=nativeEnemy.expectedGUID,
    mouseoverGUID=nativeEnemy.expectedGUID,identityMatches=true,conditionMatched=true,condition="harm",reason="confirmed"}
resetTooltipOperations();NS.RefreshTiles()
yes(tooltipContains("原生鼠标单位与此格一致"),"hover refresh displays a newly confirmed identity")
yes(tooltipContains("宏条件已命中"),"hover refresh displays the native macro condition match")
yes(hasTooltipOperation("SetUnit"),"identity status changes refresh the hovered unit tooltip")
nativeStatus.details.mouseoverGUID="Creature-other-native-unit"
resetTooltipOperations();NS.RefreshTiles()
yes(hasTooltipOperation("SetUnit"),"identity detail changes refresh even when the status message is unchanged")
nativeStatus.confirmed=false;nativeStatus.text="原生鼠标单位不对应此格；宏条件未命中；原宏可能回退当前目标。"
nativeStatus.details.identityMatches=false;nativeStatus.details.conditionMatched=false
resetTooltipOperations();NS.RefreshTiles()
yes(tooltipContains("原生鼠标单位不对应此格"),"hover refresh removes stale native identity confirmation")
yes(tooltipContains("原宏可能回退当前目标"),"unconfirmed native status discloses the original macro fallback")

NS.RefreshControls();NS.RefreshTiles()
for _,side in ipairs({"friendly","enemy"}) do
    local macroButton=NS.UI[side].mouseover
    eq(macroButton.label:GetText(),"宏","native macro control displays the help label on both panels")
    eq(macroButton:IsEnabled(),true,"native macro help remains available without native spell-setting support")
    eq(macroButton.active,false,"macro help is not displayed as an enabled spell-cast toggle")
    resetTooltipOperations();macroButton:GetScript("OnClick")(macroButton)
    eq(GameTooltip.owner,macroButton,"clicking macro control displays its own help")
    yes(tooltipContains("/cast [@mouseover,nodead,harm] 恐惧术; 恐惧术;"),"macro help shows the requested unchanged macro syntax")
    yes(tooltipContains("换成角色已学且可用的技能"),"the macro example does not claim the character knows Fear")
    yes(tooltipContains("原宏和当前目标保持"),"macro help explains original-macro and current-target preservation")
    eq(tooltipContains("GUID"),false,"native macro help contains no GUID-cast route")
    eq(tooltipContains("点击开启"),false,"native macro help does not offer an automatic spell-setting toggle")
end
eq(nativeSettingCalls,0,"native macro help never calls the mouseover-setting setter")
GetMouseFoci=function() return {nativeEnemy} end
NS.BindTiles("enemy",{"nameplate1"},5)
eq(NS.HoveredTile,nativeEnemy,"native mode rebind still restores actual tile hover")
eq(nativeEnemy:GetAttribute("*macrotext1"),nativeLeftAction,"native status refresh leaves left-click selection unchanged")
eq(nativeEnemy:GetAttribute("*type2"),nativeMarkAction,"native status refresh leaves right-click type unchanged")
eq(nativeEnemy:GetAttribute("ctrl-clickbutton2"),nativeMarkController,"native status refresh leaves marker delegation unchanged")
local victimButton=nativeEnemy.enemyTargetButton
yes(victimButton~=nil,"enemy target card creates a separate native unit button")
eq(victimButton:GetAttribute("unit"),"nameplate1target","target card binds a fixed relationship token")
eq(victimButton:GetScript("OnClick"),builtinUnitClick,"target card retains the template's native click callback")
eq(victimButton:GetAttribute("*macrotext1"),nil,"target card never inherits the enemy's name-target macro")
eq(victimButton.driver.visibility,"[@nameplate1target,help,nodead] show; hide","native state driver gates friendly living targets")
yes(victimButton.shield:GetFrameLevel()>victimButton:GetFrameLevel(),"independent target shield protects the external target card")
eq(victimButton:GetWidth(),76,"target interaction matches the enemy width")
eq(victimButton:GetHeight(),26,"target interaction covers the independent rectangle")
eq(victimButton.point[1],"TOPLEFT","target interaction anchors at its top left")
eq(victimButton.point[2],nativeEnemy,"target interaction stays associated with its owning enemy")
eq(victimButton.point[3],"BOTTOMLEFT","target interaction sits below its enemy")
eq(victimButton.point[4],0,"target interaction has no horizontal inset")
eq(victimButton.point[5],-1,"target interaction leaves a one pixel gap")
eq(nativeEnemy.enemyTargetDisplay~=victimButton,true,"target information has a separate display from its conditional input button")

local nativeSecret,priorNativeSecret={},issecretvalue
issecretvalue=function(value) return value==nativeSecret end
nativeStatus.confirmed,nativeStatus.text=nativeSecret,nativeSecret
nativeStatus.details={expectedGUID=nativeSecret,unitGUID=nativeSecret,mouseoverGUID=nativeSecret,
    condition=nativeSecret,reason=nativeSecret,identityMatches=nativeSecret,conditionMatched=nativeSecret}
resetTooltipOperations()
eq(pcall(nativeEnemy:GetScript("OnEnter"),nativeEnemy),true,"secret native status values cannot crash the tooltip")
yes(tooltipContains("原生鼠标单位未确认"),"unreadable native status falls back to an unconfirmed result")
issecretvalue=priorNativeSecret
NS.NativeMouseoverStatus=nil
resetTooltipOperations();nativeEnemy:GetScript("OnEnter")(nativeEnemy)
yes(tooltipContains("原生鼠标单位未确认"),"an unavailable native identity helper never advertises a usable target")
yes(nativeStatusCalls>0,"native UI exercises the read-only status helper")
NS.NativeMouseoverStatus,NS.MouseoverStatus,NS.SetMouseoverEnabled=savedNativeStatus,savedMouseoverStatus,savedMouseoverSetter
NS.CombatCast,NS.NearbyCast,GetMouseFoci=savedNativeCombat,savedNativeNearby,savedNativeFoci

-- Enemy target cards follow live name/class/health without changing the enemy's
-- secure unit, dimensions or current-target highlight. Rendering remains visible
-- when the friendly-only native interaction is hidden.
local savedEnemyTargetReader=NS.ReadEnemyTarget
local enemyTargetState={state="known",name="队友的完整名字",player=true,className="圣骑士",
    color={r=.96,g=.55,b=.73},health=.75,healthCurrent=75,healthMax=100,healthAvailable=true,dead=false}
NS.ReadEnemyTarget=function(unit,guid)
    eq(unit,nativeEnemy.unit,"enemy-target display reads the tile owner")
    eq(guid,nativeEnemy.expectedGUID,"enemy-target display uses the bound owner identity")
    return enemyTargetState
end
NS.BindTiles("enemy",{"nameplate1"},5)
local ownerUnit=nativeEnemy:GetAttribute("unit")
local selectedBefore=live.nameplate1.target
NS.RefreshTiles()
local victimDisplay=nativeEnemy.enemyTargetDisplay
eq(victimDisplay:IsVisible(),true,"readable target has a visible independent card")
eq(victimDisplay.nameText:GetText(),"队友的完整名字","target card displays its name without an inline arrow")
eq(victimDisplay.classText:GetText(),"圣骑士","target card displays the target's own class")
eq(victimDisplay.nameText.color[1],.96,"target name uses the target's class color")
eq(victimDisplay.classText.color[1],.96,"target profession uses the target's class color")
eq(victimDisplay.healthText:GetText(),"75%","target card presents live health percentage")
eq(victimDisplay.health.value,75,"target card health fill receives current health")
eq(victimDisplay.health.maximum,100,"target card health fill receives maximum health")
eq(nativeEnemy.classText:GetText(),"怪物","enemy class line retains the enemy's own identity")
eq(nativeEnemy:GetWidth(),76,"additional target card never widens the enemy tile")
eq(nativeEnemy:GetHeight(),58,"additional target card never shrinks the enemy tile")
victimButton:Hide()
NS.RefreshTiles()
eq(victimDisplay:IsVisible(),true,"hidden friendly interaction does not hide known target information")
eq(victimDisplay.nameText:GetText(),"队友的完整名字","hidden interaction does not clear target name")
resetTooltipOperations();nativeEnemy:GetScript("OnEnter")(nativeEnemy)
yes(tooltipContains("目标：队友的完整名字"),"tooltip exposes the complete target name")
combat=true
enemyTargetState={state="known",name="宠物",player=false,className="非玩家",color={r=.82,g=.85,b=.9},
    health=.4,healthCurrent=80,healthMax=200,healthAvailable=true,dead=false}
resetTooltipOperations();NS.RefreshTiles()
eq(victimDisplay.nameText:GetText(),"宠物","target change refreshes its independent name during combat")
eq(victimDisplay.classText:GetText(),"非玩家","target change replaces the previous player's class")
eq(victimDisplay.healthText:GetText(),"40%","target change replaces the previous target's health percentage")
eq(victimDisplay.health.value,80,"target change refreshes the current health amount")
eq(victimDisplay.health.maximum,200,"target change refreshes a different health maximum")
eq(victimDisplay.nameText.color[1],.82,"nonplayer target clears the previous player's class color")
yes(tooltipContains("目标：宠物"),"hovered tooltip updates when enemy target changes")
eq(nativeEnemy:GetAttribute("unit"),ownerUnit,"display never rebinds secure owner")
eq(nativeEnemy.selected,selectedBefore==true,"enemy target display preserves current-target highlight")
eq(nativeEnemy.classText:GetText(),"怪物","target change never replaces the enemy's class line")
enemyTargetState.health,enemyTargetState.healthCurrent=0,0
NS.RefreshTiles()
eq(victimDisplay.health.value,0,"confirmed zero target health is retained")
eq(victimDisplay.healthText:GetText(),"0%","confirmed zero living health is not treated as unknown")
enemyTargetState.healthAvailable=false
enemyTargetState.health,enemyTargetState.healthCurrent,enemyTargetState.healthMax=nil,nil,nil
NS.RefreshTiles()
eq(victimDisplay.nameText:GetText(),"宠物","unavailable health retains the independently readable name")
eq(victimDisplay.classText:GetText(),"非玩家","unavailable health retains independently readable class")
eq(victimDisplay.healthText:GetText(),"—","unavailable health does not reuse the previous percentage")
enemyTargetState.dead=true
NS.RefreshTiles()
eq(victimDisplay.healthText:GetText(),"死亡","confirmed dead target displays death state")
enemyTargetState={state="absent"}
resetTooltipOperations();NS.RefreshTiles()
eq(victimDisplay:IsVisible(),true,"present enemy retains a visible target placeholder")
eq(victimDisplay.nameText:GetText(),"目标 —","missing target clears the previous target name")
eq(victimDisplay.classText:GetText(),"","missing target clears previous class")
eq(victimDisplay.healthText:GetText(),"—","missing target clears previous health and death state")
yes(tooltipContains("目标：暂未显示"),"missing target tooltip does not assert no target exists")
enemyTargetState={state="unavailable"}
resetTooltipOperations();NS.RefreshTiles()
eq(victimDisplay.nameText:GetText(),"目标 —","restricted target does not retain a stale name")
eq(victimDisplay.classText:GetText(),"","restricted target does not retain a stale class")
eq(victimDisplay.healthText:GetText(),"—","restricted target does not retain stale health")
local ownerGUID=live.nameplate1.guid
live.nameplate1.guid="Creature-ReusedForTargetDisplay"
NS.RefreshTiles()
eq(nativeEnemy.classText:GetText(),"","reused tile owner clears its own class label")
eq(victimDisplay:IsShown(),false,"reused tile owner hides its external target card")
eq(victimDisplay.nameText:GetText(),"","reused tile owner clears target name")
eq(victimDisplay.classText:GetText(),"","reused tile owner clears target class")
eq(victimDisplay.healthText:GetText(),"","reused tile owner clears target health text")
eq(nativeEnemy.enemyTarget,nil,"reused owner clears target data")
combat=false
live.nameplate1.guid=ownerGUID
enemyTargetState={state="known",name="恢复的队友",player=true,className="牧师",color={r=1,g=1,b=1},
    health=.6,healthCurrent=60,healthMax=100,healthAvailable=true,dead=false}
NS.BindTiles("enemy",{"nameplate1"},5)
NS.RefreshTiles()
eq(victimDisplay:IsVisible(),true,"revalidated enemy restores its target card")
eq(victimDisplay.nameText:GetText(),"恢复的队友","revalidated enemy renders only its newly read target")
eq(victimDisplay.healthText:GetText(),"60%","revalidated enemy renders fresh target health")
NS.BindTiles("enemy",{},5)
NS.RefreshTiles()
eq(victimDisplay:IsShown(),false,"empty enemy slot hides its independent target card")
eq(victimDisplay.nameText:GetText(),"","empty enemy slot leaves no target name")
eq(victimDisplay.classText:GetText(),"","empty enemy slot leaves no target class")
eq(victimDisplay.healthText:GetText(),"","empty enemy slot leaves no target health text")
NS.ReadEnemyTarget=savedEnemyTargetReader

-- Production authorizes the ordinary-spell bridge for both target panels. Use
-- spies at this UI/Main boundary; the bridge's action/ownership tests live in
-- the bridge module's regression test and no spell or target action is run here.
;(function()
    local savedUI,savedCollect,savedBindings=NS.UI,NS.Collect,NS.Bindings
    local savedNearby,savedCombat,savedSetter=NS.NearbyCast,NS.CombatCast,NS.SetMouseoverEnabled
    local savedFoci,savedPolicy=GetMouseFoci,NS.LegacyNameBridge
    local savedTargetModule,savedBridgeReader,savedTargetReader=NS.EnemyTargetHover,NS.ReadBridgeTarget,NS.ReadEnemyTarget
    local installed,entered={},{}
    local leaves,reconciles,foreignCalls,settingCalls=0,0,0,0
    local bridge={count=0}
    bridge.Enter=function(row)
        entered[#entered+1]=row
        if not row then foreignCalls=foreignCalls+1;return false,0 end
        bridge.row=row
        bridge.count=NS.DB.legacyNameBridgeEnabled and not combat and 2 or 0
        return bridge.count>0,bridge.count
    end
    bridge.Install=function(row)
        installed[#installed+1]=row
        row:HookScript("OnEnter",function(self) bridge.Enter(self) end)
        return true
    end
    bridge.Leave=function() leaves=leaves+1;bridge.row=nil;bridge.count=0 end
    bridge.Reconcile=function() reconciles=reconciles+1;return false,0 end
    bridge.Status=function(row)
        local reason=not NS.DB.legacyNameBridgeEnabled and "disabled"
            or combat and "out_of_combat_only" or "prepared"
        return {legacyName=true,prepared=reason=="prepared",count=reason=="prepared" and 2 or 0,
            reason=reason,unit=row and row.unit,guid=row and row.expectedGUID}
    end
    NS.NearbyCast=bridge
    NS.CombatCast={Status=function() foreignCalls=foreignCalls+1 end,
        Install=function() foreignCalls=foreignCalls+1 end,
        ArmRow=function() foreignCalls=foreignCalls+1 end}
    NS.SetMouseoverEnabled=function() settingCalls=settingCalls+1 end
    NS.NativeMacroOnly,NS.PreserveCastTarget,NS.LegacyNameBridge=true,true,true
    assert(loadfile(root.."EnemyTargetHover.lua"))("MyForeverTargets",NS)
    NS.DB.legacyNameBridgeEnabled=true
    NS.DB.friendlyTab,NS.DB.nearbyLimit,NS.DB.enemyLimit="nearby",5,5
    NS.DB.shown=true
    NS.UI,NS.Bindings,NS.HoveredTile,NS.HoveredEnemyTarget=nil,{},nil,nil
    live.nameplate90=data("nameplate90","Player-FriendlyBridge","附近同伴","friendly",true)
    NS.Collect=function(side) return {side=="friendly" and "nameplate90" or "nameplate1"},1 end
    GetMouseFoci=function() return {} end
    NS.CreateUI()
    NS.RequestRefresh()
    for _,side in ipairs({"friendly","enemy"}) do
        for _,row in ipairs(NS.UI[side].tiles) do
            local found=false
            for _,candidate in ipairs(installed) do if candidate==row then found=true;break end end
            yes(found,"authorized bridge installs each "..side.." main tile")
        end
    end
    local friendlyRow,enemyRow=NS.UI.friendly.tiles[1],NS.UI.enemy.tiles[1]
    local friendlyButton,enemyButton=NS.UI.friendly.mouseover,NS.UI.enemy.mouseover
    local friendlyUnit,enemyUnit=friendlyRow:GetAttribute("unit"),enemyRow:GetAttribute("unit")
    local friendlyType,enemyType=friendlyRow:GetAttribute("*type1"),enemyRow:GetAttribute("*type1")
    local friendlyMark,enemyMark=friendlyRow:GetAttribute("ctrl-clickbutton2"),enemyRow:GetAttribute("ctrl-clickbutton2")
    eq(friendlyButton.label:GetText(),"施法","friendly panel labels its separate ordinary-spell toggle")
    yes(friendlyButton.tipTitle:find("普通技能",1,true),"friendly toggle describes ordinary skills")
    eq(friendlyButton.active,true,"authorized friendly bridge starts visibly enabled")
    eq(enemyButton.label:GetText(),"施法","enemy panel also exposes authorized ordinary skills")
    eq(enemyButton.active,true,"both panels show the same enabled bridge setting")
    for _,side in ipairs({"friendly","enemy"}) do
        resetTooltipOperations();NS.UI[side].ShowHelp()
        yes(tooltipContains("临时选中"),side.." header help discloses temporary target selection")
        eq(tooltipContains("GUID直施"),false,side.." header help does not advertise the disabled GUID route")
    end

    resetTooltipOperations();friendlyRow:GetScript("OnEnter")(friendlyRow)
    friendlyRow.hooks.OnEnter(friendlyRow)
    eq(entered[#entered],friendlyRow,"real friendly row entry reaches the ordinary-spell bridge")
    yes(tooltipContains("已准备 2 个普通技能键"),"friendly row shows prepared ordinary skill keys")
    yes(tooltipContains("短暂"),"friendly row discloses temporary target selection")
    yes(tooltipContains("恢复原目标"),"friendly row explains target restoration")
    yes(tooltipContains("脱战"),"friendly row states the combat restriction")
    eq(tooltipContains("GUID直施"),false,"friendly row never advertises the discarded GUID route")
    eq(tooltipContains("插件不改变当前目标"),false,"friendly bridge does not retain contradictory native-only copy")

    local beforeEntries=#entered
    GetMouseFoci=function() return {friendlyRow} end
    NS.BindTiles("friendly",{"nameplate90"},5)
    yes(#entered>beforeEntries,"friendly rebind restores its hovered bridge without requiring pointer movement")
    beforeEntries=#entered
    GetMouseFoci=function() return {enemyRow} end
    NS.BindTiles("enemy",{"nameplate1"},5)
    yes(#entered>beforeEntries,"enemy rebind restores its hovered ordinary-spell bridge")
    eq(entered[#entered],enemyRow,"enemy bridge receives its own row after rebind")
    GetMouseFoci=function() return {} end
    NS.HoveredTile=nil

    resetTooltipOperations();friendlyButton:GetScript("OnEnter")(friendlyButton)
    yes(tooltipContains("普通"),"friendly toggle describes ordinary skills")
    yes(tooltipContains("脱战"),"friendly toggle explains out-of-combat scope")
    yes(tooltipContains("临时选中") or tooltipContains("短暂"),"friendly toggle explicitly describes its target change")
    yes(tooltipContains("原来无目标则恢复为空"),"friendly toggle explains empty-target restoration")
    yes(tooltipContains("已有宏、物品"),"friendly toggle explains excluded action types")
    local previousLeaves,previousReconciles=leaves,reconciles
    friendlyButton:GetScript("OnClick")(friendlyButton)
    eq(NS.DB.legacyNameBridgeEnabled,false,"friendly toggle switches the shared ordinary-spell preference off")
    eq(friendlyButton.active,false,"disabled friendly bridge updates button presentation")
    eq(enemyButton.active,false,"shared disabled setting is reflected on the enemy button")
    yes(leaves>previousLeaves,"disabling friendly bridge immediately releases its own overrides")
    yes(reconciles>previousReconciles,"friendly setting reconciles actual hover after refresh")
    resetTooltipOperations();friendlyRow:GetScript("OnEnter")(friendlyRow)
    yes(tooltipContains("已关闭"),"disabled row no longer claims prepared ordinary keys")
    NS.HoveredTile=nil
    friendlyButton:GetScript("OnClick")(friendlyButton)
    eq(NS.DB.legacyNameBridgeEnabled,true,"friendly toggle can re-enable the shared bridge")
    eq(friendlyButton.active,true,"re-enabled friendly bridge updates button presentation")
    eq(enemyButton.active,true,"re-enabled shared setting updates the enemy button")
    NS.HandleCommand("legacycast off")
    eq(NS.DB.legacyNameBridgeEnabled,false,"legacycast off shares the ordinary-spell setting path")
    NS.HandleCommand("legacycast on")
    eq(NS.DB.legacyNameBridgeEnabled,true,"legacycast on shares the ordinary-spell setting path")

    previousLeaves,previousReconciles=leaves,reconciles
    resetTooltipOperations();enemyButton:GetScript("OnClick")(enemyButton)
    eq(NS.DB.legacyNameBridgeEnabled,false,"enemy control uses the same ordinary-spell preference")
    yes(leaves>previousLeaves,"enemy control releases the bridge's own bindings")
    yes(reconciles>previousReconciles,"enemy control reconciles actual hover after refresh")
    eq(friendlyButton.active,false,"enemy control keeps the friendly button in sync")
    enemyButton:GetScript("OnClick")(enemyButton)
    eq(NS.DB.legacyNameBridgeEnabled,true,"enemy control can re-enable the shared bridge")
    resetTooltipOperations();enemyRow:GetScript("OnEnter")(enemyRow)
    enemyRow.hooks.OnEnter(enemyRow)
    eq(entered[#entered],enemyRow,"enemy row entry reaches the authorized ordinary-spell bridge")
    yes(tooltipContains("普通技能键"),"enemy tooltip describes ordinary skill keys")
    yes(tooltipContains("短暂"),"enemy tooltip discloses temporary selection")
    yes(tooltipContains("恢复原目标"),"enemy tooltip describes target restoration")
    eq(tooltipContains("GUID直施"),false,"enemy ordinary-spell tooltip does not revive GUID casting")
    NS.HoveredTile=nil
    for _,limit in ipairs({5,10,20}) do
        NS.ApplySetting("nearbyLimit",limit)
        NS.ApplySetting("enemyLimit",limit)
        eq(NS.UI.friendly.limit,limit,"friendly bridge leaves capacity "..limit.." reachable")
        eq(NS.UI.enemy.limit,limit,"friendly bridge leaves enemy capacity "..limit.." reachable")
    end
    local function focusPhase(row,event,button,combatCondition)
        for _,entry in ipairs(wrapped) do
            if entry.button==row and entry.script==event then modelSecure(entry.pre,row,row,combatCondition) end
        end
        if row.hooks[event] then row.hooks[event](row,button or "RightButton",false) end
    end
    local function checkFocusClick(row,snapshot)
        local oldTarget,oldFocus,oldCtrl,oldExists=live.target,live.focus,IsControlKeyDown,UnitExists
        local oldDiagnostics,oldTimer,oldUnique=NS.Diagnostics,C_Timer,bridge.KnownUniqueNPC
        local oldEnabled=NS.DB.legacyNameBridgeEnabled
        local unique,uniqueCalls,events,callbacks=true,0,{},{}
        local uniqueReason,oldPrint,focusNotices=nil,NS.Print,{}
        NS.Print=function(message) focusNotices[#focusNotices+1]=message end
        bridge.KnownUniqueNPC=function(candidate,source)
            uniqueCalls=uniqueCalls+1
            eq(candidate,snapshot,"NPC focus uniqueness uses the freshly validated snapshot")
            eq(source,row,"NPC focus uniqueness receives the exact owner row or controlled child")
            return unique,uniqueReason
        end
        NS.Diagnostics={Enabled=function() return true end,Record=function(kind,fields)
            events[#events+1]={kind=kind,fields=fields}
        end}
        C_Timer={After=function(delay,callback)
            eq(delay,.1,"focus readback waits briefly for the native event")
            callbacks[#callbacks+1]=callback
        end}
        local function last(kind)
            for i=#events,1,-1 do if events[i].kind==kind then return events[i].fields end end
        end
        IsControlKeyDown=function() return false end
        UnitExists=function(unit) return live[unit]~=nil end
        NS.DB.legacyNameBridgeEnabled=false
        live.target={guid="Player-ExistingSelection"};live.focus=nil
        local beforeType,beforeMacro=row:GetAttribute("*type2"),row:GetAttribute("*macrotext2")
        local beforeLeft,beforeLeftMacro=row:GetAttribute("*type1"),row:GetAttribute("*macrotext1")
        focusPhase(row,"PreClick")
        local command=row:GetAttribute("*macrotext2")
        eq(command,table.concat({"/stopmacro [combat]","/cleartarget [nocombat]",
            "/targetexact [nocombat] "..snapshot.targetName,"/focus [@target,exists]","/targetlasttarget"},"\n"),
            "right focus clears before exact-name lookup and restores an existing target")
        eq(row:GetAttribute("*type2"),"macro","only this right click uses the focus compatibility macro")
        eq(last("FOCUS_CLICK_PRE").path,"name_restore_target","focus path is independent of the ordinary-spell switch")
        eq(last("FOCUS_CLICK_PRE").row,row:GetName(),"focus diagnostics identify the actual clicked frame")
        eq(last("FOCUS_CLICK_PRE").expectedGUID,row.expectedGUID,"focus diagnostics pin the clicked identity")
        eq(command:find("/clearfocus",1,true),nil,"repeat-click cancellation is absent")
        eq(row:GetScript("OnClick"),row.nativeClick,"focus compatibility preserves the native OnClick")
        combat=true;focusPhase(row,"PostClick");combat=false
        eq(row:GetAttribute("*type2"),beforeType,"secure post restores native focus even if combat began")
        eq(row:GetAttribute("*macrotext2"),beforeMacro,"secure post removes its temporary focus command")
        eq(last("FOCUS_CLICK_POST").focusMatchesExpected,false,"immediate post records the actual unconfirmed focus")
        live.focus={guid=row.expectedGUID};callbacks[#callbacks]()
        eq(last("FOCUS_CLICK_READBACK").focusMatchesExpected,true,"delayed readback can observe the later native focus")
        eq(last("FOCUS_CLICK_READBACK").targetRestored,true,"readback separately verifies original target preservation")
        eq(last("FOCUS_CLICK_READBACK").beforeTargetGUID,"Player-ExistingSelection","post retains the pre-click target snapshot")
        focusPhase(row,"PreClick")
        eq(row:GetAttribute("*macrotext2"),"/stopmacro","clicking the existing focus keeps it instead of cancelling")
        eq(last("FOCUS_CLICK_PRE").path,"keep_focus","existing focus is explicitly logged as retained")
        focusPhase(row,"PostClick")
        live.focus=nil;live.target=nil
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").path,"name_restore_empty","originally empty target has its own restoration path")
        yes(row:GetAttribute("*macrotext2"):match("\n/cleartarget$"),"empty original target is restored empty")
        focusPhase(row,"PostClick")
        live.target={guid=row.expectedGUID};unique=false;uniqueCalls=0
        focusPhase(row,"PreClick")
        eq(row:GetAttribute("*macrotext2"),"/stopmacro [combat]\n/focus [@target,exists]","already selected identity avoids any name lookup")
        eq(uniqueCalls,0,"already selected NPC identity does not require name uniqueness")
        focusPhase(row,"PostClick")
        live.target=nil
        if snapshot.player==false then
            focusPhase(row,"PreClick")
            eq(last("FOCUS_CLICK_PRE").reason,"not_unique","duplicate or unknown NPC identity is refused")
            eq(row:GetAttribute("*macrotext2"),"/stopmacro","refused NPC cannot run an inherited focus action")
            focusPhase(row,"PostClick")
            uniqueReason="duplicate_name"
            focusPhase(row,"PreClick")
            eq(last("FOCUS_CLICK_PRE").reason,"duplicate_name","real duplicates retain their specific diagnostic reason")
            yes(focusNotices[#focusNotices]:find("同名怪物",1,true),"duplicate focus rejection explains how to choose the exact creature")
            local noticeCount=#focusNotices
            focusPhase(row,"PostClick");focusPhase(row,"PreClick")
            eq(#focusNotices,noticeCount,"repeated refused clicks do not flood chat")
            focusPhase(row,"PostClick")
            uniqueReason="identity_unreadable"
            focusPhase(row,"PreClick")
            eq(last("FOCUS_CLICK_PRE").reason,"identity_unreadable","unreadable identities are not mislabeled as duplicate names")
            yes(focusNotices[#focusNotices]:find("信息暂不完整",1,true),"unreadable identities receive a distinct explanation")
            eq(row:GetAttribute("*macrotext2"),"/stopmacro","detailed diagnostics never bypass a rejected identity")
            focusPhase(row,"PostClick")
        end
        unique=true;uniqueReason=nil
        local name=snapshot.targetName;snapshot.targetName="坏名字\n/focus player"
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"invalid_name","macro injection in a target name is rejected")
        eq(row:GetAttribute("*macrotext2"),"/stopmacro","invalid names fail closed")
        focusPhase(row,"PostClick");snapshot.targetName=name
        UnitExists=function(unit) if unit=="target" then return nil end return live[unit]~=nil end
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"target_state_unreadable","unknown original target existence is refused")
        focusPhase(row,"PostClick")
        UnitExists=function(unit) return live[unit]~=nil end
        local restricted,secretReader={},issecretvalue
        issecretvalue=function(value) return rawequal(value,restricted) or secretReader(value) end
        live.target={guid=restricted};focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"target_state_unreadable","secret existing target GUID cannot be restored by guess")
        focusPhase(row,"PostClick");issecretvalue=secretReader;live.target=nil
        local secretExpected,originalExpected={},row.expectedGUID
        local secretString=setmetatable(secretExpected,{__tostring=function() error("secret must never be formatted") end})
        issecretvalue=function(value) return rawequal(value,secretString) or secretReader(value) end
        row.expectedGUID=secretString
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"identity_changed","restricted expected identity is refused without formatting it")
        eq(row:GetAttribute("*macrotext2"),"/stopmacro","restricted identity cannot run the native focus fallback")
        focusPhase(row,"PostClick");row.expectedGUID=originalExpected;issecretvalue=secretReader
        local identity=live[row.unit].guid;live[row.unit].guid="Reused-Unit"
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"identity_changed","reused alias cannot prepare name selection")
        focusPhase(row,"PostClick");live[row.unit].guid=identity
        IsControlKeyDown=function() return true end
        focusPhase(row,"PreClick")
        eq(row:GetAttribute("*type2"),beforeType,"Ctrl-right keeps native marking priority")
        eq(last("FOCUS_CLICK_PRE").path,"marker","Ctrl-right is logged as marking rather than focus")
        focusPhase(row,"PostClick");IsControlKeyDown=function() return false end
        combat=true;focusPhase(row,"PreClick")
        eq(row:GetAttribute("*type2"),beforeType,"combat does not install a temporary name macro")
        eq(last("FOCUS_CLICK_PRE").reason,"out_of_combat_only","combat compatibility refusal is explicit")
        focusPhase(row,"PostClick");combat=false
        focusPhase(row,"PreClick")
        combat=true;focusPhase(row,"PreClick")
        eq(row:GetAttribute("*type2"),beforeType,"secure next-preflight removes an interrupted macro during combat")
        combat=false;focusPhase(row,"PostClick")
        focusPhase(row,"PreClick")
        row:SetAttribute("*type2","focus");row:SetAttribute("*macrotext2","new-owner")
        focusPhase(row,"PostClick")
        eq(row:GetAttribute("*macrotext2"),"new-owner","cleanup never overwrites a newer action owner's attributes")
        row:SetAttribute("*macrotext2",beforeMacro)
        local oldScaleProbe=NS.NativeScaleProbe
        local probeState={active=true,restoring=false}
        local probeStops=0
        NS.NativeScaleProbe={Status=function() return probeState end,Stop=function(reason)
            eq(reason,"focus_click","actual tile right-click stops the isolated scale probe before focus preparation")
            probeStops=probeStops+1
            if probeState.restoring then return false end
            probeState.active=false;return true
        end}
        focusPhase(row,"PreClick")
        eq(probeStops,1,"tile focus path releases native geometry without requiring a slash command")
        eq(last("FOCUS_CLICK_PRE").path,"name_restore_empty","normal focus preparation resumes after geometry restoration")
        focusPhase(row,"PostClick")
        probeState.restoring=true
        focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"native_scale_restore_pending","unfinished geometry restoration blocks a new compatibility action")
        eq(row:GetAttribute("*macrotext2"),"/stopmacro","pending restore cannot begin a target-changing name macro")
        focusPhase(row,"PostClick")
        combat=true;focusPhase(row,"PreClick")
        eq(last("FOCUS_CLICK_PRE").reason,"out_of_combat_only","combat observation never configures an insecure restore blocker")
        eq(row:GetAttribute("*type2"),beforeType,"probe cleanup during combat does not write protected focus attributes")
        focusPhase(row,"PostClick");combat=false
        NS.NativeScaleProbe=oldScaleProbe
        eq(row:GetAttribute("*type1"),beforeLeft,"focus compatibility never modifies left selection")
        eq(row:GetAttribute("*macrotext1"),beforeLeftMacro,"focus compatibility leaves existing exact-name left macro intact")
        eq(row:GetAttribute("focus-click-command"),nil,"focus attempt ownership is fully released")
        live.target,live.focus,IsControlKeyDown,UnitExists=oldTarget,oldFocus,oldCtrl,oldExists
        NS.Diagnostics,C_Timer,bridge.KnownUniqueNPC=oldDiagnostics,oldTimer,oldUnique
        NS.Print=oldPrint
        NS.DB.legacyNameBridgeEnabled=oldEnabled
    end
    checkFocusClick(friendlyRow,live[friendlyRow.unit])
    checkFocusClick(enemyRow,live[enemyRow.unit])
    do
        -- This boundary spy checks routing and attribute ownership only. Real
        -- cycling/focus effects are covered by the separate FocusCycle test.
        local oldCycle,oldUnique,oldCtrl=NS.FocusCycle,bridge.KnownUniqueNPC,IsControlKeyDown
        local oldTarget,oldFocus,oldCollect=live.target,live.focus,NS.Collect
        local ownerUnit,ownerData=enemyRow.unit,live[enemyRow.unit]
        local originalUnit2=enemyRow:GetAttribute("*unit2")
        local active,prepared,after,commands,events=false,0,0,{},{}
        local pinned={}
        for key,value in pairs(ownerData) do pinned[key]=value end
        pinned.health,pinned.healthCurrent,pinned.healthMax,pinned.healthAvailable=nil,nil,nil,false
        local module={}
        module.IsActive=function() return active end
        module.Owns=function(row) return active and row==enemyRow end
        module.HoldRoster=function(side) return active and side=="enemy" end
        module.PinnedData=function(row) return module.Owns(row) and pinned or nil end
        module.RowStatus=function(row) return module.Owns(row) and "查2" or nil end
        module.Prepare=function(row,candidate)
            prepared=prepared+1
            if row~=enemyRow then return "/stopmacro","busy" end
            eq(candidate.guid,enemyRow.expectedGUID,"focus cycle receives the frozen owner identity")
            active=true;enemyRow:SetAttribute("focus-cycle-active",true)
            return "/stopmacro [combat]\n/targetenemy","seek"
        end
        module.AfterClick=function(row) after=after+1 end
        module.Command=function(argument) commands[#commands+1]=argument end
        module.OnEvent=function(event) events[#events+1]=event end
        NS.FocusCycle=module
        bridge.KnownUniqueNPC=function() return false,"duplicate_name" end
        IsControlKeyDown=function() return false end
        live.target,live.focus=nil,nil
        focusPhase(enemyRow,"PreClick")
        eq(prepared,1,"nonunique enemy main square starts the GUID cycle instead of refusing by name")
        eq(enemyRow:GetAttribute("*unit2"),"player","owner cycle bypasses only its transient nameplate unit precheck")
        eq(enemyRow:GetAttribute("*macrotext2"),"/stopmacro [combat]\n/targetenemy","cycle uses only the module's prepared native macro")
        focusPhase(enemyRow,"PostClick")
        eq(after,1,"right release dispatches the module's post-click readback")
        eq(enemyRow:GetAttribute("*unit2"),originalUnit2,"secure cleanup restores the owner's original right-click unit")
        eq(enemyRow:GetAttribute("*type2"),"focus","cycle cleanup restores the native focus baseline")
        enemyRow.unit="target"
        focusPhase(enemyRow,"PreClick")
        eq(prepared,2,"active owner resumes even when its alias no longer matches a nameplate")
        focusPhase(enemyRow,"PostClick");enemyRow.unit=ownerUnit
        focusPhase(friendlyRow,"PreClick")
        eq(prepared,3,"another row consults the active cycle before ordinary focus handling")
        eq(friendlyRow:GetAttribute("*macrotext2"),"/stopmacro","a busy cycle blocks another row's focus action")
        eq(friendlyRow:GetAttribute("*unit2"),nil,"busy rows never receive the owner's player override")
        focusPhase(friendlyRow,"PostClick")
        IsControlKeyDown=function() return true end
        focusPhase(enemyRow,"PreClick")
        eq(prepared,3,"Ctrl-right retains marker priority while a cycle is active")
        focusPhase(enemyRow,"PostClick");IsControlKeyDown=function() return false end
        local beforeAfter=after
        enemyRow.hooks.PostClick(enemyRow,"RightButton",true)
        enemyRow.hooks.PostClick(enemyRow,"LeftButton",false)
        eq(after,beforeAfter,"press and left click cannot advance focus-cycle readback")
        combat=true
        focusPhase(enemyRow,"PreClick",nil,true)
        eq(prepared,3,"ordinary combat hook never prepares or mutates a cycle command")
        eq(enemyRow:GetAttribute("*macrotext2"),"/stopmacro","secure combat guard prevents an inherited native focus action")
        focusPhase(enemyRow,"PostClick",nil,true);combat=false
        focusPhase(enemyRow,"PreClick",nil,true)
        focusPhase(enemyRow,"PostClick",nil,true)
        eq(enemyRow:GetAttribute("*type2"),"focus","first out-of-combat click releases the combat guard baseline")
        eq(enemyRow:GetAttribute("focus-cycle-combat-guard"),nil,"out-of-combat secure cleanup releases its guard ownership")
        live[ownerUnit]=nil;NS.HoveredTile=nil
        NS.RefreshTiles()
        eq(enemyRow.nameText:GetText(),pinned.name,"missing owner alias retains the frozen creature name")
        eq(enemyRow.shield:IsShown(),false,"frozen cycle owner remains clickable when its nameplate disappears")
        eq(enemyRow.statusText:GetText(),"查2","owner square exposes the module's short progress text")
        live.target={guid=enemyRow.expectedGUID};NS.RefreshTiles()
        eq(enemyRow.selected,true,"frozen owner current-target border follows the actual target GUID")
        resetTooltipOperations();enemyRow:GetScript("OnEnter")(enemyRow)
        yes(tooltipContains("焦点进度：查2"),"owner tooltip explains its current cycle progress")
        eq(hasTooltipOperation("SetUnit"),false,"frozen tooltip never attaches a missing or reused nameplate payload")
        NS.HoveredTile=nil
        NS.Collect=function(side) return {side=="enemy" and "nameplate2" or "party1"},1 end
        NS.RequestRefresh()
        eq(enemyRow.unit,ownerUnit,"active flow holds the enemy roster after the pointer leaves")
        eq(friendlyRow.unit,"party1","enemy flow leaves friendly roster updates active")
        NS.HandleCommand("focuscycle status");NS.HandleCommand("focuscycle stop");NS.HandleCommand("focuscycle restore")
        eq(table.concat(commands,","),"status,stop,restore","focuscycle commands reach their dedicated module")
        NS.HandleEvent("UNIT_HEALTH","player")
        eq(events[#events],"UNIT_HEALTH","Main forwards events to the active flow before coalescing visual work")
        active=false;enemyRow:SetAttribute("focus-cycle-active",nil)
        NS.FocusCycle,bridge.KnownUniqueNPC,IsControlKeyDown=oldCycle,oldUnique,oldCtrl
        live[ownerUnit],live.target,live.focus=ownerData,oldTarget,oldFocus
        NS.Collect=oldCollect;NS.HoveredTile=nil;NS.RequestRefresh()
    end
    for _,row in ipairs({friendlyRow,enemyRow}) do
        local originalFocus,originalSelected=live.focus,live[row.unit].target
        live.focus={guid=row.expectedGUID};live[row.unit].target=true
        combat=true;NS.RefreshTiles()
        eq(row.focused,true,"friendly and enemy main squares show their live focus identity")
        eq(row.selected,true,"current target remains visible together with focus")
        for i=1,4 do
            eq(row.focusEdges[i]:IsShown(),true,"all four outer focus edges are shown")
            eq(row.targetEdges[i]:IsShown(),true,"all four inner target edges remain shown")
        end
        eq(row.focusEdges[1].points[1][4],0,"focus outline stays at the square boundary")
        eq(row.targetEdges[1].points[1][4],2,"target outline sits inside the focus outline")
        eq(row.focusEdges[1].color[2],.82,"focus outline is gold")
        eq(row.focusEdges[1].sublevel,7,"identity borders draw above the hover texture")
        eq(row.hover.allPoints,nil,"hover fill no longer covers the border")
        eq(row:GetWidth(),76,"focus border never changes tile width")
        local secretFocus,reader={},issecretvalue
        issecretvalue=function(value) return rawequal(value,secretFocus) or reader(value) end
        live.focus={guid=secretFocus};NS.RefreshTiles()
        eq(row.focused,false,"unreadable focus identity does not produce a yellow border")
        issecretvalue=reader
        live.focus=nil;NS.RefreshTiles()
        for _,edge in ipairs(row.focusEdges) do eq(edge:IsShown(),false,"clearing focus removes every yellow edge") end
        combat=false
        live.focus,live[row.unit].target=originalFocus,originalSelected
        NS.RefreshTiles()
    end
    local child=enemyRow.enemyTargetButton
    local childInstalled=false
    for _,candidate in ipairs(installed) do if candidate==child then childInstalled=true;break end end
    yes(childInstalled,"enemy target child installs its own ordinary-spell bridge hooks")
    eq(child.bridgeTarget,true,"child is explicitly identified as an enemy-target relationship")
    eq(child.owner,enemyRow,"child bridge retains its owning enemy row")
    eq(child.driver.visibility,"[@nameplate1target,exists] show; hide","child driver permits both friendly and hostile targets")
    local childData
    NS.ReadEnemyTarget=function(unit,expectedGUID)
        if unit==enemyRow.unit and expectedGUID==enemyRow.expectedGUID then return childData end
        return {state="unavailable"}
    end
    for _,side in ipairs({"friendly","enemy"}) do
        childData={state="known",guid=side=="friendly" and "Player-ChildAlly" or "Player-ChildEnemy",
            name=side=="friendly" and "目标同伴" or "敌方目标",targetName=side=="friendly" and "目标同伴" or "敌方目标",
            className="牧师",color={r=1,g=1,b=1},player=true,dead=false,offline=false,
            assist=side=="friendly",harm=side=="enemy",health=.8,healthCurrent=80,healthMax=100,healthAvailable=true}
        live.nameplate1target={guid=childData.guid}
        -- The mock does not execute the secure exists driver; model its visible
        -- result before testing Lua delegation, without simulating a cast.
        child:Show()
        NS.RefreshTiles()
        checkFocusClick(child,childData)
        resetTooltipOperations();child:GetScript("OnEnter")(child)
        child.hooks.OnEnter(child)
        eq(NS.HoveredEnemyTarget,child,"child entry records its own hover owner for "..side)
        eq(entered[#entered],child,"ordinary-spell entry receives child rather than enemy owner for "..side)
        eq(child.side,side,"child bridge uses current target relationship for "..side)
        local currentChild=NS.ReadBridgeTarget(child)
        yes(currentChild~=nil,"UI child can provide validated bridge data for "..side)
        eq(currentChild.guid,childData.guid,"UI child exposes the target identity rather than parent enemy identity")
        eq(currentChild.side,side,"UI child exposes its own action relation")
        yes(tooltipContains("普通技能键"),"child tooltip describes ordinary skills")
        yes(tooltipContains("短暂选中此目标"),"child tooltip discloses temporary target selection")
        yes(tooltipContains("恢复原目标"),"child tooltip describes target restoration")
        yes(tooltipContains("右键设为焦点") and tooltipContains("Ctrl+右键打标记"),"child tooltip explains all three mouse actions")
        eq(child:GetScript("OnClick"),builtinUnitClick,"shared click setup preserves the native child OnClick")
        eq(child:GetAttribute("*type1"),"target","child retains explicit native left-click targeting")
        eq(child:GetAttribute("*type2"),"focus","either child relation supports native right-click focus")
        eq(child:GetAttribute("*clickbutton2"),nil,"child plain right-click never opens marking")
        for _,modifier in ipairs({"ctrl-","alt-ctrl-","ctrl-shift-","alt-ctrl-shift-"}) do
            eq(child:GetAttribute(modifier.."type2"),"click","child Ctrl modifier combination forwards marking")
            eq(child:GetAttribute(modifier.."clickbutton2"),child.markController,"child uses its own secure mark controller")
        end
        eq(NS.ValidToken(child.unit),false,"child marker support never broadens global unit tokens")
        local childMenu=NS.MarkerMenu
        local childOpen=child.markController:GetAttribute("_onclick")
        modelSecure(childOpen,child.markController,childMenu)
        eq(childMenu:GetAttribute("unit"),child.unit,"child palette freezes the relation unit")
        eq(childMenu:GetAttribute("source-row"),child:GetName(),"child palette freezes a registered child source")
        eq(childMenu:GetAttribute("source-guid"),childData.guid,"child palette freezes the child GUID")
        eq(childMenu:GetAttribute("source-owner-guid"),enemyRow.expectedGUID,"child palette also freezes the parent GUID")
        eq(childMenu.shield:IsShown(),false,"controlled child source opens a usable palette for "..side)
        modelSecure(markPre,childMenu.markers[8],childMenu)
        eq(childMenu.markers[8]:GetAttribute("*type1"),"raidtarget","child marker keeps the original native raidtarget action")
        eq(childMenu.markers[8]:GetAttribute("unit"),child.unit,"child marker targets the child rather than its parent")
        local snapshotGUID,snapshotOwner=childData.guid,enemyRow.expectedGUID
        combat=true
        childData.guid="Player-ChangedChild";live[child.unit].guid=childData.guid
        NS.HandleEvent("UNIT_TARGET",enemyRow.unit)
        eq(childMenu.shield:IsShown(),true,"UNIT_TARGET immediately shields a changed child before the UI refresh")
        NS.RefreshTiles()
        eq(child:GetAttribute("mark-guid"),snapshotGUID,"combat refresh leaves the prepared child marker identity frozen")
        eq(childMenu:GetAttribute("source-guid"),snapshotGUID,"a menu never adopts the newer child GUID")
        modelSecure(childOpen,child.markController,childMenu)
        eq(childMenu.shield:IsShown(),true,"reopening with stale combat marker attributes remains blocked")
        combat=false
        NS.RefreshTiles()
        eq(child:GetAttribute("mark-guid"),childData.guid,"out-of-combat child refresh prepares its changed identity")
        modelSecure(childOpen,child.markController,childMenu)
        eq(childMenu.shield:IsShown(),false,"fresh child identity may reopen the controlled palette")
        childData.assist,childData.harm=side=="enemy",side=="friendly"
        NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),true,"changed friend-or-enemy relation blocks the old palette")
        childData.assist,childData.harm=side=="friendly",side=="enemy"
        live[enemyRow.unit].guid="Creature-ReusedOwner"
        NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),true,"reused parent is blocked even when the child GUID is unchanged")
        live[enemyRow.unit].guid=snapshotOwner
        enemyRow.expectedGUID="Creature-NewPreparedOwner"
        NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),true,"frozen menu owner identity cannot be replaced by current row metadata")
        enemyRow.expectedGUID=snapshotOwner
        child:Hide();NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),true,"hidden child cannot retain an actionable old palette")
        child:Show();NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),false,"same valid relationship can become visible again")
        childMenu:SetAttribute("source-row","ArbitraryFrame");NS.InvalidateMarkMenu()
        eq(childMenu.shield:IsShown(),true,"unregistered source names are rejected")
        modelSecure(childOpen,child.markController,childMenu)
        childData.dead=true;NS.RefreshTiles()
        eq(child.shield:IsShown(),true,"invalid child shield also blocks right focus and Ctrl-right marker input")
        eq(child:GetAttribute("mark-guid"),nil,"invalid child clears prepared marker identity outside combat")
        modelSecure(childOpen,child.markController,childMenu)
        eq(childMenu:IsShown(),false,"an invalid child cannot reopen its palette")
        childData.dead=false;childData.guid=snapshotGUID;live[child.unit].guid=snapshotGUID
        NS.RefreshTiles()
        child:GetScript("OnLeave")(child)
        eq(NS.HoveredEnemyTarget,nil,"child leave clears its own hover owner")
    end
    eq(friendlyRow:GetAttribute("unit"),friendlyUnit,"friendly casting toggle does not change tile identity")
    eq(enemyRow:GetAttribute("unit"),enemyUnit,"friendly casting toggle does not change enemy identity")
    eq(friendlyRow:GetAttribute("*type1"),friendlyType,"friendly casting toggle preserves left-click action")
    eq(enemyRow:GetAttribute("*type1"),enemyType,"friendly casting toggle preserves enemy left-click action")
    eq(friendlyRow:GetAttribute("ctrl-clickbutton2"),friendlyMark,"friendly casting toggle preserves right-click marking")
    eq(enemyRow:GetAttribute("ctrl-clickbutton2"),enemyMark,"friendly casting toggle preserves enemy marking")
    eq(settingCalls,0,"ordinary-spell controls never mutate global native mouseover settings")
    eq(foreignCalls,0,"ordinary-spell UI never invokes combat preparation")
    NS.UI,NS.Collect,NS.Bindings=savedUI,savedCollect,savedBindings
    NS.NearbyCast,NS.CombatCast,NS.SetMouseoverEnabled=savedNearby,savedCombat,savedSetter
    GetMouseFoci,NS.LegacyNameBridge=savedFoci,savedPolicy
    NS.EnemyTargetHover,NS.ReadBridgeTarget,NS.ReadEnemyTarget=savedTargetModule,savedBridgeReader,savedTargetReader
end)()
-- All aura lists are resident visuals. Hover keeps only the existing unit
-- tooltip and instructions; wheel input forwards public scrolling gestures.
;(function()
    combat=false
    NS.NativeMacroOnly=true;NS.LegacyNameBridge=false
    NS.UI=nil;NS.HoveredTile=nil;NS.HoveredEnemyTarget=nil;NS.DB.shown=true
    local scrolls={}
    NS.Auras={
        Create=function(parent,compact)
            local container=newFrame("Frame",nil,parent);container:EnableMouse(false)
            return {container=container,compact=compact}
        end,
        Update=function(view,unit,expectedGUID,side,ownerUnit,ownerGUID)
            view.last={unit=unit,guid=expectedGUID,side=side,ownerUnit=ownerUnit,ownerGUID=ownerGUID}
        end,
        Scroll=function(view,delta) scrolls[#scrolls+1]={view=view,delta=delta} end,
        TooltipLines=function() error("all aura lists must not be read into a hover tooltip") end,
        ShowAll=function() error("hover expansion was removed") end,
        HideAll=function() error("resident auras must not hide on leave") end,
        Key=function() error("tooltip refresh must not enumerate aura revisions") end,
    }
    live.party1={side="friendly",player=true,guid="Aura-Friend",name="光环同伴",className="圣骑士",
        health=.75,healthCurrent=75,healthMax=100,healthAvailable=true,color={r=1,g=.5,b=.7},target=true}
    live.nameplate1={side="enemy",player=false,guid="Aura-Enemy",name="光环敌人",className="怪物",
        health=.5,healthCurrent=50,healthMax=100,healthAvailable=true,color={r=1,g=.4,b=.3}}
    live.nameplate1target={guid="Aura-Child"}
    local victim={state="known",guid="Aura-Child",name="光环队友",className="牧师",player=true,
        assist=true,harm=false,dead=false,offline=false,health=.8,healthCurrent=80,healthMax=100,
        healthAvailable=true,color={r=1,g=1,b=1}}
    NS.ReadEnemyTarget=function() return victim end
    NS.CreateUI()
    NS.BindTiles("friendly",{"party1"},5);NS.BindTiles("enemy",{"nameplate1"},5);NS.RefreshTiles()
    local friend,enemy=NS.UI.friendly.tiles[1],NS.UI.enemy.tiles[1]
    local card=enemy.enemyTargetDisplay
    yes(friend.auras and enemy.auras,"main cards receive resident aura views")
    eq(card.auras,nil,"the short target child never creates an aura view")
    eq(friend.auras.container.mouse,false,"resident aura visuals do not consume clicks or hover")
    eq(friend:GetWidth(),76,"compact main card reserves two aura rows")
    eq(friend:GetHeight(),58,"compact main card preserves room for two aura rows")
    eq(card:GetWidth(),76,"compact child card matches the main width")
    eq(card:GetHeight(),26,"short child card contains only name class and health")
    eq(friend.nameText.points[1][3],-3,"main name stays in the top header")
    eq(friend.nameText.height,12,"main name occupies only the first header row")
    eq(friend.nameText.points[2][2],-10,"main name uses the header width between corner markers")
    eq(friend.statusText.point[3],-16,"main health uses the second header row")
    eq(friend.statusText.width,24,"main health gets an independent readable column")
    local headerRects={
        {x=10,y=3,w=friend:GetWidth()-20,h=friend.nameText:GetHeight()},
        {x=friend:GetWidth()-4-friend.statusText:GetWidth(),y=16,w=friend.statusText:GetWidth(),h=friend.statusText:GetHeight()},
        {x=4,y=-friend.targetBadge.point[3],w=friend.targetBadge:GetWidth(),h=friend.targetBadge:GetHeight()},
        {x=0,y=-friend.questBadge.point[3],w=friend.questBadge:GetWidth(),h=friend.questBadge:GetHeight()},
        {x=friend:GetWidth()-friend.marker:GetWidth(),y=-friend.marker.point[3],w=friend.marker:GetWidth(),h=friend.marker:GetHeight()},
    }
    for i,a in ipairs(headerRects) do
        for j=1,i-1 do
            local b=headerRects[j]
            yes(not (a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y),
                "name, health, current label, quest and raid marker reserve disjoint header regions")
        end
    end
    eq(friend.questBadge.point[3],0,"quest marker stays inside its own card")
    eq(friend.marker.point[3],0,"raid marker stays inside its own card")
    yes(16+friend.targetBadge:GetHeight()<=26,"current-target label ends before compact aura rows")
    local resourceTop=58-friend.powerTrack.point[3]-friend.powerTrack.height
    eq(resourceTop,51,"resource strip remains under both compact aura rows")
    yes(38+10<=resourceTop,"second compact aura row stays above the resource strip")
    eq(friend.statusText:GetText(),"75%","main header retains actual health")
    eq(enemy.classText:GetText(),"","enemy repeat class stays in the original unit tooltip")
    eq(card.nameText.point[2],4,"child name no longer loses width to two summary icons")
    eq(card.nameText.width,68,"child name uses the complete first row")
    eq(card.classText:GetText(),"牧师","child retains its visible class")
    eq(card.classText.point[1],"TOPLEFT","child class shares the second header row with health")
    eq(card.healthText.point[3],-14,"child health remains in the short second row")
    eq(card.healthText:GetText(),"80%","child retains actual health")
    eq(friend.auras.last.unit,"party1","friendly auras are bound without pointer hover")
    eq(friend.auras.last.guid,"Aura-Friend","friendly auras retain frozen identity")
    eq(enemy.auras.last.side,"enemy","enemy auras receive enemy relation")
    eq(friend:GetScript("OnClick"),builtinActionClick,"resident auras preserve native main clicks")
    eq(enemy.enemyTargetButton:GetScript("OnClick"),builtinUnitClick,"resident auras preserve native child clicks")
    resetTooltipOperations();friend:GetScript("OnEnter")(friend)
    yes(hasTooltipOperation("SetUnit"),"resident aura tooltip retains native unit payload")
    eq(hasTooltipOperation("SetText"),false,"resident aura instructions do not replace native unit payload")
    yes(tooltipContains("效果过多时用滚轮浏览"),"overflow instructions stay in the existing tooltip")
    yes(tooltipContains("本人施加的增益"),"main tooltip describes the requested personal aura scope")
    friend:GetScript("OnLeave")(friend)
    eq(friend.auras.last.unit,"party1","leaving the square keeps all auras visible")
    eq(friend.wheel,true,"main card accepts wheel gestures without replacing clicks")
    friend:GetScript("OnMouseWheel")(friend,-1)
    eq(scrolls[1].view,friend.auras,"main wheel targets only its own aura view")
    eq(scrolls[1].delta,-1,"main wheel forwards the actual gesture direction")
    eq(enemy.enemyTargetButton:GetScript("OnMouseWheel"),nil,"short child has no aura scrolling handler")
    friend:Hide();eq(friend.auras.last.unit,nil,"hiding a main card clears detached resident visuals immediately")
    friend:Show();NS.RefreshTiles()
    combat=true;live.party1.guid="Aura-Reused";NS.RefreshTiles()
    eq(friend.auras.last.unit,nil,"combat token reuse clears the old aura view")
    live.nameplate1target.guid="Aura-ChangedChild";NS.RefreshTiles()
    eq(enemy.enemyTargetButton.expectedGUID,nil,"changed child identity invalidates its interaction")
    live.nameplate1.guid="Aura-ChangedOwner";NS.RefreshTiles()
    eq(enemy.auras.last.unit,nil,"changed enemy identity clears its resident aura view")
    eq(enemy.enemyTargetButton.expectedGUID,nil,"changed enemy owner invalidates the short child interaction")
    combat=false;NS.UI.friendly.frame:Hide();NS.RefreshTiles()
    eq(friend.auras.last.unit,nil,"hidden panel leaves no resident aura unit")
    NS.Auras=nil
end)()
print("Targets UI simulated checks: "..checks.."; secure engine and world rendering remain in-game checks")
