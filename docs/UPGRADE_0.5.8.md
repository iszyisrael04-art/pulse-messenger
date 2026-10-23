# Pulse 0.5.8

- Post Share now offers Share outside Pulse. Text posts share their caption; media posts export a selected photo or video through the native OS share sheet. Multi-media posts ask which attachment to share.
- Videos retain the existing Pulse watermark and creator handle. Existing access checks run before download and after rendering. Signed private storage URLs are never sent to other apps.
- In-Pulse sharing retains server-enforced post visibility and now shows recipient profile pictures, with group and missing-photo placeholders. Message forwarding remains unchanged.
- The profile avatar and its plus button now open Add story, offering photo, video and text. This reuses the existing status uploader, editing, audience and expiry rules. Edit profile still changes the profile photo.
- Temporary external exports remain in app cache for receiving apps; exports older than one day are reclaimed on the next external media share.

## Validation

Dart formatting/parser check completed for the changed sources. Full Flutter analysis, widget tests and Android/Windows builds must run in GitHub Actions on main. Native share targets and story creation need device smoke testing. No public post-link hosting or closed-app push delivery is introduced here.
