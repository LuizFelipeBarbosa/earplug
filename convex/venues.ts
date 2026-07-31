import { v } from "convex/values";
import { query } from "./_generated/server";
import { MAX_VENUES, toVenuePayload, venuePayloadValidator } from "./lib/helpers";

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
