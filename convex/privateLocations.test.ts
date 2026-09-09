/// <reference types="vite/client" />
import { anyApi, type ApiFromModules } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type * as privateLocations from "./privateLocations";
import schema from "./schema";

// Derive API types from the module so tests also work before code generation.
const api = anyApi as unknown as ApiFromModules<{
  privateLocations: typeof privateLocations;
}>;
const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-06T12:00:00Z");
const locationFields = {
  label: "  Backyard  ",
  addr: "  42 Garden Street  ",
  city: "  Oakland  ",
  area: "  Rockridge, Oakland  ",
  lat: 37.84,
  lng: -122.25,
  notes: "  Use the side gate  ",
};

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.useRealTimers();
});

async function setupPrivateHost(
  orgType: "privateHost" | "venueOperator" = "privateHost",
) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const userFields = {
      name: "Host",
      email: "host@example.test",
      genres: [],
      attendedCount: 0,
    };
    const ownerId = await ctx.db.insert("users", {
      ...userFields,
      clerkId: "location_owner",
    });
    const managerId = await ctx.db.insert("users", {
      ...userFields,
      clerkId: "location_manager",
    });
    await ctx.db.insert("users", {
      ...userFields,
      clerkId: "location_stranger",
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Private Host",
      slug: "private-host",
      orgType,
      status: "verified",
      ownerUserId: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const [role, userId] of [
      ["owner", ownerId],
      ["manager", managerId],
    ] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: NOW,
      });
    }
    const locationId = await ctx.db.insert("privateLocations", {
      ...locationFields,
      organizationId,
      label: "Existing location",
      createdAt: NOW,
      updatedAt: NOW,
    });
    return { ownerId, organizationId, locationId };
  });
  return {
    t,
    ...ids,
    asOwner: t.withIdentity({ subject: "location_owner" }),
    asManager: t.withIdentity({ subject: "location_manager" }),
    asStranger: t.withIdentity({ subject: "location_stranger" }),
    createArgs: { organizationId: ids.organizationId, ...locationFields },
  };
}

describe("private locations", () => {
  test("creates normalized locations and returns the owner payload", async () => {
    const f = await setupPrivateHost();
    const { locationId } = await f.asOwner.mutation(
      api.privateLocations.create,
      f.createArgs,
    );
    const locations = await f.asOwner.query(
      api.privateLocations.forOrganization,
      {
        organizationId: f.organizationId,
      },
    );
    expect(locations.find((location) => location._id === locationId)).toEqual({
      _id: locationId,
      organizationId: f.organizationId,
      label: "Backyard",
      addr: "42 Garden Street",
      city: "Oakland",
      area: "Rockridge, Oakland",
      lat: 37.84,
      lng: -122.25,
      notes: "Use the side gate",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const emptyNotes = await f.asOwner.mutation(api.privateLocations.create, {
      ...f.createArgs,
      notes: "  ",
      lat: -90,
      lng: 180,
    });
    expect(
      await f.t.run((ctx) => ctx.db.get(emptyNotes.locationId)),
    ).not.toHaveProperty("notes");
    expect(
      await f.asOwner.query(api.privateLocations.forOrganization, {
        organizationId: f.organizationId,
      }),
    ).toContainEqual(
      expect.objectContaining({ _id: emptyNotes.locationId, notes: null }),
    );
  });

  test.each([
    { label: "  ", error: "Label must be" },
    { addr: "", error: "Address must be" },
    { city: "  ", error: "City must be" },
    { area: "", error: "Area must be" },
    {
      label: "x".repeat(81),
      error: "Label must be between 1 and 80 characters",
    },
    { addr: "x".repeat(241), error: "Address must be" },
    { city: "x".repeat(121), error: "City must be" },
    { area: "x".repeat(121), error: "Area must be" },
    { notes: "x".repeat(2001), error: "Notes must be at most 2000 characters" },
    { lat: -91, error: "Latitude must be" },
    { lat: 91, error: "Latitude must be" },
    { lat: Number.NaN, error: "Latitude must be" },
    { lng: -181, error: "Longitude must be" },
    { lng: 181, error: "Longitude must be" },
    { lng: Number.POSITIVE_INFINITY, error: "Longitude must be" },
  ])("validates create and update: $error", async ({ error, ...fields }) => {
    const f = await setupPrivateHost();
    const before = await f.t.run((ctx) => ctx.db.get(f.locationId));
    await expect(
      f.asOwner.mutation(api.privateLocations.create, {
        ...f.createArgs,
        ...fields,
      }),
    ).rejects.toThrow(error);
    await expect(
      f.asOwner.mutation(api.privateLocations.update, {
        locationId: f.locationId,
        ...fields,
      }),
    ).rejects.toThrow(error);
    expect(await f.t.run((ctx) => ctx.db.get(f.locationId))).toEqual(before);
  });

  test.each(["asOwner", "asManager"] as const)(
    "all operations allow %s with labels and notes at their limits",
    async (actor) => {
      const f = await setupPrivateHost();
      const client = f[actor];
      const fields = { label: "x".repeat(80), notes: "y".repeat(2000) };
      const { locationId } = await client.mutation(
        api.privateLocations.create,
        {
          ...f.createArgs,
          ...fields,
        },
      );
      await expect(
        client.mutation(api.privateLocations.update, {
          locationId: f.locationId,
          ...fields,
        }),
      ).resolves.toBeNull();
      const locations = await client.query(
        api.privateLocations.forOrganization,
        {
          organizationId: f.organizationId,
        },
      );
      for (const id of [f.locationId, locationId]) {
        expect(locations).toContainEqual(
          expect.objectContaining({ _id: id, ...fields }),
        );
      }
      await expect(
        client.mutation(api.privateLocations.remove, { locationId }),
      ).resolves.toBeNull();
      expect(await f.t.run((ctx) => ctx.db.get(locationId))).toMatchObject({
        archivedAt: NOW,
      });
    },
  );

  test.each(["asStranger", "venueOperator", "suspended"] as const)(
    "all operations reject unauthorized access: %s",
    async (actor) => {
      const f = await setupPrivateHost(
        actor === "venueOperator" ? "venueOperator" : "privateHost",
      );
      if (actor === "suspended") {
        await f.t.run((ctx) =>
          ctx.db.patch(f.organizationId, { status: "suspended" }),
        );
      }
      const client =
        actor === "venueOperator" || actor === "suspended"
          ? f.asOwner
          : f[actor];
      const error =
        actor === "venueOperator"
          ? "Only hosts keep private locations"
          : actor === "suspended"
            ? "Organization suspended"
            : "Not permitted for this organization";
      const attempts = [
        () => client.mutation(api.privateLocations.create, f.createArgs),
        () =>
          client.mutation(api.privateLocations.update, {
            locationId: f.locationId,
            label: "Changed",
          }),
        () =>
          client.mutation(api.privateLocations.remove, {
            locationId: f.locationId,
          }),
        () =>
          client.query(api.privateLocations.forOrganization, {
            organizationId: f.organizationId,
          }),
      ];
      for (const attempt of attempts)
        await expect(attempt()).rejects.toThrow(error);
    },
  );

  test("partial updates preserve omitted fields and clear notes explicitly", async () => {
    const f = await setupPrivateHost();
    const { locationId } = await f.asOwner.mutation(
      api.privateLocations.create,
      f.createArgs,
    );
    const before = await f.t.run((ctx) => ctx.db.get(locationId));
    vi.setSystemTime(NOW + 1000);
    await f.asOwner.mutation(api.privateLocations.update, {
      locationId,
      label: "  Garden  ",
      lat: 38,
    });
    expect(await f.t.run((ctx) => ctx.db.get(locationId))).toEqual({
      ...before,
      label: "Garden",
      lat: 38,
      updatedAt: NOW + 1000,
    });
    await f.asOwner.mutation(api.privateLocations.update, {
      locationId,
      notes: null,
    });
    expect(await f.t.run((ctx) => ctx.db.get(locationId))).not.toHaveProperty(
      "notes",
    );
    await f.asOwner.mutation(api.privateLocations.update, {
      locationId,
      notes: "  New instructions  ",
    });
    expect(await f.t.run((ctx) => ctx.db.get(locationId))).toMatchObject({
      notes: "New instructions",
    });
    await f.asOwner.mutation(api.privateLocations.update, {
      locationId,
      notes: "  ",
    });
    expect(await f.t.run((ctx) => ctx.db.get(locationId))).not.toHaveProperty(
      "notes",
    );
  });

  test("archives a location, preserves history, and permits creating a new location", async () => {
    const f = await setupPrivateHost();
    const before = await f.t.run((ctx) => ctx.db.get(f.locationId));
    await expect(
      f.asOwner.mutation(api.privateLocations.remove, {
        locationId: f.locationId,
      }),
    ).resolves.toBeNull();
    expect(await f.t.run((ctx) => ctx.db.get(f.locationId))).toEqual({
      ...before,
      archivedAt: NOW,
    });
    expect(
      await f.asOwner.query(api.privateLocations.forOrganization, {
        organizationId: f.organizationId,
      }),
    ).toEqual([]);
    vi.setSystemTime(NOW + 1000);
    await expect(
      f.asOwner.mutation(api.privateLocations.remove, {
        locationId: f.locationId,
      }),
    ).resolves.toBeNull();
    expect(await f.t.run((ctx) => ctx.db.get(f.locationId))).toEqual({
      ...before,
      archivedAt: NOW,
    });
    await expect(
      f.asOwner.mutation(api.privateLocations.update, {
        locationId: f.locationId,
        label: "Changed",
      }),
    ).rejects.toThrow("Location has been removed");
    const created = await f.asOwner.mutation(
      api.privateLocations.create,
      f.createArgs,
    );
    expect(created.locationId).not.toBe(f.locationId);
    const locations = await f.asOwner.query(
      api.privateLocations.forOrganization,
      {
        organizationId: f.organizationId,
      },
    );
    expect(locations.map((location) => location._id)).toEqual([
      created.locationId,
    ]);
    expect(locations[0]).not.toHaveProperty("archivedAt");
    expect(await f.t.run((ctx) => ctx.db.get(f.locationId))).toEqual({
      ...before,
      archivedAt: NOW,
    });
  });

  test("reports missing locations for update and remove", async () => {
    const f = await setupPrivateHost();
    await f.t.run((ctx) => ctx.db.delete(f.locationId));
    for (const mutation of [
      api.privateLocations.update,
      api.privateLocations.remove,
    ]) {
      await expect(
        f.asOwner.mutation(mutation, { locationId: f.locationId }),
      ).rejects.toThrow("Location not found");
    }
  });

  test.each(["completed", "cancelled", "reference removed"] as const)(
    "protects every non-terminal reference and permits removal after %s",
    async (resolution) => {
      const f = await setupPrivateHost();
      const opportunityId = await f.t.run((ctx) =>
        ctx.db.insert("talentOpportunities", {
          organizationId: f.organizationId,
          hostUserId: f.ownerId,
          privateLocationId: f.locationId,
          mode: "privateBooking",
          area: "Rockridge, Oakland",
          title: "Backyard Party",
          desc: "Local music",
          genres: [],
          startsAt: NOW + 10000,
          ageRequirement: "allAges",
          flyKey: "xerox",
          applicationsCloseAt: NOW + 5000,
          visibility: "inviteOnly",
          ticketing: "none",
          currency: "usd",
          status: "draft",
          slug: "backyard-party",
          createdBy: f.ownerId,
          revision: 1,
          applicationCount: 0,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      for (const status of [
        "draft",
        "open",
        "applications_closed",
        "booking",
        "confirmed",
      ] as const) {
        await f.t.run((ctx) => ctx.db.patch(opportunityId, { status }));
        await expect(
          f.asOwner.mutation(api.privateLocations.remove, {
            locationId: f.locationId,
          }),
        ).rejects.toThrow("Location is in use");
      }
      await f.t.run((ctx) =>
        ctx.db.patch(
          opportunityId,
          resolution === "reference removed"
            ? { privateLocationId: undefined }
            : { status: resolution },
        ),
      );
      await f.asOwner.mutation(api.privateLocations.remove, {
        locationId: f.locationId,
      });
      expect(await f.t.run((ctx) => ctx.db.get(f.locationId))).toMatchObject({
        _id: f.locationId,
        archivedAt: NOW,
      });
      expect(await f.t.run((ctx) => ctx.db.get(opportunityId))).toMatchObject(
        resolution === "reference removed"
          ? { status: "confirmed" }
          : { status: resolution, privateLocationId: f.locationId },
      );
    },
  );
});
