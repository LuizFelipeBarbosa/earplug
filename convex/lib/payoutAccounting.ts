import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { assertPayoutTransition } from "./paymentStatus";

export async function schedulePayoutReversal(
  ctx: MutationCtx,
  payout: Doc<"payouts">,
  targetMinor: number,
): Promise<void> {
  const reservedMinor =
    payout.reversalReservedMinor ?? payout.reversedMinor ?? 0;
  const reversedMinor = Math.min(payout.amountMinor, targetMinor);
  const reversalMinor = reversedMinor - reservedMinor;
  if (reversalMinor <= 0) return;

  // Reserve before scheduling: another refund must not reclaim these funds again.
  // Keep the reservation on an ambiguous Stripe failure for reconciliation.
  await ctx.db.patch(payout._id, { reversalReservedMinor: reversedMinor });
  await ctx.scheduler.runAfter(0, internal.refunds.reverseTransfer, {
    payoutId: payout._id,
    reversalMinor,
    reversedMinor,
  });
}

export async function reconcilePaymentPayouts(
  ctx: MutationCtx,
  record: Doc<"paymentRecords">,
): Promise<void> {
  const payouts = await ctx.db
    .query("payouts")
    .withIndex("by_paymentRecordId", (q) => q.eq("paymentRecordId", record._id))
    .take(50);
  for (const payout of payouts) {
    if (payout.status === "reversed") continue;
    const originalAmountMinor =
      payout.originalAmountMinor ?? payout.amountMinor;
    // Forfeiture already accounts for the cancellation refund, even before it settles.
    const baseline = payout.refundBaselineMinor ?? 0;
    const retainedMinor = Math.max(0, record.amountMinor - baseline);
    const remainingMinor = Math.max(
      0,
      record.amountMinor - Math.max(baseline, record.refundedMinor),
    );
    const entitledMinor =
      retainedMinor === 0
        ? 0
        : Math.floor((originalAmountMinor * remainingMinor) / retainedMinor);
    if (payout.status === "paid") {
      await schedulePayoutReversal(
        ctx,
        payout,
        payout.amountMinor - entitledMinor,
      );
    } else if (payout.status === "scheduled" || payout.status === "held") {
      if (entitledMinor === 0) {
        assertPayoutTransition(payout.status, "reversed");
        await ctx.db.patch(payout._id, {
          status: "reversed",
          updatedAt: Date.now(),
        });
      } else if (entitledMinor < payout.amountMinor) {
        await ctx.db.patch(payout._id, {
          amountMinor: entitledMinor,
          originalAmountMinor,
          updatedAt: Date.now(),
        });
      }
    }
    // A processing transfer may already have reached Stripe; markPayoutPaid
    // reconciles it once the transfer id is known.
  }
}
