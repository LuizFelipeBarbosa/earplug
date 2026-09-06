import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { isPlatformAdmin, organizationMembershipFor } from "./authz";
import {
  ArtistApplicationStatus,
  OPPORTUNITY_ARTIST_VISIBLE_STATUSES,
} from "./opportunityStatus";

export async function isAdminOfAnyBand(
  ctx: QueryCtx | MutationCtx,
  userId: Id<"users">,
): Promise<boolean> {
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .filter((q) => q.eq(q.field("role"), "admin"))
    .first();
  return membership !== null;
}

export async function bandIsInvited(
  ctx: QueryCtx | MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  bandId: Id<"bands">,
): Promise<boolean> {
  const invite = await ctx.db
    .query("opportunityInvites")
    .withIndex("by_opportunityId_and_bandId", (q) =>
      q.eq("opportunityId", opportunityId).eq("bandId", bandId),
    )
    .unique();
  return invite !== null;
}

export async function latestApplicationStatusFor(
  ctx: QueryCtx | MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  bandId: Id<"bands">,
): Promise<ArtistApplicationStatus | null> {
  const application = await ctx.db
    .query("artistApplications")
    .withIndex("by_opportunityId_and_bandId", (q) =>
      q.eq("opportunityId", opportunityId).eq("bandId", bandId),
    )
    .order("desc")
    .first();
  return application?.status ?? null;
}

export async function canViewerSeeOpportunity(
  ctx: QueryCtx | MutationCtx,
  opportunity: Doc<"talentOpportunities">,
  viewer: { user: Doc<"users"> | null; bandId?: Id<"bands"> },
): Promise<boolean> {
  const { user, bandId } = viewer;
  if (opportunity.mode === "privateBooking") {
    if (!user) return false;
    if (await isPlatformAdmin(ctx, user._id)) return true;
    if (
      await organizationMembershipFor(ctx, opportunity.organizationId, user._id)
    ) {
      return true;
    }
    if (
      !OPPORTUNITY_ARTIST_VISIBLE_STATUSES.includes(opportunity.status) ||
      opportunity.visibility !== "inviteOnly" ||
      bandId === undefined
    ) {
      return false;
    }
    const membership = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", bandId).eq("userId", user._id),
      )
      .unique();
    return (
      membership !== null && (await bandIsInvited(ctx, opportunity._id, bandId))
    );
  }

  if (
    opportunity.visibility === "public" &&
    OPPORTUNITY_ARTIST_VISIBLE_STATUSES.includes(opportunity.status)
  ) {
    return true;
  }
  if (!user) return false;

  // Invites never expose drafts or cancelled opportunities to artists.
  if (
    bandId !== undefined &&
    opportunity.status !== "draft" &&
    opportunity.status !== "cancelled"
  ) {
    const membership = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", bandId).eq("userId", user._id),
      )
      .unique();
    if (membership && (await bandIsInvited(ctx, opportunity._id, bandId))) {
      return true;
    }
  }
  return (
    (await organizationMembershipFor(
      ctx,
      opportunity.organizationId,
      user._id,
    )) !== null
  );
}
