/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { orderTotals } from "./lib/ticketFees";
import {
  availableCount,
  commitInventory,
  ensureInventory,
  releaseInventory,
  reserveInventory,
} from "./lib/ticketInventory";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const DAY_MS = 24 * 60 * 60_000;
const FEE = { bps: 500, fixedMinor: 30 };
const UNIT_PRICE_MINOR = 2000;
const ACTORS = ["buyer", "otherBuyer", "owner", "door"] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("TICKETS_ENABLED", "true");
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupTickets() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `tickets_${actor}` });
  const fixture = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `tickets_${actor}`,
        name: actor,
        email: `${actor}@tickets.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Ticket Collective",
      slug: "ticket-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      ticketingFeeBps: FEE.bps,
      ticketingFeeFixedMinor: FEE.fixedMinor,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const privateDetailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "owner@tickets.test",
      contactName: "Owner",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: true,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: NOW,
    });
    for (const role of ["owner", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
    });
    const bandFields = {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const creatorBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Creator Band",
      slug: "creator-band",
    });
    const unrelatedBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Unrelated Band",
      slug: "unrelated-band",
    });
    const gigFields = {
      title: "Friday at the Hall",
      slug: "friday-at-the-hall",
      venueId,
      price: 20,
      startsAt: NOW + 7 * DAY_MS,
      doorsAt: NOW + 7 * DAY_MS - 60 * 60_000,
      doorsTime: "7 PM",
      flyKey: "xerox",
      lineup: [bandId],
      genres: ["Indie"],
      desc: "An evening of local music.",
      ticketing: "paid" as const,
      ticketPriceMinor: UNIT_PRICE_MINOR,
      ticketCurrency: "usd",
      ticketCapacity: 10,
      createdByOrganization: organizationId,
      createdByBand: creatorBandId,
      lifecycle: "published" as const,
      cap: "10",
      goingCount: 0,
    };
    const gigId = await ctx.db.insert("gigs", gigFields);
    const orderFields = {
      gigId,
      organizationId,
      buyerUserId: users.buyer,
      quantity: 1,
      unitPriceMinor: UNIT_PRICE_MINOR,
      ...orderTotals({
        unitPriceMinor: UNIT_PRICE_MINOR,
        quantity: 1,
        fee: FEE,
      }),
      currency: "usd",
      status: "reserved" as const,
      reservedUntil: NOW + 30 * 60_000,
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    };
    return {
      users,
      organizationId,
      privateDetailsId,
      venueId,
      bandId,
      creatorBandId,
      unrelatedBandId,
      gigId,
      gigFields,
      orderFields,
    };
  });

  async function reservationState(orderId: Id<"ticketOrders">) {
    return await t.run(async (ctx) => ({
      order: await ctx.db.get(orderId),
      inventory: await ctx.db
        .query("gigTicketInventory")
        .withIndex("by_gigId", (q) => q.eq("gigId", fixture.gigId))
        .unique(),
    }));
  }
  return { t, as, ...fixture, reservationState };
}

describe("ticket reservations", () => {
  test("reserve snapshots totals, reserves inventory, and schedules release", async () => {
    const { t, as, gigId, users, organizationId, reservationState } =
      await setupTickets();
    const result = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 3,
    });
    expect(result).toEqual({
      orderId: expect.any(String),
      quantity: 3,
      unitPriceMinor: UNIT_PRICE_MINOR,
      ...orderTotals({
        unitPriceMinor: UNIT_PRICE_MINOR,
        quantity: 3,
        fee: FEE,
      }),
      currency: "usd",
      reservedUntil: NOW + 30 * 60_000,
    });
    const state = await reservationState(result.orderId);
    expect(state.inventory).toMatchObject({
      capacity: 10,
      sold: 0,
      reserved: 3,
    });
    expect(state.order).toMatchObject({
      gigId,
      organizationId,
      buyerUserId: users.buyer,
      status: "reserved",
      quantity: 3,
      totalMinor: result.totalMinor,
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(state.order?.stripeCheckoutSessionId).toBeUndefined();
    expect(state.order?.paidAt).toBeUndefined();

    await t.finishAllScheduledFunctions(() => vi.runAllTimers());
    const expired = await reservationState(result.orderId);
    expect(expired.order?.status).toBe("expired");
    expect(expired.inventory).toMatchObject({ reserved: 0, sold: 0 });
  });

  test.each([undefined, "false", "invalid"])(
    "refuses sales when TICKETS_ENABLED is %s",
    async (value) => {
      vi.stubEnv("TICKETS_ENABLED", value);
      const { as, gigId } = await setupTickets();
      await expect(
        as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
      ).rejects.toThrow("Ticket sales are not open yet");
    },
  );

  test.each([11, 0, -1, 1.5])(
    "refuses invalid quantity %s",
    async (quantity) => {
      const { as, gigId } = await setupTickets();
      await expect(
        as("buyer").mutation(api.tickets.reserve, { gigId, quantity }),
      ).rejects.toThrow("Choose between 1 and 10 tickets");
    },
  );

  test.each(["rsvp", "external"] as const)(
    "refuses %s ticketing",
    async (ticketing) => {
      const { t, as, gigId } = await setupTickets();
      await t.run((ctx) => ctx.db.patch(gigId, { ticketing }));
      await expect(
        as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
      ).rejects.toThrow("This event is not selling tickets");
    },
  );

  test("refuses an organizer whose Stripe charges are disabled", async () => {
    const { t, as, gigId, privateDetailsId } = await setupTickets();
    await t.run((ctx) =>
      ctx.db.patch(privateDetailsId, { stripeChargesEnabled: false }),
    );
    await expect(
      as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).rejects.toThrow("This organizer is not ready to sell tickets yet");
  });

  test("refuses a suspended organizer", async () => {
    const { t, as, gigId, organizationId } = await setupTickets();
    await t.run((ctx) => ctx.db.patch(organizationId, { status: "suspended" }));
    await expect(
      as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).rejects.toThrow("This organizer is not ready to sell tickets yet");
  });

  test.each(["cancelled", "unpublished", "deleted"] as const)(
    "refuses a %s gig",
    async (lifecycle) => {
      const { t, as, gigId } = await setupTickets();
      await t.run((ctx) => ctx.db.patch(gigId, { lifecycle }));
      await expect(
        as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
      ).rejects.toThrow("This event is not selling tickets");
    },
  );

  test("accepts the legacy absent lifecycle as published", async () => {
    const { t, as, gigId } = await setupTickets();
    await t.run((ctx) => ctx.db.patch(gigId, { lifecycle: undefined }));
    await expect(
      as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).resolves.toMatchObject({ quantity: 1 });
  });

  test.each([
    "ticketPriceMinor",
    "ticketCurrency",
    "ticketCapacity",
    "createdByOrganization",
  ] as const)("refuses a paid gig missing %s", async (field) => {
    const { t, as, gigId } = await setupTickets();
    await t.run((ctx) => ctx.db.patch(gigId, { [field]: undefined }));
    await expect(
      as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).rejects.toThrow("This event is not selling tickets");
  });

  test.each(["reserved", "checkout_open"] as const)(
    "refuses a second reservation while an order is %s",
    async (status) => {
      const { t, as, gigId } = await setupTickets();
      const first = await as("buyer").mutation(api.tickets.reserve, {
        gigId,
        quantity: 1,
      });
      await t.run((ctx) => ctx.db.patch(first.orderId, { status }));
      await expect(
        as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
      ).rejects.toThrow("Finish or release your current ticket order first");
    },
  );

  test("prevents overselling and rolls back the rejected order", async () => {
    const { t, as, gigId, organizationId, reservationState } =
      await setupTickets();
    await t.run(async (ctx) => {
      await ctx.db.patch(gigId, { ticketCapacity: 4 });
      await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId,
        capacity: 4,
        sold: 1,
        reserved: 0,
        updatedAt: NOW,
      });
    });
    const first = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 3,
    });
    await expect(
      as("otherBuyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).rejects.toThrow("Not enough tickets left");
    expect((await reservationState(first.orderId)).inventory).toMatchObject({
      capacity: 4,
      sold: 1,
      reserved: 3,
    });
    const orders = await t.run((ctx) => ctx.db.query("ticketOrders").take(10));
    expect(orders.map((order) => order._id)).toEqual([first.orderId]);
  });

  test.each([
    ["static-bloom", "bandId"],
    ["creator-band", "creatorBandId"],
    ["unrelated-band", undefined],
    ["missing-band", undefined],
    ["", undefined],
  ] as const)(
    "resolves referral slug %s only for associated bands",
    async (slug, key) => {
      const fixture = await setupTickets();
      const result = await fixture.as("buyer").mutation(api.tickets.reserve, {
        gigId: fixture.gigId,
        quantity: 1,
        referralBandSlug: slug,
      });
      const { order } = await fixture.reservationState(result.orderId);
      expect(order?.referralBandId).toBe(key ? fixture[key] : undefined);
    },
  );

  test("releaseReservation ignores stale calls and releases exactly once after gig changes", async () => {
    const { t, as, gigId, reservationState } = await setupTickets();
    const order = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 2,
    });
    await as("otherBuyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 1,
    });
    await t.mutation(internal.tickets.releaseReservation, {
      orderId: order.orderId,
      expectedReservedUntil: order.reservedUntil - 1,
    });
    const unchanged = await reservationState(order.orderId);
    expect(unchanged.order?.status).toBe("reserved");
    expect(unchanged.inventory?.reserved).toBe(3);

    await t.run((ctx) => ctx.db.patch(gigId, { ticketing: "rsvp" }));
    for (let attempt = 0; attempt < 2; attempt++) {
      await t.mutation(internal.tickets.releaseReservation, {
        orderId: order.orderId,
        expectedReservedUntil: order.reservedUntil,
      });
      const expired = await reservationState(order.orderId);
      expect(expired.order?.status).toBe("expired");
      expect(expired.inventory?.reserved).toBe(1);
    }
  });

  test("releaseReservation leaves checkout_open orders untouched", async () => {
    const { t, as, gigId, reservationState } = await setupTickets();
    const order = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 2,
    });
    await t.run((ctx) =>
      ctx.db.patch(order.orderId, { status: "checkout_open" }),
    );
    await t.mutation(internal.tickets.releaseReservation, {
      orderId: order.orderId,
      expectedReservedUntil: order.reservedUntil,
    });
    const state = await reservationState(order.orderId);
    expect(state.order?.status).toBe("checkout_open");
    expect(state.inventory?.reserved).toBe(2);
  });

  test("cancelReservation releases inventory and rejects an already cancelled order", async () => {
    const { as, gigId, reservationState } = await setupTickets();
    const { orderId } = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 2,
    });
    await as("buyer").mutation(api.tickets.cancelReservation, { orderId });
    const cancelled = await reservationState(orderId);
    expect(cancelled.order?.status).toBe("cancelled");
    expect(cancelled.inventory?.reserved).toBe(0);
    await expect(
      as("buyer").mutation(api.tickets.cancelReservation, { orderId }),
    ).rejects.toThrow("This ticket order can no longer be cancelled");
    await expect(
      as("buyer").mutation(api.tickets.reserve, { gigId, quantity: 1 }),
    ).resolves.toMatchObject({ quantity: 1 });
  });

  test("cancelReservation enforces buyer ownership and checkout state", async () => {
    const { t, as, gigId, reservationState } = await setupTickets();
    const { orderId } = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 2,
    });
    await expect(
      as("otherBuyer").mutation(api.tickets.cancelReservation, { orderId }),
    ).rejects.toThrow("Not permitted for this ticket order");
    await t.run((ctx) => ctx.db.patch(orderId, { status: "checkout_open" }));
    await expect(
      as("buyer").mutation(api.tickets.cancelReservation, { orderId }),
    ).rejects.toThrow("Close the payment page first");
    expect((await reservationState(orderId)).inventory?.reserved).toBe(2);
  });

  test("expiry rolls back if the inventory row is missing", async () => {
    const { t, as, gigId, reservationState } = await setupTickets();
    const order = await as("buyer").mutation(api.tickets.reserve, {
      gigId,
      quantity: 1,
    });
    const { inventory } = await reservationState(order.orderId);
    await t.run((ctx) => ctx.db.delete(inventory!._id));
    await expect(
      t.mutation(internal.tickets.releaseReservation, {
        orderId: order.orderId,
        expectedReservedUntil: order.reservedUntil,
      }),
    ).rejects.toThrow("Ticket inventory not found");
    expect((await reservationState(order.orderId)).order?.status).toBe(
      "reserved",
    );
  });

  test("expireStaleReservations expires at most 100 strictly overdue reserved orders", async () => {
    const { t, gigId, organizationId, orderFields } = await setupTickets();
    const inventoryId = await t.run(async (ctx) => {
      for (let i = 0; i < 101; i++) {
        await ctx.db.insert("ticketOrders", {
          ...orderFields,
          reservedUntil: NOW - 1,
        });
      }
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        reservedUntil: NOW,
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        reservedUntil: NOW + 1,
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "checkout_open",
        reservedUntil: NOW - 1,
      });
      return await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId,
        capacity: 200,
        sold: 0,
        reserved: 104,
        updatedAt: NOW,
      });
    });
    await t.mutation(internal.tickets.expireStaleReservations, {});
    const firstBatch = await t.run((ctx) =>
      ctx.db.query("ticketOrders").take(200),
    );
    expect(
      firstBatch.filter((order) => order.status === "expired"),
    ).toHaveLength(100);
    expect((await t.run((ctx) => ctx.db.get(inventoryId)))?.reserved).toBe(4);

    await t.mutation(internal.tickets.expireStaleReservations, {});
    const secondBatch = await t.run((ctx) =>
      ctx.db.query("ticketOrders").take(200),
    );
    expect(
      secondBatch.filter((order) => order.status === "expired"),
    ).toHaveLength(101);
    expect(
      secondBatch.filter((order) => order.status === "reserved"),
    ).toHaveLength(2);
    expect(
      secondBatch.filter((order) => order.status === "checkout_open"),
    ).toHaveLength(1);
    expect((await t.run((ctx) => ctx.db.get(inventoryId)))?.reserved).toBe(3);
  });
});

describe("ticket reads", () => {
  test("myTickets sorts upcoming ascending then past descending and drops missing references", async () => {
    const { t, as, users, organizationId, gigFields, orderFields } =
      await setupTickets();
    const startsAtValues = [
      NOW - 2 * DAY_MS,
      NOW + 2 * DAY_MS,
      NOW,
      NOW - DAY_MS,
      NOW + DAY_MS,
    ];
    await t.run(async (ctx) => {
      await ctx.db.insert("clock", { key: "feedCutoff", value: NOW });
      for (const [index, startsAt] of startsAtValues.entries()) {
        const gigId = await ctx.db.insert("gigs", { ...gigFields, startsAt });
        const orderId = await ctx.db.insert("ticketOrders", {
          ...orderFields,
          gigId,
          status: "paid",
        });
        await ctx.db.insert("tickets", {
          orderId,
          gigId,
          organizationId,
          holderUserId: users.buyer,
          token: `earplug:ticket:v2:sort-${index}`,
          status: "valid",
          createdAt: NOW + index,
        });
      }
      for (const missing of ["gig", "venue"] as const) {
        const venueId = await ctx.db.insert("venues", {
          name: "Missing Venue",
          area: "Oakland",
          addr: "",
          distSF: "",
          distOak: "",
          lat: 0,
          lng: 0,
        });
        const gigId = await ctx.db.insert("gigs", { ...gigFields, venueId });
        const orderId = await ctx.db.insert("ticketOrders", {
          ...orderFields,
          gigId,
          status: "paid",
        });
        await ctx.db.insert("tickets", {
          orderId,
          gigId,
          organizationId,
          holderUserId: users.buyer,
          token: `earplug:ticket:v2:missing-${missing}`,
          status: "valid",
          createdAt: NOW,
        });
        await ctx.db.delete(missing === "gig" ? gigId : venueId);
      }
    });
    const tickets = await as("buyer").query(api.tickets.myTickets, {});
    expect(tickets.map((ticket) => ticket.gig.startsAt)).toEqual([
      NOW,
      NOW + DAY_MS,
      NOW + 2 * DAY_MS,
      NOW - DAY_MS,
      NOW - 2 * DAY_MS,
    ]);
    expect(tickets[0].gig).toMatchObject({
      title: gigFields.title,
      slug: gigFields.slug,
      doorsAt: gigFields.doorsAt,
      venueName: "Neighborhood Hall",
      lifecycle: "published",
    });
    expect(await as("otherBuyer").query(api.tickets.myTickets, {})).toEqual([]);
  });

  test("get exposes ticket summaries only to their holder and tolerates missing references", async () => {
    const { t, as, users, gigId, venueId, organizationId, orderFields } =
      await setupTickets();
    const ticketId = await t.run(async (ctx) => {
      const orderId = await ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "paid",
      });
      return await ctx.db.insert("tickets", {
        orderId,
        gigId,
        organizationId,
        holderUserId: users.buyer,
        token: "earplug:ticket:v2:holder",
        status: "valid",
        createdAt: NOW,
      });
    });
    expect(
      await as("buyer").query(api.tickets.get, { ticketId }),
    ).toMatchObject({
      _id: ticketId,
      gig: { _id: gigId, venueName: "Neighborhood Hall" },
    });
    expect(
      await as("otherBuyer").query(api.tickets.get, { ticketId }),
    ).toBeNull();
    expect(await t.query(api.tickets.get, { ticketId })).toBeNull();
    await t.run((ctx) => ctx.db.delete(venueId));
    expect(await as("buyer").query(api.tickets.get, { ticketId })).toBeNull();
    await t.run((ctx) => ctx.db.delete(gigId));
    expect(await as("buyer").query(api.tickets.get, { ticketId })).toBeNull();
    await t.run((ctx) => ctx.db.delete(ticketId));
    expect(await as("buyer").query(api.tickets.get, { ticketId })).toBeNull();
  });

  test("orderStatus is scoped to the session's buyer", async () => {
    const { t, as, gigId, orderFields } = await setupTickets();
    const sessionId = "cs_test_ticket_order";
    const orderId = await t.run((ctx) =>
      ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "checkout_open",
        stripeCheckoutSessionId: sessionId,
      }),
    );
    expect(
      await as("buyer").query(api.tickets.orderStatus, { sessionId }),
    ).toEqual({
      orderId,
      gigId,
      gigSlug: "friday-at-the-hall",
      status: "checkout_open",
      quantity: 1,
      totalMinor: 2130,
      currency: "usd",
    });
    expect(
      await as("otherBuyer").query(api.tickets.orderStatus, { sessionId }),
    ).toBeNull();
    expect(await t.query(api.tickets.orderStatus, { sessionId })).toBeNull();
    expect(
      await as("buyer").query(api.tickets.orderStatus, {
        sessionId: "missing",
      }),
    ).toBeNull();
  });

  test("salesForGig math: two paid orders, one partially refunded; refunded-status orders excluded", async () => {
    const { t, as, gigId, organizationId, orderFields } = await setupTickets();
    await t.run(async (ctx) => {
      await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId,
        capacity: 10,
        sold: 3,
        reserved: 2,
        updatedAt: NOW,
      });
      await ctx.db.insert("ticketOrders", { ...orderFields, status: "paid" });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        quantity: 2,
        ...orderTotals({
          unitPriceMinor: UNIT_PRICE_MINOR,
          quantity: 2,
          fee: FEE,
        }),
        status: "paid",
        refundedMinor: 500,
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "refunded",
        refundedMinor: orderFields.totalMinor,
      });
    });
    expect(await as("owner").query(api.tickets.salesForGig, { gigId })).toEqual(
      {
        capacity: 10,
        sold: 3,
        reserved: 2,
        available: 5,
        ordersPaid: 2,
        grossMinor: 5500,
        feeMinor: 390,
        netMinor: 5110,
        currency: "usd",
      },
    );
  });

  test.each(["door", "buyer"] as const)(
    "salesForGig rejects the %s role",
    async (actor) => {
      const { as, gigId } = await setupTickets();
      await expect(
        as(actor).query(api.tickets.salesForGig, { gigId }),
      ).rejects.toThrow("Not permitted for this organization");
    },
  );

  test("salesForGig returns zero totals without inventory", async () => {
    const { t, as, gigId } = await setupTickets();
    await t.run((ctx) => ctx.db.patch(gigId, { ticketCurrency: undefined }));
    expect(await as("owner").query(api.tickets.salesForGig, { gigId })).toEqual(
      {
        capacity: 0,
        sold: 0,
        reserved: 0,
        available: 0,
        ordersPaid: 0,
        grossMinor: 0,
        feeMinor: 0,
        netMinor: 0,
        currency: "usd",
      },
    );
  });
});

describe("ticket inventory helpers", () => {
  test("helpers reread inventory snapshots and clamp released reservations at zero", async () => {
    const { t, gigId } = await setupTickets();
    await t.run(async (ctx) => {
      const gig = (await ctx.db.get(gigId))!;
      const snapshot = await ensureInventory(ctx, gig);
      expect(await ensureInventory(ctx, gig)).toEqual(snapshot);
      await reserveInventory(ctx, snapshot, 3);
      await reserveInventory(ctx, snapshot, 2);
      await releaseInventory(ctx, snapshot, 1);
      await commitInventory(ctx, snapshot, 2);
      const current = (await ctx.db.get(snapshot._id))!;
      expect(current).toMatchObject({ reserved: 2, sold: 2 });
      expect(availableCount(current)).toBe(6);
      await releaseInventory(ctx, snapshot, 10);
      expect((await ctx.db.get(snapshot._id))?.reserved).toBe(0);
      await commitInventory(ctx, snapshot, 1);
      expect(await ctx.db.get(snapshot._id)).toMatchObject({
        reserved: 0,
        sold: 3,
      });
    });
  });

  test.each(["ticketing", "ticketCapacity", "createdByOrganization"] as const)(
    "ensureInventory refuses an existing row when the gig's %s no longer permits sales",
    async (field) => {
      const { t, gigId } = await setupTickets();
      await t.run(async (ctx) => {
        const gig = (await ctx.db.get(gigId))!;
        await ensureInventory(ctx, gig);
        const patch: Partial<Doc<"gigs">> =
          field === "ticketing"
            ? { ticketing: "rsvp" }
            : { [field]: undefined };
        await ctx.db.patch(gigId, patch);
      });
      await expect(
        t.run(async (ctx) => {
          await ensureInventory(ctx, (await ctx.db.get(gigId))!);
        }),
      ).rejects.toThrow("This event is not selling tickets");
    },
  );

  test.each([
    ["reserve", reserveInventory],
    ["release", releaseInventory],
    ["commit", commitInventory],
  ] as const)(
    "%s throws if the inventory was deleted",
    async (_, operation) => {
      const { t, gigId } = await setupTickets();
      const snapshot = await t.run(async (ctx) => {
        const inventory = await ensureInventory(
          ctx,
          (await ctx.db.get(gigId))!,
        );
        await ctx.db.delete(inventory._id);
        return inventory;
      });
      await expect(t.run((ctx) => operation(ctx, snapshot, 1))).rejects.toThrow(
        "Ticket inventory not found",
      );
    },
  );
});
