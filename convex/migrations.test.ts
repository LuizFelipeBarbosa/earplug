import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import type { FunctionReference, RegisteredMutation } from "convex/server";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { bandColorFor } from "./lib/helpers";
import type * as migrationFunctions from "./migrations";
import { doorsTime, instagramHandle, pastShowMeta } from "./migrations";
import schema from "./schema";

const PDT_EVENING = Date.UTC(2020, 4, 8, 2, 0); // May 7, 7PM PDT.

type MutationReferenceFromExport<Export> =
  Export extends RegisteredMutation<infer Visibility, infer Args, infer Returns>
    ? FunctionReference<"mutation", Visibility, Args, Awaited<Returns>>
    : never;

function internalMigrationReference<Export>(
  name: string,
): MutationReferenceFromExport<Export> {
  // makeFunctionReference constructs the same runtime object for public and
  // internal functions; visibility exists only in its static return type.
  return makeFunctionReference(
    name,
  ) as unknown as MutationReferenceFromExport<Export>;
}

// This one-shot file is intentionally absent from the checked-in generated
// API until the widened schema is deployed. Keep the test references typed
// directly from the registered exports without regenerating out-of-scope code.
const migrationApi = {
  migrateAll: internalMigrationReference<typeof migrationFunctions.migrateAll>(
    "migrations:migrateAll",
  ),
  migrateEvents: internalMigrationReference<
    typeof migrationFunctions.migrateEvents
  >("migrations:migrateEvents"),
  migrateRsvps: internalMigrationReference<
    typeof migrationFunctions.migrateRsvps
  >("migrations:migrateRsvps"),
  migrateLikes: internalMigrationReference<
    typeof migrationFunctions.migrateLikes
  >("migrations:migrateLikes"),
  migrateMediaSlots: internalMigrationReference<
    typeof migrationFunctions.migrateMediaSlots
  >("migrations:migrateMediaSlots"),
  backfillGoingCounts: internalMigrationReference<
    typeof migrationFunctions.backfillGoingCounts
  >("migrations:backfillGoingCounts"),
  purgeLegacy: internalMigrationReference<
    typeof migrationFunctions.purgeLegacy
  >("migrations:purgeLegacy"),
};

/** Fixture rows mimicking the widened production legacy shapes. */
async function seedLegacyFixture() {
  const t = convexTest(schema);
  const fixture = await t.run(async (ctx) => {
    // The widened schema requires a string, so a legacy user with no usable
    // email is represented by the production sentinel: the empty string.
    const owner = await ctx.db.insert("users", {
      clerkId: "legacy_owner",
      name: "Legacy Owner",
      email: "",
      avatar: "https://images.example/owner",
      location: "Berkeley",
      memberSince: 1,
      phoneNumber: "555-0100",
      role: "fan",
      showsAttended: 3,
      topGenres: ["punk", "noise"],
    });
    const fan = await ctx.db.insert("users", {
      clerkId: "legacy_fan",
      name: "Legacy Fan",
      email: "fan@example.com",
      showsAttended: 1,
    });

    const storageIds = await Promise.all(
      Array.from({ length: 12 }, (_, index) =>
        ctx.storage.store(
          new Blob([new Uint8Array([index + 1])], {
            type: index % 2 === 0 ? "video/quicktime" : "image/jpeg",
          }),
        ),
      ),
    );

    const mixedBand = await ctx.db.insert("bands", {
      name: "Ancient Quaffle",
      genres: ["punk", "noise"],
      location: "Berkeley, CA, USA",
      memberCount: 99,
      createdAt: 1,
      image: "https://images.example/ancient-quaffle",
      imageStorageId: storageIds[4],
      userId: owner,
      socialLinks: {
        instagram: "https://instagram.com/@ancientquaffle",
        spotify: "https://open.spotify.com/artist/ancient",
        youtube: "https://youtube.com/@ancientquaffle",
      },
    });
    const photosBand = await ctx.db.insert("bands", {
      name: "Only Photos",
      genres: ["ambient"],
      location: "Oakland, CA, USA",
    });
    const videosBand = await ctx.db.insert("bands", {
      name: "Only Videos",
      genres: ["metal"],
      location: "San Francisco, CA, USA",
    });
    const heroOnlyBand = await ctx.db.insert("bands", {
      name: "Hero Only",
      genres: ["folk"],
      location: "Richmond, CA, USA",
      imageStorageId: storageIds[9],
    });

    await ctx.db.insert("bandMemberships", {
      bandId: mixedBand,
      userId: owner,
      role: "owner",
      joinedAt: 1,
    });
    await ctx.db.insert("savedArtists", {
      bandId: mixedBand,
      userId: fan,
      createdAt: 2,
    });

    const venue = await ctx.db.insert("venues", {
      name: "Legacy Hall",
      address: "123 Telegraph Ave",
      capacity: 200,
      city: "Berkeley",
      coordinates: { lat: 37.8715, lng: -122.273 },
    });

    const twinA = await ctx.db.insert("events", {
      title: "Twin Bill",
      bandId: mixedBand,
      venueId: venue,
      dateTime: PDT_EVENING,
      price: 700,
      capacity: 200,
      genres: ["punk"],
      description: "First twin",
      imageStorageId: storageIds[10],
      rsvpCount: 99,
    });
    const twinB = await ctx.db.insert("events", {
      title: "Twin Bill",
      bandId: photosBand,
      venueId: venue,
      dateTime: PDT_EVENING,
      rsvpCount: 42,
    });
    const event1000 = await ctx.db.insert("events", {
      title: "Ten Dollar Show",
      bandId: mixedBand,
      venueId: venue,
      dateTime: PDT_EVENING + 60 * 60 * 1000,
      price: 1000,
      capacity: 0,
    });
    const event1500 = await ctx.db.insert("events", {
      title: "Fifteen Dollar Show",
      bandId: mixedBand,
      venueId: venue,
      dateTime: PDT_EVENING + 2 * 60 * 60 * 1000,
      price: 1500,
    });
    const event500 = await ctx.db.insert("events", {
      title: "Five Dollar Show",
      bandId: mixedBand,
      venueId: venue,
      dateTime: PDT_EVENING + 3 * 60 * 60 * 1000,
      price: 500,
    });

    await ctx.db.insert("rsvps", {
      eventId: twinA,
      userId: owner,
      createdAt: 1,
    });
    const twinBRsvp = await ctx.db.insert("rsvps", {
      eventId: twinB,
      userId: fan,
      createdAt: 2,
    });
    await ctx.db.insert("likes", {
      eventId: twinA,
      userId: fan,
      createdAt: 3,
    });
    await ctx.db.insert("likes", {
      eventId: twinB,
      userId: owner,
      createdAt: 4,
    });

    await ctx.db.insert("bandMediaSlots", {
      bandId: mixedBand,
      mediaStorageId: storageIds[0],
      mediaType: "video",
      slotIndex: 0,
      mimeType: "video/quicktime",
      fileSizeBytes: 101,
      durationSeconds: 12,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: mixedBand,
      mediaStorageId: storageIds[1],
      mediaType: "image",
      slotIndex: 1,
      mimeType: "image/jpeg",
      fileSizeBytes: 102,
      caption: "Cover shot",
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: mixedBand,
      mediaStorageId: storageIds[2],
      mediaType: "video",
      slotIndex: 2,
      mimeType: "video/quicktime",
      fileSizeBytes: 103,
      durationSeconds: 34,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: mixedBand,
      mediaStorageId: storageIds[3],
      mediaType: "image",
      slotIndex: 3,
      mimeType: "image/jpeg",
      fileSizeBytes: 104,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: photosBand,
      mediaStorageId: storageIds[5],
      mediaType: "image",
      slotIndex: 0,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: videosBand,
      mediaStorageId: storageIds[6],
      mediaType: "video",
      slotIndex: 0,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: videosBand,
      mediaStorageId: storageIds[7],
      mediaType: "video",
      slotIndex: 1,
    });

    // Dead tables are purged unconditionally after every guarded source row
    // has a counterpart.
    await ctx.db.insert("eventTickets", {
      eventId: twinB,
      rsvpId: twinBRsvp,
      userId: fan,
      status: "active",
    });
    await ctx.db.insert("bandInvites", { bandId: mixedBand });
    await ctx.db.insert("bandProfileEngagements", {
      bandId: mixedBand,
      userId: fan,
    });
    await ctx.db.insert("eventCohostInvites", { eventId: twinA });
    await ctx.db.insert("notifications", {
      eventId: twinA,
      userId: owner,
    });

    return {
      owner,
      fan,
      mixedBand,
      photosBand,
      videosBand,
      heroOnlyBand,
      venue,
      twinA,
      twinB,
      event1000,
      event1500,
      event500,
      storageIds,
    };
  });
  return { t, ...fixture };
}

function expectNoWork(result: Record<string, unknown>) {
  for (const counters of Object.values(result)) {
    expect(counters).toEqual({
      migrated: 0,
      skipped: 0,
      alreadyDone: 0,
    });
  }
}

describe("migration formatting helpers", () => {
  test("normalizes every production Instagram URL shape", () => {
    expect(instagramHandle("https://instagram.com/@ancientquaffle")).toBe(
      "@ancientquaffle",
    );
    expect(
      instagramHandle("https://www.instagram.com/trackmagic?igsh=abc"),
    ).toBe("@trackmagic");
    expect(
      instagramHandle(
        "https://instagram.com/encoded?igsh=YWJjZA%3D%3D&utm_source=qr",
      ),
    ).toBe("@encoded");
    expect(instagramHandle("https://instagram.com/trailing/")).toBe(
      "@trailing",
    );
    expect(instagramHandle("https://instagram.com/locale/?hl=en")).toBe(
      "@locale",
    );
    expect(
      instagramHandle("https://example.com/not-instagram"),
    ).toBeUndefined();
    expect(instagramHandle("https://instagram.com/?hl=en")).toBeUndefined();
  });

  test("formats an evening PDT timestamp on its Pacific date", () => {
    expect(doorsTime(PDT_EVENING)).toBe("7PM");
    expect(doorsTime(PDT_EVENING - 30 * 60 * 1000)).toBe("6:30PM");
    expect(pastShowMeta(PDT_EVENING)).toBe("MAY 7");
  });
});

describe("migrations:migrateEvents and dependent standalone steps", () => {
  test("converts prices and caps and resolves identical events by legacy id", async () => {
    const {
      t,
      owner,
      fan,
      twinA,
      twinB,
      event1000,
      event1500,
      event500,
      storageIds,
    } = await seedLegacyFixture();

    expect(
      await t.mutation(migrationApi.migrateEvents, {
        dryRun: false,
      }),
    ).toMatchObject({ migrated: 5 });
    await t.mutation(migrationApi.migrateRsvps, { dryRun: false });
    await t.mutation(migrationApi.migrateLikes, { dryRun: false });
    await t.mutation(migrationApi.backfillGoingCounts, {
      dryRun: false,
    });

    await t.run(async (ctx) => {
      const gigs = await ctx.db.query("gigs").take(1000);
      const byLegacyId = new Map(gigs.map((gig) => [gig.legacyEventId, gig]));
      const twinAGig = byLegacyId.get(twinA)!;
      const twinBGig = byLegacyId.get(twinB)!;

      expect(twinAGig._id).not.toBe(twinBGig._id);
      expect(twinAGig.title).toBe(twinBGig.title);
      expect(twinAGig.startsAt).toBe(twinBGig.startsAt);
      expect(twinAGig.price).toBe(7);
      expect(twinAGig.cap).toBe("200");
      expect(twinAGig.doorsTime).toBe("7PM");
      expect(twinAGig.flyKey).toBe("custom");
      expect(twinAGig.flyStorageId).toBe(storageIds[10]);
      expect(twinBGig.price).toBe(0);
      expect(twinBGig.cap).toBe("No cap");
      expect(twinBGig.flyKey).toBe("paper");
      expect(twinBGig.flyStorageId).toBeUndefined();
      expect(byLegacyId.get(event1000)?.price).toBe(10);
      expect(byLegacyId.get(event1000)?.cap).toBe("0");
      expect(byLegacyId.get(event1500)?.price).toBe(15);
      expect(byLegacyId.get(event500)?.price).toBe(5);

      const rsvps = await ctx.db.query("gigRsvps").take(1000);
      expect(
        rsvps.some(
          (rsvp) => rsvp.userId === owner && rsvp.gigId === twinAGig._id,
        ),
      ).toBe(true);
      expect(
        rsvps.some(
          (rsvp) => rsvp.userId === fan && rsvp.gigId === twinBGig._id,
        ),
      ).toBe(true);
      expect(twinAGig.goingCount).toBe(1);
      expect(twinBGig.goingCount).toBe(1);

      const saves = await ctx.db.query("gigSaves").take(1000);
      expect(
        saves.some(
          (save) => save.userId === fan && save.gigId === twinAGig._id,
        ),
      ).toBe(true);
      expect(
        saves.some(
          (save) => save.userId === owner && save.gigId === twinBGig._id,
        ),
      ).toBe(true);
    });
  });
});

describe("migrations:migrateAll", () => {
  test("reshapes the full fixture and a second live run is all-zero", async () => {
    const {
      t,
      owner,
      mixedBand,
      photosBand,
      videosBand,
      heroOnlyBand,
      venue,
      twinA,
      twinB,
      storageIds,
    } = await seedLegacyFixture();

    const first = await t.mutation(migrationApi.migrateAll, {
      dryRun: false,
    });
    expect(first.users.migrated).toBe(2);
    const second = await t.mutation(migrationApi.migrateAll, {
      dryRun: false,
    });
    expectNoWork(second);

    const ownerDoc = await t.run(async (ctx) => ctx.db.get(owner));
    expect(ownerDoc?.email).toBe("");
    expect(ownerDoc?.genres).toEqual(["punk", "noise"]);
    expect(ownerDoc?.attendedCount).toBe(3);
    expect(ownerDoc?.avatarUrl).toBe("https://images.example/owner");
    expect(ownerDoc).not.toHaveProperty("avatar");
    expect(ownerDoc).not.toHaveProperty("location");
    expect(ownerDoc).not.toHaveProperty("memberSince");
    expect(ownerDoc).not.toHaveProperty("phoneNumber");
    expect(ownerDoc).not.toHaveProperty("role");
    expect(ownerDoc).not.toHaveProperty("showsAttended");
    expect(ownerDoc).not.toHaveProperty("topGenres");

    const bandDoc = await t.run(async (ctx) => ctx.db.get(mixedBand));
    expect(bandDoc?.area).toBe("Berkeley");
    expect(bandDoc?.colorHex).toBe(bandColorFor("Ancient Quaffle"));
    expect(bandDoc?.initials).toBe("AQ");
    expect(bandDoc?.followerCount).toBe(2);
    expect(bandDoc?.slug).toBe("ancient-quaffle");
    expect(bandDoc?.bio).toBe("");
    expect(bandDoc?.linkIg).toBe("@ancientquaffle");
    expect(bandDoc?.linkYt).toBe("https://youtube.com/@ancientquaffle");
    expect(bandDoc?.legacySocialLinks).toEqual({
      spotify: "https://open.spotify.com/artist/ancient",
    });
    expect(bandDoc?.linkBc).toBeUndefined();
    expect(bandDoc).not.toHaveProperty("socialLinks");
    expect(bandDoc).not.toHaveProperty("location");
    expect(
      bandDoc?.pastShows?.some(
        (show) => show.title === "Twin Bill" && show.meta === "MAY 7",
      ),
    ).toBe(true);

    const venueDoc = await t.run(async (ctx) => ctx.db.get(venue));
    expect(venueDoc).toMatchObject({
      name: "Legacy Hall",
      area: "Berkeley",
      addr: "123 Telegraph Ave",
      lat: 37.8715,
      lng: -122.273,
    });
    expect(venueDoc?.distSF).toMatch(/^\d+\.\d mi$/);
    expect(venueDoc?.distOak).toMatch(/^\d+\.\d mi$/);
    expect(venueDoc).not.toHaveProperty("address");
    expect(venueDoc).not.toHaveProperty("capacity");
    expect(venueDoc).not.toHaveProperty("city");
    expect(venueDoc).not.toHaveProperty("coordinates");

    await t.run(async (ctx) => {
      const members = await ctx.db.query("bandMembers").take(1000);
      expect(members).toHaveLength(1);
      expect(members[0]).toMatchObject({
        bandId: mixedBand,
        userId: owner,
        role: "admin",
      });

      const gigs = await ctx.db.query("gigs").take(1000);
      const twinAGig = gigs.find((gig) => gig.legacyEventId === twinA)!;
      const twinBGig = gigs.find((gig) => gig.legacyEventId === twinB)!;
      expect(twinAGig.goingCount).toBe(1);
      expect(twinBGig.goingCount).toBe(1);
      expect(twinAGig.goingCount).not.toBe(99);
      expect(twinBGig.goingCount).not.toBe(42);

      const mixedMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", mixedBand))
        .take(1000);
      expect(mixedMedia.map((row) => row.order)).toEqual([0, 1, 2, 3, 4]);
      expect(mixedMedia.map((row) => row.title)).toEqual([
        "Clip 1",
        "Cover shot",
        "Clip 2",
        "Photo 2",
        "Profile photo",
      ]);
      expect(
        mixedMedia.filter((row) => row.kind === "video" && row.pinned),
      ).toHaveLength(1);
      expect(mixedMedia[0]).toMatchObject({
        kind: "video",
        pinned: true,
        views: 0,
        lengthSec: 12,
        contentType: "video/quicktime",
        sizeBytes: 101,
      });
      expect(mixedMedia[1]).toMatchObject({
        kind: "photo",
        caption: "Cover shot",
        pinned: false,
      });
      expect(mixedMedia[2]).toMatchObject({
        kind: "video",
        pinned: false,
        views: 0,
        lengthSec: 34,
      });
      expect(mixedMedia[3].views).toBeUndefined();
      expect(mixedMedia[4]).toMatchObject({
        kind: "photo",
        storageId: storageIds[4],
        order: 4,
        pinned: false,
      });

      const photoMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", photosBand))
        .take(1000);
      expect(photoMedia).toHaveLength(1);
      expect(photoMedia[0]).toMatchObject({
        kind: "photo",
        title: "Photo 1",
        pinned: false,
      });

      const videoMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", videosBand))
        .take(1000);
      expect(videoMedia).toHaveLength(2);
      expect(videoMedia.filter((row) => row.pinned)).toHaveLength(1);
      expect(videoMedia[0].pinned).toBe(true);

      const heroOnlyMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", heroOnlyBand))
        .take(1000);
      expect(heroOnlyMedia).toHaveLength(1);
      expect(heroOnlyMedia[0]).toMatchObject({
        title: "Profile photo",
        order: 0,
        storageId: storageIds[9],
      });
    });

    const mediaPayload = await t.query(api.media.forBand, {
      bandId: mixedBand,
    });
    expect(
      mediaPayload.find((row) => row.title === "Profile photo")?.isHero,
    ).toBe(true);
  });

  test("default and explicit dry runs make no writes", async () => {
    for (const args of [{}, { dryRun: true }]) {
      const { t, owner, mixedBand, venue } = await seedLegacyFixture();
      const before = await t.run(async (ctx) => ({
        user: await ctx.db.get(owner),
        band: await ctx.db.get(mixedBand),
        venue: await ctx.db.get(venue),
        events: await ctx.db.query("events").take(1000),
        slots: await ctx.db.query("bandMediaSlots").take(1000),
      }));

      await t.mutation(migrationApi.migrateAll, args);

      const after = await t.run(async (ctx) => ({
        user: await ctx.db.get(owner),
        band: await ctx.db.get(mixedBand),
        venue: await ctx.db.get(venue),
        events: await ctx.db.query("events").take(1000),
        slots: await ctx.db.query("bandMediaSlots").take(1000),
        gigs: await ctx.db.query("gigs").take(1000),
        members: await ctx.db.query("bandMembers").take(1000),
        follows: await ctx.db.query("follows").take(1000),
        rsvps: await ctx.db.query("gigRsvps").take(1000),
        saves: await ctx.db.query("gigSaves").take(1000),
        media: await ctx.db.query("bandMedia").take(1000),
      }));

      expect(after.user).toEqual(before.user);
      expect(after.band).toEqual(before.band);
      expect(after.venue).toEqual(before.venue);
      expect(after.events).toEqual(before.events);
      expect(after.slots).toEqual(before.slots);
      expect(after.gigs).toEqual([]);
      expect(after.members).toEqual([]);
      expect(after.follows).toEqual([]);
      expect(after.rsvps).toEqual([]);
      expect(after.saves).toEqual([]);
      expect(after.media).toEqual([]);
    }
  });
});

describe("migrations:migrateMediaSlots", () => {
  test("rejects a gap in one band's global photo/video order", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", {
        name: "Gapped Band",
        genres: ["punk"],
      });
      const first = await ctx.storage.store(new Blob(["first"]));
      const third = await ctx.storage.store(new Blob(["third"]));
      await ctx.db.insert("bandMediaSlots", {
        bandId,
        mediaStorageId: first,
        mediaType: "video",
        slotIndex: 0,
      });
      await ctx.db.insert("bandMediaSlots", {
        bandId,
        mediaStorageId: third,
        mediaType: "image",
        slotIndex: 2,
      });
    });

    await expect(
      t.mutation(migrationApi.migrateMediaSlots, {
        dryRun: false,
      }),
    ).rejects.toThrow("slotIndex values must be dense");
    expect(
      await t.run(async (ctx) => ctx.db.query("bandMedia").take(1000)),
    ).toEqual([]);
  });

  test("appends a missing hero when slot media was already migrated", async () => {
    const t = convexTest(schema);
    const bandId = await t.run(async (ctx) => {
      const slotStorage = await ctx.storage.store(new Blob(["slot"]));
      const heroStorage = await ctx.storage.store(new Blob(["hero"]));
      const bandId = await ctx.db.insert("bands", {
        name: "Partial Media Band",
        genres: ["punk"],
        imageStorageId: heroStorage,
      });
      await ctx.db.insert("bandMediaSlots", {
        bandId,
        mediaStorageId: slotStorage,
        mediaType: "image",
        slotIndex: 0,
      });
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: slotStorage,
        title: "Photo 1",
        order: 0,
        pinned: false,
      });
      return bandId;
    });

    await t.mutation(migrationApi.migrateMediaSlots, {
      dryRun: false,
    });
    const media = await t.run(async (ctx) =>
      ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", bandId))
        .take(1000),
    );
    expect(media).toHaveLength(2);
    expect(media[1]).toMatchObject({
      title: "Profile photo",
      order: 1,
    });
  });
});

describe("migrations:purgeLegacy", () => {
  test("refuses an unmigrated event and purges only after migration", async () => {
    const unmigrated = await seedLegacyFixture();
    await expect(
      unmigrated.t.mutation(migrationApi.purgeLegacy, {
        dryRun: false,
      }),
    ).rejects.toThrow("no gig has legacyEventId");

    const { t } = await seedLegacyFixture();
    await t.mutation(migrationApi.migrateAll, { dryRun: false });

    const dry = await t.mutation(migrationApi.purgeLegacy, {});
    expect(dry.deleted).toBeGreaterThan(0);
    expect(dry.legacyEventIdsCleared).toBe(5);
    expect(
      await t.run(async (ctx) => ctx.db.query("events").take(1000)),
    ).toHaveLength(5);

    const live = await t.mutation(migrationApi.purgeLegacy, {
      dryRun: false,
    });
    expect(live).toEqual(dry);

    await t.run(async (ctx) => {
      for (const table of [
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
      ] as const) {
        expect(await ctx.db.query(table).take(1000)).toEqual([]);
      }
      const gigs = await ctx.db.query("gigs").take(1000);
      expect(gigs).toHaveLength(5);
      expect(gigs.every((gig) => gig.legacyEventId === undefined)).toBe(true);
    });
  });
});
