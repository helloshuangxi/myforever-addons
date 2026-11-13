"""Synthetic parser fixtures only; never bundle real combat logs in tests."""
from contextlib import redirect_stderr, redirect_stdout
import csv
from datetime import timedelta
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("coach_combat_log", Path(__file__).resolve().parents[1] / "tools/coach_combat_log.py")
coach = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = coach
SPEC.loader.exec_module(coach)

ME, MOB, OTHER, PET = "Player-1-AAAA", "Creature-0-1-2-3-BBBB", "Player-2-CCCC", "Pet-0-1-DDDD"
NAMES = ("PRIVATE_SELF_NAME", "PRIVATE_OTHER_NAME,WITH_COMMA", "PRIVATE_SPELL_NAME", "PRIVATE_CHAT_TEXT")
START = coach.boundary("2026-11-08T11:28:20+08:00")
END = coach.boundary("2026-11-08T11:29:25+08:00")
TZ = coach.fixed_timezone("+08:00")


def base(kind, source=ME, target=MOB, source_flags="0x511", target_flags="0x10a28"):
    return [kind, source, NAMES[0], source_flags, "0x80000000", target, NAMES[1], target_flags, "0x80000000"]


def advanced(unit, hp=232):
    return [unit, coach.ZERO_GUID, hp, 232, 102, 0, 313, 0, 0, 0, 0, 245, 245, 20, -5610.73, -374.77, 1426, 5.2334, 2]


def spell_damage(amount=27, overkill=-1, source=ME, target=MOB, source_flags="0x511", target_flags="0x10a28"):
    return base("SPELL_DAMAGE", source, target, source_flags, target_flags) + [20187, NAMES[2], "0x2"] + advanced(target) + [amount, amount, overkill, 2, 0, 0, 0, "nil", "nil", "nil", "ST"]


def swing(kind="SWING_DAMAGE", amount=20, overkill=7, source=ME, target=MOB, source_flags="0x511", target_flags="0x10a28"):
    info = source if kind == "SWING_DAMAGE" else target
    return base(kind, source, target, source_flags, target_flags) + advanced(info) + [amount, amount + 2, overkill, 1, 0, 0, 0, "nil", "nil", "nil"]


def heal(amount=84, overhealing=84, absorbed=0, base_amount=None):
    return base("SPELL_HEAL", target=ME, target_flags="0x511") + [639, NAMES[2], "0x2"] + advanced(ME) + [amount, amount if base_amount is None else base_amount, overhealing, absorbed, "nil"]


def line(clock, columns):
    data = io.StringIO()
    csv.writer(data, lineterminator="").writerow(columns)
    return "11/8/2026 " + clock + "  " + data.getvalue() + "\n"


class NativeLogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "private-source.txt"

    def fixture(self, entries, version=22, header=True):
        contents = line("11:28:00.0008", ["COMBAT_LOG_VERSION", version, "ADVANCED_LOG_ENABLED", 0, "BUILD_VERSION", "1.60.1", "PROJECT_ID", 18]) if header else ""
        self.path.write_text(contents + "".join(line(clock, cols) for clock, cols in entries), encoding="utf-8")
        return coach.analyze_log(self.path, START, END, TZ)

    def test_swing_pair_counted_once_and_both_snapshots_retained(self):
        result = self.fixture([("11:28:42.0588", swing()), ("11:28:42.0588", swing("SWING_DAMAGE_LANDED"))])
        self.assertEqual(result["deduplicatedSwingRows"], 1)
        self.assertEqual(len(result["events"]), 1)
        self.assertEqual(len(result["events"][0]["snapshots"]), 2)
        self.assertEqual(result["summary"]["outgoingDamage"], {"observedEvents": 1, "eventsWithAmount": 1, "total": 20, "effective": 13, "overkill": 7, "coverage": "complete-for-observed-events"})

    def test_reverse_order_and_landed_only(self):
        result = self.fixture([("11:28:42.0588", swing("SWING_DAMAGE_LANDED")), ("11:28:42.0588", swing()), ("11:28:43.0588", swing("SWING_DAMAGE_LANDED", 9, -1))])
        self.assertEqual(result["summary"]["outgoingDamage"]["total"], 29)
        self.assertEqual(result["summary"]["outgoingDamage"]["effective"], 22)

    def test_same_type_identical_hits_are_not_collapsed(self):
        result = self.fixture([("11:28:42.0588", swing()), ("11:28:42.0588", swing()), ("11:28:42.0588", swing("SWING_DAMAGE_LANDED")), ("11:28:42.0588", swing("SWING_DAMAGE_LANDED"))])
        self.assertEqual(result["summary"]["outgoingDamage"]["observedEvents"], 2)
        self.assertEqual(result["deduplicatedSwingRows"], 2)

    def test_healing_overheal_and_actual_not_base_amount(self):
        result = self.fixture([("11:28:50.0008", heal(150, 50, base_amount=100)), ("11:28:51.0008", heal())])
        metric = result["summary"]["outgoingHealing"]
        self.assertEqual((metric["total"], metric["overhealing"], metric["effective"]), (234, 134, 100))

    def test_absorbed_healing_effective_not_guessed(self):
        result = self.fixture([("11:28:50.0008", heal(150, 50, 10))])
        self.assertNotIn("effectiveAmount", result["events"][0])
        self.assertIsNone(result["summary"]["outgoingHealing"]["effective"])

    def test_pet_and_nearby_player_not_credited(self):
        result = self.fixture([("11:28:31.0008", spell_damage()), ("11:28:32.0008", spell_damage(1000, source=OTHER, source_flags="0x518")), ("11:28:33.0008", spell_damage(2000, source=PET, source_flags="0x1111"))])
        self.assertEqual(result["summary"]["outgoingDamage"]["total"], 27)
        self.assertEqual(len(result["events"]), 1)

    def test_incoming_and_misses_do_not_inflate_outgoing(self):
        incoming = swing(amount=4, overkill=-1, source=MOB, target=ME, source_flags="0x10a28", target_flags="0x511")
        missed = base("SWING_MISSED", MOB, ME, "0x10a28", "0x511") + ["PARRY", "nil"]
        result = self.fixture([("11:28:31.0008", incoming), ("11:28:32.0008", missed)])
        self.assertEqual(result["summary"]["incomingDamage"]["total"], 4)
        self.assertEqual(result["summary"]["incomingMisses"], {"PARRY": 1})
        self.assertIsNone(result["summary"]["outgoingDamage"]["total"])

    def test_ambiguous_self_rejected_without_identity_in_error(self):
        with self.assertRaises(coach.DataError) as error:
            self.fixture([("11:28:31.0008", spell_damage()), ("11:28:32.0008", spell_damage(source=OTHER))])
        self.assertNotIn(ME, str(error.exception))
        self.assertNotIn(OTHER, str(error.exception))

    def test_pet_cannot_be_self_even_with_mine_affiliation(self):
        with self.assertRaises(coach.DataError):
            self.fixture([("11:28:31.0008", spell_damage(source=PET, source_flags="0x1111"))])
        with self.assertRaises(coach.DataError):
            self.fixture([("11:28:31.0008", spell_damage(source=MOB))])

    def test_incomplete_or_unknown_payload_not_fabricated(self):
        for entries, version, header in [([("11:28:31.0008", base("SPELL_DAMAGE"))], 22, True), ([('11:28:31.0008', spell_damage())], 99, True), ([('11:28:31.0008', spell_damage())], 22, False)]:
            with self.subTest(version=version, header=header):
                result = self.fixture(entries, version, header)
                self.assertNotIn("amount", result["events"][0])
                self.assertEqual(result["summary"]["outgoingDamage"]["coverage"], "partial")

    def test_numeric_nan_and_bad_overkill_do_not_create_effective_amount(self):
        damage = spell_damage(27, 28)
        damage[26] = "NaN"
        result = self.fixture([("11:28:31.0008", damage)])
        self.assertNotIn("worldX", result["events"][0]["snapshots"][0])
        self.assertNotIn("effectiveAmount", result["events"][0])

    def test_control_and_aura_keep_ids_never_names_or_cc_assumptions(self):
        aura = base("SPELL_AURA_APPLIED") + [853, NAMES[2], "0x2", "DEBUFF"]
        interrupt = base("SPELL_INTERRUPT") + [96231, NAMES[2], "0x2", 12345, NAMES[2], "0x4"]
        result = self.fixture([("11:28:31.0008", aura), ("11:28:32.0008", interrupt)])
        self.assertEqual(result["events"][0]["spellId"], 853)
        self.assertEqual(result["events"][1]["extraSpellId"], 12345)
        self.assertTrue(result["limits"]["aurasDoNotProveCrowdControl"])

    def test_related_death_allowed_but_unrelated_actions_and_chat_omitted(self):
        death = base("UNIT_DIED", coach.ZERO_GUID, MOB, "0x80000000")
        chat = base("CHAT_MSG_SAY") + [NAMES[3]]
        result = self.fixture([("11:28:31.0008", spell_damage()), ("11:28:32.0008", death), ("11:28:33.0008", chat)])
        self.assertEqual([e["eventType"] for e in result["events"]], ["SPELL_DAMAGE", "UNIT_DIED"])
        serialized = json.dumps(result)
        for secret in (*NAMES, ME, MOB, OTHER, PET, str(self.path)):
            self.assertNotIn(secret, serialized)

    def test_window_boundaries_are_inclusive_with_explicit_timezone(self):
        result = self.fixture([("11:28:19.9999", spell_damage(100)), ("11:28:20.0000", spell_damage(1)), ("11:29:25.0000", spell_damage(2)), ("11:29:25.0001", spell_damage(100))])
        self.assertEqual(result["summary"]["outgoingDamage"]["total"], 3)
        with self.assertRaises(coach.DataError):
            coach.boundary("2026-11-08T11:28:20")
        with self.assertRaises(coach.DataError):
            coach.fixed_timezone("+14:01")
        with self.assertRaises(coach.DataError):
            coach.analyze_log(self.path, START, START - timedelta(seconds=1), TZ)

    def test_bad_csv_and_bad_timestamps_rejected_without_input_echo(self):
        for text in ('11/8/2026 11:28:31.0008  SPELL_DAMAGE,"PRIVATE_UNCLOSED\n', 'PRIVATE_BAD_TIMESTAMP\n', '11/8/2026 11:28:31.0008  \n'):
            self.path.write_text(text, encoding="utf-8")
            with self.assertRaises(coach.DataError) as error:
                coach.analyze_log(self.path, START, END, TZ)
            self.assertNotIn("PRIVATE", str(error.exception))

    def test_bad_numeric_payload_and_unknown_miss_reason_are_omitted(self):
        damage = spell_damage()
        damage[31] = NAMES[3]
        missed = base("SWING_MISSED", MOB, ME, "0x10a28", "0x511") + [NAMES[3], "nil"]
        result = self.fixture([("11:28:31.0008", damage), ("11:28:32.0008", missed)])
        self.assertNotIn("amount", result["events"][0])
        self.assertNotIn("missType", result["events"][1])
        self.assertIsNone(result["summary"]["outgoingDamage"]["total"])
        self.assertNotIn(NAMES[3], json.dumps(result))

    def test_environmental_damage_uses_its_distinct_layout(self):
        event = base("ENVIRONMENTAL_DAMAGE", coach.ZERO_GUID, ME, "0x80000000", "0x511") + advanced(ME) + ["Falling", 10, 10, -1, 1, 0, 0, 0, "nil", "nil", "nil"]
        result = self.fixture([("11:28:31.0008", event)])
        self.assertEqual(result["events"][0]["environmentType"], "Falling")
        self.assertEqual(result["summary"]["incomingDamage"]["effective"], 10)

    def test_cli_rejects_hardlink_to_input_even_with_force(self):
        self.fixture([("11:28:31.0008", spell_damage())])
        output = self.path.with_suffix(".json")
        os.link(self.path, output)
        original = self.path.read_bytes()
        args = ["--log", str(self.path), "--start", START.isoformat(), "--end", END.isoformat(), "--log-timezone", "+08:00", "--output", str(output), "--force"]
        with redirect_stderr(io.StringIO()):
            self.assertEqual(coach.main(args), 2)
        self.assertEqual(self.path.read_bytes(), original)

    def test_cli_writes_only_anonymous_json_and_never_overwrites_source(self):
        self.fixture([("11:28:31.0008", spell_damage())])
        digest = hashlib.sha256(self.path.read_bytes()).hexdigest()
        output = self.path.with_suffix(".json")
        args = ["--log", str(self.path), "--start", START.isoformat(), "--end", END.isoformat(), "--log-timezone", "+08:00", "--output", str(output)]
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            self.assertEqual(coach.main(args), 0)
            self.assertEqual(coach.main(args), 2)
            self.assertEqual(coach.main(args + ["--force"]), 0)
        report = output.read_text()
        self.assertEqual(json.loads(report)["mode"], "postcombat-only")
        for secret in (*NAMES, ME, MOB, str(self.path)):
            self.assertNotIn(secret, report + stdout.getvalue() + stderr.getvalue())
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), digest)
        self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
