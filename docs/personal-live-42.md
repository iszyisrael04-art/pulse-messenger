# Personal LIVE — 0.1.0+42

## Find the controls

- Start or resume your own broadcast from **Create → LIVE**. Profile pages show a watchable LIVE badge only while a broadcast is active.
- Administrators: **Administrator dashboard → Channels & user LIVE minimum → LIVE icon**. Set the minimum number of accepted profile followers; **0** removes the follower requirement. Existing channel moderation remains available there, but channels cannot broadcast.
- In a live, tap **…** for seats, pending requests, microphone/camera, pause/resume, comments, gifts, wallet/battles and gift sounds. Requests have a badge on the menu.
- Tap **X** or use Back to leave immediately. Camera, microphone, room and server cleanup run with bounded timeouts. Only the host can end a broadcast for everyone.
- Viewers can tap the host or a chat message to open its author's profile, and use **Follow** for a host they do not already follow. Comments keep the latest messages visible automatically.

## Server changes

`supabase/schema/041_personal_live_only.sql` enables personal LIVE, enforces creator privacy and follower minimums, and rejects channel LIVE. It ends legacy channel broadcasts without deleting history. The deployed `pulse-live` Edge Function enforces personal-only starts and host-only ending; guests receive publishing permission only after approval. Ending is stored before best-effort room deletion.

## Media changes

LIVE requests a 720p / 30 fps camera stream and keeps the screen awake while foregrounded. This addresses inactivity dimming; it does not artificially brighten the camera or promise a particular network quality. A real phone test beyond five minutes is still required to distinguish display dimming from camera exposure, power saving or thermal behavior.

The lion gift uses an original, bundled 3D jungle run and roar cinematic with a credited public-domain roar. Other gift previews use smoother depth meshes, light trails and gift-specific motion. The lion is the first full jungle cinematic; the other gifts remain procedural mesh effects.

## Validation

Before the cinematic addition, GitHub Actions passed Android and Windows analysis, Flutter tests and native builds, plus the unsigned iOS compile and backend security suites. Run the same checks for the final commit. Physical acceptance checks: host + two viewers, seat request badge/approval, current viewer count, follow, new comments, five-minute camera stability, gift sound/mute, viewer Back/X, and host end notice. No device acceptance result is claimed by the compile checks.
