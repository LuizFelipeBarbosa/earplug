import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { bandColorFor, initialsFor, uniqueSlug } from "./lib/helpers";

// One-shot, idempotent/re-runnable reshape of the legacy dev dataset
// (dev:brilliant-cardinal-773) into the new contract schema, per the
// user-approved migration decisions. Every step guards on already-migrated
// markers so re-running is a no-op.

// ─── helpers ────────────────────────────────────────────────────────────────

const SF_ANCHOR = { lat: 37.7524, lng: -122.418 }; // Mission, SF
const OAK_ANCHOR = { lat: 37.818, lng: -122.269 }; // Temescal, Oakland

function milesBetween(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 3958.8 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatMiles(miles: number): string {
  return `${miles.toFixed(1)} mi`;
}

/** "https://www.instagram.com/itstrackmagic?igsh=…" → "@itstrackmagic" */
export function instagramHandle(url: string): string | undefined {
  const match = url.match(/instagram\.com\/([^/?#]+)/);
  if (!match) return undefined;
  const handle = match[1].trim();
  return handle === "" ? undefined : `@${handle}`;
}

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const PT_OFFSET_MS = 7 * 60 * 60 * 1000; // PDT

/** "APR 3" for a ms timestamp, in Pacific time. */
function pastShowMeta(startsAt: number): string {
  const d = new Date(startsAt - PT_OFFSET_MS);
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`;
}

// ─── step 1: delete test rows ───────────────────────────────────────────────
// "Test Band" + its owner user + its membership + the 2 test events
// ("Test Event", "TEST TEST") + rows referencing them.

async function deleteTestRows(ctx: MutationCtx) {
  const deletedBands = new Set<Id<"bands">>();
  const deletedUsers = new Set<Id<"users">>();
  const deletedEvents = new Set<Id<"events">>();

  const testBand = await ctx.db
    .query("bands")
    .withIndex("by_name", (q) => q.eq("name", "Test Band"))
    .unique();
  if (testBand) {
    deletedBands.add(testBand._id);
    // Its owner user, via legacy memberships (tiny table — full scan is fine;
    // legacy indexes are dropped by the new schema).
    for (const membership of await ctx.db.query("bandMemberships").take(1000)) {
      if (membership.bandId === testBand._id) {
        if (membership.role === "owner" && membership.userId) {
          deletedUsers.add(membership.userId);
        }
        await ctx.db.delete(membership._id);
      }
    }
    await ctx.db.delete(testBand._id);
  }

  for (const event of await ctx.db.query("events").take(1000)) {
    if (event.title === "Test Event" || event.title === "TEST TEST") {
      deletedEvents.add(event._id);
      await ctx.db.delete(event._id);
    }
  }

  for (const userId of deletedUsers) {
    const user = await ctx.db.get(userId);
    if (user) await ctx.db.delete(userId);
  }

  const refersDeleted = (row: {
    bandId?: Id<"bands">;
    userId?: Id<"users">;
    eventId?: Id<"events">;
    invitedBandId?: Id<"bands">;
    hostBandId?: Id<"bands">;
    targetUserId?: Id<"users">;
    invitedBy?: Id<"users">;
  }) =>
    (row.bandId !== undefined && deletedBands.has(row.bandId)) ||
    (row.invitedBandId !== undefined && deletedBands.has(row.invitedBandId)) ||
    (row.hostBandId !== undefined && deletedBands.has(row.hostBandId)) ||
    (row.userId !== undefined && deletedUsers.has(row.userId)) ||
    (row.targetUserId !== undefined && deletedUsers.has(row.targetUserId)) ||
    (row.invitedBy !== undefined && deletedUsers.has(row.invitedBy)) ||
    (row.eventId !== undefined && deletedEvents.has(row.eventId));

  const sweepTables = [
    "savedArtists",
    "rsvps",
    "eventTickets",
    "bandInvites",
    "bandProfileEngagements",
    "eventCohostInvites",
    "bandMediaSlots",
    "notifications",
    "spotifyProfiles",
  ] as const;
  for (const table of sweepTables) {
    for (const row of await ctx.db.query(table).take(1000)) {
      if (refersDeleted(row)) await ctx.db.delete(row._id);
    }
  }
}

// ─── step 2: users reshape (in place) ───────────────────────────────────────

async function doMigrateUsers(ctx: MutationCtx) {
  for (const user of await ctx.db.query("users").take(1000)) {
    await ctx.db.patch(user._id, {
      genres: user.genres ?? user.topGenres ?? [],
      attendedCount: user.attendedCount ?? user.showsAttended ?? 0,
      ...(user.avatarUrl === undefined && user.avatar !== undefined
        ? { avatarUrl: user.avatar }
        : {}),
      // Remove legacy fields. (avatarStorageId is kept per user decision.)
      avatar: undefined,
      location: undefined,
      memberSince: undefined,
      phoneNumber: undefined,
      role: undefined,
      showsAttended: undefined,
      topGenres: undefined,
    });
  }
}

// ─── step 3: bands reshape (in place) ───────────────────────────────────────

async function doMigrateBands(ctx: MutationCtx) {
  for (const band of await ctx.db.query("bands").take(1000)) {
    const links = band.socialLinks;
    const legacySocialLinks =
      band.legacySocialLinks ??
      (links &&
      (links.spotify || links.appleMusic || links.tiktok || links.youtube || links.website)
        ? {
            ...(links.spotify !== undefined ? { spotify: links.spotify } : {}),
            ...(links.appleMusic !== undefined ? { appleMusic: links.appleMusic } : {}),
            ...(links.tiktok !== undefined ? { tiktok: links.tiktok } : {}),
            ...(links.youtube !== undefined ? { youtube: links.youtube } : {}),
            ...(links.website !== undefined ? { website: links.website } : {}),
          }
        : undefined);
    const linkIg =
      band.linkIg ??
      (links?.instagram !== undefined ? instagramHandle(links.instagram) : undefined);

    await ctx.db.patch(band._id, {
      area:
        band.area ??
        (band.location !== undefined
          ? band.location.replace(/,\s*USA\s*$/, "")
          : ""),
      colorHex: band.colorHex ?? bandColorFor(band.name),
      initials: band.initials ?? initialsFor(band.name),
      pastShows: band.pastShows ?? [],
      ...(linkIg !== undefined ? { linkIg } : {}),
      ...(legacySocialLinks !== undefined ? { legacySocialLinks } : {}),
      // Remove legacy fields. (imageStorageId is kept per user decision.)
      createdAt: undefined,
      genre: undefined,
      image: undefined,
      location: undefined,
      memberCount: undefined,
      socialLinks: undefined,
      userId: undefined,
    });
  }
}

// ─── step 4: bandMemberships → bandMembers (owner → admin) ──────────────────

async function migrateMemberships(ctx: MutationCtx) {
  for (const membership of await ctx.db.query("bandMemberships").take(1000)) {
    const { bandId, userId, role } = membership;
    if (!bandId || !userId || !role) continue;
    if ((await ctx.db.get(bandId)) === null) continue; // e.g. deleted Test Band
    if ((await ctx.db.get(userId)) === null) continue;
    const existing = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) => q.eq("bandId", bandId).eq("userId", userId))
      .unique();
    if (!existing) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId,
        role: role === "member" ? "member" : "admin", // owner → admin
      });
    }
  }
}

// ─── step 5: savedArtists → follows, then recompute followerCount ───────────

async function migrateFollows(ctx: MutationCtx) {
  for (const saved of await ctx.db.query("savedArtists").take(1000)) {
    const { bandId, userId } = saved;
    if (!bandId || !userId) continue;
    if ((await ctx.db.get(bandId)) === null) continue;
    if ((await ctx.db.get(userId)) === null) continue;
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_user_band", (q) => q.eq("userId", userId).eq("bandId", bandId))
      .unique();
    if (!existing) {
      await ctx.db.insert("follows", { userId, bandId });
    }
  }
  // Recompute followerCount from follow rows (NOT legacy memberCount) for
  // every band that went through the legacy reshape. Demo bands seeded with
  // curated counts keep them (they have no legacy `location` marker and no
  // follow rows; skip bands that already have a followerCount and no follows).
  for (const band of await ctx.db.query("bands").take(1000)) {
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_band", (q) => q.eq("bandId", band._id))
      .collect();
    if (band.followerCount === undefined || follows.length > 0) {
      await ctx.db.patch(band._id, { followerCount: follows.length });
    }
  }
}

// ─── step 6: venues reshape (in place) ──────────────────────────────────────

async function migrateVenues(ctx: MutationCtx) {
  for (const venue of await ctx.db.query("venues").take(1000)) {
    if (venue.coordinates === undefined && venue.city === undefined) continue; // already migrated / seeded
    const lat = venue.coordinates?.lat ?? venue.lat ?? 0;
    const lng = venue.coordinates?.lng ?? venue.lng ?? 0;
    await ctx.db.patch(venue._id, {
      area: venue.area ?? venue.city ?? "",
      addr: venue.addr ?? venue.address ?? "",
      lat,
      lng,
      distSF: venue.distSF ?? formatMiles(milesBetween(lat, lng, SF_ANCHOR.lat, SF_ANCHOR.lng)),
      distOak: venue.distOak ?? formatMiles(milesBetween(lat, lng, OAK_ANCHOR.lat, OAK_ANCHOR.lng)),
      // Remove legacy fields.
      address: undefined,
      capacity: undefined,
      city: undefined,
      coordinates: undefined,
      description: undefined,
      genres: undefined,
      images: undefined,
    });
  }
}

// ─── step 7: bandMediaSlots → videos (video slots) / band field (images) ────

async function migrateMediaSlots(ctx: MutationCtx) {
  for (const slot of await ctx.db.query("bandMediaSlots").take(1000)) {
    const { bandId, mediaStorageId } = slot;
    if (!bandId || !mediaStorageId) continue;
    const band = await ctx.db.get(bandId);
    if (!band) continue;
    if (slot.mediaType === "video") {
      const siblings = await ctx.db
        .query("videos")
        .withIndex("by_band_order", (q) => q.eq("bandId", bandId))
        .collect();
      if (!siblings.some((video) => video.storageId === mediaStorageId)) {
        const slotIndex = slot.slotIndex ?? 0;
        await ctx.db.insert("videos", {
          bandId,
          title: `${band.name} — clip ${slotIndex + 1}`,
          views: 0,
          lengthSec: 0,
          pinned: false,
          order: slotIndex,
          storageId: mediaStorageId,
        });
      }
    } else if (slot.mediaType === "image") {
      const ids = band.legacyImageSlotIds ?? [];
      if (!ids.includes(mediaStorageId)) {
        await ctx.db.patch(band._id, {
          legacyImageSlotIds: [...ids, mediaStorageId],
        });
      }
    }
  }
}

// ─── step 8: EARPLUG LAUNCH NIGHT → past gig + pastShows entries ────────────

async function migrateLaunchNight(ctx: MutationCtx) {
  const launch = (await ctx.db.query("events").take(1000)).find(
    (event) => event.title === "EARPLUG LAUNCH NIGHT",
  );
  if (!launch || !launch.dateTime || !launch.venueId || !launch.bandId) return;
  if ((await ctx.db.get(launch.venueId)) === null) return;
  if ((await ctx.db.get(launch.bandId)) === null) return;

  const existing = await ctx.db
    .query("gigs")
    .withIndex("by_title", (q) => q.eq("title", "EARPLUG LAUNCH NIGHT"))
    .unique();
  if (!existing) {
    await ctx.db.insert("gigs", {
      title: "EARPLUG LAUNCH NIGHT",
      venueId: launch.venueId,
      price: (launch.price ?? 0) / 100, // legacy stored cents (500 → $5)
      startsAt: launch.dateTime,
      doorsTime: "6:30PM",
      flyKey: "bluetype",
      lineup: [launch.bandId],
      genres: launch.genres ?? [],
      desc: launch.description ?? "",
      ticketing: "rsvp",
      cap: launch.capacity !== undefined ? `${launch.capacity} cap` : "No cap",
      goingCount: launch.rsvpCount ?? 25,
    });
  }

  // pastShows entry for every band that played: the host band plus each band
  // with an accepted co-host invite for the event.
  const playedBandIds = new Set<Id<"bands">>([launch.bandId]);
  for (const invite of await ctx.db.query("eventCohostInvites").take(1000)) {
    if (
      invite.eventId === launch._id &&
      invite.status === "accepted" &&
      invite.invitedBandId
    ) {
      playedBandIds.add(invite.invitedBandId);
    }
  }
  const meta = pastShowMeta(launch.dateTime); // "APR 3"
  for (const bandId of playedBandIds) {
    const band = await ctx.db.get(bandId);
    if (!band) continue;
    const shows = band.pastShows ?? [];
    if (!shows.some((show) => show.title === "EARPLUG LAUNCH NIGHT")) {
      await ctx.db.patch(bandId, {
        pastShows: [...shows, { title: "EARPLUG LAUNCH NIGHT", meta }],
      });
    }
  }
}

// ─── step 9: backfill band slugs ────────────────────────────────────────────
// Slugs arrived with the cassette create flow, so every band predating it —
// legacy rows and seeded demo bands alike — has none, and bands:bySlug can't
// resolve any of them. Issue one per slugless band. Bands come back in
// creation order, so the oldest claimant of a name keeps the unsuffixed slug
// and later ones take -2, -3, … Already-slugged bands are skipped, which is
// what makes this re-runnable.

async function backfillBandSlugs(ctx: MutationCtx): Promise<number> {
  let issued = 0;
  for (const band of await ctx.db.query("bands").take(1000)) {
    if (band.slug !== undefined) continue;
    await ctx.db.patch(band._id, { slug: await uniqueSlug(ctx, band.name) });
    issued++;
  }
  return issued;
}

// ─── registered functions ───────────────────────────────────────────────────

export const migrateUsers = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    await doMigrateUsers(ctx);
    return null;
  },
});

export const migrateBands = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    await doMigrateBands(ctx);
    return null;
  },
});

/** Standalone: the one step a deployment that already ran migrateAll still
 * needs. Safe to re-run — it only touches bands with no slug. */
export const backfillSlugs = internalMutation({
  args: {},
  returns: v.object({ slugsIssued: v.number() }),
  handler: async (ctx) => {
    return { slugsIssued: await backfillBandSlugs(ctx) };
  },
});

export const migrateAll = internalMutation({
  args: {},
  returns: v.object({
    users: v.number(),
    bands: v.number(),
    bandMembers: v.number(),
    follows: v.number(),
    venues: v.number(),
    videos: v.number(),
    gigs: v.number(),
    bandsWithSlug: v.number(),
  }),
  handler: async (ctx) => {
    await deleteTestRows(ctx);
    await doMigrateUsers(ctx);
    await doMigrateBands(ctx);
    await migrateMemberships(ctx);
    await migrateFollows(ctx);
    await migrateVenues(ctx);
    await migrateMediaSlots(ctx);
    await migrateLaunchNight(ctx);
    await backfillBandSlugs(ctx);

    const bands = await ctx.db.query("bands").take(1000);
    return {
      // A state count, not a work count, like every other key here — so a
      // re-run of this idempotent migration reports the same numbers.
      bandsWithSlug: bands.filter((band) => band.slug !== undefined).length,
      users: (await ctx.db.query("users").take(1000)).length,
      bands: bands.length,
      bandMembers: (await ctx.db.query("bandMembers").take(1000)).length,
      follows: (await ctx.db.query("follows").take(1000)).length,
      venues: (await ctx.db.query("venues").take(1000)).length,
      videos: (await ctx.db.query("videos").take(1000)).length,
      gigs: (await ctx.db.query("gigs").take(1000)).length,
    };
  },
});
