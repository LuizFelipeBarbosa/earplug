import { v } from "convex/values";
import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";

// ─── Deterministic band identity ────────────────────────────────────────────
// Shared by bands:createBand AND migrations:migrateAll so the two can't drift.

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
  return await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.subject))
    .unique();
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

// ─── Contract payload validators + converters ───────────────────────────────

export const pastShowPayload = v.object({
  title: v.string(),
  meta: v.string(),
});

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
  pastShows: v.array(pastShowPayload),
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

export const gigPayloadValidator = v.object({
  _id: v.id("gigs"),
  title: v.string(),
  venueId: v.id("venues"),
  price: v.number(),
  startsAt: v.number(),
  doorsTime: v.string(),
  flyKey: v.string(),
  flyerUrl: v.union(v.string(), v.null()),
  lineup: v.array(v.id("bands")),
  genres: v.array(v.string()),
  desc: v.string(),
  ticketing: v.union(v.literal("rsvp"), v.literal("external")),
  externalUrl: v.union(v.string(), v.null()),
  cap: v.string(),
  goingCount: v.number(),
  createdByBand: v.union(v.id("bands"), v.null()),
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
});

// `?? null` on the optional fields is the payload contract (explicit nulls,
// never absent keys), not a defensive default — the rest are required by the
// schema, so a missing one is a bug worth failing on.
/** Known fan-out cost, accepted for v1: resolving the hero joins its `_storage`
 * row into every reader's read set — including `gigs:feed`, where one band's
 * hero change re-fires the feed for every subscribed client. First thing to
 * revisit if the feed gets hot. */
export async function toBandPayload(ctx: QueryCtx, band: Doc<"bands">) {
  return {
    _id: band._id,
    name: band.name,
    genres: band.genres,
    area: band.area ?? "", // TODO(prod-migration): remove at tighten
    colorHex: band.colorHex ?? "", // TODO(prod-migration): remove at tighten
    initials: band.initials ?? "", // TODO(prod-migration): remove at tighten
    followerCount: band.followerCount ?? 0, // TODO(prod-migration): remove at tighten
    heroUrl: band.imageStorageId
      ? await ctx.storage.getUrl(band.imageStorageId)
      : null,
    bio: band.bio ?? "",
    linkIg: band.linkIg ?? null,
    linkBc: band.linkBc ?? null,
    pastShows: band.pastShows ?? [], // TODO(prod-migration): remove at tighten
  };
}

export async function toGigPayload(ctx: QueryCtx, gig: Doc<"gigs">) {
  return {
    _id: gig._id,
    title: gig.title,
    venueId: gig.venueId,
    price: gig.price,
    startsAt: gig.startsAt,
    doorsTime: gig.doorsTime,
    flyKey: gig.flyKey,
    flyerUrl: gig.flyStorageId
      ? await ctx.storage.getUrl(gig.flyStorageId)
      : null,
    lineup: gig.lineup,
    genres: gig.genres,
    desc: gig.desc,
    ticketing: gig.ticketing,
    externalUrl: gig.externalUrl ?? null,
    cap: gig.cap,
    goingCount: gig.goingCount,
    createdByBand: gig.createdByBand ?? null,
  };
}

export function toVenuePayload(venue: Doc<"venues">) {
  return {
    _id: venue._id,
    name: venue.name,
    area: venue.area ?? "", // TODO(prod-migration): remove at tighten
    addr: venue.addr ?? "", // TODO(prod-migration): remove at tighten
    distSF: venue.distSF ?? "", // TODO(prod-migration): remove at tighten
    distOak: venue.distOak ?? "", // TODO(prod-migration): remove at tighten
    lat: venue.lat ?? 0, // TODO(prod-migration): remove at tighten
    lng: venue.lng ?? 0, // TODO(prod-migration): remove at tighten
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

export function toUserPayload(user: Doc<"users">) {
  return {
    _id: user._id,
    clerkId: user.clerkId,
    name: user.name,
    email: user.email,
    genres: user.genres ?? [], // TODO(prod-migration): remove at tighten
    attendedCount: user.attendedCount ?? 0, // TODO(prod-migration): remove at tighten
    createdAt: user._creationTime,
  };
}

// ─── Misc shared constants ──────────────────────────────────────────────────

/** Feed shows gigs with startsAt >= now - 6h. */
export const FEED_GRACE_MS = 6 * 60 * 60 * 1000;

/** Hard ceiling on feed-style index range reads. */
export const MAX_FEED_GIGS = 200;

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
  const allowed =
    kind === "video" ? VIDEO_CONTENT_TYPES : PHOTO_CONTENT_TYPES;
  if (meta.contentType !== undefined && !allowed.has(meta.contentType)) {
    throw new Error(`${meta.contentType} can't be posted as a ${kind}.`);
  }
}
