# EarPlug Convex function contract (FROZEN — v1.19)

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
resolves it back to a band (`earplug.app/<slug>`). `bands:updateProfile` covers
the whole profile, not just bio and links. All of this reached the backend
before v1.2 and was never recorded here.

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

**v1.7 — band-private fan analytics.** Added `analytics:bandRecap`, a bounded
recap of one band's past-gig RSVP measurements. The query requires a signed-in
`bandMembers` row (either role) and introduced a `K_ANON_FANS = 5` floor with
whole-partition suppression. The payload shape below is frozen jointly for
this backend and the parallel Flutter client workstream: both workstreams must
stay in sync on every field, literal and nullability change rather than
drifting around the contract.

**v1.8 — narrowed recap suppression.** The `K_ANON_FANS = 5` floor now applies
only to `leadTime`, `repeatFans`, `newReturning` and the per-show
`newFans`/`returningFans` columns. `leadTime.unmeasurable` is independently
zeroed when it represents 1–4 distinct fans, while zero and cells at or above
the floor still publish. `venues`, `weekdays` and `pricing` now always publish
with `suppressed: false` because their values are exactly recomputable from the
already-published `shows[]` rows. The payload shape did not change.

**v1.9 — a band's history stops depending on other bands.** New `gigBands`
table, one row per (gig, band in its lineup), indexed `by_band_startsAt` and
`by_gig`. `gigs:pastForBand` and `analytics:bandRecap` now read a band's own
past gigs through that index instead of scanning the global `by_startsAt`
range and filtering `lineup` in memory — a scan that silently dropped a band's
older shows once other bands' gigs crowded them past the 200-row window.
`MAX_RECAP_GIGS` rose 30 → 40, and `window.truncated` now means exactly "this
band has played more than `MAX_RECAP_GIGS` past shows"; `window.scanned` is the
index rows read for the band, which exceeds `showsAnalyzed` by one precisely
when the recap is truncated. No payload field changed shape or nullability.
**Every write path into `gigs` must go through `insertGigWithBandIndex`** — a
gig inserted directly is invisible to both read paths. Existing rows are
repaired by `maintenance:backfillGigBands`.

**v1.10 — relationship-based discovery.** Added `bands:list` with standard
Convex cursor pagination over `bands.by_name`, plus `venues:detail` with the
next 200 chronological venue gigs and their deduplicated lineup bands. Venue
detail reads `gigs.by_venueId_and_startsAt` and reports whether a 201st event
was omitted. `GigPayload` and gig publishing now carry `ageRequirement` as one
of `allAges`, `18Plus` or `21Plus`. The stored column remains optional during
the compatibility rollout, but every supported write path requires an explicit
value and every reader normalizes an absent legacy value to `allAges`.
`gigs:feed` retains its existing 200-row window and `nextStartsAt` sentinel.
`interactions:myInteractions` now includes deduplicated upcoming/grace-window
`GigPayload` rows for RSVP and saved ids so Profile remains complete outside
that feed window without moving historical RSVPs back into Upcoming.

**v1.11 — private fan profiles.** `UserPayload` now exposes an owner-only fan
identity, personalization/update preferences, and profile-tutorial state. The
stored columns are optional so legacy rows need no migration; readers normalize
them to `bio: null`, `homeLocation: null`, location personalization off,
followed-band updates on, and tutorial incomplete. Authenticated mutations now
support explicit profile saves, validated avatar upload references, clearing an
avatar without deleting its blob, and tutorial completion/replay. Fan event
history now carries gig identity, artwork inputs, venue and surviving lineup
names, plus the deliberately precise `rsvped` status; an RSVP is not evidence
of attendance.

Deletion tombstones are authorization barriers: owner queries treat them as
unauthenticated, mutations reject them, and later Clerk events for the same
never-reused Clerk id cannot restore the row or its PII.

**v1.12 — deletion and followed-show race fixes.** Account deletion now calls
`users:deleteMe` while the Clerk session can still authenticate, then deletes
the Clerk account; `user.deleted` remains an idempotent retry path. The client
subscribes to `gigs:forBand` for each followed band, and that query now reads
`gigBands.by_band_startsAt`, so the discovery feed's 200-row window cannot hide
a followed band's later show. Each band's own upcoming result remains bounded
to 200 rows.

**v1.13 — task-oriented band setup and secure memberships.** Band profiles now
store and publish optional `credits` and the existing YouTube link. The public
`bands:profileDetails` query adds accepted member names without putting that
membership join into feed/search payloads. Admins receive a private seven-flag
`bands:setupStatus`; either band role can persist the first managed public
preview with `bands:markPreviewed`. The current editor now sends one full,
validated, atomic `bands:updateProfile` save of every editable field, while the
mutation retains optional arguments for released partial-update clients and
renames still preserve slug and color. Legacy `inviteHandles` remain readable
in stored rows and are accepted as a no-op create/update argument for
compatibility, but no supported path writes them. Real membership uses one
unguessable 256-bit, reusable,
seven-day `bandInvites` link per band. Admins can create, rotate, and revoke it;
a token-guarded scheduled mutation materializes expiry so public resolution
never trusts a caller's clock and reveals only band confirmation identity;
authenticated
acceptance is idempotent and increments `followerCount` exactly once with the
new member row.

**v1.14 — gig projects and lifecycle.** `gigProjects` is now the private,
revisioned editorial source for drafts and published listings;
`gigProjectPerformers` holds its bounded, ordered lineup and secure one-use
band invitations. Publishing copies a validated snapshot into the public
`gigs` projection. Public reads include only `published` gigs, except the
direct `gigs:getPublic` lookup, which also returns a `cancelled` listing so an
old share link can explain the cancellation. Admins can save, preview, publish,
edit, duplicate, unpublish, cancel, and delete. Deletes first tombstone the
project and public row, then use a bounded scheduled purge for joins and the
projection. Released clients may keep calling `gigs:publishGig`; that
compatibility path dual-writes a project. Legacy rows remain readable during
the widen/backfill phase and normalize to `published` until
`migrations:backfillGigProjects` has run.

**v1.15 — discovery readiness and progressive activation.** Public band
payloads derive `profileComplete` and `discoveryProfileReady`; public gig
payloads fail-closed to `discoveryListingReady: false` until their stored
publish projection is populated. `bands.hasClip` is maintained in the same
transaction as video inserts/deletes. Publishing recalculates listing
readiness, while any later project or performer save clears it until
republishing. Admins receive the separate six-flag
`bands:discoveryReadiness` detail with the relevant show, next eligible show,
and seven-day/pre-show through six-hour/post-show window. The canonical
eligibility, ranking cap, label, anti-flood rule, and “progressive activation”
definition live in [discovery-policy.md](discovery-policy.md).

**v1.16 — profile setup compatibility.** Added the previously undocumented
`users:updateFanOnboarding` mutation to the frozen client contract. The client
now treats the presence of `profileTutorialCompleted` as a capability marker:
legacy deployments that omit the field do not render tutorial controls that
would call an unavailable mutation. Release builds also verify both profile
setup mutations against the exact configured Convex deployment before the
client is published.

**v1.17 — stable feed payloads under RSVP churn.** Added `gigs:feedV2` and
`gigs:goingCounts`, which read the same upcoming-gig window and bounds as
`gigs:feed`: the same six-hour grace cutoff, ascending order, 200-row cap,
`nextStartsAt` sentinel, and archived-band-owner exclusion. Convex evaluates
the two subscriptions independently, so a gig can momentarily appear in one
result and not yet the other. `feedV2` returns `GigFeedPayload[]` (`GigPayload`
minus `goingCount`) and `BandSummaryPayload[]` (identity, avatar, and readiness
only; no bio, links, or `pastShows`) instead of full `BandPayload[]`;
`goingCounts` returns `{ gigId, goingCount }[]`. The client merges each counts
emission into its last-known-count map rather than replacing that map, and it
waits for the first result from both subscriptions (or a `goingCounts` error)
before marking data ready and rendering. This split makes an RSVP anywhere
leave `feedV2` byte-for-byte unchanged. The client subscribes to `feedV2` plus
`goingCounts`, and to `gigs:forBand` for a followed band only while
`feedV2.nextStartsAt` is non-null, once the bounded feed window is exhausted.
That conditional subscription supersedes v1.12's statement that the client
subscribes to `gigs:forBand` unconditionally for every followed band.

**v1.18 — pre-marketplace cleanup.** Removed these obsolete functions and
maintenance paths: the pre-v1.17 `gigs:feed` (the client has read
`gigs:feedV2` + `gigs:goingCounts` since v1.17);
`gigs:getPublic` (superseded by `gigs:resolvePublic`, which accepts a raw gig
id as well as a slug); the `gigs:publishGig` compatibility mutation (every
client publishes through the draft pipeline, and `maintenance:publishRealGig`
remains the operator path); `users:setGenres` (no client caller — genres are
written by `users:updateProfile` and `users:updateFanOnboarding`); the one-off
`clerkBackfill:*` email backfill; the `maintenance:recountBandFollowers` and
`maintenance:backfillGigBands` reconcilers; and the completed QA-remediation
migrations (`backfillGigSlugs`, `backfillVenueNormalizedKeys`,
`repairReservedBandSlugs`, `runQaRemediationBackfills`). `venues:create` no
longer falls back to scanning rows without normalized keys — every venue row
on both deployments carries them. Internally, the four band-membership guards
collapsed into one `requireBandRole(ctx, bandId, { role, allowArchived? })`;
`requireBandAdmin` in the tables below means
`requireBandRole(…, { role: "admin" })`, and the project guard is
`requireProjectAdmin` for queries and mutations alike. Private band queries
`bands:setupStatus`, `bands:discoveryReadiness`, `bandInvites:manage`,
`analytics:bandRecap`, `gigs:manageForBand`, `gigs:getProject`, and
`gigs:doorRoster` now throw `"Account deleted"` for a tombstoned user
(previously `"No user record — call users:ensureUser first"`). Separately,
`bands:archiveStatus` now throws
`"No user record — call users:ensureUser first"` for a missing user row
(previously `"Not signed in"`) and `"Band not found"` for an unknown `bandId`
(previously `"Not an admin of this band"`). Wire shapes are unchanged in all
cases.

**v1.19 — marketplace phase 1.** Wire shapes for already-shipped functions are
otherwise unchanged. An organization is the account/business entity that
manages bookings and payouts; a venue is a physical location and may optionally
link to its manager through `managedByOrganizationId`. The schema now includes
`organizations`, `organizationPrivateDetails`, `organizationMembers`,
`organizationMemberInvites`, `organizationApplications`,
`venuePrivateDetails`, and `stripeEvents`; see their modules and schema for the
exact shapes.

`VenuePayload` adds `slug`, `approxLocation`, `neighborhood`, `city`,
`addressDisclosure`, `verified`, `managedByOrganizationId`, `exactAddr`,
`description`, `venueType`, and `capacityPublic`.
The wire `addr`/`lat`/`lng` fields are always the disclosable location: exact
for a public venue and approximate for a venue whose `addressDisclosure` is
`onTicket`.

- `organizationApplications:mine` — Query; see module for exact args and return shape.
- `organizationApplications:saveDraft` — Mutation; see module for exact args and return shape.
- `organizationApplications:submit` — Mutation; see module for exact args and return shape.
- `organizationApplications:attachDocument` — Mutation; see module for exact args and return shape.
- `organizationApplications:generateDocumentUploadUrl` — Mutation; see module for exact args and return shape.
- `organizations:mine` — Query; see module for exact args and return shape.
- `organizations:bySlug` — Query; see module for exact args and return shape.
- `organizations:dashboard` — Query; see module for exact args and return shape.
- `organizations:addPhoto` — Mutation; atomically appends one validated photo,
  preserving existing photos and treating a repeated storage ID as a no-op.
- `organizationMembers:resolveInvite` — Query; see module for exact args and return shape.
- `organizationMembers:acceptInvite` — Mutation; see module for exact args and return shape.
- `venues:resolvePublic` — Query; see module for exact args and return shape.
- `venues:privateDetail` — Query; see module for exact args and return shape.
- `admin:me` — Query; see module for exact args and return shape.

`venues:create` deduplicates only against public venue columns and returns the
existing venue with `created: false` on a name/area or exact-public-address
match; when the match is an on-ticket venue, its payload remains approximate.
Matching only another on-ticket venue's private address creates a separate
legacy venue. Platform-admin `internalMutation`s support the new administration
and verification workflows; see their modules for exact operations. Two Stripe
webhook HTTP routes record their received events in `stripeEvents`.

`organizationMembers:createInvite` accepts only `manager`, `finance`, or `door`;
owners are promoted through `organizationMembers:setRole`. Changing a live
invite's role rotates its token and expiry instead of mutating it in place.

`organizations:setPhotos` retains its full-list replacement behavior for
existing callers. The settings photo uploader uses `organizations:addPhoto`
so adding a photo after reopening settings or from another session preserves
the organization's existing photos.

Suspended venues and their gigs are excluded from public discovery: the feed,
going counts, public gig resolver, and public band upcoming/history queries.
The client subscribes to `venues:list` so directory entries also disappear or
return when an organization is suspended or restored, including venues with
no upcoming gigs. Band management projects and personal RSVP history remain
available.

Legacy venue rows are maintained by the ordered, idempotent
`migrations:runReleaseBackfills` runner and observed through
`migrations:releaseBackfillStatus`. `tool/run_release_backfills.mjs`, exposed as
`npm run backfill:release`, drives that runner to completion during a production
release.

All function results travel as JSON. Ids are Convex document-id strings (the
Flutter models already use `String` ids). Timestamps are ms-since-epoch numbers
(UTC). Auth = Clerk JWT (template `convex`) attached by the client; queries that
depend on identity return empty/null when unauthenticated (they must NOT throw,
the client subscribes before sign-in); the explicitly band-private
`analytics:bandRecap`, `bands:setupStatus`,
`bands:discoveryReadiness`, and `bandInvites:manage` queries are the exceptions
and throw unless the caller has their required band role.
**All mutations throw when unauthenticated**.

## Reconciliation

Verified against the current source as of v1.17; these deployed, client-required contract surfaces were previously undocumented:

- `gigs:resolvePublic({ ref: string }) -> GigPayload | null` — public; trims `ref`, rejects more than 200 characters, tries a slug through `by_slug` before normalizing a raw gig id, and returns only `published` or `cancelled` gigs (so an old share link can explain a cancellation) whose owning band is not archived.
- `gigs:doorRoster({ projectId }) -> { total: number, checkedIn: number, truncated: boolean }` — `requireProjectAdmin`; counts at most 501 `gigRsvps` for the project's public RSVP gig, reports `truncated` past 500, and otherwise returns zeros.
- `gigs:checkInTicket({ projectId, payload: string }) -> { status: "checkedIn"|"alreadyCheckedIn", fanName, checkedInAt } | { status: "invalid" } | { status: "wrongGig" }` — `requireProjectAdmin`; validates a `TICKET_PREFIX`-prefixed 64-hex-character token through `gigRsvps.by_ticketToken`, then patches `checkedInAt` and `checkedInBy` once.
- `interactions:ticketForGig({ gigId }) -> { payload: string, checkedInAt: number|null }` — authenticated; requires an RSVP, mints or reuses its `ticketToken`, and returns it with `TICKET_PREFIX`.
- `venues:create({ bandId, name, area, addr, lat, lng }) -> { venue: VenuePayload, created: boolean }` — `requireBandAdmin(bandId)`; trims and length-validates text, range-validates coordinates, then deduplicates by normalized address before normalized name.
- `bands:setBandAvatar` / `bands:clearBandAvatar` / `bands:setBandBanner` / `bands:clearBandBanner` — `{ bandId, mediaId }` for set or `{ bandId }` for clear, returning `null`; admin-only, setting or clearing the band's avatar/banner storage id from its existing photo without deleting the blob.
- `bands:archive({ bandId }) -> { bandId, archivedAt: number, alreadyArchived: boolean }` — admin-only soft-delete tombstone; first use sets `archivedAt`/`archivedBy` and schedules future published-gig cancellation plus follow/invite/performer-invite cleanup, while retries schedule the same cleanup as repair.
- `bands:archiveStatus({ bandId }) -> { bandId, archivedAt: number|null }` — admin-only and deliberately readable after archiving so the original admin can verify the outcome while public and management reads hide the band.
- `media:moveWithinKind({ mediaId, direction: "earlier"|"later" }) -> null` — admin-only for the media's band; swaps order with the adjacent same-kind sibling, unlike the mixed-kind `media:moveMedia`, and is a no-op at either end.
- `BandPayload.avatarUrl` / `BandPayload.bannerUrl` — `toBandPayload` resolves `avatarStorageId`/`bannerStorageId`, each falling back to legacy `imageStorageId`, then null.
- `MediaPayload.thumbnailUrl` / `MediaPayload.isAvatar` / `MediaPayload.isBanner` — `toMediaPayload` resolves the thumbnail alongside `url` and marks whether the row's blob is the band's current avatar or banner.

## Payload shapes

```jsonc
// GigPayload
{ "_id": "...", "title": "...", "venueId": "...", "price": 0,
  "doorsAt": 1785296400000, "startsAt": 1785300000000,
  "doorsTime": "8PM / 9PM", "lifecycle": "published|cancelled",
  // saveDraft accepts all eleven; maintenance:publishRealGig accepts the first six
  // custom implies a non-null flyerUrl once valid flyStorageId was supplied
  "flyKey": "xerox|riso|marquee|blueprint|sunburst|custom|paper|blue|black|yellow|bluetype",
  // resolved from flyStorageId; null when no custom flyer is stored/live
  "flyerUrl": null,
  "lineup": ["<bandId>"],
  "performers": [{ "name": "...", "role": "headliner|support|opener",
                    "bandId": "<optional bandId>" }],
  "genres": ["punk"], "desc": "...",
  "ticketing": "rsvp|external",
  "ageRequirement": "allAges|18Plus|21Plus",
  "externalUrl": null, "cap": "No cap",
  "goingCount": 43, "createdByBand": null,
  "discoveryListingReady": false }

// GigFeedPayload — exactly GigPayload with goingCount removed; no other field
// or nullability changes

// VenuePayload
{ "_id": "...", "name": "...", "area": "...", "addr": "...",
  "distSF": "0.8 mi", "distOak": "6.3 mi", "lat": 37.75, "lng": -122.41 }

// BandPayload — one shape everywhere; every key is always present
{ "_id": "...", "name": "...", "genres": ["garage"], "area": "...",
  "colorHex": "#7B8FFF", "initials": "FD", "followerCount": 486, "bio": "...",
  // resolves via imageStorageId when set and live; null otherwise
  "heroUrl": null,
  // resolves via avatarStorageId, falling back to legacy imageStorageId; null otherwise
  "avatarUrl": null,
  // resolves via bannerStorageId, falling back to legacy imageStorageId; null otherwise
  "bannerUrl": null,
  "linkIg": "@foghorndiet", "linkBc": "foghorndiet.bandcamp.com",
  "linkYt": "youtube.com/@foghorndiet", "credits": "Recorded by Mara",
  "profileComplete": true, "discoveryProfileReady": false,
  "pastShows": [{ "title": "...", "meta": "JUL 12" }] }

// BandSummaryPayload — gigs:feedV2's slim band shape: identity, avatar and
// readiness flags only; no bio, links or pastShows ride along with the feed
{ "_id": "...", "slug": "...", "name": "...", "genres": ["garage"],
  "area": "...", "colorHex": "#7B8FFF", "initials": "FD",
  "followerCount": 486,
  // resolves via avatarStorageId, falling back to legacy imageStorageId; null otherwise
  "avatarUrl": null,
  "profileComplete": true, "discoveryProfileReady": false }

// BandProfileDetails — public; only this profile-specific read joins members
{ "credits": "Recorded by Mara", "linkIg": "@foghorndiet",
  "linkBc": "foghorndiet.bandcamp.com",
  "linkYt": "youtube.com/@foghorndiet",
  "memberNames": ["Sam Reyes", "Mara Kim"] }

// BandSetupStatus — admin-only, advisory, and never an access gate
{ "profileComplete": true, "profileImageAdded": false,
  "musicAdded": true, "socialLinksAdded": true,
  "firstGigCreated": false, "membersInvited": false,
  "publicProfilePreviewed": true }

// BandDiscoveryReadiness — admin-only; supplied now affects the window only
{ "profileComplete": true, "profileImageReady": true, "clipReady": true,
  "publishedShowReady": true, "venuePosterReady": true,
  "publishedRevisionCurrent": true,
  "relevantShow": { "gigId": "...", "projectId": "...",
    "title": "Complete Listing", "startsAt": 1785300000000 },
  "nextEligibleShow": { "gigId": "...", "projectId": "...",
    "title": "Complete Listing", "startsAt": 1785300000000 },
  "boostWindow": { "opensAt": 1784695200000,
    "closesAt": 1785321600000, "active": true } }

// BandInvite — admin management payload
{ "bandId": "...", "token": "<64 lowercase hex characters>",
  "expiresAt": 1785904800000, "revoked": false, "expired": false }

// BandInviteResolution — public confirmation identity only
{ "bandId": "...", "bandName": "Foghorn Diet", "initials": "FD",
  "colorHex": "#7B8FFF" }

// MediaPayload
{ "_id": "...", "bandId": "...", "kind": "video|photo",
  // null means the client renders its placeholder tile
  "url": null,
  // resolved alongside url; null when no live thumbnail is stored
  "thumbnailUrl": null,
  "title": "...", "caption": null, "contentType": null,
  "sizeBytes": null,
  // views has no server write path: display-only legacy data; nothing increments it
  // views/lengthSec are null unless kind is video and the value is set
  "views": null, "lengthSec": null, "pinned": false, "order": 0,
  // mark whether this row's blob is the band's current avatar or banner
  "isAvatar": false, "isBanner": false,
  "isHero": false }

// UserPayload
{ "_id": "...", "clerkId": "user_...", "name": "Sam Reyes",
  "email": "sam@example.com", "genres": ["punk"], "attendedCount": 12,
  // storage-backed avatar wins while live; then legacy avatarUrl; else null
  "avatarUrl": null, "bio": null,
  // one of "sf", "oak", or null
  "homeLocation": null,
  "locationPersonalizationEnabled": false,
  "followedBandUpdatesEnabled": true,
  // Presence is also the client's capability marker for tutorial mutations.
  // A legacy payload that omits it must not render tutorial controls.
  "profileTutorialCompleted": false,
  // users.deletedAt is an internal tombstone and is deliberately not exposed
  // the row's _creationTime, surfaced under a stable name
  "createdAt": 1785300000000,
  // unchanged compatibility shape; null on pre-onboarding legacy rows
  "fanOnboarding": null }

// HistoryItem — an RSVP record, never a verified-attendance claim
{ "gigId": "...", "title": "Basement Blowout",
  "startsAt": 1785300000000, "venueName": "Casa Quake",
  "bandNames": ["Mission Creep"], "flyKey": "custom",
  "flyerUrl": null, "status": "rsvped" }

// BandRecap — shows are newest first; weekday is Monday=1 through Sunday=7
{ "window": { "showsAnalyzed": 2, "scanned": 14, "truncated": false,
               "firstStartsAt": 1784000000000, "lastStartsAt": 1785000000000 },
  "totals": { "shows": 2, "reportedRsvps": 90, "measuredRsvps": 82,
              "avgPerShow": 41, "bestShowRsvps": 47,
              "distinctFans": 70, "followerCount": 486 },
  "shows": [
    { "gigId": "...", "title": "...", "startsAt": 1785000000000,
      "venueName": "...", "price": 10, "ticketing": "rsvp|external",
      "goingCount": 48, "measuredRsvps": 47,
      // both are null on every show when newReturning.suppressed is true
      "newFans": 35, "returningFans": 12 }
  ],
  "newReturning": { "suppressed": false },
  "leadTime": {
    "buckets": [
      { "key": "twoWeeksPlus|oneToTwoWeeks|underWeek|dayOf", "count": 20 }
    ],
    // independently zeroed when the true cell contains 1–4 distinct fans
    "medianDays": 8.5, "unmeasurable": 5, "suppressed": false
  },
  "venues": {
    "rows": [{ "venueName": "...", "shows": 2,
               "totalRsvps": 82, "avgRsvps": 41 }],
    // always false: exactly recomputable from shows[]
    "suppressed": false
  },
  "weekdays": {
    "rows": [{ "weekday": 6, "shows": 2, "avgRsvps": 41 }],
    // always false: exactly recomputable from shows[]
    "suppressed": false
  },
  "repeatFans": {
    "tiers": [{ "key": "one|twoToThree|fourPlus", "count": 50 }],
    "suppressed": false
  },
  "pricing": { "freeShows": 1, "freeAvgRsvps": 35,
               "paidShows": 1, "paidAvgRsvps": 47,
               // always false: exactly recomputable from shows[]
               "suppressed": false } }

// Suppression applies only to leadTime, repeatFans and newReturning. Suppressed
// leadTime has empty buckets and a null median; unmeasurable returns its real
// count only when its distinct-fan set is empty or >= 5, and is zeroed for a
// 1–4-fan cell. Suppressed repeatFans has empty tiers. Suppressed newReturning
// makes both per-show split columns null. venues/weekdays/pricing retain the
// field for the frozen shape but always set suppressed to false.
```

## Queries (client subscribes to the ★ ones)

| Function                        | Args                 | Returns                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ★ `gigs:feedV2`                 | `{}`                 | `{ gigs: GigFeedPayload[], venues: VenuePayload[], bands: BandSummaryPayload[], nextStartsAt: number\|null }` — all published gigs with `startsAt >= now - 6h` whose owning band is not archived, ascending, plus every venue and band summary they reference. Public. Bounded to the 200 nearest upcoming gigs; `nextStartsAt` is the first omitted timestamp or `null`. Gigs omit `goingCount` so an RSVP anywhere leaves this result byte-for-byte unchanged; pair with `gigs:goingCounts` for the counts.                                                                                                     |
| `gigs:goingCounts`              | `{}`                 | `Array<{ gigId, goingCount }>` — the `goingCount` values `feedV2` omits. It reads the same window, but Convex evaluates the subscriptions independently, so a gig may momentarily occur in only one result. The client merges emissions into a last-known-count map (never replacing it wholesale) and waits for the first `feedV2` result plus the first counts result, or a counts error, before marking data ready and rendering. Public. Subscribing separately keeps RSVP churn off the feed payload.                                                                                                                                                                                         |
| ★ `gigs:forBand`                | `{ bandId }`         | `GigPayload[]` — the band's next 200 upcoming/grace-window gigs, ascending. Reads `gigBands.by_band_startsAt`, so unrelated discovery gigs cannot crowd the band out of the result. In v1.17, the branch client subscribes for a followed band only while `feedV2.nextStartsAt` is non-null, once the bounded feed window has been exhausted.                                                                                                                                                                                                                                                                       |
| `gigs:pastForBand`              | `{ bandId }`         | `{ gigs: GigPayload[], venues: VenuePayload[] }` — the band's 200 most recent past gigs, **descending**, plus the venues they reference. Public. Reads `gigBands.by_band_startsAt`, so other bands cannot crowd its history out of the window.                                                                                                                                                                                                                                                                                                                                                                      |
| `gigs:manageForBand`            | `{ bandId }`         | `GigProjectPayload[]` — admin-only draft/published/cancelled projects, newest first; deleted projects are omitted.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `gigs:getProject`               | `{ projectId }`      | `GigProjectPayload` — admin-only private source used for editing and fan preview.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `venues:list`                   | `{}`                 | `VenuePayload[]` — every venue, name-ascending, capped at 500. Public.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `venues:detail`                 | `{ venueId }`        | `null` or `{ venue: VenuePayload, gigs: GigPayload[], bands: BandPayload[], truncated: boolean }` — venue-isolated gigs with `startsAt >= now - 6h`, ascending and capped at 200, plus unique existing bands referenced by those gigs' lineups. `truncated` is true when a 201st venue gig exists. Public.                                                                                                                                                                                                                                                                                                          |
| `bands:get`                     | `{ bandId }`         | `BandPayload` (full) or `null`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `bands:list`                    | `{ paginationOpts }` | Standard Convex pagination result with `page: BandPayload[]`, name-ascending through `bands.by_name`; pass `continueCursor` into the next request unchanged. Public.                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `bands:search`                  | `{ q: string }`      | `BandPayload[]` — name search-index match; `q: ""` → all bands (capped 50)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `bands:bySlug`                  | `{ slug: string }`   | `BandPayload` (full) or `null` — resolves a shared profile link. Public. Duplicate slugs degrade to the older band rather than throwing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `bands:profileDetails`          | `{ bandId }`         | `BandProfileDetails` or `null` — public credits/links plus accepted, non-deleted member names. Memberships are capped at 100 and joined only here, not in feed/search payloads.                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ★ `bands:myBands`               | `{}`                 | `[{ band: BandPayload, role: "admin"\|"member" }]`; `[]` unauth. Capped at 100 memberships.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `bands:setupStatus`             | `{ bandId }`         | `BandSetupStatus` — admin-only and throws otherwise. The seven flags are complete core profile (including bio); configured profile image; video/Bandcamp/YouTube; Instagram; a published `gigBands` row; a second accepted membership; and persisted preview timestamp. The seven-step onboarding card and its access semantics are unchanged.                                                                                                                                                                                                                                                                      |
| `bands:discoveryReadiness`      | `{ bandId, now }`    | `BandDiscoveryReadiness` — admin-only and throws otherwise. Returns the six detailed profile/listing flags, earliest relevant published show, earliest listing-eligible show, and its boost window. `now` changes presentation only and is never used for authorization.                                                                                                                                                                                                                                                                                                                                            |
| `bandInvites:manage`            | `{ bandId }`         | `BandInvite` or `null` — admin-only status for the band's one reusable link, including expired/revoked state.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `bandInvites:resolve`           | `{ token, now? }`    | `BandInviteResolution` or `null` — public. Returns only confirmation-screen identity while the server-materialized expiry and revoked flags are clear. Deprecated `now?` is accepted for compatibility but ignored, so callers cannot extend validity with a false clock.                                                                                                                                                                                                                                                                                                                                           |
| `media:forBand`                 | `{ bandId }`         | `MediaPayload[]` — public; one list across both kinds, ordered by `order` asc                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `users:me`                      | `{}`                 | `UserPayload \| null`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ★ `interactions:myInteractions` | `{}`                 | `{ rsvpGigIds: string[], followBandIds: string[], savedGigIds: string[], gigs: GigPayload[], attendedCount: number }`; `gigs` deduplicates and hydrates upcoming/grace-window RSVP/saved rows beyond the feed window; empty/0 unauth                                                                                                                                                                                                                                                                                                                                                                                |
| `interactions:history`          | `{ now: number }`    | `HistoryItem[]` — gigs the user RSVPed to with `startsAt < now`, newest first; `[]` unauth. `now` is client-supplied ms-since-epoch so events cross into history without unrelated cache invalidation. Missing gig references are skipped, missing venues become `""`, missing lineup bands are omitted, and a live uploaded flyer resolves `flyerUrl` while generated posters use `flyKey` with `flyerUrl: null`. Every item has `status: "rsvped"`; this does not claim attendance.                                                                                                                               |
| `analytics:bandRecap`           | `{ bandId }`         | `BandRecap` — signed-in band members only (admin or member); throws otherwise. Reads the 200 most recent globally past gigs, analyzes at most the first 30 whose lineup contains the band, and returns shows newest first. `window.truncated` covers both the matching-show cap and a full global scan. The five-distinct-fan floor suppresses `leadTime`, `repeatFans`, `newReturning` and the per-show new/returning columns; `leadTime.unmeasurable` is also independently zeroed for 1–4 distinct fans. `venues`, `weekdays` and `pricing` always publish because they are exactly recomputable from `shows[]`. |

## Mutations

| Function                                | Args                                                                                                                                                                                                                 | Returns                         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `users:ensureUser`                      | `{ name?: string }`                                                                                                                                                                                                  | `{ userId }`                    | Thin authenticated adapter over the shared Clerk adoption ladder, keyed on `identity.subject`. Falls back to adopting a live legacy row by `identity.email` — but **only** when `identity.emailVerified` is true **and** exactly one row carries that address, so an unverified sign-up cannot claim a migrated account and the known duplicate-email rows are left alone. Empty-email repair refuses collisions. Called by the client right after sign-in, but `user.created` can now run the same adoption before any sign-in. |
| `users:deleteMe`                        | `{}`                                                                                                                                                                                                                 | `null`                          | Authenticated soft tombstone invoked before Clerk account deletion invalidates the session. Blanks email and preserves referenced history/joins; the webhook repeats the same operation idempotently.                                                                                                                                                                                                                                                                                                                            |
| `users:updateProfile`                   | `{ name: string, bio: string\|null, homeLocation: "sf"\|"oak"\|null, genres: string[], locationPersonalizationEnabled: boolean, followedBandUpdatesEnabled: boolean }`                                               | `null`                          | Explicit full save. Trims name, bio, and genres; blank bio/unset location are stored absent and emitted as null. Rejects a blank or >100-char name, >500-char bio, more than 20 genres, and blank, duplicate, or >50-char genres.                                                                                                                                                                                                                                                                                                |
| `users:generateAvatarUploadUrl`         | `{}`                                                                                                                                                                                                                 | upload URL string               | Requires an authenticated user row. The client must upload a photo-compatible file before calling `setAvatar`.                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `users:setAvatar`                       | `{ storageId }`                                                                                                                                                                                                      | `null`                          | Requires a live `_storage` row accepted by the shared photo size/type rules. Sets `avatarStorageId` and clears legacy `avatarUrl`; replaced blobs are left to the existing orphan sweep.                                                                                                                                                                                                                                                                                                                                         |
| `users:clearAvatar`                     | `{}`                                                                                                                                                                                                                 | `null`                          | Clears both avatar references without deleting a blob; orphan cleanup remains centralized.                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `users:setProfileTutorialCompleted`     | `{ completed: boolean }`                                                                                                                                                                                             | `null`                          | `true` persists completion/dismissal; `false` enables Settings-driven replay.                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `users:updateFanOnboarding`             | `{ preferredCity?: "sf"\|"oak", genreChoice?: "pending"\|"selected"\|"open", collapsed?: boolean, genres?: string[] }`                                                                                     | `null`                          | Requires a newly enrolled fan and at least one supplied field. Validates every supplied value and saves genre choice plus genres atomically.                                                                                                                                                                                                                                                                                                                                                                                      |
| `interactions:toggleRsvp`               | `{ gigId }`                                                                                                                                                                                                          | `{ on: boolean }`               | Insert/delete join row via by_user_gig index; `goingCount` ±1 same transaction.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `interactions:toggleFollow`             | `{ bandId }`                                                                                                                                                                                                         | `{ on: boolean }`               | `followerCount` ±1 same transaction.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `interactions:toggleSave`               | `{ gigId }`                                                                                                                                                                                                          | `{ on: boolean }`               |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `bands:createBand`                      | `{ name, genres: string[], bio, area, linkIg?, linkBc?, linkYt?, credits?, inviteHandles? }`                                                                                                                         | `{ bandId, slug, band }`        | Inserts a trimmed, validated band (nonblank name and home base, 1–3 nonblank genres; colorHex/initials/slug computed server-side; `followerCount = 1` for the admin membership). Deprecated `inviteHandles?` is accepted for old clients but ignored and never stored.                                                                                                                                                                                                                                                           |
| `bands:updateProfile`                   | `{ bandId, name?, genres?, area?, bio?, inviteHandles?, linkIg?, linkBc?, linkYt?, credits? }`                                                                                                                       | `null`                          | requireBandAdmin. Fields remain optional for released partial-update and pre-credits clients; the current editor sends every editable field in one atomic save. Supplied fields are trimmed, blank optional fields are removed, and supplied required fields are validated. Deprecated `inviteHandles?` is accepted but ignored. A rename recomputes `initials` but deliberately NOT `slug` or `colorHex`.                                                                                                                       |
| `bands:markPreviewed`                   | `{ bandId }`                                                                                                                                                                                                         | `null`                          | Requires either accepted band role. Persists the first preview timestamp idempotently.                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `bandInvites:create`                    | `{ bandId }`                                                                                                                                                                                                         | `BandInvite`                    | requireBandAdmin. Creates the band's 256-bit random, seven-day reusable link, reuses it while active, and refreshes it after expiry or revocation.                                                                                                                                                                                                                                                                                                                                                                               |
| `bandInvites:rotate`                    | `{ bandId }`                                                                                                                                                                                                         | `BandInvite`                    | requireBandAdmin. Replaces the token, creator, and seven-day expiry on the band's single row and clears revoked state. The former token stops resolving immediately.                                                                                                                                                                                                                                                                                                                                                             |
| `bandInvites:revoke`                    | `{ bandId }`                                                                                                                                                                                                         | `null`                          | requireBandAdmin. Idempotently marks the current reusable link revoked.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `bandInvites:accept`                    | `{ token }`                                                                                                                                                                                                          | `{ bandId, membershipCreated }` | Authenticated explicit confirmation. Rejects expired/revoked/unknown links. Inserts a `member` membership and increments `followerCount` in the same transaction only when no membership already exists; repeat acceptance returns `membershipCreated: false`.                                                                                                                                                                                                                                                                   |
| `media:generateUploadUrl`               | `{ bandId }`                                                                                                                                                                                                         | upload URL string               | requireBandAdmin(bandId) and nothing else — the 50-row cap is NOT checked here, because this URL also uploads gig flyers. `media:addMedia` is the only place the cap is enforced.                                                                                                                                                                                                                                                                                                                                                |
| `media:addMedia`                        | `{ bandId, kind: "video"\|"photo", storageId, title, caption?, lengthSec? }`                                                                                                                                         | `{ mediaId }`                   | requireBandAdmin(bandId); requires a live, acceptable, non-duplicate upload and room under the 50-row per-band cap. Ordering is appended **globally** — `max(order) + 1` across both kinds, one list per band, not one per kind. The first video auto-pins. A video insert sets `bands.hasClip = true` in the same transaction.                                                                                                                                                                                                  |
| `media:deleteMedia`                     | `{ mediaId }`                                                                                                                                                                                                        | `null`                          | requireBandAdmin of the media's band; deletes the row only — the blob stays and is reclaimed later by `media:sweepOrphanBlobs`, so a shared or missing blob can never wedge row deletion. Repacks the band's whole order to 0..n-1, clears the hero reference when applicable, promotes the next video when the pinned one is deleted, and transactionally recomputes `bands.hasClip` after a video deletion.                                                                                                                    |
| `media:pinMedia`                        | `{ mediaId }`                                                                                                                                                                                                        | `null`                          | requireBandAdmin of the media's band; video only; unpins siblings.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `media:moveMedia`                       | `{ mediaId, direction: "up"\|"down" }`                                                                                                                                                                               | `null`                          | requireBandAdmin of the media's band; swaps `order` with the adjacent row in the band's single global list, which may be of the other kind; no-op at ends.                                                                                                                                                                                                                                                                                                                                                                       |
| `bands:setBandPhoto`                    | `{ bandId, mediaId }`                                                                                                                                                                                                | `null`                          | requireBandAdmin(bandId); media must be a photo belonging to that band.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `bands:clearBandPhoto`                  | `{ bandId }`                                                                                                                                                                                                         | `null`                          | requireBandAdmin(bandId); clears `imageStorageId` without deleting the blob.                                                                                                                                                                                                                                                                                                                                                                                                                                                     |

The gig-project mutation family is admin-only: `gigs:createDraft`,
`gigs:saveDraft`, `gigs:addPerformer`, `gigs:updatePerformer`,
`gigs:removePerformer`, `gigs:reorderPerformers`, `gigs:publishDraft`,
`gigs:duplicate`, `gigs:unpublish`, `gigs:cancel`, and `gigs:deleteGig`.
Draft saves use an exact `revision` and reject stale writes. Lineups are capped
at 20. `band` performers reference an existing EarPlug band; `invited`
performers receive a seven-day 256-bit link; `text` performers deliberately
have no account. `gigs:resolvePerformerInvite` is the minimal public
confirmation query and `gigs:claimPerformerInvite` requires an authenticated
admin of the claiming band. Publishing or republishing recalculates
`gigs.discoveryListingReady`; every save or performer change to a published
project clears it immediately. Claiming an invitation keeps the public lineup
usable but leaves the revision stale and the discovery projection false until
the creating band republishes.

## HTTP endpoints

| Method and path       | Host                                                         | Behavior                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /clerk-webhook` | The deployment's `.convex.site` URL, **not** `.convex.cloud` | Verifies the Svix signature with that deployment's `CLERK_WEBHOOK_SECRET`. `user.created` and `user.updated` flatten a validated Clerk user into the shared adoption mutation; `user.deleted` soft-tombstones by Clerk id. Other valid event types return 200 and write nothing. Verification/payload failures return 400; missing configuration or mutation failures return 500 so Svix retries. Operations are idempotent by Clerk id; `svix-id` is logged for traceability rather than stored in an unbounded dedupe table. |

## Limits

- `MAX_RECAP_GIGS = 40` of the band's own past gigs, read through
  `gigBands.by_band_startsAt`; `MAX_RSVPS_PER_GIG = 300` per analyzed show.
  The recap cap is what the ~16k document read limit constrains (40 × 300 =
  12,000 worst case). `MAX_PAST_GIGS = 200` bounds `gigs:pastForBand`, which
  reads no RSVP rows and so lists a band's history far past the recap cap.
- `K_ANON_FANS = 5` distinct fans in every populated lead-time bucket, repeat
  tier and new/returning set. A cell with 1–4 fans suppresses its whole
  partition; zero is safe, though an entirely empty partition has no data and
  remains suppressed. `leadTime.unmeasurable` is additionally zeroed when its
  own distinct-fan set contains 1–4 fans. The floor does not apply to `venues`,
  `weekdays` or `pricing`.
- `MAX_MEDIA_PER_BAND = 50` — also the `.take()` bound on every `bandMedia`
  read, so "the whole ordered list fits in one read" holds by construction.
- `MAX_VENUE_GIGS = 200`; `venues:detail` reads one extra indexed row only to
  compute `truncated`, and hydrates gigs/bands from the returned 200-row page.
- `interactions:myInteractions` reads at most 500 RSVP, 500 follow and 500 save
  rows, then point-reads at most 1,000 deduplicated RSVP/save gigs. Only gigs at
  or after the shared six-hour feed cutoff are returned, but those hydrated
  rows make the reactive query depend on their gig and flyer-storage data.
- `interactions:history` reads the 500 most recently created RSVP rows, then hydrates the existing
  past gig, venue, lineup bands, and flyer storage referenced by each result.
- `MAX_MEDIA_BYTES = 100 MiB`.
- Band invitation tokens carry 256 bits of strong pseudo-randomness. Creation
  and rotation schedule `bandInvites:expire` for seven days later; its band and
  token guard prevents an old rotation's job from expiring a replacement.
  Each band keeps one invitation row, so rotation does not grow history.
- Fan profile name ≤ 100 chars, bio ≤ 500 chars, at most 20 favorite genres,
  each nonblank and ≤ 50 chars, with no duplicates after trimming.
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
  its follow row), `bands:createBand` (seeds 1 with its admin member row), and
  `bandInvites:accept` (+1 with a newly inserted member row).
  `convex/seed.ts`, however, writes decorative follower counts (486, 1214, 743,
  312, 927, 158) without creating any `follows` or `bandMembers` rows, so every
  seeded band intentionally violates the invariant.
- `gigs.goingCount == count(gigRsvps by gigId)`. Its writers are
  `interactions:toggleRsvp` (±1 with its RSVP row) and every gig insert, which
  seeds it to 0.
- Every supported gig insert supplies `ageRequirement` explicitly. The stored
  field is temporarily optional solely so deployed legacy rows remain valid;
  `toGigPayload` always emits it and maps absence to `allAges`.
- During the v1.15 widen phase, absent `bands.hasClip` and
  `gigs.discoveryListingReady` values mean false. Live media writes maintain
  `hasClip`; gig publishing is the only path that can set listing readiness
  true, while published project/performer edits clear it in the same
  transaction.
- `bands.pastShows` is a hand-derived summary with no live writer. No gig
  mutation maintains it, so it is not synchronized automatically.
- `analytics:bandRecap` copies each gig's `goingCount` only into its show row
  and the straight-sum `totals.reportedRsvps`. `totals.measuredRsvps`, every
  average, best-show value and fan breakdown come only from bounded
  `gigRsvps` rows. Lead-time rows created at or after `startsAt` are
  unmeasurable and excluded from both buckets and the median.
- Recap suppression is partition-wide for `leadTime`, `repeatFans` and
  `newReturning`: their buckets, tiers or per-show `newFans`/`returningFans`
  columns are never partially revealed. `leadTime.unmeasurable` has its own
  small-cell gate and can still return its real count when its distinct-fan set
  is empty or has at least five fans, even when the rest of lead time is
  suppressed. `venues`, `weekdays` and `pricing` always publish with
  `suppressed: false` because they are exactly recomputable from the
  already-visible per-show `venueName`, `startsAt`, `price` and `measuredRsvps`
  values in `shows[]`; venue and weekday turnout is ultimately also exposed
  publicly through `gigs.goingCount`. `window`, `totals`, `goingCount` and
  `measuredRsvps` remain visible counts.

## Client-side derivations (NOT server concerns)

- `GigWhen` tonight/week/later, `dateShort` ("TUE JUL 28"), `dateLine`
  ("TONIGHT · DOORS 8PM") — derived from `startsAt` + `doorsTime` in Dart.
- Flyer colors from `flyKey` via the existing client const map.
- `Color` from `colorHex`; video display strings ("12.4K views", "2:41") from numbers.
- Feed filters (city/tonight/week/free/genre) — client-side over the feed payload.

## Internal (not called by client)

- `bandInvites:expire` internalMutation — scheduled at the current token's
  server-issued expiry. It sets the materialized `expired` flag only when both
  band id and token still match, so delayed jobs from rotated links are no-ops.
- `users:syncFromClerk` internalMutation — the webhook's single write entry
  point for a flattened, validated Clerk identity. Runs the same adoption
  ladder as `users:ensureUser`; `user.updated` makes a non-empty, non-colliding
  email authoritative while preserving a non-empty stored name.
- `users:markDeletedFromClerk` internalMutation — soft-tombstones a row by
  Clerk id and blanks its email as an idempotent retry of `users:deleteMe`. It
  deliberately leaves follows, memberships, RSVPs, saves, media attribution
  and denormalized counters untouched.
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
- `maintenance:publishRealGig` internalMutation — dry-run by default and takes
  the shared gig publish fields (`gigPublishFieldsValidator` in
  `convex/lib/helpers.ts`) with no auth check. It deduplicates
  `(title, startsAt, venueId)` through the `by_title` index and takes real
  operator-supplied gig details. It is not a seeder and shares nothing with
  `seed:seedDemo`.
- The v1.14 widen phase mounts `@convex-dev/migrations` and keeps
  `migrations:backfillGigProjects` idempotent while old gig rows exist. Run it
  through the component runner after deploying the optional columns and new
  tables; verify completion before a later change tightens those optional
  fields. Historical one-shot mappings remain documented in
  [docs/history/legacy-mapping.md](history/legacy-mapping.md).
- The v1.15 widen phase adds idempotent
  `migrations:backfillBandHasClip` and
  `migrations:backfillGigDiscoveryListingReady`; the latter defaults missing
  projects or ambiguous legacy ownership to false. Run them after the gig
  project backfill through `migrations:runDiscoveryReadinessBackfills`, then
  verify completion before tightening both optional stored fields. See
  [docs/discovery-policy.md](discovery-policy.md) for the operational order.
