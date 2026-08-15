#!/usr/bin/python3 -I
"""Durable owner lease and atomic cleanup broker for Git worktrees."""

import argparse
import datetime
import fcntl
import hashlib
import hmac
import json
import os
import pathlib
import pwd
import re
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


CONTRACT = "worktree-owner-lease/v1"
RECOVERY_INVENTORY_CONTRACT = "worktree-owner-recovery-inventory/v1"
RECOVERY_MANIFEST_CONTRACT = "worktree-owner-recovery-manifest/v1"
RECOVERY_APPROVAL_CONTRACT = "worktree-owner-recovery-approval/v1"
RECOVERY_AGENT_APPROVAL_CONTRACT = (
    "worktree-owner-recovery-agent-approval/v1"
)
RECOVERY_RECEIPT_CONTRACT = "worktree-owner-recovery-receipt/v1"
RECOVERY_INVENTORY_RELATIVE = pathlib.Path(
    "records/verification/2026-08-11-lossless-worktree-recovery-inventory.json"
)
GIT = "/usr/bin/git"
FIXED_GIT_CONFIG = (
    "-c", "core.fsmonitor=false",
    "-c", "core.untrackedCache=false",
    "-c", "core.ignoreStat=false",
    "-c", "core.trustctime=true",
    "-c", "core.checkStat=default",
    "-c", "core.fileMode=true",
    "-c", "core.symlinks=true",
    "-c", "diff.ignoreSubmodules=none",
    "-c", "tag.gpgSign=false",
    "-c", "tag.forceSignAnnotated=false",
    "-c", "core.hooksPath=/dev/null",
)
TEST_MODE = os.environ.get("WORKTREE_OWNER_LEASE_TEST_MODE") == "1"
TEST_ROOT = pathlib.Path(os.environ.get("WORKTREE_OWNER_LEASE_TEST_ROOT", "")) if TEST_MODE else None
USER_HOME = pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir)
DEFAULT_LOCK_ROOT = USER_HOME / ".codex" / "thread-writer-locks"
LOCK_ROOT = pathlib.Path(os.environ.get("WORKTREE_OWNER_LOCK_ROOT", str(DEFAULT_LOCK_ROOT))) if TEST_MODE else DEFAULT_LOCK_ROOT
OWNER_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$")
MANUAL_OWNER = re.compile(r"^manual:[A-Za-z0-9][A-Za-z0-9._@+-]{0,120}$")
OWNER_CAPABILITY = re.compile(r"^c[A-Za-z0-9_-]{42}$")
RELEASE_TOKEN = re.compile(r"^r[A-Za-z0-9_-]{42}$")
OWNER_PROVIDERS = ("codex", "claude", "manual", "unknown")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
STATE_BINDING = (
    "worktree_path", "repo_common_dir", "branch", "worktree_git_dir",
    "worktree_git_dir_device", "worktree_git_dir_inode",
)
LEGACY_ACTIVE_KEYS = {
    "acquired_at_unix_ns", "branch", "contract", "generation", "head", "lease_id",
    "owner", "purpose", "replay", "repo_common_dir", "state", "worktree_path",
}
CURRENT_REQUIRED_KEYS = {
    "acquired_at_unix_ns", "acquired_head", "branch", "contract", "generation", "head",
    "lease_id", "owner", "owner_capability_sha256", "purpose", "repo_common_dir", "state",
    "worktree_git_dir", "worktree_git_dir_device", "worktree_git_dir_inode", "worktree_path",
}
CURRENT_OPTIONAL_KEYS = {
    "previous_lease_id", "legacy_schema_upgraded_at_unix_ns", "released_head", "release_token",
    "release_reason", "released_at_unix_ns", "archive_tag", "removal_started_at_unix_ns",
    "removal_failed_at_unix_ns", "removal_reconciled", "reconciled_at_unix_ns",
    "removed_at_unix_ns", "branch_deleted", "release_token_consumed", "detached",
    "prior_owners", "owner_provider", "retired_owner_capabilities",
    "recovery_manifest_sha256", "recovery_candidate_id",
    "recovery_approval_sha256", "recovered_at_unix_ns",
    "legacy_recovery_id",
    "recovery_source_state_sha256",
    "recovery_released_state_sha256",
    # Tolerated, never required and never read here. The unmerged prototype
    # branch fix/lease-registration-discriminator writes these two at acquire
    # time and through its stamp-registration-markers migration. Because the
    # primary checkout is often sitting on that branch, worktree-new.sh run
    # from there mints leases carrying them -- three live lease states already
    # did on 2026-08-13, across two different sessions. Without this entry
    # validate_state_shape rejects the whole state as unsafe-lease-state, so a
    # lease minted by one checkout became unreadable by the landed broker and
    # its worktree could not be released or removed by anyone. Listing the keys
    # as optional makes the landed broker ignore them instead of failing, which
    # is the compatible direction: it grants them no meaning and no authority.
    "registration_marker_sha256",
    "registration_marker_stamped_at_unix_ns",
}
PUBLIC_SECRET_KEYS = {
    "owner_capability_sha256", "release_token", "retired_owner_capabilities",
}
DISCOVERY_ENTRY_LIMIT = 1024
MAX_GIT_OUTPUT_BYTES = 20 * 1024 * 1024
GIT_TIMEOUT_SECONDS = 30.0


class LeaseError(Exception):
    def __init__(self, reason, detail=None):
        super().__init__(reason)
        self.reason = reason
        self.detail = detail


def emit(value):
    sys.stdout.write(json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n")


def fail(reason, detail=None):
    raise LeaseError(reason, detail)


def _path_within(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_test_boundary(args):
    if not TEST_MODE:
        return
    if TEST_ROOT is None or not TEST_ROOT.is_absolute():
        fail("unsafe-test-mode")
    try:
        root = TEST_ROOT.resolve(strict=True)
        root_st = root.lstat()
        private_tmp = pathlib.Path("/private/tmp").resolve(strict=True)
    except OSError:
        fail("unsafe-test-mode")
    if (root != TEST_ROOT or root == private_tmp or not _path_within(root, private_tmp)
            or not stat.S_ISDIR(root_st.st_mode) or stat.S_ISLNK(root_st.st_mode)
            or root_st.st_uid != os.getuid() or stat.S_IMODE(root_st.st_mode) != 0o700):
        fail("unsafe-test-mode")

    candidates = []
    if hasattr(args, "worktree"):
        candidates.append(pathlib.Path(args.worktree))
    if hasattr(args, "state_file"):
        candidates.append(pathlib.Path(args.state_file))
    if hasattr(args, "repo"):
        candidates.append(pathlib.Path(args.repo))
    if hasattr(args, "manifest"):
        candidates.append(pathlib.Path(args.manifest))
    if hasattr(args, "approval"):
        candidates.append(pathlib.Path(args.approval))
    candidates.append(LOCK_ROOT)
    for marker_name in (
        "WORKTREE_OWNER_LEASE_TEST_HOLD_MARKER",
        "WORKTREE_OWNER_LEASE_TEST_BRANCH_DELETE_MARKER",
    ):
        marker = os.environ.get(marker_name)
        if marker:
            candidates.append(pathlib.Path(marker).parent)
    for candidate in candidates:
        if not candidate.is_absolute():
            fail("unsafe-test-mode")
        try:
            resolved = candidate.resolve(strict=True)
        except OSError:
            fail("unsafe-test-mode")
        if not _path_within(resolved, root):
            fail("unsafe-test-mode")


def bounded_text(value, reason, maximum):
    if not isinstance(value, str) or not value or len(value) > maximum or "\0" in value:
        fail(reason)
    try:
        value.encode("utf-8")
    except UnicodeError:
        fail(reason)
    return value


def valid_owner(value):
    if not isinstance(value, str) or OWNER_ID.fullmatch(value) is None:
        fail("invalid-owner")
    return value


def valid_owner_provider(value, reason="invalid-owner-provider"):
    if value not in OWNER_PROVIDERS:
        fail(reason)
    return value


def valid_provider_owner(owner, provider):
    valid_owner(owner)
    if provider in ("codex", "claude"):
        valid_uuid(owner, "invalid-provider-owner")
    elif provider == "manual" and MANUAL_OWNER.fullmatch(owner) is None:
        fail("invalid-provider-owner")
    return owner


def valid_uuid(value, reason):
    if not isinstance(value, str):
        fail(reason)
    try:
        parsed = uuid.UUID(value)
    except (ValueError, TypeError, AttributeError):
        fail(reason)
    if str(parsed) != value:
        fail(reason)
    return str(parsed)


def owner_capability_hash(value):
    if not isinstance(value, str) or OWNER_CAPABILITY.fullmatch(value) is None:
        fail("invalid-owner-capability")
    return hashlib.sha256(value.encode("ascii")).hexdigest()


def valid_release_token(value):
    if not isinstance(value, str) or RELEASE_TOKEN.fullmatch(value) is None:
        fail("invalid-release-token")
    return value


def new_capability(prefix):
    value = prefix + secrets.token_urlsafe(31)
    pattern = OWNER_CAPABILITY if prefix == "c" else RELEASE_TOKEN if prefix == "r" else None
    if pattern is None or pattern.fullmatch(value) is None:
        fail("capability-generation-failed")
    return value


def authenticate(state, value):
    expected = state.get("owner_capability_sha256")
    actual = owner_capability_hash(value)
    if not isinstance(expected, str) or not hmac.compare_digest(expected, actual):
        fail("owner-capability-mismatch")


def fixed_git_environment():
    """Remove caller Git routing/config overrides from broker-owned commands."""
    environment = {
        key: value for key, value in os.environ.items() if not key.startswith("GIT_")
    }
    environment["HOME"] = str(USER_HOME)
    environment.pop("XDG_CONFIG_HOME", None)
    environment.update({
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_NO_LAZY_FETCH": "1",
        "GIT_TERMINAL_PROMPT": "0",
    })
    return environment


def _process_table():
    try:
        result = subprocess.run(
            ["/bin/ps", "-axo", "pid=,ppid=,pgid="],
            capture_output=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    rows = []
    for line in result.stdout.decode("ascii", "replace").splitlines():
        parts = line.split()
        if len(parts) != 3:
            continue
        try:
            rows.append((int(parts[0]), int(parts[1]), int(parts[2])))
        except ValueError:
            continue
    return rows


def _related_pids(root_pid, known=None):
    known = set(known or ())
    known.add(root_pid)
    rows = _process_table()
    pgids = {pgid for pid, _ppid, pgid in rows if pid == root_pid or pid in known}
    changed = True
    while changed:
        changed = False
        for pid, ppid, pgid in rows:
            if pid in known:
                if pgid not in pgids:
                    pgids.add(pgid)
                    changed = True
                continue
            if ppid in known or pgid in pgids:
                known.add(pid)
                pgids.add(pgid)
                changed = True
    return known


def _terminate_process_tree(process, known_pids=None, wait_timeout=1):
    known = set(known_pids or ())
    known.add(process.pid)
    try:
        known.update(_related_pids(process.pid, known))
    except OSError:
        pass
    protected = {0, 1, os.getpid(), os.getppid()}
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        try:
            os.kill(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    for pid in known:
        if pid in protected:
            continue
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError, OSError):
            pass
    if process.poll() is None:
        try:
            process.wait(timeout=wait_timeout)
        except subprocess.TimeoutExpired:
            pass


def _run_git_command(args, *, text):
    command = [GIT, *FIXED_GIT_CONFIG, *args]
    try:
        process = subprocess.Popen(
            command,
            env=fixed_git_environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
    except OSError:
        fail("git-binding-unavailable")
    selector = selectors.DefaultSelector()
    outputs = {"stdout": bytearray(), "stderr": bytearray()}
    known = {process.pid}
    deadline = time.monotonic() + GIT_TIMEOUT_SECONDS
    try:
        for name, stream in (("stdout", process.stdout), ("stderr", process.stderr)):
            if stream is None:
                fail("git-binding-unavailable")
            selector.register(stream, selectors.EVENT_READ, name)
        while selector.get_map():
            known.update(_related_pids(process.pid, known))
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                fail("git-timeout")
            for key, _mask in selector.select(min(0.1, remaining)):
                try:
                    chunk = os.read(key.fileobj.fileno(), 64 * 1024)
                except OSError:
                    fail("git-binding-unavailable")
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if sum(len(value) for value in outputs.values()) + len(chunk) > MAX_GIT_OUTPUT_BYTES:
                    fail("git-output-too-large")
                outputs[key.data].extend(chunk)
        remaining = max(0.0, deadline - time.monotonic())
        try:
            returncode = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            fail("git-timeout")
    except Exception:
        _terminate_process_tree(process, known)
        raise
    finally:
        selector.close()
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()
    stdout = bytes(outputs["stdout"])
    stderr = bytes(outputs["stderr"])
    if text:
        try:
            stdout = stdout.decode("utf-8")
            stderr = stderr.decode("utf-8")
        except UnicodeDecodeError:
            fail("git-binding-unavailable")
    return subprocess.CompletedProcess(command, returncode, stdout, stderr)


def run_git(args, reason="git-binding-unavailable", allowed=(0,)):
    result = _run_git_command(args, text=True)
    if result.returncode not in allowed:
        fail(reason, (result.stderr or result.stdout).strip())
    return result


def run_git_bytes(args, reason="git-binding-unavailable", allowed=(0,)):
    result = _run_git_command(args, text=False)
    if result.returncode not in allowed:
        detail = (result.stderr or result.stdout).decode("utf-8", "replace").strip()
        fail(reason, detail)
    return result


def git(path, *args):
    return run_git(["-C", str(path), *args]).stdout.strip()


def canonical_existing(path_value, reason):
    path = pathlib.Path(path_value)
    if not path.is_absolute():
        fail(reason, str(path))
    try:
        resolved = path.resolve(strict=True)
    except OSError:
        fail(reason, str(path))
    if resolved != path or resolved.is_symlink():
        fail(reason, str(path))
    return resolved


def git_info(worktree):
    path = canonical_existing(worktree, "unsafe-worktree")
    if not path.is_dir():
        fail("unsafe-worktree", str(path))
    top = canonical_existing(
        pathlib.Path(git(path, "rev-parse", "--show-toplevel")), "unsafe-worktree",
    )
    if top != path:
        fail("unsafe-worktree", str(path))
    common_raw = pathlib.Path(git(path, "rev-parse", "--git-common-dir"))
    common = canonical_existing(common_raw if common_raw.is_absolute() else path / common_raw, "unsafe-git-common-dir")
    admin_raw = pathlib.Path(git(path, "rev-parse", "--git-dir"))
    admin = canonical_existing(admin_raw if admin_raw.is_absolute() else path / admin_raw, "unsafe-worktree-git-dir")
    try:
        admin_st = admin.lstat()
    except OSError:
        fail("unsafe-worktree-git-dir")
    if not stat.S_ISDIR(admin_st.st_mode) or stat.S_ISLNK(admin_st.st_mode) or admin_st.st_uid != os.getuid():
        fail("unsafe-worktree-git-dir")
    branch = git(path, "branch", "--show-current") or None
    head = git(path, "rev-parse", "HEAD")
    result = {
        "worktree_path": str(path),
        "repo_common_dir": str(common),
        "branch": branch,
        "head": head,
        "worktree_git_dir": str(admin),
        "worktree_git_dir_device": admin_st.st_dev,
        "worktree_git_dir_inode": admin_st.st_ino,
    }
    if branch is None:
        result["detached"] = True
    return result


def repo_common_from_anchor(anchor):
    path = canonical_existing(anchor, "unsafe-repo-anchor")
    if not path.is_dir():
        fail("unsafe-repo-anchor")
    common_raw = pathlib.Path(git(path, "rev-parse", "--git-common-dir"))
    common = canonical_existing(
        common_raw if common_raw.is_absolute() else path / common_raw,
        "unsafe-git-common-dir",
    )
    if not common.is_dir():
        fail("unsafe-git-common-dir")
    return common


def private_dir(path, reason, create=False, exact_mode=True):
    if create and not (path.exists() or path.is_symlink()):
        try:
            path.mkdir(parents=True, mode=0o700)
            os.chmod(path, 0o700)
        except OSError:
            fail(reason)
    try:
        st = path.lstat()
        resolved = path.resolve(strict=True)
    except OSError:
        fail(reason)
    if (resolved != path or not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode)
            or st.st_uid != os.getuid() or (exact_mode and stat.S_IMODE(st.st_mode) != 0o700)
            or (not exact_mode and stat.S_IMODE(st.st_mode) & 0o022)):
        fail(reason)
    return path


def state_location(info, create=True):
    owner_dir = pathlib.Path(info["repo_common_dir"]) / "codex-worktree-owners"
    if create:
        owner_dir = private_dir(
            owner_dir, "unsafe-owner-directory", create=True,
        )
    elif owner_dir.exists() or owner_dir.is_symlink():
        owner_dir = private_dir(owner_dir, "unsafe-owner-directory")
    key = hashlib.sha256((info["repo_common_dir"] + "\0" + info["worktree_path"]).encode()).hexdigest()
    return owner_dir, owner_dir / (key + ".json")


def safe_read(path):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(str(path), flags)
    except OSError:
        if path.is_symlink():
            fail("unsafe-lease-state", str(path))
        fail("owner-lease-missing", str(path))
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1
                or stat.S_IMODE(before.st_mode) != 0o600 or before.st_size > 1_048_576):
            fail("unsafe-lease-state", str(path))
        data = b""
        while len(data) < before.st_size:
            chunk = os.read(fd, before.st_size - len(data))
            if not chunk:
                fail("unsafe-lease-state", "short-read")
            data += chunk
        after = os.fstat(fd)
        path_after = path.lstat()
        if ((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
                != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
                or (path_after.st_dev, path_after.st_ino) != (before.st_dev, before.st_ino)):
            fail("unsafe-lease-state", "changed-during-read")
        value = json.loads(
            data,
            object_pairs_hook=lambda pairs: _strict_object(pairs),
            parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
        )
    except (OSError, json.JSONDecodeError, UnicodeDecodeError, RecursionError, ValueError):
        fail("unsafe-lease-state", str(path))
    finally:
        os.close(fd)
    if not isinstance(value, dict) or value.get("contract") != CONTRACT:
        fail("unsafe-lease-state", str(path))
    validate_state_shape(value)
    return value


def _strict_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate-key")
        value[key] = item
    return value


def canonical_json_bytes(value):
    try:
        return json.dumps(
            value, sort_keys=True, separators=(",", ":"), allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        fail("invalid-canonical-json")


def safe_regular_bytes(path, reason, exact_mode=None, maximum=20 * 1024 * 1024):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(str(path), flags)
    except OSError:
        fail(reason, str(path))
    try:
        before = os.fstat(fd)
        mode = stat.S_IMODE(before.st_mode)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.getuid()
            or before.st_nlink != 1
            or before.st_size > maximum
            or (exact_mode is not None and mode != exact_mode)
            or (exact_mode is None and mode & 0o022)
        ):
            fail(reason, str(path))
        data = bytearray()
        while len(data) < before.st_size:
            chunk = os.read(fd, min(1024 * 1024, before.st_size - len(data)))
            if not chunk:
                fail(reason, "short-read")
            data.extend(chunk)
        after = os.fstat(fd)
        path_after = path.lstat()
        if (
            (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            or (path_after.st_dev, path_after.st_ino)
            != (before.st_dev, before.st_ino)
        ):
            fail(reason, "changed-during-read")
        return bytes(data)
    except OSError:
        fail(reason, str(path))
    finally:
        os.close(fd)


def strict_json_bytes(data, reason, canonical=False):
    try:
        value = json.loads(
            data,
            object_pairs_hook=lambda pairs: _strict_object(pairs),
            parse_constant=lambda item: (
                _ for _ in ()
            ).throw(ValueError(item)),
        )
    except (
        json.JSONDecodeError, UnicodeDecodeError, RecursionError, ValueError,
    ):
        fail(reason)
    if canonical and data != canonical_json_bytes(value) + b"\n":
        fail(reason + "-not-canonical")
    return value


def safe_json_file(path, reason, exact_mode=None, canonical=False):
    return strict_json_bytes(
        safe_regular_bytes(path, reason, exact_mode=exact_mode),
        reason,
        canonical=canonical,
    )


def safe_file_sha256(path, reason):
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(str(path), flags)
    except OSError:
        fail(reason, str(path))
    try:
        before = os.fstat(fd)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_uid != os.getuid()
            or before.st_nlink != 1
            or stat.S_IMODE(before.st_mode) & 0o022
        ):
            fail(reason, str(path))
        digest = hashlib.sha256()
        remaining = before.st_size
        while remaining:
            chunk = os.read(fd, min(1024 * 1024, remaining))
            if not chunk:
                fail(reason, "short-read")
            digest.update(chunk)
            remaining -= len(chunk)
        after = os.fstat(fd)
        path_after = path.lstat()
        if (
            (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
            or (path_after.st_dev, path_after.st_ino)
            != (before.st_dev, before.st_ino)
        ):
            fail(reason, "changed-during-read")
        return digest.hexdigest()
    except OSError:
        fail(reason, str(path))
    finally:
        os.close(fd)


def positive_int(value, reason):
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        fail(reason)
    return value


def validate_state_shape(value):
    if set(value) == LEGACY_ACTIVE_KEYS:
        fail("legacy-owner-lease-unsupported")
    if not CURRENT_REQUIRED_KEYS.issubset(value) or not set(value).issubset(CURRENT_REQUIRED_KEYS | CURRENT_OPTIONAL_KEYS):
        fail("unsafe-lease-state")
    valid_uuid(value.get("lease_id"), "unsafe-lease-state")
    valid_uuid(value.get("generation"), "unsafe-lease-state")
    if "previous_lease_id" in value:
        valid_uuid(value["previous_lease_id"], "unsafe-lease-state")
    valid_owner(value.get("owner"))
    if "owner_provider" in value:
        provider = valid_owner_provider(value["owner_provider"], "unsafe-lease-state")
        try:
            valid_provider_owner(value["owner"], provider)
        except LeaseError:
            fail("unsafe-lease-state")
    if "prior_owners" in value:
        prior = value["prior_owners"]
        if not isinstance(prior, list) or not prior or len(prior) > 32:
            fail("unsafe-lease-state")
        for prior_owner in prior:
            valid_owner(prior_owner)
        if len(set(prior)) != len(prior) or value["owner"] in prior:
            fail("unsafe-lease-state")
    if "retired_owner_capabilities" in value:
        retired = value["retired_owner_capabilities"]
        if not isinstance(retired, list) or not retired or len(retired) > 32:
            fail("unsafe-lease-state")
        retired_hashes = []
        for item in retired:
            if (not isinstance(item, dict) or set(item) != {"owner", "sha256"}
                    or not isinstance(item["sha256"], str)
                    or HEX64.fullmatch(item["sha256"]) is None):
                fail("unsafe-lease-state")
            valid_owner(item["owner"])
            retired_hashes.append(item["sha256"])
        if (len(set(retired_hashes)) != len(retired_hashes)
                or value.get("owner_capability_sha256") in retired_hashes
                or any(item["owner"] not in {value["owner"], *value.get("prior_owners", [])}
                       for item in retired)):
            fail("unsafe-lease-state")
    bounded_text(value.get("purpose"), "unsafe-lease-state", 512)
    detached = value.get("detached", False)
    if not isinstance(detached, bool):
        fail("unsafe-lease-state")
    if detached:
        if value.get("branch") is not None:
            fail("unsafe-lease-state")
    else:
        bounded_text(value.get("branch"), "unsafe-lease-state", 512)
    for key in ("worktree_path", "repo_common_dir", "worktree_git_dir"):
        text = bounded_text(value.get(key), "unsafe-lease-state", 4096)
        if not pathlib.Path(text).is_absolute():
            fail("unsafe-lease-state")
    for key in ("head", "acquired_head"):
        item = value.get(key)
        if not isinstance(item, str) or not (HEX40.fullmatch(item) or HEX64.fullmatch(item)):
            fail("unsafe-lease-state")
    if not isinstance(value.get("owner_capability_sha256"), str) or HEX64.fullmatch(value["owner_capability_sha256"]) is None:
        fail("unsafe-lease-state")
    for key in ("worktree_git_dir_device", "worktree_git_dir_inode", "acquired_at_unix_ns"):
        positive_int(value.get(key), "unsafe-lease-state")
    state_name = value.get("state")
    if state_name not in ("active", "released", "removing", "removed"):
        fail("unsafe-lease-state")
    if state_name in ("released", "removing", "removed"):
        released_head = value.get("released_head")
        if not isinstance(released_head, str) or not (HEX40.fullmatch(released_head) or HEX64.fullmatch(released_head)):
            fail("unsafe-lease-state")
        valid_release_token(value.get("release_token"))
        bounded_text(value.get("release_reason"), "unsafe-lease-state", 512)
        positive_int(value.get("released_at_unix_ns"), "unsafe-lease-state")
    if state_name in ("removing", "removed"):
        bounded_text(value.get("archive_tag"), "unsafe-lease-state", 1024)
        positive_int(value.get("removal_started_at_unix_ns"), "unsafe-lease-state")
    if state_name == "removed":
        positive_int(value.get("removed_at_unix_ns"), "unsafe-lease-state")
        if not isinstance(value.get("branch_deleted"), bool) or value.get("release_token_consumed") is not True:
            fail("unsafe-lease-state")
    for key in (
        "legacy_schema_upgraded_at_unix_ns", "removal_failed_at_unix_ns",
        "reconciled_at_unix_ns", "recovered_at_unix_ns",
    ):
        if key in value:
            positive_int(value[key], "unsafe-lease-state")
    for key in ("recovery_manifest_sha256", "recovery_approval_sha256"):
        if key in value and (
            not isinstance(value[key], str) or HEX64.fullmatch(value[key]) is None
        ):
            fail("unsafe-lease-state")
    if "recovery_source_state_sha256" in value:
        source_state = value["recovery_source_state_sha256"]
        if source_state is not None and (
            not isinstance(source_state, str)
            or HEX64.fullmatch(source_state) is None
        ):
            fail("unsafe-lease-state")
    if "recovery_released_state_sha256" in value and (
        not isinstance(value["recovery_released_state_sha256"], str)
        or HEX64.fullmatch(value["recovery_released_state_sha256"]) is None
    ):
        fail("unsafe-lease-state")
    if "recovery_candidate_id" in value:
        bounded_text(value["recovery_candidate_id"], "unsafe-lease-state", 256)
    if "legacy_recovery_id" in value:
        legacy_id = bounded_text(
            value["legacy_recovery_id"], "unsafe-lease-state", 512,
        )
        if not legacy_id.startswith("legacy-no-lease:"):
            fail("unsafe-lease-state")
    if "removal_reconciled" in value and value["removal_reconciled"] not in ("worktree-present", "worktree-absent"):
        fail("unsafe-lease-state")
    return value


def atomic_write(path, value):
    parent = private_dir(path.parent, "unsafe-owner-directory")
    fd, temp_name = tempfile.mkstemp(prefix=".owner-lease.", dir=str(parent))
    try:
        os.fchmod(fd, 0o600)
        data = (json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode()
        view = memoryview(data)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                fail("lease-write-failed")
            view = view[written:]
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(temp_name, path)
        temp_name = ""
        directory_fd = os.open(str(parent), os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except (OSError, ValueError):
        fail("lease-write-failed")
    finally:
        if fd >= 0:
            os.close(fd)
        if temp_name:
            try:
                os.unlink(temp_name)
            except OSError:
                pass


def lease_lock(owner_dir):
    path = owner_dir / ".lock"
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(str(path), flags, 0o600)
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1:
            fail("unsafe-owner-lock")
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        after = path.lstat()
        if (after.st_dev, after.st_ino) != (st.st_dev, st.st_ino):
            fail("unsafe-owner-lock")
        return fd
    except OSError:
        fail("unsafe-owner-lock")


def writer_lock(owner):
    valid_owner(owner)
    root = private_dir(LOCK_ROOT, "unsafe-writer-lock-directory", create=True, exact_mode=False)
    path = root / (owner + ".lock")
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(str(path), flags, 0o600)
        st = os.fstat(fd)
        if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1
                or stat.S_IMODE(st.st_mode) & 0o022):
            fail("unsafe-writer-lock")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        after = path.lstat()
        if (after.st_dev, after.st_ino) != (st.st_dev, st.st_ino):
            fail("unsafe-writer-lock")
        return fd
    except BlockingIOError:
        fail("active-writer-lock")
    except OSError:
        fail("unsafe-writer-lock")


def writer_locks_for(owners):
    fds = []
    try:
        for owner in sorted(set(owners)):
            fds.append(writer_lock(owner))
        return fds
    except LeaseError:
        for fd in reversed(fds):
            os.close(fd)
        raise


def all_writer_locks(state):
    return writer_locks_for({state["owner"], *state.get("prior_owners", [])})


def device_binding_matches(state, current):
    recorded = state.get("worktree_git_dir_device")
    live = current.get("worktree_git_dir_device")
    if recorded == live:
        return True
    # macOS assigns st_dev when a volume mounts, so every reboot renumbers it and
    # a lease that outlives one reboot would otherwise fail closed forever, with
    # no route left to clean up its own worktree.
    #
    # The device number cannot simply be excused. A linked worktree's admin
    # directory always shares a device with the repository common directory, so
    # comparing those is tautological, and inode numbers are reused after a
    # delete and recreate. Excusing the device on inode alone would let a stale
    # release token remove a *recreated* registration at the same path, branch,
    # and HEAD.
    #
    # Admin-directory birth time is the discriminator that survives a reboot and
    # still changes on recreation: `git worktree add` always makes a fresh admin
    # directory. A registration born after its own lease was acquired is a
    # different registration, whatever inode it landed on, so accept a renumbered
    # device only when birth time does not postdate acquisition.
    admin = state.get("worktree_git_dir")
    acquired = state.get("acquired_at_unix_ns")
    if live is None or not admin or admin != current.get("worktree_git_dir"):
        return False
    if not isinstance(acquired, int) or isinstance(acquired, bool):
        return False
    try:
        info = os.stat(admin)
    except OSError:
        return False
    birth_ns = getattr(info, "st_birthtime_ns", None)
    if birth_ns is None:
        birth = getattr(info, "st_birthtime", None)
        if birth is None:
            # No birth time means no reboot-stable recreation evidence; the
            # original exact device comparison is the only safe answer.
            return False
        birth_ns = int(birth * 1_000_000_000)
    return birth_ns <= acquired


def stable_binding_matches(state, current):
    return all(
        state.get(key) == current.get(key)
        for key in STATE_BINDING
        if key != "worktree_git_dir_device"
    ) and device_binding_matches(state, current)


def released_binding_matches(state, current):
    return stable_binding_matches(state, current) and state.get("released_head") == current.get("head")


def public_state(state, path, replay=False, extra=None):
    result = {key: value for key, value in state.items() if key not in PUBLIC_SECRET_KEYS}
    provider = state.get("owner_provider", "unknown")
    result["owner_provider"] = provider
    result["provider_integration"] = "codex-expected" if provider == "codex" else "unverified"
    result["state_file"] = str(path)
    result["replay"] = replay
    if extra:
        result.update(extra)
    return result


def mint_capability(_args):
    return {"contract": CONTRACT, "owner_capability": new_capability("c")}


def acquire(args):
    owner_provider = valid_owner_provider(args.owner_provider)
    valid_provider_owner(args.owner, owner_provider)
    bounded_text(args.purpose, "invalid-purpose", 512)
    owner_capability = args.owner_capability
    owner_capability_hash(owner_capability)
    info = git_info(pathlib.Path(args.worktree))
    owner_dir, path = state_location(info)
    fd = lease_lock(owner_dir)
    try:
        if path.exists() or path.is_symlink():
            state = safe_read(path)
            if state.get("state") == "active" and state.get("owner") == args.owner and stable_binding_matches(state, info):
                if state.get("purpose") != args.purpose:
                    fail("purpose-conflict")
                authenticate(state, args.owner_capability)
                current_provider = state.get("owner_provider", "unknown")
                if current_provider != owner_provider:
                    if "owner_provider" not in state and owner_provider != "unknown":
                        state["owner_provider"] = owner_provider
                        atomic_write(path, state)
                    else:
                        fail("owner-provider-conflict")
                return public_state(
                    state, path, replay=True,
                    extra={"owner_capability": args.owner_capability},
                )
            if not (state.get("state") == "removed"
                    and state.get("worktree_path") == info["worktree_path"]
                    and state.get("repo_common_dir") == info["repo_common_dir"]):
                fail("owner-lease-conflict", state.get("state"))
            previous_lease_id = state.get("lease_id")
        else:
            previous_lease_id = None
        state = {
            "contract": CONTRACT,
            "lease_id": str(uuid.uuid4()),
            "generation": str(uuid.uuid4()),
            "owner": args.owner,
            "purpose": args.purpose,
            **info,
            "state": "active",
            "acquired_head": info["head"],
            "owner_capability_sha256": owner_capability_hash(owner_capability),
            "acquired_at_unix_ns": time.time_ns(),
        }
        if owner_provider != "unknown":
            state["owner_provider"] = owner_provider
        if previous_lease_id is not None:
            state["previous_lease_id"] = previous_lease_id
        # A new lease ID and generation form a new authentication domain, so a
        # removed predecessor's retired hashes intentionally do not carry over.
        atomic_write(path, state)
        return public_state(state, path, extra={"owner_capability": owner_capability})
    finally:
        os.close(fd)


def transfer(args):
    """Rotate an active lease to an exact new owner without changing its generation."""
    valid_owner(args.owner)
    new_owner_provider = valid_owner_provider(args.new_owner_provider)
    valid_provider_owner(args.new_owner, new_owner_provider)
    expected_lease_id = valid_uuid(args.expected_lease_id, "invalid-lease-id")
    owner_capability_hash(args.owner_capability)
    new_capability_sha256 = owner_capability_hash(args.new_owner_capability)
    info = git_info(pathlib.Path(args.worktree))
    owner_dir, path = state_location(info)
    fd = lease_lock(owner_dir)
    writer_fds = []
    try:
        state = safe_read(path)
        if state.get("lease_id") != expected_lease_id:
            fail("lease-id-mismatch")
        if state.get("state") != "active":
            fail("invalid-transfer-state", state.get("state"))
        if not stable_binding_matches(state, info):
            fail("binding-changed")

        # An exact response-loss retry is authorized by the new capability. The
        # old capability remains invalid immediately after the first write.
        if (state.get("owner") == args.new_owner
                and state.get("owner_provider", "unknown") == new_owner_provider
                and (args.owner == args.new_owner
                     or args.owner in state.get("prior_owners", []))
                and hmac.compare_digest(
                    str(state.get("owner_capability_sha256", "")), new_capability_sha256,
                )):
            return public_state(state, path, replay=True)

        if state.get("owner") != args.owner:
            fail("owner-mismatch")
        authenticate(state, args.owner_capability)
        retired_capabilities = list(state.get("retired_owner_capabilities", []))
        retired_hashes = [item["sha256"] for item in retired_capabilities]
        current_hash = state["owner_capability_sha256"]
        if new_capability_sha256 == current_hash or new_capability_sha256 in retired_hashes:
            fail("owner-capability-reuse")
        if len(retired_capabilities) >= 32:
            fail("retired-capability-limit")
        prior_owners = set(state.get("prior_owners", []))
        prior_owners.add(state["owner"])
        prior_owners.discard(args.new_owner)
        if len(prior_owners) > 32:
            fail("prior-owner-limit")
        writer_fds = writer_locks_for(prior_owners)
        current = git_info(pathlib.Path(args.worktree))
        if not stable_binding_matches(state, current):
            fail("binding-changed")
        state.update(
            owner=args.new_owner,
            owner_provider=new_owner_provider,
            owner_capability_sha256=new_capability_sha256,
            retired_owner_capabilities=retired_capabilities + [{
                "owner": state["owner"], "sha256": current_hash,
            }],
        )
        if prior_owners:
            state["prior_owners"] = sorted(prior_owners)
        else:
            state.pop("prior_owners", None)
        atomic_write(path, state)
        return public_state(state, path)
    finally:
        for writer_fd in reversed(writer_fds):
            os.close(writer_fd)
        os.close(fd)


def release(args):
    valid_owner(args.owner)
    bounded_text(args.reason, "invalid-release-reason", 512)
    info = git_info(pathlib.Path(args.worktree))
    owner_dir, path = state_location(info)
    fd = lease_lock(owner_dir)
    try:
        state = safe_read(path)
        if state.get("owner") != args.owner:
            fail("owner-mismatch")
        authenticate(state, args.owner_capability)
        if not stable_binding_matches(state, info):
            fail("binding-changed")
        if state.get("state") == "released":
            if not released_binding_matches(state, info):
                fail("binding-changed")
            if state.get("release_reason") != args.reason:
                fail("release-reason-conflict")
            return public_state(state, path, replay=True)
        if state.get("state") != "active":
            fail("invalid-release-state", state.get("state"))
        state.update(
            state="released",
            head=info["head"],
            released_head=info["head"],
            release_token=new_capability("r"),
            release_reason=args.reason,
            released_at_unix_ns=time.time_ns(),
        )
        atomic_write(path, state)
        return public_state(state, path, extra={"release_token": state["release_token"]})
    finally:
        os.close(fd)


def is_inside(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def in_progress(info):
    admin = pathlib.Path(info["worktree_git_dir"])
    return any(os.path.lexists(admin / name) for name in (
        "MERGE_HEAD", "REVERT_HEAD", "CHERRY_PICK_HEAD", "REBASE_HEAD",
        "BISECT_LOG", "BISECT_START", "rebase-apply", "rebase-merge",
        "sequencer", "index.lock", "HEAD.lock",
    ))


def reject_git_grafts(common):
    path = pathlib.Path(common) / "info" / "grafts"
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        fd = os.open(str(path), flags)
    except FileNotFoundError:
        return
    except OSError:
        fail("unsafe-git-history-overrides")
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                or before.st_nlink != 1 or before.st_size != 0):
            fail("git-history-overrides-present")
        after = path.lstat()
        if (after.st_dev, after.st_ino) != (before.st_dev, before.st_ino):
            fail("unsafe-git-history-overrides")
    except OSError:
        fail("unsafe-git-history-overrides")
    finally:
        os.close(fd)


def nul_records(payload, reason):
    if not payload:
        return []
    if not payload.endswith(b"\0"):
        fail(reason)
    return payload[:-1].split(b"\0")


def safe_index_path(path):
    if (not path or path.startswith(b"/") or b"\0" in path
            or any(part in (b"", b".", b"..") for part in path.split(b"/"))):
        fail("unsafe-index-path")
    return path


def parse_index_entries(payload):
    entries = {}
    for record in nul_records(payload, "unsafe-index-output"):
        try:
            metadata, path = record.split(b"\t", 1)
            mode, oid, stage = metadata.split(b" ")
            mode_text = mode.decode("ascii")
            oid_text = oid.decode("ascii")
        except (ValueError, UnicodeDecodeError):
            fail("unsafe-index-output")
        path = safe_index_path(path)
        if (stage != b"0" or mode_text not in ("100644", "100755", "120000", "160000")
                or not (HEX40.fullmatch(oid_text) or HEX64.fullmatch(oid_text))
                or path in entries):
            fail("unsafe-index-output")
        entries[path] = (mode_text, oid_text)
    return entries


def parse_head_entries(payload):
    entries = {}
    for record in nul_records(payload, "unsafe-head-tree-output"):
        try:
            metadata, path = record.split(b"\t", 1)
            mode, object_type, oid = metadata.split(b" ")
            mode_text = mode.decode("ascii")
            oid_text = oid.decode("ascii")
        except (ValueError, UnicodeDecodeError):
            fail("unsafe-head-tree-output")
        path = safe_index_path(path)
        expected_type = b"commit" if mode_text == "160000" else b"blob"
        if (mode_text not in ("100644", "100755", "120000", "160000")
                or object_type != expected_type
                or not (HEX40.fullmatch(oid_text) or HEX64.fullmatch(oid_text))
                or path in entries):
            fail("unsafe-head-tree-output")
        entries[path] = (mode_text, oid_text)
    return entries


def open_index_parent(root_fd, path):
    parts = path.split(b"/")
    current_fd = os.dup(root_fd)
    try:
        for part in parts[:-1]:
            flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            next_fd = os.open(part, flags, dir_fd=current_fd)
            os.close(current_fd)
            current_fd = next_fd
        return current_fd, parts[-1]
    except OSError:
        os.close(current_fd)
        fail("worktree-transformed-content-present")


def blob_hasher(object_format, size):
    if object_format not in ("sha1", "sha256"):
        fail("unsupported-git-object-format")
    value = hashlib.new(object_format)
    value.update(b"blob " + str(size).encode("ascii") + b"\0")
    return value


def raw_entry_oid(root_fd, path, mode, object_format):
    parent_fd, name = open_index_parent(root_fd, path)
    try:
        before = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        identity = (
            before.st_dev, before.st_ino, before.st_size,
            before.st_mtime_ns, before.st_ctime_ns,
        )
        if mode == "120000":
            if not stat.S_ISLNK(before.st_mode):
                fail("worktree-transformed-content-present")
            target = os.readlink(name, dir_fd=parent_fd)
            if isinstance(target, str):
                target = os.fsencode(target)
            value = blob_hasher(object_format, len(target))
            value.update(target)
        else:
            if not stat.S_ISREG(before.st_mode):
                fail("worktree-transformed-content-present")
            expected_executable = mode == "100755"
            if bool(before.st_mode & 0o111) != expected_executable:
                fail("worktree-transformed-content-present")
            flags = os.O_RDONLY
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            fd = os.open(name, flags, dir_fd=parent_fd)
            try:
                opened = os.fstat(fd)
                if ((opened.st_dev, opened.st_ino, opened.st_size,
                     opened.st_mtime_ns, opened.st_ctime_ns)
                        != identity or not stat.S_ISREG(opened.st_mode)):
                    fail("worktree-transformed-content-present")
                value = blob_hasher(object_format, opened.st_size)
                remaining = opened.st_size
                while remaining:
                    chunk = os.read(fd, min(1_048_576, remaining))
                    if not chunk:
                        fail("worktree-transformed-content-present")
                    value.update(chunk)
                    remaining -= len(chunk)
                after_fd = os.fstat(fd)
                if ((after_fd.st_dev, after_fd.st_ino, after_fd.st_size,
                     after_fd.st_mtime_ns, after_fd.st_ctime_ns)
                        != identity):
                    fail("worktree-transformed-content-present")
            finally:
                os.close(fd)
        after = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        if (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns,
                after.st_ctime_ns) != identity:
            fail("worktree-transformed-content-present")
        return value.hexdigest()
    except OSError:
        fail("worktree-transformed-content-present")
    finally:
        os.close(parent_fd)


def verify_raw_worktree(target, budget=None):
    if budget is None:
        budget = [200_000]
    object_format = git(target, "rev-parse", "--show-object-format")
    index = parse_index_entries(run_git_bytes([
        "-C", str(target), "ls-files", "--stage", "-z",
    ], reason="worktree-index-unavailable").stdout)
    head = parse_head_entries(run_git_bytes([
        "-C", str(target), "ls-tree", "-r", "-z", "--full-tree", "HEAD",
    ], reason="worktree-head-tree-unavailable").stdout)
    budget[0] -= len(index)
    if budget[0] < 0:
        fail("worktree-verification-limit")
    if index != head:
        fail("worktree-index-not-head")
    for ignored_args in (
        ("--others", "--exclude-standard", "-z"),
        ("--others", "--ignored", "--exclude-standard", "-z"),
    ):
        if run_git_bytes([
            "-C", str(target), "ls-files", *ignored_args,
        ], reason="worktree-untracked-check-unavailable").stdout:
            fail("worktree-content-present")

    root_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    if hasattr(os, "O_NOFOLLOW"):
        root_flags |= os.O_NOFOLLOW
    try:
        root_fd = os.open(str(target), root_flags)
    except OSError:
        fail("unsafe-worktree")
    try:
        target_bytes = os.fsencode(str(target))
        for path, (mode, expected_oid) in index.items():
            if mode == "160000":
                submodule = canonical_existing(
                    pathlib.Path(os.fsdecode(os.path.join(target_bytes, path))),
                    "submodule-content-present",
                )
                submodule_top = canonical_existing(
                    pathlib.Path(git(submodule, "rev-parse", "--show-toplevel")),
                    "submodule-content-present",
                )
                if submodule_top != submodule:
                    fail("submodule-content-present")
                current = git(submodule, "rev-parse", "HEAD")
                if current != expected_oid:
                    fail("submodule-content-present")
                verify_raw_worktree(submodule, budget)
            elif raw_entry_oid(root_fd, path, mode, object_format) != expected_oid:
                fail("worktree-transformed-content-present")
    finally:
        os.close(root_fd)


def content_status(args):
    info = git_info(pathlib.Path(args.worktree))
    try:
        flags_result = run_git([
            "-C", info["worktree_path"], "ls-files", "-v",
        ], reason="worktree-index-unavailable")
        if any(line and line[0] != "H" for line in flags_result.stdout.splitlines()):
            fail("non-normal-index-flags")
        verify_raw_worktree(pathlib.Path(info["worktree_path"]))
        if in_progress(info):
            fail("git-operation-in-progress")
    except LeaseError as exc:
        if exc.reason not in {
            "worktree-content-present", "worktree-transformed-content-present",
            "worktree-index-not-head", "submodule-content-present",
            "non-normal-index-flags", "git-operation-in-progress",
            "worktree-verification-limit",
        }:
            raise
        return {
            "contract": CONTRACT,
            "status": "ok",
            "clean": False,
            "reason": exc.reason,
            "worktree_path": info["worktree_path"],
        }
    return {
        "contract": CONTRACT,
        "status": "ok",
        "clean": True,
        "worktree_path": info["worktree_path"],
    }


def changed_paths(common, left, right):
    """Paths whose content differs between two commits, as an exact set.

    `-z` because a path may contain any byte except NUL, and `--no-renames` so a
    rename reports both the old and the new path. Both sides of a rename must be
    accounted for: dropping either one would let a rename that only landed
    halfway read as contained.
    """
    result = run_git_bytes([
        "--git-dir", str(common), "diff", "--name-only", "-z", "--no-renames",
        "--no-textconv", left, right,
    ], reason="released-head-comparison-unavailable")
    return {entry for entry in result.stdout.split(b"\0") if entry}


def released_head_content_is_in_main(state, common):
    """True when every path the released head touched is byte-identical in main.

    Why literal ancestry is not enough. A squash merge replays the whole branch
    as one new commit with a new identity, so `merge-base --is-ancestor` is
    false immediately after the merge even though every byte of the work landed.
    This repository merges by squash -- #164, #165, and #166 are each
    single-parent merge commits -- so ancestry alone made every worktree that
    ever committed unremovable through the broker, and the strandings piled up.

    What replaces it, stated as the exact claim being proved: let A be the paths
    the branch changed relative to its merge base, and B the paths where the
    released head and origin/main differ today. `A & B == set()` says every path
    in A has identical content on both sides, which is precisely "the branch's
    work is already in main". It is not a heuristic and it is not patch-id
    matching -- `git cherry` compares per-commit patch ids, which a squash of
    several commits into one never matches.

    Conservative in every direction that matters:
      * a path the branch changed that main lacks, or holds differently, is in
        B, so the check refuses -- unmerged work is never removable;
      * a path the branch deleted that main still has is in B, so refusing is
        correct;
      * a path main changed further after the merge is in B, so this refuses
        rather than guesses. That is a false refusal, not a false accept, and
        the owner still has `release` plus the archive tag.

    Falsified history cannot reach here. Every broker git call runs with
    GIT_NO_REPLACE_OBJECTS=1 from fixed_git_environment(), and the caller runs
    reject_git_grafts() before this, so the replacement-ref and graft attacks
    covered by test_replacement_refs_cannot_falsify_merge_ancestry and
    test_legacy_grafts_cannot_falsify_merge_ancestry still fail closed.

    The removal path tags state["released_head"] as an archive ref before it
    deletes anything, so an accepted squash removal is still recoverable from
    the exact original commit.
    """
    released_head = state["released_head"]
    base = run_git([
        "--git-dir", str(common), "merge-base", released_head, "refs/remotes/origin/main",
    ], allowed=(0, 1))
    if base.returncode != 0 or not base.stdout.strip():
        return False
    branch_changed = changed_paths(common, base.stdout.strip(), released_head)
    if not branch_changed:
        # The branch changed nothing relative to its base, so there is nothing
        # its removal could lose.
        return True
    if not (branch_changed & changed_paths(
        common, released_head, "refs/remotes/origin/main",
    )):
        return True
    return landed_at_some_commit(common, released_head, branch_changed, base.stdout.strip())


def landed_at_some_commit(common, released_head, branch_changed, base):
    """True when some commit on origin/main holds every path in A byte-identical.

    Comparing against origin/main *as it is today* measures a moving target. A
    squash lands the work, and then ordinary later commits touch some of the
    same paths; those paths re-enter the difference set and a branch whose work
    fully landed reads as uncontained. Measured on the real
    `codex/hermes-a87e-system-ledger` lease: its work landed as squash commit
    `2cee6711` with all four paths byte-identical, then `556cee08` landed on top
    and touched two of them, so the today-comparison refused a branch that was
    genuinely safe to remove. In an active repository that is the common case,
    not an edge case.

    So look for the landing commit instead: walk origin/main's first-parent
    history from the tip down to the merge base and accept the first commit
    where every path in A matches the released head exactly. Finding one proves
    the work reached main intact; the later drift is someone else's work on top
    of it, which was never this branch's to keep.

    Still conservative. A path the branch changed that never matched anywhere on
    main yields no such commit and refuses. Deletions are compared the same way,
    through the same missing-blob sentinel, so a deletion that did not land also
    refuses. The walk is bounded by the merge base, so it cannot wander into
    unrelated history, and the archive tag is still written before any removal.

    Two limits a later reader should not mistake for defects. `--first-parent`
    means work that reached main as the second parent of a true merge is
    invisible to this walk, so such a branch refuses; that fails safe and is the
    right trade in a squash-merging repository, but it is a refusal to explain
    rather than a bug to chase. And a coincidental match inside the merge-base
    bound is theoretically possible; it is narrow, the archive tag backstops it,
    and test_never_landed_path_blocks_removal_even_after_main_moves is the guard
    for the general case.
    """
    history = run_git([
        "--git-dir", str(common), "rev-list", "--first-parent",
        "refs/remotes/origin/main", "^" + base,
    ], allowed=(0, 1))
    if history.returncode != 0:
        return False
    candidates = [line.strip() for line in history.stdout.splitlines() if line.strip()]
    if not candidates:
        return False
    wanted = {}
    for path in branch_changed:
        wanted[path] = blob_at(common, released_head, path)
    for commit in candidates:
        if all(blob_at(common, commit, path) == oid for path, oid in wanted.items()):
            return True
    return False


def blob_at(common, commit, path):
    """The blob id for one path at one commit, or None when absent.

    None is a real value here, not an error: a path the branch deleted must read
    as absent on the landing side too, otherwise a half-landed deletion would
    pass. `--` separates the revision from the pathspec so a path that looks
    like a revision cannot be reinterpreted.
    """
    result = run_git_bytes([
        "--git-dir", str(common), "rev-parse", "--quiet", "--verify",
    ] + [commit_path_spec(commit, path)], allowed=(0, 1))
    if result.returncode != 0:
        return None
    value = result.stdout.strip()
    return value or None


def commit_path_spec(commit, path):
    """`<commit>:<path>` with the path decoded exactly as git recorded it."""
    if isinstance(path, bytes):
        path = path.decode("utf-8", "surrogateescape")
    return str(commit) + ":" + path


def preflight_released_head(state, common):
    reject_git_grafts(common)
    remote = run_git(["--git-dir", common, "show-ref", "--verify", "--quiet", "refs/remotes/origin/main"], allowed=(0, 1))
    if remote.returncode != 0:
        fail("origin-main-unavailable")
    merged = run_git(["--git-dir", common, "merge-base", "--is-ancestor", state["released_head"], "refs/remotes/origin/main"], allowed=(0, 1))
    if merged.returncode != 0 and not released_head_content_is_in_main(state, common):
        fail("released-head-not-merged")


def preflight_removal(state, info):
    target = pathlib.Path(info["worktree_path"])
    cwd = pathlib.Path(os.getcwd()).resolve(strict=True)
    if is_inside(cwd, target):
        fail("current-worktree-protected")
    flags_result = run_git(["-C", str(target), "ls-files", "-v"], reason="worktree-index-unavailable")
    abnormal = [line for line in flags_result.stdout.splitlines() if line and line[0] != "H"]
    if abnormal:
        fail("non-normal-index-flags")
    verify_raw_worktree(target)
    if in_progress(info):
        fail("git-operation-in-progress")
    preflight_released_head(state, info["repo_common_dir"])


def test_pause_after_writer_lock():
    if not TEST_MODE:
        return
    marker_value = os.environ.get("WORKTREE_OWNER_LEASE_TEST_HOLD_MARKER")
    if not marker_value:
        return
    marker = pathlib.Path(marker_value)
    marker.write_text("locked\n")
    deadline = time.monotonic() + 5
    while not marker.with_suffix(".release").exists():
        if time.monotonic() >= deadline:
            fail("test-release-timeout")
        time.sleep(0.01)


def test_crash(stage):
    if TEST_MODE and os.environ.get("WORKTREE_OWNER_LEASE_TEST_CRASH_STAGE") == stage:
        os._exit(91 if stage == "after-state" else 92)


def test_pause_before_branch_delete():
    if not TEST_MODE:
        return
    marker_value = os.environ.get("WORKTREE_OWNER_LEASE_TEST_BRANCH_DELETE_MARKER")
    if not marker_value:
        return
    marker = pathlib.Path(marker_value)
    marker.write_text("ready\n")
    deadline = time.monotonic() + 5
    while not marker.with_suffix(".release").exists():
        if time.monotonic() >= deadline:
            fail("test-branch-delete-timeout")
        time.sleep(0.01)


def require_expected_lease(state, args):
    expected = getattr(args, "expected_lease_id", None)
    if expected is not None and state.get("lease_id") != expected:
        fail("lease-id-mismatch")


def delete_bound_branch(state, common):
    if state.get("detached") is True:
        return False
    branch_ref = "refs/heads/" + state["branch"]
    branch_value = run_git([
        "--git-dir", str(common), "rev-parse", "-q", "--verify", branch_ref,
    ], allowed=(0, 1, 128))
    if branch_value.returncode != 0 or branch_value.stdout.strip() != state["released_head"]:
        return False
    listed = run_git([
        "--git-dir", str(common), "worktree", "list", "--porcelain",
    ])
    if any(line == "branch " + branch_ref for line in listed.stdout.splitlines()):
        return False
    test_pause_before_branch_delete()
    deleted = run_git([
        "--git-dir", str(common), "update-ref", "-d", branch_ref, state["released_head"],
    ], allowed=(0, 1, 128))
    return deleted.returncode == 0


def remove(args):
    info = git_info(pathlib.Path(args.worktree))
    owner_dir, path = state_location(info)
    lease_fd = lease_lock(owner_dir)
    writer_fds = []
    state = None
    tag_created = False
    try:
        state = safe_read(path)
        require_expected_lease(state, args)
        if state.get("state") == "active":
            fail("owner-not-released")
        if state.get("state") != "released":
            fail("invalid-removal-state", state.get("state"))
        valid_release_token(args.release_token)
        if not hmac.compare_digest(str(state.get("release_token", "")), args.release_token):
            fail("release-token-mismatch")
        if not released_binding_matches(state, info):
            fail("binding-changed")
        writer_fds = all_writer_locks(state)
        test_pause_after_writer_lock()
        current = git_info(pathlib.Path(args.worktree))
        if not released_binding_matches(state, current):
            fail("binding-changed")
        preflight_removal(state, current)
        tag_name = "archive/" + time.strftime("%Y-%m-%d") + "/worktree/" + state["lease_id"]
        tag_ref = "refs/tags/" + tag_name
        existing = run_git(["--git-dir", current["repo_common_dir"], "rev-parse", "-q", "--verify", tag_ref], allowed=(0, 1))
        if existing.returncode == 0:
            if existing.stdout.strip() != state["released_head"]:
                fail("archive-tag-conflict")
        else:
            run_git(["--git-dir", current["repo_common_dir"], "tag", tag_name, state["released_head"]], reason="archive-tag-failed")
            tag_created = True
        state.update(state="removing", archive_tag=tag_name, removal_started_at_unix_ns=time.time_ns())
        atomic_write(path, state)
        test_crash("after-state")
        result = run_git([
            "--git-dir", current["repo_common_dir"], "worktree", "remove", "--force",
            current["worktree_path"],
        ], reason="worktree-remove-failed", allowed=(0, 1, 128))
        if os.path.lexists(current["worktree_path"]):
            state.update(state="released", removal_failed_at_unix_ns=time.time_ns())
            atomic_write(path, state)
            if tag_created:
                run_git(["--git-dir", current["repo_common_dir"], "tag", "-d", tag_name], allowed=(0, 1))
            fail("worktree-remove-failed", (result.stderr or result.stdout).strip())
        if TEST_MODE and os.environ.get("WORKTREE_OWNER_LEASE_TEST_RECREATE_ADMIN_AFTER_REMOVE") == "1":
            pathlib.Path(current["worktree_git_dir"]).mkdir(parents=True, exist_ok=True)
        listed = run_git([
            "--git-dir", current["repo_common_dir"], "worktree", "list", "--porcelain",
        ], reason="git-binding-unavailable")
        if (os.path.lexists(current["worktree_git_dir"])
                or any(line == "worktree " + current["worktree_path"] for line in listed.stdout.splitlines())):
            fail("ambiguous-removal-state")
        test_crash("after-remove")
        branch_deleted = delete_bound_branch(state, current["repo_common_dir"])
        state.update(
            state="removed",
            removed_at_unix_ns=time.time_ns(),
            branch_deleted=branch_deleted,
            release_token_consumed=True,
        )
        atomic_write(path, state)
        return public_state(state, path, extra={"writer_lock_checked": True})
    finally:
        for writer_fd in reversed(writer_fds):
            os.close(writer_fd)
        os.close(lease_fd)


def state_file_context(path_value):
    path = pathlib.Path(path_value)
    if not path.is_absolute() or path.suffix != ".json":
        fail("unsafe-lease-state")
    parent = private_dir(path.parent, "unsafe-owner-directory")
    if parent.name != "codex-worktree-owners":
        fail("unsafe-lease-state")
    return parent, path


def require_state_location(state, owner_dir, path):
    common = canonical_existing(pathlib.Path(str(state.get("repo_common_dir", ""))), "unsafe-git-common-dir")
    expected_parent = common / "codex-worktree-owners"
    key = hashlib.sha256((str(common) + "\0" + str(state.get("worktree_path", ""))).encode()).hexdigest()
    if owner_dir != expected_parent or path.name != key + ".json":
        fail("lease-location-mismatch")
    return common


def discover_cleanup(args):
    """List only non-secret later-actor cleanup locators for one repository."""
    common = repo_common_from_anchor(pathlib.Path(args.repo))
    owner_dir = common / "codex-worktree-owners"
    if not (owner_dir.exists() or owner_dir.is_symlink()):
        return {"contract": CONTRACT, "status": "ok", "candidates": []}
    owner_dir = private_dir(owner_dir, "unsafe-owner-directory")
    lease_fd = lease_lock(owner_dir)
    try:
        entries = []
        try:
            with os.scandir(owner_dir) as iterator:
                for entry in iterator:
                    entries.append(entry.name)
                    if len(entries) > DISCOVERY_ENTRY_LIMIT:
                        fail("cleanup-discovery-limit")
        except OSError:
            fail("cleanup-discovery-failed")
        candidates = []
        for name in sorted(entries):
            if name in (".lock", ".ledger.lock"):
                continue
            if re.fullmatch(r"[0-9a-f]{64}\.json", name) is None:
                fail("unexpected-owner-state-entry")
            path = owner_dir / name
            state = safe_read(path)
            state_common = require_state_location(state, owner_dir, path)
            if state_common != common:
                fail("lease-location-mismatch")
            if state["state"] in ("released", "removing"):
                candidates.append({
                    "state_file": str(path),
                    "lease_id": state["lease_id"],
                    "state": state["state"],
                    "worktree_path": state["worktree_path"],
                })
        return {"contract": CONTRACT, "status": "ok", "candidates": candidates}
    finally:
        os.close(lease_fd)


def reconcile(args):
    owner_dir, path = state_file_context(args.state_file)
    lease_fd = lease_lock(owner_dir)
    writer_fds = []
    try:
        state = safe_read(path)
        common = require_state_location(state, owner_dir, path)
        require_expected_lease(state, args)
        valid_release_token(args.release_token)
        if not hmac.compare_digest(str(state.get("release_token", "")), args.release_token):
            fail("release-token-mismatch")
        if state.get("state") == "removed":
            return public_state(state, path, replay=True)
        if state.get("state") != "removing":
            fail("invalid-reconciliation-state", state.get("state"))
        writer_fds = all_writer_locks(state)
        target = pathlib.Path(str(state.get("worktree_path", "")))
        if os.path.lexists(target):
            current = git_info(target)
            if not released_binding_matches(state, current):
                fail("binding-changed")
            state.update(state="released", removal_reconciled="worktree-present", reconciled_at_unix_ns=time.time_ns())
            atomic_write(path, state)
            return public_state(state, path, extra={"writer_lock_checked": True})
        if os.path.lexists(str(state.get("worktree_git_dir", ""))):
            fail("ambiguous-removal-state")
        listed = run_git(["--git-dir", str(common), "worktree", "list", "--porcelain"], reason="git-binding-unavailable")
        if any(line == "worktree " + str(target) for line in listed.stdout.splitlines()):
            fail("ambiguous-removal-state")
        tag_name = state.get("archive_tag")
        if not isinstance(tag_name, str) or not tag_name:
            fail("archive-tag-missing")
        tag_value = run_git(["--git-dir", str(common), "rev-parse", "-q", "--verify", "refs/tags/" + tag_name], allowed=(0, 1))
        if tag_value.returncode != 0 or tag_value.stdout.strip() != state.get("released_head"):
            fail("archive-tag-mismatch")
        branch_deleted = delete_bound_branch(state, common)
        state.update(
            state="removed", removal_reconciled="worktree-absent", reconciled_at_unix_ns=time.time_ns(),
            removed_at_unix_ns=time.time_ns(), branch_deleted=branch_deleted, release_token_consumed=True,
        )
        atomic_write(path, state)
        return public_state(state, path, extra={"writer_lock_checked": True})
    finally:
        for writer_fd in reversed(writer_fds):
            os.close(writer_fd)
        os.close(lease_fd)


def reconcile_absent_released(args):
    """Finalize a released lease whose exact worktree already disappeared."""
    owner_dir, path = state_file_context(args.state_file)
    lease_fd = lease_lock(owner_dir)
    writer_fds = []
    try:
        state = safe_read(path)
        common = require_state_location(state, owner_dir, path)
        require_expected_lease(state, args)
        valid_release_token(args.release_token)
        if not hmac.compare_digest(str(state.get("release_token", "")), args.release_token):
            fail("release-token-mismatch")
        if state.get("state") == "removed":
            return public_state(state, path, replay=True)
        if state.get("state") != "released":
            fail("invalid-reconciliation-state", state.get("state"))
        writer_fds = all_writer_locks(state)
        target = pathlib.Path(str(state.get("worktree_path", "")))
        if os.path.lexists(target) or os.path.lexists(str(state.get("worktree_git_dir", ""))):
            fail("ambiguous-removal-state")
        listed = run_git([
            "--git-dir", str(common), "worktree", "list", "--porcelain",
        ], reason="git-binding-unavailable")
        if any(line == "worktree " + str(target) for line in listed.stdout.splitlines()):
            fail("ambiguous-removal-state")
        preflight_released_head(state, str(common))
        tag_name = "archive/" + time.strftime("%Y-%m-%d") + "/worktree/" + state["lease_id"]
        tag_ref = "refs/tags/" + tag_name
        existing = run_git([
            "--git-dir", str(common), "rev-parse", "-q", "--verify", tag_ref,
        ], allowed=(0, 1))
        if existing.returncode == 0:
            if existing.stdout.strip() != state["released_head"]:
                fail("archive-tag-conflict")
        else:
            run_git([
                "--git-dir", str(common), "tag", tag_name, state["released_head"],
            ], reason="archive-tag-failed")
        now = time.time_ns()
        state.update(
            state="removing", archive_tag=tag_name,
            removal_started_at_unix_ns=now,
            removal_reconciled="released-worktree-absent",
            reconciled_at_unix_ns=now,
        )
        atomic_write(path, state)
        test_crash("after-state")
        branch_deleted = delete_bound_branch(state, common)
        state.update(
            state="removed", removed_at_unix_ns=time.time_ns(),
            branch_deleted=branch_deleted, release_token_consumed=True,
        )
        atomic_write(path, state)
        return public_state(state, path, extra={"writer_lock_checked": True})
    finally:
        for writer_fd in reversed(writer_fds):
            os.close(writer_fd)
        os.close(lease_fd)


def cleanup_released(args):
    """Complete an exact released lease without exposing its stored token."""
    expected_lease_id = valid_uuid(args.expected_lease_id, "invalid-lease-id")
    owner_dir, path = state_file_context(args.state_file)
    lease_fd = lease_lock(owner_dir)
    try:
        state = safe_read(path)
        require_state_location(state, owner_dir, path)
        if state.get("lease_id") != expected_lease_id:
            fail("lease-id-mismatch")
        state_name = state.get("state")
        if state_name == "active":
            fail("owner-not-released")
        if state_name not in ("released", "removing", "removed"):
            fail("invalid-cleanup-state", state_name)
        release_token = state["release_token"]
        worktree_path = state["worktree_path"]
    finally:
        # Never recurse into remove/reconcile while holding the same lease lock.
        # Each downstream operation reopens and fully revalidates the state.
        os.close(lease_fd)

    if state_name == "released" and not os.path.lexists(worktree_path):
        delegated = argparse.Namespace(
            state_file=str(path),
            release_token=release_token,
            expected_lease_id=expected_lease_id,
        )
        validate_test_boundary(delegated)
        result = reconcile_absent_released(delegated)
    elif state_name == "released":
        delegated = argparse.Namespace(
            worktree=worktree_path,
            release_token=release_token,
            expected_lease_id=expected_lease_id,
        )
        validate_test_boundary(delegated)
        result = remove(delegated)
    else:
        delegated = argparse.Namespace(
            state_file=str(path),
            release_token=release_token,
            expected_lease_id=expected_lease_id,
        )
        validate_test_boundary(delegated)
        result = reconcile(delegated)
        if result.get("state") == "released":
            delegated = argparse.Namespace(
                worktree=worktree_path,
                release_token=release_token,
                expected_lease_id=expected_lease_id,
            )
            validate_test_boundary(delegated)
            result = remove(delegated)

    # The cleanup handoff is deliberately non-secret. The 0600 lease state is
    # the only place this path reads the release token.
    result = dict(result)
    result.pop("release_token", None)
    result.pop("owner_capability", None)
    return result


def recovery_root(common, create=False):
    root = pathlib.Path(common) / "codex-worktree-owner-recovery"
    return private_dir(
        root, "unsafe-recovery-directory", create=create,
    )


def recovery_subdir(common, name, create=False):
    if re.fullmatch(r"[a-z][a-z0-9-]{0,63}", name) is None:
        fail("unsafe-recovery-directory")
    root = recovery_root(common, create=create)
    path = root / name
    return private_dir(
        path, "unsafe-recovery-directory", create=create,
    )


def worktree_inventory(common):
    output = run_git([
        "--git-dir", str(common), "worktree", "list", "--porcelain",
    ]).stdout
    records = []
    current = {}
    for line in output.splitlines() + [""]:
        if not line:
            if current:
                if "worktree_path" not in current or "head" not in current:
                    fail("malformed-worktree-inventory")
                records.append(current)
                current = {}
            continue
        if line.startswith("worktree "):
            if current:
                fail("malformed-worktree-inventory")
            current["worktree_path"] = line[len("worktree "):]
        elif line.startswith("HEAD "):
            current["head"] = line[len("HEAD "):]
        elif line.startswith("branch refs/heads/"):
            current["branch"] = line[len("branch refs/heads/"):]
        elif line == "detached":
            current["branch"] = None
            current["detached"] = True
        elif line == "bare":
            current["bare"] = True
        elif line.startswith("prunable "):
            current["prunable"] = True
        elif line.startswith("locked"):
            current["locked"] = True
        else:
            fail("malformed-worktree-inventory")
    if len(records) > DISCOVERY_ENTRY_LIMIT:
        fail("worktree-inventory-limit")
    paths = [item["worktree_path"] for item in records]
    if len(set(paths)) != len(paths):
        fail("malformed-worktree-inventory")
    return sorted(records, key=lambda item: item["worktree_path"])


def provider_head_inventory(repo):
    result = run_git([
        "-C", str(repo), "ls-remote", "--heads", "origin",
    ], reason="provider-head-readback-unavailable")
    heads = []
    for line in result.stdout.splitlines():
        try:
            oid, ref = line.split("\t", 1)
        except ValueError:
            fail("malformed-provider-head-readback")
        if (
            not ref.startswith("refs/heads/")
            or not (HEX40.fullmatch(oid) or HEX64.fullmatch(oid))
        ):
            fail("malformed-provider-head-readback")
        heads.append({"ref": ref, "head": oid})
    if len(heads) > DISCOVERY_ENTRY_LIMIT:
        fail("provider-head-inventory-limit")
    return sorted(heads, key=lambda item: item["ref"])


def local_branch_inventory(common):
    output = run_git([
        "--git-dir", str(common), "for-each-ref",
        "--format=%(refname)%00%(objectname)", "refs/heads/",
    ]).stdout
    branches = []
    for line in output.splitlines():
        try:
            ref, oid = line.split("\0", 1)
        except ValueError:
            fail("malformed-local-branch-inventory")
        if (
            not ref.startswith("refs/heads/")
            or not (HEX40.fullmatch(oid) or HEX64.fullmatch(oid))
        ):
            fail("malformed-local-branch-inventory")
        branches.append({"ref": ref, "head": oid})
    if len(branches) > DISCOVERY_ENTRY_LIMIT:
        fail("local-branch-inventory-limit")
    return sorted(branches, key=lambda item: item["ref"])


def read_only_writer_evidence(owner):
    valid_owner(owner)
    root = LOCK_ROOT
    if not (root.exists() or root.is_symlink()):
        return {"state": "absent", "free": True, "path": str(root / (owner + ".lock"))}
    root = private_dir(
        root, "unsafe-writer-lock-directory", exact_mode=False,
    )
    path = root / (owner + ".lock")
    flags = os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(str(path), flags)
    except FileNotFoundError:
        return {"state": "absent", "free": True, "path": str(path)}
    except OSError:
        return {"state": "unsafe", "free": False, "path": str(path)}
    try:
        st = os.fstat(fd)
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.getuid()
            or st.st_nlink != 1
            or stat.S_IMODE(st.st_mode) & 0o022
        ):
            return {"state": "unsafe", "free": False, "path": str(path)}
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"state": "locked", "free": False, "path": str(path)}
        after = path.lstat()
        if (after.st_dev, after.st_ino) != (st.st_dev, st.st_ino):
            return {"state": "unsafe", "free": False, "path": str(path)}
        fcntl.flock(fd, fcntl.LOCK_UN)
        return {"state": "unlocked", "free": True, "path": str(path)}
    except OSError:
        return {"state": "unsafe", "free": False, "path": str(path)}
    finally:
        os.close(fd)


def process_working_directories():
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-a", "-d", "cwd", "-F0pn"],
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode not in (0, 1):
        return None
    directories = {}
    pid = None
    for field in result.stdout.replace(b"\n", b"").split(b"\0"):
        if not field:
            continue
        marker, value = field[:1], field[1:]
        if marker == b"p":
            try:
                pid = int(value)
            except ValueError:
                pid = None
        elif marker == b"n" and pid is not None:
            try:
                path = value.decode("utf-8")
            except UnicodeDecodeError:
                return None
            directories[pid] = path
    return directories


def process_snapshot():
    try:
        result = subprocess.run(
            ["/bin/ps", "-axo", "pid=,command="],
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {"state": "unavailable", "processes": []}
    if result.returncode != 0:
        return {"state": "unavailable", "processes": []}
    processes = []
    for line in result.stdout.decode("utf-8", "replace").splitlines():
        stripped = line.lstrip()
        try:
            pid_text, command = stripped.split(None, 1)
            pid = int(pid_text)
        except (ValueError, IndexError):
            continue
        processes.append((pid, command))
    directories = process_working_directories()
    if directories is None:
        return {"state": "unavailable", "processes": []}
    return {
        "state": "available",
        "processes": [
            (pid, command, directories.get(pid))
            for pid, command in processes
        ],
    }


def process_evidence(snapshot, worktree_path, owner):
    if snapshot["state"] != "available":
        return {"free": False, "state": "unavailable", "matching_pids": []}
    matches = []
    for process in snapshot["processes"]:
        if len(process) == 2:
            pid, command = process
            cwd = None
        else:
            pid, command, cwd = process
        cwd_inside = cwd == worktree_path or (
            isinstance(cwd, str) and cwd.startswith(worktree_path + os.sep)
        )
        if worktree_path in command or owner in command or cwd_inside:
            matches.append(pid)
            if len(matches) > 64:
                return {
                    "free": False, "state": "limit-exceeded",
                    "matching_pids": matches[:64],
                }
    return {
        "free": not matches,
        "state": "clear" if not matches else "matched",
        "matching_pids": matches,
    }


def recovery_refusal_reasons(candidate, evidence):
    reasons = []
    if candidate.get("expected_action") != "recover-release":
        reasons.append("not-release-proposal")
    checks = (
        ("path_safe", "unsafe-or-symlinked-path", False),
        ("binding_matches", "drifted-binding", False),
        ("head_contained", "non-main-contained", False),
        ("lease_valid", "invalid-lease-evidence", False),
        ("owner_resolved", "owner-unresolved", False),
        ("writer_lock_free", "live-writer", False),
        ("process_free", "live-process", False),
        ("index_normal", "non-normal-index", False),
        ("sparse", "sparse-checkout", True),
        ("staged_clean", "staged-content", False),
        ("unstaged_clean", "unstaged-content", False),
        ("untracked_clean", "untracked-content", False),
        ("ignored_clean", "ignored-content", False),
        ("git_operation_free", "git-operation-in-progress", False),
        ("recovery_valid", "invalid-recovery-evidence", False),
    )
    for key, reason, refused_value in checks:
        if evidence.get(key) == refused_value:
            reasons.append(reason)
    if candidate.get("owner_status") in ("active", "active-foreign"):
        reasons.append("active-owner")
    for key, reason in (
        ("platform_managed", "platform-managed"),
        ("load_bearing", "load-bearing-runtime"),
        ("post_cutoff", "post-cutoff"),
        ("prevention_owner", "prevention-owner"),
        ("er912_binding_changed", "er912-binding-changed"),
    ):
        if candidate.get(key) is True:
            reasons.append(reason)
    return reasons


def validate_recovery_candidate(candidate):
    required = {
        "candidate_id", "worktree_path", "expected_branch", "expected_head",
        "lease_kind", "lease_id", "generation", "owner", "owner_provider",
        "owner_status", "archive_tag", "archive_tag_object",
        "archive_peeled_commit", "expected_action", "platform_managed",
        "load_bearing", "post_cutoff", "prevention_owner",
        "er912_binding_changed",
    }
    if not isinstance(candidate, dict) or set(candidate) != required:
        fail("invalid-recovery-inventory")
    candidate_id = bounded_text(
        candidate["candidate_id"], "invalid-recovery-inventory", 256,
    )
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,255}", candidate_id) is None:
        fail("invalid-recovery-inventory")
    path = pathlib.Path(
        bounded_text(
            candidate["worktree_path"], "invalid-recovery-inventory", 4096,
        )
    )
    if not path.is_absolute():
        fail("invalid-recovery-inventory")
    branch = candidate["expected_branch"]
    if branch is not None:
        bounded_text(branch, "invalid-recovery-inventory", 512)
    head = candidate["expected_head"]
    if not isinstance(head, str) or not (
        HEX40.fullmatch(head) or HEX64.fullmatch(head)
    ):
        fail("invalid-recovery-inventory")
    if candidate["lease_kind"] not in ("existing", "legacy-no-lease"):
        fail("invalid-recovery-inventory")
    lease_id = candidate["lease_id"]
    generation = candidate["generation"]
    if candidate["lease_kind"] == "existing":
        valid_uuid(lease_id, "invalid-recovery-inventory")
        valid_uuid(generation, "invalid-recovery-inventory")
    else:
        if (
            not isinstance(lease_id, str)
            or lease_id != "legacy-no-lease:" + candidate_id
            or generation is not None
        ):
            fail("invalid-recovery-inventory")
    provider = valid_owner_provider(
        candidate["owner_provider"], "invalid-recovery-inventory",
    )
    owner_status = candidate["owner_status"]
    if owner_status not in (
        "inactive", "active", "active-foreign", "unresolved",
    ):
        fail("invalid-recovery-inventory")
    if owner_status != "unresolved":
        try:
            valid_provider_owner(candidate["owner"], provider)
        except LeaseError:
            fail("invalid-recovery-inventory")
    else:
        bounded_text(
            candidate["owner"], "invalid-recovery-inventory", 256,
        )
    tag = bounded_text(
        candidate["archive_tag"], "invalid-recovery-inventory", 1024,
    )
    if (
        not tag.startswith("archive/")
        or ".." in tag.split("/")
        or tag.startswith("/")
    ):
        fail("invalid-recovery-inventory")
    for key in ("archive_tag_object", "archive_peeled_commit"):
        oid = candidate[key]
        if not isinstance(oid, str) or not (
            HEX40.fullmatch(oid) or HEX64.fullmatch(oid)
        ):
            fail("invalid-recovery-inventory")
    if candidate["archive_peeled_commit"] != head:
        fail("invalid-recovery-inventory")
    if candidate["expected_action"] not in (
        "recover-release", "evaluate-retain",
    ):
        fail("invalid-recovery-inventory")
    for key in (
        "platform_managed", "load_bearing", "post_cutoff",
        "prevention_owner", "er912_binding_changed",
    ):
        if not isinstance(candidate[key], bool):
            fail("invalid-recovery-inventory")
    return candidate


def validate_keep_item(item):
    if not isinstance(item, dict):
        fail("invalid-recovery-inventory")
    required = {
        "item_id", "kind", "owner", "reason", "revisit_trigger",
    }
    if not required.issubset(item):
        fail("invalid-recovery-inventory")
    allowed = required | {
        "path", "ref", "expected_head", "snapshot_sha256", "item_count",
        "snapshot_kind", "selectors",
    }
    if not set(item).issubset(allowed):
        fail("invalid-recovery-inventory")
    bounded_text(item["item_id"], "invalid-recovery-inventory", 256)
    if item["kind"] not in (
        "worktree", "provider-ref", "recovery-surface", "branch",
    ):
        fail("invalid-recovery-inventory")
    for key in ("owner", "reason", "revisit_trigger"):
        bounded_text(item[key], "invalid-recovery-inventory", 1024)
    if "path" in item:
        path = pathlib.Path(
            bounded_text(item["path"], "invalid-recovery-inventory", 4096)
        )
        if not path.is_absolute():
            fail("invalid-recovery-inventory")
    if "ref" in item:
        bounded_text(item["ref"], "invalid-recovery-inventory", 1024)
    if "expected_head" in item:
        oid = item["expected_head"]
        if not isinstance(oid, str) or not (
            HEX40.fullmatch(oid) or HEX64.fullmatch(oid)
        ):
            fail("invalid-recovery-inventory")
    if item["kind"] == "recovery-surface":
        snapshot = item.get("snapshot_sha256")
        if (
            not isinstance(snapshot, str)
            or HEX64.fullmatch(snapshot) is None
            or "item_count" not in item
            or item.get("snapshot_kind") not in (
                "file-tree", "local-refs", "remote-tags", "stashes",
            )
            or not isinstance(item.get("selectors"), list)
            or len(item["selectors"]) > 16
        ):
            fail("invalid-recovery-inventory")
        positive_int(item["item_count"], "invalid-recovery-inventory")
        selectors = item["selectors"]
        if selectors != sorted(set(selectors)):
            fail("invalid-recovery-inventory")
        for selector in selectors:
            bounded_text(selector, "invalid-recovery-inventory", 1024)
        if item["snapshot_kind"] == "file-tree":
            if "path" not in item or selectors:
                fail("invalid-recovery-inventory")
        elif item["snapshot_kind"] == "stashes":
            if selectors:
                fail("invalid-recovery-inventory")
        elif not selectors:
            fail("invalid-recovery-inventory")
    elif any(key in item for key in (
        "snapshot_sha256", "item_count", "snapshot_kind", "selectors",
    )):
        fail("invalid-recovery-inventory")
    return item


def load_recovery_inventory(repo, common):
    top = canonical_existing(
        pathlib.Path(git(repo, "rev-parse", "--show-toplevel")),
        "unsafe-repo-anchor",
    )
    inventory_path = top / RECOVERY_INVENTORY_RELATIVE
    try:
        inventory_path.relative_to(top)
    except ValueError:
        fail("invalid-recovery-inventory")
    data = safe_regular_bytes(
        inventory_path, "invalid-recovery-inventory",
    )
    inventory = strict_json_bytes(
        data, "invalid-recovery-inventory", canonical=True,
    )
    required = {
        "contract", "repo_common_dir", "frozen_at_unix_ns",
        "cutoff_unix_ns", "approval_source_thread_id", "source_record",
        "recovery", "proposals", "keep",
    }
    if not isinstance(inventory, dict) or set(inventory) != required:
        fail("invalid-recovery-inventory")
    if inventory["contract"] != RECOVERY_INVENTORY_CONTRACT:
        fail("invalid-recovery-inventory")
    if inventory["repo_common_dir"] != str(common):
        fail("recovery-repository-mismatch")
    positive_int(
        inventory["frozen_at_unix_ns"], "invalid-recovery-inventory",
    )
    positive_int(inventory["cutoff_unix_ns"], "invalid-recovery-inventory")
    valid_uuid(
        inventory["approval_source_thread_id"], "invalid-recovery-inventory",
    )
    source_record = bounded_text(
        inventory["source_record"], "invalid-recovery-inventory", 4096,
    )
    if pathlib.Path(source_record).is_absolute() or ".." in pathlib.Path(
        source_record
    ).parts:
        fail("invalid-recovery-inventory")
    proposals = inventory["proposals"]
    keep = inventory["keep"]
    if (
        not isinstance(proposals, list)
        or not proposals
        or len(proposals) > DISCOVERY_ENTRY_LIMIT
        or not isinstance(keep, list)
        or not keep
        or len(keep) > DISCOVERY_ENTRY_LIMIT * 2
    ):
        fail("invalid-recovery-inventory")
    for item in proposals:
        validate_recovery_candidate(item)
    for item in keep:
        validate_keep_item(item)
    candidate_ids = [item["candidate_id"] for item in proposals]
    candidate_paths = [item["worktree_path"] for item in proposals]
    candidate_branches = [
        item["expected_branch"] for item in proposals
        if item["expected_branch"] is not None
    ]
    keep_ids = [item["item_id"] for item in keep]
    if (
        len(set(candidate_ids)) != len(candidate_ids)
        or len(set(candidate_paths)) != len(candidate_paths)
        or len(set(candidate_branches)) != len(candidate_branches)
        or len(set(keep_ids)) != len(keep_ids)
    ):
        fail("invalid-recovery-inventory")
    remote_data = run_git_bytes([
        "-C", str(repo), "show",
        "refs/remotes/origin/main:" + str(RECOVERY_INVENTORY_RELATIVE),
    ], reason="recovery-inventory-not-landed").stdout
    if remote_data != data:
        fail("recovery-inventory-not-landed")
    inventory_blob_oid = git(
        repo, "rev-parse",
        "refs/remotes/origin/main:" + str(RECOVERY_INVENTORY_RELATIVE),
    )
    return inventory, inventory_path, inventory_blob_oid


def validate_recovery_bundle(repo, recovery):
    required = {
        "bundle_path", "independent_bundle_path", "bundle_sha256",
        "extraction_receipt",
    }
    if not isinstance(recovery, dict) or set(recovery) != required:
        fail("invalid-recovery-inventory")
    expected = recovery["bundle_sha256"]
    if not isinstance(expected, str) or HEX64.fullmatch(expected) is None:
        fail("invalid-recovery-inventory")
    paths = []
    for key in ("bundle_path", "independent_bundle_path"):
        path = pathlib.Path(
            bounded_text(
                recovery[key], "invalid-recovery-inventory", 4096,
            )
        )
        if not path.is_absolute():
            fail("invalid-recovery-inventory")
        if TEST_MODE:
            try:
                path.resolve(strict=True).relative_to(TEST_ROOT)
            except (OSError, ValueError):
                fail("unsafe-test-mode")
        if safe_file_sha256(path, "invalid-recovery-bundle") != expected:
            fail("invalid-recovery-bundle")
        run_git([
            "-C", str(repo), "bundle", "verify", str(path),
        ], reason="invalid-recovery-bundle")
        paths.append(path)
    receipt = recovery["extraction_receipt"]
    receipt_required = {
        "record_path", "record_blob_oid", "tag", "peeled_commit",
        "recovered_blob", "status",
    }
    if not isinstance(receipt, dict) or set(receipt) != receipt_required:
        fail("invalid-recovery-inventory")
    if receipt["status"] != "PASS":
        fail("invalid-recovery-extraction-receipt")
    record_path = bounded_text(
        receipt["record_path"], "invalid-recovery-inventory", 4096,
    )
    if pathlib.Path(record_path).is_absolute() or ".." in pathlib.Path(
        record_path
    ).parts:
        fail("invalid-recovery-inventory")
    for key in ("record_blob_oid", "peeled_commit", "recovered_blob"):
        oid = receipt[key]
        if not isinstance(oid, str) or not (
            HEX40.fullmatch(oid) or HEX64.fullmatch(oid)
        ):
            fail("invalid-recovery-inventory")
    landed_blob = git(
        repo, "rev-parse", "refs/remotes/origin/main:" + record_path,
    )
    if landed_blob != receipt["record_blob_oid"]:
        fail("invalid-recovery-extraction-receipt")
    record_data = run_git_bytes([
        "-C", str(repo), "show",
        "refs/remotes/origin/main:" + record_path,
    ], reason="invalid-recovery-extraction-receipt").stdout
    for value in (
        receipt["tag"], receipt["peeled_commit"], receipt["recovered_blob"],
        receipt["status"],
    ):
        if value.encode("utf-8") not in record_data:
            fail("invalid-recovery-extraction-receipt")
    return {
        "bundle_path": str(paths[0]),
        "independent_bundle_path": str(paths[1]),
        "bundle_sha256": expected,
        "extraction_receipt": receipt,
    }


def recovery_tag_catalog(repo, bundle, candidates):
    refs = sorted({
        "refs/tags/" + candidate["archive_tag"]
        for candidate in candidates
    })
    local = {}
    local_lines = run_git([
        "-C", str(repo), "for-each-ref",
        "--format=%(refname)%00%(objectname)%00%(*objectname)%00%(objecttype)",
        *refs,
    ], reason="recovery-tag-readback-unavailable").stdout.splitlines()
    for line in local_lines:
        fields = line.split("\0")
        if len(fields) != 4 or fields[0] not in refs:
            fail("recovery-tag-readback-unavailable")
        local[fields[0]] = {
            "object": fields[1],
            "peeled_commit": fields[2] or None,
            "object_type": fields[3],
        }

    remote = {}
    remote_lines = run_git([
        "-C", str(repo), "ls-remote", "origin",
        *[value for ref in refs for value in (ref, ref + "^{}")],
    ], reason="recovery-tag-readback-unavailable").stdout.splitlines()
    for line in remote_lines:
        try:
            oid, name = line.split("\t", 1)
        except ValueError:
            fail("recovery-tag-readback-unavailable")
        if name not in refs and not (
            name.endswith("^{}") and name[:-3] in refs
        ):
            fail("recovery-tag-readback-unavailable")
        remote[name] = oid

    bundled = {}
    bundle_lines = run_git([
        "-C", str(repo), "bundle", "list-heads",
        bundle["bundle_path"], *refs,
    ], reason="invalid-recovery-bundle").stdout.splitlines()
    for line in bundle_lines:
        try:
            oid, name = line.split(" ", 1)
        except ValueError:
            fail("invalid-recovery-bundle")
        if name not in refs:
            fail("invalid-recovery-bundle")
        bundled[name] = oid
    return {"local": local, "remote": remote, "bundle": bundled}


def recovery_tag_evidence(catalog, candidate):
    tag = candidate["archive_tag"]
    ref = "refs/tags/" + tag
    evidence = {
        "tag": tag,
        "expected_object": candidate["archive_tag_object"],
        "expected_peeled_commit": candidate["archive_peeled_commit"],
        "local_object": None,
        "local_peeled_commit": None,
        "remote_object": None,
        "remote_peeled_commit": None,
        "bundle_object": None,
        "valid": False,
    }
    try:
        local = catalog["local"].get(ref, {})
        evidence["local_object"] = local.get("object")
        evidence["local_peeled_commit"] = local.get("peeled_commit")
        evidence["remote_object"] = catalog["remote"].get(ref)
        evidence["remote_peeled_commit"] = catalog["remote"].get(ref + "^{}")
        evidence["bundle_object"] = catalog["bundle"].get(ref)
        evidence["valid"] = all((
            local.get("object_type") == "tag",
            evidence["local_object"] == candidate["archive_tag_object"],
            evidence["local_peeled_commit"]
            == candidate["archive_peeled_commit"],
            evidence["remote_object"] == candidate["archive_tag_object"],
            evidence["remote_peeled_commit"]
            == candidate["archive_peeled_commit"],
            evidence["bundle_object"] == candidate["archive_tag_object"],
        ))
    except (LeaseError, ValueError):
        evidence["valid"] = False
    return evidence


def valid_candidate_owner(candidate):
    if candidate.get("owner_status") == "unresolved":
        return False
    try:
        valid_provider_owner(
            candidate.get("owner"), candidate.get("owner_provider"),
        )
    except LeaseError:
        return False
    return True


def candidate_content_evidence(info):
    target = pathlib.Path(info["worktree_path"])
    evidence = {
        "index_form": "unknown",
        "index_normal": False,
        "sparse": True,
        "staged_clean": False,
        "unstaged_clean": False,
        "untracked_clean": False,
        "ignored_clean": False,
        "git_operation_free": False,
        "raw_content_clean": False,
    }
    try:
        flags = run_git([
            "-C", str(target), "ls-files", "-v",
        ], reason="worktree-index-unavailable").stdout.splitlines()
        evidence["index_normal"] = all(
            line and line[0] == "H" for line in flags
        )
        evidence["index_form"] = (
            "stage-zero-normal" if evidence["index_normal"]
            else "non-normal"
        )
        sparse = run_git([
            "-C", str(target), "config", "--bool", "core.sparseCheckout",
        ], allowed=(0, 1))
        evidence["sparse"] = (
            sparse.returncode == 0 and sparse.stdout.strip() == "true"
        )
        evidence["staged_clean"] = run_git([
            "-C", str(target), "diff", "--cached", "--quiet", "HEAD", "--",
        ], allowed=(0, 1)).returncode == 0
        evidence["unstaged_clean"] = run_git([
            "-C", str(target), "diff-files", "--quiet", "--",
        ], allowed=(0, 1)).returncode == 0
        evidence["untracked_clean"] = not run_git_bytes([
            "-C", str(target), "ls-files", "--others",
            "--exclude-standard", "-z",
        ], reason="worktree-untracked-check-unavailable").stdout
        evidence["ignored_clean"] = not run_git_bytes([
            "-C", str(target), "ls-files", "--others", "--ignored",
            "--exclude-standard", "-z",
        ], reason="worktree-untracked-check-unavailable").stdout
        evidence["git_operation_free"] = not in_progress(info)
        if all((
            evidence["index_normal"], not evidence["sparse"],
            evidence["staged_clean"], evidence["unstaged_clean"],
            evidence["untracked_clean"], evidence["ignored_clean"],
            evidence["git_operation_free"],
        )):
            verify_raw_worktree(target)
            evidence["raw_content_clean"] = True
    except LeaseError:
        pass
    if not evidence["raw_content_clean"] and evidence["unstaged_clean"]:
        evidence["unstaged_clean"] = False
    return evidence


def evaluate_recovery_candidate(
    repo, common, origin_main, tag_catalog, processes, candidate,
):
    evidence = {
        "path_safe": False,
        "binding_matches": False,
        "head_contained": False,
        "lease_valid": False,
        "owner_resolved": valid_candidate_owner(candidate),
        "writer_lock_free": False,
        "process_free": False,
        "index_normal": False,
        "sparse": True,
        "staged_clean": False,
        "unstaged_clean": False,
        "untracked_clean": False,
        "ignored_clean": False,
        "git_operation_free": False,
        "recovery_valid": False,
    }
    result = {
        "candidate_id": candidate["candidate_id"],
        "worktree_path": candidate["worktree_path"],
        "lease_id": candidate["lease_id"],
        "proposal": candidate,
        "origin_main": origin_main,
        "verified_at_unix_ns": time.time_ns(),
        "evidence": evidence,
        "binding": None,
        "reasons": [],
    }
    try:
        target = canonical_existing(
            pathlib.Path(candidate["worktree_path"]),
            "unsafe-worktree",
        )
        target_st = target.lstat()
        if (
            not stat.S_ISDIR(target_st.st_mode)
            or stat.S_ISLNK(target_st.st_mode)
            or target_st.st_uid != os.getuid()
        ):
            raise LeaseError("unsafe-worktree")
        info = git_info(target)
        if info["repo_common_dir"] != str(common):
            raise LeaseError("recovery-repository-mismatch")
        evidence["path_safe"] = True
        evidence["binding_matches"] = (
            info["branch"] == candidate["expected_branch"]
            and info["head"] == candidate["expected_head"]
        )
        contained = run_git([
            "--git-dir", str(common), "merge-base", "--is-ancestor",
            info["head"], origin_main,
        ], allowed=(0, 1))
        evidence["head_contained"] = contained.returncode == 0
        owner_dir, state_path = state_location(info, create=False)
        state_summary = None
        if candidate["lease_kind"] == "existing":
            if not (owner_dir.exists() and state_path.exists()):
                evidence["lease_valid"] = False
            else:
                state = safe_read(state_path)
                evidence["lease_valid"] = all((
                    state["lease_id"] == candidate["lease_id"],
                    state["generation"] == candidate["generation"],
                    state["owner"] == candidate["owner"],
                    state.get("owner_provider", "unknown")
                    == candidate["owner_provider"],
                    state["state"] == "active",
                    stable_binding_matches(state, info),
                ))
                state_summary = {
                    "state_file": str(state_path),
                    "lease_id": state["lease_id"],
                    "generation": state["generation"],
                    "state": state["state"],
                    "owner": state["owner"],
                    "owner_provider": state.get("owner_provider", "unknown"),
                    "state_sha256": safe_file_sha256(
                        state_path, "unsafe-lease-state",
                    ),
                }
        else:
            evidence["lease_valid"] = not (
                state_path.exists() or state_path.is_symlink()
            )
            state_summary = {
                "state_file": str(state_path),
                "lease_id": candidate["lease_id"],
                "generation": None,
                "state": "legacy-no-lease",
                "owner": candidate["owner"],
                "owner_provider": candidate["owner_provider"],
                "state_sha256": None,
            }
        writer = read_only_writer_evidence(candidate["owner"])
        process_result = process_evidence(
            processes, candidate["worktree_path"], candidate["owner"],
        )
        evidence["writer_lock_free"] = writer["free"]
        evidence["process_free"] = process_result["free"]
        evidence.update(candidate_content_evidence(info))
        tag = recovery_tag_evidence(tag_catalog, candidate)
        evidence["recovery_valid"] = tag["valid"]
        result["binding"] = {
            **info,
            "worktree_device": target_st.st_dev,
            "worktree_inode": target_st.st_ino,
            "origin_main": origin_main,
            "lease": state_summary,
            "writer_lock": writer,
            "process": process_result,
            "tag": tag,
        }
    except LeaseError:
        pass
    result["reasons"] = recovery_refusal_reasons(candidate, evidence)
    result["eligible"] = not result["reasons"]
    return result


def recovery_selector_matches(ref, selectors):
    for selector in selectors:
        if selector.endswith("*"):
            if ref.startswith(selector[:-1]):
                return True
        elif selector.endswith("/"):
            if ref.startswith(selector):
                return True
        elif ref == selector:
            return True
    return False


def recovery_snapshot_payload(rows):
    if len(rows) > DISCOVERY_ENTRY_LIMIT:
        fail("recovery-surface-limit")
    payload = b"".join(row + b"\n" for row in rows)
    return len(rows), hashlib.sha256(payload).hexdigest()


def recovery_file_tree_snapshot(path_value):
    root = canonical_existing(
        pathlib.Path(path_value), "unsafe-recovery-surface",
    )
    try:
        root_st = root.lstat()
    except OSError:
        fail("unsafe-recovery-surface")
    if (
        not stat.S_ISDIR(root_st.st_mode)
        or stat.S_ISLNK(root_st.st_mode)
        or root_st.st_uid != os.getuid()
        or stat.S_IMODE(root_st.st_mode) & 0o022
    ):
        fail("unsafe-recovery-surface")
    rows = []
    try:
        children = sorted(root.rglob("*"), key=lambda item: item.as_posix())
    except OSError:
        fail("unsafe-recovery-surface")
    for child in children:
        try:
            child_st = child.lstat()
        except OSError:
            fail("unsafe-recovery-surface")
        if stat.S_ISLNK(child_st.st_mode):
            fail("unsafe-recovery-surface")
        if stat.S_ISDIR(child_st.st_mode):
            if (
                child_st.st_uid != os.getuid()
                or stat.S_IMODE(child_st.st_mode) & 0o022
            ):
                fail("unsafe-recovery-surface")
            continue
        if not stat.S_ISREG(child_st.st_mode):
            fail("unsafe-recovery-surface")
        relative = child.relative_to(root).as_posix().encode("utf-8")
        digest = safe_file_sha256(child, "unsafe-recovery-surface")
        rows.append(relative + b"\0" + digest.encode("ascii"))
    return recovery_snapshot_payload(sorted(rows))


def recovery_local_refs_snapshot(common, selectors):
    output = run_git([
        "--git-dir", str(common), "for-each-ref",
        "--format=%(refname)%00%(objectname)%00%(*objectname)",
    ], reason="recovery-surface-unavailable").stdout
    rows = []
    seen = set()
    for line in output.splitlines():
        fields = line.split("\0")
        if len(fields) != 3:
            fail("malformed-recovery-surface")
        ref, object_oid, peeled_oid = fields
        if not recovery_selector_matches(ref, selectors):
            continue
        if (
            ref in seen
            or not (HEX40.fullmatch(object_oid) or HEX64.fullmatch(object_oid))
            or (
                peeled_oid
                and not (HEX40.fullmatch(peeled_oid) or HEX64.fullmatch(peeled_oid))
            )
        ):
            fail("malformed-recovery-surface")
        seen.add(ref)
        rows.append(
            ref.encode("utf-8") + b"\0" + object_oid.encode("ascii")
            + b"\0" + peeled_oid.encode("ascii")
        )
    return recovery_snapshot_payload(sorted(rows))


def recovery_remote_tags_snapshot(repo, selectors):
    output = run_git([
        "-C", str(repo), "ls-remote", "--tags", "origin",
    ], reason="recovery-surface-unavailable").stdout
    objects = {}
    peels = {}
    for line in output.splitlines():
        try:
            oid, ref = line.split("\t", 1)
        except ValueError:
            fail("malformed-recovery-surface")
        if not (HEX40.fullmatch(oid) or HEX64.fullmatch(oid)):
            fail("malformed-recovery-surface")
        if ref.endswith("^{}"):
            base = ref[:-3]
            if base in peels:
                fail("malformed-recovery-surface")
            peels[base] = oid
        else:
            if ref in objects:
                fail("malformed-recovery-surface")
            objects[ref] = oid
    rows = []
    for ref, object_oid in objects.items():
        if not recovery_selector_matches(ref, selectors):
            continue
        rows.append(
            ref.encode("utf-8") + b"\0" + object_oid.encode("ascii")
            + b"\0" + peels.get(ref, "").encode("ascii")
        )
    return recovery_snapshot_payload(sorted(rows))


def recovery_stash_snapshot(common):
    result = run_git([
        "--git-dir", str(common), "reflog", "show",
        "--format=%gd%x00%H", "refs/stash",
    ], reason="recovery-surface-unavailable", allowed=(0, 1))
    rows = []
    for line in result.stdout.splitlines():
        try:
            name, oid = line.split("\0", 1)
        except ValueError:
            fail("malformed-recovery-surface")
        if (
            re.fullmatch(r"stash@\{[0-9]+\}", name) is None
            or not (HEX40.fullmatch(oid) or HEX64.fullmatch(oid))
        ):
            fail("malformed-recovery-surface")
        rows.append(name.encode("utf-8") + b"\0" + oid.encode("ascii"))
    return recovery_snapshot_payload(rows)


def validate_recovery_surfaces(repo, common, inventory):
    snapshots = []
    for item in inventory["keep"]:
        if item["kind"] != "recovery-surface":
            continue
        kind = item["snapshot_kind"]
        if kind == "file-tree":
            count, digest = recovery_file_tree_snapshot(item["path"])
        elif kind == "local-refs":
            count, digest = recovery_local_refs_snapshot(
                common, item["selectors"],
            )
        elif kind == "remote-tags":
            count, digest = recovery_remote_tags_snapshot(
                repo, item["selectors"],
            )
        else:
            count, digest = recovery_stash_snapshot(common)
        if count != item["item_count"] or digest != item["snapshot_sha256"]:
            fail("recovery-surface-drift", item["item_id"])
        snapshots.append({
            "item_id": item["item_id"],
            "snapshot_kind": kind,
            "selectors": item["selectors"],
            "item_count": count,
            "snapshot_sha256": digest,
            **({"path": item["path"]} if "path" in item else {}),
            **({"ref": item["ref"]} if "ref" in item else {}),
        })
    return sorted(snapshots, key=lambda item: item["item_id"])


def full_branch_ref(value):
    if value is None or value.startswith("refs/"):
        return value
    return "refs/heads/" + value


def complete_recovery_keep_list(
    inventory, worktrees, local_branches, provider_heads, evaluations,
):
    eligible_paths = {
        item["worktree_path"] for item in evaluations if item["eligible"]
    }
    evaluation_by_path = {
        item["worktree_path"]: item for item in evaluations
    }
    frozen_worktrees = {
        item.get("path"): item for item in inventory["keep"]
        if item["kind"] == "worktree" and item.get("path")
    }
    frozen_provider = {
        item.get("ref"): item for item in inventory["keep"]
        if item["kind"] == "provider-ref" and item.get("ref")
    }
    frozen_branches = {
        full_branch_ref(item.get("ref")): item for item in inventory["keep"]
        if item["kind"] == "branch" and item.get("ref")
    }
    keep = []
    seen_worktrees = set()
    represented_refusals = set()
    for item in worktrees:
        path = item["worktree_path"]
        seen_worktrees.add(path)
        current_ref = full_branch_ref(item.get("branch"))
        if path in eligible_paths:
            continue
        if path in evaluation_by_path:
            evaluation = evaluation_by_path[path]
            represented_refusals.add(evaluation["candidate_id"])
            keep.append({
                "item_id": "refused:" + evaluation["candidate_id"],
                "kind": "worktree",
                "path": path,
                "ref": current_ref,
                "head": item["head"],
                "owner": evaluation["proposal"]["owner"],
                "reasons": evaluation["reasons"],
                "revisit_trigger": "clear every refusal and run a new Prepare",
            })
            continue
        frozen = frozen_worktrees.get(path)
        if frozen is None:
            keep.append({
                "item_id": "unlisted-worktree:" + hashlib.sha256(
                    path.encode("utf-8")
                ).hexdigest()[:16],
                "kind": "worktree",
                "path": path,
                "ref": current_ref,
                "head": item["head"],
                "owner": "unknown-live-owner",
                "reasons": ["unlisted-live-item", "post-cutoff"],
                "revisit_trigger": "freeze and independently review a later inventory",
            })
        else:
            reasons = [frozen["reason"]]
            if (
                "expected_head" in frozen
                and frozen["expected_head"] != item["head"]
            ):
                reasons.append("frozen-keep-drift")
            if full_branch_ref(frozen.get("ref")) != current_ref:
                reasons.append("frozen-keep-drift")
            keep.append({
                "item_id": frozen["item_id"],
                "kind": "worktree",
                "path": path,
                "ref": current_ref,
                "head": item["head"],
                "owner": frozen["owner"],
                "reasons": reasons,
                "revisit_trigger": frozen["revisit_trigger"],
            })
    for evaluation in evaluations:
        if (
            evaluation["eligible"]
            or evaluation["candidate_id"] in represented_refusals
        ):
            continue
        keep.append({
            "item_id": "refused:" + evaluation["candidate_id"],
            "kind": "worktree",
            "path": evaluation["worktree_path"],
            "ref": full_branch_ref(
                evaluation["proposal"].get("expected_branch"),
            ),
            "head": evaluation["proposal"].get("expected_head"),
            "owner": evaluation["proposal"]["owner"],
            "reasons": evaluation["reasons"],
            "revisit_trigger": "clear every refusal and run a new Prepare",
        })
    eligible_branches = {
        "refs/heads/" + item["proposal"]["expected_branch"]:
        item["proposal"]["expected_head"]
        for item in evaluations
        if item["eligible"] and item["proposal"]["expected_branch"] is not None
    }
    refused_by_branch = {
        "refs/heads/" + item["proposal"]["expected_branch"]: item
        for item in evaluations
        if not item["eligible"] and item["proposal"]["expected_branch"] is not None
    }
    for path, frozen in frozen_worktrees.items():
        if path in seen_worktrees:
            continue
        keep.append({
            "item_id": frozen["item_id"],
            "kind": "worktree",
            "path": path,
            "ref": full_branch_ref(frozen.get("ref")),
            "head": frozen.get("expected_head"),
            "owner": frozen["owner"],
            "reasons": [frozen["reason"], "frozen-item-missing"],
            "revisit_trigger": frozen["revisit_trigger"],
        })
    seen_branches = set()
    for item in local_branches:
        seen_branches.add(item["ref"])
        if eligible_branches.get(item["ref"]) == item["head"]:
            continue
        evaluation = refused_by_branch.get(item["ref"])
        if evaluation is not None:
            keep.append({
                "item_id": "refused-branch:" + evaluation["candidate_id"],
                "kind": "branch",
                "ref": item["ref"],
                "head": item["head"],
                "owner": evaluation["proposal"]["owner"],
                "reasons": evaluation["reasons"],
                "revisit_trigger": "clear every refusal and run a new Prepare",
            })
            continue
        frozen = frozen_branches.get(item["ref"])
        if frozen is None:
            keep.append({
                "item_id": "unlisted-branch:" + hashlib.sha256(
                    item["ref"].encode("utf-8")
                ).hexdigest()[:16],
                "kind": "branch",
                "ref": item["ref"],
                "head": item["head"],
                "owner": "unknown-live-owner",
                "reasons": ["unlisted-live-item", "post-cutoff"],
                "revisit_trigger": "freeze and independently review a later inventory",
            })
        else:
            reasons = [frozen["reason"]]
            if (
                "expected_head" in frozen
                and frozen["expected_head"] != item["head"]
            ):
                reasons.append("frozen-keep-drift")
            keep.append({
                "item_id": frozen["item_id"],
                "kind": "branch",
                "ref": item["ref"],
                "head": item["head"],
                "owner": frozen["owner"],
                "reasons": reasons,
                "revisit_trigger": frozen["revisit_trigger"],
            })
    for ref, frozen in frozen_branches.items():
        if ref in seen_branches:
            continue
        keep.append({
            "item_id": frozen["item_id"],
            "kind": "branch",
            "ref": ref,
            "head": frozen.get("expected_head"),
            "owner": frozen["owner"],
            "reasons": [frozen["reason"], "frozen-item-missing"],
            "revisit_trigger": frozen["revisit_trigger"],
        })
    seen_provider = set()
    for item in provider_heads:
        seen_provider.add(item["ref"])
        frozen = frozen_provider.get(item["ref"])
        if frozen is None:
            keep.append({
                "item_id": "unlisted-provider-ref:" + hashlib.sha256(
                    item["ref"].encode("utf-8")
                ).hexdigest()[:16],
                "kind": "provider-ref",
                "ref": item["ref"],
                "head": item["head"],
                "owner": "unknown-live-owner",
                "reasons": ["unlisted-live-item", "post-cutoff"],
                "revisit_trigger": "freeze and independently review a later inventory",
            })
        else:
            reasons = [frozen["reason"]]
            if (
                "expected_head" in frozen
                and frozen["expected_head"] != item["head"]
            ):
                reasons.append("frozen-keep-drift")
            keep.append({
                "item_id": frozen["item_id"],
                "kind": "provider-ref",
                "ref": item["ref"],
                "head": item["head"],
                "owner": frozen["owner"],
                "reasons": reasons,
                "revisit_trigger": frozen["revisit_trigger"],
            })
    for ref, frozen in frozen_provider.items():
        if ref in seen_provider:
            continue
        keep.append({
            "item_id": frozen["item_id"],
            "kind": "provider-ref",
            "ref": ref,
            "head": frozen.get("expected_head"),
            "owner": frozen["owner"],
            "reasons": [frozen["reason"], "frozen-item-missing"],
            "revisit_trigger": frozen["revisit_trigger"],
        })
    for item in inventory["keep"]:
        if item["kind"] not in ("worktree", "branch", "provider-ref"):
            keep.append({
                "item_id": item["item_id"],
                "kind": item["kind"],
                "owner": item["owner"],
                "reasons": [item["reason"]],
                "revisit_trigger": item["revisit_trigger"],
                **({"path": item["path"]} if "path" in item else {}),
                **({"ref": item["ref"]} if "ref" in item else {}),
                **({
                    "snapshot_sha256": item["snapshot_sha256"],
                    "item_count": item["item_count"],
                    "snapshot_kind": item["snapshot_kind"],
                    "selectors": item["selectors"],
                } if "snapshot_sha256" in item else {}),
            })
    return sorted(
        keep,
        key=lambda item: (
            item["kind"], item.get("path", ""), item.get("ref", ""),
            item["item_id"],
        ),
    )


def verify_recovery_source_landed(repo):
    if TEST_MODE:
        return
    source = canonical_existing(
        pathlib.Path(__file__), "recovery-source-not-landed",
    )
    live = safe_regular_bytes(source, "recovery-source-not-landed")
    landed = run_git_bytes([
        "-C", str(repo), "show",
        "refs/remotes/origin/main:scripts/worktree-owner-lease.py",
    ], reason="recovery-source-not-landed").stdout
    if live != landed:
        fail("recovery-source-not-landed")


def recovery_prepare(args):
    repo = canonical_existing(pathlib.Path(args.repo), "unsafe-repo-anchor")
    common = repo_common_from_anchor(repo)
    reject_git_grafts(common)
    verify_recovery_source_landed(repo)
    inventory, inventory_path, inventory_blob_oid = load_recovery_inventory(
        repo, common,
    )
    origin_main = git(repo, "rev-parse", "refs/remotes/origin/main")
    if not (HEX40.fullmatch(origin_main) or HEX64.fullmatch(origin_main)):
        fail("origin-main-unavailable")
    bundle = validate_recovery_bundle(repo, inventory["recovery"])
    recovery_surfaces = validate_recovery_surfaces(repo, common, inventory)
    tag_catalog = recovery_tag_catalog(repo, bundle, inventory["proposals"])
    processes = process_snapshot()
    evaluations = [
        evaluate_recovery_candidate(
            repo, common, origin_main, tag_catalog, processes, candidate,
        )
        for candidate in inventory["proposals"]
    ]
    worktrees = worktree_inventory(common)
    live_paths = {item["worktree_path"] for item in worktrees}
    for evaluation in evaluations:
        if evaluation["worktree_path"] not in live_paths:
            if "drifted-binding" not in evaluation["reasons"]:
                evaluation["reasons"].append("drifted-binding")
            evaluation["eligible"] = False
    provider_heads = provider_head_inventory(repo)
    provider_main = next(
        (
            item["head"] for item in provider_heads
            if item["ref"] == "refs/heads/main"
        ),
        None,
    )
    if provider_main != origin_main:
        fail("origin-main-provider-drift")
    local_branches = local_branch_inventory(common)
    keep = complete_recovery_keep_list(
        inventory, worktrees, local_branches, provider_heads, evaluations,
    )
    unlisted = [
        item["item_id"] for item in keep
        if "unlisted-live-item" in item.get("reasons", [])
    ]
    if unlisted:
        fail("unlisted-recovery-inventory", ",".join(unlisted))
    prepared_at = time.time_ns()
    payload = {
        "contract": RECOVERY_MANIFEST_CONTRACT,
        "schema_version": 1,
        "prepared_at_unix_ns": prepared_at,
        "repository_path": str(repo),
        "repo_common_dir": str(common),
        "inventory_path": str(inventory_path),
        "inventory_blob_oid": inventory_blob_oid,
        "inventory_frozen_at_unix_ns": inventory["frozen_at_unix_ns"],
        "approval_source_thread_id": inventory["approval_source_thread_id"],
        "origin_main": origin_main,
        "recovery": bundle,
        "recovery_surfaces": recovery_surfaces,
        "worktree_inventory": worktrees,
        "local_branch_inventory": local_branches,
        "provider_head_inventory": provider_heads,
        "evaluations": evaluations,
        "candidates": [{
            "candidate_id": item["candidate_id"],
            "worktree_path": item["worktree_path"],
            "lease_id": item["lease_id"],
            "binding": item["binding"],
        } for item in evaluations if item["eligible"]],
        "refused": [{
            "candidate_id": item["candidate_id"],
            "worktree_path": item["worktree_path"],
            "lease_id": item["lease_id"],
            "reasons": item["reasons"],
        } for item in evaluations if not item["eligible"]],
        "keep": keep,
    }
    manifest_sha256 = hashlib.sha256(
        canonical_json_bytes(payload)
    ).hexdigest()
    envelope = {
        "manifest": payload,
        "manifest_sha256": manifest_sha256,
    }
    manifests = recovery_subdir(common, "manifests", create=True)
    receipts = recovery_subdir(common, "receipts", create=True)
    manifest_path = manifests / (manifest_sha256 + ".json")
    audit_path = receipts / ("prepare-" + manifest_sha256 + ".json")
    atomic_write(manifest_path, envelope)
    audit = {
        "contract": RECOVERY_RECEIPT_CONTRACT,
        "operation": "prepare",
        "status": "prepared",
        "prepared_at_unix_ns": prepared_at,
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha256,
        "origin_main": origin_main,
        "candidates": [{
            "candidate_id": item["candidate_id"],
            "worktree_path": item["worktree_path"],
            "lease_id": item["lease_id"],
        } for item in payload["candidates"]],
        "refused": payload["refused"],
        "keep": keep,
    }
    atomic_write(audit_path, audit)
    return {
        "contract": RECOVERY_MANIFEST_CONTRACT,
        "status": "prepared",
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha256,
        "audit_receipt": str(audit_path),
        "origin_main": origin_main,
        "candidates": audit["candidates"],
        "refused": audit["refused"],
        "keep": keep,
    }


def recovery_manifest_evaluation_projections(manifest):
    candidates = []
    refused = []
    candidate_ids = []
    candidate_paths = []
    prepared_at = manifest["prepared_at_unix_ns"]
    for evaluation in manifest["evaluations"]:
        if not isinstance(evaluation, dict) or set(evaluation) != {
            "candidate_id", "worktree_path", "lease_id", "proposal",
            "origin_main", "verified_at_unix_ns", "evidence", "binding",
            "reasons", "eligible",
        }:
            fail("invalid-recovery-manifest")
        candidate_id = bounded_text(
            evaluation["candidate_id"], "invalid-recovery-manifest", 256,
        )
        worktree_path = bounded_text(
            evaluation["worktree_path"], "invalid-recovery-manifest", 4096,
        )
        lease_id = bounded_text(
            evaluation["lease_id"], "invalid-recovery-manifest", 512,
        )
        proposal = evaluation["proposal"]
        reasons = evaluation["reasons"]
        eligible = evaluation["eligible"]
        verified_at = positive_int(
            evaluation["verified_at_unix_ns"], "invalid-recovery-manifest",
        )
        if any((
            not isinstance(proposal, dict),
            not isinstance(evaluation["evidence"], dict),
            not isinstance(reasons, list),
            not isinstance(eligible, bool),
            evaluation["origin_main"] != manifest["origin_main"],
            verified_at > prepared_at,
        )):
            fail("invalid-recovery-manifest")
        if any(
            not isinstance(reason, str) or not reason or len(reason) > 256
            for reason in reasons
        ) or len(set(reasons)) != len(reasons):
            fail("invalid-recovery-manifest")
        if eligible != (not reasons):
            fail("invalid-recovery-manifest")
        if (
            proposal.get("candidate_id") != candidate_id
            or proposal.get("worktree_path") != worktree_path
            or proposal.get("lease_id") != lease_id
        ):
            fail("invalid-recovery-manifest")
        candidate_ids.append(candidate_id)
        candidate_paths.append(worktree_path)
        if eligible:
            if not isinstance(evaluation["binding"], dict):
                fail("invalid-recovery-manifest")
            candidates.append({
                "candidate_id": candidate_id,
                "worktree_path": worktree_path,
                "lease_id": lease_id,
                "binding": evaluation["binding"],
            })
        else:
            refused.append({
                "candidate_id": candidate_id,
                "worktree_path": worktree_path,
                "lease_id": lease_id,
                "reasons": reasons,
            })
    if (
        len(set(candidate_ids)) != len(candidate_ids)
        or len(set(candidate_paths)) != len(candidate_paths)
    ):
        fail("invalid-recovery-manifest")
    return candidates, refused


def load_recovery_manifest(common, path_value):
    path = pathlib.Path(path_value)
    if not path.is_absolute():
        fail("unsafe-recovery-manifest")
    manifests = recovery_subdir(common, "manifests")
    if path.parent != manifests or path.suffix != ".json":
        fail("unsafe-recovery-manifest")
    envelope = safe_json_file(
        path, "invalid-recovery-manifest", exact_mode=0o600, canonical=True,
    )
    if (
        not isinstance(envelope, dict)
        or set(envelope) != {"manifest", "manifest_sha256"}
        or not isinstance(envelope["manifest"], dict)
    ):
        fail("invalid-recovery-manifest")
    manifest_sha256 = envelope["manifest_sha256"]
    if (
        not isinstance(manifest_sha256, str)
        or HEX64.fullmatch(manifest_sha256) is None
        or path.name != manifest_sha256 + ".json"
    ):
        fail("invalid-recovery-manifest")
    actual = hashlib.sha256(
        canonical_json_bytes(envelope["manifest"])
    ).hexdigest()
    if not hmac.compare_digest(actual, manifest_sha256):
        fail("manifest-hash-mismatch")
    manifest = envelope["manifest"]
    required = {
        "contract", "schema_version", "prepared_at_unix_ns",
        "repository_path", "repo_common_dir", "inventory_path",
        "inventory_blob_oid", "inventory_frozen_at_unix_ns",
        "approval_source_thread_id", "origin_main", "recovery",
        "recovery_surfaces", "worktree_inventory",
        "local_branch_inventory", "provider_head_inventory",
        "evaluations", "candidates", "refused", "keep",
    }
    if set(manifest) != required or (
        manifest["contract"] != RECOVERY_MANIFEST_CONTRACT
        or manifest["schema_version"] != 1
        or manifest["repo_common_dir"] != str(common)
    ):
        fail("invalid-recovery-manifest")
    positive_int(
        manifest["prepared_at_unix_ns"], "invalid-recovery-manifest",
    )
    valid_uuid(
        manifest["approval_source_thread_id"], "invalid-recovery-manifest",
    )
    if not all(isinstance(manifest[key], list) for key in (
        "recovery_surfaces", "worktree_inventory", "local_branch_inventory",
        "provider_head_inventory", "evaluations", "candidates", "refused",
        "keep",
    )):
        fail("invalid-recovery-manifest")
    derived_candidates, derived_refused = (
        recovery_manifest_evaluation_projections(manifest)
    )
    if (
        manifest["candidates"] != derived_candidates
        or manifest["refused"] != derived_refused
    ):
        fail("invalid-recovery-manifest")
    candidate_ids = []
    candidate_paths = []
    for item in manifest["candidates"]:
        if not isinstance(item, dict) or set(item) != {
            "candidate_id", "worktree_path", "lease_id", "binding",
        }:
            fail("invalid-recovery-manifest")
        bounded_text(item["candidate_id"], "invalid-recovery-manifest", 256)
        bounded_text(item["worktree_path"], "invalid-recovery-manifest", 4096)
        bounded_text(item["lease_id"], "invalid-recovery-manifest", 512)
        if not isinstance(item["binding"], dict):
            fail("invalid-recovery-manifest")
        candidate_ids.append(item["candidate_id"])
        candidate_paths.append(item["worktree_path"])
    if (
        len(set(candidate_ids)) != len(candidate_ids)
        or len(set(candidate_paths)) != len(candidate_paths)
    ):
        fail("invalid-recovery-manifest")
    return manifest, manifest_sha256, path


def approval_candidate_tuples(manifest):
    tuples = []
    for item in manifest["candidates"]:
        if not isinstance(item, dict):
            fail("invalid-recovery-manifest")
        try:
            value = {
                "candidate_id": item["candidate_id"],
                "worktree_path": item["worktree_path"],
                "lease_id": item["lease_id"],
            }
        except KeyError:
            fail("invalid-recovery-manifest")
        for key, maximum in (
            ("candidate_id", 256), ("worktree_path", 4096), ("lease_id", 512),
        ):
            bounded_text(value[key], "invalid-recovery-manifest", maximum)
        tuples.append(value)
    if len({
        (item["candidate_id"], item["worktree_path"], item["lease_id"])
        for item in tuples
    }) != len(tuples):
        fail("invalid-recovery-manifest")
    return tuples


def recovery_backup_evidence_sha256(manifest, manifest_sha256):
    archive_tags = []
    for evaluation in manifest["evaluations"]:
        proposal = evaluation["proposal"]
        archive_tags.append({
            "candidate_id": proposal["candidate_id"],
            "archive_tag": proposal["archive_tag"],
            "archive_tag_object": proposal["archive_tag_object"],
            "archive_peeled_commit": proposal["archive_peeled_commit"],
        })
    return hashlib.sha256(canonical_json_bytes({
        "manifest_sha256": manifest_sha256,
        "recovery": manifest["recovery"],
        "recovery_surfaces": manifest["recovery_surfaces"],
        "archive_tags": archive_tags,
    })).hexdigest()


def validate_recovery_authorization_context(
    repo, common, manifest, manifest_sha256,
):
    inventory, inventory_path, inventory_blob_oid = load_recovery_inventory(
        repo, common,
    )
    origin_main = git(repo, "rev-parse", "refs/remotes/origin/main")
    if any((
        manifest["repository_path"] != str(repo),
        manifest["origin_main"] != origin_main,
        manifest["inventory_path"] != str(inventory_path),
        manifest["inventory_blob_oid"] != inventory_blob_oid,
        manifest["inventory_frozen_at_unix_ns"]
        != inventory["frozen_at_unix_ns"],
        manifest["approval_source_thread_id"]
        != inventory["approval_source_thread_id"],
    )):
        fail("stale-recovery-manifest")
    bundle = validate_recovery_bundle(repo, inventory["recovery"])
    if bundle != manifest["recovery"]:
        fail("stale-recovery-manifest")
    surfaces = validate_recovery_surfaces(repo, common, inventory)
    if surfaces != manifest["recovery_surfaces"]:
        fail("recovery-surface-drift")
    if any((
        worktree_inventory(common) != manifest["worktree_inventory"],
        local_branch_inventory(common) != manifest["local_branch_inventory"],
        provider_head_inventory(repo) != manifest["provider_head_inventory"],
    )):
        fail("stale-recovery-manifest")
    proposals = inventory["proposals"]
    evaluations = manifest["evaluations"]
    if (
        len(proposals) != len(evaluations)
        or any(
            evaluation.get("proposal") != proposal
            for proposal, evaluation in zip(proposals, evaluations)
        )
    ):
        fail("stale-recovery-manifest")
    tag_catalog = recovery_tag_catalog(repo, bundle, proposals)
    if any(
        not recovery_tag_evidence(tag_catalog, proposal)["valid"]
        for proposal in proposals
    ):
        fail("invalid-recovery-tag")
    expected = approval_candidate_tuples(manifest)
    if not expected:
        fail("no-approved-recovery-candidates")
    if any(
        evaluation["proposal"].get("expected_action") != "recover-release"
        for evaluation in evaluations if evaluation["eligible"]
    ):
        fail("approval-candidate-mismatch")
    return expected, recovery_backup_evidence_sha256(
        manifest, manifest_sha256,
    )


def recovery_authorize(args):
    repo = canonical_existing(pathlib.Path(args.repo), "unsafe-repo-anchor")
    common = repo_common_from_anchor(repo)
    reject_git_grafts(common)
    verify_recovery_source_landed(repo)
    manifest, manifest_sha256, manifest_path = load_recovery_manifest(
        common, args.manifest,
    )
    expected, backup_evidence_sha256 = (
        validate_recovery_authorization_context(
            repo, common, manifest, manifest_sha256,
        )
    )
    authorized_at = time.time_ns()
    if authorized_at <= manifest["prepared_at_unix_ns"]:
        fail("authorization-before-prepare")
    source_message_id = bounded_text(
        args.source_message_id, "invalid-recovery-approval", 512,
    )
    if not source_message_id.strip():
        fail("invalid-recovery-approval")
    approval = {
        "contract": RECOVERY_AGENT_APPROVAL_CONTRACT,
        "authorizer": "cleanup-agent",
        "manifest_sha256": manifest_sha256,
        "approved_candidates": expected,
        "allowed_transition": "recovered/released",
        "authorized_at_unix_ns": authorized_at,
        "source_thread_id": manifest["approval_source_thread_id"],
        "source_message_id": source_message_id,
        "authorization_basis": "ER-933-backup-verified",
        "backup_evidence_sha256": backup_evidence_sha256,
    }
    approval_bytes = canonical_json_bytes(approval) + b"\n"
    approval_sha256 = hashlib.sha256(approval_bytes).hexdigest()
    approval_path = recovery_subdir(
        common, "approvals", create=True,
    ) / ("agent-" + manifest_sha256 + "-" + approval_sha256 + ".json")
    atomic_write(approval_path, approval)
    return {
        "contract": RECOVERY_AGENT_APPROVAL_CONTRACT,
        "status": "authorized",
        "manifest_path": str(manifest_path),
        "manifest_sha256": manifest_sha256,
        "approval_path": str(approval_path),
        "approval_sha256": approval_sha256,
        "approved_candidates": expected,
        "backup_evidence_sha256": backup_evidence_sha256,
    }


def load_recovery_approval(
    path_value, manifest_sha256, expected, prepared_at_unix_ns,
    expected_source_thread_id, expected_backup_evidence_sha256,
):
    path = pathlib.Path(path_value)
    if not path.is_absolute():
        fail("unsafe-recovery-approval")
    data = safe_regular_bytes(
        path, "invalid-recovery-approval", exact_mode=0o600,
    )
    approval = strict_json_bytes(
        data, "invalid-recovery-approval", canonical=True,
    )
    trevor_required = {
        "contract", "authorizer", "manifest_sha256",
        "approved_candidates", "allowed_transition", "approved_at",
        "source_thread_id", "source_message_id",
    }
    agent_required = {
        "contract", "authorizer", "manifest_sha256",
        "approved_candidates", "allowed_transition",
        "authorized_at_unix_ns", "source_thread_id", "source_message_id",
        "authorization_basis", "backup_evidence_sha256",
    }
    if not isinstance(approval, dict):
        fail("invalid-recovery-approval")
    contract = approval.get("contract")
    if contract == RECOVERY_APPROVAL_CONTRACT:
        if set(approval) != trevor_required:
            fail("invalid-recovery-approval")
    elif contract == RECOVERY_AGENT_APPROVAL_CONTRACT:
        if set(approval) != agent_required:
            fail("invalid-recovery-approval")
    else:
        fail("invalid-recovery-approval")
    if contract == RECOVERY_APPROVAL_CONTRACT and (
        approval["authorizer"] != "Trevor Gillette"
    ):
        fail("approval-authorizer-mismatch")
    if contract == RECOVERY_AGENT_APPROVAL_CONTRACT and (
        approval["authorizer"] != "cleanup-agent"
        or approval["authorization_basis"]
        != "ER-933-backup-verified"
    ):
        fail("approval-authorizer-mismatch")
    if approval["manifest_sha256"] != manifest_sha256:
        fail("approval-manifest-mismatch")
    if approval["allowed_transition"] != "recovered/released":
        fail("approval-transition-mismatch")
    if approval["approved_candidates"] != expected:
        fail("approval-candidate-mismatch")
    if contract == RECOVERY_APPROVAL_CONTRACT:
        approved_at = bounded_text(
            approval["approved_at"], "invalid-recovery-approval", 64,
        )
        if re.fullmatch(
            r"20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",
            approved_at,
        ) is None:
            fail("invalid-recovery-approval")
        try:
            approved = datetime.datetime.strptime(
                approved_at, "%Y-%m-%dT%H:%M:%SZ",
            ).replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            fail("invalid-recovery-approval")
        approved_ns = int(approved.timestamp()) * 1_000_000_000
    else:
        approved_ns = positive_int(
            approval["authorized_at_unix_ns"],
            "invalid-recovery-approval",
        )
        if approved_ns > time.time_ns():
            fail("invalid-recovery-approval")
        evidence = approval["backup_evidence_sha256"]
        if (
            not isinstance(evidence, str)
            or HEX64.fullmatch(evidence) is None
            or not hmac.compare_digest(
                evidence, expected_backup_evidence_sha256,
            )
        ):
            fail("approval-backup-evidence-mismatch")
    if approved_ns <= prepared_at_unix_ns:
        fail("approval-before-prepare")
    source_thread_id = valid_uuid(
        approval["source_thread_id"], "invalid-recovery-approval",
    )
    if source_thread_id != expected_source_thread_id:
        fail("approval-source-thread-mismatch")
    source_message_id = bounded_text(
        approval["source_message_id"], "invalid-recovery-approval", 512,
    )
    if not source_message_id.strip():
        fail("invalid-recovery-approval")
    return approval, hashlib.sha256(data).hexdigest(), path


def recovery_binding_fingerprint(binding):
    if not isinstance(binding, dict):
        return None
    lease = binding.get("lease")
    tag = binding.get("tag")
    writer = binding.get("writer_lock")
    process = binding.get("process")
    if not all(isinstance(item, dict) for item in (
        lease, tag, writer, process,
    )):
        return None
    return {
        "worktree_path": binding.get("worktree_path"),
        "repo_common_dir": binding.get("repo_common_dir"),
        "branch": binding.get("branch"),
        "head": binding.get("head"),
        "worktree_git_dir": binding.get("worktree_git_dir"),
        "worktree_git_dir_device": binding.get("worktree_git_dir_device"),
        "worktree_git_dir_inode": binding.get("worktree_git_dir_inode"),
        "worktree_device": binding.get("worktree_device"),
        "worktree_inode": binding.get("worktree_inode"),
        "origin_main": binding.get("origin_main"),
        "state_file": lease.get("state_file"),
        "lease_id": lease.get("lease_id"),
        "generation": lease.get("generation"),
        "lease_owner": lease.get("owner"),
        "lease_owner_provider": lease.get("owner_provider"),
        "lease_state_sha256": lease.get("state_sha256"),
        "writer_lock_free": writer.get("free"),
        "writer_lock_path": writer.get("path"),
        "process_free": process.get("free"),
        "process_state": process.get("state"),
        "tag_object": tag.get("local_object"),
        "tag_peeled_commit": tag.get("local_peeled_commit"),
        "tag_remote_object": tag.get("remote_object"),
        "tag_remote_peeled_commit": tag.get("remote_peeled_commit"),
        "tag_bundle_object": tag.get("bundle_object"),
    }


def recovery_evaluation_fingerprint(evaluation):
    if not isinstance(evaluation, dict):
        return None
    return {
        "candidate_id": evaluation.get("candidate_id"),
        "worktree_path": evaluation.get("worktree_path"),
        "lease_id": evaluation.get("lease_id"),
        "proposal": evaluation.get("proposal"),
        "origin_main": evaluation.get("origin_main"),
        "evidence": evaluation.get("evidence"),
        "binding": recovery_binding_fingerprint(evaluation.get("binding")),
        "reasons": evaluation.get("reasons"),
        "eligible": evaluation.get("eligible"),
    }


def recovery_state_digest(state):
    payload = {
        key: value for key, value in state.items()
        if key != "recovery_released_state_sha256"
    }
    return hashlib.sha256(canonical_json_bytes(payload)).hexdigest()


def recovery_state_integrity_valid(state):
    expected = state.get("recovery_released_state_sha256")
    return (
        isinstance(expected, str)
        and HEX64.fullmatch(expected) is not None
        and hmac.compare_digest(expected, recovery_state_digest(state))
    )


def exact_recovery_replay_state(
    candidate, manifest_candidate, manifest_sha256, approval_sha256,
    evaluation,
):
    binding = evaluation.get("binding")
    if not isinstance(binding, dict):
        return False
    try:
        info = git_info(pathlib.Path(candidate["worktree_path"]))
        _owner_dir, state_path = state_location(info, create=False)
        state = safe_read(state_path)
    except LeaseError:
        return False
    common = all((
        state.get("state") == "released",
        state.get("owner") == candidate["owner"],
        state.get("owner_provider") == candidate["owner_provider"],
        state.get("recovery_candidate_id") == candidate["candidate_id"],
        state.get("recovery_manifest_sha256") == manifest_sha256,
        state.get("recovery_approval_sha256") == approval_sha256,
        recovery_state_integrity_valid(state),
        released_binding_matches(state, info),
    ))
    if candidate["lease_kind"] == "existing":
        exact = all((
            common,
            state.get("lease_id") == candidate["lease_id"],
            state.get("generation") == candidate["generation"],
            state.get("legacy_recovery_id") is None,
        ))
    else:
        exact = all((
            common,
            state.get("legacy_recovery_id") == candidate["lease_id"],
        ))
    if not exact:
        return False
    expected_binding = manifest_candidate.get("binding")
    if not isinstance(expected_binding, dict):
        return False
    expected_lease = expected_binding.get("lease")
    if not isinstance(expected_lease, dict):
        return False
    if (
        state.get("recovery_source_state_sha256")
        != expected_lease.get("state_sha256")
    ):
        return False
    binding["lease"] = {
        **expected_lease,
    }
    evaluation["evidence"]["lease_valid"] = True
    evaluation["reasons"] = recovery_refusal_reasons(
        candidate, evaluation["evidence"],
    )
    evaluation["eligible"] = not evaluation["reasons"]
    return all((
        evaluation["eligible"],
        recovery_binding_fingerprint(binding)
        == recovery_binding_fingerprint(expected_binding),
    ))


def evaluate_recovery_candidate_for_apply(
    repo, common, origin_main, tag_catalog, processes, candidate,
    manifest_candidate, manifest_sha256, approval_sha256,
):
    evaluation = evaluate_recovery_candidate(
        repo, common, origin_main, tag_catalog, processes, candidate,
    )
    if evaluation["eligible"]:
        return evaluation
    if exact_recovery_replay_state(
        candidate, manifest_candidate, manifest_sha256, approval_sha256,
        evaluation,
    ):
        return evaluation
    return evaluation


def recovery_transition_live_evidence(
    repo, common, origin_main, bundle, candidate, expected_binding, initial,
):
    current = git_info(pathlib.Path(candidate["worktree_path"]))
    try:
        target_st = pathlib.Path(candidate["worktree_path"]).lstat()
    except OSError:
        fail("recovery-candidate-drift")
    if not all((
        stable_binding_matches(initial, current),
        current["head"] == initial["head"],
        current["repo_common_dir"] == str(common),
        current["branch"] == candidate["expected_branch"],
        current["head"] == candidate["expected_head"],
        current["worktree_git_dir"]
        == expected_binding.get("worktree_git_dir"),
        current["worktree_git_dir_device"]
        == expected_binding.get("worktree_git_dir_device"),
        current["worktree_git_dir_inode"]
        == expected_binding.get("worktree_git_dir_inode"),
        target_st.st_dev == expected_binding.get("worktree_device"),
        target_st.st_ino == expected_binding.get("worktree_inode"),
        stat.S_ISDIR(target_st.st_mode),
        not stat.S_ISLNK(target_st.st_mode),
        target_st.st_uid == os.getuid(),
    )):
        fail("recovery-candidate-drift")
    live_process = process_evidence(
        process_snapshot(), candidate["worktree_path"], candidate["owner"],
    )
    if not live_process["free"]:
        fail("live-process")
    content = candidate_content_evidence(current)
    if not all((
        content["index_normal"], not content["sparse"],
        content["staged_clean"], content["unstaged_clean"],
        content["untracked_clean"], content["ignored_clean"],
        content["git_operation_free"], content["raw_content_clean"],
    )):
        fail("recovery-candidate-drift")
    contained = run_git([
        "--git-dir", str(common), "merge-base", "--is-ancestor",
        current["head"], origin_main,
    ], allowed=(0, 1))
    if contained.returncode != 0:
        fail("recovery-candidate-drift")
    locked_tag_catalog = recovery_tag_catalog(repo, bundle, [candidate])
    locked_tag = recovery_tag_evidence(locked_tag_catalog, candidate)
    if not locked_tag["valid"]:
        fail("recovery-candidate-drift")
    return current, target_st, live_process, locked_tag


def transition_recovery_candidate(
    repo, common, origin_main, bundle, candidate,
    expected_binding, manifest_sha256, approval_sha256,
):
    static_evidence = {
        "path_safe": True,
        "binding_matches": True,
        "head_contained": True,
        "lease_valid": True,
        "owner_resolved": valid_candidate_owner(candidate),
        "writer_lock_free": True,
        "process_free": True,
        "index_normal": True,
        "sparse": False,
        "staged_clean": True,
        "unstaged_clean": True,
        "untracked_clean": True,
        "ignored_clean": True,
        "git_operation_free": True,
        "recovery_valid": True,
    }
    static_reasons = recovery_refusal_reasons(candidate, static_evidence)
    if static_reasons:
        fail(static_reasons[0])
    info = git_info(pathlib.Path(candidate["worktree_path"]))
    try:
        target_st = pathlib.Path(candidate["worktree_path"]).lstat()
    except OSError:
        fail("recovery-candidate-drift")
    if not all((
        info["repo_common_dir"] == str(common),
        info["worktree_path"] == candidate["worktree_path"],
        info["branch"] == candidate["expected_branch"],
        info["head"] == candidate["expected_head"],
        info["worktree_git_dir"] == expected_binding.get("worktree_git_dir"),
        info["worktree_git_dir_device"]
        == expected_binding.get("worktree_git_dir_device"),
        info["worktree_git_dir_inode"]
        == expected_binding.get("worktree_git_dir_inode"),
        target_st.st_dev == expected_binding.get("worktree_device"),
        target_st.st_ino == expected_binding.get("worktree_inode"),
        stat.S_ISDIR(target_st.st_mode),
        not stat.S_ISLNK(target_st.st_mode),
        target_st.st_uid == os.getuid(),
    )):
        fail("recovery-candidate-drift", "manifest-binding-drift")
    owner_dir, state_path = state_location(info, create=False)
    lease_fd = None
    if candidate["lease_kind"] == "existing":
        if not owner_dir.exists():
            fail("recovery-candidate-drift")
        lease_fd = lease_lock(owner_dir)
    writer_fd = None
    try:
        try:
            writer_fd = writer_lock(candidate["owner"])
        except LeaseError as exc:
            if exc.reason == "active-writer-lock":
                fail("live-writer")
            raise
        current, target_st, live_process, locked_tag = (
            recovery_transition_live_evidence(
                repo, common, origin_main, bundle, candidate,
                expected_binding, info,
            )
        )
        expected_lease = expected_binding.get("lease") if isinstance(
            expected_binding, dict,
        ) else None
        if not isinstance(expected_lease, dict):
            fail("recovery-candidate-drift", "manifest-binding-drift")
        if lease_fd is None:
            owner_dir = private_dir(
                pathlib.Path(common) / "codex-worktree-owners",
                "unsafe-owner-directory", create=True,
            )
            _validated_owner_dir, state_path = state_location(
                info, create=False,
            )
            lease_fd = lease_lock(owner_dir)
            current, target_st, live_process, locked_tag = (
                recovery_transition_live_evidence(
                    repo, common, origin_main, bundle, candidate,
                    expected_binding, info,
                )
            )
        state = None
        replay = False
        state_exists = os.path.lexists(state_path)
        if candidate["lease_kind"] == "existing":
            try:
                state = safe_read(state_path)
            except LeaseError:
                fail("recovery-candidate-drift")
            exact_identity = all((
                state.get("lease_id") == candidate["lease_id"],
                state.get("generation") == candidate["generation"],
                state.get("owner") == candidate["owner"],
                state.get("owner_provider", "unknown")
                == candidate["owner_provider"],
                stable_binding_matches(state, current),
            ))
            replay = all((
                exact_identity,
                state.get("state") == "released",
                state.get("recovery_candidate_id")
                == candidate["candidate_id"],
                state.get("recovery_manifest_sha256") == manifest_sha256,
                state.get("recovery_approval_sha256") == approval_sha256,
                state.get("recovery_source_state_sha256")
                == expected_lease.get("state_sha256"),
                recovery_state_integrity_valid(state),
                released_binding_matches(state, current),
            ))
            if not replay and not all((
                exact_identity, state.get("state") == "active",
            )):
                fail("recovery-candidate-drift")
            state_sha256 = (
                expected_lease.get("state_sha256") if replay
                else safe_file_sha256(state_path, "unsafe-lease-state")
            )
        elif state_exists:
            try:
                state = safe_read(state_path)
            except LeaseError:
                fail("recovery-candidate-drift")
            replay = all((
                state.get("state") == "released",
                state.get("owner") == candidate["owner"],
                state.get("owner_provider") == candidate["owner_provider"],
                state.get("legacy_recovery_id") == candidate["lease_id"],
                state.get("recovery_candidate_id")
                == candidate["candidate_id"],
                state.get("recovery_manifest_sha256") == manifest_sha256,
                state.get("recovery_approval_sha256") == approval_sha256,
                state.get("recovery_source_state_sha256") is None,
                recovery_state_integrity_valid(state),
                released_binding_matches(state, current),
            ))
            if not replay:
                fail("recovery-candidate-drift")
            state_sha256 = expected_lease.get("state_sha256")
        else:
            state_sha256 = None
        actual_binding = {
            **current,
            "worktree_device": target_st.st_dev,
            "worktree_inode": target_st.st_ino,
            "origin_main": origin_main,
            "lease": {
                "state_file": str(state_path),
                "lease_id": candidate["lease_id"],
                "generation": candidate["generation"],
                "owner": candidate["owner"],
                "owner_provider": candidate["owner_provider"],
                "state_sha256": state_sha256,
            },
            "writer_lock": expected_binding.get("writer_lock"),
            "process": live_process,
            "tag": locked_tag,
        }
        if (
            recovery_binding_fingerprint(actual_binding)
            != recovery_binding_fingerprint(expected_binding)
        ):
            fail("recovery-candidate-drift", "manifest-binding-drift")
        now = time.time_ns()
        if candidate["lease_kind"] == "existing":
            if not replay:
                state.update(
                    head=current["head"],
                    state="released",
                    released_head=current["head"],
                    release_token=new_capability("r"),
                    release_reason=(
                        "Authorized owner recovery " + manifest_sha256
                    ),
                    released_at_unix_ns=now,
                    recovery_manifest_sha256=manifest_sha256,
                    recovery_candidate_id=candidate["candidate_id"],
                    recovery_approval_sha256=approval_sha256,
                    recovered_at_unix_ns=now,
                    recovery_source_state_sha256=(
                        expected_lease["state_sha256"]
                    ),
                )
        elif not replay:
            capability = new_capability("c")
            state = {
                    "contract": CONTRACT,
                    "lease_id": str(uuid.uuid4()),
                    "generation": str(uuid.uuid4()),
                    "owner": candidate["owner"],
                    "owner_provider": candidate["owner_provider"],
                    "purpose": (
                        "Authorized recovery " + candidate["candidate_id"]
                    ),
                    **current,
                    "state": "released",
                    "acquired_head": current["head"],
                    "owner_capability_sha256": owner_capability_hash(capability),
                    "acquired_at_unix_ns": now,
                    "released_head": current["head"],
                    "release_token": new_capability("r"),
                    "release_reason": (
                        "Authorized legacy owner recovery "
                        + manifest_sha256
                    ),
                    "released_at_unix_ns": now,
                    "recovery_manifest_sha256": manifest_sha256,
                    "recovery_candidate_id": candidate["candidate_id"],
                    "recovery_approval_sha256": approval_sha256,
                    "recovered_at_unix_ns": now,
                    "legacy_recovery_id": candidate["lease_id"],
                    "recovery_source_state_sha256": None,
            }
        if not replay:
            state["recovery_released_state_sha256"] = (
                recovery_state_digest(state)
            )
            atomic_write(state_path, state)
            test_crash("after-recovery-state")
        return {
            "candidate_id": candidate["candidate_id"],
            "worktree_path": candidate["worktree_path"],
            "lease_id": state["lease_id"],
            "state_file": str(state_path),
            "state": "released",
            "replay": replay,
        }
    finally:
        if writer_fd is not None:
            os.close(writer_fd)
        if lease_fd is not None:
            os.close(lease_fd)


def recovery_apply(args):
    repo = canonical_existing(pathlib.Path(args.repo), "unsafe-repo-anchor")
    common = repo_common_from_anchor(repo)
    reject_git_grafts(common)
    verify_recovery_source_landed(repo)
    manifest, manifest_sha256, _manifest_path = load_recovery_manifest(
        common, args.manifest,
    )
    expected_tuples = approval_candidate_tuples(manifest)
    approval, approval_sha256, approval_path = load_recovery_approval(
        args.approval, manifest_sha256, expected_tuples,
        manifest["prepared_at_unix_ns"],
        manifest["approval_source_thread_id"],
        recovery_backup_evidence_sha256(manifest, manifest_sha256),
    )
    if not expected_tuples:
        fail("no-approved-recovery-candidates")
    inventory, inventory_path, inventory_blob_oid = load_recovery_inventory(
        repo, common,
    )
    origin_main = git(repo, "rev-parse", "refs/remotes/origin/main")
    if any((
        manifest["repository_path"] != str(repo),
        manifest["origin_main"] != origin_main,
        manifest["inventory_path"] != str(inventory_path),
        manifest["inventory_blob_oid"] != inventory_blob_oid,
        manifest["inventory_frozen_at_unix_ns"]
        != inventory["frozen_at_unix_ns"],
        manifest["approval_source_thread_id"]
        != inventory["approval_source_thread_id"],
    )):
        fail("stale-recovery-manifest")
    bundle = validate_recovery_bundle(repo, inventory["recovery"])
    if bundle != manifest["recovery"]:
        fail("stale-recovery-manifest")
    proposals = {
        item["candidate_id"]: item for item in inventory["proposals"]
    }
    manifest_candidates = {
        item["candidate_id"]: item for item in manifest["candidates"]
    }
    manifest_evaluations = {
        item["candidate_id"]: item for item in manifest["evaluations"]
    }
    if (
        [item["candidate_id"] for item in manifest["evaluations"]]
        != [item["candidate_id"] for item in inventory["proposals"]]
        or any(
            manifest_evaluations.get(candidate_id, {}).get("proposal")
            != proposal
            for candidate_id, proposal in proposals.items()
        )
    ):
        fail("stale-recovery-manifest")
    for approved in expected_tuples:
        candidate = proposals.get(approved["candidate_id"])
        manifest_candidate = manifest_candidates.get(approved["candidate_id"])
        landed_tuple = None if candidate is None else {
            "candidate_id": candidate["candidate_id"],
            "worktree_path": candidate["worktree_path"],
            "lease_id": candidate["lease_id"],
        }
        manifest_tuple = None if manifest_candidate is None else {
            "candidate_id": manifest_candidate["candidate_id"],
            "worktree_path": manifest_candidate["worktree_path"],
            "lease_id": manifest_candidate["lease_id"],
        }
        if (
            approved != landed_tuple
            or approved != manifest_tuple
            or candidate.get("expected_action") != "recover-release"
        ):
            fail("approval-candidate-mismatch")
    transitioned = []
    blocked = []
    preserved = list(manifest["keep"])
    drifted = []
    malformed = []
    unauthorized = []
    recovery_lock_dir = recovery_root(common)
    lock_fd = lease_lock(recovery_lock_dir)
    try:
        live_worktrees = worktree_inventory(common)
        live_branches = local_branch_inventory(common)
        live_provider = provider_head_inventory(repo)
        live_surfaces = validate_recovery_surfaces(repo, common, inventory)
        provider_main = next((
            item["head"] for item in live_provider
            if item["ref"] == "refs/heads/main"
        ), None)
        if provider_main != origin_main:
            fail("origin-main-provider-drift")
        live_tag_catalog = recovery_tag_catalog(
            repo, bundle, inventory["proposals"],
        )
        live_processes = process_snapshot()
        live_evaluations = []
        for candidate in inventory["proposals"]:
            manifest_candidate = manifest_candidates.get(
                candidate["candidate_id"],
            )
            if manifest_candidate is None:
                evaluation = evaluate_recovery_candidate(
                    repo, common, origin_main, live_tag_catalog,
                    live_processes, candidate,
                )
            else:
                evaluation = evaluate_recovery_candidate_for_apply(
                    repo, common, origin_main, live_tag_catalog,
                    live_processes, candidate, manifest_candidate,
                    manifest_sha256, approval_sha256,
                )
            live_evaluations.append(evaluation)
        live_paths = {item["worktree_path"] for item in live_worktrees}
        for evaluation in live_evaluations:
            if evaluation["worktree_path"] not in live_paths:
                if "drifted-binding" not in evaluation["reasons"]:
                    evaluation["reasons"].append("drifted-binding")
                evaluation["eligible"] = False
        live_keep = complete_recovery_keep_list(
            inventory, live_worktrees, live_branches, live_provider,
            live_evaluations,
        )
        live_candidates = [{
            "candidate_id": item["candidate_id"],
            "worktree_path": item["worktree_path"],
            "lease_id": item["lease_id"],
            "binding": item["binding"],
        } for item in live_evaluations if item["eligible"]]
        live_refused = [{
            "candidate_id": item["candidate_id"],
            "worktree_path": item["worktree_path"],
            "lease_id": item["lease_id"],
            "reasons": item["reasons"],
        } for item in live_evaluations if not item["eligible"]]
        approved_ids = {item["candidate_id"] for item in expected_tuples}
        approved_proposals = {
            candidate_id: proposals[candidate_id]
            for candidate_id in approved_ids
        }
        candidate_preblocks = {}

        def worktree_scope(item):
            return [
                candidate_id
                for candidate_id, candidate in approved_proposals.items()
                if (
                    item.get("worktree_path") == candidate["worktree_path"]
                    or (
                        candidate["expected_branch"] is not None
                        and item.get("branch")
                        == candidate["expected_branch"]
                    )
                )
            ]

        def partition_worktrees(items):
            unscoped = []
            scoped = {candidate_id: [] for candidate_id in approved_ids}
            for item in items:
                owners = worktree_scope(item)
                if len(owners) > 1:
                    fail("stale-recovery-manifest")
                if owners:
                    scoped[owners[0]].append(item)
                else:
                    unscoped.append(item)
            return unscoped, scoped

        manifest_unscoped_worktrees, manifest_scoped_worktrees = (
            partition_worktrees(manifest["worktree_inventory"])
        )
        live_unscoped_worktrees, live_scoped_worktrees = (
            partition_worktrees(live_worktrees)
        )
        candidate_current_inventory = {
            candidate_id: {
                "worktrees": live_scoped_worktrees[candidate_id],
                "local_branches": [],
                "provider_heads": [],
            }
            for candidate_id in approved_ids
        }
        if live_unscoped_worktrees != manifest_unscoped_worktrees:
            fail("stale-recovery-manifest")
        for candidate_id in approved_ids:
            if (
                live_scoped_worktrees[candidate_id]
                != manifest_scoped_worktrees[candidate_id]
            ):
                candidate_preblocks[candidate_id] = (
                    "recovery-candidate-drift"
                )

        approved_refs = {
            candidate_id: full_branch_ref(candidate["expected_branch"])
            for candidate_id, candidate in approved_proposals.items()
            if candidate["expected_branch"] is not None
            and candidate["expected_branch"] != "main"
        }
        if len(set(approved_refs.values())) != len(approved_refs):
            fail("stale-recovery-manifest")

        def partition_refs(items):
            scoped = {}
            unscoped = []
            owners_by_ref = {
                ref: candidate_id
                for candidate_id, ref in approved_refs.items()
            }
            for item in items:
                candidate_id = owners_by_ref.get(item.get("ref"))
                if candidate_id is None:
                    unscoped.append(item)
                else:
                    scoped[candidate_id] = item
            return unscoped, scoped

        for inventory_key, live_items, manifest_items in (
            (
                "local_branches", live_branches,
                manifest["local_branch_inventory"],
            ),
            (
                "provider_heads", live_provider,
                manifest["provider_head_inventory"],
            ),
        ):
            live_unscoped, live_scoped = partition_refs(live_items)
            manifest_unscoped, manifest_scoped = partition_refs(
                manifest_items,
            )
            if live_unscoped != manifest_unscoped:
                fail("stale-recovery-manifest")
            for candidate_id in approved_ids:
                if candidate_id in live_scoped:
                    candidate_current_inventory[candidate_id][
                        inventory_key
                    ] = [live_scoped[candidate_id]]
                if live_scoped.get(candidate_id) != manifest_scoped.get(
                    candidate_id
                ):
                    candidate_preblocks[candidate_id] = (
                        "recovery-candidate-drift"
                    )
        manifest_nonapproved_evaluations = [
            item for item in manifest["evaluations"]
            if item.get("candidate_id") not in approved_ids
        ]
        live_nonapproved_evaluations = [
            item for item in live_evaluations
            if item.get("candidate_id") not in approved_ids
        ]
        manifest_nonapproved_refused = [
            item for item in manifest["refused"]
            if item.get("candidate_id") not in approved_ids
        ]
        live_nonapproved_refused = [
            item for item in live_refused
            if item.get("candidate_id") not in approved_ids
        ]
        approved_keep_ids = {
            prefix + candidate_id
            for candidate_id in approved_ids
            for prefix in ("refused:", "refused-branch:")
        }
        approved_scoped_paths = {
            item["worktree_path"]
            for candidate_id in approved_ids
            for item in (
                manifest_scoped_worktrees[candidate_id]
                + live_scoped_worktrees[candidate_id]
            )
        }
        approved_scoped_paths.update(
            candidate["worktree_path"]
            for candidate in approved_proposals.values()
        )
        approved_scoped_refs = set(approved_refs.values())
        approved_scoped_refs.update(
            full_branch_ref(item.get("branch"))
            for candidate_id in approved_ids
            for item in (
                manifest_scoped_worktrees[candidate_id]
                + live_scoped_worktrees[candidate_id]
            )
            if item.get("branch") is not None
            and item.get("branch") != "main"
        )

        def approved_keep_item(item):
            return any((
                item.get("item_id") in approved_keep_ids,
                item.get("kind") == "worktree"
                and item.get("path") in approved_scoped_paths,
                item.get("kind") in ("branch", "provider-ref")
                and item.get("ref") in approved_scoped_refs,
            ))

        live_nonapproved_keep = [
            item for item in live_keep
            if not approved_keep_item(item)
        ]
        manifest_nonapproved_keep = [
            item for item in manifest["keep"]
            if not approved_keep_item(item)
        ]
        if any((
            live_surfaces != manifest["recovery_surfaces"],
            [
                recovery_evaluation_fingerprint(item)
                for item in live_nonapproved_evaluations
            ]
            != [
                recovery_evaluation_fingerprint(item)
                for item in manifest_nonapproved_evaluations
            ],
            live_nonapproved_refused != manifest_nonapproved_refused,
            live_nonapproved_keep != manifest_nonapproved_keep,
        )):
            fail("stale-recovery-manifest")
        live_evaluations_by_id = {
            item["candidate_id"]: item for item in live_evaluations
        }
        for approved in expected_tuples:
            candidate_id = approved["candidate_id"]
            live_evaluation = live_evaluations_by_id.get(candidate_id)
            manifest_evaluation = manifest_evaluations.get(candidate_id)
            if live_evaluation is None or manifest_evaluation is None:
                candidate_preblocks[candidate_id] = (
                    "candidate-not-in-landed-inventory"
                )
                continue
            if not live_evaluation["eligible"]:
                candidate_preblocks[candidate_id] = (
                    live_evaluation["reasons"][0]
                    if live_evaluation["reasons"]
                    else "recovery-candidate-drift"
                )
                continue
            if (
                recovery_evaluation_fingerprint(live_evaluation)
                != recovery_evaluation_fingerprint(manifest_evaluation)
            ):
                candidate_preblocks[candidate_id] = (
                    "recovery-candidate-drift"
                )
        receipt_path = recovery_subdir(
            common, "receipts",
        ) / (
            "apply-" + manifest_sha256 + "-" + approval_sha256 + ".json"
        )
        def write_apply_receipt(status):
            atomic_write(receipt_path, {
                "contract": RECOVERY_RECEIPT_CONTRACT,
                "operation": "apply",
                "manifest_sha256": manifest_sha256,
                "approval_sha256": approval_sha256,
                "approval_path": str(approval_path),
                "approval": approval,
                "origin_main": origin_main,
                "transitioned": transitioned,
                "preserved": preserved,
                "blocked": blocked,
                "drifted": drifted,
                "malformed": malformed,
                "unauthorized": unauthorized,
                "status": status,
                "updated_at_unix_ns": time.time_ns(),
            })
        write_apply_receipt("applying")

        def candidate_block_item(approved, reason, detail=None):
            item = {
                **approved,
                "reason": reason,
                "prepared_binding": recovery_binding_fingerprint(
                    manifest_candidates.get(
                        approved["candidate_id"], {}
                    ).get("binding")
                ),
                "current_inventory": candidate_current_inventory.get(
                    approved["candidate_id"], {
                        "worktrees": [],
                        "local_branches": [],
                        "provider_heads": [],
                    },
                ),
            }
            if detail:
                item["detail"] = detail
            return item

        for approved in expected_tuples:
            candidate_id = approved["candidate_id"]
            candidate = proposals.get(candidate_id)
            manifest_candidate = manifest_candidates.get(candidate_id)
            if candidate is None or manifest_candidate is None:
                item = candidate_block_item(
                    approved, "candidate-not-in-landed-inventory",
                )
                blocked.append(item)
                unauthorized.append(item)
                preserved.append(item)
                write_apply_receipt("blocked")
                continue
            if candidate_id in candidate_preblocks:
                item = candidate_block_item(
                    approved, candidate_preblocks[candidate_id],
                )
                blocked.append(item)
                drifted.append(item)
                preserved.append(item)
                write_apply_receipt("blocked")
                continue
            try:
                transitioned.append(transition_recovery_candidate(
                    repo, common, origin_main, bundle, candidate,
                    manifest_candidate["binding"],
                    manifest_sha256, approval_sha256,
                ))
            except LeaseError as exc:
                item = candidate_block_item(
                    approved, exc.reason, exc.detail,
                )
                blocked.append(item)
                preserved.append(item)
                if exc.reason in (
                    "recovery-candidate-drift", "recovery-replay-drift",
                    "manifest-binding-drift", "live-writer", "live-process",
                ):
                    drifted.append(item)
                elif exc.reason.startswith(("invalid-", "malformed-", "unsafe-")):
                    malformed.append(item)
                elif exc.reason.startswith(("approval-", "unauthorized-")):
                    unauthorized.append(item)
            write_apply_receipt("blocked" if blocked else "applying")
        write_apply_receipt("blocked" if blocked else "applied")
    finally:
        os.close(lock_fd)
    result = {
        "contract": RECOVERY_RECEIPT_CONTRACT,
        "status": "blocked" if blocked else "applied",
        "manifest_sha256": manifest_sha256,
        "transitioned": transitioned,
        "preserved": preserved,
        "blocked": blocked,
        "drifted": drifted,
        "malformed": malformed,
        "unauthorized": unauthorized,
        "receipt": str(receipt_path),
    }
    if blocked:
        result["_exit_code"] = 3
    return result


def status_command(args):
    info = git_info(pathlib.Path(args.worktree))
    _, path = state_location(info)
    state = safe_read(path)
    if not stable_binding_matches(state, info):
        fail("binding-changed")
    if state.get("state") in ("released", "removing") and not released_binding_matches(state, info):
        fail("binding-changed")
    result = public_state(state, path)
    result["current_head"] = info["head"]
    result["head_changed_since_acquire"] = state.get("acquired_head", state.get("head")) != info["head"]
    return result


def build_parser():
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("mint-capability")
    parser = commands.add_parser("acquire")
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--purpose", required=True)
    parser.add_argument("--owner-capability", required=True)
    parser.add_argument("--owner-provider", choices=OWNER_PROVIDERS, default="unknown")
    parser = commands.add_parser("transfer")
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--owner-capability", required=True)
    parser.add_argument("--expected-lease-id", required=True)
    parser.add_argument("--new-owner", required=True)
    parser.add_argument("--new-owner-capability", required=True)
    parser.add_argument("--new-owner-provider", choices=OWNER_PROVIDERS, default="unknown")
    parser = commands.add_parser("release")
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--owner-capability", required=True)
    parser.add_argument("--reason", required=True)
    parser = commands.add_parser("remove")
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--release-token", required=True)
    parser = commands.add_parser("reconcile")
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--release-token", required=True)
    parser = commands.add_parser("cleanup-released")
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--expected-lease-id", required=True)
    parser = commands.add_parser("discover-cleanup")
    parser.add_argument("--repo", required=True)
    parser = commands.add_parser("content-status")
    parser.add_argument("--worktree", required=True)
    parser = commands.add_parser("status")
    parser.add_argument("--worktree", required=True)
    parser = commands.add_parser("recovery-prepare")
    parser.add_argument("--repo", required=True)
    parser = commands.add_parser("recovery-authorize")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--source-message-id", required=True)
    parser = commands.add_parser("recovery-apply")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--approval", required=True)
    return root


def main():
    args = build_parser().parse_args()
    try:
        validate_test_boundary(args)
        result = {
            "mint-capability": mint_capability,
            "acquire": acquire,
            "transfer": transfer,
            "release": release,
            "remove": remove,
            "reconcile": reconcile,
            "cleanup-released": cleanup_released,
            "discover-cleanup": discover_cleanup,
            "content-status": content_status,
            "status": status_command,
            "recovery-prepare": recovery_prepare,
            "recovery-authorize": recovery_authorize,
            "recovery-apply": recovery_apply,
        }[args.command](args)
    except LeaseError as exc:
        result = {"contract": CONTRACT, "status": "blocked", "reason": exc.reason}
        if exc.detail:
            result["detail"] = exc.detail
        emit(result)
        return 3
    exit_code = result.pop("_exit_code", 0)
    emit(result)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
