#!/usr/bin/env python3
"""Compose a Goal-style resume prompt from a Mission Control decision answer (ER-134 Phase C)."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone


def parse_options(text: str) -> list[str]:
    opts = re.findall(r"\*\*`([^`]+)`\*\*", text or "")
    if opts:
        return opts[:6]
    opts = []
    for m in re.finditer(r"\*\*([^*]{2,80})\*\*", text or ""):
        label = m.group(1).strip().strip("`")
        if re.search(r"DECISION NEEDED|Confirmed|recommend", label, re.I):
            continue
        opts.append(label)
        if len(opts) >= 6:
            break
    return opts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--decision-id", required=True)
    ap.add_argument("--choice", required=True, type=int)
    ap.add_argument("--text", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--resume-chat-id", default="")
    ap.add_argument("--resume-provider", default="")
    args = ap.parse_args()
    if args.choice < 1:
        print("choice must be >= 1", file=sys.stderr)
        return 2
    opts = parse_options(args.text)
    if opts and args.choice > len(opts):
        print("choice %d out of range for %d options" % (args.choice, len(opts)), file=sys.stderr)
        return 2
    label = opts[args.choice - 1] if opts else ("option %d" % args.choice)
    question = re.sub(r"\s+", " ", re.sub(r"\*\*|`", " ", args.text or "")).strip()
    if len(question) > 240:
        question = question[:237] + "…"
    lines = [
        "Goal: Resume the waiting work and execute Trevor's decision.",
        "",
        "Runner: Codex or Claude (same provider as the waiting chat)",
        "Model: strongest available high effort for the waiting chat's provider",
        "Reasoning: high",
        "",
        "Decision id: `%s`" % args.decision_id,
        "Trevor choice: %d — %s" % (args.choice, label),
        "Original ask: %s" % (question or "(see decision queue)"),
        "",
        "Required behavior:",
        "1. Treat the numbered choice above as binding operator direction.",
        "2. Continue only the waiting work tied to this decision; do not widen scope.",
        "3. Verify with the same acceptance checks the waiting chat already named.",
        "4. Close with evidence: what changed, what was verified, what remains.",
        "",
        "Stop conditions: irreversible/destructive/outward publish still require an explicit gate.",
        "",
        "Generated at: %s" % datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    ]
    if args.resume_chat_id:
        lines.append("Resume chat: `%s`" % args.resume_chat_id)
    if args.resume_provider:
        lines.append("Resume provider: `%s`" % args.resume_provider)
    out = os.path.expanduser(args.out)
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(json.dumps({"ok": True, "prompt_path": out, "choice": args.choice, "label": label}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
