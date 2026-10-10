For 0.2 additions and authoritative setup status, read [UPDATE_0.2.md](UPDATE_0.2.md) first.

# Deployment and next stages

## 1. Validate the native foundation

Generate runners using `scripts/bootstrap.py` on a non-root developer/CI machine, resolve pinned dependencies and commit the resolved `pubspec.lock`, run analyzer and tests, build debug Android and release Windows. The workflow builds against the public example config; use a staging project by changing config before CI to avoid test traffic in production. Rotate only public config when moving environments; secrets stay in provider dashboards/server runtime.

Use two real test devices/accounts for registration, reconnect, app restart, wrong-password rejection, private/group messaging, replies/edits/deletes, outbox retry and blocked contact flows. Verify incoming-avatar/outgoing-no-avatar behavior at phone and desktop widths. Test authenticated media ACLs using a third account. Test 4 GB Android and Windows machines; no low-end performance claim has been measured.

For existing Pulse project, migrations are already applied. For other projects, use the Supabase migration API or CLI-generated migration files, deploy `pulse-login`, enable Postgres changes for the published tables, inspect grants/RLS/storage policies and run advisors. Never expose `pulse_private` through Data API. Server credentials for `pulse-login` must be populated by the Edge runtime.

## 2. Finish authentication and account safety

Configure SMTP, confirmation/recovery templates containing `{{ .Token }}`, phone OTP provider, Auth redirect settings if links are later added, 12-character password minimum and breached-password checks. Do not reuse secret keys from chat history; use provider secret management. Add captcha, per-IP/global auth abuse limits and monitoring to complement username throttling. SMS and email delivery have not been configured or tested here.

Implement TOTP MFA enrollment/challenges and require appropriate assurance in RLS/RPCs; a frontend-only MFA prompt is insufficient. Add server-managed devices and revocation, including checks against active sessions for sensitive actions. Implement account closure/export and deletion with membership ownership transfer/media cleanup. Never grant operator rights from editable user metadata.

## 3. Finish messaging and encryption

Add cursor pagination, per-conversation local encrypted storage with eviction, expired signed-URL refresh, private typing/presence, delivery/read updates on actual foreground display and push integration. Current snapshots load up to 200 messages; change streams reconcile periodically, not via a high-scale synchronization service. Replace all-user channel follower fetches with paginated/scoped follower counts before scaling. File upload currently uses full native files and a 10 MB bucket cap.

For E2EE use an audited protocol implementation and obtain a security review. Private messages are currently **plaintext in the server database**; local vault/TLS/RLS do not make them E2EE. Device linking, key rotation, verification, attachments and recovery all need threat modeling/testing. Message editing/deletion/forwarding must operate on authenticated encrypted envelopes after this stage. Define migration behavior for any beta plaintext content.

## 4. Calls and background delivery

Implement private authenticated signaling and call state; configure TURN and test networks that block direct peer connectivity. Use WebRTC for one-to-one media and an SFU for group calls. Configure FCM for Android, APNs for future iOS and an appropriate Windows notification/channel registration. Add microphone/camera permissions only when features exist, foreground-call service behavior, incoming-call UX, media routing, reconnect and rejection tests. Calls and push are currently absent.

## 5. Billing, communities and media

Integrate a payment/store-billing provider with merchant support, signed webhooks, event idempotency and server-side entitlement reconciliation. `pulse_plans` defines USD 300 cents/month; it does not authorize charges. The promo is one redemption per verified account, not per person; add stronger fraud eligibility if needed. Implement actual Premium themes, stickers and larger-upload enforcement before selling benefits.

Implement invite tokens with expiry/rotation, communities, polls, member permissions, private channels, richer statuses, media thumbnailing/transcoding, scanning, quotas and orphan cleanup. RLS must accompany each new table/storage policy. No placeholder client button should charge or claim access to an unavailable feature.

## 6. Signed releases and updates

Android: use a private release keystore and Play App Signing; distribute AABs through a store track. Add a supported Play in-app update flow where available. Sideloaded APKs require a deliberate user installation with the same package/signing key; do not promise silent updates.

Windows: the included Inno script packages the native EXE, engine DLLs and assets. Sign the installer/executables with Authenticode. For managed updates choose signed MSIX plus a hosted HTTPS App Installer feed, or a signed installer updater with pinned publisher/signature checks. Add version feed, staged rollout, rollback policy and update UI; none of those are wired into the client yet.

iOS: requires macOS, Apple provisioning, push credentials, entitlements and store review. Add and validate the Flutter iOS runner when that stage begins.

CI artifacts are previews until native tests, code signing and dependency review pass. Pin action commit hashes after reviewing the selected actions; the supplied workflow uses version tags. Keep production certificates/keystores/payment keys in encrypted CI secrets, never in `config.local.json`. Supply SBOM and third-party license notices before distribution.

## 7. Operate and release

Set backups/recovery drills, database indexes and rate limits, metrics/errors/alerts, abuse moderation, data retention and incident procedures. Finish administrator audit logs/account suspension and secure grants. Run security advisors and backend negative tests, then native device, reconnect, load and independent security tests. Launch after these results support the claims made to users.
