import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  bandColorFor,
  bandPayloadValidator,
  currentUser,
  initialsFor,
  requireBandAdmin,
  requireUser,
  toBandPayload,
} from "./lib/helpers";

export const get = query({
  args: { bandId: v.id("bands") },
  returns: v.union(bandPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const band = await ctx.db.get(args.bandId);
    return band === null ? null : toBandPayload(band);
  },
});

/** Top-level array. `q: ""` → all bands (capped 50). */
export const search = query({
  args: { q: v.string() },
  returns: v.array(bandPayloadValidator),
  handler: async (ctx, args) => {
    const bands =
      args.q === ""
        ? await ctx.db.query("bands").take(50)
        : await ctx.db
            .query("bands")
            .withSearchIndex("search_name", (q) => q.search("name", args.q))
            .take(50);
    return bands.map(toBandPayload);
  },
});

/** Top-level array of { band, role }; [] unauthenticated. */
export const myBands = query({
  args: {},
  returns: v.array(
    v.object({
      band: bandPayloadValidator,
      role: v.union(v.literal("admin"), v.literal("member")),
    }),
  ),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const memberships = await ctx.db
      .query("bandMembers")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(100);
    const out = [];
    for (const membership of memberships) {
      const band = await ctx.db.get(membership.bandId);
      if (band) out.push({ band: toBandPayload(band), role: membership.role });
    }
    return out;
  },
});

export const createBand = mutation({
  args: {
    name: v.string(),
    genres: v.array(v.string()),
    bio: v.string(),
    inviteHandles: v.array(v.string()),
  },
  returns: v.object({ bandId: v.id("bands") }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const bandId = await ctx.db.insert("bands", {
      name: args.name,
      genres: args.genres,
      bio: args.bio,
      area: "Bay Area",
      colorHex: bandColorFor(args.name),
      initials: initialsFor(args.name),
      followerCount: 1 + args.inviteHandles.length,
      pastShows: [],
      inviteHandles: args.inviteHandles,
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: user._id,
      role: "admin",
    });
    return { bandId };
  },
});

export const updateProfile = mutation({
  args: {
    bandId: v.id("bands"),
    bio: v.optional(v.string()),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const patch: { bio?: string; linkIg?: string; linkBc?: string } = {};
    if (args.bio !== undefined) patch.bio = args.bio;
    if (args.linkIg !== undefined) patch.linkIg = args.linkIg;
    if (args.linkBc !== undefined) patch.linkBc = args.linkBc;
    if (Object.keys(patch).length > 0) {
      await ctx.db.patch(args.bandId, patch);
    }
    return null;
  },
});
