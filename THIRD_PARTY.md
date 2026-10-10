# Third-party dependencies

Pulse uses original branding and code; no WhatsApp assets are included. Before public distribution, generate and review the complete resolved dependency/license list and include the Flutter/Supabase/plugin licenses in the app's license page. Top-level packages are pinned in pubspec.yaml, but a resolved transitive lockfile must be generated and committed on the build machine.

Publisher references:

- Flutter: https://github.com/flutter/flutter
- Supabase Flutter 2.18.0: https://pub.dev/packages/supabase_flutter/versions/2.18.0
- Flutter Secure Storage 11.2.0: https://pub.dev/packages/flutter_secure_storage/versions/11.2.0
- File Picker 13.1.0: https://pub.dev/packages/file_picker/versions/13.1.0
- UUID 4.5.3: https://pub.dev/packages/uuid/versions/4.5.3
- URL Launcher 6.3.2: https://pub.dev/packages/url_launcher/versions/6.3.2

Distribution terms for the original application are for the project owner to choose. No third-party trademark ownership is implied.

Pulse 0.2 adds LiveKit Flutter SDK (Apache-2.0), flutter_local_notifications (BSD-3-Clause), Firebase Core/Messaging Flutter SDKs (BSD-3-Clause), and their transitive native dependencies. Review each package/native SDK license before redistribution. No WhatsApp assets are used.

Pulse 0.3 adds record 7.1.2 and path_provider 2.1.6 for native recording/temporary files; MediaKit 1.2.6, media_kit_video 2.0.1 and media_kit_libs_video 1.0.7 provide playback. Review the resolved platform plugin and bundled codec/native binary licenses before distribution.
