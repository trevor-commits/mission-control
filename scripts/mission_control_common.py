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
import os
import re
import time
from collections import Counter
from dataclasses import dataclass

NARRATIVE = "narrative"
ACTION = "action"
IDENTIFIER = "identifier"
ERROR = "error"
MODEL_INPUT = "model_input"
NOTIFICATION = "notification"

FIELD_CLASSES = frozenset((
    NARRATIVE, ACTION, IDENTIFIER, ERROR, MODEL_INPUT, NOTIFICATION,
))

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
# ONE source of truth for feed freshness across the dashboard status command,
# the index.html per-feed guard, and the morning brief's input-health check.
# The envelope compose timestamp alone misses two real staleness classes; both
# are folded in here so a caller cannot forget one (the class of bug that let a
# brief claim its chats input fresh while the full transcript ingest was ~a day
# behind).

def same_local_day(epoch, now):
    """True when epoch and now fall on the same local calendar day."""
    try:
        return time.strftime("%Y-%m-%d", time.localtime(int(epoch))) == time.strftime(
            "%Y-%m-%d", time.localtime(int(now)))
    except (TypeError, ValueError):
        return False


def next_local_midnight(epoch):
    """Epoch of 00:00 local on the day AFTER epoch's local day.

    This is a daily product's validity horizon: a brief composed any time today
    stays valid until the next local midnight, when a fresh compose supersedes
    it. mktime normalizes the mday+1 rollover and picks the right DST offset.
    """
    lt = time.localtime(int(epoch))
    start_next = (lt.tm_year, lt.tm_mon, lt.tm_mday + 1, 0, 0, 0, 0, 0, -1)
    return int(time.mktime(start_next))


def nested_ingest_stale(env, cadence):
    """True when a feed is envelope-fresh but its last FULL ingest is stale.

    The chats feed can be regenerated from a bounded catch-up scan while its
    last complete transcript pass is a day behind; data.counts surfaces that.
    """
    if not env or not isinstance(env.get("data"), dict):
        return False
    counts = env["data"].get("counts") or {}
    if counts.get("ingest_skipped"):
        return True
    if "last_full_ingest_age_s" not in counts:
        return False
    age = counts.get("last_full_ingest_age_s")
    return age is None or int(age) > cadence


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
            "nested_stale": False, "ok": False, "generated_epoch": None,
            "valid_until": None}
    if env is None:
        return base
    ok = bool(env.get("ok", True))
    try:
        epoch = int(env.get("generated_epoch"))
    except (TypeError, ValueError):
        epoch = None
    age = None if epoch is None else now - epoch
    try:
        valid_until = int(env["valid_until"]) if env.get("valid_until") is not None else None
    except (TypeError, ValueError):
        valid_until = None
    out = {"age_s": (max(0, age) if age is not None else None),
           "nested_stale": nested_ingest_stale(env, cadence), "ok": ok,
           "generated_epoch": epoch, "valid_until": valid_until}
    if not ok:
        out["state"], out["red"] = "error", True
    elif age is None:
        out["state"], out["red"] = "stale", True
    elif age < 0:
        out["state"], out["red"], out["age_s"] = "skew", False, age
    elif valid_until is not None and now < valid_until:
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


def write_install_stamp(bin_dir, head_sha, provenance, names, now):
    """Record sha256 of each installed runtime + the HEAD SHA it came from."""
    files = {}
    for name in names:
        path = os.path.join(bin_dir, name)
        if os.path.isfile(path):
            files[name] = _sha256_file(path)
    stamp = {"schema": 1, "installed_at": int(now),
             "head_sha": head_sha or None, "provenance": provenance,
             "files": files}
    path = os.path.join(bin_dir, INSTALL_STAMP_NAME)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as handle:
        json.dump(stamp, handle, ensure_ascii=True, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.rename(tmp, path)
    return stamp


def verify_install_stamp(bin_dir):
    """Re-hash installed runtimes against the stamp. Content-free verdict."""
    path = os.path.join(bin_dir, INSTALL_STAMP_NAME)
    try:
        with open(path) as handle:
            stamp = json.load(handle)
    except (OSError, ValueError):
        return {"present": False, "ok": False, "head_sha": None,
                "provenance": None, "mismatches": [], "missing": []}
    mismatches, missing = [], []
    for name, expected in (stamp.get("files") or {}).items():
        candidate = os.path.join(bin_dir, name)
        if not os.path.isfile(candidate):
            missing.append(name)
        elif _sha256_file(candidate) != expected:
            mismatches.append(name)
    return {"present": True, "ok": not mismatches and not missing,
            "head_sha": stamp.get("head_sha"),
            "provenance": stamp.get("provenance"),
            "mismatches": sorted(mismatches), "missing": sorted(missing)}
