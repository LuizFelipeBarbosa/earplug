import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import {
  bandColorFor,
  bandPayloadValidator,
  currentUser,
  FEED_GRACE_MS,
  hasValidProfileImage,
  initialsFor,
  isBandProfileComplete,
  requireBandAdmin,
  requireBandAdminQuery,
  requireBandMemberMutation,
  requireUser,
  toBandPayload,
  uniqueSlug,
} from "./lib/helpers";
import {
  DiscoveryListingFlags,
  discoveryListingFlags,
  isDiscoveryListingReady,
} from "./lib/discovery";

const DISCOVERY_LEAD_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_DISCOVERY_PROJECTS = 100;

const profileDetailsValidator = v.object({
  credits: v.union(v.string(), v.null()),
  linkIg: v.union(v.string(), v.null()),
  linkBc: v.union(v.string(), v.null()),
  linkYt: v.union(v.string(), v.null()),
  memberNames: v.array(v.string()),
});

const setupStatusValidator = v.object({
  profileComplete: v.boolean(),
  profileImageAdded: v.boolean(),
  musicAdded: v.boolean(),
  socialLinksAdded: v.boolean(),
  firstGigCreated: v.boolean(),
  membersInvited: v.boolean(),
  publicProfilePreviewed: v.boolean(),
});

const discoveryShowValidator = v.object({
  gigId: v.id("gigs"),
  projectId: v.id("gigProjects"),
  title: v.string(),
  startsAt: v.number(),
});

const discoveryReadinessValidator = v.object({
  profileComplete: v.boolean(),
  profileImageReady: v.boolean(),
  clipReady: v.boolean(),
  publishedShowReady: v.boolean(),
  venuePosterReady: v.boolean(),
  publishedRevisionCurrent: v.boolean(),
  relevantShow: v.union(discoveryShowValidator, v.null()),
  nextEligibleShow: v.union(discoveryShowValidator, v.null()),
  boostWindow: v.union(
    v.object({
      opensAt: v.number(),
      closesAt: v.number(),
      active: v.boolean(),
    }),
    v.null(),
  ),
});

function requiredProfileValues(
  nameInput: string,
  genresInput: string[],
  areaInput: string,
) {
  const name = nameInput.trim();
  const genres = genresInput.map((genre) => genre.trim());
  const area = areaInput.trim();
  if (name === "" || area === "" || genres.length === 0) {
    throw new Error("Band name, sound, and home base are required");
  }
  if (genres.length > 3) throw new Error("Choose no more than three genres");
  if (genres.some((genre) => genre === "")) {
    throw new Error("Genres cannot be blank");
  }
  return { name, genres, area };
}

function optionalText(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed === "" ? undefined : trimmed;
}

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
        out.push({
          band: await toBandPayload(ctx, band),
          role: membership.role,
        });
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

/** Public-profile-only joins. Membership names stay out of feed/search band
 * payloads so those broad subscriptions do not depend on every member row. */
export const profileDetails = query({
  args: { bandId: v.id("bands") },
  returns: v.union(profileDetailsValidator, v.null()),
  handler: async (ctx, args) => {
    const band = await ctx.db.get(args.bandId);
    if (!band) return null;

    const memberships = await ctx.db
      .query("bandMembers")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .take(100);
    const memberNames: string[] = [];
    for (const membership of memberships) {
      const user = await ctx.db.get(membership.userId);
      if (user && user.deletedAt === undefined && user.name.trim() !== "") {
        memberNames.push(user.name);
      }
    }
    return {
      credits: band.credits ?? null,
      linkIg: band.linkIg ?? null,
      linkBc: band.linkBc ?? null,
      linkYt: band.linkYt ?? null,
      memberNames,
    };
  },
});

/** The seven admin-only setup tasks. This is advisory and never gates access
 * to the dashboard or any other application feature. */
export const setupStatus = query({
  args: { bandId: v.id("bands") },
  returns: setupStatusValidator,
  handler: async (ctx, args) => {
    const band = await requireBandAdminQuery(ctx, args.bandId);
    const [video, gigRows, memberships] = await Promise.all([
      ctx.db
        .query("bandMedia")
        .withIndex("by_band_kind_order", (q) =>
          q.eq("bandId", args.bandId).eq("kind", "video"),
        )
        .first(),
      ctx.db
        .query("gigBands")
        .withIndex("by_band_startsAt", (q) => q.eq("bandId", args.bandId))
        .take(20),
      ctx.db
        .query("bandMembers")
        .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
        .take(2),
    ]);
    let firstGigCreated = false;
    for (const row of gigRows) {
      const gig = await ctx.db.get(row.gigId);
      if (gig && (gig.lifecycle ?? "published") === "published") {
        firstGigCreated = true;
        break;
      }
    }
    return {
      profileComplete: isBandProfileComplete(band),
      profileImageAdded: band.imageStorageId !== undefined,
      musicAdded:
        video !== null ||
        (band.linkBc?.trim() ?? "") !== "" ||
        (band.linkYt?.trim() ?? "") !== "",
      socialLinksAdded: (band.linkIg?.trim() ?? "") !== "",
      firstGigCreated,
      membersInvited: memberships.length > 1,
      publicProfilePreviewed: band.publicProfilePreviewedAt !== undefined,
    };
  },
});

/** Admin-only detail behind the dashboard's separate discovery card. `now`
 * controls window presentation only; authorization is always derived from the
 * authenticated membership. */
export const discoveryReadiness = query({
  args: { bandId: v.id("bands"), now: v.number() },
  returns: discoveryReadinessValidator,
  handler: async (ctx, args) => {
    const band = await requireBandAdminQuery(ctx, args.bandId);
    if (!Number.isFinite(args.now)) throw new Error("Invalid now");

    const profileComplete = isBandProfileComplete(band);
    const profileImageReady = await hasValidProfileImage(ctx, band);
    const clipReady = band.hasClip === true;
    const projects = await ctx.db
      .query("gigProjects")
      .withIndex("by_band_and_status", (q) =>
        q.eq("bandId", args.bandId).eq("status", "published"),
      )
      .take(MAX_DISCOVERY_PROJECTS);

    const candidates: Array<{
      project: Doc<"gigProjects">;
      gig: Doc<"gigs"> | null;
      flags: DiscoveryListingFlags;
    }> = [];
    for (const project of projects) {
      if (
        project.startsAt === undefined ||
        project.startsAt < args.now - FEED_GRACE_MS ||
        project.publicGigId === undefined
      ) {
        continue;
      }
      const gig = await ctx.db.get(project.publicGigId);
      const performers = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_project_and_order", (q) =>
          q.eq("projectId", project._id),
        )
        .take(21);
      const flags = await discoveryListingFlags(ctx, project, gig, performers);
      candidates.push({ project, gig, flags });
    }
    candidates.sort(
      (left, right) => left.project.startsAt! - right.project.startsAt!,
    );

    const eligible =
      candidates.find(
        (candidate) =>
          candidate.gig?.discoveryListingReady === true &&
          isDiscoveryListingReady(candidate.flags),
      ) ?? null;
    const relevant = eligible ?? candidates[0] ?? null;
    const showPayload = (candidate: (typeof candidates)[number] | null) => {
      if (!candidate?.gig || candidate.project.startsAt === undefined) {
        return null;
      }
      return {
        gigId: candidate.gig._id,
        projectId: candidate.project._id,
        title: candidate.project.title?.trim() || candidate.gig.title,
        startsAt: candidate.project.startsAt,
      };
    };
    const eligibleShow = showPayload(eligible);
    const opensAt = eligibleShow
      ? eligibleShow.startsAt - DISCOVERY_LEAD_MS
      : null;
    const closesAt = eligibleShow
      ? eligibleShow.startsAt + FEED_GRACE_MS
      : null;
    const allProfileReady = profileComplete && profileImageReady && clipReady;

    return {
      profileComplete,
      profileImageReady,
      clipReady,
      publishedShowReady: relevant?.flags.publishedShowReady ?? false,
      venuePosterReady: relevant?.flags.venuePosterReady ?? false,
      publishedRevisionCurrent:
        relevant?.flags.publishedRevisionCurrent ?? false,
      relevantShow: showPayload(relevant),
      nextEligibleShow: eligibleShow,
      boostWindow:
        opensAt === null || closesAt === null
          ? null
          : {
              opensAt,
              closesAt,
              active:
                allProfileReady && args.now >= opensAt && args.now <= closesAt,
            },
    };
  },
});

export const markPreviewed = mutation({
  args: { bandId: v.id("bands") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { band } = await requireBandMemberMutation(ctx, args.bandId);
    if (band.publicProfilePreviewedAt === undefined) {
      await ctx.db.patch(args.bandId, {
        publicProfilePreviewedAt: Date.now(),
      });
    }
    return null;
  },
});

export const createBand = mutation({
  args: {
    name: v.string(),
    genres: v.array(v.string()),
    bio: v.string(),
    // Accepted but deliberately ignored while older clients age out. Real
    // memberships are created only through bandInvites:accept.
    inviteHandles: v.optional(v.array(v.string())),
    area: v.string(),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    linkYt: v.optional(v.string()),
    credits: v.optional(v.string()),
  },
  returns: v.object({
    bandId: v.id("bands"),
    slug: v.string(),
    band: bandPayloadValidator,
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const profile = requiredProfileValues(args.name, args.genres, args.area);
    const slug = await uniqueSlug(ctx, profile.name);
    const bandId = await ctx.db.insert("bands", {
      name: profile.name,
      genres: profile.genres,
      bio: optionalText(args.bio),
      area: profile.area,
      colorHex: bandColorFor(profile.name),
      initials: initialsFor(profile.name),
      // Invariant: followerCount == count(follows) + count(bandMembers). This
      // insert is followed by exactly one bandMembers row (the caller, admin)
      // and no follows row. Legacy inviteHandles are ignored — only confirmed
      // bandInvites:accept calls can create another membership.
      followerCount: 1,
      pastShows: [],
      linkIg: optionalText(args.linkIg),
      linkBc: optionalText(args.linkBc),
      linkYt: optionalText(args.linkYt),
      credits: optionalText(args.credits),
      slug,
      hasClip: false,
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
    // Accepted but deliberately ignored while older clients age out. Real
    // memberships are created only through bandInvites:accept.
    inviteHandles: v.optional(v.array(v.string())),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    linkYt: v.optional(v.string()),
    credits: v.optional(v.string()),
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
      linkIg?: string;
      linkBc?: string;
      linkYt?: string;
      credits?: string;
    } = {};
    // Slug and color deliberately remain stable across renames. Initials are
    // the visible label for the new name and therefore do follow it.
    if (args.name !== undefined) {
      const name = args.name.trim();
      if (name === "") {
        throw new Error("Band name, sound, and home base are required");
      }
      patch.name = name;
      patch.initials = initialsFor(name);
    }
    if (args.genres !== undefined) {
      const genres = args.genres.map((genre) => genre.trim());
      if (genres.length === 0) {
        throw new Error("Band name, sound, and home base are required");
      }
      if (genres.length > 3) {
        throw new Error("Choose no more than three genres");
      }
      if (genres.some((genre) => genre === "")) {
        throw new Error("Genres cannot be blank");
      }
      patch.genres = genres;
    }
    if (args.area !== undefined) {
      const area = args.area.trim();
      if (area === "") {
        throw new Error("Band name, sound, and home base are required");
      }
      patch.area = area;
    }
    if (args.bio !== undefined) patch.bio = optionalText(args.bio);
    if (args.linkIg !== undefined) patch.linkIg = optionalText(args.linkIg);
    if (args.linkBc !== undefined) patch.linkBc = optionalText(args.linkBc);
    if (args.linkYt !== undefined) patch.linkYt = optionalText(args.linkYt);
    if (args.credits !== undefined) patch.credits = optionalText(args.credits);
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
