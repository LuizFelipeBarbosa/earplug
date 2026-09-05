import type { Infer } from "convex/values";
import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { fundsStateValidator, ledgerKindValidator } from "../schema";

export async function appendLedgerEntry(
  ctx: MutationCtx,
  entry: {
    idempotencyKey: string;
    kind: Infer<typeof ledgerKindValidator>;
    amountMinor: number;
    currency: string;
    fundsState: Infer<typeof fundsStateValidator>;
    bookingId?: Id<"bookings">;
    organizationId?: Id<"organizations">;
    bandId?: Id<"bands">;
    stripeRef?: string;
    stripeEventId?: string;
    occurredAt: number;
  },
): Promise<Id<"ledgerEntries">> {
  const existing = await ctx.db
    .query("ledgerEntries")
    .withIndex("by_idempotencyKey", (q) =>
      q.eq("idempotencyKey", entry.idempotencyKey),
    )
    .unique();
  if (existing) return existing._id;
  return await ctx.db.insert("ledgerEntries", entry);
}
