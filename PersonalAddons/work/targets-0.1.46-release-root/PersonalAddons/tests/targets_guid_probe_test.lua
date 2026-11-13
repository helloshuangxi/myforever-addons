-- GUID experiment configuration and evidence simulation only. Restricted
-- snippets and native unit/cast resolution are not executed or established.
local checks=0
local function eq(actual,expected,why)
    checks=checks+1
    assert(actual==expected,why..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function yes(value,why) eq(not not value,true,why) end
local combat,clock=false,10
local secret=setmetatable({}, {__tostring=function() error("secret formatting") end,
    __eq=function() error("secret comparison") end})
issecretvalue=function(value) return rawequal(value,secret) end
InCombatLockdown=function() return combat end
GetTime=function() return clock end
GetServerTime=function() return 123 end
local methods,frames,wrappers,drivers={},{},{},{}
local function frame(kind,name,parent,template)
    local f=setmetatable({kind=kind,name=name,parent=parent,template=template or "",attrs={},refs={},scripts={},events={},shown=true}, {__index=methods})
    frames[#frames+1]=f;if name then _G[name]=f end;return f
end
function methods:GetName() return self.name end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:IsForbidden() return false end
function methods:Show() assert(not combat,"insecure show in combat");self.shown=true end
function methods:Hide() assert(not combat,"insecure hide in combat");self.shown=false end
function methods:GetAttribute(key) return self.attrs[key] end
function methods:SetAttribute(key,value) assert(not combat,"insecure attribute write in combat");self.attrs[key]=value end
function methods:SetScript(key,fn) self.scripts[key]=fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:HookScript(key,fn) self.hooks=self.hooks or {};self.hooks[key]=fn end
function methods:RegisterEvent(event) self.events[event]=true end
function methods:UnregisterAllEvents() self.events={} end
function methods:RegisterForClicks(...) self.clicks={...} end
function methods:EnableMouse(value) self.mouse=value end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(value) self.width=value end
function methods:SetWordWrap(value) self.wordWrap=value end
function methods:SetPoint(...) self.point={...} end
function methods:SetText(value) self.text=value end
function methods:GetText() return self.text end
function methods:CreateFontString() return frame("FontString",nil,self) end
for _,name in ipairs({"SetFrameStrata","SetBackdrop","SetBackdropColor","SetBackdropBorderColor"}) do methods[name]=function() end end
function methods:SetFrameRef(key,value) assert(not combat,"insecure ref write in combat");self.refs[key]=value end
function methods:GetFrameRef(key) return self.refs[key] end
CreateFrame=frame;UIParent=frame("Frame","UIParent")
SecureHandlerSetFrameRef=function(owner,key,value) owner:SetFrameRef(key,value) end
SecureHandlerWrapScript=function(row,event,owner,pre,post) wrappers[#wrappers+1]={row=row,event=event,owner=owner,pre=pre,post=post} end
RegisterStateDriver=function(owner,state,condition) assert(not combat,"insecure driver install in combat");drivers[#drivers+1]={owner=owner,state=state,condition=condition} end
local overrides,baseBinding={},"MULTIACTIONBAR1BUTTON3"
GetBindingAction=function(key,active) if key=="Z" then return active and overrides.Z or baseBinding end;return "" end
ClearOverrideBindings=function(owner) assert(not combat,"insecure override clear in combat");if overrides.owner==owner then overrides.Z,overrides.owner=nil,nil end end
SetOverrideBindingClick=function(owner,priority,key,button,mouseButton)
    assert(not combat,"insecure override install in combat");overrides[key]="CLICK "..button..":"..mouseButton;overrides.owner=owner
end
SetBinding=function() error("probe must not persist bindings") end
SaveBindings=SetBinding;SetBindingClick=SetBinding;CreateMacro=SetBinding;EditMacro=SetBinding
local units={player={guid="Player-test",name="测试玩家",player=true,harm=false},
    nameplate1={guid="Creature-A",name="测试同名怪物",player=false,harm=true},
    nameplate2={guid="Creature-B",name="测试同名怪物",player=false,harm=true}}
units.target=units.nameplate1
UnitExists=function(unit) return units[unit]~=nil end
UnitGUID=function(unit) return units[unit] and units[unit].guid end
UnitName=function(unit) return units[unit] and units[unit].name end
UnitIsPlayer=function(unit) return units[unit] and units[unit].player end
UnitCanAttack=function(_,unit) return units[unit] and units[unit].harm or false end
UnitIsDeadOrGhost=function(unit) return units[unit] and units[unit].dead or false end
UnitTokenFromGUID=function(guid) if guid=="Creature-A" then return "nameplate1" elseif guid=="Creature-B" then return "nameplate2" end end
C_Spell={GetSpellName=function(id) if id==679 then return "测试攻击" end end,
    DoesSpellExist=function(name) return name=="测试攻击" end,
    GetSpellInfo=function(name) if name=="测试攻击" then return {spellID=679} end end,
    IsSpellInRange=function() return false end}
GetMouseFoci=function() return {} end
local currentCLEU={n=0}
CombatLogGetCurrentEventInfo=function() return unpack(currentCLEU,1,currentCLEU.n) end
local function emit(event,...)
    for _,f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end
    end
end
local function cleu(kind,source,destination,spellID)
    currentCLEU={clock,kind,false,source,"测试施法者",0,0,destination,"测试收件人",0,0,
        spellID,"测试攻击",1,kind=="SPELL_MISSED" and "MISS" or 12,n=15}
    emit("COMBAT_LOG_EVENT_UNFILTERED")
end
local messages,suspended={},false
local root="_forever_/Interface/AddOns/MyForeverTargets/"
local NS={}
assert(loadfile(root.."Core.lua"))("MyForeverTargets",NS)
NS.NativeMacroOnly=false -- Historical experiment fixture; never the live policy.
NS.Initialize(nil)
NS.Print=function(message) messages[#messages+1]=message end
NS.NameplateTokens=function() return {"nameplate1","nameplate2"} end
NS.SetGUIDProbeSuspended=function(value) assert(not combat,"insecure bridge suspension in combat");suspended=value end
assert(loadfile(root.."Diagnostics.lua"))("MyForeverTargets",NS)
NS.Diagnostics.Initialize()
assert(loadfile(root.."GUIDProbeLog.lua"))("MyForeverTargets",NS)
assert(loadfile(root.."GUIDProbe.lua"))("MyForeverTargets",NS)
local Probe,Log=NS.GUIDProbe,NS.GUIDProbeLog
eq(type(Probe.Command),"function","GUID experiment exposes command routing")
eq(type(Probe.Active),"function","GUID experiment exposes active state")
for _,method in ipairs({"Start","Stop","Capture","Attempt","PostAttempt","Record"}) do
    eq(type(Log[method]),"function","GUID experiment log exposes "..method)
end
local converter=UnitTokenFromGUID
local resolved=Probe.Resolve({guid="Creature-A"})
eq(resolved.converted,"nameplate1","converted path uses the public conversion API token")
eq(resolved.readableMap,true,"conversion is accepted only after public GUID roundtrip")
UnitTokenFromGUID=function() return "nameplate2" end
resolved=Probe.Resolve({guid="Creature-A"})
eq(resolved.converted,nil,"mismatched API roundtrip cannot become a converted target")
yes(resolved.liveToken,"independent hand scan can remain diagnostic evidence")
UnitTokenFromGUID=nil
resolved=Probe.Resolve({guid="Creature-A"})
eq(resolved.converted,nil,"missing conversion API never adopts the scanned diagnostic token")
eq(resolved.mapReason,"unavailable","missing conversion capability is explicit")
UnitTokenFromGUID=function() return secret end
eq(Probe.Resolve({guid="Creature-A"}).converted,nil,"secret conversion token never enters secure attributes")
UnitTokenFromGUID=function() error("conversion unavailable") end
eq(Probe.Resolve({guid="Creature-A"}).converted,nil,"conversion API failure never enables a token")
eq(Probe.Resolve({guid=secret}),nil,"secret captured identity is rejected before comparison")
UnitTokenFromGUID=converter
eq(Probe.Capture("A"),false,"closed experiment cannot capture a target")
eq(Probe.Command("open"),true,"experiment opens out of combat")
eq(Probe.Active(),true,"open experiment reports active isolation")
eq(suspended,true,"open experiment suspends ordinary name bridges")
eq(Probe.prepared.A.enabled,false,"an unrecorded pair never enables an action")
eq(Probe.Capture("B"),false,"B cannot precede A")
eq(Probe.Capture("A"),true,"public hostile NPC target can be captured as A")
eq(Probe.Capture("B"),false,"same GUID cannot masquerade as a second same-name NPC")
units.target=nil
eq(Probe.Capture("B"),false,"no live target does not fabricate a capture")
units.target=units.player
eq(Probe.Capture("B"),false,"friendly player cannot become an NPC pair member")
units.target=units.nameplate2
local unitGUIDAPI=UnitGUID
UnitGUID=nil
eq(Probe.Capture("B"),false,"missing target GUID API cannot create a pair member")
UnitGUID=unitGUIDAPI
units.nameplate2.dead=true
eq(Probe.Capture("B"),false,"dead NPC target is not accepted as a live test pair member")
units.nameplate2.dead=false
units.nameplate2.guid=secret
eq(pcall(Probe.Capture,"B"),true,"secret target identity is rejected without comparison or formatting")
eq(Probe.captures.B,nil,"secret target identity is never saved as B")
units.nameplate2.guid="Creature-B"
eq(Probe.Capture("B"),true,"same-name distinct public GUID completes the pair")
eq(Probe.captures.A.name,Probe.captures.B.name,"pair names intentionally remain indistinguishable")
eq(Probe.captures.A.guid~=Probe.captures.B.guid,true,"pair identity remains different by GUID")
eq(Probe.prepared.A.unitArg,"nameplate1","converted A uses only the verified API token")
eq(Probe.blocks.A:GetAttribute("unit"),nil,"visual probe block cannot create a native mouseover unit")
UnitTokenFromGUID=nil
Probe.SetMode("converted")
eq(Probe.prepared.A.enabled,false,"missing converter disables the converted route despite diagnostic scan")
eq(Probe.SetMode("guid_button"),true,"raw GUID button remains independently selectable")
eq(Probe.prepared.A.unitArg,"Creature-A","raw GUID button passes the captured GUID verbatim")
eq(Probe.proxies.A:GetAttribute("probe-type"),"spell","raw GUID button uses an explicit spell action")
eq(Probe.SetMode("guid_macro"),true,"pure raw GUID macro remains independently selectable")
eq(Probe.proxies.A:GetAttribute("probe-macro"),"/cast [@Creature-A] 测试攻击","raw macro contains only the explicit GUID cast condition")
eq(Probe.proxies.A:GetAttribute("probe-macro"):find("targetexact",1,true),nil,"raw GUID macro has no name targeting fallback")
eq(Probe.proxies.A:GetAttribute("probe-macro"):find(Probe.captures.A.name,1,true),nil,"raw GUID macro does not contain the shared NPC name")
eq(Probe.SetMode("integrated_macro"),true,"integrated GUID command is independently selectable")
eq(Probe.prepared.A.enabled,true,"a readable live sample can prepare the integrated GUID command")
eq(Probe.proxies.A:GetAttribute("probe-macro"),"/stopattack\n/cleartarget\n/stopmacro [@target,exists][@mouseover,harm]\n/cast [@Creature-A] 测试攻击","integrated command stops attacks, clears target, checks residual fallback, then casts the exact GUID")
local integratedMacro=Probe.proxies.A:GetAttribute("probe-macro")
yes(integratedMacro:find("/cleartarget\n/stopmacro [@target,exists][@mouseover,harm]\n/cast",1,true),"residual target and harmful mouseover stop checks run after clearing and before cast")
eq(Probe.proxies.A:GetAttribute("unit"),nil,"integrated command has no implicit secure button unit")
eq(Probe.proxies.A:GetAttribute("probe-macro"):find("targetexact",1,true),nil,"integrated command has no name-targeting fallback")
eq(Probe.proxies.A:GetAttribute("probe-macro"):find("targetlasttarget",1,true),nil,"integrated command never restores an old target")
eq(Probe.proxies.A:GetAttribute("probe-macro"):find(Probe.captures.A.name,1,true),nil,"integrated command never embeds the shared creature name")
yes(Probe.help:GetText():find("停止自动攻击、清空当前目标",1,true),"integrated help states its target side effects")
yes(Probe.help:GetText():find("不会恢复旧目标",1,true),"integrated help states that the old target is not restored")
local liveA=units.nameplate1
units.nameplate1=nil;units.target=units.nameplate2
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"integrated route cannot prepare a disappeared live sample")
eq(Probe.prepared.A.reason,"no_live_sample","missing sample is distinguished from a GUID parser result")
eq(Probe.proxies.A:GetAttribute("probe-macro"),nil,"missing sample cannot leave an executable integrated macro")
Probe.SetMode("guid_macro")
eq(Probe.prepared.A.enabled,true,"original pure GUID route remains independent of live sample availability")
units.nameplate1=liveA;liveA.dead=true
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"integrated route rejects a dead captured sample")
eq(Probe.prepared.A.reason,"no_live_sample","dead sample retains an explicit preparation reason")
liveA.dead=false
local existsAPI,deadAPI=UnitExists,UnitIsDeadOrGhost
UnitExists=function(unit) if unit=="nameplate1" then return secret end;return existsAPI(unit) end
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"secret sample existence cannot prepare an integrated command")
UnitExists=existsAPI
UnitIsDeadOrGhost=function(unit) if unit=="nameplate1" then return secret end;return deadAPI(unit) end
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"secret sample life state cannot prepare an integrated command")
UnitIsDeadOrGhost=deadAPI
UnitGUID=function(unit) if unit=="nameplate1" then return secret end;return unitGUIDAPI(unit) end
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"secret sample GUID cannot prepare an integrated command")
UnitGUID=unitGUIDAPI
local exactInfo=C_Spell.GetSpellInfo
C_Spell.GetSpellInfo=function() return {spellID=133} end
Probe.SetMode("integrated_macro")
eq(Probe.prepared.A.enabled,false,"integrated command requires the exact configured spell rank")
eq(Probe.prepared.A.reason,"exact_rank_unavailable","wrong spell rank has a separate preparation reason")
C_Spell.GetSpellInfo=exactInfo
Probe.SetMode("guid_macro")
local panelButtons={}
for _,f in ipairs(frames) do
    if f.kind=="Button" and f.parent==Probe.panel then panelButtons[#panelButtons+1]=f end
end
eq(#panelButtons,8,"GUID panel includes eight controls after adding the internal command")
for i,f in ipairs(panelButtons) do
    eq(f.point[4],14+(i-1)*86,"probe control "..i.." stays in its assigned single-row column")
    eq(f.point[5],-40,"probe control "..i.." remains on one row")
    yes(f.point[4]+f.width<=Probe.panel.width,"probe control "..i.." fits inside the unchanged panel")
end
UnitTokenFromGUID=converter
for name,snippet in pairs(Probe.Snippets) do yes(loadstring(snippet),"GUID restricted "..name.." snippet has Lua syntax") end
-- Evaluate only branch selection with inert tables and a fixed condition stub.
-- This is not restricted-environment or native unit/spell engine execution.
local preflight=assert(loadstring("return function(self,control,SecureCmdOptionParse)\n"..Probe.Snippets.preClick.."\nend"))()
local function branch(mode,targetHarm,mouseoverHarm,enabled)
    local proxy={attrs={["probe-enabled"]=enabled~=false,["probe-mode"]=mode,["probe-type"]=(mode=="guid_macro" or mode=="integrated_macro") and "macro" or "spell",
        ["probe-unit"]="Creature-A",["probe-macro"]="/cast [@Creature-A] 测试攻击",["probe-armed"]=true}}
    function proxy:GetAttribute(key) return self.attrs[key] end
    function proxy:SetAttribute(key,value) self.attrs[key]=value end
    local control={attrs={["probe-active"]=true},ClearBindings=function() end,SetBindingClick=function() end}
    function control:GetAttribute(key) return self.attrs[key] end
    function control:SetAttribute(key,value) self.attrs[key]=value end
    preflight(proxy,control,function(condition)
        if condition=="[@target,harm] blocked" and targetHarm then return "blocked" end
        if condition=="[@mouseover,harm] blocked" and mouseoverHarm then return "blocked" end
    end)
    return proxy.attrs,proxy,control
end
for _,mode in ipairs({"converted","guid_button","guid_macro"}) do
    local unsafeTarget=branch(mode,true,false)
    eq(unsafeTarget.type,nil,mode.." cannot execute with harmful current target fallback")
    eq(unsafeTarget["probe-execute"],false,mode.." blocked target is explicitly non-executed")
    local unsafeHover=branch(mode,false,true)
    eq(unsafeHover.type,nil,mode.." cannot execute with harmful native mouseover fallback")
end
eq(branch("baseline",true,true).type,"spell","explicit current-target baseline is the intentional safety exception")
local integratedTarget=branch("integrated_macro",true,false)
eq(integratedTarget.type,"macro","integrated command may dispatch with a hostile current target that its macro clears")
eq(integratedTarget.unit,nil,"integrated secure dispatch retains an empty implicit unit")
local integratedHover=branch("integrated_macro",false,true)
eq(integratedHover.type,nil,"integrated command still rejects a hostile native mouseover")
eq(integratedHover["probe-branch"],"blocked_hostile_mouseover","integrated hostile mouseover has a dedicated visible reason")
eq(branch("integrated_macro",true,true).type,nil,"clearing current target cannot authorize hostile mouseover fallback")
eq(branch("integrated_macro",false,false,false).type,nil,"disabled integrated sample never clears or casts")
local integratedOnce,integratedProxy,integratedControl=branch("integrated_macro",true,false)
preflight(integratedProxy,integratedControl,function() end)
eq(integratedOnce.type,nil,"integrated command also consumes exactly one action per hover")
eq(integratedOnce["probe-branch"],"consumed_noop","integrated repeat does not run another clear-target action")
eq(branch("guid_button",false,false,false).type,nil,"disabled probe still consumes its key without executing a spell")
local rawMacro=branch("guid_macro",false,false)
eq(rawMacro.type,"macro","raw GUID macro uses the isolated macro action")
eq(rawMacro.unit,nil,"raw GUID macro does not inherit an implicit secure button unit")
local once,oneProxy,oneControl=branch("guid_button",false,false)
eq(once.type,"spell","one fresh secure hover arms a single executable attempt")
preflight(oneProxy,oneControl,function() end)
eq(once.type,nil,"second key press during the same hover is a non-executing action")
eq(once["probe-execute"],false,"consumed hover explicitly reports no execution")
eq(once["probe-branch"],"consumed_noop","consumed attempt is distinguished from a real cast attempt")
local enter=assert(loadstring("return function(self,control)\n"..Probe.Snippets.enter.."\nend"))()
enter({GetFrameRef=function() return oneProxy end,GetAttribute=function(_,key) return key=="probe-slot" and "A" or "TestProxy" end},oneControl)
preflight(oneProxy,oneControl,function() end)
eq(once.type,"spell","another secure mouse enter re-arms one attempt")
local proxy=Probe.proxies.A
Probe.SetMode("converted")
proxy.attrs["probe-armed"]=false
emit("PLAYER_TARGET_CHANGED")
eq(proxy:GetAttribute("probe-armed"),false,"automatic converted mapping refresh cannot re-arm a consumed hover")
emit("PLAYER_REGEN_ENABLED")
eq(proxy:GetAttribute("probe-armed"),false,"automatic leaving-combat refresh preserves the one-shot latch")
Probe.SetMode("guid_macro")
-- Ordinary observers display the actual secure branch without treating an
-- input, action dispatch or blocked key as a successful cast.
local function observeInput(slot,branchName,execute)
    local action=Probe.proxies[slot]
    action.attrs["probe-branch"],action.attrs["probe-execute"]=branchName,execute
    action:GetScript("PreClick")(action,"LeftButton",true)
    action:GetScript("PostClick")(action,"LeftButton",true)
end
Probe.SetMode("integrated_macro")
observeInput("A","blocked_hostile_mouseover",false)
yes(Probe.blocks.A.label:GetText():find("未执行：请先移入中央 A/B 测试块",1,true),"integrated native mouseover block has a distinct corrective message")
eq(Probe.feedback.A.executed,0,"native mouseover block never increments integrated actions")
eq(Probe.GetAttempt().clearsCurrentTarget,true,"integrated observer declares the target-clearing contract")
eq(Probe.GetAttempt().liveExists,true,"observer reports public live-sample existence")
eq(Probe.GetAttempt().liveDead,false,"observer preserves public false life-state readback")
eq(Probe.GetAttempt().liveGUID,"Creature-A","observer reports the sample's current GUID")
eq(Probe.GetAttempt().targetExistsAfter,true,"PreClick snapshot retains target existence before the macro executes")
Probe.SetMode("guid_macro")
observeInput("A","blocked_hostile_fallback",false)
eq(Probe.feedback.A.inputs,1,"blocked hardware input increments the current-mode input count")
eq(Probe.feedback.A.executed,0,"hostile-fallback protection cannot increment dispatched actions")
yes(Probe.blocks.A.label:GetText():find("未执行：先选自己头像或清空敌方目标",1,true),"blocked input visibly explains the target prerequisite")
yes(Probe.blocks.A.label:GetText():find("按键 1 · 已发起动作 0",1,true),"blocked input visibly distinguishes key count from dispatched actions")
eq(Probe.blocks.A.label:GetText():find("成功",1,true),nil,"blocked feedback does not claim cast success")
Probe.Prepare(false)
eq(Probe.feedback.A.inputs,1,"automatic mapping refresh preserves current-mode input feedback")
observeInput("A","execute",true)
eq(Probe.feedback.A.inputs,2,"a later action retains the current-mode input total")
eq(Probe.feedback.A.executed,1,"only an explicitly executed secure branch increments action count")
yes(Probe.blocks.A.label:GetText():find("已发起动作；施法与受术结果见下方",1,true),"action dispatch is distinguished from recipient evidence")
eq(Probe.blocks.A.label:GetText():find("成功",1,true),nil,"dispatch feedback cannot claim cast or damage success")
observeInput("A","consumed_noop",false)
eq(Probe.feedback.A.executed,1,"consumed repeated key leaves action count unchanged")
yes(Probe.blocks.A.label:GetText():find("本次已用过，移出再进入",1,true),"consumed input explains how to rearm")
local staleFeedback=Probe.feedback.A
Probe.SetMode("guid_button")
eq(Probe.feedback.A,nil,"changing mode resets per-mode counts")
eq(Probe.GetAttempt(),nil,"changing mode clears prior input feedback")
Probe.feedback.A=staleFeedback
Probe.UpdateLabels()
yes(Probe.blocks.A.label:GetText():find("按键 0 · 已发起动作 0",1,true),"another mode cannot display stale input counts")
eq(Probe.blocks.A.label:GetText():find("本次已用过",1,true),nil,"another mode cannot display the previous branch result")
Probe.SetMode("guid_macro")
observeInput("A","blocked_hostile_fallback",false)
staleFeedback=Probe.feedback.A
units.target=units.nameplate1
units.nameplate1.guid="Creature-A-new"
Probe.Capture("A")
eq(Probe.feedback.A,nil,"recapturing same-name different identity resets input counts")
eq(Probe.proxies.A.lastAttempt,nil,"recapture clears proxy input correlation history")
Probe.feedback.A=staleFeedback
Probe.UpdateLabels()
yes(Probe.blocks.A.label:GetText():find("按键 0 · 已发起动作 0",1,true),"a new same-name GUID cannot inherit old counts")
eq(Probe.blocks.A.label:GetText():find("先选自己头像",1,true),nil,"a new same-name GUID cannot inherit the old last result")
units.nameplate1.guid="Creature-A";Probe.Capture("A")
observeInput("A","blocked_hostile_fallback",false)
Probe.feedback.A.slot="B"
Probe.UpdateLabels()
yes(Probe.blocks.A.label:GetText():find("按键 0 · 已发起动作 0",1,true),"feedback stored under the wrong slot is rejected")
eq(Probe.blocks.A.label:GetText():find("先选自己头像",1,true),nil,"wrong-slot last input is not shown")
UnitTokenFromGUID=nil;Probe.SetMode("converted")
observeInput("A","disabled",false)
yes(Probe.blocks.A.label:GetText():find("未执行：转换接口不可用",1,true),"disabled route explains its public capability limitation")
eq(Probe.feedback.A.executed,0,"disabled route never increments dispatched actions")
observeInput("A","stopped",false)
yes(Probe.blocks.A.label:GetText():find("未执行：测试已停止",1,true),"stopped input is visibly separate from a cast attempt")
UnitTokenFromGUID=converter;Probe.SetMode("guid_macro")
local lineCount=1
observeInput("A","blocked_hostile_fallback",false)
for _ in Probe.blocks.A.label:GetText():gmatch("\n") do lineCount=lineCount+1 end
yes(lineCount<=6,"per-block feedback stays within six explicit text lines")
Probe.SetMode("guid_macro")
proxy.attrs["probe-execute"],proxy.attrs["probe-branch"]=true,"execute"
units.target=nil
combat=true
eq(Probe.Prepare(),false,"combat cannot prepare or rewrite protected probe attributes")
eq(Probe.SetMode("baseline"),false,"combat cannot switch the prebuilt experiment route")
eq(Probe.SetMode("integrated_macro"),false,"combat cannot prepare a new integrated clearing action")
eq(pcall(proxy:GetScript("PreClick"),proxy,"LeftButton",true),true,"combat PreClick observer is read-only")
eq(Probe.GetAttempt().configuredKey,"Z","observer labels Z as configured key")
eq(Probe.GetAttempt().actualKey,nil,"observer never invents a physical keyboard key")
eq(Probe.GetAttempt().button,"LeftButton","native dispatch button remains distinct from keyboard key")
eq(pcall(proxy:GetScript("PostClick"),proxy,"LeftButton",true),true,"combat PostClick observer performs no protected writes")
eq(Probe.Stop(),false,"ordinary combat stop defers protected cleanup")
eq(Probe.Active(),true,"deferred stop retains isolation until protected cleanup can finish")
combat=false
overrides.Z="CLICK stale-probe:LeftButton";overrides.owner=Probe.owner
emit("PLAYER_REGEN_ENABLED")
eq(Probe.Active(),false,"leaving combat completes deferred stop")
eq(suspended,false,"completed stop restores ordinary frame bridges")
eq(GetBindingAction("Z",true),baseBinding,"completed stop restores the original temporary Z binding")
C_CombatLog={IsCombatLogRestricted=function() return false end}
eq(Probe.Command("open"),true,"stopped experiment can open a fresh isolated session")
eq(Probe.captures.A,nil,"fresh session cannot reuse an old A capture")
eq(Probe.captures.B,nil,"fresh session cannot reuse an old B capture")
eq(Probe.prepared.A.enabled,false,"fresh session without a new pair cannot prepare an action")
eq(Probe.prepared.A.reason,"no_pair","fresh session explicitly requires a new pair")
eq(Probe.GetAttempt(),nil,"fresh session clears the prior observed attempt")
eq(Probe.proxies.A.lastAttempt,nil,"fresh session clears proxy correlation history")
eq(Probe.mode,"converted","fresh session restores the initial test mode")
eq(Probe.feedback.A,nil,"fresh session clears per-mode input counts")
observeInput("A","disabled",false)
yes(Probe.blocks.A.label:GetText():find("未执行：先记两只同名怪 A/B",1,true),"no-pair key explains that both captures are required")
yes(Probe.blocks.A.label:GetText():find("按键 1 · 已发起动作 0",1,true),"no-pair input stays visible without claiming an action")
units.target=units.nameplate1;Probe.Capture("A")
units.target=units.nameplate2;Probe.Capture("B")
-- Recipient evidence requires the public destination GUID of the player's
-- spell 679. Names, cast notifications and health changes cannot prove it.
local activeProbeFocus="A"
GetMouseFoci=function() return activeProbeFocus and {Probe.blocks[activeProbeFocus]} or {} end
local function lastRecord(kind)
    for i=#MyForeverTargetsLogDB.events,1,-1 do
        local record=MyForeverTargetsLogDB.events[i]
        if record.kind==kind then return record end
    end
end
local function attempt(slot,execute)
    clock=clock+6 -- Independent cases do not overlap delayed-effect windows.
    activeProbeFocus=slot
    return Log.Attempt({slot=slot,expectedGUID=slot=="A" and "Creature-A" or "Creature-B",
        mode="guid_button",spellID=679,execute=execute~=false,configuredKey="Z"})
end
C_CombatLog={IsCombatLogRestricted=function() return false end}
eq(Log.Start(),true,"isolated evidence logger starts with bounded diagnostics")
eq(lastRecord("GUID_PROBE_COMBAT_LOG_CAPABILITY").fields.restricted,false,"public false restriction capability is preserved")
eq(Log.Capture("A",{guid=secret,name="测试同名怪物"}),false,"restricted identity cannot enter captured log pair")
Log.Capture("A",{guid="Creature-A",name="测试同名怪物"})
Log.Capture("B",{guid="Creature-B",name="测试同名怪物"})
yes(type(attempt("A"))=="number","executable attempt has a public correlation identifier")
emit("UNIT_SPELLCAST_SENT","player","测试同名怪物","cast-1",679)
emit("UNIT_SPELLCAST_SUCCEEDED","player","cast-1",679)
eq(Log.Status("A").receiver,"unproven","SENT name and SUCCEEDED never prove one same-name recipient")
eq(Log.Status("A").effect,"none","cast notifications alone never invent damage")
eq(lastRecord("GUID_PROBE_CAST").fields.recipientProven,false,"cast log explicitly labels recipient unproven")
local castSequence=lastRecord("GUID_PROBE_CAST").sequence
emit("UNIT_SPELLCAST_SUCCEEDED","party1","other-cast",679)
eq(lastRecord("GUID_PROBE_CAST").sequence,castSequence,"nonplayer cast notifications are filtered")
cleu("SPELL_DAMAGE","Player-other","Creature-A",679)
cleu("SPELL_HEAL","Player-test","Creature-A",679)
cleu("SWING_DAMAGE","Player-test","Creature-A",679)
cleu("SPELL_DAMAGE","Player-test","Creature-A",133)
eq(Log.Status("A").receiver,"unproven","other caster, healing, melee and different spell cannot be attributed to probe 679")
emit("UNIT_HEALTH","nameplate1")
emit("UNIT_COMBAT","nameplate1","WOUND","",12,7)
eq(Log.Status("A").receiver,"unproven","health and unit combat changes lack spell/caster recipient proof")
eq(lastRecord("GUID_PROBE_HEALTH_UPDATE").fields.recipientProven,false,"health observation is explicitly unproven")
eq(lastRecord("GUID_PROBE_UNIT_COMBAT").fields.school,7,"UNIT_COMBAT retains its fifth payload field without claiming attribution")
cleu("SPELL_CAST_SUCCESS","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"expected","public spell-success destination GUID identifies the captured NPC")
eq(Log.Status("A").effect,"cast","combat-log cast recipient does not claim damage")
eq(lastRecord("GUID_PROBE_EFFECT").fields.damageEventProven,false,"combat cast success is separate from damage evidence")
local originalUpdateLabels,labelUpdates=Probe.UpdateLabels,0
Probe.UpdateLabels=function(...) labelUpdates=labelUpdates+1;return originalUpdateLabels(...) end
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(labelUpdates,1,"one delayed public effect automatically refreshes the visible labels once")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,true,"label refresh does not alter the public recipient evidence")
yes(Probe.blocks.A.label:GetText():find("匹配 A",1,true),"delayed effect is reflected on the matching visible probe label")
Probe.UpdateLabels=originalUpdateLabels
Probe.SetMode("guid_button")
eq(Probe.blocks.A.label:GetText():find("匹配 A",1,true),nil,"switching mode hides the previous route's recipient result")
eq(Log.Status("A").receiver,"expected","hiding an old-route label does not alter public recipient evidence")
eq(Log.Status("A").effect,"damage","public player spell 679 damage upgrades effect evidence")
eq(Log.Status("A").observedGUID,"Creature-A","damage evidence retains exact public destination GUID")
eq(lastRecord("GUID_PROBE_EFFECT").fields.amount,12,"CLEU amount is read from the spell damage payload position")
eq(lastRecord("GUID_PROBE_EFFECT").fields.healthLossProven,true,"public positive damage amount can establish health loss")
currentCLEU[15]=0;emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(lastRecord("GUID_PROBE_EFFECT").fields.healthLossProven,false,"zero damage event never claims health loss")
currentCLEU[15]=secret;emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(lastRecord("GUID_PROBE_EFFECT").fields.amount,"[restricted]","secret damage amount is redacted")
eq(lastRecord("GUID_PROBE_EFFECT").fields.healthLossProven,false,"secret amount cannot establish health loss")
attempt("A");cleu("SPELL_MISSED","Player-test","Creature-B",679)
eq(Log.Status("A").receiver,"other","same-name different destination GUID is classified as another NPC")
eq(Log.Status("A").effect,"miss","miss event identifies recipient without claiming damage")
eq(Log.Status("A").expectedGUID,"Creature-A","requested GUID remains distinct from observed GUID")
attempt("A")
eq(pcall(cleu,"SPELL_DAMAGE","Player-test",secret,679),true,"restricted destination is never compared or formatted")
eq(Log.Status("A").receiver,"unproven","secret destination cannot prove a recipient")
eq(lastRecord("GUID_PROBE_EFFECT_UNREADABLE").fields.destinationGUID,"[restricted]","secret destination is redacted before persistence")
attempt("A");cleu("SPELL_DAMAGE",secret,"Creature-A",679)
eq(Log.Status("A").receiver,"unproven","secret caster cannot attribute a player's probe")
attempt("A",false);cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","blocked attempt cannot claim a coincident effect")
attempt("A");clock=clock+6
Log.frame:GetScript("OnUpdate")(Log.frame,.1)
eq(Log.Status("A").reason,"no_public_effect","empty completed window leaves the waiting state")
eq(Log.Status("A").receiver,"unproven","empty completed window never claims a recipient")
eq(Log.Status("A").effect,"none","empty completed window is neither damage nor a claimed miss")
eq(lastRecord("GUID_PROBE_WINDOW_ENDED").fields.recipientProven,false,"window end explicitly retains unproven attribution")
yes(Probe.blocks.A.label:GetText():find("未取得公开受术记录",1,true),"empty completed window updates the visible explanation")
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","expired association window cannot claim delayed damage")
local oldAttempt=attempt("A")
clock=clock+1
activeProbeFocus="B"
local overlapping=Log.Attempt({slot="B",expectedGUID="Creature-B",mode="guid_button",execute=true})
eq(Log.Status("A").reason,"ambiguous_attempt_window","rapid A/B attempt invalidates the preceding association")
eq(Log.Status("B").reason,"ambiguous_attempt_window","rapid A/B attempt also invalidates the new association")
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("B").receiver,"unproven","overlapping delayed damage never promotes the latest attempt to expected")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,false,"ambiguous effect remains observable without exact attribution")
eq(lastRecord("GUID_PROBE_EFFECT").fields.observedGUID,"Creature-A","ambiguous effect retains public destination evidence")
local executable=attempt("A")
clock=clock+1
local blocked=Log.Attempt({slot="A",expectedGUID="Creature-A",mode="guid_button",execute=false})
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(lastRecord("GUID_PROBE_EFFECT").fields.attemptID,executable,"blocked repeated key does not steal prior executable attempt's delayed effect")
eq(lastRecord("GUID_PROBE_EFFECT").fields.attemptID==blocked,false,"no-op attempt ID never gains a damage attribution")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,true,"a blocked no-op does not make the independent prior attempt ambiguous")
attempt("A")
activeProbeFocus=nil;units.target=units.nameplate1
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","leaving probe focus then using native spell cannot prove the old probe attempt")
eq(Log.Status("A").reason,"probe_focus_not_confirmed","native attack after leaving the probe keeps its explicit attribution limit")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,false,"out-of-probe damage is observed without recipient proof for the probe")
eq(lastRecord("GUID_PROBE_EFFECT").fields.observedGUID,"Creature-A","out-of-probe event retains its actual public destination")
clock=clock+6
activeProbeFocus="A"
Log.Attempt({slot="A",expectedGUID="Creature-A",unitArgGUID="Creature-B",mode="converted",execute=true})
eq(lastRecord("GUID_PROBE_PRECLICK").fields.validConfiguration,false,"converted stale GUID mapping is not a valid route")
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","stale converted mapping never proves success of that route")
eq(Log.Status("A").reason,"stale_or_unreadable_mapping","stale route keeps its explicit evidence limitation")
-- The integrated route requires a matching PostClick clear confirmation in
-- addition to live identity, source/spell/destination and focus evidence.
Probe.SetMode("integrated_macro")
local function integratedAttempt(change)
    clock=clock+6
    activeProbeFocus="A"
    local fields={slot="A",expectedGUID="Creature-A",mode="integrated_macro",spellID=679,execute=true,
        liveExists=true,liveDead=false,liveGUID="Creature-A",clearsCurrentTarget=true,targetGUID="Creature-B"}
    if type(change)=="function" then change(fields) end
    return Log.Attempt(fields)
end
local function integratedPost(id,existsAfter,change)
    local fields={attemptID=id,mode="integrated_macro",slot="A",expectedGUID="Creature-A",execute=true,targetExistsAfter=existsAfter}
    if type(change)=="function" then change(fields) end
    Log.PostAttempt(fields)
end
local integratedID=integratedAttempt()
eq(Log.Status("A").targetClearConfirmed,false,"integrated input alone does not confirm target clearing")
eq(Log.Status("A").reason,"awaiting_clear_confirmation","integrated attempt waits for its own PostClick readback")
yes(Probe.blocks.A.label:GetText():find("等待清空目标确认",1,true),"integrated pending-clear status is visible")
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","effect before PostClick cannot establish integrated recipient proof")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,false,"pre-confirmation public effect remains observation only")
integratedPost(integratedID,false)
eq(Log.Status("A").targetClearConfirmed,true,"matching PostClick public false existence confirms target clearing")
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").fields.beforeTargetGUID,"Creature-B","clear evidence keeps the prior unrelated target identity")
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").fields.recipientProven,false,"target-clear record never itself claims recipient proof")
eq(Log.Status("A").receiver,"unproven","clear confirmation cannot retroactively promote an earlier effect")
cleu("SPELL_CAST_SUCCESS","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"expected","later public cast recipient can be attributed after its own clear confirmation")
eq(Log.Status("A").effect,"cast","later cast proof cannot upgrade an earlier unproven damage event")
eq(lastRecord("GUID_PROBE_EFFECT").fields.damageEventProven,false,"post-confirmation cast event alone does not prove damage")
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"expected","a later fully attributed effect may prove the integrated recipient")
eq(lastRecord("GUID_PROBE_EFFECT").fields.targetClearConfirmed,true,"proven integrated effect carries target-clear confirmation")
for _,case in ipairs({{value=true,label="still-selected"},{label="missing"},{value=secret,label="restricted"}}) do
    local id=integratedAttempt()
    integratedPost(id,case.value)
    eq(Log.Status("A").targetClearConfirmed,false,case.label.." target existence cannot confirm a clear")
    eq(Log.Status("A").targetClearReason,"target_clear_unconfirmed",case.label.." clear keeps an explicit attribution limit")
    cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
    eq(Log.Status("A").receiver,"unproven",case.label.." clear cannot prove a recipient from coincident damage")
end
yes(Probe.blocks.A.label:GetText():find("清空目标未确认，个体未证实",1,true),"failed clear confirmation is visible without claiming success")
local matchingID=integratedAttempt()
local priorClear=lastRecord("GUID_PROBE_TARGET_CLEAR").sequence
integratedPost(matchingID+1,false)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"wrong attempt ID cannot establish another action's clear")
integratedPost(matchingID,false,function(f) f.mode="guid_macro" end)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"another mode cannot establish an integrated clear")
integratedPost(matchingID,false,function(f) f.slot="B" end)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"another probe block cannot establish the action's clear")
integratedPost(matchingID,false,function(f) f.expectedGUID="Creature-B" end)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"another expected individual cannot establish the action's clear")
integratedPost(matchingID,false,function(f) f.execute=false end)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"a blocked PostClick cannot establish an executed clear")
eq(Log.Status("A").targetClearConfirmed,false,"mismatched PostClick inputs leave the real action unconfirmed")
integratedPost(matchingID,false)
eq(Log.Status("A").targetClearConfirmed,true,"the later matching first PostClick can confirm the action")
local firstOnly=integratedAttempt()
integratedPost(firstOnly,true)
priorClear=lastRecord("GUID_PROBE_TARGET_CLEAR").sequence
integratedPost(firstOnly,false)
eq(Log.Status("A").targetClearConfirmed,false,"a duplicate PostClick cannot repair a first unconfirmed clear")
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"duplicate PostClick never produces a second clear verdict")
local expiredIntegrated=integratedAttempt()
clock=clock+6
Log.frame:GetScript("OnUpdate")(Log.frame,.1)
eq(Log.Status("A").targetClearConfirmed,false,"an expired attempt without PostClick stays unconfirmed")
eq(Log.Status("A").targetClearReason,"target_clear_unconfirmed","missing PostClick expires with an explicit clear limitation")
eq(lastRecord("GUID_PROBE_WINDOW_ENDED").fields.reason,"target_clear_unconfirmed","expired window records missing clear confirmation")
priorClear=lastRecord("GUID_PROBE_TARGET_CLEAR").sequence
integratedPost(expiredIntegrated,false)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"a late PostClick cannot establish clear confirmation after window closure")
eq(Log.Status("A").targetClearConfirmed,false,"late PostClick cannot revive expired integrated attribution")
local expiredError=integratedAttempt()
emit("UI_ERROR_MESSAGE",402,"距离太远。")
clock=clock+6
Log.frame:GetScript("OnUpdate")(Log.frame,.1)
eq(Log.Status("A").reason,"game_error","missing clear timeout preserves the earlier game error")
eq(Log.Status("A").targetClearReason,"target_clear_unconfirmed","timeout exposes the clear limitation alongside the game error")
for _,case in ipairs({{field="liveExists",value=false,label="absent sample"},
    {field="liveExists",value=secret,label="secret existence"},{field="liveDead",value=true,label="dead sample"},
    {field="liveDead",value=secret,label="secret life state"},{field="liveGUID",value="Creature-B",label="reused sample"},
    {field="liveGUID",value=secret,label="secret identity"},{field="clearsCurrentTarget",value=false,label="no clearing contract"}}) do
    local id=integratedAttempt(function(f) f[case.field]=case.value end)
    integratedPost(id,false)
    eq(Log.Status("A").targetClearConfirmed,true,case.label.." may confirm only target clearing")
    cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
    eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,false,case.label.." cannot prove integrated recipient despite clearing")
end
local earlyCast=integratedAttempt()
emit("UNIT_SPELLCAST_SUCCEEDED","player","early-integrated-cast",679)
eq(Log.Status("A").reason,"cast_event_only","early cast event remains separate from recipient evidence")
integratedPost(earlyCast,true)
eq(Log.Status("A").reason,"cast_event_only","PostClick does not erase an earlier cast observation")
yes(Probe.blocks.A.label:GetText():find("清空目标未确认，个体未证实",1,true),"clear limitation stays visible alongside an early cast observation")
local earlyError=integratedAttempt()
emit("UI_ERROR_MESSAGE",402,"距离太远。")
eq(Log.Status("A").reason,"game_error","early game error is retained for integrated diagnosis")
integratedPost(earlyError,false)
eq(Log.Status("A").reason,"game_error","successful clear confirmation does not erase an earlier game error")
eq(Log.Status("A").receiver,"unproven","game error plus confirmed clear still cannot prove a recipient")
local activeIntegrated=integratedAttempt()
clock=clock+1
local blockedIntegrated=Log.Attempt({slot="A",expectedGUID="Creature-A",mode="integrated_macro",execute=false})
priorClear=lastRecord("GUID_PROBE_TARGET_CLEAR").sequence
integratedPost(blockedIntegrated,false,function(f) f.execute=false end)
eq(lastRecord("GUID_PROBE_TARGET_CLEAR").sequence,priorClear,"blocked extra input cannot confirm or steal the preceding action")
integratedPost(activeIntegrated,false)
cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(lastRecord("GUID_PROBE_EFFECT").fields.attemptID,activeIntegrated,"blocked input does not steal an integrated action's later effect")
eq(lastRecord("GUID_PROBE_EFFECT").fields.recipientProven,true,"independent preceding action retains its own clear and recipient proof")
local getter=CombatLogGetCurrentEventInfo
Log.Stop();CombatLogGetCurrentEventInfo=nil
Log.Start();Log.Capture("A",{guid="Creature-A",name="测试同名怪物"})
attempt("A");cleu("SPELL_DAMAGE","Player-test","Creature-A",679)
eq(Log.Status("A").receiver,"unproven","missing combat-log API never fabricates destination proof")
Log.Stop();CombatLogGetCurrentEventInfo=getter
Log.Start();Log.Capture("A",{guid="Creature-A",name="测试同名怪物"})
for i=1,NS.Diagnostics.MAX_EVENTS+5 do Log.Record("GUID_PROBE_LIMIT",{value=i,restricted=secret}) end
eq(#MyForeverTargetsLogDB.events,NS.Diagnostics.MAX_EVENTS,"historical GUID experiment shares the configured bounded local log")
local rawSecret=false
for _,record in ipairs(MyForeverTargetsLogDB.events) do
    for _,value in pairs(record.fields) do if rawequal(value,secret) then rawSecret=true end end
end
eq(rawSecret,false,"raw secret values never survive inside persisted GUID event fields")
NS.Diagnostics.frame.scripts.OnUpdate(NS.Diagnostics.frame,NS.Diagnostics.MAX_SECONDS+1)
local stoppedSequence=MyForeverTargetsLogDB.sequence
Log.Record("GUID_PROBE_AFTER_TIMEOUT",{})
eq(MyForeverTargetsLogDB.sequence,stoppedSequence,"configured diagnostics timeout also bounds historical GUID experiment persistence")
Log.Stop()
Probe.Stop()
print("Targets GUID-probe simulated checks: "..checks.."; native GUID resolution and spell actions were not executed")
