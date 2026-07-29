import { v } from "convex/values";
import { mutation, query, type MutationCtx } from "./_generated/server";
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

function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug === "" ? "band" : slug;
}

/** "static-bloom", or "static-bloom-2" (-3, …) when the name is taken. */
async function uniqueSlug(ctx: MutationCtx, name: string): Promise<string> {
  const base = slugify(name);
  for (let n = 1; ; n++) {
    const candidate = n === 1 ? base : `${base}-${n}`;
    const taken = await ctx.db
      .query("bands")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .unique();
    if (taken === null) return candidate;
  }
}

/** Resolves a shared profile link (earplug.app/<slug>) to its band. */
export const bySlug = query({
  args: { slug: v.string() },
  returns: v.union(bandPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const band = await ctx.db
      .query("bands")
      .withIndex("by_slug", (q) => q.eq("slug", args.slug))
      .unique();
    return band === null ? null : toBandPayload(band);
  },
});

export const createBand = mutation({
  args: {
    name: v.string(),
    genres: v.array(v.string()),
    bio: v.string(),
    inviteHandles: v.array(v.string()),
    area: v.optional(v.string()),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    linkYt: v.optional(v.string()),
  },
  returns: v.object({ bandId: v.id("bands"), slug: v.string() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const slug = await uniqueSlug(ctx, args.name);
    const bandId = await ctx.db.insert("bands", {
      name: args.name,
      genres: args.genres,
      bio: args.bio,
      area: args.area ?? "Bay Area",
      colorHex: bandColorFor(args.name),
      initials: initialsFor(args.name),
      followerCount: 1 + args.inviteHandles.length,
      pastShows: [],
      inviteHandles: args.inviteHandles,
      linkIg: args.linkIg,
      linkBc: args.linkBc,
      linkYt: args.linkYt,
      slug,
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: user._id,
      role: "admin",
    });
    return { bandId, slug };
  },
});

export const updateProfile = mutation({
  args: {
    bandId: v.id("bands"),
    name: v.optional(v.string()),
    genres: v.optional(v.array(v.string())),
    area: v.optional(v.string()),
    bio: v.optional(v.string()),
    inviteHandles: v.optional(v.array(v.string())),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    linkYt: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const patch: {
      name?: string;
      initials?: string;
      genres?: string[];
      area?: string;
      bio?: string;
      inviteHandles?: string[];
      linkIg?: string;
      linkBc?: string;
      linkYt?: string;
    } = {};
    if (args.name !== undefined) {
      // The slug stays as issued at creation so shared links keep resolving.
      patch.name = args.name;
      patch.initials = initialsFor(args.name);
    }
    if (args.genres !== undefined) patch.genres = args.genres;
    if (args.area !== undefined) patch.area = args.area;
    if (args.bio !== undefined) patch.bio = args.bio;
    if (args.inviteHandles !== undefined) {
      patch.inviteHandles = args.inviteHandles;
    }
    if (args.linkIg !== undefined) patch.linkIg = args.linkIg;
    if (args.linkBc !== undefined) patch.linkBc = args.linkBc;
    if (args.linkYt !== undefined) patch.linkYt = args.linkYt;
    if (Object.keys(patch).length > 0) {
      await ctx.db.patch(args.bandId, patch);
    }
    return null;
  },
});
