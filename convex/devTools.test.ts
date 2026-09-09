/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const user = {
  clerkId: "dev_tools_owner",
  name: "Riley Owner",
  email: "riley@night-light.example",
  genres: [],
  attendedCount: 0,
};

async function setupUser() {
  const t = convexTest(schema, modules);
  const userId = await t.run((ctx) => ctx.db.insert("users", user));
  return { t, userId };
}

describe("grantOrganization", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv(
      "CONVEX_CLOUD_URL",
      "https://brilliant-cardinal-773.convex.cloud",
    );
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test.each([undefined, true])(
    "dryRun=%s previews the slug without writing rows",
    async (dryRun) => {
      const { t, userId } = await setupUser();

      const result = await t.mutation(internal.devTools.grantOrganization, {
        userId,
        name: "Night Light LLC",
        orgType: "promoter",
        ...(dryRun === undefined ? {} : { dryRun }),
      });

      expect(result).toEqual({
        applied: false,
        organizationId: null,
        slug: "night-light-llc",
      });
      await t.run(async (ctx) => {
        expect(await ctx.db.query("organizations").take(1)).toEqual([]);
        expect(await ctx.db.query("organizationPrivateDetails").take(1)).toEqual(
          [],
        );
        expect(await ctx.db.query("organizationMembers").take(1)).toEqual([]);
        expect(await ctx.db.query("organizationApplications").take(1)).toEqual(
          [],
        );
        expect(await ctx.db.query("venues").take(1)).toEqual([]);
      });
    },
  );

  test("creates a verified promoter with private details and owner membership", async () => {
    const { t, userId } = await setupUser();

    const result = await t.mutation(internal.devTools.grantOrganization, {
      userId,
      name: "Night Light LLC",
      orgType: "promoter",
      dryRun: false,
    });

    expect(result).toEqual({
      applied: true,
      organizationId: expect.any(String),
      slug: "night-light-llc",
    });
    const organizationId = result.organizationId;
    if (organizationId === null) throw new Error("Organization was not created");

    await t.run(async (ctx) => {
      const organization = await ctx.db.get(organizationId);
      expect(organization).toEqual({
        _id: organizationId,
        _creationTime: expect.any(Number),
        name: "Night Light LLC",
        slug: result.slug,
        orgType: "promoter",
        status: "verified",
        ownerUserId: userId,
        verifiedAt: expect.any(Number),
        createdAt: organization?.verifiedAt,
        updatedAt: organization?.verifiedAt,
      });

      const privateDetails = await ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique();
      expect(privateDetails).toEqual({
        _id: expect.any(String),
        _creationTime: expect.any(Number),
        organizationId,
        businessEmail: user.email,
        contactName: user.name,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: [],
        updatedAt: organization?.verifiedAt,
      });

      const membership = await ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q.eq("organizationId", organizationId).eq("userId", userId),
        )
        .unique();
      expect(membership).toEqual({
        _id: expect.any(String),
        _creationTime: expect.any(Number),
        organizationId,
        userId,
        role: "owner",
        createdAt: organization?.verifiedAt,
      });
      expect(await ctx.db.query("organizationApplications").take(1)).toEqual([]);
      expect(await ctx.db.query("venues").take(1)).toEqual([]);
    });
  });

  test("refuses to run on production", async () => {
    const { t, userId } = await setupUser();
    vi.stubEnv("CONVEX_CLOUD_URL", "https://decisive-iguana-759.convex.cloud");

    await expect(
      t.mutation(internal.devTools.grantOrganization, {
        userId,
        name: "Night Light LLC",
        orgType: "promoter",
        dryRun: false,
      }),
    ).rejects.toThrow("grantOrganization is a development-only tool");
  });

  test("refuses a nonexistent user", async () => {
    const { t, userId } = await setupUser();
    await t.run((ctx) => ctx.db.delete(userId));

    await expect(
      t.mutation(internal.devTools.grantOrganization, {
        userId,
        name: "Night Light LLC",
        orgType: "promoter",
        dryRun: false,
      }),
    ).rejects.toThrow("User not found");
  });

  test("uses a random host slug for private hosts", async () => {
    const { t, userId } = await setupUser();

    const result = await t.mutation(internal.devTools.grantOrganization, {
      userId,
      name: "Riley Private Host",
      orgType: "privateHost",
      dryRun: false,
    });

    expect(result).toMatchObject({
      applied: true,
      organizationId: expect.any(String),
      slug: expect.stringMatching(/^host-[0-9a-f]{12}$/),
    });
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("organizations")
          .withIndex("by_slug", (q) => q.eq("slug", result.slug))
          .unique(),
      ),
    ).toMatchObject({
      _id: result.organizationId,
      orgType: "privateHost",
      ownerUserId: userId,
      status: "verified",
    });
  });

  test.each([
    {
      name: "Night Light LLC",
      firstSlug: "night-light-llc",
      nextSlug: "night-light-llc-2",
    },
    { name: "Admin", firstSlug: "admin-2", nextSlug: "admin-3" },
  ])(
    "avoids reserved and occupied slugs for $name",
    async ({ name, firstSlug, nextSlug }) => {
      const { t, userId } = await setupUser();

      const first = await t.mutation(internal.devTools.grantOrganization, {
        userId,
        name,
        orgType: "promoter",
        dryRun: false,
      });
      const next = await t.mutation(internal.devTools.grantOrganization, {
        userId,
        name,
        orgType: "promoter",
        dryRun: false,
      });

      expect(first.slug).toBe(firstSlug);
      expect(next.slug).toBe(nextSlug);
      expect(next.organizationId).not.toBe(first.organizationId);
    },
  );
});
