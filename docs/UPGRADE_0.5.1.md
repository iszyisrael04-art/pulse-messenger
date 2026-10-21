# Pulse 0.5.1+16 — 18 October 2026

## What changed

- Chats/Calls/Updates/Channels use icons with accessible tooltips and spacing. Followed channels have unread badges on the tab and channel card.
- Channel admin/announcement dialogs now use a state-owned TextEditingController disposed only when the dialog unmounts, including its closing animation. The same unsafe caller-disposal pattern was removed from social prompts, status captions, general chat prompts, admin prompts and LIVE follower-policy editing. Username lookup in channel promotion now handles no matching account without a generic image error.
- Pulse Control has a Communities toolbar button with searchable staff-only verify/unverify controls. Community badges appear in community cards and joined-community chips on profiles. Existing account/channel verification is preserved.
- Existing community/group incoming messages still use authenticated unread previews and group-message bubbles; their bubble title now includes the group/community name and sender. Channel announcements have a separate current-follow/current-block-aware unread RPC, per-account read state, realtime hints and a 15-second reconciliation fallback while the app runs. Initial existing subscriptions do not replay old history. Reading a loaded channel clears its alert; another device's reads reconcile on refresh. Only opt-in enabled notifications show alerts. This is not terminated-app FCM delivery.
- LIVE Party supports a host plus up to eight approved guests, audio/video requests, host/channel-admin approve/reject, explicit guest Join stage, cancel/leave/remove, automatic stage grid, camera/mic controls, and existing likes/slow-mode/chat moderation. Audio-only guest grants are restricted to microphone publishing.
- Current party clients start with read-only join JWTs and request publishing grants from pulse-live after server authorization. Room permissions are updated when requests are approved or removed. The host reconciles active publishers periodically. Existing older host clients keep their original publisher-token behavior for compatibility; old viewers never gain publishing grants.
- Native app/installer version is now 0.5.1+16. Both consumer and staff identities remain unchanged. All earlier profile, icon/splash, chat, Premium redemption, media and watermark source changes are included.

## The red-screen report

The screenshot shows a Flutter inherited-widget teardown assertion, not the first exception/stack that caused it. The user reported it after making a channel administrator and posting in a channel. Inspection found premature TextEditingController disposal in their shared dialog helper; this concrete bug has been corrected. It is not yet proven to be the sole cause of the screenshot.

`test/text_prompt_test.dart` exercises the actual channelPrompt helper through repeated Save/Cancel and closing animations with an active text field. It is included for the existing Flutter-test CI step. No assertion was disabled and no global error handler hides failures. Flutter widget/native tests could not be run locally. If the red screen returns after a fresh build, collect the FIRST exception and stack from flutter run/Android logs and the exact preceding action.

## Backend deployment and checks

020_community_badges_channel_updates.sql and 021_live_party.sql are already deployed to project mhebynaprmhxfbcsiqgf. Earlier 001–019 were present. Do not run all scripts again. pulse-live was updated to ACTIVE version 2 with its existing custom Auth.getUser JWT validation and existing server environment preserved. No server secrets were read or put in client code.

The new private tables have RLS enabled and no direct client grants. Community verification checks server-side staff membership, including against user-metadata privilege spoofing, and writes staff audit records. Live seat decisions check current channel administrator membership, current following, account status, capacity and request state. User-held initial party tokens cannot promote a viewer; only the server issues participant permission changes.

Baseline/postcheck both showed 6 profiles, 21 messages, 1 channel, 1 community and 0 live sessions. No real account/community was verified or banned by tests. The follower minimum remains 100; fixture changes were rolled back. Staff can change it in Pulse Control → Channels → LIVE follower minimum, including 0 for controlled beta tests.

Completed checks:

- All 21 installation scripts loaded in isolated Postgres.
- Nine SQL suites passed, including community verification/announcement privacy/read counts and party request/approval/removal/capacity rules.
- Both new SQL suites also passed on the connected backend using disposable records and rollback. One transport request-state error occurred; its retry passed.
- Mocked LIVE endpoint tests passed for read-only party JWTs, unauthorized approval, audio-only grants, removal, active accounts and older-host compatibility. These are mocked network tests, not a real LiveKit session.
- Deployed unauthenticated LIVE endpoint returned HTTP 401.
- Dart parse/format checks and pure Dart support/chat-state tests passed. Python helpers: 10 passed, 1 skipped. The Edge source passed TypeScript syntax checks.
- Security advisor still reports the existing leaked-password-protection warning; RLS-without-policy notices on intentionally private deny-all tables remain informational.

Not completed: full Flutter analysis/widget tests, native compilation/device testing, actual LiveKit camera/audio/reconnect testing, watermark export tests on native devices, load/performance measurements or independently audited production security.

## Installation/build

Upload the cumulative update's files into matching folders of the EXISTING repository and commit. Keep other files and both workflows. No main.yml/control.yml changes are necessary. Start NEW Pulse native beta builds and Pulse Control staff builds runs. The included pubspec and installer versions must be uploaded too. Do not upload the ZIP as source or delete the repository.

Database changes and pulse-live deployment above are already complete. Real broadcasting still requires a reachable LiveKit server and correct existing LIVEKIT_URL/API_KEY/API_SECRET configuration. Readiness of those credentials/infrastructure was not tested. Keep secrets in server environment only.

## Acceptance tests on Android and Windows

1. Repeat the exact failing flow: open a channel, add an existing administrator by username, close the dialog; post an announcement; repeat and cancel with keyboard open. Check that no red screen/first exception appears.
2. Verify and unverify a community from the authorized staff app. Reopen community/profile lists on the consumer app to see the blue badge. An ordinary account must not be able to verify it.
3. Enable notifications. Use one account as admin and another as a community member/channel follower. Send a new message/announcement while the recipient views another section: check unread bubble and badge. Open it, confirm count/alert clears; unfollow/block and confirm old announcements do not replay. The app must be running for this implementation.
4. After LiveKit is configured, host on one device and watch/follow on another. Request an audio seat, approve it and tap Join stage. Confirm no capture before Join; audio-only seats cannot publish camera. Test video seats, microphone/camera controls, cancel/reject, leave, removal, eight-guest capacity and ended-session denial. Use host/staff-controlled accounts on real devices, not fake followers.
5. Interrupt network during permission changes and reconnects. A failed server permission update reports an error; retry or end the live. The SQL/backend source cannot prove immediate real-media revocation. Self-hosted/token-refresh behavior and restriction enforcement still require end-to-end validation before public launch.

## What LIVE Party does not claim

This is the nine-seat party workflow, not every TikTok LIVE feature. Paid gifts/coins, battles/leaderboards, subscriptions/payouts, guest invitation by username, AR/beauty/music effects, shopping, scheduled events, recordings/replays/clips, OBS ingest and full production moderation operations are not implemented by this release. Closed-app push, E2EE, paid billing, production signing and an automatic updater also remain separate unfinished work. No fake purchase, gift balance or tested-media claim is added.
