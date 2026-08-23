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
    expect(me!.fanOnboarding).toEqual({
      preferredCity: null,
      genreChoice: "pending",
      collapsed: false,
    });

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
    expect(row!.fanOnboarding).toBeUndefined();
    expect((await asLegacy.query(api.users.me, {}))!.fanOnboarding).toBeNull();
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
      emailVerified: true,
    });
    const { userId } = await asAnandi.mutation(api.users.ensureUser, {});
    expect(userId).toBe(uniqueId);
    const row = await t.run(async (ctx) => ctx.db.get(uniqueId));
    expect(row!.clerkId).toBe("user_new_a");
    expect(row!.fanOnboarding).toBeUndefined();
  });

  test("does NOT adopt unique email matches that are unverified", async () => {
    const t = convexTest(schema);
    const [falseVerifiedLegacyId, omittedVerifiedLegacyId] = await t.run(
      async (ctx) => [
        await ctx.db.insert("users", {
          clerkId: "user_unverified_false_old",
          name: "False Verified",
          email: "false-verified@example.com",
          genres: [],
          attendedCount: 0,
        }),
        await ctx.db.insert("users", {
          clerkId: "user_unverified_omitted_old",
          name: "Omitted Verified",
          email: "omitted-verified@example.com",
          genres: [],
          attendedCount: 0,
        }),
      ],
    );

    const asFalseVerified = t.withIdentity({
      subject: "user_unverified_false_new",
      email: "false-verified@example.com",
      emailVerified: false,
    });
    const asOmittedVerified = t.withIdentity({
      subject: "user_unverified_omitted_new",
      email: "omitted-verified@example.com",
    });
    const falseVerified = await asFalseVerified.mutation(
      api.users.ensureUser,
      {},
    );
    const omittedVerified = await asOmittedVerified.mutation(
      api.users.ensureUser,
      {},
    );

    expect(falseVerified.userId).not.toBe(falseVerifiedLegacyId);
    expect(omittedVerified.userId).not.toBe(omittedVerifiedLegacyId);
    const rows = await t.run(async (ctx) => ({
      falseVerifiedLegacy: await ctx.db.get(falseVerifiedLegacyId),
      omittedVerifiedLegacy: await ctx.db.get(omittedVerifiedLegacyId),
      falseVerifiedFresh: await ctx.db.get(falseVerified.userId),
      omittedVerifiedFresh: await ctx.db.get(omittedVerified.userId),
    }));
    expect(rows.falseVerifiedLegacy?.clerkId).toBe(
      "user_unverified_false_old",
    );
    expect(rows.omittedVerifiedLegacy?.clerkId).toBe(
      "user_unverified_omitted_old",
    );
    expect(rows.falseVerifiedFresh?.clerkId).toBe(
      "user_unverified_false_new",
    );
    expect(rows.omittedVerifiedFresh?.clerkId).toBe(
      "user_unverified_omitted_new",
    );
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

  test("skips blank-email backfill when another row holds the address", async () => {
    const t = convexTest(schema);
    const blankId = await t.run(async (ctx) => {
      const blankId = await ctx.db.insert("users", {
        clerkId: "user_blank_collision",
        name: "Blank Email",
        email: "",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("users", {
        clerkId: "user_email_owner",
        name: "Email Owner",
        email: "shared@example.com",
        genres: [],
        attendedCount: 0,
      });
      return blankId;
    });

    const asBlank = t.withIdentity({
      subject: "user_blank_collision",
      email: "shared@example.com",
    });
    const result = await asBlank.mutation(api.users.ensureUser, {});

    expect(result.userId).toBe(blankId);
    expect((await t.run(async (ctx) => ctx.db.get(blankId)))?.email).toBe("");
  });
});

describe("users:me", () => {
  test("is null when unauthenticated, never a throw", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.users.me, {})).toBeNull();
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
    expect(me!.fanOnboarding?.genreChoice).toBe("pending");
  });
});

describe("users:updateFanOnboarding", () => {
  test("requires auth and rejects accounts that were not enrolled", async () => {
    const t = convexTest(schema);
    await expect(
      t.mutation(api.users.updateFanOnboarding, { collapsed: true }),
    ).rejects.toThrow("Not signed in");

    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "user_legacy",
        name: "Legacy Fan",
        email: "legacy@example.com",
        genres: [],
        attendedCount: 0,
      });
    });
    const asLegacy = t.withIdentity({ subject: "user_legacy" });
    await expect(
      asLegacy.mutation(api.users.updateFanOnboarding, { collapsed: true }),
    ).rejects.toThrow("Fan onboarding is not available for this account");
  });

  test("applies partial updates without erasing other onboarding state", async () => {
    const t = convexTest(schema);
    const asSam = t.withIdentity({ subject: "user_sam", email: "s@x.com" });
    await asSam.mutation(api.users.ensureUser, {});

    await asSam.mutation(api.users.updateFanOnboarding, {
      preferredCity: "oak",
    });
    await asSam.mutation(api.users.updateFanOnboarding, { collapsed: true });

    expect((await asSam.query(api.users.me, {}))!.fanOnboarding).toEqual({
      preferredCity: "oak",
      genreChoice: "pending",
      collapsed: true,
    });
  });

  test("records genres and an explicit choice atomically", async () => {
    const t = convexTest(schema);
    const asSam = t.withIdentity({ subject: "user_sam", email: "s@x.com" });
    await asSam.mutation(api.users.ensureUser, {});
    await asSam.mutation(api.users.setGenres, { genres: ["punk"] });

    await asSam.mutation(api.users.updateFanOnboarding, {
      genreChoice: "open",
      genres: [],
    });

    const me = await asSam.query(api.users.me, {});
    expect(me!.genres).toEqual([]);
    expect(me!.fanOnboarding?.genreChoice).toBe("open");
  });

  test("validates city and genre choice and rejects empty updates", async () => {
    const t = convexTest(schema);
    const asSam = t.withIdentity({ subject: "user_sam", email: "s@x.com" });
    await asSam.mutation(api.users.ensureUser, {});

    await expect(
      asSam.mutation(api.users.updateFanOnboarding, {
        preferredCity: "berkeley" as "sf",
      }),
    ).rejects.toThrow();
    await expect(
      asSam.mutation(api.users.updateFanOnboarding, {
        genreChoice: "skipped" as "pending",
      }),
    ).rejects.toThrow();
    await expect(
      asSam.mutation(api.users.updateFanOnboarding, {}),
    ).rejects.toThrow("No fan onboarding fields provided");
  });
});
