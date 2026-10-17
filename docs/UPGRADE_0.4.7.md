# Pulse 0.4.7 — Account agreement and profile identity

This updates the existing native Flutter project. Keep the same repository and backend.

## Changes

- Email and phone **Create account** flows show an unchecked Privacy Policy agreement with a separate readable policy page. Submit requires acceptance. Sign-in, username login, recovery and OTP verification do not request agreement again. Switching methods or returning to sign-in clears acceptance.
- Phone login explicitly uses `shouldCreateUser: false`. New phone accounts use the Create account option, acceptance and provider OTP flow. SMS still requires a configured SMS provider.
- This client sends the accepted policy version with signup. A private, server-timestamped receipt is captured on new-account insertion. Later user-metadata edits cannot rewrite it. Older clients remain compatible and can still register without this new client checkbox; there is deliberately no global signup-blocking hook. Existing users are not asked to accept again by this release.
- Privacy Policy is also accessible from Settings. It accurately describes the beta's limitations, including lack of E2EE and incomplete deletion/export. Before public launch, the owner must supply their operator identity, a public support/privacy contact and reviewed retention terms. This beta text is not a legal compliance certification.
- Android root-screen Back requires two presses within two seconds. Backgrounding resets the sequence; an open keyboard is dismissed before arming exit. Pushed pages/dialogs retain normal Back. The system Home button leaves Pulse once as usual; it does not kill the process. Windows close behavior is unchanged.
- Profile placeholders use a photo icon rather than letters. Tap your profile photo/camera control to edit. Other people's photos open a larger view. Mobile Profile navigation displays your photo.
- Premium animated portraits support GIF files, up to 2 MiB and 512 × 512 in the picker. Static image selection is free. Reduced motion and hidden ticker scopes pause animation. Expired Premium displays a still frame. Failed image loads show the photo placeholder. The client keeps one still frame when motion is disabled, including animated PNG/WebP selected as a normal photo.
- Storage insert rules check owner, MIME and active Premium for GIFs. The profile-save RPC also checks changed avatar objects. This protects uploads, not downloaded files: a modified client or an external viewer can animate bytes it already possesses. Existing avatar read permissions were preserved. Client pixel-dimension validation does not replace a server media-scanning pipeline.
- Premium profile backgrounds now include Classic (also the free reset), Aurora, Sunset, Midnight, Ocean, Bloom, Studio and Circuit. The background extends over the profile header, with a higher-contrast name card. Existing free cover photos remain available.
- **Profile Signal** lets a Premium creator describe what they are creating, learning, available to help with or open to collaborating on, in up to 120 characters. It is profile metadata visible to signed-in visitors subject to blocking, including on private accounts. It is not a private message or a verified availability guarantee. The backend hides paid backgrounds and Signals after expiry. A free account can clear retained customization.
- Existing Pocket notes, quick replies, chat styles, requests, unread notification behavior, editor, feed, Reels, Premium-code history and Windows build fixes are preserved. Paid checkout and LiveKit deployment remain pending.

These are additions to Pulse's own identity. No claim is made that another platform lacks a similar feature.

## Backend

`supabase/schema/014_profile_identity.sql` was applied to the connected existing project on 2026-10-17. Do not rerun all schema scripts or reset the database. The numbered files are installation scripts, not Supabase CLI migration-history records. On a separate fresh backend, apply 001–014 in order.

New private tables: `policy_acceptances`, `profile_signals` (RLS enabled, direct clients denied). Authenticated invoker RPCs delegate to authenticated private functions with fixed search paths. Premium comes only from server entitlement records, never user metadata. Profile endpoints do not expose the actual subscription expiry: animation permission is returned for at most 60 seconds at a time. Avatar clients recheck it; offline failures disable motion. Existing limited account export does not include these new records.

## Verification

Passed locally:

- All Dart files formatted/parsed with standalone Dart 3.12.0.
- Pure profile rules analysis; signup/login/recovery consent rules, exit timing/reset, motion expiry and reduced-motion checks.
- Existing six standalone suites: chat/redemption state, appearance, visibility, streaming export, chunked upload and form validation.
- Python helper suite: 10 tests, one CMake-dependent fixture skipped because CMake is not installed here.
- Public config check and workflow YAML parse; both build jobs include the new offline tests and existing Flutter tests.

Passed against the connected backend with temporary fixture users and rollback:

- `profile_identity_security.sql`: acceptance capture, free/expired/Premium rules, GIF upload policy predicate, other-owner paths, Signal validation, blocked lookup, raw-table and anonymous access denial.
- `requests_privacy_premium_security.sql`: requests, unread counts, content privacy and one-time redemption retry behavior.
- `chat_tools_security.sql`: private notes, template ownership, styles, expiry and unread-preview isolation.

Advisors: new private tables intentionally have no direct-client RLS policies. The pre-existing leaked-password-protection warning remains: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection .

Not run here: Flutter dependency resolution, full Flutter analysis, widget tests, a real Storage API GIF upload, Android APK or Windows EXE builds, physical-device Back/GIF/OTP checks. New widget tests for consent and portraits are included for CI. SQL tests exercise policies and helper predicates; they are not a substitute for upload/rendering tests. Do not call this build production-ready based only on source checks.

## Build and try

1. Extract the source ZIP. Upload the **contents** of `pulse-messenger/` into the existing repository root, replacing matching files. Include `.github/workflows/main.yml`, `assets`, `lib`, `test`, `scripts`, `pubspec.yaml` and docs. Preserve private configuration/signing files.
2. Commit and start a new **Actions → Pulse native beta builds → Run workflow**. Do not rerun an old commit.
3. When both jobs succeed, download the Android and Windows artifacts. An Android debug APK is a beta build; the Windows installer includes its DLLs and data files.
4. Test a fresh email account: unread policy checkbox, readable policy, submit denied until checked, OTP then normal sign-in without checkbox. Test phone registration/login only if SMS is configured.
5. Test Back once/twice, wait over two seconds, keyboard open, nested edit page, Home/background/resume. Check Windows still closes normally.
6. Test free account static photo, GIF upgrade prompt and backend denial. Redeem an eligible code, select a small actual animated GIF, then view from another account. Test reduced motion, sign-out/account switch and expired entitlement fixtures on a separate test account.
7. Test all background presets, Signal creation/edit/clear, privacy copy and blocking. Check names at narrow widths and landscape.

No dependencies were added; the prior `ffi: 2.2.0` fix, native editor CMake installation rule, compiler compatibility definitions, build-log capture and Unicode-output fix are retained. A successful workflow/device test is still required; no workflow can be promised error-free before it runs.
