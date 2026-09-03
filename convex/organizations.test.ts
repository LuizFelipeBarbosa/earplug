import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

async function setupOrganization() {
  const t = convexTest(schema);
  const asOwner = t.withIdentity({
    subject: "dashboard_owner",
    email: "owner@dashboard.test",
    name: "Dashboard Owner",
  });
  const asDoor = t.withIdentity({
    subject: "dashboard_door",
    email: "door@dashboard.test",
    name: "Door Person",
  });
  const asStranger = t.withIdentity({
    subject: "dashboard_stranger",
    email: "stranger@dashboard.test",
    name: "Dashboard Stranger",
  });
  const { userId: ownerId } = await asOwner.mutation(api.users.ensureUser, {});
  const { userId: doorId } = await asDoor.mutation(api.users.ensureUser, {});
  await asStranger.mutation(api.users.ensureUser, {});
  const organizationId = await t.run(async (ctx) => {
    const id = await ctx.db.insert("organizations", {
      name: "Stable Slug Venues",
      slug: "stable-slug-venues",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      description: "Neighborhood venues run by neighbors.",
      createdAt: 1,
      updatedAt: 1,
    });
    await ctx.db.insert("organizationPrivateDetails", {
      organizationId: id,
      legalName: "Stable Slug Venues LLC",
      businessEmail: "office@stable-slug.test",
      contactName: "Dashboard Owner",
      phone: "415-555-0150",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: 1,
    });
    await ctx.db.insert("organizationMembers", {
      organizationId: id,
      userId: ownerId,
      role: "owner",
      createdAt: 1,
    });
    await ctx.db.insert("organizationMembers", {
      organizationId: id,
      userId: doorId,
      role: "door",
      addedBy: ownerId,
      createdAt: 2,
    });
    return id;
  });
  return { t, asOwner, asDoor, asStranger, organizationId };
}

describe("organizations", () => {
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
