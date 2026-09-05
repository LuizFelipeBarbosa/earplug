/// <reference types="vite/client" />
import { ApiFromModules, FunctionArgs } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import * as artistApplications from "./artistApplications";
import {
  APPLICATION_ACTIVE_STATUSES,
  APPLICATION_TRANSITIONS,
  ArtistApplicationStatus,
} from "./lib/opportunityStatus";
import schema from "./schema";

// Keep references typed while this lane intentionally leaves codegen untouched.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ artistApplications: typeof artistApplications }>;
const modules = import.meta.glob("./**/*.ts");
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse("2026-09-04T12:00:00Z");
const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "admin",
  "member",
  "otherAdmin",
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
});

async function setupApplications(
  overrides: Partial<
    Pick<Doc<"talentOpportunities">, "status" | "visibility" | "mode">
  > = {},
) {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) =>
    t.withIdentity({ subject: `application_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `application_${actor}`,
        name: actor,
        email: `${actor}@application.test`,
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
    const bandFields = {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      bio: "Loud guitars and harmonies.",
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 12,
      pastShows: [{ title: "Last Friday", meta: "Neighborhood Hall" }],
      linkIg: "@staticbloom",
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const otherBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
    });
    const archivedBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Archived Band",
      slug: "archived-band",
      archivedAt: NOW,
    });
    for (const [memberBandId, userId, role] of [
      [bandId, users.admin, "admin"],
      [bandId, users.member, "member"],
      [otherBandId, users.otherAdmin, "admin"],
      [archivedBandId, users.admin, "admin"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId: memberBandId,
        userId,
        role,
      });
    }
    const opportunityFields = {
      organizationId,
      mode: "publicEvent" as const,
      venueId,
      area: "Uptown, Oakland",
      venueType: "hall" as const,
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt: NOW + 14 * DAY_MS,
      ageRequirement: "allAges" as const,
      flyKey: "xerox",
      applicationsCloseAt: NOW + 7 * DAY_MS,
      visibility: "public" as const,
      ticketing: "rsvp" as const,
      currency: "usd",
      status: "open" as const,
      slug: "friday-at-the-hall",
      createdBy: users.owner,
      revision: 2,
      applicationCount: 0,
      createdAt: NOW,
      updatedAt: NOW,
    };
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      ...opportunityFields,
      ...overrides,
    });
    const otherOpportunityId = await ctx.db.insert("talentOpportunities", {
      ...opportunityFields,
      slug: "another-show",
      title: "Another show",
    });
    const slotFields = {
      opportunityId,
      order: 0,
      role: "headliner" as const,
      setLengthMin: 45,
      guaranteeMinor: 5000,
      required: true,
      status: "open" as const,
    };
    const slotId = await ctx.db.insert("opportunitySlots", slotFields);
    const secondSlotId = await ctx.db.insert("opportunitySlots", {
      ...slotFields,
      order: 1,
      role: "support",
    });
    const otherSlotId = await ctx.db.insert("opportunitySlots", {
      ...slotFields,
      opportunityId: otherOpportunityId,
    });
    return {
      users,
      organizationId,
      venueId,
      bandId,
      otherBandId,
      archivedBandId,
      opportunityId,
      otherOpportunityId,
      slotId,
      secondSlotId,
      otherSlotId,
    };
  });

  async function assertCounts() {
    await t.run(async (ctx) => {
      for (const opportunityId of [
        ids.opportunityId,
        ids.otherOpportunityId,
      ]) {
        const opportunity = await ctx.db.get(opportunityId);
        if (!opportunity) continue;
        const applications = await ctx.db
          .query("artistApplications")
          .withIndex("by_opportunityId_and_bandId", (q) =>
            q.eq("opportunityId", opportunityId),
          )
          .take(1000);
        // Fixtures stay below this bound, so the recount must include every row.
        expect(applications.length).toBeLessThan(1000);
        expect(opportunity.applicationCount).toBe(
          applications.filter((row) =>
            APPLICATION_ACTIVE_STATUSES.includes(row.status),
          ).length,
        );
      }
    });
  }
  // Every test write, including failed mutations, checks the counter immediately.
  async function checked<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } finally {
      await assertCounts();
    }
  }
  const applyArgs = {
    opportunityId: ids.opportunityId,
    slotId: ids.slotId,
    bandId: ids.bandId,
    message: "We are available",
  };
  async function apply(
    fields: Partial<FunctionArgs<typeof api.artistApplications.apply>> = {},
    actor: Actor = "admin",
  ) {
    return await checked(() =>
      as(actor).mutation(api.artistApplications.apply, {
        ...applyArgs,
        ...fields,
      }),
    );
  }
  async function seedApplications(
    rows: Array<
      Pick<Doc<"artistApplications">, "status"> &
        Partial<
          Pick<
            Doc<"artistApplications">,
            "bandId" | "createdAt" | "decidedBy" | "decidedAt"
          >
        >
    >,
  ) {
    return await checked(() =>
      t.run(async (ctx) => {
        const opportunity = await ctx.db.get(ids.opportunityId);
        if (!opportunity) throw new Error("Fixture opportunity missing");
        const applicationIds: Id<"artistApplications">[] = [];
        for (const row of rows) {
          applicationIds.push(
            await ctx.db.insert("artistApplications", {
              ...applyArgs,
              submittedBy: ids.users.admin,
              createdAt: NOW,
              updatedAt: NOW,
              ...row,
            }),
          );
        }
        await ctx.db.patch(ids.opportunityId, {
          applicationCount:
            opportunity.applicationCount +
            rows.filter((row) =>
              APPLICATION_ACTIVE_STATUSES.includes(row.status),
            ).length,
        });
        return applicationIds;
      }),
    );
  }
  await assertCounts();
  return {
    t,
    as,
    ...ids,
    applyArgs,
    checked,
    apply,
    seedApplications,
    readApplication: (id: Id<"artistApplications">) =>
      t.run((ctx) => ctx.db.get(id)),
    readOpportunity: () => t.run((ctx) => ctx.db.get(ids.opportunityId)),
  };
}

describe("artist applications: apply", () => {
  test("submits a normalized application and increments the active count", async () => {
    const f = await setupApplications();
    const { applicationId } = await f.apply({
      message: "  We are available  ",
      askMinor: 12000,
      availabilityNote: "  After 6pm  ",
      lineupNote: "  Four musicians  ",
    });
    expect(await f.readApplication(applicationId)).toMatchObject({
      ...f.applyArgs,
      submittedBy: f.users.admin,
      status: "submitted",
      askMinor: 12000,
      availabilityNote: "After 6pm",
      lineupNote: "Four musicians",
      createdAt: NOW,
      updatedAt: NOW,
    });
    expect(await f.readOpportunity()).toMatchObject({
      applicationCount: 1,
      updatedAt: NOW,
    });
  });

  test.each(APPLICATION_ACTIVE_STATUSES)(
    "rejects a duplicate when existing status is %s",
    async (status) => {
      const f = await setupApplications();
      await f.seedApplications([{ status }]);
      await expect(f.apply({ slotId: f.secondSlotId })).rejects.toThrow(
        "This band already has an active application for this opportunity",
      );
      expect((await f.readOpportunity())?.applicationCount).toBe(1);
    },
  );

  test("withdraws and reapplies with a new row, preserving the old application", async () => {
    const f = await setupApplications();
    const first = await f.apply();
    vi.setSystemTime(NOW + 100);
    await expect(
      f.checked(() =>
        f.as("admin").mutation(api.artistApplications.withdraw, first),
      ),
    ).resolves.toBeNull();
    expect(await f.readApplication(first.applicationId)).toMatchObject({
      status: "withdrawn",
      createdAt: NOW,
      updatedAt: NOW + 100,
    });
    expect(await f.readApplication(first.applicationId)).not.toHaveProperty(
      "decidedAt",
    );
    expect(await f.readOpportunity()).toMatchObject({
      applicationCount: 0,
      updatedAt: NOW + 100,
    });
    vi.setSystemTime(NOW + 200);
    const second = await f.apply();
    expect(second.applicationId).not.toBe(first.applicationId);
    expect((await f.readApplication(first.applicationId))?.status).toBe(
      "withdrawn",
    );
    expect((await f.readApplication(second.applicationId))?.status).toBe(
      "submitted",
    );
    expect((await f.readOpportunity())?.applicationCount).toBe(1);
  });

  test.each(["declined", "expired"] as const)(
    "can reapply after %s",
    async (status) => {
      const f = await setupApplications();
      const [oldId] = await f.seedApplications([{ status }]);
      const { applicationId } = await f.apply();
      expect(applicationId).not.toBe(oldId);
      expect((await f.readApplication(oldId))?.status).toBe(status);
    },
  );

  test("checks the newest applications after a longer inactive history", async () => {
    const f = await setupApplications();
    await f.seedApplications(
      Array.from({ length: 10 }, () => ({ status: "withdrawn" })),
    );
    await f.apply();
    await expect(f.apply()).rejects.toThrow(
      "already has an active application",
    );
  });

  test.each(["draft", "applications_closed"] as const)(
    "rejects a %s opportunity",
    async (status) => {
      const f = await setupApplications({ status });
      await expect(f.apply()).rejects.toThrow(
        "Opportunity is not accepting applications",
      );
    },
  );

  test.each([
    ["in the past", NOW - 1],
    ["at the current time", NOW],
  ] as const)(
    "rejects an open opportunity with an application deadline %s",
    async (_, applicationsCloseAt) => {
      const f = await setupApplications();
      await f.checked(() =>
        f.t.run((ctx) =>
          ctx.db.patch(f.opportunityId, { applicationsCloseAt }),
        ),
      );
      await expect(f.apply()).rejects.toThrow(
        /^Applications for this opportunity have closed$/,
      );
    },
  );

  test("accepts an open opportunity with an application deadline in the future", async () => {
    const f = await setupApplications();
    await f.checked(() =>
      f.t.run((ctx) =>
        ctx.db.patch(f.opportunityId, { applicationsCloseAt: NOW + 1 }),
      ),
    );
    const { applicationId } = await f.apply();
    expect((await f.readApplication(applicationId))?.status).toBe(
      "submitted",
    );
  });

  test.each(["pending", "suspended"] as const)(
    "rejects applications to a %s organization",
    async (status) => {
      const f = await setupApplications();
      await f.checked(() =>
        f.t.run((ctx) => ctx.db.patch(f.organizationId, { status })),
      );
      await expect(f.apply()).rejects.toThrow(
        "This organizer is not accepting applications",
      );
    },
  );

  test("rejects private bookings", async () => {
    const f = await setupApplications({ mode: "privateBooking" });
    await expect(f.apply()).rejects.toThrow(
      "Private bookings are not available yet",
    );
  });

  test("rejects missing opportunities, missing slots, and slots belonging to another opportunity", async () => {
    const f = await setupApplications();
    await expect(f.apply({ slotId: f.otherSlotId })).rejects.toThrow(
      "Slot not found",
    );
    await f.checked(() => f.t.run((ctx) => ctx.db.delete(f.slotId)));
    await expect(f.apply()).rejects.toThrow("Slot not found");
    await f.checked(() => f.t.run((ctx) => ctx.db.delete(f.opportunityId)));
    await expect(f.apply()).rejects.toThrow("Opportunity not found");
  });

  test.each(["booked", "cancelled"] as const)(
    "rejects a %s slot",
    async (status) => {
      const f = await setupApplications();
      await f.checked(() =>
        f.t.run((ctx) => ctx.db.patch(f.slotId, { status })),
      );
      await expect(f.apply()).rejects.toThrow("Slot is not open");
    },
  );

  test("requires a band admin and rejects an archived band even for its admin", async () => {
    const f = await setupApplications();
    for (const actor of ["member", "stranger", "owner"] as const) {
      await expect(f.apply({}, actor)).rejects.toThrow(
        "Not an admin of this band",
      );
    }
    await expect(f.apply({ bandId: f.archivedBandId })).rejects.toThrow(
      "Band not found",
    );
    await expect(
      f.checked(() =>
        f.t.mutation(api.artistApplications.apply, f.applyArgs),
      ),
    ).rejects.toThrow("Not signed in");
  });

  test("invite-only applications require an invite for the exact band and opportunity", async () => {
    const f = await setupApplications({ visibility: "inviteOnly" });
    await expect(f.apply()).rejects.toThrow(
      "This opportunity is invite-only",
    );
    await f.checked(() =>
      f.t.run(async (ctx) => {
        for (const [opportunityId, bandId] of [
          [f.opportunityId, f.otherBandId],
          [f.otherOpportunityId, f.bandId],
        ] as const) {
          await ctx.db.insert("opportunityInvites", {
            opportunityId,
            bandId,
            invitedBy: f.users.owner,
            createdAt: NOW,
          });
        }
      }),
    );
    await expect(f.apply()).rejects.toThrow(
      "This opportunity is invite-only",
    );
    await f.checked(() =>
      f.t.run((ctx) =>
        ctx.db.insert("opportunityInvites", {
          opportunityId: f.opportunityId,
          bandId: f.bandId,
          invitedBy: f.users.owner,
          createdAt: NOW,
        }),
      ),
    );
    const { applicationId } = await f.apply();
    expect((await f.readApplication(applicationId))?.status).toBe(
      "submitted",
    );
  });

  test("visibility helper checks band visibility independently of lifecycle or caller", async () => {
    const f = await setupApplications({ status: "draft" });
    expect(
      await f.t.run(async (ctx) =>
        artistApplications.canBandSeeOpportunity(
          ctx,
          (await ctx.db.get(f.opportunityId))!,
          f.bandId,
        ),
      ),
    ).toBe(true);
  });

  test.each([
    {
      message: "x".repeat(1001),
      error: "Message must be at most 1000 characters",
    },
    {
      availabilityNote: "x".repeat(501),
      error: "Availability note must be at most 500 characters",
    },
    {
      lineupNote: "x".repeat(501),
      error: "Lineup note must be at most 500 characters",
    },
    ...[-1, 0.5, 10_000_001, Number.NaN, Number.POSITIVE_INFINITY].map(
      (askMinor) => ({
        askMinor,
        error: "Ask must be an integer between 0 and 10000000",
      }),
    ),
  ])("rejects invalid fields: $error", async ({ error, ...fields }) => {
    const f = await setupApplications();
    await expect(f.apply(fields)).rejects.toThrow(error);
    expect(
      await f.as("member").query(api.artistApplications.mine, {
        opportunityId: f.opportunityId,
        bandId: f.bandId,
      }),
    ).toBeNull();
  });

  test.each([0, 10_000_000])(
    "accepts inclusive field limits with ask %s",
    async (askMinor) => {
      const f = await setupApplications();
      const { applicationId } = await f.apply({
        message: ` ${"m".repeat(1000)} `,
        availabilityNote: ` ${"a".repeat(500)} `,
        lineupNote: ` ${"l".repeat(500)} `,
        askMinor,
      });
      expect(await f.readApplication(applicationId)).toMatchObject({
        message: "m".repeat(1000),
        availabilityNote: "a".repeat(500),
        lineupNote: "l".repeat(500),
        askMinor,
      });
    },
  );

  test("allows an empty message, omits blank notes, and returns explicit null optionals", async () => {
    const f = await setupApplications();
    const { applicationId } = await f.apply({
      message: "  ",
      availabilityNote: " \n ",
      lineupNote: " \t ",
    });
    const row = await f.readApplication(applicationId);
    for (const field of [
      "askMinor",
      "availabilityNote",
      "lineupNote",
      "decidedAt",
      "decidedBy",
    ]) {
      expect(row).not.toHaveProperty(field);
    }
    const payload = await f
      .as("member")
      .query(api.artistApplications.mine, {
        opportunityId: f.opportunityId,
        bandId: f.bandId,
      });
    expect(payload).toEqual({
      _id: applicationId,
      opportunityId: f.opportunityId,
      slotId: f.slotId,
      bandId: f.bandId,
      status: "submitted",
      message: "",
      askMinor: null,
      availabilityNote: null,
      lineupNote: null,
      decidedAt: null,
      createdAt: NOW,
      updatedAt: NOW,
    });
  });
});

describe("artist applications: withdrawal and review", () => {
  test.each(APPLICATION_ACTIVE_STATUSES.filter((status) => status !== "offered"))(
    "can withdraw from %s without changing organizer decision metadata",
    async (status) => {
      const f = await setupApplications();
      const [applicationId] = await f.seedApplications([
        {
          status,
          decidedBy: f.users.owner,
          decidedAt: NOW - 100,
        },
      ]);
      vi.setSystemTime(NOW + 100);
      await f.checked(() =>
        f
          .as("admin")
          .mutation(api.artistApplications.withdraw, { applicationId }),
      );
      expect(await f.readApplication(applicationId)).toMatchObject({
        status: "withdrawn",
        decidedBy: f.users.owner,
        decidedAt: NOW - 100,
        updatedAt: NOW + 100,
      });
      expect((await f.readOpportunity())?.applicationCount).toBe(0);
      await expect(
        f.checked(() =>
          f
            .as("admin")
            .mutation(api.artistApplications.withdraw, { applicationId }),
        ),
      ).rejects.toThrow(
        "Application cannot go from withdrawn to withdrawn",
      );
      await expect(
        f.checked(() =>
          f.as("owner").mutation(api.artistApplications.review, {
            applicationId,
            action: "under_review",
          }),
        ),
      ).rejects.toThrow(
        "Application cannot go from withdrawn to under_review",
      );
    },
  );

  test("withdrawal requires an admin of the application's own band", async () => {
    const f = await setupApplications();
    const application = await f.apply();
    for (const actor of ["member", "otherAdmin", "owner"] as const) {
      await expect(
        f.checked(() =>
          f
            .as(actor)
            .mutation(api.artistApplications.withdraw, application),
        ),
      ).rejects.toThrow("Not an admin of this band");
    }
    await f.checked(() =>
      f.t.run((ctx) => ctx.db.patch(f.bandId, { archivedAt: NOW })),
    );
    await expect(
      f.checked(() =>
        f
          .as("admin")
          .mutation(api.artistApplications.withdraw, application),
      ),
    ).rejects.toThrow("Band not found");
    expect(
      (await f.readApplication(application.applicationId))?.status,
    ).toBe("submitted");
  });

  test.each(["owner", "manager"] as const)(
    "%s reviews through shortlist and declines with an atomic count update",
    async (actor) => {
      const f = await setupApplications();
      const { applicationId } = await f.apply();
      await f.apply({ bandId: f.otherBandId }, "otherAdmin");
      const actions = ["under_review", "shortlisted", "declined"] as const;
      for (const [index, action] of actions.entries()) {
        vi.setSystemTime(NOW + index + 1);
        await expect(
          f.checked(() =>
            f.as(actor).mutation(api.artistApplications.review, {
              applicationId,
              action,
            }),
          ),
        ).resolves.toBeNull();
        const application = await f.readApplication(applicationId);
        expect(application).toMatchObject({
          status: action,
          updatedAt: NOW + index + 1,
        });
        const opportunity = await f.readOpportunity();
        expect(opportunity?.applicationCount).toBe(
          action === "declined" ? 1 : 2,
        );
        if (action === "declined") {
          expect(application).toMatchObject({
            decidedBy: f.users[actor],
            decidedAt: NOW + 3,
          });
          expect(opportunity?.updatedAt).toBe(NOW + 3);
        } else {
          expect(application).not.toHaveProperty("decidedBy");
          expect(application).not.toHaveProperty("decidedAt");
          expect(opportunity?.updatedAt).toBe(NOW);
        }
      }
      await expect(
        f.checked(() =>
          f.as(actor).mutation(api.artistApplications.review, {
            applicationId,
            action: "declined",
          }),
        ),
      ).rejects.toThrow("Application cannot go from declined to declined");
    },
  );

  test.each([
    "finance",
    "door",
    "stranger",
    "admin",
    "otherAdmin",
  ] as const)("%s cannot review applications", async (actor) => {
    const f = await setupApplications();
    const { applicationId } = await f.apply();
    for (const action of [
      "under_review",
      "shortlisted",
      "declined",
    ] as const) {
      await expect(
        f.checked(() =>
          f.as(actor).mutation(api.artistApplications.review, {
            applicationId,
            action,
          }),
        ),
      ).rejects.toThrow("Not permitted for this organization");
    }
    expect((await f.readApplication(applicationId))?.status).toBe(
      "submitted",
    );
  });

  test.each(["booked", "declined", "expired"] as const)(
    "terminal status %s cannot be withdrawn or reviewed",
    async (status) => {
      const f = await setupApplications();
      const [applicationId] = await f.seedApplications([{ status }]);
      const withdrawMessage =
        status === "booked"
          ? "Cancel the booking instead of withdrawing the application"
          : `Application cannot go from ${status} to withdrawn`;
      await expect(
        f.checked(() =>
          f
            .as("admin")
            .mutation(api.artistApplications.withdraw, { applicationId }),
        ),
      ).rejects.toThrow(withdrawMessage);
      const reviewMessage =
        status === "booked"
          ? "Cancel the booking instead of declining the application"
          : `Application cannot go from ${status} to declined`;
      await expect(
        f.checked(() =>
          f.as("owner").mutation(api.artistApplications.review, {
            applicationId,
            action: "declined",
          }),
        ),
      ).rejects.toThrow(reviewMessage);
    },
  );

  test("rejects missing applications and missing review opportunities; orphaned applications can be withdrawn", async () => {
    const f = await setupApplications();
    const [missingApplicationId] = await f.seedApplications([
      { status: "withdrawn" },
    ]);
    await f.checked(() =>
      f.t.run((ctx) => ctx.db.delete(missingApplicationId)),
    );
    await expect(
      f.checked(() =>
        f.as("admin").mutation(api.artistApplications.withdraw, {
          applicationId: missingApplicationId,
        }),
      ),
    ).rejects.toThrow("Application not found");
    await expect(
      f.checked(() =>
        f.as("owner").mutation(api.artistApplications.review, {
          applicationId: missingApplicationId,
          action: "declined",
        }),
      ),
    ).rejects.toThrow("Application not found");
    const { applicationId } = await f.apply();
    await f.checked(() => f.t.run((ctx) => ctx.db.delete(f.opportunityId)));
    await expect(
      f.checked(() =>
        f.as("owner").mutation(api.artistApplications.review, {
          applicationId,
          action: "declined",
        }),
      ),
    ).rejects.toThrow("Opportunity not found");
    expect((await f.readApplication(applicationId))?.status).toBe(
      "submitted",
    );
    await f.checked(() =>
      f
        .as("admin")
        .mutation(api.artistApplications.withdraw, { applicationId }),
    );
    expect((await f.readApplication(applicationId))?.status).toBe(
      "withdrawn",
    );
  });
});

describe("artist applications: private queries", () => {
  test.each([
    ["owner", "admin@application.test"],
    ["manager", "admin@application.test"],
    ["platformAdmin", "admin@application.test"],
    ["finance", null],
    ["door", null],
  ] as const)(
    "forOpportunity gives %s the band profile with appropriate contact visibility",
    async (actor, contactEmail) => {
      const f = await setupApplications();
      const { applicationId } = await f.apply();
      const result = await f
        .as(actor)
        .query(api.artistApplications.forOpportunity, {
          opportunityId: f.opportunityId,
        });
      expect(result).toHaveLength(1);
      expect(result[0]).toEqual({
        application: {
          _id: applicationId,
          opportunityId: f.opportunityId,
          slotId: f.slotId,
          bandId: f.bandId,
          status: "submitted",
          message: "We are available",
          askMinor: null,
          availabilityNote: null,
          lineupNote: null,
          decidedAt: null,
          createdAt: NOW,
          updatedAt: NOW,
        },
        band: {
          _id: f.bandId,
          name: "Static Bloom",
          slug: "static-bloom",
          genres: ["Indie"],
          bio: "Loud guitars and harmonies.",
          area: "Oakland",
          colorHex: "#7B8FFF",
          initials: "SB",
          followerCount: 12,
          pastShows: [{ title: "Last Friday", meta: "Neighborhood Hall" }],
          linkIg: "@staticbloom",
          linkBc: null,
          linkYt: null,
          credits: null,
          heroUrl: null,
          avatarUrl: null,
          bannerUrl: null,
          profileComplete: true,
          discoveryProfileReady: false,
          reviewSummary: null,
        },
        contactEmail,
      });
    },
  );

  test("forOpportunity rejects non-organizers, signed-out callers, and missing opportunities", async () => {
    const f = await setupApplications();
    await f.apply();
    for (const actor of ["stranger", "admin", "member"] as const) {
      await expect(
        f.as(actor).query(api.artistApplications.forOpportunity, {
          opportunityId: f.opportunityId,
        }),
      ).rejects.toThrow("Not permitted for this organization");
    }
    await expect(
      f.t.query(api.artistApplications.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("Not signed in");
    await f.checked(() => f.t.run((ctx) => ctx.db.delete(f.opportunityId)));
    await expect(
      f.as("owner").query(api.artistApplications.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).rejects.toThrow("Opportunity not found");
  });

  test("forOpportunity sorts active applications first and oldest first within both groups", async () => {
    const f = await setupApplications();
    const ids = await f.seedApplications([
      { status: "declined", createdAt: NOW + 2 },
      { status: "submitted", createdAt: NOW + 4 },
      { status: "withdrawn", createdAt: NOW + 1 },
      { status: "offered", bandId: f.otherBandId, createdAt: NOW + 3 },
    ]);
    const result = await f
      .as("owner")
      .query(api.artistApplications.forOpportunity, {
        opportunityId: f.opportunityId,
      });
    expect(result.map((row) => row.application._id)).toEqual([
      ids[3],
      ids[1],
      ids[2],
      ids[0],
    ]);
  });

  test("forOpportunity skips missing or archived bands and tolerates a missing submitter", async () => {
    const f = await setupApplications();
    const [visibleId] = await f.seedApplications([
      { status: "submitted" },
      { status: "submitted", bandId: f.archivedBandId },
      { status: "submitted", bandId: f.otherBandId },
    ]);
    await f.checked(() =>
      f.t.run(async (ctx) => {
        await ctx.db.delete(f.otherBandId);
        await ctx.db.delete(f.users.admin);
      }),
    );
    const result = await f
      .as("owner")
      .query(api.artistApplications.forOpportunity, {
        opportunityId: f.opportunityId,
      });
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      application: { _id: visibleId },
      contactEmail: null,
    });
    expect((await f.readOpportunity())?.applicationCount).toBe(3);
  });

  test("forOpportunity bounds its response at 200 applications", async () => {
    const f = await setupApplications();
    await f.seedApplications(
      Array.from({ length: 201 }, (_, index) => ({
        status: "expired",
        createdAt: NOW + index,
      })),
    );
    expect(
      await f.as("owner").query(api.artistApplications.forOpportunity, {
        opportunityId: f.opportunityId,
      }),
    ).toHaveLength(200);
  });

  test("forBand gracefully denies signed-out and non-member callers while listing a member's applications", async () => {
    const f = await setupApplications();
    const { applicationId } = await f.apply();
    await f.apply({ bandId: f.otherBandId }, "otherAdmin");
    const args = { bandId: f.bandId };
    for (const client of [
      f.t,
      f.as("stranger"),
      f.as("otherAdmin"),
      f.t.withIdentity({ subject: "unknown" }),
    ]) {
      expect(
        await client.query(api.artistApplications.forBand, args),
      ).toEqual([]);
    }
    const result = await f
      .as("member")
      .query(api.artistApplications.forBand, args);
    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      application: { _id: applicationId, bandId: f.bandId },
      opportunity: {
        _id: f.opportunityId,
        title: "Friday at the Hall",
        applicationCount: 2,
        venue: {
          _id: f.venueId,
          name: "Neighborhood Hall",
          verified: true,
        },
        slots: [
          { _id: f.slotId, role: "headliner", setLengthMin: 45 },
          { _id: f.secondSlotId, role: "support" },
        ],
      },
    });
  });

  test("forBand includes all eight statuses newest first and skips missing opportunities", async () => {
    const f = await setupApplications();
    const statuses = Object.keys(
      APPLICATION_TRANSITIONS,
    ) as ArtistApplicationStatus[];
    const ids = await f.seedApplications(
      statuses.map((status, index) => ({ status, createdAt: NOW + index })),
    );
    const result = await f
      .as("member")
      .query(api.artistApplications.forBand, { bandId: f.bandId });
    expect(result.map((row) => row.application._id)).toEqual(
      [...ids].reverse(),
    );
    await f.checked(() => f.t.run((ctx) => ctx.db.delete(f.opportunityId)));
    expect(
      await f
        .as("member")
        .query(api.artistApplications.forBand, { bandId: f.bandId }),
    ).toEqual([]);
  });

  test("forBand caps the merged response at the newest 100, including beyond a single status's read limit", async () => {
    const f = await setupApplications();
    const ids = await f.seedApplications(
      Array.from({ length: 120 }, (_, index) => ({
        status: index < 110 ? "withdrawn" : "declined",
        createdAt: NOW + index,
      })),
    );
    const result = await f
      .as("member")
      .query(api.artistApplications.forBand, { bandId: f.bandId });
    expect(result.map((row) => row.application._id)).toEqual(
      ids.slice(-100).reverse(),
    );
  });

  test("mine returns null or the latest application for precisely the requested band and opportunity", async () => {
    const f = await setupApplications();
    const args = { opportunityId: f.opportunityId, bandId: f.bandId };
    expect(
      await f.as("member").query(api.artistApplications.mine, args),
    ).toBeNull();
    const first = await f.apply();
    await f.checked(() =>
      f.as("admin").mutation(api.artistApplications.withdraw, first),
    );
    vi.setSystemTime(NOW + 100);
    const latest = await f.apply();
    vi.setSystemTime(NOW + 200);
    await f.apply({ bandId: f.otherBandId }, "otherAdmin");
    await f.apply({
      opportunityId: f.otherOpportunityId,
      slotId: f.otherSlotId,
    });
    expect(
      await f.as("member").query(api.artistApplications.mine, args),
    ).toMatchObject({
      _id: latest.applicationId,
      status: "submitted",
      createdAt: NOW + 100,
    });
    await f.checked(() =>
      f.as("admin").mutation(api.artistApplications.withdraw, latest),
    );
    expect(
      await f.as("admin").query(api.artistApplications.mine, args),
    ).toMatchObject({
      _id: latest.applicationId,
      status: "withdrawn",
    });
  });

  test("mine requires membership and rejects signed-out callers and archived bands", async () => {
    const f = await setupApplications();
    const args = { opportunityId: f.opportunityId, bandId: f.bandId };
    await expect(
      f.t.query(api.artistApplications.mine, args),
    ).rejects.toThrow("Not signed in");
    await expect(
      f.as("stranger").query(api.artistApplications.mine, args),
    ).rejects.toThrow("Not a member of this band");
    await expect(
      f.as("admin").query(api.artistApplications.mine, {
        ...args,
        bandId: f.archivedBandId,
      }),
    ).rejects.toThrow("Band not found");
  });
});
