-- Lua 5.1 native-widget contract simulations; not a live game verification.
local checks = 0
local function eq(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected, tolerance, label)
    checks = checks + 1
    assert(math.abs(actual-expected) <= tolerance, label .. ": " .. tostring(actual))
end
local now, combat, hover, rotating, facing, shape = 0, false, false, false, 0, "ROUND"
local cursorX, cursorY, probes, enables, releases = 900, 20, 0, 0, 0
local tooltipReads = 0
local currentX, currentY, getterError, restoreError, enableError, releaseError, stickyText
local nodes = {}
GetTime = function() return now end
InCombatLockdown = function() return combat end
GetCursorPosition = function() return cursorX, cursorY end
GetCVar = function() return rotating and "1" or "0" end
GetPlayerFacing = function() return facing end
GetMinimapShape = function() return shape end
MouseIsOver = function() return hover end
C_Minimap = {GetUiMapID=function() return 1426 end}
local map = {cx=100,cy=100,width=60,height=60,scale=2,zoom=0,visible=true}
function map:IsVisible() return self.visible end
function map:GetCenter() return self.cx,self.cy end
function map:GetWidth() return self.width end
function map:GetHeight() return self.height end
function map:GetEffectiveScale() return self.scale end
function map:GetZoom() return self.zoom end
function map:SetUsingSoftCursor(value)
    if value then
        enables = enables + 1
        if enableError then error("denied") end
    else
        releases = releases + 1
        if releaseError then error("release denied") end
    end
    self.soft = value
end
function map:UpdateMouseoverAtPoint(x,y)
    if x == cursorX and y == cursorY then
        if restoreError then error("restore denied") end
        self.restored = {x,y}
        return
    end
    probes = probes + 1
    currentX, currentY = x,y
    self.first = self.first or {x,y}
end
local tooltip = {GetMinimapMouseover=function()
    tooltipReads = tooltipReads + 1
    if getterError then error("native tooltip refused") end
    local dx=(currentX-map.cx*map.scale)/(map.width*map.scale/2)
    local dy=(currentY-map.cy*map.scale)/(map.height*map.scale/2)
    local lines = {}
    if stickyText then lines[#lines+1]={leftText=stickyText} end
    for _,node in ipairs(nodes) do
        if (dx-node.dx)^2+(dy-node.dy)^2 <= (node.radius or 0.15)^2 then
            lines[#lines+1]={leftText=node.name}
            lines[#lines+1]={leftText=node.name} -- repeated text is not two dots
        end
    end
    return {lines=lines}
end}
local ns = {}
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/GatherScan.lua"))("MyForeverProfessions",ns)
local scan = ns.GatherScan
eq(scan.IsSupported(),false,"missing client capabilities")
eq(scan.Scan(),nil,"missing client does not throw")
Minimap, C_TooltipInfo = map, tooltip
eq(scan.IsSupported(),true,"late native capabilities discovered")
local function run(interval)
    for i=1,160 do
        local before=probes
        now=now+(interval or 0.05)
        local result,hints=scan.Scan()
        assert(probes-before <= 96,"bounded native calls")
        if result then return result,hints end
    end
    error("pass never completed")
end
nodes={{name="|cffffff00铜矿|r",dx=.5,dy=1/3},{name="铜矿",dx=-.5,dy=-1/3}}
eq(scan.Scan(),nil,"first batch is incomplete")
near(map.first[1],200,0.0001,"nearest-first physical center x")
near(map.first[2],200,0.0001,"effective scale applied to center y")
local result=run()
eq(#result,2,"same-name deposits remain spatially separate")
table.sort(result,function(a,b) return a.dx < b.dx end)
eq(result[1].name,"铜矿","color escape removed")
near(result[1].dx,-.5,.05,"left offset is negative half-radius")
near(result[1].dy,-1/3,.05,"south offset is negative")
near(result[2].dx,.5,.05,"east offset is positive")
near(result[2].dy,1/3,.05,"north offset is positive")
eq(result[1].facing,nil,"north-up maps need no facing correction")
eq(map.soft,false,"soft cursor released after successful batches")
eq(map.restored[1],cursorX,"actual cursor x restored")
eq(map.restored[2],cursorY,"actual cursor y restored")
eq(enables,releases,"every batch releases native cursor")

-- No hover emulation during combat, invisibility, or real minimap interaction.
local before=probes
combat=true; now=now+.1; eq(scan.Scan(),nil,"combat skips")
combat=false; map.visible=false; now=now+.1; eq(scan.Scan(),nil,"hidden skips")
map.visible=true; hover=true; now=now+.1; eq(scan.Scan(),nil,"mouse-over helper skips")
hover=false; cursorX,cursorY=200,200; now=now+.1
eq(scan.Scan(),nil,"physical mouse inside minimap skips")
eq(probes,before,"skipped scans never touch native hit testing")
cursorX,cursorY=900,20

-- An old half-pass cannot publish after a zoom, scale, map layout, or rotation change.
nodes={{name="旧矿",dx=0,dy=0}}
now=now+.1; scan.Scan()
nodes={{name="新矿",dx=.5,dy=1/3}}
map.zoom=1
result=run()
eq(#result,1,"zoom change discards old observations")
eq(result[1].name,"新矿","only fresh zoom data returned")
nodes={{name="旧矿",dx=0,dy=0}}
now=now+.1; scan.Scan()
nodes={{name="新矿",dx=.5,dy=1/3}}
map.cx=130;map.scale=1.5
result=run()
eq(#result,1,"layout and scale change discard old observations")
eq(result[1].name,"新矿","physical coordinate conversion survives changed scale")
nodes={{name="旧矿",dx=0,dy=0}}
now=now+.1; scan.Scan()
nodes={{name="新矿",dx=.5,dy=1/3}}
rotating=true;facing=1.25
result=run()
eq(#result,1,"rotate setting change discards old observations")
eq(result[1].facing,1.25,"rotating pass exposes sampled player facing")
nodes={{name="旧矿",dx=0,dy=0}}
now=now+.1; scan.Scan()
nodes={{name="转身后矿",dx=.5,dy=1/3}}
facing=2
result=run()
eq(#result,1,"turning invalidates inconsistent rotating sample pass")
eq(result[1].name,"转身后矿","only observations after turning returned")
eq(result[1].facing,2,"new facing snapshot returned")
C_Minimap.IsRotateMinimapIgnored=function() return true end
result=run()
eq(result[1].facing,nil,"native forced north-up overrides rotate setting")
C_Minimap.IsRotateMinimapIgnored=nil
nodes={{name=" |TInterface\\Icons\\INV_Ore_Copper_01:12|t |cffffff00铜矿|r\n\n|A:Professions:12:12|a 银叶草\r\n铜矿 ",dx=0,dy=0}}
result=run()
eq(#result,2,"multiline coincident names split and deduplicated")
local names={}
for _,hit in ipairs(result) do names[hit.name]=true end
eq(names["铜矿"],true,"colored texture-prefixed line normalized")
eq(names["银叶草"],true,"atlas-prefixed second line normalized")

-- Manual Reset drops cached partial hits, such as after changing tracking mode.
nodes={{name="旧矿",dx=0,dy=0}}
now=now+.1;scan.Scan();scan.Reset()
nodes={};result=run()
eq(#result,0,"completed empty result distinct from incomplete nil")

-- Native errors must still restore and release; no tight repeated failure loop.
getterError=true
now=now+.1
eq(scan.Scan(),nil,"native tooltip error is contained")
eq(map.soft,false,"native tooltip error releases soft cursor")
eq(map.restored[1],cursorX,"native tooltip error restores actual cursor")
before=probes
getterError=false;now=now+.2
eq(scan.Scan(),nil,"quiet cooldown after native error")
eq(probes,before,"cooldown does not repeatedly call failing native API")
now=now+10
result=run()
eq(#result,0,"scan recovers after quiet suspension")
enableError=true; now=now+.1
local released=releases
eq(scan.Scan(),nil,"soft cursor activation exception is contained")
eq(releases,released+1,"activation exception still attempts release")
enableError=false;now=now+11
restoreError=true; released=releases
eq(scan.Scan(),nil,"restore exception is contained")
eq(releases,released+1,"release still happens if pointer restore fails")
restoreError=false;now=now+11

-- Mask-aware coverage and malformed geometry.
rotating=false;shape="SQUARE"
nodes={{name="角落矿",dx=5/6,dy=5/6,radius=.2}}
result=run()
eq(#result,1,"square minimap corner remains covered")
shape="ROUND";scan.Reset();result=run()
eq(#result,0,"round map excludes outside-mask sample points")
map.width=0;now=now+.1
eq(scan.Scan(),nil,"zero-size map is skipped")
map.width=60;map.scale=0/0;now=now+.1
eq(scan.Scan(),nil,"NaN geometry is skipped")
map.scale=2
-- The integration timer runs at 0.1 seconds. A maximum-density enlarged
-- minimap must not repeatedly expire just before its last batches finish.
map.width,map.height,map.scale=600,600,1
scan.Reset();nodes={{name="大图矿",dx=0,dy=0,radius=.05}}
local started=now
result=run(.1)
eq(#result,1,"maximum grid completes with integration timer cadence")
eq(result[1].name,"大图矿","large-grid observations retained through completion")
checks=checks+1;assert(now-started < 10,"large grid finishes before stale-pass cutoff")

-- A broken client may return the previous hovered resource at every queried
-- location. Averaging that footprint must not manufacture a center deposit.
nodes={};stickyText="铜矿"
scan.Reset();result=run(.1)
eq(#result,0,"full round-map stale tooltip does not become nearby copper")
eq(map.soft,false,"rejected stale footprint still releases native cursor")
eq(map.restored[1],cursorX,"rejected stale footprint still restores pointer")
shape="SQUARE";scan.Reset();result=run(.1)
eq(#result,0,"full square-map stale tooltip also rejected")
nodes={{name="银叶草",dx=.5,dy=.25,radius=.06},{name="银叶草",dx=-.5,dy=-.25,radius=.06}}
scan.Reset();result=run(.1)
eq(#result,2,"stale name rejected without discarding separate valid resources")
eq(result[1].name,"银叶草","valid local footprint survives stale other tooltip line")
stickyText=nil;shape="ROUND"

-- Broad but incomplete regions and thin streaks also have no trustworthy
-- point location. Ordinary center and edge blips must remain accepted.
nodes={{name="宽大片矿",dx=0,dy=0,radius=.55}}
scan.Reset();result=run(.1)
eq(#result,0,"broad partial-map footprint rejected below majority coverage")
nodes={{name="铜矿",dx=0,dy=0,radius=.55},{name="铜矿",dx=.85,dy=0,radius=.06}}
scan.Reset();result=run(.1)
eq(#result,1,"invalid component does not discard separate same-name valid dot")
near(result[1].dx,.85,.05,"separate valid same-name dot retains its position")
nodes={}
for i=-14,14 do nodes[#nodes+1]={name="条带矿",dx=i*.05,dy=0,radius=.03} end
scan.Reset();result=run(.1)
eq(#result,0,"thin wide streak rejected despite low total coverage")
nodes={{name="中心矿",dx=0,dy=0,radius=.05},{name="边缘矿",dx=.95,dy=0,radius=.06}}
scan.Reset();result=run(.1)
eq(#result,2,"legitimate center and clipped edge footprints retained")
eq(result[1].name,"中心矿","real center footprint still sorts nearest")
near(result[1].dx,0,.01,"real center x remains zero")
near(result[2].dx,.95,.05,"clipped edge retains useful direction")

-- Physical bounds account for scale; compact maps need the coverage guard
-- even when the fixed UI-pixel allowance is larger than their dimensions.
cursorX,cursorY=-1000,-1000
for _,layout in ipairs({{40,40,.6},{140,100,1.4},{400,240,3}}) do
    map.width,map.height,map.scale=layout[1],layout[2],layout[3]
    nodes={{name="铜矿",dx=-.5,dy=0,radius=.16},{name="铜矿",dx=.5,dy=0,radius=.16}}
    scan.Reset();result=run(.1)
    eq(#result,2,"scaled rectangular/compact map retains separate same-name dots")
    nodes={};stickyText="铜矿"
    scan.Reset();result=run(.1)
    eq(#result,0,"scaled rectangular/compact map rejects global stale text")
    stickyText=nil
end
-- An unlocated clue remains separate from navigation, and the next successful
-- pass upgrades automatically without resetting or reloading the module.
map.width,map.height,map.scale=140,140,1
nodes={};stickyText="|cffffff00铜矿|r\n铜矿"
scan.Reset()
local located,hints=run(.1)
eq(#located,0,"unlocated text never appears in navigable dots")
eq(#hints,1,"repeated rejected text becomes one hint")
eq(hints[1].name,"铜矿","hint retains normalized resource name")
eq(hints[1].dx,nil,"hint has no x coordinate")
eq(hints[1].dy,nil,"hint has no y coordinate")
eq(hints[1].facing,nil,"hint has no direction snapshot")
stickyText=nil;nodes={{name="铜矿",dx=.5,dy=0,radius=.12}}
located,hints=run(.1)
eq(#located,1,"localized data resumes on the next completed pass")
eq(#hints,0,"restored location removes obsolete hint")
near(located[1].dx,.5,.1,"recovered dot keeps measured offset")
stickyText="铜矿";nodes={}
located,hints=run(.1)
eq(#located,0,"renewed invalid data clears navigation")
eq(#hints,1,"renewed invalid data still exposes unlocated clue")
stickyText=nil
located,hints=run(.1)
eq(#located,0,"empty pass has no located resources")
eq(#hints,0,"empty pass clears unlocated hints")
nodes={{name="铜矿",dx=-.3,dy=0,radius=.55},{name="铜矿",dx=.8,dy=0,radius=.10}}
located,hints=run(.1)
eq(#located,1,"valid same-name component survives rejected component")
eq(#hints,0,"valid same-name location supersedes ambiguous duplicate")

-- Production names-only mode must not depend on direction or expose rejected
-- old tooltip text. The original Scan contract above remains unchanged.
assert(loadfile("_forever_/Interface/AddOns/MyForeverProfessions/GatherResources.lua"))("MyForeverProfessions",ns)
local function runNames(interval)
    for _=1,160 do
        local before=probes
        now=now+(interval or .1)
        local names, extra=scan.ScanNames()
        assert(extra==nil,"names-only has no intermediate hint return")
        assert(probes-before<=96,"bounded names-only native calls")
        if names then eq(extra,nil,"names-only has no hint return");return names end
    end
    error("names-only pass never completed")
end
local function nameSet(list)
    local set={}
    for _,item in ipairs(list) do
        for key in pairs(item) do eq(key,"name","only name is public") end
        set[ns.GatherResourceKey(item.name)]=true
    end
    return set
end
map.width,map.height,map.scale=140,140,1
rotating=true;stickyText=nil;nodes={{name="铜矿",dx=.5,dy=.25,radius=.12}}
local headingCalls, forbiddenChanges=0,0
local oldFacing=GetPlayerFacing
GetPlayerFacing=function() headingCalls=headingCalls+1; error("names-only must not read heading") end
local function forbidden() forbiddenChanges=forbiddenChanges+1;error("must not alter visible minimap or pointer") end
map.SetAlpha,map.SetScale,map.SetIconScale,map.AdjustPointsOffset=forbidden,forbidden,forbidden,forbidden
C_Minimap.SetTracking=forbidden
SetCursorPosition=forbidden
scan.Reset();result=runNames()
eq(#result,1,"names-only accepts localized known mineral")
eq(result[1].name,"铜矿","names-only retains observed node name")
eq(headingCalls,0,"rotating map names-only never requests facing")
eq(forbiddenChanges,0,"names-only never moves or hides map or real cursor")
nameSet(result)
eq(map.soft,false,"names-only releases native soft cursor")
eq(map.restored[1],cursorX,"names-only restores hover position")

nodes={};stickyText="铜矿\nCopper Vein";scan.Reset();result=runNames()
eq(#result,0,"names-only rejects full-map stale mineral names")
nodes={{name="银叶草",dx=.5,dy=0,radius=.1}};scan.Reset();result=runNames()
eq(#result,1,"valid local resource survives stale other resource text")
eq(result[1].name,"银叶草","only localized name is published")
stickyText=nil
nodes={{name="铜矿",dx=-.5,dy=0,radius=.12},{name="铜矿脉\nCopper Vein",dx=.5,dy=0,radius=.12},
    {name="贫瘠的铜矿脉",dx=0,dy=.5,radius=.12},{name="玩家姓名\n任务正文",dx=0,dy=0,radius=.12}}
scan.Reset();result=runNames()
eq(#result,2,"explicit aliases and duplicate nodes deduplicate without merging weak copper")
local found=nameSet(result)
eq(found["铜矿"],true,"copper alias group present")
eq(found["贫瘠的铜矿脉"],true,"different node at same skill rank retained")
eq(found["玩家姓名"],nil,"non-resource tooltip name not published")
eq(found["任务正文"],nil,"non-resource tooltip body not published")
nodes={{name="铜矿",dx=0,dy=0,radius=.55},{name="铜矿脉",dx=.85,dy=0,radius=.1}}
scan.Reset();result=runNames()
eq(#result,1,"valid alias component survives broad rejected component")
eq(result[1].name,"铜矿脉","display spelling must come from accepted footprint")

-- Switching interfaces discards partial samples in both directions.
GetPlayerFacing=oldFacing;rotating=false
nodes={{name="铜矿",dx=0,dy=0,radius=.12}};scan.Reset();now=now+.1;scan.Scan()
nodes={{name="锡矿",dx=.5,dy=0,radius=.12}};result=runNames()
eq(#result,1,"legacy-to-names discards partial old sample")
eq(result[1].name,"锡矿","legacy-to-names returns only new mode observation")
nodes={{name="铜矿",dx=0,dy=0,radius=.12}};now=now+.1;scan.ScanNames()
nodes={{name="锡矿",dx=.5,dy=0,radius=.12}};result=run(.1)
eq(#result,1,"names-to-legacy discards partial old sample")
eq(result[1].name,"锡矿","names-to-legacy retains legacy contract")
near(result[1].dx,.5,.1,"legacy coordinates still available only through Scan")

-- Optional input APIs pause names-only sampling without breaking old clients
-- that do not expose them. Real held buttons and mouselook drop old half-passes.
local held, looking=false,false
IsMouseButtonDown=function(button) return button=="RightButton" and held or false end
IsMouselooking=function() return looking end
nodes={{name="铜矿",dx=0,dy=0,radius=.12}};scan.Reset();now=now+.1;scan.ScanNames()
before=probes;held=true;now=now+.1
eq(scan.ScanNames(),nil,"held right pauses names-only")
eq(probes,before,"held right never calls native hit testing")
held=false;looking=true;now=now+.1
eq(scan.ScanNames(),nil,"mouselook pauses after button release")
eq(probes,before,"mouselook never calls native hit testing")
looking=false;nodes={{name="锡矿",dx=.5,dy=0,radius=.12}};result=runNames()
eq(#result,1,"resume after mouse interaction starts fresh")
eq(result[1].name,"锡矿","mouse pause discards old copper observation")
local oldSecret=issecretvalue
local secret={}
issecretvalue=function(value) return value==secret end
IsMouseButtonDown=function() return secret end
before=probes;now=now+.1
eq(scan.ScanNames(),nil,"restricted mouse state pauses safely")
eq(probes,before,"restricted mouse state cannot start native sampling")
IsMouseButtonDown=function() error("unavailable") end;now=now+.1
eq(scan.ScanNames(),nil,"throwing optional mouse API pauses safely")
IsMouseButtonDown=nil;IsMouselooking=nil;issecretvalue=oldSecret

-- Restore/read failures must never publish the current pass, including when
-- its last sample has already been collected; recovery follows the old cooldown.
for _,mode in ipairs({"read","restore","enable"}) do
    nodes={{name="铜矿",dx=0,dy=0,radius=.12}};scan.Reset();now=now+11
    getterError=mode=="read";restoreError=mode=="restore";enableError=mode=="enable"
    released=releases
    eq(scan.ScanNames(),nil,"names-only contains "..mode.." failure")
    eq(releases,released+1,"names-only always attempts release after "..mode.." failure")
    getterError,restoreError,enableError=false,false,false
    before=probes;now=now+.1
    eq(scan.ScanNames(),nil,"names-only suspends after "..mode.." failure")
    eq(probes,before,"failed pass cannot continue after "..mode)
    now=now+11;nodes={};result=runNames()
    eq(#result,0,"failed "..mode.." pass cannot leak copper later")
    eq(map.soft,false,"names-only recovers soft cursor after "..mode)
end
-- A release exception is different from a tooltip failure: keep recovery
-- pending and retry without enabling soft cursor or collecting another sample.
nodes={{name="铜矿",dx=0,dy=0,radius=.12}};scan.Reset();now=now+11
releaseError=true;before=probes
eq(scan.ScanNames(),nil,"failed release never publishes names")
eq(map.soft,true,"mock models release failing before applying")
local enabledBefore=enables
before=probes;now=now+.1
eq(scan.ScanNames(),nil,"failed release blocks new batches")
eq(enables,enabledBefore,"pending release is not enabled again")
eq(probes,before,"pending release performs no sampling")
releaseError=false;scan.Reset()
eq(map.soft,false,"disabled/reset path retries pending native release")
now=now+11;nodes={};result=runNames()
eq(#result,0,"release-failed pass cannot leak names after recovery")
eq(forbiddenChanges,0,"all names-only scenarios leave visible map settings untouched")

-- Diagnostics observe the same completed pass; they do not change acceptance,
-- perform native reads, or disclose anything beyond catalogued mineral/herb names.
nodes={{name="铜矿\n玩家姓名\n任务正文",dx=.5,dy=.25,radius=.12}}
stickyText=nil;scan.Reset();before=probes
result=runNames()
local diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"ready","completed diagnostic state")
eq(diagnostic.reason,"completed","completed diagnostic reason")
eq(diagnostic.sampleCount,probes-before,"sample count matches actual hit-test samples")
eq(diagnostic.completedAt,now,"completion timestamp uses existing pass time")
eq(#diagnostic.rawKnownNames,1,"raw diagnostic excludes player and quest text")
eq(diagnostic.rawKnownNames[1],"铜矿","localized raw known name")
eq(diagnostic.acceptedNames[1],"铜矿","localized accepted name")
eq(#diagnostic.rejectedKnownNames,0,"localized footprint not rejected")
eq(#result,1,"diagnostics do not change localized result")
local diagReads,diagProbes,diagEnables,diagReleases=tooltipReads,probes,enables,releases
local diagGetTime=GetTime
GetTime=function() error("diagnostics must not query native time") end
scan.ScanDiagnostics();scan.ScanDiagnostics()
GetTime=diagGetTime
eq(tooltipReads,diagReads,"reading diagnostics never reads native tooltip")
eq(probes,diagProbes,"reading diagnostics never probes minimap")
eq(enables,diagEnables,"reading diagnostics never enables soft cursor")
eq(releases,diagReleases,"reading diagnostics never restores or mutates cursor")
diagnostic.state="caller change";diagnostic.sampleCount=-1
diagnostic.rawKnownNames[1]="caller raw";diagnostic.acceptedNames[1]="caller accepted"
diagnostic.rejectedKnownNames[1]="caller rejected"
local fresh=scan.ScanDiagnostics()
eq(fresh.state,"ready","caller cannot overwrite diagnostic state")
eq(fresh.sampleCount,probes-before,"caller cannot overwrite sample count")
eq(fresh.rawKnownNames[1],"铜矿","raw diagnostic array is a copy")
eq(fresh.acceptedNames[1],"铜矿","accepted diagnostic array is a copy")
eq(#fresh.rejectedKnownNames,0,"rejected diagnostic array is a copy")
for key in pairs(fresh) do
    assert(key=="state" or key=="reason" or key=="sampleCount" or key=="completedAt"
        or key=="rawKnownNames" or key=="acceptedNames" or key=="rejectedKnownNames" or key=="method","unexpected diagnostic field")
end

nodes={};stickyText="铜矿\n玩家姓名\n任务正文";scan.Reset();result=runNames()
diagnostic=scan.ScanDiagnostics()
eq(#result,0,"full-map stale name remains rejected with diagnostics enabled")
eq(#diagnostic.rawKnownNames,1,"full-map raw name remains visible for diagnosis")
eq(diagnostic.rawKnownNames[1],"铜矿","full-map raw known name recorded")
eq(#diagnostic.acceptedNames,0,"full-map old name cannot become accepted")
eq(diagnostic.rejectedKnownNames[1],"铜矿","full-map rejection recorded by existing filter")
local lastCompleted=diagnostic.completedAt
stickyText=nil;scan.Reset();now=now+.1
eq(scan.ScanNames(),nil,"partial empty pass remains incomplete")
diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"scanning","current scanning state tracked separately")
eq(diagnostic.completedAt,lastCompleted,"partial pass does not replace last complete time")
eq(diagnostic.rawKnownNames[1],"铜矿","partial pass preserves previous completed evidence")
result=runNames();diagnostic=scan.ScanDiagnostics()
eq(#result,0,"completed empty read remains empty")
eq(#diagnostic.rawKnownNames,0,"completed empty read has no raw known names")
eq(#diagnostic.acceptedNames,0,"completed empty read has no accepted names")
eq(#diagnostic.rejectedKnownNames,0,"completed empty read has no rejected names")
eq(diagnostic.completedAt,now,"empty completion updates evidence timestamp")

nodes={{name="铜矿",dx=0,dy=0,radius=.55},{name="铜矿",dx=.85,dy=0,radius=.1}}
scan.Reset();result=runNames();diagnostic=scan.ScanDiagnostics()
eq(#result,1,"valid same-name component acceptance unchanged")
eq(diagnostic.acceptedNames[1],"铜矿","partially valid name counted as accepted")
eq(#diagnostic.rejectedKnownNames,0,"valid component prevents whole-name rejection")
local completedBeforePause=diagnostic.completedAt
IsMouseButtonDown=function(button) return button=="RightButton" end
now=now+.1;scan.ScanNames();diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"paused-input","held mouse diagnostic state")
eq(diagnostic.reason,"mouse-button","held mouse diagnostic reason")
eq(diagnostic.completedAt,completedBeforePause,"pause keeps last completed evidence")
IsMouseButtonDown=nil
IsMouselooking=function() return true end
now=now+.1;scan.ScanNames();diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"paused-input","mouselook diagnostic state")
eq(diagnostic.reason,"mouselook","mouselook diagnostic reason")
IsMouselooking=nil
Minimap=nil;scan.ScanNames();diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"unsupported","missing native API diagnostic")
eq(diagnostic.reason,"native-api","unsupported reason is specific")
eq(diagnostic.completedAt,completedBeforePause,"unsupported state keeps completed evidence")
Minimap=map
getterError=true;now=now+.1;scan.ScanNames();diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"native-error","tooltip native failure diagnostic")
eq(diagnostic.reason,"sampling-failed","sampling error does not guess an API result")
eq(diagnostic.completedAt,completedBeforePause,"failed pass cannot replace completed evidence")
getterError=false;now=now+.1;scan.ScanNames();diagnostic=scan.ScanDiagnostics()
eq(diagnostic.state,"cooldown","error cooldown diagnostic")
eq(diagnostic.reason,"previous-native-error","cooldown reason reports known prior failure")
now=now+11;scan.Reset()

-- Restricted tooltip containers cannot masquerade as a complete empty pass.
-- No extra native reads are made, and the last completed evidence stays intact.
do
    local nativeRead, previousSecret = tooltip.GetMinimapMouseover, issecretvalue
    local secretReads = 0
    local restricted = setmetatable({}, {__index=function()
        secretReads=secretReads+1;error("restricted field accessed")
    end})
    issecretvalue=function(value) return value==restricted end
    nodes={{name="铜矿",dx=.5,dy=0,radius=.12}}
    scan.Reset();result=runNames()
    local completedEvidence=scan.ScanDiagnostics()
    local cases={
        {restricted,"tooltip-data-unavailable","restricted data"},
        {42,"tooltip-data-unavailable","malformed data"},
        {{lines=restricted},"tooltip-lines-unavailable","restricted lines"},
        {{},"tooltip-lines-unavailable","missing lines"},
        {{lines=false},"tooltip-lines-unavailable","malformed lines"},
        {{lines={restricted}},"tooltip-line-unavailable","restricted line"},
        {{lines={42}},"tooltip-line-unavailable","malformed line"},
        {{lines={{leftText=restricted}}},"tooltip-text-unavailable","restricted text"},
        {{lines={{leftText=42}}},"tooltip-text-unavailable","malformed text"},
        {{lines={{leftText="铜矿"},restricted}},"tooltip-line-unavailable","good text before restricted line"},
        {setmetatable({}, {__index=function() error("unreadable lines") end}),"tooltip-read-error","throwing data field"},
        {{lines={setmetatable({}, {__index=function() error("unreadable text") end})}},"tooltip-read-error","throwing line field"},
    }
    for _,case in ipairs(cases) do
        tooltip.GetMinimapMouseover=function() tooltipReads=tooltipReads+1;return case[1] end
        local readsBefore,probesBefore,releasesBefore=tooltipReads,probes,releases
        scan.Reset();now=now+.1
        eq(scan.ScanNames(),nil,case[3].." does not publish an empty pass")
        local observed=scan.ScanDiagnostics()
        eq(observed.state,"unavailable",case[3].." diagnostic state")
        eq(observed.reason,case[2],case[3].." diagnostic reason")
        eq(observed.completedAt,completedEvidence.completedAt,case[3].." cannot refresh completion time")
        eq(observed.rawKnownNames[1],"铜矿",case[3].." preserves previous raw evidence")
        eq(observed.acceptedNames[1],"铜矿",case[3].." preserves previous acceptance evidence")
        eq(observed.sampleCount,completedEvidence.sampleCount,case[3].." cannot replace completed sample count")
        eq(tooltipReads,readsBefore+1,case[3].." stops at one native read")
        eq(probes,probesBefore+1,case[3].." stops at one sampled point")
        eq(releases,releasesBefore+1,case[3].." releases soft cursor")
        eq(map.soft,false,case[3].." leaves native soft cursor released")
    end
    eq(secretReads,0,"restricted containers are never indexed")

    -- Discard earlier good samples too; the next pass starts fresh without a
    -- native-error cooldown, and public nil remains the native no-hit result.
    tooltip.GetMinimapMouseover=nativeRead
    nodes={{name="铜矿",dx=0,dy=0,radius=.12}}
    scan.Reset();now=now+.1;eq(scan.ScanNames(),nil,"start good partial pass before unavailable data")
    tooltip.GetMinimapMouseover=function() return {lines=restricted} end
    now=now+.1;eq(scan.ScanNames(),nil,"unavailable later batch discards good earlier samples")
    tooltip.GetMinimapMouseover=nativeRead
    nodes={{name="锡矿",dx=.5,dy=0,radius=.12}}
    result=runNames()
    eq(#result,1,"recovery after unavailable data starts a new pass")
    eq(result[1].name,"锡矿","unavailable partial pass cannot leak old copper")
    tooltip.GetMinimapMouseover=function() tooltipReads=tooltipReads+1;return nil end
    scan.Reset();result=runNames()
    eq(#result,0,"public nil tooltip remains a valid completed no-hit pass")
    eq(scan.ScanDiagnostics().state,"ready","public nil is not classified as restricted")
    tooltip.GetMinimapMouseover=function() return {lines={{},{leftText=""}}} end
    scan.Reset();result=runNames()
    eq(#result,0,"public spacer and empty text lines remain valid")
    tooltip.GetMinimapMouseover=function() return restricted end
    now=now+.1
    eq(scan.Scan(),nil,"legacy scan also rejects restricted container")
    eq(scan.ScanDiagnostics().state,"unavailable","legacy failure shares unavailable diagnostic")
    tooltip.GetMinimapMouseover=nativeRead;issecretvalue=previousSecret
end

-- Real mouse focus on minimap descendants is respected even beyond the map
-- rectangle. Only ancestry is read: no frame input or visual settings change.
do
    local oldFoci,previousSecret=GetMouseFoci,issecretvalue
    local focusList
    GetMouseFoci=function() return focusList end
    local parentCalls=0
    local function child(parent)
        return {GetParent=function() parentCalls=parentCalls+1;return parent end,
            SetMouseClickEnabled=forbidden,SetMouseMotionEnabled=forbidden,
            EnableMouse=forbidden,EnableMouseWheel=forbidden,SetAlpha=forbidden}
    end
    local root=child(nil)
    local outsideChild=child(child(map))
    local secretFocusReads=0
    local restricted=setmetatable({}, {__index=function()
        secretFocusReads=secretFocusReads+1;error("restricted focus accessed")
    end})
    issecretvalue=function(value) return value==restricted end
    local loopA,loopB={},{}
    loopA.GetParent=function() return loopB end
    loopB.GetParent=function() return loopA end
    local deep=root
    for _=1,22 do deep=child(deep) end
    local crowded={}
    for i=1,33 do crowded[i]=root end
    local cases={
        {{map},"cursor-over-map-child","direct minimap focus"},
        {{outsideChild},"cursor-over-map-child","outside descendant focus"},
        {{root,outsideChild},"cursor-over-map-child","later focused descendant"},
        {restricted,"focus-unavailable","restricted focus list"},
        {false,"focus-unavailable","malformed focus list"},
        {{restricted},"focus-unavailable","restricted focused frame"},
        {{child(restricted)},"focus-unavailable","restricted parent"},
        {{42},"focus-unavailable","malformed focused frame"},
        {{{GetParent=restricted}},"focus-unavailable","restricted parent method"},
        {{{}},"focus-unavailable","missing parent method"},
        {{loopA},"focus-cycle","cyclic parent chain"},
        {{deep},"focus-chain-limit","excessive parent depth"},
        {crowded,"focus-list-limit","excessive focus list"},
        {{setmetatable({}, {__index=function() error("blocked frame field") end})},"focus-api-error","throwing parent lookup"},
        {{{GetParent=function() error("blocked GetParent") end}},"focus-api-error","throwing parent call"},
        {setmetatable({}, {__index=function() error("blocked focus list") end}),"focus-api-error","throwing focus list lookup"},
    }
    cursorX,cursorY=-1000,-1000;hover=false
    for _,case in ipairs(cases) do
        focusList=case[1]
        local readsBefore,probesBefore,enablesBefore=tooltipReads,probes,enables
        scan.Reset();now=now+.1
        eq(scan.ScanNames(),nil,case[3].." pauses names-only scan")
        local observed=scan.ScanDiagnostics()
        eq(observed.state,"paused-input",case[3].." input state")
        eq(observed.reason,case[2],case[3].." input reason")
        eq(tooltipReads,readsBefore,case[3].." reads no tooltip")
        eq(probes,probesBefore,case[3].." performs no sampled hit test")
        eq(enables,enablesBefore,case[3].." does not enable native soft cursor")
    end
    eq(secretFocusReads,0,"restricted focused values are never indexed")
    focusList={deep};parentCalls=0;now=now+.1;scan.ScanNames()
    eq(parentCalls,20,"parent traversal has a fixed depth bound")
    GetMouseFoci=function() error("native focus query refused") end
    before=probes;now=now+.1
    eq(scan.ScanNames(),nil,"throwing optional focus API pauses safely")
    eq(scan.ScanDiagnostics().reason,"focus-api-error","native focus error is diagnosed")
    eq(probes,before,"native focus error does not sample")
    GetMouseFoci=function() return focusList end
    focusList={root};nodes={{name="铜矿",dx=0,dy=0,radius=.12}}
    scan.Reset();now=now+.1;eq(scan.ScanNames(),nil,"unrelated focus allows a partial scan")
    focusList={outsideChild};now=now+.1;eq(scan.ScanNames(),nil,"descendant hover discards partial pass")
    focusList={child(root)};nodes={{name="锡矿",dx=.5,dy=0,radius=.12}}
    result=runNames()
    eq(#result,1,"ordinary focus ancestry does not block sampling")
    eq(result[1].name,"锡矿","focus pause cannot leak partial old copper")
    focusList={};nodes={};scan.Reset();result=runNames()
    eq(#result,0,"empty public focus list allows sampling")
    focusList={outsideChild};before=probes;now=now+.1
    eq(scan.Scan(),nil,"legacy scan also respects descendant hover")
    eq(probes,before,"legacy descendant pause performs no native sample")
    GetMouseFoci=nil;scan.Reset();result=runNames()
    eq(#result,0,"missing optional focus API preserves old-client behavior")
    eq(forbiddenChanges,0,"focus and tooltip guards never change map or descendant settings")
    GetMouseFoci=oldFoci;issecretvalue=previousSecret
end
map.SetAlpha,map.SetScale,map.SetIconScale,map.AdjustPointsOffset=nil,nil,nil,nil
C_Minimap.SetTracking=nil;SetCursorPosition=nil
print("professions_gather_scan_test: "..checks.." checks passed")
