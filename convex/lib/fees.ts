import type { Doc } from "../_generated/dataModel";
import { bpsSetting } from "./env";

export function resolveCommissionBps(organization: Doc<"organizations">): number {
  // An invalid override is a hard error. Only absent overrides use the env
  // setting, with -1 marking missing or invalid configuration.
  const commissionBps =
    organization.bookingCommissionBps !== undefined
      ? organization.bookingCommissionBps
      : bpsSetting("BOOKING_COMMISSION_BPS", -1);
  if (
    !Number.isInteger(commissionBps) ||
    commissionBps < 0 ||
    commissionBps > 10_000
  ) {
    throw new Error("Booking commission is not configured");
  }
  return commissionBps;
}

export function splitFee(
  grossMinor: number,
  commissionBps: number,
): {
  grossMinor: number;
  commissionBps: number;
  commissionMinor: number;
  artistNetMinor: number;
} {
  if (!Number.isInteger(grossMinor) || grossMinor < 0) {
    throw new Error("Gross fee must be a non-negative integer");
  }
  if (
    !Number.isInteger(commissionBps) ||
    commissionBps < 0 ||
    commissionBps > 10_000
  ) {
    throw new Error("Commission must be an integer between 0 and 10000 basis points");
  }

  const commissionMinor = Math.round((grossMinor * commissionBps) / 10_000);
  const artistNetMinor = grossMinor - commissionMinor;
  return { grossMinor, commissionBps, commissionMinor, artistNetMinor };
}

export function feeSnapshot(
  grossMinor: number,
  commissionBps: number,
  currency = "usd",
): {
  grossMinor: number;
  commissionBps: number;
  commissionMinor: number;
  artistNetMinor: number;
  currency: string;
} {
  return { ...splitFee(grossMinor, commissionBps), currency };
}
