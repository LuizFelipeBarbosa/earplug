import { convexTest, TestConvex } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import schema from "./schema";

type Harness = TestConvex<typeof schema>;

async function signUp(t: Harness, subject: string, name: string) {
  const as = t.withIdentity({ subject, email: `${subject}@members.test`, name });
  const { userId } = await as.mutation(api.users.ensureUser, {});
  return { as, userId };
}

/** One band with its founding admin, plus two signed-up outsiders. */
async function setupBand() {
  const t = convexTest(schema);
  const admin = await signUp(t, "members_admin", "Zed Admin");
  const { bandId } = await admin.as.mutation(api.bands.createBand, {
    name: "Membership Band",
    genres: ["punk"],
    area: "Oakland",
    bio: "",
  });
  const alice = await signUp(t, "members_alice", "Alice Member");
  const bob = await signUp(t, "members_bob", "Bob Member");
  return { t, bandId, admin, alice, bob };
}

async function bandState(t: Harness, bandId: Id<"bands">) {
  return await t.run(async (ctx) => ({
    followerCount: (await ctx.db.get(bandId))?.followerCount,
    memberships: await ctx.db
      .query("bandMembers")
      .withIndex("by_band", (q) => q.eq("bandId", bandId))
      .take(10),
  }));
}

describe("band members", () => {
  test("only members can list; the list carries name, avatar, role and isSelf", async () => {
    const { t, bandId, admin, alice } = await setupBand();
    await expect(
      t.query(api.bandMembers.list, { bandId }),
    ).rejects.toThrow("Not signed in");
    await expect(
      alice.as.query(api.bandMembers.list, { bandId }),
    ).rejects.toThrow("Not a member of this band");

    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    await t.run((ctx) =>
      ctx.db.patch(alice.userId, { avatarUrl: "https://img.test/alice.png" }),
    );

    expect(await alice.as.query(api.bandMembers.list, { bandId })).toEqual([
      {
        userId: admin.userId,
        name: "Zed Admin",
        avatarUrl: null,
        role: "admin",
        isSelf: false,
      },
      {
        userId: alice.userId,
        name: "Alice Member",
        avatarUrl: "https://img.test/alice.png",
        role: "member",
        isSelf: true,
      },
    ]);
    const asSeenByAdmin = await admin.as.query(api.bandMembers.list, {
      bandId,
    });
    expect(asSeenByAdmin.map((m) => m.isSelf)).toEqual([true, false]);
  });

  test("list orders admins first, then by name, and skips deleted users", async () => {
    const { t, bandId, admin, alice, bob } = await setupBand();
    const carol = await signUp(t, "members_carol", "Carol Deleted");
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: bob.userId,
      role: "admin",
    });
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: carol.userId,
    });
    await t.run((ctx) => ctx.db.patch(carol.userId, { deletedAt: 1 }));

    const listed = await admin.as.query(api.bandMembers.list, { bandId });
    expect(listed.map((m) => [m.name, m.role])).toEqual([
      ["Bob Member", "admin"],
      ["Zed Admin", "admin"],
      ["Alice Member", "member"],
    ]);
  });

  test("add is admin-only, defaults to member, requires a live user, and is idempotent", async () => {
    const { t, bandId, admin, alice, bob } = await setupBand();
    await expect(
      alice.as.mutation(api.bandMembers.add, { bandId, userId: bob.userId }),
    ).rejects.toThrow("Not an admin of this band");

    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    await expect(
      alice.as.mutation(api.bandMembers.add, { bandId, userId: bob.userId }),
    ).rejects.toThrow("Not an admin of this band");

    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    let state = await bandState(t, bandId);
    expect(state.followerCount).toBe(2);
    expect(state.memberships).toHaveLength(2);
    expect(
      state.memberships.find((m) => m.userId === alice.userId)?.role,
    ).toBe("member");

    await t.run((ctx) => ctx.db.patch(bob.userId, { deletedAt: 1 }));
    await expect(
      admin.as.mutation(api.bandMembers.add, { bandId, userId: bob.userId }),
    ).rejects.toThrow("User not found");
    state = await bandState(t, bandId);
    expect(state.followerCount).toBe(2);
    expect(state.memberships).toHaveLength(2);
  });

  test("setRole is admin-only, no-ops on unchanged role, and keeps the last admin", async () => {
    const { t, bandId, admin, alice, bob } = await setupBand();
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    await expect(
      alice.as.mutation(api.bandMembers.setRole, {
        bandId,
        userId: alice.userId,
        role: "admin",
      }),
    ).rejects.toThrow("Not an admin of this band");
    await expect(
      admin.as.mutation(api.bandMembers.setRole, {
        bandId,
        userId: bob.userId,
        role: "admin",
      }),
    ).rejects.toThrow("Member not found");
    await expect(
      admin.as.mutation(api.bandMembers.setRole, {
        bandId,
        userId: admin.userId,
        role: "member",
      }),
    ).rejects.toThrow("A band needs at least one admin");
    await admin.as.mutation(api.bandMembers.setRole, {
      bandId,
      userId: admin.userId,
      role: "admin",
    });

    await admin.as.mutation(api.bandMembers.setRole, {
      bandId,
      userId: alice.userId,
      role: "admin",
    });
    await alice.as.mutation(api.bandMembers.setRole, {
      bandId,
      userId: admin.userId,
      role: "member",
    });
    const { memberships, followerCount } = await bandState(t, bandId);
    expect(
      memberships.map((m) => [m.userId, m.role]).sort(),
    ).toEqual(
      [
        [admin.userId, "member"],
        [alice.userId, "admin"],
      ].sort(),
    );
    expect(followerCount).toBe(2);
  });

  test("remove: admins remove anyone, members only leave, followerCount tracks it", async () => {
    const { t, bandId, admin, alice, bob } = await setupBand();
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
    });
    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: bob.userId,
    });
    expect((await bandState(t, bandId)).followerCount).toBe(3);

    await expect(
      alice.as.mutation(api.bandMembers.remove, {
        bandId,
        userId: bob.userId,
      }),
    ).rejects.toThrow("Not an admin of this band");
    await expect(
      alice.as.mutation(api.bandMembers.remove, {
        bandId,
        userId: admin.userId,
      }),
    ).rejects.toThrow("Not an admin of this band");

    await alice.as.mutation(api.bandMembers.remove, {
      bandId,
      userId: alice.userId,
    });
    await expect(
      alice.as.query(api.bandMembers.list, { bandId }),
    ).rejects.toThrow("Not a member of this band");
    expect((await bandState(t, bandId)).followerCount).toBe(2);

    await admin.as.mutation(api.bandMembers.remove, {
      bandId,
      userId: bob.userId,
    });
    await expect(
      admin.as.mutation(api.bandMembers.remove, {
        bandId,
        userId: bob.userId,
      }),
    ).rejects.toThrow("Member not found");
    const state = await bandState(t, bandId);
    expect(state.followerCount).toBe(1);
    expect(state.memberships.map((m) => m.userId)).toEqual([admin.userId]);
  });

  test("the only admin can neither leave nor be removed until another admin exists", async () => {
    const { t, bandId, admin, alice } = await setupBand();
    await expect(
      admin.as.mutation(api.bandMembers.remove, {
        bandId,
        userId: admin.userId,
      }),
    ).rejects.toThrow("A band needs at least one admin");

    await admin.as.mutation(api.bandMembers.add, {
      bandId,
      userId: alice.userId,
      role: "admin",
    });
    await admin.as.mutation(api.bandMembers.remove, {
      bandId,
      userId: admin.userId,
    });
    const state = await bandState(t, bandId);
    expect(state.followerCount).toBe(1);
    expect(state.memberships.map((m) => [m.userId, m.role])).toEqual([
      [alice.userId, "admin"],
    ]);
  });
});
