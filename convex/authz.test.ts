import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import {
  isPlatformAdmin,
  requireOrganizationRole,
  requireOrganizationRoleQuery,
  requirePlatformAdmin,
  requirePlatformAdminQuery,
} from "./lib/authz";
import schema from "./schema";

describe("platform authorization", () => {
  test("recognizes active, absent, and revoked admin grants", async () => {
    const t = convexTest(schema);
    const active = t.withIdentity({
      subject: "active_admin",
      email: "active@example.com",
      name: "Active Admin",
    });
    const regular = t.withIdentity({
      subject: "regular_user",
      email: "regular@example.com",
      name: "Regular User",
    });
    const revoked = t.withIdentity({
      subject: "revoked_admin",
      email: "revoked@example.com",
      name: "Revoked Admin",
    });
    await active.mutation(api.users.ensureUser, {});
    await regular.mutation(api.users.ensureUser, {});
    await revoked.mutation(api.users.ensureUser, {});

    const users = await t.run(async (ctx) => {
      const activeUser = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "active_admin"))
        .unique();
      const regularUser = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "regular_user"))
        .unique();
      const revokedUser = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "revoked_admin"))
        .unique();
      if (!activeUser || !regularUser || !revokedUser) {
        throw new Error("Test users missing");
      }
      await ctx.db.insert("platformAdmins", {
        userId: activeUser._id,
        grantedAt: 0,
        revokedAt: 1,
      });
      await ctx.db.insert("platformAdmins", {
        userId: activeUser._id,
        grantedAt: 1,
      });
      await ctx.db.insert("platformAdmins", {
        userId: revokedUser._id,
        grantedAt: 1,
        revokedAt: 2,
      });
      return { activeUser, regularUser, revokedUser };
    });

    expect(
      await t.run((ctx) => isPlatformAdmin(ctx, users.activeUser._id)),
    ).toBe(true);
    expect(
      await t.run((ctx) => isPlatformAdmin(ctx, users.regularUser._id)),
    ).toBe(false);
    expect(
      await t.run((ctx) => isPlatformAdmin(ctx, users.revokedUser._id)),
    ).toBe(false);
    await expect(
      active.run((ctx) => requirePlatformAdmin(ctx)),
    ).resolves.toMatchObject({ _id: users.activeUser._id });
    await expect(
      active.run((ctx) => requirePlatformAdminQuery(ctx)),
    ).resolves.toMatchObject({ _id: users.activeUser._id });
    await expect(
      regular.run((ctx) => requirePlatformAdmin(ctx)),
    ).rejects.toThrow("Not an EarPlug admin");
    await expect(
      regular.run((ctx) => requirePlatformAdminQuery(ctx)),
    ).rejects.toThrow("Not an EarPlug admin");
  });
});

describe("organization authorization", () => {
  test("allows an owner for an owner-only operation", async () => {
    const t = convexTest(schema);
    const asOwner = t.withIdentity({
      subject: "org_owner",
      email: "owner@example.com",
      name: "Organization Owner",
    });
    await asOwner.mutation(api.users.ensureUser, {});
    const { organizationId } = await asOwner.run(async (ctx) => {
      const owner = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "org_owner"))
        .unique();
      if (!owner) throw new Error("Test owner missing");
      const organizationId = await ctx.db.insert("organizations", {
        name: "Owner Venue Group",
        slug: "owner-venue-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: owner._id,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: owner._id,
        role: "owner",
        createdAt: 1,
      });
      return { organizationId };
    });

    const access = await asOwner.run((ctx) =>
      requireOrganizationRole(ctx, organizationId, ["owner"]),
    );
    expect(access.viaPlatformAdmin).toBe(false);
    expect(access.membership?.role).toBe("owner");
  });

  test("rejects a manager from an owner-only operation", async () => {
    const t = convexTest(schema);
    const asManager = t.withIdentity({
      subject: "org_manager",
      email: "manager@example.com",
      name: "Organization Manager",
    });
    await asManager.mutation(api.users.ensureUser, {});
    const organizationId = await asManager.run(async (ctx) => {
      const manager = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "org_manager"))
        .unique();
      if (!manager) throw new Error("Test manager missing");
      const id = await ctx.db.insert("organizations", {
        name: "Manager Venue Group",
        slug: "manager-venue-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: manager._id,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId: id,
        userId: manager._id,
        role: "manager",
        createdAt: 1,
      });
      return id;
    });

    await expect(
      asManager.run((ctx) =>
        requireOrganizationRole(ctx, organizationId, ["owner"]),
      ),
    ).rejects.toThrow("Not permitted for this organization");
  });

  test("allows a platform admin without a membership", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "org_platform_admin",
      email: "admin@example.com",
      name: "Platform Admin",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const organizationId = await asAdmin.run(async (ctx) => {
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "org_platform_admin"))
        .unique();
      if (!admin) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });
      return await ctx.db.insert("organizations", {
        name: "Admin Venue Group",
        slug: "admin-venue-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: admin._id,
        createdAt: 1,
        updatedAt: 1,
      });
    });

    const access = await asAdmin.run((ctx) =>
      requireOrganizationRole(ctx, organizationId, ["owner"]),
    );
    expect(access.viaPlatformAdmin).toBe(true);
    expect(access.membership).toBeNull();
    await expect(
      asAdmin.run((ctx) =>
        requireOrganizationRoleQuery(ctx, organizationId, ["owner"]),
      ),
    ).resolves.toMatchObject({ viaPlatformAdmin: true, membership: null });
  });

  test("blocks regular members of suspended organizations but allows admins", async () => {
    const t = convexTest(schema);
    const asMember = t.withIdentity({
      subject: "suspended_member",
      email: "member@example.com",
      name: "Suspended Member",
    });
    const asAdmin = t.withIdentity({
      subject: "suspended_admin",
      email: "admin@example.com",
      name: "Suspended Admin",
    });
    await asMember.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.users.ensureUser, {});
    const organizationId = await t.run(async (ctx) => {
      const member = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "suspended_member"))
        .unique();
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "suspended_admin"))
        .unique();
      if (!member || !admin) throw new Error("Test users missing");
      const id = await ctx.db.insert("organizations", {
        name: "Suspended Venue Group",
        slug: "suspended-venue-group",
        orgType: "venueOperator",
        status: "suspended",
        ownerUserId: member._id,
        suspendedAt: 2,
        createdAt: 1,
        updatedAt: 2,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId: id,
        userId: member._id,
        role: "owner",
        createdAt: 1,
      });
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });
      return id;
    });

    await expect(
      asMember.run((ctx) =>
        requireOrganizationRole(ctx, organizationId, ["owner"]),
      ),
    ).rejects.toThrow("Organization suspended");
    await expect(
      asAdmin.run((ctx) =>
        requireOrganizationRole(ctx, organizationId, ["owner"]),
      ),
    ).resolves.toMatchObject({ viaPlatformAdmin: true });
    await expect(
      asMember.run((ctx) =>
        requireOrganizationRoleQuery(ctx, organizationId, ["owner"]),
      ),
    ).rejects.toThrow("Organization suspended");
    await expect(
      asAdmin.run((ctx) =>
        requireOrganizationRoleQuery(ctx, organizationId, ["owner"]),
      ),
    ).resolves.toMatchObject({ viaPlatformAdmin: true });
  });

  test("rejects a signed-in user with no organization membership", async () => {
    const t = convexTest(schema);
    const asStranger = t.withIdentity({
      subject: "no_org_membership",
      email: "stranger@example.com",
      name: "Stranger",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    const organizationId = await asStranger.run(async (ctx) => {
      const user = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "no_org_membership"))
        .unique();
      if (!user) throw new Error("Test user missing");
      return await ctx.db.insert("organizations", {
        name: "No Membership Group",
        slug: "no-membership-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: user._id,
        createdAt: 1,
        updatedAt: 1,
      });
    });

    await expect(
      asStranger.run((ctx) =>
        requireOrganizationRole(ctx, organizationId, ["owner", "manager"]),
      ),
    ).rejects.toThrow("Not permitted for this organization");
  });

  test("query guards preserve the deleted-account error", async () => {
    const t = convexTest(schema);
    const asDeleted = t.withIdentity({
      subject: "deleted_guard_user",
      email: "deleted@example.com",
      name: "Deleted User",
    });
    await asDeleted.mutation(api.users.ensureUser, {});
    const organizationId = await asDeleted.run(async (ctx) => {
      const user = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "deleted_guard_user"))
        .unique();
      if (!user) throw new Error("Test user missing");
      const id = await ctx.db.insert("organizations", {
        name: "Deleted User Group",
        slug: "deleted-user-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: user._id,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.patch(user._id, { deletedAt: 2 });
      return id;
    });

    await expect(
      asDeleted.run((ctx) => requirePlatformAdminQuery(ctx)),
    ).rejects.toThrow("Account deleted");
    await expect(
      asDeleted.run((ctx) =>
        requireOrganizationRoleQuery(ctx, organizationId, ["owner"]),
      ),
    ).rejects.toThrow("Account deleted");
  });

  test("query role guard reports a nonexistent organization", async () => {
    const t = convexTest(schema);
    const asUser = t.withIdentity({
      subject: "missing_org_user",
      email: "missing-org@example.com",
      name: "Missing Org User",
    });
    await asUser.mutation(api.users.ensureUser, {});
    const missingOrganizationId = await asUser.run(async (ctx) => {
      const user = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "missing_org_user"))
        .unique();
      if (!user) throw new Error("Test user missing");
      const id = await ctx.db.insert("organizations", {
        name: "Temporary Group",
        slug: "temporary-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: user._id,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.delete(id);
      return id;
    });

    await expect(
      asUser.run((ctx) =>
        requireOrganizationRoleQuery(ctx, missingOrganizationId, ["owner"]),
      ),
    ).rejects.toThrow("Organization not found");
  });

  test("rejects an unauthenticated caller", async () => {
    const t = convexTest(schema);
    const ownerId = await t.run((ctx) =>
      ctx.db.insert("users", {
        clerkId: "fixture_owner",
        name: "Fixture Owner",
        email: "fixture@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );
    const organizationId = await t.run((ctx) =>
      ctx.db.insert("organizations", {
        name: "Fixture Venue Group",
        slug: "fixture-venue-group",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: ownerId,
        createdAt: 1,
        updatedAt: 1,
      }),
    );

    await expect(
      t.run((ctx) => requireOrganizationRole(ctx, organizationId, ["owner"])),
    ).rejects.toThrow("Not signed in");
  });
});
