import type { Infer } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type {
  bookingStatusValidator,
  paymentRecordStatusValidator,
} from "../schema";

export function ticketTotals(
  orders: Array<{
    status: Extract<Doc<"ticketOrders">["status"], "paid" | "refunded">;
    subtotalMinor: number;
    feeMinor: number;
    totalMinor: number;
    refundedMinor: number;
  }>,
): {
  ordersPaid: number;
  grossMinor: number;
  feeMinor: number;
  refundedMinor: number;
  refundedOrgMinor: number;
  netMinor: number;
  estimatedProcessingMinor: number;
} {
  const totals = {
    ordersPaid: 0,
    grossMinor: 0,
    feeMinor: 0,
    refundedMinor: 0,
    refundedOrgMinor: 0,
    netMinor: 0,
    estimatedProcessingMinor: 0,
  };
  for (const order of orders) {
    totals.grossMinor += order.subtotalMinor;
    totals.feeMinor += order.feeMinor;
    totals.refundedMinor += order.refundedMinor;
    // Buyer refunds include fees; only the organizer's share reduces its net.
    totals.refundedOrgMinor +=
      order.totalMinor === 0
        ? 0
        : Math.round(
            (order.refundedMinor * order.subtotalMinor) / order.totalMinor,
          );
    if (order.status === "paid") {
      totals.ordersPaid += 1;
    }
    if (order.status === "paid" || order.status === "refunded") {
      totals.estimatedProcessingMinor +=
        Math.round(order.totalMinor * 0.029) + 30;
    }
  }
  totals.netMinor = totals.grossMinor - totals.refundedOrgMinor;
  return totals;
}

export function bookingTotals(
  records: Array<{
    record: {
      status: Infer<typeof paymentRecordStatusValidator>;
      amountMinor: number;
      refundedMinor: number;
      disputedMinor?: number;
    };
    bookingStatus: Infer<typeof bookingStatusValidator>;
  }>,
): {
  dueMinor: number;
  paidMinor: number;
  refundedMinor: number;
  disputedMinor: number;
} {
  const totals = {
    dueMinor: 0,
    paidMinor: 0,
    refundedMinor: 0,
    disputedMinor: 0,
  };
  for (const { record, bookingStatus } of records) {
    if (
      (record.status === "pending" || record.status === "checkout_open") &&
      (bookingStatus === "awaiting_payment" || bookingStatus === "confirmed")
    ) {
      totals.dueMinor += record.amountMinor;
    }
    if (
      record.status === "paid" ||
      record.status === "partially_refunded" ||
      record.status === "refunded"
    ) {
      totals.paidMinor += record.amountMinor;
    }
    totals.refundedMinor += record.refundedMinor;
    totals.disputedMinor += record.disputedMinor ?? 0;
  }
  return totals;
}

export function organizationLedgerAmount(entry: {
  kind: string;
  amountMinor: number;
  bookingId?: Id<"bookings">;
  ticketOrderId?: Id<"ticketOrders">;
}): number | null {
  switch (entry.kind) {
    case "charge":
      return -entry.amountMinor;
    case "refund":
      // Mirrors charge: stored negative refunds credit the organization.
      return -entry.amountMinor;
    case "ticket_sale":
      return entry.amountMinor;
    case "ticket_fee":
      // Positive fees debit the organization; negative fees refund that debit.
      return -entry.amountMinor;
    case "ticket_refund":
      // Already signed from the organization's perspective.
      return entry.amountMinor;
    case "dispute_hold":
    case "dispute_release":
    case "dispute_loss":
      // Booking disputes reverse the organizer's charge; ticket disputes keep
      // the stored sign. A booking takes precedence when both IDs are present.
      return entry.bookingId ? -entry.amountMinor : entry.amountMinor;
    default:
      // Platform/band events and unknown kinds are hidden from organizers.
      return null;
  }
}

export function ledgerLabel(
  kind: string,
  context: { opportunityTitle?: string; gigTitle?: string },
): string {
  switch (kind) {
    case "charge":
      return context.opportunityTitle
        ? `Booking payment · ${context.opportunityTitle}`
        : "Booking payment";
    case "refund":
      return context.opportunityTitle
        ? `Booking refund · ${context.opportunityTitle}`
        : "Booking refund";
    case "ticket_sale":
      return context.gigTitle
        ? `Ticket sale · ${context.gigTitle}`
        : "Ticket sale";
    case "ticket_fee":
      return context.gigTitle
        ? `EarPlug fee · ${context.gigTitle}`
        : "EarPlug fee";
    case "ticket_refund":
      return context.gigTitle
        ? `Ticket refund · ${context.gigTitle}`
        : "Ticket refund";
    case "dispute_hold":
      return `Dispute hold · ${context.opportunityTitle ?? context.gigTitle ?? "transaction"}`;
    case "dispute_release":
      return `Dispute release · ${context.opportunityTitle ?? context.gigTitle ?? "transaction"}`;
    case "dispute_loss":
      return `Dispute loss · ${context.opportunityTitle ?? context.gigTitle ?? "transaction"}`;
    default:
      return kind;
  }
}
