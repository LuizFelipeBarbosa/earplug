/// <reference types="vite/client" />
import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal as generatedInternal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { stripeIdempotencyKey, stripeRequest } from "./lib/stripeClient";
import schema from "./schema";
import {
  applyRefundSucceeded,
  reconcileDashboardRefund,
  requestOrderRefund,
} from "./ticketRefunds";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ ticketRefunds: typeof import("./ticketRefunds") }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const HOUR_MS = 60 * 60 * 1000;
const stripeMock = vi.mocked(stripeRequest);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("TICKETS_ENABLED", "true");
  vi.stubEnv("PAYMENTS_ENABLED", "true");
  stripeMock.mockReset();
  let nextRefund = 0;
  stripeMock.mockImplementation(async (method, path) => {
    if (method === "POST" && path === "/v1/refunds") {
      return { id: `re_ticket_${++nextRefund}` };
    }
    throw new Error(`Unexpected Stripe request: ${method} ${path}`);
  });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupRefunds(orderOverrides: Partial<Doc<"ticketOrders">> = {}) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const buyerUserId = await ctx.db.insert("users", {
      clerkId: "ticket_buyer",
      name: "Ticket Buyer",
      email: "buyer@ticket.test",
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
      businessEmail: "billing@ticket.test",
      contactName: "Owner",
      stripeAccountId: "acct_ticket_organization",
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
      price: 5,
      startsAt: NOW + 24 * HOUR_MS,
      doorsTime: "19:00",
      flyKey: "xerox",
      lineup: [],
      genres: [],
      desc: "An evening of local music.",
      ticketing: "paid",
      cap: "100",
      goingCount: 0,
      ownerKind: "organization",
      createdByOrganization: organizationId,
    });
    const orderId = await ctx.db.insert("ticketOrders", {
      gigId,
      organizationId,
      buyerUserId,
      quantity: 2,
      unitPriceMinor: 500,
      unitFeeMinor: 50,
      subtotalMinor: 1000,
      feeMinor: 100,
      totalMinor: 1100,
      currency: "usd",
      status: "paid",
      reservedUntil: NOW,
      stripePaymentIntentId: "pi_ticket",
      stripeChargeId: "ch_ticket",
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
      ...orderOverrides,
    });
    for (const token of ["ticket_1", "ticket_2"]) {
      await ctx.db.insert("tickets", {
        orderId,
        gigId,
        organizationId,
        holderUserId: buyerUserId,
        token,
        status: "valid",
        createdAt: NOW,
      });
    }
    return { organizationId, detailsId, gigId, orderId };
  });
  return {
    t,
    ...ids,
    request: (amountMinor?: number) =>
      t.run(async (ctx) => {
        const order = (await ctx.db.get(ids.orderId))!;
        return await requestOrderRefund(ctx, order, "admin", { amountMinor });
      }),
    addRefund: (overrides: Partial<Doc<"ticketRefunds">> = {}) =>
      t.run((ctx) =>
        ctx.db.insert("ticketRefunds", {
          orderId: ids.orderId,
          gigId: ids.gigId,
          organizationId: ids.organizationId,
          amountMinor: 1100,
          currency: "usd",
          reason: "admin",
          status: "pending",
          attempt: 0,
          createdAt: NOW,
          updatedAt: NOW,
          ...overrides,
        }),
      ),
    state: () =>
      t.run(async (ctx) => ({
        order: (await ctx.db.get(ids.orderId))!,
        tickets: await ctx.db.query("tickets").collect(),
        refunds: await ctx.db.query("ticketRefunds").collect(),
        ledger: await ctx.db.query("ledgerEntries").collect(),
        jobs: await ctx.db.system.query("_scheduled_functions").collect(),
      })),
  };
}

describe("requestOrderRefund", () => {
  test("defaults to the remaining balance and deduplicates pending requests", async () => {
    const f = await setupRefunds({ refundedMinor: 200 });
    const refundId = await f.request();
    expect(await f.request(300)).toBe(refundId);
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        _id: refundId,
        orderId: f.orderId,
        gigId: f.gigId,
        organizationId: f.organizationId,
        amountMinor: 900,
        currency: "usd",
        reason: "admin",
        status: "pending",
        stripePaymentIntentId: "pi_ticket",
        attempt: 0,
        createdAt: NOW,
        updatedAt: NOW,
      },
    ]);
    expect(state.jobs).toMatchObject([
      {
        name: "ticketRefunds:executeRefund",
        args: [{ refundId, attempt: 0 }],
        scheduledTime: NOW,
      },
    ]);
  });

  test.each([0, -1, undefined])(
    "skips a nonpositive balance (%s)",
    async (amount) => {
      const f = await setupRefunds({ refundedMinor: 1100 });
      expect(await f.request(amount)).toBeNull();
      expect(await f.state()).toMatchObject({ refunds: [], jobs: [] });
    },
  );

  test.each([
    "reserved",
    "checkout_open",
    "expired",
    "cancelled",
    "refunded",
  ] as const)("rejects a %s order", async (status) => {
    const f = await setupRefunds({ status });
    await expect(f.request()).rejects.toThrow(
      "Only paid ticket orders can be refunded",
    );
    expect(await f.state()).toMatchObject({ refunds: [], jobs: [] });
  });

  test("requires a Stripe payment intent", async () => {
    const f = await setupRefunds({ stripePaymentIntentId: undefined });
    await expect(f.request()).rejects.toThrow(
      "Ticket order has no Stripe payment intent",
    );
  });

  test("does not confuse a completed refund with a pending request", async () => {
    const f = await setupRefunds({ refundedMinor: 200 });
    await f.addRefund({
      status: "succeeded",
      amountMinor: 200,
      stripeRefundId: "re_old",
    });
    const refundId = await f.request();
    const state = await f.state();
    expect(state.refunds).toHaveLength(2);
    expect(state.refunds[1]).toMatchObject({
      _id: refundId,
      status: "pending",
      amountMinor: 900,
      stripePaymentIntentId: "pi_ticket",
    });
    expect(state.jobs).toHaveLength(1);
  });
});

describe("loadRefundContext", () => {
  test("returns full documents and the organization's connected account", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund();
    const state = await f.state();
    expect(
      await f.t.query(internal.ticketRefunds.loadRefundContext, { refundId }),
    ).toEqual({
      refund: state.refunds[0],
      order: state.order,
      stripeAccountId: "acct_ticket_organization",
      paymentIntentId: "pi_ticket",
    });
  });

  test.each(["pi_ticket", undefined])(
    "uses the refund's intent when the order's intent is %s",
    async (stripePaymentIntentId) => {
      const f = await setupRefunds({ stripePaymentIntentId });
      const refundId = await f.addRefund({
        stripePaymentIntentId: "pi_late",
      });
      const state = await f.state();
      expect(
        await f.t.query(internal.ticketRefunds.loadRefundContext, { refundId }),
      ).toEqual({
        refund: state.refunds[0],
        order: state.order,
        stripeAccountId: "acct_ticket_organization",
        paymentIntentId: "pi_late",
      });
    },
  );

  test("rejects when neither the refund nor the order has a Stripe payment intent", async () => {
    const f = await setupRefunds({ stripePaymentIntentId: undefined });
    const refundId = await f.addRefund();
    await expect(
      f.t.query(internal.ticketRefunds.loadRefundContext, { refundId }),
    ).rejects.toThrow("Ticket order has no Stripe payment intent");
  });

  test.each(["refund", "order", "details", "account"] as const)(
    "rejects missing %s context",
    async (missing) => {
      const f = await setupRefunds();
      const refundId = await f.addRefund();
      await f.t.run(async (ctx) => {
        if (missing === "refund") await ctx.db.delete(refundId);
        if (missing === "order") await ctx.db.delete(f.orderId);
        if (missing === "details") await ctx.db.delete(f.detailsId);
        if (missing === "account")
          await ctx.db.patch(f.detailsId, { stripeAccountId: undefined });
      });
      await expect(
        f.t.query(internal.ticketRefunds.loadRefundContext, { refundId }),
      ).rejects.toThrow(
        missing === "refund"
          ? "Refund not found"
          : missing === "order"
            ? "Ticket order not found"
            : "Organization has no Stripe account",
      );
    },
  );
});

describe("ticket refund execution", () => {
  test("refunds the direct charge and application fee, settles tickets, and deduplicates success", async () => {
    const f = await setupRefunds();
    const refundId = (await f.request())!;
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/refunds",
      {
        payment_intent: "pi_ticket",
        amount: 1100,
        refund_application_fee: true,
        metadata: { ticketOrderId: f.orderId, refundId, reason: "admin" },
      },
      {
        stripeAccount: "acct_ticket_organization",
        idempotencyKey: stripeIdempotencyKey("ticket-refund", refundId),
      },
    );
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { status: "succeeded", stripeRefundId: "re_ticket_1" },
    ]);
    expect(state.order).toMatchObject({
      status: "refunded",
      refundedMinor: 1100,
      stripeRefundId: "re_ticket_1",
    });
    expect(state.tickets.map((row) => row.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger).toMatchObject([
      {
        kind: "ticket_refund",
        amountMinor: -1100,
        idempotencyKey: `ticket-refund:${refundId}`,
      },
      {
        kind: "ticket_fee",
        amountMinor: -100,
        idempotencyKey: `ticket-refund-fee:${refundId}`,
      },
    ]);
    for (const entry of state.ledger) {
      expect(entry).toMatchObject({
        fundsState: "refunded",
        organizationId: f.organizationId,
        ticketOrderId: f.orderId,
        currency: "usd",
        stripeRef: "refund:re_ticket_1",
        occurredAt: NOW,
      });
      expect(entry.stripeEventId).toBeUndefined();
    }

    await f.t.mutation(internal.ticketRefunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_ticket_1",
    });
    await f.t.run((ctx) =>
      applyRefundSucceeded(ctx, state.refunds[0], "re_ticket_1"),
    );
    await f.t.action(internal.ticketRefunds.executeRefund, {
      refundId,
      attempt: 0,
    });
    await f.t.mutation(internal.ticketRefunds.markRefundFailed, {
      refundId,
      attempt: 0,
      error: "Stale failure",
    });
    expect(await f.state()).toEqual(state);
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });

  test("a stray-intent refund on a paid order never touches the order or its tickets", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({
      reason: "late_payment",
      stripePaymentIntentId: "pi_stale",
      amountMinor: 500,
    });
    const before = await f.state();
    await f.t.mutation(internal.ticketRefunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_stale",
    });
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { _id: refundId, status: "succeeded", stripeRefundId: "re_stale" },
    ]);
    expect(state.order).toEqual(before.order);
    expect(state.order).toMatchObject({ status: "paid", refundedMinor: 0 });
    expect(state.order.stripeRefundId).toBeUndefined();
    expect(state.tickets).toEqual(before.tickets);
    expect(state.tickets.map((row) => row.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toHaveLength(1);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -500 },
    ]);
  });

  test("a partial refund preserves valid tickets and rounds the fee to minor units", async () => {
    const f = await setupRefunds();
    await f.request(333);
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    const state = await f.state();
    expect(state.order).toMatchObject({ status: "paid", refundedMinor: 333 });
    expect(state.tickets.map((row) => row.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -333, fundsState: "refunded" },
      { kind: "ticket_fee", amountMinor: -30, fundsState: "refunded" },
    ]);
  });

  test("refunding the remaining balance completes the order", async () => {
    const f = await setupRefunds({ refundedMinor: 500 });
    await f.request();
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    const state = await f.state();
    expect(state.order).toMatchObject({
      status: "refunded",
      refundedMinor: 1100,
    });
    expect(state.tickets.map((row) => row.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger.map((row) => row.amountMinor)).toEqual([-600, -55]);
  });

  test("a full refund also refunds used tickets", async () => {
    const f = await setupRefunds();
    const state = await f.state();
    await f.t.run((ctx) =>
      ctx.db.patch(state.tickets[0]._id, { status: "used" }),
    );
    const refundId = await f.addRefund();
    await f.t.mutation(internal.ticketRefunds.markRefundSucceeded, {
      refundId,
      stripeRefundId: "re_used",
    });
    expect((await f.state()).tickets.map((row) => row.status)).toEqual([
      "refunded",
      "refunded",
    ]);
  });

  test("preserves cancelled and already refunded tickets", async () => {
    const f = await setupRefunds();
    const state = await f.state();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(state.tickets[0]._id, { status: "cancelled" });
      await ctx.db.patch(state.tickets[1]._id, { status: "refunded" });
    });
    await f.request();
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect((await f.state()).tickets.map((row) => row.status)).toEqual([
      "cancelled",
      "refunded",
    ]);
  });

  test("disabled ticket sales never reach Stripe", async () => {
    const f = await setupRefunds();
    vi.stubEnv("TICKETS_ENABLED", "false");
    await f.request();
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(stripeMock).not.toHaveBeenCalled();
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { status: "failed", error: "Ticket sales are disabled" },
    ]);
    expect(state.ledger).toEqual([]);
    expect(state.jobs).toHaveLength(3);
    expect(state.jobs.every((job) => job.state.kind === "success")).toBe(true);
  });

  test("ignores a refund that is not pending", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({ status: "failed" });
    const before = await f.state();
    await f.t.action(internal.ticketRefunds.executeRefund, {
      refundId,
      attempt: 0,
    });
    expect(await f.state()).toEqual(before);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("retries a rejected request after one hour and succeeds with the same key", async () => {
    const f = await setupRefunds();
    stripeMock.mockRejectedValueOnce(new Error("Stripe unavailable"));
    vi.spyOn(console, "error").mockImplementation(() => {});
    const refundId = (await f.request())!;
    vi.advanceTimersByTime(0);
    await f.t.finishInProgressScheduledFunctions();
    const failed = await f.state();
    // The failed -> pending retry transition is in the same mutation, so the
    // retained error is visible while the row is already queued as pending.
    expect(failed.refunds).toMatchObject([
      { status: "pending", error: "Stripe unavailable" },
    ]);
    expect(
      failed.jobs.filter((job) => job.state.kind === "pending"),
    ).toMatchObject([
      {
        name: "ticketRefunds:executeRefund",
        args: [{ refundId, attempt: 1 }],
        scheduledTime: NOW + HOUR_MS,
      },
    ]);
    expect(stripeMock).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(HOUR_MS);
    await f.t.finishInProgressScheduledFunctions();
    expect((await f.state()).refunds).toMatchObject([{ status: "succeeded" }]);
    expect(stripeMock.mock.calls.map((call) => call[3])).toEqual(
      [0, 1].map(() => ({
        stripeAccount: "acct_ticket_organization",
        idempotencyKey: stripeIdempotencyKey("ticket-refund", refundId),
      })),
    );
  });

  test("stops after three consecutive failures and records non-Error failures", async () => {
    const f = await setupRefunds();
    stripeMock.mockRejectedValue("Stripe offline");
    const log = vi.spyOn(console, "error").mockImplementation(() => {});
    const refundId = (await f.request())!;
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        status: "failed",
        error: "Stripe offline",
        updatedAt: NOW + 2 * HOUR_MS,
      },
    ]);
    expect(state.jobs.map((job) => job.args)).toEqual(
      [0, 1, 2].map((attempt) => [{ refundId, attempt }]),
    );
    expect(state.jobs.every((job) => job.state.kind === "success")).toBe(true);
    expect(state.ledger).toEqual([]);
    expect(state.order).toMatchObject({ status: "paid", refundedMinor: 0 });
    expect(log).toHaveBeenCalledTimes(3);
    expect(stripeMock).toHaveBeenCalledTimes(3);
    expect(
      stripeMock.mock.calls.map((call) => call[3]?.idempotencyKey),
    ).toEqual(
      [0, 1, 2].map(() => stripeIdempotencyKey("ticket-refund", refundId)),
    );
  });

  test("markRefundFailed ignores a missing refund", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund();
    await f.t.run((ctx) => ctx.db.delete(refundId));
    await f.t.mutation(internal.ticketRefunds.markRefundFailed, {
      refundId,
      attempt: 0,
      error: "Missing",
    });
    expect(await f.state()).toMatchObject({ refunds: [], jobs: [] });
  });
});

describe("retryFailedTicketRefunds", () => {
  test("stops requeueing after five retries", async () => {
    const f = await setupRefunds();
    await f.addRefund({ status: "failed", retryCount: 5 });
    const before = await f.state();
    await f.t.mutation(internal.ticketRefunds.retryFailedTicketRefunds, {});
    const state = await f.state();
    expect(state).toEqual(before);
    expect(state.refunds).toMatchObject([{ status: "failed", retryCount: 5 }]);
    expect(state.jobs).toEqual([]);
  });

  test("requeues failed refunds only and schedules attempt zero", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({
      status: "failed",
      error: "Earlier failure",
    });
    await f.addRefund({ status: "succeeded", stripeRefundId: "re_old" });
    await f.addRefund({ status: "pending" });
    vi.setSystemTime(NOW + HOUR_MS);
    await f.t.mutation(internal.ticketRefunds.retryFailedTicketRefunds, {});
    const state = await f.state();
    expect(state.refunds.map((row) => row.status)).toEqual([
      "pending",
      "succeeded",
      "pending",
    ]);
    expect(state.refunds[0]).toMatchObject({ updatedAt: NOW + HOUR_MS });
    expect(state.jobs).toMatchObject([
      {
        name: "ticketRefunds:executeRefund",
        args: [{ refundId, attempt: 0 }],
        scheduledTime: NOW + HOUR_MS,
      },
    ]);
  });

  test("does not requeue when ticket sales are disabled", async () => {
    const f = await setupRefunds();
    await f.addRefund({ status: "failed" });
    const state = await f.state();
    vi.stubEnv("TICKETS_ENABLED", "false");
    await f.t.mutation(internal.ticketRefunds.retryFailedTicketRefunds, {});
    expect(await f.state()).toEqual(state);
  });

  test("limits each retry batch to 50 refunds", async () => {
    const f = await setupRefunds();
    for (let index = 0; index < 51; index++)
      await f.addRefund({ status: "failed" });
    await f.t.mutation(internal.ticketRefunds.retryFailedTicketRefunds, {});
    const state = await f.state();
    expect(
      state.refunds.filter((row) => row.status === "pending"),
    ).toHaveLength(50);
    expect(state.refunds.filter((row) => row.status === "failed")).toHaveLength(
      1,
    );
    expect(state.jobs).toHaveLength(50);
  });
});

describe("reconcileDashboardRefund", () => {
  test("settles only the delta and ignores repeated deliveries, including stale order snapshots", async () => {
    const f = await setupRefunds({ refundedMinor: 500 });
    await f.addRefund({
      amountMinor: 500,
      reason: "admin",
      status: "succeeded",
      stripeRefundId: "re_previous",
    });
    const originalOrder = (await f.state()).order;
    const charge = {
      id: "ch_ticket",
      amount_refunded: 1100,
      payment_intent: "pi_ticket",
      refunds: {
        data: [
          { id: "re_previous", amount: 500 },
          { id: "re_dashboard", amount: 600 },
        ],
      },
    };
    await f.t.run((ctx) =>
      reconcileDashboardRefund(ctx, originalOrder, charge, "evt_dashboard"),
    );
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { amountMinor: 500, status: "succeeded", stripeRefundId: "re_previous" },
      {
        amountMinor: 600,
        reason: "dashboard",
        status: "succeeded",
        stripeRefundId: "re_dashboard",
        stripePaymentIntentId: "pi_ticket",
        attempt: 0,
      },
    ]);
    expect(state.order).toMatchObject({
      status: "refunded",
      refundedMinor: 1100,
      stripeRefundId: "re_dashboard",
    });
    expect(state.tickets.map((row) => row.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger).toMatchObject([
      {
        kind: "ticket_refund",
        amountMinor: -600,
        fundsState: "refunded",
        stripeRef: "refund:re_dashboard",
        stripeEventId: "evt_dashboard",
      },
      {
        kind: "ticket_fee",
        amountMinor: -55,
        fundsState: "refunded",
        stripeRef: "refund:re_dashboard",
        stripeEventId: "evt_dashboard",
      },
    ]);
    await f.t.run((ctx) =>
      reconcileDashboardRefund(ctx, state.order, charge, "evt_replay"),
    );
    await f.t.run((ctx) =>
      reconcileDashboardRefund(ctx, originalOrder, charge, "evt_stale_replay"),
    );
    expect(await f.state()).toEqual(state);
    expect(state.jobs).toEqual([]);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("a stray-intent dashboard refund records its ledger entry without touching the paid order", async () => {
    const f = await setupRefunds();
    const order = (await f.state()).order;
    const charge = {
      id: "ch_stray",
      amount_refunded: 400,
      payment_intent: "pi_stray_charge",
      refunds: { data: [{ id: "re_stray", amount: 400 }] },
    };
    await f.t.run((ctx) =>
      reconcileDashboardRefund(ctx, order, charge, "evt_stray"),
    );
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        amountMinor: 400,
        reason: "dashboard",
        status: "succeeded",
        stripeRefundId: "re_stray",
        stripePaymentIntentId: "pi_stray_charge",
      },
    ]);
    expect(state.order).toMatchObject({ status: "paid", refundedMinor: 0 });
    expect(state.order).toEqual(order);
    expect(state.tickets.map((row) => row.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -400, fundsState: "refunded" },
    ]);
    expect(state.ledger).toHaveLength(1);
  });

  test("applies our pending refund by its Stripe metadata instead of adding a duplicate dashboard row", async () => {
    const f = await setupRefunds();
    const refundId = await f.addRefund({ amountMinor: 1100 });
    const order = (await f.state()).order;
    const charge = {
      id: "ch_ticket",
      amount_refunded: 1100,
      payment_intent: "pi_ticket",
      refunds: {
        data: [{ id: "re_ticket_1", amount: 1100, metadata: { refundId } }],
      },
    };
    await f.t.run((ctx) =>
      reconcileDashboardRefund(ctx, order, charge, "evt_webhook_first"),
    );
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        _id: refundId,
        status: "succeeded",
        stripeRefundId: "re_ticket_1",
        reason: "admin",
      },
    ]);
    expect(state.order).toMatchObject({ status: "refunded", refundedMinor: 1100 });
    expect(state.tickets.map((row) => row.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -1100 },
      { kind: "ticket_fee", amountMinor: -100 },
    ]);
    // The action's later success notification must be an idempotent no-op.
    await f.t.run((ctx) =>
      applyRefundSucceeded(ctx, state.refunds[0], "re_ticket_1"),
    );
    expect(await f.state()).toEqual(state);
  });

  test.each([undefined, { data: [] }])(
    "falls back to a charge-scoped id for refunds %j",
    async (refunds) => {
      const f = await setupRefunds();
      const order = (await f.state()).order;
      const charge = { id: "ch_fallback", amount_refunded: 333, refunds };
      await f.t.run((ctx) =>
        reconcileDashboardRefund(ctx, order, charge, "evt_fallback"),
      );
      const state = await f.state();
      expect(state.refunds).toMatchObject([
        {
          stripeRefundId: "ch_fallback:333",
          amountMinor: 333,
          status: "succeeded",
        },
      ]);
      expect(state.order).toMatchObject({ status: "paid", refundedMinor: 333 });
      expect(state.tickets.map((row) => row.status)).toEqual([
        "valid",
        "valid",
      ]);
      await f.t.run((ctx) =>
        reconcileDashboardRefund(ctx, order, charge, "evt_fallback_replay"),
      );
      expect(await f.state()).toEqual(state);
    },
  );

  test("successive partial refunds without a refunds list get distinct ids", async () => {
    const f = await setupRefunds();
    const order = (await f.state()).order;
    await f.t.run((ctx) =>
      reconcileDashboardRefund(
        ctx,
        order,
        { id: "ch_partial", amount_refunded: 200 },
        "evt_partial_1",
      ),
    );
    const afterFirst = (await f.state()).order;
    await f.t.run((ctx) =>
      reconcileDashboardRefund(
        ctx,
        afterFirst,
        { id: "ch_partial", amount_refunded: 500 },
        "evt_partial_2",
      ),
    );
    const state = await f.state();
    expect(state.refunds.map((row) => row.stripeRefundId)).toEqual([
      "ch_partial:200",
      "ch_partial:500",
    ]);
    expect(state.refunds.map((row) => row.amountMinor)).toEqual([200, 300]);
    expect(state.order).toMatchObject({ status: "paid", refundedMinor: 500 });
  });

  test("ignores an older cumulative refund balance", async () => {
    const f = await setupRefunds({ refundedMinor: 500 });
    await f.addRefund({
      amountMinor: 500,
      reason: "admin",
      status: "succeeded",
      stripeRefundId: "re_previous_2",
    });
    const state = await f.state();
    await f.t.run((ctx) =>
      reconcileDashboardRefund(
        ctx,
        state.order,
        { id: "ch_old", amount_refunded: 200 },
        "evt_old",
      ),
    );
    expect(await f.state()).toEqual(state);
  });
});
