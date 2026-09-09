/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import { insertGigWithBandIndex } from "./lib/helpers";
import { mintTickets } from "./lib/ticketMint";
import { TICKET_TOKEN_PREFIX } from "./lib/ticketStatus";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");
const NOW = Date.parse("2026-09-05T20:00:00Z");
const TICKET_TOKEN = "a".repeat(64);
const RSVP_TOKEN = "b".repeat(64);
const V2_PAYLOAD = `earplug:ticket:v2:${TICKET_TOKEN}`;
const V1_PAYLOAD = `earplug:ticket:v1:${RSVP_TOKEN}`;
const ACTORS = [
  "owner",
  "manager",
  "door",
  "finance",
  "admin",
  "member",
  "fan",
] as const;
type Actor = (typeof ACTORS)[number];

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.clearAllTimers();
  vi.useRealTimers();
});

async function setupDoor() {
  const t = convexTest(schema, modules);
  const as = (actor: Actor) => t.withIdentity({ subject: `door_${actor}` });
  const ids = await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `door_${actor}`,
        name: actor === "fan" ? "  Fan Guest  " : actor,
        email: `${actor}@door.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Door Collective",
      slug: "door-collective",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: NOW,
      updatedAt: NOW,
    });
    for (const role of ["owner", "manager", "door", "finance"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: NOW,
      });
    }
    const venueId = await ctx.db.insert("venues", {
      name: "Door Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
    });
    const bandFields = {
      name: "Door Band",
      slug: "door-band",
      genres: [],
      area: "Oakland",
      colorHex: "#7B8FFF",
      initials: "DB",
      followerCount: 0,
      pastShows: [],
    };
    const bandId = await ctx.db.insert("bands", bandFields);
    const otherBandId = await ctx.db.insert("bands", {
      ...bandFields,
      name: "Other Band",
      slug: "other-band",
    });
    for (const [actor, role] of [
      ["admin", "admin"],
      ["member", "member"],
    ] as const) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: users[actor],
        role,
      });
    }
    const gigFields = {
      title: "Door Show",
      venueId,
      price: 10,
      startsAt: NOW + 60 * 60 * 1000,
      doorsTime: "8 PM",
      flyKey: "xerox",
      lineup: [bandId],
      genres: [],
      desc: "An evening of local music",
      ticketing: "paid" as const,
      ageRequirement: "allAges" as const,
      cap: "500",
      goingCount: 0,
      createdByOrganization: organizationId,
    };
    // Omit lifecycle to exercise legacy gigs that default to published.
    const gigId = await insertGigWithBandIndex(ctx, gigFields);
    const otherGigId = await insertGigWithBandIndex(ctx, {
      ...gigFields,
      title: "Other Show",
    });
    const orderId = await ctx.db.insert("ticketOrders", {
      gigId,
      organizationId,
      buyerUserId: users.fan,
      quantity: 1,
      unitPriceMinor: 1000,
      unitFeeMinor: 0,
      subtotalMinor: 1000,
      feeMinor: 0,
      totalMinor: 1000,
      currency: "usd",
      status: "paid",
      reservedUntil: NOW,
      attempt: 1,
      paidAt: NOW,
      refundedMinor: 0,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const ticketFields = {
      orderId,
      gigId,
      organizationId,
      holderUserId: users.fan,
      createdAt: NOW,
    };
    const ticketId = await ctx.db.insert("tickets", {
      ...ticketFields,
      token: TICKET_TOKEN_PREFIX + TICKET_TOKEN,
      status: "valid",
    });
    const rsvpId = await ctx.db.insert("gigRsvps", {
      gigId,
      userId: users.fan,
      ticketToken: RSVP_TOKEN,
    });
    return {
      users,
      bandId,
      otherBandId,
      gigId,
      otherGigId,
      orderId,
      ticketId,
      rsvpId,
      ticketFields,
    };
  });

  const readRows = () =>
    t.run(async (ctx) => ({
      gig: await ctx.db.get(ids.gigId),
      order: await ctx.db.get(ids.orderId),
      ticket: await ctx.db.get(ids.ticketId),
      rsvp: await ctx.db.get(ids.rsvpId),
    }));
  return { t, as, ...ids, readRows };
}

describe("ticketsDoor.checkIn", () => {
  test("checks in a ticket minted by mintTicketsForOrder", async () => {
    const { t, as, gigId, users, ticketFields } = await setupDoor();
    const ticket = await t.run(async (ctx) => {
      await ctx.db.insert("gigTicketInventory", {
        gigId,
        organizationId: ticketFields.organizationId,
        capacity: 500,
        reserved: 1,
        sold: 1,
        updatedAt: NOW,
      });
      const orderId = await ctx.db.insert("ticketOrders", {
        gigId,
        organizationId: ticketFields.organizationId,
        buyerUserId: users.fan,
        quantity: 1,
        unitPriceMinor: 1000,
        unitFeeMinor: 0,
        subtotalMinor: 1000,
        feeMinor: 0,
        totalMinor: 1000,
        currency: "usd",
        status: "checkout_open",
        reservedUntil: NOW + 30 * 60_000,
        stripeCheckoutSessionId: "cs_test",
        checkoutExpiresAt: NOW + 30 * 60_000,
        attempt: 1,
        refundedMinor: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const order = (await ctx.db.get(orderId))!;
      const [ticketId] = await mintTickets(ctx, order, {
        paidAt: NOW,
        stripeChargeId: "ch_test",
        stripeEventId: "evt_test",
      });
      return (await ctx.db.get(ticketId))!;
    });

    expect(ticket.status).toBe("valid");
    expect(
      await as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: ticket.token.slice(TICKET_TOKEN_PREFIX.length),
      }),
    ).toEqual({ kind: "unknown" });
    expect(await t.run((ctx) => ctx.db.get(ticket._id))).toEqual(ticket);

    expect(
      await as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: ticket.token,
      }),
    ).toEqual({
      kind: "checkedIn",
      holderName: "Fan Guest",
      checkedInAt: NOW,
      source: "ticket",
    });
    const checkedIn = await t.run((ctx) => ctx.db.get(ticket._id));
    expect(checkedIn?.status).toBe("used");
  });

  test.each(["owner", "manager", "door"] as const)(
    "an organization %s checks in a v2 ticket exactly once",
    async (actor) => {
      const { as, gigId, users, readRows } = await setupDoor();
      const before = await readRows();
      expect(
        await as(actor).mutation(api.ticketsDoor.checkIn, {
          gigId,
          payload: ` \n${V2_PAYLOAD}\t `,
        }),
      ).toEqual({
        kind: "checkedIn",
        holderName: "Fan Guest",
        checkedInAt: NOW,
        source: "ticket",
      });
      const checkedIn = await readRows();
      expect(checkedIn).toEqual({
        ...before,
        ticket: {
          ...before.ticket,
          status: "used",
          checkedInAt: NOW,
          checkedInBy: users[actor],
        },
      });

      vi.setSystemTime(NOW + 1000);
      expect(
        await as("manager").mutation(api.ticketsDoor.checkIn, {
          gigId,
          payload: V2_PAYLOAD,
        }),
      ).toEqual({
        kind: "alreadyUsed",
        holderName: "Fan Guest",
        checkedInAt: NOW,
        source: "ticket",
      });
      expect(await readRows()).toEqual(checkedIn);
    },
  );

  test.each(["refunded", "cancelled"] as const)(
    "a %s ticket returns refunded without writing",
    async (status) => {
      const { t, as, gigId, ticketId, readRows } = await setupDoor();
      await t.run((ctx) => ctx.db.patch(ticketId, { status }));
      const before = await readRows();
      expect(
        await as("door").mutation(api.ticketsDoor.checkIn, {
          gigId,
          payload: V2_PAYLOAD,
        }),
      ).toEqual({ kind: "refunded" });
      expect(await readRows()).toEqual(before);
    },
  );

  test.each([V2_PAYLOAD, V1_PAYLOAD])(
    "rejects another event's token: %s",
    async (payload) => {
      const { as, otherGigId, readRows } = await setupDoor();
      const before = await readRows();
      expect(
        await as("door").mutation(api.ticketsDoor.checkIn, {
          gigId: otherGigId,
          payload,
        }),
      ).toEqual({ kind: "wrongEvent" });
      expect(await readRows()).toEqual(before);
    },
  );

  test.each([
    "garbage",
    "",
    TICKET_TOKEN,
    `earplug:ticket:v3:${TICKET_TOKEN}`,
    ...["v1", "v2"].flatMap((version) => [
      `earplug:ticket:${version}:${"a".repeat(63)}`,
      `earplug:ticket:${version}:${"a".repeat(65)}`,
      `earplug:ticket:${version}:${"A".repeat(64)}`,
      `earplug:ticket:${version}:${"g".repeat(64)}`,
      `earplug:ticket:${version}:${"a".repeat(32)} ${"a".repeat(32)}`,
    ]),
  ])(
    "returns unknown without writing for malformed payload: %s",
    async (payload) => {
      const { as, gigId, readRows } = await setupDoor();
      const before = await readRows();
      expect(
        await as("door").mutation(api.ticketsDoor.checkIn, { gigId, payload }),
      ).toEqual({ kind: "unknown" });
      expect(await readRows()).toEqual(before);
    },
  );

  test.each(["v1", "v2"])(
    "returns unknown for a missing %s token",
    async (version) => {
      const { as, gigId, readRows } = await setupDoor();
      const before = await readRows();
      expect(
        await as("door").mutation(api.ticketsDoor.checkIn, {
          gigId,
          payload: `earplug:ticket:${version}:${"c".repeat(64)}`,
        }),
      ).toEqual({ kind: "unknown" });
      expect(await readRows()).toEqual(before);
    },
  );

  test.each([V2_PAYLOAD, V1_PAYLOAD, "garbage"])(
    "a cancelled event rejects a scan without writing: %s",
    async (payload) => {
      const { t, as, gigId, readRows } = await setupDoor();
      await t.run((ctx) => ctx.db.patch(gigId, { lifecycle: "cancelled" }));
      const before = await readRows();
      expect(
        await as("door").mutation(api.ticketsDoor.checkIn, { gigId, payload }),
      ).toEqual({ kind: "eventCancelled" });
      expect(await readRows()).toEqual(before);
      expect((await readRows()).ticket?.status).toBe("valid");
    },
  );

  test("checks in a legacy RSVP once and preserves the first scan", async () => {
    const { as, gigId, users, readRows } = await setupDoor();
    const before = await readRows();
    expect(
      await as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: ` ${V1_PAYLOAD}\n`,
      }),
    ).toEqual({
      kind: "checkedIn",
      holderName: "Fan Guest",
      checkedInAt: NOW,
      source: "rsvp",
    });
    const checkedIn = await readRows();
    expect(checkedIn).toEqual({
      ...before,
      rsvp: { ...before.rsvp, checkedInAt: NOW, checkedInBy: users.door },
    });

    vi.setSystemTime(NOW + 1000);
    expect(
      await as("manager").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: V1_PAYLOAD,
      }),
    ).toEqual({
      kind: "alreadyUsed",
      holderName: "Fan Guest",
      checkedInAt: NOW,
      source: "rsvp",
    });
    expect(await readRows()).toEqual(checkedIn);
  });

  test("a used ticket without a stored timestamp falls back to zero", async () => {
    const { t, as, gigId, ticketId, readRows } = await setupDoor();
    await t.run((ctx) => ctx.db.patch(ticketId, { status: "used" }));
    const before = await readRows();
    expect(
      await as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: V2_PAYLOAD,
      }),
    ).toEqual({
      kind: "alreadyUsed",
      holderName: "Fan Guest",
      checkedInAt: 0,
      source: "ticket",
    });
    expect(await readRows()).toEqual(before);
  });

  test("an RSVP checked in at zero is already used", async () => {
    const { t, as, gigId, rsvpId, readRows } = await setupDoor();
    await t.run((ctx) => ctx.db.patch(rsvpId, { checkedInAt: 0 }));
    const before = await readRows();
    expect(
      await as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: V1_PAYLOAD,
      }),
    ).toEqual({
      kind: "alreadyUsed",
      holderName: "Fan Guest",
      checkedInAt: 0,
      source: "rsvp",
    });
    expect(await readRows()).toEqual(before);
  });

  test.each(["blank", "missing"])(
    "uses Guest for a %s holder name in both token paths",
    async (name) => {
      const { t, as, gigId, users } = await setupDoor();
      await t.run(async (ctx) => {
        if (name === "missing") await ctx.db.delete(users.fan);
        else await ctx.db.patch(users.fan, { name: " \t " });
      });
      for (const payload of [V2_PAYLOAD, V1_PAYLOAD]) {
        for (const kind of ["checkedIn", "alreadyUsed"]) {
          expect(
            await as("door").mutation(api.ticketsDoor.checkIn, {
              gigId,
              payload,
            }),
          ).toMatchObject({ kind, holderName: "Guest" });
        }
      }
    },
  );
});

describe("door authorization", () => {
  test.each(["fan", "finance", "admin", "member"] as const)(
    "rejects %s on organization gigs for both endpoints",
    async (actor) => {
      const { as, gigId, readRows } = await setupDoor();
      const before = await readRows();
      for (const payload of [V2_PAYLOAD, V1_PAYLOAD, "garbage"]) {
        await expect(
          as(actor).mutation(api.ticketsDoor.checkIn, { gigId, payload }),
        ).rejects.toThrow("Not permitted for this organization");
      }
      await expect(
        as(actor).query(api.ticketsDoor.doorRoster, { gigId }),
      ).rejects.toThrow("Not permitted for this organization");
      expect(await readRows()).toEqual(before);
    },
  );

  test("authorizes before reporting cancellation and requires a signed-in caller", async () => {
    const { t, as, gigId, readRows } = await setupDoor();
    await t.run((ctx) => ctx.db.patch(gigId, { lifecycle: "cancelled" }));
    const before = await readRows();
    await expect(
      as("fan").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: "garbage",
      }),
    ).rejects.toThrow("Not permitted for this organization");
    await expect(
      t.mutation(api.ticketsDoor.checkIn, { gigId, payload: V2_PAYLOAD }),
    ).rejects.toThrow("Not signed in");
    await expect(
      t.query(api.ticketsDoor.doorRoster, { gigId }),
    ).rejects.toThrow("Not signed in");
    expect(await readRows()).toEqual(before);
  });

  test.each(["creator", "lineup", "laterLineup"] as const)(
    "a band admin can use both token versions and the roster via %s",
    async (association) => {
      const { t, as, gigId, bandId, otherBandId, users, readRows } =
        await setupDoor();
      await t.run((ctx) =>
        ctx.db.patch(gigId, {
          createdByOrganization: undefined,
          createdByBand: association === "creator" ? bandId : undefined,
          lineup:
            association === "creator"
              ? []
              : association === "lineup"
                ? [bandId]
                : [otherBandId, bandId],
        }),
      );
      for (const [payload, source] of [
        [V2_PAYLOAD, "ticket"],
        [V1_PAYLOAD, "rsvp"],
      ] as const) {
        expect(
          await as("admin").mutation(api.ticketsDoor.checkIn, {
            gigId,
            payload,
          }),
        ).toEqual({
          kind: "checkedIn",
          holderName: "Fan Guest",
          checkedInAt: NOW,
          source,
        });
      }
      const rows = await readRows();
      expect(rows.ticket?.checkedInBy).toBe(users.admin);
      expect(rows.rsvp?.checkedInBy).toBe(users.admin);
      expect(
        await as("admin").query(api.ticketsDoor.doorRoster, { gigId }),
      ).toEqual({
        rsvpTotal: 1,
        rsvpCheckedIn: 1,
        ticketsSold: 1,
        ticketsCheckedIn: 1,
        truncated: false,
      });
    },
  );

  test.each(["member", "fan", "door"] as const)(
    "rejects a %s on band-owned gigs",
    async (actor) => {
      const { t, as, gigId, bandId, readRows } = await setupDoor();
      await t.run((ctx) =>
        ctx.db.patch(gigId, {
          createdByOrganization: undefined,
          createdByBand: bandId,
        }),
      );
      const before = await readRows();
      await expect(
        as(actor).mutation(api.ticketsDoor.checkIn, {
          gigId,
          payload: V2_PAYLOAD,
        }),
      ).rejects.toThrow("Only the band or organizer can check people in");
      await expect(
        as(actor).query(api.ticketsDoor.doorRoster, { gigId }),
      ).rejects.toThrow("Only the band or organizer can check people in");
      expect(await readRows()).toEqual(before);
    },
  );

  test("rejects gigs with no organizer or associated bands", async () => {
    const { t, as, gigId } = await setupDoor();
    await t.run((ctx) =>
      ctx.db.patch(gigId, { createdByOrganization: undefined, lineup: [] }),
    );
    await expect(
      as("admin").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: V2_PAYLOAD,
      }),
    ).rejects.toThrow("Only the band or organizer can check people in");
    await expect(
      as("admin").query(api.ticketsDoor.doorRoster, { gigId }),
    ).rejects.toThrow("Only the band or organizer can check people in");
  });

  test("both endpoints reject missing gigs", async () => {
    const { t, as, gigId } = await setupDoor();
    await t.run((ctx) => ctx.db.delete(gigId));
    await expect(
      as("door").mutation(api.ticketsDoor.checkIn, {
        gigId,
        payload: V2_PAYLOAD,
      }),
    ).rejects.toThrow("Gig not found");
    await expect(
      as("door").query(api.ticketsDoor.doorRoster, { gigId }),
    ).rejects.toThrow("Gig not found");
  });
});

describe("ticketsDoor.doorRoster", () => {
  test("counts only this gig's active tickets and includes timestamp zero", async () => {
    const { t, as, gigId, otherGigId, users, rsvpId, ticketFields } =
      await setupDoor();
    await t.run(async (ctx) => {
      await ctx.db.patch(rsvpId, { checkedInAt: 0 });
      await ctx.db.insert("gigRsvps", { gigId, userId: users.member });
      await ctx.db.insert("gigRsvps", {
        gigId,
        userId: users.manager,
        checkedInAt: NOW,
      });
      await ctx.db.insert("gigRsvps", {
        gigId: otherGigId,
        userId: users.fan,
        checkedInAt: NOW,
      });
      for (const [index, status] of (
        ["used", "refunded", "cancelled"] as const
      ).entries()) {
        await ctx.db.insert("tickets", {
          ...ticketFields,
          token: TICKET_TOKEN_PREFIX + (index + 1).toString(16).padStart(64, "0"),
          status,
          checkedInAt: status === "used" ? 0 : undefined,
        });
      }
      await ctx.db.insert("tickets", {
        ...ticketFields,
        gigId: otherGigId,
        token: TICKET_TOKEN_PREFIX + "d".repeat(64),
        status: "used",
        checkedInAt: NOW,
      });
    });
    for (const actor of ["owner", "manager", "door"] as const) {
      expect(
        await as(actor).query(api.ticketsDoor.doorRoster, { gigId }),
      ).toEqual({
        rsvpTotal: 3,
        rsvpCheckedIn: 2,
        ticketsSold: 2,
        ticketsCheckedIn: 1,
        truncated: false,
      });
    }
  });

  test.each(["rsvps", "tickets"] as const)(
    "caps %s at 500 and marks the 501st row as truncated",
    async (table) => {
      const { t, as, gigId, users, ticketFields } = await setupDoor();
      await t.run(async (ctx) => {
        for (let index = 1; index < 500; index++) {
          if (table === "rsvps") {
            await ctx.db.insert("gigRsvps", { gigId, userId: users.fan });
          } else {
            await ctx.db.insert("tickets", {
              ...ticketFields,
              token: TICKET_TOKEN_PREFIX + index.toString(16).padStart(64, "0"),
              status: "valid",
            });
          }
        }
      });
      const expected = {
        rsvpTotal: table === "rsvps" ? 500 : 1,
        rsvpCheckedIn: 0,
        ticketsSold: table === "tickets" ? 500 : 1,
        ticketsCheckedIn: 0,
        truncated: false,
      };
      expect(
        await as("door").query(api.ticketsDoor.doorRoster, { gigId }),
      ).toEqual(expected);

      // Give the sentinel a later creation time and ensure it is excluded from counts.
      vi.setSystemTime(NOW + 1000);
      await t.run(async (ctx) => {
        if (table === "rsvps") {
          await ctx.db.insert("gigRsvps", {
            gigId,
            userId: users.fan,
            checkedInAt: NOW,
          });
        } else {
          await ctx.db.insert("tickets", {
            ...ticketFields,
            token: TICKET_TOKEN_PREFIX + "e".repeat(64),
            status: "used",
            checkedInAt: NOW,
          });
        }
      });
      expect(
        await as("door").query(api.ticketsDoor.doorRoster, { gigId }),
      ).toEqual({ ...expected, truncated: true });
    },
  );
});
