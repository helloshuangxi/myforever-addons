-- Exercise the installed Details hover handler with minimal frame mocks.
-- Lua 5.1 cannot reproduce Blizzard's secret-value runtime. The sentinel below
-- only verifies that the handler checks secrecy before using optional UI data.
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end

local path = "_forever_/Interface/AddOns/Details/frames/window_main.lua"
local sourceFile = assert(io.open(path, "rb"))
local source = sourceFile:read("*a"):gsub("\r\n", "\n")
sourceFile:close()
local start = assert(source:find("local lineScript_Onenter = function(self)", 1, true))
local finish = assert(source:find("local lineScript_Onleave = function(self)", start, true))
local handlerSource = source:sub(start, finish - 1) .. "\nreturn lineScript_Onenter"

local secret = setmetatable({}, {
    __add = function() error("secret width reached arithmetic") end,
})

local function run(options)
    options = options or {}
    local state = { shown = 0, truncationReads = 0, nativeColorCopies = 0, parsedColorCopies = 0 }
    local font = {}
    function font:SetText(text) state.text = text end
    function font:SetTextColor(...) state.nativeColorCopies = state.nativeColorCopies + 1; state.color = {...} end
    function font:GetStringWidth() return options.secretWidth and secret or 120 end
    local overlay = { text = font }
    function overlay:SetPoint(...) state.anchor = {...} end
    function overlay:SetSize(width, height) state.width, state.height = width, height end
    function overlay:Show() state.shown = state.shown + 1 end
    function overlay:Hide() state.hidden = true end

    local details = { left_anti_truncate = overlay }
    function details:SetFontSize(_, value) state.fontSize = value end
    function details:SetFontFace(_, value) state.fontFace = value end
    function details:SetFontColor(target, ...)
        state.parsedColorCopies = state.parsedColorCopies + 1
        for i = 1, select("#", ...) do
            assert(select(i, ...) ~= secret, "secret color reached Details color parser")
        end
        target:SetTextColor(...)
    end

    local lefttext = {}
    if not options.legacy then
        function lefttext:HasAnySecretAspect() return options.secretAspect or false end
    end
    function lefttext:IsTruncated()
        state.truncationReads = state.truncationReads + 1
        return options.truncated
    end
    function lefttext:GetText() return "An ordinary long player name" end
    function lefttext:GetTextColor()
        if options.secretColor then return secret, secret, secret, secret end
        return 0.2, 0.4, 0.6, 1
    end
    local icon = {}
    function icon:GetTexture() return "class-icon" end
    function icon:GetTexCoord() return 0, 1, 0, 1 end
    function icon:GetVertexColor() return 1, 1, 1, 1 end
    local highlight = {}
    function highlight:SetTexture(value) state.iconTexture = value end
    function highlight:SetTexCoord(...) state.iconCoordinates = {...} end
    function highlight:SetVertexColor(...) state.iconColor = {...} end
    function highlight:SetBlendMode(value) state.iconBlend = value end
    function highlight:SetAlpha(value) state.iconAlpha = value end
    function highlight:Show() state.iconShown = true end
    local row = {
        lineText1 = lefttext,
        row_id = 1,
        _instance = { row_info = { font_size = 12, font_face_file = "font.ttf", height = 20 } },
        textura = { SetBlendMode = function(_, value) state.barBlend = value end },
        iconHighlight = highlight,
    }
    function row._instance:MontaTooltip() state.tooltip = true end
    function row:SetBackdrop(value) state.backdrop = value end
    function row:SetBackdropColor(...) state.backdropColor = {...} end
    function row:SetScript(name, callback) state.scriptName, state.script = name, callback end
    function row:GetClassIcon() return icon end

    local shiftMonitor = function() end
    local environment = setmetatable({
        Details = details,
        detailsFramework = { IsAddonApocalypseWow = function() return not options.legacy end },
        OnEnterMainWindow = function() state.windowEntered = true end,
        barra_backdrop_onenter = {},
        shiftMonitor = shiftMonitor,
    }, { __index = _G })
    if not options.legacy then
        environment.issecretvalue = function(value) return value == secret end
    end
    local chunk = assert(loadstring(handlerSource, "@" .. path .. ":hover-test"))
    setfenv(chunk, environment)
    chunk()(row)
    check(row.mouse_over and state.windowEntered and state.tooltip, "normal hover and tooltip still run")
    check(state.scriptName == "OnUpdate" and state.script == shiftMonitor, "hover installs its modifier monitor")
    check(state.iconShown and state.iconTexture == "class-icon" and state.iconAlpha == 0.3,
        "hover continues to the class-icon highlight")
    return state, lefttext
end

local state, text = run({ truncated = true })
check(state.shown == 1 and text.untruncated == true, "ordinary truncated text expands")
check(state.width == 123 and state.height == 20 and state.text == "An ordinary long player name",
    "ordinary expansion preserves full text and measured size")
check(state.color[1] == 0.2 and state.color[2] == 0.4 and state.color[3] == 0.6 and state.color[4] == 1,
    "ordinary expansion preserves font color")

state, text = run({ truncated = false })
check(state.shown == 0 and not text.untruncated, "ordinary untruncated text needs no expansion")

state, text = run({ truncated = secret, secretAspect = false })
check(state.shown == 0 and not text.untruncated,
    "secret IsTruncated result skips optional overflow even without a secret object aspect")

state, text = run({ truncated = true, secretAspect = true })
check(state.truncationReads == 0 and state.shown == 0 and not text.untruncated,
    "known secret aspect skips optional truncation work")

state, text = run({ truncated = true, secretAspect = secret })
check(state.truncationReads == 0 and state.shown == 0 and not text.untruncated,
    "secret aspect-query result skips optional truncation work")

state, text = run({ truncated = true, secretWidth = true })
check(state.shown == 0 and state.width == nil and not text.untruncated,
    "secret measured width never reaches arithmetic or shows the overflow")

state = run({ truncated = true, secretColor = true })
check(state.shown == 1 and state.nativeColorCopies == 1 and state.parsedColorCopies == 0,
    "native color components pass directly to the native FontString setter")
check(state.color[1] == secret and state.color[4] == secret, "native color forwarding preserves opaque components")

state, text = run({ truncated = true, legacy = true })
check(state.shown == 1 and text.untruncated and state.width == 123,
    "legacy runtime without secret APIs retains ordinary expansion")
state, text = run({ truncated = false, legacy = true })
check(state.shown == 0 and not text.untruncated, "legacy ordinary nontruncated text remains unchanged")

print("details_truncation_test: " .. checks .. " flow checks passed (secret sentinel, not Blizzard runtime)")
