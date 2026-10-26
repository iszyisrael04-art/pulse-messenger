# Korapay checkout setup

This adds Korapay hosted redirect checkout while retaining existing Squad webhooks and receipts. Korapay is not selected or enabled automatically. No live transaction or API-key verification was performed by this change.

## Secrets (Supabase → Edge Functions → Secrets)

- KORAPAY_SECRET_KEY: paste the merchant's live secret directly in the dashboard; never in chat or Git.
- KORAPAY_MODE: live (test mode requires a separate test secret).
- Pricing is now fixed in regional-pricing.mjs at the owner's approved NGN 450 per 100 coins. KORAPAY_NGN_PER_USD is no longer read, so a stale old secret cannot override this approved price. Existing orders retain their original quote.
- KORAPAY_LIVE_ENABLED: false until configuration and end-to-end acceptance testing are complete; true enables new checkout requests.
- PULSE_PAYMENT_PROVIDER: korapay selects this provider for new client requests. Leave unchanged until ready to switch.

No public Korapay key is required for server-side redirect checkout. Neither key belongs in the Flutter client. Save values directly in Supabase.

Webhook URL: https://mhebynaprmhxfbcsiqgf.supabase.co/functions/v1/pulse-payments
Set it in Korapay → Settings → API Configuration → Webhook URL. Checkout initialization also supplies notification_url. The function keeps gateway verify_jwt=false because it authenticates user JWTs itself and verifies signed provider webhooks.

## Guarantees and boundaries

Native build 50 allows only exact approved HTTPS checkout hosts and displays a confirmation with the returned naira quote before opening a browser. Earlier apps reject Korapay links by design and need the update. Product catalog prices remain USD internally; Korapay charges are NGN. Build 51 uses the approved NGN 450 price and adds regional display estimates; it does not alter the settlement currency.

Only active authenticated accounts can create orders, inspect their own payments, or run sandbox probes. SKU, base price and immutable naira charge come from the server. Private Korapay orders are service-only and isolated from existing Squad references. Fulfilment uses a locked order, exact amount and currency, unique receipt and idempotent wallet/creator grants.

Webhooks verify HMAC-SHA256 over JSON.stringify(payload.data), then re-query GET /charges/:reference. A successful signature or redirect alone never credits coins. Both amount and amount_paid must exactly match the stored NGN quote. Underpayment, overpayment, wrong currency/reference, pending states and test receipts cannot fulfill a live order. Exceptional over/underpayment requires merchant review rather than automatic credit.

Test mode uses sk_test_ keys and test-checkout.korapay.com; simulated transactions never create/fulfill live orders or credit coins. No new withdrawal/payout integration is included; current withdrawal controls remain unchanged. Approval of merchant KYC alone does not prove an end-to-end Pulse purchase works.

## Acceptance

1. Run automated mock provider and isolated SQL tests.
2. Save test mode/key and select the provider; use official Kora test details in the native sandbox page.
3. Save live configuration and chosen price. Enable only when the merchant is ready.
4. The account owner manually completes a small live purchase, then verifies exact receipt/coin delivery and duplicate webhook handling. Do not transmit keys, card details or banking OTPs through chat.

Sources checked: https://developers.korapay.com/docs/checkout-redirect ; https://developers.korapay.com/docs/webhooks ; https://docs.korapay.com/ ; https://supabase.com/docs/guides/functions/secrets

## Build 51 regional prices

100/200/500/1000 coins cost NGN 450/900/2250/4500 for new Kora orders. USD cents remain an internal catalog unit; NGN per catalog USD is merchant pricing, not market FX. Other creator products scale by the same catalog conversion. Existing pending orders retain their original charge; the final checkout confirmation displays that exact quote.

Shop, animated-profile/Boost plans and purchase pages use the saved country, otherwise a supported region from device locale settings. This is a user-editable regional preference, not GPS or verified residence. Selecting a country never changes a frozen order, wallet balance or entitlements. Current country currency defaults (255 territories) and currency decimal digits come from Unicode CLDR 49, dated 2026-10-26. Multi-currency territories default to CLDR's first current tender currency; territories without one fall back to clearly labelled NGN.

Foreign display amounts convert the actual naira catalog price with Frankfurter's NGN exchange-rate endpoint. This avoids presenting the old internal USD catalog value as the market-equivalent price. Foreign prices carry an approximate marker, FX source/date, and an explicit statement that checkout charges NGN and the bank decides its own conversion/fees. Reference rates are informational, not bank quotes. No universal local-currency checkout capability is claimed. Additional settlement currencies require merchant enablement, currency-specific frozen quotes and verification rules before they can be used.

The server uses HTTPS, a fixed host/path, 5-second timeout, 6-hour bounded cache, coalesced requests and a maximum 7-day observation age. Only currency code goes to the FX provider: no identity, IP forwarding, card details, payment credentials or coordinates. Invalid/unsupported/expired rates fall back to an NGN amount. If pricing itself is unavailable, the app displays 'Price available at checkout' and keeps the exact-confirmation step. No made-up rates are installed. No stale FX is shown as current.

Pricing uses the existing authenticated active-account and rate-limit checks. It cannot create an order, take a payment, grant coins, or fulfill a receipt. Existing Squad routing and signed callbacks are unchanged. Kora still requires explicit provider selection/live enablement plus a live secret/mode. Those environment values are not read back or modified by this change.

Sources: https://frankfurter.dev/ ; https://github.com/unicode-org/cldr-json ; https://developers.korapay.com/docs/checkout-redirect
