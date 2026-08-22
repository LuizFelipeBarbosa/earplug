import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

function bandFields(name: string, followerCount: number) {
  return {
    name,
    slug: name.toLowerCase().replace(/\s+/g, "-"),
    genres: ["post-punk"],
    area: "Oakland",
    colorHex: "#7B8FFF",
    initials: "TS",
    followerCount,
    bio: "",
    pastShows: [],
  };
}

function userFields(n: number) {
  return {
    clerkId: `user_${n}`,
    name: `Fan ${n}`,
    email: `fan${n}@x.com`,
    genres: [],
    attendedCount: 0,
  };
}

async function setupPublishFixture() {
  const t = convexTest(schema);
  const { bandId, venueId } = await t.run(async (ctx) => {
    const bandId = await ctx.db.insert(
      "bands",
      bandFields("Production Values", 0),
    );
    const venueId = await ctx.db.insert("venues", {
      name: "The Real Room",
      area: "Mission, SF",
      addr: "123 Valencia St",
      distSF: "0.5 mi",
      distOak: "7.0 mi",
      lat: 37.76,
      lng: -122.42,
    });
    return { bandId, venueId };
  });
  return {
    t,
    bandId,
    venueId,
    fields: {
      bandId,
      title: "A Real Upcoming Gig",
      startsAt: Date.now() + 86_400_000,
      doorsTime: "7PM / 8PM",
      venueId,
      price: 18,
      flyKey: "blueprint" as const,
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "150",
    },
  };
}

describe("maintenance:recountBandFollowers", () => {
  test("defaults to a dry run and leaves a drifted count intact", async () => {
    const t = convexTest(schema);
    const bandId = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", bandFields("Driftwood", 99));
      const userId = await ctx.db.insert("users", userFields(1));
      await ctx.db.insert("follows", { bandId, userId });
      return bandId;
    });

    const result = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId,
    });
    expect(result).toMatchObject({
      scanned: 1,
      correct: 0,
      updated: 0,
      wouldUpdate: 1,
      skipped: 0,
      aborted: false,
    });
    expect(result.changes).toEqual([
      {
        bandId,
        name: "Driftwood",
        before: 99,
        after: 1,
        follows: 1,
        members: 0,
      },
    ]);
    expect(
      await t.run(async (ctx) => (await ctx.db.get(bandId))!.followerCount),
    ).toBe(99);
  });

  test("corrects drift and is idempotent", async () => {
    const t = convexTest(schema);
    const bandId = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert(
        "bands",
        bandFields("Second Pass", 99),
      );
      const userId = await ctx.db.insert("users", userFields(2));
      await ctx.db.insert("follows", { bandId, userId });
      return bandId;
    });

    const first = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId,
      dryRun: false,
    });
    expect(first).toMatchObject({ updated: 1, wouldUpdate: 0 });
    expect(
      await t.run(async (ctx) => (await ctx.db.get(bandId))!.followerCount),
    ).toBe(1);

    const second = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId,
      dryRun: false,
    });
    expect(second).toMatchObject({ updated: 0, correct: 1, changes: [] });
  });

  test("counts memberships and follows together", async () => {
    const t = convexTest(schema);
    const bandId = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert(
        "bands",
        bandFields("Join Arithmetic", 42),
      );
      for (let n = 10; n < 15; n++) {
        const userId = await ctx.db.insert("users", userFields(n));
        if (n < 12) {
          await ctx.db.insert("bandMembers", {
            bandId,
            userId,
            role: n === 10 ? "admin" : "member",
          });
        } else {
          await ctx.db.insert("follows", { bandId, userId });
        }
      }
      return bandId;
    });

    const result = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId,
      dryRun: false,
    });
    expect(result.updated).toBe(1);
    expect(result.changes[0]).toMatchObject({
      before: 42,
      after: 5,
      follows: 3,
      members: 2,
    });
    expect(
      await t.run(async (ctx) => (await ctx.db.get(bandId))!.followerCount),
    ).toBe(5);
  });

  test("is a no-op after createBand and toggleFollow", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "recount_admin",
      email: "recount-admin@x.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Already Canonical",
      genres: ["punk"],
      bio: "",
      inviteHandles: ["@one", "@two"],
    });
    const asFan = t.withIdentity({
      subject: "recount_fan",
      email: "recount-fan@x.com",
    });
    await asFan.mutation(api.users.ensureUser, {});
    await asFan.mutation(api.interactions.toggleFollow, { bandId });

    const result = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId,
      dryRun: false,
    });
    expect(result).toMatchObject({
      updated: 0,
      wouldUpdate: 0,
      correct: 1,
      changes: [],
    });
  });

  test("can scope a live recount to one band", async () => {
    const t = convexTest(schema);
    const { firstBandId, secondBandId } = await t.run(async (ctx) => ({
      firstBandId: await ctx.db.insert("bands", bandFields("Scoped One", 99)),
      secondBandId: await ctx.db.insert("bands", bandFields("Scoped Two", 77)),
    }));

    const result = await t.mutation(internal.maintenance.recountBandFollowers, {
      bandId: firstBandId,
      dryRun: false,
    });
    expect(result).toMatchObject({ scanned: 1, updated: 1 });
    const counts = await t.run(async (ctx) => ({
      first: (await ctx.db.get(firstBandId))!.followerCount,
      second: (await ctx.db.get(secondBandId))!.followerCount,
    }));
    expect(counts).toEqual({ first: 0, second: 77 });
  });
});

describe("maintenance:publishRealGig", () => {
  test("dry runs by default, validating without writing", async () => {
    const { t, fields } = await setupPublishFixture();
    const result = await t.mutation(
      internal.maintenance.publishRealGig,
      fields,
    );
    expect(result).toEqual({
      gigId: null,
      created: false,
      alreadyExisted: false,
      bandName: "Production Values",
      venueName: "The Real Room",
    });
    expect(
      await t.run(async (ctx) => ctx.db.query("gigs").take(10)),
    ).toHaveLength(0);
  });

  test("publishes without band-admin auth", async () => {
    const { t, bandId, fields } = await setupPublishFixture();
    const result = await t.mutation(internal.maintenance.publishRealGig, {
      ...fields,
      dryRun: false,
    });
    expect(result).toMatchObject({ created: true, alreadyExisted: false });
    const gig = await t.run(async (ctx) => ctx.db.get(result.gigId!));
    expect(gig).toMatchObject({
      lineup: [bandId],
      genres: ["post-punk"],
      desc: "",
      createdByBand: bandId,
      goingCount: 0,
      flyKey: "blueprint",
    });
  });

  test("publishes a gig reachable from gigs:feed", async () => {
    const { t, fields } = await setupPublishFixture();
    const result = await t.mutation(internal.maintenance.publishRealGig, {
      ...fields,
      startsAt: Date.now() + 86_400_000,
      dryRun: false,
    });
    const feed = await t.query(api.gigs.feed, {});
    expect(feed.gigs.some((gig) => gig._id === result.gigId)).toBe(true);
  });

  test("rejects the same invalid publish inputs with the same messages", async () => {
    const { t, fields } = await setupPublishFixture();
    const missingVenueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", {
        name: "Deleted Room",
        area: "Oakland",
        addr: "Gone",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      await ctx.db.delete(venueId);
      return venueId;
    });
    const cases = [
      {
        args: { ...fields, startsAt: -1 },
        message: "Invalid startsAt",
      },
      {
        args: { ...fields, startsAt: Number.POSITIVE_INFINITY },
        message: "Invalid startsAt",
      },
      {
        args: {
          ...fields,
          ticketing: "external" as const,
          externalUrl: "ftp://tickets.example.com",
        },
        message: "External ticketing requires a valid http(s) URL",
      },
      {
        args: { ...fields, flyKey: "custom" as const },
        message: "Custom flyer requires flyStorageId",
      },
      {
        args: { ...fields, venueId: missingVenueId },
        message: "Venue not found",
      },
    ];

    for (const invalid of cases) {
      await expect(
        t.mutation(internal.maintenance.publishRealGig, invalid.args),
      ).rejects.toThrow(invalid.message);
    }
  });

  test("returns the existing gig when identical details are re-run", async () => {
    const { t, fields } = await setupPublishFixture();
    const args = { ...fields, dryRun: false };
    const first = await t.mutation(internal.maintenance.publishRealGig, args);
    const second = await t.mutation(internal.maintenance.publishRealGig, args);

    expect(first).toMatchObject({ created: true, alreadyExisted: false });
    expect(second).toMatchObject({
      gigId: first.gigId,
      created: false,
      alreadyExisted: true,
    });
    expect(
      await t.run(async (ctx) =>
        ctx.db
          .query("gigs")
          .withIndex("by_title", (q) => q.eq("title", fields.title))
          .take(20),
      ),
    ).toHaveLength(1);
  });
});

describe("maintenance:backfillGigBands", () => {
  const DAY_MS = 24 * 60 * 60 * 1000;

  /** A band and two past gigs written straight into the table, the way the
   * legacy migration wrote production's 14 — no `gigBands` rows anywhere. */
  async function setupUnindexedHistory() {
    const t = convexTest(schema);
    const { bandId, otherBandId } = await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", bandFields("Unindexed", 0));
      const otherBandId = await ctx.db.insert(
        "bands",
        bandFields("Co-headliner", 0),
      );
      const venueId = await ctx.db.insert("venues", {
        name: "The Real Room",
        area: "Mission, SF",
        addr: "123 Valencia St",
        distSF: "0.5 mi",
        distOak: "7.0 mi",
        lat: 37.76,
        lng: -122.42,
      });
      const base = {
        venueId,
        price: 0,
        doorsTime: "8PM / 9PM",
        flyKey: "paper",
        genres: ["noise"],
        desc: "",
        ticketing: "rsvp" as const,
        cap: "No cap",
        goingCount: 0,
      };
      await ctx.db.insert("gigs", {
        ...base,
        title: "Legacy Solo Show",
        startsAt: Date.now() - 30 * DAY_MS,
        lineup: [bandId],
      });
      await ctx.db.insert("gigs", {
        ...base,
        title: "Legacy Split Bill",
        startsAt: Date.now() - 20 * DAY_MS,
        lineup: [bandId, otherBandId],
      });
      return { bandId, otherBandId };
    });
    return { t, bandId, otherBandId };
  }

  test("dry run by default: reports the gap and writes nothing", async () => {
    const { t, bandId } = await setupUnindexedHistory();

    expect(await t.mutation(internal.maintenance.backfillGigBands, {})).toEqual(
      {
        gigsScanned: 2,
        pairsExisting: 0,
        pairsMissing: 3,
        rowsCreated: 0,
        done: true,
      },
    );
    const { gigs } = await t.query(api.gigs.pastForBand, { bandId });
    expect(gigs).toHaveLength(0);
  });

  test("makes migrated gigs reachable from the band's own history", async () => {
    const { t, bandId, otherBandId } = await setupUnindexedHistory();

    const report = await t.mutation(internal.maintenance.backfillGigBands, {
      dryRun: false,
    });
    expect(report).toMatchObject({ pairsMissing: 3, rowsCreated: 3 });

    const mine = await t.query(api.gigs.pastForBand, { bandId });
    expect(mine.gigs.map((gig) => gig.title)).toEqual([
      "Legacy Split Bill",
      "Legacy Solo Show",
    ]);
    // One row per lineup band, so a co-headliner gets the split bill too.
    const theirs = await t.query(api.gigs.pastForBand, {
      bandId: otherBandId,
    });
    expect(theirs.gigs.map((gig) => gig.title)).toEqual(["Legacy Split Bill"]);
  });

  test("is idempotent — a second run creates nothing", async () => {
    const { t } = await setupUnindexedHistory();
    await t.mutation(internal.maintenance.backfillGigBands, { dryRun: false });

    expect(
      await t.mutation(internal.maintenance.backfillGigBands, {
        dryRun: false,
      }),
    ).toEqual({
      gigsScanned: 2,
      pairsExisting: 3,
      pairsMissing: 0,
      rowsCreated: 0,
      done: true,
    });
  });

  test("leaves gigs published through the normal path alone", async () => {
    const { t, fields } = await setupPublishFixture();
    await t.mutation(internal.maintenance.publishRealGig, {
      ...fields,
      dryRun: false,
    });

    expect(
      await t.mutation(internal.maintenance.backfillGigBands, {}),
    ).toMatchObject({ pairsExisting: 1, pairsMissing: 0 });
  });
});
