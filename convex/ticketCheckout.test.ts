/// <reference types="vite/client" />
import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  api as generatedApi,
  internal as generatedInternal,
} from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { StripeApiError, stripeRequest } from "./lib/stripeClient";
import schema from "./schema";
import type * as ticketCheckout from "./ticketCheckout";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const api = generatedApi as typeof generatedApi &
  FilterApi<
    ApiFromModules<{ ticketCheckout: typeof ticketCheckout }>,
    FunctionReference<"query" | "mutation" | "action", "public">
  >;
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ ticketCheckout: typeof ticketCheckout }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const CHECKOUT_TTL_MS = 30 * 60_000;
const ACCOUNT_ID = "acct_ticket_organizer";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("TICKETS_ENABLED", "true");
  vi.stubEnv("PAYMENTS_ENABLED", "true");
  vi.stubEnv("APP_BASE_URL", "https://earplug.test");
  let nextSession = 0;
  vi.mocked(stripeRequest).mockReset();
  vi.mocked(stripeRequest).mockImplementation(async (_method, path) => {
    if (path.endsWith("/expire")) {
      return { id: path.split("/").at(-2), status: "expired" };
    }
    if (path === "/v1/checkout/sessions") {
      const id = `cs_ticket_${++nextSession}`;
      return {
        id,
        url: `https://checkout.stripe.com/c/pay/${id}`,
        payment_intent: `pi_ticket_${nextSession}`,
      };
    }
    throw new Error(`Unexpected Stripe request: ${path}`);
  });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupCheckout() {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const buyerUserId = await ctx.db.insert("users", {
      clerkId: "checkout_buyer",
      name: "Buyer",
      email: "buyer@tickets.test",
      genres: [],
      attendedCount: 0,
    });
    await ctx.db.insert("users", {
      clerkId: "checkout_stranger",
      name: "Stranger",
      email: "stranger@tickets.test",
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
    const detailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "organizer@tickets.test",
      contactName: "Organizer",
      stripeAccountId: ACCOUNT_ID,
      stripeChargesEnabled: true,
      stripePayoutsEnabled: true,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
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
      reserved: 2,
      sold: 0,
      updatedAt: NOW,
    });
    const orderId = await ctx.db.insert("ticketOrders", {
      gigId,
      organizationId,
      buyerUserId,
      quantity: 2,
      unitPriceMinor: 2000,
      unitFeeMinor: 130,
      subtotalMinor: 4000,
      feeMinor: 260,
      totalMinor: 4260,
      currency: "usd",
      status: "reserved",
      reservedUntil: NOW + 5 * 60_000,
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const clockId = await ctx.db.insert("clock", {
      key: "feedCutoff",
      value: NOW,
    });
    return { orderId, gigId, inventoryId, organizationId, detailsId, clockId };
  });
  const buyer = t.withIdentity({ subject: "checkout_buyer" });
  const stranger = t.withIdentity({ subject: "checkout_stranger" });
  const state = () =>
    t.run(async (ctx) => ({
      order: (await ctx.db.get(ids.orderId))!,
      inventory: (await ctx.db.get(ids.inventoryId))!,
    }));
  const start = () =>
    buyer.action(api.ticketCheckout.startCheckout, { orderId: ids.orderId });
  const cancel = () =>
    buyer.action(api.ticketCheckout.cancelOrder, { orderId: ids.orderId });
  return { t, buyer, stranger, ...ids, state, start, cancel };
}

describe("startCheckout", () => {
  test("creates a direct charge with the fee, ticket price, and first attempt key", async () => {
    const f = await setupCheckout();
    vi.setSystemTime(NOW + 1234);
    const checkoutExpiresAt = NOW + 1000 + CHECKOUT_TTL_MS;
    expect(await f.start()).toEqual({
      url: "https://checkout.stripe.com/c/pay/cs_ticket_1",
      sessionId: "cs_ticket_1",
    });
    expect(stripeRequest).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/checkout/sessions",
      {
        mode: "payment",
        payment_method_types: ["card"],
        customer_email: "buyer@tickets.test",
        client_reference_id: f.orderId,
        line_items: [
          {
            quantity: 2,
            price_data: {
              currency: "usd",
              unit_amount: 2130,
              product_data: { name: "Friday at the Hall · Ticket" },
            },
          },
        ],
        payment_intent_data: {
          application_fee_amount: 260,
          metadata: { ticketOrderId: f.orderId },
        },
        metadata: { ticketOrderId: f.orderId, gigId: f.gigId, quantity: 2 },
        success_url:
          "https://earplug.test/tickets/return?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: `https://earplug.test/tickets/cancel?order=${f.orderId}`,
        expires_at: checkoutExpiresAt / 1000,
      },
      {
        stripeAccount: ACCOUNT_ID,
        idempotencyKey: `ticket-checkout:${f.orderId}:1`,
      },
    );
    const { order, inventory } = await f.state();
    expect(order).toMatchObject({
      status: "checkout_open",
      attempt: 1,
      stripeCheckoutSessionId: "cs_ticket_1",
      stripePaymentIntentId: "pi_ticket_1",
      checkoutExpiresAt,
      reservedUntil: checkoutExpiresAt,
    });
    expect(inventory).toMatchObject({ reserved: 2, sold: 0 });
  });

  test("retry expires the old session and preserves the hold until the replacement opens", async () => {
    const f = await setupCheckout();
    await f.start();
    const before = await f.state();
    expect(before.order.reservedUntil).toBe(NOW + CHECKOUT_TTL_MS);
    vi.setSystemTime(NOW + 60_000);
    const fakeStripe = vi.mocked(stripeRequest).getMockImplementation()!;
    vi.mocked(stripeRequest).mockImplementation(
      async (method, path, params, options) => {
        if (path === "/v1/checkout/sessions") {
          const reopened = await f.state();
          expect(reopened.order.status).toBe("reserved");
          expect(reopened.order.attempt).toBe(2);
          expect(reopened.order.reservedUntil).toBe(before.order.reservedUntil);
          expect(reopened.inventory).toEqual(before.inventory);
        }
        return fakeStripe(method, path, params, options);
      },
    );
    expect((await f.start()).sessionId).toBe("cs_ticket_2");
    expect(stripeRequest).toHaveBeenNthCalledWith(
      2,
      "POST",
      "/v1/checkout/sessions/cs_ticket_1/expire",
      undefined,
      { stripeAccount: ACCOUNT_ID },
    );
    expect(stripeRequest).toHaveBeenNthCalledWith(
      3,
      "POST",
      "/v1/checkout/sessions",
      expect.any(Object),
      {
        stripeAccount: ACCOUNT_ID,
        idempotencyKey: `ticket-checkout:${f.orderId}:2`,
      },
    );
    expect((await f.state()).order).toMatchObject({
      status: "checkout_open",
      attempt: 2,
      stripeCheckoutSessionId: "cs_ticket_2",
      reservedUntil: NOW + 60_000 + CHECKOUT_TTL_MS,
    });
  });

  test("a failed create retains its attempt and retry uses a fresh key", async () => {
    const f = await setupCheckout();
    vi.mocked(stripeRequest).mockRejectedValueOnce(new Error("network blip"));
    await expect(f.start()).rejects.toThrow("network blip");
    expect((await f.state()).order).toMatchObject({
      status: "reserved",
      attempt: 1,
    });
    await f.start();
    expect(stripeRequest).toHaveBeenNthCalledWith(
      2,
      "POST",
      "/v1/checkout/sessions",
      expect.any(Object),
      {
        stripeAccount: ACCOUNT_ID,
        idempotencyKey: `ticket-checkout:${f.orderId}:2`,
      },
    );
  });

  test.each([undefined, "false"])(
    "rejects the feature flag value %s",
    async (value) => {
      const f = await setupCheckout();
      vi.stubEnv("TICKETS_ENABLED", value);
      await expect(f.start()).rejects.toThrow("Ticket sales are not open yet");
      expect(stripeRequest).not.toHaveBeenCalled();
    },
  );

  test("rejects a different buyer or an unauthenticated caller", async () => {
    const f = await setupCheckout();
    await expect(
      f.stranger.action(api.ticketCheckout.startCheckout, {
        orderId: f.orderId,
      }),
    ).rejects.toThrow("Not permitted for this ticket order");
    await expect(
      f.t.action(api.ticketCheckout.startCheckout, { orderId: f.orderId }),
    ).rejects.toThrow("Not signed in");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test("checks hold expiry against feedCutoff with a strict boundary", async () => {
    const f = await setupCheckout();
    const { order } = await f.state();
    await f.t.run((ctx) =>
      ctx.db.patch(f.clockId, { value: order.reservedUntil }),
    );
    await expect(
      f.buyer.query(internal.ticketCheckout.loadCheckoutContext, {
        orderId: f.orderId,
      }),
    ).resolves.toMatchObject({ order: { status: "reserved" } });
    await f.t.run((ctx) =>
      ctx.db.patch(f.clockId, { value: order.reservedUntil + 1 }),
    );
    await expect(f.start()).rejects.toThrow("Your ticket hold has expired");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test.each(["charges disabled", "account missing", "details missing"])(
    "rejects an organizer with %s",
    async (condition) => {
      const f = await setupCheckout();
      await f.t.run(async (ctx) => {
        if (condition === "details missing") await ctx.db.delete(f.detailsId);
        else
          await ctx.db.patch(
            f.detailsId,
            condition === "account missing"
              ? { stripeAccountId: undefined }
              : { stripeChargesEnabled: false },
          );
      });
      await expect(f.start()).rejects.toThrow(
        "This organizer is not ready to sell tickets yet",
      );
      expect(stripeRequest).not.toHaveBeenCalled();
    },
  );

  test.each(["paid", "expired", "cancelled", "refunded"] as const)(
    "rejects a %s order before contacting Stripe",
    async (status) => {
      const f = await setupCheckout();
      await f.t.run((ctx) => ctx.db.patch(f.orderId, { status }));
      await expect(f.start()).rejects.toThrow(
        "This ticket order can no longer be checked out",
      );
      expect(stripeRequest).not.toHaveBeenCalled();
    },
  );

  test.each([null, undefined])(
    "omits the payment intent field for a %s intent",
    async (intent) => {
      const f = await setupCheckout();
      vi.mocked(stripeRequest).mockResolvedValueOnce({
        id: "cs_no_intent",
        url: "https://checkout.stripe.com/c/pay/cs_no_intent",
        payment_intent: intent,
      });
      await f.start();
      const { order } = await f.state();
      expect(order.status).toBe("checkout_open");
      expect(order.stripePaymentIntentId).toBeUndefined();
      expect(order).not.toHaveProperty("stripePaymentIntentId");
    },
  );
});

describe.each(["startCheckout", "cancelOrder"] as const)(
  "%s session expiry",
  (operation) => {
    test.each([
      { message: "Session is already expired" },
      {
        message: "Cannot expire this session",
        code: "checkout_session_already_expired",
      },
    ])("continues after '$message'", async ({ message, code }) => {
      const f = await setupCheckout();
      await f.start();
      vi.mocked(stripeRequest).mockClear();
      vi.mocked(stripeRequest).mockRejectedValueOnce(
        new StripeApiError(message, { status: 400, code }),
      );
      await f.buyer.action(api.ticketCheckout[operation], {
        orderId: f.orderId,
      });
      expect(stripeRequest).toHaveBeenNthCalledWith(
        1,
        "POST",
        "/v1/checkout/sessions/cs_ticket_1/expire",
        undefined,
        { stripeAccount: ACCOUNT_ID },
      );
      expect((await f.state()).order.status).toBe(
        operation === "startCheckout" ? "checkout_open" : "cancelled",
      );
    });

    test.each([
      { message: "Session is already completed" },
      { message: "Session status is complete" },
      { message: "Session is already paid" },
      {
        message: "Payment is already paid",
        code: "checkout_session_already_paid",
      },
      {
        message: "Cannot expire this Checkout Session",
        code: "session_already_completed",
      },
    ])("preserves the order after '$message'", async ({ message, code }) => {
      const f = await setupCheckout();
      await f.start();
      const before = await f.state();
      vi.mocked(stripeRequest).mockClear();
      vi.mocked(stripeRequest).mockRejectedValueOnce(
        new StripeApiError(message, { status: 400, code }),
      );
      await expect(
        f.buyer.action(api.ticketCheckout[operation], { orderId: f.orderId }),
      ).rejects.toThrow("This payment is already being confirmed");
      expect(stripeRequest).toHaveBeenCalledTimes(1);
      expect(await f.state()).toEqual(before);
    });

    test.each([
      new StripeApiError("The API key is expired", { status: 401 }),
      new Error("Session is already expired"),
    ])(
      "propagates unrelated errors without changing the order: %s",
      async (error) => {
        const f = await setupCheckout();
        await f.start();
        const before = await f.state();
        vi.mocked(stripeRequest).mockClear();
        vi.mocked(stripeRequest).mockRejectedValueOnce(error);
        await expect(
          f.buyer.action(api.ticketCheckout[operation], { orderId: f.orderId }),
        ).rejects.toThrow(error.message);
        expect(stripeRequest).toHaveBeenCalledTimes(1);
        expect(await f.state()).toEqual(before);
      },
    );
  },
);

describe("checkout mutations", () => {
  test("markCheckoutOpen extends the hold and replay does not rewrite the order", async () => {
    const f = await setupCheckout();
    const args = {
      orderId: f.orderId,
      sessionId: "cs_open",
      checkoutExpiresAt: NOW + CHECKOUT_TTL_MS,
      attempt: 0,
    };
    await f.t.mutation(internal.ticketCheckout.markCheckoutOpen, args);
    const before = await f.state();
    expect(before.order.reservedUntil).toBe(args.checkoutExpiresAt);
    vi.setSystemTime(NOW + 1000);
    await f.t.mutation(internal.ticketCheckout.markCheckoutOpen, {
      ...args,
      attempt: 999,
    });
    expect(await f.state()).toEqual(before);
  });

  test("attempt guards reject stale writers without changing the order", async () => {
    const f = await setupCheckout();
    await expect(
      f.t.mutation(internal.ticketCheckout.reserveCheckoutAttempt, {
        orderId: f.orderId,
        expectedAttempt: 0,
      }),
    ).resolves.toBe(1);
    const before = await f.state();
    await expect(
      f.t.mutation(internal.ticketCheckout.reserveCheckoutAttempt, {
        orderId: f.orderId,
        expectedAttempt: 0,
      }),
    ).rejects.toThrow("Ticket order attempt changed elsewhere");
    await expect(
      f.t.mutation(internal.ticketCheckout.markCheckoutOpen, {
        orderId: f.orderId,
        sessionId: "cs_stale",
        checkoutExpiresAt: NOW + CHECKOUT_TTL_MS,
        attempt: 0,
      }),
    ).rejects.toThrow("Ticket order attempt changed elsewhere");
    expect(await f.state()).toEqual(before);
  });

  test("reopenReservation preserves every field except status and updatedAt", async () => {
    const f = await setupCheckout();
    await f.start();
    const before = await f.state();
    vi.setSystemTime(NOW + 1000);
    await f.t.mutation(internal.ticketCheckout.reopenReservation, {
      orderId: f.orderId,
      sessionId: "cs_ticket_1",
    });
    expect(await f.state()).toEqual({
      ...before,
      order: { ...before.order, status: "reserved", updatedAt: NOW + 1000 },
    });
  });

  test("reopening ignores replaced sessions and concurrently paid orders", async () => {
    const f = await setupCheckout();
    await f.start();
    const before = await f.state();
    await f.t.mutation(internal.ticketCheckout.reopenReservation, {
      orderId: f.orderId,
      sessionId: "cs_old",
    });
    expect(await f.state()).toEqual(before);
    await f.t.run((ctx) => ctx.db.patch(f.orderId, { status: "paid" }));
    const paid = await f.state();
    await f.t.mutation(internal.ticketCheckout.reopenReservation, {
      orderId: f.orderId,
      sessionId: "cs_ticket_1",
    });
    expect(await f.state()).toEqual(paid);
  });

  test("a payment completing during Stripe expiry prevents a replacement checkout", async () => {
    const f = await setupCheckout();
    await f.start();
    vi.mocked(stripeRequest).mockClear();
    vi.mocked(stripeRequest).mockImplementationOnce(async () => {
      await f.t.run((ctx) => ctx.db.patch(f.orderId, { status: "paid" }));
      return { id: "cs_ticket_1", status: "expired" };
    });
    await expect(f.start()).rejects.toThrow(
      "This ticket order can no longer be checked out",
    );
    expect(stripeRequest).toHaveBeenCalledTimes(1);
    expect((await f.state()).order).toMatchObject({
      status: "paid",
      attempt: 1,
    });
  });

  test("markSessionExpired ignores unknown sessions and closes an open session once", async () => {
    const f = await setupCheckout();
    await f.start();
    const before = await f.state();
    await expect(
      f.t.mutation(internal.ticketCheckout.markSessionExpired, {
        sessionId: "cs_unknown",
      }),
    ).resolves.toBeNull();
    expect(await f.state()).toEqual(before);
    await f.t.mutation(internal.ticketCheckout.markSessionExpired, {
      sessionId: "cs_ticket_1",
    });
    const expired = await f.state();
    expect(expired.order.status).toBe("expired");
    expect(expired.inventory.reserved).toBe(0);
    vi.setSystemTime(NOW + 1000);
    await f.t.mutation(internal.ticketCheckout.markSessionExpired, {
      sessionId: "cs_ticket_1",
    });
    expect(await f.state()).toEqual(expired);
  });
});

describe("cancelOrder", () => {
  test("expires the connected account's session before cancelling", async () => {
    const f = await setupCheckout();
    await f.start();
    vi.mocked(stripeRequest).mockClear();
    vi.mocked(stripeRequest).mockImplementationOnce(async () => {
      expect((await f.state()).order.status).toBe("checkout_open");
      return { id: "cs_ticket_1", status: "expired" };
    });
    expect(await f.cancel()).toBeNull();
    expect(stripeRequest).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/checkout/sessions/cs_ticket_1/expire",
      undefined,
      { stripeAccount: ACCOUNT_ID },
    );
    const { order, inventory } = await f.state();
    expect(order.status).toBe("cancelled");
    expect(inventory.reserved).toBe(0);
  });

  test("cancels a reserved order without a Stripe call", async () => {
    const f = await setupCheckout();
    expect(await f.cancel()).toBeNull();
    expect(stripeRequest).not.toHaveBeenCalled();
    expect((await f.state()).order.status).toBe("cancelled");
    expect((await f.state()).inventory.reserved).toBe(0);
  });

  test.each(["paid", "expired", "cancelled", "refunded"] as const)(
    "ignores a terminal %s order",
    async (status) => {
      const f = await setupCheckout();
      await f.t.run((ctx) => ctx.db.patch(f.orderId, { status }));
      const before = await f.state();
      expect(await f.cancel()).toBeNull();
      expect(stripeRequest).not.toHaveBeenCalled();
      expect(await f.state()).toEqual(before);
    },
  );

  test("rejects a different buyer before contacting Stripe", async () => {
    const f = await setupCheckout();
    await f.start();
    vi.mocked(stripeRequest).mockClear();
    await expect(
      f.stranger.action(api.ticketCheckout.cancelOrder, { orderId: f.orderId }),
    ).rejects.toThrow("Not permitted for this ticket order");
    expect(stripeRequest).not.toHaveBeenCalled();
  });

  test("can cancel after the hold lapses and the organizer disables charges", async () => {
    const f = await setupCheckout();
    await f.start();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.detailsId, { stripeChargesEnabled: false });
      await ctx.db.patch(f.clockId, { value: NOW + CHECKOUT_TTL_MS + 1 });
    });
    expect(await f.cancel()).toBeNull();
    expect((await f.state()).order.status).toBe("cancelled");
  });

  test("preserves an order paid concurrently while the session was expiring", async () => {
    const f = await setupCheckout();
    await f.start();
    vi.mocked(stripeRequest).mockImplementationOnce(async () => {
      await f.t.run((ctx) => ctx.db.patch(f.orderId, { status: "paid" }));
      return { id: "cs_ticket_1", status: "expired" };
    });
    expect(await f.cancel()).toBeNull();
    expect((await f.state()).order.status).toBe("paid");
  });
});

test("sweepStaleCheckouts filters session expiry before taking at most 100 orders", async () => {
  const f = await setupCheckout();
  const cutoff = NOW - 10 * 60_000;
  const { order } = await f.state();
  const { _id, _creationTime, ...fields } = order;
  const keep = await f.t.run(async (ctx) => {
    const retained = [];
    const cases: Partial<Doc<"ticketOrders">>[] = [
      { checkoutExpiresAt: cutoff },
      { checkoutExpiresAt: cutoff + 1 },
      {},
      { checkoutExpiresAt: cutoff - 1, status: "reserved" },
      { checkoutExpiresAt: cutoff - 1, status: "paid" },
    ];
    for (const patch of cases) {
      retained.push(
        await ctx.db.insert("ticketOrders", {
          ...fields,
          status: "checkout_open",
          reservedUntil: NOW - 60 * 60_000,
          ...patch,
        }),
      );
    }
    for (let index = 0; index < 101; index++) {
      await ctx.db.insert("ticketOrders", {
        ...fields,
        status: "checkout_open",
        checkoutExpiresAt: cutoff - 1,
        // The sweep must use checkoutExpiresAt even when reservedUntil is later.
        reservedUntil: NOW + CHECKOUT_TTL_MS,
      });
    }
    await ctx.db.patch(f.inventoryId, { capacity: 300, reserved: 214 });
    return retained;
  });
  const before = await f.t.run(async (ctx) =>
    Promise.all(keep.map((id) => ctx.db.get(id))),
  );
  await f.t.mutation(internal.ticketCheckout.sweepStaleCheckouts, {});
  const first = await f.t.run((ctx) => ctx.db.query("ticketOrders").collect());
  expect(first.filter((row) => row.status === "expired")).toHaveLength(100);
  expect((await f.state()).inventory.reserved).toBe(14);
  await f.t.mutation(internal.ticketCheckout.sweepStaleCheckouts, {});
  const second = await f.t.run((ctx) => ctx.db.query("ticketOrders").collect());
  expect(second.filter((row) => row.status === "expired")).toHaveLength(101);
  expect((await f.state()).inventory.reserved).toBe(12);
  expect(
    await f.t.run(async (ctx) => Promise.all(keep.map((id) => ctx.db.get(id)))),
  ).toEqual(before);
  expect(stripeRequest).not.toHaveBeenCalled();
});
