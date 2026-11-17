"""Export names and map labels already distributed with the Navigator static catalogue."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / '_forever_/Interface/AddOns/MyForeverNavigator/Data.lua'
TRANSIT = DATA.with_name('RouteData.lua')
PLANNER = ROOT / 'PersonalAddons/website/public/navigator/planner'


def build():
    rows = [line for line in DATA.read_text().splitlines() if re.match(r'\s*\{id = "npc-', line)]
    names, zones = {}, set()
    for line in rows:
        fields = dict(re.findall(r'(name|english|zone) = ("(?:\\.|[^"\\])*")', line))
        name, english, zone = (json.loads(fields[key]) for key in ('name', 'english', 'zone'))
        names.setdefault(name, set()).add(english)
        zones.add(zone)
    if not names or not zones:
        raise ValueError('No curated names found')
    stops = re.findall(r'\{"[a-z0-9-]+","([^"]+)","([^"]+)",\d+,', TRANSIT.read_text())
    if not stops:
        raise ValueError('No transit stop names found')
    content = {'stops': stops, 'zones': sorted(zones), 'npcs': [[n, *sorted(names[n])] for n in sorted(names)]}
    target = PLANNER / 'catalog.json'
    target.write_text(json.dumps(content, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{len(rows)} points, {len(names)} names, {len(zones)} maps, {len(stops)} transit points')


if __name__ == '__main__':
    build()
