# 0.5.0 backend deployment completed

See [current deployment and verification status](UPGRADE_0.5.0.md). Native builds/device tests and mail delivery setup remain pending. Earlier predeployment notes below are historical.

# 0.5.0 review source — backend not deployed

See [the current review notes](UPGRADE_0.5.0_REVIEW.md). Keep 0.4.9 installed until the access-rule deployment is approved and verified. Earlier release evidence follows.

# Current update: 0.4.7

See [UPGRADE_0.4.7.md](UPGRADE_0.4.7.md) for the registration agreement, Premium profile identity changes, test evidence and remaining build/device checks. Earlier sections below describe their respective releases.

# Current 0.4.6 status

The 0.4.6 source adds chat UI/branding, Pocket notes, paid quick replies/styles and unread-only notification eligibility. Backend authorization suites pass; Flutter/native builds and device UI checks remain pending. The earlier 012 test blockage is superseded by successful current runs. See UPGRADE_0.4.6.md. The table below retains the earlier release baseline and is not a native 0.4.6 pass.

# Release readiness — 15 October 2026

Pulse 0.4.5 remains a private beta. Passing a build is necessary but is not production approval. Do not advertise unfinished features as available.

| Gate | Evidence/status | Next action |
|---|---|---|
| Two-device chat | User and brother report a successful chat test on 15 October | Retest new requests/accept/decline and reconnect after installing this patch; record version and devices |
| Android/Windows 0.4.5 builds | User reports Android builds successfully; Windows cycle corrected; full next log exposed a literal bundle-prefix install error, now corrected with a passing install regression fixture | Start a fresh Windows workflow at the corrected commit; retain artifacts, lockfile and logs |
| Export/validation/config | Standalone logic checks passed | Verify actual database export, native save location and password/resend flows |
| 012 request/privacy/Premium authorization | Corrected fixture; last rerun not executed after approval review usage limit | Run transactional suite in controlled staging; inspect negative cases and advisors |
| Real media/editors/downloads | Source implemented, device tests pending | Test codecs, trim/mute/cover, crop/filters, progress, cancellation, memory and private media ACLs |
| Calls/channel live | Deferred at user's request | Configure and test LiveKit later; no promise of incoming background calls |
| Closed-app push | Firebase config absent; dispatcher not deployed | Configure public app options plus server credentials/scheduler, obtain required authorization, test delivery/opt-out/account switch |
| Account lifecycle | Export/password/global sign-out source available | Implement and verify account deletion, shared ownership transfer, storage erasure and retention rules; add MFA/linked-device controls |
| Message security | TLS and RLS; database messages are plaintext | Implement/review E2EE before making an E2EE claim; complete broader security review |
| Storage/capacity | App eligibility is not hosting capacity | Confirm provider upload/storage/egress limits, budget, rate limits and realistic load |
| Purchases | No paid subscription checkout | Keep purchases disabled until merchant/store setup, verified events, refunds and entitlement reconciliation work |
| Release signing/updates | Debug Android, unsigned Windows beta workflow | Supply protected signing credentials, sign/install upgrades and define supported update distribution |
| Operations/moderation | Basic reports/admin tools | Assign operators and support contact; test backups, restoration, response times, enforcement and incident handling |
| Privacy/terms | Operator decisions and final policies missing | Complete launch-policy worksheet in OPERATIONS.md and publish accurate policy/contact/deletion instructions |

A beta test with invited users is a different milestone from a public production launch. Keep a record of build version, device/OS, action, expected result, actual result and any redacted error for each acceptance check. Never mark a gate passed solely because its UI exists.
