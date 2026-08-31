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
      area: "Bay Area",
      inviteHandles: [],
    });
    const { bandId: otherId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Wet Denim",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
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
      flyKey: "xerox" as const,
      genres: ["folk"],
      desc: "",
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
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
      {
        name: "No History",
        genres: ["noise"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );

    expect(
      await t.query(api.gigs.pastForBand, { bandId: emptyBandId }),
    ).toEqual({ gigs: [], venues: [] });
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
      area: "Bay Area",
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
    ageRequirement: "allAges" as const,
    cap: "No cap",
  };

  test("rejects unauthenticated and non-members; member (non-admin) rejected too", async () => {
    const { t, bandId, venueId } = await setupBand();
    await expect(
      t.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow();

    const asStranger = t.withIdentity({
      subject: "user_stranger",
      email: "s@x.com",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow("Not an admin");

    // Plain member (not admin) also rejected.
    const asMember = t.withIdentity({
      subject: "user_member",
      email: "m@x.com",
    });
    const { userId } = await asMember.mutation(api.users.ensureUser, {});
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", { bandId, userId, role: "member" });
    });
    await expect(
      asMember.mutation(api.gigs.publishGig, { bandId, venueId, ...gigArgs }),
    ).rejects.toThrow("Not an admin");
  });

  test("admin publishes the explicit age requirement with the gig", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
      ageRequirement: "21Plus",
    });
    const gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.flyKey).toBe("riso");
    expect(gig!.ageRequirement).toBe("21Plus");
    expect(gig!.goingCount).toBe(0);
    expect(gig!.lineup).toEqual([bandId]);
    expect(gig!.createdByBand).toBe(bandId);
  });

  test("preserves an explicitly supplied doors time", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const doorsAt = gigArgs.startsAt - 45 * 60_000;
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
      doorsAt,
    });

    expect((await t.run(async (ctx) => ctx.db.get(gigId)))?.doorsAt).toBe(
      doorsAt,
    );
  });

  test("requires one of the three supported age requirements", async () => {
    const { asAdmin, bandId, venueId } = await setupBand();
    const { ageRequirement: _ageRequirement, ...withoutAge } = gigArgs;

    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...withoutAge,
      } as never),
    ).rejects.toThrow("Validator error");
    await expect(
      asAdmin.mutation(api.gigs.publishGig, {
        bandId,
        venueId,
        ...gigArgs,
        ageRequirement: "16Plus" as never,
      }),
    ).rejects.toThrow("Validator error: Expected one of");
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

  test("external ticketing requires an HTTPS URL", async () => {
    const { asAdmin, bandId, venueId } = await setupBand();
    const error = "External ticketing requires a valid HTTPS URL";

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

describe("public gig slugs", () => {
  test("publishes unique stable slugs and resolves slugs, legacy ids, and misses", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "slug_admin", email: "slug@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Slug Band",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
      inviteHandles: [],
    });
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        name: "Slug Room",
        area: "Oakland",
        addr: "1 Slug Way",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      }),
    );
    const fields = {
      bandId,
      title: "Same Night",
      startsAt: Date.now() + 86_400_000,
      doorsTime: "8PM / 9PM",
      venueId,
      price: 0,
      flyKey: "xerox" as const,
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "No cap",
    };
    const first = await asAdmin.mutation(api.gigs.publishGig, fields);
    const second = await asAdmin.mutation(api.gigs.publishGig, {
      ...fields,
      startsAt: fields.startsAt + 86_400_000,
    });
    expect(first.slug).toBe("same-night");
    expect(second.slug).toBe("same-night-2");
    expect((await t.query(api.gigs.resolvePublic, { ref: first.slug }))?._id).toBe(first.gigId);
    expect((await t.query(api.gigs.resolvePublic, { ref: first.gigId }))?._id).toBe(first.gigId);
    expect(await t.query(api.gigs.resolvePublic, { ref: "not an id !!!" })).toBeNull();

    const projects = await asAdmin.query(api.gigs.manageForBand, { bandId });
    const project = projects.find((candidate) => candidate.publicGigId === first.gigId)!;
    await asAdmin.mutation(api.gigs.unpublish, { projectId: project._id });
    const draft = await asAdmin.query(api.gigs.getProject, { projectId: project._id });
    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Renamed Night",
      doorsAt: draft.doorsAt,
      startsAt: draft.startsAt,
      venueId: draft.venueId,
      price: draft.price,
      flyKey: draft.flyKey,
      flyStorageId: null,
      overlay: draft.overlay,
      desc: draft.desc,
      ticketing: draft.ticketing,
      ageRequirement: draft.ageRequirement,
      externalUrl: draft.externalUrl ?? null,
      cap: draft.cap,
    });
    const republished = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(republished.slug).toBe(first.slug);
  });
});

describe("feed and array-shaped queries (contract clarifications)", () => {
  test("normalizes a legacy gig without stored age to allAges", async () => {
    const t = convexTest(schema);
    const { bandId, venueId } = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", {
        name: "Legacy Bill",
        slug: "legacy-bill",
        genres: ["punk"],
        area: "Bay Area",
        colorHex: "#7B8FFF",
        initials: "LB",
        followerCount: 0,
        bio: "",
        pastShows: [],
      });
      const venueId = await ctx.db.insert("venues", {
        name: "Legacy Hall",
        area: "Oakland",
        addr: "1 Archive Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      await ctx.db.insert("gigs", {
        title: "Before Age Fields",
        venueId,
        price: 0,
        startsAt: Date.now() + 86_400_000,
        doorsTime: "7PM / 8PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: ["punk"],
        desc: "",
        ticketing: "rsvp",
        cap: "No cap",
        goingCount: 0,
      });
      return { bandId, venueId };
    });

    const feed = await t.query(api.gigs.feed, {});
    expect(feed.gigs).toHaveLength(1);
    expect(feed.gigs[0].ageRequirement).toBe("allAges");
  });

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
    expect(gig.ageRequirement).toBe("allAges");

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
    expect(forBand.every((gig) => gig.lineup.includes(foghorn!._id))).toBe(
      true,
    );
  });

  test("reports the first gig omitted from the bounded feed", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Long Calendar",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
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
    expect(feed.nextStartsAt).toBe(firstStartsAt + MAX_FEED_GIGS * 60_000);
  });

  test("cancelled rows cannot crowd later published gigs out of the feed", async () => {
    const t = convexTest(schema);
    const { bandId, venueId } = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", {
        name: "Lifecycle Index",
        slug: "lifecycle-index",
        genres: ["punk"],
        area: "Bay Area",
        colorHex: "#7B8FFF",
        initials: "LI",
        followerCount: 0,
        bio: "",
        pastShows: [],
      });
      const venueId = await ctx.db.insert("venues", {
        name: "Indexed Hall",
        area: "Oakland",
        addr: "1 Fast Query Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      return { bandId, venueId };
    });
    const firstStartsAt = Date.now() + 86_400_000;
    const common = {
      venueId,
      price: 0,
      doorsTime: "7PM / 8PM",
      flyKey: "paper",
      lineup: [bandId],
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "No cap",
      goingCount: 0,
    };
    await t.run(async (ctx) => {
      for (let index = 0; index <= MAX_FEED_GIGS * 4; index++) {
        await ctx.db.insert("gigs", {
          ...common,
          title: `Cancelled ${index}`,
          startsAt: firstStartsAt + index * 60_000,
          lifecycle: "cancelled",
        });
      }
      await ctx.db.insert("gigs", {
        ...common,
        title: "Still Visible",
        startsAt: firstStartsAt + (MAX_FEED_GIGS * 4 + 1) * 60_000,
        lifecycle: "published",
      });
    });

    expect(
      (await t.query(api.gigs.feed, {})).gigs.map((gig) => gig.title),
    ).toEqual(["Still Visible"]);
  });

  test("forBand finds a show beyond the bounded discovery feed", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId: crowdedBandId } = await asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Crowded Calendar",
        genres: ["punk"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const { bandId: followedBandId } = await asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Later Band",
        genres: ["noise"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const venueId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "Index Hall",
        area: "Oakland",
        addr: "2 Date St",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.2,
      }),
    );
    const firstStartsAt = Date.now() + 86_400_000;
    const base = {
      venueId,
      price: 0,
      doorsTime: "7PM / 8PM",
      flyKey: "paper",
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "No cap",
      goingCount: 0,
    };
    await t.run(async (ctx) => {
      for (let index = 0; index < MAX_FEED_GIGS; index++) {
        await insertGigWithBandIndex(ctx, {
          ...base,
          title: `Crowding Gig ${index}`,
          startsAt: firstStartsAt + index * 60_000,
          lineup: [crowdedBandId],
        });
      }
      await insertGigWithBandIndex(ctx, {
        ...base,
        title: "Followed Show Beyond Feed",
        startsAt: firstStartsAt + MAX_FEED_GIGS * 60_000,
        lineup: [followedBandId],
      });
    });

    const feed = await t.query(api.gigs.feed, {});
    expect(feed.gigs.some((gig) => gig.lineup.includes(followedBandId))).toBe(
      false,
    );
    const followedShows = await t.query(api.gigs.forBand, {
      bandId: followedBandId,
    });
    expect(followedShows.map((gig) => gig.title)).toEqual([
      "Followed Show Beyond Feed",
    ]);
  });

  test("myBands returns band+role entries for the caller", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      genres: ["shoegaze", "punk"],
      bio: "Loud flowers.",
      area: "Bay Area",
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
