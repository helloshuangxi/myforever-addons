local W = ...
UnitName = function() return "示例角色" end
GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
UnitClass = function() return "牧师", "PRIEST" end
UnitLevel = function() return 32 end
GetServerTime = os.time
local NS = LoadAddon("MyForeverCoach")
W.fire("ADDON_LOADED", "MyForeverCoach")
W.fire("PLAYER_LOGIN")
local day = NS.GetBehaviorToday and NS.GetBehaviorToday()
if day then
    day.time.observedSeconds, day.time.combatSeconds, day.time.nonCombatSeconds, day.time.unknownCombatSeconds = 5025, 1310, 3600, 115
    for k, v in pairs({ combatsEntered = 41, castsSucceeded = 612, xpGained = 18450, questsTurnedIn = 7, deaths = 1, castsFailed = 23, castsInterrupted = 4 }) do day.counts[k] = v end
end
NS.db.settings.shown = true
NS.RenderUI()
return { { name = "玩家行为", frame = NS.panel } }
