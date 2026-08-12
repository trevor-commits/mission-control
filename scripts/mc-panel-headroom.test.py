#!/usr/bin/env python3
"""Executable regression test for the native menu-bar headroom readout."""

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
PROBE_MAIN = """if let low = AppDelegate().headroomLowest() {
  print("\\(low.pct)|\\(low.band)")
} else {
  print("nil")
}
"""


def row(now: int, **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "id": "codex:week",
        "kind": "quota",
        "remaining_pct": 19.0,
        "band": "orange",
        "health": "ok",
        "confidence": "live",
        "fetched_epoch": now - 30,
    }
    value.update(overrides)
    return value


def feed(now: int, current_row: dict[str, object], **overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "schema": 1,
        "feed": "headroom",
        "ok": True,
        "error": None,
        "cadence_s": 60,
        "generated_epoch": now - 15,
        "data": {
            "rows": [current_row],
            "summary": {
                "lowest_quota": {
                    "id": current_row["id"],
                    "remaining_pct": current_row["remaining_pct"],
                    "band": current_row["band"],
                }
            },
        },
    }
    value.update(overrides)
    return value


def main() -> int:
    source = SOURCE.read_text(encoding="utf-8")
    if source.count(APP_MAIN) != 1:
        raise AssertionError("mc-panel application entry point changed; update the isolated probe")

    failures = 0
    with tempfile.TemporaryDirectory(prefix="mc-panel-headroom-test.") as raw_tmp:
        tmp = Path(raw_tmp)
        probe_source = tmp / "mc-panel-probe.swift"
        probe_source.write_text(source.replace(APP_MAIN, PROBE_MAIN), encoding="utf-8")
        probe_binary = tmp / "mc-panel-probe"
        compile_result = subprocess.run(
            [
                "swiftc",
                "-O",
                "-o",
                str(probe_binary),
                str(probe_source),
                "-framework",
                "AppKit",
                "-framework",
                "WebKit",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        if compile_result.returncode != 0:
            print("FAIL compile native headroom probe")
            print(compile_result.stdout, end="")
            print(compile_result.stderr, end="")
            return 1

        fake_home = tmp / "home"
        data_dir = fake_home / ".mission-control" / "data"
        data_dir.mkdir(parents=True)
        data_file = data_dir / "headroom.json"
        environment = os.environ.copy()
        environment["CFFIXED_USER_HOME"] = str(fake_home)
        now = int(time.time())

        cases: list[tuple[str, dict[str, object], str]] = []
        live_row = row(now)
        cases.append(("current live summary", feed(now, live_row), "19|orange"))
        cases.append((
            "source health must be ok",
            feed(now, row(now, health="down")),
            "nil",
        ))
        cases.append((
            "source confidence must be live",
            feed(now, row(now, confidence="stale")),
            "nil",
        ))
        cases.append((
            "source fetch must be fresh",
            feed(now, row(now, fetched_epoch=now - 301)),
            "nil",
        ))
        cases.append((
            "headroom feed must be fresh",
            feed(now, row(now), generated_epoch=now - 301),
            "nil",
        ))
        cases.append((
            "headroom generated epoch must be an integer",
            feed(now, row(now), generated_epoch=now - 15.5),
            "nil",
        ))
        cases.append((
            "headroom feed error must fail closed",
            feed(now, row(now), error="collector failed"),
            "nil",
        ))
        cases.append((
            "headroom feed partial marker must fail closed",
            feed(now, row(now), partial=True),
            "nil",
        ))
        incomplete_data = feed(now, row(now))
        incomplete_data["data"]["incomplete"] = True  # type: ignore[index]
        cases.append((
            "headroom data incomplete marker must fail closed",
            incomplete_data,
            "nil",
        ))
        cases.append((
            "headroom feed complete false must fail closed",
            feed(now, row(now), complete=False),
            "nil",
        ))
        cases.append((
            "headroom feed cadence must be one minute",
            feed(now, row(now), cadence_s=300),
            "nil",
        ))
        cases.append((
            "source age marker must be fresh when present",
            feed(now, row(now, age_s=301)),
            "nil",
        ))
        mismatched = feed(now, row(now))
        mismatched["data"]["summary"]["lowest_quota"]["remaining_pct"] = 1.0  # type: ignore[index]
        cases.append(("summary must match its live row", mismatched, "nil"))
        duplicate = feed(now, row(now))
        duplicate["data"]["rows"].append(row(now))  # type: ignore[index, union-attr]
        cases.append(("summary id must match exactly one row", duplicate, "nil"))
        lower_sibling = feed(now, row(now))
        lower_sibling["data"]["rows"].append(  # type: ignore[index, union-attr]
            row(now, id="x:month", remaining_pct=4.0, band="red")
        )
        cases.append((
            "summary must reject a lower trusted live quota sibling",
            lower_sibling,
            "nil",
        ))
        stale_lower_sibling = feed(now, row(now))
        stale_lower_sibling["data"]["rows"].append(  # type: ignore[index, union-attr]
            row(now, id="x:stale", remaining_pct=4.0, band="red", fetched_epoch=now - 301)
        )
        cases.append((
            "untrusted stale sibling does not replace the live summary",
            stale_lower_sibling,
            "19|orange",
        ))

        for name, payload, expected in cases:
            data_file.write_text(json.dumps(payload), encoding="utf-8")
            result = subprocess.run(
                [str(probe_binary)],
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            actual = result.stdout.strip()
            if result.returncode == 0 and actual == expected:
                print(f"PASS {name}")
            else:
                failures += 1
                detail = actual or result.stderr.strip() or f"exit {result.returncode}"
                print(f"FAIL {name}: expected {expected!r}, got {detail!r}")

    print(f"{len(cases) - failures} passed; {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
