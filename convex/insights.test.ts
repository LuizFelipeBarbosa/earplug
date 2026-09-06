import { describe, it, expect } from "vitest";
import { K_ANON_FANS } from "./lib/helpers";
import {
  attributionCounts,
  bucketize,
  classifyAttribution,
  estimatedDraw,
  percentile,
  priceBand,
  returningAttendees,
  suppressPartition,
  weekdayKey,
  type Bucket,
} from "./lib/insights";

describe("percentile", () => {
  it.each([0, 0.25, 0.5, 0.75, 1])(
    "returns zero for no values at p=%s",
    (p) => {
      expect(percentile([], p)).toBe(0);
    },
  );

  it.each([0, 0.25, 0.5, 0.75, 1])("returns a single value at p=%s", (p) => {
    expect(percentile([12], p)).toBe(12);
  });

  it.each([
    { p: 0, expected: 10 },
    { p: 0.25, expected: 12.5 },
    { p: 0.5, expected: 15 },
    { p: 0.75, expected: 17.5 },
    { p: 1, expected: 20 },
  ])("interpolates two values at p=$p", ({ p, expected }) => {
    expect(percentile([20, 10], p)).toBe(expected);
  });

  it("interpolates fractional ranks without reordering the input", () => {
    const values = [30, 0, 10, 20];
    expect(percentile(values, 0.25)).toBe(7.5);
    expect(percentile(values, 0.6)).toBeCloseTo(18);
    expect(values).toEqual([30, 0, 10, 20]);
  });

  it("sorts numerically and matches odd and even medians", () => {
    expect(percentile([100, 2, 10], 0.5)).toBe(10);
    expect(percentile([100, 2, 20, 10], 0.5)).toBe(15);
  });

  it("handles repeated values and fractional input values", () => {
    expect(percentile([4, 4, 4], 0.7)).toBe(4);
    expect(percentile([0.5, 1.5, 2.5], 0.25)).toBe(1);
  });
});

describe("estimatedDraw", () => {
  it("returns null without events", () => {
    expect(estimatedDraw([])).toBeNull();
  });

  it("has low confidence for a single event", () => {
    expect(estimatedDraw([9])).toEqual({
      low: 9,
      high: 9,
      confidence: "low",
      events: 1,
    });
  });

  it("rounds outward for two events and preserves their order", () => {
    const counts = [9, 2];
    expect(estimatedDraw(counts)).toEqual({
      low: 3,
      high: 8,
      confidence: "low",
      events: 2,
    });
    expect(counts).toEqual([9, 2]);
  });

  it("reaches medium confidence at exactly three events", () => {
    expect(estimatedDraw([0, 5, 10])).toEqual({
      low: 2,
      high: 8,
      confidence: "medium",
      events: 3,
    });
  });

  it("keeps medium confidence through seven events", () => {
    expect(estimatedDraw([1, 2, 3, 4, 5, 6, 7])).toEqual({
      low: 2,
      high: 6,
      confidence: "medium",
      events: 7,
    });
  });

  it("reaches high confidence at exactly eight events", () => {
    expect(estimatedDraw([1, 2, 3, 4, 5, 6, 7, 8])).toEqual({
      low: 2,
      high: 7,
      confidence: "high",
      events: 8,
    });
  });

  it("keeps high confidence above eight events", () => {
    expect(estimatedDraw([0, 1, 2, 3, 4, 5, 6, 7, 8])).toEqual({
      low: 2,
      high: 6,
      confidence: "high",
      events: 9,
    });
  });

  it.each([
    { counts: [0], low: 0, high: 0 },
    { counts: [0, 0, 0], low: 0, high: 0 },
    { counts: [7, 7, 7], low: 7, high: 7 },
    { counts: [20, 0, 1, 1], low: 0, high: 6 },
  ])(
    "keeps integer bounds with high >= low for $counts",
    ({ counts, low, high }) => {
      const draw = estimatedDraw(counts)!;
      expect(draw.low).toBe(low);
      expect(draw.high).toBe(high);
      expect(draw.high).toBeGreaterThanOrEqual(draw.low);
      expect(Number.isInteger(draw.low)).toBe(true);
      expect(Number.isInteger(draw.high)).toBe(true);
    },
  );
});

describe("priceBand", () => {
  it.each(["rsvp", "external"] as const)(
    "treats %s ticketing as free",
    (ticketing) => {
      for (const price of [undefined, 0, 1, 1499, 1500, 3000, 3001, 5000]) {
        expect(priceBand(price, ticketing)).toBe("free");
      }
    },
  );

  it.each([
    { price: undefined, expected: "free" },
    { price: 0, expected: "free" },
    { price: 1, expected: "under15" },
    { price: 1499, expected: "under15" },
    { price: 1500, expected: "from15to30" },
    { price: 1501, expected: "from15to30" },
    { price: 2999, expected: "from15to30" },
    { price: 3000, expected: "from15to30" },
    { price: 3001, expected: "over30" },
  ])("classifies paid price $price as $expected", ({ price, expected }) => {
    expect(priceBand(price, "paid")).toBe(expected);
  });
});

describe("bucketize", () => {
  it("returns no buckets for no rows", () => {
    expect(
      bucketize<Bucket>(
        [],
        (row) => row.key,
        (row) => row.checkIns,
      ),
    ).toEqual([]);
  });

  it("accumulates events and check-ins by key, including zero-check-in events", () => {
    const rows = [
      { venue: "Oakland", attendees: 3 },
      { venue: "SF", attendees: 9 },
      { venue: "Oakland", attendees: 4 },
      { venue: "Oakland", attendees: 0 },
    ];
    const original = rows.map((row) => ({ ...row }));
    expect(
      bucketize(
        rows,
        (row) => row.venue,
        (row) => row.attendees,
      ),
    ).toEqual([
      { key: "SF", events: 1, checkIns: 9 },
      { key: "Oakland", events: 3, checkIns: 7 },
    ]);
    expect(rows).toEqual(original);
  });

  it("breaks check-in ties by ascending string comparison", () => {
    const rows = ["b", "a", "Z", "A"];
    expect(
      bucketize(
        rows,
        (key) => key,
        () => 5,
      ),
    ).toEqual([
      { key: "A", events: 1, checkIns: 5 },
      { key: "Z", events: 1, checkIns: 5 },
      { key: "a", events: 1, checkIns: 5 },
      { key: "b", events: 1, checkIns: 5 },
    ]);
  });

  it("handles empty and object-prototype names as ordinary keys", () => {
    expect(
      bucketize(
        ["__proto__", "", "constructor", "__proto__"],
        (key) => key,
        () => 1,
      ),
    ).toEqual([
      { key: "__proto__", events: 2, checkIns: 2 },
      { key: "", events: 1, checkIns: 1 },
      { key: "constructor", events: 1, checkIns: 1 },
    ]);
  });
});

describe("suppressPartition", () => {
  it.each([
    { name: "empty", counts: [] },
    { name: "all zero", counts: [0, 0] },
    { name: "all below floor", counts: [1, K_ANON_FANS - 1] },
    {
      name: "mixed below and above floor",
      counts: [K_ANON_FANS - 1, K_ANON_FANS + 1],
    },
  ])("suppresses an $name partition without changing input", ({ counts }) => {
    const buckets = counts.map((checkIns, index) => ({
      key: String(index),
      events: 1,
      checkIns,
    }));
    const original = buckets.map((bucket) => ({ ...bucket }));
    expect(suppressPartition(buckets)).toEqual({
      buckets: [],
      suppressed: true,
    });
    expect(buckets).toEqual(original);
  });

  it("publishes exactly the floor and returns the same array and bucket", () => {
    const bucket = { key: "Mon", events: 1, checkIns: K_ANON_FANS };
    const buckets = [bucket];
    const result = suppressPartition(buckets);
    expect(result).toEqual({ buckets, suppressed: false });
    expect(result.buckets).toBe(buckets);
    expect(result.buckets[0]).toBe(bucket);
  });

  it("publishes safe zero buckets alongside counts at or above the floor", () => {
    const buckets = [
      { key: "empty", events: 3, checkIns: 0 },
      { key: "at floor", events: 1, checkIns: K_ANON_FANS },
      { key: "above floor", events: 2, checkIns: K_ANON_FANS + 1 },
    ];
    const original = buckets.map((bucket) => ({ ...bucket }));
    const result = suppressPartition(buckets);
    expect(result).toEqual({ buckets, suppressed: false });
    expect(result.buckets).toBe(buckets);
    expect(buckets).toEqual(original);
  });

  it("uses a custom floor", () => {
    const buckets = [{ key: "Mon", events: 10, checkIns: 3 }];
    expect(suppressPartition(buckets, 3)).toEqual({
      buckets,
      suppressed: false,
    });
    expect(suppressPartition(buckets, 4)).toEqual({
      buckets: [],
      suppressed: true,
    });
  });

  it("still suppresses entirely empty data with a zero floor", () => {
    expect(
      suppressPartition([{ key: "Mon", events: 1, checkIns: 0 }], 0),
    ).toEqual({
      buckets: [],
      suppressed: true,
    });
  });
});

describe("classifyAttribution", () => {
  const bandId = "band";
  const followers: ReadonlySet<string> = new Set(["fan"]);

  it("gives a matching referral priority over following", () => {
    expect(
      classifyAttribution(
        { referralBandId: bandId, buyerUserId: "fan" },
        bandId,
        followers,
      ),
    ).toBe("referral");
  });

  it("recognizes referrals from buyers who do not follow", () => {
    expect(
      classifyAttribution(
        { referralBandId: bandId, buyerUserId: "guest" },
        bandId,
        followers,
      ),
    ).toBe("referral");
  });

  it.each([undefined, "other-band"])(
    "recognizes a follower with referral %s",
    (referralBandId) => {
      expect(
        classifyAttribution(
          { referralBandId, buyerUserId: "fan" },
          bandId,
          followers,
        ),
      ).toBe("follow");
    },
  );

  it.each([undefined, "other-band"])(
    "leaves a non-follower with referral %s unattributed",
    (referralBandId) => {
      expect(
        classifyAttribution(
          { referralBandId, buyerUserId: "guest" },
          bandId,
          followers,
        ),
      ).toBe("unattributed");
    },
  );
});

describe("attributionCounts", () => {
  const bandId = "band";
  const suppressed = {
    referral: 0,
    follow: 0,
    unattributed: 0,
    suppressed: true,
  };

  it("suppresses empty orders", () => {
    expect(attributionCounts([], bandId, new Set())).toEqual(suppressed);
  });

  it("suppresses fewer than K distinct buyers even with large quantities", () => {
    const orders = Array.from({ length: K_ANON_FANS - 1 }, (_, index) => ({
      buyerUserId: `buyer-${index}`,
      quantity: 100,
    }));
    expect(attributionCounts(orders, bandId, new Set())).toEqual(suppressed);
  });

  it("does not count repeated orders as distinct buyers", () => {
    const orders = Array.from({ length: K_ANON_FANS }, () => ({
      referralBandId: bandId,
      buyerUserId: "buyer",
      quantity: 10,
    }));
    expect(attributionCounts(orders, bandId, new Set(["buyer"]))).toEqual(
      suppressed,
    );
  });

  it.each(["referral", "follow", "unattributed"] as const)(
    "publishes exactly K buyers in %s with the other classes empty",
    (attribution) => {
      const buyerIds = Array.from(
        { length: K_ANON_FANS },
        (_, index) => `buyer-${index}`,
      );
      const orders = buyerIds.map((buyerUserId) => ({
        buyerUserId,
        quantity: 1,
        referralBandId: attribution === "referral" ? bandId : undefined,
      }));
      const followers = new Set(attribution === "unattributed" ? [] : buyerIds);
      expect(attributionCounts(orders, bandId, followers)).toEqual({
        referral: 0,
        follow: 0,
        unattributed: 0,
        [attribution]: K_ANON_FANS,
        suppressed: false,
      });
    },
  );

  it("suppresses the whole partition when one class is below the buyer floor", () => {
    const orders = [
      ...Array.from({ length: K_ANON_FANS }, (_, index) => ({
        referralBandId: bandId,
        buyerUserId: `referral-${index}`,
        quantity: 2,
      })),
      { buyerUserId: "guest", quantity: 100 },
    ];
    expect(attributionCounts(orders, bandId, new Set())).toEqual(suppressed);
  });

  it("sums quantities, including repeat orders, across all three valid classes", () => {
    const referralOrders = Array.from({ length: K_ANON_FANS }, (_, index) => ({
      referralBandId: bandId,
      buyerUserId: `referral-${index}`,
      quantity: 2,
    }));
    const followOrders = Array.from({ length: K_ANON_FANS }, (_, index) => ({
      referralBandId: "other-band",
      buyerUserId: `follow-${index}`,
      quantity: 3,
    }));
    const guestOrders = Array.from({ length: K_ANON_FANS }, (_, index) => ({
      buyerUserId: `guest-${index}`,
      quantity: 4,
    }));
    const followers = new Set(
      [...referralOrders, ...followOrders].map((order) => order.buyerUserId),
    );
    const orders = [
      ...referralOrders,
      ...followOrders,
      ...guestOrders,
      { ...referralOrders[0], quantity: 7 },
      { ...followOrders[0], quantity: 8 },
      { ...guestOrders[0], quantity: 9 },
    ];
    const original = orders.map((order) => ({ ...order }));
    const originalFollowers = new Set(followers);

    expect(attributionCounts(orders, bandId, followers)).toEqual({
      referral: K_ANON_FANS * 2 + 7,
      follow: K_ANON_FANS * 3 + 8,
      unattributed: K_ANON_FANS * 4 + 9,
      suppressed: false,
    });
    expect(orders).toEqual(original);
    expect(followers).toEqual(originalFollowers);
  });

  it("counts a buyer independently in every class where they placed orders", () => {
    const buyerIds = Array.from(
      { length: K_ANON_FANS },
      (_, index) => `buyer-${index}`,
    );
    const orders = buyerIds.flatMap((buyerUserId) => [
      { referralBandId: bandId, buyerUserId, quantity: 2 },
      { buyerUserId, quantity: 3 },
    ]);
    expect(attributionCounts(orders, bandId, new Set(buyerIds))).toEqual({
      referral: K_ANON_FANS * 2,
      follow: K_ANON_FANS * 3,
      unattributed: 0,
      suppressed: false,
    });
  });
});

describe("returningAttendees", () => {
  it("returns zero for no events or only empty events", () => {
    expect(returningAttendees([])).toBe(0);
    expect(returningAttendees([new Set(), new Set()])).toBe(0);
  });

  it("does not count users who attended only one event", () => {
    expect(returningAttendees([new Set(["a", "b"]), new Set(["c"])])).toBe(0);
  });

  it("counts a user who attended exactly two events", () => {
    expect(returningAttendees([new Set(["a", "b"]), new Set(["a", "c"])])).toBe(
      1,
    );
  });

  it("counts each returning user once across two or more events", () => {
    const events: Array<ReadonlySet<string>> = [
      new Set(["a", "b", "once"]),
      new Set(["a"]),
      new Set(),
      new Set(["a", "b"]),
    ];
    const original = events.map((event) => new Set(event));
    expect(returningAttendees(events)).toBe(2);
    expect(events).toEqual(original);
  });

  it("does not count duplicate check-ins within one event as returning", () => {
    expect(returningAttendees([new Set(["a", "a"])])).toBe(0);
  });
});

describe("weekdayKey", () => {
  it.each([
    { timestamp: "2026-01-05T07:59:59Z", expected: "Sun" },
    { timestamp: "2026-01-05T08:00:00Z", expected: "Mon" },
    { timestamp: "2026-07-06T06:59:59Z", expected: "Sun" },
    { timestamp: "2026-07-06T07:00:00Z", expected: "Mon" },
    { timestamp: "2026-07-07T12:00:00Z", expected: "Tue" },
    { timestamp: "2026-07-08T12:00:00Z", expected: "Wed" },
    { timestamp: "2026-07-09T12:00:00Z", expected: "Thu" },
    { timestamp: "2026-07-10T12:00:00Z", expected: "Fri" },
    { timestamp: "2026-07-11T12:00:00Z", expected: "Sat" },
    { timestamp: "2026-03-08T09:59:59Z", expected: "Sun" },
    { timestamp: "2026-03-08T10:00:00Z", expected: "Sun" },
    { timestamp: "2026-11-01T08:59:59Z", expected: "Sun" },
    { timestamp: "2026-11-01T09:00:00Z", expected: "Sun" },
  ])(
    "uses Pacific weekday $expected at $timestamp",
    ({ timestamp, expected }) => {
      expect(weekdayKey(Date.parse(timestamp))).toBe(expected);
    },
  );
});
