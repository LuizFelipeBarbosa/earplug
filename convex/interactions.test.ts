import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

async function setup() {
  const t = convexTest(schema);
  const { venueId, bandId, gigId } = await t.run(async (ctx) => {
    const venueId = await ctx.db.insert("venues", {
      name: "Casa Quake",
      area: "Bernal Heights, SF",
      addr: "(address with RSVP)",
      distSF: "1.2 mi",
      distOak: "6.7 mi",
      lat: 37.7399,
      lng: -122.4166,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Mission Creep",
      slug: "mission-creep",
      genres: ["hardcore"],
      area: "Mission, SF",
      colorHex: "#E4DC4A",
      initials: "MC",
      followerCount: 10,
      bio: "",
      pastShows: [],
    });
    const gigId = await ctx.db.insert("gigs", {
      title: "Basement Blowout",
      venueId,
      price: 0,
      startsAt: Date.now() + 3600_000,
      doorsTime: "8PM / 9PM",
      flyKey: "paper",
      lineup: [bandId],
      genres: ["hardcore"],
      desc: "",
      ticketing: "rsvp",
      cap: "No cap",
      goingCount: 43,
    });
    return { venueId, bandId, gigId };
  });
  const asFan = t.withIdentity({ subject: "user_fan", email: "fan@x.com" });
  await asFan.mutation(api.users.ensureUser, {});
  return { t, asFan, venueId, bandId, gigId };
}

describe("interactions", () => {
  test("mutations throw when unauthenticated", async () => {
    const { t, gigId, bandId } = await setup();
    await expect(
      t.mutation(api.interactions.toggleRsvp, { gigId }),
    ).rejects.toThrow();
    await expect(
      t.mutation(api.interactions.toggleFollow, { bandId }),
    ).rejects.toThrow();
    await expect(
      t.mutation(api.interactions.toggleSave, { gigId }),
    ).rejects.toThrow();
  });

  test("myInteractions returns empty shape when unauthenticated", async () => {
    const { t } = await setup();
    const result = await t.query(api.interactions.myInteractions, {});
    expect(result).toEqual({
      rsvpGigIds: [],
      followBandIds: [],
      savedGigIds: [],
      gigs: [],
      attendedCount: 0,
    });
  });

  test("hydrates a deduplicated interacted gig beyond the feed window", async () => {
    const { t, asFan, venueId, bandId } = await setup();
    const firstStartsAt = Date.now() + 2 * 3600_000;
    const outsideGigId = await t.run(async (ctx) => {
      const common = {
        venueId,
        price: 0,
        doorsTime: "8PM / 9PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: ["hardcore"],
        desc: "",
        ticketing: "rsvp" as const,
        ageRequirement: "allAges" as const,
        cap: "No cap",
        goingCount: 0,
      };
      for (let index = 0; index < 200; index++) {
        await ctx.db.insert("gigs", {
          ...common,
          title: `Feed gig ${index}`,
          startsAt: firstStartsAt + index * 3600_000,
        });
      }
      return await ctx.db.insert("gigs", {
        ...common,
        title: "Beyond the global feed",
        startsAt: firstStartsAt + 200 * 3600_000,
      });
    });

    const feed = await t.query(api.gigs.feed, {});
    expect(feed.gigs).toHaveLength(200);
    expect(feed.gigs.map((gig) => gig._id)).not.toContain(outsideGigId);

    await asFan.mutation(api.interactions.toggleRsvp, {
      gigId: outsideGigId,
    });
    await asFan.mutation(api.interactions.toggleSave, { gigId: outsideGigId });

    const mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([outsideGigId]);
    expect(mine.savedGigIds).toEqual([outsideGigId]);
    expect(mine.gigs).toHaveLength(1);
    expect(mine.gigs[0]).toMatchObject({
      _id: outsideGigId,
      title: "Beyond the global feed",
    });
  });

  test("toggleRsvp double-toggle adjusts goingCount both ways", async () => {
    const { t, asFan, gigId } = await setup();
    const on = await asFan.mutation(api.interactions.toggleRsvp, { gigId });
    expect(on).toEqual({ on: true });
    let gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.goingCount).toBe(44);

    let mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([gigId]);

    const off = await asFan.mutation(api.interactions.toggleRsvp, { gigId });
    expect(off).toEqual({ on: false });
    gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.goingCount).toBe(43);
    mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([]);
  });

  test("toggleFollow double-toggle adjusts followerCount both ways", async () => {
    const { t, asFan, bandId } = await setup();
    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    let band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band!.followerCount).toBe(11);
    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band!.followerCount).toBe(10);
  });

  test("toggleFollow preserves the createBand follower invariant", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "user_admin",
      email: "admin@x.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Invariant Youth",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
      inviteHandles: ["@a", "@b"],
    });
    const readCounts = () =>
      t.run(async (ctx) => {
        const band = await ctx.db.get(bandId);
        const follows = await ctx.db
          .query("follows")
          .withIndex("by_band", (q) => q.eq("bandId", bandId))
          .take(10);
        const members = await ctx.db
          .query("bandMembers")
          .withIndex("by_band", (q) => q.eq("bandId", bandId))
          .take(10);
        return {
          followerCount: band!.followerCount,
          rowCount: follows.length + members.length,
        };
      });

    expect(await readCounts()).toEqual({ followerCount: 1, rowCount: 1 });

    const asFan = t.withIdentity({
      subject: "user_fan_2",
      email: "fan2@x.com",
    });
    await asFan.mutation(api.users.ensureUser, {});
    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    expect(await readCounts()).toEqual({ followerCount: 2, rowCount: 2 });

    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    expect(await readCounts()).toEqual({ followerCount: 1, rowCount: 1 });
  });

  test("history returns only past RSVPed gigs, newest first", async () => {
    const { t, asFan, venueId, bandId, gigId } = await setup();
    const now = Date.now();

    const [oldGigId, olderGigId] = await t.run(async (ctx) => {
      const base = {
        venueId,
        price: 0,
        doorsTime: "8PM / 9PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: ["hardcore"],
        desc: "",
        ticketing: "rsvp" as const,
        cap: "No cap",
        goingCount: 0,
      };
      const flyerStorageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      return [
        await ctx.db.insert("gigs", {
          ...base,
          title: "Last Month",
          startsAt: now - 30 * 24 * 3600_000,
        }),
        await ctx.db.insert("gigs", {
          ...base,
          title: "Two Months Back",
          startsAt: now - 60 * 24 * 3600_000,
          flyKey: "custom",
          flyStorageId: flyerStorageId,
        }),
      ];
    });

    // RSVP to both past gigs and the upcoming one; only the past two count.
    for (const id of [olderGigId, gigId, oldGigId]) {
      await asFan.mutation(api.interactions.toggleRsvp, { gigId: id });
    }

    expect(await t.query(api.interactions.history, { now })).toEqual([]);
    const history = await asFan.query(api.interactions.history, { now });
    expect(history.map((h) => h.title)).toEqual([
      "Last Month",
      "Two Months Back",
    ]);
    expect(history[0]).toEqual({
      gigId: oldGigId,
      title: "Last Month",
      startsAt: expect.any(Number),
      venueName: "Casa Quake",
      bandNames: ["Mission Creep"],
      flyKey: "paper",
      flyerUrl: null,
      status: "rsvped",
    });
    expect(history[1]).toMatchObject({
      gigId: olderGigId,
      flyKey: "custom",
      flyerUrl: expect.any(String),
      status: "rsvped",
    });

    const interactions = await asFan.query(api.interactions.myInteractions, {});
    expect(interactions.rsvpGigIds).toEqual(
      expect.arrayContaining([olderGigId, gigId, oldGigId]),
    );
    expect(interactions.gigs.map((gig) => gig._id)).toEqual([gigId]);
  });

  test("history skips missing gigs and tolerates missing venue, band, and flyer references", async () => {
    const { t, asFan } = await setup();
    const now = Date.now();
    const { historyGigId, deletedGigId, storageId, venueId, bandId } =
      await t.run(async (ctx) => {
        const venueId = await ctx.db.insert("venues", {
          name: "Temporary Venue",
          area: "Oakland",
          addr: "123 Test St",
          distSF: "8 mi",
          distOak: "1 mi",
          lat: 37.8,
          lng: -122.2,
        });
        const bandId = await ctx.db.insert("bands", {
          name: "Temporary Band",
          slug: "temporary-band",
          genres: ["punk"],
          area: "Oakland",
          colorHex: "#7B8FFF",
          initials: "TB",
          followerCount: 0,
          bio: "",
          pastShows: [],
        });
        const storageId = await ctx.storage.store(
          new Blob([new Uint8Array([1, 2, 3])]),
        );
        const common = {
          venueId,
          price: 0,
          doorsTime: "8PM / 9PM",
          flyKey: "custom",
          flyStorageId: storageId,
          lineup: [bandId],
          genres: ["punk"],
          desc: "",
          ticketing: "rsvp" as const,
          cap: "No cap",
          goingCount: 0,
        };
        return {
          historyGigId: await ctx.db.insert("gigs", {
            ...common,
            title: "Dangling Details",
            startsAt: now - 24 * 3600_000,
          }),
          deletedGigId: await ctx.db.insert("gigs", {
            ...common,
            title: "Deleted Gig",
            startsAt: now - 2 * 24 * 3600_000,
          }),
          storageId,
          venueId,
          bandId,
        };
      });

    await asFan.mutation(api.interactions.toggleRsvp, { gigId: historyGigId });
    await asFan.mutation(api.interactions.toggleRsvp, { gigId: deletedGigId });
    await t.run(async (ctx) => {
      await ctx.db.delete(deletedGigId);
      await ctx.db.delete(venueId);
      await ctx.db.delete(bandId);
      await ctx.storage.delete(storageId);
    });

    expect(await asFan.query(api.interactions.history, { now })).toEqual([
      {
        gigId: historyGigId,
        title: "Dangling Details",
        startsAt: expect.any(Number),
        venueName: "",
        bandNames: [],
        flyKey: "custom",
        flyerUrl: null,
        status: "rsvped",
      },
    ]);
  });

  test("toggleSave double-toggle", async () => {
    const { asFan, gigId } = await setup();
    expect(
      await asFan.mutation(api.interactions.toggleSave, { gigId }),
    ).toEqual({ on: true });
    let mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.savedGigIds).toEqual([gigId]);
    expect(
      await asFan.mutation(api.interactions.toggleSave, { gigId }),
    ).toEqual({ on: false });
    mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.savedGigIds).toEqual([]);
  });

  test("explicit on writes are idempotent for auth-replayed intents", async () => {
    const { t, asFan, gigId, bandId } = await setup();

    for (let index = 0; index < 2; index++) {
      expect(
        await asFan.mutation(api.interactions.toggleRsvp, { gigId, on: true }),
      ).toEqual({ on: true });
      expect(
        await asFan.mutation(api.interactions.toggleFollow, {
          bandId,
          on: true,
        }),
      ).toEqual({ on: true });
      expect(
        await asFan.mutation(api.interactions.toggleSave, { gigId, on: true }),
      ).toEqual({ on: true });
    }

    const gig = await t.run(async (ctx) => ctx.db.get(gigId));
    const band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(gig?.goingCount).toBe(44);
    expect(band?.followerCount).toBe(11);
    const mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([gigId]);
    expect(mine.followBandIds).toEqual([bandId]);
    expect(mine.savedGigIds).toEqual([gigId]);
  });
});
