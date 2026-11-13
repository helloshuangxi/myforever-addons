local W = ...
StaticPopupDialogs = {}
StaticPopup_Show = function() end
GetServerTime = function() return 1794500000 end
time = GetServerTime
GetLocale = function() return "zhCN" end
NameUtil = { GetUnmodifiedUnitFullName = function() return "本人-家族" end }
UnitNameUnmodified = function() return "本人", "家族" end
UnitGUID = function() return "Player-Self" end
GetChannelList = function() return 1, "综合", false end
GetChannelName = function(id) if id == 1 or id == "综合" then return 1, "综合", false end return 0 end
IsInGroup = function() return true end
IsInRaid = function() return false end
IsInGuild = function() return true end
issecretvalue = function() return false end
C_ChatInfo = { SendChatMessage = function() end }
local NS = LoadAddon("MyForeverChat")
PREVIEW_CHAT_NS = NS
W.fire("ADDON_LOADED", "MyForeverChat")
W.fire("PLAYER_LOGIN")
local feed = {
    { "CHAT_MSG_GUILD", "今晚八点开团，记得带合剂", "阿尔萨-家族" },
    { "CHAT_MSG_PARTY", "我去修一下装备，马上回来", "圣光行者-家族" },
    { "CHAT_MSG_PARTY", "好的，门口集合", "林间游侠-家族" },
    { "CHAT_MSG_WHISPER", "你那边还收铜矿吗？", "铁炉堡商人-家族" },
    { "CHAT_MSG_PARTY", "法师给口水喝", "圣光行者-家族" },
}
for i, m in ipairs(feed) do
    W.fire(m[1], m[2], m[3], "", "", m[3], "", 0, 0, "", 0, i, "Player-" .. i)
end
local ui = NS.ui
if ui and ui.render then ui.render() end
if ui and ui.panel and not ui.panel:IsShown() then ui.panel:Show() end
return { { name = "聊天主窗", frame = ui.panel } }
