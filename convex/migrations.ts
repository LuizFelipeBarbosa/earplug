import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { bandColorFor, initialsFor, uniqueSlug } from "./lib/helpers";

// One-shot artifacts: run dry, then live, against production, then delete this
// file. Every table scan is deliberately bounded: the production dataset is a
// few hundred rows, and these mutations are not a general-purpose batcher.

// ─── shared helpers ─────────────────────────────────────────────────────────

type StepCounters = {
  migrated: number;
  skipped: number;
  alreadyDone: number;
};

const stepCountersValidator = v.object({
  migrated: v.number(),
  skipped: v.number(),
  alreadyDone: v.number(),
});

const zeroCounters = (): StepCounters => ({
  migrated: 0,
  skipped: 0,
  alreadyDone: 0,
});

/** A fully completed re-run reports no work, rather than the number of source
 * rows it recognized as already migrated. Partial runs still report that
 * distinction, which is useful while recovering from an interrupted step. */
function finishCounters(counters: StepCounters): StepCounters {
  if (counters.migrated === 0 && counters.alreadyDone > 0) {
    return zeroCounters();
  }
  return counters;
}

const SF_ANCHOR = { lat: 37.7749, lng: -122.4194 };
const OAK_ANCHOR = { lat: 37.8044, lng: -122.2712 };
const EARTH_RADIUS_MI = 3958.8;
const PDT_OFFSET_MS = 7 * 60 * 60 * 1000;
const MONTHS = [
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC",
];

function milesBetween(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const toRadians = (degrees: number) => (degrees * Math.PI) / 180;
  const dLat = toRadians(lat2 - lat1);
  const dLng = toRadians(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) ** 2;
  return EARTH_RADIUS_MI * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatMiles(miles: number): string {
  return `${miles.toFixed(1)} mi`;
}

/** Extracts one normalized @handle from a legacy Instagram profile URL. */
export function instagramHandle(url: string): string | undefined {
  const match = url.match(/instagram\.com\/([^/?#]*)/i);
  if (!match) return undefined;
  const segment = match[1]
    .split(/[?#]/, 1)[0]
    .replace(/\/$/, "")
    .replace(/^@/, "")
    .trim();
  return segment === "" ? undefined : `@${segment}`;
}

/** All 14 production event dates are PDT, so this migration intentionally
 * applies a fixed UTC-7 offset rather than daylight-saving rules. */
export function doorsTime(startsAt: number): string {
  const date = new Date(startsAt - PDT_OFFSET_MS);
  const hour24 = date.getUTCHours();
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minutes =
    date.getUTCMinutes() === 0
      ? ""
      : `:${String(date.getUTCMinutes()).padStart(2, "0")}`;
  return `${hour12}${minutes}${hour24 < 12 ? "AM" : "PM"}`;
}

/** "APR 3" for a millisecond timestamp, in Pacific time. */
export function pastShowMeta(startsAt: number): string {
  const date = new Date(startsAt - PDT_OFFSET_MS);
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCDate()}`;
}

type FollowerSource = "legacy" | "contract";

/** Shared by the early band reshape and the authoritative final backfill. */
async function followerCountFor(
  ctx: MutationCtx,
  bandId: Id<"bands">,
  source: FollowerSource,
): Promise<number> {
  if (source === "legacy") {
    const savedArtists = await ctx.db.query("savedArtists").take(1000);
    const memberships = await ctx.db.query("bandMemberships").take(1000);
    return (
      savedArtists.filter((row) => row.bandId === bandId).length +
      memberships.filter((row) => row.bandId === bandId).length
    );
  }

  const follows = await ctx.db
    .query("follows")
    .withIndex("by_band", (q) => q.eq("bandId", bandId))
    .take(1000);
  const members = await ctx.db
    .query("bandMembers")
    .withIndex("by_band", (q) => q.eq("bandId", bandId))
    .take(1000);
  return follows.length + members.length;
}

type EventToGigMap = Map<Id<"events">, Id<"gigs">>;

async function eventToGigMap(ctx: MutationCtx): Promise<EventToGigMap> {
  const result: EventToGigMap = new Map();
  for (const gig of await ctx.db.query("gigs").take(1000)) {
    if (gig.legacyEventId !== undefined && !result.has(gig.legacyEventId)) {
      result.set(gig.legacyEventId, gig._id);
    }
  }
  return result;
}

function pairKey(left: string, right: string): string {
  return `${left}:${right}`;
}

// ─── step 1: users reshape (in place) ───────────────────────────────────────

async function doMigrateUsers(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();

  for (const user of await ctx.db.query("users").take(1000)) {
    if (user.attendedCount !== undefined) {
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.patch(user._id, {
        email: user.email ?? "",
        genres: user.genres ?? user.topGenres ?? [],
        attendedCount: user.showsAttended ?? 0,
        ...(user.avatarUrl === undefined && user.avatar !== undefined
          ? { avatarUrl: user.avatar }
          : {}),
        // Remove legacy fields. avatarStorageId deliberately survives.
        avatar: undefined,
        location: undefined,
        memberSince: undefined,
        phoneNumber: undefined,
        role: undefined,
        showsAttended: undefined,
        topGenres: undefined,
      });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 2: bands reshape (in place) ───────────────────────────────────────

async function doMigrateBands(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();

  for (const band of await ctx.db.query("bands").take(1000)) {
    if (band.slug !== undefined) {
      counters.alreadyDone++;
      continue;
    }

    const links = band.socialLinks;
    const linkIg =
      links?.instagram !== undefined
        ? instagramHandle(links.instagram)
        : undefined;
    const legacySocialLinks = {
      ...(links?.spotify !== undefined ? { spotify: links.spotify } : {}),
      ...(links?.appleMusic !== undefined
        ? { appleMusic: links.appleMusic }
        : {}),
      ...(links?.tiktok !== undefined ? { tiktok: links.tiktok } : {}),
      ...(links?.website !== undefined ? { website: links.website } : {}),
    };
    const hasLegacySocialLinks = Object.keys(legacySocialLinks).length > 0;
    const followerCount = await followerCountFor(ctx, band._id, "legacy");
    const slug = await uniqueSlug(ctx, band.name);

    if (!dryRun) {
      await ctx.db.patch(band._id, {
        area: band.location?.split(",", 1)[0].trim() ?? "",
        colorHex: bandColorFor(band.name),
        initials: initialsFor(band.name),
        followerCount,
        slug,
        bio: band.bio ?? "",
        pastShows: [],
        ...(linkIg !== undefined ? { linkIg } : {}),
        ...(links?.youtube !== undefined ? { linkYt: links.youtube } : {}),
        ...(hasLegacySocialLinks ? { legacySocialLinks } : {}),
        // Remove legacy fields. imageStorageId deliberately survives.
        createdAt: undefined,
        genre: undefined,
        image: undefined,
        location: undefined,
        memberCount: undefined,
        socialLinks: undefined,
        userId: undefined,
      });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 3: venues reshape (in place) ──────────────────────────────────────

async function doMigrateVenues(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();

  for (const venue of await ctx.db.query("venues").take(1000)) {
    if (venue.area !== undefined) {
      counters.alreadyDone++;
      continue;
    }

    const lat = venue.coordinates?.lat ?? venue.lat ?? 0;
    const lng = venue.coordinates?.lng ?? venue.lng ?? 0;
    if (!dryRun) {
      await ctx.db.patch(venue._id, {
        area: venue.city ?? "",
        addr: venue.address ?? "",
        lat,
        lng,
        distSF: formatMiles(
          milesBetween(lat, lng, SF_ANCHOR.lat, SF_ANCHOR.lng),
        ),
        distOak: formatMiles(
          milesBetween(lat, lng, OAK_ANCHOR.lat, OAK_ANCHOR.lng),
        ),
        address: undefined,
        capacity: undefined,
        city: undefined,
        coordinates: undefined,
      });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 4: bandMemberships → bandMembers ─────────────────────────────────

async function doMigrateMemberships(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const seenPairs = new Set<string>();

  for (const membership of await ctx.db.query("bandMemberships").take(1000)) {
    const { bandId, userId } = membership;
    if (
      bandId === undefined ||
      userId === undefined ||
      (await ctx.db.get(bandId)) === null ||
      (await ctx.db.get(userId)) === null
    ) {
      counters.skipped++;
      continue;
    }

    const key = pairKey(bandId, userId);
    if (seenPairs.has(key)) {
      counters.alreadyDone++;
      continue;
    }
    const existing = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", bandId).eq("userId", userId),
      )
      .unique();
    if (existing !== null) {
      seenPairs.add(key);
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId,
        role:
          membership.role === "owner" || membership.role === "admin"
            ? "admin"
            : "member",
      });
    }
    seenPairs.add(key);
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 5: savedArtists → follows ─────────────────────────────────────────

async function doMigrateSaves(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const seenPairs = new Set<string>();

  for (const saved of await ctx.db.query("savedArtists").take(1000)) {
    const { bandId, userId } = saved;
    if (
      bandId === undefined ||
      userId === undefined ||
      (await ctx.db.get(bandId)) === null ||
      (await ctx.db.get(userId)) === null
    ) {
      counters.skipped++;
      continue;
    }

    const key = pairKey(userId, bandId);
    if (seenPairs.has(key)) {
      counters.alreadyDone++;
      continue;
    }
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_user_band", (q) =>
        q.eq("userId", userId).eq("bandId", bandId),
      )
      .unique();
    if (existing !== null) {
      seenPairs.add(key);
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.insert("follows", { userId, bandId });
    }
    seenPairs.add(key);
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 6: events → gigs ──────────────────────────────────────────────────

type EventsMigrationResult = {
  counters: StepCounters;
  map: EventToGigMap;
};

async function doMigrateEvents(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<EventsMigrationResult> {
  const counters = zeroCounters();
  const map = await eventToGigMap(ctx);

  for (const event of await ctx.db.query("events").take(1000)) {
    if (map.has(event._id)) {
      counters.alreadyDone++;
      continue;
    }
    if (
      event.title === undefined ||
      event.bandId === undefined ||
      event.venueId === undefined ||
      event.dateTime === undefined
    ) {
      counters.skipped++;
      continue;
    }

    if (!dryRun) {
      const gigId = await ctx.db.insert("gigs", {
        title: event.title,
        venueId: event.venueId,
        price: Math.round((event.price ?? 0) / 100),
        startsAt: event.dateTime,
        doorsTime: doorsTime(event.dateTime),
        flyKey: event.imageStorageId === undefined ? "paper" : "custom",
        ...(event.imageStorageId !== undefined
          ? { flyStorageId: event.imageStorageId }
          : {}),
        lineup: [event.bandId],
        genres: event.genres ?? [],
        desc: event.description ?? "",
        ticketing: "rsvp",
        cap: event.capacity === undefined ? "No cap" : String(event.capacity),
        goingCount: 0,
        createdByBand: event.bandId,
        legacyEventId: event._id,
      });
      map.set(event._id, gigId);
    }
    counters.migrated++;
  }

  return { counters: finishCounters(counters), map };
}

// ─── step 7: rsvps → gigRsvps ───────────────────────────────────────────────

async function doMigrateRsvps(
  ctx: MutationCtx,
  dryRun: boolean,
  suppliedMap?: EventToGigMap,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const map = suppliedMap ?? (await eventToGigMap(ctx));
  const seenPairs = new Set<string>();

  for (const rsvp of await ctx.db.query("rsvps").take(1000)) {
    if (rsvp.userId === undefined || rsvp.eventId === undefined) {
      counters.skipped++;
      continue;
    }
    const gigId = map.get(rsvp.eventId);
    if (gigId === undefined || (await ctx.db.get(rsvp.userId)) === null) {
      counters.skipped++;
      continue;
    }

    const key = pairKey(rsvp.userId, gigId);
    if (seenPairs.has(key)) {
      counters.alreadyDone++;
      continue;
    }
    const existing = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user_gig", (q) =>
        q.eq("userId", rsvp.userId!).eq("gigId", gigId),
      )
      .unique();
    if (existing !== null) {
      seenPairs.add(key);
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.insert("gigRsvps", {
        userId: rsvp.userId,
        gigId,
      });
    }
    seenPairs.add(key);
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 8: likes → gigSaves ───────────────────────────────────────────────

async function doMigrateLikes(
  ctx: MutationCtx,
  dryRun: boolean,
  suppliedMap?: EventToGigMap,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const map = suppliedMap ?? (await eventToGigMap(ctx));
  const seenPairs = new Set<string>();

  for (const like of await ctx.db.query("likes").take(1000)) {
    if (like.userId === undefined || like.eventId === undefined) {
      counters.skipped++;
      continue;
    }
    const gigId = map.get(like.eventId);
    if (gigId === undefined || (await ctx.db.get(like.userId)) === null) {
      counters.skipped++;
      continue;
    }

    const key = pairKey(like.userId, gigId);
    if (seenPairs.has(key)) {
      counters.alreadyDone++;
      continue;
    }
    const existing = await ctx.db
      .query("gigSaves")
      .withIndex("by_user_gig", (q) =>
        q.eq("userId", like.userId!).eq("gigId", gigId),
      )
      .unique();
    if (existing !== null) {
      seenPairs.add(key);
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.insert("gigSaves", {
        userId: like.userId,
        gigId,
      });
    }
    seenPairs.add(key);
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 9: bandMediaSlots + band heroes → bandMedia ──────────────────────

function assertDenseSlotOrder(
  bandId: Id<"bands">,
  slots: Doc<"bandMediaSlots">[],
): void {
  const orders = slots
    .map((slot) => slot.slotIndex)
    .sort((a, b) => (a ?? -1) - (b ?? -1));
  for (let expected = 0; expected < orders.length; expected++) {
    if (orders[expected] !== expected) {
      throw new Error(
        `Cannot migrate bandMediaSlots for band ${bandId}: slotIndex values must be dense from 0 through ${orders.length - 1}; found ${orders.join(", ")}.`,
      );
    }
  }
}

async function doMigrateMediaSlots(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const bands = await ctx.db.query("bands").take(1000);
  const slots = await ctx.db.query("bandMediaSlots").take(1000);
  const slotsByBand = new Map<Id<"bands">, Doc<"bandMediaSlots">[]>();

  for (const slot of slots) {
    if (slot.bandId === undefined) {
      counters.skipped++;
      continue;
    }
    const group = slotsByBand.get(slot.bandId) ?? [];
    group.push(slot);
    slotsByBand.set(slot.bandId, group);
  }

  // Assert every band's global sequence before attempting any writes. A
  // thrown mutation rolls back anyway, but validating up front makes the
  // failure independent of band creation order.
  for (const [bandId, bandSlots] of slotsByBand) {
    assertDenseSlotOrder(bandId, bandSlots);
  }

  const existingBandIds = new Set(bands.map((band) => band._id));
  for (const [bandId, bandSlots] of slotsByBand) {
    if (!existingBandIds.has(bandId)) {
      counters.skipped += bandSlots.length;
    }
  }

  for (const band of bands) {
    const bandSlots = (slotsByBand.get(band._id) ?? []).sort(
      (a, b) => (a.slotIndex ?? 0) - (b.slotIndex ?? 0),
    );
    const existingMedia = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order", (q) => q.eq("bandId", band._id))
      .take(1000);
    const storageIds = new Set(existingMedia.map((media) => media.storageId));
    let maxOrder = existingMedia.reduce(
      (highest, media) => Math.max(highest, media.order),
      -1,
    );
    let videoNumber = 0;
    let photoNumber = 0;
    const firstVideoOrder = bandSlots.find(
      (slot) => slot.mediaType === "video" && slot.mediaStorageId !== undefined,
    )?.slotIndex;

    for (const slot of bandSlots) {
      const isVideo = slot.mediaType === "video";
      const kindNumber = isVideo ? ++videoNumber : ++photoNumber;
      const storageId = slot.mediaStorageId;
      if (storageId === undefined || slot.slotIndex === undefined) {
        counters.skipped++;
        continue;
      }
      if (storageIds.has(storageId)) {
        counters.alreadyDone++;
        continue;
      }

      const title =
        slot.caption !== undefined && slot.caption !== ""
          ? slot.caption
          : `${isVideo ? "Clip" : "Photo"} ${kindNumber}`;
      if (!dryRun) {
        await ctx.db.insert("bandMedia", {
          bandId: band._id,
          kind: isVideo ? "video" : "photo",
          storageId,
          ...(slot.mimeType !== undefined
            ? { contentType: slot.mimeType }
            : {}),
          ...(slot.fileSizeBytes !== undefined
            ? { sizeBytes: slot.fileSizeBytes }
            : {}),
          title,
          ...(slot.caption !== undefined ? { caption: slot.caption } : {}),
          order: slot.slotIndex,
          pinned: isVideo && slot.slotIndex === firstVideoOrder,
          ...(isVideo ? { views: 0 } : {}),
          ...(isVideo && slot.durationSeconds !== undefined
            ? { lengthSec: slot.durationSeconds }
            : {}),
        });
      }
      storageIds.add(storageId);
      maxOrder = Math.max(maxOrder, slot.slotIndex);
      counters.migrated++;
    }

    const heroStorageId = band.imageStorageId;
    if (heroStorageId === undefined) continue;
    if (storageIds.has(heroStorageId)) {
      counters.alreadyDone++;
      continue;
    }

    if (!dryRun) {
      await ctx.db.insert("bandMedia", {
        bandId: band._id,
        kind: "photo",
        storageId: heroStorageId,
        title: "Profile photo",
        order: maxOrder + 1,
        pinned: false,
      });
    }
    storageIds.add(heroStorageId);
    maxOrder++;
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 10: authoritative gig RSVP counts ────────────────────────────────

async function doBackfillGoingCounts(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();

  for (const gig of await ctx.db.query("gigs").take(1000)) {
    if (gig.legacyEventId === undefined) continue;
    const rsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_gig", (q) => q.eq("gigId", gig._id))
      .take(1000);
    if (gig.goingCount === rsvps.length) {
      counters.alreadyDone++;
      continue;
    }
    if (!dryRun) {
      await ctx.db.patch(gig._id, { goingCount: rsvps.length });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 11: authoritative band follower counts ───────────────────────────

async function doBackfillFollowerCounts(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();

  for (const band of await ctx.db.query("bands").take(1000)) {
    const followerCount = await followerCountFor(ctx, band._id, "contract");
    if (band.followerCount === followerCount) {
      counters.alreadyDone++;
      continue;
    }
    if (!dryRun) {
      await ctx.db.patch(band._id, { followerCount });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── step 12: authoritative past-show summaries ─────────────────────────────

function samePastShows(
  current: Doc<"bands">["pastShows"],
  next: { title: string; meta: string }[],
): boolean {
  if (current === undefined || current.length !== next.length) return false;
  return current.every(
    (show, index) =>
      show.title === next[index].title && show.meta === next[index].meta,
  );
}

async function doBackfillPastShows(
  ctx: MutationCtx,
  dryRun: boolean,
): Promise<StepCounters> {
  const counters = zeroCounters();
  const now = Date.now();
  const migratedGigs = (await ctx.db.query("gigs").take(1000)).filter(
    (gig) => gig.legacyEventId !== undefined,
  );

  for (const band of await ctx.db.query("bands").take(1000)) {
    const pastShows = migratedGigs
      .filter((gig) => gig.startsAt < now && gig.lineup.includes(band._id))
      .sort((a, b) => b.startsAt - a.startsAt)
      .map((gig) => ({
        title: gig.title,
        meta: pastShowMeta(gig.startsAt),
      }));
    if (samePastShows(band.pastShows, pastShows)) {
      counters.alreadyDone++;
      continue;
    }
    if (!dryRun) {
      await ctx.db.patch(band._id, { pastShows });
    }
    counters.migrated++;
  }

  return finishCounters(counters);
}

// ─── registered migration steps ─────────────────────────────────────────────

export const migrateUsers = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateUsers(ctx, args.dryRun ?? true),
});

export const migrateBands = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateBands(ctx, args.dryRun ?? true),
});

export const migrateVenues = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateVenues(ctx, args.dryRun ?? true),
});

export const migrateMemberships = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    await doMigrateMemberships(ctx, args.dryRun ?? true),
});

export const migrateSaves = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateSaves(ctx, args.dryRun ?? true),
});

export const migrateEvents = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    (await doMigrateEvents(ctx, args.dryRun ?? true)).counters,
});

export const migrateRsvps = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateRsvps(ctx, args.dryRun ?? true),
});

export const migrateLikes = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) => await doMigrateLikes(ctx, args.dryRun ?? true),
});

export const migrateMediaSlots = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    await doMigrateMediaSlots(ctx, args.dryRun ?? true),
});

export const backfillGoingCounts = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    await doBackfillGoingCounts(ctx, args.dryRun ?? true),
});

export const backfillFollowerCounts = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    await doBackfillFollowerCounts(ctx, args.dryRun ?? true),
});

export const backfillPastShows = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: stepCountersValidator,
  handler: async (ctx, args) =>
    await doBackfillPastShows(ctx, args.dryRun ?? true),
});

export const migrateAll = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({
    users: stepCountersValidator,
    bands: stepCountersValidator,
    venues: stepCountersValidator,
    memberships: stepCountersValidator,
    saves: stepCountersValidator,
    events: stepCountersValidator,
    rsvps: stepCountersValidator,
    likes: stepCountersValidator,
    mediaSlots: stepCountersValidator,
    goingCounts: stepCountersValidator,
    followerCounts: stepCountersValidator,
    pastShows: stepCountersValidator,
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const users = await doMigrateUsers(ctx, dryRun);
    const bands = await doMigrateBands(ctx, dryRun);
    const venues = await doMigrateVenues(ctx, dryRun);
    const memberships = await doMigrateMemberships(ctx, dryRun);
    const saves = await doMigrateSaves(ctx, dryRun);
    const eventsResult = await doMigrateEvents(ctx, dryRun);
    const rsvps = await doMigrateRsvps(ctx, dryRun, eventsResult.map);
    const likes = await doMigrateLikes(ctx, dryRun, eventsResult.map);
    const mediaSlots = await doMigrateMediaSlots(ctx, dryRun);
    const goingCounts = await doBackfillGoingCounts(ctx, dryRun);
    const followerCounts = await doBackfillFollowerCounts(ctx, dryRun);
    const pastShows = await doBackfillPastShows(ctx, dryRun);

    return {
      users,
      bands,
      venues,
      memberships,
      saves,
      events: eventsResult.counters,
      rsvps,
      likes,
      mediaSlots,
      goingCounts,
      followerCounts,
      pastShows,
    };
  },
});

// ─── guarded legacy purge (never called by migrateAll) ──────────────────────

const PURGED_TABLES = [
  "eventTickets",
  "bandInvites",
  "bandProfileEngagements",
  "eventCohostInvites",
  "notifications",
  "events",
  "rsvps",
  "likes",
  "bandMemberships",
  "savedArtists",
  "bandMediaSlots",
] as const;

export const purgeLegacy = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({
    deleted: v.number(),
    legacyEventIdsCleared: v.number(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const gigs = await ctx.db.query("gigs").take(1000);
    const map: EventToGigMap = new Map();
    for (const gig of gigs) {
      if (gig.legacyEventId !== undefined && !map.has(gig.legacyEventId)) {
        map.set(gig.legacyEventId, gig._id);
      }
    }

    const events = await ctx.db.query("events").take(1000);
    const rsvps = await ctx.db.query("rsvps").take(1000);
    const likes = await ctx.db.query("likes").take(1000);
    const memberships = await ctx.db.query("bandMemberships").take(1000);
    const savedArtists = await ctx.db.query("savedArtists").take(1000);
    const mediaSlots = await ctx.db.query("bandMediaSlots").take(1000);

    for (const event of events) {
      if (!map.has(event._id)) {
        throw new Error(
          `Refusing to purge events row ${event._id}: no gig has legacyEventId ${event._id}. Run and verify migrateEvents first.`,
        );
      }
    }
    for (const rsvp of rsvps) {
      if (rsvp.eventId === undefined || !map.has(rsvp.eventId)) {
        throw new Error(
          `Refusing to purge rsvps row ${rsvp._id}: its legacy event has no migrated gig.`,
        );
      }
    }
    for (const like of likes) {
      if (like.eventId === undefined || !map.has(like.eventId)) {
        throw new Error(
          `Refusing to purge likes row ${like._id}: its legacy event has no migrated gig.`,
        );
      }
    }

    const contractMemberships = new Set(
      (await ctx.db.query("bandMembers").take(1000)).map((row) =>
        pairKey(row.bandId, row.userId),
      ),
    );
    for (const membership of memberships) {
      if (
        membership.bandId === undefined ||
        membership.userId === undefined ||
        !contractMemberships.has(pairKey(membership.bandId, membership.userId))
      ) {
        throw new Error(
          `Refusing to purge bandMemberships row ${membership._id}: no matching bandMembers row exists.`,
        );
      }
    }

    const contractFollows = new Set(
      (await ctx.db.query("follows").take(1000)).map((row) =>
        pairKey(row.userId, row.bandId),
      ),
    );
    for (const saved of savedArtists) {
      if (
        saved.userId === undefined ||
        saved.bandId === undefined ||
        !contractFollows.has(pairKey(saved.userId, saved.bandId))
      ) {
        throw new Error(
          `Refusing to purge savedArtists row ${saved._id}: no matching follows row exists.`,
        );
      }
    }

    const contractMedia = new Set(
      (await ctx.db.query("bandMedia").take(1000)).map((row) =>
        pairKey(row.bandId, row.storageId),
      ),
    );
    for (const slot of mediaSlots) {
      if (
        slot.bandId === undefined ||
        slot.mediaStorageId === undefined ||
        !contractMedia.has(pairKey(slot.bandId, slot.mediaStorageId))
      ) {
        throw new Error(
          `Refusing to purge bandMediaSlots row ${slot._id}: no matching bandMedia row exists.`,
        );
      }
    }

    let deleted = 0;
    for (const table of PURGED_TABLES) {
      for (const row of await ctx.db.query(table).take(1000)) {
        if (!dryRun) await ctx.db.delete(row._id);
        deleted++;
      }
    }

    const gigsWithLegacyIds = gigs.filter(
      (gig) => gig.legacyEventId !== undefined,
    );
    if (!dryRun) {
      for (const gig of gigsWithLegacyIds) {
        await ctx.db.patch(gig._id, { legacyEventId: undefined });
      }
    }

    return {
      deleted,
      legacyEventIdsCleared: gigsWithLegacyIds.length,
    };
  },
});
