# COHERENCE

## Principle
When anything changes, everything it affects must change with it in the same commit. The repo is a linked system; drift kills its authority.

## The Ripple Check
1. Identify every live section or rule touched by the change.
2. Consult the Dependency Map for local docs that reference that surface.
3. Read each dependent doc and confirm it still agrees.
4. Update any drifted companion docs in the same commit.
5. Name the Ripple Check work in Self-audit or audit notes with method used.

## Dependency Map
This map is append-only. Add a row whenever a new durable cross-reference is introduced.

| Changed surface | Dependent surface | Why the dependency exists |
|---|---|---|
| `CONTINUITY.md` | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` | AGENTS enforces Work Record and Self-audit expectations |
| `COHERENCE.md` | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` | AGENTS enforces Ripple Check and same-commit doc updates |
| `/Users/gillettes/Coding Projects/mission-control/LINEAR.md` | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md` | AGENTS gates state moves and closeout on Linear-coverage |
| `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md` | `CONTINUITY.md`, `COHERENCE.md`, `/Users/gillettes/Coding Projects/mission-control/LINEAR.md` | Claude should load the same principle docs before planning or audit |
| `/Users/gillettes/Coding Projects/mission-control/todo.md` log shapes | `CONTINUITY.md`, `/Users/gillettes/Coding Projects/mission-control/LINEAR.md` | durable records and issue coverage must stay aligned with local principle docs |
| `PROJECT_INTENT.md` and local source-of-truth docs | `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`, `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md` | task routing and authority statements depend on the docs map remaining accurate |
| optional repo-local companions such as `README.md`, `GUIDE.md`, `PROMPTS.md`, `RULES.md`, `STRUCTURE.md` | local principle docs | companion docs should point to the same principle surfaces rather than drifting separately |

## Staleness And Orphans
- Staleness is caught first at commit time through the Ripple Check, then during broader audits.
- Every live doc should be indexed from a navigation surface or referenced by another live doc.
- When an orphan is discovered, index it or retire it in the same change instead of leaving it adrift.

## Motive
A repo that drifts stops being a source of truth. Every unresolved contradiction forces later chats to guess.

## Applies To
- Codex runs the Ripple Check before commit.
- Claude Code verifies Ripple Check attestations during audit.
- Cowork confirms Ripple Check completion before state moves.

## Where The Rules Live
- `/Users/gillettes/Coding Projects/mission-control/AGENTS.md`
- `/Users/gillettes/Coding Projects/mission-control/CLAUDE.md`
- `/Users/gillettes/Coding Projects/mission-control/LINEAR.md`
- `/Users/gillettes/Coding Projects/mission-control/todo.md`
- any repo-local `GUIDE.md`, `PROMPTS.md`, or `RULES.md` that points to these surfaces
