import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, QueryCtx, mutation, query } from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  requireOrganizationRole,
  requireOrganizationRoleQuery,
} from "./lib/authz";
import {
  assertUploadAcceptable,
  currentUser,
  isValidHttpsUrl,
  toVenuePayload,
  venuePayloadValidator,
} from "./lib/helpers";
import {
  organizationRoleValidator,
  organizationStatusValidator,
  organizationTypeValidator,
} from "./schema";

export const organizationPayloadValidator = v.object({
  _id: v.id("organizations"),
  slug: v.string(),
  name: v.string(),
  orgType: organizationTypeValidator,
  status: organizationStatusValidator,
  verified: v.boolean(),
  description: v.union(v.string(), v.null()),
  website: v.union(v.string(), v.null()),
  photoUrls: v.array(v.string()),
  createdAt: v.number(),
});

export async function toOrganizationPayload(
  ctx: QueryCtx,
  organization: Doc<"organizations">,
): Promise<Infer<typeof organizationPayloadValidator>> {
  const photoUrls: string[] = [];
  for (const storageId of organization.photoStorageIds ?? []) {
    const url = await ctx.storage.getUrl(storageId);
    if (url !== null) photoUrls.push(url);
  }
  return {
    _id: organization._id,
    slug: organization.slug,
    name: organization.name,
    orgType: organization.orgType,
    status: organization.status,
    verified: organization.status === "verified",
    description: organization.description ?? null,
    website: organization.website ?? null,
    photoUrls,
    createdAt: organization.createdAt,
  };
}

const membershipPayloadValidator = v.object({
  organization: organizationPayloadValidator,
  role: organizationRoleValidator,
});

export const mine = query({
  args: {},
  returns: v.array(membershipPayloadValidator),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const memberships = await ctx.db
      .query("organizationMembers")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .take(50);
    const result = [];
    for (const membership of memberships) {
      const organization = await ctx.db.get(membership.organizationId);
      if (organization !== null) {
        result.push({
          organization: await toOrganizationPayload(ctx, organization),
          role: membership.role,
        });
      }
    }
    return result;
  },
});

export const bySlug = query({
  args: { slug: v.string() },
  returns: v.union(organizationPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const organization = await ctx.db
      .query("organizations")
      .withIndex("by_slug", (q) => q.eq("slug", args.slug))
      .first();
    return organization === null || organization.status === "suspended"
      ? null
      : await toOrganizationPayload(ctx, organization);
  },
});

export const get = query({
  args: { organizationId: v.id("organizations") },
  returns: v.union(organizationPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const organization = await ctx.db.get(args.organizationId);
    return organization === null || organization.status === "suspended"
      ? null
      : await toOrganizationPayload(ctx, organization);
  },
});

const dashboardValidator = v.object({
  organization: organizationPayloadValidator,
  role: v.union(organizationRoleValidator, v.null()),
  viaPlatformAdmin: v.boolean(),
  verification: v.object({
    verified: v.boolean(),
    stripeDetailsSubmitted: v.boolean(),
    stripeChargesEnabled: v.boolean(),
    stripePayoutsEnabled: v.boolean(),
    profileComplete: v.boolean(),
    teamInvited: v.boolean(),
  }),
  venues: v.array(venuePayloadValidator),
  memberCount: v.number(),
  privateDetails: v.union(
    v.object({
      legalName: v.union(v.string(), v.null()),
      businessEmail: v.string(),
      contactName: v.string(),
      phone: v.union(v.string(), v.null()),
    }),
    v.null(),
  ),
});

export const dashboard = query({
  args: { organizationId: v.id("organizations") },
  returns: dashboardValidator,
  handler: async (ctx, args) => {
    const access = await requireOrganizationRoleQuery(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const [privateDetails, venues, members] = await Promise.all([
      ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", args.organizationId),
        )
        .unique(),
      ctx.db
        .query("venues")
        .withIndex("by_managedByOrganizationId", (q) =>
          q.eq("managedByOrganizationId", args.organizationId),
        )
        .take(50),
      ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q.eq("organizationId", args.organizationId),
        )
        .take(101),
    ]);
    const role = access.membership?.role ?? null;
    return {
      organization: await toOrganizationPayload(ctx, access.organization),
      role,
      viaPlatformAdmin: access.viaPlatformAdmin,
      verification: {
        verified: access.organization.status === "verified",
        stripeDetailsSubmitted:
          privateDetails?.stripeDetailsSubmitted ?? false,
        stripeChargesEnabled: privateDetails?.stripeChargesEnabled ?? false,
        stripePayoutsEnabled: privateDetails?.stripePayoutsEnabled ?? false,
        profileComplete:
          access.organization.name.trim() !== "" &&
          (access.organization.description?.trim() ?? "") !== "" &&
          (access.organization.photoStorageIds?.length ?? 0) >= 1,
        teamInvited: members.length >= 2,
      },
      venues: venues.map(toVenuePayload),
      memberCount: Math.min(members.length, 100),
      privateDetails:
        role === "door" || privateDetails === null
          ? null
          : {
              legalName: privateDetails.legalName ?? null,
              businessEmail: privateDetails.businessEmail,
              contactName: privateDetails.contactName,
              phone: privateDetails.phone ?? null,
            },
    };
  },
});

export const updateProfile = mutation({
  args: {
    organizationId: v.id("organizations"),
    name: v.optional(v.string()),
    description: v.optional(v.string()),
    website: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
      "manager",
    ]);
    if (
      args.name === undefined &&
      args.description === undefined &&
      args.website === undefined
    ) {
      return null;
    }

    const patch: {
      name?: string;
      description?: string;
      website?: string;
      updatedAt: number;
    } = { updatedAt: Date.now() };
    if (args.name !== undefined) {
      const name = args.name.trim();
      if (!name) throw new Error("Organization name is required");
      if (name.length > 120) throw new Error("Organization name is too long");
      patch.name = name;
    }
    if (args.description !== undefined) {
      const description = args.description.trim();
      if (description.length > 1000) {
        throw new Error("Organization description is too long");
      }
      patch.description = description || undefined;
    }
    if (args.website !== undefined) {
      const website = args.website.trim();
      if (website.length > 200) throw new Error("Website is too long");
      if (website && !isValidHttpsUrl(website)) {
        throw new Error("Website must be a valid HTTPS URL");
      }
      patch.website = website || undefined;
    }
    await ctx.db.patch(args.organizationId, patch);
    return null;
  },
});

export const updatePrivateDetails = mutation({
  args: {
    organizationId: v.id("organizations"),
    legalName: v.optional(v.string()),
    businessEmail: v.optional(v.string()),
    contactName: v.optional(v.string()),
    phone: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, ["owner"]);
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    if (details === null) throw new Error("Organization details not found");

    const patch: {
      legalName?: string;
      businessEmail?: string;
      contactName?: string;
      phone?: string;
      updatedAt: number;
    } = { updatedAt: Date.now() };
    if (args.businessEmail !== undefined) {
      const businessEmail = args.businessEmail.trim();
      if (!businessEmail || !businessEmail.includes("@")) {
        throw new Error("Enter a valid business email");
      }
      if (businessEmail.length > 200) {
        throw new Error("Business email is too long");
      }
      patch.businessEmail = businessEmail;
    }
    if (args.contactName !== undefined) {
      const contactName = args.contactName.trim();
      if (!contactName) throw new Error("Contact name is required");
      if (contactName.length > 100) throw new Error("Contact name is too long");
      patch.contactName = contactName;
    }
    if (args.legalName !== undefined) {
      const legalName = args.legalName.trim();
      if (legalName.length > 200) throw new Error("Legal name is too long");
      patch.legalName = legalName || undefined;
    }
    if (args.phone !== undefined) {
      const phone = args.phone.trim();
      if (phone.length > 40) throw new Error("Phone number is too long");
      patch.phone = phone || undefined;
    }
    await ctx.db.patch(details._id, patch);
    return null;
  },
});

export const generatePhotoUploadUrl = mutation({
  args: { organizationId: v.id("organizations") },
  returns: v.string(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
      "manager",
    ]);
    return await ctx.storage.generateUploadUrl();
  },
});

export const setPhotos = mutation({
  args: {
    organizationId: v.id("organizations"),
    storageIds: v.array(v.id("_storage")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
      "manager",
    ]);
    if (args.storageIds.length > 10) {
      throw new Error("You can upload up to 10 photos");
    }
    for (const storageId of args.storageIds) {
      const upload = await ctx.db.system.get("_storage", storageId);
      if (upload === null) throw new Error("Upload not found");
      assertUploadAcceptable(
        { size: upload.size, contentType: upload.contentType },
        "photo",
      );
    }
    await ctx.db.patch(args.organizationId, {
      photoStorageIds: args.storageIds,
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const addPhoto = mutation({
  args: {
    organizationId: v.id("organizations"),
    storageId: v.id("_storage"),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { organization } = await requireOrganizationRole(
      ctx,
      args.organizationId,
      ["owner", "manager"],
    );
    const photoStorageIds = organization.photoStorageIds ?? [];
    if (photoStorageIds.includes(args.storageId)) return null;
    if (photoStorageIds.length >= 10) {
      throw new Error("You can upload up to 10 photos");
    }
    const upload = await ctx.db.system.get("_storage", args.storageId);
    if (upload === null) throw new Error("Upload not found");
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
    await ctx.db.patch(args.organizationId, {
      photoStorageIds: [...photoStorageIds, args.storageId],
      updatedAt: Date.now(),
    });
    return null;
  },
});

export async function setOrganizationSuspended(
  ctx: MutationCtx,
  organizationId: Id<"organizations">,
  suspended: boolean,
): Promise<void> {
  const now = Date.now();
  await ctx.db.patch(organizationId, {
    status: suspended ? "suspended" : "verified",
    suspendedAt: suspended ? now : undefined,
    updatedAt: now,
  });
  const venues = await ctx.db
    .query("venues")
    .withIndex("by_managedByOrganizationId", (q) =>
      q.eq("managedByOrganizationId", organizationId),
    )
    .take(50);
  for (const venue of venues) {
    await ctx.db.patch(venue._id, {
      status: suspended ? "suspended" : "verified",
    });
  }
}

export const deactivate = mutation({
  args: { organizationId: v.id("organizations") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, ["owner"]);
    await setOrganizationSuspended(ctx, args.organizationId, true);
    return null;
  },
});
