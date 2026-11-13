local _, NS = ...

-- Read exact measurements only when the client explicitly validates them. These
-- APIs can be unavailable for enemies/non-group players and in restricted areas.
function NS.Distance(unit)
    if not NS.ValidToken(unit) or NS.Read(UnitExists,unit)~=true then return nil end
    if unit=="player" or NS.Read(UnitIsUnit,unit,"player")==true then return 0 end
    local squared,checked=NS.Read(UnitDistanceSquared,unit)
    if checked==true and NS.Number(squared) and squared>=0 then return math.sqrt(squared) end
    local x,y,z,instance=NS.Read(UnitPosition,unit)
    local px,py,pz,playerInstance=NS.Read(UnitPosition,"player")
    if not NS.Number(x) or not NS.Number(y) or not NS.Number(z) or not NS.Number(instance)
        or not NS.Number(px) or not NS.Number(py) or not NS.Number(pz) or not NS.Number(playerInstance)
        or instance~=playerInstance then return nil end
    local distanceSquared=(x-px)^2+(y-py)^2+(z-pz)^2
    if NS.Number(distanceSquared) then return math.sqrt(distanceSquared) end
end

local function rangeLibrary()
    if NS.RangeCheck then return NS.RangeCheck end
    if type(LibStub)=="table" and type(LibStub.GetLibrary)=="function" then
        NS.RangeCheck=NS.Read(LibStub.GetLibrary,LibStub,"LibRangeCheck-3.0",true)
    end
    return NS.RangeCheck
end

function NS.MeasureDistance(unit)
    local exact=NS.Distance(unit)
    if exact~=nil then return {min=exact,max=exact,exact=true} end
    if not NS.ValidToken(unit) or NS.Read(UnitExists,unit)~=true then return nil end
    local library=rangeLibrary()
    if not library then return nil end
    local minimum,maximum=NS.Read(library.GetRange,library,unit,true,false,0.1)
    -- Range checks are intervals, not coordinates. An unbounded result can also
    -- mean no successful usable checker; leave it unknown instead of guessing.
    if not NS.Number(minimum) or not NS.Number(maximum) or minimum<0 or maximum<minimum then return nil end
    return {min=minimum,max=maximum,exact=false}
end

local function number(value)
    return (string.format("%.1f",value):gsub("%.0$",""))
end

function NS.DistanceText(range)
    if type(range)~="table" or not NS.Number(range.min) or not NS.Number(range.max) then return "距离未知" end
    if range.exact then return number(range.max).."码" end
    return number(range.min).."–"..number(range.max).."码（估计）"
end
