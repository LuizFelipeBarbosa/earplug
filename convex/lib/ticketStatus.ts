import { v, type Infer } from "convex/values";
import { canTransition } from "./bookingStatus";

export const ticketOrderStatusValidator = v.union(
  v.literal("reserved"),
  v.literal("checkout_open"),
  v.literal("paid"),
  v.literal("expired"),
  v.literal("cancelled"),
  v.literal("refunded"),
);

export const ticketStatusValidator = v.union(
  v.literal("valid"),
  v.literal("used"),
  v.literal("refunded"),
  v.literal("cancelled"),
);

export const ticketRefundReasonValidator = v.union(
  v.literal("event_cancelled"),
  v.literal("late_payment"),
  v.literal("admin"),
  v.literal("dashboard"),
);

export const ticketRefundStatusValidator = v.union(
  v.literal("pending"),
  v.literal("succeeded"),
  v.literal("failed"),
);

export type TicketOrderStatus = Infer<typeof ticketOrderStatusValidator>;
export type TicketStatus = Infer<typeof ticketStatusValidator>;
export type TicketRefundReason = Infer<typeof ticketRefundReasonValidator>;
export type TicketRefundStatus = Infer<typeof ticketRefundStatusValidator>;

export const TICKET_ORDER_TRANSITIONS: Record<
  TicketOrderStatus,
  readonly TicketOrderStatus[]
> = {
  reserved: ["checkout_open", "expired", "cancelled"],
  checkout_open: ["paid", "reserved", "expired", "cancelled"],
  paid: ["refunded"],
  expired: [],
  cancelled: [],
  refunded: [],
};

export const TICKET_TRANSITIONS: Record<
  TicketStatus,
  readonly TicketStatus[]
> = {
  valid: ["used", "refunded", "cancelled"],
  used: ["refunded"],
  refunded: [],
  cancelled: [],
};

export const TICKET_REFUND_TRANSITIONS: Record<
  TicketRefundStatus,
  readonly TicketRefundStatus[]
> = {
  pending: ["succeeded", "failed"],
  failed: ["pending"],
  succeeded: [],
};

export function assertTicketOrderTransition(
  from: TicketOrderStatus,
  to: TicketOrderStatus,
): void {
  if (!canTransition(TICKET_ORDER_TRANSITIONS, from, to)) {
    throw new Error(`Invalid ticket order transition: ${from} → ${to}`);
  }
}

export function assertTicketTransition(
  from: TicketStatus,
  to: TicketStatus,
): void {
  if (!canTransition(TICKET_TRANSITIONS, from, to)) {
    throw new Error(`Invalid ticket transition: ${from} → ${to}`);
  }
}

export function assertTicketRefundTransition(
  from: TicketRefundStatus,
  to: TicketRefundStatus,
): void {
  if (!canTransition(TICKET_REFUND_TRANSITIONS, from, to)) {
    throw new Error(`Invalid ticket refund transition: ${from} → ${to}`);
  }
}

export const TICKET_TOKEN_PREFIX = "earplug:ticket:v2:";
