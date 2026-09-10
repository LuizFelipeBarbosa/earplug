import type { ApiFromModules } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import type * as features from "./features";
import schema from "./schema";

// Keep references typed while generated files remain outside this change.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ features: typeof features }>;

beforeEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv("BOOKING_COMMISSION_BPS", undefined);
  vi.stubEnv("TICKETING_FEE_BPS", undefined);
  vi.stubEnv("TICKETING_FEE_FIXED_MINOR", undefined);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("features: public fees", () => {
  test.each([
    {
      bookingCommissionBps: 1250,
      ticketingFeeBps: 350,
      ticketingFeeFixedMinor: 50,
    },
    {
      bookingCommissionBps: 0,
      ticketingFeeBps: 0,
      ticketingFeeFixedMinor: 0,
    },
  ])("returns env-only rates without authentication: %j", async (rates) => {
    const t = convexTest(schema);
    vi.stubEnv("BOOKING_COMMISSION_BPS", String(rates.bookingCommissionBps));
    vi.stubEnv("TICKETING_FEE_BPS", String(rates.ticketingFeeBps));
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", String(rates.ticketingFeeFixedMinor));

    expect(await t.query(api.features.fees, {})).toEqual({
      ...rates,
      configured: true,
    });
  });

  async function setupOrganizationWithFeeOverrides() {
    const t = convexTest(schema);
    vi.stubEnv("BOOKING_COMMISSION_BPS", "1250");
    vi.stubEnv("TICKETING_FEE_BPS", "350");
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "50");
    const organizationId = await t.run(async (ctx) => {
      const ownerUserId = await ctx.db.insert("users", {
        clerkId: "fee-test-owner",
        name: "Fee Test Owner",
        email: "fees@example.com",
        genres: [],
        attendedCount: 0,
      });
      const id = await ctx.db.insert("organizations", {
        name: "Fee Test Organization",
        slug: "fee-test-organization",
        orgType: "promoter",
        status: "verified",
        ownerUserId,
        bookingCommissionBps: 800,
        ticketingFeeBps: 200,
        ticketingFeeFixedMinor: 25,
        createdAt: 1,
        updatedAt: 1,
      });
      const memberUserId = await ctx.db.insert("users", {
        clerkId: "fee-test-member",
        name: "Fee Test Member",
        email: "member-fees@example.com",
        genres: [],
        attendedCount: 0,
      });
      await ctx.db.insert("organizationMembers", {
        organizationId: id,
        userId: memberUserId,
        role: "door",
        createdAt: 1,
      });
      await ctx.db.insert("users", {
        clerkId: "fee-test-non-member",
        name: "Fee Test Non-Member",
        email: "non-member-fees@example.com",
        genres: [],
        attendedCount: 0,
      });
      return id;
    });

    return {
      t,
      organizationId,
      asMember: t.withIdentity({ subject: "fee-test-member" }),
      asNonMember: t.withIdentity({ subject: "fee-test-non-member" }),
    };
  }

  test("returns organization overrides ahead of env rates for a member", async () => {
    const { asMember, organizationId } = await setupOrganizationWithFeeOverrides();

    expect(await asMember.query(api.features.fees, { organizationId })).toEqual({
      bookingCommissionBps: 800,
      ticketingFeeBps: 200,
      ticketingFeeFixedMinor: 25,
      configured: true,
    });
  });

  test("returns env rates for an authenticated non-member", async () => {
    const { asNonMember, organizationId } =
      await setupOrganizationWithFeeOverrides();

    expect(
      await asNonMember.query(api.features.fees, { organizationId }),
    ).toEqual({
      bookingCommissionBps: 1250,
      ticketingFeeBps: 350,
      ticketingFeeFixedMinor: 50,
      configured: true,
    });
  });

  test("returns env rates for an anonymous caller despite organization overrides", async () => {
    const { t, organizationId } = await setupOrganizationWithFeeOverrides();

    expect(await t.query(api.features.fees, { organizationId })).toEqual({
      bookingCommissionBps: 1250,
      ticketingFeeBps: 350,
      ticketingFeeFixedMinor: 50,
      configured: true,
    });
  });

  test.each(["anonymous", "non-member"])(
    "returns configured false for %s callers when only organization overrides are set",
    async (caller) => {
      const { t, asNonMember, organizationId } =
        await setupOrganizationWithFeeOverrides();
      vi.stubEnv("BOOKING_COMMISSION_BPS", undefined);
      vi.stubEnv("TICKETING_FEE_BPS", undefined);
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", undefined);
      const client = caller === "anonymous" ? t : asNonMember;

      expect(await client.query(api.features.fees, { organizationId })).toEqual({
        bookingCommissionBps: 0,
        ticketingFeeBps: 0,
        ticketingFeeFixedMinor: 0,
        configured: false,
      });
    },
  );
});
