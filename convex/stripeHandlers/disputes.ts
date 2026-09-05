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
} from "../lib/paymentStatus";
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
    fees.length > 0 ? fees.reduce((sum, value) => sum + value, 0) : 1500;
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
    await ctx.scheduler.runAfter(0, internal.refunds.reverseTransfer, {
      payoutId: row._id,
      reversalMinor: row.amountMinor,
    });
  }
};

export const disputeHandlers: StripeHandlerMap = {
  "charge.dispute.created": disputeCreated,
  "charge.dispute.closed": disputeClosed,
};
