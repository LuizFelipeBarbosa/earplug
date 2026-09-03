import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

function bandFields(name: string, followerCount: number) {
  return {
    name,
    slug: name.toLowerCase().replace(/\s+/g, "-"),
    genres: ["post-punk"],
    area: "Oakland",
    colorHex: "#7B8FFF",
    initials: "TS",
    followerCount,
    bio: "",
    pastShows: [],
  };
}

async function setupPublishFixture() {
  const t = convexTest(schema);
  const { bandId, venueId } = await t.run(async (ctx) => {
    const bandId = await ctx.db.insert(
      "bands",
      bandFields("Production Values", 0),
    );
    const venueId = await ctx.db.insert("venues", {
      name: "The Real Room",
      area: "Mission, SF",
      addr: "123 Valencia St",
      distSF: "0.5 mi",
      distOak: "7.0 mi",
      lat: 37.76,
      lng: -122.42,
    });
    return { bandId, venueId };
  });
  return {
    t,
    bandId,
    venueId,
    fields: {
      bandId,
      title: "A Real Upcoming Gig",
      startsAt: Date.now() + 86_400_000,
      doorsTime: "7PM / 8PM",
      venueId,
      price: 18,
      flyKey: "blueprint" as const,
      ticketing: "rsvp" as const,
      ageRequirement: "allAges" as const,
      cap: "150",
    },
  };
}

describe("maintenance:publishRealGig", () => {
  test("dry runs by default, validating without writing", async () => {
    const { t, fields } = await setupPublishFixture();
    const result = await t.mutation(
      internal.maintenance.publishRealGig,
      fields,
    );
    expect(result).toEqual({
      gigId: null,
      created: false,
      alreadyExisted: false,
      bandName: "Production Values",
      venueName: "The Real Room",
    });
    expect(
      await t.run(async (ctx) => ctx.db.query("gigs").take(10)),
    ).toHaveLength(0);
  });

  test("publishes without band-admin auth", async () => {
    const { t, bandId, fields } = await setupPublishFixture();
    const result = await t.mutation(internal.maintenance.publishRealGig, {
      ...fields,
      dryRun: false,
    });
    expect(result).toMatchObject({ created: true, alreadyExisted: false });
    const gig = await t.run(async (ctx) => ctx.db.get(result.gigId!));
    expect(gig).toMatchObject({
      lineup: [bandId],
      genres: ["post-punk"],
      desc: "",
      createdByBand: bandId,
      goingCount: 0,
      flyKey: "blueprint",
    });
  });

  test("publishes a gig reachable from gigs:feed", async () => {
    const { t, fields } = await setupPublishFixture();
    const result = await t.mutation(internal.maintenance.publishRealGig, {
      ...fields,
      startsAt: Date.now() + 86_400_000,
      dryRun: false,
    });
    const feed = await t.query(api.gigs.feedV2, {});
    expect(feed.gigs.some((gig) => gig._id === result.gigId)).toBe(true);
  });

  test("rejects the same invalid publish inputs with the same messages", async () => {
    const { t, fields } = await setupPublishFixture();
    const missingVenueId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", {
        name: "Deleted Room",
        area: "Oakland",
        addr: "Gone",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      await ctx.db.delete(venueId);
      return venueId;
    });
    const cases = [
      {
        args: { ...fields, startsAt: -1 },
        message: "Invalid startsAt",
      },
      {
        args: { ...fields, startsAt: Number.POSITIVE_INFINITY },
        message: "Invalid startsAt",
      },
      {
        args: {
          ...fields,
          ticketing: "external" as const,
          externalUrl: "ftp://tickets.example.com",
        },
        message: "External ticketing requires a valid HTTPS URL",
      },
      {
        args: { ...fields, flyKey: "custom" as const },
        message: "Custom flyer requires flyStorageId",
      },
      {
        args: { ...fields, venueId: missingVenueId },
        message: "Venue not found",
      },
    ];

    for (const invalid of cases) {
      await expect(
        t.mutation(internal.maintenance.publishRealGig, invalid.args),
      ).rejects.toThrow(invalid.message);
    }
  });

  test("returns the existing gig when identical details are re-run", async () => {
    const { t, fields } = await setupPublishFixture();
    const args = { ...fields, dryRun: false };
    const first = await t.mutation(internal.maintenance.publishRealGig, args);
    const second = await t.mutation(internal.maintenance.publishRealGig, args);

    expect(first).toMatchObject({ created: true, alreadyExisted: false });
    expect(second).toMatchObject({
      gigId: first.gigId,
      created: false,
      alreadyExisted: true,
    });
    expect(
      await t.run(async (ctx) =>
        ctx.db
          .query("gigs")
          .withIndex("by_title", (q) => q.eq("title", fields.title))
          .take(20),
      ),
    ).toHaveLength(1);
  });
});
