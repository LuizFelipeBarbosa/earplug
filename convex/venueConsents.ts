import { type Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  mutation,
  query,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { consentEmail } from "./emails";
import {
  ALL_ORGANIZATION_ROLES,
  requireOrganizationRole,
  requireOrganizationRoleQuery,
} from "./lib/authz";
import { flag } from "./lib/env";
import { cancelOpportunity } from "./lib/opportunityCancel";
import {
  assertVenueConsentTransition,
  consentRequiredFor,
  currentConsentFor,
  venueConsentStatusValidator,
} from "./lib/venueConsentStatus";
import { opportunityStatusValidator } from "./schema";

export const venueConsentPayloadValidator = v.object({
  consentId: v.id("venueConsents"),
  opportunityId: v.id("talentOpportunities"),
  venueId: v.id("venues"),
  venueOrganizationId: v.id("organizations"),
  requestingOrganizationId: v.id("organizations"),
  status: venueConsentStatusValidator,
  message: v.union(v.string(), v.null()),
  note: v.union(v.string(), v.null()),
  createdAt: v.number(),
  decidedAt: v.union(v.number(), v.null()),
});

export const venueConsentRowValidator = v.object({
  ...venueConsentPayloadValidator.fields,
  opportunityTitle: v.string(),
  opportunityStatus: opportunityStatusValidator,
  startsAt: v.number(),
  endsAt: v.union(v.number(), v.null()),
  venueName: v.string(),
  requestingOrganizationName: v.string(),
});

const BLOCKING_BOOKING_STATUSES = [
  "confirmed",
  "completed",
  "paid",
  "disputed",
] as const;

function toVenueConsentPayload(consent: Doc<"venueConsents">) {
  return {
    consentId: consent._id,
    opportunityId: consent.opportunityId,
    venueId: consent.venueId,
    venueOrganizationId: consent.venueOrganizationId,
    requestingOrganizationId: consent.requestingOrganizationId,
    status: consent.status,
    message: consent.message ?? null,
    note: consent.note ?? null,
    createdAt: consent.createdAt,
    decidedAt: consent.decidedAt ?? null,
  };
}

async function toVenueConsentRow(
  ctx: QueryCtx | MutationCtx,
  consent: Doc<"venueConsents">,
  opportunities: Map<Id<"talentOpportunities">, Doc<"talentOpportunities"> | null>,
  venues: Map<Id<"venues">, Doc<"venues"> | null>,
  requestingOrganizations: Map<Id<"organizations">, Doc<"organizations"> | null>,
): Promise<Infer<typeof venueConsentRowValidator> | null> {
  // Cache missing records too so repeated references do not repeat reads.
  if (!opportunities.has(consent.opportunityId)) {
    opportunities.set(consent.opportunityId, await ctx.db.get(consent.opportunityId));
  }
  if (!venues.has(consent.venueId)) {
    venues.set(consent.venueId, await ctx.db.get(consent.venueId));
  }
  if (!requestingOrganizations.has(consent.requestingOrganizationId)) {
    requestingOrganizations.set(
      consent.requestingOrganizationId,
      await ctx.db.get(consent.requestingOrganizationId),
    );
  }
  const opportunity = opportunities.get(consent.opportunityId);
  const venue = venues.get(consent.venueId);
  const requestingOrganization = requestingOrganizations.get(
    consent.requestingOrganizationId,
  );
  if (!opportunity || !venue || !requestingOrganization) {
    return null;
  }
  return {
    ...toVenueConsentPayload(consent),
    opportunityTitle: opportunity.title,
    opportunityStatus: opportunity.status,
    startsAt: opportunity.startsAt,
    endsAt: opportunity.endsAt ?? null,
    venueName: venue.name,
    requestingOrganizationName: requestingOrganization.name,
  };
}

async function businessEmailFor(
  ctx: QueryCtx | MutationCtx,
  organizationId: Id<"organizations">,
): Promise<string | undefined> {
  const details = await ctx.db
    .query("organizationPrivateDetails")
    .withIndex("by_organizationId", (q) =>
      q.eq("organizationId", organizationId),
    )
    .unique();
  return details?.businessEmail;
}

async function scheduleConsentEmail(
  ctx: MutationCtx,
  kind: "venueConsentRequested" | "venueConsentDecided",
  to: string | undefined,
  body: { subject: string; text: string },
): Promise<void> {
  const trimmed = to?.trim();
  if (!trimmed) return;
  await ctx.scheduler.runAfter(0, internal.emails.send, {
    kind,
    to: trimmed,
    ...body,
  });
}

export const request = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    message: v.optional(v.string()),
  },
  returns: v.object({ consentId: v.id("venueConsents") }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const opportunity = await ctx.db.get(args.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const { organization } = await requireOrganizationRole(
      ctx,
      opportunity.organizationId,
      ["owner", "manager"],
    );
    if (!flag("PROMOTERS_ENABLED", false)) {
      throw new Error("Venue approval is not available yet");
    }
    if (opportunity.status !== "draft") {
      throw new Error("Request venue approval while the event is still a draft");
    }
    if (opportunity.venueId === undefined) {
      throw new Error("This opportunity has no venue");
    }
    const venue = await ctx.db.get(opportunity.venueId);
    if (!venue) throw new Error("Venue not found");
    if (!consentRequiredFor(venue, opportunity.organizationId)) {
      throw new Error("This is one of your own venues");
    }
    const venueOrganizationId = venue.managedByOrganizationId;
    if (venueOrganizationId === undefined) {
      throw new Error("This venue has not joined EarPlug yet");
    }
    const venueOrganization = await ctx.db.get(venueOrganizationId);
    if (venueOrganization?.status === "suspended") {
      throw new Error("This venue is not accepting requests");
    }
    if (await currentConsentFor(ctx, args.opportunityId)) {
      throw new Error("A venue request is already open");
    }
    const trimmedMessage = args.message?.trim();
    if (trimmedMessage !== undefined && trimmedMessage.length > 1000) {
      throw new Error("Message must be 1000 characters or fewer");
    }
    const consentId = await ctx.db.insert("venueConsents", {
      opportunityId: args.opportunityId,
      venueId: venue._id,
      venueOrganizationId,
      requestingOrganizationId: opportunity.organizationId,
      status: "pending",
      ...(trimmedMessage ? { message: trimmedMessage } : {}),
      createdAt: now,
      updatedAt: now,
    });

    const to = await businessEmailFor(ctx, venueOrganizationId);
    const email = consentEmail("venueConsentRequested", {
      venueName: venue.name,
      opportunityTitle: opportunity.title,
      startsAt: opportunity.startsAt,
      requestingOrganizationName: organization.name,
      status: "pending",
    });
    await scheduleConsentEmail(ctx, "venueConsentRequested", to, email);
    return { consentId };
  },
});

export const withdraw = mutation({
  args: { consentId: v.id("venueConsents") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const consent = await ctx.db.get(args.consentId);
    if (!consent) throw new Error("Venue request not found");
    await requireOrganizationRole(ctx, consent.requestingOrganizationId, [
      "owner",
      "manager",
    ]);
    assertVenueConsentTransition(consent.status, "withdrawn");
    const opportunity = await ctx.db.get(consent.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    if (opportunity.status !== "draft") {
      throw new Error("Withdraw is only possible while the event is a draft");
    }
    await ctx.db.patch(consent._id, { status: "withdrawn", updatedAt: now });
    return null;
  },
});

export const decide = mutation({
  args: {
    consentId: v.id("venueConsents"),
    decision: v.union(v.literal("granted"), v.literal("declined")),
    note: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const consent = await ctx.db.get(args.consentId);
    if (!consent) throw new Error("Venue request not found");
    const { user } = await requireOrganizationRole(
      ctx,
      consent.venueOrganizationId,
      ["owner", "manager"],
    );
    const opportunity = await ctx.db.get(consent.opportunityId);
    if (
      !opportunity ||
      opportunity.status === "cancelled" ||
      opportunity.status === "completed"
    ) {
      throw new Error("This event is no longer open for approval");
    }
    const venue = await ctx.db.get(consent.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId !== consent.venueOrganizationId) {
      throw new Error("This venue is no longer managed by your organization");
    }
    assertVenueConsentTransition(consent.status, args.decision);
    const trimmedNote = args.note?.trim();
    if (trimmedNote !== undefined && trimmedNote.length > 1000) {
      throw new Error("Note must be 1000 characters or fewer");
    }
    await ctx.db.patch(consent._id, {
      status: args.decision,
      ...(trimmedNote ? { note: trimmedNote } : {}),
      decidedByUserId: user._id,
      decidedAt: now,
      updatedAt: now,
    });

    const requestingOrganization = await ctx.db.get(
      consent.requestingOrganizationId,
    );
    if (!requestingOrganization) {
      throw new Error("Requesting organization not found");
    }
    const to = await businessEmailFor(ctx, consent.requestingOrganizationId);
    const email = consentEmail("venueConsentDecided", {
      venueName: venue.name,
      opportunityTitle: opportunity.title,
      startsAt: opportunity.startsAt,
      requestingOrganizationName: requestingOrganization.name,
      status: args.decision,
      note: trimmedNote,
    });
    await scheduleConsentEmail(ctx, "venueConsentDecided", to, email);
    return null;
  },
});

export const revoke = mutation({
  args: {
    consentId: v.id("venueConsents"),
    note: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const consent = await ctx.db.get(args.consentId);
    if (!consent) throw new Error("Venue request not found");
    const { user } = await requireOrganizationRole(
      ctx,
      consent.venueOrganizationId,
      ["owner", "manager"],
    );
    assertVenueConsentTransition(consent.status, "revoked");
    const opportunity = await ctx.db.get(consent.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const venue = await ctx.db.get(consent.venueId);
    if (!venue) throw new Error("Venue not found");
    if (venue.managedByOrganizationId !== consent.venueOrganizationId) {
      throw new Error("This venue is no longer managed by your organization");
    }
    const bookings = await ctx.db
      .query("bookings")
      .withIndex("by_opportunityId", (q) =>
        q.eq("opportunityId", opportunity._id),
      )
      .take(500);
    if (
      bookings.some((booking) =>
        BLOCKING_BOOKING_STATUSES.some((status) => status === booking.status),
      )
    ) {
      throw new Error(
        "This event already has a confirmed booking. Contact EarPlug support.",
      );
    }
    const trimmedNote = args.note?.trim();
    if (trimmedNote !== undefined && trimmedNote.length > 1000) {
      throw new Error("Note must be 1000 characters or fewer");
    }
    await ctx.db.patch(consent._id, {
      status: "revoked",
      ...(trimmedNote ? { note: trimmedNote } : {}),
      decidedByUserId: user._id,
      decidedAt: now,
      updatedAt: now,
    });
    if (
      opportunity.status !== "draft" &&
      opportunity.status !== "cancelled" &&
      opportunity.status !== "completed"
    ) {
      await cancelOpportunity(ctx, {
        opportunity,
        actorUserId: user._id,
        reason: "Venue approval revoked",
        now,
      });
    }

    const requestingOrganization = await ctx.db.get(
      consent.requestingOrganizationId,
    );
    if (!requestingOrganization) {
      throw new Error("Requesting organization not found");
    }
    const to = await businessEmailFor(ctx, consent.requestingOrganizationId);
    const email = consentEmail("venueConsentDecided", {
      venueName: venue.name,
      opportunityTitle: opportunity.title,
      startsAt: opportunity.startsAt,
      requestingOrganizationName: requestingOrganization.name,
      status: "revoked",
      note: trimmedNote,
    });
    await scheduleConsentEmail(ctx, "venueConsentDecided", to, email);
    return null;
  },
});

export const forOpportunity = query({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.union(venueConsentPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const opportunity = await ctx.db.get(args.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    await requireOrganizationRoleQuery(
      ctx,
      opportunity.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const consents = await ctx.db
      .query("venueConsents")
      .withIndex("by_opportunityId", (q) =>
        q.eq("opportunityId", args.opportunityId),
      )
      .order("desc")
      .take(20);
    const active = consents.find(
      (consent) => consent.status === "pending" || consent.status === "granted",
    );
    if (active) return toVenueConsentPayload(active);
    const decided = consents.find(
      (consent) => consent.status === "declined" || consent.status === "revoked",
    );
    return decided ? toVenueConsentPayload(decided) : null;
  },
});

export const forVenueOrganization = query({
  args: {
    organizationId: v.id("organizations"),
    status: v.optional(venueConsentStatusValidator),
  },
  returns: v.array(venueConsentRowValidator),
  handler: async (ctx, args) => {
    await requireOrganizationRoleQuery(ctx, args.organizationId, [
      "owner",
      "manager",
    ]);
    const statuses =
      args.status !== undefined ? [args.status] : (["pending", "granted"] as const);
    const consents: Doc<"venueConsents">[] = [];
    for (const status of statuses) {
      const rows = await ctx.db
        .query("venueConsents")
        .withIndex("by_venueOrganizationId_and_status_and_createdAt", (q) =>
          q.eq("venueOrganizationId", args.organizationId).eq("status", status),
        )
        .order("desc")
        .take(100);
      consents.push(...rows);
    }
    const opportunities = new Map<
      Id<"talentOpportunities">,
      Doc<"talentOpportunities"> | null
    >();
    const venues = new Map<Id<"venues">, Doc<"venues"> | null>();
    const requestingOrganizations = new Map<
      Id<"organizations">,
      Doc<"organizations"> | null
    >();
    const rows: Infer<typeof venueConsentRowValidator>[] = [];
    for (const consent of consents) {
      const row = await toVenueConsentRow(
        ctx,
        consent,
        opportunities,
        venues,
        requestingOrganizations,
      );
      if (row !== null) rows.push(row);
    }
    return rows;
  },
});
