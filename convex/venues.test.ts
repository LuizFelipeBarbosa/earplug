import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

function bandFields(name: string) {
  return {
    name,
    slug: name.toLowerCase().replace(/\s+/g, "-"),
    genres: ["punk"],
    area: "Bay Area",
    colorHex: "#7B8FFF",
    initials: name.slice(0, 2).toUpperCase(),
    followerCount: 0,
    bio: "",
    pastShows: [],
  };
}

function venueFields(name: string) {
  return {
    name,
    area: "Oakland",
    addr: "1 Test Way",
    distSF: "7 mi",
    distOak: "1 mi",
    lat: 37.8,
    lng: -122.27,
  };
}

function gigFields(startsAt: number) {
  return {
    price: 0,
    startsAt,
    doorsTime: "7PM / 8PM",
    flyKey: "paper",
    genres: ["punk"],
    desc: "",
    ticketing: "rsvp" as const,
    ageRequirement: "allAges" as const,
    cap: "No cap",
    goingCount: 0,
  };
}

describe("venues:list", () => {
  async function seedVenues() {
    const t = convexTest(schema);
    const venueIds = await t.run(async (ctx) => [
      await ctx.db.insert("venues", {
        name: "Oakland Secret",
        area: "Oakland",
        addr: "1618 Telegraph Ave",
        distSF: "11.4 mi",
        distOak: "0.3 mi",
        lat: 37.8058,
        lng: -122.2705,
      }),
      await ctx.db.insert("venues", {
        name: "Kingman Hall",
        area: "Berkeley",
        addr: "1730 La Loma Ave",
        distSF: "12.1 mi",
        distOak: "5.4 mi",
        lat: 37.8792,
        lng: -122.2611,
      }),
    ]);
    return { t, venueIds };
  }

  test("returns every venue, name-ordered", async () => {
    const { t } = await seedVenues();
    const venues = await t.query(api.venues.list, {});
    expect(venues.map((v) => v.name)).toEqual([
      "Kingman Hall",
      "Oakland Secret",
    ]);
  });

  test("includes venues no gig references — the gap that made them unreadable", async () => {
    const { t } = await seedVenues();
    const orphanId = await t.run(async (ctx) =>
      ctx.db.insert("venues", {
        name: "2863 Derby St",
        area: "Berkeley",
        addr: "2863 Derby St",
        distSF: "13.0 mi",
        distOak: "6.1 mi",
        lat: 37.8598,
        lng: -122.2503,
      }),
    );

    // No gigs exist at all, so the feed carries no venues.
    const feed = await t.query(api.gigs.feedV2, {});
    expect(feed.venues).toEqual([]);

    const venues = await t.query(api.venues.list, {});
    expect(venues.some((v) => v._id === orphanId)).toBe(true);
    expect(venues.length).toBe(3);
  });

  test("is public — an anonymous visitor can read the venue list", async () => {
    const { t } = await seedVenues();
    expect((await t.query(api.venues.list, {})).length).toBe(2);
  });

  test("returns an empty array when there are no venues", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.venues.list, {})).toEqual([]);
  });
});

describe("venues:create", () => {
  async function setupAdmin() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "venue_admin",
      email: "venue@x.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Venue Makers",
      genres: ["punk"],
      bio: "",
      area: "Oakland",
      inviteHandles: [],
    });
    return { t, asAdmin, bandId };
  }

  const newVenue = {
    name: "  The New Room ",
    area: " Downtown Oakland ",
    addr: " 123 Test Street ",
    lat: 37.8044,
    lng: -122.2712,
  };

  test("requires a band admin and a valid map coordinate", async () => {
    const { t, asAdmin, bandId } = await setupAdmin();
    const asStranger = t.withIdentity({
      subject: "venue_stranger",
      email: "s@x.com",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.venues.create, { bandId, ...newVenue }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asAdmin.mutation(api.venues.create, { ...newVenue, bandId, lat: 91 }),
    ).rejects.toThrow("valid map location");
  });

  test("creates immediately and returns normalized duplicates instead of adding rows", async () => {
    const { t, asAdmin, bandId } = await setupAdmin();
    const first = await asAdmin.mutation(api.venues.create, {
      bandId,
      ...newVenue,
    });
    expect(first.created).toBe(true);
    expect(first.venue).toMatchObject({
      name: "The New Room",
      area: "Downtown Oakland",
      addr: "123 Test Street",
      lat: newVenue.lat,
      lng: newVenue.lng,
      exactAddr: "123 Test Street",
      slug: "the-new-room",
    });
    expect(
      await t.query(api.venues.privateDetail, { venueId: first.venue._id }),
    ).toEqual({
      venueId: first.venue._id,
      addr: "123 Test Street",
      lat: newVenue.lat,
      lng: newVenue.lng,
      loadInNotes: null,
      capacity: null,
    });

    const duplicate = await asAdmin.mutation(api.venues.create, {
      bandId,
      ...newVenue,
      name: "the   new room",
      area: "downtown oakland",
      addr: "123   TEST STREET",
    });
    expect(duplicate).toMatchObject({ created: false });
    expect(duplicate.venue._id).toBe(first.venue._id);
    expect(await t.query(api.venues.list, {})).toHaveLength(1);
  });

  test("deduplicates venues inserted by the demo seed", async () => {
    const { t, asAdmin, bandId } = await setupAdmin();
    await t.mutation(internal.seed.seedDemo, {});
    const seededVenue = (await t.query(api.venues.list, {})).find(
      (venue) => venue.name === "The Foghorn Club",
    );
    expect(seededVenue).toBeDefined();

    const duplicate = await asAdmin.mutation(api.venues.create, {
      bandId,
      name: "The Foghorn Club",
      area: "Mission, SF",
      addr: "2455 Harrison St, San Francisco",
      lat: 37.7524,
      lng: -122.418,
    });

    expect(duplicate.created).toBe(false);
    expect(duplicate.venue._id).toBe(seededVenue!._id);
  });

  test("creates separately when only an on-ticket venue's private address matches", async () => {
    const { t, asAdmin, bandId } = await setupAdmin();
    const hiddenVenueId = await asAdmin.run(async (ctx) => {
      const owner = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "venue_admin"))
        .unique();
      if (!owner) throw new Error("Test user missing");
      const organizationId = await ctx.db.insert("organizations", {
        name: "Hidden Venue Organization",
        slug: "hidden-venue-organization",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: owner._id,
        createdAt: 1,
        updatedAt: 1,
      });
      const venueId = await ctx.db.insert("venues", {
        ...venueFields("Hidden Organization Room"),
        area: "Downtown, Oakland",
        addr: "Downtown, Oakland",
        normalizedName: "hidden organization room",
        status: "verified",
        addressDisclosure: "onTicket",
        managedByOrganizationId: organizationId,
        approxLabel: "Downtown, Oakland",
        approxLat: 37.8044,
        approxLng: -122.2711,
      });
      await ctx.db.insert("venuePrivateDetails", {
        venueId,
        addr: "987 Secret Street",
        lat: 37.806,
        lng: -122.272,
        normalizedAddr: "987 secret street",
        updatedAt: 1,
      });
      return venueId;
    });

    const created = await asAdmin.mutation(api.venues.create, {
      bandId,
      name: "A Completely Different Name",
      area: "Somewhere Else",
      addr: " 987   SECRET STREET ",
      lat: 37.806,
      lng: -122.272,
    });
    expect(created.created).toBe(true);
    expect(created.venue._id).not.toBe(hiddenVenueId);
    expect(await t.query(api.venues.list, {})).toHaveLength(2);
  });
});

describe("venues:resolvePublic", () => {
  test("resolves by slug and id and hides misses and suspended venues", async () => {
    const t = convexTest(schema);
    const { venueId, suspendedId } = await t.run(async (ctx) => ({
      venueId: await ctx.db.insert("venues", {
        ...venueFields("Slug Room"),
        slug: "slug-room",
        status: "verified",
        addressDisclosure: "public",
      }),
      suspendedId: await ctx.db.insert("venues", {
        ...venueFields("Suspended Room"),
        slug: "suspended-room",
        status: "suspended",
      }),
    }));

    const bySlug = await t.query(api.venues.resolvePublic, {
      ref: "slug-room",
    });
    const byId = await t.query(api.venues.resolvePublic, { ref: venueId });
    expect(bySlug?._id).toBe(venueId);
    expect(byId).toEqual(bySlug);
    expect(
      await t.query(api.venues.resolvePublic, { ref: suspendedId }),
    ).toBeNull();
    expect(
      await t.query(api.venues.resolvePublic, { ref: "does-not-exist" }),
    ).toBeNull();
  });
});

describe("venues:privateDetail", () => {
  test("gates exact details by disclosure, organization status, and admin access", async () => {
    const t = convexTest(schema);
    const asMember = t.withIdentity({
      subject: "venue_private_member",
      email: "member-private@example.com",
    });
    const asAdmin = t.withIdentity({
      subject: "venue_private_admin",
      email: "admin-private@example.com",
    });
    await asMember.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.users.ensureUser, {});
    const { venueId, organizationId } = await t.run(async (ctx) => {
      const member = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) =>
          q.eq("clerkId", "venue_private_member"),
        )
        .unique();
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "venue_private_admin"))
        .unique();
      if (!member || !admin) throw new Error("Test users missing");
      const organizationId = await ctx.db.insert("organizations", {
        name: "Private Detail Venues",
        slug: "private-detail-venues",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: member._id,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: member._id,
        role: "manager",
        createdAt: 1,
      });
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });
      const venueId = await ctx.db.insert("venues", {
        ...venueFields("Private Detail Room"),
        area: "Downtown, Oakland",
        addr: "Downtown, Oakland",
        status: "verified",
        addressDisclosure: "onTicket",
        managedByOrganizationId: organizationId,
        approxLabel: "Downtown, Oakland",
        approxLat: 37.8044,
        approxLng: -122.2711,
      });
      await ctx.db.insert("venuePrivateDetails", {
        venueId,
        addr: "101 Exact Avenue",
        lat: 37.81,
        lng: -122.26,
        normalizedAddr: "101 exact avenue",
        loadInNotes: "Use the alley",
        capacity: 250,
        updatedAt: 1,
      });
      return { venueId, organizationId };
    });
    const fullPayload = {
      venueId,
      addr: "101 Exact Avenue",
      lat: 37.81,
      lng: -122.26,
      loadInNotes: "Use the alley",
      capacity: 250,
    };

    expect(await t.query(api.venues.privateDetail, { venueId })).toBeNull();
    expect(await asMember.query(api.venues.privateDetail, { venueId })).toEqual(
      fullPayload,
    );

    await t.run((ctx) => ctx.db.patch(organizationId, { status: "suspended" }));
    expect(
      await asMember.query(api.venues.privateDetail, { venueId }),
    ).toBeNull();
    expect(await asAdmin.query(api.venues.privateDetail, { venueId })).toEqual(
      fullPayload,
    );

    await t.run(async (ctx) => {
      await ctx.db.patch(organizationId, { status: "verified" });
      await ctx.db.patch(venueId, { addressDisclosure: "public" });
    });
    expect(await t.query(api.venues.privateDetail, { venueId })).toEqual(
      {
        ...fullPayload,
        loadInNotes: null,
        capacity: null,
      },
    );
    expect(await asMember.query(api.venues.privateDetail, { venueId })).toEqual(
      fullPayload,
    );
  });
});

describe("venues:detail", () => {
  test("isolates the venue, orders gigs, and deduplicates lineup bands", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    const { venueId, firstBandId, secondBandId } = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Test Room"));
      const otherVenueId = await ctx.db.insert(
        "venues",
        venueFields("Other Room"),
      );
      const firstBandId = await ctx.db.insert(
        "bands",
        bandFields("Alpha Band"),
      );
      const secondBandId = await ctx.db.insert(
        "bands",
        bandFields("Beta Band"),
      );
      await ctx.db.insert("gigs", {
        ...gigFields(now + 2_000),
        title: "Second",
        venueId,
        lineup: [firstBandId, firstBandId, secondBandId],
      });
      // Deliberately omit the stored age to model a row from before v1.10.
      const { ageRequirement: _legacyAge, ...legacyGig } = gigFields(
        now + 1_000,
      );
      await ctx.db.insert("gigs", {
        ...legacyGig,
        title: "First",
        venueId,
        lineup: [secondBandId],
      });
      await ctx.db.insert("gigs", {
        ...gigFields(now + 500),
        title: "Wrong Venue",
        venueId: otherVenueId,
        lineup: [firstBandId],
      });
      return { venueId, firstBandId, secondBandId };
    });

    const detail = await t.query(api.venues.detail, { venueId });
    expect(detail?.venue._id).toBe(venueId);
    expect(detail?.gigs.map((gig) => gig.title)).toEqual(["First", "Second"]);
    expect(detail?.gigs[0].ageRequirement).toBe("allAges");
    expect(detail?.bands.map((band) => band._id)).toEqual([
      secondBandId,
      firstBandId,
    ]);
    expect(detail?.truncated).toBe(false);
  });

  test("includes organizer-editable public venue fields", async () => {
    const t = convexTest(schema);
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        ...venueFields("Editable Room"),
        description: "An intimate all-ages venue.",
        venueType: "club",
        capacityPublic: 250,
      }),
    );

    const detail = await t.query(api.venues.detail, { venueId });
    expect(detail?.venue).toMatchObject({
      description: "An intimate all-ages venue.",
      venueType: "club",
      capacityPublic: 250,
    });
  });

  test("returns null for a missing venue", async () => {
    const t = convexTest(schema);
    const missingVenueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Gone Room"));
      await ctx.db.delete(venueId);
      return venueId;
    });

    expect(
      await t.query(api.venues.detail, { venueId: missingVenueId }),
    ).toBeNull();
  });

  test("returns the next 200 venue gigs and reports truncation", async () => {
    const t = convexTest(schema);
    const firstStartsAt = Date.now() + 86_400_000;
    const venueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Big Room"));
      for (let index = 0; index < 201; index++) {
        await ctx.db.insert("gigs", {
          ...gigFields(firstStartsAt + index * 60_000),
          title: `Gig ${index}`,
          venueId,
          lineup: [],
        });
      }
      return venueId;
    });

    const detail = await t.query(api.venues.detail, { venueId });
    expect(detail?.gigs).toHaveLength(200);
    expect(detail?.gigs[0].title).toBe("Gig 0");
    expect(detail?.gigs[199].title).toBe("Gig 199");
    expect(detail?.bands).toEqual([]);
    expect(detail?.truncated).toBe(true);
  });

  test("hydrates repeated owners, lineup bands and flyers to the same values as one-off lookups", async () => {
    const t = convexTest(schema);
    const now = Date.now();
    const fixture = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", venueFields("Shared Room"));
      const ownerId = await ctx.db.insert("bands", bandFields("Owner"));
      const alphaId = await ctx.db.insert("bands", bandFields("Alpha"));
      const betaId = await ctx.db.insert("bands", bandFields("Beta"));
      const archivedId = await ctx.db.insert("bands", {
        ...bandFields("Archived"),
        archivedAt: now,
      });
      const flyerStorageId = await ctx.storage.store(new Blob(["flyer"]));
      const gigs = {
        first: await ctx.db.insert("gigs", {
          ...gigFields(now + 1_000),
          title: "First",
          venueId,
          createdByBand: ownerId,
          flyKey: "custom",
          flyStorageId: flyerStorageId,
          lineup: [ownerId, alphaId],
        }),
        second: await ctx.db.insert("gigs", {
          ...gigFields(now + 2_000),
          title: "Second",
          venueId,
          createdByBand: ownerId,
          flyKey: "custom",
          flyStorageId: flyerStorageId,
          lineup: [alphaId, betaId, archivedId],
        }),
        archivedOwner: await ctx.db.insert("gigs", {
          ...gigFields(now + 3_000),
          title: "Archived owner",
          venueId,
          createdByBand: archivedId,
          lineup: [alphaId],
        }),
        third: await ctx.db.insert("gigs", {
          ...gigFields(now + 4_000),
          title: "Third",
          venueId,
          createdByBand: ownerId,
          lineup: [betaId],
          performers: [{ name: "Beta (live)", role: "headliner" as const }],
        }),
      };
      const flyerUrl = await ctx.storage.getUrl(flyerStorageId);
      return { venueId, ownerId, alphaId, betaId, archivedId, gigs, flyerUrl };
    });
    expect(fixture.flyerUrl).not.toBeNull();

    const commonGig = {
      venueId: fixture.venueId,
      price: 0,
      doorsTime: "7PM / 8PM",
      genres: ["punk"],
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
      goingCount: 0,
      createdByBand: fixture.ownerId,
      lifecycle: "published",
      discoveryListingReady: false,
    };
    const bandPayload = (bandId: string, name: string) => ({
      _id: bandId,
      slug: name.toLowerCase().replace(/\s+/g, "-"),
      name,
      genres: ["punk"],
      area: "Bay Area",
      colorHex: "#7B8FFF",
      initials: name.slice(0, 2).toUpperCase(),
      followerCount: 0,
      heroUrl: null,
      avatarUrl: null,
      bannerUrl: null,
      bio: "",
      linkIg: null,
      linkBc: null,
      linkYt: null,
      credits: null,
      profileComplete: false,
      discoveryProfileReady: false,
      pastShows: [],
    });

    expect(
      await t.query(api.venues.detail, { venueId: fixture.venueId }),
    ).toEqual({
      venue: {
        _id: fixture.venueId,
        name: "Shared Room",
        area: "Oakland",
        addr: "1 Test Way",
        distSF: "7 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
        slug: null,
        approxLocation: {
          lat: 37.8044,
          lng: -122.2711,
          label: "Downtown, Oakland",
        },
        neighborhood: "Downtown",
        city: "Oakland",
        description: null,
        venueType: null,
        capacityPublic: null,
        addressDisclosure: "public",
        verified: false,
        managedByOrganizationId: null,
        exactAddr: "1 Test Way",
      },
      gigs: [
        {
          ...commonGig,
          _id: fixture.gigs.first,
          slug: fixture.gigs.first,
          title: "First",
          startsAt: now + 1_000,
          doorsAt: now + 1_000,
          flyKey: "custom",
          flyerUrl: fixture.flyerUrl,
          lineup: [fixture.ownerId, fixture.alphaId],
          performers: [
            { name: "Owner", role: "headliner", bandId: fixture.ownerId },
            { name: "Alpha", role: "support", bandId: fixture.alphaId },
          ],
        },
        {
          ...commonGig,
          _id: fixture.gigs.second,
          slug: fixture.gigs.second,
          title: "Second",
          startsAt: now + 2_000,
          doorsAt: now + 2_000,
          flyKey: "custom",
          flyerUrl: fixture.flyerUrl,
          lineup: [fixture.alphaId, fixture.betaId, fixture.archivedId],
          performers: [
            { name: "Alpha", role: "headliner", bandId: fixture.alphaId },
            { name: "Beta", role: "support", bandId: fixture.betaId },
            { name: "Archived", role: "support", bandId: fixture.archivedId },
          ],
        },
        {
          ...commonGig,
          _id: fixture.gigs.third,
          slug: fixture.gigs.third,
          title: "Third",
          startsAt: now + 4_000,
          doorsAt: now + 4_000,
          flyKey: "paper",
          flyerUrl: null,
          lineup: [fixture.betaId],
          performers: [{ name: "Beta (live)", role: "headliner" }],
        },
      ],
      bands: [
        bandPayload(fixture.ownerId, "Owner"),
        bandPayload(fixture.alphaId, "Alpha"),
        bandPayload(fixture.betaId, "Beta"),
      ],
      truncated: false,
    });
  });
});

describe("venue address disclosure", () => {
  test("uses an approximate public location for a pending venue", async () => {
    const t = convexTest(schema);
    const stored = {
      ...venueFields("Private Room"),
      status: "pending" as const,
      addr: "99 Private Lane",
      lat: 37.8058,
      lng: -122.2705,
    };
    const venueId = await t.run((ctx) => ctx.db.insert("venues", stored));

    const venue = (await t.query(api.venues.list, {})).find(
      (entry) => entry._id === venueId,
    );
    expect(venue).toBeDefined();
    expect(venue!.addr).toBe(venue!.approxLocation.label);
    expect(venue!.addr).not.toBe(stored.addr);
    expect(venue!.lat).not.toBe(stored.lat);
    expect(venue!.lng).not.toBe(stored.lng);
    expect(venue!.exactAddr).toBeNull();
    expect(venue!.verified).toBe(false);
    expect(venue!.approxLocation).toEqual({
      lat: expect.any(Number),
      lng: expect.any(Number),
      label: expect.any(String),
    });
  });

  test("keeps exact coordinates public for a verified public venue", async () => {
    const t = convexTest(schema);
    const stored = {
      ...venueFields("Public Room"),
      status: "verified" as const,
      addressDisclosure: "public" as const,
      addr: "100 Public Plaza",
      lat: 37.8123,
      lng: -122.2689,
    };
    const venueId = await t.run((ctx) => ctx.db.insert("venues", stored));

    const venue = (await t.query(api.venues.list, {})).find(
      (entry) => entry._id === venueId,
    );
    expect(venue).toBeDefined();
    expect(venue).toMatchObject({
      addr: stored.addr,
      lat: stored.lat,
      lng: stored.lng,
      exactAddr: stored.addr,
      verified: true,
    });
  });

  test("keeps legacy venue addresses public", async () => {
    const t = convexTest(schema);
    const stored = venueFields("Legacy Room");
    const venueId = await t.run((ctx) => ctx.db.insert("venues", stored));

    const venue = (await t.query(api.venues.list, {})).find(
      (entry) => entry._id === venueId,
    );
    expect(venue).toBeDefined();
    expect(venue!.addr).toBe(stored.addr);
    expect(venue!.exactAddr).toBe(stored.addr);
  });

  test("replaces a smuggled street-address area with the approximate label", async () => {
    const t = convexTest(schema);
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        ...venueFields("No Area Leak Room"),
        area: "123 Secret St",
        addr: "123 Secret St",
        lat: 37.81,
        lng: -122.26,
        status: "verified",
        addressDisclosure: "onTicket",
        approxLabel: "Downtown, Oakland",
        approxLat: 37.8044,
        approxLng: -122.2711,
      }),
    );

    const venue = (await t.query(api.venues.list, {})).find(
      (entry) => entry._id === venueId,
    );
    expect(venue).toMatchObject({
      area: "Downtown, Oakland",
      addr: "Downtown, Oakland",
      lat: 37.8044,
      lng: -122.2711,
      exactAddr: null,
    });
  });
});

describe("organization-managed venue location mutations", () => {
  async function setupManagedVenues() {
    const t = convexTest(schema);
    const asOwner = t.withIdentity({
      subject: "managed_venue_owner",
      email: "managed-owner@example.com",
    });
    const asManager = t.withIdentity({
      subject: "managed_venue_manager",
      email: "managed-manager@example.com",
    });
    await asOwner.mutation(api.users.ensureUser, {});
    await asManager.mutation(api.users.ensureUser, {});
    const ids = await t.run(async (ctx) => {
      const owner = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "managed_venue_owner"))
        .unique();
      const manager = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) =>
          q.eq("clerkId", "managed_venue_manager"),
        )
        .unique();
      if (!owner || !manager) throw new Error("Test users missing");
      const organizationId = await ctx.db.insert("organizations", {
        name: "Managed Venue Group",
        slug: "managed-venue-group",
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
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: manager._id,
        role: "manager",
        createdAt: 1,
      });
      const common = {
        ...venueFields("Managed Room"),
        area: "Downtown, Oakland",
        addr: "Downtown, Oakland",
        status: "verified" as const,
        managedByOrganizationId: organizationId,
        approxLabel: "Downtown, Oakland",
        approxLat: 37.8044,
        approxLng: -122.2711,
        neighborhood: "Downtown",
        city: "Oakland",
      };
      const onTicketVenueId = await ctx.db.insert("venues", {
        ...common,
        name: "On Ticket Room",
        slug: "on-ticket-room",
        addressDisclosure: "onTicket",
      });
      const publicVenueId = await ctx.db.insert("venues", {
        ...common,
        name: "Public Managed Room",
        slug: "public-managed-room",
        addressDisclosure: "public",
      });
      for (const venueId of [onTicketVenueId, publicVenueId]) {
        await ctx.db.insert("venuePrivateDetails", {
          venueId,
          addr: "10 Old Exact Street",
          lat: 37.8,
          lng: -122.27,
          normalizedAddr: "10 old exact street",
          updatedAt: 1,
        });
      }
      return { organizationId, onTicketVenueId, publicVenueId };
    });
    return { t, asOwner, asManager, ...ids };
  }

  test("updatePrivateDetails keeps private venues approximate and public venues exact", async () => {
    const { t, asOwner, onTicketVenueId, publicVenueId } =
      await setupManagedVenues();
    const exact = {
      addr: "2455 Harrison St, San Francisco",
      lat: 37.7524,
      lng: -122.418,
      loadInNotes: "  Ring the side bell  ",
      capacity: 300,
    };

    await asOwner.mutation(api.venues.updatePrivateDetails, {
      venueId: onTicketVenueId,
      ...exact,
    });
    await asOwner.mutation(api.venues.updatePrivateDetails, {
      venueId: publicVenueId,
      ...exact,
      addr: "2457 Harrison St, San Francisco",
    });

    const privatePublic = (await t.query(api.venues.detail, {
      venueId: onTicketVenueId,
    }))!.venue;
    expect(privatePublic).toMatchObject({
      area: "Mission, San Francisco",
      addr: "Mission, San Francisco",
      lat: 37.7599,
      lng: -122.4148,
      exactAddr: null,
    });
    expect(privatePublic.addr).not.toBe(exact.addr);

    const exactPublic = (await t.query(api.venues.detail, {
      venueId: publicVenueId,
    }))!.venue;
    expect(exactPublic).toMatchObject({
      addr: "2457 Harrison St, San Francisco",
      lat: exact.lat,
      lng: exact.lng,
      exactAddr: "2457 Harrison St, San Francisco",
    });
    expect(
      await asOwner.query(api.venues.privateDetail, {
        venueId: onTicketVenueId,
      }),
    ).toMatchObject({
      addr: exact.addr,
      lat: exact.lat,
      lng: exact.lng,
      loadInNotes: "Ring the side bell",
      capacity: 300,
    });
  });

  test("updatePrivateDetails never uses a private street address as an approximate fallback", async () => {
    const { t, asOwner, organizationId } = await setupManagedVenues();
    const area = "Santa Cruz Area";
    const exactAddress = "404 Hidden Wharf Street, Santa Cruz, CA";
    const venueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        ...venueFields("Santa Cruz Fallback Room"),
        slug: "santa-cruz-fallback-room",
        area,
        addr: area,
        lat: 36.97,
        lng: -122.03,
        status: "verified",
        addressDisclosure: "onTicket",
        managedByOrganizationId: organizationId,
      }),
    );

    await asOwner.mutation(api.venues.updatePrivateDetails, {
      venueId,
      addr: exactAddress,
      lat: 36.9741,
      lng: -122.0308,
    });

    const publicVenue = await t.query(api.venues.resolvePublic, {
      ref: venueId,
    });
    expect(publicVenue).toMatchObject({
      addr: area,
      area,
      approxLocation: { label: area },
    });
    expect(publicVenue?.addr).not.toContain(exactAddress);
    expect(publicVenue?.area).not.toContain(exactAddress);
    expect(publicVenue?.approxLocation.label).not.toContain(exactAddress);
  });

  test("setAddressDisclosure immediately rewrites public location columns", async () => {
    const { t, asOwner, asManager, onTicketVenueId } =
      await setupManagedVenues();

    await asOwner.mutation(api.venues.setAddressDisclosure, {
      venueId: onTicketVenueId,
      addressDisclosure: "public",
    });
    const publicDetail = await t.query(api.venues.detail, {
      venueId: onTicketVenueId,
    });
    expect(publicDetail?.venue).toMatchObject({
      addr: "10 Old Exact Street",
      lat: 37.8,
      lng: -122.27,
      exactAddr: "10 Old Exact Street",
    });
    const storedPublicVenue = await t.run((ctx) =>
      ctx.db.get(onTicketVenueId),
    );
    expect(storedPublicVenue?.normalizedAddr).toBe("10 old exact street");

    await expect(
      asManager.mutation(api.venues.setAddressDisclosure, {
        venueId: onTicketVenueId,
        addressDisclosure: "onTicket",
      }),
    ).rejects.toThrow("Not permitted for this organization");

    await asOwner.mutation(api.venues.setAddressDisclosure, {
      venueId: onTicketVenueId,
      addressDisclosure: "onTicket",
    });
    const privateListItem = (await t.query(api.venues.list, {})).find(
      (venue) => venue._id === onTicketVenueId,
    );
    expect(privateListItem).toMatchObject({
      addr: "Downtown, Oakland",
      lat: 37.8044,
      lng: -122.2711,
      exactAddr: null,
    });
    const storedPrivateVenue = await t.run((ctx) =>
      ctx.db.get(onTicketVenueId),
    );
    expect(storedPrivateVenue?.normalizedAddr).toBeUndefined();
  });
});
