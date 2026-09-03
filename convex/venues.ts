import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, mutation, query } from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";
import { docCache } from "./lib/docCache";
import {
  approximateLocation,
  formatMiles,
  OAK_CENTER,
  SF_CENTER,
} from "./lib/geo";
import {
  assertUploadAcceptable,
  bandPayloadValidator,
  currentUser,
  effectiveAddressDisclosure,
  feedCutoff,
  gigPayloadValidator,
  MAX_VENUES,
  requireBandRole,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";
import {
  readVenuePrivateFor,
  toVenuePrivatePayload,
  venuePrivatePayloadValidator,
} from "./lib/venuePrivate";
import { uniqueVenueSlug } from "./lib/venueSlug";
import { addressDisclosureValidator, venueTypeValidator } from "./schema";

const MAX_VENUE_GIGS = 200;
const MAX_VENUE_NAME = 120;
const MAX_VENUE_AREA = 120;
const MAX_VENUE_ADDRESS = 240;
const MAX_VENUE_DESCRIPTION = 1_000;
const MAX_VENUE_LOCATION_LABEL = 80;
const MAX_VENUE_CAPACITY = 100_000;

export function normalizeVenueText(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
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
    if (addr.length > MAX_VENUE_ADDRESS)
      throw new Error("Venue address is too long");
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
          (venue) =>
            normalizeVenueText(venue.area) === normalizeVenueText(area),
        ) ?? null;
    }
    if (existing) {
      return { venue: toVenuePayload(existing), created: false };
    }

    const point = { lat: args.lat, lng: args.lng };
    const approx = approximateLocation(point, area);
    const slug = await uniqueVenueSlug(ctx, name);
    const venueId = await ctx.db.insert("venues", {
      name,
      area,
      addr,
      normalizedName,
      normalizedAddr,
      createdBy: user._id,
      createdByBand: args.bandId,
      distSF: formatMiles(SF_CENTER, point),
      distOak: formatMiles(OAK_CENTER, point),
      lat: args.lat,
      lng: args.lng,
      slug,
      status: "legacy",
      approxLat: approx.lat,
      approxLng: approx.lng,
      approxLabel: approx.label,
      ...(approx.neighborhood === null
        ? {}
        : { neighborhood: approx.neighborhood }),
      ...(approx.city === null ? {} : { city: approx.city }),
    });
    await ctx.db.insert("venuePrivateDetails", {
      venueId,
      addr,
      lat: args.lat,
      lng: args.lng,
      normalizedAddr,
      updatedAt: Date.now(),
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
 * The user- and organization-generated list is capped pending pagination. */
export const list = query({
  args: {},
  returns: v.array(venuePayloadValidator),
  handler: async (ctx) => {
    const venues = await ctx.db
      .query("venues")
      .withIndex("by_name")
      .order("asc")
      .take(MAX_VENUES);
    return venues
      .filter((venue) => venue.status !== "suspended")
      .map(toVenuePayload);
  },
});

export const resolvePublic = query({
  args: { ref: v.string() },
  returns: v.union(venuePayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const ref = args.ref.trim();
    if (ref === "" || ref.length > 200) return null;
    let venue = await ctx.db
      .query("venues")
      .withIndex("by_slug", (q) => q.eq("slug", ref))
      .first();
    if (!venue) {
      const normalized = ctx.db.normalizeId("venues", ref);
      venue = normalized ? await ctx.db.get(normalized) : null;
    }
    if (!venue || venue.status === "suspended") return null;
    return toVenuePayload(venue);
  },
});

export const privateDetail = query({
  args: { venueId: v.id("venues") },
  returns: v.union(venuePrivatePayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) return null;
    const result = await readVenuePrivateFor(
      ctx,
      venue,
      await currentUser(ctx),
    );
    return result
      ? toVenuePrivatePayload(result.details, result.operational)
      : null;
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
    if (venue === null || venue.status === "suspended") return null;

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
      gigs.push(await toGigPayload(ctx, gig, cache));
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

export const updateProfile = mutation({
  args: {
    venueId: v.id("venues"),
    name: v.optional(v.string()),
    description: v.optional(v.string()),
    venueType: v.optional(venueTypeValidator),
    capacityPublic: v.optional(v.number()),
    neighborhood: v.optional(v.string()),
    city: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId === undefined) {
      throw new Error("Venue is not managed by an organization");
    }
    await requireOrganizationRole(ctx, venue.managedByOrganizationId, [
      "owner",
      "manager",
    ]);

    const patch: {
      name?: string;
      normalizedName?: string;
      description?: string;
      venueType?: Doc<"venues">["venueType"];
      capacityPublic?: number;
      neighborhood?: string;
      city?: string;
      approxLabel?: string;
      area?: string;
      addr?: string;
    } = {};
    if (args.name !== undefined) {
      const name = args.name.trim();
      if (name === "") throw new Error("Venue name is required");
      if (name.length > MAX_VENUE_NAME)
        throw new Error("Venue name is too long");
      patch.name = name;
      patch.normalizedName = normalizeVenueText(name);
    }
    if (args.description !== undefined) {
      const description = args.description.trim();
      if (description.length > MAX_VENUE_DESCRIPTION) {
        throw new Error("Venue description is too long");
      }
      patch.description = description;
    }
    if (args.venueType !== undefined) patch.venueType = args.venueType;
    if (args.capacityPublic !== undefined) {
      if (
        !Number.isInteger(args.capacityPublic) ||
        args.capacityPublic < 0 ||
        args.capacityPublic > MAX_VENUE_CAPACITY
      ) {
        throw new Error("Venue capacity must be an integer from 0 to 100000");
      }
      patch.capacityPublic = args.capacityPublic;
    }

    // Blank location labels are rejected because clearing only one side would
    // leave the derived neighborhood/city label inconsistent.
    if (args.neighborhood !== undefined) {
      const neighborhood = args.neighborhood.trim();
      if (neighborhood === "")
        throw new Error("Venue neighborhood is required");
      if (neighborhood.length > MAX_VENUE_LOCATION_LABEL) {
        throw new Error("Venue neighborhood is too long");
      }
      patch.neighborhood = neighborhood;
    }
    if (args.city !== undefined) {
      const city = args.city.trim();
      if (city === "") throw new Error("Venue city is required");
      if (city.length > MAX_VENUE_LOCATION_LABEL) {
        throw new Error("Venue city is too long");
      }
      patch.city = city;
    }

    if (
      args.name !== undefined ||
      args.neighborhood !== undefined ||
      args.city !== undefined
    ) {
      const neighborhood = patch.neighborhood ?? venue.neighborhood?.trim();
      const city = patch.city ?? venue.city?.trim();
      if (neighborhood && city) {
        const approxLabel = `${neighborhood}, ${city}`;
        patch.approxLabel = approxLabel;
        if (effectiveAddressDisclosure(venue) !== "public") {
          patch.area = approxLabel;
          patch.addr = approxLabel;
        }
      }
    }

    if (Object.keys(patch).length > 0) {
      await ctx.db.patch(args.venueId, patch);
    }
    return null;
  },
});

export const updatePrivateDetails = mutation({
  args: {
    venueId: v.id("venues"),
    addr: v.string(),
    lat: v.number(),
    lng: v.number(),
    loadInNotes: v.optional(v.string()),
    capacity: v.optional(v.number()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId === undefined) {
      throw new Error("Venue is not managed by an organization");
    }
    await requireOrganizationRole(ctx, venue.managedByOrganizationId, [
      "owner",
      "manager",
    ]);

    const addr = args.addr.trim();
    if (addr === "") throw new Error("Venue address is required");
    if (addr.length > MAX_VENUE_ADDRESS)
      throw new Error("Venue address is too long");
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
    const loadInNotes = args.loadInNotes?.trim();
    if (
      loadInNotes !== undefined &&
      loadInNotes.length > MAX_VENUE_DESCRIPTION
    ) {
      throw new Error("Load-in notes are too long");
    }
    if (args.capacity !== undefined) {
      if (
        !Number.isInteger(args.capacity) ||
        args.capacity < 0 ||
        args.capacity > MAX_VENUE_CAPACITY
      ) {
        throw new Error("Venue capacity must be an integer from 0 to 100000");
      }
    }

    const normalizedAddr = normalizeVenueText(addr);
    const addressMatches = await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_normalizedAddr", (q) =>
        q.eq("normalizedAddr", normalizedAddr),
      )
      .take(2);
    if (addressMatches.some((match) => match.venueId !== args.venueId)) {
      throw new Error("Another venue already uses that address");
    }

    // `venueId` uniqueness is enforced only by write paths, not the schema, so
    // a buggy writer could introduce duplicates and make this `.unique()` throw.
    const existing = await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", args.venueId))
      .unique();
    const detailsPatch = {
      addr,
      lat: args.lat,
      lng: args.lng,
      normalizedAddr,
      ...(args.loadInNotes === undefined
        ? {}
        : { loadInNotes: loadInNotes || undefined }),
      ...(args.capacity === undefined ? {} : { capacity: args.capacity }),
      updatedAt: Date.now(),
    };
    if (existing) {
      await ctx.db.patch(existing._id, detailsPatch);
    } else {
      await ctx.db.insert("venuePrivateDetails", {
        venueId: args.venueId,
        ...detailsPatch,
      });
    }

    const fallbackLabel =
      venue.approxLabel ??
      (venue.neighborhood !== undefined && venue.city !== undefined
        ? `${venue.neighborhood}, ${venue.city}`
        : venue.area);
    const approx = approximateLocation(
      { lat: args.lat, lng: args.lng },
      fallbackLabel,
    );
    await ctx.db.patch(args.venueId, {
      approxLat: approx.lat,
      approxLng: approx.lng,
      approxLabel: approx.label,
      ...(approx.neighborhood === null
        ? {}
        : { neighborhood: approx.neighborhood }),
      ...(approx.city === null ? {} : { city: approx.city }),
    });
    await rewriteDisclosablePublicColumns(ctx, args.venueId, {
      addr,
      lat: args.lat,
      lng: args.lng,
    });
    return null;
  },
});

export const setAddressDisclosure = mutation({
  args: {
    venueId: v.id("venues"),
    addressDisclosure: addressDisclosureValidator,
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId === undefined) {
      throw new Error("Venue is not managed by an organization");
    }
    await requireOrganizationRole(ctx, venue.managedByOrganizationId, [
      "owner",
    ]);
    // `venueId` uniqueness is enforced only by write paths, not the schema, so
    // a buggy writer could introduce duplicates and make this `.unique()` throw.
    const privateDetails = await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", args.venueId))
      .unique();
    if (!privateDetails)
      throw new Error("Venue has no private location on file");

    await ctx.db.patch(args.venueId, {
      addressDisclosure: args.addressDisclosure,
    });
    await rewriteDisclosablePublicColumns(ctx, args.venueId, privateDetails);
    return null;
  },
});

export const generatePhotoUploadUrl = mutation({
  args: { venueId: v.id("venues") },
  returns: v.string(),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId === undefined) {
      throw new Error("Venue is not managed by an organization");
    }
    await requireOrganizationRole(ctx, venue.managedByOrganizationId, [
      "owner",
      "manager",
    ]);
    return await ctx.storage.generateUploadUrl();
  },
});

export const setPhotos = mutation({
  args: {
    venueId: v.id("venues"),
    storageIds: v.array(v.id("_storage")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const venue = await ctx.db.get(args.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId === undefined) {
      throw new Error("Venue is not managed by an organization");
    }
    await requireOrganizationRole(ctx, venue.managedByOrganizationId, [
      "owner",
      "manager",
    ]);
    if (args.storageIds.length > 10) {
      throw new Error("A venue can have at most 10 photos.");
    }
    for (const storageId of args.storageIds) {
      const upload = await ctx.db.system.get("_storage", storageId);
      if (!upload) throw new Error("Upload not found");
      assertUploadAcceptable(
        { size: upload.size, contentType: upload.contentType },
        "photo",
      );
    }
    await ctx.db.patch(args.venueId, { photoStorageIds: args.storageIds });
    return null;
  },
});

async function rewriteDisclosablePublicColumns(
  ctx: MutationCtx,
  venueId: Id<"venues">,
  privateDetails: Pick<Doc<"venuePrivateDetails">, "addr" | "lat" | "lng">,
): Promise<void> {
  const venue = await ctx.db.get(venueId);
  if (!venue) throw new Error("Venue not found");

  if (effectiveAddressDisclosure(venue) === "public") {
    const point = { lat: privateDetails.lat, lng: privateDetails.lng };
    await ctx.db.patch(venueId, {
      addr: privateDetails.addr,
      normalizedAddr: normalizeVenueText(privateDetails.addr),
      lat: privateDetails.lat,
      lng: privateDetails.lng,
      distSF: formatMiles(SF_CENTER, point),
      distOak: formatMiles(OAK_CENTER, point),
    });
    return;
  }

  if (
    venue.approxLabel === undefined ||
    venue.approxLat === undefined ||
    venue.approxLng === undefined
  ) {
    throw new Error("Venue has no approximate location on file");
  }
  const point = { lat: venue.approxLat, lng: venue.approxLng };
  await ctx.db.patch(venueId, {
    addr: venue.approxLabel,
    normalizedAddr: undefined,
    lat: venue.approxLat,
    lng: venue.approxLng,
    distSF: formatMiles(SF_CENTER, point),
    distOak: formatMiles(OAK_CENTER, point),
  });
}
