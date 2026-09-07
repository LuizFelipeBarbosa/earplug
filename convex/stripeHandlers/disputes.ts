import type { MutationCtx } from "../_generated/server";
import { assertBookingTransition } from "../lib/bookingStatus";
import {
  holdForDispute,
  openInAppDispute,
  releaseDisputeHold,
} from "../lib/disputeHold";
import { appendLedgerEntry } from "../lib/ledger";
import { assertPaymentRecordTransition } from "../lib/paymentStatus";
import { reconcilePaymentPayouts } from "../lib/payoutAccounting";
import { paymentRecordsForBooking } from "../lib/paymentSchedule";
import { applyStripeRefundStatus } from "../refunds";
import type {
  StripeEvent,
  StripeEventHandler,
  StripeHandlerMap,
} from "../stripeWebhook";
import {
  handleTicketChargeRefunded,
  handleTicketDisputeCreated,
  handleTicketDisputeClosed,
  isTicketSession,
} from "./tickets";

async function paymentRecordForDispute(ctx: MutationCtx, event: StripeEvent) {
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
  const charge = event.data.object.charge;
  if (charge && typeof charge === "object" && isTicketSession(charge)) {
    return handleTicketDisputeCreated(ctx, event, charge);
  }
  const record = await paymentRecordForDispute(ctx, event);
  if (!record) return;
  const dispute = event.data.object;
  const disputeId = dispute.id;
  if (
    record.stripeDisputeId === disputeId &&
    (record.stripeDisputeStatus === "won" ||
      record.stripeDisputeStatus === "lost")
  )
    return;
  const disputedMinor =
    typeof dispute.amount === "number" ? dispute.amount : record.amountMinor;
  const now = Date.now();
  await ctx.db.patch(record._id, {
    stripeDisputeId: disputeId,
    stripeDisputeStatus: "open",
    disputedMinor,
    updatedAt: now,
  });
  const booking = await ctx.db.get(record.bookingId);
  if (!booking) throw new Error("Booking not found");
  await holdForDispute(ctx, booking, { now });
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
};

const disputeClosed: StripeEventHandler = async (ctx, event) => {
  const charge = event.data.object.charge;
  if (charge && typeof charge === "object" && isTicketSession(charge)) {
    return handleTicketDisputeClosed(ctx, event, charge);
  }
  let record = await paymentRecordForDispute(ctx, event);
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
  if (record.stripeDisputeId && record.stripeDisputeId !== disputeId) return;
  if (
    record.stripeDisputeStatus === "won" ||
    record.stripeDisputeStatus === "lost"
  )
    return;
  if (!record.stripeDisputeId) {
    // Stripe may deliver the closure first. Apply the missing opening and its
    // settlement in this transaction, so a delayed creation cannot reopen it.
    await disputeCreated(ctx, event);
    record = await ctx.db.get(record._id);
    if (!record) throw new Error("Payment record not found");
  }
  const booking = await ctx.db.get(record.bookingId);
  if (!booking) throw new Error("Booking not found");
  const disputedMinor = record.disputedMinor ?? record.amountMinor;
  const now = Date.now();
  await ctx.db.patch(record._id, {
    stripeDisputeStatus: outcome,
    updatedAt: now,
  });
  const paymentRecords = await paymentRecordsForBooking(ctx, booking._id);
  const otherOpenDisputes = paymentRecords.some(
    (payment) =>
      payment._id !== record._id &&
      payment.stripeDisputeId &&
      (payment.stripeDisputeStatus === "open" ||
        payment.stripeDisputeStatus === undefined),
  );
  const inAppDispute = await openInAppDispute(ctx, booking._id);
  const ledgerFields = {
    currency: record.currency,
    bookingId: booking._id,
    organizationId: booking.organizationId,
    bandId: booking.bandId,
    stripeRef: disputeId,
    occurredAt: now,
  };
  if (outcome === "won") {
    await releaseDisputeHold(ctx, booking, {
      now,
      keepHoldIf: async () => otherOpenDisputes || inAppDispute !== null,
      respectScheduledFor: true,
    });
    await appendLedgerEntry(ctx, {
      ...ledgerFields,
      idempotencyKey: `dispute-release:${disputeId}`,
      kind: "dispute_release",
      amountMinor: disputedMinor,
      fundsState: "available",
    });
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
  const fee = fees.length > 0 ? fees.reduce((sum, value) => sum + value, 0) : 0;
  if (fees.length === 0) {
    console.warn(
      `Dispute ${disputeId}: fee data unavailable; recorded a $0 fee for later reconciliation`,
    );
  }
  // Only the charged-back amount leaves the record; the artist's transfer is
  // reconciled against that, never against the whole payment.
  const newRefundedMinor = Math.min(
    record.amountMinor,
    record.refundedMinor + disputedMinor,
  );
  const retainedMinor = paymentRecords.reduce(
    (sum, payment) =>
      sum +
      payment.amountMinor -
      (payment._id === record._id ? newRefundedMinor : payment.refundedMinor),
    0,
  );
  if (record.status !== "refunded") {
    const status =
      newRefundedMinor === record.amountMinor
        ? "refunded"
        : "partially_refunded";
    assertPaymentRecordTransition(record.status, status);
    await ctx.db.patch(record._id, {
      status,
      refundedMinor: newRefundedMinor,
      updatedAt: now,
    });
  }
  if (inAppDispute) {
    await ctx.db.patch(inAppDispute._id, {
      status: "resolved",
      resolution:
        newRefundedMinor >= record.amountMinor
          ? "refunded_full"
          : "refunded_partial",
      resolvedRefundMinor: disputedMinor,
      adminNote: "Closed by a lost Stripe dispute",
      resolvedAt: now,
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
  await reconcilePaymentPayouts(ctx, {
    ...record,
    refundedMinor: newRefundedMinor,
  });
  if (retainedMinor > 0) {
    // Release only after trimming the affected payout, so other installments
    // retain their completion payouts and the original payout timing.
    await releaseDisputeHold(ctx, booking, {
      now,
      keepHoldIf: async () => otherOpenDisputes,
      respectScheduledFor: true,
    });
  } else {
    const status = booking.status === "disputed" ? "refunded" : booking.status;
    if (status !== booking.status)
      assertBookingTransition(booking.status, status);
    const payoutHoldReasons = (booking.payoutHoldReasons ?? []).filter(
      (reason) => reason !== "dispute" || otherOpenDisputes,
    );
    await ctx.db.patch(booking._id, {
      status,
      payoutHoldReasons,
      payoutHold: payoutHoldReasons.length > 0,
    });
  }
  await ctx.db.patch(booking._id, {
    disputedFromStatus:
      retainedMinor > 0 && otherOpenDisputes
        ? booking.disputedFromStatus
        : undefined,
    refundedMinor:
      (booking.refundedMinor ?? 0) + (newRefundedMinor - record.refundedMinor),
    revision: booking.revision + 1,
    updatedAt: now,
  });
};

async function reconcileStripeRefund(
  ctx: MutationCtx,
  object: unknown,
  chargePaymentIntentId?: string,
): Promise<void> {
  if (!object || typeof object !== "object") return;
  const { id, status, amount, payment_intent, metadata } = object as Record<
    string,
    unknown
  >;
  if (
    typeof id !== "string" ||
    typeof status !== "string" ||
    typeof amount !== "number" ||
    !Number.isSafeInteger(amount) ||
    amount <= 0
  ) {
    return;
  }
  const paymentIntent = payment_intent ?? chargePaymentIntentId;
  const paymentIntentId =
    typeof paymentIntent === "string"
      ? paymentIntent
      : paymentIntent &&
          typeof paymentIntent === "object" &&
          "id" in paymentIntent
        ? paymentIntent.id
        : undefined;
  let refund = await ctx.db
    .query("refunds")
    .withIndex("by_stripeRefundId", (q) => q.eq("stripeRefundId", id))
    .unique();
  if (
    !refund &&
    typeof paymentIntentId === "string" &&
    metadata &&
    typeof metadata === "object" &&
    "refundId" in metadata &&
    typeof metadata.refundId === "string"
  ) {
    // The POST can succeed before the accounting mutation saves its Stripe id.
    const refundId = ctx.db.normalizeId("refunds", metadata.refundId);
    const candidate = refundId ? await ctx.db.get(refundId) : null;
    if (candidate && candidate.amountMinor === amount) {
      const record = await ctx.db.get(candidate.paymentRecordId);
      if (
        (candidate.stripePaymentIntentId ?? record?.stripePaymentIntentId) ===
        paymentIntentId
      ) {
        refund = candidate;
      }
    }
  }
  if (!refund && typeof paymentIntentId === "string") {
    let record = await ctx.db
      .query("paymentRecords")
      .withIndex("by_stripePaymentIntentId", (q) =>
        q.eq("stripePaymentIntentId", paymentIntentId),
      )
      .unique();
    if (!record) {
      // Extra Checkout intents are tracked on their refund, not the installment.
      const extraRefund = await ctx.db
        .query("refunds")
        .withIndex("by_stripePaymentIntentId", (q) =>
          q.eq("stripePaymentIntentId", paymentIntentId),
        )
        .first();
      if (extraRefund) record = await ctx.db.get(extraRefund.paymentRecordId);
    }
    if (!record) return;
    // Dashboard refunds have no EarPlug metadata. Track the processor refund
    // itself so pending outcomes can be polled and duplicate events are safe.
    const now = Date.now();
    const refundId = await ctx.db.insert("refunds", {
      bookingId: record.bookingId,
      paymentRecordId: record._id,
      amountMinor: amount,
      currency: record.currency,
      reason: "admin",
      status: "pending",
      stripeRefundId: id,
      stripePaymentIntentId: paymentIntentId,
      createdAt: now,
      updatedAt: now,
    });
    refund = await ctx.db.get(refundId);
  }
  if (refund) await applyStripeRefundStatus(ctx, refund, id, status);
}

const chargeRefunded: StripeEventHandler = async (ctx, event) => {
  const charge = event.data.object;
  if (isTicketSession(charge)) return handleTicketChargeRefunded(ctx, event);
  const paymentIntent = charge.payment_intent;
  const paymentIntentId =
    typeof paymentIntent === "string" ? paymentIntent : paymentIntent?.id;
  if (typeof paymentIntentId !== "string") return;
  const refunds: unknown = charge.refunds;
  // Older webhook versions can include expanded refunds. Modern versions send
  // individual refund events instead; both use the same reconciliation path.
  if (
    !refunds ||
    typeof refunds !== "object" ||
    !("data" in refunds) ||
    !Array.isArray(refunds.data)
  ) {
    return;
  }
  for (const entry of refunds.data as unknown[]) {
    if (
      entry &&
      typeof entry === "object" &&
      "status" in entry &&
      entry.status === "succeeded"
    ) {
      await reconcileStripeRefund(ctx, entry, paymentIntentId);
    }
  }
};

const refundUpdated: StripeEventHandler = async (ctx, event) => {
  await reconcileStripeRefund(ctx, event.data.object);
};

export const disputeHandlers: StripeHandlerMap = {
  "charge.refunded": chargeRefunded,
  "refund.created": refundUpdated,
  "refund.updated": refundUpdated,
  "refund.failed": refundUpdated,
  "charge.refund.updated": refundUpdated,
  "charge.dispute.created": disputeCreated,
  "charge.dispute.closed": disputeClosed,
};
