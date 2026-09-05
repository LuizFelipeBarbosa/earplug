import { v } from "convex/values";
import { internalMutation, MutationCtx, QueryCtx } from "./_generated/server";
import { FEED_GRACE_MS } from "./lib/helpers";

export const FEED_CUTOFF_KEY = "feedCutoff";

export const heartbeat = internalMutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const value = Math.floor((Date.now() - FEED_GRACE_MS) / 60_000) * 60_000;
    const row = await ctx.db
      .query("clock")
      .withIndex("by_key", (q) => q.eq("key", FEED_CUTOFF_KEY))
      .unique();
    if (row) {
      if (row.value !== value) await ctx.db.patch(row._id, { value });
    } else {
      await ctx.db.insert("clock", { key: FEED_CUTOFF_KEY, value });
    }
    return null;
  },
});

export async function readFeedCutoff(
  ctx: QueryCtx | MutationCtx,
): Promise<number> {
  const row = await ctx.db
    .query("clock")
    .withIndex("by_key", (q) => q.eq("key", FEED_CUTOFF_KEY))
    .unique();
  if (row) return row.value;

  // Only the first deploy can precede the first heartbeat. Until that
  // 15-minute cron runs, fall back to the wall clock for the cutoff.
  return Date.now() - FEED_GRACE_MS;
}
