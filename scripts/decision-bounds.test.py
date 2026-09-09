#!/usr/bin/env python3
"""Hermetic bounds tests for decision answer transactions."""
from __future__ import annotations

import fcntl
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "scripts" / "compose-decision-prompt.py"
SPEC = importlib.util.spec_from_file_location("decision_bounds_composer", MODULE)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load decision composer")
COMPOSER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPOSER)


class DecisionBoundsTests(unittest.TestCase):
    def _script(self, root: Path, body: str) -> Path:
        path = root / "alert"
        path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
        path.chmod(0o700)
        return path

    def test_alert_timeout_has_bounded_failure(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            alert = self._script(root, "sleep 2")
            with mock.patch.dict(os.environ, {"DECISION_ALERT_TIMEOUT_S": "1"}):
                started = time.monotonic()
                with self.assertRaisesRegex(RuntimeError, "timed out"):
                    COMPOSER._run_alert(str(alert), str(root), "history", "x")
            self.assertLess(time.monotonic() - started, 1.8)

    def test_alert_output_exceeding_cap_has_bounded_failure(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            alert = self._script(root, "python3 -c 'print(\"x\" * 4096)'")
            with mock.patch.dict(os.environ, {"DECISION_ALERT_MAX_OUTPUT_BYTES": "1024"}):
                with self.assertRaisesRegex(RuntimeError, "output exceeded"):
                    COMPOSER._run_alert(str(alert), str(root), "history", "x")

    def test_held_transaction_lock_returns_retryable_busy(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "lock"
            first = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
            second = os.open(path, os.O_RDWR)
            try:
                fcntl.flock(first, fcntl.LOCK_EX)
                with self.assertRaisesRegex(COMPOSER.RetryableBusyError, "busy; retry"):
                    COMPOSER._bounded_flock(second, "decision answer", timeout_s=0.05)
            finally:
                os.close(second)
                os.close(first)

    def test_answer_cli_maps_held_lock_to_retry_exit(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw) / "state"
            answers = home / "answers"
            answers.mkdir(parents=True, mode=0o700)
            decision_id = "decision:0123456789abcdef01234567"
            lock = answers / (".%s.lock" % decision_id)
            held = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
            try:
                fcntl.flock(held, fcntl.LOCK_EX)
                env = dict(os.environ)
                env["DECISION_LOCK_TIMEOUT_S"] = "1"
                proc = subprocess.run(
                    [sys.executable, str(MODULE), "--answer-transaction",
                     "--home", str(home), "--decision-alert", "/bin/true",
                     "--decision-id", decision_id, "--choice", "1"],
                    env=env, text=True, capture_output=True, timeout=5, check=False)
                self.assertEqual(proc.returncode, 75, proc.stderr)
                self.assertIn("busy; retry", proc.stderr)
            finally:
                os.close(held)


if __name__ == "__main__":
    unittest.main(verbosity=2)
