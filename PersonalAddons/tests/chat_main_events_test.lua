-- Route delivery failures to the UI without manufacturing a chat message.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label)
end
local events = {registered={}}
function events:RegisterEvent(event) self.registered[event] = true end
function events:SetScript(name, callback) self[name] = callback end
CreateFrame = function() return events end
SlashCmdList = {}
local failures, messages, systems, about = {}, 0, 0, 0
local NS = {
    InitDB=function() return {} end,
    ShowWhisperOfflineNotice=function(...) failures[#failures+1]={n=select("#", ...), ...} end,
    HandleEvent=function() messages=messages+1; return false end,
    ShowSystemNotice=function() systems=systems+1 end,
    ShowAbout=function() about=about+1 end,
}
assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Main.lua"))("MyForeverChat", NS)
eq(events.registered.CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE, true, "native offline event registered")
events.OnEvent(events, "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", "not initialized")
eq(#failures, 0, "events before addon initialization ignored")
events.OnEvent(events, "ADDON_LOADED", "MyForeverChat")
local secret = setmetatable({}, {__tostring=function() error("do not coerce restricted payload") end})
events.OnEvent(events, "CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE", "离线", "好友", nil, "", "", "", 0, 0, "", 0, 9, secret, 77)
eq(#failures, 1, "native offline event forwarded once")
eq(failures[1].n, 13, "payload arity and nil holes preserved")
eq(failures[1][2], "好友", "native recipient name forwarded")
eq(failures[1][12], secret, "restricted payload forwarded without inspection")
eq(failures[1][13], 77, "native account ID remains in documented slot")
eq(messages, 0, "delivery failure never enters chat history handler")
events.OnEvent(events, "CHAT_MSG_SYSTEM", "系统通知")
eq(systems, 1, "existing system notice route remains intact")
events.OnEvent(events, "CHAT_MSG_BN_WHISPER", "真实来信")
eq(messages, 1, "actual whisper still reaches chat handler")
SlashCmdList.MYFOREVERCHAT(" about ")
eq(about, 1, "about command opens author and license panel")
print("chat_main_events_test: " .. checks .. " checks passed")
