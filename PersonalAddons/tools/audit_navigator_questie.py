#!/usr/bin/env python3
"""Audit installed QuestieDB through its actual Lua API, without modifying it.

Run with PersonalAddons/.venv/bin/python. Only Lupa is required. The small CBOR
reader and zlib bridge emulate client encoding APIs; all database composition,
localization and entity reads execute the installed addon's Lua 5.1 code.
This is an offline data audit, not proof of in-game NPC location or map validity.
"""

from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib

from lupa.lua51 import LuaRuntime


class CBORReader:
    """Decode the definite-length CBOR forms used in QuestieDB metadata."""

    def __init__(self, data: bytes):
        self.data, self.offset = data, 0

    def take(self, size: int) -> bytes:
        result = self.data[self.offset : self.offset + size]
        if len(result) != size:
            raise ValueError("Truncated CBOR value")
        self.offset += size
        return result

    def read(self):
        header = self.take(1)[0]
        major, additional = header >> 5, header & 31
        if additional < 24:
            value = additional
        elif additional in (24, 25, 26, 27):
            value = int.from_bytes(self.take(1 << (additional - 24)), "big")
        else:
            raise ValueError(f"Unsupported CBOR additional information: {additional}")
        if major == 0:
            return value
        if major == 1:
            return -1 - value
        if major in (2, 3):
            # Lupa uses bytes to preserve binary CBOR and UTF-8 without recoding.
            return self.take(value)
        if major == 4:
            return [self.read() for _ in range(value)]
        if major == 5:
            return dict((self.read(), self.read()) for _ in range(value))
        if major == 6:
            return self.read()
        if major == 7:
            if additional in (20, 21, 22, 23):
                return {20: False, 21: True, 22: None, 23: None}[additional]
            if additional in (25, 26, 27):
                size, fmt = {25: (2, ">e"), 26: (4, ">f"), 27: (8, ">d")}[additional]
                return struct.unpack(fmt, value.to_bytes(size, "big"))[0]
        raise ValueError(f"Unsupported CBOR major type: {major}")


def text(value) -> str:
    return value.decode("utf-8") if isinstance(value, bytes) else str(value)


def load_database(database: Path, locale: str, faction: str):
    """Load shipped Baked TOC Lua files, omitting only its visual mode indicator."""
    toc = database / "QuestieDB_Forever.toc"
    contents = toc.read_bytes()
    metadata = {
        match[1]: match[2]
        for line in contents.splitlines()
        if (match := re.match(rb"^## ([^:]+): (.*)$", line))
    }
    if metadata.get(b"X-Mode") != b"baked":
        raise ValueError("This audit expects the installed Forever Baked artifact")
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    namespace = lua.table()

    def to_lua(value):
        if isinstance(value, (list, tuple)):
            result = lua.table()
            for index, item in enumerate(value, 1):
                result[index] = to_lua(item)
            return result
        if isinstance(value, dict):
            return lua.table_from({key: to_lua(item) for key, item in value.items()})
        return value

    def decode(data):
        reader = CBORReader(data)
        result = reader.read()
        if reader.offset != len(data):
            raise ValueError("Trailing bytes in CBOR metadata")
        return to_lua(result)

    globals_ = lua.globals()
    globals_[b"_auditMetadata"] = lambda _addon, key: metadata.get(key)
    globals_[b"_auditBase64"] = lambda value: base64.b64decode(value, validate=True)
    globals_[b"_auditDecompress"] = lambda value, _method: zlib.decompress(value)
    globals_[b"_auditCBOR"] = decode
    globals_[b"_auditLocale"] = locale.encode()
    globals_[b"_auditFaction"] = faction.encode()
    globals_[b"_auditRace"] = b"Orc" if faction == "Horde" else b"Human"
    lua.execute(b"""
      C_AddOns = {GetAddOnMetadata = function(...) return _auditMetadata(...) end}
      GetAddOnMetadata = C_AddOns.GetAddOnMetadata
      C_EncodingUtil = {
        DecodeBase64 = function(...) return _auditBase64(...) end,
        DecompressString = function(...) return _auditDecompress(...) end,
        DeserializeCBOR = function(...) return _auditCBOR(...) end,
      }
      GetLocale = function() return _auditLocale end
      UnitFactionGroup = function() return _auditFaction end
      UnitClassBase = function() return 'WARRIOR' end
      UnitClass = function() return 'Warrior', 'WARRIOR', 1 end
      UnitRace = function() return _auditRace, _auditRace, _auditFaction == 'Horde' and 2 or 1 end
      GetBuildInfo = function() return '1.60.1', '70862', '', 16001 end
      GetTime = function() return 0 end
    """)
    loaded = []
    for line in contents.splitlines():
        line = line.strip()
        if not line or line.startswith(b"#"):
            continue
        relative = line.decode().replace("\\", "/")
        if not relative.endswith(".lua"):
            raise ValueError(f"Unexpected TOC entry: {relative}")
        if relative == "src/ui/modeIndicator.lua":
            continue
        lua.execute((database / relative).read_bytes(), b"QuestieDB", namespace)
        loaded.append(relative)
    return lua, namespace, metadata, loaded, contents


def audit(database: Path, locale: str, faction: str) -> dict:
    lua, db, metadata, loaded, contents = load_database(database, locale, faction)
    npc = db[b"Npc"]
    ids = npc[b"GetAllIds"]()
    flags = db[b"Enum"][b"npcFlags"]
    zone_support = db[b"Support"][b"Get"](b"ZoneDB")[b"private"]
    mapping = lua.execute(zone_support[b"areaIdToUiMapId"])
    override = lua.execute(zone_support[b"areaIdToUiMapIdOverride"])
    for area, map_id in override.items():
        mapping[area] = map_id
    dungeons = zone_support[b"dungeons"]
    keys = lua.table_from([b"name", b"subName", b"spawns", b"npcFlags", b"friendlyToFaction"])
    counts = Counter()
    services = Counter()
    maps, points, pairs = set(), 0, set()
    samples = []
    for index in range(1, len(ids) + 1):
        npc_id = ids[index]
        row = npc[b"GetAll"](npc_id, keys)
        name, subtitle, spawns, bitmask, friendly = (row[i] for i in range(1, 6))
        if name:
            counts["named_npcs"] += 1
            if any(byte >= 128 for byte in name):
                counts["non_ascii_names"] += 1
        if subtitle:
            counts["with_subtitle"] += 1
        for flag_name, flag_bit in flags.items():
            if flag_bit and int(bitmask or 0) & int(flag_bit):
                services[text(flag_name)] += 1
        valid_for_npc = False
        for area_id, locations in spawns.items() if spawns is not None else ():
            map_id = mapping[area_id]
            if not isinstance(map_id, (int, float)) or map_id <= 0:
                counts["spawn_areas_without_map"] += 1
                continue
            if dungeons[area_id] is not None:
                counts["dungeon_spawn_areas_excluded"] += 1
                continue
            accepted = 0
            for _, location in locations.items():
                x, y, phase = location[1], location[2], location[3]
                if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                    counts["invalid_coordinate_rows"] += 1
                elif not (0 < x < 100 and 0 < y < 100):
                    counts["boundary_or_sentinel_rows_excluded"] += 1
                elif phase is not None:
                    counts["phase_rows_not_evaluated"] += 1
                else:
                    accepted += 1
            if accepted:
                valid_for_npc = True
                points += accepted
                maps.add(map_id)
                pairs.add((npc_id, map_id))
        if valid_for_npc:
            counts["npcs_with_unphased_non_dungeon_reference"] += 1
            if npc_id in {240, 241, 253, 295, 332, 9996, 90000}:
                samples.append({"npcID": npc_id, "name": text(name), "subtitle": text(subtitle) if subtitle else "", "friendlyToFaction": text(friendly) if friendly else None})
    return {
        "status": "passed",
        "scope": "offline Lua 5.1 database API audit; no game or native map-type verification",
        "source": {"toc": str(database / "QuestieDB_Forever.toc"), "toc_sha256": hashlib.sha256(contents).hexdigest(), "version": text(metadata[b"Version"]), "commit": text(metadata[b"X-BUILD-COMMIT"]), "contract": db[b"contractVersion"], "lua_files_loaded": len(loaded)},
        "persona": {"locale": locale, "faction": faction, "class": "WARRIOR", "race": "Orc" if faction == "Horde" else "Human", "questie_policy_corrections_loaded": False},
        "composed_npc_count": len(ids),
        "counts": dict(counts),
        "non_dungeon_unphased_reference_points": points,
        "non_dungeon_unphased_npc_map_pairs": len(pairs),
        "mapped_ids_before_native_type_check": sorted(maps),
        "service_flags_all_npcs": dict(sorted(services.items())),
        "samples": samples,
        "limitations": ["Questie character policy and live Phasing are not initialized", "Map IDs require live C_Map type validation before navigation", "Database coordinates are reference positions, not live NPC tracking", "Only QuestieDB files are read; no database data is copied into the navigator distribution"],
    }


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=root / "_forever_/Interface/AddOns/QuestieDB")
    parser.add_argument("--locale", default="zhCN")
    parser.add_argument("--faction", choices=("Alliance", "Horde"), default="Alliance")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit(args.database.resolve(), args.locale, args.faction)
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()
