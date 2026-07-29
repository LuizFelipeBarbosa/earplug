import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import {
  currentUser,
  requireUser,
  toUserPayload,
  userPayloadValidator,
} from "./lib/helpers";

export const me = query({
  args: {},
  returns: v.union(userPayloadValidator, v.null()),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    return user === null ? null : toUserPayload(user);
  },
});

/**
 * Idempotent upsert keyed on identity.subject. Adoption order:
 *  1. clerkId match (total on the migrated dataset).
 *  2. email fallback — unique-match-only (25 legacy rows have empty email and
 *     one email appears on 3 accounts; a non-unique match must NOT adopt).
 *  3. Insert a fresh user.
 * Backfills empty email (and missing name) from the Clerk identity.
 */
export const ensureUser = mutation({
  args: { name: v.optional(v.string()) },
  returns: v.object({ userId: v.id("users") }),
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not signed in");

    const identityEmail = typeof identity.email === "string" ? identity.email : "";
    const identityName =
      args.name ??
      (typeof identity.name === "string" && identity.name !== ""
        ? identity.name
        : undefined);

    // 1. Adopt by clerkId.
    const byClerkId = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.subject))
      .unique();
    if (byClerkId) {
      const patch: { email?: string; name?: string } = {};
      if (byClerkId.email === "" && identityEmail !== "") {
        patch.email = identityEmail;
      }
      if (byClerkId.name === "" && identityName !== undefined) {
        patch.name = identityName;
      }
      if (Object.keys(patch).length > 0) {
        await ctx.db.patch(byClerkId._id, patch);
      }
      return { userId: byClerkId._id };
    }

    // 2. Email fallback — adopt only when exactly one non-empty match exists.
    if (identityEmail !== "") {
      const byEmail = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", identityEmail))
        .take(2);
      if (byEmail.length === 1) {
        const adopted = byEmail[0];
        await ctx.db.patch(adopted._id, {
          clerkId: identity.subject,
          ...(adopted.name === "" && identityName !== undefined
            ? { name: identityName }
            : {}),
        });
        return { userId: adopted._id };
      }
    }

    // 3. Fresh user.
    const userId = await ctx.db.insert("users", {
      clerkId: identity.subject,
      name: identityName ?? (identityEmail !== "" ? identityEmail.split("@")[0] : "Music fan"),
      email: identityEmail,
      genres: [],
      attendedCount: 0,
    });
    return { userId };
  },
});

export const setGenres = mutation({
  args: { genres: v.array(v.string()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    await ctx.db.patch(user._id, { genres: args.genres });
    return null;
  },
});
