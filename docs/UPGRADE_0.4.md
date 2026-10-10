# PULSE 0.4 — social foundation upgrade

This update continues the uploaded Pulse Messenger 0.3 Flutter project. It is a source-code beta, not a completed global production platform. Android and Windows remain native Flutter apps. There is no WebView replacement.

## What was inspected and preserved

The uploaded source already contained email/username authentication, phone-auth client code, profiles, private/group messaging, voice notes, call signaling/controls, channel admin feeds/live integration, photo/video/text statuses, notification integration and deployment scripts. The call/live media path still requires LiveKit configuration and device tests. Phone OTP requires an SMS provider; closed-app push/calling and E2EE remain incomplete.

Nine existing modules (`auth`, `repository`, `channels`, `statuses`, `voice`, `profile`, `avatar`, `push`, `security`) were checked byte-for-byte against the uploaded source and are unchanged. Calls retain their existing behavior with an additional disposal guard: media cleanup is sequenced and no unauthenticated leave request is sent after account sign-out. Account changes now clear secondary routes to prevent stale profile/media screens. Existing accounts, IDs, authentication/vault keys, chat tables, groups, channels, statuses and subscription/promo records were not reset or deleted. The package ID, Flutter project name and Windows installer AppId remain unchanged. Native display branding becomes PULSE.

Premium's existing backend was preserved. The new Profile includes the existing one-time redemption RPC, and shows a Premium badge only when a backend entitlement is active. USD $3/month remains the planned price; paid billing and the complete Premium benefit set are not implemented. Verified badges read a protected database flag; there is no completed identity-verification application/review system yet.

## Safe upgrade plan and completed first stage

1. Add separate social tables and a private social storage bucket. Keep messaging access rules and media buckets unchanged.
2. Add paginated APIs with owner checks, private-account follow approval, block checks, private drafts, scoped analytics and guarded moderation. Test before relying on client controls.
3. Add Home, Reels, Create and social Profile around the existing messaging module; keep Calls, Updates and Channels accessible inside Chats and Settings inside Chats/Profile.
4. Verify backend permissions and old-feature compatibility, then pass native CI and two-device UI/media checks before distribution.
5. Continue with full social communities, richer Creator Studio, verification workflows and production security/operations in later stages.

Steps 1–3 are implemented in source. Backend tests for step 4 passed as detailed below; native compilation, UI testing and performance measurements are still required. Step 5 is not claimed complete.

## Home

- Authenticated discovery and following feeds, newest first. This is not a personalized recommendation algorithm.
- Text posts, up to eight photos or one video; profile pictures, names/usernames, active Premium and protected verified flags.
- Real likes, paginated comments, save/unsave, repost/unrepost and follow/unfollow/request approval.
- Shares into existing Pulse chats. Only a post reference is transmitted; private captions/media are not copied into a recipient's chat. The recipient's ability to open it is checked separately.
- Caption editing and soft deletion, pull-to-refresh, infinite page loading with timestamp/UUID cursors and duplicate suppression.
- On-demand video playback, loading/error/retry UI and decoded-image caching limits.

Reposts are references visible through the creator's profile tabs and engagement counts. They do not bump the original post into a fresh timeline entry. External web share links are not deployed. Copying a post ID works with Home's link button; in-chat references have an Open Pulse post button.

## Reels

- A separate vertical PageView with auto playback, swipe switching, tap pause/resume, loop and sound mute/unmute.
- Creator profiles, captions/hashtags as caption text, likes/comments/shares/saves/reposts/follow controls and uploading through Create.
- One player is reused inside the Reels screen; older video opens are superseded during rapid swiping. New pages loading at the end are activated when they arrive.
- Reels loading/error/retry states; player pauses when backgrounded and disposes when the tab is removed. Video links are renewed on explicit retry. Social media signed URLs last up to five minutes; downloaded files and existing URLs cannot be instantly revoked by deletion/blocking.

No music library, sound reuse, editing timeline, effects, transcoding, adaptive streaming, hashtag search or recommendation ranking yet. Upload optimized MP4 videos; native codec support varies. The code is designed to limit resource use, but **4 GB device performance has not been measured**. Flutter's image cache is capped at 48 MB/60 entries, images decode at a reduced width and a single Reel player uses an 8 MB demux buffer. Native decoder/engine memory is additional. Feed widgets are lazy; loaded post metadata stays in memory until the view is disposed/refreshed. There is no disk video cache or offline video download.

## Create, Profile and Creator Studio foundation

Create opens a native composer. Uploads are real Supabase Storage uploads, one selected file at a time; loading text reports file completion, not a simulated byte percentage. Photos are capped at 10 MB each and videos at 40 MB. Publishing validates stored paths, media metadata, size and author ownership on the backend. Failed publishing can retry the same content UUID safely. Uploading and server drafts require a connection. Unsaved/cancelled uploads may leave private orphan files; automatic cleanup is future work.

Profile adds a cover photo, followers/following counts, Posts/Reels tabs, saved content and owner-only server drafts. Profile editing continues to use the existing authenticated profile panel. A private-account control hides content from non-approved followers; existing accepted followers retain access. Basic profile identity, bio, avatar/cover and counts remain visible to other signed-in users unless blocked. Follow requests can be approved/declined by their recipient. Drafts can be reopened, edited and published.

Creator Studio currently shows actual backend totals for published posts/Reels, unique viewers, likes and comments. Views are self-reported signed-in post opens or video playback reaching three seconds, deduplicated per account/content. They are not audited advertising/billing metrics; no watch-time, date-range graphs, monetization or bot-resistant analytics yet.

Reports enter a restricted queue. Existing operators can review reported text/media and hide content through Social moderation. Private reported content can be reviewed by trusted operators. Operator membership comes from the existing private administrator table, not user-editable metadata. The existing admin dashboard and reports are preserved.

## Existing backend deployment

The additive `supabase/schema/009_social.sql` was applied to your existing project `mhebynaprmhxfbcsiqgf`, including the ownership-race, private-repost and reference-only sharing corrections. **Do not run it again on this project.** No old schema file needs rerunning. No new external provider or secret is required for Home/Reels; they use the existing Supabase public client config and authenticated sessions. Storage/egress costs depend on project usage and plan.

For another/staging project, review and run the numbered schema installation scripts 001–009 once in order, preserve `pulse_private` as an unexposed schema, and configure the existing Auth/functions/services. These are ordered SQL installation scripts, not Supabase CLI migration-history entries. Before production migration use, generate/review the database diff with the current CLI and test it on a clean staging database. Do not copy real customer data into fixtures or reset the current project.

## Build the APK and Windows app

1. Make a branch/commit of your current repository as a rollback point. Extract this ZIP.
2. Copy the **contents of `pulse-messenger/`** to your existing repository root, including `.github/workflows/main.yml`, all new `lib/social_*.dart` files, `lib/social.dart`, tests and docs. Keep your own signing/configuration files; do not upload secrets.
3. Run **Actions → Pulse native beta builds → Run workflow**. Both jobs use Flutter 3.47.7, the existing compatible package pins, dependency resolution, analyzer, tests and native builds.
4. The new `test/social_feed_test.dart` exercises refresh races, pagination deduplication, filter error isolation and following-feed removal. It is included for Flutter CI and has not been run locally here.
5. Once both jobs pass, download **Pulse-Android-Beta** and **Pulse-Windows-Beta**. Android contains `app-debug.apk`; Windows includes the native bundle and `PulseMessenger-0.4.0-Windows-Setup.exe`. The Windows EXE needs its engine DLLs/assets; distribute the installer or complete bundle, not a lone runner EXE.
6. Commit the successful `pubspec.lock` from the artifacts for reproducible later builds. Test on two accounts/devices before distributing.

No APK or EXE is included in this source ZIP. Local Flutter execution remains unavailable after automatic approval review previously blocked a startup request to a cloud metadata endpoint; it was not bypassed. Source parsing does not prove native compilation.

On a configured, trusted native build machine:

```sh
python scripts/bootstrap.py
flutter pub get
dart format lib test
flutter analyze --no-fatal-infos --no-fatal-warnings
python test/test_bootstrap.py
flutter test
flutter build apk --debug --dart-define-from-file=config.example.json
```

Windows requires Visual Studio C++ build tooling. Keep the workflow's CMake policy/deprecation compatibility step before `flutter build windows --release --dart-define-from-file=config.example.json`, and then run the included Inno Setup script. The previous short-path Python test fix is retained.

Debug APKs require a consistent signing key to upgrade an installed APK. A changed CI debug key can cause a signature conflict; use the original/stable signing key before an in-place upgrade. Do not uninstall a user's existing app without handling unsynced local data. Production needs a private release keystore/Play signing and signed Windows distribution. Automatic updates remain architecture-only future work.

## Validation completed / still required

- New transactional social tests passed publishing/idempotency, Reel metadata, ownership, owner-only drafts, keyset pagination, likes/saves/comments/reposts, private follow approval, private profile/repost isolation, blocks, storage access, reporting/operator moderation, private analytics, reference-only sharing and grants. Fixtures were rolled back.
- Core messaging/Premium redemption, message media, status media and channel/live authorization regression suites passed. A call-suite rerun hit a service transport error; call signaling/backend was not changed, and its earlier passing result is retained in the prior notes.
- Existing-module byte comparison, Python bootstrap test, standalone Dart validation and formatting/parser checks passed. MediaKit interfaces were checked against pinned publisher source.
- Security advisors found no public-table RLS/privileged public-function warning. Nine internal private tables intentionally have RLS with no direct client policies. Auth leaked-password protection remains disabled.
- Full Flutter dependency resolution, semantic analysis, Flutter unit tests, APK/EXE compilation, native rendering, actual media uploads/playback, network reconnect and 4 GB memory tests remain unverified in this environment.

Use `docs/SOCIAL_DEVICE_CHECKS.md` for the required native test sequence. Do not claim public production readiness until the build/device/security gates pass.

## Next stages

Full public/private social communities with membership, invitations, admin moderation, announcements and community posts are not implemented yet; the Communities navigation currently retains the existing group-chat list. More advanced Creator Studio tools, verification application/review, notifications for social actions, media processing, E2EE, background calls/push, production operations and signed updates are future stages. See `docs/FEATURE_STATUS.md` for exact boundaries.
