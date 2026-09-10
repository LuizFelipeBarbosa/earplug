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
import {
  applySettlement,
  computeCancellationSettlement,
  settleDisputeRefund,
} from "./lib/cancellationSettlement";
import { feeSnapshot } from "./lib/fees";
import { paymentRecordsForBooking } from "./lib/paymentSchedule";
import { CHECKOUT_TTL_MS, PAYOUT_DELAY_MS } from "./lib/paymentStatus";
import { stripeRequest } from "./lib/stripeClient";
import {
  asActor,
  DAY_MS,
  readers,
  seedMarketplace,
} from "./marketplaceFixtures.test-helpers";
import type * as payments from "./payments";
import type * as payouts from "./payouts";
import type * as refunds from "./refunds";
import schema from "./schema";
import type { StripeEvent } from "./stripeWebhook";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
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
const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-05T12:00:00Z");
const STARTS_AT = NOW + 30 * DAY_MS;
const stripeMock = vi.mocked(stripeRequest);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("BOOKING_COMMISSION_BPS", "1000");
  vi.stubEnv("RESEND_SEND_ENABLED", "false");
  vi.stubEnv("APP_BASE_URL", "https://earplug.test");
  let nextRefund = 0;
  stripeMock.mockReset();
  stripeMock.mockImplementation(async (method, path) => {
    if (method === "POST" && path === "/v1/refunds") {
      return { id: `re_test_${++nextRefund}`, status: "succeeded" };
    }
    if (method === "GET" && path.startsWith("/v1/refunds/"))
      return { id: path.split("/").at(-1), status: "succeeded" };
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
  const as = asActor(t, "refund");
  const ids = await seedMarketplace(t, {
    prefix: "refund",
    now: NOW,
    paymentRecords: [12000, 8000].map((amountMinor, index) => ({
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
    })),
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
    ...readers(t, ids),
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

function refundEvent(
  type:
    | "refund.created"
    | "refund.updated"
    | "refund.failed"
    | "charge.refund.updated",
  fields: Record<string, unknown> = {},
): StripeEvent {
  return {
    id: `evt_${type}`,
    type,
    livemode: false,
    created: NOW / 1000,
    data: {
      object: {
        id: "re_dashboard",
        charge: "ch_a",
        payment_intent: "pi_a",
        amount: 2000,
        currency: "usd",
        status: "succeeded",
        metadata: {},
        ...fields,
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
      expect(settlement.platformKeepsMinor).toBe(amounts.forfeitedMinor / 10);
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
    for (const actor of ["finance", "door", "member", "stranger"] as const) {
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

  test("installment offers remain readable", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
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
      installments: [
        { label: "Deposit", amountMinor: 12000, dueAfterAcceptanceDays: 0 },
        { label: "Balance", amountMinor: 8000, dueAfterAcceptanceDays: 3 },
      ],
    });
    const booking = await f
      .as("admin")
      .query(api.bookingsRead.get, { bookingId: offer.bookingId });
    expect(booking).not.toBeNull();
  });

  test("booking reads expose the newly maintained payment totals", async () => {
    const f = await setupRefunds();
    const booking = await f
      .as("owner")
      .query(api.bookingsRead.get, { bookingId: f.bookingId });
    expect(booking).toMatchObject({ paidMinor: 20000, refundedMinor: 0 });
  });
});

describe("cancellation settlement", () => {
  test("allocates refunds LIFO and funds the forfeiture from retained charges", async () => {
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
    expect(payouts).toHaveLength(1);
    expect(payouts[0]).toMatchObject({
      kind: "forfeit",
      amountMinor: 9000,
      originalAmountMinor: 9000,
      refundBaselineMinor: 2000,
      status: "scheduled",
      paymentRecordId: f.paymentRecordIds[0],
      sourceChargeId: "ch_a",
      scheduledFor: Date.now() + PAYOUT_DELAY_MS,
      attempt: 0,
    });
    expect(await f.ledger()).toMatchObject([
      {
        kind: "commission",
        // Keyed by the settlement's first refund so repeated partial settlements
        // on one booking each land their own commission row.
        idempotencyKey: expect.stringMatching(/^forfeit-commission:.*refunds$/),
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
        await f.t.run((ctx) => ctx.db.patch(f.bookingId, { status: "paid" }));
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
      expect(rows.reduce((sum, row) => sum + row.amountMinor, 0)).toBe(20000);
      expect(await f.payouts()).toEqual([]);
      expect(await f.readBooking()).toMatchObject({
        status,
        refundedMinor: 0,
      });
    },
  );

  test("cancellation refunds preserve and pay the artist forfeiture exactly once", async () => {
    const f = await setupRefunds();
    vi.setSystemTime(STARTS_AT - 10 * DAY_MS);
    await f.cancel();
    for (const refund of await f.refunds()) {
      await f.t.action(internal.refunds.executeRefund, {
        refundId: refund._id,
        attempt: 0,
      });
      const saved = await f.t.run((ctx) => ctx.db.get(refund._id));
      const record = await f.t.run((ctx) => ctx.db.get(refund.paymentRecordId));
      const event = chargeRefundedEvent(
        [
          {
            id: saved!.stripeRefundId,
            amount: refund.amountMinor,
            status: "succeeded",
            metadata: { refundId: refund._id },
          },
        ],
        record!.stripePaymentIntentId,
      );
      event.id = `evt_${refund._id}`;
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    }
    const [payout] = await f.payouts();
    expect(payout).toMatchObject({ status: "scheduled", amountMinor: 9000 });
    vi.setSystemTime(Date.now() + DAY_MS);
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    stripeMock.mockResolvedValueOnce({ id: "tr_forfeit" });
    await f.t.action(internal.payouts.executePayout, {
      payoutId: payout._id,
      attempt: 0,
    });
    expect(stripeMock).toHaveBeenLastCalledWith(
      "POST",
      "/v1/transfers",
      expect.objectContaining({ amount: 9000, source_transaction: "ch_a" }),
      expect.anything(),
    );
    expect(
      (await f.ledger())
        .filter((row) => row.kind === "commission")
        .map((row) => row.amountMinor),
    ).toEqual([1000]);
  });

  test("cancellation after only the deposit releases forfeited funds", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[1], {
        status: "pending",
        paidAt: undefined,
      });
      await ctx.db.patch(f.bookingId, {
        paidMinor: 12000,
        payoutHold: true,
        payoutHoldReasons: ["unpaid_installment"],
      });
    });
    vi.setSystemTime(STARTS_AT - DAY_MS);
    await f.cancel();
    vi.setSystemTime(STARTS_AT);
    const [payout] = await f.payouts();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    expect((await f.payouts())[0].status).toBe("processing");
  });
});

describe("explicit dispute settlement", () => {
  async function setupSettlement(
    amounts = [10000],
    payoutStatus: Doc<"payouts">["status"] = "scheduled",
    commissionBps = 1000,
  ) {
    const t = convexTest(schema, modules);
    const ids = await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", {
        clerkId: "settlement_owner",
        name: "Organizer",
        email: "owner@settlement.test",
        genres: [],
        attendedCount: 0,
      });
      const organizationId = await ctx.db.insert("organizations", {
        name: "Settlement Collective",
        slug: "settlement-collective",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: userId,
        createdAt: NOW,
        updatedAt: NOW,
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
      const opportunityId = await ctx.db.insert("talentOpportunities", {
        organizationId,
        mode: "privateBooking",
        area: "Oakland",
        title: "Private performance",
        desc: "An evening of local music.",
        genres: ["Indie"],
        startsAt: NOW,
        ageRequirement: "allAges",
        flyKey: "xerox",
        applicationsCloseAt: NOW,
        visibility: "public",
        ticketing: "rsvp",
        currency: "usd",
        status: "completed",
        slug: "private-performance",
        createdBy: userId,
        revision: 1,
        applicationCount: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const grossMinor = amounts.reduce((sum, amount) => sum + amount, 0);
      const slotId = await ctx.db.insert("opportunitySlots", {
        opportunityId,
        order: 0,
        role: "headliner",
        guaranteeMinor: grossMinor,
        required: true,
        status: "booked",
        bandId,
      });
      const applicationId = await ctx.db.insert("artistApplications", {
        opportunityId,
        slotId,
        bandId,
        submittedBy: userId,
        status: "booked",
        message: "Available",
        createdAt: NOW,
        updatedAt: NOW,
      });
      const bookingId = await ctx.db.insert("bookings", {
        opportunityId,
        slotId,
        organizationId,
        bandId,
        applicationId,
        status: "disputed",
        disputedFromStatus: payoutStatus === "paid" ? "paid" : "completed",
        revision: 4,
        startsAt: NOW,
        ...feeSnapshot(grossMinor, commissionBps),
        cancellationTemplate: "standard",
        organizerAcceptedTermsAt: NOW,
        artistAcceptedTermsAt: NOW,
        confirmedAt: NOW,
        completedAt: NOW,
        payoutHold: true,
        payoutHoldReasons: ["dispute"],
        paidMinor: grossMinor,
        refundedMinor: 0,
        createdBy: userId,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const paymentRecordIds: Id<"paymentRecords">[] = [];
      const payoutIds: Id<"payouts">[] = [];
      for (const [installmentIndex, amountMinor] of amounts.entries()) {
        const paymentRecordId = await ctx.db.insert("paymentRecords", {
          bookingId,
          installmentIndex,
          label: `Installment ${installmentIndex + 1}`,
          amountMinor,
          currency: "usd",
          dueAt: NOW,
          status: "paid",
          stripeChargeId: `ch_settlement_${installmentIndex}`,
          stripePaymentIntentId: `pi_settlement_${installmentIndex}`,
          attempt: 0,
          paidAt: NOW,
          refundedMinor: 0,
          createdAt: NOW,
          updatedAt: NOW,
        });
        paymentRecordIds.push(paymentRecordId);
        payoutIds.push(
          await ctx.db.insert("payouts", {
            bookingId,
            bandId,
            paymentRecordId,
            sourceChargeId: `ch_settlement_${installmentIndex}`,
            amountMinor: feeSnapshot(amountMinor, commissionBps).artistNetMinor,
            currency: "usd",
            status: payoutStatus,
            scheduledFor: NOW + PAYOUT_DELAY_MS,
            attempt: 0,
            kind: "completion",
            stripeTransferId:
              payoutStatus === "paid" ? `tr_${installmentIndex}` : undefined,
            createdAt: NOW,
            updatedAt: NOW,
          }),
        );
      }
      return { bookingId, bandId, organizationId, paymentRecordIds, payoutIds };
    });
    return {
      t,
      ...ids,
      settle: (refundMinor: number) =>
        t.run(async (ctx) =>
          settleDisputeRefund(ctx, {
            booking: (await ctx.db.get(ids.bookingId))!,
            refundMinor,
            now: NOW,
          }),
        ),
      refunds: () =>
        t.run((ctx) =>
          ctx.db
            .query("refunds")
            .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
            .take(50),
        ),
      payouts: () =>
        t.run((ctx) =>
          ctx.db
            .query("payouts")
            .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
            .take(50),
        ),
      ledger: () =>
        t.run((ctx) =>
          ctx.db
            .query("ledgerEntries")
            .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
            .take(50),
        ),
      scheduled: () =>
        t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
    };
  }

  test("records commission for two partial settlements on the same booking", async () => {
    const f = await setupSettlement();
    const first = await f.settle(4000);
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId: first.refundIds[0],
      stripeRefundId: "re_first_partial",
    });
    const second = await f.settle(1000);
    expect(second.reversedPayoutIds).toEqual(first.forfeitPayoutIds);
    expect(
      (await f.ledger()).filter((row) => row.kind === "commission"),
    ).toMatchObject([
      {
        idempotencyKey: `forfeit-commission:${first.refundIds[0]}`,
        amountMinor: 600,
      },
      {
        idempotencyKey: `forfeit-commission:${second.refundIds[0]}`,
        amountMinor: 500,
      },
    ]);
    expect(await f.payouts()).toMatchObject([
      { _id: f.payoutIds[0], status: "reversed" },
      { _id: first.forfeitPayoutIds[0], amountMinor: 5400, status: "reversed" },
      {
        _id: second.forfeitPayoutIds[0],
        amountMinor: 4500,
        status: "scheduled",
      },
    ]);
  });

  test("uses the stored commission rate when the original fee rounded up", async () => {
    const f = await setupSettlement([3], "scheduled", 2000);
    await f.settle(1);
    expect(
      (await f.payouts()).filter((row) => row.kind === "forfeit"),
    ).toMatchObject([{ amountMinor: 2 }]);
    expect(await f.ledger()).toEqual([]);
  });

  test("keys commission by the retained record when there is no refund or artist payout", async () => {
    const f = await setupSettlement([100], "scheduled", 10000);
    const result = await f.t.run(async (ctx) =>
      applySettlement(ctx, {
        booking: (await ctx.db.get(f.bookingId))!,
        refundMinor: 0,
        reason: "organizer_cancel",
        releaseUnpaidInstallmentHold: true,
        now: NOW,
      }),
    );
    expect(result).toEqual({
      refundIds: [],
      forfeitPayoutIds: [],
      reversedPayoutIds: f.payoutIds,
    });
    expect(await f.ledger()).toMatchObject([
      {
        idempotencyKey: `forfeit-commission:${f.paymentRecordIds[0]}`,
        amountMinor: 100,
      },
    ]);
  });

  test.each([0, -1, 10001, 0.5, NaN, Infinity])(
    "rejects an invalid dispute refund of %s without changes",
    async (refundMinor) => {
      const f = await setupSettlement();
      const payouts = await f.payouts();
      await expect(f.settle(refundMinor)).rejects.toThrow(
        "Dispute refund must be a positive integer within the paid amount",
      );
      expect(await f.refunds()).toEqual([]);
      expect(await f.payouts()).toEqual(payouts);
      expect(await f.ledger()).toEqual([]);
      expect(await f.scheduled()).toEqual([]);
    },
  );

  test("rejects a dispute refund that includes an unpaid installment", async () => {
    const f = await setupSettlement([4000, 6000]);
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[1], {
        status: "pending",
        paidAt: undefined,
        stripeChargeId: undefined,
        stripePaymentIntentId: undefined,
      });
      await ctx.db.delete(f.payoutIds[1]);
      await ctx.db.patch(f.bookingId, { paidMinor: 4000 });
    });
    const payouts = await f.payouts();
    await expect(f.settle(5000)).rejects.toThrow(
      "Dispute refund must be a positive integer within the paid amount",
    );
    expect(await f.refunds()).toEqual([]);
    expect(await f.payouts()).toEqual(payouts);
    expect(await f.ledger()).toEqual([]);
    expect(await f.scheduled()).toEqual([]);
  });

  test("allows a dispute refund equal to the booking's paid amount", async () => {
    const f = await setupSettlement();
    const result = await f.settle(10000);
    expect(result.forfeitPayoutIds).toEqual([]);
    expect(result.reversedPayoutIds).toEqual(f.payoutIds);
    expect(await f.refunds()).toMatchObject([
      { amountMinor: 10000, reason: "dispute" },
    ]);
    expect(await f.ledger()).toEqual([]);
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
      return { id: "re_post_succeeded", status: "succeeded" };
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

  test("re-drives failed refunds after six hours", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({ status: "failed" });
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
    ).toEqual([0, 1, 2].map(() => `refund:${refund._id}`));
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

  test("a balance paid after completion adds only its share of the payout", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[1], {
        status: "pending",
        paidAt: undefined,
      });
      await ctx.db.patch(f.bookingId, {
        paidMinor: 12000,
        payoutHold: true,
        payoutHoldReasons: ["unpaid_installment"],
      });
    });
    vi.setSystemTime(STARTS_AT + 6 * 60 * 60 * 1000);
    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: f.bookingId,
    });
    const context = await f
      .as("owner")
      .query(internal.payments.loadCheckoutContext, {
        paymentRecordId: f.paymentRecordIds[1],
      });
    expect(context.record.status).toBe("pending");
    expect(await f.payouts()).toMatchObject([{ amountMinor: 10800 }]);
    const permissions = await f
      .as("owner")
      .query(api.payments.paymentsForBooking, { bookingId: f.bookingId });
    expect(permissions[1].canPay).toBe(true);
    await f.t.mutation(internal.payments.markCheckoutOpen, {
      paymentRecordId: f.paymentRecordIds[1],
      sessionId: "cs_balance",
      attempt: 0,
      checkoutExpiresAt: Date.now() + CHECKOUT_TTL_MS,
    });
    const event: StripeEvent = {
      id: "evt_balance",
      type: "checkout.session.completed",
      livemode: false,
      created: Date.now() / 1000,
      data: {
        object: {
          id: "cs_balance",
          payment_status: "paid",
          amount_total: 8000,
          payment_intent: { id: "pi_b", latest_charge: "ch_b" },
          metadata: { paymentRecordId: f.paymentRecordIds[1] },
        },
      },
    };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const payouts = await f.payouts();
    expect(payouts.map((p) => p.amountMinor)).toEqual([10800, 7200]);
    expect(await f.readBooking()).toMatchObject({
      status: "completed",
      paidMinor: 20000,
      payoutHold: false,
    });
    expect(await f.deliver({ ...event, id: "evt_balance_replay" })).toEqual({
      outcome: "applied",
    });
    expect(await f.payouts()).toEqual(payouts);
    for (const payout of payouts) {
      vi.setSystemTime(payout.scheduledFor);
      await f.t.mutation(internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
      stripeMock.mockResolvedValueOnce({ id: `tr_${payout._id}` });
      await f.t.action(internal.payouts.executePayout, {
        payoutId: payout._id,
        attempt: 0,
      });
    }
    expect(await f.readBooking()).toMatchObject({ status: "paid" });
  });

  test("back-to-back refunds do not schedule overlapping transfer reversals", async () => {
    const f = await setupRefunds();
    await f.addPayout({ status: "paid", stripeTransferId: "tr_paid" });
    for (let i = 0; i < 2; i++) {
      const refundId = await f.addRefund({ amountMinor: 1000 });
      await f.t.mutation(internal.refunds.markRefundSucceeded, {
        refundId,
        stripeRefundId: `re_${i}`,
      });
    }
    const reversals = (await f.scheduled()).filter(
      (j) => j.name === "refunds:reverseTransfer",
    );
    expect(reversals.reduce((sum, j) => sum + j.args[0].reversalMinor, 0)).toBe(
      1800,
    );
    stripeMock.mockImplementation(async (_method, _path, _params, options) => ({
      id: `trr_${options?.idempotencyKey?.split(":").at(-1)}`,
    }));
    for (const job of reversals.toReversed()) {
      await f.t.action(internal.refunds.reverseTransfer, job.args[0]);
    }
    expect((await f.payouts())[0]).toMatchObject({
      reversedMinor: 1800,
      reversalReservedMinor: 1800,
    });
    await f.t.action(internal.refunds.reverseTransfer, reversals[0].args[0]);
    expect((await f.payouts())[0].reversedMinor).toBe(1800);
    expect(
      (await f.ledger()).filter((row) => row.kind === "transfer_reversal"),
    ).toHaveLength(2);
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
      await f.t.run((ctx) => ctx.db.patch(f.paymentRecordIds[0], { status }));
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
          payment_status: "paid",
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
        .withIndex("by_bookingId", (q) => q.eq("bookingId", offer.bookingId))
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
    expect(await f.t.run((ctx) => ctx.db.get(offer.bookingId))).toMatchObject({
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
    expect(await f.t.run((ctx) => ctx.db.query("refunds").take(50))).toEqual(
      rows,
    );
  });
});

describe("charge refund reconciliation", () => {
  test.each([
    "refund.created",
    "refund.updated",
    "charge.refund.updated",
  ] as const)(
    "%s reconciles a dashboard refund without expanded charge refunds exactly once",
    async (type) => {
      const f = await setupRefunds();
      const payoutId = await f.addPayout({
        status: "paid",
        stripeTransferId: "tr_paid",
      });
      const chargeEvent = chargeRefundedEvent();
      delete chargeEvent.data.object.refunds;
      chargeEvent.data.object.amount_refunded = 2000;
      expect(await f.deliver(chargeEvent)).toEqual({ outcome: "applied" });
      const event = refundEvent(type);
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });

      expect(await f.refunds()).toMatchObject([
        {
          paymentRecordId: f.paymentRecordIds[0],
          amountMinor: 2000,
          stripeRefundId: "re_dashboard",
          stripePaymentIntentId: "pi_a",
          reason: "admin",
          status: "succeeded",
        },
      ]);
      expect((await f.records())[0]).toMatchObject({
        status: "partially_refunded",
        refundedMinor: 2000,
      });
      expect(await f.readBooking()).toMatchObject({ refundedMinor: 2000 });
      const ledger = await f.ledger();
      expect(ledger).toMatchObject([
        { idempotencyKey: "refund:re_dashboard", amountMinor: -2000 },
      ]);
      const jobs = await f.scheduled();
      expect(jobs).toMatchObject([
        {
          name: "refunds:reverseTransfer",
          args: [{ payoutId, reversalMinor: 1800 }],
        },
      ]);
      await f.deliver({ ...event, id: "evt_dashboard_duplicate" });
      await f.deliver({
        ...chargeRefundedEvent(),
        id: "evt_expanded_duplicate",
      });
      expect(await f.refunds()).toHaveLength(1);
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.scheduled()).toEqual(jobs);
    },
  );

  test("a dashboard refund cancels its unpaid payout without affecting other installments", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const otherPayoutId = await f.addPayout({
      paymentRecordId: f.paymentRecordIds[1],
      amountMinor: 7200,
    });
    await f.deliver(refundEvent("refund.created", { amount: 12000 }));
    expect(await f.payouts()).toMatchObject([
      { _id: payoutId, status: "reversed" },
      { _id: otherPayoutId, status: "scheduled", amountMinor: 7200 },
    ]);
    expect((await f.readBooking())!.refundedMinor).toBe(12000);
  });

  test("a pending dashboard refund is tracked and polled without a second POST", async () => {
    const f = await setupRefunds();
    await f.deliver(refundEvent("refund.created", { status: "pending" }));
    expect(await f.refunds()).toMatchObject([
      { stripeRefundId: "re_dashboard", status: "pending" },
    ]);
    expect(await f.ledger()).toEqual([]);
    await f.t.mutation(internal.refunds.reconcilePendingRefunds, {});
    const [job] = await f.scheduled();
    await f.t.action(internal.refunds.executeRefund, job.args[0]);
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "GET",
      "/v1/refunds/re_dashboard",
    );
    expect((await f.readBooking())!.refundedMinor).toBe(2000);
    // An older creation event must not undo a terminal processor result.
    await f.deliver({
      ...refundEvent("refund.created", { status: "pending" }),
      id: "evt_pending_late",
    });
    expect(await f.refunds()).toMatchObject([{ status: "succeeded" }]);
  });

  test.each(["pi_a", "pi_extra"])(
    "an individual refund event reuses the pending request for %s before its Stripe id is saved",
    async (paymentIntentId) => {
      const f = await setupRefunds();
      const refundId = await f.addRefund({
        stripePaymentIntentId: paymentIntentId,
      });
      await f.deliver(
        refundEvent("refund.created", {
          payment_intent: { id: paymentIntentId },
          metadata: { refundId },
        }),
      );
      expect(await f.refunds()).toMatchObject([
        { _id: refundId, stripeRefundId: "re_dashboard", status: "succeeded" },
      ]);
      expect((await f.readBooking())!.refundedMinor).toBe(
        paymentIntentId === "pi_a" ? 2000 : 0,
      );
      expect(await f.ledger()).toHaveLength(1);
    },
  );

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

  test("a full dashboard refund reverses only payouts funded by that payment", async () => {
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
      { _id: heldId, status: "held", updatedAt: NOW },
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

  test("Stripe pending refunds remain pending locally", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund();
    stripeMock.mockResolvedValueOnce({ id: "re_pending", status: "pending" });
    await f.t.action(internal.refunds.executeRefund, { refundId, attempt: 0 });
    expect((await f.refunds())[0].status).toBe("pending");
  });
});

describe("Stripe disputes", () => {
  test.each([false, true])(
    "a Stripe win schedules missing completion payouts when a first payout exists: %s",
    async (hasFirstPayout) => {
      const f = await setupRefunds();
      await f.t.run((ctx) =>
        ctx.db.patch(f.bookingId, {
          status: "completed",
          completedAt: NOW - DAY_MS,
        }),
      );
      if (hasFirstPayout) await f.addPayout();
      await f.deliver(disputeEvent("charge.dispute.created"));
      const won = disputeEvent("charge.dispute.closed", { status: "won" });
      expect(await f.deliver(won)).toEqual({ outcome: "applied" });
      const payouts = await f.payouts();
      expect(payouts).toMatchObject([
        {
          kind: "completion",
          paymentRecordId: f.paymentRecordIds[0],
          amountMinor: 10800,
          status: "scheduled",
        },
        {
          kind: "completion",
          paymentRecordId: f.paymentRecordIds[1],
          amountMinor: 7200,
          status: "scheduled",
        },
      ]);
      expect(await f.readBooking()).toMatchObject({
        status: "completed",
        payoutHold: false,
        payoutHoldReasons: [],
      });
      const jobs = await f.scheduled();
      expect(jobs).toHaveLength(2);
      await f.deliver({ ...won, id: "evt_won_again" });
      expect(await f.payouts()).toEqual(payouts);
      expect(await f.scheduled()).toEqual(jobs);
    },
  );

  test("creation records the open Stripe dispute status", async () => {
    const f = await setupRefunds();
    expect(await f.deliver(disputeEvent("charge.dispute.created"))).toEqual({
      outcome: "applied",
    });
    expect((await f.records())[0]).toMatchObject({
      stripeDisputeId: "dp_test",
      stripeDisputeStatus: "open",
      disputedMinor: 12000,
      updatedAt: NOW,
    });
  });

  test.each(["open", "under_review"] as const)(
    "a won Stripe dispute preserves the booking and payout holds while an in-app dispute is %s",
    async (status) => {
      const f = await setupRefunds();
      const payoutIds = [await f.addPayout(), await f.addPayout()];
      const inAppDisputeId = await f.t.run((ctx) =>
        ctx.db.insert("disputes", {
          bookingId: f.bookingId,
          openedByUserId: f.users.owner,
          side: "organizer",
          category: "no_show",
          text: "The artist did not arrive",
          requestedRefundMinor: 12000,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      await f.deliver(disputeEvent("charge.dispute.created"));
      const heldBooking = await f.readBooking();
      const heldPayouts = await f.payouts();
      const inAppDispute = await f.t.run((ctx) => ctx.db.get(inAppDisputeId));
      expect(heldBooking).toMatchObject({ status: "disputed" });
      expect(heldPayouts).toMatchObject(
        payoutIds.map((_id) => ({ _id, status: "held", holdReason: "dispute" })),
      );

      vi.setSystemTime(NOW + 1000);
      expect(
        await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" })),
      ).toEqual({ outcome: "applied" });
      expect(await f.readBooking()).toEqual(heldBooking);
      expect(await f.payouts()).toEqual(heldPayouts);
      expect(await f.t.run((ctx) => ctx.db.get(inAppDisputeId))).toEqual(inAppDispute);
      expect((await f.records())[0]).toMatchObject({
        status: "paid",
        stripeDisputeStatus: "won",
        updatedAt: NOW + 1000,
      });
      expect((await f.ledger()).filter((row) => row.kind === "dispute_release"))
        .toMatchObject([
          {
            idempotencyKey: "dispute-release:dp_test",
            amountMinor: 12000,
            fundsState: "available",
            stripeRef: "dp_test",
            occurredAt: NOW + 1000,
          },
        ]);
      expect(await f.scheduled()).toEqual([]);
    },
  );

  test("a resolved in-app dispute does not prevent a Stripe win from releasing holds", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const inAppDisputeId = await f.t.run((ctx) =>
      ctx.db.insert("disputes", {
        bookingId: f.bookingId,
        openedByUserId: f.users.owner,
        side: "organizer",
        category: "no_show",
        text: "The artist did not arrive",
        status: "resolved",
        resolution: "dismissed",
        createdAt: NOW,
        updatedAt: NOW,
        resolvedAt: NOW,
      }),
    );
    const inAppDispute = await f.t.run((ctx) => ctx.db.get(inAppDisputeId));
    await f.deliver(disputeEvent("charge.dispute.created"));
    expect(
      await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" })),
    ).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toMatchObject({
      status: "confirmed",
      payoutHold: false,
      payoutHoldReasons: [],
    });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "scheduled",
    });
    expect((await f.records())[0]?.stripeDisputeStatus).toBe("won");
    expect(await f.t.run((ctx) => ctx.db.get(inAppDisputeId))).toEqual(inAppDispute);
    expect(await f.scheduled()).toMatchObject([
      {
        name: "bookings:markCompleted",
        args: [{ bookingId: f.bookingId }],
        scheduledTime: STARTS_AT + 6 * 60 * 60 * 1000,
      },
      {
        name: "payouts:releasePayout",
        args: [{ payoutId }],
        scheduledTime: STARTS_AT + PAYOUT_DELAY_MS,
      },
    ]);
  });

  test.each(["open", "under_review"] as const)(
    "a lost Stripe dispute resolves a %s in-app dispute with the disputed amount",
    async (status) => {
      const f = await setupRefunds();
      const payoutId = await f.addPayout();
      const otherPayoutId = await f.addPayout({
        paymentRecordId: f.paymentRecordIds[1],
        amountMinor: 7200,
        sourceChargeId: "ch_b",
      });
      const otherRecord = (await f.records())[1];
      const inAppDisputeId = await f.t.run((ctx) =>
        ctx.db.insert("disputes", {
          bookingId: f.bookingId,
          openedByUserId: f.users.owner,
          side: "organizer",
          category: "no_show",
          text: "The artist did not arrive",
          requestedRefundMinor: 12000,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      await f.deliver(disputeEvent("charge.dispute.created", { amount: 7000 }));
      vi.setSystemTime(NOW + 1000);
      expect(
        await f.deliver(disputeEvent("charge.dispute.closed", {
          status: "lost",
          balance_transactions: [{ fee: 0 }],
        })),
      ).toEqual({ outcome: "applied" });
      expect(await f.t.run((ctx) => ctx.db.get(inAppDisputeId))).toMatchObject({
        status: "resolved",
        resolution: "refunded_partial",
        resolvedRefundMinor: 7000,
        adminNote: "Closed by a lost Stripe dispute",
        resolvedAt: NOW + 1000,
        updatedAt: NOW + 1000,
      });
      expect((await f.records())[0]).toMatchObject({
        status: "partially_refunded",
        stripeDisputeStatus: "lost",
        refundedMinor: 7000,
      });
      expect(await f.readBooking()).toMatchObject({
        status: "confirmed",
        refundedMinor: 7000,
        payoutHold: false,
        payoutHoldReasons: [],
      });
      expect((await f.readBooking())?.disputedFromStatus).toBeUndefined();
      expect((await f.records())[1]).toEqual(otherRecord);
      expect(await f.payouts()).toMatchObject([
        {
          _id: payoutId,
          status: "scheduled",
          amountMinor: 4500,
          originalAmountMinor: 10800,
          scheduledFor: STARTS_AT + PAYOUT_DELAY_MS,
        },
        {
          _id: otherPayoutId,
          status: "scheduled",
          amountMinor: 7200,
          scheduledFor: STARTS_AT + PAYOUT_DELAY_MS,
        },
      ]);
      expect((await f.ledger()).filter((row) => row.kind === "dispute_loss"))
        .toMatchObject([{ amountMinor: -7000 }]);
    },
  );

  test.each(["confirmed", "completed"] as const)(
    "losing 7000 of a 20000 installment restores %s and preserves the untouched payout",
    async (status) => {
      const f = await setupRefunds();
      await f.t.run(async (ctx) => {
        await ctx.db.patch(f.bookingId, {
          status,
          ...(status === "completed" ? { completedAt: NOW } : {}),
          grossMinor: 28000,
          commissionMinor: 2800,
          artistNetMinor: 25200,
          paidMinor: 28000,
        });
        await ctx.db.patch(f.paymentRecordIds[0], { amountMinor: 20000 });
      });
      const payoutId = await f.addPayout({ amountMinor: 18000 });
      const otherPayoutId = await f.addPayout({
        paymentRecordId: f.paymentRecordIds[1],
        amountMinor: 7200,
        sourceChargeId: "ch_b",
      });
      const otherRecord = (await f.records())[1];
      await f.deliver(disputeEvent("charge.dispute.created", { amount: 7000 }));
      expect(await f.readBooking()).toMatchObject({
        status: "disputed",
        disputedFromStatus: status,
        payoutHoldReasons: ["dispute"],
      });
      expect(await f.payouts()).toMatchObject([
        { _id: payoutId, status: "held", holdReason: "dispute" },
        { _id: otherPayoutId, status: "held", holdReason: "dispute" },
      ]);

      const closed = disputeEvent("charge.dispute.closed", {
        status: "lost",
        balance_transactions: [{ fee: 0 }],
      });
      expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
      const booking = await f.readBooking();
      expect(booking).toMatchObject({
        status,
        refundedMinor: 7000,
        revision: 5,
        payoutHold: false,
        payoutHoldReasons: [],
      });
      expect(booking?.disputedFromStatus).toBeUndefined();
      expect((await f.records())[0]).toMatchObject({
        amountMinor: 20000,
        refundedMinor: 7000,
        status: "partially_refunded",
        stripeDisputeStatus: "lost",
      });
      expect((await f.records())[1]).toEqual(otherRecord);
      const payouts = await f.payouts();
      expect(payouts).toMatchObject([
        {
          _id: payoutId,
          status: "scheduled",
          amountMinor: 11700,
          originalAmountMinor: 18000,
          scheduledFor: STARTS_AT + PAYOUT_DELAY_MS,
        },
        {
          _id: otherPayoutId,
          status: "scheduled",
          amountMinor: 7200,
          scheduledFor: STARTS_AT + PAYOUT_DELAY_MS,
        },
      ]);
      const jobs = await f.scheduled();
      expect(jobs.filter((job) => job.name === "payouts:releasePayout"))
        .toMatchObject([
          {
            args: [{ payoutId }],
            scheduledTime: STARTS_AT + PAYOUT_DELAY_MS,
          },
          {
            args: [{ payoutId: otherPayoutId }],
            scheduledTime: STARTS_AT + PAYOUT_DELAY_MS,
          },
        ]);
      await f.deliver({ ...closed, id: "evt_partial_loss_again" });
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.payouts()).toEqual(payouts);
      expect(await f.scheduled()).toEqual(jobs);

      vi.setSystemTime(STARTS_AT + PAYOUT_DELAY_MS);
      for (const payout of payouts) {
        await f.t.mutation(internal.payouts.releasePayout, {
          payoutId: payout._id,
        });
        expect(await f.t.run((ctx) => ctx.db.get(payout._id))).toMatchObject({
          status: "processing",
          amountMinor: payout.amountMinor,
        });
      }
    },
  );

  test("a loss with no retained booking balance marks the booking refunded", async () => {
    const f = await setupRefunds();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[1], {
        status: "refunded",
        refundedMinor: 8000,
      });
      await ctx.db.patch(f.bookingId, { refundedMinor: 8000 });
    });
    const payoutId = await f.addPayout();
    const otherPayoutId = await f.addPayout({
      paymentRecordId: f.paymentRecordIds[1],
      amountMinor: 7200,
      sourceChargeId: "ch_b",
      status: "reversed",
    });
    const otherPayout = await f.t.run((ctx) => ctx.db.get(otherPayoutId));
    await f.deliver(disputeEvent("charge.dispute.created"));
    expect(await f.deliver(disputeEvent("charge.dispute.closed", {
      status: "lost",
      balance_transactions: [{ fee: 0 }],
    }))).toEqual({ outcome: "applied" });
    const booking = await f.readBooking();
    expect(booking).toMatchObject({
      status: "refunded",
      refundedMinor: 20000,
      payoutHold: false,
      payoutHoldReasons: [],
      revision: 5,
    });
    expect(booking?.disputedFromStatus).toBeUndefined();
    expect((await f.records())[0]).toMatchObject({
      status: "refunded",
      refundedMinor: 12000,
      stripeDisputeStatus: "lost",
    });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "reversed",
    });
    expect(await f.t.run((ctx) => ctx.db.get(otherPayoutId))).toEqual(otherPayout);
    expect(await f.scheduled()).toEqual([]);
  });

  test("a loss adds only the remaining refundable amount to an already partially refunded booking", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const otherPayoutId = await f.addPayout({
      paymentRecordId: f.paymentRecordIds[1],
      amountMinor: 7200,
      sourceChargeId: "ch_b",
    });
    const refundId = await f.addRefund({ amountMinor: 6000 });
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_before_dispute",
    });
    expect((await f.records())[0]).toMatchObject({
      status: "partially_refunded",
      refundedMinor: 6000,
    });
    expect(await f.readBooking()).toMatchObject({ refundedMinor: 6000 });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      amountMinor: 5400,
      originalAmountMinor: 10800,
    });
    await f.deliver(disputeEvent("charge.dispute.created", { amount: 9000 }));
    const closed = disputeEvent("charge.dispute.closed", {
      status: "lost",
      balance_transactions: [{ fee: 0 }],
    });
    expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
    const booking = await f.readBooking();
    expect(booking).toMatchObject({
      status: "confirmed",
      refundedMinor: 12000,
      payoutHold: false,
      payoutHoldReasons: [],
    });
    expect(booking?.disputedFromStatus).toBeUndefined();
    expect((await f.records())[0]).toMatchObject({
      status: "refunded",
      refundedMinor: 12000,
      stripeDisputeStatus: "lost",
    });
    expect(await f.payouts()).toMatchObject([
      { _id: payoutId, status: "reversed" },
      { _id: otherPayoutId, status: "scheduled", amountMinor: 7200 },
    ]);
    expect((await f.ledger()).filter((row) => row.kind === "dispute_loss"))
      .toMatchObject([{ amountMinor: -9000 }]);
    const ledger = await f.ledger();
    await f.deliver({ ...closed, id: "evt_capped_loss_again" });
    expect(await f.readBooking()).toEqual(booking);
    expect(await f.ledger()).toEqual(ledger);
  });

  test("a partial loss preserves the prior status and payout holds until another Stripe dispute closes", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const otherPayoutId = await f.addPayout({
      paymentRecordId: f.paymentRecordIds[1],
      amountMinor: 7200,
      sourceChargeId: "ch_b",
    });
    await f.deliver(disputeEvent("charge.dispute.created", { amount: 7000 }));
    const second = disputeEvent("charge.dispute.created", {
      id: "dp_second",
      payment_intent: "pi_b",
      amount: 2000,
    });
    await f.deliver({ ...second, id: "evt_second_created" });
    expect(await f.deliver(disputeEvent("charge.dispute.closed", {
      status: "lost",
      balance_transactions: [{ fee: 0 }],
    }))).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toMatchObject({
      status: "disputed",
      disputedFromStatus: "confirmed",
      refundedMinor: 7000,
      payoutHold: true,
      payoutHoldReasons: ["dispute"],
    });
    expect(await f.payouts()).toMatchObject([
      {
        _id: payoutId,
        amountMinor: 4500,
        originalAmountMinor: 10800,
        status: "held",
        holdReason: "dispute",
      },
      {
        _id: otherPayoutId,
        amountMinor: 7200,
        status: "held",
        holdReason: "dispute",
      },
    ]);
    expect(await f.scheduled()).toEqual([]);

    expect(await f.deliver({
      ...disputeEvent("charge.dispute.closed", {
        ...second.data.object,
        status: "won",
      }),
      id: "evt_second_closed",
    })).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toMatchObject({
      status: "confirmed",
      refundedMinor: 7000,
      payoutHold: false,
      payoutHoldReasons: [],
    });
    expect((await f.readBooking())?.disputedFromStatus).toBeUndefined();
    expect(await f.payouts()).toMatchObject([
      { _id: payoutId, amountMinor: 4500, status: "scheduled" },
      { _id: otherPayoutId, amountMinor: 7200, status: "scheduled" },
    ]);
  });

  test("a lost Stripe dispute records its outcome when the payment was already refunded", async () => {
    const f = await setupRefunds();
    await f.deliver(disputeEvent("charge.dispute.created"));
    await f.t.run((ctx) => ctx.db.patch(f.paymentRecordIds[0], {
      status: "refunded",
      refundedMinor: 12000,
    }));
    expect(
      await f.deliver(disputeEvent("charge.dispute.closed", {
        status: "lost",
        balance_transactions: [{ fee: 0 }],
      })),
    ).toEqual({ outcome: "applied" });
    expect((await f.records())[0]).toMatchObject({
      status: "refunded",
      stripeDisputeStatus: "lost",
      refundedMinor: 12000,
    });
  });

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
      expect(await f.deliver(disputeEvent("charge.dispute.created"))).toEqual({
        outcome: "applied",
      });
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
          name: "bookings:markCompleted",
          args: [{ bookingId: f.bookingId }],
          scheduledTime: STARTS_AT + 6 * 60 * 60 * 1000,
        },
        {
          name: "payouts:releasePayout",
          args: [{ payoutId }],
          scheduledTime: STARTS_AT + PAYOUT_DELAY_MS,
        },
      ]);
      const log = vi.spyOn(console, "log").mockImplementation(() => {});
      await f.t.mutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
      expect(log).not.toHaveBeenCalled();
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
      const otherPayoutId = await f.addPayout({
        status: "paid",
        paymentRecordId: f.paymentRecordIds[1],
        stripeTransferId: "tr_other",
      });
      const otherPayout = await f.t.run((ctx) => ctx.db.get(otherPayoutId));
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
        status: "confirmed",
        refundedMinor: 12000,
        payoutHold: false,
        payoutHoldReasons: [],
      });
      expect(booking?.disputedFromStatus).toBeUndefined();
      expect((await f.records())[0]).toMatchObject({
        status: "refunded",
        refundedMinor: 12000,
      });
      expect(await f.t.run((ctx) => ctx.db.get(otherPayoutId))).toEqual(otherPayout);
      expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
        status: "paid",
        reversalReservedMinor: 10800,
      });
      const ledger = await f.ledger();
      expect(ledger).toHaveLength(3);
      expect(ledger.filter((row) => row.kind === "dispute_loss")).toMatchObject(
        [
          {
            idempotencyKey: "dispute-loss:dp_test",
            amountMinor: -12000,
            fundsState: "refunded",
          },
        ],
      );
      expect(ledger.filter((row) => row.kind === "dispute_fee")).toMatchObject([
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
        {
          name: "bookings:markCompleted",
          args: [{ bookingId: f.bookingId }],
          scheduledTime: STARTS_AT + 6 * 60 * 60 * 1000,
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
        await f.deliver(disputeEvent(type, { payment_intent: "pi_unknown" })),
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
    expect(await f.deliver(disputeEvent("charge.dispute.created"))).toEqual({
      outcome: "applied",
    });
    expect(
      await f.deliver(
        disputeEvent("charge.dispute.closed", {
          status: "lost",
          balance_transactions: [{ fee: 0 }],
        }),
      ),
    ).toEqual({ outcome: "applied" });
    expect(await f.scheduled()).toMatchObject([
      {
        name: "bookings:markCompleted",
        args: [{ bookingId: f.bookingId }],
        scheduledTime: STARTS_AT + 6 * 60 * 60 * 1000,
      },
    ]);
  });

  test("holds and releases a forfeit payout on a cancelled booking without changing its status", async () => {
    const f = await setupRefunds();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, { status: "cancelled_by_organizer" }),
    );
    const booking = await f.readBooking();
    const payoutId = await f.addPayout({
      kind: "forfeit",
      status: "scheduled",
    });

    expect(await f.deliver(disputeEvent("charge.dispute.created"))).toEqual({
      outcome: "applied",
    });
    const heldBooking = await f.readBooking();
    expect(heldBooking).toEqual({
      ...booking,
      payoutHoldReasons: ["dispute"],
      payoutHold: true,
      updatedAt: NOW,
    });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "held",
      holdReason: "dispute",
    });

    await f.t.mutation(internal.payouts.retryHeldPayouts, {});
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "held",
      holdReason: "dispute",
    });
    expect(await f.readBooking()).toEqual(heldBooking);

    expect(
      await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" })),
    ).toEqual({ outcome: "applied" });
    const releasedBooking = await f.readBooking();
    expect(releasedBooking).toEqual({
      ...booking,
      payoutHoldReasons: [],
      payoutHold: false,
      updatedAt: NOW,
    });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "scheduled",
    });
    expect(
      (await f.ledger()).filter((row) => row.kind === "dispute_release"),
    ).toMatchObject([
      {
        idempotencyKey: "dispute-release:dp_test",
        amountMinor: 12000,
        fundsState: "available",
      },
    ]);
    const jobs = await f.scheduled();
    expect(
      jobs.filter(
        (job) =>
          job.name === "payouts:releasePayout" &&
          job.scheduledTime === NOW + DAY_MS,
      ),
    ).toMatchObject([{ args: [{ payoutId }] }, { args: [{ payoutId }] }]);

    await f.t.mutation(internal.payouts.releasePayout, { payoutId });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "processing",
    });
    expect(await f.readBooking()).toEqual(releasedBooking);
  });

  test("a won dispute on a cancelled booking preserves other holds and status metadata", async () => {
    const f = await setupRefunds();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        status: "cancelled_by_organizer",
        disputedFromStatus: "confirmed",
        payoutHoldReasons: ["admin"],
        payoutHold: true,
      }),
    );
    const booking = await f.readBooking();
    const payoutId = await f.addPayout({ kind: "forfeit" });
    expect(await f.deliver(disputeEvent("charge.dispute.created"))).toEqual({
      outcome: "applied",
    });
    expect(await f.readBooking()).toEqual({
      ...booking,
      payoutHoldReasons: ["admin", "dispute"],
    });
    expect(
      await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" })),
    ).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toEqual(booking);
    await f.t.mutation(internal.payouts.releasePayout, { payoutId });
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      status: "held",
      holdReason: "admin",
    });
  });

  test.each(
    (
      ["confirmed", "completed", "paid", "cancelled_by_organizer"] as const
    ).flatMap((status) =>
      (["won", "lost"] as const).map((outcome) => ({ status, outcome })),
    ),
  )(
    "settles a $outcome dispute delivered before creation on a $status booking",
    async ({ status, outcome }) => {
      const f = await setupRefunds();
      await f.t.run((ctx) =>
        ctx.db.patch(f.bookingId, {
          status,
          payoutHoldReasons: ["admin"],
          payoutHold: true,
        }),
      );
      await f.addPayout({
        kind: status === "cancelled_by_organizer" ? "forfeit" : "completion",
        status: status === "paid" ? "paid" : "scheduled",
        ...(status === "paid" ? { stripeTransferId: "tr_paid" } : {}),
      });
      const closed = disputeEvent("charge.dispute.closed", {
        status: outcome,
        amount: 3000,
        balance_transactions: [{ fee: 0 }],
      });
      expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
      expect((await f.records())[0]).toMatchObject({
        stripeDisputeId: "dp_test",
        stripeDisputeStatus: outcome,
        disputedMinor: 3000,
        refundedMinor: outcome === "lost" ? 3000 : 0,
      });
      expect(await f.readBooking()).toMatchObject({
        status,
        payoutHoldReasons: ["admin"],
        payoutHold: true,
        refundedMinor: outcome === "lost" ? 3000 : 0,
      });
      expect((await f.readBooking())?.disputedFromStatus).toBeUndefined();
      expect((await f.payouts())[0]).toMatchObject({
        status: status === "paid" ? "paid" : "scheduled",
        amountMinor: outcome === "lost" && status !== "paid" ? 8100 : 10800,
        ...(outcome === "lost" && status === "paid"
          ? { reversalReservedMinor: 2700 }
          : {}),
      });
      const ledger = await f.ledger();
      expect(ledger).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            idempotencyKey: "dispute-hold:dp_test",
            amountMinor: -3000,
          }),
          expect.objectContaining({
            idempotencyKey: `dispute-${outcome === "won" ? "release" : "loss"}:dp_test`,
            amountMinor: outcome === "won" ? 3000 : -3000,
          }),
        ]),
      );
      const booking = await f.readBooking();
      const records = await f.records();
      const payouts = await f.payouts();
      const jobs = await f.scheduled();
      expect(await f.deliver(closed)).toEqual({ outcome: "duplicate" });
      await f.deliver(disputeEvent("charge.dispute.created"));
      await f.deliver({ ...closed, id: "evt_closure_duplicate" });
      expect(await f.readBooking()).toEqual(booking);
      expect(await f.records()).toEqual(records);
      expect(await f.payouts()).toEqual(payouts);
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.scheduled()).toEqual(jobs);
    },
  );

  test("a closure remains retryable when a disputed booking is missing its prior status", async () => {
    const f = await setupRefunds();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        status: "disputed",
        payoutHoldReasons: ["dispute"],
        payoutHold: true,
      }),
    );
    const booking = await f.readBooking();
    const records = await f.records();
    const closed = disputeEvent("charge.dispute.closed", { status: "won" });
    expect(await f.deliver(closed)).toEqual({ outcome: "failed" });
    expect(await f.readBooking()).toEqual(booking);
    expect(await f.records()).toEqual(records);
    expect(await f.ledger()).toEqual([]);
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, { disputedFromStatus: "confirmed" }),
    );
    expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
    expect(await f.readBooking()).toMatchObject({
      status: "confirmed",
      payoutHold: false,
    });
    expect((await f.records())[0].stripeDisputeStatus).toBe("won");
  });

  test("winning a dispute resumes a completion job that fired while disputed", async () => {
    const f = await setupRefunds();
    await f.deliver(disputeEvent("charge.dispute.created"));
    vi.setSystemTime(STARTS_AT + 6 * 60 * 60 * 1000);
    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: f.bookingId,
    });
    await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" }));
    const b = await f.readBooking();
    const completionScheduled = (await f.scheduled()).some(
      (j) => j.name === "bookings:markCompleted",
    );
    expect(b!.status === "completed" || completionScheduled).toBe(true);
  });

  test("winning one of two disputes preserves the remaining hold", async () => {
    const f = await setupRefunds();
    await f.addPayout();
    const first = disputeEvent("charge.dispute.created");
    await f.deliver(first);
    await f.deliver({
      ...first,
      id: "evt_second",
      data: {
        object: { id: "dp_second", payment_intent: "pi_b", amount: 8000 },
      },
    });
    await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" }));
    expect((await f.readBooking())!.payoutHoldReasons).toContain("dispute");
  });
});

describe("refund status and payout reconciliation", () => {
  test.each(["succeeded", "failed", "canceled"])(
    "a pending Stripe refund settles as %s without another refund request",
    async (status) => {
      const f = await setupRefunds();
      const refundId = await f.addRefund();
      stripeMock.mockResolvedValueOnce({ id: "re_pending", status: "pending" });
      await f.t.action(internal.refunds.executeRefund, {
        refundId,
        attempt: 0,
      });
      expect(await f.refunds()).toMatchObject([
        { status: "pending", stripeRefundId: "re_pending" },
      ]);
      expect(await f.ledger()).toEqual([]);
      expect(await f.readBooking()).toMatchObject({ refundedMinor: 0 });
      const event: StripeEvent = {
        id: "evt_refund_update",
        type: status === "failed" ? "refund.failed" : "refund.updated",
        livemode: false,
        created: NOW / 1000,
        data: {
          object: {
            id: "re_pending",
            status,
            amount: 2000,
            payment_intent: "pi_a",
          },
        },
      };
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      expect((await f.refunds())[0].status).toBe(
        status === "succeeded" ? "succeeded" : "failed",
      );
      expect((await f.readBooking())!.refundedMinor).toBe(
        status === "succeeded" ? 2000 : 0,
      );
      const ledger = await f.ledger();
      await f.deliver({ ...event, id: "evt_refund_update_again" });
      await f.t.mutation(internal.refunds.retryFailedRefunds, {});
      expect(await f.ledger()).toEqual(ledger);
      expect(await f.scheduled()).toEqual([]);
      expect(stripeMock).toHaveBeenCalledTimes(1);
    },
  );

  test("a pending refund is polled by id when its webhook is missed", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund();
    stripeMock.mockResolvedValueOnce({ id: "re_pending", status: "pending" });
    await f.t.action(internal.refunds.executeRefund, { refundId, attempt: 0 });
    await f.t.mutation(internal.refunds.reconcilePendingRefunds, {});
    const [job] = await f.scheduled();
    expect(job.name).toBe("refunds:executeRefund");
    await f.t.action(internal.refunds.executeRefund, job.args[0]);
    expect(stripeMock).toHaveBeenLastCalledWith(
      "GET",
      "/v1/refunds/re_pending",
    );
    expect((await f.refunds())[0].status).toBe("succeeded");
    expect((await f.readBooking())!.refundedMinor).toBe(2000);
  });

  test("partial refunds reduce only the affected pending payout without compounding", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout();
    const otherId = await f.addPayout({
      paymentRecordId: f.paymentRecordIds[1],
      amountMinor: 7200,
    });
    for (let index = 0; index < 2; index++) {
      const refundId = await f.addRefund({ amountMinor: 1000 });
      await f.t.mutation(internal.refunds.markRefundSucceeded, {
        refundId,
        stripeRefundId: `re_${index}`,
      });
    }
    expect(await f.t.run((ctx) => ctx.db.get(payoutId))).toMatchObject({
      amountMinor: 9000,
      originalAmountMinor: 10800,
    });
    expect(await f.t.run((ctx) => ctx.db.get(otherId))).toMatchObject({
      amountMinor: 7200,
    });
  });

  test("a refund while a transfer is processing is reconciled when the transfer completes", async () => {
    const f = await setupRefunds();
    const payoutId = await f.addPayout({ status: "processing" });
    const refundId = await f.addRefund();
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_processing",
    });
    expect(await f.scheduled()).toEqual([]);
    await f.t.mutation(internal.payouts.markPayoutPaid, {
      payoutId,
      transferId: "tr_processing",
    });
    expect(await f.scheduled()).toMatchObject([
      {
        name: "refunds:reverseTransfer",
        args: [{ payoutId, reversalMinor: 1800, reversedMinor: 1800 }],
      },
    ]);
  });

  test.each(["won", "lost"] as const)(
    "the second installment dispute closes as %s after the first is won",
    async (outcome) => {
      const f = await setupRefunds();
      await f.addPayout();
      await f.deliver(disputeEvent("charge.dispute.created"));
      const second = disputeEvent("charge.dispute.created", {
        id: "dp_b",
        payment_intent: "pi_b",
        amount: 8000,
      });
      second.id = "evt_second_dispute";
      await f.deliver(second);
      await f.deliver(disputeEvent("charge.dispute.closed", { status: "won" }));
      expect(await f.readBooking()).toMatchObject({
        status: "disputed",
        payoutHoldReasons: ["dispute"],
      });
      expect(await f.scheduled()).toEqual([]);
      expect(
        await f.deliver({
          ...second,
          id: "evt_second_closed",
          type: "charge.dispute.closed",
          data: {
            object: {
              ...second.data.object,
              status: outcome,
              balance_transactions: [{ fee: 0 }],
            },
          },
        }),
      ).toEqual({ outcome: "applied" });
      expect(await f.readBooking()).toMatchObject({
        status: "confirmed",
        payoutHoldReasons: [],
        payoutHold: false,
      });
      expect((await f.readBooking())?.disputedFromStatus).toBeUndefined();
      expect(await f.payouts()).toMatchObject([
        { status: "scheduled", amountMinor: 10800 },
      ]);
      expect((await f.records())[1].stripeDisputeStatus).toBe(outcome);
      expect(
        (await f.ledger()).some(
          (row) =>
            row.idempotencyKey ===
            `dispute-${outcome === "won" ? "release" : "loss"}:dp_b`,
        ),
      ).toBe(true);
      // A duplicate creation delivered after closure cannot reapply the hold.
      await f.deliver({ ...second, id: "evt_second_created_late" });
      expect((await f.readBooking())!.payoutHold).toBe(false);
    },
  );
});
