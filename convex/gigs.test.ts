import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

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

  test("admin publishes; flyKey server-assigned bluetype, goingCount 0", async () => {
    const { t, asAdmin, bandId, venueId } = await setupBand();
    const { gigId } = await asAdmin.mutation(api.gigs.publishGig, {
      bandId,
      venueId,
      ...gigArgs,
    });
    const gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.flyKey).toBe("bluetype");
    expect(gig!.goingCount).toBe(0);
    expect(gig!.lineup).toEqual([bandId]);
    expect(gig!.createdByBand).toBe(bandId);
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

    // bands:search — top-level array; "" → all (capped 50).
    const all = await t.query(api.bands.search, { q: "" });
    expect(Array.isArray(all)).toBe(true);
    expect(all.length).toBe(6);
    const hits = await t.query(api.bands.search, { q: "Foghorn" });
    expect(hits.length).toBe(1);
    expect(hits[0].name).toBe("Foghorn Diet");

    // videos:forBand — top-level array ordered by order asc.
    const videos = await t.query(api.videos.forBand, { bandId: foghorn!._id });
    expect(Array.isArray(videos)).toBe(true);
    expect(videos.length).toBe(5);
    expect(videos.map((video) => video.order)).toEqual([0, 1, 2, 3, 4]);
    expect(videos[0].pinned).toBe(true);
    expect(videos[0].views).toBe(12400);
    expect(videos[0].lengthSec).toBe(161);

    // bands:myBands — [] unauthenticated (never throws).
    expect(await t.query(api.bands.myBands, {})).toEqual([]);
    // users:me — null unauthenticated.
    expect(await t.query(api.users.me, {})).toBeNull();
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
    expect(mine[0].band.followerCount).toBe(3); // 1 + invites
    expect(mine[0].band.initials).toBe("SB");
  });
});
