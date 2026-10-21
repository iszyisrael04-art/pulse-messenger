# Pulse 0.5.2 — status replies, profile photos and social layouts

This cumulative update includes the complete 0.5.1 channel/dialog, verification, notification and LIVE Party source changes. Read UPGRADE_0.5.1.md for that work and its remaining limitations.

## Added in 0.5.2

- Reply privately from another person's active text/photo/video status. Successful sending opens the private chat. A status icon on the message opens the original status after a fresh access check. Expired/deleted/inaccessible statuses show an unavailable notice. Replies survive status deletion and respect blocking, rate limits and pending message requests. A stable message UUID makes network retries idempotent; status replies require a connection and are not added to the offline outbox in this release.
- Profile photos: up to 15 MiB (15,728,640 bytes) in the picker, shared upload helper and backend avatar bucket. JPEG/PNG/WebP stay available to free accounts; animated GIFs remain Premium with existing 512 × 512 restriction. Channel and community photos use this shared helper too. Profile cover photos retain their separate 10 MiB limit.
- Posts no longer have the old eight-photo count cap: add photos repeatedly in the composer. Attachment metadata has a 1 MiB bound to protect the database. Existing free/Premium per-file rules and provider storage quotas still apply; this is not unlimited file size or storage. Reels and video posts remain one video per post.
- Profile header: centered large tappable photo with an add control for your own account, display name and verification/Premium badges, edit control, username, Following/Followers/Likes and centered bio. Real cover photos and all existing tools remain. Icon tabs and the three-column content grid are preserved.
- Updates: horizontal status cards, profile rings, text/photo covers, video play indicators and followed channels with unread counts below. Video status cover-frame extraction is not implemented; video cards use their caption/background with a play indicator. Status upload limits remain 20 MiB.
- Channel: compact tappable avatar/name header, channel information sheet, follow control, local search of the most recent 100 loaded announcements, rounded announcement bubbles, reactions beneath them and an inline admin composer. Search has a clear button; it is not a full-history server search. Channel media/voice posts shown in the reference are not added by this layout update.
- Communities still open their existing working group conversations; rows show member information, blue verification badges and unread message counts.

## Verification and staff access

Use Pulse Control with the authorized staff account @iszy. Accounts and Channels have existing verify/unverify controls. Communities has its own staff verification screen from 0.5.1. Badges are backed by staff-only database checks; nobody can self-verify through profile metadata. These controls are preserved in the cumulative ZIP. No real account/channel/community was verified by the automated tests.

## Backend and validation

Installation scripts 020, 021 and 022 are already applied to the connected Pulse project. pulse-live Edge version 2 was deployed in 0.5.1. Do not reset the database or rerun scripts 001–022 on this project.

New script: supabase/schema/022_status_replies_profile_photos.sql. It adds a nullable status reference to messages, a guarded reply RPC, a 15 MiB avatar bucket limit and replaces the old eight-photo bound. It changes no existing account/chat/message data. Readback after deployment confirmed the endpoint and avatar limit; the project still had 6 profiles and 21 messages.

Local checks passed: all 22 ordered schema scripts, all 10 SQL security suites including the new status reply/12-photo suite, mocked LIVE Edge permission tests, and Python helpers (10 passed, one skipped because CMake is unavailable). New SQL tests cover duplicate submissions, expired/deleted status handling, outsider/block denial, message-request consent, avatar limit and publishing twelve photos. Fixtures roll back. A connected-backend fixture run did not return a usable response because the connector reported an expired request state; its result is not counted as passed. Deployment readback is not a native UI test.

Dart formatting/parsing passed for changed files. Full Flutter analysis, widget tests, APK/Windows builds and screenshots/device interaction checks must run in GitHub/on devices. No APK or EXE was generated here. The earlier red-screen fix corrects an unsafe dialog controller lifetime; reproducing the exact original crash on a device remains necessary.

## Upload and build

1. Extract PULSE_0.5.2_Combined_Update.zip. Upload its extracted files/folders into the root of the EXISTING repository and commit. Keep the paths intact. Do not upload the ZIP as source and do not delete your repository.
2. The cumulative patch has fewer than 100 files. It preserves the existing main.yml and control.yml; no workflow edit is required for this change.
3. Run Actions → Pulse native beta builds → Run workflow for Android and Windows. Run Pulse Control staff builds separately for the updated staff application.
4. Download the APK and Windows installer artifacts when their jobs pass. Keep the full Windows application folder if testing the portable executable.
5. Test between two accounts: reply to text/photo/video statuses, open the status link, let it expire, test blocking and pending requests. Upload a 3–15 MiB profile image and reject one over 15 MiB; confirm free GIF denial/Premium GIF behavior. Publish more than eight photos, browse profile grid, send channel announcements, and verify/unverify all three entity types with staff and non-staff accounts.

For a fresh independent backend install, run ordered schema scripts 001–022 once and deploy required Edge functions with your own server credentials. Never put service-role or LiveKit secrets in client configuration. Supabase project/bucket global limits and storage quotas remain independent of app limits (https://supabase.com/docs/guides/storage/uploads/file-limits).

LIVE Party source supports a host plus up to eight approved guests and the existing 100-follower channel policy. It still requires a reachable LiveKit server and real multi-device media testing. Paid gifts/coins, battles, payouts, AR tools and full TikTok LIVE parity are not implemented. Closed-app push/email dispatch, production signing, E2EE, automatic updates and paid billing remain unfinished. See 0.5.1 notes for details.
