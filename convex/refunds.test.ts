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
import { computeCancellationSettlement } from "./lib/cancellationSettlement";
import { paymentRecordsForBooking } from "./lib/paymentSchedule";
import { CHECKOUT_TTL_MS, PAYOUT_DELAY_MS } from "./lib/paymentStatus";
import { stripeRequest } from "./lib/stripeClient";
import type * as payments from "./payments";
import type * as payouts from "./payouts";
import type * as refunds from "./refunds";
import schema from "./schema";
import type { StripeEvent } from "./stripeWebhook";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const api = generatedApi as typeof generatedApi &
  FilterApi<
    ApiFromModules<{ payments: typeof payments; refunds: typeof refunds }>,
    FunctionReference<"query" | "mutation" | "action", "public">
  >;
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{
      payments: typeof payments;
      payouts: typeof payouts;
      refunds: typeof refunds;
    }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const STARTS_AT = NOW + 30 * DAY_MS;
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "admin",
  "member",
  "platformAdmin",
  "stranger",
] as const;
type Actor = (typeof ACTORS)[number];
const stripeMock = vi.mocked(stripeRequest);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("PAYMENTS_ENABLED", "true");
  vi.stubEnv("BOOKING_COMMISSION_BPS", "1000");
  vi.stubEnv("RESEND_SEND_ENABLED", "false");
  vi.stubEnv("APP_BASE_URL", "https://earplug.test");
  let nextRefund = 0;
  stripeMock.mockReset();
  stripeMock.mockImplementation(async (method, path) => {
    if (method === "POST" && path === "/v1/refunds") {
      return { id: `re_test_${++nextRefund}` };
    }
    throw new Error(`Unexpected Stripe request: ${method} ${path}`);
  });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupRefunds() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) =>
    t.withIdentity({ subject: `refund_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `refund_${actor}`,
        name: actor,
        email: `${actor}@refund.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Refund Collective",
      slug: "refund-collective",
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
    await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "billing@refund.test",
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
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: users[role],
        role,
      });
    }
    await ctx.db.insert("bandPayoutAccounts", {
      bandId,
      stripeAccountId: "acct_band",
      chargesEnabled: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: [],
      updatedAt: NOW,
    });
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
      applicationsCloseAt: STARTS_AT - DAY_MS,
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
      guaranteeMinor: 20000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.admin,
      status: "booked",
      message: "We are available",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "confirmed",
      revision: 3,
      startsAt: STARTS_AT,
      grossMinor: 20000,
      commissionBps: 1000,
      commissionMinor: 2000,
      artistNetMinor: 18000,
      currency: "usd",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW,
      artistAcceptedTermsAt: NOW,
      confirmedAt: NOW,
      payoutHold: false,
      paidMinor: 20000,
      refundedMinor: 0,
      createdBy: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    await ctx.db.patch(slotId, { bookingId });
    const paymentRecordIds: Id<"paymentRecords">[] = [];
    for (const [index, amountMinor] of [12000, 8000].entries()) {
      paymentRecordIds.push(
        await ctx.db.insert("paymentRecords", {
          bookingId,
          installmentIndex: index,
          label: index === 0 ? "Deposit" : "Balance",
          amountMinor,
          currency: "usd",
          dueAt: NOW,
          status: "paid",
          stripeChargeId: index === 0 ? "ch_a" : "ch_b",
          stripePaymentIntentId: index === 0 ? "pi_a" : "pi_b",
          attempt: 0,
          paidAt: NOW,
          refundedMinor: 0,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
    }
    return {
      users,
      organizationId,
      bandId,
      opportunityId,
      slotId,
      applicationId,
      bookingId,
      paymentRecordIds,
    };
  });
  return {
    t,
    as,
    ...ids,
    cancel: (actor: "owner" | "admin" = "owner") =>
      as(actor).mutation(api.bookings.cancel, {
        bookingId: ids.bookingId,
        expectedRevision: 3,
        reason: "Show cancelled",
      }),
    readBooking: () => t.run((ctx) => ctx.db.get(ids.bookingId)),
    records: () =>
      t.run((ctx) => paymentRecordsForBooking(ctx, ids.bookingId)),
    refunds: () =>
      t.run((ctx) =>
        ctx.db
          .query("refunds")
          .withIndex("by_bookingId", (q) =>
            q.eq("bookingId", ids.bookingId),
          )
          .take(50),
      ),
    payouts: () =>
      t.run((ctx) =>
        ctx.db
          .query("payouts")
          .withIndex("by_bookingId", (q) =>
            q.eq("bookingId", ids.bookingId),
          )
          .take(50),
      ),
    ledger: () =>
      t.run((ctx) =>
        ctx.db
          .query("ledgerEntries")
          .withIndex("by_bookingId", (q) =>
            q.eq("bookingId", ids.bookingId),
          )
          .take(50),
      ),
    scheduled: () =>
      t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
    deliver: (event: StripeEvent) =>
      t.mutation(internal.stripeWebhook.recordAndApply, {
        kind: "platform",
        event,
        receivedAt: Date.now(),
        livemodeMismatch: false,
      }),
    addRefund: (fields: Partial<Doc<"refunds">> = {}) =>
      t.run((ctx) =>
        ctx.db.insert("refunds", {
          bookingId: ids.bookingId,
          paymentRecordId: ids.paymentRecordIds[0],
          amountMinor: 2000,
          currency: "usd",
          reason: "admin",
          status: "pending",
          createdAt: NOW,
          updatedAt: NOW,
          ...fields,
        }),
      ),
    addPayout: (fields: Partial<Doc<"payouts">> = {}) =>
      t.run((ctx) =>
        ctx.db.insert("payouts", {
          bookingId: ids.bookingId,
          bandId: ids.bandId,
          paymentRecordId: ids.paymentRecordIds[0],
          kind: "completion",
          amountMinor: 10800,
          currency: "usd",
          status: "scheduled",
          scheduledFor: STARTS_AT + PAYOUT_DELAY_MS,
          attempt: 0,
          sourceChargeId: "ch_a",
          createdAt: NOW,
          updatedAt: NOW,
          ...fields,
        }),
      ),
  };
}

function disputeEvent(
  type: "charge.dispute.created" | "charge.dispute.closed",
  fields: Record<string, unknown> = {},
): StripeEvent {
  return {
    id:
      type === "charge.dispute.created"
        ? "evt_dispute_created"
        : "evt_dispute_closed",
    type,
    livemode: false,
    created: Date.now() / 1000,
    data: {
      object: {
        id: "dp_test",
        payment_intent: "pi_a",
        amount: 12000,
        ...fields,
      },
    },
  };
}

function chargeRefundedEvent(
  entries: unknown = [
    { id: "re_dashboard", amount: 2000, status: "succeeded" },
  ],
  paymentIntent: unknown = "pi_a",
): StripeEvent {
  return {
    id: "evt_charge_refunded",
    type: "charge.refunded",
    livemode: false,
    created: NOW / 1000,
    data: {
      object: {
        id: "ch_a",
        payment_intent: paymentIntent,
        refunds: { data: entries },
      },
    },
  };
}

describe("cancellation previews and access", () => {
  test.each([
    {
      days: 20,
      refundMinor: 20000,
      forfeitedMinor: 0,
      artistPayoutMinor: 0,
      shareBps: 10000,
    },
    {
      days: 10,
      refundMinor: 10000,
      forfeitedMinor: 10000,
      artistPayoutMinor: 9000,
      shareBps: 5000,
    },
    {
      days: 5,
      refundMinor: 0,
      forfeitedMinor: 20000,
      artistPayoutMinor: 18000,
      shareBps: 0,
    },
  ])(
    "previews organizer cancellation $days days before the show",
    async ({ days, ...amounts }) => {
      const f = await setupRefunds();
      const now = STARTS_AT - days * DAY_MS;
      expect(
        await f.as("owner").query(api.refunds.previewCancellation, {
          bookingId: f.bookingId,
          now,
        }),
      ).toEqual({
        ...amounts,
        paidMinor: 20000,
        template: "standard",
        cancelledBy: "organizer",
      });
      const settlement = await f.t.run((ctx) =>
        computeCancellationSettlement(ctx, {
          bookingId: f.bookingId,
          template: "standard",
          startsAt: STARTS_AT,
          cancelledBy: "organizer",
          artistNetMinor: 18000,
          commissionMinor: 2000,
          now,
        }),
      );
      expect(settlement.platformKeepsMinor).toBe(
        amounts.forfeitedMinor / 10,
      );
      expect(await f.refunds()).toEqual([]);
      expect(await f.scheduled()).toEqual([]);
    },
  );

  test.each([20, 10, 1])(
    "artist cancellation refunds everything %s days before the show",
    async (days) => {
      const f = await setupRefunds();
      expect(
        await f.as("admin").query(api.refunds.previewCancellation, {
          bookingId: f.bookingId,
          as: "artist",
          now: STARTS_AT - days * DAY_MS,
        }),
      ).toMatchObject({
        refundMinor: 20000,
        artistPayoutMinor: 0,
        forfeitedMinor: 0,
        cancelledBy: "artist",
      });
    },
  );

  test("counts only available paid balances, including partial refunds", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[0], {
        status: "partially_refunded",
        refundedMinor: 4000,
      });
      await ctx.db.patch(f.paymentRecordIds[1], { status: "pending" });
    });
    expect(
      await f.as("owner").query(api.refunds.previewCancellation, {
        bookingId: f.bookingId,
        now: STARTS_AT - 10 * DAY_MS,
      }),
    ).toMatchObject({
      paidMinor: 8000,
      refundMinor: 4000,
      artistPayoutMinor: 3600,
    });
    await f.t.run((ctx) =>
      ctx.db.patch(f.paymentRecordIds[0], { refundedMinor: 12000 }),
    );
    expect(
      await f.as("owner").query(api.refunds.previewCancellation, {
        bookingId: f.bookingId,
        now: NOW,
      }),
    ).toMatchObject({ paidMinor: 0, refundMinor: 0 });
  });

  test("restricts previews and refund summaries to cancellation parties", async () => {
    const f = await setupRefunds();
    await f.cancel();
    const rows = await f.refunds();
    await f.t.run((ctx) =>
      ctx.db.patch(rows[0]._id, { stripeRefundId: "re_private" }),
    );
    for (const actor of [
      "owner",
      "manager",
      "admin",
      "platformAdmin",
    ] as const) {
      expect(
        await f.as(actor).query(api.refunds.previewCancellation, {
          bookingId: f.bookingId,
          now: NOW,
        }),
      ).toMatchObject({
        cancelledBy: actor === "admin" ? "artist" : "organizer",
      });
      expect(
        await f.as(actor).query(api.refunds.refundsForBooking, {
          bookingId: f.bookingId,
        }),
      ).toEqual(
        rows.map((row) => ({
          _id: row._id,
          paymentRecordId: row.paymentRecordId,
          amountMinor: row.amountMinor,
          currency: row.currency,
          reason: row.reason,
          status: row.status,
          createdAt: row.createdAt,
        })),
      );
    }
    for (const actor of [
      "finance",
      "door",
      "member",
      "stranger",
    ] as const) {
      await expect(
        f.as(actor).query(api.refunds.previewCancellation, {
          bookingId: f.bookingId,
          now: NOW,
        }),
      ).rejects.toThrow(
        "Not permitted to view this booking's cancellation terms",
      );
      await expect(
        f.as(actor).query(api.refunds.refundsForBooking, {
          bookingId: f.bookingId,
        }),
      ).rejects.toThrow(
        "Not permitted to view this booking's cancellation terms",
      );
    }
    await expect(
      f.t.query(api.refunds.previewCancellation, {
        bookingId: f.bookingId,
        now: NOW,
      }),
    ).rejects.toThrow("Not signed in");
    await expect(
      f.t.query(api.refunds.refundsForBooking, {
        bookingId: f.bookingId,
      }),
    ).rejects.toThrow("Not signed in");
  });

  test("defaults dual members to organizer and honors only authorized side overrides", async () => {
    const f = await setupRefunds();
    const args = { bookingId: f.bookingId, now: STARTS_AT - 10 * DAY_MS };
    expect(
      await f.as("owner").query(api.refunds.previewCancellation, {
        ...args,
        as: "artist",
      }),
    ).toMatchObject({ cancelledBy: "organizer", refundMinor: 10000 });
    expect(
      await f.as("admin").query(api.refunds.previewCancellation, {
        ...args,
        as: "organizer",
      }),
    ).toMatchObject({ cancelledBy: "artist", refundMinor: 20000 });
    await f.t.run((ctx) =>
      ctx.db.insert("bandMembers", {
        bandId: f.bandId,
        userId: f.users.owner,
        role: "admin",
      }),
    );
    expect(
      await f.as("owner").query(api.refunds.previewCancellation, args),
    ).toMatchObject({ cancelledBy: "organizer", refundMinor: 10000 });
    expect(
      await f.as("owner").query(api.refunds.previewCancellation, {
        ...args,
        as: "artist",
      }),
    ).toMatchObject({ cancelledBy: "artist", refundMinor: 20000 });
  });
});

describe("cancellation settlement", () => {
  test("allocates refunds LIFO and splits the artist forfeiture across paid charges", async () => {
    const f = await setupRefunds();
    vi.setSystemTime(STARTS_AT - 10 * DAY_MS);
    await f.cancel();
    const rows = await f.refunds();
    expect(rows).toHaveLength(2);
    expect(rows).toMatchObject([
      {
        paymentRecordId: f.paymentRecordIds[1],
        amountMinor: 8000,
        status: "pending",
        reason: "organizer_cancel",
      },
      {
        paymentRecordId: f.paymentRecordIds[0],
        amountMinor: 2000,
        status: "pending",
        reason: "organizer_cancel",
      },
    ]);
    const payouts = await f.payouts();
    expect(payouts).toHaveLength(2);
    expect(payouts[0]).toMatchObject({
      kind: "forfeit",
      amountMinor: 3600,
      status: "scheduled",
      paymentRecordId: f.paymentRecordIds[1],
      sourceChargeId: "ch_b",
      scheduledFor: Date.now() + PAYOUT_DELAY_MS,
      attempt: 0,
    });
    expect(payouts[1]).toMatchObject({
      kind: "forfeit",
      amountMinor: 5400,
      status: "scheduled",
      paymentRecordId: f.paymentRecordIds[0],
      sourceChargeId: "ch_a",
      scheduledFor: Date.now() + PAYOUT_DELAY_MS,
      attempt: 0,
    });
    expect(await f.ledger()).toMatchObject([
      {
        kind: "commission",
        idempotencyKey: `forfeit-commission:${f.bookingId}`,
        amountMinor: 1000,
        fundsState: "available",
        organizationId: f.organizationId,
        bandId: f.bandId,
      },
    ]);
    expect(await f.readBooking()).toMatchObject({
      status: "cancelled_by_organizer",
      refundedMinor: 0,
    });
    const jobs = await f.scheduled();
    expect(
      jobs.filter((job) => job.name === "refunds:executeRefund"),
    ).toMatchObject(
      rows.map((row) => ({
        args: [{ refundId: row._id, attempt: 0 }],
        scheduledTime: Date.now(),
      })),
    );
    expect(
      jobs.filter((job) => job.name === "payouts:releasePayout"),
    ).toMatchObject(
      payouts.map((payout) => ({
        args: [{ payoutId: payout._id }],
        scheduledTime: Date.now() + PAYOUT_DELAY_MS,
      })),
    );
    expect(
      jobs.find((job) => job.name === "emails:send")?.args[0].text,
    ).toContain("Show cancelled Refund: 100.00 USD.");
    for (const payout of payouts) {
      await f.t.mutation(internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
      expect(await f.t.run((ctx) => ctx.db.get(payout._id))).toMatchObject({
        status: "processing",
      });
    }
  });

  test("artist cancellation schedules full refunds and no forfeiture", async () => {
    const f = await setupRefunds();
    vi.setSystemTime(STARTS_AT - DAY_MS);
    await f.cancel("admin");
    expect(await f.refunds()).toMatchObject([
      { amountMinor: 8000, reason: "artist_cancel" },
      { amountMinor: 12000, reason: "artist_cancel" },
    ]);
    expect(await f.payouts()).toEqual([]);
    expect(await f.ledger()).toEqual([]);
  });

  test("settles installments already paid while awaiting payment and still schedules Checkout cleanup", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.bookingId, {
        status: "awaiting_payment",
        paidMinor: 12000,
      });
      await ctx.db.patch(f.applicationId, { status: "offered" });
      await ctx.db.patch(f.paymentRecordIds[1], {
        status: "checkout_open",
        stripeCheckoutSessionId: "cs_balance",
      });
    });
    await f.cancel();
    expect(await f.refunds()).toMatchObject([
      {
        paymentRecordId: f.paymentRecordIds[0],
        amountMinor: 12000,
        reason: "organizer_cancel",
      },
    ]);
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payments:expireOpenSessions",
      ),
    ).toHaveLength(1);
  });

  test.each(["force_majeure", "refunded"] as const)(
    "admin %s refunds all paid installments and honors dry-run",
    async (status) => {
      const f = await setupRefunds();
      if (status === "refunded") {
        await f.t.run((ctx) =>
          ctx.db.patch(f.bookingId, { status: "paid" }),
        );
      }
      const args = {
        bookingId: f.bookingId,
        status,
        reason: "Admin cancellation",
      };
      expect(
        await f.t.mutation(internal.bookings.adminForceState, args),
      ).toMatchObject({ applied: false });
      expect(await f.refunds()).toEqual([]);
      expect(await f.scheduled()).toEqual([]);
      await f.t.mutation(internal.bookings.adminForceState, {
        ...args,
        dryRun: false,
      });
      const rows = await f.refunds();
      expect(rows).toHaveLength(2);
      expect(rows).toMatchObject([
        {
          amountMinor: 8000,
          reason: status === "force_majeure" ? "force_majeure" : "admin",
          status: "pending",
        },
        {
          amountMinor: 12000,
          reason: status === "force_majeure" ? "force_majeure" : "admin",
          status: "pending",
        },
      ]);
      expect(rows.reduce((sum, row) => sum + row.amountMinor, 0)).toBe(
        20000,
      );
      expect(await f.payouts()).toEqual([]);
      expect(await f.readBooking()).toMatchObject({
        status,
        refundedMinor: 0,
      });
    },
  );

  test("records refund and payout obligations even when payments are disabled", async () => {
    const f = await setupRefunds();
    vi.stubEnv("PAYMENTS_ENABLED", "false");
    vi.setSystemTime(STARTS_AT - 10 * DAY_MS);
    await f.cancel();
    expect(await f.refunds()).toHaveLength(2);
    expect(await f.payouts()).toHaveLength(2);
    const actual = await vi.importActual<
      typeof import("./lib/stripeClient")
    >("./lib/stripeClient");
    stripeMock.mockImplementation(actual.stripeRequest);
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const [refund] = await f.refunds();
    await f.t.action(internal.refunds.executeRefund, {
      refundId: refund._id,
      attempt: 0,
    });
    expect((await f.refunds())[0].status).toBe("pending");
    expect(log).toHaveBeenCalledWith(
      expect.stringContaining(refund._id),
      expect.objectContaining({ message: "Payments are not enabled" }),
    );
    expect(
      (await f.scheduled()).filter(
        (job) =>
          job.name === "refunds:executeRefund" && job.args[0].attempt === 1,
      ),
    ).toHaveLength(1);
  });
});

describe("refund execution", () => {
  test("leaves a refund pending without retry when Stripe succeeds but accounting throws", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund();
    stripeMock.mockImplementationOnce(async () => {
      // Force the following success mutation to fail its payment transition.
      // Its partial writes must roll back while the Stripe POST has succeeded.
      await f.t.run((ctx) =>
        ctx.db.patch(f.paymentRecordIds[0], { status: "checkout_open" }),
      );
      return { id: "re_post_succeeded" };
    });
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    await expect(
      f.t.action(internal.refunds.executeRefund, {
        refundId,
        attempt: 0,
      }),
    ).rejects.toThrow(
      "Payment cannot go from checkout_open to partially_refunded",
    );
    const [refund] = await f.refunds();
    expect(refund.status).toBe("pending");
    expect(refund.stripeRefundId).toBeUndefined();
    expect(await f.scheduled()).toEqual([]);
    expect(await f.ledger()).toEqual([]);
    expect(await f.readBooking()).toMatchObject({ refundedMinor: 0 });
    expect(stripeMock).toHaveBeenCalledTimes(1);
    expect(log).not.toHaveBeenCalled();

    await f.t.run((ctx) =>
      ctx.db.patch(f.paymentRecordIds[0], { status: "paid" }),
    );
    expect(
      await f.deliver(
        chargeRefundedEvent([
          {
            id: "re_post_succeeded",
            amount: 2000,
            status: "succeeded",
            metadata: { refundId },
          },
        ]),
      ),
    ).toEqual({ outcome: "applied" });
    expect(await f.refunds()).toMatchObject([
      {
        _id: refundId,
        status: "succeeded",
        stripeRefundId: "re_post_succeeded",
      },
    ]);
    expect(await f.ledger()).toHaveLength(1);
    expect(await f.readBooking()).toMatchObject({ refundedMinor: 2000 });
    expect(await f.scheduled()).toEqual([]);
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });

  test("re-drives failed refunds only when payments are enabled", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({ status: "failed" });
    const rows = await f.refunds();
    for (const value of [undefined, "false"]) {
      vi.stubEnv("PAYMENTS_ENABLED", value);
      await f.t.mutation(internal.refunds.retryFailedRefunds, {});
      expect(await f.refunds()).toEqual(rows);
      expect(await f.scheduled()).toEqual([]);
    }
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    vi.setSystemTime(NOW + 6 * 60 * 60 * 1000);
    await f.t.mutation(internal.refunds.retryFailedRefunds, {});
    expect(await f.refunds()).toMatchObject([
      {
        _id: refundId,
        status: "pending",
        updatedAt: Date.now(),
      },
    ]);
    const jobs = await f.scheduled();
    expect(jobs).toMatchObject([
      {
        name: "refunds:executeRefund",
        args: [{ refundId, attempt: 0 }],
        scheduledTime: Date.now(),
      },
    ]);
    await f.t.mutation(internal.refunds.retryFailedRefunds, {});
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("settles full and partial refunds and ignores success replays", async () => {
    const f = await setupRefunds();
    vi.setSystemTime(STARTS_AT - 10 * DAY_MS);
    await f.cancel();
    const rows = await f.refunds();
    let refundedMinor = 0;
    for (const [index, refund] of rows.entries()) {
      await f.t.action(internal.refunds.executeRefund, {
        refundId: refund._id,
        attempt: 0,
      });
      const stripeRefundId = `re_test_${index + 1}`;
      refundedMinor += refund.amountMinor;
      expect(await f.t.run((ctx) => ctx.db.get(refund._id))).toMatchObject({
        status: "succeeded",
        stripeRefundId,
      });
      expect(
        await f.t.run((ctx) => ctx.db.get(refund.paymentRecordId)),
      ).toMatchObject({
        status: index === 0 ? "refunded" : "partially_refunded",
        refundedMinor: refund.amountMinor,
      });
      expect(await f.readBooking()).toMatchObject({ refundedMinor });
      expect(stripeMock).toHaveBeenNthCalledWith(
        index + 1,
        "POST",
        "/v1/refunds",
        {
          payment_intent: index === 0 ? "pi_b" : "pi_a",
          amount: refund.amountMinor,
          metadata: {
            bookingId: f.bookingId,
            refundId: refund._id,
            reason: "organizer_cancel",
          },
        },
        { idempotencyKey: `refund:${refund._id}` },
      );
      const ledger = await f.ledger();
      expect(ledger).toContainEqual(
        expect.objectContaining({
          kind: "refund",
          idempotencyKey: `refund:${stripeRefundId}`,
          amountMinor: -refund.amountMinor,
          fundsState: "refunded",
        }),
      );
      await f.t.mutation(internal.refunds.markRefundSucceeded, {
        refundId: refund._id,
        stripeRefundId,
      });
      await f.t.action(internal.refunds.executeRefund, {
        refundId: refund._id,
        attempt: 0,
      });
      await f.t.mutation(internal.refunds.markRefundFailed, {
        refundId: refund._id,
        attempt: 0,
      });
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.readBooking()).toMatchObject({ refundedMinor });
    }
    expect(stripeMock).toHaveBeenCalledTimes(2);
    expect(
      (await f.ledger()).filter((row) => row.kind === "refund"),
    ).toHaveLength(2);
  });

  test("retries hourly after failure and stops after the third attempt", async () => {
    const f = await setupRefunds();
    await f.cancel();
    const [refund] = await f.refunds();
    stripeMock.mockRejectedValue(new Error("Refund unavailable"));
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    for (const attempt of [0, 1, 2]) {
      vi.setSystemTime(NOW + attempt * 60 * 60 * 1000);
      const before = await f.scheduled();
      await f.t.action(internal.refunds.executeRefund, {
        refundId: refund._id,
        attempt,
      });
      expect(await f.t.run((ctx) => ctx.db.get(refund._id))).toMatchObject({
        status: attempt < 2 ? "pending" : "failed",
      });
      const newJobs = (await f.scheduled()).filter(
        (job) => !before.some((old) => old._id === job._id),
      );
      if (attempt < 2) {
        expect(newJobs).toHaveLength(1);
        expect(newJobs[0]).toMatchObject({
          name: "refunds:executeRefund",
          args: [{ refundId: refund._id, attempt: attempt + 1 }],
          scheduledTime: Date.now() + 60 * 60 * 1000,
        });
      } else {
        expect(newJobs).toEqual([]);
      }
    }
    expect(
      stripeMock.mock.calls.map((call) => call[3]?.idempotencyKey),
    ).toEqual(
      [0, 1, 2].map(() => `refund:${refund._id}`),
    );
    expect(log).toHaveBeenCalledTimes(3);
    expect(await f.readBooking()).toMatchObject({ refundedMinor: 0 });
    expect(await f.ledger()).toEqual([]);
  });

  test("schedules a proportional reversal for a paid completion transfer and records it once", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout({
      status: "paid",
      stripeTransferId: "tr_paid",
    });
    vi.setSystemTime(STARTS_AT - 10 * DAY_MS);
    await f.cancel();
    const refund = (await f.refunds()).find(
      (row) => row.paymentRecordId === f.paymentRecordIds[0],
    )!;
    await f.t.action(internal.refunds.executeRefund, {
      refundId: refund._id,
      attempt: 0,
    });
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "refunds:reverseTransfer",
      ),
    ).toMatchObject([
      {
        args: [{ payoutId, reversalMinor: 1800 }],
        scheduledTime: Date.now(),
      },
    ]);
    stripeMock.mockResolvedValueOnce({ id: "trr_test" });
    await f.t.action(internal.refunds.reverseTransfer, {
      payoutId,
      reversalMinor: 1800,
    });
    expect(stripeMock).toHaveBeenLastCalledWith(
      "POST",
      "/v1/transfers/tr_paid/reversals",
      { amount: 1800 },
      { idempotencyKey: `reversal:${payoutId}:1800` },
    );
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "paid",
      reversedMinor: 1800,
      stripeTransferReversalId: "trr_test",
    });
    expect(
      (await f.ledger()).filter((row) => row.kind === "transfer_reversal"),
    ).toMatchObject([
      {
        idempotencyKey: "transfer_reversal:trr_test",
        amountMinor: -1800,
        fundsState: "refunded",
        bandId: f.bandId,
      },
    ]);
    const ledger = await f.ledger();
    await f.t.mutation(internal.refunds.markTransferReversed, {
      payoutId,
      reversalMinor: 1800,
      reversedMinor: 1800,
      stripeTransferReversalId: "trr_test",
    });
    expect(await f.ledger()).toEqual(ledger);
  });

  test("a second partial refund reverses only the additional excess and persists the cumulative total", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout({
      status: "paid",
      stripeTransferId: "tr_paid",
      reversedMinor: 1800,
    });
    await f.addRefund({
      status: "succeeded",
      stripeRefundId: "re_prior",
    });
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[0], {
        status: "partially_refunded",
        refundedMinor: 2000,
      });
      await ctx.db.patch(f.bookingId, { refundedMinor: 2000 });
    });
    const refundId = await f.addRefund({ amountMinor: 3000 });
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_second",
    });
    expect(await f.scheduled()).toMatchObject([
      {
        name: "refunds:reverseTransfer",
        args: [{ payoutId, reversalMinor: 2700 }],
      },
    ]);
    stripeMock.mockResolvedValueOnce({ id: "trr_second" });
    await f.t.action(internal.refunds.reverseTransfer, {
      payoutId,
      reversalMinor: 2700,
    });
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/transfers/tr_paid/reversals",
      { amount: 2700 },
      { idempotencyKey: `reversal:${payoutId}:4500` },
    );
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "paid",
      reversedMinor: 4500,
      stripeTransferReversalId: "trr_second",
    });
    expect((await f.records())[0]).toMatchObject({ refundedMinor: 5000 });
    expect(await f.ledger()).toContainEqual(
      expect.objectContaining({
        kind: "transfer_reversal",
        amountMinor: -2700,
      }),
    );
  });

  test("does not schedule another reversal when the payout is already fully reversed", async () => {
    const f = await setupRefunds();
    await f.addPayout({ status: "paid", reversedMinor: 10800 });
    const refundId = await f.addRefund();
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_no_reversal",
    });
    expect(await f.scheduled()).toEqual([]);
  });

  test("reversal failures do not retry or change refund accounting", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout({
      status: "paid",
      stripeTransferId: "tr_paid",
    });
    await f.cancel();
    const refund = (await f.refunds()).find(
      (row) => row.paymentRecordId === f.paymentRecordIds[0],
    )!;
    await f.t.action(internal.refunds.executeRefund, {
      refundId: refund._id,
      attempt: 0,
    });
    const jobs = await f.scheduled();
    const ledger = await f.ledger();
    stripeMock.mockRejectedValueOnce(new Error("Reversal unavailable"));
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    await f.t.action(internal.refunds.reverseTransfer, {
      payoutId,
      reversalMinor: 10800,
    });
    expect(log).toHaveBeenCalledTimes(1);
    expect(await f.scheduled()).toEqual(jobs);
    expect(await f.ledger()).toEqual(ledger);
    expect(await f.readBooking()).toMatchObject({ refundedMinor: 12000 });
  });
});

describe("late payments", () => {
  test.each(["paid", "partially_refunded", "refunded"] as const)(
    "refunds the extra intent without changing the original %s installment or payout",
    async (status) => {
      const f = await setupRefunds();
      await f.addPayout({
        status: "paid",
        stripeTransferId: "tr_original",
      });
      await f.t.run((ctx) =>
        ctx.db.patch(f.paymentRecordIds[0], { status }),
      );
      const records = await f.records();
      const booking = await f.readBooking();
      const payouts = await f.payouts();
      await f.t.mutation(internal.refunds.refundLatePaymentIntent, {
        paymentRecordId: f.paymentRecordIds[0],
        paymentIntentId: "pi_extra",
        amountMinor: 12000,
        eventId: "evt_extra",
      });
      const [refund] = await f.refunds();
      const jobs = await f.scheduled();
      await f.t.action(internal.refunds.executeRefund, {
        refundId: refund._id,
        attempt: 0,
      });
      expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
        "POST",
        "/v1/refunds",
        expect.objectContaining({
          payment_intent: "pi_extra",
          amount: 12000,
        }),
        { idempotencyKey: `refund:${refund._id}` },
      );
      expect(await f.refunds()).toMatchObject([
        {
          _id: refund._id,
          status: "succeeded",
          stripeRefundId: "re_test_1",
        },
      ]);
      expect(await f.records()).toEqual(records);
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.payouts()).toEqual(payouts);
      expect(await f.scheduled()).toEqual(jobs);
      expect(await f.ledger()).toMatchObject([
        {
          kind: "refund",
          idempotencyKey: "refund:re_test_1",
          amountMinor: -12000,
        },
      ]);
    },
  );

  test("refunds Checkout completion after cancellation without reviving the booking", async () => {
    const f = await setupRefunds();
    // Reuse the parties, then exercise a fresh offer/accept/Checkout flow.
    await f.t.run(async (ctx) => {
      for (const id of f.paymentRecordIds) await ctx.db.delete(id);
      await ctx.db.delete(f.bookingId);
      await ctx.db.patch(f.slotId, {
        status: "open",
        bookingId: undefined,
        bandId: undefined,
      });
      await ctx.db.patch(f.applicationId, { status: "shortlisted" });
      await ctx.db.patch(f.opportunityId, {
        status: "open",
        applicationCount: 1,
      });
    });
    const offer = await f.as("owner").mutation(api.bookings.sendOffer, {
      applicationId: f.applicationId,
      grossMinor: 20000,
      cancellationTemplate: "standard",
    });
    await f.as("admin").mutation(api.bookings.respond, {
      bookingId: offer.bookingId,
      action: "accept",
      expectedRevision: 1,
    });
    const [record] = await f.t.run((ctx) =>
      paymentRecordsForBooking(ctx, offer.bookingId),
    );
    await f.t.mutation(internal.payments.markCheckoutOpen, {
      paymentRecordId: record._id,
      sessionId: "cs_late",
      checkoutExpiresAt: NOW + CHECKOUT_TTL_MS,
      attempt: record.attempt,
    });
    await f.as("owner").mutation(api.bookings.cancel, {
      bookingId: offer.bookingId,
      expectedRevision: 3,
      reason: "Show cancelled",
    });
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payments:expireOpenSessions",
      ),
    ).toHaveLength(1);
    const event: StripeEvent = {
      id: "evt_late",
      type: "checkout.session.completed",
      livemode: false,
      created: NOW / 1000,
      data: {
        object: {
          id: "cs_late",
          amount_total: 20000,
          currency: "usd",
          payment_intent: { id: "pi_late", latest_charge: "ch_late" },
          metadata: {
            paymentRecordId: record._id,
            bookingId: offer.bookingId,
          },
        },
      },
    };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const rows = await f.t.run((ctx) =>
      ctx.db
        .query("refunds")
        .withIndex("by_bookingId", (q) =>
          q.eq("bookingId", offer.bookingId),
        )
        .take(50),
    );
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      paymentRecordId: record._id,
      amountMinor: 20000,
      reason: "late_payment",
      status: "pending",
      stripeEventId: "evt_late",
    });
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "refunds:executeRefund",
      ),
    ).toMatchObject([
      {
        args: [{ refundId: rows[0]._id, attempt: 0 }],
        scheduledTime: NOW,
      },
    ]);
    expect(
      await f.t.run((ctx) => ctx.db.get(offer.bookingId)),
    ).toMatchObject({
      status: "cancelled_by_organizer",
      paidMinor: 20000,
      payoutHold: true,
    });
    const jobs = await f.scheduled();
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    await f.t.mutation(internal.refunds.refundLatePayment, {
      paymentRecordId: record._id,
      eventId: "evt_replay",
    });
    expect(await f.scheduled()).toEqual(jobs);
    expect(
      await f.t.run((ctx) => ctx.db.query("refunds").take(50)),
    ).toEqual(rows);
  });
});

describe("charge refund reconciliation", () => {
  test("reconciles a dashboard refund and its proportional reversal exactly once", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout({
      status: "paid",
      stripeTransferId: "tr_paid",
    });
    const event = chargeRefundedEvent(undefined, { id: "pi_a" });
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const rows = await f.refunds();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      bookingId: f.bookingId,
      paymentRecordId: f.paymentRecordIds[0],
      amountMinor: 2000,
      reason: "admin",
      status: "succeeded",
      stripeRefundId: "re_dashboard",
      stripePaymentIntentId: "pi_a",
    });
    const records = await f.records();
    expect(records[0]).toMatchObject({
      status: "partially_refunded",
      refundedMinor: 2000,
    });
    const booking = await f.readBooking();
    expect(booking).toMatchObject({ refundedMinor: 2000 });
    const ledger = await f.ledger();
    expect(ledger).toMatchObject([
      {
        kind: "refund",
        idempotencyKey: "refund:re_dashboard",
        stripeRef: "re_dashboard",
        amountMinor: -2000,
        currency: "usd",
        fundsState: "refunded",
        bookingId: f.bookingId,
        organizationId: f.organizationId,
        bandId: f.bandId,
      },
    ]);
    const jobs = await f.scheduled();
    expect(jobs).toMatchObject([
      {
        name: "refunds:reverseTransfer",
        args: [{ payoutId, reversalMinor: 1800 }],
      },
    ]);
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
      eventJson: JSON.stringify(event),
    });
    expect(await f.refunds()).toEqual(rows);
    expect(await f.records()).toEqual(records);
    expect(await f.readBooking()).toEqual(booking);
    expect(await f.ledger()).toEqual(ledger);
    expect(await f.scheduled()).toEqual(jobs);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("a full dashboard refund reverses scheduled and held payouts across the booking", async () => {
    const f = await setupRefunds();
    const scheduledId = await f.addPayout();
    const heldId = await f.addPayout({
      status: "held",
      paymentRecordId: f.paymentRecordIds[1],
    });
    expect(
      await f.deliver(
        chargeRefundedEvent([
          {
            id: "re_full",
            amount: 12000,
            status: "succeeded",
          },
        ]),
      ),
    ).toEqual({ outcome: "applied" });
    expect(await f.payouts()).toMatchObject([
      { _id: scheduledId, status: "reversed", updatedAt: NOW },
      { _id: heldId, status: "reversed", updatedAt: NOW },
    ]);
    expect((await f.records())[0]).toMatchObject({
      status: "refunded",
      refundedMinor: 12000,
    });
    expect(await f.readBooking()).toMatchObject({
      refundedMinor: 12000,
    });
    expect(await f.scheduled()).toEqual([]);
  });

  test.each(["pending", "failed", "succeeded"] as const)(
    "reuses a known Stripe refund in %s state without duplicating accounting",
    async (status) => {
      const f = await setupRefunds();
      const refundId = await f.addRefund({
        stripeRefundId: "re_test_1",
      });
      if (status === "succeeded") {
        await f.t.action(internal.refunds.executeRefund, {
          refundId,
          attempt: 0,
        });
      } else if (status === "failed") {
        await f.t.mutation(internal.refunds.markRefundFailed, {
          refundId,
          attempt: 2,
        });
      }
      const event = chargeRefundedEvent([
        {
          id: "re_test_1",
          amount: 2000,
          status: "succeeded",
        },
      ]);
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      expect(await f.refunds()).toMatchObject([
        {
          _id: refundId,
          stripeRefundId: "re_test_1",
          status: "succeeded",
        },
      ]);
      expect(await f.readBooking()).toMatchObject({
        refundedMinor: 2000,
      });
      expect((await f.records())[0]).toMatchObject({
        refundedMinor: 2000,
      });
      expect(await f.ledger()).toHaveLength(1);
      const ledger = await f.ledger();
      await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
      expect(await f.refunds()).toHaveLength(1);
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.readBooking()).toMatchObject({
        refundedMinor: 2000,
      });
    },
  );

  test("reconciles a pending extra-intent refund without reversing the original payment's payouts", async () => {
    const f = await setupRefunds();
    await f.addPayout();
    const refundId = await f.addRefund({
      reason: "late_payment",
      stripePaymentIntentId: "pi_extra",
    });
    const records = await f.records();
    const booking = await f.readBooking();
    const payouts = await f.payouts();
    expect(
      await f.deliver(
        chargeRefundedEvent(
          [
            {
              id: "re_extra",
              amount: 2000,
              status: "succeeded",
              metadata: { refundId },
            },
          ],
          "pi_extra",
        ),
      ),
    ).toEqual({ outcome: "applied" });
    expect(await f.refunds()).toMatchObject([
      {
        _id: refundId,
        stripeRefundId: "re_extra",
        status: "succeeded",
      },
    ]);
    expect(await f.ledger()).toHaveLength(1);
    expect(await f.records()).toEqual(records);
    expect(await f.readBooking()).toEqual(booking);
    expect(await f.payouts()).toEqual(payouts);
    expect(await f.scheduled()).toEqual([]);
  });

  test.each([
    null,
    "invalid",
    [
      null,
      {},
      { id: "re_failed", amount: 2000, status: "failed" },
      { id: "re_invalid", amount: "invalid", status: "succeeded" },
    ],
  ])(
    "ignores malformed and unsuccessful refund entries: %j",
    async (entries) => {
      const f = await setupRefunds();
      await f.addPayout();
      const booking = await f.readBooking();
      const payouts = await f.payouts();
      expect(await f.deliver(chargeRefundedEvent(entries))).toEqual({
        outcome: "applied",
      });
      expect(await f.refunds()).toEqual([]);
      expect(await f.ledger()).toEqual([]);
      expect(await f.scheduled()).toEqual([]);
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.payouts()).toEqual(payouts);
    },
  );
});

describe("Stripe disputes", () => {
  test("creation holds the booking and scheduled payouts and replays without duplicating ledger entries", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const event = disputeEvent("charge.dispute.created", {
      payment_intent: { id: "pi_a" },
    });
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toMatchObject({
      status: "disputed",
      disputedFromStatus: "confirmed",
      payoutHoldReasons: ["dispute"],
      payoutHold: true,
      revision: 4,
    });
    expect((await f.records())[0]).toMatchObject({
      stripeDisputeId: "dp_test",
      disputedMinor: 12000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "held",
      holdReason: "dispute",
    });
    const ledger = await f.ledger();
    expect(ledger).toHaveLength(1);
    expect(ledger[0]).toMatchObject({
      idempotencyKey: "dispute-hold:dp_test",
      kind: "dispute_hold",
      amountMinor: -12000,
      fundsState: "disputed",
    });
    await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
      eventJson: JSON.stringify(event),
    });
    expect(await f.readBooking()).toMatchObject({
      revision: 4,
      payoutHoldReasons: ["dispute"],
    });
    expect(await f.ledger()).toEqual(ledger);
    expect(await f.scheduled()).toEqual([]);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test.each([false, true])(
    "a won dispute restores the booking and preserves other holds: %s",
    async (otherHold) => {
      const f = await setupRefunds();
      const payoutId = await f.addPayout();
      if (otherHold) {
        await f.t.run((ctx) =>
          ctx.db.patch(f.bookingId, {
            payoutHoldReasons: ["admin"],
            payoutHold: true,
          }),
        );
      }
      expect(
        await f.deliver(disputeEvent("charge.dispute.created")),
      ).toEqual({ outcome: "applied" });
      const event = disputeEvent("charge.dispute.closed", {
        status: "won",
        payment_intent: { id: "pi_a" },
      });
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const booking = await f.readBooking();
      expect(booking).toMatchObject({
        status: "confirmed",
        revision: 5,
        payoutHoldReasons: otherHold ? ["admin"] : [],
        payoutHold: otherHold,
      });
      expect(booking?.disputedFromStatus).toBeUndefined();
      expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
        status: "scheduled",
      });
      const ledger = await f.ledger();
      expect(
        ledger.filter((row) => row.kind === "dispute_release"),
      ).toMatchObject([
        {
          idempotencyKey: "dispute-release:dp_test",
          amountMinor: 12000,
          fundsState: "available",
        },
      ]);
      const jobs = await f.scheduled();
      expect(jobs).toMatchObject([
        {
          name: "payouts:releasePayout",
          args: [{ payoutId }],
          scheduledTime: NOW,
        },
      ]);
      const log = vi.spyOn(console, "log").mockImplementation(() => {});
      await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
      expect(log).toHaveBeenCalledTimes(1);
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.scheduled()).toEqual(jobs);
    },
  );

  test.each([
    { balance_transactions: undefined, fee: 0 },
    {
      balance_transactions: [
        { fee: 700 },
        { fee: 1000 },
        { fee: "ignored" },
        null,
      ],
      fee: 1700,
    },
    { balance_transactions: [{ fee: 0 }], fee: 0 },
    { balance_transactions: [{ fee: "invalid" }], fee: 0 },
  ])(
    "a lost dispute refunds the record, records fee $fee, and reverses paid transfers",
    async ({ balance_transactions, fee }) => {
      const f = await setupRefunds();
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
      const payoutId = await f.addPayout({
        status: "paid",
        stripeTransferId: "tr_paid",
        reversedMinor: 1800,
      });
      await f.addPayout({
        status: "paid",
        paymentRecordId: f.paymentRecordIds[1],
        stripeTransferId: "tr_other",
      });
      expect(
        await f.deliver(
          disputeEvent("charge.dispute.created", { amount: "invalid" }),
        ),
      ).toEqual({ outcome: "applied" });
      const event = disputeEvent("charge.dispute.closed", {
        status: "lost",
        balance_transactions,
      });
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const hasFee = balance_transactions?.some(
        (entry) => typeof entry?.fee === "number",
      );
      if (hasFee) {
        expect(warn).not.toHaveBeenCalled();
      } else {
        expect(warn).toHaveBeenCalledExactlyOnceWith(
          "Dispute dp_test: fee data unavailable; recorded a $0 fee for later reconciliation",
        );
      }
      const booking = await f.readBooking();
      expect(booking).toMatchObject({
        status: "refunded",
        refundedMinor: 12000,
        payoutHold: true,
        payoutHoldReasons: ["dispute"],
      });
      expect(booking?.disputedFromStatus).toBeUndefined();
      expect((await f.records())[0]).toMatchObject({
        status: "refunded",
        refundedMinor: 12000,
      });
      const ledger = await f.ledger();
      expect(ledger).toHaveLength(3);
      expect(
        ledger.filter((row) => row.kind === "dispute_loss"),
      ).toMatchObject([
        {
          idempotencyKey: "dispute-loss:dp_test",
          amountMinor: -12000,
          fundsState: "refunded",
        },
      ]);
      expect(
        ledger.filter((row) => row.kind === "dispute_fee"),
      ).toMatchObject([
        {
          idempotencyKey: "dispute-fee:dp_test",
          amountMinor: -fee,
          fundsState: "refunded",
        },
      ]);
      const jobs = await f.scheduled();
      expect(jobs).toMatchObject([
        {
          name: "refunds:reverseTransfer",
          args: [{ payoutId, reversalMinor: 9000 }],
        },
      ]);
      vi.spyOn(console, "log").mockImplementation(() => {});
      await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.scheduled()).toEqual(jobs);
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test("ignores unknown payment intents and nonterminal dispute outcomes", async () => {
    const f = await setupRefunds();
    const booking = await f.readBooking();
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    for (const type of [
      "charge.dispute.created",
      "charge.dispute.closed",
    ] as const) {
      expect(
        await f.deliver(
          disputeEvent(type, { payment_intent: "pi_unknown" }),
        ),
      ).toEqual({ outcome: "applied" });
    }
    await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
      eventJson: JSON.stringify(
        disputeEvent("charge.dispute.closed", { status: "under_review" }),
      ),
    });
    expect(log).toHaveBeenCalledTimes(3);
    expect(await f.readBooking()).toEqual(booking);
    expect(await f.ledger()).toEqual([]);
    expect(await f.scheduled()).toEqual([]);
  });

  test("a lost dispute skips transfers already fully reversed", async () => {
    const f = await setupRefunds();
    await f.addPayout({
      status: "paid",
      stripeTransferId: "tr_reversed",
      reversedMinor: 10800,
    });
    expect(
      await f.deliver(disputeEvent("charge.dispute.created")),
    ).toEqual({ outcome: "applied" });
    expect(
      await f.deliver(disputeEvent("charge.dispute.closed", {
        status: "lost",
        balance_transactions: [{ fee: 0 }],
      })),
    ).toEqual({ outcome: "applied" });
    expect(await f.scheduled()).toEqual([]);
  });
});
