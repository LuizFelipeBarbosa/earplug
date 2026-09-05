import { type Infer, v } from "convex/values";
import { internalMutation, internalQuery, query } from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  requireOrganizationRoleQuery,
} from "./lib/authz";
import { requireBandRole } from "./lib/helpers";
import { syncStripeAccount } from "./lib/stripeAccountSync";

export const stripeAccountStatusValidator = v.object({
  state: v.union(
    v.literal("none"),
    v.literal("onboarding"),
    v.literal("restricted"),
    v.literal("enabled"),
  ),
  stripeAccountId: v.boolean(),
  chargesEnabled: v.boolean(),
  payoutsEnabled: v.boolean(),
  detailsSubmitted: v.boolean(),
  requirementsDue: v.array(v.string()),
});

type StripeAccountStatus = Infer<typeof stripeAccountStatusValidator>;

function accountStatus(
  account: Omit<StripeAccountStatus, "state"> | null,
): StripeAccountStatus {
  if (account === null) {
    return {
      state: "none",
      stripeAccountId: false,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
    };
  }
  return {
    ...account,
    state: account.payoutsEnabled
      ? "enabled"
      : !account.detailsSubmitted
        ? "onboarding"
        : "restricted",
  };
}

export const bandPayoutStatus = query({
  args: { bandId: v.id("bands") },
  returns: stripeAccountStatusValidator,
  handler: async (ctx, args) => {
    await requireBandRole(ctx, args.bandId, { role: "member" });
    const account = await ctx.db
      .query("bandPayoutAccounts")
      .withIndex("by_bandId", (q) => q.eq("bandId", args.bandId))
      .unique();
    return accountStatus(
      account === null
        ? null
        : {
            stripeAccountId: true,
            chargesEnabled: account.chargesEnabled,
            payoutsEnabled: account.payoutsEnabled,
            detailsSubmitted: account.detailsSubmitted,
            requirementsDue: account.requirementsDue,
          },
    );
  },
});

export const organizationStripeStatus = query({
  args: { organizationId: v.id("organizations") },
  returns: stripeAccountStatusValidator,
  handler: async (ctx, args) => {
    await requireOrganizationRoleQuery(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    return accountStatus(
      details === null
        ? null
        : {
            stripeAccountId: details.stripeAccountId !== undefined,
            chargesEnabled: details.stripeChargesEnabled,
            payoutsEnabled: details.stripePayoutsEnabled,
            detailsSubmitted: details.stripeDetailsSubmitted,
            requirementsDue: details.stripeRequirementsDue ?? [],
          },
    );
  },
});

export const bandOnboardingContext = internalQuery({
  args: { bandId: v.id("bands") },
  returns: v.object({
    stripeAccountId: v.union(v.string(), v.null()),
    bandName: v.string(),
    contactEmail: v.union(v.string(), v.null()),
  }),
  handler: async (ctx, args) => {
    const { band, user } = await requireBandRole(ctx, args.bandId, {
      role: "admin",
    });
    const account = await ctx.db
      .query("bandPayoutAccounts")
      .withIndex("by_bandId", (q) => q.eq("bandId", args.bandId))
      .unique();
    return {
      stripeAccountId: account?.stripeAccountId ?? null,
      bandName: band.name,
      contactEmail: user.email || null,
    };
  },
});

export const organizationOnboardingContext = internalQuery({
  args: { organizationId: v.id("organizations") },
  returns: v.object({
    stripeAccountId: v.union(v.string(), v.null()),
    name: v.string(),
    businessEmail: v.union(v.string(), v.null()),
    legalName: v.union(v.string(), v.null()),
  }),
  handler: async (ctx, args) => {
    const { organization } = await requireOrganizationRoleQuery(
      ctx,
      args.organizationId,
      ["owner"],
    );
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    return {
      stripeAccountId: details?.stripeAccountId ?? null,
      name: organization.name,
      businessEmail: details?.businessEmail ?? null,
      legalName: details?.legalName ?? null,
    };
  },
});

export const attachBandAccount = internalMutation({
  args: { bandId: v.id("bands"), stripeAccountId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("bandPayoutAccounts")
      .withIndex("by_bandId", (q) => q.eq("bandId", args.bandId))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, {
        stripeAccountId: args.stripeAccountId,
        updatedAt: now,
        ...(existing.stripeAccountId !== args.stripeAccountId
          ? {
              chargesEnabled: false,
              payoutsEnabled: false,
              detailsSubmitted: false,
              requirementsDue: [],
            }
          : {}),
      });
      return null;
    }
    await ctx.db.insert("bandPayoutAccounts", {
      bandId: args.bandId,
      stripeAccountId: args.stripeAccountId,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
      onboardingStartedAt: now,
      updatedAt: now,
    });
    return null;
  },
});

export const attachOrganizationAccount = internalMutation({
  args: {
    organizationId: v.id("organizations"),
    stripeAccountId: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const details = await ctx.db
      .query("organizationPrivateDetails")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .unique();
    if (details === null) {
      throw new Error("Organization private details not found");
    }
    await ctx.db.patch("organizationPrivateDetails", details._id, {
      stripeAccountId: args.stripeAccountId,
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const applyAccountSnapshot = internalMutation({
  args: { account: v.any() },
  returns: v.null(),
  handler: async (ctx, args) => {
    await syncStripeAccount(
      ctx,
      args.account as Parameters<typeof syncStripeAccount>[1],
    );
    return null;
  },
});
