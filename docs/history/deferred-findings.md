# Deferred findings — quality audit, 2026-07-31

An audit of the whole repo produced these. They are **real but deliberately not
fixed** in the cleanup that produced this file, because each one changes
behaviour, touches production data, or crosses a boundary that wants its own
reviewed change. Nothing here is speculative — every item was verified against
the source.

The cleanup itself is the commit range `ce60ae8..a662455` on `chore/slop-cleanup`.

---

## Correctness

**`Date.now()` inside queries** — `convex/gigs.ts` (`feedCutoff`) and
`convex/interactions.ts` (`history`). A query's result is cached until something
writes to the range it read, so on a quiet deployment a gig can linger past the
6h grace window. The intended fix is a cron heartbeat writing the current hour's
cutoff to a singleton document that these read instead of the clock. Changing it
alters reactivity and caching semantics, so it is not a cleanup edit.

**The past/upcoming boundary disagrees between modules.** `gigs:*` splits at
`now − FEED_GRACE_MS` (6h); `interactions:history` splits at raw `now`. A gig
that started two hours ago is simultaneously upcoming in `gigs:feed` and
attended in `interactions:history`.

**`gigs:pastForBand` and `gigs:forBand` bound globally, then filter by band.**
Both read the 200 nearest gigs across the whole deployment and filter for the
band afterwards, so a band whose shows fall outside that window gets an empty
history or an empty upcoming list. Harmless at current data volume; a
silent-empty bug at scale. Now documented in `backend-contract.md`.

**`bands:updateProfile` cannot clear a field.** `undefined` means "leave alone",
so `linkIg`/`linkBc`/`linkYt` can be set but never unset.

**`slug` and `linkYt` are write-only.** `bandPayloadValidator` returns neither,
but `createBand`/`updateProfile` accept `linkYt` and every band has a `slug`. A
client that sets a YouTube link can never read it back.

**`notifyListeners()` after `await` on a possibly-disposed `AppState`** —
`_refreshHistory`, `_refreshProfile`, `_refreshExploreBands`, the optimistic
toggles, and `_persistBandField`. Wants a `_disposed` flag applied uniformly.

## Security

**Existence oracle in `convex/media.ts`.** `mediaForAdmin` loads the row before
authorizing, so a non-admin can distinguish a real `mediaId` from a fake one by
which error returns. `bands:setBandPhoto` already authorizes first, so the
codebase is inconsistent. The fix changes the error every caller sees and the
tests asserting them.

**`identity.subject` used as the identity key** — `convex/lib/helpers.ts`,
`convex/users.ts`, and the `by_clerk_id` index. The Convex guidelines prefer
`identity.tokenIdentifier` and call out `subject` by name. Safe today because
there is exactly one Clerk provider; changing it is an auth migration against
production identities.

**`media:forBand` is fully public** and returns signed storage URLs to anonymous
callers. Intentional and documented — listed here so it stays a decision rather
than an accident.

## Schema — needs widen-migrate-narrow, not deletion

These four look like dead weight and are not. Each is deliberately wide so
migrated **production** rows stay readable; narrowing any is a live-data outage.

- `legacySocialLinks` — zero readers, but holds the only surviving copy of
  migrated social links.
- `flyKey: v.string()` — `flyKeyValidator` already narrows on write; the column
  stays wide so gigs carrying the five legacy keys still read.
- `avatarUrl` / `avatarStorageId` — no reader and no writer. The only genuine
  removal candidate here, and only after confirming no migrated user carries
  them.
- `views` — never incremented; documented as display-only legacy data.

## Cross-boundary

**`moveBandMedia(String direction)` is stringly typed** — `'up'`/`'down'`, with
an unreachable silent-no-op arm in `DemoRepository`. An enum removes both, but
the change spans the repository interface, both implementations, the Convex
mutation and two test suites, so it needs its own solo wave.

**`DemoData.flyers` / `flyerPicks` are real design tokens living in a demo
fixture.** `app_state.dart` and `gig_create.dart` both read them, which keeps the
539-line fixture file reachable from production code. Moving them to
`theme.dart` is a design decision about where flyer tokens belong.

## Considered and deliberately rejected

Recorded so they are not "found" again:

- **`bands:bySlug` is not dead.** It resolves the `earplug.app/join/<slug>` link
  `band_create.dart` copies to the clipboard. `gigs:forBand` has no Flutter
  caller but is published contract surface.
- **The Convex tests do not need `import.meta.glob` module maps.** `convex-test`
  self-discovers via a default glob and `vitest.config.ts` inlines the dep so
  Vite transforms it.
- **The "is public — an anonymous visitor can read X" tests are not trivial.**
  `convexTest()` without `withIdentity` is anonymous; they are the
  auth-regression coverage for queries that declare publicness as contract.
- **The wizard forms should stay on `AppState`.** The sheet bodies are pushed as
  separate Navigator routes and read `context.watch<AppState>()`, so
  screen-local `State` is unreachable from them.
- **band-create and gig-create should not share their art.** The cassette and
  the flyer are deliberately divergent; only the mechanical chrome was shared.
- **`venuePayloadValidator` and its identity converter are not duplication.** A
  wire contract that must not move when the table moves is the correct pattern.
- **`FakeAuthService`'s hardcoded `'424242'` is not a hole.** The app uses the
  real Clerk service, and `FakeAuthService.fetchConvexToken()` returns `null`,
  so every mutation would throw regardless.

## Housekeeping

`backups/*.zip` — 260MB of post-migration snapshots sitting in the working
directory. Correctly gitignored, both migrations they guard completed and were
verified. Safe to move off-disk whenever you want the space.

## Addendum — PR #6 review, 2026-08-05

**The analytics anonymity floor is now server-side.** `convex/analytics.ts`
applies `partitionMeetsFloor` at `K_ANON_FANS = 5` to every fan breakdown. It
suppresses the entire partition rather than an individual bucket because each
breakdown partitions a published total: if every bucket but one remained
visible, the withheld bucket would be recoverable by complement. Zero-fan
buckets do not trigger suppression and remain publishable because an empty
bucket identifies nobody.

Two honest gaps remain. Fan geography was dropped outright, not deferred: no
user location field exists in the schema, so it was removed from the UI copy
rather than gated. RSVP lead time is a floor, not a truth. Production RSVP rows
were inserted at migration time and therefore postdate the gigs they belong to;
the recap reports those rows as `unmeasurable` instead of inventing a false lead
time. Separately, an un-RSVP followed by a re-RSVP resets `_creationTime`, so
lead time for a fan who does that is measured from the wrong moment.
