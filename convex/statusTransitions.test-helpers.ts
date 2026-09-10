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
  const statuses = Object.keys(expected) as T[];

  const allowedFrom = statuses.find((status) => expected[status].length > 0);
  if (allowedFrom === undefined) {
    throw new Error(`${entity}: expected at least one non-terminal status`);
  }
  const allowedTo = expected[allowedFrom][0];

  const deniedFrom =
    statuses.find((status) => expected[status].length === 0) ?? statuses[0];
  const deniedTo = statuses.find(
    (status) => !expected[deniedFrom].includes(status),
  );
  if (deniedTo === undefined) {
    throw new Error(`${entity}: expected at least one denied edge`);
  }

  describe(`${entity} transitions`, () => {
    test("declares exactly the allowed edges", () => {
      expect(table).toEqual(expected);
    });

    test(`${allowedFrom} ${arrow} ${allowedTo}`, () => {
      expect(canTransition(table, allowedFrom, allowedTo)).toBe(true);
      expect(assertTransition(allowedFrom, allowedTo)).toBeUndefined();
    });

    test(`${deniedFrom} ${arrow} ${deniedTo}`, () => {
      expect(canTransition(table, deniedFrom, deniedTo)).toBe(false);
      expect(() => assertTransition(deniedFrom, deniedTo)).toThrowError(
        expect.objectContaining({
          message: buildErrorMessage(entity, deniedFrom, deniedTo),
        }),
      );
    });
  });
}
