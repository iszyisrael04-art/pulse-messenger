## 0.4.5 update — current source and user test

User reports successful two-device chatting with their brother on 15 October 2026. Exact build/devices and additional flows were not specified. New source adds bounded JSON data export, masked password/confirmation/nonce controls, code resend cooldown, diagnostics, safer sign-out and build-config preflight. Standalone tests pass; native/backend integration of these new controls is not verified. See [UPGRADE_0.4.5.md](UPGRADE_0.4.5.md) and [RELEASE_READINESS.md](RELEASE_READINESS.md). No LiveKit, schema, billing or push-dispatcher deployment changes in this patch.

## 0.4.4 update — current source

See [UPGRADE_0.4.4.md](UPGRADE_0.4.4.md) for the authoritative changes, verification and limitations. Backend 012 is deployed; its new security suite has **not passed** (fixed fixture, rerun blocked by automatic review usage limit). Message requests, private audience, retry-safe redemption and paid profile themes are implemented. Native Studio editors, menus/downloads and running-app notification/count UI are implemented in source but await native builds and device validation. Windows is branded Pulse with Pulse.exe. Full TikTok editing, closed-app push, E2EE and paid billing remain incomplete.

The table below describes the earlier baseline; this update note takes precedence where behavior changed.

# UI/autoplay patch 0.4.3

See [UPGRADE_0.4.3.md](UPGRADE_0.4.3.md) for original branding, interface polish, visibility-aware feed autoplay and the remaining native verification.

# Appearance patch 0.4.2

Local account themes/wallpapers and native/Flutter startup source are added; see [UPGRADE_0.4.2.md](UPGRADE_0.4.2.md). Native compilation/device checks remain pending.

# Current patch: PULSE 0.4.1

See [UPGRADE_0.4.1.md](UPGRADE_0.4.1.md): native preview/cover source, 500 MiB free eligibility with infrastructure restrictions, Premium redirect, hashtags, videos/profiles search and suggestions, recent-view trending. Connected SQL tests and local transport tests passed; native build/device checks remain pending. Crop/trim/export and LiveKit setup are still incomplete.

# Feature status — PULSE 0.4

Source implementation and passing SQL tests do not establish native-device functionality. Build/UI/media verification remains required. Historical messaging coverage follows the current social coverage below.

| Feature | Implemented/tested evidence | Remaining work |
|---|---|---|
| Existing accounts/auth/messages/groups | Existing modules preserved; core authorization/Premium regression tests passed | Native regression tests; SMS provider, E2EE, stronger abuse controls |
| Home text/photo/video/multi-photo feed | Native source implemented; publishing, privacy and pagination SQL tests passed | Native upload/playback/scroll validation; recommendation ranking, global search and media processing |
| Likes/comments/save/repost/share | Source and backend implemented; authorization/idempotency/visibility tests passed | Native controls tests; external web share links; richer repost timeline |
| Follow/unfollow/private requests | Implemented with approval, block checks and private-profile/repost isolation; SQL tests passed | Native request workflow tests; full followers list/pagination |
| Reels | Separate vertical single-player source; same authenticated social APIs, Reel validation and counts tested in SQL | Swipe/autoplay/decoder/network tests; transcoding, adaptive streaming, music/effects/sound library, hashtag search |
| Profile/cover/private account | Source, secured storage/account RPCs and follower counts implemented | Device editing tests; broader privacy controls; identity-verification application/operator workflow |
| Creator Studio/drafts | Owner-only drafts and actual total counters implemented; SQL isolation tests passed | Native draft/race tests; time-series analytics, watch time, editing tools and monetization |
| Social reports/moderation | Restricted queue, operator review and hiding implemented/tested in SQL | Native review tests; restore UI, comment reports, appeals, account suspension and operational workflows |
| Communities | Existing group-chat list retained | Public/private social communities, pictures/descriptions, join/leave, membership/admins, community posts and announcements are not implemented yet |
| Premium | Historical plans/entitlements/one-time code preserved; redemption backend regression passed; profile badge/code UI restored | $3/month paid billing, full Premium benefits and fraud/entitlement reconciliation remain planned |
| Calls/statuses/channels | Existing native source preserved; message/status media and channel/live SQL regression tests passed | LiveKit setup and two-device media tests; call suite rerun encountered a service transport error; background calls/push still incomplete |
| Performance/caching | Lazy lists, keyset pages, reduced image decoding, bounded image/URL cache and one Reel player in source | 4 GB Android/Windows measurements, codec validation, disk caching/offline media, CDN/transcoding and load tests |
| Security/distribution | New tables have RLS; guarded RPCs, no client server secrets; existing build/signing identifiers retained | Independent security review, quotas/cleanup/scanning, MFA, signed production releases, updates and operating procedures |

## Remaining safe stages

1. Pass Android/Windows native CI and the supplied two/three-account device checks. Fix observed build/runtime issues before broader rollout.
2. Implement real public/private social communities and announcements on separate tables without altering existing chat groups.
3. Expand Creator Studio, content search, social notifications, verification application/review and richer editing tools; add server media processing and quotas.
4. Finish security/operations: audited E2EE/device linking, MFA/account lifecycle, spam protection, cleanup, moderation, recovery, load tests and low-end benchmarks.
5. Add signed releases/updates, future iOS and later explicit paid billing. Gifts/coins remain deferred.

# Historical messaging coverage — Pulse 0.3

**Implemented** below means client/server source exists; it does not mean this release compiled or passed device testing. **External setup** requires a provider/configuration. **Pending** means additional development. No full WhatsApp parity or production-readiness claim is made.

| Area | Implemented in the staged beta | External setup / pending work |
|---|---|---|
| Authentication | Email/password, code verification/recovery, username/password, persistent sessions, global/local sign-out | SMTP delivery; phone OTP needs SMS; MFA/passkeys, account deletion/export, per-device revocation, captcha and stronger abuse protection pending |
| Profiles | Display name, unique username/ID, bio, profile photo, blocking/reporting, theme toggle | Animated photos, granular presence/privacy, contact management, wallpaper and advanced account settings pending |
| Messaging | Private/group text, emojis, replies, text forwarding, edit, delete for me/everyone, reactions, stars, loaded-message search, read receipts, persisted outbox/cache | Typing/online/last-seen, delivery receipts, pins, global/paginated search, rich reply previews, media forwarding, robust sync at scale pending |
| Files/photos/videos | Private storage uploads, on-demand photo display and in-chat audio/video playback, external document opening | 10 MB chat cap; HD controls, compression/thumbnails/transcoding, camera composer, video notes, resumable transfers, scanning and quotas pending |
| Voice messages | Native recording/pause/resume/discard/review/send, actual sampled waveform, playback/seek/speed | Device/codec verification needed; transcripts, consecutive playback, encrypted local recording and background recording pending |
| Calls | Private/group voice/video source, up to 8 members, accept/decline, history, busy checks, mute, camera controls, Android speaker, SDK reconnect, authorized signaling | LiveKit credentials/TURN and device tests required; closed-app incoming calls, Android foreground service, screen sharing, links, handoff, effects, favorites and reliable server eviction pending |
| Chat organization/design | Rounded gradient bubbles, lively Pulse palette, light/dark, responsive native layouts, desktop/mobile navigation, incoming avatars only | Custom lists/filters, archived/locked/pinned chats, wallpaper/themes, accessibility/performance audits and richer loading transitions pending |
| Groups | Create/add/remove members, promote/demote admins, group text/media and small calls | Pictures, invite links, member permissions, polls, events/RSVP/reminders, announcements, mentions, history sharing and large-group scaling pending |
| Communities | Group list | Multiple-group community model, community admins, membership and announcements pending |
| Status | Text/photo/video, 24-hour visibility, contact/block access checks, fullscreen viewer and own deletion | Replies/likes/viewers, audience selection, mentions, music/layout tools, expiration worker and storage cleanup pending |
| Channels | Public discovery/list, photo/name/description, admin-only posts, followers, reactions, admin management, host/viewer livestream source and follower live chat | LiveKit setup required; private channels, verified badge process, polls/audio posts, QR/invites, paginated search/counts, moderation and scaling pending |
| Notifications | Local Android/Windows message and incoming-call alerts while running; Android FCM client/queue/dispatcher source | OS testing needed; FCM dispatcher deployment withheld, provider/scheduler setup required; Windows closed-app push and call wake-up pending |
| Stickers/GIFs/avatars | Emoji text and supported image files/GIF display | Sticker packs/editor/search, GIF provider/search, custom avatar creation and interactive media pending |
| Locations/contacts | Username-based chat creation | Phone/address-book discovery, contact cards, live/static location sharing and contact privacy pending |
| Security | Supabase Auth, TLS, private storage, scoped tokens, RLS/RPC authorization, sender checks, blocking/reporting and several rate limits | **E2EE absent**; audited encryption protocol, key verification/rotation, encrypted backups, view-once/disappearing messages, app/chat lock, MFA enforcement, comprehensive spam protection and independent security review pending |
| Multi-device/backups | Same backend and realtime reconciliation, persistent sessions, native Android/Windows sources | Secure linked-device enrollment, scalable delta sync, backup/restore/recovery, migrations and device handoff pending; iOS future |
| Administration | Restricted operator access and basic report/channel management | Suspensions, audit logs, analytics, announcements, feature flags, moderation workflows and operational monitoring pending |
| Purchases | Premium benefit screens removed in 0.3; historical records preserved; 0.4 restores badge/redemption controls | Premium deferred; gifts/coins/billing/refunds/store compliance not implemented; no purchase button or entitlement claim |
| Advanced/regional | Pulse-specific channel livestream/fan chat source | AI assistant, business catalog/automation, regional payments and parent-managed accounts need distinct product scope/provider integration; proprietary Meta services are not copied |
| Distribution/updates | Android APK and native Windows EXE/installer CI configuration, setup scripts, SQL schema and public config examples | 0.3 native compilation/device testing, lockfile commit, production signing, auto-update implementation, stores, iOS and low-end benchmarks pending |

## Remaining implementation sequence

1. Pass native CI and two-device call/media/notification tests; configure LiveKit and close media-room revocation gaps.
2. Add pagination, delivery/presence controls, media forwarding, pins and full message search. Add group invites/pictures/polls and richer status privacy/replies.
3. Build communities, private channels, channel moderation/discovery and reliable background notifications/calls.
4. Design and implement audited E2EE, secure device linking, backups, MFA and account lifecycle; run security and load reviews before a public launch.
5. Implement signed releases/updates and future iOS support. Gifts/coins or Premium require a later explicit billing update.

The security work is a release requirement; feature quantity alone does not make this beta ready for public production use.
