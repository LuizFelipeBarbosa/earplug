import type { Infer } from "convex/values";
import {
  bookingCancelledByValidator,
  cancellationTemplateValidator,
} from "../schema";

export type CancellationTemplate = Infer<typeof cancellationTemplateValidator>;
export type BookingCancelledBy = Infer<typeof bookingCancelledByValidator>;

export function refundShareBps(
  template: CancellationTemplate,
  msBeforeStart: number,
): number {
  switch (template) {
    case "flexible":
      return msBeforeStart > 48 * 60 * 60 * 1000 ? 10_000 : 0;
    case "standard":
      if (msBeforeStart > 14 * 24 * 60 * 60 * 1000) return 10_000;
      return msBeforeStart > 7 * 24 * 60 * 60 * 1000 ? 5000 : 0;
    case "strict":
      return msBeforeStart > 14 * 24 * 60 * 60 * 1000 ? 10_000 : 0;
  }
}

function roundHalfUp(minor: number): number {
  // All amounts are non-negative, so Math.round rounds exact halves up.
  return Math.round(minor);
}

// Organizer refunds apply the template share to paidMinor, rounding half up.
// Gross is reconstructed as artistNetMinor + commissionMinor; commission / gross
// is rounded to basis points, then applied to the forfeiture with half-up rounding.
// The artist receives forfeiture minus that commission, and the platform keeps
// the remainder. Other cancellation roles receive a full refund of paidMinor.
export function settleCancellation(input: {
  template: CancellationTemplate;
  msBeforeStart: number;
  cancelledBy: BookingCancelledBy;
  paidMinor: number;
  artistNetMinor: number;
  commissionMinor: number;
}): {
  refundMinor: number;
  forfeitedMinor: number;
  artistPayoutMinor: number;
  platformKeepsMinor: number;
} {
  const {
    template,
    msBeforeStart,
    cancelledBy,
    paidMinor,
    artistNetMinor,
    commissionMinor,
  } = input;
  if (cancelledBy !== "organizer") {
    return {
      refundMinor: paidMinor,
      forfeitedMinor: 0,
      artistPayoutMinor: 0,
      platformKeepsMinor: 0,
    };
  }

  const shareBps = refundShareBps(template, msBeforeStart);
  const refundMinor = Math.min(
    paidMinor,
    Math.max(0, roundHalfUp((paidMinor * shareBps) / 10_000)),
  );
  const forfeitedMinor = paidMinor - refundMinor;
  const grossMinor = artistNetMinor + commissionMinor;
  const commissionRateBps =
    grossMinor > 0 ? roundHalfUp((commissionMinor * 10_000) / grossMinor) : 0;
  const artistPayoutMinor = Math.min(
    forfeitedMinor,
    Math.max(
      0,
      forfeitedMinor - roundHalfUp((forfeitedMinor * commissionRateBps) / 10_000),
    ),
  );
  const platformKeepsMinor = forfeitedMinor - artistPayoutMinor;
  return { refundMinor, forfeitedMinor, artistPayoutMinor, platformKeepsMinor };
}

export function describeTemplate(template: CancellationTemplate): string {
  switch (template) {
    case "flexible":
      return "Full refund up until 48 hours before the show.";
    case "standard":
      return "Full refund up until 14 days before the show, 50% refund from 14 to 7 days before, no refund inside 7 days.";
    case "strict":
      return "Full refund up until 14 days before the show, no refund inside 14 days.";
  }
}
