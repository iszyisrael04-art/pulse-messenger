## User-reported result — 15 October 2026

The user and their brother successfully tested chatting on two devices. Build/OS combination and detailed scenarios were not specified. Record this as a user-reported chat pass, not a blanket pass for the checklist or 0.4.5 changes. Next test Settings export/password/resend/sign-out and the 0.4.4 request/editor/privacy flows. LiveKit is deferred by the user.

# PULSE 0.4 native acceptance checks

Run after both CI jobs pass, with a staging project and three test accounts A/B/C. These checks have not been executed on devices here.

1. Sign in to existing accounts on Android/Windows. Confirm existing private/group chats, files, voice notes, video statuses, channels, settings and call history. Check incoming avatars and absence of an outgoing own avatar. Confirm the new six-item navigation at phone/desktop widths.
2. A publishes text, eight photos, one video and one Reel. Try mixed video/photos, nine images, empty content and over-limit files. Verify real completion/errors, no false success and safe publishing retries after a lost response.
3. B refreshes Discover, follows A and checks Following. Load multiple pages including identical timestamps; confirm no repeats/skips. Unfollow A and check removal. Open photos and test video codecs, sound, seeking and failed-link retry.
4. In Reels swipe rapidly back/forth and reach a newly loaded pagination page. Confirm one video at a time, correct caption/creator, auto play, tap pause/resume, mute/unmute, background pause and player disposal when switching tabs. Test separate networks and slow/reconnected internet.
5. B likes/unlikes, comments/deletes own comment, saves/unsaves and reposts/unreposts. A can remove an inappropriate comment on A's post; C cannot edit/delete someone else's content. A edits a caption and deletes a post. Refresh B and check privacy/deletion changes.
6. A becomes private. C cannot see A's content or repost activity before approval. C requests a follow; A accepts/declines. Verify accepted versus pending access. B saves private content then unfollows: saved private content/media must no longer be retrievable through new requests.
7. B shares a private post into a chat containing C. The message must contain only a reference, not a copied caption/media. C's Open Pulse post must deny access until eligible. Blocking must prevent social content/media and follow actions. Previously downloaded content/signed URLs can remain available briefly; verify no new unauthorized links.
8. A saves a draft, exits/reopens Profile → Drafts, edits and publishes once. B/C must never see it as a draft. Check cover/profile edits, counts and creator totals. Unique views should deduplicate repeated opens/playback per account; owners are excluded. Treat metrics as beta, not audited revenue data.
9. Use a disposable eligible verified account for `30DAYSPULSE`, verify active backend badge and reject a second redemption. Do not redeem a real user's one-time promotion solely for testing. No paid billing is enabled.
10. B reports a post. C cannot access operator review/moderation. A trusted test operator can review reported media, hide it and inspect the report state. Test raw RPC/table/storage negative access as well as buttons; confirm no client/server secrets in release files.
11. On 4 GB Android and Windows devices, measure frame time, memory, crashes, player/decoder counts and bandwidth over a long scroll. Test an optimized 720p MP4 and an unsupported file. Confirm there is no simultaneous offscreen audio. Test keyboard resizing, accessibility text scaling and narrow layouts.
12. Test update signing and preservation of existing login/cache before distribution. Confirm LiveKit credentials/TURN separately for calls/live. Closed-app push/calls, E2EE, full communities, paid billing and automatic updates remain outside this acceptance claim.
