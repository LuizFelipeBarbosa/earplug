import { v } from "convex/values";
import { internal } from "./_generated/api";
import { env, httpAction, internalMutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { deploymentName, PRODUCTION_DEPLOYMENT } from "./lib/env";
import { verifyStripeSignature } from "./lib/stripeSignature";
import { accountHandlers } from "./stripeHandlers/accounts";
import { paymentHandlers } from "./stripeHandlers/payments";
import { disputeHandlers } from "./stripeHandlers/disputes";

export type StripeEvent = {
  id: string;
  type: string;
  livemode: boolean;
  account?: string;
  created: number;
  data: {
    object: Record<string, any>;
    previous_attributes?: Record<string, any>;
  };
};

export type StripeEventHandler = (
  ctx: MutationCtx,
  event: StripeEvent,
) => Promise<void>;

export type StripeHandlerMap = Record<string, StripeEventHandler>;

type EventOutcome = "applied" | "ignored" | "duplicate" | "failed";

const handlers: StripeHandlerMap = Object.create(null);
for (const map of [accountHandlers, paymentHandlers, disputeHandlers]) {
  for (const [type, handler] of Object.entries(map)) {
    if (Object.hasOwn(handlers, type)) {
      throw new Error(`Duplicate Stripe handler for ${type}`);
    }
    handlers[type] = handler;
  }
}

export const markEventOutcome = internalMutation({
  args: {
    eventId: v.string(),
    type: v.string(),
    account: v.optional(v.string()),
    livemode: v.boolean(),
    receivedAt: v.number(),
    status: v.union(
      v.literal("applied"),
      v.literal("ignored"),
      v.literal("failed"),
    ),
    error: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const existing = await ctx.db
      .query("stripeEvents")
      .withIndex("by_eventId", (query) => query.eq("eventId", args.eventId))
      .unique();
    if (existing === null) {
      await ctx.db.insert("stripeEvents", {
        ...args,
        appliedAt: args.status === "failed" ? undefined : args.receivedAt,
      });
    } else {
      await ctx.db.patch("stripeEvents", existing._id, {
        status: args.status,
        error: args.error,
        account: args.account,
        livemode: args.livemode,
        ...(args.status === "failed" ? {} : { appliedAt: args.receivedAt }),
      });
    }
    return null;
  },
});

export const applyEventHandler = internalMutation({
  // The envelope is already validated; JSON preserves Stripe's arbitrary payload.
  args: { eventJson: v.string() },
  returns: v.null(),
  handler: async (ctx, args): Promise<null> => {
    const event = JSON.parse(args.eventJson) as StripeEvent;
    const handler = handlers[event.type];
    if (!handler) throw new Error(`Missing Stripe handler for ${event.type}`);
    await handler(ctx, event);
    return null;
  },
});

export const recordAndApply = internalMutation({
  args: {
    kind: v.union(v.literal("platform"), v.literal("connect")),
    // Stripe data.object varies by event type; the HTTP boundary validates the envelope.
    event: v.any(),
    receivedAt: v.number(),
    livemodeMismatch: v.boolean(),
  },
  returns: v.object({
    outcome: v.union(
      v.literal("applied"),
      v.literal("ignored"),
      v.literal("duplicate"),
      v.literal("failed"),
    ),
  }),
  handler: async (ctx, args): Promise<{ outcome: EventOutcome }> => {
    const event = args.event as StripeEvent;
    const existing = await ctx.db
      .query("stripeEvents")
      .withIndex("by_eventId", (query) => query.eq("eventId", event.id))
      .unique();
    if (existing?.status === "applied" || existing?.status === "ignored") {
      return { outcome: "duplicate" };
    }

    const metadata = {
      eventId: event.id,
      type: event.type,
      account: event.account,
      livemode: event.livemode,
      receivedAt: args.receivedAt,
    };
    if (args.livemodeMismatch) {
      await ctx.runMutation(internal.stripeWebhook.markEventOutcome, {
        ...metadata,
        status: "ignored",
        error: "livemode mismatch",
      });
      return { outcome: "ignored" };
    }

    if (!handlers[event.type]) {
      await ctx.runMutation(internal.stripeWebhook.markEventOutcome, {
        ...metadata,
        status: "ignored",
        error: undefined,
      });
      return { outcome: "ignored" };
    }

    try {
      // Nested writes merge into this transaction on success and roll back on failure.
      await ctx.runMutation(internal.stripeWebhook.applyEventHandler, {
        eventJson: JSON.stringify(event),
      });
    } catch (error) {
      await ctx.runMutation(internal.stripeWebhook.markEventOutcome, {
        ...metadata,
        status: "failed",
        error: error instanceof Error ? error.message : String(error),
      });
      // Returning commits the failure record; throwing would roll it back too.
      return { outcome: "failed" };
    }
    await ctx.runMutation(internal.stripeWebhook.markEventOutcome, {
      ...metadata,
      status: "applied",
      error: undefined,
    });
    return { outcome: "applied" };
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
      typeof event.livemode !== "boolean" ||
      typeof event.created !== "number" ||
      typeof event.data !== "object" ||
      event.data === null ||
      typeof (event.data as Record<string, unknown>).object !== "object" ||
      (event.data as Record<string, unknown>).object === null
    ) {
      return new Response("invalid event", { status: 400 });
    }
    const account =
      typeof event.account === "string" ? event.account : undefined;
    const expectedLivemode = deploymentName() === PRODUCTION_DEPLOYMENT;
    const livemodeMismatch = event.livemode !== expectedLivemode;
    const data = event.data as StripeEvent["data"];
    const stripeEvent: StripeEvent = {
      id: event.id,
      type: event.type,
      account,
      livemode: event.livemode,
      created: event.created,
      data: {
        object: data.object,
        ...(data.previous_attributes === undefined
          ? {}
          : { previous_attributes: data.previous_attributes }),
      },
    };

    try {
      const { outcome }: { outcome: EventOutcome } =
        await ctx.runMutation(internal.stripeWebhook.recordAndApply, {
          kind,
          event: stripeEvent,
          receivedAt: Date.now(),
          livemodeMismatch,
        });
      console.log(
        `stripe-webhook ${kind} ${event.id} ${event.type} ${outcome}`,
      );
      return new Response(
        outcome === "failed"
          ? "webhook mutation failed"
          : livemodeMismatch
            ? "ignored-livemode"
            : outcome,
        { status: outcome === "failed" ? 500 : 200 },
      );
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
