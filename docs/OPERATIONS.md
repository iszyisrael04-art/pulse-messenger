# Pulse operating and launch worksheet

This is a runbook/worksheet, not evidence that production operations or legal policies have been completed. Credentials stay in provider/CI secret stores. Do not paste them into source or chat.

## Backups and recovery

1. Confirm what the backend plan backs up and its retention/restore limits. Record a database backup schedule and secure access owner. Database backups alone do not substitute for backing up uploaded media files.
2. Define separate media backup/inventory and retention procedures for each Pulse storage bucket. Avoid copying signed URLs as backups; preserve protected object data and access rules.
3. Restore to an isolated staging project. Apply/verify schema, grants, RLS and private buckets. Never restore unreviewed fixture credentials into production.
4. Verify test-account login, ownership, chat history, restricted media access and content privacy after restoration. Record the recovery duration and amount of data lost; set explicit recovery objectives based on that result.
5. Delete temporary staging exports according to the retention policy. Do not call backups ready until a restoration drill succeeds.

## Monitoring and abuse

Assign a responsible operator and monitor Auth failures/rate limits, database errors/latency, storage failures/egress, Edge Function errors and spend/capacity. Start with provider dashboards and controlled alerts; no external telemetry/crash collector is added by 0.4.5. The app Diagnostics screen is user-triggered and can help reproduce connectivity issues without exposing message text.

Maintain a report-review queue, escalation path, response targets and actions for blocking/removing abusive material. Basic report/admin screens are not a complete trust-and-safety operation. Test operator authorization with a normal account. Define upload quotas/abuse limits, copyright process, child-safety reporting and emergency escalation with appropriate professional support before worldwide launch.

## Signing and release

Keep Android release keystore/passwords outside the repository and backed up securely. An upgrade must use the same application ID/signing identity. Current Android CI uses debug signing and is not a production release. Windows installer AppId remains stable; sign the native bundle/installer with the chosen publisher identity before broad distribution. Keep the complete native DLL/assets bundle together. Automatic update delivery is not implemented; do not fetch/execute unsigned installers from arbitrary URLs.

For every release, retain a source/version identifier, dependency lockfile, test logs and artifact checksums. Test installing over the previous build without losing accounts/history. Roll back the client only after checking backend compatibility; do not reverse schema changes blindly or reset real data.

## Policy decisions required before publication

Fill in and review these facts before creating final public Privacy Policy/Terms pages:

- Operator legal identity, contact address and working privacy/support/deletion contact.
- Intended countries and age/eligibility rules, including handling of minors.
- Actual stored fields (auth email/phone, public profile, plaintext chat database, media, social content, reports, Premium history and device notification tokens when enabled), purposes, access controls and provider recipients.
- Clear disclosure that E2EE is not implemented; distinguish deletion-for-me, deletion-for-everyone, account deletion and backup retention.
- Account deletion workflow and shared group/channel ownership handling. It is not implemented yet; export is not deletion.
- Retention periods for content, logs, reports, deleted accounts and backups; operator procedures to honor them.
- Payment provider, subscription/renewal/cancellation/refund terms only when checkout is implemented. The planned $3/month price is not currently charged.
- Reporting/moderation rules, appeals, copyright process and security-incident contact.
- Update distribution, third-party/native codec notices and country-specific obligations reviewed with suitable professional help.

Do not publish this worksheet as if it were a finished policy or promise a retention/deletion process that has not been implemented and tested.
