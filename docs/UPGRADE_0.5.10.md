# Pulse 0.5.10

- Create is rebuilt around a large media preview. Phones use a vertical workspace; desktop uses a preview beside posting details. Post/Draft actions remain fixed at the bottom.
- Photo/video Studio editing happens before uploading. Local copies are held in a temporary composer workspace, so selected originals are never deleted. Media can reopen in Studio; photos can be selected and reordered by holding a thumbnail. Caption changes from Studio carry into the post. Removed/replaced temporary edits are cleaned with the workspace.
- The picker no longer imposes the old eight-photo limit. Posts still use one video or multiple photos, the existing 2 GB per-file hosting maximum, and the existing server attachment-metadata limit. Each photo is edited sequentially.
- Audience choices use a focused sheet. Hashtag, mention and community controls insert caption tokens at the cursor. Drafts preserve audience and video-download preference.
- Allow video downloads is checked through a server export RPC for both saves and external media sharing, before fetching media and after encoding. The owner can export their own video. Playback and in-Pulse post sharing stay available according to post visibility. These app-level controls cannot revoke earlier downloads or prevent screen recording/direct capture of playback.
- Home has a simpler header, rounded media-first cards and compact metadata. Reels adds a functional scrubber and For You marker. Video covers remain visible until playback advances; a gradient fallback is used for older uploads without a cover.
- Video URL/open requests and buffering have deadlines and explicit retry UI. This addresses indefinite blank loading states; device codec/network compatibility still requires testing.

## Validation

Dart parsing/formatting, isolated SQL schema/security tests and Python helper tests passed. New Flutter tests cover phone/desktop composer layouts and saving caption/audience/download choices. Those widget tests, full Flutter analysis, native Android/Windows builds, actual media editing/reordering and playback smoke tests must run on the new main commit.

026_composer_download_privacy.sql is applied to the connected backend. Do not reinstall historical schema scripts on live data. No checkout provider or LiveKit credentials are configured by this update.
