import type { MutationCtx } from "../_generated/server";

type StripeAccount = {
  id: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  requirements?: {
    currently_due?: string[];
    past_due?: string[];
    disabled_reason?: string | null;
  };
};

function requirementsDue(requirements: StripeAccount["requirements"]): string[] {
  return [
    ...new Set([
      ...(requirements?.currently_due ?? []),
      ...(requirements?.past_due ?? []),
    ]),
  ];
}

export async function syncStripeAccount(
  ctx: MutationCtx,
  account: StripeAccount,
): Promise<"band" | "organization" | "unknown"> {
  const bandAccount = await ctx.db
    .query("bandPayoutAccounts")
    .withIndex("by_stripeAccountId", (query) =>
      query.eq("stripeAccountId", account.id),
    )
    .unique();
  if (bandAccount !== null) {
    await ctx.db.patch("bandPayoutAccounts", bandAccount._id, {
      chargesEnabled: account.charges_enabled ?? false,
      payoutsEnabled: account.payouts_enabled ?? false,
      detailsSubmitted: account.details_submitted ?? false,
      requirementsDue: requirementsDue(account.requirements),
      updatedAt: Date.now(),
    });
    return "band";
  }

  const organization = await ctx.db
    .query("organizationPrivateDetails")
    .withIndex("by_stripeAccountId", (query) =>
      query.eq("stripeAccountId", account.id),
    )
    .unique();
  if (organization !== null) {
    await ctx.db.patch("organizationPrivateDetails", organization._id, {
      stripeChargesEnabled: account.charges_enabled ?? false,
      stripePayoutsEnabled: account.payouts_enabled ?? false,
      stripeDetailsSubmitted: account.details_submitted ?? false,
      stripeRequirementsDue: requirementsDue(account.requirements),
      updatedAt: Date.now(),
    });
    return "organization";
  }

  return "unknown";
}
