import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";

export type TicketSellerKind = "organization" | "band";

export type TicketSeller = {
  kind: TicketSellerKind;
  organizationId?: Id<"organizations">;
  bandId?: Id<"bands">;
  name: string;
  stripeAccountId: string | null;
  chargesEnabled: boolean;
  suspended: boolean;
  feeSource: { ticketingFeeBps?: number; ticketingFeeFixedMinor?: number };
};

async function resolveOrganizationSeller(
  ctx: QueryCtx | MutationCtx,
  organizationId: Id<"organizations">,
): Promise<TicketSeller | null> {
  const organization = await ctx.db.get(organizationId);
  if (!organization) return null;
  const privateDetails = await ctx.db
    .query("organizationPrivateDetails")
    .withIndex("by_organizationId", (q) => q.eq("organizationId", organizationId))
    .unique();
  return {
    kind: "organization",
    organizationId,
    name: organization.name,
    stripeAccountId: privateDetails?.stripeAccountId ?? null,
    chargesEnabled: privateDetails?.stripeChargesEnabled ?? false,
    suspended: organization.status === "suspended",
    feeSource: {
      ticketingFeeBps: organization.ticketingFeeBps,
      ticketingFeeFixedMinor: organization.ticketingFeeFixedMinor,
    },
  };
}

async function resolveBandSeller(
  ctx: QueryCtx | MutationCtx,
  bandId: Id<"bands">,
): Promise<TicketSeller | null> {
  const band = await ctx.db.get(bandId);
  if (!band) return null;
  const payoutAccount = await ctx.db
    .query("bandPayoutAccounts")
    .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
    .unique();
  return {
    kind: "band",
    bandId,
    name: band.name,
    stripeAccountId: payoutAccount?.stripeAccountId ?? null,
    chargesEnabled:
      payoutAccount?.chargesEnabled === true &&
      payoutAccount?.cardPaymentsStatus === "active",
    suspended: band.archivedAt !== undefined,
    feeSource: {},
  };
}

export async function resolveTicketSeller(
  ctx: QueryCtx | MutationCtx,
  gig: Doc<"gigs">,
): Promise<TicketSeller | null> {
  if (gig.createdByOrganization) {
    return await resolveOrganizationSeller(ctx, gig.createdByOrganization);
  }
  if (gig.createdByBand) {
    return await resolveBandSeller(ctx, gig.createdByBand);
  }
  return null;
}

export async function resolveOrderSeller(
  ctx: QueryCtx | MutationCtx,
  order: {
    gigId: Id<"gigs">;
    sellerKind?: TicketSellerKind;
    organizationId?: Id<"organizations">;
    bandId?: Id<"bands">;
  },
): Promise<TicketSeller | null> {
  if (order.sellerKind === "band") {
    return order.bandId ? await resolveBandSeller(ctx, order.bandId) : null;
  }
  if (order.sellerKind === "organization") {
    return order.organizationId
      ? await resolveOrganizationSeller(ctx, order.organizationId)
      : null;
  }
  if (order.bandId && order.organizationId) return null;
  if (order.bandId) {
    return await resolveBandSeller(ctx, order.bandId);
  }
  if (order.organizationId) {
    return await resolveOrganizationSeller(ctx, order.organizationId);
  }
  const gig = await ctx.db.get(order.gigId);
  return gig ? await resolveTicketSeller(ctx, gig) : null;
}

export function sellerRefFields(seller: TicketSeller): {
  sellerKind: TicketSellerKind;
  organizationId?: Id<"organizations">;
  bandId?: Id<"bands">;
} {
  if (seller.kind === "organization") {
    return { sellerKind: "organization", organizationId: seller.organizationId };
  }
  return { sellerKind: "band", bandId: seller.bandId };
}

export function assertSellerOpen(seller: TicketSeller): void {
  if (seller.suspended || !seller.stripeAccountId || !seller.chargesEnabled) {
    throw new Error(
      seller.kind === "organization"
        ? "This organizer is not ready to sell tickets yet"
        : "This band is not ready to sell tickets yet",
    );
  }
}
