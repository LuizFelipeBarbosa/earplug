import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { MutationCtx, QueryCtx, mutation, query } from "./_generated/server";
import { docCache } from "./lib/docCache";
import { requireBandRole } from "./lib/helpers";
import { isLiveUser, toSocialPerson } from "./lib/social";

const bandMemberRoleValidator = v.union(
  v.literal("admin"),
  v.literal("member"),
);

/** Matches the membership cap used by bands:profileDetails. */
const MAX_BAND_MEMBERS = 100;

async function membershipFor(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  userId: Id<"users">,
) {
  return await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", userId),
    )
    .unique();
}

/** The last-admin invariant: a band always keeps at least one admin, so the
 * only admin can neither be demoted nor leave/be removed. */
async function anotherAdminExists(
  ctx: MutationCtx,
  bandId: Id<"bands">,
  excludedMembershipId: Id<"bandMembers">,
): Promise<boolean> {
  const memberships = await ctx.db
    .query("bandMembers")
    .withIndex("by_band", (q) => q.eq("bandId", bandId))
    .take(MAX_BAND_MEMBERS);
  return memberships.some(
    (membership) =>
      membership.role === "admin" && membership._id !== excludedMembershipId,
  );
}

export const list = query({
  args: { bandId: v.id("bands") },
  returns: v.array(
    v.object({
      userId: v.id("users"),
      name: v.string(),
      avatarUrl: v.union(v.string(), v.null()),
      role: bandMemberRoleValidator,
      isSelf: v.boolean(),
    }),
  ),
  handler: async (ctx, args) => {
    const { user: me } = await requireBandRole(ctx, args.bandId, {
      role: "member",
    });
    const memberships = await ctx.db
      .query("bandMembers")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .take(MAX_BAND_MEMBERS);
    const cache = docCache(ctx);
    const members = [];
    for (const membership of memberships) {
      const user = await cache.get(membership.userId);
      if (user === null || user.deletedAt !== undefined) continue;
      const person = await toSocialPerson(ctx, user, cache);
      members.push({
        ...person,
        role: membership.role,
        isSelf: user._id === me._id,
      });
    }
    return members.sort((a, b) => {
      if (a.role !== b.role) return a.role === "admin" ? -1 : 1;
      return a.name.localeCompare(b.name);
    });
  },
});

export const setRole = mutation({
  args: {
    bandId: v.id("bands"),
    userId: v.id("users"),
    role: bandMemberRoleValidator,
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandRole(ctx, args.bandId, { role: "admin" });
    const membership = await membershipFor(ctx, args.bandId, args.userId);
    if (membership === null) throw new Error("Member not found");
    if (membership.role === args.role) return null;
    if (
      membership.role === "admin" &&
      !(await anotherAdminExists(ctx, args.bandId, membership._id))
    ) {
      throw new Error("A band needs at least one admin");
    }
    await ctx.db.patch(membership._id, { role: args.role });
    return null;
  },
});

/** Admins remove anyone; any member may remove themself (leave the band). */
export const remove = mutation({
  args: { bandId: v.id("bands"), userId: v.id("users") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { band, user } = await requireBandRole(ctx, args.bandId, {
      role: "member",
    });
    if (user._id !== args.userId) {
      await requireBandRole(ctx, args.bandId, { role: "admin" });
    }
    const membership = await membershipFor(ctx, args.bandId, args.userId);
    if (membership === null) throw new Error("Member not found");
    if (
      membership.role === "admin" &&
      !(await anotherAdminExists(ctx, args.bandId, membership._id))
    ) {
      throw new Error("A band needs at least one admin");
    }
    await ctx.db.delete(membership._id);
    // Mirrors bandInvites:accept, which adds 1 with each new member row.
    await ctx.db.patch(band._id, {
      followerCount: Math.max(0, band.followerCount - 1),
    });
    return null;
  },
});

export const add = mutation({
  args: {
    bandId: v.id("bands"),
    userId: v.id("users"),
    role: v.optional(bandMemberRoleValidator),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { band } = await requireBandRole(ctx, args.bandId, { role: "admin" });
    if (!isLiveUser(await ctx.db.get(args.userId))) {
      throw new Error("User not found");
    }
    const existing = await membershipFor(ctx, args.bandId, args.userId);
    if (existing !== null) return null;
    await ctx.db.insert("bandMembers", {
      bandId: band._id,
      userId: args.userId,
      role: args.role ?? "member",
    });
    // Mirrors bandInvites:accept, which adds 1 with each new member row.
    await ctx.db.patch(band._id, {
      followerCount: band.followerCount + 1,
    });
    return null;
  },
});
