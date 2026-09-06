import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { QueryCtx, mutation, query } from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";

const MAX_LOCATION_LABEL = 120;
const MAX_LOCATION_ADDRESS = 240;
const MAX_LOCATION_CITY = 120;
const MAX_LOCATION_AREA = 120;

export const privateLocationValidator = v.object({
  _id: v.id("privateLocations"),
  organizationId: v.id("organizations"),
  label: v.string(),
  addr: v.string(),
  city: v.string(),
  area: v.string(),
  lat: v.number(),
  lng: v.number(),
  notes: v.union(v.string(), v.null()),
  createdAt: v.number(),
  updatedAt: v.number(),
});

async function requireHostOrganization(
  ctx: QueryCtx,
  organizationId: Id<"organizations">,
) {
  const { organization } = await requireOrganizationRole(ctx, organizationId, [
    "owner",
  ]);
  if (organization.orgType !== "privateHost") {
    throw new Error("Only hosts keep private locations");
  }
  return organization;
}

function normalizeAndValidateLocation(
  fields: Pick<
    Doc<"privateLocations">,
    "label" | "addr" | "city" | "area" | "lat" | "lng"
  >,
) {
  const label = fields.label.trim();
  const addr = fields.addr.trim();
  const city = fields.city.trim();
  const area = fields.area.trim();
  for (const [name, value, maxLength] of [
    ["Label", label, MAX_LOCATION_LABEL],
    ["Address", addr, MAX_LOCATION_ADDRESS],
    ["City", city, MAX_LOCATION_CITY],
    ["Area", area, MAX_LOCATION_AREA],
  ] as const) {
    if (!value || value.length > maxLength) {
      throw new Error(`${name} must be between 1 and ${maxLength} characters`);
    }
  }
  if (!Number.isFinite(fields.lat) || fields.lat < -90 || fields.lat > 90) {
    throw new Error("Latitude must be between -90 and 90");
  }
  if (!Number.isFinite(fields.lng) || fields.lng < -180 || fields.lng > 180) {
    throw new Error("Longitude must be between -180 and 180");
  }
  return { label, addr, city, area, lat: fields.lat, lng: fields.lng };
}

export async function requireOwnedPrivateLocation(
  ctx: QueryCtx,
  locationId: Id<"privateLocations">,
  organizationId: Id<"organizations">,
): Promise<Doc<"privateLocations">> {
  const location = await ctx.db.get(locationId);
  if (!location || location.organizationId !== organizationId) {
    throw new Error("Choose a location");
  }
  return location;
}

export const create = mutation({
  args: {
    organizationId: v.id("organizations"),
    label: v.string(),
    addr: v.string(),
    city: v.string(),
    area: v.string(),
    lat: v.number(),
    lng: v.number(),
    notes: v.optional(v.string()),
  },
  returns: v.object({ locationId: v.id("privateLocations") }),
  handler: async (ctx, args) => {
    await requireHostOrganization(ctx, args.organizationId);
    const fields = normalizeAndValidateLocation(args);
    const now = Date.now();
    const locationId = await ctx.db.insert("privateLocations", {
      organizationId: args.organizationId,
      ...fields,
      notes: args.notes?.trim() || undefined,
      createdAt: now,
      updatedAt: now,
    });
    return { locationId };
  },
});

export const update = mutation({
  args: {
    locationId: v.id("privateLocations"),
    label: v.optional(v.string()),
    addr: v.optional(v.string()),
    city: v.optional(v.string()),
    area: v.optional(v.string()),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    notes: v.optional(v.union(v.string(), v.null())),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const location = await ctx.db.get(args.locationId);
    if (!location) throw new Error("Location not found");
    await requireHostOrganization(ctx, location.organizationId);
    const fields = normalizeAndValidateLocation({
      label: args.label ?? location.label,
      addr: args.addr ?? location.addr,
      city: args.city ?? location.city,
      area: args.area ?? location.area,
      lat: args.lat ?? location.lat,
      lng: args.lng ?? location.lng,
    });
    await ctx.db.patch(args.locationId, {
      ...fields,
      ...(args.notes !== undefined
        ? { notes: args.notes?.trim() || undefined }
        : {}),
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const remove = mutation({
  args: { locationId: v.id("privateLocations") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const location = await ctx.db.get(args.locationId);
    if (!location) throw new Error("Location not found");
    await requireHostOrganization(ctx, location.organizationId);
    for (const status of [
      "draft",
      "open",
      "applications_closed",
      "booking",
      "confirmed",
    ] as const) {
      const opportunity = await ctx.db
        .query("talentOpportunities")
        .withIndex("by_organizationId_and_status", (q) =>
          q.eq("organizationId", location.organizationId).eq("status", status),
        )
        .filter((q) => q.eq(q.field("privateLocationId"), args.locationId))
        .first();
      if (opportunity) throw new Error("Location is in use");
    }
    await ctx.db.delete(args.locationId);
    return null;
  },
});

export const forOrganization = query({
  args: { organizationId: v.id("organizations") },
  returns: v.array(privateLocationValidator),
  handler: async (ctx, args) => {
    await requireHostOrganization(ctx, args.organizationId);
    const locations = await ctx.db
      .query("privateLocations")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .take(200);
    return locations.map(({ _creationTime, ...location }) => ({
      ...location,
      notes: location.notes ?? null,
    }));
  },
});
