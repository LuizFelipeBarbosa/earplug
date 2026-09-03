import migrations from "@convex-dev/migrations/convex.config.js";
import { defineApp } from "convex/server";
import { v } from "convex/values";

const app = defineApp({
  env: {
    STRIPE_SECRET_KEY: v.optional(v.string()),
    STRIPE_WEBHOOK_SECRET: v.optional(v.string()),
    STRIPE_CONNECT_WEBHOOK_SECRET: v.optional(v.string()),
    BOOKING_COMMISSION_BPS: v.optional(v.string()),
    TICKETING_FEE_BPS: v.optional(v.string()),
    TICKETING_FEE_FIXED_MINOR: v.optional(v.string()),
    APP_BASE_URL: v.optional(v.string()),
    RESEND_API_KEY: v.optional(v.string()),
    RESEND_SEND_ENABLED: v.optional(v.string()),
    PAYMENTS_ENABLED: v.optional(v.string()),
    TICKETS_ENABLED: v.optional(v.string()),
    PRIVATE_BOOKINGS_ENABLED: v.optional(v.string()),
    BAND_GIG_WRITES: v.optional(v.string()),
  },
});
app.use(migrations);

export default app;
