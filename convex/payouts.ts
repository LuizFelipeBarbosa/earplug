import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { type Infer, v } from "convex/values";
import { internal as generatedInternal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import {
  internalAction,
  internalMutation,
  internalQuery,
  query,
  type MutationCtx,
} from "./_generated/server";
import { isPlatformAdmin, organizationMembershipFor } from "./lib/authz";
import { assertBookingTransition } from "./lib/bookingStatus";
import { currentUser, requireBandRole } from "./lib/helpers";
import { appendLedgerEntry } from "./lib/ledger";
import { paymentRecordsForBooking } from "./lib/paymentSchedule";
import {
  assertPayoutTransition,
  HELD_PAYOUT_MAX_DAYS,
  HELD_PAYOUT_RETRY_MS,
  PAYOUT_DELAY_MS,
} from "./lib/paymentStatus";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import type * as payouts from "./payouts";
import schema, {
  payoutHoldReasonValidator,
  payoutStatusValidator,
} from "./schema";

// Keep references typed until the shared generated API includes this module.
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ payouts: typeof payouts }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;

const payoutValidator = schema.tables.payouts.validator.extend({
  _id: v.id("payouts"),
  _creationTime: v.number(),
});
const executionContextValidator = v.object({
  payout: payoutValidator,
  stripeAccountId: v.string(),
  fallbackPaymentIntentId: v.optional(v.string()),
});
const payoutSummaryValidator = v.object({
  _id: v.id("payouts"),
  kind: v.union(v.literal("completion"), v.literal("forfeit")),
  amountMinor: v.number(),
  currency: v.string(),
  status: payoutStatusValidator,
  scheduledFor: v.number(),
  paidAt: v.optional(v.number()),
  holdReason: v.optional(payoutHoldReasonValidator),
});

export async function schedulePayoutsForBooking(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
): Promise<void> {
  const records = (await paymentRecordsForBooking(ctx, booking._id)).filter(
    (record) => record.status === "paid",
  );
  if (records.length === 0) return;

  const totalPaidMinor = records.reduce(
    (sum, record) => sum + record.amountMinor,
    0,
  );
  const now = Date.now();
  const scheduledFor = (booking.completedAt ?? now) + PAYOUT_DELAY_MS;
  let remaining = booking.artistNetMinor;
  for (const [index, record] of records.entries()) {
    // The last charge absorbs rounding so the shares sum to the snapshotted net.
    const amountMinor =
      index === records.length - 1
        ? remaining
        : Math.floor(
            (booking.artistNetMinor * record.amountMinor) / totalPaidMinor +
              0.5,
          );
    remaining -= amountMinor;
    const payoutId = await ctx.db.insert("payouts", {
      bookingId: booking._id,
      bandId: booking.bandId,
      amountMinor,
      currency: booking.currency,
      status: "scheduled",
      scheduledFor,
      attempt: 0,
      kind: "completion",
      paymentRecordId: record._id,
      sourceChargeId: record.stripeChargeId,
      createdAt: now,
      updatedAt: now,
    });
    await ctx.scheduler.runAt(scheduledFor, internal.payouts.releasePayout, {
      payoutId,
    });
  }
}

async function emailPayoutSetupRequired(
  ctx: MutationCtx,
  booking: Doc<"bookings">,
): Promise<void> {
  const members = await ctx.db
    .query("bandMembers")
    .withIndex("by_band", (q) => q.eq("bandId", booking.bandId))
    .collect();
  for (const member of members) {
    if (member.role !== "admin") continue;
    const user = await ctx.db.get(member.userId);
    const to = user?.email.trim();
    if (!to) continue;
    await ctx.scheduler.runAfter(0, internal.emails.send, {
      kind: "bookingConfirmed",
      to,
      subject: "Payout on hold",
      text: `The payout for booking ${booking._id} is on hold. Finish your band's Stripe Express payout setup in EarPlug to receive it.`,
    });
  }
}

async function releaseOrHold(
  ctx: MutationCtx,
  payoutId: Id<"payouts">,
): Promise<void> {
  const payout = await ctx.db.get(payoutId);
  if (!payout || (payout.status !== "scheduled" && payout.status !== "held")) {
    return;
  }
  const booking = await ctx.db.get(payout.bookingId);
  if (!booking) throw new Error("Booking not found");
  const reasons = booking.payoutHoldReasons ?? [];
  const account = await ctx.db
    .query("bandPayoutAccounts")
    .withIndex("by_bandId", (q) => q.eq("bandId", payout.bandId))
    .unique();
  const accountReady = account?.payoutsEnabled === true;
  const now = Date.now();
  if (reasons.length > 0 || !accountReady) {
    const holdReason = reasons.includes("dispute")
      ? "dispute"
      : reasons.includes("unpaid_installment")
        ? "unpaid_installment"
        : reasons.includes("admin")
          ? "admin"
          : "no_payout_account";
    const wasAlreadyHeld = payout.status === "held";
    if (!wasAlreadyHeld) assertPayoutTransition(payout.status, "held");
    await ctx.db.patch(payoutId, {
      status: "held",
      holdReason,
      attempt: payout.attempt + 1,
      updatedAt: now,
    });
    if (now - payout.createdAt < HELD_PAYOUT_MAX_DAYS * 24 * 60 * 60 * 1000) {
      const scheduledFor = now + HELD_PAYOUT_RETRY_MS;
      await ctx.db.patch(payoutId, { scheduledFor });
      await ctx.scheduler.runAt(scheduledFor, internal.payouts.releasePayout, {
        payoutId,
      });
    }
    if (!wasAlreadyHeld && holdReason === "no_payout_account") {
      await emailPayoutSetupRequired(ctx, booking);
    }
    return;
  }

  assertPayoutTransition(payout.status, "processing");
  await ctx.db.patch(payoutId, { status: "processing", updatedAt: now });
  await ctx.scheduler.runAfter(0, internal.payouts.executePayout, {
    payoutId,
    attempt: payout.attempt,
  });
}

export const releasePayout = internalMutation({
  args: { payoutId: v.id("payouts") },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    await releaseOrHold(ctx, args.payoutId);
    return null;
  },
});

export const loadExecutionContext = internalQuery({
  args: { payoutId: v.id("payouts") },
  returns: executionContextValidator,
  handler: async (ctx, args) => {
    const payout = await ctx.db.get(args.payoutId);
    if (!payout) throw new Error("Payout not found");
    const account = await ctx.db
      .query("bandPayoutAccounts")
      .withIndex("by_bandId", (q) => q.eq("bandId", payout.bandId))
      .unique();
    if (!account) throw new Error("Band payout account not found");
    const record =
      payout.sourceChargeId === undefined && payout.paymentRecordId
        ? await ctx.db.get(payout.paymentRecordId)
        : null;
    return {
      payout,
      stripeAccountId: account.stripeAccountId,
      fallbackPaymentIntentId: record?.stripePaymentIntentId,
    };
  },
});

export const executePayout = internalAction({
  args: { payoutId: v.id("payouts"), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    try {
      const context: Infer<typeof executionContextValidator> =
        await ctx.runQuery(internal.payouts.loadExecutionContext, {
          payoutId: args.payoutId,
        });
      const { payout, stripeAccountId, fallbackPaymentIntentId } = context;
      let sourceChargeId = payout.sourceChargeId;
      if (sourceChargeId === undefined && fallbackPaymentIntentId) {
        const intent = await stripeRequest<{ latest_charge?: string | null }>(
          "GET",
          `/v1/payment_intents/${fallbackPaymentIntentId}`,
        );
        sourceChargeId = intent.latest_charge ?? undefined;
      }
      if (!sourceChargeId) {
        await ctx.runMutation(internal.payouts.markPayoutFailed, {
          payoutId: args.payoutId,
          error: "No source charge found for this payout's payment record",
          attempt: args.attempt,
        });
        return null;
      }
      const transfer = await stripeRequest<{ id: string }>(
        "POST",
        "/v1/transfers",
        {
          amount: payout.amountMinor,
          currency: payout.currency,
          destination: stripeAccountId,
          source_transaction: sourceChargeId,
          transfer_group: payout.bookingId,
          metadata: {
            bookingId: payout.bookingId,
            payoutId: payout._id,
            paymentRecordId: payout.paymentRecordId,
          },
        },
        {
          idempotencyKey: stripeIdempotencyKey(
            "payout",
            payout._id,
            args.attempt,
          ),
        },
      );
      await ctx.runMutation(internal.payouts.markPayoutPaid, {
        payoutId: args.payoutId,
        transferId: transfer.id,
      });
    } catch (error) {
      await ctx.runMutation(internal.payouts.markPayoutFailed, {
        payoutId: args.payoutId,
        error: error instanceof StripeApiError ? error.message : String(error),
        attempt: args.attempt,
      });
    }
    return null;
  },
});

export const markPayoutPaid = internalMutation({
  args: { payoutId: v.id("payouts"), transferId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const payout = await ctx.db.get(args.payoutId);
    if (!payout || payout.status === "paid") return null;
    assertPayoutTransition(payout.status, "paid");
    const now = Date.now();
    await ctx.db.patch(payout._id, {
      status: "paid",
      stripeTransferId: args.transferId,
      paidAt: now,
      releasedAt: now,
      updatedAt: now,
    });
    const booking = await ctx.db.get(payout.bookingId);
    if (!booking) throw new Error("Booking not found");
    await appendLedgerEntry(ctx, {
      idempotencyKey: `payout:${args.transferId}`,
      kind: "payout",
      amountMinor: -payout.amountMinor,
      currency: payout.currency,
      fundsState: "paid",
      bandId: payout.bandId,
      bookingId: payout.bookingId,
      occurredAt: now,
    });
    await appendLedgerEntry(ctx, {
      idempotencyKey: `commission:${payout.bookingId}`,
      kind: "commission",
      amountMinor: booking.commissionMinor,
      currency: booking.currency,
      fundsState: "available",
      bandId: booking.bandId,
      organizationId: booking.organizationId,
      bookingId: payout.bookingId,
      occurredAt: now,
    });
    const bookingPayouts = await ctx.db
      .query("payouts")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", payout.bookingId))
      .take(50);
    if (
      bookingPayouts.every((row) => row.status === "paid") &&
      booking.status === "completed"
    ) {
      assertBookingTransition("completed", "paid");
      await ctx.db.patch(booking._id, {
        status: "paid",
        revision: booking.revision + 1,
        updatedAt: now,
      });
      console.log(`Booking ${booking._id} fully paid out`);
    }
    return null;
  },
});

export const markPayoutFailed = internalMutation({
  args: { payoutId: v.id("payouts"), error: v.string(), attempt: v.number() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const payout = await ctx.db.get(args.payoutId);
    if (!payout || payout.status !== "processing") return null;
    assertPayoutTransition("processing", "failed");
    const now = Date.now();
    await ctx.db.patch(payout._id, {
      status: "failed",
      error: args.error,
      updatedAt: now,
    });
    if (args.attempt < 2) {
      assertPayoutTransition("failed", "scheduled");
      const scheduledFor = now + HELD_PAYOUT_RETRY_MS;
      await ctx.db.patch(payout._id, {
        status: "scheduled",
        scheduledFor,
        attempt: args.attempt + 1,
        updatedAt: now,
      });
      await ctx.scheduler.runAt(scheduledFor, internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
    }
    return null;
  },
});

export const retryHeldPayouts = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx): Promise<null> => {
    const heldPayouts = await ctx.db
      .query("payouts")
      .withIndex("by_status_and_scheduledFor", (q) => q.eq("status", "held"))
      .order("asc")
      .take(100);
    for (const payout of heldPayouts) {
      await releaseOrHold(ctx, payout._id);
    }
    return null;
  },
});

function toPayoutSummary(
  payout: Doc<"payouts">,
): Infer<typeof payoutSummaryValidator> {
  return {
    _id: payout._id,
    kind: payout.kind,
    amountMinor: payout.amountMinor,
    currency: payout.currency,
    status: payout.status,
    scheduledFor: payout.scheduledFor,
    paidAt: payout.paidAt,
    holdReason: payout.holdReason,
  };
}

export const payoutsForBooking = query({
  args: { bookingId: v.id("bookings") },
  returns: v.array(payoutSummaryValidator),
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) return [];
    const user = await currentUser(ctx);
    if (!user) return [];
    const [membership, bandMembership, platformAdmin] = await Promise.all([
      organizationMembershipFor(ctx, booking.organizationId, user._id),
      ctx.db
        .query("bandMembers")
        .withIndex("by_band_user", (q) =>
          q.eq("bandId", booking.bandId).eq("userId", user._id),
        )
        .unique(),
      isPlatformAdmin(ctx, user._id),
    ]);
    if (!membership && bandMembership?.role !== "admin" && !platformAdmin)
      return [];
    const rows = await ctx.db
      .query("payouts")
      .withIndex("by_bookingId", (q) => q.eq("bookingId", args.bookingId))
      .take(50);
    return rows.map(toPayoutSummary);
  },
});

export const payoutsForBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(payoutSummaryValidator),
  handler: async (ctx, args) => {
    await requireBandRole(ctx, args.bandId, { role: "admin" });
    const rows = await ctx.db
      .query("payouts")
      .withIndex("by_bandId", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .take(100);
    return rows.map(toPayoutSummary);
  },
});
