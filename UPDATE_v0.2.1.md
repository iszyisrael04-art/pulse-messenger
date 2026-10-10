# Pulse v0.2.1 update

## Install this source update

Extract the ZIP. Open its `pulse-messenger` folder. Replace the repository files with their matching paths, keeping `.github/workflows/main.yml` in that exact folder. Commit the update and start a NEW workflow run on main. Download/install the resulting Android APK and Windows installer.

Changed application files: `lib/home.dart`, `lib/channels.dart`, new `lib/statuses.dart`, `pubspec.yaml`. The update also includes the Windows fixes in `.github/workflows/main.yml` and `test/test_bootstrap.py`. Keep all existing lib files, including `lib/avatar.dart`.

The backend SQL in `supabase/schema/006_status_media.sql` has already been applied to the connected Pulse project. Do not run it again on that project. It is included for new installations.

## Added

- Channel admins have a visible camera button at the top of a channel to choose its picture. JPG/PNG/WebP, maximum 2 MB. Non-admins cannot change it.
- Each message has a visible trash button. A confirmation offers Delete for me and, for your own sent messages, Delete for everyone. Server authorization remains enforced. Queued messages can be discarded.
- Updates + menu offers Text, Photo, and Video statuses. Media limit: 20 MB. Photo formats JPG/PNG/WebP; video formats MP4/MOV/WebM. Tap a status to open the full-screen viewer. Video controls support playback/pause/seeking. Only one viewer/player is created at a time, and it is disposed when closed. Playback pauses when the app leaves the foreground.
- Delete your own status using its trash button. Others cannot delete it.
- Statuses expire after 24 hours. Visibility remains people sharing a chat, subject to blocking. RLS protects private media. Signed playback URLs expire within 60 seconds or the remaining status lifetime, whichever is shorter. Bytes already downloaded cannot be revoked. Expired/unreferenced files still require a server cleanup job to reclaim storage; no cleanup schedule was deployed.
- Live service failures now distinguish missing configuration, expired login, and server errors.

## LiveKit setup REQUIRED

Streaming is implemented against LiveKit but no server credentials have been configured by this update.

1. Create or use your LiveKit Cloud project (or your own deployed LiveKit server).
2. Obtain the server WebSocket URL beginning `wss://`, API key, and API secret from its project settings.
3. In the Pulse Supabase dashboard, open Edge Functions -> Secrets. Set:
   - LIVEKIT_URL
   - LIVEKIT_API_KEY
   - LIVEKIT_API_SECRET
4. Keep the API secret in Supabase only. Never put it in config.example.json, Flutter code, GitHub files, or a chat message.
5. Reopen Pulse. As a channel admin, choose Go live and allow camera/microphone permission. Test with a second signed-in account on another device. Viewers receive subscribe-only media tokens; fans can chat during active lives if following the channel.

External service provisioning, credentials and end-to-end streaming tests are still needed. This update does not claim the LiveKit connection is fixed or verified on a real server. If configured but failing, send the exact in-app error, excluding credentials.

## Validation and limits

Passed: server tests for media type, retry safety, ownership, contact access, blocking, expiration and status deletion; Python native-bootstrap configuration test. Security advisor found no new issue from this update. The existing disabled breached-password check remains.

Native Flutter dependency resolution, compilation and real-device video playback must be validated by GitHub Actions and device testing; they were not run locally. Media Kit dependencies are pinned to published versions. Video codecs vary; MP4/H.264 is the preferred portable upload. Large/unsupported videos should be compressed or re-encoded before posting; no transcoding service exists yet.

Pulse is a staged beta, not a completed WhatsApp-equivalent or production-ready secure messenger. Private/group calls, voice recording/waveforms, full community permissions, sticker/GIF systems, status privacy choices/viewer lists/replies, media editing, scalable pagination, verified end-to-end encryption, closed-app push provisioning and automatic updates require additional development or setup. Premium/gifts/coins remain disabled/deferred. Do not advertise E2EE.
