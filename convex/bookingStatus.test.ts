import { describe, expect, test } from "vitest";
import {
  BOOKING_ACTIVE_STATUSES,
  BOOKING_LIVE_STATUSES,
  BOOKING_TRANSITIONS,
  COMPLETION_DELAY_MS,
  OFFER_TTL_MS,
  REVIEW_WINDOW_MS,
  assertBookingTransition,
  canTransition,
  isTerminalBookingStatus,
  type BookingStatus,
} from "./lib/bookingStatus";

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
  "Booking",
  BOOKING_TRANSITIONS,
  assertBookingTransition,
  {
    offer_sent: ["artist_accepted", "declined", "expired", "withdrawn"],
    artist_accepted: ["confirmed", "awaiting_payment", "withdrawn"],
    awaiting_payment: [
      "confirmed",
      "cancelled_by_organizer",
      "cancelled_by_artist",
      "expired",
      "withdrawn",
    ],
    confirmed: [
      "completed",
      "cancelled_by_organizer",
      "cancelled_by_artist",
      "force_majeure",
      "disputed",
    ],
    completed: ["paid", "disputed", "force_majeure"],
    paid: ["disputed", "refunded", "force_majeure"],
    disputed: ["confirmed", "completed", "paid", "refunded", "force_majeure"],
    refunded: [],
    cancelled_by_organizer: [],
    cancelled_by_artist: [],
    force_majeure: [],
    declined: [],
    expired: [],
    withdrawn: [],
  },
);

test("only statuses without outgoing transitions are terminal", () => {
  for (const status of Object.keys(BOOKING_TRANSITIONS) as BookingStatus[]) {
    expect(isTerminalBookingStatus(status)).toBe(
      BOOKING_TRANSITIONS[status].length === 0,
    );
  }
});

test("booking active statuses have the expected order", () => {
  expect(BOOKING_ACTIVE_STATUSES).toEqual([
    "offer_sent",
    "artist_accepted",
    "awaiting_payment",
    "confirmed",
    "completed",
    "paid",
    "disputed",
  ]);
});

test("booking live statuses have the expected order", () => {
  expect(BOOKING_LIVE_STATUSES).toEqual(["confirmed", "completed", "paid"]);
});

test("booking deadlines use the expected durations", () => {
  expect(OFFER_TTL_MS).toBe(72 * 60 * 60 * 1000);
  expect(COMPLETION_DELAY_MS).toBe(6 * 60 * 60 * 1000);
  expect(REVIEW_WINDOW_MS).toBe(14 * 24 * 60 * 60 * 1000);
});
