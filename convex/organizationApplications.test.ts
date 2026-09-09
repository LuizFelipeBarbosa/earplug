/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);

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

const hostDraftFields = {
  kind: "host" as const,
  orgName: "",
  orgType: "venueOperator" as const,
  contactName: "",
  businessEmail: "",
};

const hostDetails = {
  hostDisplayName: "Riley",
  hostPhone: "415-555-0100",
  hostArea: "Mission, San Francisco",
  hostAgreementAccepted: true,
};

async function setupActors() {
  const t = convexTest(schema, modules);
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
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("PROMOTERS_ENABLED", undefined);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

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

  test("saveDraft accepts a draft with only an organization name", async () => {
    const { asApplicant } = await setupActors();
    const created = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        orgName: "  Night Light LLC  ",
        orgType: "venueOperator",
        contactName: "",
        businessEmail: "",
      },
    );

    expect(created.revision).toBe(1);
    expect(
      await asApplicant.query(api.organizationApplications.mine, {}),
    ).toMatchObject({
      orgName: "Night Light LLC",
      contactName: "",
      businessEmail: "",
      revision: 1,
    });
  });

  test("saveDraft accepts contact fields without an organization name", async () => {
    const { asApplicant } = await setupActors();

    await expect(
      asApplicant.mutation(api.organizationApplications.saveDraft, {
        orgName: "",
        orgType: "venueOperator",
        contactName: "Riley Owner",
        businessEmail: "riley@night-light.example",
      }),
    ).resolves.toMatchObject({ revision: 1 });
  });

  test("saveDraft rejects a non-blank malformed business email", async () => {
    const { asApplicant } = await setupActors();

    await expect(
      asApplicant.mutation(api.organizationApplications.saveDraft, {
        ...draftFields,
        businessEmail: "not-an-email",
      }),
    ).rejects.toThrow("Enter a valid business email");
  });

  test("submit reports the first missing organization detail", async () => {
    const { asApplicant } = await setupActors();
    const application = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        orgName: "Night Light LLC",
        orgType: "venueOperator",
        contactName: "",
        businessEmail: "",
      },
    );

    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: application.applicationId,
        expectedRevision: application.revision,
      }),
    ).rejects.toThrow("Contact name is required");
  });

  test("partial drafts can be completed and submitted", async () => {
    const { t, asApplicant } = await setupActors();
    const organizationStep = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        orgName: "  Night Light LLC  ",
        orgType: "venueOperator",
        contactName: "",
        businessEmail: "",
      },
    );
    expect(organizationStep.revision).toBe(1);

    const contactStep = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        applicationId: organizationStep.applicationId,
        expectedRevision: organizationStep.revision,
        orgName: "Night Light LLC",
        orgType: "venueOperator",
        contactName: "Riley Owner",
        businessEmail: "riley@night-light.example",
      },
    );
    expect(contactStep.revision).toBe(2);

    const venueStep = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        ...draftFields,
        venue: venueFields,
        applicationId: contactStep.applicationId,
        expectedRevision: contactStep.revision,
      },
    );
    expect(venueStep.revision).toBe(3);

    const storageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: venueStep.applicationId, storageId },
    );
    expect(attached.revision).toBe(4);

    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: venueStep.applicationId,
        expectedRevision: attached.revision,
      }),
    ).resolves.toEqual({ revision: 5 });
    expect(
      await asApplicant.query(api.organizationApplications.get, {
        applicationId: venueStep.applicationId,
      }),
    ).toMatchObject({ status: "submitted", revision: 5 });
  });

  test.each([
    { orgType: "promoter", value: undefined },
    { orgType: "promoter", value: "false" },
    { orgType: "studentOrg", value: undefined },
    { orgType: "studentOrg", value: "false" },
  ] as const)(
    "saveDraft enforces the phase-one venue operator restriction ($orgType, PROMOTERS_ENABLED=$value)",
    async ({ orgType, value }) => {
      vi.stubEnv("PROMOTERS_ENABLED", value);
      const { asApplicant } = await setupActors();
      await expect(
        asApplicant.mutation(api.organizationApplications.saveDraft, {
          ...draftFields,
          orgType,
        }),
      ).rejects.toThrow(
        "Only bars and clubs that control their location can apply right now",
      );
    },
  );

  test.each(["promoter", "studentOrg"] as const)(
    "saveDraft accepts %s with PROMOTERS_ENABLED and drops its venue",
    async (orgType) => {
      vi.stubEnv("PROMOTERS_ENABLED", "true");
      const { t, asApplicant } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...draftFields, orgType, venue: venueFields },
      );

      const application = await t.run((ctx) => ctx.db.get(applicationId));
      expect(application).toMatchObject({
        kind: "organization",
        orgType,
        status: "draft",
        revision: 1,
      });
      expect(application?.venue).toBeUndefined();
    },
  );

  test.each([undefined, "false", "true"])(
    "saveDraft refuses other organizations when PROMOTERS_ENABLED is %s",
    async (value) => {
      vi.stubEnv("PROMOTERS_ENABLED", value);
      const { asApplicant } = await setupActors();
      await expect(
        asApplicant.mutation(api.organizationApplications.saveDraft, {
          ...draftFields,
          orgType: "other",
        }),
      ).rejects.toThrow(
        "Only bars and clubs that control their location can apply right now",
      );
    },
  );

  test.each(["promoter", "studentOrg"] as const)(
    "submit requires a verification document for %s without a venue",
    async (orgType) => {
      vi.stubEnv("PROMOTERS_ENABLED", "true");
      const { t, asApplicant } = await setupActors();
      const { applicationId, revision } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...draftFields, orgType },
      );
      await expect(
        asApplicant.mutation(api.organizationApplications.submit, {
          applicationId,
          expectedRevision: revision,
        }),
      ).rejects.toThrow(
        "Attach at least one verification document before submitting",
      );

      const storageId = await t.run((ctx) =>
        ctx.storage.store(
          new Blob(["verification"], { type: "application/pdf" }),
        ),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        { applicationId, storageId },
      );
      await expect(
        asApplicant.mutation(api.organizationApplications.submit, {
          applicationId,
          expectedRevision: attached.revision,
        }),
      ).resolves.toEqual({ revision: attached.revision + 1 });
      expect(
        await asApplicant.query(api.organizationApplications.get, {
          applicationId,
        }),
      ).toMatchObject({
        status: "submitted",
        orgType,
        venue: null,
        revision: attached.revision + 1,
      });
    },
  );

  test.each(["promoter", "studentOrg"] as const)(
    "submit refuses a saved %s draft after PROMOTERS_ENABLED is turned off",
    async (orgType) => {
      vi.stubEnv("PROMOTERS_ENABLED", "true");
      const { t, asApplicant } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...draftFields, orgType },
      );
      const storageId = await t.run((ctx) =>
        ctx.storage.store(
          new Blob(["verification"], { type: "application/pdf" }),
        ),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        { applicationId, storageId },
      );

      vi.stubEnv("PROMOTERS_ENABLED", "false");
      await expect(
        asApplicant.mutation(api.organizationApplications.submit, {
          applicationId,
          expectedRevision: attached.revision,
        }),
      ).rejects.toThrow(
        "Only bars and clubs that control their location can apply right now",
      );
      expect(await t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
        status: "draft",
        revision: attached.revision,
      });
    },
  );

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

  test.each([
    { organizerAgreementAccepted: true },
    { organizerAgreementAccepted: false },
    {},
  ])("submit records optional organizer agreement acceptance: %j", async (args) => {
    const { t, asApplicant } = await setupActors();
    const { applicationId } = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, venue: venueFields },
    );
    const storageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId, storageId },
    );

    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId,
        expectedRevision: attached.revision,
        ...args,
      }),
    ).resolves.toEqual({ revision: attached.revision + 1 });

    const payload = await asApplicant.query(api.organizationApplications.get, {
      applicationId,
    });
    expect(payload).toMatchObject({
      kind: "organization",
      status: "submitted",
      organizerAgreementAcceptedAt:
        args.organizerAgreementAccepted === true ? expect.any(Number) : null,
    });
    if (args.organizerAgreementAccepted === true) {
      expect(payload?.organizerAgreementAcceptedAt).toBe(payload?.updatedAt);
    }
    const stored = await t.run((ctx) => ctx.db.get(applicationId));
    expect(stored?.organizerAgreementAcceptedAt ?? null).toBe(
      payload?.organizerAgreementAcceptedAt,
    );
  });

  test.each([{ organizerAgreementAccepted: false }, {}])(
    "submit preserves existing organizer agreement acceptance: %j",
    async (args) => {
      const { t, asApplicant } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...draftFields, venue: venueFields },
      );
      const storageId = await t.run((ctx) =>
        ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        { applicationId, storageId },
      );
      await t.run((ctx) =>
        ctx.db.patch(applicationId, {
          status: "needs_info",
          organizerAgreementAcceptedAt: 1000,
        }),
      );

      await asApplicant.mutation(api.organizationApplications.submit, {
        applicationId,
        expectedRevision: attached.revision,
        ...args,
      });

      expect(
        await asApplicant.query(api.organizationApplications.get, {
          applicationId,
        }),
      ).toMatchObject({
        status: "submitted",
        organizerAgreementAcceptedAt: 1000,
      });
    },
  );

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
      await asApplicant.mutation(api.organizationApplications.attachDocument, {
        applicationId: application.applicationId,
        storageId,
      });
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
          q.eq("organizationId", organizationId).eq("userId", applicantUserId),
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

  test("approval creates a promoter organization and owner without a venue", async () => {
    vi.stubEnv("PROMOTERS_ENABLED", "true");
    const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
    const { applicationId } = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...draftFields, orgType: "promoter", venue: venueFields },
    );
    const storageId = await t.run((ctx) =>
      ctx.storage.store(
        new Blob(["verification"], { type: "application/pdf" }),
      ),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId, storageId },
    );
    await asApplicant.mutation(api.organizationApplications.submit, {
      applicationId,
      expectedRevision: attached.revision,
    });
    const decision = await asAdmin.mutation(
      api.organizationApplications.decide,
      { applicationId, decision: "approved" },
    );
    expect(decision).toMatchObject({ status: "approved", venueId: null });
    const organizationId = decision.organizationId;
    if (organizationId === null) {
      throw new Error("Approved promoter missing organization");
    }

    const state = await t.run(async (ctx) => ({
      organization: await ctx.db.get(organizationId),
      privateDetails: await ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
      membership: await ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q.eq("organizationId", organizationId).eq("userId", applicantUserId),
        )
        .unique(),
      venues: await ctx.db.query("venues").take(1),
      venuePrivateDetails: await ctx.db.query("venuePrivateDetails").take(1),
    }));
    expect(state.organization).toMatchObject({
      name: draftFields.orgName,
      orgType: "promoter",
      status: "verified",
      ownerUserId: applicantUserId,
      applicationId,
    });
    expect(state.privateDetails).toMatchObject({
      businessEmail: draftFields.businessEmail,
      contactName: draftFields.contactName,
      verificationDocStorageIds: [storageId],
    });
    expect(state.membership).toMatchObject({
      organizationId,
      userId: applicantUserId,
      role: "owner",
    });
    expect(state.venues).toEqual([]);
    expect(state.venuePrivateDetails).toEqual([]);
    expect(
      await asApplicant.query(api.organizationApplications.get, {
        applicationId,
      }),
    ).toMatchObject({
      status: "approved",
      resultingOrganizationId: organizationId,
      resultingVenueId: null,
      venue: null,
    });
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

  test.each([
    { privateDetails: false, nearbyCount: 0 },
    { privateDetails: true, nearbyCount: 0 },
    { privateDetails: false, nearbyCount: 1 },
    { privateDetails: true, nearbyCount: 1 },
    { privateDetails: false, nearbyCount: 2 },
    { privateDetails: true, nearbyCount: 2 },
  ])(
    "approval checks all address matches using exact coordinates ($privateDetails, $nearbyCount nearby)",
    async ({ privateDetails, nearbyCount }) => {
      const { t, asApplicant, asAdmin } = await setupActors();
      const venue = { ...venueFields, addr: "123 Exact Street" };
      const venueIds = await t.run(async (ctx) => {
        const ids: Id<"venues">[] = [];
        for (let index = 0; index <= nearbyCount; index++) {
          const point =
            index === 0
              ? { lat: 37.3355, lng: -121.889 }
              : { lat: venue.lat, lng: venue.lng };
          const id = await ctx.db.insert("venues", {
            name: `Existing venue ${index}`,
            area: "Bay Area",
            addr: venue.addr,
            normalizedAddr: "123 exact street",
            distSF: "1.0 mi",
            distOak: "8.0 mi",
            // A public pin may be approximate; only private coordinates should
            // control matching once private details exist.
            ...(privateDetails ? { lat: 37.76, lng: -122.42 } : point),
          });
          if (privateDetails) {
            await ctx.db.insert("venuePrivateDetails", {
              venueId: id,
              addr: venue.addr,
              normalizedAddr: "123 exact street",
              ...point,
              updatedAt: Date.now(),
            });
          }
          ids.push(id);
        }
        return ids;
      });
      const application = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        {
          ...draftFields,
          venue,
        },
      );
      const storageId = await t.run((ctx) =>
        ctx.storage.store(new Blob(["license"], { type: "application/pdf" })),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        {
          applicationId: application.applicationId,
          storageId,
        },
      );
      await asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: application.applicationId,
        expectedRevision: attached.revision,
      });
      const approval = asAdmin.mutation(api.organizationApplications.decide, {
        applicationId: application.applicationId,
        decision: "approved",
      });
      if (nearbyCount > 1) {
        await expect(approval).rejects.toThrow("Multiple venues match");
        expect(
          await t.run((ctx) => ctx.db.query("organizations").take(1)),
        ).toEqual([]);
      } else {
        const decision = await approval;
        expect(decision.venueId).not.toBe(venueIds[0]);
        if (nearbyCount === 1) expect(decision.venueId).toBe(venueIds[1]);
        expect(
          await t.run((ctx) => ctx.db.query("venues").take(10)),
        ).toHaveLength(2);
      }
      expect(await t.run((ctx) => ctx.db.get(venueIds[0]))).not.toHaveProperty(
        "managedByOrganizationId",
      );
    },
  );

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

describe("host applications", () => {
  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  test.each([
    {
      name: "prefers a trimmed business email",
      businessEmail: "  business@example.com  ",
      applicantEmail: "applicant@example.com",
      expectedTo: "business@example.com",
    },
    {
      name: "falls back to a trimmed applicant email for a blank business email",
      businessEmail: " \t ",
      applicantEmail: "  applicant@example.com  ",
      expectedTo: "applicant@example.com",
    },
    {
      name: "skips email when both addresses are empty",
      businessEmail: "",
      applicantEmail: "",
      expectedTo: null,
    },
    {
      name: "skips email when both addresses are whitespace",
      businessEmail: " \t ",
      applicantEmail: " \t ",
      expectedTo: null,
    },
    {
      name: "skips email when the applicant is missing and business email is empty",
      businessEmail: "",
      applicantEmail: null,
      expectedTo: null,
    },
  ])(
    "a status transition $name",
    async ({ businessEmail, applicantEmail, expectedTo }) => {
      vi.useFakeTimers();
      const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...hostDraftFields, ...hostDetails },
      );
      await t.run(async (ctx) => {
        // Preserve raw stored whitespace to exercise recipient normalization.
        await ctx.db.patch(applicationId, { status: "submitted", businessEmail });
        if (applicantEmail === null) {
          await ctx.db.delete(applicantUserId);
        } else {
          await ctx.db.patch(applicantUserId, { email: applicantEmail });
        }
      });

      await expect(
        asAdmin.mutation(api.organizationApplications.decide, {
          applicationId,
          decision: "needs_info",
          note: "Please update the verification document.",
        }),
      ).resolves.toMatchObject({ status: "needs_info" });

      const jobs = await t.run((ctx) =>
        ctx.db.system.query("_scheduled_functions").take(100),
      );
      if (expectedTo === null) {
        expect(jobs).toEqual([]);
      } else {
        expect(jobs).toMatchObject([
          {
            name: "emails:send",
            args: [{ kind: "applicationNeedsInfo", to: expectedTo }],
          },
        ]);
      }
    },
  );

  test.each(["venueOperator", "privateHost"] as const)(
    "saveDraft accepts an empty host draft with orgType %s and no venue",
    async (orgType) => {
      const { asApplicant } = await setupActors();
      const created = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        {
          ...hostDraftFields,
          orgType,
          hostDisplayName: "  ",
          hostPhone: "  ",
          hostArea: "  ",
        },
      );
      expect(created.revision).toBe(1);
      expect(
        await asApplicant.query(api.organizationApplications.mine, {}),
      ).toMatchObject({
        kind: "host",
        hostDisplayName: null,
        hostPhone: null,
        hostArea: null,
        hostAgreementAcceptedAt: null,
        venue: null,
      });
    },
  );

  test.each([
    ["hostDisplayName", 60],
    ["hostPhone", 40],
    ["hostArea", 120],
  ] as const)("saveDraft trims and limits %s", async (field, limit) => {
    const { asApplicant } = await setupActors();
    await expect(
      asApplicant.mutation(api.organizationApplications.saveDraft, {
        ...hostDraftFields,
        [field]: `  ${"a".repeat(limit + 1)}  `,
      }),
    ).rejects.toThrow("too long");
    const created = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...hostDraftFields, [field]: `  ${"a".repeat(limit)}  ` },
    );
    expect(
      await asApplicant.query(api.organizationApplications.get, {
        applicationId: created.applicationId,
      }),
    ).toMatchObject({ [field]: "a".repeat(limit) });
    await asApplicant.mutation(api.organizationApplications.saveDraft, {
      ...hostDraftFields,
      applicationId: created.applicationId,
      expectedRevision: created.revision,
      [field]: "  ",
    });
    expect(
      await asApplicant.query(api.organizationApplications.mine, {}),
    ).toMatchObject({ [field]: null });
  });

  test("saveDraft preserves, renews, and clears the hosting agreement", async () => {
    const { asApplicant } = await setupActors();
    const now = vi.spyOn(Date, "now").mockReturnValue(1000);
    let draft = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...hostDraftFields, ...hostDetails },
    );
    for (const [accepted, timestamp] of [
      [undefined, 1000],
      [true, 2000],
      [false, null],
      [undefined, null],
    ] as const) {
      now.mockReturnValue(2000);
      draft = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        {
          ...hostDraftFields,
          ...hostDetails,
          applicationId: draft.applicationId,
          expectedRevision: draft.revision,
          hostAgreementAccepted: accepted,
        },
      );
      expect(
        await asApplicant.query(api.organizationApplications.mine, {}),
      ).toMatchObject({ hostAgreementAcceptedAt: timestamp });
    }
  });

  test.each([
    { hostDisplayName: "Riley" },
    { hostPhone: "415-555-0100" },
    { hostArea: "Mission" },
    { hostAgreementAccepted: true },
  ])(
    "saveDraft allows changing kind before submission even when host data exists: %j",
    async (fields) => {
      const { t, asApplicant } = await setupActors();
      const created = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...hostDraftFields, ...fields },
      );
      if (fields.hostAgreementAccepted) {
        await t.run((ctx) =>
          ctx.db.patch(created.applicationId, {
            hostAgreementAcceptedAt: 0,
          }),
        );
      }
      let revision = created.revision;
      for (const kind of [undefined, "organization"] as const) {
        const updated = await asApplicant.mutation(
          api.organizationApplications.saveDraft,
          {
            ...draftFields,
            applicationId: created.applicationId,
            expectedRevision: revision,
            kind,
          },
        );
        expect(updated.revision).toBe(revision + 1);
        revision = updated.revision;
      }
      expect(
        await asApplicant.query(api.organizationApplications.mine, {}),
      ).toMatchObject({ kind: "organization", revision });
    },
  );

  test.each(["host", "organization", undefined] as const)(
    "saveDraft freezes submitted kind %s in needs_info while allowing other edits",
    async (kind) => {
      vi.useFakeTimers();
      vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
      const { t, asApplicant, asAdmin } = await setupActors();
      const fields = {
        ...draftFields,
        ...hostDetails,
        venue: venueFields,
        kind,
      };
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        fields,
      );
      if (kind === undefined) {
        await t.run((ctx) => ctx.db.patch(applicationId, { kind: undefined }));
      }
      const storageId = await t.run((ctx) =>
        ctx.storage.store(
          new Blob(["verification"], { type: "application/pdf" }),
        ),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        { applicationId, storageId },
      );
      const submitted = await asApplicant.mutation(
        api.organizationApplications.submit,
        {
          applicationId,
          expectedRevision: attached.revision,
        },
      );
      await asAdmin.mutation(api.organizationApplications.decide, {
        applicationId,
        decision: "needs_info",
      });
      const before = await t.run((ctx) => ctx.db.get(applicationId));
      const changedKinds =
        kind === "host"
          ? (["organization", undefined] as const)
          : (["host"] as const);
      for (const changedKind of changedKinds) {
        await expect(
          asApplicant.mutation(api.organizationApplications.saveDraft, {
            ...fields,
            applicationId,
            expectedRevision: submitted.revision,
            kind: changedKind,
          }),
        ).rejects.toThrow("Application kind cannot change after submission");
        expect(await t.run((ctx) => ctx.db.get(applicationId))).toEqual(before);
      }
      await expect(
        asApplicant.mutation(api.organizationApplications.saveDraft, {
          ...fields,
          applicationId,
          expectedRevision: submitted.revision,
          contactName: "Updated contact",
          hostArea: "Oakland",
        }),
      ).resolves.toEqual({ applicationId, revision: submitted.revision + 1 });
      expect(await t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
        kind: kind ?? "organization",
        status: "needs_info",
        contactName: "Updated contact",
        hostArea: "Oakland",
      });
    },
  );

  test("an empty host draft may become an organization draft", async () => {
    const { asApplicant } = await setupActors();
    const created = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      hostDraftFields,
    );
    await asApplicant.mutation(api.organizationApplications.saveDraft, {
      ...draftFields,
      applicationId: created.applicationId,
      expectedRevision: created.revision,
    });
    expect(
      await asApplicant.query(api.organizationApplications.mine, {}),
    ).toMatchObject({ kind: "organization", revision: 2 });
  });

  test.each([false, true])(
    "mine and get default organization payload kind (legacy: %s)",
    async (legacy) => {
      const { t, asApplicant } = await setupActors();
      const created = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        draftFields,
      );
      if (legacy) {
        await t.run((ctx) =>
          ctx.db.patch(created.applicationId, { kind: undefined }),
        );
      }
      for (const payload of [
        await asApplicant.query(api.organizationApplications.mine, {}),
        await asApplicant.query(api.organizationApplications.get, {
          applicationId: created.applicationId,
        }),
      ]) {
        expect(payload).toMatchObject({
          kind: "organization",
          hostDisplayName: null,
          hostPhone: null,
          hostArea: null,
          hostAgreementAcceptedAt: null,
        });
      }
    },
  );

  test.each([undefined, "false"])(
    "submit rejects hosts when PRIVATE_BOOKINGS_ENABLED is %s",
    async (value) => {
      vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", value);
      const { asApplicant } = await setupActors();
      const created = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        hostDraftFields,
      );
      await expect(
        asApplicant.mutation(api.organizationApplications.submit, {
          applicationId: created.applicationId,
          expectedRevision: created.revision,
        }),
      ).rejects.toThrow("Hosting is not available yet");
    },
  );

  test("submit requires host details, agreement, and a document", async () => {
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    const { t, asApplicant } = await setupActors();
    let draft = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      hostDraftFields,
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: draft.applicationId,
        expectedRevision: draft.revision,
      }),
    ).rejects.toThrow("Host name is required");

    for (const [fields, error] of [
      [{ ...hostDetails, hostDisplayName: " R " }, "Host name is required"],
      [{ ...hostDetails, hostPhone: "  " }, "Phone number is required"],
      [{ ...hostDetails, hostArea: "  " }, "Area is required"],
      [
        { ...hostDetails, hostAgreementAccepted: false },
        "Accept the hosting agreement before submitting",
      ],
      [
        hostDetails,
        "Attach at least one verification document before submitting",
      ],
    ] as const) {
      draft = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        {
          ...hostDraftFields,
          ...fields,
          applicationId: draft.applicationId,
          expectedRevision: draft.revision,
        },
      );
      await expect(
        asApplicant.mutation(api.organizationApplications.submit, {
          applicationId: draft.applicationId,
          expectedRevision: draft.revision,
        }),
      ).rejects.toThrow(error);
    }

    await expect(
      asApplicant.mutation(
        api.organizationApplications.generateDocumentUploadUrl,
        {},
      ),
    ).resolves.toEqual(expect.any(String));
    const storageId = await t.run((ctx) =>
      ctx.storage.store(
        new Blob(["host verification"], { type: "application/pdf" }),
      ),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: draft.applicationId, storageId },
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: draft.applicationId,
        expectedRevision: attached.revision,
      }),
    ).resolves.toEqual({ revision: attached.revision + 1 });
    expect(
      await asApplicant.query(api.organizationApplications.mine, {}),
    ).toMatchObject({ status: "submitted", kind: "host", venue: null });
  });

  test.each([
    { organizerAgreementAccepted: true },
    { organizerAgreementAccepted: false },
    {},
  ])("host submit ignores organizer agreement acceptance: %j", async (args) => {
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    const { t, asApplicant } = await setupActors();
    const { applicationId } = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...hostDraftFields, ...hostDetails, hostAgreementAccepted: false },
    );
    const storageId = await t.run((ctx) =>
      ctx.storage.store(
        new Blob(["host verification"], { type: "application/pdf" }),
      ),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId, storageId },
    );
    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId,
        expectedRevision: attached.revision,
        ...args,
      }),
    ).rejects.toThrow("Accept the hosting agreement before submitting");

    const accepted = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      {
        ...hostDraftFields,
        ...hostDetails,
        applicationId,
        expectedRevision: attached.revision,
      },
    );
    const beforeSubmit = await asApplicant.query(
      api.organizationApplications.get,
      { applicationId },
    );
    expect(beforeSubmit?.hostAgreementAcceptedAt).toEqual(expect.any(Number));

    await expect(
      asApplicant.mutation(api.organizationApplications.submit, {
        applicationId,
        expectedRevision: accepted.revision,
        ...args,
      }),
    ).resolves.toEqual({ revision: accepted.revision + 1 });
    expect(
      await asApplicant.query(api.organizationApplications.get, {
        applicationId,
      }),
    ).toMatchObject({
      kind: "host",
      status: "submitted",
      hostAgreementAcceptedAt: beforeSubmit?.hostAgreementAcceptedAt,
      organizerAgreementAcceptedAt: null,
    });
  });

  test("approval creates a privateHost organization and owner without a venue", async () => {
    vi.useFakeTimers();
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    const { t, asApplicant, asAdmin, applicantUserId } =
      await setupActors();
    const created = await asApplicant.mutation(
      api.organizationApplications.saveDraft,
      { ...hostDraftFields, ...hostDetails },
    );
    const storageId = await t.run((ctx) =>
      ctx.storage.store(
        new Blob(["host verification"], { type: "application/pdf" }),
      ),
    );
    const attached = await asApplicant.mutation(
      api.organizationApplications.attachDocument,
      { applicationId: created.applicationId, storageId },
    );
    await asApplicant.mutation(api.organizationApplications.submit, {
      applicationId: created.applicationId,
      expectedRevision: attached.revision,
    });
    await asAdmin.mutation(api.organizationApplications.decide, {
      applicationId: created.applicationId,
      decision: "under_review",
    });
    const decision = await asAdmin.mutation(
      api.organizationApplications.decide,
      {
        applicationId: created.applicationId,
        decision: "approved",
        note: "Host verified",
      },
    );
    expect(decision).toMatchObject({ status: "approved", venueId: null });
    const organizationId = decision.organizationId;
    if (organizationId === null)
      throw new Error("Approved host missing organization");

    const state = await t.run(async (ctx) => ({
      organization: await ctx.db.get(organizationId),
      applicant: await ctx.db.get(applicantUserId),
      privateDetails: await ctx.db
        .query("organizationPrivateDetails")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
      membership: await ctx.db
        .query("organizationMembers")
        .withIndex("by_organizationId_and_userId", (q) =>
          q
            .eq("organizationId", organizationId)
            .eq("userId", applicantUserId),
        )
        .unique(),
      venues: await ctx.db.query("venues").take(1),
      venuePrivateDetails: await ctx.db
        .query("venuePrivateDetails")
        .take(1),
    }));
    expect(state.organization).toMatchObject({
      name: hostDetails.hostDisplayName,
      slug: expect.stringMatching(/^host-[0-9a-f]{12}$/),
      orgType: "privateHost",
      status: "verified",
      ownerUserId: applicantUserId,
      applicationId: created.applicationId,
      verifiedAt: expect.any(Number),
    });
    expect(state.organization).not.toHaveProperty("website");
    expect(state.organization).not.toHaveProperty("description");
    expect(state.privateDetails).toMatchObject({
      businessEmail: state.applicant?.email,
      contactName: hostDetails.hostDisplayName,
      phone: hostDetails.hostPhone,
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: [storageId],
    });
    expect(state.privateDetails?.businessEmail).not.toBe(
      hostDraftFields.businessEmail,
    );
    expect(state.membership).toMatchObject({
      userId: applicantUserId,
      role: "owner",
    });
    expect(state.venues).toEqual([]);
    expect(state.venuePrivateDetails).toEqual([]);
    const jobs = await t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(100),
    );
    expect(jobs.filter((job) => job.name === "emails:send")).toMatchObject([
      {
        args: [
          { kind: "applicationReceived", to: "riley@night-light.example" },
        ],
      },
      {
        args: [
          { kind: "applicationApproved", to: "riley@night-light.example" },
        ],
      },
    ]);
    expect(
      await asAdmin.query(api.organizationApplications.get, {
        applicationId: created.applicationId,
      }),
    ).toMatchObject({
      status: "approved",
      resultingOrganizationId: organizationId,
      resultingVenueId: null,
      reviewNote: "Host verified",
    });
  });

  test.each([
    { applicantEmail: "", businessEmail: "" },
    { applicantEmail: " \t ", businessEmail: " \n " },
    { applicantEmail: "", businessEmail: " \t " },
    { applicantEmail: " \t ", businessEmail: "" },
  ])(
    "approval refuses a host without an email: %j",
    async ({ applicantEmail, businessEmail }) => {
      const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...hostDraftFields, ...hostDetails },
      );
      await t.run(async (ctx) => {
        await ctx.db.patch(applicationId, {
          status: "submitted",
          businessEmail,
        });
        await ctx.db.patch(applicantUserId, { email: applicantEmail });
      });
      const before = await t.run((ctx) => ctx.db.get(applicationId));
      await expect(
        asAdmin.mutation(api.organizationApplications.decide, {
          applicationId,
          decision: "approved",
        }),
      ).rejects.toThrow("Host application has no email");
      const state = await t.run(async (ctx) => ({
        application: await ctx.db.get(applicationId),
        organizations: await ctx.db.query("organizations").collect(),
        privateDetails: await ctx.db
          .query("organizationPrivateDetails")
          .collect(),
        members: await ctx.db.query("organizationMembers").collect(),
      }));
      expect(state).toEqual({
        application: before,
        organizations: [],
        privateDetails: [],
        members: [],
      });
      expect(state.application?.status).toBe("submitted");
    },
  );

  test.each([
    {
      applicantEmail: "  applicant@example.com  ",
      expected: "applicant@example.com",
    },
    { applicantEmail: "", expected: "business@example.com" },
    { applicantEmail: " \t ", expected: "business@example.com" },
  ])(
    "approval saves the trimmed effective host email: %j",
    async ({ applicantEmail, expected }) => {
      vi.useFakeTimers();
      const { t, asApplicant, asAdmin, applicantUserId } = await setupActors();
      const { applicationId } = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        { ...hostDraftFields, ...hostDetails },
      );
      await t.run(async (ctx) => {
        await ctx.db.patch(applicationId, {
          status: "submitted",
          businessEmail: "  business@example.com  ",
        });
        await ctx.db.patch(applicantUserId, { email: applicantEmail });
      });
      const { organizationId } = await asAdmin.mutation(
        api.organizationApplications.decide,
        {
          applicationId,
          decision: "approved",
        },
      );
      expect(
        await t.run((ctx) =>
          ctx.db.query("organizationPrivateDetails").collect(),
        ),
      ).toMatchObject([{ organizationId, businessEmail: expected }]);
    },
  );

  test("listForReview filters host applications while preserving the combined queue", async () => {
    const { t, asAdmin, applicantUserId } = await setupActors();
    const ids = await t.run(async (ctx) => {
      const ids = [];
      const kinds = [undefined, "host", "organization"] as const;
      for (const [index, kind] of kinds.entries()) {
        ids.push(
          await ctx.db.insert("organizationApplications", {
            applicantUserId,
            ...draftFields,
            kind,
            verificationDocStorageIds: [],
            status: "submitted",
            revision: 1,
            createdAt: index,
            updatedAt: index,
          }),
        );
      }
      return ids;
    });
    const paginationOpts = { numItems: 10, cursor: null };
    const combined = await asAdmin.query(
      api.organizationApplications.listForReview,
      {
        paginationOpts,
      },
    );
    expect(combined.page.map(({ application }) => application._id)).toEqual(
      ids,
    );
    const hosts = await asAdmin.query(
      api.organizationApplications.listForReview,
      {
        kind: "host",
        paginationOpts,
      },
    );
    expect(hosts.page.map(({ application }) => application._id)).toEqual([
      ids[1],
    ]);
    expect(hosts.page[0].application.kind).toBe("host");
    const organizations = await asAdmin.query(
      api.organizationApplications.listForReview,
      {
        kind: "organization",
        paginationOpts,
      },
    );
    expect(
      organizations.page.map(({ application }) => application._id),
    ).toEqual([ids[2]]);
  });
});
