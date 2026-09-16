import { Infer, v } from "convex/values";
import { Doc, Id } from "../_generated/dataModel";
import { QueryCtx } from "../_generated/server";
import { DocCache } from "./docCache";

export const MAX_SOCIAL_FOLLOWS = 200;
export const MAX_FRIENDS_GOING_FRIENDS = 100;
export const MAX_RSVPS_PER_FRIEND = 50;
export const MAX_USER_SEARCH_RESULTS = 20;
export const MIN_USER_SEARCH_QUERY = 2;
/** 14 days. */
export const MAX_FRIENDS_GOING_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
export const MIN_SHARED_PAST_SHOWS = 2;
export const MAX_KNOWN_ATTENDEE_ROWS = 300;
export const MAX_KNOWN_ATTENDEE_CHECKS = 60;
// The ~4096 queries-per-function limit applies across the whole invocation,
// so this row budget bounds candidate RSVP-history reads.
export const MAX_KNOWN_ATTENDEE_RSVP_ROWS = 2500;
export const MAX_KNOWN_ATTENDEES = 20;
export const MIN_SHARED_SHOWS_FOR_SUGGESTION = 3;
export const MAX_SUGGESTED_PEOPLE = 20;

export const socialPersonValidator = v.object({
  userId: v.id("users"),
  name: v.string(),
  avatarUrl: v.union(v.string(), v.null()),
});

export const socialUserCardValidator = socialPersonValidator.extend({
  isFollowing: v.boolean(),
  followsMe: v.boolean(),
  isFriend: v.boolean(),
});

export function isLiveUser(doc: Doc<"users"> | null): boolean {
  return doc !== null && doc.deletedAt === undefined;
}

export function sharesRsvps(user: Doc<"users">): boolean {
  return user.shareRsvpsWithFriends ?? true;
}

export async function followEdges(
  ctx: QueryCtx,
  me: Doc<"users">,
): Promise<{
  following: Id<"users">[];
  followers: Id<"users">[];
  friends: Id<"users">[];
  truncated: boolean;
}> {
  const [followingRows, followerRows] = await Promise.all([
    ctx.db
      .query("userFollows")
      .withIndex("by_follower", (q) => q.eq("followerId", me._id))
      .take(MAX_SOCIAL_FOLLOWS + 1),
    ctx.db
      .query("userFollows")
      .withIndex("by_followee", (q) => q.eq("followeeId", me._id))
      .take(MAX_SOCIAL_FOLLOWS + 1),
  ]);
  const following = followingRows
    .slice(0, MAX_SOCIAL_FOLLOWS)
    .map((row) => row.followeeId);
  const followers = followerRows
    .slice(0, MAX_SOCIAL_FOLLOWS)
    .map((row) => row.followerId);
  const followerSet = new Set(followers);
  return {
    following,
    followers,
    friends: following.filter((userId) => followerSet.has(userId)),
    truncated:
      followingRows.length > MAX_SOCIAL_FOLLOWS ||
      followerRows.length > MAX_SOCIAL_FOLLOWS,
  };
}

export async function toSocialPerson(
  ctx: QueryCtx,
  user: Doc<"users">,
  cache: DocCache,
): Promise<Infer<typeof socialPersonValidator>> {
  void ctx;
  const storedAvatarUrl = user.avatarStorageId
    ? await cache.getUrl(user.avatarStorageId)
    : null;
  return {
    userId: user._id,
    name: user.name,
    avatarUrl: storedAvatarUrl ?? user.avatarUrl ?? null,
  };
}

export async function toSocialUserCard(
  ctx: QueryCtx,
  me: Doc<"users">,
  user: Doc<"users">,
  cache: DocCache,
): Promise<Infer<typeof socialUserCardValidator>> {
  const person = await toSocialPerson(ctx, user, cache);
  const [following, followsMe] = await Promise.all([
    ctx.db
      .query("userFollows")
      .withIndex("by_follower_followee", (q) =>
        q.eq("followerId", me._id).eq("followeeId", user._id),
      )
      .unique(),
    ctx.db
      .query("userFollows")
      .withIndex("by_follower_followee", (q) =>
        q.eq("followerId", user._id).eq("followeeId", me._id),
      )
      .unique(),
  ]);
  const isFollowing = following !== null;
  const followsMeValue = followsMe !== null;
  return {
    ...person,
    isFollowing,
    followsMe: followsMeValue,
    isFriend: isFollowing && followsMeValue,
  };
}
