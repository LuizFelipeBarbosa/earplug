# Environments and build configuration

Three build targets — web, iOS, Android — from one Flutter codebase. Only the
auth service differs by platform (`lib/services/auth_service_factory.dart`
switches on `dart.library.js_interop`); every screen, model and repository is
shared.

## Two environments, paired

A Convex deployment and a Clerk instance are chosen **together**. Each
deployment trusts exactly one issuer via `CLERK_JWT_ISSUER_DOMAIN`, read in
`convex/auth.config.ts`, so a client holding the other instance's key signs in
successfully and then reads nothing — indistinguishable from deleted data.

| | development | production |
|---|---|---|
| Convex | `brilliant-cardinal-773` | `decisive-iguana-759` |
| Clerk issuer | `premium-sheep-24.clerk.accounts.dev` | `clerk.earplug.dev` |
| Publishable key | `pk_test_…` | `pk_live_…` |
| Config file | `config/dev.json` | `config/prod.json` |

`Env.configurationError` (`lib/env.dart`) refuses to start on a mismatched
pair, naming both sides. Non-production builds carry a `DEV` corner ribbon.

## Building

```sh
flutter run                        --dart-define-from-file=config/dev.json
flutter build web       --release  --dart-define-from-file=config/prod.json
flutter build ipa       --release  --dart-define-from-file=config/prod.json
flutter build appbundle --release  --dart-define-from-file=config/prod.json
```

Netlify uses the same mechanism — its build command reads
`config/${EARPLUG_ENV}.json`, and `EARPLUG_ENV` is the only environment
variable the web build still consumes.

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

- No CI. There is no workflow building, signing or shipping any platform;
  every build is run by hand.
- `ios/Flutter/Generated.xcconfig` is a local `flutter run` artifact and is not
  tracked. It is not a config source — treat anything in it as scratch.
