import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import {
  MutationCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import {
  ALL_ORGANIZATION_ROLES,
  organizationMembershipFor,
  requireOrganizationRole,
} from "./lib/authz";
import { requireUser } from "./lib/helpers";
import { insertInvite, refreshInvite } from "./lib/invites";
import { organizationPayloadValidator } from "./organizations";
import { organizationRoleValidator } from "./schema";

const invitationalOrganizationRoleValidator = v.union(
  v.literal("manager"),
  v.literal("finance"),
  v.literal("door"),
);

export const organizationMembershipPayloadValidator = v.object({
  organization: organizationPayloadValidator,
  role: organizationRoleValidator,
});

export const organizationInvitePayloadValidator = v.object({
  organizationId: v.id("organizations"),
  token: v.string(),
  role: organizationRoleValidator,
  expiresAt: v.number(),
  revoked: v.boolean(),
  expired: v.boolean(),
});

function invitePayload(
  invite: Doc<"organizationMemberInvites">,
): Infer<typeof organizationInvitePayloadValidator> {
  return {
    organizationId: invite.organizationId,
    token: invite.token,
    role: invite.role,
    expiresAt: invite.expiresAt,
    revoked: invite.revoked,
    expired: invite.expired === true,
  };
}

async function newestInvite(
  ctx: MutationCtx,
  organizationId: Id<"organizations">,
) {
  return await ctx.db
    .query("organizationMemberInvites")
    .withIndex("by_organizationId", (q) =>
      q.eq("organizationId", organizationId),
    )
    .order("desc")
    .first();
}

async function anotherOwnerExists(
  ctx: MutationCtx,
  organizationId: Id<"organizations">,
  excludedMembershipId: Id<"organizationMembers">,
): Promise<boolean> {
  const owner = await ctx.db
    .query("organizationMembers")
    .withIndex("by_organizationId_and_userId", (q) =>
      q.eq("organizationId", organizationId),
    )
    .filter((q) =>
      q.and(
        q.eq(q.field("role"), "owner"),
        q.neq(q.field("_id"), excludedMembershipId),
      ),
    )
    .first();
  return owner !== null;
}

export const list = query({
  args: { organizationId: v.id("organizations") },
  returns: v.array(
    v.object({
      userId: v.id("users"),
      name: v.string(),
      email: v.union(v.string(), v.null()),
      role: organizationRoleValidator,
      createdAt: v.number(),
    }),
  ),
  handler: async (ctx, args) => {
    const access = await requireOrganizationRole(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    const canSeeEmails =
      access.viaPlatformAdmin ||
      access.membership?.role === "owner" ||
      access.membership?.role === "manager";
    const memberships = await ctx.db
      .query("organizationMembers")
      .withIndex("by_organizationId_and_userId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .take(100);
    const result = [];
    for (const membership of memberships) {
      const user = await ctx.db.get(membership.userId);
      if (user !== null && user.deletedAt === undefined) {
        result.push({
          userId: user._id,
          name: user.name,
          email: canSeeEmails ? user.email : null,
          role: membership.role,
          createdAt: membership.createdAt,
        });
      }
    }
    return result;
  },
});

export const setRole = mutation({
  args: {
    organizationId: v.id("organizations"),
    userId: v.id("users"),
    role: organizationRoleValidator,
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, ["owner"]);
    const membership = await organizationMembershipFor(
      ctx,
      args.organizationId,
      args.userId,
    );
    if (membership === null) throw new Error("Member not found");
    if (
      membership.role === "owner" &&
      args.role !== "owner" &&
      !(await anotherOwnerExists(ctx, args.organizationId, membership._id))
    ) {
      throw new Error("An organization needs at least one owner");
    }
    await ctx.db.patch(membership._id, { role: args.role });
    return null;
  },
});

export const remove = mutation({
  args: {
    organizationId: v.id("organizations"),
    userId: v.id("users"),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const access = await requireOrganizationRole(
      ctx,
      args.organizationId,
      ALL_ORGANIZATION_ROLES,
    );
    if (
      access.membership?.role !== "owner" &&
      access.user._id !== args.userId
    ) {
      throw new Error("Not permitted for this organization");
    }
    const membership = await organizationMembershipFor(
      ctx,
      args.organizationId,
      args.userId,
    );
    if (membership === null) throw new Error("Member not found");
    if (
      membership.role === "owner" &&
      !(await anotherOwnerExists(ctx, args.organizationId, membership._id))
    ) {
      throw new Error("An organization needs at least one owner");
    }
    await ctx.db.delete(membership._id);
    return null;
  },
});

export const manageInvite = query({
  args: { organizationId: v.id("organizations") },
  returns: v.union(organizationInvitePayloadValidator, v.null()),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, ["owner"]);
    const invite = await ctx.db
      .query("organizationMemberInvites")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
      .order("desc")
      .first();
    return invite === null ? null : invitePayload(invite);
  },
});

export const createInvite = mutation({
  args: {
    organizationId: v.id("organizations"),
    role: invitationalOrganizationRoleValidator,
  },
  returns: organizationInvitePayloadValidator,
  handler: async (ctx, args) => {
    if ((args.role as string) === "owner") {
      throw new Error("Owners are added with setRole");
    }
    const access = await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
    ]);
    const existing = await newestInvite(ctx, args.organizationId);
    if (existing !== null) {
      const live =
        !existing.revoked &&
        existing.expired !== true &&
        existing.expiresAt > Date.now();
      if (live && existing.role === args.role) return invitePayload(existing);
    }
    const organizationId = existing?.organizationId ?? args.organizationId;
    const fields = {
      organizationId,
      createdBy: access.user._id,
      role: args.role,
    };
    const scheduleExpire = async (expiresAt: number, token: string) => {
      await ctx.scheduler.runAt(expiresAt, internal.organizationMembers.expire, {
        organizationId,
        token,
      });
    };
    const invite =
      existing === null
        ? await insertInvite(
            ctx,
            "organizationMemberInvites",
            fields,
            scheduleExpire,
          )
        : await refreshInvite(
            ctx,
            "organizationMemberInvites",
            existing._id,
            fields,
            scheduleExpire,
          );
    return invitePayload(invite);
  },
});

export const rotateInvite = mutation({
  args: { organizationId: v.id("organizations") },
  returns: organizationInvitePayloadValidator,
  handler: async (ctx, args) => {
    const access = await requireOrganizationRole(ctx, args.organizationId, [
      "owner",
    ]);
    const existing = await newestInvite(ctx, args.organizationId);
    const organizationId = existing?.organizationId ?? args.organizationId;
    const fields = {
      organizationId,
      createdBy: access.user._id,
      // Rotation normally follows creation, but a first call gets a safe door role.
      role: existing?.role ?? "door",
    };
    const scheduleExpire = async (expiresAt: number, token: string) => {
      await ctx.scheduler.runAt(expiresAt, internal.organizationMembers.expire, {
        organizationId,
        token,
      });
    };
    const invite =
      existing === null
        ? await insertInvite(
            ctx,
            "organizationMemberInvites",
            fields,
            scheduleExpire,
          )
        : await refreshInvite(
            ctx,
            "organizationMemberInvites",
            existing._id,
            fields,
            scheduleExpire,
          );
    return invitePayload(invite);
  },
});

export const revokeInvite = mutation({
  args: { organizationId: v.id("organizations") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await requireOrganizationRole(ctx, args.organizationId, ["owner"]);
    const existing = await newestInvite(ctx, args.organizationId);
    if (existing !== null && !existing.revoked) {
      await ctx.db.patch(existing._id, { revoked: true });
    }
    return null;
  },
});

export const resolveInvite = query({
  args: { token: v.string() },
  returns: v.union(
    v.object({
      organizationId: v.id("organizations"),
      organizationName: v.string(),
      role: organizationRoleValidator,
    }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    if (args.token.length > 200) return null;
    const invite = await ctx.db
      .query("organizationMemberInvites")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .first();
    if (invite === null || invite.revoked || invite.expired === true) {
      return null;
    }
    const organization = await ctx.db.get(invite.organizationId);
    return organization === null || organization.status === "suspended"
      ? null
      : {
          organizationId: organization._id,
          organizationName: organization.name,
          role: invite.role,
        };
  },
});

export const acceptInvite = mutation({
  args: { token: v.string() },
  returns: v.object({
    organizationId: v.id("organizations"),
    membershipCreated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const user = await requireUser(ctx);
    const invite =
      args.token.length <= 200
        ? await ctx.db
            .query("organizationMemberInvites")
            .withIndex("by_token", (q) => q.eq("token", args.token))
            .first()
        : null;
    if (
      invite === null ||
      invite.revoked ||
      invite.expired === true ||
      invite.expiresAt <= Date.now()
    ) {
      throw new Error("This invitation is no longer valid");
    }
    const organization = await ctx.db.get(invite.organizationId);
    if (organization === null || organization.status === "suspended") {
      throw new Error("This invitation is no longer valid");
    }
    const membership = await organizationMembershipFor(
      ctx,
      organization._id,
      user._id,
    );
    if (membership !== null) {
      return {
        organizationId: organization._id,
        membershipCreated: false,
      };
    }
    await ctx.db.insert("organizationMembers", {
      organizationId: organization._id,
      userId: user._id,
      role: invite.role,
      addedBy: undefined,
      createdAt: Date.now(),
    });
    return { organizationId: organization._id, membershipCreated: true };
  },
});

export const expire = internalMutation({
  args: {
    organizationId: v.id("organizations"),
    token: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const invite = await ctx.db
      .query("organizationMemberInvites")
      .withIndex("by_organizationId", (q) =>
        q.eq("organizationId", args.organizationId),
      )
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
