/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import type { Doc, Id } from "./_generated/dataModel";
import {
  VENUE_CONSENT_TRANSITIONS,
  assertVenueConsentTransition,
  assertVenueUsable,
  consentRequiredFor,
  currentConsentFor,
  type VenueConsentStatus,
} from "./lib/venueConsentStatus";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);

const venueFields = {
  name: "The Lantern",
  area: "Oakland",
  addr: "99 Main Street",
  distSF: "7 mi",
  distOak: "1 mi",
  lat: 37.8044,
  lng: -122.2711,
  status: "verified" as const,
};

describe("Venue consent transitions", () => {
  const expectedTransitions: Record<
    VenueConsentStatus,
    readonly VenueConsentStatus[]
  > = {
    pending: ["granted", "declined", "withdrawn"],
    granted: ["revoked", "withdrawn"],
    declined: [],
    withdrawn: [],
    revoked: [],
  };
  const statuses = Object.keys(expectedTransitions) as VenueConsentStatus[];

  test("exports the supported transition table", () => {
    expect(VENUE_CONSENT_TRANSITIONS).toEqual(expectedTransitions);
  });

  describe.each(statuses)("from %s", (from) => {
    test.each(statuses)("to %s", (to) => {
      if (expectedTransitions[from].includes(to)) {
        expect(() => assertVenueConsentTransition(from, to)).not.toThrow();
      } else {
        expect(() => assertVenueConsentTransition(from, to)).toThrowError(
          new Error(`Venue approval cannot go from ${from} to ${to}`),
        );
      }
    });
  });
});

describe("consentRequiredFor", () => {
  const organizationId = "requesting-organization" as Id<"organizations">;
  const venueOrganizationId = "venue-organization" as Id<"organizations">;
  const venue: Doc<"venues"> = {
    ...venueFields,
    _id: "venue" as Id<"venues">,
    _creationTime: 0,
    managedByOrganizationId: venueOrganizationId,
  };

  test("does not require consent for the organization's own verified venue", () => {
    expect(
      consentRequiredFor(
        { ...venue, managedByOrganizationId: organizationId },
        organizationId,
      ),
    ).toBe(false);
  });

  test("requires consent for a foreign verified venue", () => {
    expect(consentRequiredFor(venue, organizationId)).toBe(true);
  });

  test.each<Doc<"venues">["status"]>([
    undefined,
    "legacy",
    "pending",
    "verified",
    "suspended",
  ])("does not require consent for an unmanaged venue with status %s", (status) => {
    expect(
      consentRequiredFor(
        { ...venue, managedByOrganizationId: undefined, status },
        organizationId,
      ),
    ).toBe(false);
  });

  describe.each([
    { label: "own", managedByOrganizationId: organizationId },
    { label: "foreign", managedByOrganizationId: venueOrganizationId },
  ])("$label venue", ({ managedByOrganizationId }) => {
    test.each<Doc<"venues">["status"]>([
      undefined,
      "legacy",
      "pending",
      "suspended",
    ])("does not require consent for unverified status %s", (status) => {
      expect(
        consentRequiredFor(
          { ...venue, managedByOrganizationId, status },
          organizationId,
        ),
      ).toBe(false);
    });
  });
});

describe("assertVenueUsable", () => {
  const organizationId = "requesting-organization" as Id<"organizations">;
  const venueOrganizationId = "venue-organization" as Id<"organizations">;
  const venue: Doc<"venues"> = {
    ...venueFields,
    _id: "venue" as Id<"venues">,
    _creationTime: 0,
    managedByOrganizationId: venueOrganizationId,
  };

  describe.each([false, true])("promotersEnabled: %s", (promotersEnabled) => {
    test("accepts the organization's own verified venue without consent", () => {
      expect(
        assertVenueUsable(
          { ...venue, managedByOrganizationId: organizationId },
          organizationId,
          { promotersEnabled },
        ),
      ).toEqual({ consentRequired: false });
    });

    test.each<Doc<"venues">["status"]>([
      undefined,
      "legacy",
      "pending",
      "suspended",
    ])("rejects an own venue with unverified status %s", (status) => {
      expect(() =>
        assertVenueUsable(
          { ...venue, managedByOrganizationId: organizationId, status },
          organizationId,
          { promotersEnabled },
        ),
      ).toThrowError(new Error("Choose one of your verified venues"));
    });
  });

  describe.each([
    { label: "foreign managed", managedByOrganizationId: venueOrganizationId },
    { label: "unmanaged", managedByOrganizationId: undefined },
  ])("$label venue with promoters disabled", ({ managedByOrganizationId }) => {
    test.each<Doc<"venues">["status"]>([
      undefined,
      "legacy",
      "pending",
      "verified",
      "suspended",
    ])("preserves the original venue error for status %s", (status) => {
      expect(() =>
        assertVenueUsable(
          { ...venue, managedByOrganizationId, status },
          organizationId,
          { promotersEnabled: false },
        ),
      ).toThrowError(new Error("Choose one of your verified venues"));
    });
  });

  test.each<Doc<"venues">["status"]>([
    undefined,
    "legacy",
    "pending",
    "verified",
    "suspended",
  ])("rejects an unmanaged venue with promoters enabled and status %s", (status) => {
    expect(() =>
      assertVenueUsable(
        { ...venue, managedByOrganizationId: undefined, status },
        organizationId,
        { promotersEnabled: true },
      ),
    ).toThrowError(new Error("This venue has not joined EarPlug yet"));
  });

  test.each<Doc<"venues">["status"]>([
    undefined,
    "legacy",
    "pending",
    "suspended",
  ])("rejects a foreign unverified venue with promoters enabled and status %s", (status) => {
    expect(() =>
      assertVenueUsable(
        { ...venue, status },
        organizationId,
        { promotersEnabled: true },
      ),
    ).toThrowError(new Error("Choose a verified venue"));
  });

  test("requires consent for a foreign verified venue with promoters enabled", () => {
    expect(
      assertVenueUsable(venue, organizationId, { promotersEnabled: true }),
    ).toEqual({ consentRequired: true });
  });
});

async function setupConsents(statuses: readonly VenueConsentStatus[]) {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const createdAt = Date.UTC(2026, 8, 8);
    const userId = await ctx.db.insert("users", {
      clerkId: "consent-organizer",
      name: "Organizer",
      email: "organizer@example.com",
      genres: [],
      attendedCount: 0,
    });
    const organizationFields = {
      status: "verified" as const,
      ownerUserId: userId,
      createdAt,
      updatedAt: createdAt,
    };
    const requestingOrganizationId = await ctx.db.insert("organizations", {
      ...organizationFields,
      name: "Bay Area Shows",
      slug: "bay-area-shows",
      orgType: "promoter",
    });
    const venueOrganizationId = await ctx.db.insert("organizations", {
      ...organizationFields,
      name: "The Lantern",
      slug: "the-lantern",
      orgType: "venueOperator",
    });
    const venueId = await ctx.db.insert("venues", {
      ...venueFields,
      managedByOrganizationId: venueOrganizationId,
    });
    const opportunityFields: Omit<
      Doc<"talentOpportunities">,
      "_id" | "_creationTime"
    > = {
      organizationId: requestingOrganizationId,
      venueId,
      mode: "publicEvent",
      area: "Oakland",
      title: "Autumn Sessions",
      desc: "An evening of live music.",
      genres: [],
      startsAt: createdAt + 86_400_000,
      ageRequirement: "allAges",
      flyKey: "paper",
      applicationsCloseAt: createdAt,
      visibility: "public",
      ticketing: "none",
      currency: "USD",
      status: "draft",
      slug: "autumn-sessions",
      createdBy: userId,
      revision: 1,
      applicationCount: 0,
      createdAt,
      updatedAt: createdAt,
    };
    const opportunityId = await ctx.db.insert(
      "talentOpportunities",
      opportunityFields,
    );
    const otherOpportunityId = await ctx.db.insert("talentOpportunities", {
      ...opportunityFields,
      slug: "other-sessions",
    });
    const consentIds: Id<"venueConsents">[] = [];
    for (const status of statuses) {
      consentIds.push(
        await ctx.db.insert("venueConsents", {
          opportunityId,
          venueId,
          venueOrganizationId,
          requestingOrganizationId,
          status,
          createdAt,
          updatedAt: createdAt,
        }),
      );
    }
    return { opportunityId, otherOpportunityId, consentIds };
  });
  return { t, ...ids };
}

describe("currentConsentFor", () => {
  test.each<VenueConsentStatus>(["pending", "granted"])(
    "returns the %s row after ignoring inactive rows",
    async (status) => {
      const { t, opportunityId, consentIds } = await setupConsents([
        "declined",
        "withdrawn",
        "revoked",
        status,
      ]);
      const expected = await t.run((ctx) =>
        ctx.db.get("venueConsents", consentIds[3]),
      );

      expect(await t.run((ctx) => currentConsentFor(ctx, opportunityId))).toEqual(
        expected,
      );
    },
  );

  test("returns null when only inactive rows exist", async () => {
    const { t, opportunityId } = await setupConsents([
      "declined",
      "withdrawn",
      "revoked",
    ]);

    expect(await t.run((ctx) => currentConsentFor(ctx, opportunityId))).toBeNull();
  });

  test("returns null when no consent rows exist", async () => {
    const { t, opportunityId } = await setupConsents([]);

    expect(await t.run((ctx) => currentConsentFor(ctx, opportunityId))).toBeNull();
  });

  test("ignores active rows belonging to another opportunity", async () => {
    const { t, otherOpportunityId } = await setupConsents(["pending"]);

    expect(
      await t.run((ctx) => currentConsentFor(ctx, otherOpportunityId)),
    ).toBeNull();
  });

  test("returns the newest match if multiple active rows exist", async () => {
    const { t, opportunityId, consentIds } = await setupConsents([
      "granted",
      "pending",
    ]);
    const consent = await t.run((ctx) => currentConsentFor(ctx, opportunityId));

    expect(consent?._id).toBe(consentIds[1]);
  });

  test("finds a new pending consent after twelve inactive rows", async () => {
    const { t, opportunityId, consentIds } = await setupConsents([
      ...Array.from({ length: 12 }, () => "declined" as const),
      "pending",
    ]);

    expect(
      await t.run((ctx) => currentConsentFor(ctx, opportunityId)),
    ).toMatchObject({ _id: consentIds[12], status: "pending" });
  });
});
