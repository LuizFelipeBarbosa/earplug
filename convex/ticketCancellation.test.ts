/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc, Id } from "./_generated/dataModel";
import { cancelTicketSalesForGig } from "./lib/ticketCancellation";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("APP_BASE_URL", "https://earplug.app");
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupOrders(statuses: Doc<"ticketOrders">["status"][]) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
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
      ticketCapacity: 20,
      createdByOrganization: organizationId,
      lifecycle: "cancelled",
      cap: "20",
      goingCount: 0,
    });
    const inventoryId = await ctx.db.insert("gigTicketInventory", {
      gigId,
      organizationId,
      capacity: 20,
      reserved:
        3 *
        statuses.filter(
          (status) => status === "reserved" || status === "checkout_open",
        ).length,
      sold: 3 * statuses.filter((status) => status === "paid").length,
      updatedAt: NOW - 2000,
    });
    const orderIds: Id<"ticketOrders">[] = [];
    for (const status of statuses) {
      orderIds.push(
        await ctx.db.insert("ticketOrders", {
          gigId,
          organizationId,
          buyerUserId,
          quantity: 3,
          unitPriceMinor: 2000,
          unitFeeMinor: 130,
          subtotalMinor: 6000,
          feeMinor: 390,
          totalMinor: 6390,
          currency: "usd",
          status,
          reservedUntil: NOW + 30 * 60_000,
          stripePaymentIntentId: status === "paid" ? "pi_ticket" : undefined,
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
    t.run(async (ctx) => ({
      orders: await ctx.db.query("ticketOrders").collect(),
      inventory: await ctx.db.get(ids.inventoryId),
      refunds: await ctx.db.query("ticketRefunds").collect(),
      scheduled: await ctx.db.system.query("_scheduled_functions").collect(),
    }));
  const cancel = () => t.run((ctx) => cancelTicketSalesForGig(ctx, ids.gigId));
  return { t, ...ids, state, cancel };
}

describe("cancelTicketSalesForGig", () => {
  test("requests a pending refund and emails the buyer for a paid order", async () => {
    const f = await setupOrders(["paid"]);
    expect(await f.cancel()).toEqual({ refundsRequested: 1, holdsReleased: 0 });

    const { refunds, scheduled } = await f.state();
    expect(refunds).toHaveLength(1);
    expect(refunds[0]).toMatchObject({
      orderId: f.orderIds[0],
      gigId: f.gigId,
      amountMinor: 6390,
      currency: "usd",
      reason: "event_cancelled",
      status: "pending",
    });
    const emails = scheduled.filter(
      (job) =>
        job.name === "emails:send" && job.args[0].kind === "ticketRefunded",
    );
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

  test("only processes orders for the cancelled gig", async () => {
    const f = await setupOrders(["paid", "reserved", "checkout_open"]);
    const otherGigId = await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...gig } = (await ctx.db.get(f.gigId))!;
      return await ctx.db.insert("gigs", { ...gig, title: "Another show" });
    });
    const before = await f.state();
    expect(
      await f.t.run((ctx) => cancelTicketSalesForGig(ctx, otherGigId)),
    ).toEqual({ refundsRequested: 0, holdsReleased: 0 });
    expect(await f.state()).toEqual(before);
  });
});
