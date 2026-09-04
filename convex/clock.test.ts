import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { FEED_CUTOFF_KEY, readFeedCutoff } from "./clock";
import { FEED_GRACE_MS } from "./lib/helpers";
import schema from "./schema";

afterEach(() => {
  vi.useRealTimers();
});

describe("feed cutoff clock", () => {
  test("heartbeat keeps one singleton rounded down to the minute", async () => {
    vi.useFakeTimers();
    const now = Date.UTC(2026, 8, 4, 12, 34, 12);
    vi.setSystemTime(now);
    const t = convexTest(schema);

    expect(await t.mutation(internal.clock.heartbeat, {})).toBeNull();
    const first = await t.run((ctx) => ctx.db.query("clock").unique());
    expect(first).toMatchObject({
      key: "feedCutoff",
      value: Date.UTC(2026, 8, 4, 6, 34),
    });

    vi.setSystemTime(now + 20_000);
    expect(await t.mutation(internal.clock.heartbeat, {})).toBeNull();
    const rows = await t.run((ctx) => ctx.db.query("clock").take(2));
    expect(rows).toEqual([first]);
    expect(rows[0].value % 60_000).toBe(0);
  });

  test("readFeedCutoff falls back before the first heartbeat", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(Date.UTC(2026, 8, 4, 12, 34, 12));
    const t = convexTest(schema);

    const expected = Date.now() - FEED_GRACE_MS;
    const actual = await t.run((ctx) => readFeedCutoff(ctx));
    expect(Math.abs(actual - expected)).toBeLessThan(5000);
    expect(await t.run((ctx) => ctx.db.query("clock").unique())).toBeNull();
  });

  test.each(["published", undefined] as const)(
    "a heartbeat ages a %s gig out of the feed, while time alone does not",
    async (lifecycle) => {
      vi.useFakeTimers();
      const now = Date.UTC(2026, 8, 4, 12);
      vi.setSystemTime(now);
      const t = convexTest(schema);
      const startsAt = now - 3 * 60 * 60 * 1000;
      const gigId = await t.run(async (ctx) => {
        const bandId = await ctx.db.insert("bands", {
          name: "Clock Band",
          slug: "clock-band",
          genres: ["punk"],
          area: "Oakland",
          colorHex: "#7B8FFF",
          initials: "CB",
          followerCount: 0,
          pastShows: [],
        });
        const venueId = await ctx.db.insert("venues", {
          name: "Clock Hall",
          area: "Oakland",
          addr: "1 Clock Way",
          distSF: "7 mi",
          distOak: "1 mi",
          lat: 37.8,
          lng: -122.27,
        });
        return ctx.db.insert("gigs", {
          title: "Still Playing",
          venueId,
          price: 0,
          startsAt,
          doorsTime: "8AM / 9AM",
          flyKey: "paper",
          lineup: [bandId],
          genres: ["punk"],
          desc: "",
          ticketing: "rsvp",
          cap: "No cap",
          goingCount: 0,
          createdByBand: bandId,
          lifecycle,
        });
      });

      await t.mutation(internal.clock.heartbeat, {});
      const initial = await t.query(api.gigs.feedV2, {});
      expect(initial.gigs.map((gig) => gig._id)).toEqual([gigId]);

      vi.setSystemTime(startsAt + FEED_GRACE_MS + 60_000);
      expect(await t.query(api.gigs.feedV2, {})).toEqual(initial);

      await t.mutation(internal.clock.heartbeat, {});
      expect((await t.query(api.gigs.feedV2, {})).gigs).toEqual([]);
      const row = await t.run((ctx) =>
        ctx.db
          .query("clock")
          .withIndex("by_key", (q) => q.eq("key", FEED_CUTOFF_KEY))
          .unique(),
      );
      expect(row?.value).toBe(startsAt + 60_000);
    },
  );
});
