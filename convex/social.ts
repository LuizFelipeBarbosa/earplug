import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { docCache } from "./lib/docCache";
import {
  currentUser,
  feedCutoff,
  MAX_FRIEND_RSVP_ROWS,
  requireUser,
} from "./lib/helpers";
import {
  followEdges,
  isLiveUser,
  MAX_FRIENDS_GOING_FRIENDS,
  MAX_FRIENDS_GOING_WINDOW_MS,
  MAX_RSVPS_PER_FRIEND,
  MAX_USER_SEARCH_RESULTS,
  MIN_USER_SEARCH_QUERY,
  sharesRsvps,
  socialPersonValidator,
  socialUserCardValidator,
  toSocialPerson,
  toSocialUserCard,
} from "./lib/social";

export const searchUsers = query({
  args: { q: v.string() },
  returns: v.array(socialUserCardValidator),
  handler: async (ctx, args) => {
    const currentUserDoc = await currentUser(ctx);
    if (currentUserDoc === null) return [];
    const q = args.q.trim();
    if (q === "") return [];
    const cache = docCache(ctx);
    if (q.includes("@")) {
      const exact = await ctx.db
        .query("users")
        .withIndex("by_email", (index) => index.eq("email", q))
        .unique();
      const lower =
        exact === null
          ? await ctx.db
              .query("users")
              .withIndex("by_email", (index) =>
                index.eq("email", q.toLowerCase()),
              )
              .unique()
          : null;
      const user = exact ?? lower;
      if (
        user === null ||
        user.email === "" ||
        !isLiveUser(user) ||
        user._id === currentUserDoc._id
      ) {
        return [];
      }
      return [await toSocialUserCard(ctx, currentUserDoc, user, cache)];
    }
    if (q.length < MIN_USER_SEARCH_QUERY) return [];
    const users = await ctx.db
      .query("users")
      .withSearchIndex("search_name", (search) => search.search("name", q))
      .take(MAX_USER_SEARCH_RESULTS * 2);
    const matches = users
      .filter(
        (user) =>
          user._id !== currentUserDoc._id &&
          isLiveUser(user) &&
          user.name !== "",
      )
      .slice(0, MAX_USER_SEARCH_RESULTS);
    const cards = [];
    for (const user of matches) {
      cards.push(await toSocialUserCard(ctx, currentUserDoc, user, cache));
    }
    return cards;
  },
});

export const toggleFollowUser = mutation({
  args: { userId: v.id("users"), on: v.optional(v.boolean()) },
  returns: v.object({ on: v.boolean() }),
  handler: async (ctx, args) => {
    const me = await requireUser(ctx);
    if (args.userId === me._id) throw new Error("You can't follow yourself");
    const target = await ctx.db.get(args.userId);
    if (!target || target.deletedAt !== undefined) {
      throw new Error("User not found");
    }
    const existing = await ctx.db
      .query("userFollows")
      .withIndex("by_follower_followee", (q) =>
        q.eq("followerId", me._id).eq("followeeId", args.userId),
      )
      .unique();
    const shouldBeOn = args.on ?? existing === null;
    if (existing && shouldBeOn) return { on: true };
    if (existing) {
      await ctx.db.delete(existing._id);
      return { on: false };
    }
    if (!shouldBeOn) return { on: false };
    await ctx.db.insert("userFollows", {
      followerId: me._id,
      followeeId: args.userId,
    });
    return { on: true };
  },
});

export const mySocial = query({
  args: {},
  returns: v.object({
    following: v.array(v.id("users")),
    followers: v.array(v.id("users")),
    friends: v.array(v.id("users")),
    followingCount: v.number(),
    followerCount: v.number(),
    truncated: v.boolean(),
    shareRsvpsWithFriends: v.boolean(),
  }),
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    if (me === null) {
      return {
        following: [],
        followers: [],
        friends: [],
        followingCount: 0,
        followerCount: 0,
        truncated: false,
        shareRsvpsWithFriends: true,
      };
    }
    const edges = await followEdges(ctx, me);
    return {
      ...edges,
      followingCount: edges.following.length,
      followerCount: edges.followers.length,
      shareRsvpsWithFriends: sharesRsvps(me),
    };
  },
});

export const friendsGoing = query({
  args: { from: v.number(), to: v.number() },
  returns: v.object({
    entries: v.array(
      v.object({
        gigId: v.id("gigs"),
        startsAt: v.number(),
        friends: v.array(socialPersonValidator),
      }),
    ),
    truncated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const empty = { entries: [], truncated: false };
    const me = await currentUser(ctx);
    if (
      me === null ||
      args.to <= args.from ||
      args.to - args.from > MAX_FRIENDS_GOING_WINDOW_MS
    ) {
      return empty;
    }
    const windowStart = Math.max(args.from, await feedCutoff(ctx));
    const edges = await followEdges(ctx, me);
    let truncated = edges.truncated;
    let rowsRead = 0;
    const friendIds = edges.friends.slice(0, MAX_FRIENDS_GOING_FRIENDS);
    if (edges.friends.length > MAX_FRIENDS_GOING_FRIENDS) truncated = true;
    const cache = docCache(ctx);
    const gigs = new Map<
      Id<"gigs">,
      { startsAt: number; friendIds: Id<"users">[] }
    >();
    // Friend-major reads keep each friend's sharing preference and RSVP rows
    // together, while the row budget bounds the transaction's indexed queries.
    for (const friendId of friendIds) {
      // The ~4096 queries-per-function transaction limit binds before the
      // ~16k-document read limit, so this row budget keeps up to 100 friends'
      // one-query RSVP reads under that ceiling.
      if (rowsRead > MAX_FRIEND_RSVP_ROWS) {
        truncated = true;
        break;
      }
      const friendUser = await cache.get(friendId);
      if (
        friendUser === null ||
        friendUser.deletedAt !== undefined ||
        !sharesRsvps(friendUser)
      ) {
        continue;
      }
      const rows = await ctx.db
        .query("gigRsvps")
        .withIndex("by_user", (q) => q.eq("userId", friendId))
        .order("desc")
        .take(MAX_RSVPS_PER_FRIEND);
      rowsRead += rows.length;
      for (const rsvp of rows) {
        const gig = await cache.get(rsvp.gigId);
        if (
          !gig ||
          windowStart > gig.startsAt ||
          gig.startsAt >= args.to ||
          (gig.lifecycle ?? "published") !== "published"
        ) {
          continue;
        }
        const entry = gigs.get(gig._id);
        if (entry) {
          entry.friendIds.push(friendId);
        } else {
          gigs.set(gig._id, { startsAt: gig.startsAt, friendIds: [friendId] });
        }
      }
    }
    const sorted = [...gigs.entries()].sort(([gigA, a], [gigB, b]) => {
      if (a.startsAt !== b.startsAt) return a.startsAt - b.startsAt;
      return String(gigA).localeCompare(String(gigB));
    });
    const entries = [];
    for (const [gigId, gig] of sorted) {
      const friends = [];
      for (const friendId of gig.friendIds) {
        const friend = await cache.get(friendId);
        if (friend !== null && friend.deletedAt === undefined) {
          friends.push(await toSocialPerson(ctx, friend, cache));
        }
      }
      entries.push({ gigId, startsAt: gig.startsAt, friends });
    }
    return { entries, truncated };
  },
});

export const userCard = query({
  args: { userId: v.id("users") },
  returns: v.union(
    socialUserCardValidator.extend({
      followedBandCount: v.number(),
      mutualBands: v.array(
        v.object({ bandId: v.id("bands"), name: v.string() }),
      ),
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    if (me === null) return null;
    const target = await ctx.db.get(args.userId);
    if (target === null || target.deletedAt !== undefined) return null;
    const cache = docCache(ctx);
    const card = await toSocialUserCard(ctx, me, target, cache);
    const [myFollows, targetFollows] = await Promise.all([
      ctx.db
        .query("follows")
        .withIndex("by_user", (q) => q.eq("userId", me._id))
        .take(500),
      ctx.db
        .query("follows")
        .withIndex("by_user", (q) => q.eq("userId", target._id))
        .take(500),
    ]);
    const myBandIds = new Set(myFollows.map((follow) => follow.bandId));
    const mutualBands = [];
    for (const follow of targetFollows) {
      if (!myBandIds.has(follow.bandId) || mutualBands.length >= 10) continue;
      const band = await cache.get(follow.bandId);
      if (band && band.archivedAt === undefined) {
        mutualBands.push({ bandId: band._id, name: band.name });
      }
    }
    return {
      ...card,
      followedBandCount: targetFollows.length,
      mutualBands,
    };
  },
});
