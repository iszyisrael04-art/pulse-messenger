# Verification results — 9 October 2026

## Passed against the connected Pulse backend

A live HTTP integration test used three disposable, verified fixture accounts, not the existing account. It passed:

- Correct email/password authentication for all three identities.
- Wrong-password rejection.
- Username/password exchange through the deployed `pulse-login` Edge Function.
- Session refresh using the returned refresh token.
- Profile update through restricted RPC.
- Direct-chat creation and recipient message reads.
- Retrying the same message UUID without creating duplicate messages.
- Outsider private-message invisibility and rejected unauthorized send.
- Recipient cannot edit another sender's message.
- Read receipt creation.
- `30DAYSPULSE` success and duplicate rejection.
- Non-operator denial of administrator overview.
- Blocking prevents further sends.

The temporary sessions, conversations, accounts and promo-use increment were cleaned up. Existing user count returned to one. The user's existing account was not modified.

The separate SQL transactional suite also passed private membership isolation, direct-chat idempotency, ownership, protected Premium updates, private username/email lookup denial, reactions and blocking. That suite rolled back all fixtures.

## Source checks

- Dart formatter parsed all native source and Dart test files successfully.
- Standalone username/password validation checks passed.
- Python helper syntax compilation passed.
- Pinned top-level packages were checked against publisher package APIs; the Supabase initialization/secure-storage interface was checked against the pinned package source.

These checks are **not** full Dart semantic analysis or native compilation. Dependency resolution, lockfile generation, `flutter analyze`, `flutter test`, visual rendering, device checks, APK build and Windows build were not completed.

## Advisor results

Every public Pulse table has RLS; anonymous roles cannot execute app mutation functions. Privileged logic is kept in an unexposed schema with fixed search paths and explicit grants. The advisor initially reported missing FK indexes and repeated Auth policy calls; an additional migration applies the indexes and init-plan policies. The final performance check has no missing-FK-index or Auth-init-plan warnings; only informational unused-index notices remain on this new database.

The four private internal tables deliberately have RLS with no client policies: operator membership, promo definitions, redemption history and login throttling are accessed only through narrowly authorized server logic. The Auth advisor reports breached-password protection disabled; that provider setting remains a deployment task.

## Build interruption

Automatic approval review rejected a Flutter command because its startup unexpectedly requested a link-local cloud metadata endpoint. Such requests can expose instance credentials and were unnecessary for the authorized build. The blocked Flutter command was not retried or bypassed. Subsequent local checks used standalone source formatting and validation. No APK or EXE is supplied in this package, and native compatibility/performance is not verified.

## Not tested / not implemented

Email/SMS OTP delivery and recovery delivery, native UI behavior, real-time delivery between native devices, storage uploads on device, offline reconnect/background behavior, group/admin UI actions, MFA, E2EE, calls, push, paid billing, signed releases and automatic updates. See FEATURE_STATUS.md for the precise feature boundaries.


# Pulse 0.3 verification — 10 October 2026

New transactional SQL tests ran against the connected backend using temporary fixture users/data and rollback. `test/calls_security.sql` passed call/member RLS isolation, nonmember start/accept/heartbeat rejection, internal-function denial, simultaneous busy reservation, accept/leave state, unanswered expiry, removed-member reconciliation and blocked contact prevention. A runtime ambiguous-variable bug was corrected in `call_start` before the passing run.

`test/message_media_security.sql` passed media retry idempotency, peer/outsider visibility, foreign storage path rejection, MIME matching, waveform ranges and duration limits. Tests validate metadata and permissions, not actual audio decoding or delivery.

Dart formatting parsed all 18 Dart files, standalone username/password checks passed, and the Python bootstrap test passed. Relevant APIs were inspected in the pinned official LiveKit/record/MediaKit package source. These are not Flutter semantic analysis, dependency resolution, native builds, visual QA or real-device media tests. Flutter execution remains blocked here by the earlier automatic approval review decision; it was not bypassed.

The security advisor reports no public-table RLS or privileged public-function warnings. Six private internal tables intentionally deny direct client access through RLS with no policies. Auth leaked-password protection remains disabled and should be configured before release.

Schemas 007/008 and `pulse-call` are deployed. LiveKit credentials/media delivery are not configured or verified. Closed-app FCM dispatch is not deployed. No APK/EXE from 0.3 is supplied.

Existing core messaging authorization regression tests also passed on this update. A rerun of the unchanged status-media suite failed at the service transport layer with an expired request state; no new status regression pass is claimed. Its prior successful result remains documented in the 0.2 update notes.


# PULSE 0.4 verification — 10 October 2026

The uploaded 0.3 source was inspected and retained. Nine auth/messaging/profile/status/channel/security modules match the upload byte-for-byte. The call screen adds sequential, best-effort disposal and avoids leave RPCs after sign-out; signaling and control behavior are retained. Native cleanup testing remains required. The upgrade adds a social schema, isolated storage and UI modules; it does not reset existing accounts or conversation/subscription data.

`test/social_security.sql` passed transactional tests on the connected backend for public posts/Reels, publishing retry safety and ownership, draft isolation, stable timestamp/UUID pagination, media permissions, private follow requests/approval, private-profile repost privacy, blocking, likes/saves/reposts/comments, unique view counts, own analytics, report/operator moderation, reference-only sharing and client grants. Publishing uses per-content locking to prevent concurrent ownership conflicts. All fixtures rolled back.

Current core messaging/Premium, message media, status media and channel/live authorization suites passed again. The unchanged call suite rerun encountered an expired request-state transport error, so no new call regression pass is claimed. Its prior pass is recorded above. These SQL tests do not decode/upload real video bytes or prove native SDK operation.

Dart formatting parses all source/test files. Python bootstrap and standalone username/password validation pass. New Flutter tests cover delayed-page versus refresh races, pagination duplicate/cursor handling, failed filter isolation and removing unfollowed creators. They are included for CI and were **not executed here**. Relevant MediaKit/video APIs were checked against pinned publisher source.

The security advisor reports no public RLS/privileged-function warning; nine private internal tables intentionally have no client policies. Leaked-password protection remains disabled. Full Flutter package resolution/semantic analysis, native compilation, visual UI testing, real uploads/player lifecycle and low-end performance are not completed. Automatic approval review's earlier local Flutter metadata-endpoint block was not bypassed. Use GitHub Actions and the device acceptance checklist to close these gates.

The additive 009 social installation script is deployed, including ownership locking, private creator/repost visibility, scoped operator media review and reference-only chat sharing. Supabase CLI migration-history generation/replay on a clean staging database remains a production deployment task. No public production launch or app binary is claimed.


# 0.4.4 verification — 15 October 2026

See UPGRADE_0.4.4.md. Dart parsing/formatting and selected standalone analysis passed. Upload test now asserts intermediate transport progress, retry recovery and byte integrity; appearance, visibility, username/password validation and bootstrap idempotency/native-registration/Windows-name tests passed. Native compilation, full Flutter analysis/tests and actual media exports were not run. The new SQL suite's overlong fixture was fixed after its first failed run, but the rerun was blocked by automatic approval review usage limit and was not executed. No passing new request/privacy/redemption security result is claimed.


# 0.4.5 verification — 15 October 2026

The user reports successful chatting with their brother on two devices. This is user-reported evidence for that tested chat flow, with no exact build or device matrix supplied. It is not a blanket device-test pass for new source.

Local checks passed: all 53 Dart source/test files parse/format; selected standalone analysis including export/validation; export pagination/content/Unicode, cancellation cleanup, existing-file and invalid-page safeguards; password confirmation; five Python native-bootstrap/configuration tests; public config preflight. Existing standalone upload recovery/progress/integrity, appearance and visibility tests passed again. No real user's password/session/account was modified for verification.

No new database DDL or deployment was performed. New export queries use existing RLS and explicit field lists but have not been exercised against the real backend through a native app. Full Flutter analysis/tests/native builds and export/password/nonce/resend/sign-out device tests remain. The prior corrected 012 security-suite rerun remains unexecuted after automatic approval review's usage-limit block.


## Windows build correction — 15 October 2026

User reports Android successfully built. Windows failed CMake generation due to the editor/app target cycle. The bootstrap output-directory correction passed five Python tests, including a real CMake 4.1 configuration of the generated dependency graph and upgrade from the legacy cyclic command. This configures the native source target but does not compile Windows C++/WinRT code on Linux. Full Windows compilation and editor/device tests still require CI.


## Confirmed install-prefix failure and regression — 15 October 2026

Full verbose user log identifies a literal $<TARGET_FILE_DIR:Pulse> install destination. Editor runtime installation now uses an explicit bundle destination. Nine Python tests passed, including a real CMake configure/compile/install fixture reproducing Flutter's generator-expression prefix and a path containing spaces. This builds tiny fixture code, not the real Flutter/WinRT app; fresh Windows CI remains required.
