import { v } from "convex/values";
import { query } from "./_generated/server";
import { organizationMembershipFor } from "./lib/authz";
import { resolveCommissionBps } from "./lib/fees";
import { currentUser } from "./lib/helpers";
import { resolveTicketingFee } from "./lib/ticketFees";

export const flags = query({
  args: {},
  returns: v.object({
    privateBookings: v.boolean(),
    tickets: v.boolean(),
    payments: v.boolean(),
    bandGigWrites: v.boolean(),
    disputes: v.boolean(),
    promoters: v.boolean(),
  }),
  handler: async () => {
    return {
      privateBookings: true,
      tickets: true,
      payments: true,
      bandGigWrites: true,
      disputes: true,
      promoters: true,
    };
  },
});

export const fees = query({
  args: { organizationId: v.optional(v.id("organizations")) },
  returns: v.object({
    bookingCommissionBps: v.number(),
    ticketingFeeBps: v.number(),
    ticketingFeeFixedMinor: v.number(),
    configured: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const user = args.organizationId ? await currentUser(ctx) : null;
    const membership =
      args.organizationId && user
        ? await organizationMembershipFor(ctx, args.organizationId, user._id)
        : null;
    const organization =
      args.organizationId && membership
        ? await ctx.db.get(args.organizationId)
        : null;
    let configured = true;
    let bookingCommissionBps = 0;
    try {
      bookingCommissionBps = resolveCommissionBps({
        bookingCommissionBps: organization?.bookingCommissionBps,
      });
    } catch {
      configured = false;
    }

    let ticketingFeeBps = 0;
    let ticketingFeeFixedMinor = 0;
    try {
      const ticketingFee = resolveTicketingFee(
        organization ?? {
          ticketingFeeBps: undefined,
          ticketingFeeFixedMinor: undefined,
        },
      );
      ticketingFeeBps = ticketingFee.bps;
      ticketingFeeFixedMinor = ticketingFee.fixedMinor;
    } catch {
      configured = false;
    }

    return {
      bookingCommissionBps,
      ticketingFeeBps,
      ticketingFeeFixedMinor,
      configured,
    };
  },
});
