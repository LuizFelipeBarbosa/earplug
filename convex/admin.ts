import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { type Infer, v } from "convex/values";
import {
  env,
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import {
  isPlatformAdmin,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import { openInAppDispute } from "./lib/disputeHold";
import { deploymentName, flag } from "./lib/env";
import { currentUser } from "./lib/helpers";
import { bookingStatusValidator } from "./schema";

export const me = query({
  args: {},
  returns: v.object({ isPlatformAdmin: v.boolean() }),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    return {
      isPlatformAdmin:
        user === null ? false : await isPlatformAdmin(ctx, user._id),
    };
  },
});

export const overview = query({
  args: {},
  returns: v.object({
    counts: v.object({
      submittedApplications: v.number(),
      underReviewApplications: v.number(),
      needsInfoApplications: v.number(),
      verifiedOrganizations: v.number(),
      suspendedOrganizations: v.number(),
      hostApplications: v.object({
        submitted: v.number(),
        under_review: v.number(),
        needs_info: v.number(),
      }),
    }),
    capped: v.boolean(),
  }),
  handler: async (ctx) => {
    await requirePlatformAdminQuery(ctx);
    const [
      submitted,
      underReview,
      needsInfo,
      verified,
      suspended,
      hostSubmitted,
      hostUnderReview,
      hostNeedsInfo,
    ] = await Promise.all([
      ctx.db
        .query("organizationApplications")
        .withIndex("by_status_and_createdAt", (q) =>
          q.eq("status", "submitted"),
        )
        .take(101),
      ctx.db
        .query("organizationApplications")
        .withIndex("by_status_and_createdAt", (q) =>
          q.eq("status", "under_review"),
        )
        .take(101),
      ctx.db
        .query("organizationApplications")
        .withIndex("by_status_and_createdAt", (q) =>
          q.eq("status", "needs_info"),
        )
        .take(101),
      ctx.db
        .query("organizations")
        .withIndex("by_status_and_name", (q) => q.eq("status", "verified"))
        .take(101),
      ctx.db
        .query("organizations")
        .withIndex("by_status_and_name", (q) => q.eq("status", "suspended"))
        .take(101),
      ctx.db
        .query("organizationApplications")
        .withIndex("by_kind_and_status_and_createdAt", (q) =>
          q.eq("kind", "host").eq("status", "submitted"),
        )
        .take(101),
      ctx.db
        .query("organizationApplications")
        .withIndex("by_kind_and_status_and_createdAt", (q) =>
          q.eq("kind", "host").eq("status", "under_review"),
        )
        .take(101),
      ctx.db
        .query("organizationApplications")
        .withIndex("by_kind_and_status_and_createdAt", (q) =>
          q.eq("kind", "host").eq("status", "needs_info"),
        )
        .take(101),
    ]);
    const rows = [
      submitted,
      underReview,
      needsInfo,
      verified,
      suspended,
      hostSubmitted,
      hostUnderReview,
      hostNeedsInfo,
    ];
    return {
      counts: {
        submittedApplications: Math.min(submitted.length, 100),
        underReviewApplications: Math.min(underReview.length, 100),
        needsInfoApplications: Math.min(needsInfo.length, 100),
        verifiedOrganizations: Math.min(verified.length, 100),
        suspendedOrganizations: Math.min(suspended.length, 100),
        hostApplications: {
          submitted: Math.min(hostSubmitted.length, 100),
          under_review: Math.min(hostUnderReview.length, 100),
          needs_info: Math.min(hostNeedsInfo.length, 100),
        },
      },
      capped: rows.some((group) => group.length === 101),
    };
  },
});

export const opsHealth = internalQuery({
  args: { days: v.optional(v.number()), now: v.number() },
  returns: v.object({
    deployment: v.string(),
    since: v.number(),
    flags: v.object({
      payments: v.boolean(),
      tickets: v.boolean(),
      privateBookings: v.boolean(),
      disputes: v.boolean(),
      promoters: v.boolean(),
      bandGigWrites: v.boolean(),
      resendSend: v.boolean(),
    }),
    resendConfigured: v.boolean(),
    stripeEvents: v.array(
      v.object({
        type: v.string(),
        status: v.string(),
        livemode: v.boolean(),
        count: v.number(),
        lastReceivedAt: v.number(),
      }),
    ),
    failed: v.array(
      v.object({
        eventId: v.string(),
        type: v.string(),
        receivedAt: v.number(),
        error: v.optional(v.string()),
      }),
    ),
  }),
  handler: async (ctx, args) => {
    const days = Math.min(30, Math.max(1, args.days ?? 7));
    const since = args.now - days * 24 * 60 * 60 * 1000;
    const rows = await ctx.db
      .query("stripeEvents")
      .withIndex("by_receivedAt", (q) => q.gte("receivedAt", since))
      .order("desc")
      .take(5000);

    const groups = new Map<
      string,
      {
        type: string;
        status: string;
        livemode: boolean;
        count: number;
        lastReceivedAt: number;
      }
    >();
    for (const row of rows) {
      const key = JSON.stringify([row.type, row.status, row.livemode]);
      const group = groups.get(key);
      if (group) {
        group.count++;
      } else {
        groups.set(key, {
          type: row.type,
          status: row.status,
          livemode: row.livemode,
          count: 1,
          // Rows are newest first, so the first row has the latest timestamp.
          lastReceivedAt: row.receivedAt,
        });
      }
    }
    const stripeEvents = Array.from(groups.values()).sort(
      (a, b) =>
        a.type.localeCompare(b.type) ||
        a.status.localeCompare(b.status) ||
        Number(a.livemode) - Number(b.livemode),
    );
    const failed = rows
      .filter((row) => row.status === "failed")
      .slice(0, 20)
      .map((row) => ({
        eventId: row.eventId,
        type: row.type,
        receivedAt: row.receivedAt,
        error: row.error,
      }));

    return {
      deployment: deploymentName() ?? "unknown",
      since,
      flags: {
        payments: flag("PAYMENTS_ENABLED", false),
        tickets: flag("TICKETS_ENABLED", false),
        privateBookings: flag("PRIVATE_BOOKINGS_ENABLED", false),
        disputes: flag("DISPUTES_ENABLED", false),
        promoters: flag("PROMOTERS_ENABLED", false),
        bandGigWrites: flag("BAND_GIG_WRITES", true),
        resendSend: flag("RESEND_SEND_ENABLED", false),
      },
      resendConfigured: Boolean(env.RESEND_API_KEY),
      stripeEvents,
      failed,
    };
  },
});

const bookingRowValidator = v.object({
  bookingId: v.id("bookings"),
  title: v.string(),
  organizationName: v.string(),
  bandName: v.string(),
  status: bookingStatusValidator,
  startsAt: v.number(),
  paidMinor: v.number(),
  refundedMinor: v.number(),
  payoutHoldReasons: v.array(v.string()),
  openDisputeId: v.union(v.id("disputes"), v.null()),
});

export const bookings = query({
  args: {
    filter: v.union(
      v.literal("all"),
      v.literal("disputed"),
      v.literal("held"),
      v.literal("awaiting_payment"),
    ),
    paginationOpts: paginationOptsValidator,
  },
  returns: paginationResultValidator(bookingRowValidator),
  handler: async (ctx, args) => {
    await requirePlatformAdminQuery(ctx);
    const filter = args.filter;
    const source = ctx.db.query("bookings");
    const result =
      filter === "disputed" || filter === "awaiting_payment"
        ? await source
            .withIndex("by_status_and_startsAt", (q) => q.eq("status", filter))
            .order("desc")
            .paginate(args.paginationOpts)
        : await source.order("desc").paginate(args.paginationOpts);

    let rows = result.page;
    // Known limitation: filtering after pagination can return fewer (even zero)
    // rows than requested while more held bookings exist on later pages.
    if (filter === "held") {
      rows = rows.filter((booking) => (booking.payoutHoldReasons?.length ?? 0) > 0);
    }

    const page: Infer<typeof bookingRowValidator>[] = [];
    for (const booking of rows) {
      const [organization, band, opportunity] = await Promise.all([
        ctx.db.get(booking.organizationId),
        ctx.db.get(booking.bandId),
        ctx.db.get(booking.opportunityId),
      ]);
      if (!organization || !band || !opportunity) continue;
      const openDispute = await openInAppDispute(ctx, booking._id);
      page.push({
        bookingId: booking._id,
        title: opportunity.title,
        organizationName: organization.name,
        bandName: band.name,
        status: booking.status,
        startsAt: booking.startsAt,
        paidMinor: booking.paidMinor ?? 0,
        refundedMinor: booking.refundedMinor ?? 0,
        payoutHoldReasons: booking.payoutHoldReasons ?? [],
        openDisputeId: openDispute?._id ?? null,
      });
    }
    return { ...result, page };
  },
});

export const suspendOrganization = mutation({
  args: {
    organizationId: v.id("organizations"),
    suspended: v.boolean(),
    note: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requirePlatformAdmin(ctx);
    const organization = await ctx.db.get(args.organizationId);
    if (!organization) throw new Error("Organization not found");

    if (args.suspended) {
      await ctx.db.patch(args.organizationId, {
        status: "suspended",
        suspendedAt: Date.now(),
        suspensionNote: args.note,
      });
    } else {
      await ctx.db.patch(args.organizationId, {
        status: "verified",
        suspendedAt: undefined,
        suspensionNote: undefined,
      });
    }

    const venues = await ctx.db
      .query("venues")
      .withIndex("by_managedByOrganizationId", (q) =>
        q.eq("managedByOrganizationId", args.organizationId),
      )
      .take(50);
    for (const venue of venues) {
      await ctx.db.patch(venue._id, {
        status: args.suspended ? "suspended" : "verified",
      });
    }
    return null;
  },
});

export const grantPlatformAdmin = internalMutation({
  args: {
    userId: v.id("users"),
    note: v.optional(v.string()),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({
    granted: v.boolean(),
    alreadyAdmin: v.boolean(),
    dryRun: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    if (await isPlatformAdmin(ctx, args.userId)) {
      return { granted: false, alreadyAdmin: true, dryRun };
    }
    if (dryRun) {
      return { granted: false, alreadyAdmin: false, dryRun: true };
    }
    await ctx.db.insert("platformAdmins", {
      userId: args.userId,
      grantedAt: Date.now(),
      ...(args.note === undefined ? {} : { note: args.note }),
    });
    return { granted: true, alreadyAdmin: false, dryRun: false };
  },
});

export const revokePlatformAdmin = internalMutation({
  args: {
    userId: v.id("users"),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({ revoked: v.boolean(), dryRun: v.boolean() }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const activeGrant = await ctx.db
      .query("platformAdmins")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .filter((q) => q.eq(q.field("revokedAt"), undefined))
      .first();
    if (!activeGrant) return { revoked: false, dryRun };
    if (dryRun) return { revoked: false, dryRun: true };
    await ctx.db.patch(activeGrant._id, { revokedAt: Date.now() });
    return { revoked: true, dryRun: false };
  },
});
