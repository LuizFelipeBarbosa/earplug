import { WithoutSystemFields } from "convex/server";
import { Infer, v } from "convex/values";
import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { readFeedCutoff } from "../clock";
import { DocCache } from "./docCache";
import {
  addressDisclosureValidator,
  ageRequirementValidator,
  fanCityValidator,
  fanGenreChoiceValidator,
  gigLifecycleValidator,
  gigPublicPerformerValidator,
  pastShowValidator,
  reviewSummaryValidator,
  venueTypeValidator,
} from "../schema";
import { approximateLocation, formatMiles, OAK_CENTER, SF_CENTER } from "./geo";

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

const RESERVED_PUBLIC_SLUGS = new Set([
  "g",
  "join",
  "gig-invite",
  "check-in",
  "opportunities",
  "venues",
  "apply",
  "org",
  "orgs",
  "band",
  "checkout",
  "t",
  "admin",
]);

export function isReservedPublicSlug(slug: string): boolean {
  return RESERVED_PUBLIC_SLUGS.has(slug);
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
    if (isReservedPublicSlug(candidate)) continue;
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

/** Throwing: the current user's doc for any function that needs a signed-in,
 * live account. `MutationCtx` extends `QueryCtx`, so this serves both. */
export async function requireUser(ctx: QueryCtx): Promise<Doc<"users">> {
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

/** The one band-membership guard, for queries and mutations alike. Throws
 * unless the caller is signed in with a live user row and holds `role` in the
 * band: `"admin"` requires the admin role, `"member"` accepts either. Private
 * band queries intentionally throw instead of returning an empty payload to
 * an unauthorized caller. An archived band reads as missing unless
 * `allowArchived` is set (only `bands:archive` and `bands:archiveStatus`, which
 * must keep answering the original admin after the tombstone). */
export async function requireBandRole(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  options: { role: "admin" | "member"; allowArchived?: boolean },
): Promise<{ band: Doc<"bands">; user: Doc<"users"> }> {
  const user = await requireUser(ctx);
  const band = await ctx.db.get(bandId);
  if (!band || (band.archivedAt !== undefined && !options.allowArchived)) {
    throw new Error("Band not found");
  }
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", user._id),
    )
    .unique();
  if (options.role === "admin") {
    if (!membership || membership.role !== "admin") {
      throw new Error("Not an admin of this band");
    }
  } else if (!membership) {
    throw new Error("Not a member of this band");
  }
  return { band, user };
}

// ─── Contract payload validators + converters ───────────────────────────────

export const bandPayloadValidator = v.object({
  _id: v.id("bands"),
  slug: v.string(),
  name: v.string(),
  genres: v.array(v.string()),
  area: v.string(),
  colorHex: v.string(),
  initials: v.string(),
  followerCount: v.number(),
  heroUrl: v.union(v.string(), v.null()),
  avatarUrl: v.union(v.string(), v.null()),
  bannerUrl: v.union(v.string(), v.null()),
  bio: v.string(),
  linkIg: v.union(v.string(), v.null()),
  linkBc: v.union(v.string(), v.null()),
  linkYt: v.union(v.string(), v.null()),
  credits: v.union(v.string(), v.null()),
  profileComplete: v.boolean(),
  discoveryProfileReady: v.boolean(),
  // The wire shape is the stored shape here; reuse it rather than restating it.
  pastShows: v.array(pastShowValidator),
  reviewSummary: v.union(reviewSummaryValidator, v.null()),
});

/** The six presses offered by the client's gig-create picker. "custom" means
 * band-supplied art backed by gigs.flyStorageId; clients render a placeholder
 * plate when flyerUrl resolves null. The gigs.flyKey schema column stays
 * v.string() because legacy rows/seeds use older keys: paper, blue, black,
 * yellow, and bluetype. */
const flyKeyValidator = v.union(
  v.literal("xerox"),
  v.literal("riso"),
  v.literal("marquee"),
  v.literal("blueprint"),
  v.literal("sunburst"),
  v.literal("custom"),
);

/** Every flyer key the client can render, including legacy styles. */
export const knownFlyKeyValidator = v.union(
  v.literal("xerox"),
  v.literal("riso"),
  v.literal("marquee"),
  v.literal("blueprint"),
  v.literal("sunburst"),
  v.literal("custom"),
  v.literal("paper"),
  v.literal("blue"),
  v.literal("black"),
  v.literal("yellow"),
  v.literal("bluetype"),
);
export type KnownFlyKey = Infer<typeof knownFlyKeyValidator>;

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

export function isValidHttpsUrl(value: string | undefined): boolean {
  if (!value) return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" && parsed.host !== "";
  } catch {
    return false;
  }
}

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

/** Every non-auth check a gig publish performs, in one fixed order. Throws on
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
  if (args.ticketing === "external" && !isValidHttpsUrl(args.externalUrl)) {
    throw new Error("External ticketing requires a valid HTTPS URL");
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

/** The instant that divides "upcoming" from "past" for every feed-shaped read.
 * A clock singleton row is kept fresh by a 15-minute cron heartbeat (see
 * convex/clock.ts), so queries recompute when the row changes instead of
 * reading the wall clock directly after the first heartbeat. */
export async function feedCutoff(ctx: QueryCtx | MutationCtx): Promise<number> {
  return readFeedCutoff(ctx);
}

/** One band's published gigs on one side of the feed cutoff, at most `limit`
 * of them: past gigs newest first, upcoming gigs oldest first.
 *
 * Reads `gigBands.by_band_startsAt` rather than filtering the global gig range
 * by `lineup`, so the window bounds the band's own calendar and nothing else —
 * the discovery feed's cap cannot crowd a band's shows out of this result. A
 * join row whose gig has been deleted is skipped rather than trusted. */
async function publishedGigsForBand(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  limit: number,
  side: "past" | "upcoming",
): Promise<Doc<"gigs">[]> {
  const cutoff = await feedCutoff(ctx);
  const joinRows = await ctx.db
    .query("gigBands")
    .withIndex("by_band_startsAt", (q) =>
      side === "past"
        ? q.eq("bandId", bandId).lt("startsAt", cutoff)
        : q.eq("bandId", bandId).gte("startsAt", cutoff),
    )
    .order(side === "past" ? "desc" : "asc")
    .take(limit * 4);

  const gigs: Doc<"gigs">[] = [];
  for (const row of joinRows) {
    const gig = await ctx.db.get(row.gigId);
    if (gig && (gig.lifecycle ?? "published") === "published") gigs.push(gig);
    if (gigs.length === limit) break;
  }
  return gigs;
}

/** One band's past gigs, newest first, at most `limit` of them. */
export function pastGigsForBand(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  limit: number,
): Promise<Doc<"gigs">[]> {
  return publishedGigsForBand(ctx, bandId, limit, "past");
}

/** One band's upcoming gigs, oldest first, at most `limit` of them. */
export function upcomingGigsForBand(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  limit: number,
): Promise<Doc<"gigs">[]> {
  return publishedGigsForBand(ctx, bandId, limit, "upcoming");
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
  slug: v.string(),
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
  slug: v.union(v.string(), v.null()),
  approxLocation: v.object({
    lat: v.number(),
    lng: v.number(),
    label: v.string(),
  }),
  neighborhood: v.union(v.string(), v.null()),
  city: v.union(v.string(), v.null()),
  description: v.union(v.string(), v.null()),
  venueType: v.union(venueTypeValidator, v.null()),
  capacityPublic: v.union(v.number(), v.null()),
  addressDisclosure: addressDisclosureValidator,
  verified: v.boolean(),
  managedByOrganizationId: v.union(v.id("organizations"), v.null()),
  exactAddr: v.union(v.string(), v.null()),
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
  thumbnailUrl: v.union(v.string(), v.null()),
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
  isAvatar: v.boolean(),
  isBanner: v.boolean(),
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

function resolveArtworkStorageId(
  overrideStorageId: Id<"_storage"> | null | undefined,
  legacyStorageId: Id<"_storage"> | undefined,
): Id<"_storage"> | undefined {
  return overrideStorageId === undefined
    ? legacyStorageId
    : (overrideStorageId ?? undefined);
}

// `?? null` on the optional fields is the payload contract (explicit nulls,
// never absent keys), not a defensive default — the rest are required by the
// schema, so a missing one is a bug worth failing on.
/** Known fan-out cost, accepted for v1: resolving the hero joins its `_storage`
 * row into every reader's read set — `venues:detail`, `bands:list` and
 * `bands:search` among them — so one band's hero change re-fires those results
 * for every subscribed client. (`gigs:feedV2` ships summaries for this reason.) */
export async function toBandPayload(ctx: QueryCtx, band: Doc<"bands">) {
  const profileComplete = isBandProfileComplete(band);
  const profileImageReady = await hasValidProfileImage(ctx, band);
  const avatarStorageId = resolveArtworkStorageId(
    band.avatarStorageId,
    band.imageStorageId,
  );
  const bannerStorageId = resolveArtworkStorageId(
    band.bannerStorageId,
    band.imageStorageId,
  );
  const artworkUrls = new Map<Id<"_storage">, string | null>();
  for (const storageId of [
    band.imageStorageId,
    avatarStorageId,
    bannerStorageId,
  ]) {
    if (storageId && !artworkUrls.has(storageId)) {
      artworkUrls.set(storageId, await ctx.storage.getUrl(storageId));
    }
  }
  return {
    _id: band._id,
    slug: band.slug,
    name: band.name,
    genres: band.genres,
    area: band.area,
    colorHex: band.colorHex,
    initials: band.initials,
    followerCount: band.followerCount,
    heroUrl: band.imageStorageId
      ? (artworkUrls.get(band.imageStorageId) ?? null)
      : null,
    avatarUrl: avatarStorageId
      ? (artworkUrls.get(avatarStorageId) ?? null)
      : null,
    bannerUrl: bannerStorageId
      ? (artworkUrls.get(bannerStorageId) ?? null)
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
    reviewSummary: band.reviewSummary ?? null,
  };
}

/** The slim band shape `gigs:feedV2` ships: identity, avatar and readiness
 * flags only. Derived from the full validator so the two can never disagree on
 * a field's type. */
export const bandSummaryPayloadValidator = bandPayloadValidator.pick(
  "_id",
  "slug",
  "name",
  "genres",
  "area",
  "colorHex",
  "initials",
  "followerCount",
  "avatarUrl",
  "profileComplete",
  "discoveryProfileReady",
);

/** `toBandPayload` restricted to the summary fields, computed the same way so
 * every value matches the full payload's — at the cost of one `_storage` read
 * and one `storage.getUrl` per band instead of up to three of each. */
export async function toBandSummaryPayload(ctx: QueryCtx, band: Doc<"bands">) {
  const profileComplete = isBandProfileComplete(band);
  const profileImageReady = await hasValidProfileImage(ctx, band);
  const avatarStorageId = resolveArtworkStorageId(
    band.avatarStorageId,
    band.imageStorageId,
  );
  return {
    _id: band._id,
    slug: band.slug,
    name: band.name,
    genres: band.genres,
    area: band.area,
    colorHex: band.colorHex,
    initials: band.initials,
    followerCount: band.followerCount,
    avatarUrl: avatarStorageId
      ? await ctx.storage.getUrl(avatarStorageId)
      : null,
    profileComplete,
    discoveryProfileReady:
      profileComplete && profileImageReady && band.hasClip === true,
  };
}

/** The gig shape `gigs:feedV2` ships: the full payload minus `goingCount`, so
 * an RSVP anywhere no longer changes the feed's result. Counts travel through
 * `gigs:goingCounts` instead. */
export const gigFeedPayloadValidator = gigPayloadValidator.omit("goingCount");

export async function toGigFeedPayload(
  ctx: QueryCtx,
  gig: Doc<"gigs">,
  cache: DocCache,
) {
  const { goingCount: _goingCount, ...payload } = await toGigPayload(
    ctx,
    gig,
    cache,
  );
  return payload;
}

/** Pass one `docCache` across a hydration loop so gigs sharing a flyer or a
 * legacy lineup band read each row once. */
export async function toGigPayload(
  ctx: QueryCtx,
  gig: Doc<"gigs">,
  cache: DocCache,
) {
  const performers = [];
  if (gig.performers) {
    performers.push(...gig.performers);
  } else {
    for (let index = 0; index < gig.lineup.length; index++) {
      const band = await cache.get(gig.lineup[index]);
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
    slug: gig.slug ?? gig._id,
    title: gig.title,
    venueId: gig.venueId,
    price: gig.price,
    startsAt: gig.startsAt,
    doorsAt: gig.doorsAt ?? gig.startsAt,
    doorsTime: gig.doorsTime,
    flyKey: gig.flyKey,
    flyerUrl: gig.flyStorageId ? await cache.getUrl(gig.flyStorageId) : null,
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

export function effectiveAddressDisclosure(
  venue: Doc<"venues">,
): "onTicket" | "public" {
  if (venue.addressDisclosure !== undefined) return venue.addressDisclosure;
  return venue.status === undefined || venue.status === "legacy"
    ? "public"
    : "onTicket";
}

export function toVenuePayload(venue: Doc<"venues">) {
  const disclosure = effectiveAddressDisclosure(venue);
  const approx =
    venue.approxLat !== undefined && venue.approxLng !== undefined
      ? {
          lat: venue.approxLat,
          lng: venue.approxLng,
          label: venue.approxLabel ?? venue.area,
          neighborhood: venue.neighborhood ?? null,
          city: venue.city ?? null,
        }
      : approximateLocation({ lat: venue.lat, lng: venue.lng }, venue.area);
  const address =
    disclosure === "public"
      ? {
          addr: venue.addr,
          lat: venue.lat,
          lng: venue.lng,
          distSF: venue.distSF,
          distOak: venue.distOak,
          exactAddr: venue.addr,
        }
      : {
          addr: approx.label,
          lat: approx.lat,
          lng: approx.lng,
          distSF: formatMiles(SF_CENTER, approx),
          distOak: formatMiles(OAK_CENTER, approx),
          exactAddr: null,
        };

  return {
    _id: venue._id,
    name: venue.name,
    area: disclosure === "public" ? venue.area : approx.label,
    ...address,
    slug: venue.slug ?? null,
    approxLocation: {
      lat: approx.lat,
      lng: approx.lng,
      label: approx.label,
    },
    neighborhood: venue.neighborhood ?? approx.neighborhood ?? null,
    city: venue.city ?? approx.city ?? null,
    description: venue.description ?? null,
    venueType: venue.venueType ?? null,
    capacityPublic: venue.capacityPublic ?? null,
    addressDisclosure: disclosure,
    verified: venue.status === "verified",
    managedByOrganizationId: venue.managedByOrganizationId ?? null,
  };
}

export function toMediaPayload(
  media: Doc<"bandMedia">,
  url: string | null,
  thumbnailUrl: string | null,
  artwork: {
    legacyStorageId: Id<"_storage"> | undefined;
    avatarStorageId: Id<"_storage"> | null | undefined;
    bannerStorageId: Id<"_storage"> | null | undefined;
  },
) {
  const avatarStorageId = resolveArtworkStorageId(
    artwork.avatarStorageId,
    artwork.legacyStorageId,
  );
  const bannerStorageId = resolveArtworkStorageId(
    artwork.bannerStorageId,
    artwork.legacyStorageId,
  );
  return {
    _id: media._id,
    bandId: media.bandId,
    kind: media.kind,
    url,
    thumbnailUrl,
    title: media.title,
    caption: media.caption ?? null,
    contentType: media.contentType ?? null,
    sizeBytes: media.sizeBytes ?? null,
    views: media.views ?? null,
    lengthSec: media.lengthSec ?? null,
    pinned: media.pinned,
    order: media.order,
    // `isHero` is the legacy name for the band's profile photo. Keep it as an
    // alias of the avatar role for old clients; banners use `isBanner` only.
    isHero:
      avatarStorageId !== undefined && avatarStorageId === media.storageId,
    isAvatar:
      avatarStorageId !== undefined && avatarStorageId === media.storageId,
    isBanner:
      bannerStorageId !== undefined && bannerStorageId === media.storageId,
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

/** The venue list is now user- and organization-generated; `venues:list`
 * truncates at 500 pending real pagination. */
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
export const MAX_VIDEO_THUMBNAIL_BYTES = 2 * 1024 * 1024;

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
  const avatarStorageId = resolveArtworkStorageId(
    band.avatarStorageId,
    band.imageStorageId,
  );
  if (avatarStorageId === undefined) return false;
  const upload = await ctx.db.system.get("_storage", avatarStorageId);
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

export function assertVideoThumbnailAcceptable(meta: {
  size: number;
  contentType?: string;
}): void {
  if (meta.size > MAX_VIDEO_THUMBNAIL_BYTES) {
    throw new Error("That video thumbnail is too big — 2 MB max.");
  }
  if (meta.contentType !== undefined && meta.contentType !== "image/jpeg") {
    throw new Error("Video thumbnails must be JPEG images.");
  }
}
