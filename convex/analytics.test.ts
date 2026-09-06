import { makeFunctionReference } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { BandRecap, computeFanHistory } from "./analytics";
import { MAX_RECAP_GIGS, insertGigWithBandIndex } from "./lib/helpers";
import schema from "./schema";

const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const FIXTURE_START = Date.UTC(2020, 0, 1);
const NOW = Date.UTC(2026, 7, 5, 12);

const bandRecap = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  BandRecap
>("analytics:bandRecap");

afterEach(() => {
  vi.useRealTimers();
});

test("edge runtime formats Pacific weekdays across UTC day boundaries", () => {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    weekday: "short",
  });

  expect(formatter.format(new Date(Date.UTC(2026, 7, 8, 4)))).toBe("Fri");
  expect(formatter.format(new Date(Date.UTC(2026, 7, 10, 4)))).toBe("Sun");
});

async function setupMemberBand(followerCount = 37) {
  vi.useFakeTimers();
  vi.setSystemTime(FIXTURE_START);
  const t = convexTest(schema);
  const asMember = t.withIdentity({
    subject: "user_member",
    email: "member@example.com",
  });
  const { userId } = await asMember.mutation(api.users.ensureUser, {});
  const { bandId, venueId } = await t.run(async (ctx) => {
    const bandId = await ctx.db.insert("bands", {
      name: "Private Signals",
      slug: "private-signals",
      genres: ["noise"],
      area: "Bay Area",
      colorHex: "#7B8FFF",
      initials: "PS",
      followerCount,
      bio: "",
      pastShows: [],
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId,
      role: "member",
    });
    const venueId = await ctx.db.insert("venues", {
      name: "The Recap Room",
      area: "Oakland",
      addr: "1 Test Way",
      distSF: "6 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
    });
    return { bandId, venueId };
  });
  return { t, asMember, userId, bandId, venueId };
}

type Setup = Awaited<ReturnType<typeof setupMemberBand>>;

async function insertFans(
  t: Setup["t"],
  count: number,
  prefix: string,
): Promise<Id<"users">[]> {
  return await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (let index = 0; index < count; index++) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `${prefix}_${index}`,
          name: `${prefix} ${index}`,
          email: `${prefix}_${index}@example.com`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    return userIds;
  });
}

async function insertGig(
  setup: Setup,
  options: {
    title: string;
    startsAt: number;
    goingCount?: number;
    price?: number;
    bandId?: Id<"bands">;
  },
): Promise<Id<"gigs">> {
  return await setup.t.run(async (ctx) =>
    insertGigWithBandIndex(ctx, {
      title: options.title,
      venueId: setup.venueId,
      price: options.price ?? 0,
      startsAt: options.startsAt,
      doorsTime: "8PM / 9PM",
      flyKey: "paper",
      lineup: [options.bandId ?? setup.bandId],
      genres: ["noise"],
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      cap: "No cap",
      goingCount: options.goingCount ?? 0,
    }),
  );
}

async function insertRsvps(
  t: Setup["t"],
  gigId: Id<"gigs">,
  userIds: Id<"users">[],
) {
  await t.run(async (ctx) => {
    for (const userId of userIds) {
      await ctx.db.insert("gigRsvps", { gigId, userId });
    }
  });
}

async function queryRecap(setup: Setup): Promise<BandRecap> {
  vi.setSystemTime(NOW);
  return await setup.asMember.query(bandRecap, { bandId: setup.bandId });
}

describe("analytics:bandRecap authorization", () => {
  test("throws when a signed-in caller is not a band member", async () => {
    const setup = await setupMemberBand();
    const asOutsider = setup.t.withIdentity({
      subject: "user_outsider",
      email: "outsider@example.com",
    });
    await asOutsider.mutation(api.users.ensureUser, {});

    await expect(
      asOutsider.query(bandRecap, { bandId: setup.bandId }),
    ).rejects.toThrow("Not a member of this band");
  });

  test("throws when the caller is signed out", async () => {
    const setup = await setupMemberBand();
    await expect(
      setup.t.query(bandRecap, { bandId: setup.bandId }),
    ).rejects.toThrow("Not signed in");
  });
});

describe("analytics:bandRecap fan measurements", () => {
  test("walks shows oldest first when classifying new and returning fans", async () => {
    const setup = await setupMemberBand();
    const [oldestGigId, middleGigId, newestGigId] = await Promise.all([
      insertGig(setup, {
        title: "Oldest",
        startsAt: NOW - 30 * DAY_MS,
      }),
      insertGig(setup, {
        title: "Middle",
        startsAt: NOW - 20 * DAY_MS,
      }),
      insertGig(setup, {
        title: "Newest",
        startsAt: NOW - 10 * DAY_MS,
      }),
    ]);
    const [fanA, fanB, fanC, fanD] = await insertFans(setup.t, 4, "walk_fan");
    await insertRsvps(setup.t, oldestGigId, [fanA, fanB]);
    await insertRsvps(setup.t, middleGigId, [fanB, fanC]);
    await insertRsvps(setup.t, newestGigId, [fanA, fanB, fanD]);

    const history = computeFanHistory([
      {
        gigId: newestGigId,
        startsAt: NOW - 10 * DAY_MS,
        fanIds: [fanA, fanB, fanD],
      },
      { gigId: oldestGigId, startsAt: NOW - 30 * DAY_MS, fanIds: [fanA, fanB] },
      { gigId: middleGigId, startsAt: NOW - 20 * DAY_MS, fanIds: [fanB, fanC] },
    ]);
    expect(history.splitByGig.get(oldestGigId)?.newFanIds.size).toBe(2);
    expect(history.splitByGig.get(oldestGigId)?.returningFanIds.size).toBe(0);
    expect(history.splitByGig.get(middleGigId)?.newFanIds.size).toBe(1);
    expect(history.splitByGig.get(middleGigId)?.returningFanIds.size).toBe(1);
    expect(history.splitByGig.get(newestGigId)?.newFanIds.size).toBe(1);
    expect(history.splitByGig.get(newestGigId)?.returningFanIds.size).toBe(2);

    const recap = await queryRecap(setup);
    expect(recap.shows.map((show) => show.title)).toEqual([
      "Newest",
      "Middle",
      "Oldest",
    ]);
    expect(recap.newReturning).toEqual({ suppressed: true });
    expect(
      recap.shows.every(
        (show) => show.newFans === null && show.returningFans === null,
      ),
    ).toBe(true);
  });

  test("publishes new and returning columns when only empty buckets are below the floor", async () => {
    const setup = await setupMemberBand();
    const [oldestGigId, newestGigId] = await Promise.all([
      insertGig(setup, {
        title: "Oldest Published",
        startsAt: NOW - 20 * DAY_MS,
      }),
      insertGig(setup, {
        title: "Newest Published",
        startsAt: NOW - 10 * DAY_MS,
      }),
    ]);
    const fans = await insertFans(setup.t, 15, "published_walk_fan");
    await insertRsvps(setup.t, oldestGigId, fans.slice(0, 10));
    await insertRsvps(setup.t, newestGigId, [
      ...fans.slice(0, 5),
      ...fans.slice(10, 15),
    ]);

    const recap = await queryRecap(setup);
    expect(recap.newReturning.suppressed).toBe(false);
    expect(
      recap.shows.every(
        (show) =>
          typeof show.newFans === "number" &&
          typeof show.returningFans === "number",
      ),
    ).toBe(true);
    expect(
      recap.shows.find((show) => show.gigId === oldestGigId),
    ).toMatchObject({
      newFans: 10,
      returningFans: 0,
    });
    expect(
      recap.shows.find((show) => show.gigId === newestGigId),
    ).toMatchObject({
      newFans: 5,
      returningFans: 5,
    });
  });

  test("buckets repeat fans by distinct show count", async () => {
    const setup = await setupMemberBand();
    const gigIds: Id<"gigs">[] = [];
    for (let index = 0; index < 4; index++) {
      gigIds.push(
        await insertGig(setup, {
          title: `Repeat ${index}`,
          startsAt: NOW - (40 - index * 5) * DAY_MS,
        }),
      );
    }
    const fans = await insertFans(setup.t, 15, "repeat_fan");
    const oneShowFans = fans.slice(0, 5);
    const twoShowFans = fans.slice(5, 10);
    const fourShowFans = fans.slice(10, 15);
    await insertRsvps(setup.t, gigIds[0], [
      ...oneShowFans,
      ...twoShowFans,
      ...fourShowFans,
    ]);
    await insertRsvps(setup.t, gigIds[1], [...twoShowFans, ...fourShowFans]);
    await insertRsvps(setup.t, gigIds[2], fourShowFans);
    await insertRsvps(setup.t, gigIds[3], fourShowFans);

    const recap = await queryRecap(setup);
    expect(recap.repeatFans).toEqual({
      tiers: [
        { key: "one", count: 5 },
        { key: "twoToThree", count: 5 },
        { key: "fourPlus", count: 5 },
      ],
      suppressed: false,
    });
  });

  test("publishes empty higher repeat tiers when every fan attended once", async () => {
    const setup = await setupMemberBand();
    const gigId = await insertGig(setup, {
      title: "One Each",
      startsAt: NOW - DAY_MS,
    });
    const fans = await insertFans(setup.t, 5, "one_show_fan");
    await insertRsvps(setup.t, gigId, fans);

    const recap = await queryRecap(setup);
    expect(recap.repeatFans).toEqual({
      tiers: [
        { key: "one", count: 5 },
        { key: "twoToThree", count: 0 },
        { key: "fourPlus", count: 0 },
      ],
      suppressed: false,
    });
  });

  test("buckets positive lead time and excludes post-gig rows from the median", async () => {
    const setup = await setupMemberBand();
    const startsAt = NOW - DAY_MS;
    const gigId = await insertGig(setup, {
      title: "Lead Time",
      startsAt,
      goingCount: 999,
    });
    const fans = await insertFans(setup.t, 25, "lead_fan");
    const groups = [
      { createdAt: startsAt - 20 * DAY_MS, fanIds: fans.slice(0, 5) },
      { createdAt: startsAt - 10 * DAY_MS, fanIds: fans.slice(5, 10) },
      { createdAt: startsAt - 3 * DAY_MS, fanIds: fans.slice(10, 15) },
      { createdAt: startsAt - DAY_MS / 2, fanIds: fans.slice(15, 20) },
      { createdAt: startsAt + DAY_MS, fanIds: fans.slice(20, 25) },
    ];
    for (const group of groups) {
      vi.setSystemTime(group.createdAt);
      await insertRsvps(setup.t, gigId, group.fanIds);
    }

    const recap = await queryRecap(setup);
    expect(recap.leadTime.buckets).toEqual([
      { key: "twoWeeksPlus", count: 5 },
      { key: "oneToTwoWeeks", count: 5 },
      { key: "underWeek", count: 5 },
      { key: "dayOf", count: 5 },
    ]);
    expect(recap.leadTime.unmeasurable).toBe(5);
    expect(recap.leadTime.medianDays).toBeCloseTo(6.5, 6);
    expect(recap.leadTime.suppressed).toBe(false);
    expect(recap.totals).toMatchObject({
      reportedRsvps: 999,
      measuredRsvps: 25,
      avgPerShow: 25,
      bestShowRsvps: 25,
    });
  });

  test("publishes lead time when every RSVP predates the gig", async () => {
    const setup = await setupMemberBand();
    const startsAt = NOW - DAY_MS;
    const gigId = await insertGig(setup, {
      title: "Clean Lead Time",
      startsAt,
    });
    const fans = await insertFans(setup.t, 5, "clean_lead_fan");
    vi.setSystemTime(startsAt - 20 * DAY_MS);
    await insertRsvps(setup.t, gigId, fans);

    const recap = await queryRecap(setup);
    expect(recap.leadTime).toMatchObject({
      buckets: [
        { key: "twoWeeksPlus", count: 5 },
        { key: "oneToTwoWeeks", count: 0 },
        { key: "underWeek", count: 0 },
        { key: "dayOf", count: 0 },
      ],
      unmeasurable: 0,
      suppressed: false,
    });
    expect(recap.leadTime.medianDays).toBeCloseTo(20, 6);
  });

  test("withholds a small unmeasurable lead-time cell", async () => {
    const setup = await setupMemberBand();
    const startsAt = NOW - DAY_MS;
    const gigId = await insertGig(setup, {
      title: "Small Unmeasurable Cell",
      startsAt,
    });
    const fans = await insertFans(setup.t, 9, "small_unmeasurable_fan");
    vi.setSystemTime(startsAt - 20 * DAY_MS);
    await insertRsvps(setup.t, gigId, fans.slice(0, 5));
    vi.setSystemTime(startsAt + DAY_MS);
    await insertRsvps(setup.t, gigId, fans.slice(5));

    const recap = await queryRecap(setup);
    expect(recap.leadTime).toEqual({
      buckets: [],
      medianDays: null,
      unmeasurable: 0,
      suppressed: true,
    });
  });

  test("publishes unmeasurable rows while lead-time buckets are suppressed", async () => {
    const setup = await setupMemberBand();
    const startsAt = NOW - DAY_MS;
    const gigId = await insertGig(setup, {
      title: "Partly Unmeasurable",
      startsAt,
    });
    const fans = await insertFans(setup.t, 8, "suppressed_lead_fan");
    vi.setSystemTime(startsAt - 20 * DAY_MS);
    await insertRsvps(setup.t, gigId, fans.slice(0, 3));
    vi.setSystemTime(startsAt + DAY_MS);
    await insertRsvps(setup.t, gigId, fans.slice(3));

    const recap = await queryRecap(setup);
    expect(recap.leadTime).toEqual({
      buckets: [],
      medianDays: null,
      unmeasurable: 5,
      suppressed: true,
    });
  });

  test("publishes an empty free side for a band with only paid shows", async () => {
    const setup = await setupMemberBand();
    const gigId = await insertGig(setup, {
      title: "Paid Only",
      startsAt: NOW - DAY_MS,
      price: 18,
    });
    const fans = await insertFans(setup.t, 5, "paid_fan");
    await insertRsvps(setup.t, gigId, fans);

    const recap = await queryRecap(setup);
    expect(recap.pricing).toEqual({
      freeShows: 0,
      freeAvgRsvps: 0,
      paidShows: 1,
      paidAvgRsvps: 5,
      suppressed: false,
    });
  });

  test("suppresses a four-fan repeat tier and reveals the five-fan boundary", async () => {
    async function recapWithFanCount(count: number) {
      const setup = await setupMemberBand();
      const gigId = await insertGig(setup, {
        title: `${count} fans`,
        startsAt: NOW - DAY_MS,
      });
      const fans = await insertFans(setup.t, count, `repeat_${count}`);
      await insertRsvps(setup.t, gigId, fans);
      return await queryRecap(setup);
    }

    const fourFans = await recapWithFanCount(4);
    expect(fourFans.repeatFans).toEqual({ tiers: [], suppressed: true });
    expect(fourFans.venues).toEqual({
      rows: [
        {
          venueName: "The Recap Room",
          shows: 1,
          totalRsvps: 4,
          avgRsvps: 4,
        },
      ],
      suppressed: false,
    });
    expect(fourFans.weekdays).toEqual({
      rows: [{ weekday: 2, shows: 1, avgRsvps: 4 }],
      suppressed: false,
    });
    expect(fourFans.pricing).toEqual({
      freeShows: 1,
      freeAvgRsvps: 4,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: false,
    });

    const fiveFans = await recapWithFanCount(5);
    expect(fiveFans.repeatFans).toEqual({
      tiers: [
        { key: "one", count: 5 },
        { key: "twoToThree", count: 0 },
        { key: "fourPlus", count: 0 },
      ],
      suppressed: false,
    });
  });

  test("groups Friday evening Pacific gigs under Friday instead of Saturday", async () => {
    const setup = await setupMemberBand();
    const fans = await insertFans(setup.t, 10, "pacific_weekday_fan");
    /* July is PDT (UTC-7): Saturday 04:00 UTC is Friday 21:00 Pacific,
     * while Monday 04:00 UTC is Sunday 21:00 Pacific. The Sunday row also
     * protects the ISO convention where Sunday must be 7 rather than 0. */
    const fridayStartsAt = Date.UTC(2026, 6, 11, 4);
    const sundayStartsAt = Date.UTC(2026, 6, 13, 4);
    const fridayGigId = await insertGig(setup, {
      title: "Friday Pacific",
      startsAt: fridayStartsAt,
    });
    const sundayGigId = await insertGig(setup, {
      title: "Sunday Pacific",
      startsAt: sundayStartsAt,
    });
    await insertRsvps(setup.t, fridayGigId, fans.slice(0, 5));
    await insertRsvps(setup.t, sundayGigId, fans.slice(5));

    const recap = await queryRecap(setup);
    expect(recap.weekdays).toEqual({
      rows: [
        { weekday: 5, shows: 1, avgRsvps: 5 },
        { weekday: 7, shows: 1, avgRsvps: 5 },
      ],
      suppressed: false,
    });
    expect(recap.weekdays.rows.some((row) => row.weekday === 6)).toBe(false);
  });
});

describe("analytics:bandRecap window", () => {
  test("truncates at MAX_RECAP_GIGS and says so", async () => {
    const setup = await setupMemberBand();
    await setup.t.run(async (ctx) => {
      for (let index = 0; index < MAX_RECAP_GIGS + 1; index++) {
        await insertGigWithBandIndex(ctx, {
          title: `Matched ${index}`,
          venueId: setup.venueId,
          price: 0,
          startsAt: NOW - DAY_MS - index * HOUR_MS,
          doorsTime: "8PM / 9PM",
          flyKey: "paper",
          lineup: [setup.bandId],
          genres: ["noise"],
          desc: "",
          ticketing: "rsvp",
          ageRequirement: "allAges",
          cap: "No cap",
          goingCount: 0,
        });
      }
    });

    const recap = await queryRecap(setup);
    expect(recap.window).toMatchObject({
      showsAnalyzed: MAX_RECAP_GIGS,
      scanned: MAX_RECAP_GIGS + 1,
      truncated: true,
    });
    expect(recap.shows).toHaveLength(MAX_RECAP_GIGS);
  });

  // The regression this join table exists for. Under the old global-scan read
  // these two shows sat past the 200-row window and vanished from the band's
  // own history entirely — the band saw an empty recap while its gigs were
  // right there in the table.
  test("keeps a band's whole history behind hundreds of other bands' gigs", async () => {
    const setup = await setupMemberBand();
    const otherBandId = await setup.t.run(async (ctx) =>
      ctx.db.insert("bands", {
        name: "Other Band",
        slug: "other-band",
        genres: ["punk"],
        area: "Bay Area",
        colorHex: "#E4DC4A",
        initials: "OB",
        followerCount: 0,
        bio: "",
        pastShows: [],
      }),
    );
    await setup.t.run(async (ctx) => {
      // Ours are the two oldest; 201 newer gigs belong to someone else.
      for (let index = 0; index < 203; index++) {
        await insertGigWithBandIndex(ctx, {
          title: `Show ${index}`,
          venueId: setup.venueId,
          price: 0,
          startsAt: NOW - DAY_MS - index * HOUR_MS,
          doorsTime: "8PM / 9PM",
          flyKey: "paper",
          lineup: [index < 201 ? otherBandId : setup.bandId],
          genres: ["noise"],
          desc: "",
          ticketing: "rsvp",
          ageRequirement: "allAges",
          cap: "No cap",
          goingCount: 0,
        });
      }
    });

    const recap = await queryRecap(setup);
    expect(recap.window).toMatchObject({
      showsAnalyzed: 2,
      scanned: 2,
      truncated: false,
    });
    expect(recap.shows.map((show) => show.title)).toEqual([
      "Show 201",
      "Show 202",
    ]);
  });
});

test("analytics:bandRecap returns the complete empty shape for a band with no past gigs", async () => {
  const setup = await setupMemberBand(81);
  expect(await queryRecap(setup)).toEqual({
    window: {
      showsAnalyzed: 0,
      scanned: 0,
      truncated: false,
      firstStartsAt: null,
      lastStartsAt: null,
    },
    totals: {
      shows: 0,
      reportedRsvps: 0,
      measuredRsvps: 0,
      avgPerShow: 0,
      bestShowRsvps: 0,
      distinctFans: 0,
      followerCount: 81,
    },
    shows: [],
    newReturning: { suppressed: true },
    leadTime: {
      buckets: [],
      medianDays: null,
      unmeasurable: 0,
      suppressed: true,
    },
    venues: { rows: [], suppressed: false },
    weekdays: { rows: [], suppressed: false },
    repeatFans: { tiers: [], suppressed: true },
    pricing: {
      freeShows: 0,
      freeAvgRsvps: 0,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: false,
    },
  });
});

import type { Doc } from "./_generated/dataModel";
import type { ArtistInsights } from "./analytics";

const artistInsights = makeFunctionReference<
  "query",
  { applicationId: Id<"artistApplications"> },
  ArtistInsights
>("analytics:artistInsights");

const myBandInsights = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  ArtistInsights
>("analytics:myBandInsights");

async function insertInsightsOrganization(
  setup: Setup,
  ownerUserId: Id<"users">,
  slug: string,
) {
  return await setup.t.run(async (ctx) => {
    const organizationId = await ctx.db.insert("organizations", {
      name: slug,
      slug,
      orgType: "promoter",
      status: "verified",
      ownerUserId,
      createdAt: FIXTURE_START,
      updatedAt: FIXTURE_START,
    });
    await ctx.db.insert("organizationMembers", {
      organizationId,
      userId: ownerUserId,
      role: "owner",
      createdAt: FIXTURE_START,
    });
    return organizationId;
  });
}

async function setupInsightsApplication(setup: Setup) {
  const asOrganizer = setup.t.withIdentity({
    subject: "insights_organizer",
    email: "organizer@insights.test",
  });
  const { userId: organizerId } = await asOrganizer.mutation(
    api.users.ensureUser,
    {},
  );
  const organizationId = await insertInsightsOrganization(
    setup,
    organizerId,
    "insights-organizer",
  );
  const ids = await setup.t.run(async (ctx) => {
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "publicEvent",
      venueId: setup.venueId,
      area: "Oakland",
      title: "Local music night",
      desc: "An evening of local music.",
      genres: ["noise"],
      startsAt: NOW + 14 * DAY_MS,
      ageRequirement: "allAges",
      flyKey: "paper",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "open",
      slug: "local-music-night",
      createdBy: organizerId,
      revision: 1,
      applicationCount: 1,
      createdAt: FIXTURE_START,
      updatedAt: FIXTURE_START,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 5000,
      required: true,
      status: "open",
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId: setup.bandId,
      submittedBy: setup.userId,
      message: "We are available",
      status: "submitted",
      createdAt: FIXTURE_START,
      updatedAt: FIXTURE_START,
    });
    return { opportunityId, applicationId };
  });
  return { ...ids, organizationId, organizerId, asOrganizer };
}

async function insertCheckedInRsvps(
  setup: Setup,
  gigId: Id<"gigs">,
  userIds: Id<"users">[],
) {
  await setup.t.run(async (ctx) => {
    for (const userId of userIds) {
      // Zero is a recorded check-in, not an absent timestamp.
      await ctx.db.insert("gigRsvps", { gigId, userId, checkedInAt: 0 });
    }
  });
}

async function insertInsightsFollows(setup: Setup, userIds: Id<"users">[]) {
  await setup.t.run(async (ctx) => {
    for (const userId of userIds) {
      await ctx.db.insert("follows", { bandId: setup.bandId, userId });
    }
  });
}

type InsightsOrderFixture = Pick<
  Doc<"ticketOrders">,
  "buyerUserId" | "quantity"
> &
  Partial<Pick<Doc<"ticketOrders">, "referralBandId" | "status">>;

async function insertInsightsOrders(
  setup: Setup,
  gigId: Id<"gigs">,
  organizationId: Id<"organizations">,
  orders: InsightsOrderFixture[],
) {
  return await setup.t.run(async (ctx) => {
    const inserted = [];
    for (const order of orders) {
      const status = order.status ?? "paid";
      const orderId = await ctx.db.insert("ticketOrders", {
        ...order,
        gigId,
        organizationId,
        status,
        unitPriceMinor: 2000,
        unitFeeMinor: 0,
        subtotalMinor: order.quantity * 2000,
        feeMinor: 0,
        totalMinor: order.quantity * 2000,
        currency: "usd",
        reservedUntil: FIXTURE_START + HOUR_MS,
        attempt: 1,
        refundedMinor: status === "refunded" ? order.quantity * 2000 : 0,
        createdAt: FIXTURE_START,
        updatedAt: FIXTURE_START,
      });
      inserted.push({ ...order, status, orderId });
    }
    return inserted;
  });
}

async function insertInsightsTickets(
  setup: Setup,
  gigId: Id<"gigs">,
  organizationId: Id<"organizations">,
  tickets: Array<Pick<Doc<"tickets">, "orderId" | "holderUserId" | "status">>,
) {
  await setup.t.run(async (ctx) => {
    for (const [index, ticket] of tickets.entries()) {
      await ctx.db.insert("tickets", {
        ...ticket,
        gigId,
        organizationId,
        token: `${ticket.orderId}-${index}`,
        createdAt: FIXTURE_START,
      });
    }
  });
}

async function queryBandInsights(setup: Setup) {
  vi.setSystemTime(NOW);
  return await setup.asMember.query(myBandInsights, { bandId: setup.bandId });
}

async function setupMixedArtistInsights() {
  const setup = await setupMemberBand(81);
  const application = await setupInsightsApplication(setup);
  const fans = await insertFans(setup.t, 20, "insights_fan");
  const oldestStartsAt = Date.UTC(2026, 6, 11, 4); // Friday in Pacific time.
  const paidStartsAt = Date.UTC(2026, 6, 18, 4); // Friday in Pacific time.
  const newestStartsAt = Date.UTC(2026, 6, 20, 4); // Sunday in Pacific time.
  // Deliberately insert out of chronological order.
  const newestGigId = await insertGig(setup, {
    title: "Newest RSVP",
    startsAt: newestStartsAt,
  });
  const paidGigId = await insertGig(setup, {
    title: "Paid show",
    startsAt: paidStartsAt,
    price: 20,
  });
  const oldestGigId = await insertGig(setup, {
    title: "Oldest RSVP",
    startsAt: oldestStartsAt,
  });
  await setup.t.run(async (ctx) => {
    await ctx.db.patch(setup.venueId, { venueType: "hall" });
    const paidVenueId = await ctx.db.insert("venues", {
      name: "Private paid venue",
      area: "San Francisco",
      venueType: "club",
      addr: "2 Test Way",
      distSF: "1 mi",
      distOak: "6 mi",
      lat: 37.77,
      lng: -122.42,
    });
    await ctx.db.patch(paidGigId, {
      venueId: paidVenueId,
      ticketing: "paid",
      ticketPriceMinor: 2000,
    });
  });
  await insertCheckedInRsvps(setup, oldestGigId, fans.slice(0, 5));
  await insertRsvps(setup.t, oldestGigId, fans.slice(15, 17));
  await insertCheckedInRsvps(setup, newestGigId, [fans[0], ...fans.slice(7, 12)]);
  await insertRsvps(setup.t, newestGigId, fans.slice(15, 18));
  await insertCheckedInRsvps(setup, paidGigId, [fans[0], fans[6]]);
  await insertRsvps(setup.t, paidGigId, [fans[19]]);

  // Referral buyers also follow: their referral must take precedence.
  await insertInsightsFollows(setup, fans.slice(0, 10));
  const referralOrders = fans.slice(0, 5).map((buyerUserId, index) => ({
    buyerUserId,
    quantity: (index % 3) + 1,
    referralBandId: setup.bandId,
  }));
  const followOrders = fans.slice(5, 10).map((buyerUserId, index) => ({
    buyerUserId,
    quantity: ((index + 1) % 3) + 1,
  }));
  const unattributedOrders = fans.slice(10, 15).map((buyerUserId, index) => ({
    buyerUserId,
    quantity: ((index + 2) % 3) + 1,
  }));
  const orders = await insertInsightsOrders(
    setup,
    paidGigId,
    application.organizationId,
    [...referralOrders, ...followOrders, ...unattributedOrders],
  );
  await insertInsightsTickets(
    setup,
    paidGigId,
    application.organizationId,
    orders.flatMap((order, buyerIndex) =>
      Array.from({ length: order.quantity }, (_, ticketIndex) => ({
        orderId: order.orderId,
        holderUserId: order.buyerUserId,
        // Two used tickets for one buyer must count that fan only once.
        status:
          buyerIndex < 6 && (ticketIndex === 0 || buyerIndex === 1)
            ? ("used" as const)
            : ("valid" as const),
      })),
    ),
  );
  for (const status of ["refunded", "cancelled"] as const) {
    const [order] = await insertInsightsOrders(
      setup,
      paidGigId,
      application.organizationId,
      [{ buyerUserId: fans[18], quantity: 2, status }],
    );
    await insertInsightsTickets(
      setup,
      paidGigId,
      application.organizationId,
      Array.from({ length: order.quantity }, () => ({
        orderId: order.orderId,
        holderUserId: order.buyerUserId,
        status,
      })),
    );
  }
  return {
    ...setup,
    ...application,
    fans,
    gigIds: [oldestGigId, paidGigId, newestGigId],
    oldestStartsAt,
    newestStartsAt,
    referralOrders,
    followOrders,
    unattributedOrders,
  };
}

describe("analytics:artistInsights aggregates", () => {
  test("both audiences receive identical aggregates without events or user ids", async () => {
    const setup = await setupMixedArtistInsights();
    const bandResult = await queryBandInsights(setup);
    const organizerResult = await setup.asOrganizer.query(artistInsights, {
      applicationId: setup.applicationId,
    });
    const referral = setup.referralOrders.reduce(
      (sum, row) => sum + row.quantity,
      0,
    );
    const follow = setup.followOrders.reduce((sum, row) => sum + row.quantity, 0);
    const unattributed = setup.unattributedOrders.reduce(
      (sum, row) => sum + row.quantity,
      0,
    );
    expect(organizerResult).toEqual(bandResult);
    expect(organizerResult).toEqual({
      band: { bandId: setup.bandId, name: "Private Signals" },
      window: {
        events: 3,
        truncated: false,
        firstStartsAt: setup.oldestStartsAt,
        lastStartsAt: setup.newestStartsAt,
      },
      followers: 81,
      rsvpTotal: 7 + 9 + 3,
      ticketsSold: referral + follow + unattributed,
      checkIns: 5 + 7 + 6,
      returningAttendees: 5,
      returningSuppressed: false,
      attribution: { referral, follow, unattributed, suppressed: false },
      byArea: {
        buckets: [
          { key: "Oakland", events: 2, checkIns: 11 },
          { key: "San Francisco", events: 1, checkIns: 7 },
        ],
        suppressed: false,
      },
      byVenueType: {
        buckets: [
          { key: "hall", events: 2, checkIns: 11 },
          { key: "club", events: 1, checkIns: 7 },
        ],
        suppressed: false,
      },
      byWeekday: {
        buckets: [
          { key: "Fri", events: 2, checkIns: 12 },
          { key: "Sun", events: 1, checkIns: 6 },
        ],
        suppressed: false,
      },
      byPriceBand: {
        buckets: [
          { key: "free", events: 2, checkIns: 11 },
          { key: "from15to30", events: 1, checkIns: 7 },
        ],
        suppressed: false,
      },
      estimatedDraw: {
        low: 5,
        high: 7,
        confidence: "medium",
        events: 3,
        basis: "checkIns",
      },
    });
    const serialized = JSON.stringify(organizerResult);
    for (const id of [
      ...setup.fans,
      ...setup.gigIds,
      setup.organizerId,
      setup.userId,
    ]) {
      expect(serialized).not.toContain(id);
    }
  });

  test("suppresses a small area bucket while the other partitions remain publishable", async () => {
    const setup = await setupMemberBand();
    const fans = await insertFans(setup.t, 8, "small_area");
    const largeGigId = await insertGig(setup, {
      title: "Five fans",
      startsAt: Date.UTC(2026, 6, 11, 4),
    });
    const smallGigId = await insertGig(setup, {
      title: "Three fans",
      startsAt: Date.UTC(2026, 6, 18, 4),
    });
    await setup.t.run(async (ctx) => {
      await ctx.db.patch(setup.venueId, { venueType: "hall" });
      const venueId = await ctx.db.insert("venues", {
        name: "Small venue",
        area: "Berkeley",
        venueType: "hall",
        addr: "3 Test Way",
        distSF: "10 mi",
        distOak: "3 mi",
        lat: 37.87,
        lng: -122.27,
      });
      await ctx.db.patch(smallGigId, { venueId });
    });
    await insertCheckedInRsvps(setup, largeGigId, fans.slice(0, 5));
    await insertCheckedInRsvps(setup, smallGigId, fans.slice(5));
    const result = await queryBandInsights(setup);
    expect(result.byArea).toEqual({ buckets: [], suppressed: true });
    for (const [partition, key] of [
      [result.byVenueType, "hall"],
      [result.byWeekday, "Fri"],
      [result.byPriceBand, "free"],
    ] as const) {
      expect(partition).toEqual({
        buckets: [{ key, events: 2, checkIns: 8 }],
        suppressed: false,
      });
    }
  });

  test("suppresses attribution based on distinct buyers despite repeated large orders", async () => {
    const setup = await setupMixedArtistInsights();
    // Fold the fifth guest into a repeat buyer, leaving four distinct guests
    // and five each in referral/follow, despite large guest order quantities.
    await setup.t.run(async (ctx) => {
      const orders = await ctx.db
        .query("ticketOrders")
        .withIndex("by_gigId_and_status", (q) =>
          q.eq("gigId", setup.gigIds[1]).eq("status", "paid"),
        )
        .take(500);
      for (const order of orders) {
        if (setup.fans.slice(10, 15).includes(order.buyerUserId)) {
          await ctx.db.patch(order._id, {
            quantity: 100,
            buyerUserId:
              order.buyerUserId === setup.fans[14]
                ? setup.fans[10]
                : order.buyerUserId,
          });
        }
      }
    });
    expect((await queryBandInsights(setup)).attribution).toEqual({
      referral: 0,
      follow: 0,
      unattributed: 0,
      suppressed: true,
    });
  });

  test.each([4, 5])(
    "returning privacy uses the union of %i distinct fans",
    async (count) => {
      const setup = await setupMemberBand();
      const fans = await insertFans(setup.t, count, `returning_${count}`);
      for (const daysAgo of [1, 20, 10]) {
        const gigId = await insertGig(setup, {
          title: `Repeat ${daysAgo}`,
          startsAt: NOW - daysAgo * DAY_MS,
        });
        await insertCheckedInRsvps(setup, gigId, fans);
      }
      const result = await queryBandInsights(setup);
      expect(result.checkIns).toBe(count * 3);
      expect(result.returningAttendees).toBe(count < 5 ? 0 : count);
      expect(result.returningSuppressed).toBe(count < 5);
    },
  );

  test("estimates from RSVPs when every event has zero check-ins", async () => {
    const setup = await setupMemberBand();
    const fans = await insertFans(setup.t, 10, "rsvp_draw");
    for (const [index, count] of [6, 10].entries()) {
      const gigId = await insertGig(setup, {
        title: `RSVP only ${index}`,
        startsAt: NOW - (index + 1) * DAY_MS,
      });
      await insertRsvps(setup.t, gigId, fans.slice(0, count));
    }
    expect(await queryBandInsights(setup)).toMatchObject({
      rsvpTotal: 16,
      ticketsSold: 0,
      checkIns: 0,
      returningAttendees: 0,
      returningSuppressed: true,
      estimatedDraw: {
        low: 7,
        high: 9,
        confidence: "low",
        events: 2,
        basis: "rsvps",
      },
    });
  });

  test("keeps zero-attendance events in the check-in draw and publishes unknown venue buckets", async () => {
    const setup = await setupMemberBand();
    const fans = await insertFans(setup.t, 5, "unknown_venue");
    const gigId = await insertGig(setup, {
      title: "Attended",
      startsAt: NOW - 10 * DAY_MS,
    });
    await insertCheckedInRsvps(setup, gigId, fans);
    await insertGig(setup, {
      title: "No attendance",
      startsAt: NOW - DAY_MS,
    });
    await setup.t.run((ctx) => ctx.db.delete(setup.venueId));
    const result = await queryBandInsights(setup);
    for (const partition of [result.byArea, result.byVenueType]) {
      expect(partition).toEqual({
        buckets: [{ key: "unknown", events: 2, checkIns: 5 }],
        suppressed: false,
      });
    }
    expect(result.estimatedDraw).toEqual({
      low: 1,
      high: 4,
      confidence: "low",
      events: 2,
      basis: "checkIns",
    });
  });
});

describe("analytics:artistInsights window", () => {
  test.each([MAX_RECAP_GIGS, MAX_RECAP_GIGS + 1])(
    "analyzes the newest capped window from %i past gigs",
    async (count) => {
      const setup = await setupMemberBand();
      const [fan] = await insertFans(setup.t, 1, "window_fan");
      for (let index = 0; index < count; index++) {
        const gigId = await insertGig(setup, {
          title: `Past ${index}`,
          startsAt: NOW - (index + 1) * DAY_MS,
        });
        await insertRsvps(setup.t, gigId, [fan]);
      }
      const futureGigId = await insertGig(setup, {
        title: "Future",
        startsAt: NOW + DAY_MS,
      });
      await insertRsvps(setup.t, futureGigId, [fan]);
      const result = await queryBandInsights(setup);
      expect(result.window).toEqual({
        events: MAX_RECAP_GIGS,
        truncated: count > MAX_RECAP_GIGS,
        firstStartsAt: NOW - MAX_RECAP_GIGS * DAY_MS,
        lastStartsAt: NOW - DAY_MS,
      });
      expect(result.rsvpTotal).toBe(MAX_RECAP_GIGS);
    },
  );

  test("returns zero totals and optional dates with no past events", async () => {
    const setup = await setupMemberBand(81);
    const result = await queryBandInsights(setup);
    expect(result).toMatchObject({
      band: { bandId: setup.bandId, name: "Private Signals" },
      window: { events: 0, truncated: false },
      followers: 81,
      rsvpTotal: 0,
      ticketsSold: 0,
      checkIns: 0,
      returningAttendees: 0,
      returningSuppressed: true,
      estimatedDraw: null,
    });
    expect(result.window.firstStartsAt).toBeUndefined();
    expect(result.window.lastStartsAt).toBeUndefined();
    for (const partition of [
      result.byArea,
      result.byVenueType,
      result.byWeekday,
      result.byPriceBand,
    ]) {
      expect(partition.buckets).toEqual([]);
    }
  });
});

describe("analytics:artistInsights authorization", () => {
  test.each(["owner", "manager"] as const)(
    "allows the opportunity organization's %s",
    async (role) => {
      const setup = await setupMemberBand();
      const application = await setupInsightsApplication(setup);
      const asReviewer = setup.t.withIdentity({ subject: `reviewer_${role}` });
      const { userId } = await asReviewer.mutation(api.users.ensureUser, {});
      await setup.t.run((ctx) =>
        ctx.db.insert("organizationMembers", {
          organizationId: application.organizationId,
          userId,
          role,
          createdAt: FIXTURE_START,
        }),
      );
      vi.setSystemTime(NOW);
      const result = await asReviewer.query(artistInsights, {
        applicationId: application.applicationId,
      });
      expect(result.band.bandId).toBe(setup.bandId);
    },
  );

  test("refuses another organization's owner and an unauthenticated caller", async () => {
    const setup = await setupMemberBand();
    const application = await setupInsightsApplication(setup);
    const asOtherOwner = setup.t.withIdentity({ subject: "other_org_owner" });
    const { userId } = await asOtherOwner.mutation(api.users.ensureUser, {});
    await insertInsightsOrganization(setup, userId, "other-organization");
    const args = { applicationId: application.applicationId };
    await expect(asOtherOwner.query(artistInsights, args)).rejects.toThrow(
      "Not permitted for this organization",
    );
    await expect(setup.t.query(artistInsights, args)).rejects.toThrow(
      "Not signed in",
    );
  });

  test.each(["finance", "door"] as const)(
    "refuses an opportunity organization's %s member",
    async (role) => {
      const setup = await setupMemberBand();
      const application = await setupInsightsApplication(setup);
      await setup.t.run((ctx) =>
        ctx.db.insert("organizationMembers", {
          organizationId: application.organizationId,
          userId: setup.userId,
          role,
          createdAt: FIXTURE_START,
        }),
      );
      await expect(
        setup.asMember.query(artistInsights, {
          applicationId: application.applicationId,
        }),
      ).rejects.toThrow("Not permitted for this organization");
    },
  );

  test.each([
    ["application", "Application not found"],
    ["opportunity", "Opportunity not found"],
    ["band", "Band not found"],
  ] as const)("reports a missing %s", async (missing, message) => {
    const setup = await setupMemberBand();
    const application = await setupInsightsApplication(setup);
    const id =
      missing === "application"
        ? application.applicationId
        : missing === "opportunity"
          ? application.opportunityId
          : setup.bandId;
    await setup.t.run((ctx) => ctx.db.delete(id));
    await expect(
      application.asOrganizer.query(artistInsights, {
        applicationId: application.applicationId,
      }),
    ).rejects.toThrow(message);
  });
});

describe("analytics:myBandInsights authorization", () => {
  test("allows a band member", async () => {
    const setup = await setupMemberBand();
    expect((await queryBandInsights(setup)).band.bandId).toBe(setup.bandId);
  });

  test("refuses a signed-in stranger and an unauthenticated caller", async () => {
    const setup = await setupMemberBand();
    const asStranger = setup.t.withIdentity({ subject: "insights_stranger" });
    await asStranger.mutation(api.users.ensureUser, {});
    const args = { bandId: setup.bandId };
    await expect(asStranger.query(myBandInsights, args)).rejects.toThrow(
      "Not a member of this band",
    );
    await expect(setup.t.query(myBandInsights, args)).rejects.toThrow(
      "Not signed in",
    );
  });
});
