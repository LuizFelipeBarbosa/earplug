/// <reference types="vite/client" />
import { makeFunctionReference } from "convex/server";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc, Id } from "./_generated/dataModel";
import { StripeApiError, stripeRequest } from "./lib/stripeClient";
import schema from "./schema";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

type Snapshot = Pick<
  Doc<"financeSnapshots">,
  "availableMinor" | "pendingMinor" | "currency" | "fetchedAt"
>;

const refreshBalance = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations"> },
  Snapshot | null
>("financeActions:refreshBalance");
const exportStatement = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations">; fromMs: number; toMs: number },
  { csv: string; rows: number; truncated: boolean }
>("financeActions:exportStatement");

const modules = import.meta.glob("./**/*.ts");
const stripeMock = vi.mocked(stripeRequest);
const NOW = Date.UTC(2026, 8, 6, 12);
const FIVE_MINUTES = 5 * 60 * 1000;
const MAX_RANGE = 366 * 24 * 60 * 60 * 1000;
const HEADER = "date,type,label,amount,currency,funds_state,reference";
const ACTORS = ["owner", "manager", "finance", "door", "outsider"] as const;
type Actor = (typeof ACTORS)[number];
const STALE_SNAPSHOT: Snapshot = {
  availableMinor: 12_345,
  pendingMinor: 678,
  currency: "usd",
  fetchedAt: NOW - 2 * FIVE_MINUTES,
};

beforeEach(() => {
  stripeMock.mockReset();
  vi.spyOn(Date, "now").mockReturnValue(NOW);
});

afterEach(() => {
  vi.restoreAllMocks();
});

async function setupFinance(snapshot: Snapshot | null = null) {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) =>
    t.withIdentity({ subject: `finance_actions_${actor}` });
  const fixture = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `finance_actions_${actor}`,
        name: actor,
        email: `${actor}@finance-actions.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Finance Collective",
      slug: "finance-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager", "finance", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const privateDetailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "owner@finance-actions.test",
      contactName: "Owner",
      stripeAccountId: "acct_finance",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: NOW,
    });
    if (snapshot) {
      await ctx.db.insert("financeSnapshots", {
        organizationId,
        stripeAccountId: "acct_finance",
        ...snapshot,
      });
    }
    return { organizationId, privateDetailsId, users };
  });
  return { t, as, ...fixture };
}

async function seedLedger(
  { t, organizationId }: Awaited<ReturnType<typeof setupFinance>>,
  entries: Array<
    Pick<Doc<"ledgerEntries">, "kind" | "amountMinor" | "occurredAt"> &
      Partial<
        Pick<
          Doc<"ledgerEntries">,
          "ticketOrderId" | "stripeRef" | "currency" | "fundsState"
        >
      >
  >,
) {
  await t.run(async (ctx) => {
    await Promise.all(
      entries.map((entry, index) =>
        ctx.db.insert("ledgerEntries", {
          organizationId,
          currency: "usd",
          fundsState: "available",
          idempotencyKey: `${organizationId}:${entry.occurredAt}:${index}`,
          ...entry,
        }),
      ),
    );
  });
}

describe("refreshBalance", () => {
  test("returns a snapshot younger than five minutes without calling Stripe", async () => {
    const snapshot = {
      ...STALE_SNAPSHOT,
      fetchedAt: NOW - FIVE_MINUTES + 1,
    };
    const { as, organizationId } = await setupFinance(snapshot);

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual(snapshot);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test.each([
    { name: "missing", snapshot: null },
    {
      name: "exactly five minutes old",
      snapshot: { ...STALE_SNAPSHOT, fetchedAt: NOW - FIVE_MINUTES },
    },
    { name: "stale", snapshot: STALE_SNAPSHOT },
  ])(
    "fetches and persists a $name snapshot using only USD buckets",
    async ({ snapshot }) => {
      const { t, as, organizationId } = await setupFinance(snapshot);
      stripeMock.mockResolvedValueOnce({
        available: [
          { amount: 15_000, currency: "usd" },
          { amount: 90_000, currency: "eur" },
          { amount: -500, currency: "usd" },
        ],
        pending: [
          { amount: 5, currency: "usd" },
          { amount: 50_000, currency: "cad" },
          { amount: 995, currency: "usd" },
        ],
      });

      const expected = {
        availableMinor: 14_500,
        pendingMinor: 1000,
        currency: "usd",
        fetchedAt: NOW,
      };
      expect(
        await as("owner").action(refreshBalance, { organizationId }),
      ).toEqual(expected);
      expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
        "GET",
        "/v1/balance",
        undefined,
        { stripeAccount: "acct_finance" },
      );
      const snapshots = await t.run((ctx) =>
        ctx.db
          .query("financeSnapshots")
          .withIndex("by_organizationId", (q) =>
            q.eq("organizationId", organizationId),
          )
          .take(2),
      );
      expect(snapshots).toHaveLength(1);
      expect(snapshots[0]).toMatchObject({
        organizationId,
        stripeAccountId: "acct_finance",
        ...expected,
      });
    },
  );

  test("uses zero when balance buckets contain no USD entries", async () => {
    const { as, organizationId } = await setupFinance();
    stripeMock.mockResolvedValueOnce({
      available: [],
      pending: [{ amount: 500, currency: "eur" }],
    });

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual({
      availableMinor: 0,
      pendingMinor: 0,
      currency: "usd",
      fetchedAt: NOW,
    });
  });

  test("returns the stale snapshot unchanged when Stripe fails", async () => {
    const { t, as, organizationId } = await setupFinance(STALE_SNAPSHOT);
    stripeMock.mockRejectedValueOnce(
      new StripeApiError("Stripe unavailable", { status: 503 }),
    );

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual(STALE_SNAPSHOT);
    expect(stripeMock).toHaveBeenCalledTimes(1);
    const stored = await t.run((ctx) =>
      ctx.db
        .query("financeSnapshots")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
    );
    expect(stored).toMatchObject(STALE_SNAPSHOT);
  });

  test("rethrows Stripe failures when no snapshot exists", async () => {
    const { as, organizationId } = await setupFinance();
    stripeMock.mockRejectedValueOnce(
      new StripeApiError("Stripe unavailable", { status: 503 }),
    );

    await expect(
      as("owner").action(refreshBalance, { organizationId }),
    ).rejects.toThrow("Stripe unavailable");
  });

  test.each([null, STALE_SNAPSHOT])(
    "returns null without a connected account, even with snapshot %j",
    async (snapshot) => {
      const { t, as, organizationId, privateDetailsId } =
        await setupFinance(snapshot);
      await t.run((ctx) =>
        ctx.db.patch(privateDetailsId, { stripeAccountId: undefined }),
      );

      expect(
        await as("owner").action(refreshBalance, { organizationId }),
      ).toBeNull();
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );
});

describe("finance action access", () => {
  test.each(["manager", "door", "outsider"] as const)(
    "refuses %s access to both actions before contacting Stripe",
    async (actor) => {
      const { as, organizationId } = await setupFinance();

      await expect(
        as(actor).action(refreshBalance, { organizationId }),
      ).rejects.toThrow("Not permitted");
      await expect(
        as(actor).action(exportStatement, {
          organizationId,
          fromMs: 0,
          toMs: 1000,
        }),
      ).rejects.toThrow("Not permitted");
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test("requires authentication for both actions", async () => {
    const { t, organizationId } = await setupFinance();

    await expect(
      t.action(refreshBalance, { organizationId }),
    ).rejects.toThrow();
    await expect(
      t.action(exportStatement, { organizationId, fromMs: 0, toMs: 1000 }),
    ).rejects.toThrow();
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("allows finance members to use both actions", async () => {
    const { as, organizationId } = await setupFinance();
    stripeMock.mockResolvedValueOnce({ available: [], pending: [] });

    expect(
      await as("finance").action(refreshBalance, { organizationId }),
    ).toEqual({
      availableMinor: 0,
      pendingMinor: 0,
      currency: "usd",
      fetchedAt: NOW,
    });
    expect(
      await as("finance").action(exportStatement, {
        organizationId,
        fromMs: 0,
        toMs: 1000,
      }),
    ).toEqual({ csv: HEADER, rows: 0, truncated: false });
  });

  test("refuses both actions for a suspended organization's owner", async () => {
    const { t, as, organizationId } = await setupFinance();
    await t.run((ctx) => ctx.db.patch(organizationId, { status: "suspended" }));

    await expect(
      as("owner").action(refreshBalance, { organizationId }),
    ).rejects.toThrow("Organization suspended");
    await expect(
      as("owner").action(exportStatement, {
        organizationId,
        fromMs: 0,
        toMs: 1000,
      }),
    ).rejects.toThrow("Organization suspended");
    expect(stripeMock).not.toHaveBeenCalled();
  });
});

describe("exportStatement", () => {
  test("exports quoted labels and references, UTC dates, and signed decimal amounts", async () => {
    const setup = await setupFinance();
    const { t, as, organizationId, users } = setup;
    const ticketOrderId = await t.run(async (ctx) => {
      const venueId = await ctx.db.insert("venues", {
        name: "Neighborhood Hall",
        area: "Oakland",
        addr: "100 Main Street",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const gigId = await ctx.db.insert("gigs", {
        title: 'Friday, "Live"',
        venueId,
        price: 150,
        startsAt: 1000,
        doorsTime: "7 PM",
        flyKey: "xerox",
        lineup: [],
        genres: [],
        desc: "Local music",
        ticketing: "paid",
        createdByOrganization: organizationId,
        cap: "100",
        goingCount: 0,
      });
      return await ctx.db.insert("ticketOrders", {
        gigId,
        organizationId,
        buyerUserId: users.outsider,
        quantity: 1,
        unitPriceMinor: 15_000,
        unitFeeMinor: 0,
        subtotalMinor: 15_000,
        feeMinor: 0,
        totalMinor: 15_000,
        currency: "usd",
        status: "paid",
        reservedUntil: 1000,
        attempt: 1,
        refundedMinor: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
    });
    await seedLedger(setup, [
      { kind: "ticket_sale", amountMinor: 5, occurredAt: 3000 },
      {
        kind: "ticket_sale",
        amountMinor: 15_000,
        occurredAt: 1000,
        ticketOrderId,
        stripeRef: "pi_sale",
        fundsState: "pending",
      },
      {
        kind: "charge",
        amountMinor: 15_000,
        occurredAt: 2000,
        stripeRef: "pi_line\rbreak\nend",
      },
      { kind: "ticket_refund", amountMinor: 5, occurredAt: 4000 },
      { kind: "refund", amountMinor: 0, occurredAt: 5000, currency: "eur" },
      { kind: "ticket_sale", amountMinor: 999, occurredAt: 6000 },
    ]);

    const result = await as("owner").action(exportStatement, {
      organizationId,
      fromMs: 1000,
      toMs: 5000,
    });
    expect(result).toEqual({
      csv: [
        HEADER,
        '1970-01-01T00:00:01.000Z,ticket_sale,"Ticket sale · Friday, ""Live""",150.00,usd,pending,pi_sale',
        '1970-01-01T00:00:02.000Z,charge,Booking payment,-150.00,usd,available,"pi_line\rbreak\nend"',
        "1970-01-01T00:00:03.000Z,ticket_sale,Ticket sale,0.05,usd,available,",
        "1970-01-01T00:00:04.000Z,ticket_refund,Ticket refund,-0.05,usd,available,",
        "1970-01-01T00:00:05.000Z,refund,Booking refund,0.00,eur,available,",
      ].join("\r\n"),
      rows: 5,
      truncated: false,
    });
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("rejects a reversed range", async () => {
    const { as, organizationId } = await setupFinance();

    await expect(
      as("owner").action(exportStatement, {
        organizationId,
        fromMs: 1001,
        toMs: 1000,
      }),
    ).rejects.toThrow("fromMs must not be after toMs");
  });

  test("rejects a range exceeding 366 days", async () => {
    const { as, organizationId } = await setupFinance();

    await expect(
      as("owner").action(exportStatement, {
        organizationId,
        fromMs: 1000,
        toMs: 1000 + MAX_RANGE + 1,
      }),
    ).rejects.toThrow("one year");
  });

  test.each([0, MAX_RANGE])(
    "accepts a range spanning %i milliseconds",
    async (span) => {
      const { as, organizationId } = await setupFinance();

      expect(
        await as("owner").action(exportStatement, {
          organizationId,
          fromMs: 1000,
          toMs: 1000 + span,
        }),
      ).toEqual({ csv: HEADER, rows: 0, truncated: false });
    },
  );

  test("marks exactly 2000 returned rows as truncated", async () => {
    const setup = await setupFinance();
    await seedLedger(
      setup,
      Array.from({ length: 2001 }, (_, index) => ({
        kind: "ticket_sale" as const,
        amountMinor: 100,
        occurredAt: index,
      })),
    );

    const result = await setup.as("owner").action(exportStatement, {
      organizationId: setup.organizationId,
      fromMs: 0,
      toMs: 2000,
    });
    expect(result.rows).toBe(2000);
    expect(result.truncated).toBe(true);
    const lines = result.csv.split("\r\n");
    expect(lines).toHaveLength(2001);
    expect(lines[0]).toBe(HEADER);
    expect(lines.at(-1)).toBe(
      "1970-01-01T00:00:01.999Z,ticket_sale,Ticket sale,1.00,usd,available,",
    );
  });
});
