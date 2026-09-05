/// <reference types="vite/client" />
import type { ApiFromModules } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import * as bookingsRead from "./bookingsRead";
import {
  BOOKING_ACTIVE_STATUSES,
  BOOKING_TRANSITIONS,
  type BookingStatus,
} from "./lib/bookingStatus";
import schema from "./schema";

// Keep references typed while intentionally leaving codegen untouched.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ bookingsRead: typeof bookingsRead }>;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-04T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const STARTS_AT = NOW + 14 * DAY_MS;
const DOORS_AT = STARTS_AT - 60 * 60 * 1000;
const EXACT_ADDRESS = "42 Secret Alley, Oakland";
const BUSINESS_EMAIL = "booking-office@example.test";
const APPLICANT_EMAIL = "bandadmin@example.test";
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "bandAdmin",
  "bandMember",
  "otherBandAdmin",
  "outsider",
  "platformAdmin",
] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

async function setupBookings(overrides: { status?: BookingStatus } = {}) {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) =>
    t.withIdentity({ subject: `booking_read_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `booking_read_${actor}`,
        name: actor,
        email:
          actor === "bandAdmin" ? APPLICANT_EMAIL : `${actor}@example.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager", "finance", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationPrivateId = await ctx.db.insert(
      "organizationPrivateDetails",
      {
        organizationId,
        businessEmail: BUSINESS_EMAIL,
        contactName: "Booking Office",
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: [],
        updatedAt: NOW,
      },
    );
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      slug: "neighborhood-hall",
      area: "Oakland",
      addr: "Uptown, Oakland",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      managedByOrganizationId: organizationId,
      status: "verified",
      addressDisclosure: "onTicket",
      approxLabel: "Uptown, Oakland",
      venueType: "hall",
    });
    const venuePrivateId = await ctx.db.insert("venuePrivateDetails", {
      venueId,
      addr: EXACT_ADDRESS,
      normalizedAddr: EXACT_ADDRESS.toLowerCase(),
      lat: 37.8058,
      lng: -122.2705,
      loadInNotes: "Use the side entrance.",
      capacity: 200,
      updatedAt: NOW,
    });
    const bandFields = {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 12,
      pastShows: [],
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const otherBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
    });
    for (const [memberBandId, userId, role] of [
      [bandId, users.bandAdmin, "admin"],
      [bandId, users.bandMember, "member"],
      [otherBandId, users.otherBandAdmin, "admin"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId: memberBandId,
        userId,
        role,
      });
    }
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "publicEvent",
      venueId,
      area: "Uptown, Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: STARTS_AT,
      doorsAt: DOORS_AT,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "confirmed",
      slug: "friday-at-the-hall",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 0,
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
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.bandAdmin,
      message: "We are available",
      status: "booked",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const fee = {
      grossMinor: 5000,
      commissionBps: 1000,
      commissionMinor: 500,
      artistNetMinor: 4500,
      currency: "usd",
    };
    const bookingFields = {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: overrides.status ?? "confirmed",
      revision: 2,
      startsAt: STARTS_AT,
      ...fee,
      cancellationTemplate: "standard" as const,
      organizerAcceptedTermsAt: NOW,
      payoutHold: false,
      createdBy: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const bookingId = await ctx.db.insert("bookings", bookingFields);
    const offerId = await ctx.db.insert("bookingOffers", {
      bookingId,
      revision: bookingFields.revision,
      ...fee,
      cancellationTemplate: bookingFields.cancellationTemplate,
      installments: [],
      message: "Looking forward to the show!",
      sentBy: users.owner,
      sentAt: NOW,
      expiresAt: NOW + 3 * DAY_MS,
    });
    await ctx.db.patch(bookingId, { currentOfferId: offerId });
    await ctx.db.patch(slotId, { bookingId });
    const gigId = await ctx.db.insert("gigs", {
      title: "Friday at the Hall",
      slug: "friday-public-show",
      venueId,
      price: 0,
      startsAt: STARTS_AT,
      doorsTime: "19:00",
      flyKey: "xerox",
      lineup: [bandId],
      genres: ["Indie"],
      desc: "An evening of local music.",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      cap: "200",
      goingCount: 0,
      ownerKind: "organization",
      createdByOrganization: organizationId,
      opportunityId,
      lifecycle: "published",
      // Deliberately different: the payload must read the opportunity's time.
      doorsAt: DOORS_AT - 1000,
    });
    await ctx.db.patch(opportunityId, { publicGigId: gigId });
    return {
      users,
      organizationId,
      organizationPrivateId,
      venueId,
      venuePrivateId,
      bandId,
      otherBandId,
      opportunityId,
      slotId,
      applicationId,
      bookingId,
      offerId,
      gigId,
      bookingFields,
    };
  });
  return { t, as, ...ids };
}

describe("bookings read: get", () => {
  test("owner receives the booking contract, private address, and applicant email", async () => {
    const f = await setupBookings();
    const payload = await f.as("owner").query(api.bookingsRead.get, {
      bookingId: f.bookingId,
    });
    expect(payload).toEqual({
      _id: f.bookingId,
      opportunityId: f.opportunityId,
      opportunityTitle: "Friday at the Hall",
      opportunitySlug: "friday-at-the-hall",
      slotId: f.slotId,
      slotRole: "headliner",
      slotRequired: true,
      organizationId: f.organizationId,
      organizationName: "Opportunity Collective",
      bandId: f.bandId,
      bandName: "Static Bloom",
      bandSlug: "static-bloom",
      applicationId: f.applicationId,
      status: "confirmed",
      revision: 2,
      startsAt: STARTS_AT,
      doorsAt: DOORS_AT,
      fee: {
        grossMinor: 5000,
        commissionBps: 1000,
        commissionMinor: 500,
        artistNetMinor: 4500,
        currency: "usd",
      },
      cancellationTemplate: "standard",
      termsNotes: null,
      organizerAcceptedTermsAt: NOW,
      artistAcceptedTermsAt: null,
      confirmedAt: null,
      completedAt: null,
      cancelledAt: null,
      cancelledBy: null,
      cancelReason: null,
      expiresAt: null,
      currentOffer: {
        revision: 2,
        message: "Looking forward to the show!",
        sentAt: NOW,
        expiresAt: NOW + 3 * DAY_MS,
        response: null,
        installments: [],
      },
      venue: {
        _id: f.venueId,
        name: "Neighborhood Hall",
        slug: "neighborhood-hall",
        approxLabel: "Uptown, Oakland",
        exactAddress: EXACT_ADDRESS,
      },
      publicGigId: f.gigId,
      publicGigSlug: "friday-public-show",
      counterpartyEmail: APPLICANT_EMAIL,
      viewerSide: "organizer",
    });
  });

  test.each([
    ["manager", APPLICANT_EMAIL],
    ["finance", null],
    ["door", null],
    ["platformAdmin", APPLICANT_EMAIL],
  ] as const)(
    "%s receives organizer access with the appropriate contact visibility",
    async (actor, email) => {
      const f = await setupBookings();
      expect(
        await f
          .as(actor)
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toMatchObject({
        venue: { exactAddress: EXACT_ADDRESS },
        counterpartyEmail: email,
        viewerSide: "organizer",
      });
    },
  );

  test.each([
    "offer_sent",
    "awaiting_payment",
    "disputed",
    "cancelled_by_artist",
  ] as const)(
    "band admin cannot see private address or business email for a %s booking",
    async (status) => {
      const f = await setupBookings({ status });
      expect(
        await f
          .as("bandAdmin")
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toMatchObject({
        venue: { exactAddress: null },
        counterpartyEmail: null,
        viewerSide: "artist",
      });
    },
  );

  test.each(["confirmed", "completed", "paid"] as const)(
    "band admin sees private address and business email for a %s booking",
    async (status) => {
      const f = await setupBookings({ status });
      expect(
        await f
          .as("bandAdmin")
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toMatchObject({
        venue: { exactAddress: EXACT_ADDRESS },
        counterpartyEmail: BUSINESS_EMAIL,
        viewerSide: "artist",
      });
    },
  );

  test.each(["outsider", "otherBandAdmin", "bandMember"] as const)(
    "%s cannot read another party's booking",
    async (actor) => {
      const f = await setupBookings();
      expect(
        await f
          .as(actor)
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toBeNull();
    },
  );

  test("returns null for signed-out, unknown, deleted users and missing bookings", async () => {
    const f = await setupBookings();
    const args = { bookingId: f.bookingId };
    expect(await f.t.query(api.bookingsRead.get, args)).toBeNull();
    expect(
      await f.t
        .withIdentity({ subject: "unknown" })
        .query(api.bookingsRead.get, args),
    ).toBeNull();
    await f.t.run((ctx) => ctx.db.patch(f.users.bandAdmin, { deletedAt: NOW }));
    expect(
      await f.as("bandAdmin").query(api.bookingsRead.get, args),
    ).toBeNull();
    await f.t.run((ctx) => ctx.db.delete(f.bookingId));
    expect(await f.as("owner").query(api.bookingsRead.get, args)).toBeNull();
  });

  test("does not use a different live booking at the same venue to disclose this booking's address", async () => {
    const f = await setupBookings({ status: "offer_sent" });
    await f.t.run((ctx) =>
      ctx.db.insert("bookings", {
        ...f.bookingFields,
        status: "confirmed",
      }),
    );
    expect(
      await f
        .as("bandAdmin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      venue: { exactAddress: null },
      counterpartyEmail: null,
    });
  });

  test("a public venue discloses its address before confirmation but keeps business email private", async () => {
    const f = await setupBookings({ status: "offer_sent" });
    await f.t.run((ctx) =>
      ctx.db.patch(f.venueId, {
        addressDisclosure: "public",
        addr: EXACT_ADDRESS,
      }),
    );
    expect(
      await f
        .as("bandAdmin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      venue: { exactAddress: EXACT_ADDRESS },
      counterpartyEmail: null,
    });
  });

  test("a public venue uses its own address before confirmation without private details", async () => {
    const f = await setupBookings({ status: "offer_sent" });
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.venueId, {
        addressDisclosure: "public",
        addr: EXACT_ADDRESS,
      });
      await ctx.db.delete(f.venuePrivateId);
    });
    expect(
      await f
        .as("bandAdmin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      venue: { exactAddress: EXACT_ADDRESS },
      counterpartyEmail: null,
      viewerSide: "artist",
    });
  });

  test("organization membership takes precedence over band and platform admin access", async () => {
    const f = await setupBookings();
    await f.t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", {
        bandId: f.bandId,
        userId: f.users.door,
        role: "admin",
      });
      await ctx.db.insert("platformAdmins", {
        userId: f.users.door,
        grantedAt: NOW,
      });
    });
    expect(
      await f
        .as("door")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({ viewerSide: "organizer", counterpartyEmail: null });
  });

  test("band admin access takes precedence over platform admin access", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.insert("platformAdmins", {
        userId: f.users.bandAdmin,
        grantedAt: NOW,
      }),
    );
    expect(
      await f
        .as("bandAdmin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      viewerSide: "artist",
      counterpartyEmail: BUSINESS_EMAIL,
    });
  });

  test("normalizes absent optional links and venue details to null", async () => {
    const f = await setupBookings();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.bookingId, { currentOfferId: undefined });
      await ctx.db.patch(f.opportunityId, {
        publicGigId: undefined,
        doorsAt: undefined,
      });
      await ctx.db.patch(f.venueId, {
        slug: undefined,
        approxLabel: undefined,
      });
      await ctx.db.delete(f.venuePrivateId);
    });
    expect(
      await f
        .as("owner")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      currentOffer: null,
      publicGigId: null,
      publicGigSlug: null,
      doorsAt: null,
      venue: { slug: null, approxLabel: null, exactAddress: null },
    });
  });

  test("preserves a linked gig id when its document is missing", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) => ctx.db.delete(f.gigId));
    expect(
      await f
        .as("owner")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({ publicGigId: f.gigId, publicGigSlug: null });
  });

  test("copies optional terms, offer response and installment amounts without recomputing them", async () => {
    const f = await setupBookings();
    const terms = {
      termsNotes: "Backline provided",
      artistAcceptedTermsAt: NOW + 1,
      confirmedAt: NOW + 2,
      completedAt: NOW + 3,
      cancelledAt: NOW + 4,
      cancelledBy: "admin" as const,
      cancelReason: "Event cancelled",
      expiresAt: NOW + 5,
    };
    const installments = [
      { label: "Deposit", amountMinor: 1234, dueAt: NOW + DAY_MS },
    ];
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.bookingId, terms);
      await ctx.db.patch(f.offerId, {
        response: "accepted",
        message: undefined,
        installments,
      });
    });
    expect(
      await f
        .as("owner")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      ...terms,
      currentOffer: { response: "accepted", message: null, installments },
    });
  });

  test.each(["application", "submitter"] as const)(
    "missing %s yields no applicant email",
    async (missing) => {
      const f = await setupBookings();
      await f.t.run((ctx) =>
        ctx.db.delete(
          missing === "application" ? f.applicationId : f.users.bandAdmin,
        ),
      );
      expect(
        await f
          .as("owner")
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toMatchObject({ counterpartyEmail: null });
    },
  );

  test("missing organization private details yields no business email", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) => ctx.db.delete(f.organizationPrivateId));
    expect(
      await f
        .as("bandAdmin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({ counterpartyEmail: null });
  });

  test.each([
    ["opportunityId", "opportunity"],
    ["slotId", "slot"],
    ["organizationId", "organization"],
    ["bandId", "band"],
    ["venueId", "venue"],
    ["offerId", "current offer"],
  ] as const)(
    "reports a missing %s as a booking invariant violation",
    async (field, label) => {
      const f = await setupBookings();
      await f.t.run((ctx) => ctx.db.delete(f[field]));
      await expect(
        f.as("owner").query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).rejects.toThrow(`Booking ${f.bookingId} references a missing ${label}`);
    },
  );

  test("reports an opportunity without a venue as a booking invariant violation", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.patch(f.opportunityId, { venueId: undefined }),
    );
    await expect(
      f.as("owner").query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).rejects.toThrow(
      `Booking ${f.bookingId} has an opportunity without a venue`,
    );
  });
});

describe("bookings read: lists", () => {
  test("forOrganization filters statuses and merges results newest first", async () => {
    const f = await setupBookings();
    const [newerId, olderId] = await f.t.run(async (ctx) => {
      const newerId = await ctx.db.insert("bookings", {
        ...f.bookingFields,
        status: "offer_sent",
        startsAt: STARTS_AT + DAY_MS,
      });
      const olderId = await ctx.db.insert("bookings", {
        ...f.bookingFields,
        status: "paid",
        startsAt: STARTS_AT - DAY_MS,
      });
      return [newerId, olderId];
    });
    const args = { organizationId: f.organizationId };
    const filtered = await f
      .as("owner")
      .query(api.bookingsRead.forOrganization, {
        ...args,
        statuses: ["confirmed", "paid"],
      });
    expect(filtered.map((row) => [row._id, row.status])).toEqual([
      [f.bookingId, "confirmed"],
      [olderId, "paid"],
    ]);
    const all = await f
      .as("owner")
      .query(api.bookingsRead.forOrganization, args);
    expect(all.map((row) => row._id)).toEqual([newerId, f.bookingId, olderId]);
    expect(all.every((row) => row.viewerSide === "organizer")).toBe(true);
    expect(
      await f
        .as("owner")
        .query(api.bookingsRead.forOrganization, { ...args, statuses: [] }),
    ).toEqual([]);
  });

  test.each(["owner", "manager", "finance", "door", "platformAdmin"] as const)(
    "suspended organization remains readable by %s, sees its own venue address, but never the counterparty email",
    async (actor) => {
      const f = await setupBookings();
      await f.t.run((ctx) =>
        ctx.db.patch(f.organizationId, { status: "suspended" }),
      );
      const payload = await f
        .as(actor)
        .query(api.bookingsRead.get, { bookingId: f.bookingId });
      expect(payload).toMatchObject({
        viewerSide: "organizer",
        venue: { exactAddress: EXACT_ADDRESS },
        counterpartyEmail: null,
      });
      expect(
        await f
          .as(actor)
          .query(api.bookingsRead.forOrganization, {
            organizationId: f.organizationId,
          }),
      ).toEqual([payload]);
    },
  );

  test("a suspended organization does not change the artist's live-booking contact access", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.patch(f.organizationId, { status: "suspended" }),
    );
    expect(
      await f.as("bandAdmin").query(api.bookingsRead.forBand, {
        bandId: f.bandId,
      }),
    ).toMatchObject([
      {
        _id: f.bookingId,
        venue: { exactAddress: EXACT_ADDRESS },
        counterpartyEmail: BUSINESS_EMAIL,
      },
    ]);
  });

  test("platform admin can list bookings without organization membership", async () => {
    const f = await setupBookings();
    const result = await f
      .as("platformAdmin")
      .query(api.bookingsRead.forOrganization, {
        organizationId: f.organizationId,
      });
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      _id: f.bookingId,
      viewerSide: "organizer",
      counterpartyEmail: APPLICANT_EMAIL,
      venue: { exactAddress: EXACT_ADDRESS },
    });
  });

  test.each(["bandMember", "otherBandAdmin", "outsider"] as const)(
    "forBand rejects %s who is not an admin of the requested band",
    async (actor) => {
      const f = await setupBookings();
      await expect(
        f.as(actor).query(api.bookingsRead.forBand, { bandId: f.bandId }),
      ).rejects.toThrow("Not an admin of this band");
    },
  );

  test("forBand lists the band's bookings for its admin", async () => {
    const f = await setupBookings();
    const result = await f
      .as("bandAdmin")
      .query(api.bookingsRead.forBand, { bandId: f.bandId });
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      _id: f.bookingId,
      bandId: f.bandId,
      viewerSide: "artist",
      venue: { exactAddress: EXACT_ADDRESS },
      counterpartyEmail: BUSINESS_EMAIL,
    });
    expect(
      await f
        .as("otherBandAdmin")
        .query(api.bookingsRead.forBand, { bandId: f.otherBandId }),
    ).toEqual([]);
  });

  test("both lists include every status on request, default to active statuses, and exclude unrelated bookings", async () => {
    const f = await setupBookings();
    const statuses = Object.keys(BOOKING_TRANSITIONS) as BookingStatus[];
    const ids = await f.t.run(async (ctx) => {
      await ctx.db.delete(f.bookingId);
      const ids: Id<"bookings">[] = [];
      for (const [index, status] of statuses.entries()) {
        ids.push(
          await ctx.db.insert("bookings", {
            ...f.bookingFields,
            status,
            startsAt: STARTS_AT + index * DAY_MS,
          }),
        );
      }
      const otherOrganizationId = await ctx.db.insert("organizations", {
        name: "Other Organizer",
        slug: "other-organizer",
        orgType: "promoter",
        status: "verified",
        ownerUserId: f.users.outsider,
        createdAt: NOW,
        updatedAt: NOW,
      });
      await ctx.db.insert("bookings", {
        ...f.bookingFields,
        bandId: f.otherBandId,
        organizationId: otherOrganizationId,
        startsAt: STARTS_AT + 100 * DAY_MS,
      });
      return ids;
    });
    const organizationBookings = await f
      .as("owner")
      .query(api.bookingsRead.forOrganization, {
        organizationId: f.organizationId,
        statuses,
      });
    const bandBookings = await f
      .as("bandAdmin")
      .query(api.bookingsRead.forBand, { bandId: f.bandId, statuses });
    expect(organizationBookings.map((row) => row._id)).toEqual(
      [...ids].reverse(),
    );
    expect(bandBookings.map((row) => row._id)).toEqual([...ids].reverse());
    const activeIds = ids
      .filter((_, index) => BOOKING_ACTIVE_STATUSES.includes(statuses[index]))
      .reverse();
    const defaultOrganizationBookings = await f
      .as("owner")
      .query(api.bookingsRead.forOrganization, {
        organizationId: f.organizationId,
      });
    const defaultBandBookings = await f
      .as("bandAdmin")
      .query(api.bookingsRead.forBand, { bandId: f.bandId });
    expect(defaultOrganizationBookings.map((row) => row._id)).toEqual(activeIds);
    expect(defaultBandBookings.map((row) => row._id)).toEqual(activeIds);
  });

  test("both lists keep the newest 100 per status, including explicitly requested terminal statuses", async () => {
    const f = await setupBookings({ status: "offer_sent" });
    const ids = await f.t.run(async (ctx) => {
      const ids: Id<"bookings">[] = [];
      for (let index = 1; index <= 100; index++) {
        ids.push(
          await ctx.db.insert("bookings", {
            ...f.bookingFields,
            startsAt: STARTS_AT + index,
          }),
        );
      }
      ids.push(
        await ctx.db.insert("bookings", {
          ...f.bookingFields,
          status: "expired",
          startsAt: STARTS_AT + 101,
        }),
      );
      return ids;
    });
    const args = {
      statuses: ["offer_sent", "expired"] as BookingStatus[],
      limit: 200,
    };
    const organizationBookings = await f
      .as("owner")
      .query(api.bookingsRead.forOrganization, {
        organizationId: f.organizationId,
        ...args,
      });
    const bandBookings = await f
      .as("bandAdmin")
      .query(api.bookingsRead.forBand, { bandId: f.bandId, ...args });
    expect(organizationBookings.map((row) => row._id)).toEqual(
      [...ids].reverse(),
    );
    expect(bandBookings.map((row) => row._id)).toEqual([...ids].reverse());
  });

  test.each(["forOrganization", "forBand"] as const)(
    "%s limits the merged active bookings to the newest 5, defaults to 100, and clamps to 200",
    async (query) => {
      const f = await setupBookings({ status: "offer_sent" });
      const ids = await f.t.run(async (ctx) => {
        const ids = [f.bookingId];
        const statuses = [
          "offer_sent",
          "artist_accepted",
          "awaiting_payment",
        ] as const;
        // Interleave statuses to catch limiting before the merge and sort.
        for (let index = 1; index < 225; index++) {
          ids.push(
            await ctx.db.insert("bookings", {
              ...f.bookingFields,
              status: statuses[index % statuses.length],
              startsAt: STARTS_AT + index,
            }),
          );
        }
        return ids.reverse();
      });
      const list = (limit?: number) =>
        query === "forOrganization"
          ? f.as("owner").query(api.bookingsRead.forOrganization, {
              organizationId: f.organizationId,
              limit,
            })
          : f.as("bandAdmin").query(api.bookingsRead.forBand, {
              bandId: f.bandId,
              limit,
            });
      expect((await list(5)).map((row) => row._id)).toEqual(ids.slice(0, 5));
      expect((await list()).map((row) => row._id)).toEqual(ids.slice(0, 100));
      expect((await list(500)).map((row) => row._id)).toEqual(ids.slice(0, 200));
    },
  );

  test.each(["forOrganization", "forBand"] as const)(
    "%s skips a booking with a deleted opportunity and returns the remaining bookings",
    async (query) => {
      const f = await setupBookings();
      const olderId = await f.t.run(async (ctx) => {
        const opportunity = (await ctx.db.get(f.opportunityId))!;
        const { _id, _creationTime, ...fields } = opportunity;
        const deletedOpportunityId = await ctx.db.insert(
          "talentOpportunities",
          { ...fields, slug: "deleted-opportunity" },
        );
        await ctx.db.insert("bookings", {
          ...f.bookingFields,
          opportunityId: deletedOpportunityId,
          startsAt: STARTS_AT + DAY_MS,
        });
        const olderId = await ctx.db.insert("bookings", {
          ...f.bookingFields,
          startsAt: STARTS_AT - DAY_MS,
        });
        await ctx.db.delete(deletedOpportunityId);
        return olderId;
      });
      const result =
        query === "forOrganization"
          ? await f.as("owner").query(api.bookingsRead.forOrganization, {
              organizationId: f.organizationId,
            })
          : await f.as("bandAdmin").query(api.bookingsRead.forBand, {
              bandId: f.bandId,
            });
      expect(result.map((row) => row._id)).toEqual([f.bookingId, olderId]);
    },
  );

  test.each(["forOrganization", "forBand"] as const)(
    "%s propagates errors other than missing booking references",
    async (query) => {
      const f = await setupBookings();
      await f.t.run(async (ctx) => {
        const details = (await ctx.db.get(f.venuePrivateId))!;
        const { _id, _creationTime, ...fields } = details;
        await ctx.db.insert("venuePrivateDetails", fields);
      });
      const result =
        query === "forOrganization"
          ? f.as("owner").query(api.bookingsRead.forOrganization, {
              organizationId: f.organizationId,
            })
          : f.as("bandAdmin").query(api.bookingsRead.forBand, {
              bandId: f.bandId,
            });
      await expect(result).rejects.toThrow();
    },
  );

  test("forOrganization rejects outsiders", async () => {
    const f = await setupBookings();
    await expect(
      f
        .as("outsider")
        .query(api.bookingsRead.forOrganization, {
          organizationId: f.organizationId,
        }),
    ).rejects.toThrow("Not permitted for this organization");
  });

  test("list queries require a signed-in user", async () => {
    const f = await setupBookings();
    await expect(
      f.t.query(api.bookingsRead.forOrganization, {
        organizationId: f.organizationId,
      }),
    ).rejects.toThrow("Not signed in");
    await expect(
      f.t.query(api.bookingsRead.forBand, { bandId: f.bandId }),
    ).rejects.toThrow("Not signed in");
  });
});
