# Pulse 0.5.9

## Free core features

Premium UI, redemption-code implementation and paid badges are removed. Server redemption functions are retired and client execution revoked; staff promo creation is retired. Historical records remain intact. Large uploads (up to the existing 2 GB storage limit), backgrounds, Profile Signals, chat bubble styles and 20 quick replies are free. Verification badges are independent and remain available to authorized staff.

## Standalone animated profiles

GIF and five-second video profiles cost USD $1 as a one-time unlock. The connected administrator account @iszy receives a permanent owner grant stored against its account ID. It remains valid if its username or staff role changes. Existing Premium codes do not activate this product. Both upload authorization and animated playback leases use the new server entitlement. Static 15 MB profile photos stay free.

## Boost catalog

| Plan | USD price | Period | View cap per public video |
| --- | ---: | --- | ---: |
| Boost 50K | $25 | Monthly | 50,000 |
| Boost 100K | $40 | Monthly | 100,000 |
| Boost 500K | $1,000 | Yearly | 500,000 |

Active purchased plans make eligible public videos available in labeled Promoted slots in Home and Reels. Private accounts and restricted posts are excluded. Unique delivered views require a recent server-issued exposure plus the existing three-second playback report. Organic views do not count as paid delivery, and receipt confirmation never inserts video views. Per-video caps and plan expiry are enforced server-side. These beta playback reports are not audited advertising metrics; delivery depends on available real viewers and the cap is not a guarantee.

## Checkout status

Payments, automatic renewals, refunds and checkout UI are not connected to a provider. Purchase buttons clearly say Checkout not connected; no user is charged. The private product catalog is authoritative. A service-role-only receipt confirmation boundary is provided for a future trusted verifier: validate provider signature/API, exact USD amount, SKU and account identity before calling it. Receipt IDs are unique and retries are idempotent; a client cannot mint access. Marking a motion purchase revoked removes paid motion access; owner access persists. Subscription cancellation and refund handling must be connected before enabling checkout.

## Deployment and verification

025_creator_access.sql is an additive upgrade for the connected backend; do not rerun older schema files on live data. The isolated runner validates historical schema/test behavior first, then this upgrade and its new security tests. Price helpers, Dart parsing and Python runner tests also pass. Full Flutter analysis, widget tests and Android/Windows builds must run on the new main commit through GitHub Actions. Real checkout and two-device LiveKit media remain unverified.
