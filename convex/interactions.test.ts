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
        flyKey: "xerox",
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

describe("interactions hydration with shared venues, bands and flyers", () => {
  const DAY = 86_400_000;

  function bandFields(name: string) {
    return {
      name,
      slug: name.toLowerCase(),
      genres: ["punk"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: name.slice(0, 2).toUpperCase(),
      followerCount: 0,
      bio: "",
      pastShows: [],
    };
  }

  function gigFields(startsAt: number) {
    return {
      price: 5,
      startsAt,
      doorsTime: "7PM / 8PM",
      flyKey: "paper",
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "No cap",
      goingCount: 0,
    };
  }

  test("history resolves repeated venues, lineup bands and flyers to the same values as one-off lookups", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    const fixture = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", {
        name: "Shared Room",
        area: "Oakland",
        addr: "1 Shared Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const goneVenueId = await ctx.db.insert("venues", {
        name: "Gone Room",
        area: "Oakland",
        addr: "2 Gone Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const alphaId = await ctx.db.insert("bands", bandFields("Alpha"));
      const betaId = await ctx.db.insert("bands", bandFields("Beta"));
      const goneBandId = await ctx.db.insert("bands", bandFields("Gamma"));
      const flyerStorageId = await ctx.storage.store(new Blob(["flyer"]));
      const gigs = {
        newest: await ctx.db.insert("gigs", {
          ...gigFields(now - DAY),
          title: "Newest",
          venueId,
          flyKey: "custom",
          flyStorageId: flyerStorageId,
          lineup: [alphaId, betaId],
        }),
        middle: await ctx.db.insert("gigs", {
          ...gigFields(now - 2 * DAY),
          title: "Middle",
          venueId,
          flyKey: "custom",
          flyStorageId: flyerStorageId,
          lineup: [betaId, goneBandId],
        }),
        oldest: await ctx.db.insert("gigs", {
          ...gigFields(now - 3 * DAY),
          title: "Oldest",
          venueId: goneVenueId,
          lineup: [alphaId],
        }),
        upcoming: await ctx.db.insert("gigs", {
          ...gigFields(now + DAY),
          title: "Upcoming",
          venueId,
          lineup: [alphaId],
        }),
        removed: await ctx.db.insert("gigs", {
          ...gigFields(now - 4 * DAY),
          title: "Removed",
          venueId,
          lineup: [alphaId],
        }),
      };
      return { gigs, goneVenueId, goneBandId, flyerStorageId };
    });

    const asFan = t.withIdentity({ subject: "history_fan", email: "h@x.com" });
    await asFan.mutation(api.users.ensureUser, {});
    for (const gigId of Object.values(fixture.gigs)) {
      await asFan.mutation(api.interactions.toggleRsvp, { gigId, on: true });
    }
    const flyerUrl = await t.run(async (ctx) => {
      await ctx.db.delete(fixture.goneVenueId);
      await ctx.db.delete(fixture.goneBandId);
      await ctx.db.delete(fixture.gigs.removed);
      return await ctx.storage.getUrl(fixture.flyerStorageId);
    });
    expect(flyerUrl).not.toBeNull();

    expect(await asFan.query(api.interactions.history, { now })).toEqual([
      {
        gigId: fixture.gigs.newest,
        title: "Newest",
        startsAt: now - DAY,
        venueName: "Shared Room",
        bandNames: ["Alpha", "Beta"],
        flyKey: "custom",
        flyerUrl,
        status: "rsvped",
      },
      {
        gigId: fixture.gigs.middle,
        title: "Middle",
        startsAt: now - 2 * DAY,
        venueName: "Shared Room",
        bandNames: ["Beta"],
        flyKey: "custom",
        flyerUrl,
        status: "rsvped",
      },
      {
        gigId: fixture.gigs.oldest,
        title: "Oldest",
        startsAt: now - 3 * DAY,
        venueName: "",
        bandNames: ["Alpha"],
        flyKey: "paper",
        flyerUrl: null,
        status: "rsvped",
      },
    ]);
  });

  test("myInteractions hydrates RSVP'd and saved gigs sharing a band and a flyer", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    const fixture = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", {
        name: "Shared Room",
        area: "Oakland",
        addr: "1 Shared Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const alphaId = await ctx.db.insert("bands", bandFields("Alpha"));
      const betaId = await ctx.db.insert("bands", bandFields("Beta"));
      const flyerStorageId = await ctx.storage.store(new Blob(["flyer"]));
      const firstGigId = await ctx.db.insert("gigs", {
        ...gigFields(now + DAY),
        title: "First",
        venueId,
        flyKey: "custom",
        flyStorageId: flyerStorageId,
        lineup: [alphaId, betaId],
      });
      const secondGigId = await ctx.db.insert("gigs", {
        ...gigFields(now + 2 * DAY),
        title: "Second",
        venueId,
        flyKey: "custom",
        flyStorageId: flyerStorageId,
        lineup: [alphaId],
      });
      const flyerUrl = await ctx.storage.getUrl(flyerStorageId);
      return { venueId, alphaId, betaId, firstGigId, secondGigId, flyerUrl };
    });
    expect(fixture.flyerUrl).not.toBeNull();

    const asFan = t.withIdentity({ subject: "mine_fan", email: "m@x.com" });
    await asFan.mutation(api.users.ensureUser, {});
    await asFan.mutation(api.interactions.toggleRsvp, {
      gigId: fixture.firstGigId,
      on: true,
    });
    await asFan.mutation(api.interactions.toggleSave, {
      gigId: fixture.secondGigId,
      on: true,
    });
    await asFan.mutation(api.interactions.toggleSave, {
      gigId: fixture.firstGigId,
      on: true,
    });

    const commonPayload = {
      venueId: fixture.venueId,
      price: 5,
      doorsTime: "7PM / 8PM",
      flyKey: "custom",
      flyerUrl: fixture.flyerUrl,
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
      createdByBand: null,
      lifecycle: "published",
      discoveryListingReady: false,
    };
    expect(await asFan.query(api.interactions.myInteractions, {})).toEqual({
      rsvpGigIds: [fixture.firstGigId],
      followBandIds: [],
      savedGigIds: [fixture.secondGigId, fixture.firstGigId],
      gigs: [
        {
          ...commonPayload,
          _id: fixture.firstGigId,
          slug: fixture.firstGigId,
          title: "First",
          startsAt: now + DAY,
          doorsAt: now + DAY,
          lineup: [fixture.alphaId, fixture.betaId],
          performers: [
            { name: "Alpha", role: "headliner", bandId: fixture.alphaId },
            { name: "Beta", role: "support", bandId: fixture.betaId },
          ],
          goingCount: 1,
        },
        {
          ...commonPayload,
          _id: fixture.secondGigId,
          slug: fixture.secondGigId,
          title: "Second",
          startsAt: now + 2 * DAY,
          doorsAt: now + 2 * DAY,
          lineup: [fixture.alphaId],
          performers: [
            { name: "Alpha", role: "headliner", bandId: fixture.alphaId },
          ],
          goingCount: 0,
        },
      ],
      attendedCount: 0,
    });
  });
});

describe("RSVP tickets and Door Mode", () => {
  test("keeps tickets private, rejects wrong gigs, checks in idempotently, and revokes on RSVP removal", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "door_admin", email: "door@x.com", name: "Door Admin" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Door Band",
      genres: ["punk"],
      bio: "",
      area: "Oakland",
      inviteHandles: [],
    });
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        name: "Door Room",
        area: "Oakland",
        addr: "1 Door Street",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      }),
    );
    const publish = (title: string, offset: number) =>
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        title,
        startsAt: Date.now() + offset,
        doorsTime: "8PM / 9PM",
        venueId,
        price: 0,
        flyKey: "xerox",
        ticketing: "rsvp",
        ageRequirement: "allAges",
        cap: "No cap",
      });
    const first = await publish("Door One", 86_400_000);
    const second = await publish("Door Two", 2 * 86_400_000);
    const projects = await asAdmin.query(api.gigs.manageForBand, { bandId });
    const firstProject = projects.find((project) => project.publicGigId === first.gigId)!;
    const secondProject = projects.find((project) => project.publicGigId === second.gigId)!;

    const asFan = t.withIdentity({ subject: "door_fan", email: "fan@x.com", name: "Ticket Fan" });
    const asOtherFan = t.withIdentity({ subject: "other_fan", email: "other@x.com" });
    await asFan.mutation(api.users.ensureUser, {});
    await asOtherFan.mutation(api.users.ensureUser, {});
    await asFan.mutation(api.interactions.toggleRsvp, { gigId: first.gigId, on: true });
    const ticket = await asFan.mutation(api.interactions.ticketForGig, { gigId: first.gigId });
    expect(ticket.payload).toMatch(/^earplug:ticket:v1:[a-f0-9]{64}$/);
    await expect(
      asOtherFan.mutation(api.interactions.ticketForGig, { gigId: first.gigId }),
    ).rejects.toThrow("RSVP before");

    expect(await asAdmin.query(api.gigs.doorRoster, { projectId: firstProject._id })).toEqual({
      total: 1,
      checkedIn: 0,
      truncated: false,
    });
    expect(
      await asAdmin.mutation(api.gigs.checkInTicket, {
        projectId: secondProject._id,
        payload: ticket.payload,
      }),
    ).toEqual({ status: "wrongGig" });
    const checkedIn = await asAdmin.mutation(api.gigs.checkInTicket, {
      projectId: firstProject._id,
      payload: ticket.payload,
    });
    expect(checkedIn).toMatchObject({ status: "checkedIn", fanName: "Ticket Fan" });
    const repeated = await asAdmin.mutation(api.gigs.checkInTicket, {
      projectId: firstProject._id,
      payload: ticket.payload,
    });
    expect(repeated).toMatchObject({ status: "alreadyCheckedIn", fanName: "Ticket Fan" });
    expect((await asAdmin.query(api.gigs.doorRoster, { projectId: firstProject._id })).checkedIn).toBe(1);

    await asFan.mutation(api.interactions.toggleRsvp, { gigId: first.gigId, on: false });
    expect(
      await asAdmin.mutation(api.gigs.checkInTicket, {
        projectId: firstProject._id,
        payload: ticket.payload,
      }),
    ).toEqual({ status: "invalid" });
  });
});
