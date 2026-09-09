import { expect, test } from "vitest";
import { canTransition } from "./lib/bookingStatus";
import {
  TICKET_ORDER_TRANSITIONS,
  TICKET_REFUND_TRANSITIONS,
  TICKET_TOKEN_PREFIX,
  TICKET_TRANSITIONS,
  assertTicketOrderTransition,
  assertTicketRefundTransition,
  assertTicketTransition,
} from "./lib/ticketStatus";
import { expectStatusTransitions } from "./statusTransitions.test-helpers";

const ticketTransitionStyle = {
  arrow: "→",
  buildErrorMessage: (entity: string, from: string, to: string) =>
    `Invalid ${entity} transition: ${from} → ${to}`,
};

expectStatusTransitions({
  ...ticketTransitionStyle,
  entity: "ticket order",
  table: TICKET_ORDER_TRANSITIONS,
  canTransition,
  assertTransition: assertTicketOrderTransition,
  expected: {
    reserved: ["checkout_open", "expired", "cancelled"],
    checkout_open: ["paid", "reserved", "expired", "cancelled"],
    paid: ["refunded"],
    expired: [],
    cancelled: [],
    refunded: [],
  },
});

expectStatusTransitions({
  ...ticketTransitionStyle,
  entity: "ticket",
  table: TICKET_TRANSITIONS,
  canTransition,
  assertTransition: assertTicketTransition,
  expected: {
    valid: ["used", "refunded", "cancelled"],
    used: ["refunded"],
    refunded: [],
    cancelled: [],
  },
});

expectStatusTransitions({
  ...ticketTransitionStyle,
  entity: "ticket refund",
  table: TICKET_REFUND_TRANSITIONS,
  canTransition,
  assertTransition: assertTicketRefundTransition,
  expected: {
    pending: ["succeeded", "failed"],
    failed: ["pending"],
    succeeded: [],
  },
});

test("ticket tokens use the exact versioned prefix", () => {
  expect(TICKET_TOKEN_PREFIX).toBe("earplug:ticket:v2:");
});
