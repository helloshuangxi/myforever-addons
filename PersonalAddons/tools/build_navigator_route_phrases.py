"""Build the add-on and web copies of the maintained route phrase dictionary.

Edit PersonalAddons/data/navigator-route-phrases.json, run this script, and
review the generated diff. --check verifies both delivered copies without writes.
Aliases are authored examples, never records from players or model responses.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "PersonalAddons/data/navigator-route-phrases.json"
LUA = ROOT / "_forever_/Interface/AddOns/MyForeverNavigator/RoutePhrases.lua"
WEB = ROOT / "PersonalAddons/website/public/navigator/planner/phrases.json"


def phrase_key(value):
    return re.sub(r"[ ?？.。]+$", "", re.sub(r" +", " ", value.strip()).lower())


def validate(data):
    if set(data) != {"version", "phrases"} or type(data["version"]) is not int or data["version"] != 1:
        raise ValueError("Expected a version 1 phrase dictionary")
    rows = data["phrases"]
    if not isinstance(rows, list) or not rows:
        raise ValueError("Expected a nonempty list of phrase entries")
    known = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"aliases", "terms"}:
            raise ValueError("Each entry must contain only aliases and terms")
        aliases, terms = row["aliases"], row["terms"]
        if not isinstance(aliases, list) or not aliases or not isinstance(terms, list) or not 1 <= len(terms) <= 6:
            raise ValueError("An entry needs aliases and one to six ordered terms")
        for phrase in aliases + terms:
            if not isinstance(phrase, str) or not phrase or phrase != phrase.strip() or not phrase.isprintable():
                raise ValueError(f"Invalid text: {phrase!r}")
            if any(ch in phrase for ch in '~|<>/\\') or len(phrase.encode()) > 180:
                raise ValueError(f"Disallowed or oversized phrase: {phrase!r}")
        for term in terms:
            if not re.fullmatch(r"[\w \-\u0080-\U0010ffff]+", term) or term.isdigit() or len(term.encode()) > 64:
                raise ValueError(f"Invalid search term: {term!r}")
        for alias in aliases:
            key = phrase_key(alias)
            if not key or key in known:
                raise ValueError(f"Duplicate or empty normalized alias: {alias!r}")
            known.add(key)
    return rows


def lua_array(values):
    return "{" + ", ".join(json.dumps(v, ensure_ascii=False) for v in values) + "}"


def build(check):
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    rows = validate(data)
    lines = ["-- Generated from PersonalAddons/data/navigator-route-phrases.json.",
             "local _, NS = ...", "NS.SharedRoutePhrases = {"]
    for row in rows:
        lines.append("    {aliases=" + lua_array(row["aliases"]) + ", terms=" + lua_array(row["terms"]) + "},")
    lines.append("}")
    files = {LUA: "\n".join(lines) + "\n",
             WEB: json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n"}
    for path, expected in files.items():
        if check:
            if not path.is_file() or path.read_bytes() != expected.encode():
                raise SystemExit(f"Out of date: {path.relative_to(ROOT)}")
        else:
            path.write_bytes(expected.encode())
    print(f"{len(rows)} routes, {sum(len(row['aliases']) for row in rows)} shared phrasings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
