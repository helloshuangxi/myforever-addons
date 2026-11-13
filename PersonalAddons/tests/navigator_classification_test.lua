local NS = {}
local root = "_forever_/Interface/AddOns/MyForeverNavigator/"
assert(loadfile(root .. "Data.lua"))("MyForeverNavigator", NS)
assert(loadfile(root .. "Classification.lua"))("MyForeverNavigator", NS)

local fields, source = {"id","category","service","tags","name","mapID","x","y"}, {}
for _, point in ipairs(NS.Points) do
    local values = {}
    for _, field in ipairs(fields) do values[#values+1] = tostring(point[field]) end
    source[#source+1] = table.concat(values,"\031")
end
local expected = {trainers=195, reputation=40, materials=109, special=26, services=57}
local primaryGroups = {}
for _, point in ipairs(NS.Points) do
    local id = NS.GetPointSubcategory(point)
    assert(type(id)=="string" and id:find(point.category .. ":",1,true)==1)
    assert(point.category=="special" or not id:find(":other",1,true),point.id .. " lacks a specific group")
    assert(NS.PointMatchesSubcategory(point,id))
    assert(NS.PointMatchesSubcategory(point,"all"))
    assert(NS.PointMatchesSubcategory(point,nil))
    assert(not NS.PointMatchesSubcategory(point,"unknown"))
    primaryGroups[point.category] = primaryGroups[point.category] or {}
    primaryGroups[point.category][id] = true
end
local function count(t) local n=0;for _ in pairs(t)do n=n+1 end;return n end
assert(count(primaryGroups.trainers)==9)
assert(count(primaryGroups.reputation)==14)
assert(count(primaryGroups.materials)==8)
assert(count(primaryGroups.special)==4)
assert(count(primaryGroups.services)==1)
local function get(category,id)
    for _, group in ipairs(NS.GetSubcategories(category)) do if group.id==id then return group end end
    error("missing group " .. id)
end
for category,total in pairs(expected) do
    assert(get(category,"all").count==total)
    local known = {}
    for _, group in ipairs(NS.GetSubcategories(category)) do
        assert(not known[group.id],"duplicate group ID")
        known[group.id]=true
        assert(type(group.label)=="string" and group.label~="")
        assert(group.count>=0 and group.count%1==0)
    end
end
assert(#NS.GetSubcategories("all")==1 and get("all","all").count==#NS.Points)
NS.DB={custom={{category="custom",name="私有地点"}}}
assert(get("all","all").count==#NS.Points,"custom data must not change NPC counts")
assert(#NS.GetSubcategories("favorites")==1 and #NS.GetSubcategories("custom")==1)

assert(get("materials","materials:alchemy").count==18)
assert(get("materials","materials:enchanting").count==8)
assert(get("materials","materials:tailoring").count==20)
assert(get("materials","materials:leatherworking").count==19)
assert(get("materials","materials:reagents").count==3)
assert(get("materials","materials:trade").count==19)
assert(get("special","special:mount").count==7)
assert(get("special","special:weapon-training").count==4)
assert(get("special","special:profession-advancement").count==11)
assert(get("special","special:other").count==4)

-- Exact role matching must keep class trainers separate from pet trainers,
-- class-specific quest contacts and commercial profession trainers.
local classRoles={warrior="战士",paladin="圣骑士",hunter="猎人",rogue="盗贼",priest="牧师",shaman="萨满祭司",mage="法师",warlock="术士",druid="德鲁伊"}
for key,name in pairs(classRoles) do
    local role={category="trainers",service=name .. "训练师",tags="职业训练师"}
    assert(NS.GetPointSubcategory(role)=="trainers:"..key,"exact trainer role: "..key)
    assert(get("trainers","trainers:"..key).count>0,"class has catalogue locations: "..key)
end
assert(NS.GetPointSubcategory({category="trainers",service="猎人宠物训练师",tags="宠物"})=="trainers:other","pet trainers are not hunter class trainers")
assert(NS.GetPointSubcategory({category="special",service="工程训练",tags="工程"})=="special:profession-advancement")
assert(not NS.PointMatchesSubcategory({category="reputation",service="拉文霍德：任务",tags="盗贼"},"trainers:rogue"),"class quest contacts are not class trainers")

local compound={category="materials",service="制皮与裁缝材料",tags="材料 供应商"}
assert(NS.GetPointSubcategory(compound)=="materials:leatherworking")
assert(NS.PointMatchesSubcategory(compound,"materials:tailoring"))
assert(NS.PointMatchesSubcategory(compound,"materials:leatherworking"))
assert(not NS.PointMatchesSubcategory(compound,"materials:alchemy"))
assert(NS.GetPointSubcategory({category="reputation",service="瑟银兄弟会：任务"})=="reputation:thorium-brotherhood","UTF-8 faction prefix survives colon splitting")
assert(NS.GetPointSubcategory({category="reputation",service="木喉要塞:任务"})=="reputation:timbermaw")
assert(NS.GetPointSubcategory({category="materials",service="未知",tags="炼金 附魔"})=="materials:alchemy")
assert(NS.PointMatchesSubcategory({category="materials",service="未知",tags="炼金 附魔"},"materials:enchanting"))
assert(NS.GetPointSubcategory({category="special",service="武器锻造专精任务",tags="锻造 铸剑"})=="special:profession-advancement","smith training is not a weapon master")
assert(NS.GetPointSubcategory({category="materials",service="假炼金内容",tags="材料"})=="materials:other","do not use weak substring inference")
assert(NS.GetPointSubcategory({category="special",service="未知",tags="未知"})=="special:other")
assert(NS.GetPointSubcategory(nil)=="other")
assert(NS.GetPointSubcategory({category="custom"})=="other")

local first=NS.GetSubcategories("materials")
first[1].count=0;first[2].label="changed"
assert(get("materials","all").count==109 and get("materials","materials:alchemy").label=="炼金","return independent UI descriptors")
for index, point in ipairs(NS.Points) do
    local values={}
    for _,field in ipairs(fields)do values[#values+1]=tostring(point[field])end
    assert(table.concat(values,"\031")==source[index],"classification must not mutate source data")
end
local original=NS.Points
local reversed={};for index=#original,1,-1 do reversed[#reversed+1]=original[index]end
NS.Points=reversed
local again=NS.GetSubcategories("materials")
for index,group in ipairs(again)do
    assert(group.id==NS.GetSubcategories("materials")[index].id)
    if index>1 then assert(group.id==first[index].id,"stable IDs/order independent of source order")end
end
NS.Points=original
print("Navigator classification: " .. #NS.Points .. " source records, stable groups, composite purposes and immutable counts passed")

assert(loadfile(root .. "Core.lua"))("MyForeverNavigator", NS)
LibQuestieDB={Enum={npcFlags={TRAINER=16,VENDOR=4,FLIGHT_MASTER=8,INNKEEPER=128,BANKER=256,AUCTIONEER=4096,STABLEMASTER=8192,REPAIR=16384}}}
local function classify(title,flags,friendly,starts)
    return NS.ClassifyQuestieNPC({subName=title,flags=flags,friendly=friendly,questStarts=starts})
end
for key,name in pairs(classRoles) do
    local p=classify(name.."训练师",16,"AH")
    assert(p.category=="trainers" and NS.GetPointSubcategory(p)=="trainers:"..key)
end
assert(classify("猎人宠物训练师",16,"AH").category=="services","pet trainer is not a class trainer")
assert(NS.GetPointSubcategory(classify("潜行者训练师",16,"AH"))=="trainers:rogue","Questie zhCN rogue synonym")
assert(NS.GetPointSubcategory(classify("高级潜行者训练师",16,"AH"))=="trainers:rogue")
assert(NS.GetPointSubcategory(classify("武器大师",16,"AH"))=="special:weapon-training")
assert(classify("炼金术训练师",16,"AH").category=="profession-trainers","profession trainer has its own purpose, separate from class trainers")
assert(NS.GetPointSubcategory(classify("Alchemy Supplies",4,"AH"))=="materials:alchemy")
assert(NS.GetPointSubcategory(classify("武器锻造供应商",4,"AH"))=="services:vendor","generic supplies do not invent material specialities")
assert(classify("军需官",4,"AH").category=="reputation")
for title,info in pairs({
    ["旅店老板"]={128,"innkeeper"},["银行职员"]={256,"banker"},
    ["拍卖师"]={4096,"auctioneer"},["兽栏管理员"]={8192,"stable-master"},
    ["飞行管理员"]={8,"flight-master"},["修理工"]={16388,"repair"},
}) do
    assert(NS.GetPointSubcategory(classify(title,info[1],"AH"))=="services:"..info[2])
end
assert(NS.GetPointSubcategory(classify("",0,nil))=="npcs:hostile","nil DB friendliness means hostile to both")
assert(NS.GetPointSubcategory(classify("",0,"A",{123}))=="npcs:quest-contact")
assert(NS.GetPointSubcategory(classify("",0,"AH"))=="npcs:other")
local retained=NS.ClassifyQuestieNPC({subName="新标题",flags=4,friendly="AH"},NS.Points[1])
assert(retained.category==NS.Points[1].category and retained.service==NS.Points[1].service,"known NPC's authored purpose retained on extra maps")
print("Navigator Questie roles: class/profession/pet separation, merchants, services, quest contacts and hostility passed")
