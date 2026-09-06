/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  bookingTotals,
  ledgerLabel,
  organizationLedgerAmount,
  ticketTotals,
} from "./lib/financeMath";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const CREATED_AT = 1_000;
const ACTORS = ["owner", "manager", "finance", "door", "outsider"] as const;
type Actor = (typeof ACTORS)[number];

async function setupFinance() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `finance_${actor}` });
  const fixture = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `finance_${actor}`,
        name: actor,
        email: `${actor}@finance.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationFields = {
      name: "Finance Collective",
      slug: "finance-collective",
      orgType: "venueOperator" as const,
      status: "verified" as const,
      ownerUserId: users.owner,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    };
    const organizationId = await ctx.db.insert(
      "organizations",
      organizationFields,
    );
    const otherOrganizationId = await ctx.db.insert("organizations", {
      ...organizationFields,
      name: "Other Collective",
      slug: "other-collective",
      ownerUserId: users.outsider,
    });
    for (const role of ["owner", "manager", "finance", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: CREATED_AT,
      });
    }
    const privateDetailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "owner@finance.test",
      contactName: "Owner",
      stripeAccountId: "acct_finance",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: CREATED_AT,
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
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "publicEvent",
      venueId,
      area: "Oakland",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: 10_000,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: 5_000,
      visibility: "public",
      ticketing: "paid",
      currency: "usd",
      status: "confirmed",
      slug: "friday-at-the-hall",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 0,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 15_000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.owner,
      message: "Available",
      status: "booked",
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    });
    const bookingFields = {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "confirmed" as const,
      revision: 1,
      startsAt: 10_000,
      grossMinor: 15_000,
      commissionBps: 1000,
      commissionMinor: 1500,
      artistNetMinor: 13_500,
      currency: "usd",
      cancellationTemplate: "standard" as const,
      organizerAcceptedTermsAt: CREATED_AT,
      payoutHold: false,
      createdBy: users.owner,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    };
    const bookingId = await ctx.db.insert("bookings", bookingFields);
    const awaitingBookingId = await ctx.db.insert("bookings", {
      ...bookingFields,
      status: "awaiting_payment",
    });
    const paymentFields = {
      bookingId,
      installmentIndex: 0,
      label: "Deposit",
      amountMinor: 10_000,
      currency: "usd",
      dueAt: 2_000,
      status: "paid" as const,
      attempt: 1,
      refundedMinor: 2_000,
      disputedMinor: 300,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    };
    const paidRecordId = await ctx.db.insert("paymentRecords", paymentFields);
    const pendingRecordId = await ctx.db.insert("paymentRecords", {
      ...paymentFields,
      bookingId: awaitingBookingId,
      label: "Balance",
      status: "pending",
      amountMinor: 5_000,
      refundedMinor: 0,
      disputedMinor: undefined,
      dueAt: 3_000,
    });
    const gigId = await ctx.db.insert("gigs", {
      title: "Friday Live",
      venueId,
      price: 10,
      startsAt: 10_000,
      doorsTime: "7 PM",
      flyKey: "xerox",
      lineup: [bandId],
      genres: ["Indie"],
      desc: "An evening of local music.",
      ticketing: "paid",
      createdByOrganization: organizationId,
      cap: "100",
      goingCount: 0,
    });
    const orderFields = {
      gigId,
      organizationId,
      buyerUserId: users.outsider,
      quantity: 1,
      unitPriceMinor: 1_000,
      unitFeeMinor: 100,
      subtotalMinor: 1_000,
      feeMinor: 100,
      totalMinor: 1_100,
      currency: "usd",
      status: "paid" as const,
      reservedUntil: 2_000,
      attempt: 1,
      refundedMinor: 0,
      createdAt: CREATED_AT,
      updatedAt: CREATED_AT,
    };
    return {
      organizationId,
      otherOrganizationId,
      privateDetailsId,
      opportunityId,
      bookingId,
      awaitingBookingId,
      bookingFields,
      paymentFields,
      paidRecordId,
      pendingRecordId,
      gigId,
      orderFields,
    };
  });
  return { t, as, ...fixture };
}

async function seedLedger(
  t: Awaited<ReturnType<typeof setupFinance>>["t"],
  organizationId: Id<"organizations">,
  entries: Array<
    Pick<Doc<"ledgerEntries">, "kind" | "amountMinor" | "occurredAt"> &
      Partial<
        Pick<Doc<"ledgerEntries">, "bookingId" | "ticketOrderId" | "stripeRef">
      >
  >,
) {
  return await t.run(async (ctx) => {
    const ids: Id<"ledgerEntries">[] = [];
    for (const entry of entries) {
      ids.push(
        await ctx.db.insert("ledgerEntries", {
          organizationId,
          currency: "usd",
          fundsState: "available",
          idempotencyKey: `${organizationId}:${entry.occurredAt}:${entry.kind}`,
          ...entry,
        }),
      );
    }
    return ids;
  });
}

describe("overview", () => {
  test("summarizes payment records and resolves the pending booking title", async () => {
    const { as, organizationId, awaitingBookingId, pendingRecordId } =
      await setupFinance();
    const result = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    expect(result.bookings).toEqual({
      paidMinor: 10_000,
      dueMinor: 5_000,
      refundedMinor: 2_000,
      disputedMinor: 300,
      activeCount: 2,
    });
    expect(result.pendingPayments).toEqual([
      {
        bookingId: awaitingBookingId,
        paymentRecordId: pendingRecordId,
        opportunityTitle: "Friday at the Hall",
        label: "Balance",
        amountMinor: 5_000,
        dueAt: 3_000,
      },
    ]);
    expect(result.currency).toBe("usd");
  });

  test("includes paid and refunded ticket orders and excludes other statuses and organizations", async () => {
    const { t, as, organizationId, otherOrganizationId, orderFields } =
      await setupFinance();
    await t.run(async (ctx) => {
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        refundedMinor: 275,
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "refunded",
        refundedMinor: 1_100,
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        status: "reserved",
      });
      await ctx.db.insert("ticketOrders", {
        ...orderFields,
        organizationId: otherOrganizationId,
      });
    });
    const result = await as("finance").query(api.finance.overview, {
      organizationId,
    });
    // The organizer owes 250 of the 275 partial refund, plus the full 1,000 refund.
    expect(result.tickets).toEqual({
      ordersPaid: 1,
      grossMinor: 2_000,
      feeMinor: 200,
      refundedMinor: 1_375,
      refundedOrgMinor: 1_250,
      netMinor: 750,
      estimatedProcessingMinor: 124,
      truncated: false,
    });
  });

  test("returns the stored snapshot, or null when absent", async () => {
    const { t, as, organizationId } = await setupFinance();
    expect(
      (await as("owner").query(api.finance.overview, { organizationId }))
        .snapshot,
    ).toBeNull();
    const snapshot = {
      availableMinor: 12_000,
      pendingMinor: 3_000,
      currency: "usd",
      fetchedAt: 4_000,
    };
    await t.run(async (ctx) => {
      await ctx.db.insert("financeSnapshots", {
        organizationId,
        stripeAccountId: "acct_finance",
        ...snapshot,
      });
    });
    expect(
      (await as("owner").query(api.finance.overview, { organizationId }))
        .snapshot,
    ).toEqual(snapshot);
  });

  test("requires both Stripe flags and handles missing private details", async () => {
    const { t, as, organizationId, privateDetailsId } = await setupFinance();
    expect(
      (await as("owner").query(api.finance.overview, { organizationId }))
        .stripeReady,
    ).toBe(true);
    for (const flags of [
      { stripeChargesEnabled: false, stripeDetailsSubmitted: true },
      { stripeChargesEnabled: true, stripeDetailsSubmitted: false },
    ]) {
      await t.run(async (ctx) => {
        await ctx.db.patch(privateDetailsId, flags);
      });
      expect(
        (await as("owner").query(api.finance.overview, { organizationId }))
          .stripeReady,
      ).toBe(false);
    }
    await t.run(async (ctx) => {
      await ctx.db.delete(privateDetailsId);
    });
    expect(
      (await as("owner").query(api.finance.overview, { organizationId }))
        .stripeReady,
    ).toBe(false);
    expect(
      await t.query(internal.finance.financeContext, { organizationId }),
    ).toEqual({ snapshot: null, snapshotStripeAccountId: undefined });
  });

  test("bounds payment history, sorts pending payments, ignores cancelled dues, and falls back for missing opportunities", async () => {
    const {
      t,
      as,
      organizationId,
      otherOrganizationId,
      bookingFields,
      paymentFields,
      bookingId,
      opportunityId,
    } = await setupFinance();
    await t.run(async (ctx) => {
      for (let dueAt = 25; dueAt >= 1; dueAt--) {
        await ctx.db.insert("paymentRecords", {
          ...paymentFields,
          bookingId,
          status: "checkout_open",
          amountMinor: 100,
          refundedMinor: 0,
          disputedMinor: undefined,
          dueAt,
        });
      }
      const cancelledBookingId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "cancelled_by_organizer",
      });
      await ctx.db.insert("paymentRecords", {
        ...paymentFields,
        bookingId: cancelledBookingId,
        status: "pending",
        refundedMinor: 0,
        disputedMinor: undefined,
        dueAt: 0,
      });
      const excludedBookingId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "offer_sent",
      });
      await ctx.db.insert("paymentRecords", {
        ...paymentFields,
        bookingId: excludedBookingId,
      });
      const otherBookingId = await ctx.db.insert("bookings", {
        ...bookingFields,
        organizationId: otherOrganizationId,
      });
      await ctx.db.insert("paymentRecords", {
        ...paymentFields,
        bookingId: otherBookingId,
      });
      await ctx.db.delete(opportunityId);
    });
    const result = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    expect(result.bookings).toEqual({
      dueMinor: 5_900,
      paidMinor: 10_000,
      refundedMinor: 2_000,
      disputedMinor: 300,
      activeCount: 2,
    });
    // The paid record and first nine inserted installments fill the booking's cap.
    expect(result.pendingPayments.map((payment) => payment.dueAt)).toEqual([
      ...Array.from({ length: 9 }, (_, index) => index + 17),
      3_000,
    ]);
    expect(
      result.pendingPayments.every(
        (payment) => payment.opportunityTitle === "Booking",
      ),
    ).toBe(true);
  });

  test("caps pending payments at the earliest 20 across bookings", async () => {
    const { t, as, organizationId, bookingFields, paymentFields } =
      await setupFinance();
    await t.run(async (ctx) => {
      for (let index = 0; index < 6; index++) {
        const bookingId = await ctx.db.insert("bookings", bookingFields);
        for (let installmentIndex = 0; installmentIndex < 4; installmentIndex++) {
          await ctx.db.insert("paymentRecords", {
            ...paymentFields,
            bookingId,
            installmentIndex,
            status: "pending",
            amountMinor: 100,
            refundedMinor: 0,
            disputedMinor: undefined,
            dueAt: 24 - index * 4 - installmentIndex,
          });
        }
      }
    });

    const result = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    expect(result.pendingPayments.map((payment) => payment.dueAt)).toEqual(
      Array.from({ length: 20 }, (_, index) => index + 1),
    );
  });

  test.each([
    "withdrawn",
    "cancelled_by_organizer",
    "cancelled_by_artist",
    "force_majeure",
  ] as const)("excludes %s bookings and their payment records", async (status) => {
    const { t, as, organizationId, bookingFields, paymentFields } =
      await setupFinance();
    const baseline = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    await t.run(async (ctx) => {
      const bookingId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status,
      });
      await ctx.db.insert("paymentRecords", { ...paymentFields, bookingId });
      await ctx.db.insert("paymentRecords", {
        ...paymentFields,
        bookingId,
        installmentIndex: 1,
        status: "pending",
        refundedMinor: 0,
        disputedMinor: undefined,
      });
    });

    const result = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    expect(result.bookings).toEqual(baseline.bookings);
    expect(result.pendingPayments).toEqual(baseline.pendingPayments);
  });

  test("marks ticket totals truncated at the per-status limit", async () => {
    const { t, as, organizationId, orderFields } = await setupFinance();
    await t.run(async (ctx) => {
      for (let index = 0; index < 1_001; index++)
        await ctx.db.insert("ticketOrders", orderFields);
    });
    const result = await as("owner").query(api.finance.overview, {
      organizationId,
    });
    expect(result.tickets.ordersPaid).toBe(1_000);
    expect(result.tickets.grossMinor).toBe(1_000_000);
    expect(result.tickets.truncated).toBe(true);
  });
});

describe("finance authorization", () => {
  test.each(["owner", "manager", "finance"] as const)(
    "allows %s to read both public queries",
    async (role) => {
      const { as, organizationId } = await setupFinance();
      await expect(
        as(role).query(api.finance.overview, { organizationId }),
      ).resolves.toMatchObject({ currency: "usd" });
      await expect(
        as(role).query(api.finance.transactions, {
          organizationId,
          paginationOpts: { numItems: 2, cursor: null },
        }),
      ).resolves.toMatchObject({ page: [], isDone: true });
    },
  );

  test.each(["door", "outsider"] as const)(
    "rejects %s from both public queries",
    async (role) => {
      const { as, organizationId } = await setupFinance();
      await expect(
        as(role).query(api.finance.overview, { organizationId }),
      ).rejects.toThrow("Not permitted for this organization");
      await expect(
        as(role).query(api.finance.transactions, {
          organizationId,
          paginationOpts: { numItems: 2, cursor: null },
        }),
      ).rejects.toThrow("Not permitted for this organization");
    },
  );

  test("rejects unauthenticated reads", async () => {
    const { t, organizationId } = await setupFinance();
    await expect(
      t.query(api.finance.overview, { organizationId }),
    ).rejects.toThrow();
    await expect(
      t.query(api.finance.transactions, {
        organizationId,
        paginationOpts: { numItems: 2, cursor: null },
      }),
    ).rejects.toThrow();
  });
});

describe("ledger reads", () => {
  test("maps signed amounts and titles, preserves references, and hides platform events", async () => {
    const {
      t,
      as,
      organizationId,
      otherOrganizationId,
      bookingId,
      awaitingBookingId,
      orderFields,
    } = await setupFinance();
    const [orderId, secondOrderId] = await t.run(async (ctx) => [
      await ctx.db.insert("ticketOrders", orderFields),
      await ctx.db.insert("ticketOrders", orderFields),
    ]);
    const ids = await seedLedger(t, organizationId, [
      {
        kind: "charge",
        amountMinor: 10_000,
        occurredAt: 1,
        bookingId,
        stripeRef: "ch_finance",
      },
      {
        kind: "refund",
        amountMinor: -2_000,
        occurredAt: 2,
        bookingId: awaitingBookingId,
      },
      {
        kind: "ticket_sale",
        amountMinor: 1_100,
        occurredAt: 3,
        ticketOrderId: orderId,
      },
      {
        kind: "ticket_fee",
        amountMinor: 100,
        occurredAt: 4,
        ticketOrderId: orderId,
      },
      {
        kind: "ticket_refund",
        amountMinor: -275,
        occurredAt: 5,
        ticketOrderId: secondOrderId,
      },
      { kind: "dispute_hold", amountMinor: -300, occurredAt: 6, bookingId },
      {
        kind: "dispute_release",
        amountMinor: 300,
        occurredAt: 7,
        ticketOrderId: orderId,
      },
      {
        kind: "dispute_loss",
        amountMinor: -300,
        occurredAt: 8,
        bookingId,
        ticketOrderId: orderId,
      },
      { kind: "payout", amountMinor: -9_000, occurredAt: 9, bookingId },
      { kind: "commission", amountMinor: 1_000, occurredAt: 10, bookingId },
    ]);
    await seedLedger(t, otherOrganizationId, [
      { kind: "charge", amountMinor: 99_999, occurredAt: 11 },
    ]);
    const result = await as("finance").query(api.finance.transactions, {
      organizationId,
      paginationOpts: { numItems: 20, cursor: null },
    });
    expect(result.isDone).toBe(true);
    expect(
      result.page.map(({ id, amountMinor, label }) => ({
        id,
        amountMinor,
        label,
      })),
    ).toEqual([
      {
        id: ids[7],
        amountMinor: 300,
        label: "Dispute loss · Friday at the Hall",
      },
      { id: ids[6], amountMinor: 300, label: "Dispute release · Friday Live" },
      {
        id: ids[5],
        amountMinor: 300,
        label: "Dispute hold · Friday at the Hall",
      },
      { id: ids[4], amountMinor: -275, label: "Ticket refund · Friday Live" },
      { id: ids[3], amountMinor: -100, label: "EarPlug fee · Friday Live" },
      { id: ids[2], amountMinor: 1_100, label: "Ticket sale · Friday Live" },
      {
        id: ids[1],
        amountMinor: 2_000,
        label: "Booking refund · Friday at the Hall",
      },
      {
        id: ids[0],
        amountMinor: -10_000,
        label: "Booking payment · Friday at the Hall",
      },
    ]);
    expect(result.page[7]).toMatchObject({
      kind: "charge",
      currency: "usd",
      fundsState: "available",
      bookingId,
      stripeRef: "ch_finance",
      occurredAt: 1,
    });
    expect(result.page[5].ticketOrderId).toBe(orderId);
  });

  test("passes the source cursor through a shortened page without duplicates", async () => {
    const { t, as, organizationId } = await setupFinance();
    const ids = await seedLedger(t, organizationId, [
      { kind: "charge", amountMinor: 100, occurredAt: 1 },
      { kind: "refund", amountMinor: -50, occurredAt: 2 },
      { kind: "payout", amountMinor: -100, occurredAt: 3 },
      { kind: "ticket_sale", amountMinor: 200, occurredAt: 4 },
    ]);
    const first = await as("owner").query(api.finance.transactions, {
      organizationId,
      paginationOpts: { numItems: 2, cursor: null },
    });
    expect(first.page.map((row) => row.id)).toEqual([ids[3]]);
    expect(first.isDone).toBe(false);
    expect(first.continueCursor).toEqual(expect.any(String));
    expect(first.continueCursor.length).toBeGreaterThan(0);
    const second = await as("owner").query(api.finance.transactions, {
      organizationId,
      paginationOpts: { numItems: 2, cursor: first.continueCursor },
    });
    expect(second.isDone).toBe(true);
    expect(second.continueCursor).toEqual(expect.any(String));
    expect(second.continueCursor).not.toBe(first.continueCursor);
    const seen = [...first.page, ...second.page].map((row) => row.id);
    expect(seen).toEqual([ids[3], ids[1], ids[0]]);
    expect(new Set(seen).size).toBe(seen.length);
  });

  test("statements include both range boundaries and map rows in ascending order", async () => {
    const { t, as, organizationId, otherOrganizationId, bookingId } =
      await setupFinance();
    await seedLedger(t, organizationId, [
      { kind: "charge", amountMinor: 500, occurredAt: 9, bookingId },
      { kind: "charge", amountMinor: 400, occurredAt: 10, bookingId },
      { kind: "commission", amountMinor: 40, occurredAt: 15, bookingId },
      { kind: "refund", amountMinor: -100, occurredAt: 20, bookingId },
      { kind: "refund", amountMinor: -200, occurredAt: 21, bookingId },
    ]);
    await seedLedger(t, otherOrganizationId, [
      { kind: "charge", amountMinor: 9_999, occurredAt: 12 },
    ]);
    const { rows, truncated } = await t.query(
      internal.finance.ledgerRowsForStatement,
      { organizationId, fromMs: 10, toMs: 20 },
    );
    expect(truncated).toBe(false);
    expect(
      rows.map(({ occurredAt, amountMinor, label }) => ({
        occurredAt,
        amountMinor,
        label,
      })),
    ).toEqual([
      {
        occurredAt: 10,
        amountMinor: -400,
        label: "Booking payment · Friday at the Hall",
      },
      {
        occurredAt: 20,
        amountMinor: 100,
        label: "Booking refund · Friday at the Hall",
      },
    ]);
    const publicRows = await as("owner").query(api.finance.transactions, {
      organizationId,
      paginationOpts: { numItems: 10, cursor: null },
    });
    expect(rows).toEqual(
      publicRows.page
        .filter((row) => row.occurredAt >= 10 && row.occurredAt <= 20)
        .reverse(),
    );
  });

  test("marks statements truncated from 2000 source entries even when some kinds are hidden", async () => {
    const { t, organizationId } = await setupFinance();
    await seedLedger(
      t,
      organizationId,
      Array.from({ length: 2000 }, (_, index) => ({
        kind: index % 10 === 0 ? ("commission" as const) : ("ticket_sale" as const),
        amountMinor: 100,
        occurredAt: index,
      })),
    );

    const { rows, truncated } = await t.query(
      internal.finance.ledgerRowsForStatement,
      { organizationId, fromMs: 0, toMs: 1999 },
    );
    expect(rows).toHaveLength(1800);
    expect(truncated).toBe(true);
  });

  test("falls back when linked records or titles are missing", async () => {
    const {
      t,
      as,
      organizationId,
      bookingId,
      awaitingBookingId,
      opportunityId,
      gigId,
      orderFields,
    } = await setupFinance();
    const orderId = await t.run(
      async (ctx) => await ctx.db.insert("ticketOrders", orderFields),
    );
    await seedLedger(t, organizationId, [
      { kind: "charge", amountMinor: 100, occurredAt: 1, bookingId },
      {
        kind: "refund",
        amountMinor: -50,
        occurredAt: 2,
        bookingId: awaitingBookingId,
      },
      {
        kind: "ticket_sale",
        amountMinor: 200,
        occurredAt: 3,
        ticketOrderId: orderId,
      },
      {
        kind: "dispute_hold",
        amountMinor: -25,
        occurredAt: 4,
        ticketOrderId: orderId,
      },
    ]);
    await t.run(async (ctx) => {
      await ctx.db.delete(bookingId);
      await ctx.db.delete(opportunityId);
      await ctx.db.delete(gigId);
    });
    const read = () =>
      as("owner").query(api.finance.transactions, {
        organizationId,
        paginationOpts: { numItems: 10, cursor: null },
      });
    expect((await read()).page.map((row) => row.label)).toEqual([
      "Dispute hold · transaction",
      "Ticket sale",
      "Booking refund",
      "Booking payment",
    ]);
    await t.run(async (ctx) => {
      await ctx.db.delete(orderId);
    });
    expect((await read()).page.map((row) => row.label)).toEqual([
      "Dispute hold · transaction",
      "Ticket sale",
      "Booking refund",
      "Booking payment",
    ]);
  });
});

test("upsertSnapshot inserts once and patches the same organization snapshot", async () => {
  const { t, organizationId } = await setupFinance();
  expect(
    await t.query(internal.finance.financeContext, { organizationId }),
  ).toEqual({
    stripeAccountId: "acct_finance",
    snapshotStripeAccountId: undefined,
    snapshot: null,
  });
  const first = {
    organizationId,
    stripeAccountId: "acct_finance",
    availableMinor: 5_000,
    pendingMinor: 2_000,
    currency: "usd",
    fetchedAt: 3_000,
  };
  expect(await t.mutation(internal.finance.upsertSnapshot, first)).toBeNull();
  const readSnapshots = () =>
    t.run(
      async (ctx) =>
        await ctx.db
          .query("financeSnapshots")
          .withIndex("by_organizationId", (q) =>
            q.eq("organizationId", organizationId),
          )
          // Two rows suffice to detect an accidental duplicate for this organization.
          .take(2),
    );
  const inserted = await readSnapshots();
  expect(inserted).toHaveLength(1);
  expect(inserted[0]).toMatchObject(first);
  const second = {
    ...first,
    stripeAccountId: "acct_refreshed",
    availableMinor: 6_000,
    pendingMinor: 1_000,
    currency: "eur",
    fetchedAt: 4_000,
  };
  expect(await t.mutation(internal.finance.upsertSnapshot, second)).toBeNull();
  const updated = await readSnapshots();
  expect(updated).toHaveLength(1);
  expect(updated[0]).toMatchObject({ ...second, _id: inserted[0]._id });
  expect(
    await t.query(internal.finance.financeContext, { organizationId }),
  ).toEqual({
    // Account context comes from private details, independently of snapshot data.
    stripeAccountId: "acct_finance",
    snapshotStripeAccountId: "acct_refreshed",
    snapshot: {
      availableMinor: 6_000,
      pendingMinor: 1_000,
      currency: "eur",
      fetchedAt: 4_000,
    },
  });
});

describe("finance math", () => {
  test("rounds each organizer refund separately and handles zero-total orders", () => {
    const roundedOrder = {
      status: "refunded" as const,
      subtotalMinor: 1,
      feeMinor: 1,
      totalMinor: 2,
      refundedMinor: 1,
    };
    expect(
      ticketTotals([
        roundedOrder,
        roundedOrder,
        {
          status: "paid",
          subtotalMinor: 0,
          feeMinor: 0,
          totalMinor: 0,
          refundedMinor: 0,
        },
      ]),
    ).toEqual({
      ordersPaid: 1,
      grossMinor: 2,
      feeMinor: 2,
      refundedMinor: 2,
      refundedOrgMinor: 2,
      netMinor: 0,
      estimatedProcessingMinor: 90,
    });
  });

  test("computes dues only for payable bookings and reports gross settled payments", () => {
    const record = {
      amountMinor: 1_000,
      refundedMinor: 200,
      disputedMinor: 50,
    };
    expect(
      bookingTotals([
        { record: { ...record, status: "paid" }, bookingStatus: "confirmed" },
        {
          record: { ...record, status: "partially_refunded" },
          bookingStatus: "disputed",
        },
        {
          record: { ...record, status: "refunded", refundedMinor: 1_000 },
          bookingStatus: "refunded",
        },
        { record: { ...record, status: "failed" }, bookingStatus: "confirmed" },
        {
          record: { ...record, status: "expired" },
          bookingStatus: "confirmed",
        },
        {
          record: { status: "pending", amountMinor: 500, refundedMinor: 0 },
          bookingStatus: "awaiting_payment",
        },
        {
          record: {
            status: "checkout_open",
            amountMinor: 700,
            refundedMinor: 0,
          },
          bookingStatus: "confirmed",
        },
        {
          record: { status: "pending", amountMinor: 900, refundedMinor: 0 },
          bookingStatus: "cancelled_by_artist",
        },
      ]),
    ).toEqual({
      dueMinor: 1_200,
      paidMinor: 3_000,
      refundedMinor: 1_800,
      disputedMinor: 250,
    });
    expect(bookingTotals([])).toEqual({
      dueMinor: 0,
      paidMinor: 0,
      refundedMinor: 0,
      disputedMinor: 0,
    });
    expect(ticketTotals([])).toEqual({
      ordersPaid: 0,
      grossMinor: 0,
      feeMinor: 0,
      refundedMinor: 0,
      refundedOrgMinor: 0,
      netMinor: 0,
      estimatedProcessingMinor: 0,
    });
  });

  test.each([
    ["charge", 100, false, -100],
    ["charge", -100, false, 100],
    ["refund", -100, false, 100],
    ["refund", 100, false, -100],
    ["ticket_sale", 100, false, 100],
    ["ticket_sale", -100, false, -100],
    ["ticket_fee", 100, false, -100],
    ["ticket_fee", -100, false, 100],
    ["ticket_refund", 100, false, 100],
    ["ticket_refund", -100, false, -100],
    ["dispute_hold", -100, false, -100],
    ["dispute_hold", -100, true, 100],
    ["dispute_release", 100, false, 100],
    ["dispute_release", 100, true, -100],
    ["dispute_loss", -100, false, -100],
    ["dispute_loss", -100, true, 100],
    ["commission", 100, false, null],
    ["payout", -100, false, null],
    ["transfer_reversal", 100, false, null],
    ["dispute_fee", -100, false, null],
    ["unknown", 100, false, null],
  ] as const)(
    "maps %s amount %i with booking=%s to %s",
    (kind, amountMinor, hasBooking, expected) => {
      expect(
        organizationLedgerAmount({
          kind,
          amountMinor,
          bookingId: hasBooking ? ("booking" as Id<"bookings">) : undefined,
        }),
      ).toBe(expected);
    },
  );

  test("uses readable label fallbacks and opportunity-first dispute titles", () => {
    for (const [kind, label] of [
      ["charge", "Booking payment"],
      ["refund", "Booking refund"],
      ["ticket_sale", "Ticket sale"],
      ["ticket_fee", "EarPlug fee"],
      ["ticket_refund", "Ticket refund"],
    ])
      expect(ledgerLabel(kind, {})).toBe(label);
    for (const [kind, prefix] of [
      ["dispute_hold", "Dispute hold"],
      ["dispute_release", "Dispute release"],
      ["dispute_loss", "Dispute loss"],
    ]) {
      expect(ledgerLabel(kind, {})).toBe(`${prefix} · transaction`);
      expect(ledgerLabel(kind, { gigTitle: "Gig" })).toBe(`${prefix} · Gig`);
      expect(
        ledgerLabel(kind, { opportunityTitle: "Booking", gigTitle: "Gig" }),
      ).toBe(`${prefix} · Booking`);
    }
    expect(ledgerLabel("payout", {})).toBe("payout");
  });
});
