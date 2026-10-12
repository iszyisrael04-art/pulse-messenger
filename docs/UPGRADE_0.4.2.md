# PULSE 0.4.2 — Themes, wallpapers and startup styles

Use Settings → Themes & wallpapers (also reachable from Profile → Settings).

## Added source functionality

- Light, Dark and System themes with persisted account/device preferences. The existing quick Dark / light switch now uses the same saved settings.
- 20 built-in gradient/pattern wallpapers, available offline. These are native vector patterns in different palettes, not stock photography or downloaded assets.
- Choose a JPG/PNG/WebP from local photos, normalize its first frame into an app-owned PNG, and show it behind all chat message lists. Removing the original gallery file will not remove the app-owned copy.
- Wallpaper matching uses a built-in palette or Flutter's Material image-color extraction for custom photos. Disable matching to choose one of 12 accents manually.
- Wallpaper dimming, a chat preview, a selected-wallpaper indicator and Restore Pulse defaults. Incoming/outgoing bubble surfaces remain opaque/readable.
- Three Flutter splash styles (glow/minimal/wave) and three animated loading styles (pulse/orbit/dots), with an explicit splash preview. Indeterminate loading in auth/chats/feed/reels/profile/media/search uses the new loader; real upload progress stays real and remains a progress bar. Some older independent modules retain their own loading indicators.
- Flutter shows a branded startup screen during actual initialization instead of waiting to mount the app until initialization completes. No minimum fake delay is added. A nonsensitive boot preference stores colors/mode/loading/splash, without photo paths, so subsequent startups can restore the selected style. The actual first Android OS launch frame is a fixed Pulse mark/background; dynamic account-selected styles apply within Flutter. Windows' pre-Flutter startup window is not replaced with a custom native window.
- Android launch resources, including Android 12+ icon/background, are generated idempotently by the existing bootstrap script. Existing native identifiers/signing/permissions remain.

## Local scope / performance

Appearance preferences are local per account on each device. Custom wallpapers are copied into that account's local application-support folder and are not uploaded to Supabase or synced across devices. Sign-out/account changes reset the in-memory appearance and load the destination account's preferences. Chat wallpaper applies globally to that account's chats, not per-conversation. Stored settings reject path traversal and unsupported values. Custom imports are limited to 30 MiB and resized with the longest edge at most 1920 pixels. Display decoding is bounded and preserves aspect ratio. Palette extraction uses a small image provider. OS reduced-animation settings disable animated loader ticks/theme transitions. No device-memory benchmark or independent accessibility certification has been performed.

## Upgrade and build

Upload the extracted `pulse-messenger` CONTENTS into the existing repository, replacing matching files including `.github/workflows/main.yml`. Keep custom config and signing keys. Do not delete the repository or reset backend tables. Start a NEW Actions run; download APK/Windows artifacts once their jobs pass. No new backend SQL is needed for this appearance patch. Previously deployed 010/011 search/upload changes remain included. Android debug signing remains private-beta; in-place installs require the same signing key as the installed app.

## Verification

Passed locally: standalone Dart model analysis and `test/appearance_offline.dart` for preference round-trip, corrupt/unsafe-path recovery, dimming bounds and independent default reset; Python bootstrap/idempotent native-splash-resource test; Python syntax check; Dart syntax/format of changed source. CI includes the preference test on both jobs.

Flutter native analyze/widget tests/APK/Windows builds were not run locally. Earlier automatic approval review rejected Flutter startup because it contacted a cloud metadata endpoint; it must not be bypassed. Native CI/device verification is pending. Test account switching, restart, missing/corrupt photos, offline wallpaper selection, wide desktop/narrow phone layouts, both theme modes and OS theme changes, reduced motion, actual startup timing, gallery-file independence, image memory, errors saving local preferences and video/call interactions. Existing chats/accounts/feed/search code is retained; this patch does not configure LiveKit, paid checkout or hosting for large files, nor add video/photo transformation editors.
