import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import {
  internalAction,
  internalMutation,
  internalQuery,
} from "./_generated/server";
import { verifiedPrimaryEmail } from "./lib/clerkUser";

const MAX_BATCH_SIZE = 100;

const applyResultValidator = v.object({
  patched: v.number(),
  wouldPatch: v.number(),
  skippedNotBlank: v.number(),
  skippedCollision: v.number(),
  skippedMissing: v.number(),
});

type ApplyResult = {
  patched: number;
  wouldPatch: number;
  skippedNotBlank: number;
  skippedCollision: number;
  skippedMissing: number;
};

type BackfillResult = ApplyResult & {
  scanned: number;
  fetched: number;
  skippedNoVerifiedEmail: number;
  skippedNotFoundInClerk: number;
  done: boolean;
  nextAfterCreationTime: number;
};

export const listUsersNeedingEmail = internalQuery({
  args: { afterCreationTime: v.number(), batchSize: v.number() },
  returns: v.object({
    users: v.array(
      v.object({
        userId: v.id("users"),
        clerkId: v.string(),
        creationTime: v.number(),
      }),
    ),
    lastCreationTime: v.number(),
    isDone: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const users = await ctx.db
      .query("users")
      .withIndex("by_email", (q) =>
        q.eq("email", "").gt("_creationTime", args.afterCreationTime),
      )
      .take(args.batchSize);
    return {
      users: users.map((user) => ({
        userId: user._id,
        clerkId: user.clerkId,
        creationTime: user._creationTime,
      })),
      lastCreationTime:
        users.length === 0
          ? args.afterCreationTime
          : users[users.length - 1]._creationTime,
      isDone: users.length < args.batchSize,
    };
  },
});

export const applyEmails = internalMutation({
  args: {
    updates: v.array(v.object({ userId: v.id("users"), email: v.string() })),
    dryRun: v.boolean(),
  },
  returns: applyResultValidator,
  handler: async (ctx, args): Promise<ApplyResult> => {
    const result: ApplyResult = {
      patched: 0,
      wouldPatch: 0,
      skippedNotBlank: 0,
      skippedCollision: 0,
      skippedMissing: 0,
    };

    for (const update of args.updates) {
      // Re-read every assumption inside the write transaction. The action's
      // query snapshot is stale after the Clerk network round trip.
      const user = await ctx.db.get("users", update.userId);
      if (user === null) {
        result.skippedMissing++;
        continue;
      }
      if (user.deletedAt !== undefined) {
        console.warn(`Skipping tombstoned user ${update.userId}`);
        continue;
      }
      if (user.email !== "") {
        result.skippedNotBlank++;
        continue;
      }

      const collision = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", update.email))
        .take(1);
      if (collision.length > 0) {
        result.skippedCollision++;
        console.warn(
          `${update.userId} <- ${update.email} (already on ${collision[0]._id})`,
        );
        continue;
      }

      if (args.dryRun) {
        result.wouldPatch++;
      } else {
        await ctx.db.patch(update.userId, { email: update.email });
        result.patched++;
      }
    }
    return result;
  },
});

export const backfillEmails = internalAction({
  args: {
    dryRun: v.optional(v.boolean()),
    batchSize: v.optional(v.number()),
    afterCreationTime: v.optional(v.number()),
  },
  returns: v.object({
    scanned: v.number(),
    fetched: v.number(),
    patched: v.number(),
    wouldPatch: v.number(),
    skippedNoVerifiedEmail: v.number(),
    skippedNotFoundInClerk: v.number(),
    skippedCollision: v.number(),
    skippedNotBlank: v.number(),
    skippedMissing: v.number(),
    done: v.boolean(),
    nextAfterCreationTime: v.number(),
  }),
  handler: async (ctx, args): Promise<BackfillResult> => {
    const secretKey = process.env.CLERK_SECRET_KEY;
    if (!secretKey) throw new Error("CLERK_SECRET_KEY is not set");

    const dryRun = args.dryRun ?? true;
    const batchSize = args.batchSize ?? MAX_BATCH_SIZE;
    const afterCreationTime = args.afterCreationTime ?? 0;
    if (
      !Number.isInteger(batchSize) ||
      batchSize < 1 ||
      batchSize > MAX_BATCH_SIZE
    ) {
      throw new Error("batchSize must be an integer between 1 and 100");
    }

    const page: {
      users: Array<{
        userId: Id<"users">;
        clerkId: string;
        creationTime: number;
      }>;
      lastCreationTime: number;
      isDone: boolean;
    } = await ctx.runQuery(internal.clerkBackfill.listUsersNeedingEmail, {
      afterCreationTime,
      batchSize,
    });

    if (page.users.length === 0) {
      const emptyResult: BackfillResult = {
        scanned: 0,
        fetched: 0,
        patched: 0,
        wouldPatch: 0,
        skippedNoVerifiedEmail: 0,
        skippedNotFoundInClerk: 0,
        skippedCollision: 0,
        skippedNotBlank: 0,
        skippedMissing: 0,
        done: page.isDone,
        nextAfterCreationTime: page.lastCreationTime,
      };
      console.log(
        `clerkBackfill scanned=0 fetched=0 patched=0 wouldPatch=0 done=${page.isDone}`,
      );
      return emptyResult;
    }

    const search = new URLSearchParams();
    // Clerk defaults limit to 10. It must cover every requested id or a
    // 100-user request silently looks like 90 missing Clerk users.
    search.set("limit", String(page.users.length));
    for (const user of page.users) search.append("user_id", user.clerkId);
    const response = await fetch(
      `https://api.clerk.com/v1/users?${search.toString()}`,
      { headers: { Authorization: `Bearer ${secretKey}` } },
    );
    const responseBody: unknown = await response.json().catch(() => null);
    if (!response.ok) {
      const errorObject =
        typeof responseBody === "object" && responseBody !== null
          ? (responseBody as Record<string, unknown>)
          : {};
      console.error(
        `Clerk users fetch failed: errors=${JSON.stringify(errorObject.errors ?? null)} clerk_trace_id=${String(errorObject.clerk_trace_id ?? "unknown")}`,
      );
      throw new Error(
        `Clerk users fetch failed with status ${response.status}`,
      );
    }
    if (!Array.isArray(responseBody)) {
      throw new Error("Clerk users response was not an array");
    }

    const returnedById = new Map<string, unknown>();
    for (const user of responseBody) {
      if (typeof user !== "object" || user === null) continue;
      const id = (user as Record<string, unknown>).id;
      if (typeof id === "string") returnedById.set(id, user);
    }

    const missingClerkIds: string[] = [];
    const updates: Array<{ userId: Id<"users">; email: string }> = [];
    let fetched = 0;
    let skippedNoVerifiedEmail = 0;
    for (const user of page.users) {
      const clerkUser = returnedById.get(user.clerkId);
      if (clerkUser === undefined) {
        missingClerkIds.push(user.clerkId);
        continue;
      }
      fetched++;
      const email = verifiedPrimaryEmail(clerkUser);
      if (email === null) {
        skippedNoVerifiedEmail++;
        continue;
      }
      updates.push({ userId: user.userId, email });
    }
    if (missingClerkIds.length > 0) {
      console.warn(
        `Clerk returned no user for ${missingClerkIds.length} ids; sample=${missingClerkIds.slice(0, 10).join(",")}`,
      );
    }

    const applied: ApplyResult = await ctx.runMutation(
      internal.clerkBackfill.applyEmails,
      { updates, dryRun },
    );
    const result: BackfillResult = {
      scanned: page.users.length,
      fetched,
      ...applied,
      skippedNoVerifiedEmail,
      skippedNotFoundInClerk: missingClerkIds.length,
      done: page.isDone,
      nextAfterCreationTime: page.lastCreationTime,
    };
    console.log(
      `clerkBackfill scanned=${result.scanned} fetched=${result.fetched} patched=${result.patched} wouldPatch=${result.wouldPatch} noVerifiedEmail=${result.skippedNoVerifiedEmail} notFound=${result.skippedNotFoundInClerk} collisions=${result.skippedCollision} done=${result.done}`,
    );

    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.clerkBackfill.backfillEmails, {
        dryRun,
        batchSize,
        afterCreationTime: page.lastCreationTime,
      });
    }
    return result;
  },
});
