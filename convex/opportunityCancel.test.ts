/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { confirmBooking } from "./lib/bookingConfirm";
import { feeSnapshot } from "./lib/fees";
import { cancelOpportunity } from "./lib/opportunityCancel";
import { APPLICATION_ACTIVE_STATUSES } from "./lib/opportunityStatus";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse("2026-09-04T12:00:00Z");
const CUSTOM_REASON = "Venue approval revoked";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupOpportunity(status: "draft" | "open" = "open") {
  const t = convexTest(schema, modules);
  const asOwner = t.withIdentity({ subject: "cancel_owner" });
  const ids = await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (const actor of ["owner", "manager", "artist"]) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `cancel_${actor}`,
          name: actor,
          email: `${actor}@opportunity.test`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    const [ownerId, managerId, artistId] = userIds;
    const organizationId = await ctx.db.insert("organizations", {
      name: "Cancellation Collective",
      slug: "cancellation-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: 1,
      updatedAt: 1,
    });
    for (const [role, userId] of [
      ["owner", ownerId],
      ["manager", managerId],
    ] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: 1,
      });
    }
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
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
      slug: "static-bloom",
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: artistId,
      role: "admin",
    });
    return { ownerId, managerId, artistId, organizationId, venueId, bandId };
  });
  const { opportunityId } = await asOwner.mutation(
    api.talentOpportunities.create,
    {
      organizationId: ids.organizationId,
      venueId: ids.venueId,
      title: "Friday at the Hall",
      startsAt: NOW + 14 * DAY_MS,
    },
  );
  if (status === "open") {
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
  }
  const slotId = await t.run(async (ctx) => {
    const slot = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", opportunityId),
      )
      .first();
    if (!slot) throw new Error("Fixture slot missing");
    return slot._id;
  });

  async function seedApplications(statuses: Doc<"artistApplications">["status"][]) {
    return await t.run(async (ctx) => {
      const applicationIds: Id<"artistApplications">[] = [];
      for (const status of statuses) {
        applicationIds.push(
          await ctx.db.insert("artistApplications", {
            opportunityId,
            slotId,
            bandId: ids.bandId,
            submittedBy: ids.artistId,
            message: "We are available",
            status,
            createdAt: 1,
            updatedAt: 1,
          }),
        );
      }
      await ctx.db.patch(opportunityId, {
        applicationCount: statuses.filter((status) =>
          APPLICATION_ACTIVE_STATUSES.includes(status),
        ).length,
      });
      return applicationIds;
    });
  }

  async function seedBooking() {
    const [applicationId] = await seedApplications(["offered"]);
    return await t.run(async (ctx) => {
      const terms = {
        ...feeSnapshot(0, 0, "usd"),
        cancellationTemplate: "standard" as const,
      };
      const bookingId = await ctx.db.insert("bookings", {
        opportunityId,
        slotId,
        organizationId: ids.organizationId,
        bandId: ids.bandId,
        applicationId,
        status: "offer_sent",
        revision: 1,
        startsAt: NOW + 14 * DAY_MS,
        ...terms,
        organizerAcceptedTermsAt: NOW,
        payoutHold: false,
        expiresAt: NOW + 3 * DAY_MS,
        createdBy: ids.ownerId,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const offerId = await ctx.db.insert("bookingOffers", {
        bookingId,
        revision: 1,
        ...terms,
        installments: [],
        sentBy: ids.ownerId,
        sentAt: NOW,
        expiresAt: NOW + 3 * DAY_MS,
      });
      await ctx.db.patch(bookingId, { currentOfferId: offerId });
      return { bookingId, offerId, applicationId };
    });
  }

  async function cancel(actorUserId: Id<"users"> = ids.ownerId) {
    await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      await cancelOpportunity(ctx, {
        opportunity,
        actorUserId,
        reason: CUSTOM_REASON,
        now: Date.now(),
      });
    });
  }

  async function readOpportunity() {
    return await t.run(async (ctx) => ({
      opportunity: await ctx.db.get(opportunityId),
      slots: await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .take(20),
    }));
  }

  return {
    t,
    ...ids,
    opportunityId,
    slotId,
    seedApplications,
    seedBooking,
    cancel,
    readOpportunity,
  };
}

async function setupConfirmedBooking() {
  const f = await setupOpportunity();
  const booking = await f.seedBooking();
  await f.t.run(async (ctx) => {
    await ctx.db.patch(booking.bookingId, { status: "artist_accepted", revision: 2 });
    await ctx.db.patch(booking.offerId, {
      response: "accepted",
      respondedAt: NOW,
      respondedBy: f.artistId,
    });
    await confirmBooking(ctx, booking.bookingId);
  });
  const before = await f.readOpportunity();
  const gigId = before.opportunity?.publicGigId;
  if (!gigId) throw new Error("Fixture public gig missing");
  return { ...f, ...booking, before, gigId };
}

describe("cancelOpportunity", () => {
  test.each(["pending", "granted", "declined", "withdrawn", "revoked"] as const)(
    "withdraws %s consent only when it is still active",
    async (status) => {
      const f = await setupOpportunity();
      const consentId = await f.t.run(async (ctx) => {
        const venueOrganizationId = await ctx.db.insert("organizations", {
          name: "Venue Operator",
          slug: "venue-operator",
          orgType: "venueOperator",
          status: "verified",
          ownerUserId: f.managerId,
          createdAt: NOW,
          updatedAt: NOW,
        });
        await ctx.db.patch(f.venueId, {
          managedByOrganizationId: venueOrganizationId,
        });
        return await ctx.db.insert("venueConsents", {
          opportunityId: f.opportunityId,
          venueId: f.venueId,
          venueOrganizationId,
          requestingOrganizationId: f.organizationId,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        });
      });
      const consentBefore = await f.t.run((ctx) => ctx.db.get(consentId));
      vi.setSystemTime(NOW + 1000);

      await f.cancel();

      const consent = await f.t.run((ctx) => ctx.db.get(consentId));
      if (status === "pending" || status === "granted") {
        expect(consent).toEqual({
          ...consentBefore,
          status: "withdrawn",
          updatedAt: NOW + 1000,
        });
      } else {
        expect(consent).toEqual(consentBefore);
      }
      expect((await f.readOpportunity()).opportunity).toMatchObject({
        status: "cancelled",
        updatedAt: NOW + 1000,
      });
    },
  );

  test("declines active applications with the actor and cancels only open slots", async () => {
    const f = await setupOpportunity("draft");
    await f.t.run(async (ctx) => {
      await ctx.db.insert("opportunitySlots", {
        opportunityId: f.opportunityId,
        order: 1,
        role: "support",
        guaranteeMinor: 5000,
        required: true,
        status: "booked",
        bandId: f.bandId,
      });
      await ctx.db.insert("opportunitySlots", {
        opportunityId: f.opportunityId,
        order: 2,
        role: "support",
        guaranteeMinor: 5000,
        required: false,
        status: "cancelled",
      });
    });
    const applicationIds = await f.seedApplications([
      ...APPLICATION_ACTIVE_STATUSES,
      "booked",
      "declined",
      "withdrawn",
      "expired",
    ]);
    const before = await f.readOpportunity();
    const applicationsBefore = await f.t.run((ctx) =>
      Promise.all(applicationIds.map((id) => ctx.db.get(id))),
    );

    await f.cancel();

    const applications = await f.t.run((ctx) =>
      Promise.all(applicationIds.map((id) => ctx.db.get(id))),
    );
    for (const application of applications.slice(0, 4)) {
      expect(application).toMatchObject({
        status: "declined",
        decidedBy: f.ownerId,
        decidedAt: NOW,
        updatedAt: NOW,
      });
    }
    expect(applications.slice(4)).toEqual(applicationsBefore.slice(4));
    const result = await f.readOpportunity();
    expect(result.opportunity).toMatchObject({
      status: "cancelled",
      revision: 2,
      applicationCount: 0,
      updatedAt: NOW,
    });
    expect(result.slots.map((slot) => slot.status)).toEqual([
      "cancelled",
      "booked",
      "cancelled",
    ]);
    expect(result.slots.slice(1)).toEqual(before.slots.slice(1));
    await expect(f.cancel()).rejects.toThrow(
      "Opportunity cannot go from cancelled to cancelled",
    );
    expect(await f.readOpportunity()).toEqual(result);
  });

  test.each([
    ["offer_sent", true],
    ["offer_sent", false],
    ["artist_accepted", true],
    ["awaiting_payment", true],
  ] as const)(
    "withdraws a %s booking and declines its application (offer pointer: %s)",
    async (status, hasOfferPointer) => {
      const f = await setupOpportunity();
      const { bookingId, offerId, applicationId } = await f.seedBooking();
      await f.t.run((ctx) =>
        ctx.db.patch(bookingId, {
          status,
          currentOfferId: hasOfferPointer ? offerId : undefined,
        }),
      );
      vi.setSystemTime(NOW + 1000);

      await f.cancel(f.managerId);

      const booking = await f.t.run((ctx) => ctx.db.get(bookingId));
      expect(booking).toMatchObject({
        status: "withdrawn",
        cancelledBy: "organizer",
        cancelledByUserId: f.managerId,
        cancelledAt: NOW + 1000,
        cancelReason: CUSTOM_REASON,
        revision: 2,
        updatedAt: NOW + 1000,
      });
      expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
        response: "withdrawn",
        respondedAt: NOW + 1000,
        respondedBy: f.managerId,
      });
      // The booking withdrawal shortlists it before the final pass declines it.
      expect(await f.t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
        status: "declined",
        decidedBy: f.managerId,
        decidedAt: NOW + 1000,
        updatedAt: NOW + 1000,
      });
      const result = await f.readOpportunity();
      expect(result.opportunity).toMatchObject({
        status: "cancelled",
        revision: 3,
        applicationCount: 0,
        updatedAt: NOW + 1000,
      });
      expect(result.slots[0].status).toBe("cancelled");
      const scheduled = await f.t.run((ctx) =>
        ctx.db.system.query("_scheduled_functions").take(100),
      );
      const emails = scheduled.filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      );
      expect(emails.map((job) => job.args[0].to)).toEqual([
        "artist@opportunity.test",
      ]);
      expect(emails[0].scheduledTime).toBe(NOW + 1000);
      expect(emails[0].args[0].text).toContain(`Reason: ${CUSTOM_REASON}`);
      expect(emails[0].args[0].text).toContain(CUSTOM_REASON);
      await expect(f.cancel(f.managerId)).rejects.toThrow(
        "Opportunity cannot go from cancelled to cancelled",
      );
      expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toEqual(booking);
      expect(
        await f.t.run((ctx) =>
          ctx.db.system.query("_scheduled_functions").take(100),
        ),
      ).toEqual(scheduled);
    },
  );

  test("winds down a confirmed booking and cancels its required-slot gig", async () => {
    const f = await setupConfirmedBooking();
    expect(f.before.slots[0]).toMatchObject({
      status: "booked",
      required: true,
      bookingId: f.bookingId,
      bandId: f.bandId,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.gigId))).toMatchObject({
      lifecycle: "published",
    });
    const offerBefore = await f.t.run((ctx) => ctx.db.get(f.offerId));
    vi.setSystemTime(NOW + 1000);

    await f.cancel();

    expect(await f.t.run((ctx) => ctx.db.get(f.bookingId))).toMatchObject({
      status: "cancelled_by_organizer",
      cancelledBy: "organizer",
      cancelledByUserId: f.ownerId,
      cancelledAt: NOW + 1000,
      cancelReason: CUSTOM_REASON,
      revision: 4,
      updatedAt: NOW + 1000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.offerId))).toEqual(offerBefore);
    const result = await f.readOpportunity();
    expect(result.slots[0]).toMatchObject({ status: "cancelled" });
    expect(result.slots[0].bookingId).toBeUndefined();
    expect(result.slots[0].bandId).toBeUndefined();
    expect(await f.t.run((ctx) => ctx.db.get(f.applicationId))).toMatchObject({
      status: "declined",
      updatedAt: NOW + 1000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.gigId))).toMatchObject({
      lifecycle: "cancelled",
      discoveryListingReady: false,
    });
    expect(result.opportunity).toMatchObject({
      status: "cancelled",
      publicGigId: f.gigId,
      revision: f.before.opportunity!.revision + 1,
      applicationCount: 0,
      updatedAt: NOW + 1000,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      ),
    );
    expect(emails.map((job) => job.args[0].to)).toEqual([
      "artist@opportunity.test",
    ]);
    expect(emails[0].scheduledTime).toBe(NOW + 1000);
    expect(emails[0].args[0].text).toContain(`Reason: ${CUSTOM_REASON}`);
    expect(emails[0].args[0].text).toContain(CUSTOM_REASON);
  });

  test("requests ticket refunds and emails buyers for a paid-ticket gig", async () => {
    const f = await setupConfirmedBooking();
    const orderId = await f.t.run(async (ctx) => {
      await ctx.db.patch(f.gigId, {
        ticketing: "paid",
        ticketPriceMinor: 2000,
        ticketCurrency: "usd",
        ticketCapacity: 20,
      });
      const buyerUserId = await ctx.db.insert("users", {
        clerkId: "cancel_ticket_buyer",
        name: "Buyer",
        email: "buyer@tickets.test",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("gigTicketInventory", {
        gigId: f.gigId,
        organizationId: f.organizationId,
        capacity: 20,
        reserved: 0,
        sold: 3,
        updatedAt: NOW,
      });
      return await ctx.db.insert("ticketOrders", {
        gigId: f.gigId,
        organizationId: f.organizationId,
        buyerUserId,
        quantity: 3,
        unitPriceMinor: 2000,
        unitFeeMinor: 130,
        subtotalMinor: 6000,
        feeMinor: 390,
        totalMinor: 6390,
        currency: "usd",
        status: "paid",
        reservedUntil: NOW,
        stripePaymentIntentId: "pi_cancelled_event",
        paidAt: NOW,
        attempt: 1,
        refundedMinor: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
    });

    await f.cancel();

    expect((await f.readOpportunity()).opportunity?.status).toBe("cancelled");
    expect(await f.t.run((ctx) => ctx.db.get(f.gigId))).toMatchObject({
      lifecycle: "cancelled",
      discoveryListingReady: false,
    });
    const refunds = await f.t.run((ctx) =>
      ctx.db
        .query("ticketRefunds")
        .withIndex("by_orderId", (q) => q.eq("orderId", orderId))
        .take(10),
    );
    expect(refunds).toHaveLength(1);
    expect(refunds[0]).toMatchObject({
      orderId,
      status: "pending",
      reason: "event_cancelled",
      amountMinor: 6390,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "ticketRefunded",
      ),
    );
    expect(emails.map((job) => job.args[0].to)).toEqual(["buyer@tickets.test"]);
  });
});
