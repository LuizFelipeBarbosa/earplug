// Future handlers: charge.dispute.created, charge.dispute.closed,
// charge.dispute.funds_withdrawn, charge.dispute.funds_reinstated.
import type { StripeHandlerMap } from "../stripeWebhook";

export const disputeHandlers: StripeHandlerMap = {};
