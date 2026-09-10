import { canTransition } from "./lib/bookingStatus";
import {
  PAYMENT_RECORD_TRANSITIONS,
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
