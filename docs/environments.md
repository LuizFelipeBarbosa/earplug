# Environments and build configuration

Three build targets — web, iOS, Android — from one Flutter codebase. Only the
auth service differs by platform (`lib/services/auth_service_factory.dart`
switches on `dart.library.js_interop`); every screen, model and repository is
shared.

## Two environments, paired

**This section is the canonical statement of the pairing rule.** `.env.example`,
`config/README.md` and `netlify.toml` state it in one line and point here; keep
the detail in this file only.

A Convex deployment and a Clerk instance are chosen **together, never
independently**. The pairing governs all three Clerk deployment secrets:
`CLERK_JWT_ISSUER_DOMAIN`, `CLERK_WEBHOOK_SECRET` and `CLERK_SECRET_KEY`. Each
deployment trusts exactly one issuer via `CLERK_JWT_ISSUER_DOMAIN`, read in
`convex/auth.config.ts`, so a client holding the other instance's key signs in
successfully and then reads nothing — indistinguishable from deleted data, not
from misconfiguration.

| | development | production |
|---|---|---|
| Convex | `brilliant-cardinal-773` | `decisive-iguana-759` |
| Clerk issuer | `premium-sheep-24.clerk.accounts.dev` | `clerk.earplug.app` |
| Publishable key | `pk_test_…` | `pk_live_…` |
| Stripe | test mode (`sk_test_…`) | live mode (`sk_live_…`) |
| Config file | `config/dev.json` | `config/prod.json` |

`Env.configurationError` (`lib/env.dart`) refuses to start on a mismatched
pair, naming both sides. Non-production builds carry a `DEV` corner ribbon.
`decisive-iguana-759` is also named literally in `lib/env.dart` as the one
production deployment — if it ever changes, change it there too or the guard
checks the wrong name.

Two facts about the deployment side of the pair, since they are the ones people
look for:

- `CLERK_JWT_ISSUER_DOMAIN` is set per deployment with `npx convex env set`,
  never read from a file in this repo. It decides which Clerk instance a
  deployment trusts.
- `CLERK_WEBHOOK_SECRET` is also set per deployment and belongs to one Clerk
  webhook endpoint/instance. It must pair with the same deployment as the
  issuer domain. Configure the endpoint as `POST /clerk-webhook` on the
  deployment's `.convex.site` host, not `.convex.cloud`.
- `CLERK_SECRET_KEY` exists on both deployments; no client code ever sees it,
  and no Convex function currently reads it (the one-off email backfill that
  did has been removed). It must still belong to the same Clerk instance as
  the issuer and webhook secret.

### Convex marketplace environment variables

Set each of these independently on both paired Convex deployments with
`npx convex env set`, using test/service values for development and live values
for production:

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `STRIPE_CONNECT_WEBHOOK_SECRET`
- `BOOKING_COMMISSION_BPS`
- `TICKETING_FEE_BPS`
- `TICKETING_FEE_FIXED_MINOR` — reserved for Phase 4 (declared, not yet read by any function).
- `APP_BASE_URL`
- `RESEND_API_KEY`
- `RESEND_SEND_ENABLED`
- `PAYMENTS_ENABLED`
- `TICKETS_ENABLED`
- `PRIVATE_BOOKINGS_ENABLED`
- `BAND_GIG_WRITES`

`convex/lib/env.ts` enforces the pairing at runtime: it refuses a `sk_live_`
Stripe key on every deployment except production deployment
`decisive-iguana-759`. The two Stripe webhook HTTP routes, like the Clerk route
above, live on the selected deployment's `.convex.site` host, not its
`.convex.cloud` host.

Configure the platform endpoint as `POST /stripe-webhook` on that
deployment's `.convex.site` host, using `STRIPE_WEBHOOK_SECRET`, and subscribe
it to `checkout.session.completed`, `checkout.session.expired`,
`payment_intent.payment_failed`, `charge.dispute.created`, and
`charge.dispute.closed`. Configure the connected-account endpoint as
`POST /stripe-connect-webhook` on the same host, using
`STRIPE_CONNECT_WEBHOOK_SECRET`, and subscribe it to `account.updated`.

`APP_BASE_URL` must match the deployed client's origin for the selected
environment: the development client's origin for development, and
`https://earplug.app` for production. Checkout and Connect append these paths
to that origin:

- `/checkout/return?session_id={CHECKOUT_SESSION_ID}` — Checkout success return; Stripe substitutes the session id.
- `/checkout/cancel?booking=<bookingId>` — Checkout cancellation return.
- `/band/stripe/return?band=<bandId>` — band Connect onboarding return.
- `/band/stripe/refresh?band=<bandId>` — band Connect onboarding link refresh.
- `/org/stripe/return?org=<organizationId>` — organization Connect onboarding return.
- `/org/stripe/refresh?org=<organizationId>` — organization Connect onboarding link refresh.

A mismatched `APP_BASE_URL` sends these redirects to the wrong environment.
`appBaseUrl()` defaults to `https://earplug.app` when the variable is absent,
so development must set its own client origin explicitly. Development
previews share one Convex deployment and therefore one configured return
origin.

Before setting `PAYMENTS_ENABLED=true`, also set `BOOKING_COMMISSION_BPS`
to the intended commission (an integer from 0 to 10000 basis points) and
enable Stripe Connect on the Stripe account connected to the deployment
through `STRIPE_SECRET_KEY`. Test mode suffices for development. Live mode
requires the platform's Stripe account to have accepted the Connect platform
terms in the Stripe dashboard; this repository does not configure that
dashboard action. The payments flag defaults to false and blocks all
non-`GET` Stripe API calls while disabled.

## Building

```sh
flutter run                        --dart-define-from-file=config/dev.json
flutter build web       --release  --dart-define-from-file=config/prod.json
flutter build ipa       --release  --dart-define-from-file=config/prod.json \
  --dart-define=STADIA_MAPS_API_KEY="$STADIA_MAPS_API_KEY"
flutter build appbundle --release  --dart-define-from-file=config/prod.json \
  --dart-define=STADIA_MAPS_API_KEY="$STADIA_MAPS_API_KEY"
```

Deploy and verify the production backend before building a client that calls
it:

```sh
npx convex deploy --typecheck enable
npm run backfill:release -- --prod
npm run check:release-contract -- prod
flutter build web --release --dart-define-from-file=config/prod.json
```

The contract check reads the exact deployment named by `config/prod.json` and
fails if a client-required Convex function is missing or has the wrong type.
This prevents publishing a new client against an older backend, which otherwise
surfaces as a generic mutation error only after a user clicks the affected UI.

Netlify uses the same config-file mechanism. `netlify.toml` selects production
configuration for production-context builds and development configuration for
deploy previews and branch deploys. When Netlify has a production
`CONVEX_DEPLOY_KEY`, production builds deploy Convex and verify the production
contract before building Flutter. The build does not run the release-backfill
runner itself. Instead, the deployment's own cron ("apply release backfills" in
`convex/crons.ts`) applies the idempotent release backfills within roughly 30
minutes of any deploy, without needing the
`deployment:functions:runInternalMutations` permission that a Netlify deploy key
lacks. `npm run backfill:release -- --prod` remains available to apply them
immediately from an authenticated admin session instead of waiting for the cron.
Without that key, deploy and verify the backend separately before triggering the
production build; Netlify then uses the already-deployed backend.
Development builds do not deploy and can be
checked against the shared development deployment manually with
`npm run check:release-contract -- dev`. `EARPLUG_ENV` remains the only Netlify
environment selector consumed by the web client itself. Netlify intentionally
forwards the optional `STADIA_MAPS_API_KEY` Dart define, baking it into preview
and production web bundles. Netlify supplies the same scoped key to Production,
Deploy Previews and Branch Deploys; every hosted origin that uses it must be
allowed by the Stadia property. Local web development on `localhost` or
`127.0.0.1` is intentionally keyless. The native commands above likewise bake
a scoped key into the shipped bundle; omitting it leaves the app usable and
gives each map a recoverable configuration error.

## Stadia Maps authentication and caching

The client reads `STADIA_MAPS_API_KEY` only as a compile-time Dart define. Any
value passed via `--dart-define` is extractable from the shipped bundle, so this
key is not a secret in the credential sense. It is a scoped, revocable,
monitored client credential comparable to `CLERK_PUBLISHABLE_KEY`; true secrets
such as `CLERK_SECRET_KEY` and `CLERK_WEBHOOK_SECRET` never reach client code.
Use a scoped and rotatable client key for hosted web builds and a separately
scoped key for native releases. Never put a real value in `.env.example`,
`config/*.json`, or source control.

Because the key itself provides no meaningful confidentiality, it **MUST** be
domain/referrer-restricted in the Stadia dashboard for every hosted origin
allowed to use it, in addition to being scoped and rotatable. Register
`earplug.app` in the Stadia property before production release. Domain and
referrer restrictions rely on browser `Origin` and `Referer` headers; verify
those headers on the Netlify preview before promoting the release. The app
caches only visited vector tiles, capped at 50 MB with a seven-day TTL. This is
below Stadia's 100 MB per-device ceiling, but still requires an active plan that
permits caching. No region download or public OSM fallback is configured.

## Sign-in capabilities

Both environment files deliberately expose the same product surface: Email
Code and Google are enabled; Apple is disabled. The three explicit flags are
`EMAIL_SIGN_IN_ENABLED`, `GOOGLE_SIGN_IN_ENABLED`, and `APPLE_SIGN_IN_ENABLED`.

| Method | Environment policy | Web | Mobile |
|---|---|---|---|
| Email code | enabled | shown | shown |
| Google | enabled | shown | hidden until native credentials exist |
| Apple | disabled | hidden | hidden |

The service combines environment policy with platform availability. Web OAuth
uses Clerk's hosted redirect and needs no native client ID. Mobile uses the
native Apple and Google SDKs, so an enabled OAuth method remains hidden until
its required platform credentials are configured. The flows are implemented
in `lib/services/clerk_mobile_auth.dart`; native credentials remain a separate
release task.

Web sign-in preserves the organizer application route (`/org/apply`) or
organization invitation route (`/apply/<token>`) through Clerk's full-page
redirect. Startup restores the destination from that route. Invitations still
require an explicit acceptance after sign-in.

### Checklist — Google

1. **Google Cloud console → APIs & Services → Credentials.**
   - Create an **iOS** OAuth client. Bundle ID `com.earplug.app`. Copy the
     client ID and the *iOS URL scheme* it shows you.
   - Create an **Android** OAuth client. Package `com.earplug.app` plus the
     SHA-1 of the signing key — debug and upload keys are different, so
     register both. Android needs no manifest entry; `google_sign_in` v7 goes
     through Credential Manager.
   - Create a **Web application** OAuth client. Its client ID is the
     `serverClientId` both platforms send to Clerk. This one is *not* for a
     website — it identifies your backend to Google.
2. **`ios/Config/Google.xcconfig`** — set `GOOGLE_IOS_CLIENT_ID` and
   `GOOGLE_IOS_URL_SCHEME` from step 1. `Info.plist` reads them as build
   variables, so nothing is hardcoded in source. While they are empty the built
   `Info.plist` carries an empty `GIDClientID` and one empty entry in
   `CFBundleURLSchemes`; harmless for development, but fill them in before an
   App Store submission rather than shipping an empty scheme.
3. **`config/dev.json` and `config/prod.json`** — set
   `GOOGLE_SERVER_CLIENT_ID` to the *web application* client ID. Google must
   also remain allowed by `GOOGLE_SIGN_IN_ENABLED`; mobile requires both.
4. **Clerk dashboard → SSO connections** — enable Google for both instances,
   and use the same web client ID and its secret so Clerk can verify the ID
   token the app sends.

### Checklist — Apple

1. **Apple Developer → Certificates, Identifiers & Profiles** — enable the
   *Sign in with Apple* capability on the `com.earplug.app` App ID, then
   regenerate the provisioning profile.
2. `ios/Runner/Runner.entitlements` already declares
   `com.apple.developer.applesignin`, and all three Runner build configurations
   reference it. Nothing to change unless the bundle ID moves.
3. **Clerk dashboard → SSO connections** — enable Apple, supply the Services
   ID, Team ID, Key ID and the `.p8` private key.
4. **`config/*.json`** — set `APPLE_SIGN_IN_ENABLED` to `true`. The button
   stays hidden on Android regardless: the implementation also gates on
   `Platform.isIOS`.

Until these credentials land, mobile offers Email Code only. Web offers Email
Code and Google in both environments.

## What is not configured anywhere

- Native release automation is not configured; iOS and Android builds, signing,
  and shipping are still run by hand. Netlify is the only automated release
  path and covers the web client plus its production Convex deployment.
- `ios/Flutter/Generated.xcconfig` is a local `flutter run` artifact and is not
  tracked. It is not a config source — treat anything in it as scratch.
