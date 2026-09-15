import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
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
  MAX_KNOWN_ATTENDEE_CHECKS,
  MAX_KNOWN_ATTENDEE_ROWS,
  MAX_KNOWN_ATTENDEE_RSVP_ROWS,
  MAX_KNOWN_ATTENDEES,
  MAX_FRIENDS_GOING_FRIENDS,
  MAX_FRIENDS_GOING_WINDOW_MS,
  MAX_RSVPS_PER_FRIEND,
  MAX_SUGGESTED_PEOPLE,
  MAX_USER_SEARCH_RESULTS,
  MIN_SHARED_PAST_SHOWS,
  MIN_SHARED_SHOWS_FOR_SUGGESTION,
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

export const knownAttendees = query({
  args: { gigId: v.id("gigs"), now: v.number() },
  returns: v.object({
    people: v.array(
      socialPersonValidator.extend({
        relation: v.union(v.literal("friend"), v.literal("seen")),
        sharedShows: v.number(),
      }),
    ),
    goingCount: v.number(),
    truncated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const me = await currentUser(ctx);
    if (me === null) return { people: [], goingCount: 0, truncated: false };
    const gig = await ctx.db.get(args.gigId);
    if (gig === null) return { people: [], goingCount: 0, truncated: false };
    if ((gig.lifecycle ?? "published") !== "published") {
      return { people: [], goingCount: gig.goingCount, truncated: false };
    }

    const attendeeRows = await ctx.db
      .query("gigRsvps")
      .withIndex("by_gig", (q) => q.eq("gigId", args.gigId))
      .take(MAX_KNOWN_ATTENDEE_ROWS);
    const cache = docCache(ctx);
    const edges = await followEdges(ctx, me);
    const friendIds = new Set(edges.friends);
    const callerHistory = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user", (q) => q.eq("userId", me._id))
      .take(200);
    let rowsRead = attendeeRows.length + callerHistory.length;
    const callerPastShows = new Set<Id<"gigs">>();
    for (const row of callerHistory) {
      const pastGig = await cache.get(row.gigId);
      if (pastGig !== null && pastGig.startsAt < args.now) {
        callerPastShows.add(pastGig._id);
      }
    }

    const attendeeIds: Id<"users">[] = [];
    const seenAttendees = new Set<Id<"users">>();
    for (const row of attendeeRows) {
      if (row.userId !== me._id && !seenAttendees.has(row.userId)) {
        seenAttendees.add(row.userId);
        attendeeIds.push(row.userId);
      }
    }
    const included: Array<{
      user: Doc<"users">;
      relation: "friend" | "seen";
      sharedShows: number;
    }> = [];
    let nonFriendChecks = 0;
    let truncated = false;
    for (const userId of attendeeIds) {
      if (rowsRead > MAX_KNOWN_ATTENDEE_RSVP_ROWS) {
        truncated = true;
        break;
      }
      if (!friendIds.has(userId) && nonFriendChecks >= MAX_KNOWN_ATTENDEE_CHECKS) {
        truncated = true;
        break;
      }
      const user = await cache.get(userId);
      if (user === null || !isLiveUser(user) || !sharesRsvps(user)) continue;
      if (friendIds.has(userId)) {
        included.push({ user, relation: "friend", sharedShows: 0 });
        continue;
      }
      nonFriendChecks += 1;
      const history = await ctx.db
        .query("gigRsvps")
        .withIndex("by_user", (q) => q.eq("userId", userId))
        .take(100);
      rowsRead += history.length;
      let sharedShows = 0;
      for (const row of history) {
        if (callerPastShows.has(row.gigId)) sharedShows += 1;
      }
      if (sharedShows >= MIN_SHARED_PAST_SHOWS) {
        included.push({ user, relation: "seen", sharedShows });
      }
      if (rowsRead > MAX_KNOWN_ATTENDEE_RSVP_ROWS) {
        truncated = true;
        break;
      }
    }

    included.sort((a, b) => {
      if (a.relation !== b.relation) return a.relation === "friend" ? -1 : 1;
      if (a.sharedShows !== b.sharedShows) return b.sharedShows - a.sharedShows;
      return a.user.name.localeCompare(b.user.name);
    });
    const people = [];
    for (const entry of included.slice(0, MAX_KNOWN_ATTENDEES)) {
      people.push({
        ...(await toSocialPerson(ctx, entry.user, cache)),
        relation: entry.relation,
        sharedShows: entry.sharedShows,
      });
    }
    return { people, goingCount: gig.goingCount, truncated };
  },
});

export const suggestedPeople = query({
  args: {},
  returns: v.object({
    people: v.array(v.object({
      userId: v.id("users"),
      name: v.string(),
      avatarUrl: v.optional(v.string()),
      sharedShows: v.number(),
      mutualFriends: v.number(),
      followsMe: v.boolean(),
    })),
    truncated: v.boolean(),
  }),
  handler: async (ctx) => {
    const me = await currentUser(ctx);
    if (me === null) return { people: [], truncated: false };

    const cache = docCache(ctx);
    const edges = await followEdges(ctx, me);
    let truncated = edges.truncated;
    const candidates = new Map<
      Id<"users">,
      { sharedShows: number; mutualFriends: number }
    >();
    const callerRsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user", (q) => q.eq("userId", me._id))
      .order("desc")
      .take(50);
    let rowsRead = callerRsvps.length;
    const gigIds = new Set(callerRsvps.map((row) => row.gigId));
    for (const gigId of gigIds) {
      const attendeeRows = await ctx.db
        .query("gigRsvps")
        .withIndex("by_gig", (q) => q.eq("gigId", gigId))
        .take(100);
      rowsRead += attendeeRows.length;
      const attendeeIds = new Set(attendeeRows.map((row) => row.userId));
      for (const userId of attendeeIds) {
        if (userId === me._id) continue;
        const user = await cache.get(userId);
        // RSVP privacy applies to this signal even when mutual friends would
        // independently qualify the candidate for a suggestion.
        if (user === null || !isLiveUser(user) || !sharesRsvps(user)) continue;
        const candidate = candidates.get(userId) ?? {
          sharedShows: 0,
          mutualFriends: 0,
        };
        candidate.sharedShows += 1;
        candidates.set(userId, candidate);
      }
      if (rowsRead > MAX_FRIEND_RSVP_ROWS) {
        truncated = true;
        break;
      }
    }

    const friendIds = [...new Set(edges.friends)];
    if (friendIds.length > 50) truncated = true;
    for (const friendId of friendIds.slice(0, 50)) {
      const followeeRows = await ctx.db
        .query("userFollows")
        .withIndex("by_follower", (q) => q.eq("followerId", friendId))
        .take(100);
      const followeeIds = new Set(followeeRows.map((row) => row.followeeId));
      for (const userId of followeeIds) {
        const candidate = candidates.get(userId) ?? {
          sharedShows: 0,
          mutualFriends: 0,
        };
        candidate.mutualFriends += 1;
        candidates.set(userId, candidate);
      }
    }

    const followingIds = new Set(edges.following);
    const included: Array<{
      user: Doc<"users">;
      sharedShows: number;
      mutualFriends: number;
    }> = [];
    for (const [userId, candidate] of candidates) {
      if (userId === me._id || followingIds.has(userId)) continue;
      if (
        candidate.sharedShows < MIN_SHARED_SHOWS_FOR_SUGGESTION &&
        candidate.mutualFriends < 1
      ) {
        continue;
      }
      const user = await cache.get(userId);
      if (user === null || !isLiveUser(user)) continue;
      included.push({ user, ...candidate });
    }
    included.sort((a, b) => {
      const scoreA = a.sharedShows * 2 + a.mutualFriends;
      const scoreB = b.sharedShows * 2 + b.mutualFriends;
      if (scoreA !== scoreB) return scoreB - scoreA;
      return a.user.name.localeCompare(b.user.name);
    });
    const followerIds = new Set(edges.followers);
    const people = [];
    for (const entry of included.slice(0, MAX_SUGGESTED_PEOPLE)) {
      const person = await toSocialPerson(ctx, entry.user, cache);
      people.push({
        userId: person.userId,
        name: person.name,
        avatarUrl: person.avatarUrl ?? undefined,
        sharedShows: entry.sharedShows,
        mutualFriends: entry.mutualFriends,
        followsMe: followerIds.has(person.userId),
      });
    }
    return { people, truncated };
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
