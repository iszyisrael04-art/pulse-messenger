# Pulse 0.5.7

- Profile cover photos and their upload control are removed. Existing cover files are preserved. Video thumbnail/cover images remain part of posts and statuses.
- Premium profiles accept GIFs or a video trimmed to at most five seconds. The picker exports a muted MP4 and a JPEG poster. Android uses precise Media3 clipping and 512px-height encoding; Windows uses the existing precise native editor. Saved output is limited to 15 MB. Profile playback loops silently and pauses off screen, in background, on covered routes, and under reduced motion. Compact chat avatars use the poster to limit decoder/memory usage. Five-second duration is enforced by native export and player playback; Storage enforces size, ownership, MIME, and Premium entitlement, not independent video decoding/duration validation.
- Profiles receive top-level total likes for published posts/reels. Follow/like mutations refresh affected visible profiles. Pull-to-refresh also refreshes profile counts. Pending private follow requests are excluded from accepted following/follower totals.
- Likes, comments, follows/requests, mentions/community tags and followed-creator publications can show native OS activity alerts when Pulse is running and notifications are enabled. Existing category preferences still filter events server-side. Initial history, already-read items and duplicate events do not trigger alerts. Notification taps open Activity. Channel/community message alerts remain on the existing message/channel paths.
- This release does not add closed-app FCM activity delivery. Android Firebase configuration, deployed push dispatcher, and multi-device push testing remain separate requirements.
- LIVE diagnostics identify a server configuration failure, authentication failure, rate limit or control-service failure. A successful control API probe never claims camera/microphone transport has been verified. The observed live endpoint returned 503; the owner must configure a valid LIVEKIT_URL (wss://), LIVEKIT_API_KEY, and LIVEKIT_API_SECRET in server secrets. Never add these credentials to Flutter code or GitHub.

## Backend

Apply `supabase/migrations/20261023010914_profile_motion_counts.sql` after the existing schema files. This migration has already been applied to the connected Pulse project. It preserves the private avatar bucket and the existing 15 MB cap. Deploy the updated `pulse-live` function; its own authenticated-user checks remain enabled.

## Validation

Pure Dart tests cover clip bounds, poster naming, notification replay/deduplication and LIVE result handling. The edge-function fixture checks authorization, party permissions, configuration failure and secret-free health responses. Python helper tests cover native bootstrap. Database read-only checks verified like/following totals and avatar ownership/MIME/Premium rules. Flutter widget tests, platform analysis and real Android/Windows export/playback require GitHub Actions and devices; no claim of live-media or closed-app push verification is made.
