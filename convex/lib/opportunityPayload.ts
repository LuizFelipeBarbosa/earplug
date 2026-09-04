import { Infer, v } from "convex/values";
import { Doc } from "../_generated/dataModel";
import { QueryCtx, MutationCtx } from "../_generated/server";
import {
  ageRequirementValidator,
  gigPerformerRoleValidator,
  opportunityModeValidator,
  opportunitySlotStatusValidator,
  opportunityStatusValidator,
  opportunityTicketingValidator,
  opportunityVisibilityValidator,
  venueTypeValidator,
} from "../schema";
import { toVenuePayload, venuePayloadValidator } from "./helpers";

export const MAX_OPPORTUNITY_SLOTS = 8;

export const opportunitySlotPayloadValidator = v.object({
  _id: v.id("opportunitySlots"),
  order: v.number(),
  role: gigPerformerRoleValidator,
  setLengthMin: v.union(v.number(), v.null()),
  guaranteeMinor: v.number(),
  required: v.boolean(),
  status: opportunitySlotStatusValidator,
  bandId: v.union(v.id("bands"), v.null()),
});

export const opportunityPayloadValidator = v.object({
  _id: v.id("talentOpportunities"),
  organizationId: v.id("organizations"),
  mode: opportunityModeValidator,
  venueId: v.union(v.id("venues"), v.null()),
  venue: v.union(venuePayloadValidator, v.null()),
  area: v.string(),
  venueType: v.union(venueTypeValidator, v.null()),
  title: v.string(),
  desc: v.string(),
  eventType: v.union(v.string(), v.null()),
  expectedAttendance: v.union(v.number(), v.null()),
  genres: v.array(v.string()),
  startsAt: v.number(),
  doorsAt: v.union(v.number(), v.null()),
  endsAt: v.union(v.number(), v.null()),
  ageRequirement: ageRequirementValidator,
  equipment: v.union(v.string(), v.null()),
  requirements: v.union(v.string(), v.null()),
  flyKey: v.string(),
  flyerUrl: v.union(v.string(), v.null()),
  applicationsCloseAt: v.number(),
  visibility: opportunityVisibilityValidator,
  ticketing: opportunityTicketingValidator,
  currency: v.string(),
  externalUrl: v.union(v.string(), v.null()),
  status: opportunityStatusValidator,
  slug: v.string(),
  revision: v.number(),
  applicationCount: v.number(),
  slots: v.array(opportunitySlotPayloadValidator),
  invitedBandIds: v.array(v.id("bands")),
  createdAt: v.number(),
  updatedAt: v.number(),
});

export const artistOpportunityPayloadValidator =
  opportunityPayloadValidator.omit("invitedBandIds");

export async function toArtistOpportunityPayload(
  ctx: QueryCtx | MutationCtx,
  opportunity: Doc<"talentOpportunities">,
): Promise<Infer<typeof artistOpportunityPayloadValidator>> {
  const { invitedBandIds: _invitedBandIds, ...payload } =
    await toOpportunityPayload(ctx, opportunity);
  return payload;
}

export async function toOpportunityPayload(
  ctx: QueryCtx | MutationCtx,
  opportunity: Doc<"talentOpportunities">,
): Promise<Infer<typeof opportunityPayloadValidator>> {
  const slots = await ctx.db
    .query("opportunitySlots")
    .withIndex("by_opportunityId_and_order", (q) =>
      q.eq("opportunityId", opportunity._id),
    )
    .order("asc")
    .take(20);
  const invites = await ctx.db
    .query("opportunityInvites")
    .withIndex("by_opportunityId_and_bandId", (q) =>
      q.eq("opportunityId", opportunity._id),
    )
    .take(100);
  const venue = opportunity.venueId
    ? await ctx.db.get(opportunity.venueId)
    : null;
  const flyerUrl = opportunity.flyStorageId
    ? await ctx.storage.getUrl(opportunity.flyStorageId)
    : null;

  return {
    _id: opportunity._id,
    organizationId: opportunity.organizationId,
    mode: opportunity.mode,
    venueId: opportunity.venueId ?? null,
    venue: venue ? toVenuePayload(venue) : null,
    area: opportunity.area,
    venueType: opportunity.venueType ?? null,
    title: opportunity.title,
    desc: opportunity.desc,
    eventType: opportunity.eventType ?? null,
    expectedAttendance: opportunity.expectedAttendance ?? null,
    genres: opportunity.genres,
    startsAt: opportunity.startsAt,
    doorsAt: opportunity.doorsAt ?? null,
    endsAt: opportunity.endsAt ?? null,
    ageRequirement: opportunity.ageRequirement,
    equipment: opportunity.equipment ?? null,
    requirements: opportunity.requirements ?? null,
    flyKey: opportunity.flyKey,
    flyerUrl,
    applicationsCloseAt: opportunity.applicationsCloseAt,
    visibility: opportunity.visibility,
    ticketing: opportunity.ticketing,
    currency: opportunity.currency,
    externalUrl: opportunity.externalUrl ?? null,
    status: opportunity.status,
    slug: opportunity.slug,
    revision: opportunity.revision,
    applicationCount: opportunity.applicationCount,
    slots: slots.map((slot) => ({
      _id: slot._id,
      order: slot.order,
      role: slot.role,
      setLengthMin: slot.setLengthMin ?? null,
      guaranteeMinor: slot.guaranteeMinor,
      required: slot.required,
      status: slot.status,
      bandId: slot.bandId ?? null,
    })),
    invitedBandIds: invites.map((invite) => invite.bandId),
    createdAt: opportunity.createdAt,
    updatedAt: opportunity.updatedAt,
  };
}
