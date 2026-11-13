"""Summarize a Coach JSON export or its own SavedVariables without executing Lua.

The SavedVariables reader accepts one MyForeverCoachDB assignment containing only
literal tables, strings, finite numbers, booleans, and nil. It never imports or
executes input code. Printed reports omit character names, GUIDs, and raw payloads.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import re


MAX_BYTES = 8 * 1024 * 1024
MAX_ITEMS = 1_000_000
CAPTIONS = {
    "health": "生命值", "power": "资源", "position": "地图坐标", "xp": "经验",
    "quests": "任务", "spells": "已学技能", "cooldown": "冷却", "auras": "玩家光环",
    "player_cast": "玩家施法", "combat_log": "战斗日志事件", "target_cast": "目标读条",
    "restrictions": "限制状态", "combat_logging": "磁盘战斗日志开关",
}
CONTEXTS = {"idle": "脱战", "combat": "战斗", "instance": "副本", "pvp": "PvP"}
FIELDS = {
    "health": "当前生命", "healthMax": "最大生命", "power": "当前资源", "powerMax": "最大资源",
    "powerType": "资源类型", "mapID": "地图ID", "coordinates": "坐标对象", "x": "横坐标", "y": "纵坐标",
    "level": "等级", "xp": "当前经验", "xpMax": "升级所需经验", "rested": "休息经验",
    "questCount": "任务数", "entryCount": "任务条目数", "questID": "任务ID", "spellID": "法术ID",
    "startTime": "冷却/读条开始", "duration": "冷却/读条时长", "isEnabled": "冷却可用标志", "modRate": "冷却倍率",
    "targetExists": "目标存在标志", "interruptible": "可打断标志", "castTimeMS": "施法时间",
    "state": "限制状态", "Combat": "战斗限制", "Encounter": "首领战限制", "ChallengeMode": "挑战限制",
    "PvPMatch": "PvP限制", "Map": "地图限制", "Chat": "聊天限制状态", "logging": "磁盘日志开关",
    "restrictionState": "战斗日志限制状态", "eventType": "限制类型事件", "eventState": "限制状态事件",
    "acceptedID": "接取任务ID", "turnedInID": "交付任务ID", "levelUp": "升级事件",
    "amount": "伤害/治疗数值", "extraSpellID": "被打断法术ID", "selfSource": "自己是来源", "selfTarget": "自己是目标",
}
EVENTS = (
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_POWER_UPDATE", "UNIT_HEALTH",
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "UNIT_AURA", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
    "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_TARGET_CHANGED", "ADDON_RESTRICTION_STATE_CHANGED",
    "COMBAT_LOG_EVENT_UNFILTERED",
)
FILTERS = {
    "paused": "采集已暂停", "stopped": "会话已结束", "full": "记录容量已满", "invalid_kind": "记录类型无效",
    "written": "已写入记录", "unit_restricted": "单位参数受限", "unit_missing": "单位参数缺失",
    "other_unit": "并非玩家单位", "spell_id_restricted": "法术ID受限", "spell_id_missing": "法术ID缺失",
    "combat_state_mismatch": "公开战斗状态纠正事件状态", "safety_stopped": "接口拦截后停用",
    "unknown_event": "未知事件", "throttled": "已节流", "handler_error": "事件处理失败",
}
REGISTRATION_LABELS = {
    "confirmed": "已核验注册", "not_registered": "未实际注册", "missing": "无核验接口", "error": "核验报错",
    "disabled_restricted": "已停用（受限接口）",
}


class DataError(ValueError):
    pass


class LiteralReader:
    """A deliberately small parser for Blizzard's literal SavedVariables syntax."""

    def __init__(self, source: str):
        self.source = source
        self.pos = 0
        self.items = 0

    def skip(self):
        while self.pos < len(self.source):
            if self.source[self.pos].isspace():
                self.pos += 1
            elif self.source.startswith("--", self.pos):
                end = self.source.find("\n", self.pos)
                self.pos = len(self.source) if end < 0 else end + 1
            else:
                break

    def take(self, token: str):
        self.skip()
        if not self.source.startswith(token, self.pos):
            raise DataError(f"Unsupported SavedVariables syntax at offset {self.pos}.")
        self.pos += len(token)

    def read(self):
        self.take("MyForeverCoachDB")
        self.take("=")
        result = self.value(0)
        self.skip()
        if self.pos < len(self.source) and self.source[self.pos] == ";":
            self.pos += 1
        self.skip()
        if self.pos != len(self.source):
            raise DataError("Only one literal MyForeverCoachDB assignment is accepted.")
        return result

    def string(self):
        quote = self.source[self.pos]
        self.pos += 1
        result = []
        escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}
        while self.pos < len(self.source):
            char = self.source[self.pos]
            self.pos += 1
            if char == quote:
                return "".join(result)
            if char == "\\":
                if self.pos >= len(self.source):
                    break
                escaped = self.source[self.pos]
                self.pos += 1
                if escaped.isdigit():
                    digits = escaped
                    for _ in range(2):
                        if self.pos < len(self.source) and self.source[self.pos].isdigit():
                            digits += self.source[self.pos]
                            self.pos += 1
                        else:
                            break
                    number = int(digits)
                    if number > 255:
                        raise DataError("Invalid Lua decimal escape.")
                    result.append(chr(number))
                elif escaped in escapes:
                    result.append(escapes[escaped])
                elif escaped in ("\\", '"', "'", "\n"):
                    result.append(escaped)
                else:
                    raise DataError("Unsupported Lua escape sequence.")
            elif char in ("\n", "\r"):
                raise DataError("Unescaped newline in SavedVariables string.")
            else:
                result.append(char)
        raise DataError("Unterminated SavedVariables string.")

    def value(self, depth: int):
        if depth > 45:
            raise DataError("SavedVariables nesting limit exceeded.")
        self.items += 1
        if self.items > MAX_ITEMS:
            raise DataError("SavedVariables item limit exceeded.")
        self.skip()
        if self.pos >= len(self.source):
            raise DataError("Unexpected end of SavedVariables.")
        char = self.source[self.pos]
        if char in ('"', "'"):
            return self.string()
        if char == "{":
            self.pos += 1
            result = {}
            next_index = 1
            while True:
                self.skip()
                if self.pos >= len(self.source):
                    raise DataError("Unterminated SavedVariables table.")
                if self.source[self.pos] == "}":
                    self.pos += 1
                    if result and set(result) == set(range(1, len(result) + 1)):
                        return [result[i] for i in range(1, len(result) + 1)]
                    return result
                if self.source[self.pos] == "[":
                    self.pos += 1
                    key = self.value(depth + 1)
                    if type(key) not in (str, int):
                        raise DataError("Only string/integer table keys are accepted.")
                    self.take("]")
                    self.take("=")
                else:
                    match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=", self.source[self.pos:])
                    if match:
                        key = match.group(1)
                        self.pos += match.end()
                    else:
                        key = next_index
                        next_index += 1
                if key in result:
                    raise DataError("Duplicate SavedVariables key.")
                result[key] = self.value(depth + 1)
                self.skip()
                if self.pos < len(self.source) and self.source[self.pos] in (",", ";"):
                    self.pos += 1
                elif self.pos >= len(self.source) or self.source[self.pos] != "}":
                    raise DataError("Expected SavedVariables table separator.")
        for token, value in (("true", True), ("false", False), ("nil", None)):
            if self.source.startswith(token, self.pos):
                end = self.pos + len(token)
                if end == len(self.source) or not (self.source[end].isalnum() or self.source[end] == "_"):
                    self.pos = end
                    return value
        match = re.match(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", self.source[self.pos:])
        if match:
            token = match.group(0)
            self.pos += len(token)
            if "x" in token.lower():
                number = int(token, 16)
            else:
                number = float(token) if any(c in token for c in ".eE") else int(token)
            if isinstance(number, float) and not math.isfinite(number):
                raise DataError("Non-finite number in SavedVariables.")
            return number
        raise DataError(f"Executable or unsupported SavedVariables value at offset {self.pos}.")


def read_data(path: Path, data_format="auto"):
    if path.stat().st_size > MAX_BYTES:
        raise DataError("Input is larger than 8 MiB.")
    source = path.read_text(encoding="utf-8-sig")
    if data_format == "savedvariables" or (data_format == "auto" and source.lstrip().startswith("MyForeverCoachDB")):
        return LiteralReader(source).read()
    def finite_float(token):
        value = float(token)
        if not math.isfinite(value):
            raise DataError("Non-finite JSON number.")
        return value

    try:
        return json.loads(source, parse_float=finite_float,
                          parse_constant=lambda _: (_ for _ in ()).throw(DataError("Non-finite JSON number.")))
    except json.JSONDecodeError as error:
        raise DataError(f"Invalid JSON at line {error.lineno}, column {error.colno}.") from None
    except ValueError as error:
        if isinstance(error, DataError):
            raise
        raise DataError("Invalid JSON number.") from None


def count(value):
    return value if type(value) is int and 0 <= value <= 10**12 else 0


def scalar(value, fallback="未知"):
    if type(value) is int and abs(value) <= 10**15:
        return str(value)
    if type(value) is float and math.isfinite(value) and abs(value) <= 10**15:
        return str(value)
    if isinstance(value, str) and len(value) <= 80 and re.fullmatch(r"[A-Za-z0-9_.:/ -]+", value):
        return value
    return fallback


def select_session(data, selection="latest"):
    if not isinstance(data, dict):
        raise DataError("Expected a Coach JSON object or SavedVariables table.")
    if isinstance(data.get("session"), dict):
        sessions = [data["session"]]
    elif "sessions" in data:
        sessions = data["sessions"]
        if isinstance(sessions, dict):
            sessions = [value for _, value in sorted(sessions.items(), key=lambda pair: str(pair[0])) if isinstance(value, dict)]
    else:
        sessions = [data]
    if not isinstance(sessions, list) or not sessions:
        raise DataError("No saved Coach sessions were found.")
    if selection == "latest":
        session = sessions[-1]
    else:
        session = next((s for s in sessions if isinstance(s, dict) and str(s.get("id")) == selection), None)
    if not isinstance(session, dict) or not isinstance(session.get("capabilities"), dict):
        raise DataError("The selected session has no capability observations.")
    if session.get("schema", data.get("schema")) != 1:
        raise DataError("Unsupported Coach schema; expected schema 1.")
    return session


def diagnostic_lines(session):
    def number(value):
        if type(value) in (int, float) and 0 <= value <= 10**12 and math.isfinite(value):
            return value
        return None

    def elapsed(value):
        value = number(value)
        return "—" if value is None else f"{value:.2f}秒"

    def timestamp(value):
        value = number(value)
        if value is None:
            return "未知"
        try:
            return datetime.fromtimestamp(value, timezone(timedelta(hours=8))).strftime("%Y-%m-%d %H:%M:%S")
        except (ValueError, OSError, OverflowError):
            return "未知"

    records = session.get("records", [])
    records = records if isinstance(records, list) else list(records.values()) if isinstance(records, dict) else []
    records = [row for row in records if isinstance(row, dict)]
    times = [number(row.get("t")) for row in records]
    times = [value for value in times if value is not None]
    received = session.get("receivedEvents", {})
    received = received if isinstance(received, dict) else {}
    checks = session.get("registrationChecks", {})
    checks = checks if isinstance(checks, dict) else {}
    processed = session.get("eventCounts", {})
    processed = processed if isinstance(processed, dict) else {}
    filters = session.get("filterCounts", {})
    filters = filters if isinstance(filters, dict) else {}
    event_rows, received_total = [], 0
    for event in EVENTS:
        entry = received.get(event)
        entry = entry if isinstance(entry, dict) else {}
        arrived = count(entry.get("count"))
        handled = count(processed.get(event))
        registration = checks.get(event)
        received_total += arrived
        if arrived or handled or registration is not None:
            label = REGISTRATION_LABELS.get(registration, "未核验") if isinstance(registration, str) else "未核验"
            event_rows.append(f"| {event} | {label} | {arrived} | {elapsed(entry.get('firstAt'))} | {elapsed(entry.get('lastAt'))} | {handled} |")
    lines = [
        "采集链路：注册核验 → 入口收件 → 过滤计数 → 写入记录。注册调用返回成功不等于事件已实际注册。",
        f"会话时间（北京时间）：{timestamp(session.get('startedAt'))} → {timestamp(session.get('endedAt'))}；会话时长 {elapsed(session.get('duration'))}。",
        f"记录覆盖范围：{elapsed(min(times)) if times else '未知'} → {elapsed(max(times)) if times else '未知'}（相对会话开始）。",
        f"入口共收到 {received_total} 次受控事件；最终保存 {len(records)} 条记录。暂停期间仍可记入口诊断，不保存事件 payload。",
        "",
    ]
    if event_rows:
        lines += ["| 事件 | 注册核验 | 入口收到 | 最早收到 | 最近收到 | 进入处理计数 |",
                  "| --- | --- | ---: | ---: | ---: | ---: |", *event_rows, ""]
    else:
        lines += ["本会话没有入口收件或注册核验诊断；旧版本缺少此层记录，不能据此推断事件未发生。", ""]
    filter_rows = []
    for reason, label in FILTERS.items():
        value = count(filters.get(reason))
        if value:
            filter_rows.append(f"| {reason} | {label} | {value} |")
    if filter_rows:
        lines += ["| 过滤/写入原因 | 含义 | 次数 |", "| --- | --- | ---: |", *filter_rows, ""]
    else:
        lines += ["过滤/写入原因尚无计数；缺少此诊断不等于没有过滤。", ""]
    contexts = {key: sum(row.get("context") == key for row in records) for key in CONTEXTS}
    lines.append("最终记录场景：" + "；".join(f"{CONTEXTS[key]} {value}条" for key, value in contexts.items()) + "。")
    regen = received.get("PLAYER_REGEN_DISABLED")
    battle = isinstance(regen, dict) and count(regen.get("count")) > 0
    for record in records:
        data = record.get("data") if isinstance(record.get("data"), dict) else {}
        if (record.get("context") == "combat" or data.get("combat") is True
                or data.get("lockdown") is True or data.get("affectingCombat") is True
                or (record.get("kind") == "combat" and data.get("phase") == "enter")):
            battle = True
            break
    if battle:
        lines.append("本会话观测到进战事件或公开战斗标志；仍须核对有效玩家技能记录，才能分析输出或控制循环。")
    else:
        lines.append("本会话没有可核对的战斗迹象，不能对输出循环或控制循环作出结论，也不能据此否定玩家实际发生过战斗。")
    return lines


def summarize(session):
    client = session.get("client") if isinstance(session.get("client"), dict) else {}
    records = session.get("records", [])
    record_count = len(records) if isinstance(records, (dict, list)) else 0
    lines = [
        "# 我的无限 · 采集能力报告",
        "",
        f"客户端：{scalar(client.get('version'))} / build {scalar(client.get('build'))}；接口 {scalar(client.get('interface'))}。",
        f"采集器版本：{scalar(session.get('version'))}；记录 {record_count} 条；达到容量后丢弃 {count(session.get('dropped'))} 条。",
        "来源是输入会话数据；实机、模拟及测试动作范围应另见对应验收记录。未观察到不代表不支持。",
        "",
        "| 能力 | 场景 | 结果 | 可读 | 受限 | 缺失 | 错误 | 观察 |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    lines[5:5] = diagnostic_lines(session) + [""]
    safety_stop = session.get("safetyStop")
    if isinstance(safety_stop, dict):
        event = safety_stop.get("event")
        if event in ("ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED"):
            lines[5:5] = [f"接口安全停止：{event}；函数 {scalar(safety_stop.get('func'))}。本次采样已暂停。", ""]
    caps = session["capabilities"]
    def row_status(row):
        values = [count(row.get(k)) for k in ("readable", "restricted", "missing", "error", "observed")]
        readable, restricted, missing, error, observed = values
        if readable and restricted:
            status = "部分可读，部分受限"
        elif readable:
            status = "已读到公开字段"
        elif restricted:
            status = "受限"
        elif error:
            status = "读取或注册失败"
        elif missing:
            status = "未取得字段"
        elif observed:
            status = "仅观察到事件"
        else:
            status = "待观察"
        return status, values

    for key, caption in CAPTIONS.items():
        cap = caps.get(key, {})
        if isinstance(cap, dict) and cap.get("disabled") is True:
            reason = scalar(cap.get("reason"), "unspecified")
            lines.append(f"| {caption} | — | 已停用（受限接口）；{reason} | 0 | 0 | 0 | 0 | 0 |")
            continue
        contexts = cap.get("contexts", {}) if isinstance(cap, dict) else {}
        found = False
        for context, label in CONTEXTS.items():
            row = contexts.get(context) if isinstance(contexts, dict) else None
            if not isinstance(row, dict):
                continue
            status, values = row_status(row)
            lines.append(f"| {caption} | {label} | {status} | " + " | ".join(map(str, values)) + " |")
            found = True
        if not found:
            lines.append(f"| {caption} | — | 待观察 | 0 | 0 | 0 | 0 | 0 |")
    detail_rows = []
    for key, caption in CAPTIONS.items():
        cap = caps.get(key, {})
        if isinstance(cap, dict) and cap.get("disabled") is True:
            continue
        fields = cap.get("fields", {}) if isinstance(cap, dict) else {}
        if not isinstance(fields, dict):
            continue
        for field, label in FIELDS.items():
            entry = fields.get(field)
            if not isinstance(entry, dict):
                continue
            contexts = entry.get("contexts")
            rows = contexts.items() if isinstance(contexts, dict) and contexts else [(None, entry)]
            for context, row in rows:
                if not isinstance(row, dict) or (context is not None and context not in CONTEXTS):
                    continue
                status, values = row_status(row)
                if not any(values):
                    continue
                scene = CONTEXTS.get(context, "全部")
                detail_rows.append(f"| {caption} | {label} | {scene} | {status} | " + " | ".join(map(str, values[:4])) + " |")
    if detail_rows:
        lines += ["", "字段观察如下；同一能力中一个公开标志可读，不代表其他数值也可读。", "",
                  "| 能力 | 字段 | 场景 | 结果 | 可读 | 受限 | 缺失 | 错误 |",
                  "| --- | --- | --- | --- | ---: | ---: | ---: | ---: |", *detail_rows]
    combat_log = caps.get("combat_log")
    if isinstance(combat_log, dict) and combat_log.get("disabled") is True:
        lines += ["", "战斗日志事件采集已停用：不注册 CLEU，也不读取 CombatLogGetCurrentEventInfo；公开限制状态的读取不代表事件数据可采。磁盘日志需另行验证。"]
    lines += ["", "这些计数描述采集能力，不等于输出质量、漏打断次数或玩家失误。"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Coach JSON or its own SavedVariables file")
    parser.add_argument("--format", choices=("auto", "json", "savedvariables"), default="auto")
    parser.add_argument("--session", default="latest", help="latest or an exact session id")
    parser.add_argument("--output", type=Path, help="Write Markdown report instead of printing")
    parser.add_argument("--json-output", type=Path, help="Write the selected session as JSON; keep private")
    args = parser.parse_args()
    try:
        session = select_session(read_data(args.input, args.format), args.session)
        report = summarize(session)
        if args.output:
            args.output.write_text(report, encoding="utf-8")
        else:
            print(report, end="")
        if args.json_output:
            args.json_output.write_text(json.dumps(session, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    except (OSError, UnicodeError, DataError, RecursionError) as error:
        parser.exit(2, f"Coach report error: {error}\n")


if __name__ == "__main__":
    main()
