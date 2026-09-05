import { Infer, v } from "convex/values";
import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { isPlatformAdmin, organizationMembershipFor } from "./authz";
import { BOOKING_LIVE_STATUSES } from "./bookingStatus";
import { effectiveAddressDisclosure } from "./helpers";

export const venuePrivatePayloadValidator = v.object({
  venueId: v.id("venues"),
  addr: v.string(),
  lat: v.number(),
  lng: v.number(),
  loadInNotes: v.union(v.string(), v.null()),
  capacity: v.union(v.number(), v.null()),
});

export function toVenuePrivatePayload(
  doc: Doc<"venuePrivateDetails">,
  operational: boolean,
): Infer<typeof venuePrivatePayloadValidator> {
  return {
    venueId: doc.venueId,
    addr: doc.addr,
    lat: doc.lat,
    lng: doc.lng,
    loadInNotes: operational ? (doc.loadInNotes ?? null) : null,
    capacity: operational ? (doc.capacity ?? null) : null,
  };
}

export async function readVenuePrivateFor(
  ctx: QueryCtx | MutationCtx,
  venue: Doc<"venues">,
  user: Doc<"users"> | null,
): Promise<{
  details: Doc<"venuePrivateDetails">;
  operational: boolean;
} | null> {
  // `venueId` uniqueness is enforced only by write paths, not the schema, so
  // a buggy writer could introduce duplicates and make this `.unique()` throw.
  const privateDetails = await ctx.db
    .query("venuePrivateDetails")
    .withIndex("by_venueId", (q) => q.eq("venueId", venue._id))
    .unique();
  if (privateDetails === null) return null;

  let operational = false;
  if (user !== null && (await isPlatformAdmin(ctx, user._id))) {
    operational = true;
  } else if (user !== null && venue.managedByOrganizationId !== undefined) {
    // Suspended organizations' members must not see operational details or an
    // on-ticket venue's exact address while it is pulled from listing.
    const organization = await ctx.db.get(venue.managedByOrganizationId);
    if (
      organization !== null &&
      organization.status !== "suspended" &&
      (await organizationMembershipFor(
        ctx,
        venue.managedByOrganizationId,
        user._id,
      )) !== null
    ) {
      operational = true;
    }
  }

  if (effectiveAddressDisclosure(venue) === "public") {
    return { details: privateDetails, operational };
  }
  if (operational) return { details: privateDetails, operational: true };

  let isConfirmedBookingBandAdmin = false;
  if (user !== null) {
    const memberships = await ctx.db
      .query("bandMembers")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(50);
    // The membership cap also bounds the number of bands checked.
    const adminBandIds = memberships
      .filter((membership) => membership.role === "admin")
      .map((membership) => membership.bandId);
    bookingBands: for (const bandId of adminBandIds) {
      for (const status of BOOKING_LIVE_STATUSES) {
        const bookings = await ctx.db
          .query("bookings")
          .withIndex("by_bandId_and_status_and_startsAt", (q) =>
            q.eq("bandId", bandId).eq("status", status),
          )
          .take(50);
        for (const booking of bookings) {
          const opportunity = await ctx.db.get(booking.opportunityId);
          if (opportunity !== null && opportunity.venueId === venue._id) {
            isConfirmedBookingBandAdmin = true;
            break bookingBands;
          }
        }
      }
    }
  }
  // TODO(phase2): Grant access to a ticket or RSVP holder.
  const isTicketOrRsvpHolder = false;

  return isConfirmedBookingBandAdmin || isTicketOrRsvpHolder
    ? { details: privateDetails, operational: false }
    : null;
}
