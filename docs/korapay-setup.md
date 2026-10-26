# Korapay checkout setup

This adds Korapay hosted redirect checkout while retaining existing Squad webhooks and receipts. Korapay is not selected or enabled automatically. No live transaction or API-key verification was performed by this change.

## Secrets (Supabase → Edge Functions → Secrets)

- KORAPAY_SECRET_KEY: paste the merchant's live secret directly in the dashboard; never in chat or Git.
- KORAPAY_MODE: live (test mode requires a separate test secret).
- KORAPAY_NGN_PER_USD: the merchant's chosen naira price for one USD of Pulse catalog value. This is a merchant-configured price, not an automatic market FX feed. Since 100 coins cost $1, this also sets the naira price of 100 coins. Existing orders retain the original quote when this value changes.
- KORAPAY_LIVE_ENABLED: false until configuration and end-to-end acceptance testing are complete; true enables new checkout requests.
- PULSE_PAYMENT_PROVIDER: korapay selects this provider for new client requests. Leave unchanged until ready to switch.

No public Korapay key is required for server-side redirect checkout. Neither key belongs in the Flutter client. Save values directly in Supabase.

Webhook URL: https://mhebynaprmhxfbcsiqgf.supabase.co/functions/v1/pulse-payments
Set it in Korapay → Settings → API Configuration → Webhook URL. Checkout initialization also supplies notification_url. The function keeps gateway verify_jwt=false because it authenticates user JWTs itself and verifies signed provider webhooks.

## Guarantees and boundaries

Native build 50 allows only exact approved HTTPS checkout hosts and displays a confirmation with the returned naira quote before opening a browser. Earlier apps reject Korapay links by design and need the update. Product catalog prices remain USD internally; Korapay charges are NGN. No guessed exchange rate is installed.

Only active authenticated accounts can create orders, inspect their own payments, or run sandbox probes. SKU, base price and immutable naira charge come from the server. Private Korapay orders are service-only and isolated from existing Squad references. Fulfilment uses a locked order, exact amount and currency, unique receipt and idempotent wallet/creator grants.

Webhooks verify HMAC-SHA256 over JSON.stringify(payload.data), then re-query GET /charges/:reference. A successful signature or redirect alone never credits coins. Both amount and amount_paid must exactly match the stored NGN quote. Underpayment, overpayment, wrong currency/reference, pending states and test receipts cannot fulfill a live order. Exceptional over/underpayment requires merchant review rather than automatic credit.

Test mode uses sk_test_ keys and test-checkout.korapay.com; simulated transactions never create/fulfill live orders or credit coins. No new withdrawal/payout integration is included; current withdrawal controls remain unchanged. Approval of merchant KYC alone does not prove an end-to-end Pulse purchase works.

## Acceptance

1. Run automated mock provider and isolated SQL tests.
2. Save test mode/key and select the provider; use official Kora test details in the native sandbox page.
3. Save live configuration and chosen price. Enable only when the merchant is ready.
4. The account owner manually completes a small live purchase, then verifies exact receipt/coin delivery and duplicate webhook handling. Do not transmit keys, card details or banking OTPs through chat.

Sources checked: https://developers.korapay.com/docs/checkout-redirect ; https://developers.korapay.com/docs/webhooks ; https://docs.korapay.com/ ; https://supabase.com/docs/guides/functions/secrets
