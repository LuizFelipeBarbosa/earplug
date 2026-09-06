import { type Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalMutation,
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";
import { flag } from "./lib/env";
import { currentUser, feedCutoff, requireUser } from "./lib/helpers";
import { orderTotals, resolveTicketingFee } from "./lib/ticketFees";
import {
  availableCount,
  ensureInventory,
  releaseInventory,
  reserveInventory,
} from "./lib/ticketInventory";
import {
  assertTicketOrderTransition,
  ticketOrderStatusValidator,
} from "./lib/ticketStatus";
import schema, { gigLifecycleValidator } from "./schema";

export const ticketOrderValidator = schema.tables.ticketOrders.validator.extend(
  {
    _id: v.id("ticketOrders"),
    _creationTime: v.number(),
  },
);

export const ticketValidator = schema.tables.tickets.validator.extend({
  _id: v.id("tickets"),
  _creationTime: v.number(),
});

export const ticketSummaryValidator = ticketValidator.extend({
  gig: v.object({
    _id: v.id("gigs"),
    title: v.string(),
    slug: v.optional(v.string()),
    startsAt: v.number(),
    doorsAt: v.optional(v.number()),
    venueName: v.string(),
    lifecycle: v.optional(gigLifecycleValidator),
  }),
});

export const reserve = mutation({
  args: {
    gigId: v.id("gigs"),
    quantity: v.number(),
    referralBandSlug: v.optional(v.string()),
  },
  returns: v.object({
    orderId: v.id("ticketOrders"),
    quantity: v.number(),
    unitPriceMinor: v.number(),
    unitFeeMinor: v.number(),
    subtotalMinor: v.number(),
    feeMinor: v.number(),
    totalMinor: v.number(),
    currency: v.string(),
    reservedUntil: v.number(),
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (!flag("TICKETS_ENABLED", false)) {
      throw new Error("Ticket sales are not open yet");
    }
    const gig = await ctx.db.get(args.gigId);
    if (!gig) throw new Error("Event not found");
    if (
      gig.ticketing !== "paid" ||
      (gig.lifecycle ?? "published") !== "published" ||
      !gig.createdByOrganization
    ) {
      throw new Error("This event is not selling tickets");
    }
    const now = Date.now();
    if (gig.startsAt <= now) {
      throw new Error("This event has already started");
    }
    const organization = await ctx.db.get(gig.createdByOrganization);
    if (!organization || organization.status === "suspended") {
      throw new Error("This organizer is not ready to sell tickets yet");
    }
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", organization._id),
      )
      .unique();
    if (!details || details.stripeChargesEnabled !== true) {
      throw new Error("This organizer is not ready to sell tickets yet");
    }
    if (
      !Number.isInteger(args.quantity) ||
      args.quantity < 1 ||
      args.quantity > 10
    ) {
      throw new Error("Choose between 1 and 10 tickets");
    }
    for (const status of ["reserved", "checkout_open"] as const) {
      const existing = await ctx.db
        .query("ticketOrders")
        .withIndex("by_gigId_and_buyerUserId_and_status", (q) =>
          q
            .eq("gigId", gig._id)
            .eq("buyerUserId", user._id)
            .eq("status", status),
        )
        .first();
      if (existing) {
        throw new Error("Finish or release your current ticket order first");
      }
    }

    const fee = resolveTicketingFee(organization);
    if (
      gig.ticketPriceMinor === undefined ||
      gig.ticketCurrency === undefined
    ) {
      throw new Error("This event is not selling tickets");
    }
    const totals = orderTotals({
      unitPriceMinor: gig.ticketPriceMinor,
      quantity: args.quantity,
      fee,
    });
    let referralBandId: Id<"bands"> | undefined;
    if (args.referralBandSlug !== undefined) {
      const band = await ctx.db
        .query("bands")
        .withIndex("by_slug", (q) => q.eq("slug", args.referralBandSlug!))
        .unique();
      const bandIds = new Set([
        ...gig.lineup,
        ...(gig.createdByBand ? [gig.createdByBand] : []),
      ]);
      if (band && bandIds.has(band._id)) referralBandId = band._id;
    }
    const inventory = await ensureInventory(ctx, gig);
    const reservedUntil = now + 30 * 60_000;
    const orderId = await ctx.db.insert("ticketOrders", {
      gigId: gig._id,
      organizationId: gig.createdByOrganization,
      buyerUserId: user._id,
      quantity: args.quantity,
      unitPriceMinor: gig.ticketPriceMinor,
      ...totals,
      currency: gig.ticketCurrency,
      status: "reserved",
      reservedUntil,
      attempt: 0,
      ...(referralBandId ? { referralBandId } : {}),
      refundedMinor: 0,
      createdAt: now,
      updatedAt: now,
    });
    await reserveInventory(ctx, inventory, args.quantity);
    await ctx.scheduler.runAt(
      reservedUntil,
      internal.tickets.releaseReservation,
      {
        orderId,
        expectedReservedUntil: reservedUntil,
      },
    );
    return {
      orderId,
      quantity: args.quantity,
      unitPriceMinor: gig.ticketPriceMinor,
      ...totals,
      currency: gig.ticketCurrency,
      reservedUntil,
    };
  },
});

async function releaseOrderReservation(
  ctx: MutationCtx,
  order: Doc<"ticketOrders">,
  status: "expired" | "cancelled",
): Promise<void> {
  assertTicketOrderTransition(order.status, status);
  await ctx.db.patch(order._id, { status, updatedAt: Date.now() });
  // Existing reservations must release even if the gig stopped selling tickets.
  const inventory = await ctx.db
    .query("gigTicketInventory")
    .withIndex("by_gigId", (q) => q.eq("gigId", order.gigId))
    .unique();
  if (!inventory) throw new Error("Ticket inventory not found");
  await releaseInventory(ctx, inventory, order.quantity);
}

export const releaseReservation = internalMutation({
  args: {
    orderId: v.id("ticketOrders"),
    expectedReservedUntil: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.orderId);
    if (
      !order ||
      order.status !== "reserved" ||
      order.reservedUntil !== args.expectedReservedUntil
    ) {
      return null;
    }
    await releaseOrderReservation(ctx, order, "expired");
    return null;
  },
});

export const cancelReservation = mutation({
  args: { orderId: v.id("ticketOrders") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const order = await ctx.db.get(args.orderId);
    if (!order) throw new Error("Ticket order not found");
    if (order.buyerUserId !== user._id) {
      throw new Error("Not permitted for this ticket order");
    }
    if (order.status === "checkout_open") {
      throw new Error("Close the payment page first");
    }
    if (order.status !== "reserved") {
      throw new Error("This ticket order can no longer be cancelled");
    }
    await releaseOrderReservation(ctx, order, "cancelled");
    return null;
  },
});

export const expireStaleReservations = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const now = Date.now();
    const orders = await ctx.db
      .query("ticketOrders")
      .withIndex("by_status_and_reservedUntil", (q) =>
        q.eq("status", "reserved").lt("reservedUntil", now),
      )
      .take(100);
    for (const order of orders) {
      await releaseOrderReservation(ctx, order, "expired");
    }
    return null;
  },
});

async function ticketSummary(
  ctx: QueryCtx,
  ticket: Doc<"tickets">,
): Promise<Infer<typeof ticketSummaryValidator> | null> {
  const gig = await ctx.db.get(ticket.gigId);
  if (!gig) return null;
  const venue = await ctx.db.get(gig.venueId);
  if (!venue) return null;
  return {
    ...ticket,
    gig: {
      _id: gig._id,
      title: gig.title,
      slug: gig.slug,
      startsAt: gig.startsAt,
      doorsAt: gig.doorsAt,
      venueName: venue.name,
      lifecycle: gig.lifecycle,
    },
  };
}

export const myTickets = query({
  args: {},
  returns: v.array(ticketSummaryValidator),
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    const tickets = await ctx.db
      .query("tickets")
      .withIndex("by_holderUserId_and_createdAt", (q) =>
        q.eq("holderUserId", user._id),
      )
      .take(200);
    const summaries = (
      await Promise.all(tickets.map((ticket) => ticketSummary(ctx, ticket)))
    ).filter((summary) => summary !== null);
    const cutoff = await feedCutoff(ctx);
    const upcoming = summaries
      .filter((summary) => summary.gig.startsAt >= cutoff)
      .sort((a, b) => a.gig.startsAt - b.gig.startsAt);
    const past = summaries
      .filter((summary) => summary.gig.startsAt < cutoff)
      .sort((a, b) => b.gig.startsAt - a.gig.startsAt);
    return [...upcoming, ...past];
  },
});

export const get = query({
  args: { ticketId: v.id("tickets") },
  returns: v.union(ticketSummaryValidator, v.null()),
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (!user) return null;
    const ticket = await ctx.db.get(args.ticketId);
    if (!ticket || ticket.holderUserId !== user._id) return null;
    return await ticketSummary(ctx, ticket);
  },
});

export const orderStatus = query({
  args: { sessionId: v.string() },
  returns: v.union(
    v.object({
      orderId: v.id("ticketOrders"),
      gigId: v.id("gigs"),
      gigSlug: v.optional(v.string()),
      status: ticketOrderStatusValidator,
      quantity: v.number(),
      totalMinor: v.number(),
      currency: v.string(),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (!user) return null;
    const order = await ctx.db
      .query("ticketOrders")
      .withIndex("by_stripeCheckoutSessionId", (q) =>
        q.eq("stripeCheckoutSessionId", args.sessionId),
      )
      .unique();
    if (!order || order.buyerUserId !== user._id) return null;
    const gig = await ctx.db.get(order.gigId);
    return {
      orderId: order._id,
      gigId: order.gigId,
      gigSlug: gig?.slug,
      status: order.status,
      quantity: order.quantity,
      totalMinor: order.totalMinor,
      currency: order.currency,
    };
  },
});

export const salesForGig = query({
  args: { gigId: v.id("gigs") },
  returns: v.object({
    capacity: v.number(),
    sold: v.number(),
    reserved: v.number(),
    available: v.number(),
    ordersPaid: v.number(),
    grossMinor: v.number(),
    feeMinor: v.number(),
    netMinor: v.number(),
    currency: v.string(),
    truncated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const gig = await ctx.db.get(args.gigId);
    if (!gig || !gig.createdByOrganization) throw new Error("Event not found");
    await requireOrganizationRole(ctx, gig.createdByOrganization, [
      "owner",
      "manager",
      "finance",
    ]);
    const inventory = await ctx.db
      .query("gigTicketInventory")
      .withIndex("by_gigId", (q) => q.eq("gigId", gig._id))
      .unique();
    if (!inventory) {
      return {
        capacity: 0,
        sold: 0,
        reserved: 0,
        available: 0,
        ordersPaid: 0,
        grossMinor: 0,
        feeMinor: 0,
        netMinor: 0,
        currency: gig.ticketCurrency ?? "usd",
        truncated: false,
      };
    }
    const [paidOrders, refundedOrders] = await Promise.all(
      (["paid", "refunded"] as const).map((status) =>
        ctx.db
          .query("ticketOrders")
          .withIndex("by_gigId_and_status", (q) =>
            q.eq("gigId", gig._id).eq("status", status),
          )
          .take(1000),
      ),
    );
    const orders = [...paidOrders, ...refundedOrders];
    const grossMinor = orders.reduce(
      (sum, order) => sum + order.subtotalMinor,
      0,
    );
    const feeMinor = orders.reduce((sum, order) => sum + order.feeMinor, 0);
    // Fees are charged to fans; only the organizer's share of refunds reduces net.
    const refundedOrgMinor = orders.reduce(
      (sum, order) =>
        sum +
        (order.totalMinor === 0
          ? 0
          : Math.round(
              (order.refundedMinor * order.subtotalMinor) / order.totalMinor,
            )),
      0,
    );
    return {
      capacity: inventory.capacity,
      sold: inventory.sold,
      reserved: inventory.reserved,
      available: availableCount(inventory),
      ordersPaid: paidOrders.length,
      grossMinor,
      feeMinor,
      netMinor: grossMinor - refundedOrgMinor,
      currency:
        paidOrders[0]?.currency ??
        refundedOrders[0]?.currency ??
        gig.ticketCurrency ??
        "usd",
      truncated: paidOrders.length === 1000 || refundedOrders.length === 1000,
    };
  },
});
