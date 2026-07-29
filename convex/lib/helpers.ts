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
  bio: v.string(),
  linkIg: v.union(v.string(), v.null()),
  linkBc: v.union(v.string(), v.null()),
  pastShows: v.array(pastShowPayload),
});

/** The six presses offered by the client's gig-create picker. "custom" means
 * band-supplied art and is currently a v1 stub: no image/storage field backs it
 * yet, so clients render a placeholder plate. The gigs.flyKey schema column
 * stays v.string() because legacy rows/seeds use older keys: paper, blue, black,
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

export const videoPayloadValidator = v.object({
  _id: v.id("videos"),
  bandId: v.id("bands"),
  title: v.string(),
  views: v.number(),
  lengthSec: v.number(),
  pinned: v.boolean(),
  order: v.number(),
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

// Defensive defaults: the schema is widened during migration, so new fields
// may be transiently absent on legacy rows.
export function toBandPayload(band: Doc<"bands">) {
  return {
    _id: band._id,
    name: band.name,
    genres: band.genres,
    area: band.area ?? "",
    colorHex: band.colorHex ?? bandColorFor(band.name),
    initials: band.initials ?? initialsFor(band.name),
    followerCount: band.followerCount ?? 0,
    bio: band.bio ?? "",
    linkIg: band.linkIg ?? null,
    linkBc: band.linkBc ?? null,
    pastShows: band.pastShows ?? [],
  };
}

export function toGigPayload(gig: Doc<"gigs">) {
  return {
    _id: gig._id,
    title: gig.title,
    venueId: gig.venueId,
    price: gig.price,
    startsAt: gig.startsAt,
    doorsTime: gig.doorsTime,
    flyKey: gig.flyKey,
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
    area: venue.area ?? "",
    addr: venue.addr ?? "",
    distSF: venue.distSF ?? "",
    distOak: venue.distOak ?? "",
    lat: venue.lat ?? 0,
    lng: venue.lng ?? 0,
  };
}

export function toVideoPayload(video: Doc<"videos">) {
  return {
    _id: video._id,
    bandId: video.bandId,
    title: video.title,
    views: video.views,
    lengthSec: video.lengthSec,
    pinned: video.pinned,
    order: video.order,
  };
}

export function toUserPayload(user: Doc<"users">) {
  return {
    _id: user._id,
    clerkId: user.clerkId,
    name: user.name,
    email: user.email,
    genres: user.genres ?? [],
    attendedCount: user.attendedCount ?? 0,
    createdAt: user.memberSince ?? user._creationTime,
  };
}

// ─── Misc shared constants ──────────────────────────────────────────────────

/** Feed shows gigs with startsAt >= now - 6h. */
export const FEED_GRACE_MS = 6 * 60 * 60 * 1000;

/** Hard ceiling on feed-style index range reads. */
export const MAX_FEED_GIGS = 200;
