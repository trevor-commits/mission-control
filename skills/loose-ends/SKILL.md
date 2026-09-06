---
name: loose-ends
description: Pick up unfinished work without restated context. Use when Trevor says "what's unfinished", "pick up where we left off", "loose ends", "what did we leave open", or at the end of a session. Reads Mission Control's open-work ledger, the attention board, the repo's todo.md Active Next Steps, and git state. Then it either closes one item or writes the next concrete resume prompt.
---

# Loose ends

One skill, four tools: Claude Code `/loose-ends`, Codex `$loose-ends`, Cursor `/loose-ends`, Hermes `hermes -z "use the loose-ends skill: pick up the top unfinished item in $PWD"`. The helper is `~/.mission-control/bin/loose-ends` from the existing Mission Control installation. If it is unavailable, inspect the installation health before running a development copy. It makes no model calls. you do the judgment.

## Steps

1. **List.** Inside a repo run `loose-ends --repo "$PWD"`, else `loose-ends`. Show Trevor the table as printed. The two noise kinds (`register_unverified`, `chat_open_end`) are hidden. `--all-kinds` restores them.
2. **Pick one.** The item Trevor named, else row 1. `loose-ends show <n>` gives the text, source chat, reopen and read commands, and the resolve command.
3. **Decide: close or prompt.** Close it now only if it is bounded, reversible, inside this repo, and verifiable in this session (the contract's autonomous-fix rule). Anything destructive, cross-repo, credential-bearing, or decision-shaped gets a prompt instead. Say which path and why in one sentence.
4. **Close path.** Do the work → run the verification → write the durable record (`todo.md` line moved under `## Completed` with date and evidence, or the item's own record) → `loose-ends resolve <n>` → closeout card.
5. **Prompt path.** `loose-ends --repo "$PWD" prompt <n>` writes a recovery prompt under `~/.mission-control/prompts/`. It preserves the receiving task's selected model and reasoning. It includes the source identity, freshness, available read/reopen commands, and current repository snapshot. The receiving agent verifies the original request, ownership, next step, and acceptance evidence before editing. Unknown fields require source inspection, not invented facts. Do not replay old tool calls or repeat an external effect without checking whether it succeeded. When handing off a visible prompt, keep it under 4,000 characters and link its complete file.
6. **One item per invocation.** End by naming what the next row would be.

## Boundaries

- Never edit human documents from the helper. `resolve` only runs the item's own `chat-graph resolve` or `dashboard attention resolve` command.
- Never merge, force-push, delete branches, or restart services to close an item.
- Read the freshness recorded by `show` or `prompt`. A freshly exported feed can still contain an old full transcript scan. Verify the current source before acting. Use the existing collector when a refresh is needed and authorized.

## Invoke lines

| Tool | Line |
|---|---|
| Claude Code | `/loose-ends` |
| Codex | `$loose-ends` |
| Cursor | `/loose-ends` |
| Hermes | `hermes -z "use the loose-ends skill: pick up the top unfinished item in $PWD"` (`-p` is profile, not prompt) |
