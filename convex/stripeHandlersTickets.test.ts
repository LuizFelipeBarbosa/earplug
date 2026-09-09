/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { feeSnapshot } from "./lib/fees";
import { stripeRequest } from "./lib/stripeClient";
import schema from "./schema";
import { isTicketSession } from "./stripeHandlers/tickets";
import type { StripeEvent } from "./stripeWebhook";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-05T12:00:00Z");
const ACCOUNT_ID = "acct_ticket_organization";
const BAND_ACCOUNT_ID = "acct_ticket_band";
const SESSION_ID = "cs_ticket";
const stripeMock = vi.mocked(stripeRequest);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  stripeMock.mockReset();
  stripeMock.mockResolvedValue({ id: "re_late_ticket" });
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupTickets(
  orderOverrides: Partial<Doc<"ticketOrders">> = {},
  sellerKind: "organization" | "band" = "organization",
) {
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
      stripeAccountId: ACCOUNT_ID,
      stripeChargesEnabled: true,
      stripePayoutsEnabled: true,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: NOW,
    });
    const bandId =
      sellerKind === "band"
        ? await ctx.db.insert("bands", {
            name: "Static Bloom",
            slug: "static-bloom",
            genres: [],
            area: "Oakland",
            colorHex: "#7B8FFF",
            initials: "SB",
            followerCount: 0,
            pastShows: [],
          })
        : undefined;
    const payoutAccountId = bandId
      ? await ctx.db.insert("bandPayoutAccounts", {
          bandId,
          stripeAccountId: BAND_ACCOUNT_ID,
          chargesEnabled: true,
          cardPaymentsStatus: "active",
          payoutsEnabled: true,
          detailsSubmitted: true,
          requirementsDue: [],
          updatedAt: NOW,
        })
      : undefined;
    const sellerFields = bandId
      ? { sellerKind: "band" as const, bandId }
      : { organizationId };
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
      startsAt: NOW + 24 * 60 * 60 * 1000,
      doorsTime: "19:00",
      flyKey: "xerox",
      lineup: [],
      genres: [],
      desc: "An evening of local music.",
      ticketing: "paid",
      ticketCapacity: 100,
      cap: "100",
      goingCount: 0,
      ownerKind: sellerKind,
      ...(bandId
        ? { createdByBand: bandId }
        : { createdByOrganization: organizationId }),
    });
    const orderId = await ctx.db.insert("ticketOrders", {
      gigId,
      ...sellerFields,
      buyerUserId,
      quantity: 2,
      unitPriceMinor: 500,
      unitFeeMinor: 50,
      subtotalMinor: 1000,
      feeMinor: 100,
      totalMinor: 1100,
      currency: "usd",
      status: "checkout_open",
      stripeCheckoutSessionId: SESSION_ID,
      reservedUntil: NOW + 30 * 60 * 1000,
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
      ...orderOverrides,
    });
    const order = (await ctx.db.get(orderId))!;
    const inventoryId = await ctx.db.insert("gigTicketInventory", {
      gigId,
      ...sellerFields,
      capacity: 100,
      reserved:
        order.status === "checkout_open" || order.status === "reserved"
          ? order.quantity
          : 0,
      sold:
        order.status === "paid" || order.status === "refunded"
          ? order.quantity
          : 0,
      updatedAt: NOW,
    });
    if (order.status === "paid" || order.status === "refunded") {
      for (let index = 0; index < order.quantity; index++) {
        await ctx.db.insert("tickets", {
          orderId,
          gigId,
          ...sellerFields,
          holderUserId: buyerUserId,
          token: `ticket_${index}`,
          status: order.status === "paid" ? "valid" : "refunded",
          createdAt: NOW,
        });
      }
    }
    return {
      buyerUserId,
      organizationId,
      detailsId,
      bandId,
      payoutAccountId,
      venueId,
      gigId,
      orderId,
      inventoryId,
    };
  });
  return {
    t,
    ...ids,
    deliver: (event: StripeEvent, kind: "connect" | "platform" = "connect") =>
      t.mutation(internal.stripeWebhook.recordAndApply, {
        kind,
        event,
        receivedAt: Date.now(),
        livemodeMismatch: false,
      }),
    state: () =>
      t.run(async (ctx) => ({
        order: (await ctx.db.get(ids.orderId))!,
        inventory: (await ctx.db.get(ids.inventoryId))!,
        tickets: await ctx.db.query("tickets").collect(),
        refunds: await ctx.db.query("ticketRefunds").collect(),
        ledger: await ctx.db.query("ledgerEntries").collect(),
        jobs: await ctx.db.system.query("_scheduled_functions").collect(),
      })),
  };
}

function checkoutEvent(
  orderId: Id<"ticketOrders">,
  fields: Record<string, unknown> = {},
  type = "checkout.session.completed",
): StripeEvent {
  return {
    id: "evt_ticket_checkout",
    type,
    livemode: false,
    account: ACCOUNT_ID,
    created: NOW / 1000 - 60,
    data: {
      object: {
        id: SESSION_ID,
        object: "checkout.session",
        payment_status: "paid",
        amount_total: 1100,
        currency: "usd",
        payment_intent: "pi_ticket",
        metadata: { ticketOrderId: orderId },
        ...fields,
      },
    },
  };
}

function refundedEvent(orderId: Id<"ticketOrders">): StripeEvent {
  return {
    id: "evt_ticket_refunded",
    type: "charge.refunded",
    livemode: false,
    account: ACCOUNT_ID,
    created: NOW / 1000,
    data: {
      object: {
        id: "ch_ticket",
        payment_intent: "pi_ticket",
        metadata: { ticketOrderId: orderId },
        amount_refunded: 1100,
        refunds: {
          data: [
            { id: "re_previous", amount: 500 },
            { id: "re_dashboard", amount: 600 },
          ],
        },
      },
    },
  };
}

function ticketDisputeEvent(
  type: "charge.dispute.created" | "charge.dispute.closed",
  orderId: Id<"ticketOrders">,
  fields: Record<string, unknown> = {},
): StripeEvent {
  return {
    id:
      type === "charge.dispute.created"
        ? "evt_ticket_dispute_created"
        : "evt_ticket_dispute_closed",
    type,
    livemode: false,
    account: ACCOUNT_ID,
    created: NOW / 1000,
    data: {
      object: {
        id: "dp_ticket",
        payment_intent: "pi_ticket",
        amount: 1100,
        status: type === "charge.dispute.closed" ? "won" : undefined,
        charge: { id: "ch_ticket", metadata: { ticketOrderId: orderId } },
        ...fields,
      },
    },
  };
}

describe("ticket Checkout completion", () => {
  test("mints a band order paid on the band's connected account", async () => {
    const f = await setupTickets({}, "band");
    const before = await f.state();
    expect(before.order).toMatchObject({ sellerKind: "band", bandId: f.bandId });
    expect(before.order).not.toHaveProperty("organizationId");
    const event = { ...checkoutEvent(f.orderId), account: BAND_ACCOUNT_ID };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.order).toMatchObject({
      status: "paid",
      stripePaymentIntentId: "pi_ticket",
      paidAt: event.created * 1000,
    });
    expect(state.tickets).toHaveLength(2);
    expect(state.tickets.map((ticket) => ticket.status)).toEqual(["valid", "valid"]);
    expect(state.inventory).toMatchObject({ reserved: 0, sold: 2 });
    expect(state.refunds).toEqual([]);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test.each(["checkout_open", "reserved"] as const)(
    "mints a matching %s order once, including deliveries with a new event id",
    async (status) => {
      const f = await setupTickets({ status });
      const event = checkoutEvent(f.orderId);
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const state = await f.state();
      expect(state.order).toMatchObject({
        status: "paid",
        stripePaymentIntentId: "pi_ticket",
        paidAt: event.created * 1000,
      });
      expect(state.order.stripeChargeId).toBeUndefined();
      expect(state.tickets).toHaveLength(state.order.quantity);
      expect(state.tickets.every((ticket) => ticket.status === "valid")).toBe(
        true,
      );
      expect(state.inventory).toMatchObject({ reserved: 0, sold: 2 });
      expect(state.ledger).toMatchObject([
        { kind: "ticket_sale", amountMinor: 1100, stripeEventId: event.id },
        { kind: "ticket_fee", amountMinor: 100, stripeEventId: event.id },
      ]);
      expect(state.refunds).toEqual([]);
      expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
      expect(await f.deliver({ ...event, id: "evt_ticket_replay" })).toEqual({
        outcome: "applied",
      });
      expect(await f.state()).toEqual(state);
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test.each(["invalid", "deleted"])(
    "falls back to the session id when the metadata order id is %s",
    async (metadataCase) => {
      const f = await setupTickets();
      let metadataOrderId = "not_an_id";
      if (metadataCase === "deleted") {
        metadataOrderId = await f.t.run(async (ctx) => {
          const { _id, _creationTime, ...order } = (await ctx.db.get(
            f.orderId,
          ))!;
          const deletedId = await ctx.db.insert("ticketOrders", {
            ...order,
            stripeCheckoutSessionId: undefined,
          });
          await ctx.db.delete(deletedId);
          return deletedId;
        });
      }
      const event = checkoutEvent(f.orderId, {
        metadata: { ticketOrderId: metadataOrderId },
      });
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const state = await f.state();
      expect(state.order.status).toBe("paid");
      expect(state.tickets).toHaveLength(2);
    },
  );

  test("ignores unpaid Checkout sessions", async () => {
    const f = await setupTickets();
    const before = await f.state();
    expect(
      await f.deliver(checkoutEvent(f.orderId, { payment_status: "unpaid" })),
    ).toEqual({ outcome: "applied" });
    expect(await f.state()).toEqual(before);
  });

  test.each([undefined, null, "1300"])(
    "ignores a late payment with a non-numeric amount_total (%j)",
    async (amountTotal) => {
      const f = await setupTickets({ status: "expired" });
      const before = await f.state();
      expect(
        await f.deliver(checkoutEvent(f.orderId, { amount_total: amountTotal })),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(before);
    },
  );

  test.each([undefined, null, { id: "pi_expanded" }])(
    "rejects a late payment without a string payment intent (%j)",
    async (paymentIntent) => {
      const f = await setupTickets({ status: "expired" });
      const before = await f.state();
      expect(
        await f.deliver(
          checkoutEvent(f.orderId, { payment_intent: paymentIntent }),
        ),
      ).toEqual({ outcome: "failed" });
      expect(await f.state()).toEqual(before);
    },
  );
});

describe("ticket event account checks", () => {
  test.each(["seller", "account"] as const)(
    "ignores a band Checkout event with a missing %s",
    async (missing) => {
      const f = await setupTickets({}, "band");
      await f.t.run((ctx) =>
        ctx.db.delete(missing === "seller" ? f.bandId! : f.payoutAccountId!),
      );
      const before = await f.state();
      expect(
        await f.deliver({ ...checkoutEvent(f.orderId), account: BAND_ACCOUNT_ID }),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(before);
    },
  );

  test.each([ACCOUNT_ID, "acct_other", undefined])(
    "ignores a band Checkout event from the wrong account (%s)",
    async (account) => {
      const f = await setupTickets({}, "band");
      const before = await f.state();
      const event = { ...checkoutEvent(f.orderId), account };
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      expect(warn).toHaveBeenCalledExactlyOnceWith(
        `${event.type} ignored: Stripe account mismatch for ticket order ${f.orderId}`,
      );
      expect(await f.state()).toEqual(before);
      expect(before.order.status).toBe("checkout_open");
      expect(before.tickets).toEqual([]);
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test.each([
    "checkout.session.completed",
    "checkout.session.expired",
    "charge.refunded",
  ])(
    "%s ignores mismatched and missing connected accounts without changing ticket state",
    async (type) => {
      const f = await setupTickets(
        type === "charge.refunded" ? { status: "paid" } : {},
      );
      const event =
        type === "charge.refunded"
          ? refundedEvent(f.orderId)
          : checkoutEvent(f.orderId, {}, type);
      const before = await f.state();
      for (const account of ["acct_other", undefined]) {
        const rejected = { ...event, id: `evt_account_${account}`, account };
        expect(await f.deliver(rejected)).toEqual({ outcome: "applied" });
        const recorded = await f.t.run((ctx) =>
          ctx.db
            .query("stripeEvents")
            .withIndex("by_eventId", (q) => q.eq("eventId", rejected.id))
            .unique(),
        );
        expect(recorded).toMatchObject({
          status: "applied",
        });
        expect(recorded?.error).toBeUndefined();
        expect(await f.state()).toEqual(before);
      }
    },
  );

  test.each(["missing details", "missing account"])(
    "ignores Checkout when the organization has %s, even without an event account",
    async (missing) => {
      const f = await setupTickets();
      await f.t.run((ctx) =>
        missing === "missing details"
          ? ctx.db.delete(f.detailsId)
          : ctx.db.patch(f.detailsId, { stripeAccountId: undefined }),
      );
      const before = await f.state();
      expect(
        await f.deliver({ ...checkoutEvent(f.orderId), account: undefined }),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(before);
    },
  );
});

describe("late ticket payments", () => {
  test("refunds a late band payment with band seller references", async () => {
    const f = await setupTickets({ status: "expired" }, "band");
    const event = { ...checkoutEvent(f.orderId), account: BAND_ACCOUNT_ID };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const pending = await f.state();
    expect(pending.refunds).toMatchObject([
      {
        sellerKind: "band",
        bandId: f.bandId,
        reason: "late_payment",
        status: "pending",
        stripePaymentIntentId: "pi_ticket",
      },
    ]);
    expect(pending.refunds[0]).not.toHaveProperty("organizationId");
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/refunds",
      expect.objectContaining({
        payment_intent: "pi_ticket",
        amount: 1100,
        refund_application_fee: true,
      }),
      expect.objectContaining({ stripeAccount: BAND_ACCOUNT_ID }),
    );
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { sellerKind: "band", bandId: f.bandId, status: "succeeded" },
    ]);
    expect(state.refunds[0]).not.toHaveProperty("organizationId");
    expect(state.order).toMatchObject({ status: "expired", refundedMinor: 0 });
    expect(state.tickets).toEqual([]);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -1100, bandId: f.bandId },
    ]);
    expect(state.ledger[0]).not.toHaveProperty("organizationId");
  });

  test.each(["expired", "cancelled", "refunded"] as const)(
    "refunds a %s order asynchronously without minting or reversing an unrecorded fee",
    async (status) => {
      const f = await setupTickets({ status });
      const before = await f.state();
      const event = checkoutEvent(f.orderId, { amount_total: 1300 });
      expect(await f.deliver(event)).toEqual({ outcome: "applied" });
      const pending = await f.state();
      expect(pending.order).toMatchObject({
        status,
        stripePaymentIntentId: "pi_ticket",
      });
      expect(pending.tickets).toEqual(before.tickets);
      expect(pending.inventory).toEqual(before.inventory);
      expect(pending.ledger).toEqual([]);
      expect(pending.refunds).toMatchObject([
        {
          orderId: f.orderId,
          gigId: f.gigId,
          organizationId: f.organizationId,
          reason: "late_payment",
          status: "pending",
          amountMinor: 1300,
          currency: "usd",
          attempt: 0,
        },
      ]);
      const refundId = pending.refunds[0]._id;
      expect(pending.jobs).toMatchObject([
        {
          name: "ticketRefunds:executeRefund",
          args: [{ refundId, attempt: 0 }],
          scheduledTime: NOW,
        },
      ]);
      expect(stripeMock).not.toHaveBeenCalled();
      expect(
        await f.deliver({ ...event, id: "evt_late_pending_replay" }),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(pending);

      await f.t.finishAllScheduledFunctions(vi.runAllTimers);
      expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
        "POST",
        "/v1/refunds",
        expect.objectContaining({ payment_intent: "pi_ticket", amount: 1300 }),
        expect.objectContaining({ stripeAccount: ACCOUNT_ID }),
      );
      const settled = await f.state();
      expect(settled.refunds).toMatchObject([
        {
          _id: refundId,
          status: "succeeded",
          stripeRefundId: "re_late_ticket",
        },
      ]);
      expect(settled.order).toMatchObject({
        status,
        refundedMinor: 0,
      });
      expect(settled.order.stripeRefundId).toBeUndefined();
      expect(settled.tickets).toEqual(before.tickets);
      expect(settled.inventory).toEqual(before.inventory);
      expect(settled.ledger).toMatchObject([
        { kind: "ticket_refund", amountMinor: -1300 },
      ]);
      expect(
        await f.deliver({ ...event, id: "evt_late_succeeded_replay" }),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(settled);
    },
  );

  test.each(["paid", "checkout_open", "reserved"] as const)(
    "refunds the late payment's own intent on a %s order without replacing the order's intent",
    async (status) => {
      const f = await setupTickets({
        status,
        stripePaymentIntentId: "pi_current",
      });
      const before = await f.state();
      expect(
        await f.deliver(
          checkoutEvent(f.orderId, {
            id: "cs_stale",
            payment_intent: "pi_stale",
          }),
        ),
      ).toEqual({ outcome: "applied" });
      const after = await f.state();
      expect(after.order).toEqual(before.order);
      expect(after.order.stripePaymentIntentId).toBe("pi_current");
      expect(after.tickets).toEqual(before.tickets);
      expect(after.inventory).toEqual(before.inventory);
      expect(after.refunds).toMatchObject([
        {
          reason: "late_payment",
          status: "pending",
          stripePaymentIntentId: "pi_stale",
        },
      ]);
      expect(after.jobs).toMatchObject([
        { name: "ticketRefunds:executeRefund" },
      ]);
      await f.t.finishAllScheduledFunctions(vi.runAllTimers);
      expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
        "POST",
        "/v1/refunds",
        expect.objectContaining({ payment_intent: "pi_stale" }),
        expect.objectContaining({ stripeAccount: ACCOUNT_ID }),
      );
    },
  );

  test("a late payment against a paid order leaves the order paid and its tickets valid", async () => {
    const f = await setupTickets({
      status: "paid",
      stripePaymentIntentId: "pi_current",
    });
    const before = await f.state();
    expect(
      await f.deliver(
        checkoutEvent(f.orderId, {
          id: "cs_stale",
          payment_intent: "pi_stale",
        }),
      ),
    ).toEqual({ outcome: "applied" });
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        reason: "late_payment",
        status: "succeeded",
        stripePaymentIntentId: "pi_stale",
      },
    ]);
    expect(state.order).toEqual(before.order);
    expect(state.order).toMatchObject({
      status: "paid",
      refundedMinor: 0,
      stripePaymentIntentId: "pi_current",
    });
    expect(state.tickets).toEqual(before.tickets);
    expect(state.tickets.map((ticket) => ticket.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toHaveLength(1);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -1100 },
    ]);
  });

  test("refunds two distinct late payment intents independently on a paid order", async () => {
    const f = await setupTickets({
      status: "paid",
      stripePaymentIntentId: "pi_current",
    });
    stripeMock
      .mockResolvedValueOnce({ id: "re_stale" })
      .mockResolvedValueOnce({ id: "re_stale_2" });
    const firstEvent = checkoutEvent(f.orderId, {
      id: "cs_stale",
      payment_intent: "pi_stale",
    });
    const secondEvent = {
      ...checkoutEvent(f.orderId, {
        id: "cs_stale_2",
        payment_intent: "pi_stale_2",
      }),
      id: "evt_stale_2",
    };
    expect(await f.deliver(firstEvent)).toEqual({ outcome: "applied" });
    expect(await f.deliver(secondEvent)).toEqual({ outcome: "applied" });
    const pending = await f.state();
    expect(pending.order.stripePaymentIntentId).toBe("pi_current");
    expect(pending.refunds).toHaveLength(2);
    expect(pending.refunds).toMatchObject([
      {
        reason: "late_payment",
        status: "pending",
        stripePaymentIntentId: "pi_stale",
      },
      {
        reason: "late_payment",
        status: "pending",
        stripePaymentIntentId: "pi_stale_2",
      },
    ]);
    await f.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(stripeMock).toHaveBeenCalledTimes(2);
    for (const refund of pending.refunds) {
      expect(stripeMock).toHaveBeenCalledWith(
        "POST",
        "/v1/refunds",
        expect.objectContaining({
          payment_intent: refund.stripePaymentIntentId,
          metadata: expect.objectContaining({ refundId: refund._id }),
        }),
        expect.objectContaining({ stripeAccount: ACCOUNT_ID }),
      );
    }
    const settled = await f.state();
    expect(settled.refunds.map((refund) => refund.status)).toEqual([
      "succeeded",
      "succeeded",
    ]);
    expect(settled.order.stripePaymentIntentId).toBe("pi_current");
  });

  test("allows a new refund after a failed late-payment request", async () => {
    const f = await setupTickets({ status: "expired" });
    const event = checkoutEvent(f.orderId);
    await f.deliver(event);
    const refundId = (await f.state()).refunds[0]._id;
    await f.t.mutation(internal.ticketRefunds.markRefundFailed, {
      refundId,
      attempt: 2,
      error: "Stripe unavailable",
    });
    expect(await f.deliver({ ...event, id: "evt_late_retry" })).toEqual({
      outcome: "applied",
    });
    expect((await f.state()).refunds.map((refund) => refund.status)).toEqual([
      "failed",
      "pending",
    ]);
  });
});

describe("ticket Checkout expiry", () => {
  test("releases only the matching session's reservation, once", async () => {
    const f = await setupTickets();
    const before = await f.state();
    const stale = checkoutEvent(
      f.orderId,
      { id: "cs_stale" },
      "checkout.session.expired",
    );
    expect(await f.deliver(stale)).toEqual({ outcome: "applied" });
    expect(await f.state()).toEqual(before);
    const current = {
      ...checkoutEvent(f.orderId, {}, "checkout.session.expired"),
      id: "evt_expiry_current",
    };
    expect(await f.deliver(current)).toEqual({ outcome: "applied" });
    const expired = await f.state();
    expect(expired.order.status).toBe("expired");
    expect(expired.inventory).toMatchObject({ reserved: 0, sold: 0 });
    expect(expired.tickets).toEqual([]);
    expect(expired.refunds).toEqual([]);
    expect(await f.deliver({ ...current, id: "evt_expiry_replay" })).toEqual({
      outcome: "applied",
    });
    expect(await f.state()).toEqual(expired);
  });

  test.each(["reserved", "paid", "expired", "cancelled", "refunded"] as const)(
    "ignores expiry for a %s order",
    async (status) => {
      const f = await setupTickets({ status });
      const before = await f.state();
      expect(
        await f.deliver(
          checkoutEvent(f.orderId, {}, "checkout.session.expired"),
        ),
      ).toEqual({ outcome: "applied" });
      expect(await f.state()).toEqual(before);
    },
  );
});

describe("ticket dashboard refunds", () => {
  test("records the band seller on dashboard refunds and their ledger entries", async () => {
    const f = await setupTickets(
      { status: "paid", stripePaymentIntentId: "pi_ticket" },
      "band",
    );
    const event = { ...refundedEvent(f.orderId), account: BAND_ACCOUNT_ID };
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      {
        sellerKind: "band",
        bandId: f.bandId,
        reason: "dashboard",
        status: "succeeded",
        amountMinor: 1100,
      },
    ]);
    expect(state.refunds[0]).not.toHaveProperty("organizationId");
    expect(state.order).toMatchObject({ status: "refunded", refundedMinor: 1100 });
    expect(state.tickets.map((ticket) => ticket.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger).toMatchObject([
      { kind: "ticket_refund", amountMinor: -1100, bandId: f.bandId },
      { kind: "ticket_fee", amountMinor: -100, bandId: f.bandId },
    ]);
    for (const entry of state.ledger) {
      expect(entry).not.toHaveProperty("organizationId");
    }
    expect(await f.deliver({ ...event, id: "evt_band_refund_replay" })).toEqual({
      outcome: "applied",
    });
    expect(await f.state()).toEqual(state);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("reconciles only the refund delta and deduplicates repeated charge events", async () => {
    const f = await setupTickets({
      status: "paid",
      refundedMinor: 500,
      stripePaymentIntentId: "pi_ticket",
    });
    await f.t.run((ctx) =>
      ctx.db.insert("ticketRefunds", {
        orderId: f.orderId,
        gigId: f.gigId,
        organizationId: f.organizationId,
        amountMinor: 500,
        currency: "usd",
        reason: "admin",
        status: "succeeded",
        stripeRefundId: "re_previous",
        attempt: 0,
        createdAt: NOW,
        updatedAt: NOW,
      }),
    );
    const event = refundedEvent(f.orderId);
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.refunds).toMatchObject([
      { amountMinor: 500, status: "succeeded", stripeRefundId: "re_previous" },
      {
        reason: "dashboard",
        status: "succeeded",
        amountMinor: 600,
        stripeRefundId: "re_dashboard",
      },
    ]);
    expect(state.order).toMatchObject({
      status: "refunded",
      refundedMinor: 1100,
    });
    expect(state.tickets.map((ticket) => ticket.status)).toEqual([
      "refunded",
      "refunded",
    ]);
    expect(state.ledger).toMatchObject([
      {
        kind: "ticket_refund",
        amountMinor: -600,
        fundsState: "refunded",
        stripeEventId: event.id,
      },
      {
        kind: "ticket_fee",
        amountMinor: -55,
        fundsState: "refunded",
        stripeEventId: event.id,
      },
    ]);
    expect(state.jobs).toEqual([]);
    expect(await f.deliver({ ...event, id: "evt_dashboard_replay" })).toEqual({
      outcome: "applied",
    });
    expect(await f.state()).toEqual(state);
    expect(stripeMock).not.toHaveBeenCalled();
  });
});

test.each([
  "checkout.session.completed",
  "checkout.session.expired",
  "charge.refunded",
])("%s ignores unknown ticket orders", async (type) => {
  const f = await setupTickets();
  const before = await f.state();
  const event =
    type === "charge.refunded"
      ? refundedEvent(f.orderId)
      : checkoutEvent(f.orderId, {}, type);
  event.data.object.metadata = { ticketOrderId: "not_an_id" };
  event.data.object.id = "unknown_session_or_charge";
  expect(await f.deliver(event)).toEqual({ outcome: "applied" });
  expect(await f.state()).toEqual(before);
});

describe("ticket disputes", () => {
  test.each(["won", "lost"] as const)(
    "records the band's dispute hold and %s outcome on its own ledger",
    async (outcome) => {
      const f = await setupTickets({ status: "paid" }, "band");
      const before = await f.state();
      const created = {
        ...ticketDisputeEvent("charge.dispute.created", f.orderId),
        account: BAND_ACCOUNT_ID,
      };
      const closed = {
        ...ticketDisputeEvent("charge.dispute.closed", f.orderId, {
          status: outcome,
        }),
        account: BAND_ACCOUNT_ID,
      };
      expect(await f.deliver(created)).toEqual({ outcome: "applied" });
      expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
      const state = await f.state();
      expect(state.ledger).toMatchObject([
        { kind: "dispute_hold", amountMinor: -1100, fundsState: "disputed" },
        {
          kind: outcome === "won" ? "dispute_release" : "dispute_loss",
          amountMinor: outcome === "won" ? 1100 : -1100,
          fundsState: outcome === "won" ? "available" : "refunded",
        },
      ]);
      for (const entry of state.ledger) {
        expect(entry).toMatchObject({
          bandId: f.bandId,
          ticketOrderId: f.orderId,
          currency: "usd",
          stripeRef: "dispute:dp_ticket",
        });
        expect(entry).not.toHaveProperty("organizationId");
      }
      if (outcome === "won") {
        expect(state.order).toEqual(before.order);
        expect(state.tickets).toEqual(before.tickets);
      } else {
        expect(state.order).toMatchObject({
          status: "refunded",
          refundedMinor: 1100,
        });
        expect(state.tickets.map((ticket) => ticket.status)).toEqual([
          "cancelled",
          "cancelled",
        ]);
      }
      expect(await f.deliver({ ...closed, id: "evt_band_dispute_replay" })).toEqual({
        outcome: "applied",
      });
      expect(await f.state()).toEqual(state);
    },
  );

  test("created holds the disputed amount without changing the paid order or tickets", async () => {
    const f = await setupTickets({ status: "paid" });
    const before = await f.state();
    const event = ticketDisputeEvent("charge.dispute.created", f.orderId);
    expect(await f.deliver(event)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.order).toEqual(before.order);
    expect(state.order).toMatchObject({ status: "paid" });
    expect(state.tickets).toEqual(before.tickets);
    expect(state.tickets.map((ticket) => ticket.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toHaveLength(1);
    expect(state.ledger).toMatchObject([
      {
        kind: "dispute_hold",
        amountMinor: -1100,
        fundsState: "disputed",
        organizationId: f.organizationId,
        ticketOrderId: f.orderId,
        currency: "usd",
        stripeRef: "dispute:dp_ticket",
        stripeEventId: event.id,
        idempotencyKey: "ticket-dispute-hold:dp_ticket",
      },
    ]);
    expect(await f.deliver(event)).toEqual({ outcome: "duplicate" });
    expect(await f.state()).toEqual(state);
    // A new event id also exercises the ledger's dispute-id deduplication.
    expect(await f.deliver({ ...event, id: "evt_ticket_dispute_replay" })).toEqual({
      outcome: "applied",
    });
    expect(await f.state()).toEqual(state);
  });

  test("closed won releases the hold and preserves the paid order and valid tickets", async () => {
    const f = await setupTickets({ status: "paid" });
    const before = await f.state();
    await f.deliver(ticketDisputeEvent("charge.dispute.created", f.orderId));
    const closed = ticketDisputeEvent("charge.dispute.closed", f.orderId, {
      status: "won",
    });
    expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.order).toEqual(before.order);
    expect(state.order).toMatchObject({ status: "paid" });
    expect(state.tickets).toEqual(before.tickets);
    expect(state.tickets.map((ticket) => ticket.status)).toEqual(["valid", "valid"]);
    expect(state.ledger).toMatchObject([
      { kind: "dispute_hold", amountMinor: -1100 },
      {
        kind: "dispute_release",
        amountMinor: 1100,
        fundsState: "available",
        organizationId: f.organizationId,
        ticketOrderId: f.orderId,
        stripeRef: "dispute:dp_ticket",
        stripeEventId: closed.id,
        idempotencyKey: "ticket-dispute-release:dp_ticket",
      },
    ]);
  });

  test("closed lost refunds the order and cancels only valid tickets", async () => {
    const f = await setupTickets({ status: "paid" });
    const before = await f.state();
    await f.t.run((ctx) =>
      ctx.db.patch(before.tickets[0]._id, { status: "used" }),
    );
    const usedTicket = (await f.state()).tickets[0];
    await f.deliver(ticketDisputeEvent("charge.dispute.created", f.orderId));
    const closed = ticketDisputeEvent("charge.dispute.closed", f.orderId, {
      status: "lost",
    });
    expect(await f.deliver(closed)).toEqual({ outcome: "applied" });
    const state = await f.state();
    expect(state.order).toMatchObject({
      status: "refunded",
      refundedMinor: before.order.totalMinor,
    });
    expect(state.tickets.map((ticket) => ticket.status).sort()).toEqual([
      "cancelled",
      "used",
    ]);
    expect(state.tickets.find((ticket) => ticket._id === usedTicket._id)).toEqual(
      usedTicket,
    );
    expect(state.ledger).toMatchObject([
      { kind: "dispute_hold", amountMinor: -1100 },
      {
        kind: "dispute_loss",
        amountMinor: -1100,
        fundsState: "refunded",
        organizationId: f.organizationId,
        ticketOrderId: f.orderId,
        stripeRef: "dispute:dp_ticket",
        stripeEventId: closed.id,
        idempotencyKey: "ticket-dispute-loss:dp_ticket",
      },
    ]);
  });

  test.each(["organization", "band"] as const)(
    "ignores %s disputes with mismatched or missing event accounts without ledger entries",
    async (sellerKind) => {
      const f = await setupTickets({ status: "paid" }, sellerKind);
      const before = await f.state();
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
      for (const type of [
        "charge.dispute.created",
        "charge.dispute.closed",
      ] as const) {
        for (const account of ["acct_other", undefined]) {
          const event = {
            ...ticketDisputeEvent(type, f.orderId, { status: "lost" }),
            id: `evt_${type}_${account}`,
            account,
          };
          warn.mockClear();
          expect(await f.deliver(event)).toEqual({ outcome: "applied" });
          expect(warn).toHaveBeenCalledExactlyOnceWith(
            `${event.type} ignored: Stripe account mismatch for ticket order ${f.orderId}`,
          );
          const state = await f.state();
          expect(state).toEqual(before);
          expect(state.ledger).toEqual([]);
        }
      }
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test.each(["organization", "band"] as const)(
    "ignores %s disputes with no stored Stripe account, even without an event account",
    async (sellerKind) => {
      const f = await setupTickets({ status: "paid" }, sellerKind);
      await f.t.run((ctx) =>
        sellerKind === "band"
          ? ctx.db.delete(f.payoutAccountId!)
          : ctx.db.patch(f.detailsId, { stripeAccountId: undefined }),
      );
      const before = await f.state();
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
      for (const type of [
        "charge.dispute.created",
        "charge.dispute.closed",
      ] as const) {
        const event = {
          ...ticketDisputeEvent(type, f.orderId, { status: "lost" }),
          account: undefined,
        };
        warn.mockClear();
        expect(await f.deliver(event)).toEqual({ outcome: "applied" });
        expect(warn).toHaveBeenCalledExactlyOnceWith(
          `${event.type} ignored: Stripe account mismatch for ticket order ${f.orderId}`,
        );
        const state = await f.state();
        expect(state).toEqual(before);
        expect(state.ledger).toEqual([]);
      }
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );
});

test("booking Checkout still applies through the existing payment-record handler", async () => {
  const f = await setupTickets();
  const { bookingId, paymentRecordId } = await f.t.run(async (ctx) => {
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: [],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId: f.organizationId,
      venueId: f.venueId,
      mode: "publicEvent",
      area: "Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "Local music",
      genres: [],
      startsAt: NOW,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "confirmed",
      slug: "friday",
      createdBy: f.buyerUserId,
      revision: 1,
      applicationCount: 1,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 1100,
      required: true,
      status: "booked",
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: f.buyerUserId,
      message: "Available",
      status: "booked",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId: f.organizationId,
      bandId,
      applicationId,
      status: "confirmed",
      revision: 1,
      startsAt: NOW,
      ...feeSnapshot(1100, 1000),
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW,
      payoutHold: true,
      payoutHoldReasons: ["unpaid_installment"],
      paidMinor: 0,
      createdBy: f.buyerUserId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const paymentRecordId = await ctx.db.insert("paymentRecords", {
      bookingId,
      installmentIndex: 1,
      label: "Balance",
      amountMinor: 1100,
      currency: "usd",
      dueAt: NOW,
      status: "checkout_open",
      stripeCheckoutSessionId: "cs_booking",
      attempt: 0,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    return { bookingId, paymentRecordId };
  });
  const event = checkoutEvent(f.orderId, {
    id: "cs_booking",
    payment_intent: "pi_booking",
    metadata: { paymentRecordId },
  });
  delete event.account;
  expect(isTicketSession(event.data.object)).toBe(false);
  expect(await f.deliver(event, "platform")).toEqual({ outcome: "applied" });
  expect(await f.t.run((ctx) => ctx.db.get(paymentRecordId))).toMatchObject({
    status: "paid",
    stripePaymentIntentId: "pi_booking",
    stripeEventId: event.id,
  });
  expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toMatchObject({
    paidMinor: 1100,
    payoutHold: false,
  });
  const state = await f.state();
  expect(state.order.status).toBe("checkout_open");
  expect(state.tickets).toEqual([]);
  expect(state.refunds).toEqual([]);
  expect(state.ledger).toMatchObject([
    { kind: "charge", bookingId, amountMinor: 1100 },
  ]);
});
