import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { sendTicketEmail } from "../emails";
import { requestOrderRefund } from "../ticketRefunds";
import { expireOrder } from "./ticketMint";

const BATCH_LIMIT = 100;
// Bounds lookahead past refunded paid rows; realistic per-gig volumes fit, but larger backlogs may need reruns as refunds settle.
const PAID_READ_BUFFER = 500;

export async function runTicketCancellationBatch(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
): Promise<{
  refundsRequested: number;
  holdsReleased: number;
  hasMore: boolean;
}> {
  const paidCandidates = await ctx.db
    .query("ticketOrders")
    .withIndex("by_gigId_and_status", (q) =>
      q.eq("gigId", gigId).eq("status", "paid"),
    )
    .take(PAID_READ_BUFFER);
  let hasMore = paidCandidates.length === PAID_READ_BUFFER;
  const paidOrders: Doc<"ticketOrders">[] = [];
  for (const order of paidCandidates) {
    if (paidOrders.length === BATCH_LIMIT) {
      // Unchecked candidates may still need refunds in the next transaction.
      hasMore = true;
      break;
    }
    const existingRefund = await ctx.db
      .query("ticketRefunds")
      .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
      .filter((q) => q.eq(q.field("reason"), "event_cancelled"))
      .first();
    if (!existingRefund) paidOrders.push(order);
  }

  let refundsRequested = 0;
  for (const order of paidOrders) {
    const refundId = await requestOrderRefund(ctx, order, "event_cancelled");
    if (refundId !== null) {
      await sendTicketEmail(ctx, order, "ticketRefunded");
      refundsRequested++;
    }
  }

  let holdsReleased = 0;
  for (const status of ["reserved", "checkout_open"] as const) {
    const remainingBudget = Math.max(
      0,
      BATCH_LIMIT - refundsRequested - holdsReleased,
    );
    const readLimit = Math.max(remainingBudget, 1);
    const orders = await ctx.db
      .query("ticketOrders")
      .withIndex("by_gigId_and_status", (q) =>
        q.eq("gigId", gigId).eq("status", status),
      )
      .take(readLimit);
    if (orders.length === readLimit) hasMore = true;
    if (remainingBudget === 0) continue;

    for (const order of orders) {
      await expireOrder(ctx, order, "cancelled");
      holdsReleased++;
    }
  }
  return { refundsRequested, holdsReleased, hasMore };
}

export async function cancelTicketSalesForGig(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
): Promise<{ refundsRequested: number; holdsReleased: number }> {
  const { refundsRequested, holdsReleased, hasMore } =
    await runTicketCancellationBatch(ctx, gigId);
  if (hasMore) {
    await ctx.scheduler.runAfter(0, internal.ticketCancellationJobs.processBatch, {
      gigId,
    });
  }
  return { refundsRequested, holdsReleased };
}
