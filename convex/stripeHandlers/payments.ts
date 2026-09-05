// Future handlers: checkout.session.completed, checkout.session.expired,
// payment_intent.succeeded, payment_intent.payment_failed, charge.refunded.
import type { StripeHandlerMap } from "../stripeWebhook";

export const paymentHandlers: StripeHandlerMap = {};
