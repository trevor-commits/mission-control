#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("resource-health")


def fixture(**overrides):
    payload = {
        "schema": "resource-governor-status-v1",
        "checked_epoch": 1000,
        "metrics": {
            "pressure_state": "normal",
            "swap_used_mb": 500.0,
            "swap_rate_mb_per_minute": 2.0,
            "effective_free_gib": 40.0,
            "raw_free_gib": 50.0,
        },
        "admit": {"free_percent": 45.0},
        "memory_guard": {
            "age_seconds": 20,
            "stale": False,
            "summary": {"health": "green"},
        },
        "disk_guard": {
            "age_seconds": 30,
            "stale": False,
            "summary": {"status": "ok"},
        },
        "watchdog": {"memory_guard": "ok", "disk_guard": "ok"},
        "slo": {
            "thresholds": {
                "disk_floor_gib": 25.0,
                "disk_target_gib": 40.0,
                "swap_rate_alarm_mb_per_min": 80.0,
            }
        },
        "alerts": [],
        "top_rss": [{"pid": 7, "family": "Hermes", "rss_mb": 900.0, "summary": "/private/path secret"}],
        "recent_incidents": [],
    }
    payload.update(overrides)
    return payload


class ResourceHealthTest(unittest.TestCase):
    def run_feed(self, payload=None, now=1100, activity=None):
        with tempfile.TemporaryDirectory() as tmp:
            status = Path(tmp) / "status.json"
            if payload is not None:
                status.write_text(json.dumps(payload), encoding="utf-8")
            activity_command = "off"
            if activity is not None:
                activity_script = Path(tmp) / "activity.py"
                activity_script.write_text(
                    "#!/usr/bin/env python3\nprint(" + repr(json.dumps(activity)) + ")\n",
                    encoding="utf-8",
                )
                activity_script.chmod(0o755)
                activity_command = str(activity_script)
            env = os.environ.copy()
            env.update(
                {
                    "MISSION_CONTROL_RESOURCE_STATUS": str(status),
                    "MISSION_CONTROL_NOW_EPOCH": str(now),
                    "MISSION_CONTROL_ACTIVITY_COMMAND": activity_command,
                }
            )
            result = subprocess.run(
                [str(SCRIPT)], env=env, text=True, capture_output=True, check=True
            )
            return json.loads(result.stdout)

    def test_green_status_is_compact_and_sanitized(self):
        data = self.run_feed(fixture())
        self.assertEqual(data["state"], "green")
        self.assertEqual(data["issue_codes"], [])
        self.assertEqual(data["memory"]["pressure"], "normal")
        self.assertEqual(data["disk"]["effective_free_gib"], 40.0)
        self.assertNotIn("summary", data["top_rss"][0])
        self.assertNotIn("command", data["top_rss"][0])
        self.assertNotIn("host", data)

    def test_warning_identifies_memory_and_disk(self):
        payload = fixture(
            metrics={
                "pressure_state": "warning",
                "swap_used_mb": 4096.0,
                "swap_rate_mb_per_minute": 120.0,
                "effective_free_gib": 29.0,
                "raw_free_gib": 35.0,
            },
            disk_guard={"age_seconds": 20, "stale": False, "summary": {"status": "alert"}},
            alerts=[{"key": "pressure", "severity": "warning", "title": "Memory pressure", "message": "Watch it"}],
        )
        data = self.run_feed(payload)
        self.assertEqual(data["state"], "amber")
        self.assertEqual(data["issue_codes"], ["M", "D"])
        self.assertEqual(data["memory"]["state"], "amber")
        self.assertEqual(data["disk"]["state"], "amber")

    def test_critical_pressure_is_red(self):
        payload = fixture(
            metrics={
                "pressure_state": "critical",
                "swap_used_mb": 12000.0,
                "swap_rate_mb_per_minute": 500.0,
                "effective_free_gib": 20.0,
                "raw_free_gib": 25.0,
            },
            alerts=[{"key": "pressure", "severity": "critical", "title": "Critical", "message": "Act"}],
        )
        data = self.run_feed(payload)
        self.assertEqual(data["state"], "red")
        self.assertIn("M", data["issue_codes"])
        self.assertIn("D", data["issue_codes"])

    def test_stale_status_fails_visible(self):
        data = self.run_feed(fixture(), now=1300)
        self.assertEqual(data["state"], "red")
        self.assertFalse(data["fresh"])
        self.assertEqual(data["watchdog"]["state"], "red")

    def test_activity_summary_preserves_counts_without_task_content(self):
        activity = {
            "schema": "resource-governor-activity-v1",
            "exact": False,
            "working_count": 2,
            "waiting_count": 1,
            "cooling_count": 1,
            "unknown_provider_count": 1,
            "providers": {
                "cursor": {
                    "state": "active",
                    "exact": True,
                    "working_count": 2,
                    "waiting_count": 1,
                    "cooling_count": 1,
                    "source_health": {"status": "ok", "path": "/private/transcript"},
                    "restart_horizon": {"state": "active", "reason": "private task"},
                    "tasks": [{"text": "secret task content"}],
                }
            },
            "longest_task": {
                "provider": "cursor",
                "label": "cursor:ab12cd",
                "phase": "tool-work",
                "eta_min_minutes": 15,
                "eta_max_minutes": 60,
                "eta_kind": "phase-range-not-countdown",
                "confidence": "low",
                "private_text": "do not expose",
            },
            "mac_restart_horizon": {"state": "blocked", "reason": "unknown-activity"},
        }
        data = self.run_feed(fixture(), activity=activity)
        self.assertFalse(data["activity"]["exact"])
        self.assertEqual(data["activity"]["working_count"], 2)
        self.assertEqual(data["activity"]["providers"][0]["name"], "cursor")
        self.assertEqual(data["activity"]["longest_task"]["label"], "cursor:ab12cd")
        self.assertNotIn("private_text", data["activity"]["longest_task"])
        self.assertNotIn("tasks", data["activity"]["providers"][0])
        self.assertNotIn("path", data["activity"]["providers"][0])

    def test_missing_status_fails_visible(self):
        data = self.run_feed(None)
        self.assertEqual(data["state"], "red")
        self.assertEqual(data["issue_codes"], ["!"])
        self.assertFalse(data["fresh"])


if __name__ == "__main__":
    unittest.main()
