#!/usr/bin/env python3
"""Shared provider-native transcript source discovery for outcome tooling.

Discovery is read-only and returns one newest source per provider/session.  The
collector keeps its own cursor discipline; coverage planning and Tier 2 use
this bounded recent-window view so their provider roots cannot drift apart.
"""

import glob
import os
import re
import sqlite3
import time

PROVIDERS = ("claude", "codex", "cursor", "hermes", "copilot")
MAX_FILE_BYTES = 200 * 1024 * 1024
UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

_DEFAULT_ROOTS = {
    "claude": "~/.claude/projects",
    "codex": "~/.codex/sessions",
    "cursor": "~/.cursor/projects",
    "hermes": "~/.hermes/sessions",
    "copilot": "~/.copilot/session-state",
}


def _configured(name, default, env_prefix=None, fallback_prefix="CHAT_GRAPH"):
    names = []
    if env_prefix:
        names.append("%s_%s" % (env_prefix, name))
    if fallback_prefix:
        names.append("%s_%s" % (fallback_prefix, name))
    for candidate in names:
        if candidate in os.environ:
            return os.path.expanduser(os.environ[candidate])
    return os.path.expanduser(default)


def root_for(provider, env_prefix=None):
    return _configured("%s_ROOT" % provider.upper(), _DEFAULT_ROOTS[provider],
                       env_prefix=env_prefix)


def hermes_db(env_prefix=None):
    names = []
    if env_prefix:
        names.extend(("%s_HERMES_DB" % env_prefix,
                      "%s_HERMES_STATE_DB" % env_prefix))
    names.append("CHAT_GRAPH_HERMES_STATE_DB")
    for name in names:
        if name in os.environ:
            return os.path.expanduser(os.environ[name])
    return os.path.expanduser("~/.hermes/state.db")


def session_id(path, root, provider):
    match = UUID_RE.search(path)
    if match:
        return match.group(0)
    name = os.path.basename(path)
    stem = name[:-6] if name.endswith(".jsonl") else name
    if provider == "copilot" and stem == "events":
        return os.path.basename(os.path.dirname(path))
    if provider == "codex" and stem.startswith("rollout-"):
        return stem[len("rollout-"):]
    relative = os.path.relpath(path, root)
    return relative[:-6] if relative.endswith(".jsonl") else relative


def recent_sources(days, max_messages=12, env_prefix=None,
                   max_file_bytes=MAX_FILE_BYTES):
    """Return ``(sources, status)`` for a bounded recent window.

    A source row is ``(provider, session_id, source, mtime_ns)``. ``source`` is
    either ``{"kind":"jsonl","path":...}`` or an in-memory Hermes assistant
    tail.  No content is logged or persisted here.
    """
    cutoff = time.time() - max(1, int(days)) * 86400
    latest = {}
    status = {}
    for provider in PROVIDERS:
        if provider == "hermes":
            continue
        root = root_for(provider, env_prefix=env_prefix)
        seen = skipped_large = 0
        pattern = "rollout-*.jsonl" if provider == "codex" else "*.jsonl"
        paths = (glob.glob(os.path.join(root, "**", pattern), recursive=True)
                 if os.path.isdir(root) else [])
        for path in paths:
            if provider in ("claude", "cursor") and "subagents" in os.path.relpath(
                    path, root).split(os.sep):
                continue
            try:
                stat = os.stat(path)
            except OSError:
                continue
            if stat.st_mtime < cutoff:
                continue
            seen += 1
            if stat.st_size > max_file_bytes:
                skipped_large += 1
                continue
            sid = session_id(path, root, provider)
            key = (provider, sid)
            row = (provider, sid, {"kind": "jsonl", "path": path}, stat.st_mtime_ns)
            current = latest.get(key)
            if current is None or row[3] > current[3]:
                latest[key] = row
        status[provider] = {
            "root_present": os.path.isdir(root),
            "recent_files": seen,
            "skipped_large": skipped_large,
            "storage": "jsonl",
        }

    path = hermes_db(env_prefix=env_prefix)
    sessions = 0
    try:
        source = sqlite3.connect("file:%s?mode=ro" % path, uri=True, timeout=5)
        source.row_factory = sqlite3.Row
        source.execute("BEGIN")
        rows = source.execute("""SELECT DISTINCT session_id FROM messages
            WHERE active=1 AND role='assistant' AND timestamp>=?
            ORDER BY session_id""", (cutoff,)).fetchall()
        for row in rows:
            sid = row["session_id"]
            tail = source.execute("""SELECT id,role,content,timestamp FROM messages
                WHERE session_id=? AND active=1 AND role='assistant'
                ORDER BY id DESC LIMIT ?""", (sid, max(1, int(max_messages)))).fetchall()
            messages = [dict(item) for item in reversed(tail)]
            if not messages:
                continue
            timestamp = max(float(item.get("timestamp") or cutoff) for item in messages)
            latest[("hermes", sid)] = (
                "hermes", sid, {"kind": "messages", "messages": messages},
                int(timestamp * 1_000_000_000))
            sessions += 1
        source.close()
        present, read_error = True, False
    except (OSError, sqlite3.Error):
        present, read_error = os.path.isfile(path), True
    status["hermes"] = {
        "root_present": present,
        "recent_files": 0,
        "recent_sessions": sessions,
        "skipped_large": 0,
        "read_error": read_error,
        "storage": "state.db",
    }
    rows = list(latest.values())
    rows.sort(key=lambda item: (-item[3], item[0], item[1]))
    return rows, status


def read_messages(source, file_reader):
    if source.get("kind") == "messages":
        return list(source.get("messages") or [])
    return file_reader(source["path"])
