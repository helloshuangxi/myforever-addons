"""Validate the Coach prototype in Lua 5.1; these are simulated checks only."""
from pathlib import Path
import json
import runpy
import os

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "_forever_/Interface/AddOns/MyForeverCoach"


def main():
    os.chdir(ROOT)
    sources = sorted(ADDON.glob("*.lua"))
    if not sources:
        raise SystemExit("Coach source files are missing.")
    runtime = LuaRuntime(unpack_returned_tuples=True)
    compile_lua = runtime.eval(
        "function(text, name) local chunk, err = loadstring(text, name); "
        "assert(chunk, err); return true end"
    )
    for source in sources:
        compile_lua(source.read_text(encoding="utf-8"), "@" + str(source))
    print(f"Coach Lua 5.1 syntax: {len(sources)} files passed", flush=True)
    runtime = LuaRuntime(unpack_returned_tuples=True)
    exported = runtime.execute((ROOT / "PersonalAddons/tests/coach_test.lua").read_text(encoding="utf-8"))
    payload = json.loads(exported)
    if not isinstance(payload, dict):
        raise AssertionError("Export must be a JSON object.")
    if not isinstance(payload.get("records"), list) or not isinstance(payload.get("errors"), list):
        raise AssertionError("Export records and errors must be JSON arrays.")
    if not isinstance(payload.get("capabilities"), dict):
        raise AssertionError("Export capabilities must be a JSON object.")
    print("Coach export: parsed by an independent JSON decoder", flush=True)
    behavior_runtime = LuaRuntime(unpack_returned_tuples=True)
    behavior_export = behavior_runtime.execute((ROOT / "PersonalAddons/tests/behavior_test.lua").read_text(encoding="utf-8"))
    behavior_payload = json.loads(behavior_export)
    behavior = behavior_payload.get("behavior")
    if not isinstance(behavior, dict) or behavior.get("dayBasis") != "UTC+08:00":
        raise AssertionError("Behavior export must contain the fixed daily schema.")
    for day in behavior["days"].values():
        if not isinstance(day.get("spells"), dict) or not isinstance(day.get("maps"), dict):
            raise AssertionError("Behavior distributions must be JSON objects with string IDs.")
    print("Behavior export: explicit daily fields parsed by an independent JSON decoder", flush=True)
    report_tool = runpy.run_path(str(ROOT / "PersonalAddons/tools/coach_report.py"))
    report = report_tool["summarize"]({
        "schema": 1, "version": "0.1.2", "startedAt": 1800000000, "duration": 10,
        "client": {}, "capabilities": {},
        "records": [{"kind": "snapshot", "context": "idle", "t": 0, "data": {"combat": False}}],
        "receivedEvents": {"UNIT_SPELLCAST_SUCCEEDED": {"count": 2, "firstAt": 1, "lastAt": 2,
                                                       "payload": "FORBIDDEN_REPORT_PAYLOAD"}},
        "registrationChecks": {"UNIT_SPELLCAST_SUCCEEDED": "not_registered"},
        "filterCounts": {"unit_restricted": 2, "FORBIDDEN_PRIVATE_REASON": 1},
    })
    for expected in ("未实际注册", "单位参数受限", "入口共收到 2 次", "记录覆盖范围：0.00秒",
                     "不能对输出循环或控制循环作出结论", "也不能据此否定玩家实际发生过战斗"):
        if expected not in report:
            raise AssertionError(f"Report diagnostic missing: {expected}")
    if "FORBIDDEN_" in report:
        raise AssertionError("Report included an arbitrary diagnostic payload/reason.")
    print("Coach report: 7 diagnostic/absence-of-combat checks passed", flush=True)
    print("Coach simulated checks passed. Actual client validation is separate.", flush=True)


if __name__ == "__main__":
    main()
