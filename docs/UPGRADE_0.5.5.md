# Pulse 0.5.5 — camera, upload studio and interests

This is an update of the existing native Flutter project. Accounts, messages, groups, channels, status, verification, Premium records and previous Copy/reaction changes are preserved. Message forwarding remains removed. No database script, reset or secret change is required for this source update.

## Implemented source

- Chat camera button inside the composer: tap to open Photo/Video capture. Hold the camera button and swipe up by at least 48 logical pixels to open a locked, automatically started round video-note recorder. A timer stops recordings at 30 seconds. Stop, preview, discard/retake and use-capture controls are implemented. Front/back switching is available before recording; mid-record camera switching is not implemented. Windows offers its available cameras; flash is hidden there because the camera plugin does not support it.
- Camera captures and selected chat photos/videos pass through Pulse Studio before sending, with a caption field. Voice notes remain inside the composer. The empty composer does not reserve a disabled Send button. Existing chat storage limits remain 10 MB per file. A short recording may still exceed that limit on some devices; the app reports an error rather than claiming it was sent.
- Video notes use the existing authenticated video attachment transport, duration field and media storage. The filename marker identifies circular presentation without a schema migration. The stored file is a normal video; it is displayed as a circle, not permanently masked or cropped in the file. Ordinary videos retain larger cards and full-screen player controls.
- Post/Reel media picker: Camera, All/Videos/Photos filters for the native file chooser, local photo/video previews, ordered selection and removal. Up to 8 photos or one video match the existing backend limit. This is not direct enumeration of the entire phone photo library; users select files through the native system picker. Each selected item opens the editor before upload. Existing privacy, hashtags, community tags, drafts, publishing and real upload progress remain.
- Android video tools now export rotation, centered aspect-ratio crop, monochrome, brightness, contrast and a fixed text overlay through Media3, alongside trim, mute and cover. Photo crop/rotation/filters/adjustments/text remain. Windows retains trim/mute/cover and the photo editor; advanced video style export is Android-only in this release. AI effects, multi-track editing, music licensing, speed editing, animated stickers, beauty filters and mid-record camera switching are not implemented.
- For You is the default Home feed; Discover and Friends are separate tabs. Friends uses the existing approved-following server feed (including your own posts), not everyone who merely follows you. Existing follower/private visibility rules are enforced by the server. New accounts are offered an interest picker after profile setup; existing accounts without choices can choose too. Interests can be changed with the tune icon. Choices are stored in the user's account metadata, not as an authorization claim.
- For You and Reels combine paginated hashtag-interest results with discovery candidates, remove duplicates and vary ordering while diversifying creators. There is no requirement to follow accounts first. This is a basic hashtag/text recommender, not AI analysis of video contents or a trained watch-history algorithm. If Pulse has few matching posts, discovery fills the feed.
- Phone sign-in now has a searchable country/calling-code picker and country-aware parsing of national and pasted international numbers. Significant zeros (such as Italian numbers) are preserved; invalid numbers are rejected. SMS verification still uses the real backend OTP.

## Phone OTP blocker — confirmed from this project

On 21 October 2026 the project's public Auth settings returned external.phone=false, phone_autoconfirm=false and sms_provider=twilio. No credentials were read or changed. The provider name alone does not establish valid Twilio credentials or working delivery. The last-24-hour Auth logs did not contain an SMS OTP request to diagnose provider delivery further.

Open Supabase > Authentication > Sign In / Providers > Phone. Configure a supported SMS provider with credentials in Supabase, enable Phone, and save. Provider billing, trial-recipient/geographic restrictions and carrier delivery can apply. Keep OTP verification enabled. Then test request, resend and verification with a real number, including Nigeria +234. SMTP sends email; it does not send SMS. Never put SMS provider credentials in config.example.json or client code.

The app now explains disabled-phone/provider errors and offers email or Pulse username as alternatives. SMS delivery is not fixed or verified by installing this ZIP alone.

Official reference: https://supabase.com/docs/guides/auth/phone-login

## Build

1. Extract PULSE_0.5.5_Combined_Update.zip and upload the extracted files to the root of the existing GitHub repository, preserving paths. Do not delete unrelated files. Keep main.yml/control.yml unchanged.
2. Run the existing native beta workflows. flutter pub get must resolve the new pinned camera, camera_windows, country_picker and phone_numbers_parser dependencies. Native runner generation already copies the changed Android Kotlin editor files.
3. No SQL script is needed for this update. Earlier optional script 024 is not needed for Copy, camera, interests or upload editing. Previously installed backend features remain in place.
4. Install the resulting Android and Windows builds only after CI analysis/tests/builds pass. This ZIP is source, not a compiled APK or EXE.

## Validation and remaining checks

Passed locally: Dart formatting/parser checks; international phone parsing tests; interest validation/ranking/deduplication/diversity tests; chat preview/calendar tests; dependency-free Dart analysis; Python helper checks (10 pass, one CMake-dependent test skipped); public configuration check. The new Flutter gesture test is included for CI but was not executed locally. Firebase client configuration is still absent, so closed-app push is not verified.

Full Flutter package resolution/analysis/widget tests, Android Media3/Kotlin compilation, Windows plugin compilation, physical camera/microphone permissions, camera recording/audio, clipboard and gesture layout, decoded covers, exact video effects and native exports require GitHub CI/device verification. No claim of perfect calls, E2EE, completed live streaming, paid billing, or production readiness is added.

Test on two devices: photo/video capture, denied permissions, app background/resume, hold/swipe exactly once, 30-second automatic stop, retake, cancellation without sending, sound in recorded videos, circular note arrival/playback, caption preservation, mixed/oversized selection rejection, multi-photo order, trim+mute+style export, exported cover and upload progress. Check 320px layouts with the keyboard visible. Test fresh accounts with interests, skip/change choices, matching/nonmatching hashtags, pagination, private and blocked creators, and the separate Friends feed. Test country examples and SMS only after enabling/configuring the real provider.

## Editor follow-up

The video editor now has bounded Undo/Redo for trim, mute, crop, rotation, brightness, contrast, monochrome and text edits, plus a playback seek timeline constrained to the selected export range. Slider gestures create one history step each, and a new edit discards the redo branch. Reset is undoable; covers are regenerated after restoring edits. These controls use the existing native export path. This is a single-video editor, not the multi-track timeline shown in the reference: music tracks, layer timing, shapes, split/merge and export quality selection remain pending. No unsupported controls are presented as working features.

Standalone history regressions are included in the Flutter CI test entry point. UI interaction and real exported videos still need native CI/device checks.
