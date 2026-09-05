import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { DEFAULT_PAYMENT_DUE_MS, PAYMENT_OPEN_STATUSES } from "./paymentStatus";

export function buildInstallments(args: {
  offer: Doc<"bookingOffers">;
  booking: Doc<"bookings">;
  acceptedAt: number;
}): { index: number; label: string; amountMinor: number; dueAt: number }[] {
  const { offer, booking, acceptedAt } = args;
  if (offer.installments.length > 0) {
    const installments = offer.installments.map((installment, index) => ({
      index,
      label: installment.label,
      amountMinor: installment.amountMinor,
      dueAt:
        installment.dueAfterAcceptanceMs !== undefined
          ? acceptedAt + installment.dueAfterAcceptanceMs
          : installment.dueAt,
    }));
    const total = installments.reduce((sum, row) => sum + row.amountMinor, 0);
    if (total !== booking.grossMinor) {
      throw new Error("Installments must sum to the booking's gross amount");
    }
    return installments;
  }
  return [
    {
      index: 0,
      label: "Booking payment",
      amountMinor: booking.grossMinor,
      dueAt: acceptedAt + DEFAULT_PAYMENT_DUE_MS,
    },
  ];
}

export async function paymentRecordsForBooking(
  ctx: QueryCtx | MutationCtx,
  bookingId: Id<"bookings">,
): Promise<Doc<"paymentRecords">[]> {
  return await ctx.db
    .query("paymentRecords")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", bookingId))
    .order("asc")
    .take(50);
}

export function unpaidMinor(records: Doc<"paymentRecords">[]): number {
  return records.reduce(
    (sum, record) =>
      sum +
      (PAYMENT_OPEN_STATUSES.includes(record.status) ? record.amountMinor : 0),
    0,
  );
}

export async function recomputePayoutHold(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
): Promise<void> {
  const records = await paymentRecordsForBooking(ctx, booking._id);
  const hasUnpaid = unpaidMinor(records) > 0;
  const reasons = [...(booking.payoutHoldReasons ?? [])];
  if (hasUnpaid && !reasons.includes("unpaid_installment")) {
    reasons.push("unpaid_installment");
  }
  const payoutHoldReasons = hasUnpaid
    ? reasons
    : reasons.filter((reason) => reason !== "unpaid_installment");
  await ctx.db.patch(booking._id, {
    payoutHoldReasons,
    payoutHold: payoutHoldReasons.length > 0,
    updatedAt: Date.now(),
  });
}
