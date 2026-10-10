# Pulse Messenger 0.3 — calls and voice notes

This is an incremental native beta. It does not implement every WhatsApp feature or claim production readiness. Pulse uses its own name, assets and interface.

## Install this source update

1. Extract the ZIP. Upload **the contents of `pulse-messenger/`** into the root of your existing GitHub repository, replacing matching files. Include `lib/voice.dart`, `lib/media.dart`, `lib/calls.dart`, `lib/avatar.dart`, `pubspec.yaml`, scripts, tests and `.github/workflows/main.yml`.
2. Run the Android and Windows workflow jobs. Download their artifacts only after the jobs pass. The ZIP is source code, not an APK or EXE.
3. Install on two test devices with two accounts. Use a staging backend for tests where possible. GitHub Actions resolves dependencies and includes `pubspec.lock` in the artifacts; commit the successful lockfile for reproducible subsequent builds.

The Windows CMake compatibility settings and Python short-path test fix remain included. Versions of Firebase Core, Firebase Messaging, File Picker and secure storage retain their compatible pins. `record 7.1.2` and `path_provider 2.1.6` are added for native microphone recording and temporary files. CI uses Flutter 3.47.7.

## New source functionality

- Voice/video calls from the chat header, including group chats of 2–8 total members.
- Incoming accept/decline banner, busy checks, call history, mute, camera on/off/switching, Android speaker routing and SDK reconnection.
- Server-authorized participant invitations and short-lived LiveKit join tokens. Call signaling uses realtime events plus reconciliation polling.
- Voice recording with pause/resume, review, discard, send, a five-minute limit and waveform samples from actual microphone amplitude.
- In-chat photo display, video/audio playback, audio seeking and playback speed. Media loads on demand to reduce memory use.
- Voice notes use the same persisted outbox as messages after successful upload. Uploading requires a connection. Recordings discarded before sending are deleted from temporary storage.

## LiveKit setup — required for calls and channel live

Your existing Pulse Supabase project already has schemas 007/008 and the `pulse-call` Edge Function deployed, including the tested call-start correction. `pulse-live` was deployed previously. Do not run those schema files again on this project.

Create or use a LiveKit Cloud project, or deploy a self-hosted LiveKit server with reachable TURN support. In **Supabase → Edge Functions → Secrets**, set:

| Secret | Value |
|---|---|
| `LIVEKIT_URL` | The project's `wss://…` server URL |
| `LIVEKIT_API_KEY` | Server API key |
| `LIVEKIT_API_SECRET` | Server signing secret |

Keep keys/secrets out of `config.example.json`, Flutter source and GitHub uploads. Native clients receive scoped tokens, not signing credentials. Provider/network fees may apply. Never paste secrets into chat.

Calls show a setup error until these credentials are configured. On both devices, open Pulse, allow microphone/camera access and use the header call buttons. Test on separate networks, with Wi-Fi/mobile changes, permission denial, decline, mute, camera switch, busy users, group member removal and force-close.

**Current call limits:** Pulse must be open to receive an incoming call. Android backgrounding ends the call because a foreground-call service is not shipped. No CallKit, closed-app ringing, screen sharing, public call links, device handoff or call recording. Native media connection, audio routing and reconnection have not been verified on devices here.

Call leases reconcile on RPC access; no scheduled cleanup worker is deployed. Server leave attempts to remove a participant/delete the room. Removing or blocking a member stops signaling authorization but does not guarantee immediate eviction of an already connected, modified client. Production requires LiveKit webhooks and a trusted moderation/cleanup worker, plus reconnection/token revocation tests. A token expiry limits admission; it does not terminate an existing session. Calls use transport encryption; **E2EE is not implemented**.

## Other platforms and services

- Android APK and native Windows installer builds are configured; this update's actual builds remain to be run.
- Local message/call alerts work only with a running process and permitted OS notifications; device behavior is unverified.
- Android closed-app FCM code and database queue exist, but the dispatcher is not deployed. Automatic approval review previously rejected sending device tokens/message IDs to Google FCM without explicit authorization. Firebase configuration and trusted scheduling are also required. Closed-app calls are not implemented by that message dispatcher.
- Phone login requires an SMS provider. Email delivery depends on your configured SMTP.
- iOS, automatic updates, release signing and store distribution remain future work.
- Existing channel admin posting, pictures and livestream fan chat, photo/video/text statuses and message deletion are retained. Premium remains removed; gifts and coins are deferred.

## Media and security limits

Chat uploads are capped at 10 MB; status uploads at 20 MB. Audio/video compatibility depends on native codecs. Upload MIME metadata is checked against storage metadata, not scanned or independently decoded by the server. Thumbnailing, transcoding, malware scanning, resumable uploads and orphan cleanup are not implemented. Forwarding currently forwards text; full media forwarding remains pending.

Deletion and status expiry prevent normal retrieval through the app, but cannot erase downloaded media. Existing chat-member storage access policies and temporary signed URLs do not provide instant revocation. Recordings use OS temporary storage before upload; encrypted local recordings and automatic abandoned-file cleanup remain future work.

Messages remain plaintext in the backend. TLS, RLS and the secure outbox do not equal E2EE. Leaked-password protection remains disabled in the provider configuration. Do not use the beta for sensitive conversations.

See [FEATURE_STATUS.md](FEATURE_STATUS.md) for the full feature coverage and remaining release work, and [VERIFICATION.md](VERIFICATION.md) for exact test evidence.


## Fresh backend installation

For a separate Supabase project, review and run the numbered SQL files in `supabase/schema/` in order 001–008 through the SQL editor, once each. They are ordered schema installation scripts, not entries in Supabase CLI migration history. Deploy the included `pulse-login`, `pulse-live` and `pulse-call` functions, preserving their explicit bearer-token validation where applicable. The call function uses runtime Auth validation rather than relying on gateway legacy JWT verification. Keep `pulse_private` unexposed. Configure your Auth, SMTP/SMS and server secrets and update only public client configuration. Do not deploy `pulse-push` without the required authorization/provider setup. Run the supplied transactional security tests and advisors before connecting real users. For production migration history, generate CLI migrations from the reviewed database diff and validate against a clean staging database.
