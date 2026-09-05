import { describe, expect, test } from "vitest";
import {
  describeTemplate,
  refundShareBps,
  settleCancellation,
  type CancellationTemplate,
} from "./lib/cancellationPolicy";

const DAY_MS = 24 * 60 * 60 * 1000;
const templates: readonly CancellationTemplate[] = [
  "flexible",
  "standard",
  "strict",
];

describe("refundShareBps", () => {
  test.each([
    ["flexible", 20, 10_000],
    ["flexible", 10, 10_000],
    ["flexible", 3, 10_000],
    ["flexible", 1, 0],
    ["standard", 20, 10_000],
    ["standard", 10, 5000],
    ["standard", 3, 0],
    ["standard", 1, 0],
    ["strict", 20, 10_000],
    ["strict", 10, 0],
    ["strict", 3, 0],
    ["strict", 1, 0],
  ] as const)("%s at %i days returns %i basis points", (template, days, share) => {
    expect(refundShareBps(template, days * DAY_MS)).toBe(share);
  });

  test.each([
    ["flexible", 2, 0, 10_000],
    ["standard", 14, 5000, 10_000],
    ["standard", 7, 0, 5000],
    ["strict", 14, 0, 10_000],
  ] as const)(
    "%s requires strictly more than %i days for the higher refund",
    (template, days, atCutoff, beforeCutoff) => {
      const cutoffMs = days * DAY_MS;
      expect(refundShareBps(template, cutoffMs - 1)).toBe(atCutoff);
      expect(refundShareBps(template, cutoffMs)).toBe(atCutoff);
      expect(refundShareBps(template, cutoffMs + 1)).toBe(beforeCutoff);
    },
  );

  test.each(templates)("%s gives no refund at or after show start", (template) => {
    expect(refundShareBps(template, 0)).toBe(0);
    expect(refundShareBps(template, -DAY_MS)).toBe(0);
  });
});

describe("settleCancellation", () => {
  test.each([
    ["flexible", 20, 20_000, 0, 0, 0],
    ["flexible", 10, 20_000, 0, 0, 0],
    ["flexible", 3, 20_000, 0, 0, 0],
    ["flexible", 1, 0, 20_000, 18_000, 2000],
    ["standard", 20, 20_000, 0, 0, 0],
    ["standard", 10, 10_000, 10_000, 9000, 1000],
    ["standard", 3, 0, 20_000, 18_000, 2000],
    ["standard", 1, 0, 20_000, 18_000, 2000],
    ["strict", 20, 20_000, 0, 0, 0],
    ["strict", 10, 0, 20_000, 18_000, 2000],
    ["strict", 3, 0, 20_000, 18_000, 2000],
    ["strict", 1, 0, 20_000, 18_000, 2000],
  ] as const)(
    "%s settles an organizer cancellation at %i days",
    (
      template,
      days,
      refundMinor,
      forfeitedMinor,
      artistPayoutMinor,
      platformKeepsMinor,
    ) => {
      expect(
        settleCancellation({
          template,
          msBeforeStart: days * DAY_MS,
          cancelledBy: "organizer",
          paidMinor: 20_000,
          artistNetMinor: 18_000,
          commissionMinor: 2000,
        }),
      ).toEqual({
        refundMinor,
        forfeitedMinor,
        artistPayoutMinor,
        platformKeepsMinor,
      });
    },
  );

  for (const template of templates) {
    describe(template, () => {
      for (const cancelledBy of ["artist", "admin", "system"] as const) {
        test.each([20, 10, 3, 1, 0, -1])(
          `${cancelledBy} refunds everything at %i days`,
          (days) => {
            expect(
              settleCancellation({
                template,
                msBeforeStart: days * DAY_MS,
                cancelledBy,
                paidMinor: 4001,
                artistNetMinor: 18_000,
                commissionMinor: 2000,
              }),
            ).toEqual({
              refundMinor: 4001,
              forfeitedMinor: 0,
              artistPayoutMinor: 0,
              platformKeepsMinor: 0,
            });
          },
        );
      }

      test.each([20, 10, 3, 1])("zero paid settles to zero at %i days", (days) => {
        expect(
          settleCancellation({
            template,
            msBeforeStart: days * DAY_MS,
            cancelledBy: "organizer",
            paidMinor: 0,
            artistNetMinor: 18_000,
            commissionMinor: 2000,
          }),
        ).toEqual({
          refundMinor: 0,
          forfeitedMinor: 0,
          artistPayoutMinor: 0,
          platformKeepsMinor: 0,
        });
      });
    });
  }

  test("rounds an odd half-refund up and splits only the remaining forfeiture", () => {
    expect(
      settleCancellation({
        template: "standard",
        msBeforeStart: 10 * DAY_MS,
        cancelledBy: "organizer",
        paidMinor: 101,
        artistNetMinor: 900,
        commissionMinor: 100,
      }),
    ).toEqual({
      refundMinor: 51,
      forfeitedMinor: 50,
      artistPayoutMinor: 45,
      platformKeepsMinor: 5,
    });
  });

  test("rounds an exact half minor unit of forfeiture commission up", () => {
    expect(
      settleCancellation({
        template: "strict",
        msBeforeStart: DAY_MS,
        cancelledBy: "organizer",
        paidMinor: 5,
        artistNetMinor: 90,
        commissionMinor: 10,
      }),
    ).toEqual({
      refundMinor: 0,
      forfeitedMinor: 5,
      artistPayoutMinor: 4,
      platformKeepsMinor: 1,
    });
  });

  test("rounds an exact half basis point of the reconstructed commission rate up", () => {
    expect(
      settleCancellation({
        template: "strict",
        msBeforeStart: DAY_MS,
        cancelledBy: "organizer",
        paidMinor: 20_000,
        artistNetMinor: 19_999,
        commissionMinor: 1,
      }),
    ).toEqual({
      refundMinor: 0,
      forfeitedMinor: 20_000,
      artistPayoutMinor: 19_998,
      platformKeepsMinor: 2,
    });
  });

  test.each([
    [20, 4000, 0, 0, 0],
    [10, 2000, 2000, 1800, 200],
    [3, 0, 4000, 3600, 400],
  ])(
    "settles a partial payment at %i days using paid funds and the gross commission rate",
    (days, refundMinor, forfeitedMinor, artistPayoutMinor, platformKeepsMinor) => {
      expect(
        settleCancellation({
          template: "standard",
          msBeforeStart: days * DAY_MS,
          cancelledBy: "organizer",
          paidMinor: 4000,
          artistNetMinor: 18_000,
          commissionMinor: 2000,
        }),
      ).toEqual({
        refundMinor,
        forfeitedMinor,
        artistPayoutMinor,
        platformKeepsMinor,
      });
    },
  );

  test.each([0, 500])("zero reconstructed gross has no commission for %i paid", (paidMinor) => {
    expect(
      settleCancellation({
        template: "strict",
        msBeforeStart: DAY_MS,
        cancelledBy: "organizer",
        paidMinor,
        artistNetMinor: 0,
        commissionMinor: 0,
      }),
    ).toEqual({
      refundMinor: 0,
      forfeitedMinor: paidMinor,
      artistPayoutMinor: paidMinor,
      platformKeepsMinor: 0,
    });
  });

  test.each([
    [100, 0, 100, 0],
    [0, 100, 0, 100],
  ])(
    "bounds the payout for artist net %i and commission %i",
    (artistNetMinor, commissionMinor, artistPayoutMinor, platformKeepsMinor) => {
      expect(
        settleCancellation({
          template: "strict",
          msBeforeStart: DAY_MS,
          cancelledBy: "organizer",
          paidMinor: 100,
          artistNetMinor,
          commissionMinor,
        }),
      ).toEqual({
        refundMinor: 0,
        forfeitedMinor: 100,
        artistPayoutMinor,
        platformKeepsMinor,
      });
    },
  );
});

describe("describeTemplate", () => {
  test.each([
    ["flexible", "Full refund up until 48 hours before the show."],
    [
      "standard",
      "Full refund up until 14 days before the show, 50% refund from 14 to 7 days before, no refund inside 7 days.",
    ],
    [
      "strict",
      "Full refund up until 14 days before the show, no refund inside 14 days.",
    ],
  ] as const)("%s describes the policy verbatim", (template, description) => {
    expect(describeTemplate(template)).toBe(description);
  });
});
