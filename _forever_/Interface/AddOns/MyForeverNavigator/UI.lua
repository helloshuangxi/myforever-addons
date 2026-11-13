local _, NS = ...

local panel, hud
local workspace, ready = "npc", false
local WIDTH, HEIGHT, MAX_ROWS, SUBCATEGORY_ROWS = 900, 600, 6, 6
local npcState = {query="",category="all",subcategory="all",sort="distance",faction="own",currentZone=false,page=1,subPage=1,filters=false,more=false}
local placeState = {query="",category="favorites",sort="distance",page=1,more=false}
local npcPage, placePage, navigationPage, npcBrowser, placeBrowser
local categories, subcategories, workspaceTabs, placeTabs = {}, {}, {}, {}
local subPrevious, subNext, subPageLabel, subTitle
local createToggle, placeForm, mapInput, xInput, yInput, nameInput, saveButton, currentButton, importButton
local formShown = false
local Style = MyForeverStyle
local function token(name, alpha) local r, g, b = Style.Color(name); return {r, g, b, alpha} end
-- Suite tokens. "gold" keeps its old name for the active/selected state, which is now the suite accent;
-- "title" is primary text, so names and headings no longer compete with the active state.
local colors = {
    surface = token("outer", Style.alpha.window), raised = token("surface", 1),
    line = token("line", 1), gold = token("accent"), title = token("text"),
    white = token("text"), muted = token("muted"), teal = token("secondary"), accent = token("accent"),
}
local factionNames = {Alliance = "联盟", Horde = "部落", Neutral = "中立", Hostile = "怪物／双方敌对"}

local function validDistance(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function relativeDirection(angle)
    if type(angle) ~= "number" or angle ~= angle or angle <= -math.huge or angle >= math.huge then return nil end
    local directions = {"前方", "右前方", "右侧", "右后方", "后方", "左后方", "左侧", "左前方"}
    -- Navigation.angle is the texture rotation, the negative of the target's
    -- clockwise angle relative to the player's facing, not a map compass point.
    local clockwise = (-angle) % (math.pi * 2)
    return directions[math.floor((clockwise + math.pi / 8) / (math.pi / 4)) % 8 + 1]
end

local function formatDistance(value, compact)
    if not validDistance(value) then return "距离未知" end
    if value >= 1000 then return string.format(compact and "%.1f公里" or "%.1f 公里", value / 1000) end
    return string.format(compact and "%d米" or "%d 米", math.floor(value + 0.5))
end

local function pointDistance(point)
    if validDistance(point.distance) then return formatDistance(point.distance, true) end
    return point.scope == "other-continent" and "跨大陆" or "距离未知"
end

local function label(parent, width, height, template, color)
    local t = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    t:SetSize(width, height)
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    t:SetWordWrap(true)
    t:SetSpacing(3)
    t:SetTextColor(unpack(color or colors.white))
    return t
end

local function backdrop(frame, fill, edge)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(unpack(fill or colors.raised))
    frame:SetBackdropBorderColor(unpack(edge or colors.line))
end

local function button(parent, caption, width, height, action)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 28)
    backdrop(b)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.07)
    b.label = label(b, width - 8, (height or 28) - 4, "GameFontNormalSmall", colors.white)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.label:SetText(caption)
    b:SetScript("OnClick", action)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    return b
end

local function input(parent, width, hint, x, y)
    local title = label(parent, width, 16, "GameFontDisableSmall", colors.muted)
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(hint)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width - 6, 26)
    box:SetPoint("TOPLEFT", x + 6, y - 18)
    box:SetAutoFocus(false)
    box:SetMaxLetters(80)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function showMessage(message)
    if message and NS.Print then NS.Print(message) end
end

local function restorePosition(frame, key, defaultX, defaultY)
    local saved = NS.DB[key] or {}
    frame:ClearAllPoints()
    frame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or defaultX, saved.y or defaultY)
end

local function drag(frame, handle, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() frame:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        NS.DB[key] = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
end

function NS.RefreshHUD()
    if not hud then return end
    local nav = NS.GetNavigation()
    if NS.RefreshNavigationPage then NS.RefreshNavigationPage(nav) end
    if not nav or not nav.point then hud:Hide(); return end
    if NS.UpdateArrival then NS.UpdateArrival(nav) end
    hud:Show()
    hud.title:SetText(nav.point.name or "目的地")
    hud.navigation = nav
    hud.distance:SetText(formatDistance(nav.distance))
    local direction = nav.mode == "direction" and relativeDirection(nav.angle) or nil
    hud.direction:SetText(direction or (nav.mode == "arrived" and "已到达" or (nav.mode == "cross" and "跨区" or "暂无朝向")))
    if direction then
        hud.arrow:Show()
        hud.arrow:SetRotation(nav.angle)
    else hud.arrow:Hide() end
end

local function createHUD()
    hud = CreateFrame("Frame", "MyForeverNavigatorHUD", UIParent, "BackdropTemplate")
    hud:SetSize(300, 84)
    hud:SetFrameStrata("MEDIUM")
    -- 0.56 / 0.12 are the opacities the user asked for on this HUD; only the hue follows the suite.
    backdrop(hud, token("outer", 0.56), token("line", 0.12))
    restorePosition(hud, "hud", 0, 180)
    local handle = CreateFrame("Frame", nil, hud)
    handle:SetPoint("TOPLEFT", 72, 0)
    handle:SetPoint("TOPRIGHT", -64, 0)
    handle:SetHeight(36)
    drag(hud, handle, "hud")
    hud.title = label(hud, 166, 22, "GameFontNormalLarge", colors.title)
    hud.title:SetPoint("TOPLEFT", 72, -9)
    hud.title:SetWordWrap(false)
    hud.map = button(hud, "地图", 48, 28, function()
        local nav = hud.navigation
        if nav and nav.point then
            local ok, reason = NS.ShowOnMap(nav.point)
            if ok then panel:Hide() else showMessage(reason) end
        end
    end)
    hud.map:SetPoint("TOPRIGHT", -8, -8)
    hud.close = button(hud, "关闭", 48, 28, function() NS.Stop(); NS.RefreshHUD(); NS.RefreshUI() end)
    hud.close:SetPoint("TOPRIGHT", -8, -45)
    for _,control in ipairs({hud.map,hud.close}) do
        control:SetBackdropColor(colors.raised[1], colors.raised[2], colors.raised[3], 0.16)
        control:SetBackdropBorderColor(colors.line[1], colors.line[2], colors.line[3], 0.18)
        control.label:SetTextColor(unpack(colors.muted))
        control.label:SetWordWrap(false)
    end
    hud.arrow = hud:CreateTexture(nil, "ARTWORK")
    hud.arrow:SetSize(50, 50)
    hud.arrow:SetPoint("TOPLEFT", 8, -4)
    hud.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    hud.arrow:SetVertexColor(unpack(colors.accent))
    hud.direction = label(hud, 64, 20, "GameFontNormal", colors.white)
    hud.direction:SetPoint("TOPLEFT", 4, -60)
    hud.direction:SetJustifyH("CENTER")
    hud.direction:SetWordWrap(false)
    hud.distance = label(hud, 166, 32, "GameFontNormalHuge", colors.white)
    hud.distance:SetPoint("TOPLEFT", 72, -39)
    hud.distance:SetWordWrap(false)
    -- Only the title drag handle and the two explicit buttons accept mouse
    -- input. The compact HUD has no auxiliary labels or hover explanations.
    hud:EnableMouse(false)
    hud.helpTarget = handle
    hud:Hide()
    NS.HUD = hud
end


local function activeButton(b, active)
    b:SetBackdropBorderColor(unpack(active and colors.gold or colors.line))
    b.label:SetTextColor(unpack(active and colors.gold or colors.white))
end

local function setWorkspace(id)
    workspace = id
    NS.RefreshUI()
end

local function categoryList()
    local all = {{id="all",label="全部 NPC"}}
    for _, category in ipairs(NS.Categories or {}) do all[#all+1]=category end
    return all
end

local function getSubcategories()
    local list = NS.Call(NS.GetSubcategories, npcState.category)
    if type(list) ~= "table" or #list == 0 then return {{id="all",label="全部",count=0}} end
    return list
end

local function updateSubcategories()
    local list = getSubcategories()
    local found = false
    for _, c in ipairs(list) do if c.id == npcState.subcategory then found=true;break end end
    if not found then npcState.subcategory="all" end
    local maximum = math.max(1,math.ceil(#list/SUBCATEGORY_ROWS))
    npcState.subPage=math.max(1,math.min(maximum,npcState.subPage))
    for i,b in ipairs(subcategories) do
        local item=list[(npcState.subPage-1)*SUBCATEGORY_ROWS+i]
        b.entry=item
        b:SetShown(item~=nil)
        if item then
            b.label:SetText(item.label.."  "..tostring(item.count or 0))
            activeButton(b,item.id==npcState.subcategory)
        end
    end
    subPrevious:SetEnabled(npcState.subPage>1)
    subNext:SetEnabled(npcState.subPage<maximum)
    subPrevious:SetShown(maximum>1);subNext:SetShown(maximum>1);subPageLabel:SetShown(maximum>1)
    subPageLabel:SetText(npcState.subPage.." / "..maximum)
    subTitle:SetText("细分 · 全阵营数量")
end

local function selectedPoint(browser)
    return browser.state.selectedID and NS.GetPoint(browser.state.selectedID)
end

local function showMore(browser)
    local details=browser.details
    local state=browser.state
    details.more.label:SetText(state.more and "收起资料" or "更多资料")
    details.extra:SetShown(state.more and selectedPoint(browser)~=nil)
end

local function refreshDetails(browser)
    local point=selectedPoint(browser)
    local d=browser.details
    d.start:SetEnabled(point~=nil);d.map:SetEnabled(point~=nil);d.favorite:SetEnabled(point~=nil)
    d.more:SetEnabled(point~=nil)
    for _, action in ipairs({d.start,d.map,d.favorite,d.more}) do action:SetShown(point~=nil) end
    d.delete:SetShown(browser.kind=="places" and point~=nil and point.category=="custom")
    if not point then
        d.name:SetText("选择一个目的地")
        d.service:SetText("")
        d.location:SetText(browser.kind=="npc" and "先选择用途分类，或搜索 NPC。" or "收藏常去的 NPC，或保存自己的地点。")
        d.info:SetText("");d.favorite.label:SetText("收藏地点")
        showMore(browser)
        return
    end
    d.name:SetText(point.name or "未命名地点")
    d.service:SetText(point.service or "自定义地点")
    d.location:SetText(string.format("%s · %.1f, %.1f\n%s",point.zone or "目标地图",point.x*100,point.y*100,factionNames[point.faction] or "自定义"))
    d.favorite.label:SetText(NS.DB.favorites[point.id] and "取消收藏" or "收藏地点")
    d.start.label:SetText(NS.DB.activeID==point.id and "继续导航" or "开始导航")
    d.info:SetText(string.format("地图 ID %d%s\n\n%s",point.mapID,point.npcID and (" · NPC "..point.npcID) or "",point.note or "暂无补充资料。"))
    local textHeight=math.max(40,d.info:GetStringHeight() or 40)
    d.info:SetHeight(textHeight)
    d.content:SetHeight(textHeight)
    d.scrollOffset=0;d.extra:SetVerticalScroll(0)
    showMore(browser)
end

local function revealPoint(browser,id)
    browser.state.selectedID=id
    browser.reveal=true
end

local function refreshBrowser(browser)
    local state=browser.state
    local options={category=state.category,sort=state.sort,faction=browser.kind=="npc" and state.faction or "all"}
    if browser.kind=="npc" then
        options.subcategory=state.subcategory
        options.currentZone=state.currentZone
        options.includeCustom=false
    end
    browser.results=NS.Search(state.query,options) or {}
    local list=browser.results
    local rows=browser.visibleRows or MAX_ROWS
    local maximum=math.max(1,math.ceil(#list/rows))
    state.page=math.max(1,math.min(state.page,maximum))
    local selectedIndex
    for i,point in ipairs(list) do if point.id==state.selectedID then selectedIndex=i;break end end
    if selectedIndex and browser.reveal then state.page=math.ceil(selectedIndex/rows) end
    browser.reveal=false
    if not selectedIndex then
        local first=list[(state.page-1)*rows+1]
        state.selectedID=first and first.id or nil
    end
    local title = string.format("%d 个%s",#list,browser.kind=="npc" and "NPC" or "地点")
    local catalogue = browser.kind=="npc" and NS.Call(NS.GetQuestieCatalogStatus)
    if catalogue then
        if catalogue.status=="ready" then title=title.." · Questie 已接入"
        elseif catalogue.status=="loading" then title=title.." · Questie 读取中"
        elseif catalogue.status=="waiting" then title=title.." · 等待 Questie"
        elseif catalogue.status=="error" then title=title.." · Questie 读取失败"
        else title=title.." · 启用 Questie 可扩展" end
    end
    browser.title:SetText(title)
    browser.pageLabel:SetText(state.page.." / "..maximum.." 页")
    browser.previous:SetEnabled(state.page>1);browser.next:SetEnabled(state.page<maximum)
    browser.sort.label:SetText(state.sort=="distance" and "最近优先" or "名称排序")
    if browser.filterToggle then
        local summary = state.currentZone and "当前区" or (state.faction == "own" and "本方" or "全部")
        browser.filterToggle.label:SetText(state.filters and "收起筛选" or ("筛选 · " .. summary))
        browser.filterBar:SetShown(state.filters)
        browser.faction.label:SetText(state.faction=="own" and "本方、中立与怪物" or "阵营：全部")
        browser.zone.label:SetText(state.currentZone and "区域：当前区域" or "区域：整个世界")
    end
    for i,row in ipairs(browser.rows) do
        local point=i<=rows and list[(state.page-1)*rows+i] or nil
        row.point=point;row:SetShown(point~=nil)
        if point then
            row.name:SetText((NS.DB.favorites[point.id] and "[收藏] " or "")..point.name)
            row.zone:SetText(point.zone or "目标地图")
            row.service:SetText(point.service or "自定义地点")
            row.distance:SetText(pointDistance(point))
            row:SetBackdropBorderColor(unpack(point.id==state.selectedID and colors.gold or colors.line))
        end
    end
    browser.empty:SetShown(#list==0)
    browser.empty:SetText(browser.kind=="npc" and "没有匹配的 NPC。\n可换一个用途或目录分类，\n也可展开筛选检查阵营与区域。"
        or (state.category=="favorites" and "还没有匹配的收藏。\n在 NPC 详情中点击「收藏地点」。" or "还没有匹配的自定义地点。\n可以新增坐标，或保存当前位置。"))
    if browser.kind=="npc" and #list==0 and catalogue and catalogue.status~="ready" then
        browser.empty:SetText("没有匹配的 NPC。\nQuestie 扩展目录尚未可用。\n请确认 Questie 与 QuestieDB 已启用并完成加载。")
    end
    refreshDetails(browser)
end

local function browserLayout(browser,height)
    browser:SetHeight(height)
    local controls=browser.kind=="npc" and (browser.state.filters and 100 or 64) or 56
    browser.listTop=controls
    browser.title:ClearAllPoints();browser.title:SetPoint("TOPLEFT",0,-controls)
    browser.visibleRows=math.max(1,math.min(MAX_ROWS,math.floor((height-controls-52)/48)))
    for i,row in ipairs(browser.rows) do
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-controls-26-(i-1)*48)
    end
    local footer=controls+26+browser.visibleRows*48
    browser.previous:ClearAllPoints();browser.previous:SetPoint("TOPLEFT",0,-footer)
    browser.next:ClearAllPoints();browser.next:SetPoint("TOPLEFT",browser.listWidth-76,-footer)
    browser.pageLabel:ClearAllPoints();browser.pageLabel:SetPoint("TOPLEFT",82,-footer-5)
    browser.empty:ClearAllPoints();browser.empty:SetPoint("TOPLEFT",8,-controls-90)
    local detailHeight=height-controls
    browser.details:ClearAllPoints();browser.details:SetPoint("TOPLEFT",browser.listWidth+16,-controls)
    browser.details:SetHeight(detailHeight)
    browser.details.extra:SetHeight(math.max(20,detailHeight-234))
end

local function createBrowser(parent,state,kind,width,listWidth)
    local browser=CreateFrame("Frame",nil,parent)
    browser:SetWidth(width);browser.state=state;browser.kind=kind;browser.listWidth=listWidth;browser.rows={}
    browser.search=input(browser,listWidth,"搜索名称 / 用途",0,0)
    browser.search:SetMaxLetters(120)
    browser.search:SetScript("OnTextChanged",function(self)
        state.query=self:GetText() or "";state.page=1;state.selectedID=nil
        if ready then NS.RefreshUI() end
    end)
    browser.sort=button(browser,"最近优先",130,28,function()
        state.sort=state.sort=="distance" and "name" or "distance";state.page=1;state.selectedID=nil;NS.RefreshUI()
    end)
    browser.sort:SetPoint("TOPLEFT",listWidth+16,-18)
    if kind=="npc" then
        browser.filterToggle=button(browser,"筛选",140,28,function()state.filters=not state.filters;NS.RefreshUI()end)
        browser.filterToggle:SetPoint("TOPRIGHT",0,-18)
        browser.filterBar=CreateFrame("Frame",nil,browser)
        browser.filterBar:SetPoint("TOPLEFT",0,-55);browser.filterBar:SetSize(width,32)
        browser.faction=button(browser.filterBar,"阵营：本方与中立",210,28,function()
            state.faction=state.faction=="own" and "all" or "own";state.page=1;state.selectedID=nil;NS.RefreshUI()
        end)
        browser.faction:SetPoint("TOPLEFT")
        browser.zone=button(browser.filterBar,"区域：整个世界",210,28,function()
            state.currentZone=not state.currentZone;state.page=1;state.selectedID=nil;NS.RefreshUI()
        end)
        browser.zone:SetPoint("TOPLEFT",226,0)
    end
    browser.title=label(browser,220,20,"GameFontNormal",colors.muted)
    for i=1,MAX_ROWS do
        local row=CreateFrame("Button",nil,browser,"BackdropTemplate")
        row:SetSize(listWidth,44);backdrop(row)
        row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8");row:GetHighlightTexture():SetVertexColor(.7,.9,.85,.1)
        row.name=label(row,listWidth-140,18,"GameFontNormalSmall",colors.white)
        row.name:SetPoint("TOPLEFT",9,-5);row.name:SetWordWrap(false)
        row.zone=label(row,120,16,"GameFontHighlightSmall",colors.muted)
        row.zone:SetPoint("TOPRIGHT",-8,-6);row.zone:SetJustifyH("RIGHT");row.zone:SetWordWrap(false)
        row.service=label(row,listWidth-118,16,"GameFontHighlightSmall",colors.muted)
        row.service:SetPoint("TOPLEFT",9,-25);row.service:SetWordWrap(false)
        row.distance=label(row,96,16,"GameFontHighlightSmall",colors.teal)
        row.distance:SetPoint("TOPRIGHT",-8,-25);row.distance:SetJustifyH("RIGHT");row.distance:SetWordWrap(false)
        row:SetScript("OnClick",function(self)if self.point then state.selectedID=self.point.id;NS.RefreshUI()end end)
        browser.rows[i]=row
    end
    browser.previous=button(browser,"上一页",76,26,function()
        state.page=math.max(1,state.page-1);state.selectedID=nil;NS.RefreshUI()
    end)
    browser.next=button(browser,"下一页",76,26,function()
        local maximum=math.max(1,math.ceil(#(browser.results or {})/(browser.visibleRows or MAX_ROWS)))
        state.page=math.min(maximum,state.page+1);state.selectedID=nil;NS.RefreshUI()
    end)
    browser.pageLabel=label(browser,listWidth-164,22,"GameFontHighlightSmall",colors.muted)
    browser.pageLabel:SetJustifyH("CENTER")
    browser.empty=label(browser,listWidth-16,110,"GameFontHighlight",colors.muted)
    browser.empty:SetJustifyH("CENTER")
    browser:EnableMouseWheel(true)
    browser:SetScript("OnMouseWheel",function(_,delta)
        if delta>0 then browser.previous:Click() else browser.next:Click() end
    end)
    local d=CreateFrame("Frame",nil,browser,"BackdropTemplate")
    browser.details=d;d:SetWidth(width-listWidth-16);backdrop(d)
    local inner=width-listWidth-40
    d.name=label(d,inner,42,"GameFontNormalLarge",colors.title);d.name:SetPoint("TOPLEFT",12,-12)
    d.service=label(d,inner,32,"GameFontHighlight",colors.white);d.service:SetPoint("TOPLEFT",12,-58)
    d.location=label(d,inner,42,"GameFontHighlightSmall",colors.teal);d.location:SetPoint("TOPLEFT",12,-96)
    local actionWidth=(inner-8)/2
    d.start=button(d,"开始导航",actionWidth,28,function()
        local point=selectedPoint(browser)
        if point then local ok,reason=NS.Start(point);if not ok then showMessage(reason)end;NS.RefreshHUD();NS.RefreshUI()end
    end)
    d.start:SetPoint("TOPLEFT",12,-146)
    -- The one primary action of this view: filled with the suite accent.
    d.start:SetBackdropColor(unpack(colors.accent));d.start:SetBackdropBorderColor(unpack(colors.accent))
    d.start.label:SetTextColor(Style.Color("onAccent"))
    d.map=button(d,"地图",actionWidth,28,function()
        local point=selectedPoint(browser)
        if point then local ok,reason=NS.ShowOnMap(point);if ok then panel:Hide()else showMessage(reason)end end
    end)
    d.map:SetPoint("TOPRIGHT",-12,-146)
    d.favorite=button(d,"收藏地点",actionWidth,26,function()
        if state.selectedID then NS.ToggleFavorite(state.selectedID);NS.RefreshUI()end
    end)
    d.favorite:SetPoint("TOPLEFT",12,-182)
    d.more=button(d,"更多资料",actionWidth,26,function()state.more=not state.more;showMore(browser)end)
    d.more:SetPoint("TOPRIGHT",-12,-182)
    d.extra=CreateFrame("ScrollFrame",nil,d)
    d.extra:SetPoint("TOPLEFT",12,-220);d.extra:SetWidth(inner)
    d.content=CreateFrame("Frame",nil,d.extra);d.content:SetWidth(inner)
    d.info=label(d.content,inner,40,"GameFontHighlightSmall",colors.muted);d.info:SetPoint("TOPLEFT")
    d.extra:SetScrollChild(d.content);d.extra:EnableMouseWheel(true)
    d.extra:SetScript("OnMouseWheel",function(_,delta)
        local maximum=math.max(0,d.content:GetHeight()-d.extra:GetHeight())
        d.scrollOffset=math.max(0,math.min(maximum,(d.scrollOffset or 0)-delta*28));d.extra:SetVerticalScroll(d.scrollOffset)
    end)
    d.delete=button(browser,"删除此自定义地点",170,26,function()
        local point=selectedPoint(browser)
        if point and point.category=="custom" then NS.RemoveCustom(point.id);state.selectedID=nil;NS.RefreshUI();NS.RefreshHUD()end
    end)
    d.delete:SetPoint("TOPRIGHT",0,-18)
    return browser
end

function NS.RefreshNavigationPage(nav)
    if not ready or workspace~="navigation" then return end
    local view=NS.UI.nav
    nav=nav or NS.GetNavigation()
    local point=nav and nav.point
    view.active:SetShown(point~=nil);view.empty:SetShown(point==nil)
    if not point then return end
    view.point=point
    view.target:SetText(point.name or "目的地")
    view.location:SetText(string.format("%s · %.1f, %.1f",point.zone or "目标地图",point.x*100,point.y*100))
    view.distance:SetText(validDistance(nav.distance) and ("直线 "..formatDistance(nav.distance)) or "距离暂不可用")
    view.status:SetText((nav.status or "正在读取位置").."\n\n"..(nav.detail or ""))
    local tracking=nav.nativeTracking and (nav.nativeKind=="quest" and "原生任务追踪已开启" or "原生航点追踪已开启") or (nav.nativeReason or "使用独立方向指引")
    view.tracking:SetText(tracking)
end

function NS.RefreshUI()
    if not ready then return end
    npcPage:SetShown(workspace=="npc");placePage:SetShown(workspace=="places");navigationPage:SetShown(workspace=="navigation")
    placeForm:SetShown(workspace=="places" and formShown)
    for id,b in pairs(workspaceTabs)do activeButton(b,id==workspace)end
    if workspace=="npc" then
        updateSubcategories()
        for _,b in ipairs(categories)do activeButton(b,b.category==npcState.category)end
        browserLayout(npcBrowser,478);refreshBrowser(npcBrowser)
        NS.UI.search,NS.UI.rows,NS.UI.details=npcBrowser.search,npcBrowser.rows,npcBrowser.details
        NS.UI.moreToggle=npcBrowser.details.more
    elseif workspace=="places" then
        for id,b in pairs(placeTabs)do activeButton(b,id==placeState.category)end
        placeForm:SetShown(formShown)
        createToggle.label:SetText(formShown and "收起新增" or "新增地点")
        local top=formShown and 168 or 82
        placeBrowser:ClearAllPoints();placeBrowser:SetPoint("TOPLEFT",0,-top)
        browserLayout(placeBrowser,478-top);refreshBrowser(placeBrowser)
        NS.UI.search,NS.UI.rows,NS.UI.details=placeBrowser.search,placeBrowser.rows,placeBrowser.details
        NS.UI.moreToggle=placeBrowser.details.more
    else NS.RefreshNavigationPage()end
    NS.UI.workspace=workspace
end

local function selectPlace(point)
    placeState.category="custom";placeState.query="";placeState.page=1;placeState.more=false
    placeBrowser.search:SetText("")
    revealPoint(placeBrowser,point.id)
    NS.RefreshUI()
end

function NS.CreateUI()
    if panel then return end
    panel=CreateFrame("Frame","MyForeverNavigatorPanel",UIParent,"BackdropTemplate")
    panel:SetSize(WIDTH,HEIGHT);panel:SetFrameStrata("HIGH");panel:EnableMouse(true);backdrop(panel,colors.surface)
    local scale=math.min(1,(UIParent:GetWidth()-30)/WIDTH,(UIParent:GetHeight()-30)/HEIGHT)
    panel:SetScale(math.max(.55,scale));restorePosition(panel,"panel",0,0)
    local header=CreateFrame("Frame",nil,panel);header:SetPoint("TOPLEFT");header:SetPoint("TOPRIGHT",-36,0);header:SetHeight(40);drag(panel,header,"panel")
    local title=label(panel,700,26,"GameFontNormalLarge",colors.title);title:SetPoint("TOPLEFT",18,-12);title:SetText("世界向导")
    local close=Style.CloseButton(panel,function()panel:Hide()end);close:SetPoint("TOPRIGHT",-8,-10)
    for i,item in ipairs({{"npc","找 NPC"},{"places","我的地点"},{"navigation","当前导航"}})do
        local id=item[1]
        local b=button(panel,item[2],150,32,function()setWorkspace(id)end);b:SetPoint("TOPLEFT",18+(i-1)*162,-54)
        workspaceTabs[id]=b
    end
    npcPage=CreateFrame("Frame",nil,panel);npcPage:SetPoint("TOPLEFT",18,-104);npcPage:SetSize(864,478)
    placePage=CreateFrame("Frame",nil,panel);placePage:SetPoint("TOPLEFT",18,-104);placePage:SetSize(864,478)
    navigationPage=CreateFrame("Frame",nil,panel);navigationPage:SetPoint("TOPLEFT",18,-104);navigationPage:SetSize(864,478)
    local purpose=label(npcPage,152,20,"GameFontNormalSmall",colors.muted);purpose:SetPoint("TOPLEFT");purpose:SetText("NPC 用途")
    local purposes=categoryList()
    local purposeHeight,purposeStep=28,32
    if #purposes > 6 then purposeHeight,purposeStep=24,27 end
    local compactSidebar = #purposes > 7
    local purposeTop = compactSidebar and 24 or 26
    if compactSidebar then purposeStep=26 end
    local purposeBottom=purposeTop+(#purposes-1)*purposeStep+purposeHeight
    local subTitleTop=purposeBottom+(compactSidebar and 8 or 12)
    local subStart=subTitleTop+(compactSidebar and 22 or 26)
    local subStep=28
    local subPagerTop=subStart+(SUBCATEGORY_ROWS-1)*subStep+24+(compactSidebar and 8 or 14)
    for i,c in ipairs(purposes)do
        local id=c.id
        local b=button(npcPage,c.label,152,purposeHeight,function()
            npcState.category=id;npcState.subcategory="all";npcState.subPage=1;npcState.page=1;npcState.selectedID=nil;npcState.more=false;NS.RefreshUI()
        end)
        b:SetPoint("TOPLEFT",0,-purposeTop-(i-1)*purposeStep);b.category=id;categories[#categories+1]=b
    end
    subTitle=label(npcPage,152,18,"GameFontHighlightSmall",colors.muted);subTitle:SetPoint("TOPLEFT",0,-subTitleTop)
    for i=1,SUBCATEGORY_ROWS do
        local b=button(npcPage,"",152,24,function(self)
            if self.entry then npcState.subcategory=self.entry.id;npcState.page=1;npcState.selectedID=nil;npcState.more=false;NS.RefreshUI()end
        end)
        b:SetPoint("TOPLEFT",0,-subStart-(i-1)*subStep);subcategories[i]=b
    end
    subPrevious=button(npcPage,"上页",44,24,function()npcState.subPage=math.max(1,npcState.subPage-1);updateSubcategories()end)
    subPrevious:SetPoint("TOPLEFT",0,-subPagerTop)
    subNext=button(npcPage,"下页",44,24,function()npcState.subPage=npcState.subPage+1;updateSubcategories()end)
    subNext:SetPoint("TOPLEFT",108,-subPagerTop)
    subPageLabel=label(npcPage,56,20,"GameFontHighlightSmall",colors.muted);subPageLabel:SetPoint("TOPLEFT",48,-subPagerTop-5);subPageLabel:SetJustifyH("CENTER")
    local hint=label(npcPage,152,18,"GameFontHighlightSmall",colors.muted);hint:SetPoint("BOTTOMLEFT",0,0);hint:SetText("Esc 关闭窗口")
    npcBrowser=createBrowser(npcPage,npcState,"npc",698,380);npcBrowser:SetPoint("TOPLEFT",166,0)
    for i,item in ipairs({{"favorites","收藏地点"},{"custom","自定义地点"}})do
        local id=item[1]
        local b=button(placePage,item[2],150,30,function()placeState.category=id;placeState.page=1;placeState.selectedID=nil;placeState.more=false;NS.RefreshUI()end)
        b:SetPoint("TOPLEFT",(i-1)*162,0);placeTabs[id]=b
    end
    createToggle=button(placePage,"新增地点",132,28,function()formShown=not formShown;NS.RefreshUI()end)
    createToggle:SetPoint("TOPLEFT",0,-42)
    currentButton=button(placePage,"保存当前位置",154,28,function()
        local point,reason=NS.SaveCurrent(formShown and nameInput:GetText() or "")
        if point then formShown=false;selectPlace(point)else showMessage(reason)end
    end)
    currentButton:SetPoint("TOPLEFT",146,-42)
    importButton=button(placePage,"导入地图标记",154,28,function()
        if type(NS.ImportWaypoint)~="function"then showMessage("当前无法读取地图标记。");return end
        local point,reason=NS.ImportWaypoint()
        if not point then showMessage(reason);return end
        local ok,startReason=NS.Start(point)
        if not ok then showMessage(startReason);return end
        formShown=false;selectPlace(point);NS.RefreshHUD()
    end)
    importButton:SetPoint("TOPLEFT",314,-42)
    placeForm=CreateFrame("Frame",nil,placePage,"BackdropTemplate");placeForm:SetPoint("TOPLEFT",0,-82);placeForm:SetSize(864,74);backdrop(placeForm)
    mapInput=input(placeForm,86,"地图 ID",12,-8);mapInput:SetMaxLetters(6)
    xInput=input(placeForm,72,"X %",112,-8);xInput:SetMaxLetters(8)
    yInput=input(placeForm,72,"Y %",198,-8);yInput:SetMaxLetters(8)
    nameInput=input(placeForm,350,"地点名称",284,-8)
    saveButton=button(placeForm,"保存地点",192,28,function()
        local point,reason=NS.AddCustom(nameInput:GetText(),tonumber(mapInput:GetText()),(tonumber(xInput:GetText())or -100)/100,(tonumber(yInput:GetText())or -100)/100)
        if point then formShown=false;nameInput:ClearFocus();selectPlace(point)else showMessage(reason)end
    end)
    saveButton:SetPoint("TOPRIGHT",-12,-27)
    local boxes={mapInput,xInput,yInput,nameInput}
    for i,box in ipairs(boxes)do
        local nextBox=boxes[i%#boxes+1]
        box:SetScript("OnTabPressed",function(self)self:ClearFocus();nextBox:SetFocus()end)
    end
    placeBrowser=createBrowser(placePage,placeState,"places",864,536)
    local nav={}
    nav.empty=CreateFrame("Frame",nil,navigationPage);nav.empty:SetAllPoints(navigationPage)
    local emptyTitle=label(nav.empty,600,32,"GameFontNormalLarge",colors.title);emptyTitle:SetPoint("TOPLEFT",24,-70);emptyTitle:SetText("还没有导航目的地")
    local emptyText=label(nav.empty,700,64,"GameFontHighlight",colors.muted);emptyText:SetPoint("TOPLEFT",24,-118);emptyText:SetText("先在「找 NPC」选择一个目的地，\n或到「我的地点」保存坐标、导入地图标记。")
    nav.find=button(nav.empty,"去找 NPC",180,32,function()setWorkspace("npc")end);nav.find:SetPoint("TOPLEFT",24,-206)
    nav.active=CreateFrame("Frame",nil,navigationPage,"BackdropTemplate");nav.active:SetAllPoints(navigationPage);backdrop(nav.active)
    nav.target=label(nav.active,816,40,"GameFontNormalLarge",colors.title);nav.target:SetPoint("TOPLEFT",24,-24)
    nav.location=label(nav.active,816,28,"GameFontHighlight",colors.teal);nav.location:SetPoint("TOPLEFT",24,-78)
    nav.distance=label(nav.active,816,40,"GameFontNormalLarge",colors.white);nav.distance:SetPoint("TOPLEFT",24,-120)
    nav.status=label(nav.active,816,160,"GameFontHighlight",colors.white);nav.status:SetPoint("TOPLEFT",24,-182)
    nav.tracking=label(nav.active,816,40,"GameFontHighlightSmall",colors.muted);nav.tracking:SetPoint("TOPLEFT",24,-350)
    nav.resume=button(nav.active,"继续指引",180,34,function()
        local point=NS.GetPoint(NS.DB.activeID)
        if point then local ok,reason=NS.Start(point);if not ok then showMessage(reason)end;NS.RefreshHUD();NS.RefreshNavigationPage()end
    end)
    nav.resume:SetPoint("BOTTOMLEFT",24,24)
    nav.map=button(nav.active,"地图",180,34,function()
        local point=NS.GetPoint(NS.DB.activeID)
        if point then local ok,reason=NS.ShowOnMap(point);if ok then panel:Hide()else showMessage(reason)end end
    end)
    nav.map:SetPoint("BOTTOMLEFT",220,24)
    nav.stop=button(nav.active,"停止导航",180,34,function()NS.Stop();NS.RefreshHUD();NS.RefreshNavigationPage()end)
    nav.stop:SetPoint("BOTTOMLEFT",416,24)
    panel:SetScript("OnShow",function()
        local mapID=NS.GetPlayerPosition()
        if mapInput:GetText()==""and mapID then mapInput:SetText(tostring(mapID))end
        NS.RefreshUI()
    end)
    UISpecialFrames=UISpecialFrames or {};table.insert(UISpecialFrames,"MyForeverNavigatorPanel")
    panel:Hide();createHUD()
    NS.Panel=panel
    NS.UI={panel=panel,hud=hud,workspaceTabs=workspaceTabs,npcCategories=categories,subcategories=subcategories,
        subPrevious=subPrevious,subNext=subNext,subPageLabel=subPageLabel,subTitle=subTitle,sidebarHint=hint,placeTabs=placeTabs,
        createToggle=createToggle,form=placeForm,filterToggle=npcBrowser.filterToggle,
        npcBrowser=npcBrowser,placeBrowser=placeBrowser,npcPage=npcPage,placePage=placePage,navigationPage=navigationPage,
        nav=nav,mapInput=mapInput,xInput=xInput,yInput=yInput,nameInput=nameInput,save=saveButton,current=currentButton,import=importButton,
        faction=npcBrowser.faction,zone=npcBrowser.zone,sort=npcBrowser.sort}
    panel.controls=NS.UI
    ready=true;NS.RefreshUI()
end

function NS.ToggleUI(forceVisible)
    if not panel then NS.CreateUI()end
    if forceVisible==true then panel:Show()elseif forceVisible==false then panel:Hide()
    elseif panel:IsShown()then panel:Hide()else panel:Show()end
end

function NS.SetSearch(value)
    NS.ToggleUI(true)
    workspace="npc";npcState.category="all";npcState.subcategory="all";npcState.subPage=1;npcState.page=1;npcState.selectedID=nil;npcState.more=false;npcState.currentZone=false
    npcBrowser.search:SetText(type(value)=="string"and value or "")
    NS.RefreshUI()
end
