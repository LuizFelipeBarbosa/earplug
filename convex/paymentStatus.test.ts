import { expect, test } from "vitest";
import { canTransition } from "./lib/bookingStatus";
import {
  AUTO_CANCEL_GRACE_MS,
  CHECKOUT_TTL_MS,
  DEFAULT_PAYMENT_DUE_MS,
  HELD_PAYOUT_MAX_DAYS,
  HELD_PAYOUT_RETRY_MS,
  PAYMENT_OPEN_STATUSES,
  PAYMENT_RECORD_TRANSITIONS,
  PAYMENT_REMINDER_LEAD_MS,
  PAYOUT_DELAY_MS,
  PAYOUT_TRANSITIONS,
  REFUND_TRANSITIONS,
  assertPaymentRecordTransition,
  assertPayoutTransition,
  assertRefundTransition,
} from "./lib/paymentStatus";
import { expectStatusTransitions } from "./statusTransitions.test-helpers";

expectStatusTransitions({
  entity: "Payment",
  table: PAYMENT_RECORD_TRANSITIONS,
  canTransition,
  assertTransition: assertPaymentRecordTransition,
  expected: {
    pending: ["checkout_open", "expired"],
    checkout_open: ["paid", "failed", "expired", "pending"],
    failed: ["checkout_open", "pending", "expired", "paid"],
    expired: ["checkout_open", "pending", "paid"],
    paid: ["partially_refunded", "refunded"],
    partially_refunded: ["refunded", "partially_refunded"],
    refunded: [],
  },
});

expectStatusTransitions({
  entity: "Payout",
  table: PAYOUT_TRANSITIONS,
  canTransition,
  assertTransition: assertPayoutTransition,
  expected: {
    scheduled: ["processing", "held", "reversed"],
    held: ["scheduled", "processing", "reversed"],
    processing: ["paid", "failed"],
    failed: ["scheduled", "held"],
    paid: ["reversed"],
    reversed: [],
  },
});

expectStatusTransitions({
  entity: "Refund",
  table: REFUND_TRANSITIONS,
  canTransition,
  assertTransition: assertRefundTransition,
  expected: {
    pending: ["succeeded", "failed"],
    failed: ["pending"],
    succeeded: [],
  },
});

test("payment open statuses have the expected order", () => {
  expect(PAYMENT_OPEN_STATUSES).toEqual([
    "pending",
    "checkout_open",
    "failed",
    "expired",
  ]);
});

test("payment and payout deadlines use the expected durations", () => {
  expect(CHECKOUT_TTL_MS).toBe(2_100_000);
  expect(PAYMENT_REMINDER_LEAD_MS).toBe(86_400_000);
  expect(AUTO_CANCEL_GRACE_MS).toBe(172_800_000);
  expect(DEFAULT_PAYMENT_DUE_MS).toBe(172_800_000);
  expect(PAYOUT_DELAY_MS).toBe(86_400_000);
  expect(HELD_PAYOUT_RETRY_MS).toBe(86_400_000);
  expect(HELD_PAYOUT_MAX_DAYS).toBe(30);
});
