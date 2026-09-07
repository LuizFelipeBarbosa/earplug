import type { Infer } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { refundReasonValidator } from "../schema";
import {
  refundShareBps,
  settleCancellation,
  type BookingCancelledBy,
  type CancellationTemplate,
} from "./cancellationPolicy";
import { splitFee } from "./fees";
import { appendLedgerEntry } from "./ledger";
import { paymentRecordsForBooking } from "./paymentSchedule";
import { assertPayoutTransition, PAYOUT_DELAY_MS } from "./paymentStatus";

type CancellationSettlement = {
  refundMinor: number;
  forfeitedMinor: number;
  artistPayoutMinor: number;
  platformKeepsMinor: number;
  paidMinor: number;
  shareBps: number;
};

type SettlementResult = {
  refundIds: Id<"refunds">[];
  forfeitPayoutIds: Id<"payouts">[];
  reversedPayoutIds: Id<"payouts">[];
};

async function availablePaidRecords(
  ctx: QueryCtx | MutationCtx,
  bookingId: Id<"bookings">,
): Promise<Doc<"paymentRecords">[]> {
  return (await paymentRecordsForBooking(ctx, bookingId)).filter(
    (record) =>
      (record.status === "paid" || record.status === "partially_refunded") &&
      record.amountMinor - record.refundedMinor > 0,
  );
}

export async function computeCancellationSettlement(
  ctx: QueryCtx | MutationCtx,
  args: {
    bookingId: Id<"bookings">;
    template: CancellationTemplate;
    startsAt: number;
    cancelledBy: BookingCancelledBy;
    artistNetMinor: number;
    commissionMinor: number;
    now: number;
  },
): Promise<CancellationSettlement> {
  const records = await availablePaidRecords(ctx, args.bookingId);
  const paidMinor = records.reduce(
    (sum, record) => sum + record.amountMinor - record.refundedMinor,
    0,
  );
  const msBeforeStart = args.startsAt - args.now;
  const shareBps = refundShareBps(args.template, msBeforeStart);
  const settlement = settleCancellation({
    template: args.template,
    msBeforeStart,
    cancelledBy: args.cancelledBy,
    paidMinor,
    artistNetMinor: args.artistNetMinor,
    commissionMinor: args.commissionMinor,
  });
  return { ...settlement, paidMinor, shareBps };
}

export async function settleBookingCancellation(
  ctx: MutationCtx,
  args: {
    booking: Doc<"bookings">;
    cancelledBy: BookingCancelledBy;
    reason: Infer<typeof refundReasonValidator>;
    now: number;
  },
): Promise<CancellationSettlement> {
  const { booking, now } = args;
  const settlement = await computeCancellationSettlement(ctx, {
    bookingId: booking._id,
    template: booking.cancellationTemplate,
    startsAt: booking.startsAt,
    cancelledBy: args.cancelledBy,
    artistNetMinor: booking.artistNetMinor,
    commissionMinor: booking.commissionMinor,
    now,
  });
  await applySettlement(ctx, {
    booking,
    refundMinor: settlement.refundMinor,
    reason: args.reason,
    now,
  });
  return settlement;
}

export async function settleDisputeRefund(
  ctx: MutationCtx,
  args: { booking: Doc<"bookings">; refundMinor: number; now: number },
): Promise<SettlementResult> {
  const records = await paymentRecordsForBooking(ctx, args.booking._id);
  const refundableMinor = records.reduce(
    (sum, record) => sum + record.amountMinor - record.refundedMinor,
    0,
  );
  if (
    !Number.isSafeInteger(args.refundMinor) ||
    args.refundMinor <= 0 ||
    args.refundMinor > refundableMinor
  ) {
    throw new Error(
      "Dispute refund must be a positive integer within the paid amount",
    );
  }
  return await applySettlement(ctx, { ...args, reason: "dispute" });
}

export async function applySettlement(
  ctx: MutationCtx,
  args: {
    booking: Doc<"bookings">;
    refundMinor: number;
    reason: Infer<typeof refundReasonValidator>;
    now: number;
  },
): Promise<SettlementResult> {
  const { booking, refundMinor, now } = args;
  // The caller may already have cleared a hold while changing booking status.
  const currentBooking = await ctx.db.get(booking._id);
  if (!currentBooking) throw new Error("Booking not found");
  // The cancelled balance is no longer collectible. Dispute/admin holds still apply.
  const payoutHoldReasons = (currentBooking.payoutHoldReasons ?? []).filter(
    (reason) => reason !== "unpaid_installment",
  );
  await ctx.db.patch(booking._id, {
    payoutHoldReasons,
    payoutHold: payoutHoldReasons.length > 0,
  });
  const existingPayouts = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
    .take(50);
  const reversedPayoutIds: Id<"payouts">[] = [];
  for (const payout of existingPayouts) {
    if (payout.status === "scheduled" || payout.status === "held") {
      assertPayoutTransition(payout.status, "reversed");
      await ctx.db.patch(payout._id, { status: "reversed", updatedAt: now });
      reversedPayoutIds.push(payout._id);
    }
  }
  const records = (await availablePaidRecords(ctx, booking._id)).sort(
    (a, b) => b.installmentIndex - a.installmentIndex,
  );
  const refundIds: Id<"refunds">[] = [];
  const refundAllocations = new Map<Id<"paymentRecords">, number>();
  if (refundMinor > 0) {
    let remaining = refundMinor;
    for (const record of records) {
      const available = record.amountMinor - record.refundedMinor;
      const allocate = Math.min(remaining, available);
      if (allocate > 0) {
        refundAllocations.set(record._id, allocate);
        const refundId = await ctx.db.insert("refunds", {
          bookingId: booking._id,
          paymentRecordId: record._id,
          amountMinor: allocate,
          currency: booking.currency,
          reason: args.reason,
          status: "pending",
          createdAt: now,
          updatedAt: now,
        });
        refundIds.push(refundId);
        await ctx.scheduler.runAfter(0, internal.refunds.executeRefund, {
          refundId,
          attempt: 0,
        });
        remaining -= allocate;
      }
      if (remaining === 0) break;
    }
  }
  // Paid transfers are settled by refund reconciliation, including paid forfeits.
  // Only retained charges without a paid payout fund new forfeits and commission.
  const retainedRecords = records.filter(
    (record) =>
      record.amountMinor -
        record.refundedMinor -
        (refundAllocations.get(record._id) ?? 0) >
        0 &&
      !existingPayouts.some(
        (payout) =>
          payout.paymentRecordId === record._id && payout.status === "paid",
      ),
  );
  const forfeitedMinor = retainedRecords.reduce(
    (sum, record) =>
      sum +
      record.amountMinor -
      record.refundedMinor -
      (refundAllocations.get(record._id) ?? 0),
    0,
  );
  const { artistNetMinor: artistPayoutMinor, commissionMinor: platformKeepsMinor } =
    splitFee(forfeitedMinor, booking.commissionBps);
  const forfeitPayoutIds: Id<"payouts">[] = [];
  if (artistPayoutMinor > 0) {
    const scheduledFor = now + PAYOUT_DELAY_MS;
    let remaining = artistPayoutMinor;
    for (const [index, record] of retainedRecords.entries()) {
      const refundBaselineMinor =
        record.refundedMinor + (refundAllocations.get(record._id) ?? 0);
      const available = record.amountMinor - refundBaselineMinor;
      // The last charge absorbs rounding so the shares sum to the forfeited payout.
      const amountMinor =
        index === retainedRecords.length - 1
          ? remaining
          : Math.floor((artistPayoutMinor * available) / forfeitedMinor + 0.5);
      remaining -= amountMinor;
      if (amountMinor === 0) continue;
      const payoutId = await ctx.db.insert("payouts", {
        bookingId: booking._id,
        bandId: booking.bandId,
        amountMinor,
        originalAmountMinor: amountMinor,
        refundBaselineMinor,
        currency: booking.currency,
        status: "scheduled",
        scheduledFor,
        attempt: 0,
        kind: "forfeit",
        paymentRecordId: record._id,
        sourceChargeId: record.stripeChargeId,
        createdAt: now,
        updatedAt: now,
      });
      forfeitPayoutIds.push(payoutId);
      await ctx.scheduler.runAt(scheduledFor, internal.payouts.releasePayout, {
        payoutId,
      });
    }
  }
  if (platformKeepsMinor > 0) {
    const settlementId =
      refundIds[0] ?? forfeitPayoutIds[0] ?? retainedRecords[0]._id;
    await appendLedgerEntry(ctx, {
      idempotencyKey: `forfeit-commission:${settlementId}`,
      kind: "commission",
      amountMinor: platformKeepsMinor,
      currency: booking.currency,
      fundsState: "available",
      bandId: booking.bandId,
      organizationId: booking.organizationId,
      bookingId: booking._id,
      occurredAt: now,
    });
  }
  // Pending refunds change the booking's refunded total only when they succeed.
  return { refundIds, forfeitPayoutIds, reversedPayoutIds };
}
