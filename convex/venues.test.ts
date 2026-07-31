import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

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
    expect(venues.map((v) => v.name)).toEqual(["Kingman Hall", "Oakland Secret"]);
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
