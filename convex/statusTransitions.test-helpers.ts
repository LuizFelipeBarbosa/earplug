import { describe, expect, test } from "vitest";

export function expectStatusTransitions<T extends string>({
  entity,
  table,
  canTransition,
  assertTransition,
  expected,
  arrow = "->",
  buildErrorMessage = (entity, from, to) =>
    `${entity} cannot go from ${from} to ${to}`,
}: {
  entity: string;
  table: Record<T, readonly T[]>;
  canTransition: (table: Record<T, readonly T[]>, from: T, to: T) => boolean;
  assertTransition: (from: T, to: T) => void;
  expected: Record<T, readonly T[]>;
  arrow?: string;
  buildErrorMessage?: (entity: string, from: T, to: T) => string;
}): void {
  describe(`${entity} transitions`, () => {
    test("declares exactly the allowed edges", () => {
      expect(table).toEqual(expected);
    });

    const statuses = Object.keys(expected) as T[];
    for (const from of statuses) {
      if (expected[from].length === 0) {
        test(`${from} is terminal`, () => {
          expect(table[from]).toEqual([]);
        });
      }

      for (const to of statuses) {
        test(`${from} ${arrow} ${to}`, () => {
          const allowed = expected[from].includes(to);
          expect(canTransition(table, from, to)).toBe(allowed);

          if (allowed) {
            expect(assertTransition(from, to)).toBeUndefined();
          } else {
            expect(() => assertTransition(from, to)).toThrowError(
              expect.objectContaining({
                message: buildErrorMessage(entity, from, to),
              }),
            );
          }
        });
      }
    }
  });
}
