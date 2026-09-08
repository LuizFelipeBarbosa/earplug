import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { schedulePayoutsForBooking } from "../payouts";
import {
  assertBookingTransition,
  BOOKING_LIVE_STATUSES,
  COMPLETION_DELAY_MS,
} from "./bookingStatus";
import { assertPayoutTransition } from "./paymentStatus";

export async function holdForDispute(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
  opts: { now: number },
): Promise<{ movedToDisputed: boolean; heldPayoutIds: Id<"payouts">[] }> {
  const { now } = opts;
  const reasons = [...(booking.payoutHoldReasons ?? [])];
  const hasDisputeHold = reasons.includes("dispute");
  if (!hasDisputeHold) reasons.push("dispute");
  const movedToDisputed = BOOKING_LIVE_STATUSES.includes(booking.status);
  if (movedToDisputed) {
    assertBookingTransition(booking.status, "disputed");
    await ctx.db.patch(booking._id, {
      status: "disputed",
      disputedFromStatus: booking.status,
      payoutHoldReasons: reasons,
      payoutHold: true,
      revision: booking.revision + 1,
      updatedAt: now,
    });
  } else if (booking.status !== "disputed" || !hasDisputeHold) {
    await ctx.db.patch(booking._id, {
      payoutHoldReasons: reasons,
      payoutHold: true,
      updatedAt: now,
    });
  }

  const rows = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
    .take(50);
  const heldPayoutIds: Id<"payouts">[] = [];
  for (const row of rows) {
    if (row.status !== "scheduled") continue;
    assertPayoutTransition("scheduled", "held");
    await ctx.db.patch(row._id, {
      status: "held",
      holdReason: "dispute",
      updatedAt: now,
    });
    heldPayoutIds.push(row._id);
  }
  return { movedToDisputed, heldPayoutIds };
}

export async function releaseDisputeHold(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
  opts: {
    now: number;
    keepHoldIf?: () => Promise<boolean>;
    // Stripe wins preserve payout timing; admin resolutions recheck holds now.
    respectScheduledFor?: boolean;
  },
): Promise<{ restoredStatus?: string; rescheduledPayoutIds: Id<"payouts">[] }> {
  if (await opts.keepHoldIf?.()) return { rescheduledPayoutIds: [] };

  const { now } = opts;
  // A partial settlement may have removed the unpaid-installment hold already.
  const currentBooking = await ctx.db.get(booking._id);
  if (!currentBooking) throw new Error("Booking not found");
  booking = currentBooking;
  const rows = await ctx.db
    .query("payouts")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
    .take(50);
  const heldPayouts = rows.filter(
    (row) => row.status === "held" && row.holdReason === "dispute",
  );
  const reasons = booking.payoutHoldReasons ?? [];
  if (
    booking.status !== "disputed" &&
    !reasons.includes("dispute") &&
    heldPayouts.length === 0
  ) {
    return { rescheduledPayoutIds: [] };
  }

  const payoutHoldReasons = reasons.filter((reason) => reason !== "dispute");
  let restoredStatus: Doc<"bookings">["status"] | undefined;
  if (booking.status === "disputed") {
    if (booking.disputedFromStatus === undefined) {
      throw new Error("Disputed booking has no prior status");
    }
    restoredStatus = booking.disputedFromStatus;
    assertBookingTransition("disputed", restoredStatus);
    await ctx.db.patch(booking._id, {
      status: restoredStatus,
      disputedFromStatus: undefined,
      payoutHoldReasons,
      payoutHold: payoutHoldReasons.length > 0,
      revision: booking.revision + 1,
      updatedAt: now,
    });
    if (restoredStatus === "confirmed") {
      // The original completion job may have run while the booking was disputed.
      await ctx.scheduler.runAt(
        Math.max(now, booking.startsAt + COMPLETION_DELAY_MS),
        internal.bookings.markCompleted,
        { bookingId: booking._id },
      );
    } else if (
      restoredStatus === "completed" &&
      !rows.some((row) => row.kind === "forfeit")
    ) {
      // An in-flight Checkout may have paid an installment during the dispute.
      // A partial settlement's forfeits already replace the payable remainder.
      await schedulePayoutsForBooking(ctx, { ...booking, status: restoredStatus });
    }
  } else {
    await ctx.db.patch(booking._id, {
      payoutHoldReasons,
      payoutHold: payoutHoldReasons.length > 0,
      updatedAt: now,
    });
  }

  const rescheduledPayoutIds: Id<"payouts">[] = [];
  for (const row of heldPayouts) {
    assertPayoutTransition("held", "scheduled");
    await ctx.db.patch(row._id, { status: "scheduled", updatedAt: now });
    if (opts.respectScheduledFor) {
      await ctx.scheduler.runAt(
        Math.max(now, row.scheduledFor),
        internal.payouts.releasePayout,
        { payoutId: row._id },
      );
    } else {
      await ctx.scheduler.runAfter(0, internal.payouts.releasePayout, {
        payoutId: row._id,
      });
    }
    rescheduledPayoutIds.push(row._id);
  }
  return { restoredStatus, rescheduledPayoutIds };
}

export async function openInAppDispute(
  ctx: QueryCtx,
  bookingId: Id<"bookings">,
): Promise<Doc<"disputes"> | null> {
  return await ctx.db
    .query("disputes")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", bookingId))
    .order("desc")
    .filter((q) =>
      q.or(q.eq(q.field("status"), "open"), q.eq(q.field("status"), "under_review")),
    )
    .first();
}
