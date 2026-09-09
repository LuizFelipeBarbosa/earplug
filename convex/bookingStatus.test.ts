import { expect, test } from "vitest";
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
import { expectStatusTransitions } from "./statusTransitions.test-helpers";

expectStatusTransitions({
  entity: "Booking",
  table: BOOKING_TRANSITIONS,
  canTransition,
  assertTransition: assertBookingTransition,
  expected: {
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
});

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
