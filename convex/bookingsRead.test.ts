/// <reference types="vite/client" />
import type { ApiFromModules } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import * as bookingsRead from "./bookingsRead";
import {
  BOOKING_ACTIVE_STATUSES,
  BOOKING_LIVE_STATUSES,
  BOOKING_TRANSITIONS,
  type BookingStatus,
} from "./lib/bookingStatus";
import {
  ACTORS,
  asActor,
  DAY_MS,
  readers,
  seedMarketplace,
  type Actor,
} from "./marketplaceFixtures.test-helpers";
import schema from "./schema";

// Keep references typed while intentionally leaving codegen untouched.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ bookingsRead: typeof bookingsRead }>;
const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-04T12:00:00Z");
const STARTS_AT = NOW + 14 * DAY_MS;
const DOORS_AT = STARTS_AT - 60 * 60 * 1000;
const EXACT_ADDRESS = "42 Secret Alley, Oakland";
const BUSINESS_EMAIL = "booking-office@example.test";
const APPLICANT_EMAIL = "bandadmin@example.test";

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
  const marketplaceActor = asActor(t, "booking_read");
  const as = (actor: Actor | "otherBandAdmin") =>
    actor === "otherBandAdmin"
      ? t.withIdentity({ subject: "booking_read_otherBandAdmin" })
      : marketplaceActor(actor);
  const fee = {
    grossMinor: 5000,
    commissionBps: 1000,
    commissionMinor: 500,
    artistNetMinor: 4500,
    currency: "usd",
  };
  const booking = {
    status: overrides.status ?? "confirmed",
    revision: 2,
    startsAt: STARTS_AT,
    ...fee,
    cancellationTemplate: "standard" as const,
    organizerAcceptedTermsAt: NOW,
    // Leave acceptance and payment totals absent for the read-side defaults.
    artistAcceptedTermsAt: undefined,
    confirmedAt: undefined,
    paidMinor: undefined,
    refundedMinor: undefined,
    payoutHold: false,
    createdAt: NOW,
    updatedAt: NOW,
  };
  const marketplace = await seedMarketplace(t, {
    prefix: "booking_read",
    now: NOW,
    organization: {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
    },
    organizationPrivateDetails: {
      businessEmail: BUSINESS_EMAIL,
      contactName: "Booking Office",
    },
    venue: {
      slug: "neighborhood-hall",
      addr: "Uptown, Oakland",
      addressDisclosure: "onTicket",
      approxLabel: "Uptown, Oakland",
    },
    band: { bio: "Loud guitars and harmonies.", followerCount: 12 },
    bandPayoutAccount: false,
    opportunity: {
      area: "Uptown, Oakland",
      startsAt: STARTS_AT,
      doorsAt: DOORS_AT,
      applicationsCloseAt: NOW + 7 * DAY_MS,
    },
    slot: { setLengthMin: 45, guaranteeMinor: 5000 },
    booking,
  });
  const ids = await t.run(async (ctx) => {
    const {
      organizationId,
      venueId,
      bandId,
      opportunityId,
      slotId,
      applicationId,
      bookingId,
    } = marketplace;
    // Preserve the existing profiles while using the shared identity names.
    const profileNames: Partial<Record<Actor, string>> = {
      admin: "bandAdmin",
      member: "bandMember",
      stranger: "outsider",
    };
    for (const actor of ACTORS) {
      const name = profileNames[actor] ?? actor;
      await ctx.db.patch(marketplace.users[actor], {
        name,
        email: actor === "admin" ? APPLICANT_EMAIL : `${name}@example.test`,
      });
    }
    const otherBandAdmin = await ctx.db.insert("users", {
      clerkId: "booking_read_otherBandAdmin",
      name: "otherBandAdmin",
      email: "otherBandAdmin@example.test",
      genres: [],
      attendedCount: 0,
    });
    const users = { ...marketplace.users, otherBandAdmin };
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
    const otherBandId = await ctx.db.insert("bands", {
      name: "Other Band",
      slug: "other-band",
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 12,
      pastShows: [],
    });
    await ctx.db.insert("bandMembers", {
      bandId: otherBandId,
      userId: otherBandAdmin,
      role: "admin",
    });
    const bookingFields = {
      ...booking,
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      createdBy: users.owner,
    };
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
      ...marketplace,
      users,
      organizationPrivateId: marketplace.detailsId,
      venuePrivateId,
      otherBandId,
      offerId,
      gigId,
      bookingFields,
    };
  });
  return { t, as, ...ids, ...readers(t, ids) };
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
      paidMinor: 0,
      refundedMinor: 0,
      paymentDueAt: null,
      payoutHoldReasons: [],
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
      privateLocation: null,
      privateEvent: false,
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
          .as("admin")
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
          .as("admin")
          .query(api.bookingsRead.get, { bookingId: f.bookingId }),
      ).toMatchObject({
        venue: { exactAddress: EXACT_ADDRESS },
        counterpartyEmail: BUSINESS_EMAIL,
        viewerSide: "artist",
      });
    },
  );

  test.each(["artist", "organizer", undefined] as const)(
    "dual-role user resolves viewAs %s with the corresponding disclosures",
    async (viewAs) => {
      const f = await setupBookings({ status: "offer_sent" });
      await f.t.run((ctx) =>
        ctx.db.insert("bandMembers", {
          bandId: f.bandId,
          userId: f.users.owner,
          role: "admin",
        }),
      );
      const args = { bookingId: f.bookingId };
      const payload = await f
        .as("owner")
        .query(
          api.bookingsRead.get,
          viewAs === undefined ? args : { ...args, viewAs },
        );
      expect(payload).toMatchObject({
        viewerSide: viewAs ?? "organizer",
        venue: { exactAddress: viewAs === "artist" ? null : EXACT_ADDRESS },
        counterpartyEmail: viewAs === "artist" ? null : APPLICANT_EMAIL,
      });
    },
  );

  test.each([
    ["admin", "organizer", "artist", null, null],
    ["owner", "artist", "organizer", EXACT_ADDRESS, APPLICANT_EMAIL],
    ["door", "artist", "organizer", EXACT_ADDRESS, null],
    ["platformAdmin", "artist", "organizer", EXACT_ADDRESS, APPLICANT_EMAIL],
  ] as const)(
    "%s requesting %s falls back to %s with the appropriate disclosures",
    async (actor, viewAs, viewerSide, exactAddress, counterpartyEmail) => {
      const f = await setupBookings({ status: "offer_sent" });
      expect(
        await f.as(actor).query(api.bookingsRead.get, {
          bookingId: f.bookingId,
          viewAs,
        }),
      ).toMatchObject({
        viewerSide,
        venue: { exactAddress },
        counterpartyEmail,
      });
    },
  );

  test.each(["organizer", "artist"] as const)(
    "outsider cannot read a booking by requesting %s",
    async (viewAs) => {
      const f = await setupBookings();
      expect(
        await f.as("stranger").query(api.bookingsRead.get, {
          bookingId: f.bookingId,
          viewAs,
        }),
      ).toBeNull();
    },
  );

  test.each(["stranger", "otherBandAdmin", "member"] as const)(
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
    await f.t.run((ctx) => ctx.db.patch(f.users.admin, { deletedAt: NOW }));
    expect(
      await f.as("admin").query(api.bookingsRead.get, args),
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
        .as("admin")
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
        .as("admin")
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
        .as("admin")
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
        userId: f.users.admin,
        grantedAt: NOW,
      }),
    );
    expect(
      await f
        .as("admin")
        .query(api.bookingsRead.get, { bookingId: f.bookingId }),
    ).toMatchObject({
      viewerSide: "artist",
      counterpartyEmail: BUSINESS_EMAIL,
    });
  });

  test.each(["organizer", "artist"] as const)(
    "band admin with platform admin access can request %s",
    async (viewAs) => {
      const f = await setupBookings({ status: "offer_sent" });
      await f.t.run((ctx) =>
        ctx.db.insert("platformAdmins", {
          userId: f.users.admin,
          grantedAt: NOW,
        }),
      );
      expect(
        await f.as("admin").query(api.bookingsRead.get, {
          bookingId: f.bookingId,
          viewAs,
        }),
      ).toMatchObject({
        viewerSide: viewAs,
        venue: { exactAddress: viewAs === "artist" ? null : EXACT_ADDRESS },
        counterpartyEmail: viewAs === "artist" ? null : APPLICANT_EMAIL,
      });
    },
  );

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
          missing === "application" ? f.applicationId : f.users.admin,
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
        .as("admin")
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

describe("bookings read: platform admin viewer flag", () => {
  test("marks access granted solely through platform administration", async () => {
    const f = await setupBookings();
    const payload = await f.as("platformAdmin").query(api.bookingsRead.get, {
      bookingId: f.bookingId,
    });
    expect(payload).toMatchObject({
      viewerSide: "organizer",
      viewerIsPlatformAdmin: true,
    });
  });

  test.each(["owner", "manager", "finance", "door", "admin"] as const)(
    "does not mark %s viewing as a booking party",
    async (actor) => {
      const f = await setupBookings();
      const payload = await f.as(actor).query(api.bookingsRead.get, {
        bookingId: f.bookingId,
      });
      expect(payload).toMatchObject({
        viewerSide: actor === "admin" ? "artist" : "organizer",
      });
      expect(payload?.viewerIsPlatformAdmin).not.toBe(true);
    },
  );

  test("organization members with an admin grant still view as a party", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.insert("platformAdmins", { userId: f.users.owner, grantedAt: NOW }),
    );
    const payload = await f.as("owner").query(api.bookingsRead.get, {
      bookingId: f.bookingId,
    });
    expect(payload?.viewerSide).toBe("organizer");
    expect(payload?.viewerIsPlatformAdmin).not.toBe(true);
  });

  test.each([undefined, "artist", "organizer"] as const)(
    "band admins with an admin grant use the flag only for organizer view: %s",
    async (viewAs) => {
      const f = await setupBookings();
      await f.t.run((ctx) =>
        ctx.db.insert("platformAdmins", {
          userId: f.users.admin,
          grantedAt: NOW,
        }),
      );
      const payload = await f.as("admin").query(api.bookingsRead.get, {
        bookingId: f.bookingId,
        viewAs,
      });
      expect(payload?.viewerSide).toBe(viewAs ?? "artist");
      if (viewAs === "organizer") {
        expect(payload?.viewerIsPlatformAdmin).toBe(true);
      } else {
        expect(payload?.viewerIsPlatformAdmin).not.toBe(true);
      }
    },
  );

  test("list payloads omit the optional flag even for platform admins", async () => {
    const f = await setupBookings();
    const organizationRows = await f.as("platformAdmin").query(
      api.bookingsRead.forOrganization,
      { organizationId: f.organizationId },
    );
    const bandRows = await f.as("admin").query(api.bookingsRead.forBand, {
      bandId: f.bandId,
    });
    for (const rows of [organizationRows, bandRows]) {
      expect(rows).toHaveLength(1);
      expect(rows[0].viewerIsPlatformAdmin).toBeUndefined();
    }
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
      if (actor === "platformAdmin") {
        expect(payload?.viewerIsPlatformAdmin).toBe(true);
      } else {
        expect(payload?.viewerIsPlatformAdmin).not.toBe(true);
      }
      const { viewerIsPlatformAdmin: _payloadFlag, ...payloadForListComparison } =
        payload!;
      const listRows = await f
        .as(actor)
        .query(api.bookingsRead.forOrganization, {
          organizationId: f.organizationId,
        });
      expect(
        listRows.map(({ viewerIsPlatformAdmin: _rowFlag, ...rest }) => rest),
      ).toEqual([payloadForListComparison]);
    },
  );

  test("a suspended organization does not change the artist's live-booking contact access", async () => {
    const f = await setupBookings();
    await f.t.run((ctx) =>
      ctx.db.patch(f.organizationId, { status: "suspended" }),
    );
    expect(
      await f.as("admin").query(api.bookingsRead.forBand, {
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

  test.each(["member", "otherBandAdmin", "stranger"] as const)(
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
      .as("admin")
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
        ownerUserId: f.users.stranger,
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
      .as("admin")
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
      .as("admin")
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
      .as("admin")
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
          : f.as("admin").query(api.bookingsRead.forBand, {
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
          : await f.as("admin").query(api.bookingsRead.forBand, {
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
          : f.as("admin").query(api.bookingsRead.forBand, {
              bandId: f.bandId,
            });
      await expect(result).rejects.toThrow();
    },
  );

  test("forOrganization rejects outsiders", async () => {
    const f = await setupBookings();
    await expect(
      f
        .as("stranger")
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

const PRIVATE_LOCATION = {
  label: "Backyard",
  area: "Rockridge, Oakland",
  city: "Oakland",
  addr: "42 Garden Street",
  lat: 37.84,
  lng: -122.25,
  notes: "Use the side gate",
};
const APPROXIMATE_PRIVATE_LOCATION = {
  label: PRIVATE_LOCATION.area,
  area: PRIVATE_LOCATION.area,
  city: PRIVATE_LOCATION.city,
};

async function setupPrivateBooking(status: BookingStatus = "awaiting_payment") {
  const f = await setupBookings({ status });
  const privateLocationId = await f.t.run(async (ctx) => {
    const privateLocationId = await ctx.db.insert("privateLocations", {
      organizationId: f.organizationId,
      ...PRIVATE_LOCATION,
      createdAt: NOW,
      updatedAt: NOW,
    });
    await ctx.db.patch(f.organizationId, { orgType: "privateHost" });
    await ctx.db.patch(f.opportunityId, {
      mode: "privateBooking",
      venueId: undefined,
      privateLocationId,
      area: PRIVATE_LOCATION.area,
      venueType: undefined,
      publicGigId: undefined,
    });
    return privateLocationId;
  });
  return { ...f, privateLocationId };
}

describe("private booking location disclosure", () => {
  test("get hides the exact location before confirmation and reveals it once the same booking is confirmed", async () => {
    const f = await setupPrivateBooking();
    const read = () =>
      f.as("admin").query(api.bookingsRead.get, {
        bookingId: f.bookingId,
        viewAs: "artist",
      });
    const pending = await read();
    expect(pending).toMatchObject({
      venue: null,
      privateEvent: true,
      organizationName: "Private host",
    });
    expect(pending?.privateLocation).toStrictEqual(APPROXIMATE_PRIVATE_LOCATION);
    for (const field of ["addr", "lat", "lng", "notes"] as const) {
      expect(pending?.privateLocation?.[field]).toBeUndefined();
    }
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, { status: "confirmed", confirmedAt: NOW }),
    );
    const confirmed = await read();
    expect(confirmed).toMatchObject({
      venue: null,
      privateEvent: true,
      organizationName: "Opportunity Collective",
    });
    expect(confirmed?.privateLocation).toStrictEqual(PRIVATE_LOCATION);
  });

  test.each(Object.keys(BOOKING_TRANSITIONS) as BookingStatus[])(
    "get applies the live-status location rule to artists and always discloses to organizers for %s",
    async (status) => {
      const f = await setupPrivateBooking(status);
      const artist = await f.as("admin").query(api.bookingsRead.get, {
        bookingId: f.bookingId,
      });
      expect(artist).toMatchObject({
        venue: null,
        privateEvent: true,
        organizationName: BOOKING_LIVE_STATUSES.includes(status)
          ? "Opportunity Collective"
          : "Private host",
      });
      expect(artist?.privateLocation).toStrictEqual(
        BOOKING_LIVE_STATUSES.includes(status)
          ? PRIVATE_LOCATION
          : APPROXIMATE_PRIVATE_LOCATION,
      );
      const organizer = await f.as("owner").query(api.bookingsRead.get, {
        bookingId: f.bookingId,
      });
      expect(organizer).toMatchObject({
        venue: null,
        privateEvent: true,
        organizationName: "Opportunity Collective",
      });
      expect(organizer?.privateLocation).toStrictEqual(PRIVATE_LOCATION);
    },
  );

  test("shared cached locations in mixed-status lists are redacted separately for each artist row", async () => {
    const f = await setupPrivateBooking();
    const statuses = Object.keys(BOOKING_TRANSITIONS) as BookingStatus[];
    await f.t.run(async (ctx) => {
      for (const [index, status] of statuses.entries()) {
        await ctx.db.insert("bookings", {
          ...f.bookingFields,
          status,
          startsAt: STARTS_AT + index + 1,
        });
      }
    });
    const artistRows = await f.as("admin").query(api.bookingsRead.forBand, {
      bandId: f.bandId,
      statuses,
    });
    expect(artistRows).toHaveLength(statuses.length + 1);
    for (const row of artistRows) {
      expect(row).toMatchObject({
        venue: null,
        privateEvent: true,
        organizationName: BOOKING_LIVE_STATUSES.includes(row.status)
          ? "Opportunity Collective"
          : "Private host",
      });
      expect(row.privateLocation).toStrictEqual(
        BOOKING_LIVE_STATUSES.includes(row.status)
          ? PRIVATE_LOCATION
          : APPROXIMATE_PRIVATE_LOCATION,
      );
      if (!BOOKING_LIVE_STATUSES.includes(row.status)) {
        for (const field of ["addr", "lat", "lng", "notes"] as const) {
          expect(row.privateLocation?.[field]).toBeUndefined();
        }
      }
    }
    const organizerRows = await f.as("owner").query(
      api.bookingsRead.forOrganization,
      { organizationId: f.organizationId, statuses },
    );
    expect(organizerRows).toHaveLength(statuses.length + 1);
    for (const row of organizerRows) {
      expect(row).toMatchObject({
        venue: null,
        privateEvent: true,
        organizationName: "Opportunity Collective",
      });
      expect(row.privateLocation).toStrictEqual(PRIVATE_LOCATION);
    }
  });

  test.each(["cancelled_by_artist", "cancelled_by_organizer"] as const)(
    "safety cancellation is preserved in get and lists for both sides of a %s booking",
    async (status) => {
      const f = await setupPrivateBooking(status);
      await f.t.run((ctx) =>
        ctx.db.patch(f.bookingId, { cancellationKind: "safety" }),
      );
      for (const actor of ["owner", "admin"] as const) {
        const payload = await f.as(actor).query(api.bookingsRead.get, {
          bookingId: f.bookingId,
        });
        expect(payload?.cancellationKind).toBe("safety");
        expect(payload?.privateLocation).toStrictEqual(
          actor === "owner" ? PRIVATE_LOCATION : APPROXIMATE_PRIVATE_LOCATION,
        );
      }
      const artistRows = await f.as("admin").query(api.bookingsRead.forBand, {
        bandId: f.bandId,
        statuses: [status],
      });
      const organizerRows = await f.as("owner").query(
        api.bookingsRead.forOrganization,
        { organizationId: f.organizationId, statuses: [status] },
      );
      expect(artistRows).toHaveLength(1);
      expect(organizerRows).toHaveLength(1);
      expect(artistRows[0].cancellationKind).toBe("safety");
      expect(organizerRows[0].cancellationKind).toBe("safety");
      expect(artistRows[0].privateLocation).toStrictEqual(
        APPROXIMATE_PRIVATE_LOCATION,
      );
      expect(organizerRows[0].privateLocation).toStrictEqual(PRIVATE_LOCATION);
    },
  );

  test.each(["absent", "deleted"] as const)(
    "get reports a private location that is %s and both lists skip only the broken booking",
    async (locationState) => {
      const f = await setupPrivateBooking();
      const brokenBookingId = await f.t.run(async (ctx) => {
        const opportunity = (await ctx.db.get(f.opportunityId))!;
        const { _id, _creationTime, ...fields } = opportunity;
        let privateLocationId: Id<"privateLocations"> | undefined;
        if (locationState === "deleted") {
          privateLocationId = await ctx.db.insert("privateLocations", {
            organizationId: f.organizationId,
            ...PRIVATE_LOCATION,
            createdAt: NOW,
            updatedAt: NOW,
          });
          await ctx.db.delete(privateLocationId);
        }
        const opportunityId = await ctx.db.insert("talentOpportunities", {
          ...fields,
          slug: "broken-private-request",
          privateLocationId,
        });
        return await ctx.db.insert("bookings", {
          ...f.bookingFields,
          opportunityId,
          startsAt: STARTS_AT + DAY_MS,
        });
      });
      await expect(
        f.as("admin").query(api.bookingsRead.get, {
          bookingId: brokenBookingId,
        }),
      ).rejects.toThrow(
        locationState === "absent"
          ? `Booking ${brokenBookingId} has a private opportunity without a location`
          : `Booking ${brokenBookingId} references a missing private location`,
      );
      const artistRows = await f.as("admin").query(api.bookingsRead.forBand, {
        bandId: f.bandId,
      });
      const organizerRows = await f.as("owner").query(
        api.bookingsRead.forOrganization,
        { organizationId: f.organizationId },
      );
      expect(artistRows.map((row) => row._id)).toEqual([f.bookingId]);
      expect(organizerRows.map((row) => row._id)).toEqual([f.bookingId]);
    },
  );
});
