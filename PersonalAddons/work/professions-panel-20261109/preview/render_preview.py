#!/usr/bin/env python3
"""Run actual UI.lua in a read-only WoW-frame sandbox; export its layout to PNG.

This is a mock, never a game screenshot. It reads no SavedVariables or live state.
Only Pillow + the already installed Lupa are required. Output stays beside this file.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from functools import lru_cache
from pathlib import Path

from lupa.lua51 import LuaRuntime
try:
    from PIL import Image, ImageDraw, ImageFont
except ModuleNotFoundError:
    # Reuse an installed matching-ABI Pillow; do not mutate this project's venv.
    pillow_site = Path.home() / ".codex/skills/sprite-gen/.venv/lib/python3.12/site-packages"
    if sys.version_info[:2] != (3, 12) or not (pillow_site / "PIL").is_dir():
        raise
    sys.path.insert(0, str(pillow_site))
    from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / "_forever_/Interface/AddOns/MyForeverProfessions/UI.lua"
FONT_PATH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
TITLE = "模拟布局，非游戏截图"
LIMITS = [
    "真实 UI.lua 在 Lupa 中执行；虚构专业与物品样本，不读取角色数据。",
    "使用系统中文替代字体，WoW 字体、字距及 GetStringHeight 可能不同；需游戏内确认。",
    "仅记录 frame API 与锚点。背景为实参近似色块，图标与状态条纹理为占位，不仿造游戏截图。",
    "缩放为构造时 65/100/160%；不验证真实鼠标拖动、屏幕钳制、Esc、游戏滚动与渲染裁切。",
]


@lru_cache(maxsize=128)
def font(size: int):
    return ImageFont.truetype(FONT_PATH, max(1, size))


def plain(text):
    text = re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", text)
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text).replace("||", "|")


def colored_chars(text, base):
    text = re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", text)
    result, current, i = [], base, 0
    while i < len(text):
        color = re.match(r"\|c([0-9a-fA-F]{8})", text[i:])
        if color:
            value = color.group(1)
            current = tuple(int(value[k:k + 2], 16) / 255 for k in (2, 4, 6)) + (int(value[:2], 16) / 255,)
            i += 10
        elif text[i:i + 2] == "|r":
            current, i = base, i + 2
        elif text[i:i + 2] == "||":
            result.append(("|", current)); i += 2
        else:
            result.append((text[i], current)); i += 1
    return result


def wrap_chars(chars, width, size, wrap=True):
    lines, line, used = [], [], 0
    for char, color in chars:
        length = font(round(size)).getlength(char) if char != "\n" else 0
        if char == "\n":
            lines.append(line); line, used = [], 0
        else:
            if wrap and width > 0 and used + length > width + .01 and line:
                lines.append(line); line, used = [], 0
            line.append((char, color)); used += length
    lines.append(line)
    return lines


def text_height(text, width, size, spacing, wrap):
    if not text:
        return 0
    lines = wrap_chars([(c, None) for c in plain(text)], width, size, wrap)
    return len(lines) * size + max(0, len(lines) - 1) * spacing


def lua_array(value):
    return [value[i] for i in range(1, len(value) + 1)] if value else None


def capture(scale, scene, width, height, scroll_end=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    gl = lua.globals()
    gl.MOCK_WIDTH, gl.MOCK_HEIGHT = width, height
    gl.py_text_height = text_height
    gl.py_text_width = lambda t, s: max((font(round(s)).getlength(x) for x in plain(t).split("\n")), default=0)
    lua.execute((HERE / "wow_mock.lua").read_text())
    ns = gl.MockNamespace(scale, scene)
    source_bytes = SOURCE.read_bytes()
    loader = lua.eval("function(code,name,ns) assert(loadstring(code,name))('MyForeverProfessions', ns) end")
    loader(source_bytes.decode(), str(SOURCE), ns)
    panel = ns.CreateUI()
    chosen = {"crafting": 1, "long-alternative": 1, "gathering": 2, "unlearned": 3, "no-recipes": 4}[scene]
    card = panel.cards[chosen]
    card.header.scripts.OnClick()
    if scene == "long-alternative":
        card.choices[2].scripts.OnClick(card.choices[2])
    if scroll_end:
        panel.scrollbar.SetValue(panel.scrollbar, panel.scrollbar.max)
    # Semantic aliases are paths to real frame references, never inferred from text.
    aliases = {int(panel.id): "panel"}
    def alias_members(table, path):
        for key, value in table.items():
            if key in {"parent", "allPoints", "child", "points", "scripts"}:
                continue
            if hasattr(value, "items") and value["id"]:
                aliases[int(value.id)] = f"{path}.{key}"
                for sub in ("label", "rank", "toggle", "counts", "role", "stock", "icon", "fill", "rule", "bg", "marker"):
                    child = value[sub]
                    if child is not None and hasattr(child, "items") and child["id"]:
                        aliases[int(child.id)] = f"{path}.{key}.{sub}"
    alias_members(panel, "panel")
    alias_members(panel.controls, "panel.controls")
    for i in range(1, len(panel.cards) + 1):
        value = panel.cards[i]
        aliases[int(value.id)] = f"panel.cards.{i}"
        alias_members(value, f"panel.cards.{i}")
        for family in ("choices", "materialRows"):
            for j in range(1, len(value[family]) + 1):
                row = value[family][j]
                aliases[int(row.id)] = f"panel.cards.{i}.{family}.{j}"
                alias_members(row, f"panel.cards.{i}.{family}.{j}")
    frames = []
    for f in lua_array(gl.MOCK_FRAMES):
        d = {key: f[key] for key in ("id", "kind", "name", "template", "shown", "width", "height", "scale", "alpha", "scroll", "text", "fontSize", "fontPath", "justifyH", "justifyV", "spacing", "wordWrap", "texture", "layer", "sublayer", "clamped", "scrollChild") if isinstance(f[key], (str, int, float, bool))}
        d["parent"] = int(f.parent.id) if f.parent else None
        d["alias"] = aliases.get(int(f.id), f.name or f"frame.{int(f.id)}")
        for key in ("colorTexture", "textColor", "vertexColor", "backdropColor", "backdropBorderColor"):
            if f[key] is not None:
                d[key] = lua_array(f[key])
        if f.allPoints:
            d["allPoints"] = int(f.allPoints.id)
        d["points"] = [{"point": p.point, "relative": int(p.relative.id) if p.relative else None, "relativePoint": p.relativePoint, "x": p.x, "y": p.y} for p in lua_array(f.points)]
        frames.append(d)
    return {"title": TITLE, "scene": scene, "scroll_position": "bottom" if scroll_end else "top", "scale": scale, "viewport": [width, height], "source": str(SOURCE), "source_sha256": hashlib.sha256(source_bytes).hexdigest(), "limitations": LIMITS, "frames": frames}


FACTORS = {"TOPLEFT": (0, 0), "TOP": (.5, 0), "TOPRIGHT": (1, 0), "LEFT": (0, .5), "CENTER": (.5, .5), "RIGHT": (1, .5), "BOTTOMLEFT": (0, 1), "BOTTOM": (.5, 1), "BOTTOMRIGHT": (1, 1)}


class Layout:
    def __init__(self, data):
        self.data, self.frames, self.cache = data, {f["id"]: f for f in data["frames"]}, {}

    @lru_cache(None)
    def scale(self, fid):
        f = self.frames[fid]
        return f["scale"] * (self.scale(f["parent"]) if f["parent"] else 1)

    @lru_cache(None)
    def visible(self, fid):
        f = self.frames[fid]
        return f["shown"] and (not f["parent"] or self.visible(f["parent"]))

    def rect(self, fid):
        if fid in self.cache:
            return self.cache[fid]
        f, s = self.frames[fid], self.scale(fid)
        if not f["parent"]:
            box = (0, 0, f["width"] * s, f["height"] * s)
        elif f.get("allPoints"):
            box = self.rect(f["allPoints"])
        else:
            w, h = f["width"] * s, f["height"] * s
            if f["kind"] == "FontString":
                h = h or text_height(f.get("text", ""), f["width"], f["fontSize"], f["spacing"], f.get("wordWrap", True)) * s
                w = w or max((font(round(f["fontSize"])).getlength(x) for x in plain(f.get("text", "")).split("\n")), default=0) * s
            x, y = [], []
            for p in f["points"]:
                other = self.rect(p["relative"] or f["parent"])
                ax, ay = FACTORS[p["point"]]; bx, by = FACTORS[p["relativePoint"]]
                x.append((ax, other[0] + (other[2] - other[0]) * bx + p["x"] * s))
                y.append((ay, other[1] + (other[3] - other[1]) * by - p["y"] * s))
            def solve(values, dimension, fallback):
                for a, q in values:
                    for b, r in values:
                        if a != b:
                            dimension = (r - q) / (b - a)
                            return q - a * dimension, dimension
                return (values[0][1] - values[0][0] * dimension if values else fallback), dimension
            parent = self.rect(f["parent"])
            left, w = solve(x, w, parent[0]); top, h = solve(y, h, parent[1])
            if f.get("scrollChild"):
                top -= self.frames[f["parent"]]["scroll"] * s
            box = (left, top, left + w, top + h)
        self.cache[fid] = box
        return box

    def clip(self, fid):
        clip = (0, 0, *self.data["viewport"])
        f = self.frames[fid]
        while f["parent"]:
            f = self.frames[f["parent"]]
            if f["kind"] == "ScrollFrame":
                clip = intersect(clip, self.rect(f["id"]))
        return clip


def intersect(a, b):
    return max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])


def rgba(values, default_alpha=1):
    return tuple(max(0, min(255, round(x * 255))) for x in (values[:3] + [values[3] if len(values) > 3 else default_alpha]))


def draw_frame(image, layout, f, transform=(0, 0), crop=True):
    fid = f["id"]
    if not layout.visible(fid):
        return
    box = layout.rect(fid)
    clip = layout.clip(fid) if crop else (0, 0, image.width, image.height)
    clip = tuple(v + transform[i % 2] for i, v in enumerate(clip)) if crop else clip
    box = tuple(v + transform[i % 2] for i, v in enumerate(box))
    layer = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(layer)
    s = layout.scale(fid)
    color = f.get("colorTexture") or f.get("backdropColor")
    if f["kind"] == "Texture" and not color:
        color = f.get("vertexColor")
        if not color and f.get("texture"):
            # An explicit asset placeholder: no invented WoW icon extraction.
            color = [.25, .31, .32, .9]
    if color and box[2] > box[0] and box[3] > box[1]:
        draw.rectangle(box, fill=rgba(color))
        if f.get("backdropBorderColor"):
            draw.rectangle(box, outline=rgba(f["backdropBorderColor"]), width=max(1, round(s)))
        if f.get("texture") and not f.get("vertexColor") and not f.get("colorTexture"):
            draw.line((box[0], box[1], box[2], box[3]), fill=(150, 160, 163, 180), width=1)
    if f["kind"] == "FontString" and f.get("text"):
        size = f["fontSize"]
        lines = wrap_chars(colored_chars(f["text"], tuple(f["textColor"])), f["width"], size, f.get("wordWrap", True))
        height = (len(lines) * size + max(0, len(lines) - 1) * f["spacing"]) * s
        top = box[1] + (max(0, box[3] - box[1] - height) / 2 if f["justifyV"] == "MIDDLE" else 0)
        for i, line in enumerate(lines):
            line_width = sum(font(round(size)).getlength(c) for c, _ in line) * s
            x = box[0] + ({"LEFT": 0, "CENTER": .5, "RIGHT": 1}.get(f["justifyH"], 0) * ((box[2] - box[0]) - line_width))
            y = top + i * (size + f["spacing"]) * s
            for char, color in line:
                draw.text((round(x), round(y)), char, fill=rgba(list(color)), font=font(round(size * s)), anchor="lt")
                x += font(round(size)).getlength(char) * s
    if crop:
        x0, y0, x1, y1 = (round(v) for v in clip)
        if x1 > x0 and y1 > y0:
            image.alpha_composite(layer.crop((x0, y0, x1, y1)), (x0, y0))
    else:
        image.alpha_composite(layer)


def paint(data, destination):
    layout = Layout(data)
    image = Image.new("RGBA", tuple(data["viewport"]), (26, 30, 35, 255))
    draw = ImageDraw.Draw(image)
    draw.text((32, 14), TITLE, font=font(21), fill=(232, 193, 112), anchor="lt")
    draw.text((32, 43), f"{data['scene']}  /  {round(data['scale'] * 100)}%  /  {data['scroll_position']}  /  UI.lua 真实执行，字体与纹理近似", font=font(13), fill=(160, 170, 181), anchor="lt")
    # Background sublayers render before text regardless of object creation order.
    def priority(f):
        return (0 if f["kind"] not in {"Texture", "FontString"} else 1 if f["kind"] == "Texture" else 2, {"BACKGROUND": 0, "ARTWORK": 1, "OVERLAY": 2}.get(f.get("layer"), 0), f.get("sublayer", 0), f["id"])
    for f in sorted(data["frames"], key=priority):
        draw_frame(image, layout, f)
    image.convert("RGB").save(destination)
    for f in data["frames"]:
        f["physical_rect"] = [round(v, 3) for v in layout.rect(f["id"])]
        f["visible_with_ancestors"] = bool(layout.visible(f["id"]))
        f["clip_rect"] = [round(v, 3) for v in layout.clip(f["id"])]
    return layout


def paint_content(data, layout, destination):
    content = next(f for f in data["frames"] if f["alias"] == "panel.content")
    content_rect, s = layout.rect(content["id"]), data["scale"]
    image = Image.new("RGBA", (math.ceil(330 * s) + 64, math.ceil(content["height"] * s) + 100), (26, 30, 35, 255))
    draw = ImageDraw.Draw(image)
    draw.text((24, 16), TITLE, font=font(18), fill=(232, 193, 112), anchor="lt")
    draw.text((24, 42), "离线完整内容展开图 · 滚动视口外也展示", font=font(12), fill=(160, 170, 181), anchor="lt")
    for f in sorted(data["frames"], key=lambda v: (0 if v["kind"] != "FontString" else 1, v["id"])):
        cursor = f
        while cursor["parent"] and cursor["id"] != content["id"]:
            cursor = layout.frames[cursor["parent"]]
        if cursor["id"] == content["id"]:
            draw_frame(image, layout, f, (32 - content_rect[0], 76 - content_rect[1]), crop=False)
    image.convert("RGB").save(destination)


def check(data, layout):
    panel = next(f for f in data["frames"] if f["alias"] == "panel")
    bounds = layout.rect(panel["id"])
    width, height = data["viewport"]
    overlaps, box_overlaps = [], []
    labels = [f for f in data["frames"] if f["kind"] == "FontString" and f.get("text") and layout.visible(f["id"])]
    # Full content bounds are checked, including offscreen labels. Expected ancestor
    # containment (button + its own label) is intentionally not called an overlap.
    def ink_rects(f):
        box, s, size = layout.rect(f["id"]), layout.scale(f["id"]), f["fontSize"]
        lines = wrap_chars(colored_chars(f["text"], tuple(f["textColor"])), f["width"], size, f.get("wordWrap", True))
        height = (len(lines) * size + max(0, len(lines) - 1) * f["spacing"]) * s
        top = box[1] + (max(0, box[3] - box[1] - height) / 2 if f["justifyV"] == "MIDDLE" else 0)
        for i, line in enumerate(lines):
            width = sum(font(round(size)).getlength(c) for c, _ in line) * s
            x = box[0] + {"LEFT": 0, "CENTER": .5, "RIGHT": 1}.get(f["justifyH"], 0) * (box[2] - box[0] - width)
            y = top + i * (size + f["spacing"]) * s
            yield (x, y, x + width, y + size * s)
    ink = {f["id"]: list(ink_rects(f)) for f in labels}
    def scroll_ancestor(fid):
        f = layout.frames[fid]
        while f["parent"]:
            f = layout.frames[f["parent"]]
            if f["kind"] == "ScrollFrame":
                return f["id"]
        return None
    for i, first in enumerate(labels):
        for second in labels[i + 1:]:
            # Compare all scroll content internally, including offscreen sections;
            # compare scroll content to panel chrome only after native clipping.
            same_scroll = scroll_ancestor(first["id"]) is not None and scroll_ancestor(first["id"]) == scroll_ancestor(second["id"])
            first_box, second_box = layout.rect(first["id"]), layout.rect(second["id"])
            if not same_scroll:
                first_box = intersect(first_box, layout.clip(first["id"]))
                second_box = intersect(second_box, layout.clip(second["id"]))
            intersection = intersect(first_box, second_box)
            if intersection[2] - intersection[0] > 1 and intersection[3] - intersection[1] > 1:
                box_overlaps.append([first["alias"], second["alias"], [round(v, 2) for v in intersection]])
            for first_ink in ink[first["id"]]:
                for second_ink in ink[second["id"]]:
                    touched = intersect(first_ink if same_scroll else intersect(first_ink, layout.clip(first["id"])), second_ink if same_scroll else intersect(second_ink, layout.clip(second["id"])))
                    if touched[2] - touched[0] > 1 and touched[3] - touched[1] > 1:
                        overlaps.append([first["alias"], second["alias"], [round(v, 2) for v in touched]])
    return {"scene": data["scene"], "scale": data["scale"], "scroll_position": data["scroll_position"], "panel_in_viewport": bounds[0] >= 0 and bounds[1] >= 0 and bounds[2] <= width and bounds[3] <= height,
        "text_ink_overlaps": overlaps, "text_ink_overlap_count": len(overlaps),
        "allocated_label_box_overlaps": box_overlaps, "allocated_label_box_overlap_count": len(box_overlaps),
        "scope": "Mock frame/text geometry only; does not prove WoW font metrics or gameplay behavior."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenes", nargs="+", default=["crafting", "long-alternative", "gathering", "unlearned", "no-recipes"])
    parser.add_argument("--scales", nargs="+", type=float, default=[.65, 1, 1.6])
    parser.add_argument("--width", type=int, default=1440)
    parser.add_argument("--height", type=int, default=1000)
    args = parser.parse_args()
    reports, source_hashes = [], set()
    for scene in args.scenes:
        for scale in args.scales:
            name = f"{scene}-{round(scale * 100):03d}"
            data = capture(scale, scene, args.width, args.height)
            source_hashes.add(data["source_sha256"])
            layout = paint(data, HERE / f"{name}.png")
            if scale == 1:
                paint_content(data, layout, HERE / f"{scene}-content.png")
            (HERE / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
            reports.append(check(data, layout))
            if scale == 1:
                bottom = capture(scale, scene, args.width, args.height, scroll_end=True)
                source_hashes.add(bottom["source_sha256"])
                bottom_layout = paint(bottom, HERE / f"{scene}-bottom.png")
                (HERE / f"{scene}-bottom.json").write_text(json.dumps(bottom, ensure_ascii=False, indent=2) + "\n")
                reports.append(check(bottom, bottom_layout))
    if len(source_hashes) != 1:
        raise RuntimeError("UI.lua changed during capture; regenerate from a frozen version")
    report = {"title": TITLE, "source_sha256": next(iter(source_hashes)), "dependencies": {"python": sys.executable, "lua": "lupa.lua51", "pillow": str(Path(Image.__file__).parent), "font": FONT_PATH}, "limitations": LIMITS, "checks": reports}
    (HERE / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"mock_only": True, "source_sha256": report["source_sha256"], "cases": len(reports), "out_of_viewport": sum(not r["panel_in_viewport"] for r in reports), "text_ink_overlaps": sum(r["text_ink_overlap_count"] for r in reports), "report": str(HERE / "report.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
