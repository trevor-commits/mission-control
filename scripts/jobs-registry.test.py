#!/usr/bin/env python3
"""jobs.json schema + freshness sanity (T9/T11).

The jobs registry is the single source automation-status reads for liveness.
A malformed registry must fail loudly here, not degrade the panel silently.

Schema contract (content-free):
  name        launchd label, ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$
  label       human display string
  kind        interval | calendar | keepalive
  schedule    non-empty display string
  evidence    list of {path, role}; role in {run, progress}
  expected_freshness_s  positive int; keepalive <= 7d, others <= 30d

identity / identity_source are optional but when present must be a consistent
pair (label-style identity + a known source string).
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "dashboard" / "jobs.json"

LABEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
KINDS = {"interval", "calendar", "keepalive"}
ROLES = {"run", "progress", "scan", "digest"}
IDENTITY_SOURCES = {"launchd template label", "registry name"}

MAX_FRESHNESS = {
    "interval": 30 * 86400,
    "calendar": 30 * 86400,
    "keepalive": 7 * 86400,
}


def main() -> int:
    try:
        registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print("FAIL: registry unreadable: %s" % exc)
        return 1
    if not isinstance(registry, dict) or not isinstance(registry.get("jobs"), list):
        print("FAIL: registry shape: want {jobs: [...]}")
        return 1
    failures = []
    seen_names = set()
    jobs = registry["jobs"]
    if not jobs:
        failures.append("registry has zero jobs")
    for index, job in enumerate(jobs):
        where = "jobs[%d]" % index
        if not isinstance(job, dict):
            failures.append("%s: not an object" % where)
            continue
        name = job.get("name")
        if not isinstance(name, str) or LABEL_RE.match(name) is None:
            failures.append("%s.name: bad launchd label %r" % (where, name))
        elif name in seen_names:
            failures.append("%s.name: duplicate %s" % (where, name))
        else:
            seen_names.add(name)
        if not isinstance(job.get("label"), str) or not job["label"].strip():
            failures.append("%s.label: missing" % where)
        if job.get("kind") not in KINDS:
            failures.append("%s.kind: %r not in %s" % (where, job.get("kind"),
                                                       sorted(KINDS)))
        if not isinstance(job.get("schedule"), str) or not job["schedule"].strip():
            failures.append("%s.schedule: missing" % where)
        evidence = job.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            failures.append("%s.evidence: need a non-empty list" % where)
        else:
            for e_index, ev in enumerate(evidence):
                tag = "%s.evidence[%d]" % (where, e_index)
                if not isinstance(ev, dict):
                    failures.append("%s: not an object" % tag)
                    continue
                if not isinstance(ev.get("path"), str) or not ev["path"]:
                    failures.append("%s.path: missing" % tag)
                if ev.get("role") not in ROLES:
                    failures.append("%s.role: %r" % (tag, ev.get("role")))
        exp = job.get("expected_freshness_s")
        kind = job.get("kind")
        if type(exp) is not int or exp <= 0:
            failures.append("%s.expected_freshness_s: %r" % (where, exp))
        elif kind in MAX_FRESHNESS and exp > MAX_FRESHNESS[kind]:
            failures.append("%s.expected_freshness_s=%ds exceeds %s cap"
                            % (where, exp, kind))
        identity = job.get("identity")
        source = job.get("identity_source")
        if (identity is None) != (source is None):
            failures.append("%s: identity/identity_source must pair" % where)
        elif identity is not None:
            if not isinstance(identity, str) or LABEL_RE.match(identity) is None:
                failures.append("%s.identity: bad label %r" % (where, identity))
            if source not in IDENTITY_SOURCES:
                failures.append("%s.identity_source: %r" % (where, source))
            if isinstance(identity, str) and isinstance(name, str) \
                    and source == "launchd template label" and identity != name:
                # The launchd template renders __MCHOME__ paths but never a
                # different label; a mismatch means the registry lied.
                failures.append("%s: identity != name under template-label source"
                                % where)
    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        return 1
    print("PASS: jobs.json registry (%d jobs)" % len(jobs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
