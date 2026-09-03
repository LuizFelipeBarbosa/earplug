import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import schema from "./schema";

const draftFields = {
  orgName: "Night Light LLC",
  orgType: "venueOperator" as const,
  website: "https://night-light.example",
  contactName: "Riley Owner",
  businessEmail: "riley@night-light.example",
  phone: "415-555-0100",
};

const venueFields = {
  name: "Night Light",
  addr: "123 Exact Street, San Francisco, CA",
  lat: 37.76123,
  lng: -122.41234,
  area: "Mission, San Francisco",
  capacity: 240,
  venueType: "club" as const,
};

async function setupActors() {
  const t = convexTest(schema);
  const asApplicant = t.withIdentity({
    subject: "organization_applicant",
    email: "riley@night-light.example",
    name: "Riley Owner",
  });
  const asAdmin = t.withIdentity({
    subject: "organization_reviewer",
    email: "reviewer@earplug.app",
    name: "Platform Reviewer",
  });
  const { userId: applicantUserId } = await asApplicant.mutation(
    api.users.ensureUser,
    {},
  );
  const { userId: adminUserId } = await asAdmin.mutation(
    api.users.ensureUser,
    {},
  );
  await t.run((ctx) =>
    ctx.db.insert("platformAdmins", {
      userId: adminUserId,
      grantedAt: Date.now(),
    }),
  );
  return { t, asApplicant, asAdmin, applicantUserId };
}

describe("organization applications", () => {
  test("saveDraft creates and updates with optimistic concurrency", async () => {
    const { asApplicant } = await setupActors();
    const created = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      draftFields,
    );
    expect(created.revision).toBe(1);

    const updated = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        ...draftFields,
        applicationId: created.applicationId,
        expectedRevision: created.revision,
        orgName: "  Night Light Group  ",
      },
    );
    expect(updated).toEqual({
      applicationId: created.applicationId,
      revision: 2,
    });
    expect(
      await asApplicant.query(api.organizationApplications.mine, {}),
    ).toMatchObject({ orgName: "Night Light Group", revision: 2 });

    await expect(
      asApplicant.mutation(api.organizationApplications.saveDraft, {
        ...draftFields,
        applicationId: created.applicationId,
        expectedRevision: 1,
      }),
    ).rejects.toThrow("Application changed elsewhere");
  });

  test("saveDraft enforces the phase-one venue operator restriction", async () => {
    const { asApplicant } = await setupActors();
    await expect(
      asApplicant.mutation(api.organizationApplications.saveDraft, {
        ...draftFields,
        orgType: "promoter",
      }),
    ).rejects.toThrow(
      "Only bars and clubs that control their location can apply right now",
    );
  });

  test("submit requires venue details and a verification document", async () => {
    const { t, asApplicant } = await setupActors();
    const withoutVenue = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      draftFields,
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: withoutVenue.applicationId,
        expectedRevision: withoutVenue.revision,
      }),
    ).rejects.toThrow("Add your venue's details before submitting");

    const withVenue = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, venue: venueFields },
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: withVenue.applicationId,
        expectedRevision: withVenue.revision,
      }),
    ).rejects.toThrow(
      "Attach at least one verification document before submitting",
    );

    const storageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: withVenue.applicationId, storageId },
    );
    const submitted = await asApplicant.mutation(
      api.organizationApplications.submit,
      {
        applicationId: withVenue.applicationId,
        expectedRevision: attached.revision,
      },
    );
    expect(submitted.revision).toBe(3);
    expect(
      await asApplicant.query(api.organizationApplications.get, {
        applicationId: withVenue.applicationId,
      }),
    ).toMatchObject({ status: "submitted", revision: 3 });
  });

  test("attachDocument enforces size, type, and five-document limits", async () => {
    const { t, asApplicant } = await setupActors();
    const application = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, venue: venueFields },
    );
    const oversizedId = await t.run((ctx) =>
      ctx.storage.store(
        new Blob([new Uint8Array(15 * 1024 * 1024 + 1)], {
          type: "application/pdf",
        }),
      ),
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.attachDocument, {
        applicationId: application.applicationId,
        storageId: oversizedId,
      }),
    ).rejects.toThrow("That file is too big — 15 MB max.");

    const textId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["not a document"])),
    );
    await t.run(async (ctx) => {
      // convex-test omits Blob contentType, so inject the system metadata that
      // the deployed storage table supplies after an upload.
      const db = ctx.db as unknown as {
        patch(
          id: Id<"_storage">,
          value: { contentType: string },
        ): Promise<void>;
      };
      await db.patch(textId, { contentType: "text/plain" });
    });
    await expect(
      asApplicant.mutation(api.organizationApplications.attachDocument, {
        applicationId: application.applicationId,
        storageId: textId,
      }),
    ).rejects.toThrow("Documents must be a PDF or photo");

    const ids = [];
    for (let index = 0; index < 6; index++) {
      ids.push(
        await t.run((ctx) =>
          ctx.storage.store(
            new Blob([`document-${index}`], { type: "application/pdf" }),
          ),
        ),
      );
    }
    for (const storageId of ids.slice(0, 5)) {
      await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        { applicationId: application.applicationId, storageId },
      );
    }
    await expect(
      asApplicant.mutation(api.organizationApplications.attachDocument, {
        applicationId: application.applicationId,
        storageId: ids[5],
      }),
    ).rejects.toThrow("You can attach up to 5 documents");
  });

  test("admin approval atomically creates the organization and private venue", async () => {
    const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
    const application = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, venue: venueFields },
    );
    const documentId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: application.applicationId, storageId: documentId },
    );
    await asApplicant.mutation(api.organizationApplications.submit, {
      applicationId: application.applicationId,
      expectedRevision: attached.revision,
    });

    await expect(
      asApplicant.mutation(api.organizationApplications.decide, {
        applicationId: application.applicationId,
        decision: "approved",
      }),
    ).rejects.toThrow("Not an EarPlug admin");

    const decision = await asAdmin.mutation(
      api.organizationApplications.decide,
      {
        applicationId: application.applicationId,
        decision: "approved",
        note: "Verified documents.",
      },
    );
    expect(decision.status).toBe("approved");
    expect(decision.organizationId).not.toBeNull();
    expect(decision.venueId).not.toBeNull();
    const organizationId = decision.organizationId as Id<"organizations">;
    const venueId = decision.venueId as Id<"venues">;

    const state = await t.run(async (ctx) => {
      const organization = await ctx.db.get(organizationId);
      const privateDetails = await ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique();
      const membership = await ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q
            .eq("organizationId", organizationId)
            .eq("userId", applicantUserId),
        )
        .unique();
      const venue = await ctx.db.get(venueId);
      const venuePrivate = await ctx.db
        .query("venuePrivateDetails")
        .withIndex("by_venueId", (q) => q.eq("venueId", venueId))
        .unique();
      return { organization, privateDetails, membership, venue, venuePrivate };
    });
    expect(state.organization).toMatchObject({
      name: draftFields.orgName,
      status: "verified",
      ownerUserId: applicantUserId,
    });
    expect(state.privateDetails).toMatchObject({
      businessEmail: draftFields.businessEmail,
      contactName: draftFields.contactName,
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
    });
    expect(state.membership).toMatchObject({
      userId: applicantUserId,
      role: "owner",
    });
    expect(state.venue).toMatchObject({
      status: "verified",
      addressDisclosure: "onTicket",
      managedByOrganizationId: decision.organizationId,
    });
    expect(state.venue?.slug).toEqual(expect.any(String));
    expect(state.venue?.slug).not.toBe("");
    expect(state.venue?.addr).not.toBe(venueFields.addr);
    expect(state.venue?.lat).not.toBe(venueFields.lat);
    expect(state.venue?.lng).not.toBe(venueFields.lng);
    expect(state.venuePrivate).toMatchObject({
      addr: venueFields.addr,
      lat: venueFields.lat,
      lng: venueFields.lng,
    });
    expect(await asApplicant.query(api.organizations.mine, {})).toEqual([
      expect.objectContaining({
        organization: expect.objectContaining({
          _id: decision.organizationId,
          status: "verified",
        }),
        role: "owner",
      }),
    ]);
    await expect(
      asAdmin.mutation(api.organizationApplications.decide, {
        applicationId: application.applicationId,
        decision: "rejected",
      }),
    ).rejects.toThrow("Invalid decision for this application");
  });

  test("approval adopts a normalized-address legacy venue", async () => {
    const { t, asApplicant, asAdmin } = await setupActors();
    const legacyVenueId = await t.run((ctx) =>
      ctx.db.insert("venues", {
        name: "Legacy Night Light",
        area: "Mission",
        addr: "123 EXACT Street, San Francisco, CA",
        normalizedName: "legacy night light",
        normalizedAddr: "123 exact street, san francisco, ca",
        distSF: "1.0 mi",
        distOak: "8.0 mi",
        lat: 37.761,
        lng: -122.412,
      }),
    );
    const application = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, venue: venueFields },
    );
    const storageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: application.applicationId, storageId },
    );
    await asApplicant.mutation(api.organizationApplications.submit, {
      applicationId: application.applicationId,
      expectedRevision: attached.revision,
    });
    const decision = await asAdmin.mutation(
      api.organizationApplications.decide,
      { applicationId: application.applicationId, decision: "approved" },
    );
    expect(decision.venueId).toBe(legacyVenueId);
    const venues = await t.run((ctx) => ctx.db.query("venues").take(10));
    expect(venues).toHaveLength(1);
    expect(venues[0]).toMatchObject({
      _id: legacyVenueId,
      managedByOrganizationId: decision.organizationId,
      status: "verified",
    });
    expect(venues[0].addressDisclosure).toBe("public");
    expect(
      await t.query(api.venues.resolvePublic, { ref: legacyVenueId }),
    ).toMatchObject({
      verified: true,
      addr: "123 EXACT Street, San Francisco, CA",
      exactAddr: "123 EXACT Street, San Francisco, CA",
    });
  });

  test("listForReview is admin-only and paginates oldest first", async () => {
    const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
    await t.run(async (ctx) => {
      for (let createdAt = 1; createdAt <= 3; createdAt++) {
        await ctx.db.insert("organizationApplications", {
          applicantUserId,
          ...draftFields,
          verificationDocStorageIds: [],
          status: "submitted",
          revision: 1,
          createdAt,
          updatedAt: createdAt,
        });
      }
    });
    await expect(
      asApplicant.query(api.organizationApplications.listForReview, {
        paginationOpts: { numItems: 2, cursor: null },
      }),
    ).rejects.toThrow("Not an EarPlug admin");
    const firstPage = await asAdmin.query(
      api.organizationApplications.listForReview,
      { paginationOpts: { numItems: 2, cursor: null } },
    );
    expect(firstPage.page).toHaveLength(2);
    expect(firstPage.page[0].application.createdAt).toBe(1);
    expect(firstPage.page[1].application.createdAt).toBe(2);
    expect(firstPage.isDone).toBe(false);
  });

  test("email action skips cleanly when sending is disabled", async () => {
    const t = convexTest(schema);
    await expect(
      t.action(internal.emails.send, {
        kind: "applicationReceived",
        to: "venue@example.com",
        subject: "Application received",
        text: "Thanks for applying.",
      }),
    ).resolves.toBeNull();
  });
});
