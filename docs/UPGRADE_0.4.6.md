# Pulse 0.4.6 — friend chats and Pulse chat studio

Continues the existing native Flutter project and Supabase backend. Account, conversation, channel, status and redemption history remain intact. No new package/provider is required. LiveKit setup and closed-app push deployment are unchanged.

## Requested chat changes

- In-app message popups and local notification counts are based on the backend unread-preview RPC. Own, read, deleted, hidden-for-me, blocked and inaccessible messages are excluded. An already visible chat at the latest messages suppresses popups; foreground, laid-out messages are marked read after a frame. Scrolling to older messages leaves new content unread. Read acknowledgement clears local notification and in-app counts. Other-device changes reconcile through realtime/polling; a notification-state lookup is not an atomic guarantee against a concurrent remote read.
- Popups respect the notification switch. These remain **in-app overlays/local alerts**, not Android OS floating conversation bubbles. Firebase is not configured in the example build and no push dispatcher is deployed. The server push eligibility helper now also excludes read/hidden messages if dispatch is configured later.
- Outgoing footer uses a clock for queued, error outline for failed, one check for sent, grey double checks for delivered where a backend receipt exists, and colored double checks for read. In groups, colored checks currently mean at least one other recipient read; the tooltip says so. Incoming messages have an own-read indicator. No fake delivered/read status is inferred from merely sending.
- Reactions are grouped into small count chips **below** the colored message bubble. Incoming messages keep the sender avatar; outgoing messages have no own avatar. Ordinary bubbles show no sender name. A reply quote shows the referenced author's name and preview when available in the currently loaded messages.
- Incoming avatars, list avatars and direct-chat header names open profiles. Names use one-line ellipsis. Calls and refresh move into the header dropdown to give names more width. The direct-chat subtitle identifies a friend chat or pending request; it does not invent online status.
- Chats offers All, Friends, Catch-up (unread) and Requests filters. Friends means accepted direct conversations plus pre-request legacy direct conversations, not a new mutual-follow/friend database model. Empty Catch-up shows an all-caught-up state.
- Username lookup shows an account-found check and On Pulse label. The check is **not an identity verification badge**. Group creation now selects confirmed usernames with removable chips; existing group member management reuses the same lookup.

## Pulse branding

The electrical/heartbeat mark is replaced by an original P monogram with a violet accent. The runtime splash uses the matching PNG favicon with a gentle breathing/glow animation and honors reduced-motion settings. Android launcher PNGs, Windows ICO and native Android launch glyph are bundled and applied by bootstrap. Android's first OS launch frame is static; the animated splash runs after Flutter starts. The Home logo and desktop navigation use the new P mark; the empty chat illustration uses a community/hub icon.

Include the entire `assets/branding` folder, including Android density PNGs, and the updated pubspec and bootstrap. No image-rendering dependency is added to CI; icons are already generated. Android/Windows native rendering still needs device review.

## New chat tools

Open the notebook icon in a chat header to access **Pulse chat studio**:

- **Pocket:** free, account-private per-conversation scratchpad (up to 4,000 characters). It saves to the backend and is not sent to participants. Access is restricted to the note owner with current chat membership. Unsaved changes prompt before leaving. Notes are plaintext under access controls, not E2EE.
- **Quick replies:** Premium accounts can save/edit up to 20 titled templates (2,000 characters each). Selecting one inserts a composer draft; it never sends automatically. Ownership and active Premium are enforced for saving/using templates on the backend. Owners can remove retained templates after expiry. Existing saved text is still their own data, not DRM-protected content.
- **Bubble styles:** Classic plus Premium Aurora, Rose and Ocean outgoing-bubble styles per conversation. Preference writes are owner-scoped and Premium-gated; expired users receive Classic from the server. It is a personal appearance preference and does not change the recipient's screen. Free themes and wallpapers are preserved.

Pocket and Catch-up are Pulse product additions; no claim is made that no other app has comparable functionality. The existing account-data export does not include the new Pocket/templates/styles tables yet and is still explicitly a limited export, not a complete legal-access response or restorable backup.

## Premium redemption

Both profile and upgrade-page entry points now use one redemption flow. Response parsing accepts normal JSON objects and serialized JSON, validates the expiry, applies the confirmed entitlement locally and reports a retry as already redeemed with Premium still active. Known server/schema/auth/expired-code errors are translated into readable messages; raw database codes are not shown on the redeem page. A malformed/unconfirmed response remains an honest failure message rather than claiming a code succeeded.

`30DAYSPULSE` stays one use per eligible verified account and grants 30 days. Existing code definitions/history are not reset. Database tests confirm one-time and retry behavior. The user's exact native redemption error was not supplied or reproduced, so no perfect-device-fix claim is made. Payments remain unconnected; planned $3/month billing is not charged.

## Backend installation

Additive `supabase/schema/013_chat_tools.sql` has **already been applied** to the connected Pulse project, including its notification refinements. Do not reset accounts, reinstall 001–012 or rerun 013 on that project. On another staging backend, install the prerequisite scripts in order first. These files are installation scripts, not a completed Supabase CLI migration-history/replay workflow.

New data is in an unexposed private schema with RLS, no raw client table grants and explicit authenticated invoker wrappers. Internal definers use fixed empty search paths, auth/membership/ownership checks, per-user write throttling and Premium checks. Unread preview is authenticated and limited to currently accessible unread messages. Push eligibility remains service-role-only. No server secrets are added to the client.

## Verification

**Passed against the connected backend with disposable fixtures and rollback:**

- Existing request/privacy/Premium retry suite: sender/recipient/outsider authorization, pending requests, acceptance, private audience, read counts, Premium themes and single redemption history. This is a new successful run; the historical usage-limit block no longer represents its current result.
- New chat-tool suite: own-note persistence, peer/outsider isolation, no raw authenticated note SELECT grant, free/expired Premium restrictions, paid quick reply/style behavior, cross-owner template overwrite/use rejection, and style fallback on expiry.
- Unread preview/count rules: own/outsider, read, hidden-for-me and blocked messages are excluded. All fixtures rolled back; real users' codes/accounts were not changed for tests.

**Passed locally:** all 59 Dart files parse/format; standalone analysis of pure chat/Premium models and existing export/upload/appearance/visibility code; six standalone suites including receipt-state/notification policy, reaction grouping, redemption parsing/error messages, export cancellation, upload progress/integrity, appearance and visibility; ten Python tests completed with one CMake-install test skipped because CMake is not installed in this refreshed environment. Bootstrap icon copying and prior Windows fixes are covered by source/Python checks. Workflow YAML parses, both jobs retain analysis and add the chat-state suite. The CMake cycle, install-prefix and Python console-Unicode fixes are preserved.

**Not run here:** full Flutter dependency resolution/semantic analysis, Flutter widget tests (including new reduced-motion/favicon asset test), native builds, on-device layout, animated splash/icon appearance, notification timing, remote-read reconciliation, actual Premium redemption UI and chat-studio synchronization on devices. Existing local Flutter execution restrictions were not bypassed. Run both GitHub jobs and install the resulting builds before sharing them as an updated beta.

The security advisor reports no new public RLS/privileged-function warnings. Twelve private tables intentionally have deny-all RLS with no client policies. The existing [leaked-password-protection advisory](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains; that Auth/provider setting was not changed by this UI patch.

## Upload/build

Replace matching files in the **existing repository**, including `.github/workflows/main.yml`, `lib`, `test`, `scripts`, `pubspec.yaml`, `native` and the new `assets/branding` directory. Preserve your private configuration/signing files and do not delete the repository. Start a **new workflow run at the new commit**. The ZIP is source, not a prebuilt APK/EXE. Android remains a debug beta build; Windows installer/signing limitations remain in RELEASE_READINESS.md. Keep build logs if a native job fails; no error-free build is promised without CI evidence.

## Two-device checks for this update

1. Open a direct chat, confirm no duplicate name in ordinary bubbles, reply to a message, react twice from different accounts and check count chips appear below it.
2. Check one/double/read marks against real actions; verify the user's own receipt never marks their outgoing message read by the friend. Test groups separately.
3. Keep a chat visible at the bottom and send from the other device: no new popup; scroll up or switch tabs and send: unread popup/count appears. Read on the other device and verify counts reconcile. Disable notifications and check no popup. Hide/block/read a message and verify no stale notification is generated.
4. Test profile taps, long names at narrow desktop/mobile widths, account-found check and group member selection/removal.
5. Save a Pocket note as A; B must see an independent empty note for the same chat. Verify A's note survives reopening and unsaved back navigation asks before discarding.
6. Verify free accounts cannot save/use paid templates or styles. Redeem an unused eligible code; retry after success; verify one history record and no second extension. Test expiry and Classic fallback. Insert a template and verify it remains a draft until Send.
7. Confirm app icon and animated splash on Android and Windows, including reduced motion. Retest the Windows installer and older build upgrade with the correct signing identity.
