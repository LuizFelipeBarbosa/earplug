import { v } from "convex/values";
import { Doc } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import {
  MutationCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import {
  requireBandAdmin,
  requireBandAdminQuery,
  requireUser,
} from "./lib/helpers";

const INVITE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;

const invitePayloadValidator = v.object({
  bandId: v.id("bands"),
  token: v.string(),
  expiresAt: v.number(),
  revoked: v.boolean(),
  expired: v.boolean(),
});

const resolutionValidator = v.object({
  bandId: v.id("bands"),
  bandName: v.string(),
  initials: v.string(),
  colorHex: v.string(),
});

function invitePayload(invite: Doc<"bandInvites">) {
  return {
    bandId: invite.bandId,
    token: invite.token,
    expiresAt: invite.expiresAt,
    revoked: invite.revoked,
    expired: invite.expired === true,
  };
}

async function uniqueToken(ctx: MutationCtx): Promise<string> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const bytes = new Uint8Array(32);
    // Convex supplies a seeded strong PRNG inside mutations so retries replay
    // the same result while distinct calls receive fresh entropy.
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    const token = Array.from(bytes, (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
    const collision = await ctx.db
      .query("bandInvites")
      .withIndex("by_token", (q) => q.eq("token", token))
      .first();
    if (collision === null) return token;
  }
  throw new Error("Could not issue invitation token");
}

async function insertInvite(
  ctx: MutationCtx,
  bandId: Doc<"bands">["_id"],
  createdBy: Doc<"users">["_id"],
) {
  const token = await uniqueToken(ctx);
  const expiresAt = Date.now() + INVITE_LIFETIME_MS;
  const inviteId = await ctx.db.insert("bandInvites", {
    bandId,
    token,
    createdBy,
    expiresAt,
    revoked: false,
    expired: false,
  });
  await ctx.scheduler.runAt(expiresAt, internal.bandInvites.expire, {
    bandId,
    token,
  });
  const invite = await ctx.db.get(inviteId);
  if (!invite) throw new Error("Created invitation not found");
  return invitePayload(invite);
}

async function refreshInvite(
  ctx: MutationCtx,
  invite: Doc<"bandInvites">,
  createdBy: Doc<"users">["_id"],
) {
  const replacement = {
    bandId: invite.bandId,
    token: await uniqueToken(ctx),
    createdBy,
    expiresAt: Date.now() + INVITE_LIFETIME_MS,
    revoked: false,
    expired: false,
  };
  await ctx.db.replace(invite._id, replacement);
  await ctx.scheduler.runAt(
    replacement.expiresAt,
    internal.bandInvites.expire,
    { bandId: replacement.bandId, token: replacement.token },
  );
  return {
    bandId: replacement.bandId,
    token: replacement.token,
    expiresAt: replacement.expiresAt,
    revoked: replacement.revoked,
    expired: replacement.expired,
  };
}

/** Materializes expiry so the public resolver never trusts a client clock.
 * The token guard makes a delayed job from a rotation harmless. */
export const expire = internalMutation({
  args: { bandId: v.id("bands"), token: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const invite = await ctx.db
      .query("bandInvites")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .first();
    if (
      invite !== null &&
      invite.token === args.token &&
      !invite.revoked &&
      invite.expired !== true
    ) {
      await ctx.db.patch(invite._id, { expired: true });
    }
    return null;
  },
});

/** Admin-only status for the newest reusable link, including revoked/expired
 * state so the management UI can offer rotation instead of hiding history. */
export const manage = query({
  args: { bandId: v.id("bands") },
  returns: v.union(invitePayloadValidator, v.null()),
  handler: async (ctx, args) => {
    await requireBandAdminQuery(ctx, args.bandId);
    const invite = await ctx.db
      .query("bandInvites")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .first();
    return invite === null ? null : invitePayload(invite);
  },
});

export const create = mutation({
  args: { bandId: v.id("bands") },
  returns: invitePayloadValidator,
  handler: async (ctx, args) => {
    const user = await requireBandAdmin(ctx, args.bandId);
    const existing = await ctx.db
      .query("bandInvites")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .first();
    if (existing === null) {
      return await insertInvite(ctx, args.bandId, user._id);
    }
    return !existing.revoked &&
      existing.expired !== true &&
      existing.expiresAt > Date.now()
      ? invitePayload(existing)
      : await refreshInvite(ctx, existing, user._id);
  },
});

export const rotate = mutation({
  args: { bandId: v.id("bands") },
  returns: invitePayloadValidator,
  handler: async (ctx, args) => {
    const user = await requireBandAdmin(ctx, args.bandId);
    const existing = await ctx.db
      .query("bandInvites")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .first();
    if (existing === null) {
      return await insertInvite(ctx, args.bandId, user._id);
    }
    return await refreshInvite(ctx, existing, user._id);
  },
});

export const revoke = mutation({
  args: { bandId: v.id("bands") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const existing = await ctx.db
      .query("bandInvites")
      .withIndex("by_band", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .first();
    if (existing !== null && !existing.revoked) {
      await ctx.db.patch(existing._id, { revoked: true });
    }
    return null;
  },
});

/** Public and deliberately minimal. Expiry is materialized by the scheduled
 * internal mutation above, so authorization never depends on a client clock. */
export const resolve = query({
  args: {
    token: v.string(),
    // Deprecated compatibility input. Expiry is materialized server-side and
    // this value is never consulted for authorization.
    now: v.optional(v.number()),
  },
  returns: v.union(resolutionValidator, v.null()),
  handler: async (ctx, args) => {
    if (args.token.length > 200) return null;
    const invite = await ctx.db
      .query("bandInvites")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();
    if (invite === null || invite.revoked || invite.expired === true) {
      return null;
    }
    const band = await ctx.db.get(invite.bandId);
    return band === null || band.archivedAt !== undefined
      ? null
      : {
          bandId: band._id,
          bandName: band.name,
          initials: band.initials,
          colorHex: band.colorHex,
        };
  },
});

export const accept = mutation({
  args: { token: v.string() },
  returns: v.object({
    bandId: v.id("bands"),
    membershipCreated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const invite =
      args.token.length <= 200
        ? await ctx.db
            .query("bandInvites")
            .withIndex("by_token", (q) => q.eq("token", args.token))
            .first()
        : null;
    if (
      invite === null ||
      invite.revoked ||
      invite.expired === true ||
      invite.expiresAt <= Date.now()
    ) {
      throw new Error("Invitation is no longer active");
    }
    const band = await ctx.db.get(invite.bandId);
    if (!band || band.archivedAt !== undefined) {
      throw new Error("Invitation is no longer active");
    }

    const membership = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", band._id).eq("userId", user._id),
      )
      .unique();
    if (membership) {
      return { bandId: band._id, membershipCreated: false };
    }

    await ctx.db.insert("bandMembers", {
      bandId: band._id,
      userId: user._id,
      role: "member",
    });
    await ctx.db.patch(band._id, {
      followerCount: band.followerCount + 1,
    });
    return { bandId: band._id, membershipCreated: true };
  },
});
