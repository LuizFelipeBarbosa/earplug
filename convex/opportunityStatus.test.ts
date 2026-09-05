import { describe, expect, test } from "vitest";
import {
  APPLICATION_ACTIVE_STATUSES,
  APPLICATION_TRANSITIONS,
  OPPORTUNITY_ARTIST_VISIBLE_STATUSES,
  OPPORTUNITY_TRANSITIONS,
  SLOT_TRANSITIONS,
  assertApplicationTransition,
  assertOpportunityTransition,
  assertSlotTransition,
  canTransition,
} from "./lib/opportunityStatus";

function testStatusTransitions<T extends string>(
  entity: string,
  table: Record<T, readonly T[]>,
  assertTransition: (from: T, to: T) => void,
  expectedTransitions: Record<T, readonly T[]>,
) {
  describe(`${entity} transitions`, () => {
    test("declares exactly the allowed edges", () => {
      expect(table).toEqual(expectedTransitions);
    });

    const statuses = Object.keys(expectedTransitions) as T[];
    for (const from of statuses) {
      if (expectedTransitions[from].length === 0) {
        test(`${from} is terminal`, () => {
          expect(table[from]).toEqual([]);
        });
      }

      for (const to of statuses) {
        test(`${from} -> ${to}`, () => {
          const allowed = expectedTransitions[from].includes(to);
          expect(canTransition(table, from, to)).toBe(allowed);

          if (allowed) {
            expect(assertTransition(from, to)).toBeUndefined();
          } else {
            expect(() => assertTransition(from, to)).toThrowError(
              expect.objectContaining({
                message: `${entity} cannot go from ${from} to ${to}`,
              }),
            );
          }
        });
      }
    }
  });
}

testStatusTransitions(
  "Opportunity",
  OPPORTUNITY_TRANSITIONS,
  assertOpportunityTransition,
  {
    draft: ["open", "cancelled"],
    open: ["applications_closed", "cancelled"],
    applications_closed: ["open", "booking", "cancelled"],
    booking: ["confirmed", "applications_closed", "cancelled"],
    confirmed: ["completed", "cancelled", "booking"],
    completed: [],
    cancelled: [],
  },
);

testStatusTransitions(
  "Application",
  APPLICATION_TRANSITIONS,
  assertApplicationTransition,
  {
    submitted: ["under_review", "shortlisted", "declined", "withdrawn", "expired"],
    under_review: ["shortlisted", "declined", "withdrawn", "expired"],
    shortlisted: ["offered", "declined", "withdrawn", "expired"],
    offered: ["booked", "declined", "withdrawn", "expired", "shortlisted"],
    booked: [],
    declined: [],
    withdrawn: [],
    expired: [],
  },
);

testStatusTransitions("Slot", SLOT_TRANSITIONS, assertSlotTransition, {
  open: ["booked", "cancelled"],
  booked: ["open", "cancelled"],
  cancelled: [],
});

test("application active statuses have the expected order", () => {
  expect(APPLICATION_ACTIVE_STATUSES).toEqual([
    "submitted",
    "under_review",
    "shortlisted",
    "offered",
  ]);
});

test("opportunity artist-visible statuses have the expected order", () => {
  expect(OPPORTUNITY_ARTIST_VISIBLE_STATUSES).toEqual([
    "open",
    "applications_closed",
    "booking",
    "confirmed",
  ]);
});
