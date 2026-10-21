Current 0.5.4 chat update: [UPGRADE_0.5.4.md](UPGRADE_0.5.4.md). Older notes below are historical.

Current 0.5.3 changes and validation: [UPGRADE_0.5.3.md](UPGRADE_0.5.3.md). Older notes below are historical.

Current 0.5.2 changes and limits: [UPGRADE_0.5.2.md](UPGRADE_0.5.2.md). Earlier release notes below remain historical.

# Current status: Pulse 0.5.1

See [current upgrade and deployment evidence](UPGRADE_0.5.1.md). The notes below describe earlier source snapshots and are historical where they differ from 0.5.1.

# Pulse source review and LIVE stage 1 — 18 October 2026

This is a source/backend review, not an on-device app run. Flutter semantic analysis, native builds, media rendering and actual LiveKit broadcasts have not been verified locally.

## Implemented in this update

- Minimum **100 channel followers** to start a new livestream; database enforcement applies even to modified/older clients. Owners cannot count themselves; banned/currently suspended followers do not count. This is a Pulse beta policy, not a claim about TikTok requirements. No arbitrary total-viewer limit has been introduced; real capacity depends on infrastructure.
- Channel administrators host; fans can watch and followers can comment during an active live. Existing admin-only channel announcements remain separate.
- Host/channel-admin chat controls: pause/resume fan comments, choose slow mode (2–120 seconds), pin/unpin comments, hide comments, mute fans for 10 minutes and unmute them. Backend supports custom mute durations 1–1440 minutes. Mutes restrict chat, not viewing or LiveKit room access. Other administrators/host cannot be muted.
- Idempotent per-account likes, count and unlike. These are unique likes, not unlimited repeated taps. Camera off/on and microphone off/on are host-only.
- A chat reconnection warning clears after a successful poll. Live publisher/viewer room rendering is still based on the existing LiveKit client.
- Pulse Control → channel toolbar → LIVE follower minimum: authorized staff can change the global minimum, with an audit entry. Zero removes the follower requirement for controlled beta testing. Default/deployed value is 100. Ordinary users cannot change the policy.
- Updated pulse-live Edge source explicitly checks active account status before issuing tokens. This updated Edge source has NOT been deployed in this task.

## Backend deployment and verification

Schema installation scripts 001–018 were already installed. **019_live_controls.sql is now deployed to the connected Pulse backend. Do not rerun 001–019 or reset the database.** Existing account/chat records were preserved: before/after 4 profiles, 19 messages, 1 channel and no live sessions; follower minimum is 100. New private tables have RLS enabled and no direct client access. Scoped security-definer implementations remain in pulse_private; public RPC is security-invoker with an active-account guard.

All 19 scripts loaded in isolated Postgres. Seven security suites passed: requests/privacy/Premium, profile identity, activity, Control, channel verification, baseline channels, and new live controls. Live-controls and baseline-channel suites also passed on the connected backend using disposable fixtures and rollback. The small 2-follower fixture policy is only inside the rolled-back test; it did not change the deployed 100 threshold.

Dart formatting checks passed; pulse-live TypeScript syntax check passed. These do not prove Flutter semantic/native compilation or LiveKit runtime behavior. Security advisor still reports the existing disabled leaked-password-protection warning. RLS-without-policy notices are expected for intentionally private deny-all tables.

## Problems and setup still needed before release

| Priority | Finding | Required action |
|---|---|---|
| First | Recent Flutter profile/composer/watermark/live controls lack completed native CI/device validation | Build Android and Windows and test the supplied scenarios. Fix first actual analyzer/compiler error, not the warnings. |
| First | LiveKit broadcaster/calls need working infrastructure | Configure LIVEKIT_URL/API_KEY/API_SECRET as server-only Edge secrets, deploy pulse-live/pulse-call, and test camera/mic/TURN/reconnect/end from two devices. No secret belongs in Flutter config or chat. |
| First | Existing LiveKit room tokens are not immediately revoked on every account restriction | Add LiveKit participant removal/permission enforcement and periodic server reconciliation before public production use. A chat mute is not a video-room ban. |
| First | Closed-app social push is not configured | Configure FCM server credentials, token registration and deployment, plus platform-specific background behavior. Current foreground activity/local notifications are not proof of background delivery. |
| First | No genuine private-message E2EE | Implement and independently verify a protocol/device-key lifecycle before making that claim. Current access rules/TLS do not provide E2EE. |
| Before broad release | Paid Premium/gifts/coins/subscriptions are not connected | Payments, server ledger, store/provider receipt validation, refunds, fraud handling and payouts. Do not display fake balances or purchases. |
| Before broad release | Signing/update/distribution needs final setup | Stable Android signing, Windows installer/code-signing strategy, durable download releases, rollback/versioning and an actual updater. |
| Before broad release | Account lifecycle and service operations need completion | Full account deletion, recovery/MFA/device sessions, media cleanup/scanning, backups, rate/load tests, moderation operations and privacy-policy review. |
| Before broad release | Mail queue is not end-to-end email delivery | Configure verified sender/provider and deploy/schedule the supplied mail dispatcher. |
| Performance | 4 GB Android/Windows media behavior not measured | Test portrait/landscape codecs, long files, upload cancellation, disk pressure, scroll memory and network interruption. Watermarking re-encodes locally and needs temporary storage. |

## LIVE roadmap, not claimed implemented

1. **LiveKit validation and media controls**: front/back camera switching, audio/speaker routing, adaptive quality testing, connection health, server participant removal and stream closure reconciliation.
2. **Collaboration**: guest requests, host accept/reject/invite, approved publish grants, guest removal, split/grid layouts and co-host sessions. Do not grant camera publishing to arbitrary viewers.
3. **Richer safety/engagement**: delegated session moderators, keyword filters, report/escalation tools, Q&A, polls, free reaction animations, and stream discovery/scheduled events/follower alerts.
4. **Production/creator tools**: consent-aware recording, replays/clips, retention/watch-time analytics, music rights/effects/AR pipeline, screen sharing/OBS ingest and reconnection tests.
5. **Monetization**: gift catalog/coins/wallet/payouts, paid subscriptions/fan badges, battle scoring and leaderboards backed by validated server events. Gifts/coins were previously deferred and remain unimplemented. Shopping/affiliate services would be a separate product integration.

TikTok reference features include multi-guest, co-hosting, moderation, Gifts/subscriptions and LIVE matches; this update does not claim complete parity. Official references: https://support.tiktok.com/en/live-gifts-wallet/tiktok-live/what-is-tiktok-live and https://support.tiktok.com/en/live-gifts-wallet/tiktok-live/live-match .

## Device acceptance checklist

- Build both consumer/staff workflows from the new commit. The package is cumulative, including previous icon/profile/chat/watermark changes.
- On a channel below 100 followers, Go live shows progress and server start RPC rejects it. Staff can use a temporary smaller policy for private tests, then restore 100; do not create fake followers.
- After configuring/deploying LiveKit, host on one device and follow/watch on the other. Confirm viewer has no publishing permission.
- Verify one like per account, unlike, comments only from followers, paused fan chat, 30-second slow mode, pin/hide, 10-minute mute and unmute; attempts from an ordinary viewer must fail server-side.
- End the live; confirm the other device stops and cannot send comments. Disconnect/reconnect the network and confirm no permanent stale chat warning. Test host exit and expired lease.
- Separately test downloaded watermark MP4s outside Pulse, microphone recorder, keyboard shortcuts and the profile grid. They are not proven by passing SQL tests.
