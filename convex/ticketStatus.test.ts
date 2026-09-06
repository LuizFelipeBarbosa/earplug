import { describe, expect, test } from "vitest";
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
        test(`${from} → ${to}`, () => {
          const allowed = expectedTransitions[from].includes(to);
          expect(canTransition(table, from, to)).toBe(allowed);

          if (allowed) {
            expect(assertTransition(from, to)).toBeUndefined();
          } else {
            expect(() => assertTransition(from, to)).toThrowError(
              expect.objectContaining({
                message: `Invalid ${entity} transition: ${from} → ${to}`,
              }),
            );
          }
        });
      }
    }
  });
}

testStatusTransitions(
  "ticket order",
  TICKET_ORDER_TRANSITIONS,
  assertTicketOrderTransition,
  {
    reserved: ["checkout_open", "expired", "cancelled"],
    checkout_open: ["paid", "reserved", "expired", "cancelled"],
    paid: ["refunded"],
    expired: [],
    cancelled: [],
    refunded: [],
  },
);

testStatusTransitions("ticket", TICKET_TRANSITIONS, assertTicketTransition, {
  valid: ["used", "refunded", "cancelled"],
  used: ["refunded"],
  refunded: [],
  cancelled: [],
});

testStatusTransitions(
  "ticket refund",
  TICKET_REFUND_TRANSITIONS,
  assertTicketRefundTransition,
  {
    pending: ["succeeded", "failed"],
    failed: ["pending"],
    succeeded: [],
  },
);

test("ticket tokens use the exact versioned prefix", () => {
  expect(TICKET_TOKEN_PREFIX).toBe("earplug:ticket:v2:");
});
