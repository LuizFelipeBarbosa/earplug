import { internal } from "../_generated/api";
import type { MutationCtx } from "../_generated/server";
import {
  assertBookingTransition,
  BOOKING_LIVE_STATUSES,
} from "../lib/bookingStatus";
import { appendLedgerEntry } from "../lib/ledger";
import {
  assertPaymentRecordTransition,
  assertPayoutTransition,
  assertRefundTransition,
} from "../lib/paymentStatus";
import { reversibleMinor } from "../payouts";
import { applyRefundSucceeded } from "../refunds";
import type {
  StripeEvent,
  StripeEventHandler,
  StripeHandlerMap,
} from "../stripeWebhook";

async function paymentRecordForDispute(
  ctx: MutationCtx,
  event: StripeEvent,
) {
  const paymentIntent = event.data.object.payment_intent;
  const paymentIntentId =
    typeof paymentIntent === "string" ? paymentIntent : paymentIntent?.id;
  const record =
    typeof paymentIntentId === "string"
      ? await ctx.db
          .query("paymentRecords")
          .withIndex("by_stripePaymentIntentId", (q) =>
            q.eq("stripePaymentIntentId", paymentIntentId),
          )
          .unique()
      : null;
  if (!record) {
    console.log(
      `${event.type} ignored: no payment record for intent ${paymentIntentId}`,
    );
  }
  return record;
}

const disputeCreated: StripeEventHandler = async (ctx, event) => {
  const record = await paymentRecordForDispute(ctx, event);
  if (!record) return;
  const dispute = event.data.object;
  const disputeId = dispute.id;
  const disputedMinor =
    typeof dispute.amount === "number"
      ? dispute.amount
      : record.amountMinor;
  const now = Date.now();
  await ctx.db.patch(record._id, {
    stripeDisputeId: disputeId,
    disputedMinor,
    updatedAt: now,
  });
  const booking = await ctx.db.get(record.bookingId);
  if (!booking) throw new Error("Booking not found");
  const reasons = [...(booking.payoutHoldReasons ?? [])];
  if (!reasons.includes("dispute")) reasons.push("dispute");
  if (BOOKING_LIVE_STATUSES.includes(booking.status)) {
    assertBookingTransition(booking.status, "disputed");
    await ctx.db.patch(booking._id, {
      status: "disputed",
      disputedFromStatus: booking.status,
      payoutHoldReasons: reasons,
      payoutHold: true,
      revision: booking.revision + 1,
      updatedAt: now,
    });
  } else if (booking.status === "disputed") {
    await ctx.db.patch(booking._id, {
      payoutHoldReasons: reasons,
      payoutHold: true,
      updatedAt: now,
    });
  }
  await appendLedgerEntry(ctx, {
    idempotencyKey: `dispute-hold:${disputeId}`,
    kind: "dispute_hold",
    amountMinor: -disputedMinor,
    currency: record.currency,
    fundsState: "disputed",
    bookingId: record.bookingId,
    organizationId: booking.organizationId,
    bandId: booking.bandId,
    stripeRef: disputeId,
    occurredAt: now,
  });
  const rows = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
    .take(50);
  for (const row of rows) {
    if (row.status !== "scheduled") continue;
    assertPayoutTransition("scheduled", "held");
    await ctx.db.patch(row._id, {
      status: "held",
      holdReason: "dispute",
      updatedAt: now,
    });
  }
};

const disputeClosed: StripeEventHandler = async (ctx, event) => {
  const record = await paymentRecordForDispute(ctx, event);
  if (!record) return;
  const dispute = event.data.object;
  const disputeId = dispute.id;
  const outcome = dispute.status;
  if (outcome !== "won" && outcome !== "lost") {
    console.log(
      `charge.dispute.closed ignored: dispute ${disputeId} is ${outcome}`,
    );
    return;
  }
  const booking = await ctx.db.get(record.bookingId);
  if (!booking) throw new Error("Booking not found");
  if (
    booking.status !== "disputed" ||
    (outcome === "won" && !booking.disputedFromStatus)
  ) {
    console.log(
      `charge.dispute.closed ignored: nothing to resolve for ${disputeId}`,
    );
    return;
  }
  const disputedMinor = record.disputedMinor ?? record.amountMinor;
  const now = Date.now();
  const ledgerFields = {
    currency: record.currency,
    bookingId: booking._id,
    organizationId: booking.organizationId,
    bandId: booking.bandId,
    stripeRef: disputeId,
    occurredAt: now,
  };
  const rows = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
    .take(50);
  if (outcome === "won") {
    const status = booking.disputedFromStatus!;
    assertBookingTransition("disputed", status);
    const payoutHoldReasons = (booking.payoutHoldReasons ?? []).filter(
      (reason) => reason !== "dispute",
    );
    await ctx.db.patch(booking._id, {
      status,
      disputedFromStatus: undefined,
      payoutHoldReasons,
      payoutHold: payoutHoldReasons.length > 0,
      revision: booking.revision + 1,
      updatedAt: now,
    });
    await appendLedgerEntry(ctx, {
      ...ledgerFields,
      idempotencyKey: `dispute-release:${disputeId}`,
      kind: "dispute_release",
      amountMinor: disputedMinor,
      fundsState: "available",
    });
    for (const row of rows) {
      if (row.status !== "held" || row.holdReason !== "dispute") continue;
      assertPayoutTransition("held", "scheduled");
      await ctx.db.patch(row._id, { status: "scheduled", updatedAt: now });
      await ctx.scheduler.runAfter(0, internal.payouts.releasePayout, {
        payoutId: row._id,
      });
    }
    return;
  }

  const transactions: unknown = dispute.balance_transactions;
  const fees = Array.isArray(transactions)
    ? transactions.flatMap((entry: unknown) =>
        typeof entry === "object" &&
        entry !== null &&
        "fee" in entry &&
        typeof entry.fee === "number"
          ? [entry.fee]
          : [],
      )
    : [];
  const fee =
    fees.length > 0 ? fees.reduce((sum, value) => sum + value, 0) : 0;
  if (fees.length === 0) {
    console.warn(
      `Dispute ${disputeId}: fee data unavailable; recorded a $0 fee for later reconciliation`,
    );
  }
  assertBookingTransition("disputed", "refunded");
  await ctx.db.patch(booking._id, {
    status: "refunded",
    disputedFromStatus: undefined,
    refundedMinor: (booking.refundedMinor ?? 0) + disputedMinor,
    revision: booking.revision + 1,
    updatedAt: now,
  });
  if (record.status !== "refunded") {
    assertPaymentRecordTransition(record.status, "refunded");
    await ctx.db.patch(record._id, {
      status: "refunded",
      refundedMinor: record.amountMinor,
      updatedAt: now,
    });
  }
  await appendLedgerEntry(ctx, {
    ...ledgerFields,
    idempotencyKey: `dispute-loss:${disputeId}`,
    kind: "dispute_loss",
    amountMinor: -disputedMinor,
    fundsState: "refunded",
  });
  await appendLedgerEntry(ctx, {
    ...ledgerFields,
    idempotencyKey: `dispute-fee:${disputeId}`,
    kind: "dispute_fee",
    amountMinor: -fee,
    fundsState: "refunded",
  });
  for (const row of rows) {
    if (row.paymentRecordId !== record._id || row.status !== "paid")
      continue;
    const reversalMinor = reversibleMinor(row);
    if (reversalMinor <= 0) continue;
    await ctx.scheduler.runAfter(0, internal.refunds.reverseTransfer, {
      payoutId: row._id,
      reversalMinor,
    });
  }
};

const chargeRefunded: StripeEventHandler = async (ctx, event) => {
  const charge = event.data.object;
  const paymentIntent = charge.payment_intent;
  const paymentIntentId =
    typeof paymentIntent === "string" ? paymentIntent : paymentIntent?.id;
  if (typeof paymentIntentId !== "string") return;
  let record = await ctx.db
    .query("paymentRecords")
    .withIndex("by_stripePaymentIntentId", (q) =>
      q.eq("stripePaymentIntentId", paymentIntentId),
    )
    .unique();
  if (!record) {
    // Extra Checkout intents are tracked on their refund, not the installment.
    const refund = await ctx.db
      .query("refunds")
      .withIndex("by_stripePaymentIntentId", (q) =>
        q.eq("stripePaymentIntentId", paymentIntentId),
      )
      .first();
    if (refund) record = await ctx.db.get(refund.paymentRecordId);
  }
  if (!record) return;
  const refunds: unknown = charge.refunds;
  if (
    !refunds ||
    typeof refunds !== "object" ||
    !("data" in refunds) ||
    !Array.isArray(refunds.data)
  ) {
    return;
  }
  const now = Date.now();
  let reconciled = false;
  for (const entry of refunds.data as unknown[]) {
    if (
      !entry ||
      typeof entry !== "object" ||
      !("status" in entry) ||
      entry.status !== "succeeded" ||
      !("id" in entry) ||
      typeof entry.id !== "string" ||
      !("amount" in entry) ||
      typeof entry.amount !== "number" ||
      !Number.isSafeInteger(entry.amount) ||
      entry.amount <= 0
    ) {
      continue;
    }
    const stripeRefundId = entry.id;
    let refund = await ctx.db
      .query("refunds")
      .withIndex("by_stripeRefundId", (q) =>
        q.eq("stripeRefundId", stripeRefundId),
      )
      .unique();
    if (!refund && "metadata" in entry) {
      // The POST can succeed before markRefundSucceeded commits its Stripe id.
      const metadata = entry.metadata;
      if (
        metadata &&
        typeof metadata === "object" &&
        "refundId" in metadata &&
        typeof metadata.refundId === "string"
      ) {
        const refundId = ctx.db.normalizeId("refunds", metadata.refundId);
        const candidate = refundId ? await ctx.db.get(refundId) : null;
        if (
          candidate &&
          !candidate.stripeRefundId &&
          candidate.paymentRecordId === record._id &&
          candidate.amountMinor === entry.amount &&
          (candidate.stripePaymentIntentId ?? record.stripePaymentIntentId) ===
            paymentIntentId
        ) {
          refund = candidate;
        }
      }
    }
    if (!refund) {
      const refundId = await ctx.db.insert("refunds", {
        bookingId: record.bookingId,
        paymentRecordId: record._id,
        amountMinor: entry.amount,
        currency: record.currency,
        reason: "admin",
        status: "pending",
        stripeRefundId,
        stripePaymentIntentId: paymentIntentId,
        createdAt: now,
        updatedAt: now,
      });
      refund = await ctx.db.get(refundId);
    }
    if (!refund) throw new Error("Refund not found");
    if (refund.status !== "succeeded") {
      if (refund.status === "failed") {
        assertRefundTransition("failed", "pending");
        await ctx.db.patch(refund._id, { status: "pending", updatedAt: now });
        refund = { ...refund, status: "pending" };
      }
      await applyRefundSucceeded(ctx, refund, stripeRefundId);
    }
    reconciled = true;
  }
  if (!reconciled || paymentIntentId !== record.stripePaymentIntentId)
    return;
  const payouts = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", record.bookingId))
    .take(50);
  for (const payout of payouts) {
    if (payout.status !== "scheduled" && payout.status !== "held") continue;
    assertPayoutTransition(payout.status, "reversed");
    await ctx.db.patch(payout._id, { status: "reversed", updatedAt: now });
  }
};

export const disputeHandlers: StripeHandlerMap = {
  "charge.refunded": chargeRefunded,
  "charge.dispute.created": disputeCreated,
  "charge.dispute.closed": disputeClosed,
};
