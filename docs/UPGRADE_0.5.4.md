# Pulse 0.5.4 — revised chat update (no message forwarding)

Long-press a chat bubble (or right-click on Windows) to select one message. The icon action bar offers Copy text, Reply, Delete and Star; the reaction row offers quick emojis. Copy text writes the original message body or caption to the system clipboard, works without sending a new message, and reports clipboard errors. Copy is unavailable for deleted messages and attachments with no caption. It does not copy attachment bytes or private download links. Copy text is also available in the message dropdown, including queued text.

Message forwarding has been removed from chat menus, media side buttons, the picker and the client repository. Existing historical Forwarded labels are retained as message history. No messages or attachments are deleted.

Photo and video chat cards use more available width (up to 460 logical pixels); received messages retain a clickable sender avatar. Photos open a large zoomable viewer when tapped. Videos retain the media player controls, including its full-screen control. Voice notes and document cards stay compact. Small or low-resolution source files may look soft when enlarged; images preserve their aspect ratio. The device screen and message layout determine the inline card size.

Chat date separators, reply links, reactions below bubbles, receipts, menus and the existing composer are preserved.

## Installation

Upload the extracted cumulative update into your existing repository, preserving paths and replacing matching files. Keep main.yml unchanged. Build with the existing Android/Windows Actions workflows.

No database update is required to remove forwarding or enlarge the cards. You can skip SQL 024 for this revision. The previous SQL 024 file is retained for historical compatibility, but is not required for this layout change. If you already installed it, do not delete database objects: the updated client no longer exposes forwarding. Enhanced server-provided conversation previews still require that optional backend script; chat loading falls back if it is absent.

## Validation

For the Copy/selection revision, Dart formatting/parser checks passed for home.dart and message_selection.dart. Pure chat-display tests and their dependency-free analysis passed. Python helpers passed 10 checks with one skipped because the CMake fixture tool is unavailable. These checks do not validate Flutter clipboard behavior or widget layout; test those on devices after CI builds. Full Flutter analysis, native builds and photo/video/full-screen behavior on Android and Windows still require CI and device testing. Existing backend security tests from the preceding update were not rerun because no SQL changed.

Test old and newly sent images/videos, portrait and landscape photos, play/pause/full-screen controls, compact voice/file cards and narrow layouts with the keyboard open. Confirm Forward is absent from both text and media menus. LiveKit, push notifications, billing and other previous beta limitations are unchanged.
