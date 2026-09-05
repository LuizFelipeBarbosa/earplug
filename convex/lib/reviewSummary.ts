import { Id } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";

export const REVIEW_CATEGORIES = [
  "professionalism",
  "punctuality",
  "communication",
  "sound",
  "hospitality",
  "payment",
] as const;

export async function recomputeReviewSummary(
  ctx: MutationCtx,
  subject: { bandId: Id<"bands"> } | { organizationId: Id<"organizations"> },
): Promise<void> {
  const subjectId =
    "bandId" in subject ? subject.bandId : subject.organizationId;
  if (!(await ctx.db.get(subjectId))) return;

  const reviews =
    "bandId" in subject
      ? await ctx.db
          .query("reviews")
          .withIndex("by_subjectBandId", (q) =>
            q.eq("subjectBandId", subject.bandId),
          )
          .take(1000)
      : await ctx.db
          .query("reviews")
          .withIndex("by_subjectOrganizationId", (q) =>
            q.eq("subjectOrganizationId", subject.organizationId),
          )
          .take(1000);
  const visibleReviews = reviews.filter(
    (review) => review.visibleAt !== undefined && review.hidden === false,
  );
  const count = visibleReviews.length;
  const sum = visibleReviews.reduce(
    (total, review) => total + review.rating,
    0,
  );
  const mean = count === 0 ? 0 : Math.round((sum / count) * 100) / 100;

  const cancellationStatus =
    "bandId" in subject ? "cancelled_by_artist" : "cancelled_by_organizer";
  const [completed, paid, cancelled] = await Promise.all(
    (["completed", "paid", cancellationStatus] as const).map((status) =>
      "bandId" in subject
        ? ctx.db
            .query("bookings")
            .withIndex("by_bandId_and_status_and_startsAt", (q) =>
              q.eq("bandId", subject.bandId).eq("status", status),
            )
            .take(1000)
        : ctx.db
            .query("bookings")
            .withIndex("by_organizationId_and_status_and_startsAt", (q) =>
              q
                .eq("organizationId", subject.organizationId)
                .eq("status", status),
            )
            .take(1000),
    ),
  );
  await ctx.db.patch(subjectId, {
    reviewSummary: {
      count,
      mean,
      completedBookings: completed.length + paid.length,
      cancellations: cancelled.length,
    },
  });
}
