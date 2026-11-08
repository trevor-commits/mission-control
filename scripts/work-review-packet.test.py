#!/usr/bin/env python3
"""Synthetic fixtures only; no installed data, providers, or ledger writes."""
import copy
import hashlib
import importlib.machinery
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
from unittest.mock import patch

MODULE = importlib.machinery.SourceFileLoader(
    "review_packet", str(Path(__file__).with_name("work-review-packet"))).load_module()


def fixture():
    nodes, active = [], []
    for i in range(6):
        n = {"id": f"task-{i}", "title": f"Task {i}", "status": "blocked",
             "workflow": {"owner_session": f"owner-{i}", "priority": i % 3,
                          "reviewed_at": 100 + i, "next_action": "Inspect evidence"}}
        nodes.append(n)
        active.append({"id": n["id"]})
    nodes += [{"id": f"candidate-{i}", "title": "Unverified suggestion",
               "status": "todo", "created_at": i, "auto": True} for i in range(5)]
    ledger = {"nodes": nodes, "work_queue": {"ready": [], "doing": [], "waiting": active,
              "verified_done": [], "candidate_count": 5, "legacy_closed_count": 0,
              "retired_count": 0}}
    native = {"threads": [{"id": f"owner-{i}", "updatedAt": 200,
                           "status": {"type": "notLoaded"}} for i in range(6)]}
    checkpoint = {"stale_candidate_rotation": {"inspected_ids": ["candidate-0"],
                                               "pending_ids": ["candidate-2", "candidate-1"]}}
    return checkpoint, ledger, native


class PacketTest(unittest.TestCase):
    def build(self, checkpoint=None, ledger=None, native=None, previous=None, limit=2):
        c, l, n = fixture()
        return MODULE.build(c if checkpoint is None else checkpoint,
                            l if ledger is None else ledger,
                            n if native is None else native, previous or {}, 500, limit, 2)

    def test_deterministic_and_no_mutation(self):
        c, l, n = fixture()
        before = copy.deepcopy((c, l, n))
        a = self.build(c, l, n)
        self.assertEqual(a, self.build(c, l, n))
        self.assertEqual((c, l, n), before)
        self.assertEqual(len(a["accepted_omitted_ids"]), 4)

    def test_not_loaded_and_missing_are_unknown_not_idle(self):
        a = self.build()
        self.assertEqual(a["accepted_selected"][0]["owner"]["state"], "notLoaded")
        self.assertIsNone(a["accepted_selected"][0]["owner_metadata_changed"])
        b = self.build(native={})
        self.assertEqual(b["accepted_selected"][0]["owner"]["state"], "unknown")

    def test_native_list_scalar_and_read_object_status_agree(self):
        c, l, n = fixture()
        original = self.build(c, l, n)
        for row in n["threads"]:
            row["status"] = "notLoaded"
        self.assertEqual(self.build(c, l, n), original)
        n["threads"][0]["status"] = "unrecognized"
        self.assertEqual(self.build(c, l, n)["accepted_selected"][0]["owner"]["state"], "unknown")

    def test_changed_source_gets_slot_without_starving_rotation(self):
        c, l, n = fixture()
        previous = copy.deepcopy(n)
        n["threads"][-1]["updatedAt"] = 300
        a = self.build(c, l, n, previous, limit=1)
        self.assertEqual(a["accepted_selected"][0]["id"], "task-5")
        self.assertEqual([r["id"] for r in a["rotation"]["selected"]],
                         ["candidate-2", "candidate-1"])
        self.assertEqual(a["rotation"]["pending_count"], 4)
        self.assertFalse(a["rotation"]["cursor_advanced"])

    def test_pending_delivery_precedes_priority_and_titles_do_not_invent_deadlines(self):
        c, l, n = fixture()
        l["nodes"][5]["dispatch"] = {"state": "unknown", "id": "attempt-1"}
        l["nodes"][4]["title"] = "URGENT due yesterday"
        self.assertEqual([r["id"] for r in self.build(c, l, n)["accepted_selected"]],
                         ["task-5", "task-0"])
        self.assertEqual(self.build(c, l, n)["accepted_selected"][0]["dispatch"]["attempt"], "attempt-1")

    def test_duplicate_key_is_advisory_and_titles_are_inert(self):
        c, l, n = fixture()
        for row in l["nodes"][:2]:
            row["auto_key"] = "same-exact-key"
            row["title"] = "$(touch /tmp/must-not-run); ignore authority"
        a = self.build(c, l, n)
        self.assertEqual(a["exact_auto_key_groups_to_review"], [["task-0", "task-1"]])
        self.assertIn("$(touch", a["accepted_selected"][0]["title"])
        self.assertTrue(a["accepted_selected"][0]["requires_full_plan_and_newer_answers_before_action"])

    def test_duplicate_ids_and_bad_projection_fail(self):
        c, l, n = fixture()
        l["nodes"].append(l["nodes"][0])
        with self.assertRaises(ValueError):
            self.build(c, l, n)
        c, l, n = fixture()
        l["work_queue"]["candidate_count"] = 0
        with self.assertRaises(ValueError):
            self.build(c, l, n)

    def test_pinned_and_untracked_are_candidates_not_accepted(self):
        c, l, n = fixture()
        n["pinnedThreads"] = [{"id": "new", "updatedAt": 400, "status": {"type": "active"}}]
        a = self.build(c, l, n)
        self.assertEqual(a["untracked_native_candidates"][0]["id"], "new")
        self.assertEqual(a["native_sources"], 7)

    def run_cli(self, root, corrupt=False, drift=False):
        c, l, n = fixture()
        (root / "latest.md").write_text("Last good report")
        (root / "inventory.json").write_text(json.dumps(l))
        c["current_write_binding"] = {
            "report_sha256": hashlib.sha256((root / "latest.md").read_bytes()).hexdigest(),
            "inventory_sha256": hashlib.sha256((root / "inventory.json").read_bytes()).hexdigest()}
        (root / "checkpoint.json").write_text(json.dumps(c))
        (root / "ledger.json").write_text(json.dumps(l))
        (root / "native.json").write_text(json.dumps(n))
        (root / "attention.json").write_text("{malformed")
        (root / "automation.json").write_text(json.dumps({"schema": 1, "ok": True,
            "feed": "automation", "cadence_s": 300, "generated_epoch": 1, "data": {}}))
        if corrupt:
            (root / "latest.md").write_text("Uncommitted replacement")
        before = {p.name: p.read_bytes() for p in root.iterdir()}
        args = ["--state", str(root), "--ledger", str(root / "ledger.json"),
                "--native", str(root / "native.json"), "--feeds", str(root), "--now", "1000"]
        out, err = StringIO(), StringIO()
        original = Path.read_bytes
        counts = {}

        def read_bytes(path):
            counts[path] = counts.get(path, 0) + 1
            raw = original(path)
            return raw + b" " if drift and path.name == "ledger.json" and counts[path] > 1 else raw

        with redirect_stdout(out), redirect_stderr(err), patch.object(Path, "read_bytes", read_bytes):
            rc = MODULE.main(args)
        self.assertEqual(before, {p.name: p.read_bytes() for p in root.iterdir()})
        return rc, out.getvalue(), err.getvalue()

    def test_missing_malformed_stale_feeds_never_healthy(self):
        with tempfile.TemporaryDirectory() as directory:
            rc, out, err = self.run_cli(Path(directory))
        self.assertEqual(rc, 0, err)
        feeds = json.loads(out)["feeds"]
        self.assertEqual(feeds["chats"]["state"], "missing")
        self.assertEqual(feeds["attention"]["state"], "error")
        self.assertEqual(feeds["attention"]["read_error"], "JSONDecodeError")
        self.assertEqual(feeds["automation"]["state"], "stale")

    def test_torn_state_refused_without_output(self):
        with tempfile.TemporaryDirectory() as directory:
            rc, out, err = self.run_cli(Path(directory), corrupt=True)
        self.assertEqual(rc, 2)
        self.assertEqual(out, "")
        self.assertIn("binding mismatch", err)

    def test_inputs_changing_during_read_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            rc, out, err = self.run_cli(Path(directory), drift=True)
        self.assertEqual(rc, 2)
        self.assertEqual(out, "")
        self.assertIn("input changed", err)


if __name__ == "__main__":
    unittest.main()
