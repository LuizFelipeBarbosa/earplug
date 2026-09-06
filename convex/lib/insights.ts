import { K_ANON_FANS } from "./helpers";

/** Interpolates between sorted values at the fractional rank p * (n - 1).
 * Callers supply p in [0, 1]; sorting leaves the input array unchanged. */
export function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  if (values.length === 1) return values[0];

  const sorted = [...values].sort((a, b) => a - b);
  const rank = p * (sorted.length - 1);
  const lowerIndex = Math.floor(rank);
  const upperIndex = Math.ceil(rank);
  return (
    sorted[lowerIndex] +
    (sorted[upperIndex] - sorted[lowerIndex]) * (rank - lowerIndex)
  );
}

/** Rounds the interquartile range outward to whole attendees and keeps the
 * upper bound at least as large as the lower bound. */
export function estimatedDraw(perEventCounts: number[]): {
  low: number;
  high: number;
  confidence: "low" | "medium" | "high";
  events: number;
} | null {
  const events = perEventCounts.length;
  if (events === 0) return null;

  const low = Math.floor(percentile(perEventCounts, 0.25));
  const high = Math.max(Math.ceil(percentile(perEventCounts, 0.75)), low);
  const confidence = events < 3 ? "low" : events < 8 ? "medium" : "high";
  return { low, high, confidence, events };
}

export function priceBand(
  priceMinor: number | undefined,
  ticketing: "rsvp" | "external" | "paid",
): "free" | "under15" | "from15to30" | "over30" {
  if (ticketing !== "paid" || priceMinor === undefined || priceMinor === 0) {
    return "free";
  }

  const dollars = priceMinor / 100;
  if (dollars < 15) return "under15";
  if (dollars <= 30) return "from15to30";
  return "over30";
}

export type Bucket = { key: string; events: number; checkIns: number };

export function bucketize<T>(
  rows: T[],
  keyOf: (row: T) => string,
  checkInsOf: (row: T) => number,
): Bucket[] {
  const bucketsByKey = new Map<string, Bucket>();
  for (const row of rows) {
    const key = keyOf(row);
    const bucket = bucketsByKey.get(key) ?? { key, events: 0, checkIns: 0 };
    bucket.events += 1;
    bucket.checkIns += checkInsOf(row);
    bucketsByKey.set(key, bucket);
  }

  return [...bucketsByKey.values()].sort((a, b) => {
    if (a.checkIns !== b.checkIns) return b.checkIns - a.checkIns;
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
  });
}

/** Empty buckets identify nobody and are safe to publish; only nonzero
 * counts below the floor suppress the partition. Do not require every
 * bucket to reach the floor: that would reject safe zero buckets. An
 * entirely empty partition still has no data to publish. */
function partitionMeetsFloor(counts: number[], floor: number): boolean {
  return (
    counts.some((count) => count > 0) &&
    counts.every((count) => count === 0 || count >= floor)
  );
}

export function suppressPartition(
  buckets: Bucket[],
  floor = K_ANON_FANS,
): { buckets: Bucket[]; suppressed: boolean } {
  if (
    !partitionMeetsFloor(
      buckets.map((bucket) => bucket.checkIns),
      floor,
    )
  ) {
    return { buckets: [], suppressed: true };
  }
  return { buckets, suppressed: false };
}

type Attribution = "referral" | "follow" | "unattributed";

export function classifyAttribution(
  order: { referralBandId?: string; buyerUserId: string },
  bandId: string,
  followerIds: ReadonlySet<string>,
): Attribution {
  if (order.referralBandId === bandId) return "referral";
  if (followerIds.has(order.buyerUserId)) return "follow";
  return "unattributed";
}

/** Quantities measure tickets, but privacy depends on distinct buyers in
 * each class. Repeat orders or large quantities cannot satisfy the floor. */
export function attributionCounts(
  orders: Array<{
    referralBandId?: string;
    buyerUserId: string;
    quantity: number;
  }>,
  bandId: string,
  followerIds: ReadonlySet<string>,
): {
  referral: number;
  follow: number;
  unattributed: number;
  suppressed: boolean;
} {
  const quantities: Record<Attribution, number> = {
    referral: 0,
    follow: 0,
    unattributed: 0,
  };
  const buyers: Record<Attribution, Set<string>> = {
    referral: new Set<string>(),
    follow: new Set<string>(),
    unattributed: new Set<string>(),
  };

  for (const order of orders) {
    const attribution = classifyAttribution(order, bandId, followerIds);
    quantities[attribution] += order.quantity;
    buyers[attribution].add(order.buyerUserId);
  }

  const buyerCounts = Object.values(buyers).map((buyerIds) => buyerIds.size);
  if (!partitionMeetsFloor(buyerCounts, K_ANON_FANS)) {
    return { referral: 0, follow: 0, unattributed: 0, suppressed: true };
  }
  return { ...quantities, suppressed: false };
}

export function returningAttendees(
  checkInsByEvent: Array<ReadonlySet<string>>,
): number {
  const seen = new Set<string>();
  const returning = new Set<string>();
  for (const checkIns of checkInsByEvent) {
    for (const userId of checkIns) {
      if (seen.has(userId)) returning.add(userId);
      seen.add(userId);
    }
  }
  return returning.size;
}

const PACIFIC_WEEKDAY_FORMATTER = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Los_Angeles",
  weekday: "short",
});

/** Uses the show's Pacific calendar day, including PST/PDT transitions. */
export function weekdayKey(startsAt: number): string {
  return PACIFIC_WEEKDAY_FORMATTER.format(new Date(startsAt));
}
