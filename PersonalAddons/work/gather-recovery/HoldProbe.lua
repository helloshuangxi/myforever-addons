local _, ns = ...
local d = { ns = ns, results = {} }
_G.MFPHold = d
local function read()
    local data = C_TooltipInfo.GetMinimapMouseover()
    local out = {}
    for _, line in ipairs(data and data.lines or {}) do
        if type(line.leftText) == 'string' and not (issecretvalue and issecretvalue(line.leftText)) then
            out[#out+1] = line.leftText:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
        end
    end
    return #out > 0 and table.concat(out, ' / ') or '<empty>'
end
function d:Stop()
    self.generation=(self.generation or 0)+1
    if self.frame then self.frame:SetScript('OnUpdate', nil) end
    Minimap:SetUsingSoftCursor(false)
    if self.cvars then
        for k,v in pairs(self.cvars) do C_CVar.SetCVar(k,v) end
        self.cvars=nil
    end
    if self.oldHover ~= nil then C_GamePad.SetAllowHoverEventsWithFreeLook(self.oldHover); self.oldHover = nil end
    if self.original ~= nil then ns.db.gatherAlerts = self.original; self.original = nil end
    ns.GatherScan.Reset()
end
function d:Prepare()
    self:Stop()
    self.original = ns.db.gatherAlerts
    ns.db.gatherAlerts = false
    self.frame = self.frame or CreateFrame('Frame')
    local generation=self.generation
    C_Timer.After(60,function() if self.generation==generation then self:Stop();print('PROBE timeout restored') end end)
end
function d:Soft()
    self:Prepare()
    local settings={SoftTargetInteract=3,SoftTargetInteractRange=60,SoftTargetInteractArc=2,SoftTargetInteractOnlyInRange=0}
    self.cvars={}
    for k,v in pairs(settings) do self.cvars[k]=C_CVar.GetCVar(k);C_CVar.SetCVar(k,v) end
    local function safe(v)
        if issecretvalue and issecretvalue(v) then return '<secret>' end
        return tostring(v)
    end
    for _,delay in ipairs({1,3,6}) do C_Timer.After(delay,function()
        local ok,err=pcall(function()
            local x,y,z,map=UnitPosition('softinteract')
            print('SOFTPOS',safe(UnitIsGameObject('softinteract')),safe(UnitName('softinteract')),safe(UnitGUID('softinteract')),safe(x),safe(y),safe(z),safe(map))
            self.softResult={exists=safe(UnitExists('softinteract')),object=safe(UnitIsGameObject('softinteract')),name=safe(UnitName('softinteract')),x=safe(x),y=safe(y),z=safe(z),map=safe(map)}
        end)
        if not ok then self:Stop();print('SOFT ERROR',err) end
    end) end
    C_Timer.After(8,function() self:Stop();print('SOFT restored') end)
end

local logout=CreateFrame('Frame')
logout:RegisterEvent('PLAYER_LOGOUT')
logout:SetScript('OnEvent',function() d:Stop() end)
function d:Capture()
    self:Prepare()
    C_Timer.After(5, function()
        local x,y = GetCursorPosition()
        self.point = { x=x, y=y, text=read() }
        print('CAPTURE', x, y, self.point.text)
    end)
end
function d:Read() print('HOLD READ', read()) end
function d:Latch(enabled)
    if enabled then self:Prepare() end
    Minimap:SetUsingSoftCursor(enabled)
    print('LATCH',enabled,read())
end
function d:Run(hover)
    if not self.point then print('Capture a live ore first'); return end
    local x,y=GetCursorPosition()
    local l,b,w,h=Minimap:GetScaledRect()
    if x>=l and x<=l+w and y>=b and y<=b+h then print('Move real pointer outside minimap');return end
    self:Prepare()
    if hover then
        self.oldHover = C_GamePad.GetAllowHoverEventsWithFreeLook()
        C_GamePad.SetAllowHoverEventsWithFreeLook(true)
    end
    local segment, start, count, before, after = 1, GetTime(), 0, '', ''
    Minimap:SetUsingSoftCursor(true)
    self.frame:SetScript('OnUpdate', function()
        local ok,err=pcall(function()
            before=read()
            local p=segment%2==1 and self.point or {x=100,y=100}
            Minimap:UpdateMouseoverAtPoint(p.x,p.y)
            after=read()
            count=count+1
            if GetTime()-start>=0.5 then
                self.results[#self.results+1]={segment=segment,hover=hover,count=count,before=before,after=after}
                print('HOLD '..segment..' '..(segment%2==1 and 'ore' or 'outside')..' '..count..' before='..before..' after='..after)
                segment,start,count=segment+1,GetTime(),0
                if segment>8 then self:Stop();print('HOLD FINISHED',ns.db.gatherAlerts) end
            end
        end)
        if not ok then self:Stop();print('HOLD ERROR',err) end
    end)
end
