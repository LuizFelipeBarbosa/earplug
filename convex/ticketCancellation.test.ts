/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { v } from "convex/values";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc, Id } from "./_generated/dataModel";
import { internalAction } from "./_generated/server";
import { cancelTicketSalesForGig } from "./lib/ticketCancellation";
import schema from "./schema";

const modules = {
  ...import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]),
  "./ticketRefunds.ts": async () => ({
    ...(await import("./ticketRefunds")),
    // Leave refunds pending so continuations must skip orders still marked paid.
    executeRefund: internalAction({
      args: { refundId: v.id("ticketRefunds"), attempt: v.number() },
      returns: v.null(),
      handler: async () => null,
    }),
  }),
};
const NOW = Date.parse("2026-09-05T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("APP_BASE_URL", "https://earplug.app");
  vi.stubEnv("RESEND_SEND_ENABLED", "false");
  vi.spyOn(console, "log").mockImplementation(() => {});
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupOrders(statuses: Doc<"ticketOrders">["status"][]) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const capacity = Math.max(20, statuses.length * 3);
    const buyerUserId = await ctx.db.insert("users", {
      clerkId: "ticket_buyer",
      name: "Buyer",
      email: "buyer@tickets.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Ticket Collective",
      slug: "ticket-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: buyerUserId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
    });
    const gigId = await ctx.db.insert("gigs", {
      title: "Friday at the Hall",
      venueId,
      price: 20,
      startsAt: NOW + 7 * 24 * 60 * 60_000,
      doorsTime: "7 PM",
      flyKey: "xerox",
      lineup: [],
      genres: [],
      desc: "Live music",
      ticketing: "paid",
      ticketPriceMinor: 2000,
      ticketCurrency: "usd",
      ticketCapacity: capacity,
      createdByOrganization: organizationId,
      lifecycle: "cancelled",
      cap: String(capacity),
      goingCount: 0,
    });
    const inventoryId = await ctx.db.insert("gigTicketInventory", {
      gigId,
      organizationId,
      capacity,
      reserved:
        3 *
        statuses.filter(
          (status) => status === "reserved" || status === "checkout_open",
        ).length,
      sold: 3 * statuses.filter((status) => status === "paid").length,
      updatedAt: NOW - 2000,
    });
    const orderIds: Id<"ticketOrders">[] = [];
    for (const [index, status] of statuses.entries()) {
      const orderBuyerId =
        index === 0
          ? buyerUserId
          : await ctx.db.insert("users", {
              clerkId: `ticket_buyer_${index}`,
              name: `Buyer ${index}`,
              email: `buyer${index}@tickets.test`,
              genres: [],
              attendedCount: 0,
            });
      orderIds.push(
        await ctx.db.insert("ticketOrders", {
          gigId,
          organizationId,
          buyerUserId: orderBuyerId,
          quantity: 3,
          unitPriceMinor: 2000,
          unitFeeMinor: 130,
          subtotalMinor: 6000,
          feeMinor: 390,
          totalMinor: 6390,
          currency: "usd",
          status,
          reservedUntil: NOW + 30 * 60_000,
          stripePaymentIntentId:
            status === "paid" ? `pi_ticket_${index}` : undefined,
          attempt: 1,
          refundedMinor: status === "refunded" ? 6390 : 0,
          createdAt: NOW - 2000,
          updatedAt: NOW - 2000,
        }),
      );
    }
    return { buyerUserId, gigId, inventoryId, orderIds };
  });
  const state = () =>
    t.run(async (ctx) => {
      const scheduled = await ctx.db.system
        .query("_scheduled_functions")
        .collect();
      return {
        orders: await ctx.db.query("ticketOrders").collect(),
        inventory: await ctx.db.get(ids.inventoryId),
        refunds: await ctx.db.query("ticketRefunds").collect(),
        scheduled,
        refundEmails: scheduled.filter(
          (job) =>
            job.name === "emails:send" && job.args[0].kind === "ticketRefunded",
        ),
        batches: scheduled.filter(
          (job) => job.name === "ticketCancellationJobs:processBatch",
        ),
      };
    });
  const cancel = () => t.run((ctx) => cancelTicketSalesForGig(ctx, ids.gigId));
  return { t, ...ids, state, cancel };
}

describe("cancelTicketSalesForGig", () => {
  test("continues refunding paid orders when one has no payment intent", async () => {
    const f = await setupOrders(["paid", "paid"]);
    const [brokenOrderId, validOrderId] = f.orderIds;
    await f.t.run((ctx) =>
      ctx.db.patch(brokenOrderId, { stripePaymentIntentId: undefined }),
    );
    const errorLog = vi.spyOn(console, "error").mockImplementation(() => {});

    await expect(f.cancel()).resolves.toEqual({
      refundsRequested: 1,
      holdsReleased: 0,
    });

    const { refunds, refundEmails } = await f.state();
    expect(refunds).toHaveLength(1);
    expect(refunds[0]).toMatchObject({
      orderId: validOrderId,
      stripePaymentIntentId: "pi_ticket_1",
      reason: "event_cancelled",
      status: "pending",
    });
    expect(refundEmails).toHaveLength(1);
    expect(refundEmails[0].args[0].to).toBe("buyer1@tickets.test");
    expect(errorLog).toHaveBeenCalledExactlyOnceWith(
      expect.stringContaining(brokenOrderId),
      expect.objectContaining({
        message: "Ticket order has no Stripe payment intent",
      }),
    );
  });

  test("requests a pending refund and emails the buyer for a paid order", async () => {
    const f = await setupOrders(["paid"]);
    expect(await f.cancel()).toEqual({ refundsRequested: 1, holdsReleased: 0 });

    const { refunds, refundEmails: emails, batches } = await f.state();
    expect(refunds).toHaveLength(1);
    expect(refunds[0]).toMatchObject({
      orderId: f.orderIds[0],
      gigId: f.gigId,
      amountMinor: 6390,
      currency: "usd",
      reason: "event_cancelled",
      status: "pending",
    });
    expect(batches).toEqual([]);
    expect(emails).toHaveLength(1);
    expect(emails[0].scheduledTime).toBe(NOW);
    expect(emails[0].args[0]).toMatchObject({
      to: "buyer@tickets.test",
      subject: "Refund on the way for Friday at the Hall",
    });
    expect(emails[0].args[0].text).toContain("63.90 USD");
    expect(emails[0].args[0].text.endsWith("\n\nhttps://earplug.app/")).toBe(
      true,
    );
  });

  test.each([100, 130, 230])(
    "processes 100 of %i paid orders inline and continues without duplicate refunds or emails",
    async (count) => {
      const f = await setupOrders(Array.from({ length: count }, () => "paid"));
      expect(await f.cancel()).toEqual({
        refundsRequested: 100,
        holdsReleased: 0,
      });

      const inline = await f.state();
      expect(inline.refunds).toHaveLength(100);
      expect(new Set(inline.refunds.map((refund) => refund.orderId)).size).toBe(
        100,
      );
      expect(inline.refundEmails).toHaveLength(100);
      expect(
        new Set(inline.refundEmails.map((job) => job.args[0].to)).size,
      ).toBe(100);
      expect(inline.batches).toEqual(
        count > 100
          ? [
              expect.objectContaining({
                args: [{ gigId: f.gigId }],
                scheduledTime: NOW,
                state: { kind: "pending" },
              }),
            ]
          : [],
      );

      await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());

      const completed = await f.state();
      expect(completed.orders.every((order) => order.status === "paid")).toBe(
        true,
      );
      expect(completed.refunds).toHaveLength(count);
      expect(
        new Set(completed.refunds.map((refund) => refund.orderId)),
      ).toEqual(new Set(f.orderIds));
      expect(
        completed.refunds.every(
          (refund) => refund.reason === "event_cancelled",
        ),
      ).toBe(true);
      expect(completed.refundEmails).toHaveLength(count);
      expect(
        new Set(completed.refundEmails.map((job) => job.args[0].to)).size,
      ).toBe(count);
      expect(completed.batches).toHaveLength(Math.ceil(count / 100) - 1);
      expect(
        completed.scheduled.every((job) => job.state.kind === "success"),
      ).toBe(true);
      expect(await f.cancel()).toEqual({
        refundsRequested: 0,
        holdsReleased: 0,
      });
      expect(await f.state()).toEqual(completed);
    },
  );

  test.each([0, 65, 130])(
    "releases 130 holds in batches with %i initially reserved orders",
    async (reservedCount) => {
      const f = await setupOrders([
        ...Array.from({ length: reservedCount }, () => "reserved" as const),
        ...Array.from(
          { length: 130 - reservedCount },
          () => "checkout_open" as const,
        ),
      ]);
      expect((await f.state()).inventory).toMatchObject({
        reserved: 390,
        sold: 0,
      });
      expect(await f.cancel()).toEqual({
        refundsRequested: 0,
        holdsReleased: 100,
      });

      const inline = await f.state();
      expect(
        inline.orders.filter((order) => order.status === "cancelled"),
      ).toHaveLength(100);
      expect(inline.inventory).toMatchObject({ reserved: 90, sold: 0 });
      expect(inline.batches).toHaveLength(1);
      expect(inline.batches[0].state.kind).toBe("pending");

      await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());

      const completed = await f.state();
      expect(completed.orders).toHaveLength(130);
      expect(
        completed.orders.every((order) => order.status === "cancelled"),
      ).toBe(true);
      expect(completed.inventory).toMatchObject({
        reserved: 0,
        sold: 0,
        updatedAt: NOW,
      });
      expect(completed.refunds).toEqual([]);
      expect(completed.refundEmails).toEqual([]);
      expect(completed.batches).toHaveLength(1);
      expect(completed.batches[0].state.kind).toBe("success");
    },
  );

  test.each([70, 100])(
    "shares the batch budget across %i paid orders and both hold statuses",
    async (paidCount) => {
      const f = await setupOrders([
        ...Array.from({ length: paidCount }, () => "paid" as const),
        ...Array.from({ length: 20 }, () => "reserved" as const),
        ...Array.from({ length: 20 }, () => "checkout_open" as const),
      ]);
      expect(await f.cancel()).toEqual({
        refundsRequested: paidCount,
        holdsReleased: 100 - paidCount,
      });
      const inline = await f.state();
      expect(inline.inventory?.reserved).toBe(3 * (paidCount - 60));
      expect(
        inline.orders.filter((order) => order.status === "cancelled"),
      ).toHaveLength(100 - paidCount);
      expect(inline.batches).toHaveLength(1);

      await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());

      const completed = await f.state();
      expect(completed.refunds).toHaveLength(paidCount);
      expect(completed.refundEmails).toHaveLength(paidCount);
      expect(
        completed.orders.filter((order) => order.status === "cancelled"),
      ).toHaveLength(40);
      expect(completed.inventory).toMatchObject({
        reserved: 0,
        sold: 3 * paidCount,
      });
      expect(
        completed.scheduled.every((job) => job.state.kind === "success"),
      ).toBe(true);
    },
  );

  test("cancels reserved and open checkout orders and releases both holds", async () => {
    const f = await setupOrders(["reserved", "checkout_open"]);
    expect((await f.state()).inventory).toMatchObject({ reserved: 6, sold: 0 });
    expect(await f.cancel()).toEqual({ refundsRequested: 0, holdsReleased: 2 });

    const { orders, inventory, refunds, scheduled } = await f.state();
    expect(orders.map((order) => order.status)).toEqual([
      "cancelled",
      "cancelled",
    ]);
    expect(inventory).toMatchObject({ reserved: 0, sold: 0, updatedAt: NOW });
    expect(refunds).toEqual([]);
    expect(scheduled).toEqual([]);
    expect(await f.cancel()).toEqual({ refundsRequested: 0, holdsReleased: 0 });
  });

  test("leaves expired, cancelled, and refunded orders untouched", async () => {
    const f = await setupOrders(["expired", "cancelled", "refunded"]);
    const before = await f.state();
    expect(await f.cancel()).toEqual({ refundsRequested: 0, holdsReleased: 0 });
    expect(await f.state()).toEqual(before);
  });

  test("does not count or email an order with nothing left to refund", async () => {
    const f = await setupOrders(["paid"]);
    await f.t.run((ctx) =>
      ctx.db.patch(f.orderIds[0], { refundedMinor: 6390 }),
    );
    const before = await f.state();
    expect(await f.cancel()).toEqual({ refundsRequested: 0, holdsReleased: 0 });
    expect(await f.state()).toEqual(before);
  });

  test("only processes orders for the cancelled gig, including continuations", async () => {
    const f = await setupOrders([
      ...Array.from({ length: 130 }, () => "paid" as const),
      "reserved",
      "checkout_open",
    ]);
    const other = await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...gig } = (await ctx.db.get(f.gigId))!;
      const gigId = await ctx.db.insert("gigs", {
        ...gig,
        title: "Another show",
        lifecycle: "published",
      });
      const inventoryId = await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId: gig.createdByOrganization!,
        capacity: 20,
        reserved: 6,
        sold: 3,
        updatedAt: NOW - 2000,
      });
      for (const orderId of [f.orderIds[0], ...f.orderIds.slice(-2)]) {
        const { _id, _creationTime, ...order } = (await ctx.db.get(orderId))!;
        await ctx.db.insert("ticketOrders", { ...order, gigId });
      }
      return { gigId, inventoryId };
    });
    const otherState = () =>
      f.t.run(async (ctx) => ({
        orders: await ctx.db
          .query("ticketOrders")
          .withIndex("by_gigId_and_status", (q) => q.eq("gigId", other.gigId))
          .collect(),
        inventory: await ctx.db.get(other.inventoryId),
      }));
    const before = await otherState();

    expect(await f.cancel()).toEqual({
      refundsRequested: 100,
      holdsReleased: 0,
    });
    expect(await otherState()).toEqual(before);

    await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());

    expect(await otherState()).toEqual(before);
    const completed = await f.state();
    expect(completed.refunds).toHaveLength(130);
    expect(completed.refunds.every((refund) => refund.gigId === f.gigId)).toBe(
      true,
    );
    expect(completed.refundEmails).toHaveLength(130);
    expect(completed.inventory).toMatchObject({ reserved: 0, sold: 390 });
    expect(
      completed.scheduled.every((job) => job.state.kind === "success"),
    ).toBe(true);
  });
});
