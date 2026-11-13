"""Build a shared, cross-checked Classic quest reference without addon code.

Only pfQuest's MIT factual records are emitted. The existing Forever reference
checks quest/entity identities and map-frame coordinates; its code, localization
and guide text are not copied. Run from any directory with Python 3.
"""

from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import ast
import gzip
import hashlib
import json
import math
import re
import urllib.request

from inspect_points import Parser, entries as npc_entries, points as npc_points, q as npc_reference


BASE = Path(__file__).resolve().parent
PF_SHA = "104f35678ca39ab1fb78b655f815cc7016f5e0c8"
REFERENCE_SHA = "aa1d7e7294596cf50a6fd0946dfae0d969cb9623"
MAX_ERROR = 0.65
SOURCE = "pfquest-104f356"


def parse_pf_rows(text):
    return {
        int(match[1]): Parser(match[2]).parse()
        for match in re.finditer(r"^  \[(\d+)\] = (\{\}|\{\n.*?^  \}),$", text, re.M | re.S)
    }


def parse_reference_rows(text):
    return {
        int(match[1]): Parser(match[2]).parse()
        for match in re.finditer(r"^\[(\d+)\] = (\{.*\}),$", text, re.M)
    }


def parse_names(text):
    return {
        int(match[1]): Parser(match[2]).parse()
        for match in re.finditer(r'^  \[(\d+)\] = ("(?:\\.|[^"\\])*"),$', text, re.M)
    }


def values(table):
    return list(table.values()) if isinstance(table, dict) else []


def lua(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua(item) for item in value) + "}"
    return "{" + ",".join("[" + lua(key) + "]=" + lua(item) for key, item in value.items()) + "}"


def main():
    requests = [("pf", "db/" + name + ".lua") for name in ("quests", "items", "objects", "areatrigger", "refloot")]
    requests += [("pf", "db/" + locale + "/" + name + ".lua")
                 for locale in ("zhCN", "enUS") for name in ("items", "objects")]
    requests += [("pf", "db/zhCN/quests.lua")]
    requests += [("reference", "data/Forever/forever" + name + "DB.lua") for name in ("Object", "Quest")]

    def fetch(request):
        provider, path = request
        org, repo, sha = ("shagu", "pfQuest", PF_SHA) if provider == "pf" else ("Questie", "QuestieDB", REFERENCE_SHA)
        url = f"https://raw.githubusercontent.com/{org}/{repo}/{sha}/{path}"
        data = urllib.request.urlopen(url, timeout=45).read()
        return request, data.decode(), {"url": url, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}

    with ThreadPoolExecutor(max_workers=6) as executor:
        fetched = list(executor.map(fetch, requests))
    raw = {key: text for key, text, _ in fetched}
    provenance = [source for _, _, source in fetched]
    for filename in ("pfquest_db_units.lua", "pfquest_db_zhCN_units.lua", "pfquest_db_enUS_units.lua",
                     "pfquest_db_zhCN_zones.lua", "data_Forever_foreverNpcDB.lua"):
        data = (BASE / filename).read_bytes()
        provenance.append({"local": filename, "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})

    quests = parse_pf_rows(raw["pf", "db/quests.lua"])
    quest_names = parse_pf_rows(raw["pf", "db/zhCN/quests.lua"])
    items = parse_pf_rows(raw["pf", "db/items.lua"])
    objects = parse_pf_rows(raw["pf", "db/objects.lua"])
    areas = parse_pf_rows(raw["pf", "db/areatrigger.lua"])
    refloot = parse_pf_rows(raw["pf", "db/refloot.lua"])
    reference_objects = parse_reference_rows(raw["reference", "data/Forever/foreverObjectDB.lua"])
    reference_quests = parse_reference_rows(raw["reference", "data/Forever/foreverQuestDB.lua"])
    names = {
        "npc": (parse_names((BASE / "pfquest_db_zhCN_units.lua").read_text()),
                parse_names((BASE / "pfquest_db_enUS_units.lua").read_text())),
        "object": (parse_names(raw["pf", "db/zhCN/objects.lua"]), parse_names(raw["pf", "db/enUS/objects.lua"])),
        "item": (parse_names(raw["pf", "db/zhCN/items.lua"]), parse_names(raw["pf", "db/enUS/items.lua"])),
    }
    area_names = parse_names((BASE / "pfquest_db_zhCN_zones.lua").read_text())
    config = {}
    for node in ast.parse((BASE / "build_catalog.py").read_text()).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id in ("maps", "transforms"):
                    config[target.id] = ast.literal_eval(node.value)
    map_names = {map_id: area_names[area_id] for area_id, map_id in config["maps"].items() if area_id in area_names}
    assert len(map_names) == len(config["maps"])

    rejected = Counter()
    rejection_examples = defaultdict(list)
    cached_points = {}

    def reject(reason, example):
        rejected[reason] += 1
        if len(rejection_examples[reason]) < 20:
            rejection_examples[reason].append(example)

    def convert(x, y, area_id):
        if area_id in config["transforms"]:
            ax, bx, ay, by = config["transforms"][area_id]
            return ax * x + bx, ay * y + by
        return x, y

    def verified(kind, entity_id):
        key = kind, entity_id
        if key in cached_points:
            return cached_points[key]
        if not all(entity_id in language for language in names[kind]):
            cached_points[key] = []
            reject("entity_name_missing", [kind, entity_id])
            return []
        raw_points = npc_points.get(entity_id, []) if kind == "npc" else [
            (point[1], point[2], point[3]) for point in values(objects.get(entity_id, {}).get("coords"))
        ]
        refs = npc_reference.get(entity_id, {}).get(7) if kind == "npc" else reference_objects.get(entity_id, {}).get(4)
        refs = refs or {}
        grids, result = {}, set()
        for old_x, old_y, area_id in raw_points:
            if area_id not in config["maps"] or not refs.get(area_id):
                reject("spawn_no_shared_map", [kind, entity_id, area_id])
                continue
            x, y = convert(old_x, old_y, area_id)
            if not (0 < x < 100 and 0 < y < 100):
                reject("spawn_out_of_bounds", [kind, entity_id, area_id, x, y])
                continue
            if area_id not in grids:
                grid = defaultdict(list)
                for point in refs[area_id].values():
                    grid[math.floor(point[1] / MAX_ERROR), math.floor(point[2] / MAX_ERROR)].append((point[1], point[2]))
                grids[area_id] = grid
            grid = grids[area_id]
            ix, iy = math.floor(x / MAX_ERROR), math.floor(y / MAX_ERROR)
            agrees = any(abs(x - a) + abs(y - b) <= MAX_ERROR
                         for i in range(ix - 1, ix + 2) for j in range(iy - 1, iy + 2)
                         for a, b in grid.get((i, j), []))
            if agrees:
                result.add((config["maps"][area_id], round(x / 100, 5), round(y / 100, 5)))
            else:
                reject("spawn_coordinate_disagreement", [kind, entity_id, area_id, old_x, old_y])
        cached_points[key] = sorted(result)
        return cached_points[key]

    def relationship_ids(quest_id, field, slot):
        group = ((reference_quests.get(quest_id, {}).get(field) or {}).get(slot) or {})
        return {entry if isinstance(entry, int) else entry.get(1) for entry in group.values()}

    def item_sources(item_id):
        row, result = items.get(item_id, {}), set()
        for field, kind, role in (("U", "npc", "drop"), ("O", "object", "container"), ("V", "npc", "vendor")):
            for source_id, amount in (row.get(field) or {}).items():
                if role == "vendor" or amount > 0:
                    result.add((role, kind, source_id))
        for reference_id, chance in (row.get("R") or {}).items():
            if chance <= 0:
                continue
            for field, kind, role in (("U", "npc", "drop"), ("O", "object", "container")):
                result.update((role, kind, source_id) for source_id in (refloot.get(reference_id, {}).get(field) or {}))
        return [source for source in sorted(result) if verified(source[1], source[2])]

    packed_quests, packed_items, packed_areas = {}, {}, {}
    objective_counts, unresolved = Counter(), []
    for quest_id, row in sorted(quests.items()):
        if quest_id not in reference_quests:
            reject("quest_not_in_forever_reference", quest_id)
            continue
        goals, turnin = [], []
        for field, kind, slot in (("U", "npc", 1), ("O", "object", 2), ("I", "item", 3)):
            for entity_id in sorted(set(values((row.get("obj") or {}).get(field)))):
                if entity_id not in relationship_ids(quest_id, 10, slot):
                    reject("objective_identity_disagreement", [quest_id, kind, entity_id])
                    continue
                if kind == "item":
                    if not all(entity_id in language for language in names[kind]):
                        reject("item_name_missing", [quest_id, entity_id])
                        continue
                    sources = item_sources(entity_id)
                    if not sources:
                        reject("item_no_verified_source", [quest_id, entity_id])
                        continue
                    packed_items[entity_id] = [names[kind][0][entity_id], names[kind][1][entity_id], sources]
                elif not verified(kind, entity_id):
                    reject("objective_no_verified_spawn", [quest_id, kind, entity_id])
                    continue
                goals.append([kind, entity_id])
                objective_counts[kind] += 1
        for field, kind, slot in (("U", "npc", 1), ("O", "object", 2)):
            for entity_id in sorted(set(values((row.get("end") or {}).get(field)))):
                if entity_id not in relationship_ids(quest_id, 3, slot):
                    reject("turnin_identity_disagreement", [quest_id, kind, entity_id])
                    continue
                if verified(kind, entity_id):
                    turnin.append([kind, entity_id])
                else:
                    reject("turnin_no_verified_spawn", [quest_id, kind, entity_id])

        # AreaTrigger IDs are not Zone IDs. Check their existing coordinates
        # against this same quest's Forever trigger, rather than a guessed zone
        # center or a quest finisher. A trigger reference does not mean completion.
        area_goals = []
        trigger_refs = ((reference_quests[quest_id].get(9) or {}).get(2) or {})
        for area_trigger_id in sorted(set(values((row.get("obj") or {}).get("A")))):
            result = set()
            for point in values(areas.get(area_trigger_id, {}).get("coords")):
                old_x, old_y, area_id = point[1], point[2], point[3]
                if area_id not in config["maps"]:
                    continue
                x, y = convert(old_x, old_y, area_id)
                if 0 < x < 100 and 0 < y < 100 and any(
                    abs(x - ref[1]) + abs(y - ref[2]) <= MAX_ERROR for ref in values(trigger_refs.get(area_id))
                ):
                    result.add((config["maps"][area_id], round(x / 100, 5), round(y / 100, 5)))
            if result:
                area_goals.append([area_trigger_id, sorted(result)])
            else:
                reject("area_no_same_quest_trigger_agreement", [quest_id, area_trigger_id])
        if area_goals:
            packed_areas[quest_id] = area_goals
            goals.append(["area", quest_id])
            objective_counts["area"] += 1
        if goals or turnin:
            name = quest_names.get(quest_id, {}).get("T") or f"任务 #{quest_id}"
            packed_quests[quest_id] = [name, goals, turnin]
        else:
            unresolved.append(quest_id)

    used = {(kind, entity_id) for _, goals, turnin in packed_quests.values()
            for kind, entity_id in goals + turnin if kind in ("npc", "object")}
    used.update((kind, entity_id) for _, _, sources in packed_items.values() for _, kind, entity_id in sources)
    packed_entities = {"npc": {}, "object": {}}
    for kind, entity_id in sorted(used):
        raw_faction = re.search(r'\["fac"\] = "([AH]+)"', npc_entries.get(entity_id, "")) if kind == "npc" else None
        faction = raw_faction[1] if raw_faction else objects.get(entity_id, {}).get("fac") if kind == "object" else None
        packed_entities[kind][entity_id] = [names[kind][0][entity_id], names[kind][1][entity_id], verified(kind, entity_id), faction]

    header = '''local _, NS = ...

-- Selected pfQuest MIT database facts, not upstream addon runtime code.
-- Copyright (c) 2017-2021 Eric Mauser (Shagu). MIT notice: SOURCES.md.
-- pfQuest commit 104f35678ca39ab1fb78b655f815cc7016f5e0c8.
-- Coordinates cross-checked against the same entity/map in Forever reference;
-- exploration uses the same quest's trigger/map. These are area references,
-- not live positions, guaranteed drops, vendor stock, or gameplay validation.
-- Generated by PersonalAddons/research/navigator/build_quest_catalog.py.
'''
    tables = {"zones": map_names, "npcs": packed_entities["npc"], "objects": packed_entities["object"],
              "items": packed_items, "areas": packed_areas, "quests": packed_quests}
    parts = [header]
    for name, rows in tables.items():
        parts.append("local " + name + " = {\n")
        parts.extend("[" + lua(key) + "]=" + lua(row) + ",\n" for key, row in sorted(rows.items()))
        parts.append("}\n")
    parts.append('''
local SOURCE = "pfquest-104f356"
local factionNames = {A="Alliance",H="Horde",AH="Neutral"}

local function Entity(kind, id)
    return (kind == "npc" and npcs or objects)[id]
end

local function AppendPoints(destination, entity, id, sourceKind)
    for _, p in ipairs(entity[3]) do
        destination[#destination + 1] = {
            mapID=p[1],x=p[2],y=p[3],zone=zones[p[1]],source=SOURCE,
            sourceName=entity[1],sourceID=id,sourceKind=sourceKind,
            faction=factionNames[entity[4]],areaReference=true,
        }
    end
end

-- Every returned table is a fresh copy. Static tables stay private so caller
-- selection/sorting or saved navigation state cannot corrupt later lookups.
function NS.GetQuestReference(questID)
    questID = tonumber(questID)
    local row = questID and quests[questID]
    if not row then return nil end
    local result = {name=row[1],objectives={},turnin={}}
    for _, reference in ipairs(row[2]) do
        local kind, id = reference[1], reference[2]
        local goal = {kind=kind,id=id,points={}}
        if kind == "item" then
            local item = items[id]
            goal.name, goal.english = item[1], item[2]
            for _, source in ipairs(item[3]) do
                AppendPoints(goal.points, Entity(source[2], source[3]), source[3], source[1])
            end
        elseif kind == "area" then
            goal.name, goal.english = row[1], "Quest area"
            for _, area in ipairs(areas[id]) do
                for _, p in ipairs(area[2]) do
                    goal.points[#goal.points + 1] = {
                        mapID=p[1],x=p[2],y=p[3],zone=zones[p[1]],source=SOURCE,
                        sourceName=goal.name,sourceID=area[1],sourceKind="area",areaReference=true,
                    }
                end
            end
        else
            local entity = Entity(kind, id)
            goal.name, goal.english = entity[1], entity[2]
            AppendPoints(goal.points, entity, id, kind)
        end
        result.objectives[#result.objectives + 1] = goal
    end
    for _, reference in ipairs(row[3]) do
        local kind, id = reference[1], reference[2]
        local entity = Entity(kind, id)
        local target = {kind="turnin",id=id,name=entity[1],english=entity[2],points={}}
        AppendPoints(target.points, entity, id, kind)
        result.turnin[#result.turnin + 1] = target
    end
    return result
end
''')
    target = BASE.parents[2] / "_forever_/Interface/AddOns/MyForeverNavigator/QuestData.lua"
    content = "".join(parts).encode()
    target.write_bytes(content)
    summary = {
        "quests": len(packed_quests), "withObjectives": sum(bool(r[1]) for r in packed_quests.values()),
        "withTurnin": sum(bool(r[2]) for r in packed_quests.values()), "objectiveReferences": dict(objective_counts),
        "itemEntities": len(packed_items), "npcEntities": len(packed_entities["npc"]),
        "objectEntities": len(packed_entities["object"]), "areaQuests": len(packed_areas),
        "areaPoints": sum(len(points) for rows in packed_areas.values() for _, points in rows),
        "verifiedEntityPoints": sum(len(entity[2]) for rows in packed_entities.values() for entity in rows.values()),
        "maps": len({p[0] for rows in packed_entities.values() for entity in rows.values() for p in entity[2]}),
        "luaBytes": len(content), "gzipBytes": len(gzip.compress(content, mtime=0)),
    }
    audit = {
        "schemaVersion": 1, "sources": provenance, "summary": summary,
        "selection": {"coordinateErrorLimit": MAX_ERROR, "sameEntityAndAreaRequired": True,
                      "areaException": "same quest ID trigger and same AreaID; native AreaTrigger IDs are not exposed by reference",
                      "coordinateUnit": "sum of map percentage-point differences", "transforms": config["transforms"],
                      "spawnTruncation": False, "questRelationshipCrossCheck": True,
                      "itemSourceKinds": ["drop", "container", "vendor"],
                      "notImported": ["IR use-item/spell interactions", "zone centers", "unverified instance coordinates", "quest descriptions"]},
        "rejectedCounts": dict(rejected), "rejectedExamples": dict(rejection_examples),
        "unresolvedQuestIDs": unresolved, "includedQuestIDs": sorted(packed_quests),
        "knownExamples": {str(qid): packed_quests.get(qid) for qid in (6, 7, 18, 25, 62, 76, 783)},
        "outputSHA256": hashlib.sha256(content).hexdigest(),
        "verification": "Offline source and coordinate-frame cross-check only; no Forever gameplay validation.",
    }
    (BASE / "quest-catalog-audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
