## ADDED Requirements

### Requirement: Repo and branch fact contract
The scanner MUST emit repo path, current branch, upstream, remote name/classification, ahead, behind, worktrees, dirty state, recent activity, and branch-level local/upstream refs, last commit, checkout paths, and push eligibility with all refusal reasons.

#### Scenario: Branch-level facts differ from current checkout
- **WHEN** a non-current branch is ahead of its upstream
- **THEN** its own branch row reports ahead/behind/upstream/worktrees independently from the current checkout

### Requirement: Eligibility fails closed
`push_eligible` MUST be false unless ahead is positive, behind is zero, remote and upstream are configured, the branch is not default/protected, no worktree checks it out, the conservative repo/worktree dirt rule passes, activity is older than six hours, activity evidence is fresh, and the sanitized remote has no embedded credentials.

#### Scenario: One refusal guard fails
- **WHEN** any required guard is false or unknown
- **THEN** `push_eligible` is false and the response lists the guard-specific reason

### Requirement: Remote data is sanitized
The feed and logs MUST expose only remote name and safe classification, MUST reject embedded-credential URLs, and MUST NOT persist or print credential-bearing remote strings.

#### Scenario: Remote URL embeds a token
- **WHEN** a remote URL includes credentials
- **THEN** eligibility is false and output contains a safe reason without the URL or credential

### Requirement: Consumers recompute current facts
Any state-moving consumer MUST rerun the scanner immediately before action and MUST use the returned branch-specific refs rather than cached dashboard/open-end prose.

#### Scenario: Cached eligible branch becomes checked out
- **WHEN** the cached feed says eligible but a worktree checks out the branch before action
- **THEN** recomputation refuses the action

### Requirement: Explicit refspec command
When an action is eligible, the deterministic command MUST use an explicit repository path, remote name, local ref, and remote refspec and MUST never rely on plain current-branch `git push` behavior.

#### Scenario: Safe command is constructed
- **WHEN** a branch passes every eligibility guard
- **THEN** the proposed argv targets exactly `<local-branch>:<remote-branch>` on the named remote without logging a URL
