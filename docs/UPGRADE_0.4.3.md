# PULSE 0.4.3 — Interface polish and autoplay

This source update continues 0.4.2. It does not claim feature parity with TikTok/WhatsApp or production readiness.

## Design changes

Original Pulse vector mark and compact lowercase wordmark replace stock lightning icons in the splash, Home header, login and desktop navigation. Flutter startup uses a one-time 650 ms eased reveal, restrained typography, no forced startup delay, and a small genuine loading indicator beneath the screen. Minimal is the default for new accounts; previous explicit splash choices remain. Glow/Wave/Minimal choices now share the same original mark; Glow is a subtle edge tint. Android OS launch resources match the mark and dark base; account-specific styles begin inside Flutter.

Mobile navigation is a compact six-item bar with visible labels and a distinct Create action; desktop navigation expands on wider windows. Existing destinations/actions remain available. The Home Discover/Following filters use simple active-underlined tabs. The shared theme has quieter surfaces, flat bordered cards and clearer title spacing while preserving wallpaper-based accents. Login headers reflect sign-in/register/verification/recovery states, with identity/password autofill hints and password-visibility tooltips. Chat bubbles use readable solid surfaces, and profile counters have clearer hierarchy. This is a source-level refinement across core surfaces, not a full redesign of every settings/admin/call screen.

## Autoplay

Reels' existing swipe/autoplay remains. Home video posts now start muted once more than 55% of their player area is visible (excluding navigation/header insets), with explicit sound control. Selection previews also start playing muted; pause on the desired cover before accepting. Stored composer media without a cover remains manual playback.

Visibility is sampled every 350 ms. Offscreen/off-route feed players are released to reduce retained buffers; each has an 8 MiB demux buffer. App background pauses playback; visible foreground playback can resume unless manually paused. Shared activation is serialized, and programmatic pauses are distinguished from user pauses. Native video controls remain available. Autoplay streams data; a data-saver policy, adaptive bitrate/transcoding and persistent playback-position restoration are not implemented. Where two clips qualify, one gains playback focus; no claim of a TikTok-grade feed scheduler.

## Validation and limits

Passed: standalone Dart video-visibility analysis/tests (thresholds, scroll-out, nav insets, invalid layout, compact viewport), appearance preference tests, Python bootstrap/idempotent Android splash-resource test and Dart source parsing/format. These do not test native MediaKit autoplay or visual layout. New offline visibility test is included in both native CI jobs.

Android/Windows native builds, actual texture/audio playback, manual pause/resume, fast scrolling, simultaneous visible players, background/route changes and preview cover capture still require GitHub Actions/device validation. Earlier automatic approval review rejected local Flutter startup due a cloud metadata endpoint; local Flutter execution was not retried or bypassed. The UI has not been rendered natively here. Test low-memory phones, desktop resizing, large system text and screen-reader navigation.

## Install/build

Replace matching repository files with the contents inside this ZIP's `pulse-messenger` folder, including `.github/workflows/main.yml`. Keep custom configuration and signing keys; do not delete the repository. Commit and run a NEW native workflow. Download artifacts only after their job passes. No new backend SQL/deployment is required for this patch. LiveKit configuration, paid billing, full photo/video editing and the hosting requirement for 500 MB transfers remain outstanding.
