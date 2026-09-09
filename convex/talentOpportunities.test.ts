/// <reference types="vite/client" />
import { FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { confirmBooking } from "./lib/bookingConfirm";
import { feeSnapshot } from "./lib/fees";
import { toVenuePayload } from "./lib/helpers";
import {
  opportunityPayloadValidator,
  toArtistOpportunityPayload,
  toOpportunityPayload,
} from "./lib/opportunityPayload";
import { APPLICATION_ACTIVE_STATUSES } from "./lib/opportunityStatus";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
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

async function setupOrganization(
  orgType: "venueOperator" | "privateHost" = "venueOperator",
) {
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
      orgType,
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
    const { managedByOrganizationId: _managedByOrganizationId, ...legacyFields } =
      venueFields;
    const legacyVenueId = await ctx.db.insert("venues", legacyFields);
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
      legacyVenueId,
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
  async function seedBooking(opportunityId: Id<"talentOpportunities">) {
    const [applicationId] = await seedApplications(opportunityId, ["offered"]);
    return await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      const application = await ctx.db.get(applicationId);
      if (!opportunity || !application) throw new Error("Fixture lineage missing");
      const artistId = await ctx.db.insert("users", {
        clerkId: "opportunity_artist",
        name: "Artist",
        email: "artist@opportunity.test",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("bandMembers", {
        bandId: ids.bandId,
        userId: artistId,
        role: "admin",
      });
      const terms = {
        ...feeSnapshot(0, 0, opportunity.currency),
        cancellationTemplate: "standard" as const,
      };
      const bookingId = await ctx.db.insert("bookings", {
        opportunityId,
        slotId: application.slotId,
        organizationId: ids.organizationId,
        bandId: ids.bandId,
        applicationId,
        status: "offer_sent",
        revision: 1,
        startsAt: opportunity.startsAt,
        ...terms,
        organizerAcceptedTermsAt: NOW,
        payoutHold: false,
        expiresAt: NOW + 3 * DAY_MS,
        createdBy: ids.ownerId,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const offerId = await ctx.db.insert("bookingOffers", {
        bookingId,
        revision: 1,
        ...terms,
        installments: [],
        sentBy: ids.ownerId,
        sentAt: NOW,
        expiresAt: NOW + 3 * DAY_MS,
      });
      await ctx.db.patch(bookingId, { currentOfferId: offerId });
      return { bookingId, offerId, applicationId, artistId };
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
    seedBooking,
  };
}


async function setupPrivateHostOrganization() {
  const fixture = await setupOrganization("privateHost");
  const locations = await fixture.t.run(async (ctx) => {
    const fields = {
      organizationId: fixture.organizationId,
      label: "Backyard",
      addr: "42 Garden Street",
      city: "Oakland",
      area: "Rockridge, Oakland",
      lat: 37.84,
      lng: -122.25,
      notes: "Use the side gate",
      createdAt: NOW,
      updatedAt: NOW,
    };
    const privateLocationId = await ctx.db.insert("privateLocations", fields);
    const alternateLocationId = await ctx.db.insert("privateLocations", {
      ...fields,
      area: "Temescal, Oakland",
    });
    const otherLocationId = await ctx.db.insert("privateLocations", {
      ...fields,
      organizationId: fixture.otherOrganizationId,
    });
    return { privateLocationId, alternateLocationId, otherLocationId };
  });
  async function createPrivateDraft(
    overrides: Partial<
      FunctionArgs<typeof api.talentOpportunities.create>
    > = {},
  ) {
    return await fixture.createDraft({
      mode: "privateBooking",
      venueId: undefined,
      privateLocationId: locations.privateLocationId,
      applicationsCloseAt: NOW + 7 * DAY_MS,
      slots: [{ role: "headliner", guaranteeMinor: 10000 }],
      ...overrides,
    });
  }
  return { ...fixture, ...locations, createPrivateDraft };
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

  test("rejects an unverified venue", async () => {
    const { createDraft, unverifiedVenueId } =
      await setupOrganization();
    await expect(createDraft({ venueId: unverifiedVenueId })).rejects.toThrow(
      "Choose one of your verified venues",
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

  test.each([undefined, " USD ", "   "])(
    "stores paid ticketing with normalized USD currency (input: %s)",
    async (ticketCurrency) => {
      const { createDraft, readOpportunity } = await setupOrganization();
      const { opportunityId } = await createDraft({
        ticketing: "paid",
        ticketPriceMinor: 1500,
        ticketCapacity: 100,
        ticketCurrency,
      });
      expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
        ticketing: "paid",
        ticketPriceMinor: 1500,
        ticketCapacity: 100,
        ticketCurrency: "usd",
      });
    },
  );

  test.each([undefined, 50, 100.5])(
    "rejects invalid paid ticket prices: %s",
    async (ticketPriceMinor) => {
      const { createDraft } = await setupOrganization();
      await expect(
        createDraft({ ticketing: "paid", ticketPriceMinor, ticketCapacity: 100 }),
      ).rejects.toThrow("Ticket price must be at least $1.00");
    },
  );

  test.each([undefined, 0, 5001, 1.5])(
    "rejects invalid paid ticket capacities: %s",
    async (ticketCapacity) => {
      const { createDraft } = await setupOrganization();
      await expect(
        createDraft({ ticketing: "paid", ticketPriceMinor: 1500, ticketCapacity }),
      ).rejects.toThrow("Ticket capacity must be between 1 and 5,000");
    },
  );

  test.each([1, 5000])(
    "accepts the minimum ticket price and capacity boundary: %s",
    async (ticketCapacity) => {
      const { createDraft, readOpportunity } = await setupOrganization();
      const { opportunityId } = await createDraft({
        ticketing: "paid",
        ticketPriceMinor: 100,
        ticketCapacity,
      });
      expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
        ticketPriceMinor: 100,
        ticketCapacity,
      });
    },
  );

  test("rejects paid ticketing in unsupported currencies", async () => {
    const { createDraft } = await setupOrganization();
    await expect(
      createDraft({
        ticketing: "paid",
        ticketPriceMinor: 1500,
        ticketCapacity: 100,
        ticketCurrency: "eur",
      }),
    ).rejects.toThrow("Only USD ticketing is supported right now");
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

  test("update locks date changes while a booking is active but permits other edits", async () => {
    const { t, createDraft, asOwner, readOpportunity, seedBooking } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      doorsAt: NOW + 14 * DAY_MS - 3600000,
    });
    const { bookingId } = await seedBooking(opportunityId);
    const before = await readOpportunity(opportunityId);
    const startsAt = NOW + 15 * DAY_MS;
    const doorsAt = startsAt - 3600000;

    for (const dateChange of [{ startsAt }, { doorsAt }, { doorsAt: null }]) {
      await expect(
        asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          title: "Should not be applied",
          ...dateChange,
        }),
      ).rejects.toThrow("Dates are locked while offers or bookings are active");
    }
    expect(await readOpportunity(opportunityId)).toEqual(before);

    expect(
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        title: "Revised title",
      }),
    ).toEqual({ revision: 2 });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      title: "Revised title",
      startsAt: before.opportunity!.startsAt,
      doorsAt: before.opportunity!.doorsAt,
    });

    await t.run((ctx) => ctx.db.patch(bookingId, { status: "declined" }));
    expect(
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 2,
        startsAt,
        doorsAt,
      }),
    ).toEqual({ revision: 3 });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      title: "Revised title",
      startsAt,
      doorsAt,
      revision: 3,
    });
  });

  test.each([undefined, NOW + 14 * DAY_MS - 3600000])(
    "update permits unchanged dates with an active booking (doorsAt: %s)",
    async (doorsAt) => {
      const { createDraft, createArgs, asOwner, readOpportunity, seedBooking } =
        await setupOrganization();
      const { opportunityId } = await createDraft({ doorsAt });
      await seedBooking(opportunityId);

      expect(
        await asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          startsAt: createArgs.startsAt,
          doorsAt: doorsAt ?? null,
          title: "Revised title",
        }),
      ).toEqual({ revision: 2 });
      const { opportunity } = await readOpportunity(opportunityId);
      expect(opportunity).toMatchObject({
        title: "Revised title",
        startsAt: createArgs.startsAt,
        revision: 2,
      });
      expect(opportunity?.doorsAt).toBe(doorsAt);
    },
  );

  test("update validates paid ticketing while preserving omitted ticket fields", async () => {
    const { createDraft, asOwner, readOpportunity } = await setupOrganization();
    const { opportunityId } = await createDraft({
      ticketing: "paid",
      ticketPriceMinor: 1500,
      ticketCapacity: 100,
    });
    await expect(
      asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        ticketPriceMinor: 50,
      }),
    ).rejects.toThrow("Ticket price must be at least $1.00");
    await asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      ticketPriceMinor: 2000,
    });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      ticketing: "paid",
      ticketPriceMinor: 2000,
      ticketCapacity: 100,
      ticketCurrency: "usd",
    });
  });

  test.each(["rsvp", "none", "external"] as const)(
    "update clears paid ticket fields when switching to %s",
    async (ticketing) => {
      const { createDraft, asOwner, readOpportunity } = await setupOrganization();
      const { opportunityId } = await createDraft({
        ticketing: "paid",
        ticketPriceMinor: 1500,
        ticketCapacity: 100,
      });
      await asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        ticketing,
        externalUrl: "https://tickets.test/event",
        ticketPriceMinor: 50,
        ticketCapacity: 0,
        ticketCurrency: "eur",
      });
      const { opportunity } = await readOpportunity(opportunityId);
      expect(opportunity?.ticketing).toBe(ticketing);
      expect(opportunity?.ticketPriceMinor).toBeUndefined();
      expect(opportunity?.ticketCapacity).toBeUndefined();
      expect(opportunity?.ticketCurrency).toBeUndefined();
    },
  );

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

describe("opportunity venue approval", () => {
  test("creates a draft at a foreign verified venue", async () => {
    const { createDraft, readOpportunity, otherVenueId } =
      await setupOrganization();
    const { opportunityId } = await createDraft({ venueId: otherVenueId });
    expect((await readOpportunity(opportunityId)).opportunity).toMatchObject({
      venueId: otherVenueId,
      status: "draft",
    });
  });

  test("rejects an unmanaged legacy venue", async () => {
    const { createDraft, legacyVenueId } = await setupOrganization();
    await expect(createDraft({ venueId: legacyVenueId })).rejects.toThrow(
      "This venue has not joined EarPlug yet",
    );
  });

  test("opening a foreign-venue opportunity requires granted consent", async () => {
    const f = await setupOrganization();
    const applicationsCloseAt = NOW + DAY_MS;
    const { opportunityId } = await f.createDraft({
      venueId: f.otherVenueId,
      applicationsCloseAt,
    });
    const openArgs = { opportunityId, expectedRevision: 1 };
    await expect(
      f.asOwner.mutation(api.talentOpportunities.open, openArgs),
    ).rejects.toThrow("The venue has not approved this event yet");

    const consentId = await f.t.run((ctx) =>
      ctx.db.insert("venueConsents", {
        opportunityId,
        venueId: f.otherVenueId,
        venueOrganizationId: f.otherOrganizationId,
        requestingOrganizationId: f.organizationId,
        status: "pending",
        createdAt: NOW,
        updatedAt: NOW,
      }),
    );
    await expect(
      f.asOwner.mutation(api.talentOpportunities.open, openArgs),
    ).rejects.toThrow("The venue has not approved this event yet");
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "draft",
      revision: 1,
    });

    await f.t.run((ctx) => ctx.db.patch(consentId, { status: "granted" }));
    expect(
      await f.asOwner.mutation(api.talentOpportunities.open, openArgs),
    ).toEqual({ revision: 2, applicationsCloseAt });
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "open",
    });
  });

  describe("opening after venue status changes", () => {
    test.each<Doc<"venues">["status"]>([
      undefined,
      "legacy",
      "pending",
      "verified",
      "suspended",
    ])("does not recheck an own venue's verification status: %s", async (status) => {
      const f = await setupOrganization();
      const { opportunityId } = await f.createDraft();
      await f.t.run((ctx) => ctx.db.patch(f.venueId, { status }));

      await f.asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      });

      expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
        status: "open",
        revision: 2,
      });
    });

    test.each(["unmanaged", "unverified"])(
      "still requires approval for a foreign venue that became %s",
      async (venueState) => {
        const f = await setupOrganization();
        const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
        await f.t.run((ctx) =>
          ctx.db.patch(
            f.otherVenueId,
            venueState === "unmanaged"
              ? { managedByOrganizationId: undefined }
              : { status: "suspended" },
          ),
        );

        await expect(
          f.asOwner.mutation(api.talentOpportunities.open, {
            opportunityId,
            expectedRevision: 1,
          }),
        ).rejects.toThrow(
          "The venue has not approved this event yet",
        );
        expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
          status: "draft",
          revision: 1,
        });
      },
    );
  });

  test.each(["pending", "granted"] as const)(
    "%s consent locks venue and date changes until withdrawal but permits other edits",
    async (status) => {
      const f = await setupOrganization();
      const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
      const consentId = await f.t.run((ctx) =>
        ctx.db.insert("venueConsents", {
          opportunityId,
          venueId: f.otherVenueId,
          venueOrganizationId: f.otherOrganizationId,
          requestingOrganizationId: f.organizationId,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      const before = await f.readOpportunity(opportunityId);
      const startsAt = NOW + 15 * DAY_MS;
      for (const change of [
        { startsAt },
        { doorsAt: startsAt - 3600000 },
        { endsAt: startsAt + 3600000 },
        { venueId: f.venueId },
        { venueId: f.unverifiedVenueId },
      ]) {
        await expect(
          f.asOwner.mutation(api.talentOpportunities.update, {
            opportunityId,
            expectedRevision: 1,
            ...change,
          }),
        ).rejects.toThrow(
          "Withdraw the venue request before changing the venue or date",
        );
      }
      expect(await f.readOpportunity(opportunityId)).toEqual(before);

      expect(
        await f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          desc: "Updated event description",
        }),
      ).toEqual({ revision: 2 });
      expect(
        await f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 2,
          venueId: f.otherVenueId,
          startsAt: f.createArgs.startsAt,
          doorsAt: null,
          endsAt: null,
        }),
      ).toEqual({ revision: 3 });

      await f.t.run((ctx) => ctx.db.patch(consentId, { status: "withdrawn" }));
      expect(
        await f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 3,
          startsAt,
        }),
      ).toEqual({ revision: 4 });
      expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
        desc: "Updated event description",
        startsAt,
      });
    },
  );

  test.each(["pending", "granted"] as const)(
    "an open opportunity with %s consent directs date changes to the venue",
    async (status) => {
      const f = await setupOrganization();
      const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
      const consentId = await f.t.run((ctx) =>
        ctx.db.insert("venueConsents", {
          opportunityId,
          venueId: f.otherVenueId,
          venueOrganizationId: f.otherOrganizationId,
          requestingOrganizationId: f.organizationId,
          status: "granted",
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      await f.asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      });
      await f.t.run((ctx) => ctx.db.patch(consentId, { status }));
      const before = await f.readOpportunity(opportunityId);
      const startsAt = NOW + 15 * DAY_MS;
      for (const change of [
        { startsAt },
        { doorsAt: startsAt - 3600000 },
        { endsAt: startsAt + 3600000 },
      ]) {
        await expect(
          f.asOwner.mutation(api.talentOpportunities.update, {
            opportunityId,
            expectedRevision: 2,
            ...change,
          }),
        ).rejects.toThrow(
          "The venue approved this date. Contact the venue to change it.",
        );
      }
      expect(await f.readOpportunity(opportunityId)).toEqual(before);
      expect(
        await f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 2,
          desc: "Updated event description",
        }),
      ).toEqual({ revision: 3 });
    },
  );

  test("duplicates an opportunity at a foreign verified venue", async () => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
    const copy = await f.asOwner.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    expect(copy.opportunityId).not.toBe(opportunityId);
    expect(
      (await f.readOpportunity(copy.opportunityId)).opportunity,
    ).toMatchObject({ venueId: f.otherVenueId, status: "draft" });
  });

  test("only organizer payloads carry the current venue consent status", async () => {
    const f = await setupOrganization();
    const own = await f.createDraft();
    const foreign = await f.createDraft({ venueId: f.otherVenueId });
    await f.t.run((ctx) =>
      ctx.db.insert("venueConsents", {
        opportunityId: foreign.opportunityId,
        venueId: f.otherVenueId,
        venueOrganizationId: f.otherOrganizationId,
        requestingOrganizationId: f.organizationId,
        status: "pending",
        createdAt: NOW,
        updatedAt: NOW,
      }),
    );

    for (const [opportunityId, venueConsentStatus] of [
      [own.opportunityId, null],
      [foreign.opportunityId, "pending"],
    ] as const) {
      const [organizerPayload, artistPayload] = await f.t.run(async (ctx) => {
        const opportunity = await ctx.db.get(opportunityId);
        if (!opportunity) throw new Error("Fixture opportunity missing");
        return await Promise.all([
          toOpportunityPayload(ctx, opportunity),
          toArtistOpportunityPayload(ctx, opportunity),
        ]);
      });
      expect(organizerPayload).toMatchObject({ venueConsentStatus });
      expect(artistPayload).not.toHaveProperty("venueConsentStatus");
    }
  });

  test("the venue operator dashboard counts only incoming pending consents", async () => {
    const f = await setupOrganization();
    for (const status of ["pending", "granted"] as const) {
      const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
      await f.t.run((ctx) =>
        ctx.db.insert("venueConsents", {
          opportunityId,
          venueId: f.otherVenueId,
          venueOrganizationId: f.otherOrganizationId,
          requestingOrganizationId: f.organizationId,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
    }

    expect(
      await f.asOtherOwner.query(api.organizations.dashboard, {
        organizationId: f.otherOrganizationId,
      }),
    ).toMatchObject({ pendingVenueConsents: 1 });
    expect(
      await f.asOwner.query(api.organizations.dashboard, {
        organizationId: f.organizationId,
      }),
    ).toMatchObject({ pendingVenueConsents: 0 });
  });
});

describe("live opportunity ticketing updates", () => {
  async function setupPublishedOpportunity(ticketing: "paid" | "rsvp" = "paid") {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft({
      ticketing,
      ticketPriceMinor: 1500,
      ticketCapacity: 100,
    });
    await f.asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const { bookingId, offerId, artistId } = await f.seedBooking(opportunityId);
    await f.t.run(async (ctx) => {
      await ctx.db.patch(bookingId, { status: "artist_accepted", revision: 2 });
      await ctx.db.patch(offerId, {
        response: "accepted",
        respondedAt: NOW,
        respondedBy: artistId,
      });
      await confirmBooking(ctx, bookingId);
    });
    const { opportunity } = await f.readOpportunity(opportunityId);
    if (!opportunity?.publicGigId) throw new Error("Expected a published gig");
    expect(opportunity.status).toBe("confirmed");
    return {
      ...f,
      opportunity,
      opportunityId,
      gigId: opportunity.publicGigId,
      updateArgs: {
        opportunityId,
        expectedRevision: opportunity.revision,
        ticketPriceMinor: 2050,
        ticketCapacity: 2,
      },
    };
  }

  test.each([
    ["asOwner", "confirmed", 4],
    ["asManager", "confirmed", 200],
    ["asManager", "booking", 5],
  ] as const)(
    "%s updates a %s paid event to capacity %s and syncs its gig and inventory",
    async (actor, status, ticketCapacity) => {
      const f = await setupPublishedOpportunity();
      const inventoryId = await f.t.run(async (ctx) => {
        await ctx.db.patch(f.opportunityId, { status });
        const inventory = await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
          .unique();
        if (!inventory) throw new Error("Expected paid ticket inventory");
        await ctx.db.patch(inventory._id, { sold: 3, reserved: 1 });
        return inventory._id;
      });
      vi.setSystemTime(NOW + 1000);

      expect(
        await f[actor].mutation(api.talentOpportunities.updateTicketing, {
          ...f.updateArgs,
          ticketCapacity,
        }),
      ).toEqual({
        revision: f.opportunity.revision + 1,
        capacity: ticketCapacity,
      });

      await f.t.run(async (ctx) => {
        expect(await ctx.db.get(f.opportunityId)).toEqual({
          ...f.opportunity,
          status,
          ticketPriceMinor: 2050,
          ticketCapacity,
          revision: f.opportunity.revision + 1,
          updatedAt: NOW + 1000,
        });
        expect(await ctx.db.get(f.gigId)).toMatchObject({
          ticketing: "paid",
          ticketPriceMinor: 2050,
          ticketCurrency: "usd",
          ticketCapacity,
          price: 21,
          lifecycle: "published",
        });
        expect(await ctx.db.get(inventoryId)).toMatchObject({
          capacity: ticketCapacity,
          sold: 3,
          reserved: 1,
          updatedAt: NOW + 1000,
        });
      });
    },
  );

  test.each([
    ["asOwner", "confirmed"],
    ["asManager", "booking"],
  ] as const)(
    "rejects %s lowering a %s event below sold and held tickets without changes",
    async (actor, status) => {
      const f = await setupPublishedOpportunity();
      const before = await f.t.run(async (ctx) => {
        await ctx.db.patch(f.opportunityId, { status });
        const inventory = await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
          .unique();
        if (!inventory) throw new Error("Expected paid ticket inventory");
        await ctx.db.patch(inventory._id, { sold: 3, reserved: 1 });
        return {
          opportunity: await ctx.db.get(f.opportunityId),
          gig: await ctx.db.get(f.gigId),
          inventory: await ctx.db.get(inventory._id),
        };
      });
      vi.setSystemTime(NOW + 1000);

      await expect(
        f[actor].mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow("Capacity cannot go below tickets already sold or held");

      await f.t.run(async (ctx) => {
        expect(await ctx.db.get(f.opportunityId)).toEqual(before.opportunity);
        expect(await ctx.db.get(f.gigId)).toEqual(before.gig);
        expect(
          await ctx.db
            .query("gigTicketInventory")
            .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
            .unique(),
        ).toEqual(before.inventory);
      });
    },
  );

  test.each([NOW, NOW - DAY_MS])(
    "rejects an event starting at %i without changing the opportunity, gig, or inventory",
    async (startsAt) => {
      const f = await setupPublishedOpportunity();
      await f.t.run((ctx) => ctx.db.patch(f.opportunityId, { startsAt }));
      const before = await f.t.run(async (ctx) => ({
        opportunity: await ctx.db.get(f.opportunityId),
        gig: await ctx.db.get(f.gigId),
        inventory: await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
          .unique(),
      }));
      vi.setSystemTime(NOW);

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow("This event has already started");

      await f.t.run(async (ctx) => {
        expect(await ctx.db.get(f.opportunityId)).toEqual(before.opportunity);
        expect(await ctx.db.get(f.gigId)).toEqual(before.gig);
        expect(
          await ctx.db
            .query("gigTicketInventory")
            .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
            .unique(),
        ).toEqual(before.inventory);
      });
    },
  );

  test.each([
    "draft",
    "open",
    "applications_closed",
    "completed",
    "cancelled",
  ] as const)(
    "rejects ticket updates when the opportunity is %s",
    async (status) => {
      const f = await setupPublishedOpportunity();
      await f.t.run((ctx) => ctx.db.patch(f.opportunityId, { status }));

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow("Ticket details can only change on a live paid event");
    },
  );

  test.each(["confirmed", "booking"] as const)(
    "rejects ticket updates for a %s RSVP opportunity",
    async (status) => {
      const f = await setupPublishedOpportunity("rsvp");
      await f.t.run((ctx) => ctx.db.patch(f.opportunityId, { status }));

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow("Ticket details can only change on a live paid event");
    },
  );

  test.each([99, 100.5])(
    "rejects invalid ticket price %s",
    async (ticketPriceMinor) => {
      const f = await setupPublishedOpportunity();

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, {
          ...f.updateArgs,
          ticketPriceMinor,
        }),
      ).rejects.toThrow("Ticket price must be at least $1.00");
    },
  );

  test.each([0, 5001, 1.5])(
    "rejects invalid ticket capacity %s",
    async (ticketCapacity) => {
      const f = await setupPublishedOpportunity();
      await f.t.run(async (ctx) => {
        const inventory = await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
          .unique();
        if (!inventory) throw new Error("Expected paid ticket inventory");
        await ctx.db.patch(inventory._id, { sold: 3, reserved: 1 });
      });

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, {
          ...f.updateArgs,
          ticketCapacity,
        }),
      ).rejects.toThrow("Ticket capacity must be between 1 and 5,000");
    },
  );

  test("rejects a stale revision without changing the opportunity, gig, or inventory", async () => {
    const f = await setupPublishedOpportunity();
    const before = await f.t.run(async (ctx) => ({
      gig: await ctx.db.get(f.gigId),
      inventory: await ctx.db
        .query("gigTicketInventory")
        .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
        .unique(),
    }));
    vi.setSystemTime(NOW + 1000);

    await expect(
      f.asOwner.mutation(api.talentOpportunities.updateTicketing, {
        ...f.updateArgs,
        expectedRevision: f.opportunity.revision - 1,
      }),
    ).rejects.toThrow("Opportunity changed elsewhere");

    await f.t.run(async (ctx) => {
      expect(await ctx.db.get(f.opportunityId)).toEqual(f.opportunity);
      expect(await ctx.db.get(f.gigId)).toEqual(before.gig);
      expect(
        await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
          .unique(),
      ).toEqual(before.inventory);
    });
  });

  test.each(["asFinance", "asDoor", "asStranger", "asOtherOwner"] as const)(
    "rejects ticket updates by %s",
    async (actor) => {
      const f = await setupPublishedOpportunity();

      await expect(
        f[actor].mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow("Not permitted for this organization");
    },
  );

  test.each([
    ["pending", "Organization must be verified"],
    ["suspended", "Organization suspended"],
  ] as const)(
    "rejects ticket updates for a %s organization",
    async (status, error) => {
      const f = await setupPublishedOpportunity();
      await f.t.run((ctx) => ctx.db.patch(f.organizationId, { status }));

      await expect(
        f.asOwner.mutation(api.talentOpportunities.updateTicketing, f.updateArgs),
      ).rejects.toThrow(error);
    },
  );
});

describe("talent opportunity lifecycle", () => {
  test("public opportunities can be updated, opened, closed, reopened, and duplicated", async () => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft({ mode: "publicEvent" });

    await expect(
      f.asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        title: "Updated public event",
      }),
    ).resolves.toEqual({ revision: 2 });
    await expect(
      f.asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 2,
      }),
    ).resolves.toMatchObject({ revision: 3 });
    await expect(
      f.asOwner.mutation(api.talentOpportunities.closeApplications, {
        opportunityId,
      }),
    ).resolves.toBeNull();
    await expect(
      f.asOwner.mutation(api.talentOpportunities.reopen, {
        opportunityId,
        applicationsCloseAt: NOW + 8 * DAY_MS,
      }),
    ).resolves.toBeNull();
    const copy = await f.asOwner.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      mode: "publicEvent",
      status: "open",
      revision: 5,
    });
    const { opportunity: copiedOpportunity } = await f.readOpportunity(
      copy.opportunityId,
    );
    expect(copiedOpportunity).toMatchObject({
      mode: "publicEvent",
      status: "draft",
      title: "Updated public event (copy)",
    });
  });

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

  test("reopen from booking with an open slot returns to open and reschedules expiry", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      applicationsCloseAt: NOW + DAY_MS,
      slots: [
        { role: "headliner", guaranteeMinor: 10000 },
        { role: "support", guaranteeMinor: 5000 },
      ],
    });
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const { slots } = await readOpportunity(opportunityId);
    await t.run(async (ctx) => {
      await ctx.db.patch(opportunityId, { status: "booking" });
      await ctx.db.patch(slots[0]._id, { status: "booked" });
    });

    await expect(
      asOwner.mutation(api.talentOpportunities.reopen, {
        opportunityId,
        applicationsCloseAt: NOW + 2 * DAY_MS,
      }),
    ).resolves.toBeNull();
    const reopened = await readOpportunity(opportunityId);
    expect(reopened.opportunity).toMatchObject({
      status: "open",
      applicationsCloseAt: NOW + 2 * DAY_MS,
    });
    expect(reopened.slots.map((slot) => slot.status)).toEqual([
      "booked",
      "open",
    ]);

    vi.advanceTimersByTime(2 * DAY_MS + 1);
    await t.finishInProgressScheduledFunctions();
    expect((await readOpportunity(opportunityId)).opportunity?.status).toBe(
      "applications_closed",
    );
  });

  test("reopen refuses a booking opportunity whose slots are all booked", async () => {
    const { t, createDraft, asOwner, readOpportunity } =
      await setupOrganization();
    const { opportunityId } = await createDraft({
      applicationsCloseAt: NOW + DAY_MS,
      slots: [
        { role: "headliner", guaranteeMinor: 10000 },
        { role: "support", guaranteeMinor: 5000 },
      ],
    });
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const { slots } = await readOpportunity(opportunityId);
    await t.run(async (ctx) => {
      await ctx.db.patch(opportunityId, { status: "booking" });
      for (const slot of slots) {
        await ctx.db.patch(slot._id, { status: "booked" });
      }
    });

    await expect(
      asOwner.mutation(api.talentOpportunities.reopen, {
        opportunityId,
        applicationsCloseAt: NOW + 2 * DAY_MS,
      }),
    ).rejects.toThrow("Every slot is booked");
  });

  test.each([
    { label: "empty", reason: "" },
    { label: "whitespace-only", reason: " \n\t " },
    { label: "over 500 characters", reason: "x".repeat(501) },
  ])("cancel rejects a $label reason without changing the opportunity or booking", async ({ reason }) => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft();
    const { bookingId, offerId } = await f.seedBooking(opportunityId);
    const before = await f.readOpportunity(opportunityId);
    const bookingBefore = await f.t.run((ctx) => ctx.db.get(bookingId));
    const offerBefore = await f.t.run((ctx) => ctx.db.get(offerId));

    await expect(
      f.asOwner.mutation(api.talentOpportunities.cancel, { opportunityId, reason }),
    ).rejects.toThrow("Cancellation reason must be 1 to 500 characters");

    expect(await f.readOpportunity(opportunityId)).toEqual(before);
    expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toEqual(bookingBefore);
    expect(await f.t.run((ctx) => ctx.db.get(offerId))).toEqual(offerBefore);
  });

  test.each([
    { label: "surrounding whitespace", reason: " \n Venue unavailable \t ", expected: "Venue unavailable" },
    { label: "one character", reason: " x ", expected: "x" },
    { label: "500 characters", reason: ` ${"x".repeat(500)} `, expected: "x".repeat(500) },
  ])("cancel trims a valid reason with $label before storing and emailing it", async ({ reason, expected }) => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft();
    const { bookingId } = await f.seedBooking(opportunityId);

    await f.asOwner.mutation(api.talentOpportunities.cancel, { opportunityId, reason });

    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      status: "cancelled",
    });
    expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toMatchObject({
      status: "withdrawn",
      cancelReason: expected,
    });
    const scheduled = await f.t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(100),
    );
    const emails = scheduled.filter(
      (job) => job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
    );
    expect(emails).toHaveLength(1);
    expect(emails[0].args[0].text).toContain(`Reason: ${expected}`);
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

  test.each([
    ["offer_sent", true],
    ["offer_sent", false],
    ["artist_accepted", true],
    ["awaiting_payment", true],
  ] as const)(
    "cancel withdraws a %s booking and declines its application (offer pointer: %s)",
    async (status, hasOfferPointer) => {
      const f = await setupOrganization();
      const { opportunityId } = await f.createDraft();
      await f.asOwner.mutation(api.talentOpportunities.open, {
        opportunityId,
        expectedRevision: 1,
      });
      const { bookingId, offerId, applicationId } =
        await f.seedBooking(opportunityId);
      await f.t.run((ctx) =>
        ctx.db.patch(bookingId, {
          status,
          currentOfferId: hasOfferPointer ? offerId : undefined,
        }),
      );
      vi.setSystemTime(NOW + 1000);
      await f.asManager.mutation(api.talentOpportunities.cancel, {
        opportunityId,
      });
      const booking = await f.t.run((ctx) => ctx.db.get(bookingId));
      expect(booking).toMatchObject({
        status: "withdrawn",
        cancelledBy: "organizer",
        cancelledByUserId: f.managerId,
        cancelledAt: NOW + 1000,
        cancelReason: "Opportunity cancelled",
        revision: 2,
        updatedAt: NOW + 1000,
      });
      expect(await f.t.run((ctx) => ctx.db.get(offerId))).toMatchObject({
        response: "withdrawn",
        respondedAt: NOW + 1000,
        respondedBy: f.managerId,
      });
      expect(await f.t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
        status: "declined",
        decidedBy: f.managerId,
        decidedAt: NOW + 1000,
        updatedAt: NOW + 1000,
      });
      const result = await f.readOpportunity(opportunityId);
      expect(result.opportunity).toMatchObject({
        status: "cancelled",
        revision: 3,
        applicationCount: 0,
      });
      expect(result.slots[0].status).toBe("cancelled");
      const scheduled = await f.t.run((ctx) =>
        ctx.db.system.query("_scheduled_functions").take(100),
      );
      const emails = scheduled.filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      );
      expect(emails.map((job) => job.args[0].to)).toEqual([
        "artist@opportunity.test",
      ]);
      expect(emails[0].scheduledTime).toBe(NOW + 1000);
      expect(emails[0].args[0].text).toContain("Reason: Opportunity cancelled");
      await expect(
        f.asManager.mutation(api.talentOpportunities.cancel, { opportunityId }),
      ).rejects.toThrow("Opportunity cannot go from cancelled to cancelled");
      expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toEqual(booking);
      expect(
        await f.t.run((ctx) =>
          ctx.db.system.query("_scheduled_functions").take(100),
        ),
      ).toEqual(scheduled);
    },
  );

  test("cancel winds down a confirmed booking and cancels its required-slot gig", async () => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft();
    await f.asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const { bookingId, offerId, applicationId, artistId } =
      await f.seedBooking(opportunityId);
    await f.t.run(async (ctx) => {
      await ctx.db.patch(bookingId, { status: "artist_accepted", revision: 2 });
      await ctx.db.patch(offerId, {
        response: "accepted",
        respondedAt: NOW,
        respondedBy: artistId,
      });
      await confirmBooking(ctx, bookingId);
    });
    const before = await f.readOpportunity(opportunityId);
    const gigId = before.opportunity!.publicGigId!;
    expect(before.slots[0]).toMatchObject({
      status: "booked",
      required: true,
      bookingId,
      bandId: f.bandId,
    });
    expect(await f.t.run((ctx) => ctx.db.get(gigId))).toMatchObject({
      lifecycle: "published",
    });
    vi.setSystemTime(NOW + 1000);
    await f.asOwner.mutation(api.talentOpportunities.cancel, { opportunityId });
    expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toMatchObject({
      status: "cancelled_by_organizer",
      cancelledBy: "organizer",
      cancelledByUserId: f.ownerId,
      cancelledAt: NOW + 1000,
      cancelReason: "Opportunity cancelled",
      revision: 4,
      updatedAt: NOW + 1000,
    });
    const result = await f.readOpportunity(opportunityId);
    expect(result.slots[0]).toMatchObject({ status: "cancelled" });
    expect(result.slots[0].bookingId).toBeUndefined();
    expect(result.slots[0].bandId).toBeUndefined();
    expect(await f.t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
      status: "declined",
      updatedAt: NOW + 1000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(gigId))).toMatchObject({
      lifecycle: "cancelled",
      discoveryListingReady: false,
    });
    expect(result.opportunity).toMatchObject({
      status: "cancelled",
      publicGigId: gigId,
      revision: before.opportunity!.revision + 1,
      applicationCount: 0,
      updatedAt: NOW + 1000,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      ),
    );
    expect(emails.map((job) => job.args[0].to)).toEqual([
      "artist@opportunity.test",
    ]);
    expect(emails[0].args[0].text).toContain("Reason: Opportunity cancelled");
  });

  test("cancel requests ticket refunds and emails buyers for a paid-ticket gig", async () => {
    const f = await setupOrganization();
    const { opportunityId } = await f.createDraft();
    await f.asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
    const { bookingId, offerId, artistId } = await f.seedBooking(opportunityId);
    await f.t.run(async (ctx) => {
      await ctx.db.patch(bookingId, { status: "artist_accepted", revision: 2 });
      await ctx.db.patch(offerId, {
        response: "accepted",
        respondedAt: NOW,
        respondedBy: artistId,
      });
      await confirmBooking(ctx, bookingId);
    });
    const { opportunity } = await f.readOpportunity(opportunityId);
    const gigId = opportunity!.publicGigId!;
    const orderId = await f.t.run(async (ctx) => {
      await ctx.db.patch(gigId, {
        ticketing: "paid",
        ticketPriceMinor: 2000,
        ticketCurrency: "usd",
        ticketCapacity: 20,
      });
      const buyerUserId = await ctx.db.insert("users", {
        clerkId: "ticket_buyer",
        name: "Buyer",
        email: "buyer@tickets.test",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId: f.organizationId,
        capacity: 20,
        reserved: 0,
        sold: 3,
        updatedAt: NOW,
      });
      return await ctx.db.insert("ticketOrders", {
        gigId,
        organizationId: f.organizationId,
        buyerUserId,
        quantity: 3,
        unitPriceMinor: 2000,
        unitFeeMinor: 130,
        subtotalMinor: 6000,
        feeMinor: 390,
        totalMinor: 6390,
        currency: "usd",
        status: "paid",
        reservedUntil: NOW,
        stripePaymentIntentId: "pi_cancelled_event",
        paidAt: NOW,
        attempt: 1,
        refundedMinor: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
    });

    await f.asOwner.mutation(api.talentOpportunities.cancel, { opportunityId });
    expect((await f.readOpportunity(opportunityId)).opportunity?.status).toBe(
      "cancelled",
    );
    expect(await f.t.run((ctx) => ctx.db.get(gigId))).toMatchObject({
      lifecycle: "cancelled",
    });
    const refunds = await f.t.run((ctx) =>
      ctx.db
        .query("ticketRefunds")
        .withIndex("by_orderId", (q) => q.eq("orderId", orderId))
        .take(10),
    );
    expect(refunds).toHaveLength(1);
    expect(refunds[0]).toMatchObject({
      orderId,
      status: "pending",
      reason: "event_cancelled",
      amountMinor: 6390,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "ticketRefunded",
      ),
    );
    expect(emails.map((job) => job.args[0].to)).toEqual(["buyer@tickets.test"]);
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

  test.each(["pending", "granted"] as const)(
    "deleteDraft withdraws %s consent while deleting the opportunity and its children",
    async (status) => {
      const f = await setupOrganization();
      const { opportunityId } = await f.createDraft({ venueId: f.otherVenueId });
      await f.asOwner.mutation(api.talentOpportunities.inviteBand, {
        opportunityId,
        bandId: f.bandId,
      });
      const consentId = await f.t.run((ctx) =>
        ctx.db.insert("venueConsents", {
          opportunityId,
          venueId: f.otherVenueId,
          venueOrganizationId: f.otherOrganizationId,
          requestingOrganizationId: f.organizationId,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        }),
      );
      vi.setSystemTime(NOW + 1000);

      await f.asOwner.mutation(api.talentOpportunities.deleteDraft, { opportunityId });

      expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
        opportunityId,
        status: "withdrawn",
        createdAt: NOW,
        updatedAt: NOW + 1000,
      });
      expect(await f.readOpportunity(opportunityId)).toEqual({
        opportunity: null,
        slots: [],
        invites: [],
      });
    },
  );

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

describe("private talent opportunity drafts", () => {
  test.each([
    {
      mutation: "update",
      status: "draft",
      args: { expectedRevision: 1, title: "Updated private request" },
    },
    { mutation: "open", status: "draft", args: { expectedRevision: 1 } },
    {
      mutation: "reopen",
      status: "applications_closed",
      args: { applicationsCloseAt: NOW + 8 * DAY_MS },
    },
    { mutation: "closeApplications", status: "open", args: {} },
    { mutation: "duplicate", status: "draft", args: {} },
  ] as const)(
    "$mutation supports an existing private request",
    async ({ mutation, status, args }) => {
      const f = await setupPrivateHostOrganization();
      const { opportunityId } = await f.createPrivateDraft();
      await f.t.run((ctx) => ctx.db.patch(opportunityId, { status }));
      await f.asOwner.mutation(api.talentOpportunities[mutation], {
        opportunityId,
        ...args,
      });
    },
  );

  test.each([NOW, 0])(
    "rejects creating a private request at a location archived at %s",
    async (archivedAt) => {
      const f = await setupPrivateHostOrganization();
      await f.t.run((ctx) =>
        ctx.db.patch(f.privateLocationId, { archivedAt }),
      );
      await expect(f.createPrivateDraft()).rejects.toThrow(
        "Choose an active location",
      );
    },
  );

  test.each(["draft", "open"] as const)(
    "rejects moving a private request in %s status to an archived location",
    async (status) => {
      const f = await setupPrivateHostOrganization();
      const { opportunityId } = await f.createPrivateDraft();
      await f.t.run(async (ctx) => {
        await ctx.db.patch(opportunityId, { status });
        await ctx.db.patch(f.alternateLocationId, { archivedAt: NOW });
      });
      const before = await f.readOpportunity(opportunityId);

      await expect(
        f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          privateLocationId: f.alternateLocationId,
        }),
      ).rejects.toThrow("Choose an active location");
      expect(await f.readOpportunity(opportunityId)).toEqual(before);
    },
  );

  test("requires a verified host organization", async () => {
    const f = await setupOrganization();
    await expect(f.createDraft({ mode: "privateBooking" })).rejects.toThrow(
      "Only verified hosts post private requests",
    );
    const host = await setupPrivateHostOrganization();
    await host.t.run((ctx) =>
      ctx.db.patch(host.organizationId, { status: "pending" }),
    );
    await expect(host.createPrivateDraft()).rejects.toThrow(
      "Organization must be verified",
    );
  });

  test("requires an owned location and excludes venues", async () => {
    const f = await setupPrivateHostOrganization();
    await expect(
      f.createPrivateDraft({ privateLocationId: undefined }),
    ).rejects.toThrow("Choose a location");
    await expect(
      f.createPrivateDraft({ privateLocationId: f.otherLocationId }),
    ).rejects.toThrow("Choose a location");
    await f.t.run((ctx) => ctx.db.delete(f.alternateLocationId));
    await expect(
      f.createPrivateDraft({ privateLocationId: f.alternateLocationId }),
    ).rejects.toThrow("Choose a location");
    await expect(f.createPrivateDraft({ venueId: f.venueId })).rejects.toThrow(
      "Private requests don't use a venue",
    );
  });

  test("requires positive guarantees and an explicit deadline before the event", async () => {
    const f = await setupPrivateHostOrganization();
    for (const slots of [
      undefined,
      [],
      [{ role: "headliner" as const, guaranteeMinor: 0 }],
    ]) {
      await expect(f.createPrivateDraft({ slots })).rejects.toThrow(
        "Private slots need a guarantee",
      );
    }
    await expect(
      f.createPrivateDraft({
        slots: [{ role: "headliner", guaranteeMinor: 1.5 }],
      }),
    ).rejects.toThrow("Slot guarantee must be a non-negative integer");
    for (const applicationsCloseAt of [
      undefined,
      NOW + 14 * DAY_MS,
      NOW + 15 * DAY_MS,
      Number.NaN,
    ]) {
      await expect(
        f.createPrivateDraft({ applicationsCloseAt }),
      ).rejects.toThrow("Set an application deadline before the event");
    }
  });

  test("creates a private request with no ticketing", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft({
      ticketing: "paid",
      ticketPriceMinor: -100,
      ticketCapacity: -1,
      ticketCurrency: "cad",
    });
    const { opportunity, slots } = await f.readOpportunity(opportunityId);
    expect(opportunity).toMatchObject({
      mode: "privateBooking",
      privateLocationId: f.privateLocationId,
      area: "Rockridge, Oakland",
      ticketing: "none",
      applicationsCloseAt: NOW + 7 * DAY_MS,
    });
    for (const field of [
      "venueId",
      "venueType",
      "ticketPriceMinor",
      "ticketCapacity",
      "ticketCurrency",
    ]) {
      expect(opportunity).not.toHaveProperty(field);
    }
    expect(slots[0]).toMatchObject({ guaranteeMinor: 10000 });
  });

  test("updates owned locations and area in draft and open requests", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    await expect(
      f.asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        venueId: f.venueId,
      }),
    ).rejects.toThrow("Private requests don't use a venue");
    await expect(
      f.asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        privateLocationId: f.otherLocationId,
      }),
    ).rejects.toThrow("Choose a location");
    await f.asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      privateLocationId: f.alternateLocationId,
    });
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      privateLocationId: f.alternateLocationId,
      area: "Temescal, Oakland",
      revision: 2,
    });
    await f.asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 2,
    });
    await f.asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 3,
      privateLocationId: f.privateLocationId,
    });
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      privateLocationId: f.privateLocationId,
      area: "Rockridge, Oakland",
      status: "open",
    });
  });

  test("updates retain private guarantees, deadline rules, and no ticketing", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    for (const slots of [
      [],
      [{ role: "headliner" as const, guaranteeMinor: 0 }],
    ]) {
      await expect(
        f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          slots,
        }),
      ).rejects.toThrow("Private slots need a guarantee");
    }
    for (const fields of [
      { applicationsCloseAt: NOW + 14 * DAY_MS },
      { startsAt: NOW + 7 * DAY_MS },
    ]) {
      await expect(
        f.asOwner.mutation(api.talentOpportunities.update, {
          opportunityId,
          expectedRevision: 1,
          ...fields,
        }),
      ).rejects.toThrow("Set an application deadline before the event");
    }
    await f.asOwner.mutation(api.talentOpportunities.update, {
      opportunityId,
      expectedRevision: 1,
      ticketing: "paid",
      ticketPriceMinor: 1000,
      ticketCapacity: 10,
      ticketCurrency: "cad",
      slots: [{ role: "headliner", guaranteeMinor: 20000 }],
    });
    const { opportunity, slots } = await f.readOpportunity(opportunityId);
    expect(opportunity).toMatchObject({ ticketing: "none", revision: 2 });
    for (const field of [
      "ticketPriceMinor",
      "ticketCapacity",
      "ticketCurrency",
    ]) {
      expect(opportunity).not.toHaveProperty(field);
    }
    expect(slots[0].guaranteeMinor).toBe(20000);
  });

  test("public events require venues and reject private locations on create and update", async () => {
    const f = await setupPrivateHostOrganization();
    await expect(f.createDraft({ venueId: undefined })).rejects.toThrow(
      "Choose one of your verified venues",
    );
    await expect(
      f.createDraft({ privateLocationId: f.privateLocationId }),
    ).rejects.toThrow("Public events don't use a private location");
    const { opportunityId } = await f.createDraft();
    await expect(
      f.asOwner.mutation(api.talentOpportunities.update, {
        opportunityId,
        expectedRevision: 1,
        privateLocationId: f.privateLocationId,
      }),
    ).rejects.toThrow("Public events don't use a private location");
  });

  test("duplicates the private location", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    const copy = await f.asOwner.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    const { opportunity } = await f.readOpportunity(copy.opportunityId);
    expect(opportunity).toMatchObject({
      mode: "privateBooking",
      privateLocationId: f.privateLocationId,
      area: "Rockridge, Oakland",
      ticketing: "none",
      status: "draft",
    });
    expect(opportunity).not.toHaveProperty("venueId");
  });

  test("omits an archived private location when duplicating a draft", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    await f.t.run((ctx) =>
      ctx.db.patch(f.privateLocationId, { archivedAt: NOW }),
    );

    const copy = await f.asOwner.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    const { opportunity } = await f.readOpportunity(copy.opportunityId);
    expect(opportunity).toMatchObject({
      mode: "privateBooking",
      status: "draft",
      area: "Rockridge, Oakland",
    });
    expect(opportunity).not.toHaveProperty("privateLocationId");
    expect((await f.readOpportunity(opportunityId)).opportunity).toMatchObject({
      privateLocationId: f.privateLocationId,
    });
  });

  test("preserves a missing private location reference when duplicating a draft", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    await f.t.run((ctx) => ctx.db.delete(f.privateLocationId));

    const copy = await f.asOwner.mutation(api.talentOpportunities.duplicate, {
      opportunityId,
    });
    const { opportunity } = await f.readOpportunity(copy.opportunityId);
    expect(opportunity).toMatchObject({
      mode: "privateBooking",
      status: "draft",
      privateLocationId: f.privateLocationId,
    });
  });

  test("organizer and artist payloads reveal only the area, even with stale venue fields", async () => {
    const f = await setupPrivateHostOrganization();
    const { opportunityId } = await f.createPrivateDraft();
    await f.t.run((ctx) =>
      ctx.db.patch(opportunityId, {
        venueId: f.venueId,
        venueType: "hall",
      }),
    );
    const { payload, artistPayload } = await f.t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      const getSpy = vi.spyOn(ctx.db, "get");
      try {
        const payload = await toOpportunityPayload(ctx, opportunity);
        const artistPayload = await toArtistOpportunityPayload(
          ctx,
          opportunity,
        );
        expect(getSpy).not.toHaveBeenCalled();
        return { payload, artistPayload };
      } finally {
        getSpy.mockRestore();
      }
    });
    expect(payload).toMatchObject({
      privateEvent: true,
      venueId: null,
      venue: null,
      venueType: "private",
      area: "Rockridge, Oakland",
    });
    expect(Object.keys(payload).sort()).toEqual(
      Object.keys(opportunityPayloadValidator.fields).sort(),
    );
    for (const field of [
      "privateLocationId",
      "addr",
      "lat",
      "lng",
      "notes",
      "label",
    ]) {
      expect(payload).not.toHaveProperty(field);
    }
    const { invitedBandIds, venueConsentStatus, ...expectedArtistPayload } = payload;
    expect(artistPayload).toEqual(expectedArtistPayload);
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
      privateEvent: false,
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
