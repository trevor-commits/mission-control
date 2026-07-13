#!/usr/bin/env python3
"""Shared Mission Control boundary helpers.

This module owns the field-aware privacy contract for transcript-derived and
operator-facing text.  Callers select a field class; they do not copy regexes.
Sensitive fields fail closed.  Counters contain only reason totals, never the
rejected content.

Python standard library only.
"""

from __future__ import print_function

import hashlib
import json
import math
import os
import re
import stat
import subprocess
import time
from collections import Counter
from dataclasses import dataclass

NARRATIVE = "narrative"
ACTION = "action"
IDENTIFIER = "identifier"
ERROR = "error"
MODEL_INPUT = "model_input"
NOTIFICATION = "notification"

# Desktop-first where-to-look CTA for briefs / deadman / operator alerts (ER-134).
# Telegram remains optional transport only; do not point operators at Slack.
DESKTOP_GLANCE_CTA = (
    "Glance: menu-bar MC (dashboard panel) or light Home (dashboard open)."
)

FIELD_CLASSES = frozenset((
    NARRATIVE, ACTION, IDENTIFIER, ERROR, MODEL_INPUT, NOTIFICATION,
))

REQUIRED_INSTALL_RUNTIMES = (
    "dashboard", "morning-brief", "morning-brief-deadman",
    "decision-alert", "mission_control_common.py",
    "compose-decision-prompt.py", "mc-panel.swift",
)
REQUIRED_INSTALL_ASSETS = (
    "index.html", "vendor/cytoscape.min.js", "panel.html",
    "launchd/com.gillettes.mc-panel.plist.template",
)

SECRET_PLACEHOLDER = "«REDACTED-SECRET»"
PII_PLACEHOLDER = "«REDACTED-PII»"
SENSITIVE_PLACEHOLDER = "«REDACTED-SENSITIVE-FIELD»"
PATH_PLACEHOLDER = "«REDACTED-PATH»"

_SECRET_RE = re.compile(
    r"(sk-ant-(?:api|oat)\d{2}-[A-Za-z0-9_-]*"
    r"|sk-[A-Za-z0-9_-]{20,}"
    r"|AIza[0-9A-Za-z_-]{35}"
    r"|ya29\.[0-9A-Za-z._-]+"
    r"|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|xox[baprs]-[A-Za-z0-9-]{10,}"
    r"|AKIA[0-9A-Z]{16}"
    r"|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    r"|(?i:bearer)\s+[A-Za-z0-9._-]{16,}"
    r"|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)"
)
_EMAIL_RE = re.compile(
    r"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@"
    r"[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![A-Za-z0-9.-])"
)
_PHONE_RE = re.compile(
    r"(?<![A-Za-z0-9])(?:\+?1[\s.-]?)?"
    r"(?:\(\d{3}\)|\d{3})[\s.-]\d{3}[\s.-]\d{4}"
    r"(?![A-Za-z0-9])"
)
_HOST_PATH_RE = re.compile(
    r"(?<![A-Za-z0-9])/(?:Users|Volumes|private|tmp|var|etc)"
    r"(?:/[^\s\"'`<>|)\]}]+)+"
)

_PATH_STRIP_FIELDS = frozenset((NARRATIVE, ERROR, MODEL_INPUT, NOTIFICATION))


def _default_approved_roots():
    home = os.path.expanduser("~")
    return (
        os.path.join(home, "Coding Projects"),
        os.path.join(home, ".codex", "scripts"),
        os.path.join(home, ".local", "bin"),
        os.path.join(home, ".mission-control"),
        os.path.join(home, ".chat-graph"),
    )


def _configured_roots():
    configured = os.environ.get("MISSION_CONTROL_EGRESS_APPROVED_ROOTS", "")
    extra = tuple(os.path.expanduser(x) for x in configured.split(os.pathsep) if x)
    roots = _default_approved_roots() + extra
    return tuple(os.path.normpath(x) for x in roots if x)


def _configured_denylist():
    raw = os.environ.get("MISSION_CONTROL_EGRESS_DENYLIST", "")
    return tuple(x.strip() for x in raw.split(",") if x.strip())


@dataclass(frozen=True)
class SanitizedText:
    value: str
    dropped: bool
    reasons: tuple
    path_redactions: int = 0


class EgressCounters(object):
    """Content-free counters suitable for machinery-health output."""

    def __init__(self):
        self._counts = Counter()

    def increment(self, name, amount=1):
        self._counts[str(name)] += int(amount)

    def record(self, result):
        if result.dropped:
            self.increment("dropped_fields")
        for reason in result.reasons:
            self.increment("reason_%s" % reason)
        if result.path_redactions:
            self.increment("path_redactions", result.path_redactions)

    def snapshot(self):
        keys = (
            "dropped_fields", "path_redactions", "tool_outputs_skipped",
            "reason_secret", "reason_email", "reason_phone", "reason_denylist",
        )
        out = {key: int(self._counts.get(key, 0)) for key in keys}
        for key, value in self._counts.items():
            if key not in out:
                out[key] = int(value)
        return out

    def __repr__(self):
        return "EgressCounters(%r)" % self.snapshot()


def _path_is_approved(path, approved_roots):
    clean = os.path.normpath(path.rstrip(".,;:"))
    for root in approved_roots:
        if clean == root or clean.startswith(root + os.sep):
            return True
    return False


def _strip_unapproved_paths(value, approved_roots):
    count = [0]
    protected = value
    sentinels = []
    # Roots such as "Coding Projects" contain spaces, so a generic whitespace-
    # terminated path regex cannot recognize the whole approved prefix. Protect
    # exact approved roots before scanning the remaining host paths.
    for index, root in enumerate(sorted(approved_roots, key=len, reverse=True)):
        if root and root in protected:
            sentinel = "__MC_APPROVED_ROOT_%d__" % index
            protected = protected.replace(root, sentinel)
            sentinels.append((sentinel, root))

    def replace(match):
        path = match.group(0)
        if _path_is_approved(path, approved_roots):
            return path
        count[0] += 1
        trailing = ""
        while path and path[-1] in ".,;:":
            trailing = path[-1] + trailing
            path = path[:-1]
        return PATH_PLACEHOLDER + trailing

    protected = _HOST_PATH_RE.sub(replace, protected)
    for sentinel, root in sentinels:
        protected = protected.replace(sentinel, root)
    return protected, count[0]


def sanitize_text(value, field_class, counters=None, denylist=None,
                  approved_roots=None):
    """Sanitize one field and return a content-safe result.

    Secrets, email, phone and denylisted terms drop the entire field value.
    Transcript-derived narrative-like fields also replace unapproved host paths.
    ACTION fields intentionally retain necessary paths after sensitive screening.
    """
    if field_class not in FIELD_CLASSES:
        raise ValueError("unknown egress field class: %s" % field_class)
    text = "" if value is None else str(value)
    reasons = []
    if _SECRET_RE.search(text):
        reasons.append("secret")
    if _EMAIL_RE.search(text):
        reasons.append("email")
    if _PHONE_RE.search(text):
        reasons.append("phone")
    terms = tuple(denylist if denylist is not None else _configured_denylist())
    lowered = text.casefold()
    if any(term.casefold() in lowered for term in terms if term):
        reasons.append("denylist")
    if reasons:
        unique = tuple(sorted(set(reasons)))
        if unique == ("secret",):
            placeholder = SECRET_PLACEHOLDER
        elif set(unique).issubset(("email", "phone")):
            placeholder = PII_PLACEHOLDER
        else:
            placeholder = SENSITIVE_PLACEHOLDER
        result = SanitizedText(placeholder, True, unique)
        if counters is not None:
            counters.record(result)
        return result

    redacted_paths = 0
    if field_class in _PATH_STRIP_FIELDS:
        roots = tuple(approved_roots if approved_roots is not None else _configured_roots())
        text, redacted_paths = _strip_unapproved_paths(text, roots)
    result = SanitizedText(text, False, (), redacted_paths)
    if counters is not None:
        counters.record(result)
    return result


def safe_text(value, field_class=NARRATIVE, counters=None, **kwargs):
    """Compatibility helper returning only the sanitized display value."""
    return sanitize_text(value, field_class, counters=counters, **kwargs).value


def process_start_identity(pid, timeout_s=2):
    """Return ``(probe_ok, identity)``; a missing PID has identity ``None``.

    Process-start identity distinguishes a still-current owner from PID reuse.
    Fail closed when the host probe itself is unavailable or ambiguous.
    """
    try:
        proc = subprocess.run(
            ["/bin/ps", "-o", "lstart=", "-p", str(int(pid))],
            capture_output=True, text=True, timeout=timeout_s)
    except (OSError, TypeError, ValueError, subprocess.TimeoutExpired):
        return False, None
    start = proc.stdout.strip()
    if proc.returncode == 0 and start:
        return True, start
    if proc.returncode in (0, 1) and not start:
        return True, None
    return False, None


def _message_is_tool_output(message):
    role = str(message.get("role", "")).lower()
    kind = str(message.get("type", "")).lower()
    return role in ("tool", "tool_result") or kind in ("tool", "tool_result")


def _truncate_utf8_tail(value, max_bytes):
    data = value.encode("utf-8")
    if len(data) <= max_bytes:
        return value
    data = data[-max_bytes:]
    while data:
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            data = data[1:]
    return ""


def sanitize_model_messages(messages, source_provider, max_messages=12,
                            max_bytes=32768, counters=None,
                            include_tool_output=False):
    """Prepare a bounded content-safe tail plus content-free call metadata."""
    counters = counters if counters is not None else EgressCounters()
    selected = []
    remaining = max(0, int(max_bytes))
    for original in reversed(list(messages or [])):
        if len(selected) >= max(0, int(max_messages)) or remaining <= 0:
            break
        message = original if isinstance(original, dict) else {"role": "unknown", "text": original}
        if _message_is_tool_output(message) and not include_tool_output:
            counters.increment("tool_outputs_skipped")
            continue
        raw = message.get("text")
        if raw is None and isinstance(message.get("content"), str):
            raw = message.get("content")
        if raw is None:
            continue
        result = sanitize_text(raw, MODEL_INPUT, counters=counters)
        if result.dropped:
            continue
        bounded = _truncate_utf8_tail(result.value, remaining)
        if not bounded:
            continue
        remaining -= len(bounded.encode("utf-8"))
        selected.append({"role": str(message.get("role") or "unknown"), "text": bounded})
    selected.reverse()
    used = sum(len(row["text"].encode("utf-8")) for row in selected)
    metadata = {
        "source_provider": str(source_provider or "unknown"),
        "messages_selected": len(selected),
        "bytes_selected": used,
        "max_messages": max(0, int(max_messages)),
        "max_bytes": max(0, int(max_bytes)),
        "result_status": "prepared",
    }
    return selected, metadata


def sanitize_chunks(chunks, counters=None):
    """Sanitize notification chunks; sensitive chunks are omitted entirely."""
    counters = counters if counters is not None else EgressCounters()
    out = []
    for chunk in chunks or []:
        result = sanitize_text(chunk, NOTIFICATION, counters=counters)
        if not result.dropped and result.value:
            out.append(result.value)
    return out


# --- freshness + product validity -------------------------------------------
# Shared Python source of truth for feed freshness. The browser independently
# verifies the advertised raw evidence against the same wire contract so a
# malformed or contradictory producer envelope cannot render green.

def _wire_number(value):
    """Return a finite JSON number without bool/string coercion."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return value


def _wire_epoch(value):
    """Return strict integer epoch seconds, or None for malformed wire data."""
    value = _wire_number(value)
    if value is None or (isinstance(value, float) and not value.is_integer()):
        return None
    return int(value)

def same_local_day(epoch, now):
    """True when epoch and now fall on the same local calendar day."""
    epoch = _wire_epoch(epoch)
    now = _wire_epoch(now)
    if epoch is None or now is None:
        return False
    try:
        return time.strftime("%Y-%m-%d", time.localtime(epoch)) == time.strftime(
            "%Y-%m-%d", time.localtime(now))
    except (TypeError, ValueError, OverflowError, OSError):
        return False


def next_local_midnight(epoch):
    """Epoch of 00:00 local on the day AFTER epoch's local day.

    This is a daily product's validity horizon: a brief composed any time today
    stays valid until the next local midnight, when a fresh compose supersedes
    it. mktime normalizes the mday+1 rollover and picks the right DST offset.
    """
    try:
        raw = _wire_epoch(epoch)
        if raw is None:
            return None
        if raw <= 0:
            return None
        lt = time.localtime(raw)
    except (TypeError, ValueError, OverflowError, OSError):
        return None
    start_next = (lt.tm_year, lt.tm_mon, lt.tm_mday + 1, 0, 0, 0, 0, 0, -1)
    try:
        return int(time.mktime(start_next))
    except (OverflowError, OSError):
        return None


# The full transcript ingest runs NIGHTLY (com.gillettes.nightly-review,
# StartCalendarInterval 23:30 daily -> nightly-review.sh runs `chat-graph ingest`,
# which writes ~/.chat-graph/last-ingest; round-4 proof observed the marker at
# 2026-07-10 23:31:21). Its staleness horizon is therefore a nightly one, NOT the
# 1800s envelope cadence the chats FEED is regenerated on. Band: a healthy last-night
# ingest tops out near the 24h cycle (marker stamped at completion, no meaningful
# export lag), while a genuinely missed nightly is >=~31.5h at the 07:00 brief
# (~48h general). 30h separates the two; an envelope may override with its own
# completion SLA via counts.full_ingest_sla_s.
def full_ingest_sla_s():
    default = 30 * 3600
    try:
        value = int(os.environ.get("MISSION_CONTROL_FULL_INGEST_SLA_S", default))
    except (TypeError, ValueError):
        return default
    return value if value > 0 else default


def nested_ingest_state(env):
    """Freshness state for a feed's nested full transcript ingest.

    The chats feed is regenerated from a bounded catch-up scan on the 1800s
    envelope cadence, while its last complete transcript pass runs nightly; the
    nightly SLA (not the envelope cadence) decides whether that pass is stale.
    """
    is_chats = isinstance(env, dict) and env.get("feed") == "chats"
    if not isinstance(env, dict) or not isinstance(env.get("data"), dict):
        return "unknown" if is_chats else "fresh"
    counts = env["data"].get("counts")
    if not isinstance(counts, dict):
        return "unknown" if is_chats else "fresh"
    full_ingest_keys = ("full_ingest_state", "full_ingest_stale",
                        "last_full_ingest_age_s", "last_full_ingest_epoch",
                        "full_ingest_sla_s")
    has_full_ingest = any(k in counts for k in full_ingest_keys)
    if not is_chats and not has_full_ingest:
        return "fresh"
    if "ingest_skipped" in counts:
        skipped = counts.get("ingest_skipped")
        if not isinstance(skipped, bool):
            return "unknown"
        if skipped:
            return "stale"
    if "last_full_ingest_age_s" not in counts:
        return "unknown"
    age = counts.get("last_full_ingest_age_s")
    age = _wire_number(age)
    if age is None or age < 0:
        return "unknown"
    if "full_ingest_sla_s" in counts:
        sla = counts.get("full_ingest_sla_s")
        sla = _wire_number(sla)
        if sla is None or sla <= 0:
            return "unknown"
    else:
        sla = full_ingest_sla_s()
    computed = "stale" if age > sla else "fresh"

    # Derived producer flags are useful to non-Python consumers, but they cannot
    # override malformed raw evidence. A contradictory envelope is unknown,
    # never green: this catches partial writes and rolling-version mismatches.
    has_declared = "full_ingest_state" in counts
    has_legacy = "full_ingest_stale" in counts
    if not has_declared and not has_legacy:
        return computed
    if has_declared != has_legacy:
        return "unknown"
    declared = counts.get("full_ingest_state")
    legacy = counts.get("full_ingest_stale")
    if declared not in ("fresh", "stale", "unknown") or not isinstance(legacy, bool):
        return "unknown"
    if declared == "unknown":
        return "unknown"
    if declared != computed or legacy != (declared == "stale"):
        return "unknown"
    return declared


def nested_ingest_stale(env):
    """True when a feed is envelope-fresh but its full ingest is not trusted."""
    return nested_ingest_state(env) != "fresh"


def feed_health(env, cadence, now, stale_multiple=6, aging=True):
    """Freshness verdict for one feed envelope.

    Returns a dict: state in {missing, error, skew, stale, aging, fresh};
    red (bool) True when the feed must alarm on age alone; nested_stale (bool)
    the separate full-ingest signal callers surface however they like; plus
    age_s, ok, generated_epoch, valid_until.

    stale_multiple/aging tune the age ladder for each caller (dashboard: 6x with
    an aging tier; brief inputs: 1x, no aging). A daily product that stamps
    valid_until stays fresh for its whole valid window regardless of cadence.
    """
    base = {"state": "missing", "red": True, "age_s": None,
            "nested_stale": False, "nested_state": "fresh", "ok": False, "generated_epoch": None,
            "valid_until": None}
    if env is None:
        return base
    if not isinstance(env, dict):
        return base
    wire_cadence = _wire_epoch(env.get("cadence_s"))
    expected_cadence = _wire_epoch(cadence)
    wire_now = _wire_epoch(now)
    schema = env.get("schema")
    ok_value = env.get("ok")
    data = env.get("data")
    envelope_valid = (
        type(schema) is int and schema == 1 and
        isinstance(ok_value, bool) and
        wire_cadence is not None and wire_cadence > 0 and
        expected_cadence is not None and expected_cadence > 0 and
        wire_cadence == expected_cadence and
        wire_now is not None and
        (ok_value is False or isinstance(data, dict))
    )
    if not envelope_valid:
        malformed = dict(base)
        malformed["state"] = "error"
        malformed["nested_state"] = "unknown" if env.get("feed") == "chats" else "fresh"
        malformed["nested_stale"] = malformed["nested_state"] != "fresh"
        return malformed
    ok = ok_value
    epoch = _wire_epoch(env.get("generated_epoch"))
    age = None if epoch is None else wire_now - epoch
    has_valid_until = "valid_until" in env and env.get("valid_until") is not None
    valid_until = _wire_epoch(env.get("valid_until")) if has_valid_until else None
    valid_until_invalid = has_valid_until and valid_until is None
    nested_state = nested_ingest_state(env)
    counts = env.get("data", {}).get("counts") if isinstance(env.get("data"), dict) else None
    # A chats consumer must see the producer's derived state. Raw age alone is
    # insufficient during a rolling upgrade; consumers also verify the derived
    # state against the advertised/default nightly SLA before trusting green.
    if env.get("feed") == "chats":
        if (not isinstance(counts, dict) or
                "full_ingest_state" not in counts or
                "full_ingest_stale" not in counts):
            nested_state = "unknown"
    out = {"age_s": (max(0, age) if age is not None else None),
           "nested_stale": nested_state != "fresh", "nested_state": nested_state,
           "ok": ok,
           "generated_epoch": epoch, "valid_until": valid_until}
    # A daily product's validity horizon is exactly the next local midnight after
    # its compose epoch (<=~24h, ~25h across a fall-back DST day). A valid_until
    # beyond that is malformed (a 47h value, or a 30h-old brief still claiming
    # validity) and must NOT suppress staleness, so it is honored only up to that
    # per-day boundary — not a flat multi-day slab.
    midnight = next_local_midnight(epoch) if epoch is not None else None
    valid_ok = (valid_until is not None and midnight is not None and
                valid_until <= midnight)
    if not ok:
        out["state"], out["red"] = "error", True
    elif age is None:
        out["state"], out["red"] = "stale", True
    elif age < 0:
        out["state"], out["red"], out["age_s"] = "skew", False, age
    elif valid_until_invalid:
        out["state"], out["red"] = "stale", True
    elif valid_until is not None and wire_now >= valid_until:
        # A present valid_until is a HARD expiry: once now reaches it, an expired
        # daily brief reads stale immediately, regardless of the poll cadence age.
        out["state"], out["red"] = "stale", True
    elif valid_ok and wire_now < valid_until:
        out["state"], out["red"] = "fresh", False
    elif age > stale_multiple * cadence:
        out["state"], out["red"] = "stale", True
    elif age > cadence:
        out["state"], out["red"] = ("aging", False) if aging else ("stale", True)
    else:
        out["state"], out["red"] = "fresh", False
    return out


# --- install provenance stamp -----------------------------------------------
# The install step copies runtimes from the committed HEAD SHA and records this
# stamp; status + deadman re-hash the installed files against it so an install
# that drifted from any committed SHA (or from a mutated bin/) is visible.

INSTALL_STAMP_NAME = "install-stamp.json"


def _sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_install_stamp(bin_dir, head_sha, provenance, names, now, assets=None):
    """Record sha256 of each installed runtime + deployment asset + the HEAD SHA.

    `names` are runtimes under bin_dir (stored bare in "files"). `assets` is an
    optional {home_relative_path: absolute_path} map for the non-bin deployment
    set (index.html, vendor/*), stored under "assets" so status + the deadman
    detect drift in the exact code/render surface, not just the five bin files.
    """
    expected_files = set(REQUIRED_INSTALL_RUNTIMES)
    expected_assets = set(REQUIRED_INSTALL_ASSETS)
    if set(names or ()) != expected_files:
        raise ValueError("install stamp runtime set must be exactly %s" %
                         sorted(expected_files))
    if set((assets or {}).keys()) != expected_assets:
        raise ValueError("install stamp asset set must be exactly %s" %
                         sorted(expected_assets))
    files = {}
    for name in REQUIRED_INSTALL_RUNTIMES:
        path = os.path.join(bin_dir, name)
        if not os.path.isfile(path):
            raise OSError("required installed runtime missing: %s" % name)
        files[name] = _sha256_file(path)
    asset_hashes = {}
    for rel in REQUIRED_INSTALL_ASSETS:
        path = assets[rel]
        if not os.path.isfile(path):
            raise OSError("required installed asset missing: %s" % rel)
        asset_hashes[rel] = _sha256_file(path)
    stamp = {"schema": 1, "installed_at": int(now),
             "head_sha": head_sha or None, "provenance": provenance,
             "files": files, "assets": asset_hashes}
    path = os.path.join(bin_dir, INSTALL_STAMP_NAME)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    try:
        with open(tmp, "w") as handle:
            json.dump(stamp, handle, ensure_ascii=True, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    return stamp


def verify_install_stamp(bin_dir):
    """Re-hash installed runtimes against the stamp. Content-free verdict."""
    def verdict(present, reason, head_sha=None, provenance=None,
                mismatches=None, missing=None, unexpected=None):
        mismatches = sorted(mismatches or [])
        missing = sorted(missing or [])
        unexpected = sorted(unexpected or [])
        return {"present": bool(present), "ok": reason == "verified",
                "reason": reason, "head_sha": head_sha,
                "provenance": provenance, "mismatches": mismatches,
                "missing": missing, "unexpected": unexpected}

    path = os.path.join(bin_dir, INSTALL_STAMP_NAME)
    if not os.path.lexists(path):
        return verdict(False, "missing")
    if os.path.islink(path) or not os.path.isfile(path):
        return verdict(True, "malformed")
    try:
        with open(path) as handle:
            stamp = json.load(handle)
    except OSError:
        return verdict(True, "unreadable")
    except ValueError:
        return verdict(True, "malformed")
    if not isinstance(stamp, dict):
        return verdict(True, "malformed")
    files = stamp.get("files")
    assets = stamp.get("assets")
    head_sha = stamp.get("head_sha")
    provenance = stamp.get("provenance")
    installed_at = stamp.get("installed_at")
    schema = stamp.get("schema")
    head_valid = (
        provenance == "head" and isinstance(head_sha, str) and
        re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", head_sha) is not None
    ) or (provenance == "worktree" and head_sha == "worktree")
    if (type(schema) is not int or schema != 1 or
            type(installed_at) is not int or installed_at <= 0 or
            not isinstance(files, dict) or
            not isinstance(assets, dict) or not isinstance(head_sha, str) or
            not head_sha or provenance not in ("head", "worktree") or
            not head_valid or any(not isinstance(k, str)
                                  for k in list(files) + list(assets))):
        safe_provenance = provenance if provenance in ("head", "worktree") else None
        return verdict(True, "malformed",
                       head_sha if head_valid else None, safe_provenance)
    mismatches, missing, unexpected, invalid_hashes = [], [], [], []
    if set(files) - set(REQUIRED_INSTALL_RUNTIMES):
        unexpected.append("unexpected-runtime")
    if set(assets) - set(REQUIRED_INSTALL_ASSETS):
        unexpected.append("unexpected-asset")
    for name in REQUIRED_INSTALL_RUNTIMES:
        expected = files.get(name)
        if expected is None:
            missing.append(name)
            continue
        if not isinstance(expected, str) or len(expected) != 64:
            invalid_hashes.append(name)
            continue
        candidate = os.path.join(bin_dir, name)
        if os.path.islink(candidate) or not os.path.isfile(candidate):
            missing.append(name)
        else:
            try:
                mode = os.stat(candidate).st_mode
                if (name not in ("mission_control_common.py", "mc-panel.swift") and
                        not (mode & stat.S_IXUSR)):
                    mismatches.append(name)
                elif _sha256_file(candidate) != expected:
                    mismatches.append(name)
            except OSError:
                missing.append(name)
    # Assets live under the mission-control home (parent of bin_dir), keyed by a
    # home-relative path (e.g. index.html, vendor/foo.js).
    home = os.path.dirname(bin_dir)
    for rel in REQUIRED_INSTALL_ASSETS:
        expected = assets.get(rel)
        if expected is None:
            missing.append(rel)
            continue
        if not isinstance(expected, str) or len(expected) != 64:
            invalid_hashes.append(rel)
            continue
        candidate = os.path.join(home, rel)
        if os.path.islink(candidate) or not os.path.isfile(candidate):
            missing.append(rel)
        else:
            try:
                if _sha256_file(candidate) != expected:
                    mismatches.append(rel)
            except OSError:
                missing.append(rel)
    if missing or unexpected:
        return verdict(True, "drift", head_sha, provenance,
                       mismatches, missing, unexpected)
    if invalid_hashes:
        return verdict(True, "malformed", head_sha, provenance)
    if mismatches:
        return verdict(True, "drift", head_sha, provenance,
                       mismatches, missing, unexpected)
    if provenance != "head":
        return verdict(True, "uncommitted", head_sha, provenance)
    return verdict(True, "verified", head_sha, provenance)
