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
  vi.stubEnv("PROMOTERS_ENABLED", undefined);
  vi.stubEnv("BOOKING_COMMISSION_BPS", undefined);
  vi.stubEnv("TICKETING_FEE_BPS", undefined);
  vi.stubEnv("TICKETING_FEE_FIXED_MINOR", undefined);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("features: public flags", () => {
  test("returns defaults without authentication when flags are unset", async () => {
    const t = convexTest(schema);

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: false,
      tickets: false,
      payments: false,
      bandGigWrites: true,
      disputes: false,
      promoters: false,
    });
  });

  test("reads explicit true and false flags without authentication", async () => {
    const t = convexTest(schema);
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    vi.stubEnv("TICKETS_ENABLED", "true");
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    vi.stubEnv("BAND_GIG_WRITES", "false");
    vi.stubEnv("DISPUTES_ENABLED", "true");
    vi.stubEnv("PROMOTERS_ENABLED", "true");

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: true,
      tickets: true,
      payments: true,
      bandGigWrites: false,
      disputes: true,
      promoters: true,
    });
  });

  test("reads numeric string flags without authentication", async () => {
    const t = convexTest(schema);
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "0");
    vi.stubEnv("TICKETS_ENABLED", "1");
    vi.stubEnv("PAYMENTS_ENABLED", "0");
    vi.stubEnv("BAND_GIG_WRITES", "1");
    vi.stubEnv("DISPUTES_ENABLED", "0");
    vi.stubEnv("PROMOTERS_ENABLED", "0");

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: false,
      tickets: true,
      payments: false,
      bandGigWrites: true,
      disputes: false,
      promoters: false,
    });
  });

  test.each([
    { value: undefined, enabled: false },
    { value: "", enabled: false },
    { value: "invalid", enabled: false },
    { value: "true", enabled: true },
    { value: "1", enabled: true },
    { value: "false", enabled: false },
    { value: "0", enabled: false },
  ])("reads DISPUTES_ENABLED=$value as $enabled", async ({ value, enabled }) => {
    const t = convexTest(schema);
    vi.stubEnv("DISPUTES_ENABLED", value);

    expect((await t.query(api.features.flags, {})).disputes).toBe(enabled);
  });

  test.each([
    { value: undefined, enabled: false },
    { value: "", enabled: false },
    { value: "invalid", enabled: false },
    { value: "true", enabled: true },
    { value: "1", enabled: true },
    { value: "false", enabled: false },
    { value: "0", enabled: false },
  ])("reads PROMOTERS_ENABLED=$value as $enabled", async ({ value, enabled }) => {
    const t = convexTest(schema);
    vi.stubEnv("PROMOTERS_ENABLED", value);

    expect((await t.query(api.features.flags, {})).promoters).toBe(enabled);
  });
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

  test("returns organization overrides ahead of env rates without authentication", async () => {
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
      return await ctx.db.insert("organizations", {
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
    });

    expect(await t.query(api.features.fees, { organizationId })).toEqual({
      bookingCommissionBps: 800,
      ticketingFeeBps: 200,
      ticketingFeeFixedMinor: 25,
      configured: true,
    });
  });

  test("returns zeros and configured false when both fees are unset", async () => {
    const t = convexTest(schema);

    expect(await t.query(api.features.fees, {})).toEqual({
      bookingCommissionBps: 0,
      ticketingFeeBps: 0,
      ticketingFeeFixedMinor: 0,
      configured: false,
    });
  });

  test("preserves commission when ticketing fees are unset", async () => {
    const t = convexTest(schema);
    vi.stubEnv("BOOKING_COMMISSION_BPS", "1250");

    expect(await t.query(api.features.fees, {})).toEqual({
      bookingCommissionBps: 1250,
      ticketingFeeBps: 0,
      ticketingFeeFixedMinor: 0,
      configured: false,
    });
  });

  test("preserves ticketing fees when commission is unset", async () => {
    const t = convexTest(schema);
    vi.stubEnv("TICKETING_FEE_BPS", "350");
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "50");

    expect(await t.query(api.features.fees, {})).toEqual({
      bookingCommissionBps: 0,
      ticketingFeeBps: 350,
      ticketingFeeFixedMinor: 50,
      configured: false,
    });
  });

  test.each([false, true])(
    "falls back to env for an organization without overrides (deleted: %s)",
    async (deleted) => {
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
          createdAt: 1,
          updatedAt: 1,
        });
        if (deleted) await ctx.db.delete(id);
        return id;
      });

      expect(await t.query(api.features.fees, { organizationId })).toEqual({
        bookingCommissionBps: 1250,
        ticketingFeeBps: 350,
        ticketingFeeFixedMinor: 50,
        configured: true,
      });
    },
  );
});
