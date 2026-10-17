# Pulse 0.4.5 — account controls and release checks

Continues the existing native Android/Windows Flutter project. Windows remains **Pulse**, with `Pulse.exe`. LiveKit/calls/live work is deliberately deferred. No database schema change, account reset, payment activation or provider deployment is made in this patch. Backend scripts through 012 remain required; do not reinstall/reset the existing project.

## Dependency correction

The corrected archive pins `ffi: 2.2.0`, satisfying `flutter_secure_storage_windows ^4.2.2`. The earlier `ffi: 2.1.4` pin caused dependency resolution to fail on both platforms. Full Flutter dependency resolution/native builds must be rerun in CI; they were not executed here. No workflow change is required for this correction.

## Analyzer correction

Both supplied Android/Windows logs reached Flutter analysis and reported the same blocking error at `lib/social_media.dart:264`: a nullable Player field was passed to a non-null parameter during disposal. Cleanup now captures a local final player and checks it before calling the helper. The analyzer step stays enabled. Other supplied diagnostics were nonfatal warnings/style notices. Full CI/native builds must still be rerun; no successful build is claimed for this correction.

## Windows CMake dependency correction

The user reports that Android now builds successfully. The next Windows log reached CMake generation but failed on the cycle `Pulse -> pulse_editor -> Pulse`. The editor's POST_BUILD command referenced the app target directory, creating a reverse dependency under the generated project's CMake policy settings. Bootstrap now puts the editor DLL directly in `${CMAKE_BINARY_DIR}/runner/$<CONFIG>` using RUNTIME_OUTPUT_DIRECTORY, with the app depending on the editor in one direction only. It also repairs the earlier generated command on subsequent runs. The installation rule is retained.

Upload the corrected bootstrap and bootstrap test (or replace matching files from this archive), then start a new Windows workflow run. No main.yml change is needed. Re-running an old workflow revision does not pick up new source commits. CMake deprecation and media-kit developer warnings in the supplied log were not the cause of this cycle failure. Full Windows compilation remains a separate CI gate.

## Windows install failure: diagnosis pending

The next user log reached INSTALL.vcxproj but contains only the MSB3073 wrapper failure. It does not contain the underlying CMake file/copy/install error, so a root-cause fix cannot be claimed. A local same-directory install fixture passed; the DLL install rule was not changed based on speculation.

The workflow now runs `python scripts/build_windows.py`: it saves verbose Flutter output to `build-logs/windows-build.log`. On failure, if an install script exists, it also captures `cmake --install ... --config Release --verbose` in `windows-install.log`. The original build exit code remains a failure even if the diagnostic install succeeds. The workflow uploads these logs as **Pulse-Windows-Build-Logs**, including failed builds. It still packages the app only after a successful build.

Replace `.github/workflows/main.yml`, add `scripts/build_windows.py` and `test/test_windows_build.py`, and retain the previous bootstrap/CMake fixes. Start a new Windows workflow on the new commit. If it fails, provide windows-install.log and windows-build.log, especially the first CMake Error with a filename/copy failure. Review logs before public sharing; they contain runner paths and public build configuration. The project does not put server credentials in build config.

Eight Python tests pass, covering graph configuration, legacy runner repair, config checks and diagnostic logging/exit-code preservation. These are not a successful native Windows build. Android previously passed and its build command is unchanged.

## Confirmed Windows install-prefix correction

The full user log now identifies `file cannot create directory .../$<TARGET_FILE_DIR:Pulse>/..` in cmake_install.cmake. Flutter's install prefix is a generator expression; the editor's relative target-install destination left that prefix literal. This was an install-rule error, not evidence that elevated permissions were needed.

Bootstrap now installs only the runtime DLL with `install(FILES "$<TARGET_FILE:pulse_editor>" DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)`, matching Flutter's explicit bundle-destination pattern. It repairs the old rule in existing generated runners. The workflow's Windows compatibility step includes the same replacement, so updating that step fixes newly generated runners even when the old bootstrap is still present. There is no change to Android behavior or the one-way dependency graph.

Nine Python tests pass, including a new CMake configure/build/install fixture with Flutter's exact generator-expression prefix and paths containing spaces. It verifies the runtime library lands beside the app and no literal generator-expression directory is created. The fixture uses tiny native code; it is not a full Flutter or Windows MediaComposition build. Run a fresh Windows CI build to confirm the production bundle.

## Windows console Unicode correction

The next supplied failure is Python UnicodeEncodeError while printing a UTF-8 build log to a cp1252 console. The build helper now escapes characters unsupported by the console while keeping the original UTF-8 log file intact. Tests simulate a strict cp1252 console with √ and emoji and verify both successful and failed native exit codes are preserved. This logging correction does not establish whether the actual app build succeeded; rerun CI and inspect its result/artifacts. No main.yml change is required for this patch.

## New source functionality

- Settings → **Download your data** streams a JSON export of the signed-in user's public profile fields, currently accessible conversations/messages, own statuses/posts/Reels/comments and own message requests. It uses the ordinary authenticated client and existing RLS, explicit field lists and owner filters. No service-role key, login password or session tokens are added to the export. Each query fetches at most 250 records with a keyset cursor; pages are flushed to disk rather than retaining the full account in memory. Message/content queries use an initial creation-time cutoff. Edits/deletes during export can change results; it is not a transactional snapshot, a complete legal-access response or a restorable backup. It excludes media file bytes, other personal settings, reactions and follower lists. Locally hidden messages may still be accessible in the backend. Unsent local messages are not exported.
- Export cancellation and failed exports remove partial JSON files. Account changes cancel subsequent export queries. Windows asks for a folder; Android 10+ saves through MediaStore Downloads/Pulse. The file is readable plaintext, with an explicit warning before export. Do not share it casually. Native platform file-save behavior requires device testing.
- **Change password** uses masked fields, matching confirmation and validation. It supports a security nonce via Supabase reauthenticate/updateUser when the provider requires it. Reauthentication policy and minimum-length enforcement must also be configured in Auth; the UI alone does not enforce server policy. Email/SMS delivery must be configured. Current-password enforcement, authenticator MFA and device-list UI are not added.
- Verification/recovery screens gain a resend action with a 60-second local cooldown and provider-error handling. This does not bypass provider rate limits or guarantee email/SMS delivery. Responses that arrive after the screen is disposed no longer update that screen's state.
- **Diagnostics** can perform a real authenticated own-profile read with a 15-second timeout and copy a report containing platform, app version, connection outcome, pending-message count and notification configuration. It does not send data automatically or include user IDs, email, tokens or message content. It is a support tool, not remote crash monitoring.
- Sign-out now asks for confirmation, warns about unsent local messages and clears local notification counts. The outbox/cache are removed after successful sign-out rather than before it. If push unregister or session revocation fails, local data is retained and an error is shown. In-flight queue operations are bound to the original account/generation to avoid writing one account's results under another account after a sign-out/switch. Global revocation still does not instantly invalidate issued access JWTs.
- Build preflight rejects server-secret configuration fields, service-role/user JWTs used as client keys, credential-bearing/insecure backend URLs and partial Firebase client configuration. It does not validate a token signature or contact providers. Both existing GitHub build jobs run this preflight, Python tests and the new standalone export test. Firebase is absent from the supplied public config; closed-app push is not enabled by this update.

## Install/build

Extract the source ZIP and replace matching files in the **existing repository root**. Keep your signing/configuration files and GitHub secrets. Include `.github/workflows/main.yml`, `native/editor`, `scripts`, `test` and `lib`. Do not delete the repository or database. Run the Pulse native beta builds workflow. The Android artifact is still a debug APK; Windows produces the unsigned native installer and complete bundle. No production signing claim is made.

Local/source checks:

```sh
python scripts/check_config.py config.example.json
python -m unittest discover -s test -p 'test_*.py'
dart test/data_export_offline.dart
dart test/validation_offline.dart
```

For native CI retain `python scripts/bootstrap.py`, `flutter pub get`, formatting, analysis, Flutter tests and the existing build steps. The standalone checks above do not replace Flutter/native compilation. Commit the successful pubspec.lock returned by CI.

## Test evidence

**User-reported:** on 15 October 2026 the user reports that they and their brother successfully tested chatting on two devices. This validates that chat flow on their tested version/devices; exact build, OS pair, request/privacy variants and closed-app behavior were not specified. It does not establish a device pass for this new patch.

**Passed locally:** formatting/parser checks; standalone analysis of new export/validation code; export pagination over 631 Unicode messages, content preservation, cancellation cleanup, rejection of oversized/non-advancing pages and protection against overwriting an existing file; password confirmation checks; five Python tests covering bootstrap idempotency, native integration/Windows branding and build-configuration failures; public-config preflight. Existing standalone upload, appearance and visibility checks are retained and rerun as documented in verification notes.

**Not run:** Flutter semantic analysis/widget tests, native Kotlin/C++ compilation, APK/EXE builds, real backend export, actual password change/nonce and resend delivery, native export download destination, cross-device global-sign-out and notification-device checks. No real user's password/session was changed to test this patch.

The 012 request/privacy/Premium security suite remains unverified after its corrected fixture: the prior rerun was blocked when automatic approval review hit a usage limit. This patch does not bypass that block or reinterpret old results as a pass.

## Remaining before public launch

See RELEASE_READINESS.md and OPERATIONS.md. Full account deletion with ownership transfer/media cleanup, E2EE, linked-device security/MFA, background push delivery, code signing/automatic updates, payment verification, production moderation, storage capacity, backups/restore drills and independent security/load checks remain. LiveKit is deferred separately. This update improves the beta; it does not make the whole platform finished or production-ready.
