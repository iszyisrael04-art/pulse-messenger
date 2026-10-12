# PULSE 0.4.1: previews, hashtags and upload eligibility

Replace matching files in the existing repository with this package's contents, including `.github/workflows/main.yml`. Preserve custom configuration, signing keys and GitHub secrets. Run a NEW Actions build after committing. Download Android/Windows artifacts when their respective jobs succeed. Do not uninstall an existing app if you have unsynced data; signing continuity is still required for Android upgrades.

## Implemented source and connected backend

- Free social accounts are eligible for files up to **524,288,000 bytes (500 MiB)** inclusive. Above that, a free user selecting a file is taken to Premium with “Your file is over 500MB. Please upgrade to Premium to continue.” No size-limit/Premium promotion is placed below the upload picker.
- Actual Premium eligibility comes from existing `pulse_premium` expiry records. The backend checks real stored sizes at publication as well as authenticated Storage metadata writes. Client flags cannot grant Premium. A temporary infrastructure maximum of **2 GiB** applies even to Premium; there is no unlimited-upload claim.
- The Premium page exposes the existing secure redemption RPC, including one-time eligible `30DAYSPULSE`. Paid checkout is NOT connected. No fake purchase button is supplied.
- Selecting media opens a real local photo/video preview before transfer. For videos, pause on a desired frame and accept to capture a JPEG cover. New drafts and selected uploads show images/covers rather than filenames. Legacy video drafts attempt serialized first-frame capture on demand, release the player after capture, and show retry on failure.
- Native TUS upload transport sends at most one 6 MiB chunk at a time, reports server-confirmed progress, and recovers the acknowledged offset after transient errors. It retries within the active upload; restart/background persistence is not implemented. Cover upload is separate. Interrupted uploads/orphan cleanup remain a future operational task.
- Captions expose clickable hashtag chips. Home has a hashtag search button with All / Posts / Reels filters, keyset pagination and refresh. Matching is case-insensitive and exact. Tags use ASCII letters/numbers/underscores, up to 64 characters, first 20 distinct caption tags. Hashtag results use creation order; the separate Trending videos view uses recent unique views. Private accounts, approved follows, blocks, deletion, and moderation remain enforced by the same backend visibility helper. Caption edits update the generated hashtag index automatically.
- Existing chat/call/channel/status authentication paths remain intact. Their separate media-upload limits are unchanged; this update changes social posts/Reels only.

## Hosting blocker: 500 MB is not enabled merely by this app

Supabase Free hosting has a global per-file ceiling of **50 MB**, independently of a Pulse account being free or Premium. A paid/self-hosted storage deployment with an appropriate global limit is required to actually transfer 500 MB and larger files. Do not purchase anything just to build the APK. The bucket limit in SQL is 2 GiB, but it does NOT override your provider plan or the global Storage setting.

When ready, open the project's Storage Settings and configure the global file limit to match the desired hosting cap on a compatible plan. This is an owner/infrastructure change, not a user Premium entitlement. Storage quota, bandwidth expenses and abuse controls must also be budgeted. If the provider returns HTTP 413, the app identifies the hosting limit separately and does not send an eligible free user to Premium.

Official docs: https://supabase.com/docs/guides/storage/uploads/file-limits and https://supabase.com/docs/guides/storage/uploads/resumable-uploads

## Backend installation

`supabase/schema/010_social_uploads_hashtags.sql` is additive and was applied to the existing connected Pulse project. **Do not rerun 001–009 or reset the database.** New installations run the numbered scripts in order. These are installation scripts, not CLI migration-history records; reconcile schema diff/history on a staging database before production migration tooling.

## Validation and remaining work

Passed: connected transactional `test/social_hashtags_security.sql` (free/Premium byte boundaries, tags/deduplication/case matching, draft/private isolation, caption re-indexing, deletion and anonymous RPC denial); existing `test/social_security.sql` regression suite; standalone Dart TUS transport test (chunk bounds, metadata/auth, transient-response resume, progress and exact byte integrity); Dart analysis of the transport/offline test; Python bootstrap test; Dart source parse/format.

Native Flutter analyze/tests/builds cannot run in this environment: earlier automatic approval review rejected Flutter startup because it contacted a cloud metadata endpoint. User CI remains the native gate. The user reported the preceding Windows release built; this revised source is not yet device-tested or compiled in CI. MediaKit preview/screenshot, legacy covers and real Supabase TUS binary transfers need verification on Android and Windows. No 500 MB transfer or low-memory benchmark was performed. Photo/video transformation editors are not included in this patch; it provides preview and video cover selection, not crop/trim/export tools. LiveKit credentials/deployment and two-device call/live testing remain outstanding.

Device checks: pick JPG/PNG/MP4; cancel preview; select video frame/cover; save/reopen draft; test legacy draft; revoke/delete/private/block cover access; choose a 500 MiB sparse fixture and >500 MiB fixture for eligibility without posting actual junk; test Premium redemption once; test small real TUS uploads; simulate network interruption; test token refresh; run slow-network and native memory checks. Do not publish arbitrary large test files.

Security advisor: no new exposed-function/RLS warnings; existing internal deny-all policy info and disabled leaked-password protection warning remain. https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Search added in this same patch

Home and Reels both expose Search PULSE. Videos searches video posts and Reels by caption keywords/hashtags; Posts searches all published content; Profiles finds usernames/display names using public profile projections; Hashtags shows matching topics. Typing at least two characters fetches related visible hashtag, profile, and video-caption suggestions after a 300 ms debounce, with stale-response guards. The search action is available even if suggestions fail. Keyword/video results paginate by creation time/id. Profile results are capped at 20, hashtag suggestions at 5; those lists are not fully paginated yet.

The empty query opens Trending videos: up to 20 visible videos ordered by unique signed-in view records created in the past seven days. There is no fake global trend data or TikTok recommendation algorithm. With no qualifying views it is empty. Metrics remain client-reported and unaudited. Search is caption-based, not video transcription or visual analysis; suggestions are literal related captions/topics, not an AI semantic engine. The basic profile metadata of a private account can appear, but its content remains restricted. Blocks exclude profiles too.

`supabase/schema/011_social_search.sql` was applied to the connected project. It adds an indexed generated full-text column, a recent-view index, and guarded RPCs. Do not rerun installed scripts. `test/social_search_security.sql` passed connected transactional checks for video keyword search, draft isolation, topic suggestions, no email/phone profile projection, recent-view ranking, private content/suggestion/trending isolation, blocked profiles and anonymous denial. The native suggestion/search screen still needs CI/device testing.
