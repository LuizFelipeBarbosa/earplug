/// <reference types="vite/client" />
import { makeFunctionReference } from "convex/server";
import type { Infer } from "convex/values";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc, Id } from "./_generated/dataModel";
import type { transactionValidator } from "./finance";
import { StripeApiError, stripeRequest } from "./lib/stripeClient";
import schema from "./schema";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

type StoredSnapshot = Pick<
  Doc<"financeSnapshots">,
  "availableMinor" | "pendingMinor" | "currency" | "fetchedAt"
>;

const refreshBalance = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations"> },
  (StoredSnapshot & { stale: boolean }) | null
>("financeActions:refreshBalance");
const exportStatement = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations">; fromMs: number; toMs: number },
  {
    csv: string;
    rows: number;
    truncated: boolean;
    transactions: Infer<typeof transactionValidator>[];
    totalsByKind: { kind: string; amountMinor: number; count: number }[];
  }
>("financeActions:exportStatement");

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const stripeMock = vi.mocked(stripeRequest);
const NOW = Date.UTC(2026, 8, 6, 12);
const FIVE_MINUTES = 5 * 60 * 1000;
const MAX_RANGE = 366 * 24 * 60 * 60 * 1000;
const HEADER = "date,type,label,amount,currency,funds_state,reference";
const ACTORS = ["owner", "manager", "finance", "door", "outsider"] as const;
type Actor = (typeof ACTORS)[number];
const STALE_SNAPSHOT: StoredSnapshot = {
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

async function setupFinance(
  snapshot: StoredSnapshot | null = null,
  snapshotStripeAccountId = "acct_finance",
) {
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
        stripeAccountId: snapshotStripeAccountId,
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
  return await t.run(async (ctx) => {
    return await Promise.all(
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
    ).toEqual({ ...snapshot, stale: false });
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
      ).toEqual({ ...expected, stale: false });
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
      expect(snapshots[0]).not.toHaveProperty("stale");
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
      stale: false,
    });
  });

  test.each([
    {
      name: "missing buckets",
      balance: {},
      availableMinor: 0,
      pendingMinor: 0,
    },
    {
      name: "null buckets",
      balance: { available: null, pending: null },
      availableMinor: 0,
      pendingMinor: 0,
    },
    {
      name: "a non-array available bucket",
      balance: {
        available: { amount: 100, currency: "usd" },
        pending: [{ amount: 300, currency: "usd" }],
      },
      availableMinor: 0,
      pendingMinor: 300,
    },
    {
      name: "a non-array pending bucket",
      balance: {
        available: [{ amount: 200, currency: "usd" }],
        pending: "invalid",
      },
      availableMinor: 200,
      pendingMinor: 0,
    },
  ])("uses zero for $name", async ({ balance, availableMinor, pendingMinor }) => {
    const { as, organizationId } = await setupFinance();
    stripeMock.mockResolvedValueOnce(balance);

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual({
      availableMinor,
      pendingMinor,
      currency: "usd",
      fetchedAt: NOW,
      stale: false,
    });
  });

  test("refetches a recent snapshot belonging to a previously connected account", async () => {
    const snapshot = { ...STALE_SNAPSHOT, fetchedAt: NOW - 1000 };
    const { t, as, organizationId } = await setupFinance(snapshot, "acct_old");
    stripeMock.mockResolvedValueOnce({
      available: [{ amount: 500, currency: "usd" }],
      pending: [{ amount: 100, currency: "usd" }],
    });

    const expected = {
      availableMinor: 500,
      pendingMinor: 100,
      currency: "usd",
      fetchedAt: NOW,
    };
    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual({ ...expected, stale: false });
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "GET",
      "/v1/balance",
      undefined,
      { stripeAccount: "acct_finance" },
    );
    const stored = await t.run((ctx) =>
      ctx.db
        .query("financeSnapshots")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
    );
    expect(stored).toMatchObject({ ...expected, stripeAccountId: "acct_finance" });
    expect(stored).not.toHaveProperty("stale");
  });

  test("returns a recent snapshot from the old account as stale if Stripe fails", async () => {
    const snapshot = { ...STALE_SNAPSHOT, fetchedAt: NOW - 1000 };
    const { t, as, organizationId } = await setupFinance(snapshot, "acct_old");
    const error = new StripeApiError("Stripe unavailable", { status: 503 });
    const logError = vi.spyOn(console, "error").mockImplementation(() => {});
    stripeMock.mockRejectedValueOnce(error);

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual({ ...snapshot, stale: true });
    expect(stripeMock).toHaveBeenCalledExactlyOnceWith(
      "GET",
      "/v1/balance",
      undefined,
      { stripeAccount: "acct_finance" },
    );
    expect(logError).toHaveBeenCalledWith(error);
    const stored = await t.run((ctx) =>
      ctx.db
        .query("financeSnapshots")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
    );
    expect(stored).toMatchObject({ ...snapshot, stripeAccountId: "acct_old" });
    expect(stored).not.toHaveProperty("stale");
  });

  test("returns the stored snapshot marked stale when Stripe fails", async () => {
    const { t, as, organizationId } = await setupFinance(STALE_SNAPSHOT);
    const error = new StripeApiError("Stripe unavailable", { status: 503 });
    const logError = vi.spyOn(console, "error").mockImplementation(() => {});
    stripeMock.mockRejectedValueOnce(error);

    expect(
      await as("owner").action(refreshBalance, { organizationId }),
    ).toEqual({ ...STALE_SNAPSHOT, stale: true });
    expect(stripeMock).toHaveBeenCalledTimes(1);
    expect(logError).toHaveBeenCalledWith(error);
    const stored = await t.run((ctx) =>
      ctx.db
        .query("financeSnapshots")
        .withIndex("by_organizationId", (q) =>
          q.eq("organizationId", organizationId),
        )
        .unique(),
    );
    expect(stored).toMatchObject(STALE_SNAPSHOT);
    expect(stored).not.toHaveProperty("stale");
  });

  test("rethrows Stripe failures when no snapshot exists", async () => {
    const { as, organizationId } = await setupFinance();
    const error = new StripeApiError("Stripe unavailable", { status: 503 });
    const logError = vi.spyOn(console, "error").mockImplementation(() => {});
    stripeMock.mockRejectedValueOnce(error);

    await expect(
      as("owner").action(refreshBalance, { organizationId }),
    ).rejects.toThrow("Stripe unavailable");
    expect(logError).toHaveBeenCalledWith(error);
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
      stale: false,
    });
    expect(
      await as("finance").action(exportStatement, {
        organizationId,
        fromMs: 0,
        toMs: 1000,
      }),
    ).toEqual({
      csv: HEADER,
      rows: 0,
      truncated: false,
      transactions: [],
      totalsByKind: [],
    });
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
    const ledgerIds = await seedLedger(setup, [
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
        "1970-01-01T00:00:04.000Z,ticket_refund,Ticket refund,0.05,usd,available,",
        "1970-01-01T00:00:05.000Z,refund,Booking refund,0.00,eur,available,",
      ].join("\r\n"),
      rows: 5,
      truncated: false,
      transactions: [
        {
          id: ledgerIds[1],
          kind: "ticket_sale",
          amountMinor: 15_000,
          currency: "usd",
          fundsState: "pending",
          occurredAt: 1000,
          label: 'Ticket sale · Friday, "Live"',
          ticketOrderId,
          stripeRef: "pi_sale",
        },
        {
          id: ledgerIds[2],
          kind: "charge",
          amountMinor: -15_000,
          currency: "usd",
          fundsState: "available",
          occurredAt: 2000,
          label: "Booking payment",
          stripeRef: "pi_line\rbreak\nend",
        },
        {
          id: ledgerIds[0],
          kind: "ticket_sale",
          amountMinor: 5,
          currency: "usd",
          fundsState: "available",
          occurredAt: 3000,
          label: "Ticket sale",
        },
        {
          id: ledgerIds[3],
          kind: "ticket_refund",
          amountMinor: 5,
          currency: "usd",
          fundsState: "available",
          occurredAt: 4000,
          label: "Ticket refund",
        },
        {
          id: ledgerIds[4],
          kind: "refund",
          amountMinor: -0,
          currency: "eur",
          fundsState: "available",
          occurredAt: 5000,
          label: "Booking refund",
        },
      ],
      totalsByKind: [
        { kind: "charge", amountMinor: -15_000, count: 1 },
        { kind: "refund", amountMinor: 0, count: 1 },
        { kind: "ticket_refund", amountMinor: 5, count: 1 },
        { kind: "ticket_sale", amountMinor: 15_005, count: 2 },
      ],
    });
    expect(result.transactions).toHaveLength(result.rows);
    expect(stripeMock).not.toHaveBeenCalled();
  });

  test("totals each distinct transaction kind in ascending order", async () => {
    const setup = await setupFinance();
    await seedLedger(setup, [
      { kind: "ticket_sale", amountMinor: 1500, occurredAt: 1000 },
      { kind: "refund", amountMinor: 500, occurredAt: 2000 },
      { kind: "charge", amountMinor: 1000, occurredAt: 3000 },
      { kind: "ticket_sale", amountMinor: 2500, occurredAt: 4000 },
      { kind: "charge", amountMinor: 2000, occurredAt: 5000 },
      { kind: "commission", amountMinor: 300, occurredAt: 6000 },
    ]);

    const result = await setup.as("owner").action(exportStatement, {
      organizationId: setup.organizationId,
      fromMs: 1000,
      toMs: 6000,
    });
    const kinds = [...new Set(result.transactions.map((row) => row.kind))].sort();
    expect(result.totalsByKind).toEqual(
      kinds.map((kind) => {
        const transactions = result.transactions.filter(
          (row) => row.kind === kind,
        );
        return {
          kind,
          amountMinor: transactions.reduce((sum, row) => sum + row.amountMinor, 0),
          count: transactions.length,
        };
      }),
    );
    expect(result.transactions).toHaveLength(5);
    expect(result.transactions).toHaveLength(result.rows);
  });

  test.each([
    ["=SUM(1)", `"'=SUM(1)"`],
    ["+SUM(1)", `"'+SUM(1)"`],
    ["-SUM(1)", `"'-SUM(1)"`],
    ["@SUM(1)", `"'@SUM(1)"`],
    ["\tSUM(1)", `"'\tSUM(1)"`],
    ["\rSUM(1)", `"'\rSUM(1)"`],
    ['=SUM("1",2)', `"'=SUM(""1"",2)"`],
  ])(
    "escapes formula-like reference %j while leaving negative amounts unquoted",
    async (stripeRef, expectedReference) => {
      const setup = await setupFinance();
      await seedLedger(setup, [
        { kind: "charge", amountMinor: 15_000, occurredAt: 1000, stripeRef },
      ]);

      const result = await setup.as("owner").action(exportStatement, {
        organizationId: setup.organizationId,
        fromMs: 1000,
        toMs: 1000,
      });
      expect(result).toEqual({
        csv: `${HEADER}\r\n1970-01-01T00:00:01.000Z,charge,Booking payment,-150.00,usd,available,${expectedReference}`,
        rows: 1,
        truncated: false,
        transactions: [
          {
            id: expect.any(String),
            kind: "charge",
            amountMinor: -15_000,
            currency: "usd",
            fundsState: "available",
            occurredAt: 1000,
            label: "Booking payment",
            stripeRef,
          },
        ],
        totalsByKind: [{ kind: "charge", amountMinor: -15_000, count: 1 }],
      });
    },
  );

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
      ).toEqual({
        csv: HEADER,
        rows: 0,
        truncated: false,
        transactions: [],
        totalsByKind: [],
      });
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
    expect(result.transactions).toHaveLength(result.rows);
    expect(result.totalsByKind).toEqual([
      { kind: "ticket_sale", amountMinor: 200_000, count: 2000 },
    ]);
    const lines = result.csv.split("\r\n");
    expect(lines).toHaveLength(2001);
    expect(lines[0]).toBe(HEADER);
    expect(lines.at(-1)).toBe(
      "1970-01-01T00:00:01.999Z,ticket_sale,Ticket sale,1.00,usd,available,",
    );
  });

  test("marks 2000 source entries truncated even when hidden kinds reduce the CSV row count", async () => {
    const setup = await setupFinance();
    await seedLedger(
      setup,
      Array.from({ length: 2000 }, (_, index) => ({
        kind: index % 10 === 0 ? ("commission" as const) : ("ticket_sale" as const),
        amountMinor: 100,
        occurredAt: index,
      })),
    );

    const result = await setup.as("owner").action(exportStatement, {
      organizationId: setup.organizationId,
      fromMs: 0,
      toMs: 1999,
    });
    expect(result.rows).toBe(1800);
    expect(result.truncated).toBe(true);
    expect(result.transactions).toHaveLength(result.rows);
    expect(result.totalsByKind).toEqual([
      { kind: "ticket_sale", amountMinor: 180_000, count: 1800 },
    ]);
    expect(result.csv.split("\r\n")).toHaveLength(1801);
  });
});
