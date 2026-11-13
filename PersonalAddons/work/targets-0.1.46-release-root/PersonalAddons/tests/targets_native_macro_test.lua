-- Configuration simulation only: no native mouseover, macro, or spell is run.
-- Native-only controllers leave user macros and keys untouched. The separately
-- authorized ordinary-spell bridge has its own integration fixture.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local calls={}
local function forbidden(name)
    calls[name]=0
    return function()
        calls[name]=calls[name]+1
        error("native macro controllers must not call "..name)
    end
end
local secret,combat={},false
issecretvalue=function(value) return value==secret end
InCombatLockdown=function() return combat end
for _,name in ipairs({"CreateFrame","RegisterStateDriver","UnregisterStateDriver",
    "SecureHandlerWrapScript","SecureHandlerSetFrameRef","SetOverrideBindingClick","ClearOverrideBindings",
    "SetBinding","SetBindingClick","SaveBindings","CreateMacro","EditMacro","GetMacroBody",
    "GetMacroInfo","GetMacroIndexByName","GetNumMacros","GetActionInfo","GetBindingKey","GetBindingAction",
    "GetMouseFoci","MouseIsOver","UnitExists","UnitGUID","UnitName","UnitIsPlayer",
    "SecureCmdOptionParse","RunMacroText","TargetUnit","ClearTarget","SpellStopCasting"}) do
    _G[name]=forbidden(name)
end
C_ActionBar={GetActionInfo=forbidden("C_ActionBar.GetActionInfo")}
C_Spell={GetSpellName=forbidden("C_Spell.GetSpellName"),GetSpellInfo=forbidden("C_Spell.GetSpellInfo")}
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
eq(NS.NativeMacroOnly,true,"Core defaults to the user's native mouseover macro policy")
eq(NS.PreserveCastTarget,true,"the legacy target-preservation guard remains enabled")
eq(NS.LegacyNameBridge,true,"Core separately enables the authorized ordinary-spell name bridge")
NS.LegacyNameBridge=false -- Explicit pure-native policy fixture.
NS.Initialize(nil)
NS.ReadUnit=forbidden("NS.ReadUnit")
NS.Diagnostics={Record=forbidden("Diagnostics.Record"),BeginCastAttempt=forbidden("Diagnostics.BeginCastAttempt")}
local userBody="/cast [@mouseover,nodead,harm] 恐惧术; 恐惧术;"
local macros={[1]={body=userBody,name="恐惧术悬停"}}
local bindings={Z="ACTIONBUTTON1",W="MULTIACTIONBAR1BUTTON3"}
local actionSlots={[1]={kind="macro",id=1},[63]={kind="spell",id=679}}
local currentTarget={guid="Creature-0-7121-0-4-735-5DEAEBC80E"}
local originalTarget=currentTarget
ActionButton1={action=1}
MultiBarBottomLeftButton3={action=63}
assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."GUIDProbe.lua"))("MyForeverTargets",NS)
local probe=NS.GUIDProbe
eq(probe.Active(),false,"the historical experiment never activates")
eq(probe.GetAttempt(),nil,"the historical experiment starts no attempt")
eq(probe.Resolve(row),nil,"the historical experiment resolves no casting units")
eq(probe.Capture("A"),false,"the historical experiment records no target")
eq(probe.SetMode("guid_macro"),false,"the historical experiment cannot select a route")
eq(probe.Prepare(),false,"the historical experiment creates no actions")
probe.UpdateLabels()
eq(probe.Stop(),true,"stopping the inert experiment is harmless")
eq(probe.Command("integrated_macro"),false,"old commands cannot reopen the experiment")
eq(#probe.proxies,0,"the historical experiment has no proxies")
local Nearby,Combat=NS.NearbyCast,NS.CombatCast
local readRow=forbidden("row access")
local row=setmetatable({}, {__index=readRow,__newindex=readRow})
local invoked={nearby={},combat={}}
local function call(module,name,...)
    local object=module=="nearby" and Nearby or Combat
    eq(type(object[name]),"function",module.." exposes "..name)
    invoked[module][name]=true
    return object[name](...)
end
for _,name in ipairs({"BuildGUIDMacro","BuildFallback","BuildMacro","GuardMacro",
    "BuildUserMacro","BuildUserFallback","FrozenUserMacro"}) do
    eq(call("nearby",name,"Creature-0-7121-0-4-735-5DEAEBC80E",userBody,true,"enemy"),nil,
        name.." cannot generate or rewrite a production cast command")
end
eq(call("nearby","MacroHasHarmfulCast",userBody),false,"native controllers do not classify user macro contents")
eq(call("nearby","KnownUniqueNPC",row),false,"native controllers do not resolve names or identity uniqueness")
local snapshot,eligible=call("nearby","SnapshotRow",row)
eq(snapshot,nil,"native controllers provide no bridge snapshot")
eq(eligible,false,"native rows are not reported as bridge eligible")
eq(call("combat","BuildMacros",row,{actionKind="spell",spell="神圣打击(等级 1)",keys={"Z"}}),nil,
    "combat cannot prepare GUID, name, or fallback macros")
for _,inCombat in ipairs({false,true}) do
    combat=inCombat
    for _,name in ipairs({"Install","Enter","Refresh","Reconcile"}) do
        local enabled,count=call("nearby",name,row)
        eq(enabled,false,"nearby "..name.." never activates a bridge")
        eq(count,0,"nearby "..name.." never captures a skill key")
    end
    call("nearby","Leave",row)
    for _,name in ipairs({"Install","ArmRow","RefreshAll","Reconcile"}) do
        local enabled,count=call("combat",name,row)
        eq(enabled,false,"combat "..name.." never activates a bridge")
        eq(count,0,"combat "..name.." never captures a skill key")
    end
    for _,side in ipairs({"friendly","enemy"}) do
        eq(#call("nearby","DiscoverActions",side,true),0,"no action scan for "..side)
    end
    for _,module in ipairs({"nearby","combat"}) do
        for _,argument in ipairs({false,row}) do
            local status=call(module,"Status",argument or nil)
            eq(status.native,true,"status identifies native macro handling")
            eq(status.prepared,false,"status never claims a generated cast is prepared")
            eq(status.count,0,"status has no captured keys")
            eq(status.reason,"native_macro_only","status explains the inactive bridge")
            eq(status.castMode,"native_mouseover","status does not claim GUID dispatch")
        end
    end
end
eq(Nearby.owner,nil,"Nearby has no binding owner")
eq(Combat.owner,nil,"Combat has no binding owner")
eq(#Nearby.proxies,0,"Nearby creates no generated actions")
eq(#Combat.proxies,0,"Combat creates no generated actions")
eq(#Combat.rows,0,"Combat installs no secure row hooks")
eq(next(Combat.Snippets),nil,"native controllers install no legacy secure snippets")
for module,object in pairs({nearby=Nearby,combat=Combat}) do
    for name,value in pairs(object) do
        if type(value)=="function" then eq(invoked[module][name],true,"all native public entries were exercised: "..name) end
    end
end
-- The policy is captured at module load. A later flag write is not a supported
-- hot switch and must not revive generated actions without reloading the UI.
NS.NativeMacroOnly=false
eq(Nearby.Enter(row),false,"runtime flag changes cannot enable an uninstalled nearby controller")
eq(Combat.ArmRow(row),false,"runtime flag changes cannot enable an uninstalled combat controller")
for _,policy in ipairs({"missing","restricted"}) do
    local other={}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",other)
    other.LegacyNameBridge=false
    if policy=="missing" then other.NativeMacroOnly=nil else other.NativeMacroOnly=secret end
    assert(loadfile(root.."NearbyCast.lua"))("MyForeverTargets",other)
    assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",other)
    eq(other.NearbyCast.Enter(row),false,policy.." policy cannot enable the legacy nearby bridge")
    eq(other.CombatCast.ArmRow(row),false,policy.." policy cannot enable the legacy combat bridge")
end
-- The production ordinary-spell exception must not revive combat or GUID
-- routes. NearbyCast's authorized target/ownership behavior has a separate test.
do
    combat=false
    local production={}
    assert(loadfile(root.."Core.lua"))("MyForeverTargets",production)
    production.Initialize(nil)
    eq(production.NativeMacroOnly,true,"production retains original macro handling and disables old controllers")
    eq(production.PreserveCastTarget,true,"production retains the global target-preservation policy")
    eq(production.LegacyNameBridge,true,"production explicitly authorizes the ordinary-spell exception")
    eq(production.DB.legacyNameBridgeEnabled,true,"ordinary-spell exception starts enabled after authorization")
    production.ReadUnit=forbidden("production combat unit read")
    assert(loadfile(root.."CombatCast.lua"))("MyForeverTargets",production)
    assert(loadfile(root.."GUIDProbe.lua"))("MyForeverTargets",production)
    local enemy={side="enemy",unit="nameplate1",expectedGUID="Creature-0-1-2-3-4-5"}
    for _,name in ipairs({"Install","ArmRow","RefreshAll","Reconcile"}) do
        local enabled,count=production.CombatCast[name](enemy)
        eq(enabled,false,"ordinary-spell exception keeps combat "..name.." disabled")
        eq(count,0,"ordinary-spell exception gives combat "..name.." no keys")
    end
    eq(production.CombatCast.owner,nil,"ordinary-spell exception does not create a combat owner")
    eq(#production.CombatCast.proxies,0,"ordinary-spell exception does not create combat proxies")
    eq(production.GUIDProbe.Active(),false,"ordinary-spell exception keeps GUID experiments inactive")
    eq(production.GUIDProbe.Prepare(),false,"ordinary-spell exception cannot prepare a GUID action")
    eq(production.GUIDProbe.Command("integrated_macro"),false,"ordinary-spell exception cannot reactivate old GUID commands")
end
eq(macros[1].body,userBody,"the exact original mouseover macro body is preserved")
eq(macros[1].name,"恐惧术悬停","the original macro metadata is preserved")
eq(bindings.Z,"ACTIONBUTTON1","the original macro key is preserved")
eq(bindings.W,"MULTIACTIONBAR1BUTTON3","other original action keys are preserved")
eq(actionSlots[1].kind,"macro","the original macro slot is preserved")
eq(actionSlots[1].id,1,"the original macro reference is preserved")
eq(actionSlots[63].id,679,"ordinary skill slots are preserved too")
eq(currentTarget,originalTarget,"controllers do not change the target object")
eq(currentTarget.guid,"Creature-0-7121-0-4-735-5DEAEBC80E","controllers do not modify target identity")
for name,count in pairs(calls) do eq(count,0,"native policy performs no "..name) end
print("Targets native-macro simulated checks: "..checks.."; no game mouseover or spell was executed")
