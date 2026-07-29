import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { QueryCtx, mutation, query } from "./_generated/server";
import {
  FEED_GRACE_MS,
  MAX_FEED_GIGS,
  bandPayloadValidator,
  flyKeyValidator,
  gigPayloadValidator,
  requireBandAdmin,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";

/** Known staleness, deferred for v1: Date.now() is captured when the query
 * executes, and cached results only recompute on writes to the gigs range this
 * reads — so a gig can linger past the 6h grace until the next gig is published
 * (RSVPs write `interactions` and do not invalidate this). Pre-launch fix: a
 * cron heartbeat that writes the current hour cutoff to a singleton doc which
 * this function reads instead of the clock. */
async function upcomingGigs(ctx: QueryCtx): Promise<Doc<"gigs">[]> {
  const cutoff = Date.now() - FEED_GRACE_MS;
  return await ctx.db
    .query("gigs")
    .withIndex("by_startsAt", (q) => q.gte("startsAt", cutoff))
    .order("asc")
    .take(MAX_FEED_GIGS);
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

    const venues = [];
    for (const venueId of venueIds) {
      const venue = await ctx.db.get(venueId);
      if (venue) venues.push(toVenuePayload(venue));
    }
    const bands = [];
    for (const bandId of bandIds) {
      const band = await ctx.db.get(bandId);
      if (band) bands.push(toBandPayload(band));
    }

    return { gigs: gigs.map(toGigPayload), venues, bands };
  },
});

/** Top-level array: upcoming gigs whose lineup contains bandId, ascending. */
export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(gigPayloadValidator),
  handler: async (ctx, args) => {
    const gigs = await upcomingGigs(ctx);
    return gigs
      .filter((gig) => gig.lineup.includes(args.bandId))
      .map(toGigPayload);
  },
});

export const publishGig = mutation({
  args: {
    bandId: v.id("bands"),
    title: v.string(),
    startsAt: v.number(),
    doorsTime: v.string(),
    venueId: v.id("venues"),
    price: v.number(),
    flyKey: flyKeyValidator,
    ticketing: v.union(v.literal("rsvp"), v.literal("external")),
    externalUrl: v.optional(v.string()),
    cap: v.string(),
  },
  returns: v.object({ gigId: v.id("gigs") }),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    if (!Number.isFinite(args.startsAt) || args.startsAt < 0) {
      throw new Error("Invalid startsAt");
    }
    if (!Number.isFinite(args.price) || args.price < 0) {
      throw new Error("Invalid price");
    }
    if (
      args.ticketing === "external" &&
      (!args.externalUrl || !/^https?:\/\//.test(args.externalUrl))
    ) {
      throw new Error("External ticketing requires a valid http(s) URL");
    }
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    const band = await ctx.db.get(args.bandId);
    if (!band) throw new Error("Band not found");

    const gigId = await ctx.db.insert("gigs", {
      title: args.title,
      venueId: args.venueId,
      price: args.price,
      startsAt: args.startsAt,
      doorsTime: args.doorsTime,
      flyKey: args.flyKey,
      lineup: [args.bandId],
      genres: band.genres,
      desc: "",
      ticketing: args.ticketing,
      ...(args.ticketing === "external" && args.externalUrl !== undefined
        ? { externalUrl: args.externalUrl }
        : {}),
      cap: args.cap,
      goingCount: 0,
      createdByBand: args.bandId,
    });
    return { gigId };
  },
});
