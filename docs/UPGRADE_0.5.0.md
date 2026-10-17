# Pulse 0.5.0 — Backend deployed; native builds and device tests pending

On 2026-10-17, the owner approved live deployment of scripts **016–018** after the access-rule risk explanation. They were then applied in a single atomic transaction to the existing Supabase project. The prior automatic approval rejection was reconsidered with this explicit approval, matching production preflight and passing isolated tests. Deployment succeeded. **Do not rerun 016–018 or reset the database.**

Community cards/requests, community-tag activity, Pulse inbox, staff moderation, account restrictions, video appeal APIs and the service-only email queue worker API now exist in the connected backend. The Flutter source and separate staff build workflow are included. Feature details and their limits are recorded in [the historical predeployment review](UPGRADE_0.5.0_REVIEW.md); its earlier statements that deployment is blocked are superseded by this page.

## What passed after live deployment

The request/privacy/redemption, Premium profile identity, activity and new control/security SQL suites all passed on the connected project. Each used temporary fixture accounts, actions and metadata-only storage objects inside rolled-back transactions. No real account was verified, banned, suspended, released or granted staff privileges; no actual appeal video was uploaded and no mail was sent.

Postflight confirmed the pre-existing account count was preserved, no real restrictions/appeals/email jobs remained, no staff account was added, and no normal client Pulse RPC lacked the account guard. The complete disposable PostgreSQL schema/security test harness also passed again locally.

Security advisors report intentional RLS-without-direct-policies on private tables and the existing leaked-password protection warning: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Performance advisors found no new unindexed foreign keys; pre-existing missing-index and informational unused-index entries remain. No indices were dropped based on beta usage statistics.

## Next steps

1. Upload the ZIP's `pulse-messenger/` contents to the same GitHub repository root, replacing matching files. Include `.github/workflows/main.yml`, `.github/workflows/control.yml`, assets, scripts, lib, tests and pubspec. Preserve local secrets/signing files.
2. Start a new **Pulse native beta builds** workflow to build the consumer Android APK and Windows application. Keep your current installed version until those builds pass, then test on both phones.
3. **Pulse Control staff builds** creates the separate Android staff app and Windows `PulseControl.exe` installer. It requires an explicitly authorized account in the private staff-role table. No staff role is currently provisioned; the owner must identify the exact Pulse username to authorize. A username does not itself grant privileges, and no client flag can bypass the server checks.
4. Actual outbound email is still pending: deploy/configure `pulse-mail-dispatch` with server-only Brevo credentials and a verified sender, then invoke it from a secure server scheduler. The database queue is deployed; the Edge Function is not deployed or configured here. Verification and appeal messages will queue, not magically arrive in Gmail. Never place provider or service-role keys in client files or public GitHub configuration.
5. Test communities, !community tags, profile membership chips/4+ button, join approvals, mail requests, staff search/verify/unverify and moderation on a dedicated test account. Check restriction notices/logout, appeal upload/expiry/review, suspension expiry and release on physical devices.

## Remaining verification limits

Full Flutter analysis/widget tests, native APK/EXE compilation, real Supabase Storage video upload/playback, foreground/background notification delivery, external email handoff/delivery and multi-device session enforcement have not been run here. CI includes all existing checks plus isolated SQL fixtures. Closed-app push and LiveKit provider deployment remain pending. Existing signed URLs can live until expiry; downloaded copies and issued LiveKit tokens cannot be recalled by these database rules. The release is a private beta, not a verified production-ready system.

No new Flutter dependencies were added. Existing Windows CMake/Unicode fixes and ffi pin are preserved. The historical review contains the appeal privacy/retention limits, manual video-review behavior, storage caps, email-link expiry and public/private community behavior; those still apply. No production backup was created by this task.
