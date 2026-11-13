-- Simulates the scale-independent native hit area HYPOTHESIS, not game proof.
local source = assert(io.open("PersonalAddons/work/gather-recovery/MFPTinyProbe.lua")):read("*a")
local checks=0
local function check(v, why) assert(v,why); checks=checks+1 end
local function client()
    local e=setmetatable({}, {__index=_G})
    local s={now=0,cx=500,cy=600,frames={},timers={},logs={},mouse=false,combat=false,dead=false,zoom=0}
    e.MyForeverProfessionsDB={gatherAlerts=false}
    e.GetTime=function() return s.now end
    e.print=function(...) s.logs[#s.logs+1]={...} end
    e.issecretvalue=function(v) return type(v)=="table" and v.secret==true end
    e.InCombatLockdown=function() return s.combat end
    e.UnitIsDeadOrGhost=function() return s.dead end
    e.IsMouseButtonDown=function() return s.mouse end
    e.GetCursorPosition=function() return s.cx,s.cy end
    e.WorldFrame={}
    local mt={}
    local function frame()
        local f=setmetatable({localScale=1.25,alpha=.8,clicks=true,wheel=true,children={},scripts={},events={},anchors={{"BOTTOMLEFT",e.WorldFrame,"BOTTOMLEFT",100,200}}},{__index=mt})
        s.frames[#s.frames+1]=f; return f
    end
    function mt:GetNumPoints() return #self.anchors end
    function mt:GetPoint(i) return unpack(self.anchors[i],1,5) end
    function mt:GetScale() return self.localScale end
    function mt:SetScale(v)
        if s.failScaleBefore and v==s.failScaleBefore then error("scale-before") end
        self.localScale=v
        if s.failScaleAfter and v==s.failScaleAfter then error("scale-after") end
    end
    function mt:GetEffectiveScale() return self.localScale*.64 end
    -- Anchored to a fixed physical parent point: GetLeft changes with scale.
    function mt:GetLeft() return 1000/self:GetEffectiveScale()+self.anchors[1][4] end
    function mt:GetBottom() return 700/self:GetEffectiveScale()+self.anchors[1][5] end
    function mt:GetWidth() return 198 end
    function mt:GetHeight() return 198 end
    function mt:AdjustPointsOffset(x,y)
        if s.failMoveBefore then error("move-before") end
        for _,a in ipairs(self.anchors) do a[4],a[5]=a[4]+x,a[5]+y end
        if s.failMoveAfter then error("move-after") end
    end
    function mt:GetAlpha() return self.alpha end
    function mt:SetAlpha(v) self.alpha=v end
    function mt:IsMouseClickEnabled() return self.clicks end
    function mt:SetMouseClickEnabled(v) self.clicks=v end
    function mt:IsMouseWheelEnabled() return self.wheel end
    function mt:EnableMouseWheel(v) self.wheel=v end
    function mt:IsProtected() return self.protected or false end
    function mt:IsVisible() return true end
    function mt:GetChildren() return unpack(self.children) end
    function mt:SetScript(k,v) self.scripts[k]=v end
    function mt:RegisterEvent(k) self.events[k]=true end
    function mt:UnregisterAllEvents() self.events={} end
    e.CreateFrame=frame
    e.Minimap=frame(); s.map=e.Minimap; s.child=frame(); s.map.children={s.child}
    e.GetMouseFoci=function() return s.foci or {e.WorldFrame} end
    e.C_Timer={After=function(delay,f) s.timers[#s.timers+1]={at=s.now+delay,fn=f} end}
    e.C_TooltipInfo={GetMinimapMouseover=function()
        if s.tipError then error("tip") end
        if s.secretTip then return {secret=true} end
        return s.rendered
    end}
    local f=assert(loadstring(source)); setfenv(f,e); f()
    local p=e.MFPTinyProbe
    function s.tick()
        s.now=s.now+1/60
        local m=s.map; local eff=m:GetEffectiveScale()
        local found={}
        for _,n in ipairs({{.08,.71,"Copper Vein"},{-.57,-.15,"Tin Vein"}}) do
            local x=(m:GetLeft()+(n[1]+1)*99)*eff
            local y=(m:GetBottom()+(n[2]+1)*99)*eff
            if (x-s.cx)^2+(y-s.cy)^2<=12^2 then found[#found+1]=n[3] end
        end
        -- Never preserve or print this unrelated tooltip body.
        found[#found+1]="Private quest text"
        s.rendered={lines={{leftText=table.concat(found,"\n")}}}
        local f=p.frame and p.frame.scripts.OnUpdate; if f then f() end
        for _,t in ipairs(s.timers) do if not t.done and s.now>=t.at then t.done=true;t.fn() end end
    end
    function s.finish() for _=1,7 do s.tick() end end
    function s.event(event) if p.frame and p.frame.events[event] then p.frame.scripts.OnEvent(nil,event) end end
    return s,p,e
end
local function restored(s,p,why)
    check(not p.active and not p.recovery,why.." inactive")
    check(math.abs(s.map.anchors[1][4]-100)<.01 and math.abs(s.map.anchors[1][5]-200)<.01,why.." anchors")
    check(s.map.localScale==1.25,why.." local scale")
    check(s.map.alpha==.8 and s.map.clicks and s.map.wheel and s.child.clicks,why.." input/alpha")
    check(p.last and p.last.restored,why.." receipt")
end
do
    local s,p=client(); check(p:Start(),"start")
    check(not p.active.at,"no same-frame placement/read")
    s.finish(); restored(s,p,"normal")
    check(#p.last.samples==3,"three final samples")
    check(not p.last.samples[1].mineral and p.last.samples[2].mineral and not p.last.samples[3].mineral,"blank tiny blank")
    check(p.last.samples[2].names:find("铜矿",1,true) and p.last.samples[2].names:find("锡矿",1,true),"overlapping known names")
    for _,r in ipairs(p.last.samples) do check(r.firstText==nil and r.text==nil,"no body retained") end
    for _,row in ipairs(s.logs) do for _,v in ipairs(row) do check(v~="Private quest text","private body not printed") end end
end
for _,mode in ipairs({"scale-before-tiny","scale-after-tiny","scale-before-full","scale-after-full","move-before","move-after","tooltip","timeout","mouse","window","cursor","world","combat","off","manual"}) do
    local s,p,e=client(); p:Start(); s.tick(); s.tick()
    if mode=="scale-before-tiny" then s.failScaleBefore=1.25/20
    elseif mode=="scale-after-tiny" then s.failScaleAfter=1.25/20
    elseif mode=="move-before" then s.failMoveBefore=true
    elseif mode=="move-after" then s.failMoveAfter=true
    elseif mode=="tooltip" then s.tipError=true
    elseif mode=="mouse" then s.mouse=true
    elseif mode=="window" then s.foci={{}}
    elseif mode=="cursor" then s.cx=s.cx+5
    elseif mode=="combat" then s.combat=true
    elseif mode=="off" then e.MyForeverProfessionsDB.gatherAlerts=true end
    if mode=="scale-before-full" or mode=="scale-after-full" then
        s.tick(); s.tick()
        if mode=="scale-before-full" then s.failScaleBefore=1.25 else s.failScaleAfter=1.25 end
    end
    if mode=="timeout" then s.now=2; for _,t in ipairs(s.timers) do if not t.done then t.done=true;t.fn() end end
    elseif mode=="world" then s.event("PLAYER_LEAVING_WORLD")
    elseif mode=="manual" then p:Cleanup("manual")
    else s.finish() end
    -- A native setter that refuses the restore is retained for an explicit retry.
    s.failScaleBefore,s.failScaleAfter,s.failMoveBefore,s.failMoveAfter=nil,nil,nil,nil
    if p.recovery then p:Cleanup("retry") end
    restored(s,p,mode)
end
do
    local s,p,e=client(); e.MyForeverProfessionsDB.gatherAlerts=true
    check(not p:Start(),"reject while scanner enabled")
    check(s.map.localScale==1.25 and s.map.alpha==.8,"no enabled mutation")
end
do
    local s,p=client(); s.child.protected=true
    check(not p:Start(),"protected child preflight")
    check(s.map.localScale==1.25 and s.map.clicks,"protected untouched")
end
do
    local s,p=client(); s.secretTip=true; p:Start(); s.finish(); restored(s,p,"secret")
    check(not p.last.samples[2].mineral and p.last.samples[2].restricted,"secret is unknown not a resource")
end
do
    local s,p=client(); p:Start(); s.tick(); s.tick(); s.tick(); s.map.localScale=.3; p:Cleanup("external-scale")
    check(s.map.localScale==.3 and not p.last.restored,"external scale preserved")
    check(s.map.alpha==.8 and s.map.clicks and s.map.wheel,"other state restored")
end
do
    local s,p=client(); p:Start(); s.tick(); s.map.anchors[1][4]=900; p:Cleanup("external-anchor")
    check(s.map.anchors[1][4]==900 and not p.last.restored,"external anchor preserved")
    check(s.map.localScale==1.25 and s.map.alpha==.8,"other geometry restored")
end
do
    local s,p=client(); p:Start(); s.tick(); s.tick(); s.tick(); s.event("GLOBAL_MOUSE_DOWN")
    restored(s,p,"global click during tiny")
end
print("MFPTinyProbe Lua 5.1 mock checks passed:",checks)
