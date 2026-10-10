# Pulse Messenger 0.2 — native beta

Native Flutter clients for Android and Windows, connected to one Supabase backend. This is a staged beta, not a complete production-ready platform. No WebView wrapper or WhatsApp assets are used.

**Start here:** [Update, installation and service setup](docs/UPDATE_0.2.md).

## This update

Dedicated channel feeds, admin-only announcements, photos/descriptions, following and reactions. LiveKit broadcast/viewer integration and follower live chat. Teal/coral/violet accents and gradient bubbles. Android/Windows local notifications plus optional Android Firebase background-push code. Premium is removed from the screens; records are preserved. Gifts and coins remain deferred.

## Build

Upload the contents of `pulse-messenger` to your repository. Run `.github/workflows/main.yml` in GitHub Actions. The jobs run dependency resolution, analyzer, tests and native compilation. Android outputs a debug-signed APK; Windows outputs a native installer and complete application bundle. This update has not yet passed those native build/device gates.

For a configured local build machine:

```sh
python scripts/bootstrap.py
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug --dart-define-from-file=config.example.json
flutter build windows --release --dart-define-from-file=config.example.json
```

`config.example.json` contains only public Supabase project values. Add Firebase public Android app values only if enabling background push; never add service-account, LiveKit signing, SMTP or service_role secrets there.

## Required external setup

- Supabase project: migrations 001–005, Auth and Storage. Existing Pulse project has these deployed.
- Email OTP: configured SMTP and code-based signup/recovery email templates. Phone OTP: SMS provider required.
- Livestreams: LiveKit project/server credentials stored as server secrets, plus two-device media testing. `pulse-live` is deployed but credentials are not configured.
- Android background push: Firebase public app options, server FCM service account, trusted scheduler and explicit authorization to deploy `pulse-push`. That deployment was blocked by automatic approval review and remains pending. Local alerts do not require Firebase.
- Windows closed-app push, private/group calls, E2EE, full communities, media status/stickers, automated updates, purchases and production signing are not implemented.

## Validation and security

Backend transactional tests passed for existing messaging authorization, new channel/live permissions and push token/queue privacy. Python bootstrap checks and standalone Dart validation passed. Native builds and external media/push delivery must be tested in GitHub Actions and on devices. See [Feature status](docs/FEATURE_STATUS.md) and [update notes](docs/UPDATE_0.2.md) for exact limits.

All client-side mutations use authorized RPCs. Private schemas are unexposed. Tokens and media access are scoped. No end-to-end encryption claim is made. Review third-party/native SDK licenses in [THIRD_PARTY.md](THIRD_PARTY.md) before distribution.
