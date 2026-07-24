#!/usr/bin/env python3
"""Compose a Goal-style resume prompt from a Mission Control decision answer (ER-134 Phase C)."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time
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


def write_private_atomic(path: str, text: str) -> None:
    parent = os.path.dirname(path) or "."
    os.makedirs(parent, mode=0o700, exist_ok=True)
    os.chmod(parent, 0o700)
    if os.path.lexists(path) and (os.path.islink(path) or not os.path.isfile(path)):
        raise ValueError("output destination must be a regular non-symlink file")
    fd, tmp = tempfile.mkstemp(prefix=".decision-prompt.", dir=parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def build_prompt(
    decision_id: str,
    choice: int,
    text: str = "",
    resume_chat_id: str = "",
    resume_provider: str = "",
) -> tuple[str, str]:
    """Return the prompt bytes and chosen label without performing I/O."""
    if choice < 1:
        raise ValueError("choice must be >= 1")
    opts = parse_options(text)
    if opts and choice > len(opts):
        raise ValueError("choice %d out of range for %d options" % (choice, len(opts)))
    label = opts[choice - 1] if opts else ("option %d" % choice)
    question = re.sub(r"\s+", " ", re.sub(r"\*\*|`", " ", text or "")).strip()
    if len(question) > 240:
        question = question[:237] + "…"
    lines = [
        "Goal: Resume the waiting work and execute Trevor's decision.",
        "",
        "Runner: Codex or Claude (same provider as the waiting chat)",
        "Model: strongest available high effort for the waiting chat's provider",
        "Reasoning: high",
        "",
        "Decision id: `%s`" % decision_id,
        "Trevor choice: %d — %s" % (choice, label),
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
    if resume_chat_id:
        lines.append("Resume chat: `%s`" % resume_chat_id)
    if resume_provider:
        lines.append("Resume provider: `%s`" % resume_provider)
    return "\n".join(lines) + "\n", label


def _open_private_dir(parent_fd: int | None, name_or_path: str) -> int:
    """Open an exact, non-linked private directory and return its pinned fd."""
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        return os.open(name_or_path, flags, dir_fd=parent_fd)
    except FileNotFoundError:
        os.mkdir(name_or_path, 0o700, dir_fd=parent_fd)
        return os.open(name_or_path, flags, dir_fd=parent_fd)


def _same_inode(left: os.stat_result, right: os.stat_result) -> bool:
    return (left.st_dev, left.st_ino) == (right.st_dev, right.st_ino)


def _validate_transaction_dirs(home: str, home_fd: int, answers_fd: int, prompts_fd: int) -> None:
    """Prove paths still name the exact directories pinned at transaction start."""
    checks = (
        (os.fstat(home_fd), os.lstat(home), "state"),
        (os.fstat(answers_fd), os.stat("answers", dir_fd=home_fd, follow_symlinks=False), "answers"),
        (os.fstat(prompts_fd), os.stat("prompts", dir_fd=home_fd, follow_symlinks=False), "prompts"),
    )
    for held, current, label in checks:
        if not stat.S_ISDIR(held.st_mode) or not stat.S_ISDIR(current.st_mode):
            raise RuntimeError("decide answer: unsafe %s directory" % label)
        if not _same_inode(held, current):
            raise RuntimeError("decide answer: %s directory changed during transaction" % label)


def _safe_destination(dir_fd: int, name: str, label: str) -> None:
    try:
        current = os.stat(name, dir_fd=dir_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if stat.S_ISLNK(current.st_mode) or not stat.S_ISREG(current.st_mode):
        raise RuntimeError(
            "decide answer: %s destination must be a regular non-symlink file" % label)


def _write_stage(dir_fd: int, prefix: str, content: bytes) -> str:
    for _ in range(32):
        name = "%s%s" % (prefix, secrets.token_hex(12))
        flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
        except FileExistsError:
            continue
        try:
            os.fchmod(fd, 0o600)
            view = memoryview(content)
            while view:
                view = view[os.write(fd, view):]
            os.fsync(fd)
        finally:
            os.close(fd)
        return name
    raise RuntimeError("decide answer: could not allocate private stage file")


def _unlink_stage(dir_fd: int, name: str | None) -> None:
    if not name:
        return
    try:
        os.unlink(name, dir_fd=dir_fd)
    except FileNotFoundError:
        pass


def _test_pause_after_stage(home_fd: int) -> None:
    """Deterministic test-only boundary for directory rename/swap regression."""
    if os.environ.get("DASHBOARD_TESTING") != "1":
        return
    marker = ".decision-answer-test-ready"
    release = ".decision-answer-test-continue"
    fd = os.open(marker, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600, dir_fd=home_fd)
    os.close(fd)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            os.stat(release, dir_fd=home_fd, follow_symlinks=False)
            return
        except FileNotFoundError:
            time.sleep(0.01)
    raise RuntimeError("decide answer: test transaction release timed out")


def _run_alert(decision_alert: str, home: str, *args: str) -> dict:
    env = dict(os.environ)
    env["MISSION_CONTROL_HOME"] = home
    proc = subprocess.run(
        [decision_alert, *args], env=env, text=True, capture_output=True)
    if proc.returncode:
        message = proc.stderr.strip() or proc.stdout.strip() or "decision-alert failed"
        raise RuntimeError(message)
    return json.loads(proc.stdout)


def answer_transaction(
    home: str, decision_alert: str, decision_id: str, choice: int,
    resume_chat_id: str = "", resume_provider: str = "", source: str = "",
) -> tuple[dict, dict, str]:
    """Resolve and publish one answer while pinning every private directory.

    resume_chat_id/resume_provider are carried into the composed Goal prompt
    (build_prompt already renders them) so the resumed worker knows where to
    send a consumption receipt once it finishes the waiting work. source is
    recorded on the decision_events row (never in resolution_evidence_ref,
    which stays the mc-answer:<choice> idempotent-replay key)."""
    if not re.fullmatch(r"decision:[0-9a-f]{24}", decision_id):
        raise ValueError("decide answer: invalid decision id")
    if choice < 1:
        raise ValueError("decide answer: choice must be >= 1")
    home = os.path.abspath(os.path.expanduser(home))
    parent = os.path.dirname(home)
    if not os.path.isdir(parent):
        raise RuntimeError("decide answer: state parent does not exist")
    home_fd = answers_fd = prompts_fd = lock_fd = -1
    prompt_stage = answer_stage = None
    try:
        home_fd = _open_private_dir(None, home)
        answers_fd = _open_private_dir(home_fd, "answers")
        prompts_fd = _open_private_dir(home_fd, "prompts")
        for fd in (home_fd, answers_fd, prompts_fd):
            os.fchmod(fd, 0o700)
        _validate_transaction_dirs(home, home_fd, answers_fd, prompts_fd)

        lock_name = ".%s.lock" % decision_id
        flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
        lock_fd = os.open(lock_name, flags, 0o600, dir_fd=answers_fd)
        os.fchmod(lock_fd, 0o600)
        if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
            raise RuntimeError("decide answer: lock must be a regular file")
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        lock_path = os.stat(lock_name, dir_fd=answers_fd, follow_symlinks=False)
        if not _same_inode(os.fstat(lock_fd), lock_path):
            raise RuntimeError("decide answer: lock inode changed")

        history = _run_alert(decision_alert, home, "history", decision_id, "--json")
        decision = history.get("decision") or {}
        evidence_ref = ((decision.get("resolution") or {}).get("evidence_ref"))
        evidence_type = ((decision.get("resolution") or {}).get("evidence_type"))
        if decision.get("state") == "open":
            recover = False
        elif (decision.get("state") == "resolved" and evidence_type == "manual_resolution"
              and evidence_ref == "mc-answer:%d" % choice):
            recover = True
        else:
            raise RuntimeError("decide answer: decision is no longer open for this choice")

        text = ""
        decisions_path = os.path.join(home, "data", "decisions.json")
        try:
            with open(decisions_path, encoding="utf-8") as handle:
                data = (json.load(handle).get("data") or {})
            for row in (data.get("pinned") or []) + (data.get("inferred") or []):
                if row.get("id") == decision_id:
                    text = row.get("text") or ""
                    break
        except (OSError, ValueError):
            pass

        answer_name = "%s.json" % decision_id
        prompt_name = "%s.md" % decision_id
        _safe_destination(answers_fd, answer_name, "answer")
        _safe_destination(prompts_fd, prompt_name, "prompt")
        prompt, label = build_prompt(
            decision_id, choice, text, resume_chat_id, resume_provider)
        prompt_path = os.path.join(home, "prompts", prompt_name)
        reason = "Trevor chose option %d via Mission Control" % choice
        answer = {
            "decision_id": decision_id,
            "choice": choice,
            "reason": reason,
            "prompt_path": prompt_path,
        }
        prompt_stage = _write_stage(
            prompts_fd, ".decision-prompt-stage.", prompt.encode("utf-8"))
        answer_stage = _write_stage(
            answers_fd, ".decision-answer-stage.",
            (json.dumps(answer, sort_keys=True) + "\n").encode("utf-8"))
        _test_pause_after_stage(home_fd)

        # The decision stays open if either named path stopped referring to the
        # exact directories pinned above. Recheck at the final boundary before
        # the irreversible database transition.
        _validate_transaction_dirs(home, home_fd, answers_fd, prompts_fd)
        _safe_destination(answers_fd, answer_name, "answer")
        _safe_destination(prompts_fd, prompt_name, "prompt")
        if recover:
            decision_result = history
        else:
            resolve_args = [
                "resolve", decision_id,
                "--evidence-type", "manual_resolution",
                "--evidence-ref", "mc-answer:%d" % choice,
            ]
            if source:
                resolve_args += ["--source", source]
            resolve_args.append("--json")
            decision_result = _run_alert(decision_alert, home, *resolve_args)

        # A post-resolution directory swap cannot redirect publication. It is
        # rejected here, and exact-choice replay can finish the derived files.
        _validate_transaction_dirs(home, home_fd, answers_fd, prompts_fd)
        _safe_destination(answers_fd, answer_name, "answer")
        _safe_destination(prompts_fd, prompt_name, "prompt")
        os.replace(answer_stage, answer_name, src_dir_fd=answers_fd, dst_dir_fd=answers_fd)
        answer_stage = None
        os.replace(prompt_stage, prompt_name, src_dir_fd=prompts_fd, dst_dir_fd=prompts_fd)
        prompt_stage = None
        os.fsync(answers_fd)
        os.fsync(prompts_fd)
        compose_result = {
            "ok": True, "prompt_path": prompt_path,
            "choice": choice, "label": label,
        }
        return compose_result, decision_result, prompt_path
    finally:
        if answers_fd >= 0:
            _unlink_stage(answers_fd, answer_stage)
        if prompts_fd >= 0:
            _unlink_stage(prompts_fd, prompt_stage)
        for fd in (lock_fd, prompts_fd, answers_fd, home_fd):
            if fd >= 0:
                os.close(fd)


def answer_transaction_main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Atomically answer one Mission Control decision")
    ap.add_argument("--home", required=True)
    ap.add_argument("--decision-alert", required=True)
    ap.add_argument("--decision-id", required=True)
    ap.add_argument("--choice", required=True, type=int)
    ap.add_argument("--resume-chat-id", default="",
                    help="waiting chat/session id to notify once the resumed "
                         "work consumes this answer (carried into the prompt)")
    ap.add_argument("--resume-provider", default="",
                    help="provider that owns --resume-chat-id (e.g. telegram)")
    ap.add_argument("--source", default="",
                    help="who triggered this answer (e.g. telegram); recorded "
                         "on the decision_events row, not the replay key")
    args = ap.parse_args(argv)
    try:
        compose, decision, prompt_path = answer_transaction(
            args.home, args.decision_alert, args.decision_id, args.choice,
            args.resume_chat_id, args.resume_provider, args.source)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(json.dumps(compose, sort_keys=True))
    print(json.dumps(decision, sort_keys=True))
    print("prompt: %s" % prompt_path)
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--answer-transaction":
        return answer_transaction_main(sys.argv[2:])
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--decision-id", required=True)
    ap.add_argument("--choice", required=True, type=int)
    ap.add_argument("--text", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--resume-chat-id", default="")
    ap.add_argument("--resume-provider", default="")
    args = ap.parse_args()
    try:
        prompt, label = build_prompt(
            args.decision_id, args.choice, args.text,
            args.resume_chat_id, args.resume_provider)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    out = os.path.expanduser(args.out)
    try:
        write_private_atomic(out, prompt)
    except (OSError, ValueError) as exc:
        print("cannot write prompt safely: %s" % exc, file=sys.stderr)
        return 2
    print(json.dumps({"ok": True, "prompt_path": out, "choice": args.choice, "label": label}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
