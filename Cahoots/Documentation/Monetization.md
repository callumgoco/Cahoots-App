# Cahoots Plus monetization

## Packaging

| Tier | Active crew memberships | Product surface |
| --- | --- | --- |
| **Free** | **1** | Full check-in, vote, recovery, leaderboard in that crew |
| **Plus** | Up to **10** | Same features across multiple crews |
| **groupPro** | Unused | Reserved for a later crew-sponsored experiment |

Do **not** gate the core accountability loop. Do **not** monetize per-crew member limits (2–20 stays social).

## SKUs (App Store Connect)

| Product ID | Type | Suggested price |
| --- | --- | --- |
| `cahoots_plus_monthly` | Auto-renewable | $4.99 / month |
| `cahoots_plus_annual` | Auto-renewable (default in paywall) | $29.99 / year |

Configure a **7-day free trial** introductory offer on the annual product.

Local StoreKit testing uses [`Cahoots/Cahoots/Configuration/Cahoots.storekit`](../Cahoots/Configuration/Cahoots.storekit). The shared **Cahoots** scheme points at that file for Run (Xcode → Edit Scheme → Run → Options → StoreKit Configuration). Clear it to **None** before a sandbox purchase against App Store Connect.

## Gates

- **Blocked when over Free cap:** create group, redeem invite / join.
- **Always free:** first crew from empty account, check-in, clips, voting, recovery, leaderboard, switching among crews the user already belongs to.
- **Escape hatch:** leave current crew, then join/create the new one without Plus.
- **Grandfather:** users with more than one active membership at migration time receive `plus_preview_until = now() + 90 days` (Plus limits without StoreKit).

## Client architecture

- `EntitlementService` → `StoreKitEntitlementService` (live), `PlusEntitlementService` (demo), `FreeEntitlementService` (unit tests), launch arg `-entitlement plus` for UITests.
- `AppStore.paywallContext` presents `PaywallView` from `RootView`.
- After purchase/restore, client calls Edge Function `sync-entitlement` so RPCs see Plus.

## Server enforcement

- `private.crew_membership_limit(uid)` / `private.assert_can_add_crew_membership(uid)`.
- `private.create_private_group` and `private.redeem_group_invite` raise `plus_required` when over cap.
- Profile columns: `entitlement`, `plus_expires_at`, `plus_preview_until`, `plus_original_transaction_id`, `entitlement_updated_at`.

## Edge Functions

| Function | Role | JWT |
| --- | --- | --- |
| `sync-entitlement` | Authenticated user posts signed StoreKit transaction; updates profile Plus fields | required |
| `storekit-notifications` | App Store Server Notifications V2 → renew / expire / refund / revoke | off (Apple webhook) |

Both are deployed on project `wfxmguwfowvtkngqiqfr`. ASN URL:

`https://wfxmguwfowvtkngqiqfr.supabase.co/functions/v1/storekit-notifications`

## Operator checklist (production)

1. App Store Connect: Paid Apps agreement, Plus subscription group, both products, annual intro offer.
2. Xcode / Apple Developer: In-App Purchase on App ID `com.callumoconnor.cahoots`.
3. ~~Deploy entitlement migration~~ (applied as `cahoots_plus_entitlements`).
4. ~~Deploy `sync-entitlement` and `storekit-notifications`~~. Still set Edge Function secret:
   - `APPLE_BUNDLE_ID=com.callumoconnor.cahoots` (Dashboard → Project Settings → Edge Functions → Secrets, or `supabase secrets set`)
   - Optional later: App Store Server API key material for stricter ASN verification
5. Point ASC Server Notifications V2 (Production + Sandbox) at the ASN URL above.
6. Sandbox purchase on a physical device with scheme StoreKit Configuration = **None**; confirm profile entitlement flips and a second join succeeds.
7. Confirm UITests still pass with `-entitlement plus` (or demo mode).
