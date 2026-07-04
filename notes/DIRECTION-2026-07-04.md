# Trevor's direction (2026-07-04)

## Build order
1. Chat connection DIAGRAM first (the visual map — nodes=chats, lines=how they spawned/audited/researched each other, see evolution). Also: whole-bar-click on Home + deep-link "go" to the SPECIFIC chat, not the top of a list.
2. Usage -> routing (make it practical).
3. Autonomy loop.

## UI approach (React question resolved)
Keep single-file + double-click + offline. Do NOT go full React/Vite (loses the open-a-file simplicity). Instead vendor a real vanilla graph library LOCALLY (cytoscape.js at dashboard/vendor/, loaded via relative <script src>, no CDN, works offline). Revisit React only if this still isn't enough.

## Usage sources to wire (ALL)
- Codex + Claude: local (make Codex fresh; Claude burn+reset, no % exists).
- GLM / z.ai: real usage API (key already held for claude-glm).
- GitHub Copilot: usage API (needs a GitHub token scope from Trevor).
- Cursor: no public API — explore creative capture (Trevor may provide screenshots) rather than leave blank.
- Hermes: its own API — Trevor can buy credits that use available models; read credit state directly.

## Autonomy loop
Auto-fix the SAFE class (merged branches, dead worktrees, stale refs, already-blessed pushes) + GLARING alerts (phone + dashboard top) for anything needing a decision. NEVER merge/push active work. Never destructive-without-containment.

## Confusions to fix (his read of the current UI)
- Needs-attention: whole bar clickable + highlight; "go" jumps to the exact chat.
- Chats tab cluster area is unreadable ("$", "parent_provider: unknown", "...", "◄...►") -> replaced by the real diagram.
- "live" (green) meaning unclear -> label it ("active in last 30 min"); make provider/repo obvious.
- resume / chat-source-full commands unclear -> label what each does ("Reopen this chat" / "Read it").
- "76 new chats today" ambiguous -> clarify it means chats recorded, not ones he worked in.
