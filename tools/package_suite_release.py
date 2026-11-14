#!/usr/bin/env python3
"""Build immutable addon ZIPs from TOC/source assets; never include player data."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAMES = {
    "MyForeverChat": ("微信式聊天", "/wx"),
    "MyForeverProfessions": ("商业技能助手", "/myprof"),
    "MyForeverNavigator": ("世界向导", "/mynav"),
    "MyForeverTargets": ("目标选择", "/mytargets"),
    "MyForeverCoach": ("玩家行为采集", "/mybehavior"),
    "MyForeverMacros": ("个人宏工坊", "/mymacro"),
    "MyForeverFieldKit": ("随身手册", "/myfield"),
}


def package(name, output):
    addon = ROOT / "_forever_/Interface/AddOns" / name
    toc = addon / (name + ".toc")
    text = toc.read_text(encoding="utf-8")
    version = re.search(r"^## Version:\s*([0-9.]+)$", text, re.M).group(1)
    entries = [line.strip().replace("\\", "/") for line in text.splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    assert entries[0] == "MyForeverStyle.lua"
    files = [name + ".toc", *entries]
    # WoW loads root Bindings.xml automatically; it need not appear in the TOC.
    if (addon / "Bindings.xml").is_file():
        files.append("Bindings.xml")
    # The chat emotes are referenced dynamically rather than from the TOC.
    if (addon / "Media").is_dir():
        files += [p.relative_to(addon).as_posix() for p in (addon / "Media").rglob("*")
                  if p.is_file() and p.suffix.lower() in {".tga", ".blp", ".png"}]
    for p in addon.rglob("*"):
        if p.is_file() and (p.name.lower().startswith("license") or p.name == "SOURCES.md"):
            files.append(p.relative_to(addon).as_posix())
    payload = {}
    for relative in sorted(set(files)):
        parsed = PurePosixPath(relative)
        source = addon.joinpath(*parsed.parts)
        assert not parsed.is_absolute() and ".." not in parsed.parts
        assert source.is_file() and not source.is_symlink()
        assert source.resolve().is_relative_to(addon.resolve())
        payload[relative] = source.read_bytes()
    assert {p.relative_to(addon).as_posix() for p in addon.rglob("*.lua")} == {
        p for p in entries if p.endswith(".lua")}, "TOC does not cover all Lua source"
    title, command = NAMES[name]
    readme = (f"# 我的无限 · {title} {version} 试用版\n\n"
              "适配国服《魔兽世界：无限》1.60.1，Interface 16001。\n"
              f"完整退出游戏后，仅将 {name} 文件夹复制到 _forever_/Interface/AddOns/，保留 WTF，重新启动。\n"
              f"进入游戏后使用 {command}；/myui 打开统一布局，/myui sound 切换菜单音效。\n"
              "已有手动位置与主题保留；聊天旧用户可在设置选择“午夜”。\n"
              "星辉窗口、反馈及布局调整已获用户进游戏后的界面验收与发布授权；专项功能测试范围见 VALIDATION.md。\n"
              "共享样式随插件内嵌，无需额外安装。不自动移动角色或改写保存的按键/动作条；施法兼容可能临时接管原技能键并在离开后恢复。\n")
    if name == "MyForeverCoach":
        readme += ("\n/mybehavior pause 暂停，/mybehavior resume 恢复。只记录公开游戏事件的本机日累计，"
                   "不记录按键、聊天、姓名或 GUID，不上传。统计按 UTC+08:00 分日，保留最近90天；"
                   "游戏 /reload 或退出写盘后，在管理器0.4.0的“行为统计”页刷新。旧会话可能不完整，"
                   "施法失败不是误操作，静止不是挂机。管理器不自动安装此采集器。\n")
    if name == "MyForeverMacros":
        readme += "\n/mypriest 进入牧师模板，/myseal 查看圣印提醒；创建角色宏前检查技能与预览，插件不自动改动作条或按键。\n"
    if name == "MyForeverFieldKit":
        readme += "\n/myfield lock 切换锁定，/myfield reset 重置本次旅途统计。金币是所有收支净变化，空格仅含普通背包，耐久为最低值。\n"
    payload["README.md"] = readme.encode("utf-8")
    payload["VALIDATION.md"] = (ROOT / "PersonalAddons/releases/ui-20261114-VALIDATION.md").read_bytes()
    members = {name + "/" + p: data for p, data in payload.items()}
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{name}-{version}-Trial.zip"
    if archive.exists():
        with zipfile.ZipFile(archive) as existing:
            assert {p: existing.read(p) for p in existing.namelist()} == members, "Refusing to replace an immutable ZIP"
    else:
        with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as target:
            for p, data in sorted(members.items()):
                info = zipfile.ZipInfo(p, (2026, 11, 14, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                target.writestr(info, data)
    with zipfile.ZipFile(archive) as check:
        assert check.testzip() is None
        assert len(check.namelist()) == len(members)
        assert {p: check.read(p) for p in check.namelist()} == members
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
    record = {"name": name, "version": version, "filename": archive.name,
              "size_bytes": archive.stat().st_size, "sha256": digest,
              "source_files": {p: hashlib.sha256(data).hexdigest() for p, data in payload.items()}}
    archive.with_suffix(".manifest.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "PersonalAddons/dist/ui-20261114")
    args = parser.parse_args()
    records = [package(name, args.output) for name in NAMES]
    (args.output / "addons-manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
    for item in records:
        print(item["filename"], item["size_bytes"], item["sha256"])


if __name__ == "__main__":
    main()
