/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { cancelOpportunity } from "./lib/opportunityCancel";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = Date.parse("2026-09-04T12:00:00Z");
const CUSTOM_REASON = "Venue approval revoked";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupOpportunity(status: "draft" | "open" = "open") {
  const t = convexTest(schema, modules);
  const asOwner = t.withIdentity({ subject: "cancel_owner" });
  const ids = await t.run(async (ctx) => {
    const userIds: Id<"users">[] = [];
    for (const actor of ["owner", "manager", "artist"]) {
      userIds.push(
        await ctx.db.insert("users", {
          clerkId: `cancel_${actor}`,
          name: actor,
          email: `${actor}@opportunity.test`,
          genres: [],
          attendedCount: 0,
        }),
      );
    }
    const [ownerId, managerId, artistId] = userIds;
    const organizationId = await ctx.db.insert("organizations", {
      name: "Cancellation Collective",
      slug: "cancellation-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: ownerId,
      createdAt: 1,
      updatedAt: 1,
    });
    for (const [role, userId] of [
      ["owner", ownerId],
      ["manager", managerId],
    ] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: 1,
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
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: artistId,
      role: "admin",
    });
    return { ownerId, managerId, artistId, organizationId, venueId, bandId };
  });
  const { opportunityId } = await asOwner.mutation(
    api.talentOpportunities.create,
    {
      organizationId: ids.organizationId,
      venueId: ids.venueId,
      title: "Friday at the Hall",
      startsAt: NOW + 14 * DAY_MS,
    },
  );
  if (status === "open") {
    await asOwner.mutation(api.talentOpportunities.open, {
      opportunityId,
      expectedRevision: 1,
    });
  }
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

  async function cancel(actorUserId: Id<"users"> = ids.ownerId) {
    await t.run(async (ctx) => {
      const opportunity = await ctx.db.get(opportunityId);
      if (!opportunity) throw new Error("Fixture opportunity missing");
      await cancelOpportunity(ctx, {
        opportunity,
        actorUserId,
        reason: CUSTOM_REASON,
        now: Date.now(),
      });
    });
  }

  async function readOpportunity() {
    return await t.run(async (ctx) => ({
      opportunity: await ctx.db.get(opportunityId),
      slots: await ctx.db
        .query("opportunitySlots")
        .withIndex("by_opportunityId_and_order", (q) =>
          q.eq("opportunityId", opportunityId),
        )
        .take(20),
    }));
  }

  return {
    t,
    ...ids,
    opportunityId,
    slotId,
    cancel,
    readOpportunity,
  };
}

describe("cancelOpportunity", () => {
  test.each(["pending", "granted", "declined", "withdrawn", "revoked"] as const)(
    "withdraws %s consent only when it is still active",
    async (status) => {
      const f = await setupOpportunity();
      const consentId = await f.t.run(async (ctx) => {
        const venueOrganizationId = await ctx.db.insert("organizations", {
          name: "Venue Operator",
          slug: "venue-operator",
          orgType: "venueOperator",
          status: "verified",
          ownerUserId: f.managerId,
          createdAt: NOW,
          updatedAt: NOW,
        });
        await ctx.db.patch(f.venueId, {
          managedByOrganizationId: venueOrganizationId,
        });
        return await ctx.db.insert("venueConsents", {
          opportunityId: f.opportunityId,
          venueId: f.venueId,
          venueOrganizationId,
          requestingOrganizationId: f.organizationId,
          status,
          createdAt: NOW,
          updatedAt: NOW,
        });
      });
      const consentBefore = await f.t.run((ctx) => ctx.db.get(consentId));
      vi.setSystemTime(NOW + 1000);

      await f.cancel();

      const consent = await f.t.run((ctx) => ctx.db.get(consentId));
      if (status === "pending" || status === "granted") {
        expect(consent).toEqual({
          ...consentBefore,
          status: "withdrawn",
          updatedAt: NOW + 1000,
        });
      } else {
        expect(consent).toEqual(consentBefore);
      }
      expect((await f.readOpportunity()).opportunity).toMatchObject({
        status: "cancelled",
        updatedAt: NOW + 1000,
      });
    },
  );
});
