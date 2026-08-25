import { WithoutSystemFields } from "convex/server";
import { Infer, v } from "convex/values";
import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import {
  ageRequirementValidator,
  fanCityValidator,
  fanGenreChoiceValidator,
  gigLifecycleValidator,
  gigPublicPerformerValidator,
  pastShowValidator,
} from "../schema";

// ─── Deterministic band identity ────────────────────────────────────────────
// Every band's colour, initials and slug are derived from its name rather than
// stored by hand, so any write path that creates or renames a band lands on the
// same values. Live callers: bands:createBand (all three) and
// bands:updateProfile (initials only — see the note there on why colour and
// slug deliberately do not follow a rename).

const BAND_PALETTE = [
  "#7B8FFF",
  "#B9C4FF",
  "#E4DC4A",
  "#8FE6C4",
  "#F0A26B",
  "#D9A6E8",
];

export function bandColorFor(name: string): string {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return BAND_PALETTE[hash % BAND_PALETTE.length];
}

/** First letter of the first two words; single-word names take the first two
 * letters. "SOBO" → "SO", "Public School Records" → "PS". */
export function initialsFor(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "??";
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

/** "Static Bloom!" → "static-bloom". Punctuation-only names fall back to
 * "band" so every row can be given a slug. */
export function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug === "" ? "band" : slug;
}

/** "static-bloom", or "static-bloom-2" (-3, …) when the name is taken.
 *
 * Reads with `.first()`, not `.unique()`: nothing in the schema enforces slug
 * uniqueness — this function is the only thing that does — so a duplicate
 * introduced by any other write path must not be able to wedge slug issuance
 * (and `bands:bySlug`) permanently by making the read throw. */
export async function uniqueSlug(
  ctx: MutationCtx,
  name: string,
): Promise<string> {
  const base = slugify(name);
  for (let n = 1; ; n++) {
    const candidate = n === 1 ? base : `${base}-${n}`;
    const taken = await ctx.db
      .query("bands")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (taken === null) return candidate;
  }
}

// ─── Auth ───────────────────────────────────────────────────────────────────

/** Non-throwing: the current user's doc, or null (queries must not throw when
 * unauthenticated). */
export async function currentUser(
  ctx: QueryCtx | MutationCtx,
): Promise<Doc<"users"> | null> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) return null;
  const user = await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.subject))
    .unique();
  return user?.deletedAt === undefined ? user : null;
}

/** Throwing: for mutations. */
export async function requireUser(ctx: MutationCtx): Promise<Doc<"users">> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) throw new Error("Not signed in");
  const user = await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.subject))
    .unique();
  if (!user) throw new Error("No user record — call users:ensureUser first");
  if (user.deletedAt !== undefined) throw new Error("Account deleted");
  return user;
}

/** Throws unless the caller is an admin member of the band. Returns the user. */
export async function requireBandAdmin(
  ctx: MutationCtx,
  bandId: Id<"bands">,
): Promise<Doc<"users">> {
  const user = await requireUser(ctx);
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", user._id),
    )
    .unique();
  if (!membership || membership.role !== "admin") {
    throw new Error("Not an admin of this band");
  }
  return user;
}

/** Query counterpart to requireBandAdmin. Private admin queries intentionally
 * throw instead of returning an empty payload to an unauthorized caller. */
export async function requireBandAdminQuery(
  ctx: QueryCtx,
  bandId: Id<"bands">,
): Promise<Doc<"bands">> {
  const user = await currentUser(ctx);
  if (!user) {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not signed in");
    throw new Error("No user record — call users:ensureUser first");
  }
  const band = await ctx.db.get(bandId);
  if (!band) throw new Error("Band not found");
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", user._id),
    )
    .unique();
  if (!membership || membership.role !== "admin") {
    throw new Error("Not an admin of this band");
  }
  return band;
}

/** Mutation guard for operations available to either band role. */
export async function requireBandMemberMutation(
  ctx: MutationCtx,
  bandId: Id<"bands">,
): Promise<{ band: Doc<"bands">; user: Doc<"users"> }> {
  const user = await requireUser(ctx);
  const band = await ctx.db.get(bandId);
  if (!band) throw new Error("Band not found");
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", user._id),
    )
    .unique();
  if (!membership) throw new Error("Not a member of this band");
  return { band, user };
}

/** Throws unless the caller is a member of the band. Returns the band so a
 * private query can authorize and hydrate band-owned data with one guard. */
export async function requireBandMember(
  ctx: QueryCtx,
  bandId: Id<"bands">,
): Promise<Doc<"bands">> {
  const user = await currentUser(ctx);
  if (!user) {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not signed in");
    throw new Error("No user record — call users:ensureUser first");
  }
  const band = await ctx.db.get(bandId);
  if (!band) throw new Error("Band not found");
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", user._id),
    )
    .unique();
  if (!membership) throw new Error("Not a member of this band");
  return band;
}

// ─── Contract payload validators + converters ───────────────────────────────

export const bandPayloadValidator = v.object({
  _id: v.id("bands"),
  name: v.string(),
  genres: v.array(v.string()),
  area: v.string(),
  colorHex: v.string(),
  initials: v.string(),
  followerCount: v.number(),
  heroUrl: v.union(v.string(), v.null()),
  bio: v.string(),
  linkIg: v.union(v.string(), v.null()),
  linkBc: v.union(v.string(), v.null()),
  linkYt: v.union(v.string(), v.null()),
  credits: v.union(v.string(), v.null()),
  profileComplete: v.boolean(),
  discoveryProfileReady: v.boolean(),
  // The wire shape is the stored shape here; reuse it rather than restating it.
  pastShows: v.array(pastShowValidator),
});

/** The six presses offered by the client's gig-create picker. "custom" means
 * band-supplied art backed by gigs.flyStorageId; clients render a placeholder
 * plate when flyerUrl resolves null. The gigs.flyKey schema column stays
 * v.string() because legacy rows/seeds use older keys: paper, blue, black,
 * yellow, and bluetype. */
export const flyKeyValidator = v.union(
  v.literal("xerox"),
  v.literal("riso"),
  v.literal("marquee"),
  v.literal("blueprint"),
  v.literal("sunburst"),
  v.literal("custom"),
);

export type AgeRequirement = Infer<typeof ageRequirementValidator>;

export const gigPublishFieldsValidator = v.object({
  bandId: v.id("bands"),
  title: v.string(),
  startsAt: v.number(),
  doorsAt: v.optional(v.number()),
  doorsTime: v.string(),
  venueId: v.id("venues"),
  price: v.number(),
  flyKey: flyKeyValidator,
  flyStorageId: v.optional(v.id("_storage")),
  ticketing: v.union(v.literal("rsvp"), v.literal("external")),
  ageRequirement: ageRequirementValidator,
  externalUrl: v.optional(v.string()),
  cap: v.string(),
});
export type GigPublishFields = Infer<typeof gigPublishFieldsValidator>;

type GigPublishValidationFields = {
  bandId: Id<"bands">;
  startsAt: number;
  venueId: Id<"venues">;
  price: number;
  flyKey: string;
  flyStorageId?: Id<"_storage">;
  ticketing: "rsvp" | "external";
  externalUrl?: string;
};

/** Every non-auth check publishGig performs, in its original order. Throws on
 * the first failure; returns the resolved rows. Performs no writes. */
export async function assertGigPublishable(
  ctx: MutationCtx,
  args: GigPublishValidationFields,
): Promise<{ band: Doc<"bands">; venue: Doc<"venues"> }> {
  if (!Number.isFinite(args.startsAt) || args.startsAt < 0) {
    throw new Error("Invalid startsAt");
  }
  if (!Number.isFinite(args.price) || args.price < 0) {
    throw new Error("Invalid price");
  }
  if (
    args.ticketing === "external" &&
    (!args.externalUrl || !/^https?:\/\//.test(args.externalUrl))
  ) {
    throw new Error("External ticketing requires a valid http(s) URL");
  }
  if (args.flyKey === "custom") {
    if (args.flyStorageId === undefined) {
      throw new Error("Custom flyer requires flyStorageId");
    }
    const upload = await ctx.db.system.get("_storage", args.flyStorageId);
    if (!upload) throw new Error("Flyer upload not found");
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
  }
  const venue = await ctx.db.get(args.venueId);
  if (!venue) throw new Error("Venue not found");
  const band = await ctx.db.get(args.bandId);
  if (!band) throw new Error("Band not found");
  return { band, venue };
}

/** The instant that divides "upcoming" from "past". Every feed-shaped read
 * derives from it so they share one grace window — but each query execution
 * takes its own reading, so a gig sitting right on the boundary can still be
 * upcoming to one query and past to another.
 *
 * Known staleness, deferred for v1: Date.now() is captured when the query
 * executes, and a cached result only recomputes when something writes to the
 * range it read — so on a quiet deployment a gig can linger past the 6h grace.
 * Pre-launch fix: a cron heartbeat that writes the current hour's cutoff to a
 * singleton doc this reads instead of the clock. */
export function feedCutoff(): number {
  return Date.now() - FEED_GRACE_MS;
}

/** One band's past gigs, newest first, at most `limit` of them.
 *
 * Reads `gigBands.by_band_startsAt` rather than filtering the global gig range
 * by `lineup`, so the window bounds the band's own history and nothing else.
 * A join row whose gig has been deleted is skipped rather than trusted. */
export async function pastGigsForBand(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  limit: number,
): Promise<Doc<"gigs">[]> {
  const joinRows = await ctx.db
    .query("gigBands")
    .withIndex("by_band_startsAt", (q) =>
      q.eq("bandId", bandId).lt("startsAt", feedCutoff()),
    )
    .order("desc")
    .take(limit * 4);

  const gigs: Doc<"gigs">[] = [];
  for (const row of joinRows) {
    const gig = await ctx.db.get(row.gigId);
    if (gig && (gig.lifecycle ?? "published") === "published") gigs.push(gig);
    if (gigs.length === limit) break;
  }
  return gigs;
}

/** One band's upcoming gigs, oldest first, at most `limit` of them.
 *
 * The global discovery feed has its own cap. Reading the band's join rows
 * keeps unrelated gigs from crowding its shows out of this result. */
export async function upcomingGigsForBand(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  limit: number,
): Promise<Doc<"gigs">[]> {
  const joinRows = await ctx.db
    .query("gigBands")
    .withIndex("by_band_startsAt", (q) =>
      q.eq("bandId", bandId).gte("startsAt", feedCutoff()),
    )
    .order("asc")
    .take(limit * 4);

  const gigs: Doc<"gigs">[] = [];
  for (const row of joinRows) {
    const gig = await ctx.db.get(row.gigId);
    if (gig && (gig.lifecycle ?? "published") === "published") gigs.push(gig);
    if (gigs.length === limit) break;
  }
  return gigs;
}

/** The only supported way to create a gig. `gigs.lineup` is an array, which
 * Convex cannot index, so a band's own history is reachable only through the
 * `gigBands` join rows written here. A gig inserted straight into `ctx.db`
 * exists but is invisible to `gigs:pastForBand` and `analytics:bandRecap` —
 * route every insert through this function, including seeds and fixtures. */
export async function insertGigWithBandIndex(
  ctx: MutationCtx,
  gig: WithoutSystemFields<Doc<"gigs">> & {
    ageRequirement: AgeRequirement;
  },
): Promise<Id<"gigs">> {
  const gigId = await ctx.db.insert("gigs", {
    ...gig,
    discoveryListingReady: gig.discoveryListingReady ?? false,
  });
  for (const bandId of new Set(gig.lineup)) {
    await ctx.db.insert("gigBands", { gigId, bandId, startsAt: gig.startsAt });
  }
  return gigId;
}

/** The insert half. `band` must come from assertGigPublishable — call that
 * first. */
export async function insertPublishedGig(
  ctx: MutationCtx,
  args: GigPublishFields,
  band: Doc<"bands">,
): Promise<Id<"gigs">> {
  const gigId = await insertGigWithBandIndex(ctx, {
    title: args.title,
    venueId: args.venueId,
    price: args.price,
    startsAt: args.startsAt,
    doorsAt: args.doorsAt ?? args.startsAt,
    doorsTime: args.doorsTime,
    flyKey: args.flyKey,
    lineup: [args.bandId],
    performers: [
      { name: band.name, role: "headliner" as const, bandId: band._id },
    ],
    genres: band.genres,
    desc: "",
    ticketing: args.ticketing,
    ageRequirement: args.ageRequirement,
    ...(args.ticketing === "external" && args.externalUrl !== undefined
      ? { externalUrl: args.externalUrl }
      : {}),
    ...(args.flyKey === "custom" && args.flyStorageId !== undefined
      ? { flyStorageId: args.flyStorageId }
      : {}),
    cap: args.cap,
    goingCount: 0,
    createdByBand: args.bandId,
    lifecycle: "published",
    discoveryListingReady: true,
  });
  return gigId;
}

export const gigPayloadValidator = v.object({
  _id: v.id("gigs"),
  title: v.string(),
  venueId: v.id("venues"),
  price: v.number(),
  startsAt: v.number(),
  doorsAt: v.number(),
  doorsTime: v.string(),
  flyKey: v.string(),
  flyerUrl: v.union(v.string(), v.null()),
  lineup: v.array(v.id("bands")),
  performers: v.array(gigPublicPerformerValidator),
  genres: v.array(v.string()),
  desc: v.string(),
  ticketing: v.union(v.literal("rsvp"), v.literal("external")),
  ageRequirement: ageRequirementValidator,
  externalUrl: v.union(v.string(), v.null()),
  cap: v.string(),
  goingCount: v.number(),
  createdByBand: v.union(v.id("bands"), v.null()),
  lifecycle: gigLifecycleValidator,
  discoveryListingReady: v.boolean(),
});

export const venuePayloadValidator = v.object({
  _id: v.id("venues"),
  name: v.string(),
  area: v.string(),
  addr: v.string(),
  distSF: v.string(),
  distOak: v.string(),
  lat: v.number(),
  lng: v.number(),
});

export const mediaKindValidator = v.union(
  v.literal("video"),
  v.literal("photo"),
);

export const mediaPayloadValidator = v.object({
  _id: v.id("bandMedia"),
  bandId: v.id("bands"),
  kind: mediaKindValidator,
  // Resolved per read; null when the blob is gone, so clients render the
  // placeholder tile rather than a dead image.
  url: v.union(v.string(), v.null()),
  title: v.string(),
  caption: v.union(v.string(), v.null()),
  contentType: v.union(v.string(), v.null()),
  sizeBytes: v.union(v.number(), v.null()),
  views: v.union(v.number(), v.null()),
  lengthSec: v.union(v.number(), v.null()),
  pinned: v.boolean(),
  order: v.number(),
  /** True when this row's blob is also the band's profile photo. */
  isHero: v.boolean(),
});

export const userPayloadValidator = v.object({
  _id: v.id("users"),
  clerkId: v.string(),
  name: v.string(),
  email: v.string(),
  genres: v.array(v.string()),
  attendedCount: v.number(),
  createdAt: v.number(),
  avatarUrl: v.union(v.string(), v.null()),
  bio: v.union(v.string(), v.null()),
  homeLocation: v.union(fanCityValidator, v.null()),
  locationPersonalizationEnabled: v.boolean(),
  followedBandUpdatesEnabled: v.boolean(),
  profileTutorialCompleted: v.boolean(),
  fanOnboarding: v.union(
    v.object({
      preferredCity: v.union(fanCityValidator, v.null()),
      genreChoice: fanGenreChoiceValidator,
      collapsed: v.boolean(),
    }),
    v.null(),
  ),
});

// `?? null` on the optional fields is the payload contract (explicit nulls,
// never absent keys), not a defensive default — the rest are required by the
// schema, so a missing one is a bug worth failing on.
/** Known fan-out cost, accepted for v1: resolving the hero joins its `_storage`
 * row into every reader's read set — including `gigs:feed`, where one band's
 * hero change re-fires the feed for every subscribed client. First thing to
 * revisit if the feed gets hot. */
export async function toBandPayload(ctx: QueryCtx, band: Doc<"bands">) {
  const profileComplete = isBandProfileComplete(band);
  const profileImageReady = await hasValidProfileImage(ctx, band);
  return {
    _id: band._id,
    name: band.name,
    genres: band.genres,
    area: band.area,
    colorHex: band.colorHex,
    initials: band.initials,
    followerCount: band.followerCount,
    heroUrl: band.imageStorageId
      ? await ctx.storage.getUrl(band.imageStorageId)
      : null,
    bio: band.bio ?? "",
    linkIg: band.linkIg ?? null,
    linkBc: band.linkBc ?? null,
    linkYt: band.linkYt ?? null,
    credits: band.credits ?? null,
    profileComplete,
    discoveryProfileReady:
      profileComplete && profileImageReady && band.hasClip === true,
    pastShows: band.pastShows,
  };
}

export async function toGigPayload(ctx: QueryCtx, gig: Doc<"gigs">) {
  const performers = [];
  if (gig.performers) {
    performers.push(...gig.performers);
  } else {
    for (let index = 0; index < gig.lineup.length; index++) {
      const band = await ctx.db.get(gig.lineup[index]);
      if (band) {
        performers.push({
          name: band.name,
          role: index === 0 ? ("headliner" as const) : ("support" as const),
          bandId: band._id,
        });
      }
    }
  }
  return {
    _id: gig._id,
    title: gig.title,
    venueId: gig.venueId,
    price: gig.price,
    startsAt: gig.startsAt,
    doorsAt: gig.doorsAt ?? gig.startsAt,
    doorsTime: gig.doorsTime,
    flyKey: gig.flyKey,
    flyerUrl: gig.flyStorageId
      ? await ctx.storage.getUrl(gig.flyStorageId)
      : null,
    lineup: gig.lineup,
    performers,
    genres: gig.genres,
    desc: gig.desc,
    ticketing: gig.ticketing,
    ageRequirement: gig.ageRequirement ?? "allAges",
    externalUrl: gig.externalUrl ?? null,
    cap: gig.cap,
    goingCount: gig.goingCount,
    createdByBand: gig.createdByBand ?? null,
    lifecycle: gig.lifecycle ?? "published",
    discoveryListingReady: gig.discoveryListingReady === true,
  };
}

export function toVenuePayload(venue: Doc<"venues">) {
  return {
    _id: venue._id,
    name: venue.name,
    area: venue.area,
    addr: venue.addr,
    distSF: venue.distSF,
    distOak: venue.distOak,
    lat: venue.lat,
    lng: venue.lng,
  };
}

export function toMediaPayload(
  media: Doc<"bandMedia">,
  url: string | null,
  heroStorageId: Id<"_storage"> | undefined,
) {
  return {
    _id: media._id,
    bandId: media.bandId,
    kind: media.kind,
    url,
    title: media.title,
    caption: media.caption ?? null,
    contentType: media.contentType ?? null,
    sizeBytes: media.sizeBytes ?? null,
    views: media.views ?? null,
    lengthSec: media.lengthSec ?? null,
    pinned: media.pinned,
    order: media.order,
    isHero: heroStorageId !== undefined && heroStorageId === media.storageId,
  };
}

export async function toUserPayload(ctx: QueryCtx, user: Doc<"users">) {
  const storedAvatarUrl = user.avatarStorageId
    ? await ctx.storage.getUrl(user.avatarStorageId)
    : null;
  return {
    _id: user._id,
    clerkId: user.clerkId,
    name: user.name,
    email: user.email,
    genres: user.genres,
    attendedCount: user.attendedCount,
    createdAt: user._creationTime,
    avatarUrl: storedAvatarUrl ?? user.avatarUrl ?? null,
    bio: user.bio?.trim() ? user.bio : null,
    homeLocation: user.homeLocation ?? null,
    locationPersonalizationEnabled:
      user.locationPersonalizationEnabled ?? false,
    followedBandUpdatesEnabled: user.followedBandUpdatesEnabled ?? true,
    profileTutorialCompleted: user.profileTutorialCompleted ?? false,
    fanOnboarding:
      user.fanOnboarding === undefined
        ? null
        : {
            preferredCity: user.fanOnboarding.preferredCity ?? null,
            genreChoice: user.fanOnboarding.genreChoice,
            collapsed: user.fanOnboarding.collapsed,
          },
  };
}

// ─── Misc shared constants ──────────────────────────────────────────────────

/** Feed shows gigs with startsAt >= now - 6h. */
export const FEED_GRACE_MS = 6 * 60 * 60 * 1000;

/** Hard ceiling on feed-style index range reads. */
export const MAX_FEED_GIGS = 200;

/** Ceiling on `gigs:pastForBand`. Read through the `gigBands` index, so this
 * bounds one band's own past gigs — not, as it once did, a global scan window
 * that other bands' gigs could crowd a band's history out of. */
export const MAX_PAST_GIGS = 200;

/** Ceiling on `gigs:forBand`, applied to one band's indexed calendar rather
 * than the shared discovery window. */
export const MAX_UPCOMING_GIGS_PER_BAND = 200;

/** Maximum band gigs included in one fan recap. Every one of them costs up to
 * MAX_RSVPS_PER_GIG row reads, so this is the number the ~16k document read
 * limit actually constrains: 40 × 300 = 12,000 worst case, leaving headroom
 * for the gig, venue and membership reads around it. `pastForBand` lists the
 * band's history far past this — the cap is on fan-level analysis, not on the
 * events a band can see. */
export const MAX_RECAP_GIGS = 40;

/** Maximum RSVP rows measured for one gig in a fan recap. */
export const MAX_RSVPS_PER_GIG = 300;

/** Minimum distinct fans required in every row of a private partition. */
export const K_ANON_FANS = 5;

/** The venue table is a small curated list, not user-generated, so one read
 * returns all of it. */
export const MAX_VENUES = 500;

// ─── Fan profile limits ────────────────────────────────────────────────────

export const MAX_PROFILE_NAME_LENGTH = 100;
export const MAX_PROFILE_BIO_LENGTH = 500;
export const MAX_PROFILE_GENRES = 20;
export const MAX_PROFILE_GENRE_LENGTH = 50;

// ─── Band media limits ──────────────────────────────────────────────────────

/** Both the insert cap and every `.take()` on `bandMedia`, so "the whole
 * ordered list fits in one read" holds by construction. */
export const MAX_MEDIA_PER_BAND = 50;

export const MAX_MEDIA_BYTES = 100 * 1024 * 1024;

export const PHOTO_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
]);

/** `video/quicktime` is not optional: every legacy clip in the deployment is a
 * .mov, so rejecting it would orphan the entire existing library. */
export const VIDEO_CONTENT_TYPES = new Set([
  "video/mp4",
  "video/quicktime",
  "video/webm",
]);

export const MAX_MEDIA_TITLE = 200;
export const MAX_MEDIA_CAPTION = 500;
/** Four hours — long enough for a full set, short enough to catch garbage. */
export const MAX_MEDIA_LENGTH_SEC = 4 * 60 * 60;

export function isBandProfileComplete(band: Doc<"bands">): boolean {
  return (
    band.name.trim() !== "" &&
    band.genres.length >= 1 &&
    band.genres.length <= 3 &&
    band.genres.every((genre) => genre.trim() !== "") &&
    band.area.trim() !== "" &&
    (band.bio?.trim() ?? "") !== ""
  );
}

/** True only for an assigned, live image upload accepted by the same storage
 * rules as band photos. Legacy or deleted references fail closed. */
export async function hasValidProfileImage(
  ctx: QueryCtx | MutationCtx,
  band: Doc<"bands">,
): Promise<boolean> {
  if (band.imageStorageId === undefined) return false;
  const upload = await ctx.db.system.get("_storage", band.imageStorageId);
  if (!upload) return false;
  try {
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
    return true;
  } catch {
    return false;
  }
}

/**
 * Throws unless the uploaded blob is acceptable for `kind`.
 *
 * Pure, so the size and type rules are testable without allocating a 100 MB
 * Blob in the edge-runtime VM.
 *
 * `contentType` is rejected only when present AND disallowed. It is absent in
 * convex-test (which records `_storage` docs as `{size, sha256}` only) and on
 * some legacy blobs, and it is never sniffed — it is whatever header the
 * uploader sent. So this is hygiene (an .mp4 filed as a photo breaks the
 * gallery renderer), not a security control.
 */
export function assertUploadAcceptable(
  meta: { size: number; contentType?: string },
  kind: "video" | "photo",
): void {
  if (meta.size > MAX_MEDIA_BYTES) {
    throw new Error("That file is too big — 100 MB max.");
  }
  const allowed = kind === "video" ? VIDEO_CONTENT_TYPES : PHOTO_CONTENT_TYPES;
  if (meta.contentType !== undefined && !allowed.has(meta.contentType)) {
    throw new Error(`${meta.contentType} can't be posted as a ${kind}.`);
  }
}
