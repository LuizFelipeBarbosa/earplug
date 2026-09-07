import type { ApiFromModules } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api as generatedApi } from "./_generated/api";
import type * as features from "./features";
import schema from "./schema";

// Keep references typed while generated files remain outside this change.
const api = generatedApi as typeof generatedApi &
  ApiFromModules<{ features: typeof features }>;

describe("features: public flags", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("returns defaults without authentication when flags are unset", async () => {
    const t = convexTest(schema);

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: false,
      tickets: false,
      payments: false,
      bandGigWrites: true,
      disputes: false,
    });
  });

  test("reads explicit true and false flags without authentication", async () => {
    const t = convexTest(schema);
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "true");
    vi.stubEnv("TICKETS_ENABLED", "true");
    vi.stubEnv("PAYMENTS_ENABLED", "true");
    vi.stubEnv("BAND_GIG_WRITES", "false");
    vi.stubEnv("DISPUTES_ENABLED", "true");

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: true,
      tickets: true,
      payments: true,
      bandGigWrites: false,
      disputes: true,
    });
  });

  test("reads numeric string flags without authentication", async () => {
    const t = convexTest(schema);
    vi.stubEnv("PRIVATE_BOOKINGS_ENABLED", "0");
    vi.stubEnv("TICKETS_ENABLED", "1");
    vi.stubEnv("PAYMENTS_ENABLED", "0");
    vi.stubEnv("BAND_GIG_WRITES", "1");
    vi.stubEnv("DISPUTES_ENABLED", "0");

    expect(await t.query(api.features.flags, {})).toEqual({
      privateBookings: false,
      tickets: true,
      payments: false,
      bandGigWrites: true,
      disputes: false,
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
});
