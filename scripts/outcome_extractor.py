#!/usr/bin/env python3
"""Bounded, fail-open Tier 2 outcome extraction.

The public entry point remains ``chat-graph extract-outcomes``.  This module is
deliberately separate from ingest/export: it owns a distinct mkdir lock, closes
SQLite before every model call, and reopens WAL only for short reservations and
per-card writes.  Model text is narrative-only; Tier 1 remains authoritative
for commands, identifiers, commits, decisions, and resolution evidence.
"""

import argparse
import hashlib
import json
import math
import os
import subprocess
import tempfile
import time

from mission_control_common import (NARRATIVE, EgressCounters,
                                    sanitize_model_messages, sanitize_text)
from outcome_sources import PROVIDERS, read_messages, recent_sources

EXTRACTOR_VERSION = 1
PROMPT_VERSION = 3
EGRESS_POLICY_VERSION = 3
DEFAULT_MODEL = "claude-haiku-4.5"
DEFAULT_ESCALATION_MODEL = "claude-sonnet-4-6"
DEFAULT_CLAUDE = os.path.expanduser("~/.local/bin/claude")
DEFAULT_MAX_OUTPUT_TOKENS = 512
MAX_MODEL_OUTPUT_BYTES = 16 * 1024
LOCK_STALE_S = 30 * 60
DEFER_RETRY_S = 5 * 60
FAILURE_RETRY_S = 6 * 60 * 60
_LOCK_TOKEN = "%d-%d" % (os.getpid(), int(time.time() * 1000000))

_DID_LABELS = {
    "implementation_completed": "Implementation work was completed.",
    "implementation_progress": "Implementation work progressed.",
    "analysis_completed": "Analysis was completed.",
    "audit_completed": "An audit was completed.",
    "defect_fixed": "A defect was fixed.",
    "testing_completed": "Testing was completed.",
    "documentation_completed": "Documentation was completed.",
    "configuration_completed": "Configuration work was completed.",
    "handoff_prepared": "A handoff was prepared.",
    "decision_recorded": "A decision was recorded.",
    "work_verified": "The work was verified.",
}
_OPEN_LABELS = {
    "review_remaining": "Review remains open.",
    "testing_remaining": "Testing remains open.",
    "implementation_remaining": "Implementation remains open.",
    "verification_remaining": "Verification remains open.",
    "decision_remaining": "A decision remains open.",
    "follow_up_remaining": "A follow-up remains open.",
}
_NEEDS_LABELS = {
    "choose_direction": "Trevor needs to choose a direction.",
    "approve_change": "Trevor needs to approve a change.",
    "provide_input": "Trevor needs to provide missing input.",
    "review_evidence": "Trevor needs to review the evidence.",
    "resolve_ambiguity": "Trevor needs to resolve an ambiguity.",
}

_HEALTH_FIELDS = frozenset((
    "calls", "successes", "input_tokens", "output_tokens", "cache_hits",
    "deferred", "failures", "budget_skips", "provider_skips",
    "disabled_skips", "privacy_skips", "uncalibrated_skips",
    "lock_skips", "backoff_skips", "escalations", "total_latency_ms",
))

_RESULT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "did": {"type": "array", "maxItems": 4,
                "items": {"type": "string", "enum": sorted(_DID_LABELS)}},
        "left_open": {"type": "array", "maxItems": 4,
                      "items": {"type": "string", "enum": sorted(_OPEN_LABELS)}},
        "needs_trevor": {"type": "array", "maxItems": 3,
                         "items": {"type": "string", "enum": sorted(_NEEDS_LABELS)}},
        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
        "ambiguity": {"type": "boolean"},
    },
    "required": ["did", "left_open", "needs_trevor", "confidence", "ambiguity"],
}


def _sha1(value):
    return hashlib.sha1(value.encode("utf-8", "replace")).hexdigest()


def _flag(name, default=True):
    raw = os.environ.get(name)
    if raw is None:
        return bool(default)
    return raw.strip().lower() not in ("0", "false", "no", "off", "disabled")


def _int_env(name, default=None, minimum=None, maximum=None):
    raw = os.environ.get(name)
    if raw in (None, ""):
        return default
    try:
        value = int(raw)
    except ValueError:
        return default
    if minimum is not None:
        value = max(minimum, value)
    if maximum is not None:
        value = min(maximum, value)
    return value


def _prompt_version():
    """Keep production identity pinned while allowing migration tests."""
    if _flag("MORNING_BRIEF_LLM_TESTING", False):
        return _int_env("MORNING_BRIEF_LLM_TEST_PROMPT_VERSION", PROMPT_VERSION,
                        minimum=1, maximum=1000000)
    return PROMPT_VERSION


def _day():
    return time.strftime("%Y-%m-%d", time.localtime())


def _ensure_health_row(con):
    con.execute("INSERT OR IGNORE INTO outcome_extraction_health(day,updated_at) VALUES(?,?)",
                (_day(), int(time.time())))


def _health(graph, status, **increments):
    if any(key not in _HEALTH_FIELDS for key in increments):
        raise ValueError("unknown outcome health counter")
    con = graph.connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        _ensure_health_row(con)
        for key, value in increments.items():
            con.execute("UPDATE outcome_extraction_health SET %s=%s+? WHERE day=?" %
                        (key, key), (int(value), _day()))
        con.execute("UPDATE outcome_extraction_health SET last_status=?,updated_at=? WHERE day=?",
                    (status, int(time.time()), _day()))
        con.commit()
    finally:
        con.close()


def _reserve_budget(graph, estimated_input, projected_output,
                    call_cap_override=None, token_cap_override=None):
    call_cap = (call_cap_override if call_cap_override is not None else
                _int_env("MORNING_BRIEF_LLM_DAILY_CALL_CAP"))
    token_cap = (token_cap_override if token_cap_override is not None else
                 _int_env("MORNING_BRIEF_LLM_DAILY_TOKEN_CAP"))
    con = graph.connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        _ensure_health_row(con)
        row = con.execute("SELECT * FROM outcome_extraction_health WHERE day=?",
                          (_day(),)).fetchone()
        if call_cap is None or token_cap is None:
            con.execute("""UPDATE outcome_extraction_health
                SET budget_skips=budget_skips+1,uncalibrated_skips=uncalibrated_skips+1,
                    last_status='uncalibrated',updated_at=? WHERE day=?""",
                        (int(time.time()), _day()))
            con.commit()
            return "uncalibrated"
        if (call_cap <= 0 or token_cap <= 0 or row["calls"] + 1 > call_cap or
                row["input_tokens"] + row["output_tokens"] + estimated_input +
                projected_output > token_cap):
            con.execute("""UPDATE outcome_extraction_health
                SET budget_skips=budget_skips+1,last_status='budget_skip',updated_at=?
                WHERE day=?""", (int(time.time()), _day()))
            con.commit()
            return "budget"
        con.execute("""UPDATE outcome_extraction_health
            SET calls=calls+1,input_tokens=input_tokens+?,last_status='reserved',updated_at=?
            WHERE day=?""", (estimated_input, int(time.time()), _day()))
        con.commit()
        return "reserved"
    finally:
        con.close()


def _finish_call(graph, status, estimated_input, actual_input=None,
                 actual_output=0, latency_ms=0, **increments):
    values = dict(increments)
    values["total_latency_ms"] = int(latency_ms)
    if actual_input is not None:
        values["input_tokens"] = int(actual_input) - int(estimated_input)
    values["output_tokens"] = int(actual_output or 0)
    _health(graph, status, **values)


def _lock_path(graph):
    return os.path.join(graph.HOME_DIR(), "outcome-extract.lock")


def _lock_owner_path(graph):
    return os.path.join(_lock_path(graph), "owner.json")


def _write_lock_owner(graph):
    path = _lock_owner_path(graph)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump({"pid": os.getpid(), "token": _LOCK_TOKEN,
                   "started_at": int(time.time())}, handle, sort_keys=True)
        handle.write("\n")


def _read_lock_owner(graph):
    try:
        with open(_lock_owner_path(graph)) as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def _pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


def _acquire_lock(graph):
    path = _lock_path(graph)
    try:
        os.mkdir(path, 0o700)
        _write_lock_owner(graph)
        return True
    except FileExistsError:
        owner = _read_lock_owner(graph)
        if owner and _pid_alive(owner.get("pid")):
            return False
        try:
            if time.time() - os.path.getmtime(path) > LOCK_STALE_S:
                try:
                    os.unlink(_lock_owner_path(graph))
                except FileNotFoundError:
                    pass
                os.rmdir(path)
                os.mkdir(path, 0o700)
                _write_lock_owner(graph)
                return True
        except OSError:
            pass
        return False
    except OSError:
        try:
            os.rmdir(path)
        except OSError:
            pass
        return False


def _release_lock(graph):
    owner = _read_lock_owner(graph)
    if not owner or owner.get("token") != _LOCK_TOKEN:
        return
    try:
        os.unlink(_lock_owner_path(graph))
        os.rmdir(_lock_path(graph))
    except OSError:
        pass


def _normal_messages(graph, messages):
    rows = []
    for message in messages or []:
        if not isinstance(message, dict):
            continue
        text = graph._msg_text(message)
        if text is None:
            continue
        rows.append({"role": "assistant", "content": text})
    return rows


def _sanitized_packet(graph, provider, messages):
    counters = EgressCounters()
    rows, metadata = sanitize_model_messages(
        _normal_messages(graph, messages), provider,
        max_messages=graph.TIER1_MAX_MESSAGES, max_bytes=graph.TIER1_MAX_BYTES,
        counters=counters, include_tool_output=False)
    packet = {"source_provider": provider, "messages": rows}
    encoded = json.dumps(packet, ensure_ascii=True, sort_keys=True,
                         separators=(",", ":"))
    metadata["egress_counters"] = counters.snapshot()
    metadata["sanitized_tail_hash"] = _sha1(encoded)
    return packet, metadata


def _prompt(packet):
    return (
        "Classify this bounded assistant tail into the supplied fixed outcome taxonomy.\n"
        "Return JSON matching the schema and select only its enum codes; never write free-form "
        "narrative, commands, identifiers, repository names, paths, or contact details. The "
        "caller maps codes to fixed plain-language sentences and copies exact anchors only from "
        "deterministic Tier 1. Use ambiguity=true only when the tail cannot support a reliable "
        "classification.\n\n"
        "SANITIZED_INPUT_JSON\n" +
        json.dumps(packet, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    )


def _model_command():
    configured = os.environ.get("MORNING_BRIEF_LLM_CMD")
    if _flag("MORNING_BRIEF_LLM_TESTING", False):
        # Test mode is a synthetic-only escape hatch.  It must never fall back
        # to the installed subscription wrapper when a fixture forgot its stub.
        return os.path.expanduser(configured) if configured else ""
    return DEFAULT_CLAUDE


def _state_home():
    return os.path.expanduser(os.environ.get(
        "MISSION_CONTROL_HOME", "~/.mission-control"))


def _config_path():
    return os.path.join(_state_home(), "outcome-extractor", "config.json")


def _run_marker_path():
    return os.path.join(_state_home(), "outcome-extractor", "last-run.json")


def _atomic_json(path, value, private_parent=False):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, mode=0o700, exist_ok=True)
    if private_parent:
        os.chmod(parent, 0o700)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(tmp, flags, 0o600)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def _load_config_env():
    try:
        with open(_config_path()) as handle:
            config = json.load(handle)
    except (OSError, ValueError):
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "uncalibrated"
    if not isinstance(config, dict) or config.get("schema") != (
            "mission-control/outcome-extractor-config/v1"):
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "uncalibrated"
    if config.get("enabled") is False:
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "disabled"
    providers = config.get("providers") if isinstance(config.get("providers"), dict) else {}
    call_cap = config.get("daily_call_cap")
    token_cap = config.get("daily_token_cap")
    valid_caps = (
        isinstance(call_cap, int) and not isinstance(call_cap, bool) and
        1 <= call_cap <= 100 and
        isinstance(token_cap, int) and not isinstance(token_cap, bool) and
        1 <= token_cap <= 10000000
    )
    valid_providers = (set(providers) == set(PROVIDERS) and
                       all(isinstance(providers[name], bool) for name in PROVIDERS))
    if config.get("enabled") is not True or not valid_caps or not valid_providers:
        os.environ["MORNING_BRIEF_LLM"] = "0"
        for provider in PROVIDERS:
            os.environ["MORNING_BRIEF_LLM_%s" % provider.upper()] = "0"
        return "uncalibrated"
    for key, env_name in (("daily_call_cap", "MORNING_BRIEF_LLM_DAILY_CALL_CAP"),
                          ("daily_token_cap", "MORNING_BRIEF_LLM_DAILY_TOKEN_CAP")):
        if key not in config:
            continue
        configured = _int_env(env_name)
        try:
            cap = int(config[key])
        except (TypeError, ValueError):
            continue
        # Runtime environment may tighten a calibrated cap, never raise it.
        os.environ[env_name] = str(min(cap, configured) if configured is not None else cap)
    if "MORNING_BRIEF_LLM" not in os.environ:
        os.environ["MORNING_BRIEF_LLM"] = "1"
    for provider in PROVIDERS:
        env_name = "MORNING_BRIEF_LLM_%s" % provider.upper()
        if providers.get(provider) is not True:
            os.environ[env_name] = "0"
        elif env_name not in os.environ:
            os.environ[env_name] = "1"
    return "ready"


def _bypass_config_state():
    """Bypass only a truly missing config; present corruption always fails closed."""
    try:
        with open(_config_path()) as handle:
            config = json.load(handle)
    except FileNotFoundError:
        return "bypass"
    except (OSError, ValueError):
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "uncalibrated"
    if (not isinstance(config, dict) or config.get("schema") !=
            "mission-control/outcome-extractor-config/v1"):
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "uncalibrated"
    if config.get("enabled") is False:
        os.environ["MORNING_BRIEF_LLM"] = "0"
        return "disabled"
    # A present config must pass the exact production validator. This also
    # applies its narrower provider scope before a sample/test can proceed.
    return _load_config_env()


def _write_run_marker(summary, status):
    marker = {
        "schema": "mission-control/outcome-extractor-run/v1",
        "run_id": "%d-%d" % (int(time.time()), os.getpid()),
        "completed_epoch": int(time.time()),
        "status": status,
        "scanned": int(summary.get("scanned") or 0),
        "eligible": int(summary.get("eligible") or 0),
        "calls": int(summary.get("calls") or 0),
        "successes": int(summary.get("successes") or 0),
        "cache_hits": int(summary.get("cache_hits") or 0),
        "deferred": int(summary.get("deferred") or 0),
        "failures": int(summary.get("failures") or 0),
        "budget_skips": int(summary.get("budget_skips") or 0),
        "uncalibrated_skips": int(summary.get("uncalibrated_skips") or 0),
        "provider_skips": int(summary.get("provider_skips") or 0),
        "disabled_skips": int(summary.get("disabled_skips") or 0),
        "privacy_skips": int(summary.get("privacy_skips") or 0),
        "backoff_skips": int(summary.get("backoff_skips") or 0),
        "escalations": int(summary.get("escalations") or 0),
    }
    _atomic_json(_run_marker_path(), marker, private_parent=True)


def _apply_calibration(path):
    try:
        with open(path) as handle:
            sample = json.load(handle)
    except (OSError, ValueError):
        raise ValueError("calibration file is unreadable or invalid")
    if not isinstance(sample, dict) or sample.get("schema") != (
            "mission-control/outcome-calibration/v1"):
        raise ValueError("calibration schema is invalid")
    observations = sample.get("observations")
    caps = sample.get("recommended_caps")
    if (not isinstance(observations, list) or not observations or
            not any(row.get("status") == "success" for row in observations
                    if isinstance(row, dict)) or not isinstance(caps, dict)):
        raise ValueError("calibration has no successful bounded sample")
    call_cap = caps.get("daily_call_cap")
    token_cap = caps.get("daily_token_cap")
    if (not isinstance(call_cap, int) or isinstance(call_cap, bool) or
            not isinstance(token_cap, int) or isinstance(token_cap, bool)):
        raise ValueError("calibration caps are invalid")
    if call_cap < 1 or token_cap < 1 or call_cap > 100 or token_cap > 10000000:
        raise ValueError("calibration caps are outside safe bounds")
    sampled_providers = {
        str(row.get("provider")) for row in observations
        if isinstance(row, dict) and row.get("status") == "success" and
        row.get("provider") in PROVIDERS
    }
    config = {
        "schema": "mission-control/outcome-extractor-config/v1",
        "enabled": True,
        "daily_call_cap": call_cap,
        "daily_token_cap": token_cap,
        "model": DEFAULT_MODEL,
        "escalation_model": DEFAULT_ESCALATION_MODEL,
        "providers": {provider: provider in sampled_providers for provider in PROVIDERS},
        "calibrated_at": int(time.time()),
        "calibration_fingerprint": _sha1(json.dumps(sample, sort_keys=True)),
        "sample_calls": int(sample.get("model_calls") or 0),
    }
    _atomic_json(_config_path(), config, private_parent=True)
    return config


def _set_enabled(enabled):
    try:
        with open(_config_path()) as handle:
            config = json.load(handle)
    except (OSError, ValueError):
        config = {}
    if not isinstance(config, dict) or config.get("schema") != (
            "mission-control/outcome-extractor-config/v1"):
        config = {
            "schema": "mission-control/outcome-extractor-config/v1",
            "model": DEFAULT_MODEL,
            "escalation_model": DEFAULT_ESCALATION_MODEL,
            "providers": {provider: True for provider in PROVIDERS},
        }
    config["enabled"] = bool(enabled)
    config["updated_at"] = int(time.time())
    _atomic_json(_config_path(), config, private_parent=True)
    return config


def _invoke_model(prompt, model, timeout_s):
    command = _model_command()
    if not (os.path.isfile(command) and os.access(command, os.X_OK)):
        return {"status": "unavailable", "latency_ms": 0}
    argv = [
        command, "-p", "--model", model, "--output-format", "json",
        "--json-schema", json.dumps(_RESULT_SCHEMA, sort_keys=True,
                                     separators=(",", ":")),
        "--no-session-persistence", "--tools", "",
    ]
    child_env = dict(os.environ)
    # The installed wrapper otherwise waits 900s for OAuth serialization while
    # this command times out much sooner. Force wrapper defer to happen first.
    child_env["CLAUDE_OAUTH_LOCK_TIMEOUT"] = str(max(1, min(60, timeout_s - 5)))
    started = time.monotonic()
    try:
        with tempfile.TemporaryFile(mode="w+b") as stdout_file, \
                tempfile.TemporaryFile(mode="w+b") as stderr_file:
            completed = subprocess.run(
                argv, input=prompt.encode("utf-8"), stdout=stdout_file,
                stderr=stderr_file, timeout=timeout_s, check=False, env=child_env)
            stdout_size = os.fstat(stdout_file.fileno()).st_size
            stderr_size = os.fstat(stderr_file.fileno()).st_size
            if stdout_size > MAX_MODEL_OUTPUT_BYTES or stderr_size > MAX_MODEL_OUTPUT_BYTES:
                return {"status": "output_too_large",
                        "latency_ms": int((time.monotonic() - started) * 1000)}
            stdout_file.seek(0); stderr_file.seek(0)
            stdout = stdout_file.read(MAX_MODEL_OUTPUT_BYTES).decode("utf-8", "replace")
            stderr = stderr_file.read(MAX_MODEL_OUTPUT_BYTES).decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return {"status": "failed", "latency_ms": int((time.monotonic() - started) * 1000)}
    latency = int((time.monotonic() - started) * 1000)
    if completed.returncode == 75 or "holds the OAuth lock" in stderr:
        return {"status": "deferred", "latency_ms": latency}
    if completed.returncode != 0:
        return {"status": "failed", "latency_ms": latency}
    try:
        outer = json.loads(stdout)
        if not isinstance(outer, dict) or outer.get("is_error"):
            raise ValueError("model result envelope")
        result = outer.get("structured_output")
        if result is None:
            result = outer.get("result")
            if isinstance(result, str):
                result = json.loads(result)
        if not isinstance(result, dict):
            raise ValueError("model result object")
        usage = outer.get("usage") if isinstance(outer.get("usage"), dict) else {}
        return {
            "status": "success", "result": result, "latency_ms": latency,
            "input_tokens": int(usage.get("input_tokens") or 0),
            "output_tokens": int(usage.get("output_tokens") or 0),
        }
    except (TypeError, ValueError, json.JSONDecodeError):
        return {"status": "failed", "latency_ms": latency}


def _sample_row(provider, model, response, estimated_input, status=None):
    return {
        "provider": provider,
        "model": model,
        "input_tokens": int(response.get("input_tokens") or estimated_input),
        "output_tokens": int(response.get("output_tokens") or 0),
        "latency_ms": int(response.get("latency_ms") or 0),
        "status": status or response["status"],
    }


def _map_codes(values, labels, counters, maximum):
    codes, prose = [], []
    if not isinstance(values, list):
        return codes, prose
    for code in values[:maximum]:
        if not isinstance(code, str) or code not in labels or code in codes:
            continue
        result = sanitize_text(labels[code], NARRATIVE, counters=counters)
        if result.dropped or not result.value.strip():
            continue
        codes.append(code)
        prose.append(result.value.strip())
    return codes, prose


def _clean_result(raw, allow_ambiguous_empty=False):
    if not isinstance(raw, dict):
        return None
    expected = {"did", "left_open", "needs_trevor", "confidence", "ambiguity"}
    if set(raw) != expected:
        return None
    if (not isinstance(raw["did"], list) or len(raw["did"]) > 4 or
            not isinstance(raw["left_open"], list) or len(raw["left_open"]) > 4 or
            not isinstance(raw["needs_trevor"], list) or len(raw["needs_trevor"]) > 3 or
            not isinstance(raw["ambiguity"], bool) or
            not isinstance(raw["confidence"], (int, float)) or
            isinstance(raw["confidence"], bool) or
            not math.isfinite(float(raw["confidence"])) or
            not 0 <= raw["confidence"] <= 1):
        return None
    for values, labels in ((raw["did"], _DID_LABELS),
                           (raw["left_open"], _OPEN_LABELS),
                           (raw["needs_trevor"], _NEEDS_LABELS)):
        if any(not isinstance(code, str) or code not in labels for code in values):
            return None
    counters = EgressCounters()
    did_codes, did = _map_codes(raw["did"], _DID_LABELS, counters, 4)
    open_codes, left_open = _map_codes(raw["left_open"], _OPEN_LABELS, counters, 4)
    needs_codes, needs_trevor = _map_codes(
        raw["needs_trevor"], _NEEDS_LABELS, counters, 3)
    clean = {
        "did": did, "left_open": left_open, "needs_trevor": needs_trevor,
        "did_codes": did_codes, "left_open_codes": open_codes,
        "needs_trevor_codes": needs_codes,
        "confidence": 0.0,
        "ambiguity": raw["ambiguity"],
        "egress_counters": counters.snapshot(),
    }
    clean["confidence"] = max(0.0, min(0.79, float(raw["confidence"])))
    if not clean["did"] and not (allow_ambiguous_empty and clean["ambiguity"]):
        return None
    return clean


def _high_value_rows(graph, candidates):
    """Read candidate graph evidence, then close before any model work."""
    values = {}
    con = graph.connect()
    try:
        for provider, sid, _source, _mtime, tier1, _messages in candidates:
            row = con.execute("SELECT repo FROM sessions WHERE id=?", (sid,)).fetchone()
            repo = str(row["repo"] or "").strip() if row else ""
            edge = con.execute("""SELECT 1 FROM edges
                WHERE status='active' AND type IN ('spawned','audits','continues')
                  AND (src=? OR dst=?) LIMIT 1""", (sid, sid)).fetchone()
            commits = tier1.get("anchors", {}).get("commits") or []
            if repo or edge or commits:
                values[(provider, sid)] = {
                    "repo": repo,
                    "reasons": [name for name, present in (
                        ("repo", bool(repo)), ("lineage", bool(edge)),
                        ("commit", bool(commits))) if present],
                }
    finally:
        con.close()
    return values


def _order_candidates(graph, candidates):
    """Prefer never-attempted tails, then the least-recently attempted work."""
    con = graph.connect()
    try:
        attempted = {}
        for row in con.execute("""SELECT provider,session_id,tail_hash,
            MAX(last_attempt_at) AS last_attempt_at FROM outcome_extraction_attempts
            GROUP BY provider,session_id,tail_hash"""):
            attempted[(row["provider"], row["session_id"], row["tail_hash"])] = int(
                row["last_attempt_at"] or 0)
    finally:
        con.close()

    def key(row):
        provider, sid, _source, mtime_ns, tier1, _messages = row
        last = attempted.get((provider, sid, tier1["tail_hash"]))
        return (1 if last is not None else 0, last or 0, -int(mtime_ns))

    return sorted(candidates, key=key)


def _persist_current_tier1(graph, sid, provider, messages, source):
    """Guarantee the exact source tail has a deterministic fallback version."""
    con = graph.connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        card = graph._persist_tier1_outcome(
            con, sid, provider, messages,
            source.get("path") if isinstance(source, dict) else "provider-state")
        con.commit()
        return card
    finally:
        con.close()


def _cache_lookup(graph, cache_key):
    con = graph.connect()
    try:
        row = con.execute("SELECT result_json,model FROM outcome_extraction_cache WHERE cache_key=?",
                          (cache_key,)).fetchone()
        value = json.loads(row["result_json"]) if row else None
        return (value, str(row["model"] or DEFAULT_MODEL)) if isinstance(value, dict) else None
    except (TypeError, ValueError):
        return None
    finally:
        con.close()


def _delete_cache(graph, cache_key):
    con = graph.connect()
    try:
        con.execute("DELETE FROM outcome_extraction_cache WHERE cache_key=?", (cache_key,))
        con.commit()
    finally:
        con.close()


def _observe_tier1(graph, sid, tail_hash):
    """Make deterministic evidence current after a failed enrichment attempt."""
    now = int(time.time())
    con = graph.connect()
    try:
        row = con.execute("""SELECT id,finalized,evidence_fingerprint
            FROM session_outcomes WHERE session_id=? AND tail_hash=? AND method='tier1'
            ORDER BY COALESCE(created_at,updated_at,0) DESC LIMIT 1""",
                          (sid, tail_hash)).fetchone()
        if row is None:
            return
        latest = con.execute("""SELECT outcome_id FROM session_outcome_observations
            WHERE session_id=? ORDER BY observation_id DESC LIMIT 1""", (sid,)).fetchone()
        if latest is not None and latest["outcome_id"] == row["id"]:
            return
        con.execute("""INSERT INTO session_outcome_observations(
            session_id,outcome_id,tail_hash,observed_at,finalized,evidence_fingerprint)
            VALUES(?,?,?,?,?,?)""", (
                sid, row["id"], tail_hash, now, int(row["finalized"] or 0),
                row["evidence_fingerprint"]))
        con.commit()
    finally:
        con.close()


def _retry_blocked(graph, sid, provider, tail_hash, variant):
    con = graph.connect()
    try:
        row = con.execute("""SELECT next_retry_at FROM outcome_extraction_attempts
            WHERE session_id=? AND provider=? AND tail_hash=? AND variant=?""",
                          (sid, provider, tail_hash, variant)).fetchone()
        return bool(row and int(row["next_retry_at"] or 0) > int(time.time()))
    finally:
        con.close()


def _record_attempt(graph, sid, provider, tail_hash, variant, status, delay_s):
    now = int(time.time())
    con = graph.connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        con.execute("""INSERT INTO outcome_extraction_attempts(
            session_id,provider,tail_hash,variant,last_status,attempts,
            last_attempt_at,next_retry_at) VALUES(?,?,?,?,?,1,?,?)
            ON CONFLICT(session_id,provider,tail_hash,variant) DO UPDATE SET
              last_status=excluded.last_status,
              attempts=outcome_extraction_attempts.attempts+1,
              last_attempt_at=excluded.last_attempt_at,
              next_retry_at=excluded.next_retry_at""", (
                  sid, provider, tail_hash, variant, status, now, now + int(delay_s)))
        con.commit()
    finally:
        con.close()


def _clear_attempt(graph, sid, provider, tail_hash, variant):
    con = graph.connect()
    try:
        con.execute("DELETE FROM outcome_extraction_attempts WHERE "
                    "session_id=? AND provider=? AND tail_hash=? AND variant=?",
                    (sid, provider, tail_hash, variant))
        con.commit()
    finally:
        con.close()


def _build_card(tier1, clean, model, metadata, result_status, prompt_version):
    card = json.loads(json.dumps(tier1, ensure_ascii=True))
    card["did"] = list(clean["did"])
    card["left_open"] = list(clean["left_open"])
    card["inferred_needs_trevor"] = list(clean["needs_trevor"])
    card["did_codes"] = list(clean["did_codes"])
    card["left_open_codes"] = list(clean["left_open_codes"])
    card["inferred_needs_trevor_codes"] = list(clean["needs_trevor_codes"])
    card["open_work"] = [dict(item, trust="structured", source_method="tier1")
                         for item in tier1.get("open_work") or []
                         if isinstance(item, dict)]
    card["method"] = "tier2"
    card["provenance"] = "inferred"
    card["confidence"] = clean["confidence"]
    card["ambiguity"] = bool(clean["ambiguity"])
    card["extraction_status"] = "llm_success"
    card["model_metadata"] = {
        "source_provider": metadata["source_provider"],
        "messages_selected": metadata["messages_selected"],
        "bytes_selected": metadata["bytes_selected"],
        "model": model,
        "extractor_version": EXTRACTOR_VERSION,
        "prompt_version": prompt_version,
        "egress_policy_version": EGRESS_POLICY_VERSION,
        "result_status": result_status,
        "egress_counters": metadata["egress_counters"],
    }
    evidence = {
        "did": card["did"], "left_open": card["left_open"],
        "inferred_needs_trevor": card["inferred_needs_trevor"],
        "anchors": card.get("anchors") or {},
    }
    card["evidence_fingerprint"] = _sha1(json.dumps(evidence, sort_keys=True))
    card.pop("resolution_markers", None)
    return card


def _persist(graph, sid, provider, tier1, card, cache_key, clean, model, metadata):
    now = int(time.time())
    version_id = _sha1("outcome-version-tier2:%s:%s:%s" % (
        sid, tier1["tail_hash"], cache_key))
    con = graph.connect()
    try:
        con.execute("BEGIN IMMEDIATE")
        exists = con.execute("SELECT id FROM session_outcomes WHERE id=?", (version_id,)).fetchone()
        if not exists:
            con.execute("""INSERT INTO session_outcomes(
                id,session_id,provider,tail_hash,outcome_json,extraction_status,
                finalized,updated_at,method,variant,confidence,source_start,source_end,
                source_span,evidence_fingerprint,created_at)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""", (
                    version_id, sid, provider, tier1["tail_hash"],
                    json.dumps(card, ensure_ascii=True, sort_keys=True),
                    card["extraction_status"], 1 if card.get("finalized") else 0,
                    now, "tier2", cache_key, card["confidence"], "sanitized-assistant-tail",
                    "sanitized-assistant-tail-end",
                    json.dumps(card.get("source_span") or {}, sort_keys=True),
                    card["evidence_fingerprint"], now))
        latest = con.execute("""SELECT outcome_id FROM session_outcome_observations
            WHERE session_id=? ORDER BY observation_id DESC LIMIT 1""", (sid,)).fetchone()
        if latest is None or latest["outcome_id"] != version_id:
            con.execute("""INSERT INTO session_outcome_observations(
                session_id,outcome_id,tail_hash,observed_at,finalized,evidence_fingerprint)
                VALUES(?,?,?,?,?,?)""", (
                    sid, version_id, tier1["tail_hash"], now,
                    1 if card.get("finalized") else 0, card["evidence_fingerprint"]))
        cache_result = {
            "did": list(clean["did_codes"]),
            "left_open": list(clean["left_open_codes"]),
            "needs_trevor": list(clean["needs_trevor_codes"]),
            "confidence": float(clean["confidence"]),
            "ambiguity": bool(clean["ambiguity"]),
        }
        con.execute("""INSERT OR REPLACE INTO outcome_extraction_cache(
            cache_key,session_id,provider,model,sanitized_tail_hash,result_json,
            created_at,updated_at) VALUES(?,?,?,?,?,?,COALESCE((SELECT created_at
            FROM outcome_extraction_cache WHERE cache_key=?),?),?)""", (
                cache_key, sid, provider, model, metadata["sanitized_tail_hash"],
                json.dumps(cache_result, ensure_ascii=True, sort_keys=True),
                cache_key, now, now))
        con.commit()
    finally:
        con.close()


def _parse_args(args):
    parser = argparse.ArgumentParser(prog="chat-graph extract-outcomes")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--sample-per-provider", type=int, default=0)
    parser.add_argument("--calibration-out",
                        default="/tmp/morning-brief-outcome-calibration.json")
    parser.add_argument("--apply-calibration")
    parser.add_argument("--set-enabled", choices=("0", "1"))
    parsed = parser.parse_args(args)
    if parsed.days < 1 or parsed.days > 365:
        parser.error("--days must be between 1 and 365")
    if parsed.limit < 1 or parsed.limit > 500:
        parser.error("--limit must be between 1 and 500")
    if parsed.sample_per_provider < 0 or parsed.sample_per_provider > 3:
        parser.error("--sample-per-provider must be between 0 and 3")
    state_actions = int(bool(parsed.apply_calibration)) + int(parsed.set_enabled is not None)
    if state_actions > 1 or (state_actions and parsed.sample_per_provider):
        parser.error("configuration actions cannot be combined with a live sample")
    return parsed


def run(graph, args):
    parsed = _parse_args(args)
    if parsed.apply_calibration:
        try:
            config = _apply_calibration(parsed.apply_calibration)
        except ValueError as error:
            print("chat-graph: %s" % error, file=os.sys.stderr)
            return 2
        result = {
            "schema": 1, "mode": "apply_calibration", "applied": True,
            "config_path": _config_path(),
            "daily_call_cap": config["daily_call_cap"],
            "daily_token_cap": config["daily_token_cap"],
        }
        print(json.dumps(result, sort_keys=True) if parsed.json else
              "chat-graph: applied private outcome extraction calibration")
        return 0
    if parsed.set_enabled is not None:
        config = _set_enabled(parsed.set_enabled == "1")
        result = {
            "schema": 1, "mode": "set_enabled", "enabled": config["enabled"],
            "config_path": _config_path(),
        }
        print(json.dumps(result, sort_keys=True) if parsed.json else
              "chat-graph: Tier 2 %s" % ("enabled" if config["enabled"] else "disabled"))
        return 0
    sample_mode = parsed.sample_per_provider > 0
    testing_mode = _flag("MORNING_BRIEF_LLM_TESTING", False)
    config_state = (_bypass_config_state() if sample_mode or testing_mode else
                    _load_config_env())
    initial = graph.connect()
    initial.commit()
    initial.close()
    summary = {
        "schema": 1, "mode": "extract", "scanned": 0, "eligible": 0,
        "calls": 0, "successes": 0, "cache_hits": 0, "deferred": 0,
        "failures": 0, "budget_skips": 0, "provider_skips": 0,
        "disabled_skips": 0, "uncalibrated_skips": 0, "privacy_skips": 0,
        "backoff_skips": 0,
        "escalations": 0, "lock_skip": False, "selected": 0,
    }
    sample_observations = []
    if config_state == "uncalibrated":
        summary["budget_skips"] = 1
        summary["uncalibrated_skips"] = 1
        _health(graph, "uncalibrated", budget_skips=1, uncalibrated_skips=1)
        _write_run_marker(summary, "uncalibrated")
        if parsed.json:
            print(json.dumps(summary, sort_keys=True))
        else:
            print("chat-graph: Tier 2 uncalibrated; Tier 1 remains active")
        return 0
    if config_state == "disabled" or not _flag("MORNING_BRIEF_LLM", True):
        summary["disabled_skips"] = 1
        _health(graph, "disabled", disabled_skips=1)
        _write_run_marker(summary, "disabled")
        if parsed.json:
            print(json.dumps(summary, sort_keys=True))
        else:
            print("chat-graph: Tier 2 disabled; Tier 1 remains active")
        return 0
    if not _acquire_lock(graph):
        summary["lock_skip"] = True
        _health(graph, "lock_skip", lock_skips=1)
        _write_run_marker(summary, "lock_skip")
        if parsed.json:
            print(json.dumps(summary, sort_keys=True))
        else:
            print("chat-graph: outcome extraction lock held; deferred")
        return 0

    try:
        sources, _status = recent_sources(
            parsed.days, max_messages=graph.TIER1_MAX_MESSAGES,
            env_prefix="OUTCOME_EXTRACTOR")
        candidates = []
        for provider, sid, source, mtime_ns in sources:
            try:
                messages = read_messages(source, graph.read_assistant_messages)
                tier1 = graph.tier1_parse_outcome(sid, provider, messages)
            except (OSError, UnicodeDecodeError, ValueError):
                continue
            summary["scanned"] += 1
            if tier1.get("source_span", {}).get("message_count"):
                candidates.append((provider, sid, source, mtime_ns, tier1, messages))
        high_value = _high_value_rows(graph, candidates)
        selected = _order_candidates(
            graph, [row for row in candidates if (row[0], row[1]) in high_value])
        summary["eligible"] = len(selected)
        if sample_mode:
            per_provider = {provider: 0 for provider in PROVIDERS}
            bounded = []
            for row in selected:
                if per_provider[row[0]] >= parsed.sample_per_provider:
                    continue
                per_provider[row[0]] += 1
                bounded.append(row)
            selected = bounded
        persisted = []
        for provider, sid, source, mtime_ns, tier1, messages in selected:
            current_tier1 = _persist_current_tier1(
                graph, sid, provider, messages, source)
            if current_tier1 is not None:
                persisted.append((provider, sid, source, mtime_ns,
                                  current_tier1, messages))
        selected = persisted
        timeout_s = _int_env("MORNING_BRIEF_LLM_TIMEOUT", 120, minimum=6, maximum=900)
        max_output = DEFAULT_MAX_OUTPUT_TOKENS
        haiku_model = DEFAULT_MODEL
        sonnet_model = DEFAULT_ESCALATION_MODEL
        prompt_version = _prompt_version()

        for provider, sid, _source, _mtime_ns, tier1, messages in selected:
            if summary["calls"] >= parsed.limit:
                break
            summary["selected"] += 1
            if not _flag("MORNING_BRIEF_LLM_%s" % provider.upper(), True):
                summary["provider_skips"] += 1
                _health(graph, "provider_skip", provider_skips=1)
                continue
            packet, metadata = _sanitized_packet(graph, provider, messages)
            if not packet["messages"]:
                summary["privacy_skips"] += 1
                _health(graph, "privacy_skip", privacy_skips=1)
                continue
            cache_key = _sha1(json.dumps({
                "extractor": EXTRACTOR_VERSION, "prompt": prompt_version,
                "egress_policy": EGRESS_POLICY_VERSION, "session_id": sid,
                "provider": provider, "tail": metadata["sanitized_tail_hash"],
                "haiku": haiku_model, "sonnet": sonnet_model,
            }, sort_keys=True))
            cached = _cache_lookup(graph, cache_key)
            if cached:
                cached_result, cached_model = cached
                revalidated = _clean_result(cached_result)
                if revalidated is None or revalidated["ambiguity"]:
                    _delete_cache(graph, cache_key)
                    _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                    "cache_rejected", FAILURE_RETRY_S)
                    _observe_tier1(graph, sid, tier1["tail_hash"])
                    summary["privacy_skips"] += 1
                    _health(graph, "cache_rejected", privacy_skips=1)
                    continue
                revalidated["model"] = cached_model
                summary["cache_hits"] += 1
                _health(graph, "cache_hit", cache_hits=1)
                card = _build_card(tier1, revalidated, cached_model, metadata,
                                   "cache_hit", prompt_version)
                _persist(graph, sid, provider, tier1, card, cache_key, revalidated,
                         cached_model, metadata)
                _clear_attempt(graph, sid, provider, tier1["tail_hash"], cache_key)
                continue

            if _retry_blocked(graph, sid, provider, tier1["tail_hash"], cache_key):
                _observe_tier1(graph, sid, tier1["tail_hash"])
                summary["backoff_skips"] += 1
                _health(graph, "backoff_skip", backoff_skips=1)
                continue

            prompt = _prompt(packet)
            estimated_input = int(math.ceil(len(prompt.encode("utf-8")) / 4.0)) + 512
            sample_call_cap = parsed.sample_per_provider * len(PROVIDERS)
            sample_token_cap = max(100000, sample_call_cap * (estimated_input + max_output))
            reservation = _reserve_budget(
                    graph, estimated_input, max_output,
                    call_cap_override=sample_call_cap if sample_mode else None,
                    token_cap_override=sample_token_cap if sample_mode else None)
            if reservation != "reserved":
                _observe_tier1(graph, sid, tier1["tail_hash"])
                summary["budget_skips"] += 1
                if reservation == "uncalibrated":
                    summary["uncalibrated_skips"] += 1
                break
            summary["calls"] += 1
            response = _invoke_model(prompt, haiku_model, timeout_s)
            if response["status"] == "deferred":
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, haiku_model, response, estimated_input))
                summary["deferred"] += 1
                _finish_call(graph, "deferred", estimated_input,
                             latency_ms=response["latency_ms"], deferred=1)
                _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                "deferred", DEFER_RETRY_S)
                _observe_tier1(graph, sid, tier1["tail_hash"])
                continue
            if response["status"] != "success":
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, haiku_model, response, estimated_input))
                summary["failures"] += 1
                _finish_call(graph, response["status"], estimated_input,
                             latency_ms=response.get("latency_ms", 0), failures=1)
                _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                response["status"], FAILURE_RETRY_S)
                _observe_tier1(graph, sid, tier1["tail_hash"])
                continue
            clean = _clean_result(response["result"], allow_ambiguous_empty=True)
            if clean is None:
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, haiku_model, response, estimated_input,
                        status="invalid_result"))
                summary["failures"] += 1
                _finish_call(graph, "invalid_result", estimated_input,
                             actual_input=response.get("input_tokens") or estimated_input,
                             actual_output=response.get("output_tokens") or 0,
                             latency_ms=response["latency_ms"], failures=1)
                _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                "invalid_result", FAILURE_RETRY_S)
                _observe_tier1(graph, sid, tier1["tail_hash"])
                continue
            actual_input = response.get("input_tokens") or estimated_input
            actual_output = response.get("output_tokens") or 0
            model = haiku_model

            if clean["ambiguity"]:
                _finish_call(graph, "ambiguous", estimated_input,
                             actual_input=actual_input, actual_output=actual_output,
                             latency_ms=response["latency_ms"])
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, haiku_model, response, estimated_input,
                        status="ambiguous"))
                if summary["calls"] >= parsed.limit:
                    summary["deferred"] += 1
                    _health(graph, "ambiguity_deferred", deferred=1)
                    _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                    "ambiguity_deferred", DEFER_RETRY_S)
                    _observe_tier1(graph, sid, tier1["tail_hash"])
                    continue
                second_estimate = estimated_input
                second_reservation = _reserve_budget(
                        graph, second_estimate, max_output,
                        call_cap_override=sample_call_cap if sample_mode else None,
                        token_cap_override=sample_token_cap if sample_mode else None)
                if second_reservation != "reserved":
                    summary["budget_skips"] += 1
                    if second_reservation == "uncalibrated":
                        summary["uncalibrated_skips"] += 1
                    _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                    "ambiguity_budget", DEFER_RETRY_S)
                    _observe_tier1(graph, sid, tier1["tail_hash"])
                    break
                summary["calls"] += 1
                summary["escalations"] += 1
                _health(graph, "escalating", escalations=1)
                second = _invoke_model(prompt, sonnet_model, timeout_s)
                if second["status"] == "deferred":
                    if sample_mode:
                        sample_observations.append(_sample_row(
                            provider, sonnet_model, second, second_estimate))
                    summary["deferred"] += 1
                    _finish_call(graph, "deferred", second_estimate,
                                 latency_ms=second["latency_ms"], deferred=1)
                    _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                    "deferred", DEFER_RETRY_S)
                    _observe_tier1(graph, sid, tier1["tail_hash"])
                    continue
                second_clean = (_clean_result(second["result"], allow_ambiguous_empty=True)
                                if second["status"] == "success" else None)
                if second_clean is None or second_clean["ambiguity"]:
                    failure_status = ("ambiguity_unresolved" if second_clean is not None else
                                      "invalid_result" if second["status"] == "success" else
                                      second["status"])
                    if sample_mode:
                        sample_observations.append(_sample_row(
                            provider, sonnet_model, second, second_estimate,
                            status=failure_status))
                    summary["failures"] += 1
                    _finish_call(
                        graph, failure_status, second_estimate,
                        actual_input=(second.get("input_tokens") or second_estimate)
                        if second["status"] == "success" else None,
                        actual_output=second.get("output_tokens") or 0,
                        latency_ms=second.get("latency_ms", 0), failures=1)
                    _record_attempt(graph, sid, provider, tier1["tail_hash"], cache_key,
                                    failure_status, FAILURE_RETRY_S)
                    _observe_tier1(graph, sid, tier1["tail_hash"])
                    continue
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, sonnet_model, second, second_estimate,
                        status="success"))
                _finish_call(
                    graph, "success", second_estimate,
                    actual_input=second.get("input_tokens") or second_estimate,
                    actual_output=second.get("output_tokens") or 0,
                    latency_ms=second["latency_ms"])
                clean, model = second_clean, sonnet_model
            else:
                _finish_call(graph, "success", estimated_input, actual_input=actual_input,
                             actual_output=actual_output, latency_ms=response["latency_ms"])
                if sample_mode:
                    sample_observations.append(_sample_row(
                        provider, haiku_model, response, estimated_input,
                        status="success"))

            clean["model"] = model
            card = _build_card(tier1, clean, model, metadata, "success", prompt_version)
            _persist(graph, sid, provider, tier1, card, cache_key, clean, model, metadata)
            _clear_attempt(graph, sid, provider, tier1["tail_hash"], cache_key)
            summary["successes"] += 1
            _health(graph, "success", successes=1)
    finally:
        _release_lock(graph)

    if sample_mode:
        successful = [row for row in sample_observations if row["status"] == "success"]
        totals = sorted(row["input_tokens"] + row["output_tokens"] for row in successful)
        p95 = totals[max(0, int(math.ceil(len(totals) * 0.95)) - 1)] if totals else 0
        modeled_calls_day = float(summary["eligible"]) / float(parsed.days)
        uncapped_calls = max(1, int(math.ceil(modeled_calls_day * 2.0)))
        recommended_calls = min(100, uncapped_calls)
        uncapped_tokens = max(p95, recommended_calls * p95 * 2) if p95 else 0
        recommended_tokens = min(10000000, uncapped_tokens)
        calibration = {
            "schema": "mission-control/outcome-calibration/v1",
            "generated_epoch": int(time.time()),
            "window_days": parsed.days,
            "eligible_sessions": summary["eligible"],
            "model_calls": len(sample_observations),
            "observations": sample_observations,
            "observed_p95_tokens_per_call": p95,
            "modeled_calls_per_day": round(modeled_calls_day, 3),
            "hard_cap_limited": (recommended_calls != uncapped_calls or
                                 recommended_tokens != uncapped_tokens),
            "recommended_caps": {
                "daily_call_cap": recommended_calls,
                "daily_token_cap": recommended_tokens,
            },
            "default_model": haiku_model,
            "escalation_model": sonnet_model,
            "basis": "bounded provider sample plus two-times modeled headroom",
        }
        _atomic_json(parsed.calibration_out, calibration)
        summary["calibration_path"] = os.path.abspath(parsed.calibration_out)

    marker_status = (
        "completed_with_failures" if summary["failures"] else
        "uncalibrated" if summary["uncalibrated_skips"] else
        "budget_limited" if summary["budget_skips"] else
        "deferred" if summary["deferred"] and not summary["successes"] else
        "backoff" if summary["backoff_skips"] and not summary["successes"] else
        "provider_limited" if summary["provider_skips"] and not summary["successes"] else
        "privacy_limited" if summary["privacy_skips"] and not summary["successes"] else
        "completed")
    _write_run_marker(summary, marker_status)

    if parsed.json:
        print(json.dumps(summary, sort_keys=True))
    else:
        print("chat-graph: Tier 2 %d success, %d cache, %d deferred, %d failed" % (
            summary["successes"], summary["cache_hits"], summary["deferred"],
            summary["failures"]))
    return 0
