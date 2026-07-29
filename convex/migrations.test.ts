import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import { bandColorFor } from "./lib/helpers";
import schema from "./schema";

const LAUNCH_DATE = 1775266200000; // 2026-04-03 6:30PM PT

/** Fixture rows mimicking the legacy dev-deployment shapes. */
async function seedLegacyFixture() {
  const t = convexTest(schema);
  const fixture = await t.run(async (ctx) => {
    const owner = await ctx.db.insert("users", {
      clerkId: "user_owner",
      name: "Luiz B.",
      email: "",
      avatar: "https://img.clerk.com/owner",
      memberSince: 1774900000000,
      role: "fan",
      showsAttended: 0,
      topGenres: ["indie", "rock"],
    });
    const fan = await ctx.db.insert("users", {
      clerkId: "user_fan",
      name: "Anandi J.",
      email: "anandi@example.com",
      avatar: "https://img.clerk.com/fan",
      memberSince: 1774900000001,
      role: "fan",
      showsAttended: 0,
    });
    const testOwner = await ctx.db.insert("users", {
      clerkId: "user_testowner",
      name: "Test Owner",
      email: "",
      memberSince: 1775300000000,
      role: "fan",
      showsAttended: 0,
    });

    const storageA = await ctx.storage.store(new Blob(["video-bytes"]));
    const storageB = await ctx.storage.store(new Blob(["image-bytes"]));

    const trackmagic = await ctx.db.insert("bands", {
      name: "TRACKMAGIC",
      genres: ["indie", "rock"],
      location: "Berkeley, CA, USA",
      memberCount: 6,
      createdAt: 1774931516652,
      userId: owner,
      socialLinks: {
        instagram: "https://www.instagram.com/itstrackmagic?igsh=NTc4MTIwNjQ2YQ==",
        spotify: "https://open.spotify.com/artist/xyz",
        website: "https://trackmagic.example.com",
      },
      image: "https://x.convex.cloud/api/storage/abc",
    });
    const earplug = await ctx.db.insert("bands", {
      name: "EARPLUG",
      genres: ["indie", "jazz"],
      bio: "Connecting Local Musicians",
      location: "Berkeley, CA, USA",
      memberCount: 5,
      createdAt: 1774914366042,
      userId: owner,
    });
    const testBand = await ctx.db.insert("bands", {
      name: "Test Band",
      genres: ["indie", "folk"],
      location: "Berkeley, CA",
      memberCount: 4,
      createdAt: 1775326597172,
      userId: testOwner,
    });

    await ctx.db.insert("bandMemberships", {
      bandId: earplug, userId: owner, role: "owner", joinedAt: 1774914366042,
    });
    await ctx.db.insert("bandMemberships", {
      bandId: earplug, userId: fan, role: "member", joinedAt: 1774922473400, invitedBy: owner,
    });
    await ctx.db.insert("bandMemberships", {
      bandId: trackmagic, userId: owner, role: "owner", joinedAt: 1774931516652,
    });
    await ctx.db.insert("bandMemberships", {
      bandId: testBand, userId: testOwner, role: "owner", joinedAt: 1775326597172,
    });

    // savedArtists: 2 real follows on TRACKMAGIC, 1 self-follow on Test Band.
    await ctx.db.insert("savedArtists", { bandId: trackmagic, userId: fan, createdAt: 1 });
    await ctx.db.insert("savedArtists", { bandId: trackmagic, userId: owner, createdAt: 2 });
    await ctx.db.insert("savedArtists", { bandId: testBand, userId: testOwner, createdAt: 3 });

    const venue = await ctx.db.insert("venues", {
      name: "Theta Chi Fraternity",
      address: "2499 Piedmont Ave, Berkeley, CA 94704, USA",
      capacity: 100,
      city: "Berkeley",
      coordinates: { lat: 37.866168, lng: -122.251098 },
    });
    const testVenue = await ctx.db.insert("venues", {
      name: "2521 Regent St",
      address: "2521 Regent St, Berkeley, CA 94704",
      capacity: 323,
      city: "Berkeley",
      coordinates: { lat: 37.8644308, lng: -122.2573684 },
    });

    const launchEvent = await ctx.db.insert("events", {
      title: "EARPLUG LAUNCH NIGHT",
      bandId: earplug,
      venueId: venue,
      dateTime: LAUNCH_DATE,
      capacity: 250,
      price: 500,
      rsvpCount: 25,
      status: "confirmed",
      genres: ["indie", "rock", "alternative"],
      description: "COME SHOW OUT FOR EARPLUG LAUNCH NIGHT!!",
      addressVisibility: "public",
    });
    const testEvent = await ctx.db.insert("events", {
      title: "Test Event",
      bandId: testBand,
      venueId: testVenue,
      dateTime: 1775520000000,
      rsvpCount: 1,
      status: "confirmed",
    });

    // TRACKMAGIC accepted a co-host invite for launch night.
    await ctx.db.insert("eventCohostInvites", {
      eventId: launchEvent,
      hostBandId: earplug,
      invitedBandId: trackmagic,
      invitedByBandId: earplug,
      invitedByUserId: owner,
      status: "accepted",
      createdAt: 1,
      expiresAt: 2,
    });

    await ctx.db.insert("rsvps", { eventId: testEvent, userId: testOwner, createdAt: 1 });
    await ctx.db.insert("eventTickets", {
      eventId: testEvent, userId: testOwner, status: "active", token: "tok", issuedAt: 1,
      rsvpId: undefined,
    });

    await ctx.db.insert("bandMediaSlots", {
      bandId: trackmagic, mediaStorageId: storageA, mediaType: "video",
      slotIndex: 1, mimeType: "video/quicktime", fileSizeBytes: 100,
      durationSeconds: 26, createdAt: 1, updatedAt: 1,
    });
    await ctx.db.insert("bandMediaSlots", {
      bandId: trackmagic, mediaStorageId: storageB, mediaType: "image",
      slotIndex: 2, mimeType: "image/jpeg", fileSizeBytes: 100,
      createdAt: 1, updatedAt: 1,
    });

    return { owner, fan, testOwner, trackmagic, earplug, testBand, venue, storageA, storageB };
  });
  return { t, ...fixture };
}

describe("migrations:migrateAll", () => {
  test("full reshape, test-row deletion, and idempotent re-run", async () => {
    const { t, owner, fan, testOwner, trackmagic, earplug, testBand, venue, storageA, storageB } =
      await seedLegacyFixture();

    const first = await t.mutation(internal.migrations.migrateAll, {});
    // Re-run must be a no-op.
    const second = await t.mutation(internal.migrations.migrateAll, {});
    expect(second).toEqual(first);

    await t.run(async (ctx) => {
      // Test rows deleted: band, its owner user, membership, events, referencing rows.
      expect(await ctx.db.get(testBand)).toBeNull();
      expect(await ctx.db.get(testOwner)).toBeNull();
      const events = await ctx.db.query("events").take(10);
      expect(events.length).toBe(1);
      expect(events[0].title).toBe("EARPLUG LAUNCH NIGHT");
      expect((await ctx.db.query("rsvps").take(10)).length).toBe(0);
      expect((await ctx.db.query("eventTickets").take(10)).length).toBe(0);
      expect((await ctx.db.query("savedArtists").take(10)).length).toBe(2);

      // Users reshaped: topGenres → genres, showsAttended → attendedCount,
      // avatar → avatarUrl, legacy fields removed.
      const ownerDoc = (await ctx.db.get(owner))!;
      expect(ownerDoc.genres).toEqual(["indie", "rock"]);
      expect(ownerDoc.attendedCount).toBe(0);
      expect(ownerDoc.avatarUrl).toBe("https://img.clerk.com/owner");
      expect("avatar" in ownerDoc).toBe(false);
      expect("role" in ownerDoc).toBe(false);
      expect("memberSince" in ownerDoc).toBe(false);
      expect("topGenres" in ownerDoc).toBe(false);
      const fanDoc = (await ctx.db.get(fan))!;
      expect(fanDoc.genres).toEqual([]); // no topGenres → []

      // Bands reshaped.
      const tm = (await ctx.db.get(trackmagic))!;
      expect(tm.area).toBe("Berkeley, CA"); // ", USA" stripped
      expect(tm.colorHex).toBe(bandColorFor("TRACKMAGIC"));
      expect(tm.initials).toBe("TR"); // single word → first two letters
      expect(tm.linkIg).toBe("@itstrackmagic"); // instagram → @handle
      expect(tm.legacySocialLinks).toEqual({
        spotify: "https://open.spotify.com/artist/xyz",
        website: "https://trackmagic.example.com",
      });
      expect(tm.followerCount).toBe(2); // recomputed from follows, NOT memberCount
      expect("location" in tm).toBe(false);
      expect("memberCount" in tm).toBe(false);
      expect("socialLinks" in tm).toBe(false);
      expect("userId" in tm).toBe(false);
      const ep = (await ctx.db.get(earplug))!;
      expect(ep.initials).toBe("EA");
      expect(ep.followerCount).toBe(0);

      // Memberships → bandMembers, owner → admin.
      const members = await ctx.db.query("bandMembers").take(10);
      expect(members.length).toBe(3); // test band membership not copied
      const ownerMembership = members.find(
        (m) => m.bandId === earplug && m.userId === owner,
      );
      expect(ownerMembership!.role).toBe("admin");
      const fanMembership = members.find(
        (m) => m.bandId === earplug && m.userId === fan,
      );
      expect(fanMembership!.role).toBe("member");

      // Follows copied (test-band row excluded).
      const follows = await ctx.db.query("follows").take(10);
      expect(follows.length).toBe(2);
      expect(follows.every((f) => f.bandId === trackmagic)).toBe(true);

      // Venue reshaped with computed distances.
      const venueDoc = (await ctx.db.get(venue))!;
      expect(venueDoc.area).toBe("Berkeley");
      expect(venueDoc.addr).toBe("2499 Piedmont Ave, Berkeley, CA 94704, USA");
      expect(venueDoc.lat).toBeCloseTo(37.866168);
      expect(venueDoc.distSF).toMatch(/^\d+\.\d mi$/);
      expect(venueDoc.distOak).toMatch(/^\d+\.\d mi$/);
      expect("coordinates" in venueDoc).toBe(false);
      expect("city" in venueDoc).toBe(false);

      // Media slots: video → videos row; image → legacyImageSlotIds.
      const videos = await ctx.db.query("videos").take(10);
      expect(videos.length).toBe(1);
      expect(videos[0].bandId).toBe(trackmagic);
      expect(videos[0].title).toBe("TRACKMAGIC — clip 2");
      expect(videos[0].views).toBe(0);
      expect(videos[0].lengthSec).toBe(0);
      expect(videos[0].pinned).toBe(false);
      expect(videos[0].order).toBe(1);
      expect(videos[0].storageId).toBe(storageA);
      expect(tm.legacyImageSlotIds).toEqual([storageB]);

      // LAUNCH NIGHT ported as a past gig + pastShows on every band that played.
      const gigs = await ctx.db.query("gigs").take(10);
      expect(gigs.length).toBe(1);
      const launch = gigs[0];
      expect(launch.title).toBe("EARPLUG LAUNCH NIGHT");
      expect(launch.startsAt).toBe(LAUNCH_DATE);
      expect(launch.goingCount).toBe(25);
      expect(launch.lineup).toEqual([earplug]);
      expect(launch.venueId).toBe(venue);
      expect(launch.price).toBe(5); // legacy cents → dollars
      const pastShow = { title: "EARPLUG LAUNCH NIGHT", meta: "APR 3" };
      expect(ep.pastShows).toEqual([pastShow]);
      expect(tm.pastShows).toEqual([pastShow]); // accepted co-host played too
    });
  });
});
