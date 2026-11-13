local addonName, NS = ...
local events = CreateFrame("Frame")
local initialized = false
local chatEvents = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}
local contactEvents={
    FRIENDLIST_UPDATE=true, UNIT_CONNECTION=true, BN_FRIEND_LIST_SIZE_CHANGED=true, BN_FRIEND_INFO_CHANGED=true,
    BN_FRIEND_ACCOUNT_ONLINE=true, BN_FRIEND_ACCOUNT_OFFLINE=true, BN_CONNECTED=true, BN_DISCONNECTED=true,
    RECENT_ALLIES_CACHE_UPDATE=true, RECENT_ALLIES_DATA_READY=true, RECENT_ALLY_DATA_UPDATED=true,
}
local function init()
    if initialized then return end
    MyForeverChatDB = NS.InitDB(MyForeverChatDB)
    initialized = true
end
local function attachHistory()
    if NS.AttachAccountHistory and not NS.accountHistory then
        MyForeverChatAccountDB = NS.AttachAccountHistory(MyForeverChatAccountDB, NS.GetHistoryOwnerKey())
    end
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE")
events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
events:RegisterEvent("CHANNEL_UI_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, event in ipairs(chatEvents) do events:RegisterEvent(event) end
for event in pairs(contactEvents) do pcall(events.RegisterEvent,events,event) end
if NS.Communities then
    for _, event in ipairs(NS.Communities.Events) do pcall(events.RegisterEvent, events, event) end
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then init()
        elseif initialized and type(name)=="string" and name:match("^MyForeverChatEmotes_") then
            NS.RefreshEmotePacks(); NS.RefreshEmotePicker()
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        init()
        attachHistory()
        if NS.Communities then NS.Communities.Refresh() end
        NS.SyncChannels(); NS.CaptureTarget(); NS.RefreshEmotePacks(); NS.BuildUI()
        NS.InstallNativeClicks(); NS.InstallItemLinkBridge()
        NS.InstallQuickReplyShortcut()
        print("|cff70d6aa我的聊天|r 已加载：Ctrl+X 回复泡泡／最小化，/wx 打开。")
        return
    end
    if not initialized then return end
    if event == "PLAYER_ENTERING_WORLD" then attachHistory() end
    if NS.Communities and NS.Communities.HandleEvent(event, ...) then return end
    if NS.Communities and (event == "BN_CONNECTED" or event == "BN_DISCONNECTED" or event == "PLAYER_ENTERING_WORLD") then NS.Communities.Refresh() end
    if event == "CHAT_MSG_SYSTEM" then NS.ShowSystemNotice(...)
    elseif event == "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE" then NS.ShowWhisperOfflineNotice(...)
    elseif event == "PLAYER_TARGET_CHANGED" then NS.CaptureTarget(); NS.RefreshUI()
    elseif contactEvents[event] then NS.RefreshUI()
    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" or event == "PLAYER_ENTERING_WORLD" then NS.SyncChannels(); NS.RefreshUI()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then NS.RefreshUI()
    else
        local changed=NS.HandleEvent(event,...)
        if changed and event=="CHAT_MSG_WHISPER" then
            local author=select(2,...)
            local guid=select(12,...)
            NS.CaptureWhisperProfile(author,guid)
        end
    end
end)

SLASH_MYFOREVERCHAT1 = "/wx"
SLASH_MYFOREVERCHAT2 = "/mychat"
SlashCmdList.MYFOREVERCHAT = function(command)
    command = (command or ""):gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    if command == "reply" then NS.ReplyRecent()
    elseif command == "target" then NS.OpenTargetWhisper()
    elseif command == "reset" then NS.ResetPosition()
    elseif command == "settings" then NS.ShowAppearanceSettings()
    elseif command == "about" then NS.ShowAbout()
    elseif command == "actions" then NS.ShowActions()
    elseif command == "clear" then NS.ClearNotifications()
    elseif command == "" then NS.ToggleUI()
    else print("|cff70d6aa我的聊天|r /wx 开关；/wx settings 外观；/wx about 作者与许可；/wx actions 动作；/wx clear 清除泡泡；/wx reply 回复；/wx target 目标；/wx reset 复位。") end
end
BINDING_HEADER_MYFOREVERCHAT = "我的微信式聊天"
BINDING_NAME_MYFOREVERCHAT_TOGGLE = "打开／关闭聊天窗口"
BINDING_NAME_MYFOREVERCHAT_REPLY = "回复最近私聊"
BINDING_NAME_MYFOREVERCHAT_QUICKREPLY = "回复消息泡泡／最小化（Ctrl+X）"
BINDING_NAME_MYFOREVERCHAT_TARGET = "私聊当前选中玩家"
BINDING_NAME_MYFOREVERCHAT_ACTIONS = "打开游戏动作面板"
BINDING_NAME_MYFOREVERCHAT_DANCE = "动作 · 跳舞"
BINDING_NAME_MYFOREVERCHAT_WAVE = "动作 · 招手"
BINDING_NAME_MYFOREVERCHAT_BOW = "动作 · 鞠躬"
BINDING_NAME_MYFOREVERCHAT_CHEER = "动作 · 欢呼"
MyForeverChat_Toggle = function() NS.ToggleUI() end
MyForeverChat_Reply = function() NS.ReplyRecent() end
MyForeverChat_QuickReply = function() NS.RunQuickReplyShortcut() end
MyForeverChat_Target = function() NS.OpenTargetWhisper() end
MyForeverChat_Actions = function() NS.ShowActions() end
MyForeverChat_Action = function(token) NS.RunAction(token) end
