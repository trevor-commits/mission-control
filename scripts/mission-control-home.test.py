#!/usr/bin/env python3
"""Mission Control state-home expansion contracts."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"


class StateHomeExpansionTests(unittest.TestCase):
    def test_python_runtimes_expand_tilde_mission_control_home(self) -> None:
        program = r'''
import importlib.machinery, importlib.util, json, os, sys
scripts = sys.argv[1]
sys.path.insert(0, scripts)
def load(name):
    loader = importlib.machinery.SourceFileLoader(name, os.path.join(scripts, name))
    spec = importlib.util.spec_from_loader(name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod
expected = os.path.join(os.environ["HOME"], "state")
sr = load("self-repair")
uw = load("usage-watch")
assert sr.MC_HOME == expected, sr.MC_HOME
assert uw.MC_HOME == expected, uw.MC_HOME
os.makedirs(os.path.join(expected, "self-repair"), exist_ok=True)
with open(os.path.join(expected, "self-repair", "heartbeat.json"), "w") as out:
    json.dump({"last_run_epoch": 123}, out)
automation = load("automation-status")
assert automation._self_check_receipt() == {"last_run_epoch": 123}
'''
        with tempfile.TemporaryDirectory() as raw:
            home = Path(raw) / "home"
            home.mkdir()
            env = dict(os.environ, HOME=str(home), MISSION_CONTROL_HOME="~/state",
                       PYTHONDONTWRITEBYTECODE="1")
            proc = subprocess.run([sys.executable, "-c", program, str(SCRIPTS)],
                                  env=env, text=True, capture_output=True,
                                  timeout=60, check=False)
            self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
