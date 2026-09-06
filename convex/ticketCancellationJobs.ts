import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation } from "./_generated/server";
import { runTicketCancellationBatch } from "./lib/ticketCancellation";

export const processBatch = internalMutation({
  args: { gigId: v.id("gigs") },
  returns: v.null(),
  handler: async (ctx, { gigId }) => {
    const { hasMore } = await runTicketCancellationBatch(ctx, gigId);
    if (hasMore) {
      await ctx.scheduler.runAfter(0, internal.ticketCancellationJobs.processBatch, {
        gigId,
      });
    }
    return null;
  },
});
