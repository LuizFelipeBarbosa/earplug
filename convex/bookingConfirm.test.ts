/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { confirmBooking } from "./lib/bookingConfirm";
import { unpublishOpportunityGig } from "./lib/gigPublish";
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

async function setupPrivateBooking() {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const ownerId = await ctx.db.insert("users", {
      clerkId: "confirm_owner",
      name: "Private Host",
      email: "host@confirm.test",
      genres: [],
      attendedCount: 0,
    });
    const artistId = await ctx.db.insert("users", {
      clerkId: "confirm_artist",
      name: "Artist",
      email: "artist@confirm.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Backyard Host",
      slug: "backyard-host",
      orgType: "privateHost",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const privateLocationId = await ctx.db.insert("privateLocations", {
      organizationId,
      label: "Backyard",
      addr: "42 Garden Street",
      city: "Oakland",
      area: "Rockridge, Oakland",
      lat: 37.84,
      lng: -122.25,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      initials: "SB",
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      followerCount: 0,
      pastShows: [],
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      hostUserId: ownerId,
      mode: "privateBooking",
      privateLocationId,
      area: "Rockridge, Oakland",
      title: "Backyard Celebration",
      desc: "Live music for a private gathering.",
      genres: ["Indie"],
      startsAt: NOW + 14 * DAY_MS,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "none",
      currency: "usd",
      status: "booking",
      slug: "backyard-celebration",
      createdBy: ownerId,
      revision: 2,
      applicationCount: 1,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      setLengthMin: 45,
      guaranteeMinor: 5000,
      required: true,
      status: "open",
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: artistId,
      message: "We are available",
      status: "offered",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "artist_accepted",
      revision: 1,
      startsAt: NOW + 14 * DAY_MS,
      grossMinor: 5000,
      commissionBps: 1000,
      commissionMinor: 500,
      artistNetMinor: 4500,
      currency: "usd",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW,
      artistAcceptedTermsAt: NOW,
      payoutHold: false,
      createdBy: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    return { opportunityId, slotId, applicationId, bookingId, bandId };
  });
  return { t, ...ids };
}

describe("private booking confirmation", () => {
  test("confirms the booking, slot, application, and opportunity without a gig", async () => {
    const f = await setupPrivateBooking();
    vi.setSystemTime(NOW + 1000);

    const confirmed = await f.t.run((ctx) => confirmBooking(ctx, f.bookingId));

    await f.t.run(async (ctx) => {
      const booking = await ctx.db.get(f.bookingId);
      expect(confirmed).toEqual(booking);
      expect(booking).toMatchObject({
        status: "confirmed",
        revision: 2,
        confirmedAt: NOW + 1000,
        updatedAt: NOW + 1000,
      });
      expect(await ctx.db.get(f.slotId)).toMatchObject({
        status: "booked",
        bookingId: f.bookingId,
        bandId: f.bandId,
      });
      expect(await ctx.db.get(f.applicationId)).toMatchObject({
        status: "booked",
        updatedAt: NOW + 1000,
      });
      const opportunity = await ctx.db.get(f.opportunityId);
      expect(opportunity).toMatchObject({
        status: "confirmed",
        revision: 3,
        applicationCount: 0,
        updatedAt: NOW + 1000,
      });
      expect(opportunity?.publicGigId).toBeUndefined();
      expect(await ctx.db.query("gigs").collect()).toEqual([]);
      expect(await ctx.db.query("gigBands").collect()).toEqual([]);
      expect(await ctx.db.query("gigTicketInventory").collect()).toEqual([]);
    });
  });

  test("reopens a confirmed private opportunity after a required-slot cancellation", async () => {
    const f = await setupPrivateBooking();
    await f.t.run((ctx) => confirmBooking(ctx, f.bookingId));
    const before = await f.t.run((ctx) => ctx.db.get(f.opportunityId));
    vi.setSystemTime(NOW + 1000);

    // bookings.cancel/releaseBookingSlot gates this call on publicGigId !== undefined; bookings.ts is out of scope, so exercise the helper directly.
    await f.t.run((ctx) =>
      unpublishOpportunityGig(ctx, f.opportunityId, "required_slot_cancelled"),
    );

    await f.t.run(async (ctx) => {
      expect(await ctx.db.get(f.opportunityId)).toEqual({
        ...before,
        status: "booking",
        revision: 4,
        updatedAt: NOW + 1000,
      });
      expect((await ctx.db.get(f.opportunityId))?.publicGigId).toBeUndefined();
      expect(await ctx.db.query("gigs").collect()).toEqual([]);
      expect(await ctx.db.query("gigBands").collect()).toEqual([]);
      expect(await ctx.db.query("gigTicketInventory").collect()).toEqual([]);
    });
  });

  test("cancels a private opportunity while it is still booking", async () => {
    const f = await setupPrivateBooking();
    const before = await f.t.run((ctx) => ctx.db.get(f.opportunityId));
    vi.setSystemTime(NOW + 1000);

    await f.t.run((ctx) =>
      unpublishOpportunityGig(ctx, f.opportunityId, "opportunity_cancelled"),
    );

    await f.t.run(async (ctx) => {
      expect(await ctx.db.get(f.opportunityId)).toEqual({
        ...before,
        status: "cancelled",
        revision: 3,
        updatedAt: NOW + 1000,
      });
      expect((await ctx.db.get(f.opportunityId))?.publicGigId).toBeUndefined();
      expect(await ctx.db.query("gigs").collect()).toEqual([]);
      expect(await ctx.db.query("gigBands").collect()).toEqual([]);
      expect(await ctx.db.query("gigTicketInventory").collect()).toEqual([]);
    });
  });
});
