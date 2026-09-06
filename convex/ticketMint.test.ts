/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc } from "./_generated/dataModel";
import { appBaseUrl } from "./lib/env";
import { expireOrder, mintTickets } from "./lib/ticketMint";
import { TICKET_TOKEN_PREFIX } from "./lib/ticketStatus";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const PAYMENT = {
  stripePaymentIntentId: "pi_ticket",
  stripeChargeId: "ch_ticket",
  stripeEventId: "evt_ticket",
  paidAt: NOW - 1000,
};

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

async function setupOrder(
  status: Doc<"ticketOrders">["status"] = "checkout_open",
) {
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
      lifecycle: "published",
      cap: "20",
      goingCount: 0,
    });
    const inventoryId = await ctx.db.insert("gigTicketInventory", {
      gigId,
      organizationId,
      capacity: 20,
      reserved: 5,
      sold: 4,
      updatedAt: NOW - 2000,
    });
    const orderId = await ctx.db.insert("ticketOrders", {
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
      stripeCheckoutSessionId: "cs_ticket",
      checkoutExpiresAt: NOW + 30 * 60_000,
      attempt: 1,
      refundedMinor: 0,
      createdAt: NOW - 2000,
      updatedAt: NOW - 2000,
    });
    return { buyerUserId, organizationId, gigId, inventoryId, orderId };
  });
  const state = () =>
    t.run(async (ctx) => ({
      order: (await ctx.db.get(ids.orderId))!,
      inventory: (await ctx.db.get(ids.inventoryId))!,
      tickets: await ctx.db.query("tickets").collect(),
      ledger: await ctx.db.query("ledgerEntries").collect(),
    }));
  const mint = (payment: Parameters<typeof mintTickets>[2] = PAYMENT) =>
    t.run(async (ctx) =>
      mintTickets(ctx, (await ctx.db.get(ids.orderId))!, payment),
    );
  const expire = (reason: Parameters<typeof expireOrder>[2]) =>
    t.run(async (ctx) =>
      expireOrder(ctx, (await ctx.db.get(ids.orderId))!, reason),
    );
  return { t, ...ids, state, mint, expire };
}

describe("mintTickets", () => {
  test("mints unique tickets, commits inventory, and records the sale and fee", async () => {
    const f = await setupOrder();
    const ids = await f.mint();
    const { order, inventory, tickets, ledger } = await f.state();
    expect(ids).toHaveLength(order.quantity);
    expect(tickets.map((ticket) => ticket._id)).toEqual(ids);
    expect(new Set(tickets.map((ticket) => ticket.token)).size).toBe(3);
    for (const ticket of tickets) {
      expect(ticket.token.startsWith(TICKET_TOKEN_PREFIX)).toBe(true);
      expect(ticket.token.slice(TICKET_TOKEN_PREFIX.length)).toMatch(
        /^[0-9a-f]{64}$/,
      );
      expect(ticket).toMatchObject({
        orderId: order._id,
        gigId: order.gigId,
        organizationId: order.organizationId,
        holderUserId: order.buyerUserId,
        status: "valid",
        createdAt: NOW,
      });
    }
    expect(order).toMatchObject({
      status: "paid",
      paidAt: PAYMENT.paidAt,
      stripePaymentIntentId: PAYMENT.stripePaymentIntentId,
      stripeChargeId: PAYMENT.stripeChargeId,
      updatedAt: NOW,
    });
    expect(inventory).toMatchObject({ reserved: 2, sold: 7, capacity: 20 });
    expect(ledger).toHaveLength(2);
    for (const entry of ledger) {
      expect(entry).toMatchObject({
        organizationId: order.organizationId,
        ticketOrderId: order._id,
        currency: "usd",
        fundsState: "pending",
        stripeRef: "charge:ch_ticket",
        stripeEventId: PAYMENT.stripeEventId,
        occurredAt: PAYMENT.paidAt,
      });
    }
    expect(ledger).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "ticket_sale",
          amountMinor: 6390,
          idempotencyKey: `ticket-sale:${order._id}`,
        }),
        expect.objectContaining({
          kind: "ticket_fee",
          amountMinor: 390,
          idempotencyKey: `ticket-fee:${order._id}`,
        }),
      ]),
    );
  });

  test("returns the same tickets on replay without changing any rows", async () => {
    const f = await setupOrder();
    const ids = await f.mint();
    const before = await f.state();
    vi.setSystemTime(NOW + 60_000);
    expect(await f.mint({ paidAt: NOW, stripeChargeId: "ch_replay" })).toEqual(
      ids,
    );
    const after = await f.state();
    expect(after.tickets).toHaveLength(before.tickets.length);
    expect(after.ledger).toHaveLength(before.ledger.length);
    expect(after).toEqual(before);
  });

  test("emails one receipt to the buyer and does not resend it on replay", async () => {
    const f = await setupOrder();
    const ticketIds = await f.mint();
    const receiptEmails = () =>
      f.t.run(async (ctx) =>
        (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
          (job) =>
            job.name === "emails:send" && job.args[0].kind === "ticketReceipt",
        ),
      );
    const emails = await receiptEmails();
    expect(emails).toHaveLength(1);
    expect(emails[0].scheduledTime).toBe(NOW);
    expect(emails[0].args[0]).toMatchObject({
      to: "buyer@tickets.test",
      subject: "Your tickets for Friday at the Hall",
    });
    expect(emails[0].args[0].text).toContain("3 tickets");
    expect(emails[0].args[0].text).toContain("63.90 USD");
    expect(
      emails[0].args[0].text.endsWith(`\n\n${appBaseUrl()}/t/${ticketIds[0]}`),
    ).toBe(true);

    expect(await f.mint()).toEqual(ticketIds);
    expect(await receiptEmails()).toEqual(emails);
  });

  test("uses the intent as the ledger reference when the charge is absent", async () => {
    const f = await setupOrder();
    await f.mint({ stripePaymentIntentId: "pi_only", paidAt: NOW });
    const { order, ledger } = await f.state();
    expect(order).not.toHaveProperty("stripeChargeId");
    expect(ledger.map((entry) => entry.stripeRef)).toEqual([
      "charge:pi_only",
      "charge:pi_only",
    ]);
  });

  test("preserves stored payment identifiers when omitted from the payment", async () => {
    const f = await setupOrder();
    await f.t.run((ctx) =>
      ctx.db.patch(f.orderId, {
        stripePaymentIntentId: "pi_existing",
        stripeChargeId: "ch_existing",
      }),
    );
    await f.mint({ paidAt: NOW });
    expect((await f.state()).order).toMatchObject({
      stripePaymentIntentId: "pi_existing",
      stripeChargeId: "ch_existing",
    });
  });

  test.each(["reserved", "expired", "cancelled", "refunded"] as const)(
    "enforces the existing transition table for a %s order",
    async (status) => {
      const f = await setupOrder(status);
      const before = await f.state();
      await expect(f.mint()).rejects.toThrow(
        `Invalid ticket order transition: ${status} → paid`,
      );
      expect(await f.state()).toEqual(before);
    },
  );

  test("retries token collisions and fails atomically after three collisions", async () => {
    const f = await setupOrder();
    const random = vi.spyOn(crypto, "getRandomValues");
    random.mockImplementation((buffer) => {
      new Uint8Array(
        buffer!.buffer,
        buffer!.byteOffset,
        buffer!.byteLength,
      ).fill(0);
      return buffer;
    });
    await f.t.run((ctx) => ctx.db.patch(f.orderId, { quantity: 1 }));
    await f.mint();
    expect(random).toHaveBeenCalledTimes(1);
    const collisionToken = (await f.state()).tickets[0].token;
    expect(collisionToken).toBe(TICKET_TOKEN_PREFIX + "00".repeat(32));

    // Keep the existing token to force all three attempts for another ticket.
    await f.t.run((ctx) =>
      ctx.db.patch(f.orderId, { status: "checkout_open" }),
    );
    const before = await f.state();
    random.mockClear();
    await expect(f.mint()).rejects.toThrow(
      "Could not create a unique ticket token after 3 attempts",
    );
    expect(random).toHaveBeenCalledTimes(3);
    expect(await f.state()).toEqual(before);

    random.mockRestore();
    const retry = vi.spyOn(crypto, "getRandomValues");
    retry.mockImplementationOnce((buffer) => {
      new Uint8Array(
        buffer!.buffer,
        buffer!.byteOffset,
        buffer!.byteLength,
      ).fill(0);
      return buffer;
    });
    await f.mint();
    expect(retry).toHaveBeenCalledTimes(2);
    const { tickets, ledger } = await f.state();
    expect(tickets).toHaveLength(2);
    expect(tickets[1].token).not.toBe(collisionToken);
    expect(ledger).toHaveLength(2);
  });

  test("rolls back minting if inventory is missing", async () => {
    const f = await setupOrder();
    await f.t.run((ctx) => ctx.db.delete(f.inventoryId));
    const before = await f.state();
    await expect(f.mint()).rejects.toThrow("Ticket inventory not found");
    expect(await f.state()).toEqual(before);
  });
});

describe("expireOrder", () => {
  test.each([
    ["reserved", "session_expired", "expired"],
    ["checkout_open", "cancelled", "cancelled"],
  ] as const)("moves %s to %s exactly once", async (status, reason, target) => {
    const f = await setupOrder(status);
    const before = await f.state();
    await f.expire(reason);
    const after = await f.state();
    expect(after.order).toEqual({
      ...before.order,
      status: target,
      updatedAt: NOW,
    });
    expect(after.inventory).toEqual({
      ...before.inventory,
      reserved: 2,
      updatedAt: NOW,
    });
    vi.setSystemTime(NOW + 60_000);
    await f.expire(reason);
    expect(await f.state()).toEqual(after);
  });

  test.each(["expired", "cancelled", "paid", "refunded"] as const)(
    "does not touch a terminal %s order",
    async (status) => {
      const f = await setupOrder(status);
      const before = await f.state();
      await f.expire("session_expired");
      await f.expire("cancelled");
      expect(await f.state()).toEqual(before);
    },
  );

  test("rolls back expiry if inventory is missing", async () => {
    const f = await setupOrder();
    await f.t.run((ctx) => ctx.db.delete(f.inventoryId));
    const before = await f.state();
    await expect(f.expire("cancelled")).rejects.toThrow(
      "Ticket inventory not found",
    );
    expect(await f.state()).toEqual(before);
  });
});
