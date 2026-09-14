import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";
import {
  MAX_FRIENDS_GOING_FRIENDS,
  MAX_FRIENDS_GOING_WINDOW_MS,
  MAX_RSVPS_PER_FRIEND,
} from "./lib/social";
import { FEED_GRACE_MS, MAX_FRIEND_RSVP_ROWS } from "./lib/helpers";

type TestConvex = ReturnType<typeof convexTest>;
const profileArgs = {
  bio: "",
  homeLocation: null,
  genres: [],
  locationPersonalizationEnabled: false,
  followedBandUpdatesEnabled: true,
};

async function user(
  t: TestConvex,
  subject: string,
  name = subject,
  email = `${subject}@example.com`,
) {
  const as = t.withIdentity({ subject, name, email });
  await as.mutation(api.users.ensureUser, {});
  const userId = (await as.query(api.users.me, {}))!._id;
  return { as, userId };
}

async function venue(t: TestConvex) {
  return await t.run((ctx) =>
    ctx.db.insert("venues", {
      name: "The Venue",
      area: "Mission, SF",
      addr: "1 Main St",
      distSF: "1 mi",
      distOak: "8 mi",
      lat: 37.75,
      lng: -122.42,
    }),
  );
}

async function gig(
  t: TestConvex,
  venueId: Id<"venues">,
  startsAt = Date.now() + 2 * 60 * 60 * 1000,
  overrides: Partial<{
    title: string;
    genres: string[];
    lifecycle: "published" | "cancelled" | "unpublished";
  }> = {},
) {
  return await t.run((ctx) =>
    ctx.db.insert("gigs", {
      title: overrides.title ?? "A Gig",
      venueId,
      price: 0,
      startsAt,
      doorsTime: "7:00 PM",
      flyKey: "paper",
      lineup: [],
      genres: overrides.genres ?? [],
      desc: "",
      ticketing: "rsvp",
      cap: "No cap",
      goingCount: 0,
      ...(overrides.lifecycle ? { lifecycle: overrides.lifecycle } : {}),
    }),
  );
}

async function follow(
  t: TestConvex,
  followerId: Id<"users">,
  followeeId: Id<"users">,
) {
  await t.run((ctx) =>
    ctx.db.insert("userFollows", { followerId, followeeId }),
  );
}

async function rsvp(t: TestConvex, userId: Id<"users">, gigId: Id<"gigs">) {
  await t.run((ctx) => ctx.db.insert("gigRsvps", { userId, gigId }));
}

describe("social", () => {
  test("toggleFollowUser throws when unauthenticated", async () => {
    const t = convexTest(schema);
    const target = await user(t, "target");
    await expect(
      t.mutation(api.social.toggleFollowUser, { userId: target.userId }),
    ).rejects.toThrow("Not signed in");
  });

  test("toggleFollowUser rejects following yourself", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    await expect(
      me.as.mutation(api.social.toggleFollowUser, { userId: me.userId }),
    ).rejects.toThrow("follow yourself");
  });

  test("toggleFollowUser rejects a deleted target", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const target = await user(t, "target");
    await t.run((ctx) =>
      ctx.db.patch(target.userId, { deletedAt: Date.now(), email: "" }),
    );
    await expect(
      me.as.mutation(api.social.toggleFollowUser, { userId: target.userId }),
    ).rejects.toThrow("User not found");
  });

  test("toggleFollowUser toggles, honours on=true idempotently and on=false removal", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const target = await user(t, "target");
    expect(
      await me.as.mutation(api.social.toggleFollowUser, {
        userId: target.userId,
      }),
    ).toEqual({ on: true });
    expect(
      await me.as.mutation(api.social.toggleFollowUser, {
        userId: target.userId,
        on: true,
      }),
    ).toEqual({ on: true });
    expect(
      await me.as.mutation(api.social.toggleFollowUser, {
        userId: target.userId,
        on: false,
      }),
    ).toEqual({ on: false });
    expect(
      await me.as.mutation(api.social.toggleFollowUser, {
        userId: target.userId,
        on: false,
      }),
    ).toEqual({ on: false });
  });

  test("mySocial returns the empty shape when unauthenticated", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.social.mySocial, {})).toEqual({
      following: [],
      followers: [],
      friends: [],
      followingCount: 0,
      followerCount: 0,
      truncated: false,
      shareRsvpsWithFriends: true,
    });
  });

  test("mySocial reports a one-way follow as following only, not friend", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const other = await user(t, "other");
    await follow(t, me.userId, other.userId);
    expect(await me.as.query(api.social.mySocial, {})).toMatchObject({
      following: [other.userId],
      followers: [],
      friends: [],
      followingCount: 1,
      followerCount: 0,
    });
  });

  test("mySocial reports mutual follows as friends and defaults shareRsvpsWithFriends to true", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const other = await user(t, "other");
    await follow(t, me.userId, other.userId);
    await follow(t, other.userId, me.userId);
    expect(await me.as.query(api.social.mySocial, {})).toMatchObject({
      friends: [other.userId],
      shareRsvpsWithFriends: true,
    });
  });

  test("updateProfile with shareRsvpsWithFriends=false is reflected by users:me and mySocial", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    await me.as.mutation(api.users.updateProfile, {
      ...profileArgs,
      name: "Me",
      shareRsvpsWithFriends: false,
    });
    expect((await me.as.query(api.users.me, {}))!.shareRsvpsWithFriends).toBe(
      false,
    );
    expect(
      (await me.as.query(api.social.mySocial, {})).shareRsvpsWithFriends,
    ).toBe(false);
  });

  test("friendsGoing returns no entries when unauthenticated", async () => {
    const t = convexTest(schema);
    expect(
      await t.query(api.social.friendsGoing, {
        from: Date.now(),
        to: Date.now() + 1000,
      }),
    ).toEqual({ entries: [], truncated: false });
  });

  test("friendsGoing returns no entries for an empty or oversized window", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    expect(
      await t.query(api.social.friendsGoing, { from: now, to: now }),
    ).toEqual({ entries: [], truncated: false });
    expect(
      await t.query(api.social.friendsGoing, {
        from: now,
        to: now + MAX_FRIENDS_GOING_WINDOW_MS + 1,
      }),
    ).toEqual({ entries: [], truncated: false });
  });

  test("friendsGoing lists a mutual friend's RSVP inside the window with name and null avatar", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend", "Friend Name");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const startsAt = Date.now() + 3 * 60 * 60 * 1000;
    const g = await gig(t, v, startsAt);
    await rsvp(t, friend.userId, g);
    expect(
      await me.as.query(api.social.friendsGoing, {
        from: startsAt - 1000,
        to: startsAt + 1000,
      }),
    ).toEqual({
      entries: [
        {
          gigId: g,
          startsAt,
          friends: [
            { userId: friend.userId, name: "Friend Name", avatarUrl: null },
          ],
        },
      ],
      truncated: false,
    });
  });

  test("friendsGoing ignores RSVPs of one-way follows in both directions", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const a = await user(t, "a");
    const b = await user(t, "b");
    await follow(t, me.userId, a.userId);
    await follow(t, b.userId, me.userId);
    const v = await venue(t);
    const g = await gig(t, v);
    await rsvp(t, a.userId, g);
    await rsvp(t, b.userId, g);
    expect(
      await me.as.query(api.social.friendsGoing, {
        from: Date.now(),
        to: Date.now() + 86_400_000,
      }),
    ).toEqual({ entries: [], truncated: false });
  });

  test("friendsGoing hides RSVPs of a friend who turned sharing off and shows them again when turned on", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const startsAt = Date.now() + 3 * 60 * 60 * 1000;
    const g = await gig(t, v, startsAt);
    await rsvp(t, friend.userId, g);
    const args = { from: startsAt - 1000, to: startsAt + 1000 };
    await friend.as.mutation(api.users.updateProfile, {
      ...profileArgs,
      name: "friend",
      shareRsvpsWithFriends: false,
    });
    expect(
      (await me.as.query(api.social.friendsGoing, args)).entries,
    ).toHaveLength(0);
    await friend.as.mutation(api.users.updateProfile, {
      ...profileArgs,
      name: "friend",
      shareRsvpsWithFriends: true,
    });
    expect(
      (await me.as.query(api.social.friendsGoing, args)).entries,
    ).toHaveLength(1);
  });

  test("friendsGoing excludes gigs before from, at or after to, and before the feed cutoff", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const now = Date.now();
    const from = now - 24 * 60 * 60 * 1000;
    const recentFrom = now - 60 * 60 * 1000;
    const to = now + 24 * 60 * 60 * 1000;
    const cutoff = now - FEED_GRACE_MS;
    const beforeFrom = await gig(t, v, recentFrom - 1);
    const atTo = await gig(t, v, to);
    const beforeCutoff = await gig(t, v, cutoff - 60_000);
    const included = await gig(t, v, recentFrom + 60_000);
    for (const id of [beforeFrom, atTo, beforeCutoff, included])
      await rsvp(t, friend.userId, id);
    const recent = await me.as.query(api.social.friendsGoing, {
      from: recentFrom,
      to,
    });
    expect(recent.entries.map((e) => e.gigId)).toEqual([included]);
    const broad = await me.as.query(api.social.friendsGoing, { from, to });
    expect(broad.entries.map((e) => e.gigId)).toEqual([beforeFrom, included]);
  });

  test("friendsGoing excludes cancelled and unpublished gigs", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const at = Date.now() + 3 * 60 * 60 * 1000;
    const cancelled = await gig(t, v, at, { lifecycle: "cancelled" });
    const unpublished = await gig(t, v, at + 1, { lifecycle: "unpublished" });
    const published = await gig(t, v, at + 2);
    for (const id of [cancelled, unpublished, published])
      await rsvp(t, friend.userId, id);
    expect(
      (
        await me.as.query(api.social.friendsGoing, {
          from: at - 1,
          to: at + 1000,
        })
      ).entries.map((e) => e.gigId),
    ).toEqual([published]);
  });

  test("friendsGoing groups several friends on one gig and orders gigs by startsAt", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const a = await user(t, "a", "A");
    const b = await user(t, "b", "B");
    for (const f of [a, b]) {
      await follow(t, me.userId, f.userId);
      await follow(t, f.userId, me.userId);
    }
    const v = await venue(t);
    const now = Date.now();
    const late = await gig(t, v, now + 5 * 3600_000);
    const early = await gig(t, v, now + 2 * 3600_000);
    await rsvp(t, a.userId, late);
    await rsvp(t, b.userId, late);
    await rsvp(t, a.userId, early);
    const entries = (
      await me.as.query(api.social.friendsGoing, {
        from: now,
        to: now + 24 * 3600_000,
      })
    ).entries;
    expect(entries.map((e) => e.gigId)).toEqual([early, late]);
    expect(entries[1].friends.map((f) => f.name)).toEqual(["A", "B"]);
  });

  test("friendsGoing excludes deleted friends", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const g = await gig(t, v);
    await rsvp(t, friend.userId, g);
    await t.run((ctx) =>
      ctx.db.patch(friend.userId, { deletedAt: Date.now(), email: "" }),
    );
    expect(
      (
        await me.as.query(api.social.friendsGoing, {
          from: Date.now(),
          to: Date.now() + 86_400_000,
        })
      ).entries,
    ).toEqual([]);
  });

  test("friendsGoing scans at most MAX_FRIENDS_GOING_FRIENDS friends and reports truncated", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    await t.run(async (ctx) => {
      for (let i = 0; i < MAX_FRIENDS_GOING_FRIENDS + 1; i++) {
        const id = await ctx.db.insert("users", {
          clerkId: `f${i}`,
          name: `F${i}`,
          email: `f${i}@x.com`,
          genres: [],
          attendedCount: 0,
        });
        await ctx.db.insert("userFollows", {
          followerId: me.userId,
          followeeId: id,
        });
        await ctx.db.insert("userFollows", {
          followerId: id,
          followeeId: me.userId,
        });
      }
    });
    expect(
      (
        await me.as.query(api.social.friendsGoing, {
          from: Date.now(),
          to: Date.now() + 86_400_000,
        })
      ).truncated,
    ).toBe(true);
  });

  test("friendsGoing reads only the newest MAX_RSVPS_PER_FRIEND RSVP rows per friend", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const friend = await user(t, "friend");
    await follow(t, me.userId, friend.userId);
    await follow(t, friend.userId, me.userId);
    const v = await venue(t);
    const now = Date.now();
    const gigs: Id<"gigs">[] = [];
    for (let i = 0; i < MAX_RSVPS_PER_FRIEND + 1; i++) {
      const g = await gig(t, v, now + (i + 1) * 1000);
      gigs.push(g);
      await rsvp(t, friend.userId, g);
    }
    const entries = (
      await me.as.query(api.social.friendsGoing, {
        from: now,
        to: now + 100_000,
      })
    ).entries;
    expect(entries).toHaveLength(MAX_RSVPS_PER_FRIEND);
    expect(entries.map((e) => e.gigId)).not.toContain(gigs[0]);
  });

  test("friendsGoing stops scanning once MAX_FRIEND_RSVP_ROWS is spent and reports truncated", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const v = await venue(t);
    const now = Date.now();
    await t.run(async (ctx) => {
      for (let i = 0; i < 60; i++) {
        const friend = await ctx.db.insert("users", {
          clerkId: `f${i}`,
          name: `F${i}`,
          email: `f${i}@x.com`,
          genres: [],
          attendedCount: 0,
        });
        await ctx.db.insert("userFollows", {
          followerId: me.userId,
          followeeId: friend,
        });
        await ctx.db.insert("userFollows", {
          followerId: friend,
          followeeId: me.userId,
        });
        const g = await ctx.db.insert("gigs", {
          title: `G${i}`,
          venueId: v,
          price: 0,
          startsAt: now + i + 1,
          doorsTime: "7",
          flyKey: "paper",
          lineup: [],
          genres: [],
          desc: "",
          ticketing: "rsvp",
          cap: "No cap",
          goingCount: 0,
        });
        for (let j = 0; j < 50; j++)
          await ctx.db.insert("gigRsvps", { userId: friend, gigId: g });
      }
    });
    const result = await me.as.query(api.social.friendsGoing, {
      from: now,
      to: now + 100_000,
    });
    expect(result.truncated).toBe(true);
    expect(result.entries.length).toBeLessThan(60);
    expect(MAX_FRIEND_RSVP_ROWS).toBe(2500);
  });

  test("searchUsers returns nothing when unauthenticated, blank, or shorter than two characters", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.social.searchUsers, { q: "a" })).toEqual([]);
    expect(await t.query(api.social.searchUsers, { q: " " })).toEqual([]);
    const me = await user(t, "me", "Alice");
    expect(await t.query(api.social.searchUsers, { q: " " })).toEqual([]);
    expect(await me.as.query(api.social.searchUsers, { q: "A" })).toEqual([]);
  });

  test("searchUsers matches names case-insensitively, excludes self and deleted users, and carries no email field", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me", "Alice");
    await user(t, "live", "Alina");
    const deleted = await user(t, "deleted", "Alison");
    await t.run((ctx) =>
      ctx.db.patch(deleted.userId, { deletedAt: Date.now(), email: "" }),
    );
    const cards = await me.as.query(api.social.searchUsers, { q: "ali" });
    expect(cards.map((c) => c.name)).toEqual(["Alina"]);
    expect(Object.keys(cards[0])).not.toContain("email");
  });

  test("searchUsers with an email returns only the exact match and nothing for a partial email", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me", "Me");
    await user(t, "other", "Other", "other@example.com");
    expect(
      (
        await me.as.query(api.social.searchUsers, { q: "other@example.com" })
      ).map((c) => c.name),
    ).toEqual(["Other"]);
    expect(await me.as.query(api.social.searchUsers, { q: "other@" })).toEqual(
      [],
    );
  });

  test("searchUsers marks isFollowing, followsMe and isFriend", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const a = await user(t, "a", "Ann");
    const b = await user(t, "b", "Bob");
    const c = await user(t, "c", "Cat");
    await follow(t, me.userId, a.userId);
    await follow(t, b.userId, me.userId);
    await follow(t, me.userId, c.userId);
    await follow(t, c.userId, me.userId);
    const [ca, cb, cc] = await Promise.all([
      me.as.query(api.social.searchUsers, { q: "Ann" }),
      me.as.query(api.social.searchUsers, { q: "Bob" }),
      me.as.query(api.social.searchUsers, { q: "Cat" }),
    ]);
    expect(ca[0]).toMatchObject({
      isFollowing: true,
      followsMe: false,
      isFriend: false,
    });
    expect(cb[0]).toMatchObject({
      isFollowing: false,
      followsMe: true,
      isFriend: false,
    });
    expect(cc[0]).toMatchObject({
      isFollowing: true,
      followsMe: true,
      isFriend: true,
    });
  });

  test("userCard returns null unauthenticated, for unknown ids and for deleted users", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const target = await user(t, "target");
    const deleted = await user(t, "deleted");
    await t.run((ctx) =>
      ctx.db.patch(deleted.userId, { deletedAt: Date.now(), email: "" }),
    );
    const unknown = await t.run((ctx) =>
      ctx.db.insert("users", {
        clerkId: "unknown",
        name: "Unknown",
        email: "u@x.com",
        genres: [],
        attendedCount: 0,
      }),
    );
    await t.run((ctx) => ctx.db.delete(unknown));
    expect(
      await t.query(api.social.userCard, { userId: target.userId }),
    ).toBeNull();
    expect(
      await me.as.query(api.social.userCard, { userId: deleted.userId }),
    ).toBeNull();
    expect(
      await me.as.query(api.social.userCard, { userId: unknown }),
    ).toBeNull();
  });

  test("userCard reports mutual followed bands and follow state", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const target = await user(t, "target");
    const band = await t.run((ctx) =>
      ctx.db.insert("bands", {
        name: "Band",
        slug: "band",
        genres: [],
        area: "SF",
        colorHex: "#000",
        initials: "B",
        followerCount: 0,
        pastShows: [],
      }),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("follows", { userId: me.userId, bandId: band });
      await ctx.db.insert("follows", { userId: target.userId, bandId: band });
    });
    await follow(t, me.userId, target.userId);
    expect(
      await me.as.query(api.social.userCard, { userId: target.userId }),
    ).toMatchObject({
      isFollowing: true,
      followsMe: false,
      isFriend: false,
      followedBandCount: 1,
      mutualBands: [{ bandId: band, name: "Band" }],
    });
  });

  test("history rows carry the gig's genres", async () => {
    const t = convexTest(schema);
    const me = await user(t, "me");
    const v = await venue(t);
    const g = await gig(t, v, Date.now() - 1000, { genres: ["punk", "jazz"] });
    await me.as.mutation(api.interactions.toggleRsvp, { gigId: g });
    expect(
      (await me.as.query(api.interactions.history, { now: Date.now() })).find(
        (row) => row.gigId === g,
      )?.genres,
    ).toEqual(["punk", "jazz"]);
  });
});
