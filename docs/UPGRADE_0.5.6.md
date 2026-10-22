# Pulse 0.5.6 — reference layout and camera fix

Upload these complete replacement files into the existing pulse-messenger repository. Keep main.yml and control.yml unchanged. No SQL change is required. Run Pulse native beta builds, install the new APK/Windows build, and keep existing accounts/data.

## Implemented changes

- Profiles: one scrolling header and three-column content grid instead of two independent scrolling sections. Centered existing photo/name/badges, real compact follower/following/like counts, icon-only content tabs, existing photo/background and edit tools preserved.
- Inbox: larger profile photos, more row spacing, clearer names/previews, horizontally scrolling filters and unread-only count badges. Existing chat/request behavior is preserved.
- Camera: preview is removed from the widget tree before controller disposal during reinitialization and capture preview. Playback is detached before disposal on retake. This addresses the disposed CameraController exception visible in the supplied recording.
- Working right-side Flip, flash and timer controls; 3/10-second timer; 15/60/180-second recording choices. Round chat notes retain a 30-second limit. Existing platform camera/flash support still applies.
- Create: direct Open camera button alongside existing file selection and image/video edit-preview flow. Camera Upload selects a local file and copies it into temporary app-owned storage; discarding does not delete the original file.
- Earlier administrator verification and channel/widget source corrections are included.

## Not included

No beauty/face effects, AR filters or licensed sound catalog has been implemented in the capture screen. Existing image/video editing tools remain the editing step after selection. This is Pulse branding/layout inspired by the references; no third-party logos/assets are copied.

## Verification

Dart parsing/format checks passed for modified app files. Pure Dart profile-count/privacy/exit/motion tests and chat-preview/date tests passed. Full Flutter analysis, Flutter widget tests, Android/Windows compilation and physical-device camera checks were not run locally.

On the phone, repeat the supplied recording: open chat camera, switch Photo/Video, record, stop, preview, retake, flip cameras, use a timer, choose Upload, cancel, background/resume, and reopen the camera. Confirm the red disposed-controller screen does not recur and discarded imports remain on the phone. Test a narrow screen and larger text for layout overflow.
