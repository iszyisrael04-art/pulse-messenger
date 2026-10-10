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
