import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

async function setupLifecycle() {
  const t = convexTest(schema);
  const asAdmin = t.withIdentity({
    subject: "gig_admin",
    email: "admin@x.com",
  });
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
    expect(
      (await t.query(api.gigs.feedV2, {})).gigs.map((gig) => gig._id),
    ).toContain(gigId);

    await asAdmin.mutation(api.gigs.unpublish, { projectId: draft._id });
    expect((await t.query(api.gigs.feedV2, {})).gigs).toHaveLength(0);
    expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();

    await asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id });
    await asAdmin.mutation(api.gigs.cancel, { projectId: draft._id });
    expect((await t.query(api.gigs.feedV2, {})).gigs).toHaveLength(0);
    expect((await t.query(api.gigs.resolvePublic, { ref: gigId }))?.lifecycle).toBe(
      "cancelled",
    );

    const duplicate = await asAdmin.mutation(api.gigs.duplicate, {
      projectId: draft._id,
    });
    expect(duplicate.status).toBe("draft");
    expect(duplicate.publicGigId).toBeNull();
    expect(duplicate.title).toBe("Copy of Recoverable Show");

    await asAdmin.mutation(api.gigs.deleteGig, { projectId: draft._id });
    expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();
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

  test("project publishing reuses URL, upload, and venue validation", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    let { revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "riso",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "not-a-url",
      cap: "No cap",
    });
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("External ticketing requires a valid HTTPS URL");

    const deletedFlyerId = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      await ctx.storage.delete(storageId);
      return storageId;
    });
    ({ revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "custom",
      flyStorageId: deletedFlyerId,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "https://example.com/tickets",
      cap: "No cap",
    }));
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("Flyer upload not found");

    ({ revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "riso",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "https://example.com/tickets",
      cap: "No cap",
    }));
    expect(revision).toBeGreaterThan(draft.revision);
    await t.run(async (ctx) => ctx.db.delete(venueId));
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("Venue not found");
  });

  test("an orphaned public gig remains editable and can be republished", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    const saved = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Repairable Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const { gigId: missingGigId } = await asAdmin.mutation(
      api.gigs.publishDraft,
      { projectId: draft._id },
    );
    await t.run(async (ctx) => ctx.db.delete(missingGigId));

    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: saved.revision,
      title: "Repaired Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "Saved after projection loss.",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "text",
      name: "Repair Opener",
      role: "opener",
    });
    const { gigId: replacementGigId } = await asAdmin.mutation(
      api.gigs.publishDraft,
      { projectId: draft._id },
    );

    expect(replacementGigId).not.toBe(missingGigId);
    expect(
      (await t.query(api.gigs.resolvePublic, { ref: replacementGigId }))?.title,
    ).toBe("Repaired Show");
  });

  test("invite expiry is materialized and a live claim stays published", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const { bandId: guestBandId } = await asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Claimed Guest",
        genres: ["noise"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Invitation Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const invited = await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "invited",
      name: "Mystery Guest",
      role: "support",
    });
    const inviteUrl = invited.performers.at(-1)?.inviteUrl;
    const token = inviteUrl?.split("/").at(-1);
    expect(token).toEqual(expect.any(String));
    if (!token) throw new Error("Expected performer invite token");

    await t.run(async (ctx) => {
      const performer = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_invite_token", (q) => q.eq("inviteToken", token))
        .unique();
      await ctx.db.patch(performer!._id, { inviteExpiresAt: Date.now() - 1 });
    });
    expect(
      await t.query(api.gigs.resolvePerformerInvite, { token }),
    ).toMatchObject({ performerName: "Mystery Guest" });
    await expect(
      asAdmin.mutation(api.gigs.claimPerformerInvite, {
        token,
        bandId: guestBandId,
      }),
    ).rejects.toThrow("Invitation is invalid or expired");

    await t.run(async (ctx) => {
      const performer = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_invite_token", (q) => q.eq("inviteToken", token))
        .unique();
      await ctx.db.patch(performer!._id, {
        inviteExpiresAt: Date.now() + 86_400_000,
      });
    });
    const { gigId } = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });
    await asAdmin.mutation(api.gigs.claimPerformerInvite, {
      token,
      bandId: guestBandId,
    });
    const project = await asAdmin.query(api.gigs.getProject, {
      projectId: draft._id,
    });
    expect(project.publishedRevision).not.toBe(project.revision);
    expect(
      (await t.query(api.gigs.resolvePublic, { ref: gigId }))?.discoveryListingReady,
    ).toBe(false);
    expect((await t.query(api.gigs.resolvePublic, { ref: gigId }))?.lineup).toContain(
      guestBandId,
    );
  });
});
