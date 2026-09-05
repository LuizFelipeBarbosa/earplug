import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import {
  QueryCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  organizationMembershipFor,
  requireOrganizationRole,
  requirePlatformAdmin,
} from "./lib/authz";
import { REVIEW_WINDOW_MS } from "./lib/bookingStatus";
import { requireUser } from "./lib/helpers";
import { REVIEW_CATEGORIES, recomputeReviewSummary } from "./lib/reviewSummary";
import { reviewSideValidator } from "./schema";

export const reviewPayloadValidator = v.object({
  reviewId: v.id("reviews"),
  authorSide: reviewSideValidator,
  rating: v.number(),
  categories: v.array(v.string()),
  text: v.string(),
  submittedAt: v.number(),
  visibleAt: v.union(v.number(), v.null()),
});

const listingReviewPayloadValidator = reviewPayloadValidator
  .omit("authorSide", "visibleAt")
  .extend({ monthLabel: v.string(), opportunityTitle: v.string() });
const bandReviewPayloadValidator = listingReviewPayloadValidator.extend({
  organizationName: v.string(),
});
const organizationReviewPayloadValidator = listingReviewPayloadValidator.extend(
  {
    bandName: v.string(),
  },
);

function validateRating(rating: number): void {
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new Error("Rating must be an integer between 1 and 5");
  }
}

function validateCategories(categories: string[]): void {
  if (categories.length > REVIEW_CATEGORIES.length) {
    throw new Error("Review must have at most 6 categories");
  }
  for (const category of categories) {
    if (!REVIEW_CATEGORIES.some((allowed) => allowed === category)) {
      throw new Error(`Unknown review category: ${category}`);
    }
  }
}

function normalizeReviewText(value: string): string {
  const text = value.trim();
  if (text.length > 1000) {
    throw new Error("Review text must be at most 1000 characters");
  }
  return text;
}

type BookingParty =
  | { authorSide: "organizer"; subject: { bandId: Id<"bands"> } }
  | { authorSide: "artist"; subject: { organizationId: Id<"organizations"> } };

async function requireBookingParty(
  ctx: QueryCtx,
  booking: Doc<"bookings">,
  userId: Id<"users">,
): Promise<BookingParty> {
  const organizationMembership = await organizationMembershipFor(
    ctx,
    booking.organizationId,
    userId,
  );
  if (
    organizationMembership?.role === "owner" ||
    organizationMembership?.role === "manager"
  ) {
    return { authorSide: "organizer", subject: { bandId: booking.bandId } };
  }
  const bandMembership = await ctx.db
    .query("bandMembers")
    .withIndex("by_band_user", (q) =>
      q.eq("bandId", booking.bandId).eq("userId", userId),
    )
    .unique();
  if (bandMembership?.role === "admin") {
    return {
      authorSide: "artist",
      subject: { organizationId: booking.organizationId },
    };
  }
  throw new Error("Only booking parties can review");
}

function toReviewPayload(
  review: Doc<"reviews">,
): Infer<typeof reviewPayloadValidator> {
  return {
    reviewId: review._id,
    authorSide: review.authorSide,
    rating: review.rating,
    categories: review.categories,
    text: review.text,
    submittedAt: review.submittedAt,
    visibleAt: review.visibleAt ?? null,
  };
}

function visibleListingReviews(reviews: Doc<"reviews">[], limit?: number) {
  return reviews
    .filter(
      (review): review is Doc<"reviews"> & { visibleAt: number } =>
        review.visibleAt !== undefined && review.hidden === false,
    )
    .sort((a, b) => b.visibleAt - a.visibleAt)
    .slice(0, Math.min(limit ?? 20, 50));
}

function toListingReviewPayload(
  review: Doc<"reviews">,
  opportunityTitle: string,
): Infer<typeof listingReviewPayloadValidator> {
  return {
    reviewId: review._id,
    rating: review.rating,
    categories: review.categories,
    text: review.text,
    submittedAt: review.submittedAt,
    monthLabel: new Date(review.submittedAt).toLocaleDateString("en-US", {
      month: "short",
      year: "numeric",
      timeZone: "UTC",
    }),
    opportunityTitle,
  };
}

export const submit = mutation({
  args: {
    bookingId: v.id("bookings"),
    rating: v.number(),
    categories: v.array(v.string()),
    text: v.string(),
  },
  returns: v.object({ reviewId: v.id("reviews"), visible: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    if (booking.status !== "completed" && booking.status !== "paid") {
      throw new Error("Booking has not been completed yet");
    }
    const { authorSide, subject } = await requireBookingParty(
      ctx,
      booking,
      user._id,
    );
    const now = Date.now();
    if (now > (booking.completedAt ?? 0) + REVIEW_WINDOW_MS) {
      throw new Error("The review window has closed");
    }
    const existing = await ctx.db
      .query("reviews")
      .withIndex("by_bookingId_and_authorSide", (q) =>
        q.eq("bookingId", booking._id).eq("authorSide", authorSide),
      )
      .unique();
    if (existing) throw new Error("You already reviewed this booking");

    validateRating(args.rating);
    validateCategories(args.categories);
    const text = normalizeReviewText(args.text);
    const reviewId = await ctx.db.insert("reviews", {
      bookingId: booking._id,
      authorSide,
      authorUserId: user._id,
      ...("bandId" in subject
        ? { subjectBandId: subject.bandId }
        : { subjectOrganizationId: subject.organizationId }),
      rating: args.rating,
      categories: args.categories,
      text,
      submittedAt: now,
      hidden: false,
      privateEvent: false,
    });
    const other = await ctx.db
      .query("reviews")
      .withIndex("by_bookingId_and_authorSide", (q) =>
        q
          .eq("bookingId", booking._id)
          .eq(
            "authorSide",
            authorSide === "organizer" ? "artist" : "organizer",
          ),
      )
      .unique();
    // The new review is pending; reveal the pair atomically when both are pending.
    if (other && other.visibleAt === undefined) {
      await ctx.db.patch(reviewId, { visibleAt: now });
      await ctx.db.patch(other._id, { visibleAt: now });
      await recomputeReviewSummary(ctx, { bandId: booking.bandId });
      await recomputeReviewSummary(ctx, {
        organizationId: booking.organizationId,
      });
      return { reviewId, visible: true };
    }
    return { reviewId, visible: false };
  },
});

export const closeReviewWindow = internalMutation({
  args: { bookingId: v.id("bookings") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) return null;
    const reviews = await ctx.db
      .query("reviews")
      .withIndex("by_bookingId_and_authorSide", (q) =>
        q.eq("bookingId", booking._id),
      )
      .take(10);
    const pending = reviews.filter((review) => review.visibleAt === undefined);
    if (pending.length === 0) return null;

    const now = Date.now();
    for (const review of pending) {
      await ctx.db.patch(review._id, { visibleAt: now });
    }
    await recomputeReviewSummary(ctx, { bandId: booking.bandId });
    await recomputeReviewSummary(ctx, {
      organizationId: booking.organizationId,
    });
    return null;
  },
});

export const hide = mutation({
  args: { reviewId: v.id("reviews"), reason: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requirePlatformAdmin(ctx);
    const review = await ctx.db.get(args.reviewId);
    if (!review) throw new Error("Review not found");
    await ctx.db.patch(review._id, { hidden: true, hiddenReason: args.reason });
    if (review.subjectBandId !== undefined) {
      await recomputeReviewSummary(ctx, { bandId: review.subjectBandId });
    }
    if (review.subjectOrganizationId !== undefined) {
      await recomputeReviewSummary(ctx, {
        organizationId: review.subjectOrganizationId,
      });
    }
    return null;
  },
});

export const forBooking = query({
  args: { bookingId: v.id("bookings") },
  returns: v.object({
    mine: v.union(reviewPayloadValidator, v.null()),
    theirs: v.union(reviewPayloadValidator, v.null()),
    windowClosesAt: v.number(),
    canSubmit: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const { authorSide } = await requireBookingParty(ctx, booking, user._id);
    const mine = await ctx.db
      .query("reviews")
      .withIndex("by_bookingId_and_authorSide", (q) =>
        q.eq("bookingId", booking._id).eq("authorSide", authorSide),
      )
      .unique();
    const theirs = await ctx.db
      .query("reviews")
      .withIndex("by_bookingId_and_authorSide", (q) =>
        q
          .eq("bookingId", booking._id)
          .eq(
            "authorSide",
            authorSide === "organizer" ? "artist" : "organizer",
          ),
      )
      .unique();
    const now = Date.now();
    const windowClosesAt = (booking.completedAt ?? now) + REVIEW_WINDOW_MS;
    return {
      mine: mine ? toReviewPayload(mine) : null,
      theirs:
        theirs && theirs.visibleAt !== undefined
          ? toReviewPayload(theirs)
          : null,
      windowClosesAt,
      canSubmit:
        (booking.status === "completed" || booking.status === "paid") &&
        now <= windowClosesAt &&
        mine === null,
    };
  },
});

export const forBand = query({
  args: { bandId: v.id("bands"), limit: v.optional(v.number()) },
  returns: v.array(bandReviewPayloadValidator),
  handler: async (ctx, args) => {
    const reviews = await ctx.db
      .query("reviews")
      .withIndex("by_subjectBandId", (q) => q.eq("subjectBandId", args.bandId))
      .order("desc")
      .take(200);
    const result: Infer<typeof bandReviewPayloadValidator>[] = [];
    for (const review of visibleListingReviews(reviews, args.limit)) {
      const booking = await ctx.db.get(review.bookingId);
      if (!booking) continue;
      const organization = await ctx.db.get(booking.organizationId);
      const opportunity = await ctx.db.get(booking.opportunityId);
      if (!organization || !opportunity) continue;
      result.push({
        ...toListingReviewPayload(review, opportunity.title),
        organizationName: organization.name,
      });
    }
    return result;
  },
});

export const forOrganization = query({
  args: {
    organizationId: v.id("organizations"),
    limit: v.optional(v.number()),
  },
  returns: v.array(organizationReviewPayloadValidator),
  handler: async (ctx, args) => {
    await requireOrganizationRole(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const reviews = await ctx.db
      .query("reviews")
      .withIndex("by_subjectOrganizationId", (q) =>
        q.eq("subjectOrganizationId", args.organizationId),
      )
      .order("desc")
      .take(200);
    const result: Infer<typeof organizationReviewPayloadValidator>[] = [];
    for (const review of visibleListingReviews(reviews, args.limit)) {
      const booking = await ctx.db.get(review.bookingId);
      if (!booking) continue;
      const band = await ctx.db.get(booking.bandId);
      const opportunity = await ctx.db.get(booking.opportunityId);
      if (!band || !opportunity) continue;
      result.push({
        ...toListingReviewPayload(review, opportunity.title),
        bandName: band.name,
      });
    }
    return result;
  },
});
