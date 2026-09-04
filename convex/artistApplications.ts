import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import {
  MutationCtx,
  QueryCtx,
  mutation,
  query,
} from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  requireOrganizationRole,
} from "./lib/authz";
import {
  bandPayloadValidator,
  currentUser,
  requireBandRole,
  toBandPayload,
} from "./lib/helpers";
import {
  opportunityPayloadValidator,
  toOpportunityPayload,
} from "./lib/opportunityPayload";
import {
  APPLICATION_ACTIVE_STATUSES,
  APPLICATION_TRANSITIONS,
  ArtistApplicationStatus,
  assertApplicationTransition,
} from "./lib/opportunityStatus";
import { artistApplicationStatusValidator } from "./schema";

export const applicationPayloadValidator = v.object({
  _id: v.id("artistApplications"),
  opportunityId: v.id("talentOpportunities"),
  slotId: v.id("opportunitySlots"),
  bandId: v.id("bands"),
  status: artistApplicationStatusValidator,
  message: v.string(),
  askMinor: v.union(v.number(), v.null()),
  availabilityNote: v.union(v.string(), v.null()),
  lineupNote: v.union(v.string(), v.null()),
  decidedAt: v.union(v.number(), v.null()),
  createdAt: v.number(),
  updatedAt: v.number(),
});

export const applicantPayloadValidator = v.object({
  application: applicationPayloadValidator,
  band: bandPayloadValidator,
  contactEmail: v.union(v.string(), v.null()),
});

export const bandApplicationPayloadValidator = v.object({
  application: applicationPayloadValidator,
  opportunity: opportunityPayloadValidator,
});

function toApplicationPayload(
  application: Doc<"artistApplications">,
): Infer<typeof applicationPayloadValidator> {
  return {
    _id: application._id,
    opportunityId: application.opportunityId,
    slotId: application.slotId,
    bandId: application.bandId,
    status: application.status,
    message: application.message,
    askMinor: application.askMinor ?? null,
    availabilityNote: application.availabilityNote ?? null,
    lineupNote: application.lineupNote ?? null,
    decidedAt: application.decidedAt ?? null,
    createdAt: application.createdAt,
    updatedAt: application.updatedAt,
  };
}

export async function canBandSeeOpportunity(
  ctx: QueryCtx | MutationCtx,
  opportunity: Doc<"talentOpportunities">,
  bandId: Id<"bands">,
): Promise<boolean> {
  if (opportunity.visibility === "public") return true;
  const invite = await ctx.db
    .query("opportunityInvites")
    .withIndex("by_opportunityId_and_bandId", (q) =>
      q.eq("opportunityId", opportunity._id).eq("bandId", bandId),
    )
    .first();
  return invite !== null;
}

function normalizeNote(value: string | undefined, label: string) {
  const note = value?.trim();
  if (note !== undefined && note.length > 500) {
    throw new Error(`${label} must be at most 500 characters`);
  }
  return note || undefined;
}

export const apply = mutation({
  args: {
    opportunityId: v.id("talentOpportunities"),
    slotId: v.id("opportunitySlots"),
    bandId: v.id("bands"),
    message: v.string(),
    askMinor: v.optional(v.number()),
    availabilityNote: v.optional(v.string()),
    lineupNote: v.optional(v.string()),
  },
  returns: v.object({ applicationId: v.id("artistApplications") }),
  handler: async (ctx, args) => {
    const { user } = await requireBandRole(ctx, args.bandId, {
      role: "admin",
    });
    const opportunity = await ctx.db.get(args.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    if (opportunity.status !== "open") {
      throw new Error("Opportunity is not accepting applications");
    }
    if (opportunity.mode !== "publicEvent") {
      throw new Error("Private bookings are not available yet");
    }
    if (!(await canBandSeeOpportunity(ctx, opportunity, args.bandId))) {
      throw new Error("This opportunity is invite-only");
    }
    const slot = await ctx.db.get(args.slotId);
    if (!slot || slot.opportunityId !== args.opportunityId) {
      throw new Error("Slot not found");
    }
    if (slot.status !== "open") throw new Error("Slot is not open");

    const existing = await ctx.db
      .query("artistApplications")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", args.opportunityId).eq("bandId", args.bandId),
      )
      .order("desc")
      .take(10);
    if (
      existing.some((row) =>
        APPLICATION_ACTIVE_STATUSES.includes(row.status),
      )
    ) {
      throw new Error(
        "This band already has an active application for this opportunity",
      );
    }

    const message = args.message.trim();
    if (message.length > 1000) {
      throw new Error("Message must be at most 1000 characters");
    }
    if (
      args.askMinor !== undefined &&
      (!Number.isInteger(args.askMinor) ||
        args.askMinor < 0 ||
        args.askMinor > 10_000_000)
    ) {
      throw new Error("Ask must be an integer between 0 and 10000000");
    }
    const availabilityNote = normalizeNote(
      args.availabilityNote,
      "Availability note",
    );
    const lineupNote = normalizeNote(args.lineupNote, "Lineup note");
    const now = Date.now();
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId: opportunity._id,
      slotId: slot._id,
      bandId: args.bandId,
      submittedBy: user._id,
      message,
      status: "submitted",
      createdAt: now,
      updatedAt: now,
      ...(args.askMinor !== undefined ? { askMinor: args.askMinor } : {}),
      ...(availabilityNote !== undefined ? { availabilityNote } : {}),
      ...(lineupNote !== undefined ? { lineupNote } : {}),
    });
    await ctx.db.patch(opportunity._id, {
      applicationCount: opportunity.applicationCount + 1,
      updatedAt: now,
    });
    return { applicationId };
  },
});

export const withdraw = mutation({
  args: { applicationId: v.id("artistApplications") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const application = await ctx.db.get(args.applicationId);
    if (!application) throw new Error("Application not found");
    await requireBandRole(ctx, application.bandId, { role: "admin" });
    assertApplicationTransition(application.status, "withdrawn");
    const now = Date.now();
    await ctx.db.patch(application._id, {
      status: "withdrawn",
      updatedAt: now,
    });
    const opportunity = await ctx.db.get(application.opportunityId);
    if (opportunity) {
      await ctx.db.patch(opportunity._id, {
        applicationCount: Math.max(0, opportunity.applicationCount - 1),
        updatedAt: now,
      });
    }
    return null;
  },
});

export const review = mutation({
  args: {
    applicationId: v.id("artistApplications"),
    action: v.union(
      v.literal("under_review"),
      v.literal("shortlisted"),
      v.literal("declined"),
    ),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const application = await ctx.db.get(args.applicationId);
    if (!application) throw new Error("Application not found");
    const opportunity = await ctx.db.get(application.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const { user } = await requireOrganizationRole(
      ctx,
      opportunity.organizationId,
      ["owner", "manager"],
    );
    assertApplicationTransition(application.status, args.action);
    const now = Date.now();
    if (args.action === "declined") {
      await ctx.db.patch(application._id, {
        status: "declined",
        decidedBy: user._id,
        decidedAt: now,
        updatedAt: now,
      });
      await ctx.db.patch(opportunity._id, {
        applicationCount: Math.max(0, opportunity.applicationCount - 1),
        updatedAt: now,
      });
    } else {
      await ctx.db.patch(application._id, {
        status: args.action,
        updatedAt: now,
      });
    }
    return null;
  },
});

export const forOpportunity = query({
  args: { opportunityId: v.id("talentOpportunities") },
  returns: v.array(applicantPayloadValidator),
  handler: async (ctx, args) => {
    const opportunity = await ctx.db.get(args.opportunityId);
    if (!opportunity) throw new Error("Opportunity not found");
    const access = await requireOrganizationRole(
      ctx,
      opportunity.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const applications = await ctx.db
      .query("artistApplications")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", args.opportunityId),
      )
      .take(200);
    applications.sort((a, b) => {
      const aActive = APPLICATION_ACTIVE_STATUSES.includes(a.status);
      const bActive = APPLICATION_ACTIVE_STATUSES.includes(b.status);
      return Number(bActive) - Number(aActive) || a.createdAt - b.createdAt;
    });
    const canReadContact =
      access.membership?.role === "owner" ||
      access.membership?.role === "manager" ||
      access.viaPlatformAdmin;
    const applicants: Infer<typeof applicantPayloadValidator>[] = [];
    for (const application of applications) {
      const band = await ctx.db.get(application.bandId);
      if (!band || band.archivedAt !== undefined) continue;
      const submitter = canReadContact
        ? await ctx.db.get(application.submittedBy)
        : null;
      applicants.push({
        application: toApplicationPayload(application),
        band: await toBandPayload(ctx, band),
        contactEmail: submitter?.email ?? null,
      });
    }
    return applicants;
  },
});

export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(bandApplicationPayloadValidator),
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (!user) return [];
    const membership = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", args.bandId).eq("userId", user._id),
      )
      .unique();
    if (!membership) return [];

    const applications: Doc<"artistApplications">[] = [];
    for (const status of Object.keys(
      APPLICATION_TRANSITIONS,
    ) as ArtistApplicationStatus[]) {
      const rows = await ctx.db
        .query("artistApplications")
        .withIndex("by_bandId_and_status", (q) =>
          q.eq("bandId", args.bandId).eq("status", status),
        )
        .order("desc")
        .take(100);
      applications.push(...rows);
    }
    applications.sort((a, b) => b.createdAt - a.createdAt);
    const result: Infer<typeof bandApplicationPayloadValidator>[] = [];
    for (const application of applications.slice(0, 100)) {
      const opportunity = await ctx.db.get(application.opportunityId);
      if (!opportunity) continue;
      result.push({
        application: toApplicationPayload(application),
        opportunity: await toOpportunityPayload(ctx, opportunity),
      });
    }
    return result;
  },
});

export const mine = query({
  args: {
    opportunityId: v.id("talentOpportunities"),
    bandId: v.id("bands"),
  },
  returns: v.union(applicationPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    await requireBandRole(ctx, args.bandId, { role: "member" });
    const application = await ctx.db
      .query("artistApplications")
      .withIndex("by_opportunityId_and_bandId", (q) =>
        q.eq("opportunityId", args.opportunityId).eq("bandId", args.bandId),
      )
      .order("desc")
      .first();
    return application ? toApplicationPayload(application) : null;
  },
});
