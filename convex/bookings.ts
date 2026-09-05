import type { FunctionReference } from "convex/server";
import { v } from "convex/values";
import { internal as generatedInternal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalMutation,
  mutation,
  type MutationCtx,
} from "./_generated/server";
import { bookingEmail, type BookingEmailKind } from "./emails";
import {
  organizationMembershipFor,
  requireOrganizationRole,
} from "./lib/authz";
import { confirmBooking, releaseSlot } from "./lib/bookingConfirm";
import {
  assertBookingTransition,
  BOOKING_LIVE_STATUSES,
  COMPLETION_DELAY_MS,
  OFFER_TTL_MS,
  REVIEW_WINDOW_MS,
} from "./lib/bookingStatus";
import { appBaseUrl, flag } from "./lib/env";
import { feeSnapshot, resolveCommissionBps } from "./lib/fees";
import { syncGigLineup, unpublishOpportunityGig } from "./lib/gigPublish";
import { requireBandRole, requireUser } from "./lib/helpers";
import { assertApplicationTransition } from "./lib/opportunityStatus";
import { recomputeReviewSummary } from "./lib/reviewSummary";
import {
  bookingStatusValidator,
  cancellationTemplateValidator,
} from "./schema";

// convex/_generated/api.d.ts has not been regenerated to include this new module yet
// (regeneration is deliberately deferred to a later step outside this change). This
// narrow, hand-written augmentation lets the two internal self-references below
// type-check; it can be deleted once `npx convex dev` regenerates api.d.ts.
const internal = generatedInternal as typeof generatedInternal & {
  bookings: {
    expireOffer: FunctionReference<
      "mutation",
      "internal",
      { bookingId: Id<"bookings">; revision: number },
      null
    >;
    markCompleted: FunctionReference<
      "mutation",
      "internal",
      { bookingId: Id<"bookings"> },
      null
    >;
  };
};

async function loadBooking(ctx: MutationCtx, bookingId: Id<"bookings">) {
  const booking = await ctx.db.get(bookingId);
  if (!booking) throw new Error("Booking not found");
  return booking;
}

async function loadCurrentOffer(ctx: MutationCtx, booking: Doc<"bookings">) {
  const offer =
    booking.currentOfferId !== undefined
      ? await ctx.db.get(booking.currentOfferId)
      : await ctx.db
          .query("bookingOffers")
          .withIndex("by_bookingId_and_revision", (q) =>
            q.eq("bookingId", booking._id).eq("revision", booking.revision),
          )
          .unique();
  if (!offer) throw new Error("Booking offer not found");
  return offer;
}

function normalizeNote(
  value: string | undefined,
  label: string,
  limit: number,
) {
  const note = value?.trim();
  if (note !== undefined && note.length > limit) {
    throw new Error(`${label} must be at most ${limit} characters`);
  }
  return note || undefined;
}

async function shortlistApplication(
  ctx: MutationCtx,
  applicationId: Id<"artistApplications">,
  now: number,
) {
  const application = await ctx.db.get(applicationId);
  if (!application) throw new Error("Application not found");
  assertApplicationTransition(application.status, "shortlisted");
  await ctx.db.patch(applicationId, { status: "shortlisted", updatedAt: now });
}

async function resolveEmailRecipients(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
  organization: Doc<"organizations">,
  kind: BookingEmailKind,
): Promise<string[]> {
  const artistFacing =
    kind === "offerSent" ||
    kind === "offerWithdrawn" ||
    kind === "bookingConfirmed" ||
    kind === "reviewRequested" ||
    (kind === "bookingCancelled" && booking.cancelledBy === "organizer");
  const organizerFacing =
    kind === "offerAccepted" ||
    kind === "offerDeclined" ||
    kind === "offerExpired" ||
    kind === "reviewRequested" ||
    (kind === "bookingCancelled" && booking.cancelledBy === "artist");
  const recipients: string[] = [];
  if (artistFacing) {
    const members = await ctx.db
      .query("bandMembers")
      .withIndex("by_band", (q) => q.eq("bandId", booking.bandId))
      .collect();
    for (const member of members) {
      if (member.role !== "admin") continue;
      const user = await ctx.db.get(member.userId);
      const email = user?.email.trim();
      if (email) recipients.push(email);
    }
  }
  if (organizerFacing) {
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", booking.organizationId),
      )
      .unique();
    const email = details
      ? details.businessEmail.trim()
      : (await ctx.db.get(organization.ownerUserId))?.email.trim();
    if (email) recipients.push(email);
  }
  return recipients;
}

async function sendBookingEmail(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
  kind: BookingEmailKind,
) {
  const [opportunity, band, organization] = await Promise.all([
    ctx.db.get(booking.opportunityId),
    ctx.db.get(booking.bandId),
    ctx.db.get(booking.organizationId),
  ]);
  if (!opportunity) throw new Error("Opportunity not found");
  if (!band) throw new Error("Band not found");
  if (!organization) throw new Error("Organization not found");
  const venue =
    opportunity.venueId !== undefined
      ? await ctx.db.get(opportunity.venueId)
      : null;
  if (!venue) throw new Error("Venue not found");
  const body = bookingEmail(kind, {
    opportunityTitle: opportunity.title,
    bandName: band.name,
    orgName: organization.name,
    venueName: venue.name,
    startsAt: booking.startsAt,
    link: `${appBaseUrl()}/bookings/${booking._id}`,
    ...(booking.grossMinor > 0
      ? {
          grossLabel: `${(booking.grossMinor / 100).toFixed(2)} ${booking.currency.toUpperCase()}`,
        }
      : {}),
    ...(kind === "bookingCancelled" ? { reason: booking.cancelReason } : {}),
  });
  const recipients = await resolveEmailRecipients(
    ctx,
    booking,
    organization,
    kind,
  );
  for (const to of recipients) {
    await ctx.scheduler.runAfter(0, internal.emails.send, {
      kind,
      to,
      ...body,
    });
  }
}

async function releaseBookingSlot(ctx: MutationCtx, booking: Doc<"bookings">) {
  await releaseSlot(ctx, booking.slotId);
  const opportunity = await ctx.db.get(booking.opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  if (opportunity.publicGigId === undefined) return;
  const slot = await ctx.db.get(booking.slotId);
  if (!slot) throw new Error("Slot not found");
  if (slot.required) {
    await unpublishOpportunityGig(
      ctx,
      opportunity._id,
      "required_slot_cancelled",
    );
  } else {
    await syncGigLineup(ctx, opportunity._id);
  }
}

export const sendOffer = mutation({
  args: {
    applicationId: v.id("artistApplications"),
    grossMinor: v.number(),
    cancellationTemplate: cancellationTemplateValidator,
    termsNotes: v.optional(v.string()),
    message: v.optional(v.string()),
  },
  returns: v.object({
    bookingId: v.id("bookings"),
    offerId: v.id("bookingOffers"),
    revision: v.number(),
  }),
  handler: async (ctx, args) => {
    const application = await ctx.db.get(args.applicationId);
    if (!application) throw new Error("Application not found");
    const opportunity = await ctx.db.get(application.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const { organization, user } = await requireOrganizationRole(
      ctx,
      opportunity.organizationId,
      ["owner", "manager"],
    );
    if (application.status !== "shortlisted") {
      throw new Error("Shortlist the application before sending an offer");
    }
    if (
      !["open", "applications_closed", "booking", "confirmed"].includes(
        opportunity.status,
      )
    ) {
      throw new Error("This opportunity is not accepting offers");
    }
    const slot = await ctx.db.get(application.slotId);
    if (!slot) throw new Error("Slot not found");
    if (slot.bookingId !== undefined)
      throw new Error("This slot is already booked");
    for (const status of [
      "offer_sent",
      "artist_accepted",
      "awaiting_payment",
    ] as const) {
      const pending = await ctx.db
        .query("bookings")
        .withIndex("by_slotId_and_status", (q) =>
          q.eq("slotId", slot._id).eq("status", status),
        )
        .first();
      if (pending) throw new Error("This slot already has a pending offer");
    }
    const confirmed = await ctx.db
      .query("bookings")
      .withIndex("by_slotId_and_status", (q) =>
        q.eq("slotId", slot._id).eq("status", "confirmed"),
      )
      .first();
    if (confirmed) throw new Error("This slot is already booked");
    if (!Number.isInteger(args.grossMinor) || args.grossMinor < 0) {
      throw new Error("Gross fee must be a non-negative integer");
    }
    if (args.grossMinor > 0 && !flag("PAYMENTS_ENABLED", false)) {
      throw new Error("Paid offers open once payments are enabled");
    }
    const termsNotes = normalizeNote(args.termsNotes, "Terms notes", 2000);
    const message = normalizeNote(args.message, "Message", 1000);
    const fees =
      args.grossMinor === 0
        ? feeSnapshot(0, 0)
        : feeSnapshot(args.grossMinor, resolveCommissionBps(organization));
    const now = Date.now();
    const expiresAt = now + OFFER_TTL_MS;
    const terms = {
      ...fees,
      cancellationTemplate: args.cancellationTemplate,
      ...(termsNotes !== undefined ? { termsNotes } : {}),
    };
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId: opportunity._id,
      slotId: slot._id,
      organizationId: opportunity.organizationId,
      bandId: application.bandId,
      applicationId: application._id,
      status: "offer_sent",
      revision: 1,
      startsAt: opportunity.startsAt,
      ...terms,
      organizerAcceptedTermsAt: now,
      payoutHold: false,
      expiresAt,
      createdBy: user._id,
      createdAt: now,
      updatedAt: now,
    });
    const offerId = await ctx.db.insert("bookingOffers", {
      bookingId,
      revision: 1,
      ...terms,
      installments: [],
      ...(message !== undefined ? { message } : {}),
      sentBy: user._id,
      sentAt: now,
      expiresAt,
    });
    await ctx.db.patch(bookingId, { currentOfferId: offerId });
    assertApplicationTransition(application.status, "offered");
    await ctx.db.patch(application._id, { status: "offered", updatedAt: now });
    await ctx.scheduler.runAt(expiresAt, internal.bookings.expireOffer, {
      bookingId,
      revision: 1,
    });
    await sendBookingEmail(ctx, await loadBooking(ctx, bookingId), "offerSent");
    return { bookingId, offerId, revision: 1 };
  },
});

export const withdrawOffer = mutation({
  args: { bookingId: v.id("bookings"), expectedRevision: v.number() },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const booking = await loadBooking(ctx, args.bookingId);
    const opportunity = await ctx.db.get(booking.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const { user } = await requireOrganizationRole(
      ctx,
      opportunity.organizationId,
      ["owner", "manager"],
    );
    if (args.expectedRevision !== booking.revision) {
      throw new Error("Booking changed elsewhere");
    }
    assertBookingTransition(booking.status, "withdrawn");
    const offer = await loadCurrentOffer(ctx, booking);
    const now = Date.now();
    const revision = booking.revision + 1;
    await ctx.db.patch(booking._id, {
      status: "withdrawn",
      revision,
      updatedAt: now,
    });
    await ctx.db.patch(offer._id, {
      response: "withdrawn",
      respondedAt: now,
      respondedBy: user._id,
    });
    await shortlistApplication(ctx, booking.applicationId, now);
    await sendBookingEmail(ctx, booking, "offerWithdrawn");
    return { revision };
  },
});

export const respond = mutation({
  args: {
    bookingId: v.id("bookings"),
    action: v.union(v.literal("accept"), v.literal("decline")),
    expectedRevision: v.number(),
    message: v.optional(v.string()),
  },
  returns: v.object({ status: bookingStatusValidator, revision: v.number() }),
  handler: async (ctx, args) => {
    const booking = await loadBooking(ctx, args.bookingId);
    const { user } = await requireBandRole(ctx, booking.bandId, {
      role: "admin",
    });
    if (args.expectedRevision !== booking.revision) {
      throw new Error("Booking changed elsewhere");
    }
    if (booking.status !== "offer_sent") {
      throw new Error("Only a pending offer can be accepted or declined");
    }
    const now = Date.now();
    if (booking.expiresAt !== undefined && now > booking.expiresAt) {
      throw new Error("This offer has expired");
    }
    const offer = await loadCurrentOffer(ctx, booking);
    if (args.action === "decline") {
      assertBookingTransition(booking.status, "declined");
      const revision = booking.revision + 1;
      await ctx.db.patch(booking._id, {
        status: "declined",
        revision,
        updatedAt: now,
      });
      await ctx.db.patch(offer._id, {
        response: "declined",
        respondedAt: now,
        respondedBy: user._id,
      });
      await shortlistApplication(ctx, booking.applicationId, now);
      await sendBookingEmail(ctx, booking, "offerDeclined");
      return { status: "declined" as const, revision };
    }

    await ctx.db.patch(offer._id, {
      response: "accepted",
      respondedAt: now,
      respondedBy: user._id,
    });
    assertBookingTransition(booking.status, "artist_accepted");
    await ctx.db.patch(booking._id, {
      artistAcceptedTermsAt: now,
      status: "artist_accepted",
      revision: booking.revision + 1,
      updatedAt: now,
    });
    if (booking.grossMinor === 0) {
      await confirmBooking(ctx, booking._id);
    } else {
      assertBookingTransition("artist_accepted", "awaiting_payment");
      await ctx.db.patch(booking._id, {
        status: "awaiting_payment",
        revision: booking.revision + 2,
        updatedAt: now,
      });
    }
    const finalBooking = await loadBooking(ctx, booking._id);
    await sendBookingEmail(ctx, finalBooking, "offerAccepted");
    if (finalBooking.status === "confirmed") {
      await sendBookingEmail(ctx, finalBooking, "bookingConfirmed");
    }
    return { status: finalBooking.status, revision: finalBooking.revision };
  },
});

export const cancel = mutation({
  args: {
    bookingId: v.id("bookings"),
    reason: v.string(),
    expectedRevision: v.number(),
  },
  returns: v.object({ status: bookingStatusValidator, revision: v.number() }),
  handler: async (ctx, args) => {
    const booking = await loadBooking(ctx, args.bookingId);
    if (args.expectedRevision !== booking.revision) {
      throw new Error("Booking changed elsewhere");
    }
    const reason = args.reason.trim();
    if (!reason) throw new Error("Cancellation reason is required");
    if (reason.length > 500) {
      throw new Error("Cancellation reason must be at most 500 characters");
    }
    const user = await requireUser(ctx);
    const membership = await organizationMembershipFor(
      ctx,
      booking.organizationId,
      user._id,
    );
    let side: "organizer" | "artist";
    if (membership?.role === "owner" || membership?.role === "manager") {
      side = "organizer";
    } else {
      const bandMember = await ctx.db
        .query("bandMembers")
        .withIndex("by_band_user", (q) =>
          q.eq("bandId", booking.bandId).eq("userId", user._id),
        )
        .unique();
      if (bandMember?.role !== "admin") {
        throw new Error("Not permitted to cancel this booking");
      }
      side = "artist";
    }
    const status: "cancelled_by_organizer" | "cancelled_by_artist" =
      side === "organizer" ? "cancelled_by_organizer" : "cancelled_by_artist";
    assertBookingTransition(booking.status, status);
    const now = Date.now();
    const revision = booking.revision + 1;
    await ctx.db.patch(booking._id, {
      status,
      cancelledBy: side,
      cancelledByUserId: user._id,
      cancelledAt: now,
      cancelReason: reason,
      revision,
      updatedAt: now,
    });
    if (booking.status === "confirmed") {
      await releaseBookingSlot(ctx, booking);
      const application = await ctx.db.get(booking.applicationId);
      if (!application) throw new Error("Application not found");
      if (application.status === "booked") {
        const applicationStatus =
          side === "organizer" ? "declined" : "withdrawn";
        assertApplicationTransition(application.status, applicationStatus);
        await ctx.db.patch(application._id, {
          status: applicationStatus,
          updatedAt: now,
        });
      }
      await recomputeReviewSummary(
        ctx,
        side === "artist"
          ? { bandId: booking.bandId }
          : { organizationId: booking.organizationId },
      );
    }
    await sendBookingEmail(
      ctx,
      await loadBooking(ctx, booking._id),
      "bookingCancelled",
    );
    return { status, revision };
  },
});

export const expireOffer = internalMutation({
  args: { bookingId: v.id("bookings"), revision: v.number() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (
      !booking ||
      booking.status !== "offer_sent" ||
      booking.revision !== args.revision
    ) {
      return null;
    }
    const offer = await loadCurrentOffer(ctx, booking);
    const now = Date.now();
    assertBookingTransition(booking.status, "expired");
    await ctx.db.patch(booking._id, {
      status: "expired",
      revision: booking.revision + 1,
      updatedAt: now,
    });
    await ctx.db.patch(offer._id, { response: "expired", respondedAt: now });
    await shortlistApplication(ctx, booking.applicationId, now);
    await sendBookingEmail(ctx, booking, "offerExpired");
    return null;
  },
});

export const markCompleted = internalMutation({
  args: { bookingId: v.id("bookings") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    const now = Date.now();
    if (
      !booking ||
      booking.status !== "confirmed" ||
      now < booking.startsAt + COMPLETION_DELAY_MS
    ) {
      return null;
    }
    assertBookingTransition(booking.status, "completed");
    await ctx.db.patch(booking._id, {
      status: "completed",
      completedAt: now,
      revision: booking.revision + 1,
      updatedAt: now,
    });
    await ctx.scheduler.runAt(
      now + REVIEW_WINDOW_MS,
      internal.reviews.closeReviewWindow,
      {
        bookingId: booking._id,
      },
    );
    await recomputeReviewSummary(ctx, { bandId: booking.bandId });
    await recomputeReviewSummary(ctx, {
      organizationId: booking.organizationId,
    });
    await sendBookingEmail(ctx, booking, "reviewRequested");
    return null;
  },
});

export const adminForceState = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    status: bookingStatusValidator,
    reason: v.string(),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({ from: v.string(), to: v.string(), applied: v.boolean() }),
  handler: async (ctx, args) => {
    const booking = await loadBooking(ctx, args.bookingId);
    assertBookingTransition(booking.status, args.status);
    if (args.dryRun ?? true) {
      return { from: booking.status, to: args.status, applied: false };
    }
    const now = Date.now();
    const isCancellation =
      args.status === "cancelled_by_organizer" ||
      args.status === "cancelled_by_artist" ||
      args.status === "force_majeure";
    await ctx.db.patch(booking._id, {
      status: args.status,
      revision: booking.revision + 1,
      updatedAt: now,
      ...(isCancellation
        ? {
            cancelledBy: "admin" as const,
            cancelledAt: now,
            cancelReason: args.reason,
            cancelledByUserId: undefined,
          }
        : {}),
    });
    if (BOOKING_LIVE_STATUSES.includes(booking.status)) {
      await releaseBookingSlot(ctx, booking);
    }
    return { from: booking.status, to: args.status, applied: true };
  },
});
