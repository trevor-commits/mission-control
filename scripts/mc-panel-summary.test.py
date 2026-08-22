#!/usr/bin/env python3
"""Executable regression test for native core-feed fail-closed behavior."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts" / "mc-panel.swift"
APP_MAIN = """let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
ProcessInfo.processInfo.disableAutomaticTermination("Mission Control menu bar")
app.run()
"""
PROBE_MAIN = """let summary = AppDelegate().needsSummary()
let age = summary.ageSeconds.map(String.init) ?? "nil"
print("\\(summary.count)|\\(summary.redJobs)|\\(summary.failedFeeds.joined(separator: ","))|\\(age)")
"""


def envelope(name: str, now: int, data: dict[str, object], **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": 1,
        "feed": name,
        "ok": True,
        "error": None,
        "cadence_s": 300,
        "generated_epoch": now - 10,
        "data": data,
    }
    value.update(overrides)
    return value


def valid_feeds(now: int) -> dict[str, dict[str, object]]:
    return {
        "attention": envelope("attention", now, {"board": [], "top5": []}),
        "decisions": envelope("decisions", now, {"pinned": []}),
        "automation": envelope("automation", now, {"jobs": [], "unregistered": []}),
    }


def main() -> int:
    source = SOURCE.read_text(encoding="utf-8")
    if source.count(APP_MAIN) != 1:
        raise AssertionError("mc-panel application entry point changed; update the isolated probe")

    failures = 0
    total = 0
    with tempfile.TemporaryDirectory(prefix="mc-panel-summary-test.") as raw_tmp:
        tmp = Path(raw_tmp)
        probe_source = tmp / "mc-panel-summary-probe.swift"
        probe_source.write_text(source.replace(APP_MAIN, PROBE_MAIN), encoding="utf-8")
        probe_binary = tmp / "mc-panel-summary-probe"
        compile_result = subprocess.run(
            [
                "swiftc", "-O", "-o", str(probe_binary), str(probe_source),
                "-framework", "AppKit", "-framework", "WebKit",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        if compile_result.returncode != 0:
            print("FAIL compile native core-feed probe")
            print(compile_result.stdout, end="")
            print(compile_result.stderr, end="")
            return 1

        fake_home = tmp / "home"
        data_dir = fake_home / ".mission-control" / "data"
        data_dir.mkdir(parents=True)
        environment = os.environ.copy()
        environment["CFFIXED_USER_HOME"] = str(fake_home)
        now = int(time.time())

        def run_case(
            name: str,
            feeds: dict[str, dict[str, object] | str],
            expected_prefix: str,
            expected_age: int | None = None,
        ) -> None:
            nonlocal failures, total
            total += 1
            for path in data_dir.glob("*.json"):
                path.unlink()
            for feed_name, payload in feeds.items():
                path = data_dir / f"{feed_name}.json"
                if isinstance(payload, str):
                    path.write_text(payload, encoding="utf-8")
                else:
                    path.write_text(json.dumps(payload), encoding="utf-8")
            result = subprocess.run(
                [str(probe_binary)], env=environment, text=True, capture_output=True, check=False,
            )
            actual = result.stdout.strip()
            parts = actual.split("|")
            age_ok = expected_age is None or (
                len(parts) == 4 and parts[3].isdigit() and expected_age <= int(parts[3]) <= expected_age + 2
            )
            if result.returncode == 0 and actual.startswith(expected_prefix) and age_ok:
                print(f"PASS {name}")
            else:
                failures += 1
                detail = actual or result.stderr.strip() or f"exit {result.returncode}"
                print(f"FAIL {name}: expected prefix {expected_prefix!r}, got {detail!r}")

        feeds = valid_feeds(now)
        feeds["attention"] = envelope("attention", now, {"board": [], "top5": []}, generated_epoch=now - 10)
        feeds["decisions"] = envelope(
            "decisions", now, {"pinned": [{"id": "decision:1"}, {"id": "decision:2"}]},
            generated_epoch=now - 120,
        )
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [{"state": "red"}], "unregistered": []},
            generated_epoch=now - 20,
        )
        run_case(
            "empty attention cannot hide decisions and age reflects oldest core feed",
            feeds,
            "2|1||",
            expected_age=120,
        )

        feeds = valid_feeds(now)
        feeds["decisions"] = envelope(
            "decisions", now, {"pinned": [
                {"id": "decision:pending", "answer_pending": {"choice": 1}},
                {"id": "decision:actionable", "answer_pending": None},
            ]},
        )
        run_case(
            "pending receipts do not inflate the native action count",
            feeds,
            "1|0||",
        )

        feeds = valid_feeds(now)
        del feeds["decisions"]
        run_case("missing decisions fails closed", feeds, "0|0|decisions|")

        feeds = valid_feeds(now)
        feeds["attention"] = "{not-json"
        run_case("unreadable attention fails closed", feeds, "0|0|attention|")

        feeds = valid_feeds(now)
        feeds["attention"] = envelope(
            "attention", now, {"board": [], "top5": []}, generated_epoch=now - 901,
        )
        run_case("stale attention fails closed", feeds, "0|0|attention|")

        feeds = valid_feeds(now)
        feeds["decisions"] = envelope("wrong", now, {"pinned": []})
        run_case("wrong decisions feed identity fails closed", feeds, "0|0|decisions|")

        feeds = valid_feeds(now)
        feeds["decisions"] = envelope("decisions", now, {"pinned": []}, schema=2)
        run_case("wrong decisions schema fails closed", feeds, "0|0|decisions|")

        feeds = valid_feeds(now)
        feeds["decisions"] = envelope("decisions", now, {"pinned": []}, ok=False)
        run_case("decisions not-ok envelope fails closed", feeds, "0|0|decisions|")

        feeds = valid_feeds(now)
        del feeds["decisions"]["error"]
        run_case("decisions missing error field fails closed", feeds, "0|0|decisions|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": []}, error="launchctl failed",
        )
        run_case("automation error fails closed", feeds, "0|0|automation|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": []}, partial=True,
        )
        run_case("automation partial marker fails closed", feeds, "0|0|automation|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [], "incomplete": True},
        )
        run_case("automation incomplete data fails closed", feeds, "0|0|automation|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": []}, cadence_s=60,
        )
        run_case("automation wrong cadence fails closed", feeds, "0|0|automation|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [{"state": "mystery"}]},
        )
        run_case("automation unknown job state fails closed", feeds, "0|0|automation|")

        # Registry drift is routine on this Mac (57 untracked launchd jobs vs 17
        # tracked) and must NOT blank job health -- failing closed here once hid a
        # live red job behind "Status incomplete". The list is shape-checked only.
        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [], "unregistered": ["com.gillettes.unknown"]},
        )
        run_case("registry drift does not blank job health", feeds, "0|0||")

        # ...and a red job still reports through that same drift.
        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now,
            {"jobs": [{"state": "red"}], "unregistered": ["com.gillettes.unknown"]},
        )
        run_case("red job survives registry drift", feeds, "0|1||")

        # A malformed unregistered value is still a broken feed, not drift.
        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [], "unregistered": "not-a-list"},
        )
        run_case("malformed unregistered fails closed", feeds, "0|0|automation|")

        feeds = valid_feeds(now)
        feeds["automation"] = envelope(
            "automation", now, {"jobs": [], "launchctl_note": "unparseable"},
        )
        run_case("automation parse note fails closed", feeds, "0|0|automation|")

    print(f"{total - failures} passed; {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
