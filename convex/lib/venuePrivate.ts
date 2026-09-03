import { Infer, v } from "convex/values";
import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { isPlatformAdmin, organizationMembershipFor } from "./authz";

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
): Infer<typeof venuePrivatePayloadValidator> {
  return {
    venueId: doc.venueId,
    addr: doc.addr,
    lat: doc.lat,
    lng: doc.lng,
    loadInNotes: doc.loadInNotes ?? null,
    capacity: doc.capacity ?? null,
  };
}

export function effectiveAddressDisclosure(
  venue: Doc<"venues">,
): "onTicket" | "public" {
  if (venue.addressDisclosure !== undefined) return venue.addressDisclosure;
  return venue.status === undefined || venue.status === "legacy"
    ? "public"
    : "onTicket";
}

export async function readVenuePrivateFor(
  ctx: QueryCtx | MutationCtx,
  venue: Doc<"venues">,
  user: Doc<"users"> | null,
): Promise<Doc<"venuePrivateDetails"> | null> {
  const privateDetails = await ctx.db
    .query("venuePrivateDetails")
    .withIndex("by_venueId", (q) => q.eq("venueId", venue._id))
    .unique();
  if (privateDetails === null) return null;

  if (effectiveAddressDisclosure(venue) === "public") return privateDetails;
  if (user !== null && (await isPlatformAdmin(ctx, user._id))) {
    return privateDetails;
  }
  if (
    user !== null &&
    venue.managedByOrganizationId !== undefined &&
    (await organizationMembershipFor(
      ctx,
      venue.managedByOrganizationId,
      user._id,
    )) !== null
  ) {
    return privateDetails;
  }
  // TODO(phase2): Grant access to a confirmed-booking band admin.
  const isConfirmedBookingBandAdmin = false;
  // TODO(phase2): Grant access to a ticket or RSVP holder.
  const isTicketOrRsvpHolder = false;

  return isConfirmedBookingBandAdmin || isTicketOrRsvpHolder
    ? privateDetails
    : null;
}
