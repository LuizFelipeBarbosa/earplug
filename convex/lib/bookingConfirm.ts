import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { assertBookingTransition, COMPLETION_DELAY_MS } from "./bookingStatus";
import { publishGigFromOpportunity, syncGigLineup } from "./gigPublish";
import {
  APPLICATION_ACTIVE_STATUSES,
  assertApplicationTransition,
  assertSlotTransition,
} from "./opportunityStatus";


export async function confirmBooking(
  ctx: MutationCtx,
  bookingId: Id<"bookings">,
): Promise<Doc<"bookings">> {
  const booking = await ctx.db.get(bookingId);
  if (!booking) throw new Error("Booking not found");
  assertBookingTransition(booking.status, "confirmed");
  const now = Date.now();
  await ctx.db.patch(bookingId, {
    status: "confirmed",
    confirmedAt: now,
    revision: booking.revision + 1,
    updatedAt: now,
  });

  const slot = await ctx.db.get(booking.slotId);
  if (!slot) throw new Error("Slot not found");
  assertSlotTransition(slot.status, "booked");
  await ctx.db.patch(slot._id, {
    bookingId,
    bandId: booking.bandId,
    status: "booked",
  });

  const application = await ctx.db.get(booking.applicationId);
  if (!application) throw new Error("Application not found");
  assertApplicationTransition(application.status, "booked");
  await ctx.db.patch(application._id, { status: "booked", updatedAt: now });

  let competitorCount = 0;
  for (const status of APPLICATION_ACTIVE_STATUSES) {
    const competitors = await ctx.db
      .query("artistApplications")
      .withIndex("by_slotId_and_status", (q) =>
        q.eq("slotId", slot._id).eq("status", status),
      )
      .collect();
    for (const competitor of competitors) {
      if (competitor._id === booking.applicationId) continue;
      assertApplicationTransition(competitor.status, "declined");
      await ctx.db.patch(competitor._id, {
        status: "declined",
        declineReason: "slot_filled",
        decidedAt: now,
        updatedAt: now,
      });
      competitorCount++;
    }
  }

  const opportunity = await ctx.db.get(booking.opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  await ctx.db.patch(opportunity._id, {
    applicationCount: Math.max(
      0,
      opportunity.applicationCount - 1 - competitorCount,
    ),
    updatedAt: now,
  });
  // Later optional bookings update the published lineup. Publishing again would
  // attempt the invalid opportunity transition from confirmed to confirmed.
  if (opportunity.status === "confirmed") {
    await syncGigLineup(ctx, opportunity._id);
  } else {
    await publishGigFromOpportunity(ctx, opportunity._id);
  }
  await ctx.scheduler.runAt(
    booking.startsAt + COMPLETION_DELAY_MS,
    internal.bookings.markCompleted,
    { bookingId },
  );

  const confirmedBooking = await ctx.db.get(bookingId);
  if (!confirmedBooking) throw new Error("Booking not found");
  return confirmedBooking;
}

export async function releaseSlot(
  ctx: MutationCtx,
  slotId: Id<"opportunitySlots">,
): Promise<void> {
  const slot = await ctx.db.get(slotId);
  if (!slot) throw new Error("Slot not found");
  assertSlotTransition(slot.status, "open");
  await ctx.db.patch(slotId, {
    bookingId: undefined,
    bandId: undefined,
    status: "open",
  });
}
