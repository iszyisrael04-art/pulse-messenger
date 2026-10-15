# Pulse 0.4.4 — requests, Studio and native controls

This is an update to the existing Flutter project, not a new project or a production release. Android retains PULSE branding. Windows is named **Pulse**: window title, installer, Start/Desktop shortcuts and `Pulse.exe`. The installer AppId is unchanged for upgrade recognition. Existing account and content identifiers are unchanged.

## Install the source and build

1. Extract this ZIP. Upload the **contents of pulse-messenger/** into the same repository root, replacing matching source files. Do not delete the repository, accounts, database or personal signing/configuration files.
2. Include `native/editor/`, `scripts/`, `lib/`, `test/` and `.github/workflows/main.yml`. Native editor integration depends on those files. The workflow is included; replace the matching workflow too.
3. Keep your configured public `config.example.json` values and existing GitHub signing secrets. Never commit SMTP passwords, service-role keys or provider server keys.
4. Open GitHub Actions, select **Pulse native beta builds**, and choose **Run workflow**. Both jobs must pass. Android artifact contains the debug APK. Windows artifact contains `Pulse-0.4.4-Windows-Setup.exe`, the complete Release bundle and the generated pubspec.lock. Install the setup EXE, or keep the entire Release folder together; Pulse.exe alone is insufficient.
5. Commit the successful pubspec.lock. Production signing, updates and store distribution remain separate work.

On a configured machine, use the commands in README. Run `python scripts/bootstrap.py` before native builds; it generates the runners, registers the Android editor and configures the Windows editor DLL. Retain the workflow's Windows CMake compatibility step.

## Backend

Additive `supabase/schema/012_requests_privacy_premium.sql` has already been applied to the existing connected Pulse project. **Do not rerun all schema scripts or reset that project.** On another environment, install the existing prerequisite scripts in order and then 012, first in staging. These are installation scripts, not a clean Supabase CLI migration-history workflow.

- New direct conversations create pending requests. The sender can continue sending. The recipient must accept before sending messages or placing a call. Declining stops both sides from sending. Existing direct chats without request records retain access; groups are unaffected. Upgrade both test devices: older clients have no accept UI.
- Insert triggers enforce request permissions even when clients bypass UI controls. Participants can read only their request rows; approval is recipient-only. No public client write policy is added for request records.
- `public.pulse_unread_counts()` supplies authoritative unread counts. Read acknowledgements clear the in-app badge. Existing own-avatar/outgoing message rules remain.
- Content visibility includes Public, Followers and Private (only the author). The UI selection is backed by content/media access checks; it is not just a label.
- `public.pulse_redeem_result()` returns existing successful redemption results on a retry without extending the subscription twice. Strict one-time history remains. The active 30DAYSPULSE definition and previous redemptions were preserved, not reset. The user's exact original error was not reproduced; if it persists, retain its exact text.
- Exclusive Aurora, Sunset and Midnight profile themes require an active server-verified Premium entitlement; expired accounts render Classic. Larger-upload eligibility and Premium badges remain server-controlled. Paid subscriptions are **not connected**.

## App changes in source

- Redesigned username contact dialog: validation, debounced exact-username lookup, avatar/result state, errors and request explanation.
- Request accept/decline banner, pending-state composer and call controls, per-chat and total unread badges, tappable in-app incoming-message overlay. Alerts preserve generic lock-screen text and per-chat local notification counts.
- Message delete actions are in the existing dropdown. Posts and Reels offer Download in the dropdown, plus Windows right-click actions for download, save/unsave, copy ID, own-content deletion or reporting. Downloads recheck access and remove incomplete files. Windows streams to the chosen folder; Android 10+ streams into Downloads/Pulse. Android versions below 10 do not yet support this public-download action.
- Upload percentage reports intermediate network writes in 64 KiB segments while keeping the existing 6 MiB TUS chunk bound. Completion is confirmed by server offsets. Retry recovery can correct the displayed progress. This is transport progress, not video transcoding progress or process-restart recovery.
- Full media preview before uploading and a right-side Studio tool rail.

## Studio capabilities and limits

Photo Studio applies center crop ratios, 90-degree rotation, Mono/Warm/Cool/Vivid filters, brightness, contrast and a fixed lower text overlay to actual exported PNG pixels. Undo and reset are included. To bound memory, decoding targets a maximum 2048-pixel long edge and editing rejects input photos above 100 MiB. This editing limit is separate from upload eligibility. Animated image editing exports the first frame. Free-position text, drawing, arbitrary crop gestures and retaining original full-resolution quality are not implemented.

Video Studio previews playback, selects trim range, mutes exported audio and selects a JPEG cover. Changed video is exported through native platform codecs, not a website wrapper or an external FFmpeg download. Android performs a fast MP4 remux starting at the preceding keyframe, so its trim is **not frame accurate**. Windows uses MediaComposition precise rendering and may take longer. Unsupported codecs produce an error rather than a fake export. Native exports, cancellation and codec compatibility still require device testing. Music libraries, multi-track timelines, video filters, captions and advanced effects remain future work; this is not full TikTok editor parity.

Free accounts remain eligible for files up to 500 MiB; larger files route to Premium. The current app infrastructure ceiling is 2 GiB. **Provider storage restrictions still apply**: the connected Supabase plan's configured upload limit may be lower (including the Free-plan 50 MB limit). Premium in this app cannot override the provider limit. Billing, capacity and deployment must be configured before promising large uploads publicly.

## Verification and release gates

Passed locally for this update: all 48 Dart files parse/format; standalone analysis of upload transport, appearance model and video-visibility code; the TUS test checks intermediate progress (more than ten nonzero/nonfinal updates), retry recovery, bounded chunks and byte integrity; standalone appearance, visibility and validation checks; Python bootstrap idempotency, editor registration and Windows branding assertions.

The new transactional `test/requests_privacy_premium_security.sql` fixture initially failed because its generated promo code exceeded the allowed length. That fixture was corrected. **Its rerun was not executed**: automatic approval review could not complete after a usage limit. The new backend behavior must not be described as fully security-tested. Existing older test results do not prove these changes.

Full Flutter dependency resolution, semantic analysis, Flutter/widget tests, Kotlin/C++ compilation, APK/EXE generation, visual review and real-device editor/notification checks have not run here. An earlier automatic review block on local Flutter startup was not bypassed. Use CI and two-device acceptance tests before distributing.

Notifications added here are running-app overlays and local alerts, not Android OS conversation bubbles. Reliable terminated-app push and background calls remain incomplete; the FCM dispatcher was not deployed. Calls and channel live still need LiveKit credentials, reachable infrastructure/TURN and device tests. No new call-success claim is made. End-to-end encryption is not implemented.

## Required two-device checks

- Create a new direct chat: sender sends twice; recipient sees request and cannot reply/call; accept then exchange messages; repeat with decline. Existing direct chats and groups still work.
- Compare unread totals before and after opening a chat; foreground overlay opens the correct chat; notification privacy and permission denial behave correctly.
- Publish Public/Followers/Private media and verify access using an outsider, follower and author. Check signed media access as well as feed visibility.
- Upload a supported video on a slow connection: observe intermediate percentages and byte integrity; retry interruption. Check plan-size errors rather than assuming 500 MiB works on hosting.
- Export and play cropped/rotated/filtered photos, Android keyframe trims, Windows precise trims, mute and covers. Cancel exports, test unsupported codecs and inspect memory on a 4 GB device.
- Download through dropdown and Windows right click; cancel and revoke access; confirm no partial file remains.
- Redeem an unused code, retry after success, confirm expiry/history unchanged, reject expired reused code, verify free users cannot set paid themes and expired themes fall back.
- Run the new SQL suite in controlled staging with rollback. Close security, signing, billing and capacity gates before a public production launch.
