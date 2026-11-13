-- Profession navigation contracts with simulated APIs; not an in-game test.
local root="_forever_/Interface/AddOns/MyForeverNavigator/"
local checks=0
local function check(value,message) checks=checks+1;assert(value,message)end
local function vector(x,y)return{x=x,y=y,GetXY=function(self)return self.x,self.y end}end
local nativePoint,tracked
CreateFrame,WorldMapFrame,UIParent,debugprofilestop=nil,nil,nil,nil
Enum={UIMapType={Zone=3,Continent=2}}
CreateVector2D=vector
C_Map={
    GetBestMapForUnit=function()return 1455 end,
    GetMapInfo=function(id)return{name="测试地图"..id,mapType=id==100 and 2 or 3,parentMapID=id~=100 and 100 or 0}end,
    GetPlayerMapPosition=function()return vector(.1,.1)end,
    GetMapWorldSize=function()return 1000,700 end,
    GetWorldPosFromMapPos=function(_,p)return 0,vector(p.x*1000,p.y*700)end,
    CanSetUserWaypointOnMap=function()return true end,
    SetUserWaypoint=function(p)nativePoint=p;return true end,
    GetUserWaypoint=function()return nativePoint end,
}
UiMapPoint={CreateFromCoordinates=function(id,x,y)return{uiMapID=id,position=vector(x,y)}end}
C_SuperTrack={SetSuperTrackedUserWaypoint=function(v)tracked=v end,IsSuperTrackingUserWaypoint=function()return tracked==true end}
UnitFactionGroup=function()return"Alliance"end
GetPlayerFacing=function()return 0 end
IsInInstance=function()return false end
InCombatLockdown=function()return false end
GetTime=function()return 0 end
local NS={}
for _,file in ipairs({"Core","Data","Classification","Provider","QuestieCatalog","Navigation"})do
    assert(loadfile(root..file..".lua"))("MyForeverNavigator",NS)
end
NS.RefreshHUD=function()end;NS.RefreshUI=function()end
NS.Initialize(nil)
local function serialize(value)
    if type(value)~="table"then return type(value)..":"..tostring(value)end
    local parts={}
    for k,v in pairs(value)do parts[#parts+1]=serialize(k).."="..serialize(v)end
    table.sort(parts);return"{"..table.concat(parts,",").."}"
end
local original=serialize(NS.Points)
local professions={
    {"mining","采矿训练师",{"矿工","Junior Mining Trainer","Mining Trainer"}},
    {"herbalism","草药学训练师",{"采药人","见习采药师","高级采药师","Junior Herbalism Trainer"}},
    {"skinning","剥皮训练师",{"剥皮师","高级屠夫","Skinning\194\160Trainer","Junior Skinning Trainer"}},
    {"alchemy","炼金术训练师",{"初级炼金师","中级炼金师","高级炼金师","大师级炼金师","Journeyman Alchemist Trainer","Artisan Alchemist"}},
    {"blacksmithing","锻造训练师",{"初级铁匠","中级铁匠","高级铁匠","大师级铁匠","铸甲师","Master Blacksmith","Special Weapon Crafter"}},
    {"leatherworking","制皮训练师",{"初级制皮师","中级制皮师","高级制皮师","大师级制皮训练师","部族制皮训练师","Master Dragonscale Leatherworker"}},
    {"tailoring","裁缝训练师",{"初级裁缝","中级裁缝","高级裁缝","大师级暗纹裁缝","Expert Tailor"}},
    {"engineering","工程训练师",{"初级技师","中级技师","高级技师","大师级侏儒技师","Master Goblin Engineer","工程学供应商"}},
    {"enchanting","附魔训练师",{"初级附魔师","中级附魔师","高级附魔师","大师级附魔师","Journeyman Enchanter","Artisan Enchanter"}},
    {"first-aid","急救训练师",{"急救训练师","外科医疗队","医师","Medic","Physician","Trauma Surgeon"}},
    {"cooking","烹饪训练师",{"烹饪训练师","厨师","高级厨师","Cook","Superior Cook"}},
    {"fishing","钓鱼训练师",{"钓鱼训练师","渔夫","渔具供应商","高级渔夫","Fishing Trainer & Supplies","Fisherman"}},
}
LibQuestieDB={Enum={npcFlags={TRAINER=16,VENDOR=4,REPAIR=16384}}}
local function classify(title,flags,template)
    return NS.ClassifyQuestieNPC({subName=title,flags=flags,friendly="AH"},template)
end
for _,profession in ipairs(professions)do
    for _,title in ipairs(profession[3])do
        local p=classify(title,19)
        check(p.category=="profession-trainers" and NS.GetPointProfession(p)==profession[1],"professional role/title "..title)
        check(NS.PointMatchesSubcategory(p,"profession-trainers:"..profession[1]),"profession subgroup "..title)
        check(classify(title,4).professionKey==nil,"same title without TRAINER is not a trainer: "..title)
    end
end
for _,title in ipairs({"法师训练师","潜行者训练师","Pet Trainer","宠物训练师","武器大师","Weapon Master","Mining Supplies","炼金材料商人","不是采矿训练师","初级炼金师的朋友"})do
    check(classify(title,16).professionKey==nil,"other roles do not leak into professions: "..title)
end
local records,ids={},{}
local function record(id,name,title,flags,mapID,x,y)
    records[id]={n=7,[1]=name,[2]=title,[3]={[30000+(mapID or 1455)]={{x or 60,y or 60}}},[4]=flags,[5]="AH"}
    ids[#ids+1]=id
end
for i,profession in ipairs(professions)do record(900000+i,"普通专业导师"..i,profession[3][1],19)end
-- Keep an actual NBSP title in the catalogue fixture, not only direct role tests.
records[900003][2]="Skinning\194\160Trainer"
local overlaps={
    [3181]={"first-aid","急救训练师"},[5164]={"blacksmithing","铸甲师"},
    [7406]={"engineering","大师级侏儒技师"},[8736]={"engineering","大师级技师"},
    [12920]={"first-aid","外科医疗队"},[12939]={"first-aid","外科医疗队"},
}
local curated={}
for _,point in ipairs(NS.Points)do
    if overlaps[point.npcID]then
        curated[point.npcID]=point
        record(point.npcID,point.name,overlaps[point.npcID][2],19,point.mapID,point.x*100,point.y*100)
    elseif point.npcID==2626 then
        record(2626,point.name,"渔夫",4,point.mapID,point.x*100,point.y*100)
    end
end
record(1684,"卡拉·深水","渔具供应商",6)
record(54,"科瑞娜·斯蒂利","武器锻造师",16388)
record(900101,"职业训练导师","法师训练师",16)
record(900102,"宠物训练导师","宠物训练师",16)
record(900103,"武器训练导师","武器大师",16)
table.sort(ids)
local db={Enum=LibQuestieDB.Enum,Npc={
    GetAllIds=function()return ids end,
    GetAll=function(id)return records[id]end,
    Get=function(id,key)
        local p=records[id]
        return p and (key=="name" and p[1] or key=="spawns" and p[3])or nil
    end,
}}
LibQuestieDB=db
local zones={GetUiMapIdByAreaId=function(_,id)return id-30000 end,IsDungeonZone=function()return false end}
QuestieLoader={ImportModule=function(_,name)return name=="ZoneDB"and zones or nil end}
Questie={API={isReady=false}}
local before=NS.GetSubcategories("profession-trainers")
check(before[1].count==0,"offline curated list is not guessed to contain ordinary trainers")
local rawBefore=serialize(records)
NS.UpdateQuestieCatalog(2)
check(NS.QuestieProfessionRoles==nil,"unready data does not publish profession roles")
Questie.API.isReady=true
for _=1,100 do
    NS.UpdateQuestieCatalog(1)
    if NS.GetQuestieCatalogStatus().status=="ready"then break end
end
check(NS.GetQuestieCatalogStatus().status=="ready","catalogue became ready")
check(serialize(records)==rawBefore and serialize(NS.Points)==original,"upstream and authored catalogue remain immutable")
local all=NS.Search("",{category="profession-trainers",faction="all"})
check(#all==18,"twelve ordinary fixture trainers plus six preserved curated secondary members")
check(NS.GetSubcategories("profession-trainers")[1].count==#all,"counts reflect complete primary and secondary membership")
for i,profession in ipairs(professions)do
    local id=900000+i
    local list=NS.Search(profession[2],{category="profession-trainers",subcategory="profession-trainers:"..profession[1],faction="all"})
    local found
    for _,p in ipairs(list)do if p.npcID==id then found=p end end
    check(found~=nil,"generic training keyword finds ordinary title: "..profession[1])
    check(NS.GetPointProfession(found)==profession[1],"result keeps profession identity")
    check(NS.ToggleFavorite(found.id),"profession trainer can be favorited")
    local favorites=NS.Search("",{category="favorites",faction="all"})
    local favoriteFound=false
    for _,p in ipairs(favorites)do if p.id==found.id then favoriteFound=true end end
    check(favoriteFound,"profession trainer survives favorite lookup")
    check(NS.Start(found),"profession trainer starts navigation")
    check(NS.GetNavigation().point.id==found.id and NS.GetPoint(found.id).npcID==id,"profession trainer navigation uses same point")
    NS.Stop()
end
for id,info in pairs(overlaps)do
    local list=NS.Search(tostring(id),{category="profession-trainers",subcategory="profession-trainers:"..info[1],faction="all"})
    local found
    for _,p in ipairs(list)do if p.npcID==id then found=p end end
    check(found and found.id==curated[id].id and found.category=="special","curated identity and primary classification retained: "..id)
    check(NS.GetPointSubcategory(found)=="special:profession-advancement","old special subgroup retained: "..id)
    check(NS.PointMatchesSubcategory(found,"profession-trainers:"..info[1]),"secondary profession subgroup available: "..id)
    check(curated[id].professionKey==nil,"secondary membership does not mutate authored point: "..id)
    check(NS.Start(found) and NS.GetPoint(found.id).id==curated[id].id,"curated secondary trainer navigates with old ID: "..id)
    NS.Stop()
end
for _,id in ipairs({2626,1684,54,900101,900102,900103})do
    local list=NS.Search(tostring(id),{category="profession-trainers",faction="all"})
    local leaked=false
    for _,p in ipairs(list)do if p.npcID==id then leaked=true end end
    check(not leaked,"non-trainer, class, pet or weapon role excluded: "..id)
end
local publishedRoles=NS.QuestieProfessionRoles
LibQuestieDB={Enum=db.Enum,Npc={GetAllIds=db.Npc.GetAllIds,GetAll=function(id)
    if id<=3181 then return records[id]end
    error("simulated DB interruption")
end}}
NS.UpdateQuestieCatalog(2)
check(NS.GetQuestieCatalogStatus().status=="error" and NS.QuestieProfessionRoles==publishedRoles,"partial rebuild never replaces published secondary roles")
check(#NS.Search("",{category="profession-trainers",faction="all"})==18,"last good professional catalogue survives provider failure")
check(serialize(NS.Points)==original and serialize(records)==rawBefore,"navigation, favorites and failures never mutate source data")
print("Navigator profession trainers: "..checks.." behavioral checks passed (simulated client, not in-game tests)")
