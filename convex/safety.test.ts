/// <reference types="vite/client" />
import type { ApiFromModules, FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { feeSnapshot } from "./lib/fees";
import * as safety from "./safety";
import schema from "./schema";

// Keep references typed without changing generated files owned by another lane.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ safety: typeof safety }>;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-04T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTORS = [
  "owner",
  "manager",
  "artist",
  "member",
  "stranger",
  "platformAdmin",
] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupSafety() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `safety_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `safety_${actor}`,
        name: actor,
        email: `  ${actor}@safety.test  `,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Safety Collective",
      slug: "safety-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    });
    for (const [actor, role] of [
      ["artist", "admin"],
      ["member", "member"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: users[actor],
        role,
      });
    }
    const privateLocationId = await ctx.db.insert("privateLocations", {
      organizationId,
      label: "Garden reception",
      addr: "200 Private Street",
      city: "Oakland",
      area: "Oakland",
      lat: 37.8,
      lng: -122.27,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      privateLocationId,
      mode: "privateBooking",
      area: "Oakland",
      venueType: "hall",
      title: "Private reception",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: NOW + 14 * DAY_MS,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "confirmed",
      slug: "private-reception",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 0,
      required: true,
      status: "booked",
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.artist,
      status: "booked",
      message: "We are available",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "confirmed",
      revision: 3,
      startsAt: NOW + 14 * DAY_MS,
      ...feeSnapshot(0, 0),
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW,
      artistAcceptedTermsAt: NOW,
      confirmedAt: NOW,
      payoutHold: false,
      createdBy: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    await ctx.db.patch(slotId, { bookingId, bandId });
    return {
      users,
      organizationId,
      bandId,
      privateLocationId,
      opportunityId,
      bookingId,
    };
  });
  const report = (
    actor: Actor = "artist",
    fields: Partial<FunctionArgs<typeof api.safety.report>> = {},
  ) =>
    as(actor).mutation(api.safety.report, {
      bookingId: ids.bookingId,
      category: "safety",
      text: "  Unsafe conditions at the event  ",
      ...fields,
    });
  return {
    t,
    as,
    ...ids,
    report,
    readReport: (reportId: Id<"safetyReports">) =>
      t.run((ctx) => ctx.db.get(reportId)),
    emails: () =>
      t.run(async (ctx) =>
        (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
          (job) => job.name === "emails:send",
        ),
      ),
  };
}

describe("safety reporting", () => {
  test.each([
    ["artist", "artist", "harassment"],
    ["owner", "organizer", "misrepresentation"],
    ["manager", "organizer", "other"],
  ] as const)(
    "accepts a report from %s and emails only the reporter",
    async (actor, side, category) => {
      const f = await setupSafety();
      vi.stubEnv("APP_BASE_URL", "https://safety.example.test");
      const { reportId } = await f.report(actor, { category });
      expect(await f.readReport(reportId)).toMatchObject({
        bookingId: f.bookingId,
        reporterUserId: f.users[actor],
        side,
        category,
        text: "Unsafe conditions at the event",
        status: "open",
        createdAt: NOW,
      });
      const emails = await f.emails();
      expect(emails).toHaveLength(1);
      expect(emails[0]).toMatchObject({
        scheduledTime: NOW,
        args: [
          {
            kind: "safetyReportReceived",
            to: `${actor}@safety.test`,
            subject: "We received your report about Private reception",
            text: expect.stringContaining("received your report"),
          },
        ],
      });
      expect(emails[0].args[0].text).toContain("Private event");
      expect(emails[0].args[0].text).toContain(
        `https://safety.example.test/bookings/${f.bookingId}`,
      );
      expect(emails[0].args[0].text).not.toContain("200 Private Street");
    },
  );

  test.each(["stranger", "member", "platformAdmin"] as const)(
    "refuses reporting and reading as non-party %s",
    async (actor) => {
      const f = await setupSafety();
      await expect(f.report(actor)).rejects.toThrow(
        "Not permitted to report on this booking",
      );
      await expect(
        f.as(actor).query(api.safety.mine, { bookingId: f.bookingId }),
      ).rejects.toThrow("Not permitted to report on this booking");
    },
  );

  test.each([
    "completed",
    "paid",
    "cancelled_by_artist",
    "cancelled_by_organizer",
    "disputed",
    "force_majeure",
    "refunded",
  ] as const)("enforces the strict 30-day window for %s", async (status) => {
    const f = await setupSafety();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, { status, startsAt: NOW - 30 * DAY_MS }),
    );
    vi.setSystemTime(NOW - 1);
    await expect(f.report()).resolves.toHaveProperty("reportId");
    vi.setSystemTime(NOW);
    await expect(f.report()).rejects.toThrow(
      "Reports are open until 30 days after the event",
    );
    vi.setSystemTime(NOW + 1);
    await expect(f.report()).rejects.toThrow(
      "Reports are open until 30 days after the event",
    );
  });

  test("keeps confirmed bookings reportable without a time bound", async () => {
    const f = await setupSafety();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        status: "confirmed",
        startsAt: NOW - 60 * DAY_MS,
      }),
    );
    await expect(f.report()).resolves.toHaveProperty("reportId");
  });

  test.each([
    "offer_sent",
    "artist_accepted",
    "awaiting_payment",
    "expired",
    "withdrawn",
    "declined",
  ] as const)("refuses reports for ineligible status %s", async (status) => {
    const f = await setupSafety();
    await f.t.run((ctx) => ctx.db.patch(f.bookingId, { status }));
    await expect(f.report()).rejects.toThrow(
      "Reports are open until 30 days after the event",
    );
  });

  test.each(["  short  ", "x".repeat(2001)])(
    "rejects report details outside the length limits",
    async (text) => {
      const f = await setupSafety();
      await expect(f.report("artist", { text })).rejects.toThrow(
        "Report details must be between 10 and 2000 characters",
      );
      expect(await f.emails()).toEqual([]);
    },
  );

  test.each([10, 2000])(
    "accepts %s characters after trimming",
    async (length) => {
      const f = await setupSafety();
      const { reportId } = await f.report("artist", {
        text: `  ${"x".repeat(length)}  `,
      });
      expect((await f.readReport(reportId))?.text).toHaveLength(length);
    },
  );

  test("saves the report without scheduling mail when the reporter has no email", async () => {
    const f = await setupSafety();
    await f.t.run((ctx) => ctx.db.patch(f.users.artist, { email: " \t\n " }));
    const { reportId } = await f.report();
    expect(await f.readReport(reportId)).toMatchObject({ status: "open" });
    expect(await f.emails()).toEqual([]);
  });

  test("mine returns only this user's reports for this booking, newest first", async () => {
    const f = await setupSafety();
    const first = await f.report("owner");
    vi.setSystemTime(NOW + 1);
    await f.report("manager");
    await f.report("artist");
    vi.setSystemTime(NOW + 2);
    const second = await f.report("owner");
    const otherBookingId = await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...booking } = (await ctx.db.get(
        f.bookingId,
      ))!;
      return await ctx.db.insert("bookings", booking);
    });
    await f.report("owner", { bookingId: otherBookingId });
    const reports = await f
      .as("owner")
      .query(api.safety.mine, { bookingId: f.bookingId });
    expect(reports.map((report) => report._id)).toEqual([
      second.reportId,
      first.reportId,
    ]);
    expect(
      reports.every((report) => report.reporterUserId === f.users.owner),
    ).toBe(true);
  });
});

describe("safety admin triage", () => {
  test("paginates open reports, resolves them, and retains booking history", async () => {
    const f = await setupSafety();
    const first = await f.report("artist");
    vi.setSystemTime(NOW + 1);
    const second = await f.report("owner");
    const admin = f.as("platformAdmin");
    const firstPage = await admin.query(api.safety.listOpen, {
      paginationOpts: { numItems: 1, cursor: null },
    });
    expect(firstPage.page).toMatchObject([
      {
        _id: second.reportId,
        bookingTitle: "Private reception",
        bandName: "Static Bloom",
        reporterSide: "organizer",
        status: "open",
      },
    ]);
    expect(firstPage.isDone).toBe(false);
    const secondPage = await admin.query(api.safety.listOpen, {
      paginationOpts: { numItems: 1, cursor: firstPage.continueCursor },
    });
    expect(secondPage.page).toMatchObject([
      { _id: first.reportId, reporterSide: "artist" },
    ]);

    vi.setSystemTime(NOW + 2);
    const args = {
      reportId: second.reportId,
      adminNote: "Reviewed with the reporter",
    };
    await expect(admin.mutation(api.safety.resolve, args)).resolves.toBeNull();
    await expect(admin.mutation(api.safety.resolve, args)).resolves.toBeNull();
    expect(await f.readReport(second.reportId)).toMatchObject({
      status: "resolved",
      resolvedAt: NOW + 2,
      resolvedBy: f.users.platformAdmin,
      adminNote: args.adminNote,
    });
    const open = await admin.query(api.safety.listOpen, {
      paginationOpts: { numItems: 10, cursor: null },
    });
    expect(open.page.map((report) => report._id)).toEqual([first.reportId]);
    const history = await admin.query(api.safety.forBookingAdmin, {
      bookingId: f.bookingId,
    });
    expect(history.map((report) => report._id)).toEqual([
      second.reportId,
      first.reportId,
    ]);
    expect(history[0]).toMatchObject({
      status: "resolved",
      resolvedAt: NOW + 2,
      resolvedBy: f.users.platformAdmin,
      adminNote: args.adminNote,
    });
    const mine = await f.as("owner").query(api.safety.mine, {
      bookingId: f.bookingId,
    });
    expect(mine).toHaveLength(1);
    expect(mine[0]).toMatchObject({
      _id: second.reportId,
      status: "resolved",
      resolvedAt: NOW + 2,
      text: "Unsafe conditions at the event",
    });
    expect(mine[0]).not.toHaveProperty("adminNote");
    expect(mine[0]).not.toHaveProperty("resolvedBy");
    expect(mine[0]).not.toHaveProperty("_creationTime");
  });

  test("refuses all admin operations for a plain band member", async () => {
    const f = await setupSafety();
    const { reportId } = await f.report();
    const member = f.as("member");
    await expect(
      member.query(api.safety.listOpen, {
        paginationOpts: { numItems: 10, cursor: null },
      }),
    ).rejects.toThrow("Not an EarPlug admin");
    await expect(
      member.mutation(api.safety.resolve, { reportId }),
    ).rejects.toThrow("Not an EarPlug admin");
    await expect(
      member.query(api.safety.forBookingAdmin, { bookingId: f.bookingId }),
    ).rejects.toThrow("Not an EarPlug admin");
    expect(await f.readReport(reportId)).toMatchObject({ status: "open" });
  });

  test.each(["booking", "opportunity", "band"] as const)(
    "lists reports when the %s has been deleted",
    async (missing) => {
      const f = await setupSafety();
      const { reportId } = await f.report();
      await f.t.run((ctx) =>
        ctx.db.delete(
          missing === "booking"
            ? f.bookingId
            : missing === "opportunity"
              ? f.opportunityId
              : f.bandId,
        ),
      );
      const result = await f.as("platformAdmin").query(api.safety.listOpen, {
        paginationOpts: { numItems: 10, cursor: null },
      });
      expect(result.page).toMatchObject([
        {
          _id: reportId,
          bookingTitle:
            missing === "band" ? "Private reception" : "(deleted booking)",
          bandName:
            missing === "opportunity" ? "Static Bloom" : "(deleted band)",
        },
      ]);
    },
  );

  test("returns clear errors for a missing booking or report", async () => {
    const f = await setupSafety();
    const { reportId } = await f.report();
    await f.t.run(async (ctx) => {
      await ctx.db.delete(f.bookingId);
      await ctx.db.delete(reportId);
    });
    await expect(f.report()).rejects.toThrow("Booking not found");
    await expect(
      f.as("artist").query(api.safety.mine, { bookingId: f.bookingId }),
    ).rejects.toThrow("Booking not found");
    await expect(
      f.as("platformAdmin").mutation(api.safety.resolve, { reportId }),
    ).rejects.toThrow("Report not found");
  });
});
