# Pulse 0.5.12 — Squad sandbox checkout

Read [the test setup](docs/UPGRADE_0.5.12.md). A separate simulated checkout and server verification are available from Animated profile & Boost after installing a new build. Real purchases remain disabled.

# Pulse 0.5.11 — online and last-seen status

Read [the update notes](docs/UPGRADE_0.5.11.md). Chat, profile and creator avatars can show online status, with last seen and a privacy setting. Native builds and device verification remain pending.

## Previous releases

# Pulse 0.5.10 — media-first Studio and playback recovery

Read [the update notes](docs/UPGRADE_0.5.10.md). Create now uses a local editing workspace, a reorderable photo strip and video-download privacy. Home and Reels have cover-backed loading and bounded playback recovery. Native builds and device testing remain pending.

## Previous releases

# Pulse 0.5.9 — free core features and standalone creator purchases

Read [the update notes](docs/UPGRADE_0.5.9.md). Premium subscriptions, redemption and Premium badges are retired. Core features are free; animated profiles and account Boost have separate prices. Checkout is not connected yet. Native build and device verification remain pending.

## Previous releases

# Pulse 0.5.6 — profile, camera and inbox update

Read [upgrade/build instructions](docs/UPGRADE_0.5.6.md). Addresses the camera preview disposal error shown in the recording and updates the referenced layouts. No main.yml or SQL change. Full Flutter/native/device verification remains pending.

## Previous update

# Pulse 0.5.5 — camera, studio and For You interests

Read [upgrade/build instructions](docs/UPGRADE_0.5.5.md). Upload the extracted cumulative update into the existing repository. Keep main.yml unchanged; no SQL update is needed. Phone OTP is blocked by disabled Phone authentication and still needs a configured SMS provider. Native builds and device tests remain pending.

## Previous update

# Pulse 0.5.4 — revised chat layout, no forwarding

Read [upgrade/build instructions](docs/UPGRADE_0.5.4.md). Long-press/right-click offers Copy text and quick reactions. Message forwarding is removed; photos and videos retain large responsive cards. No SQL step is required for these changes. Keep main.yml unchanged. Native builds and device tests remain pending.

## Previous update

# Pulse 0.5.3 — channel media, status covers and watermarked downloads

Read [upgrade/build instructions](docs/UPGRADE_0.5.3.md). Script 023 is installed on the connected backend and pulse-live Edge version 3 is deployed. Upload the extracted cumulative patch to your existing repository. Keep main.yml unchanged. Native builds and device testing remain pending.

## Previous update

# Pulse 0.5.2 — status replies and refreshed social layouts

Read [upgrade and build instructions](docs/UPGRADE_0.5.2.md). Scripts 001–022 are installed on the connected backend. Upload this cumulative patch to the existing repository; main.yml does not need changing. Native builds and device tests remain pending.

## Previous update

# Pulse 0.5.1 — channel fixes, community badges and LIVE Party

Read [the current upgrade and verification notes](docs/UPGRADE_0.5.1.md). Database scripts 001–021 are installed on the connected Pulse backend; pulse-live Edge version 2 is deployed. Do not reset the database or rerun all scripts. Native builds/device tests and real LiveKit media validation remain pending.

## Earlier release history

# Current update: 0.4.9

See [Activity and support identity update](docs/UPGRADE_0.4.9.md).

# Current update: 0.4.8

See [Help & support update](docs/UPGRADE_0.4.8.md).

# Current update: 0.4.7

See [docs/UPGRADE_0.4.7.md](docs/UPGRADE_0.4.7.md) for the registration agreement, Premium profile identity changes, test evidence and remaining build/device checks. Earlier sections below describe their respective releases.

# PULSE 0.4.6

Chat polish, unread notifications, Pulse branding and private chat tools: [docs/UPGRADE_0.4.6.md](docs/UPGRADE_0.4.6.md). [Current release readiness](docs/RELEASE_READINESS.md) records the user-reported two-device chat pass and the remaining gates.

# PULSE 0.4.2

Themes, wallpapers and loading/splash styles: [docs/UPGRADE_0.4.2.md](docs/UPGRADE_0.4.2.md). Continue using the existing repository; no backend changes for this patch.

# PULSE 0.4.1

See [docs/UPGRADE_0.4.1.md](docs/UPGRADE_0.4.1.md) for previews, hashtags, free/Premium upload eligibility and the hosting limits. The sections below describe the 0.4 foundation.

# PULSE 0.4 — native social platform beta

This continues the existing Pulse Messenger Flutter project and shared Supabase backend. Android and Windows remain native applications. Accounts, chats, groups, statuses, channels, calls, authentication and Premium/promo records are preserved.

**Start here:** [Upgrade and build instructions](docs/UPGRADE_0.4.md).

This first social stage implements Home discovery/following feeds; text/photo/video posts; multiple photos; likes/comments/saves/reposts; sharing into existing chats; separate vertical Reels; real uploads; private follow approval; server drafts; cover/profile views and basic creator totals. SQL permission/functionality tests passed. Native Flutter compilation and device/media behavior are **not verified here**.

Navigation: Home, Reels, Create, Chats, Communities, Profile. Chats keeps Calls, Updates and Channels; Settings remains accessible. Communities currently retains group chats; full social communities are a later stage. Premium badges reflect actual backend entitlements and one-time 30DAYSPULSE redemption remains available. Paid $3/month billing is planned, not enabled.

No new provider credentials are required for Home/Reels. Your existing backend has the additive social schema deployed. Do not rerun existing schema scripts on that project. Calls/channel live still require LiveKit credentials/TURN; phone OTP requires SMS configuration. Background incoming calls, closed-app push delivery, E2EE, production signing and automatic updates remain incomplete.

## Build

Upload the **contents of `pulse-messenger/`** to the existing repository root and run `.github/workflows/main.yml`. Android produces a debug APK; Windows produces the native installer and complete bundle. CI runs dependency resolution, analysis and Flutter tests, including new feed-race tests. Commit the successful `pubspec.lock` from CI. Preserve existing signing/config files and never upload server secrets.

On a trusted configured machine:

```sh
python scripts/bootstrap.py
flutter pub get
dart format lib test
flutter analyze --no-fatal-infos --no-fatal-warnings
python test/test_bootstrap.py
flutter test
flutter build apk --debug --dart-define-from-file=config.example.json
```

For Windows, retain the workflow CMake compatibility step before native building and the Inno installer step. See [UPGRADE_0.4.md](docs/UPGRADE_0.4.md) for exact artifacts, signing and update limits.

## Evidence and boundaries

[Feature status](docs/FEATURE_STATUS.md), [verification](docs/VERIFICATION.md) and [device acceptance checks](docs/SOCIAL_DEVICE_CHECKS.md) distinguish deployed/tested backend behavior from native source awaiting CI and future development. No APK/EXE is supplied in this ZIP. This beta is not a finished worldwide production service. Messages remain plaintext in the backend; no E2EE claim is made.

Previous 0.2/0.3 update notes are retained as historical context. The 0.4 guide is authoritative for the current release. Review third-party/native codec licenses before distribution.
