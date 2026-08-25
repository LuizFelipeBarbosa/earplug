import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { query } from "./_generated/server";
import {
  bandPayloadValidator,
  feedCutoff,
  gigPayloadValidator,
  MAX_VENUES,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";

const MAX_VENUE_GIGS = 200;

/** Every venue, name-ordered.
 *
 * Venues had no query of their own: they reached the client only bundled
 * inside `gigs:feed`, so a venue no upcoming gig referenced could not be read
 * at all. Public and unauthenticated — a venue is a name and a street address.
 *
 * The table is a small curated list rather than user-generated, so a single
 * capped read returns all of it. */
export const list = query({
  args: {},
  returns: v.array(venuePayloadValidator),
  handler: async (ctx) => {
    const venues = await ctx.db
      .query("venues")
      .withIndex("by_name")
      .order("asc")
      .take(MAX_VENUES);
    return venues.map(toVenuePayload);
  },
});

/** One venue with its next 200 chronological gigs and the unique performers
 * referenced by those gigs. Uses the same six-hour grace window as the feed,
 * so a card does not disappear when a visitor moves between discovery views. */
export const detail = query({
  args: { venueId: v.id("venues") },
  returns: v.union(
    v.object({
      venue: venuePayloadValidator,
      gigs: v.array(gigPayloadValidator),
      bands: v.array(bandPayloadValidator),
      truncated: v.boolean(),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (venue === null) return null;

    const rows = await ctx.db
      .query("gigs")
      .withIndex("by_venueId_and_startsAt", (q) =>
        q.eq("venueId", args.venueId).gte("startsAt", feedCutoff()),
      )
      .order("asc")
      .take(MAX_VENUE_GIGS * 4 + 1);
    const visible = rows.filter(
      (gig) => (gig.lifecycle ?? "published") === "published",
    );
    const venueGigs = visible.slice(0, MAX_VENUE_GIGS);

    const bandIds = new Set<Id<"bands">>();
    const gigs = [];
    for (const gig of venueGigs) {
      gigs.push(await toGigPayload(ctx, gig));
      for (const bandId of gig.lineup) bandIds.add(bandId);
    }

    const bands = [];
    for (const bandId of bandIds) {
      const band = await ctx.db.get(bandId);
      if (band) bands.push(await toBandPayload(ctx, band));
    }

    return {
      venue: toVenuePayload(venue),
      gigs,
      bands,
      truncated: visible.length > MAX_VENUE_GIGS,
    };
  },
});
