/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Doc } from "./_generated/dataModel";
import {
  applyTicketInventoryCapacity,
  ensureInventory,
} from "./lib/ticketInventory";
import {
  assertSellerOpen,
  resolveOrderSeller,
  resolveTicketSeller,
  sellerRefFields,
  type TicketSeller,
  type TicketSellerKind,
} from "./lib/ticketSeller";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-08T12:00:00Z");

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

async function setupSeller(kind: TicketSellerKind = "organization") {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const ownerUserId = await ctx.db.insert("users", {
      clerkId: "seller_owner",
      name: "Owner",
      email: "owner@seller.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Ticket Collective",
      slug: "ticket-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId,
      ticketingFeeBps: 500,
      ticketingFeeFixedMinor: 30,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const privateDetailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: "owner@seller.test",
      contactName: "Owner",
      stripeAccountId: "acct_organization",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: true,
      stripeDetailsSubmitted: true,
      verificationDocStorageIds: [],
      updatedAt: NOW,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Static Bloom",
      slug: "static-bloom",
      genres: ["Indie"],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "SB",
      followerCount: 0,
      pastShows: [],
    });
    const payoutAccountId = await ctx.db.insert("bandPayoutAccounts", {
      bandId,
      stripeAccountId: "acct_band",
      chargesEnabled: true,
      cardPaymentsStatus: "active",
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: [],
      updatedAt: NOW,
    });
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
      title: "Friday at the Hall",
      venueId,
      price: 20,
      startsAt: NOW + 7 * 24 * 60 * 60_000,
      doorsTime: "7 PM",
      flyKey: "xerox",
      lineup: [bandId],
      genres: ["Indie"],
      desc: "Live music",
      ticketing: "paid",
      ticketPriceMinor: 2000,
      ticketCurrency: "usd",
      ticketCapacity: 100,
      ownerKind: kind,
      ...(kind === "organization"
        ? { createdByOrganization: organizationId }
        : { createdByBand: bandId }),
      cap: "100",
      goingCount: 0,
    });
    return { organizationId, privateDetailsId, bandId, payoutAccountId, gigId };
  });
  const resolveGig = () =>
    t.run(async (ctx) => {
      const gig = await ctx.db.get(ids.gigId);
      if (!gig) throw new Error("Fixture gig missing");
      return await resolveTicketSeller(ctx, gig);
    });
  return { t, ...ids, resolveGig };
}

describe("resolveTicketSeller", () => {
  test.each(["verified", "suspended"] as const)(
    "resolves a %s organization with its fee overrides and payment details",
    async (status) => {
      const f = await setupSeller();
      await f.t.run((ctx) => ctx.db.patch(f.organizationId, { status }));

      expect(await f.resolveGig()).toEqual({
        kind: "organization",
        organizationId: f.organizationId,
        name: "Ticket Collective",
        stripeAccountId: "acct_organization",
        chargesEnabled: true,
        suspended: status === "suspended",
        feeSource: { ticketingFeeBps: 500, ticketingFeeFixedMinor: 30 },
      });
    },
  );

  test("defaults missing organization details and fee overrides", async () => {
    const f = await setupSeller();
    await f.t.run(async (ctx) => {
      await ctx.db.delete(f.privateDetailsId);
      await ctx.db.patch(f.organizationId, {
        ticketingFeeBps: undefined,
        ticketingFeeFixedMinor: undefined,
      });
    });

    const seller = await f.resolveGig();
    expect(seller).toMatchObject({
      stripeAccountId: null,
      chargesEnabled: false,
      suspended: false,
    });
    expect(seller?.feeSource).toEqual({});
  });

  test("prefers an organization creator even when band ownership is set", async () => {
    const f = await setupSeller();
    await f.t.run((ctx) =>
      ctx.db.patch(f.gigId, { createdByBand: f.bandId, ownerKind: "band" }),
    );
    expect(await f.resolveGig()).toMatchObject({
      kind: "organization",
      organizationId: f.organizationId,
    });
    await f.t.run((ctx) => ctx.db.delete(f.organizationId));
    expect(await f.resolveGig()).toBeNull();
  });

  test.each([undefined, "organization", "band"] as const)(
    "resolves a band creator when ownerKind is %s",
    async (ownerKind) => {
      const f = await setupSeller("band");
      await f.t.run((ctx) => ctx.db.patch(f.gigId, { ownerKind }));

      expect(await f.resolveGig()).toEqual({
        kind: "band",
        bandId: f.bandId,
        name: "Static Bloom",
        stripeAccountId: "acct_band",
        chargesEnabled: true,
        suspended: false,
        feeSource: {},
      });
    },
  );

  test("defaults a band's missing payout account to unavailable", async () => {
    const f = await setupSeller("band");
    await f.t.run((ctx) => ctx.db.delete(f.payoutAccountId));
    expect(await f.resolveGig()).toMatchObject({
      stripeAccountId: null,
      chargesEnabled: false,
    });
  });

  test.each([undefined, "pending", "inactive", "unrequested"])(
    "blocks band charges when card payments status is %s",
    async (cardPaymentsStatus) => {
      const f = await setupSeller("band");
      await f.t.run((ctx) =>
        ctx.db.patch(f.payoutAccountId, { cardPaymentsStatus }),
      );
      const seller = await f.resolveGig();
      if (!seller) throw new Error("Expected a band seller");
      expect(seller.chargesEnabled).toBe(false);
      expect(() => assertSellerOpen(seller)).toThrow(
        "This band is not ready to sell tickets yet",
      );
    },
  );

  test.each(["organization", "band"] as const)(
    "reflects disabled charges for a %s seller",
    async (kind) => {
      const f = await setupSeller(kind);
      await f.t.run(async (ctx) => {
        await ctx.db.patch(f.privateDetailsId, { stripeChargesEnabled: false });
        await ctx.db.patch(f.payoutAccountId, { chargesEnabled: false });
      });
      expect((await f.resolveGig())?.chargesEnabled).toBe(false);
    },
  );

  test("marks an archived band as suspended", async () => {
    const f = await setupSeller("band");
    await f.t.run((ctx) => ctx.db.patch(f.bandId, { archivedAt: NOW }));
    expect((await f.resolveGig())?.suspended).toBe(true);
  });

  test("returns null when the band row is missing", async () => {
    const f = await setupSeller("band");
    await f.t.run((ctx) => ctx.db.delete(f.bandId));
    expect(await f.resolveGig()).toBeNull();
  });

  test.each([undefined, "band"] as const)(
    "returns null without a concrete seller even when ownerKind is %s",
    async (ownerKind) => {
      const f = await setupSeller("band");
      await f.t.run((ctx) =>
        ctx.db.patch(f.gigId, { createdByBand: undefined, ownerKind }),
      );
      expect(await f.resolveGig()).toBeNull();
    },
  );
});

describe("resolveOrderSeller", () => {
  test.each(["band", "organization"] as const)(
    "honors sellerKind %s when both seller IDs are set",
    async (sellerKind) => {
      const f = await setupSeller("band");
      expect(
        await f.t.run((ctx) =>
          resolveOrderSeller(ctx, {
            gigId: f.gigId,
            sellerKind,
            organizationId: f.organizationId,
            bandId: f.bandId,
          }),
        ),
      ).toMatchObject(
        sellerKind === "band"
          ? { kind: "band", bandId: f.bandId }
          : { kind: "organization", organizationId: f.organizationId },
      );
    },
  );

  test("rejects ambiguous legacy orders with both seller IDs", async () => {
    const f = await setupSeller("band");
    expect(
      await f.t.run((ctx) =>
        resolveOrderSeller(ctx, {
          gigId: f.gigId,
          organizationId: f.organizationId,
          bandId: f.bandId,
        }),
      ),
    ).toBeNull();
  });

  test("resolves a legacy order's sole seller ID, then falls back to its gig", async () => {
    const f = await setupSeller("band");
    await f.t.run(async (ctx) => {
      const bandOrder = { gigId: f.gigId, bandId: f.bandId };
      const organizationOrder = {
        gigId: f.gigId,
        organizationId: f.organizationId,
      };
      expect(await resolveOrderSeller(ctx, bandOrder)).toMatchObject({
        kind: "band",
        bandId: f.bandId,
      });
      expect(
        await resolveOrderSeller(ctx, organizationOrder),
      ).toMatchObject({ kind: "organization", organizationId: f.organizationId });
      expect(await resolveOrderSeller(ctx, { gigId: f.gigId })).toMatchObject({
        kind: "band",
        bandId: f.bandId,
      });
      await ctx.db.patch(f.gigId, { createdByOrganization: f.organizationId });
      expect(await resolveOrderSeller(ctx, { gigId: f.gigId })).toMatchObject({
        kind: "organization",
        organizationId: f.organizationId,
      });

      await ctx.db.delete(f.gigId);
      expect(await resolveOrderSeller(ctx, bandOrder)).toMatchObject({
        kind: "band",
      });
      expect(await resolveOrderSeller(ctx, organizationOrder)).toMatchObject({
        kind: "organization",
      });
      expect(await resolveOrderSeller(ctx, { gigId: f.gigId })).toBeNull();
    });
  });

  test.each(["band", "organization"] as const)(
    "does not fall back when sellerKind %s has no matching seller ID",
    async (sellerKind) => {
      const f = await setupSeller(
        sellerKind === "band" ? "organization" : "band",
      );
      await f.t.run(async (ctx) => {
        expect(
          await resolveOrderSeller(ctx, {
            gigId: f.gigId,
            sellerKind,
            organizationId:
              sellerKind === "band" ? f.organizationId : undefined,
            bandId: sellerKind === "organization" ? f.bandId : undefined,
          }),
        ).toBeNull();
        expect(
          await resolveOrderSeller(ctx, { gigId: f.gigId, sellerKind }),
        ).toBeNull();
      });
    },
  );

  test("does not fall back when the order's explicit seller is missing", async () => {
    const f = await setupSeller();
    await f.t.run(async (ctx) => {
      await ctx.db.delete(f.bandId);
      expect(
        await resolveOrderSeller(ctx, {
          gigId: f.gigId,
          sellerKind: "band",
          bandId: f.bandId,
          organizationId: f.organizationId,
        }),
      ).toBeNull();
      expect(
        await resolveOrderSeller(ctx, { gigId: f.gigId, bandId: f.bandId }),
      ).toBeNull();
    });
    const bandGig = await setupSeller("band");
    await bandGig.t.run(async (ctx) => {
      await ctx.db.delete(bandGig.organizationId);
      expect(
        await resolveOrderSeller(ctx, {
          gigId: bandGig.gigId,
          sellerKind: "organization",
          organizationId: bandGig.organizationId,
          bandId: bandGig.bandId,
        }),
      ).toBeNull();
      expect(
        await resolveOrderSeller(ctx, {
          gigId: bandGig.gigId,
          organizationId: bandGig.organizationId,
        }),
      ).toBeNull();
    });
  });
});

describe.each(["organization", "band"] as const)("%s seller guards", (kind) => {
  const openSeller: TicketSeller = {
    kind,
    name: "Seller",
    stripeAccountId: "acct_seller",
    chargesEnabled: true,
    suspended: false,
    feeSource: {},
  };

  test.each([
    { stripeAccountId: null },
    { chargesEnabled: false },
    { suspended: true },
  ])("rejects an unavailable seller: %o", (overrides) => {
    expect(() => assertSellerOpen({ ...openSeller, ...overrides })).toThrow(
      kind === "organization"
        ? "This organizer is not ready to sell tickets yet"
        : "This band is not ready to sell tickets yet",
    );
  });

  test("accepts an open seller", () => {
    expect(() => assertSellerOpen(openSeller)).not.toThrow();
  });

  test("includes only the chosen seller's reference fields", async () => {
    const f = await setupSeller(kind);
    const seller = await f.resolveGig();
    if (!seller) throw new Error("Expected a seller");
    expect(
      sellerRefFields({
        ...seller,
        organizationId: f.organizationId,
        bandId: f.bandId,
      }),
    ).toEqual(
      kind === "organization"
        ? { sellerKind: "organization", organizationId: f.organizationId }
        : { sellerKind: "band", bandId: f.bandId },
    );
  });
});

describe("seller ticket inventory", () => {
  test("creates band inventory without an organization reference", async () => {
    const f = await setupSeller("band");
    await f.t.run(async (ctx) => {
      const gig = (await ctx.db.get(f.gigId))!;
      const inventory = await ensureInventory(ctx, gig);
      expect(inventory).toMatchObject({
        gigId: f.gigId,
        sellerKind: "band",
        bandId: f.bandId,
        capacity: 100,
        sold: 0,
        reserved: 0,
        updatedAt: NOW,
      });
      expect(inventory).not.toHaveProperty("organizationId");
      expect(await ensureInventory(ctx, gig)).toEqual(inventory);
    });
  });

  test.each([
    { ticketing: "rsvp" },
    { ticketCapacity: undefined },
    { createdByBand: undefined },
  ] satisfies Partial<Doc<"gigs">>[])(
    "rejects inventory creation when the gig cannot sell tickets: %o",
    async (patch) => {
      const f = await setupSeller("band");
      await f.t.run((ctx) => ctx.db.patch(f.gigId, patch));
      await expect(
        f.t.run(async (ctx) => ensureInventory(ctx, (await ctx.db.get(f.gigId))!)),
      ).rejects.toThrow("This event is not selling tickets");
    },
  );

  test("applies band capacity without reducing sold or reserved inventory", async () => {
    const f = await setupSeller("band");
    const seller = await f.resolveGig();
    if (!seller) throw new Error("Expected a band seller");
    await f.t.run(async (ctx) => {
      await applyTicketInventoryCapacity(ctx, f.gigId, seller, 10);
      const inventory = await ctx.db
        .query("gigTicketInventory")
        .withIndex("by_gigId", (q) => q.eq("gigId", f.gigId))
        .unique();
      expect(inventory).toMatchObject({
        sellerKind: "band",
        bandId: f.bandId,
        capacity: 10,
        sold: 0,
        reserved: 0,
      });
      expect(inventory).not.toHaveProperty("organizationId");
      if (!inventory) throw new Error("Expected ticket inventory");
      await ctx.db.patch(inventory._id, { sold: 3, reserved: 2 });

      vi.setSystemTime(NOW + 1000);
      await applyTicketInventoryCapacity(ctx, f.gigId, seller, 4);
      expect(await ctx.db.get(inventory._id)).toMatchObject({
        sellerKind: "band",
        bandId: f.bandId,
        capacity: 5,
        sold: 3,
        reserved: 2,
        updatedAt: NOW + 1000,
      });
      await applyTicketInventoryCapacity(ctx, f.gigId, seller, 20);
      expect((await ctx.db.get(inventory._id))?.capacity).toBe(20);
    });
  });

  test("rejects reusing a band's inventory for a different seller", async () => {
    const f = await setupSeller("band");
    await f.t.run(async (ctx) => {
      await ensureInventory(ctx, (await ctx.db.get(f.gigId))!);
      await ctx.db.patch(f.gigId, { createdByOrganization: f.organizationId });
    });
    await expect(
      f.t.run(async (ctx) => ensureInventory(ctx, (await ctx.db.get(f.gigId))!)),
    ).rejects.toThrow("This event is not selling tickets");
  });

  test("rejects a missing capacity", async () => {
    const f = await setupSeller("band");
    const seller = await f.resolveGig();
    if (!seller) throw new Error("Expected a band seller");
    await expect(
      f.t.run((ctx) => applyTicketInventoryCapacity(ctx, f.gigId, seller, undefined)),
    ).rejects.toThrow("Paid opportunity is missing a ticket capacity");
  });
});
