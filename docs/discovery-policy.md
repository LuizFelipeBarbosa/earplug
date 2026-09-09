# Discovery progression policy

This document is the canonical policy for EarPlug's organic discovery reward.
The product term is **progressive activation**: bands unlock additional
discovery treatment by completing transparent, attainable listing-quality
steps. It does not mean round-robin distribution, guaranteed impressions, or
an opaque ranking tier. The earlier, undefined “Robin structure” wording is
retired.

## Eligibility

A band profile is complete only when it has a nonblank name, one to three
nonblank genres, a nonblank home area, and a nonblank bio. The public
`PROFILE COMPLETE` badge reflects this derived state and disappears whenever
the profile no longer meets it.

A band is discovery-profile-ready when its complete profile also has:

- an assigned, live profile-image upload accepted by the existing image rules;
- at least one valid uploaded video clip. External music links do not count.

A published show is discovery-listing-ready when:

- the creating band is represented in the lineup;
- no performer invitation remains unresolved (`kind == "invited"`); text-only
  performers are allowed;
- its venue exists;
- it uses a built-in poster, or a live custom poster with its readable overlay
  enabled; and
- the public projection represents the current project revision.

Saving a published project or changing its performers immediately makes the
listing projection stale. Republishing is the only operation that can restore
listing readiness. Missing or ambiguous legacy data always fails closed.

## Timing and anti-flood rule

An otherwise eligible show can boost from exactly seven days before its start
through exactly six hours after its start, matching the public feed's existing
post-show grace. A band can have only one boosted show at a time: choose its
earliest active qualifying show. A later legitimate show may boost after the
earlier window ends.

The boost window's six-hour post-show grace boundary uses the same shared
`feedCutoff` instant as gigs and opportunities. A 15-minute cron heartbeat
(`convex/clock.ts`) keeps it fresh by writing to a `clock` singleton row,
instead of each query reading the wall clock directly. Those writes invalidate
cached query results so they cannot linger indefinitely past the boundary on
a quiet deployment. Only before the very first heartbeat ever runs, while
the row does not yet exist, does the read fall back to the wall clock.

## Ranking cap and labeling

Filters run first. The client establishes its normal nearest-first result,
then changes only positions occupied by shows that share both:

- the same `America/Los_Angeles` calendar day; and
- the same five-mile distance bucket (`0–<5`, `5–<10`, and so on).

Within that peer group, boosted shows lead, followed by actual distance and
start time. Stable input order breaks an exact tie. A boost cannot cross a day,
cross a distance bucket, bypass a filter, or add another card to the feed.

Every active reward is labeled exactly
`DISCOVERY BOOST · COMPLETE LISTING`. It is an organic completeness reward,
not sponsorship or paid placement.

## Exclusions

This policy does not change typed search, name-ordered band browsing, featured
collections, sponsorships, or paid promotion.

## Widen–migrate–narrow rollout

The widen deploy kept `bands.hasClip` and `gigs.discoveryListingReady`
optional so absent values read as ineligible. The discovery-readiness backfills
completed on production on 2026-09-04, so every row now carries its projection,
maintained by live writes. The migration functions and operational commands
have been removed now that the rollout is finished; the fields remain optional
pending a separate narrowing change.
