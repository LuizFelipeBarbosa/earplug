import type { Infer } from "convex/values";
import {
  paymentRecordStatusValidator,
  payoutStatusValidator,
  refundStatusValidator,
} from "../schema";
import { canTransition } from "./bookingStatus";

export type PaymentRecordStatus = Infer<typeof paymentRecordStatusValidator>;
export type PayoutStatus = Infer<typeof payoutStatusValidator>;
export type RefundStatus = Infer<typeof refundStatusValidator>;

export const PAYMENT_RECORD_TRANSITIONS: Record<
  PaymentRecordStatus,
  readonly PaymentRecordStatus[]
> = {
  pending: ["checkout_open", "expired"],
  checkout_open: ["paid", "failed", "expired", "pending"],
  failed: ["checkout_open", "pending"],
  expired: ["checkout_open", "pending"],
  paid: ["partially_refunded", "refunded"],
  partially_refunded: ["refunded", "partially_refunded"],
  refunded: [],
};

export const PAYOUT_TRANSITIONS: Record<
  PayoutStatus,
  readonly PayoutStatus[]
> = {
  scheduled: ["processing", "held", "reversed"],
  held: ["scheduled", "processing", "reversed"],
  processing: ["paid", "failed"],
  failed: ["scheduled", "held"],
  paid: ["reversed"],
  reversed: [],
};

export const REFUND_TRANSITIONS: Record<
  RefundStatus,
  readonly RefundStatus[]
> = {
  pending: ["succeeded", "failed"],
  failed: ["pending"],
  succeeded: [],
};

export function assertPaymentRecordTransition(
  from: PaymentRecordStatus,
  to: PaymentRecordStatus,
): void {
  if (!canTransition(PAYMENT_RECORD_TRANSITIONS, from, to)) {
    throw new Error(`Payment cannot go from ${from} to ${to}`);
  }
}

export function assertPayoutTransition(
  from: PayoutStatus,
  to: PayoutStatus,
): void {
  if (!canTransition(PAYOUT_TRANSITIONS, from, to)) {
    throw new Error(`Payout cannot go from ${from} to ${to}`);
  }
}

export function assertRefundTransition(
  from: RefundStatus,
  to: RefundStatus,
): void {
  if (!canTransition(REFUND_TRANSITIONS, from, to)) {
    throw new Error(`Refund cannot go from ${from} to ${to}`);
  }
}

export const PAYMENT_OPEN_STATUSES: readonly PaymentRecordStatus[] = [
  "pending",
  "checkout_open",
  "failed",
  "expired",
];

export const CHECKOUT_TTL_MS = 30 * 60 * 1000;
export const PAYMENT_REMINDER_LEAD_MS = 24 * 60 * 60 * 1000;
export const AUTO_CANCEL_GRACE_MS = 48 * 60 * 60 * 1000;
export const DEFAULT_PAYMENT_DUE_MS = 48 * 60 * 60 * 1000;
export const PAYOUT_DELAY_MS = 24 * 60 * 60 * 1000;
export const HELD_PAYOUT_RETRY_MS = 24 * 60 * 60 * 1000;
export const HELD_PAYOUT_MAX_DAYS = 30;
