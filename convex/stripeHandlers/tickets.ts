import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { expireOrder, mintTickets } from "../lib/ticketMint";
import type { StripeEvent } from "../stripeWebhook";
import {
  reconcileDashboardRefund,
  requestLatePaymentRefund,
} from "../ticketRefunds";

export function isTicketSession(object: Record<string, any>): boolean {
  return typeof object.metadata?.ticketOrderId === "string";
}

async function orderForSession(
  ctx: MutationCtx,
  session: Record<string, any>,
): Promise<Doc<"ticketOrders"> | null> {
  if (isTicketSession(session)) {
    const orderId = ctx.db.normalizeId(
      "ticketOrders",
      session.metadata.ticketOrderId,
    );
    const order = orderId ? await ctx.db.get(orderId) : null;
    if (order) return order;
  }
  return await ctx.db
    .query("ticketOrders")
    .withIndex("by_stripeCheckoutSessionId", (q) =>
      q.eq("stripeCheckoutSessionId", session.id),
    )
    .unique();
}

async function assertTicketEventAccount(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  event: StripeEvent,
): Promise<void> {
  const details = await ctx.db
    .query("organizationPrivateDetails")
    .withIndex("by_organizationId", (q) =>
      q.eq("organizationId", order.organizationId),
    )
    .unique();
  if (!details?.stripeAccountId || event.account !== details.stripeAccountId) {
    throw new Error("Ticket event account mismatch");
  }
}

export async function handleTicketCheckoutCompleted(
  ctx: MutationCtx,
  event: StripeEvent,
): Promise<void> {
  const session = event.data.object;
  let order = await orderForSession(ctx, session);
  if (!order) return;
  await assertTicketEventAccount(ctx, order, event);
  if (session.payment_status !== "paid") return;

  const matchingSession = order.stripeCheckoutSessionId === session.id;
  if (order.status === "paid" && matchingSession) return;
  if (
    matchingSession &&
    (order.status === "checkout_open" || order.status === "reserved")
  ) {
    if (order.status === "reserved") {
      // A delayed payment may arrive after Checkout was reopened for a retry.
      const updatedAt = Date.now();
      await ctx.db.patch(order._id, { status: "checkout_open", updatedAt });
      order = { ...order, status: "checkout_open", updatedAt };
    }
    await mintTickets(ctx, order, {
      stripePaymentIntentId:
        typeof session.payment_intent === "string"
          ? session.payment_intent
          : undefined,
      stripeEventId: event.id,
      paidAt: event.created * 1000,
    });
    return;
  }

  if (typeof session.payment_intent !== "string") {
    throw new Error("Late ticket payment is missing a Stripe payment intent");
  }
  await requestLatePaymentRefund(ctx, order, {
    stripePaymentIntentId: session.payment_intent,
    amountMinor: session.amount_total,
    stripeEventId: event.id,
  });
}

export async function handleTicketCheckoutExpired(
  ctx: MutationCtx,
  event: StripeEvent,
): Promise<void> {
  const session = event.data.object;
  const order = await orderForSession(ctx, session);
  if (!order) return;
  await assertTicketEventAccount(ctx, order, event);
  if (
    order.status === "checkout_open" &&
    session.id === order.stripeCheckoutSessionId
  ) {
    await expireOrder(ctx, order, "session_expired");
  }
}

export async function handleTicketChargeRefunded(
  ctx: MutationCtx,
  event: StripeEvent,
): Promise<void> {
  const charge = event.data.object;
  if (!isTicketSession(charge)) return;
  const orderId = ctx.db.normalizeId(
    "ticketOrders",
    charge.metadata.ticketOrderId,
  );
  const order = orderId ? await ctx.db.get(orderId) : null;
  if (!order) return;
  await assertTicketEventAccount(ctx, order, event);
  await reconcileDashboardRefund(
    ctx,
    order,
    charge as Parameters<typeof reconcileDashboardRefund>[2],
    event.id,
  );
}
