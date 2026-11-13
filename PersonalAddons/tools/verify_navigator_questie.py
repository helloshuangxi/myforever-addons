"""Run Navigator against installed QuestieDB in Lua 5.1 with modeled map APIs.

This checks actual database reads and application integration, not game UI,
native map validity, character-specific Questie policy or NPC locations.
"""
from pathlib import Path
import argparse
from collections import Counter
import json
import time
from audit_navigator_questie import load_database, text


def run(root, locale="zhCN", faction="Alliance"):
    database = root / "_forever_/Interface/AddOns/QuestieDB"
    addon = root / "_forever_/Interface/AddOns/MyForeverNavigator"
    lua, db, metadata, loaded, _ = load_database(database, locale, faction)
    support = db[b"Support"][b"Get"](b"ZoneDB")[b"private"]
    mapping = lua.execute(support[b"areaIdToUiMapId"])
    for area, map_id in lua.execute(support[b"areaIdToUiMapIdOverride"]).items():
        mapping[area] = map_id
    # The native client is not running a character. Treat non-dungeon support
    # mappings as zones for this fixture, explicitly excluding continent maps.
    # Production always uses real C_Map.GetMapInfo and rejects unknown maps.
    modeled = lua.table()
    dungeon_areas = lua.table()
    for area, entry in support[b"dungeons"].items():
        dungeon_areas[area] = True
        if entry[2]:
            for _, alias in entry[2].items():
                dungeon_areas[alias] = True
    for area, map_id in mapping.items():
        if support[b"dungeons"][area] is None and map_id not in (1414, 1415, 947):
            modeled[map_id] = True
    g = lua.globals()
    g[b"_verifyMapping"], g[b"_verifyMaps"], g[b"_verifyDungeons"] = mapping, modeled, dungeon_areas
    g[b"debugprofilestop"] = lambda: time.perf_counter() * 1000
    lua.execute(b"""
        Questie = {API={isReady=true}}
        local zones={GetUiMapIdByAreaId=function(_, area) return _verifyMapping[area] end,
            IsDungeonZone=function(area) return _verifyDungeons[area]==true end}
        QuestieLoader={ImportModule=function(_,key)
            if key=='ZoneDB' then return zones end
            if key=='Phasing' then return {IsSpawnVisible=function()return false end} end
        end}
        Enum={UIMapType={Zone=3}}
        C_Map={GetBestMapForUnit=function() return 1429 end,
            GetMapInfo=function(id) if _verifyMaps[id] then return {name='Map '..id,mapType=3} end end}
        _verifyNS={}
    """)
    ns = g[b"_verifyNS"]
    for name in ("Core", "Data", "Classification", "Provider", "QuestieCatalog", "Navigation"):
        lua.execute((addon / (name + ".lua")).read_bytes(), b"MyForeverNavigator", ns)
    ns[b"Initialize"](None)
    serialize = lua.eval(b"""function(value)
        local function encode(v)
            if type(v)~='table' then return type(v)..':'..tostring(v) end
            local items={}
            for k,item in pairs(v) do items[#items+1]=encode(k)..'='..encode(item) end
            table.sort(items);return '{'..table.concat(items,',')..'}'
        end
        return encode(value)
    end""")
    source_points_before = serialize(ns[b"Points"])
    profession_samples = {
        "mining": (1681, "采矿训练师"), "herbalism": (812, "草药训练师"),
        "skinning": (1292, "剥皮训练师"), "alchemy": (1215, "炼金术训练师"),
        "blacksmithing": (514, "锻造训练师"), "leatherworking": (223, "制皮训练师"),
        "tailoring": (1103, "裁缝训练师"), "engineering": (1676, "工程训练师"),
        "enchanting": (1317, "附魔训练师"), "first-aid": (2326, "急救训练师"),
        "cooking": (1355, "烹饪训练师"), "fishing": (1651, "钓鱼训练师"),
    }
    overlaps = {3181: "first-aid", 5164: "blacksmithing", 7406: "engineering", 8736: "engineering", 12920: "first-aid", 12939: "first-aid"}
    rejected_ids = (2626, 1684, 54)
    source_fields = lua.table_from([b"name", b"subName", b"spawns", b"npcFlags", b"friendlyToFaction"])
    source_ids = {row[0] for row in profession_samples.values()} | set(overlaps) | set(rejected_ids)
    db_before = {npc_id: serialize(db[b"Npc"][b"GetAll"](npc_id, source_fields)) for npc_id in source_ids}
    lua.execute(b"""
        _verifyNS.GetPlayerPosition=function()return 1429,.42,.65 end
        _verifyNS.GetLocationContext=function()return {mapID=1429,x=.42,y=.65,width=1000,height=700} end
        _verifyNS.MeasurePoint=function(p)
            if p.mapID==1429 then return math.sqrt((p.x-.42)^2+(p.y-.65)^2)*1000,'same-map' end
            return nil,'unknown'
        end
    """)
    original_count = len(ns[b"Points"])
    started, frames = time.perf_counter(), 0
    while frames < 10000:
        ns[b"UpdateQuestieCatalog"](1 / 60)
        frames += 1
        state = ns[b"GetQuestieCatalogStatus"]()
        if state[b"status"] == b"error":
            raise AssertionError(text(state[b"error"]))
        if state[b"status"] == b"ready":
            break
    assert state[b"status"] == b"ready", "Catalogue did not finish"
    assert len(ns[b"Points"]) == original_count == 427
    points = ns[b"GetCatalogPoints"]()
    unique, maps, categories = set(), set(), Counter()
    for _, p in points.items():
        pair = (p[b"npcID"], p[b"mapID"])
        assert pair not in unique, ("Duplicate NPC/map", pair)
        unique.add(pair)
        maps.add(p[b"mapID"])
        assert ns[b"ValidPoint"](p)
        categories[text(p[b"category"])] += 1
    samples = []
    for npc_id in (240, 295, 332, 1411):
        found = ns[b"Search"](str(npc_id).encode(), lua.table_from({b"faction": b"all"}))
        exact = [p for _, p in found.items() if p[b"npcID"] == npc_id]
        assert exact, ("Missing actual Questie NPC", npc_id)
        p = exact[0]
        assert p[b"questie"] is True
        assert ns[b"ToggleFavorite"](p[b"id"])
        favorites = ns[b"Search"](str(npc_id).encode(), lua.table_from({b"category": b"favorites", b"faction": b"all"}))
        assert any(row[b"id"] == p[b"id"] for _, row in favorites.items())
        assert ns[b"GetPoint"](p[b"id"])[b"npcID"] == npc_id
        if p[b"english"]:
            aliases = ns[b"Search"](p[b"english"], lua.table_from({b"faction": b"all"}))
            assert any(row[b"npcID"] == npc_id for _, row in aliases.items())
        if npc_id == 1411:
            assert ns[b"GetPointSubcategory"](p) == b"trainers:rogue"
        samples.append({"npcID": npc_id, "name": text(p[b"name"]), "english": text(p[b"english"]), "category": text(p[b"category"]), "service": text(p[b"service"]), "mapID": p[b"mapID"], "x": p[b"x"], "y": p[b"y"]})
    profession_options = {b"category": b"profession-trainers", b"faction": b"all"}
    all_professions = ns[b"Search"](b"", lua.table_from(profession_options))
    profession_counts, profession_npcs, verified_trainers = Counter(), {}, []
    for _, point in all_professions.items():
        profession = text(ns[b"GetPointProfession"](point))
        assert profession in profession_samples, ("Unknown profession in results", profession)
        profession_counts[profession] += 1
        profession_npcs.setdefault(profession, set()).add(point[b"npcID"])
    for profession, (npc_id, alias) in profession_samples.items():
        options = dict(profession_options)
        options[b"subcategory"] = ("profession-trainers:" + profession).encode()
        results = ns[b"Search"](alias.encode(), lua.table_from(options))
        matches = [p for _, p in results.items() if p[b"npcID"] == npc_id]
        assert matches, ("Missing ordinary profession trainer", profession, npc_id, alias)
        point = matches[0]
        assert point[b"category"] == b"profession-trainers"
        assert ns[b"ToggleFavorite"](point[b"id"])
        assert ns[b"GetPoint"](point[b"id"])[b"npcID"] == npc_id
        assert ns[b"Start"](point) is True
        assert ns[b"GetNavigation"]()[b"point"][b"id"] == point[b"id"]
        ns[b"Stop"]()
        verified_trainers.append({"profession": profession, "query": alias, "npcID": npc_id,
                                  "name": text(point[b"name"]), "title": text(point[b"service"]),
                                  "mapID": point[b"mapID"], "id": text(point[b"id"])})
    preserved_trainers = []
    for npc_id, profession in overlaps.items():
        source = next(p for _, p in ns[b"Points"].items() if p[b"npcID"] == npc_id)
        options = dict(profession_options)
        options[b"subcategory"] = ("profession-trainers:" + profession).encode()
        found = ns[b"Search"](str(npc_id).encode(), lua.table_from(options))
        exact = [p for _, p in found.items() if p[b"npcID"] == npc_id]
        assert exact, ("Curated trainer missing secondary profession", npc_id)
        point = exact[0]
        assert point[b"id"] == source[b"id"] and point[b"category"] == b"special"
        assert ns[b"GetPointSubcategory"](point) == b"special:profession-advancement"
        assert ns[b"PointMatchesSubcategory"](point, ("profession-trainers:" + profession).encode())
        assert source[b"professionKey"] is None, "Authored source point mutated"
        assert ns[b"Start"](point) is True and ns[b"GetPoint"](point[b"id"])[b"npcID"] == npc_id
        ns[b"Stop"]()
        preserved_trainers.append({"npcID": npc_id, "profession": profession, "id": text(point[b"id"]),
                                   "primary_category": text(point[b"category"]), "old_subcategory": text(ns[b"GetPointSubcategory"](point))})
    for npc_id in rejected_ids:
        assert all(point[b"npcID"] != npc_id for _, point in all_professions.items()), ("Non-trainer leaked", npc_id)
        raw = db[b"Npc"][b"GetAll"](npc_id, source_fields)
        trainer_flag = db[b"Enum"][b"npcFlags"][b"TRAINER"]
        assert not (int(raw[4] or 0) & int(trainer_flag))
    assert serialize(ns[b"Points"]) == source_points_before
    assert all(serialize(db[b"Npc"][b"GetAll"](npc_id, source_fields)) == before for npc_id, before in db_before.items())
    timings = {}
    for query in ("", "治安官杜汉", "旅店老板", "马迪亚斯", "332"):
        t = time.perf_counter()
        result = ns[b"Search"](query.encode(), lua.table_from({b"faction": b"all"}))
        timings[query or "all"] = {"milliseconds": round((time.perf_counter() - t) * 1000, 2), "returned_points": len(result)}
    assert len(ns[b"Search"]("definitely-not-a-npc-name-784922".encode(), lua.table_from({b"faction": b"all"}))) == 0
    return {"status": "passed", "scope": "actual installed DB + Navigator Lua, modeled client maps; not in-game validation",
            "source": {"questie_db_version": text(metadata[b"Version"]), "commit": text(metadata[b"X-BUILD-COMMIT"]), "lua_files_loaded": len(loaded)},
            "persona": {"locale": locale, "faction": faction}, "build_frames": frames,
            "elapsed_ms": round((time.perf_counter() - started) * 1000, 2), "curated_points": original_count,
            "total_points": len(points), "unique_npcs": len({pair[0] for pair in unique}), "maps": len(maps),
            "categories": dict(categories), "samples": samples, "search_timings_modeled_apis": timings,
            "profession_trainers": {"returned_points": len(all_professions),
                "unique_npcs": len(set().union(*profession_npcs.values())),
                "points_by_profession": dict(profession_counts), "npcs_by_profession": {k: len(v) for k, v in profession_npcs.items()},
                "verified_ordinary_samples": verified_trainers, "preserved_curated_secondary_samples": preserved_trainers,
                "non_trainer_ids_rejected": list(rejected_ids), "source_values_unchanged": True,
                "navigation_scope": "NS.Start/GetNavigation/GetPoint with modeled APIs; no physical clicks or in-game travel"},
            "limitations": ["C_Map was modeled from support mappings, not native client results", "Character Questie policy and live Phasing not loaded; phased-only points excluded from returned results", "Reference coordinates, not current NPC tracking"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = run(Path(__file__).resolve().parents[2])
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded)
    print(encoded)
