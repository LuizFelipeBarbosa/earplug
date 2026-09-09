/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { isPlatformAdmin } from "./lib/authz";
import schema from "./schema";

describe("admin:opsHealth", () => {
  const modules = import.meta.glob("./**/*.ts");
  const now = Date.UTC(2026, 8, 8);
  const day = 24 * 60 * 60 * 1000;

  beforeEach(() => {
    for (const name of [
      "PAYMENTS_ENABLED",
      "TICKETS_ENABLED",
      "PRIVATE_BOOKINGS_ENABLED",
      "DISPUTES_ENABLED",
      "PROMOTERS_ENABLED",
      "BAND_GIG_WRITES",
      "RESEND_SEND_ENABLED",
      "RESEND_API_KEY",
      "CONVEX_CLOUD_URL",
    ]) {
      vi.stubEnv(name, undefined);
    }
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("groups recent events by type, status, and mode in sorted order", async () => {
    const t = convexTest(schema, modules);
    const since = now - 2 * day;
    await t.run(async (ctx) => {
      const rows = [
        {
          eventId: "evt_failed_live",
          type: "payment_intent.succeeded",
          status: "failed",
          livemode: true,
          receivedAt: now - 10,
          error: "Payment record missing",
        },
        {
          eventId: "evt_applied_test_new",
          type: "payment_intent.succeeded",
          status: "applied",
          livemode: false,
          receivedAt: now - 20,
        },
        {
          eventId: "evt_ignored",
          type: "account.updated",
          status: "ignored",
          livemode: true,
          receivedAt: now - 5,
        },
        {
          eventId: "evt_applied_live",
          type: "payment_intent.succeeded",
          status: "applied",
          livemode: true,
          receivedAt: now - 30,
        },
        {
          eventId: "evt_applied_test_boundary",
          type: "payment_intent.succeeded",
          status: "applied",
          livemode: false,
          receivedAt: since,
        },
        {
          eventId: "evt_failed_test",
          type: "payment_intent.succeeded",
          status: "failed",
          livemode: false,
          receivedAt: now - 40,
        },
        {
          eventId: "evt_applied_old",
          type: "payment_intent.succeeded",
          status: "applied",
          livemode: false,
          receivedAt: since - 1,
        },
        {
          eventId: "evt_failed_old",
          type: "account.updated",
          status: "failed",
          livemode: true,
          receivedAt: since - day,
          error: "Old failure",
        },
      ] as const;
      for (const row of rows) {
        await ctx.db.insert("stripeEvents", row);
      }
    });

    const health = await t.query(internal.admin.opsHealth, { days: 2, now });
    expect(health.since).toBe(since);
    expect(health.stripeEvents).toEqual([
      {
        type: "account.updated",
        status: "ignored",
        livemode: true,
        count: 1,
        lastReceivedAt: now - 5,
      },
      {
        type: "payment_intent.succeeded",
        status: "applied",
        livemode: false,
        count: 2,
        lastReceivedAt: now - 20,
      },
      {
        type: "payment_intent.succeeded",
        status: "applied",
        livemode: true,
        count: 1,
        lastReceivedAt: now - 30,
      },
      {
        type: "payment_intent.succeeded",
        status: "failed",
        livemode: false,
        count: 1,
        lastReceivedAt: now - 40,
      },
      {
        type: "payment_intent.succeeded",
        status: "failed",
        livemode: true,
        count: 1,
        lastReceivedAt: now - 10,
      },
    ]);
    expect(health.failed).toEqual([
      {
        eventId: "evt_failed_live",
        type: "payment_intent.succeeded",
        receivedAt: now - 10,
        error: "Payment record missing",
      },
      {
        eventId: "evt_failed_test",
        type: "payment_intent.succeeded",
        receivedAt: now - 40,
      },
    ]);
  });

  test("returns only the 20 newest failures while counting all recent failures", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      for (let index = 0; index < 21; index++) {
        await ctx.db.insert("stripeEvents", {
          eventId: `evt_failed_${index}`,
          type: "account.updated",
          livemode: false,
          status: "failed",
          receivedAt: now - 100 + index,
          error: `Failure ${index}`,
        });
      }
      await ctx.db.insert("stripeEvents", {
        eventId: "evt_applied_newest",
        type: "account.updated",
        livemode: false,
        status: "applied",
        receivedAt: now,
      });
    });

    const health = await t.query(internal.admin.opsHealth, { days: 1, now });
    expect(health.failed).toEqual(
      Array.from({ length: 20 }, (_, offset) => {
        const index = 20 - offset;
        return {
          eventId: `evt_failed_${index}`,
          type: "account.updated",
          receivedAt: now - 100 + index,
          error: `Failure ${index}`,
        };
      }),
    );
    expect(health.stripeEvents).toContainEqual({
      type: "account.updated",
      status: "failed",
      livemode: false,
      count: 21,
      lastReceivedAt: now - 80,
    });
  });

  test.each([
    { days: undefined, expectedDays: 7 },
    { days: -3, expectedDays: 1 },
    { days: 2.5, expectedDays: 2.5 },
    { days: 31, expectedDays: 30 },
  ])(
    "uses $expectedDays days when days is $days",
    async ({ days, expectedDays }) => {
      const t = convexTest(schema, modules);
      const health = await t.query(internal.admin.opsHealth, {
        ...(days === undefined ? {} : { days }),
        now,
      });
      expect(health.since).toBe(now - expectedDays * day);
    },
  );

  test("reports truncation when recent events reach or exceed the 5000-row cap", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await Promise.all(
        Array.from({ length: 4999 }, (_, index) =>
          ctx.db.insert("stripeEvents", {
            eventId: `evt_capped_${index}`,
            type: "account.updated",
            status: "applied",
            livemode: false,
            receivedAt: now,
          }),
        ),
      );
    });

    const underCap = await t.query(internal.admin.opsHealth, { now });
    expect(underCap.truncated).toBe(false);
    expect(underCap.stripeEvents[0].count).toBe(4999);

    for (const count of [5000, 5001]) {
      await t.run((ctx) =>
        ctx.db.insert("stripeEvents", {
          eventId: `evt_capped_${count - 1}`,
          type: "account.updated",
          status: "applied",
          livemode: false,
          receivedAt: now,
        }),
      );
      const health = await t.query(internal.admin.opsHealth, { now });
      expect(health.truncated).toBe(true);
      expect(health.stripeEvents[0].count).toBe(5000);
    }
  });

  test("rejects a non-finite now", async () => {
    const t = convexTest(schema, modules);

    await expect(
      t.query(internal.admin.opsHealth, { now: NaN }),
    ).rejects.toThrow("finite numbers");
  });

  test("rejects non-finite days", async () => {
    const t = convexTest(schema, modules);

    await expect(
      t.query(internal.admin.opsHealth, { days: Infinity, now }),
    ).rejects.toThrow("finite numbers");
  });

  test("returns default flags and no Resend configuration when unset", async () => {
    const t = convexTest(schema, modules);
    expect(await t.query(internal.admin.opsHealth, { now })).toEqual({
      deployment: "unknown",
      since: now - 7 * day,
      truncated: false,
      flags: {
        payments: false,
        tickets: false,
        privateBookings: false,
        disputes: false,
        promoters: false,
        bandGigWrites: true,
        resendSend: false,
      },
      resendConfigured: false,
      stripeEvents: [],
      failed: [],
    });
  });

  test("reports configured flags, deployment, and only the presence of the Resend key", async () => {
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    vi.stubEnv("TICKETS_ENABLED", "1");
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    vi.stubEnv("DISPUTES_ENABLED", "1");
    vi.stubEnv("PROMOTERS_ENABLED", "true");
    vi.stubEnv("BAND_GIG_WRITES", "false");
    vi.stubEnv("RESEND_SEND_ENABLED", "true");
    vi.stubEnv("RESEND_API_KEY", "re_test_key");
    vi.stubEnv("CONVEX_CLOUD_URL", "https://brilliant-cardinal-773.convex.cloud");
    const t = convexTest(schema, modules);
    const health = await t.query(internal.admin.opsHealth, { now });
    expect(health.flags).toEqual({
      payments: true,
      tickets: true,
      privateBookings: true,
      disputes: true,
      promoters: true,
      bandGigWrites: false,
      resendSend: true,
    });
    expect(health.deployment).toBe("brilliant-cardinal-773");
    expect(health.resendConfigured).toBe(true);
    expect(JSON.stringify(health)).not.toContain("re_test_key");
  });
});

describe("admin:me", () => {
  test("reports signed-out, regular, and active-admin callers", async () => {
    const t = convexTest(schema);
    expect(await t.query(api.admin.me, {})).toEqual({ isPlatformAdmin: false });

    const asRegular = t.withIdentity({
      subject: "admin_me_regular",
      email: "regular-admin-me@example.com",
    });
    const asAdmin = t.withIdentity({
      subject: "admin_me_active",
      email: "active-admin-me@example.com",
    });
    await asRegular.mutation(api.users.ensureUser, {});
    await asAdmin.mutation(api.users.ensureUser, {});
    await asAdmin.run(async (ctx) => {
      const user = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "admin_me_active"))
        .unique();
      if (!user) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", { userId: user._id, grantedAt: 1 });
    });

    expect(await asRegular.query(api.admin.me, {})).toEqual({
      isPlatformAdmin: false,
    });
    expect(await asAdmin.query(api.admin.me, {})).toEqual({
      isPlatformAdmin: true,
    });
  });
});

describe("admin:overview", () => {
  test("rejects non-admins and returns bounded status counts to admins", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "overview_admin",
      email: "overview-admin@example.com",
    });
    const asRegular = t.withIdentity({
      subject: "overview_regular",
      email: "overview-regular@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    await asRegular.mutation(api.users.ensureUser, {});
    await t.run(async (ctx) => {
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "overview_admin"))
        .unique();
      if (!admin) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });

      const applicationStatuses = [
        "submitted",
        "submitted",
        "under_review",
        "needs_info",
        "approved",
      ] as const;
      for (const [index, status] of applicationStatuses.entries()) {
        await ctx.db.insert("organizationApplications", {
          applicantUserId: admin._id,
          orgName: `Application ${index}`,
          orgType: "venueOperator",
          contactName: "Applicant",
          businessEmail: `applicant-${index}@example.com`,
          verificationDocStorageIds: [],
          status,
          revision: 1,
          createdAt: index,
          updatedAt: index,
        });
      }

      const organizationStatuses = [
        "verified",
        "verified",
        "suspended",
        "pending",
      ] as const;
      for (const [index, status] of organizationStatuses.entries()) {
        await ctx.db.insert("organizations", {
          name: `Organization ${index}`,
          slug: `organization-${index}`,
          orgType: "venueOperator",
          status,
          ownerUserId: admin._id,
          createdAt: index,
          updatedAt: index,
        });
      }
    });

    await expect(asRegular.query(api.admin.overview, {})).rejects.toThrow(
      "Not an EarPlug admin",
    );
    expect(await asAdmin.query(api.admin.overview, {})).toEqual({
      counts: {
        submittedApplications: 2,
        underReviewApplications: 1,
        needsInfoApplications: 1,
        verifiedOrganizations: 2,
        suspendedOrganizations: 1,
        hostApplications: { submitted: 0, under_review: 0, needs_info: 0 },
      },
      capped: false,
    });
  });
});

describe("admin:overview host applications", () => {
  test("tracks host review counts and caps crowded queues", async () => {
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    try {
      const t = convexTest(schema, import.meta.glob("./**/*.ts"));
      const asAdmin = t.withIdentity({
        subject: "host_overview_admin",
        email: "host-overview-admin@example.com",
      });
      const asApplicant = t.withIdentity({
        subject: "host_overview_applicant",
        email: "host-overview-applicant@example.com",
      });
      const { userId: adminUserId } = await asAdmin.mutation(
        api.users.ensureUser,
        {},
      );
      await asApplicant.mutation(api.users.ensureUser, {});
      await t.run((ctx) =>
        ctx.db.insert("platformAdmins", {
          userId: adminUserId,
          grantedAt: 1,
        }),
      );
      const draft = await asApplicant.mutation(
        api.organizationApplications.saveDraft,
        {
          kind: "host",
          orgName: "",
          orgType: "venueOperator",
          contactName: "",
          businessEmail: "",
          hostDisplayName: "Riley",
          hostPhone: "415-555-0100",
          hostArea: "Mission, San Francisco",
          hostAgreementAccepted: true,
        },
      );
      await asApplicant.mutation(
        api.organizationApplications.generateDocumentUploadUrl,
        {},
      );
      const storageId = await t.run((ctx) =>
        ctx.storage.store(
          new Blob(["host verification"], { type: "application/pdf" }),
        ),
      );
      const attached = await asApplicant.mutation(
        api.organizationApplications.attachDocument,
        {
          applicationId: draft.applicationId,
          storageId,
        },
      );
      await asApplicant.mutation(api.organizationApplications.submit, {
        applicationId: draft.applicationId,
        expectedRevision: attached.revision,
      });
      const overview = await asAdmin.query(api.admin.overview, {});
      expect(overview.counts.hostApplications).toEqual({
        submitted: 1,
        under_review: 0,
        needs_info: 0,
      });
      expect(overview.counts.submittedApplications).toBe(1);
      expect(overview.capped).toBe(false);

      for (const status of ["under_review", "needs_info"] as const) {
        await asAdmin.mutation(api.organizationApplications.decide, {
          applicationId: draft.applicationId,
          decision: status,
        });
        expect(
          (await asAdmin.query(api.admin.overview, {})).counts
            .hostApplications,
        ).toEqual({
          submitted: 0,
          under_review: status === "under_review" ? 1 : 0,
          needs_info: status === "needs_info" ? 1 : 0,
        });
      }

      await t.run(async (ctx) => {
        for (let index = 0; index < 100; index++) {
          await ctx.db.insert("organizationApplications", {
            applicantUserId: adminUserId,
            kind: "host",
            orgName: "",
            orgType: "venueOperator",
            contactName: "",
            businessEmail: "",
            verificationDocStorageIds: [],
            status: "needs_info",
            revision: 1,
            createdAt: index,
            updatedAt: index,
          });
        }
      });
      const cappedOverview = await asAdmin.query(api.admin.overview, {});
      expect(cappedOverview.counts.hostApplications.needs_info).toBe(100);
      expect(cappedOverview.capped).toBe(true);
    } finally {
      vi.unstubAllEnvs();
    }
  });
});

describe("admin:suspendOrganization", () => {
  test("suspends managed venues and restores their public visibility", async () => {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "suspension_admin",
      email: "suspension-admin@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { organizationId, venueIds } = await asAdmin.run(async (ctx) => {
      const admin = await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "suspension_admin"))
        .unique();
      if (!admin) throw new Error("Test admin missing");
      await ctx.db.insert("platformAdmins", {
        userId: admin._id,
        grantedAt: 1,
      });
      const organizationId = await ctx.db.insert("organizations", {
        name: "Suspendable Venues",
        slug: "suspendable-venues",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: admin._id,
        createdAt: 1,
        updatedAt: 1,
      });
      const venueIds = [];
      for (const name of ["Suspend Room A", "Suspend Room B"]) {
        venueIds.push(
          await ctx.db.insert("venues", {
            name,
            area: "Oakland",
            addr: "1 Test Way",
            distSF: "7 mi",
            distOak: "1 mi",
            lat: 37.8,
            lng: -122.27,
            status: "verified",
            addressDisclosure: "public",
            managedByOrganizationId: organizationId,
          }),
        );
      }
      return { organizationId, venueIds };
    });

    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: true,
      note: "Policy review",
    });
    expect(await t.query(api.venues.list, {})).toEqual([]);
    for (const venueId of venueIds) {
      expect(await t.query(api.venues.detail, { venueId })).toBeNull();
    }

    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: false,
    });
    expect(
      (await t.query(api.venues.list, {})).map((venue) => venue._id),
    ).toEqual(venueIds);
    for (const venueId of venueIds) {
      expect(await t.query(api.venues.detail, { venueId })).not.toBeNull();
    }
    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(organization).toMatchObject({ status: "verified" });
    expect(organization?.suspendedAt).toBeUndefined();
  });
});

describe("admin:grantPlatformAdmin", () => {
  test("defaults to dry-run and grants exactly one active row live", async () => {
    const t = convexTest(schema);
    const userId = await t.run((ctx) =>
      ctx.db.insert("users", {
        clerkId: "grant_target",
        name: "Grant Target",
        email: "grant-target@example.com",
        genres: [],
        attendedCount: 0,
      }),
    );

    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, { userId }),
    ).toEqual({ granted: false, alreadyAdmin: false, dryRun: true });
    expect(await t.run((ctx) => isPlatformAdmin(ctx, userId))).toBe(false);

    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, {
        userId,
        note: "Initial operator",
        dryRun: false,
      }),
    ).toEqual({ granted: true, alreadyAdmin: false, dryRun: false });
    expect(
      await t.mutation(internal.admin.grantPlatformAdmin, {
        userId,
        dryRun: false,
      }),
    ).toEqual({ granted: false, alreadyAdmin: true, dryRun: false });
    expect(await t.run((ctx) => isPlatformAdmin(ctx, userId))).toBe(true);
    const activeRows = await t.run((ctx) =>
      ctx.db
        .query("platformAdmins")
        .withIndex("by_userId", (q) => q.eq("userId", userId))
        .filter((q) => q.eq(q.field("revokedAt"), undefined))
        .take(10),
    );
    expect(activeRows).toHaveLength(1);
    expect(activeRows[0].note).toBe("Initial operator");
  });
});

describe("admin:bookings", () => {
  async function setupBookings() {
    const t = convexTest(schema, import.meta.glob("./**/*.ts"));
    const asAdmin = t.withIdentity({ subject: "bookings_admin" });
    const asRegular = t.withIdentity({ subject: "bookings_regular" });
    const { userId: adminUserId } = await asAdmin.mutation(
      api.users.ensureUser,
      {},
    );
    await asRegular.mutation(api.users.ensureUser, {});
    const ids = await t.run(async (ctx) => {
      await ctx.db.insert("platformAdmins", {
        userId: adminUserId,
        grantedAt: 1,
      });
      const organizationId = await ctx.db.insert("organizations", {
        name: "Booking Collective",
        slug: "booking-collective",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: adminUserId,
        createdAt: 1,
        updatedAt: 1,
      });
      const bandId = await ctx.db.insert("bands", {
        name: "Static Bloom",
        slug: "static-bloom",
        genres: ["Indie"],
        bio: "Local live music.",
        area: "Oakland",
        colorHex: "#7B8FFF",
        initials: "SB",
        followerCount: 0,
        pastShows: [],
      });
      const opportunityId = await ctx.db.insert("talentOpportunities", {
        organizationId,
        mode: "publicEvent",
        area: "Oakland",
        title: "Friday at the Hall",
        desc: "An evening of local music.",
        genres: ["Indie"],
        startsAt: 5000,
        ageRequirement: "allAges",
        flyKey: "xerox",
        applicationsCloseAt: 1000,
        visibility: "public",
        ticketing: "rsvp",
        currency: "usd",
        status: "confirmed",
        slug: "friday-at-the-hall",
        createdBy: adminUserId,
        revision: 1,
        applicationCount: 0,
        createdAt: 1,
        updatedAt: 1,
      });
      const slotId = await ctx.db.insert("opportunitySlots", {
        opportunityId,
        order: 0,
        role: "headliner",
        guaranteeMinor: 5000,
        required: true,
        status: "booked",
        bandId,
      });
      const applicationId = await ctx.db.insert("artistApplications", {
        opportunityId,
        slotId,
        bandId,
        submittedBy: adminUserId,
        message: "Available",
        status: "booked",
        createdAt: 1,
        updatedAt: 1,
      });
      const bookingFields = {
        opportunityId,
        slotId,
        organizationId,
        bandId,
        applicationId,
        revision: 1,
        grossMinor: 5000,
        commissionBps: 1000,
        commissionMinor: 500,
        artistNetMinor: 4500,
        currency: "usd",
        cancellationTemplate: "standard" as const,
        organizerAcceptedTermsAt: 1,
        payoutHold: false,
        createdBy: adminUserId,
        createdAt: 1,
        updatedAt: 1,
      };
      // Event times deliberately run opposite to insertion order.
      const disputedId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "disputed",
        startsAt: 5000,
      });
      const heldId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "confirmed",
        startsAt: 4000,
        payoutHold: true,
        payoutHoldReasons: ["admin"],
        paidMinor: 5000,
        refundedMinor: 750,
      });
      const plainId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "confirmed",
        startsAt: 3000,
        payoutHoldReasons: [],
      });
      const awaitingId = await ctx.db.insert("bookings", {
        ...bookingFields,
        status: "awaiting_payment",
        startsAt: 2000,
      });
      return {
        organizationId,
        bandId,
        opportunityId,
        disputedId,
        heldId,
        plainId,
        awaitingId,
      };
    });
    return { t, asAdmin, asRegular, adminUserId, ...ids };
  }

  test("rejects non-admin and signed-out callers", async () => {
    const f = await setupBookings();
    const args = {
      filter: "all" as const,
      paginationOpts: { numItems: 50, cursor: null },
    };
    await expect(f.asRegular.query(api.admin.bookings, args)).rejects.toThrow(
      "Not an EarPlug admin",
    );
    await expect(f.t.query(api.admin.bookings, args)).rejects.toThrow();
  });

  test("all pages by creation newest-first and includes related names and money", async () => {
    const f = await setupBookings();
    const first = await f.asAdmin.query(api.admin.bookings, {
      filter: "all",
      paginationOpts: { numItems: 2, cursor: null },
    });
    expect(first.page).toEqual([
      {
        bookingId: f.awaitingId,
        title: "Friday at the Hall",
        organizationName: "Booking Collective",
        bandName: "Static Bloom",
        status: "awaiting_payment",
        startsAt: 2000,
        paidMinor: 0,
        refundedMinor: 0,
        payoutHoldReasons: [],
        openDisputeId: null,
      },
      {
        bookingId: f.plainId,
        title: "Friday at the Hall",
        organizationName: "Booking Collective",
        bandName: "Static Bloom",
        status: "confirmed",
        startsAt: 3000,
        paidMinor: 0,
        refundedMinor: 0,
        payoutHoldReasons: [],
        openDisputeId: null,
      },
    ]);
    expect(first.isDone).toBe(false);
    const second = await f.asAdmin.query(api.admin.bookings, {
      filter: "all",
      paginationOpts: { numItems: 2, cursor: first.continueCursor },
    });
    expect(second.page.map((row) => row.bookingId)).toEqual([
      f.heldId,
      f.disputedId,
    ]);
    expect(second.page[0]).toMatchObject({
      paidMinor: 5000,
      refundedMinor: 750,
      payoutHoldReasons: ["admin"],
    });
    expect(second.isDone).toBe(true);
  });

  test.each([
    ["disputed", "disputedId"],
    ["held", "heldId"],
    ["awaiting_payment", "awaitingId"],
  ] as const)("%s includes only matching bookings", async (filter, key) => {
    const f = await setupBookings();
    const result = await f.asAdmin.query(api.admin.bookings, {
      filter,
      paginationOpts: { numItems: 50, cursor: null },
    });
    expect(result.page.map((row) => row.bookingId)).toEqual([f[key]]);
  });

  test("held preserves the cursor when an empty page precedes a held booking", async () => {
    const f = await setupBookings();
    const first = await f.asAdmin.query(api.admin.bookings, {
      filter: "held",
      paginationOpts: { numItems: 2, cursor: null },
    });
    expect(first.page).toEqual([]);
    expect(first.isDone).toBe(false);
    const second = await f.asAdmin.query(api.admin.bookings, {
      filter: "held",
      paginationOpts: { numItems: 2, cursor: first.continueCursor },
    });
    expect(second.page.map((row) => row.bookingId)).toEqual([f.heldId]);
    expect(second.isDone).toBe(true);
  });

  test("links open or under-review disputes belonging to the booking and ignores resolved rows", async () => {
    const f = await setupBookings();
    const { disputeId, underReviewId } = await f.t.run(async (ctx) => {
      const fields = {
        openedByUserId: f.adminUserId,
        side: "organizer" as const,
        category: "payment" as const,
        text: "Payment review requested.",
        createdAt: 1,
        updatedAt: 1,
      };
      const underReviewId = await ctx.db.insert("disputes", {
        ...fields,
        bookingId: f.heldId,
        status: "under_review",
      });
      for (const bookingId of [f.disputedId, f.heldId, f.plainId]) {
        await ctx.db.insert("disputes", {
          ...fields,
          bookingId,
          status: "resolved",
        });
      }
      const disputeId = await ctx.db.insert("disputes", {
        ...fields,
        bookingId: f.disputedId,
        status: "open",
      });
      return { disputeId, underReviewId };
    });
    const result = await f.asAdmin.query(api.admin.bookings, {
      filter: "all",
      paginationOpts: { numItems: 50, cursor: null },
    });
    expect(result.page.map((row) => [row.bookingId, row.openDisputeId])).toEqual([
      [f.awaitingId, null],
      [f.plainId, null],
      [f.heldId, underReviewId],
      [f.disputedId, disputeId],
    ]);
  });

  test.each([
    ["organizationId", "organizations"],
    ["bandId", "bands"],
    ["opportunityId", "talentOpportunities"],
  ] as const)("skips a booking with a missing %s", async (field, table) => {
    const f = await setupBookings();
    await f.t.run(async (ctx) => {
      const related = (await ctx.db.get(f[field]))!;
      const { _id, _creationTime, ...fields } = related;
      const missingId = await ctx.db.insert(table, fields);
      await ctx.db.patch(f.plainId, { [field]: missingId });
      await ctx.db.delete(missingId);
    });
    const result = await f.asAdmin.query(api.admin.bookings, {
      filter: "all",
      paginationOpts: { numItems: 50, cursor: null },
    });
    expect(result.page.map((row) => row.bookingId)).toEqual([
      f.awaitingId,
      f.heldId,
      f.disputedId,
    ]);
    expect(result.isDone).toBe(true);
  });
});

describe("admin:suspendOrganization notes", () => {
  test("stores a suspension note and clears it when omitted or unsuspended", async () => {
    const t = convexTest(schema, import.meta.glob("./**/*.ts"));
    const asAdmin = t.withIdentity({ subject: "suspension_note_admin" });
    const { userId } = await asAdmin.mutation(api.users.ensureUser, {});
    const organizationId = await t.run(async (ctx) => {
      await ctx.db.insert("platformAdmins", { userId, grantedAt: 1 });
      return await ctx.db.insert("organizations", {
        name: "Suspension Review",
        slug: "suspension-review",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: userId,
        createdAt: 1,
        updatedAt: 1,
      });
    });
    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: true,
      note: "Policy review",
    });
    expect(await t.run((ctx) => ctx.db.get(organizationId))).toMatchObject({
      status: "suspended",
      suspensionNote: "Policy review",
    });
    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: true,
    });
    expect(
      (await t.run((ctx) => ctx.db.get(organizationId)))?.suspensionNote,
    ).toBeUndefined();
    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: true,
      note: "Follow-up review",
    });
    await asAdmin.mutation(api.admin.suspendOrganization, {
      organizationId,
      suspended: false,
      note: "Must not persist after reinstatement",
    });
    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(organization?.status).toBe("verified");
    expect(organization?.suspensionNote).toBeUndefined();
  });
});
