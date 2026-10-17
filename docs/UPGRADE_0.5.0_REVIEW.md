# Historical predeployment review — superseded deployment status

The owner subsequently approved deployment and scripts 016–018 were applied successfully. Read [the current deployment notes](UPGRADE_0.5.0.md). Earlier blocked/not-deployed instructions below describe the pre-approval state; feature limits still apply.

# Pulse 0.5.0 — Source prepared; production deployment awaiting approval

**Do not replace the working installed 0.4.9 app yet.** This source build requires database scripts 016–018. They are NOT deployed. The live backend remains through 015. The account gate intentionally prevents normal app entry when its backend access-check RPC is missing. Native builds can be produced for review, but they are not ready for ordinary users until deployment and device checks pass.

Automatic approval review rejected the proposed production migration because it adds moderation/appeals, changes storage and restrictive RLS policies across existing Pulse tables, and guards existing RPCs. A mistake could lock users out or disrupt service. No workaround or partial production execution was attempted after rejection. The full change is now reviewable in source and has passed isolated database tests. Owner approval is still needed before a deployment can be reconsidered.

## Included source

- Communities retain the existing group-chat memberships. Legacy groups become private community cards; new communities get unique handles, join requests and admin approval/decline through Pulse Mail. Existing administrator invitations remain possible. The current group membership ceiling is 101; multi-group umbrella communities are not added here.
- Community profile pictures appear as profile chips when one to three memberships are visible. Four or more visible memberships use a Communities button. Private-community identities are visible only to their own members, even when another user has joined them. The current community list/profile projection is limited to 100 items.
- A caption/video can tag joined communities with `!community_handle`, up to 10 recognized handles. Existing `@username` person tags and #hashtags remain. Non-members cannot generate a community tag alert. Other current members/admins receive an in-app event only when the underlying content is readable. A tag does not override public/followers/private audience rules. Self-post notifications are suppressed. Community alerts use the existing in-app 30-second activity refresh, not closed-app push.
- Settings and Chats have **Pulse mail & requests**: community join requests for admins, message requests, personal system mail and Pulse announcements. Mail refresh is explicit on open/refresh/actions; it is not an external email inbox or arbitrary Gmail reader.
- **Pulse Control** is a distinct native build from the same Flutter project and Supabase backend, with Android application ID `com.pulsemessenger.pulse_control`, Windows binary `PulseControl.exe`, a separate installer AppId and a separate stored auth-session key. Android native Activity/namespace remain correctly mapped. It lists/searches usernames with pagination; verification has a direct button, while ban/suspend/release/unverify are also available through the account menu.
- Staff roles come only from the existing private admin table. No accounts were promoted to staff. A client build flag or user metadata does not grant staff permission. A staff account must be provisioned separately by an authorized project operator; no public self-enrolment exists. Self/staff bans are denied to prevent lockout. Actions record an audit entry and require confirmation; ban/suspend require a reason and suspension accepts 1–365 days.
- Verify/unverify changes the existing social verification flag, so profiles, posts and Reels show/remove the badge after refresh. Verification here means staff approval, not government-ID, legal identity or automatic video verification.
- Bans/suspensions deny normal RPCs and raw public/storage access using current backend account state, including requests made with an existing access token. Expired suspensions permit access again. Release reverses either restriction. The updated consumer app checks on entry/resume and every 15 seconds while foregrounded; it displays a red restriction sign and signs out locally. Older app versions cannot display this new notice, although backend access rules apply once deployed.
- The restriction screen permits a separate, limited sign-in path for appeals. Only status/appeal APIs and owned appeal media remain accessible; normal content stays blocked. A private, random phrase expires after 15 minutes. A user records it using their device camera and selects the video; the app does not add an in-app camera recorder. Videos are capped at 25 MB, one deterministic object per challenge, with three challenge starts/day. Staff manually review the clip/phrase and can accept/release or reject. This is NOT automatic face recognition, speech matching or a liveness guarantee. Video file-content scanning, transcoding and automated identity verification are not implemented.

## Email delivery requires external setup

Verification/restriction actions create personal in-app mail plus queued email for accounts with confirmed email. Phone-only accounts receive in-app mail. Appeal submission queues a message to `pulseservicemanagement@gmail.com` with the user's explicit video-sharing consent.

`supabase/functions/pulse-mail-dispatch/index.ts` is provided but NOT deployed or configured. It uses a private service-role-authenticated worker and Brevo transactional API. The operator must configure server secrets `BREVO_API_KEY` and `PULSE_SENDER_EMAIL` (a verified sender), deploy the worker, and invoke it from a secured server scheduler. Never put these credentials in Flutter/config/public GitHub files or share the service key with a client. The job claims up to 10 items at a time; provider acceptance is recorded, not guaranteed inbox delivery. Failed/uncertain/sending jobs require operator reconciliation; blind retries can duplicate mail. No messages were sent and no mailbox ownership/deliverability was tested during this work.

Appeal emails include a private video link valid for one hour; anyone who receives that link can view it until expiry. Staff Control opens a fresh five-minute link. Consent text explains this. Mail/video retention and orphan-file cleanup must be defined and operated before public launch. The existing limited export does not yet include the new moderation/appeal/inbox tables.

## Restriction limitations and review scope

016 creates account_limits, audit, system_mail, email_jobs, community_cards/requests and appeals in the private schema. Raw clients are denied. It adds current-account restrictive RLS policies to existing public Pulse tables and Storage, with a scoped exception for owned appeal media. It prefixes existing public invoker SQL RPCs with the account guard, excluding status/appeals. 017 adds community-tag events and updates activity visibility. 018 exposes an email worker only to service_role. Future RPCs must explicitly preserve the access guard; later schema scripts must not accidentally overwrite it.

Downloaded files and already-issued signed URLs cannot be recalled. Existing signed media links can survive until their expiry. LiveKit room/call token revocation needs the later provider work; this change does not claim to disconnect an already-authorized LiveKit session. Banning does not automatically delete old posts/accounts or grant staff access to private chats. Auth can issue a session for the restricted appeal path; backend authorization, rather than the presence of a JWT alone, controls normal access. Online checks and additional device/provider tests are required.

## Isolated test evidence

The entire source schema 001–018 loaded successfully into disposable PGlite PostgreSQL with pgcrypto/pg_trgm and minimal Auth/Storage stand-ins. These stand-ins do NOT emulate Supabase Auth HTTP, actual object bytes, signed-URL validation, Realtime, SMTP or LiveKit.

Passing SQL suites:

- Existing request/privacy/redemption, Premium profile identity and activity suites.
- New `test/control_security.sql`: ordinary metadata cannot grant staff; request cannot self-approve; owner inbox sees requests; approval grants membership; community tags reach members and not outsiders; profile membership projection; verify/email queue; staff self-ban denied; banned stale JWT cannot SELECT profiles or use normal RPC/send; restricted appeal upload policy and one-time submission; staff acceptance releases; unverify; timed suspension expiry; email worker inaccessible to clients; existing RPC guard coverage.

All tests used disposable fixture users and rollback. No production data was tested or changed by these suites. Backend security/performance advisors for 016–018 have NOT been run on the production project because deployment is blocked. Existing through-015 advisories, including leaked-password protection, remain documented in the earlier release notes.

Local source checks: 77 Dart files parsed/formatted; pure activity/support/profile/chat suites passed; Python suite 11 tests, one CMake-dependent fixture skipped; staff native identity/idempotency test passed; both workflow YAML files parse. Full Flutter semantic analysis, widget tests, APK/EXE compilation, real private-video upload/playback, sign-out/session behavior across physical devices, SMTP delivery and real Supabase enforcement remain unverified.

Reproduce database tests without any production connection:

```sh
npm ci --prefix test/isolated_backend
node test/isolated_backend/run.mjs
```

## Build paths after review

Keep the same repository. Upload matching source files, including both workflow files; do not delete configs/signing assets. Consumer builds use **Pulse native beta builds** (`main.yml`). Staff builds use **Pulse Control staff builds** (`control.yml`), which first runs `scripts/configure_staff.py` and passes `--dart-define=PULSE_STAFF=true`. Use fresh checkouts for consumer and staff native runners; do not mix generated identities in the same dirty build folder.

Both workflows include the isolated backend test job and existing Flutter checks. Windows diagnostic/Unicode/compiler/CMake installation fixes and the ffi pin are preserved. Staff Firebase push initialization is disabled; its Android package does not share the consumer Firebase identity. APKs remain debug-signed beta builds; release signing, updates and device tests are separate requirements. No build is promised error-free before CI runs.

Before deployment: review scripts 016–018 and the local fixtures, confirm an authorized staff account and recovery route, capture the project's appropriate backup/rollback plan, and obtain approval for the access-rule changes. Do not run these scripts manually to bypass the deployment review. No production backup was created here. Existing 0.4.9 remains the usable release until this upgrade is approved and verified.
