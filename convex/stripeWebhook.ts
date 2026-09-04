import { v } from "convex/values";
import { internal } from "./_generated/api";
import { env, httpAction, internalMutation } from "./_generated/server";
import { deploymentName, PRODUCTION_DEPLOYMENT } from "./lib/env";
import { verifyStripeSignature } from "./lib/stripeSignature";

export const record = internalMutation({
  args: {
    eventId: v.string(),
    type: v.string(),
    account: v.optional(v.string()),
    livemode: v.boolean(),
    receivedAt: v.number(),
    error: v.optional(v.string()),
  },
  returns: v.object({
    outcome: v.union(v.literal("recorded"), v.literal("duplicate")),
  }),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("stripeEvents")
      .withIndex("by_eventId", (query) => query.eq("eventId", args.eventId))
      .first();
    if (existing !== null) return { outcome: "duplicate" as const };

    await ctx.db.insert("stripeEvents", {
      eventId: args.eventId,
      type: args.type,
      account: args.account,
      livemode: args.livemode,
      receivedAt: args.receivedAt,
      appliedAt: args.receivedAt,
      status: "ignored",
      error: args.error,
    });
    return { outcome: "recorded" as const };
  },
});

export function stripeWebhookHandler(
  kind: "platform" | "connect",
): ReturnType<typeof httpAction> {
  return httpAction(async (ctx, request) => {
    const secret =
      kind === "platform"
        ? env.STRIPE_WEBHOOK_SECRET
        : env.STRIPE_CONNECT_WEBHOOK_SECRET;
    if (!secret) {
      console.error(`stripe-webhook ${kind} secret_not_configured`);
      return new Response("webhook secret not configured", { status: 500 });
    }

    const payload = await request.text();
    const header = request.headers.get("stripe-signature");
    const verification = await verifyStripeSignature({
      payload,
      header,
      secret,
      nowSeconds: Math.floor(Date.now() / 1000),
    });
    if (verification !== "ok") {
      return new Response(verification, { status: 400 });
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(payload) as unknown;
    } catch {
      return new Response("invalid event", { status: 400 });
    }
    if (typeof parsed !== "object" || parsed === null) {
      return new Response("invalid event", { status: 400 });
    }

    const event = parsed as Record<string, unknown>;
    if (
      typeof event.id !== "string" ||
      !event.id.startsWith("evt_") ||
      typeof event.type !== "string" ||
      typeof event.livemode !== "boolean"
    ) {
      return new Response("invalid event", { status: 400 });
    }
    const account =
      typeof event.account === "string" ? event.account : undefined;
    const expectedLivemode = deploymentName() === PRODUCTION_DEPLOYMENT;
    const livemodeMismatch = event.livemode !== expectedLivemode;

    try {
      const { outcome }: { outcome: "recorded" | "duplicate" } =
        await ctx.runMutation(internal.stripeWebhook.record, {
          eventId: event.id,
          type: event.type,
          account,
          livemode: event.livemode,
          receivedAt: Date.now(),
          error: livemodeMismatch ? "livemode mismatch" : undefined,
        });
      console.log(
        `stripe-webhook ${kind} ${event.id} ${event.type} ${outcome}`,
      );
      return new Response(livemodeMismatch ? "ignored-livemode" : outcome, {
        status: 200,
      });
    } catch {
      console.error(
        `stripe-webhook ${kind} ${event.id} ${event.type} mutation_failed`,
      );
      return new Response("webhook mutation failed", { status: 500 });
    }
  });
}

export const handlePlatformWebhook = stripeWebhookHandler("platform");
export const handleConnectWebhook = stripeWebhookHandler("connect");
