/// <reference types="vite/client" />
import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  api as generatedApi,
  internal as generatedInternal,
} from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { OFFER_TTL_MS } from "./lib/bookingStatus";
import { feeSnapshot } from "./lib/fees";
import { appendLedgerEntry } from "./lib/ledger";
import { APPLICATION_ACTIVE_STATUSES } from "./lib/opportunityStatus";
import {
  paymentRecordsForBooking,
  recomputePayoutHold,
  unpaidMinor,
} from "./lib/paymentSchedule";
import {
  AUTO_CANCEL_GRACE_MS,
  CHECKOUT_TTL_MS,
  DEFAULT_PAYMENT_DUE_MS,
  PAYMENT_REMINDER_LEAD_MS,
} from "./lib/paymentStatus";
import { StripeApiError, stripeRequest } from "./lib/stripeClient";
import type * as payments from "./payments";
import schema from "./schema";
import type { StripeEvent } from "./stripeWebhook";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const api = generatedApi as typeof generatedApi &
  FilterApi<
    ApiFromModules<{ payments: typeof payments }>,
    FunctionReference<"query" | "mutation" | "action", "public">
  >;
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ payments: typeof payments }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTORS = [
  "owner",
  "finance",
  "manager",
  "door",
  "admin",
  "member",
  "platformAdmin",
  "stranger",
] as const;
type Actor = (typeof ACTORS)[number];
const INSTALLMENTS = [
  {
    label: "Deposit",
    amountMinor: 9000,
    dueAt: NOW + DAY_MS,
    dueAfterAcceptanceMs: 2 * DAY_MS,
  },
  { label: "Balance", amountMinor: 6000, dueAt: NOW + 7 * DAY_MS },
];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("PAYMENTS_ENABLED", "true");
  vi.stubEnv("BOOKING_COMMISSION_BPS", "1000");
  vi.stubEnv("APP_BASE_URL", "https://earplug.test");
  let nextSession = 0;
  vi.mocked(stripeRequest).mockReset();
  vi.mocked(stripeRequest).mockImplementation(async (_method, path) => {
    if (path === "/v1/customers")
      return { id: "cus_test_1", object: "customer" };
    if (path.endsWith("/expire"))
      return { id: path.split("/").at(-2), status: "expired" };
    if (path === "/v1/checkout/sessions") {
      const id = `cs_test_${++nextSession}`;
      return {
        id,
        object: "checkout.session",
        url: `https://checkout.stripe.com/c/pay/${id}`,
      };
    }
    throw new Error(`Unexpected Stripe request: ${path}`);
  });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupPayments() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `payment_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `payment_${actor}`,
        name: actor,
        email: `${actor}@payment.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Payment Collective",
      slug: "payment-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "finance", "manager", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const detailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "billing@payment.test",
      contactName: "Owner",
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: [],
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
      venueType: "hall",
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    });
    for (const role of ["admin", "member"] as const) {
      await ctx.db.insert("bandMembers", { bandId, userId: users[role], role });
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
      startsAt: NOW + 14 * DAY_MS,
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
      applicationCount: 1,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 15000,
      required: true,
      status: "open",
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.admin,
      status: "shortlisted",
      message: "We are available",
      createdAt: NOW,
      updatedAt: NOW,
    });
    return {
      users,
      organizationId,
      detailsId,
      venueId,
      bandId,
      opportunityId,
      slotId,
      applicationId,
    };
  });

  async function checked<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } finally {
      await t.run(async (ctx) => {
        const opportunity = await ctx.db.get(ids.opportunityId);
        const applications = await ctx.db
          .query("artistApplications")
          .withIndex("by_opportunityId_and_bandId", (q) =>
            q.eq("opportunityId", ids.opportunityId),
          )
          .take(100);
        expect(opportunity?.applicationCount).toBe(
          applications.filter((row) =>
            APPLICATION_ACTIVE_STATUSES.includes(row.status),
          ).length,
        );
      });
    }
  }
  async function seedOffer(installments: Doc<"bookingOffers">["installments"]) {
    return await checked(() =>
      t.run(async (ctx) => {
        const terms = {
          ...feeSnapshot(15000, 1000),
          cancellationTemplate: "standard" as const,
        };
        const bookingId = await ctx.db.insert("bookings", {
          opportunityId: ids.opportunityId,
          slotId: ids.slotId,
          organizationId: ids.organizationId,
          bandId: ids.bandId,
          applicationId: ids.applicationId,
          status: "offer_sent",
          revision: 1,
          startsAt: NOW + 14 * DAY_MS,
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
          revision: 1,
          ...terms,
          installments,
          sentBy: ids.users.owner,
          sentAt: NOW,
          expiresAt: NOW + OFFER_TTL_MS,
        });
        // Exercise loadCurrentOffer's revision-index fallback.
        await ctx.db.patch(ids.applicationId, { status: "offered" });
        return { bookingId, offerId };
      }),
    );
  }
  const respond = (bookingId: Id<"bookings">) =>
    checked(() =>
      as("admin").mutation(api.bookings.respond, {
        bookingId,
        action: "accept",
        expectedRevision: 1,
      }),
    );
  async function accept(installments?: Doc<"bookingOffers">["installments"]) {
    const offer =
      installments === undefined
        ? await checked(() =>
            as("owner").mutation(api.bookings.sendOffer, {
              applicationId: ids.applicationId,
              grossMinor: 15000,
              cancellationTemplate: "standard",
            }),
          )
        : await seedOffer(installments);
    const result = await respond(offer.bookingId);
    return { ...offer, ...result };
  }
  const records = (bookingId: Id<"bookings">) =>
    t.run((ctx) => paymentRecordsForBooking(ctx, bookingId));
  async function open(
    record: Doc<"paymentRecords">,
    sessionId = `cs_installment_${record.installmentIndex}`,
  ) {
    await t.mutation(internal.payments.markCheckoutOpen, {
      paymentRecordId: record._id,
      sessionId,
      checkoutExpiresAt: NOW + CHECKOUT_TTL_MS,
      attempt: record.attempt,
    });
    return sessionId;
  }
  const deliver = (event: StripeEvent) =>
    checked(() =>
      t.mutation(internal.stripeWebhook.recordAndApply, {
        kind: "platform",
        event,
        receivedAt: Date.now(),
        livemodeMismatch: false,
      }),
    );
  return {
    t,
    as,
    ...ids,
    checked,
    seedOffer,
    respond,
    accept,
    records,
    open,
    deliver,
    readBooking: (bookingId: Id<"bookings">) =>
      t.run((ctx) => ctx.db.get(bookingId)),
    scheduled: () =>
      t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
    ledger: () => t.run((ctx) => ctx.db.query("ledgerEntries").take(50)),
  };
}

function completedEvent(
  record: Doc<"paymentRecords">,
  fields: Record<string, unknown> = {},
): StripeEvent {
  return {
    id: `evt_complete_${record.installmentIndex}`,
    type: "checkout.session.completed",
    livemode: false,
    created: NOW / 1000,
    data: {
      object: {
        id: `cs_installment_${record.installmentIndex}`,
        object: "checkout.session",
        mode: "payment",
        status: "complete",
        payment_status: "paid",
        amount_total: record.amountMinor,
        currency: record.currency,
        payment_intent: {
          id: `pi_installment_${record.installmentIndex}`,
          latest_charge: `ch_installment_${record.installmentIndex}`,
        },
        metadata: {
          paymentRecordId: record._id,
          bookingId: record.bookingId,
          installmentIndex: `${record.installmentIndex}`,
        },
        ...fields,
      },
    },
  };
}

describe("paid booking acceptance", () => {
  test("creates the default installment and revision-matched reminder and cancellation jobs", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    expect(offer).toMatchObject({ status: "awaiting_payment", revision: 3 });
    const records = await f.records(offer.bookingId);
    expect(records).toHaveLength(1);
    expect(records[0]).toMatchObject({
      installmentIndex: 0,
      label: "Booking payment",
      amountMinor: 15000,
      currency: "usd",
      dueAt: NOW + DEFAULT_PAYMENT_DUE_MS,
      status: "pending",
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      payoutHold: true,
      payoutHoldReasons: ["unpaid_installment"],
      paymentDueAt: NOW + DEFAULT_PAYMENT_DUE_MS,
      autoCancelAt: NOW + DEFAULT_PAYMENT_DUE_MS + AUTO_CANCEL_GRACE_MS,
    });
    const jobs = await f.scheduled();
    expect(
      jobs.filter((job) => job.name === "payments:remindPayment"),
    ).toMatchObject([
      {
        scheduledTime: NOW + DEFAULT_PAYMENT_DUE_MS - PAYMENT_REMINDER_LEAD_MS,
        args: [
          {
            bookingId: offer.bookingId,
            paymentRecordId: records[0]._id,
            revision: 3,
          },
        ],
      },
    ]);
    expect(
      jobs.filter((job) => job.name === "bookings:autoCancelUnpaid"),
    ).toMatchObject([
      {
        scheduledTime: NOW + DEFAULT_PAYMENT_DUE_MS + AUTO_CANCEL_GRACE_MS,
        args: [{ bookingId: offer.bookingId, revision: 3 }],
      },
    ]);
  });

  test("preserves installment order and resolves relative deadlines from acceptance time", async () => {
    const f = await setupPayments();
    const offer = await f.seedOffer(INSTALLMENTS);
    vi.setSystemTime(NOW + DAY_MS);
    await f.respond(offer.bookingId);
    expect(await f.records(offer.bookingId)).toMatchObject([
      {
        installmentIndex: 0,
        amountMinor: 9000,
        label: "Deposit",
        dueAt: NOW + 3 * DAY_MS,
      },
      {
        installmentIndex: 1,
        amountMinor: 6000,
        label: "Balance",
        dueAt: NOW + 7 * DAY_MS,
      },
    ]);
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payments:remindPayment",
      ),
    ).toHaveLength(2);
  });

  test("rolls back acceptance when installments do not sum to the booking gross", async () => {
    const f = await setupPayments();
    const offer = await f.seedOffer([
      { ...INSTALLMENTS[0], amountMinor: 14999 },
    ]);
    await expect(f.respond(offer.bookingId)).rejects.toThrow(
      "Installments must sum to the booking's gross amount",
    );
    expect(await f.records(offer.bookingId)).toEqual([]);
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      status: "offer_sent",
      revision: 1,
    });
    expect(
      await f.t.run((ctx) => ctx.db.get(offer.offerId)),
    ).not.toHaveProperty("response");
    expect(await f.scheduled()).toEqual([]);
  });
});

describe("installment Checkout", () => {
  test("finance creates and reuses the customer, with exact session params and attempt keys", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    const first = await f
      .as("finance")
      .action(api.payments.startInstallmentCheckout, {
        paymentRecordId: record._id,
      });
    expect(first).toEqual({
      sessionId: "cs_test_1",
      url: "https://checkout.stripe.com/c/pay/cs_test_1",
    });
    expect(stripeRequest).toHaveBeenNthCalledWith(
      1,
      "POST",
      "/v1/customers",
      {
        name: "Payment Collective",
        email: "billing@payment.test",
        metadata: { organizationId: f.organizationId },
      },
      { idempotencyKey: `customer:${f.organizationId}` },
    );
    expect(stripeRequest).toHaveBeenNthCalledWith(
      2,
      "POST",
      "/v1/checkout/sessions",
      {
        mode: "payment",
        customer: "cus_test_1",
        client_reference_id: record._id,
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: "usd",
              unit_amount: 15000,
              product_data: { name: "Friday at the Hall · Booking payment" },
            },
          },
        ],
        success_url:
          "https://earplug.test/checkout/return?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: `https://earplug.test/checkout/cancel?booking=${offer.bookingId}`,
        expires_at: (NOW + CHECKOUT_TTL_MS) / 1000,
        payment_intent_data: {
          transfer_group: offer.bookingId,
          metadata: { bookingId: offer.bookingId, paymentRecordId: record._id },
        },
        metadata: {
          bookingId: offer.bookingId,
          paymentRecordId: record._id,
          installmentIndex: 0,
        },
      },
      { idempotencyKey: `checkout:${record._id}:1` },
    );
    expect(await f.records(offer.bookingId)).toMatchObject([
      {
        status: "checkout_open",
        stripeCheckoutSessionId: "cs_test_1",
        attempt: 1,
        checkoutExpiresAt: NOW + CHECKOUT_TTL_MS,
      },
    ]);
    expect(await f.t.run((ctx) => ctx.db.get(f.detailsId))).toMatchObject({
      stripeCustomerId: "cus_test_1",
    });
    await f.as("owner").action(api.payments.startInstallmentCheckout, {
      paymentRecordId: record._id,
    });
    expect(
      vi
        .mocked(stripeRequest)
        .mock.calls.filter((call) => call[1] === "/v1/customers"),
    ).toHaveLength(1);
    expect(stripeRequest).toHaveBeenNthCalledWith(
      3,
      "POST",
      "/v1/checkout/sessions/cs_test_1/expire",
    );
    expect(stripeRequest).toHaveBeenNthCalledWith(
      4,
      "POST",
      "/v1/checkout/sessions",
      expect.objectContaining({ customer: "cus_test_1" }),
      { idempotencyKey: `checkout:${record._id}:2` },
    );
    expect(await f.records(offer.bookingId)).toMatchObject([
      {
        status: "checkout_open",
        stripeCheckoutSessionId: "cs_test_2",
        attempt: 2,
      },
    ]);
  });

  test.each([
    "manager",
    "door",
    "admin",
    "member",
    "platformAdmin",
    "stranger",
  ] as const)("%s cannot start a payment", async (actor) => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await expect(
      f.as(actor).action(api.payments.startInstallmentCheckout, {
        paymentRecordId: record._id,
      }),
    ).rejects.toThrow("Not permitted to start a payment");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test.each(["expired", "completed"])(
    "restarts after Stripe reports the previous session already %s",
    async (status) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      await f.open(record);
      vi.mocked(stripeRequest).mockRejectedValueOnce(
        new StripeApiError(`Session is already ${status}`, { status: 400 }),
      );
      await f.as("finance").action(api.payments.startInstallmentCheckout, {
        paymentRecordId: record._id,
      });
      expect(await f.records(offer.bookingId)).toMatchObject([
        { status: "checkout_open", attempt: 2 },
      ]);
    },
  );

  test.each(["Invalid API key", "The API key is expired"])(
    "propagates unrelated Stripe error '%s' and does not replace the session",
    async (message) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      await f.open(record);
      vi.mocked(stripeRequest).mockRejectedValueOnce(
        new StripeApiError(message, { status: 401 }),
      );
      await expect(
        f.as("finance").action(api.payments.startInstallmentCheckout, {
          paymentRecordId: record._id,
        }),
      ).rejects.toThrow(message);
      expect(stripeRequest).toHaveBeenCalledTimes(1);
      expect(await f.records(offer.bookingId)).toMatchObject([
        { status: "checkout_open", attempt: 1 },
      ]);
    },
  );

  test("refuses a paid installment before contacting Stripe", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    expect(await f.deliver(completedEvent(record))).toEqual({
      outcome: "applied",
    });
    await expect(
      f.as("finance").action(api.payments.startInstallmentCheckout, {
        paymentRecordId: record._id,
      }),
    ).rejects.toThrow("This installment is not payable");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test("refuses Checkout once the booking is no longer accepting payments", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    vi.setSystemTime(NOW + DEFAULT_PAYMENT_DUE_MS + AUTO_CANCEL_GRACE_MS);
    await f.checked(() =>
      f.t.mutation(internal.bookings.autoCancelUnpaid, {
        bookingId: offer.bookingId,
        revision: 3,
      }),
    );
    expect((await f.readBooking(offer.bookingId))?.status).toBe("expired");
    expect((await f.records(offer.bookingId))[0].status).toBe("pending");
    await expect(
      f.as("finance").action(api.payments.startInstallmentCheckout, {
        paymentRecordId: record._id,
      }),
    ).rejects.toThrow("This booking is not accepting payments");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test("cleanup expires every open session locally even when Stripe fails", async () => {
    const f = await setupPayments();
    const offer = await f.accept(INSTALLMENTS);
    const records = await f.records(offer.bookingId);
    for (const record of records) await f.open(record);
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.mocked(stripeRequest).mockRejectedValueOnce(
      new Error("Network unavailable"),
    );
    await f.t.action(internal.payments.expireOpenSessions, {
      bookingId: offer.bookingId,
    });
    expect(log).toHaveBeenCalledTimes(1);
    expect(stripeRequest).toHaveBeenCalledTimes(2);
    expect(await f.records(offer.bookingId)).toMatchObject([
      { status: "expired" },
      { status: "expired" },
    ]);
    await f.t.action(internal.payments.expireOpenSessions, {
      bookingId: offer.bookingId,
    });
    expect(stripeRequest).toHaveBeenCalledTimes(2);
  });
});

describe("payment webhooks and ledger", () => {
  test("refunds a stale Checkout intent after settlement and ignores replays", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    const originalEvent = completedEvent(record);
    expect(await f.deliver(originalEvent)).toEqual({
      outcome: "applied",
    });
    const settledRecords = await f.records(offer.bookingId);
    const booking = await f.readBooking(offer.bookingId);
    const jobsBefore = await f.scheduled();
    const event = {
      ...completedEvent(record, {
        id: "cs_stale",
        payment_intent: "pi_stale",
        amount_total: 14000,
      }),
      id: "evt_stale",
    };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const rows = await f.t.run((ctx) => ctx.db.query("refunds").take(50));
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      paymentRecordId: record._id,
      reason: "late_payment",
      stripePaymentIntentId: "pi_stale",
      amountMinor: 14000,
      status: "pending",
    });
    const ledger = await f.ledger();
    expect(ledger).toHaveLength(2);
    expect(ledger).toContainEqual(
      expect.objectContaining({
        kind: "charge",
        idempotencyKey: "charge:pi_stale",
        stripeRef: "pi_stale",
        amountMinor: 14000,
      }),
    );
    const jobs = await f.scheduled();
    expect(
      jobs.filter(
        (job) => !jobsBefore.some((old) => old._id === job._id),
      ),
    ).toMatchObject([
      {
        name: "refunds:executeRefund",
        args: [{ refundId: rows[0]._id, attempt: 0 }],
        scheduledTime: NOW,
      },
    ]);
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    // Exercise the handler's own guards for both intents after every settled state.
    for (const status of [
      "paid",
      "partially_refunded",
      "refunded",
    ] as const) {
      await f.t.run((ctx) => ctx.db.patch(record._id, { status }));
      for (const replay of [event, originalEvent]) {
        await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
          eventJson: JSON.stringify(replay),
        });
      }
      expect((await f.records(offer.bookingId))[0]).toEqual({
        ...settledRecords[0],
        status,
      });
    }
    expect(
      await f.t.run((ctx) => ctx.db.query("refunds").take(50)),
    ).toEqual(rows);
    expect(await f.ledger()).toEqual(ledger);
    expect(await f.scheduled()).toEqual(jobs);
    expect(await f.readBooking(offer.bookingId)).toEqual(booking);
  });

  test("first payment confirms the booking, books the slot, notifies both sides, and replays safely", async () => {
    const f = await setupPayments();
    const offer = await f.accept(INSTALLMENTS);
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    const event = completedEvent(record);
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const paidRecords = await f.records(offer.bookingId);
    expect(paidRecords[0]).toMatchObject({
      status: "paid",
      stripePaymentIntentId: "pi_installment_0",
      stripeChargeId: "ch_installment_0",
      stripeEventId: event.id,
      paidAt: NOW,
    });
    const booking = await f.readBooking(offer.bookingId);
    expect(booking).toMatchObject({
      status: "confirmed",
      revision: 4,
      paidMinor: 9000,
      payoutHold: true,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.slotId))).toMatchObject({
      status: "booked",
      bookingId: offer.bookingId,
    });
    const ledger = await f.ledger();
    expect(ledger).toHaveLength(1);
    expect(ledger[0]).toMatchObject({
      kind: "charge",
      amountMinor: 9000,
      currency: "usd",
      fundsState: "pending",
      bookingId: offer.bookingId,
      organizationId: f.organizationId,
      idempotencyKey: "charge:pi_installment_0",
      stripeEventId: event.id,
    });
    const jobs = await f.scheduled();
    const confirmations = jobs.filter(
      (job) =>
        job.name === "emails:send" && job.args[0].kind === "bookingConfirmed",
    );
    expect(confirmations.map((job) => job.args[0].to).sort()).toEqual([
      "admin@payment.test",
      "billing@payment.test",
    ]);
    vi.setSystemTime(NOW + 1000);
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    // Bypass event deduplication to prove the handler and markPaid are independently idempotent.
    await f.checked(() =>
      f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      }),
    );
    await f.t.mutation(internal.payments.markPaid, {
      paymentRecordId: record._id,
      paymentIntentId: "pi_retry",
      amountMinor: 1,
      eventId: "evt_retry",
      sessionId: "cs_retry",
    });
    expect(await f.ledger()).toEqual(ledger);
    expect(await f.readBooking(offer.bookingId)).toEqual(booking);
    expect(await f.records(offer.bookingId)).toEqual(paidRecords);
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("the balance clears the unpaid hold without confirming the booking again", async () => {
    const f = await setupPayments();
    const offer = await f.accept(INSTALLMENTS);
    const records = await f.records(offer.bookingId);
    for (const record of records) {
      await f.open(record);
      expect(await f.deliver(completedEvent(record))).toEqual({
        outcome: "applied",
      });
    }
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      status: "confirmed",
      revision: 4,
      paidMinor: 15000,
      payoutHold: false,
      payoutHoldReasons: [],
    });
    expect(await f.records(offer.bookingId)).toMatchObject([
      { status: "paid" },
      { status: "paid" },
    ]);
    expect(await f.ledger()).toHaveLength(2);
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "bookings:markCompleted",
      ),
    ).toHaveLength(1);
  });

  test("a late Checkout completion marks an expired payment paid", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    const sessionId = await f.open(record);
    vi.setSystemTime(NOW + CHECKOUT_TTL_MS);
    await f.t.mutation(internal.payments.markSessionExpired, { sessionId });
    expect((await f.records(offer.bookingId))[0].status).toBe("expired");
    expect(await f.deliver(completedEvent(record))).toEqual({
      outcome: "applied",
    });
    expect((await f.records(offer.bookingId))[0]).toMatchObject({
      status: "paid",
      paidAt: Date.now(),
    });
    expect(await f.ledger()).toHaveLength(1);
  });

  test.each(["paid", "expired"] as const)(
    "a Checkout event moves a failed payment to %s",
    async (status) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      const sessionId = await f.open(record);
      await f.t.mutation(internal.payments.markFailed, {
        paymentIntentId: "pi_installment_0",
        metadataPaymentRecordId: record._id,
      });
      expect((await f.records(offer.bookingId))[0].status).toBe("failed");
      vi.setSystemTime(NOW + CHECKOUT_TTL_MS);
      const event: StripeEvent =
        status === "paid"
          ? completedEvent(record)
          : {
              id: "evt_expired_after_failure",
              type: "checkout.session.expired",
              livemode: false,
              created: Date.now() / 1000,
              data: {
                object: {
                  id: sessionId,
                  object: "checkout.session",
                  status: "expired",
                },
              },
            };
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      expect((await f.records(offer.bookingId))[0].status).toBe(status);
      expect(await f.ledger()).toHaveLength(status === "paid" ? 1 : 0);
    },
  );

  test("payment failure resolves the intent stored when Checkout is created", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    vi.mocked(stripeRequest)
      .mockResolvedValueOnce({ id: "cus_test_1", object: "customer" })
      .mockResolvedValueOnce({
        id: "cs_with_intent",
        object: "checkout.session",
        url: "https://checkout.stripe.com/c/pay/cs_with_intent",
        payment_intent: "pi_checkout",
      });
    await f.as("finance").action(api.payments.startInstallmentCheckout, {
      paymentRecordId: record._id,
    });
    expect((await f.records(offer.bookingId))[0]).toMatchObject({
      status: "checkout_open",
      stripePaymentIntentId: "pi_checkout",
    });
    expect(
      await f.deliver({
        id: "evt_payment_failed",
        type: "payment_intent.payment_failed",
        livemode: false,
        created: NOW / 1000,
        data: {
          object: {
            id: "pi_checkout",
            object: "payment_intent",
            status: "requires_payment_method",
            last_payment_error: { code: "card_declined" },
          },
        },
      }),
    ).toEqual({ outcome: "applied" });
    expect((await f.records(offer.bookingId))[0].status).toBe("failed");
    expect(await f.ledger()).toEqual([]);
  });

  test("payment failure falls back to payment intent metadata", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    expect(
      (await f.records(offer.bookingId))[0].stripePaymentIntentId,
    ).toBeUndefined();
    expect(
      await f.deliver({
        id: "evt_payment_failed_metadata",
        type: "payment_intent.payment_failed",
        livemode: false,
        created: NOW / 1000,
        data: {
          object: {
            id: "pi_not_stored",
            object: "payment_intent",
            status: "requires_payment_method",
            last_payment_error: { code: "card_declined" },
            metadata: { paymentRecordId: record._id },
          },
        },
      }),
    ).toEqual({ outcome: "applied" });
    expect((await f.records(offer.bookingId))[0].status).toBe("failed");
    expect(await f.ledger()).toEqual([]);
  });

  test.each([
    undefined,
    { paymentRecordId: "invalid-id" },
    { paymentRecordId: 123 },
  ])(
    "ignores payment failure with an unknown intent and metadata %j",
    async (metadata) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      await f.open(record);
      const records = await f.records(offer.bookingId);
      const log = vi.spyOn(console, "log").mockImplementation(() => {});
      expect(
        await f.deliver({
          id: "evt_payment_failed_unknown",
          type: "payment_intent.payment_failed",
          livemode: false,
          created: NOW / 1000,
          data: {
            object: { id: "pi_unknown", object: "payment_intent", metadata },
          },
        }),
      ).toEqual({ outcome: "applied" });
      expect(log).toHaveBeenCalledWith(
        "payment_intent.payment_failed ignored: no payment record for intent pi_unknown",
      );
      expect(await f.records(offer.bookingId)).toEqual(records);
      expect(await f.ledger()).toEqual([]);
    },
  );

  test.each([undefined, { paymentRecordId: "invalid-id" }])(
    "falls back to session lookup with metadata %j",
    async (metadata) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      await f.open(record);
      expect(
        await f.deliver(
          completedEvent(record, {
            metadata,
            payment_intent: "pi_string",
            amount_total: null,
          }),
        ),
      ).toEqual({ outcome: "applied" });
      expect((await f.records(offer.bookingId))[0]).toMatchObject({
        status: "paid",
        stripePaymentIntentId: "pi_string",
      });
      expect(
        (await f.records(offer.bookingId))[0].stripeChargeId,
      ).toBeUndefined();
      expect((await f.ledger())[0]).toMatchObject({
        amountMinor: 15000,
        stripeRef: "pi_string",
      });
    },
  );

  test("records a failed event with no payment changes when the payment intent is missing", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    expect(
      await f.deliver(completedEvent(record, { payment_intent: null })),
    ).toEqual({ outcome: "failed" });
    expect((await f.records(offer.bookingId))[0].status).toBe("checkout_open");
    expect(await f.ledger()).toEqual([]);
  });

  test("an unknown session is ignored by the handler but the event is applied", async () => {
    const f = await setupPayments();
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    expect(
      await f.deliver({
        id: "evt_unknown",
        type: "checkout.session.completed",
        livemode: false,
        created: NOW / 1000,
        data: { object: { id: "cs_unknown", metadata: {} } },
      }),
    ).toEqual({ outcome: "applied" });
    expect(log).toHaveBeenCalledWith(
      "checkout.session.completed ignored: no payment record for session cs_unknown",
    );
    expect(await f.ledger()).toEqual([]);
  });

  test.each(["checkout.session.expired", "payment_intent.payment_failed"])(
    "handles %s idempotently",
    async (type) => {
      const f = await setupPayments();
      const offer = await f.accept();
      const [record] = await f.records(offer.bookingId);
      const sessionId = await f.open(record);
      await f.t.run((ctx) =>
        ctx.db.patch(record._id, { stripePaymentIntentId: "pi_failed" }),
      );
      const event: StripeEvent = {
        id: "evt_status",
        type,
        livemode: false,
        created: NOW / 1000,
        data: {
          object:
            type === "checkout.session.expired"
              ? { id: sessionId, object: "checkout.session", status: "expired" }
              : {
                  id: "pi_failed",
                  object: "payment_intent",
                  status: "requires_payment_method",
                  last_payment_error: { code: "card_declined" },
                },
        },
      };
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const records = await f.records(offer.bookingId);
      expect(records[0].status).toBe(
        type === "checkout.session.expired" ? "expired" : "failed",
      );
      vi.setSystemTime(NOW + 1000);
      await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
      expect(await f.records(offer.bookingId)).toEqual(records);
      expect(await f.ledger()).toEqual([]);
    },
  );

  test("appendLedgerEntry never changes an existing entry even if replay fields differ", async () => {
    const f = await setupPayments();
    const entry = {
      idempotencyKey: "charge:pi_dedupe",
      kind: "charge" as const,
      amountMinor: 100,
      currency: "usd",
      fundsState: "pending" as const,
      occurredAt: NOW,
    };
    const first = await f.t.run((ctx) => appendLedgerEntry(ctx, entry));
    const rows = await f.ledger();
    const repeated = await f.t.run((ctx) =>
      appendLedgerEntry(ctx, {
        ...entry,
        amountMinor: 500,
        occurredAt: NOW + 1000,
      }),
    );
    expect(repeated).toBe(first);
    expect(await f.ledger()).toEqual(rows);
  });

  test("hold recomputation preserves other reasons and counts only open payments as owed", async () => {
    const f = await setupPayments();
    const offer = await f.accept(INSTALLMENTS);
    await f.t.run(async (ctx) => {
      await ctx.db.patch(offer.bookingId, {
        payoutHoldReasons: ["admin", "dispute", "no_payout_account"],
      });
      await recomputePayoutHold(ctx, (await ctx.db.get(offer.bookingId))!);
    });
    expect((await f.readBooking(offer.bookingId))?.payoutHoldReasons).toEqual([
      "admin",
      "dispute",
      "no_payout_account",
      "unpaid_installment",
    ]);
    const records = await f.records(offer.bookingId);
    expect(unpaidMinor(records)).toBe(15000);
    for (const record of records) {
      await f.open(record);
      expect(await f.deliver(completedEvent(record))).toEqual({
        outcome: "applied",
      });
    }
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      payoutHold: true,
      payoutHoldReasons: ["admin", "dispute", "no_payout_account"],
    });
    expect(unpaidMinor(await f.records(offer.bookingId))).toBe(0);
  });
});

describe("payment access and scheduled jobs", () => {
  test("only parties can read payments; only owners and finance members see canPay", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    const sessionId = await f.open(record);
    for (const actor of [
      "owner",
      "finance",
      "manager",
      "door",
      "admin",
    ] as const) {
      expect(
        await f.as(actor).query(api.payments.paymentsForBooking, {
          bookingId: offer.bookingId,
        }),
      ).toEqual([
        {
          _id: record._id,
          installmentIndex: 0,
          label: record.label,
          amountMinor: 15000,
          currency: "usd",
          dueAt: record.dueAt,
          status: "checkout_open",
          paidAt: null,
          canPay: actor === "owner" || actor === "finance",
        },
      ]);
      expect(
        await f.as(actor).query(api.payments.checkoutStatus, { sessionId }),
      ).toEqual({
        bookingId: offer.bookingId,
        paymentStatus: "checkout_open",
        bookingStatus: "awaiting_payment",
      });
    }
    for (const actor of ["member", "platformAdmin", "stranger"] as const) {
      await expect(
        f.as(actor).query(api.payments.paymentsForBooking, {
          bookingId: offer.bookingId,
        }),
      ).rejects.toThrow("Not permitted to view these payments");
      await expect(
        f.as(actor).query(api.payments.checkoutStatus, { sessionId }),
      ).rejects.toThrow("Not permitted to view these payments");
    }
    await expect(
      f.t.query(api.payments.paymentsForBooking, {
        bookingId: offer.bookingId,
      }),
    ).rejects.toThrow("Not signed in");
    expect(
      await f.t.query(api.payments.checkoutStatus, { sessionId: "cs_missing" }),
    ).toBeNull();
    expect(await f.deliver(completedEvent(record))).toEqual({
      outcome: "applied",
    });
    expect(
      await f
        .as("finance")
        .query(api.payments.paymentsForBooking, { bookingId: offer.bookingId }),
    ).toMatchObject([{ canPay: false, paidAt: NOW, status: "paid" }]);
  });

  test("reminders email the organizer with the deadline and ignore settled payments", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    const args = {
      bookingId: offer.bookingId,
      paymentRecordId: record._id,
    };
    const initial = await f.scheduled();
    await f.t.mutation(internal.payments.remindPayment, args);
    const reminders = (await f.scheduled()).filter(
      (job) => !initial.some((old) => old._id === job._id),
    );
    expect(reminders).toHaveLength(1);
    expect(reminders[0]).toMatchObject({
      name: "emails:send",
      args: [
        {
          to: "billing@payment.test",
          kind: "offerAccepted",
          text: expect.stringContaining(
            `Payment due ${new Date(record.dueAt).toISOString()}`,
          ),
        },
      ],
    });
    await f.open(record);
    expect(await f.deliver(completedEvent(record))).toEqual({
      outcome: "applied",
    });
    const jobs = await f.scheduled();
    await f.t.mutation(internal.payments.remindPayment, args);
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("a later installment reminder still sends after confirmation changes the revision", async () => {
    const f = await setupPayments();
    const offer = await f.accept(INSTALLMENTS);
    const [deposit, balance] = await f.records(offer.bookingId);
    const args = {
      bookingId: offer.bookingId,
      paymentRecordId: balance._id,
      revision: 3,
    };
    expect(
      (await f.scheduled()).find(
        (job) =>
          job.name === "payments:remindPayment" &&
          job.args[0].paymentRecordId === balance._id,
      ),
    ).toMatchObject({ args: [args] });
    await f.open(deposit);
    expect(await f.deliver(completedEvent(deposit))).toEqual({
      outcome: "applied",
    });
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      status: "confirmed",
      revision: 4,
    });
    expect((await f.records(offer.bookingId))[1].status).toBe("pending");
    vi.setSystemTime(balance.dueAt - PAYMENT_REMINDER_LEAD_MS);
    const initial = await f.scheduled();
    await f.t.mutation(internal.payments.remindPayment, args);
    const reminders = (await f.scheduled()).filter(
      (job) => !initial.some((old) => old._id === job._id),
    );
    expect(reminders).toHaveLength(1);
    expect(reminders[0]).toMatchObject({
      name: "emails:send",
      args: [
        {
          to: "billing@payment.test",
          kind: "offerAccepted",
          text: expect.stringContaining(
            `Payment due ${new Date(balance.dueAt).toISOString()}`,
          ),
        },
      ],
    });
  });

  test("auto-cancellation expires the booking, shortlists the application, and notifies both sides once", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    vi.setSystemTime(NOW + DEFAULT_PAYMENT_DUE_MS + AUTO_CANCEL_GRACE_MS);
    await f.checked(() =>
      f.t.mutation(internal.bookings.autoCancelUnpaid, {
        bookingId: offer.bookingId,
        revision: 3,
      }),
    );
    const booking = await f.readBooking(offer.bookingId);
    expect(booking).toMatchObject({
      status: "expired",
      revision: 4,
      cancelledBy: "system",
      cancelReason: "Payment not received",
      cancelledAt: Date.now(),
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.applicationId))).toMatchObject({
      status: "shortlisted",
    });
    const jobs = await f.scheduled();
    expect(
      jobs.filter((job) => job.name === "payments:expireOpenSessions"),
    ).toMatchObject([
      {
        args: [{ bookingId: offer.bookingId }],
        scheduledTime: Date.now(),
      },
    ]);
    expect(
      jobs
        .filter(
          (job) =>
            job.name === "emails:send" &&
            job.args[0].kind === "bookingCancelled",
        )
        .map((job) => job.args[0].to)
        .sort(),
    ).toEqual(["admin@payment.test", "billing@payment.test"]);
    await f.checked(() =>
      f.t.mutation(internal.bookings.autoCancelUnpaid, {
        bookingId: offer.bookingId,
        revision: 3,
      }),
    );
    expect(await f.readBooking(offer.bookingId)).toEqual(booking);
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("a stale auto-cancel does nothing while the booking is still awaiting payment", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const before = await f.readBooking(offer.bookingId);
    const jobs = await f.scheduled();
    await f.t.mutation(internal.bookings.autoCancelUnpaid, {
      bookingId: offer.bookingId,
      revision: 2,
    });
    expect(await f.readBooking(offer.bookingId)).toEqual(before);
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("cancellation schedules cleanup; an in-flight payment is captured and held without confirming", async () => {
    const f = await setupPayments();
    const offer = await f.accept();
    const [record] = await f.records(offer.bookingId);
    await f.open(record);
    await f.checked(() =>
      f.as("owner").mutation(api.bookings.cancel, {
        bookingId: offer.bookingId,
        expectedRevision: 3,
        reason: "Show cancelled",
      }),
    );
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payments:expireOpenSessions",
      ),
    ).toHaveLength(1);
    const event = completedEvent(record);
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    expect((await f.records(offer.bookingId))[0].status).toBe("paid");
    expect(await f.readBooking(offer.bookingId)).toMatchObject({
      status: "cancelled_by_organizer",
      revision: 4,
      paidMinor: 15000,
      payoutHold: true,
      payoutHoldReasons: ["unpaid_installment", "admin"],
    });
    expect(await f.ledger()).toHaveLength(1);
    expect(await f.t.run((ctx) => ctx.db.get(f.slotId))).toMatchObject({
      status: "open",
    });
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "bookings:markCompleted",
      ),
    ).toEqual([]);
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    expect((await f.readBooking(offer.bookingId))?.paidMinor).toBe(15000);
  });
});
