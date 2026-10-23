# Pulse 0.5.12+27: Squad sandbox checkout

## Scope
A separate test checkout is available from Animated profile & Boost > Test Squad checkout (no real money).
The test simulates NGN 100 (10,000 kobo); this is not an exchange rate or product price.
Enter a test receipt email, open Squad sandbox checkout, return to Pulse and press Verify test.
The email is sent to Squad only after pressing Open sandbox checkout.
Test references are bound to the signed-in account. Changing accounts cannot verify another user's reference.
The reference is retained only while this page stays open; after restart begin a new test.

## Deployment
The `pulse-payments` Edge Function v1 is deployed to the Pulse project.
Set `SQUAD_SECRET_KEY` in Supabase Edge Function secrets to a sandbox secret beginning `sandbox_sk_`.
Live keys are explicitly rejected. The function only calls the fixed sandbox API host and returns allowlisted HTTPS sandbox checkout URLs.
A signed-in active account is required. Test start/verify share the existing server live-probe limiter (3 per minute); this also temporarily consumes LIVE diagnostic checks.
This temporary reuse avoids adding an unapproved migration; use a dedicated payment limiter before release.

## Verification and limitations
The Node sandbox-rule tests pass (key mode, checkout host, owner, reference, exact amount/currency/status).
The deployed endpoint rejects unauthenticated requests with Sign in required.
No authenticated provider checkout, actual secret validity, Flutter analysis/widget tests, or native device checkout has been verified yet.
Native builds must be run in GitHub Actions. Flutter is not executed in this environment.

## Not enabled
No coin credits, gifts, animated-profile entitlements or Boost purchases are granted by the test endpoint.
Existing product purchase buttons remain disabled.
No webhook, production payment fulfillment, recurring debit, refunds or payout integration is deployed in this update.
The existing USD catalog is unchanged. Confirm production currencies, merchant permissions, prices and an explicit FX policy before NGN sales.
Do not switch to live mode merely by replacing the secret: production integration and release tests must be completed first.
Google Play distribution needs an appropriate billing integration for digital goods.

## API references
https://docs.squadco.com/Payments/Initiate-payment/
https://squadinc.gitbook.io/squad-api-documentation/payments/accept-payments-1
The old verification page is deprecated; verify the provider contract with a real sandbox response before release.
