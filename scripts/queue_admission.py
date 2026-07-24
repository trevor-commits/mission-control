#!/usr/bin/env python3
"""Phase 0 item 0.3 — decision-queue admission classification, rollup, and
domain/severity tagging for the Mission Control operator-decision queue.

AUTHORITY INVARIANT (hard, non-negotiable): this module MUST NOT import
subprocess, MUST NOT call os.system/os.exec*/os.popen, and MUST NOT call
eval/exec/compile on anything derived from decision text or action_argv.
Classification output (admission_class, domain, severity, required_action,
work-order packets) is ADVISORY METADATA ONLY. A WorkOrder packet is a
pointer a downstream system MAY consider under ITS OWN policy; nothing here
executes, dispatches, or shells out based on queue content. This is enforced
structurally (grep the imports below — there is no subprocess/os.system/exec
path in this file) and confirmed by queue_admission.test.py, which (a)
statically scans this file's source for the forbidden tokens and (b) feeds a
decision whose text looks like a shell command through the full classify +
rollup + packet pipeline and asserts nothing executes and a normal
classification comes back.

Python standard library only. No I/O in the classification functions
themselves (normalize_text / classify_admission / classify_domain /
classify_severity / classify_row / rollup / same_equivalence / build_
workorder_packet) — they take plain dicts/strings and return plain
dicts/strings. The small CLI at the bottom does file/sqlite I/O and is the
only place that touches disk.
"""

from __future__ import print_function

import argparse
import json
import re
import sqlite3
import sys
import time


SCHEMA = 1

# ---------------------------------------------------------------------------
# Vocabulary (deterministic, explainable — every classification decision
# names the rule that fired so a human can audit *why*).
# ---------------------------------------------------------------------------

ADMISSION_CLASSES = ("noop", "workorder", "operator_decision")
DOMAINS = ("business", "personal", "infra", "faith-personal-projects")
SEVERITIES = ("normal", "security")

# Anything mentioning a credential/secret surface routes to a human,
# unconditionally. This is the single most safety-critical rule in the file:
# false positives (routing a non-credential item to a human) are cheap;
# false negatives (letting a credential-bearing item slip toward WorkOrder,
# which could reach an unattended dispatch path) are not. Fail toward the
# human on any ambiguity here.
_CREDENTIAL_GATE_RE = re.compile(
    r"\b(password|credential|api\s+key|security\s+key|secret|token|"
    r"2fa|passkey|touch\s*id|sign\s+in|log\s*in|authoriz\w*|oauth)\b",
    re.IGNORECASE,
)

# A forced multiple-choice presentation (what the dashboard renders as
# "DECISION NEEDED" cards today) is definitionally something only Trevor can
# resolve — a choice among options is an act of judgment, not dispatch.
_DECISION_NEEDED_RE = re.compile(r"decision\s+needed\s*:", re.IGNORECASE)
_BOLD_BACKTICK_OPTION_RE = re.compile(r"\*\*`([^`]+)`\*\*")
_BOLD_LABEL_OPTION_RE = re.compile(r"\*\*([^*]{2,80})\*\*")

# Verbs that indicate *something* actionable is being asked of the reader.
# Absence of all of these plus no "?" means the row is read-only narrative
# (a status update that happened to land in the needs_you section) rather
# than a live ask — that is the NoOp case.
_ACTION_VERB_RE = re.compile(
    r"\b(choose|confirm|approve|reply|tell\s+me|send|rotate|restart|fix|"
    r"implement|run\b|merge|deploy|dismiss|answer|decide|select|enter|"
    r"click|pick\s+one)\b",
    re.IGNORECASE,
)

# Severity=security requires evidence of an *active exposure/incident*, not
# merely a security-adjacent topic (e.g. routine 2FA enrollment is
# credential-related but not an incident — it must NOT bypass the queue).
_SECURITY_INCIDENT_RE = re.compile(
    r"\b(leak(?:ed)?|expos(?:ed|ure)|breach(?:ed)?|compromis(?:ed|e)|"
    r"inadvertently\s+print\w*|credential\s+exposure|"
    r"rotate\w*\s+(?:the\s+|a\s+|an\s+)?\w*\s*(?:api\s+)?"
    r"(?:key|credential|token|password))\b",
    re.IGNORECASE,
)

_FAITH_RE = re.compile(
    r"\b(jw[\s-]study|jehovah|congregation|kingdom\s+hall|scripture|"
    r"\belder\b|ministry|theocratic|watchtower)\b", re.IGNORECASE)
_BUSINESS_RE = re.compile(
    r"\b(clearpath|leads?\s+dashboard|customer|invoice|quickbooks|"
    r"property-intelligence|grant\s+eligibility|revenue|payroll|sales\b|"
    r"\bclient\b)\b", re.IGNORECASE)
_PERSONAL_RE = re.compile(
    r"\btravel(?:l?ers?|ing)?\b|\bitinerary\b|\bpacking\b|\bvacation\b|"
    r"\btrip\b|\bzip\s+code\b|\bheadquarters\s+city\b|\bwife\b|\bfamily\b|"
    r"\bspouse\b", re.IGNORECASE)

_BACKTICK_TOKEN_RE = re.compile(r"`([A-Za-z0-9/_.\-]+)`")
_DEADLINE_HINT_RE = re.compile(
    r"\b(today|tonight|tomorrow|eod|end of day|by \w+day)\b", re.IGNORECASE)


def normalize_text(text):
    """Equivalence-contract normalization for PRESENTATION rollup.

    Two rows are "the same question" for rollup purposes iff
    normalize_text(a) == normalize_text(b) — EXACT string equality after
    this transform, never fuzzy/similarity matching.

    Steps, in order:
      1. Coerce to str, strip leading/trailing whitespace.
      2. Casefold (locale-independent lowercase).
      3. Strip markdown emphasis markers: ``**``, ``__``, and backticks.
      4. Strip one leading "decision needed:" prefix, case-insensitive.
      5. Collapse all whitespace runs (including newlines) to one space.
      6. Strip again.

    No stemming, no punctuation folding beyond the above, no edit-distance
    matching. A one-word difference (a different branch name, a different
    number) normalizes UNEQUAL and stays a separate card — "when in doubt,
    separate cards" is enforced by doing the least possible normalization.
    """
    if text is None:
        return ""
    value = str(text).strip().casefold()
    value = value.replace("**", "").replace("__", "").replace("`", "")
    value = re.sub(r"^\s*decision needed:\s*", "", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def _extract_options(text):
    raw = str(text or "")
    matches = _BOLD_BACKTICK_OPTION_RE.findall(raw)
    if matches:
        return matches[:3]
    out = []
    for m in _BOLD_LABEL_OPTION_RE.finditer(raw):
        label = m.group(1).strip("` ")
        if re.search(r"decision needed|confirmed|recommend", label, re.I):
            continue
        out.append(label)
        if len(out) == 3:
            break
    return out


def classify_admission(text):
    """Deterministic admission classification. Returns (class, rule_id).

    Rule order (first match wins — evaluated top to bottom):
      1. credential_or_secret_reference -> operator_decision
         Any credential/secret/auth surface mentioned anywhere in the text.
         Fail toward the human: never let a credential-bearing row become a
         WorkOrder that could reach an unattended dispatch path.
      2. forced_choice_presented -> operator_decision
         "DECISION NEEDED:" or >=1 bold/backtick option block present — the
         row is a judgment call among options, not a bounded task.
      3. informational_no_action_verb -> noop
         No "?" and none of the action-verb vocabulary present anywhere —
         the row is a status update, not a live ask.
      4. bounded_directive_no_choice -> workorder
         An action verb is present, no forced choice, no credential surface
         — a single-path directive that could in principle be dispatched.
      5. unclassifiable_fail_to_human -> operator_decision
         Fallback. Unclassifiable always fails toward the human, never
         toward WorkOrder.
    """
    raw = str(text or "")
    if _CREDENTIAL_GATE_RE.search(raw):
        return "operator_decision", "credential_or_secret_reference"
    if _DECISION_NEEDED_RE.search(raw) or _extract_options(raw):
        return "operator_decision", "forced_choice_presented"
    has_question = "?" in raw
    has_action_verb = bool(_ACTION_VERB_RE.search(raw))
    if not has_question and not has_action_verb:
        return "noop", "informational_no_action_verb"
    if has_action_verb:
        return "workorder", "bounded_directive_no_choice"
    return "operator_decision", "unclassifiable_fail_to_human"


def classify_domain(text):
    """Deterministic domain classification. Returns (domain, rule_id).

    Priority order (first match wins): faith-personal-projects, business,
    personal, then infra as the default (no keyword list needed for infra —
    it is what remains when none of the more specific domains match, which
    is correct for a coding/ops queue where most rows ARE infra).
    """
    raw = str(text or "")
    if _FAITH_RE.search(raw):
        return "faith-personal-projects", "faith_keyword_match"
    if _BUSINESS_RE.search(raw):
        return "business", "business_keyword_match"
    if _PERSONAL_RE.search(raw):
        return "personal", "personal_keyword_match"
    return "infra", "default_infra_no_specific_keyword"


def classify_severity(text):
    """Deterministic severity classification. Returns (severity, rule_id).

    "security" requires evidence of an ACTIVE incident (leak/exposure/
    breach/compromise/rotate-a-credential language) — not merely that the
    topic touches credentials. Routine credential handling (e.g. enrolling
    a 2FA security key) is severity=normal even though it also trips the
    admission credential gate; those are two independent axes on purpose.
    """
    raw = str(text or "")
    if _SECURITY_INCIDENT_RE.search(raw):
        return "security", "active_exposure_language"
    return "normal", "no_incident_signal"


def _required_action(admission_class, severity, admission_rule):
    if severity == "security":
        return "rotate/contain credential now — do not wait for the queue"
    if admission_class == "operator_decision":
        if admission_rule == "credential_or_secret_reference":
            return "complete the credential/authorization step yourself"
        if admission_rule == "forced_choice_presented":
            return "choose one of the presented options"
        return "review and decide — could not classify further"
    if admission_class == "workorder":
        return "dispatchable — pointer routed to the autonomous loop"
    return "none — informational, no action required"


def _extract_deadline(text):
    m = _DEADLINE_HINT_RE.search(str(text or ""))
    return m.group(0).strip().casefold() if m else None


def classify_row(text):
    """Compute every advisory field for one decision row's text.

    This is the SINGLE function used both by the read-only `derive` staging
    tool (proving behavior against the live store without mutating it) and
    by the write path (decision-alert's ingest(), when the conductor wires
    this module in) that stamps new rows at intake time. Using one function
    for both guarantees the staging proof predicts deployed behavior.
    """
    admission_class, admission_rule = classify_admission(text)
    domain, domain_rule = classify_domain(text)
    severity, severity_rule = classify_severity(text)
    return {
        "admission_class": admission_class,
        "admission_rule": admission_rule,
        "domain": domain,
        "domain_rule": domain_rule,
        "severity": severity,
        "severity_rule": severity_rule,
        "required_action": _required_action(
            admission_class, severity, admission_rule),
        "deadline": _extract_deadline(text),
        "snoozed_until": None,
    }


# ---------------------------------------------------------------------------
# Rollup — presentation grouping by normalize_text, plus the STRICTER
# supersession equivalence contract (action + owner + target) mandated by
# the canonical plan (docs/designs/2026-07-17-minimal-input-operation-
# master-plan.md, row 0.3(b), round-2 hardening).
# ---------------------------------------------------------------------------

_ACTION_TAG_RE = _ACTION_VERB_RE


def _action_tag(text):
    m = _ACTION_TAG_RE.search(str(text or ""))
    return m.group(1).casefold() if m else None


def _owner_tag(source_key):
    """Owner = the originating session, parsed from source_key.

    source_key shapes seen in production: "outcome:<session_id>:<item_key>"
    and "outcome-inferred:<session_id>:<code>". The session is the closest
    deterministic proxy we have for "who/what conversation this ask came
    from" — two rows from different sessions are different owners even if
    their text is byte-identical, because different sessions can describe
    different branches, deadlines, or intents that happen to render the
    same template text.
    """
    parts = str(source_key or "").split(":")
    if len(parts) >= 2 and parts[0] in ("outcome", "outcome-inferred"):
        return parts[1] or None
    return None


def _target_tag(text):
    """Target = backtick-quoted identifier(s) in the text (branch name,
    file, command name, decision id). Returns a sorted tuple, or None if no
    identifier is present — an absent target FAILS CLOSED (never treated as
    equal to another absent target), per "when in doubt, separate/don't
    supersede".
    """
    tokens = _BACKTICK_TOKEN_RE.findall(str(text or ""))
    if not tokens:
        return None
    return tuple(sorted(set(t.casefold() for t in tokens)))


def same_equivalence(member_a, member_b):
    """The SUPERSESSION contract (stricter than rollup presentation grouping).

    ============================= EQUIVALENCE CONTRACT =============================
    Two member rows may supersede one another when answering a rollup card
    ONLY if all three of the following are independently determinable AND
    equal:
      - action  (the imperative verb driving the ask, extracted from text)
      - owner   (the originating session_id, extracted from source_key)
      - target  (a backtick-quoted identifier in the text — branch, file,
                 command, id)
    Any of the three being UNDETERMINABLE (None) on either side blocks
    supersession — this fails CLOSED, not open. Identical normalized text
    from two different sources is NOT sufficient on its own: the same
    words can describe different branches, owners, or deadlines. Absent a
    full three-way match, each member resolves INDEPENDENTLY — the rollup
    card still presents them together (density), but answering the card
    does not silently close members that only "look like" the same ask.
    ==================================================================================

    This function must NEVER be used for rollup PRESENTATION grouping
    (that is normalize_text equality, deliberately looser/for density
    only) — it is used exclusively to gate the write-path supersession
    fan-out when a card is answered.
    """
    member = {"a": member_a, "b": member_b}
    action = {}
    owner = {}
    target = {}
    for key, m in member.items():
        action[key] = _action_tag(m.get("text"))
        owner[key] = _owner_tag(m.get("source_key"))
        target[key] = _target_tag(m.get("text"))
    if action["a"] is None or action["a"] != action["b"]:
        return False
    if owner["a"] is None or owner["a"] != owner["b"]:
        return False
    if target["a"] is None or target["a"] != target["b"]:
        return False
    return True


def rollup(rows):
    """Group rows into presentation cards by EXACT normalize_text equality.

    Every member row is kept underneath its card for provenance — rollup
    NEVER drops a row, it only changes how many cards are rendered. A
    card's severity is the MAX severity among its members (an escalating
    member is surfaced, never hidden, by raising the whole card). A card's
    domain is the majority domain among members, tied-broken by earliest
    first_seen (deterministic). Members whose own domain/severity differ
    from the card's chosen values are listed under "dissenting_members" so
    a disagreement is always visible, never silently normalized away.

    Re-ask handling is a structural consequence of computing rollup fresh
    from current rows on every call rather than persisting cards as their
    own entities: a brand-new row whose normalized text matches an
    existing (still-open) group is automatically absorbed as another
    member the next time rollup() runs — it never gets a second card
    ("expires into the group"). If that new row's severity is higher than
    the group's current members, the card's MAX-severity rule raises the
    whole card ("escalates ... recorded") instead of silently keeping the
    old, lower severity.
    """
    groups = {}
    order = []
    for row in rows:
        key = normalize_text(row.get("text"))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(row)

    severity_rank = {s: i for i, s in enumerate(SEVERITIES)}
    cards = []
    for key in order:
        members = sorted(
            groups[key], key=lambda r: (r.get("first_seen") or 0, r.get("decision_id") or ""))
        dominant_severity = max(
            members, key=lambda r: severity_rank.get(r.get("severity"), 0)
        ).get("severity")
        domain_counts = {}
        for m in members:
            domain_counts[m.get("domain")] = domain_counts.get(m.get("domain"), 0) + 1
        best_count = max(domain_counts.values())
        # tie-break: earliest first_seen among domains sharing the max count
        dominant_domain = None
        for m in members:
            if domain_counts[m.get("domain")] == best_count:
                dominant_domain = m.get("domain")
                break
        dissenting = [
            {"decision_id": m.get("decision_id"),
             "domain": m.get("domain"), "severity": m.get("severity")}
            for m in members
            if m.get("domain") != dominant_domain or m.get("severity") != dominant_severity
        ]
        cards.append({
            "card_id": "card:%s" % _stable_hash(key),
            "normalized_text": key,
            "display_text": members[0].get("text"),
            "severity": dominant_severity,
            "domain": dominant_domain,
            "member_count": len(members),
            "members": [
                {"decision_id": m.get("decision_id"),
                 "source_kind": m.get("source_kind"),
                 "source_key": m.get("source_key"),
                 "state": m.get("state"),
                 "first_seen": m.get("first_seen"),
                 "last_seen": m.get("last_seen")}
                for m in members
            ],
            "dissenting_members": dissenting,
        })
    return cards


def plan_rollup_supersession(card_members, primary_decision_id):
    """Given a card's member rows and the decision_id Trevor just answered,
    decide which OTHER members may be superseded under the equivalence
    contract, and which must resolve independently (visibly).

    Returns {"supersede": [decision_id, ...], "independent": [decision_id, ...]}.
    This function only PLANS the fan-out (pure, no I/O, no DB writes) — the
    write path (decision-alert.py, patched separately) executes it by
    calling the EXISTING resolve() primitive per superseded member, one at
    a time, with evidence_type="manual_resolution" and evidence_ref
    pointing at the primary decision_id. That write path is validated only
    against a copy of the live database in this session (see
    scripts/queue_admission.test.py), never against live.
    """
    by_id = {m["decision_id"]: m for m in card_members}
    primary = by_id.get(primary_decision_id)
    supersede = []
    independent = []
    for m in card_members:
        if m["decision_id"] == primary_decision_id:
            continue
        if primary is not None and same_equivalence(primary, m):
            supersede.append(m["decision_id"])
        else:
            independent.append(m["decision_id"])
    return {"supersede": supersede, "independent": independent}


def _stable_hash(value):
    import hashlib
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# WorkOrder packet — advisory pointer only. See module docstring: this NEVER
# grants execution authority. The authority-envelope fields below (capability
# / risk / expiry / rollback) are DATA the downstream loop's OWN authority
# policy may consult; this code makes no claim about what that policy allows
# and does not itself gate, approve, or execute anything.
# ---------------------------------------------------------------------------

def build_workorder_packet(row, now_epoch=None):
    """Build an advisory WorkOrder pointer packet (data only — see module
    and function-group docstrings for the authority boundary).

    Field shape follows the existing ready-packets/ convention observed at
    ~/.cross-agent/autonomous-loop/{failed,done,inflight}-packets/*.json
    (work_order_id / lane_key / task_file / scope / verify_cmd / owner /
    governor_* fields) plus new authority-envelope fields required by the
    canonical plan's round-2 hardening: capability, risk, expiry, rollback.
    None of these fields cause execution — the loop's Agency v2 authority
    policy is the only thing that could ever act on a packet, and per the
    canonical plan (§9) that policy currently has ZERO live runtime effect.
    """
    now_epoch = now_epoch if now_epoch is not None else int(time.time())
    return {
        "work_order_id": "phase0-queue-%s" % (row.get("decision_id") or "").replace(
            "decision:", ""),
        "lane_key": "mission-control:decision-queue:%s" % row.get("domain"),
        "source_decision_id": row.get("decision_id"),
        "source_kind": row.get("source_kind"),
        "source_key": row.get("source_key"),
        "text": row.get("text"),
        "admission_class": row.get("admission_class"),
        "admission_rule": row.get("admission_rule"),
        "created_epoch": now_epoch,
        # --- authority envelope (data only; no execution effect here) ---
        "authority_envelope": {
            "capability": "none-granted",
            "risk": "unassessed",
            "expiry_epoch": now_epoch + 24 * 60 * 60,
            "rollback": "not-verified",
            "note": ("advisory pointer only; the consuming loop's own "
                     "authority policy decides whether/what may execute — "
                     "this packet grants nothing"),
        },
    }


# ---------------------------------------------------------------------------
# CLI — the only I/O in this file. `derive` opens the target sqlite database
# READ-ONLY (mode=ro) and never writes to it; it writes results to --out.
# `migrate` (for use against a scratch COPY of the db only, never live) adds
# the new columns so the write path can be validated end to end offline.
# ---------------------------------------------------------------------------

ADMISSION_COLUMNS = (
    ("admission_class", "TEXT"),
    ("admission_rule", "TEXT"),
    ("domain", "TEXT"),
    ("severity", "TEXT"),
    ("required_action", "TEXT"),
    ("deadline", "TEXT"),
    ("snoozed_until", "INTEGER"),
)


def add_admission_columns(con):
    """Idempotent ALTER TABLE, mirroring the existing anchor_ref migration
    pattern in decision-alert.py's _migrate(). Additive only — never drops
    or rewrites existing columns/rows. Safe to call on every connect (it
    no-ops once the columns exist), exactly like the rest of _migrate().
    """
    existing = {row[1] for row in con.execute(
        "PRAGMA table_info(decisions)").fetchall()}
    for name, coltype in ADMISSION_COLUMNS:
        if name not in existing:
            con.execute("ALTER TABLE decisions ADD COLUMN %s %s" % (name, coltype))
    con.commit()


def _iso(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


def _read_rows_readonly(db_path, state=None):
    uri = "file:%s?mode=ro" % db_path
    con = sqlite3.connect(uri, uri=True, timeout=5)
    con.row_factory = sqlite3.Row
    try:
        sql = "SELECT decision_id, source_kind, source_key, state, trust_state, text, first_seen, last_seen FROM decisions"
        params = []
        if state:
            sql += " WHERE state=?"
            params.append(state)
        return [dict(r) for r in con.execute(sql, params).fetchall()]
    finally:
        con.close()


def cmd_derive(args):
    rows = _read_rows_readonly(args.db, state=args.state)
    for row in rows:
        row.update(classify_row(row.get("text")))
    cards = rollup(rows)
    lane_counts = {}
    for row in rows:
        lane_counts[row["domain"]] = lane_counts.get(row["domain"], 0) + 1
    security_rows = [r for r in rows if r["severity"] == "security" and r["state"] == "open"]
    admission_counts = {}
    for row in rows:
        admission_counts[row["admission_class"]] = admission_counts.get(
            row["admission_class"], 0) + 1
    result = {
        "schema": SCHEMA,
        "generated_at": _iso(int(time.time())),
        "source_db": args.db,
        "row_count": len(rows),
        "admission_counts": admission_counts,
        "card_count": len(cards),
        "lane_counts": lane_counts,
        "security_decision_ids": [r["decision_id"] for r in security_rows],
        "rows": rows,
        "cards": cards,
    }
    out = json.dumps(result, ensure_ascii=True, sort_keys=True, indent=2)
    if args.out:
        with open(args.out, "w") as f:
            f.write(out)
    else:
        print(out)
    return 0


def cmd_migrate(args):
    con = sqlite3.connect(args.db, timeout=10)
    try:
        add_admission_columns(con)
    finally:
        con.close()
    print(json.dumps({"ok": True, "db": args.db}))
    return 0


def _parser():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)

    d = sub.add_parser("derive", help="read-only classify+rollup against a db")
    d.add_argument("--db", required=True)
    d.add_argument("--out")
    d.add_argument("--state", default="open")

    m = sub.add_parser("migrate", help="ALTER TABLE add admission columns (never live)")
    m.add_argument("--db", required=True)

    return p


def main(argv=None):
    args = _parser().parse_args(argv)
    handlers = {"derive": cmd_derive, "migrate": cmd_migrate}
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
