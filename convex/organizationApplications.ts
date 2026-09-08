import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, QueryCtx, mutation, query } from "./_generated/server";
import { applicationEmail } from "./emails";
import {
  isPlatformAdmin,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import { flag } from "./lib/env";
import {
  OAK_CENTER,
  SF_CENTER,
  approximateLocation,
  formatMiles,
  milesBetween,
} from "./lib/geo";
import {
  currentUser,
  isReservedPublicSlug,
  isValidHttpsUrl,
  requireUser,
  slugify,
} from "./lib/helpers";
import { uniqueVenueSlug } from "./lib/venueSlug";
import {
  organizationApplicationStatusValidator,
  organizationTypeValidator,
  venueTypeValidator,
} from "./schema";
import { normalizeVenueText } from "./venues";

const MAX_DOCUMENT_BYTES = 15 * 1024 * 1024;
const DOCUMENT_CONTENT_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/heic",
  "image/heif",
  "application/pdf",
]);

function assertDocumentUploadAcceptable(meta: {
  size: number;
  contentType?: string;
}): void {
  if (meta.size > MAX_DOCUMENT_BYTES) {
    throw new Error("That file is too big — 15 MB max.");
  }
  if (
    meta.contentType !== undefined &&
    !DOCUMENT_CONTENT_TYPES.has(meta.contentType)
  ) {
    throw new Error("Documents must be a PDF or photo");
  }
}

const venueInputValidator = v.object({
  name: v.string(),
  addr: v.string(),
  lat: v.number(),
  lng: v.number(),
  area: v.string(),
  neighborhood: v.optional(v.string()),
  city: v.optional(v.string()),
  capacity: v.optional(v.number()),
  venueType: v.optional(venueTypeValidator),
});

async function findVenueAtAddress(
  ctx: QueryCtx,
  venue: Infer<typeof venueInputValidator>,
): Promise<Doc<"venues"> | null> {
  const normalizedAddr = normalizeVenueText(venue.addr);
  const [privateMatches, publicMatches] = await Promise.all([
    ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_normalizedAddr", (q) =>
        q.eq("normalizedAddr", normalizedAddr),
      )
      .take(51),
    ctx.db
      .query("venues")
      .withIndex("by_normalizedAddr", (q) =>
        q.eq("normalizedAddr", normalizedAddr),
      )
      .take(51),
  ]);
  if (privateMatches.length > 50 || publicMatches.length > 50) {
    throw new Error(
      "Too many venues share this address; provide a more specific address",
    );
  }

  // A street line can recur in different cities. Allow small pin/geocoder
  // differences (about 160 metres), but never match by address alone.
  const nearby = new Map<Id<"venues">, Doc<"venues">>();
  for (const details of privateMatches) {
    if (milesBetween(venue, details) > 0.1) continue;
    const existing = await ctx.db.get(details.venueId);
    if (existing !== null) nearby.set(existing._id, existing);
  }
  for (const existing of publicMatches) {
    const details = await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", existing._id))
      .unique();
    // Private details are authoritative; the public row may contain an
    // approximate location or an address left over from before an edit.
    if (details !== null) continue;
    if (milesBetween(venue, existing) <= 0.1)
      nearby.set(existing._id, existing);
  }
  if (nearby.size > 1) {
    throw new Error(
      "Multiple venues match this address and location; resolve the duplicate venues before approval",
    );
  }
  return nearby.values().next().value ?? null;
}

export const organizationApplicationPayloadValidator = v.object({
  _id: v.id("organizationApplications"),
  kind: v.union(v.literal("organization"), v.literal("host")),
  hostDisplayName: v.union(v.string(), v.null()),
  hostPhone: v.union(v.string(), v.null()),
  hostArea: v.union(v.string(), v.null()),
  hostAgreementAcceptedAt: v.union(v.number(), v.null()),
  status: organizationApplicationStatusValidator,
  orgName: v.string(),
  orgType: organizationTypeValidator,
  website: v.union(v.string(), v.null()),
  contactName: v.string(),
  businessEmail: v.string(),
  phone: v.union(v.string(), v.null()),
  venue: v.union(
    v.object({
      name: v.string(),
      addr: v.string(),
      lat: v.number(),
      lng: v.number(),
      area: v.string(),
      neighborhood: v.union(v.string(), v.null()),
      city: v.union(v.string(), v.null()),
      capacity: v.union(v.number(), v.null()),
      venueType: v.union(venueTypeValidator, v.null()),
    }),
    v.null(),
  ),
  documents: v.array(
    v.object({
      storageId: v.id("_storage"),
      url: v.union(v.string(), v.null()),
      contentType: v.union(v.string(), v.null()),
      sizeBytes: v.union(v.number(), v.null()),
    }),
  ),
  reviewNote: v.union(v.string(), v.null()),
  decidedAt: v.union(v.number(), v.null()),
  resultingOrganizationId: v.union(v.id("organizations"), v.null()),
  resultingVenueId: v.union(v.id("venues"), v.null()),
  revision: v.number(),
  createdAt: v.number(),
  updatedAt: v.number(),
});

export async function toApplicationPayload(
  ctx: QueryCtx,
  application: Doc<"organizationApplications">,
): Promise<Infer<typeof organizationApplicationPayloadValidator>> {
  const documents = [];
  for (const storageId of application.verificationDocStorageIds) {
    const [upload, url] = await Promise.all([
      ctx.db.system.get("_storage", storageId),
      ctx.storage.getUrl(storageId),
    ]);
    documents.push({
      storageId,
      url,
      contentType: upload?.contentType ?? null,
      sizeBytes: upload?.size ?? null,
    });
  }
  return {
    _id: application._id,
    kind: application.kind ?? "organization",
    hostDisplayName: application.hostDisplayName ?? null,
    hostPhone: application.hostPhone ?? null,
    hostArea: application.hostArea ?? null,
    hostAgreementAcceptedAt: application.hostAgreementAcceptedAt ?? null,
    status: application.status,
    orgName: application.orgName,
    orgType: application.orgType,
    website: application.website ?? null,
    contactName: application.contactName,
    businessEmail: application.businessEmail,
    phone: application.phone ?? null,
    venue:
      application.venue === undefined
        ? null
        : {
            ...application.venue,
            neighborhood: application.venue.neighborhood ?? null,
            city: application.venue.city ?? null,
            capacity: application.venue.capacity ?? null,
            venueType: application.venue.venueType ?? null,
          },
    documents,
    reviewNote: application.reviewNote ?? null,
    decidedAt: application.decidedAt ?? null,
    resultingOrganizationId: application.resultingOrganizationId ?? null,
    resultingVenueId: application.resultingVenueId ?? null,
    revision: application.revision,
    createdAt: application.createdAt,
    updatedAt: application.updatedAt,
  };
}

function optionalText(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function normalizeAndValidateDraft(args: {
  kind?: "organization" | "host";
  hostDisplayName?: string;
  hostPhone?: string;
  hostArea?: string;
  orgName: string;
  orgType: Infer<typeof organizationTypeValidator>;
  website?: string;
  contactName: string;
  businessEmail: string;
  phone?: string;
  venue?: Infer<typeof venueInputValidator>;
}) {
  const orgName = args.orgName.trim();
  if (orgName.length > 120) throw new Error("Organization name is too long");

  const contactName = args.contactName.trim();
  if (contactName.length > 100) throw new Error("Contact name is too long");

  const businessEmail = args.businessEmail.trim();
  if (businessEmail && !businessEmail.includes("@")) {
    throw new Error("Enter a valid business email");
  }
  if (businessEmail.length > 200) throw new Error("Business email is too long");

  const website = optionalText(args.website);
  if (website !== undefined && website.length > 200) {
    throw new Error("Website is too long");
  }
  if (website !== undefined && !isValidHttpsUrl(website)) {
    throw new Error("Website must be a valid HTTPS URL");
  }

  const phone = optionalText(args.phone);
  if (phone !== undefined && phone.length > 40) {
    throw new Error("Phone number is too long");
  }

  let venue: Infer<typeof venueInputValidator> | undefined;
  if (args.venue !== undefined) {
    const name = args.venue.name.trim();
    const addr = args.venue.addr.trim();
    const area = args.venue.area.trim();
    if (name.length > 120) throw new Error("Venue name is too long");
    if (addr.length > 240) throw new Error("Venue address is too long");
    if (!area) throw new Error("Venue area is required");
    if (area.length > 120) throw new Error("Venue area is too long");
    if (
      !Number.isFinite(args.venue.lat) ||
      args.venue.lat < -90 ||
      args.venue.lat > 90 ||
      !Number.isFinite(args.venue.lng) ||
      args.venue.lng < -180 ||
      args.venue.lng > 180
    ) {
      throw new Error("Choose a valid map location");
    }
    if (
      args.venue.capacity !== undefined &&
      (!Number.isInteger(args.venue.capacity) ||
        args.venue.capacity < 0 ||
        args.venue.capacity > 100_000)
    ) {
      throw new Error("Venue capacity must be between 0 and 100000");
    }
    venue = {
      name,
      addr,
      lat: args.venue.lat,
      lng: args.venue.lng,
      area,
      neighborhood: optionalText(args.venue.neighborhood),
      city: optionalText(args.venue.city),
      capacity: args.venue.capacity,
      venueType: args.venue.venueType,
    };
  }

  const isPromoterOrStudentOrg =
    args.orgType === "promoter" || args.orgType === "studentOrg";
  if (
    args.kind !== "host" &&
    args.orgType !== "venueOperator" &&
    (!isPromoterOrStudentOrg || !flag("PROMOTERS_ENABLED", false))
  ) {
    throw new Error(
      "Only bars and clubs that control their location can apply right now",
    );
  }
  if (isPromoterOrStudentOrg) venue = undefined;

  const hostDisplayName = optionalText(args.hostDisplayName);
  if (hostDisplayName !== undefined && hostDisplayName.length > 60) {
    throw new Error("Host name is too long");
  }
  const hostPhone = optionalText(args.hostPhone);
  if (hostPhone !== undefined && hostPhone.length > 40) {
    throw new Error("Host phone number is too long");
  }
  const hostArea = optionalText(args.hostArea);
  if (hostArea !== undefined && hostArea.length > 120) {
    throw new Error("Host area is too long");
  }

  return {
    kind: args.kind ?? "organization",
    hostDisplayName,
    hostPhone,
    hostArea,
    orgName,
    orgType: args.orgType,
    website,
    contactName,
    businessEmail,
    phone,
    venue,
  };
}

async function ownedApplication(
  ctx: MutationCtx,
  applicationId: Id<"organizationApplications">,
  userId: Id<"users">,
) {
  const application = await ctx.db.get(applicationId);
  if (!application) throw new Error("Application not found");
  if (application.applicantUserId !== userId) {
    throw new Error("Not your application");
  }
  return application;
}

function assertEditable(application: Doc<"organizationApplications">): void {
  if (application.status !== "draft" && application.status !== "needs_info") {
    throw new Error("Application can no longer be edited");
  }
}

async function uniqueOrganizationSlug(
  ctx: MutationCtx,
  name: string,
): Promise<string> {
  const base = slugify(name);
  for (let n = 1; ; n++) {
    const candidate = n === 1 ? base : `${base}-${n}`;
    if (isReservedPublicSlug(candidate)) continue;
    const existing = await ctx.db
      .query("organizations")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (existing === null) return candidate;
  }
}

async function uniqueHostOrganizationSlug(ctx: MutationCtx): Promise<string> {
  for (;;) {
    const bytes = new Uint8Array(6);
    crypto.getRandomValues(bytes);
    const suffix = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
    const candidate = `host-${suffix}`;
    const existing = await ctx.db
      .query("organizations")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (existing === null) return candidate;
  }
}

async function scheduleApplicationEmail(
  ctx: MutationCtx,
  kind:
    | "applicationReceived"
    | "applicationApproved"
    | "applicationNeedsInfo"
    | "applicationRejected",
  application: Doc<"organizationApplications">,
  note: string | undefined,
) {
  let to = application.businessEmail.trim();
  if (!to) {
    const applicant = await ctx.db.get(application.applicantUserId);
    to = applicant?.email.trim() ?? "";
  }
  if (!to) return;

  const email = applicationEmail(kind, {
    orgName: application.orgName,
    note,
  });
  await ctx.scheduler.runAfter(0, internal.emails.send, {
    kind,
    to,
    ...email,
  });
}

export const mine = query({
  args: {},
  returns: v.union(organizationApplicationPayloadValidator, v.null()),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return null;
    const applications = await ctx.db
      .query("organizationApplications")
      .withIndex("by_applicantUserId_and_createdAt", (q) =>
        q.eq("applicantUserId", user._id),
      )
      .order("desc")
      .take(5);
    const application =
      applications.find((candidate) => candidate.status !== "withdrawn") ??
      null;
    return application === null
      ? null
      : await toApplicationPayload(ctx, application);
  },
});

export const saveDraft = mutation({
  args: {
    applicationId: v.optional(v.id("organizationApplications")),
    expectedRevision: v.optional(v.number()),
    kind: v.optional(v.union(v.literal("organization"), v.literal("host"))),
    hostDisplayName: v.optional(v.string()),
    hostPhone: v.optional(v.string()),
    hostArea: v.optional(v.string()),
    hostAgreementAccepted: v.optional(v.boolean()),
    orgName: v.string(),
    orgType: organizationTypeValidator,
    website: v.optional(v.string()),
    contactName: v.string(),
    businessEmail: v.string(),
    phone: v.optional(v.string()),
    venue: v.optional(venueInputValidator),
  },
  returns: v.object({
    applicationId: v.id("organizationApplications"),
    revision: v.number(),
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const fields = normalizeAndValidateDraft(args);
    const now = Date.now();
    if (args.applicationId !== undefined) {
      const application = await ownedApplication(
        ctx,
        args.applicationId,
        user._id,
      );
      assertEditable(application);
      if (args.expectedRevision !== application.revision) {
        throw new Error("Application changed elsewhere");
      }
      if (
        application.status !== "draft" &&
        fields.kind !== (application.kind ?? "organization")
      ) {
        throw new Error("Application kind cannot change after submission");
      }
      const hostAgreementAcceptedAt =
        args.hostAgreementAccepted === true
          ? now
          : args.hostAgreementAccepted === false
            ? undefined
            : application.hostAgreementAcceptedAt;
      const revision = application.revision + 1;
      await ctx.db.patch(application._id, {
        ...fields,
        hostAgreementAcceptedAt,
        revision,
        updatedAt: now,
      });
      return { applicationId: application._id, revision };
    }

    const applicationId = await ctx.db.insert("organizationApplications", {
      applicantUserId: user._id,
      ...fields,
      hostAgreementAcceptedAt:
        args.hostAgreementAccepted === true ? now : undefined,
      verificationDocStorageIds: [],
      status: "draft",
      revision: 1,
      createdAt: now,
      updatedAt: now,
    });
    return { applicationId, revision: 1 };
  },
});

export const submit = mutation({
  args: {
    applicationId: v.id("organizationApplications"),
    expectedRevision: v.number(),
  },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const application = await ownedApplication(
      ctx,
      args.applicationId,
      user._id,
    );
    assertEditable(application);
    if (args.expectedRevision !== application.revision) {
      throw new Error("Application changed elsewhere");
    }
    if (application.kind === "host") {
      if (!flag("PRIVATE_BOOKINGS_ENABLED", false)) {
        throw new Error("Hosting is not available yet");
      }
      const hostDisplayName = application.hostDisplayName?.trim() ?? "";
      if (hostDisplayName.length < 2) throw new Error("Host name is required");
      if (hostDisplayName.length > 60) throw new Error("Host name is too long");
      if (!application.hostPhone?.trim()) {
        throw new Error("Phone number is required");
      }
      if (!application.hostArea?.trim()) {
        throw new Error("Area is required");
      }
      if (application.hostAgreementAcceptedAt === undefined) {
        throw new Error("Accept the hosting agreement before submitting");
      }
      if (application.verificationDocStorageIds.length === 0) {
        throw new Error(
          "Attach at least one verification document before submitting",
        );
      }
    } else {
      if (
        (application.orgType === "promoter" ||
          application.orgType === "studentOrg") &&
        !flag("PROMOTERS_ENABLED", false)
      ) {
        throw new Error(
          "Only bars and clubs that control their location can apply right now",
        );
      }
      if (!application.orgName.trim()) {
        throw new Error("Organization name is required");
      }
      if (!application.contactName.trim()) {
        throw new Error("Contact name is required");
      }
      if (
        !application.businessEmail.trim() ||
        !application.businessEmail.trim().includes("@")
      ) {
        throw new Error("Enter a valid business email");
      }
      if (
        application.orgType === "venueOperator" &&
        (application.venue === undefined ||
          !application.venue.name.trim() ||
          !application.venue.addr.trim() ||
          !Number.isFinite(application.venue.lat) ||
          !Number.isFinite(application.venue.lng))
      ) {
        throw new Error("Add your venue's details before submitting");
      }
      if (application.verificationDocStorageIds.length === 0) {
        throw new Error(
          "Attach at least one verification document before submitting",
        );
      }
    }

    const revision = application.revision + 1;
    await ctx.db.patch(application._id, {
      status: "submitted",
      revision,
      updatedAt: Date.now(),
    });
    await scheduleApplicationEmail(
      ctx,
      "applicationReceived",
      application,
      application.reviewNote,
    );
    return { revision };
  },
});

export const withdraw = mutation({
  args: { applicationId: v.id("organizationApplications") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const application = await ownedApplication(
      ctx,
      args.applicationId,
      user._id,
    );
    if (
      application.status !== "draft" &&
      application.status !== "submitted" &&
      application.status !== "under_review" &&
      application.status !== "needs_info"
    ) {
      throw new Error("Application can no longer be edited");
    }
    await ctx.db.patch(application._id, {
      status: "withdrawn",
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const generateDocumentUploadUrl = mutation({
  args: {},
  returns: v.string(),
  handler: async (ctx) => {
    await requireUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const attachDocument = mutation({
  args: {
    applicationId: v.id("organizationApplications"),
    storageId: v.id("_storage"),
  },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const application = await ownedApplication(
      ctx,
      args.applicationId,
      user._id,
    );
    assertEditable(application);
    const upload = await ctx.db.system.get("_storage", args.storageId);
    if (upload === null) throw new Error("Upload not found");
    assertDocumentUploadAcceptable({
      size: upload.size,
      contentType: upload.contentType,
    });
    // Retried attachment requests are a no-op, even when the list is full.
    if (application.verificationDocStorageIds.includes(args.storageId)) {
      return { revision: application.revision };
    }
    if (application.verificationDocStorageIds.length >= 5) {
      throw new Error("You can attach up to 5 documents");
    }
    const revision = application.revision + 1;
    await ctx.db.patch(application._id, {
      verificationDocStorageIds: [
        ...application.verificationDocStorageIds,
        args.storageId,
      ],
      revision,
      updatedAt: Date.now(),
    });
    return { revision };
  },
});

export const removeDocument = mutation({
  args: {
    applicationId: v.id("organizationApplications"),
    storageId: v.id("_storage"),
  },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const application = await ownedApplication(
      ctx,
      args.applicationId,
      user._id,
    );
    assertEditable(application);
    const revision = application.revision + 1;
    await ctx.db.patch(application._id, {
      verificationDocStorageIds: application.verificationDocStorageIds.filter(
        (storageId) => storageId !== args.storageId,
      ),
      revision,
      updatedAt: Date.now(),
    });
    // The blob sweeper reclaims storage that is no longer referenced.
    return { revision };
  },
});

export const get = query({
  args: { applicationId: v.id("organizationApplications") },
  returns: v.union(organizationApplicationPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const [application, user] = await Promise.all([
      ctx.db.get(args.applicationId),
      currentUser(ctx),
    ]);
    if (application === null || user === null) return null;
    if (
      application.applicantUserId !== user._id &&
      !(await isPlatformAdmin(ctx, user._id))
    ) {
      return null;
    }
    return await toApplicationPayload(ctx, application);
  },
});

const reviewListItemValidator = v.object({
  application: organizationApplicationPayloadValidator,
  applicant: v.object({
    userId: v.id("users"),
    name: v.string(),
    email: v.string(),
  }),
});

export const listForReview = query({
  args: {
    kind: v.optional(v.union(v.literal("organization"), v.literal("host"))),
    status: v.optional(organizationApplicationStatusValidator),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(reviewListItemValidator),
  handler: async (ctx, args) => {
    await requirePlatformAdminQuery(ctx);
    const result =
      args.kind !== undefined
        ? await ctx.db
            .query("organizationApplications")
            .withIndex("by_kind_and_status_and_createdAt", (q) =>
              q.eq("kind", args.kind).eq("status", args.status ?? "submitted"),
            )
            .order("asc")
            .paginate(args.paginationOpts)
        : await ctx.db
            .query("organizationApplications")
            .withIndex("by_status_and_createdAt", (q) =>
              q.eq("status", args.status ?? "submitted"),
            )
            .order("asc")
            .paginate(args.paginationOpts);
    const page = [];
    for (const application of result.page) {
      const applicant = await ctx.db.get(application.applicantUserId);
      if (applicant !== null) {
        page.push({
          application: await toApplicationPayload(ctx, application),
          applicant: {
            userId: applicant._id,
            name: applicant.name,
            email: applicant.email,
          },
        });
      }
    }
    return { ...result, page };
  },
});

export const decide = mutation({
  args: {
    applicationId: v.id("organizationApplications"),
    decision: v.union(
      v.literal("under_review"),
      v.literal("needs_info"),
      v.literal("approved"),
      v.literal("rejected"),
    ),
    note: v.optional(v.string()),
  },
  returns: v.object({
    status: organizationApplicationStatusValidator,
    organizationId: v.union(v.id("organizations"), v.null()),
    venueId: v.union(v.id("venues"), v.null()),
  }),
  handler: async (ctx, args) => {
    const reviewer = await requirePlatformAdmin(ctx);
    const application = await ctx.db.get(args.applicationId);
    if (application === null) throw new Error("Application not found");
    const allowed =
      application.status === "submitted"
        ? ["under_review", "needs_info", "approved", "rejected"]
        : application.status === "under_review"
          ? ["needs_info", "approved", "rejected"]
          : [];
    if (!allowed.includes(args.decision)) {
      throw new Error("Invalid decision for this application");
    }

    const reviewNote = optionalText(args.note);
    const updatedAt = Date.now();
    if (args.decision === "under_review" || args.decision === "needs_info") {
      await ctx.db.patch(application._id, {
        status: args.decision,
        reviewerUserId: reviewer._id,
        reviewNote,
        updatedAt,
      });
      if (args.decision === "needs_info") {
        await scheduleApplicationEmail(
          ctx,
          "applicationNeedsInfo",
          application,
          reviewNote,
        );
      }
      return {
        status: args.decision as "under_review" | "needs_info",
        organizationId: null,
        venueId: null,
      };
    }

    if (args.decision === "rejected") {
      await ctx.db.patch(application._id, {
        status: "rejected",
        reviewerUserId: reviewer._id,
        reviewNote,
        decidedAt: updatedAt,
        updatedAt,
      });
      await scheduleApplicationEmail(
        ctx,
        "applicationRejected",
        application,
        reviewNote,
      );
      return {
        status: "rejected" as const,
        organizationId: null,
        venueId: null,
      };
    }

    if (application.kind === "host") {
      const applicant = await ctx.db.get(application.applicantUserId);
      const businessEmail =
        applicant?.email.trim() || application.businessEmail.trim();
      if (!businessEmail) throw new Error("Host application has no email");
      const slug = await uniqueHostOrganizationSlug(ctx);
      const organizationId = await ctx.db.insert("organizations", {
        name: application.hostDisplayName ?? "",
        slug,
        orgType: "privateHost",
        status: "verified",
        ownerUserId: application.applicantUserId,
        applicationId: application._id,
        verifiedAt: updatedAt,
        createdAt: updatedAt,
        updatedAt,
      });
      await ctx.db.insert("organizationPrivateDetails", {
        organizationId,
        businessEmail,
        contactName: application.hostDisplayName ?? "",
        phone: application.hostPhone,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: application.verificationDocStorageIds,
        updatedAt,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: application.applicantUserId,
        role: "owner",
        addedBy: reviewer._id,
        createdAt: updatedAt,
      });

      await ctx.db.patch(application._id, {
        status: "approved",
        reviewerUserId: reviewer._id,
        reviewNote,
        decidedAt: updatedAt,
        updatedAt,
        resultingOrganizationId: organizationId,
        resultingVenueId: undefined,
      });
      await scheduleApplicationEmail(
        ctx,
        "applicationApproved",
        application,
        reviewNote,
      );
      return { status: "approved" as const, organizationId, venueId: null };
    }

    const slug = await uniqueOrganizationSlug(ctx, application.orgName);
    const organizationId = await ctx.db.insert("organizations", {
      name: application.orgName,
      slug,
      orgType: application.orgType,
      status: "verified",
      ownerUserId: application.applicantUserId,
      applicationId: application._id,
      website: application.website,
      verifiedAt: updatedAt,
      createdAt: updatedAt,
      updatedAt,
    });
    await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: application.businessEmail,
      contactName: application.contactName,
      phone: application.phone,
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: application.verificationDocStorageIds,
      updatedAt,
    });
    // This is the only place that writes organizations.ownerUserId and its
    // matching owner membership together. Every other owner check must use the
    // membership row because ownerUserId will not track future transfers.
    await ctx.db.insert("organizationMembers", {
      organizationId,
      userId: application.applicantUserId,
      role: "owner",
      addedBy: reviewer._id,
      createdAt: updatedAt,
    });

    let venueId: Id<"venues"> | null = null;
    if (application.venue !== undefined) {
      const normalizedAddr = normalizeVenueText(application.venue.addr);
      const existingVenue = await findVenueAtAddress(ctx, application.venue);

      const approx = approximateLocation(
        { lat: application.venue.lat, lng: application.venue.lng },
        application.venue.area,
      );
      if (existingVenue !== null) {
        if (existingVenue.managedByOrganizationId !== undefined) {
          throw new Error("That venue already belongs to another organization");
        }
        await ctx.db.patch(existingVenue._id, {
          managedByOrganizationId: organizationId,
          status: "verified",
          addressDisclosure: "public",
          venueType: application.venue.venueType,
          neighborhood:
            existingVenue.neighborhood ?? approx.neighborhood ?? undefined,
          city: existingVenue.city ?? approx.city ?? undefined,
          approxLabel: existingVenue.approxLabel ?? approx.label,
          approxLat: existingVenue.approxLat ?? approx.lat,
          approxLng: existingVenue.approxLng ?? approx.lng,
        });
        // Adoption explicitly preserves the address that the legacy venue had
        // already exposed publicly.
        const privateDetails = await ctx.db
          .query("venuePrivateDetails")
          .withIndex("by_venueId", (q) => q.eq("venueId", existingVenue!._id))
          .unique();
        if (privateDetails === null) {
          await ctx.db.insert("venuePrivateDetails", {
            venueId: existingVenue._id,
            addr: existingVenue.addr,
            lat: existingVenue.lat,
            lng: existingVenue.lng,
            normalizedAddr: normalizeVenueText(existingVenue.addr),
            capacity: application.venue.capacity,
            updatedAt,
          });
        }
        venueId = existingVenue._id;
      } else {
        venueId = await ctx.db.insert("venues", {
          name: application.venue.name,
          slug: await uniqueVenueSlug(ctx, application.venue.name),
          area: approx.label,
          addr: approx.label,
          normalizedName: normalizeVenueText(application.venue.name),
          distSF: formatMiles(SF_CENTER, approx),
          distOak: formatMiles(OAK_CENTER, approx),
          lat: approx.lat,
          lng: approx.lng,
          status: "verified",
          addressDisclosure: "onTicket",
          managedByOrganizationId: organizationId,
          venueType: application.venue.venueType,
          approxLabel: approx.label,
          approxLat: approx.lat,
          approxLng: approx.lng,
          neighborhood: approx.neighborhood ?? undefined,
          city: approx.city ?? undefined,
          capacityPublic: application.venue.capacity,
        });
        await ctx.db.insert("venuePrivateDetails", {
          venueId,
          addr: application.venue.addr,
          lat: application.venue.lat,
          lng: application.venue.lng,
          normalizedAddr,
          capacity: application.venue.capacity,
          updatedAt,
        });
      }
    }

    await ctx.db.patch(application._id, {
      status: "approved",
      reviewerUserId: reviewer._id,
      reviewNote,
      decidedAt: updatedAt,
      updatedAt,
      resultingOrganizationId: organizationId,
      resultingVenueId: venueId ?? undefined,
    });
    await scheduleApplicationEmail(
      ctx,
      "applicationApproved",
      application,
      reviewNote,
    );
    return { status: "approved" as const, organizationId, venueId };
  },
});
