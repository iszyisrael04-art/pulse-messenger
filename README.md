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
