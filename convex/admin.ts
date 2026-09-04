import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import {
  isPlatformAdmin,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import { currentUser } from "./lib/helpers";

export const me = query({
  args: {},
  returns: v.object({ isPlatformAdmin: v.boolean() }),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    return {
      isPlatformAdmin:
        user === null ? false : await isPlatformAdmin(ctx, user._id),
    };
  },
});

export const overview = query({
  args: {},
  returns: v.object({
    counts: v.object({
      submittedApplications: v.number(),
      underReviewApplications: v.number(),
      needsInfoApplications: v.number(),
      verifiedOrganizations: v.number(),
      suspendedOrganizations: v.number(),
    }),
    capped: v.boolean(),
  }),
  handler: async (ctx) => {
    await requirePlatformAdminQuery(ctx);
    const [submitted, underReview, needsInfo, verified, suspended] =
      await Promise.all([
        ctx.db
          .query("organizationApplications")
          .withIndex("by_status_and_createdAt", (q) =>
            q.eq("status", "submitted"),
          )
          .take(101),
        ctx.db
          .query("organizationApplications")
          .withIndex("by_status_and_createdAt", (q) =>
            q.eq("status", "under_review"),
          )
          .take(101),
        ctx.db
          .query("organizationApplications")
          .withIndex("by_status_and_createdAt", (q) =>
            q.eq("status", "needs_info"),
          )
          .take(101),
        ctx.db
          .query("organizations")
          .withIndex("by_status_and_name", (q) => q.eq("status", "verified"))
          .take(101),
        ctx.db
          .query("organizations")
          .withIndex("by_status_and_name", (q) => q.eq("status", "suspended"))
          .take(101),
      ]);
    const rows = [submitted, underReview, needsInfo, verified, suspended];
    return {
      counts: {
        submittedApplications: Math.min(submitted.length, 100),
        underReviewApplications: Math.min(underReview.length, 100),
        needsInfoApplications: Math.min(needsInfo.length, 100),
        verifiedOrganizations: Math.min(verified.length, 100),
        suspendedOrganizations: Math.min(suspended.length, 100),
      },
      capped: rows.some((group) => group.length === 101),
    };
  },
});

export const suspendOrganization = mutation({
  args: {
    organizationId: v.id("organizations"),
    suspended: v.boolean(),
    note: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requirePlatformAdmin(ctx);
    const organization = await ctx.db.get(args.organizationId);
    if (!organization) throw new Error("Organization not found");

    if (args.suspended) {
      await ctx.db.patch(args.organizationId, {
        status: "suspended",
        suspendedAt: Date.now(),
      });
    } else {
      await ctx.db.patch(args.organizationId, {
        status: "verified",
        suspendedAt: undefined,
      });
    }

    const venues = await ctx.db
      .query("venues")
      .withIndex("by_managedByOrganizationId", (q) =>
        q.eq("managedByOrganizationId", args.organizationId),
      )
      .take(50);
    for (const venue of venues) {
      await ctx.db.patch(venue._id, {
        status: args.suspended ? "suspended" : "verified",
      });
    }
    // Reserved for a future audit-log field; the current schema has nowhere
    // appropriate to persist this note.
    void args.note;
    return null;
  },
});

export const grantPlatformAdmin = internalMutation({
  args: {
    userId: v.id("users"),
    note: v.optional(v.string()),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({
    granted: v.boolean(),
    alreadyAdmin: v.boolean(),
    dryRun: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    if (await isPlatformAdmin(ctx, args.userId)) {
      return { granted: false, alreadyAdmin: true, dryRun };
    }
    if (dryRun) {
      return { granted: false, alreadyAdmin: false, dryRun: true };
    }
    await ctx.db.insert("platformAdmins", {
      userId: args.userId,
      grantedAt: Date.now(),
      ...(args.note === undefined ? {} : { note: args.note }),
    });
    return { granted: true, alreadyAdmin: false, dryRun: false };
  },
});

export const revokePlatformAdmin = internalMutation({
  args: {
    userId: v.id("users"),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({ revoked: v.boolean(), dryRun: v.boolean() }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const activeGrant = await ctx.db
      .query("platformAdmins")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("revokedAt"), undefined))
      .first();
    if (!activeGrant) return { revoked: false, dryRun };
    if (dryRun) return { revoked: false, dryRun: true };
    await ctx.db.patch(activeGrant._id, { revokedAt: Date.now() });
    return { revoked: true, dryRun: false };
  },
});
