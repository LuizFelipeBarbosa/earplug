import type { Infer } from "convex/values";
import type {
  disputeCategoryValidator,
  disputeResolutionValidator,
  disputeSideValidator,
  disputeStatusValidator,
} from "../schema";
import {
  BOOKING_LIVE_STATUSES,
  COMPLETION_DELAY_MS,
  canTransition,
} from "./bookingStatus";

export type DisputeSide = Infer<typeof disputeSideValidator>;
export type DisputeCategory = Infer<typeof disputeCategoryValidator>;
export type DisputeStatus = Infer<typeof disputeStatusValidator>;
export type DisputeResolution = Infer<typeof disputeResolutionValidator>;

export const DISPUTE_WINDOW_AFTER_COMPLETION_MS = 14 * 24 * 60 * 60 * 1000;

const DISPUTE_TRANSITIONS: Record<DisputeStatus, readonly DisputeStatus[]> = {
  open: ["under_review", "resolved"],
  under_review: ["resolved"],
  resolved: [],
};

export function disputeOpenCheck(input: {
  side: DisputeSide;
  bookingStatus: string;
  grossMinor: number;
  paidMinor: number;
  startsAt: number;
  completedAt?: number;
  hasOpenDispute: boolean;
  hasOpenStripeDispute: boolean;
  anyPayoutPaid: boolean;
  requestedRefundMinor?: number;
  now: number;
}): { ok: true } | { ok: false; reason: string } {
  if (!BOOKING_LIVE_STATUSES.some((status) => status === input.bookingStatus)) {
    return {
      ok: false,
      reason: "Disputes can only be opened for confirmed, completed, or paid bookings",
    };
  }
  if (!(input.grossMinor > 0)) {
    return { ok: false, reason: "Disputes require a booking with a positive fee" };
  }
  if (input.now < input.startsAt) {
    return { ok: false, reason: "Disputes can only be opened after the show starts" };
  }
  const completedAt = input.completedAt ?? input.startsAt + COMPLETION_DELAY_MS;
  if (input.now > completedAt + DISPUTE_WINDOW_AFTER_COMPLETION_MS) {
    return { ok: false, reason: "The dispute window has closed" };
  }
  if (input.hasOpenDispute) {
    return { ok: false, reason: "This booking already has an open dispute" };
  }
  if (input.hasOpenStripeDispute) {
    return { ok: false, reason: "This booking already has an open Stripe dispute" };
  }
  if (input.side === "organizer") {
    const requestedRefundMinor = input.requestedRefundMinor;
    if (requestedRefundMinor === undefined) {
      return { ok: false, reason: "Enter the refund amount you are requesting" };
    }
    if (!Number.isInteger(requestedRefundMinor)) {
      return { ok: false, reason: "The refund amount must be a whole number in minor units" };
    }
    if (!(requestedRefundMinor > 0 && requestedRefundMinor <= input.paidMinor)) {
      return { ok: false, reason: "The refund amount must be positive and no more than the amount paid" };
    }
    if (input.anyPayoutPaid) {
      return { ok: false, reason: "Refund requests close once the artist has been paid" };
    }
  } else if (input.requestedRefundMinor !== undefined) {
    return { ok: false, reason: "Artists cannot request a refund" };
  }
  return { ok: true };
}

export function disputeResolutionCheck(input: {
  resolution: DisputeResolution;
  refundMinor?: number;
  paidMinor: number;
  hasOpenStripeDispute: boolean;
}): { ok: true; refundMinor: number } | { ok: false; reason: string } {
  if (input.hasOpenStripeDispute) {
    return { ok: false, reason: "Disputes cannot be resolved while a Stripe dispute is open" };
  }
  if (input.resolution === "released" || input.resolution === "dismissed") {
    if (input.refundMinor !== undefined && input.refundMinor !== 0) {
      return { ok: false, reason: "Releasing or dismissing a dispute cannot include a refund" };
    }
    return { ok: true, refundMinor: 0 };
  }
  if (input.resolution === "refunded_full") {
    if (!(input.paidMinor > 0)) {
      return { ok: false, reason: "A full refund requires a positive amount paid" };
    }
    return { ok: true, refundMinor: input.paidMinor };
  }
  const refundMinor = input.refundMinor;
  if (
    refundMinor === undefined ||
    !Number.isInteger(refundMinor) ||
    !(refundMinor > 0 && refundMinor < input.paidMinor)
  ) {
    return { ok: false, reason: "A partial refund must be a positive whole number in minor units below the amount paid" };
  }
  return { ok: true, refundMinor };
}

export function assertDisputeTransition(
  from: DisputeStatus,
  to: DisputeStatus,
): void {
  if (!canTransition(DISPUTE_TRANSITIONS, from, to)) {
    throw new Error(`Dispute cannot go from ${from} to ${to}`);
  }
}
