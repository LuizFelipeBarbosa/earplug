import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { deploymentName } from "./lib/env";
import {
  uniqueHostOrganizationSlug,
  uniqueOrganizationSlug,
} from "./organizationApplications";
import { organizationTypeValidator } from "./schema";

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

/**
 * Test-data helper for development deployments: creates a verified organization
 * owned by a user so promoter flows can be exercised without an organizer
 * application. Refuses to run on production and defaults to a dry run.
 */
export const grantOrganization = internalMutation({
  args: {
    userId: v.id("users"),
    name: v.string(),
    orgType: organizationTypeValidator,
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({
    applied: v.boolean(),
    organizationId: v.union(v.id("organizations"), v.null()),
    slug: v.string(),
  }),
  handler: async (ctx, args) => {
    if (deploymentName() === PROD_DEPLOYMENT) {
      throw new Error("grantOrganization is a development-only tool");
    }
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("User not found");
    const slug =
      args.orgType === "privateHost"
        ? await uniqueHostOrganizationSlug(ctx)
        : await uniqueOrganizationSlug(ctx, args.name);
    const dryRun = args.dryRun ?? true;
    if (!dryRun) {
      const now = Date.now();
      const organizationId = await ctx.db.insert("organizations", {
        name: args.name,
        slug,
        orgType: args.orgType,
        status: "verified",
        ownerUserId: args.userId,
        verifiedAt: now,
        createdAt: now,
        updatedAt: now,
      });
      await ctx.db.insert("organizationPrivateDetails", {
        organizationId,
        businessEmail: user.email,
        contactName: user.name,
        phone: undefined,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: [],
        updatedAt: now,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: args.userId,
        role: "owner",
        createdAt: now,
      });
      return { applied: true, organizationId, slug };
    }
    return { applied: false, organizationId: null, slug };
  },
});
