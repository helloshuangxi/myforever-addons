#!/usr/bin/env python3
"""Copy the shared suite style into every owned addon, or check the copies.

    python3 tools/sync_style.py          # write the embedded copies
    python3 tools/sync_style.py --check  # exit 1 if any copy differs

Each MyForever* addon ships alone, so each embeds its own identical copy of
PersonalAddons/shared/MyForeverStyle.lua and lists it first in its TOC.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "PersonalAddons/shared/MyForeverStyle.lua"
NAME = "MyForeverStyle.lua"


def main():
    check = "--check" in sys.argv[1:]
    wanted = SOURCE.read_bytes()
    bad = []
    for addon in sorted((ROOT / "_forever_/Interface/AddOns").glob("MyForever*")):
        copy = addon / NAME
        toc = addon / (addon.name + ".toc")
        entries = [line.strip() for line in toc.read_text(encoding="utf-8").splitlines()
                   if line.strip() and not line.strip().startswith("#")]
        first = entries[0] if entries else ""
        if check:
            if not copy.is_file() or copy.read_bytes() != wanted:
                bad.append(f"{copy.relative_to(ROOT)} differs from the shared source")
            if NAME in entries and first != NAME:
                bad.append(f"{toc.relative_to(ROOT)} must list {NAME} first")
            if NAME not in entries:
                bad.append(f"{toc.relative_to(ROOT)} does not load {NAME}")
        else:
            copy.write_bytes(wanted)
            print("wrote", copy.relative_to(ROOT))
    for line in bad:
        print("STYLE:", line)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
