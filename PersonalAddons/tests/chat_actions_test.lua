local NS, checks = {}, 0
local function check(value, description)
    checks = checks + 1
    assert(value, description)
end

MAXEMOTEINDEX = 628
EMOTE35_TOKEN, EMOTE35_CMD1 = "DANCE", "/跳舞"
EMOTE36_TOKEN, EMOTE36_CMD1 = "UNUSED", "/unused"
EMOTE37_TOKEN, EMOTE37_CMD1 = "NO_LABEL", nil
EMOTE628_TOKEN, EMOTE628_CMD1 = "LEAN", "/倚靠"
GetLocale = function() return "zhCN" end

assert(loadfile("_forever_/Interface/AddOns/MyForeverChat/Actions.lua"))("MyForeverChat", NS)
local actions = NS.GetActions()
check(#actions == 5 and actions[5].token == "LEAN", "loads sparse native indices and ignores entries without a real command")
check(actions[1].token == "DANCE" and actions[1].label == "/跳舞", "keeps the native localized slash label")
check(actions[2].label == "/招手" and actions[4].token == "CHEER", "always supplies the common action bindings")

local invoked = {}
C_ChatInfo = {
    PerformEmote = function(token)
        invoked[#invoked + 1] = token
        return token == "LEAN"
    end,
}
DoEmote = function() error("must use native PerformEmote when available") end
check(NS.PerformAction("DANCE") and invoked[1] == "DANCE", "sends the game token through the native action API")
check(not NS.PerformAction("LEAN") and invoked[2] == "LEAN", "reports the restriction flag from the native slash path")
check(not NS.PerformAction("/run foo") and not NS.PerformAction("UNUSED") and #invoked == 2, "does not execute arbitrary slash commands or hidden tokens")

C_ChatInfo.PerformEmote = nil
DoEmote = function(token) invoked[#invoked + 1] = token end
check(NS.PerformAction("WAVE") and invoked[3] == "WAVE", "uses the legacy wrapper when the modern method is absent")
DoEmote = nil
check(not NS.PerformAction("WAVE"), "missing action API fails without executing anything")

print("chat_actions_test: " .. checks .. " checks passed")
