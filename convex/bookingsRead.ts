import { type Infer, v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { type QueryCtx, query } from "./_generated/server";
import {
  isPlatformAdmin,
  organizationMembershipFor,
  type OrganizationRole,
} from "./lib/authz";
import {
  BOOKING_ACTIVE_STATUSES,
  BOOKING_LIVE_STATUSES,
} from "./lib/bookingStatus";
import { docCache, type DocCache } from "./lib/docCache";
import {
  currentUser,
  effectiveAddressDisclosure,
  requireBandRole,
  requireUser,
} from "./lib/helpers";
import {
  bookingCancelledByValidator,
  bookingStatusValidator,
  cancellationTemplateValidator,
  feeSnapshotFields,
  gigPerformerRoleValidator,
  payoutHoldReasonValidator,
} from "./schema";

export const bookingPayloadValidator = v.object({
  _id: v.id("bookings"),
  opportunityId: v.id("talentOpportunities"),
  opportunityTitle: v.string(),
  opportunitySlug: v.string(),
  slotId: v.id("opportunitySlots"),
  slotRole: gigPerformerRoleValidator,
  slotRequired: v.boolean(),
  organizationId: v.id("organizations"),
  organizationName: v.string(),
  bandId: v.id("bands"),
  bandName: v.string(),
  bandSlug: v.string(),
  applicationId: v.id("artistApplications"),
  status: bookingStatusValidator,
  revision: v.number(),
  startsAt: v.number(),
  doorsAt: v.union(v.number(), v.null()),
  fee: v.object(feeSnapshotFields),
  paidMinor: v.number(),
  refundedMinor: v.number(),
  paymentDueAt: v.union(v.number(), v.null()),
  payoutHoldReasons: v.array(payoutHoldReasonValidator),
  cancellationTemplate: cancellationTemplateValidator,
  termsNotes: v.union(v.string(), v.null()),
  organizerAcceptedTermsAt: v.number(),
  artistAcceptedTermsAt: v.union(v.number(), v.null()),
  confirmedAt: v.union(v.number(), v.null()),
  completedAt: v.union(v.number(), v.null()),
  cancelledAt: v.union(v.number(), v.null()),
  cancelledBy: v.union(bookingCancelledByValidator, v.null()),
  cancelReason: v.union(v.string(), v.null()),
  cancellationKind: v.optional(v.literal("safety")),
  expiresAt: v.union(v.number(), v.null()),
  currentOffer: v.union(
    v.object({
      revision: v.number(),
      message: v.union(v.string(), v.null()),
      sentAt: v.number(),
      expiresAt: v.number(),
      response: v.union(
        v.literal("accepted"),
        v.literal("declined"),
        v.literal("expired"),
        v.literal("withdrawn"),
        v.null(),
      ),
      installments: v.array(
        v.object({
          label: v.string(),
          amountMinor: v.number(),
          dueAt: v.number(),
        }),
      ),
    }),
    v.null(),
  ),
  venue: v.union(
    v.object({
      _id: v.id("venues"),
      name: v.string(),
      slug: v.union(v.string(), v.null()),
      approxLabel: v.union(v.string(), v.null()),
      exactAddress: v.union(v.string(), v.null()),
    }),
    v.null(),
  ),
  privateLocation: v.union(
    v.object({
      label: v.string(),
      area: v.string(),
      city: v.string(),
      addr: v.optional(v.string()),
      lat: v.optional(v.number()),
      lng: v.optional(v.number()),
      notes: v.optional(v.string()),
    }),
    v.null(),
  ),
  privateEvent: v.boolean(),
  publicGigId: v.union(v.id("gigs"), v.null()),
  publicGigSlug: v.union(v.string(), v.null()),
  counterpartyEmail: v.union(v.string(), v.null()),
  viewerSide: v.union(v.literal("organizer"), v.literal("artist")),
});

export async function toBookingPayload(
  ctx: QueryCtx,
  booking: Doc<"bookings">,
  viewer: {
    userId: Id<"users">;
    side: "organizer" | "artist";
    organizationRole?: OrganizationRole;
  },
  cache: DocCache = docCache(ctx),
): Promise<Infer<typeof bookingPayloadValidator>> {
  const [opportunity, slot, organization, band] = await Promise.all([
    cache.get(booking.opportunityId),
    cache.get(booking.slotId),
    cache.get(booking.organizationId),
    cache.get(booking.bandId),
  ]);
  if (!opportunity) {
    throw new Error(`Booking ${booking._id} references a missing opportunity`);
  }
  if (!slot) {
    throw new Error(`Booking ${booking._id} references a missing slot`);
  }
  if (!organization) {
    throw new Error(`Booking ${booking._id} references a missing organization`);
  }
  if (!band) {
    throw new Error(`Booking ${booking._id} references a missing band`);
  }
  const isPrivate = opportunity.mode === "privateBooking";
  const showFullLocation =
    viewer.side === "organizer" ||
    (viewer.side === "artist" && BOOKING_LIVE_STATUSES.includes(booking.status));
  let venue: Infer<typeof bookingPayloadValidator>["venue"] = null;
  let privateLocation: Infer<typeof bookingPayloadValidator>["privateLocation"] =
    null;
  if (isPrivate) {
    if (!opportunity.privateLocationId) {
      throw new Error(
        `Booking ${booking._id} has a private opportunity without a location`,
      );
    }
    const location = await cache.get(opportunity.privateLocationId);
    if (!location) {
      throw new Error(
        `Booking ${booking._id} references a missing private location`,
      );
    }
    privateLocation = {
      label: showFullLocation ? location.label : location.area,
      area: location.area,
      city: location.city,
      addr: showFullLocation ? location.addr : undefined,
      lat: showFullLocation ? location.lat : undefined,
      lng: showFullLocation ? location.lng : undefined,
      notes: showFullLocation ? location.notes : undefined,
    };
  } else {
    if (!opportunity.venueId) {
      throw new Error(
        `Booking ${booking._id} has an opportunity without a venue`,
      );
    }
    const venueDoc = await cache.get(opportunity.venueId);
    if (!venueDoc) {
      throw new Error(`Booking ${booking._id} references a missing venue`);
    }
    let exactAddress: string | null = null;
    if (effectiveAddressDisclosure(venueDoc) === "public") {
      exactAddress = venueDoc.addr;
    } else if (
      viewer.side === "organizer" ||
      (viewer.side === "artist" && BOOKING_LIVE_STATUSES.includes(booking.status))
    ) {
      const venuePrivate = await ctx.db
        .query("venuePrivateDetails")
        .withIndex("by_venueId", (q) => q.eq("venueId", venueDoc._id))
        .unique();
      exactAddress = venuePrivate?.addr ?? null;
    }
    venue = {
      _id: venueDoc._id,
      name: venueDoc.name,
      slug: venueDoc.slug ?? null,
      approxLabel: venueDoc.approxLabel ?? null,
      exactAddress,
    };
  }

  const offer = booking.currentOfferId
    ? await cache.get(booking.currentOfferId)
    : null;
  if (booking.currentOfferId && !offer) {
    throw new Error(
      `Booking ${booking._id} references a missing current offer`,
    );
  }
  const publicGig = opportunity.publicGigId
    ? await cache.get(opportunity.publicGigId)
    : null;

  let counterpartyEmail: string | null = null;
  if (viewer.side === "organizer") {
    // An absent organizer role means access was granted via platform admin.
    const canReadContact =
      viewer.organizationRole === "owner" ||
      viewer.organizationRole === "manager" ||
      viewer.organizationRole === undefined;
    if (canReadContact && organization.status !== "suspended") {
      const application = await cache.get(booking.applicationId);
      const submitter = application
        ? await cache.get(application.submittedBy)
        : null;
      counterpartyEmail = submitter?.email ?? null;
    }
  } else if (BOOKING_LIVE_STATUSES.includes(booking.status)) {
    const organizationPrivate = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", booking.organizationId),
      )
      .unique();
    counterpartyEmail = organizationPrivate?.businessEmail ?? null;
  }

  return {
    _id: booking._id,
    opportunityId: booking.opportunityId,
    opportunityTitle: opportunity.title,
    opportunitySlug: opportunity.slug,
    slotId: booking.slotId,
    slotRole: slot.role,
    slotRequired: slot.required,
    organizationId: booking.organizationId,
    organizationName:
      isPrivate && !showFullLocation ? "Private host" : organization.name,
    bandId: booking.bandId,
    bandName: band.name,
    bandSlug: band.slug,
    applicationId: booking.applicationId,
    status: booking.status,
    revision: booking.revision,
    startsAt: booking.startsAt,
    doorsAt: opportunity.doorsAt ?? null,
    fee: {
      grossMinor: booking.grossMinor,
      commissionBps: booking.commissionBps,
      commissionMinor: booking.commissionMinor,
      artistNetMinor: booking.artistNetMinor,
      currency: booking.currency,
    },
    cancellationTemplate: booking.cancellationTemplate,
    paidMinor: booking.paidMinor ?? 0,
    refundedMinor: booking.refundedMinor ?? 0,
    paymentDueAt: booking.paymentDueAt ?? null,
    payoutHoldReasons: booking.payoutHoldReasons ?? [],
    termsNotes: booking.termsNotes ?? null,
    organizerAcceptedTermsAt: booking.organizerAcceptedTermsAt,
    artistAcceptedTermsAt: booking.artistAcceptedTermsAt ?? null,
    confirmedAt: booking.confirmedAt ?? null,
    completedAt: booking.completedAt ?? null,
    cancelledAt: booking.cancelledAt ?? null,
    cancelledBy: booking.cancelledBy ?? null,
    cancelReason: booking.cancelReason ?? null,
    cancellationKind: booking.cancellationKind,
    expiresAt: booking.expiresAt ?? null,
    currentOffer: offer
      ? {
          revision: offer.revision,
          message: offer.message ?? null,
          sentAt: offer.sentAt,
          expiresAt: offer.expiresAt,
          response: offer.response ?? null,
          installments: offer.installments.map((installment) => ({
            label: installment.label,
            amountMinor: installment.amountMinor,
            dueAt:
              installment.dueAfterAcceptanceMs === undefined
                ? installment.dueAt
                : (booking.artistAcceptedTermsAt ?? offer.sentAt) +
                  installment.dueAfterAcceptanceMs,
          })),
        }
      : null,
    venue,
    privateLocation,
    privateEvent: isPrivate,
    publicGigId: opportunity.publicGigId ?? null,
    publicGigSlug: publicGig?.slug ?? null,
    counterpartyEmail,
    viewerSide: viewer.side,
  };
}

export const get = query({
  args: {
    bookingId: v.id("bookings"),
    viewAs: v.optional(v.union(v.literal("organizer"), v.literal("artist"))),
  },
  returns: v.union(bookingPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) return null;
    const user = await currentUser(ctx);
    if (!user) return null;

    const [membership, bandMembership, platformAdmin] = await Promise.all([
      organizationMembershipFor(ctx, booking.organizationId, user._id),
      ctx.db
        .query("bandMembers")
        .withIndex("by_band_user", (q) =>
          q.eq("bandId", booking.bandId).eq("userId", user._id),
        )
        .unique(),
      isPlatformAdmin(ctx, user._id),
    ]);
    const canOrganizer = membership !== null || platformAdmin;
    const canArtist = bandMembership?.role === "admin";
    if (!canOrganizer && !canArtist) return null;

    // Preserve the default order: organization member, band admin, platform admin.
    let side: "organizer" | "artist" =
      membership || !canArtist ? "organizer" : "artist";
    if (args.viewAs === "organizer" && canOrganizer) {
      side = "organizer";
    } else if (args.viewAs === "artist" && canArtist) {
      side = "artist";
    }

    return await toBookingPayload(ctx, booking, {
      userId: user._id,
      side,
      organizationRole: side === "organizer" ? membership?.role : undefined,
    });
  },
});

export const forOrganization = query({
  args: {
    organizationId: v.id("organizations"),
    statuses: v.optional(v.array(bookingStatusValidator)),
    limit: v.optional(v.number()),
  },
  returns: v.array(bookingPayloadValidator),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const membership = await organizationMembershipFor(
      ctx,
      args.organizationId,
      user._id,
    );
    const viaPlatformAdmin =
      membership === null && (await isPlatformAdmin(ctx, user._id));
    if (!membership && !viaPlatformAdmin) {
      throw new Error("Not permitted for this organization");
    }

    // Members retain access to booking history while their org is suspended.
    // Terminal statuses must be requested explicitly.
    const statuses = args.statuses ?? BOOKING_ACTIVE_STATUSES;
    const cache = docCache(ctx);
    const bookings: Doc<"bookings">[] = [];
    for (const status of statuses) {
      bookings.push(
        ...(await ctx.db
          .query("bookings")
          .withIndex("by_organizationId_and_status_and_startsAt", (q) =>
            q.eq("organizationId", args.organizationId).eq("status", status),
          )
          .order("desc")
          .take(100)),
      );
    }
    bookings.sort((a, b) => b.startsAt - a.startsAt);
    const effectiveLimit = Math.min(args.limit ?? 100, 200);
    const payloads = await Promise.all(
      bookings.slice(0, effectiveLimit).map(async (booking) => {
        try {
          return await toBookingPayload(
            ctx,
            booking,
            {
              userId: user._id,
              side: "organizer",
              organizationRole: membership?.role,
            },
            cache,
          );
        } catch (error) {
          if (
            error instanceof Error &&
            /references a missing|has an opportunity without a venue|has a private opportunity without a location/.test(
              error.message,
            )
          ) {
            return null;
          }
          throw error;
        }
      }),
    );
    return payloads.filter(
      (payload): payload is Infer<typeof bookingPayloadValidator> =>
        payload !== null,
    );
  },
});

export const forBand = query({
  args: {
    bandId: v.id("bands"),
    statuses: v.optional(v.array(bookingStatusValidator)),
    limit: v.optional(v.number()),
  },
  returns: v.array(bookingPayloadValidator),
  handler: async (ctx, args) => {
    const { user } = await requireBandRole(ctx, args.bandId, { role: "admin" });
    // Terminal statuses must be requested explicitly.
    const statuses = args.statuses ?? BOOKING_ACTIVE_STATUSES;
    const cache = docCache(ctx);
    const bookings: Doc<"bookings">[] = [];
    for (const status of statuses) {
      bookings.push(
        ...(await ctx.db
          .query("bookings")
          .withIndex("by_bandId_and_status_and_startsAt", (q) =>
            q.eq("bandId", args.bandId).eq("status", status),
          )
          .order("desc")
          .take(100)),
      );
    }
    bookings.sort((a, b) => b.startsAt - a.startsAt);
    const effectiveLimit = Math.min(args.limit ?? 100, 200);
    const payloads = await Promise.all(
      bookings.slice(0, effectiveLimit).map(async (booking) => {
        try {
          return await toBookingPayload(
            ctx,
            booking,
            { userId: user._id, side: "artist" },
            cache,
          );
        } catch (error) {
          if (
            error instanceof Error &&
            /references a missing|has an opportunity without a venue|has a private opportunity without a location/.test(
              error.message,
            )
          ) {
            return null;
          }
          throw error;
        }
      }),
    );
    return payloads.filter(
      (payload): payload is Infer<typeof bookingPayloadValidator> =>
        payload !== null,
    );
  },
});
