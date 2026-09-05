/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  bookedLineup,
  publishGigFromOpportunity,
  syncGigLineup,
  unpublishOpportunityGig,
} from "./lib/gigPublish";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-04T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

async function setupGigPublish(
  overrides: Partial<
    Pick<
      Doc<"talentOpportunities">,
      | "status"
      | "startsAt"
      | "doorsAt"
      | "ticketing"
      | "externalUrl"
      | "expectedAttendance"
    >
  > = {},
) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const ownerId = await ctx.db.insert("users", {
      clerkId: "publish_owner",
      name: "Organizer",
      email: "organizer@publish.test",
      genres: [],
      attendedCount: 0,
    });
    const artistId = await ctx.db.insert("users", {
      clerkId: "publish_artist",
      name: "Artist",
      email: "artist@publish.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      managedByOrganizationId: organizationId,
      status: "verified",
      approxLabel: "Uptown, Oakland",
      venueType: "hall",
    });
    const bandFields = {
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      followerCount: 0,
      pastShows: [],
    };
    const bandA = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Static Bloom",
      slug: "static-bloom",
      initials: "SB",
    });
    const bandB = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
      initials: "OB",
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "publicEvent",
      venueId,
      area: "Uptown, Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: NOW + 14 * DAY_MS,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "none",
      currency: "usd",
      status: "booking",
      slug: "friday-at-the-hall",
      createdBy: ownerId,
      revision: 2,
      applicationCount: 0,
      createdAt: NOW,
      updatedAt: NOW,
      ...overrides,
    });
    const slotA = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      setLengthMin: 45,
      guaranteeMinor: 5000,
      required: true,
      status: "open",
    });
    const slotB = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 1,
      role: "support",
      setLengthMin: 30,
      guaranteeMinor: 5000,
      required: false,
      status: "open",
    });
    return {
      ownerId,
      artistId,
      organizationId,
      venueId,
      bandA,
      bandB,
      opportunityId,
      slotA,
      slotB,
    };
  });

  async function bookSlot(slotId: Id<"opportunitySlots">, bandId: Id<"bands">) {
    return await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(ids.opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      const applicationId = await ctx.db.insert("artistApplications", {
        opportunityId: ids.opportunityId,
        slotId,
        bandId,
        submittedBy: ids.artistId,
        message: "We are available",
        status: "booked",
        createdAt: NOW,
        updatedAt: NOW,
      });
      const bookingId = await ctx.db.insert("bookings", {
        opportunityId: ids.opportunityId,
        slotId,
        organizationId: ids.organizationId,
        bandId,
        applicationId,
        status: "confirmed",
        revision: 1,
        startsAt: opportunity.startsAt,
        grossMinor: 5000,
        commissionBps: 1000,
        commissionMinor: 500,
        artistNetMinor: 4500,
        currency: "usd",
        cancellationTemplate: "standard",
        organizerAcceptedTermsAt: NOW,
        artistAcceptedTermsAt: NOW,
        confirmedAt: NOW,
        payoutHold: false,
        createdBy: ids.ownerId,
        createdAt: NOW,
        updatedAt: NOW,
      });
      await ctx.db.patch(slotId, { bookingId, bandId, status: "booked" });
      return bookingId;
    });
  }

  async function publish() {
    const gigId = await t.run((ctx) =>
      publishGigFromOpportunity(ctx, ids.opportunityId),
    );
    expect(gigId).not.toBeNull();
    if (!gigId) throw new Error("Expected the fixture to publish");
    return gigId;
  }

  return { t, ...ids, bookSlot, publish };
}

describe("opportunity gig publishing", () => {
  test("publishes when only the required slot is confirmed", async () => {
    const f = await setupGigPublish();
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();

    await f.t.run(async (ctx) => {
      const gig = await ctx.db.get(gigId);
      expect(gig).toMatchObject({
        ownerKind: "organization",
        createdByOrganization: f.organizationId,
        opportunityId: f.opportunityId,
        venueId: f.venueId,
        lineup: [f.bandA],
        performers: [
          { name: "Static Bloom", role: "headliner", bandId: f.bandA },
        ],
        ticketing: "rsvp",
        price: 0,
        cap: "No cap",
        doorsAt: NOW + 14 * DAY_MS,
        discoveryListingReady: true,
        lifecycle: "published",
      });
      expect(gig?.createdByBand).toBeUndefined();
      expect(await ctx.db.query("gigBands").collect()).toMatchObject([
        { gigId, bandId: f.bandA, startsAt: NOW + 14 * DAY_MS },
      ]);
      expect(await ctx.db.get(f.opportunityId)).toMatchObject({
        status: "confirmed",
        publicGigId: gigId,
        revision: 3,
      });
    });
  });

  test.each([false, true])(
    "does not publish an unfilled required slot (optional booked: %s)",
    async (bookOptional) => {
      const f = await setupGigPublish();
      if (bookOptional) await f.bookSlot(f.slotB, f.bandB);
      const before = await f.t.run((ctx) => ctx.db.get(f.opportunityId));

      expect(
        await f.t.run((ctx) => publishGigFromOpportunity(ctx, f.opportunityId)),
      ).toBeNull();

      await f.t.run(async (ctx) => {
        expect(await ctx.db.query("gigs").collect()).toEqual([]);
        expect(await ctx.db.query("gigBands").collect()).toEqual([]);
        expect(await ctx.db.get(f.opportunityId)).toEqual(before);
      });
    },
  );

  test.each(["awaiting_payment", "cancelled_by_artist", "missing"] as const)(
    "does not count a %s booking as filling the required slot",
    async (status) => {
      const f = await setupGigPublish();
      const bookingId = await f.bookSlot(f.slotA, f.bandA);
      await f.t.run(async (ctx) => {
        if (status === "missing") await ctx.db.delete(bookingId);
        else await ctx.db.patch(bookingId, { status });
        expect(await bookedLineup(ctx, f.opportunityId)).toEqual({
          lineup: [],
          performers: [],
          requiredFilled: false,
        });
        expect(await publishGigFromOpportunity(ctx, f.opportunityId)).toBeNull();
        expect(await ctx.db.query("gigs").collect()).toEqual([]);
      });
    },
  );

  test("syncs optional bookings without changing the confirmed opportunity", async () => {
    const f = await setupGigPublish();
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    const before = await f.t.run((ctx) => ctx.db.get(f.opportunityId));
    const optionalBookingId = await f.bookSlot(f.slotB, f.bandB);

    await f.t.run(async (ctx) => {
      // Repeated synchronization must replace the join rows without duplicates.
      await syncGigLineup(ctx, f.opportunityId);
      await syncGigLineup(ctx, f.opportunityId);
      expect(await ctx.db.get(gigId)).toMatchObject({
        lineup: [f.bandA, f.bandB],
        performers: [
          { name: "Static Bloom", role: "headliner", bandId: f.bandA },
          { name: "Other Band", role: "support", bandId: f.bandB },
        ],
      });
      expect(await ctx.db.query("gigBands").collect()).toMatchObject([
        { gigId, bandId: f.bandA, startsAt: NOW + 14 * DAY_MS },
        { gigId, bandId: f.bandB, startsAt: NOW + 14 * DAY_MS },
      ]);
      expect(await ctx.db.get(f.opportunityId)).toEqual(before);

      await ctx.db.patch(optionalBookingId, { status: "cancelled_by_artist" });
      await syncGigLineup(ctx, f.opportunityId);
      expect(await ctx.db.get(gigId)).toMatchObject({ lineup: [f.bandA] });
      expect(await ctx.db.query("gigBands").collect()).toMatchObject([
        { gigId, bandId: f.bandA },
      ]);
      expect(await ctx.db.get(f.opportunityId)).toEqual(before);
    });
  });

  test("unpublishes and reopens booking after a required-slot cancellation", async () => {
    const f = await setupGigPublish();
    const bookingId = await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();

    await f.t.run(async (ctx) => {
      await ctx.db.patch(bookingId, { status: "cancelled_by_artist" });
      await ctx.db.patch(f.slotA, {
        bookingId: undefined,
        bandId: undefined,
        status: "open",
      });
      await unpublishOpportunityGig(ctx, f.opportunityId, "required_slot_cancelled");
      expect(await ctx.db.get(gigId)).toMatchObject({
        lifecycle: "unpublished",
        discoveryListingReady: false,
      });
      expect(await ctx.db.get(f.opportunityId)).toMatchObject({
        status: "booking",
        publicGigId: gigId,
        revision: 4,
      });
    });
    expect(await f.t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();
  });

  test("republishes the same gig after the required slot is rebooked", async () => {
    const f = await setupGigPublish();
    const bookingId = await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    const original = await f.t.run((ctx) => ctx.db.get(gigId));
    await f.t.run(async (ctx) => {
      await ctx.db.patch(bookingId, { status: "cancelled_by_artist" });
      await ctx.db.patch(f.slotA, {
        bookingId: undefined,
        bandId: undefined,
        status: "open",
      });
      await unpublishOpportunityGig(ctx, f.opportunityId, "required_slot_cancelled");
    });
    await f.bookSlot(f.slotA, f.bandB);

    expect(await f.publish()).toBe(gigId);

    await f.t.run(async (ctx) => {
      expect(await ctx.db.query("gigs").collect()).toMatchObject([
        {
          _id: gigId,
          slug: original?.slug,
          lifecycle: "published",
          discoveryListingReady: true,
          lineup: [f.bandB],
        },
      ]);
      expect(await ctx.db.query("gigBands").collect()).toMatchObject([
        { gigId, bandId: f.bandB },
      ]);
      expect(await ctx.db.get(f.opportunityId)).toMatchObject({
        status: "confirmed",
        publicGigId: gigId,
        revision: 5,
      });
    });
  });

  test.each(["open", "applications_closed"] as const)(
    "can publish directly from %s",
    async (status) => {
      const f = await setupGigPublish({ status });
      await f.bookSlot(f.slotA, f.bandA);
      const gigId = await f.publish();
      expect(await f.t.run((ctx) => ctx.db.get(f.opportunityId))).toMatchObject({
        status: "confirmed",
        publicGigId: gigId,
      });
    },
  );

  test("preserves external ticketing, attendance cap, and doors time", async () => {
    const f = await setupGigPublish({
      ticketing: "external",
      externalUrl: "https://tickets.example.com/friday",
      expectedAttendance: 250,
      startsAt: Date.parse("2026-09-19T03:00:00Z"),
      doorsAt: Date.parse("2026-09-19T02:00:00Z"),
    });
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    expect(await f.t.run((ctx) => ctx.db.get(gigId))).toMatchObject({
      ticketing: "external",
      externalUrl: "https://tickets.example.com/friday",
      cap: "250",
      doorsTime: "7PM / 8PM",
      doorsAt: Date.parse("2026-09-19T02:00:00Z"),
      startsAt: Date.parse("2026-09-19T03:00:00Z"),
    });
  });
});

describe("organization-owned gig visibility", () => {
  test("hides suspended organizers from public links and upcoming feeds", async () => {
    const f = await setupGigPublish();
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    const gig = await f.t.run((ctx) => ctx.db.get(gigId));
    if (!gig?.slug) throw new Error("Expected a published slug");

    expect(
      await f.t.query(api.gigs.resolvePublic, { ref: gig.slug }),
    ).toMatchObject({ _id: gigId });
    expect((await f.t.query(api.gigs.feedV2, {})).gigs).toHaveLength(1);
    expect(await f.t.query(api.gigs.goingCounts, {})).toHaveLength(1);
    expect(await f.t.query(api.gigs.forBand, { bandId: f.bandA })).toHaveLength(1);

    await f.t.run((ctx) => ctx.db.patch(f.organizationId, { status: "suspended" }));

    expect(await f.t.query(api.gigs.resolvePublic, { ref: gig.slug })).toBeNull();
    expect(await f.t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();
    expect((await f.t.query(api.gigs.feedV2, {})).gigs).toEqual([]);
    expect(await f.t.query(api.gigs.goingCounts, {})).toEqual([]);
    expect(await f.t.query(api.gigs.forBand, { bandId: f.bandA })).toEqual([]);
  });

  test("hides suspended organizations from band history", async () => {
    const f = await setupGigPublish({ startsAt: NOW - 7 * DAY_MS });
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    expect(
      (await f.t.query(api.gigs.pastForBand, { bandId: f.bandA })).gigs,
    ).toMatchObject([{ _id: gigId }]);

    await f.t.run((ctx) => ctx.db.patch(f.organizationId, { status: "suspended" }));

    expect(await f.t.query(api.gigs.pastForBand, { bandId: f.bandA })).toEqual({
      gigs: [],
      venues: [],
    });
  });
});

describe("organization-owned gig backfills", () => {
  // Run the registered migration's batch handler, including its returned patch.
  // These single-gig fixtures need neither component state nor scheduled jobs.
  const batchArgs = { cursor: null, dryRun: false, oneBatchOnly: true };

  test("backfillGigProjects skips organization gigs without patching them", async () => {
    const f = await setupGigPublish();
    await f.bookSlot(f.slotA, f.bandA);
    const gigId = await f.publish();
    await f.t.run((ctx) =>
      ctx.db.patch(gigId, {
        lifecycle: undefined,
        doorsAt: undefined,
        performers: undefined,
      }),
    );
    const before = await f.t.run((ctx) => ctx.db.get(gigId));

    expect(
      await f.t.mutation(internal.migrations.backfillGigProjects, batchArgs),
    ).toMatchObject({ processed: 1, isDone: true });

    await f.t.run(async (ctx) => {
      expect(await ctx.db.query("gigProjects").collect()).toEqual([]);
      expect(await ctx.db.query("gigProjectPerformers").collect()).toEqual([]);
      expect(await ctx.db.get(gigId)).toEqual(before);
    });
  });

  test.each([undefined, false, true])(
    "backfillGigDiscoveryListingReady makes organization gigs ready without a project (was %s)",
    async (discoveryListingReady) => {
      const f = await setupGigPublish();
      await f.bookSlot(f.slotA, f.bandA);
      const gigId = await f.publish();
      await f.t.run((ctx) => ctx.db.patch(gigId, { discoveryListingReady }));
      const before = await f.t.run((ctx) => ctx.db.get(gigId));

      expect(
        await f.t.mutation(
          internal.migrations.backfillGigDiscoveryListingReady,
          batchArgs,
        ),
      ).toMatchObject({ processed: 1, isDone: true });
      await f.t.mutation(
        internal.migrations.backfillGigDiscoveryListingReady,
        batchArgs,
      );

      await f.t.run(async (ctx) => {
        expect(await ctx.db.query("gigProjects").collect()).toEqual([]);
        expect(await ctx.db.get(gigId)).toEqual({
          ...before,
          discoveryListingReady: true,
        });
      });
    },
  );
});
