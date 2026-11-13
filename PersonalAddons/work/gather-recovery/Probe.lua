local _, ns = ...
local d = { ns = ns, history = {} }
_G.MFPDiag = d
local function text()
    local data = C_TooltipInfo.GetMinimapMouseover()
    local lines = {}
    for _, line in ipairs(data and data.lines or {}) do
        local s = line.leftText
        if type(s) == 'string' and not (issecretvalue and issecretvalue(s)) then
            lines[#lines+1] = s:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):gsub('|T.-|t',''):gsub('|A.-|a','')
        end
    end
    return table.concat(lines, ' / ')
end
function d:Stop()
    if self.frame then self.frame:SetScript('OnUpdate', nil) end
    Minimap:SetUsingSoftCursor(false)
    if self.original ~= nil then ns.db.gatherAlerts = self.original; self.original = nil end
    ns.GatherScan.Reset()
end
function d:Prepare()
    self:Stop()
    self.original = ns.db.gatherAlerts
    ns.db.gatherAlerts = false
    self.frame = self.frame or CreateFrame('Frame')
end
function d:Point(x,y,soft)
    Minimap:SetUsingSoftCursor(soft ~= false)
    Minimap:UpdateMouseoverAtPoint(x,y)
    local s = text()
    Minimap:SetUsingSoftCursor(false)
    print('PROBE',x,y,soft,s == '' and '<empty>' or s)
end
function d:Scan(mode,soft)
    self:Prepare()
    local l,b,w,h=Minimap:GetRect()
    local sc=Minimap:GetEffectiveScale()
    local sw,sh=GetScreenWidth(),GetScreenHeight()
    local pw,ph=GetPhysicalScreenSize()
    local cx,cy=GetCursorPosition()
    local r={mode=mode,soft=soft,hover=(cx>=l*sc and cx<=(l+w)*sc and cy>=b*sc and cy<=(b+h)*sc),cx=cx,cy=cy,total=0,nonempty=0,names={},ore=0,oreMinX=1,oreMaxX=-1,oreMinY=1,oreMaxY=-1}
    local points={}
    for iy=0,40 do for ix=0,40 do
        local u,v=ix/40,iy/40
        if (u-.5)^2+(v-.5)^2 <= .25 then
            local x,y=(l+u*w)*sc,(b+v*h)*sc
            if mode=='top' then y=sh*UIParent:GetEffectiveScale()-y
            elseif mode=='ui' then x,y=l+u*w,b+v*h
            elseif mode=='local' then x,y=u*w,v*h
            elseif mode=='center' then x,y=(u-.5)*w,(v-.5)*h
            elseif mode=='localScaled' then x,y=u*w*sc,v*h*sc
            elseif mode=='centerScaled' then x,y=(u-.5)*w*sc,(v-.5)*h*sc
            elseif mode=='unit' then x,y=u,v
            elseif mode=='signed' then x,y=u*2-1,v*2-1
            elseif mode=='screenUnit' then x,y=x/(sw*UIParent:GetEffectiveScale()),y/(sh*UIParent:GetEffectiveScale())
            elseif mode=='screenUnitTop' then x,y=x/(sw*UIParent:GetEffectiveScale()),1-y/(sh*UIParent:GetEffectiveScale())
            elseif mode=='screenSigned' then x,y=x/(sw*UIParent:GetEffectiveScale())*2-1,y/(sh*UIParent:GetEffectiveScale())*2-1
            elseif mode=='physical' then x,y=x*ph/(sh*UIParent:GetEffectiveScale()),y*ph/(sh*UIParent:GetEffectiveScale())
            elseif mode=='physicalTop' then x,y=x*ph/(sh*UIParent:GetEffectiveScale()),ph-y*ph/(sh*UIParent:GetEffectiveScale()) end
            points[#points+1]={x=x,y=y,u=u,v=v}
        end
    end end
    local index=1
    self.frame:SetScript('OnUpdate',function()
        local ok,err=pcall(function()
            Minimap:SetUsingSoftCursor(soft~=false)
            for n=1,80 do
                local p=points[index]
                if not p then break end
                Minimap:UpdateMouseoverAtPoint(p.x,p.y)
                local s=text()
                r.total=r.total+1
                if s~='' then r.nonempty=r.nonempty+1 end
                r.names[s]=(r.names[s] or 0)+1
                if s:find('铜矿',1,true) then
                    r.ore=r.ore+1
                    r.oreMinX=math.min(r.oreMinX,p.u);r.oreMaxX=math.max(r.oreMaxX,p.u)
                    r.oreMinY=math.min(r.oreMinY,p.v);r.oreMaxY=math.max(r.oreMaxY,p.v)
                end
                index=index+1
            end
        end)
        Minimap:SetUsingSoftCursor(false)
        if not ok or index>#points then
            self.frame:SetScript('OnUpdate',nil)
            r.error=not ok and tostring(err) or nil
            self.history[#self.history+1]=r
            local distinct=0;for _ in pairs(r.names) do distinct=distinct+1 end
            print('PROBE '..mode..' soft='..tostring(soft)..' hover='..tostring(r.hover)..' all='..r.total..' nonempty='..r.nonempty..' unique='..distinct..' ore='..r.ore)
            print('RANGE',r.oreMinX,r.oreMaxX,r.oreMinY,r.oreMaxY,r.error or '')
            self.last=r
        end
    end)
end

function d:Wide()
    self:Prepare()
    local x,y,count,counts=0,0,0,{}
    self.frame:SetScript('OnUpdate',function()
        local begin=debugprofilestop()
        local ok,err=pcall(function()
            Minimap:SetUsingSoftCursor(true)
            for i=1,500 do
                Minimap:UpdateMouseoverAtPoint(x,y)
                local s=text()
                counts[s]=(counts[s] or 0)+1
                count=count+1
                x=x+2
                if x>2560 then x=0;y=y+2 end
                if y>1440 or debugprofilestop()-begin>2 then break end
            end
        end)
        Minimap:SetUsingSoftCursor(false)
        if not ok or y>1440 then
            self.frame:SetScript('OnUpdate',nil)
            local n=0;for s,c in pairs(counts) do n=n+1;print('WIDE value',c,s) end
            print('WIDE done',count,n,err)
            self.wide={count=count,unique=n,counts=counts,error=err}
        end
    end)
end
