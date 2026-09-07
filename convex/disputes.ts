import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { resolveVenueName } from "./bookings";
import { bookingEmail } from "./emails";
import {
  isPlatformAdmin,
  organizationMembershipFor,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import { assertBookingTransition } from "./lib/bookingStatus";
import {
  settleBookingCancellation,
  settleDisputeRefund,
} from "./lib/cancellationSettlement";
import {
  holdForDispute,
  openInAppDispute,
  releaseDisputeHold,
} from "./lib/disputeHold";
import {
  assertDisputeTransition,
  disputeOpenCheck,
  disputeResolutionCheck,
  type DisputeCategory,
  type DisputeResolution,
  type DisputeSide,
} from "./lib/disputeStatus";
import { appBaseUrl, flag } from "./lib/env";
import { requireUser } from "./lib/helpers";
import {
  bookingStatusValidator,
  disputeCategoryValidator,
  disputeResolutionValidator,
  disputeSideValidator,
  disputeStatusValidator,
} from "./schema";

const disputeRow = v.object({
  disputeId: v.id("disputes"),
  bookingId: v.id("bookings"),
  side: disputeSideValidator,
  category: disputeCategoryValidator,
  text: v.string(),
  requestedRefundMinor: v.optional(v.number()),
  status: disputeStatusValidator,
  resolution: v.optional(disputeResolutionValidator),
  resolvedRefundMinor: v.optional(v.number()),
  adminNote: v.optional(v.string()),
  createdAt: v.number(),
  resolvedAt: v.optional(v.number()),
});

const categoryLabels: Record<DisputeCategory, string> = {
  no_show: "no-show",
  late_or_short_set: "late or short set",
  misrepresentation: "misrepresentation",
  payment: "payment",
  safety: "safety",
  other: "other",
};
const resolutionLabels: Record<DisputeResolution, string> = {
  released: "artist payout released",
  refunded_full: "full refund",
  refunded_partial: "partial refund",
  dismissed: "dismissed",
};

async function reportingSide(
  ctx: QueryCtx,
  booking: Doc<"bookings">,
  user: Doc<"users">,
): Promise<DisputeSide> {
  const bandMembership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", booking.bandId).eq("userId", user._id),
    )
    .unique();
  if (bandMembership?.role === "admin") return "artist";

  const membership = await organizationMembershipFor(
    ctx,
    booking.organizationId,
    user._id,
  );
  if (
    membership?.role === "owner" ||
    membership?.role === "manager" ||
    membership?.role === "finance"
  ) {
    return "organizer";
  }
  throw new Error("Not permitted to access disputes for this booking");
}

async function hasOpenStripeDispute(
  ctx: QueryCtx,
  bookingId: Id<"bookings">,
): Promise<boolean> {
  const record = await ctx.db
    .query("paymentRecords")
    .withIndex("by_bookingId", (q) => q.eq("bookingId", bookingId))
    .filter((q) => q.eq(q.field("stripeDisputeStatus"), "open"))
    .first();
  return record !== null;
}

function disputePayload(dispute: Doc<"disputes">) {
  return {
    disputeId: dispute._id,
    bookingId: dispute.bookingId,
    side: dispute.side,
    category: dispute.category,
    text: dispute.text,
    requestedRefundMinor: dispute.requestedRefundMinor,
    status: dispute.status,
    resolution: dispute.resolution,
    resolvedRefundMinor: dispute.resolvedRefundMinor,
    ...(dispute.status === "resolved" ? { adminNote: dispute.adminNote } : {}),
    createdAt: dispute.createdAt,
    resolvedAt: dispute.resolvedAt,
  };
}

async function sendDisputeEmail(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
  kind: "disputeOpened" | "disputeResolved",
  details: {
    side: DisputeSide;
    category: DisputeCategory;
    resolution?: DisputeResolution;
    refundMinor?: number;
  },
): Promise<void> {
  const [opportunity, band, organization] = await Promise.all([
    ctx.db.get(booking.opportunityId),
    ctx.db.get(booking.bandId),
    ctx.db.get(booking.organizationId),
  ]);
  if (!opportunity) throw new Error("Opportunity not found");
  if (!band) throw new Error("Band not found");
  if (!organization) throw new Error("Organization not found");

  const recipients = new Set<string>();
  if (kind === "disputeResolved" || details.side === "organizer") {
    const members = await ctx.db
      .query("bandMembers")
      .withIndex("by_band", (q) => q.eq("bandId", booking.bandId))
      .collect();
    for (const member of members) {
      if (member.role !== "admin") continue;
      const user = await ctx.db.get(member.userId);
      const email = user?.email.trim();
      if (email) recipients.add(email);
    }
  }
  if (kind === "disputeResolved" || details.side === "artist") {
    const privateDetails = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", booking.organizationId),
      )
      .unique();
    const email =
      privateDetails?.businessEmail.trim() ||
      (await ctx.db.get(organization.ownerUserId))?.email.trim();
    if (email) recipients.add(email);
  }

  const body = bookingEmail(kind, {
    opportunityTitle: opportunity.title,
    bandName: band.name,
    orgName: organization.name,
    venueName: await resolveVenueName(ctx, opportunity),
    startsAt: booking.startsAt,
    categoryLabel: categoryLabels[details.category],
    resolutionLabel: details.resolution && resolutionLabels[details.resolution],
    amountLabel:
      details.refundMinor !== undefined && details.refundMinor > 0
        ? `${(details.refundMinor / 100).toFixed(2)} ${booking.currency.toUpperCase()}`
        : undefined,
    link: `${appBaseUrl()}/bookings/${booking._id}`,
  });
  for (const to of recipients) {
    await ctx.scheduler.runAfter(0, internal.emails.send, { kind, to, ...body });
  }
}

export const open = mutation({
  args: {
    bookingId: v.id("bookings"),
    category: disputeCategoryValidator,
    text: v.string(),
    requestedRefundMinor: v.optional(v.number()),
  },
  returns: v.object({ disputeId: v.id("disputes") }),
  handler: async (ctx, args) => {
    if (!flag("DISPUTES_ENABLED", false)) {
      throw new Error("Disputes are not available yet");
    }
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const user = await requireUser(ctx);
    const side = await reportingSide(ctx, booking, user);
    const text = args.text.trim();
    if (text.length < 10 || text.length > 2000) {
      throw new Error("Dispute details must be between 10 and 2000 characters");
    }
    const [existingDispute, stripeDisputeOpen, paidPayout] = await Promise.all([
      openInAppDispute(ctx, booking._id),
      hasOpenStripeDispute(ctx, booking._id),
      ctx.db
        .query("payouts")
        .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
        .filter((q) => q.eq(q.field("status"), "paid"))
        .first(),
    ]);
    const now = Date.now();
    const check = disputeOpenCheck({
      side,
      bookingStatus: booking.status,
      grossMinor: booking.grossMinor,
      paidMinor: booking.paidMinor ?? 0,
      startsAt: booking.startsAt,
      completedAt: booking.completedAt,
      hasOpenDispute: existingDispute !== null,
      hasOpenStripeDispute: stripeDisputeOpen,
      anyPayoutPaid: paidPayout !== null,
      requestedRefundMinor: args.requestedRefundMinor,
      now,
    });
    if (!check.ok) throw new Error(check.reason);

    const disputeId = await ctx.db.insert("disputes", {
      bookingId: booking._id,
      openedByUserId: user._id,
      side,
      category: args.category,
      text,
      requestedRefundMinor: args.requestedRefundMinor,
      status: "open",
      createdAt: now,
      updatedAt: now,
    });
    await holdForDispute(ctx, booking, { now });
    await sendDisputeEmail(ctx, booking, "disputeOpened", {
      side,
      category: args.category,
      refundMinor: args.requestedRefundMinor,
    });
    return { disputeId };
  },
});

export const forBooking = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(disputeRow),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const user = await requireUser(ctx);
    if (!(await isPlatformAdmin(ctx, user._id))) {
      await reportingSide(ctx, booking, user);
    }
    const disputes = await ctx.db
      .query("disputes")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
      .order("desc")
      .take(50);
    return disputes.map(disputePayload);
  },
});

export const listOpen = query({
  args: { paginationOpts: paginationOptsValidator },
  returns: paginationResultValidator(
    disputeRow.extend({
      bookingTitle: v.string(),
      organizationName: v.string(),
      bandName: v.string(),
      paidMinor: v.number(),
      bookingStatus: v.union(
        bookingStatusValidator,
        v.literal("(deleted booking)"),
      ),
    }),
  ),
  handler: async (ctx, args) => {
    await requirePlatformAdminQuery(ctx);
    const result = await ctx.db
      .query("disputes")
      .withIndex("by_status_and_createdAt", (q) => q.eq("status", "open"))
      .order("desc")
      .paginate(args.paginationOpts);
    // Only open disputes drive the cursor. Append all under-review rows on the
    // first page (which can exceed numItems) so later pages do not repeat them.
    const underReview =
      args.paginationOpts.cursor === null
        ? await ctx.db
            .query("disputes")
            .withIndex("by_status_and_createdAt", (q) =>
              q.eq("status", "under_review"),
            )
            .order("desc")
            .collect()
        : [];
    const page = await Promise.all(
      [...result.page, ...underReview].map(async (dispute) => {
        const booking = await ctx.db.get(dispute.bookingId);
        const [opportunity, organization, band] = booking
          ? await Promise.all([
              ctx.db.get(booking.opportunityId),
              ctx.db.get(booking.organizationId),
              ctx.db.get(booking.bandId),
            ])
          : [null, null, null];
        return {
          ...disputePayload(dispute),
          bookingTitle: opportunity?.title ?? "(deleted booking)",
          organizationName: organization?.name ?? "(deleted organization)",
          bandName: band?.name ?? "(deleted band)",
          paidMinor: booking?.paidMinor ?? 0,
          bookingStatus: booking?.status ?? ("(deleted booking)" as const),
        };
      }),
    );
    return { ...result, page };
  },
});

export const startReview = mutation({
  args: { disputeId: v.id("disputes") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requirePlatformAdmin(ctx);
    const dispute = await ctx.db.get(args.disputeId);
    if (!dispute) throw new Error("Dispute not found");
    assertDisputeTransition(dispute.status, "under_review");
    await ctx.db.patch(dispute._id, {
      status: "under_review",
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const resolve = mutation({
  args: {
    disputeId: v.id("disputes"),
    resolution: disputeResolutionValidator,
    refundMinor: v.optional(v.number()),
    adminNote: v.optional(v.string()),
  },
  returns: v.object({ status: v.literal("resolved"), refundMinor: v.number() }),
  handler: async (ctx, args) => {
    const admin = await requirePlatformAdmin(ctx);
    const dispute = await ctx.db.get(args.disputeId);
    if (!dispute) throw new Error("Dispute not found");
    assertDisputeTransition(dispute.status, "resolved");
    const booking = await ctx.db.get(dispute.bookingId);
    if (!booking) throw new Error("Booking not found");
    const paymentRecords = await ctx.db
      .query("paymentRecords")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
      .collect();
    const refundableMinor = paymentRecords
      .filter(
        (record) =>
          (record.status === "paid" || record.status === "partially_refunded") &&
          record.amountMinor - record.refundedMinor > 0,
      )
      .reduce((sum, record) => sum + record.amountMinor - record.refundedMinor, 0);
    const check = disputeResolutionCheck({
      resolution: args.resolution,
      refundMinor: args.refundMinor,
      paidMinor: refundableMinor,
      hasOpenStripeDispute: await hasOpenStripeDispute(ctx, booking._id),
    });
    if (!check.ok) throw new Error(check.reason);

    const now = Date.now();
    if (args.resolution === "refunded_full") {
      assertBookingTransition(booking.status, "refunded");
      // Clear the hold without restoring the booking to its pre-dispute status.
      // As in adminForceState, a disputed booking keeps its slot/application.
      const payoutHoldReasons = (booking.payoutHoldReasons ?? []).filter(
        (reason) => reason !== "dispute",
      );
      await ctx.db.patch(booking._id, {
        status: "refunded",
        revision: booking.revision + 1,
        updatedAt: now,
        cancelledBy: "admin",
        cancelledAt: now,
        cancelReason: "Dispute resolved: full refund",
        cancelledByUserId: undefined,
        disputedFromStatus: undefined,
        payoutHoldReasons,
        payoutHold: payoutHoldReasons.length > 0,
      });
      if (booking.grossMinor > 0) {
        await settleBookingCancellation(ctx, {
          booking,
          cancelledBy: "admin",
          reason: "dispute",
          now,
        });
      }
    } else {
      if (args.resolution === "refunded_partial") {
        await settleDisputeRefund(ctx, {
          booking,
          refundMinor: check.refundMinor,
          now,
        });
      }
      await releaseDisputeHold(ctx, booking, { now });
    }
    await ctx.db.patch(dispute._id, {
      status: "resolved",
      resolution: args.resolution,
      resolvedRefundMinor: check.refundMinor,
      adminNote: args.adminNote,
      resolvedBy: admin._id,
      resolvedAt: now,
      updatedAt: now,
    });
    await sendDisputeEmail(ctx, booking, "disputeResolved", {
      side: dispute.side,
      category: dispute.category,
      resolution: args.resolution,
      refundMinor: check.refundMinor,
    });
    return { status: "resolved" as const, refundMinor: check.refundMinor };
  },
});
