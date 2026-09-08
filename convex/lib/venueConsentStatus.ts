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

// All venues must be managed and verified, including an organization's own venue.
export function consentRequiredFor(
  venue: Doc<"venues">,
  organizationId: Id<"organizations">,
): boolean {
  if (venue.managedByOrganizationId === undefined) {
    throw new Error("This venue has not joined EarPlug yet");
  }
  if (venue.status !== "verified") {
    throw new Error("Choose a verified venue");
  }
  return venue.managedByOrganizationId !== organizationId;
}

// Return the first active consent among the opportunity's first ten rows.
export async function currentConsentFor(
  ctx: QueryCtx | MutationCtx,
  opportunityId: Id<"talentOpportunities">,
): Promise<Doc<"venueConsents"> | null> {
  const consents = await ctx.db
    .query("venueConsents")
    .withIndex("by_opportunityId", (q) => q.eq("opportunityId", opportunityId))
    .take(10);
  return (
    consents.find((consent) =>
      VENUE_CONSENT_ACTIVE_STATUSES.includes(consent.status),
    ) ?? null
  );
}
