-- Private visual-layout harness. Executes real UI.lua; does not reproduce its logic.
-- Font measurements come from Pillow, not the WoW client. No game APIs are called.
unpack = table.unpack or unpack
local M = {}
MOCK_FRAMES = {}
local function frame(kind, name, parent, template)
    local f = setmetatable({id=#MOCK_FRAMES+1, kind=kind, name=name, parent=parent,
        template=template, scripts={}, shown=true, width=0, height=0, scale=1,
        alpha=1, scroll=0, points={}, fontSize=template == "GameFontNormal" and 14 or 12,
        justifyH="LEFT", justifyV="TOP", spacing=0, textColor={1,1,1,1}}, {__index=M})
    MOCK_FRAMES[#MOCK_FRAMES+1] = f
    if name then _G[name]=f end
    return f
end
function M:SetScript(event, fn) self.scripts[event]=fn end
function M:GetScript(event) return self.scripts[event] end
function M:HookScript(event, fn)
    local previous=self.scripts[event]
    self.scripts[event]=function(...) if previous then previous(...) end; fn(...) end
end
function M:SetSize(w,h) self.width,self.height=w,h end
function M:SetWidth(w) self.width=w end
function M:SetHeight(h) self.height=h end
function M:GetWidth() return self.width end
function M:GetHeight() return self.height end
function M:SetPoint(point, a,b,c,d)
    local relative, relativePoint, x,y
    if type(a)=="number" or a==nil then relative,relativePoint,x,y=self.parent,point,a or 0,b or 0
    elseif type(a)=="table" then
        relative=a
        if type(b)=="string" then relativePoint,x,y=b,c or 0,d or 0
        else relativePoint,x,y=point,b or 0,c or 0 end
    elseif type(a)=="string" and _G[a] then relative,relativePoint,x,y=_G[a],b or point,c or 0,d or 0
    else error("Unsupported SetPoint arguments: "..tostring(point)..", "..tostring(a)) end
    for i,p in ipairs(self.points) do if p.point==point then table.remove(self.points,i); break end end
    self.points[#self.points+1]={point=point, relative=relative, relativePoint=relativePoint,x=x,y=y}
end
function M:GetPoint(i)
    local p=self.points[i or 1]
    if p then return p.point,p.relative,p.relativePoint,p.x,p.y end
    return "CENTER",UIParent,"CENTER",0,0
end
function M:ClearAllPoints() self.points={}; self.allPoints=nil end
function M:SetAllPoints(target) self.allPoints=target or self.parent end
function M:SetText(value) self.text=tostring(value or "") end
function M:GetText() return self.text end
function M:GetFont() return "mock-system-cjk-font",self.fontSize,"" end
function M:SetFont(path,size,flags) self.fontPath,self.fontSize,self.fontFlags=path,size,flags end
function M:GetStringHeight() return py_text_height(self.text or "",self.width,self.fontSize,self.spacing,self.wordWrap~=false) end
function M:GetStringWidth() return py_text_width(self.text or "",self.fontSize) end
function M:SetJustifyH(v) self.justifyH=v end
function M:SetJustifyV(v) self.justifyV=v end
function M:SetWordWrap(v) self.wordWrap=v end
function M:SetSpacing(v) self.spacing=v end
function M:SetTextColor(...) self.textColor={...} end
function M:SetAlpha(v) self.alpha=v end
function M:SetVertexColor(...) self.vertexColor={...} end
function M:SetColorTexture(...) self.colorTexture={...} end
function M:SetTexture(v) self.texture=v end
function M:SetTexCoord(...) self.texCoord={...} end
function M:CreateFontString(name,layer,template)
    local f=frame("FontString",name,self,template); f.layer=layer; return f
end
function M:CreateTexture(name,layer,template,sublayer)
    local f=frame("Texture",name,self,template); f.layer,f.sublayer=layer,sublayer; return f
end
function M:SetHighlightTexture(texture)
    self.highlight=frame("Texture",nil,self); self.highlight.texture=texture; self.highlight.shown=false
end
function M:GetHighlightTexture() return self.highlight end
function M:SetNormalTexture(texture)
    self.normal=frame("Texture",nil,self); self.normal.texture=texture; self.normal:SetAllPoints()
end
function M:GetNormalTexture() return self.normal end
function M:SetPushedTexture(texture)
    self.pushed=frame("Texture",nil,self); self.pushed.texture=texture; self.pushed.shown=false
end
function M:SetThumbTexture(texture)
    self.thumb=frame("Texture",nil,self); self.thumb.texture=texture
    self.thumb:SetPoint("TOP",0,0)
end
function M:GetThumbTexture() return self.thumb end
function M:SetVerticalScroll(v) self.scroll=v end
function M:GetVerticalScroll() return self.scroll end
function M:SetScrollChild(child) self.child=child; child.scrollChild=true end
function M:SetMinMaxValues(a,b) self.min,self.max=a,b end
function M:SetValue(v) self.value=v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end end
function M:GetValue() return self.value or 0 end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:IsShown() return self.shown end
function M:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function M:Show() local changed=not self.shown; self.shown=true; if changed and self.scripts.OnShow then self.scripts.OnShow(self) end end
function M:Hide() local changed=self.shown; self.shown=false; if changed and self.scripts.OnHide then self.scripts.OnHide(self) end end
function M:SetScale(v) self.scale=v end
function M:GetScale() return self.scale end
function M:GetEffectiveScale() return self.scale*(self.parent and self.parent:GetEffectiveScale() or 1) end
-- Geometry is resolved after export. These two are only used on scale changes;
-- scenarios set their scale before UI construction, avoiding simulated drag geometry.
function M:GetLeft() return 0 end
function M:GetTop() return self.height end
function M:SetClampedToScreen(v) self.clamped=v end
function M:SetBackdrop(v) self.backdrop=v end
function M:SetBackdropColor(...) self.backdropColor={...} end
function M:SetBackdropBorderColor(...) self.backdropBorderColor={...} end
function M:StartMoving() self.moving=true end
function M:StopMovingOrSizing() self.moving=false end
function M:EnableMouse(v) self.mouse=v end
for _,name in ipairs({"SetMovable","EnableMouseWheel","SetFrameStrata","RegisterForDrag","SetOrientation","SetValueStep","SetResizable","SetResizeBounds","RegisterForClicks"}) do
    M[name]=function(self,...) self[name.."Args"]={...} end
end
CreateFrame=frame
UIParent=frame("Frame","UIParent")
UIParent:SetSize(MOCK_WIDTH,MOCK_HEIGHT)
UISpecialFrames={}
GetCursorPosition=function() return 0,0 end
IsControlKeyDown=function() return false end
IsShiftKeyDown=function() return false end
IsMouseButtonDown=function() return false end
GetCurrentKeyBoardFocus=function() return nil end
GameTooltip={SetOwner=function(self,v) self.owner=v end,IsOwned=function(self,v) return self.owner==v end,
    SetText=function() end,AddLine=function() end,Show=function() end,
    Hide=function(self) self.owner=nil end,SetHyperlink=function() end}
C_Item={GetItemInfo=function() return nil end}
SetItemRef=function() end

function MockNamespace(scale, scene)
    local ns={db={shown=true,collapsed=false,locked=false,scale=scale,point="TOPLEFT",relativePoint="TOPLEFT",x=32/scale,y=-72/scale},
        detectReady=true, professions={},OpenProfession=function() end, Refresh=function() end,GatherCommand=function() end,
        Print=function() end, GatheringAdvice=function() return "资源颜色以游戏显示为准。" end,
        GetNearbyTrainer=function(id) return {name=id==186 and "布罗克·寻石者" or "长名字训练师示例",mapName="丹莫罗",mapID=1426,x=.477,y=.523} end,
        ProfessionIcon=function(id) return "Interface\\Icons\\Trade_Mining" end}
    ns.professions={
        {id=171,name="炼金术",rank=45,maxRank=75,cacheState="fresh",kind="crafting",icon="Interface\\Icons\\Trade_Alchemy",recipes={
            {id=1,name="初级治疗药水",difficulty="orange",craftable=0,reagentsComplete=true,reagents={
                {name="宁神花",itemID=2447,required=2,owned=1,missing=1},
                {name="银叶草",itemID=765,required=1,owned=4,missing=0},
                {name="空瓶",itemID=3371,required=1,owned=6,missing=0}}},
            {id=2,name="超长中文训练项目名称用于检查自然换行与材料区域是否发生遮挡",difficulty="yellow",craftable=1,reagentsComplete=true,reagents={
                {required=2,options={{name="用于检查自然换行的特别长中文材料名称以及带有括号链接的替代材料测试示例",itemID=2770,owned=1,missing=1},{name="锡矿石",itemID=2771,owned=4,missing=0}}}}},
            {id=3,name="初级防御药剂",difficulty="green",craftable=3,reagentsComplete=true,reagents={
                {name="银叶草",itemID=765,required=1,owned=4,missing=0}}}}},
        {id=186,name="采矿",rank=32,maxRank=75,cacheState="fresh",kind="gathering",icon="Interface\\Icons\\Trade_Mining",recipes={
            {id=10,name="铜矿脉",difficulty="orange",isGatheringRecipe=true,currentRecipeExperience=2,nextLevelRecipeExperience=5,reagents={}},
            {id=11,name="锡矿脉",difficulty="yellow",isGatheringRecipe=true,reagents={}},
            {id=12,name="劣质石头",difficulty="green",isGatheringRecipe=true,reagents={}}}},
        {id=185,name="烹饪",unlearned=true,recipes={}},
        {id=129,name="急救",rank=25,maxRank=75,cacheState="fresh",kind="crafting",recipes={}}}
    return ns
end
