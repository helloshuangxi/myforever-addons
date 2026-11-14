local _, NS = ...
-- Shared layout hooks (grid while dragging, snap on release, /myui tags).
local function mfLayout(name, ...)
    local S = rawget(_G, "MyForeverStyle")
    local fn = type(S) == "table" and rawget(S, name)
    if type(fn) == "function" then
        local ok, result = pcall(fn, ...)
        return ok and result or nil
    end
end

local panel, hud
local workspace, ready = "npc", false
-- Compact single-column directory (UX-001 phase 2, 2026-11-14).
local WIDTH, HEIGHT, MAX_ROWS, SUBCATEGORY_ROWS = 440, 690, 6, 6
local INNER, PAGE_TOP, PAGE_HEIGHT = 408, 84, 590
local ROW_HEIGHT, ROW_STEP, PILL_HEIGHT, PILL_GAP = 36, 38, 24, 6
local DETAILS_HEIGHT, EXTRA_HEIGHT = 92, 132
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

-- HUD controls keep the backdrop path and opacities the user approved.
local function hudButton(parent, caption, width, height, action)
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

-- Directory controls: rounded, borderless. kind: default | primary | quiet | pill.
local function button(parent, caption, width, height, action, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 28)
    b.restKind = kind == "pill" and "quiet" or kind or "default"
    if kind == "pill" then b.styleRadius = (height or 28) / 2 end
    b.label = label(b, width - 8, (height or 28) - 4, "GameFontNormalSmall", colors.white)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("MIDDLE")
    b.label:SetWordWrap(false)
    b.label:SetText(caption)
    Style.SetButtonKind(b, b.restKind)
    b:SetScript("OnClick", action)
    b:SetScript("OnEnter", Style.HoverIn)
    b:SetScript("OnLeave", Style.HoverOut)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    return b
end

-- Width of a pill for its caption: CJK and full-width characters ~13, others ~7.
local function captionWidth(text)
    local width, i = 0, 1
    text = tostring(text or "")
    while i <= #text do
        local c = text:byte(i)
        if c < 128 then width, i = width + 7, i + 1
        elseif c < 224 then width, i = width + 9, i + 2
        elseif c < 240 then width, i = width + 13, i + 3
        else width, i = width + 13, i + 4 end
    end
    return width
end
local function pillWidth(text) return math.max(44, captionWidth(text) + 22) end
-- Rounded input. With placeholder=true the hint sits inside the field and
-- hides while there is text; otherwise it is a caption above the field.
local function input(parent, width, hint, x, y, placeholder)
    local box, holder = Style.Input(parent, width, 30)
    if placeholder then
        holder:SetPoint("TOPLEFT", x, y)
        box.hint = label(holder, width - 20, 18, "GameFontHighlightSmall", colors.muted)
        box.hint:SetPoint("LEFT", 10, 0)
        box.hint:SetText(hint)
    else
        local title = label(parent, width, 16, "GameFontDisableSmall", colors.muted)
        title:SetPoint("TOPLEFT", x, y)
        title:SetText(hint)
        holder:SetPoint("TOPLEFT", x, y - 18)
    end
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
    handle:SetScript("OnDragStart", function() frame:StartMoving(); mfLayout("BeginDrag", frame) end)
    handle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        mfLayout("SnapToGrid", frame)
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
    mfLayout("RegisterLayout", hud, "世界向导 · 指引", {
        save = function(frame)
            local point, _, relativePoint, x, y = frame:GetPoint()
            NS.DB.hud = {point = point, relativePoint = relativePoint, x = x, y = y}
        end,
        reset = function()
            NS.DB.hud = {point = "CENTER", relativePoint = "CENTER", x = 0, y = 180}
            restorePosition(hud, "hud", 0, 180)
        end,
    })
    hud.title = label(hud, 166, 22, "GameFontNormalLarge", colors.title)
    hud.title:SetPoint("TOPLEFT", 72, -9)
    hud.title:SetWordWrap(false)
    hud.map = hudButton(hud, "地图", 48, 28, function()
        local nav = hud.navigation
        if nav and nav.point then
            local ok, reason = NS.ShowOnMap(nav.point)
            if ok then panel:Hide() else showMessage(reason) end
        end
    end)
    hud.map:SetPoint("TOPRIGHT", -8, -8)
    hud.close = hudButton(hud, "关闭", 48, 28, function() NS.Stop(); NS.RefreshHUD(); NS.RefreshUI() end)
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
    Style.SetButtonKind(b, active and "selected" or b.restKind or "quiet")
end

-- Place pills left to right, wrapping inside width. Returns the bottom y.
local function flow(buttons, x, y, width)
    local cx, cy = x, y
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            local w = b:GetWidth()
            if cx > x and cx + w > x + width then cx, cy = x, cy + PILL_HEIGHT + PILL_GAP end
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", cx, -cy)
            cx = cx + w + PILL_GAP
        end
    end
    return cy + PILL_HEIGHT
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

-- Subcategory pills are paged by what fits in two rows of the page width.
local SUB_TOP, SUB_ROWS_WIDTH = 0, INNER
local function subPages(list)
    local pages, start, used, rows = {}, 1, 0, 1
    for i, item in ipairs(list) do
        local w = pillWidth(item.label .. "  " .. tostring(item.count or 0)) + PILL_GAP
        if i - start >= SUBCATEGORY_ROWS or used > 0 and used + w > SUB_ROWS_WIDTH and rows == 2 then
            pages[#pages + 1] = start; start, used, rows = i, 0, 1
        elseif used > 0 and used + w > SUB_ROWS_WIDTH then rows, used = rows + 1, 0 end
        used = used + w
    end
    pages[#pages + 1] = start
    return pages
end

local function updateSubcategories()
    local list = getSubcategories()
    local found = false
    for _, c in ipairs(list) do if c.id == npcState.subcategory then found=true;break end end
    if not found then npcState.subcategory="all" end
    local pages = subPages(list)
    local maximum = #pages
    npcState.subPage=math.max(1,math.min(maximum,npcState.subPage))
    local first = pages[npcState.subPage]
    local last = (pages[npcState.subPage + 1] or (#list + 1)) - 1
    for i,b in ipairs(subcategories) do
        local item = first + i - 1 <= last and list[first + i - 1] or nil
        b.entry=item
        b:SetShown(item~=nil)
        if item then
            local caption = item.label.."  "..tostring(item.count or 0)
            b.label:SetText(caption)
            b:SetWidth(pillWidth(caption)); b.label:SetWidth(pillWidth(caption) - 8)
            activeButton(b,item.id==npcState.subcategory)
        end
    end
    -- A purpose without facets shows no facet row; the list moves up instead.
    local faceted = #list > 1
    subTitle:SetShown(faceted)
    if not faceted then for _,b in ipairs(subcategories) do b:Hide() end end
    local bottom = faceted and flow(subcategories, 0, SUB_TOP + 22, INNER) or SUB_TOP - 10
    if npcBrowser then npcBrowser.headerHeight = bottom + 12 end
    subPrevious:SetEnabled(npcState.subPage>1)
    subNext:SetEnabled(npcState.subPage<maximum)
    subPrevious:SetShown(faceted and maximum>1);subNext:SetShown(faceted and maximum>1);subPageLabel:SetShown(faceted and maximum>1)
    subPageLabel:SetText(npcState.subPage.." / "..maximum)
    subTitle:SetText("细分 · 全阵营数量")
end

local function selectedPoint(browser)
    return browser.state.selectedID and NS.GetPoint(browser.state.selectedID)
end

local function showMore(browser)
    local details=browser.details
    local state=browser.state
    details.more.label:SetText(state.more and "收起" or "资料")
    local open = state.more and selectedPoint(browser)~=nil
    details.extra:SetShown(open)
    -- The card grows upward over the list instead of pushing the page.
    local height = DETAILS_HEIGHT + (open and EXTRA_HEIGHT or 0)
    details:SetHeight(height)
    details:ClearAllPoints();details:SetPoint("TOPLEFT",0,-((browser:GetHeight() or 0)-height))
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
        d.location:SetText(browser.kind=="npc" and "选用途分类，或搜索 NPC。" or "收藏常去的 NPC，或保存自己的地点。")
        d.info:SetText("");d.favorite.label:SetText("收藏")
        showMore(browser)
        return
    end
    d.name:SetText(point.name or "未命名地点")
    d.service:SetText(point.service or "自定义地点")
    d.location:SetText(string.format("%s · %.1f, %.1f · %s",point.zone or "目标地图",point.x*100,point.y*100,factionNames[point.faction] or "自定义"))
    d.favorite.label:SetText(NS.DB.favorites[point.id] and "取消收藏" or "收藏")
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
            row.name:SetText((NS.DB.favorites[point.id] and "★ " or "")..point.name)
            row.zone:SetText(point.zone or "目标地图")
            -- Caption reads "what · where"; the distance is the number on the right.
            row.service:SetText((point.service or "自定义地点").." · "..(point.zone or "目标地图"))
            row.distance:SetText(pointDistance(point))
            row.selected = point.id==state.selectedID
            -- 星辉 cursor: slanted band + gold diamond instead of a flat fill.
            Style.Round(row, "surface", 0, 8)
            if Style.MarkSelected then Style.MarkSelected(row, row.selected) end
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
    local header=browser.headerHeight or 40
    local filters=browser.kind=="npc" and browser.state.filters
    local controls=header+(filters and 58 or 26)
    browser.listTop=controls
    browser.title:ClearAllPoints();browser.title:SetPoint("TOPLEFT",0,-header-3)
    browser.sort:ClearAllPoints();browser.sort:SetPoint("TOPLEFT",INNER-(browser.filterToggle and 196 or 92),-header)
    if browser.filterToggle then
        browser.filterToggle:ClearAllPoints();browser.filterToggle:SetPoint("TOPLEFT",INNER-100,-header)
        browser.filterBar:ClearAllPoints();browser.filterBar:SetPoint("TOPLEFT",0,-header-28)
    end
    local room=height-controls-28-DETAILS_HEIGHT-4
    browser.visibleRows=math.max(1,math.min(MAX_ROWS,math.floor(room/ROW_STEP)))
    for i,row in ipairs(browser.rows) do
        row:ClearAllPoints();row:SetPoint("TOPLEFT",0,-controls-(i-1)*ROW_STEP)
    end
    local footer=controls+browser.visibleRows*ROW_STEP+2
    browser.previous:ClearAllPoints();browser.previous:SetPoint("TOPLEFT",0,-footer)
    browser.next:ClearAllPoints();browser.next:SetPoint("TOPLEFT",INNER-72,-footer)
    browser.pageLabel:ClearAllPoints();browser.pageLabel:SetPoint("TOPLEFT",80,-footer-2)
    browser.empty:ClearAllPoints();browser.empty:SetPoint("TOPLEFT",8,-controls-60)
    local d=browser.details
    d:SetHeight(DETAILS_HEIGHT)
    d:ClearAllPoints();d:SetPoint("TOPLEFT",0,-(height-DETAILS_HEIGHT))
    d.extra:SetHeight(EXTRA_HEIGHT-12)
    if browser.state.more then showMore(browser) end
end

-- headerHeight: space above the result list owned by the page (search, pills).
local function createBrowser(parent,state,kind,headerHeight)
    local browser=CreateFrame("Frame",nil,parent)
    browser:SetWidth(INNER);browser.state=state;browser.kind=kind;browser.listWidth=INNER;browser.rows={}
    browser.headerHeight=headerHeight
    browser.search=input(browser,INNER,kind=="npc" and "搜索 NPC 名称或用途" or "搜索收藏或自定义地点",0,0,true)
    browser.search:SetMaxLetters(120)
    browser.search:SetScript("OnTextChanged",function(self)
        state.query=self:GetText() or "";state.page=1;state.selectedID=nil
        if self.hint then self.hint:SetShown(state.query=="") end
        if ready then NS.RefreshUI() end
    end)
    browser.sort=button(browser,"最近优先",88,24,function()
        state.sort=state.sort=="distance" and "name" or "distance";state.page=1;state.selectedID=nil;NS.RefreshUI()
    end,"quiet")
    if kind=="npc" then
        browser.filterToggle=button(browser,"筛选",100,24,function()state.filters=not state.filters;NS.RefreshUI()end,"quiet")
        browser.filterBar=CreateFrame("Frame",nil,browser)
        browser.filterBar:SetSize(INNER,24)
        browser.faction=button(browser.filterBar,"阵营：本方与中立",200,24,function()
            state.faction=state.faction=="own" and "all" or "own";state.page=1;state.selectedID=nil;NS.RefreshUI()
        end,"pill")
        browser.faction:SetPoint("TOPLEFT")
        browser.zone=button(browser.filterBar,"区域：整个世界",200,24,function()
            state.currentZone=not state.currentZone;state.page=1;state.selectedID=nil;NS.RefreshUI()
        end,"pill")
        browser.zone:SetPoint("TOPLEFT",208,0)
    end
    browser.title=label(browser,200,18,"GameFontHighlightSmall",colors.muted)
    browser.title:SetWordWrap(false)
    for i=1,MAX_ROWS do
        local row=CreateFrame("Button",nil,browser)
        row:SetSize(INNER,ROW_HEIGHT)
        Style.Round(row,"surface",0,8)
        row.name=label(row,INNER-110,18,"GameFontHighlightSmall",colors.white)
        row.name:SetPoint("TOPLEFT",22,-2);row.name:SetWordWrap(false)
        Style.SetType(row.name,"body","text")
        row.service=label(row,INNER-110,16,"GameFontHighlightSmall",colors.muted)
        row.service:SetPoint("TOPLEFT",22,-19);row.service:SetWordWrap(false)
        Style.SetType(row.service,"caption","muted")
        -- Kept for callers that read the zone on its own; the caption shows it.
        row.zone=label(row,1,1,"GameFontHighlightSmall",colors.muted);row.zone:Hide()
        row.distance=label(row,90,18,"GameFontHighlightSmall",colors.teal)
        row.distance:SetPoint("TOPRIGHT",-10,-9);row.distance:SetJustifyH("RIGHT");row.distance:SetWordWrap(false)
        row:SetScript("OnClick",function(self)if self.point then state.selectedID=self.point.id;NS.RefreshUI()end end)
        row:SetScript("OnEnter",function(self) if not self.selected then Style.Round(self,"surface",1) end end)
        row:SetScript("OnLeave",function(self) if not self.selected then Style.Round(self,"surface",0) end end)
        browser.rows[i]=row
    end
    browser.previous=button(browser,"上一页",72,24,function()
        state.page=math.max(1,state.page-1);state.selectedID=nil;NS.RefreshUI()
    end,"quiet")
    browser.next=button(browser,"下一页",72,24,function()
        local maximum=math.max(1,math.ceil(#(browser.results or {})/(browser.visibleRows or MAX_ROWS)))
        state.page=math.min(maximum,state.page+1);state.selectedID=nil;NS.RefreshUI()
    end,"quiet")
    browser.pageLabel=label(browser,INNER-160,20,"GameFontHighlightSmall",colors.muted)
    browser.pageLabel:SetJustifyH("CENTER")
    browser.empty=label(browser,INNER-16,90,"GameFontHighlight",colors.muted)
    browser.empty:SetJustifyH("CENTER")
    browser:EnableMouseWheel(true)
    browser:SetScript("OnMouseWheel",function(_,delta)
        if delta>0 then browser.previous:Click() else browser.next:Click() end
    end)
    -- Selected destination: one line of identity, one of place, one row of actions.
    local d=CreateFrame("Frame",nil,browser)
    browser.details=d;d:SetWidth(INNER)
    if d.SetFrameLevel and browser.GetFrameLevel then d:SetFrameLevel((browser:GetFrameLevel() or 1)+10) end
    Style.Round(d,"side",1,10)
    d:EnableMouse(true)
    local inner=INNER-24
    d.name=label(d,inner-130,20,"GameFontNormal",colors.title);d.name:SetPoint("TOPLEFT",12,-10);d.name:SetWordWrap(false)
    Style.SetType(d.name,"title","text")
    d.service=label(d,124,18,"GameFontHighlightSmall",colors.muted);d.service:SetPoint("TOPRIGHT",-12,-12)
    d.service:SetJustifyH("RIGHT");d.service:SetWordWrap(false)
    d.location=label(d,inner,16,"GameFontHighlightSmall",colors.muted);d.location:SetPoint("TOPLEFT",12,-32);d.location:SetWordWrap(false)
    Style.SetType(d.location,"caption","muted")
    d.start=button(d,"开始导航",inner-216,28,function()
        local point=selectedPoint(browser)
        if point then local ok,reason=NS.Start(point);if not ok then showMessage(reason)end;NS.RefreshHUD();NS.RefreshUI()end
    end,"primary")
    d.map=button(d,"地图",64,28,function()
        local point=selectedPoint(browser)
        if point then local ok,reason=NS.ShowOnMap(point);if ok then panel:Hide()else showMessage(reason)end end
    end)
    d.favorite=button(d,"收藏",72,28,function()
        if state.selectedID then NS.ToggleFavorite(state.selectedID);NS.RefreshUI()end
    end)
    d.more=button(d,"资料",64,28,function()state.more=not state.more;showMore(browser)end,"quiet")
    d.start:SetPoint("BOTTOMLEFT",12,10)
    d.map:SetPoint("BOTTOMLEFT",12+(inner-216)+8,10)
    d.favorite:SetPoint("BOTTOMLEFT",12+(inner-216)+80,10)
    d.more:SetPoint("BOTTOMLEFT",12+(inner-216)+160,10)
    d.extra=CreateFrame("ScrollFrame",nil,d)
    d.extra:SetPoint("TOPLEFT",12,-54);d.extra:SetWidth(inner)
    d.content=CreateFrame("Frame",nil,d.extra);d.content:SetWidth(inner)
    d.info=label(d.content,inner,40,"GameFontHighlightSmall",colors.muted);d.info:SetPoint("TOPLEFT")
    d.extra:SetScrollChild(d.content);d.extra:EnableMouseWheel(true)
    d.extra:SetScript("OnMouseWheel",function(_,delta)
        local maximum=math.max(0,d.content:GetHeight()-d.extra:GetHeight())
        d.scrollOffset=math.max(0,math.min(maximum,(d.scrollOffset or 0)-delta*28));d.extra:SetVerticalScroll(d.scrollOffset)
    end)
    d.delete=button(d,"删除",56,24,function()
        local point=selectedPoint(browser)
        if point and point.category=="custom" then NS.RemoveCustom(point.id);state.selectedID=nil;NS.RefreshUI();NS.RefreshHUD()end
    end,"quiet")
    d.delete.label:SetTextColor(Style.Color("danger"))
    d.delete:SetPoint("TOPRIGHT",-8,-30)
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
    view.status:SetText((nav.status or "正在读取位置")..((nav.detail and nav.detail~="") and ("\n"..nav.detail) or ""))
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
        browserLayout(npcBrowser,PAGE_HEIGHT);refreshBrowser(npcBrowser)
        NS.UI.search,NS.UI.rows,NS.UI.details=npcBrowser.search,npcBrowser.rows,npcBrowser.details
        NS.UI.moreToggle=npcBrowser.details.more
    elseif workspace=="places" then
        for id,b in pairs(placeTabs)do activeButton(b,id==placeState.category)end
        placeForm:SetShown(formShown)
        createToggle.label:SetText(formShown and "收起新增" or "新增地点")
        local top=formShown and 172 or 66
        placeBrowser:ClearAllPoints();placeBrowser:SetPoint("TOPLEFT",0,-top)
        browserLayout(placeBrowser,PAGE_HEIGHT-top);refreshBrowser(placeBrowser)
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
    panel=CreateFrame("Frame","MyForeverNavigatorPanel",UIParent)
    panel:SetSize(WIDTH,HEIGHT);panel:SetFrameStrata("HIGH");panel:EnableMouse(true);Style.Panel(panel,"window")
    local scale=math.min(1,(UIParent:GetWidth()-30)/WIDTH,(UIParent:GetHeight()-30)/HEIGHT)
    panel:SetScale(math.max(.55,scale));restorePosition(panel,"panel",0,0)
    local header=CreateFrame("Frame",nil,panel);header:SetPoint("TOPLEFT");header:SetPoint("TOPRIGHT",-36,0);header:SetHeight(40);drag(panel,header,"panel")
    local title=label(panel,300,24,"GameFontNormalLarge",colors.title);title:SetPoint("TOPLEFT",16,-11);title:SetText("世界向导")
    Style.SetType(title,"title","text")
    if Style.WindowTitle then Style.WindowTitle(title,"世界向导") end
    if Style.TitleRule then Style.TitleRule(panel,16,nil,220,38) end
    if Style.HintBar then Style.HintBar(panel,{{"左键","选择"},{"Esc","关闭"}},"/myui 摆放面板") end
    local close=Style.CloseButton(panel,function()panel:Hide()end);close:SetPoint("TOPRIGHT",-8,-8)
    for i,item in ipairs({{"npc","找 NPC"},{"places","我的地点"},{"navigation","当前导航"}})do
        local id=item[1]
        local b=button(panel,item[2],96,26,function()setWorkspace(id)end,"pill");b:SetPoint("TOPLEFT",16+(i-1)*102,-44)
        workspaceTabs[id]=b
    end
    npcPage=CreateFrame("Frame",nil,panel);npcPage:SetPoint("TOPLEFT",16,-PAGE_TOP);npcPage:SetSize(INNER,PAGE_HEIGHT)
    placePage=CreateFrame("Frame",nil,panel);placePage:SetPoint("TOPLEFT",16,-PAGE_TOP);placePage:SetSize(INNER,PAGE_HEIGHT)
    navigationPage=CreateFrame("Frame",nil,panel);navigationPage:SetPoint("TOPLEFT",16,-PAGE_TOP);navigationPage:SetSize(INNER,PAGE_HEIGHT)
    -- NPC page: search, purpose pills, subcategory pills, then the result list.
    for _,c in ipairs(categoryList())do
        local id=c.id
        local b=button(npcPage,c.label,pillWidth(c.label),PILL_HEIGHT,function()
            npcState.category=id;npcState.subcategory="all";npcState.subPage=1;npcState.page=1;npcState.selectedID=nil;npcState.more=false;NS.RefreshUI()
        end,"pill")
        b.category=id;categories[#categories+1]=b
    end
    local purposeBottom=flow(categories,0,40,INNER)
    SUB_TOP=purposeBottom+10
    subTitle=label(npcPage,200,18,"GameFontHighlightSmall",colors.muted);subTitle:SetPoint("TOPLEFT",0,-SUB_TOP)
    Style.SetType(subTitle,"caption","muted")
    for i=1,SUBCATEGORY_ROWS do
        local b=button(npcPage,"",80,PILL_HEIGHT,function(self)
            if self.entry then npcState.subcategory=self.entry.id;npcState.page=1;npcState.selectedID=nil;npcState.more=false;NS.RefreshUI()end
        end,"pill")
        subcategories[i]=b
    end
    subPrevious=button(npcPage,"‹",24,20,function()npcState.subPage=math.max(1,npcState.subPage-1);updateSubcategories()end,"quiet")
    subPrevious:SetPoint("TOPLEFT",INNER-96,-SUB_TOP+1)
    subNext=button(npcPage,"›",24,20,function()npcState.subPage=npcState.subPage+1;updateSubcategories()end,"quiet")
    subNext:SetPoint("TOPLEFT",INNER-24,-SUB_TOP+1)
    subPageLabel=label(npcPage,44,18,"GameFontHighlightSmall",colors.muted);subPageLabel:SetPoint("TOPLEFT",INNER-70,-SUB_TOP-1);subPageLabel:SetJustifyH("CENTER")
    local npcHeader=SUB_TOP+22+2*PILL_HEIGHT+PILL_GAP+12
    npcBrowser=createBrowser(npcPage,npcState,"npc",npcHeader);npcBrowser:SetPoint("TOPLEFT",0,0)
    -- Places page: list switch, actions, optional coordinate form, then the list.
    for i,item in ipairs({{"favorites","收藏地点"},{"custom","自定义地点"}})do
        local id=item[1]
        local b=button(placePage,item[2],96,26,function()placeState.category=id;placeState.page=1;placeState.selectedID=nil;placeState.more=false;NS.RefreshUI()end,"pill")
        b:SetPoint("TOPLEFT",(i-1)*102,0);placeTabs[id]=b
    end
    createToggle=button(placePage,"新增地点",104,26,function()formShown=not formShown;NS.RefreshUI()end)
    createToggle:SetPoint("TOPLEFT",0,-34)
    currentButton=button(placePage,"保存当前位置",136,26,function()
        local point,reason=NS.SaveCurrent(formShown and nameInput:GetText() or "")
        if point then formShown=false;selectPlace(point)else showMessage(reason)end
    end)
    currentButton:SetPoint("TOPLEFT",112,-34)
    importButton=button(placePage,"导入地图标记",152,26,function()
        if type(NS.ImportWaypoint)~="function"then showMessage("当前无法读取地图标记。");return end
        local point,reason=NS.ImportWaypoint()
        if not point then showMessage(reason);return end
        local ok,startReason=NS.Start(point)
        if not ok then showMessage(startReason);return end
        formShown=false;selectPlace(point);NS.RefreshHUD()
    end)
    importButton:SetPoint("TOPLEFT",256,-34)
    placeForm=CreateFrame("Frame",nil,placePage);placeForm:SetPoint("TOPLEFT",0,-68);placeForm:SetSize(INNER,96)
    Style.Round(placeForm,"side",1,10)
    mapInput=input(placeForm,72,"地图 ID",10,-8);mapInput:SetMaxLetters(6)
    xInput=input(placeForm,64,"X %",88,-8);xInput:SetMaxLetters(8)
    yInput=input(placeForm,64,"Y %",158,-8);yInput:SetMaxLetters(8)
    nameInput=input(placeForm,170,"地点名称",228,-8)
    saveButton=button(placeForm,"保存地点",120,26,function()
        local point,reason=NS.AddCustom(nameInput:GetText(),tonumber(mapInput:GetText()),(tonumber(xInput:GetText())or -100)/100,(tonumber(yInput:GetText())or -100)/100)
        if point then formShown=false;nameInput:ClearFocus();selectPlace(point)else showMessage(reason)end
    end,"primary")
    saveButton:SetPoint("BOTTOMRIGHT",-10,8)
    local boxes={mapInput,xInput,yInput,nameInput}
    for i,box in ipairs(boxes)do
        local nextBox=boxes[i%#boxes+1]
        box:SetScript("OnTabPressed",function(self)self:ClearFocus();nextBox:SetFocus()end)
    end
    placeBrowser=createBrowser(placePage,placeState,"places",40)
    local hint=nil
    local nav={}
    nav.empty=CreateFrame("Frame",nil,navigationPage);nav.empty:SetAllPoints(navigationPage)
    local emptyTitle=label(nav.empty,INNER,28,"GameFontNormalLarge",colors.title);emptyTitle:SetPoint("TOPLEFT",0,-40);emptyTitle:SetText("还没有导航目的地")
    Style.SetType(emptyTitle,"title","text")
    local emptyText=label(nav.empty,INNER,48,"GameFontHighlight",colors.muted);emptyText:SetPoint("TOPLEFT",0,-74);emptyText:SetText("在「找 NPC」选一个目的地，\n或到「我的地点」保存坐标、导入地图标记。")
    nav.find=button(nav.empty,"去找 NPC",140,30,function()setWorkspace("npc")end,"primary");nav.find:SetPoint("TOPLEFT",0,-134)
    nav.active=CreateFrame("Frame",nil,navigationPage);nav.active:SetAllPoints(navigationPage)
    local card=CreateFrame("Frame",nil,nav.active);card:SetPoint("TOPLEFT",0,0);card:SetSize(INNER,212);Style.Round(card,"side",1,12)
    nav.target=label(nav.active,INNER-28,26,"GameFontNormalLarge",colors.title);nav.target:SetPoint("TOPLEFT",14,-14)
    Style.SetType(nav.target,"title","text")
    nav.location=label(nav.active,INNER-28,18,"GameFontHighlight",colors.muted);nav.location:SetPoint("TOPLEFT",14,-42)
    Style.SetType(nav.location,"caption","muted")
    nav.distance=label(nav.active,INNER-28,30,"GameFontNormalLarge",colors.white);nav.distance:SetPoint("TOPLEFT",14,-66)
    Style.SetType(nav.distance,"value","text")
    nav.status=label(nav.active,INNER-28,80,"GameFontHighlight",colors.teal);nav.status:SetPoint("TOPLEFT",14,-104)
    Style.SetType(nav.status,"secondary","secondary")
    nav.tracking=label(nav.active,INNER-28,18,"GameFontHighlightSmall",colors.muted);nav.tracking:SetPoint("TOPLEFT",14,-186)
    Style.SetType(nav.tracking,"caption","muted")
    nav.resume=button(nav.active,"继续指引",180,30,function()
        local point=NS.GetPoint(NS.DB.activeID)
        if point then local ok,reason=NS.Start(point);if not ok then showMessage(reason)end;NS.RefreshHUD();NS.RefreshNavigationPage()end
    end,"primary")
    nav.resume:SetPoint("TOPLEFT",0,-226)
    nav.map=button(nav.active,"地图",100,30,function()
        local point=NS.GetPoint(NS.DB.activeID)
        if point then local ok,reason=NS.ShowOnMap(point);if ok then panel:Hide()else showMessage(reason)end end
    end)
    nav.map:SetPoint("TOPLEFT",188,-226)
    nav.stop=button(nav.active,"停止",112,30,function()NS.Stop();NS.RefreshHUD();NS.RefreshNavigationPage()end)
    nav.stop.label:SetTextColor(Style.Color("danger"))
    nav.stop:SetPoint("TOPLEFT",296,-226)
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
