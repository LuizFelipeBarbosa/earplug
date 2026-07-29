import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { currentUser, requireUser } from "./lib/helpers";

/** Per-user interaction state; empty/0 when unauthenticated (never throws). */
export const myInteractions = query({
  args: {},
  returns: v.object({
    rsvpGigIds: v.array(v.id("gigs")),
    followBandIds: v.array(v.id("bands")),
    savedGigIds: v.array(v.id("gigs")),
    attendedCount: v.number(),
  }),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) {
      return { rsvpGigIds: [], followBandIds: [], savedGigIds: [], attendedCount: 0 };
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
    return {
      rsvpGigIds: rsvps.map((r) => r.gigId),
      followBandIds: follows.map((f) => f.bandId),
      savedGigIds: saves.map((s) => s.gigId),
      attendedCount: user.attendedCount ?? 0,
    };
  },
});

/** Gigs the user RSVPed to that have already happened, newest first; [] when
 * unauthenticated. Same Date.now() staleness caveat as gigs:feed — a gig only
 * crosses into history when something invalidates this query. */
export const history = query({
  args: {},
  returns: v.array(
    v.object({
      title: v.string(),
      venueName: v.string(),
      startsAt: v.number(),
    }),
  ),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    if (user === null) return [];
    const rsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .take(500);
    const now = Date.now();
    const past = [];
    for (const rsvp of rsvps) {
      const gig = await ctx.db.get(rsvp.gigId);
      if (!gig || gig.startsAt >= now) continue;
      const venue = await ctx.db.get(gig.venueId);
      past.push({
        title: gig.title,
        venueName: venue?.name ?? "",
        startsAt: gig.startsAt,
      });
    }
    past.sort((a, b) => b.startsAt - a.startsAt);
    return past;
  },
});

export const toggleRsvp = mutation({
  args: { gigId: v.id("gigs") },
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
    if (existing) {
      await ctx.db.delete(existing._id);
      await ctx.db.patch(args.gigId, {
        goingCount: Math.max(0, gig.goingCount - 1),
      });
      return { on: false };
    }
    await ctx.db.insert("gigRsvps", { userId: user._id, gigId: args.gigId });
    await ctx.db.patch(args.gigId, { goingCount: gig.goingCount + 1 });
    return { on: true };
  },
});

export const toggleFollow = mutation({
  args: { bandId: v.id("bands") },
  returns: v.object({ on: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const band = await ctx.db.get(args.bandId);
    if (!band) throw new Error("Band not found");
    const count = band.followerCount ?? 0;
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_user_band", (q) =>
        q.eq("userId", user._id).eq("bandId", args.bandId),
      )
      .unique();
    if (existing) {
      await ctx.db.delete(existing._id);
      await ctx.db.patch(args.bandId, {
        followerCount: Math.max(0, count - 1),
      });
      return { on: false };
    }
    await ctx.db.insert("follows", { userId: user._id, bandId: args.bandId });
    await ctx.db.patch(args.bandId, { followerCount: count + 1 });
    return { on: true };
  },
});

export const toggleSave = mutation({
  args: { gigId: v.id("gigs") },
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
    if (existing) {
      await ctx.db.delete(existing._id);
      return { on: false };
    }
    await ctx.db.insert("gigSaves", { userId: user._id, gigId: args.gigId });
    return { on: true };
  },
});
