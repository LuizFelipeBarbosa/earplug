/// <reference types="vite/client" />
import { FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { toVenuePayload } from "./lib/helpers";
import {
  opportunityPayloadValidator,
  toOpportunityPayload,
} from "./lib/opportunityPayload";
import { APPLICATION_ACTIVE_STATUSES } from "./lib/opportunityStatus";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse("2026-09-04T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

async function setupOrganization() {
  const t = convexTest(schema, modules);
  const asOwner = t.withIdentity({ subject: "opportunity_owner" });
  const asManager = t.withIdentity({ subject: "opportunity_manager" });
  const asFinance = t.withIdentity({ subject: "opportunity_finance" });
  const asDoor = t.withIdentity({ subject: "opportunity_door" });
  const asStranger = t.withIdentity({ subject: "opportunity_stranger" });
  const asOtherOwner = t.withIdentity({ subject: "opportunity_other" });
  const ids = await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (const actor of [
      "owner",
      "manager",
      "finance",
      "door",
      "stranger",
      "other",
    ]) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `opportunity_${actor}`,
          name: actor,
          email: `${actor}@opportunity.test`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    const [ownerId, managerId, financeId, doorId, , otherOwnerId] = userIds;
    const organizationId = await ctx.db.insert("organizations", {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: 1,
      updatedAt: 1,
    });
    const otherOrganizationId = await ctx.db.insert("organizations", {
      name: "Other Collective",
      slug: "other-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: otherOwnerId,
      createdAt: 1,
      updatedAt: 1,
    });
    for (const [role, userId] of [
      ["owner", ownerId],
      ["manager", managerId],
      ["finance", financeId],
      ["door", doorId],
    ] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: 1,
      });
    }
    await ctx.db.insert("organizationMembers", {
      organizationId: otherOrganizationId,
      userId: otherOwnerId,
      role: "owner",
      createdAt: 1,
    });
    const venueFields = {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      managedByOrganizationId: organizationId,
      status: "verified" as const,
    };
    const venueId = await ctx.db.insert("venues", {
      ...venueFields,
      approxLabel: "Uptown, Oakland",
      venueType: "hall",
    });
    const otherVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      managedByOrganizationId: otherOrganizationId,
    });
    const unverifiedVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      status: "pending",
    });
    const alternateVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      area: "Berkeley",
    });
    const bandFields = {
      name: "Static Bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
      slug: "static-bloom",
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const archivedBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Archived Band",
      slug: "archived-band",
      archivedAt: 1,
    });
    return {
      ownerId,
      managerId,
      organizationId,
      otherOrganizationId,
      venueId,
      otherVenueId,
      unverifiedVenueId,
      alternateVenueId,
      bandId,
      archivedBandId,
    };
  });
  const createArgs = {
    organizationId: ids.organizationId,
    venueId: ids.venueId,
    title: "  Friday at the Hall  ",
    startsAt: NOW + 14 * DAY_MS,
  };
  async function createDraft(
    overrides: Partial<
      FunctionArgs<typeof api.talentOpportunities.create>
    > = {},
  ) {
    return await asOwner.mutation(api.talentOpportunities.create, {
      ...createArgs,
      ...overrides,
    });
  }
  async function readOpportunity(opportunityId: Id<"talentOpportunities">) {
    return await t.run(async (ctx) => ({
      opportunity: await ctx.db.get(opportunityId),
      slots: await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .take(20),
      invites: await ctx.db
        .query("opportunityInvites")
        .withIndex("by_opportunityId_and_bandId", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .take(105),
    }));
  }
  async function seedApplications(
    opportunityId: Id<"talentOpportunities">,
    statuses: Doc<"artistApplications">["status"][] = ["submitted"],
  ) {
    return await t.run(async (ctx) => {
      const slot = await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .first();
      if (!slot) throw new Error("Fixture needs a slot");
      const applicationIds: Id<"artistApplications">[] = [];
      for (const status of statuses) {
        applicationIds.push(
          await ctx.db.insert("artistApplications", {
            opportunityId,
            slotId: slot._id,
            bandId: ids.bandId,
            submittedBy: ids.ownerId,
            message: "We are available",
            status,
            createdAt: 1,
            updatedAt: 1,
          }),
        );
      }
      await ctx.db.patch(opportunityId, {
        applicationCount: statuses.filter((status) =>
          APPLICATION_ACTIVE_STATUSES.includes(status),
        ).length,
      });
      return applicationIds;
    });
  }
  return {
    t,
    asOwner,
    asManager,
    asFinance,
    asDoor,
    asStranger,
    asOtherOwner,
    ...ids,
    createArgs,
    createDraft,
    readOpportunity,
    seedApplications,
  };
}

describe("talent opportunity drafts", () => {
  test("defaults include a free headliner slot and venue discovery fields", async () => {
    const { createDraft, readOpportunity, ownerId, venueId } =
      await setupOrganization();
    const { opportunityId, slug } = await createDraft();
    const { opportunity, slots } = await readOpportunity(opportunityId);
    expect(slug).toBe("friday-at-the-hall");
    expect(opportunity).toMatchObject({
      title: "Friday at the Hall",
      desc: "",
      genres: [],
      mode: "publicEvent",
      venueId,
      area: "Uptown, Oakland",
      venueType: "hall",
      currency: "usd",
      flyKey: "xerox",
      ticketing: "rsvp",
      visibility: "public",
      ageRequirement: "allAges",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      status: "draft",
      revision: 1,
      applicationCount: 0,
      createdBy: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(slots).toHaveLength(1);
    expect(slots[0]).toMatchObject({
      order: 0,
      role: "headliner",
      guaranteeMinor: 0,
      required: true,
      status: "open",
    });
    expect(slots[0]).not.toHaveProperty("currency");
    expect(slots[0]).not.toHaveProperty("bandId");
  });

  test("empty slots and currency use defaults; absent venue metadata falls back", async () => {
    const { createDraft, readOpportunity, alternateVenueId } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      venueId: alternateVenueId,
      slots: [],
      currency: "   ",
    });
    const { opportunity, slots } = await readOpportunity(opportunityId);
    expect(opportunity).toMatchObject({ area: "Berkeley", currency: "usd" });
    expect(opportunity).not.toHaveProperty("venueType");
    expect(slots).toHaveLength(1);
  });

  test("rejects another organization's venue, an unverified venue, and private bookings", async () => {
    const { createDraft, otherVenueId, unverifiedVenueId } =
      await setupOrganization();
    for (const venueId of [otherVenueId, unverifiedVenueId]) {
      await expect(createDraft({ venueId })).rejects.toThrow(
        "Choose one of your verified venues",
      );
    }
    await expect(createDraft({ mode: "privateBooking" })).rejects.toThrow(
      "Private bookings are not available yet",
    );
  });

  test.each([
    { title: "", error: "Title must be" },
    { title: "x".repeat(121), error: "Title must be" },
    { desc: "x".repeat(2001), error: "Description is too long" },
    { genres: Array(6).fill("rock"), error: "Choose up to 5 genres" },
    { genres: ["x".repeat(51)], error: "Choose up to 5 genres" },
    { startsAt: Number.NaN, error: "Invalid startsAt" },
    {
      applicationsCloseAt: NOW + 14 * DAY_MS,
      error: "Applications must close before",
    },
    {
      ticketing: "external" as const,
      externalUrl: "http://tickets.test",
      error: "valid HTTPS URL",
    },
    { flyKey: "custom", error: "Custom flyer requires flyStorageId" },
  ])("validates draft fields: $error", async ({ error, ...fields }) => {
    const { createDraft } = await setupOrganization();
    await expect(createDraft(fields)).rejects.toThrow(error);
  });

  test("rejects too many slots, invalid guarantees, and invalid set lengths", async () => {
    const { createDraft } = await setupOrganization();
    await expect(
      createDraft({
        slots: Array.from({ length: 9 }, () => ({
          role: "support",
          guaranteeMinor: 0,
        })),
      }),
    ).rejects.toThrow("Choose between 1 and 8 slots");
    for (const guaranteeMinor of [-1, 0.5, Number.POSITIVE_INFINITY]) {
      await expect(
        createDraft({ slots: [{ role: "headliner", guaranteeMinor }] }),
      ).rejects.toThrow("Slot guarantee");
    }
    for (const setLengthMin of [0, 601, 1.5]) {
      await expect(
        createDraft({
          slots: [{ role: "headliner", guaranteeMinor: 0, setLengthMin }],
        }),
      ).rejects.toThrow("Set length");
    }
  });

  test("issues collision-safe, non-reserved slugs and keeps them stable on update", async () => {
    const { createDraft, readOpportunity, asOwner } = await setupOrganization();
    expect((await createDraft({ title: "join" })).slug).toBe("join-2");
    expect((await createDraft({ title: "!!!" })).slug).toBe("opportunity");
    expect((await createDraft({ title: "???" })).slug).toBe("opportunity-2");
    const first = await createDraft();
    expect((await createDraft()).slug).toBe(`${first.slug}-2`);
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId: first.opportunityId,
      expectedRevision: 1,
      title: "New name",
    });
    expect((await readOpportunity(first.opportunityId)).opportunity?.slug).toBe(
      first.slug,
    );
  });

  test("update enforces OCC and replaces slots and venue metadata atomically", async () => {
    const {
      createDraft,
      asOwner,
      readOpportunity,
      alternateVenueId,
      otherVenueId,
    } = await setupOrganization();
    const { opportunityId } = await createDraft();
    const oldSlot = (await readOpportunity(opportunityId)).slots[0];
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 0,
        title: "Stale",
      }),
    ).rejects.toThrow("Opportunity changed elsewhere");
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        venueId: otherVenueId,
      }),
    ).rejects.toThrow("Choose one of your verified venues");
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        startsAt: NOW + 7 * DAY_MS,
      }),
    ).rejects.toThrow("Applications must close before the event starts");
    vi.setSystemTime(NOW + 100);
    expect(
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        venueId: alternateVenueId,
        title: "  Revised  ",
        desc: "  Live music  ",
        currency: " cad ",
        genres: [" Indie ", ""],
        slots: [
          {
            role: "support",
            guaranteeMinor: 5000,
            setLengthMin: 45,
            required: false,
          },
        ],
      }),
    ).toEqual({ revision: 2 });
    const { opportunity, slots } = await readOpportunity(opportunityId);
    expect(opportunity).toMatchObject({
      title: "Revised",
      desc: "Live music",
      genres: ["Indie"],
      area: "Berkeley",
      venueId: alternateVenueId,
      currency: "cad",
      revision: 2,
      updatedAt: NOW + 100,
    });
    expect(opportunity).not.toHaveProperty("venueType");
    expect(slots).toHaveLength(1);
    expect(slots[0]._id).not.toBe(oldSlot._id);
    expect(slots[0]).toMatchObject({
      order: 0,
      role: "support",
      guaranteeMinor: 5000,
      setLengthMin: 45,
      required: false,
    });
  });

  test("update validates merged external ticketing and flyer uploads", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const flyStorageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["photo"], { type: "image/png" })),
    );
    const { opportunityId } = await createDraft({
      ticketing: "external",
      externalUrl: "https://tickets.test/event",
      flyKey: "custom",
      flyStorageId,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        externalUrl: "",
      }),
    ).rejects.toThrow("External ticketing requires a valid HTTPS URL");
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      desc: "Updated",
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      flyStorageId,
      ticketing: "external",
      desc: "Updated",
    });
    await t.run((ctx) => ctx.storage.delete(flyStorageId));
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        title: "Another edit",
      }),
    ).rejects.toThrow("Flyer upload not found");
  });

  test("update clears equipment with null and preserves omitted fields", async () => {
    const { createDraft, asOwner, readOpportunity } = await setupOrganization();
    const { opportunityId } = await createDraft({
      equipment: "Backline",
      requirements: "Bring cables",
    });
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      equipment: null,
    });
    const { opportunity } = await readOpportunity(opportunityId);
    expect(opportunity).not.toHaveProperty("equipment");
    expect(opportunity).toMatchObject({ requirements: "Bring cables" });

    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 2,
      title: "New title",
    });
    const updated = (await readOpportunity(opportunityId)).opportunity;
    expect(updated).not.toHaveProperty("equipment");
    expect(updated).toMatchObject({
      title: "New title",
      requirements: "Bring cables",
    });
  });

  test("update clears optional event metadata and can set it again", async () => {
    const { createDraft, asOwner, readOpportunity } = await setupOrganization();
    const optionalFields = {
      eventType: "Showcase",
      expectedAttendance: 150,
      doorsAt: NOW + 14 * DAY_MS - 3600000,
      endsAt: NOW + 14 * DAY_MS + 3600000,
      requirements: "Bring cables",
      externalUrl: "https://tickets.test/event",
    };
    const { opportunityId } = await createDraft(optionalFields);
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      eventType: null,
      expectedAttendance: null,
      doorsAt: null,
      endsAt: null,
      requirements: null,
      externalUrl: null,
    });
    const { opportunity } = await readOpportunity(opportunityId);
    for (const field of Object.keys(optionalFields)) {
      expect(opportunity).not.toHaveProperty(field);
    }
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 2,
      ...optionalFields,
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject(
      optionalFields,
    );
  });

  test("clearing a custom flyer removes its storage ID and restores xerox", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const flyStorageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["photo"], { type: "image/png" })),
    );
    const { opportunityId } = await createDraft({
      flyKey: "custom",
      flyStorageId,
    });
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      flyStorageId: null,
    });
    const { opportunity } = await readOpportunity(opportunityId);
    expect(opportunity).not.toHaveProperty("flyStorageId");
    expect(opportunity).toMatchObject({ flyKey: "xerox" });
  });

  test("custom flyers reject a non-photo upload", async () => {
    const { t, createDraft } = await setupOrganization();
    const flyStorageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["text"], { type: "text/plain" })),
    );
    await t.run(async (ctx) => {
      // convex-test omits Blob contentType; seed the metadata used in production.
      const db = ctx.db as unknown as {
        patch(
          id: Id<"_storage">,
          value: { contentType: string },
        ): Promise<void>;
      };
      await db.patch(flyStorageId, { contentType: "text/plain" });
    });
    await expect(
      createDraft({ flyKey: "custom", flyStorageId }),
    ).rejects.toThrow("can't be posted as a photo");
  });
});

describe("talent opportunity lifecycle", () => {
  test("open schedules expiry while preserving shortlisted and offered applications", async () => {
    const { t, createDraft, asOwner, readOpportunity, seedApplications } =
      await setupOrganization();
    const applicationsCloseAt = NOW + DAY_MS;
    const { opportunityId } = await createDraft({ applicationsCloseAt });
    const [applicationId, shortlistedId, offeredId] = await seedApplications(
      opportunityId,
      ["submitted", "shortlisted", "offered"],
    );
    expect(
      await asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      }),
    ).toEqual({ revision: 2, applicationsCloseAt });
    const scheduled = await t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(10),
    );
    expect(scheduled).toHaveLength(1);
    expect(scheduled[0]).toMatchObject({
      name: "talentOpportunities:expireApplications",
      args: [{ opportunityId, expectedRevision: 2 }],
      scheduledTime: applicationsCloseAt,
    });
    vi.advanceTimersByTime(DAY_MS + 1);
    await t.finishInProgressScheduledFunctions();
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "applications_closed",
      revision: 3,
      applicationCount: 2,
    });
    expect(await t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
      status: "expired",
    });
    const survivors = await t.run((ctx) =>
      Promise.all([shortlistedId, offeredId].map((id) => ctx.db.get(id))),
    );
    expect(survivors).toMatchObject([
      { status: "shortlisted", updatedAt: 1 },
      { status: "offered", updatedAt: 1 },
    ]);
    for (const application of survivors) {
      expect(application).not.toHaveProperty("decidedAt");
      expect(application).not.toHaveProperty("decidedBy");
    }
  });

  test("open rejects stale revisions, missing slots, past starts, and invalid deadlines", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await expect(
      asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 0,
      }),
    ).rejects.toThrow("Opportunity changed elsewhere");
    for (const applicationsCloseAt of [
      NOW,
      NOW + 14 * DAY_MS,
      NOW + 15 * DAY_MS,
    ]) {
      await t.run((ctx) =>
        ctx.db.patch(opportunityId, { applicationsCloseAt }),
      );
      await expect(
        asOwner.mutation(api.talentOpportunities.open, {
          opportunityId,
          expectedRevision: 1,
        }),
      ).rejects.toThrow("Set an applications deadline before the event starts");
    }
    await t.run((ctx) => ctx.db.patch(opportunityId, { startsAt: NOW }));
    await expect(
      asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      }),
    ).rejects.toThrow("The event has already started");
    const { slots } = await readOpportunity(opportunityId);
    await t.run((ctx) => ctx.db.delete(slots[0]._id));
    await expect(
      asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      }),
    ).rejects.toThrow("Add at least one slot before opening");
  });

  test("open opportunities lock slots and venue changes while allowing other edits", async () => {
    const { createDraft, asOwner, venueId, alternateVenueId } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        slots: [],
      }),
    ).rejects.toThrow("Slots are locked once applications are open");
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        venueId: alternateVenueId,
      }),
    ).rejects.toThrow(
      "Venue can only be changed while the opportunity is still a draft",
    );
    expect(
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        venueId,
        desc: "Updated while open",
      }),
    ).toEqual({ revision: 3 });
  });

  test("updating an open opportunity rejects a past start without changing it", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const before = await readOpportunity(opportunityId);
    const scheduledBefore = await t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(10),
    );
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        startsAt: NOW - DAY_MS,
      }),
    ).rejects.toThrow("The event has already started");
    expect(await readOpportunity(opportunityId)).toEqual(before);
    expect(
      await t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(10)),
    ).toEqual(scheduledBefore);
  });

  test("updating an open opportunity rejects deadlines outside the future application window", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const before = await readOpportunity(opportunityId);
    const scheduledBefore = await t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(10),
    );
    for (const applicationsCloseAt of [
      NOW,
      NOW + 14 * DAY_MS,
      NOW + 15 * DAY_MS,
    ]) {
      await expect(
        asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 2,
          applicationsCloseAt,
        }),
      ).rejects.toThrow("Set an applications deadline before the event starts");
      expect(await readOpportunity(opportunityId)).toEqual(before);
      expect(
        await t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(10)),
      ).toEqual(scheduledBefore);
    }
  });

  test("a title-only edit makes the old expiry revision a no-op", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const applicationsCloseAt = NOW + DAY_MS;
    const { opportunityId } = await createDraft({ applicationsCloseAt });
    const { revision: expectedRevision } = await asOwner.mutation(
      api.talentOpportunities.open,
      { opportunityId, expectedRevision: 1 },
    );
    expect(expectedRevision).toBe(2);
    const { revision } = await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision,
      title: "Updated title",
    });
    expect(revision).toBe(3);
    const scheduled = await t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(10),
    );
    expect(scheduled).toHaveLength(2);
    expect(scheduled).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          name: "talentOpportunities:expireApplications",
          args: [{ opportunityId, expectedRevision }],
          scheduledTime: applicationsCloseAt,
        }),
        expect.objectContaining({
          name: "talentOpportunities:expireApplications",
          args: [{ opportunityId, expectedRevision: revision }],
          scheduledTime: applicationsCloseAt,
        }),
      ]),
    );
    await t.mutation(internal.talentOpportunities.expireApplications, {
      opportunityId,
      expectedRevision,
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "open",
      revision: 3,
    });
    await t.mutation(internal.talentOpportunities.expireApplications, {
      opportunityId,
      expectedRevision: revision,
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "applications_closed",
      revision: 4,
    });
  });

  test.each([false, true])(
    "an edit renews scheduled expiry (deadline changed: %s)",
    async (changeDeadline) => {
      const { t, createDraft, asOwner, readOpportunity } =
        await setupOrganization();
      const { opportunityId } = await createDraft({
        applicationsCloseAt: NOW + DAY_MS,
      });
      await asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      });
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        title: "Updated",
        ...(changeDeadline ? { applicationsCloseAt: NOW + 2 * DAY_MS } : {}),
      });
      vi.advanceTimersByTime(DAY_MS + 1);
      await t.finishInProgressScheduledFunctions();
      expect((await readOpportunity(opportunityId)).opportunity?.status).toBe(
        changeDeadline ? "open" : "applications_closed",
      );
      if (changeDeadline) {
        vi.advanceTimersByTime(DAY_MS);
        await t.finishInProgressScheduledFunctions();
        expect(
          (await readOpportunity(opportunityId)).opportunity,
        ).toMatchObject({ status: "applications_closed", revision: 4 });
      }
    },
  );

  test("closing expires submitted and under-review applications and preserves all other statuses", async () => {
    const { t, createDraft, asOwner, readOpportunity, seedApplications } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const statuses = [
      ...APPLICATION_ACTIVE_STATUSES,
      "booked",
      "withdrawn",
      "declined",
      "expired",
    ] as const;
    const ids = await seedApplications(opportunityId, [...statuses]);
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId,
    });
    const applications = await t.run((ctx) =>
      Promise.all(ids.map((id) => ctx.db.get(id))),
    );
    for (const application of applications.slice(0, 2)) {
      expect(application).toMatchObject({
        status: "expired",
        decidedAt: NOW,
        updatedAt: NOW,
      });
      expect(application).not.toHaveProperty("decidedBy");
    }
    for (const [index, application] of applications.entries()) {
      if (index < 2) continue;
      expect(application).toMatchObject({
        status: statuses[index],
        updatedAt: 1,
      });
      expect(application).not.toHaveProperty("decidedAt");
      expect(application).not.toHaveProperty("decidedBy");
    }
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "applications_closed",
      revision: 3,
      applicationCount: 2,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 3,
        desc: "Closed",
      }),
    ).rejects.toThrow("Opportunity can no longer be edited");
  });

  test("closing drains more than 200 submitted applications and counts surviving shortlist entries", async () => {
    const { t, createDraft, asOwner, readOpportunity, seedApplications } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const ids = await seedApplications(opportunityId, [
      ...Array.from({ length: 250 }, () => "submitted" as const),
      "shortlisted",
      "shortlisted",
    ]);
    expect(
      (await readOpportunity(opportunityId)).opportunity?.applicationCount,
    ).toBe(252);
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId,
    });
    const applications = await t.run((ctx) =>
      Promise.all(ids.map((id) => ctx.db.get(id))),
    );
    for (const application of applications.slice(0, 250)) {
      expect(application).toMatchObject({ status: "expired" });
    }
    for (const application of applications.slice(250)) {
      expect(application).toMatchObject({
        status: "shortlisted",
        updatedAt: 1,
      });
      expect(application).not.toHaveProperty("decidedAt");
      expect(application).not.toHaveProperty("decidedBy");
    }
    expect(
      (await readOpportunity(opportunityId)).opportunity?.applicationCount,
    ).toBe(2);
  });

  test("reopen checks the deadline and invalidates the prior scheduled run", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      applicationsCloseAt: NOW + DAY_MS,
    });
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId,
    });
    for (const applicationsCloseAt of [NOW, NOW + 14 * DAY_MS]) {
      await expect(
        asOwner.mutation(api.talentOpportunities.reopen, {
          opportunityId,
          applicationsCloseAt,
        }),
      ).rejects.toThrow("Set an applications deadline before the event starts");
    }
    await asOwner.mutation(api.talentOpportunities.reopen, {
      opportunityId,
      applicationsCloseAt: NOW + 2 * DAY_MS,
    });
    vi.advanceTimersByTime(DAY_MS + 1);
    await t.finishInProgressScheduledFunctions();
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "open",
      revision: 4,
    });
    vi.advanceTimersByTime(DAY_MS);
    await t.finishInProgressScheduledFunctions();
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "applications_closed",
      revision: 5,
    });
  });

  test("cancel declines active applications with the caller and cancels only open slots", async () => {
    const {
      t,
      createDraft,
      asOwner,
      readOpportunity,
      seedApplications,
      ownerId,
      bandId,
    } = await setupOrganization();
    const { opportunityId } = await createDraft({
      slots: [
        { role: "headliner", guaranteeMinor: 10000 },
        { role: "support", guaranteeMinor: 5000 },
      ],
    });
    const { slots } = await readOpportunity(opportunityId);
    await t.run((ctx) =>
      ctx.db.patch(slots[1]._id, { status: "booked", bandId }),
    );
    const ids = await seedApplications(opportunityId, [
      ...APPLICATION_ACTIVE_STATUSES,
      "booked",
    ]);
    await asOwner.mutation(api.talentOpportunities.cancel, {
      opportunityId,
      reason: "Venue unavailable",
    });
    const applications = await t.run((ctx) =>
      Promise.all(ids.map((id) => ctx.db.get(id))),
    );
    for (const application of applications.slice(0, 4)) {
      expect(application).toMatchObject({
        status: "declined",
        decidedBy: ownerId,
        decidedAt: NOW,
        updatedAt: NOW,
      });
    }
    expect(applications[4]).toMatchObject({ status: "booked", updatedAt: 1 });
    const result = await readOpportunity(opportunityId);
    expect(result.opportunity).toMatchObject({
      status: "cancelled",
      revision: 2,
      applicationCount: 0,
    });
    expect(result.slots.map((slot) => slot.status)).toEqual([
      "cancelled",
      "booked",
    ]);
    await expect(
      asOwner.mutation(api.talentOpportunities.cancel, { opportunityId }),
    ).rejects.toThrow("Opportunity cannot go");
  });

  test("scheduled expiry is a no-op for stale revisions, non-open rows, and deleted rows", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    const args = { opportunityId, expectedRevision: 1 };
    await t.mutation(internal.talentOpportunities.expireApplications, args);
    expect((await readOpportunity(opportunityId)).opportunity?.revision).toBe(
      1,
    );
    await asOwner.mutation(api.talentOpportunities.open, args);
    await t.mutation(internal.talentOpportunities.expireApplications, args);
    expect((await readOpportunity(opportunityId)).opportunity?.status).toBe(
      "open",
    );
    await asOwner.mutation(api.talentOpportunities.cancel, { opportunityId });
    await t.mutation(internal.talentOpportunities.expireApplications, {
      opportunityId,
      expectedRevision: 3,
    });
    expect((await readOpportunity(opportunityId)).opportunity?.status).toBe(
      "cancelled",
    );
    const draft = await createDraft();
    await asOwner.mutation(api.talentOpportunities.deleteDraft, {
      opportunityId: draft.opportunityId,
    });
    await expect(
      t.mutation(internal.talentOpportunities.expireApplications, {
        opportunityId: draft.opportunityId,
        expectedRevision: 1,
      }),
    ).resolves.toBeNull();
  });

  test("deleteDraft removes its children and refuses an open opportunity", async () => {
    const { createDraft, asOwner, bandId, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    await asOwner.mutation(api.talentOpportunities.inviteBand, {
      opportunityId,
      bandId,
    });
    await asOwner.mutation(api.talentOpportunities.deleteDraft, {
      opportunityId,
    });
    expect(await readOpportunity(opportunityId)).toEqual({
      opportunity: null,
      slots: [],
      invites: [],
    });
    const draft = await createDraft();
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId: draft.opportunityId,
      expectedRevision: 1,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.deleteDraft, {
        opportunityId: draft.opportunityId,
      }),
    ).rejects.toThrow("Only a draft can be deleted");
  });

  test("duplicate copies editable fields but resets lifecycle, slots, and invites", async () => {
    const {
      t,
      createDraft,
      asOwner,
      asManager,
      managerId,
      bandId,
      readOpportunity,
      seedApplications,
    } = await setupOrganization();
    const flyStorageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["photo"], { type: "image/png" })),
    );
    const { opportunityId } = await createDraft({
      desc: "Show description",
      eventType: "Showcase",
      expectedAttendance: 150,
      genres: ["Indie"],
      doorsAt: NOW + 14 * DAY_MS - 3600000,
      endsAt: NOW + 14 * DAY_MS + 3600000,
      ageRequirement: "21Plus",
      equipment: "Backline",
      requirements: "Bring cables",
      flyKey: "custom",
      flyStorageId,
      visibility: "inviteOnly",
      ticketing: "external",
      currency: "cad",
      externalUrl: "https://tickets.test",
      slots: [
        { role: "headliner", guaranteeMinor: 20000, setLengthMin: 60 },
        { role: "opener", guaranteeMinor: 5000, required: false },
      ],
    });
    await asOwner.mutation(api.talentOpportunities.inviteBand, {
      opportunityId,
      bandId,
    });
    await seedApplications(opportunityId);
    const source = await readOpportunity(opportunityId);
    await t.run(async (ctx) => {
      await ctx.db.patch(source.slots[0]._id, { status: "booked", bandId });
      await ctx.db.patch(source.slots[1]._id, { status: "cancelled" });
      await ctx.db.patch(opportunityId, { status: "completed", revision: 10 });
    });
    vi.setSystemTime(NOW + 100);
    const copy = await asManager.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    const result = await readOpportunity(copy.opportunityId);
    const {
      _id,
      _creationTime,
      title,
      slug,
      status,
      revision,
      applicationCount,
      createdBy,
      createdAt,
      updatedAt,
      ...editable
    } = source.opportunity!;
    expect(result.opportunity).toMatchObject({
      ...editable,
      title: "Friday at the Hall (copy)",
      slug: copy.slug,
      status: "draft",
      revision: 1,
      applicationCount: 0,
      createdBy: managerId,
      createdAt: NOW + 100,
      updatedAt: NOW + 100,
    });
    expect(copy.opportunityId).not.toBe(opportunityId);
    expect(copy.slug).not.toBe(source.opportunity?.slug);
    expect(result.invites).toEqual([]);
    expect(result.slots).toHaveLength(2);
    for (const [index, slot] of result.slots.entries()) {
      expect(slot).toMatchObject({
        order: source.slots[index].order,
        role: source.slots[index].role,
        guaranteeMinor: source.slots[index].guaranteeMinor,
        required: source.slots[index].required,
        status: "open",
      });
      expect(slot.setLengthMin).toBe(source.slots[index].setLengthMin);
      expect(slot).not.toHaveProperty("bandId");
      expect(slot).not.toHaveProperty("currency");
    }
  });
});

describe("talent opportunity invitations and authorization", () => {
  test("invites are idempotent, reject archived bands, and can be removed after closing", async () => {
    const { createDraft, asOwner, bandId, archivedBandId, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft();
    expect(
      await asOwner.mutation(api.talentOpportunities.inviteBand, {
        opportunityId,
        bandId,
      }),
    ).toEqual({ invited: true });
    expect(
      await asOwner.mutation(api.talentOpportunities.inviteBand, {
        opportunityId,
        bandId,
      }),
    ).toEqual({ invited: false });
    expect((await readOpportunity(opportunityId)).invites).toHaveLength(1);
    await expect(
      asOwner.mutation(api.talentOpportunities.inviteBand, {
        opportunityId,
        bandId: archivedBandId,
      }),
    ).rejects.toThrow("Band not found");
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.inviteBand, {
        opportunityId,
        bandId,
      }),
    ).rejects.toThrow("Invites are closed");
    await asOwner.mutation(api.talentOpportunities.uninviteBand, {
      opportunityId,
      bandId,
    });
    await asOwner.mutation(api.talentOpportunities.uninviteBand, {
      opportunityId,
      bandId,
    });
    expect((await readOpportunity(opportunityId)).invites).toEqual([]);
  });

  test("a manager can create and edit opportunities", async () => {
    const { asManager, createArgs, managerId, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await asManager.mutation(
      api.talentOpportunities.create,
      createArgs,
    );
    await asManager.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      desc: "Manager edit",
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      createdBy: managerId,
      desc: "Manager edit",
      revision: 2,
    });
  });

  test.each([
    "asFinance",
    "asDoor",
    "asStranger",
    "asOtherOwner",
    "pending",
    "suspendedAdmin",
  ] as const)(
    "every public mutation rejects an unauthorized organizer: %s",
    async (actor) => {
      const fixture = await setupOrganization();
      const { t, createDraft, createArgs, organizationId, ownerId, bandId } =
        fixture;
      const { opportunityId } = await createDraft();
      if (actor === "pending" || actor === "suspendedAdmin") {
        await t.run(async (ctx) => {
          await ctx.db.patch(organizationId, {
            status: actor === "pending" ? "pending" : "suspended",
          });
          if (actor === "suspendedAdmin") {
            await ctx.db.insert("platformAdmins", {
              userId: ownerId,
              grantedAt: 1,
            });
          }
        });
      }
      const client =
        actor === "pending" || actor === "suspendedAdmin"
          ? fixture.asOwner
          : fixture[actor];
      const error =
        actor === "pending" || actor === "suspendedAdmin"
          ? "Organization must be verified"
          : "Not permitted for this organization";
      const attempts = [
        () => client.mutation(api.talentOpportunities.create, createArgs),
        () =>
          client.mutation(api.talentOpportunities.update, {
            opportunityId,
            expectedRevision: 1,
          }),
        () =>
          client.mutation(api.talentOpportunities.open, {
            opportunityId,
            expectedRevision: 1,
          }),
        () =>
          client.mutation(api.talentOpportunities.closeApplications, {
            opportunityId,
          }),
        () =>
          client.mutation(api.talentOpportunities.reopen, {
            opportunityId,
            applicationsCloseAt: NOW + DAY_MS,
          }),
        () =>
          client.mutation(api.talentOpportunities.cancel, { opportunityId }),
        () =>
          client.mutation(api.talentOpportunities.deleteDraft, {
            opportunityId,
          }),
        () =>
          client.mutation(api.talentOpportunities.duplicate, { opportunityId }),
        () =>
          client.mutation(api.talentOpportunities.inviteBand, {
            opportunityId,
            bandId,
          }),
        () =>
          client.mutation(api.talentOpportunities.uninviteBand, {
            opportunityId,
            bandId,
          }),
      ];
      for (const attempt of attempts)
        await expect(attempt()).rejects.toThrow(error);
    },
  );
});

describe("opportunity payload", () => {
  test("returns the complete organizer shape with null optionals and opportunity-level currency", async () => {
    const { t, createDraft, asOwner, bandId, venueId } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      currency: "cad",
      slots: [
        { role: "headliner", guaranteeMinor: 10000 },
        { role: "opener", guaranteeMinor: 1000, setLengthMin: 30 },
      ],
    });
    await asOwner.mutation(api.talentOpportunities.inviteBand, {
      opportunityId,
      bandId,
    });
    const { payload, venue } = await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      return {
        payload: await toOpportunityPayload(ctx, opportunity),
        venue: await ctx.db.get(venueId),
      };
    });
    expect(Object.keys(payload).sort()).toEqual(
      Object.keys(opportunityPayloadValidator.fields).sort(),
    );
    expect(payload).toMatchObject({
      _id: opportunityId,
      venueId,
      venue: toVenuePayload(venue!),
      flyerUrl: null,
      area: "Uptown, Oakland",
      venueType: "hall",
      currency: "cad",
      invitedBandIds: [bandId],
      eventType: null,
      expectedAttendance: null,
      doorsAt: null,
      endsAt: null,
      equipment: null,
      requirements: null,
      externalUrl: null,
    });
    expect(payload.slots.map((slot) => slot.order)).toEqual([0, 1]);
    expect(payload.slots[0]).toMatchObject({
      setLengthMin: null,
      bandId: null,
    });
    expect(payload.slots[1]).toMatchObject({ setLengthMin: 30, bandId: null });
    for (const slot of payload.slots)
      expect(slot).not.toHaveProperty("currency");
  });

  test("handles missing venues, optional venue types, and flyer URLs", async () => {
    const { t, createDraft, alternateVenueId } = await setupOrganization();
    const flyStorageId = await t.run((ctx) =>
      ctx.storage.store(new Blob(["photo"], { type: "image/png" })),
    );
    const { opportunityId } = await createDraft({
      venueId: alternateVenueId,
      flyKey: "custom",
      flyStorageId,
    });
    await t.run((ctx) => ctx.db.delete(alternateVenueId));
    const payload = await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      return await toOpportunityPayload(ctx, opportunity);
    });
    expect(payload).toMatchObject({
      venueId: alternateVenueId,
      venue: null,
      venueType: null,
      area: "Berkeley",
    });
    expect(payload.flyerUrl).toEqual(expect.any(String));
    await t.run(async (ctx) => {
      await ctx.db.patch(opportunityId, { venueId: undefined });
      await ctx.storage.delete(flyStorageId);
    });
    const withoutVenue = await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      return await toOpportunityPayload(ctx, opportunity);
    });
    expect(withoutVenue).toMatchObject({
      venueId: null,
      venue: null,
      flyerUrl: null,
    });
  });
});
