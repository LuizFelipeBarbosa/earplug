import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { QueryCtx, mutation, query } from "./_generated/server";
import {
  FEED_GRACE_MS,
  MAX_FEED_GIGS,
  MAX_PAST_GIGS,
  assertGigPublishable,
  bandPayloadValidator,
  gigPublishFieldsValidator,
  gigPayloadValidator,
  insertPublishedGig,
  requireBandAdmin,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";

/** The instant that divides "upcoming" from "past". Every feed-shaped read
 * derives from it so they share one grace window — but each query execution
 * takes its own reading, so a gig sitting right on the boundary can still be
 * upcoming to one query and past to another.
 *
 * Known staleness, deferred for v1: Date.now() is captured when the query
 * executes, and a cached result only recomputes when something writes to the
 * range it read — so on a quiet deployment a gig can linger past the 6h grace.
 * Pre-launch fix: a cron heartbeat that writes the current hour's cutoff to a
 * singleton doc this reads instead of the clock. */
function feedCutoff(): number {
  return Date.now() - FEED_GRACE_MS;
}

/** Gigs at or after the cutoff, ascending. */
async function upcomingGigs(ctx: QueryCtx): Promise<Doc<"gigs">[]> {
  return await ctx.db
    .query("gigs")
    .withIndex("by_startsAt", (q) => q.gte("startsAt", feedCutoff()))
    .order("asc")
    .take(MAX_FEED_GIGS);
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
  }),
  handler: async (ctx) => {
    const gigs = await upcomingGigs(ctx);

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

    return { gigs: gigPayloads, venues, bands };
  },
});

/** Top-level array: upcoming gigs whose lineup contains bandId, ascending. */
export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(gigPayloadValidator),
  handler: async (ctx, args) => {
    const gigs = await upcomingGigs(ctx);
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
 * migrated from past events that left every gig unreachable. */
export const pastForBand = query({
  args: { bandId: v.id("bands") },
  returns: v.object({
    gigs: v.array(gigPayloadValidator),
    venues: v.array(venuePayloadValidator),
  }),
  handler: async (ctx, args) => {
    const recent = await ctx.db
      .query("gigs")
      .withIndex("by_startsAt", (q) => q.lt("startsAt", feedCutoff()))
      .order("desc")
      .take(MAX_PAST_GIGS);

    const gigs = [];
    const venueIds = new Set<Id<"venues">>();
    for (const gig of recent) {
      if (!gig.lineup.includes(args.bandId)) continue;
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
