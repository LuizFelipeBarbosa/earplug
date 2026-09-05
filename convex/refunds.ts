import { type Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import {
  internalAction,
  internalMutation,
  internalQuery,
  query,
  type QueryCtx,
} from "./_generated/server";
import { isPlatformAdmin, organizationMembershipFor } from "./lib/authz";
import { computeCancellationSettlement } from "./lib/cancellationSettlement";
import { requireUser } from "./lib/helpers";
import { appendLedgerEntry } from "./lib/ledger";
import {
  assertPaymentRecordTransition,
  assertRefundTransition,
} from "./lib/paymentStatus";
import { stripeIdempotencyKey, stripeRequest } from "./lib/stripeClient";
import schema, {
  cancellationTemplateValidator,
  refundReasonValidator,
  refundStatusValidator,
} from "./schema";

// Settlement mutations always insert refunds/payouts regardless of PAYMENTS_ENABLED
// so obligations are retained. Only executeRefund/reverseTransfer call Stripe;
// POST throws while disabled. markRefundFailed retries refunds hourly, up to
// three total attempts. Transfer reversals are best-effort and do not retry.
const cancellationSideValidator = v.union(
  v.literal("organizer"),
  v.literal("artist"),
);
const refundValidator = schema.tables.refunds.validator.extend({
  _id: v.id("refunds"),
  _creationTime: v.number(),
});
const refundContextValidator = v.object({
  refund: refundValidator,
  stripePaymentIntentId: v.optional(v.string()),
  bookingId: v.id("bookings"),
  currency: v.string(),
  organizationId: v.id("organizations"),
  bandId: v.id("bands"),
});

async function requireCancellationParty(
  ctx: QueryCtx,
  booking: Doc<"bookings">,
) {
  const user = await requireUser(ctx);
  const [membership, bandMembership, platformAdmin] = await Promise.all([
    organizationMembershipFor(ctx, booking.organizationId, user._id),
    ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", booking.bandId).eq("userId", user._id),
      )
      .unique(),
    isPlatformAdmin(ctx, user._id),
  ]);
  const canOrganizer =
    membership?.role === "owner" ||
    membership?.role === "manager" ||
    platformAdmin;
  const canArtist = bandMembership?.role === "admin";
  if (!canOrganizer && !canArtist) {
    throw new Error(
      "Not permitted to view this booking's cancellation terms",
    );
  }
  return { canOrganizer, canArtist };
}

export const previewCancellation = query({
  args: {
    bookingId: v.id("bookings"),
    as: v.optional(cancellationSideValidator),
    now: v.number(),
  },
  returns: v.object({
    refundMinor: v.number(),
    forfeitedMinor: v.number(),
    artistPayoutMinor: v.number(),
    paidMinor: v.number(),
    shareBps: v.number(),
    template: cancellationTemplateValidator,
    cancelledBy: cancellationSideValidator,
  }),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const { canOrganizer, canArtist } = await requireCancellationParty(
      ctx,
      booking,
    );
    let side: "organizer" | "artist" = canOrganizer
      ? "organizer"
      : "artist";
    if (args.as === "organizer" && canOrganizer) {
      side = "organizer";
    } else if (args.as === "artist" && canArtist) {
      side = "artist";
    }
    const settlement = await computeCancellationSettlement(ctx, {
      bookingId: booking._id,
      template: booking.cancellationTemplate,
      startsAt: booking.startsAt,
      cancelledBy: side,
      artistNetMinor: booking.artistNetMinor,
      commissionMinor: booking.commissionMinor,
      now: args.now,
    });
    return {
      refundMinor: settlement.refundMinor,
      forfeitedMinor: settlement.forfeitedMinor,
      artistPayoutMinor: settlement.artistPayoutMinor,
      paidMinor: settlement.paidMinor,
      shareBps: settlement.shareBps,
      template: booking.cancellationTemplate,
      cancelledBy: side,
    };
  },
});

export const refundsForBooking = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(
    v.object({
      _id: v.id("refunds"),
      paymentRecordId: v.id("paymentRecords"),
      amountMinor: v.number(),
      currency: v.string(),
      reason: refundReasonValidator,
      status: refundStatusValidator,
      stripeRefundId: v.optional(v.string()),
      createdAt: v.number(),
    }),
  ),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    await requireCancellationParty(ctx, booking);
    const rows = await ctx.db
      .query("refunds")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", args.bookingId))
      .take(50);
    return rows.map((row) => ({
      _id: row._id,
      paymentRecordId: row.paymentRecordId,
      amountMinor: row.amountMinor,
      currency: row.currency,
      reason: row.reason,
      status: row.status,
      stripeRefundId: row.stripeRefundId,
      createdAt: row.createdAt,
    }));
  },
});

export const loadRefundContext = internalQuery({
  args: { refundId: v.id("refunds") },
  returns: refundContextValidator,
  handler: async (ctx, args) => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund) throw new Error("Refund not found");
    const [record, booking] = await Promise.all([
      ctx.db.get(refund.paymentRecordId),
      ctx.db.get(refund.bookingId),
    ]);
    if (!record) throw new Error("Payment record not found");
    if (!booking) throw new Error("Booking not found");
    return {
      refund,
      stripePaymentIntentId: record.stripePaymentIntentId,
      bookingId: booking._id,
      currency: booking.currency,
      organizationId: booking.organizationId,
      bandId: booking.bandId,
    };
  },
});

export const executeRefund = internalAction({
  args: { refundId: v.id("refunds"), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const context: Infer<typeof refundContextValidator> =
      await ctx.runQuery(internal.refunds.loadRefundContext, {
        refundId: args.refundId,
      });
    const { refund, stripePaymentIntentId } = context;
    if (refund.status !== "pending") return null;
    try {
      const response = await stripeRequest<{ id: string }>(
        "POST",
        "/v1/refunds",
        {
          payment_intent: stripePaymentIntentId,
          amount: refund.amountMinor,
          metadata: {
            bookingId: refund.bookingId,
            refundId: refund._id,
            reason: refund.reason,
          },
        },
        {
          idempotencyKey: stripeIdempotencyKey(
            "refund",
            refund._id,
            args.attempt,
          ),
        },
      );
      await ctx.runMutation(internal.refunds.markRefundSucceeded, {
        refundId: refund._id,
        stripeRefundId: response.id,
      });
    } catch (error) {
      console.error(`Could not execute refund ${refund._id}`, error);
      await ctx.runMutation(internal.refunds.markRefundFailed, {
        refundId: refund._id,
        attempt: args.attempt,
      });
    }
    return null;
  },
});

export const markRefundSucceeded = internalMutation({
  args: { refundId: v.id("refunds"), stripeRefundId: v.string() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund || refund.status === "succeeded") return null;
    assertRefundTransition(refund.status, "succeeded");
    const now = Date.now();
    await ctx.db.patch(refund._id, {
      status: "succeeded",
      stripeRefundId: args.stripeRefundId,
      updatedAt: now,
    });
    const record = await ctx.db.get(refund.paymentRecordId);
    if (!record) throw new Error("Payment record not found");
    const newRefundedMinor = record.refundedMinor + refund.amountMinor;
    const newStatus =
      newRefundedMinor >= record.amountMinor
        ? "refunded"
        : "partially_refunded";
    assertPaymentRecordTransition(record.status, newStatus);
    await ctx.db.patch(record._id, {
      refundedMinor: newRefundedMinor,
      status: newStatus,
      updatedAt: now,
    });
    const booking = await ctx.db.get(refund.bookingId);
    if (!booking) throw new Error("Booking not found");
    await ctx.db.patch(booking._id, {
      refundedMinor: (booking.refundedMinor ?? 0) + refund.amountMinor,
      updatedAt: now,
    });
    await appendLedgerEntry(ctx, {
      idempotencyKey: `refund:${args.stripeRefundId}`,
      kind: "refund",
      amountMinor: -refund.amountMinor,
      currency: refund.currency,
      fundsState: "refunded",
      bookingId: refund.bookingId,
      organizationId: booking.organizationId,
      bandId: booking.bandId,
      stripeRef: args.stripeRefundId,
      occurredAt: now,
    });

    // A paid completion transfer is entitled only to its proportional share of
    // the charge left unrefunded. Reverse the excess through an action because
    // Stripe HTTP calls cannot run inside this mutation.
    const payouts = await ctx.db
      .query("payouts")
      .withIndex("by_paymentRecordId", (q) =>
        q.eq("paymentRecordId", record._id),
      )
      .take(50);
    const payout = payouts.find((row) => row.status === "paid");
    if (payout) {
      const entitledMinor = Math.floor(
        (payout.amountMinor * (record.amountMinor - newRefundedMinor)) /
          record.amountMinor,
      );
      if (payout.amountMinor > entitledMinor) {
        await ctx.scheduler.runAfter(0, internal.refunds.reverseTransfer, {
          payoutId: payout._id,
          reversalMinor: payout.amountMinor - entitledMinor,
        });
      }
    }
    return null;
  },
});

export const loadTransferContext = internalQuery({
  args: { payoutId: v.id("payouts") },
  returns: v.object({ stripeTransferId: v.optional(v.string()) }),
  handler: async (ctx, args) => {
    const payout = await ctx.db.get(args.payoutId);
    if (!payout) throw new Error("Payout not found");
    return { stripeTransferId: payout.stripeTransferId };
  },
});

export const reverseTransfer = internalAction({
  args: { payoutId: v.id("payouts"), reversalMinor: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    if (args.reversalMinor <= 0) return null;
    try {
      const payout: { stripeTransferId?: string } = await ctx.runQuery(
        internal.refunds.loadTransferContext,
        { payoutId: args.payoutId },
      );
      if (!payout.stripeTransferId) return null;
      const response = await stripeRequest<{ id: string }>(
        "POST",
        `/v1/transfers/${payout.stripeTransferId}/reversals`,
        { amount: args.reversalMinor },
      );
      await ctx.runMutation(internal.refunds.markTransferReversed, {
        payoutId: args.payoutId,
        reversalMinor: args.reversalMinor,
        stripeTransferReversalId: response.id,
      });
    } catch (error) {
      console.error(
        `Could not reverse transfer for payout ${args.payoutId}`,
        error,
      );
    }
    return null;
  },
});

export const markTransferReversed = internalMutation({
  args: {
    payoutId: v.id("payouts"),
    reversalMinor: v.number(),
    stripeTransferReversalId: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const payout = await ctx.db.get(args.payoutId);
    if (!payout) throw new Error("Payout not found");
    const now = Date.now();
    // Partial reversals leave the completed payout in its terminal paid state.
    await ctx.db.patch(payout._id, {
      stripeTransferReversalId: args.stripeTransferReversalId,
      updatedAt: now,
    });
    await appendLedgerEntry(ctx, {
      idempotencyKey: `transfer_reversal:${args.stripeTransferReversalId}`,
      kind: "transfer_reversal",
      amountMinor: -args.reversalMinor,
      currency: payout.currency,
      fundsState: "refunded",
      bookingId: payout.bookingId,
      bandId: payout.bandId,
      occurredAt: now,
    });
    return null;
  },
});

export const refundLatePayment = internalMutation({
  args: { paymentRecordId: v.id("paymentRecords"), eventId: v.string() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const record = await ctx.db.get(args.paymentRecordId);
    if (!record) return null;
    const refunds = await ctx.db
      .query("refunds")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", record.bookingId))
      .take(50);
    if (
      refunds.some(
        (row) =>
          row.paymentRecordId === record._id &&
          row.reason === "late_payment",
      )
    )
      return null;
    const amountMinor = record.amountMinor - record.refundedMinor;
    if (amountMinor <= 0) return null;
    const now = Date.now();
    const refundId = await ctx.db.insert("refunds", {
      bookingId: record.bookingId,
      paymentRecordId: record._id,
      amountMinor,
      currency: record.currency,
      reason: "late_payment",
      status: "pending",
      stripeEventId: args.eventId,
      createdAt: now,
      updatedAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.refunds.executeRefund, {
      refundId,
      attempt: 0,
    });
    return null;
  },
});

export const markRefundFailed = internalMutation({
  args: { refundId: v.id("refunds"), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const refund = await ctx.db.get(args.refundId);
    if (!refund || refund.status === "succeeded") return null;
    const now = Date.now();
    if (refund.status === "pending") {
      assertRefundTransition("pending", "failed");
      await ctx.db.patch(refund._id, { status: "failed", updatedAt: now });
    }
    if (args.attempt < 2) {
      assertRefundTransition("failed", "pending");
      await ctx.db.patch(refund._id, { status: "pending", updatedAt: now });
      await ctx.scheduler.runAfter(
        60 * 60 * 1000,
        internal.refunds.executeRefund,
        {
          refundId: refund._id,
          attempt: args.attempt + 1,
        },
      );
    }
    return null;
  },
});
