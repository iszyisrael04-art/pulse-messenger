# Pulse 0.1.0+28: combined release candidate

The requested visible version is 0.1.0. Android build number increases to 28 so an existing Android installation can update without deleting its data PROVIDED the signing key is the same. The current workflow produces debug APKs; a stable existing signing key must be configured before reliable public upgrades. A build-number increase alone cannot fix a signing-key mismatch. Windows installer IDs are unchanged.

## Implemented
- Calling stays Calling until a recipient device acknowledges the current call. A pending server invitation or online dot never counts as ringing.
- Local calling/ringback/incoming tones stop when calls connect, expire, end or the controller is disposed. Incoming notification channels are separate from messages. Notification taps open Calls rather than silently answering.
- Server-authorized, short-lived Android call push invitations, foreground/background receivers and recipient acknowledgements. An expired call cannot ring after the device reconnects.
- Shop icon in Home and LIVE, normal coin and P-coin balances, ten gift tiers, gift history, a server-priced gift catalog and protected credit boundary.
- Rose: 5 normal coins spends 5 and credits exactly 2 P-coins to the recipient. Normal coins cannot be withdrawn or converted directly to P-coins. Gift recipient must be the active host or an approved guest; self-gifting is rejected.
- 100 P-coins = USD 3, as confirmed by the owner after the initial USD 30 proposal was corrected. This is an earnings valuation, not an enabled payout service.
- Same-room three-minute LIVE battles: host invites an approved guest, guest accepts/declines, gift costs determine scores during the battle window. Either participant can end; guest removal or stream expiry ends scoring. No betting or cash prize for winning.
- LIVE entry from Studio opens channel selection. Channel follower minimum remains enforced on the server; admin dashboard now points directly to Channels & LIVE follower minimum.
- Chat preview shows the latest visible message and sender name (or You). Empty chats retain Start the conversation.
- Durable, owner-bound payment orders, server prices, exact amount/currency/reference matching, signed webhook verification, provider re-query and atomic idempotent fulfillment for coins, animated profiles and Boost.
- Boost purchases buy a fixed-duration period; no automatic renewal or card tokenisation is created.

## Backend deployment
Schemas 027, 028 and 029 are installed on the Pulse Supabase project. No user money or test balances were added. The presence migration previously pending is now applied.
`pulse-call`, `pulse-call-push` and `pulse-payments` are deployed. Private wallets, gifts, orders and tokens are not client-readable tables. Clients cannot credit wallets or fulfill orders.

## Required before one final app download
1. Firebase: create/register Pulse Android app in Firebase. Put the four PUBLIC client options in the GitHub Actions secret FIREBASE_CLIENT_JSON (schema below). Put the PRIVATE service account JSON only in Supabase Edge Function secret FIREBASE_SERVICE_ACCOUNT_JSON. Never put the private service account in GitHub source, app assets or chat.
2. Build and install once with those public options; enable notifications in Pulse. FCM tokens must be registered. Validate on two devices, including data off/on while the 45-second call invitation remains valid. Android force-stop and OS battery restrictions can prevent delivery; background push is not yet device-confirmed. Windows closed-app push is not implemented.
3. Squad: the currently supplied sandbox key does not enable real money. The new function defaults live payments off. Real USD checkout requires verified live merchant permissions, an appropriate live key, SQUAD_MODE=live and SQUAD_LIVE_ENABLED=true. Do not set the enable flag until provider checkout, signed webhook delivery and fulfillment have been tested. Configure the Squad webhook URL to https://mhebynaprmhxfbcsiqgf.supabase.co/functions/v1/pulse-payments .
4. All production orders use USD catalog amounts. There is NO implicit NGN exchange rate. If the merchant cannot charge USD, agree an NGN price/FX policy and implement that explicitly before launch.
5. Withdrawals: bank payouts, recipient verification, withdrawal requests/reservations, refunds/chargeback accounting and payout reconciliation are NOT implemented. Cashout is explicitly disabled. Do not advertise payouts as available. Establish these before a public money release; never enable live payments merely to collect money for an unfinished earnings product.
6. Test real camera/audio, LIVE guests/battles, notification permissions, checkout return, refund handling and a signed release build before marking production-ready.

Public client JSON shape (replace values from Firebase app settings):
```json
{
  "FIREBASE_API_KEY": "PUBLIC_FIREBASE_API_KEY",
  "FIREBASE_APP_ID": "ANDROID_APP_ID",
  "FIREBASE_MESSAGING_SENDER_ID": "PROJECT_NUMBER",
  "FIREBASE_PROJECT_ID": "PROJECT_ID"
}
```
These are build-time app identifiers, not the private service account JSON. App package ID must match the generated Android runner. The build helper also writes native Android Firebase resources, so a push can initialize Firebase before the Flutter UI starts.

## Checks performed here
- Full Dart source formatting parsed all 126 files; changed source formatted.
- Pure Dart call-state and chat-preview tests passed; pure Dart analyzer passed their modules.
- Isolated PostgreSQL security fixtures passed for schemas through 029, wallet access, forged credits, exact Rose rewards, duplicate gift requests and receipts, insufficient funds, battle consent/scoring, call acknowledgements and payment fulfillment.
- Node payment tests passed for sandbox/live separation, URL host allowlists, webhook signatures, reference/amount/currency/status checks. Mocked FCM dispatcher tests passed for authorization, missing configuration, short TTL and content-free payloads.
- Python helper suite: 12 tests, 1 skipped, no failures.
- Native Flutter analyze/widget/Android/Windows checks are delegated to GitHub Actions; they have not run locally. No real provider payment, payout, or two-device call test was performed by this environment.

## Temporary limitations
Payment verification still shares the existing 3/minute LIVE diagnostic limiter; replace with a dedicated payment limiter before scale. Call push is dispatched immediately from call start; transient dispatch failures need an external scheduler retry before the short invitation deadline. Existing local incoming polling remains a fallback while Pulse is open. No automatic payout claims or fabricated earnings exist.
