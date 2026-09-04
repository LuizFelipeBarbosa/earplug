/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { expect, test } from "vitest";
import { api } from "./_generated/api";
import { publishGigAsAdmin } from "./gigFixtures.test-helpers";
import { insertGigWithBandIndex } from "./lib/helpers";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

test("organization suspension hides its gigs from public reads and restores them", async () => {
  const t = convexTest(schema, modules);
  const admin = t.withIdentity({
    subject: "suspension_admin",
    email: "suspension-admin@example.com",
  });
  const { userId } = await admin.mutation(api.users.ensureUser, {});
  const { bandId } = await admin.mutation(api.bands.createBand, {
    name: "Suspension Test Band",
    genres: ["punk"],
    bio: "",
    area: "Oakland",
    inviteHandles: [],
  });
  const { organizationId, venueId, otherVenueId } = await t.run(async (ctx) => {
    await ctx.db.insert("platformAdmins", { userId, grantedAt: 1 });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Suspension Test Organizer",
      slug: "suspension-test-organizer",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: userId,
      createdAt: 1,
      updatedAt: 1,
    });
    const venue = {
      area: "Oakland",
      addr: "1 Test Way",
      distSF: "7 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      addressDisclosure: "public" as const,
    };
    const venueId = await ctx.db.insert("venues", {
      ...venue,
      name: "Managed Room",
      slug: "managed-room",
      status: "verified",
      managedByOrganizationId: organizationId,
    });
    const otherVenueId = await ctx.db.insert("venues", {
      ...venue,
      name: "Independent Room",
    });
    return { organizationId, venueId, otherVenueId };
  });
  const startsAt = Date.now() + 86400_000;
  const published = await publishGigAsAdmin(admin, {
    bandId,
    venueId,
    title: "Managed Show",
    startsAt,
    price: 5,
    flyKey: "xerox",
    ticketing: "rsvp",
    ageRequirement: "allAges",
    cap: "No cap",
  });
  const { legacyId, pastId, otherId } = await t.run(async (ctx) => {
    const fields = {
      venueId,
      price: 5,
      doorsTime: "7PM / 8PM",
      flyKey: "xerox",
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "No cap",
      goingCount: 0,
      lineup: [bandId],
    };
    const legacyId = await insertGigWithBandIndex(ctx, {
      ...fields,
      title: "Legacy Managed Show",
      startsAt: startsAt + 1000,
    });
    const pastId = await insertGigWithBandIndex(ctx, {
      ...fields,
      title: "Past Managed Show",
      startsAt: Date.now() - 7 * 86400_000,
    });
    const otherId = await insertGigWithBandIndex(ctx, {
      ...fields,
      venueId: otherVenueId,
      title: "Independent Show",
      startsAt: startsAt + 2000,
    });
    await ctx.db.insert("gigRsvps", { userId, gigId: pastId });
    return { legacyId, pastId, otherId };
  });

  for (const suspended of [false, true, false]) {
    await admin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended,
    });
    const expectedGigs = suspended
      ? [otherId]
      : [published.gigId, legacyId, otherId];
    const feed = await t.query(api.gigs.feedV2, {});
    expect(feed.gigs.map((gig) => gig._id)).toEqual(expectedGigs);
    expect(feed.venues.map((venue) => venue._id)).toEqual(
      suspended ? [otherVenueId] : [venueId, otherVenueId],
    );
    expect(
      (await t.query(api.gigs.goingCounts, {})).map((row) => row.gigId),
    ).toEqual(expectedGigs);
    expect(
      (await t.query(api.gigs.forBand, { bandId })).map((gig) => gig._id),
    ).toEqual(expectedGigs);
    const history = await t.query(api.gigs.pastForBand, { bandId });
    expect(history.gigs.map((gig) => gig._id)).toEqual(suspended ? [] : [pastId]);
    expect(history.venues.map((venue) => venue._id)).toEqual(
      suspended ? [] : [venueId],
    );
    for (const ref of [published.slug, published.gigId, legacyId, pastId]) {
      const gig = await t.query(api.gigs.resolvePublic, { ref });
      expect(gig === null).toBe(suspended);
    }
    expect(
      (await t.query(api.venues.resolvePublic, { ref: "managed-room" })) === null,
    ).toBe(suspended);

    // Suspension changes public visibility without destroying the band's
    // working project or a fan's record of a show they already attended.
    expect(
      (await admin.query(api.gigs.getProject, { projectId: published.projectId }))
        .publicGigId,
    ).toBe(published.gigId);
    expect(
      (await admin.query(api.interactions.history, { now: Date.now() })).map(
        (gig) => gig.gigId,
      ),
    ).toEqual([pastId]);
  }
});
