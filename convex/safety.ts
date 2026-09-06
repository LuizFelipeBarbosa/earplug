import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { resolveVenueName } from "./bookings";
import { bookingEmail } from "./emails";
import {
  organizationMembershipFor,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import { appBaseUrl } from "./lib/env";
import { requireUser } from "./lib/helpers";

const REPORT_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const sideValidator = v.union(v.literal("organizer"), v.literal("artist"));
const categoryValidator = v.union(
  v.literal("safety"),
  v.literal("harassment"),
  v.literal("misrepresentation"),
  v.literal("other"),
);
const safetyReportValidator = v.object({
  _id: v.id("safetyReports"),
  bookingId: v.id("bookings"),
  reporterUserId: v.id("users"),
  side: sideValidator,
  category: categoryValidator,
  text: v.string(),
  status: v.union(v.literal("open"), v.literal("resolved")),
  createdAt: v.number(),
  resolvedAt: v.optional(v.number()),
  resolvedBy: v.optional(v.id("users")),
  adminNote: v.optional(v.string()),
});
const safetyReportMineValidator = safetyReportValidator.omit(
  "adminNote",
  "resolvedBy",
);

async function reportingSide(
  ctx: QueryCtx,
  booking: Doc<"bookings">,
  user: Doc<"users">,
): Promise<"organizer" | "artist"> {
  const bandMembership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", booking.bandId).eq("userId", user._id),
    )
    .unique();
  if (bandMembership?.role === "admin") return "artist";

  const membership = await organizationMembershipFor(
    ctx,
    booking.organizationId,
    user._id,
  );
  if (membership?.role === "owner" || membership?.role === "manager") {
    return "organizer";
  }
  throw new Error("Not permitted to report on this booking");
}

function reportPayload({ _creationTime, ...report }: Doc<"safetyReports">) {
  return report;
}

export const report = mutation({
  args: {
    bookingId: v.id("bookings"),
    category: categoryValidator,
    text: v.string(),
  },
  returns: v.object({ reportId: v.id("safetyReports") }),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const user = await requireUser(ctx);
    const side = await reportingSide(ctx, booking, user);
    const text = args.text.trim();
    if (text.length < 10 || text.length > 2000) {
      throw new Error("Report details must be between 10 and 2000 characters");
    }
    const now = Date.now();
    const withinPostEventWindow =
      (booking.status === "completed" ||
        booking.status === "paid" ||
        booking.status === "cancelled_by_organizer" ||
        booking.status === "cancelled_by_artist" ||
        booking.status === "disputed" ||
        booking.status === "force_majeure" ||
        booking.status === "refunded") &&
      now < booking.startsAt + REPORT_WINDOW_MS;
    if (booking.status !== "confirmed" && !withinPostEventWindow) {
      throw new Error("Reports are open until 30 days after the event");
    }

    const reportId = await ctx.db.insert("safetyReports", {
      bookingId: booking._id,
      reporterUserId: user._id,
      side,
      category: args.category,
      text,
      status: "open",
      createdAt: now,
    });
    const to = user.email.trim();
    if (to) {
      const [opportunity, band, organization] = await Promise.all([
        ctx.db.get(booking.opportunityId),
        ctx.db.get(booking.bandId),
        ctx.db.get(booking.organizationId),
      ]);
      if (!opportunity) throw new Error("Opportunity not found");
      if (!band) throw new Error("Band not found");
      if (!organization) throw new Error("Organization not found");
      const venueName = await resolveVenueName(ctx, opportunity);
      const body = bookingEmail("safetyReportReceived", {
        opportunityTitle: opportunity.title,
        bandName: band.name,
        orgName: organization.name,
        venueName,
        startsAt: booking.startsAt,
        link: `${appBaseUrl()}/bookings/${booking._id}`,
      });
      await ctx.scheduler.runAfter(0, internal.emails.send, {
        kind: "safetyReportReceived",
        to,
        ...body,
      });
    }
    return { reportId };
  },
});

export const mine = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(safetyReportMineValidator),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const user = await requireUser(ctx);
    await reportingSide(ctx, booking, user);
    const reports = await ctx.db
      .query("safetyReports")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", booking._id))
      .order("desc")
      .collect();
    return reports
      .filter((report) => report.reporterUserId === user._id)
      .map(({ _creationTime, adminNote, resolvedBy, ...report }) => report);
  },
});

export const listOpen = query({
  args: { paginationOpts: paginationOptsValidator },
  returns: paginationResultValidator(
    safetyReportValidator.extend({
      bookingTitle: v.string(),
      bandName: v.string(),
      reporterSide: sideValidator,
    }),
  ),
  handler: async (ctx, args) => {
    await requirePlatformAdminQuery(ctx);
    const result = await ctx.db
      .query("safetyReports")
      .withIndex("by_status_and_createdAt", (q) => q.eq("status", "open"))
      .order("desc")
      .paginate(args.paginationOpts);
    const page = await Promise.all(
      result.page.map(async (report) => {
        const booking = await ctx.db.get(report.bookingId);
        const [opportunity, band] = booking
          ? await Promise.all([
              ctx.db.get(booking.opportunityId),
              ctx.db.get(booking.bandId),
            ])
          : [null, null];
        return {
          ...reportPayload(report),
          bookingTitle: opportunity?.title ?? "(deleted booking)",
          bandName: band?.name ?? "(deleted band)",
          reporterSide: report.side,
        };
      }),
    );
    return { ...result, page };
  },
});

export const resolve = mutation({
  args: { reportId: v.id("safetyReports"), adminNote: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requirePlatformAdmin(ctx);
    const report = await ctx.db.get(args.reportId);
    if (!report) throw new Error("Report not found");
    await ctx.db.patch(report._id, {
      status: "resolved",
      resolvedAt: Date.now(),
      resolvedBy: user._id,
      adminNote: args.adminNote,
    });
    return null;
  },
});

export const forBookingAdmin = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(safetyReportValidator),
  handler: async (ctx, args) => {
    await requirePlatformAdminQuery(ctx);
    const reports = await ctx.db
      .query("safetyReports")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", args.bookingId))
      .order("desc")
      .collect();
    return reports.map(reportPayload);
  },
});
