# EarPlug Convex function contract (FROZEN — v1.6)

Both the Convex backend and the Flutter client are built against this contract.
Changes require updating both workstreams — do not drift silently.

**v1.1 — band media.** The client migrated to `media:*`, which superseded
`videos:*`; the deprecated `videos:*` functions have now been removed.

**v1.2 — reachable history.** `gigs:feed` and `gigs:forBand` both read forward
from `now - 6h`, and venues reached the client only bundled inside the feed. On
prod — where all 14 gigs are migrated past events — that left every gig, every
venue and all 275 RSVPs unreadable by any query. Added `gigs:pastForBand` and
`venues:list`; no existing function changed.

**v1.3 — share links.** Every band carries a `slug`, derived from its name by
`uniqueSlug` and deliberately frozen across renames so a shared link keeps
resolving. `bands:createBand` returns it next to the id and `bands:bySlug`
resolves it back to a band (`earplug.app/<slug>`, and the `join/<slug>` invite
link built on it). `bands:updateProfile` covers the whole profile, not just bio
and links. All of this reached the backend before v1.2 and was never recorded
here.

**v1.4 — the follower-count invariant, stated.** `bands.followerCount` is
`count(follows by band) + count(bandMembers by band)`. Of the three writers
that have touched it, `interactions:toggleFollow`'s ±1 per follow row and the
now-deleted migration's `follows + bandMembers` sum agree; production already
reflects that sum. `bands:createBand` was the exception: its old `1 + invites`
formula counted invite handles even though they are stored strings that never
become members, so a band created with three invites was born three followers
ahead of reality. It now seeds `followerCount: 1` for the single admin member
row it creates. The new `maintenance:recountBandFollowers` reconciler is
therefore a no-op on production. No wire shape changed.

**v1.5 — Clerk synchronization and verified-email repair.** Clerk now delivers
`user.created`, `user.updated` and `user.deleted` to `POST /clerk-webhook` on
the deployment's `.convex.site` host (**not** `.convex.cloud`). `users:ensureUser`
and the webhook use one shared adoption ladder in one mutation transaction, so
adoption may now happen before sign-in without introducing a check/create race.
`user.deleted` is a soft tombstone with no cascade: deleting the row would
leave five tables with dangling user ids and can strand a band's sole admin,
while cascading would have to reimplement counters across unbounded joins and
destroy RSVP history in response to a replayable event. The tombstone blanks
email so a new Clerk identity cannot adopt the dead row. `users.deletedAt` was
added to storage but is deliberately absent from `UserPayload`. Existing-row
email backfills and authoritative updates are collision-guarded in the shared
ladder, webhook and backfill paths; the two deliberate ladder deltas are that
blank-email repair now pays an extra `by_email` read rather than creating a
duplicate, and email fallback excludes tombstones.

**v1.6 — review fixes to Clerk sync.** The optional ms-since-epoch
`users.clerkUpdatedAt` mirrors Clerk's `updated_at` from the last applied
webhook event and now guards authoritative email overwrites in the shared
adoption ladder. An out-of-order or retried older `user.updated` can therefore
no longer replace a newer email already applied; events without a timestamp
retain the prior unguarded behavior. Email-collision refusals are also visible:
`users:syncFromClerk` returns `emailConflict: boolean`, and the webhook log line
appends `email_conflict` when manual resolution is required instead of reading
as ordinary success. `clerkBackfill:listUsersNeedingEmail` now excludes
tombstones whose blank email would otherwise enter the `email == ""` index
range, while `clerkBackfill:applyEmails` reports a `skippedTombstoned` counter.
An all-tombstone page continues the backfill's self-scheduling walk rather than
halting progress. No client-facing wire shape changed.

All function results travel as JSON. Ids are Convex document-id strings (the
Flutter models already use `String` ids). Timestamps are ms-since-epoch numbers
(UTC). Auth = Clerk JWT (template `convex`) attached by the client; queries that
depend on identity return empty/null when unauthenticated (they must NOT throw,
the client subscribes before sign-in); **all mutations throw when unauthenticated**.

## Payload shapes

```jsonc
// GigPayload
{ "_id": "...", "title": "...", "venueId": "...", "price": 0,
  "startsAt": 1785300000000, "doorsTime": "8PM / 9PM",
  // publish accepts the first six; feeds may also return the five legacy keys
  // custom implies a non-null flyerUrl once valid flyStorageId was supplied
  "flyKey": "xerox|riso|marquee|blueprint|sunburst|custom|paper|blue|black|yellow|bluetype",
  // resolved from flyStorageId; null when no custom flyer is stored/live
  "flyerUrl": null,
  "lineup": ["<bandId>"], "genres": ["punk"], "desc": "...",
  "ticketing": "rsvp|external", "externalUrl": null, "cap": "No cap",
  "goingCount": 43, "createdByBand": null }

// VenuePayload
{ "_id": "...", "name": "...", "area": "...", "addr": "...",
  "distSF": "0.8 mi", "distOak": "6.3 mi", "lat": 37.75, "lng": -122.41 }

// BandPayload — one shape everywhere; every key is always present
// slug and linkYt are stored and writable but deliberately NOT on the wire in v1
{ "_id": "...", "name": "...", "genres": ["garage"], "area": "...",
  "colorHex": "#7B8FFF", "initials": "FD", "followerCount": 486, "bio": "...",
  // resolves via imageStorageId when set and live; null otherwise
  "heroUrl": null,
  "linkIg": "@foghorndiet", "linkBc": "foghorndiet.bandcamp.com",
  "pastShows": [{ "title": "...", "meta": "JUL 12" }] }

// MediaPayload
{ "_id": "...", "bandId": "...", "kind": "video|photo",
  // null means the client renders its placeholder tile
  "url": null, "title": "...", "caption": null, "contentType": null,
  "sizeBytes": null,
  // views has no server write path: display-only legacy data; nothing increments it
  // views/lengthSec are null unless kind is video and the value is set
  "views": null, "lengthSec": null, "pinned": false, "order": 0,
  "isHero": false }

// UserPayload
{ "_id": "...", "clerkId": "user_...", "name": "Sam Reyes",
  "email": "sam@example.com", "genres": ["punk"], "attendedCount": 12,
  // users.deletedAt is an internal tombstone and is deliberately not exposed
  // the row's _creationTime, surfaced under a stable name
  "createdAt": 1785300000000 }
```

## Queries (client subscribes to the ★ ones)

| Function | Args | Returns |
|---|---|---|
| ★ `gigs:feed` | `{}` | `{ gigs: GigPayload[], venues: VenuePayload[], bands: BandPayload[] }` — all gigs with `startsAt >= now - 6h`, ascending, plus every venue/band they reference. Public. Bounded to the 200 nearest upcoming gigs. |
| `gigs:forBand` | `{ bandId }` | `GigPayload[]` upcoming gigs whose lineup contains bandId, ascending. Filtered out of the same 200-gig forward window as `gigs:feed`. |
| `gigs:pastForBand` | `{ bandId }` | `{ gigs: GigPayload[], venues: VenuePayload[] }` — past gigs whose lineup contains bandId, **descending**, plus the venues they reference. Public. Reads the 200 most recent past gigs **globally** and then filters by lineup, so a band whose shows fall outside that window returns empty — the same trap `gigs:forBand` carries forward. |
| `venues:list` | `{}` | `VenuePayload[]` — every venue, name-ascending, capped at 500. Public. |
| `bands:get` | `{ bandId }` | `BandPayload` (full) or `null` |
| `bands:search` | `{ q: string }` | `BandPayload[]` — name search-index match; `q: ""` → all bands (capped 50) |
| `bands:bySlug` | `{ slug: string }` | `BandPayload` (full) or `null` — resolves a shared profile link. Public. Duplicate slugs degrade to the older band rather than throwing. |
| ★ `bands:myBands` | `{}` | `[{ band: BandPayload, role: "admin"\|"member" }]`; `[]` unauth. Capped at 100 memberships. |
| `media:forBand` | `{ bandId }` | `MediaPayload[]` — public; one list across both kinds, ordered by `order` asc |
| `users:me` | `{}` | `UserPayload \| null` |
| ★ `interactions:myInteractions` | `{}` | `{ rsvpGigIds: string[], followBandIds: string[], savedGigIds: string[], attendedCount: number }`; empty/0 unauth |
| `interactions:history` | `{}` | `[{ title: string, venueName: string, startsAt: number }]` — gigs the user RSVPed to with `startsAt < now`, newest first; `[]` unauth. Display string ("title — venue", "SAT JUL 5") derived client-side. |

## Mutations

| Function | Args | Returns | Notes |
|---|---|---|---|
| `users:ensureUser` | `{ name?: string }` | `{ userId }` | Thin authenticated adapter over the shared Clerk adoption ladder, keyed on `identity.subject`. Falls back to adopting a live legacy row by `identity.email` — but **only** when `identity.emailVerified` is true **and** exactly one row carries that address, so an unverified sign-up cannot claim a migrated account and the known duplicate-email rows are left alone. Empty-email repair refuses collisions. Called by the client right after sign-in, but `user.created` can now run the same adoption before any sign-in. |
| `users:setGenres` | `{ genres: string[] }` | `null` | |
| `interactions:toggleRsvp` | `{ gigId }` | `{ on: boolean }` | Insert/delete join row via by_user_gig index; `goingCount` ±1 same transaction. |
| `interactions:toggleFollow` | `{ bandId }` | `{ on: boolean }` | `followerCount` ±1 same transaction. |
| `interactions:toggleSave` | `{ gigId }` | `{ on: boolean }` | |
| `bands:createBand` | `{ name, genres: string[], bio, inviteHandles: string[], area?, linkIg?, linkBc?, linkYt? }` | `{ bandId, slug }` | Inserts band (colorHex/initials/slug computed server-side; `area` defaults to "Bay Area"; `followerCount = 1` — the single admin `bandMembers` row this insert is always followed by, per the v1.4 invariant; invites are stored/ignored for v1 and are deliberately not counted). |
| `bands:updateProfile` | `{ bandId, name?, genres?, area?, bio?, inviteHandles?, linkIg?, linkBc?, linkYt? }` | `null` | requireBandAdmin. Only the keys supplied are patched. A rename recomputes `initials` but deliberately NOT `slug` (shared links keep resolving) or `colorHex` (the band's visual identity in the feed). |
| `gigs:publishGig` | `{ bandId, title, startsAt, doorsTime, venueId, price: number, flyKey: "xerox"\|"riso"\|"marquee"\|"blueprint"\|"sunburst"\|"custom", ticketing, externalUrl?, cap }` | `{ gigId }` | requireBandAdmin(bandId); flyKey client-chosen from the six listed literals; `ticketing === "external"` requires a valid http(s) `externalUrl`; `externalUrl` is dropped for `ticketing === "rsvp"`; `startsAt`/`price` must be finite and non-negative and the venue must exist. `lineup` is `[bandId]`, `genres` are copied from the band, `desc` starts empty, `createdByBand = bandId`, goingCount 0. |
| ↳ v1.1 args/rules for `gigs:publishGig` | Adds `flyStorageId?` to the args above | `{ gigId }` | `flyKey === "custom"` requires a live `flyStorageId` or throws. A non-`"custom"` flyKey silently drops any supplied `flyStorageId`; nothing is stored. |
| `media:generateUploadUrl` | `{ bandId }` | upload URL string | requireBandAdmin(bandId) and nothing else — the 50-row cap is NOT checked here, because this URL also uploads gig flyers. `media:addMedia` is the only place the cap is enforced. |
| `media:addMedia` | `{ bandId, kind: "video"\|"photo", storageId, title, caption?, lengthSec? }` | `{ mediaId }` | requireBandAdmin(bandId); requires a live, acceptable, non-duplicate upload and room under the 50-row per-band cap. Ordering is appended **globally** — `max(order) + 1` across both kinds, one list per band, not one per kind. The first video auto-pins. |
| `media:deleteMedia` | `{ mediaId }` | `null` | requireBandAdmin of the media's band; deletes the row only — the blob stays and is reclaimed later by `media:sweepOrphanBlobs`, so a shared or missing blob can never wedge row deletion. Repacks the band's whole order to 0..n-1, clears the hero reference when applicable, and promotes the next video when the pinned one is deleted. |
| `media:pinMedia` | `{ mediaId }` | `null` | requireBandAdmin of the media's band; video only; unpins siblings. |
| `media:moveMedia` | `{ mediaId, direction: "up"\|"down" }` | `null` | requireBandAdmin of the media's band; swaps `order` with the adjacent row in the band's single global list, which may be of the other kind; no-op at ends. |
| `bands:setBandPhoto` | `{ bandId, mediaId }` | `null` | requireBandAdmin(bandId); media must be a photo belonging to that band. |
| `bands:clearBandPhoto` | `{ bandId }` | `null` | requireBandAdmin(bandId); clears `imageStorageId` without deleting the blob. |

## HTTP endpoints

| Method and path | Host | Behavior |
|---|---|---|
| `POST /clerk-webhook` | The deployment's `.convex.site` URL, **not** `.convex.cloud` | Verifies the Svix signature with that deployment's `CLERK_WEBHOOK_SECRET`. `user.created` and `user.updated` flatten a validated Clerk user into the shared adoption mutation; `user.deleted` soft-tombstones by Clerk id. Other valid event types return 200 and write nothing. Verification/payload failures return 400; missing configuration or mutation failures return 500 so Svix retries. Operations are idempotent by Clerk id; `svix-id` is logged for traceability rather than stored in an unbounded dedupe table. |

## Limits

- `MAX_MEDIA_PER_BAND = 50` — also the `.take()` bound on every `bandMedia`
  read, so "the whole ordered list fits in one read" holds by construction.
- `MAX_MEDIA_BYTES = 100 MiB`.
- Titles ≤ 200 chars, captions ≤ 500. `lengthSec` is video-only and ≤ 4 hours.
- Photo content types: `image/jpeg`, `image/png`, `image/webp`, `image/heic`,
  `image/heif`.
- Video content types: `video/mp4`, `video/quicktime`, `video/webm`.
- Size and content type are enforced after upload by `media:addMedia`. The
  direct-POST URL from `media:generateUploadUrl` bypasses mutation-level
  validation, so clients **must** pre-check file size and type before uploading.

## Invariants

- `bands.followerCount == count(follows by bandId) + count(bandMembers by
  bandId)`. Its permitted live writers are `interactions:toggleFollow` (±1 with
  its follow row) and `bands:createBand` (seeds 1 with its admin member row).
  `maintenance:recountBandFollowers` checks and can repair drift.
  `convex/seed.ts`, however, writes decorative follower counts (486, 1214, 743,
  312, 927, 158) without creating any `follows` or `bandMembers` rows, so every
  seeded band intentionally violates the invariant. On a seeded dev deployment
  the reconciler reports every band as drift, and a non-dry run zeroes those
  counts; non-dry runs are therefore for production or unseeded data only.
- `gigs.goingCount == count(gigRsvps by gigId)`. Its writers are
  `interactions:toggleRsvp` (±1 with its RSVP row) and every gig insert, which
  seeds it to 0.
- `bands.pastShows` is a hand-derived summary with no live writer. No gig
  mutation maintains it, so it is not synchronized automatically.

## Client-side derivations (NOT server concerns)

- `GigWhen` tonight/week/later, `dateShort` ("TUE JUL 28"), `dateLine`
  ("TONIGHT · DOORS 8PM") — derived from `startsAt` + `doorsTime` in Dart.
- Flyer colors from `flyKey` via the existing client const map.
- `Color` from `colorHex`; video display strings ("12.4K views", "2:41") from numbers.
- Feed filters (city/tonight/week/free/genre) — client-side over the feed payload.

## Internal (not called by client)

- `users:syncFromClerk` internalMutation — the webhook's single write entry
  point for a flattened, validated Clerk identity. Runs the same adoption
  ladder as `users:ensureUser`; `user.updated` makes a non-empty, non-colliding
  email authoritative while preserving a non-empty stored name.
- `users:markDeletedFromClerk` internalMutation — soft-tombstones a row by
  Clerk id and blanks its email. It deliberately leaves follows, memberships,
  RSVPs, saves, media attribution and denormalized counters untouched.
- `clerkBackfill:backfillEmails` internalAction — dry-run by default; processes
  one batch per invocation and self-schedules by monotonic creation time. It
  writes only Clerk-verified primary addresses and never an address another
  row already holds.
- `clerkBackfill:listUsersNeedingEmail` internalQuery — reads only the
  `by_email` range for `email == ""`, after a supplied creation-time boundary.
- `clerkBackfill:applyEmails` internalMutation — rechecks missing/filled/
  tombstoned rows and email collisions inside the write transaction, including
  collisions introduced earlier in the same batch.

- `seed:seedDemo` internalMutation — **test fixture only, never run it against a
  real deployment.** Its idempotency marker is a venue named "The Foghorn Club",
  which prod does not have, so on prod it is not idempotent: it inserts fake
  bands and gigs into the live feed, and the purger that could undo that was
  deleted with `convex/cleanup.ts`. A port of lib/demo_data.dart; startsAt is
  computed relative to run date so one gig is "tonight".
- `media:sweepOrphanBlobs` internalMutation — dry-run by default; scheduled by
  `convex/crons.ts` every 24 hours with `{ dryRun: false }`. Also the only
  thing that deletes blobs: it aborts rather than guess when any reference
  table hits its 2000-row read guard.
- `maintenance:recountBandFollowers` internalMutation — dry-run by default with
  an optional `bandId` scope. It recomputes counts from the `by_band` indexes on
  `follows` and `bandMembers`, reports each before/after in `changes`, and is
  idempotent when run live twice. It is NOT scheduled by crons. An unscoped
  band read that hits its cap aborts the whole run; a per-band join read that
  hits its cap skips that band without writing.
- `maintenance:publishRealGig` internalMutation — dry-run by default and takes
  the same args as `gigs:publishGig` through the shared validators/helpers in
  `convex/lib/helpers.ts`, minus the `requireBandAdmin` check. It deduplicates
  `(title, startsAt, venueId)` through the `by_title` index and takes real
  operator-supplied gig details. It is not a seeder and shares nothing with
  `seed:seedDemo`.
- The one-shot legacy migrations are gone. `convex/migrations.ts` and
  `convex/cleanup.ts` were deleted after their runs, per the established
  one-shot lifecycle; both deployments now run the tight v1 schema, and prod
  (`decisive-iguana-759`) holds the real user base. The mapping, the outcome
  and the commits to recover the code from are in
  [docs/history/legacy-mapping.md](history/legacy-mapping.md).
