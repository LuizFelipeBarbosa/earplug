/// <reference types="vite/client" />
import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  api as generatedApi,
  internal as generatedInternal,
} from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import { COMPLETION_DELAY_MS, REVIEW_WINDOW_MS } from "./lib/bookingStatus";
import {
  HELD_PAYOUT_MAX_DAYS,
  HELD_PAYOUT_RETRY_MS,
  PAYOUT_DELAY_MS,
} from "./lib/paymentStatus";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import type * as payouts from "./payouts";
import schema from "./schema";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const api = generatedApi as typeof generatedApi &
  FilterApi<
    ApiFromModules<{ payouts: typeof payouts }>,
    FunctionReference<"query" | "mutation" | "action", "public">
  >;
const internal = generatedInternal as typeof generatedInternal &
  FilterApi<
    ApiFromModules<{ payouts: typeof payouts }>,
    FunctionReference<"query" | "mutation" | "action", "internal">
  >;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTORS = [
  "owner",
  "admin",
  "member",
  "platformAdmin",
  "stranger",
] as const;
type Actor = (typeof ACTORS)[number];
const stripeMock = vi.mocked(stripeRequest);

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  vi.stubEnv("RESEND_SEND_ENABLED", "false");
  vi.stubEnv("APP_BASE_URL", "https://earplug.test");
  stripeMock.mockReset();
  stripeMock.mockImplementation(async (method, path) => {
    if (method === "POST" && path === "/v1/transfers")
      return { id: "tr_test_1" };
    throw new Error(`Unexpected Stripe request: ${method} ${path}`);
  });
  vi.spyOn(console, "log").mockImplementation(() => {});
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupPayouts(amounts = [15000]) {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `payout_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `payout_${actor}`,
        name: actor,
        email: `${actor}@payout.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Payout Collective",
      slug: "payout-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    await ctx.db.insert("organizationMembers", {
      organizationId,
      userId: users.owner,
      role: "owner",
      createdAt: NOW,
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
    for (const role of ["admin", "member"] as const) {
      await ctx.db.insert("bandMembers", { bandId, userId: users[role], role });
    }
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      managedByOrganizationId: organizationId,
      status: "verified",
      venueType: "hall",
    });
    const startsAt = NOW - COMPLETION_DELAY_MS - 1000;
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      venueId,
      mode: "publicEvent",
      area: "Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: startsAt - DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "confirmed",
      slug: "friday-at-the-hall",
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
      guaranteeMinor: 15000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.admin,
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
      startsAt,
      grossMinor: 15000,
      commissionBps: 1000,
      commissionMinor: 1500,
      artistNetMinor: 13500,
      currency: "usd",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: startsAt - DAY_MS,
      artistAcceptedTermsAt: startsAt - DAY_MS,
      confirmedAt: startsAt - DAY_MS,
      payoutHold: false,
      createdBy: users.owner,
      createdAt: startsAt - DAY_MS,
      updatedAt: NOW,
    });
    await ctx.db.patch(slotId, { bookingId });
    const paymentRecordIds: Id<"paymentRecords">[] = [];
    for (const [index, amountMinor] of amounts.entries()) {
      paymentRecordIds.push(
        await ctx.db.insert("paymentRecords", {
          bookingId,
          installmentIndex: index,
          label: `Installment ${index + 1}`,
          amountMinor,
          currency: "usd",
          dueAt: startsAt - DAY_MS,
          status: "paid",
          stripeChargeId: `ch_test_${index + 1}`,
          stripePaymentIntentId: `pi_test_${index + 1}`,
          attempt: 0,
          paidAt: startsAt - DAY_MS,
          refundedMinor: 0,
          createdAt: startsAt - DAY_MS,
          updatedAt: NOW,
        }),
      );
    }
    return {
      users,
      organizationId,
      bandId,
      opportunityId,
      bookingId,
      paymentRecordIds,
    };
  });
  return {
    t,
    as,
    ...ids,
    complete: () =>
      t.mutation(internal.bookings.markCompleted, { bookingId: ids.bookingId }),
    addAccount: (payoutsEnabled = true) =>
      t.run((ctx) =>
        ctx.db.insert("bandPayoutAccounts", {
          bandId: ids.bandId,
          stripeAccountId: "acct_band",
          chargesEnabled: true,
          payoutsEnabled,
          detailsSubmitted: true,
          requirementsDue: [],
          updatedAt: NOW,
        }),
      ),
    readBooking: () => t.run((ctx) => ctx.db.get(ids.bookingId)),
    payouts: () =>
      t.run((ctx) =>
        ctx.db
          .query("payouts")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .take(50),
      ),
    ledger: () =>
      t.run((ctx) =>
        ctx.db
          .query("ledgerEntries")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .take(50),
      ),
    scheduled: () =>
      t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
  };
}

describe("completion payout scheduling", () => {
  test("schedules the artist net against the paid charge once", async () => {
    const f = await setupPayouts();
    await f.complete();
    const booking = await f.readBooking();
    const rows = await f.payouts();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      bookingId: f.bookingId,
      bandId: f.bandId,
      kind: "completion",
      amountMinor: 13500,
      currency: "usd",
      status: "scheduled",
      scheduledFor: booking!.completedAt! + PAYOUT_DELAY_MS,
      attempt: 0,
      paymentRecordId: f.paymentRecordIds[0],
      sourceChargeId: "ch_test_1",
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(rows[0].stripeAccountId).toBeUndefined();
    expect(booking).toMatchObject({
      status: "completed",
      revision: 4,
      completedAt: NOW,
    });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "payouts:releasePayout",
        args: [{ payoutId: rows[0]._id }],
        scheduledTime: NOW + PAYOUT_DELAY_MS,
      }),
    );
    await f.complete();
    expect(await f.payouts()).toEqual(rows);
  });

  test.each([
    { amounts: [9000, 6000], shares: [8100, 5400] },
    { amounts: [5005, 5005, 4990], shares: [4505, 4505, 4490] },
  ])(
    "allocates $amounts with the rounding remainder on the last charge",
    async ({ amounts, shares }) => {
      const f = await setupPayouts(amounts);
      await f.complete();
      const rows = await f.payouts();
      expect(rows).toHaveLength(amounts.length);
      expect(
        f.paymentRecordIds.map(
          (id) => rows.find((row) => row.paymentRecordId === id)?.amountMinor,
        ),
      ).toEqual(shares);
      expect(rows.reduce((sum, row) => sum + row.amountMinor, 0)).toBe(13500);
    },
  );

  test("creates no payouts when no payment has been paid", async () => {
    const f = await setupPayouts();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[0], { status: "pending" });
      await ctx.db.patch(f.bookingId, {
        payoutHold: true,
        payoutHoldReasons: ["unpaid_installment"],
      });
    });
    await f.complete();
    expect(await f.payouts()).toEqual([]);
    expect(await f.readBooking()).toMatchObject({ status: "completed" });
  });

  test("only schedules paid installments and holds them while another is unpaid", async () => {
    const f = await setupPayouts([9000, 6000]);
    await f.addAccount();
    await f.t.run(async (ctx) => {
      await ctx.db.patch(f.paymentRecordIds[1], { status: "pending" });
      await ctx.db.patch(f.bookingId, {
        payoutHold: true,
        payoutHoldReasons: ["unpaid_installment"],
      });
    });
    await f.complete();
    const [payout] = await f.payouts();
    expect(await f.payouts()).toHaveLength(1);
    expect(payout).toMatchObject({
      amountMinor: 13500,
      paymentRecordId: f.paymentRecordIds[0],
    });
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    expect((await f.payouts())[0]).toMatchObject({
      status: "held",
      holdReason: "unpaid_installment",
    });
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("zero-fee bookings become paid immediately and retain review side effects", async () => {
    const f = await setupPayouts([]);
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        grossMinor: 0,
        commissionMinor: 0,
        artistNetMinor: 0,
      }),
    );
    await f.complete();
    expect(await f.payouts()).toEqual([]);
    expect(await f.readBooking()).toMatchObject({
      status: "paid",
      revision: 5,
      completedAt: NOW,
      updatedAt: NOW,
    });
    expect(await f.t.run((ctx) => ctx.db.get(f.opportunityId))).toMatchObject({
      status: "completed",
    });
    const jobs = await f.scheduled();
    expect(jobs).toContainEqual(
      expect.objectContaining({
        name: "reviews:closeReviewWindow",
        args: [{ bookingId: f.bookingId }],
        scheduledTime: NOW + REVIEW_WINDOW_MS,
      }),
    );
    expect(
      jobs
        .filter((job) => job.name === "emails:send")
        .map((job) => job.args[0].kind),
    ).toEqual(["reviewRequested", "reviewRequested"]);
    for (const subjectId of [f.bandId, f.organizationId]) {
      expect(await f.t.run((ctx) => ctx.db.get(subjectId))).toMatchObject({
        reviewSummary: { completedBookings: 1 },
      });
    }
    await f.complete();
    expect((await f.readBooking())?.revision).toBe(5);
    expect(await f.scheduled()).toEqual(jobs);
  });
});

describe("payout release and holds", () => {
  test("a ready account starts processing and schedules execution once", async () => {
    const f = await setupPayouts();
    await f.addAccount();
    await f.complete();
    const [payout] = await f.payouts();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    expect((await f.payouts())[0]).toMatchObject({ status: "processing" });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "payouts:executePayout",
        args: [{ payoutId: payout._id, attempt: 0 }],
        scheduledTime: NOW,
      }),
    );
    const jobs = await f.scheduled();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    expect(await f.scheduled()).toEqual(jobs);
  });

  test.each([
    { reasons: ["dispute"], expected: "dispute" },
    {
      reasons: ["admin", "unpaid_installment", "dispute"],
      expected: "dispute",
    },
    {
      reasons: ["admin", "unpaid_installment"],
      expected: "unpaid_installment",
    },
    { reasons: ["admin"], expected: "admin" },
  ] satisfies {
    reasons: Doc<"bookings">["payoutHoldReasons"];
    expected: string;
  }[])("respects hold priority for $reasons", async ({ reasons, expected }) => {
    const f = await setupPayouts();
    await f.addAccount();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        payoutHold: true,
        payoutHoldReasons: reasons,
      }),
    );
    await f.complete();
    const [payout] = await f.payouts();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    expect((await f.payouts())[0]).toMatchObject({
      status: "held",
      holdReason: expected,
      attempt: 1,
    });
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payouts:executePayout",
      ),
    ).toEqual([]);
    expect(
      (await f.scheduled()).filter(
        (job) =>
          job.name === "emails:send" &&
          job.args[0].subject === "Payout on hold",
      ),
    ).toEqual([]);
  });

  test.each(["missing", "disabled"])(
    "a %s account holds, retries, and emails only band admins once",
    async (account) => {
      const f = await setupPayouts();
      if (account === "disabled") await f.addAccount(false);
      await f.complete();
      const [payout] = await f.payouts();
      vi.setSystemTime(NOW + PAYOUT_DELAY_MS);
      await f.t.mutation(internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
      expect((await f.payouts())[0]).toMatchObject({
        status: "held",
        holdReason: "no_payout_account",
        attempt: 1,
        scheduledFor: Date.now() + HELD_PAYOUT_RETRY_MS,
      });
      expect(await f.scheduled()).toContainEqual(
        expect.objectContaining({
          name: "payouts:releasePayout",
          args: [{ payoutId: payout._id }],
          scheduledTime: Date.now() + HELD_PAYOUT_RETRY_MS,
        }),
      );
      vi.setSystemTime(Date.now() + HELD_PAYOUT_RETRY_MS);
      await f.t.mutation(internal.payouts.retryHeldPayouts, {});
      expect((await f.payouts())[0]).toMatchObject({
        status: "held",
        attempt: 2,
      });
      const emails = (await f.scheduled()).filter(
        (job) =>
          job.name === "emails:send" &&
          job.args[0].subject === "Payout on hold",
      );
      expect(emails).toHaveLength(1);
      expect(emails[0].args).toEqual([
        {
          kind: "bookingConfirmed",
          to: "admin@payout.test",
          subject: "Payout on hold",
          text: expect.stringContaining(f.bookingId),
        },
      ]);
      expect(emails[0].args[0].text).toContain("Stripe Express");
    },
  );

  test("stops scheduling held retries at the maximum age", async () => {
    const f = await setupPayouts();
    await f.complete();
    const [payout] = await f.payouts();
    vi.setSystemTime(NOW + HELD_PAYOUT_MAX_DAYS * DAY_MS - 1);
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    const held = (await f.payouts())[0];
    const jobs = await f.scheduled();
    vi.setSystemTime(NOW + HELD_PAYOUT_MAX_DAYS * DAY_MS);
    await f.t.mutation(internal.payouts.retryHeldPayouts, {});
    expect((await f.payouts())[0]).toMatchObject({
      status: "held",
      attempt: 2,
      scheduledFor: held.scheduledFor,
    });
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("the cron releases an existing hold once setup and booking holds are resolved", async () => {
    const f = await setupPayouts();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, {
        payoutHold: true,
        payoutHoldReasons: ["admin"],
      }),
    );
    await f.complete();
    const [payout] = await f.payouts();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    await f.addAccount();
    await f.t.run((ctx) =>
      ctx.db.patch(f.bookingId, { payoutHold: false, payoutHoldReasons: [] }),
    );
    await f.t.mutation(internal.payouts.retryHeldPayouts, {});
    expect((await f.payouts())[0]).toMatchObject({ status: "processing" });
    await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());
    expect((await f.payouts())[0]).toMatchObject({ status: "paid" });
    expect(stripeMock).toHaveBeenCalledTimes(1);
    expect(stripeMock.mock.calls[0][3]).toEqual({
      idempotencyKey: stripeIdempotencyKey("payout", payout._id, 1),
    });
  });
});

describe("Stripe execution and settlement", () => {
  test("transfers the net with a source charge and records payout and commission once", async () => {
    const f = await setupPayouts();
    await f.addAccount();
    await f.complete();
    const [payout] = await f.payouts();
    await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "POST",
      "/v1/transfers",
      {
        amount: 13500,
        currency: "usd",
        destination: "acct_band",
        source_transaction: "ch_test_1",
        transfer_group: f.bookingId,
        metadata: {
          bookingId: f.bookingId,
          payoutId: payout._id,
          paymentRecordId: f.paymentRecordIds[0],
        },
      },
      { idempotencyKey: stripeIdempotencyKey("payout", payout._id, 0) },
    );
    const paid = (await f.payouts())[0];
    expect(paid).toMatchObject({
      status: "paid",
      stripeTransferId: "tr_test_1",
    });
    expect(paid.paidAt).toBeTypeOf("number");
    expect(paid.releasedAt).toBe(paid.paidAt);
    const ledger = await f.ledger();
    expect(ledger).toHaveLength(2);
    expect(ledger).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          kind: "payout",
          amountMinor: -13500,
          currency: "usd",
          fundsState: "paid",
          idempotencyKey: "payout:tr_test_1",
          bandId: f.bandId,
          bookingId: f.bookingId,
        }),
        expect.objectContaining({
          kind: "commission",
          amountMinor: 1500,
          currency: "usd",
          fundsState: "available",
          idempotencyKey: `commission:${f.bookingId}`,
          bandId: f.bandId,
          organizationId: f.organizationId,
          bookingId: f.bookingId,
        }),
      ]),
    );
    expect(await f.readBooking()).toMatchObject({
      status: "paid",
      revision: 5,
    });
    expect(console.log).toHaveBeenCalledWith(
      `Booking ${f.bookingId} fully paid out`,
    );
    const jobs = await f.scheduled();
    expect(jobs.filter((job) => job.name === "emails:send")).toHaveLength(2);
    await f.t.mutation(internal.payouts.markPayoutPaid, {
      payoutId: payout._id,
      transferId: "tr_test_1",
    });
    expect(await f.ledger()).toEqual(ledger);
    expect((await f.payouts())[0]).toEqual(paid);
    expect((await f.readBooking())?.revision).toBe(5);
    expect(await f.scheduled()).toEqual(jobs);
  });

  test("settles the booking only after every charge has been paid out", async () => {
    const f = await setupPayouts([9000, 6000]);
    await f.addAccount();
    await f.complete();
    const rows = await f.payouts();
    for (const payout of rows) {
      await f.t.mutation(internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
    }
    await f.t.mutation(internal.payouts.markPayoutPaid, {
      payoutId: rows[0]._id,
      transferId: "tr_first",
    });
    expect(await f.readBooking()).toMatchObject({
      status: "completed",
      revision: 4,
    });
    await f.t.mutation(internal.payouts.markPayoutPaid, {
      payoutId: rows[1]._id,
      transferId: "tr_second",
    });
    expect(await f.readBooking()).toMatchObject({
      status: "paid",
      revision: 5,
    });
    const ledger = await f.ledger();
    expect(ledger.filter((row) => row.kind === "commission")).toHaveLength(1);
    expect(ledger.filter((row) => row.kind === "payout")).toHaveLength(2);
    expect(
      ledger
        .filter((row) => row.kind === "payout")
        .reduce((sum, row) => sum + row.amountMinor, 0),
    ).toBe(-13500);
  });

  test("uses the current account and looks up the charge on the payment intent when needed", async () => {
    const f = await setupPayouts();
    const accountId = await f.addAccount();
    await f.t.run((ctx) =>
      ctx.db.patch(f.paymentRecordIds[0], { stripeChargeId: undefined }),
    );
    await f.complete();
    const [payout] = await f.payouts();
    expect(
      await f.t.query(internal.payouts.loadExecutionContext, {
        payoutId: payout._id,
      }),
    ).toMatchObject({
      payout,
      stripeAccountId: "acct_band",
      fallbackPaymentIntentId: "pi_test_1",
    });
    await f.t.run((ctx) =>
      ctx.db.patch(accountId, { stripeAccountId: "acct_current" }),
    );
    stripeMock
      .mockResolvedValueOnce({ latest_charge: "ch_fallback" })
      .mockResolvedValueOnce({ id: "tr_fallback" });
    await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());
    expect(stripeMock).toHaveBeenNthCalledWith(
      1,
      "GET",
      "/v1/payment_intents/pi_test_1",
    );
    expect(stripeMock).toHaveBeenNthCalledWith(
      2,
      "POST",
      "/v1/transfers",
      expect.objectContaining({
        source_transaction: "ch_fallback",
        destination: "acct_current",
      }),
      { idempotencyKey: stripeIdempotencyKey("payout", payout._id, 0) },
    );
    expect((await f.payouts())[0]).toMatchObject({
      status: "paid",
      stripeTransferId: "tr_fallback",
    });
  });

  test.each(["missing intent", "missing latest charge"])(
    "fails without transferring when there is a %s",
    async (missing) => {
      const f = await setupPayouts();
      await f.addAccount();
      await f.t.run((ctx) =>
        ctx.db.patch(f.paymentRecordIds[0], {
          stripeChargeId: undefined,
          stripePaymentIntentId:
            missing === "missing intent" ? undefined : "pi_test_1",
        }),
      );
      await f.complete();
      const [payout] = await f.payouts();
      await f.t.mutation(internal.payouts.releasePayout, {
        payoutId: payout._id,
      });
      stripeMock.mockResolvedValue({ latest_charge: null });
      await f.t.action(internal.payouts.executePayout, {
        payoutId: payout._id,
        attempt: 0,
      });
      expect((await f.payouts())[0]).toMatchObject({
        status: "scheduled",
        attempt: 1,
        error: expect.stringContaining("No source charge"),
      });
      expect(
        stripeMock.mock.calls.filter(([, path]) => path === "/v1/transfers"),
      ).toEqual([]);
      expect(stripeMock).toHaveBeenCalledTimes(
        missing === "missing intent" ? 0 : 1,
      );
      expect(await f.ledger()).toEqual([]);
    },
  );

  test("a transfer failure records the error and schedules the next attempt", async () => {
    const f = await setupPayouts();
    await f.addAccount();
    await f.complete();
    const [payout] = await f.payouts();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    stripeMock.mockRejectedValueOnce(
      new StripeApiError("Transfer unavailable", { status: 503 }),
    );
    vi.setSystemTime(NOW + PAYOUT_DELAY_MS);
    await f.t.action(internal.payouts.executePayout, {
      payoutId: payout._id,
      attempt: 0,
    });
    expect((await f.payouts())[0]).toMatchObject({
      status: "scheduled",
      error: "Transfer unavailable",
      attempt: 1,
      scheduledFor: Date.now() + HELD_PAYOUT_RETRY_MS,
    });
    expect(await f.scheduled()).toContainEqual(
      expect.objectContaining({
        name: "payouts:releasePayout",
        args: [{ payoutId: payout._id }],
        scheduledTime: Date.now() + HELD_PAYOUT_RETRY_MS,
      }),
    );
    const jobs = await f.scheduled();
    await f.t.mutation(internal.payouts.markPayoutFailed, {
      payoutId: payout._id,
      error: "Repeated callback",
      attempt: 0,
    });
    expect((await f.payouts())[0]?.error).toBe("Transfer unavailable");
    expect(await f.scheduled()).toEqual(jobs);
    expect(await f.ledger()).toEqual([]);
  });

  test("stops permanently after three failed transfer attempts", async () => {
    const f = await setupPayouts();
    await f.addAccount();
    await f.complete();
    const [payout] = await f.payouts();
    stripeMock.mockRejectedValue(new Error("Network unavailable"));
    await f.t.finishAllScheduledFunctions(() => vi.runAllTimers());
    expect(stripeMock).toHaveBeenCalledTimes(3);
    expect(
      stripeMock.mock.calls.map((call) => call[3]?.idempotencyKey),
    ).toEqual(
      [0, 1, 2].map((attempt) =>
        stripeIdempotencyKey("payout", payout._id, attempt),
      ),
    );
    expect((await f.payouts())[0]).toMatchObject({
      status: "failed",
      attempt: 2,
      error: "Error: Network unavailable",
    });
    expect(await f.readBooking()).toMatchObject({ status: "completed" });
    expect(await f.ledger()).toEqual([]);
    expect(
      (await f.scheduled()).filter(
        (job) => job.name === "payouts:releasePayout",
      ),
    ).toHaveLength(3);
    const jobs = await f.scheduled();
    await f.t.mutation(internal.payouts.releasePayout, {
      payoutId: payout._id,
    });
    await f.t.mutation(internal.payouts.retryHeldPayouts, {});
    expect(await f.scheduled()).toEqual(jobs);
  });
});

describe("payout query access", () => {
  test("booking parties and platform admins see only the payout summary", async () => {
    const f = await setupPayouts();
    await f.complete();
    const [payout] = await f.payouts();
    for (const actor of ["owner", "admin", "platformAdmin"] as const) {
      expect(
        await f
          .as(actor)
          .query(api.payouts.payoutsForBooking, { bookingId: f.bookingId }),
      ).toEqual([
        {
          _id: payout._id,
          kind: "completion",
          amountMinor: 13500,
          currency: "usd",
          status: "scheduled",
          scheduledFor: NOW + PAYOUT_DELAY_MS,
        },
      ]);
    }
    for (const actor of ["member", "stranger"] as const) {
      expect(
        await f
          .as(actor)
          .query(api.payouts.payoutsForBooking, { bookingId: f.bookingId }),
      ).toEqual([]);
    }
    expect(
      await f.t.query(api.payouts.payoutsForBooking, {
        bookingId: f.bookingId,
      }),
    ).toEqual([]);
    const missingBookingId = await f.t.run(async (ctx) => {
      const booking = (await ctx.db.get(f.bookingId))!;
      const { _id, _creationTime, ...fields } = booking;
      const id = await ctx.db.insert("bookings", fields);
      await ctx.db.delete(id);
      return id;
    });
    expect(
      await f
        .as("owner")
        .query(api.payouts.payoutsForBooking, { bookingId: missingBookingId }),
    ).toEqual([]);
  });

  test("band queries require band admin membership, including for platform admins, and return newest first", async () => {
    const f = await setupPayouts([9000, 6000]);
    await f.complete();
    const rows = await f.payouts();
    expect(
      (
        await f
          .as("admin")
          .query(api.payouts.payoutsForBand, { bandId: f.bandId })
      ).map((row) => row._id),
    ).toEqual([rows[1]._id, rows[0]._id]);
    for (const actor of [
      "owner",
      "member",
      "platformAdmin",
      "stranger",
    ] as const) {
      await expect(
        f.as(actor).query(api.payouts.payoutsForBand, { bandId: f.bandId }),
      ).rejects.toThrow("Not an admin of this band");
    }
    await f.t.run((ctx) =>
      ctx.db.insert("bandMembers", {
        bandId: f.bandId,
        userId: f.users.platformAdmin,
        role: "admin",
      }),
    );
    expect(
      await f
        .as("platformAdmin")
        .query(api.payouts.payoutsForBand, { bandId: f.bandId }),
    ).toHaveLength(2);
    await expect(
      f.t.query(api.payouts.payoutsForBand, { bandId: f.bandId }),
    ).rejects.toThrow("Not signed in");
  });
});
