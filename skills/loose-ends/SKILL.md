---
name: loose-ends
description: Pick up unfinished work without restated context. Use when Trevor says "what's unfinished", "pick up where we left off", "loose ends", "what did we leave open", or at the end of a session. Reads Mission Control's open-work ledger, the attention board, the repo's todo.md Active Next Steps, and git state. Then it either closes one item or writes the next concrete resume prompt.
---

# Loose ends

One skill, four tools: Claude Code `/loose-ends`, Codex `$loose-ends`, Cursor `/loose-ends`, Hermes `hermes -z "use the loose-ends skill: pick up the top unfinished item in $PWD"`. The helper is `~/.mission-control/bin/loose-ends` once `scripts/dashboard install` has run from a main that contains it. until then use `/Users/gillettes/Coding Projects/mission-control/scripts/loose-ends`. It makes no model calls. you do the judgment.

## Steps

1. **List.** Inside a repo run `loose-ends --repo "$PWD"`, else `loose-ends`. Show Trevor the table as printed. The two noise kinds (`register_unverified`, `chat_open_end`) are hidden. `--all-kinds` restores them.
2. **Pick one.** The item Trevor named, else row 1. `loose-ends show <n>` gives the text, source chat, reopen and read commands, and the resolve command.
3. **Decide: close or prompt.** Close it now only if it is bounded, reversible, inside this repo, and verifiable in this session (the contract's autonomous-fix rule). Anything destructive, cross-repo, credential-bearing, or decision-shaped gets a prompt instead. Say which path and why in one sentence.
4. **Close path.** Do the work → run the verification → write the durable record (`todo.md` line moved under `## Completed` with date and evidence, or the item's own record) → `loose-ends resolve <n>` → closeout card.
5. **Prompt path.** `loose-ends --repo "$PWD" prompt <n>` writes a skeleton under `~/.mission-control/prompts/`. Fill every field with facts gathered in this session (files read, commands run, what is already true). Never write "see chat". Run `~/.codex/scripts/prompt-handoff-lint --response` on your reply. the visible block stays under 4,000 characters with the `Prompt file:` pointer. Print the invoke line for the runner you chose.
6. **One item per invocation.** End by naming what the next row would be.

## Boundaries

- Never edit human documents from the helper. `resolve` only runs the item's own `chat-graph resolve` or `dashboard attention resolve` command.
- Never merge, force-push, delete branches, or restart services to close an item.
- If the feeds are stale (`generated_at` older than a day in `~/.mission-control/data/chats.json`), say so and run `~/.mission-control/bin/dashboard collect` first.

## Invoke lines

| Tool | Line |
|---|---|
| Claude Code | `/loose-ends` |
| Codex | `$loose-ends` |
| Cursor | `/loose-ends` |
| Hermes | `hermes -z "use the loose-ends skill: pick up the top unfinished item in $PWD"` (`-p` is profile, not prompt) |
