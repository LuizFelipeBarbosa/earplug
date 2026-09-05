import { type Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  query,
  type QueryCtx,
} from "./_generated/server";
import { sendBookingEmail } from "./bookings";
import {
  organizationMembershipFor,
  requireOrganizationRole,
} from "./lib/authz";
import { appBaseUrl } from "./lib/env";
import { requireUser } from "./lib/helpers";
import { paymentRecordsForBooking } from "./lib/paymentSchedule";
import {
  assertPaymentRecordTransition,
  CHECKOUT_TTL_MS,
  PAYMENT_OPEN_STATUSES,
} from "./lib/paymentStatus";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import schema, {
  bookingStatusValidator,
  paymentRecordStatusValidator,
} from "./schema";

const paymentRecordValidator = schema.tables.paymentRecords.validator.extend({
  _id: v.id("paymentRecords"),
  _creationTime: v.number(),
});
const checkoutContextValidator = v.object({
  record: paymentRecordValidator,
  opportunityTitle: v.string(),
  organizationId: v.id("organizations"),
  organizationName: v.string(),
  businessEmail: v.string(),
  stripeCustomerId: v.optional(v.string()),
});

export const loadCheckoutContext = internalQuery({
  args: { paymentRecordId: v.id("paymentRecords") },
  returns: checkoutContextValidator,
  handler: async (ctx, args) => {
    const record = await ctx.db.get(args.paymentRecordId);
    if (!record) throw new Error("Payment record not found");
    const booking = await ctx.db.get(record.bookingId);
    if (!booking) throw new Error("Booking not found");
    if (
      booking.status !== "awaiting_payment" &&
      booking.status !== "confirmed"
    ) {
      throw new Error("This booking is not accepting payments");
    }
    const { organization } = await requireOrganizationRole(
      ctx,
      booking.organizationId,
      ["owner", "finance"],
    );
    const [opportunity, details] = await Promise.all([
      ctx.db.get(booking.opportunityId),
      ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", booking.organizationId),
        )
        .unique(),
    ]);
    if (!opportunity) throw new Error("Opportunity not found");
    if (!details) throw new Error("Organization private details not found");
    return {
      record,
      opportunityTitle: opportunity.title,
      organizationId: organization._id,
      organizationName: organization.name,
      businessEmail: details.businessEmail,
      stripeCustomerId: details.stripeCustomerId,
    };
  },
});

function isAlreadyClosedSession(error: unknown): boolean {
  if (!(error instanceof StripeApiError)) return false;
  return (
    /\bsession\b[\s\S]*\b(?:already|status|is|has)\b[\s\S]*\b(?:expired|complete(?:d)?)\b/i.test(
      error.message,
    ) ||
    /^(?:checkout_)?session_(?:already_)?(?:expired|complete|completed)$/.test(
      error.code ?? "",
    )
  );
}

export const startInstallmentCheckout = action({
  args: { paymentRecordId: v.id("paymentRecords") },
  returns: v.object({ url: v.string(), sessionId: v.string() }),
  handler: async (ctx, args): Promise<{ url: string; sessionId: string }> => {
    const context: Infer<typeof checkoutContextValidator> = await ctx.runQuery(
      internal.payments.loadCheckoutContext,
      args,
    );
    const {
      record,
      organizationId,
      organizationName,
      businessEmail,
      opportunityTitle,
    } = context;
    if (!PAYMENT_OPEN_STATUSES.includes(record.status)) {
      throw new Error("This installment is not payable");
    }
    if (record.status === "checkout_open" && record.stripeCheckoutSessionId) {
      try {
        await stripeRequest(
          "POST",
          `/v1/checkout/sessions/${record.stripeCheckoutSessionId}/expire`,
        );
      } catch (error) {
        if (!isAlreadyClosedSession(error)) throw error;
      }
      // Restart through expired: checkout_open cannot transition to itself.
      await ctx.runMutation(internal.payments.markSessionExpired, {
        sessionId: record.stripeCheckoutSessionId,
      });
    }
    let stripeCustomerId = context.stripeCustomerId;
    if (stripeCustomerId === undefined) {
      const customer = await stripeRequest<{ id: string }>(
        "POST",
        "/v1/customers",
        {
          name: organizationName,
          email: businessEmail,
          metadata: { organizationId },
        },
        { idempotencyKey: stripeIdempotencyKey("customer", organizationId) },
      );
      stripeCustomerId = customer.id;
      await ctx.runMutation(internal.payments.setOrganizationStripeCustomer, {
        organizationId,
        stripeCustomerId,
      });
    }
    const checkoutExpiresAt =
      Math.floor((Date.now() + CHECKOUT_TTL_MS) / 1000) * 1000;
    const session = await stripeRequest<{
      id: string;
      url: string;
      payment_intent?: string;
    }>(
      "POST",
      "/v1/checkout/sessions",
      {
        mode: "payment",
        payment_method_types: ["card"],
        customer: stripeCustomerId,
        client_reference_id: record._id,
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: record.currency,
              unit_amount: record.amountMinor,
              product_data: { name: `${opportunityTitle} · ${record.label}` },
            },
          },
        ],
        success_url: `${appBaseUrl()}/checkout/return?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${appBaseUrl()}/checkout/cancel?booking=${record.bookingId}`,
        expires_at: checkoutExpiresAt / 1000,
        payment_intent_data: {
          transfer_group: record.bookingId,
          metadata: {
            bookingId: record.bookingId,
            paymentRecordId: record._id,
          },
        },
        metadata: {
          bookingId: record.bookingId,
          paymentRecordId: record._id,
          installmentIndex: record.installmentIndex,
        },
      },
      {
        idempotencyKey: stripeIdempotencyKey(
          "checkout",
          record._id,
          record.attempt + 1,
        ),
      },
    );
    await ctx.runMutation(internal.payments.markCheckoutOpen, {
      paymentRecordId: record._id,
      sessionId: session.id,
      stripePaymentIntentId: session.payment_intent,
      checkoutExpiresAt,
      attempt: record.attempt,
    });
    return { url: session.url, sessionId: session.id };
  },
});

export const setOrganizationStripeCustomer = internalMutation({
  args: { organizationId: v.id("organizations"), stripeCustomerId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    if (!details) throw new Error("Organization private details not found");
    await ctx.db.patch(details._id, {
      stripeCustomerId: args.stripeCustomerId,
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const markCheckoutOpen = internalMutation({
  args: {
    paymentRecordId: v.id("paymentRecords"),
    sessionId: v.string(),
    stripePaymentIntentId: v.optional(v.string()),
    checkoutExpiresAt: v.number(),
    attempt: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const record = await ctx.db.get(args.paymentRecordId);
    if (!record) throw new Error("Payment record not found");
    if (
      record.status === "checkout_open" &&
      record.stripeCheckoutSessionId === args.sessionId
    ) {
      return null;
    }
    if (record.attempt !== args.attempt)
      throw new Error("Payment attempt changed elsewhere");
    assertPaymentRecordTransition(record.status, "checkout_open");
    await ctx.db.patch(record._id, {
      status: "checkout_open",
      stripeCheckoutSessionId: args.sessionId,
      stripePaymentIntentId: args.stripePaymentIntentId,
      checkoutExpiresAt: args.checkoutExpiresAt,
      attempt: args.attempt + 1,
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const openSessionsForBooking = internalQuery({
  args: { bookingId: v.id("bookings") },
  returns: v.array(paymentRecordValidator),
  handler: async (ctx, args) => {
    const records = await paymentRecordsForBooking(ctx, args.bookingId);
    return records.filter((record) => record.status === "checkout_open");
  },
});

export const expireOpenSessions = internalAction({
  args: { bookingId: v.id("bookings") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const records: Doc<"paymentRecords">[] = await ctx.runQuery(
      internal.payments.openSessionsForBooking,
      args,
    );
    for (const record of records) {
      const sessionId = record.stripeCheckoutSessionId;
      if (!sessionId) continue;
      try {
        await stripeRequest(
          "POST",
          `/v1/checkout/sessions/${sessionId}/expire`,
        );
      } catch (error) {
        console.error(`Could not expire Checkout session ${sessionId}`, error);
      }
      await ctx.runMutation(internal.payments.markSessionExpired, {
        sessionId,
      });
    }
    return null;
  },
});

export const remindPayment = internalMutation({
  args: {
    bookingId: v.id("bookings"),
    paymentRecordId: v.id("paymentRecords"),
    revision: v.optional(v.number()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const record = await ctx.db.get(args.paymentRecordId);
    if (
      !record ||
      record.bookingId !== args.bookingId ||
      !PAYMENT_OPEN_STATUSES.includes(record.status)
    ) {
      return null;
    }
    const booking = await ctx.db.get(args.bookingId);
    if (
      !booking ||
      !["awaiting_payment", "confirmed"].includes(booking.status)
    ) {
      return null;
    }
    // Stand-in until emails.ts supports a dedicated paymentReminder kind.
    await sendBookingEmail(ctx, booking, "offerAccepted", {
      reason: `Payment due ${new Date(record.dueAt).toISOString()}`,
    });
    return null;
  },
});

async function requirePaymentParty(ctx: QueryCtx, booking: Doc<"bookings">) {
  const user = await requireUser(ctx);
  const membership = await organizationMembershipFor(
    ctx,
    booking.organizationId,
    user._id,
  );
  if (!membership) {
    const bandMembership = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", booking.bandId).eq("userId", user._id),
      )
      .unique();
    if (bandMembership?.role !== "admin") {
      throw new Error("Not permitted to view these payments");
    }
  }
  return membership;
}

export const paymentsForBooking = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(
    v.object({
      _id: v.id("paymentRecords"),
      installmentIndex: v.number(),
      label: v.string(),
      amountMinor: v.number(),
      currency: v.string(),
      dueAt: v.number(),
      status: paymentRecordStatusValidator,
      paidAt: v.union(v.number(), v.null()),
      canPay: v.boolean(),
    }),
  ),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found");
    const membership = await requirePaymentParty(ctx, booking);
    const canPay =
      membership?.role === "owner" || membership?.role === "finance";
    const records = await paymentRecordsForBooking(ctx, booking._id);
    const openIndexes = records
      .filter((record) => PAYMENT_OPEN_STATUSES.includes(record.status))
      .map((record) => record.installmentIndex);
    const lowestOpenIndex = openIndexes.length ? Math.min(...openIndexes) : null;
    return records.map((record) => ({
      _id: record._id,
      installmentIndex: record.installmentIndex,
      label: record.label,
      amountMinor: record.amountMinor,
      currency: record.currency,
      dueAt: record.dueAt,
      status: record.status,
      paidAt: record.paidAt ?? null,
      canPay:
        canPay &&
        PAYMENT_OPEN_STATUSES.includes(record.status) &&
        record.installmentIndex === lowestOpenIndex,
    }));
  },
});

export const checkoutStatus = query({
  args: { sessionId: v.string() },
  returns: v.union(
    v.object({
      bookingId: v.id("bookings"),
      paymentStatus: paymentRecordStatusValidator,
      bookingStatus: bookingStatusValidator,
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const record = await ctx.db
      .query("paymentRecords")
      .withIndex("by_stripeCheckoutSessionId", (q) =>
        q.eq("stripeCheckoutSessionId", args.sessionId),
      )
      .unique();
    if (!record) return null;
    const booking = await ctx.db.get(record.bookingId);
    if (!booking) throw new Error("Booking not found");
    await requirePaymentParty(ctx, booking);
    return {
      bookingId: booking._id,
      paymentStatus: record.status,
      bookingStatus: booking.status,
    };
  },
});

export const markPaid = internalMutation({
  args: {
    paymentRecordId: v.id("paymentRecords"),
    paymentIntentId: v.string(),
    chargeId: v.optional(v.string()),
    amountMinor: v.number(),
    eventId: v.string(),
    sessionId: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const record = await ctx.db.get(args.paymentRecordId);
    if (!record) throw new Error("Payment record not found");
    if (record.status === "paid") return null;
    assertPaymentRecordTransition(record.status, "paid");
    const now = Date.now();
    await ctx.db.patch(record._id, {
      status: "paid",
      stripePaymentIntentId: args.paymentIntentId,
      stripeChargeId: args.chargeId,
      stripeCheckoutSessionId: args.sessionId,
      stripeEventId: args.eventId,
      paidAt: now,
      updatedAt: now,
    });
    return null;
  },
});

export const markSessionExpired = internalMutation({
  args: { sessionId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const record = await ctx.db
      .query("paymentRecords")
      .withIndex("by_stripeCheckoutSessionId", (q) =>
        q.eq("stripeCheckoutSessionId", args.sessionId),
      )
      .unique();
    if (
      !record ||
      ["paid", "refunded", "partially_refunded", "expired"].includes(
        record.status,
      )
    ) {
      return null;
    }
    assertPaymentRecordTransition(record.status, "expired");
    await ctx.db.patch(record._id, {
      status: "expired",
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const markFailed = internalMutation({
  args: {
    paymentIntentId: v.string(),
    metadataPaymentRecordId: v.optional(v.id("paymentRecords")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    let record = await ctx.db
      .query("paymentRecords")
      .withIndex("by_stripePaymentIntentId", (q) =>
        q.eq("stripePaymentIntentId", args.paymentIntentId),
      )
      .unique();
    if (!record && args.metadataPaymentRecordId) {
      record = await ctx.db.get(args.metadataPaymentRecordId);
    }
    if (!record) {
      console.log(
        `payment_intent.payment_failed ignored: no payment record for intent ${args.paymentIntentId}`,
      );
      return null;
    }
    if (
      ["paid", "refunded", "partially_refunded", "failed"].includes(
        record.status,
      )
    )
      return null;
    assertPaymentRecordTransition(record.status, "failed");
    await ctx.db.patch(record._id, { status: "failed", updatedAt: Date.now() });
    return null;
  },
});
