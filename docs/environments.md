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
independently**. The pairing now governs all three deployment secrets:
`CLERK_JWT_ISSUER_DOMAIN`, `CLERK_WEBHOOK_SECRET` and `CLERK_SECRET_KEY`. Each
deployment trusts exactly one issuer via `CLERK_JWT_ISSUER_DOMAIN`, read in
`convex/auth.config.ts`, so a client holding the other instance's key signs in
successfully and then reads nothing — indistinguishable from deleted data, not
from misconfiguration.

| | development | production |
|---|---|---|
| Convex | `brilliant-cardinal-773` | `decisive-iguana-759` |
| Clerk issuer | `premium-sheep-24.clerk.accounts.dev` | `clerk.earplug.dev` |
| Publishable key | `pk_test_…` | `pk_live_…` |
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
- `CLERK_SECRET_KEY` exists on both deployments and is read by
  `clerkBackfill:backfillEmails`; no client code ever sees it. It must belong
  to the same Clerk instance as the issuer and webhook secret. A `sk_live_`
  key used against dev (or a test key against prod) returns zero matches for
  every id and reports `skippedNotFoundInClerk: 146` with no other symptom —
  indistinguishable from “Clerk has no record of these users”.

## Building

```sh
flutter run                        --dart-define-from-file=config/dev.json
flutter build web       --release  --dart-define-from-file=config/prod.json
flutter build ipa       --release  --dart-define-from-file=config/prod.json
flutter build appbundle --release  --dart-define-from-file=config/prod.json
```

Deploy and verify the production backend before building a client that calls
it:

```sh
npx convex deploy --typecheck enable
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
contract before building Flutter. Without that key, deploy and verify the
backend separately before triggering the production build; Netlify then uses
the already-deployed backend. Development builds do not deploy and can be
checked against the shared development deployment manually with
`npm run check:release-contract -- dev`. `EARPLUG_ENV` remains the only Netlify
environment variable consumed by the web client itself.

## Sign-in parity between web and mobile

| Method | Web | Mobile | Needs credentials |
|---|---|---|---|
| Email code | ✅ | ✅ | no |
| Phone code | ✅ | ✅ | no |
| Google | ✅ | gated | **yes** |
| Apple | ✅ | gated | **yes** |

Web reaches Google and Apple through Clerk's hosted redirect, which needs no
per-app credentials — hence `supportsGoogleSignIn => true`. Mobile uses the
native SDKs (`sign_in_with_apple`, `google_sign_in`), which require real client
IDs, so it hides a provider until that provider is configured. The flows
themselves are fully implemented in `lib/services/clerk_mobile_auth.dart`;
only configuration is outstanding.

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
   `GOOGLE_SERVER_CLIENT_ID` to the *web application* client ID. This is what
   flips `supportsGoogleSignIn` on.
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
   stays hidden on Android regardless: the implementation gates on
   `Platform.isIOS`.

Until these land, mobile offers email and phone codes, which work today and
need no credentials.

## What is not configured anywhere

- Native release automation is not configured; iOS and Android builds, signing,
  and shipping are still run by hand. Netlify is the only automated release
  path and covers the web client plus its production Convex deployment.
- `ios/Flutter/Generated.xcconfig` is a local `flutter run` artifact and is not
  tracked. It is not a config source — treat anything in it as scratch.
