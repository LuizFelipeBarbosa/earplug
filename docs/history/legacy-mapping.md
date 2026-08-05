# Legacy → v1 data migration — post-mortem

> **STATUS: COMPLETE. This is history, not a plan.**
> Development migrated 2026-07-29, production migrated 2026-07-30. The code
> that performed both migrations has been deleted from the working tree; §R
> below is how to get it back. Nothing in this document describes work that is
> still outstanding, and nothing in it should be used to plan new work — the
> current contract is [`../backend-contract.md`](../backend-contract.md).

Both surviving EarPlug deployments ran the *legacy* app: a much larger product
(booking marketplace, DMs, friends, QR tickets and door check-in, Spotify sync,
event co-hosts) across 141 Convex functions, identical between dev and prod.
The v1 rebuild froze a far smaller contract, so the legacy rows had to be
reshaped in place rather than re-created. Both deployments were migrated
successfully with no data loss beyond what the v1 contract deliberately drops:
prod ended at 287 users / 11 bands / 12 venues / 14 gigs / 275 RSVPs, dev at 33
users / 6 bands / 4 venues / 1 gig / 25 RSVPs, zero dangling references on
either. The only residue is 21 emptied legacy tables that survive as undeclared
empty shells, because removing a table from `schema.ts` does not drop it.

The forward-looking mapping that was written before any of this ran is
preserved verbatim below the divider, as **historical context**.

---

# Part 1 — Outcome

## Production `decisive-iguana-759` — migrated 2026-07-30

Prod held the real user base (see §7 for how that was established while its rows
were still unreadable). It was migrated in place by a prod-specific
`migrations:migrateAll` + `migrations:purgeLegacy`.

Deviations from the dev design below:

- Clerk linkage needed **no email fallback** — 287/287 rows carried unique live-
  instance clerkIds.
- All 14 past events, 275 rsvps, 5 likes and 12 venues **were** migrated (dev
  dropped its equivalents).
- `bandMediaSlots` plus band profile images became 40 `bandMedia` rows.
- `area` is the bare city (`"Berkeley"` / `"Oakland"`), not `"Berkeley, CA"`.
- `followerCount` = savedArtists + memberships.
- Migrated gigs briefly carried a `legacyEventId` for idempotency and purge
  guards; `purgeLegacy` stripped it.

**Final prod state:** 287 users, 11 bands, 12 venues, 14 gigs, 19 bandMembers,
17 follows, 275 gigRsvps, 5 gigSaves, 40 bandMedia. All 54 storage blobs are
referenced (`media:sweepOrphanBlobs` dry run reported `wouldDelete: 0`).

## Development `brilliant-cardinal-773` — migrated 2026-07-29

- **Phase 1** — `migrations:migrateAll` reshaped users/bands/venues in place and
  moved `bandMemberships`→`bandMembers`, `savedArtists`→`follows`,
  `bandMediaSlots`→`videos`, and the launch-night `events` row→`gigs`.
- **Phase 2** — `cleanup:cleanupAll` recovered the 25 launch-night RSVPs still
  stranded in `rsvps`, collapsed 4 duplicate accounts onto 1, and deleted the
  seeded demo content (6 bands / 6 venues / 7 gigs / 5 videos), the `test band`
  and e2e rows, and 124 rows across 11 superseded tables.
- **Then** `schema.ts` dropped the legacy tables and promoted every backfilled
  field to required.

**Final dev state:** 33 users, 6 bands, 4 venues, 1 gig, 25 gigRsvps, 8 follows,
12 bandMembers, 4 videos. Zero dangling references.

The `videos` table was itself later folded into `bandMedia`; see the
`v1.1 — band media` note in [`../backend-contract.md`](../backend-contract.md).

## How the open questions were decided

The mapping below refers to these by number. All are settled.

| | Question | Decision |
|---|---|---|
| **Q0** | dev or prod? | **Both**, in sequence — dev first (prod was left frozen and out of scope until 2026-07-30). |
| **Q1** | empty `email` on 25 dev users | Backfill from the Clerk identity on adoption. |
| **Q2** | avatars / band images with no home in v1 | Keep the storage ids in optional fields; do not sweep. |
| **Q3** | delete the obvious test rows | Yes. |
| **Q4** | `area` format | Dev `"Berkeley, CA"`; prod used the bare city. |
| **Q5** | migrate `savedArtists` → follows | Yes. **Q5b:** park the non-Instagram links in `legacySocialLinks`. |
| **Q6** | `bandMediaSlots` | Map the videos across; keep the band image storage ids. |
| **Q7** | the 4 legacy dev venues | Keep the real ones, drop the demo ones. On prod all 12 venues migrated. |
| **Q8** | port "EARPLUG LAUNCH NIGHT" as a past gig | Yes, ported. |

## §R — Recovering the migration code

Every migration was written as one-shot code and deleted after it ran. The
deletion commits, newest first:

| Commit | Deleted | What it migrated |
|---|---|---|
| `579e2be` | `convex/migrations.ts` (+ test) | Prod `migrateAll` / `purgeLegacy` |
| `d1a271a` | `convex/migrations.ts` (+ test), `convex/videos.ts` | `videos` → `bandMedia`, legacy band photos |
| `4b5c819` | `convex/migrations.ts`, `convex/cleanup.ts` (+ tests) | Dev phase 1 and phase 2 |

Read a file back with the commit's parent, e.g.

```sh
git show 579e2be^:convex/migrations.ts
git show 4b5c819^:convex/cleanup.ts
```

## Known leftover

Removing a table from `schema.ts` does not drop it. The 21 emptied legacy tables
still exist as empty shells on both deployments. They are undeclared,
unreachable from code, and harmless — but deleting them is a dashboard-only
action the CLI cannot perform.

---
---

# Part 2 — Historical context: the mapping as written 2026-07-28

> Everything from here down is the **original forward-looking plan**, kept for
> the record of what the legacy schema contained and how each table was mapped.
> It is written in the future tense and its recommendations and open questions
> have since been superseded by Part 1. Where the two disagree, Part 1 is what
> actually happened.

Discovered 2026-07-28 by read-only inspection (Convex MCP) of the two surviving
EarPlug deployments. Target shapes are the frozen contract in
`docs/backend-contract.md`. PII is masked throughout.

| Deployment | Selector | Access | Verdict |
|---|---|---|---|
| **dev** `brilliant-cardinal-773` | `dev:brilliant-cardinal-773` (the one in `.env.local`) | full | Spring-2026 Berkeley beta dataset. Real people and bands, plus some test rows. **This is what the migration below maps.** |
| **prod** `decisive-iguana-759` | `prod` | read-only (schema + functions only, no rows) | Same app code, same declared schema — but its *inferred* schema shows heavier real usage. See "Prod vs dev" below. |

Both deployments run the **identical last build** of the legacy app: 141 functions,
zero diff between dev and prod. The legacy app was far bigger than the new v1
(booking marketplace, DMs, friends, tickets/check-in, Spotify sync, co-hosts).

---

## 1. Row counts (dev)

| Table | Rows | Migrate? |
|---|---|---|
| `users` | **36** | **yes → reshape in place** |
| `bands` | **7** | **yes → reshape in place** |
| `bandMemberships` | **13** | **yes → `bandMembers`** |
| `savedArtists` | 9 | recommend yes → follow rows (feeds `followerCount`) |
| `eventTickets` | 47 | no — drop |
| `rsvps` | 26 | no — 25 belong to one past event, 0 marked attended |
| `bandProfileEngagements` | 18 | no — analytics, drop |
| `bandInvites` | 9 | no — 7 accepted (already memberships), 2 pending but expired Apr 2026 |
| `bandMediaSlots` | 5 | no direct target — see open question Q6 |
| `venues` | 4 | optional — trivial mapping exists (see §5) |
| `eventCohostInvites` | 4 | no — drop |
| `events` | 3 | no — 1 real past event + 2 test events; contract seeds gigs fresh |
| `notifications` | 1 | no |
| `spotifyProfiles` | 1 | no |
| `applications`, `bandCreationAttempts`, `conversationReads`, `conversations`, `eventCheckinStaff`, `friendships`, `likes`, `messages`, `openDates`, `savedVenues` | 0 each | delete |

Data vintage: users joined ≈ Mar–Apr 2026; the one real event ("EARPLUG LAUNCH
NIGHT", 25 RSVPs) was ≈ Apr 3 2026. No real upcoming events (the only future
`events` row is titled "TEST TEST").

---

## 2. Clerk-linkage analysis (determines `ensureUser` adoption)

Legacy `users` linkage fields, measured on all 36 dev rows:

- **`clerkId`**: present on **36/36**, all format `user_…` (real Clerk user ids),
  **0 duplicates**. Indexed as `by_clerk_id`. This is the linkage field — there is
  no `tokenIdentifier`/`subject` field.
- **`email`**: **only 11/36 non-empty** (25 rows have an empty string — the legacy
  Clerk webhook/upsert didn't always capture it). Domains: 8× gmail.com,
  3× berkeley.edu. **One email appears on 3 different accounts**
  (`l***@gmail.com` — almost certainly the developer's multiple test sign-ups).
- **`phoneNumber`**: 0/36 rows have one (schema field exists, never populated).

Clerk instance check: the dev deployment's env has
`CLERK_JWT_ISSUER_DOMAIN = https://premium-sheep-24.clerk.accounts.dev`
(test instance, `sk_test` key) — and the new app's `.env.local` points at the
**same instance**. Therefore, on dev:

- **`ensureUser` can adopt every one of the 36 rows directly by
  `identity.subject === users.clerkId`.** Match by clerkId FIRST; it is total.
- Email adoption is a fallback only, and must be **unique-match-only**: 25 rows
  are unreachable by email (empty), and the tripled `l***@gmail.com` would make a
  naive email match adopt an arbitrary row.
- **Rows that can never be adopted if the Clerk instance ever changes**: the 25
  empty-email rows (no clerkId match in a new instance, no email to fall back
  on). On the current same-instance plan, zero rows are stranded.
- Prod caveat: prod almost certainly uses a *live* Clerk instance with different
  `user_…` ids; dev clerkIds and prod clerkIds are disjoint populations. Email
  coverage on prod is unknown (no row access).

---

## 3. `users` — field-by-field mapping

Target (`UserPayload` / new `users` table): `clerkId`, `name`, `email`,
`genres: string[]`, `attendedCount: number`.

| Source field | Target field | Transform | Notes / open questions |
|---|---|---|---|
| `clerkId` (string, 36/36, unique) | `clerkId` | **verbatim** | Adoption key. Keep index `by_clerk_id`. |
| `name` (36/36) | `name` | **verbatim** | Real first+last names, e.g. "Luiz B.", "Anandi J." (masked). |
| `email` (11/36 non-empty) | `email` | **verbatim**, but normalize empty string → decide `""` vs `null` | Contract shows `email` as a string. **Q1:** is empty string acceptable, or should `ensureUser` backfill it from the Clerk identity on next sign-in (recommended)? |
| `topGenres` (2/36 set) | `genres` | **rename**; default `[]` when absent | Legacy vocab is a closed union: indie, rock, jazz, electronic, folk, pop, alternative. Contract examples use free strings ("punk"). Carry verbatim. |
| `showsAttended` (all 0/unset) | `attendedCount` | **rename**; default `0` | Cross-check: 0 of 26 rsvps have `attendanceStatus: "attended"` on dev, so 0 is also the recomputed value. |
| `avatar` (35/36, mostly Clerk-hosted URLs) + `avatarStorageId` (3/36) | — | **dropped by contract** | **Q2:** new shape has no avatar. Clerk still serves avatars for these users via its own API; the 3 Convex-storage avatars orphan their `_storage` files if dropped. Recommend leaving both fields in place (schema-optional) until v2 decides. |
| `location` (4/36) | — | drop | |
| `phoneNumber` (0/36) | — | drop | Never populated. |
| `role` ("fan" on 36/36) | — | drop | Legacy fan/musician split never used. |
| `memberSince` | — | drop | ≈ `_creationTime`, which reshaping in place preserves. |

Migration is an in-place `migrations:migrateUsers` patch: add `genres`/
`attendedCount` (widen schema with `v.optional` first, backfill, then tighten),
delete dead fields. `_id` and `_creationTime` survive.

---

## 4. `bands` — field-by-field mapping

Target (`BandPayload` / new `bands` table): `name`, `genres`, `area`, `colorHex`,
`initials`, `followerCount`, `bio`, `linkIg`, `linkBc` (`pastShows` is derived
from gigs at read time, not stored).

| Source field | Target field | Transform | Notes / open questions |
|---|---|---|---|
| `name` (7/7) | `name` | **verbatim** | SOBO, EARPLUG, Circadian Rhythm, TRACKMAGIC, Whalefall, Public School Records, Test Band. **Q3:** delete "Test Band" (and its user/membership/event) during migration? |
| `genres` (array, 7/7) | `genres` | **verbatim** | Legacy singular `genre` field exists in schema but is unset on all rows — ignore it. |
| `location` (7/7, "Berkeley, CA, USA" ×6, "Berkeley, CA" ×1) | `area` | **compute**: strip trailing `", USA"` → "Berkeley, CA" | **Q4:** confirm desired `area` granularity ("Berkeley" vs "Berkeley, CA"). |
| — | `colorHex` | **compute**: MUST reuse the exact same deterministic name→palette function the new `bands:createBand` uses | Do not hand-pick; extract the helper so create and migrate can't drift. |
| — | `initials` | **compute**: first letter of first two words, uppercased; single-word names take first two letters ("SOBO"→"SO", "Public School Records"→"PS") | Same rule as `createBand`. |
| — (no legacy counter) | `followerCount` | **compute**: count of `savedArtists` rows per band (dev: SOBO 5, EARPLUG 1, Circadian Rhythm 1, TRACKMAGIC 1, Test Band 1, others 0) | Keep consistent with Q5 (migrating savedArtists → follow rows). Do NOT carry legacy `memberCount` — it was self-reported at creation (4–6) and disagrees with actual membership rows (1–4). |
| `bio` (4/7) | `bio` | **verbatim**; default `""` (or keep optional) for the 3 nulls | |
| `socialLinks.instagram` (4/7, full URLs with query junk) | `linkIg` | **compute**: extract first path segment after `instagram.com/`, drop query string, prefix `@` — e.g. `https://www.instagram.com/itstrackmagic?igsh=…` → `@itstrackmagic` | |
| — (no bandcamp field in legacy) | `linkBc` | **default `null`** | |
| `socialLinks.{spotify,appleMusic,tiktok,youtube,website}` | — | **dropped by contract** | Only Whalefall has the full set. **Q5b:** lossy — acceptable, or park them in an optional `legacySocialLinks` field? |
| `image` / `imageStorageId` (5/7 have a storage-backed image) | — | **dropped by contract** | New BandPayload has no image. Deleting the fields orphans 5 `_storage` files. Recommend keeping `imageStorageId` schema-optional until v2. |
| `userId` (creator, 7/7, all resolve) | — | drop from band doc | Ownership is already represented by the `owner` row in `bandMemberships` (see §5); nothing lost. |
| `createdAt` | — | drop | ≈ `_creationTime`. |

---

## 5. Related tables with a target

### `bandMemberships` (13 rows) → new `bandMembers`

All 13 rows resolve (0 orphan userIds, 0 orphan bandIds). 8 distinct users are in
bands; 5 of those 8 have empty emails (clerkId adoption covers them — see §2).

| Source | Target | Transform |
|---|---|---|
| `bandId`, `userId` | same | verbatim |
| `role: "owner" \| "admin" \| "member"` | `role: "admin" \| "member"` | **compute**: `owner` → `admin`, others verbatim (contract has no owner tier) |
| `joinedAt`, `invitedBy` | — | drop (or keep `joinedAt` if the new table wants it) |

### `savedArtists` (9 rows, 7 users × 5 bands) → follow rows (`interactions:toggleFollow` store)

Verbatim `userId`/`bandId` copy into whatever join table backs `followBandIds`.
This is the only genuine "fan signal" in the legacy data and is what makes the
migrated `followerCount` non-arbitrary. **Recommend migrating.**

### `venues` (4 rows) → new `venues` (optional)

Mapping is trivial if wanted: `name`→`name`, `city`→`area`, `address`→`addr`,
`coordinates.lat/lng`→`lat`/`lng`; `distSF`/`distOak` computed from lat/lng.
But the 4 rows are two Berkeley fraternities and two street addresses used as
names — **Q7:** migrate these or start from `seed:seedDemo` venues?

### `events` (3) / `rsvps` (26) / `likes` (0)

Conceptual targets exist (`gigs`, rsvp rows, `savedGigIds`) but the data isn't
worth it on dev: the single real event is past (contract feed only shows
`startsAt >= now − 6h`), the two others are test rows, no rsvp was ever marked
attended, `likes` is empty. **Recommend: do not migrate; run `seed:seedDemo`.**
Only value lost: "EARPLUG LAUNCH NIGHT" would not appear in bands' derived
`pastShows` (**Q8** if that matters, port it as a single past gig row).

---

## 6. Legacy tables the new schema does NOT cover

| Table (dev rows) | What it was | Recommendation |
|---|---|---|
| `applications` (0), `openDates` (0) | venue booking marketplace | **drop** |
| `conversations` (0), `conversationReads` (0), `messages` (0) | band↔venue DMs | **drop** |
| `friendships` (0) | fan friend graph | **drop** |
| `savedVenues` (0), `eventCheckinStaff` (0), `bandCreationAttempts` (0) | misc | **drop** |
| `notifications` (1) | in-app notifications | **drop** |
| `spotifyProfiles` (1) | Spotify top-artist personalization | **drop** (re-derivable if v2 rebuilds the feature) |
| `eventTickets` (47), `eventCohostInvites` (4) | QR ticketing + co-host flow for the launch event | **drop** (event is past) |
| `bandProfileEngagements` (18) | profile-view analytics | **drop** |
| `bandInvites` (9) | member invites (7 accepted → already memberships; 2 pending expired 2026-04) | **drop** |
| `bandMediaSlots` (5) | band photo/video gallery (6 slots, `_storage`-backed) | **keep the `_storage` files**; see Q6 — closest new target is the `videos` table but legacy slots have no title/views/length and include images. |

"Drop" here means: exclude from the new `schema.ts` and delete rows once the
migration is verified. Until then, leaving them untouched costs nothing.
NOTE: deleting rows does not delete referenced `_storage` files (they just
orphan) — sweep storage deliberately or keep it.

---

## 7. Prod vs dev — where is the real user base?

Prod row data is not readable (deployment is readOnly to MCP), but schema
inference over its actual documents tells a clear story. Same declared schema,
different lived-in shape:

| Signal (from inferred schemas) | dev | prod |
|---|---|---|
| `eventTickets.usedAt` / `usedByUserId` present on rows | **no** — no ticket was ever scanned | **yes** — real door check-ins happened |
| `rsvps.attendedAt` present on rows | no | **yes** |
| `likes` table has rows | empty | **populated** |
| `users.avatar` on every row | 35/36 | **36/36-equivalent (non-optional)** |
| `bands.socialLinks` on every row, incl. `website` | sparse, no website | **every band, incl. website** |

**Verdict: prod looks like the real, more mature user base — actual events were
run with door scans and attendance — while dev is the smaller spring-2026 beta
circle.** The current plan ("reuse dev in place") migrates only the dev dataset.
If the "users and bands registered" the user cares about are the prod ones, this
plan silently ignores them, and two extra problems appear: (a) prod row data
must be exported (dashboard/CLI with prod credentials — MCP can't), and (b) prod
users' clerkIds belong to a different (live) Clerk instance than the new app's
`.env.local` (`premium-sheep-24` test instance), so adoption there would lean on
email — whose coverage on prod is unknown. **This needs an explicit user
decision before any migration runs.**

*(Resolved: prod was indeed the real user base, and was migrated on 2026-07-30
against its own live Clerk instance — where clerkId coverage turned out to be
287/287, so the email fallback was never needed. See Part 1.)*

---

## 8. Migration risks

1. **Wrong-deployment risk (highest).** See §7 — confirm dev really is the
   dataset that matters before reshaping it.
2. **Schema-push deadlock.** The new `schema.ts` must not declare required
   fields (`colorHex`, `initials`, `followerCount`, `attendedCount`, `genres`)
   before the backfill runs, and must temporarily keep (or explicitly not
   declare) the 20 legacy tables. Sequence: widen (all new fields
   `v.optional`, legacy fields still present) → run `migrateUsers` /
   `migrateBands` → tighten + delete legacy tables/fields. A required field
   pushed onto populated rows blocks ALL deploys including the fix.
3. **Email adoption is unsafe as a primary key.** 25/36 empty emails and one
   email shared by 3 accounts. `ensureUser` must match clerkId first, and only
   adopt by email when exactly one non-empty match exists.
4. **Denormalized counters must be recomputed, not carried.** `followerCount`
   from savedArtists; drop legacy `memberCount` (provably inconsistent with
   membership rows); `goingCount` starts fresh with seeded gigs.
5. **Deterministic-compute drift.** `colorHex`/`initials` must come from the
   same helper `bands:createBand` uses, or migrated bands will look different
   from newly created ones.
6. **Storage orphaning.** Dropping `imageStorageId`/`avatarStorageId`/
   `bandMediaSlots` rows leaves ~13 `_storage` files unreferenced. Decide
   keep-in-optional-fields vs deliberate storage sweep.
7. **Clerk-instance coupling.** All adoption guarantees in §2 hold only while
   the new app keeps using `premium-sheep-24.clerk.accounts.dev`. Going to a
   production Clerk instance later strands the 25 email-less users.
8. **Legacy Clerk webhook.** The legacy app has an HTTP action (Clerk webhook →
   `users.js:createUserFromClerk`). If the Clerk instance still has that
   endpoint registered, it will 404 (or worse, half-create users) once the new
   code replaces `http.ts` — unregister it or reimplement; the new contract
   relies on client-called `ensureUser` instead.
