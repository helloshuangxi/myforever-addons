-- Draw the mocked frame tree as absolutely positioned HTML.
local M = {}

local function rgba(c, alpha)
    c = c or { 1, 1, 1, 1 }
    local function ch(v) return math.floor(math.max(0, math.min(1, v or 0)) * 255 + 0.5) end
    return string.format("rgba(%d,%d,%d,%.3f)", ch(c[1]), ch(c[2]), ch(c[3]), math.max(0, math.min(1, (c[4] or 1) * (alpha or 1))))
end
local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

local function richText(text)
    text = tostring(text or ""):gsub("||", "\1")
    local out, open = {}, 0
    local i, n = 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == "|" then
            local code = text:sub(i + 1, i + 1)
            if code == "c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then
                out[#out + 1] = '<span style="color:#' .. text:sub(i + 4, i + 9) .. '">'; open = open + 1; i = i + 10
            elseif code == "r" then
                if open > 0 then out[#out + 1] = "</span>"; open = open - 1 end
                i = i + 2
            elseif code == "n" then out[#out + 1] = "<br>"; i = i + 2
            elseif code == "T" or code == "A" then
                local stop = text:find(code == "T" and "|t" or "|a", i + 2, true)
                out[#out + 1] = '<i class="ic"></i>'; i = (stop or n) + 2
            elseif code == "H" then
                local stop = text:find("|h", i + 2, true); i = (stop or n) + 2
            elseif code == "h" then i = i + 2
            else out[#out + 1] = "|"; i = i + 1 end
        elseif c == "\n" then out[#out + 1] = "<br>"; i = i + 1
        else
            local j = text:find("[|\n]", i) or (n + 1)
            out[#out + 1] = esc(text:sub(i, j - 1)); i = j
        end
    end
    for _ = 1, open do out[#out + 1] = "</span>" end
    return (table.concat(out):gsub("\1", "|"))
end

function M.collect(W)
    local items, H = {}, W.screen.height
    local function visit(f, clip, alpha, strata, level)
        if not f.shown then return end
        alpha = alpha * (f.alpha or 1)
        strata = f.strata or strata
        level = f.level or (level + 1)
        local r = f.isScreen and { l = 0, b = 0, r = f.width, t = f.height } or W.rect(f)
        if r and not f.isScreen then
            items[#items + 1] = { f = f, r = r, clip = clip, alpha = alpha, strata = W.STRATA[strata] or 3, level = level, seq = f.seq }
        end
        local childClip = clip
        if r and (f.kind == "ScrollFrame" or f.clips) and not f.isScreen then
            childClip = clip and { l = math.max(clip.l, r.l), r = math.min(clip.r, r.r), b = math.max(clip.b, r.b), t = math.min(clip.t, r.t) } or r
        end
        for _, child in ipairs(f.children) do visit(child, childClip, alpha, strata, level) end
    end
    visit(W.screen, nil, 1, "MEDIUM", 0)
    table.sort(items, function(a, b)
        if a.strata ~= b.strata then return a.strata < b.strata end
        if a.level ~= b.level then return a.level < b.level end
        return a.seq < b.seq
    end)
    return items, H
end

local function box(r, clip, H, style, inner, class)
    local l, t, w, h = r.l, H - r.t, r.r - r.l, r.t - r.b
    if w <= 0 and h <= 0 then return "" end
    local clipCss = ""
    if clip then
        local ci = { math.max(0, r.t - clip.t), math.max(0, r.r - clip.r), math.max(0, clip.b - r.b), math.max(0, clip.l - r.l) }
        if ci[1] >= h and h > 0 or ci[3] >= h and h > 0 or ci[2] >= w and w > 0 or ci[4] >= w and w > 0 then return "" end
        if ci[1] > 0 or ci[2] > 0 or ci[3] > 0 or ci[4] > 0 then
            clipCss = string.format("clip-path:inset(%.1fpx %.1fpx %.1fpx %.1fpx);", ci[1], ci[2], ci[3], ci[4])
        end
    end
    return string.format('<div class="%s" style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;%s%s">%s</div>\n',
        class or "b", l, t, w, h, clipCss, style or "", inner or "")
end

local function fontStyle(W, s, es, alpha)
    local size = (s.fontSize or 14) * es
    local jh = ({ LEFT = "left", RIGHT = "right", CENTER = "center" })[s.justifyH or "CENTER"] or "center"
    local jv = ({ TOP = "flex-start", BOTTOM = "flex-end", MIDDLE = "center" })[s.justifyV or "MIDDLE"] or "center"
    local wrap = s.wordWrap == false and "white-space:nowrap;" or ""
    local weight = (s.fontFlags and tostring(s.fontFlags):find("OUTLINE")) and "text-shadow:0 0 2px #000,0 0 2px #000;" or ""
    return string.format("font-size:%.1fpx;line-height:%.2f;color:%s;text-align:%s;align-items:%s;%s%s",
        size, 1.3 + (s.spacing or 0) / (s.fontSize or 14), rgba(s.textColor, alpha), jh, jv, wrap, weight), jh
end

function M.html(W, options)
    options = options or {}
    local items, H = M.collect(W)
    local out = {}
    for _, item in ipairs(items) do
        local f, r, clip, alpha = item.f, item.r, item.clip, item.alpha
        local es = W.effScale(f)
        -- shell
        if f.look == "blizzFrame" then
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha, '<div class="bft"></div>', "b blizzFrame")
        elseif f.look == "blizzButton" then
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha * (f.enabled and 1 or 0.5), "", "b blizzButton")
        elseif f.look == "blizzClose" then
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha, "×", "b blizzClose")
        elseif f.look == "blizzInput" then
            out[#out + 1] = box({ l = r.l - 5 * es, r = r.r, t = r.t, b = r.b }, clip, H, "opacity:" .. alpha, "", "b blizzInput")
        elseif f.look == "blizzScrollBar" then
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha, '<i></i>', "b blizzScroll")
        elseif f.look == "blizzCheck" then
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha, f.checked and "✓" or "", "b blizzCheck")
        elseif f.look == "blizzSlider" then
            local lo, hi = f.min or 0, f.max or 1
            local pct = hi > lo and ((f.value or lo) - lo) / (hi - lo) * 100 or 0
            out[#out + 1] = box(r, clip, H, "opacity:" .. alpha, string.format('<i style="left:%.1f%%"></i>', pct), "b blizzSlider")
        end
        if f.backdrop and (f.backdrop.bgFile or f.backdrop.edgeFile) then
            local style = {}
            if f.backdrop.bgFile then style[#style + 1] = "background:" .. rgba(f.backdropColor, alpha) .. ";" end
            if f.backdrop.edgeFile then
                local tooltipEdge = tostring(f.backdrop.edgeFile):find("Tooltip") ~= nil
                local size = tooltipEdge and math.max(1.5, 2 * es) or math.max(1, (f.backdrop.edgeSize or 1) * es)
                style[#style + 1] = string.format("box-shadow:inset 0 0 0 %.1fpx %s;", size, rgba(f.backdropBorderColor, alpha))
                if tooltipEdge then style[#style + 1] = string.format("border-radius:%.1fpx;", 5 * es) end
            end
            out[#out + 1] = box(r, clip, H, table.concat(style))
        end
        -- regions
        local regions = {}
        for _, g in ipairs(f.regions) do regions[#regions + 1] = g end
        table.sort(regions, function(a, b)
            local la, lb = W.LAYER[a.layer] or 3, W.LAYER[b.layer] or 3
            if la ~= lb then return la < lb end
            if (a.sub or 0) ~= (b.sub or 0) then return (a.sub or 0) < (b.sub or 0) end
            if a.kind ~= b.kind then return a.kind == "Texture" end
            return a.seq < b.seq
        end)
        for _, g in ipairs(regions) do
            if g.shown and g.layer ~= "HIGHLIGHT" and g ~= f.pushedTexture and g ~= f.disabledTexture and g ~= f.checkedTexture then
                local ga = alpha * (g.alpha or 1)
                if g.kind == "Texture" then
                    local gr
                    if g.isBarFill then
                        local lo, hi = f.min or 0, f.max or 1
                        local fraction = hi > lo and math.max(0, math.min(1, ((f.value or lo) - lo) / (hi - lo))) or 0
                        gr = { l = r.l, r = r.l + (r.r - r.l) * fraction, t = r.t, b = r.b }
                    elseif g.isThumb then
                        local lo, hi = f.min or 0, f.max or 1
                        local fraction = hi > lo and math.max(0, math.min(1, ((f.value or lo) - lo) / (hi - lo))) or 0
                        local tw, th = (g.width or 8) * es, (g.height or 16) * es
                        if (f.orientation or "HORIZONTAL") == "VERTICAL" then
                            local top = r.t - (r.t - r.b - th) * fraction
                            gr = { l = (r.l + r.r) / 2 - tw / 2, r = (r.l + r.r) / 2 + tw / 2, t = top, b = top - th }
                        else
                            local left = r.l + (r.r - r.l - tw) * fraction
                            gr = { l = left, r = left + tw, t = (r.t + r.b) / 2 + th / 2, b = (r.t + r.b) / 2 - th / 2 }
                        end
                    else gr = W.rect(g) end
                    if gr then
                        local style
                        local white = g.file and tostring(g.file):upper():find("WHITE8X8")
                        local circle = g.file and tostring(g.file):find("TempPortraitAlphaMask", 1, true)
                        if circle then
                            -- Quarter (or whole) circle cut from the round portrait mask.
                            local tc = g.texCoord or { 0, 1, 0, 1 }
                            local corner = (tc[2] - tc[1] >= 0.99) and "border-radius:50%;"
                                or string.format("border-%s-%s-radius:100%%;", tc[3] < 0.25 and "top" or "bottom", tc[1] < 0.25 and "left" or "right")
                            style = "background:" .. rgba(g.vertex, ga) .. ";" .. corner
                        elseif g.color then style = "background:" .. rgba(g.color, ga) .. ";"
                        elseif g.isBarFill then style = "background:" .. rgba(f.barColor or g.vertex, ga) .. ";"
                        elseif white or (g.isThumb and not g.file) then style = "background:" .. rgba(g.vertex, ga) .. ";"
                        elseif g.file then
                            local tint = g.vertex and rgba({ g.vertex[1], g.vertex[2], g.vertex[3], 0.55 * (g.vertex[4] or 1) }, ga) or "rgba(150,150,150,0.35)"
                            style = "background:repeating-linear-gradient(45deg," .. tint .. " 0 3px,rgba(0,0,0,0.25) 3px 6px);outline:1px solid rgba(255,255,255,0.18);outline-offset:-1px;opacity:" .. ga .. ";"
                        end
                        if style then
                            if g.rotation then style = style .. string.format("transform:rotate(%.3frad);", -g.rotation) end
                            out[#out + 1] = box(gr, clip, H, style)
                        end
                    end
                else
                    local gr = W.rect(g)
                    if gr and (g.text or "") ~= "" then
                        local style = fontStyle(W, g, es, ga)
                        local free = not (g.width and g.width > 0) and #g.points < 2
                        if free then style = style .. "white-space:nowrap;overflow:visible;" end
                        out[#out + 1] = box(gr, clip, H, style, '<span>' .. richText(g.text) .. '</span>', "b t")
                    end
                end
            end
        end
        if f.kind == "EditBox" and (f.text or "") ~= "" then
            local style = fontStyle(W, { fontSize = f.fontSize, textColor = f.textColor, justifyH = "LEFT", justifyV = f.multiLine and "TOP" or "MIDDLE", wordWrap = f.multiLine and true or false }, es, alpha)
            out[#out + 1] = box(r, clip, H, style .. "overflow:hidden;", '<span>' .. richText(f.text) .. '</span>', "b t")
        end
    end
    return table.concat(out), items
end

function M.bounds(W, frame)
    local r = W.rect(frame)
    if not r then return nil end
    return { x = r.l, y = W.screen.height - r.t, w = r.r - r.l, h = r.t - r.b }
end

local CSS = [[
*{box-sizing:border-box}body{margin:0;background:#0b0c0e;font-family:"Noto Sans CJK SC","Noto Sans SC",sans-serif}
.stage{position:relative;overflow:hidden;background:
 linear-gradient(180deg,rgba(74,104,128,.0) 0%,rgba(20,26,22,.55) 100%),
 radial-gradient(120% 80% at 70% 0%,#8fa9b8 0%,#5f7f8c 38%,#3f5a4c 62%,#2c3a2c 100%)}
.stage:before{content:"";position:absolute;inset:auto 0 0 0;height:46%;background:
 linear-gradient(170deg,transparent 0 22%,#3d5340 22% 100%),linear-gradient(190deg,transparent 0 38%,#34472f 38% 100%);opacity:.9}
.b{position:absolute;overflow:visible}
.t{display:flex;overflow:hidden}.t>span{width:100%}
.ic{display:inline-block;width:1em;height:1em;vertical-align:-0.12em;background:rgba(160,160,160,.45);outline:1px solid rgba(255,255,255,.2)}
.blizzFrame{background:linear-gradient(#2a2622,#1c1a18);box-shadow:inset 0 0 0 2px #6b6257,inset 0 0 0 3px #2a2521,0 0 0 1px #000;border-radius:4px}
.blizzFrame .bft{position:absolute;left:2px;right:2px;top:2px;height:21px;background:linear-gradient(#5a5148,#3b352f);border-bottom:1px solid #1a1714}
.blizzButton{background:linear-gradient(#7a1414,#4a0808);box-shadow:inset 0 0 0 1px #9c7a2e,inset 0 0 0 2px #2c0505;border-radius:3px}
.blizzClose{background:linear-gradient(#8a1c14,#571009);box-shadow:inset 0 0 0 2px #9c7a2e;border-radius:4px;color:#ffd24a;font-weight:700;display:flex;align-items:center;justify-content:center;font-size:20px;transform:scale(.72)}
.blizzInput{background:rgba(0,0,0,.6);box-shadow:inset 0 0 0 1px #7d7462;border-radius:3px}
.blizzScroll{background:rgba(0,0,0,.45);box-shadow:inset 0 0 0 1px #5f574b}.blizzScroll i{position:absolute;left:1px;right:1px;top:1px;height:24px;background:#8d7c56;border-radius:2px}
.blizzCheck{background:rgba(0,0,0,.55);box-shadow:inset 0 0 0 2px #8a7a55;border-radius:3px;color:#ffd24a;display:flex;align-items:center;justify-content:center;font-weight:700;transform:scale(.8)}
.blizzSlider{background:rgba(0,0,0,.55);box-shadow:inset 0 0 0 1px #7d7462;border-radius:8px}.blizzSlider i{position:absolute;top:-3px;width:12px;height:22px;margin-left:-6px;background:#c9b27a;border-radius:3px}
.cap{position:absolute;left:8px;bottom:6px;font-size:11px;color:rgba(255,255,255,.75);text-shadow:0 1px 2px #000}
]]
M.CSS = CSS

function M.page(W, caption)
    local body = M.html(W)
    return string.format('<!doctype html><meta charset="utf-8"><style>%s</style><div class="stage" style="width:%dpx;height:%dpx">%s<div class="cap">%s</div></div>',
        CSS, W.screen.width, W.screen.height, body, esc(caption or ""))
end

return M
