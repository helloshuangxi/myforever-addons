-- Lua 5.1 UI/library contracts; these checks are not in-game validation.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local methods = {}
local function frame(kind, name, parent)
    return setmetatable({kind=kind,parent=parent,scripts={},shown=true}, {__index=methods})
end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetParent(p) self.parent=p end
function methods:SetPoint(...) self.point={...} end
function methods:ClearAllPoints() self.point=nil end
function methods:SetAllPoints(p) self.allPoints=p end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:SetTexture(t) self.texture=t end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetText(t) self.text=t end
function methods:SetShown(v) self.shown=v end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:Show() self.shown=true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:CreateTexture() return frame("Texture",nil,self) end
function methods:CreateFontString() return frame("FontString",nil,self) end
function methods:SetFrameStrata(v) self.strata=v end
function methods:GetFrameStrata() return "HIGH" end
function methods:SetAlpha(value) self.alpha=value end
function methods:CreateAnimationGroup()
    self.animationGroup=frame("AnimationGroup",nil,self)
    self.animationGroup.animations={}
    return self.animationGroup
end
function methods:CreateAnimation(kind)
    local animation=frame(kind,nil,self)
    self.animations[#self.animations+1]=animation
    return animation
end
function methods:SetLooping(value) self.looping=value end
function methods:SetFromAlpha(value) self.fromAlpha=value end
function methods:SetToAlpha(value) self.toAlpha=value end
function methods:SetDuration(value) self.duration=value end
function methods:SetOrder(value) self.order=value end
function methods:SetSmoothing(value) self.smoothing=value end
function methods:IsPlaying() return self.playing==true end
function methods:Play() self.playing=true;self.plays=(self.plays or 0)+1 end
function methods:Stop() self.playing=false;if self.scripts.OnStop then self.scripts.OnStop(self) end end
for _,name in ipairs({"EnableMouse","RegisterForClicks","SetTexCoord","SetJustifyH","SetTextColor"}) do methods[name]=function() end end
UIParent=frame("Frame")
WorldMapFrame=frame("Frame",nil,UIParent)
CreateFrame=frame
GameTooltip={
    SetOwner=function(self,v) self.owner=v end,
    IsOwned=function(self,v) return self.owner==v end,
    SetText=function(self,v) self.title=v;self.lines={} end,
    AddLine=function(self,v) self.lines[#self.lines+1]=v end,
    Show=function(self) self.shown=true end,
    Hide=function(self) self.shown=false end,
}
local ns={}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/API.lua"))("MyForeverProfessions",ns)
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/TrainerPins.lua"))("MyForeverProfessions",ns)
local ids={171,164,333,202,165,197,182,186,393,185,129,356}
local textures={}
for _,id in ipairs(ids) do
    local icon=ns.ProfessionIcon(id)
    eq(type(icon),"string","profession fallback path "..id)
    eq(textures[icon],nil,"unique profession fallback "..id)
    textures[icon]=true
end
eq(ns.ProfessionIcon(186,12345),12345,"provided icon preferred")
C_Spell={GetSpellInfo=function() return {iconID=54321} end}
eq(ns.ProfessionIcon(186),54321,"live native skill icon preferred")
C_Spell=nil
local data={
    [186]={npcID=10,name="矿工",mapName="丹莫罗",mapID=1426,x=.6932,y=.5546},
    [185]={npcID=11,name="厨师",mapName="丹莫罗",mapID=1426,x=.4767,y=.5231},
    [129]={npcID=12,name="医师",mapName="丹莫罗",mapID=1426,x=.4718,y=.5261},
    [356]={npcID=13,name="渔夫",mapName="丹莫罗",mapID=1426,x=.3548,y=.4022},
}
local professions={{id=186,name="采矿"},{id=185,name="烹饪"},{id=129,name="急救",unlearned=true},{id=356,name="钓鱼",unlearned=true}}
ns.GetNearbyTrainer=function(id) return data[id] end
local clicks,messages=0,{}
ns.Print=function(message) messages[#messages+1]=message end
ns.ShowTrainerOnMap=function(record,iconsOnly)
    clicks=clicks+1
    eq(iconsOnly,true,"map icon clicks never add a second native waypoint")
    return true,"icons"
end
eq(ns.UpdateTrainerPins(professions,185),false,"no library graceful fallback")
eq(ns.HasTrainerPin(185),false,"no library cannot claim an available pin")
local adds,removals,registered,owned=0,0,{},nil
local standard={}
function standard:AddWorldMapIconMap(owner,anchor,mapID,x,y,flag,frameLevel)
    adds=adds+1;owned=owner
    eq(flag,2,"zones and continents only")
    eq(mapID,1426,"UI map ID forwarded")
    eq(frameLevel,nil,"ordinary HBD map layer without elevated overlay")
    local wrapper=frame("Frame",nil,WorldMapFrame)
    anchor:SetParent(wrapper)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER",wrapper,"CENTER")
    anchor:Show()
    registered[#registered+1]={anchor=anchor,mapID=mapID,x=x,y=y}
    return true
end
function standard:RemoveAllWorldMapIcons(owner)
    removals=removals+1
    if owned then eq(owner,owned,"remove only own registry") end
    registered={}
end
local coordinateReady=true
local coordinates={GetWorldCoordinatesFromZone=function(_,x,y,id)
    if coordinateReady then return x*1000,y*1000,0 end
end}
local available={ ["HereBeDragons-Pins-2.0"]=standard,["HereBeDragons-2.0"]=coordinates }
LibStub={GetLibrary=function(_,name) return available[name] end}
local ok,count=ns.UpdateTrainerPins(professions,185)
eq(ok,true,"late library initializes")
eq(count,4,"learned and unlearned secondary professions included")
eq(#registered,3,"nearby cooking and first aid share one anchor")
eq(ns.HasTrainerPin(185),true,"registered button is available")
eq(ns.HasTrainerPin(171),false,"absent profession does not claim a pin")
eq(clicks,0,"refresh never replaces native waypoint")
local function buttons()
    local result={}
    for _,entry in ipairs(registered) do
        for _,button in ipairs(entry.anchor.buttons) do
            if button.shown then result[button.professionID]=button end
        end
    end
    return result
end
local byID=buttons()
eq(byID[185].parent,byID[129].parent,"adjacent professions share anchor")
eq(byID[185].point[4]~=byID[129].point[4],true,"adjacent icons have distinct screen offsets")
eq(byID[185].point[2],byID[185].parent,"offset is on child rather than HBD-owned anchor")
eq(byID[185].record.x,.4767,"cooking retains exact coordinate")
eq(byID[129].record.x,.4718,"first aid retains its own exact coordinate")
eq(byID[186].parent.strata,"HIGH","icons remain in world map strata")
eq(byID[185].width,28,"selected icon keeps original size")
eq(byID[129].width,28,"unselected icon has same size")
eq(byID[185].label,nil,"no label overlays the icon")
eq(byID[185].border,nil,"no selected gold frame overlays the icon")
eq(byID[185].blink:IsPlaying(),true,"only selected profession blinks")
eq(byID[129].blink:IsPlaying(),false,"other professions stay static")
eq(byID[185].blink.looping,"REPEAT","animation loops natively")
eq(byID[185].blink.animations[1].toAlpha,.45,"blink never fully disappears")
eq(byID[185].blink.animations[2].toAlpha,1,"blink returns to full alpha")
eq(byID[185].blink.animations[1].duration+byID[185].blink.animations[2].duration,1.6,"slow 1.6 second pulse")
eq(byID[185].scripts.OnUpdate,nil,"no per-frame Lua animation")
byID[129].scripts.OnEnter(byID[129])
eq(GameTooltip.title,"急救训练师","tooltip identifies profession")
eq(GameTooltip.lines[2],"丹莫罗 47.2, 52.6","tooltip uses precise trainer coordinates")
eq(GameTooltip.lines[3],"尚未学习该专业","unlearned indication")
eq(GameTooltip.lines[4],"点击闪烁定位","tooltip describes blinking instead of placing another point")
byID[129].scripts.OnClick(byID[129])
eq(clicks,1,"icon click opens native trainer location")
eq(byID[129].blink:IsPlaying(),true,"click blinks chosen profession")
eq(byID[185].blink:IsPlaying(),false,"previous selection stops blinking")
eq(byID[185].alpha,1,"previous selection returns to full visibility")
eq(#messages,0,"successful icons-only opening does not emit unnecessary messages")
local showTrainer=ns.ShowTrainerOnMap
ns.ShowTrainerOnMap=function() return false,"已标记训练师，但地图暂时无法打开" end
byID[129].scripts.OnClick(byID[129])
eq(messages[#messages],"已标记训练师，但地图暂时无法打开","map icon reports partial failure")
ns.ShowTrainerOnMap=function() return true,"map" end
byID[129].scripts.OnClick(byID[129])
eq(messages[#messages],"已打开丹莫罗地图，请按 47.2, 52.6 查找训练师。","map-only outcome prints exact coordinates")
ns.ShowTrainerOnMap=function() error("map unavailable") end
byID[129].scripts.OnClick(byID[129])
eq(messages[#messages],"暂时无法打开地图","unexpected map error is contained and explained")
ns.ShowTrainerOnMap=showTrainer
local blinkPlays=byID[129].blink.plays
ns.UpdateTrainerPins(professions,185)
eq(byID[129].blink:IsPlaying(),true,"periodic panel refresh preserves directly selected map icon")
eq(byID[129].blink.plays,blinkPlays,"periodic refresh does not restart ongoing pulse")
local oldAdds,oldRemovals=adds,removals
ns.UpdateTrainerPins(professions,186)
eq(adds,oldAdds,"unchanged records do not rebuild every refresh")
eq(removals,oldRemovals,"unchanged records do not clear map pins")
eq(byID[186].blink:IsPlaying(),true,"panel selection starts corresponding pulse")
eq(byID[129].blink:IsPlaying(),false,"panel selection stops previous pulse")
byID[186]:Hide()
eq(byID[186].blink:IsPlaying(),false,"hidden icon stops animation")
eq(byID[186].alpha,1,"hidden icon resets alpha")
byID[186]:Show()
eq(byID[186].blink:IsPlaying(),true,"showing selected icon restarts pulse")
WorldMapFrame:Hide()
eq(ns.IsTrainerPinVisible(186),false,"a registered pin is invisible when the map is closed")
local hiddenPlays=byID[186].blink.plays
ns.UpdateTrainerPins(professions,186)
eq(byID[186].blink:IsPlaying(),false,"periodic refresh does not animate a hidden map")
eq(byID[186].blink.plays,hiddenPlays,"hidden parent never starts a new animation")
WorldMapFrame:Show()
eq(ns.IsTrainerPinVisible(186),true,"visible pin can be toggled off by a repeated lookup")
ns.UpdateTrainerPins(professions,186)
eq(byID[186].blink:IsPlaying(),true,"visible map resumes selected pulse")
data[185].x=.8
ns.UpdateTrainerPins(professions,186)
eq(#registered,4,"moving trainer updates clustering")
eq(removals,oldRemovals+1,"coordinate change clears old owned pins once")
ns.UpdateTrainerPins({professions[1]},186)
eq(#registered,1,"removed professions lose pins")
eq(buttons()[129],nil,"unlearned secondary only shown when supplied")
ns.ClearTrainerPins()
eq(#registered,0,"explicit clear removes owned pins")
eq(ns.HasTrainerPin(186),false,"cleared icon no longer reported available")
eq(ns.IsTrainerPinVisible(186),false,"cleared icon cannot be toggled off again")
eq(byID[186].blink:IsPlaying(),false,"clearing stops pooled animation")
eq(byID[186].alpha,1,"clearing restores pooled alpha")
local fork={AddWorldMapIconMap=function(self,...) standard.AddWorldMapIconMap(self,...);return nil end,
    RemoveAllWorldMapIcons=standard.RemoveAllWorldMapIcons}
available["HereBeDragons-Pins-2.0"]=nil
available["HereBeDragons-2.0"]=nil
available["HereBeDragonsQuestie-Pins-2.0"]=fork
available["HereBeDragonsQuestie-2.0"]=coordinates
ok,count=ns.UpdateTrainerPins(professions,185)
eq(ok,true,"Questie fork nil success supported")
eq(count,4,"Questie fork produces all profession buttons")
coordinateReady=false
data[185].x=.7
ok,count=ns.UpdateTrainerPins(professions,185)
eq(ok,false,"uninitialized coordinates are retryable")
eq(count,0,"failed conversion produces no fake pins")
coordinateReady=true
ok,count=ns.UpdateTrainerPins(professions,185)
eq(ok,true,"coordinate readiness retries without reload")
eq(count,4,"coordinates recover all records")
data[185].x=0/0
ns.UpdateTrainerPins(professions,185)
eq(buttons()[185],nil,"invalid coordinates skipped")
eq(ns.HasTrainerPin(185),false,"invalid coordinates cannot claim a pin")
available={}
eq(ns.UpdateTrainerPins(professions),false,"library loss clears gracefully")
eq(#registered,0,"library loss removes previous pins")
print("MyForeverProfessions trainer pins: "..checks.." simulated checks passed")
