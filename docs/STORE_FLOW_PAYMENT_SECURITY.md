# StoreFlow Payment Security Setup

## Slip verification provider

1. In Supabase Dashboard, open Project Settings -> Edge Functions -> Secrets.
2. Add `SLIP_CREDENTIALS_ENCRYPTION_KEY` with a random 32-character ASCII value. Generate one locally with:
   `openssl rand -hex 16`
3. Keep this secret stable. Changing it makes existing encrypted store API keys unreadable; if rotated, each store owner must re-enter their EasySlip key.
4. In EasySlip, register the store's receiving bank account / PromptPay account for account matching.
5. In StoreFlow, open Payment Settings and enter the store's EasySlip API Key. The key is encrypted by the `verify-slip` Edge Function and is never returned to the browser.
6. Configure the store's bank account number and account name, or PromptPay ID and account name, in Payment Settings.

The Edge Function uploads the stored image to EasySlip API v2 (`POST https://api.easyslip.com/v2/verify/bank`) with `matchAccount=true`, `matchAmount`, and `checkDuplicate=true`. It checks the returned `transRef`, amount, registered receiver account, THB currency, and transfer timestamp. The current freshness window is 30 minutes (with 2 minutes of future-clock tolerance).

If EasySlip is unavailable or the account information is insufficient, the sale stays pending and enters `Pending Review`. Only the store owner can manually approve it after independently confirming that the money actually arrived in the bank account. Manual approvals are marked `Owner Verified` and recorded with the owner ID and note.

## Google Pay and Stripe Checkout

- `card` is enabled for monthly, yearly, and lifetime Checkout Sessions. Google Pay is a card wallet rendered by Stripe Checkout when the customer's browser/device and Stripe account are eligible; it is not a separate `payment_method_types` value.
- `promptpay` is added only to the one-time lifetime purchase. Do not add it to recurring subscription sessions.
- Lifetime Checkout uses the existing `stripe_lifetime_price_id` configured for the `lifetime` plan (database display price: THB 2,590).
- Entitlements are granted by the signed Stripe webhook only after Stripe reports the payment as paid. Delayed methods are handled through `checkout.session.async_payment_succeeded`.

## Database protections

- A bank-transfer sale can remain pending while the customer transfers and uploads the slip.
- The deferred database constraint prevents a transfer sale from committing as paid/completed unless it has a slip path, a unique transaction reference, and a `verified` or `manual_verified` state.
- `sales` and `payment_slips` enforce unique transaction references per organization/store.
- Client roles cannot directly change payment verification fields. The trusted verification Edge Function finalizes verified payments.
- Historical paid bank-transfer rows without evidence are labeled `legacy_unverified`; they are not silently represented as verified.
