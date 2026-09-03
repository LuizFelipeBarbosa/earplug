import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";
import { requireUser } from "./helpers";

export type OrganizationRole = "owner" | "manager" | "finance" | "door";

export const ALL_ORGANIZATION_ROLES: readonly OrganizationRole[] = [
  "owner",
  "manager",
  "finance",
  "door",
];

export async function isPlatformAdmin(
  ctx: QueryCtx | MutationCtx,
  userId: Id<"users">,
): Promise<boolean> {
  const activeGrant = await ctx.db
    .query("platformAdmins")
    .withIndex("by_userId", (q) => q.eq("userId", userId))
    .filter((q) => q.eq(q.field("revokedAt"), undefined))
    .first();
  return activeGrant !== null;
}

export async function requirePlatformAdmin(
  ctx: QueryCtx,
): Promise<Doc<"users">> {
  const user = await requireUser(ctx);
  if (!(await isPlatformAdmin(ctx, user._id))) {
    throw new Error("Not an EarPlug admin");
  }
  return user;
}

export const requirePlatformAdminQuery = requirePlatformAdmin;

export async function organizationMembershipFor(
  ctx: QueryCtx | MutationCtx,
  organizationId: Id<"organizations">,
  userId: Id<"users">,
): Promise<Doc<"organizationMembers"> | null> {
  return await ctx.db
    .query("organizationMembers")
    .withIndex("by_organizationId_and_userId", (q) =>
      q.eq("organizationId", organizationId).eq("userId", userId),
    )
    .unique();
}

export type OrganizationAccess = {
  organization: Doc<"organizations">;
  user: Doc<"users">;
  membership: Doc<"organizationMembers"> | null;
  viaPlatformAdmin: boolean;
};

async function organizationAccessFor(
  ctx: QueryCtx | MutationCtx,
  organizationId: Id<"organizations">,
  roles: readonly OrganizationRole[],
  user: Doc<"users">,
): Promise<OrganizationAccess> {
  const organization = await ctx.db.get(organizationId);
  if (!organization) throw new Error("Organization not found");

  const viaPlatformAdmin = await isPlatformAdmin(ctx, user._id);
  if (organization.status === "suspended" && !viaPlatformAdmin) {
    throw new Error("Organization suspended");
  }

  const membership = await organizationMembershipFor(
    ctx,
    organizationId,
    user._id,
  );
  if (membership && roles.includes(membership.role)) {
    return { organization, user, membership, viaPlatformAdmin: false };
  }
  if (viaPlatformAdmin) {
    return { organization, user, membership, viaPlatformAdmin: true };
  }
  throw new Error("Not permitted for this organization");
}

export async function requireOrganizationRole(
  ctx: QueryCtx,
  organizationId: Id<"organizations">,
  roles: readonly OrganizationRole[],
): Promise<OrganizationAccess> {
  const user = await requireUser(ctx);
  return await organizationAccessFor(ctx, organizationId, roles, user);
}

export const requireOrganizationRoleQuery = requireOrganizationRole;
