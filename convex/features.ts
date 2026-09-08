import { v } from "convex/values";
import { env, query } from "./_generated/server";
import { flag } from "./lib/env";

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
