#!/usr/bin/env python3
"""Hermetic contracts for dashboard home resolution and demo projection."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
DASHBOARD = ROOT / "scripts" / "dashboard"


class DashboardDemoContracts(unittest.TestCase):
    def test_demo_projects_every_static_asset_the_live_page_uses(self) -> None:
        env = dict(os.environ)
        env["DASHBOARD_NO_OPEN"] = "1"
        proc = subprocess.run(["/bin/bash", str(DASHBOARD), "demo"], cwd=ROOT,
                              env=env, text=True, capture_output=True,
                              timeout=60, check=False)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        found = re.search(r"^demo state: (.+)$", proc.stdout, re.MULTILINE)
        if found is None:
            self.fail(proc.stdout)
        state = Path(found.group(1))
        try:
            expected = ["index.html", "panel.html", "jobs.json",
                        "vendor/cytoscape.min.js"]
            for relative in expected:
                self.assertTrue((state / relative).is_file(), relative)
            for fixture in (ROOT / "dashboard" / "fixtures").glob("*.json"):
                self.assertTrue((state / "data" / fixture.name).is_file(), fixture.name)
                self.assertTrue((state / "data" / (fixture.stem + ".js")).is_file(),
                                fixture.stem + ".js")
        finally:
            shutil.rmtree(state, ignore_errors=True)

    def test_dashboard_expands_tilde_state_home_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw) / "home"
            home.mkdir()
            env = dict(os.environ, HOME=str(home), MISSION_CONTROL_HOME="~/state",
                       DASHBOARD_INSTALL_NO_LAUNCHD="1", DASHBOARD_NO_OPEN="1")
            proc = subprocess.run(["/bin/bash", str(DASHBOARD), "install"], cwd=raw,
                                  env=env, text=True, capture_output=True,
                                  timeout=60, check=False)
            self.assertNotEqual(proc.returncode, 2, proc.stderr)
            self.assertTrue((home / "state").is_dir())
            self.assertFalse((Path(raw) / "~").exists())

    def test_failed_fixture_cat_remains_a_failed_strict_collection(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            state = Path(raw) / "state"
            env = dict(os.environ, MISSION_CONTROL_HOME=str(state),
                       DASHBOARD_CMD_GIT="cat %s" % (Path(raw) / "missing.json"))
            proc = subprocess.run(["/bin/bash", str(DASHBOARD), "collect", "--strict", "git"],
                                  cwd=ROOT, env=env, text=True, capture_output=True,
                                  timeout=60, check=False)
            self.assertEqual(proc.returncode, 1, proc.stderr)
            self.assertIn("feeder exit", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
