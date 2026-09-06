import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { type Infer, v } from "convex/values";
import { internal as generatedInternal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalAction,
  internalMutation,
  internalQuery,
  type MutationCtx,
} from "./_generated/server";
import { flag } from "./lib/env";
import { appendLedgerEntry } from "./lib/ledger";
import { stripeIdempotencyKey, stripeRequest } from "./lib/stripeClient";
import {
  assertTicketOrderTransition,
  assertTicketRefundTransition,
  assertTicketTransition,
  type TicketRefundReason,
} from "./lib/ticketStatus";
import schema from "./schema";

// Keep this lane type-safe before its functions enter the shared generated API.
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ ticketRefunds: typeof import("./ticketRefunds") }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;

const refundValidator = schema.tables.ticketRefunds.validator.extend({
  _id: v.id("ticketRefunds"),
  _creationTime: v.number(),
});
const orderValidator = schema.tables.ticketOrders.validator.extend({
  _id: v.id("ticketOrders"),
  _creationTime: v.number(),
});
const refundContextValidator = v.object({
  refund: refundValidator,
  order: orderValidator,
  stripeAccountId: v.string(),
  paymentIntentId: v.string(),
});

export async function requestOrderRefund(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  reason: TicketRefundReason,
  options?: { amountMinor?: number },
): Promise<Id<"ticketRefunds"> | null> {
  if (order.status !== "paid") {
    throw new Error("Only paid ticket orders can be refunded");
  }
  if (!order.stripePaymentIntentId) {
    throw new Error("Ticket order has no Stripe payment intent");
  }
  const amountMinor =
    options?.amountMinor ?? order.totalMinor - order.refundedMinor;
  if (amountMinor <= 0) return null;

  const pending = await ctx.db
    .query("ticketRefunds")
    .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
    .filter((q) => q.eq(q.field("status"), "pending"))
    .first();
  if (pending) return pending._id;

  const now = Date.now();
  const refundId = await ctx.db.insert("ticketRefunds", {
    orderId: order._id,
    gigId: order.gigId,
    organizationId: order.organizationId,
    amountMinor,
    currency: order.currency,
    reason,
    status: "pending",
    stripePaymentIntentId: order.stripePaymentIntentId,
    attempt: 0,
    createdAt: now,
    updatedAt: now,
  });
  await ctx.scheduler.runAfter(0, internal.ticketRefunds.executeRefund, {
    refundId,
    attempt: 0,
  });
  return refundId;
}

export async function requestLatePaymentRefund(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  options: {
    stripePaymentIntentId: string;
    amountMinor: number;
    stripeEventId: string;
  },
): Promise<Id<"ticketRefunds">> {
  const existing = await ctx.db
    .query("ticketRefunds")
    .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
    .filter((q) =>
      q.and(
        q.eq(q.field("reason"), "late_payment"),
        q.eq(q.field("stripePaymentIntentId"), options.stripePaymentIntentId),
        q.or(
          q.eq(q.field("status"), "pending"),
          q.eq(q.field("status"), "succeeded"),
        ),
      ),
    )
    .first();
  if (existing) return existing._id;

  const now = Date.now();
  if (order.stripePaymentIntentId === undefined) {
    await ctx.db.patch(order._id, {
      stripePaymentIntentId: options.stripePaymentIntentId,
      updatedAt: now,
    });
  }
  const refundId = await ctx.db.insert("ticketRefunds", {
    orderId: order._id,
    gigId: order.gigId,
    organizationId: order.organizationId,
    amountMinor: options.amountMinor,
    currency: order.currency,
    reason: "late_payment",
    status: "pending",
    stripePaymentIntentId: options.stripePaymentIntentId,
    attempt: 0,
    createdAt: now,
    updatedAt: now,
  });
  await ctx.scheduler.runAfter(0, internal.ticketRefunds.executeRefund, {
    refundId,
    attempt: 0,
  });
  return refundId;
}

export const loadRefundContext = internalQuery({
  args: { refundId: v.id("ticketRefunds") },
  returns: refundContextValidator,
  handler: async (ctx, args) => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund) throw new Error("Refund not found");
    const order = await ctx.db.get(refund.orderId);
    if (!order) throw new Error("Ticket order not found");
    const paymentIntentId =
      refund.stripePaymentIntentId ?? order.stripePaymentIntentId;
    if (!paymentIntentId) {
      throw new Error("Ticket order has no Stripe payment intent");
    }
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", order.organizationId),
      )
      .unique();
    if (!details?.stripeAccountId) {
      throw new Error("Organization has no Stripe account");
    }
    return {
      refund,
      order,
      stripeAccountId: details.stripeAccountId,
      paymentIntentId,
    };
  },
});

export const executeRefund = internalAction({
  args: { refundId: v.id("ticketRefunds"), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const context: Infer<typeof refundContextValidator> = await ctx.runQuery(
      internal.ticketRefunds.loadRefundContext,
      { refundId: args.refundId },
    );
    const { refund, order, stripeAccountId, paymentIntentId } = context;
    if (refund.status !== "pending") return null;
    if (!flag("TICKETS_ENABLED", false)) {
      await ctx.runMutation(internal.ticketRefunds.markRefundFailed, {
        refundId: refund._id,
        attempt: args.attempt,
        error: "Ticket sales are disabled",
      });
      return null;
    }

    let response: { id: string };
    try {
      response = await stripeRequest<{ id: string }>(
        "POST",
        "/v1/refunds",
        {
          payment_intent: paymentIntentId,
          amount: refund.amountMinor,
          refund_application_fee: true,
          metadata: {
            ticketOrderId: order._id,
            refundId: refund._id,
            reason: refund.reason,
          },
        },
        {
          idempotencyKey: stripeIdempotencyKey("ticket-refund", refund._id),
          stripeAccount: stripeAccountId,
        },
      );
    } catch (error) {
      console.error(`Could not execute ticket refund ${refund._id}`, error);
      await ctx.runMutation(internal.ticketRefunds.markRefundFailed, {
        refundId: refund._id,
        attempt: args.attempt,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    }
    // As with booking refunds, accounting failures after a successful POST
    // must not enter the Stripe failure/retry path.
    await ctx.runMutation(internal.ticketRefunds.markRefundSucceeded, {
      refundId: refund._id,
      stripeRefundId: response.id,
    });
    return null;
  },
});

export async function applyRefundSucceeded(
  ctx: MutationCtx,
  refund: Doc<"ticketRefunds">,
  stripeRefundId: string,
  stripeEventId?: string,
): Promise<void> {
  if (
    refund.status === "succeeded" &&
    refund.stripeRefundId === stripeRefundId
  ) {
    return;
  }
  assertTicketRefundTransition(refund.status, "succeeded");
  const now = Date.now();
  await ctx.db.patch(refund._id, {
    status: "succeeded",
    stripeRefundId,
    updatedAt: now,
  });
  const order = await ctx.db.get(refund.orderId);
  if (!order) throw new Error("Ticket order not found");
  const wasPaid = order.status === "paid";
  const refundedMinor = order.refundedMinor + refund.amountMinor;
  await ctx.db.patch(order._id, {
    refundedMinor,
    stripeRefundId,
    updatedAt: now,
  });
  if (wasPaid && refundedMinor >= order.totalMinor) {
    assertTicketOrderTransition(order.status, "refunded");
    await ctx.db.patch(order._id, { status: "refunded" });
    const tickets = await ctx.db
      .query("tickets")
      .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
      .filter((q) =>
        q.or(q.eq(q.field("status"), "valid"), q.eq(q.field("status"), "used")),
      )
      .collect();
    for (const ticket of tickets) {
      assertTicketTransition(ticket.status, "refunded");
      await ctx.db.patch(ticket._id, { status: "refunded" });
    }
  }

  const ledgerContext = {
    occurredAt: now,
    organizationId: order.organizationId,
    ticketOrderId: order._id,
    currency: refund.currency,
    fundsState: "refunded" as const,
    stripeRef: `refund:${stripeRefundId}`,
    ...(stripeEventId !== undefined ? { stripeEventId } : {}),
  };
  await appendLedgerEntry(ctx, {
    ...ledgerContext,
    kind: "ticket_refund",
    amountMinor: -refund.amountMinor,
    idempotencyKey: `ticket-refund:${refund._id}`,
  });
  if (wasPaid) {
    await appendLedgerEntry(ctx, {
      ...ledgerContext,
      kind: "ticket_fee",
      amountMinor: -Math.round(
        (order.feeMinor * refund.amountMinor) / order.totalMinor,
      ),
      idempotencyKey: `ticket-refund-fee:${refund._id}`,
    });
  }
}

export const markRefundSucceeded = internalMutation({
  args: { refundId: v.id("ticketRefunds"), stripeRefundId: v.string() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund) throw new Error("Refund not found");
    const order = await ctx.db.get(refund.orderId);
    if (!order) throw new Error("Ticket order not found");
    await applyRefundSucceeded(ctx, refund, args.stripeRefundId);
    return null;
  },
});

export const markRefundFailed = internalMutation({
  args: {
    refundId: v.id("ticketRefunds"),
    attempt: v.number(),
    error: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund || refund.status === "succeeded") return null;
    const now = Date.now();
    if (refund.status === "pending") {
      assertTicketRefundTransition("pending", "failed");
      await ctx.db.patch(refund._id, {
        status: "failed",
        error: args.error,
        updatedAt: now,
      });
    }
    if (args.attempt < 2) {
      assertTicketRefundTransition("failed", "pending");
      await ctx.db.patch(refund._id, { status: "pending", updatedAt: now });
      await ctx.scheduler.runAfter(
        60 * 60 * 1000,
        internal.ticketRefunds.executeRefund,
        { refundId: refund._id, attempt: args.attempt + 1 },
      );
    }
    return null;
  },
});

export const retryFailedTicketRefunds = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx): Promise<null> => {
    if (!flag("TICKETS_ENABLED", false)) return null;
    const rows = await ctx.db
      .query("ticketRefunds")
      .withIndex("by_status_and_updatedAt", (q) => q.eq("status", "failed"))
      .take(50);
    const now = Date.now();
    for (const row of rows) {
      assertTicketRefundTransition("failed", "pending");
      await ctx.db.patch(row._id, { status: "pending", updatedAt: now });
      await ctx.scheduler.runAfter(0, internal.ticketRefunds.executeRefund, {
        refundId: row._id,
        attempt: 0,
      });
    }
    return null;
  },
});

export async function reconcileDashboardRefund(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  charge: {
    id: string;
    amount_refunded: number;
    payment_intent?: string;
    refunds?: { data: Array<{ id: string; amount: number }> };
  },
  stripeEventId: string,
): Promise<void> {
  const delta = charge.amount_refunded - order.refundedMinor;
  if (delta <= 0) return;
  const stripeRefundId = charge.refunds?.data.at(-1)?.id ?? charge.id;
  const existing = await ctx.db
    .query("ticketRefunds")
    .withIndex("by_stripeRefundId", (q) =>
      q.eq("stripeRefundId", stripeRefundId),
    )
    .unique();
  if (existing) return;

  const now = Date.now();
  const refundId = await ctx.db.insert("ticketRefunds", {
    orderId: order._id,
    gigId: order.gigId,
    organizationId: order.organizationId,
    amountMinor: delta,
    currency: order.currency,
    reason: "dashboard",
    status: "pending",
    stripePaymentIntentId: charge.payment_intent,
    attempt: 0,
    createdAt: now,
    updatedAt: now,
  });
  const refund = await ctx.db.get(refundId);
  if (!refund) throw new Error("Refund not found");
  await applyRefundSucceeded(ctx, refund, stripeRefundId, stripeEventId);
}
