import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { query } from "./_generated/server";
import {
  K_ANON_FANS,
  MAX_RECAP_GIGS,
  MAX_RSVPS_PER_GIG,
  pastGigsForBand,
  requireBandRole,
} from "./lib/helpers";

const leadTimeKeyValidator = v.union(
  v.literal("twoWeeksPlus"),
  v.literal("oneToTwoWeeks"),
  v.literal("underWeek"),
  v.literal("dayOf"),
);

const repeatFanKeyValidator = v.union(
  v.literal("one"),
  v.literal("twoToThree"),
  v.literal("fourPlus"),
);

const bandRecapValidator = v.object({
  window: v.object({
    showsAnalyzed: v.number(),
    scanned: v.number(),
    truncated: v.boolean(),
    firstStartsAt: v.union(v.number(), v.null()),
    lastStartsAt: v.union(v.number(), v.null()),
  }),
  totals: v.object({
    shows: v.number(),
    reportedRsvps: v.number(),
    measuredRsvps: v.number(),
    avgPerShow: v.number(),
    bestShowRsvps: v.number(),
    distinctFans: v.number(),
    followerCount: v.number(),
  }),
  shows: v.array(
    v.object({
      gigId: v.id("gigs"),
      title: v.string(),
      startsAt: v.number(),
      venueName: v.string(),
      price: v.number(),
      ticketing: v.union(v.literal("rsvp"), v.literal("external")),
      goingCount: v.number(),
      measuredRsvps: v.number(),
      newFans: v.union(v.number(), v.null()),
      returningFans: v.union(v.number(), v.null()),
    }),
  ),
  newReturning: v.object({ suppressed: v.boolean() }),
  leadTime: v.object({
    buckets: v.array(
      v.object({ key: leadTimeKeyValidator, count: v.number() }),
    ),
    medianDays: v.union(v.number(), v.null()),
    unmeasurable: v.number(),
    suppressed: v.boolean(),
  }),
  venues: v.object({
    rows: v.array(
      v.object({
        venueName: v.string(),
        shows: v.number(),
        totalRsvps: v.number(),
        avgRsvps: v.number(),
      }),
    ),
    suppressed: v.boolean(),
  }),
  weekdays: v.object({
    rows: v.array(
      v.object({
        weekday: v.number(),
        shows: v.number(),
        avgRsvps: v.number(),
      }),
    ),
    suppressed: v.boolean(),
  }),
  repeatFans: v.object({
    tiers: v.array(v.object({ key: repeatFanKeyValidator, count: v.number() })),
    suppressed: v.boolean(),
  }),
  pricing: v.object({
    freeShows: v.number(),
    freeAvgRsvps: v.number(),
    paidShows: v.number(),
    paidAvgRsvps: v.number(),
    suppressed: v.boolean(),
  }),
});

export type BandRecap = Infer<typeof bandRecapValidator>;

type FanHistoryInput = {
  gigId: Id<"gigs">;
  startsAt: number;
  fanIds: Id<"users">[];
};

/** Computes the chronological fan walk before privacy suppression is applied.
 * This is exported as ordinary TypeScript, not a Convex function, so focused
 * tests can verify the oldest-first classification that the wire contract may
 * intentionally hide. Duplicate rows for one fan at one gig count once. */
export function computeFanHistory(shows: FanHistoryInput[]) {
  const seenAtEarlierShows = new Set<Id<"users">>();
  const showCountByFan = new Map<Id<"users">, number>();
  const splitByGig = new Map<
    Id<"gigs">,
    {
      newFanIds: Set<Id<"users">>;
      returningFanIds: Set<Id<"users">>;
    }
  >();

  const oldestFirst = [...shows].sort((a, b) => a.startsAt - b.startsAt);
  for (const show of oldestFirst) {
    const newFanIds = new Set<Id<"users">>();
    const returningFanIds = new Set<Id<"users">>();
    const fanIds = new Set(show.fanIds);

    for (const fanId of fanIds) {
      if (seenAtEarlierShows.has(fanId)) returningFanIds.add(fanId);
      else newFanIds.add(fanId);
      showCountByFan.set(fanId, (showCountByFan.get(fanId) ?? 0) + 1);
    }
    splitByGig.set(show.gigId, { newFanIds, returningFanIds });
    for (const fanId of fanIds) seenAtEarlierShows.add(fanId);
  }

  return { splitByGig, showCountByFan };
}

type AnalyzedShow = {
  gig: Doc<"gigs">;
  venueName: string;
  rsvps: Doc<"gigRsvps">[];
  fanIds: Set<Id<"users">>;
};

type AggregateRow = {
  shows: number;
  totalRsvps: number;
  fanIds: Set<Id<"users">>;
};

const DAY_MS = 24 * 60 * 60 * 1000;
const LEAD_TIME_KEYS = [
  "twoWeeksPlus",
  "oneToTwoWeeks",
  "underWeek",
  "dayOf",
] as const;

/** Empty buckets identify nobody and are safe to publish; only buckets with
 * 1..K-1 distinct fans create a re-identification risk. Do not simplify this
 * to "every bucket >= K": that would suppress ordinary partitions containing
 * a safe zero. An entirely empty partition still has no data to publish. */
function partitionMeetsFloor(fanSets: Array<Set<Id<"users">>>): boolean {
  return (
    fanSets.some((fanIds) => fanIds.size > 0) &&
    fanSets.every((fanIds) => fanIds.size === 0 || fanIds.size >= K_ANON_FANS)
  );
}

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

const PACIFIC_WEEKDAY_FORMATTER = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Los_Angeles",
  weekday: "short",
});

/** Uses the Bay Area show's calendar day rather than its UTC day so recap rows
 * match the date fans saw locally. Intl applies both PST and PDT transitions. */
function pacificWeekday(startsAt: number): number {
  const weekday = PACIFIC_WEEKDAY_FORMATTER.format(new Date(startsAt));
  const isoWeekdays: Record<string, number> = {
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
    Sun: 7,
  };
  return isoWeekdays[weekday];
}

/** Band-private recap of the band's past gigs, newest first.
 *
 * Read through `gigBands.by_band_startsAt`, so the window covers this band's
 * own history and `window.truncated` means exactly one thing: the band has
 * played more than MAX_RECAP_GIGS past shows. It is no longer possible for a
 * band's older shows to fall out of the recap because other bands published
 * gigs in the meantime. Asking the index for one row beyond the cap is what
 * makes the flag exact rather than inferred.
 *
 * Lead time uses RSVP row creation time only when it predates the gig. Migrated
 * past gigs commonly have rows created after startsAt; those rows are reported
 * as unmeasurable instead of being mislabeled as day-of intent. */
export const bandRecap = query({
  args: { bandId: v.id("bands") },
  returns: bandRecapValidator,
  handler: async (ctx, args) => {
    const { band } = await requireBandRole(ctx, args.bandId, {
      role: "member",
    });
    const probed = await pastGigsForBand(ctx, args.bandId, MAX_RECAP_GIGS + 1);
    const truncated = probed.length > MAX_RECAP_GIGS;
    const analyzedGigs = probed.slice(0, MAX_RECAP_GIGS);

    const analyzed: AnalyzedShow[] = [];
    for (const gig of analyzedGigs) {
      const rsvps = await ctx.db
        .query("gigRsvps")
        .withIndex("by_gig", (q) => q.eq("gigId", gig._id))
        .take(MAX_RSVPS_PER_GIG);
      const venue = await ctx.db.get(gig.venueId);
      analyzed.push({
        gig,
        venueName: venue?.name ?? "",
        rsvps,
        fanIds: new Set(rsvps.map((rsvp) => rsvp.userId)),
      });
    }

    const fanHistory = computeFanHistory(
      analyzed.map(({ gig, rsvps }) => ({
        gigId: gig._id,
        startsAt: gig.startsAt,
        fanIds: rsvps.map((rsvp) => rsvp.userId),
      })),
    );

    const newReturningFanSets: Array<Set<Id<"users">>> = [];
    for (const show of analyzed) {
      const split = fanHistory.splitByGig.get(show.gig._id);
      if (!split) continue;
      newReturningFanSets.push(split.newFanIds, split.returningFanIds);
    }
    const newReturningSuppressed = !partitionMeetsFloor(newReturningFanSets);

    const leadBuckets: Record<
      (typeof LEAD_TIME_KEYS)[number],
      { count: number; fanIds: Set<Id<"users">> }
    > = {
      twoWeeksPlus: { count: 0, fanIds: new Set() },
      oneToTwoWeeks: { count: 0, fanIds: new Set() },
      underWeek: { count: 0, fanIds: new Set() },
      dayOf: { count: 0, fanIds: new Set() },
    };
    const positiveLeadDays: number[] = [];
    const unmeasurableFanIds = new Set<Id<"users">>();
    let unmeasurable = 0;
    for (const { gig, rsvps } of analyzed) {
      for (const rsvp of rsvps) {
        const leadDays = (gig.startsAt - rsvp._creationTime) / DAY_MS;
        if (leadDays <= 0) {
          unmeasurable++;
          unmeasurableFanIds.add(rsvp.userId);
          continue;
        }
        positiveLeadDays.push(leadDays);
        const key =
          leadDays >= 14
            ? "twoWeeksPlus"
            : leadDays >= 7
              ? "oneToTwoWeeks"
              : leadDays >= 1
                ? "underWeek"
                : "dayOf";
        leadBuckets[key].count++;
        leadBuckets[key].fanIds.add(rsvp.userId);
      }
    }
    const leadTimeSuppressed = !partitionMeetsFloor([
      ...LEAD_TIME_KEYS.map((key) => leadBuckets[key].fanIds),
      unmeasurableFanIds,
    ]);
    // Withhold this count only when its distinct fans form a re-identifying
    // small cell. Migrated production rows are above the floor and still ship.
    const publishedUnmeasurable = partitionMeetsFloor([unmeasurableFanIds])
      ? unmeasurable
      : 0;

    const venueAggregates = new Map<string, AggregateRow>();
    const weekdayAggregates = new Map<number, AggregateRow>();
    const pricingAggregates = {
      free: { shows: 0, totalRsvps: 0, fanIds: new Set<Id<"users">>() },
      paid: { shows: 0, totalRsvps: 0, fanIds: new Set<Id<"users">>() },
    };
    for (const show of analyzed) {
      const measuredRsvps = show.rsvps.length;
      const venueAggregate = venueAggregates.get(show.venueName) ?? {
        shows: 0,
        totalRsvps: 0,
        fanIds: new Set<Id<"users">>(),
      };
      venueAggregate.shows++;
      venueAggregate.totalRsvps += measuredRsvps;
      for (const fanId of show.fanIds) venueAggregate.fanIds.add(fanId);
      venueAggregates.set(show.venueName, venueAggregate);

      const weekday = pacificWeekday(show.gig.startsAt);
      const weekdayAggregate = weekdayAggregates.get(weekday) ?? {
        shows: 0,
        totalRsvps: 0,
        fanIds: new Set<Id<"users">>(),
      };
      weekdayAggregate.shows++;
      weekdayAggregate.totalRsvps += measuredRsvps;
      for (const fanId of show.fanIds) weekdayAggregate.fanIds.add(fanId);
      weekdayAggregates.set(weekday, weekdayAggregate);

      const pricingAggregate =
        show.gig.price === 0 ? pricingAggregates.free : pricingAggregates.paid;
      pricingAggregate.shows++;
      pricingAggregate.totalRsvps += measuredRsvps;
      for (const fanId of show.fanIds) pricingAggregate.fanIds.add(fanId);
    }

    const repeatFanIds = {
      one: new Set<Id<"users">>(),
      twoToThree: new Set<Id<"users">>(),
      fourPlus: new Set<Id<"users">>(),
    };
    for (const [fanId, showCount] of fanHistory.showCountByFan) {
      const key =
        showCount === 1 ? "one" : showCount <= 3 ? "twoToThree" : "fourPlus";
      repeatFanIds[key].add(fanId);
    }
    const repeatFansSuppressed = !partitionMeetsFloor([
      repeatFanIds.one,
      repeatFanIds.twoToThree,
      repeatFanIds.fourPlus,
    ]);
    const newestFirst = [...analyzed].sort(
      (a, b) => b.gig.startsAt - a.gig.startsAt,
    );
    const shows = newestFirst.map((show) => {
      const split = fanHistory.splitByGig.get(show.gig._id);
      return {
        gigId: show.gig._id,
        title: show.gig.title,
        startsAt: show.gig.startsAt,
        venueName: show.venueName,
        price: show.gig.price,
        ticketing: show.gig.ticketing,
        goingCount: show.gig.goingCount,
        measuredRsvps: show.rsvps.length,
        newFans: newReturningSuppressed || !split ? null : split.newFanIds.size,
        returningFans:
          newReturningSuppressed || !split ? null : split.returningFanIds.size,
      };
    });

    const measuredRsvps = analyzed.reduce(
      (total, show) => total + show.rsvps.length,
      0,
    );
    const reportedRsvps = analyzed.reduce(
      (total, show) => total + show.gig.goingCount,
      0,
    );
    const startsAtValues = analyzed.map((show) => show.gig.startsAt);
    const firstStartsAt =
      startsAtValues.length === 0 ? null : Math.min(...startsAtValues);
    const lastStartsAt =
      startsAtValues.length === 0 ? null : Math.max(...startsAtValues);

    return {
      window: {
        showsAnalyzed: analyzed.length,
        // Index rows read for this band, which is one more than the shows
        // analyzed exactly when the recap is truncated.
        scanned: probed.length,
        truncated,
        firstStartsAt,
        lastStartsAt,
      },
      totals: {
        shows: analyzed.length,
        reportedRsvps,
        measuredRsvps,
        avgPerShow: analyzed.length === 0 ? 0 : measuredRsvps / analyzed.length,
        bestShowRsvps: analyzed.reduce(
          (best, show) => Math.max(best, show.rsvps.length),
          0,
        ),
        distinctFans: fanHistory.showCountByFan.size,
        followerCount: band.followerCount,
      },
      shows,
      newReturning: { suppressed: newReturningSuppressed },
      leadTime: leadTimeSuppressed
        ? {
            buckets: [],
            medianDays: null,
            unmeasurable: publishedUnmeasurable,
            suppressed: true,
          }
        : {
            buckets: LEAD_TIME_KEYS.map((key) => ({
              key,
              count: leadBuckets[key].count,
            })),
            medianDays: median(positiveLeadDays),
            unmeasurable: publishedUnmeasurable,
            suppressed: false,
          },
      // Exactly recomputable from the published `shows[]` rows; per-show
      // turnout is also public through `gigs.goingCount`, so a floor adds no
      // privacy.
      venues: {
        rows: [...venueAggregates.entries()]
          .map(([venueName, row]) => ({
            venueName,
            shows: row.shows,
            totalRsvps: row.totalRsvps,
            avgRsvps: row.totalRsvps / row.shows,
          }))
          .sort(
            (a, b) =>
              b.totalRsvps - a.totalRsvps ||
              a.venueName.localeCompare(b.venueName),
          ),
        suppressed: false,
      },
      // Exactly recomputable from the published `shows[]` rows; the same
      // per-show turnout is public through `gigs.goingCount`, so suppression
      // protects nothing.
      weekdays: {
        rows: [...weekdayAggregates.entries()]
          .map(([weekday, row]) => ({
            weekday,
            shows: row.shows,
            avgRsvps: row.totalRsvps / row.shows,
          }))
          .sort((a, b) => a.weekday - b.weekday),
        suppressed: false,
      },
      repeatFans: repeatFansSuppressed
        ? { tiers: [], suppressed: true }
        : {
            tiers: [
              { key: "one" as const, count: repeatFanIds.one.size },
              {
                key: "twoToThree" as const,
                count: repeatFanIds.twoToThree.size,
              },
              { key: "fourPlus" as const, count: repeatFanIds.fourPlus.size },
            ],
            suppressed: false,
          },
      // Exactly recomputable from each published `shows[]` row's price and
      // measured turnout, so suppressing this aggregate protects nothing.
      pricing: {
        freeShows: pricingAggregates.free.shows,
        freeAvgRsvps:
          pricingAggregates.free.shows === 0
            ? 0
            : pricingAggregates.free.totalRsvps / pricingAggregates.free.shows,
        paidShows: pricingAggregates.paid.shows,
        paidAvgRsvps:
          pricingAggregates.paid.shows === 0
            ? 0
            : pricingAggregates.paid.totalRsvps / pricingAggregates.paid.shows,
        suppressed: false,
      },
    };
  },
});
