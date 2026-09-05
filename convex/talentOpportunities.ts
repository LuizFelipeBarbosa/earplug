import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { MutationCtx, internalMutation, mutation } from "./_generated/server";
import { loadCurrentOffer, sendBookingEmail } from "./bookings";
import { requireOrganizationRole } from "./lib/authz";
import { releaseSlot } from "./lib/bookingConfirm";
import { assertBookingTransition } from "./lib/bookingStatus";
import { unpublishOpportunityGig } from "./lib/gigPublish";
import {
  assertUploadAcceptable,
  isReservedPublicSlug,
  isValidHttpsUrl,
  slugify,
} from "./lib/helpers";
import { MAX_OPPORTUNITY_SLOTS } from "./lib/opportunityPayload";
import {
  APPLICATION_ACTIVE_STATUSES,
  assertApplicationTransition,
  assertOpportunityTransition,
  assertSlotTransition,
  type ArtistApplicationStatus,
} from "./lib/opportunityStatus";
import {
  ageRequirementValidator,
  gigPerformerRoleValidator,
  opportunityModeValidator,
  opportunityTicketingValidator,
  opportunityVisibilityValidator,
} from "./schema";

const APPLICATION_LEAD_TIME_MS = 7 * 24 * 60 * 60 * 1000;
const APPLICATION_DEADLINE_EXPIRABLE_STATUSES: readonly ArtistApplicationStatus[] = [
  "submitted",
  "under_review",
];

const slotInputValidator = v.object({
  role: gigPerformerRoleValidator,
  setLengthMin: v.optional(v.number()),
  guaranteeMinor: v.number(),
  required: v.optional(v.boolean()),
});

const opportunityFieldsValidator = v.object({
  title: v.string(),
  desc: v.optional(v.string()),
  eventType: v.optional(v.string()),
  expectedAttendance: v.optional(v.number()),
  genres: v.optional(v.array(v.string())),
  startsAt: v.number(),
  doorsAt: v.optional(v.number()),
  endsAt: v.optional(v.number()),
  ageRequirement: v.optional(ageRequirementValidator),
  equipment: v.optional(v.string()),
  requirements: v.optional(v.string()),
  flyKey: v.optional(v.string()),
  flyStorageId: v.optional(v.id("_storage")),
  applicationsCloseAt: v.optional(v.number()),
  visibility: v.optional(opportunityVisibilityValidator),
  ticketing: v.optional(opportunityTicketingValidator),
  currency: v.optional(v.string()),
  externalUrl: v.optional(v.string()),
});

function resolveClearable<T>(
  provided: T | null | undefined,
  current: T | undefined,
): T | undefined {
  if (provided === undefined) return current;
  return provided === null ? undefined : provided;
}

async function normalizeAndValidateFields(
  ctx: MutationCtx,
  args: Infer<typeof opportunityFieldsValidator>,
) {
  const title = args.title.trim();
  if (!title || title.length > 120) {
    throw new Error("Title must be between 1 and 120 characters");
  }
  const desc = (args.desc ?? "").trim();
  if (desc.length > 2000) throw new Error("Description is too long");
  const genres = (args.genres ?? [])
    .map((genre) => genre.trim())
    .filter(Boolean);
  if (genres.length > 5 || genres.some((genre) => genre.length > 50)) {
    throw new Error("Choose up to 5 genres of at most 50 characters each");
  }
  for (const [name, value] of [
    ["startsAt", args.startsAt],
    ["doorsAt", args.doorsAt],
    ["endsAt", args.endsAt],
  ] as const) {
    if (value !== undefined && (!Number.isFinite(value) || value < 0)) {
      throw new Error(`Invalid ${name}`);
    }
  }
  const applicationsCloseAt =
    args.applicationsCloseAt ?? args.startsAt - APPLICATION_LEAD_TIME_MS;
  if (
    !Number.isFinite(applicationsCloseAt) ||
    !(applicationsCloseAt < args.startsAt)
  ) {
    throw new Error("Applications must close before the event starts");
  }
  const ticketing = args.ticketing ?? "rsvp";
  if (ticketing === "external" && !isValidHttpsUrl(args.externalUrl)) {
    throw new Error("External ticketing requires a valid HTTPS URL");
  }
  const flyKey = args.flyKey ?? "xerox";
  if (flyKey === "custom") {
    if (args.flyStorageId === undefined) {
      throw new Error("Custom flyer requires flyStorageId");
    }
    const upload = await ctx.db.system.get("_storage", args.flyStorageId);
    if (!upload) throw new Error("Flyer upload not found");
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
  }
  return {
    title,
    desc,
    genres,
    startsAt: args.startsAt,
    applicationsCloseAt,
    ticketing,
    flyKey,
    visibility: args.visibility ?? "public",
    ageRequirement: args.ageRequirement ?? "allAges",
    currency: (args.currency ?? "usd").trim() || "usd",
    ...(args.eventType !== undefined ? { eventType: args.eventType } : {}),
    ...(args.expectedAttendance !== undefined
      ? { expectedAttendance: args.expectedAttendance }
      : {}),
    ...(args.doorsAt !== undefined ? { doorsAt: args.doorsAt } : {}),
    ...(args.endsAt !== undefined ? { endsAt: args.endsAt } : {}),
    ...(args.equipment !== undefined ? { equipment: args.equipment } : {}),
    ...(args.requirements !== undefined
      ? { requirements: args.requirements }
      : {}),
    ...(args.flyStorageId !== undefined
      ? { flyStorageId: args.flyStorageId }
      : {}),
    ...(args.externalUrl !== undefined
      ? { externalUrl: args.externalUrl }
      : {}),
  };
}

function normalizeAndValidateSlots(
  input: Infer<typeof slotInputValidator>[] | undefined,
): Infer<typeof slotInputValidator>[] {
  const slots = input?.length
    ? input
    : [{ role: "headliner" as const, guaranteeMinor: 0, required: true }];
  if (slots.length > MAX_OPPORTUNITY_SLOTS) {
    throw new Error(`Choose between 1 and ${MAX_OPPORTUNITY_SLOTS} slots`);
  }
  for (const slot of slots) {
    if (!Number.isInteger(slot.guaranteeMinor) || slot.guaranteeMinor < 0) {
      throw new Error("Slot guarantee must be a non-negative integer");
    }
    if (
      slot.setLengthMin !== undefined &&
      (!Number.isInteger(slot.setLengthMin) ||
        slot.setLengthMin < 1 ||
        slot.setLengthMin > 600)
    ) {
      throw new Error(
        "Set length must be an integer between 1 and 600 minutes",
      );
    }
  }
  return slots;
}

async function insertSlots(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  slots: Infer<typeof slotInputValidator>[],
) {
  for (const [order, slot] of slots.entries()) {
    await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order,
      role: slot.role,
      guaranteeMinor: slot.guaranteeMinor,
      required: slot.required ?? true,
      status: "open",
      ...(slot.setLengthMin !== undefined
        ? { setLengthMin: slot.setLengthMin }
        : {}),
    });
  }
}

async function requireVerifiedVenue(
  ctx: MutationCtx,
  venueId: Id<"venues">,
  organizationId: Id<"organizations">,
) {
  const venue = await ctx.db.get(venueId);
  if (!venue) throw new Error("Venue not found");
  if (
    venue.managedByOrganizationId !== organizationId ||
    venue.status !== "verified"
  ) {
    throw new Error("Choose one of your verified venues");
  }
  return venue;
}

async function requireOpportunityManager(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
) {
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  const { organization, user } = await requireOrganizationRole(
    ctx,
    opportunity.organizationId,
    ["owner", "manager"],
  );
  if (organization.status !== "verified") {
    throw new Error("Organization must be verified");
  }
  return { opportunity, user };
}

async function uniqueOpportunitySlug(
  ctx: MutationCtx,
  title: string,
): Promise<string> {
  const generated = slugify(title);
  const base = generated === "band" ? "opportunity" : generated;
  for (let suffix = 1; ; suffix++) {
    const candidate = suffix === 1 ? base : `${base}-${suffix}`;
    if (isReservedPublicSlug(candidate)) continue;
    const existing = await ctx.db
      .query("talentOpportunities")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (!existing) return candidate;
  }
}

export const create = mutation({
  args: {
    organizationId: v.id("organizations"),
    venueId: v.id("venues"),
    mode: v.optional(opportunityModeValidator),
    ...opportunityFieldsValidator.fields,
    slots: v.optional(v.array(slotInputValidator)),
  },
  returns: v.object({
    opportunityId: v.id("talentOpportunities"),
    slug: v.string(),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { organization, user } = await requireOrganizationRole(
      ctx,
      args.organizationId,
      ["owner", "manager"],
    );
    if (organization.status !== "verified") {
      throw new Error("Organization must be verified");
    }
    const mode = args.mode ?? "publicEvent";
    if (mode === "privateBooking") {
      throw new Error("Private bookings are not available yet");
    }
    const venue = await requireVerifiedVenue(
      ctx,
      args.venueId,
      args.organizationId,
    );
    const fields = await normalizeAndValidateFields(ctx, args);
    const slots = normalizeAndValidateSlots(args.slots);
    const slug = await uniqueOpportunitySlug(ctx, fields.title);
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId: args.organizationId,
      mode,
      venueId: venue._id,
      area: venue.approxLabel ?? venue.area,
      ...(venue.venueType !== undefined ? { venueType: venue.venueType } : {}),
      ...fields,
      slug,
      status: "draft",
      revision: 1,
      applicationCount: 0,
      createdBy: user._id,
      createdAt: now,
      updatedAt: now,
    });
    await insertSlots(ctx, opportunityId, slots);
    return { opportunityId, slug };
  },
});

export const update = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    expectedRevision: v.number(),
    venueId: v.optional(v.id("venues")),
    ...opportunityFieldsValidator.partial().fields,
    eventType: v.optional(v.union(v.string(), v.null())),
    expectedAttendance: v.optional(v.union(v.number(), v.null())),
    doorsAt: v.optional(v.union(v.number(), v.null())),
    endsAt: v.optional(v.union(v.number(), v.null())),
    equipment: v.optional(v.union(v.string(), v.null())),
    requirements: v.optional(v.union(v.string(), v.null())),
    externalUrl: v.optional(v.union(v.string(), v.null())),
    flyStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    slots: v.optional(v.array(slotInputValidator)),
  },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    if (args.expectedRevision !== opportunity.revision) {
      throw new Error("Opportunity changed elsewhere");
    }
    if (opportunity.status !== "draft" && opportunity.status !== "open") {
      throw new Error("Opportunity can no longer be edited");
    }
    if (args.slots !== undefined && opportunity.status !== "draft") {
      throw new Error("Slots are locked once applications are open");
    }
    const venueChanged =
      args.venueId !== undefined && args.venueId !== opportunity.venueId;
    if (venueChanged && opportunity.status !== "draft") {
      throw new Error(
        "Venue can only be changed while the opportunity is still a draft",
      );
    }
    const venue = venueChanged
      ? await requireVerifiedVenue(
          ctx,
          args.venueId!,
          opportunity.organizationId,
        )
      : null;
    const startsAt = args.startsAt ?? opportunity.startsAt;
    const applicationsCloseAt =
      args.applicationsCloseAt ?? opportunity.applicationsCloseAt;
    // Check open timing first so normalization cannot mask open's error messages.
    if (opportunity.status === "open") {
      if (!(startsAt > now)) {
        throw new Error("The event has already started");
      }
      if (!(applicationsCloseAt > now && applicationsCloseAt < startsAt)) {
        throw new Error("Set an applications deadline before the event starts");
      }
    }
    const effectiveFlyKey = args.flyKey ?? opportunity.flyKey;
    const fields = await normalizeAndValidateFields(ctx, {
      title: args.title ?? opportunity.title,
      desc: args.desc ?? opportunity.desc,
      eventType: resolveClearable(args.eventType, opportunity.eventType),
      expectedAttendance: resolveClearable(
        args.expectedAttendance,
        opportunity.expectedAttendance,
      ),
      genres: args.genres ?? opportunity.genres,
      startsAt,
      doorsAt: resolveClearable(args.doorsAt, opportunity.doorsAt),
      endsAt: resolveClearable(args.endsAt, opportunity.endsAt),
      ageRequirement: args.ageRequirement ?? opportunity.ageRequirement,
      equipment: resolveClearable(args.equipment, opportunity.equipment),
      requirements: resolveClearable(
        args.requirements,
        opportunity.requirements,
      ),
      flyKey:
        args.flyStorageId === null && effectiveFlyKey === "custom"
          ? "xerox"
          : effectiveFlyKey,
      flyStorageId: resolveClearable(
        args.flyStorageId,
        opportunity.flyStorageId,
      ),
      applicationsCloseAt,
      visibility: args.visibility ?? opportunity.visibility,
      ticketing: args.ticketing ?? opportunity.ticketing,
      currency: args.currency ?? opportunity.currency,
      externalUrl: resolveClearable(args.externalUrl, opportunity.externalUrl),
    });
    if (args.slots !== undefined) {
      const slots = normalizeAndValidateSlots(args.slots);
      const existing = await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunity._id),
        )
        .take(MAX_OPPORTUNITY_SLOTS + 5);
      for (const slot of existing) await ctx.db.delete(slot._id);
      await insertSlots(ctx, opportunity._id, slots);
    }
    const clearedFields = {
      ...(args.eventType === null ? { eventType: undefined } : {}),
      ...(args.expectedAttendance === null
        ? { expectedAttendance: undefined }
        : {}),
      ...(args.doorsAt === null ? { doorsAt: undefined } : {}),
      ...(args.endsAt === null ? { endsAt: undefined } : {}),
      ...(args.equipment === null ? { equipment: undefined } : {}),
      ...(args.requirements === null ? { requirements: undefined } : {}),
      ...(args.externalUrl === null ? { externalUrl: undefined } : {}),
      ...(args.flyStorageId === null ? { flyStorageId: undefined } : {}),
    };
    const revision = opportunity.revision + 1;
    await ctx.db.patch(opportunity._id, {
      ...fields,
      ...clearedFields,
      ...(venue
        ? {
            venueId: venue._id,
            area: venue.approxLabel ?? venue.area,
            // Explicit undefined clears the old venue's optional type on a patch.
            venueType: venue.venueType,
          }
        : {}),
      revision,
      updatedAt: now,
    });
    if (opportunity.status === "open") {
      // Every edit invalidates the previous job's revision guard.
      await ctx.scheduler.runAt(
        fields.applicationsCloseAt,
        internal.talentOpportunities.expireApplications,
        {
          opportunityId: opportunity._id,
          expectedRevision: revision,
        },
      );
    }
    return { revision };
  },
});

export const open = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    expectedRevision: v.number(),
  },
  returns: v.object({ revision: v.number(), applicationsCloseAt: v.number() }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    if (args.expectedRevision !== opportunity.revision) {
      throw new Error("Opportunity changed elsewhere");
    }
    assertOpportunityTransition(opportunity.status, "open");
    const slots = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(MAX_OPPORTUNITY_SLOTS + 1);
    if (slots.length === 0)
      throw new Error("Add at least one slot before opening");
    if (!(opportunity.startsAt > now))
      throw new Error("The event has already started");
    if (!(
      opportunity.applicationsCloseAt > now &&
      opportunity.applicationsCloseAt < opportunity.startsAt
    )) {
      throw new Error("Set an applications deadline before the event starts");
    }
    const revision = opportunity.revision + 1;
    await ctx.db.patch(opportunity._id, {
      status: "open",
      revision,
      updatedAt: now,
    });
    await ctx.scheduler.runAt(
      opportunity.applicationsCloseAt,
      internal.talentOpportunities.expireApplications,
      {
        opportunityId: opportunity._id,
        expectedRevision: revision,
      },
    );
    return { revision, applicationsCloseAt: opportunity.applicationsCloseAt };
  },
});

export const closeApplications = mutation({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    assertOpportunityTransition(opportunity.status, "applications_closed");
    await ctx.db.patch(opportunity._id, {
      status: "applications_closed",
      revision: opportunity.revision + 1,
      updatedAt: now,
    });
    await expireActiveApplications(ctx, opportunity._id, {
      statuses: APPLICATION_DEADLINE_EXPIRABLE_STATUSES,
      to: "expired",
    });
    return null;
  },
});

export const reopen = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    applicationsCloseAt: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    assertOpportunityTransition(opportunity.status, "open");
    if (!(
      args.applicationsCloseAt > now &&
      args.applicationsCloseAt < opportunity.startsAt
    )) {
      throw new Error("Set an applications deadline before the event starts");
    }
    const revision = opportunity.revision + 1;
    await ctx.db.patch(opportunity._id, {
      status: "open",
      applicationsCloseAt: args.applicationsCloseAt,
      revision,
      updatedAt: now,
    });
    await ctx.scheduler.runAt(
      args.applicationsCloseAt,
      internal.talentOpportunities.expireApplications,
      {
        opportunityId: opportunity._id,
        expectedRevision: revision,
      },
    );
    return null;
  },
});

export const cancel = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    reason: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity, user } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    assertOpportunityTransition(opportunity.status, "cancelled");
    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_opportunityId", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(500);
    for (const booking of bookings) {
      if (
        booking.status !== "offer_sent" &&
        booking.status !== "artist_accepted" &&
        booking.status !== "awaiting_payment" &&
        booking.status !== "confirmed"
      ) {
        continue;
      }
      const status =
        booking.status === "confirmed" ? "cancelled_by_organizer" : "withdrawn";
      assertBookingTransition(booking.status, status);
      await ctx.db.patch(booking._id, {
        status,
        cancelledBy: "organizer",
        cancelledByUserId: user._id,
        cancelledAt: now,
        cancelReason: "Opportunity cancelled",
        revision: booking.revision + 1,
        updatedAt: now,
      });
      if (status === "withdrawn") {
        const offer = await loadCurrentOffer(ctx, booking);
        await ctx.db.patch(offer._id, {
          response: "withdrawn",
          respondedAt: now,
          respondedBy: user._id,
        });
        const application = await ctx.db.get(booking.applicationId);
        if (application?.status === "offered") {
          assertApplicationTransition(application.status, "shortlisted");
          await ctx.db.patch(application._id, {
            status: "shortlisted",
            updatedAt: now,
          });
        }
      } else {
        await releaseSlot(ctx, booking.slotId);
        const application = await ctx.db.get(booking.applicationId);
        if (application?.status === "booked") {
          assertApplicationTransition(application.status, "declined");
          await ctx.db.patch(application._id, {
            status: "declined",
            updatedAt: now,
          });
        }
      }
      const cancelledBooking = await ctx.db.get(booking._id);
      if (!cancelledBooking) throw new Error("Booking not found");
      await sendBookingEmail(ctx, cancelledBooking, "bookingCancelled");
    }
    if (opportunity.publicGigId !== undefined) {
      await unpublishOpportunityGig(ctx, opportunity._id, "opportunity_cancelled");
    } else {
      await ctx.db.patch(opportunity._id, {
        status: "cancelled",
        revision: opportunity.revision + 1,
        updatedAt: now,
      });
    }
    await expireActiveApplications(ctx, opportunity._id, {
      statuses: APPLICATION_ACTIVE_STATUSES,
      to: "declined",
      decidedBy: user._id,
    });
    const slots = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(MAX_OPPORTUNITY_SLOTS + 1);
    for (const slot of slots) {
      if (slot.status === "open") {
        assertSlotTransition(slot.status, "cancelled");
        await ctx.db.patch(slot._id, { status: "cancelled" });
      }
    }
    return null;
  },
});

export const deleteDraft = mutation({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    if (opportunity.status !== "draft")
      throw new Error("Only a draft can be deleted");
    const slots = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(MAX_OPPORTUNITY_SLOTS + 5);
    const invites = await ctx.db
      .query("opportunityInvites")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(105);
    for (const slot of slots) await ctx.db.delete(slot._id);
    for (const invite of invites) await ctx.db.delete(invite._id);
    await ctx.db.delete(opportunity._id);
    return null;
  },
});

export const duplicate = mutation({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.object({
    opportunityId: v.id("talentOpportunities"),
    slug: v.string(),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity: source, user } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    const title = `${source.title} (copy)`.slice(0, 120);
    const slug = await uniqueOpportunitySlug(ctx, title);
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId: source.organizationId,
      mode: source.mode,
      ...(source.venueId !== undefined ? { venueId: source.venueId } : {}),
      area: source.area,
      ...(source.venueType !== undefined
        ? { venueType: source.venueType }
        : {}),
      title,
      desc: source.desc,
      ...(source.eventType !== undefined
        ? { eventType: source.eventType }
        : {}),
      ...(source.expectedAttendance !== undefined
        ? { expectedAttendance: source.expectedAttendance }
        : {}),
      genres: source.genres,
      startsAt: source.startsAt,
      ...(source.doorsAt !== undefined ? { doorsAt: source.doorsAt } : {}),
      ...(source.endsAt !== undefined ? { endsAt: source.endsAt } : {}),
      ageRequirement: source.ageRequirement,
      ...(source.equipment !== undefined
        ? { equipment: source.equipment }
        : {}),
      ...(source.requirements !== undefined
        ? { requirements: source.requirements }
        : {}),
      flyKey: source.flyKey,
      ...(source.flyStorageId !== undefined
        ? { flyStorageId: source.flyStorageId }
        : {}),
      applicationsCloseAt: source.applicationsCloseAt,
      visibility: source.visibility,
      ticketing: source.ticketing,
      currency: source.currency,
      ...(source.externalUrl !== undefined
        ? { externalUrl: source.externalUrl }
        : {}),
      slug,
      status: "draft",
      revision: 1,
      applicationCount: 0,
      createdBy: user._id,
      createdAt: now,
      updatedAt: now,
    });
    const slots = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", source._id),
      )
      .take(MAX_OPPORTUNITY_SLOTS + 5);
    for (const slot of slots) {
      await ctx.db.insert("opportunitySlots", {
        opportunityId,
        order: slot.order,
        role: slot.role,
        ...(slot.setLengthMin !== undefined
          ? { setLengthMin: slot.setLengthMin }
          : {}),
        guaranteeMinor: slot.guaranteeMinor,
        required: slot.required,
        status: "open",
      });
    }
    return { opportunityId, slug };
  },
});

export const inviteBand = mutation({
  args: { opportunityId: v.id("talentOpportunities"), bandId: v.id("bands") },
  returns: v.object({ invited: v.boolean() }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity, user } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    if (opportunity.status !== "draft" && opportunity.status !== "open") {
      throw new Error("Invites are closed for this opportunity");
    }
    const band = await ctx.db.get(args.bandId);
    if (!band || band.archivedAt !== undefined)
      throw new Error("Band not found");
    const existing = await ctx.db
      .query("opportunityInvites")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", opportunity._id).eq("bandId", args.bandId),
      )
      .unique();
    if (existing) return { invited: false };
    await ctx.db.insert("opportunityInvites", {
      opportunityId: opportunity._id,
      bandId: args.bandId,
      invitedBy: user._id,
      createdAt: now,
    });
    return { invited: true };
  },
});

export const uninviteBand = mutation({
  args: { opportunityId: v.id("talentOpportunities"), bandId: v.id("bands") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    const invite = await ctx.db
      .query("opportunityInvites")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", opportunity._id).eq("bandId", args.bandId),
      )
      .unique();
    if (invite) await ctx.db.delete(invite._id);
    return null;
  },
});

export const expireApplications = internalMutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    expectedRevision: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const opportunity = await ctx.db.get(args.opportunityId);
    if (
      !opportunity ||
      opportunity.status !== "open" ||
      opportunity.revision !== args.expectedRevision
    ) {
      return null;
    }
    await ctx.db.patch(opportunity._id, {
      status: "applications_closed",
      revision: opportunity.revision + 1,
      updatedAt: now,
    });
    await expireActiveApplications(ctx, opportunity._id, {
      statuses: APPLICATION_DEADLINE_EXPIRABLE_STATUSES,
      to: "expired",
    });
    return null;
  },
});

async function expireActiveApplications(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  options: {
    statuses: readonly ArtistApplicationStatus[];
    to: "expired" | "declined";
    decidedBy?: Id<"users">;
  },
): Promise<void> {
  const now = Date.now();
  let patchedCount = 0;
  for (const status of options.statuses) {
    for (;;) {
      const page = await ctx.db
        .query("artistApplications")
        .withIndex("by_opportunityId_and_status", (q) =>
          q.eq("opportunityId", opportunityId).eq("status", status),
        )
        .take(200);
      for (const application of page) {
        await ctx.db.patch(application._id, {
          status: options.to,
          decidedAt: now,
          updatedAt: now,
          ...(options.decidedBy ? { decidedBy: options.decidedBy } : {}),
        });
        patchedCount++;
      }
      if (page.length < 200) break;
    }
  }
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) return;
  await ctx.db.patch(opportunityId, {
    applicationCount: Math.max(0, opportunity.applicationCount - patchedCount),
    updatedAt: now,
  });
}
