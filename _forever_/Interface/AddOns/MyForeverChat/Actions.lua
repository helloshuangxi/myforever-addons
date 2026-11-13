local _, NS = ...

local shortcuts = {
    { token = "DANCE", chinese = "/跳舞", english = "/dance" },
    { token = "WAVE", chinese = "/招手", english = "/wave" },
    { token = "BOW", chinese = "/鞠躬", english = "/bow" },
    { token = "CHEER", chinese = "/欢呼", english = "/cheer" },
}
local actions, byToken

function NS.GetActions()
    if actions then return actions end
    actions, byToken = {}, {}

    local maxIndex = type(MAXEMOTEINDEX) == "number" and MAXEMOTEINDEX or 0
    for i = 1, maxIndex do
        local prefix = "EMOTE" .. i
        local token = _G[prefix .. "_TOKEN"]
        local command = _G[prefix .. "_CMD1"]
        if type(token) == "string" and token ~= "UNUSED" and token:match("^[A-Z][A-Z0-9_]*$")
            and type(command) == "string" and command:match("^/[^/|%z\1-\32\127]+$") and not byToken[token] then
            byToken[token] = { token = token, label = command }
        end
    end

    local remaining = {}
    for _, action in pairs(byToken) do remaining[#remaining + 1] = action end
    local chinese = GetLocale and GetLocale() == "zhCN"
    local pinned = {}
    for _, shortcut in ipairs(shortcuts) do
        local token = shortcut.token
        local action = byToken[token] or { token = token, label = chinese and shortcut.chinese or shortcut.english }
        byToken[token] = action
        actions[#actions + 1] = action
        pinned[token] = true
    end

    table.sort(remaining, function(a, b)
        if a.label == b.label then return a.token < b.token end
        return a.label < b.label
    end)
    for _, action in ipairs(remaining) do
        if not pinned[action.token] then actions[#actions + 1] = action end
    end
    return actions
end

function NS.PerformAction(token)
    if (issecretvalue and issecretvalue(token)) or type(token) ~= "string" then
        return false, "请选择一个游戏动作。"
    end
    NS.GetActions()
    local action = byToken[token]
    if not action then return false, "请选择一个游戏动作。" end

    local perform = C_ChatInfo and C_ChatInfo.PerformEmote or DoEmote
    if type(perform) ~= "function" then return false, "当前客户端没有可用的动作接口。" end
    local ok, restricted = pcall(perform, action.token)
    -- The native slash parser treats true as restricted.
    if not ok or (issecretvalue and issecretvalue(restricted)) or restricted then
        return false, "游戏暂时无法执行 " .. action.label
    end
    return true, "已提交动作 " .. action.label
end
