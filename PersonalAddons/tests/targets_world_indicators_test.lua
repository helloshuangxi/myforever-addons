-- Native-position/identity configuration simulation only. Pixel readability
-- and the client's actual world/nameplate anchoring remain game checks.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local secret={}
issecretvalue=function(value) return rawequal(value,secret) end
local combat,now=false,0
InCombatLockdown=function() return combat end
GetTime=function() return now end
local methods,frames={},{}
local nativeWrites=0
local function mutable(frame)
    if frame.native then nativeWrites=nativeWrites+1;error("native frame must remain read-only") end
end
local function frame(kind,name,parent,template)
    local value=setmetatable({kind=kind,name=name,parent=parent,template=template,scripts={},shown=true,scale=1}, {__index=methods})
    frames[#frames+1]=value
    if name then _G[name]=value end
    return value
end
CreateFrame=frame
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:IsForbidden() return self.forbidden or false end
function methods:SetSize(w,h) mutable(self);self.width,self.height=w,h end
function methods:SetScale(value) mutable(self);self.scale=value end
function methods:SetFrameStrata(value) mutable(self);self.strata=value end
function methods:EnableMouse(value) mutable(self);self.mouse=value end
function methods:SetPoint(...) mutable(self);self.point={...} end
function methods:ClearAllPoints() mutable(self);self.point=nil end
function methods:SetScript(kind,callback) mutable(self);self.scripts[kind]=callback end
function methods:CreateTexture() mutable(self);return frame("Texture",nil,self) end
function methods:CreateFontString() mutable(self);return frame("FontString",nil,self) end
function methods:SetTexture(value) mutable(self);self.texture=value end
function methods:SetRotation(value) mutable(self);self.rotation=value end
function methods:SetVertexColor(...) mutable(self);self.color={...} end
function methods:SetTextColor(...) mutable(self);self.color={...} end
function methods:SetBlendMode(value) mutable(self);self.blend=value end
function methods:SetAlpha(value) mutable(self);self.alpha=value end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF",12,"" end
function methods:SetFont(...) mutable(self);self.font={...} end
function methods:SetText(value) mutable(self);self.text=value end
function methods:Hide() mutable(self);self.shown=false end
function methods:Show() mutable(self);self.shown=true end
UIParent=frame("Frame","UIParent")
local units,plates={},{ }
UnitExists=function(unit) return units[unit]~=nil end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
local mappingHook
C_NamePlate={GetNamePlateForUnit=function(unit)
    if mappingHook then mappingHook(unit) end
    return plates[unit]
end}
local forbiddenActions=0
for _,name in ipairs({"TargetUnit","ClearTarget","FocusUnit","ClearFocus","SetRaidTarget","SetCVar",
    "SetBinding","SetOverrideBindingClick","CastSpellByName"}) do
    _G[name]=function() forbiddenActions=forbiddenActions+1;error("visual marker called "..name) end
end
C_NamePlate.SetNamePlateSize=function() forbiddenActions=forbiddenActions+1;error("visual marker resized native plates") end
local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.Initialize(nil)
NS.NameplateTokens=function()
    local tokens={}
    for token in pairs(units) do if token:match("^nameplate%d+$") then tokens[#tokens+1]=token end end
    table.sort(tokens);return tokens
end
NS.ReadUnit=function(unit,side)
    local data=units[unit]
    return data and {unit=unit,guid=data.guid,side=side} or nil
end
assert(loadfile(root.."Hover.lua"))("MyForeverTargets",NS)
NS.UpdateWorldIndicators()
eq(next(NS.WorldIndicators),nil,"no target/focus leaves no guessed world markers")

local plate1=frame("Frame","NativePlateOne",UIParent)
plate1.namePlateUnitToken="nameplate1";plate1.native=true
local plate2=frame("Frame","NativePlateTwo",UIParent)
plate2.namePlateUnitToken="nameplate2";plate2.native=true
units.nameplate1={guid="Creature-one"};units.nameplate2={guid="Creature-two"}
units.target={guid="Creature-one"}
plates.nameplate1,plates.nameplate2=plate1,plate2
NS.UpdateWorldIndicators()
eq(NS.WorldIndicators.target,nil,"a current target alone no longer creates a world marker")
eq(MyForeverTargetsTargetIndicator,nil,"removed target indicator frame is never created")
eq(next(NS.WorldIndicators),nil,"target-only state leaves world markers empty")

units.focus={guid="Creature-two"};NS.UpdateWorldIndicators()
local focus=NS.WorldIndicators.focus
yes(focus and focus:IsShown(),"focus still resolves its own same-GUID native plate")
eq(focus.guid,"Creature-two","focus stores only verified identity")
eq(focus.plate,plate2,"focus anchors to its real plate")
eq(focus.plateUnit,"nameplate2","focus stores the verified reverse-mapped token")
eq(focus.parent,UIParent,"focus is not parented into the native plate")
eq(focus.label.text,"焦点","focus retains its label")
eq(MyForeverTargetsFocusIndicator,focus,"focus retains its diagnostic frame name")
eq(focus.label.color[2],.75,"focus retains its gold color")
eq(focus.point[4],0,"focus is centered without reserving room for a target mark")
eq(focus.scripts.OnUpdate,nil,"focus still shares the main update loop")
eq(focus.width*focus.scale,42,"focus keeps its compact size")
local oldBreath=focus.body.alpha
now=.6;NS.UpdateWorldIndicators()
yes(focus.body.alpha~=oldBreath,"focus breathing animation remains active")

units.focus.guid="Creature-one";NS.UpdateWorldIndicators()
eq(focus.point[4],0,"same-unit current target no longer shifts focus sideways")
eq(NS.WorldIndicators.target,nil,"same-unit focus does not bring back the target marker")
NS.SetHoverUnit("nameplate1","enemy")
local hover=NS.HoverIndicator
yes(hover:IsShown(),"original hover animation remains available")
local hoverPoint=hover.point
NS.UpdateWorldIndicators()
yes(focus.point[4]>0,"focus still moves aside for the original hover animation")
eq(NS.HoverIndicator,hover,"focus does not replace the original hover frame")
eq(hover.point,hoverPoint,"focus does not move the hover marker")
NS.HideHover();NS.UpdateWorldIndicators()
eq(focus.point[4],0,"focus recenters after hover leaves")
eq(focus:IsShown(),true,"ending hover does not hide focus")

units.target=nil;NS.UpdateWorldIndicators()
eq(focus:IsShown(),true,"clearing current target does not hide focus")
eq(focus.point[4],0,"current-target changes do not move focus")
units.target={guid="Creature-one"};units.focus=nil;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"clearing focus hides its world mark even with a current target")
eq(focus.guid,nil,"hidden focus clears stale identity")
eq(MyForeverTargetsTargetIndicator,nil,"retaining a current target still creates no target mark")
units.focus={guid="Creature-one"}

-- Missing frame token fields remain supported through verified reverse lookup.
plate1.namePlateUnitToken=nil;NS.UpdateWorldIndicators()
eq(focus:IsShown(),true,"fieldless native plate can still show verified focus")
eq(focus.plateUnit,"nameplate1","fieldless plate retains a real exposed token")
plate1.namePlateUnitToken=secret;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"restricted native token does not become a guessed match")
plate1.namePlateUnitToken="nameplate2";NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"contradictory native token prevents a stale focus anchor")
plate1.namePlateUnitToken="nameplate1"
plate1.shown=false;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"hidden plates have no guessed world position")
plate1.shown=true;UIParent.shown=false;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"effective parent visibility is respected")
UIParent.shown=true;plate1.forbidden=true;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"forbidden native frame is rejected")
plate1.forbidden=false
plate1.IsForbidden=function() error("restricted native frame") end
eq(pcall(NS.UpdateWorldIndicators),true,"native API errors remain contained")
eq(focus:IsShown(),false,"unknown native frame permission fails closed")
plate1.IsForbidden=nil

units.nameplate1.guid="Creature-reused";NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"nameplate pool reuse cannot carry the old focus mark")
units.nameplate1.guid="Creature-one"
units.focus.guid=secret;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"secret focus identity is not rendered")
units.focus.guid="Creature-one"
local normalExists=UnitExists
local focusRemoved=false
UnitExists=function(unit) if unit=="focus" and focusRemoved then return false end;return normalExists(unit) end
mappingHook=function(unit) if unit=="nameplate1" then focusRemoved=true end end
NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"removed focus is rejected even if its old GUID remains readable")
mappingHook=nil;UnitExists=normalExists
mappingHook=function(unit) if unit=="nameplate1" then units.focus.guid="Creature-two" end end
NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"focus change during lookup rejects mixed identity")
mappingHook=nil;NS.UpdateWorldIndicators()
eq(focus.plate,plate2,"next update finds the new focus plate")
eq(focus.guid,"Creature-two","replacement focus cannot inherit old identity")
plates.nameplate2=nil;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"missing native mapping hides focus")
plates.nameplate2=plate2

combat=true;NS.UpdateWorldIndicators()
eq(focus:IsShown(),true,"focus visuals still work in combat")
eq(NS.WorldIndicators.target,nil,"combat does not recreate a target world mark")
eq(nativeWrites,0,"native plate geometry and input remain untouched")
eq(forbiddenActions,0,"visuals never change target/focus/raid marks or cast")
for _,value in ipairs(frames) do
    if value~=UIParent and not value.native and value.kind=="Frame" then
        eq(value.mouse,false,"all visual frames are click-through")
        eq(value.template,nil,"visual frames remain unprotected")
    end
end
NS.DB.shown=false;NS.UpdateWorldIndicators()
eq(focus:IsShown(),false,"hiding addon hides focus")
NS.DB.shown=true;NS.UpdateWorldIndicators();NS.HideWorldIndicators()
eq(focus:IsShown(),false,"leaving-world cleanup hides focus")
eq(focus.plate,nil,"cleanup clears native anchor identity")
print("Targets world-indicator simulated checks: "..checks.."; actual pixels and native world anchors remain in-game checks")
