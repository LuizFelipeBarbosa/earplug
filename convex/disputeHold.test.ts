/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc } from "./_generated/dataModel";
import {
  holdForDispute,
  openInAppDispute,
  releaseDisputeHold,
} from "./lib/disputeHold";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

async function setupDisputeHold(bookingFields: Partial<Doc<"bookings">> = {}) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const userId = await ctx.db.insert("users", {
      clerkId: "dispute_owner",
      name: "Host",
      email: "host@dispute.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Dispute Collective",
      slug: "dispute-collective",
      orgType: "privateHost",
      status: "verified",
      ownerUserId: userId,
      createdAt: NOW,
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
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "privateBooking",
      area: "Oakland",
      title: "Private Show",
      desc: "Live music",
      genres: ["Indie"],
      startsAt: NOW,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW,
      visibility: "public",
      ticketing: "none",
      currency: "usd",
      status: "confirmed",
      slug: "private-show",
      createdBy: userId,
      revision: 1,
      applicationCount: 1,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 20000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: userId,
      status: "booked",
      message: "Available",
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
      startsAt: NOW,
      grossMinor: 20000,
      commissionBps: 1000,
      commissionMinor: 2000,
      artistNetMinor: 18000,
      currency: "usd",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: NOW,
      payoutHold: false,
      createdBy: userId,
      createdAt: NOW,
      updatedAt: NOW,
      ...bookingFields,
    });
    return { userId, bandId, bookingId };
  });
  return {
    t,
    ...ids,
    hold: (now = NOW) =>
      t.run(async (ctx) => {
        const booking = await ctx.db.get(ids.bookingId);
        return holdForDispute(ctx, booking!, { now });
      }),
    release: (now = NOW, keepHoldIf?: () => Promise<boolean>) =>
      t.run(async (ctx) => {
        const booking = await ctx.db.get(ids.bookingId);
        return releaseDisputeHold(ctx, booking!, { now, keepHoldIf });
      }),
    readState: () =>
      t.run(async (ctx) => ({
        booking: await ctx.db.get(ids.bookingId),
        payouts: await ctx.db
          .query("payouts")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
          .take(50),
        jobs: await ctx.db.system.query("_scheduled_functions").take(100),
      })),
    addPayout: (fields: Partial<Doc<"payouts">> = {}) =>
      t.run((ctx) =>
        ctx.db.insert("payouts", {
          bookingId: ids.bookingId,
          bandId: ids.bandId,
          kind: "completion",
          amountMinor: 9000,
          currency: "usd",
          status: "scheduled",
          scheduledFor: NOW,
          attempt: 0,
          createdAt: NOW,
          updatedAt: NOW,
          ...fields,
        }),
      ),
    addDispute: (fields: Partial<Doc<"disputes">> = {}) =>
      t.run((ctx) =>
        ctx.db.insert("disputes", {
          bookingId: ids.bookingId,
          openedByUserId: ids.userId,
          side: "organizer",
          category: "no_show",
          text: "Artist did not arrive",
          requestedRefundMinor: 20000,
          status: "open",
          createdAt: Date.now(),
          updatedAt: Date.now(),
          ...fields,
        }),
      ),
  };
}

describe("holdForDispute", () => {
  test("moves a confirmed booking to disputed and holds both scheduled payouts", async () => {
    const f = await setupDisputeHold();
    const payoutIds = [await f.addPayout(), await f.addPayout()];

    expect(await f.hold()).toEqual({
      movedToDisputed: true,
      heldPayoutIds: payoutIds,
    });
    const state = await f.readState();
    expect(state.booking).toMatchObject({
      status: "disputed",
      disputedFromStatus: "confirmed",
      payoutHoldReasons: ["dispute"],
      payoutHold: true,
      revision: 4,
      updatedAt: NOW,
    });
    expect(state.payouts).toMatchObject(
      payoutIds.map((_id) => ({ _id, status: "held", holdReason: "dispute" })),
    );
    expect(state.jobs).toEqual([]);
  });

  test("holds a refunded booking's payout without changing its status or revision", async () => {
    const f = await setupDisputeHold({ status: "refunded" });
    const payoutId = await f.addPayout();

    expect(await f.hold(NOW + 1000)).toEqual({
      movedToDisputed: false,
      heldPayoutIds: [payoutId],
    });
    const state = await f.readState();
    expect(state.booking).toMatchObject({
      status: "refunded",
      revision: 3,
      payoutHoldReasons: ["dispute"],
      payoutHold: true,
      updatedAt: NOW + 1000,
    });
    expect(state.booking?.disputedFromStatus).toBeUndefined();
    expect(state.payouts).toMatchObject([
      { _id: payoutId, status: "held", holdReason: "dispute" },
    ]);
  });

  test("repeated holds leave the booking untouched but still hold newly scheduled payouts", async () => {
    const f = await setupDisputeHold({
      payoutHoldReasons: ["admin"],
      payoutHold: true,
    });
    await f.addPayout();
    await f.addPayout({ status: "paid" });
    await f.addPayout({ status: "held", holdReason: "admin" });
    await f.hold();
    const held = await f.readState();

    expect(await f.hold(NOW + 1000)).toEqual({
      movedToDisputed: false,
      heldPayoutIds: [],
    });
    expect(await f.readState()).toEqual(held);
    const payoutId = await f.addPayout();
    expect(await f.hold(NOW + 2000)).toEqual({
      movedToDisputed: false,
      heldPayoutIds: [payoutId],
    });
    const state = await f.readState();
    expect(state.booking).toEqual(held.booking);
    expect(state.booking?.payoutHoldReasons).toEqual(["admin", "dispute"]);
    expect(state.payouts.slice(0, held.payouts.length)).toEqual(held.payouts);
  });
});

describe("releaseDisputeHold", () => {
  test.each(["confirmed", "completed", "paid"] as const)(
    "restores %s and schedules each released payout once while preserving other holds",
    async (status) => {
      const f = await setupDisputeHold({
        status,
        payoutHoldReasons: ["admin"],
        payoutHold: true,
      });
      const payoutIds = [await f.addPayout(), await f.addPayout()];
      const adminPayoutId = await f.addPayout({ status: "held", holdReason: "admin" });
      const adminPayout = await f.t.run((ctx) => ctx.db.get(adminPayoutId));
      await f.hold();

      expect(await f.release(NOW + 1000, async () => false)).toEqual({
        restoredStatus: status,
        rescheduledPayoutIds: payoutIds,
      });
      const released = await f.readState();
      expect(released.booking).toMatchObject({
        status,
        revision: 5,
        payoutHoldReasons: ["admin"],
        payoutHold: true,
        updatedAt: NOW + 1000,
      });
      expect(released.booking?.disputedFromStatus).toBeUndefined();
      expect(released.payouts.slice(0, 2)).toMatchObject(
        payoutIds.map((_id) => ({
          _id,
          status: "scheduled",
          updatedAt: NOW + 1000,
        })),
      );
      expect(await f.t.run((ctx) => ctx.db.get(adminPayoutId))).toEqual(adminPayout);
      expect(released.jobs).toMatchObject(
        payoutIds.map((payoutId) => ({
          name: "payouts:releasePayout",
          args: [{ payoutId }],
          scheduledTime: NOW,
        })),
      );
      expect(await f.release(NOW + 2000)).toEqual({ rescheduledPayoutIds: [] });
      expect(await f.readState()).toEqual(released);
    },
  );

  test("does not patch or schedule anything when no dispute hold exists", async () => {
    const f = await setupDisputeHold();
    await f.addPayout();
    const before = await f.readState();

    await f.t.run(async (ctx) => {
      const booking = await ctx.db.get(f.bookingId);
      const patch = vi.spyOn(ctx.db, "patch");
      const schedule = vi.spyOn(ctx.scheduler, "runAfter");
      expect(await releaseDisputeHold(ctx, booking!, { now: NOW + 1000 })).toEqual({
        rescheduledPayoutIds: [],
      });
      expect(patch).not.toHaveBeenCalled();
      expect(schedule).not.toHaveBeenCalled();
    });
    expect(await f.readState()).toEqual(before);
  });

  test("keeps all held state untouched when keepHoldIf returns true", async () => {
    const f = await setupDisputeHold();
    await f.addPayout();
    await f.hold();
    const held = await f.readState();
    const keepHoldIf = vi.fn(async () => true);

    expect(await f.release(NOW + 1000, keepHoldIf)).toEqual({
      rescheduledPayoutIds: [],
    });
    expect(keepHoldIf).toHaveBeenCalledOnce();
    expect(await f.readState()).toEqual(held);
  });
});

describe("openInAppDispute", () => {
  test("returns null when there is no active dispute for the booking", async () => {
    const f = await setupDisputeHold();
    expect(await f.t.run((ctx) => openInAppDispute(ctx, f.bookingId))).toBeNull();
    await f.addDispute({ status: "resolved", resolution: "dismissed" });
    expect(await f.t.run((ctx) => openInAppDispute(ctx, f.bookingId))).toBeNull();
  });

  test("returns the newest open or under-review row and ignores newer resolved rows", async () => {
    const f = await setupDisputeHold();
    const firstId = await f.addDispute();
    expect(await f.t.run((ctx) => openInAppDispute(ctx, f.bookingId))).toMatchObject({
      _id: firstId,
      status: "open",
    });
    vi.setSystemTime(NOW + 1000);
    const latestId = await f.addDispute({ status: "under_review" });
    vi.setSystemTime(NOW + 2000);
    await f.addDispute({ status: "resolved", resolution: "released" });

    expect(await f.t.run((ctx) => openInAppDispute(ctx, f.bookingId))).toMatchObject({
      _id: latestId,
      status: "under_review",
    });
  });
});
