import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { upsertUserFromClerk } from "./lib/clerkUser";
import {
  currentUser,
  requireUser,
  toUserPayload,
  userPayloadValidator,
} from "./lib/helpers";
import { fanOnboardingValidator } from "./schema";

export const me = query({
  args: {},
  returns: v.union(userPayloadValidator, v.null()),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    return user === null ? null : toUserPayload(user);
  },
});

export const ensureUser = mutation({
  args: { name: v.optional(v.string()) },
  returns: v.object({ userId: v.id("users") }),
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not signed in");

    const { userId } = await upsertUserFromClerk(ctx, {
      clerkId: identity.subject,
      email: identity.email ?? "",
      emailVerified: identity.emailVerified === true,
      name: (args.name ?? identity.name) || undefined,
    });
    return { userId };
  },
});

export const syncFromClerk = internalMutation({
  args: {
    clerkId: v.string(),
    email: v.string(),
    emailVerified: v.boolean(),
    name: v.optional(v.string()),
    updatedAt: v.optional(v.number()),
    emailIsAuthoritative: v.boolean(),
  },
  returns: v.object({
    userId: v.id("users"),
    outcome: v.union(
      v.literal("created"),
      v.literal("adopted_by_clerk_id"),
      v.literal("adopted_by_email"),
    ),
    emailConflict: v.boolean(),
  }),
  handler: async (ctx, args) => {
    return await upsertUserFromClerk(ctx, args, {
      emailIsAuthoritative: args.emailIsAuthoritative,
    });
  },
});

export const markDeletedFromClerk = internalMutation({
  args: { clerkId: v.string() },
  returns: v.object({ found: v.boolean() }),
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();
    if (user === null) return { found: false };

    // Keep the row and every reference to it. A hard delete would dangle user
    // ids in five tables and can leave a band with no surviving admin. A
    // cascade would also have to reproduce counter maintenance across
    // unbounded joins and would destroy RSVP history on a replayable event.
    // Blanking email keeps the tombstone out of non-empty by_email ranges so a
    // later sign-up under a new Clerk id cannot adopt this dead identity.
    await ctx.db.patch(user._id, { deletedAt: Date.now(), email: "" });
    return { found: true };
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

export const updateFanOnboarding = mutation({
  args: {
    ...fanOnboardingValidator.partial().fields,
    genres: v.optional(v.array(v.string())),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    if (user.fanOnboarding === undefined) {
      throw new Error("Fan onboarding is not available for this account");
    }
    if (
      args.preferredCity === undefined &&
      args.genreChoice === undefined &&
      args.collapsed === undefined &&
      args.genres === undefined
    ) {
      throw new Error("No fan onboarding fields provided");
    }

    await ctx.db.patch(user._id, {
      ...(args.genres === undefined ? {} : { genres: args.genres }),
      fanOnboarding: {
        ...(user.fanOnboarding.preferredCity === undefined
          ? {}
          : { preferredCity: user.fanOnboarding.preferredCity }),
        ...(args.preferredCity === undefined
          ? {}
          : { preferredCity: args.preferredCity }),
        genreChoice: args.genreChoice ?? user.fanOnboarding.genreChoice,
        collapsed: args.collapsed ?? user.fanOnboarding.collapsed,
      },
    });
    return null;
  },
});
