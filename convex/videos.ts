import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  requireBandAdmin,
  toVideoPayload,
  videoPayloadValidator,
} from "./lib/helpers";

/** Top-level array, ordered by `order` asc. */
export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(videoPayloadValidator),
  handler: async (ctx, args) => {
    const videos = await ctx.db
      .query("videos")
      .withIndex("by_band_order", (q) => q.eq("bandId", args.bandId))
      .order("asc")
      .take(100);
    return videos.map(toVideoPayload);
  },
});

export const pinVideo = mutation({
  args: { videoId: v.id("videos") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const video = await ctx.db.get(args.videoId);
    if (!video) throw new Error("Video not found");
    await requireBandAdmin(ctx, video.bandId);
    const siblings = await ctx.db
      .query("videos")
      .withIndex("by_band_order", (q) => q.eq("bandId", video.bandId))
      .take(100);
    for (const sibling of siblings) {
      if (sibling.pinned && sibling._id !== args.videoId) {
        await ctx.db.patch(sibling._id, { pinned: false });
      }
    }
    await ctx.db.patch(args.videoId, { pinned: true });
    return null;
  },
});

export const moveVideo = mutation({
  args: {
    videoId: v.id("videos"),
    direction: v.union(v.literal("up"), v.literal("down")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const video = await ctx.db.get(args.videoId);
    if (!video) throw new Error("Video not found");
    await requireBandAdmin(ctx, video.bandId);
    const siblings = await ctx.db
      .query("videos")
      .withIndex("by_band_order", (q) => q.eq("bandId", video.bandId))
      .order("asc")
      .take(100);
    const index = siblings.findIndex((s) => s._id === args.videoId);
    const neighborIndex = args.direction === "up" ? index - 1 : index + 1;
    if (neighborIndex < 0 || neighborIndex >= siblings.length) return null; // no-op at ends
    const neighbor = siblings[neighborIndex];
    await ctx.db.patch(video._id, { order: neighbor.order });
    await ctx.db.patch(neighbor._id, { order: video.order });
    return null;
  },
});
