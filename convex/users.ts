import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import {
  MutationCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import { upsertUserFromClerk } from "./lib/clerkUser";
import {
  MAX_PROFILE_BIO_LENGTH,
  MAX_PROFILE_GENRE_LENGTH,
  MAX_PROFILE_GENRES,
  MAX_PROFILE_NAME_LENGTH,
  assertUploadAcceptable,
  currentUser,
  requireUser,
  toUserPayload,
  userPayloadValidator,
} from "./lib/helpers";
import { fanCityValidator, fanOnboardingValidator } from "./schema";

function validateProfileGenres(input: string[]): string[] {
  if (input.length > MAX_PROFILE_GENRES) {
    throw new Error(`Choose at most ${MAX_PROFILE_GENRES} favorite genres.`);
  }
  const genres = input.map((genre) => genre.trim());
  if (genres.some((genre) => genre === "")) {
    throw new Error("Genres cannot be blank");
  }
  if (genres.some((genre) => genre.length > MAX_PROFILE_GENRE_LENGTH)) {
    throw new Error(
      `Genres can be at most ${MAX_PROFILE_GENRE_LENGTH} characters.`,
    );
  }
  if (new Set(genres).size !== genres.length) {
    throw new Error("Genres cannot be duplicated");
  }
  return genres;
}

async function tombstoneUser(ctx: MutationCtx, user: Doc<"users">) {
  // Keep the row and every reference to it. A hard delete would dangle user
  // ids in five tables and can leave a band with no surviving admin. A
  // cascade would also have to reproduce counter maintenance across
  // unbounded joins and would destroy RSVP history on a replayable event.
  // Blanking email keeps the tombstone out of non-empty by_email ranges so a
  // later sign-up under a new Clerk id cannot adopt this dead identity.
  if (user.deletedAt !== undefined && user.email === "") return;
  await ctx.db.patch(user._id, { deletedAt: Date.now(), email: "" });
}

export const me = query({
  args: {},
  returns: v.union(userPayloadValidator, v.null()),
  handler: async (ctx) => {
    const user = await currentUser(ctx);
    return user === null ? null : await toUserPayload(ctx, user);
  },
});

export const updateProfile = mutation({
  args: {
    name: v.string(),
    bio: v.union(v.string(), v.null()),
    homeLocation: v.union(fanCityValidator, v.null()),
    genres: v.array(v.string()),
    locationPersonalizationEnabled: v.boolean(),
    followedBandUpdatesEnabled: v.boolean(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const name = args.name.trim();
    if (name === "") throw new Error("Name cannot be blank");
    if (name.length > MAX_PROFILE_NAME_LENGTH) {
      throw new Error(
        `Name can be at most ${MAX_PROFILE_NAME_LENGTH} characters.`,
      );
    }

    const bio = args.bio?.trim() ?? "";
    if (bio.length > MAX_PROFILE_BIO_LENGTH) {
      throw new Error(
        `Bio can be at most ${MAX_PROFILE_BIO_LENGTH} characters.`,
      );
    }
    const genres = validateProfileGenres(args.genres);

    await ctx.db.patch(user._id, {
      name,
      bio: bio === "" ? undefined : bio,
      homeLocation: args.homeLocation ?? undefined,
      genres,
      locationPersonalizationEnabled: args.locationPersonalizationEnabled,
      followedBandUpdatesEnabled: args.followedBandUpdatesEnabled,
    });
    return null;
  },
});

export const generateAvatarUploadUrl = mutation({
  args: {},
  returns: v.string(),
  handler: async (ctx) => {
    await requireUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const setAvatar = mutation({
  args: { storageId: v.id("_storage") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const upload = await ctx.db.system.get("_storage", args.storageId);
    if (upload === null) throw new Error("Avatar upload not found");
    assertUploadAcceptable(
      { size: upload.size, contentType: upload.contentType },
      "photo",
    );
    await ctx.db.patch(user._id, {
      avatarStorageId: args.storageId,
      avatarUrl: undefined,
    });
    return null;
  },
});

export const clearAvatar = mutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const user = await requireUser(ctx);
    await ctx.db.patch(user._id, {
      avatarStorageId: undefined,
      avatarUrl: undefined,
    });
    return null;
  },
});

export const setProfileTutorialCompleted = mutation({
  args: { completed: v.boolean() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    await ctx.db.patch(user._id, {
      profileTutorialCompleted: args.completed,
    });
    return null;
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
    const user = await ctx.db.get(userId);
    if (user?.deletedAt !== undefined) throw new Error("Account deleted");
    return { userId };
  },
});

/** Tombstones the current Convex user while its Clerk session is still valid.
 * The client awaits this before deleting the Clerk account; the webhook is an
 * idempotent retry path, not the operation that establishes deletion safety. */
export const deleteMe = mutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) throw new Error("Not signed in");
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.subject))
      .unique();
    if (!user) throw new Error("No user record — call users:ensureUser first");
    await tombstoneUser(ctx, user);
    return null;
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
    await tombstoneUser(ctx, user);
    return { found: true };
  },
});

export const setGenres = mutation({
  args: { genres: v.array(v.string()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    await ctx.db.patch(user._id, {
      genres: validateProfileGenres(args.genres),
    });
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

    const genres =
      args.genres === undefined
        ? undefined
        : validateProfileGenres(args.genres);
    await ctx.db.patch(user._id, {
      ...(genres === undefined ? {} : { genres }),
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
