# EarPlug Convex function contract (FROZEN — v1)

Both the Convex backend and the Flutter client are built against this contract.
Changes require updating both workstreams — do not drift silently.

**v1.1 — band media.** The client migrated to `media:*`, which superseded
`videos:*`; the deprecated `videos:*` functions have now been removed.

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

// BandPayload (summary and full are the same shape; summary MAY omit linkIg/linkBc/pastShows)
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
  "email": "sam@example.com", "genres": ["punk"], "attendedCount": 12 }
```

## Queries (client subscribes to the ★ ones)

| Function | Args | Returns |
|---|---|---|
| ★ `gigs:feed` | `{}` | `{ gigs: GigPayload[], venues: VenuePayload[], bands: BandPayload[] }` — all gigs with `startsAt >= now - 6h`, ascending, plus every venue/band they reference. Public. |
| `gigs:forBand` | `{ bandId }` | `GigPayload[]` upcoming gigs whose lineup contains bandId, ascending |
| `bands:get` | `{ bandId }` | `BandPayload` (full) or `null` |
| `bands:search` | `{ q: string }` | `BandPayload[]` — name search-index match; `q: ""` → all bands (capped 50) |
| ★ `bands:myBands` | `{}` | `[{ band: BandPayload, role: "admin"\|"member" }]`; `[]` unauth |
| `media:forBand` | `{ bandId }` | `MediaPayload[]` — public; ordered by `order` asc |
| `users:me` | `{}` | `UserPayload \| null` |
| ★ `interactions:myInteractions` | `{}` | `{ rsvpGigIds: string[], followBandIds: string[], savedGigIds: string[], attendedCount: number }`; empty/0 unauth |
| `interactions:history` | `{}` | `[{ title: string, venueName: string, startsAt: number }]` — gigs the user RSVPed to with `startsAt < now`, newest first; `[]` unauth. Display string ("title — venue", "SAT JUL 5") derived client-side. |

## Mutations

| Function | Args | Returns | Notes |
|---|---|---|---|
| `users:ensureUser` | `{ name?: string }` | `{ userId }` | Idempotent upsert keyed on `identity.subject`; adopts a legacy row matching `identity.email` (sets its clerkId). Called by the client right after sign-in. |
| `users:setGenres` | `{ genres: string[] }` | `null` | |
| `interactions:toggleRsvp` | `{ gigId }` | `{ on: boolean }` | Insert/delete join row via by_user_gig index; `goingCount` ±1 same transaction. |
| `interactions:toggleFollow` | `{ bandId }` | `{ on: boolean }` | `followerCount` ±1 same transaction. |
| `interactions:toggleSave` | `{ gigId }` | `{ on: boolean }` | |
| `bands:createBand` | `{ name, genres: string[], bio, inviteHandles: string[] }` | `{ bandId }` | Inserts band (colorHex/initials computed server-side; followerCount = 1 + invites) + admin bandMembers row for caller. Invites stored/ignored for v1 (no user linking yet). |
| `bands:updateProfile` | `{ bandId, bio?, linkIg?, linkBc? }` | `null` | requireBandAdmin |
| `gigs:publishGig` | `{ bandId, title, startsAt, doorsTime, venueId, price: number, flyKey: "xerox"\|"riso"\|"marquee"\|"blueprint"\|"sunburst"\|"custom", ticketing, externalUrl?, cap }` | `{ gigId }` | requireBandAdmin(bandId); flyKey client-chosen from the six listed literals; `ticketing === "external"` requires a valid http(s) `externalUrl`; `externalUrl` is dropped for `ticketing === "rsvp"`; goingCount 0. |
| ↳ v1.1 args/rules for `gigs:publishGig` | Adds `flyStorageId?` to the args above | `{ gigId }` | `flyKey === "custom"` requires a live `flyStorageId` or throws. A non-`"custom"` flyKey silently drops any supplied `flyStorageId`; nothing is stored. |
| `media:generateUploadUrl` | `{ bandId }` | upload URL string | requireBandAdmin(bandId); throws when the band already has 50 media rows. |
| `media:addMedia` | `{ bandId, kind: "video"\|"photo", storageId, title, caption?, lengthSec? }` | `{ mediaId }` | requireBandAdmin(bandId); requires a live, acceptable, non-duplicate upload and room under the per-band cap. Ordering is appended within `kind`; the first video auto-pins. |
| `media:deleteMedia` | `{ mediaId }` | `null` | requireBandAdmin of the media's band; deletes the blob and row, repacks that kind's order, clears the hero reference when applicable, and promotes a video when the pinned one is deleted. |
| `media:pinMedia` | `{ mediaId }` | `null` | requireBandAdmin of the media's band; video only; unpins siblings. |
| `media:moveMedia` | `{ mediaId, direction: "up"\|"down" }` | `null` | requireBandAdmin of the media's band; swaps order with the adjacent row of the same kind; no-op at ends. |
| `bands:setBandPhoto` | `{ bandId, mediaId }` | `null` | requireBandAdmin(bandId); media must be a photo belonging to that band. |
| `bands:clearBandPhoto` | `{ bandId }` | `null` | requireBandAdmin(bandId); clears `imageStorageId` without deleting the blob. |

## Limits

- `MAX_MEDIA_PER_BAND = 50`.
- `MAX_MEDIA_BYTES = 100 MiB`.
- Photo content types: `image/jpeg`, `image/png`, `image/webp`, `image/heic`,
  `image/heif`.
- Video content types: `video/mp4`, `video/quicktime`, `video/webm`.
- Size and content type are enforced after upload by `media:addMedia`. The
  direct-POST URL from `media:generateUploadUrl` bypasses mutation-level
  validation, so clients **must** pre-check file size and type before uploading.

## Client-side derivations (NOT server concerns)

- `GigWhen` tonight/week/later, `dateShort` ("TUE JUL 28"), `dateLine`
  ("TONIGHT · DOORS 8PM") — derived from `startsAt` + `doorsTime` in Dart.
- Flyer colors from `flyKey` via the existing client const map.
- `Color` from `colorHex`; video display strings ("12.4K views", "2:41") from numbers.
- Feed filters (city/tonight/week/free/genre) — client-side over the feed payload.

## Internal (not called by client)

- `seed:seedDemo` internalMutation — idempotent demo venues/bands/gigs port of
  lib/demo_data.dart; startsAt computed relative to run date so one gig is "tonight".
- `migrations:migrateUsers` / `migrations:migrateBands` internalMutations — written
  only after the legacy-schema mapping checkpoint.
- `media:sweepOrphanBlobs` internalMutation — dry-run by default; scheduled by
  `convex/crons.ts` every 24 hours with `{ dryRun: false }`.
- `migrations:migrateVideosToBandMedia`,
  `migrations:backfillLegacyPhotos`, `migrations:purgeVideosTable`, and
  `migrations:clearLegacyBandImageFields` were run against dev, and
  `convex/migrations.ts` has now been deleted. The entries remain recoverable
  from git history, following the established one-shot migration lifecycle.
- Prod (`decisive-iguana-759`) was migrated to this contract on 2026-07-30 via
  `migrations:migrateAll` + `migrations:purgeLegacy` (one-shot, deleted after
  the run — recoverable from git history like the dev migration). Both
  deployments now run the tight v1 schema; prod holds the real user base
  (287 users, 11 bands, 14 past gigs and their RSVP history).
