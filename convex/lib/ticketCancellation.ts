import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { sendTicketEmail } from "../emails";
import { requestOrderRefund } from "../ticketRefunds";
import { expireOrder } from "./ticketMint";

export async function cancelTicketSalesForGig(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
): Promise<{ refundsRequested: number; holdsReleased: number }> {
  const paidOrders = await ctx.db
    .query("ticketOrders")
    .withIndex("by_gigId_and_status", (q) =>
      q.eq("gigId", gigId).eq("status", "paid"),
    )
    .take(500);
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
    const orders = await ctx.db
      .query("ticketOrders")
      .withIndex("by_gigId_and_status", (q) =>
        q.eq("gigId", gigId).eq("status", status),
      )
      .take(500);
    for (const order of orders) {
      await expireOrder(ctx, order, "cancelled");
      holdsReleased++;
    }
  }
  return { refundsRequested, holdsReleased };
}
