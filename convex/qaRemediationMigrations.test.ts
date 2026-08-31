import { runToCompletion } from "@convex-dev/migrations";
import migrationsTest from "@convex-dev/migrations/test";
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, components, internal } from "./_generated/api";
import schema from "./schema";

describe("QA remediation migrations", () => {
  test("backfills stable gig refs, venue keys, and reserved band slugs", async () => {
    const t = convexTest(schema);
    migrationsTest.register(t);
    const asAdmin = t.withIdentity({
      subject: "migration_admin",
      email: "migration@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Migration Band",
      genres: ["punk"],
      bio: "",
      area: "Oakland",
    });

    const fixture = await t.run(async (ctx) => {
      await ctx.db.patch(bandId, { slug: "g" });
      const venueId = await ctx.db.insert("venues", {
        name: "  Migration   Hall ",
        area: "Oakland",
        addr: "  12   Test Street ",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const gigFields = {
        title: "Migration Night",
        venueId,
        price: 0,
        startsAt: Date.now() + 86_400_000,
        doorsTime: "8PM / 9PM",
        flyKey: "xerox" as const,
        lineup: [bandId],
        genres: ["punk"],
        desc: "",
        ticketing: "rsvp" as const,
        cap: "No cap",
        goingCount: 0,
      };
      const firstGigId = await ctx.db.insert("gigs", gigFields);
      const secondGigId = await ctx.db.insert("gigs", {
        ...gigFields,
        startsAt: gigFields.startsAt + 86_400_000,
      });
      const projectId = await ctx.db.insert("gigProjects", {
        bandId,
        status: "published",
        revision: 1,
        publishedRevision: 1,
        publicGigId: firstGigId,
        title: gigFields.title,
        startsAt: gigFields.startsAt,
        venueId,
        price: 0,
        flyKey: "xerox",
        overlay: true,
        desc: "",
        ticketing: "rsvp",
        ageRequirement: "allAges",
        cap: "No cap",
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      return { firstGigId, secondGigId, projectId, venueId };
    });

    for (const migration of [
      internal.migrations.backfillGigSlugs,
      internal.migrations.backfillVenueNormalizedKeys,
      internal.migrations.repairReservedBandSlugs,
    ]) {
      await t.run((ctx) =>
        runToCompletion(ctx, components.migrations, migration),
      );
    }

    const values = await t.run(async (ctx) => ({
      band: await ctx.db.get(bandId),
      venue: await ctx.db.get(fixture.venueId),
      firstGig: await ctx.db.get(fixture.firstGigId),
      secondGig: await ctx.db.get(fixture.secondGigId),
      project: await ctx.db.get(fixture.projectId),
    }));
    expect(values.firstGig?.slug).toBe("migration-night");
    expect(values.secondGig?.slug).toBe("migration-night-2");
    expect(values.project?.publicSlug).toBe(values.firstGig?.slug);
    expect(values.venue).toMatchObject({
      normalizedName: "migration hall",
      normalizedAddr: "12 test street",
    });
    expect(values.band?.slug).not.toBe("g");

    for (const migration of [
      internal.migrations.backfillGigSlugs,
      internal.migrations.backfillVenueNormalizedKeys,
      internal.migrations.repairReservedBandSlugs,
    ]) {
      await t.run((ctx) =>
        runToCompletion(ctx, components.migrations, migration),
      );
    }
    expect(
      await t.run(async (ctx) => (await ctx.db.get(fixture.firstGigId))?.slug),
    ).toBe(values.firstGig?.slug);
  });
});
