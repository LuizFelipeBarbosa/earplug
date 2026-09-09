import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { type Infer, v } from "convex/values";
import { internal as generatedInternal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  action,
  internalMutation,
  internalQuery,
  type QueryCtx,
} from "./_generated/server";
import { appBaseUrl, flag } from "./lib/env";
import { feedCutoff, requireUser } from "./lib/helpers";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import { expireOrder } from "./lib/ticketMint";
import { assertSellerOpen, resolveOrderSeller } from "./lib/ticketSeller";
import { assertTicketOrderTransition } from "./lib/ticketStatus";
import schema from "./schema";

// Keep this module typed before the next deployment regenerates the shared API.
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ ticketCheckout: typeof import("./ticketCheckout") }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const CHECKOUT_TTL_MS = 30 * 60_000;
const ticketOrderValidator = schema.tables.ticketOrders.validator.extend({
  _id: v.id("ticketOrders"),
  _creationTime: v.number(),
});
const checkoutContextValidator = v.object({
  order: ticketOrderValidator,
  gigTitle: v.string(),
  stripeAccountId: v.string(),
  sellerKind: v.union(v.literal("organization"), v.literal("band")),
  buyerEmail: v.string(),
});

async function requireOrder(ctx: QueryCtx, orderId: Id<"ticketOrders">) {
  const order = await ctx.db.get(orderId);
  if (!order) throw new Error("Ticket order not found");
  return order;
}

export const loadCheckoutContext = internalQuery({
  args: { orderId: v.id("ticketOrders") },
  returns: checkoutContextValidator,
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const order = await ctx.db.get(args.orderId);
    if (!order) {
      throw new Error("This ticket order can no longer be checked out");
    }
    if (user._id !== order.buyerUserId) {
      throw new Error("Not permitted for this ticket order");
    }
    if (order.status !== "reserved" && order.status !== "checkout_open") {
      throw new Error("This ticket order can no longer be checked out");
    }
    if (order.reservedUntil < (await feedCutoff(ctx))) {
      throw new Error("Your ticket hold has expired");
    }
    const [gig, seller] = await Promise.all([
      ctx.db.get(order.gigId),
      resolveOrderSeller(ctx, order),
    ]);
    if (!gig) throw new Error("Event not found");
    if (!seller) throw new Error("This event is not selling tickets");
    assertSellerOpen(seller);
    return {
      order,
      gigTitle: gig.title,
      stripeAccountId: seller.stripeAccountId!,
      sellerKind: seller.kind,
      buyerEmail: user.email,
    };
  },
});

export const reserveCheckoutAttempt = internalMutation({
  args: { orderId: v.id("ticketOrders"), expectedAttempt: v.number() },
  returns: v.number(),
  handler: async (ctx, args) => {
    const order = await requireOrder(ctx, args.orderId);
    if (order.attempt !== args.expectedAttempt) {
      throw new Error("Ticket order attempt changed elsewhere");
    }
    if (order.status !== "reserved" && order.status !== "checkout_open") {
      throw new Error("This ticket order can no longer be checked out");
    }
    const attempt = args.expectedAttempt + 1;
    await ctx.db.patch(order._id, { attempt, updatedAt: Date.now() });
    return attempt;
  },
});

export const markCheckoutOpen = internalMutation({
  args: {
    orderId: v.id("ticketOrders"),
    sessionId: v.string(),
    checkoutExpiresAt: v.number(),
    attempt: v.number(),
    stripePaymentIntentId: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const order = await requireOrder(ctx, args.orderId);
    if (
      order.status === "checkout_open" &&
      order.stripeCheckoutSessionId === args.sessionId
    ) {
      return null;
    }
    if (order.attempt !== args.attempt) {
      throw new Error("Ticket order attempt changed elsewhere");
    }
    assertTicketOrderTransition(order.status, "checkout_open");
    await ctx.db.patch(order._id, {
      status: "checkout_open",
      stripeCheckoutSessionId: args.sessionId,
      ...(args.stripePaymentIntentId !== undefined
        ? { stripePaymentIntentId: args.stripePaymentIntentId }
        : {}),
      checkoutExpiresAt: args.checkoutExpiresAt,
      reservedUntil: args.checkoutExpiresAt,
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const reopenReservation = internalMutation({
  args: { orderId: v.id("ticketOrders"), sessionId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const order = await requireOrder(ctx, args.orderId);
    if (
      order.status !== "checkout_open" ||
      order.stripeCheckoutSessionId !== args.sessionId
    ) {
      return null;
    }
    assertTicketOrderTransition(order.status, "reserved");
    await ctx.db.patch(order._id, {
      status: "reserved",
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const markSessionExpired = internalMutation({
  args: { sessionId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const order = await ctx.db
      .query("ticketOrders")
      .withIndex("by_stripeCheckoutSessionId", (q) =>
        q.eq("stripeCheckoutSessionId", args.sessionId),
      )
      .unique();
    if (order?.status === "checkout_open") {
      await expireOrder(ctx, order, "session_expired");
    }
    return null;
  },
});

export const loadOrderForCancel = internalQuery({
  args: { orderId: v.id("ticketOrders") },
  returns: ticketOrderValidator,
  handler: async (ctx, args) => {
    const order = await requireOrder(ctx, args.orderId);
    const user = await requireUser(ctx);
    if (user._id !== order.buyerUserId) {
      throw new Error("Not permitted for this ticket order");
    }
    return order;
  },
});

export const loadStripeAccountForCancel = internalQuery({
  args: { orderId: v.id("ticketOrders") },
  returns: v.string(),
  handler: async (ctx, args) => {
    const order = await requireOrder(ctx, args.orderId);
    const seller = await resolveOrderSeller(ctx, order);
    // Cancellation must still work after charges are disabled or a hold lapses.
    if (!seller?.stripeAccountId) {
      throw new Error(
        seller?.kind === "band"
          ? "This band is not ready to sell tickets yet"
          : "This organizer is not ready to sell tickets yet",
      );
    }
    return seller.stripeAccountId;
  },
});

export const markCancelled = internalMutation({
  args: { orderId: v.id("ticketOrders") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.orderId);
    if (order) await expireOrder(ctx, order, "cancelled");
    return null;
  },
});

function isAlreadyExpiredSession(error: unknown): boolean {
  if (!(error instanceof StripeApiError)) return false;
  return (
    /\bsession\b[\s\S]*\b(?:already|status|is|has)\b[\s\S]*\bexpired\b/i.test(
      error.message,
    ) || /^(?:checkout_)?session_(?:already_)?expired$/.test(error.code ?? "")
  );
}

function isAlreadyCompletedSession(error: unknown): boolean {
  if (!(error instanceof StripeApiError)) return false;
  return (
    /\bsession\b[\s\S]*\b(?:already|status|is|has)\b[\s\S]*\b(?:complete(?:d)?|paid)\b/i.test(
      error.message,
    ) ||
    /^(?:checkout_)?session_(?:already_)?(?:complete(?:d)?|paid)$/.test(
      error.code ?? "",
    )
  );
}

async function expireCheckoutSession(
  sessionId: string,
  stripeAccountId: string,
) {
  try {
    await stripeRequest(
      "POST",
      `/v1/checkout/sessions/${sessionId}/expire`,
      undefined,
      { stripeAccount: stripeAccountId },
    );
  } catch (error) {
    if (isAlreadyCompletedSession(error)) {
      throw new Error("This payment is already being confirmed");
    }
    if (!isAlreadyExpiredSession(error)) throw error;
  }
}

export const startCheckout = action({
  args: { orderId: v.id("ticketOrders") },
  returns: v.object({ url: v.string(), sessionId: v.string() }),
  handler: async (ctx, args): Promise<{ url: string; sessionId: string }> => {
    if (!flag("TICKETS_ENABLED", false)) {
      throw new Error("Ticket sales are not open yet");
    }
    const context: Infer<typeof checkoutContextValidator> = await ctx.runQuery(
      internal.ticketCheckout.loadCheckoutContext,
      args,
    );
    if (context.sellerKind === "band" && !flag("BAND_GIG_WRITES", true)) {
      throw new Error("Bands are not selling tickets right now");
    }
    const { order } = context;
    if (order.attempt >= 3) {
      throw new Error(
        "Too many checkout attempts; release the hold and start over",
      );
    }
    const holdDeadline = order.createdAt + 60 * 60_000;
    if (Date.now() >= holdDeadline) {
      throw new Error("Your ticket hold has expired");
    }
    if (order.status === "checkout_open" && order.stripeCheckoutSessionId) {
      await expireCheckoutSession(
        order.stripeCheckoutSessionId,
        context.stripeAccountId,
      );
      await ctx.runMutation(internal.ticketCheckout.reopenReservation, {
        orderId: order._id,
        sessionId: order.stripeCheckoutSessionId,
      });
    }
    const attempt: number = await ctx.runMutation(
      internal.ticketCheckout.reserveCheckoutAttempt,
      { orderId: order._id, expectedAttempt: order.attempt },
    );
    const checkoutExpiresAt =
      Math.floor(Math.min(Date.now() + CHECKOUT_TTL_MS, holdDeadline) / 1000) *
      1000;
    const session = await stripeRequest<{
      id: string;
      url: string;
      payment_intent?: string | null;
    }>(
      "POST",
      "/v1/checkout/sessions",
      {
        mode: "payment",
        payment_method_types: ["card"],
        customer_email: context.buyerEmail,
        client_reference_id: order._id,
        line_items: [
          {
            quantity: order.quantity,
            price_data: {
              currency: order.currency,
              unit_amount: order.unitPriceMinor + order.unitFeeMinor,
              product_data: { name: `${context.gigTitle} · Ticket` },
            },
          },
        ],
        payment_intent_data: {
          application_fee_amount: order.feeMinor,
          metadata: { ticketOrderId: order._id },
        },
        metadata: {
          ticketOrderId: order._id,
          gigId: order.gigId,
          quantity: order.quantity,
        },
        success_url: `${appBaseUrl()}/tickets/return?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${appBaseUrl()}/tickets/cancel?order=${order._id}`,
        expires_at: checkoutExpiresAt / 1000,
      },
      {
        idempotencyKey: stripeIdempotencyKey(
          "ticket-checkout",
          order._id,
          attempt,
        ),
        stripeAccount: context.stripeAccountId,
      },
    );
    await ctx.runMutation(internal.ticketCheckout.markCheckoutOpen, {
      orderId: order._id,
      sessionId: session.id,
      stripePaymentIntentId: session.payment_intent ?? undefined,
      checkoutExpiresAt,
      attempt,
    });
    return { url: session.url, sessionId: session.id };
  },
});

export const cancelOrder = action({
  args: { orderId: v.id("ticketOrders") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const order: Doc<"ticketOrders"> = await ctx.runQuery(
      internal.ticketCheckout.loadOrderForCancel,
      args,
    );
    if (order.status === "checkout_open") {
      if (order.stripeCheckoutSessionId) {
        const stripeAccountId: string = await ctx.runQuery(
          internal.ticketCheckout.loadStripeAccountForCancel,
          { orderId: order._id },
        );
        await expireCheckoutSession(
          order.stripeCheckoutSessionId,
          stripeAccountId,
        );
      }
      await ctx.runMutation(internal.ticketCheckout.markCancelled, args);
    } else if (order.status === "reserved") {
      await ctx.runMutation(internal.ticketCheckout.markCancelled, args);
    }
    return null;
  },
});

export const sweepStaleCheckouts = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const cutoff = Date.now() - 10 * 60_000;
    const orders = await ctx.db
      .query("ticketOrders")
      .withIndex("by_status_and_reservedUntil", (q) =>
        q.eq("status", "checkout_open").lt("reservedUntil", cutoff),
      )
      .take(100);
    for (const order of orders) {
      await expireOrder(ctx, order, "session_expired");
    }
    return null;
  },
});
