import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

async function setupLifecycle() {
  const t = convexTest(schema);
  const asAdmin = t.withIdentity({ subject: "gig_admin", email: "admin@x.com" });
  await asAdmin.mutation(api.users.ensureUser, {});
  const { bandId } = await asAdmin.mutation(api.bands.createBand, {
    name: "Draft Mechanics",
    genres: ["punk"],
    bio: "",
    area: "Bay Area",
    inviteHandles: [],
  });
  const venueId = await t.run(async (ctx) =>
    ctx.db.insert("venues", {
      name: "Lifecycle Hall",
      area: "Oakland",
      addr: "1 Draft Way",
      distSF: "7 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.2,
    }),
  );
  return { t, asAdmin, bandId, venueId };
}

describe("gig project lifecycle", () => {
  test("saves, previews through its private payload, publishes, unpublishes, cancels, and deletes", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    expect(draft.status).toBe("draft");
    expect(draft.performers.map((performer) => performer.name)).toEqual([
      "Draft Mechanics",
    ]);

    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Recoverable Show",
      doorsAt,
      startsAt,
      venueId,
      price: 10,
      flyKey: "paper",
      flyStorageId: null,
      overlay: true,
      desc: "Saved before publishing.",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const saved = await asAdmin.query(api.gigs.getProject, {
      projectId: draft._id,
    });
    expect(saved.title).toBe("Recoverable Show");

    const added = await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "text",
      name: "Unlisted Opener",
      role: "opener",
    });
    expect(added.performers.map((performer) => performer.name)).toEqual([
      "Draft Mechanics",
      "Unlisted Opener",
    ]);

    const { gigId } = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });
    expect((await t.query(api.gigs.feed, {})).gigs.map((gig) => gig._id)).toContain(
      gigId,
    );

    await asAdmin.mutation(api.gigs.unpublish, { projectId: draft._id });
    expect((await t.query(api.gigs.feed, {})).gigs).toHaveLength(0);
    expect(await t.query(api.gigs.getPublic, { gigId })).toBeNull();

    await asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id });
    await asAdmin.mutation(api.gigs.cancel, { projectId: draft._id });
    expect((await t.query(api.gigs.feed, {})).gigs).toHaveLength(0);
    expect((await t.query(api.gigs.getPublic, { gigId }))?.lifecycle).toBe(
      "cancelled",
    );

    const duplicate = await asAdmin.mutation(api.gigs.duplicate, {
      projectId: draft._id,
    });
    expect(duplicate.status).toBe("draft");
    expect(duplicate.publicGigId).toBeNull();
    expect(duplicate.title).toBe("Copy of Recoverable Show");

    await asAdmin.mutation(api.gigs.deleteGig, { projectId: draft._id });
    expect(await t.query(api.gigs.getPublic, { gigId })).toBeNull();
    expect(
      (await asAdmin.query(api.gigs.manageForBand, { bandId })).map(
        (project) => project._id,
      ),
    ).not.toContain(draft._id);
  });

  test("management is restricted to band admins", async () => {
    const { t, bandId } = await setupLifecycle();
    const stranger = t.withIdentity({ subject: "stranger", email: "s@x.com" });
    await stranger.mutation(api.users.ensureUser, {});

    await expect(
      stranger.query(api.gigs.manageForBand, { bandId }),
    ).rejects.toThrow();
  });
});
