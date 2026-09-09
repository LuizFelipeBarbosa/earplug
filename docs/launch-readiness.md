# Launch readiness — v1.28

Production baseline facts were verified on 2026-09-08. Run this checklist
against `decisive-iguana-759` paired with production Clerk and
`https://earplug.app`; see [Environments](environments.md) for configuration
and the normal production release workflow. Record the date, operator, and
verification evidence in **Done on/by** as each pending step is completed.
Only the Connect endpoint step below is already recorded as done.

Commands are operator instructions. Replace `<ms>` with the current
epoch-ms timestamp when running `admin:opsHealth`; `now` is required and
`days` is optional. Replace `…` with the API key or smoke-test recipient as
appropriate. `admin:opsHealth` is an `internalQuery` and `emails:sendTest`
is an `internalAction`; run them from an authenticated operator CLI session.

## Runbook

Complete A0 through A4 in order. During A3, enable and verify each flag
before enabling the next one. Production already has payments and ticketing
enabled, a 10% booking commission (`1000` bps), and a per-ticket fee of 5%
(`500` bps) plus $1.00 (`100` minor units). `DISPUTES_ENABLED` and
`PROMOTERS_ENABLED` are unset (default `false`),
`PRIVATE_BOOKINGS_ENABLED=false` is explicit, and `BAND_GIG_WRITES` is unset
(default `true`). Both Resend variables are unset.

| Step | Owner (Luiz or architect) | Command or action | Verification | Done on/by |
| --- | --- | --- | --- | --- |
| **A0 baseline — contract** | architect | `npm run check:release-contract -- prod` | Passes against `decisive-iguana-759`, including `features:fees` and the optional `organizationApplications:submit.organizerAgreementAccepted` argument. | Pending |
| A0 baseline — flags | architect | `npx convex run features:flags --prod` | `payments` and `tickets` are `true`; `disputes`, `promoters`, and `privateBookings` are `false`; `bandGigWrites` is `true`. Save the output. | Pending |
| A0 baseline — ops | architect | `npx convex run admin:opsHealth '{"days":30,"now":<ms>}' --prod` | Save feature-flag state, Resend configuration, and Stripe event counts by type/status. Confirm the baseline above and investigate failed events. | Pending |
| **A1 Stripe — Connect endpoint** | Luiz | Already done: live endpoint `we_1UCkAuL1cr6HohouLdvDWmEG` (`stripe-connect-webhook`) was recreated with `connect=true` and the eleven connected-account events listed in [Environments](environments.md#convex-marketplace-environment-variables). | The first live `account.updated` event was applied on production on 2026-09-07. | 2026-09-07 / operator not recorded |
| A1 Stripe — platform refunds | Luiz | Confirm the platform (non-Connect) `stripe-webhook` endpoint also subscribes to `refund.created`, `refund.updated`, and `refund.failed`, plus `charge.refunded` and legacy `charge.refund.updated`. Add any missing subscriptions. | Save the platform endpoint's subscribed-event list showing all required `refund.*` events. | Pending |
| **A2 Resend — DNS records** | Luiz | Add `earplug.app` in Resend. In Netlify DNS (`dns1-4.p03.nsone.net`), add the Resend-provided MX and SPF records on `send.earplug.app`, the `resend._domainkey` DKIM record, and a `_dmarc` TXT record. | Record names and values match the Resend domain setup; the sender is `EarPlug <no-reply@earplug.app>`. | Pending |
| A2 Resend — propagation | Luiz | Run `dig MX send.earplug.app`, `dig TXT send.earplug.app`, `dig TXT resend._domainkey.earplug.app`, and `dig TXT _dmarc.earplug.app`. | Answers match the configured records and Resend marks `earplug.app` verified. | Pending |
| A2 Resend — obtain key | Luiz | Create a Resend API key authorized to send for the verified domain; keep the key in the credential store. | Key is available for the production configuration step. | Pending |
| A2 Resend — configure key | Luiz | `npx convex env set RESEND_API_KEY … --prod` | Command succeeds for production; retain no key value in this checklist. | Pending |
| A2 Resend — enable sending | Luiz | `npx convex env set RESEND_SEND_ENABLED true --prod` | `admin:opsHealth` reports a configured Resend key and sending enabled; both are required by `emails:send`. | Pending |
| A2 Resend — smoke test | Luiz | `npx convex run emails:sendTest '{"to":"…"}' --prod` | Action succeeds and the recipient receives the message from `EarPlug <no-reply@earplug.app>`. | Pending |
| A2 Resend — authentication headers | Luiz | Inspect the received email's original headers. | SPF, DKIM, and DMARC all pass. Save the header evidence. | Pending |
| **A3 flags — DISPUTES first** | Luiz | `npx convex env set DISPUTES_ENABLED true --prod`; then `npx convex run features:flags --prod`; open `/admin/disputes` and `/admin/bookings` as a platform admin. Rollback: `npx convex env set DISPUTES_ENABLED false --prod`. | `disputes: true`; both admin screens load and their queues/filters work. If verification fails, roll back and confirm `disputes: false` before proceeding. | Pending |
| A3 flags — PROMOTERS second | Luiz | `npx convex env set PROMOTERS_ENABLED true --prod`; then `npx convex run features:flags --prod`; open the `/org/apply` type picker. Rollback: `npx convex env set PROMOTERS_ENABLED false --prod`. | `promoters: true`; the promoter organizer type is available. If verification fails, roll back and confirm `promoters: false` before proceeding. | Pending |
| A3 flags — PRIVATE_BOOKINGS third | Luiz | `npx convex env set PRIVATE_BOOKINGS_ENABLED true --prod`; then `npx convex run features:flags --prod`; open the BECOME A HOST entry point and `/host/apply`. Rollback: `npx convex env set PRIVATE_BOOKINGS_ENABLED false --prod`. | `privateBookings: true`; the host entry point appears and the host application loads. If verification fails, roll back and confirm `privateBookings: false`. | Pending |
| **A4 legal go-live — approved text** | Luiz | Obtain counsel's real text for `/legal/terms`, `/legal/privacy`, `/legal/organizer-agreement`, `/legal/artist-agreement`, and `/legal/host-agreement`; resolve the decisions below. | Approved text is available for all five pages. | Pending |
| A4 legal go-live — implementation | architect | Paste counsel's text into the static pages in `web/legal/`; remove every DRAFT banner and `noindex` meta tag; set `legalEffective = true` in `lib/app_links.dart`. | All five pages contain the approved text, no DRAFT banner, and no `noindex`; sign-up requires ToS acceptance with the gate enabled. Verify the affected behavior in the Netlify deploy preview, including its `DEV` ribbon. | Pending |
| A4 legal go-live — deploy | Luiz | Merge the reviewed change into `main` through the normal Netlify production release workflow. | Production build and contract check pass; all five legal routes serve the approved text at `https://earplug.app`, and the sign-up acceptance gate works. Record the release and verification evidence. | Pending |

## Decisions for counsel

These are implementation defaults and outstanding decisions for counsel to
resolve before supplying the final documents. v1.28 adds diagnostics,
documentation, and legal scaffolding without changing money-affecting
behavior.

| Decision | Code that depends on it | Shipped default |
| --- | --- | --- |
| Merchant of record | `payments:startInstallmentCheckout`, `ticketCheckout:startCheckout`, Stripe Connect payout flow | Booking installments charge on the platform; tickets charge on the organizer's connected account with an application fee. Counsel must confirm the merchant-of-record wording and responsibilities for each flow. |
| Fee disclosure (10% commission and 5% + $1.00 ticketing fee) | `features:fees`, `convex/lib/env.ts`, booking fee snapshots, `tickets:reserve` | Production booking commission is `1000` bps; per-ticket fee is `500` bps plus `100` minor units (USD). Disclosures must match these values and any organization-specific fee configuration. |
| Cancellation percentages | [`convex/lib/cancellationPolicy.ts`](../convex/lib/cancellationPolicy.ts), `refunds:previewCancellation`, `bookings:cancel` | Organizer refunds: flexible 100% when more than 48 hours remain, otherwise 0%; standard 100% when more than 14 days remain, 50% when more than 7 and at most 14 days remain, otherwise 0%; strict 100% when more than 14 days remain, otherwise 0%. Other cancelling parties receive a full refund. Thresholds are strictly `>`. |
| Refund/chargeback split | `convex/lib/cancellationPolicy.ts`, `convex/refunds.ts`, `convex/stripeHandlers/disputes.ts`, `convex/stripeHandlers/tickets.ts` | Organizer-cancellation forfeiture is split between artist and platform at the snapshotted commission rate. Stripe disputes hold payouts; losses reconcile the charged-back amount and record processor dispute fees. Counsel must settle contractual responsibility for refunds, chargebacks, and fees. |
| Click-through timestamps and absence of a terms-version column | `convex/schema.ts`, `bookings:sendOffer`, `bookings:respond`, `organizationApplications:saveDraft`, `organizationApplications:submit` | Stores `organizerAcceptedTermsAt`, `artistAcceptedTermsAt`, `hostAgreementAcceptedAt`, and optional `organizerAgreementAcceptedAt`; there is no terms-version column tying those timestamps to a legal document revision. |
| ToS acceptance at sign-up, gated by `legalEffective` | `lib/app_links.dart`, sign-up UI | `legalEffective` is `false` while legal pages are drafts. Acceptance becomes required when the gate is set to `true`; A4 publishes the real text and enables the gate together. |
| Organizer agreement recorded but not required | `organizationApplications:submit`, `organizationApplications.organizerAgreementAcceptedAt` | Optional `organizerAgreementAccepted: true` records a timestamp for organizer applications; omission or `false` does not block submission. Host agreement acceptance is separately required for host applications. |
| Tax/KYC delegated to Stripe Express | `convex/stripeActions.ts`, `convex/payoutAccounts.ts` | Connected accounts use Stripe Express onboarding for tax/KYC collection. Counsel must confirm each party's remaining tax and reporting responsibilities. |
| PCI SAQ A via hosted Checkout | `payments:startInstallmentCheckout`, `ticketCheckout:startCheckout` | Card entry occurs in Stripe-hosted Checkout; EarPlug does not collect card details. SAQ A is the intended assessment path; confirm the applicable attestation before launch. |
| Document retention after account deletion | `users:deleteMe`, Clerk deletion handling, `organizationApplications.verificationDocStorageIds` | Account deletion soft-tombstones the user and blanks email without cascading to applications, verification documents, or referenced history. No retention period is encoded for those retained documents; counsel must define it. |
| Review moderation / safety reports | `reviews:hide`, `safety:report`, `safety:listOpen`, `safety:resolve` | Platform admins can hide reviews with a reason and triage/resolve safety reports. Counsel must define the moderation, escalation, and appeal policy. |
| Age restriction is display-only | `ageRequirement` in `convex/schema.ts`, event details UI, `tickets:reserve` | Event age requirements are displayed; there is no age-verification gate. Counsel must decide whether display-only restrictions meet the launch policy. |
| Support contact: none yet | `web/legal/`, legal/support links | No support contact is configured yet. Supply the contact and response/escalation process before publishing the final documents. |
