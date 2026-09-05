import { describe, expect, test } from "vitest";
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

function testStatusTransitions<T extends string>(
  entity: string,
  table: Record<T, readonly T[]>,
  assertTransition: (from: T, to: T) => void,
  expectedTransitions: Record<T, readonly T[]>,
) {
  describe(`${entity} transitions`, () => {
    test("declares exactly the allowed edges", () => {
      expect(table).toEqual(expectedTransitions);
    });

    const statuses = Object.keys(expectedTransitions) as T[];
    for (const from of statuses) {
      if (expectedTransitions[from].length === 0) {
        test(`${from} is terminal`, () => {
          expect(table[from]).toEqual([]);
        });
      }

      for (const to of statuses) {
        test(`${from} -> ${to}`, () => {
          const allowed = expectedTransitions[from].includes(to);
          expect(canTransition(table, from, to)).toBe(allowed);

          if (allowed) {
            expect(assertTransition(from, to)).toBeUndefined();
          } else {
            expect(() => assertTransition(from, to)).toThrowError(
              expect.objectContaining({
                message: `${entity} cannot go from ${from} to ${to}`,
              }),
            );
          }
        });
      }
    }
  });
}

testStatusTransitions(
  "Payment",
  PAYMENT_RECORD_TRANSITIONS,
  assertPaymentRecordTransition,
  {
    pending: ["checkout_open", "expired"],
    checkout_open: ["paid", "failed", "expired", "pending"],
    failed: ["checkout_open", "pending"],
    expired: ["checkout_open", "pending"],
    paid: ["partially_refunded", "refunded"],
    partially_refunded: ["refunded", "partially_refunded"],
    refunded: [],
  },
);

testStatusTransitions("Payout", PAYOUT_TRANSITIONS, assertPayoutTransition, {
  scheduled: ["processing", "held", "reversed"],
  held: ["scheduled", "processing", "reversed"],
  processing: ["paid", "failed"],
  failed: ["scheduled", "held"],
  paid: ["reversed"],
  reversed: [],
});

testStatusTransitions("Refund", REFUND_TRANSITIONS, assertRefundTransition, {
  pending: ["succeeded", "failed"],
  failed: ["pending"],
  succeeded: [],
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
  expect(CHECKOUT_TTL_MS).toBe(1_800_000);
  expect(PAYMENT_REMINDER_LEAD_MS).toBe(86_400_000);
  expect(AUTO_CANCEL_GRACE_MS).toBe(172_800_000);
  expect(DEFAULT_PAYMENT_DUE_MS).toBe(172_800_000);
  expect(PAYOUT_DELAY_MS).toBe(86_400_000);
  expect(HELD_PAYOUT_RETRY_MS).toBe(86_400_000);
  expect(HELD_PAYOUT_MAX_DAYS).toBe(30);
});
