/// <reference types="vite/client" />
import type { ApiFromModules, FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi, internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import type * as disputes from "./disputes";
import { DISPUTE_WINDOW_AFTER_COMPLETION_MS } from "./lib/disputeStatus";
import { feeSnapshot } from "./lib/fees";
import { PAYOUT_DELAY_MS } from "./lib/paymentStatus";
import schema from "./schema";

// Keep references typed without editing generated files owned by another lane.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ disputes: typeof disputes }>;
const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-06T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "artist",
  "secondArtist",
  "member",
  "stranger",
  "platformAdmin",
] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("DISPUTES_ENABLED", "true");
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupDisputes(bookingFields: Partial<Doc<"bookings">> = {}) {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `disputes_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `disputes_${actor}`,
        name: actor,
        email: `  ${actor}@disputes.test  `,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Dispute Collective",
      slug: "dispute-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager", "finance", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const privateDetailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "  contact@disputes.test  ",
      contactName: "Organizer",
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: [],
      updatedAt: NOW,
    });
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
      ["secondArtist", "admin"],
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
      title: "Autumn reception",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: NOW - DAY_MS,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW - 2 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "completed",
      slug: "autumn-reception",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 1,
      createdAt: NOW - 2 * DAY_MS,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 10000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.artist,
      status: "booked",
      message: "We are available",
      createdAt: NOW - 2 * DAY_MS,
      updatedAt: NOW,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "completed",
      revision: 3,
      startsAt: NOW - DAY_MS,
      ...feeSnapshot(10000, 1250),
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW - 2 * DAY_MS,
      artistAcceptedTermsAt: NOW - 2 * DAY_MS,
      confirmedAt: NOW - 2 * DAY_MS,
      completedAt: NOW - 60 * 60 * 1000,
      payoutHold: false,
      paidMinor: 10000,
      refundedMinor: 0,
      createdBy: users.owner,
      createdAt: NOW - 2 * DAY_MS,
      updatedAt: NOW,
      ...bookingFields,
    });
    await ctx.db.patch(slotId, { bookingId });
    const paymentRecordId = await ctx.db.insert("paymentRecords", {
      bookingId,
      installmentIndex: 0,
      label: "Full payment",
      amountMinor: 10000,
      currency: "usd",
      dueAt: NOW - 2 * DAY_MS,
      status: "paid",
      stripeChargeId: "ch_dispute",
      stripePaymentIntentId: "pi_dispute",
      attempt: 0,
      paidAt: NOW - 2 * DAY_MS,
      refundedMinor: 0,
      createdAt: NOW - 2 * DAY_MS,
      updatedAt: NOW,
    });
    const payoutId = await ctx.db.insert("payouts", {
      bookingId,
      bandId,
      paymentRecordId,
      sourceChargeId: "ch_dispute",
      kind: "completion",
      amountMinor: 8750,
      currency: "usd",
      status: "scheduled",
      scheduledFor: NOW + PAYOUT_DELAY_MS,
      attempt: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    return {
      users,
      organizationId,
      privateDetailsId,
      bandId,
      bookingId,
      slotId,
      applicationId,
      paymentRecordId,
      payoutId,
    };
  });
  return {
    t,
    as,
    ...ids,
    open: (
      actor: Actor = "owner",
      fields: Partial<FunctionArgs<typeof api.disputes.open>> = {},
    ) =>
      as(actor).mutation(api.disputes.open, {
        bookingId: ids.bookingId,
        category: "late_or_short_set",
        text: "  The performance was shorter than agreed.  ",
        requestedRefundMinor: actor === "artist" ? undefined : 2500,
        ...fields,
      }),
    state: () =>
      t.run(async (ctx) => ({
        booking: (await ctx.db.get(ids.bookingId))!,
        disputes: await ctx.db
          .query("disputes")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .collect(),
        payouts: await ctx.db
          .query("payouts")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .collect(),
        refunds: await ctx.db
          .query("refunds")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .collect(),
        jobs: await ctx.db.system.query("_scheduled_functions").take(100),
      })),
  };
}

describe("disputes.open", () => {
  test.each([undefined, "false", "0"])(
    "refuses when the flag is %s",
    async (flag) => {
      const f = await setupDisputes();
      vi.stubEnv("DISPUTES_ENABLED", flag);
      const before = await f.state();
      await expect(f.open()).rejects.toThrow("Disputes are not available yet");
      expect(await f.state()).toEqual(before);
    },
  );

  test.each(["true", "1"])(
    "opens a refund request and holds the booking/payout with flag %s",
    async (flag) => {
      vi.stubEnv("DISPUTES_ENABLED", flag);
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      const state = await f.state();
      expect(state.booking).toMatchObject({
        status: "disputed",
        disputedFromStatus: "completed",
        payoutHold: true,
        payoutHoldReasons: ["dispute"],
        revision: 4,
      });
      expect(state.disputes).toMatchObject([
        {
          _id: disputeId,
          bookingId: f.bookingId,
          openedByUserId: f.users.owner,
          side: "organizer",
          category: "late_or_short_set",
          text: "The performance was shorter than agreed.",
          requestedRefundMinor: 2500,
          status: "open",
          createdAt: NOW,
          updatedAt: NOW,
        },
      ]);
      expect(state.payouts).toMatchObject([
        {
          _id: f.payoutId,
          status: "held",
          holdReason: "dispute",
        },
      ]);
      expect(state.jobs.map((job) => job.args[0].to).sort()).toEqual([
        "artist@disputes.test",
        "secondArtist@disputes.test",
      ]);
      for (const job of state.jobs) {
        expect(job).toMatchObject({
          name: "emails:send",
          args: [
            {
              kind: "disputeOpened",
              subject: "A dispute was opened on Autumn reception",
            },
          ],
          scheduledTime: NOW,
        });
        expect(job.args[0].text).toContain("Category: late or short set.");
        expect(job.args[0].text).toContain("Requested refund: 25.00 USD");
        expect(job.args[0].text).toContain("Private event");
        expect(job.args[0].text).not.toContain("200 Private Street");
      }
    },
  );

  test("an artist opens without an amount and emails the organizer contact", async () => {
    const f = await setupDisputes();
    await f.open("artist", { category: "payment" });
    const state = await f.state();
    expect(state.disputes[0].side).toBe("artist");
    expect(state.disputes[0].requestedRefundMinor).toBeUndefined();
    expect(state.jobs).toHaveLength(1);
    expect(state.jobs[0].args[0]).toMatchObject({
      kind: "disputeOpened",
      to: "contact@disputes.test",
    });
    expect(state.jobs[0].args[0].text).toContain("Category: payment.");
    expect(state.jobs[0].args[0].text).not.toContain("Requested refund:");
  });

  test.each(["owner", "manager", "finance"] as const)(
    "%s can open as organizer",
    async (actor) => {
      const f = await setupDisputes();
      await f.open(actor);
      expect((await f.state()).disputes[0].side).toBe("organizer");
    },
  );

  test.each(["door", "member", "stranger", "platformAdmin"] as const)(
    "%s cannot open without party access",
    async (actor) => {
      const f = await setupDisputes();
      await expect(f.open(actor)).rejects.toThrow("Not permitted");
      expect((await f.state()).disputes).toEqual([]);
    },
  );

  test.each(["", "  too short  ", "x".repeat(2001)])(
    "rejects text outside the trimmed length limits (case %#)",
    async (text) => {
      const f = await setupDisputes();
      await expect(f.open("owner", { text })).rejects.toThrow(
        "Dispute details must be between 10 and 2000 characters",
      );
    },
  );

  test.each([undefined, 0, -1, 10001, 1.5])(
    "rejects an invalid organizer refund amount %s",
    async (requestedRefundMinor) => {
      const f = await setupDisputes();
      await expect(f.open("owner", { requestedRefundMinor })).rejects.toThrow();
      expect((await f.state()).disputes).toEqual([]);
    },
  );

  test("rejects an artist refund amount", async () => {
    const f = await setupDisputes();
    await expect(f.open("artist", { requestedRefundMinor: 1 })).rejects.toThrow(
      "Artists cannot request a refund",
    );
  });

  test.each(["open", "under_review"] as const)(
    "refuses a second dispute while the first is %s",
    async (status) => {
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      if (status === "under_review") {
        await f
          .as("platformAdmin")
          .mutation(api.disputes.startReview, { disputeId });
      }
      const before = await f.state();
      await expect(f.open("artist")).rejects.toThrow();
      expect(await f.state()).toEqual(before);
    },
  );

  test("checks for active disputes even if the booking is still live", async () => {
    const f = await setupDisputes();
    await f.open();
    await f.t.run((ctx) => ctx.db.patch(f.bookingId, { status: "completed" }));
    await expect(f.open()).rejects.toThrow(
      "This booking already has an open dispute",
    );
  });

  test("a paid payout blocks an organizer refund request but permits an artist dispute", async () => {
    const f = await setupDisputes({ status: "paid" });
    await f.t.run((ctx) => ctx.db.patch(f.payoutId, { status: "paid" }));
    await expect(f.open()).rejects.toThrow(
      "Refund requests close once the artist has been paid",
    );
    await f.open("artist");
    const state = await f.state();
    expect(state.booking).toMatchObject({
      status: "disputed",
      disputedFromStatus: "paid",
    });
    expect(state.payouts[0].status).toBe("paid");
  });

  test.each([
    {
      fields: { startsAt: NOW + 1 },
      reason: "Disputes can only be opened after the show starts",
    },
    {
      fields: { completedAt: NOW - DISPUTE_WINDOW_AFTER_COMPLETION_MS - 1 },
      reason: "The dispute window has closed",
    },
    {
      fields: { grossMinor: 0 },
      reason: "Disputes require a booking with a positive fee",
    },
    {
      fields: { paidMinor: undefined },
      reason:
        "The refund amount must be positive and no more than the amount paid",
    },
    {
      fields: { status: "refunded" as const },
      reason:
        "Disputes can only be opened for confirmed, completed, or paid bookings",
    },
  ])(
    "passes booking eligibility failures through: $reason",
    async ({ fields, reason }) => {
      const f = await setupDisputes(fields);
      await expect(f.open()).rejects.toThrow(reason);
    },
  );

  test("refuses an open Stripe dispute on any installment", async () => {
    const f = await setupDisputes();
    await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...record } = (await ctx.db.get(
        f.paymentRecordId,
      ))!;
      await ctx.db.insert("paymentRecords", {
        ...record,
        installmentIndex: 1,
        stripeDisputeStatus: "open",
      });
    });
    await expect(f.open()).rejects.toThrow(
      "This booking already has an open Stripe dispute",
    );
  });

  test.each(["missing", "blank"])(
    "uses owner email when the contact is %s",
    async (contact) => {
      const f = await setupDisputes();
      await f.t.run(async (ctx) => {
        if (contact === "missing") await ctx.db.delete(f.privateDetailsId);
        else await ctx.db.patch(f.privateDetailsId, { businessEmail: "  " });
      });
      await f.open("artist");
      expect((await f.state()).jobs.map((job) => job.args[0].to)).toEqual([
        "owner@disputes.test",
      ]);
    },
  );

  test("skips empty artist emails", async () => {
    const f = await setupDisputes();
    await f.t.run((ctx) => ctx.db.patch(f.users.secondArtist, { email: "  " }));
    await f.open();
    expect((await f.state()).jobs.map((job) => job.args[0].to)).toEqual([
      "artist@disputes.test",
    ]);
  });
});

describe("disputes.open side selection", () => {
  async function setupDualRoleDisputes() {
    const f = await setupDisputes();
    await f.t.run((ctx) =>
      ctx.db.insert("bandMembers", {
        bandId: f.bandId,
        userId: f.users.owner,
        role: "admin",
      }),
    );
    return f;
  }

  test("an owner who is also a band admin can request a refund as organizer", async () => {
    const f = await setupDualRoleDisputes();
    const { disputeId } = await f.open("owner", {
      side: "organizer",
      requestedRefundMinor: 2500,
    });
    const state = await f.state();
    expect(state.disputes).toMatchObject([
      {
        _id: disputeId,
        openedByUserId: f.users.owner,
        side: "organizer",
        requestedRefundMinor: 2500,
        status: "open",
      },
    ]);
    expect(state.jobs.map((job) => job.args[0].to).sort()).toEqual([
      "artist@disputes.test",
      "owner@disputes.test",
      "secondArtist@disputes.test",
    ]);
    for (const job of state.jobs) {
      expect(job.args[0].kind).toBe("disputeOpened");
      expect(job.args[0].text).toContain("Requested refund: 25.00 USD");
    }
  });

  test("an owner who is also a band admin can open as artist without an amount", async () => {
    const f = await setupDualRoleDisputes();
    await f.open("owner", { side: "artist", requestedRefundMinor: undefined });
    const state = await f.state();
    expect(state.disputes[0].side).toBe("artist");
    expect(state.disputes[0].requestedRefundMinor).toBeUndefined();
    expect(state.jobs).toHaveLength(1);
    expect(state.jobs[0].args[0]).toMatchObject({
      kind: "disputeOpened",
      to: "contact@disputes.test",
    });
  });

  test.each(["owner", "manager", "finance"] as const)(
    "%s can explicitly select organizer",
    async (actor) => {
      const f = await setupDisputes();
      await f.open(actor, { side: "organizer" });
      expect((await f.state()).disputes[0].side).toBe("organizer");
    },
  );

  test.each([
    ["artist", "organizer"],
    ["owner", "artist"],
    ["door", "organizer"],
    ["member", "artist"],
  ] as const)("%s cannot select %s without permission", async (actor, side) => {
    const f = await setupDisputes();
    const before = await f.state();
    await expect(f.open(actor, { side })).rejects.toThrow(
      `Not permitted to act as ${side} on this booking`,
    );
    expect(await f.state()).toEqual(before);
  });

  test("omitting side still gives band admin priority over organization owner", async () => {
    const f = await setupDualRoleDisputes();
    const before = await f.state();
    await expect(f.open("owner")).rejects.toThrow(
      "Artists cannot request a refund",
    );
    expect(await f.state()).toEqual(before);

    await f.open("owner", { requestedRefundMinor: undefined });
    expect((await f.state()).disputes[0].side).toBe("artist");
  });
});

describe("disputes review and resolution", () => {
  test("only an admin can start review, and review cannot be started twice", async () => {
    const f = await setupDisputes();
    const { disputeId } = await f.open();
    await expect(
      f.as("owner").mutation(api.disputes.startReview, { disputeId }),
    ).rejects.toThrow("Not an EarPlug admin");
    vi.setSystemTime(NOW + 1000);
    await f
      .as("platformAdmin")
      .mutation(api.disputes.startReview, { disputeId });
    expect((await f.state()).disputes[0]).toMatchObject({
      status: "under_review",
      updatedAt: NOW + 1000,
    });
    await expect(
      f.as("platformAdmin").mutation(api.disputes.startReview, { disputeId }),
    ).rejects.toThrow("Dispute cannot go from under_review to under_review");
  });

  test.each(["released", "dismissed"] as const)(
    "%s restores status, reschedules the payout, and emails both sides",
    async (resolution) => {
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      if (resolution === "released") {
        await f
          .as("platformAdmin")
          .mutation(api.disputes.startReview, { disputeId });
      }
      vi.setSystemTime(NOW + 1000);
      const result = await f
        .as("platformAdmin")
        .mutation(api.disputes.resolve, {
          disputeId,
          resolution,
          adminNote: "Both parties have been heard.",
        });
      expect(result).toEqual({ status: "resolved", refundMinor: 0 });
      const state = await f.state();
      expect(state.booking).toMatchObject({
        status: "completed",
        payoutHoldReasons: [],
        payoutHold: false,
        revision: 5,
      });
      expect(state.booking.disputedFromStatus).toBeUndefined();
      expect(state.payouts[0].status).toBe("scheduled");
      expect(state.refunds).toEqual([]);
      expect(
        state.jobs.filter((job) => job.name === "payouts:releasePayout"),
      ).toMatchObject([
        {
          args: [{ payoutId: f.payoutId }],
          scheduledTime: NOW + 1000,
        },
      ]);
      expect(state.disputes[0]).toMatchObject({
        status: "resolved",
        resolution,
        resolvedRefundMinor: 0,
        adminNote: "Both parties have been heard.",
        resolvedBy: f.users.platformAdmin,
        resolvedAt: NOW + 1000,
        updatedAt: NOW + 1000,
      });
      const emails = state.jobs.filter(
        (job) => job.args[0].kind === "disputeResolved",
      );
      expect(emails.map((job) => job.args[0].to).sort()).toEqual([
        "artist@disputes.test",
        "contact@disputes.test",
        "secondArtist@disputes.test",
      ]);
      for (const email of emails) {
        expect(email.args[0].subject).toBe(
          "Dispute resolved on Autumn reception",
        );
        expect(email.args[0].text).toContain(
          resolution === "released" ? "artist payout released" : "dismissed",
        );
        expect(email.args[0].text).toContain("Private event");
        expect(email.args[0].text).not.toContain("200 Private Street");
        expect(email.args[0].text).not.toContain("Refund:");
      }
      await expect(
        f.as("platformAdmin").mutation(api.disputes.resolve, {
          disputeId,
          resolution,
        }),
      ).rejects.toThrow("Dispute cannot go from resolved to resolved");
      expect(await f.state()).toEqual(state);
    },
  );

  test("partial refund restores status and settles the remainder using stored commission", async () => {
    const f = await setupDisputes();
    const { disputeId } = await f.open();
    expect(
      await f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId,
        resolution: "refunded_partial",
        refundMinor: 2000,
      }),
    ).toEqual({ status: "resolved", refundMinor: 2000 });
    const state = await f.state();
    expect(state.booking).toMatchObject({
      status: "completed",
      payoutHold: false,
      refundedMinor: 0,
    });
    expect(state.booking.disputedFromStatus).toBeUndefined();
    expect(state.refunds).toMatchObject([
      {
        bookingId: f.bookingId,
        paymentRecordId: f.paymentRecordId,
        amountMinor: 2000,
        currency: "usd",
        reason: "dispute",
        status: "pending",
      },
    ]);
    expect(state.payouts).toMatchObject([
      { _id: f.payoutId, status: "reversed" },
      { kind: "forfeit", status: "scheduled", amountMinor: 7000 },
    ]);
    expect(state.jobs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          name: "refunds:executeRefund",
          args: [{ refundId: state.refunds[0]._id, attempt: 0 }],
        }),
        expect.objectContaining({
          name: "payouts:releasePayout",
          args: [{ payoutId: state.payouts[1]._id }],
        }),
      ]),
    );
    const emails = state.jobs.filter(
      (job) => job.args[0].kind === "disputeResolved",
    );
    expect(emails).toHaveLength(3);
    expect(
      emails.every((job) => job.args[0].text.includes("Refund: 20.00 USD")),
    ).toBe(true);
    expect(state.disputes[0]).toMatchObject({
      status: "resolved",
      resolution: "refunded_partial",
      resolvedRefundMinor: 2000,
    });
  });

  test("completion after a confirmed booking's partial refund keeps only its forfeit payout", async () => {
    const f = await setupDisputes({
      status: "confirmed",
      completedAt: undefined,
    });
    await f.t.run((ctx) => ctx.db.delete(f.payoutId));
    const { disputeId } = await f.open();
    await f.as("platformAdmin").mutation(api.disputes.resolve, {
      disputeId,
      resolution: "refunded_partial",
      refundMinor: 2000,
    });
    const resolved = await f.state();
    expect(resolved.booking.status).toBe("confirmed");
    expect(resolved.booking.completedAt).toBeUndefined();
    expect(resolved.jobs).toContainEqual(
      expect.objectContaining({
        name: "bookings:markCompleted",
        args: [{ bookingId: f.bookingId }],
      }),
    );

    await f.t.mutation(internal.bookings.markCompleted, {
      bookingId: f.bookingId,
    });
    const state = await f.state();
    expect(state.booking).toMatchObject({ status: "completed", completedAt: NOW });
    expect(state.payouts).toHaveLength(1);
    expect(state.payouts).toMatchObject([
      {
        kind: "forfeit",
        paymentRecordId: f.paymentRecordId,
        amountMinor: 7000,
        status: "scheduled",
        scheduledFor: NOW + PAYOUT_DELAY_MS,
      },
    ]);
    expect(state.payouts).toEqual(resolved.payouts);
    const ledger = await f.t.run((ctx) =>
      ctx.db
        .query("ledgerEntries")
        .withIndex("by_bookingId", (q) => q.eq("bookingId", f.bookingId))
        .collect(),
    );
    expect(ledger.filter((row) => row.kind === "commission")).toMatchObject([
      {
        idempotencyKey: `forfeit-commission:${state.refunds[0]._id}`,
        amountMinor: 1000,
      },
    ]);
  });

  test("partial settlement without a prior payout creates only the forfeit and preserves admin and installment holds", async () => {
    const f = await setupDisputes({
      payoutHoldReasons: ["admin", "unpaid_installment"],
      payoutHold: true,
    });
    await f.t.run((ctx) => ctx.db.delete(f.payoutId));
    const { disputeId } = await f.open();
    await f.as("platformAdmin").mutation(api.disputes.resolve, {
      disputeId,
      resolution: "refunded_partial",
      refundMinor: 2000,
    });
    const state = await f.state();
    // Partial dispute refunds keep the booking live, so the unpaid balance is still owed.
    expect(state.booking).toMatchObject({
      status: "completed",
      payoutHoldReasons: ["admin", "unpaid_installment"],
      payoutHold: true,
    });
    expect(state.payouts).toMatchObject([
      {
        kind: "forfeit",
        paymentRecordId: f.paymentRecordId,
        amountMinor: 7000,
        originalAmountMinor: 7000,
        refundBaselineMinor: 2000,
      },
    ]);
  });

  test.each([false, true])(
    "full refund preserves other holds (%s) and keeps the slot/application booked",
    async (adminHold) => {
      const f = await setupDisputes({
        payoutHoldReasons: adminHold ? ["admin"] : [],
        payoutHold: adminHold,
        cancelledByUserId: undefined,
      });
      // A historical actor must be cleared when the admin resolves the booking.
      await f.t.run((ctx) =>
        ctx.db.patch(f.bookingId, { cancelledByUserId: f.users.owner }),
      );
      const { disputeId } = await f.open();
      expect(
        await f.as("platformAdmin").mutation(api.disputes.resolve, {
          disputeId,
          resolution: "refunded_full",
        }),
      ).toEqual({ status: "resolved", refundMinor: 10000 });
      const state = await f.state();
      expect(state.booking).toMatchObject({
        status: "refunded",
        revision: 5,
        cancelledBy: "admin",
        cancelledAt: NOW,
        cancelReason: "Dispute resolved: full refund",
        payoutHoldReasons: adminHold ? ["admin"] : [],
        payoutHold: adminHold,
      });
      expect(state.booking.cancelledByUserId).toBeUndefined();
      expect(state.booking.disputedFromStatus).toBeUndefined();
      expect(state.refunds).toMatchObject([
        { amountMinor: 10000, reason: "dispute", status: "pending" },
      ]);
      expect(state.payouts).toMatchObject([
        { _id: f.payoutId, status: "reversed" },
      ]);
      expect(
        state.jobs.filter((job) => job.name === "payouts:releasePayout"),
      ).toEqual([]);
      expect(await f.t.run((ctx) => ctx.db.get(f.slotId))).toMatchObject({
        status: "booked",
        bookingId: f.bookingId,
      });
      expect(await f.t.run((ctx) => ctx.db.get(f.applicationId))).toMatchObject(
        { status: "booked" },
      );
      const emails = state.jobs.filter(
        (job) => job.args[0].kind === "disputeResolved",
      );
      expect(emails).toHaveLength(3);
      expect(
        emails.every((job) => job.args[0].text.includes("Refund: 100.00 USD")),
      ).toBe(true);
    },
  );

  test("full refund reports and emails the remaining refundable amount across installments", async () => {
    const f = await setupDisputes({ refundedMinor: 3000 });
    await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...record } = (await ctx.db.get(
        f.paymentRecordId,
      ))!;
      await ctx.db.patch(f.paymentRecordId, {
        amountMinor: 4000,
        refundedMinor: 1000,
      });
      await ctx.db.insert("paymentRecords", {
        ...record,
        installmentIndex: 1,
        amountMinor: 6000,
        refundedMinor: 2000,
        stripeChargeId: "ch_dispute_second",
        stripePaymentIntentId: "pi_dispute_second",
      });
      const { _id: bookingId, _creationTime: bookingCreatedAt, ...booking } =
        (await ctx.db.get(f.bookingId))!;
      const otherBookingId = await ctx.db.insert("bookings", booking);
      await ctx.db.insert("paymentRecords", {
        ...record,
        bookingId: otherBookingId,
      });
    });
    const { disputeId } = await f.open();

    expect(
      await f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId,
        resolution: "refunded_full",
      }),
    ).toEqual({ status: "resolved", refundMinor: 7000 });
    const state = await f.state();
    expect(state.disputes[0]).toMatchObject({
      status: "resolved",
      resolution: "refunded_full",
      resolvedRefundMinor: 7000,
    });
    const emails = state.jobs.filter(
      (job) => job.args[0].kind === "disputeResolved",
    );
    expect(emails).toHaveLength(3);
    for (const email of emails) {
      expect(email.args[0].text).toContain("Refund: 70.00 USD");
      expect(email.args[0].text).not.toContain("Refund: 100.00 USD");
    }
  });

  test("refund resolutions count only the paid installment and full refunds release its balance hold", async () => {
    const f = await setupDisputes({
      paidMinor: 4000,
      payoutHold: true,
      payoutHoldReasons: ["unpaid_installment"],
    });
    const pendingRecordId = await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...record } = (await ctx.db.get(
        f.paymentRecordId,
      ))!;
      await ctx.db.patch(f.paymentRecordId, { amountMinor: 4000 });
      await ctx.db.patch(f.payoutId, { amountMinor: 3500 });
      return await ctx.db.insert("paymentRecords", {
        ...record,
        installmentIndex: 1,
        label: "Remaining balance",
        amountMinor: 6000,
        status: "pending",
        paidAt: undefined,
        stripeChargeId: undefined,
        stripePaymentIntentId: undefined,
      });
    });
    const { disputeId } = await f.open();
    const before = await f.state();
    await expect(
      f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId,
        resolution: "refunded_partial",
        refundMinor: 5000,
      }),
    ).rejects.toThrow(
      "A partial refund must be a positive whole number in minor units below the amount paid",
    );
    expect(await f.state()).toEqual(before);

    expect(
      await f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId,
        resolution: "refunded_full",
      }),
    ).toEqual({ status: "resolved", refundMinor: 4000 });
    const state = await f.state();
    expect(state.booking).toMatchObject({
      status: "refunded",
      payoutHoldReasons: [],
      payoutHold: false,
    });
    expect(state.refunds).toMatchObject([
      {
        paymentRecordId: f.paymentRecordId,
        amountMinor: 4000,
        status: "pending",
      },
    ]);
    expect(state.disputes[0].resolvedRefundMinor).toBe(4000);
    expect(await f.t.run((ctx) => ctx.db.get(pendingRecordId))).toMatchObject({
      status: "pending",
      refundedMinor: 0,
    });
  });

  test("full refund rejects a booking whose payments are already fully refunded", async () => {
    const f = await setupDisputes({ refundedMinor: 10000 });
    await f.t.run((ctx) =>
      ctx.db.patch(f.paymentRecordId, { refundedMinor: 10000 }),
    );
    const { disputeId } = await f.open();
    const before = await f.state();

    await expect(
      f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId,
        resolution: "refunded_full",
      }),
    ).rejects.toThrow("A full refund requires a positive amount paid");
    expect(await f.state()).toEqual(before);
  });

  test("partial refund cannot reach or exceed the remaining refundable amount", async () => {
    const f = await setupDisputes({ refundedMinor: 3000 });
    await f.t.run((ctx) =>
      ctx.db.patch(f.paymentRecordId, { refundedMinor: 3000 }),
    );
    const { disputeId } = await f.open();
    const before = await f.state();

    for (const refundMinor of [7000, 8000]) {
      await expect(
        f.as("platformAdmin").mutation(api.disputes.resolve, {
          disputeId,
          resolution: "refunded_partial",
          refundMinor,
        }),
      ).rejects.toThrow(
        "A partial refund must be a positive whole number in minor units below the amount paid",
      );
      expect(await f.state()).toEqual(before);
    }
  });

  test("an artist's partial refund after payout uses the existing transfer reversal pipeline", async () => {
    const f = await setupDisputes({ status: "paid" });
    await f.t.run((ctx) =>
      ctx.db.patch(f.payoutId, {
        status: "paid",
        stripeTransferId: "tr_dispute",
      }),
    );
    const { disputeId } = await f.open("artist");
    await f.as("platformAdmin").mutation(api.disputes.resolve, {
      disputeId,
      resolution: "refunded_partial",
      refundMinor: 2000,
    });
    const state = await f.state();
    expect(state.booking.status).toBe("paid");
    expect(state.payouts).toMatchObject([{ _id: f.payoutId, status: "paid" }]);
    await f.t.mutation(internal.refunds.markRefundSucceeded, {
      refundId: state.refunds[0]._id,
      stripeRefundId: "re_dispute",
    });
    expect((await f.state()).jobs).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          name: "refunds:reverseTransfer",
          args: [
            { payoutId: f.payoutId, reversalMinor: 1750, reversedMinor: 1750 },
          ],
        }),
      ]),
    );
  });

  test.each([
    "released",
    "dismissed",
    "refunded_full",
    "refunded_partial",
  ] as const)(
    "refuses %s while any installment has an open Stripe dispute",
    async (resolution) => {
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      await f.t.run(async (ctx) => {
        const { _id, _creationTime, ...record } = (await ctx.db.get(
          f.paymentRecordId,
        ))!;
        await ctx.db.insert("paymentRecords", {
          ...record,
          installmentIndex: 1,
          stripeDisputeStatus: "open",
        });
      });
      const before = await f.state();
      await expect(
        f.as("platformAdmin").mutation(api.disputes.resolve, {
          disputeId,
          resolution,
          refundMinor: resolution === "refunded_partial" ? 2000 : undefined,
        }),
      ).rejects.toThrow(
        "Disputes cannot be resolved while a Stripe dispute is open",
      );
      expect(await f.state()).toEqual(before);
    },
  );

  test.each(["owner", "artist", "stranger"] as const)(
    "%s cannot resolve",
    async (actor) => {
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      await expect(
        f.as(actor).mutation(api.disputes.resolve, {
          disputeId,
          resolution: "refunded_full",
        }),
      ).rejects.toThrow("Not an EarPlug admin");
    },
  );

  test.each([undefined, 0, -1, 1.5, 10000, 10001])(
    "rejects partial refund %s without changing state",
    async (refundMinor) => {
      const f = await setupDisputes();
      const { disputeId } = await f.open();
      const before = await f.state();
      await expect(
        f.as("platformAdmin").mutation(api.disputes.resolve, {
          disputeId,
          resolution: "refunded_partial",
          refundMinor,
        }),
      ).rejects.toThrow(
        "A partial refund must be a positive whole number in minor units below the amount paid",
      );
      expect(await f.state()).toEqual(before);
    },
  );

  test("resolution emails deduplicate recipients shared by both parties", async () => {
    const f = await setupDisputes();
    await f.t.run((ctx) =>
      ctx.db.patch(f.privateDetailsId, {
        businessEmail: " artist@disputes.test ",
      }),
    );
    const { disputeId } = await f.open("artist");
    await f
      .as("platformAdmin")
      .mutation(api.disputes.resolve, { disputeId, resolution: "dismissed" });
    const emails = (await f.state()).jobs.filter(
      (job) => job.args[0].kind === "disputeResolved",
    );
    expect(emails.map((job) => job.args[0].to).sort()).toEqual([
      "artist@disputes.test",
      "secondArtist@disputes.test",
    ]);
  });
});

describe("disputes queries", () => {
  test.each([
    "owner",
    "manager",
    "finance",
    "artist",
    "platformAdmin",
  ] as const)(
    "%s reads booking disputes newest first with notes only after resolution",
    async (actor) => {
      const f = await setupDisputes();
      const first = await f.open();
      await f.as("platformAdmin").mutation(api.disputes.resolve, {
        disputeId: first.disputeId,
        resolution: "released",
        adminNote: "Reviewed with both parties.",
      });
      vi.setSystemTime(NOW + 1000);
      const second = await f.open("artist");
      await f.t.run((ctx) =>
        ctx.db.patch(second.disputeId, { adminNote: "Unresolved draft note" }),
      );
      const rows = await f
        .as(actor)
        .query(api.disputes.forBooking, { bookingId: f.bookingId });
      expect(rows.map((row) => row.disputeId)).toEqual([
        second.disputeId,
        first.disputeId,
      ]);
      expect(rows[0]).not.toHaveProperty("adminNote");
      expect(rows[1]).toMatchObject({
        bookingId: f.bookingId,
        side: "organizer",
        status: "resolved",
        resolution: "released",
        resolvedRefundMinor: 0,
        adminNote: "Reviewed with both parties.",
        resolvedAt: NOW,
      });
      expect(rows[0]).not.toHaveProperty("_creationTime");
      expect(rows[0]).not.toHaveProperty("openedByUserId");
      expect(rows[1]).not.toHaveProperty("resolvedBy");
    },
  );

  test.each(["stranger", "door", "member"] as const)(
    "%s sees no booking disputes instead of an error",
    async (actor) => {
      const f = await setupDisputes();
      await f.open();
      // The booking page loads disputes for every live booking; viewers who
      // are not a party get an empty list rather than a logged failure.
      expect(
        await f
          .as(actor)
          .query(api.disputes.forBooking, { bookingId: f.bookingId }),
      ).toEqual([]);
    },
  );

  test("forBooking returns only the 50 newest disputes", async () => {
    const f = await setupDisputes();
    const disputeIds = await f.t.run(async (ctx) => {
      const ids = [];
      for (let index = 0; index < 52; index++) {
        ids.push(
          await ctx.db.insert("disputes", {
            bookingId: f.bookingId,
            openedByUserId: f.users.owner,
            side: "organizer",
            category: "payment",
            text: `Historical dispute ${index}`,
            status: "resolved",
            resolution: "dismissed",
            createdAt: NOW + index,
            updatedAt: NOW + index,
          }),
        );
      }
      return ids;
    });

    const rows = await f.as("owner").query(api.disputes.forBooking, {
      bookingId: f.bookingId,
    });
    expect(rows.map((row) => row.disputeId)).toEqual(
      disputeIds.reverse().slice(0, 50),
    );
  });

  test("listOpen paginates open rows and appends under-review rows only on the first page", async () => {
    const f = await setupDisputes();
    const first = await f.open();
    vi.setSystemTime(NOW + 1000);
    const { newestId, underReviewId, newestUnderReviewId } = await f.t.run(async (ctx) => {
      const { _id, _creationTime, ...dispute } = (await ctx.db.get(
        first.disputeId,
      ))!;
      const newestUnderReviewId = await ctx.db.insert("disputes", {
        ...dispute,
        status: "under_review",
        createdAt: NOW + 4000,
      });
      const underReviewId = await ctx.db.insert("disputes", {
        ...dispute,
        status: "under_review",
        createdAt: NOW + 2000,
      });
      await ctx.db.insert("disputes", {
        ...dispute,
        status: "resolved",
        createdAt: NOW + 3000,
      });
      const newestId = await ctx.db.insert("disputes", {
        ...dispute,
        createdAt: NOW + 1000,
      });
      return { newestId, underReviewId, newestUnderReviewId };
    });
    const admin = f.as("platformAdmin");
    const firstPage = await admin.query(api.disputes.listOpen, {
      paginationOpts: { numItems: 1, cursor: null },
    });
    expect(firstPage.isDone).toBe(false);
    expect(firstPage.page).toMatchObject([
      {
        disputeId: newestId,
        bookingTitle: "Autumn reception",
        organizationName: "Dispute Collective",
        bandName: "Static Bloom",
        paidMinor: 10000,
        bookingStatus: "disputed",
      },
      { disputeId: newestUnderReviewId, status: "under_review" },
      { disputeId: underReviewId, status: "under_review" },
    ]);
    expect(firstPage.page[0]).not.toHaveProperty("_creationTime");
    const secondPage = await admin.query(api.disputes.listOpen, {
      paginationOpts: { numItems: 1, cursor: firstPage.continueCursor },
    });
    expect(secondPage.isDone).toBe(true);
    expect(secondPage.page.map((row) => row.disputeId)).toEqual([
      first.disputeId,
    ]);
    await f.t.run((ctx) => ctx.db.patch(f.bookingId, { paidMinor: undefined }));
    const withoutPaidMinor = await admin.query(api.disputes.listOpen, {
      paginationOpts: { numItems: 1, cursor: null },
    });
    expect(withoutPaidMinor.page[0].paidMinor).toBe(0);
  });

  test("listOpen keeps a dispute visible when review leaves no open rows", async () => {
    const f = await setupDisputes();
    const { disputeId } = await f.open();
    const admin = f.as("platformAdmin");
    await admin.mutation(api.disputes.startReview, { disputeId });

    const result = await admin.query(api.disputes.listOpen, {
      paginationOpts: { numItems: 1, cursor: null },
    });
    expect(result.isDone).toBe(true);
    expect(result.page).toMatchObject([{ disputeId, status: "under_review" }]);
  });

  test("listOpen preserves the placeholder for a deleted booking", async () => {
    const f = await setupDisputes();
    const { disputeId } = await f.open();
    await f.t.run((ctx) => ctx.db.delete(f.bookingId));

    const result = await f.as("platformAdmin").query(api.disputes.listOpen, {
      paginationOpts: { numItems: 1, cursor: null },
    });
    expect(result.page).toMatchObject([
      {
        disputeId,
        bookingTitle: "(deleted booking)",
        bookingStatus: "(deleted booking)",
      },
    ]);
  });

  test.each(["owner", "artist", "stranger"] as const)(
    "listOpen refuses %s",
    async (actor) => {
      const f = await setupDisputes();
      await expect(
        f.as(actor).query(api.disputes.listOpen, {
          paginationOpts: { numItems: 10, cursor: null },
        }),
      ).rejects.toThrow("Not an EarPlug admin");
    },
  );
});
