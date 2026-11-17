-- Read-only diagnostic contracts. No native binding or spell action is run.
local checks,secret,combat=0,{},false
local function eq(a,b,why)
    checks=checks+1
    assert(a==b,why..": expected "..tostring(b)..", got "..tostring(a))
end
issecretvalue=function(v) return v==secret end
InCombatLockdown=function() return combat end
GetTime=function() return 10 end
GetServerTime=function() return 123 end
local methods={}
function methods:RegisterEvent() end
function methods:SetScript(k,v) self[k]=v end
CreateFrame=function() return setmetatable({},{__index=methods}) end
local bindings,reads={},0
GetBindingAction=function(key) reads=reads+1;return bindings[key] or "ACTIONBUTTON1" end
UnitExists=function(unit) return unit=="nameplate1" or unit=="player" end
UnitGUID=function(unit)
    if unit=="nameplate1" then return "Player-fixture" end
    if unit=="player" then return "Player-self" end
end
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."Diagnostics.lua"))("MyForeverTargets",NS)
local D=NS.Diagnostics
D.Initialize()
local before=reads
eq(D.CastRouteSnapshot("off"),false,"disabled logger does not sample routes")
eq(reads,before,"disabled logging makes no binding queries")
D.Start()
NS.DB={legacyNameBridgeEnabled=true}
local row={side="friendly",unit="nameplate1",expectedGUID="Player-fixture",attrs={unit="nameplate1",["combat-key-count"]=6},shield={IsShown=function() return true end}}
function row:GetName() return "FixtureFriendly" end
function row:GetAttribute(k) return self.attrs[k] end
for i=1,6 do row.attrs["combat-key"..i]="F"..i;row.attrs["combat-proxy"..i]="NameProxy"..i end
local nameState={prepared=true,reason="prepared",count=6,guid="Player-fixture"}
local fixedState={ready=false,stable=false,availableKeys=0}
local function controller(attrs)
    return {GetAttribute=function(_,k) return attrs[k] end}
end
NS.CombatCast={Status=function() return nameState end,owner=controller({["combat-active"]=true})}
NS.CombatHover={Status=function() return fixedState end,owner=controller({["mfch-combat"]=true})}
bindings.F1="CLICK NameProxy1:LeftButton"
combat=true
D.CastRouteSnapshot("shield_blocked",row)
local function last() local e=MyForeverTargetsLogDB.events;return e[#e] end
eq(last().kind,"CAST_ROUTE","shield row gets an independent route record")
local f=last().fields
eq(f.reason,"shield_blocked","blocked-row reason retained")
eq(f.row,"FixtureFriendly","blocked row captured even when no hovered row exists")
eq(f.unitExists,true,"unit existence preserved")
eq(f.identityMatches,true,"public identity comparison")
eq(f.shieldShown,true,"shield state explicit")
eq(f.namePrepared,true,"prepared name route recorded")
eq(f.fixedReady,false,"fixed route exclusion remains explicit")
eq(f.nameCombat,true,"native name owner combat state recorded")
eq(f.fixedCombat,true,"fixed owner state recorded")
eq(f.key1,"F1","prepared key recorded")
eq(f.binding1,"CLICK NameProxy1:LeftButton","actual override queried")
eq(f.proxy1,"NameProxy1","expected native proxy recorded")
eq(f.keysNotExpanded,2,"key details bounded to four")
eq(f.key5,nil,"no unbounded key expansion")
eq(f.observationOnly,true,"read-only evidence explicit")
eq(f.recipientProven,false,"routing does not prove recipient")
local n=#MyForeverTargetsLogDB.events
D.CastRouteSnapshot("different_reason",row)
eq(#MyForeverTargetsLogDB.events,n,"unchanged routes do not spam on new reasons")
bindings.F1="ACTIONBUTTON1"
D.CastRouteSnapshot("poll",row)
eq(#MyForeverTargetsLogDB.events,n+1,"binding handoff changes are recorded")
eq(last().fields.binding1,"ACTIONBUTTON1","fallthrough is visible")
UnitGUID=function(unit) if unit=="nameplate1" then return secret end end
D.CastRouteSnapshot("restricted",row)
eq(last().fields.liveGUID,"[restricted]","secret GUID is redacted")
eq(last().fields.identityMatches,"[unknown]","secret GUID is not an identity match or mismatch")
UnitGUID=function() return nil end
row.unit="nameplate2"
D.CastRouteSnapshot("missing",row)
eq(last().fields.unitExists,false,"known absent unit keeps false instead of missing")
fixedState={ready=true,stable=true,availableKeys=1}
NS.CombatHover.owner=controller({["mfch-combat"]=true,["friendly-keys"]=1,
    ["friendly-key1"]="H",["friendly-keyproxy1"]=1,["friendly-proxyname1"]="FixedProxy"})
row.unit="player";row.attrs.unit="player";row.expectedGUID="Player-self"
bindings.H="CLICK FixedProxy:LeftButton"
D.CastRouteSnapshot("fixed",row)
eq(last().fields.fixedReady,true,"fixed route readiness captured")
eq(last().fields.key1,"H","fixed route uses controller key table")
eq(last().fields.proxy1,"FixedProxy","fixed route proxy captured")
eq(last().fields.binding1,"CLICK FixedProxy:LeftButton","fixed route actual binding captured")
NS.HoveredTile=row
nameState.name="Fixture Fullname"
D.frame.OnEvent(D.frame,"UNIT_SPELLCAST_SENT","player",secret,"Cast-fixture",19742)
local detail
for i=#MyForeverTargetsLogDB.events,1,-1 do
    if MyForeverTargetsLogDB.events[i].kind=="SPELL_SENT_DETAIL" then detail=MyForeverTargetsLogDB.events[i].fields;break end
end
eq(detail.sentTarget,"[restricted]","native recipient secrets are redacted in the bounded detail record")
eq(detail.spellID,19742,"native spell id survives independently of general snapshot budget")
eq(detail.expectedName,"Fixture Fullname","frozen player name retained without parsing or guessing")
eq(detail.expectedGUID,"Player-self","expected row identity is separate from native recipient")
eq(detail.recipientProven,false,"sent recipient does not certify a successful or correct cast")
eq(MyForeverTargetsLogDB.events[#MyForeverTargetsLogDB.events].kind,"UNIT_SPELLCAST_SENT","general spell snapshot still follows the bounded detail")
D.Stop("test")
n=#MyForeverTargetsLogDB.events
before=reads
D.CastRouteSnapshot("off_again",row)
eq(#MyForeverTargetsLogDB.events,n,"stopped logger does not append")
eq(reads,before,"stopped logger makes no binding queries")
print("targets_cast_route_log_test: "..checks.." checks passed")
