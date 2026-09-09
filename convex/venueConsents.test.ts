/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { feeSnapshot } from "./lib/fees";
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
  vi.unstubAllEnvs();
});

async function setupConsentFixture() {
  vi.stubEnv("PROMOTERS_ENABLED", "true");
  const t = convexTest(schema, modules);
  const asRequestingOwner = t.withIdentity({ subject: "consent_requesting_owner" });
  const asRequestingManager = t.withIdentity({
    subject: "consent_requesting_manager",
  });
  const asRequestingStranger = t.withIdentity({
    subject: "consent_requesting_stranger",
  });
  const asVenueOwner = t.withIdentity({ subject: "consent_venue_owner" });
  const asVenueManager = t.withIdentity({ subject: "consent_venue_manager" });
  const requestingBusinessEmail = "bookings@requesting.example.com";
  const venueBusinessEmail = "bookings@venue.example.com";
  const ids = await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (const actor of [
      "requesting_owner",
      "requesting_manager",
      "requesting_stranger",
      "venue_owner",
      "venue_manager",
      "artist",
    ]) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `consent_${actor}`,
          name: actor,
          email: `${actor}@consent.test`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    const [
      requestingOwnerId,
      requestingManagerId,
      requestingStrangerId,
      venueOwnerId,
      venueManagerId,
      artistId,
    ] = userIds;
    const requestingOrganizationId = await ctx.db.insert("organizations", {
      name: "Requesting Collective",
      slug: "requesting-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: requestingOwnerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const venueOrganizationId = await ctx.db.insert("organizations", {
      name: "Venue Collective",
      slug: "venue-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: venueOwnerId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const [organizationId, userId, role] of [
      [requestingOrganizationId, requestingOwnerId, "owner"],
      [requestingOrganizationId, requestingManagerId, "manager"],
      [venueOrganizationId, venueOwnerId, "owner"],
      [venueOrganizationId, venueManagerId, "manager"],
    ] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: NOW,
      });
    }
    for (const [organizationId, businessEmail] of [
      [requestingOrganizationId, requestingBusinessEmail],
      [venueOrganizationId, venueBusinessEmail],
    ] as const) {
      await ctx.db.insert("organizationPrivateDetails", {
        organizationId,
        businessEmail,
        contactName: "Bookings Team",
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: [],
        updatedAt: NOW,
      });
    }
    const venueFields = {
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      approxLabel: "Uptown, Oakland",
      venueType: "hall" as const,
      status: "verified" as const,
    };
    const foreignVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      name: "Neighborhood Hall",
      managedByOrganizationId: venueOrganizationId,
    });
    const ownVenueId = await ctx.db.insert("venues", {
      ...venueFields,
      name: "Requesting Hall",
      managedByOrganizationId: requestingOrganizationId,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
      slug: "static-bloom",
    });
    return {
      requestingOwnerId,
      requestingStrangerId,
      venueOwnerId,
      artistId,
      requestingOrganizationId,
      venueOrganizationId,
      foreignVenueId,
      ownVenueId,
      bandId,
    };
  });
  const { opportunityId } = await asRequestingOwner.mutation(
    api.talentOpportunities.create,
    {
      organizationId: ids.requestingOrganizationId,
      venueId: ids.foreignVenueId,
      title: "Friday at the Hall",
      startsAt: NOW + 14 * DAY_MS,
    },
  );
  const slotId = await t.run(async (ctx) => {
    const slot = await ctx.db
      .query("opportunitySlots")
      .withIndex("by_opportunityId_and_order", (q) =>
        q.eq("opportunityId", opportunityId),
      )
      .first();
    if (!slot) throw new Error("Fixture slot missing");
    return slot._id;
  });

  async function seedApplication() {
    return await t.run(async (ctx) => {
      const applicationId = await ctx.db.insert("artistApplications", {
        opportunityId,
        slotId,
        bandId: ids.bandId,
        submittedBy: ids.artistId,
        message: "We are available",
        status: "submitted",
        createdAt: NOW,
        updatedAt: NOW,
      });
      await ctx.db.patch(opportunityId, { applicationCount: 1 });
      return applicationId;
    });
  }

  return {
    t,
    asRequestingOwner,
    asRequestingManager,
    asRequestingStranger,
    asVenueOwner,
    asVenueManager,
    ...ids,
    opportunityId,
    slotId,
    requestingBusinessEmail,
    venueBusinessEmail,
    seedApplication,
  };
}

describe("venueConsents.request", () => {
  test("refuses a request to a suspended venue organization", async () => {
    const f = await setupConsentFixture();
    await f.t.run((ctx) =>
      ctx.db.patch(f.venueOrganizationId, { status: "suspended" }),
    );

    await expect(
      f.asRequestingManager.mutation(api.venueConsents.request, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow(/^This venue is not accepting requests$/);
    expect(
      await f.t.run((ctx) =>
        ctx.db
          .query("venueConsents")
          .withIndex("by_opportunityId", (q) =>
            q.eq("opportunityId", f.opportunityId),
          )
          .take(20),
      ),
    ).toEqual([]);
  });

  test("creates a pending request with a trimmed message and emails the venue", async () => {
    const f = await setupConsentFixture();

    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId, message: "  May we use the hall?  " },
    );

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      _id: consentId,
      opportunityId: f.opportunityId,
      venueId: f.foreignVenueId,
      requestingOrganizationId: f.requestingOrganizationId,
      venueOrganizationId: f.venueOrganizationId,
      status: "pending",
      message: "May we use the hall?",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const scheduled = await f.t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(100),
    );
    const emails = scheduled.filter(
      (job) =>
        job.name === "emails:send" &&
        job.args[0].kind === "venueConsentRequested",
    );
    expect(emails).toHaveLength(1);
    expect(emails[0].args[0].to).toBe(f.venueBusinessEmail);
    expect(emails[0].scheduledTime).toBe(NOW);
  });

  test("refuses a request after the opportunity is opened", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    await f.asRequestingOwner.mutation(api.talentOpportunities.open, {
      opportunityId: f.opportunityId,
      expectedRevision: 1,
    });

    await expect(
      f.asRequestingOwner.mutation(api.venueConsents.request, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("Request venue approval while the event is still a draft");
  });

  test("refuses approval requests for the requesting organization's own venue", async () => {
    const f = await setupConsentFixture();
    const { opportunityId } = await f.asRequestingOwner.mutation(
      api.talentOpportunities.create,
      {
        organizationId: f.requestingOrganizationId,
        venueId: f.ownVenueId,
        title: "Our own hall",
        startsAt: NOW + 14 * DAY_MS,
      },
    );

    await expect(
      f.asRequestingOwner.mutation(api.venueConsents.request, { opportunityId }),
    ).rejects.toThrow("This is one of your own venues");
  });

  test("refuses a duplicate pending request", async () => {
    const f = await setupConsentFixture();
    await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
    });

    await expect(
      f.asRequestingOwner.mutation(api.venueConsents.request, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("A venue request is already open");
  });

  test("refuses a caller without requesting organization membership", async () => {
    const f = await setupConsentFixture();

    await expect(
      f.asRequestingStranger.mutation(api.venueConsents.request, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("Not permitted for this organization");
  });
});

describe("venueConsents.decide", () => {
  test.each(["cancelled", "completed", "deleted"] as const)(
    "refuses approval for a %s opportunity and preserves the pending consent",
    async (status) => {
      const f = await setupConsentFixture();
      const { consentId } = await f.asRequestingOwner.mutation(
        api.venueConsents.request,
        { opportunityId: f.opportunityId },
      );
      const consentBefore = await f.t.run((ctx) => ctx.db.get(consentId));
      await f.t.run(async (ctx) => {
        if (status === "deleted") {
          await ctx.db.delete(f.opportunityId);
        } else {
          await ctx.db.patch(f.opportunityId, { status });
        }
      });

      await expect(
        f.asVenueManager.mutation(api.venueConsents.decide, {
          consentId,
          decision: "granted",
        }),
      ).rejects.toThrow(/^This event is no longer open for approval$/);
      const consentAfter = await f.t.run((ctx) => ctx.db.get(consentId));
      expect(consentAfter?.status).toBe("pending");
      expect(consentAfter).toEqual(consentBefore);
    },
  );

  test("refuses a decision by the former venue organization after management transfers", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    const consentBefore = await f.t.run((ctx) => ctx.db.get(consentId));
    await f.t.run((ctx) =>
      ctx.db.patch(f.foreignVenueId, {
        managedByOrganizationId: f.requestingOrganizationId,
      }),
    );

    await expect(
      f.asVenueOwner.mutation(api.venueConsents.decide, {
        consentId,
        decision: "granted",
      }),
    ).rejects.toThrow(/^This venue is no longer managed by your organization$/);
    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toEqual(consentBefore);
  });

  test.each([
    ["granted", "approved"],
    ["declined", "declined"],
  ] as const)("records a %s decision and emails the requester", async (decision, outcome) => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    vi.setSystemTime(NOW + 1000);

    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision,
      note: "  Please contact our bookings team.  ",
    });

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: decision,
      note: "Please contact our bookings team.",
      decidedByUserId: f.venueOwnerId,
      decidedAt: NOW + 1000,
      updatedAt: NOW + 1000,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" &&
          job.args[0].kind === "venueConsentDecided",
      ),
    );
    expect(emails).toHaveLength(1);
    expect(emails[0].args[0].to).toBe(f.requestingBusinessEmail);
    expect(emails[0].args[0].subject).toContain(outcome);
    expect(emails[0].scheduledTime).toBe(NOW + 1000);
  });

  test("refuses a decision from the requesting organization's owner", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );

    await expect(
      f.asRequestingOwner.mutation(api.venueConsents.decide, {
        consentId,
        decision: "granted",
      }),
    ).rejects.toThrow("Not permitted for this organization");
    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "pending",
    });
  });
});

describe("venueConsents.withdraw", () => {
  test("withdraws a pending request while the opportunity is a draft", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    vi.setSystemTime(NOW + 1000);

    await f.asRequestingOwner.mutation(api.venueConsents.withdraw, { consentId });

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "withdrawn",
      updatedAt: NOW + 1000,
    });
  });

  test("refuses withdrawal after the opportunity is opened", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    await f.asRequestingOwner.mutation(api.talentOpportunities.open, {
      opportunityId: f.opportunityId,
      expectedRevision: 1,
    });

    await expect(
      f.asRequestingOwner.mutation(api.venueConsents.withdraw, { consentId }),
    ).rejects.toThrow("Withdraw is only possible while the event is a draft");
    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "granted",
    });
  });
});

describe("venueConsents.revoke", () => {
  test("refuses revocation by the former venue organization after management transfers", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    const consentBefore = await f.t.run((ctx) => ctx.db.get(consentId));
    await f.t.run((ctx) =>
      ctx.db.patch(f.foreignVenueId, {
        managedByOrganizationId: f.requestingOrganizationId,
      }),
    );

    await expect(
      f.asVenueManager.mutation(api.venueConsents.revoke, { consentId }),
    ).rejects.toThrow(/^This venue is no longer managed by your organization$/);
    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toEqual(consentBefore);
  });

  test("cancels an open opportunity and declines its active application", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    await f.asRequestingOwner.mutation(api.talentOpportunities.open, {
      opportunityId: f.opportunityId,
      expectedRevision: 1,
    });
    const applicationId = await f.seedApplication();
    vi.setSystemTime(NOW + 1000);

    await f.asVenueOwner.mutation(api.venueConsents.revoke, {
      consentId,
      note: "  The hall is no longer available.  ",
    });

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "revoked",
      note: "The hall is no longer available.",
      decidedByUserId: f.venueOwnerId,
      decidedAt: NOW + 1000,
      updatedAt: NOW + 1000,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.opportunityId))).toMatchObject({
      status: "cancelled",
      applicationCount: 0,
    });
    expect(await f.t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
      status: "declined",
      decidedBy: f.venueOwnerId,
      decidedAt: NOW + 1000,
    });
    const emails = await f.t.run(async (ctx) =>
      (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
        (job) =>
          job.name === "emails:send" &&
          job.args[0].kind === "venueConsentDecided" &&
          job.scheduledTime === NOW + 1000,
      ),
    );
    expect(emails).toHaveLength(1);
    expect(emails[0].args[0].to).toBe(f.requestingBusinessEmail);
    expect(emails[0].args[0].subject).toContain("revoked");
  });

  test("preserves a draft opportunity and does not schedule booking cancellations", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    const applicationId = await f.seedApplication();
    const opportunityBefore = await f.t.run((ctx) => ctx.db.get(f.opportunityId));

    await f.asVenueOwner.mutation(api.venueConsents.revoke, { consentId });

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "revoked",
    });
    const opportunity = await f.t.run((ctx) => ctx.db.get(f.opportunityId));
    expect(opportunity?.status).toBe("draft");
    expect(opportunity).toEqual(opportunityBefore);
    expect(await f.t.run((ctx) => ctx.db.get(applicationId))).toMatchObject({
      status: "submitted",
    });
    const scheduled = await f.t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(100),
    );
    expect(
      scheduled.filter(
        (job) =>
          job.name === "emails:send" && job.args[0].kind === "bookingCancelled",
      ),
    ).toEqual([]);
  });

  test("refuses revocation when a confirmed booking exists", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingOwner.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId,
      decision: "granted",
    });
    await f.asRequestingOwner.mutation(api.talentOpportunities.open, {
      opportunityId: f.opportunityId,
      expectedRevision: 1,
    });
    const applicationId = await f.seedApplication();
    const bookingId = await f.t.run(async (ctx) => {
      await ctx.db.patch(applicationId, { status: "booked" });
      await ctx.db.patch(f.opportunityId, { applicationCount: 0 });
      return await ctx.db.insert("bookings", {
        opportunityId: f.opportunityId,
        slotId: f.slotId,
        organizationId: f.requestingOrganizationId,
        bandId: f.bandId,
        applicationId,
        status: "confirmed",
        revision: 1,
        startsAt: NOW + 14 * DAY_MS,
        ...feeSnapshot(0, 0, "usd"),
        cancellationTemplate: "standard",
        organizerAcceptedTermsAt: NOW,
        payoutHold: false,
        createdBy: f.requestingOwnerId,
        createdAt: NOW,
        updatedAt: NOW,
      });
    });
    const scheduledBefore = await f.t.run((ctx) =>
      ctx.db.system.query("_scheduled_functions").take(100),
    );

    await expect(
      f.asVenueOwner.mutation(api.venueConsents.revoke, { consentId }),
    ).rejects.toThrow(
      "This event already has a confirmed booking. Contact EarPlug support.",
    );

    expect(await f.t.run((ctx) => ctx.db.get(consentId))).toMatchObject({
      status: "granted",
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.opportunityId))).toMatchObject({
      status: "open",
    });
    expect(await f.t.run((ctx) => ctx.db.get(bookingId))).toMatchObject({
      status: "confirmed",
    });
    expect(
      await f.t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
    ).toEqual(scheduledBefore);
  });
});

describe("venueConsents.forOpportunity", () => {
  test.each(["pending", "granted"] as const)(
    "prefers an older %s consent over newer decisions",
    async (activeStatus) => {
      const f = await setupConsentFixture();
      const consentIds: Id<"venueConsents">[] = [];
      const statuses = ["declined", activeStatus, "revoked"] as const;
      for (const [index, status] of statuses.entries()) {
        // Separate transactions and clock values establish creation order.
        const createdAt = NOW + index * 1000;
        vi.setSystemTime(createdAt);
        consentIds.push(
          await f.t.run((ctx) =>
            ctx.db.insert("venueConsents", {
              opportunityId: f.opportunityId,
              venueId: f.foreignVenueId,
              venueOrganizationId: f.venueOrganizationId,
              requestingOrganizationId: f.requestingOrganizationId,
              status,
              createdAt,
              updatedAt: createdAt,
            }),
          ),
        );
      }

      expect(
        await f.asRequestingOwner.query(api.venueConsents.forOpportunity, {
          opportunityId: f.opportunityId,
        }),
      ).toMatchObject({
        consentId: consentIds[1],
        status: activeStatus,
        createdAt: NOW + 1000,
      });
    },
  );

  test.each(["declined", "revoked"] as const)(
    "returns the newest %s consent when the history contains only decisions",
    async (newestStatus) => {
      const f = await setupConsentFixture();
      const consentIds: Id<"venueConsents">[] = [];
      const statuses = ["declined", "revoked", newestStatus] as const;
      for (const [index, status] of statuses.entries()) {
        const createdAt = NOW + index * 1000;
        vi.setSystemTime(createdAt);
        consentIds.push(
          await f.t.run((ctx) =>
            ctx.db.insert("venueConsents", {
              opportunityId: f.opportunityId,
              venueId: f.foreignVenueId,
              venueOrganizationId: f.venueOrganizationId,
              requestingOrganizationId: f.requestingOrganizationId,
              status,
              note: `Decision ${index + 1}`,
              createdAt,
              updatedAt: createdAt,
            }),
          ),
        );
      }

      expect(
        await f.asRequestingOwner.query(api.venueConsents.forOpportunity, {
          opportunityId: f.opportunityId,
        }),
      ).toMatchObject({
        consentId: consentIds[2],
        status: newestStatus,
        note: "Decision 3",
        createdAt: NOW + 2000,
      });
    },
  );

  test("returns the active pending request with nullable optional fields", async () => {
    const f = await setupConsentFixture();
    const { consentId } = await f.asRequestingManager.mutation(
      api.venueConsents.request,
      { opportunityId: f.opportunityId },
    );

    expect(
      await f.asRequestingManager.query(api.venueConsents.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).toEqual({
      consentId,
      opportunityId: f.opportunityId,
      venueId: f.foreignVenueId,
      venueOrganizationId: f.venueOrganizationId,
      requestingOrganizationId: f.requestingOrganizationId,
      status: "pending",
      message: null,
      note: null,
      createdAt: NOW,
      decidedAt: null,
    });
  });

  test("returns the most recent declined request when none is active", async () => {
    const f = await setupConsentFixture();
    const first = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
    });
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId: first.consentId,
      decision: "declined",
    });
    vi.setSystemTime(NOW + 1000);
    const second = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
    });
    await f.asVenueManager.mutation(api.venueConsents.decide, {
      consentId: second.consentId,
      decision: "declined",
      note: "The second date is also unavailable.",
    });

    expect(
      await f.asRequestingOwner.query(api.venueConsents.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).toMatchObject({
      consentId: second.consentId,
      status: "declined",
      note: "The second date is also unavailable.",
      createdAt: NOW + 1000,
      decidedAt: NOW + 1000,
    });
  });

  test("refuses a caller without requesting organization membership", async () => {
    const f = await setupConsentFixture();
    await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
    });

    await expect(
      f.asRequestingStranger.query(api.venueConsents.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("Not permitted for this organization");
  });
});

describe("venueConsents.forVenueOrganization", () => {
  test("omits a consent whose opportunity was deleted and keeps valid rows", async () => {
    const f = await setupConsentFixture();
    const orphaned = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
    });
    const { opportunityId } = await f.asRequestingOwner.mutation(
      api.talentOpportunities.create,
      {
        organizationId: f.requestingOrganizationId,
        venueId: f.foreignVenueId,
        title: "Saturday at the Hall",
        startsAt: NOW + 15 * DAY_MS,
      },
    );
    const valid = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId,
    });
    await f.t.run((ctx) => ctx.db.delete(f.opportunityId));

    const rows = await f.asVenueOwner.query(api.venueConsents.forVenueOrganization, {
      organizationId: f.venueOrganizationId,
    });
    expect(rows.map((row) => row.consentId)).toEqual([valid.consentId]);
    expect(rows[0]).toMatchObject({
      opportunityId,
      opportunityTitle: "Saturday at the Hall",
      venueName: "Neighborhood Hall",
      requestingOrganizationName: "Requesting Collective",
    });
    expect(await f.t.run((ctx) => ctx.db.get(orphaned.consentId))).not.toBeNull();
  });

  test("populates distinct opportunities that share a venue and requesting organization", async () => {
    const f = await setupConsentFixture();
    const first = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId: f.opportunityId,
      message: "Friday request",
    });
    await f.asVenueOwner.mutation(api.venueConsents.decide, {
      consentId: first.consentId,
      decision: "granted",
      note: "Friday approved",
    });
    const { opportunityId } = await f.asRequestingOwner.mutation(
      api.talentOpportunities.create,
      {
        organizationId: f.requestingOrganizationId,
        venueId: f.foreignVenueId,
        title: "Saturday at the Hall",
        startsAt: NOW + 15 * DAY_MS,
      },
    );
    await f.t.run((ctx) =>
      ctx.db.patch(opportunityId, { endsAt: NOW + 15 * DAY_MS + 3_600_000 }),
    );
    const second = await f.asRequestingOwner.mutation(api.venueConsents.request, {
      opportunityId,
      message: "Saturday request",
    });

    const rows = await f.asVenueOwner.query(api.venueConsents.forVenueOrganization, {
      organizationId: f.venueOrganizationId,
    });
    const sharedFields = {
      venueId: f.foreignVenueId,
      venueOrganizationId: f.venueOrganizationId,
      requestingOrganizationId: f.requestingOrganizationId,
      venueName: "Neighborhood Hall",
      requestingOrganizationName: "Requesting Collective",
      opportunityStatus: "draft",
      createdAt: NOW,
    };
    expect(rows).toEqual([
      {
        ...sharedFields,
        consentId: second.consentId,
        opportunityId,
        opportunityTitle: "Saturday at the Hall",
        startsAt: NOW + 15 * DAY_MS,
        endsAt: NOW + 15 * DAY_MS + 3_600_000,
        status: "pending",
        message: "Saturday request",
        note: null,
        decidedAt: null,
      },
      {
        ...sharedFields,
        consentId: first.consentId,
        opportunityId: f.opportunityId,
        opportunityTitle: "Friday at the Hall",
        startsAt: NOW + 14 * DAY_MS,
        endsAt: null,
        status: "granted",
        message: "Friday request",
        note: "Friday approved",
        decidedAt: NOW,
      },
    ]);
  });

  test("filters by status and lists pending before granted, newest first within each", async () => {
    const f = await setupConsentFixture();
    const [pendingNew, declinedNew, grantedNew, pendingOld, declinedOld, grantedOld] =
      await f.t.run(async (ctx) => {
        const consentIds: Id<"venueConsents">[] = [];
        // Deliberately insert out of date order to exercise the createdAt index.
        for (const [status, createdAt] of [
          ["pending", NOW + 2000],
          ["declined", NOW + 7000],
          ["granted", NOW + 6000],
          ["pending", NOW + 1000],
          ["declined", NOW + 5000],
          ["granted", NOW + 4000],
        ] as const) {
          consentIds.push(
            await ctx.db.insert("venueConsents", {
              opportunityId: f.opportunityId,
              venueId: f.foreignVenueId,
              venueOrganizationId: f.venueOrganizationId,
              requestingOrganizationId: f.requestingOrganizationId,
              status,
              createdAt,
              updatedAt: createdAt,
            }),
          );
        }
        await ctx.db.insert("venueConsents", {
          opportunityId: f.opportunityId,
          venueId: f.ownVenueId,
          venueOrganizationId: f.requestingOrganizationId,
          requestingOrganizationId: f.venueOrganizationId,
          status: "pending",
          createdAt: NOW + 8000,
          updatedAt: NOW + 8000,
        });
        return consentIds;
      });

    const rows = await f.asVenueOwner.query(api.venueConsents.forVenueOrganization, {
      organizationId: f.venueOrganizationId,
    });
    expect(rows.map((row) => row.consentId)).toEqual([
      pendingNew,
      pendingOld,
      grantedNew,
      grantedOld,
    ]);
    expect(rows[0]).toEqual({
      consentId: pendingNew,
      opportunityId: f.opportunityId,
      venueId: f.foreignVenueId,
      venueOrganizationId: f.venueOrganizationId,
      requestingOrganizationId: f.requestingOrganizationId,
      status: "pending",
      message: null,
      note: null,
      createdAt: NOW + 2000,
      decidedAt: null,
      opportunityTitle: "Friday at the Hall",
      opportunityStatus: "draft",
      startsAt: NOW + 14 * DAY_MS,
      endsAt: null,
      venueName: "Neighborhood Hall",
      requestingOrganizationName: "Requesting Collective",
    });
    for (const [status, expectedIds] of [
      ["pending", [pendingNew, pendingOld]],
      ["granted", [grantedNew, grantedOld]],
      ["declined", [declinedNew, declinedOld]],
    ] as const) {
      const filtered = await f.asVenueManager.query(
        api.venueConsents.forVenueOrganization,
        { organizationId: f.venueOrganizationId, status },
      );
      expect(filtered.map((row) => row.consentId)).toEqual(expectedIds);
      expect(filtered.map((row) => row.status)).toEqual([status, status]);
    }
  });

  test.each([undefined, "finance", "door"] as const)(
    "refuses a caller with venue organization role %s",
    async (role) => {
      const f = await setupConsentFixture();
      if (role !== undefined) {
        await f.t.run((ctx) =>
          ctx.db.insert("organizationMembers", {
            organizationId: f.venueOrganizationId,
            userId: f.requestingStrangerId,
            role,
            createdAt: NOW,
          }),
        );
      }

      await expect(
        f.asRequestingStranger.query(api.venueConsents.forVenueOrganization, {
          organizationId: f.venueOrganizationId,
        }),
      ).rejects.toThrow("Not permitted for this organization");
    },
  );
});
