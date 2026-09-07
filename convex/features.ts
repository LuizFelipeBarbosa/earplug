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
  }),
  handler: async () => {
    // The disputes flag is not yet declared in the generated environment type.
    const disputesEnabled =
      "DISPUTES_ENABLED" in env ? env.DISPUTES_ENABLED : undefined;
    return {
      privateBookings: flag("PRIVATE_BOOKINGS_ENABLED", false),
      tickets: flag("TICKETS_ENABLED", false),
      payments: flag("PAYMENTS_ENABLED", false),
      bandGigWrites: flag("BAND_GIG_WRITES", true),
      disputes: disputesEnabled === "true" || disputesEnabled === "1",
    };
  },
});
