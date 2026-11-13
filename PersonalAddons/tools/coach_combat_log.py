"""Read an explicit native-log time window and emit a private, anonymous report.

Standard library only. No network, game APIs, live tailing, AI, or input control.
Names, GUIDs, arbitrary strings, filenames and raw lines never enter the report.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict, deque
import csv
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


MAX_LINE_BYTES = 128 * 1024
MAX_WINDOW_ROWS = 250_000
STAMP = re.compile(r"^(\d{1,2}/\d{1,2}/\d{4}) (\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)  (.*)$")
GUID = re.compile(r"^(Player|Creature|Pet|Vehicle|GameObject)-(?:[0-9A-Fa-f]+-)*[0-9A-Fa-f]+$")
ZERO_GUID = "0000000000000000"
SWINGS = {"SWING_DAMAGE", "SWING_DAMAGE_LANDED"}
DAMAGE = {"SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "RANGE_DAMAGE", "DAMAGE_SHIELD", "DAMAGE_SPLIT", "ENVIRONMENTAL_DAMAGE"} | SWINGS
HEAL = {"SPELL_HEAL", "SPELL_PERIODIC_HEAL"}
MISSED = {"SPELL_MISSED", "SPELL_PERIODIC_MISSED", "RANGE_MISSED", "SWING_MISSED"}
AURAS = {"SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED", "SPELL_AURA_REFRESH", "SPELL_AURA_APPLIED_DOSE", "SPELL_AURA_REMOVED_DOSE", "SPELL_AURA_BROKEN", "SPELL_AURA_BROKEN_SPELL"}
CASTS = {"SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_CAST_FAILED"}
CONTROL = {"SPELL_INTERRUPT", "SPELL_DISPEL", "SPELL_DISPEL_FAILED", "SPELL_STOLEN"}
DEATHS = {"UNIT_DIED", "UNIT_DESTROYED", "PARTY_KILL"}
RESOURCE = {"SPELL_ENERGIZE", "SPELL_PERIODIC_ENERGIZE", "SPELL_DRAIN", "SPELL_LEECH"}
ALLOWED = DAMAGE | HEAL | MISSED | AURAS | CASTS | CONTROL | DEATHS | RESOURCE | {"SPELL_RESURRECT", "SPELL_SUMMON"}
MISS_TYPES = {"MISS", "DODGE", "PARRY", "BLOCK", "DEFLECT", "IMMUNE", "ABSORB", "REFLECT", "EVADE", "RESIST"}
ENVIRONMENT = {"Falling", "Lava", "Fire", "Slime", "Drowning", "Fatigue"}


class DataError(ValueError):
    """Messages are fixed diagnostics, never copied from input or OS errors."""


@dataclass
class Row:
    time: datetime
    cols: list[str]
    version: int | None
    project: int | None


def number(value: str, *, integer: bool = True, minimum: float = 0):
    try:
        if integer:
            if not re.fullmatch(r"-?(?:\d+|0x[0-9A-Fa-f]+)", value):
                return None
            result = int(value, 16 if value.startswith("0x") else 10)
        else:
            result = float(value)
        if not math.isfinite(result) or not minimum <= result <= 2**53 - 1:
            return None
        return result
    except (ValueError, OverflowError):
        return None


def flag(value: str):
    return number(value)


def valid_guid(value: str) -> bool:
    return GUID.fullmatch(value) is not None


def fixed_timezone(value: str):
    match = re.fullmatch(r"([+-])(\d{2}):(\d{2})", value)
    if not match:
        raise DataError("log-timezone must be a numeric offset such as +08:00.")
    sign, hours, minutes = match.groups()
    if int(hours) > 14 or int(minutes) > 59 or (int(hours) == 14 and int(minutes)):
        raise DataError("Invalid log timezone offset.")
    delta = timedelta(hours=int(hours), minutes=int(minutes))
    return timezone(delta if sign == "+" else -delta)


def boundary(value: str):
    try:
        result = datetime.fromisoformat(value)
    except ValueError:
        raise DataError("Window boundaries must be ISO-8601 timestamps with offsets.") from None
    if result.tzinfo is None or result.utcoffset() is None:
        raise DataError("Window boundaries require explicit timezone offsets.")
    return result


def read_window(path: Path, start: datetime, end: datetime, log_tz):
    if start >= end:
        raise DataError("Window end must be after its start.")
    rows = []
    versions = set()
    version = project = None
    header_advanced = None
    with path.open("r", encoding="utf-8-sig", errors="strict") as stream:
        for line in stream:
            if len(line.encode("utf-8")) > MAX_LINE_BYTES:
                raise DataError("Log line exceeds the parser limit.")
            match = STAMP.fullmatch(line.rstrip("\r\n"))
            if not match:
                # A damaged timestamp can conceal an in-window event; fail closed.
                if line.strip():
                    raise DataError("Unsupported or malformed native-log timestamp.")
                continue
            date, clock, payload = match.groups()
            try:
                stamp = datetime.strptime(date + " " + clock, "%m/%d/%Y %H:%M:%S.%f" if "." in clock else "%m/%d/%Y %H:%M:%S").replace(tzinfo=log_tz)
            except ValueError:
                raise DataError("Invalid native-log timestamp.") from None
            if not start <= stamp <= end and not payload.startswith("COMBAT_LOG_VERSION,"):
                continue
            try:
                cols = next(csv.reader([payload], strict=True))
            except (csv.Error, StopIteration):
                raise DataError("Malformed CSV in selected log data.") from None
            if not cols:
                raise DataError("Empty combat-log payload.")
            if cols[0] == "COMBAT_LOG_VERSION":
                version = number(cols[1]) if len(cols) > 1 else None
                meta = dict(zip(cols[2::2], cols[3::2]))
                project = number(meta.get("PROJECT_ID", ""))
                header_advanced = number(meta.get("ADVANCED_LOG_ENABLED", ""))
                continue
            if len(rows) >= MAX_WINDOW_ROWS:
                raise DataError("Selected window exceeds the row limit; use a smaller window.")
            if len(cols) < 9:
                # Metadata rows do not describe units and are never exported.
                if cols[0] in ALLOWED:
                    raise DataError("Truncated combat-event header in selected window.")
                continue
            if cols[0] in ALLOWED:
                for at in (3, 7):
                    if flag(cols[at]) is None:
                        raise DataError("Invalid combat-event unit flags.")
                rows.append(Row(stamp, cols, version, project))
                versions.add((version, project, header_advanced))
    return rows, versions


def identify_self(rows: list[Row]):
    candidates = set()
    for row in rows:
        for identity_at, flags_at in ((1, 3), (5, 7)):
            value = flag(row.cols[flags_at])
            # Affiliation MINE, unit type PLAYER. Pets/guardians have other types.
            if value & 0xF == 1 and value & 0xFC00 == 0x400:
                identity = row.cols[identity_at]
                if not valid_guid(identity) or not identity.startswith("Player-"):
                    raise DataError("Self player flags conflict with unit identity type.")
                candidates.add(identity)
    if not candidates:
        raise DataError("No unambiguous self player found in the selected window.")
    if len(candidates) != 1:
        raise DataError("Multiple self players found; select a window with one character.")
    return next(iter(candidates))


def known_layout(row: Row):
    # Validated against the Forever 1.60.1 log-v22/project-18 disk format.
    return row.version == 22 and row.project == 18


def swing_shape(row: Row):
    return known_layout(row) and row.cols[0] in SWINGS and len(row.cols) in (38, 39)


def deduplicate(rows: list[Row]):
    groups = []
    waiting = defaultdict(lambda: {"SWING_DAMAGE": deque(), "SWING_DAMAGE_LANDED": deque()})
    removed = 0
    for row in rows:
        if not swing_shape(row):
            groups.append([row])
            continue
        c = row.cols
        key = (row.time, c[1], c[5], tuple(c[28:]))
        other = "SWING_DAMAGE_LANDED" if c[0] == "SWING_DAMAGE" else "SWING_DAMAGE"
        if waiting[key][other]:
            groups[waiting[key][other].popleft()].append(row)
            removed += 1
        else:
            waiting[key][c[0]].append(len(groups))
            groups.append([row])
    return groups, removed


def analyze_log(path: Path, start: datetime, end: datetime, log_tz):
    rows, formats = read_window(path, start, end, log_tz)
    me = identify_self(rows)
    direct = [r for r in rows if me in (r.cols[1], r.cols[5])]
    associated = {v for r in direct for v in (r.cols[1], r.cols[5]) if valid_guid(v)}
    selected = [r for r in rows if me in (r.cols[1], r.cols[5]) or (r.cols[0] in DEATHS and r.cols[5] in associated)]
    groups, removed = deduplicate(selected)
    aliases = {me: "self"}
    entities = {"self": "player"}
    issues = Counter()

    def alias(value):
        if not valid_guid(value):
            return None
        if value not in aliases:
            name = "target_" + str(len(aliases))
            aliases[value] = name
            entities[name] = {"Player": "player", "Creature": "npc", "Pet": "pet", "Vehicle": "vehicle", "GameObject": "object"}[value.split("-", 1)[0]]
        return aliases[value]

    def put_num(out, name, cols, at, **kwargs):
        if at < len(cols):
            value = number(cols[at], **kwargs)
            if value is not None:
                out[name] = value

    def advanced(row, at):
        c = row.cols
        if len(c) < at + 19 or c[at] not in (c[1], c[5]) or not valid_guid(c[at]):
            return None
        out = {"unit": alias(c[at])}
        for offset, name in ((2, "health"), (3, "healthMax"), (4, "attackPower"), (5, "spellPower"), (6, "armor"), (7, "absorbShield"), (10, "powerType"), (11, "power"), (12, "powerMax"), (13, "powerCostRaw"), (16, "mapId")):
            put_num(out, name, c, at + offset)
        for offset, name in ((14, "worldX"), (15, "worldY"), (17, "facing")):
            put_num(out, name, c, at + offset, integer=False, minimum=-2**53 + 1)
        # The final field is NPC level / player item-level: omit ambiguous meaning.
        return out

    events = []
    for group in groups:
        row = next((r for r in group if r.cols[0] == "SWING_DAMAGE"), group[0])
        c = row.cols
        kind = c[0]
        out = {"time": row.time.isoformat(timespec="microseconds"), "t": round((row.time - start).total_seconds(), 6), "eventType": "SWING_DAMAGE" if kind in SWINGS else kind, "source": alias(c[1]), "target": alias(c[5])}
        out["direction"] = "self" if c[1] == me == c[5] else "outgoing" if c[1] == me else "incoming" if c[5] == me else "related-target"
        prefix = kind.startswith(("SPELL_", "RANGE_", "DAMAGE_"))
        if prefix:
            put_num(out, "spellId", c, 9, minimum=1)
            put_num(out, "spellSchool", c, 11)
        layout = known_layout(row)
        payload_at = None
        adv_at = None
        if kind in SWINGS and swing_shape(row):
            adv_at, payload_at = 9, 28
        elif kind in DAMAGE - SWINGS - {"ENVIRONMENTAL_DAMAGE"} and layout and len(c) in (41, 42):
            adv_at, payload_at = 12, 31
        elif kind == "ENVIRONMENTAL_DAMAGE" and layout and len(c) == 39:
            adv_at, payload_at = 9, 29
            if c[28] in ENVIRONMENT:
                out["environmentType"] = c[28]
        elif kind in HEAL and layout and len(c) == 36:
            adv_at, payload_at = 12, 31
        elif kind in CASTS | RESOURCE and layout and len(c) >= 31:
            # Only these known-size cast/resource layouts get advanced fields.
            if (kind == "SPELL_CAST_SUCCESS" and len(c) == 31) or (kind in RESOURCE and len(c) == 35):
                adv_at = 12
        if adv_at is not None:
            snapshots = [value for r in group if (value := advanced(r, adv_at)) is not None]
            if snapshots:
                out["snapshots"] = snapshots
        if kind in DAMAGE and payload_at is not None:
            for offset, name in ((0, "amount"), (1, "baseAmount"), (3, "damageSchool"), (4, "resisted"), (5, "blocked"), (6, "absorbed")):
                put_num(out, name, c, payload_at + offset)
            put_num(out, "overkill", c, payload_at + 2, minimum=-1)
            for offset, name in ((7, "critical"), (8, "glancing"), (9, "crushing")):
                if c[payload_at + offset] in ("nil", "0", "1"):
                    out[name] = c[payload_at + offset] == "1"
            if kind in SWINGS and len(c) == 39 and c[38] in ("nil", "0", "1"):
                out["offHand"] = c[38] == "1"
            if "amount" in out and "overkill" in out and max(0, out["overkill"]) <= out["amount"]:
                out["effectiveAmount"] = out["amount"] - max(0, out["overkill"])
        elif kind in HEAL and payload_at is not None:
            for offset, name in ((0, "amount"), (1, "baseAmount"), (2, "overhealing"), (3, "absorbed")):
                put_num(out, name, c, payload_at + offset)
            if c[payload_at + 4] in ("nil", "0", "1"):
                out["critical"] = c[payload_at + 4] == "1"
            if all(k in out for k in ("amount", "overhealing", "absorbed")) and out["absorbed"] == 0 and out["overhealing"] <= out["amount"]:
                out["effectiveAmount"] = out["amount"] - out["overhealing"]
            elif out.get("absorbed", 0) != 0:
                issues["healing_absorb_semantics_unverified"] += 1
        elif kind in RESOURCE and layout and len(c) == 35:
            for at, name in ((31, "resourceAmount"), (32, "resourceExcess"), (33, "resourceType"), (34, "resourceMaximum")):
                put_num(out, name, c, at, integer=False)
        if kind in DAMAGE | HEAL and payload_at is None:
            issues["unsupported_or_missing_numeric_payload"] += 1
        if kind in MISSED:
            at = 9 if kind == "SWING_MISSED" else 12
            if len(c) > at and c[at] in MISS_TYPES:
                out["missType"] = c[at]
        if kind in CONTROL or kind == "SPELL_AURA_BROKEN_SPELL":
            put_num(out, "extraSpellId", c, 12, minimum=1)
            put_num(out, "extraSpellSchool", c, 14)
        if kind in AURAS | CONTROL:
            at = 15 if kind in CONTROL | {"SPELL_AURA_BROKEN_SPELL"} else 12
            if len(c) > at and c[at] in ("BUFF", "DEBUFF"):
                out["auraType"] = c[at]
            if kind.endswith("_DOSE"):
                put_num(out, "stacks", c, at + 1)
        events.append(out)

    def metric(kinds, outgoing, excess):
        field = "source" if outgoing else "target"
        relevant = [e for e in events if e["eventType"] in kinds and e[field] == "self"]
        result = {"observedEvents": len(relevant), "eventsWithAmount": sum("amount" in e for e in relevant)}
        for output_key, value_key in (("total", "amount"), ("effective", "effectiveAmount"), (excess, excess)):
            values = [max(0, e[value_key]) for e in relevant if value_key in e]
            result[output_key] = sum(values) if relevant and len(values) == len(relevant) else None
        result["coverage"] = "not-observed" if not relevant else "complete-for-observed-events" if result["effective"] is not None else "partial"
        return result

    summary = {
        "outgoingDamage": metric(DAMAGE - {"SWING_DAMAGE_LANDED", "DAMAGE_SPLIT"}, True, "overkill"),
        "incomingDamage": metric(DAMAGE - {"SWING_DAMAGE_LANDED"}, False, "overkill"),
        "outgoingHealing": metric(HEAL, True, "overhealing"),
        "incomingHealing": metric(HEAL, False, "overhealing"),
        "eventCounts": dict(sorted(Counter(e["eventType"] for e in events).items())),
        "incomingMisses": dict(sorted(Counter(e["missType"] for e in events if e.get("target") == "self" and "missType" in e).items())),
    }
    return {
        "schema": 1, "mode": "postcombat-only", "source": "native-disk-combat-log",
        "window": {"start": start.isoformat(), "end": end.isoformat(), "inclusive": True, "logTimezone": str(log_tz)},
        "identity": {"selfPlayers": 1, "rule": "unique-mine-affiliation-player-type-and-player-guid", "petAttribution": "excluded"},
        "formats": [{"logVersion": v, "projectId": p, "headerAdvancedLogging": a} for v, p, a in sorted(formats, key=str)],
        "entities": entities, "deduplicatedSwingRows": removed,
        "issues": dict(sorted(issues.items())),
        "limits": {"unobservedMeansUnknown": True, "noExpectedRotationAssumed": True, "aurasDoNotProveCrowdControl": True, "timeWindowIsNotCombatBoundary": True, "nativeTimestampsUsedLiterally": True, "healingAbsorbEffectiveAmount": "omitted-unless-absorbed-is-zero"},
        "summary": summary, "events": events,
    }


def write_report(output: Path, report, force: bool):
    # Atomic, owner-only temporary file; never leave raw data on disk.
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=output.parent, prefix=".coach-", suffix=".json", delete=False) as stream:
            temp_name = stream.name
            json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
        if force:
            os.replace(temp_name, output)
        else:
            os.link(temp_name, output)
    finally:
        if temp_name is not None:
            Path(temp_name).unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Export one explicit native-log window as anonymous, local postcombat-only JSON.")
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--start", required=True)
    parser.add_argument("--end", required=True)
    parser.add_argument("--log-timezone", required=True, help="Fixed timezone offset of the native file, e.g. +08:00")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--force", action="store_true", help="Replace an existing JSON report")
    args = parser.parse_args(argv)
    try:
        if args.output.suffix.lower() != ".json":
            raise DataError("Output must be a local .json file.")
        if args.log.resolve() == args.output.resolve() or (args.output.exists() and os.path.samefile(args.log, args.output)):
            raise DataError("Output must not replace the input log.")
        report = analyze_log(args.log, boundary(args.start), boundary(args.end), fixed_timezone(args.log_timezone))
        write_report(args.output, report, args.force)
        print(json.dumps({"mode": report["mode"], "events": len(report["events"]), "summary": report["summary"]}, ensure_ascii=False))
        return 0
    except DataError as error:
        print("coach_combat_log: " + str(error), file=sys.stderr)
    except FileExistsError:
        print("coach_combat_log: Output already exists; use --force to replace the JSON report.", file=sys.stderr)
    except (OSError, UnicodeError, csv.Error):
        print("coach_combat_log: Cannot safely read the log or write the local report.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
