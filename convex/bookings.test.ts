/// <reference types="vite/client" />
import type {
  ApiFromModules,
  FilterApi,
  FunctionArgs,
  FunctionReference,
} from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  api as generatedApi,
  internal as generatedInternal,
} from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import * as bookings from "./bookings";
import {
  COMPLETION_DELAY_MS,
  OFFER_TTL_MS,
  REVIEW_WINDOW_MS,
} from "./lib/bookingStatus";
import { feeSnapshot } from "./lib/fees";
import { APPLICATION_ACTIVE_STATUSES } from "./lib/opportunityStatus";
import schema from "./schema";

// Keep references typed while this lane intentionally leaves codegen untouched.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ bookings: typeof bookings }>;
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ bookings: typeof bookings }>,
    FunctionReference<any, "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-04T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const STARTS_AT = NOW + 14 * DAY_MS;
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "admin",
  "otherAdmin",
  "member",
  "stranger",
] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupBookings() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `booking_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `booking_${actor}`,
        name: actor,
        email: `${actor}@booking.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Booking Collective",
      slug: "booking-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager", "finance"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
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
      venueType: "hall",
    });
    const bandFields = {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const otherBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
    });
    for (const [memberBandId, userId, role] of [
      [bandId, users.admin, "admin"],
      [bandId, users.member, "member"],
      [otherBandId, users.otherAdmin, "admin"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId: memberBandId,
        userId,
        role,
      });
    }
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      venueId,
      mode: "publicEvent",
      area: "Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: STARTS_AT,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "open",
      slug: "friday-at-the-hall",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 2,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 0,
      required: true,
      status: "open",
    });
    const supportSlotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 1,
      role: "support",
      guaranteeMinor: 0,
      required: false,
      status: "open",
    });
    const applicationFields = {
      opportunityId,
      slotId,
      status: "shortlisted" as const,
      message: "We are available",
      createdAt: NOW,
      updatedAt: NOW,
    };
    const applicationId = await ctx.db.insert("artistApplications", {
      ...applicationFields,
      bandId,
      submittedBy: users.admin,
    });
    const otherApplicationId = await ctx.db.insert("artistApplications", {
      ...applicationFields,
      bandId: otherBandId,
      submittedBy: users.otherAdmin,
    });
    return {
      users,
      organizationId,
      venueId,
      bandId,
      otherBandId,
      opportunityId,
      slotId,
      supportSlotId,
      applicationId,
      otherApplicationId,
    };
  });

  async function assertCounts() {
    await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(ids.opportunityId);
      const applications = await ctx.db
        .query("artistApplications")
        .withIndex("by_opportunityId_and_bandId", (q) =>
          q.eq("opportunityId", ids.opportunityId),
        )
        .take(100);
      expect(applications.length).toBeLessThan(100);
      expect(opportunity?.applicationCount).toBe(
        applications.filter((row) =>
          APPLICATION_ACTIVE_STATUSES.includes(row.status),
        ).length,
      );
    });
  }
  async function checked<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } finally {
      await assertCounts();
    }
  }
  async function sendOffer(
    fields: Partial<FunctionArgs<typeof api.bookings.sendOffer>> = {},
    actor: Actor = "owner",
  ) {
    return await checked(() =>
      as(actor).mutation(api.bookings.sendOffer, {
        applicationId: ids.applicationId,
        grossMinor: 0,
        cancellationTemplate: "standard",
        ...fields,
      }),
    );
  }
  async function respond(
    bookingId: Id<"bookings">,
    action: "accept" | "decline" = "accept",
    expectedRevision = 1,
    actor: Actor = "admin",
  ) {
    return await checked(() =>
      as(actor).mutation(api.bookings.respond, {
        bookingId,
        action,
        expectedRevision,
      }),
    );
  }
  async function confirm() {
    const offer = await sendOffer();
    const result = await respond(offer.bookingId);
    return { ...offer, ...result };
  }
  async function cancel(
    bookingId: Id<"bookings">,
    actor: Actor,
    expectedRevision = 3,
    actingAs?: "organizer" | "artist",
  ) {
    return await checked(() =>
      as(actor).mutation(api.bookings.cancel, {
        bookingId,
        expectedRevision,
        reason: "  Unable to perform  ",
        as: actingAs,
      }),
    );
  }
  async function seedOffer(revision: number) {
    return await checked(() =>
      t.run(async (ctx) => {
        const terms = {
          ...feeSnapshot(0, 0),
          cancellationTemplate: "standard" as const,
        };
        const bookingId = await ctx.db.insert("bookings", {
          opportunityId: ids.opportunityId,
          slotId: ids.slotId,
          organizationId: ids.organizationId,
          bandId: ids.bandId,
          applicationId: ids.applicationId,
          status: "offer_sent",
          revision,
          startsAt: STARTS_AT,
          ...terms,
          organizerAcceptedTermsAt: NOW,
          payoutHold: false,
          expiresAt: NOW + OFFER_TTL_MS,
          createdBy: ids.users.owner,
          createdAt: NOW,
          updatedAt: NOW,
        });
        const offerId = await ctx.db.insert("bookingOffers", {
          bookingId,
          revision,
          ...terms,
          installments: [],
          sentBy: ids.users.owner,
          sentAt: NOW,
          expiresAt: NOW + OFFER_TTL_MS,
        });
        // Omit currentOfferId to exercise the revision-index fallback.
        await ctx.db.patch(ids.applicationId, { status: "offered" });
        return { bookingId, offerId, revision };
      }),
    );
  }
  await assertCounts();
  return {
    t,
    as,
    ...ids,
    checked,
    sendOffer,
    respond,
    confirm,
    cancel,
    seedOffer,
    readBooking: (id: Id<"bookings">) => t.run((ctx) => ctx.db.get(id)),
    readApplication: (id = ids.applicationId) => t.run((ctx) => ctx.db.get(id)),
    readOpportunity: () => t.run((ctx) => ctx.db.get(ids.opportunityId)),
    readSlot: (id = ids.slotId) => t.run((ctx) => ctx.db.get(id)),
    scheduled: () =>
      t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
  };
}

describe("booking offers", () => {
  test.each(["withdraw", "decline", "expire"] as const)(
    "offered applications cannot bypass booking responses; %s still releases the offer",
    async (response) => {
      const f = await setupBookings();
      const offer = await f.sendOffer();
      await expect(
        f.as("admin").mutation(api.artistApplications.withdraw, {
          applicationId: f.applicationId,
        }),
      ).rejects.toThrow("Respond to the booking offer");
      for (const action of ["under_review", "shortlisted", "declined"] as const) {
        await expect(
          f.as("owner").mutation(api.artistApplications.review, {
            applicationId: f.applicationId,
            action,
          }),
        ).rejects.toThrow("Withdraw the booking offer");
      }
      expect(await f.readApplication()).toMatchObject({ status: "offered" });
      expect(await f.readBooking(offer.bookingId)).toMatchObject({
        status: "offer_sent",
        revision: 1,
      });
      if (response === "withdraw") {
        await f.as("owner").mutation(api.bookings.withdrawOffer, {
          bookingId: offer.bookingId,
          expectedRevision: 1,
        });
      } else if (response === "decline") {
        await f.respond(offer.bookingId, "decline");
      } else {
        vi.setSystemTime(NOW + OFFER_TTL_MS);
        await f.t.mutation(internal.bookings.expireOffer, {
          bookingId: offer.bookingId,
          revision: 1,
        });
      }
      await f.as("admin").mutation(api.artistApplications.withdraw, {
        applicationId: f.applicationId,
      });
      await f.sendOffer({ applicationId: f.otherApplicationId });
    },
  );

  test("sends a zero-fee offer, snapshots terms and schedules expiration without changing the count", async () => {
    const f = await setupBookings();
    const { bookingId, offerId, revision } = await f.sendOffer({
      termsNotes: "  Bring your instruments  ",
      message: "  Join us  ",
    });
    expect(revision).toBe(1);
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "offer_sent",
      revision: 1,
      currentOfferId: offerId,
      opportunityId: f.opportunityId,
      slotId: f.slotId,
      organizationId: f.organizationId,
      bandId: f.bandId,
      applicationId: f.applicationId,
      startsAt: STARTS_AT,
      ...feeSnapshot(0, 0),
      cancellationTemplate: "standard",
      termsNotes: "Bring your instruments",
      organizerAcceptedTermsAt: NOW,
      payoutHold: false,
      expiresAt: NOW + OFFER_TTL_MS,
      createdBy: f.users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
      bookingId,
      revision: 1,
      ...feeSnapshot(0, 0),
      cancellationTemplate: "standard",
      termsNotes: "Bring your instruments",
      message: "Join us",
      installments: [],
      sentBy: f.users.owner,
      sentAt: NOW,
      expiresAt: NOW + OFFER_TTL_MS,
    });
    expect(await f.readApplication()).toMatchObject({
      status: "offered",
      updatedAt: NOW,
    });
    expect(await f.readOpportunity()).toMatchObject({ applicationCount: 2 });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "bookings:expireOffer",
        args: [{ bookingId, revision: 1 }],
        scheduledTime: NOW + OFFER_TTL_MS,
      }),
    );
  });

  test("allows managers and refuses finance members", async () => {
    const f = await setupBookings();
    await expect(f.sendOffer({}, "finance")).rejects.toThrow(
      "Not permitted for this organization",
    );
    await expect(f.sendOffer({}, "manager")).resolves.toMatchObject({
      revision: 1,
    });
  });

  test("requires a shortlisted application", async () => {
    const f = await setupBookings();
    await f.checked(() =>
      f.t.run((ctx) => ctx.db.patch(f.applicationId, { status: "submitted" })),
    );
    await expect(f.sendOffer()).rejects.toThrow(
      "Shortlist the application before sending an offer",
    );
  });

  test.each(["draft", "cancelled", "completed"] as const)(
    "refuses offers on %s opportunities",
    async (status) => {
      const f = await setupBookings();
      await f.t.run((ctx) => ctx.db.patch(f.opportunityId, { status }));
      await expect(f.sendOffer()).rejects.toThrow(
        "This opportunity is not accepting offers",
      );
    },
  );

  test("refuses a second pending offer on the same slot", async () => {
    const f = await setupBookings();
    await f.sendOffer();
    await expect(
      f.sendOffer({ applicationId: f.otherApplicationId }),
    ).rejects.toThrow("This slot already has a pending offer");
  });

  test.each([-1, 0.5, NaN, Infinity])(
    "rejects invalid gross fee %s before the payments flag",
    async (grossMinor) => {
      const f = await setupBookings();
      await expect(f.sendOffer({ grossMinor })).rejects.toThrow(
        "Gross fee must be a non-negative integer",
      );
    },
  );

  test("refuses paid offers while payments are disabled", async () => {
    const f = await setupBookings();
    await expect(f.sendOffer({ grossMinor: 10000 })).rejects.toThrow(
      "Paid offers open once payments are enabled",
    );
  });

  test("requires configured commission and snapshots the paid split on both rows", async () => {
    const f = await setupBookings();
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    await expect(f.sendOffer({ grossMinor: 12345 })).rejects.toThrow(
      "Booking commission is not configured",
    );
    vi.stubEnv("BOOKING_COMMISSION_BPS", "1000");
    const { bookingId, offerId } = await f.sendOffer({ grossMinor: 12345 });
    const fees = {
      grossMinor: 12345,
      commissionBps: 1000,
      commissionMinor: 1235,
      artistNetMinor: 11110,
      currency: "usd",
    };
    expect(await f.readBooking(bookingId)).toMatchObject(fees);
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject(fees);
    expect(await f.respond(bookingId)).toEqual({
      status: "awaiting_payment",
      revision: 3,
    });
    expect(await f.readBooking(bookingId)).toMatchObject({
      artistAcceptedTermsAt: NOW,
      ...fees,
    });
    expect(await f.readSlot()).toMatchObject({ status: "open" });
    expect(await f.readApplication()).toMatchObject({ status: "offered" });
    await expect(
      f.sendOffer({ applicationId: f.otherApplicationId }),
    ).rejects.toThrow("This slot already has a pending offer");
    expect(await f.cancel(bookingId, "admin")).toMatchObject({
      status: "cancelled_by_artist",
      revision: 4,
    });
    expect(await f.readApplication()).toMatchObject({ status: "shortlisted" });
  });

  test.each([0, 12345])(
    "snapshots the opportunity currency on a %s minor-unit offer and booking",
    async (grossMinor) => {
      const f = await setupBookings();
      vi.stubEnv("PAYMENTS_ENABLED", "true");
      vi.stubEnv("BOOKING_COMMISSION_BPS", "1000");
      await f.t.run((ctx) =>
        ctx.db.patch(f.opportunityId, { currency: "eur" }),
      );
      const { bookingId, offerId } = await f.sendOffer({ grossMinor });
      expect(await f.readBooking(bookingId)).toMatchObject({
        grossMinor,
        currency: "eur",
      });
      expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
        grossMinor,
        currency: "eur",
      });
    },
  );

  test.each([
    [
      { termsNotes: "x".repeat(2001) },
      "Terms notes must be at most 2000 characters",
    ],
    [{ message: "x".repeat(1001) }, "Message must be at most 1000 characters"],
  ])("rejects oversized offer notes", async (fields, error) => {
    const f = await setupBookings();
    await expect(f.sendOffer(fields)).rejects.toThrow(error);
  });

  test("declining returns the application to the shortlist and records the responder", async () => {
    const f = await setupBookings();
    const { bookingId, offerId } = await f.sendOffer();
    vi.setSystemTime(NOW + 1000);
    expect(await f.respond(bookingId, "decline")).toEqual({
      status: "declined",
      revision: 2,
    });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "declined",
      revision: 2,
      updatedAt: NOW + 1000,
    });
    expect(await f.readApplication()).toMatchObject({
      status: "shortlisted",
      updatedAt: NOW + 1000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
      response: "declined",
      respondedAt: NOW + 1000,
      respondedBy: f.users.admin,
    });
  });

  test("withdrawing returns the application to the shortlist and supports offers without a pointer", async () => {
    const f = await setupBookings();
    const { bookingId, offerId } = await f.sendOffer();
    await f.t.run((ctx) =>
      ctx.db.patch(bookingId, { currentOfferId: undefined }),
    );
    const result = await f.checked(() =>
      f
        .as("manager")
        .mutation(api.bookings.withdrawOffer, {
          bookingId,
          expectedRevision: 1,
        }),
    );
    expect(result).toEqual({ revision: 2 });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "withdrawn",
      revision: 2,
    });
    expect(await f.readApplication()).toMatchObject({ status: "shortlisted" });
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
      response: "withdrawn",
      respondedAt: NOW,
      respondedBy: f.users.manager,
    });
  });

  test.each(["accept", "decline"] as const)(
    "checks organizer suspension for an artist's %s response",
    async (action) => {
      const f = await setupBookings();
      const { bookingId, offerId } = await f.sendOffer();
      await f.t.run((ctx) =>
        ctx.db.patch(f.organizationId, { status: "suspended" }),
      );
      if (action === "accept") {
        const booking = await f.readBooking(bookingId);
        const offer = await f.t.run((ctx) => ctx.db.get(offerId));
        const scheduled = await f.scheduled();
        await expect(f.respond(bookingId, action)).rejects.toThrow(
          "This organizer is suspended",
        );
        expect(await f.readBooking(bookingId)).toEqual(booking);
        expect(await f.t.run((ctx) => ctx.db.get(offerId))).toEqual(offer);
        expect(await f.scheduled()).toEqual(scheduled);
        expect(await f.readApplication()).toMatchObject({ status: "offered" });
        expect(await f.readSlot()).toMatchObject({ status: "open" });
        expect((await f.readOpportunity())?.publicGigId).toBeUndefined();
      } else {
        expect(await f.respond(bookingId, action)).toEqual({
          status: "declined",
          revision: 2,
        });
        expect(await f.readApplication()).toMatchObject({
          status: "shortlisted",
        });
        expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
          response: "declined",
        });
      }
    },
  );

  test("refuses acceptance after the offer deadline even before its expiry job runs", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.sendOffer();
    vi.setSystemTime(NOW + OFFER_TTL_MS + 1);
    await expect(f.respond(bookingId)).rejects.toThrow(
      "This offer has expired",
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "offer_sent",
      revision: 1,
    });
  });

  test.each(["member", "otherAdmin", "stranger"] as const)(
    "refuses responses by %s",
    async (actor) => {
      const f = await setupBookings();
      const { bookingId } = await f.sendOffer();
      await expect(f.respond(bookingId, "accept", 1, actor)).rejects.toThrow(
        "Not an admin of this band",
      );
    },
  );

  test("expiry ignores stale revisions, expires the matching offer, and ignores repeated jobs", async () => {
    const f = await setupBookings();
    const { bookingId, offerId } = await f.seedOffer(7);
    const before = await f.readBooking(bookingId);
    await f.checked(() =>
      f.t.mutation(internal.bookings.expireOffer, { bookingId, revision: 6 }),
    );
    expect(await f.readBooking(bookingId)).toEqual(before);
    vi.setSystemTime(NOW + OFFER_TTL_MS);
    await f.checked(() =>
      f.t.mutation(internal.bookings.expireOffer, { bookingId, revision: 7 }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "expired",
      revision: 8,
      updatedAt: NOW + OFFER_TTL_MS,
    });
    expect(await f.readApplication()).toMatchObject({ status: "shortlisted" });
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
      response: "expired",
      respondedAt: NOW + OFFER_TTL_MS,
    });
    const after = await f.readBooking(bookingId);
    await f.checked(() =>
      f.t.mutation(internal.bookings.expireOffer, { bookingId, revision: 8 }),
    );
    expect(await f.readBooking(bookingId)).toEqual(after);
  });

  test("refuses stale revisions for respond, withdrawOffer, and cancel", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.sendOffer();
    await expect(f.respond(bookingId, "accept", 0)).rejects.toThrow(
      "Booking changed elsewhere",
    );
    await expect(
      f.checked(() =>
        f
          .as("owner")
          .mutation(api.bookings.withdrawOffer, {
            bookingId,
            expectedRevision: 0,
          }),
      ),
    ).rejects.toThrow("Booking changed elsewhere");
    await f.respond(bookingId);
    await expect(f.cancel(bookingId, "admin", 1)).rejects.toThrow(
      "Booking changed elsewhere",
    );
  });
});

describe("booking confirmation and cancellation", () => {
  test("confirms the free headliner, declines competitors, and publishes the gig", async () => {
    const f = await setupBookings();
    const { bookingId, offerId, status, revision } = await f.confirm();
    expect({ status, revision }).toEqual({ status: "confirmed", revision: 3 });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "confirmed",
      revision: 3,
      artistAcceptedTermsAt: NOW,
      confirmedAt: NOW,
      updatedAt: NOW,
    });
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
      response: "accepted",
      respondedBy: f.users.admin,
      respondedAt: NOW,
    });
    expect(await f.readSlot()).toMatchObject({
      status: "booked",
      bookingId,
      bandId: f.bandId,
    });
    expect(await f.readApplication()).toMatchObject({ status: "booked" });
    expect(await f.readApplication(f.otherApplicationId)).toMatchObject({
      status: "declined",
      declineReason: "slot_filled",
      decidedAt: NOW,
      updatedAt: NOW,
    });
    const opportunity = await f.readOpportunity();
    expect(opportunity).toMatchObject({
      status: "confirmed",
      applicationCount: 0,
    });
    expect(opportunity?.publicGigId).toBeDefined();
    const gig = await f.t.run((ctx) => ctx.db.get(opportunity!.publicGigId!));
    expect(gig).toMatchObject({ lifecycle: "published", lineup: [f.bandId] });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "bookings:markCompleted",
        args: [{ bookingId }],
        scheduledTime: STARTS_AT + COMPLETION_DELAY_MS,
      }),
    );
    await f.checked(() =>
      f.t.mutation(internal.bookings.expireOffer, { bookingId, revision: 1 }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "confirmed",
      revision: 3,
    });
  });

  test("waits to publish until all required slots are booked", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) => ctx.db.patch(f.supportSlotId, { required: true }));
    await f.confirm();
    expect(await f.readOpportunity()).toMatchObject({
      status: "open",
      applicationCount: 0,
    });
    expect((await f.readOpportunity())?.publicGigId).toBeUndefined();
  });

  test.each([
    ["admin", "artist", "cancelled_by_artist", "withdrawn"],
    ["owner", "organizer", "cancelled_by_organizer", "declined"],
  ] as const)(
    "%s cancellation releases the required slot and unpublishes its gig",
    async (actor, side, status, applicationStatus) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      vi.setSystemTime(NOW + 1000);
      expect(await f.cancel(bookingId, actor)).toEqual({ status, revision: 4 });
      expect(await f.readBooking(bookingId)).toMatchObject({
        status,
        revision: 4,
        cancelledBy: side,
        cancelledByUserId: f.users[actor],
        cancelledAt: NOW + 1000,
        cancelReason: "Unable to perform",
        updatedAt: NOW + 1000,
      });
      const slot = await f.readSlot();
      expect(slot).toMatchObject({ status: "open", required: true });
      expect(slot?.bookingId).toBeUndefined();
      expect(slot?.bandId).toBeUndefined();
      expect(await f.readApplication()).toMatchObject({
        status: applicationStatus,
        updatedAt: NOW + 1000,
      });
      const opportunity = await f.readOpportunity();
      expect(opportunity).toMatchObject({
        status: "booking",
        applicationCount: 0,
      });
      expect(
        await f.t.run((ctx) => ctx.db.get(opportunity!.publicGigId!)),
      ).toMatchObject({ lifecycle: "unpublished" });
      const subject = await f.t.run((ctx) =>
        ctx.db.get(side === "artist" ? f.bandId : f.organizationId),
      );
      expect(subject?.reviewSummary).toMatchObject({ cancellations: 1 });
      vi.setSystemTime(STARTS_AT + COMPLETION_DELAY_MS + 1);
      await f.checked(() =>
        f.t.mutation(internal.bookings.markCompleted, { bookingId }),
      );
      expect(await f.readBooking(bookingId)).toMatchObject({
        status,
        revision: 4,
      });
    },
  );

  test.each([
    ["artist", "artist", "cancelled_by_artist", "withdrawn"],
    ["organizer", "organizer", "cancelled_by_organizer", "declined"],
    [undefined, "organizer", "cancelled_by_organizer", "declined"],
  ] as const)(
    "resolves dual-role cancellation with as=%s to %s",
    async (actingAs, side, status, applicationStatus) => {
      const f = await setupBookings();
      await f.t.run((ctx) =>
        ctx.db.insert("bandMembers", {
          bandId: f.bandId,
          userId: f.users.owner,
          role: "admin",
        }),
      );
      const { bookingId } = await f.confirm();
      expect(await f.cancel(bookingId, "owner", 3, actingAs)).toEqual({
        status,
        revision: 4,
      });
      expect(await f.readBooking(bookingId)).toMatchObject({
        status,
        cancelledBy: side,
      });
      expect(await f.readApplication()).toMatchObject({
        status: applicationStatus,
      });
      const band = await f.t.run((ctx) => ctx.db.get(f.bandId));
      const organization = await f.t.run((ctx) => ctx.db.get(f.organizationId));
      expect(band?.reviewSummary?.cancellations ?? 0).toBe(
        side === "artist" ? 1 : 0,
      );
      expect(organization?.reviewSummary?.cancellations ?? 0).toBe(
        side === "organizer" ? 1 : 0,
      );
    },
  );

  test.each([
    ["admin", "organizer", "artist", "cancelled_by_artist"],
    ["owner", "artist", "organizer", "cancelled_by_organizer"],
  ] as const)(
    "falls back to the authorized side when %s requests cancellation as %s",
    async (actor, actingAs, side, status) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      expect(await f.cancel(bookingId, actor, 3, actingAs)).toEqual({
        status,
        revision: 4,
      });
      expect(await f.readBooking(bookingId)).toMatchObject({
        status,
        cancelledBy: side,
      });
    },
  );

  test.each(["organizer", "artist"] as const)(
    "refuses outsider cancellation with as=%s",
    async (actingAs) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      await expect(
        f.cancel(bookingId, "stranger", 3, actingAs),
      ).rejects.toThrow("Not permitted to cancel this booking");
      expect(await f.readBooking(bookingId)).toMatchObject({
        status: "confirmed",
        revision: 3,
      });
    },
  );

  test("allows a platform admin to cancel as the organizer", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.insert("platformAdmins", {
        userId: f.users.stranger,
        grantedAt: NOW,
      }),
    );
    const { bookingId } = await f.confirm();
    expect(await f.cancel(bookingId, "stranger", 3, "organizer")).toEqual({
      status: "cancelled_by_organizer",
      revision: 4,
    });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "cancelled_by_organizer",
      cancelledBy: "organizer",
    });
  });

  test("optional slot cancellation updates the lineup while keeping the gig published", async () => {
    const f = await setupBookings();
    // Book optional support first so headliner confirmation publishes both bands.
    await f.checked(() =>
      f.t.run((ctx) =>
        ctx.db.patch(f.otherApplicationId, { slotId: f.supportSlotId }),
      ),
    );
    const support = await f.sendOffer({ applicationId: f.otherApplicationId });
    await f.respond(support.bookingId, "accept", 1, "otherAdmin");
    await f.confirm();
    const opportunity = await f.readOpportunity();
    expect(
      await f.t.run((ctx) => ctx.db.get(opportunity!.publicGigId!)),
    ).toMatchObject({
      lineup: [f.bandId, f.otherBandId],
      lifecycle: "published",
    });
    await f.cancel(support.bookingId, "otherAdmin");
    expect(await f.readOpportunity()).toMatchObject({
      status: "confirmed",
      publicGigId: opportunity!.publicGigId,
    });
    expect(
      await f.t.run((ctx) => ctx.db.get(opportunity!.publicGigId!)),
    ).toMatchObject({ lineup: [f.bandId], lifecycle: "published" });
  });

  test.each(["owner", "admin"] as const)(
    "checks organizer suspension for cancellation by %s",
    async (actor) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      await f.t.run((ctx) =>
        ctx.db.patch(f.organizationId, { status: "suspended" }),
      );
      if (actor === "owner") {
        const booking = await f.readBooking(bookingId);
        const slot = await f.readSlot();
        const scheduled = await f.scheduled();
        await expect(f.cancel(bookingId, actor)).rejects.toThrow(
          "This organizer is suspended",
        );
        expect(await f.readBooking(bookingId)).toEqual(booking);
        expect(await f.readSlot()).toEqual(slot);
        expect(await f.scheduled()).toEqual(scheduled);
        expect(await f.readApplication()).toMatchObject({ status: "booked" });
      } else {
        expect(await f.cancel(bookingId, actor)).toEqual({
          status: "cancelled_by_artist",
          revision: 4,
        });
        expect(await f.readSlot()).toMatchObject({ status: "open" });
        expect(await f.readApplication()).toMatchObject({ status: "withdrawn" });
      }
    },
  );

  test("accepts a later optional booking on an already-published opportunity", async () => {
    const f = await setupBookings();
    await f.checked(() =>
      f.t.run((ctx) =>
        ctx.db.patch(f.otherApplicationId, { slotId: f.supportSlotId }),
      ),
    );
    await f.confirm();
    const published = await f.readOpportunity();
    const support = await f.sendOffer({ applicationId: f.otherApplicationId });
    expect(
      await f.respond(support.bookingId, "accept", 1, "otherAdmin"),
    ).toEqual({ status: "confirmed", revision: 3 });
    expect(await f.readOpportunity()).toMatchObject({
      status: "confirmed",
      publicGigId: published!.publicGigId,
      applicationCount: 0,
    });
    expect(
      await f.t.run((ctx) => ctx.db.get(published!.publicGigId!)),
    ).toMatchObject({
      lineup: [f.bandId, f.otherBandId],
      lifecycle: "published",
    });
  });

  test.each(["finance", "member", "stranger"] as const)(
    "refuses cancellation by %s",
    async (actor) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      await expect(f.cancel(bookingId, actor)).rejects.toThrow(
        "Not permitted to cancel this booking",
      );
    },
  );

  test.each([
    ["   ", "Cancellation reason is required"],
    ["x".repeat(501), "Cancellation reason must be at most 500 characters"],
  ])("validates cancellation reason", async (reason, error) => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    await expect(
      f.checked(() =>
        f
          .as("admin")
          .mutation(api.bookings.cancel, {
            bookingId,
            expectedRevision: 3,
            reason,
          }),
      ),
    ).rejects.toThrow(error);
  });

  test("completion guards timing and status, updates summaries, and schedules the review deadline", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    await f.checked(() =>
      f.t.mutation(internal.bookings.markCompleted, { bookingId }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "confirmed",
      revision: 3,
    });
    const completedAt = STARTS_AT + COMPLETION_DELAY_MS + 1;
    vi.setSystemTime(completedAt);
    await f.checked(() =>
      f.t.mutation(internal.bookings.markCompleted, { bookingId }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "completed",
      revision: 4,
      completedAt,
      updatedAt: completedAt,
    });
    expect(await f.readOpportunity()).toMatchObject({
      status: "completed",
      updatedAt: completedAt,
    });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "reviews:closeReviewWindow",
        args: [{ bookingId }],
        scheduledTime: completedAt + REVIEW_WINDOW_MS,
      }),
    );
    for (const subjectId of [f.bandId, f.organizationId]) {
      const subject = await f.t.run((ctx) => ctx.db.get(subjectId));
      expect(subject?.reviewSummary).toMatchObject({
        completedBookings: 1,
        cancellations: 0,
      });
    }
    const reviewEmails = (await f.scheduled()).filter(
      (job) =>
        job.name === "emails:send" && job.args[0].kind === "reviewRequested",
    );
    expect(reviewEmails.map((job) => job.args[0].to).sort()).toEqual([
      "admin@booking.test",
      "owner@booking.test",
    ]);
    const before = await f.scheduled();
    await f.checked(() =>
      f.t.mutation(internal.bookings.markCompleted, { bookingId }),
    );
    expect(await f.scheduled()).toEqual(before);
  });

  test("the opportunity completes only after every booked performer finishes", async () => {
    const f = await setupBookings();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.supportSlotId, { required: true });
      await ctx.db.patch(f.otherApplicationId, { slotId: f.supportSlotId });
    });
    const headliner = await f.confirm();
    const support = await f.sendOffer({ applicationId: f.otherApplicationId });
    await f.respond(support.bookingId, "accept", 1, "otherAdmin");
    const confirmed = await f.readOpportunity();
    vi.setSystemTime(STARTS_AT + COMPLETION_DELAY_MS);

    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: headliner.bookingId,
    });
    expect(await f.readOpportunity()).toMatchObject({ status: "confirmed" });
    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: support.bookingId,
    });
    expect(await f.readOpportunity()).toMatchObject({
      status: "completed",
      revision: confirmed!.revision + 1,
    });
    expect(await f.t.run((ctx) => ctx.db.get(confirmed!.publicGigId!)))
      .toMatchObject({ lifecycle: "published", lineup: [f.bandId, f.otherBandId] });
  });

  test("expiring the last pending offer completes an otherwise finished opportunity", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.patch(f.otherApplicationId, { slotId: f.supportSlotId }),
    );
    const headliner = await f.confirm();
    vi.setSystemTime(STARTS_AT - 60 * 60 * 1000);
    const support = await f.sendOffer({ applicationId: f.otherApplicationId });
    vi.setSystemTime(STARTS_AT + COMPLETION_DELAY_MS);
    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: headliner.bookingId,
    });
    expect(await f.readOpportunity()).toMatchObject({ status: "confirmed" });
    vi.setSystemTime(STARTS_AT + OFFER_TTL_MS);
    await f.t.mutation(internal.bookings.expireOffer, {
      bookingId: support.bookingId,
      revision: 1,
    });
    expect(await f.readOpportunity()).toMatchObject({ status: "completed" });
  });

  test("admin completion keeps the confirmed booking's slot", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    const slot = await f.readSlot();
    expect(slot).toMatchObject({ status: "booked", bookingId });
    expect(
      await f.checked(() =>
        f.t.mutation(internal.bookings.adminForceState, {
          bookingId,
          status: "completed",
          reason: "Performance completed",
          dryRun: false,
        }),
      ),
    ).toEqual({ from: "confirmed", to: "completed", applied: true });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "completed",
      revision: 4,
    });
    expect(await f.readSlot()).toEqual(slot);
    expect(await f.readApplication()).toMatchObject({ status: "booked" });
  });

  test("admin dispute records the source and keeps the slot through resolution", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    const slot = await f.readSlot();
    expect(slot).toMatchObject({ status: "booked", bookingId });
    await f.checked(() =>
      f.t.mutation(internal.bookings.adminForceState, {
        bookingId,
        status: "disputed",
        reason: "Review the agreement",
        dryRun: false,
      }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "disputed",
      disputedFromStatus: "confirmed",
      revision: 4,
    });
    expect(await f.readSlot()).toEqual(slot);
    await f.checked(() =>
      f.t.mutation(internal.bookings.adminForceState, {
        bookingId,
        status: "confirmed",
        reason: "Dispute resolved",
        dryRun: false,
      }),
    );
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "confirmed",
      revision: 5,
    });
    expect(await f.readSlot()).toEqual(slot);
    expect(await f.readApplication()).toMatchObject({ status: "booked" });
  });

  test("admin refund releases a paid booking's slot and declines its application", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    await f.t.run((ctx) => ctx.db.patch(bookingId, { status: "paid" }));
    vi.setSystemTime(NOW + 1000);
    expect(
      await f.checked(() =>
        f.t.mutation(internal.bookings.adminForceState, {
          bookingId,
          status: "refunded",
          reason: "Refund approved",
          dryRun: false,
        }),
      ),
    ).toEqual({ from: "paid", to: "refunded", applied: true });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "refunded",
      revision: 4,
      cancelledBy: "admin",
      cancelledAt: NOW + 1000,
      cancelReason: "Refund approved",
    });
    const slot = await f.readSlot();
    expect(slot).toMatchObject({ status: "open" });
    expect(slot?.bookingId).toBeUndefined();
    expect(slot?.bandId).toBeUndefined();
    expect(await f.readApplication()).toMatchObject({
      status: "declined",
      updatedAt: NOW + 1000,
    });
  });

  test("admin override defaults to dry run, rejects illegal edges, and releases a live slot when applied", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.confirm();
    const args = {
      bookingId,
      status: "force_majeure" as const,
      reason: "Venue emergency",
    };
    const before = await f.readBooking(bookingId);
    expect(
      await f.checked(() =>
        f.t.mutation(internal.bookings.adminForceState, args),
      ),
    ).toEqual({ from: "confirmed", to: "force_majeure", applied: false });
    expect(await f.readBooking(bookingId)).toEqual(before);
    await expect(
      f.checked(() =>
        f.t.mutation(internal.bookings.adminForceState, {
          ...args,
          status: "offer_sent",
        }),
      ),
    ).rejects.toThrow("Booking cannot go from confirmed to offer_sent");
    expect(
      await f.checked(() =>
        f.t.mutation(internal.bookings.adminForceState, {
          ...args,
          dryRun: false,
        }),
      ),
    ).toEqual({ from: "confirmed", to: "force_majeure", applied: true });
    expect(await f.readBooking(bookingId)).toMatchObject({
      status: "force_majeure",
      revision: 4,
      cancelledBy: "admin",
      cancelledAt: NOW,
      cancelReason: args.reason,
    });
    expect((await f.readBooking(bookingId))?.cancelledByUserId).toBeUndefined();
    expect(await f.readSlot()).toMatchObject({ status: "open" });
    expect((await f.readSlot())?.bookingId).toBeUndefined();
    expect(await f.readOpportunity()).toMatchObject({ status: "booking" });
  });
});

describe("booking email scheduling", () => {
  test("emails every artist admin with an address and uses the booking context", async () => {
    const f = await setupBookings();
    await f.t.run(async (ctx) => {
      for (const actor of ["manager", "stranger", "otherAdmin"] as const) {
        await ctx.db.insert("bandMembers", {
          bandId: f.bandId,
          userId: f.users[actor],
          role: "admin",
        });
      }
      await ctx.db.patch(f.users.stranger, { email: "  " });
      await ctx.db.delete(f.users.otherAdmin);
    });
    const { bookingId } = await f.sendOffer();
    const emails = (await f.scheduled()).filter(
      (job) => job.name === "emails:send",
    );
    expect(emails.map((job) => job.args[0].to).sort()).toEqual([
      "admin@booking.test",
      "manager@booking.test",
    ]);
    for (const email of emails) {
      expect(email.scheduledTime).toBe(NOW);
      expect(email.args[0].kind).toBe("offerSent");
      for (const value of [
        "Static Bloom",
        "Booking Collective",
        "Friday at the Hall",
        "Neighborhood Hall",
        `/bookings/${bookingId}`,
      ]) {
        expect(email.args[0].text).toContain(value);
      }
      expect(email.args[0].text).not.toContain("Fee:");
      expect(email.args[0].text).not.toContain("Reason:");
    }
  });

  test.each([
    [undefined, "owner@booking.test"],
    ["contact@booking.test", "contact@booking.test"],
    ["  ", undefined],
  ])(
    "resolves the organizer recipient from contact details or an owner fallback",
    async (businessEmail, expectedEmail) => {
      const f = await setupBookings();
      if (businessEmail !== undefined) {
        await f.t.run((ctx) =>
          ctx.db.insert("organizationPrivateDetails", {
            organizationId: f.organizationId,
            businessEmail,
            contactName: "Booking contact",
            stripeChargesEnabled: false,
            stripePayoutsEnabled: false,
            stripeDetailsSubmitted: false,
            verificationDocStorageIds: [],
            updatedAt: NOW,
          }),
        );
      }
      const { bookingId } = await f.sendOffer();
      await f.respond(bookingId, "decline");
      const emails = (await f.scheduled()).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "offerDeclined",
      );
      expect(emails.map((job) => job.args[0].to)).toEqual(
        expectedEmail ? [expectedEmail] : [],
      );
    },
  );

  test("skips organizer mail when the fallback user is missing", async () => {
    const f = await setupBookings();
    const { bookingId } = await f.sendOffer();
    await f.t.run((ctx) => ctx.db.delete(f.users.owner));
    await f.respond(bookingId, "decline");
    expect(
      (await f.scheduled()).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "offerDeclined",
      ),
    ).toEqual([]);
  });

  test.each([
    ["admin", "owner@booking.test"],
    ["owner", "admin@booking.test"],
  ] as const)(
    "emails only the opposite side when %s cancels",
    async (actor, recipient) => {
      const f = await setupBookings();
      const { bookingId } = await f.confirm();
      await f.cancel(bookingId, actor);
      const emails = (await f.scheduled()).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      );
      expect(emails.map((job) => job.args[0].to)).toEqual([recipient]);
      expect(emails[0].args[0].text).toContain("Reason: Unable to perform");
    },
  );
});
