import { internal } from "./_generated/api";
import { v, type Infer } from "convex/values";
import type { Id } from "./_generated/dataModel";
import { action, internalQuery } from "./_generated/server";
import type { transactionValidator } from "./finance";
import { requireOrganizationRole, type OrganizationRole } from "./lib/authz";
import { stripeRequest } from "./lib/stripeClient";

const snapshotValidator = v.object({
  availableMinor: v.number(),
  pendingMinor: v.number(),
  currency: v.string(),
  fetchedAt: v.number(),
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
      roles: ["owner", "finance"],
    });
    const { stripeAccountId, snapshot } = await ctx.runQuery(
      internal.finance.financeContext,
      args,
    );
    if (stripeAccountId == null) return null;
    if (snapshot && Date.now() - snapshot.fetchedAt < 5 * 60 * 1000) {
      return snapshot;
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
      if (snapshot) return snapshot;
      throw error;
    }

    const refreshedSnapshot: Snapshot = {
      availableMinor: sumUsd(balance.available),
      pendingMinor: sumUsd(balance.pending),
      currency: "usd",
      fetchedAt: Date.now(),
    };
    await ctx.runMutation(internal.finance.upsertSnapshot, {
      organizationId: args.organizationId,
      stripeAccountId,
      ...refreshedSnapshot,
    });
    return refreshedSnapshot;
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
  handler: async (ctx, args): Promise<{ csv: string; rows: number; truncated: boolean }> => {
    await ctx.runQuery(internal.financeActions.requireFinanceAccess, {
      organizationId: args.organizationId,
      roles: ["owner", "finance"],
    });
    if (args.fromMs > args.toMs) {
      throw new Error("fromMs must not be after toMs");
    }
    if (args.toMs - args.fromMs > 366 * 24 * 60 * 60 * 1000) {
      throw new Error("Choose a range of one year or less");
    }

    const rows: Infer<typeof transactionValidator>[] = await ctx.runQuery(
      internal.finance.ledgerRowsForStatement,
      args,
    );
    const lines = ["date,type,label,amount,currency,funds_state,reference"];
    for (const row of rows) {
      lines.push(
        [
          new Date(row.occurredAt).toISOString(),
          row.kind,
          row.label,
          formatAmount(row.amountMinor),
          row.currency,
          row.fundsState,
          row.stripeRef ?? "",
        ]
          .map(csvField)
          .join(","),
      );
    }
    return {
      csv: lines.join("\r\n"),
      rows: rows.length,
      truncated: rows.length === 2000,
    };
  },
});
