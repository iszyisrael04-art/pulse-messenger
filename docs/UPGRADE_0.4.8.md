# Pulse 0.4.8 — Help & support

Settings now includes **Help & support**, addressed to `pulseservicemanagement@gmail.com`.

Users choose a topic, enter a subject and message, and select **Open support email**. Pulse opens a draft in the installed email app; the user reviews and sends it there. Pulse does not silently send mail or claim delivery. The draft includes only the entered text, app version and platform, with no automatic account identifiers or diagnostic logs. A copy-address and copy-message fallback works when no email app is available. Gmail on a phone or an installed/configured Windows mail client is needed for the mail-app path; users can paste the fallback into webmail.

The Privacy Policy now lists this support contact. Operator identity, retention terms and review before public launch remain outstanding.

No backend or dependency changes. All 0.4.7 features and Windows fixes are preserved. Both Actions jobs include the new pure Dart encoding test. Local encoding/recipient/header checks, selected pure Dart analysis, formatting and workflow parse passed. Full Flutter analysis, widget/native builds and actual email-app handoff remain CI/device checks. No email was sent during development, and mailbox ownership/deliverability was not tested.

Replace matching files in the existing repository, including `.github/workflows/main.yml`, and start a **new** workflow run. Do not reset the backend or rerun SQL. Download the built artifacts after both jobs succeed.
