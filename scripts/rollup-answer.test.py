#!/usr/bin/env python3
"""Hermetic contract tests for answered-pending rollup answers.

Every test uses a temporary Mission Control home and, when needed, a temporary
chat-graph database. No provider, live store, installation, or network path is
reachable from this suite.
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
ALERT = ROOT / "scripts" / "decision-alert"
DASHBOARD = ROOT / "scripts" / "dashboard"

COMPOSER_SPEC = importlib.util.spec_from_file_location(
    "mission_control_compose_decision_prompt",
    ROOT / "scripts" / "compose-decision-prompt.py")
if COMPOSER_SPEC is None or COMPOSER_SPEC.loader is None:
    raise RuntimeError("could not load compose-decision-prompt.py")
COMPOSER = importlib.util.module_from_spec(COMPOSER_SPEC)
COMPOSER_SPEC.loader.exec_module(COMPOSER)

TEXT = (
    "**DECISION NEEDED:** Approve `feature/rollup`. "
    "**`Approve`** or **`Wait`**."
)


class RollupAnswerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="mc-rollup-answer-test."))
        self.home = self.temp / "state"
        self.home.mkdir(mode=0o700)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith((
                "MISSION_CONTROL_", "DECISION_ALERT_", "DECISION_TEST_",
                "MORNING_BRIEF_", "CHAT_GRAPH_", "DASHBOARD_"))
        }
        self.env.update({
            "MISSION_CONTROL_HOME": str(self.home),
            "REPO_ROOT": str(ROOT),
            "DASHBOARD_NO_OPEN": "1",
            "DECISION_ALERT_NOW_EPOCH": "1784368800",
            "MISSION_CONTROL_NOW_EPOCH": "1784368800",
            "PYTHONDONTWRITEBYTECODE": "1",
        })

    def tearDown(self) -> None:
        shutil.rmtree(self.temp, ignore_errors=True)

    def _proc(self, argv: list[str], *, ok: bool = True,
              extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        env = dict(self.env)
        if extra_env:
            env.update(extra_env)
        proc = subprocess.run(
            argv, env=env, text=True, capture_output=True, timeout=60, check=False)
        if ok and proc.returncode != 0:
            self.fail("command failed (%s): %s\nstdout=%s\nstderr=%s" % (
                proc.returncode, argv, proc.stdout, proc.stderr))
        if not ok and proc.returncode == 0:
            self.fail("command unexpectedly succeeded: %s\nstdout=%s" % (argv, proc.stdout))
        return proc

    def _await_pause(self, proc: subprocess.Popen[str], marker: Path,
                     what: str) -> None:
        deadline = time.monotonic() + 30
        while not marker.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if marker.exists():
            return
        if proc.poll() is None:
            proc.kill()
        stdout, stderr = proc.communicate()
        self.fail("%s did not reach test pause: %s %s" % (
            what, stdout, stderr))

    def _alert(self, *args: str, ok: bool = True,
               extra_env: dict[str, str] | None = None) -> dict:
        proc = self._proc([str(ALERT), *args, "--json"], ok=ok,
                          extra_env=extra_env)
        if not ok:
            return {"returncode": proc.returncode, "stderr": proc.stderr}
        return json.loads(proc.stdout)

    def _dashboard(self, *args: str, ok: bool = True,
                   extra_env: dict[str, str] | None = None) -> dict:
        proc = self._proc(["/bin/bash", str(DASHBOARD), *args], ok=ok,
                          extra_env=extra_env)
        if not ok:
            return {"returncode": proc.returncode, "stderr": proc.stderr,
                    "stdout": proc.stdout}
        return json.loads(proc.stdout)

    def _ingest(self, owner: str, item: str, *, evidence: str | None = None,
                text: str = TEXT) -> dict:
        resolution_key = hashlib.sha1(
            ("%s:%s" % (owner, item)).encode("utf-8")).hexdigest()
        result = self._alert(
            "ingest", "--source-kind", "chat",
            "--source-key", "outcome:%s:%s" % (owner, resolution_key),
            "--text", text,
            "--evidence", evidence or ("evidence-%s-%s" % (owner, item)),
            "--trust", "structured", "--provenance", "chat-graph tier1",
            "--resolution-key", resolution_key,
            "--anchor", "chat-graph:%s:%s" % (owner, resolution_key))
        result["resolution_key"] = resolution_key
        return result

    def _ingest_graph_item(self, owner: str, item_key: str, *,
                           evidence: str | None = None) -> dict:
        result = self._alert(
            "ingest", "--source-kind", "chat",
            "--source-key", "outcome:%s:%s" % (owner, item_key),
            "--text", TEXT,
            "--evidence", evidence or ("evidence-%s" % owner),
            "--trust", "structured", "--provenance", "chat-graph tier1",
            "--resolution-key", item_key,
            "--anchor", "chat-graph:%s:%s" % (owner, item_key))
        result["resolution_key"] = item_key
        return result

    def _three_member_card(self) -> dict:
        primary = self._ingest("owner-a", "one")
        equivalent = self._ingest("owner-a", "two")
        independent = self._ingest("owner-b", "one")
        ids = {
            "primary": primary["decision"]["id"],
            "equivalent": equivalent["decision"]["id"],
            "independent": independent["decision"]["id"],
        }
        cards = self._alert("rollup")["cards"]
        card = next(c for c in cards if {m["decision_id"] for m in c["members"]}
                    == set(ids.values()))
        return {
            "card": card,
            "ids": ids,
            "resolution_keys": {
                ids["primary"]: primary["resolution_key"],
                ids["equivalent"]: equivalent["resolution_key"],
                ids["independent"]: independent["resolution_key"],
            },
        }

    def _history(self, decision_id: str) -> dict:
        return self._alert("history", decision_id)

    def _pending_events(self, decision_id: str) -> list[dict]:
        return [e for e in self._history(decision_id)["events"]
                if e["event_type"] == "answered_pending"]

    def _answer_single(self, decision_id: str, choice: int = 1) -> dict:
        self._proc([
            "/bin/bash", str(DASHBOARD), "decide", "answer",
            decision_id, str(choice),
        ])
        return self._history(decision_id)

    def _deliver(self, decision_id: str, event_id: str,
                 evidence_ref: str) -> dict:
        decision = self._history(decision_id)["decision"]
        return self._alert(
            "transition", decision_id, "--to", "delivered",
            "--expected-fingerprint", decision["evidence_fingerprint"],
            "--resolution-key", decision["resolution_key"],
            "--event-id", event_id,
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", evidence_ref,
            "--outcome", "delivered", "--source", "test-suite")

    def _write_chat_change(self, change: dict) -> None:
        data_dir = self.home / "data"
        data_dir.mkdir(mode=0o700, exist_ok=True)
        (data_dir / "chats.json").write_text(json.dumps({
            "schema": 1,
            "data": {"outcomes": [], "loose_end_changes": [change]},
        }))

    def _state_snapshot(self) -> list[tuple[str, str, int, bytes | str]]:
        snapshot = []
        for path in sorted(self.home.rglob("*")):
            relative = str(path.relative_to(self.home))
            info = path.lstat()
            mode = stat.S_IMODE(info.st_mode)
            if path.is_symlink():
                snapshot.append((relative, "symlink", mode, os.readlink(path)))
            elif path.is_file():
                # SQLite read-only WAL readers may update lock slots inside an
                # existing -shm file. Keep its namespace and mode in scope;
                # bind durable database and WAL bytes exactly.
                content = b"<sqlite-shm>" if relative.endswith("-shm") \
                    else path.read_bytes()
                snapshot.append((relative, "file", mode, content))
            else:
                snapshot.append((relative, "directory", mode, b""))
        return snapshot

    def _checkpoint_without_sidecars(self) -> None:
        """Leave a valid WAL-mode database with no journal namespace."""
        path = self.home / "decisions" / "decisions.db"
        con = sqlite3.connect(path)
        try:
            checkpoint = con.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
            self.assertIsNotNone(checkpoint)
            self.assertEqual(checkpoint[0], 0)
        finally:
            con.close()
        for suffix in ("-wal", "-shm"):
            Path(str(path) + suffix).unlink(missing_ok=True)

    def _seed_brief_inputs(self) -> None:
        data_dir = self.home / "data"
        for name, cadence in (("automation", 300), ("git", 900), ("chats", 1800)):
            (data_dir / (name + ".json")).write_text(json.dumps({
                "schema": 1,
                "feed": name,
                "generated_epoch": 1784368800,
                "cadence_s": cadence,
                "ok": True,
                "error": None,
                "data": {"test_fixture": True},
            }))

    def test_plan_targets_only_strict_equivalents_without_writes(self) -> None:
        fixture = self._three_member_card()
        card_id = fixture["card"]["card_id"]
        ids = fixture["ids"]

        plan = self._alert(
            "plan-rollup-answer", card_id, ids["primary"], "1")

        self.assertEqual(plan["target_ids"], [ids["primary"], ids["equivalent"]])
        self.assertEqual(plan["independent_ids"], [ids["independent"]])
        self.assertEqual(plan["already_pending_ids"], [])
        self.assertRegex(plan["scope_key"], r"^scope:[0-9a-f]{40}$")
        self.assertRegex(plan["batch_key"], r"^rollup-[0-9a-f]{40}$")
        for decision_id in ids.values():
            self.assertEqual(self._pending_events(decision_id), [])

    def test_invalid_card_or_primary_is_rejected_before_writes(self) -> None:
        empty = self._state_snapshot()
        self._alert(
            "answer-rollup", "card:" + "0" * 16,
            "decision:" + "0" * 24, "1",
            "--expected-scope-key", "scope:" + "0" * 40,
            "--artifact-batch-name", "rollup-" + "0" * 40,
            "--artifact-manifest-sha256", "0" * 64, ok=False)
        self.assertEqual(self._state_snapshot(), empty)

        self._dashboard(
            "decide", "answer-rollup", "card:" + "0" * 16,
            "decision:" + "0" * 24, "1", ok=False)
        self.assertEqual(self._state_snapshot(), empty)

        fixture = self._three_member_card()
        self._checkpoint_without_sidecars()
        before = self._state_snapshot()
        invalid = self._alert(
            "answer-rollup", fixture["card"]["card_id"],
            "decision:" + "0" * 24, "1",
            "--expected-scope-key", "scope:" + "0" * 40,
            "--artifact-batch-name", "rollup-" + "0" * 40,
            "--artifact-manifest-sha256", "0" * 64, ok=False)
        self.assertEqual(
            json.loads(invalid["stderr"])["error"],
            "primary decision is not a current card member")
        self.assertEqual(self._state_snapshot(), before)

        self._dashboard(
            "decide", "answer-rollup", fixture["card"]["card_id"],
            "decision:" + "0" * 24, "1", ok=False)
        self.assertEqual(self._state_snapshot(), before)

    def test_public_rollup_identifiers_reject_trailing_lines(self) -> None:
        fixture = self._three_member_card()
        card_id = fixture["card"]["card_id"]
        primary_id = fixture["ids"]["primary"]
        before = self._state_snapshot()
        marker = self.temp / "composer-invoked"
        fake_bin = self.temp / "bin"
        fake_bin.mkdir()
        fake_python = fake_bin / "python3"
        fake_python.write_text(
            "#!/bin/sh\ntouch \"$ROLLUP_TEST_COMPOSER_MARKER\"\nexit 99\n")
        fake_python.chmod(0o700)
        validation_env = {
            "PATH": str(fake_bin) + os.pathsep + self.env.get("PATH", ""),
            "ROLLUP_TEST_COMPOSER_MARKER": str(marker),
        }

        bad_card = self._dashboard(
            "decide", "answer-rollup", card_id + "\ntrailing",
            primary_id, "1", ok=False, extra_env=validation_env)
        self.assertEqual(
            bad_card["stderr"].strip(),
            "decide answer-rollup: invalid card id")
        self.assertFalse(marker.exists())
        self.assertEqual(self._state_snapshot(), before)

        bad_primary = self._dashboard(
            "decide", "answer-rollup", card_id,
            primary_id + "\ntrailing", "1", ok=False,
            extra_env=validation_env)
        self.assertEqual(
            bad_primary["stderr"].strip(),
            "decide answer-rollup: invalid primary decision id")
        self.assertFalse(marker.exists())
        self.assertEqual(self._state_snapshot(), before)

    def test_batch_keeps_targets_open_and_blocks_ordinary_reanswer(self) -> None:
        fixture = self._three_member_card()
        card_id = fixture["card"]["card_id"]
        ids = fixture["ids"]

        result = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            "--source", "test-suite", "--resume-chat-id", "owner-a",
            "--resume-provider", "codex")

        self.assertEqual(result["target_ids"], [ids["primary"], ids["equivalent"]])
        self.assertEqual(result["independent_ids"], [ids["independent"]])
        self.assertFalse(result["replayed"])
        batch = Path(result["batch_path"])
        self.assertTrue(batch.is_dir())
        self.assertEqual(stat.S_IMODE(batch.stat().st_mode), 0o700)
        manifest = json.loads((batch / "manifest.json").read_text())
        self.assertEqual(manifest["batch_key"], result["batch_key"])
        self.assertEqual(manifest["target_ids"], result["target_ids"])

        for decision_id in (ids["primary"], ids["equivalent"]):
            history = self._history(decision_id)
            self.assertEqual(history["decision"]["state"], "open")
            pending = history["decision"]["answer_pending"]
            self.assertEqual(pending["choice"], 1)
            self.assertEqual(pending["source"], "test-suite")
            self.assertEqual(pending["card_id"], card_id)
            self.assertEqual(
                pending["artifact_manifest_sha256"], result["manifest_sha256"])
            self.assertEqual(len(self._pending_events(decision_id)), 1)
            answer = batch / "answers" / (decision_id + ".json")
            prompt = batch / "prompts" / (decision_id + ".md")
            self.assertEqual(stat.S_IMODE(answer.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(prompt.stat().st_mode), 0o600)
            self.assertEqual(json.loads(answer.read_text())["choice"], 1)
            self.assertIn("Trevor choice: 1", prompt.read_text())

        independent = self._history(ids["independent"])["decision"]
        self.assertEqual(independent["state"], "open")
        self.assertIsNone(independent["answer_pending"])

        preview = self._alert("alert", "--decision-id", ids["primary"])
        self.assertEqual(preview["eligible_count"], 0)
        self.assertEqual(preview["skipped_ids"], [{
            "id": ids["primary"], "reason": "answered_pending_consumption"}])
        self._alert("dismiss", ids["primary"], ok=False)
        self._dashboard("decide", "answer", ids["primary"], "1", ok=False)

        replay = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            "--source", "test-suite", "--resume-chat-id", "owner-a",
            "--resume-provider", "codex")
        self.assertTrue(replay["replayed"])
        self.assertEqual(replay["batch_path"], str(batch))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "2",
            ok=False)
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_verified_consumption_advances_only_the_exact_member(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")

        primary = self._history(ids["primary"])["decision"]
        fingerprint = primary["evidence_fingerprint"]
        resolution_key = fixture["resolution_keys"][ids["primary"]]
        self.assertEqual(primary["lifecycle"]["state"], "answered_pending")
        self.assertEqual(primary["lifecycle"]["requested_action"], "deliver")

        self._alert(
            "transition", ids["primary"], "--to", "delivered",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "delivery:failed-primary",
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", "provider:failed-primary",
            "--outcome", "failed", "--source", "test-suite", ok=False)
        self.assertEqual(
            self._history(ids["primary"])["decision"]["lifecycle"]["state"],
            "answered_pending")

        delivered = self._alert(
            "transition", ids["primary"], "--to", "delivered",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "delivery:primary-001",
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", "provider:receipt-primary-001",
            "--outcome", "delivered", "--source", "test-suite")
        self.assertTrue(delivered["changed"])
        self.assertEqual(delivered["decision"]["state"], "open")
        self.assertEqual(delivered["decision"]["lifecycle"]["state"], "delivered")
        self.assertEqual(
            delivered["decision"]["lifecycle"]["requested_action"],
            "consume")

        replay = self._alert(
            "transition", ids["primary"], "--to", "delivered",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "delivery:primary-001",
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", "provider:receipt-primary-001",
            "--outcome", "delivered", "--source", "test-suite")
        self.assertFalse(replay["changed"])
        self.assertTrue(replay["replayed"])

        equivalent = self._history(ids["equivalent"])["decision"]
        self._alert(
            "transition", ids["equivalent"], "--to", "delivered",
            "--expected-fingerprint", equivalent["evidence_fingerprint"],
            "--resolution-key", fixture["resolution_keys"][ids["equivalent"]],
            "--event-id", "delivery:primary-001",
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", "provider:receipt-primary-001",
            "--outcome", "delivered", "--source", "test-suite", ok=False)

        self._alert(
            "transition", ids["primary"], "--to", "running",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "execution:skip-consumption",
            "--evidence-type", "execution_start_receipt",
            "--evidence-ref", "executor:start-skipped",
            "--outcome", "started", "--source", "test-suite", ok=False)

        self._alert(
            "resolve", ids["primary"], "--evidence-type", "manual_resolution",
            "--evidence-ref", "manual-not-consumption",
            "--source", "test-suite", ok=False)

        self._alert(
            "resolve", ids["primary"],
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "consumer:rejected",
            "--resolution-key", resolution_key,
            "--event-id", "consumption:rejected-primary",
            "--expected-fingerprint", fingerprint,
            "--source", "test-suite", ok=False)

        self._alert(
            "resolve", ids["primary"],
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "wrong-task-consumption",
            "--resolution-key", fixture["resolution_keys"][ids["equivalent"]],
            "--event-id", "consumption:wrong-task",
            "--expected-fingerprint", fingerprint,
            "--source", "test-suite", ok=False)

        graph = self.temp / "graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT,
            UNIQUE(session_id, kind, item_key))""")
        evidence_ref = "turn-owner-a-consumed-one"
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "owner-a", "chat_open_end",
            fixture["resolution_keys"][ids["primary"]], 1784368801,
            "answering_user_turn", evidence_ref))
        con.commit()
        con.close()

        consumed = self._alert(
            "resolve", ids["primary"],
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", evidence_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:primary-001",
            "--expected-fingerprint", fingerprint,
            "--source", "test-suite",
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertTrue(consumed["changed"])
        self.assertEqual(consumed["decision"]["state"], "open")
        self.assertEqual(consumed["decision"]["lifecycle"]["state"], "consumed")
        self.assertEqual(
            consumed["decision"]["lifecycle"]["requested_action"], "start")
        self.assertIsNotNone(consumed["decision"]["answer_pending"])
        self.assertEqual(self._history(ids["equivalent"])["decision"]["state"], "open")
        self.assertEqual(
            self._history(ids["equivalent"])["decision"]["lifecycle"]["state"],
            "answered_pending")
        self.assertIsNotNone(
            self._history(ids["equivalent"])["decision"]["answer_pending"])
        self.assertIsNone(
            self._history(ids["independent"])["decision"]["answer_pending"])

        replay = self._alert(
            "resolve", ids["primary"],
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", evidence_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:primary-001",
            "--expected-fingerprint", fingerprint,
            "--source", "test-suite",
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertFalse(replay["changed"])

        self._alert(
            "transition", ids["primary"], "--to", "closed",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "closure:unverified-primary",
            "--evidence-type", "closure_receipt",
            "--evidence-ref", "closure:without-result",
            "--outcome", "closed", "--source", "test-suite", ok=False)

        running = self._alert(
            "transition", ids["primary"], "--to", "running",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "execution:primary-001",
            "--evidence-type", "execution_start_receipt",
            "--evidence-ref", "executor:start-primary-001",
            "--outcome", "started", "--source", "test-suite")
        self.assertEqual(running["decision"]["lifecycle"]["state"], "running")
        self.assertEqual(
            running["decision"]["lifecycle"]["requested_action"],
            "verify_live_result")

        self._alert(
            "transition", ids["primary"], "--to", "live_result_verified",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "result:unverified-primary",
            "--evidence-type", "live_result_receipt",
            "--evidence-ref", "result:unverified-primary",
            "--outcome", "unverified", "--source", "test-suite", ok=False)
        self._alert(
            "transition", ids["primary"], "--to", "running",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "execution:timeout-primary",
            "--evidence-type", "execution_start_receipt",
            "--evidence-ref", "executor:timeout-primary",
            "--outcome", "timeout", "--source", "test-suite", ok=False)

        verified = self._alert(
            "transition", ids["primary"], "--to", "live_result_verified",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "result:primary-001",
            "--evidence-type", "live_result_receipt",
            "--evidence-ref", "result:verified-primary-001",
            "--outcome", "verified", "--source", "test-suite")
        self.assertEqual(
            verified["decision"]["lifecycle"]["state"],
            "live_result_verified")
        self.assertEqual(
            verified["decision"]["lifecycle"]["requested_action"], "close")

        closed = self._alert(
            "transition", ids["primary"], "--to", "closed",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "closure:primary-001",
            "--evidence-type", "closure_receipt",
            "--evidence-ref", "closure:receipt-primary-001",
            "--outcome", "closed", "--source", "test-suite")
        self.assertTrue(closed["changed"])
        self.assertEqual(closed["decision"]["state"], "resolved")
        self.assertEqual(closed["decision"]["lifecycle"]["state"], "closed")
        self.assertIsNone(closed["decision"]["lifecycle"]["requested_action"])
        self.assertIsNone(closed["decision"]["answer_pending"])

        replay = self._alert(
            "transition", ids["primary"], "--to", "closed",
            "--expected-fingerprint", fingerprint,
            "--resolution-key", resolution_key,
            "--event-id", "closure:primary-001",
            "--evidence-type", "closure_receipt",
            "--evidence-ref", "closure:receipt-primary-001",
            "--outcome", "closed", "--source", "test-suite")
        self.assertFalse(replay["changed"])
        self.assertTrue(replay["replayed"])

        events = self._history(ids["primary"])["events"]
        lifecycle_events = [event["event_type"] for event in events
                            if event["event_type"] in {
                                "answered_pending", "delivered", "consumed",
                                "running", "live_result_verified", "closed"}]
        self.assertEqual(lifecycle_events, [
            "answered_pending", "delivered", "consumed", "running",
            "live_result_verified", "closed"])

    def test_lifecycle_requires_source_and_reducer_rejects_missing_source(
            self) -> None:
        ingested = self._ingest("source-owner", "one")
        decision_id = ingested["decision"]["id"]
        self._answer_single(decision_id)
        pending = self._history(decision_id)["decision"]
        self.assertEqual(pending["answer_pending"]["source"], "mission-control")
        self.assertEqual(pending["lifecycle"]["state"], "answered_pending")

        self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "consumer:missing-source",
            "--resolution-key", pending["resolution_key"],
            "--event-id", "consumption:missing-source", ok=False)

        self._alert(
            "transition", decision_id, "--to", "delivered",
            "--expected-fingerprint", pending["evidence_fingerprint"],
            "--resolution-key", pending["resolution_key"],
            "--event-id", "delivery:missing-source",
            "--evidence-type", "provider_delivery_receipt",
            "--evidence-ref", "provider:missing-source",
            "--outcome", "delivered", ok=False)
        delivered = self._deliver(
            decision_id, "delivery:source-bound", "provider:source-bound")
        self.assertEqual(delivered["decision"]["lifecycle"]["state"], "delivered")

        db = self.home / "decisions" / "decisions.db"
        con = sqlite3.connect(db)
        row = con.execute("""SELECT event_id,detail_json FROM decision_events
            WHERE decision_id=? AND event_type='delivered'""",
                          (decision_id,)).fetchone()
        self.assertIsNotNone(row)
        detail = json.loads(row[1])
        detail.pop("source", None)
        con.execute("UPDATE decision_events SET detail_json=? WHERE event_id=?",
                    (json.dumps(detail, sort_keys=True), row[0]))
        con.commit()
        con.close()

        invalid = self._history(decision_id)["decision"]["lifecycle"]
        self.assertFalse(invalid["valid"])
        self.assertEqual(invalid["state"], "invalid")
        status = self._alert("status")
        self.assertEqual(status["data"]["lifecycle_counts"]["invalid"], 1)

    def test_lifecycle_reducer_rejects_missing_persisted_receipt_fields(
            self) -> None:
        cases = (
            ("answered_pending", "evidence_type"),
            ("answered_pending", "evidence_ref"),
            ("delivered", "evidence_type"),
            ("delivered", "evidence_ref"),
        )
        for index, (event_type, column) in enumerate(cases):
            with self.subTest(event_type=event_type, column=column):
                ingested = self._ingest(
                    "receipt-field-owner-%d" % index, "one")
                decision_id = ingested["decision"]["id"]
                self._answer_single(decision_id)
                if event_type == "delivered":
                    self._deliver(
                        decision_id,
                        "delivery:receipt-field-%d" % index,
                        "provider:receipt-field-%d" % index)

                db = self.home / "decisions" / "decisions.db"
                con = sqlite3.connect(db)
                con.execute(
                    "UPDATE decision_events SET %s=NULL "
                    "WHERE decision_id=? AND event_type=?" % column,
                    (decision_id, event_type))
                con.commit()
                con.close()

                lifecycle = self._history(decision_id)["decision"]["lifecycle"]
                self.assertFalse(lifecycle["valid"])
                self.assertEqual(lifecycle["state"], "invalid")

    def test_parent_commit_pending_source_upgrades_without_rewriting_evidence(
            self) -> None:
        ingested = self._ingest("legacy-owner", "one")
        decision = ingested["decision"]
        decision_id = decision["id"]
        self._answer_single(decision_id)
        db = self.home / "decisions" / "decisions.db"
        con = sqlite3.connect(db)
        legacy_event_id, raw_detail = con.execute("""SELECT event_id,detail_json
            FROM decision_events WHERE decision_id=?
              AND event_type='answered_pending'""", (decision_id,)).fetchone()
        legacy = json.loads(raw_detail)
        legacy["source"] = ""
        legacy.pop("batch_key")
        canonical = json.dumps(
            legacy, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        legacy["batch_key"] = "single-%s" % hashlib.sha256(
            canonical.encode("utf-8")).hexdigest()[:40]
        original_detail = json.dumps(
            legacy, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        con.execute("""UPDATE decision_events SET evidence_ref=?,detail_json=?
            WHERE event_id=?""", (
                legacy["batch_key"], original_detail, legacy_event_id))
        con.commit()
        con.close()

        before = self._history(decision_id)["decision"]
        self.assertFalse(before["answer_pending"]["valid"])
        self.assertTrue(
            before["answer_pending"]["legacy_source_upgradeable"])
        upgraded_proc = self._proc([
            "/bin/bash", str(DASHBOARD), "decide", "answer",
            decision_id, "1",
        ])
        upgraded = json.loads(upgraded_proc.stdout.splitlines()[0])
        self.assertEqual(upgraded["choice"], 1)
        history = self._history(decision_id)
        pending_events = [
            event for event in history["events"]
            if event["event_type"] == "answered_pending"]
        self.assertEqual(len(pending_events), 2)
        self.assertEqual(pending_events[0]["detail"]["source"], "")
        self.assertEqual(
            pending_events[1]["detail"]["source"], "mission-control")
        self.assertEqual(
            pending_events[1]["detail"]["source_upgrade_from_event_id"],
            legacy_event_id)
        self.assertEqual(
            history["decision"]["lifecycle"]["state"], "answered_pending")
        self.assertTrue(history["decision"]["answer_pending"]["valid"])
        con = sqlite3.connect(db)
        preserved = con.execute(
            "SELECT detail_json FROM decision_events WHERE event_id=?",
            (legacy_event_id,)).fetchone()[0]
        con.close()
        self.assertEqual(preserved, original_detail)

    def test_lifecycle_source_accepts_64_and_rejects_65_before_staging(
            self) -> None:
        accepted = self._ingest("source-boundary", "accepted")
        accepted_id = accepted["decision"]["id"]
        source_64 = "s" * 64
        self._proc([
            "/bin/bash", str(DASHBOARD), "decide", "answer",
            accepted_id, "1", "--source", source_64,
        ])
        accepted_history = self._history(accepted_id)
        self.assertEqual(
            accepted_history["decision"]["answer_pending"]["source"],
            source_64)
        self.assertEqual(
            accepted_history["decision"]["lifecycle"]["state"],
            "answered_pending")

        rejected = self._ingest("source-boundary", "rejected")
        rejected_id = rejected["decision"]["id"]
        before = self._state_snapshot()
        self._proc([
            "/bin/bash", str(DASHBOARD), "decide", "answer",
            rejected_id, "1", "--source", "s" * 65,
        ], ok=False)
        self.assertEqual(self._state_snapshot(), before)
        rejected_history = self._history(rejected_id)
        self.assertIsNone(rejected_history["decision"]["answer_pending"])
        self.assertEqual(
            rejected_history["decision"]["lifecycle"]["state"],
            "awaiting_answer")
        self.assertFalse(any(
            path.name.startswith((
                ".decision-answer-stage.", ".decision-prompt-stage."))
            for path in self.home.rglob("*")))

    def test_graph_consumption_rejects_duplicate_capable_identity_schema(
            self) -> None:
        ingested = self._ingest_graph_item("duplicate-owner", "d" * 40)
        decision_id = ingested["decision"]["id"]
        self._answer_single(decision_id)
        self._deliver(
            decision_id, "delivery:duplicate-rows", "provider:duplicate-rows")

        graph = self.temp / "duplicate-graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT)""")
        receipt = (
            "duplicate-owner", "chat_open_end", ingested["resolution_key"],
            1784368801, "answering_user_turn", "turn-duplicate-consumed",
        )
        con.executemany("INSERT INTO open_ends VALUES(?,?,?,?,?,?)",
                        (receipt, receipt))
        con.commit()
        con.close()

        rejected = self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "turn-duplicate-consumed",
            "--resolution-key", ingested["resolution_key"],
            "--event-id", "consumption:duplicate-rows",
            "--expected-fingerprint",
            ingested["decision"]["evidence_fingerprint"],
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertIn("unique identity", rejected["stderr"])
        history = self._history(decision_id)
        self.assertEqual(history["decision"]["lifecycle"]["state"], "delivered")
        self.assertFalse(any(
            event["event_type"] == "consumed" for event in history["events"]))

    def test_legacy_resolution_rejects_duplicate_capable_identity_schema(
            self) -> None:
        ingested = self._ingest_graph_item("legacy-duplicate-owner", "e" * 40)
        decision_id = ingested["decision"]["id"]
        graph = self.temp / "legacy-duplicate-graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT)""")
        receipt = (
            "legacy-duplicate-owner", "chat_open_end",
            ingested["resolution_key"], 1784368801,
            "answering_user_turn", "turn-legacy-duplicate-consumed",
        )
        con.executemany("INSERT INTO open_ends VALUES(?,?,?,?,?,?)",
                        (receipt, receipt))
        con.commit()
        con.close()

        rejected = self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "turn-legacy-duplicate-consumed",
            "--resolution-key", ingested["resolution_key"],
            "--event-id", "resolution:legacy-duplicate-rows",
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertIn("unique identity", rejected["stderr"])
        self.assertEqual(
            self._history(decision_id)["decision"]["state"], "open")

    def test_graph_consumption_is_fresh_and_receipt_is_not_cross_fingerprint(
            self) -> None:
        first = self._ingest("receipt-owner", "one", evidence="evidence-v1")
        decision_id = first["decision"]["id"]
        resolution_key = first["resolution_key"]
        self._answer_single(decision_id)
        self._deliver(decision_id, "delivery:receipt-v1", "provider:receipt-v1")

        graph = self.temp / "graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT,
            UNIQUE(session_id, kind, item_key))""")
        shared_ref = "turn-receipt-owner-consumed"
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "receipt-owner", "chat_open_end", resolution_key, 1784368801,
            "answering_user_turn", shared_ref))
        con.commit()
        con.close()

        self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", shared_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:missing-fingerprint",
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", shared_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:stale-fingerprint",
            "--expected-fingerprint", "0" * 64,
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})

        first_consumed = self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", shared_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:receipt-v1",
            "--expected-fingerprint", first["decision"]["evidence_fingerprint"],
            "--source", "test-suite",
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        consumed_event = next(
            event for event in self._history(decision_id)["events"]
            if event["event_type"] == "consumed")
        self.assertEqual(consumed_event["detail"]["resolved_at"], 1784368801)
        self.assertEqual(consumed_event["detail"]["source_id"], "receipt-owner")
        self.assertIsInstance(consumed_event["detail"]["delivered_event_id"], int)
        self.assertEqual(consumed_event["detail"]["delivered_at"], 1784368800)
        self.assertEqual(first_consumed["decision"]["lifecycle"]["state"], "consumed")

        self.env["DECISION_ALERT_NOW_EPOCH"] = "1784368802"
        second = self._ingest("receipt-owner", "one", evidence="evidence-v2")
        self.assertNotEqual(
            first["decision"]["evidence_fingerprint"],
            second["decision"]["evidence_fingerprint"])
        self._answer_single(decision_id, 2)
        self._deliver(decision_id, "delivery:receipt-v2", "provider:receipt-v2")

        con = sqlite3.connect(graph)
        con.execute("""UPDATE open_ends SET resolved_at=1784368801,
            resolution_evidence_type='answering_user_turn',
            resolution_evidence_ref='turn-stale-for-v2'
            WHERE session_id='receipt-owner' AND kind='chat_open_end'
              AND item_key=?""", (resolution_key,))
        con.commit()
        con.close()

        stale = self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", "turn-stale-for-v2",
            "--resolution-key", resolution_key,
            "--event-id", "consumption:stale-v2",
            "--expected-fingerprint", second["decision"]["evidence_fingerprint"],
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertIn("predates current delivery", stale["stderr"])

        con = sqlite3.connect(graph)
        con.execute("""UPDATE open_ends SET resolved_at=1784368803,
            resolution_evidence_ref=? WHERE session_id='receipt-owner'
              AND kind='chat_open_end' AND item_key=?""",
                    (shared_ref, resolution_key))
        con.commit()
        con.close()
        reused = self._alert(
            "resolve", decision_id,
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", shared_ref,
            "--resolution-key", resolution_key,
            "--event-id", "consumption:reused-v2",
            "--expected-fingerprint", second["decision"]["evidence_fingerprint"],
            "--source", "test-suite", ok=False,
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertIn("already bound", reused["stderr"])
        self.assertEqual(
            self._history(decision_id)["decision"]["lifecycle"]["state"],
            "delivered")

    def test_graph_consumption_binds_source_kind_and_item_identity(self) -> None:
        item_key = "a" * 40
        owner_a = self._ingest_graph_item("owner-a", item_key)
        decision_id = owner_a["decision"]["id"]
        self._answer_single(decision_id)
        self._deliver(decision_id, "delivery:identity-a", "provider:identity-a")

        graph = self.temp / "graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT,
            UNIQUE(session_id, kind, item_key))""")
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "owner-b", "chat_open_end", item_key, 1784368801,
            "downstream_explicit", "owner-b-proof"))
        con.commit()
        con.close()

        owner_b_change = {
            "item_key": item_key,
            "kind": "chat_open_end",
            "change_type": "resolved",
            "resolved_at": 1784368801,
            "source_id": "owner-b",
            "resolution_evidence_type": "downstream_explicit",
            "resolution_evidence_ref": "owner-b-proof",
        }
        self._write_chat_change(owner_b_change)
        wrong_owner = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(wrong_owner["data"]["sync"]["consumed"], 0)
        self.assertEqual(wrong_owner["data"]["sync"]["unmatched"], 1)
        self.assertEqual(
            self._history(decision_id)["decision"]["lifecycle"]["state"],
            "delivered")

        missing_kind = dict(owner_b_change)
        missing_kind.pop("kind")
        self._write_chat_change(missing_kind)
        malformed = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(malformed["data"]["sync"]["invalid"], 1)

        owner_a_change = dict(owner_b_change)
        owner_a_change.update({
            "source_id": "owner-a",
            "resolution_evidence_ref": "owner-a-proof",
        })
        con = sqlite3.connect(graph)
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "owner-a", "closeout_handoff", item_key, 1784368801,
            "downstream_explicit", "owner-a-proof"))
        con.commit()
        con.close()
        self._write_chat_change(owner_a_change)
        wrong_kind = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(wrong_kind["data"]["sync"]["consumed"], 0)
        self.assertEqual(wrong_kind["data"]["sync"]["invalid"], 1)
        self.assertEqual(
            self._history(decision_id)["decision"]["lifecycle"]["state"],
            "delivered")

        con = sqlite3.connect(graph)
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "owner-a", "chat_open_end", item_key, 1784368801,
            "downstream_explicit", "owner-a-proof"))
        con.commit()
        con.close()
        consumed = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(consumed["data"]["sync"]["consumed"], 1)
        event = next(
            event for event in self._history(decision_id)["events"]
            if event["event_type"] == "consumed")
        self.assertEqual(event["detail"]["source_id"], "owner-a")
        self.assertEqual(event["detail"]["kind"], "chat_open_end")
        self.assertEqual(event["detail"]["item_key"], item_key)

    def test_graph_watcher_consumes_only_delivered_with_deterministic_event(
            self) -> None:
        first = self._ingest("watch-owner", "one")
        decision_id = first["decision"]["id"]
        resolution_key = first["resolution_key"]
        self._answer_single(decision_id)

        graph = self.temp / "graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT,
            UNIQUE(session_id, kind, item_key))""")
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "watch-owner", "chat_open_end", resolution_key, 1784368801,
            "downstream_explicit", "watch-child-result"))
        con.commit()
        con.close()
        change = {
            "item_key": resolution_key,
            "kind": "chat_open_end",
            "change_type": "resolved",
            "resolved_at": 1784368801,
            "source_id": "watch-owner",
            "resolution_evidence_type": "downstream_explicit",
            "resolution_evidence_ref": "watch-child-result",
        }
        self._write_chat_change(change)

        pre_delivery = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(pre_delivery["data"]["sync"]["resolved_semantics"],
                         "compatibility_queue_alias")
        self.assertEqual(pre_delivery["data"]["sync"]["resolved_compatibility"],
                         pre_delivery["data"]["sync"]["resolved"])
        self.assertEqual(pre_delivery["data"]["sync"]["pre_delivery"], 1)
        self.assertEqual(pre_delivery["data"]["sync"]["invalid"], 0)
        self.assertEqual(
            self._history(decision_id)["decision"]["lifecycle"]["state"],
            "answered_pending")

        self._deliver(decision_id, "delivery:watch-owner", "provider:watch-owner")
        consumed = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(consumed["data"]["sync"]["consumed"], 1)
        history = self._history(decision_id)
        self.assertEqual(history["decision"]["lifecycle"]["state"], "consumed")
        event = next(e for e in history["events"] if e["event_type"] == "consumed")
        self.assertRegex(event["detail"]["transition_id"],
                         r"^chat-graph:[0-9a-f]{40}$")
        self.assertEqual(event["detail"]["source"], "chat-graph")
        self.assertEqual(event["detail"]["resolved_at"], 1784368801)
        self.assertEqual(event["detail"]["source_id"], "watch-owner")
        self.assertIsInstance(event["detail"]["delivered_event_id"], int)
        self.assertEqual(event["detail"]["delivered_at"], 1784368800)
        replay = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(replay["data"]["sync"]["consumed"], 0)
        self.assertEqual(replay["data"]["sync"]["already_consumed"], 1)
        self.assertEqual(
            len([e for e in self._history(decision_id)["events"]
                 if e["event_type"] == "consumed"]), 1)

        invalid = dict(change)
        invalid["item_key"] = "b" * 40
        invalid.pop("source_id")
        self._write_chat_change(invalid)
        malformed = self._alert(
            "sync-snapshot", extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertEqual(malformed["data"]["sync"]["invalid"], 1)
        self.assertEqual(malformed["data"]["sync"]["pre_delivery"], 0)

    def test_status_separates_lifecycle_counts_from_compatibility_counts(
            self) -> None:
        waiting = self._ingest("status-owner", "waiting")
        pending = self._ingest("status-owner", "pending")
        self._answer_single(pending["decision"]["id"])

        status = self._alert("status")
        lifecycle = status["data"]["lifecycle_counts"]
        self.assertEqual(lifecycle["awaiting_answer"], 1)
        self.assertEqual(lifecycle["answered_pending"], 1)
        self.assertEqual(sum(lifecycle.values()), 2)
        self.assertEqual(status["data"]["counts_semantics"],
                         "compatibility_queue_alias")
        self.assertEqual(status["data"]["compatibility_counts"],
                         status["data"]["counts"])
        self.assertEqual(status["data"]["compatibility_counts"]["open"], 2)
        self.assertIn(waiting["decision"]["id"],
                      [d["id"] for d in status["data"]["pinned"]])

    def test_changed_evidence_unlocks_a_new_answer(self) -> None:
        first = self._ingest("solo-owner", "one", evidence="evidence-v1")
        decision_id = first["decision"]["id"]
        card_id = self._alert("rollup")["cards"][0]["card_id"]
        one = self._dashboard(
            "decide", "answer-rollup", card_id, decision_id, "1")
        self.assertFalse(one["replayed"])

        changed = self._ingest("solo-owner", "one", evidence="evidence-v2")
        self.assertEqual(changed["decision"]["id"], decision_id)
        self.assertIsNone(changed["decision"]["answer_pending"])
        self.assertEqual(changed["decision"]["state"], "open")

        card_id = self._alert("rollup")["cards"][0]["card_id"]
        two = self._dashboard(
            "decide", "answer-rollup", card_id, decision_id, "2")
        self.assertFalse(two["replayed"])
        events = self._pending_events(decision_id)
        self.assertEqual(len(events), 2)
        self.assertNotEqual(events[0]["evidence_fingerprint"],
                            events[1]["evidence_fingerprint"])
        self.assertEqual(self._history(decision_id)["decision"]["state"], "open")

    def test_returning_fingerprint_does_not_resurrect_old_lifecycle(self) -> None:
        first = self._ingest(
            "returning-fingerprint-owner", "one", evidence="evidence-v1")
        decision_id = first["decision"]["id"]
        fingerprint_v1 = first["decision"]["evidence_fingerprint"]
        self._answer_single(decision_id)
        self._deliver(
            decision_id, "delivery:returning-v1", "provider:returning-v1")
        before = self._history(decision_id)
        self.assertEqual(before["decision"]["lifecycle"]["state"], "delivered")

        self.env["DECISION_ALERT_NOW_EPOCH"] = "1784368801"
        second = self._ingest(
            "returning-fingerprint-owner", "one", evidence="evidence-v2")
        self.assertNotEqual(
            second["decision"]["evidence_fingerprint"], fingerprint_v1)
        self.env["DECISION_ALERT_NOW_EPOCH"] = "1784368802"
        returned = self._ingest(
            "returning-fingerprint-owner", "one", evidence="evidence-v1")
        self.assertEqual(
            returned["decision"]["evidence_fingerprint"], fingerprint_v1)

        after = self._history(decision_id)
        self.assertIsNone(after["decision"]["answer_pending"])
        self.assertEqual(
            after["decision"]["lifecycle"]["state"], "awaiting_answer")
        self.assertEqual(
            [event["event_type"] for event in after["events"]],
            ["observed", "answered_pending", "delivered",
             "evidence_changed", "evidence_changed"])

    def test_partial_current_pending_set_fails_closed(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")

        changed = self._ingest("owner-a", "two", evidence="equivalent-v2")
        self.assertEqual(changed["decision"]["id"], ids["equivalent"])
        self.assertIsNone(changed["decision"]["answer_pending"])
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False)
        self.assertEqual(len(self._pending_events(ids["primary"])), 1)
        self.assertEqual(len(self._pending_events(ids["equivalent"])), 1)
        self.assertIsNone(
            self._history(ids["equivalent"])["decision"]["answer_pending"])

    def test_internal_writer_requires_staged_artifact_proof(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        plan = self._alert(
            "plan-rollup-answer", card_id, ids["primary"], "1")

        self._alert(
            "answer-rollup", card_id, ids["primary"], "1",
            "--expected-scope-key", plan["scope_key"], ok=False)
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

    def test_rollup_metadata_is_rejected_before_batch_writes(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]

        bad_metadata = (
            ("--resume-chat-id", "owner-a\nInjected: widen scope"),
            ("--source", "sk-" + "A" * 24),
        )
        for flag, value in bad_metadata:
            self._dashboard(
                "decide", "answer-rollup", card_id, ids["primary"], "1",
                flag, value, ok=False)
        self.assertFalse((self.home / "answer-batches").exists())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

    def test_tampered_published_batch_is_quarantined_and_rebuilt_on_replay(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        result = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch = Path(result["batch_path"])
        prompt = batch / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "tampered\n")
        prompt.chmod(0o600)

        replay = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(replay["replayed"])
        self.assertTrue(Path(replay["batch_path"]).is_dir())
        self.assertNotIn("tampered", prompt.read_text())
        self.assertTrue(any(batch.parent.glob(".rollup-quarantine.*")))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        # A published batch without a matching immutable pending receipt remains
        # an orphan and must never be adopted as current operator intent.
        con = sqlite3.connect(self.home / "decisions" / "decisions.db")
        con.execute("DELETE FROM decision_events WHERE event_type='answered_pending'")
        con.commit()
        con.close()
        self.assertIsNone(
            self._history(ids["primary"])["decision"]["answer_pending"])
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False)
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

    def test_database_atomicity_and_postcommit_publication_recovery(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        plan = self._alert(
            "plan-rollup-answer", card_id, ids["primary"], "1")

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env={
                "DECISION_ALERT_TESTING": "1",
                "DECISION_ALERT_TEST_FAIL_AFTER_PENDING_EVENT": "1",
            })
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

        (self.home / ".rollup-answer-test-continue").touch(mode=0o600)
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False,
            extra_env={
                "DASHBOARD_TESTING": "1",
                "DASHBOARD_TEST_ROLLUP_FAIL_BEFORE_COMMIT": "1",
            })
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])
        batch_parent = self.home / "answer-batches"
        self.assertFalse(any(batch_parent.glob(".rollup-stage.*")))
        self.assertFalse((batch_parent / plan["batch_key"]).exists())

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False,
            extra_env={
                "DASHBOARD_TESTING": "1",
                "DASHBOARD_TEST_ROLLUP_FAIL_AFTER_COMMIT": "1",
            })
        pending_digest = self._history(
            ids["primary"])["decision"]["answer_pending"][
                "artifact_manifest_sha256"]
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)
        self.assertFalse((batch_parent / plan["batch_key"]).exists())
        self.assertFalse(any(batch_parent.glob(".rollup-stage.*")))

        # Reproduction after a different wall-clock second proves the staged
        # bytes and persisted digest are deterministic, not timestamp-derived.
        time.sleep(1.1)
        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertEqual(recovered["manifest_sha256"], pending_digest)
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_ambient_rollup_failure_switches_are_ignored_outside_tests(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        result = self._dashboard(
            "decide", "answer-rollup", fixture["card"]["card_id"],
            ids["primary"], "1", extra_env={
                "DASHBOARD_TEST_ROLLUP_FAIL_BEFORE_COMMIT": "1",
                "DASHBOARD_TEST_ROLLUP_FAIL_AFTER_COMMIT": "1",
            })
        self.assertTrue(Path(result["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_batch_parent_symlink_and_rename_swap_fail_closed(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        outside = self.temp / "outside"
        outside.mkdir()
        (outside / "sentinel").write_text("unchanged\n")
        os.symlink(outside, self.home / "answer-batches")

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1", ok=False)
        self.assertEqual((outside / "sentinel").read_text(), "unchanged\n")
        self.assertEqual(list(outside.iterdir()), [outside / "sentinel"])
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

        (self.home / "answer-batches").unlink()
        batch_parent = self.home / "answer-batches"
        batch_parent.mkdir(mode=0o700)
        env = dict(self.env)
        env["DASHBOARD_TESTING"] = "1"
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-test-ready",
            "rollup transaction")
        old_parent = self.home / "answer-batches-old"
        batch_parent.rename(old_parent)
        batch_parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])
        self.assertFalse(any(old_parent.glob(".rollup-stage.*")))
        self.assertFalse(any(batch_parent.iterdir()))

    def test_postcommit_stage_mutation_is_quarantined_then_exactly_replayed(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "rollup transaction")
        stage = next((self.home / "answer-batches").glob(".rollup-stage.*"))
        prompt = stage / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "mutated-after-commit\n")
        prompt.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)
        parent = self.home / "answer-batches"
        self.assertFalse((parent / self._alert(
            "plan-rollup-answer", card_id, ids["primary"], "1")["batch_key"]).exists())
        self.assertTrue(any(parent.glob(".rollup-quarantine.*")))

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_postcommit_parent_swap_fails_then_replays_into_current_parent(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "rollup transaction")
        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-postcommit"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        self.assertTrue(os.path.samefile(Path(recovered["batch_path"]).parent, parent))
        self.assertTrue(any(old_parent.glob(".rollup-quarantine.*")))

    def test_existing_batch_mutated_during_replay_is_quarantined(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        initial = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch = Path(initial["batch_path"])

        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "replay")

        prompt = batch / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "mutated-during-replay\n")
        prompt.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        self.assertFalse(batch.exists())
        self.assertTrue(any(batch.parent.glob(".rollup-quarantine.*")))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_existing_batch_parent_swap_quarantines_pinned_artifact(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        initial = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch_name = Path(initial["batch_path"]).name

        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "replay")

        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-replay"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        self.assertFalse((old_parent / batch_name).exists())
        self.assertTrue(any(old_parent.glob(".rollup-quarantine.*")))
        self.assertEqual(list(parent.iterdir()), [])
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(os.path.samefile(Path(recovered["batch_path"]).parent, parent))
        self.assertTrue(Path(recovered["batch_path"]).is_dir())

    def test_existing_batch_parent_swap_quarantines_visible_conflict(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        initial = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch_name = Path(initial["batch_path"]).name

        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "replay")

        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-visible-conflict"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        conflict = parent / batch_name
        conflict.mkdir(mode=0o700)
        manifest = conflict / "manifest.json"
        manifest.write_text("{}\n")
        manifest.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        self.assertFalse((old_parent / batch_name).exists())
        self.assertTrue(any(old_parent.glob(".rollup-quarantine.*")))
        self.assertFalse(conflict.exists())
        self.assertTrue(any(parent.glob(".rollup-quarantine.*")))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(os.path.samefile(Path(recovered["batch_path"]).parent, parent))
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_existing_batch_parent_swap_quarantines_visible_regular_file(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        initial = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch_name = Path(initial["batch_path"]).name

        env = dict(self.env)
        env.update({
            "DASHBOARD_TESTING": "1",
            "DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT": "1",
        })
        proc = subprocess.Popen(
            ["/bin/bash", str(DASHBOARD), "decide", "answer-rollup",
             card_id, ids["primary"], "1"],
            env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._await_pause(
            proc, self.home / ".rollup-answer-postcommit-test-ready",
            "replay")

        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-regular-conflict"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        conflict = parent / batch_name
        conflict.write_text("occupied canonical name\n")
        conflict.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=30)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        self.assertFalse((old_parent / batch_name).exists())
        self.assertTrue(any(old_parent.glob(".rollup-quarantine.*")))
        self.assertFalse(conflict.exists())
        self.assertTrue(any(parent.glob(".rollup-quarantine.*")))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(os.path.samefile(Path(recovered["batch_path"]).parent, parent))
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_receipt_backed_canonical_symlink_is_quarantined_and_rebuilt(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        initial = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch = Path(initial["batch_path"])
        parent = batch.parent
        held = parent / (batch.name + ".held")
        batch.rename(held)
        os.symlink(held.name, batch)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")

        self.assertTrue(recovered["replayed"])
        self.assertTrue(batch.is_dir())
        self.assertFalse(batch.is_symlink())
        self.assertTrue(held.is_dir())
        quarantines = list(parent.glob(".rollup-quarantine.*"))
        self.assertTrue(any(path.is_symlink() for path in quarantines))
        replay = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(replay["replayed"])
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_orphan_first_answer_symlink_is_untouched(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        plan = self._alert(
            "plan-rollup-answer", card_id, ids["primary"], "1")
        parent = self.home / "answer-batches"
        parent.mkdir(mode=0o700)
        held = parent / "unrelated-held"
        held.mkdir(mode=0o700)
        canonical = parent / plan["batch_key"]
        os.symlink(held.name, canonical)

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False)

        self.assertTrue(canonical.is_symlink())
        self.assertTrue(held.is_dir())
        self.assertFalse(any(parent.glob(".rollup-quarantine.*")))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])

    def test_quarantine_name_swap_rolls_back_unbound_replacement(self) -> None:
        parent = self.temp / "quarantine-race"
        parent.mkdir(mode=0o700)
        canonical = parent / "canonical"
        canonical.write_text("receipt-backed\n")
        canonical.chmod(0o600)
        replacement = parent / "replacement"
        replacement.write_text("unbound replacement\n")
        replacement.chmod(0o600)
        raced = False
        with contextlib.ExitStack() as stack:
            parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            stack.callback(os.close, parent_fd)
            held_fd = os.open(
                canonical, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
            stack.callback(os.close, held_fd)
            real_rename = COMPOSER.os.rename

            def racing_rename(src, dst, *, src_dir_fd=None, dst_dir_fd=None):
                nonlocal raced
                if src == "canonical" and str(dst).startswith(
                        ".rollup-quarantine.") and not raced:
                    raced = True
                    real_rename(
                        "canonical", "held-away",
                        src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
                    real_rename(
                        "replacement", "canonical",
                        src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)
                return real_rename(
                    src, dst, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)

            stack.enter_context(mock.patch.object(
                COMPOSER.os, "rename", side_effect=racing_rename))
            with self.assertRaisesRegex(RuntimeError, "path changed"):
                COMPOSER._quarantine_rollup_entry(
                    parent_fd, "canonical", held_fd, "race")

        self.assertTrue(raced)
        self.assertEqual(canonical.read_text(), "unbound replacement\n")
        self.assertEqual((parent / "held-away").read_text(), "receipt-backed\n")
        self.assertFalse(any(parent.glob(".rollup-quarantine.*")))

    def test_public_answer_refreshes_local_views_without_provider_send(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        no_send_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
        }
        self._proc(
            ["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
            extra_env=no_send_env)
        self._proc(
            ["/bin/bash", str(DASHBOARD), "refresh", "attention"],
            extra_env=no_send_env)
        before = json.loads((self.home / "data" / "decisions.json").read_text())
        before_by_id = {row["id"]: row for row in before["data"]["pinned"]}
        self.assertIsNone(before_by_id[ids["primary"]]["answer_pending"])
        attention_path = self.home / "data" / "attention.json"
        attention_before = json.loads(attention_path.read_text())
        attention_before_ids = {
            row["id"] for row in attention_before["data"]["board"]}
        self.assertIn(ids["primary"], attention_before_ids)
        self.assertIn(ids["equivalent"], attention_before_ids)

        # Persist both Morning Brief surfaces before the answer. The public
        # transaction itself must reconcile these already-existing views; a
        # later preview is not evidence that its reported success was coherent.
        data_dir = self.home / "data"
        self._seed_brief_inputs()
        brief_env = {
            **no_send_env,
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        latest_path = self.home / "morning-brief" / "latest.json"
        brief_feed_path = data_dir / "brief.json"
        latest_before = latest_path.read_text()
        brief_feed_before = brief_feed_path.read_text()
        for decision_id in ids.values():
            self.assertIn(decision_id, latest_before)
            self.assertIn(decision_id, brief_feed_before)

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            extra_env=brief_env)
        after = json.loads((self.home / "data" / "decisions.json").read_text())
        after_by_id = {row["id"]: row for row in after["data"]["pinned"]}
        self.assertIsNotNone(after_by_id[ids["primary"]]["answer_pending"])
        self.assertIsNotNone(after_by_id[ids["equivalent"]]["answer_pending"])
        attention_after = json.loads(attention_path.read_text())
        attention_after_ids = {
            row["id"] for row in attention_after["data"]["board"]}
        self.assertNotIn(ids["primary"], attention_after_ids)
        self.assertNotIn(ids["equivalent"], attention_after_ids)
        self.assertIn(ids["independent"], attention_after_ids)
        latest_after = latest_path.read_text()
        brief_feed_after = brief_feed_path.read_text()
        self.assertNotEqual(latest_before, latest_after)
        self.assertNotEqual(brief_feed_before, brief_feed_after)
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertNotIn(decision_id, latest_after)
            self.assertNotIn(decision_id, brief_feed_after)
        self.assertIn(ids["independent"], latest_after)
        self.assertIn(ids["independent"], brief_feed_after)
        self.assertFalse(marker.exists())

    def test_public_answer_refreshes_delivered_brief_without_resend(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)

        # Generate the receipt through the real delivery transaction and a
        # hermetic sender. Clear its marker so the assertion below covers only
        # the public answer path, which must never resend.
        self._proc([str(ROOT / "scripts" / "morning-brief"), "--send"],
                   extra_env=brief_env)
        self.assertTrue(marker.exists())
        marker.unlink()

        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        latest = json.loads(latest_path.read_text())
        brief_id = latest["brief_id"]
        delivered_hash = latest["markdown_sha256"]
        latest["delivery"] = {
            # Receipt is authoritative even if a prior process died before it
            # copied delivered state back into the sidecar.
            "state": "not_sent", "confirmed_chunks": 0, "total_chunks": 0,
        }
        latest_path.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")
        delivery_dir = brief_home / "delivery"
        receipt_path = delivery_dir / (brief_id + ".json")
        cursor_path = brief_home / "delivery-cursor.json"
        receipt_before = receipt_path.read_text()
        cursor_before = cursor_path.read_text()
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)

        # Let another required input become stale after compose. The local
        # refresh must keep sidecar health and the rebuilt NEEDS YOU text equal.
        automation_path = self.home / "data" / "automation.json"
        automation = json.loads(automation_path.read_text())
        automation["generated_epoch"] = 1784360000
        automation_path.write_text(json.dumps(automation))

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            extra_env=brief_env)

        refreshed = json.loads(latest_path.read_text())
        self.assertEqual(refreshed["brief_id"], brief_id)
        self.assertEqual(refreshed["delivery"]["state"], "delivered")
        self.assertEqual(
            refreshed["local_refresh"]["delivered_markdown_sha256"], delivered_hash)
        self.assertEqual(
            refreshed["local_refresh"]["delivered_receipt_sha256"],
            hashlib.sha256(receipt_before.encode("utf-8")).hexdigest())
        self.assertEqual(refreshed["inputs"]["automation"]["state"], "stale")
        self.assertIn("automation", refreshed["stale_required_inputs"])
        needs = next(
            section for section in refreshed["sections"]
            if section["title"] == "NEEDS YOU")
        self.assertTrue(any(
            "Required inputs are not current: automation" in row["text"]
            for row in needs["lines"]))
        rendered = latest_path.read_text()
        brief_feed = (self.home / "data" / "brief.json").read_text()
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertNotIn(decision_id, rendered)
            self.assertNotIn(decision_id, brief_feed)
        self.assertIn(ids["independent"], rendered)
        self.assertIn(ids["independent"], brief_feed)
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(cursor_path.read_text(), cursor_before)
        self.assertFalse(marker.exists())

        replay = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            extra_env=brief_env)
        self.assertTrue(replay["replayed"])
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(cursor_path.read_text(), cursor_before)
        self.assertFalse(marker.exists())

    def test_public_answer_rejects_delivered_brief_without_valid_receipt(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)

        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        markdown_path = brief_home / "latest.md"
        latest = json.loads(latest_path.read_text())
        latest["delivery"] = {
            "state": "delivered", "confirmed_chunks": 1, "total_chunks": 1,
        }
        latest_path.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")
        delivery_dir = brief_home / "delivery"
        delivery_dir.mkdir(mode=0o700)
        receipt_path = delivery_dir / (latest["brief_id"] + ".json")
        # Matching top-level counters are not enough: without the confirmed
        # per-chunk digest list this cannot bind the delivered bytes.
        receipt_path.write_text(json.dumps({
            "schema": 1, "brief_id": latest["brief_id"], "state": "delivered",
            "confirmed_chunks": 1, "total_chunks": 1,
        }, indent=2, sort_keys=True) + "\n")
        receipt_path.chmod(0o600)
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        brief_feed_path = self.home / "data" / "brief.json"
        latest_before = latest_path.read_text()
        markdown_before = markdown_path.read_text()
        receipt_before = receipt_path.read_text()
        feed_before = brief_feed_path.read_text()

        failed = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env=brief_env)

        self.assertTrue(json.loads(failed["stdout"])["ok"])
        self.assertIn("committed but local view refresh failed", failed["stderr"])
        self.assertIsNotNone(self._history(ids["primary"])["decision"]["answer_pending"])
        self.assertEqual(latest_path.read_text(), latest_before)
        self.assertEqual(markdown_path.read_text(), markdown_before)
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(brief_feed_path.read_text(), feed_before)
        self.assertFalse(marker.exists())

    def test_public_answer_rejects_unbound_delivered_receipt(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)
        self._proc([str(ROOT / "scripts" / "morning-brief"), "--send"],
                   extra_env=brief_env)

        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        markdown_path = brief_home / "latest.md"
        latest = json.loads(latest_path.read_text())
        receipt_path = brief_home / "delivery" / (latest["brief_id"] + ".json")
        receipt = json.loads(receipt_path.read_text())
        receipt["chunks"][0]["content_hash"] = "a" * 64
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
        receipt_path.chmod(0o600)
        marker.unlink()
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        brief_feed_path = self.home / "data" / "brief.json"
        latest_before = latest_path.read_text()
        markdown_before = markdown_path.read_text()
        receipt_before = receipt_path.read_text()
        feed_before = brief_feed_path.read_text()

        failed = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env=brief_env)

        self.assertTrue(json.loads(failed["stdout"])["ok"])
        self.assertIn("committed but local view refresh failed", failed["stderr"])
        self.assertIsNotNone(self._history(ids["primary"])["decision"]["answer_pending"])
        self.assertEqual(latest_path.read_text(), latest_before)
        self.assertEqual(markdown_path.read_text(), markdown_before)
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(brief_feed_path.read_text(), feed_before)
        self.assertFalse(marker.exists())

    def test_public_answer_rejects_missing_delivery_binding_fields(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)
        self._proc([str(ROOT / "scripts" / "morning-brief"), "--send"],
                   extra_env=brief_env)

        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        markdown_path = brief_home / "latest.md"
        latest = json.loads(latest_path.read_text())
        receipt_path = brief_home / "delivery" / (latest["brief_id"] + ".json")
        complete_receipt = json.loads(receipt_path.read_text())
        marker.unlink()
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        brief_feed_path = self.home / "data" / "brief.json"

        for missing_field in ("markdown_sha256", "chunk_bytes"):
            with self.subTest(missing_field=missing_field):
                incomplete = dict(complete_receipt)
                incomplete.pop(missing_field)
                receipt_path.write_text(
                    json.dumps(incomplete, indent=2, sort_keys=True) + "\n")
                receipt_path.chmod(0o600)
                latest_before = latest_path.read_text()
                markdown_before = markdown_path.read_text()
                receipt_before = receipt_path.read_text()
                feed_before = brief_feed_path.read_text()

                failed = self._dashboard(
                    "decide", "answer-rollup", card_id, ids["primary"], "1",
                    ok=False, extra_env=brief_env)

                self.assertTrue(json.loads(failed["stdout"])["ok"])
                self.assertIn(
                    "committed but local view refresh failed", failed["stderr"])
                self.assertEqual(latest_path.read_text(), latest_before)
                self.assertEqual(markdown_path.read_text(), markdown_before)
                self.assertEqual(receipt_path.read_text(), receipt_before)
                self.assertEqual(brief_feed_path.read_text(), feed_before)
                self.assertFalse(marker.exists())

    def test_public_answer_preserves_prior_day_inflight_brief(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)

        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        markdown_path = brief_home / "latest.md"
        latest = json.loads(latest_path.read_text())
        latest["generated_epoch"] = 1784368800 - 86400
        latest["delivery"] = {
            "state": "pending", "confirmed_chunks": 0, "total_chunks": 1,
        }
        latest_path.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")
        delivery_dir = brief_home / "delivery"
        delivery_dir.mkdir(mode=0o700)
        receipt_path = delivery_dir / (latest["brief_id"] + ".json")
        receipt_path.write_text(json.dumps({
            "schema": 1, "brief_id": latest["brief_id"], "state": "pending",
            "confirmed_chunks": 0, "total_chunks": 1,
        }, indent=2, sort_keys=True) + "\n")
        receipt_path.chmod(0o600)
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        brief_feed_path = self.home / "data" / "brief.json"
        latest_before = latest_path.read_text()
        markdown_before = markdown_path.read_text()
        receipt_before = receipt_path.read_text()
        feed_before = brief_feed_path.read_text()

        failed = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env=brief_env)

        self.assertTrue(json.loads(failed["stdout"])["ok"])
        self.assertIn("committed but local view refresh failed", failed["stderr"])
        self.assertIsNotNone(self._history(ids["primary"])["decision"]["answer_pending"])
        self.assertEqual(latest_path.read_text(), latest_before)
        self.assertEqual(markdown_path.read_text(), markdown_before)
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(brief_feed_path.read_text(), feed_before)
        self.assertFalse(marker.exists())

    def test_public_single_answer_refreshes_local_views_without_send(self) -> None:
        ingested = self._ingest("owner-a", "one")
        decision_id = ingested["decision"]["id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        latest_path = self.home / "morning-brief" / "latest.json"
        brief_feed_path = self.home / "data" / "brief.json"
        self.assertIn(decision_id, latest_path.read_text())
        self.assertIn(decision_id, brief_feed_path.read_text())

        answered = self._proc(
            ["/bin/bash", str(DASHBOARD), "decide", "answer", decision_id, "1"],
            extra_env=brief_env)

        self.assertIn("prompt:", answered.stdout)
        decision = self._history(decision_id)["decision"]
        self.assertEqual(decision["state"], "open")
        self.assertIsNotNone(decision["answer_pending"])
        self.assertEqual(decision["answer_pending"]["mode"], "single")
        self.assertEqual(decision["lifecycle"]["state"], "answered_pending")
        self.assertNotIn(decision_id, latest_path.read_text())
        self.assertNotIn(decision_id, brief_feed_path.read_text())
        self.assertFalse(marker.exists())

        prompt_path = self.home / "prompts" / (decision_id + ".md")
        prompt_before = prompt_path.read_bytes()
        replay = self._proc(
            ["/bin/bash", str(DASHBOARD), "decide", "answer", decision_id, "1"],
            extra_env=brief_env)
        self.assertIn("prompt:", replay.stdout)
        self.assertEqual(prompt_path.read_bytes(), prompt_before)
        events = self._pending_events(decision_id)
        self.assertEqual(len(events), 1)
        self._proc(
            ["/bin/bash", str(DASHBOARD), "decide", "answer", decision_id, "2"],
            ok=False, extra_env=brief_env)
        self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_public_answer_fails_closed_for_inflight_brief_delivery(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nprintf '%s\n' delivered\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_INCIDENTS_CHAT_ID": "123",
            "MORNING_BRIEF_NOW_EPOCH": "1784368800",
        }
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
                   extra_env=brief_env)
        self._seed_brief_inputs()
        self._proc([str(ROOT / "scripts" / "morning-brief")],
                   extra_env=brief_env)
        brief_home = self.home / "morning-brief"
        latest_path = brief_home / "latest.json"
        markdown_path = brief_home / "latest.md"
        latest = json.loads(latest_path.read_text())
        latest["delivery"] = {
            "state": "pending", "confirmed_chunks": 0, "total_chunks": 1,
        }
        latest_path.write_text(json.dumps(latest, indent=2, sort_keys=True) + "\n")
        delivery_dir = brief_home / "delivery"
        delivery_dir.mkdir(mode=0o700)
        receipt_path = delivery_dir / (latest["brief_id"] + ".json")
        receipt_path.write_text(json.dumps({
            "schema": 1, "brief_id": latest["brief_id"], "state": "pending",
            "confirmed_chunks": 0, "total_chunks": 1,
        }, indent=2, sort_keys=True) + "\n")
        receipt_path.chmod(0o600)
        self._proc(["/bin/bash", str(DASHBOARD), "refresh", "brief"],
                   extra_env=brief_env)
        brief_feed_path = self.home / "data" / "brief.json"
        latest_before = latest_path.read_text()
        markdown_before = markdown_path.read_text()
        receipt_before = receipt_path.read_text()
        feed_before = brief_feed_path.read_text()

        failed = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env=brief_env)

        self.assertTrue(json.loads(failed["stdout"])["ok"])
        self.assertIn("committed but local view refresh failed", failed["stderr"])
        self.assertIsNotNone(self._history(ids["primary"])["decision"]["answer_pending"])
        self.assertEqual(latest_path.read_text(), latest_before)
        self.assertEqual(markdown_path.read_text(), markdown_before)
        self.assertEqual(receipt_path.read_text(), receipt_before)
        self.assertEqual(brief_feed_path.read_text(), feed_before)
        self.assertFalse(marker.exists())

    def test_public_answer_ignores_stale_installed_decision_reader(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        no_send_env = {"DECISION_ALERT_AUTO": "0"}
        self._proc(
            ["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
            extra_env=no_send_env)
        stale_payload = json.loads(
            (self.home / "data" / "decisions.json").read_text())

        marker = self.temp / "stale-installed-reader-invoked"
        installed = self.home / "bin" / "decision-alert"
        installed.parent.mkdir(mode=0o700)
        installed.write_text(
            "#!/usr/bin/env python3\n"
            "import os\n"
            "from pathlib import Path\n"
            "Path(os.environ['STALE_READER_MARKER']).touch()\n"
            "print(%r)\n" % json.dumps(stale_payload, sort_keys=True))
        installed.chmod(0o700)
        stale_brief_marker = self.temp / "stale-installed-brief-invoked"
        installed_brief = self.home / "bin" / "morning-brief"
        installed_brief.write_text(
            "#!/bin/sh\n"
            "touch \"$STALE_BRIEF_MARKER\"\n"
            "exit 17\n")
        installed_brief.chmod(0o700)
        stale_composer_marker = self.temp / "stale-composer-invoked"
        stale_repo_scripts = self.temp / "stale-repo" / "scripts"
        stale_repo_scripts.mkdir(parents=True, mode=0o700)
        stale_composer = stale_repo_scripts / "compose-decision-prompt.py"
        stale_composer.write_text(
            "#!/bin/sh\n"
            "touch \"$STALE_COMPOSER_MARKER\"\n"
            "exit 17\n")
        stale_composer.chmod(0o700)

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            extra_env={
                **no_send_env,
                "STALE_READER_MARKER": str(marker),
                "STALE_BRIEF_MARKER": str(stale_brief_marker),
                "MORNING_BRIEF_NOW_EPOCH": "1784368800",
                "DASHBOARD_CMD_DECISIONS": str(installed),
                "DASHBOARD_CMD_BRIEF": str(installed_brief),
                "REPO_ROOT": str(stale_repo_scripts.parent),
                "STALE_COMPOSER_MARKER": str(stale_composer_marker),
            })
        feed = json.loads((self.home / "data" / "decisions.json").read_text())
        by_id = {row["id"]: row for row in feed["data"]["pinned"]}
        self.assertIsNotNone(by_id[ids["primary"]]["answer_pending"])
        self.assertIsNotNone(by_id[ids["equivalent"]]["answer_pending"])
        self.assertIsNone(by_id[ids["independent"]]["answer_pending"])
        self.assertFalse(marker.exists())
        self.assertFalse(stale_brief_marker.exists())
        self.assertFalse(stale_composer_marker.exists())

    def test_public_answer_reports_committed_feed_refresh_failure(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        data_dir = self.home / "data"
        data_dir.mkdir(mode=0o700)
        # A directory at the feed destination forces the real exact-runtime
        # collector's atomic replace to fail; no ambient feeder override is
        # needed (or trusted) by the public answer transaction.
        (data_dir / "decisions.json").mkdir(mode=0o700)
        failed = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False, extra_env={
                "DECISION_ALERT_AUTO": "0",
            })
        payload = json.loads(failed["stdout"])
        self.assertTrue(payload["ok"])
        self.assertIn("committed", failed["stderr"])
        self.assertIsNotNone(
            self._history(ids["primary"])["decision"]["answer_pending"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
