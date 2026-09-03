import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { isPlatformAdmin } from "./lib/authz";
import schema from "./schema";

describe("admin:me", () => {
  test("reports signed-out, regular, and active-admin callers", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.admin.me, {})).toEqual({ isPlatformAdmin: false });

    const asRegular = t.withIdentity({
      subject: "admin_me_regular",
      email: "regular-admin-me@example.com",
    });
    const asAdmin = t.withIdentity({
      subject: "admin_me_active",
      email: "active-admin-me@example.com",
    });
    await asRegular.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.users.ensureUser, {});
    await asAdmin.run(async (ctx) => {
      const user = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "admin_me_active"))
        .unique();
      if (!user) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", { userId: user._id, grantedAt: 1 });
    });

    expect(await asRegular.query(api.admin.me, {})).toEqual({
      isPlatformAdmin: false,
    });
    expect(await asAdmin.query(api.admin.me, {})).toEqual({
      isPlatformAdmin: true,
    });
  });
});

describe("admin:overview", () => {
  test("rejects non-admins and returns bounded status counts to admins", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "overview_admin",
      email: "overview-admin@example.com",
    });
    const asRegular = t.withIdentity({
      subject: "overview_regular",
      email: "overview-regular@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    await asRegular.mutation(api.users.ensureUser, {});
    await t.run(async (ctx) => {
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "overview_admin"))
        .unique();
      if (!admin) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });

      const applicationStatuses = [
        "submitted",
        "submitted",
        "under_review",
        "needs_info",
        "approved",
      ] as const;
      for (const [index, status] of applicationStatuses.entries()) {
        await ctx.db.insert("organizationApplications", {
          applicantUserId: admin._id,
          orgName: `Application ${index}`,
          orgType: "venueOperator",
          contactName: "Applicant",
          businessEmail: `applicant-${index}@example.com`,
          verificationDocStorageIds: [],
          status,
          revision: 1,
          createdAt: index,
          updatedAt: index,
        });
      }

      const organizationStatuses = [
        "verified",
        "verified",
        "suspended",
        "pending",
      ] as const;
      for (const [index, status] of organizationStatuses.entries()) {
        await ctx.db.insert("organizations", {
          name: `Organization ${index}`,
          slug: `organization-${index}`,
          orgType: "venueOperator",
          status,
          ownerUserId: admin._id,
          createdAt: index,
          updatedAt: index,
        });
      }
    });

    await expect(asRegular.query(api.admin.overview, {})).rejects.toThrow(
      "Not an EarPlug admin",
    );
    expect(await asAdmin.query(api.admin.overview, {})).toEqual({
      counts: {
        submittedApplications: 2,
        underReviewApplications: 1,
        needsInfoApplications: 1,
        verifiedOrganizations: 2,
        suspendedOrganizations: 1,
      },
      capped: false,
    });
  });
});

describe("admin:suspendOrganization", () => {
  test("suspends managed venues and restores their public visibility", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "suspension_admin",
      email: "suspension-admin@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { organizationId, venueIds } = await asAdmin.run(async (ctx) => {
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "suspension_admin"))
        .unique();
      if (!admin) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });
      const organizationId = await ctx.db.insert("organizations", {
        name: "Suspendable Venues",
        slug: "suspendable-venues",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: admin._id,
        createdAt: 1,
        updatedAt: 1,
      });
      const venueIds = [];
      for (const name of ["Suspend Room A", "Suspend Room B"]) {
        venueIds.push(
          await ctx.db.insert("venues", {
            name,
            area: "Oakland",
            addr: "1 Test Way",
            distSF: "7 mi",
            distOak: "1 mi",
            lat: 37.8,
            lng: -122.27,
            status: "verified",
            addressDisclosure: "public",
            managedByOrganizationId: organizationId,
          }),
        );
      }
      return { organizationId, venueIds };
    });

    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: true,
      note: "Policy review",
    });
    expect(await t.query(api.venues.list, {})).toEqual([]);
    for (const venueId of venueIds) {
      expect(await t.query(api.venues.detail, { venueId })).toBeNull();
    }

    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: false,
    });
    expect(
      (await t.query(api.venues.list, {})).map((venue) => venue._id),
    ).toEqual(venueIds);
    for (const venueId of venueIds) {
      expect(await t.query(api.venues.detail, { venueId })).not.toBeNull();
    }
    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(organization).toMatchObject({ status: "verified" });
    expect(organization?.suspendedAt).toBeUndefined();
  });
});

describe("admin:grantPlatformAdmin", () => {
  test("defaults to dry-run and grants exactly one active row live", async () => {
    const t = convexTest(schema);
    const userId = await t.run((ctx) =>
      ctx.db.insert("users", {
        clerkId: "grant_target",
        name: "Grant Target",
        email: "grant-target@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );

    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, { userId }),
    ).toEqual({ granted: false, alreadyAdmin: false, dryRun: true });
    expect(await t.run((ctx) => isPlatformAdmin(ctx, userId))).toBe(false);

    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, {
        userId,
        note: "Initial operator",
        dryRun: false,
      }),
    ).toEqual({ granted: true, alreadyAdmin: false, dryRun: false });
    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, {
        userId,
        dryRun: false,
      }),
    ).toEqual({ granted: false, alreadyAdmin: true, dryRun: false });
    expect(await t.run((ctx) => isPlatformAdmin(ctx, userId))).toBe(true);
    const activeRows = await t.run((ctx) =>
      ctx.db
        .query("platformAdmins")
        .withIndex("by_userId", (q) => q.eq("userId", userId))
        .filter((q) => q.eq(q.field("revokedAt"), undefined))
        .take(10),
    );
    expect(activeRows).toHaveLength(1);
    expect(activeRows[0].note).toBe("Initial operator");
  });
});
