#!/usr/bin/env python3
"""Compose a Goal-style resume prompt from a Mission Control decision answer (ER-134 Phase C)."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
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

from mission_control_common import IDENTIFIER, sanitize_text


_ROLLUP_METADATA_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/+@-]{0,255}$")


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
    include_generated_at: bool = True,
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
    ]
    if include_generated_at:
        lines.extend((
            "",
            "Generated at: %s" % datetime.now(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"),
        ))
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


def _open_existing_private_dir(parent_fd: int, name: str, label: str) -> int:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(name, flags, dir_fd=parent_fd)
    except OSError as exc:
        raise RuntimeError("decide answer-rollup: unsafe %s directory" % label) from exc
    if not stat.S_ISDIR(os.fstat(fd).st_mode):
        os.close(fd)
        raise RuntimeError("decide answer-rollup: unsafe %s directory" % label)
    return fd


def _validate_rollup_dirs(home: str, home_fd: int, batches_fd: int) -> None:
    checks = (
        (os.fstat(home_fd), os.lstat(home), "state"),
        (os.fstat(batches_fd),
         os.stat("answer-batches", dir_fd=home_fd, follow_symlinks=False),
         "answer-batches"),
    )
    for held, current, label in checks:
        if not stat.S_ISDIR(held.st_mode) or not stat.S_ISDIR(current.st_mode):
            raise RuntimeError("decide answer-rollup: unsafe %s directory" % label)
        if not _same_inode(held, current):
            raise RuntimeError(
                "decide answer-rollup: %s directory changed during transaction" % label)


def _write_exact_file(dir_fd: int, name: str, content: bytes) -> None:
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(content)
        while view:
            view = view[os.write(fd, view):]
        os.fsync(fd)
    finally:
        os.close(fd)


def _read_private_file(dir_fd: int, name: str, label: str) -> bytes:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(name, flags, dir_fd=dir_fd)
    except OSError as exc:
        raise RuntimeError("decide answer-rollup: missing %s" % label) from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600:
            raise RuntimeError("decide answer-rollup: unsafe %s" % label)
        chunks = []
        total = 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            total += len(chunk)
            if total > 2 * 1024 * 1024:
                raise RuntimeError("decide answer-rollup: oversized %s" % label)
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        os.close(fd)


def _validate_named_dir(parent_fd: int, name: str, held_fd: int,
                        label: str) -> None:
    """Prove a name still resolves to the exact pinned private directory."""
    try:
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except OSError as exc:
        raise RuntimeError(
            "decide answer-rollup: %s path changed during transaction" % label
        ) from exc
    held = os.fstat(held_fd)
    if (not stat.S_ISDIR(held.st_mode) or not stat.S_ISDIR(current.st_mode) or
            stat.S_IMODE(held.st_mode) != 0o700 or
            stat.S_IMODE(current.st_mode) != 0o700 or
            not _same_inode(held, current)):
        raise RuntimeError(
            "decide answer-rollup: %s path changed during transaction" % label)


def _cleanup_rollup_stage(batches_fd: int, stage_name: str | None,
                          stage_fd: int, target_ids: list[str]) -> bool:
    """Delete only a pre-commit stage whose name still binds to its pinned fd."""
    if not stage_name or stage_fd < 0:
        return False
    try:
        _validate_named_dir(batches_fd, stage_name, stage_fd, "stage")
    except RuntimeError:
        return False
    for child, suffix in (("answers", ".json"), ("prompts", ".md")):
        try:
            child_fd = _open_existing_private_dir(stage_fd, child, child)
        except RuntimeError:
            continue
        try:
            for decision_id in target_ids:
                try:
                    os.unlink(decision_id + suffix, dir_fd=child_fd)
                except FileNotFoundError:
                    pass
        finally:
            os.close(child_fd)
        try:
            os.rmdir(child, dir_fd=stage_fd)
        except OSError:
            pass
    try:
        os.unlink("manifest.json", dir_fd=stage_fd)
    except FileNotFoundError:
        pass
    try:
        os.rmdir(stage_name, dir_fd=batches_fd)
    except OSError:
        return False
    os.fsync(batches_fd)
    return True


def _quarantine_rollup_dir(batches_fd: int, name: str | None, held_fd: int,
                           label: str) -> str | None:
    """Atomically preserve a suspect committed artifact under a private name."""
    if not name or held_fd < 0:
        return None
    try:
        _validate_named_dir(batches_fd, name, held_fd, label)
    except RuntimeError:
        return None
    for _ in range(32):
        quarantine = ".rollup-quarantine.%s.%s" % (
            label, secrets.token_hex(12))
        try:
            os.stat(quarantine, dir_fd=batches_fd, follow_symlinks=False)
        except FileNotFoundError:
            os.rename(name, quarantine,
                      src_dir_fd=batches_fd, dst_dir_fd=batches_fd)
            os.fsync(batches_fd)
            _validate_named_dir(batches_fd, quarantine, held_fd, "quarantine")
            return quarantine
    raise RuntimeError("decide answer-rollup: could not allocate quarantine name")


def _batch_destination_exists(batches_fd: int, batch_name: str) -> bool:
    try:
        current = os.stat(batch_name, dir_fd=batches_fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    if not stat.S_ISDIR(current.st_mode):
        raise RuntimeError(
            "decide answer-rollup: batch destination must be a private directory")
    return True


def _verify_rollup_batch_fd(batch_fd: int, expected: dict,
                            expected_manifest_sha256: str = "") -> tuple[dict, str]:
    if stat.S_IMODE(os.fstat(batch_fd).st_mode) != 0o700:
        raise RuntimeError("decide answer-rollup: unsafe published batch mode")
    raw = _read_private_file(batch_fd, "manifest.json", "batch manifest")
    manifest_sha256 = hashlib.sha256(raw).hexdigest()
    if (expected_manifest_sha256 and
            manifest_sha256 != expected_manifest_sha256):
        raise RuntimeError("decide answer-rollup: batch manifest digest mismatch")
    try:
        manifest = json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise RuntimeError("decide answer-rollup: invalid batch manifest") from exc
    for key in ("batch_key", "scope_key", "card_id",
                "primary_decision_id", "choice", "member_ids",
                "target_ids", "independent_ids", "already_pending_ids",
                "source", "resume_chat_id", "resume_provider"):
        if manifest.get(key) != expected.get(key):
            raise RuntimeError(
                "decide answer-rollup: published batch conflicts with current answer")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, dict) or set(artifacts) != set(expected["target_ids"]):
        raise RuntimeError("decide answer-rollup: incomplete batch manifest")
    answers_fd = _open_existing_private_dir(batch_fd, "answers", "batch answers")
    prompts_fd = _open_existing_private_dir(batch_fd, "prompts", "batch prompts")
    try:
        for decision_id in expected["target_ids"]:
            item = artifacts.get(decision_id)
            if not isinstance(item, dict):
                raise RuntimeError("decide answer-rollup: invalid member manifest")
            answer = _read_private_file(
                answers_fd, decision_id + ".json", "member answer")
            prompt = _read_private_file(
                prompts_fd, decision_id + ".md", "member prompt")
            if (hashlib.sha256(answer).hexdigest() != item.get("answer_sha256") or
                    hashlib.sha256(prompt).hexdigest() != item.get("prompt_sha256")):
                raise RuntimeError("decide answer-rollup: member artifact hash mismatch")
    finally:
        os.close(prompts_fd)
        os.close(answers_fd)
    return manifest, manifest_sha256


def _quarantine_visible_rollup_conflict(
    home: str, home_fd: int, pinned_batches_fd: int, batch_name: str,
    expected: dict, manifest_sha256: str,
) -> str | None:
    """Quarantine an invalid canonical batch below a replacement parent.

    Receipt-backed cleanup first preserves the exact artifact held below the
    descriptor-pinned parent. If the visible answer-batches name now resolves
    to a different private directory, validate that replacement independently
    and quarantine only an exact invalid canonical directory. A valid copy is
    left alone, and any name/inode race fails without renaming an unbound path.
    """
    current_batches_fd = current_batch_fd = -1
    try:
        current_batches_fd = _open_existing_private_dir(
            home_fd, "answer-batches", "current answer-batches")
        _validate_rollup_dirs(home, home_fd, current_batches_fd)
        if _same_inode(
                os.fstat(current_batches_fd), os.fstat(pinned_batches_fd)):
            return None
        if not _batch_destination_exists(current_batches_fd, batch_name):
            return None
        current_batch_fd = _open_existing_private_dir(
            current_batches_fd, batch_name, "current published batch")
        _validate_named_dir(
            current_batches_fd, batch_name, current_batch_fd,
            "current published batch")
        try:
            _verify_rollup_batch_fd(
                current_batch_fd, expected, manifest_sha256)
        except RuntimeError:
            return _quarantine_rollup_dir(
                current_batches_fd, batch_name, current_batch_fd,
                "visible-conflict")
        return None
    except (OSError, RuntimeError):
        return None
    finally:
        for fd in (current_batch_fd, current_batches_fd):
            if fd >= 0:
                os.close(fd)


def _verify_rollup_batch(batches_fd: int, batch_name: str,
                         expected: dict,
                         expected_manifest_sha256: str = "") -> tuple[dict, str]:
    batch_fd = _open_existing_private_dir(batches_fd, batch_name, "published batch")
    try:
        _validate_named_dir(batches_fd, batch_name, batch_fd, "published batch")
        return _verify_rollup_batch_fd(
            batch_fd, expected, expected_manifest_sha256)
    finally:
        os.close(batch_fd)


def _stage_rollup_batch(
    home: str, batches_fd: int, plan: dict, source: str,
    resume_chat_id: str, resume_provider: str,
) -> tuple[str, int, dict]:
    target_ids = list(plan["target_ids"])
    stage_name = None
    stage_fd = answers_fd = prompts_fd = -1
    try:
        for _ in range(32):
            candidate = ".rollup-stage.%s" % secrets.token_hex(12)
            try:
                os.mkdir(candidate, 0o700, dir_fd=batches_fd)
            except FileExistsError:
                continue
            stage_name = candidate
            break
        if stage_name is None:
            raise RuntimeError("decide answer-rollup: could not allocate stage directory")
        stage_fd = _open_existing_private_dir(batches_fd, stage_name, "stage")
        os.fchmod(stage_fd, 0o700)
        answers_fd = _open_private_dir(stage_fd, "answers")
        prompts_fd = _open_private_dir(stage_fd, "prompts")
        os.fchmod(answers_fd, 0o700)
        os.fchmod(prompts_fd, 0o700)

        artifacts = {}
        for target in plan["targets"]:
            decision_id = target.get("id")
            if (not isinstance(decision_id, str) or
                    not re.fullmatch(r"decision:[0-9a-f]{24}", decision_id)):
                raise RuntimeError("decide answer-rollup: invalid planned member")
            prompt, label = build_prompt(
                decision_id, plan["choice"], target.get("text") or "",
                resume_chat_id, resume_provider, include_generated_at=False)
            prompt_path = os.path.join(
                home, "answer-batches", plan["batch_key"],
                "prompts", decision_id + ".md")
            answer = {
                "schema": 1,
                "batch_key": plan["batch_key"],
                "card_id": plan["card_id"],
                "primary_decision_id": plan["primary_decision_id"],
                "decision_id": decision_id,
                "choice": plan["choice"],
                "label": label,
                "reason": "Trevor chose option %d via Mission Control" % plan["choice"],
                "prompt_path": prompt_path,
            }
            answer_bytes = (json.dumps(answer, sort_keys=True) + "\n").encode("utf-8")
            prompt_bytes = prompt.encode("utf-8")
            _write_exact_file(answers_fd, decision_id + ".json", answer_bytes)
            _write_exact_file(prompts_fd, decision_id + ".md", prompt_bytes)
            artifacts[decision_id] = {
                "answer": "answers/%s.json" % decision_id,
                "answer_sha256": hashlib.sha256(answer_bytes).hexdigest(),
                "prompt": "prompts/%s.md" % decision_id,
                "prompt_sha256": hashlib.sha256(prompt_bytes).hexdigest(),
            }

        manifest = {
            "schema": 1,
            "batch_key": plan["batch_key"],
            "scope_key": plan["scope_key"],
            "card_id": plan["card_id"],
            "primary_decision_id": plan["primary_decision_id"],
            "choice": plan["choice"],
            "member_ids": plan["member_ids"],
            "target_ids": target_ids,
            "independent_ids": plan["independent_ids"],
            "already_pending_ids": plan["already_pending_ids"],
            "source": source,
            "resume_chat_id": resume_chat_id,
            "resume_provider": resume_provider,
            "artifacts": artifacts,
        }
        _write_exact_file(
            stage_fd, "manifest.json",
            (json.dumps(manifest, sort_keys=True) + "\n").encode("utf-8"))
        os.fsync(answers_fd)
        os.fsync(prompts_fd)
        os.fsync(stage_fd)
        result_fd = stage_fd
        stage_fd = -1
        return stage_name, result_fd, manifest
    except BaseException:
        for fd in (prompts_fd, answers_fd, stage_fd):
            if fd >= 0:
                os.close(fd)
        prompts_fd = answers_fd = stage_fd = -1
        cleanup_fd = -1
        try:
            cleanup_fd = _open_existing_private_dir(batches_fd, stage_name, "stage") \
                if stage_name else -1
            _cleanup_rollup_stage(
                batches_fd, stage_name, cleanup_fd, target_ids)
        finally:
            if cleanup_fd >= 0:
                os.close(cleanup_fd)
        raise
    finally:
        for fd in (prompts_fd, answers_fd, stage_fd):
            if fd >= 0:
                os.close(fd)


def _test_pause_after_rollup_stage(home_fd: int) -> None:
    if os.environ.get("DASHBOARD_TESTING") != "1":
        return
    if os.environ.get("DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT") == "1":
        return
    marker = ".rollup-answer-test-ready"
    release = ".rollup-answer-test-continue"
    fd = os.open(marker, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600,
                 dir_fd=home_fd)
    os.close(fd)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            os.stat(release, dir_fd=home_fd, follow_symlinks=False)
            return
        except FileNotFoundError:
            time.sleep(0.01)
    raise RuntimeError("decide answer-rollup: test transaction release timed out")


def _test_pause_after_rollup_commit(home_fd: int) -> None:
    if (os.environ.get("DASHBOARD_TESTING") != "1" or
            os.environ.get("DASHBOARD_TEST_ROLLUP_PAUSE_AFTER_COMMIT") != "1"):
        return
    marker = ".rollup-answer-postcommit-test-ready"
    release = ".rollup-answer-postcommit-test-continue"
    fd = os.open(marker, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600,
                 dir_fd=home_fd)
    os.close(fd)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            os.stat(release, dir_fd=home_fd, follow_symlinks=False)
            return
        except FileNotFoundError:
            time.sleep(0.01)
    raise RuntimeError("decide answer-rollup: postcommit test release timed out")


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
        if decision.get("answer_pending") is not None:
            raise RuntimeError(
                "decide answer: answered-pending decision awaits owner consumption")
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


def answer_rollup_transaction(
    home: str, decision_alert: str, card_id: str, primary_decision_id: str,
    choice: int, resume_chat_id: str = "", resume_provider: str = "",
    source: str = "",
) -> dict:
    """Stage, transactionally record, and atomically publish one rollup answer."""
    if not re.fullmatch(r"card:[0-9a-f]{16}", card_id or ""):
        raise ValueError("decide answer-rollup: invalid card id")
    if not re.fullmatch(r"decision:[0-9a-f]{24}", primary_decision_id or ""):
        raise ValueError("decide answer-rollup: invalid primary decision id")
    if choice < 1:
        raise ValueError("decide answer-rollup: choice must be >= 1")
    metadata = []
    for value, label in (
        (source, "source"),
        (resume_chat_id, "resume chat id"),
        (resume_provider, "resume provider"),
    ):
        if not value:
            metadata.append("")
            continue
        screened = sanitize_text(value, IDENTIFIER)
        clean = screened.value.strip()
        if (screened.dropped or not _ROLLUP_METADATA_RE.fullmatch(clean)):
            raise ValueError(
                "decide answer-rollup: invalid %s" % label)
        metadata.append(clean)
    source, resume_chat_id, resume_provider = metadata
    home = os.path.abspath(os.path.expanduser(home))
    parent = os.path.dirname(home)
    if not os.path.isdir(parent):
        raise RuntimeError("decide answer-rollup: state parent does not exist")

    home_fd = batches_fd = lock_fd = artifact_fd = -1
    stage_name = artifact_name = None
    artifact_is_stage = False
    receipt_exists = False
    commit_recorded = False
    transaction_complete = False
    target_ids: list[str] = []
    batch_name = ""
    expected: dict | None = None
    manifest_sha256 = ""
    try:
        home_fd = _open_private_dir(None, home)
        batches_fd = _open_private_dir(home_fd, "answer-batches")
        os.fchmod(home_fd, 0o700)
        os.fchmod(batches_fd, 0o700)
        _validate_rollup_dirs(home, home_fd, batches_fd)

        lock_hash = hashlib.sha256(
            (card_id + "\0" + primary_decision_id).encode("utf-8")).hexdigest()[:32]
        lock_name = ".rollup-%s.lock" % lock_hash
        flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
        lock_fd = os.open(lock_name, flags, 0o600, dir_fd=batches_fd)
        os.fchmod(lock_fd, 0o600)
        if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
            raise RuntimeError("decide answer-rollup: lock must be a regular file")
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        lock_path = os.stat(lock_name, dir_fd=batches_fd, follow_symlinks=False)
        if not _same_inode(os.fstat(lock_fd), lock_path):
            raise RuntimeError("decide answer-rollup: lock inode changed")

        plan = _run_alert(
            decision_alert, home, "plan-rollup-answer", card_id,
            primary_decision_id, str(choice), "--json")
        target_ids = list(plan.get("target_ids") or [])
        if (not target_ids or primary_decision_id not in target_ids or
                not re.fullmatch(r"scope:[0-9a-f]{40}", plan.get("scope_key") or "") or
                not re.fullmatch(r"rollup-[0-9a-f]{40}", plan.get("batch_key") or "")):
            raise RuntimeError("decide answer-rollup: invalid current plan")
        batch_name = plan["batch_key"]

        primary_target = next(
            (target for target in plan.get("targets") or []
             if target.get("id") == primary_decision_id), None)
        pending = ((primary_target or {}).get("answer_pending") or {})
        if pending.get("valid") is True:
            receipt_exists = True
            effective_source = str(pending.get("source") or "")
            effective_resume_chat = str(pending.get("resume_chat_id") or "")
            effective_resume_provider = str(pending.get("resume_provider") or "")
            pending_manifest_sha256 = str(
                pending.get("artifact_manifest_sha256") or "")
            if not re.fullmatch(r"[0-9a-f]{64}", pending_manifest_sha256):
                raise RuntimeError(
                    "decide answer-rollup: pending receipt lacks an exact manifest digest")
        else:
            effective_source = source
            effective_resume_chat = resume_chat_id
            effective_resume_provider = resume_provider
            pending_manifest_sha256 = ""

        expected = {
            "batch_key": plan["batch_key"],
            "scope_key": plan["scope_key"],
            "card_id": card_id,
            "primary_decision_id": primary_decision_id,
            "choice": choice,
            "member_ids": plan["member_ids"],
            "target_ids": target_ids,
            "independent_ids": plan["independent_ids"],
            "already_pending_ids": plan["already_pending_ids"],
            "source": effective_source,
            "resume_chat_id": effective_resume_chat,
            "resume_provider": effective_resume_provider,
        }
        final_exists = _batch_destination_exists(batches_fd, plan["batch_key"])
        if final_exists:
            if pending.get("valid") is not True:
                raise RuntimeError(
                    "decide answer-rollup: published batch has no pending receipt")
            artifact_fd = _open_existing_private_dir(
                batches_fd, plan["batch_key"], "published batch")
            try:
                _validate_named_dir(
                    batches_fd, plan["batch_key"], artifact_fd, "published batch")
                manifest, manifest_sha256 = _verify_rollup_batch_fd(
                    artifact_fd, expected, pending_manifest_sha256)
            except RuntimeError:
                _quarantine_rollup_dir(
                    batches_fd, plan["batch_key"], artifact_fd,
                    "invalid-published")
                os.close(artifact_fd)
                artifact_fd = -1
                final_exists = False
            else:
                artifact_name = plan["batch_key"]
        if not final_exists:
            stage_name, artifact_fd, manifest = _stage_rollup_batch(
                home, batches_fd, plan, effective_source,
                effective_resume_chat, effective_resume_provider)
            artifact_name = stage_name
            artifact_is_stage = True
            manifest_bytes = (
                json.dumps(manifest, sort_keys=True) + "\n").encode("utf-8")
            manifest_sha256 = hashlib.sha256(manifest_bytes).hexdigest()
            if (pending_manifest_sha256 and
                    manifest_sha256 != pending_manifest_sha256):
                raise RuntimeError(
                    "decide answer-rollup: deterministic replay digest mismatch")
        _test_pause_after_rollup_stage(home_fd)
        _validate_rollup_dirs(home, home_fd, batches_fd)
        _validate_named_dir(
            batches_fd, artifact_name, artifact_fd, "artifact proof")
        _verify_rollup_batch_fd(artifact_fd, expected, manifest_sha256)
        if os.environ.get("DASHBOARD_TEST_ROLLUP_FAIL_BEFORE_COMMIT") == "1":
            raise RuntimeError("decide answer-rollup: forced pre-commit failure")

        record_args = [
            "answer-rollup", card_id, primary_decision_id, str(choice),
            "--expected-scope-key", plan["scope_key"],
            "--artifact-batch-name", artifact_name,
            "--artifact-manifest-sha256", manifest_sha256,
        ]
        if effective_source:
            record_args += ["--source", effective_source]
        if effective_resume_chat:
            record_args += ["--resume-chat-id", effective_resume_chat]
        if effective_resume_provider:
            record_args += ["--resume-provider", effective_resume_provider]
        record_args.append("--json")
        decision_result = _run_alert(decision_alert, home, *record_args)
        commit_recorded = True

        if os.environ.get("DASHBOARD_TEST_ROLLUP_FAIL_AFTER_COMMIT") == "1":
            raise RuntimeError("decide answer-rollup: forced post-commit failure")
        _test_pause_after_rollup_commit(home_fd)
        _validate_rollup_dirs(home, home_fd, batches_fd)
        _validate_named_dir(
            batches_fd, artifact_name, artifact_fd, "artifact proof")
        _verify_rollup_batch_fd(artifact_fd, expected, manifest_sha256)
        if artifact_is_stage:
            if _batch_destination_exists(batches_fd, plan["batch_key"]):
                final_fd = _open_existing_private_dir(
                    batches_fd, plan["batch_key"], "published batch")
                try:
                    _validate_named_dir(
                        batches_fd, plan["batch_key"], final_fd,
                        "published batch")
                    _verify_rollup_batch_fd(
                        final_fd, expected, manifest_sha256)
                except RuntimeError:
                    _quarantine_rollup_dir(
                        batches_fd, plan["batch_key"], final_fd,
                        "invalid-published")
                    os.close(final_fd)
                    final_fd = -1
                if final_fd >= 0:
                    if not _cleanup_rollup_stage(
                            batches_fd, stage_name, artifact_fd, target_ids):
                        os.close(final_fd)
                        raise RuntimeError(
                            "decide answer-rollup: redundant stage path changed")
                    stage_name = None
                    os.close(artifact_fd)
                    artifact_fd = final_fd
                    artifact_name = plan["batch_key"]
                    artifact_is_stage = False
            if artifact_is_stage:
                os.rename(stage_name, plan["batch_key"],
                          src_dir_fd=batches_fd, dst_dir_fd=batches_fd)
                stage_name = None
                artifact_name = plan["batch_key"]
                artifact_is_stage = False
                os.fsync(batches_fd)
        _validate_rollup_dirs(home, home_fd, batches_fd)
        _validate_named_dir(
            batches_fd, plan["batch_key"], artifact_fd, "published batch")
        manifest, verified_manifest_sha256 = _verify_rollup_batch_fd(
            artifact_fd, expected, manifest_sha256)
        if verified_manifest_sha256 != manifest_sha256:
            raise RuntimeError("decide answer-rollup: published digest changed")
        transaction_complete = True
        return {
            "ok": True,
            "card_id": card_id,
            "primary_decision_id": primary_decision_id,
            "choice": choice,
            "scope_key": plan["scope_key"],
            "batch_key": plan["batch_key"],
            "batch_path": os.path.join(home, "answer-batches", plan["batch_key"]),
            "target_ids": target_ids,
            "independent_ids": plan["independent_ids"],
            "already_pending_ids": plan["already_pending_ids"],
            "changed": bool(decision_result.get("changed")),
            "replayed": not bool(decision_result.get("changed")),
            "manifest_sha256": manifest_sha256,
        }
    finally:
        if (not transaction_complete and batches_fd >= 0 and artifact_fd >= 0):
            if commit_recorded or receipt_exists:
                # artifact_name always names the directory currently bound to
                # artifact_fd. Receipt-backed failures quarantine that held
                # object whether this invocation staged it or replayed an
                # already-published batch; lifecycle booleans are not identity.
                _quarantine_rollup_dir(
                    batches_fd, artifact_name, artifact_fd, "postcommit")
                if expected is not None and batch_name and manifest_sha256:
                    _quarantine_visible_rollup_conflict(
                        home, home_fd, batches_fd, batch_name, expected,
                        manifest_sha256)
            elif artifact_is_stage:
                _cleanup_rollup_stage(
                    batches_fd, stage_name, artifact_fd, target_ids)
        for fd in (artifact_fd, lock_fd, batches_fd, home_fd):
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


def answer_rollup_transaction_main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Atomically record one Mission Control rollup answer")
    ap.add_argument("--home", required=True)
    ap.add_argument("--decision-alert", required=True)
    ap.add_argument("--card-id", required=True)
    ap.add_argument("--primary-decision-id", required=True)
    ap.add_argument("--choice", required=True, type=int)
    ap.add_argument("--resume-chat-id", default="")
    ap.add_argument("--resume-provider", default="")
    ap.add_argument("--source", default="")
    args = ap.parse_args(argv)
    try:
        result = answer_rollup_transaction(
            args.home, args.decision_alert, args.card_id,
            args.primary_decision_id, args.choice, args.resume_chat_id,
            args.resume_provider, args.source)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--answer-rollup-transaction":
        return answer_rollup_transaction_main(sys.argv[2:])
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
