import { convexTest } from "convex-test";
import { runToCompletion } from "@convex-dev/migrations";
import migrationsTest from "@convex-dev/migrations/test";
import { describe, expect, test } from "vitest";
import { api, components, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import schema from "./schema";

const DAY_MS = 24 * 60 * 60 * 1000;

async function setup() {
  const t = convexTest(schema);
  migrationsTest.register(t);
  const asAdmin = t.withIdentity({
    subject: "discovery_admin",
    email: "discovery@example.com",
  });
  await asAdmin.mutation(api.users.ensureUser, {});
  const { bandId } = await asAdmin.mutation(api.bands.createBand, {
    name: "Discovery Band",
    genres: ["punk"],
    bio: "A complete public bio.",
    area: "Oakland",
  });
  const venueId = await t.run(async (ctx) =>
    ctx.db.insert("venues", {
      name: "Discovery Hall",
      area: "Oakland",
      addr: "1 Complete Way",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
    }),
  );
  return { t, asAdmin, bandId, venueId };
}

async function addMedia(
  setupResult: Awaited<ReturnType<typeof setup>>,
  kind: "photo" | "video",
) {
  const storageId = await setupResult.t.run(async (ctx) =>
    ctx.storage.store(new Blob([kind])),
  );
  const { mediaId } = await setupResult.asAdmin.mutation(api.media.addMedia, {
    bandId: setupResult.bandId,
    kind,
    storageId,
    title: `${kind} upload`,
  });
  return { mediaId, storageId };
}

async function completeProfileMedia(
  setupResult: Awaited<ReturnType<typeof setup>>,
) {
  const video = await addMedia(setupResult, "video");
  const photo = await addMedia(setupResult, "photo");
  await setupResult.asAdmin.mutation(api.bands.setBandPhoto, {
    bandId: setupResult.bandId,
    mediaId: photo.mediaId,
  });
  return { video, photo };
}

async function createPublishableProject(
  setupResult: Awaited<ReturnType<typeof setup>>,
  options: {
    startsAt?: number;
    flyKey?: string;
    flyStorageId?: Id<"_storage"> | null;
    overlay?: boolean;
  } = {},
) {
  const draft = await setupResult.asAdmin.mutation(api.gigs.createDraft, {
    bandId: setupResult.bandId,
  });
  const startsAt = options.startsAt ?? Date.now() + 2 * DAY_MS;
  await setupResult.asAdmin.mutation(api.gigs.saveDraft, {
    projectId: draft._id,
    revision: draft.revision,
    title: "Complete Listing",
    doorsAt: startsAt - 60 * 60 * 1000,
    startsAt,
    venueId: setupResult.venueId,
    price: 0,
    flyKey: options.flyKey ?? "xerox",
    flyStorageId: options.flyStorageId ?? null,
    overlay: options.overlay ?? true,
    desc: "",
    ticketing: "rsvp",
    ageRequirement: "allAges",
    externalUrl: null,
    cap: "No cap",
  });
  return await setupResult.asAdmin.query(api.gigs.getProject, {
    projectId: draft._id,
  });
}

describe("discovery profile readiness", () => {
  test("requires core profile, assigned image, and an uploaded clip", async () => {
    const fixture = await setup();
    expect(
      await fixture.t.query(api.bands.get, { bandId: fixture.bandId }),
    ).toMatchObject({
      profileComplete: true,
      discoveryProfileReady: false,
    });

    const { video, photo } = await completeProfileMedia(fixture);
    expect(
      await fixture.t.query(api.bands.get, { bandId: fixture.bandId }),
    ).toMatchObject({
      profileComplete: true,
      discoveryProfileReady: true,
    });
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(fixture.bandId))?.hasClip,
      ),
    ).toBe(true);

    await fixture.asAdmin.mutation(api.bands.updateProfile, {
      bandId: fixture.bandId,
      bio: "  ",
    });
    expect(
      await fixture.t.query(api.bands.get, { bandId: fixture.bandId }),
    ).toMatchObject({
      profileComplete: false,
      discoveryProfileReady: false,
    });
    await fixture.asAdmin.mutation(api.bands.updateProfile, {
      bandId: fixture.bandId,
      bio: "Complete again",
    });
    expect(
      (await fixture.t.query(api.bands.get, { bandId: fixture.bandId }))
        ?.discoveryProfileReady,
    ).toBe(true);

    await fixture.asAdmin.mutation(api.media.deleteMedia, {
      mediaId: video.mediaId,
    });
    expect(
      await fixture.t.query(api.bands.get, { bandId: fixture.bandId }),
    ).toMatchObject({
      profileComplete: true,
      discoveryProfileReady: false,
    });
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(fixture.bandId))?.hasClip,
      ),
    ).toBe(false);

    await fixture.t.run(async (ctx) => ctx.storage.delete(photo.storageId));
    expect(
      (await fixture.t.query(api.bands.get, { bandId: fixture.bandId }))
        ?.discoveryProfileReady,
    ).toBe(false);
  });

  test("profile image assignment enforces owner and media type", async () => {
    const fixture = await setup();
    const video = await addMedia(fixture, "video");
    await expect(
      fixture.asAdmin.mutation(api.bands.setBandPhoto, {
        bandId: fixture.bandId,
        mediaId: video.mediaId,
      }),
    ).rejects.toThrow("Only photos");

    const { bandId: otherBandId } = await fixture.asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Other Band",
        genres: ["noise"],
        bio: "Also complete",
        area: "Oakland",
      },
    );
    const photo = await addMedia(fixture, "photo");
    await expect(
      fixture.asAdmin.mutation(api.bands.setBandPhoto, {
        bandId: otherBandId,
        mediaId: photo.mediaId,
      }),
    ).rejects.toThrow("different band");
  });
});

describe("discovery listing readiness", () => {
  test("past projects cannot crowd an upcoming show out of readiness", async () => {
    const fixture = await setup();
    const now = Date.now();
    await fixture.t.run(async (ctx) => {
      for (let index = 0; index < 100; index++) {
        await ctx.db.insert("gigProjects", {
          bandId: fixture.bandId,
          status: "published",
          revision: 1,
          publishedRevision: 1,
          title: `Past Listing ${index}`,
          doorsAt: now - 2 * DAY_MS,
          startsAt: now - DAY_MS,
          venueId: fixture.venueId,
          price: 0,
          flyKey: "xerox",
          overlay: true,
          desc: "",
          ticketing: "rsvp",
          ageRequirement: "allAges",
          cap: "No cap",
          createdAt: now - DAY_MS + index,
          updatedAt: now - DAY_MS + index,
        });
      }
    });
    const project = await createPublishableProject(fixture, {
      startsAt: now + 2 * DAY_MS,
    });
    const { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });

    const readiness = await fixture.asAdmin.query(
      api.bands.discoveryReadiness,
      { bandId: fixture.bandId, now },
    );

    expect(readiness.relevantShow).toMatchObject({
      gigId,
      projectId: project._id,
    });
    expect(readiness.nextEligibleShow).toMatchObject({ gigId });
  });

  test("publishes, becomes stale on edits, and restores only on republish", async () => {
    const fixture = await setup();
    await completeProfileMedia(fixture);
    const project = await createPublishableProject(fixture);
    const { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(true);

    const published = await fixture.asAdmin.query(api.gigs.getProject, {
      projectId: project._id,
    });
    await fixture.asAdmin.mutation(api.gigs.saveDraft, {
      projectId: project._id,
      revision: published.revision,
      title: "Edited Listing",
      doorsAt: published.doorsAt,
      startsAt: published.startsAt,
      venueId: published.venueId,
      price: published.price,
      flyKey: published.flyKey,
      flyStorageId: published.flyStorageId,
      overlay: published.overlay,
      desc: "saved after publish",
      ticketing: published.ticketing,
      ageRequirement: published.ageRequirement,
      externalUrl: published.externalUrl,
      cap: published.cap,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(false);

    const now = Date.now();
    const stale = await fixture.asAdmin.query(api.bands.discoveryReadiness, {
      bandId: fixture.bandId,
      now,
    });
    expect(stale.publishedRevisionCurrent).toBe(false);
    await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(true);
  });

  test("allows text performers but blocks unresolved invitations", async () => {
    const fixture = await setup();
    const project = await createPublishableProject(fixture);
    await fixture.asAdmin.mutation(api.gigs.addPerformer, {
      projectId: project._id,
      kind: "text",
      name: "Text Opener",
      role: "opener",
    });
    let { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(true);

    await fixture.asAdmin.mutation(api.gigs.addPerformer, {
      projectId: project._id,
      kind: "invited",
      name: "Pending Guest",
      role: "support",
    });
    ({ gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    }));
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(false);
  });

  test("requires the creating band to remain in the published lineup", async () => {
    const fixture = await setup();
    const project = await createPublishableProject(fixture);
    const owner = project.performers.find(
      (performer) => performer.bandId === fixture.bandId,
    );
    if (!owner) throw new Error("Expected owner performer");
    await fixture.asAdmin.mutation(api.gigs.removePerformer, {
      performerId: owner._id,
    });
    await fixture.asAdmin.mutation(api.gigs.addPerformer, {
      projectId: project._id,
      kind: "text",
      name: "Text-only Headliner",
      role: "headliner",
    });
    const { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(false);
  });

  test("custom posters require their readable overlay", async () => {
    const fixture = await setup();
    const flyerStorageId = await fixture.t.run(async (ctx) =>
      ctx.storage.store(new Blob(["flyer"])),
    );
    const project = await createPublishableProject(fixture, {
      flyKey: "custom",
      flyStorageId: flyerStorageId,
      overlay: false,
    });
    const { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(false);

    const published = await fixture.asAdmin.query(api.gigs.getProject, {
      projectId: project._id,
    });
    await fixture.asAdmin.mutation(api.gigs.saveDraft, {
      projectId: project._id,
      revision: published.revision,
      title: published.title,
      doorsAt: published.doorsAt,
      startsAt: published.startsAt,
      venueId: published.venueId,
      price: published.price,
      flyKey: "custom",
      flyStorageId: flyerStorageId,
      overlay: true,
      desc: published.desc,
      ticketing: published.ticketing,
      ageRequirement: published.ageRequirement,
      externalUrl: published.externalUrl,
      cap: published.cap,
    });
    await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    expect(
      (await fixture.t.query(api.gigs.resolvePublic, { ref: gigId }))
        ?.discoveryListingReady,
    ).toBe(true);
  });

  test("admin detail returns the eligible show and inclusive boost window", async () => {
    const fixture = await setup();
    await completeProfileMedia(fixture);
    const startsAt = Date.now() + 2 * DAY_MS;
    const project = await createPublishableProject(fixture, { startsAt });
    const { gigId } = await fixture.asAdmin.mutation(api.gigs.publishDraft, {
      projectId: project._id,
    });
    const atOpen = await fixture.asAdmin.query(api.bands.discoveryReadiness, {
      bandId: fixture.bandId,
      now: startsAt - 7 * DAY_MS,
    });
    expect(atOpen.nextEligibleShow).toMatchObject({ gigId, startsAt });
    expect(atOpen.boostWindow).toEqual({
      opensAt: startsAt - 7 * DAY_MS,
      closesAt: startsAt + 6 * 60 * 60 * 1000,
      active: true,
    });
    const atClose = await fixture.asAdmin.query(api.bands.discoveryReadiness, {
      bandId: fixture.bandId,
      now: startsAt + 6 * 60 * 60 * 1000,
    });
    expect(atClose.boostWindow?.active).toBe(true);

    const stranger = fixture.t.withIdentity({
      subject: "discovery_stranger",
      email: "stranger@example.com",
    });
    await stranger.mutation(api.users.ensureUser, {});
    await expect(
      stranger.query(api.bands.discoveryReadiness, {
        bandId: fixture.bandId,
        now: 0,
      }),
    ).rejects.toThrow("Not an admin");
  });
});

describe("discovery readiness migrations", () => {
  test("dry-runs, backfills legacy rows pessimistically, and reruns safely", async () => {
    const fixture = await setup();
    const { bandId: missingClipBandId } = await fixture.asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Missing Legacy Clip",
        genres: ["punk"],
        bio: "The referenced upload is gone.",
        area: "Oakland",
      },
    );
    const storageId = await fixture.t.run(async (ctx) =>
      ctx.storage.store(new Blob(["legacy video"])),
    );
    await fixture.t.run(async (ctx) => {
      await ctx.db.patch(fixture.bandId, { hasClip: undefined });
      await ctx.db.insert("bandMedia", {
        bandId: fixture.bandId,
        kind: "video",
        storageId,
        title: "Legacy clip",
        order: 0,
        pinned: true,
      });
      const missingStorageId = await ctx.storage.store(
        new Blob(["deleted legacy video"]),
      );
      await ctx.storage.delete(missingStorageId);
      await ctx.db.patch(missingClipBandId, { hasClip: undefined });
      await ctx.db.insert("bandMedia", {
        bandId: missingClipBandId,
        kind: "video",
        storageId: missingStorageId,
        title: "Missing legacy clip",
        order: 0,
        pinned: true,
      });
    });

    await fixture.t.mutation(internal.migrations.backfillBandHasClip, {
      dryRun: true,
    });
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(fixture.bandId))?.hasClip,
      ),
    ).toBeNull();
    await fixture.t.run(async (ctx) =>
      runToCompletion(
        ctx,
        components.migrations,
        internal.migrations.backfillBandHasClip,
      ),
    );
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(fixture.bandId))?.hasClip,
      ),
    ).toBe(true);
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(missingClipBandId))?.hasClip,
      ),
    ).toBe(false);
    await fixture.t.run(async (ctx) =>
      runToCompletion(
        ctx,
        components.migrations,
        internal.migrations.backfillBandHasClip,
      ),
    );

    const orphanGigId = await fixture.t.run(async (ctx) =>
      ctx.db.insert("gigs", {
        title: "Ambiguous legacy gig",
        venueId: fixture.venueId,
        price: 0,
        startsAt: Date.now() + DAY_MS,
        doorsTime: "8PM",
        flyKey: "paper",
        lineup: [fixture.bandId],
        genres: ["punk"],
        desc: "",
        ticketing: "rsvp",
        cap: "No cap",
        goingCount: 0,
      }),
    );
    const legacyProject = await createPublishableProject(fixture);
    const { gigId: eligibleGigId } = await fixture.asAdmin.mutation(
      api.gigs.publishDraft,
      { projectId: legacyProject._id },
    );
    await fixture.t.run(async (ctx) =>
      ctx.db.patch(eligibleGigId, { discoveryListingReady: undefined }),
    );
    await fixture.t.run(async (ctx) =>
      runToCompletion(
        ctx,
        components.migrations,
        internal.migrations.backfillGigDiscoveryListingReady,
      ),
    );
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(orphanGigId))?.discoveryListingReady,
      ),
    ).toBe(false);
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(eligibleGigId))?.discoveryListingReady,
      ),
    ).toBe(true);
    await fixture.t.run(async (ctx) =>
      runToCompletion(
        ctx,
        components.migrations,
        internal.migrations.backfillGigDiscoveryListingReady,
      ),
    );
    expect(
      await fixture.t.run(
        async (ctx) => (await ctx.db.get(orphanGigId))?.discoveryListingReady,
      ),
    ).toBe(false);
  });
});
