import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { QueryCtx, mutation, query } from "./_generated/server";
import {
  MAX_FEED_GIGS,
  MAX_PAST_GIGS,
  assertGigPublishable,
  bandPayloadValidator,
  feedCutoff,
  gigPublishFieldsValidator,
  gigPayloadValidator,
  insertPublishedGig,
  pastGigsForBand,
  requireBandAdmin,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";

type UpcomingGigs = {
  gigs: Doc<"gigs">[];
  nextStartsAt: number | null;
};

/** Gigs at or after the cutoff, ascending, plus the first omitted timestamp. */
async function upcomingGigs(ctx: QueryCtx): Promise<UpcomingGigs> {
  const rows = await ctx.db
    .query("gigs")
    .withIndex("by_startsAt", (q) => q.gte("startsAt", feedCutoff()))
    .order("asc")
    .take(MAX_FEED_GIGS + 1);
  return {
    gigs: rows.slice(0, MAX_FEED_GIGS),
    nextStartsAt: rows[MAX_FEED_GIGS]?.startsAt ?? null,
  };
}

/** Venue payloads for the ids a set of gigs referenced, skipping any venue that
 * has since been deleted. */
async function hydrateVenues(ctx: QueryCtx, venueIds: Set<Id<"venues">>) {
  const venues = [];
  for (const venueId of venueIds) {
    const venue = await ctx.db.get(venueId);
    if (venue) venues.push(toVenuePayload(venue));
  }
  return venues;
}

/** All gigs with startsAt >= now - 6h, ascending, plus every venue/band they
 * reference. Public — never throws. */
export const feed = query({
  args: {},
  returns: v.object({
    gigs: v.array(gigPayloadValidator),
    venues: v.array(venuePayloadValidator),
    bands: v.array(bandPayloadValidator),
    nextStartsAt: v.union(v.number(), v.null()),
  }),
  handler: async (ctx) => {
    const { gigs, nextStartsAt } = await upcomingGigs(ctx);

    const venueIds = new Set<Id<"venues">>();
    const bandIds = new Set<Id<"bands">>();
    for (const gig of gigs) {
      venueIds.add(gig.venueId);
      for (const bandId of gig.lineup) bandIds.add(bandId);
      if (gig.createdByBand) bandIds.add(gig.createdByBand);
    }

    const venues = await hydrateVenues(ctx, venueIds);
    const bands = [];
    for (const bandId of bandIds) {
      const band = await ctx.db.get(bandId);
      if (band) bands.push(await toBandPayload(ctx, band));
    }

    const gigPayloads = [];
    for (const gig of gigs) {
      gigPayloads.push(await toGigPayload(ctx, gig));
    }

    return { gigs: gigPayloads, venues, bands, nextStartsAt };
  },
});

/** Top-level array: upcoming gigs whose lineup contains bandId, ascending. */
export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(gigPayloadValidator),
  handler: async (ctx, args) => {
    const { gigs } = await upcomingGigs(ctx);
    const out = [];
    for (const gig of gigs) {
      if (gig.lineup.includes(args.bandId)) {
        out.push(await toGigPayload(ctx, gig));
      }
    }
    return out;
  },
});

/** Past gigs whose lineup contains bandId, newest first, with the venues they
 * reference so a profile can render date + place without a second round trip.
 *
 * `feed` and `forBand` both look forward from `now - 6h`, so before this the
 * only read path to a band's history was the denormalized `bands.pastShows`
 * strings — title and a short date, no venue, flyer or gig id. On a dataset
 * migrated from past events that left every gig unreachable.
 *
 * Read through `gigBands.by_band_startsAt`: this returns the band's own past
 * gigs, so how far back the history reaches no longer depends on how many
 * gigs other bands have published since. */
export const pastForBand = query({
  args: { bandId: v.id("bands") },
  returns: v.object({
    gigs: v.array(gigPayloadValidator),
    venues: v.array(venuePayloadValidator),
  }),
  handler: async (ctx, args) => {
    const past = await pastGigsForBand(ctx, args.bandId, MAX_PAST_GIGS);

    const gigs = [];
    const venueIds = new Set<Id<"venues">>();
    for (const gig of past) {
      gigs.push(await toGigPayload(ctx, gig));
      venueIds.add(gig.venueId);
    }

    return { gigs, venues: await hydrateVenues(ctx, venueIds) };
  },
});

export const publishGig = mutation({
  args: gigPublishFieldsValidator.fields,
  returns: v.object({ gigId: v.id("gigs") }),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const { band } = await assertGigPublishable(ctx, args);
    return { gigId: await insertPublishedGig(ctx, args, band) };
  },
});
