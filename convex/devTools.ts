import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { deploymentName } from "./lib/env";

const PROD_DEPLOYMENT = "decisive-iguana-759";

/**
 * Test-data helper for development deployments: moves a booking (and its
 * opportunity) to a new start time so time-gated flows such as disputes can be
 * exercised without waiting. Refuses to run on production and defaults to a
 * dry run.
 */
export const shiftBookingStart = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    startsAt: v.number(),
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({
    applied: v.boolean(),
    previousStartsAt: v.number(),
    startsAt: v.number(),
  }),
  handler: async (ctx, args) => {
    if (deploymentName() === PROD_DEPLOYMENT) {
      throw new Error("shiftBookingStart is a development-only tool");
    }
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const dryRun = args.dryRun ?? true;
    if (!dryRun) {
      const now = Date.now();
      await ctx.db.patch(booking._id, { startsAt: args.startsAt, updatedAt: now });
      const opportunity = await ctx.db.get(booking.opportunityId);
      if (opportunity) {
        const shift = args.startsAt - opportunity.startsAt;
        await ctx.db.patch(opportunity._id, {
          startsAt: args.startsAt,
          doorsAt:
            opportunity.doorsAt === undefined
              ? undefined
              : opportunity.doorsAt + shift,
          endsAt:
            opportunity.endsAt === undefined
              ? undefined
              : opportunity.endsAt + shift,
          updatedAt: now,
        });
      }
    }
    return {
      applied: !dryRun,
      previousStartsAt: booking.startsAt,
      startsAt: args.startsAt,
    };
  },
});
