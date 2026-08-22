import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { insertGigWithBandIndex, MAX_FEED_GIGS } from "./lib/helpers";
import schema from "./schema";

describe("gigs:pastForBand", () => {
  /** A band, a venue, and one gig on each side of the feed cutoff. */
  async function setupHistory() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Ancient Quaffle",
      genres: ["folk"],
      bio: "",
      inviteHandles: [],
    });
    const { bandId: otherId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Wet Denim",
      genres: ["punk"],
      bio: "",
      inviteHandles: [],
    });
    const venueId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "Kingman Hall",
        area: "Berkeley",
        addr: "1730 La Loma Ave",
        distSF: "12.1 mi",
        distOak: "5.4 mi",
        lat: 37.8792,
        lng: -122.2611,
      }),
    );
    const base = {
      venueId,
      price: 5,
      doorsTime: "7PM / 8PM",
      flyKey: "paper",
      genres: ["folk"],
      desc: "",
      ticketing: "rsvp" as const,
      cap: "No cap",
      goingCount: 0,
    };
    await t.run(async (ctx) => {
      await insertGigWithBandIndex(ctx, {
        ...base,
        title: "Older Show",
        startsAt: Date.now() - 90 * 86400_000,
        lineup: [bandId],
      });
      await insertGigWithBandIndex(ctx, {
        ...base,
        title: "Recent Show",
        startsAt: Date.now() - 7 * 86400_000,
        lineup: [bandId],
      });
      await insertGigWithBandIndex(ctx, {
        ...base,
        title: "Upcoming Show",
        startsAt: Date.now() + 7 * 86400_000,
        lineup: [bandId],
      });
      await insertGigWithBandIndex(ctx, {
        ...base,
        title: "Someone Else's Past Show",
        startsAt: Date.now() - 30 * 86400_000,
        lineup: [otherId],
      });
    });
    return { t, bandId, otherId, venueId };
  }

  test("returns only this band's past gigs, newest first, with their venues", async () => {
    const { t, bandId, venueId } = await setupHistory();
    const { gigs, venues } = await t.query(api.gigs.pastForBand, { bandId });

    expect(gigs.map((g) => g.title)).toEqual(["Recent Show", "Older Show"]);
    expect(venues.length).toBe(1);
    expect(venues[0]._id).toBe(venueId);
  });

  test("excludes upcoming gigs, which forBand already covers", async () => {
    const { t, bandId } = await setupHistory();
    const { gigs } = await t.query(api.gigs.pastForBand, { bandId });
    const upcoming = await t.query(api.gigs.forBand, { bandId });

    expect(gigs.some((g) => g.title === "Upcoming Show")).toBe(false);
    expect(upcoming.map((g) => g.title)).toEqual(["Upcoming Show"]);
  });

  test("a band with no past gigs gets empty arrays, not an error", async () => {
    const { t, otherId } = await setupHistory();
    const asStranger = t.withIdentity({ subject: "user_x", email: "x@x.com" });
    await asStranger.mutation(api.users.ensureUser, {});
    const { bandId: emptyBandId } = await asStranger.mutation(
      api.bands.createBand,
      { name: "No History", genres: ["noise"], bio: "", inviteHandles: [] },
    );

    expect(await t.query(api.gigs.pastForBand, { bandId: emptyBandId })).toEqual(
      { gigs: [], venues: [] },
    );
    // The other band's single past gig is still reachable from its own profile.
    const { gigs } = await t.query(api.gigs.pastForBand, { bandId: otherId });
    expect(gigs.map((g) => g.title)).toEqual(["Someone Else's Past Show"]);
  });

  test("is public — an anonymous visitor can read a band's history", async () => {
    const { t, bandId } = await setupHistory();
    const { gigs } = await t.query(api.gigs.pastForBand, { bandId });
    expect(gigs.length).toBe(2);
  });
});

describe("gigs:publishGig auth", () => {
  async function setupBand() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Foghorn Diet",
      genres: ["garage"],
      bio: "",
      inviteHandles: [],
    });
    const venueId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "The Foghorn Club",
        area: "Mission, SF",
        addr: "2455 Harrison St",
        distSF: "0.8 mi",
        distOak: "6.3 mi",
        lat: 37.7524,
        lng: -122.418,
      }),
    );
    return { t, asAdmin, bandId, venueId };
  }

  const gigArgs = {
    title: "Riptide Release Show",
    startsAt: Date.now() + 86400_000,
    doorsTime: "8PM / 9PM",
    price: 10,
    flyKey: "riso" as const,
    ticketing: "rsvp" as const,
    cap: "No cap",
  };

  test("rejects unauthenticated and non-members; member (non-admin) rejected too", async () => {
    const { t, bandId, venueId } = await setupBand();
    await expect(
      t.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow();

    const asStranger = t.withIdentity({ subject: "user_stranger", email: "s@x.com" });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow("Not an admin");

    // Plain member (not admin) also rejected.
    const asMember = t.withIdentity({ subject: "user_member", email: "m@x.com" });
    const { userId } = await asMember.mutation(api.users.ensureUser, {});
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", { bandId, userId, role: "member" });
    });
    await expect(
      asMember.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow("Not an admin");
  });

  test("admin publishes; flyKey is the chosen press, goingCount 0", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
    });
    const gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.flyKey).toBe("riso");
    expect(gig!.goingCount).toBe(0);
    expect(gig!.lineup).toEqual([bandId]);
    expect(gig!.createdByBand).toBe(bandId);
  });

  test("rejects a flyKey outside the press list", async () => {
    const { asAdmin, bandId, venueId } = await setupBand();
    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        flyKey: "hologram" as never,
      }),
    ).rejects.toThrow("Validator error: Expected one of");
  });

  test("publishes custom flyer storage and resolves its URL", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const flyStorageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
      flyKey: "custom",
      flyStorageId,
    });
    const gigs = await t.query(api.gigs.forBand, { bandId });
    const gig = gigs.find((candidate) => candidate._id === gigId);
    expect(gig?.flyKey).toBe("custom");
    expect(gig?.flyerUrl).toEqual(expect.any(String));
  });

  test("rejects a custom press without flyer storage", async () => {
    const { asAdmin, bandId, venueId } = await setupBand();
    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        flyKey: "custom",
      }),
    ).rejects.toThrow("Custom flyer requires flyStorageId");
  });

  test("rejects a custom press whose flyer blob was deleted", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const flyStorageId = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      await ctx.storage.delete(storageId);
      return storageId;
    });
    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        flyKey: "custom",
        flyStorageId,
      }),
    ).rejects.toThrow("Flyer upload not found");
  });

  test("drops flyer storage supplied with a non-custom press", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const flyStorageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
      flyStorageId,
    });
    const rawGig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(rawGig?.flyStorageId).toBeUndefined();
    const gigs = await t.query(api.gigs.forBand, { bandId });
    expect(gigs.find((gig) => gig._id === gigId)?.flyerUrl).toBeNull();
  });

  test("external ticketing requires an http(s) URL", async () => {
    const { asAdmin, bandId, venueId } = await setupBand();
    const error = "External ticketing requires a valid http(s) URL";

    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        ticketing: "external",
      }),
    ).rejects.toThrow(error);
    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        ticketing: "external",
        externalUrl: "not-a-url",
      }),
    ).rejects.toThrow(error);
  });

  test("rsvp ticketing drops an external URL", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
      externalUrl: "https://example.com",
    });
    const gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.externalUrl).toBeUndefined();
  });
});

describe("feed and array-shaped queries (contract clarifications)", () => {
  test("seedDemo then feed: object with arrays; band summaries always carry pastShows; explicit nulls", async () => {
    const t = convexTest(schema);
    await t.mutation(internal.seed.seedDemo, {});
    // Idempotent re-run.
    const again = await t.mutation(internal.seed.seedDemo, {});
    expect(again).toEqual({ seeded: false });

    const feed = await t.query(api.gigs.feed, {});
    expect(Array.isArray(feed.gigs)).toBe(true);
    expect(Array.isArray(feed.venues)).toBe(true);
    expect(Array.isArray(feed.bands)).toBe(true);
    expect(feed.gigs.length).toBe(7);
    expect(feed.venues.length).toBe(6);
    expect(feed.bands.length).toBe(6);
    expect(feed.nextStartsAt).toBeNull();

    // Ascending startsAt.
    const starts = feed.gigs.map((gig) => gig.startsAt);
    expect([...starts].sort((a, b) => a - b)).toEqual(starts);

    // Every contract field present; explicit nulls when absent.
    const gig = feed.gigs[0];
    expect(gig.externalUrl).toBeNull();
    expect(gig.createdByBand).toBeNull();
    expect(gig.cap).toBe("No cap");

    // Band summaries always include pastShows.
    for (const band of feed.bands) {
      expect(Array.isArray(band.pastShows)).toBe(true);
    }
    const foghorn = feed.bands.find((band) => band.name === "Foghorn Diet");
    expect(foghorn!.pastShows.length).toBe(4);
    expect(foghorn!.colorHex).toBe("#7B8FFF");
    expect(foghorn!.initials).toBe("FD");
    expect(foghorn!.followerCount).toBe(486);

    // gigs:forBand — top-level array, upcoming only, ascending.
    const forBand = await t.query(api.gigs.forBand, { bandId: foghorn!._id });
    expect(Array.isArray(forBand)).toBe(true);
    expect(forBand.length).toBe(2); // g2 + g7
    expect(forBand.every((gig) => gig.lineup.includes(foghorn!._id))).toBe(true);
  });

  test("reports the first gig omitted from the bounded feed", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Long Calendar",
      genres: ["punk"],
      bio: "",
      inviteHandles: [],
    });
    const venueId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "Calendar Hall",
        area: "Mission, SF",
        addr: "1 Date St",
        distSF: "1.0 mi",
        distOak: "7.0 mi",
        lat: 37.75,
        lng: -122.42,
      }),
    );
    const firstStartsAt = Date.now() + 86_400_000;
    await t.run(async (ctx) => {
      for (let index = 0; index <= MAX_FEED_GIGS; index++) {
        await ctx.db.insert("gigs", {
          title: `Gig ${index}`,
          venueId,
          price: 0,
          startsAt: firstStartsAt + index * 60_000,
          doorsTime: "7PM / 8PM",
          flyKey: "paper",
          lineup: [bandId],
          genres: ["punk"],
          desc: "",
          ticketing: "rsvp",
          cap: "No cap",
          goingCount: 0,
        });
      }
    });

    const feed = await t.query(api.gigs.feed, {});

    expect(feed.gigs).toHaveLength(MAX_FEED_GIGS);
    expect(feed.gigs[0].startsAt).toBe(firstStartsAt);
    expect(feed.nextStartsAt).toBe(
      firstStartsAt + MAX_FEED_GIGS * 60_000,
    );
  });

  test("myBands returns band+role entries for the caller", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      genres: ["shoegaze", "punk"],
      bio: "Loud flowers.",
      inviteHandles: ["@friend1", "@friend2"],
    });
    const mine = await asAdmin.query(api.bands.myBands, {});
    expect(mine.length).toBe(1);
    expect(mine[0].role).toBe("admin");
    expect(mine[0].band.name).toBe("Static Bloom");
    // Only the admin member row counts; invite handles are stored strings.
    expect(mine[0].band.followerCount).toBe(1);
    expect(mine[0].band.initials).toBe("SB");
  });
});
