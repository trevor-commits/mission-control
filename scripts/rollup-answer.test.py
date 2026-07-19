#!/usr/bin/env python3
"""Hermetic contract tests for answered-pending rollup answers.

Every test uses a temporary Mission Control home and, when needed, a temporary
chat-graph database. No provider, live store, installation, or network path is
reachable from this suite.
"""

from __future__ import annotations

import hashlib
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


ROOT = Path(__file__).resolve().parent.parent
ALERT = ROOT / "scripts" / "decision-alert"
DASHBOARD = ROOT / "scripts" / "dashboard"

TEXT = (
    "**DECISION NEEDED:** Approve `feature/rollup`. "
    "**`Approve`** or **`Wait`**."
)


class RollupAnswerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp(prefix="mc-rollup-answer-test."))
        self.home = self.temp / "state"
        self.home.mkdir(mode=0o700)
        self.env = dict(os.environ)
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
            argv, env=env, text=True, capture_output=True, timeout=15, check=False)
        if ok and proc.returncode != 0:
            self.fail("command failed (%s): %s\nstdout=%s\nstderr=%s" % (
                proc.returncode, argv, proc.stdout, proc.stderr))
        if not ok and proc.returncode == 0:
            self.fail("command unexpectedly succeeded: %s\nstdout=%s" % (argv, proc.stdout))
        return proc

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
        resolution_key = "rk-%s-%s" % (owner, item)
        result = self._alert(
            "ingest", "--source-kind", "chat",
            "--source-key", "outcome:%s:%s" % (owner, item),
            "--text", text,
            "--evidence", evidence or ("evidence-%s-%s" % (owner, item)),
            "--trust", "structured", "--provenance", "chat-graph tier1",
            "--resolution-key", resolution_key)
        result["resolution_key"] = resolution_key
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

    def test_verified_consumption_resolves_only_the_exact_member(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")

        self._alert(
            "resolve", ids["primary"], "--evidence-type", "manual_resolution",
            "--evidence-ref", "manual-not-consumption", ok=False)

        graph = self.temp / "graph.db"
        con = sqlite3.connect(graph)
        con.execute("""CREATE TABLE open_ends(
            session_id TEXT, kind TEXT, item_key TEXT, resolved_at INTEGER,
            resolution_evidence_type TEXT, resolution_evidence_ref TEXT)""")
        evidence_ref = "turn-owner-a-consumed-one"
        con.execute("INSERT INTO open_ends VALUES(?,?,?,?,?,?)", (
            "owner-a", "chat_open_end",
            fixture["resolution_keys"][ids["primary"]], 1784368801,
            "answering_user_turn", evidence_ref))
        con.commit()
        con.close()

        resolved = self._alert(
            "resolve", ids["primary"],
            "--evidence-type", "answering_user_turn",
            "--evidence-ref", evidence_ref,
            "--resolution-key", fixture["resolution_keys"][ids["primary"]],
            extra_env={"CHAT_GRAPH_DB": str(graph)})
        self.assertTrue(resolved["changed"])
        self.assertEqual(resolved["decision"]["state"], "resolved")
        self.assertIsNone(resolved["decision"]["answer_pending"])
        self.assertEqual(self._history(ids["equivalent"])["decision"]["state"], "open")
        self.assertIsNotNone(
            self._history(ids["equivalent"])["decision"]["answer_pending"])
        self.assertIsNone(
            self._history(ids["independent"])["decision"]["answer_pending"])

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

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False,
            extra_env={"DASHBOARD_TEST_ROLLUP_FAIL_BEFORE_COMMIT": "1"})
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(self._pending_events(decision_id), [])
        batch_parent = self.home / "answer-batches"
        self.assertFalse(any(batch_parent.glob(".rollup-stage.*")))
        self.assertFalse((batch_parent / plan["batch_key"]).exists())

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False,
            extra_env={"DASHBOARD_TEST_ROLLUP_FAIL_AFTER_COMMIT": "1"})
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
        ready = self.home / ".rollup-answer-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("rollup transaction did not reach test pause: %s %s" % (
                stdout, stderr))
        old_parent = self.home / "answer-batches-old"
        batch_parent.rename(old_parent)
        batch_parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("rollup transaction did not reach postcommit pause: %s %s" % (
                stdout, stderr))
        stage = next((self.home / "answer-batches").glob(".rollup-stage.*"))
        prompt = stage / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "mutated-after-commit\n")
        prompt.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("rollup transaction did not reach postcommit pause: %s %s" % (
                stdout, stderr))
        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-postcommit"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        self.assertTrue(str(Path(recovered["batch_path"])).startswith(str(parent)))
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("replay did not reach postcommit pause: %s %s" % (
                stdout, stderr))

        prompt = batch / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "mutated-during-replay\n")
        prompt.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("replay did not reach postcommit pause: %s %s" % (
                stdout, stderr))

        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-replay"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
        self.assertNotEqual(proc.returncode, 0, (stdout, stderr))
        self.assertFalse((old_parent / batch_name).exists())
        self.assertTrue(any(old_parent.glob(".rollup-quarantine.*")))
        self.assertEqual(list(parent.iterdir()), [])
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
        self.assertEqual(Path(recovered["batch_path"]).parent, parent)
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("replay did not reach postcommit pause: %s %s" % (
                stdout, stderr))

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
        stdout, stderr = proc.communicate(timeout=10)
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
        self.assertEqual(Path(recovered["batch_path"]).parent, parent)
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
        ready = self.home / ".rollup-answer-postcommit-test-ready"
        deadline = time.monotonic() + 5
        while not ready.exists() and time.monotonic() < deadline:
            if proc.poll() is not None:
                break
            time.sleep(0.01)
        if not ready.exists():
            stdout, stderr = proc.communicate(timeout=2)
            self.fail("replay did not reach postcommit pause: %s %s" % (
                stdout, stderr))

        parent = self.home / "answer-batches"
        old_parent = self.home / "answer-batches-old-regular-conflict"
        parent.rename(old_parent)
        parent.mkdir(mode=0o700)
        conflict = parent / batch_name
        conflict.write_text("occupied canonical name\n")
        conflict.chmod(0o600)
        (self.home / ".rollup-answer-postcommit-test-continue").touch(mode=0o600)
        stdout, stderr = proc.communicate(timeout=10)
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
        self.assertEqual(Path(recovered["batch_path"]).parent, parent)
        self.assertTrue(Path(recovered["batch_path"]).is_dir())
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

    def test_public_answer_refreshes_local_views_without_provider_send(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        no_send_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
        }
        self._proc(
            ["/bin/bash", str(DASHBOARD), "refresh", "decisions"],
            extra_env=no_send_env)
        before = json.loads((self.home / "data" / "decisions.json").read_text())
        before_by_id = {row["id"]: row for row in before["data"]["pinned"]}
        self.assertIsNone(before_by_id[ids["primary"]]["answer_pending"])

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
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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

    def test_public_answer_preserves_prior_day_inflight_brief(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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
        self.assertEqual(self._history(decision_id)["decision"]["state"], "resolved")
        self.assertNotIn(decision_id, latest_path.read_text())
        self.assertNotIn(decision_id, brief_feed_path.read_text())
        self.assertFalse(marker.exists())

    def test_public_answer_fails_closed_for_inflight_brief_delivery(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        marker = self.temp / "provider-send-invoked"
        sender = self.temp / "fake-sender"
        sender.write_text("#!/bin/sh\ntouch \"$DECISION_TEST_SEND_MARKER\"\nexit 0\n")
        sender.chmod(0o700)
        brief_env = {
            "DECISION_ALERT_AUTO": "0",
            "DECISION_ALERT_SEND_BIN": str(sender),
            "DECISION_TEST_SEND_MARKER": str(marker),
            "MORNING_BRIEF_SEND_BIN": str(sender),
            "MORNING_BRIEF_CHAT_ID": "123",
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
