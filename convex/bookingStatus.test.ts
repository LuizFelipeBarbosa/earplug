import {
  BOOKING_TRANSITIONS,
  assertBookingTransition,
  canTransition,
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
