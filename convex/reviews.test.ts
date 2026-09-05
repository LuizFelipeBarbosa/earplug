/// <reference types="vite/client" />
import { ApiFromModules, FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  api as generatedApi,
  internal as generatedInternal,
} from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { REVIEW_WINDOW_MS } from "./lib/bookingStatus";
import { REVIEW_CATEGORIES, recomputeReviewSummary } from "./lib/reviewSummary";
import * as reviews from "./reviews";
import schema from "./schema";

// This slice intentionally leaves generated API declarations untouched.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ reviews: typeof reviews }>;
const internal = generatedInternal as typeof generatedInternal &
  ApiFromModules<{ reviews: typeof reviews }>;
const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-04T12:00:00Z");
const DAY_MS = 24 * 60 * 60 * 1000;
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "bandAdmin",
  "bandMember",
  "outsider",
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
});

async function setupReviews() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `review_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `review_${actor}`,
        name: actor,
        email: `${actor}@review.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Opportunity Collective",
      slug: "opportunity-collective",
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
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: NOW,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 12,
      pastShows: [],
    });
    for (const [actor, role] of [
      ["bandAdmin", "admin"],
      ["bandMember", "member"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: users[actor],
        role,
      });
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
      approxLabel: "Uptown, Oakland",
      venueType: "hall",
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      mode: "publicEvent",
      venueId,
      area: "Uptown, Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: NOW - DAY_MS,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: NOW - 7 * DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "completed",
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
      setLengthMin: 45,
      guaranteeMinor: 5000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.bandAdmin,
      message: "We are available",
      status: "booked",
      createdAt: NOW,
      updatedAt: NOW,
    });
    const bookingFields = {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "completed" as const,
      completedAt: NOW,
      revision: 1,
      startsAt: NOW - DAY_MS,
      grossMinor: 5000,
      commissionBps: 1000,
      commissionMinor: 500,
      artistNetMinor: 4500,
      currency: "usd",
      cancellationTemplate: "standard" as const,
      organizerAcceptedTermsAt: NOW,
      payoutHold: false,
      createdBy: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const bookingId = await ctx.db.insert("bookings", bookingFields);
    await ctx.db.patch(slotId, { bookingId });
    return {
      users,
      organizationId,
      bandId,
      opportunityId,
      bookingId,
      bookingFields,
    };
  });
  const submitArgs = {
    bookingId: ids.bookingId,
    rating: 5,
    categories: ["professionalism", "communication"],
    text: "  Great performance!  ",
  };
  const submit = (
    actor: Actor = "manager",
    fields: Partial<FunctionArgs<typeof api.reviews.submit>> = {},
  ) => as(actor).mutation(api.reviews.submit, { ...submitArgs, ...fields });
  const forBooking = (actor: Actor) =>
    as(actor).query(api.reviews.forBooking, { bookingId: ids.bookingId });
  const summaries = () =>
    t.run(async (ctx) => ({
      band: (await ctx.db.get(ids.bandId))?.reviewSummary,
      organization: (await ctx.db.get(ids.organizationId))?.reviewSummary,
    }));
  return { t, as, ...ids, submitArgs, submit, forBooking, summaries };
}

describe("reviews: double-blind submission", () => {
  test("a manager's first review is private to its author", async () => {
    const f = await setupReviews();
    const result = await f.submit();
    expect(result.visible).toBe(false);
    expect(await f.forBooking("bandAdmin")).toEqual({
      mine: null,
      theirs: null,
      windowClosesAt: NOW + REVIEW_WINDOW_MS,
      canSubmit: true,
    });
    expect(await f.forBooking("manager")).toMatchObject({
      mine: {
        reviewId: result.reviewId,
        authorSide: "organizer",
        text: "Great performance!",
        visibleAt: null,
      },
      theirs: null,
      canSubmit: false,
    });
    const stored = await f.t.run((ctx) => ctx.db.get(result.reviewId));
    expect(stored).toMatchObject({
      authorUserId: f.users.manager,
      subjectBandId: f.bandId,
      submittedAt: NOW,
      hidden: false,
      privateEvent: false,
    });
    expect(stored).not.toHaveProperty("visibleAt");
    expect(stored).not.toHaveProperty("subjectOrganizationId");
    expect(await f.t.query(api.reviews.forBand, { bandId: f.bandId })).toEqual(
      [],
    );
    expect(await f.summaries()).toEqual({
      band: undefined,
      organization: undefined,
    });
  });

  test.each(["manager", "bandAdmin"] as const)(
    "reveals both reviews atomically when %s submits first",
    async (firstActor) => {
      const f = await setupReviews();
      const secondActor = firstActor === "manager" ? "bandAdmin" : "manager";
      const first = await f.submit(firstActor, {
        rating: firstActor === "manager" ? 5 : 3,
      });
      expect(first.visible).toBe(false);
      vi.setSystemTime(NOW + 100);
      const second = await f.submit(secondActor, {
        rating: secondActor === "manager" ? 5 : 3,
      });
      expect(second.visible).toBe(true);
      for (const actor of ["manager", "bandAdmin"] as const) {
        const payload = await f.forBooking(actor);
        expect(payload.mine?.visibleAt).toBe(NOW + 100);
        expect(payload.theirs?.visibleAt).toBe(NOW + 100);
        expect(payload.canSubmit).toBe(false);
      }
      expect(await f.summaries()).toEqual({
        band: { count: 1, mean: 5, completedBookings: 1, cancellations: 0 },
        organization: {
          count: 1,
          mean: 3,
          completedBookings: 1,
          cancellations: 0,
        },
      });
    },
  );

  test("enforces one review per side, including different organization users", async () => {
    const f = await setupReviews();
    await f.submit();
    for (const actor of ["manager", "owner"] as const) {
      await expect(f.submit(actor)).rejects.toThrow(
        "You already reviewed this booking",
      );
    }
    await f.submit("bandAdmin");
    await expect(f.submit("bandAdmin")).rejects.toThrow(
      "You already reviewed this booking",
    );
  });

  test.each([
    "door",
    "finance",
    "outsider",
    "bandMember",
    "platformAdmin",
  ] as const)("%s cannot submit or read a booking's reviews", async (actor) => {
    const f = await setupReviews();
    await expect(f.submit(actor)).rejects.toThrow(
      "Only booking parties can review",
    );
    await expect(f.forBooking(actor)).rejects.toThrow(
      "Only booking parties can review",
    );
  });

  test("organization authority takes precedence for a caller on both sides", async () => {
    const f = await setupReviews();
    await f.t.run((ctx) =>
      ctx.db.insert("bandMembers", {
        bandId: f.bandId,
        userId: f.users.owner,
        role: "admin",
      }),
    );
    await f.submit("owner");
    expect(await f.forBooking("owner")).toMatchObject({
      mine: { authorSide: "organizer" },
    });
    await expect(f.submit("manager")).rejects.toThrow(
      "You already reviewed this booking",
    );
  });

  test("requires authentication and an existing booking", async () => {
    const f = await setupReviews();
    await expect(
      f.t.mutation(api.reviews.submit, f.submitArgs),
    ).rejects.toThrow("Not signed in");
    await expect(
      f.t.query(api.reviews.forBooking, { bookingId: f.bookingId }),
    ).rejects.toThrow("Not signed in");
    await f.t.run((ctx) => ctx.db.delete(f.bookingId));
    await expect(f.submit()).rejects.toThrow("Booking not found");
    await expect(f.forBooking("manager")).rejects.toThrow("Booking not found");
  });

  test.each(["confirmed", "cancelled_by_artist", "disputed"] as const)(
    "rejects reviews for a %s booking",
    async (status) => {
      const f = await setupReviews();
      await f.t.run((ctx) => ctx.db.patch(f.bookingId, { status }));
      await expect(f.submit()).rejects.toThrow(
        "Booking has not been completed yet",
      );
      expect((await f.forBooking("manager")).canSubmit).toBe(false);
    },
  );

  test("accepts a paid booking", async () => {
    const f = await setupReviews();
    await f.t.run((ctx) => ctx.db.patch(f.bookingId, { status: "paid" }));
    expect((await f.forBooking("manager")).canSubmit).toBe(true);
    expect((await f.submit()).visible).toBe(false);
  });
});

describe("reviews: review window", () => {
  test("rejects submission after the 14-day window", async () => {
    const f = await setupReviews();
    vi.setSystemTime(NOW + REVIEW_WINDOW_MS + 1);
    await expect(f.submit()).rejects.toThrow("The review window has closed");
    expect((await f.forBooking("manager")).canSubmit).toBe(false);
  });

  test("accepts submission exactly at the window deadline", async () => {
    const f = await setupReviews();
    vi.setSystemTime(NOW + REVIEW_WINDOW_MS);
    expect((await f.forBooking("manager")).canSubmit).toBe(true);
    expect((await f.submit()).visible).toBe(false);
  });

  test.each(["manager", "bandAdmin"] as const)(
    "closing the window reveals a lone %s review and is idempotent",
    async (actor) => {
      const f = await setupReviews();
      const { reviewId } = await f.submit(actor, { rating: 4 });
      vi.setSystemTime(NOW + REVIEW_WINDOW_MS + 1);
      const args = { bookingId: f.bookingId };
      await expect(
        f.t.mutation(internal.reviews.closeReviewWindow, args),
      ).resolves.toBeNull();
      const otherActor = actor === "manager" ? "bandAdmin" : "manager";
      expect((await f.forBooking(actor)).mine).toMatchObject({
        reviewId,
        visibleAt: NOW + REVIEW_WINDOW_MS + 1,
      });
      expect((await f.forBooking(otherActor)).theirs?.reviewId).toBe(reviewId);
      const summaries = await f.summaries();
      const subject =
        actor === "manager" ? summaries.band : summaries.organization;
      const otherSubject =
        actor === "manager" ? summaries.organization : summaries.band;
      expect(subject).toEqual({
        count: 1,
        mean: 4,
        completedBookings: 1,
        cancellations: 0,
      });
      expect(otherSubject).toEqual({
        count: 0,
        mean: 0,
        completedBookings: 1,
        cancellations: 0,
      });
      vi.setSystemTime(NOW + REVIEW_WINDOW_MS + DAY_MS);
      await f.t.mutation(internal.reviews.closeReviewWindow, args);
      expect((await f.forBooking(actor)).mine?.visibleAt).toBe(
        NOW + REVIEW_WINDOW_MS + 1,
      );
      expect(await f.summaries()).toEqual(summaries);
    },
  );

  test("closing with no pending reviews or a missing booking is a no-op", async () => {
    const f = await setupReviews();
    const args = { bookingId: f.bookingId };
    await f.t.mutation(internal.reviews.closeReviewWindow, args);
    expect(await f.summaries()).toEqual({
      band: undefined,
      organization: undefined,
    });
    const { reviewId } = await f.submit();
    await f.t.run((ctx) => ctx.db.delete(f.bookingId));
    await expect(
      f.t.mutation(internal.reviews.closeReviewWindow, args),
    ).resolves.toBeNull();
    expect(await f.t.run((ctx) => ctx.db.get(reviewId))).not.toHaveProperty(
      "visibleAt",
    );
  });
});

describe("reviews: validation", () => {
  test.each([0, 6, 3.5, NaN, Infinity])("rejects rating %s", async (rating) => {
    const f = await setupReviews();
    await expect(f.submit("manager", { rating })).rejects.toThrow(
      "Rating must be an integer between 1 and 5",
    );
    expect((await f.forBooking("manager")).mine).toBeNull();
  });

  test("rejects an unknown category", async () => {
    const f = await setupReviews();
    await expect(
      f.submit("manager", { categories: ["unknown"] }),
    ).rejects.toThrow("Unknown review category: unknown");
  });

  test("rejects more than six categories", async () => {
    const f = await setupReviews();
    await expect(
      f.submit("manager", { categories: Array(7).fill("sound") }),
    ).rejects.toThrow("Review must have at most 6 categories");
  });

  test("rejects text longer than 1000 trimmed characters", async () => {
    const f = await setupReviews();
    await expect(
      f.submit("manager", { text: "x".repeat(1001) }),
    ).rejects.toThrow("Review text must be at most 1000 characters");
  });

  test("accepts inclusive limits, all categories, and empty trimmed text", async () => {
    const f = await setupReviews();
    await f.submit("manager", {
      rating: 1,
      categories: [...REVIEW_CATEGORIES],
      text: ` ${"x".repeat(1000)} `,
    });
    await f.submit("bandAdmin", { rating: 5, categories: [], text: " \n\t " });
    expect((await f.forBooking("manager")).mine?.text).toBe("x".repeat(1000));
    expect((await f.forBooking("bandAdmin")).mine?.text).toBe("");
  });
});

describe("reviews: listings and moderation", () => {
  test("lists a visible band review and removes it and its rating when hidden", async () => {
    const f = await setupReviews();
    const { reviewId } = await f.submit();
    await f.submit("bandAdmin", { rating: 3 });
    expect(await f.t.query(api.reviews.forBand, { bandId: f.bandId })).toEqual([
      {
        reviewId,
        rating: 5,
        categories: f.submitArgs.categories,
        text: "Great performance!",
        submittedAt: NOW,
        monthLabel: "Sep 2026",
        organizationName: "Opportunity Collective",
        opportunityTitle: "Friday at the Hall",
      },
    ]);
    await expect(
      f.as("platformAdmin").mutation(api.reviews.hide, {
        reviewId,
        reason: "Abusive content",
      }),
    ).resolves.toBeNull();
    expect(await f.t.query(api.reviews.forBand, { bandId: f.bandId })).toEqual(
      [],
    );
    expect(await f.summaries()).toEqual({
      band: { count: 0, mean: 0, completedBookings: 1, cancellations: 0 },
      organization: {
        count: 1,
        mean: 3,
        completedBookings: 1,
        cancellations: 0,
      },
    });
    expect(await f.t.run((ctx) => ctx.db.get(reviewId))).toMatchObject({
      hidden: true,
      hiddenReason: "Abusive content",
    });
    // Moderation removes public listings; the booking parties retain their history.
    expect((await f.forBooking("bandAdmin")).theirs?.reviewId).toBe(reviewId);
  });

  test("moderation requires a platform admin and an existing review", async () => {
    const f = await setupReviews();
    const { reviewId } = await f.submit();
    const args = { reviewId, reason: "Spam" };
    await expect(
      f.as("owner").mutation(api.reviews.hide, args),
    ).rejects.toThrow("Not an EarPlug admin");
    await expect(f.t.mutation(api.reviews.hide, args)).rejects.toThrow(
      "Not signed in",
    );
    await f.t.run((ctx) => ctx.db.delete(reviewId));
    await expect(
      f.as("platformAdmin").mutation(api.reviews.hide, args),
    ).rejects.toThrow("Review not found");
  });

  test("a review hidden before reveal never contributes to listings or ratings", async () => {
    const f = await setupReviews();
    const { reviewId } = await f.submit("bandAdmin");
    await f
      .as("platformAdmin")
      .mutation(api.reviews.hide, { reviewId, reason: "Spam" });
    await f.submit();
    expect((await f.summaries()).organization).toEqual({
      count: 0,
      mean: 0,
      completedBookings: 1,
      cancellations: 0,
    });
    expect(
      await f
        .as("owner")
        .query(api.reviews.forOrganization, {
          organizationId: f.organizationId,
        }),
    ).toEqual([]);
  });

  test.each(["owner", "manager", "finance", "door", "platformAdmin"] as const)(
    "organization listings allow %s and include the band's name",
    async (actor) => {
      const f = await setupReviews();
      const { reviewId } = await f.submit("bandAdmin", { rating: 3 });
      const args = { organizationId: f.organizationId };
      expect(
        await f.as(actor).query(api.reviews.forOrganization, args),
      ).toEqual([]);
      await f.submit();
      expect(
        await f.as(actor).query(api.reviews.forOrganization, args),
      ).toEqual([
        {
          reviewId,
          rating: 3,
          categories: f.submitArgs.categories,
          text: "Great performance!",
          submittedAt: NOW,
          monthLabel: "Sep 2026",
          bandName: "Static Bloom",
          opportunityTitle: "Friday at the Hall",
        },
      ]);
      await f
        .as("platformAdmin")
        .mutation(api.reviews.hide, { reviewId, reason: "Spam" });
      expect(
        await f.as(actor).query(api.reviews.forOrganization, args),
      ).toEqual([]);
      expect((await f.summaries()).organization?.count).toBe(0);
    },
  );

  test("organization listings reject outsiders and unauthenticated callers", async () => {
    const f = await setupReviews();
    const args = { organizationId: f.organizationId };
    for (const actor of ["outsider", "bandAdmin"] as const) {
      await expect(
        f.as(actor).query(api.reviews.forOrganization, args),
      ).rejects.toThrow("Not permitted for this organization");
    }
    await expect(f.t.query(api.reviews.forOrganization, args)).rejects.toThrow(
      "Not signed in",
    );
  });

  test.each(["band", "organization"] as const)(
    "%s listings sort by reveal time, exclude hidden/pending reviews, and limit results",
    async (subject) => {
      const f = await setupReviews();
      const reviewIds = await f.t.run(async (ctx) => {
        const ids: Id<"reviews">[] = [];
        for (let index = 0; index < 62; index++) {
          ids.push(
            await ctx.db.insert("reviews", {
              bookingId: f.bookingId,
              authorSide: subject === "band" ? "organizer" : "artist",
              authorUserId: f.users.manager,
              ...(subject === "band"
                ? { subjectBandId: f.bandId }
                : { subjectOrganizationId: f.organizationId }),
              rating: 4,
              categories: [],
              text: `Review ${index}`,
              submittedAt: NOW + index,
              // Reveal order deliberately differs from insertion/submission order.
              ...(index === 61 ? {} : { visibleAt: NOW + 100 - index }),
              hidden: index === 60,
              privateEvent: false,
            }),
          );
        }
        return ids.slice(0, 60);
      });
      const list = (limit?: number) =>
        subject === "band"
          ? f.t.query(api.reviews.forBand, { bandId: f.bandId, limit })
          : f
              .as("owner")
              .query(api.reviews.forOrganization, {
                organizationId: f.organizationId,
                limit,
              });
      expect((await list()).map((row) => row.reviewId)).toEqual(
        reviewIds.slice(0, 20),
      );
      expect((await list(3)).map((row) => row.reviewId)).toEqual(
        reviewIds.slice(0, 3),
      );
      expect(await list(100)).toHaveLength(50);
      expect(await list(0)).toEqual([]);
    },
  );

  test.each(["bookingId", "organizationId", "opportunityId"] as const)(
    "band listings skip missing %s references",
    async (field) => {
      const f = await setupReviews();
      await f.submit();
      await f.submit("bandAdmin");
      await f.t.run((ctx) => ctx.db.delete(f[field]));
      expect(
        await f.t.query(api.reviews.forBand, { bandId: f.bandId }),
      ).toEqual([]);
    },
  );

  test.each(["bookingId", "bandId", "opportunityId"] as const)(
    "organization listings skip missing %s references",
    async (field) => {
      const f = await setupReviews();
      await f.submit();
      await f.submit("bandAdmin");
      await f.t.run((ctx) => ctx.db.delete(f[field]));
      expect(
        await f
          .as("owner")
          .query(api.reviews.forOrganization, {
            organizationId: f.organizationId,
          }),
      ).toEqual([]);
    },
  );
});

describe("reviews: rating summaries", () => {
  test("counts completed and paid bookings, and each subject's own cancellations", async () => {
    const f = await setupReviews();
    await f.submit();
    await f.submit("bandAdmin");
    expect((await f.summaries()).band?.completedBookings).toBe(1);
    await f.t.run(async (ctx) => {
      for (const status of [
        "paid",
        "cancelled_by_artist",
        "cancelled_by_organizer",
        "confirmed",
      ] as const) {
        await ctx.db.insert("bookings", {
          ...f.bookingFields,
          status,
          ...(status.startsWith("cancelled") ? { cancelledAt: NOW } : {}),
        });
      }
      await recomputeReviewSummary(ctx, { bandId: f.bandId });
      await recomputeReviewSummary(ctx, { organizationId: f.organizationId });
    });
    expect(await f.summaries()).toEqual({
      band: { count: 1, mean: 5, completedBookings: 2, cancellations: 1 },
      organization: {
        count: 1,
        mean: 5,
        completedBookings: 2,
        cancellations: 1,
      },
    });
  });

  test.each(["band", "organization"] as const)(
    "%s summaries round visible ratings, exclude hidden/pending rows, and are idempotent",
    async (subject) => {
      const f = await setupReviews();
      const target =
        subject === "band"
          ? { bandId: f.bandId }
          : { organizationId: f.organizationId };
      await f.t.run(async (ctx) => {
        for (const [rating, visibleAt, hidden] of [
          [4, NOW, false],
          [4, NOW, false],
          [5, NOW, false],
          [1, NOW, true],
          [1, undefined, false],
        ] as const) {
          await ctx.db.insert("reviews", {
            bookingId: f.bookingId,
            authorSide: subject === "band" ? "organizer" : "artist",
            authorUserId: f.users.manager,
            ...(subject === "band"
              ? { subjectBandId: f.bandId }
              : { subjectOrganizationId: f.organizationId }),
            rating,
            categories: [],
            text: "",
            submittedAt: NOW,
            ...(visibleAt !== undefined ? { visibleAt } : {}),
            hidden,
            privateEvent: false,
          });
        }
        await recomputeReviewSummary(ctx, target);
      });
      const before = await f.summaries();
      expect(before[subject]).toEqual({
        count: 3,
        mean: 4.33,
        completedBookings: 1,
        cancellations: 0,
      });
      await f.t.run((ctx) => recomputeReviewSummary(ctx, target));
      expect(await f.summaries()).toEqual(before);
    },
  );

  test("summary recomputation tolerates deleted subjects", async () => {
    const f = await setupReviews();
    await f.t.run(async (ctx) => {
      await ctx.db.delete(f.bandId);
      await ctx.db.delete(f.organizationId);
      await recomputeReviewSummary(ctx, { bandId: f.bandId });
      await recomputeReviewSummary(ctx, { organizationId: f.organizationId });
    });
    expect(await f.summaries()).toEqual({
      band: undefined,
      organization: undefined,
    });
  });
});
