import type { Infer } from "convex/values";
import { v } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { canTransition } from "./bookingStatus";

export const venueConsentStatusValidator = v.union(
  v.literal("pending"),
  v.literal("granted"),
  v.literal("declined"),
  v.literal("withdrawn"),
  v.literal("revoked"),
);
export type VenueConsentStatus = Infer<typeof venueConsentStatusValidator>;

export const VENUE_CONSENT_TRANSITIONS: Record<
  VenueConsentStatus,
  readonly VenueConsentStatus[]
> = {
  pending: ["granted", "declined", "withdrawn"],
  granted: ["revoked", "withdrawn"],
  declined: [],
  withdrawn: [],
  revoked: [],
};

export function assertVenueConsentTransition(
  from: VenueConsentStatus,
  to: VenueConsentStatus,
): void {
  if (!canTransition(VENUE_CONSENT_TRANSITIONS, from, to)) {
    throw new Error(`Venue approval cannot go from ${from} to ${to}`);
  }
}

export const VENUE_CONSENT_ACTIVE_STATUSES: readonly VenueConsentStatus[] = [
  "pending",
  "granted",
];

export function consentRequiredFor(
  venue: Doc<"venues">,
  organizationId: Id<"organizations">,
): boolean {
  return (
    venue.status === "verified" &&
    venue.managedByOrganizationId !== undefined &&
    venue.managedByOrganizationId !== organizationId
  );
}

export function assertVenueUsable(
  venue: Doc<"venues">,
  organizationId: Id<"organizations">,
  options: { promotersEnabled: boolean },
): { consentRequired: boolean } {
  if (venue.managedByOrganizationId === organizationId) {
    if (venue.status !== "verified") {
      throw new Error("Choose one of your verified venues");
    }
    return { consentRequired: false };
  }
  if (!options.promotersEnabled) {
    throw new Error("Choose one of your verified venues");
  }
  if (venue.managedByOrganizationId === undefined) {
    throw new Error("This venue has not joined EarPlug yet");
  }
  if (venue.status !== "verified") {
    throw new Error("Choose a verified venue");
  }
  return { consentRequired: consentRequiredFor(venue, organizationId) };
}

// Return the newest active consent among the opportunity's ten newest rows.
export async function currentConsentFor(
  ctx: QueryCtx | MutationCtx,
  opportunityId: Id<"talentOpportunities">,
): Promise<Doc<"venueConsents"> | null> {
  const consents = await ctx.db
    .query("venueConsents")
    .withIndex("by_opportunityId", (q) => q.eq("opportunityId", opportunityId))
    .order("desc")
    .take(10);
  return (
    consents.find((consent) =>
      VENUE_CONSENT_ACTIVE_STATUSES.includes(consent.status),
    ) ?? null
  );
}
