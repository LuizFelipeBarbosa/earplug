# Build configuration

One file per environment, consumed identically by web, iOS and Android:

```sh
flutter run                       --dart-define-from-file=config/dev.json
flutter build web     --release   --dart-define-from-file=config/prod.json
flutter build ipa     --release   --dart-define-from-file=config/prod.json
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

Before this existed, web got its values from `netlify.toml` and mobile got
nothing at all — so iOS and Android builds fell back to whatever a local
`flutter run` had left in `ios/Flutter/Generated.xcconfig`, and both OAuth
providers stayed switched off because no build path supplied their variables.

## Why these values are committed

Every key here is public by construction. `CONVEX_URL` is the address browsers
connect to directly; Clerk publishable keys are client-side credentials that
encode nothing but the Frontend API host; Google **client** IDs are public
identifiers (the client *secret* is not, and is not used by this app — native
sign-in exchanges an ID token instead). All of them are readable in any shipped
bundle. Committing them is what makes a build reproducible.

Nothing secret belongs in this directory. `CLERK_SECRET_KEY` lives in the
Convex deployment environment and is read by no client code.

## The pairing rule

A Convex deployment and a Clerk instance are chosen together, never
independently — and these files are the unit in which the pair travels, which is
why the URL and the key live in one file rather than two variables.

**See [`../docs/environments.md`](../docs/environments.md) for the rule, the
deployment/instance table, and why a mismatch is worse than a missing value.**
That document is the only place the pairing is spelled out.

## Native configuration lives elsewhere

`--dart-define-from-file` reaches Dart only. Two things must also be set at the
platform level, and cannot come from these files:

- **iOS Google client ID** — `ios/Config/Google.xcconfig`, referenced by
  `Info.plist` as `$(GOOGLE_IOS_CLIENT_ID)`.
- **Sign in with Apple capability** — `ios/Runner/Runner.entitlements`.

See [`../docs/environments.md`](../docs/environments.md) for the full credential
checklist.
