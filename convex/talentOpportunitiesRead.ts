import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { QueryCtx, query } from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  requireOrganizationRoleQuery,
} from "./lib/authz";
import { currentUser, feedCutoff } from "./lib/helpers";
import {
  artistOpportunityPayloadValidator,
  opportunityPayloadValidator,
  toArtistOpportunityPayload,
  toOpportunityPayload,
} from "./lib/opportunityPayload";
import {
  OPPORTUNITY_ARTIST_VISIBLE_STATUSES,
  OpportunityStatus,
} from "./lib/opportunityStatus";
import {
  bandIsInvited,
  canViewerSeeOpportunity,
  latestApplicationStatusFor,
} from "./lib/opportunityVisibility";
import { artistApplicationStatusValidator, venueTypeValidator } from "./schema";

export const browseItemValidator = v.object({
  opportunity: artistOpportunityPayloadValidator,
  invited: v.boolean(),
  myApplicationStatus: v.union(artistApplicationStatusValidator, v.null()),
});

async function bandHasMember(
  ctx: QueryCtx,
  bandId: Id<"bands">,
  userId: Id<"users">,
): Promise<boolean> {
  const membership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", bandId).eq("userId", userId),
    )
    .unique();
  return membership !== null;
}

export const browse = query({
  args: {
    paginationOpts: paginationOptsValidator,
    bandId: v.optional(v.id("bands")),
    filters: v.optional(
      v.object({
        area: v.optional(v.string()),
        genre: v.optional(v.string()),
        venueType: v.optional(venueTypeValidator),
        minGuaranteeMinor: v.optional(v.number()),
      }),
    ),
  },
  returns: paginationResultValidator(browseItemValidator),
  handler: async (ctx, args) => {
    const cutoff = await feedCutoff(ctx);
    const result = await ctx.db
      .query("talentOpportunities")
      .withIndex("by_mode_and_visibility_and_status_and_startsAt", (q) =>
        q
          .eq("mode", "publicEvent")
          .eq("visibility", "public")
          .eq("status", "open"),
      )
      .order("asc")
      .paginate(args.paginationOpts);
    const user = await currentUser(ctx);
    const canSeeBandState =
      args.bandId !== undefined &&
      user !== null &&
      (await bandHasMember(ctx, args.bandId, user._id));
    const page: Infer<typeof browseItemValidator>[] = [];
    for (const opportunity of result.page) {
      if (opportunity.startsAt < cutoff) continue;
      const organization = await ctx.db.get(opportunity.organizationId);
      if (!organization || organization.status !== "verified") continue;
      const payload = await toArtistOpportunityPayload(ctx, opportunity);
      const filters = args.filters;
      if (
        filters?.area !== undefined &&
        !payload.area.toLowerCase().includes(filters.area.toLowerCase())
      ) {
        continue;
      }
      if (
        filters?.genre !== undefined &&
        !payload.genres.includes(filters.genre)
      ) {
        continue;
      }
      if (
        filters?.venueType !== undefined &&
        payload.venueType !== filters.venueType
      ) {
        continue;
      }
      const minGuaranteeMinor = filters?.minGuaranteeMinor;
      if (
        minGuaranteeMinor !== undefined &&
        !payload.slots.some((slot) => slot.guaranteeMinor >= minGuaranteeMinor)
      ) {
        continue;
      }
      page.push({
        opportunity: payload,
        invited: canSeeBandState
          ? await bandIsInvited(ctx, opportunity._id, args.bandId!)
          : false,
        myApplicationStatus: canSeeBandState
          ? await latestApplicationStatusFor(ctx, opportunity._id, args.bandId!)
          : null,
      });
    }
    return { ...result, page };
  },
});

export const invitedFor = query({
  args: { bandId: v.id("bands") },
  returns: v.array(browseItemValidator),
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (!user || !(await bandHasMember(ctx, args.bandId, user._id))) return [];
    const cutoff = await feedCutoff(ctx);
    const invites = await ctx.db
      .query("opportunityInvites")
      .withIndex("by_bandId", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .take(100);
    const items: Infer<typeof browseItemValidator>[] = [];
    for (const invite of invites) {
      const opportunity = await ctx.db.get(invite.opportunityId);
      if (
        !opportunity ||
        !OPPORTUNITY_ARTIST_VISIBLE_STATUSES.includes(opportunity.status) ||
        opportunity.startsAt < cutoff
      ) {
        continue;
      }
      const organization = await ctx.db.get(opportunity.organizationId);
      if (!organization || organization.status !== "verified") continue;
      items.push({
        opportunity: await toArtistOpportunityPayload(ctx, opportunity),
        invited: true,
        myApplicationStatus: await latestApplicationStatusFor(
          ctx,
          opportunity._id,
          args.bandId,
        ),
      });
    }
    return items.sort(
      (a, b) => b.opportunity.startsAt - a.opportunity.startsAt,
    );
  },
});

export const resolvePublic = query({
  args: { ref: v.string(), bandId: v.optional(v.id("bands")) },
  returns: v.union(browseItemValidator, v.null()),
  handler: async (ctx, args) => {
    const ref = args.ref.trim();
    if (ref === "" || ref.length > 200) return null;
    let opportunity = await ctx.db
      .query("talentOpportunities")
      .withIndex("by_slug", (q) => q.eq("slug", ref))
      .first();
    if (!opportunity) {
      const normalized = ctx.db.normalizeId("talentOpportunities", ref);
      opportunity = normalized ? await ctx.db.get(normalized) : null;
    }
    if (!opportunity) return null;
    const organization = await ctx.db.get(opportunity.organizationId);
    if (!organization || organization.status !== "verified") return null;
    const user = await currentUser(ctx);
    const visible = await canViewerSeeOpportunity(ctx, opportunity, {
      user,
      bandId: args.bandId,
    });
    if (!visible) return null;
    const canSeeBandState =
      args.bandId !== undefined &&
      user !== null &&
      (await bandHasMember(ctx, args.bandId, user._id));
    return {
      opportunity: await toArtistOpportunityPayload(ctx, opportunity),
      invited: canSeeBandState
        ? await bandIsInvited(ctx, opportunity._id, args.bandId!)
        : false,
      myApplicationStatus: canSeeBandState
        ? await latestApplicationStatusFor(ctx, opportunity._id, args.bandId!)
        : null,
    };
  },
});

export const manageForOrganization = query({
  args: { organizationId: v.id("organizations") },
  returns: v.array(opportunityPayloadValidator),
  handler: async (ctx, args) => {
    await requireOrganizationRoleQuery(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const statuses: readonly OpportunityStatus[] = [
      "draft",
      "open",
      "applications_closed",
      "booking",
      "confirmed",
      "completed",
      "cancelled",
    ];
    const opportunities: Doc<"talentOpportunities">[] = [];
    for (const status of statuses) {
      opportunities.push(
        ...(await ctx.db
          .query("talentOpportunities")
          .withIndex("by_organizationId_and_status", (q) =>
            q.eq("organizationId", args.organizationId).eq("status", status),
          )
          .take(100)),
      );
    }
    opportunities.sort((a, b) => {
      if ((a.status === "draft") !== (b.status === "draft")) {
        return a.status === "draft" ? -1 : 1;
      }
      return a.startsAt - b.startsAt;
    });
    const payloads = [];
    for (const opportunity of opportunities) {
      payloads.push(await toOpportunityPayload(ctx, opportunity));
    }
    return payloads;
  },
});

export const get = query({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.union(opportunityPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const opportunity = await ctx.db.get(args.opportunityId);
    if (!opportunity) return null;
    try {
      await requireOrganizationRoleQuery(
        ctx,
        opportunity.organizationId,
        ALL_ORGANIZATION_ROLES,
      );
    } catch {
      return null;
    }
    return await toOpportunityPayload(ctx, opportunity);
  },
});
