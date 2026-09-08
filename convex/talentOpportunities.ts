import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, internalMutation, mutation } from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";
import { flag } from "./lib/env";
import { BOOKING_ACTIVE_STATUSES } from "./lib/bookingStatus";
import { syncGigTicketing } from "./lib/gigPublish";
import {
  assertUploadAcceptable,
  isReservedPublicSlug,
  isValidHttpsUrl,
  slugify,
} from "./lib/helpers";
import {
  cancelOpportunity,
  expireActiveApplications,
} from "./lib/opportunityCancel";
import { MAX_OPPORTUNITY_SLOTS } from "./lib/opportunityPayload";
import {
  assertOpportunityTransition,
  type ArtistApplicationStatus,
} from "./lib/opportunityStatus";
import { consentRequiredFor, currentConsentFor } from "./lib/venueConsentStatus";
import { requireOwnedPrivateLocation } from "./privateLocations";
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
  ticketPriceMinor: v.optional(v.number()),
  ticketCapacity: v.optional(v.number()),
  ticketCurrency: v.optional(v.string()),
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

export function requirePrivateBookingsEnabled(): void {
  if (!flag("PRIVATE_BOOKINGS_ENABLED", false)) {
    throw new Error("Private bookings are not available yet");
  }
}

function validateTicketPriceAndCapacity(
  ticketPriceMinor: number | undefined,
  ticketCapacity: number | undefined,
): { ticketPriceMinor: number; ticketCapacity: number } {
  if (
    ticketPriceMinor === undefined ||
    !Number.isInteger(ticketPriceMinor) ||
    ticketPriceMinor < 100
  ) {
    throw new Error("Ticket price must be at least $1.00");
  }
  if (
    ticketCapacity === undefined ||
    !Number.isInteger(ticketCapacity) ||
    ticketCapacity < 1 ||
    ticketCapacity > 5000
  ) {
    throw new Error("Ticket capacity must be between 1 and 5,000");
  }
  return { ticketPriceMinor, ticketCapacity };
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
  if (ticketing === "paid" && !flag("TICKETS_ENABLED", false)) {
    throw new Error("Paid ticketing is not available yet");
  }
  if (ticketing === "external" && !isValidHttpsUrl(args.externalUrl)) {
    throw new Error("External ticketing requires a valid HTTPS URL");
  }
  let ticketPriceMinor: number | undefined;
  let ticketCapacity: number | undefined;
  let ticketCurrency: string | undefined;
  if (ticketing === "paid") {
    ticketCurrency = (args.ticketCurrency ?? "usd").trim().toLowerCase() || "usd";
    if (ticketCurrency !== "usd") {
      throw new Error("Only USD ticketing is supported right now");
    }
    ({ ticketPriceMinor, ticketCapacity } = validateTicketPriceAndCapacity(
      args.ticketPriceMinor,
      args.ticketCapacity,
    ));
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
    ticketPriceMinor,
    ticketCapacity,
    ticketCurrency,
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

async function requireUsableVenue(
  ctx: MutationCtx,
  organizationId: Id<"organizations">,
  venueId: Id<"venues">,
): Promise<{ venue: Doc<"venues">; consentRequired: boolean }> {
  const venue = await ctx.db.get(venueId);
  if (!venue) throw new Error("Venue not found");
  if (venue.managedByOrganizationId === organizationId) {
    if (venue.status !== "verified") {
      throw new Error("Choose one of your verified venues");
    }
    return { venue, consentRequired: false };
  }
  const consentRequired = consentRequiredFor(venue, organizationId);
  if (consentRequired && !flag("PROMOTERS_ENABLED", false)) {
    throw new Error("Venue approval is not available yet");
  }
  return { venue, consentRequired };
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
    venueId: v.optional(v.id("venues")),
    privateLocationId: v.optional(v.id("privateLocations")),
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
    let locationFields: Pick<
      Doc<"talentOpportunities">,
      "area" | "venueId" | "venueType" | "privateLocationId"
    >;
    if (mode === "privateBooking") {
      requirePrivateBookingsEnabled();
      if (organization.orgType !== "privateHost") {
        throw new Error("Only verified hosts post private requests");
      }
      if (args.privateLocationId === undefined) {
        throw new Error("Choose a location");
      }
      const location = await requireOwnedPrivateLocation(
        ctx,
        args.privateLocationId,
        args.organizationId,
      );
      if (location.archivedAt !== undefined) {
        throw new Error("Choose an active location");
      }
      if (args.venueId !== undefined) {
        throw new Error("Private requests don't use a venue");
      }
      locationFields = { privateLocationId: location._id, area: location.area };
    } else {
      if (args.privateLocationId !== undefined) {
        throw new Error("Public events don't use a private location");
      }
      if (args.venueId === undefined) {
        throw new Error("Choose one of your verified venues");
      }
      const { venue } = await requireUsableVenue(
        ctx,
        args.organizationId,
        args.venueId,
      );
      locationFields = {
        venueId: venue._id,
        area: venue.approxLabel ?? venue.area,
        ...(venue.venueType !== undefined ? { venueType: venue.venueType } : {}),
      };
    }
    const slots = normalizeAndValidateSlots(args.slots);
    if (mode === "privateBooking") {
      if (slots.some((slot) => slot.guaranteeMinor <= 0)) {
        throw new Error("Private slots need a guarantee");
      }
      if (
        args.applicationsCloseAt === undefined ||
        !(args.applicationsCloseAt < args.startsAt)
      ) {
        throw new Error("Set an application deadline before the event");
      }
    }
    const { ticketPriceMinor, ticketCapacity, ticketCurrency, ...fieldsInput } =
      args;
    const fields = await normalizeAndValidateFields(ctx, {
      ...fieldsInput,
      ...(mode === "privateBooking"
        ? { ticketing: "none" as const }
        : { ticketPriceMinor, ticketCapacity, ticketCurrency }),
    });
    const slug = await uniqueOpportunitySlug(ctx, fields.title);
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId: args.organizationId,
      mode,
      ...locationFields,
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
    privateLocationId: v.optional(v.id("privateLocations")),
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
    if (opportunity.mode === "privateBooking") {
      requirePrivateBookingsEnabled();
    }
    if (opportunity.status !== "draft" && opportunity.status !== "open") {
      throw new Error("Opportunity can no longer be edited");
    }
    if (args.slots !== undefined && opportunity.status !== "draft") {
      throw new Error("Slots are locked once applications are open");
    }
    if (opportunity.mode === "privateBooking" && args.venueId !== undefined) {
      throw new Error("Private requests don't use a venue");
    }
    if (
      opportunity.mode === "publicEvent" &&
      args.privateLocationId !== undefined
    ) {
      throw new Error("Public events don't use a private location");
    }
    const venueChanged =
      args.venueId !== undefined && args.venueId !== opportunity.venueId;
    if (venueChanged && opportunity.status !== "draft") {
      throw new Error(
        "Venue can only be changed while the opportunity is still a draft",
      );
    }
    const startsAtChanged =
      args.startsAt !== undefined && args.startsAt !== opportunity.startsAt;
    const doorsAtChanged =
      args.doorsAt !== undefined && args.doorsAt !== (opportunity.doorsAt ?? null);
    const endsAtChanged =
      args.endsAt !== undefined && args.endsAt !== (opportunity.endsAt ?? null);
    if (venueChanged || startsAtChanged || doorsAtChanged || endsAtChanged) {
      if (await currentConsentFor(ctx, opportunity._id)) {
        throw new Error(
          "Withdraw the venue request before changing the venue or date",
        );
      }
    }
    const venue = venueChanged
      ? (
          await requireUsableVenue(ctx, opportunity.organizationId, args.venueId!)
        ).venue
      : null;
    const locationChanged =
      args.privateLocationId !== undefined &&
      args.privateLocationId !== opportunity.privateLocationId;
    const location = locationChanged
      ? await requireOwnedPrivateLocation(
          ctx,
          args.privateLocationId!,
          opportunity.organizationId,
        )
      : null;
    if (location && location.archivedAt !== undefined) {
      throw new Error("Choose an active location");
    }
    if (startsAtChanged || doorsAtChanged) {
      const bookings = ctx.db
        .query("bookings")
        .withIndex("by_opportunityId", (q) =>
          q.eq("opportunityId", opportunity._id),
        );
      for await (const booking of bookings) {
        if (BOOKING_ACTIVE_STATUSES.includes(booking.status)) {
          throw new Error("Dates are locked while offers or bookings are active");
        }
      }
    }
    const startsAt = args.startsAt ?? opportunity.startsAt;
    const applicationsCloseAt =
      args.applicationsCloseAt ?? opportunity.applicationsCloseAt;
    if (
      opportunity.mode === "privateBooking" &&
      !(applicationsCloseAt < startsAt)
    ) {
      throw new Error("Set an application deadline before the event");
    }
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
      ...(opportunity.mode === "privateBooking"
        ? { ticketing: "none" as const }
        : {
            ticketing: args.ticketing ?? opportunity.ticketing,
            ticketPriceMinor:
              args.ticketPriceMinor ?? opportunity.ticketPriceMinor,
            ticketCapacity: args.ticketCapacity ?? opportunity.ticketCapacity,
            ticketCurrency: args.ticketCurrency ?? opportunity.ticketCurrency,
          }),
      currency: args.currency ?? opportunity.currency,
      externalUrl: resolveClearable(args.externalUrl, opportunity.externalUrl),
    });
    if (args.slots !== undefined) {
      const slots = normalizeAndValidateSlots(args.slots);
      if (
        opportunity.mode === "privateBooking" &&
        slots.some((slot) => slot.guaranteeMinor <= 0)
      ) {
        throw new Error("Private slots need a guarantee");
      }
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
      ...(location
        ? { privateLocationId: location._id, area: location.area }
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

export const updateTicketing = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    expectedRevision: v.number(),
    ticketPriceMinor: v.number(),
    ticketCapacity: v.number(),
  },
  returns: v.object({ revision: v.number(), capacity: v.number() }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { opportunity } = await requireOpportunityManager(
      ctx,
      args.opportunityId,
    );
    if (args.expectedRevision !== opportunity.revision) {
      throw new Error("Opportunity changed elsewhere");
    }
    if (
      opportunity.ticketing !== "paid" ||
      (opportunity.status !== "confirmed" && opportunity.status !== "booking")
    ) {
      throw new Error("Ticket details can only change on a live paid event");
    }
    if (opportunity.startsAt <= now) {
      throw new Error("This event has already started");
    }
    const fields = validateTicketPriceAndCapacity(
      args.ticketPriceMinor,
      args.ticketCapacity,
    );
    const gigId = opportunity.publicGigId;
    if (gigId !== undefined) {
      const inventory = await ctx.db
        .query("gigTicketInventory")
        .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
        .unique();
      if (
        inventory &&
        fields.ticketCapacity < inventory.sold + inventory.reserved
      ) {
        throw new Error("Capacity cannot go below tickets already sold or held");
      }
    }
    const revision = opportunity.revision + 1;
    await ctx.db.patch(opportunity._id, {
      ...fields,
      revision,
      updatedAt: now,
    });
    await syncGigTicketing(ctx, args.opportunityId);
    return { revision, capacity: fields.ticketCapacity };
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
    if (opportunity.mode === "privateBooking") {
      requirePrivateBookingsEnabled();
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
    if (opportunity.venueId !== undefined) {
      const venue = await ctx.db.get(opportunity.venueId);
      if (!venue) throw new Error("Venue not found");
      if (consentRequiredFor(venue, opportunity.organizationId)) {
        const consent = await currentConsentFor(ctx, opportunity._id);
        if (consent?.status !== "granted") {
          throw new Error("The venue has not approved this event yet");
        }
      }
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
    if (opportunity.mode === "privateBooking") {
      requirePrivateBookingsEnabled();
    }
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
    if (opportunity.mode === "privateBooking") {
      requirePrivateBookingsEnabled();
    }
    assertOpportunityTransition(opportunity.status, "open");
    if (opportunity.status === "booking") {
      const slots = await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunity._id),
        )
        .take(MAX_OPPORTUNITY_SLOTS + 1);
      if (slots.every((slot) => slot.status === "booked")) {
        throw new Error("Every slot is booked");
      }
    }
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
    await cancelOpportunity(ctx, {
      opportunity,
      actorUserId: user._id,
      reason: args.reason ?? "Opportunity cancelled",
      now,
    });
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
    if (source.mode === "publicEvent" && source.venueId !== undefined) {
      await requireUsableVenue(ctx, source.organizationId, source.venueId);
    }
    let privateLocationId = source.privateLocationId;
    if (source.mode === "privateBooking") {
      requirePrivateBookingsEnabled();
      if (source.privateLocationId !== undefined) {
        const location = await ctx.db.get(source.privateLocationId);
        if (location && location.archivedAt !== undefined) {
          privateLocationId = undefined;
        }
      }
    }
    const title = `${source.title} (copy)`.slice(0, 120);
    const slug = await uniqueOpportunitySlug(ctx, title);
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId: source.organizationId,
      mode: source.mode,
      ...(source.venueId !== undefined ? { venueId: source.venueId } : {}),
      ...(privateLocationId !== undefined ? { privateLocationId } : {}),
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
