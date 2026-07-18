#!/usr/bin/env python3
"""Hermetic contract tests for answered-pending rollup answers.

Every test uses a temporary Mission Control home and, when needed, a temporary
chat-graph database. No provider, live store, installation, or network path is
reachable from this suite.
"""

from __future__ import annotations

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

    def test_tampered_or_orphaned_published_batch_fails_closed(self) -> None:
        fixture = self._three_member_card()
        ids = fixture["ids"]
        card_id = fixture["card"]["card_id"]
        result = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        batch = Path(result["batch_path"])
        prompt = batch / "prompts" / (ids["primary"] + ".md")
        prompt.write_text(prompt.read_text() + "tampered\n")
        prompt.chmod(0o600)

        self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1",
            ok=False)
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)

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
        for decision_id in (ids["primary"], ids["equivalent"]):
            self.assertEqual(len(self._pending_events(decision_id)), 1)
        self.assertFalse((batch_parent / plan["batch_key"]).exists())
        self.assertFalse(any(batch_parent.glob(".rollup-stage.*")))

        recovered = self._dashboard(
            "decide", "answer-rollup", card_id, ids["primary"], "1")
        self.assertTrue(recovered["replayed"])
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
