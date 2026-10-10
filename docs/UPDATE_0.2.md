# Pulse 0.2 — channels, color and notifications

This is a native Flutter beta, not a production-complete messenger.

## Install this update

1. Extract the ZIP. Upload the contents of `pulse-messenger` into the GitHub repository, replacing matching files.
2. There must be only one Pulse workflow: `.github/workflows/main.yml`. Remove the old `native-builds.yml` if your repository also contains it, to avoid duplicate jobs.
3. Run **Pulse native beta builds** under GitHub Actions.
4. Download `Pulse-Android-Beta` and `Pulse-Windows-Beta`. Install `app-debug.apk` and `PulseMessenger-0.2.0-Windows-Setup.exe`.
5. Keep the same Android package/signing identity when installing over the previous APK. If GitHub's debug signing key differs, Android may require uninstalling the previous beta. Pending offline messages and local sessions will be lost on uninstall; sync first.
6. Log in. In Settings enable notifications and use Test notification. Windows alerts are local to a running Pulse process; closing the window ends delivery.

The archive you supplied was the original 0.1 source, not your corrected GitHub checkout. This update restores the Row import fix and Windows bootstrap fix. It upgrades file_picker to 13.1.0 and updates both attachment/profile pickers to its new API, avoiding the prior win32 conflict. New SDKs add dependencies; GitHub Actions must resolve, analyze and compile them before device testing.

## What changed

- Dedicated channel discovery and announcement feed, follow controls, channel photos, descriptions and verification display.
- Channel owner can add administrators by username. Backend permissions restrict announcement posting and channel editing to administrators. Fans react instead of posting.
- Five reaction choices, one reaction per person per post; tap your selected reaction to remove it.
- Native channel broadcasting/viewing via LiveKit, host microphone toggle, connected participant count, reconnect state, follower chat during live, host comment moderation, explicit end broadcast.
- Database live chat deduplication, rate limits and expiry checks. Live sessions have a 90-second host lease, refreshed while the host is connected. Clients stop viewing when the lease expires. Explicit End deletes the LiveKit room before marking the session closed.
- Teal, coral and violet theme accents, gradient channel header and outgoing bubbles; light and dark themes.
- Native Android/Windows OS notifications for incoming message INSERT events while realtime remains connected. The alert hides message content. Local alerts alone cannot wake a suspended/killed Android app.
- Optional Android FCM client registration and server queue/dispatcher implementation for background push. NOT active until configured and authorized, as described below.
- Premium and promo UI removed from user settings and the admin dashboard. Existing entitlement/redemption records and their legacy backend RPCs are retained, dormant, for a future update. No purchases, coins, gifts or premium benefits are enabled.

## Backend deployment status

For the existing Pulse project, schemas `004_channels_live.sql` and `005_push.sql` have been applied. Do not apply them twice. The authenticated `pulse-live` Edge Function is deployed; it returns a configuration error until you set LiveKit secrets. The `pulse-push` dispatcher deployment was blocked by automatic approval review and has NOT been deployed.

For another project, apply schemas 001 through 005 in order. Keep `pulse_private` outside exposed Data API schemas. Device tokens and push queue rows cannot be read by clients. All mutating functions validate the caller and restrict privileges; only server service_role can claim/deliver push jobs.

## Livestream setup required

Create a LiveKit Cloud project, or deploy a LiveKit server with TLS and working TURN connectivity. Set the following **Supabase Edge Function secrets**, never client defines:

- `LIVEKIT_URL`: `wss://...`
- `LIVEKIT_API_KEY`: server API key
- `LIVEKIT_API_SECRET`: server signing secret

No live credentials are included in the ZIP or installed in the deployed function. Review your provider's usage/pricing before enabling public streams.

Fans' LiveKit tokens have `canPublish=false` and `canPublishData=false`; they cannot broadcast microphone/video. Fan chat passes through the database RPC, requires following the channel, and closes when the session expires/ends. Hosts receive publishing permission only after Auth verifies their identity and SQL verifies their channel-admin role. Tokens expire in five minutes; expiry limits reuse, but it does not disconnect an already connected media session. Explicit end deletes the room.

Hardening before a public launch: schedule orphan room cleanup after lease expiry, server-side stream monitoring and revocation on role changes, per-channel bans, scalable follower counts/discovery pagination, webhook verification, and load/device tests. A channel admin currently has no removal UI; the owner can revoke it with `pulse_channel_set_admin(p_channel,p_user,p_enabled=false)`.

## Android background push setup required

Create a Firebase project and register Android package `com.pulsemessenger.pulse_messenger`. Add its **public** app values to a private build config copied from `config.example.json`:

- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`

Use the exact values from your Firebase Android app. This implementation initializes Firebase with explicit runtime options. Firebase options identify the project; they are not service account secrets. Ensure the Android application ID matches your Firebase registration.

Keep these server secrets solely in Supabase's Edge Function secrets:

- `FCM_SERVICE_ACCOUNT_JSON`: Firebase service account JSON with FCM sending permission.
- `PUSH_DISPATCH_SECRET`: a random server-only dispatcher secret, at least 32 random bytes.

The dispatcher sends only a generic “You have a new message” alert, a message identifier for deduplication, and the device's registration token to Google's FCM service. It sends no message text or attachment. Deployment is currently blocked pending explicit user authorization for this external transfer. Do not deploy or schedule it until that approval is given.

After authorization and deployment, a trusted scheduler must POST to `/functions/v1/pulse-push` with `Authorization: Bearer <PUSH_DISPATCH_SECRET>` every minute. Store that scheduler credential in Vault or the scheduler's secret store, never client code. Each invocation claims at most 20 queued recipient jobs with a lease; retries stop after five attempts. Scale the batch/worker concurrency for production traffic and retain/delete completed queue rows under an appropriate retention policy. Invalid device tokens are removed. Delivery rechecks membership, deletion and blocking before sending. Registration and this-device/all-device unregister RPCs are implemented. Turning notifications off unregisters this device.

FCM requires Google Play services and user notification permission. OS battery restrictions and force-stop can prevent delivery. Windows closed-app push/WNS is not implemented. Turning on local alerts does not imply background push has been deployed or tested.

## Calls

Private/group calling is still unimplemented. Livestreaming shares a WebRTC media transport but does not implement ringing, call acceptance/rejection, private call rooms, call history or background incoming-call delivery. No E2EE claim is made for private messages or livestreams.

## Validation

Passed on the deployed backend (fixtures rolled back):

- `test/channels_security.sql`: fan post/broadcast denial; follower-only live chat; deduplication/rate limits; admin moderation; closure after end.
- `test/push_security.sql`: token privacy, device ownership, recipient queue, server-only claiming, global unregister and block checks.
- Existing `test/backend_security.sql`: auth-isolated chats, message ownership, receipts/reactions, blocking and legacy redeem rules.
- `test/test_bootstrap.py`: Windows batch executable resolution, repeat-safe native permissions, Android icon and Gradle desugaring.
- Dart syntax formatting and standalone username/password tests.

Not run here: Flutter dependency resolution/analyzer, Android/Windows native compilation, hardware camera/microphone/toast tests, end-to-end LiveKit media or FCM delivery. The earlier local Flutter invocation was rejected by automatic approval review due to an unexpected metadata-endpoint request; no local retry or workaround was attempted. The included GitHub workflow is the build/analysis gate, followed by two-device testing. This update is not a verified production release.
