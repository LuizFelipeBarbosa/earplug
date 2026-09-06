import { internal } from "./_generated/api";
import { v, type Infer } from "convex/values";
import { action, internalQuery } from "./_generated/server";
import { requireOrganizationRole, type OrganizationRole } from "./lib/authz";
import { stripeRequest } from "./lib/stripeClient";

// Stripe access and data exports are limited to owner/finance, excluding managers.
const FINANCE_WRITE_ROLES: OrganizationRole[] = ["owner", "finance"];

const snapshotValidator = v.object({
  availableMinor: v.number(),
  pendingMinor: v.number(),
  currency: v.string(),
  fetchedAt: v.number(),
  stale: v.boolean(),
});
type Snapshot = Infer<typeof snapshotValidator>;

export const requireFinanceAccess = internalQuery({
  args: {
    organizationId: v.id("organizations"),
    roles: v.array(
      v.union(
        v.literal("owner"),
        v.literal("manager"),
        v.literal("finance"),
        v.literal("door"),
      ),
    ),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, args.roles);
    return null;
  },
});

type StripeBalance = {
  available: Array<{ amount: number; currency: string }>;
  pending: Array<{ amount: number; currency: string }>;
};

function sumUsd(buckets: Array<{ amount: number; currency: string }>): number {
  return buckets.reduce(
    (total, bucket) => total + (bucket.currency === "usd" ? bucket.amount : 0),
    0,
  );
}

export const refreshBalance = action({
  args: { organizationId: v.id("organizations") },
  returns: v.union(snapshotValidator, v.null()),
  handler: async (ctx, args): Promise<Snapshot | null> => {
    await ctx.runQuery(internal.financeActions.requireFinanceAccess, {
      organizationId: args.organizationId,
      roles: FINANCE_WRITE_ROLES,
    });
    const { stripeAccountId, snapshotStripeAccountId, snapshot } =
      await ctx.runQuery(internal.finance.financeContext, args);
    if (stripeAccountId == null) return null;
    if (
      snapshot &&
      snapshotStripeAccountId === stripeAccountId &&
      Date.now() - snapshot.fetchedAt < 5 * 60 * 1000
    ) {
      return { ...snapshot, stale: false };
    }

    let balance: StripeBalance;
    try {
      balance = await stripeRequest<StripeBalance>(
        "GET",
        "/v1/balance",
        undefined,
        { stripeAccount: stripeAccountId },
      );
    } catch (error) {
      console.error(error);
      if (snapshot) return { ...snapshot, stale: true };
      throw error;
    }

    const refreshedSnapshot = {
      availableMinor: sumUsd(
        Array.isArray(balance.available) ? balance.available : [],
      ),
      pendingMinor: sumUsd(
        Array.isArray(balance.pending) ? balance.pending : [],
      ),
      currency: "usd",
      fetchedAt: Date.now(),
    };
    await ctx.runMutation(internal.finance.upsertSnapshot, {
      organizationId: args.organizationId,
      stripeAccountId,
      ...refreshedSnapshot,
    });
    return { ...refreshedSnapshot, stale: false };
  },
});

function formatAmount(amountMinor: number): string {
  const absoluteMinor = Math.abs(amountMinor);
  const dollars = Math.floor(absoluteMinor / 100);
  const cents = String(absoluteMinor % 100).padStart(2, "0");
  return `${amountMinor < 0 ? "-" : ""}${dollars}.${cents}`;
}

function csvField(value: string): string {
  return /[,"\r\n]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value;
}

function csvTextField(value: string): string {
  if (/^[=+\-@\t\r]/.test(value)) {
    return `"'${value.replace(/"/g, '""')}"`;
  }
  return csvField(value);
}

export const exportStatement = action({
  args: {
    organizationId: v.id("organizations"),
    fromMs: v.number(),
    toMs: v.number(),
  },
  returns: v.object({
    csv: v.string(),
    rows: v.number(),
    truncated: v.boolean(),
  }),
  handler: async (
    ctx,
    args,
  ): Promise<{ csv: string; rows: number; truncated: boolean }> => {
    await ctx.runQuery(internal.financeActions.requireFinanceAccess, {
      organizationId: args.organizationId,
      roles: FINANCE_WRITE_ROLES,
    });
    if (args.fromMs > args.toMs) {
      throw new Error("fromMs must not be after toMs");
    }
    if (args.toMs - args.fromMs > 366 * 24 * 60 * 60 * 1000) {
      throw new Error("Choose a range of one year or less");
    }

    const { rows, truncated } = await ctx.runQuery(
      internal.finance.ledgerRowsForStatement,
      args,
    );
    const lines = ["date,type,label,amount,currency,funds_state,reference"];
    for (const row of rows) {
      lines.push(
        [
          csvField(new Date(row.occurredAt).toISOString()),
          csvTextField(row.kind),
          csvTextField(row.label),
          formatAmount(row.amountMinor),
          csvField(row.currency),
          csvField(row.fundsState),
          csvTextField(row.stripeRef ?? ""),
        ].join(","),
      );
    }
    return {
      csv: lines.join("\r\n"),
      rows: rows.length,
      truncated,
    };
  },
});
