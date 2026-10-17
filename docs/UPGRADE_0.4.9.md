# Pulse 0.4.9 — Account-aware support and social activity

## Support identity

Help & support now shows the current **Pulse display name**, **@username** and the email linked to the signed-in Pulse account, then includes them in the reviewable email draft/copy fallback. It does not retrieve a Google/Gmail display name or infer a Gmail address from a Pulse username. Phone-only accounts show “No email linked”. The destination remains `pulseservicemanagement@gmail.com`. No messages were sent during development. An email draft is not proof of account ownership; support must verify ownership before account-sensitive changes.

## Activity inbox

A bell on Home and Reels, plus Settings → Activity notifications, opens the actual backend activity inbox. New events after this upgrade include:

- `@username` tags in published post/video captions and mentions in comments.
- New followers and follow requests; pending requests open your profile where Follow requests can be managed.
- Likes and comments on your posts/videos. “Interested” was interpreted as likes in this update; there is no new interest-topic recommendation engine or follow-hashtag subscription feature.
- New published posts/videos from accounts you follow. Drafts do not notify. Publishing a draft creates an event then; ordinary edits do not create another publication alert. Posts published before following are excluded. Accounts with pending follow requests receive content notifications only once accepted and only when content permissions allow them.

Notifications have unread dots/counts, individual read-on-open, a mark-all-read action, pull-to-refresh and cursor-based load-more (30 per page). Avatar taps open profiles; content notifications open the existing post/video page. All five categories can be toggled in the inbox preferences; changes persist per account on the backend. Muted categories are hidden and excluded from the unread count; re-enabling can reveal older unread entries. Private messages retain their separate existing unread counts/notification behavior.

This is an **in-app** inbox. The badge refreshes on startup/resume, every 30 seconds while foregrounded, and after inbox actions. Pull to refresh for an immediate fetch. It does not send social alerts through Firebase, email, Android floating bubbles or a Windows background service. Closed-app push still requires the pending provider/dispatcher setup. It does not poll while backgrounded. Existing loaded inbox rows remain available on request failure; activity is not persisted as a complete offline cache.

## Backend and access controls

`supabase/schema/015_social_activity.sql` was applied to the connected project on 2026-10-17. Do not rerun the script or reset existing schema/data. On a separate fresh installation, the numbered installation scripts run in order through 015. No CLI migration-history entries were generated.

Private RLS-enabled tables record events, per-account preferences and individual read state. Raw client access is denied. Authenticated invoker endpoints call scoped private functions with fixed search paths. Content visibility, blocking, current follow state and preferences are rechecked on every inbox/count request; deleted/hidden/restricted posts and unliked items are suppressed. A blocked post author suppresses comment-context previews too. Email-like strings such as `person@username` are not parsed as tags. At most 20 distinct matching usernames are considered per caption/comment; missing usernames and self-mentions do not generate alerts. Removing a tag from an edited caption removes its mention record.

Follow toggles/like retries and ordinary edits do not generate duplicate alerts for the same actor/reference. Read state is per recipient, including the shared publication event. Mark-all stores the server-provided cutoff and does not intentionally clear notifications newer than that cutoff. The view covers the last 90 days; this is a display window, not automatic database deletion. Publication uses one event per post, queried by eligible followers; it does not fan out an insert to every follower. Production-scale load testing and a retention/cleanup job remain outstanding. The existing limited account export does not yet include activity records.

## Verification

Passed against the connected backend using disposable fixtures and rollback:

- `test/activity_security.sql`: follower events; @mentions in posts/comments; exclusion of email-like strings; following posts/videos; no drafts, earlier pre-follow publications or private audience leaks; duplicate-like suppression; read-on-open and mark-all; pagination; category preferences; blocking, deleted content, recipient/raw-table isolation and anonymous denial.
- Existing message-request/privacy/redemption and Premium profile identity suites passed again after the notification triggers were installed.
- An initial same-transaction timestamp test caught earlier posts appearing after a later follow. New follow rows now use actual creation time (`clock_timestamp()`); the suite then passed.

Security advisors report the intentional deny-all private RLS tables and the pre-existing leaked-password-protection warning: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . No new public-table security finding appeared. Performance advisors found no missing foreign-key indexes on the new tables; existing unrelated FK/unused-index advisories remain. No indexes were removed based on “unused” observations during beta.

Passed locally: standalone activity label/time/support-identity tests, mailto recipient/header/Unicode tests, selected pure Dart analysis, full Dart formatting/parsing, Python helpers, public config and workflow YAML checks. Both jobs run the new activity test. Full Flutter analysis, widget tests, APK/EXE builds, physical-device inbox navigation/email handoff and cross-device read-state testing have not run here. Test results are not a claim of complete production readiness.

## Build / device checklist

Replace matching files in the existing repository, including `.github/workflows/main.yml`, and start a **new** Actions workflow. The backend is already updated; do not rerun SQL. Keep all assets, native editor source, private configs and signing material in their proper locations. Version is `0.4.9+14`; Windows installer is `Pulse-0.4.9-Windows-Setup.exe`. No dependencies changed, and the prior CMake/Unicode/ffi fixes remain.

On two test accounts, follow a creator, publish a fresh post or video, type an exact existing `@username` in a caption/comment, like/comment, then refresh the recipient's bell. Test pending private follow requests, preferences, tapping profiles/content, read counts across devices, unfollow/block/delete and offline retry. Check narrow screen layout. In Help, confirm the visible account identity, inspect the email draft, and send a test email only when you choose to. Mailbox ownership/delivery and external email applications were not verified by source tests.
