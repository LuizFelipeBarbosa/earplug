import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { appendLedgerEntry } from "../lib/ledger";
import { expireOrder, mintTickets } from "../lib/ticketMint";
import {
  assertTicketOrderTransition,
  assertTicketTransition,
} from "../lib/ticketStatus";
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
): Promise<boolean> {
  const details = await ctx.db
    .query("organizationPrivateDetails")
    .withIndex("by_organizationId", (q) =>
      q.eq("organizationId", order.organizationId),
    )
    .unique();
  if (!details?.stripeAccountId || event.account !== details.stripeAccountId) {
    console.warn(
      `${event.type} ignored: Stripe account mismatch for ticket order ${order._id}`,
    );
    return false;
  }
  return true;
}

export async function handleTicketCheckoutCompleted(
  ctx: MutationCtx,
  event: StripeEvent,
): Promise<void> {
  const session = event.data.object;
  let order = await orderForSession(ctx, session);
  if (!order) return;
  if (!(await assertTicketEventAccount(ctx, order, event))) return;
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
      assertTicketOrderTransition("reserved", "checkout_open");
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

  if (typeof session.amount_total !== "number") return;
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
  if (!(await assertTicketEventAccount(ctx, order, event))) return;
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
  if (!(await assertTicketEventAccount(ctx, order, event))) return;
  await reconcileDashboardRefund(
    ctx,
    order,
    charge as Parameters<typeof reconcileDashboardRefund>[2],
    event.id,
  );
}

export async function handleTicketDisputeCreated(
  ctx: MutationCtx,
  event: StripeEvent,
  charge: Record<string, any>,
): Promise<void> {
  const orderId = ctx.db.normalizeId(
    "ticketOrders",
    charge.metadata.ticketOrderId,
  );
  const order = orderId ? await ctx.db.get(orderId) : null;
  if (!order) return;
  if (!(await assertTicketEventAccount(ctx, order, event))) return;

  const dispute = event.data.object;
  const disputeId = dispute.id;
  const disputedMinor =
    typeof dispute.amount === "number" ? dispute.amount : order.totalMinor;
  const ledgerContext = {
    currency: order.currency,
    organizationId: order.organizationId,
    ticketOrderId: order._id,
    stripeRef: `dispute:${disputeId}`,
    stripeEventId: event.id,
    occurredAt: Date.now(),
  };
  await appendLedgerEntry(ctx, {
    ...ledgerContext,
    idempotencyKey: `ticket-dispute-hold:${disputeId}`,
    kind: "dispute_hold",
    amountMinor: -disputedMinor,
    fundsState: "disputed",
  });
}

export async function handleTicketDisputeClosed(
  ctx: MutationCtx,
  event: StripeEvent,
  charge: Record<string, any>,
): Promise<void> {
  const orderId = ctx.db.normalizeId(
    "ticketOrders",
    charge.metadata.ticketOrderId,
  );
  const order = orderId ? await ctx.db.get(orderId) : null;
  if (!order) return;
  if (!(await assertTicketEventAccount(ctx, order, event))) return;

  const dispute = event.data.object;
  const disputeId = dispute.id;
  const outcome = dispute.status;
  if (outcome !== "won" && outcome !== "lost") {
    console.log(
      `charge.dispute.closed ignored: ticket dispute ${disputeId} is ${outcome}`,
    );
    return;
  }
  const disputedMinor =
    typeof dispute.amount === "number" ? dispute.amount : order.totalMinor;
  const now = Date.now();
  const ledgerContext = {
    currency: order.currency,
    organizationId: order.organizationId,
    ticketOrderId: order._id,
    stripeRef: `dispute:${disputeId}`,
    stripeEventId: event.id,
    occurredAt: now,
  };
  if (outcome === "won") {
    await appendLedgerEntry(ctx, {
      ...ledgerContext,
      idempotencyKey: `ticket-dispute-release:${disputeId}`,
      kind: "dispute_release",
      amountMinor: disputedMinor,
      fundsState: "available",
    });
    return;
  }

  await appendLedgerEntry(ctx, {
    ...ledgerContext,
    idempotencyKey: `ticket-dispute-loss:${disputeId}`,
    kind: "dispute_loss",
    amountMinor: -disputedMinor,
    fundsState: "refunded",
  });
  if (order.status === "paid") {
    assertTicketOrderTransition("paid", "refunded");
    await ctx.db.patch(order._id, {
      status: "refunded",
      refundedMinor: order.totalMinor,
      updatedAt: now,
    });
    const tickets = await ctx.db
      .query("tickets")
      .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
      .filter((q) => q.eq(q.field("status"), "valid"))
      .collect();
    for (const ticket of tickets) {
      assertTicketTransition("valid", "cancelled");
      await ctx.db.patch(ticket._id, { status: "cancelled" });
    }
  }
}
