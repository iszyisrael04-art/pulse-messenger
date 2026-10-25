# Windows snapshot backport

`flutter_frame_capturer.cc` and `.h` come from flutter-webrtc main, reviewed at
commit `f1bc5f8cf006703298832e5891a29bb4e0d43512` (2026-10-25). See the adjacent MIT
license and the dependency's existing license notice.

The pinned resolved release 1.6.2+hotfix.4 busy-spins while waiting for a camera
frame and allocates a pixel array without releasing it. The upstream implementation
uses a condition variable with a two-second deadline, waits for the renderer to
detach, and owns pixels in a vector. Pulse's Windows build helper applies only
these two upstream source files after dependency resolution. It refuses unknown
unfixed versions, and skips an already fixed source.

Source: https://github.com/flutter-webrtc/flutter-webrtc/tree/f1bc5f8cf006703298832e5891a29bb4e0d43512/common/cpp
