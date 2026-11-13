local W = ...
GetMoney = function() return 1234567 end
GetRealZoneText = function() return "艾尔文森林" end
GetZoneText = GetRealZoneText
GetSubZoneText = function() return "闪金镇" end
C_Map = { GetBestMapForUnit = function() return 1429 end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.423, 0.657 end } end }
C_Container = { GetContainerNumFreeSlots = function() return 4, 0 end, GetContainerNumSlots = function() return 16 end }
GetInventoryItemDurability = function() return 62, 100 end
local NS = LoadAddon("MyForeverFieldKit")
W.fire("ADDON_LOADED", "MyForeverFieldKit")
W.fire("PLAYER_LOGIN")
local panel = MyForeverFieldKitPanel
if not panel:IsShown() then SlashCmdList.MYFOREVERFIELDKIT("") end
W.now = W.now + 754
SlashCmdList.MYFOREVERFIELDKIT("lock"); SlashCmdList.MYFOREVERFIELDKIT("lock")
return { { name = "随身手册", frame = panel } }
