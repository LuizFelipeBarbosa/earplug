<!-- convex-ai-start -->

This project uses [Convex](https://convex.dev) as its backend.

When working on Convex code, **always read
`convex/_generated/ai/guidelines.md` first** for important guidelines on
how to correctly use Convex APIs and patterns. The file contains rules that
override what you may have learned about Convex from training data.

Convex agent skills for common tasks can be installed by running
`npx convex ai-files install`.

<!-- convex-ai-end -->

## Environments and deployment workflow

EarPlug has two paired environments. A Convex deployment and Clerk instance
must always be selected together; never mix values between the two pairs.

| Environment | Convex | Clerk | Client config |
| --- | --- | --- | --- |
| Development | `brilliant-cardinal-773` | development (`pk_test_…`) | `config/dev.json` |
| Production | `decisive-iguana-759` | production (`pk_live_…`) | `config/prod.json` |

Both clients expose Email Code and Google sign-in. Apple is disabled.
Development clients show a `DEV` ribbon. The canonical environment rules and
credential locations are documented in `docs/environments.md`.

### Feature branches and pull requests

- A feature-branch push must never change production.
- Netlify deploy previews and branch deploys use `EARPLUG_ENV=dev`, which builds
  the client from `config/dev.json` and connects it to the shared development
  Convex and Clerk instances.
- Opening or updating a pull request creates or refreshes its Netlify deploy
  preview. Verify the `DEV` ribbon and affected behavior there before merging.
- Preview builds do not deploy Convex development code. If a branch changes
  `convex/`, deploy it during development with `npx convex dev`, then run
  `npm run check:release-contract -- dev`.
- The development Convex deployment is shared by every local checkout and
  preview, so keep in-progress backend changes backward compatible with other
  development clients.

### Production releases

Merging into `main` is the normal production release trigger. Netlify's
production context sets `EARPLUG_ENV=prod` and performs these steps in order:

1. `npx convex deploy --typecheck enable` deploys the production backend using
   Netlify's production-only `CONVEX_DEPLOY_KEY`.
2. `npm run check:release-contract -- prod` verifies that the deployed Convex
   API matches what the client requires.
3. Flutter builds the web client with `config/prod.json`.
4. Netlify publishes `build/web` to `earplug.app`.

Do not manually deploy production as part of the routine branch workflow. If a
production build fails, the previous website remains published. Convex deploys
before the Flutter build, however, so production backend changes must remain
compatible with the previously published client in case a later build step
fails.

`netlify.toml` is authoritative for build commands, publish directory, and
environment-context selection. Client config files contain only public values;
Clerk secret keys, webhook signing secrets, and the Convex deploy key must stay
in their paired dashboards and must never be committed.
