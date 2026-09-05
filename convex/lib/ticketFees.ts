import { bpsSetting, minorSetting } from "./env";

export type TicketingFee = { bps: number; fixedMinor: number };

export function resolveTicketingFee(organization: {
  ticketingFeeBps?: number;
  ticketingFeeFixedMinor?: number;
}): TicketingFee {
  const { ticketingFeeBps, ticketingFeeFixedMinor } = organization;
  // Invalid overrides are hard errors, even when the pair is incomplete.
  if (
    (ticketingFeeBps !== undefined &&
      (!Number.isInteger(ticketingFeeBps) ||
        ticketingFeeBps < 0 ||
        ticketingFeeBps > 10_000)) ||
    (ticketingFeeFixedMinor !== undefined &&
      (!Number.isInteger(ticketingFeeFixedMinor) || ticketingFeeFixedMinor < 0))
  ) {
    throw new Error("Ticketing fee is not configured");
  }

  if (ticketingFeeBps !== undefined && ticketingFeeFixedMinor !== undefined) {
    return { bps: ticketingFeeBps, fixedMinor: ticketingFeeFixedMinor };
  }

  // An incomplete override uses both environment settings, never a mixed pair.
  const bps = bpsSetting("TICKETING_FEE_BPS", -1);
  const fixedMinor = minorSetting("TICKETING_FEE_FIXED_MINOR");
  if (bps === -1 || fixedMinor === undefined) {
    throw new Error("Ticketing fee is not configured");
  }
  return { bps, fixedMinor };
}

export function unitFeeMinor(unitPriceMinor: number, fee: TicketingFee): number {
  if (!Number.isInteger(unitPriceMinor) || unitPriceMinor < 0) {
    throw new Error("Unit price must be a non-negative integer");
  }
  if (!Number.isInteger(fee.bps) || fee.bps < 0 || fee.bps > 10_000) {
    throw new Error("Ticketing fee must be an integer between 0 and 10000 basis points");
  }
  if (!Number.isInteger(fee.fixedMinor) || fee.fixedMinor < 0) {
    throw new Error("Fixed ticketing fee must be a non-negative integer");
  }

  if (unitPriceMinor === 0) return 0;
  return Math.round((unitPriceMinor * fee.bps) / 10_000) + fee.fixedMinor;
}

export function orderTotals(args: {
  unitPriceMinor: number;
  quantity: number;
  fee: TicketingFee;
}): {
  unitFeeMinor: number;
  subtotalMinor: number;
  feeMinor: number;
  totalMinor: number;
} {
  const { unitPriceMinor, quantity, fee } = args;
  if (!Number.isInteger(quantity) || quantity <= 0) {
    throw new Error("Quantity must be a positive integer");
  }

  const feePerUnitMinor = unitFeeMinor(unitPriceMinor, fee);
  const subtotalMinor = unitPriceMinor * quantity;
  const feeMinor = feePerUnitMinor * quantity;
  const totalMinor = subtotalMinor + feeMinor;
  return { unitFeeMinor: feePerUnitMinor, subtotalMinor, feeMinor, totalMinor };
}
