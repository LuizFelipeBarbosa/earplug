# EarPlug

A live-music app for the Bay Area. Fans get a feed of upcoming gigs — venue,
door time, price, lineup, flyer — and can RSVP, save a gig for later, follow
bands, and browse venues on a map. Bands get the other half: create a band
profile, publish gigs to the same feed, keep an ordered photo/video gallery,
and read a past-events recap whose fan breakdowns are withheld server-side
below a 5-fan privacy floor.

One Flutter codebase ships web, iOS and Android. Only the auth service differs
per platform; every screen, model and repository is shared.

## Stack

| | |
|---|---|
| Client | Flutter (`lib/`) — web, iOS, Android |
| Backend | [Convex](https://convex.dev) (`convex/`) — schema, queries, mutations, crons |
| Auth | [Clerk](https://clerk.com) — Clerk JWT (template `convex`) verified by Convex |
| Web hosting | Netlify (`netlify.toml`) — builds `build/web` |

The client never talks to a database directly. Every read and write goes
through a Convex function, and the exact set of functions, their arguments and
their payload shapes are frozen in **[`docs/backend-contract.md`](docs/backend-contract.md)**.
Both sides are built against that document; changing one without the other is
the failure mode it exists to prevent.

`lib/data/repository.dart` is the seam: `ConvexRepository` talks to the real
backend, `DemoRepository` serves the offline fixtures in `lib/demo_data.dart`.

## Running it

```sh
flutter pub get
npm install                       # Convex CLI + test toolchain

npx convex dev                    # backend, in its own terminal
flutter run --dart-define-from-file=config/dev.json
```

`config/dev.json` supplies the Convex URL and the Clerk publishable key
together — see [Environments](#environments). Without them the app refuses to
start and says why (`Env.configurationError` in `lib/env.dart`).

No backend, no Clerk account, just the UI:

```sh
flutter run --dart-define=EARPLUG_DEMO=true
```

## Environments

There are two: development and production. A Convex deployment and a Clerk
instance are chosen **together, never independently** — each deployment trusts
exactly one Clerk issuer, so a mismatched pair signs in successfully and then
reads nothing.

**[`docs/environments.md`](docs/environments.md) is the canonical reference** for
which deployment pairs with which Clerk instance, how the two `config/*.json`
files are consumed by every build target, how Netlify picks one, and what still
needs credentials (native Google and Apple sign-in). Read it before changing
any of it.

## Tests

```sh
flutter test        # Dart: widget and controller tests in test/
npm test            # Convex suites + release-contract unit tests
```

Production Netlify builds deploy Convex and verify the client-required function
contract before compiling Flutter. Native releases and local test runs remain
manual; see [`docs/environments.md`](docs/environments.md#building) for the
release sequence and required credentials.

## Docs

- [`docs/backend-contract.md`](docs/backend-contract.md) — the frozen v1
  function contract between client and backend.
- [`docs/environments.md`](docs/environments.md) — deployments, Clerk pairing,
  build commands, outstanding native credentials.
- [`config/README.md`](config/README.md) — why the build config is committed.
- [`docs/history/`](docs/history/) — post-mortems. Not current design.
