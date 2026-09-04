import { verifyWebhook } from "@clerk/backend/webhooks";
import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import { clerkUserFacts } from "./lib/clerkUser";
import {
  handleConnectWebhook,
  handlePlatformWebhook,
} from "./stripeWebhook";

const clerkWebhook = httpAction(async (ctx, request) => {
  const secret = process.env.CLERK_WEBHOOK_SECRET;
  if (!secret) {
    console.error("CLERK_WEBHOOK_SECRET is not set");
    return new Response("Webhook is not configured", { status: 500 });
  }

  let evt: Awaited<ReturnType<typeof verifyWebhook>>;
  try {
    // verifyWebhook owns the body. Reading request.text()/json() first would
    // consume it and make signature verification impossible.
    evt = await verifyWebhook(request, { signingSecret: secret });
  } catch {
    return new Response("Invalid webhook", { status: 400 });
  }

  const svixId = request.headers.get("svix-id") ?? "unknown";
  switch (evt.type) {
    case "user.created":
    case "user.updated": {
      const facts = clerkUserFacts(evt.data);
      if (facts === null) {
        console.log(`${svixId} ${evt.type} invalid_payload`);
        return new Response("Invalid user payload", { status: 400 });
      }

      try {
        // Exactly one database transaction owns the complete adoption ladder.
        const result = await ctx.runMutation(internal.users.syncFromClerk, {
          ...facts,
          emailIsAuthoritative: evt.type === "user.updated",
        });
        console.log(
          `${svixId} ${evt.type} ${result.outcome}${result.emailConflict ? " email_conflict" : ""}`,
        );
        return new Response("ok", { status: 200 });
      } catch {
        console.error(`${svixId} ${evt.type} mutation_failed`);
        return new Response("Webhook mutation failed", { status: 500 });
      }
    }

    case "user.deleted": {
      if (typeof evt.data.id !== "string") {
        console.log(`${svixId} ${evt.type} invalid_payload`);
        return new Response("Invalid user payload", { status: 400 });
      }

      try {
        const result = await ctx.runMutation(
          internal.users.markDeletedFromClerk,
          { clerkId: evt.data.id },
        );
        console.log(
          `${svixId} ${evt.type} ${result.found ? "tombstoned" : "not_found"}`,
        );
        return new Response("ok", { status: 200 });
      } catch {
        console.error(`${svixId} ${evt.type} mutation_failed`);
        return new Response("Webhook mutation failed", { status: 500 });
      }
    }

    default:
      // Unsubscribed event types are valid deliveries. A non-2xx response here
      // would make Svix retry an event this deployment intentionally ignores.
      console.log(`${svixId} ${evt.type} ignored`);
      return new Response("ignored", { status: 200 });
  }
});

const http = httpRouter();
http.route({ path: "/clerk-webhook", method: "POST", handler: clerkWebhook });
http.route({
  path: "/stripe-webhook",
  method: "POST",
  handler: handlePlatformWebhook,
});
http.route({
  path: "/stripe-connect-webhook",
  method: "POST",
  handler: handleConnectWebhook,
});

export default http;
