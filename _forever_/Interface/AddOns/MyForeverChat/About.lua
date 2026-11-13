local addonName, NS = ...
local ui
local license = [[MIT License

Copyright (c) 2026 Hyder

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.]]

local function version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    if type(get) == "function" then
        local ok, value = pcall(get, addonName, "Version")
        if ok and not (issecretvalue and issecretvalue(value))
            and type(value) == "string" and value:match("^%d+%.%d+%.%d+$") then
            return value
        end
    end
    return "0.9.0"
end

local function contents()
    return "我的微信式聊天 MyForeverChat\n版本 " .. version() .. " · 试用版\n\n"
        .. "作者：Hyder\n邮箱：267500@qq.com\n官网：https://afabiaoge.xyz/\n\n"
        .. "服务器：PVE普通\n阵营：联盟\n公会：炉边余客\n角色：苏氏集团苏晚晴\n\n"
        .. "MIT 许可证\n允许使用、修改、分发和商用；须保留版权声明与许可文本。"
        .. "软件按现状提供，不作担保。完整条款见下方英文原文及插件目录内 LICENSE.txt。\n\n"
        .. "官网和邮箱可选中复制；本窗口不会在游戏内打开外部网页。\n\n"
        .. license
end

local function wheel(_, delta)
    local offset = ui.scroll:GetVerticalScroll() - delta * 36
    ui.scroll:SetVerticalScroll(math.max(0, math.min(ui.scroll:GetVerticalScrollRange(), offset)))
end

local function build()
    local frame = CreateFrame("Frame", "MyForeverChatAboutFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("关于 · 我的微信式聊天")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -40)
    scroll:SetPoint("BOTTOMRIGHT", -34, 66)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", wheel)
    local body = CreateFrame("EditBox", nil, scroll)
    body:SetMultiLine(true)
    body:SetAutoFocus(false)
    body:SetFontObject(ChatFontNormal)
    body:SetWidth(496)
    body:SetTextInsets(2, 2, 4, 4)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", wheel)
    scroll:SetScrollChild(body)

    ui = {frame=frame, scroll=scroll, text=body}
    NS.aboutUI = ui
    -- Keep text selectable for native copy shortcuts while rejecting edits.
    -- WoW EditBoxes size themselves from multiline text; the scroll child
    -- follows that height rather than clipping the license to a fixed panel.
    body:SetScript("OnTextChanged", function(self)
        if ui.restoring or self:GetText() == ui.content then return end
        ui.restoring = true
        self:SetText(ui.content or "")
        ui.restoring = false
    end)
    body:SetScript("OnEscapePressed", function() frame:Hide() end)
    body:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top = math.max(0, -y)
        local offset = scroll:GetVerticalScroll()
        if top < offset then scroll:SetVerticalScroll(top)
        elseif top + height > offset + scroll:GetHeight() then
            scroll:SetVerticalScroll(math.max(0, top + height - scroll:GetHeight()))
        end
    end)
    frame:SetScript("OnHide", function() body:ClearFocus() end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 45)
    hint:SetText("选中文字复制：Ctrl+C · macOS Cmd+C；滚轮查看完整许可证。")
    local selectAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAll:SetSize(100, 24)
    selectAll:SetPoint("BOTTOMLEFT", 18, 14)
    selectAll:SetText("全选文字")
    selectAll:SetScript("OnClick", function() body:SetFocus(); body:HighlightText() end)
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(90, 24)
    close:SetPoint("BOTTOMRIGHT", -18, 14)
    close:SetText("关闭")
    close:SetScript("OnClick", function() frame:Hide() end)
    ui.selectAll, ui.close = selectAll, close
    UISpecialFrames = UISpecialFrames or {}
    tinsert(UISpecialFrames, "MyForeverChatAboutFrame")
    return frame
end

function NS.ShowAbout()
    local frame = ui and ui.frame or build()
    ui.content = contents()
    ui.text:SetText(ui.content)
    ui.text:SetCursorPosition(0)
    ui.text:ClearFocus()
    ui.scroll:SetVerticalScroll(0)
    frame:Show()
    frame:Raise()
    return frame
end
