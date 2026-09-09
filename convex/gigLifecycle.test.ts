import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import schema from "./schema";

async function setupLifecycle() {
  const t = convexTest(schema);
  const asAdmin = t.withIdentity({
    subject: "gig_admin",
    email: "admin@x.com",
  });
  await asAdmin.mutation(api.users.ensureUser, {});
  const { bandId } = await asAdmin.mutation(api.bands.createBand, {
    name: "Draft Mechanics",
    genres: ["punk"],
    bio: "",
    area: "Bay Area",
    inviteHandles: [],
  });
  const venueId = await t.run(async (ctx) =>
    ctx.db.insert("venues", {
      name: "Lifecycle Hall",
      area: "Oakland",
      addr: "1 Draft Way",
      distSF: "7 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.2,
    }),
  );
  return { t, asAdmin, bandId, venueId };
}

describe("paid band gig drafts and publishing", () => {
  async function setupPaidDraft(
    payout: { chargesEnabled: boolean; cardPaymentsStatus?: string } | null = {
      chargesEnabled: true,
      cardPaymentsStatus: "active",
    },
  ) {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    if (payout) {
      await t.run(async (ctx) =>
        ctx.db.insert("bandPayoutAccounts", {
          bandId,
          stripeAccountId: "acct_test",
          ...payout,
          payoutsEnabled: true,
          detailsSubmitted: true,
          requirementsDue: [],
          updatedAt: Date.now(),
        }),
      );
    }
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const saveArgs = {
      projectId: draft._id,
      revision: draft.revision,
      title: "Paid Band Show",
      doorsAt,
      startsAt: doorsAt + 60 * 60_000,
      venueId,
      price: 99,
      flyKey: "xerox" as const,
      flyStorageId: null,
      overlay: true,
      desc: "Tickets sold by the band.",
      ticketing: "paid" as const,
      ticketPriceMinor: 1250,
      ticketCapacity: 100,
      ageRequirement: "allAges" as const,
      externalUrl: null,
      cap: "No cap",
    };
    return { t, asAdmin, bandId, draft, saveArgs };
  }

  test.each([
    { name: "no payout account", payout: null },
    {
      name: "charges disabled",
      payout: { chargesEnabled: false, cardPaymentsStatus: "active" },
    },
    {
      name: "card payments pending",
      payout: { chargesEnabled: true, cardPaymentsStatus: "pending" },
    },
    {
      name: "card payments inactive",
      payout: { chargesEnabled: true, cardPaymentsStatus: "inactive" },
    },
    {
      name: "card payments status missing",
      payout: { chargesEnabled: true },
    },
  ])("refuses a paid draft with $name", async ({ payout }) => {
    const { asAdmin, saveArgs } = await setupPaidDraft(payout);

    await expect(
      asAdmin.mutation(api.gigs.saveDraft, saveArgs),
    ).rejects.toThrow("Enable ticket sales in PAYOUTS first");
  });

  test.each([
    {
      name: "price below $1.00",
      fields: { ticketPriceMinor: 99 },
      error: "Ticket price must be at least $1.00",
    },
    {
      name: "fractional price",
      fields: { ticketPriceMinor: 100.5 },
      error: "Ticket price must be at least $1.00",
    },
    {
      name: "zero capacity",
      fields: { ticketCapacity: 0 },
      error: "Ticket capacity must be between 1 and 5,000",
    },
    {
      name: "capacity over 5,000",
      fields: { ticketCapacity: 5001 },
      error: "Ticket capacity must be between 1 and 5,000",
    },
    {
      name: "fractional capacity",
      fields: { ticketCapacity: 1.5 },
      error: "Ticket capacity must be between 1 and 5,000",
    },
    {
      name: "missing price",
      fields: { ticketPriceMinor: undefined },
      error: "Ticket price and capacity are required",
    },
    {
      name: "null price",
      fields: { ticketPriceMinor: null },
      error: "Ticket price and capacity are required",
    },
    {
      name: "missing capacity",
      fields: { ticketCapacity: undefined },
      error: "Ticket price and capacity are required",
    },
    {
      name: "null capacity",
      fields: { ticketCapacity: null },
      error: "Ticket price and capacity are required",
    },
  ])("refuses a paid draft with $name", async ({ fields, error }) => {
    const { asAdmin, draft, saveArgs } = await setupPaidDraft();

    await expect(
      asAdmin.mutation(api.gigs.saveDraft, { ...saveArgs, ...fields }),
    ).rejects.toThrow(error);
    expect(
      await asAdmin.query(api.gigs.getProject, { projectId: draft._id }),
    ).toMatchObject({ ticketing: "rsvp", revision: draft.revision });
  });

  test("saves valid paid fields and returns them from getProject", async () => {
    const { asAdmin, draft, saveArgs } = await setupPaidDraft();
    const saved = await asAdmin.mutation(api.gigs.saveDraft, saveArgs);

    expect(
      await asAdmin.query(api.gigs.getProject, { projectId: draft._id }),
    ).toMatchObject({
      ticketing: "paid",
      ticketPriceMinor: 1250,
      ticketCapacity: 100,
      revision: saved.revision,
    });
  });

  test("publishes a paid gig with band ownership and ticket inventory", async () => {
    const { t, asAdmin, bandId, draft, saveArgs } = await setupPaidDraft();
    await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
    const { gigId } = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });

    await t.run(async (ctx) => {
      expect(await ctx.db.get(gigId)).toMatchObject({
        createdByBand: bandId,
        ownerKind: "band",
        ticketing: "paid",
        ticketPriceMinor: 1250,
        ticketCurrency: "usd",
        ticketCapacity: 100,
        price: Math.round(1250 / 100),
      });
      expect(
        await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
          .unique(),
      ).toMatchObject({
        gigId,
        bandId,
        sellerKind: "band",
        capacity: 100,
        sold: 0,
        reserved: 0,
      });
    });
  });

  test("refuses paid publishing when card payments became pending after saving", async () => {
    const { t, asAdmin, bandId, draft, saveArgs } = await setupPaidDraft();
    await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
    await t.run(async (ctx) => {
      const payoutAccount = await ctx.db
        .query("bandPayoutAccounts")
        .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
        .unique();
      await ctx.db.patch(payoutAccount!._id, {
        chargesEnabled: true,
        cardPaymentsStatus: "pending",
      });
    });

    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("This band is not ready to sell tickets yet");
    await t.run(async (ctx) => {
      expect((await ctx.db.get(draft._id))?.status).toBe("draft");
      expect((await ctx.db.get(draft._id))?.publicGigId).toBeUndefined();
      expect(await ctx.db.query("gigTicketInventory").first()).toBeNull();
    });
  });

  test(
    "allows saving a published paid title when payout capability lapsed while still validating price and capacity",
    async () => {
      const { t, asAdmin, bandId, draft, saveArgs } = await setupPaidDraft();
      const saved = await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
      await asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id });
      await t.run(async (ctx) => {
        const payoutAccount = await ctx.db
          .query("bandPayoutAccounts")
          .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
          .unique();
        await ctx.db.patch(payoutAccount!._id, {
          cardPaymentsStatus: "inactive",
        });
      });

      const editArgs = {
        ...saveArgs,
        revision: saved.revision,
        title: "Updated Paid Band Show",
      };
      await expect(
        asAdmin.mutation(api.gigs.saveDraft, {
          ...editArgs,
          ticketPriceMinor: 99,
        }),
      ).rejects.toThrow("Ticket price must be at least $1.00");
      await expect(
        asAdmin.mutation(api.gigs.saveDraft, {
          ...editArgs,
          ticketCapacity: 0,
        }),
      ).rejects.toThrow("Ticket capacity must be between 1 and 5,000");
      await expect(
        asAdmin.mutation(api.gigs.saveDraft, editArgs),
      ).resolves.toEqual({ revision: saved.revision + 1 });
      expect(
        await asAdmin.query(api.gigs.getProject, { projectId: draft._id }),
      ).toMatchObject({
        title: editArgs.title,
        ticketing: "paid",
        status: "published",
      });
    },
  );

  test("refuses edits to a never-published paid draft after its payout account is removed", async () => {
    const { t, asAdmin, bandId, draft, saveArgs } = await setupPaidDraft();
    const saved = await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
    await t.run(async (ctx) => {
      const payoutAccount = await ctx.db
        .query("bandPayoutAccounts")
        .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
        .unique();
      await ctx.db.delete(payoutAccount!._id);
      expect(await ctx.db.get(draft._id)).toMatchObject({
        ticketing: "paid",
        status: "draft",
      });
    });

    await expect(
      asAdmin.mutation(api.gigs.saveDraft, {
        ...saveArgs,
        revision: saved.revision,
        title: "Still a draft",
      }),
    ).rejects.toThrow("Enable ticket sales in PAYOUTS first");
  });

  test.each(["ticketPriceMinor", "ticketCapacity"] as const)(
    "refuses to publish a paid draft missing %s",
    async (field) => {
      const { t, asAdmin, draft, saveArgs } = await setupPaidDraft();
      await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
      await t.run(async (ctx) => ctx.db.patch(draft._id, { [field]: undefined }));

      await expect(
        asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
      ).rejects.toThrow("Ticket price and capacity are required");
    },
  );

  test.each([
    {
      name: "updates capacity when inventory is available",
      sold: 0,
      reserved: 0,
      ticketCapacity: 50,
      expectedCapacity: 50,
    },
    {
      name: "clamps capacity to sold plus reserved",
      sold: 30,
      reserved: 25,
      ticketCapacity: 20,
      expectedCapacity: 55,
    },
  ])(
    "republishing $name",
    async ({ sold, reserved, ticketCapacity, expectedCapacity }) => {
      const { t, asAdmin, draft, saveArgs } = await setupPaidDraft();
      const saved = await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
      const published = await asAdmin.mutation(api.gigs.publishDraft, {
        projectId: draft._id,
      });
      const inventoryId = await t.run(async (ctx) => {
        const inventory = await ctx.db
          .query("gigTicketInventory")
          .withIndex("by_gigId", (q) => q.eq("gigId", published.gigId))
          .unique();
        if (!inventory) throw new Error("Expected published ticket inventory");
        await ctx.db.patch(inventory._id, { sold, reserved });
        return inventory._id;
      });

      await asAdmin.mutation(api.gigs.saveDraft, {
        ...saveArgs,
        revision: saved.revision,
        ticketCapacity,
      });
      const republished = await asAdmin.mutation(api.gigs.publishDraft, {
        projectId: draft._id,
      });

      expect(republished.gigId).toBe(published.gigId);
      await t.run(async (ctx) => {
        expect((await ctx.db.get(published.gigId))?.ticketCapacity).toBe(
          ticketCapacity,
        );
        expect(
          await ctx.db
            .query("gigTicketInventory")
            .withIndex("by_gigId", (q) => q.eq("gigId", published.gigId))
            .unique(),
        ).toMatchObject({
          _id: inventoryId,
          capacity: expectedCapacity,
          sold,
          reserved,
        });
      });
    },
  );
});

describe("band gig ticket cancellation, deletion, and public payload", () => {
  beforeEach(() => {
    // Observe refund requests without running the scheduled Stripe action.
    vi.useFakeTimers();
    vi.stubEnv("APP_BASE_URL", "https://earplug.app");
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.unstubAllEnvs();
  });

  async function setupPublishedGig(
    ticketing: "paid" | "rsvp" | "external" = "paid",
  ) {
    const fixture = await setupLifecycle();
    const { t, asAdmin, bandId, venueId } = fixture;
    if (ticketing === "paid") {
      await t.run((ctx) =>
        ctx.db.insert("bandPayoutAccounts", {
          bandId,
          stripeAccountId: "acct_band_lifecycle",
          chargesEnabled: true,
          cardPaymentsStatus: "active",
          payoutsEnabled: true,
          detailsSubmitted: true,
          requirementsDue: [],
          updatedAt: Date.now(),
        }),
      );
    }
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const saveArgs = {
      projectId: draft._id,
      revision: draft.revision,
      title: "Band Ticket Lifecycle",
      doorsAt,
      startsAt: doorsAt + 60 * 60_000,
      venueId,
      price: 0,
      flyKey: "xerox" as const,
      flyStorageId: null,
      overlay: true,
      desc: "A show managed by the band.",
      ticketing,
      ...(ticketing === "paid"
        ? { ticketPriceMinor: 1250, ticketCapacity: 100 }
        : {}),
      ageRequirement: "allAges" as const,
      externalUrl: ticketing === "external" ? "https://example.com/tickets" : null,
      cap: "No cap",
    };
    const saved = await asAdmin.mutation(api.gigs.saveDraft, saveArgs);
    const published = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });
    return {
      ...fixture,
      ...published,
      projectId: draft._id,
      saveArgs: { ...saveArgs, revision: saved.revision },
    };
  }

  async function insertTicketOrder(
    { t, gigId, bandId }: Awaited<ReturnType<typeof setupPublishedGig>>,
    status: Doc<"ticketOrders">["status"],
  ) {
    return await t.run(async (ctx) => {
      const buyerUserId = await ctx.db.insert("users", {
        clerkId: "band_ticket_buyer",
        name: "Ticket Buyer",
        email: "buyer@tickets.test",
        genres: [],
        attendedCount: 0,
      });
      const inventory = await ctx.db
        .query("gigTicketInventory")
        .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
        .unique();
      if (!inventory) throw new Error("Expected published ticket inventory");
      await ctx.db.patch(inventory._id, {
        sold: inventory.sold + (status === "paid" ? 2 : 0),
        reserved:
          inventory.reserved +
          (status === "reserved" || status === "checkout_open" ? 2 : 0),
      });
      return await ctx.db.insert("ticketOrders", {
        gigId,
        sellerKind: "band",
        bandId,
        buyerUserId,
        quantity: 2,
        unitPriceMinor: 1250,
        unitFeeMinor: 100,
        subtotalMinor: 2500,
        feeMinor: 200,
        totalMinor: 2700,
        currency: "usd",
        status,
        reservedUntil: Date.now() + 30 * 60_000,
        stripePaymentIntentId: status === "paid" ? "pi_band_lifecycle" : undefined,
        attempt: 1,
        refundedMinor: status === "refunded" ? 2700 : 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
    });
  }

  test("cancelling a paid band gig requests a refund only once", async () => {
    const fixture = await setupPublishedGig();
    const { t, asAdmin, bandId, gigId, projectId } = fixture;
    const orderId = await insertTicketOrder(fixture, "paid");

    await asAdmin.mutation(api.gigs.cancel, { projectId });
    await asAdmin.mutation(api.gigs.cancel, { projectId });

    await t.run(async (ctx) => {
      expect((await ctx.db.get(gigId))?.lifecycle).toBe("cancelled");
      expect((await ctx.db.get(projectId))?.status).toBe("cancelled");
      const refunds = await ctx.db
        .query("ticketRefunds")
        .withIndex("by_orderId", (q) => q.eq("orderId", orderId))
        .take(10);
      expect(refunds).toHaveLength(1);
      expect(refunds[0]).toMatchObject({
        orderId,
        gigId,
        sellerKind: "band",
        bandId,
        amountMinor: 2700,
        currency: "usd",
        reason: "event_cancelled",
        status: "pending",
        stripePaymentIntentId: "pi_band_lifecycle",
      });
    });
  });

  test.each(["paid", "refunded", "reserved", "checkout_open"] as const)(
    "refuses saving an RSVP draft for a published paid gig with a %s order",
    async (status) => {
      const fixture = await setupPublishedGig();
      const { t, asAdmin, gigId, projectId, saveArgs } = fixture;
      await insertTicketOrder(fixture, status);

      await expect(
        asAdmin.mutation(api.gigs.saveDraft, {
          ...saveArgs,
          ticketing: "rsvp",
        }),
      ).rejects.toThrow("Cancel the show before changing ticketing");
      await t.run(async (ctx) => {
        expect(await ctx.db.get(projectId)).toMatchObject({
          ticketing: "paid",
          revision: saveArgs.revision,
        });
        expect((await ctx.db.get(gigId))?.ticketing).toBe("paid");
      });
    },
  );

  test.each(["paid", "refunded", "reserved", "checkout_open"] as const)(
    "refuses publishing an RSVP draft when the live paid gig acquired a %s order",
    async (status) => {
      const fixture = await setupPublishedGig();
      const { t, asAdmin, gigId, projectId, saveArgs } = fixture;
      await asAdmin.mutation(api.gigs.saveDraft, {
        ...saveArgs,
        ticketing: "rsvp",
      });
      // Sales still use the paid public gig until the draft is published.
      await insertTicketOrder(fixture, status);

      await expect(
        asAdmin.mutation(api.gigs.publishDraft, { projectId }),
      ).rejects.toThrow("Cancel the show before changing ticketing");
      await t.run(async (ctx) => {
        expect((await ctx.db.get(projectId))?.ticketing).toBe("rsvp");
        expect((await ctx.db.get(gigId))?.ticketing).toBe("paid");
      });
    },
  );

  test("cancelling refunds paid live orders after the draft switched to RSVP", async () => {
    const fixture = await setupPublishedGig();
    const { t, asAdmin, bandId, gigId, projectId, saveArgs } = fixture;
    await insertTicketOrder(fixture, "expired");
    await asAdmin.mutation(api.gigs.saveDraft, {
      ...saveArgs,
      ticketing: "rsvp",
    });
    // A buyer pays for the still-paid public gig after the draft was saved.
    const orderId = await insertTicketOrder(fixture, "paid");
    await t.run(async (ctx) => {
      expect((await ctx.db.get(projectId))?.ticketing).toBe("rsvp");
      expect((await ctx.db.get(gigId))?.ticketing).toBe("paid");
    });

    await asAdmin.mutation(api.gigs.cancel, { projectId });

    await t.run(async (ctx) => {
      expect((await ctx.db.get(gigId))?.lifecycle).toBe("cancelled");
      expect(await ctx.db.get(projectId)).toMatchObject({
        ticketing: "rsvp",
        status: "cancelled",
      });
      const refunds = await ctx.db
        .query("ticketRefunds")
        .withIndex("by_orderId", (q) => q.eq("orderId", orderId))
        .take(10);
      expect(refunds).toHaveLength(1);
      expect(refunds[0]).toMatchObject({
        orderId,
        gigId,
        sellerKind: "band",
        bandId,
        amountMinor: 2700,
        reason: "event_cancelled",
        status: "pending",
        stripePaymentIntentId: "pi_band_lifecycle",
      });
    });
  });

  test.each(["reserved", "checkout_open"] as const)(
    "cancelling closes a %s order and releases its inventory",
    async (status) => {
      const fixture = await setupPublishedGig();
      const { t, asAdmin, gigId, projectId } = fixture;
      const orderId = await insertTicketOrder(fixture, status);

      await asAdmin.mutation(api.gigs.cancel, { projectId });

      await t.run(async (ctx) => {
        expect((await ctx.db.get(orderId))?.status).toBe("cancelled");
        expect(
          await ctx.db
            .query("gigTicketInventory")
            .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
            .unique(),
        ).toMatchObject({ reserved: 0, sold: 0 });
      });
      await expect(
        asAdmin.mutation(api.gigs.deleteGig, { projectId }),
      ).resolves.toBeNull();
    },
  );

  test.each(["rsvp", "external"] as const)(
    "cancels a %s gig without ticketing setup",
    async (ticketing) => {
      const { t, asAdmin, gigId, projectId } = await setupPublishedGig(ticketing);

      await expect(
        asAdmin.mutation(api.gigs.cancel, { projectId }),
      ).resolves.toBeNull();
      expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toMatchObject({
        lifecycle: "cancelled",
      });
    },
  );

  test.each(["reserved", "checkout_open"] as const)(
    "unpublishing leaves a %s order and its hold unchanged",
    async (status) => {
      const fixture = await setupPublishedGig();
      const { t, asAdmin, gigId, projectId } = fixture;
      const orderId = await insertTicketOrder(fixture, status);
      const before = await t.run((ctx) => ctx.db.get(orderId));

      await asAdmin.mutation(api.gigs.unpublish, { projectId });

      await t.run(async (ctx) => {
        expect(await ctx.db.get(orderId)).toEqual(before);
        expect(
          await ctx.db
            .query("gigTicketInventory")
            .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
            .unique(),
        ).toMatchObject({ reserved: 2, sold: 0 });
        expect((await ctx.db.get(gigId))?.lifecycle).toBe("unpublished");
      });
    },
  );

  test.each([
    { blocking: "paid", resolved: "cancelled" },
    { blocking: "refunded", resolved: "expired" },
    { blocking: "reserved", resolved: "expired" },
    { blocking: "checkout_open", resolved: "cancelled" },
  ] as const)(
    "refuses deletion for $blocking orders and allows it after $resolved",
    async ({ blocking, resolved }) => {
      const fixture = await setupPublishedGig();
      const { t, asAdmin, gigId, projectId } = fixture;
      const orderId = await insertTicketOrder(fixture, blocking);
      const before = await t.run(async (ctx) => ({
        project: await ctx.db.get(projectId),
        gig: await ctx.db.get(gigId),
      }));

      await expect(
        asAdmin.mutation(api.gigs.deleteGig, { projectId }),
      ).rejects.toThrow("Cancel the show first");
      expect(
        await t.run(async (ctx) => ({
          project: await ctx.db.get(projectId),
          gig: await ctx.db.get(gigId),
        })),
      ).toEqual(before);

      await t.run((ctx) => ctx.db.patch(orderId, { status: resolved }));
      await expect(
        asAdmin.mutation(api.gigs.deleteGig, { projectId }),
      ).resolves.toBeNull();
      await t.run(async (ctx) => {
        expect((await ctx.db.get(projectId))?.status).toBe("deleted");
        expect((await ctx.db.get(gigId))?.lifecycle).toBe("deleted");
      });
    },
  );

  test.each(["paid", "rsvp"] as const)(
    "deletes a %s gig with no orders",
    async (ticketing) => {
      const { t, asAdmin, gigId, projectId } = await setupPublishedGig(ticketing);

      await expect(
        asAdmin.mutation(api.gigs.deleteGig, { projectId }),
      ).resolves.toBeNull();
      await t.run(async (ctx) => {
        expect((await ctx.db.get(projectId))?.status).toBe("deleted");
        expect((await ctx.db.get(gigId))?.lifecycle).toBe("deleted");
      });
    },
  );

  test("deletes an unpublished draft without a public gig", async () => {
    const { t, asAdmin, bandId } = await setupLifecycle();
    const { _id: projectId } = await asAdmin.mutation(api.gigs.createDraft, {
      bandId,
    });

    await expect(
      asAdmin.mutation(api.gigs.deleteGig, { projectId }),
    ).resolves.toBeNull();
    await t.mutation(internal.gigs.purgeDeletedGig, { projectId });
    expect(await t.run((ctx) => ctx.db.get(projectId))).toBeNull();
  });

  test.each([
    "reserved",
    "checkout_open",
    "paid",
    "expired",
    "cancelled",
    "refunded",
    null,
  ] as const)("purge only deletes rows without orders (status: %s)", async (status) => {
    const fixture = await setupPublishedGig();
    const { t, gigId, projectId } = fixture;
    if (status !== null) await insertTicketOrder(fixture, status);
    await t.run(async (ctx) => {
      // Simulate an already-deleted project, including legacy blocking orders.
      await ctx.db.patch(projectId, { status: "deleted" });
      await ctx.db.patch(gigId, { lifecycle: "deleted" });
      const user = await ctx.db.query("users").first();
      if (!user) throw new Error("Expected the band admin");
      await ctx.db.insert("gigRsvps", { gigId, userId: user._id });
      await ctx.db.insert("gigSaves", { gigId, userId: user._id });
    });
    const state = () =>
      t.run(async (ctx) => ({
        project: await ctx.db.get(projectId),
        gig: await ctx.db.get(gigId),
        performers: await ctx.db.query("gigProjectPerformers").take(100),
        joins: await ctx.db.query("gigBands").take(100),
        rsvps: await ctx.db.query("gigRsvps").take(100),
        saves: await ctx.db.query("gigSaves").take(100),
        orders: await ctx.db.query("ticketOrders").take(100),
        scheduled: await ctx.db.system.query("_scheduled_functions").take(100),
      }));
    const before = await state();
    expect(before.performers).toHaveLength(1);
    expect(before.joins).toHaveLength(1);

    await t.mutation(internal.gigs.purgeDeletedGig, { projectId });

    const after = await state();
    if (status !== null) {
      expect(after).toEqual(before);
    } else {
      expect(after).toEqual({
        project: null,
        gig: null,
        performers: [],
        joins: [],
        rsvps: [],
        saves: [],
        orders: [],
        scheduled: before.scheduled,
      });
    }
  });

  test.each(["paid", "rsvp", "external"] as const)(
    "only names the band seller for paid gigs: %s",
    async (ticketing) => {
      const { t, gigId } = await setupPublishedGig(ticketing);

      const payload = await t.query(api.gigs.resolvePublic, { ref: gigId });
      expect(payload).not.toBeNull();
      expect(payload?.ticketSeller).toEqual(
        ticketing === "paid" ? { kind: "band", name: "Draft Mechanics" } : undefined,
      );
      const feed = await t.query(api.gigs.feedV2, {});
      expect(feed.gigs.find((gig) => gig._id === gigId)?.ticketSeller).toEqual(
        payload?.ticketSeller,
      );
    },
  );

  test("names the organization seller in the public paid gig payload", async () => {
    const { t, bandId, venueId } = await setupLifecycle();
    const gigId = await t.run(async (ctx) => {
      const user = await ctx.db.query("users").first();
      if (!user) throw new Error("Expected the band admin");
      const organizationId = await ctx.db.insert("organizations", {
        name: "Lifecycle Collective",
        slug: "lifecycle-collective",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: user._id,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      return await ctx.db.insert("gigs", {
        title: "Organization Ticket Show",
        venueId,
        price: 12,
        startsAt: Date.now() + 2 * 86_400_000,
        doorsTime: "7 PM",
        flyKey: "xerox",
        lineup: [bandId],
        genres: ["punk"],
        desc: "Organization ticket seller.",
        ticketing: "paid",
        ticketPriceMinor: 1250,
        ticketCurrency: "usd",
        ticketCapacity: 100,
        createdByOrganization: organizationId,
        ownerKind: "organization",
        lifecycle: "published",
        cap: "100",
        goingCount: 0,
      });
    });

    expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toMatchObject({
      ticketSeller: { kind: "organization", name: "Lifecycle Collective" },
    });
  });
});

describe("gig project lifecycle", () => {
  test("saves, previews through its private payload, publishes, unpublishes, cancels, and deletes", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    expect(draft.status).toBe("draft");
    expect(draft.performers.map((performer) => performer.name)).toEqual([
      "Draft Mechanics",
    ]);

    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Recoverable Show",
      doorsAt,
      startsAt,
      venueId,
      price: 10,
      flyKey: "paper",
      flyStorageId: null,
      overlay: true,
      desc: "Saved before publishing.",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const saved = await asAdmin.query(api.gigs.getProject, {
      projectId: draft._id,
    });
    expect(saved.title).toBe("Recoverable Show");

    const added = await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "text",
      name: "Unlisted Opener",
      role: "opener",
    });
    expect(added.performers.map((performer) => performer.name)).toEqual([
      "Draft Mechanics",
      "Unlisted Opener",
    ]);

    const { gigId } = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });
    expect(
      (await t.query(api.gigs.feedV2, {})).gigs.map((gig) => gig._id),
    ).toContain(gigId);

    await asAdmin.mutation(api.gigs.unpublish, { projectId: draft._id });
    expect((await t.query(api.gigs.feedV2, {})).gigs).toHaveLength(0);
    expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();

    await asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id });
    await asAdmin.mutation(api.gigs.cancel, { projectId: draft._id });
    expect((await t.query(api.gigs.feedV2, {})).gigs).toHaveLength(0);
    expect((await t.query(api.gigs.resolvePublic, { ref: gigId }))?.lifecycle).toBe(
      "cancelled",
    );

    const duplicate = await asAdmin.mutation(api.gigs.duplicate, {
      projectId: draft._id,
    });
    expect(duplicate.status).toBe("draft");
    expect(duplicate.publicGigId).toBeNull();
    expect(duplicate.title).toBe("Copy of Recoverable Show");

    await asAdmin.mutation(api.gigs.deleteGig, { projectId: draft._id });
    expect(await t.query(api.gigs.resolvePublic, { ref: gigId })).toBeNull();
    expect(
      (await asAdmin.query(api.gigs.manageForBand, { bandId })).map(
        (project) => project._id,
      ),
    ).not.toContain(draft._id);
  });

  test("management is restricted to band admins", async () => {
    const { t, bandId } = await setupLifecycle();
    const stranger = t.withIdentity({ subject: "stranger", email: "s@x.com" });
    await stranger.mutation(api.users.ensureUser, {});

    await expect(
      stranger.query(api.gigs.manageForBand, { bandId }),
    ).rejects.toThrow();
  });

  test("project publishing reuses URL, upload, and venue validation", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    let { revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "riso",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "not-a-url",
      cap: "No cap",
    });
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("External ticketing requires a valid HTTPS URL");

    const deletedFlyerId = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      await ctx.storage.delete(storageId);
      return storageId;
    });
    ({ revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "custom",
      flyStorageId: deletedFlyerId,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "https://example.com/tickets",
      cap: "No cap",
    }));
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("Flyer upload not found");

    ({ revision } = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision,
      title: "Validated Project",
      doorsAt,
      startsAt,
      venueId,
      price: 12,
      flyKey: "riso",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "external",
      ageRequirement: "allAges",
      externalUrl: "https://example.com/tickets",
      cap: "No cap",
    }));
    expect(revision).toBeGreaterThan(draft.revision);
    await t.run(async (ctx) => ctx.db.delete(venueId));
    await expect(
      asAdmin.mutation(api.gigs.publishDraft, { projectId: draft._id }),
    ).rejects.toThrow("Venue not found");
  });

  test("an orphaned public gig remains editable and can be republished", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    const saved = await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Repairable Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const { gigId: missingGigId } = await asAdmin.mutation(
      api.gigs.publishDraft,
      { projectId: draft._id },
    );
    await t.run(async (ctx) => ctx.db.delete(missingGigId));

    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: saved.revision,
      title: "Repaired Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "Saved after projection loss.",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "text",
      name: "Repair Opener",
      role: "opener",
    });
    const { gigId: replacementGigId } = await asAdmin.mutation(
      api.gigs.publishDraft,
      { projectId: draft._id },
    );

    expect(replacementGigId).not.toBe(missingGigId);
    expect(
      (await t.query(api.gigs.resolvePublic, { ref: replacementGigId }))?.title,
    ).toBe("Repaired Show");
  });

  test("invite expiry is materialized and a live claim stays published", async () => {
    const { t, asAdmin, bandId, venueId } = await setupLifecycle();
    const { bandId: guestBandId } = await asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Claimed Guest",
        genres: ["noise"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const draft = await asAdmin.mutation(api.gigs.createDraft, { bandId });
    const doorsAt = Date.now() + 2 * 86_400_000;
    const startsAt = doorsAt + 60 * 60_000;
    await asAdmin.mutation(api.gigs.saveDraft, {
      projectId: draft._id,
      revision: draft.revision,
      title: "Invitation Show",
      doorsAt,
      startsAt,
      venueId,
      price: 0,
      flyKey: "xerox",
      flyStorageId: null,
      overlay: true,
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      externalUrl: null,
      cap: "No cap",
    });
    const invited = await asAdmin.mutation(api.gigs.addPerformer, {
      projectId: draft._id,
      kind: "invited",
      name: "Mystery Guest",
      role: "support",
    });
    const inviteUrl = invited.performers.at(-1)?.inviteUrl;
    const token = inviteUrl?.split("/").at(-1);
    expect(token).toEqual(expect.any(String));
    if (!token) throw new Error("Expected performer invite token");

    await t.run(async (ctx) => {
      const performer = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_invite_token", (q) => q.eq("inviteToken", token))
        .unique();
      await ctx.db.patch(performer!._id, { inviteExpiresAt: Date.now() - 1 });
    });
    expect(
      await t.query(api.gigs.resolvePerformerInvite, { token }),
    ).toMatchObject({ performerName: "Mystery Guest" });
    await expect(
      asAdmin.mutation(api.gigs.claimPerformerInvite, {
        token,
        bandId: guestBandId,
      }),
    ).rejects.toThrow("Invitation is invalid or expired");

    await t.run(async (ctx) => {
      const performer = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_invite_token", (q) => q.eq("inviteToken", token))
        .unique();
      await ctx.db.patch(performer!._id, {
        inviteExpiresAt: Date.now() + 86_400_000,
      });
    });
    const { gigId } = await asAdmin.mutation(api.gigs.publishDraft, {
      projectId: draft._id,
    });
    await asAdmin.mutation(api.gigs.claimPerformerInvite, {
      token,
      bandId: guestBandId,
    });
    const project = await asAdmin.query(api.gigs.getProject, {
      projectId: draft._id,
    });
    expect(project.publishedRevision).not.toBe(project.revision);
    expect(
      (await t.query(api.gigs.resolvePublic, { ref: gigId }))?.discoveryListingReady,
    ).toBe(false);
    expect((await t.query(api.gigs.resolvePublic, { ref: gigId }))?.lineup).toContain(
      guestBandId,
    );
  });
});
