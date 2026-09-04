import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { Id } from "./_generated/dataModel";
import { migrateVenueLocationPrivacy } from "./migrations";
import schema from "./schema";

async function applyVenueLocationPrivacyMigration(
  t: ReturnType<typeof convexTest>,
  venueId: Id<"venues">,
) {
  return await t.run(async (ctx) => {
    const venue = await ctx.db.get(venueId);
    if (!venue) throw new Error("Test venue not found");
    const patch = await migrateVenueLocationPrivacy(ctx, venue);
    if (patch) await ctx.db.patch(venueId, patch);
    return patch;
  });
}

test("backfills legacy venue location privacy idempotently", async () => {
  const t = convexTest(schema);
  const original = {
    name: "  The Foghorn Club  ",
    area: "San Francisco",
    addr: "  123 Test Street  ",
    lat: 37.7749,
    lng: -122.4194,
    distSF: "0.0 mi",
    distOak: "8.1 mi",
  };
  const venueId = await t.run(async (ctx) =>
    ctx.db.insert("venues", original),
  );

  const firstPatch = await applyVenueLocationPrivacyMigration(t, venueId);
  expect(firstPatch).toMatchObject({
    status: "legacy",
    slug: "the-foghorn-club",
    normalizedName: "the foghorn club",
    normalizedAddr: "123 test street",
  });

  const afterFirst = await t.run(async (ctx) => ({
    venue: await ctx.db.get(venueId),
    privateDetails: await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", venueId))
      .collect(),
  }));
  expect(afterFirst.venue).toMatchObject({
    status: "legacy",
    slug: "the-foghorn-club",
    approxLabel: expect.any(String),
    approxLat: expect.any(Number),
    approxLng: expect.any(Number),
    normalizedName: "the foghorn club",
    normalizedAddr: "123 test street",
  });
  expect(afterFirst.venue?.slug).not.toBe("");
  expect(afterFirst.venue?.addr).toBe(original.addr);
  expect(afterFirst.venue?.lat).toBe(original.lat);
  expect(afterFirst.venue?.lng).toBe(original.lng);
  expect(afterFirst.privateDetails).toHaveLength(1);
  expect(afterFirst.privateDetails[0]).toMatchObject({
    venueId,
    addr: original.addr,
    lat: original.lat,
    lng: original.lng,
    normalizedAddr: "123 test street",
    updatedAt: expect.any(Number),
  });

  const secondPatch = await applyVenueLocationPrivacyMigration(t, venueId);
  const afterSecond = await t.run(async (ctx) => ({
    venue: await ctx.db.get(venueId),
    privateDetails: await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", venueId))
      .collect(),
  }));
  expect(secondPatch == null).toBe(true);
  expect(afterSecond).toEqual(afterFirst);
});

test("leaves a fully populated venue and private detail untouched", async () => {
  const t = convexTest(schema);
  const { venueId, detailId } = await t.run(async (ctx) => {
    const venueId = await ctx.db.insert("venues", {
      name: "Complete Venue",
      area: "Oakland",
      addr: "456 Complete Avenue",
      normalizedName: "complete venue",
      normalizedAddr: "456 complete avenue",
      distSF: "7.0 mi",
      distOak: "0.2 mi",
      lat: 37.8044,
      lng: -122.2712,
      slug: "complete-venue",
      status: "verified",
      approxLabel: "Downtown Oakland",
      approxLat: 37.804,
      approxLng: -122.271,
      neighborhood: "Downtown Oakland",
      city: "Oakland",
    });
    const detailId = await ctx.db.insert("venuePrivateDetails", {
      venueId,
      addr: "456 Complete Avenue",
      lat: 37.8044,
      lng: -122.2712,
      normalizedAddr: "456 complete avenue",
      updatedAt: 12345,
    });
    return { venueId, detailId };
  });
  const before = await t.run(async (ctx) => ({
    venue: await ctx.db.get(venueId),
    detail: await ctx.db.get(detailId),
  }));

  const patch = await applyVenueLocationPrivacyMigration(t, venueId);
  const after = await t.run(async (ctx) => ({
    venue: await ctx.db.get(venueId),
    detail: await ctx.db.get(detailId),
  }));

  expect(patch == null).toBe(true);
  expect(after).toEqual(before);
});

test("backfills normalized addresses only for effectively public venues", async () => {
  const t = convexTest(schema);
  const [legacyVenueId, onTicketVenueId] = await t.run(async (ctx) => [
    await ctx.db.insert("venues", {
      name: "Legacy Public Room",
      area: "San Francisco",
      addr: "11 Legacy Street",
      distSF: "0 mi",
      distOak: "8 mi",
      lat: 37.77,
      lng: -122.42,
    }),
    await ctx.db.insert("venues", {
      name: "Private Verified Room",
      area: "Mission, San Francisco",
      addr: "Mission, San Francisco",
      distSF: "0 mi",
      distOak: "8 mi",
      lat: 37.7599,
      lng: -122.4148,
      status: "verified",
      addressDisclosure: "onTicket",
      approxLabel: "Mission, San Francisco",
      approxLat: 37.7599,
      approxLng: -122.4148,
    }),
  ]);

  await applyVenueLocationPrivacyMigration(t, legacyVenueId);
  await applyVenueLocationPrivacyMigration(t, onTicketVenueId);
  const venues = await t.run(async (ctx) => ({
    legacy: await ctx.db.get(legacyVenueId),
    onTicket: await ctx.db.get(onTicketVenueId),
  }));

  expect(venues.legacy?.normalizedAddr).toBe("11 legacy street");
  expect(venues.onTicket?.normalizedAddr).toBeUndefined();
});

test("assigns distinct slugs to legacy venues with the same name", async () => {
  const t = convexTest(schema);
  const [firstId, secondId] = await t.run(async (ctx) => [
    await ctx.db.insert("venues", {
      name: "The Foghorn Club",
      area: "San Francisco",
      addr: "1 First Street",
      distSF: "0 mi",
      distOak: "8 mi",
      lat: 37.77,
      lng: -122.42,
    }),
    await ctx.db.insert("venues", {
      name: "The Foghorn Club",
      area: "San Francisco",
      addr: "2 Second Street",
      distSF: "0 mi",
      distOak: "8 mi",
      lat: 37.78,
      lng: -122.41,
    }),
  ]);

  await applyVenueLocationPrivacyMigration(t, firstId);
  await applyVenueLocationPrivacyMigration(t, secondId);
  const venues = await t.run(async (ctx) => ({
    first: await ctx.db.get(firstId),
    second: await ctx.db.get(secondId),
  }));

  expect(venues.first?.slug).toBe("the-foghorn-club");
  expect(venues.second?.slug).toBe("the-foghorn-club-2");
});

test("skips private detail creation for a blank legacy address", async () => {
  const t = convexTest(schema);
  const venueId = await t.run(async (ctx) =>
    ctx.db.insert("venues", {
      name: "Location TBA",
      area: "East Bay",
      addr: "",
      distSF: "9 mi",
      distOak: "2 mi",
      lat: 37.8,
      lng: -122.3,
    }),
  );

  await applyVenueLocationPrivacyMigration(t, venueId);
  const result = await t.run(async (ctx) => ({
    venue: await ctx.db.get(venueId),
    privateDetail: await ctx.db
      .query("venuePrivateDetails")
      .withIndex("by_venueId", (q) => q.eq("venueId", venueId))
      .first(),
  }));

  expect(result.privateDetail).toBeNull();
  expect(result.venue).toMatchObject({
    status: "legacy",
    slug: "location-tba",
    approxLabel: expect.any(String),
    approxLat: expect.any(Number),
    approxLng: expect.any(Number),
    normalizedAddr: "",
  });
});
