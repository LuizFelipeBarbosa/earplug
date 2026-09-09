import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { env, query } from "./_generated/server";
import { flag } from "./lib/env";
import { resolveCommissionBps } from "./lib/fees";
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
      privateBookings: flag("PRIVATE_BOOKINGS_ENABLED", false),
      tickets: flag("TICKETS_ENABLED", false),
      payments: flag("PAYMENTS_ENABLED", false),
      bandGigWrites: flag("BAND_GIG_WRITES", true),
      disputes: flag("DISPUTES_ENABLED", false),
      promoters: flag("PROMOTERS_ENABLED", false),
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
    const organization = args.organizationId
      ? await ctx.db.get(args.organizationId)
      : null;
    let configured = true;
    let bookingCommissionBps = 0;
    try {
      bookingCommissionBps = resolveCommissionBps(
        organization ??
          ({ bookingCommissionBps: undefined } as Doc<"organizations">),
      );
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
