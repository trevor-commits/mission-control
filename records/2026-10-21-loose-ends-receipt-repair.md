# Loose-ends installed-source receipt repair — October 21, 2026

Owner: Codex `01a0dabb-ddb9-7be3-bf25-11c0fb14eec2` for Trevor.
Request: fix the remaining loose-ends skill hash mismatch thoroughly.
Integration: existing clean Mission Control main; no new branch or worktree.
Acceptance: verified published source, installed file and all existing aliases;
receipt checker and rejection coverage pass; full native diagnostic completes;
owned procedure/record published through the normal local gate and remote-main
readback. No website, scheduler, model/effort, collector, credential or skill
behavior change is authorized by this repair.

## Cause and repair

Mission Control's published skill update `20281065ca7bacb4071426367661ba4200c1b347`
added the newer-answer guard on October 21. The current source and installed
`SKILL.md` already match that commit. The old receipt instead pinned
`3340b23751239be174b619ba0727be35a0924fd2` and hash
`cbb0b1d0adbd54f9fd20a2a297785686bfeaa8367a129b45bb89e88d071ee3b8`.
The correct current skill hash is
`ff65f5d994511c474bd50ad62a563171f519e4919e8edeb4e9f966b11dcbce00`.
Fresh fetch/remote-main ancestry and the source's complete committed file map
were verified before the receipt changed. No skill content was changed.

Only the existing loose-ends installation entry was refreshed. Its source commit
and complete source/installed maps now match the published skill. The existing
Cursor and Hermes aliases were added to the receipt's coverage alongside Claude
and shared agents. All four are existing symlinks to the same Codex directory;
no alias was created, moved or replaced. Unrelated manifest entries and metadata
were independently compared and preserved. The refresh used a private backup,
compare-before-replace, same-directory atomic replacement and file/parent fsync.

The generated local receipt remains outside repository publication; this record
preserves the relevant provenance. The full private backup and entry proof are
in the existing Gillette task evidence directory, under
`tmp/readiness-repairs-20261018/loose-ends-receipt-before.json` and
`loose-ends-receipt-repair.json`. Before-manifest SHA-256:
`2fb35a9f23b60f91988aad24a5ad090cce6689c356e5ed8fac0385ede6aeeff6`.
After-manifest SHA-256:
`906418d4deaecfc03cdd24df43650ea476acbfc03a36b28bd92253f062a1b2e4`.

## Verification and terminal evidence

- Baseline complete receipt check rejected the stale source, installed file and
  both previously declared aliases.
- Corrected complete receipt check: `installed skill source receipt: OK`.
- Existing checker regression suite: three tests passed.
- Private wrong-hash negative control: all seven expected source, committed-source,
  installed and four-alias mismatches were rejected; real receipt untouched.
- The full global-policy diagnostic uses the unchanged native validator and
  its full installed cleanup safety suite. Its managed process receipt and
  complete log are `loose-ends-global-policy-process.json` and
  `loose-ends-global-policy.log` in the same private task directory.
- Terminal evidence is `loose-ends-final-verification.json` in that directory.
  It must contain the final native diagnostic result, normal repository push
  gate result, exact remote-main containment, clean owned checkout and absent
  owned process groups before this task is reported complete. This external
  receipt records final publication without a self-referential follow-up commit.

The full native diagnostic subsequently completed with exit 0 and
`GLOBAL POLICY STACK: PASS`, including the skill receipt, 79 runtime hostile
fixtures and full installed cleanup-source verification.

The first normal source push was rejected after `SUITES PASS=41 FAIL=1`.
Its sole failing suite was the Python floor: the inherited command path selected
Apple Python 3.9.6, below the required 3.11. All other suites passed. The installed
Homebrew Python 3.11.16 passes the unchanged requirement. Retry the normal HTTPS
push with only its Python command directory prepended through a task-scoped
`env PATH=...`; preserve the failure log and every test/assertion. No shell
profile, global hook, Python floor or test budget is changed. The supported
version matches the repository CI toolchain. Terminal proof remains the external
receipt above.

Rollback: preserve the private predecessor receipt. If rollback is needed,
compare the live receipt against this exact post-repair entry and merge only the
owned entry; never overwrite later unrelated changes. No active checkout or
foreign edits were reset, no security check was weakened, and no external
message, website deployment or natural collector run was performed.
