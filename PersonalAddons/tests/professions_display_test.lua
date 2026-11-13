local ns, checks = {}, 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local base = PROFESSIONS_DISPLAY_BASE or "_forever_/Interface/AddOns/MyForeverProfessions/"
assert(loadfile(base .. "API.lua"))("MyForeverProfessions", ns)
C_Spell = {GetSpellInfo = function(id) return {iconID = id + 1} end}
local mining = {id = 186, name = "采矿", rank = 3, maxRank = 75, recipes = {}}
local rows = ns.DisplayProfessions({mining}, true)
check(#rows == 4 and rows[1] == mining, "learned profession unchanged; three secondary entries added")
for i, id in ipairs({185,129,356}) do
    local row = rows[i + 1]
    check(row.id == id and row.unlearned == true, "secondary entry has correct identity")
    check(row.rank == nil and row.maxRank == nil and #row.recipes == 0, "unlearned skills never invent rank or recipes")
end
local firstAid = {id=129, name="急救", rank=12,maxRank=75,recipes={{id=1}}}
local input = {mining,firstAid}
rows = ns.DisplayProfessions(input, true)
check(#rows==4 and rows[3]==firstAid and not rows[3].unlearned, "learned secondary retains real rank and recipes")
check(#input==2 and input[1]==mining and input[2]==firstAid, "projection never changes authoritative input")
check(#ns.DisplayProfessions({},false)==0, "loading does not invent unlearned skills")
check(#ns.DisplayProfessions(input,false)==2, "transient loading preserves learned rows")
rows=ns.DisplayProfessions({},true)
check(#rows==3 and rows[1].id==185 and rows[2].id==129 and rows[3].id==356, "ready character with no professions still has secondary entries")
C_Spell=nil
check(ns.DisplayProfessions({},true)[1].icon==nil, "icon API absence is safe")
print("professions_display_test: " .. checks .. " checks passed")
