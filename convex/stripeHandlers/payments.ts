import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { internal as generatedInternal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import { sendBookingEmail } from "../bookings";
import { confirmBooking } from "../lib/bookingConfirm";
import { BOOKING_ACTIVE_STATUSES } from "../lib/bookingStatus";
import { appendLedgerEntry } from "../lib/ledger";
import { recomputePayoutHold } from "../lib/paymentSchedule";
import type * as payments from "../payments";
import type { StripeEventHandler, StripeHandlerMap } from "../stripeWebhook";

const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ payments: typeof payments }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;

const checkoutCompleted: StripeEventHandler = async (ctx, event) => {
  const session = event.data.object;
  let record: Doc<"paymentRecords"> | null = null;
  if (typeof session.metadata?.paymentRecordId === "string") {
    const paymentRecordId = ctx.db.normalizeId(
      "paymentRecords",
      session.metadata.paymentRecordId,
    );
    if (paymentRecordId) record = await ctx.db.get(paymentRecordId);
  }
  if (!record) {
    record = await ctx.db
      .query("paymentRecords")
      .withIndex("by_stripeCheckoutSessionId", (q) =>
        q.eq("stripeCheckoutSessionId", session.id),
      )
      .unique();
  }
  if (!record) {
    console.log(
      `checkout.session.completed ignored: no payment record for session ${session.id}`,
    );
    return;
  }
  if (record.status === "paid") return;
  const paymentIntent = session.payment_intent;
  const paymentIntentId =
    typeof paymentIntent === "string" ? paymentIntent : paymentIntent?.id;
  if (typeof paymentIntentId !== "string") {
    throw new Error("Completed Checkout session is missing a payment intent");
  }
  const chargeId =
    typeof paymentIntent?.latest_charge === "string"
      ? paymentIntent.latest_charge
      : undefined;
  const amountMinor =
    typeof session.amount_total === "number"
      ? session.amount_total
      : record.amountMinor;
  await ctx.runMutation(internal.payments.markPaid, {
    paymentRecordId: record._id,
    paymentIntentId,
    chargeId,
    amountMinor,
    eventId: event.id,
    sessionId: session.id,
  });
  const booking = await ctx.db.get(record.bookingId);
  if (!booking) throw new Error("Booking not found");
  await appendLedgerEntry(ctx, {
    idempotencyKey: `charge:${paymentIntentId}`,
    kind: "charge",
    amountMinor,
    currency: record.currency,
    fundsState: "pending",
    bookingId: booking._id,
    organizationId: booking.organizationId,
    stripeRef: paymentIntentId,
    stripeEventId: event.id,
    occurredAt: Date.now(),
  });
  await ctx.db.patch(booking._id, {
    paidMinor: (booking.paidMinor ?? 0) + amountMinor,
    updatedAt: Date.now(),
  });
  const updatedBooking = await ctx.db.get(booking._id);
  if (!updatedBooking) throw new Error("Booking not found");
  if (!BOOKING_ACTIVE_STATUSES.includes(updatedBooking.status)) {
    const reasons = [...(updatedBooking.payoutHoldReasons ?? [])];
    if (!reasons.includes("admin")) reasons.push("admin");
    await ctx.db.patch(booking._id, {
      payoutHoldReasons: reasons,
      payoutHold: true,
      updatedAt: Date.now(),
    });
    // TODO(b3b-refunds): auto-refund late payment.
    return;
  }
  if (
    record.installmentIndex === 0 &&
    updatedBooking.status === "awaiting_payment"
  ) {
    await confirmBooking(ctx, booking._id);
    const confirmedBooking = await ctx.db.get(booking._id);
    if (!confirmedBooking) throw new Error("Booking not found");
    await sendBookingEmail(ctx, confirmedBooking, "bookingConfirmed");
  }
  const currentBooking = await ctx.db.get(booking._id);
  if (!currentBooking) throw new Error("Booking not found");
  await recomputePayoutHold(ctx, currentBooking);
};

export const paymentHandlers: StripeHandlerMap = {
  "checkout.session.completed": checkoutCompleted,
  "checkout.session.expired": async (ctx, event) => {
    await ctx.runMutation(internal.payments.markSessionExpired, {
      sessionId: event.data.object.id,
    });
  },
  "payment_intent.payment_failed": async (ctx, event) => {
    await ctx.runMutation(internal.payments.markFailed, {
      paymentIntentId: event.data.object.id,
    });
  },
};
