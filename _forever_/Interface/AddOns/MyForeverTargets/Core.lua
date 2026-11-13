local _, NS = ...
NS.VERSION = "0.1.45"
-- This client read back 512x256 after the requested native expansion. Keep the
-- incompatible trial unavailable until a separately verified implementation.
NS.NativeTrialUnavailable = "native_size_clamped_512x256"
-- User-owned @mouseover macros run on their original action buttons. This is
-- a startup policy: changing it requires a full UI reload, not a hot switch.
NS.NativeMacroOnly = true
-- Explicit user authorization: all target tiles may use the old out-of-combat
-- name bridge for ordinary spells. Existing user macros remain untouched.
NS.LegacyNameBridge = true
-- Legacy combat/GUID controllers stay disabled. The separately authorized
-- out-of-combat bridge restores the pre-cast target after a temporary switch.
NS.PreserveCastTarget = true
NS.Nameplates = {}

function NS.Public(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if not ok or secret then return false end
    end
    return true
end

function NS.Number(value)
    return NS.Public(value) and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function NS.Read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    if not NS.Public(a) then a = nil end
    if not NS.Public(b) then b = nil end
    if not NS.Public(c) then c = nil end
    if not NS.Public(d) then d = nil end
    return a, b, c, d
end

function NS.InCombat()
    return NS.Read(InCombatLockdown) == true
end

function NS.Text(value)
    if not NS.Public(value) or type(value) ~= "string" then return "" end
    return value:gsub("|", ""):gsub("[%z\1-\31\127]", "")
end

local anchors = {CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,
    TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
local function position(old, x, defaults)
    old = type(old) == "table" and old or {}
    defaults=defaults or {point="CENTER",relativePoint="CENTER",x=x,y=160}
    return {point=anchors[old.point] and old.point or defaults.point,
        relativePoint=anchors[old.relativePoint] and old.relativePoint or defaults.relativePoint,
        x=NS.Number(old.x) and math.max(-3000,math.min(3000,old.x)) or defaults.x,
        y=NS.Number(old.y) and math.max(-2000,math.min(2000,old.y)) or defaults.y,
        manual=NS.Public(old.manual) and old.manual==true}
end

-- Leave room for the unscaled 42px launcher even at the 0.7 panel scale.
local friendlyDefault={point="LEFT",relativePoint="LEFT",x=120,y=80}

function NS.NormalizeDB(value)
    local old = type(value) == "table" and value or {}
    local function panelShown(key)
        if NS.Public(old[key]) and type(old[key])=="boolean" then return old[key] end
        return old.shown~=false
    end
    local friendlyShown,enemyShown=panelShown("friendlyShown"),panelShown("enemyShown")
    local launcherPosition=position(old.launcherPosition,0)
    local oldLauncherDefault=not launcherPosition.manual and launcherPosition.point=="TOPRIGHT"
        and launcherPosition.relativePoint=="TOPRIGHT" and launcherPosition.x==-280 and launcherPosition.y==-60
    if type(old.launcherPosition)~="table" or oldLauncherDefault then
        launcherPosition={point="LEFT",relativePoint="LEFT",x=24,y=0,manual=false}
    end
    local friendlyPosition=position(old.friendlyPosition,120,friendlyDefault)
    -- Migrate only the previous untouched default. A saved drag remains the
    -- player's placement, even when it overlaps action bars at a new ratio.
    if not friendlyPosition.manual and friendlyPosition.point=="CENTER"
        and friendlyPosition.relativePoint=="CENTER" and friendlyPosition.x==-225 and friendlyPosition.y==160 then
        friendlyPosition=position(nil,120,friendlyDefault)
    end
    local tabs, limits = {raid=true,party=true,nearby=true}, {[5]=true,[10]=true,[20]=true}
    local backup
    local plateBackup={}
    if type(old.nameplateBackup)=="table" then
        for _,name in ipairs({"nameplateShowFriendlyPlayers","nameplateShowFriends","nameplateShowEnemies","nameplateShowAll"}) do
            local saved=old.nameplateBackup[name]
            if saved=="0" or saved=="1" then plateBackup[name]=saved end
        end
    end
    if type(old.mouseoverBackup)=="table" then
        local saved=old.mouseoverBackup
        backup={enabled=type(saved.enabled)=="string" and saved.enabled or nil,modifiers={},pendingSaves={}}
        if saved.autoSelfCast=="0" or saved.autoSelfCast=="1" then backup.autoSelfCast=saved.autoSelfCast end
        for i=1,2 do
            if type(saved.modifiers)=="table" and type(saved.modifiers[i])=="string" then backup.modifiers[i]=saved.modifiers[i] end
            if type(saved.pendingSaves)=="table" and saved.pendingSaves[i]==true then backup.pendingSaves[i]=true end
        end
        if type(saved.key)=="string" and (saved.bindingSet==1 or saved.bindingSet==2) then
            backup.key,backup.bindingSet=saved.key,saved.bindingSet
            if not backup.modifiers[saved.bindingSet] then backup.modifiers[saved.bindingSet]=saved.key end
        end
    end
    return {version=1, friendlyTab=tabs[old.friendlyTab] and old.friendlyTab or "raid",
        nearbyLimit=limits[old.nearbyLimit] and old.nearbyLimit or 20,
        enemyLimit=limits[old.enemyLimit] and old.enemyLimit or 20,
        shown=friendlyShown or enemyShown, friendlyShown=friendlyShown,enemyShown=enemyShown,
        launcherPosition=launcherPosition, locked=old.locked == true,
        scale=NS.Number(old.scale) and math.max(0.7,math.min(1.4,old.scale)) or 1,
        friendlyPosition=friendlyPosition,
        enemyPosition=position(old.enemyPosition,225),
        mouseoverRequested=old.mouseoverRequested ~= false,
        legacyNameBridgeEnabled=old.legacyNameBridgeEnabled ~= false,
        detectionRequested=old.detectionRequested~=false,nameplateBackup=plateBackup,
        mouseoverBackup=backup}
end

function NS.IsPanelShown(side)
    return (side=="friendly" or side=="enemy") and NS.DB~=nil
        and NS.DB.shown~=false and NS.DB[side.."Shown"]~=false
end

function NS.Initialize(value)
    NS.DB = NS.NormalizeDB(value)
    return NS.DB
end

function NS.Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff80c9ef目标选择|r " .. tostring(message))
    end
end

function NS.ValidToken(unit)
    if not NS.Public(unit) or type(unit) ~= "string" then return false end
    if unit == "player" or unit == "target" or unit == "focus"
        or unit == "targettarget" or unit == "focustarget" then return true end
    local number = tonumber(unit:match("^party(%d+)$"))
    if number then return number >= 1 and number <= 4 end
    number = tonumber(unit:match("^raid(%d+)$"))
    if number then return number >= 1 and number <= 40 end
    number = tonumber(unit:match("^party(%d+)target$"))
    if number then return number >= 1 and number <= 4 end
    number = tonumber(unit:match("^raid(%d+)target$"))
    if number then return number >= 1 and number <= 40 end
    number = tonumber(unit:match("^boss(%d+)$"))
    if number then return number >= 1 and number <= 8 end
    number = tonumber(unit:match("^arena(%d+)$"))
    if number then return number >= 1 and number <= 5 end
    number = tonumber(unit:match("^nameplate(%d+)$"))
    return number ~= nil and number >= 1 and number <= 1000
end
