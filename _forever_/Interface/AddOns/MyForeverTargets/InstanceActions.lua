local _,NS=...
-- Explicit, non-persistent OOC experiment. Native nameplate actions are not
-- assumed to work merely because the client accepted their configuration.
local P={rows={},byRow=setmetatable({},{__mode="k"}),serial=0}
NS.InstanceActions=P
local NAME="MyForeverTargetsInstanceActions"
local STOP=[[
 self:SetAttribute("enabled",false)
 self:SetAttribute("hover",nil)
 self:ClearBindings()
 for i=1,self:GetAttribute("rows") or 0 do
  local row=self:GetFrameRef("row"..i)
  local palette=self:GetFrameRef("palette"..i)
  if row then row:Hide() end
  if palette then palette:Hide() end
 end
 local stop=self:GetFrameRef("stop")
 if stop then stop:Hide() end
]]
local ENTER=[[
 control:ClearBindings()
 local host=control:GetFrameRef("host"..self:GetAttribute("index"))
 if control:GetAttribute("enabled") and not control:GetAttribute("combat") and host and host:IsVisible() then
  for _,key in ipairs(newtable("nearby","names","fixed")) do
   local other=control:GetFrameRef(key)
   if other then
    other:ClearBindings()
    if key=="names" then other:SetAttribute("combat-hover-index",nil) end
    if key=="fixed" then other:SetAttribute("mfch-hover",nil) end
   end
  end
  control:SetAttribute("hover",self:GetAttribute("index"))
  for i=1,self:GetAttribute("keys") or 0 do
   control:SetBindingClick(true,self:GetAttribute("key"..i),self:GetAttribute("proxy"..i),"LeftButton")
  end
 end
]]
local LEAVE=[[
 if control:GetAttribute("hover")==self:GetAttribute("index") then
  control:ClearBindings();control:SetAttribute("hover",nil)
 end
]]
local SPELL=[[
 self:SetAttribute("type",nil)
 self:SetAttribute("guard-ok",false)
 local host=control:GetFrameRef("host"..self:GetAttribute("index"))
 if control:GetAttribute("enabled") and not control:GetAttribute("combat") and host and host:IsVisible()
  and control:GetAttribute("hover")==self:GetAttribute("index")
  and SecureCmdOptionParse(self:GetAttribute("guard"))=="ready" then
  self:SetAttribute("guard-ok",true)
  self:SetAttribute("type","spell")
 end
]]
P.Snippets={STOP=STOP,ENTER=ENTER,LEAVE=LEAVE,SPELL=SPELL}
local function idle() return NS.Read(InCombatLockdown)==false end
local function enabled() return P.owner and NS.Read(P.owner.GetAttribute,P.owner,"enabled")==true end
P.Enabled=enabled
local function scalar(v)
 if not NS.Public(v) then return "[restricted]" end
 if v==nil then return "[nil]" end
 if type(v)=="boolean" or type(v)=="string" or NS.Number(v) then return v end
 return "[unsupported]"
end
local function same(unit,other)
 local value=NS.Read(UnitIsUnit,unit,other)
 if type(value)=="boolean" then return value end
 return "[unknown]"
end
local function observe(state,kind,extra)
 local d=NS.Diagnostics
 if not d or type(d.Record)~="function" then return end
 local targetMatch,focusMatch="[unknown]","[unknown]"
 if state then targetMatch,focusMatch=same(state.unit,"target"),same(state.unit,"focus") end
 local f={version=NS.VERSION,unit=state and state.unit,rowIndex=state and state.index,
  experiment=true,combat=scalar(NS.Read(InCombatLockdown)),enabled=enabled()==true,
  targetExists=scalar(NS.Read(UnitExists,"target")),focusExists=scalar(NS.Read(UnitExists,"focus")),
  targetMatches=targetMatch,focusMatches=focusMatch,
  raidMarker=state and scalar(NS.Read(GetRaidTargetIndex,state.unit)) or "[unknown]",
  nativeResultsOnly=true,recipientProven=false}
 for k,v in pairs(extra or {}) do f[k]=scalar(v) end
 pcall(d.Record,"INSTANCE_ACTION_"..kind,f)
end
local function entry(state)
 if not enabled() or not idle() then return nil end
 local data=NS.Read(NS.ReadUnit,state.unit,"enemy")
 if type(data)=="table" and NS.Public(data.guid) and type(data.guid)=="string"
  and NS.Read(UnitGUID,state.unit)==data.guid then return {unit=state.unit,guid=data.guid} end
 local display=NS.EnemyDisplay
 return display and type(display.RestrictedEntry)=="function" and NS.Read(display.RestrictedEntry,state.unit) or nil
end
function P.VisualEntry(row)
 local state=P.byRow[row]
 if enabled() and state then return true,entry(state) end
 return false
end
local function valid(state)
 if not enabled() or not idle() then return false,"combat_or_stopped" end
 if NS.Read(SpellIsTargeting)~=false or NS.Read(CursorHasItem)~=false then return false,"cursor_active" end
 if NS.Read(state.row.IsVisible or state.row.IsShown,state.row)~=true then return false,"panel_hidden" end
 if NS.Read(UnitExists,state.unit)~=true or NS.Read(UnitCanAttack,"player",state.unit)~=true then
  return false,"unit_unavailable"
 end
 return entry(state)~=nil,"native_unit_unavailable"
end
local function actionType(button)
 if button=="RightButton" and NS.Read(IsControlKeyDown)==true then return "palette" end
 return button=="RightButton" and "focus" or button=="LeftButton" and "target" or "none"
end
local function installObservers()
 if P.observersInstalled then return end
 P.observersInstalled=true
 if type(hooksecurefunc)~="function" then return end
 for _,api in ipairs({"TargetUnit","FocusUnit","SetRaidTarget","CastSpellByName","CastSpellByID"}) do
  if type(_G[api])=="function" then
   local name=api
   pcall(hooksecurefunc,name,function(a,b)
    pcall(function()
     local execution=P.execution
     if not execution or not enabled() then return end
     local unit=(name=="CastSpellByName" or name=="CastSpellByID") and b or a
     local matches=NS.Public(unit) and type(unit)=="string" and unit==execution.state.unit
     observe(execution.state,"API",{attemptID=execution.attempt.id,api=name,
      explicitUnitMatches=matches,callOnly=true,effectProven=false})
    end)
   end)
  end
 end
end
local function configure(button,state,mode)
 button:SetAttribute("unit",state.unit)
 button:SetAttribute("*unit1",nil);button:SetAttribute("*unit2",nil)
 if mode=="main" then
  button:SetAttribute("*type1","target");button:SetAttribute("*type2","focus")
  button:SetAttribute("ctrl-type2","click");button:SetAttribute("ctrl-clickbutton2",state.opener)
 elseif mode=="marker" then button:SetAttribute("*type1","raidtarget")
 else button:SetAttribute("type","spell") end
end
local function noop(button,mode)
 if mode=="main" then
  button:SetAttribute("*type1",nil);button:SetAttribute("*type2",nil);button:SetAttribute("ctrl-type2",nil)
 elseif mode=="marker" then button:SetAttribute("*type1",nil)
 else button:SetAttribute("type",nil) end
end
local function hook(button,state,mode,marker,spell)
 button:HookScript("PreClick",function(self,mouse,down)
  P.serial=P.serial+1
  local ok,reason=valid(state)
  local action=mode=="main" and actionType(mouse) or mode
  if idle() then
   if ok then configure(self,state,mode) else noop(self,mode) end
  end
  local guard
  if mode=="spell" then
   guard=NS.Read(self.GetAttribute,self,"guard-ok")==true
   local kind,id=NS.Read(GetActionInfo,spell.slot)
   local unchanged=kind=="spell" and id==spell.spellID
   if not guard or not unchanged then
    ok=false;reason=not guard and "native_macro_condition_rejected" or "action_changed"
    if idle() then self:SetAttribute("type",nil) end
   end
  end
  self.nativeAttempt={id=P.serial,action=action,target=same(state.unit,"target"),focus=same(state.unit,"focus"),
   generation=P.generation,allowed=ok,reason=ok and "prepared" or reason}
  P.execution={state=state,attempt=self.nativeAttempt}
  local execution=P.execution
  if C_Timer and type(C_Timer.After)=="function" then
   C_Timer.After(0,function() if P.execution==execution then P.execution=nil end end)
  end
  observe(state,"PRE",{attemptID=P.serial,action=action,allowed=ok,reason=self.nativeAttempt.reason,
   button=mouse,down=down,marker=marker,spellID=spell and spell.spellID,guard=guard,
   resolvedUnit=NS.Read(SecureButton_GetModifiedUnit,self,mouse),
   publicGuard=mode=="spell" and NS.Read(SecureCmdOptionParse,self:GetAttribute("guard"))=="ready" or nil})
 end)
 button:HookScript("PostClick",function(self)
  local attempt=self.nativeAttempt
  if not attempt then return end
  local function report(kind)
   if attempt.generation~=P.generation then return end
   local target,focus=same(state.unit,"target"),same(state.unit,"focus")
   local markerMatches
   if marker then
    local actual=NS.Read(GetRaidTargetIndex,state.unit)
    markerMatches=NS.Number(actual) and actual==marker or "[unknown]"
    if NS.Number(actual) and actual~=marker then markerMatches=false end
   end
   observe(state,kind,{attemptID=attempt.id,action=attempt.action,allowed=attempt.allowed,
    reason=attempt.reason,targetChangedToGoal=attempt.target==false and target==true,
    focusChangedToGoal=attempt.focus==false and focus==true,marker=marker,
    markerMatches=markerMatches,
    spellID=spell and spell.spellID})
  end
  report("POST")
  P.execution=nil
  if C_Timer and type(C_Timer.After)=="function" then C_Timer.After(.15,function() report("READBACK") end) end
 end)
end
local function text(frame)
 local label=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 label:SetPoint("CENTER")
 return label
end
local function getOwner()
 if P.owner then return P.owner end
 local owner=CreateFrame("Frame",NAME.."Owner",UIParent,"SecureHandlerStateTemplate")
 owner:SetAttribute("enabled",false);owner:SetAttribute("rows",0)
 owner:SetAttribute("_onstate-combat","self:SetAttribute('combat',newstate=='combat'); if newstate=='combat' then "..STOP.." end")
 RegisterStateDriver(owner,"combat","[combat] combat; idle")
 P.owner=owner
 installObservers()
 local stop=CreateFrame("Button",NAME.."Stop",UIParent,"SecureHandlerClickTemplate")
 stop:SetSize(24,20);stop:SetFrameStrata("DIALOG")
 stop:SetAttribute("_onclick",[[local ctl=self:GetFrameRef("owner");ctl:RunAttribute("stop")]])
 stop:SetFrameRef("owner",owner);owner:SetAttribute("stop",STOP);owner:SetFrameRef("stop",stop)
 stop.label=text(stop,10);stop.label:SetText("停止");stop:Hide();P.stop=stop
 return owner
end
local function createState(row,index,unit)
 local state={row=row,index=index,unit=unit,proxies={}}
 local suffix=index.."_"..P.generation
 -- Generic secure actions preserve our explicit click semantics instead of
 -- SecureUnitButton_OnClick allowing a global click-cast binding to intercept.
 local overlay=CreateFrame("Button",NAME.."Row"..suffix,row,"SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate")
 overlay:SetAllPoints(row);overlay:SetFrameStrata("MEDIUM");overlay:SetFrameLevel(row:GetFrameLevel()+16)
 overlay:RegisterForClicks("AnyUp");overlay:SetAttribute("useOnKeyDown",false);overlay:Hide();state.overlay=overlay
 local palette=CreateFrame("Frame",NAME.."Palette"..suffix,UIParent,"SecureHandlerBaseTemplate,BackdropTemplate")
 palette:SetSize(240,30);palette:SetPoint("BOTTOMLEFT",row,"TOPLEFT",0,3);palette:SetFrameStrata("DIALOG")
 palette:Hide();state.palette=palette
 local opener=CreateFrame("Button",NAME.."Open"..suffix,UIParent,"SecureHandlerClickTemplate")
 opener:SetFrameRef("palette",palette);opener:SetAttribute("_onclick",[[local p=self:GetFrameRef("palette");if p:IsShown() then p:Hide() else p:Show() end]])
 state.opener=opener
 overlay:SetFrameRef("palette",palette)
 for marker=1,8 do
  local mark=CreateFrame("Button",NAME.."Mark"..suffix.."_"..marker,palette,"SecureActionButtonTemplate")
  mark:SetSize(28,28);mark:SetPoint("LEFT",palette,"LEFT",(marker-1)*30,0)
  mark:RegisterForClicks("AnyUp");mark:SetAttribute("useOnKeyDown",false)
  mark:SetAttribute("action","set");mark:SetAttribute("marker",marker)
  mark.label=text(mark,10);mark.label:SetText(tostring(marker))
  configure(mark,state,"marker");hook(mark,state,"marker",marker)
 end
 overlay:SetAttribute("index",index);overlay:SetAttribute("keys",0)
 SecureHandlerWrapScript(overlay,"OnEnter",P.owner,ENTER)
 SecureHandlerWrapScript(overlay,"OnLeave",P.owner,LEAVE)
 SecureHandlerWrapScript(overlay,"OnHide",P.owner,LEAVE..[[local p=self:GetFrameRef("palette");if p then p:Hide() end]])
 overlay:HookScript("OnEnter",function()
  if GameTooltip then
   GameTooltip:SetOwner(overlay,"ANCHOR_RIGHT");GameTooltip:SetText("副本原生操作试验")
   GameTooltip:AddLine("左键选中 · 右键焦点 · Ctrl+右键标记",.9,.8,.55,true)
   GameTooltip:AddLine("悬停按原普通攻击技能键；客户端拒绝时不回退其他目标。",.82,.85,.9,true)
   GameTooltip:AddLine("进入战斗自动停止。本试验尚未确认原生动作有效。",.82,.85,.9,true)
   GameTooltip:Show()
  end
  observe(state,"ENTER")
 end)
 overlay:HookScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
 hook(overlay,state,"main");configure(overlay,state,"main")
 P.owner:SetFrameRef("host"..index,row)
 return state
end
local function prepareSpells(state)
 local actions=NS.NearbyCast and NS.Read(NS.NearbyCast.DiscoverActions,"enemy",true) or {}
 if type(actions)~="table" then actions={} end
 local keys=0
 for ai,spell in ipairs(actions) do
  if ai>16 then break end
  if spell.actionKind=="spell" and NS.Number(spell.spellID) and NS.Number(spell.slot) then
   local name=NAME.."Spell"..state.index.."_"..ai.."_"..tostring(P.generation)
   local proxy=CreateFrame("Button",name,UIParent,"SecureActionButtonTemplate")
   proxy:RegisterForClicks("AnyDown","AnyUp");proxy:SetAttribute("useOnKeyDown",spell.useOnKeyDown==true)
   proxy:SetAttribute("unit",state.unit);proxy:SetAttribute("spell",spell.spell or spell.spellID)
   proxy:SetAttribute("type",nil);proxy:SetAttribute("index",state.index)
   proxy:SetAttribute("guard","[@"..state.unit..",exists,harm,nodead] ready")
   SecureHandlerWrapScript(proxy,"PreClick",P.owner,SPELL)
   hook(proxy,state,"spell",nil,spell)
   state.proxies[#state.proxies+1]=proxy
   for _,key in ipairs(spell.keys or {}) do
    if NS.Public(key) and type(key)=="string" and #key<=64 and keys<32 then
     keys=keys+1;state.overlay:SetAttribute("key"..keys,key);state.overlay:SetAttribute("proxy"..keys,name)
    end
   end
  end
 end
 state.overlay:SetAttribute("keys",keys)
 observe(state,"READY",{keys=keys,mode="native_unit_no_guid",combatSupported=false})
end
function P.Off()
 if not idle() then NS.Print("请点敌方面板左侧的“停止”按钮；进入战斗也会自动停止原生试验。");return false end
 if P.owner then
  ClearOverrideBindings(P.owner);P.owner:SetAttribute("enabled",false);P.owner:SetAttribute("hover",nil)
  for _,s in ipairs(P.rows) do s.overlay:Hide();s.palette:Hide() end
  P.stop:Hide()
 end
 P.byRow=setmetatable({},{__mode="k"});P.rows={};P.generation=(P.generation or 0)+1
 P.execution=nil
 if NS.RequestRefresh then NS.RequestRefresh() end
 return true
end
function P.On()
 if not idle() or NS.Read(SpellIsTargeting)~=false or NS.Read(CursorHasItem)~=false then
  NS.Print("请脱战，取消待施法或物品光标后再开启。");return false
 end
 local section=NS.UI and NS.UI.enemy
 if not section or NS.Read(section.frame.IsShown,section.frame)~=true then NS.Print("请先打开敌方面板。");return false end
 if (P.activations or 0)>=10 then NS.Print("本轮试验次数已到10次，请 /reload 后继续。");return false end
 for _,module in pairs({cycle=NS.FocusCycle,scale=NS.NativeScaleProbe,native=NS.EnemyNativeHover,trial=NS.EnemyNativeTrial}) do
  if module and type(module.IsActive)=="function" and NS.Read(module.IsActive)==true then
   NS.Print("请先结束其他目标试验再开启原生操作。");return false
  end
  local status=module and type(module.Status)=="function" and NS.Read(module.Status)
  if type(status)=="table" and (status.active==true or status.restoring==true) then
   NS.Print("请先结束并恢复其他目标试验。");return false
  end
 end
 if enabled() then NS.Print("原生操作试验已运行；先 off，再 on 可重新准备。");return true end
 -- Flush any previously suspended activation before choosing empty cells.
 P.Off()
 local candidates={}
 for i,row in ipairs(section.tiles) do
  if i>(section.limit or 5) then break end
  local e=NS.EnemyDisplay and NS.Read(NS.EnemyDisplay.Get,i)
  local empty=NS.Public(row.unit) and NS.Public(row.expectedGUID) and row.unit==nil and row.expectedGUID==nil
  for _,key in ipairs({"unit","combat-prepared","mfch-ready"}) do
   local ok,value=pcall(row.GetAttribute,row,key)
   if not ok or not NS.Public(value) or (key=="unit" and value~=nil)
    or (key~="unit" and value~=nil and value~=false) then empty=false end
  end
  if e and e.restrictedIdentity==true and NS.EnemyDisplay.IsCurrent(e) and empty then
   candidates[#candidates+1]={row=row,index=i,unit=e.unit}
  end
 end
 if #candidates==0 then NS.Print("没有可测试的受限敌人格子，请靠近怪物。");return false end
 local owner=getOwner();P.generation=(P.generation or 0)+1;P.activations=(P.activations or 0)+1
 if NS.Diagnostics and type(NS.Diagnostics.Start)=="function" then NS.Diagnostics.Start() end
 for key,module in pairs({nearby=NS.NearbyCast,names=NS.CombatCast,fixed=NS.CombatHover}) do
  if module and module.owner then owner:SetFrameRef(key,module.owner) end
 end
 owner:SetAttribute("combat",false);owner:SetAttribute("enabled",true);owner:SetAttribute("rows",#candidates)
 for _,c in ipairs(candidates) do
  local s=createState(c.row,c.index,c.unit);P.rows[#P.rows+1]=s;P.byRow[c.row]=s
  -- Stop loops use contiguous references, while hover IDs retain physical cells.
  owner:SetFrameRef("row"..#P.rows,s.overlay);owner:SetFrameRef("palette"..#P.rows,s.palette)
  prepareSpells(s);s.overlay:Show()
 end
 P.stop:ClearAllPoints();P.stop:SetPoint("TOPRIGHT",section.frame,"TOPLEFT",-3,0);P.stop:Show()
 if NS.RefreshTiles then NS.RefreshTiles() end
 NS.Print("原生操作试验已开启：左键目标、右键焦点、Ctrl+右键选标记；悬停按原普通技能键。进入战斗自动停止，输入 /mytargets instanceactions off 关闭。结果以日志和游戏实际效果为准。")
 return true
end
function P.OnEvent(event)
 if not P.owner then return end
 if event=="PLAYER_REGEN_ENABLED" and not enabled() then P.Off()
 elseif (event=="PLAYER_LEAVING_WORLD" or event=="PLAYER_LOGOUT" or event=="UPDATE_BINDINGS"
  or event=="SPELLS_CHANGED") and idle() then P.Off() end
end
function P.Command(arg)
 arg=NS.Text(arg):lower()
 if arg=="on" then return P.On() elseif arg=="off" then return P.Off() end
 NS.Print("副本原生操作试验："..(enabled() and "运行中" or "未运行").."；/mytargets instanceactions on / off。仅脱战验证，不宣称客户端已接受动作。")
 return enabled()
end
