import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { appendLedgerEntry } from "./ledger";
import { commitInventory, releaseInventory } from "./ticketInventory";
import {
  assertTicketOrderTransition,
  TICKET_TOKEN_PREFIX,
} from "./ticketStatus";

function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

async function uniqueTicketToken(ctx: MutationCtx): Promise<string> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const token = TICKET_TOKEN_PREFIX + randomToken();
    const existing = await ctx.db
      .query("tickets")
      .withIndex("by_token", (q) => q.eq("token", token))
      .first();
    if (!existing) return token;
  }
  throw new Error("Could not create a unique ticket token after 3 attempts");
}

async function orderInventory(ctx: MutationCtx, order: Doc<"ticketOrders">) {
  const inventory = await ctx.db
    .query("gigTicketInventory")
    .withIndex("by_gigId", (q) => q.eq("gigId", order.gigId))
    .unique();
  if (!inventory) throw new Error("Ticket inventory not found");
  return inventory;
}

export async function mintTickets(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  payment: {
    stripePaymentIntentId?: string;
    stripeChargeId?: string;
    stripeEventId?: string;
    paidAt: number;
  },
): Promise<Id<"tickets">[]> {
  if (order.status === "paid") {
    const tickets = await ctx.db
      .query("tickets")
      .withIndex("by_orderId", (q) => q.eq("orderId", order._id))
      .collect();
    return tickets.map((ticket) => ticket._id);
  }

  assertTicketOrderTransition(order.status, "paid");
  const now = Date.now();
  await ctx.db.patch(order._id, {
    status: "paid",
    paidAt: payment.paidAt,
    ...(payment.stripePaymentIntentId !== undefined
      ? { stripePaymentIntentId: payment.stripePaymentIntentId }
      : {}),
    ...(payment.stripeChargeId !== undefined
      ? { stripeChargeId: payment.stripeChargeId }
      : {}),
    updatedAt: now,
  });
  const inventory = await orderInventory(ctx, order);
  await commitInventory(ctx, inventory, order.quantity);

  const ticketIds: Id<"tickets">[] = [];
  for (let index = 0; index < order.quantity; index++) {
    const token = await uniqueTicketToken(ctx);
    ticketIds.push(
      await ctx.db.insert("tickets", {
        orderId: order._id,
        gigId: order.gigId,
        organizationId: order.organizationId,
        holderUserId: order.buyerUserId,
        token,
        status: "valid",
        createdAt: now,
      }),
    );
  }

  const ledgerFields = {
    currency: order.currency,
    fundsState: "pending" as const,
    organizationId: order.organizationId,
    ticketOrderId: order._id,
    stripeRef: `charge:${payment.stripeChargeId ?? payment.stripePaymentIntentId}`,
    stripeEventId: payment.stripeEventId,
    occurredAt: payment.paidAt,
  };
  await appendLedgerEntry(ctx, {
    ...ledgerFields,
    kind: "ticket_sale",
    amountMinor: order.totalMinor,
    idempotencyKey: `ticket-sale:${order._id}`,
  });
  await appendLedgerEntry(ctx, {
    ...ledgerFields,
    kind: "ticket_fee",
    amountMinor: order.feeMinor,
    idempotencyKey: `ticket-fee:${order._id}`,
  });
  return ticketIds;
}

export async function expireOrder(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  reason: "session_expired" | "cancelled",
): Promise<void> {
  if (
    order.status === "expired" ||
    order.status === "cancelled" ||
    order.status === "paid" ||
    order.status === "refunded"
  ) {
    return;
  }
  const status = reason === "session_expired" ? "expired" : "cancelled";
  assertTicketOrderTransition(order.status, status);
  await ctx.db.patch(order._id, { status, updatedAt: Date.now() });
  const inventory = await orderInventory(ctx, order);
  await releaseInventory(ctx, inventory, order.quantity);
}
