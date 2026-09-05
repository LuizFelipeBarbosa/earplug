import type { Infer } from "convex/values";
import { bookingStatusValidator } from "../schema";

export type BookingStatus = Infer<typeof bookingStatusValidator>;

export const BOOKING_TRANSITIONS: Record<
  BookingStatus,
  readonly BookingStatus[]
> = {
  offer_sent: ["artist_accepted", "declined", "expired", "withdrawn"],
  artist_accepted: ["confirmed", "awaiting_payment"],
  awaiting_payment: [
    "confirmed",
    "cancelled_by_organizer",
    "cancelled_by_artist",
    "expired",
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
};

export function canTransition<T extends string>(
  table: Record<T, readonly T[]>,
  from: T,
  to: T,
): boolean {
  return table[from]?.includes(to) ?? false;
}

export function assertBookingTransition(
  from: BookingStatus,
  to: BookingStatus,
): void {
  if (!canTransition(BOOKING_TRANSITIONS, from, to)) {
    throw new Error(`Booking cannot go from ${from} to ${to}`);
  }
}

export const BOOKING_ACTIVE_STATUSES: readonly BookingStatus[] = [
  "offer_sent",
  "artist_accepted",
  "awaiting_payment",
  "confirmed",
  "completed",
  "paid",
  "disputed",
];

// These statuses hold a slot.
export const BOOKING_LIVE_STATUSES: readonly BookingStatus[] = [
  "confirmed",
  "completed",
  "paid",
];

export function isTerminalBookingStatus(status: BookingStatus): boolean {
  return BOOKING_TRANSITIONS[status].length === 0;
}

export const OFFER_TTL_MS = 72 * 60 * 60 * 1000;
export const COMPLETION_DELAY_MS = 6 * 60 * 60 * 1000;
export const REVIEW_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
