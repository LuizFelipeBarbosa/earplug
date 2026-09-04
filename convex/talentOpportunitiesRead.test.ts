/// <reference types="vite/client" />
import { ApiFromModules, FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { ArtistApplicationStatus } from "./lib/opportunityStatus";
import schema from "./schema";
import type * as readModule from "./talentOpportunitiesRead";

// Keep the new module typed locally until the integration lane runs codegen.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ talentOpportunitiesRead: typeof readModule }>;
const modules = import.meta.glob("./**/*.ts");
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse("2026-09-04T12:00:00Z");
const paginationOpts = { numItems: 100, cursor: null };

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
  const asOwner = t.withIdentity({ subject: "read_owner" });
  const asManager = t.withIdentity({ subject: "read_manager" });
  const asFinance = t.withIdentity({ subject: "read_finance" });
  const asDoor = t.withIdentity({ subject: "read_door" });
  const asArtist = t.withIdentity({ subject: "read_artist" });
  const asOtherArtist = t.withIdentity({ subject: "read_other_artist" });
  const asStranger = t.withIdentity({ subject: "read_stranger" });
  const ids = await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (const actor of [
      "owner",
      "manager",
      "finance",
      "door",
      "artist",
      "other_artist",
      "stranger",
    ]) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `read_${actor}`,
          name: actor,
          email: `${actor}@opportunity.test`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    const [ownerId, managerId, financeId, doorId, artistId, otherArtistId] =
      userIds;
    const organizationId = await ctx.db.insert("organizations", {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: NOW,
      updatedAt: NOW,
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
        createdAt: NOW,
      });
    }
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
    const alternateVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      name: "Berkeley Bar",
      area: "Berkeley",
      venueType: "bar",
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
    const otherBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: artistId,
      role: "member",
    });
    await ctx.db.insert("bandMembers", {
      bandId: otherBandId,
      userId: otherArtistId,
      role: "admin",
    });
    return {
      ownerId,
      artistId,
      organizationId,
      venueId,
      alternateVenueId,
      bandId,
      otherBandId,
    };
  });

  async function createDraft(
    overrides: Partial<
      FunctionArgs<typeof api.talentOpportunities.create>
    > = {},
  ) {
    return await asOwner.mutation(api.talentOpportunities.create, {
      organizationId: ids.organizationId,
      venueId: ids.venueId,
      title: "Friday at the Hall",
      startsAt: NOW + 14 * DAY_MS,
      applicationsCloseAt: NOW + DAY_MS,
      ...overrides,
    });
  }

  async function createOpen(
    overrides: Partial<
      FunctionArgs<typeof api.talentOpportunities.create>
    > = {},
  ) {
    const opportunity = await createDraft(overrides);
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId: opportunity.opportunityId,
      expectedRevision: 1,
    });
    return opportunity;
  }

  async function seedInvite(
    opportunityId: Id<"talentOpportunities">,
    bandId = ids.bandId,
  ) {
    await t.run(async (ctx) => {
      await ctx.db.insert("opportunityInvites", {
        opportunityId,
        bandId,
        invitedBy: ids.ownerId,
        createdAt: NOW,
      });
    });
  }

  async function seedApplication(
    opportunityId: Id<"talentOpportunities">,
    status: ArtistApplicationStatus = "shortlisted",
  ) {
    return await t.run(async (ctx) => {
      const slot = await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .first();
      if (!slot) throw new Error("Fixture needs a slot");
      return await ctx.db.insert("artistApplications", {
        opportunityId,
        slotId: slot._id,
        bandId: ids.bandId,
        submittedBy: ids.artistId,
        message: "We are available",
        status,
        createdAt: NOW,
        updatedAt: NOW,
      });
    });
  }

  return {
    t,
    asOwner,
    asManager,
    asFinance,
    asDoor,
    asArtist,
    asOtherArtist,
    asStranger,
    ...ids,
    createDraft,
    createOpen,
    seedInvite,
    seedApplication,
  };
}

describe("talent opportunity browse", () => {
  test("signed-out callers see hydrated upcoming open public events in start order", async () => {
    const { t, asOwner, createOpen, createDraft, venueId } =
      await setupOrganization();
    const later = await createOpen({ startsAt: NOW + 4 * DAY_MS });
    const earlier = await createOpen({ startsAt: NOW + 2 * DAY_MS });
    await createDraft();
    await createOpen({ visibility: "inviteOnly" });
    const cancelled = await createOpen();
    await asOwner.mutation(api.talentOpportunities.cancel, {
      opportunityId: cancelled.opportunityId,
    });
    const past = await createOpen();
    const privateBooking = await createOpen();
    // These states have no write mutation path: open rejects past events and
    // create reserves private bookings for a later phase.
    await t.run(async (ctx) => {
      await ctx.db.patch(past.opportunityId, {
        startsAt: Date.now() - 2 * DAY_MS,
      });
      await ctx.db.patch(privateBooking.opportunityId, {
        mode: "privateBooking",
      });
    });

    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      earlier.opportunityId,
      later.opportunityId,
    ]);
    for (const item of result.page) {
      expect(item).toMatchObject({
        invited: false,
        myApplicationStatus: null,
        opportunity: {
          venue: { _id: venueId, name: "Neighborhood Hall" },
          flyerUrl: null,
          slots: [{ guaranteeMinor: 0 }],
        },
      });
    }
  });

  test("pagination continues from the raw page cursor", async () => {
    const { t, createOpen } = await setupOrganization();
    const third = await createOpen({ startsAt: NOW + 4 * DAY_MS });
    const first = await createOpen({ startsAt: NOW + 2 * DAY_MS });
    const second = await createOpen({ startsAt: NOW + 3 * DAY_MS });
    const page1 = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts: { numItems: 2, cursor: null },
    });
    expect(page1.page.map((item) => item.opportunity._id)).toEqual([
      first.opportunityId,
      second.opportunityId,
    ]);
    const page2 = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts: { numItems: 2, cursor: page1.continueCursor },
    });
    expect(page2.page.map((item) => item.opportunity._id)).toEqual([
      third.opportunityId,
    ]);
  });

  test("area is a case-insensitive substring filter", async () => {
    const { t, createOpen, alternateVenueId } = await setupOrganization();
    const match = await createOpen();
    await createOpen({ venueId: alternateVenueId });
    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
      filters: { area: "ToWn, oAk" },
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("genre matches an exact authored array entry", async () => {
    const { t, createOpen } = await setupOrganization();
    const match = await createOpen({ genres: ["Jazz", "Indie"] });
    await createOpen({ genres: ["indie"] });
    await createOpen({ genres: ["Indie Rock"] });
    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
      filters: { genre: "Indie" },
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("venue type matches the hydrated payload", async () => {
    const { t, createOpen, alternateVenueId } = await setupOrganization();
    const match = await createOpen();
    await createOpen({ venueId: alternateVenueId });
    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
      filters: { venueType: "hall" },
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("minimum guarantee uses the largest slot guarantee and includes equality", async () => {
    const { t, createOpen } = await setupOrganization();
    const match = await createOpen({
      slots: [
        { role: "headliner", guaranteeMinor: 100 },
        { role: "support", guaranteeMinor: 10000 },
      ],
    });
    await createOpen({ slots: [{ role: "headliner", guaranteeMinor: 9999 }] });
    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
      filters: { minGuaranteeMinor: 10000 },
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("filters combine and an empty filtered page retains its continuation cursor", async () => {
    const { t, createOpen } = await setupOrganization();
    await createOpen({ genres: ["Jazz"], startsAt: NOW + 2 * DAY_MS });
    const match = await createOpen({
      genres: ["Indie"],
      startsAt: NOW + 3 * DAY_MS,
    });
    const filters = {
      area: "oak",
      genre: "Indie",
      venueType: "hall" as const,
      minGuaranteeMinor: 0,
    };
    const page1 = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts: { numItems: 1, cursor: null },
      filters,
    });
    expect(page1.page).toEqual([]);
    const page2 = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts: { numItems: 1, cursor: page1.continueCursor },
      filters,
    });
    expect(page2.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("uses the stored feed cutoff inclusively when a heartbeat exists", async () => {
    const { t, createOpen } = await setupOrganization();
    await createOpen({ startsAt: NOW + 2 * DAY_MS });
    const match = await createOpen({ startsAt: NOW + 3 * DAY_MS });
    await t.run(async (ctx) => {
      await ctx.db.insert("clock", {
        key: "feedCutoff",
        value: NOW + 3 * DAY_MS,
      });
    });
    const result = await t.query(api.talentOpportunitiesRead.browse, {
      paginationOpts,
    });
    expect(result.page.map((item) => item.opportunity._id)).toEqual([
      match.opportunityId,
    ]);
  });

  test("band state is visible only to members and uses the newest application regardless of status", async () => {
    const {
      t,
      asArtist,
      asStranger,
      bandId,
      createOpen,
      seedInvite,
      seedApplication,
    } = await setupOrganization();
    const { opportunityId } = await createOpen();
    await seedInvite(opportunityId);
    const olderApplicationId = await seedApplication(
      opportunityId,
      "shortlisted",
    );
    vi.setSystemTime(NOW + 1000);
    await seedApplication(opportunityId, "withdrawn");
    await t.run(async (ctx) => {
      await ctx.db.patch(olderApplicationId, { updatedAt: NOW + 2000 });
    });
    const memberResult = await asArtist.query(
      api.talentOpportunitiesRead.browse,
      {
        paginationOpts,
        bandId,
      },
    );
    expect(memberResult.page).toMatchObject([
      {
        opportunity: { _id: opportunityId },
        invited: true,
        myApplicationStatus: "withdrawn",
      },
    ]);
    for (const caller of [asStranger, t]) {
      const result = await caller.query(api.talentOpportunitiesRead.browse, {
        paginationOpts,
        bandId,
      });
      expect(result.page).toMatchObject([
        {
          opportunity: { _id: opportunityId },
          invited: false,
          myApplicationStatus: null,
        },
      ]);
    }
  });
});

describe("invited talent opportunities", () => {
  test("invite-only opportunities appear only for a member of the invited band", async () => {
    const {
      t,
      asArtist,
      asOtherArtist,
      asStranger,
      bandId,
      otherBandId,
      createOpen,
      seedInvite,
      seedApplication,
    } = await setupOrganization();
    const { opportunityId } = await createOpen({ visibility: "inviteOnly" });
    await seedInvite(opportunityId);
    await seedApplication(opportunityId);
    const result = await asArtist.query(
      api.talentOpportunitiesRead.invitedFor,
      { bandId },
    );
    expect(result).toMatchObject([
      {
        opportunity: { _id: opportunityId, visibility: "inviteOnly" },
        invited: true,
        myApplicationStatus: "shortlisted",
      },
    ]);
    expect(
      await asOtherArtist.query(api.talentOpportunitiesRead.invitedFor, {
        bandId: otherBandId,
      }),
    ).toEqual([]);
    for (const caller of [asStranger, asOtherArtist, t]) {
      expect(
        await caller.query(api.talentOpportunitiesRead.invitedFor, { bandId }),
      ).toEqual([]);
    }
  });

  test("lists only upcoming artist-visible statuses, newest start first, and skips stale invites", async () => {
    const {
      t,
      asOwner,
      asArtist,
      bandId,
      createOpen,
      createDraft,
      seedInvite,
    } = await setupOrganization();
    const open = await createOpen({
      startsAt: NOW + 2 * DAY_MS,
      visibility: "inviteOnly",
    });
    const closed = await createOpen({ startsAt: NOW + 3 * DAY_MS });
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId: closed.opportunityId,
    });
    const booking = await createOpen({ startsAt: NOW + 4 * DAY_MS });
    const confirmed = await createOpen({ startsAt: NOW + 5 * DAY_MS });
    const completed = await createOpen();
    const draft = await createDraft();
    const cancelled = await createOpen();
    await asOwner.mutation(api.talentOpportunities.cancel, {
      opportunityId: cancelled.opportunityId,
    });
    const past = await createOpen();
    const deleted = await createDraft();
    await asOwner.mutation(api.talentOpportunities.deleteDraft, {
      opportunityId: deleted.opportunityId,
    });
    await t.run(async (ctx) => {
      await ctx.db.patch(booking.opportunityId, { status: "booking" });
      await ctx.db.patch(confirmed.opportunityId, { status: "confirmed" });
      await ctx.db.patch(completed.opportunityId, { status: "completed" });
      await ctx.db.patch(past.opportunityId, { startsAt: NOW - 2 * DAY_MS });
    });
    for (const opportunity of [
      open,
      closed,
      booking,
      confirmed,
      completed,
      draft,
      cancelled,
      past,
      deleted,
    ]) {
      await seedInvite(opportunity.opportunityId);
    }
    const result = await asArtist.query(
      api.talentOpportunitiesRead.invitedFor,
      { bandId },
    );
    expect(result.map((item) => item.opportunity._id)).toEqual([
      confirmed.opportunityId,
      booking.opportunityId,
      closed.opportunityId,
      open.opportunityId,
    ]);
    expect(
      result.every((item) => item.invited && item.myApplicationStatus === null),
    ).toBe(true);
  });
});

describe("public talent opportunity resolution", () => {
  test("resolves the same hydrated public opportunity by trimmed slug and ID", async () => {
    const { t, createOpen, venueId } = await setupOrganization();
    const { opportunityId, slug } = await createOpen();
    const bySlug = await t.query(api.talentOpportunitiesRead.resolvePublic, {
      ref: ` ${slug} `,
    });
    const byId = await t.query(api.talentOpportunitiesRead.resolvePublic, {
      ref: opportunityId,
    });
    expect(byId).toEqual(bySlug);
    expect(bySlug).toMatchObject({
      opportunity: {
        _id: opportunityId,
        venue: { _id: venueId },
        slots: [{ guaranteeMinor: 0 }],
      },
      invited: false,
      myApplicationStatus: null,
    });
  });

  test("invalid and missing references return null", async () => {
    const { t, venueId, createDraft, asOwner } = await setupOrganization();
    const deleted = await createDraft();
    await asOwner.mutation(api.talentOpportunities.deleteDraft, {
      opportunityId: deleted.opportunityId,
    });
    for (const ref of [
      "",
      "   ",
      "x".repeat(201),
      "unknown-opportunity",
      venueId,
      deleted.opportunityId,
    ]) {
      expect(
        await t.query(api.talentOpportunitiesRead.resolvePublic, { ref }),
      ).toBeNull();
    }
  });

  test("invite-only resolution requires both band membership and an invite", async () => {
    const {
      t,
      asArtist,
      asOtherArtist,
      asStranger,
      asOwner,
      bandId,
      otherBandId,
      createOpen,
      seedInvite,
      seedApplication,
    } = await setupOrganization();
    const { opportunityId } = await createOpen({ visibility: "inviteOnly" });
    await seedInvite(opportunityId);
    await seedApplication(opportunityId);
    expect(
      await asArtist.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
      }),
    ).toBeNull();
    expect(
      await asOtherArtist.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
        bandId: otherBandId,
      }),
    ).toBeNull();
    for (const caller of [asStranger, asOtherArtist, t]) {
      expect(
        await caller.query(api.talentOpportunitiesRead.resolvePublic, {
          ref: opportunityId,
          bandId,
        }),
      ).toBeNull();
    }
    expect(
      await asArtist.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
        bandId,
      }),
    ).toMatchObject({
      opportunity: { _id: opportunityId },
      invited: true,
      myApplicationStatus: "shortlisted",
    });
    expect(
      await asOwner.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
        bandId,
      }),
    ).toMatchObject({
      opportunity: { _id: opportunityId },
      invited: false,
      myApplicationStatus: null,
    });
  });

  test.each(["draft", "cancelled"] as const)(
    "%s opportunities resolve only for organization members even when a band is invited",
    async (status) => {
      const {
        t,
        asOwner,
        asManager,
        asFinance,
        asDoor,
        asArtist,
        asStranger,
        bandId,
        createDraft,
        seedInvite,
      } = await setupOrganization();
      const { opportunityId } = await createDraft();
      if (status === "cancelled") {
        await asOwner.mutation(api.talentOpportunities.cancel, {
          opportunityId,
        });
      }
      await seedInvite(opportunityId);
      for (const caller of [t, asStranger, asArtist]) {
        expect(
          await caller.query(api.talentOpportunitiesRead.resolvePublic, {
            ref: opportunityId,
            bandId,
          }),
        ).toBeNull();
      }
      for (const caller of [asOwner, asManager, asFinance, asDoor]) {
        expect(
          await caller.query(api.talentOpportunitiesRead.resolvePublic, {
            ref: opportunityId,
          }),
        ).toMatchObject({ opportunity: { _id: opportunityId, status } });
      }
    },
  );

  test.each(["applications_closed", "booking", "confirmed"] as const)(
    "public %s opportunities remain resolvable but leave the open browse feed",
    async (status) => {
      const { t, asOwner, createOpen } = await setupOrganization();
      const { opportunityId } = await createOpen();
      await asOwner.mutation(api.talentOpportunities.closeApplications, {
        opportunityId,
      });
      if (status !== "applications_closed") {
        await t.run(async (ctx) => {
          await ctx.db.patch(opportunityId, { status });
        });
      }
      expect(
        await t.query(api.talentOpportunitiesRead.resolvePublic, {
          ref: opportunityId,
        }),
      ).toMatchObject({ opportunity: { _id: opportunityId, status } });
      expect(
        (await t.query(api.talentOpportunitiesRead.browse, { paginationOpts }))
          .page,
      ).toEqual([]);
    },
  );

  test("public resolution does not filter out past open opportunities", async () => {
    const { t, createOpen } = await setupOrganization();
    const { opportunityId } = await createOpen();
    await t.run(async (ctx) => {
      await ctx.db.patch(opportunityId, { startsAt: NOW - 2 * DAY_MS });
    });
    expect(
      await t.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
      }),
    ).toMatchObject({ opportunity: { _id: opportunityId } });
  });

  test("completed opportunities resolve for invited band members and organization members, but not the public", async () => {
    const {
      t,
      asOwner,
      asArtist,
      asOtherArtist,
      bandId,
      otherBandId,
      createOpen,
      seedInvite,
    } = await setupOrganization();
    const { opportunityId } = await createOpen();
    await seedInvite(opportunityId);
    await t.run(async (ctx) => {
      await ctx.db.patch(opportunityId, { status: "completed" });
    });
    expect(
      await t.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
      }),
    ).toBeNull();
    expect(
      await asOtherArtist.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
        bandId: otherBandId,
      }),
    ).toBeNull();
    expect(
      await asArtist.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
        bandId,
      }),
    ).toMatchObject({
      opportunity: { _id: opportunityId, status: "completed" },
      invited: true,
    });
    expect(
      await asOwner.query(api.talentOpportunitiesRead.resolvePublic, {
        ref: opportunityId,
      }),
    ).toMatchObject({
      opportunity: { _id: opportunityId, status: "completed" },
    });
  });
});

describe("organization talent opportunity reads", () => {
  test("manage rejects non-members and sorts drafts before all other statuses by start time", async () => {
    const {
      t,
      asOwner,
      asManager,
      asFinance,
      asDoor,
      asStranger,
      organizationId,
      createDraft,
      createOpen,
    } = await setupOrganization();
    const open = await createOpen({ startsAt: NOW + 5 * DAY_MS });
    const laterDraft = await createDraft({ startsAt: NOW + 10 * DAY_MS });
    const earlierDraft = await createDraft({ startsAt: NOW + 8 * DAY_MS });
    const cancelled = await createOpen({ startsAt: NOW + 2 * DAY_MS });
    await asOwner.mutation(api.talentOpportunities.cancel, {
      opportunityId: cancelled.opportunityId,
    });
    const closed = await createOpen({ startsAt: NOW + 3 * DAY_MS });
    await asOwner.mutation(api.talentOpportunities.closeApplications, {
      opportunityId: closed.opportunityId,
    });
    const booking = await createOpen({ startsAt: NOW + 4 * DAY_MS });
    const confirmed = await createOpen({ startsAt: NOW + 6 * DAY_MS });
    const completed = await createOpen({ startsAt: NOW + 7 * DAY_MS });
    await t.run(async (ctx) => {
      await ctx.db.patch(booking.opportunityId, { status: "booking" });
      await ctx.db.patch(confirmed.opportunityId, { status: "confirmed" });
      await ctx.db.patch(completed.opportunityId, { status: "completed" });
    });
    await expect(
      asStranger.query(api.talentOpportunitiesRead.manageForOrganization, {
        organizationId,
      }),
    ).rejects.toThrow();
    await expect(
      t.query(api.talentOpportunitiesRead.manageForOrganization, {
        organizationId,
      }),
    ).rejects.toThrow();
    for (const caller of [asOwner, asManager, asFinance, asDoor]) {
      const result = await caller.query(
        api.talentOpportunitiesRead.manageForOrganization,
        { organizationId },
      );
      expect(result.map((opportunity) => opportunity._id)).toEqual([
        earlierDraft.opportunityId,
        laterDraft.opportunityId,
        cancelled.opportunityId,
        closed.opportunityId,
        booking.opportunityId,
        open.opportunityId,
        confirmed.opportunityId,
        completed.opportunityId,
      ]);
      expect(
        result.every((opportunity) => opportunity.slots.length === 1),
      ).toBe(true);
    }
  });

  test("get returns a hydrated payload only for organization members and null for missing opportunities", async () => {
    const {
      t,
      asOwner,
      asManager,
      asFinance,
      asDoor,
      asStranger,
      asArtist,
      createOpen,
      createDraft,
      venueId,
    } = await setupOrganization();
    const { opportunityId } = await createOpen();
    for (const caller of [asStranger, asArtist, t]) {
      expect(
        await caller.query(api.talentOpportunitiesRead.get, { opportunityId }),
      ).toBeNull();
    }
    for (const caller of [asOwner, asManager, asFinance, asDoor]) {
      expect(
        await caller.query(api.talentOpportunitiesRead.get, { opportunityId }),
      ).toMatchObject({
        _id: opportunityId,
        venue: { _id: venueId },
        slots: [{ guaranteeMinor: 0 }],
      });
    }
    const deleted = await createDraft();
    await asOwner.mutation(api.talentOpportunities.deleteDraft, {
      opportunityId: deleted.opportunityId,
    });
    expect(
      await asOwner.query(api.talentOpportunitiesRead.get, {
        opportunityId: deleted.opportunityId,
      }),
    ).toBeNull();
  });
});
