import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import {
  orderTotals,
  resolveTicketingFee,
  unitFeeMinor,
} from "./lib/ticketFees";

describe("resolveTicketingFee", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("TICKETING_FEE_BPS", undefined);
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", undefined);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  test("uses a complete organization override without environment settings", () => {
    expect(
      resolveTicketingFee({
        ticketingFeeBps: 750,
        ticketingFeeFixedMinor: 50,
      }),
    ).toEqual({ bps: 750, fixedMinor: 50 });
  });

  test.each(["500", "invalid"])(
    "prefers a complete organization override to environment settings %j",
    (value) => {
      vi.stubEnv("TICKETING_FEE_BPS", value);
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", value);

      expect(
        resolveTicketingFee({
          ticketingFeeBps: 750,
          ticketingFeeFixedMinor: 50,
        }),
      ).toEqual({ bps: 750, fixedMinor: 50 });
    },
  );

  test.each([0, 10000])(
    "allows a %i basis point override and zero fixed fee",
    (bps) => {
      expect(
        resolveTicketingFee({
          ticketingFeeBps: bps,
          ticketingFeeFixedMinor: 0,
        }),
      ).toEqual({ bps, fixedMinor: 0 });
    },
  );

  test.each([
    {},
    { ticketingFeeBps: 750 },
    { ticketingFeeFixedMinor: 50 },
    { ticketingFeeBps: 0 },
    { ticketingFeeFixedMinor: 0 },
  ])(
    "uses both environment settings for an incomplete override %j",
    (organization) => {
      vi.stubEnv("TICKETING_FEE_BPS", "500");
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "100");

      expect(resolveTicketingFee(organization)).toEqual({
        bps: 500,
        fixedMinor: 100,
      });
    },
  );

  test.each([
    undefined,
    "",
    " ",
    "abc",
    "-5",
    "10001",
    "1.5",
    "NaN",
    "Infinity",
  ])("rejects missing or invalid environment basis points %j", (value) => {
    vi.stubEnv("TICKETING_FEE_BPS", value);
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "100");

    expect(() => resolveTicketingFee({})).toThrowError(
      new Error("Ticketing fee is not configured"),
    );
  });

  test.each([undefined, "", " \t "])(
    "rejects missing or blank environment fixed fee %j",
    (value) => {
      vi.stubEnv("TICKETING_FEE_BPS", "500");
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", value);

      expect(() => resolveTicketingFee({})).toThrowError(
        new Error("Ticketing fee is not configured"),
      );
    },
  );

  test(
    "rejects garbage environment fixed fee abc with the raw value",
    () => {
      vi.stubEnv("TICKETING_FEE_BPS", "500");
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "abc");

      expect(() => resolveTicketingFee({})).toThrowError(
        new Error("Invalid TICKETING_FEE_FIXED_MINOR: abc"),
      );
    },
  );

  test.each(["0", "10000"])(
    "allows %s environment basis points and an explicitly zero fixed fee",
    (value) => {
      vi.stubEnv("TICKETING_FEE_BPS", value);
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "0");

      expect(resolveTicketingFee({})).toEqual({
        bps: Number(value),
        fixedMinor: 0,
      });
    },
  );

  test("accepts whitespace around configured integer values", () => {
    vi.stubEnv("TICKETING_FEE_BPS", " 500 ");
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", " 100 ");

    expect(resolveTicketingFee({})).toEqual({ bps: 500, fixedMinor: 100 });
  });

  test.each([{}, { ticketingFeeBps: 750 }, { ticketingFeeFixedMinor: 50 }])(
    "rejects incomplete overrides %j without environment settings",
    (organization) => {
      expect(() => resolveTicketingFee(organization)).toThrowError(
        new Error("Ticketing fee is not configured"),
      );
    },
  );

  test("does not combine organization basis points with only an environment fixed fee", () => {
    vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "100");

    expect(() => resolveTicketingFee({ ticketingFeeBps: 750 })).toThrowError(
      new Error("Ticketing fee is not configured"),
    );
  });

  test("does not combine an organization fixed fee with only environment basis points", () => {
    vi.stubEnv("TICKETING_FEE_BPS", "500");

    expect(() =>
      resolveTicketingFee({ ticketingFeeFixedMinor: 50 }),
    ).toThrowError(new Error("Ticketing fee is not configured"));
  });

  test(
    "rejects invalid organization basis points -1 even with valid environment settings",
    () => {
      vi.stubEnv("TICKETING_FEE_BPS", "500");
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "100");

      for (const ticketingFeeFixedMinor of [undefined, 50]) {
        expect(() =>
          resolveTicketingFee({
            ticketingFeeBps: -1,
            ticketingFeeFixedMinor,
          }),
        ).toThrowError(new Error("Ticketing fee is not configured"));
      }
    },
  );

  test(
    "rejects an invalid organization fixed fee -1 even with valid environment settings",
    () => {
      vi.stubEnv("TICKETING_FEE_BPS", "500");
      vi.stubEnv("TICKETING_FEE_FIXED_MINOR", "100");

      for (const ticketingFeeBps of [undefined, 750]) {
        expect(() =>
          resolveTicketingFee({
            ticketingFeeBps,
            ticketingFeeFixedMinor: -1,
          }),
        ).toThrowError(new Error("Ticketing fee is not configured"));
      }
    },
  );
});

describe("unitFeeMinor", () => {
  test("rounds the half minor unit up before adding the fixed fee", () => {
    expect(unitFeeMinor(1250, { bps: 500, fixedMinor: 100 })).toBe(163);
  });

  test.each([
    { unitPriceMinor: 1249, expectedFeeMinor: 162 },
    { unitPriceMinor: 1251, expectedFeeMinor: 163 },
  ])("rounds the percentage fee for $unitPriceMinor minor units", (example) => {
    expect(
      unitFeeMinor(example.unitPriceMinor, { bps: 500, fixedMinor: 100 }),
    ).toBe(example.expectedFeeMinor);
  });

  test.each([0, 100, 10000])(
    "waives even a fixed fee of %i for a free ticket",
    (fixedMinor) => {
      expect(unitFeeMinor(0, { bps: 500, fixedMinor })).toBe(0);
    },
  );

  test.each([
    { bps: 0, fixedMinor: 0, expectedFeeMinor: 0 },
    { bps: 0, fixedMinor: 100, expectedFeeMinor: 100 },
    { bps: 10000, fixedMinor: 0, expectedFeeMinor: 1250 },
  ])("allows fee boundaries $bps bps and $fixedMinor fixed", (fee) => {
    expect(unitFeeMinor(1250, fee)).toBe(fee.expectedFeeMinor);
  });

  test("rejects invalid unit price -1", () => {
    expect(() =>
      unitFeeMinor(-1, { bps: 500, fixedMinor: 100 }),
    ).toThrowError();
  });

  test(
    "rejects invalid fee basis points -1, including for free tickets",
    () => {
      for (const price of [0, 1250]) {
        expect(() =>
          unitFeeMinor(price, { bps: -1, fixedMinor: 100 }),
        ).toThrowError();
      }
    },
  );

  test(
    "rejects invalid fixed fee -1, including for free tickets",
    () => {
      for (const price of [0, 1250]) {
        expect(() =>
          unitFeeMinor(price, { bps: 500, fixedMinor: -1 }),
        ).toThrowError();
      }
    },
  );
});

describe("orderTotals", () => {
  test("multiplies the rounded per-ticket fee by quantity", () => {
    expect(
      orderTotals({
        unitPriceMinor: 1250,
        quantity: 3,
        fee: { bps: 500, fixedMinor: 100 },
      }),
    ).toEqual({
      unitFeeMinor: 163,
      subtotalMinor: 3750,
      feeMinor: 489,
      totalMinor: 4239,
    });
  });

  test("charges no fees for an order of free tickets", () => {
    expect(
      orderTotals({
        unitPriceMinor: 0,
        quantity: 3,
        fee: { bps: 500, fixedMinor: 100 },
      }),
    ).toEqual({
      unitFeeMinor: 0,
      subtotalMinor: 0,
      feeMinor: 0,
      totalMinor: 0,
    });
  });

  test.each([0, -1, 1.5, NaN, Infinity, -Infinity])(
    "rejects invalid quantity %s",
    (quantity) => {
      expect(() =>
        orderTotals({
          unitPriceMinor: 1250,
          quantity,
          fee: { bps: 500, fixedMinor: 100 },
        }),
      ).toThrowError(new Error("Quantity must be a positive integer"));
    },
  );

  test.each([
    { unitPriceMinor: -1, fee: { bps: 500, fixedMinor: 100 } },
    { unitPriceMinor: 1250, fee: { bps: 10001, fixedMinor: 100 } },
    { unitPriceMinor: 1250, fee: { bps: 500, fixedMinor: -1 } },
  ])("rejects invalid pricing or fees %j", (args) => {
    expect(() => orderTotals({ ...args, quantity: 3 })).toThrowError();
  });
});
