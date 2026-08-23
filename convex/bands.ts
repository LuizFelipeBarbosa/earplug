import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
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
  uniqueSlug,
} from "./lib/helpers";

export const get = query({
  args: { bandId: v.id("bands") },
  returns: v.union(bandPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const band = await ctx.db.get(args.bandId);
    return band === null ? null : await toBandPayload(ctx, band);
  },
});

/** Every band, name-ordered, through Convex's standard cursor pagination. */
export const list = query({
  args: { paginationOpts: paginationOptsValidator },
  returns: paginationResultValidator(bandPayloadValidator),
  handler: async (ctx, args) => {
    const result = await ctx.db
      .query("bands")
      .withIndex("by_name")
      .order("asc")
      .paginate(args.paginationOpts);
    const page = [];
    for (const band of result.page) {
      page.push(await toBandPayload(ctx, band));
    }
    return { ...result, page };
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
    const out = [];
    for (const band of bands) {
      out.push(await toBandPayload(ctx, band));
    }
    return out;
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
      if (band) {
        out.push({ band: await toBandPayload(ctx, band), role: membership.role });
      }
    }
    return out;
  },
});

/** Resolves a shared profile link (earplug.app/<slug>) to its band. `slug` is a
 * required schema column and `uniqueSlug` is the only thing that issues one, so
 * every band — including the migrated rows, which were backfilled before the
 * column was tightened — is reachable here. */
export const bySlug = query({
  args: { slug: v.string() },
  returns: v.union(bandPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    // .first(), not .unique(): a duplicate slug should degrade to "resolves to
    // the older band", never to a thrown query. See uniqueSlug in lib/helpers.
    const band = await ctx.db
      .query("bands")
      .withIndex("by_slug", (q) => q.eq("slug", args.slug))
      .first();
    return band === null ? null : await toBandPayload(ctx, band);
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
  returns: v.object({
    bandId: v.id("bands"),
    slug: v.string(),
    band: bandPayloadValidator,
  }),
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
      // Invariant: followerCount == count(follows) + count(bandMembers). This
      // insert is followed by exactly one bandMembers row (the caller, admin)
      // and no follows row. inviteHandles are stored strings — nothing converts
      // them into bandMembers, so they must not be counted here.
      followerCount: 1,
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
    const band = await ctx.db.get(bandId);
    if (band === null) throw new Error("Created band not found");
    return { bandId, slug, band: await toBandPayload(ctx, band) };
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
      // Two name-derived fields deliberately do NOT follow a rename:
      // `slug`, so shared links keep resolving, and `colorHex`, which is the
      // band's visual identity everywhere it appears in the feed — recoloring
      // a known band mid-flight is worse than a color that no longer matches
      // its name hash. Initials are the label on that swatch, so they do.
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

export const setBandPhoto = mutation({
  args: {
    bandId: v.id("bands"),
    mediaId: v.id("bandMedia"),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const media = await ctx.db.get(args.mediaId);
    if (!media) throw new Error("Media not found");
    if (media.bandId !== args.bandId) {
      throw new Error("Media belongs to a different band");
    }
    if (media.kind !== "photo") {
      throw new Error("Only photos can be the band photo");
    }
    await ctx.db.patch(args.bandId, { imageStorageId: media.storageId });
    return null;
  },
});

export const clearBandPhoto = mutation({
  args: { bandId: v.id("bands") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    await ctx.db.patch(args.bandId, { imageStorageId: undefined });
    return null;
  },
});
