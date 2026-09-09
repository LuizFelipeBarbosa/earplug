import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { setupOrganization as setupOrganizationFixture } from "./orgFixtures.test-helpers";
import schema from "./schema";

async function setupOrganization() {
  const t = convexTest(schema);
  const fixture = await setupOrganizationFixture(t, {
    prefix: "dashboard",
    viaEnsureUser: true,
    withPrivateDetails: true,
    roles: [
      { label: "owner", role: "owner", name: "Dashboard Owner" },
      {
        label: "door",
        role: "door",
        name: "Door Person",
        addedBy: "owner",
        createdAt: 2,
      },
      { label: "stranger", role: null, name: "Dashboard Stranger" },
    ],
    organization: {
      name: "Stable Slug Venues",
      slug: "stable-slug-venues",
      description: "Neighborhood venues run by neighbors.",
    },
    privateDetails: {
      legalName: "Stable Slug Venues LLC",
      businessEmail: "office@stable-slug.test",
      phone: "415-555-0150",
      stripeChargesEnabled: true,
      stripeDetailsSubmitted: true,
    },
  });
  return {
    t: fixture.t,
    asOwner: fixture.as("owner"),
    asDoor: fixture.as("door"),
    asStranger: fixture.as("stranger"),
    organizationId: fixture.organizationId,
  };
}

describe("organizations", () => {
  test("private hosts are hidden from public lookups but visible to their owner", async () => {
    const { t, asOwner, organizationId } = await setupOrganization();
    await t.run((ctx) =>
      ctx.db.patch(organizationId, { orgType: "privateHost" }),
    );

    for (const caller of [t, asOwner]) {
      expect(
        await caller.query(api.organizations.get, { organizationId }),
      ).toBeNull();
      expect(
        await caller.query(api.organizations.bySlug, {
          slug: "stable-slug-venues",
        }),
      ).toBeNull();
    }
    expect(await asOwner.query(api.organizations.mine, {})).toMatchObject([
      {
        organization: { _id: organizationId, orgType: "privateHost" },
        role: "owner",
      },
    ]);
    expect(
      await asOwner.query(api.organizations.dashboard, { organizationId }),
    ).toMatchObject({
      organization: { _id: organizationId, orgType: "privateHost" },
      role: "owner",
    });
  });

  test.each(["verified", "suspended"] as const)(
    "public lookups preserve visibility for a %s venue operator",
    async (status) => {
      const { t, organizationId } = await setupOrganization();
      await t.run((ctx) => ctx.db.patch(organizationId, { status }));

      for (const organization of [
        await t.query(api.organizations.get, { organizationId }),
        await t.query(api.organizations.bySlug, { slug: "stable-slug-venues" }),
      ]) {
        if (status === "suspended") {
          expect(organization).toBeNull();
        } else {
          expect(organization).toMatchObject({
            _id: organizationId,
            orgType: "venueOperator",
            status,
          });
        }
      }
    },
  );

  test("dashboard rejects strangers and hides private details from door staff", async () => {
    const { asDoor, asStranger, organizationId } = await setupOrganization();
    await expect(
      asStranger.query(api.organizations.dashboard, { organizationId }),
    ).rejects.toThrow("Not permitted for this organization");

    const dashboard = await asDoor.query(api.organizations.dashboard, {
      organizationId,
    });
    expect(dashboard.role).toBe("door");
    expect(dashboard.viaPlatformAdmin).toBe(false);
    expect(dashboard.privateDetails).toBeNull();
    expect(dashboard.verification).toMatchObject({
      verified: true,
      stripeDetailsSubmitted: true,
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      teamInvited: true,
    });
    expect(dashboard.memberCount).toBe(2);
  });

  test("renaming an organization leaves its issued slug stable", async () => {
    const { t, asOwner, organizationId } = await setupOrganization();
    await asOwner.mutation(api.organizations.updateProfile, {
      organizationId,
      name: "  Renamed Venue Collective  ",
    });
    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(organization?.name).toBe("Renamed Venue Collective");
    expect(organization?.slug).toBe("stable-slug-venues");
  });

  test("adding photos preserves existing uploads and concurrent additions", async () => {
    const { t, asOwner, organizationId } = await setupOrganization();
    const storageIds = await t.run(async (ctx) =>
      Promise.all(
        [1, 2, 3].map((value) =>
          ctx.storage.store(
            new Blob([new Uint8Array([value])], { type: "image/png" }),
          ),
        ),
      ),
    );
    await asOwner.mutation(api.organizations.setPhotos, {
      organizationId,
      storageIds: [storageIds[0]],
    });

    await Promise.all(
      storageIds.slice(1).map((storageId) =>
        asOwner.mutation(api.organizations.addPhoto, {
          organizationId,
          storageId,
        }),
      ),
    );
    await asOwner.mutation(api.organizations.addPhoto, {
      organizationId,
      storageId: storageIds[1],
    });

    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(organization?.photoStorageIds).toHaveLength(3);
    expect(organization?.photoStorageIds?.[0]).toBe(storageIds[0]);
    expect(organization?.photoStorageIds).toEqual(
      expect.arrayContaining(storageIds),
    );
    expect(
      (await asOwner.query(api.organizations.dashboard, { organizationId }))
        .organization.photoUrls,
    ).toHaveLength(3);
  });

  test("adding photos requires a manager, acceptable upload, and available space", async () => {
    const { t, asOwner, asDoor, organizationId } = await setupOrganization();
    const { storageIds, invalidUpload } = await t.run(async (ctx) => ({
      storageIds: await Promise.all(
        Array.from({ length: 11 }, (_, value) =>
          ctx.storage.store(
            new Blob([new Uint8Array([value])], { type: "image/png" }),
          ),
        ),
      ),
      invalidUpload: await ctx.storage.store(
        new Blob(["text"], { type: "text/plain" }),
      ),
    }));
    await t.run(async (ctx) => {
      // convex-test omits Blob contentType, unlike deployed storage metadata.
      const db = ctx.db as unknown as {
        patch(
          id: typeof invalidUpload,
          value: { contentType: string },
        ): Promise<void>;
      };
      await db.patch(invalidUpload, { contentType: "text/plain" });
    });
    await expect(
      asDoor.mutation(api.organizations.addPhoto, {
        organizationId,
        storageId: storageIds[0],
      }),
    ).rejects.toThrow("Not permitted for this organization");
    await expect(
      asOwner.mutation(api.organizations.addPhoto, {
        organizationId,
        storageId: invalidUpload,
      }),
    ).rejects.toThrow("can't be posted as a photo");
    await asOwner.mutation(api.organizations.setPhotos, {
      organizationId,
      storageIds: storageIds.slice(0, 10),
    });
    await expect(
      asOwner.mutation(api.organizations.addPhoto, {
        organizationId,
        storageId: storageIds[10],
      }),
    ).rejects.toThrow("up to 10 photos");
    expect(
      (await t.run((ctx) => ctx.db.get(organizationId)))?.photoStorageIds,
    ).toEqual(storageIds.slice(0, 10));
  });

  test("deactivation suspends the organization's managed venues", async () => {
    const { t, asOwner, organizationId } = await setupOrganization();
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        name: "Managed Deactivation Room",
        slug: "managed-deactivation-room",
        area: "Oakland",
        addr: "100 Public Street",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
        status: "verified",
        addressDisclosure: "public",
        managedByOrganizationId: organizationId,
      }),
    );

    await asOwner.mutation(api.organizations.deactivate, { organizationId });

    expect(
      (await t.query(api.venues.list, {})).some((venue) => venue._id === venueId),
    ).toBe(false);
    expect(
      await t.query(api.venues.resolvePublic, { ref: venueId }),
    ).toBeNull();
  });
});
