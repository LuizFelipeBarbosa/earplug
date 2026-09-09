import { makeFunctionReference } from "convex/server";
import { type Infer, v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { action, type ActionCtx } from "./_generated/server";
import { appBaseUrl } from "./lib/env";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import { stripeAccountStatusValidator } from "./payoutAccounts";

// These references work before the shared generated API includes this module.
const bandOnboardingContext = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  {
    stripeAccountId: string | null;
    cardPaymentsStatus: string | null;
    bandName: string;
    contactEmail: string | null;
  }
>("payoutAccounts:bandOnboardingContext");

const organizationOnboardingContext = makeFunctionReference<
  "query",
  { organizationId: Id<"organizations"> },
  {
    stripeAccountId: string | null;
    name: string;
    businessEmail: string | null;
    legalName: string | null;
  }
>("payoutAccounts:organizationOnboardingContext");

const attachBandAccount = makeFunctionReference<
  "mutation",
  { bandId: Id<"bands">; stripeAccountId: string },
  null
>("payoutAccounts:attachBandAccount");

const attachOrganizationAccount = makeFunctionReference<
  "mutation",
  { organizationId: Id<"organizations">; stripeAccountId: string },
  null
>("payoutAccounts:attachOrganizationAccount");

const applyAccountSnapshot = makeFunctionReference<
  "mutation",
  { account: Record<string, unknown> },
  null
>("payoutAccounts:applyAccountSnapshot");

const bandPayoutStatus = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  Infer<typeof stripeAccountStatusValidator>
>("payoutAccounts:bandPayoutStatus");

const organizationStripeStatus = makeFunctionReference<
  "query",
  { organizationId: Id<"organizations"> },
  Infer<typeof stripeAccountStatusValidator>
>("payoutAccounts:organizationStripeStatus");

async function callStripe<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    if (err instanceof StripeApiError)
      throw new Error(`Stripe: ${err.message}`);
    throw err;
  }
}

async function createBandAccount(
  ctx: ActionCtx,
  bandId: Id<"bands">,
  bandName: string,
): Promise<string> {
  const account = await callStripe(() =>
    stripeRequest<{ id: string }>(
      "POST",
      "/v1/accounts",
      {
        type: "express",
        country: "US",
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: "individual",
        business_profile: {
          name: bandName,
          product_description: "Live music performances booked through EarPlug",
        },
        metadata: { bandId, earplug: "band" },
        settings: { payouts: { schedule: { interval: "daily" } } },
      },
      { idempotencyKey: stripeIdempotencyKey("band-account", bandId) },
    ),
  );
  await ctx.runMutation(attachBandAccount, {
    bandId,
    stripeAccountId: account.id,
  });
  return account.id;
}

async function createBandOnboardingLink(
  bandId: Id<"bands">,
  stripeAccountId: string,
): Promise<{ url: string }> {
  const link = await callStripe(() =>
    stripeRequest<{ url: string }>("POST", "/v1/account_links", {
      account: stripeAccountId,
      type: "account_onboarding",
      refresh_url: `${appBaseUrl()}/band/stripe/refresh?band=${bandId}`,
      return_url: `${appBaseUrl()}/band/stripe/return?band=${bandId}`,
    }),
  );
  return { url: link.url };
}

export const startBandOnboarding = action({
  args: { bandId: v.id("bands") },
  returns: v.object({ url: v.string() }),
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(bandOnboardingContext, {
      bandId: args.bandId,
    });
    let stripeAccountId = context.stripeAccountId;
    if (stripeAccountId === null) {
      stripeAccountId = await createBandAccount(
        ctx,
        args.bandId,
        context.bandName,
      );
    }
    return await createBandOnboardingLink(args.bandId, stripeAccountId);
  },
});

export const enableBandTicketSales = action({
  args: { bandId: v.id("bands") },
  returns: v.object({ url: v.string() }),
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(bandOnboardingContext, {
      bandId: args.bandId,
    });
    let stripeAccountId = context.stripeAccountId;
    if (stripeAccountId === null) {
      stripeAccountId = await createBandAccount(
        ctx,
        args.bandId,
        context.bandName,
      );
    } else if (context.cardPaymentsStatus !== "active") {
      await callStripe(() =>
        stripeRequest(
          "POST",
          `/v1/accounts/${stripeAccountId}`,
          { capabilities: { card_payments: { requested: true } } },
          {
            idempotencyKey: stripeIdempotencyKey(
              "band-card-payments",
              args.bandId,
              Date.now(),
            ),
          },
        ),
      );
      const account = await callStripe(() =>
        stripeRequest("GET", `/v1/accounts/${stripeAccountId}`),
      );
      await ctx.runMutation(applyAccountSnapshot, { account });
    }
    return await createBandOnboardingLink(args.bandId, stripeAccountId);
  },
});

export const startOrganizationOnboarding = action({
  args: { organizationId: v.id("organizations") },
  returns: v.object({ url: v.string() }),
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(organizationOnboardingContext, {
      organizationId: args.organizationId,
    });
    let stripeAccountId = context.stripeAccountId;
    if (stripeAccountId === null) {
      const account = await callStripe(() =>
        stripeRequest<{ id: string }>(
          "POST",
          "/v1/accounts",
          {
            type: "express",
            country: "US",
            capabilities: {
              card_payments: { requested: true },
              transfers: { requested: true },
            },
            business_type: "company",
            business_profile: {
              name: context.legalName ?? context.name,
              product_description:
                "Live music performances booked through EarPlug",
            },
            metadata: {
              organizationId: args.organizationId,
              earplug: "organization",
            },
            settings: { payouts: { schedule: { interval: "daily" } } },
            ...(context.businessEmail !== null
              ? { email: context.businessEmail }
              : {}),
          },
          {
            idempotencyKey: stripeIdempotencyKey(
              "org-account",
              args.organizationId,
            ),
          },
        ),
      );
      await ctx.runMutation(attachOrganizationAccount, {
        organizationId: args.organizationId,
        stripeAccountId: account.id,
      });
      stripeAccountId = account.id;
    }

    const link = await callStripe(() =>
      stripeRequest<{ url: string }>("POST", "/v1/account_links", {
        account: stripeAccountId,
        type: "account_onboarding",
        refresh_url: `${appBaseUrl()}/org/stripe/refresh?org=${args.organizationId}`,
        return_url: `${appBaseUrl()}/org/stripe/return?org=${args.organizationId}`,
      }),
    );
    return { url: link.url };
  },
});

export const refreshBandAccountStatus = action({
  args: { bandId: v.id("bands") },
  returns: stripeAccountStatusValidator,
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(bandOnboardingContext, {
      bandId: args.bandId,
    });
    if (context.stripeAccountId !== null) {
      const account = await callStripe(() =>
        stripeRequest("GET", `/v1/accounts/${context.stripeAccountId}`),
      );
      await ctx.runMutation(applyAccountSnapshot, { account });
    }
    return await ctx.runQuery(bandPayoutStatus, { bandId: args.bandId });
  },
});

export const refreshOrganizationAccountStatus = action({
  args: { organizationId: v.id("organizations") },
  returns: stripeAccountStatusValidator,
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(organizationOnboardingContext, {
      organizationId: args.organizationId,
    });
    if (context.stripeAccountId !== null) {
      const account = await callStripe(() =>
        stripeRequest("GET", `/v1/accounts/${context.stripeAccountId}`),
      );
      await ctx.runMutation(applyAccountSnapshot, { account });
    }
    return await ctx.runQuery(organizationStripeStatus, {
      organizationId: args.organizationId,
    });
  },
});

export const bandExpressDashboardLink = action({
  args: { bandId: v.id("bands") },
  returns: v.object({ url: v.string() }),
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(bandOnboardingContext, {
      bandId: args.bandId,
    });
    if (context.stripeAccountId === null) {
      throw new Error("Finish Stripe setup first");
    }
    const status = await ctx.runQuery(bandPayoutStatus, {
      bandId: args.bandId,
    });
    if (!status.detailsSubmitted) {
      throw new Error("Finish Stripe setup first");
    }
    const response = await callStripe(() =>
      stripeRequest<{ url: string }>(
        "POST",
        `/v1/accounts/${context.stripeAccountId}/login_links`,
        {},
        {
          idempotencyKey: stripeIdempotencyKey(
            "band-dashboard",
            args.bandId,
            Date.now(),
          ),
        },
      ),
    );
    return { url: response.url };
  },
});

export const organizationExpressDashboardLink = action({
  args: { organizationId: v.id("organizations") },
  returns: v.object({ url: v.string() }),
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(organizationOnboardingContext, {
      organizationId: args.organizationId,
    });
    if (context.stripeAccountId === null) {
      throw new Error("Finish Stripe setup first");
    }
    const status = await ctx.runQuery(organizationStripeStatus, {
      organizationId: args.organizationId,
    });
    if (!status.detailsSubmitted) {
      throw new Error("Finish Stripe setup first");
    }
    const response = await callStripe(() =>
      stripeRequest<{ url: string }>(
        "POST",
        `/v1/accounts/${context.stripeAccountId}/login_links`,
        {},
        {
          idempotencyKey: stripeIdempotencyKey(
            "org-dashboard",
            args.organizationId,
            Date.now(),
          ),
        },
      ),
    );
    return { url: response.url };
  },
});
