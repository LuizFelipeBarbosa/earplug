/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  applySettlement,
  settleDisputeRefund,
} from "./lib/cancellationSettlement";
import { feeSnapshot } from "./lib/fees";
import { PAYOUT_DELAY_MS } from "./lib/paymentStatus";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

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

describe("explicit settlement", () => {
  test.each(["scheduled", "held"] as const)(
    "refunds 4000 and replaces a %s completion payout with the remaining net",
    async (status) => {
      const f = await setupSettlement([10000], status);
      const result = await f.t.run(async (ctx) =>
        applySettlement(ctx, {
          booking: (await ctx.db.get(f.bookingId))!,
          refundMinor: 4000,
          reason: "dispute",
          now: NOW,
        }),
      );
      const refunds = await f.refunds();
      expect(refunds).toMatchObject([
        {
          amountMinor: 4000,
          paymentRecordId: f.paymentRecordIds[0],
          reason: "dispute",
          status: "pending",
        },
      ]);
      const payouts = await f.payouts();
      expect(payouts).toMatchObject([
        { _id: f.payoutIds[0], kind: "completion", status: "reversed" },
        {
          kind: "forfeit",
          amountMinor: 5400,
          paymentRecordId: f.paymentRecordIds[0],
          sourceChargeId: "ch_settlement_0",
          status: "scheduled",
          scheduledFor: NOW + PAYOUT_DELAY_MS,
        },
      ]);
      expect(result).toEqual({
        refundIds: [refunds[0]._id],
        forfeitPayoutIds: [payouts[1]._id],
        reversedPayoutIds: f.payoutIds,
      });
      expect(await f.ledger()).toMatchObject([
        {
          idempotencyKey: `forfeit-commission:${refunds[0]._id}`,
          kind: "commission",
          amountMinor: 600,
          currency: "usd",
          fundsState: "available",
          bookingId: f.bookingId,
          bandId: f.bandId,
          organizationId: f.organizationId,
        },
      ]);
      expect(await f.scheduled()).toMatchObject([
        {
          name: "refunds:executeRefund",
          args: [{ refundId: refunds[0]._id, attempt: 0 }],
          scheduledTime: NOW,
        },
        {
          name: "payouts:releasePayout",
          args: [{ payoutId: payouts[1]._id }],
          scheduledTime: NOW + PAYOUT_DELAY_MS,
        },
      ]);
      expect(await f.t.run((ctx) => ctx.db.get(f.bookingId))).toMatchObject({
        refundedMinor: 0,
      });
    },
  );

  test("leaves a paid completion transfer to the proportional refund reversal", async () => {
    const f = await setupSettlement([10000], "paid");
    const payouts = await f.payouts();
    const result = await f.settle(4000);
    expect(result).toEqual({
      refundIds: [expect.any(String)],
      forfeitPayoutIds: [],
      reversedPayoutIds: [],
    });
    expect(await f.refunds()).toMatchObject([
      {
        _id: result.refundIds[0],
        amountMinor: 4000,
        reason: "dispute",
        status: "pending",
      },
    ]);
    expect(await f.payouts()).toEqual(payouts);
    expect(await f.ledger()).toEqual([]);
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId: result.refundIds[0],
      stripeRefundId: "re_paid_completion",
    });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "refunds:reverseTransfer",
        args: [{ payoutId: f.payoutIds[0], reversalMinor: 3600 }],
      }),
    );
    expect(
      (await f.ledger()).filter((row) => row.kind === "commission"),
    ).toEqual([]);
  });

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

  test("allocates refunds newest-first and preserves proportional forfeit rounding", async () => {
    const f = await setupSettlement([3335, 3335, 3330]);
    const result = await f.settle(4000);
    expect(await f.refunds()).toMatchObject([
      { paymentRecordId: f.paymentRecordIds[2], amountMinor: 3330 },
      { paymentRecordId: f.paymentRecordIds[1], amountMinor: 670 },
    ]);
    expect(
      (await f.payouts()).filter((row) => row.kind === "forfeit"),
    ).toMatchObject([
      { paymentRecordId: f.paymentRecordIds[2], amountMinor: 1798 },
      { paymentRecordId: f.paymentRecordIds[1], amountMinor: 1801 },
      { paymentRecordId: f.paymentRecordIds[0], amountMinor: 1801 },
    ]);
    expect(await f.ledger()).toMatchObject([
      {
        idempotencyKey: `forfeit-commission:${result.refundIds[0]}`,
        amountMinor: 600,
      },
    ]);
  });

  test("zero refunds still reverse payouts and create forfeits and commission", async () => {
    const f = await setupSettlement();
    const result = await f.t.run(async (ctx) =>
      applySettlement(ctx, {
        booking: (await ctx.db.get(f.bookingId))!,
        refundMinor: 0,
        reason: "organizer_cancel",
        now: NOW,
      }),
    );
    expect(result.refundIds).toEqual([]);
    expect(result.reversedPayoutIds).toEqual(f.payoutIds);
    expect(await f.refunds()).toEqual([]);
    expect(await f.payouts()).toMatchObject([
      { _id: f.payoutIds[0], status: "reversed" },
      { _id: result.forfeitPayoutIds[0], kind: "forfeit", amountMinor: 9000 },
    ]);
    expect(await f.ledger()).toMatchObject([
      {
        idempotencyKey: `forfeit-commission:${result.forfeitPayoutIds[0]}`,
        amountMinor: 1000,
      },
    ]);
    expect((await f.scheduled()).map((job) => job.name)).toEqual([
      "payouts:releasePayout",
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
