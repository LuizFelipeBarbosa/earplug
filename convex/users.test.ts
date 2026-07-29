import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

describe("users:ensureUser", () => {
  test("throws when unauthenticated", async () => {
    const t = convexTest(schema);
    await expect(t.mutation(api.users.ensureUser, {})).rejects.toThrow(
      "Not signed in",
    );
  });

  test("creates a user and is idempotent", async () => {
    const t = convexTest(schema);
    const asSam = t.withIdentity({
      subject: "user_sam",
      email: "sam@example.com",
      name: "Sam Reyes",
    });
    const first = await asSam.mutation(api.users.ensureUser, {});
    const second = await asSam.mutation(api.users.ensureUser, {});
    expect(second.userId).toBe(first.userId);

    const me = await asSam.query(api.users.me, {});
    expect(me).not.toBeNull();
    expect(me!.clerkId).toBe("user_sam");
    expect(me!.name).toBe("Sam Reyes");
    expect(me!.email).toBe("sam@example.com");
    expect(me!.genres).toEqual([]);
    expect(me!.attendedCount).toBe(0);

    const count = await t.run(
      async (ctx) => (await ctx.db.query("users").take(10)).length,
    );
    expect(count).toBe(1);
  });

  // 25 migrated rows have an empty email — Clerk never gave the legacy app one.
  test("adopts an existing row by clerkId and backfills empty email", async () => {
    const t = convexTest(schema);
    const existingId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_legacy1",
        name: "Luiz B.",
        email: "",
        genres: [],
        attendedCount: 0,
      }),
    );
    const asLegacy = t.withIdentity({
      subject: "user_legacy1",
      email: "luiz@example.com",
    });
    const { userId } = await asLegacy.mutation(api.users.ensureUser, {});
    expect(userId).toBe(existingId);

    const row = await t.run(async (ctx) => ctx.db.get(existingId));
    expect(row!.email).toBe("luiz@example.com"); // backfilled
    expect(row!.name).toBe("Luiz B."); // kept
  });

  test("adopts by email only on a unique match", async () => {
    const t = convexTest(schema);
    const uniqueId = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        clerkId: "user_old_instance_a",
        name: "Anandi J.",
        email: "anandi@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );
    const asAnandi = t.withIdentity({
      subject: "user_new_a",
      email: "anandi@example.com",
    });
    const { userId } = await asAnandi.mutation(api.users.ensureUser, {});
    expect(userId).toBe(uniqueId);
    const row = await t.run(async (ctx) => ctx.db.get(uniqueId));
    expect(row!.clerkId).toBe("user_new_a");
  });

  test("does NOT adopt by email when the match is ambiguous", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "user_dup_1",
        name: "Dup One",
        email: "dup@example.com",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("users", {
        clerkId: "user_dup_2",
        name: "Dup Two",
        email: "dup@example.com",
        genres: [],
        attendedCount: 0,
      });
    });
    const asDup = t.withIdentity({
      subject: "user_dup_new",
      email: "dup@example.com",
    });
    await asDup.mutation(api.users.ensureUser, {});
    const users = await t.run(async (ctx) => ctx.db.query("users").take(10));
    expect(users.length).toBe(3); // fresh row, neither dup adopted
    expect(users.filter((u) => u.clerkId === "user_dup_new").length).toBe(1);
  });
});

describe("users:setGenres", () => {
  test("requires auth and updates genres", async () => {
    const t = convexTest(schema);
    await expect(
      t.mutation(api.users.setGenres, { genres: ["punk"] }),
    ).rejects.toThrow();
    const asSam = t.withIdentity({ subject: "user_sam", email: "s@x.com" });
    await asSam.mutation(api.users.ensureUser, {});
    await asSam.mutation(api.users.setGenres, { genres: ["punk", "garage"] });
    const me = await asSam.query(api.users.me, {});
    expect(me!.genres).toEqual(["punk", "garage"]);
  });
});
