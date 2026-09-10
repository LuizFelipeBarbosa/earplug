import { describe, expect, test } from "vitest";
import {
  DISPUTE_WINDOW_AFTER_COMPLETION_MS,
  assertDisputeTransition,
  disputeOpenCheck,
  disputeResolutionCheck,
  type DisputeResolution,
} from "./lib/disputeStatus";

describe("disputeOpenCheck", () => {
  const startsAt = Date.parse("2026-09-01T18:00:00Z");
  const completedAt = startsAt + 2 * 60 * 60 * 1000;
  const validInput: Parameters<typeof disputeOpenCheck>[0] = {
    side: "organizer",
    bookingStatus: "confirmed",
    grossMinor: 10_000,
    paidMinor: 8_000,
    startsAt,
    completedAt,
    hasOpenDispute: false,
    hasOpenStripeDispute: false,
    anyPayoutPaid: false,
    requestedRefundMinor: 4_000,
    now: completedAt,
  };

  test.each(["confirmed", "completed", "paid"])(
    "allows an organizer refund request for a %s booking",
    (bookingStatus) => {
      expect(disputeOpenCheck({ ...validInput, bookingStatus })).toEqual({
        ok: true,
      });
    },
  );

  test.each([false, true])(
    "allows an artist dispute without a refund when anyPayoutPaid is %s",
    (anyPayoutPaid) => {
      const { requestedRefundMinor, ...input } = validInput;
      expect(
        disputeOpenCheck({ ...input, side: "artist", anyPayoutPaid }),
      ).toEqual({ ok: true });
    },
  );

  test.each([
    "offer_sent",
    "artist_accepted",
    "awaiting_payment",
    "cancelled_by_organizer",
    "cancelled_by_artist",
    "force_majeure",
    "disputed",
    "refunded",
    "declined",
    "expired",
    "withdrawn",
    "unknown",
  ])("refuses a %s booking", (bookingStatus) => {
    expect(disputeOpenCheck({ ...validInput, bookingStatus })).toEqual({
      ok: false,
      reason: "Disputes can only be opened for confirmed, completed, or paid bookings",
    });
  });

  test.each([0, -1, Number.NaN])("refuses grossMinor %s", (grossMinor) => {
    expect(disputeOpenCheck({ ...validInput, grossMinor })).toEqual({
      ok: false,
      reason: "Disputes require a booking with a positive fee",
    });
  });

  test("refuses before the show starts", () => {
    expect(disputeOpenCheck({ ...validInput, now: startsAt - 1 })).toEqual({
      ok: false,
      reason: "Disputes can only be opened after the show starts",
    });
  });

  test("allows opening exactly when the show starts", () => {
    expect(disputeOpenCheck({ ...validInput, now: startsAt })).toEqual({
      ok: true,
    });
  });

  test("the dispute window lasts fourteen days after completion", () => {
    expect(DISPUTE_WINDOW_AFTER_COMPLETION_MS).toBe(14 * 24 * 60 * 60 * 1000);
  });

  test.each([
    { label: "recorded completion", completedAt, endOfShow: completedAt },
    {
      label: "six-hour fallback",
      completedAt: undefined,
      endOfShow: startsAt + 6 * 60 * 60 * 1000,
    },
  ])("uses $label for the inclusive dispute deadline", ({ completedAt, endOfShow }) => {
    const deadline = endOfShow + DISPUTE_WINDOW_AFTER_COMPLETION_MS;
    expect(
      disputeOpenCheck({ ...validInput, completedAt, now: deadline }),
    ).toEqual({ ok: true });
    expect(
      disputeOpenCheck({ ...validInput, completedAt, now: deadline + 1 }),
    ).toEqual({ ok: false, reason: "The dispute window has closed" });
  });

  test("uses a later recorded completion instead of the fallback", () => {
    const completedAt = startsAt + 8 * 60 * 60 * 1000;
    expect(
      disputeOpenCheck({
        ...validInput,
        completedAt,
        now: completedAt + DISPUTE_WINDOW_AFTER_COMPLETION_MS,
      }),
    ).toEqual({ ok: true });
  });

  test("refuses an existing open in-app dispute", () => {
    expect(disputeOpenCheck({ ...validInput, hasOpenDispute: true })).toEqual({
      ok: false,
      reason: "This booking already has an open dispute",
    });
  });

  test("refuses an existing open Stripe dispute", () => {
    expect(
      disputeOpenCheck({ ...validInput, hasOpenStripeDispute: true }),
    ).toEqual({
      ok: false,
      reason: "This booking already has an open Stripe dispute",
    });
  });

  test("requires an organizer refund amount", () => {
    const { requestedRefundMinor, ...input } = validInput;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "Enter the refund amount you are requesting",
    });
  });

  test("refuses a non-integer organizer refund amount", () => {
    expect(
      disputeOpenCheck({ ...validInput, requestedRefundMinor: 1.5 }),
    ).toEqual({
      ok: false,
      reason: "The refund amount must be a whole number in minor units",
    });
  });

  test("refuses an organizer refund amount outside the paid range", () => {
    expect(
      disputeOpenCheck({ ...validInput, requestedRefundMinor: 0 }),
    ).toEqual({
      ok: false,
      reason:
        "The refund amount must be positive and no more than the amount paid",
    });
  });

  test("allows organizer refund amount at the paid range boundary", () => {
    expect(
      disputeOpenCheck({ ...validInput, requestedRefundMinor: 1 }),
    ).toEqual({ ok: true });
    expect(
      disputeOpenCheck({
        ...validInput,
        requestedRefundMinor: validInput.paidMinor,
      }),
    ).toEqual({ ok: true });
  });

  test("refuses organizer refunds once any artist payout has been paid", () => {
    expect(disputeOpenCheck({ ...validInput, anyPayoutPaid: true })).toEqual({
      ok: false,
      reason: "Refund requests close once the artist has been paid",
    });
  });

  test.each([0, 1])("refuses an artist refund amount of %s", (requestedRefundMinor) => {
    expect(
      disputeOpenCheck({ ...validInput, side: "artist", requestedRefundMinor }),
    ).toEqual({ ok: false, reason: "Artists cannot request a refund" });
  });

  test("reports the first failing opening check in the specified order", () => {
    const input = {
      ...validInput,
      bookingStatus: "cancelled_by_organizer",
      grossMinor: 0,
      now: startsAt - 1,
      hasOpenDispute: true,
      hasOpenStripeDispute: true,
      requestedRefundMinor: undefined,
      anyPayoutPaid: true,
    };
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "Disputes can only be opened for confirmed, completed, or paid bookings",
    });
    input.bookingStatus = "confirmed";
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "Disputes require a booking with a positive fee",
    });
    input.grossMinor = validInput.grossMinor;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "Disputes can only be opened after the show starts",
    });
    input.now = completedAt + DISPUTE_WINDOW_AFTER_COMPLETION_MS + 1;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "The dispute window has closed",
    });
    input.now = completedAt;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "This booking already has an open dispute",
    });
    input.hasOpenDispute = false;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "This booking already has an open Stripe dispute",
    });
    input.hasOpenStripeDispute = false;
    expect(disputeOpenCheck(input)).toEqual({
      ok: false,
      reason: "Enter the refund amount you are requesting",
    });
  });
});

describe("disputeResolutionCheck", () => {
  const paidMinor = 8_000;
  const validInput = { paidMinor, hasOpenStripeDispute: false };

  describe.each(["released", "dismissed"] as const)("%s", (resolution) => {
    test.each([undefined, 0])("returns zero for refundMinor %s", (refundMinor) => {
      expect(
        disputeResolutionCheck({ ...validInput, resolution, refundMinor }),
      ).toEqual({ ok: true, refundMinor: 0 });
    });

    test("refuses a nonzero refundMinor", () => {
      expect(
        disputeResolutionCheck({ ...validInput, resolution, refundMinor: 1 }),
      ).toEqual({
        ok: false,
        reason: "Releasing or dismissing a dispute cannot include a refund",
      });
    });
  });

  test("a full refund returns the amount paid without a supplied amount", () => {
    expect(
      disputeResolutionCheck({ ...validInput, resolution: "refunded_full" }),
    ).toEqual({ ok: true, refundMinor: paidMinor });
  });

  test("a full refund derives the amount from paidMinor regardless of refundMinor", () => {
    expect(
      disputeResolutionCheck({
        ...validInput,
        resolution: "refunded_full",
        refundMinor: 4_000,
      }),
    ).toEqual({ ok: true, refundMinor: paidMinor });
  });

  test("refuses a full refund when paidMinor is not positive", () => {
    expect(
      disputeResolutionCheck({
        ...validInput,
        resolution: "refunded_full",
        paidMinor: 0,
      }),
    ).toEqual({
      ok: false,
      reason: "A full refund requires a positive amount paid",
    });
  });

  test("allows a partial refund within range", () => {
    const refundMinor = 4_000;
    expect(
      disputeResolutionCheck({
        ...validInput,
        resolution: "refunded_partial",
        refundMinor,
      }),
    ).toEqual({ ok: true, refundMinor });
  });

  test("refuses an invalid partial refund amount", () => {
    expect(
      disputeResolutionCheck({
        ...validInput,
        resolution: "refunded_partial",
        refundMinor: 0,
      }),
    ).toEqual({
      ok: false,
      reason:
        "A partial refund must be a positive whole number in minor units below the amount paid",
    });
  });

  test.each<DisputeResolution>([
    "released",
    "dismissed",
    "refunded_full",
    "refunded_partial",
  ])("refuses %s before amount checks while a Stripe dispute is open", (resolution) => {
    expect(
      disputeResolutionCheck({
        resolution,
        paidMinor: 0,
        refundMinor: -1,
        hasOpenStripeDispute: true,
      }),
    ).toEqual({
      ok: false,
      reason: "Disputes cannot be resolved while a Stripe dispute is open",
    });
  });
});

describe("Dispute transitions", () => {
  test("open -> under_review is allowed", () => {
    expect(assertDisputeTransition("open", "under_review")).toBeUndefined();
  });

  test("resolved -> open is denied", () => {
    expect(() => assertDisputeTransition("resolved", "open")).toThrowError(
      expect.objectContaining({
        message: "Dispute cannot go from resolved to open",
      }),
    );
  });
});
