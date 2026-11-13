local NS = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/Core.lua"))("MyForeverNavigator",NS)
local frames, commands = {}, {}
CreateFrame = function()
    local f={scripts={},events={}}
    function f:SetScript(k,v) self.scripts[k]=v end
    function f:RegisterEvent(e) self.events[e]=true end
    frames[#frames+1]=f
    return f
end
SlashCmdList={}
local ui, refresh, hud, pins, started, stopped=0,0,0,0,nil,0
local questUI, questRefresh=0,0
NS.InitializeQuestUI=function()questUI=questUI+1 end
NS.RefreshQuestSession=function()questRefresh=questRefresh+1 end
NS.OpenQuestNavigation=function(id)commands.questID=id end
NS.CreateUI=function() ui=ui+1 end
NS.RefreshUI=function() refresh=refresh+1 end
NS.RefreshHUD=function() hud=hud+1 end
NS.UpdateMapPin=function() pins=pins+1 end
NS.ToggleUI=function(force) commands.force=force;commands.toggled=true end
NS.SetSearch=function(s) commands.search=s end
NS.GetPlayerPosition=function() return 1453,.5,.6 end
C_Map={GetMapInfo=function() return {name="暴风城"} end,GetBestMapForUnit=function() return 1453 end}
NS.Start=function(p) started=p;NS.DB.activeID=p.id end
NS.Stop=function() NS.DB.activeID=nil;stopped=stopped+1 end
NS.Print=function(s) commands.last=s end
assert(loadfile("_forever_/Interface/AddOns/MyForeverNavigator/Main.lua"))("MyForeverNavigator",NS)
local f=frames[1]
f.scripts.OnEvent(f,"ADDON_LOADED","OtherAddon")
assert(ui==0)
f.scripts.OnEvent(f,"ADDON_LOADED","MyForeverNavigator")
assert(ui==1 and MyForeverNavigatorDB==NS.DB and type(SlashCmdList.MYFOREVERNAVIGATOR)=="function")
f.scripts.OnEvent(f,"ADDON_LOADED","MyForeverNavigator")
assert(ui==1,"no duplicate initialization")
NS.HandleCommand("木喉")
assert(commands.force==true and commands.search=="木喉")
NS.HandleCommand("go 1453 50 60 测试地点")
assert(started and started.x==.5 and started.y==.6 and started.name=="测试地点")
NS.HandleCommand("go 1453 101 20 错误")
assert(#NS.DB.custom==1,"invalid coordinates must not save")
f.scripts.OnUpdate(f,.25)
assert(hud>=1 and pins>=1)
NS.HandleCommand("stop")
assert(stopped==1 and NS.DB.activeID==nil)
NS.HandleCommand("save 我的站位")
assert(#NS.DB.custom==2 and NS.DB.custom[2].name=="我的站位")
f.scripts.OnEvent(f,"PLAYER_ENTERING_WORLD")
assert(refresh>0)
NS.HandleCommand("way 50,60 当前地图")
assert(started and started.mapID==1453 and started.name=="当前地图" and started.x==.5)
NS.HandleCommand("way #1426 25 30 丹莫罗目标")
assert(started and started.mapID==1426 and started.name=="丹莫罗目标" and started.y==.3)
local count=#NS.DB.custom
NS.HandleCommand("way 150 30 错误坐标")
assert(#NS.DB.custom==count)
local point=NS.DB.custom[1]
NS.ImportWaypoint=function(name) commands.importName=name;return point end
NS.HandleCommand("pin 地图目标")
assert(started==point and commands.importName=="地图目标")
NS.ImportWaypoint=function()return nil,"没有标记" end
NS.HandleCommand("pin")
assert(commands.last=="没有标记")
assert(SLASH_MYFOREVERNAVIGATOR1=="/mynav" and SLASH_MYFOREVERNAVIGATOR2==nil,"does not claim another addon's /way alias")
assert(questUI==1,"quest UI initialized once")
NS.HandleCommand("quest 182")
assert(commands.questID==182,"explicit quest command reaches navigation")
C_QuestLog={GetSelectedQuest=function()return 3361 end}
NS.HandleCommand("quest")
assert(commands.questID==3361,"selected quest command")
NS.HandleCommand("quest nope")
assert(commands.questID==3361 and commands.last:find("先选择任务",1,true),"invalid quest command rejected")
assert(f.events.QUEST_LOG_UPDATE)
f.scripts.OnEvent(f,"QUEST_LOG_UPDATE")
assert(questRefresh==1,"quest updates validate active session")
print("Navigator startup: event lifecycle, slash search, coordinate navigation, save and stop passed")
