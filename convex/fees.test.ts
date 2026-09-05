import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc } from "./_generated/dataModel";
import { feeSnapshot, resolveCommissionBps, splitFee } from "./lib/fees";

describe("splitFee", () => {
  test("splits a fee into commission and artist net", () => {
    expect(splitFee(15000, 1000)).toEqual({
      grossMinor: 15000,
      commissionBps: 1000,
      commissionMinor: 1500,
      artistNetMinor: 13500,
    });
  });

  test("rounds commission to the nearest minor unit", () => {
    expect(splitFee(3333, 1500)).toEqual({
      grossMinor: 3333,
      commissionBps: 1500,
      commissionMinor: 500,
      artistNetMinor: 2833,
    });
  });

  test("rounds an exact half minor unit up", () => {
    expect(splitFee(5, 1000)).toEqual({
      grossMinor: 5,
      commissionBps: 1000,
      commissionMinor: 1,
      artistNetMinor: 4,
    });
  });

  test("allows a zero gross fee", () => {
    expect(splitFee(0, 1500)).toEqual({
      grossMinor: 0,
      commissionBps: 1500,
      commissionMinor: 0,
      artistNetMinor: 0,
    });
  });

  test.each([
    { commissionBps: 0, commissionMinor: 0, artistNetMinor: 15000 },
    { commissionBps: 10000, commissionMinor: 15000, artistNetMinor: 0 },
  ])("allows $commissionBps basis points", (split) => {
    expect(splitFee(15000, split.commissionBps)).toEqual({
      grossMinor: 15000,
      ...split,
    });
  });

  test.each([-1, 1.5, NaN, Infinity, -Infinity])(
    "rejects invalid gross fee %s",
    (grossMinor) => {
      expect(() => splitFee(grossMinor, 1000)).toThrowError();
    },
  );

  test.each([-1, 10001, 1000.5, NaN, Infinity, -Infinity])(
    "rejects invalid commission %s",
    (commissionBps) => {
      expect(() => splitFee(15000, commissionBps)).toThrowError();
    },
  );
});

describe("feeSnapshot", () => {
  test("defaults to usd", () => {
    expect(feeSnapshot(15000, 1000)).toEqual({
      grossMinor: 15000,
      commissionBps: 1000,
      commissionMinor: 1500,
      artistNetMinor: 13500,
      currency: "usd",
    });
  });

  test("preserves the supplied currency", () => {
    expect(feeSnapshot(15000, 1000, "eur")).toEqual({
      grossMinor: 15000,
      commissionBps: 1000,
      commissionMinor: 1500,
      artistNetMinor: 13500,
      currency: "eur",
    });
  });
});

describe("resolveCommissionBps", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("BOOKING_COMMISSION_BPS", undefined);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("uses the organization override without an environment setting", () => {
    const organization = { bookingCommissionBps: 750 } as Doc<"organizations">;

    expect(resolveCommissionBps(organization)).toBe(750);
  });

  test("prefers the organization override to the environment setting", () => {
    vi.stubEnv("BOOKING_COMMISSION_BPS", "1200");
    const organization = { bookingCommissionBps: 750 } as Doc<"organizations">;

    expect(resolveCommissionBps(organization)).toBe(750);
  });

  test("uses the environment setting when the override is absent", () => {
    vi.stubEnv("BOOKING_COMMISSION_BPS", "1200");
    const organization = {} as Doc<"organizations">;

    expect(resolveCommissionBps(organization)).toBe(1200);
  });

  test("rejects missing commission configuration", () => {
    const organization = {} as Doc<"organizations">;

    expect(() => resolveCommissionBps(organization)).toThrowError(
      new Error("Booking commission is not configured"),
    );
  });

  test.each(["", " ", "invalid", "-5", "10500", "1200.5"])(
    "rejects invalid environment setting %j",
    (value) => {
      vi.stubEnv("BOOKING_COMMISSION_BPS", value);
      const organization = {} as Doc<"organizations">;

      expect(() => resolveCommissionBps(organization)).toThrowError(
        new Error("Booking commission is not configured"),
      );
    },
  );

  test.each([-5, 10500, 750.5, NaN, Infinity, -Infinity])(
    "rejects invalid organization override %s even with a valid environment setting",
    (bookingCommissionBps) => {
      vi.stubEnv("BOOKING_COMMISSION_BPS", "1200");
      const organization = { bookingCommissionBps } as Doc<"organizations">;

      expect(() => resolveCommissionBps(organization)).toThrowError(
        new Error("Booking commission is not configured"),
      );
    },
  );

  test.each([0, 10000])(
    "allows a %i basis point override",
    (bookingCommissionBps) => {
      const organization = { bookingCommissionBps } as Doc<"organizations">;

      expect(resolveCommissionBps(organization)).toBe(bookingCommissionBps);
    },
  );

  test.each(["0", "10000"])(
    "allows a %s basis point environment setting",
    (value) => {
      vi.stubEnv("BOOKING_COMMISSION_BPS", value);
      const organization = {} as Doc<"organizations">;

      expect(resolveCommissionBps(organization)).toBe(Number(value));
    },
  );
});
