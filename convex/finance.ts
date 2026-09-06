import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v, type Infer } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalMutation,
  internalQuery,
  query,
  type QueryCtx,
} from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";
import {
  bookingTotals,
  ledgerLabel,
  organizationLedgerAmount,
  ticketTotals,
} from "./lib/financeMath";
import {
  bookingStatusValidator,
  fundsStateValidator,
  ledgerKindValidator,
} from "./schema";

const snapshotValidator = v.object({
  availableMinor: v.number(),
  pendingMinor: v.number(),
  currency: v.string(),
  fetchedAt: v.number(),
});

export const financeOverviewValidator = v.object({
  stripeReady: v.boolean(),
  snapshot: v.union(snapshotValidator, v.null()),
  bookings: v.object({
    dueMinor: v.number(),
    paidMinor: v.number(),
    refundedMinor: v.number(),
    disputedMinor: v.number(),
    activeCount: v.number(),
  }),
  tickets: v.object({
    ordersPaid: v.number(),
    grossMinor: v.number(),
    feeMinor: v.number(),
    refundedMinor: v.number(),
    refundedOrgMinor: v.number(),
    netMinor: v.number(),
    estimatedProcessingMinor: v.number(),
    truncated: v.boolean(),
  }),
  pendingPayments: v.array(
    v.object({
      bookingId: v.id("bookings"),
      paymentRecordId: v.id("paymentRecords"),
      opportunityTitle: v.string(),
      label: v.string(),
      amountMinor: v.number(),
      dueAt: v.number(),
    }),
  ),
  currency: v.literal("usd"),
});

export const transactionValidator = v.object({
  id: v.string(),
  kind: ledgerKindValidator,
  amountMinor: v.number(),
  currency: v.string(),
  fundsState: fundsStateValidator,
  occurredAt: v.number(),
  label: v.string(),
  bookingId: v.optional(v.id("bookings")),
  ticketOrderId: v.optional(v.id("ticketOrders")),
  stripeRef: v.optional(v.string()),
});

function snapshotPayload(row: Doc<"financeSnapshots"> | null) {
  if (!row) return null;
  const { availableMinor, pendingMinor, currency, fetchedAt } = row;
  return { availableMinor, pendingMinor, currency, fetchedAt };
}

async function collectBookingsWithRecords(
  ctx: QueryCtx,
  organizationId: Id<"organizations">,
) {
  const statuses: Infer<typeof bookingStatusValidator>[] = [
    "awaiting_payment",
    "confirmed",
    "completed",
    "paid",
    "disputed",
    "refunded",
    "cancelled_by_organizer",
    "cancelled_by_artist",
    "force_majeure",
  ];
  const bookings = (
    await Promise.all(
      statuses.map((status) =>
        ctx.db
          .query("bookings")
          .withIndex("by_organizationId_and_status_and_startsAt", (q) =>
            q.eq("organizationId", organizationId).eq("status", status),
          )
          // Bound the overview to 200 bookings per financial status.
          .take(200),
      ),
    )
  ).flat();
  const records = (
    await Promise.all(
      bookings.map(async (booking) => {
        const payments = await ctx.db
          .query("paymentRecords")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
          // Bound installment history to 50 payment records per booking.
          .take(50);
        return payments.map((record) => ({
          record,
          booking,
          bookingStatus: booking.status,
        }));
      }),
    )
  ).flat();
  return { bookings, records };
}

export const overview = query({
  args: { organizationId: v.id("organizations") },
  returns: financeOverviewValidator,
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
      "manager",
      "finance",
    ]);
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    const snapshot = await ctx.db
      .query("financeSnapshots")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    const { bookings, records } = await collectBookingsWithRecords(
      ctx,
      args.organizationId,
    );
    const [paidOrders, refundedOrders] = await Promise.all(
      (["paid", "refunded"] as const).map(async (status) => {
        const orders = await ctx.db
          .query("ticketOrders")
          .withIndex("by_organizationId_and_status", (q) =>
            q.eq("organizationId", args.organizationId).eq("status", status),
          )
          // Cap each status at 1,000 orders and expose possible truncation.
          .take(1000);
        // Index equality guarantees this narrower status for the pure helper.
        return orders.map((order) => ({ ...order, status }));
      }),
    );
    const pendingPayments = await Promise.all(
      records
        .filter(
          ({ record, bookingStatus }) =>
            (record.status === "pending" ||
              record.status === "checkout_open") &&
            (bookingStatus === "awaiting_payment" ||
              bookingStatus === "confirmed"),
        )
        .sort((a, b) => a.record.dueAt - b.record.dueAt)
        .slice(0, 20)
        .map(async ({ booking, record }) => {
          const opportunity = await ctx.db.get(booking.opportunityId);
          return {
            bookingId: booking._id,
            paymentRecordId: record._id,
            opportunityTitle: opportunity?.title ?? "Booking",
            label: record.label,
            amountMinor: record.amountMinor,
            dueAt: record.dueAt,
          };
        }),
    );
    return {
      stripeReady:
        details?.stripeChargesEnabled === true &&
        details?.stripeDetailsSubmitted === true,
      snapshot: snapshotPayload(snapshot),
      bookings: {
        ...bookingTotals(records),
        // Counts bookings with financial activity, including terminal statuses.
        activeCount: bookings.length,
      },
      tickets: {
        ...ticketTotals([...paidOrders, ...refundedOrders]),
        truncated: paidOrders.length === 1000 || refundedOrders.length === 1000,
      },
      pendingPayments,
      currency: "usd" as const,
    };
  },
});

type LedgerTitleMemo = {
  bookings: Map<Id<"bookings">, string | undefined>;
  opportunities: Map<Id<"talentOpportunities">, string | undefined>;
  orders: Map<Id<"ticketOrders">, string | undefined>;
  gigs: Map<Id<"gigs">, string | undefined>;
};

async function ledgerEntryToTransaction(
  ctx: QueryCtx,
  entry: Doc<"ledgerEntries">,
  memo: LedgerTitleMemo,
): Promise<Infer<typeof transactionValidator> | null> {
  const amountMinor = organizationLedgerAmount(entry);
  if (amountMinor === null) return null;

  let opportunityTitle: string | undefined;
  if (entry.bookingId) {
    if (!memo.bookings.has(entry.bookingId)) {
      const booking = await ctx.db.get(entry.bookingId);
      if (booking && !memo.opportunities.has(booking.opportunityId)) {
        const opportunity = await ctx.db.get(booking.opportunityId);
        memo.opportunities.set(booking.opportunityId, opportunity?.title);
      }
      memo.bookings.set(
        entry.bookingId,
        booking ? memo.opportunities.get(booking.opportunityId) : undefined,
      );
    }
    opportunityTitle = memo.bookings.get(entry.bookingId);
  }

  let gigTitle: string | undefined;
  if (entry.ticketOrderId) {
    if (!memo.orders.has(entry.ticketOrderId)) {
      const order = await ctx.db.get(entry.ticketOrderId);
      if (order && !memo.gigs.has(order.gigId)) {
        const gig = await ctx.db.get(order.gigId);
        memo.gigs.set(order.gigId, gig?.title);
      }
      memo.orders.set(
        entry.ticketOrderId,
        order ? memo.gigs.get(order.gigId) : undefined,
      );
    }
    gigTitle = memo.orders.get(entry.ticketOrderId);
  }

  return {
    id: entry._id,
    kind: entry.kind,
    amountMinor,
    currency: entry.currency,
    fundsState: entry.fundsState,
    occurredAt: entry.occurredAt,
    label: ledgerLabel(entry.kind, { opportunityTitle, gigTitle }),
    bookingId: entry.bookingId,
    ticketOrderId: entry.ticketOrderId,
    stripeRef: entry.stripeRef,
  };
}

async function mapLedgerRows(ctx: QueryCtx, entries: Doc<"ledgerEntries">[]) {
  const memo: LedgerTitleMemo = {
    bookings: new Map(),
    opportunities: new Map(),
    orders: new Map(),
    gigs: new Map(),
  };
  const rows: Infer<typeof transactionValidator>[] = [];
  // Sequential mapping fills both memo levels before another entry can use them.
  // Map.has also remembers missing records, avoiding repeated failed lookups.
  for (const entry of entries) {
    const row = await ledgerEntryToTransaction(ctx, entry, memo);
    if (row !== null) rows.push(row);
  }
  return rows;
}

export const transactions = query({
  args: {
    organizationId: v.id("organizations"),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(transactionValidator),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
      "manager",
      "finance",
    ]);
    const result = await ctx.db
      .query("ledgerEntries")
      .withIndex("by_organizationId_and_occurredAt", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .order("desc")
      .paginate(args.paginationOpts);
    const page = await mapLedgerRows(ctx, result.page);
    return { ...result, page };
  },
});

export const ledgerRowsForStatement = internalQuery({
  args: {
    organizationId: v.id("organizations"),
    fromMs: v.number(),
    toMs: v.number(),
  },
  returns: v.array(transactionValidator),
  handler: async (ctx, args) => {
    const entries = await ctx.db
      .query("ledgerEntries")
      .withIndex("by_organizationId_and_occurredAt", (q) =>
        q
          .eq("organizationId", args.organizationId)
          .gte("occurredAt", args.fromMs)
          .lte("occurredAt", args.toMs),
      )
      .order("asc")
      // Statements include at most 2,000 source ledger entries in the range.
      .take(2000);
    return await mapLedgerRows(ctx, entries);
  },
});

export const financeContext = internalQuery({
  args: { organizationId: v.id("organizations") },
  returns: v.object({
    stripeAccountId: v.optional(v.string()),
    snapshot: v.union(snapshotValidator, v.null()),
  }),
  handler: async (ctx, args) => {
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    const snapshot = await ctx.db
      .query("financeSnapshots")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    return {
      stripeAccountId: details?.stripeAccountId,
      snapshot: snapshotPayload(snapshot),
    };
  },
});

export const upsertSnapshot = internalMutation({
  args: {
    organizationId: v.id("organizations"),
    stripeAccountId: v.string(),
    ...snapshotValidator.fields,
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("financeSnapshots")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, args);
    } else {
      await ctx.db.insert("financeSnapshots", { ...args });
    }
    return null;
  },
});
