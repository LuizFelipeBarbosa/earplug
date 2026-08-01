import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";

function clerkUser(
  id: string,
  email: string,
  options: { verified?: boolean; secondaryVerified?: string } = {},
) {
  return {
    id,
    primary_email_address_id: "idn_primary",
    email_addresses: [
      {
        id: "idn_primary",
        email_address: email,
        verification: {
          status: options.verified === false ? "unverified" : "verified",
        },
      },
      ...(options.secondaryVerified === undefined
        ? []
        : [
            {
              id: "idn_secondary",
              email_address: options.secondaryVerified,
              verification: { status: "verified" },
            },
          ]),
    ],
  };
}

function blankUserFields(clerkId: string) {
  return {
    clerkId,
    name: clerkId,
    email: "",
    genres: [] as string[],
    attendedCount: 0,
  };
}

beforeEach(() => {
  vi.stubEnv("CLERK_SECRET_KEY", "sk_test_fake");
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("clerkBackfill:backfillEmails", () => {
  test("throws for a missing key before doing work", async () => {
    vi.stubEnv("CLERK_SECRET_KEY", "");
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const t = convexTest(schema);
    await expect(
      t.action(internal.clerkBackfill.backfillEmails, {}),
    ).rejects.toThrow("CLERK_SECRET_KEY is not set");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("does not fetch when there are no blank rows", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        ...blankUserFields("user_filled"),
        email: "filled@example.com",
      });
    });
    const result = await t.action(internal.clerkBackfill.backfillEmails, {});
    expect(result).toMatchObject({ scanned: 0, fetched: 0, done: true });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("defaults to dry-run and leaves rows unchanged", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", blankUserFields("user_dry_run")),
    );
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([clerkUser("user_dry_run", "dry@example.com")]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {});
    expect(result).toMatchObject({ wouldPatch: 1, patched: 0 });
    expect((await t.run(async (ctx) => ctx.db.get(userId)))?.email).toBe("");
  });

  test("writes a verified primary email and removes the row from the blank range", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", blankUserFields("user_patch"));
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([clerkUser("user_patch", "patch@example.com")]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result).toMatchObject({ patched: 1, wouldPatch: 0 });
    const remaining = await t.query(
      internal.clerkBackfill.listUsersNeedingEmail,
      { afterCreationTime: 0, batchSize: 100 },
    );
    expect(remaining.users).toHaveLength(0);
  });

  test("skips an unverified primary email", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", blankUserFields("user_unverified")),
    );
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([
              clerkUser("user_unverified", "unverified@example.com", {
                verified: false,
              }),
            ]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result.skippedNoVerifiedEmail).toBe(1);
    expect((await t.run(async (ctx) => ctx.db.get(userId)))?.email).toBe("");
  });

  test("never falls back to a verified non-primary email", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", blankUserFields("user_secondary")),
    );
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([
              clerkUser("user_secondary", "primary@example.com", {
                verified: false,
                secondaryVerified: "secondary@example.com",
              }),
            ]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result.skippedNoVerifiedEmail).toBe(1);
    expect((await t.run(async (ctx) => ctx.db.get(userId)))?.email).toBe("");
  });

  test("counts a Clerk id omitted from the response", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", blankUserFields("user_not_in_clerk"));
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify([]), { status: 200 })),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result).toMatchObject({
      fetched: 0,
      skippedNotFoundInClerk: 1,
      patched: 0,
    });
  });

  test("skips an email already held by another row", async () => {
    const t = convexTest(schema);
    const blankId = await t.run(async (ctx) => {
      const blankId = await ctx.db.insert(
        "users",
        blankUserFields("user_collision"),
      );
      await ctx.db.insert("users", {
        ...blankUserFields("user_owner"),
        email: "owner@example.com",
      });
      return blankId;
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([clerkUser("user_collision", "owner@example.com")]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result.skippedCollision).toBe(1);
    const rows = await t.run(async (ctx) => ctx.db.query("users").take(10));
    expect(rows.find((row) => row._id === blankId)?.email).toBe("");
    expect(rows.find((row) => row.clerkId === "user_owner")?.email).toBe(
      "owner@example.com",
    );
  });

  test("catches a same-email collision within one mutation batch", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", blankUserFields("user_batch_a"));
      await ctx.db.insert("users", blankUserFields("user_batch_b"));
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify([
              clerkUser("user_batch_a", "same@example.com"),
              clerkUser("user_batch_b", "same@example.com"),
            ]),
            { status: 200 },
          ),
      ),
    );

    const result = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
    });
    expect(result).toMatchObject({ patched: 1, skippedCollision: 1 });
    const rows = await t.run(async (ctx) => ctx.db.query("users").take(10));
    expect(rows.filter((row) => row.email === "same@example.com")).toHaveLength(
      1,
    );
    expect(rows.filter((row) => row.email === "")).toHaveLength(1);
  });

  test("requests every id with an explicit sufficient limit", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", blankUserFields("user_url_a"));
      await ctx.db.insert("users", blankUserFields("user_url_b"));
    });
    const fetchMock = vi.fn(async (url: string) => {
      const parsed = new URL(url);
      const ids = parsed.searchParams.getAll("user_id");
      expect(ids).toEqual(["user_url_a", "user_url_b"]);
      expect(Number(parsed.searchParams.get("limit"))).toBeGreaterThanOrEqual(
        ids.length,
      );
      return new Response(JSON.stringify([]), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);

    await t.action(internal.clerkBackfill.backfillEmails, { batchSize: 2 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("self-schedules monotonic batches until all rows are processed once", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      for (let index = 0; index < 5; index++) {
        await ctx.db.insert("users", blankUserFields(`user_page_${index}`));
      }
    });
    const requestedIds: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string) => {
        const ids = new URL(url).searchParams.getAll("user_id");
        requestedIds.push(...ids);
        return new Response(
          JSON.stringify(ids.map((id) => clerkUser(id, `${id}@example.com`))),
          { status: 200 },
        );
      }),
    );

    const first = await t.action(internal.clerkBackfill.backfillEmails, {
      dryRun: false,
      batchSize: 2,
    });
    expect(first).toMatchObject({ scanned: 2, patched: 2, done: false });
    await t.finishAllScheduledFunctions(() => vi.runAllTimers());

    const rows = await t.run(async (ctx) => ctx.db.query("users").take(10));
    expect(rows.every((row) => row.email !== "")).toBe(true);
    expect(requestedIds).toHaveLength(5);
    expect(new Set(requestedIds).size).toBe(5);
  });

  test("throws on a Clerk error without patching or scheduling", async () => {
    vi.useFakeTimers();
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) =>
      ctx.db.insert("users", blankUserFields("user_422")),
    );
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(
            JSON.stringify({
              errors: [{ message: "invalid user_id" }],
              clerk_trace_id: "trace_test",
            }),
            { status: 422 },
          ),
      ),
    );

    await expect(
      t.action(internal.clerkBackfill.backfillEmails, {
        dryRun: false,
        batchSize: 1,
      }),
    ).rejects.toThrow("status 422");
    await t.finishAllScheduledFunctions(() => vi.runAllTimers());
    expect((await t.run(async (ctx) => ctx.db.get(userId)))?.email).toBe("");
  });
});

describe("clerkBackfill:applyEmails stale-state checks", () => {
  test("skips a row filled after the action snapshot", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) => {
      const userId = await ctx.db.insert(
        "users",
        blankUserFields("user_stale"),
      );
      await ctx.db.patch(userId, { email: "live@example.com" });
      return userId;
    });
    const result = await t.mutation(internal.clerkBackfill.applyEmails, {
      updates: [{ userId, email: "stale@example.com" }],
      dryRun: false,
    });
    expect(result).toMatchObject({ skippedNotBlank: 1, patched: 0 });
    expect((await t.run(async (ctx) => ctx.db.get(userId)))?.email).toBe(
      "live@example.com",
    );
  });

  test("skips an update whose user row disappeared", async () => {
    const t = convexTest(schema);
    const userId = await t.run(async (ctx) => {
      const userId = await ctx.db.insert(
        "users",
        blankUserFields("user_missing"),
      );
      await ctx.db.delete("users", userId);
      return userId;
    });
    const result = await t.mutation(internal.clerkBackfill.applyEmails, {
      updates: [{ userId, email: "missing@example.com" }],
      dryRun: false,
    });
    expect(result).toMatchObject({ skippedMissing: 1, patched: 0 });
  });
});
