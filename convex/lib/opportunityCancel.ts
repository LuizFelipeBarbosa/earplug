import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";
import { loadCurrentOffer, sendBookingEmail } from "../bookings";
import { releaseSlot } from "./bookingConfirm";
import { assertBookingTransition } from "./bookingStatus";
import { unpublishOpportunityGig } from "./gigPublish";
import { MAX_OPPORTUNITY_SLOTS } from "./opportunityPayload";
import {
  APPLICATION_ACTIVE_STATUSES,
  assertApplicationTransition,
  assertOpportunityTransition,
  assertSlotTransition,
  type ArtistApplicationStatus,
} from "./opportunityStatus";
import { cancelTicketSalesForGig } from "./ticketCancellation";

export async function cancelOpportunity(
  ctx: MutationCtx,
  args: {
    opportunity: Doc<"talentOpportunities">;
    actorUserId: Id<"users">;
    reason: string;
    now: number;
  },
): Promise<void> {
  const { opportunity, now } = args;
  assertOpportunityTransition(opportunity.status, "cancelled");
  const bookings = await ctx.db
    .query("bookings")
    .withIndex("by_opportunityId", (q) =>
      q.eq("opportunityId", opportunity._id),
    )
    .take(500);
  for (const booking of bookings) {
    if (
      booking.status !== "offer_sent" &&
      booking.status !== "artist_accepted" &&
      booking.status !== "awaiting_payment" &&
      booking.status !== "confirmed"
    ) {
      continue;
    }
    const status =
      booking.status === "confirmed" ? "cancelled_by_organizer" : "withdrawn";
    assertBookingTransition(booking.status, status);
    await ctx.db.patch(booking._id, {
      status,
      cancelledBy: "organizer",
      cancelledByUserId: args.actorUserId,
      cancelledAt: now,
      cancelReason: args.reason,
      revision: booking.revision + 1,
      updatedAt: now,
    });
    if (status === "withdrawn") {
      const offer = await loadCurrentOffer(ctx, booking);
      await ctx.db.patch(offer._id, {
        response: "withdrawn",
        respondedAt: now,
        respondedBy: args.actorUserId,
      });
      const application = await ctx.db.get(booking.applicationId);
      if (application?.status === "offered") {
        assertApplicationTransition(application.status, "shortlisted");
        await ctx.db.patch(application._id, {
          status: "shortlisted",
          updatedAt: now,
        });
      }
    } else {
      await releaseSlot(ctx, booking.slotId);
      const application = await ctx.db.get(booking.applicationId);
      if (application?.status === "booked") {
        assertApplicationTransition(application.status, "declined");
        await ctx.db.patch(application._id, {
          status: "declined",
          updatedAt: now,
        });
      }
    }
    const cancelledBooking = await ctx.db.get(booking._id);
    if (!cancelledBooking) throw new Error("Booking not found");
    await sendBookingEmail(ctx, cancelledBooking, "bookingCancelled");
  }
  if (opportunity.publicGigId !== undefined) {
    await unpublishOpportunityGig(ctx, opportunity._id, "opportunity_cancelled");
    const gig = await ctx.db.get(opportunity.publicGigId);
    if (gig?.ticketing === "paid") {
      await cancelTicketSalesForGig(ctx, opportunity.publicGigId);
    }
  } else {
    await ctx.db.patch(opportunity._id, {
      status: "cancelled",
      revision: opportunity.revision + 1,
      updatedAt: now,
    });
  }
  await expireActiveApplications(ctx, opportunity._id, {
    statuses: APPLICATION_ACTIVE_STATUSES,
    to: "declined",
    decidedBy: args.actorUserId,
  });
  const slots = await ctx.db
    .query("opportunitySlots")
    .withIndex("by_opportunityId_and_order", (q) =>
      q.eq("opportunityId", opportunity._id),
    )
    .take(MAX_OPPORTUNITY_SLOTS + 1);
  for (const slot of slots) {
    if (slot.status === "open") {
      assertSlotTransition(slot.status, "cancelled");
      await ctx.db.patch(slot._id, { status: "cancelled" });
    }
  }
}

export async function expireActiveApplications(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  options: {
    statuses: readonly ArtistApplicationStatus[];
    to: "expired" | "declined";
    decidedBy?: Id<"users">;
  },
): Promise<void> {
  const now = Date.now();
  let patchedCount = 0;
  for (const status of options.statuses) {
    for (;;) {
      const page = await ctx.db
        .query("artistApplications")
        .withIndex("by_opportunityId_and_status", (q) =>
          q.eq("opportunityId", opportunityId).eq("status", status),
        )
        .take(200);
      for (const application of page) {
        await ctx.db.patch(application._id, {
          status: options.to,
          decidedAt: now,
          updatedAt: now,
          ...(options.decidedBy ? { decidedBy: options.decidedBy } : {}),
        });
        patchedCount++;
      }
      if (page.length < 200) break;
    }
  }
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) return;
  await ctx.db.patch(opportunityId, {
    applicationCount: Math.max(0, opportunity.applicationCount - patchedCount),
    updatedAt: now,
  });
}
