import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

function bandFields(name: string) {
  return {
    name,
    slug: name.toLowerCase().replace(/\s+/g, "-"),
    genres: ["punk"],
    area: "Bay Area",
    colorHex: "#7B8FFF",
    initials: name.slice(0, 2).toUpperCase(),
    followerCount: 0,
    bio: "",
    pastShows: [],
  };
}

function venueFields(name: string) {
  return {
    name,
    area: "Oakland",
    addr: "1 Test Way",
    distSF: "7 mi",
    distOak: "1 mi",
    lat: 37.8,
    lng: -122.27,
  };
}

function gigFields(startsAt: number) {
  return {
    price: 0,
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

describe("venues:list", () => {
  async function seedVenues() {
    const t = convexTest(schema);
    const venueIds = await t.run(async (ctx) => [
      await ctx.db.insert("venues", {
        name: "Oakland Secret",
        area: "Oakland",
        addr: "1618 Telegraph Ave",
        distSF: "11.4 mi",
        distOak: "0.3 mi",
        lat: 37.8058,
        lng: -122.2705,
      }),
      await ctx.db.insert("venues", {
        name: "Kingman Hall",
        area: "Berkeley",
        addr: "1730 La Loma Ave",
        distSF: "12.1 mi",
        distOak: "5.4 mi",
        lat: 37.8792,
        lng: -122.2611,
      }),
    ]);
    return { t, venueIds };
  }

  test("returns every venue, name-ordered", async () => {
    const { t } = await seedVenues();
    const venues = await t.query(api.venues.list, {});
    expect(venues.map((v) => v.name)).toEqual([
      "Kingman Hall",
      "Oakland Secret",
    ]);
  });

  test("includes venues no gig references — the gap that made them unreadable", async () => {
    const { t } = await seedVenues();
    const orphanId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "2863 Derby St",
        area: "Berkeley",
        addr: "2863 Derby St",
        distSF: "13.0 mi",
        distOak: "6.1 mi",
        lat: 37.8598,
        lng: -122.2503,
      }),
    );

    // No gigs exist at all, so the feed carries no venues.
    const feed = await t.query(api.gigs.feed, {});
    expect(feed.venues).toEqual([]);

    const venues = await t.query(api.venues.list, {});
    expect(venues.some((v) => v._id === orphanId)).toBe(true);
    expect(venues.length).toBe(3);
  });

  test("is public — an anonymous visitor can read the venue list", async () => {
    const { t } = await seedVenues();
    expect((await t.query(api.venues.list, {})).length).toBe(2);
  });

  test("returns an empty array when there are no venues", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.venues.list, {})).toEqual([]);
  });
});

describe("venues:detail", () => {
  test("isolates the venue, orders gigs, and deduplicates lineup bands", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    const { venueId, firstBandId, secondBandId } = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Test Room"));
      const otherVenueId = await ctx.db.insert(
        "venues",
        venueFields("Other Room"),
      );
      const firstBandId = await ctx.db.insert(
        "bands",
        bandFields("Alpha Band"),
      );
      const secondBandId = await ctx.db.insert(
        "bands",
        bandFields("Beta Band"),
      );
      await ctx.db.insert("gigs", {
        ...gigFields(now + 2_000),
        title: "Second",
        venueId,
        lineup: [firstBandId, firstBandId, secondBandId],
      });
      // Deliberately omit the stored age to model a row from before v1.10.
      const { ageRequirement: _legacyAge, ...legacyGig } = gigFields(
        now + 1_000,
      );
      await ctx.db.insert("gigs", {
        ...legacyGig,
        title: "First",
        venueId,
        lineup: [secondBandId],
      });
      await ctx.db.insert("gigs", {
        ...gigFields(now + 500),
        title: "Wrong Venue",
        venueId: otherVenueId,
        lineup: [firstBandId],
      });
      return { venueId, firstBandId, secondBandId };
    });

    const detail = await t.query(api.venues.detail, { venueId });
    expect(detail?.venue._id).toBe(venueId);
    expect(detail?.gigs.map((gig) => gig.title)).toEqual(["First", "Second"]);
    expect(detail?.gigs[0].ageRequirement).toBe("allAges");
    expect(detail?.bands.map((band) => band._id)).toEqual([
      secondBandId,
      firstBandId,
    ]);
    expect(detail?.truncated).toBe(false);
  });

  test("returns null for a missing venue", async () => {
    const t = convexTest(schema);
    const missingVenueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Gone Room"));
      await ctx.db.delete(venueId);
      return venueId;
    });

    expect(
      await t.query(api.venues.detail, { venueId: missingVenueId }),
    ).toBeNull();
  });

  test("returns the next 200 venue gigs and reports truncation", async () => {
    const t = convexTest(schema);
    const firstStartsAt = Date.now() + 86_400_000;
    const venueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Big Room"));
      for (let index = 0; index < 201; index++) {
        await ctx.db.insert("gigs", {
          ...gigFields(firstStartsAt + index * 60_000),
          title: `Gig ${index}`,
          venueId,
          lineup: [],
        });
      }
      return venueId;
    });

    const detail = await t.query(api.venues.detail, { venueId });
    expect(detail?.gigs).toHaveLength(200);
    expect(detail?.gigs[0].title).toBe("Gig 0");
    expect(detail?.gigs[199].title).toBe("Gig 199");
    expect(detail?.bands).toEqual([]);
    expect(detail?.truncated).toBe(true);
  });
});
