import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import {
  currentUser,
  feedCutoff,
  gigPayloadValidator,
  requireUser,
  toGigPayload,
} from "./lib/helpers";

/** Per-user interaction state; empty/0 when unauthenticated (never throws). */
export const myInteractions = query({
  args: {},
  returns: v.object({
    rsvpGigIds: v.array(v.id("gigs")),
    followBandIds: v.array(v.id("bands")),
    savedGigIds: v.array(v.id("gigs")),
    gigs: v.array(gigPayloadValidator),
    attendedCount: v.number(),
  }),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) {
      return {
        rsvpGigIds: [],
        followBandIds: [],
        savedGigIds: [],
        gigs: [],
        attendedCount: 0,
      };
    }
    const rsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(500);
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(500);
    const saves = await ctx.db
      .query("gigSaves")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(500);
    const gigIds = new Set<Id<"gigs">>([
      ...rsvps.map((rsvp) => rsvp.gigId),
      ...saves.map((save) => save.gigId),
    ]);
    const cutoff = feedCutoff();
    const gigs = [];
    for (const gigId of gigIds) {
      const gig = await ctx.db.get(gigId);
      if (gig && gig.startsAt >= cutoff) {
        gigs.push(await toGigPayload(ctx, gig));
      }
    }
    return {
      rsvpGigIds: rsvps.map((r) => r.gigId),
      followBandIds: follows.map((f) => f.bandId),
      savedGigIds: saves.map((s) => s.gigId),
      gigs,
      attendedCount: user.attendedCount,
    };
  },
});

/** Gigs the user RSVPed to that have already happened, newest first; [] when
 * unauthenticated. The client supplies `now` so crossing the event boundary
 * changes the query arguments instead of relying on unrelated invalidation. */
export const history = query({
  args: { now: v.number() },
  returns: v.array(
    v.object({
      gigId: v.id("gigs"),
      title: v.string(),
      startsAt: v.number(),
      venueName: v.string(),
      bandNames: v.array(v.string()),
      flyKey: v.string(),
      flyerUrl: v.union(v.string(), v.null()),
      status: v.literal("rsvped"),
    }),
  ),
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const rsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(500);
    const past = [];
    for (const rsvp of rsvps) {
      const gig = await ctx.db.get(rsvp.gigId);
      if (!gig || gig.startsAt >= args.now) continue;
      const venue = await ctx.db.get(gig.venueId);
      const bandNames: string[] = [];
      for (const bandId of gig.lineup) {
        const band = await ctx.db.get(bandId);
        if (band !== null) bandNames.push(band.name);
      }
      past.push({
        gigId: gig._id,
        title: gig.title,
        startsAt: gig.startsAt,
        venueName: venue?.name ?? "",
        bandNames,
        flyKey: gig.flyKey,
        flyerUrl: gig.flyStorageId
          ? await ctx.storage.getUrl(gig.flyStorageId)
          : null,
        status: "rsvped" as const,
      });
    }
    past.sort((a, b) => b.startsAt - a.startsAt);
    return past;
  },
});

export const toggleRsvp = mutation({
  args: { gigId: v.id("gigs"), on: v.optional(v.boolean()) },
  returns: v.object({ on: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const gig = await ctx.db.get(args.gigId);
    if (!gig) throw new Error("Gig not found");
    const existing = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user_gig", (q) =>
        q.eq("userId", user._id).eq("gigId", args.gigId),
      )
      .unique();
    const shouldBeOn = args.on ?? existing === null;
    if (existing && shouldBeOn) return { on: true };
    if (existing) {
      await ctx.db.delete(existing._id);
      await ctx.db.patch(args.gigId, {
        goingCount: Math.max(0, gig.goingCount - 1),
      });
      return { on: false };
    }
    if (!shouldBeOn) return { on: false };
    await ctx.db.insert("gigRsvps", { userId: user._id, gigId: args.gigId });
    await ctx.db.patch(args.gigId, { goingCount: gig.goingCount + 1 });
    return { on: true };
  },
});

export const toggleFollow = mutation({
  args: { bandId: v.id("bands"), on: v.optional(v.boolean()) },
  returns: v.object({ on: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const band = await ctx.db.get(args.bandId);
    if (!band) throw new Error("Band not found");
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_user_band", (q) =>
        q.eq("userId", user._id).eq("bandId", args.bandId),
      )
      .unique();
    const shouldBeOn = args.on ?? existing === null;
    if (existing && shouldBeOn) return { on: true };
    if (existing) {
      await ctx.db.delete(existing._id);
      await ctx.db.patch(args.bandId, {
        followerCount: Math.max(0, band.followerCount - 1),
      });
      return { on: false };
    }
    if (!shouldBeOn) return { on: false };
    await ctx.db.insert("follows", { userId: user._id, bandId: args.bandId });
    await ctx.db.patch(args.bandId, { followerCount: band.followerCount + 1 });
    return { on: true };
  },
});

export const toggleSave = mutation({
  args: { gigId: v.id("gigs"), on: v.optional(v.boolean()) },
  returns: v.object({ on: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const gig = await ctx.db.get(args.gigId);
    if (!gig) throw new Error("Gig not found");
    const existing = await ctx.db
      .query("gigSaves")
      .withIndex("by_user_gig", (q) =>
        q.eq("userId", user._id).eq("gigId", args.gigId),
      )
      .unique();
    const shouldBeOn = args.on ?? existing === null;
    if (existing && shouldBeOn) return { on: true };
    if (existing) {
      await ctx.db.delete(existing._id);
      return { on: false };
    }
    if (!shouldBeOn) return { on: false };
    await ctx.db.insert("gigSaves", { userId: user._id, gigId: args.gigId });
    return { on: true };
  },
});
