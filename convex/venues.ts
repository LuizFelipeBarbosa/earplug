import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { docCache } from "./lib/docCache";
import {
  bandPayloadValidator,
  feedCutoff,
  gigPayloadValidator,
  MAX_VENUES,
  requireBandRole,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";

const MAX_VENUE_GIGS = 200;
const MAX_VENUE_NAME = 120;
const MAX_VENUE_AREA = 120;
const MAX_VENUE_ADDRESS = 240;
const SF_CENTER = { lat: 37.7599, lng: -122.4148 };
const OAK_CENTER = { lat: 37.8378, lng: -122.2628 };

export function normalizeVenueText(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

function milesBetween(
  from: { lat: number; lng: number },
  to: { lat: number; lng: number },
) {
  const radians = (degrees: number) => (degrees * Math.PI) / 180;
  const earthMiles = 3958.7613;
  const dLat = radians(to.lat - from.lat);
  const dLng = radians(to.lng - from.lng);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(from.lat)) *
      Math.cos(radians(to.lat)) *
      Math.sin(dLng / 2) ** 2;
  return earthMiles * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export const create = mutation({
  args: {
    bandId: v.id("bands"),
    name: v.string(),
    area: v.string(),
    addr: v.string(),
    lat: v.number(),
    lng: v.number(),
  },
  returns: v.object({ venue: venuePayloadValidator, created: v.boolean() }),
  handler: async (ctx, args) => {
    const { user } = await requireBandRole(ctx, args.bandId, { role: "admin" });
    const name = args.name.trim();
    const area = args.area.trim();
    const addr = args.addr.trim();
    if (!name || !area || !addr) throw new Error("Venue details are required");
    if (name.length > MAX_VENUE_NAME) throw new Error("Venue name is too long");
    if (area.length > MAX_VENUE_AREA) throw new Error("Venue area is too long");
    if (addr.length > MAX_VENUE_ADDRESS) throw new Error("Venue address is too long");
    if (
      !Number.isFinite(args.lat) ||
      !Number.isFinite(args.lng) ||
      args.lat < -90 ||
      args.lat > 90 ||
      args.lng < -180 ||
      args.lng > 180
    ) {
      throw new Error("Choose a valid map location");
    }

    const normalizedName = normalizeVenueText(name);
    const normalizedAddr = normalizeVenueText(addr);
    let existing = await ctx.db
      .query("venues")
      .withIndex("by_normalizedAddr", (q) =>
        q.eq("normalizedAddr", normalizedAddr),
      )
      .first();
    if (!existing) {
      const sameName = await ctx.db
        .query("venues")
        .withIndex("by_normalizedName", (q) =>
          q.eq("normalizedName", normalizedName),
        )
        .take(20);
      existing =
        sameName.find(
          (venue) => normalizeVenueText(venue.area) === normalizeVenueText(area),
        ) ?? null;
    }
    if (existing) return { venue: toVenuePayload(existing), created: false };

    const point = { lat: args.lat, lng: args.lng };
    const venueId = await ctx.db.insert("venues", {
      name,
      area,
      addr,
      normalizedName,
      normalizedAddr,
      createdBy: user._id,
      createdByBand: args.bandId,
      distSF: `${milesBetween(SF_CENTER, point).toFixed(1)} mi`,
      distOak: `${milesBetween(OAK_CENTER, point).toFixed(1)} mi`,
      lat: args.lat,
      lng: args.lng,
    });
    const venue = await ctx.db.get(venueId);
    if (!venue) throw new Error("Created venue not found");
    return { venue: toVenuePayload(venue), created: true };
  },
});

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
    // A venue's gigs are mostly created by a few bands that also play them,
    // so owner and lineup reads share one memo across both loops below.
    const cache = docCache(ctx);
    const visible = [];
    for (const gig of rows) {
      if ((gig.lifecycle ?? "published") !== "published") continue;
      if (gig.createdByBand) {
        const owner = await cache.get(gig.createdByBand);
        if (!owner || owner.archivedAt !== undefined) continue;
      }
      visible.push(gig);
    }
    const venueGigs = visible.slice(0, MAX_VENUE_GIGS);

    const bandIds = new Set<Id<"bands">>();
    const gigs = [];
    for (const gig of venueGigs) {
      gigs.push(await toGigPayload(ctx, gig));
      for (const bandId of gig.lineup) bandIds.add(bandId);
    }

    const bands = [];
    for (const bandId of bandIds) {
      const band = await cache.get(bandId);
      if (band && band.archivedAt === undefined) {
        bands.push(await toBandPayload(ctx, band));
      }
    }

    return {
      venue: toVenuePayload(venue),
      gigs,
      bands,
      truncated: visible.length > MAX_VENUE_GIGS,
    };
  },
});
