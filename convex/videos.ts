// Compatibility shim over `bandMedia` preserving the frozen v1 `VideoPayload`
// wire shape for the deployed client. Delete when the client moves to
// `media:forBand` (see docs/backend-contract.md).

import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { requireBandAdmin } from "./lib/helpers";

const shimVideoPayloadValidator = v.object({
  _id: v.id("bandMedia"),
  bandId: v.id("bands"),
  title: v.string(),
  views: v.number(),
  lengthSec: v.number(),
  pinned: v.boolean(),
  order: v.number(),
});

function toShimVideoPayload(video: Doc<"bandMedia">) {
  return {
    _id: video._id,
    bandId: video.bandId,
    title: video.title,
    views: video.views ?? 0,
    lengthSec: video.lengthSec ?? 0,
    pinned: video.pinned,
    order: video.order,
  };
}

/** Top-level array, ordered by `order` asc. */
export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(shimVideoPayloadValidator),
  handler: async (ctx, args) => {
    const videos = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_kind_order", (q) =>
        q.eq("bandId", args.bandId).eq("kind", "video"),
      )
      .order("asc")
      .take(100);
    return videos.map(toShimVideoPayload);
  },
});

export const pinVideo = mutation({
  args: { videoId: v.id("bandMedia") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const video = await ctx.db.get(args.videoId);
    if (!video || video.kind !== "video") throw new Error("Video not found");
    await requireBandAdmin(ctx, video.bandId);
    const siblings = await ctx.db
      .query("bandMedia")
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
    videoId: v.id("bandMedia"),
    direction: v.union(v.literal("up"), v.literal("down")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const video = await ctx.db.get(args.videoId);
    if (!video || video.kind !== "video") throw new Error("Video not found");
    await requireBandAdmin(ctx, video.bandId);
    const siblings = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_kind_order", (q) =>
        q.eq("bandId", video.bandId).eq("kind", "video"),
      )
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
