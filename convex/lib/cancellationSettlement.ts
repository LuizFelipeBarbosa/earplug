import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import type { Infer } from "convex/values";
import { internal as generatedInternal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import type * as payouts from "../payouts";
import type * as refunds from "../refunds";
import type { refundReasonValidator } from "../schema";
import {
  refundShareBps,
  settleCancellation,
  type BookingCancelledBy,
  type CancellationTemplate,
} from "./cancellationPolicy";
import { appendLedgerEntry } from "./ledger";
import { paymentRecordsForBooking } from "./paymentSchedule";
import { PAYOUT_DELAY_MS } from "./paymentStatus";

const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ payouts: typeof payouts; refunds: typeof refunds }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;

type CancellationSettlement = {
  refundMinor: number;
  forfeitedMinor: number;
  artistPayoutMinor: number;
  platformKeepsMinor: number;
  paidMinor: number;
  shareBps: number;
};

async function availablePaidRecords(
  ctx: QueryCtx | MutationCtx,
  bookingId: Id<"bookings">,
): Promise<Doc<"paymentRecords">[]> {
  return (await paymentRecordsForBooking(ctx, bookingId)).filter(
    (record) =>
      (record.status === "paid" ||
        record.status === "partially_refunded") &&
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
  const records = (await availablePaidRecords(ctx, booking._id)).sort(
    (a, b) => b.installmentIndex - a.installmentIndex,
  );
  if (settlement.refundMinor > 0) {
    let remaining = settlement.refundMinor;
    for (const record of records) {
      const available = record.amountMinor - record.refundedMinor;
      const allocate = Math.min(remaining, available);
      if (allocate > 0) {
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
        await ctx.scheduler.runAfter(0, internal.refunds.executeRefund, {
          refundId,
          attempt: 0,
        });
        remaining -= allocate;
      }
      if (remaining === 0) break;
    }
  }
  if (settlement.artistPayoutMinor > 0) {
    const scheduledFor = now + PAYOUT_DELAY_MS;
    const payoutId = await ctx.db.insert("payouts", {
      bookingId: booking._id,
      bandId: booking.bandId,
      amountMinor: settlement.artistPayoutMinor,
      currency: booking.currency,
      status: "scheduled",
      scheduledFor,
      attempt: 0,
      kind: "forfeit",
      sourceChargeId: records.at(-1)?.stripeChargeId,
      createdAt: now,
      updatedAt: now,
    });
    await ctx.scheduler.runAt(
      scheduledFor,
      internal.payouts.releasePayout,
      {
        payoutId,
      },
    );
  }
  if (settlement.platformKeepsMinor > 0) {
    await appendLedgerEntry(ctx, {
      idempotencyKey: `forfeit-commission:${booking._id}`,
      kind: "commission",
      amountMinor: settlement.platformKeepsMinor,
      currency: booking.currency,
      fundsState: "available",
      bandId: booking.bandId,
      organizationId: booking.organizationId,
      bookingId: booking._id,
      occurredAt: now,
    });
  }
  // Pending refunds change the booking's refunded total only when they succeed.
  return settlement;
}
