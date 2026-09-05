import type { StripeHandlerMap } from "../stripeWebhook";
import { syncStripeAccount } from "../lib/stripeAccountSync";

export const accountHandlers: StripeHandlerMap = {
  "account.updated": async (ctx, event) => {
    await syncStripeAccount(
      ctx,
      event.data.object as Parameters<typeof syncStripeAccount>[1],
    );
  },
};
