# Video-first calls — 0.1.0+44

Video calls now use a full-bleed main video and a small rounded, draggable in-call preview. Tap the preview to swap the two views. Dragging snaps it to a safe corner, above the call dock and below the header. Its placement adapts to resizing and orientation; tiny windows hide the preview when it cannot fit safely. Three or more connected participants use a bounded grid.

The header shows the peer/group name and existing delivery-aware Calling/Ringing state, then an elapsed duration updated locally every second. Full video and fit-to-screen modes are available from the quick tools or More menu. Device controls are actual microphone, camera, camera switching and mobile speaker routing operations. Participants displays the existing call members and their invitation/join state; it does not pretend to invite people outside the call. Group call authorization and limits are unchanged.

A rounded dark dock keeps More, camera, speaker, microphone and red End controls visible. End remains usable while a device operation is busy. Back and End close the route on the next frame, while bounded server/media cleanup starts in the background. The screen stays awake during the call. No new server endpoint or database migration is required.

The previous transport-encryption information remains in Call information rather than a banner covering the video. This is a WhatsApp-style layout, not an implementation of WhatsApp's end-to-end encryption. The Android beta still releases a call when backgrounded: this preview floats inside Pulse and does not add Android system picture-in-picture or a foreground-call service.

Validation covers interactive preview swapping/drag bounds, small and landscape windows, large text, eight participants, a scrollable More menu and an enabled End button during busy controls. Synthetic-camera screenshots are emitted for visual review; user-supplied photos are not published to CI. Full existing signaling/backend/native checks should pass before distributing the build. Two-device camera/audio checks are still required on physical devices.
