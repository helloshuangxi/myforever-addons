-- Simulates native configuration, fixed clipping, public-only scroll bounds and
-- identity gating. It does not execute the native renderer or secure hit testing.
local checks=0
local function eq(a,b,why) checks=checks+1;assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a)) end
local function yes(a,why) eq(not not a,true,why) end
local secret=setmetatable({}, {__tostring=function() error("secret tostring") end,
    __concat=function() error("secret concat") end})
issecretvalue=function(v) return rawequal(v,secret) end
local combat,nativeAvailable=false,true
InCombatLockdown=function() return combat end
GetTime=function() return 100 end
AuraContainerSortMethod={ExpirationOnly=5}
AuraContainerSortDirection={Normal=0}
AnchorUtil={FlowDirection={Right=1,Down=2}}
local methods,frames={},{}
local function frame(kind,name,parent,template)
    if kind=="AuraContainer" and not nativeAvailable then error("unsupported frame type") end
    local f=setmetatable({kind=kind,parent=parent,template=template,shown=true,groups={},hooks={},writes=0,scroll=0}, {__index=methods})
    frames[#frames+1]=f
    return f
end
CreateFrame=frame
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetAllPoints() self.allPoints=true end
function methods:SetPoint(...) self.point={...} end
function methods:SetFrameLevel(n) self.level=n end
function methods:GetFrameLevel() return self.level or 4 end
function methods:GetEffectiveScale() return self.effectiveScale or 1 end
function methods:SetScale(n) assert(not issecretvalue(n));self.scale=n end
function methods:EnableMouse(v) self.mouse=v end
function methods:SetMouseClickEnabled(v) self.click=v end
function methods:SetMouseMotionEnabled(v) self.motion=v end
function methods:SetClipsChildren(v) self.clips=v end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and self.ancestorVisible~=false end
function methods:Show() self.shown=true end
function methods:Hide()
    local wasShown=self.shown
    self.shown=false
    if wasShown then for _,f in ipairs(self.hooks.OnHide or {}) do f(self) end end
end
function methods:HookScript(name,f)
    self.hooks[name]=self.hooks[name] or {}
    self.hooks[name][#self.hooks[name]+1]=f
end
function methods:SetEnabled(v) self.enabled=v;self.writes=self.writes+1 end
local onSetUnit
function methods:SetUnit(unit)
    assert(type(unit)=="string","native SetUnit must not receive nil")
    self.unit=unit;self.writes=self.writes+1
    if onSetUnit then onSetUnit(unit) end
end
function methods:SetFlowLayoutAnchorPoint(v) self.anchor=v end
function methods:SetFlowLayoutGrowthDirection(...) self.growth={...} end
function methods:SetFlowLayoutMaximumLineSize(v) self.lineSize=v end
function methods:CreateTexture() return frame("Texture",nil,self) end
function methods:CreateFontString() return frame("FontString",nil,self) end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetText(v) self.text=v end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetJustifyH(v) self.justify=v end
function methods:GetFont() return "font",9,"" end
function methods:SetFont(...) self.font={...} end
function methods:SetIcon(v) self.icon=v end
function methods:SetApplicationCount(v) self.count=v end
function methods:AddDispelTypeTexture(v) self.dispel=v end
function methods:SetDurationCooldown(v) self.cooldown=v end
function methods:SetReverse(v) self.reverse=v end
function methods:SetDrawEdge(v) self.edge=v end
function methods:SetHideCountdownNumbers(v) self.hideNumbers=v end
function methods:AddAuraGroup(key,filter,options)
    local group={filter=filter,options=options,buttons={}}
    self.groups[key]=group
    for i=1,3 do
        local button=frame("AuraButton",nil,self)
        group.buttons[i]=button
        options.initializeFrame(button)
    end
end
function methods:UpdateAllAuras() self.refreshes=(self.refreshes or 0)+1 end
function methods:SetScrollChild(child) self.scrollChild=child end
local scrollHook,throwScroll
function methods:SetVerticalScroll(value)
    assert(type(value)=="number" and not issecretvalue(value),"no secret scroll writes")
    if throwScroll then error("scroll unavailable") end
    self.scroll=value
    if scrollHook then scrollHook(self,value) end
end
function methods:GetVerticalScrollRange() return self.range==nil and secret or self.range end
function methods:GetHeight() error("addon must not read native aura dimensions") end
function methods:GetWidth() error("addon must not read native aura dimensions") end
local forbidden=0
for _,api in ipairs({"TargetUnit","ClearTarget","FocusUnit","ClearFocus","CastSpellByName","CastSpellByID",
    "RunMacroText","SetRaidTarget","SetBinding","SetOverrideBindingClick","CreateMacro","EditMacro"}) do
    _G[api]=function() forbidden=forbidden+1;error("aura module called "..api) end
end
function methods:SetAttribute() forbidden=forbidden+1;error("aura module changed secure attribute") end
local units={player="player-a",nameplate1="enemy-a",nameplate1target="friend-a",party1="friend-a"}
UnitGUID=function(unit) return units[unit] end
local auraCalls,throwRead,readSecret,readHook=0,false,false,nil
local canDispel=true
local auras={}
C_UnitAuras={GetAuraDataByIndex=function(unit,index,filter)
    auraCalls=auraCalls+1
    assert(not combat,"combat must never enumerate aura data")
    assert(filter=="HELPFUL|PLAYER" or filter=="HARMFUL|PLAYER" or filter=="HARMFUL|RAID" or filter=="HARMFUL|PLAYER|!RAID","counting matches related native filters")
    if readHook then readHook() end
    if throwRead then error("restricted aura access") end
    if readSecret then return secret end
    local selected={}
    for _,aura in ipairs(auras[unit] or {}) do
        local dispellable=aura.dispellable and canDispel
        if filter=="HELPFUL|PLAYER" and not aura.harmful and aura.mine
            or filter=="HARMFUL|PLAYER" and aura.harmful and aura.mine
            or filter=="HARMFUL|RAID" and aura.harmful and dispellable
            or filter=="HARMFUL|PLAYER|!RAID" and aura.harmful and aura.mine and not dispellable then
            selected[#selected+1]=aura
        end
    end
    return selected[index]
end}
local function effects(buffs,debuffs)
    local result={}
    for i=1,buffs do result[#result+1]={name=secret,spellId=100000+i,mine=true,duration=60} end
    for i=1,debuffs do result[#result+1]={name=secret,spellId=secret,harmful=true,mine=true,dispellable=i%2==0} end
    return result
end
local NS={}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Auras.lua"))("MyForeverTargets",NS)
local A=NS.Auras
UIParent=frame("Frame")
local parent=frame("Frame")
parent.effectiveScale=0.8
local view=A.Create(parent,false)
yes(view and view.ready,"native permanent view ready")
eq(A.ShowAll,nil,"hover expansion removed")
eq(A.HideAll,nil,"hover popup lifecycle removed")
eq(#view.containers,3,"one buff and two relation-specific harmful containers")
eq(#view.viewports,3,"separate fixed clipping viewport per native container")
eq(view.helpful.groups.buffs.filter,"HELPFUL|PLAYER","buffs are from player, pet or vehicle")
eq(view.harmful.groups.debuffs.filter,"HARMFUL|PLAYER","enemy only has own-source debuffs")
eq(view.dispellable.groups.dispels.filter,"HARMFUL|RAID","friendly highlights own dispels")
eq(view.dispellable.groups.otherDebuffs.filter,"HARMFUL|PLAYER|!RAID","friendly own-source complement avoids duplicate auras")
for _,container in ipairs(view.containers) do
    eq(container.lineSize,65,"native row wraps after six 10px icons")
    eq(container.enabled,false,"initial native container disabled")
    for _,group in pairs(container.groups) do
        eq(group.options.maxFrameCount,nil,"full native list has no addon item cap")
        if group.filter=="HELPFUL|PLAYER" then
            eq(group.options.candidateFilters.maxDuration,math.huge,"native excludes permanent buffs without finite-duration cutoff")
            for _,id in ipairs({2580,2383,43308}) do
                eq(group.options.candidateFilters.excludeSpellIDs[id],true,"known tracking ID excluded "..id)
            end
        else eq(group.options.candidateFilters,nil,"tracking exclusions never remove a debuff") end
        eq(group.options.sortMethod,5,"native expiration sorting")
        eq(group.options.sortDirection,0,"native normal order")
        eq(group.options.layout.elementWidth,10,"compact icon size")
        eq(group.options.layout.elementSpacing,1,"compact column spacing")
        eq(group.options.layout.lineSpacing,1,"compact row spacing")
        eq(group.options.layout.forceNewLine,false,"groups continue on same row")
        eq(group.options.layout.groupSpacing,0,"group boundary adds no empty space")
    end
end
for i,viewport in ipairs(view.viewports) do
    eq(viewport.parent,UIParent,"scroll viewport independent of secure unit button")
    eq(viewport.width,65,"viewport row width")
    eq(viewport.height,10,"viewport shows one complete row")
    eq(viewport.point[5],i==1 and -26 or -38,"separate buff and debuff rows below main header")
    eq(viewport.point[4],8,"row leaves room for compact category symbol")
    eq(viewport.clips,true,"overflow cannot paint into neighboring tiles")
    eq(viewport.shown,false,"unbound independent viewport hidden")
    yes(viewport.scrollChild,"native aura container is scroll child")
end
eq(view.labels[1].text,"+","compact helpful symbol")
eq(view.labels[2].text,"-","compact harmful symbol")
eq(view.labels[1].height,8,"category label avoids icon area")
eq(view.labels[1].width,5,"category label stays in narrow gutter")
eq(view.labels[1].point[2],2,"category symbol left inset")
eq(view.labels[1].point[3],-27,"main helpful symbol aligns within icon height")
eq(view.labels[2].point[3],-39,"main harmful symbol aligns within icon height")
eq(view.labels[1].textColor[2],1,"helpful symbol is green")
eq(view.labels[2].textColor[1],1,"harmful symbol is red")
for _,f in ipairs(frames) do
    if f.kind=="AuraContainer" or f.kind=="AuraButton" or f.kind=="Cooldown" or f.kind=="ScrollFrame" or f.parent and f.kind=="Frame" then
        eq(f.mouse,false,"visual mouse disabled")
        eq(f.click,false,"visual click disabled")
        eq(f.motion,false,"visual motion disabled")
    end
    if f.kind=="AuraButton" then
        yes(f.icon and f.dispel and f.cooldown,"native sinks own visible aura data")
        eq(f.count,nil,"tiny icons omit crowded stack digits")
        eq(f.dispel.allPoints,true,"border remains inside icon")
        eq(f.cooldown.hideNumbers,true,"no countdown number clutter")
    end
end
local compact=A.Create(parent,true)
eq(compact.nameInset,4,"child no longer reserves old tiny summary gutter")
eq(compact.helpful.groups.buffs.options.layout.elementWidth,10,"child uses same compact permanent icons")
eq(compact.helpfulViewport.height,10,"child viewport shows one row")
eq(compact.helpfulViewport.point[5],-24,"child helpful row clears name and status")
eq(compact.harmfulViewport.point[5],-36,"child harmful row fits 48px height")
eq(compact.labels[1].point[3],-25,"child helpful symbol alignment")
eq(compact.labels[2].point[3],-37,"child harmful symbol alignment")
yes(A.Update(view,"party1","friend-a","friendly"),"verified friendly binds")
eq(view.helpful.enabled,true,"helpful list enabled")
eq(view.dispellable.enabled,true,"friendly complete harmful list enabled")
eq(view.harmful.enabled,false,"enemy harmful duplicate disabled")
eq(view.helpfulViewport.scale,0.8,"independent viewport follows parent effective scale")
eq(view.labels[1].shown,true,"bound categories visible")
local writes=view.helpful.writes
for i=1,100 do A.Update(view,"party1","friend-a","friendly") end
eq(view.helpful.writes,writes,"stable rows do not continually rebind")
eq(auraCalls,0,"normal display never enumerates public auras")
parent.effectiveScale=0.65
A.Update(view,"party1","friend-a","friendly")
eq(view.helpfulViewport.scale,0.65,"runtime scale updates independent viewport")
UIParent.effectiveScale=0.5
A.Update(view,"party1","friend-a","friendly")
eq(view.helpfulViewport.scale,1.3,"viewport uses relative scale versus UIParent")
UIParent.effectiveScale=1

-- Secret native range with only three buffs must not scroll into blank space.
auras.party1=effects(3,0)
yes(A.Scroll(view,-1),"nonoverflow scroll safely handled")
eq(view.scrollOffset,0,"three buffs cannot scroll empty")
eq(view.helpfulViewport.scroll,0,"native viewport stays at zero")
yes(auraCalls>0,"public presence count is used only as scroll fallback")
local reads=auraCalls
A.Scroll(view,-1)
eq(auraCalls,reads,"same revision reuses public scroll bounds")
eq(view.scrollRangeCurrent,true,"out-of-combat public count is current")
eq(#A.TooltipLines(view),0,"no aura text popup")
eq(A.Key(view),"","no aura tooltip refresh key")
eq(auraCalls,reads,"compatibility tooltip never enumerates effects")

-- Unrelated effects and the three confirmed tracking buffs do not create scroll overflow.
auras.party1=effects(6,0)
for _,id in ipairs({2580,2383,43308}) do auras.party1[#auras.party1+1]={spellId=id,mine=true} end
for i=1,20 do auras.party1[#auras.party1+1]={spellId=200000+i,mine=false} end
for i=1,20 do auras.party1[#auras.party1+1]={harmful=true,mine=false,dispellable=false} end
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,0,"unrelated and tracking auras do not inflate public fallback range")
-- Permanent helpful effects do not occupy the related timed-buff row.
auras.party1=effects(6,0)
for i=1,20 do auras.party1[#auras.party1+1]={spellId=300000+i,mine=true,duration=0} end
auras.party1[#auras.party1+1]={spellId=secret,mine=true,duration=0}
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,0,"permanent effects do not inflate timed-buff scroll range")
eq(view.scrollRangeCurrent,true,"public zero duration safely excludes even unknown spell identity")
auras.party1[#auras.party1+1]={spellId=400000,mine=true,duration=1000000000}
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,11,"very long finite buff is retained without arbitrary duration ceiling")
auras.party1=effects(6,0)
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,0)
auras.party1[1].duration=secret
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollRangeCurrent,false,"secret duration cannot be used to infer native candidate count")
eq(view.scrollOffset,0,"unknown duration keeps conservative prior bounds")
auras.party1[1].duration=nil
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollRangeCurrent,false,"missing duration does not guess permanent or timed")
auras.party1[1].duration=60
-- Spell ID uncertainty cannot be guessed from a localized tracking name.
auras.party1[1].spellId=secret
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollRangeCurrent,false,"secret buff spell identity prevents an exact excluded count")
eq(view.scrollOffset,0,"unknown filtered count retains safe prior bounds")
auras.party1[1].spellId=nil
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollRangeCurrent,false,"missing buff spell identity also refuses an exact count")
-- Friend: another caster's dispellable debuff plus own harmful effects is a
-- union; an own dispellable aura is present once, not in both native groups.
auras.party1={
    {harmful=true,mine=false,dispellable=true,duration=0},
    {harmful=true,mine=true,dispellable=true,duration=0},
}
for i=1,4 do auras.party1[#auras.party1+1]={harmful=true,mine=true,dispellable=false} end
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,0,"two dispels plus four own non-dispels fit one six-icon row")
auras.party1[#auras.party1+1]={harmful=true,mine=true,dispellable=false}
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,11,"seventh union member creates exactly one extra row")
canDispel=false
A.OnEvent("SPELLS_CHANGED")
eq(view.scrollOffset,0,"losing dispel capability removes only the unrelated dispel from union")
canDispel=true
A.ResetScroll(view)

auras.party1=effects(6,6)
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,0,"six icons fit without blank scrolling")
auras.party1=effects(7,7)
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,11,"seventh effect is reachable on next native row")
A.ResetScroll(view)

auras.party1=effects(51,60)
A.OnEvent("UNIT_AURA","party1")
yes(A.Scroll(view,-1),"overflow scrolls one visible row at a time")
eq(view.scrollOffset,11,"public scroll step")
eq(view.helpfulViewport.scroll,11,"helpful row scrolls")
eq(view.dispellableViewport.scroll,11,"friendly harmful row scrolls")
A.Scroll(view,-1)
eq(view.scrollOffset,22,"second wheel step does not skip an icon row")
A.Scroll(view,-99)
eq(view.scrollOffset,99,"overall offset clamps to larger public bound")
eq(view.helpfulViewport.scroll,88,"shorter row list clamps independently")
eq(view.dispellableViewport.scroll,99,"longer row list reaches final page")
A.Scroll(view,99)
eq(view.scrollOffset,0,"wheel up clamps at top")
-- Increasing beyond the six-item viewport never adds a rendering cap.
eq(view.helpful.groups.buffs.options.maxFrameCount,nil,"scrolling does not truncate native list")

-- Current public native ranges avoid any fallback enumeration.
view.helpfulViewport.range=13;view.dispellableViewport.range=26
A.OnEvent("UNIT_AURA","party1")
reads=auraCalls
A.Scroll(view,-99)
eq(auraCalls,reads,"public native ranges need no aura enumeration")
eq(view.helpfulViewport.scroll,13,"native helpful range used")
eq(view.dispellableViewport.scroll,26,"native harmful range used")
view.helpfulViewport.range=secret;view.dispellableViewport.range=secret
combat=true
A.OnEvent("PLAYER_REGEN_DISABLED")
reads=auraCalls
A.Scroll(view,-99)
eq(auraCalls,reads,"combat never counts protected auras")
eq(view.scrollOffset,26,"combat secret range conservatively uses last public bounds")
eq(view.scrollRangeCurrent,false,"historical bounds are not claimed current")
eq(A.Create(parent,false),nil,"combat does not create containers")
combat=false
A.OnEvent("PLAYER_REGEN_ENABLED")

-- Shrinking publicly readable lists returns a scrolled viewport to the top.
auras.party1=effects(3,0)
A.OnEvent("UNIT_AURA","party1")
eq(view.scrollOffset,0,"aura removal clamps stale scroll offset")
eq(view.helpfulViewport.scroll,0,"small list cannot remain scrolled blank")
throwRead=true
A.OnEvent("UNIT_AURA","party1")
yes(A.Scroll(view,-1),"unavailable count retains safe previous bounds")
eq(view.scrollOffset,0,"read failure does not invent overflow")
eq(view.scrollRangeCurrent,false,"failed count is not current evidence")
throwRead=false;readSecret=true
A.OnEvent("UNIT_AURA","party1")
A.Scroll(view,-1)
eq(view.scrollOffset,0,"secret aura table is never counted")
readSecret=false

-- Public range loss before any confirmed count uses the top position.
yes(A.Update(compact,"nameplate1target","friend-a","friendly","nameplate1","enemy-a"),"verified child binds")
combat=true
reads=auraCalls
A.Scroll(compact,-1)
eq(auraCalls,reads,"new combat child does not enumerate")
eq(compact.scrollOffset,0,"unknown child range defaults to top")
combat=false
local refresh=view.dispellable.refreshes or 0
A.OnEvent("SPELLS_CHANGED")
eq(view.dispellable.refreshes,refresh+1,"learning refreshes own-dispel classification")

-- Identity, ancestor hiding and world transitions close independent UIParent frames.
yes(A.Update(view,"nameplate1","enemy-a","enemy"),"enemy rebind succeeds")
eq(view.dispellableViewport.shown,false,"friendly detail viewport closes")
eq(view.harmfulViewport.shown,true,"enemy harmful viewport appears")
eq(view.scrollOffset,0,"unit change resets scroll")
eq(view.publicRanges,nil,"new identity does not inherit old scroll bounds")
auras.nameplate1=effects(6,6)
for i=1,20 do auras.nameplate1[#auras.nameplate1+1]={harmful=true,mine=false,dispellable=true} end
A.Scroll(view,-1)
eq(view.scrollOffset,0,"enemy public range excludes all other-caster debuffs")
auras.nameplate1[#auras.nameplate1+1]={harmful=true,mine=true}
A.OnEvent("UNIT_AURA","nameplate1")
A.Scroll(view,-1)
eq(view.scrollOffset,11,"enemy seventh own-source debuff remains reachable")

units.nameplate1="enemy-reused"
eq(A.Scroll(view,-1),false,"reused source identity refuses scrolling")
eq(view.helpfulViewport.shown,false,"reused source closes independent visuals")
eq(view.harmful.enabled,false,"reused source stops native updates")
units.nameplate1="enemy-a"
onSetUnit=function(unit) if unit=="nameplate1" then units[unit]="enemy-race" end end
eq(A.Update(view,"nameplate1","enemy-a","enemy"),false,"binding rechecks identity after native calls")
eq(view.helpfulViewport.shown,false,"binding race never exposes new visuals")
onSetUnit=nil;units.nameplate1="enemy-a"
yes(A.Update(view,"party1","friend-a","friendly"),"friend rebind before hide")
parent:Hide()
eq(view.bound,false,"parent hide immediately invalidates binding")
eq(view.helpfulViewport.shown,false,"parent hide immediately closes independent viewport")
eq(view.helpful.enabled,false,"parent hide immediately disables native updates")
eq(A.Update(view,"party1","friend-a","friendly"),false,"hidden parent cannot reopen independent viewport")
parent:Show();parent.ancestorVisible=false
eq(A.Update(view,"party1","friend-a","friendly"),false,"hidden ancestor prevents reopening even when IsShown true")
parent.ancestorVisible=true
yes(A.Update(view,"party1","friend-a","friendly"),"visible parent rebinds normally")
parent.effectiveScale=secret
eq(A.Update(view,"party1","friend-a","friendly"),false,"unknown parent scale cannot misalign viewport")
eq(view.helpfulViewport.shown,false,"unknown scale hides independent visual")
parent.effectiveScale=1

yes(A.Update(compact,"nameplate1target","friend-a","friendly","nameplate1","enemy-a"),"child rebind")
units.nameplate1="owner-new"
eq(A.Update(compact,"nameplate1target","friend-a","friendly","nameplate1","enemy-a"),false,"owner reuse clears relation visuals")
eq(compact.helpfulViewport.shown,false,"invalid owner closes child viewport")
units.nameplate1="enemy-a"
eq(A.Update(compact,"nameplate1target","friend-a","friendly"),false,"relationship cannot bypass owner validation")
eq(A.Update(compact,"nameplate1target","friend-a",secret,"nameplate1","enemy-a"),false,"secret side rejected")
eq(A.Update(compact,"nameplate1target","friend-a","friendly",secret,"enemy-a"),false,"secret owner rejected")

yes(A.Update(view,"party1","friend-a","friendly"),"friend binds before public count race")
readHook=function() units.party1="friend-race" end
A.OnEvent("UNIT_AURA","party1")
eq(A.Scroll(view,-1),false,"identity rechecked after public fallback count")
eq(view.helpfulViewport.shown,false,"count race hides stale viewport")
readHook=nil;units.party1="friend-a"
yes(A.Update(view,"party1","friend-a","friendly"),"friend rebinds before scroll race")
scrollHook=function() units.party1="scroll-race" end
eq(A.Scroll(view,-1),false,"identity rechecked after native scrolling")
eq(view.helpfulViewport.shown,false,"scroll race closes native visuals")
scrollHook=nil;units.party1="friend-a"
yes(A.Update(view,"party1","friend-a","friendly"),"friend ready for world exit")
A.OnEvent("PLAYER_LEAVING_WORLD")
eq(view.bound,false,"world exit clears binding")
eq(view.helpfulViewport.shown,false,"world exit closes independent viewport")
eq(A.Update(view,"party1","friend-a","friendly"),false,"event tail cannot reopen after world exit")
A.OnEvent("PLAYER_ENTERING_WORLD")
yes(A.Update(view,"party1","friend-a","friendly"),"entering world allows verified view")
A.OnEvent("PLAYER_LOGOUT")
eq(A.Update(view,"party1","friend-a","friendly"),false,"logout prevents reopen")
A.OnEvent("PLAYER_ENTERING_WORLD")
nativeAvailable=false
eq(A.Create(parent,false),nil,"missing native container fails cleanly")
for _,f in ipairs(frames) do
    if f.kind=="ScrollFrame" and f.scrollChild==nil then eq(f.shown,false,"partial viewport creation cleaned up") end
end
nativeAvailable=true
eq(forbidden,0,"display never casts, changes target/focus/bindings or secure attributes")
print("Targets aura simulated checks: "..checks.."; native clipping, scrolling, secret rendering and dispel selection remain in-game checks")
