# Alert provider receipts

The storage/lifecycle audit found that an alert sender's exit zero became a
durable `fixed_argv_receipt` while its provider acknowledgment was discarded.
Disk Guard could also call zero eligible sends successful. This slice repairs
the Mission Control consumer and its two dashboard labels; the coordinated
Disk Guard classification and later natural delivery remain in the original
storage task.

`decision-alert` now captures at most 4,096 stdout bytes from the fixed Control
sender, within the existing timeout. It requires one versioned metadata object
with exact decision ID and UTF-8 message SHA256, expected provider and acceptance
status, usable integer message ID and recipient hash. Unknown/missing fields,
duplicate JSON keys, wrong bindings/types, malformed or empty JSON, nonzero
exit, oversized output and timeout cannot become a success receipt. Recipient
acknowledgment matching belongs to the landed Mobile Connect sender; this
consumer does not duplicate routing configuration or read its credentials.

The existing transaction updates the attempt, receipt and `alert_success`
event together. Provider metadata lives in the existing event detail; there is
no schema, daemon or schedule addition. The read model requires the exact
decision/fingerprint/attempt/message binding. Historical fixed-argv receipts
keep their 24-hour dedupe and show delivery unverified. New committed receipts
show provider acceptance. Existing count fields remain; provider-accepted
counts and bound receipts are explicit. The cycle summary distinguishes old
counts and acceptance followed by uncertain local persistence.

Provider acceptance is separate from visible delivery and from atomic local
persistence. If COMMIT is rejected after a valid acknowledgment, stdout reports
known provider acceptance with local receipt unverified; it does not stamp
success. Interruption or timeout can leave an uncertain external outcome.
This repair does not claim exactly-once sending or remove the reservation
expiry/retry boundary.

The sender runs in an owned process group. Its exact PID/group/start identity,
purpose, stop method and retention are recorded in the existing event log;
completion is recorded after reaping. Bounded pipe capture leaves unrelated
sender file writes unrestricted. TERM/INT waits until the created child handle
and identity are held, then cleanup stops its exact group before reaping the
leader. Child signal masks stay unchanged; prior parent handlers and masks are
restored. Native group membership must be empty before reporting completion.
No existing user or foreign process is stopped. There is no broad-name kill.

The existing queue checks pass. Fourteen focused test methods cover strict packet
refusals, exact metadata joining, legacy dedupe, reservation mismatch, real
SQLite event-trigger rollback, actual COMMIT authorizer denial and truthful
post-acceptance classification, stdout bounds, sender timeout, parent TERM,
and TERM before/after actual SQLite commit. All successful transaction controls
reopen and verify integrity. These are process interruption controls, not a
power-loss simulation. The first new fixture was refused by the existing
structured admission gate: manual synthetic provenance needs `--anchor`;
`--resolution-key` supplies a different binding. The corrected fixture declares
a synthetic deterministic anchor and leaves production admission intact.

The first full local gate passed 42 suites. Independent native review found
three gaps: sender-finish SQL rejection hid captured acceptance, a signal
between native child creation and handle assignment leaked that sender, and
a successful leader could leave a closed-stdout descendant alive. All three
are repaired. Finish-event rejection now preserves known acceptance with local
receipt unverified. Actual TERM and INT at creation restore handlers/masks and
reap the child; owned descendants are stopped before leader reaping. Fourteen
methods pass under Python 3.14.7 and Apple's 3.9.6, including rejection of
success when an injected signal denial leaves a native descendant running.
Native Darwin checks established that an exited leader can disappear from
getpgid and a group with no living member can return EPERM. Exact numeric group
membership distinguishes that case; a remaining group fails closed. The first
repair attempt failed four unchanged acceptance checks at this native EPERM
boundary. Failed evidence is retained; expectations were not weakened.

The incoming Linux CI workflow had changed its ShellCheck installation while
the prerequisite test still required Homebrew. Its native before check fails
at that exact predicate. The dependent check now verifies the current Linux
installation and manual-dispatch-only routine tests. Existing Linux runner,
pinned action versions, deployment/operational jobs and all other workflow
choices are preserved. No hosted runner is started. Browser checks reuse the
existing file:// Playwright suite against private synthetic state. A hash-only
page navigation does not reload rewritten data scripts; reload after a fixture
change before asserting the new data. This was the first new browser fixture's
failure, with no production source defect or weakened expectation.

The final full local gate passed all 42 suites. The focused independent recheck
accepted all three repairs: 14 native methods passed across both Python versions,
all 15 reviewed hashes stayed unchanged, and all owned children exited.
Implementation `4eafbced9311fafbc07d0e2fafaf84703131fa45` is verified on remote
main and the clean canonical checkout. Its normal guarded push also passed all
42 suites. GitHub accepted that push under the account's configured exemption
while its GitHub Actions `verify` status remained absent. No hosted runner or
rules change supplied that acceptance; the local gate and server exemption are
separate evidence.

The supported aggregate installer ran with `DASHBOARD_INSTALL_NO_LAUNCHD=1`
from stable canonical main. Fresh preflight matched all 94 preserved entries.
All 18 installed payloads match committed bytes and private modes; the complete
native stamp verifies the exact implementation. Installed HTML labels match,
both prior LKG generations retain their bytes, metadata and identities, and the
new third LKG verifies. Unaffected originals and service plists remain intact.
Fourteen unchanged receipt methods pass against the actual installed runtime.
Three actual installed CLI controls verify provider acceptance, dedupe with no
new send, and malformed receipt rejection. All use disposable synthetic state
and senders; their integrity checks pass, children exit and fixtures are removed.
No provider request, live decision-state change or service activation was used
to obtain this proof. Future installation must use a stable checkout because
the native dashboard bakes that repository path.

The private before-image retains 79 files (5,309,335 logical bytes), the stamp,
pointer and both prior LKG generations. A native restore drill verifies the old
aggregate stamp. All 83 replacement/stamp/pointer/release entries have exact
bytes and metadata, with no metadata exception. Four optional extra copies
carry different OS provenance attributes: the bin directory, an unchanged
self-repair bytecode cache, compiled panel and build marker. Their original
attribute bytes are separately retained, and their originals remain in place;
the native installer does not replace them. An ordinary setxattr returned zero
but did not restore that attribute on readback. Do not overwrite these unchanged
objects with their optional copies during rollback. Acceptance and four
rejection controls cover the copy comparison. This is local code preservation,
not an independent backup of production data.

Rollback uses the retained pre-install aggregate and a governed source revert
through the same native procedure. It preserves the live decision database,
historical receipts and private evidence. After source, installation and its
record are verified, release the exact owned lease and use the supported
broker quarantine with ignored bytes and branch retained. Natural provider
acceptance, original capacity/backup/index cadences and 72-hour stability remain
separate acceptance items in the existing storage brief.
