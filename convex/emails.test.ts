/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import {
  bookingEmail,
  sendTicketEmail,
  ticketEmail,
  type BookingEmailKind,
} from "./emails";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const kinds: BookingEmailKind[] = [
  "offerSent",
  "offerAccepted",
  "offerDeclined",
  "offerExpired",
  "offerWithdrawn",
  "bookingConfirmed",
  "bookingCancelled",
  "reviewRequested",
];

const input = {
  opportunityTitle: "Autumn Sessions",
  bandName: "The Satellites",
  orgName: "Bay Area Shows",
  venueName: "The Lantern",
  // Early UTC catches accidental formatting in America/Los_Angeles.
  startsAt: Date.UTC(2026, 9, 17, 0, 30),
  link: "https://earplug.app/bookings/test-booking",
};

describe("bookingEmail", () => {
  test.each(kinds)("formats %s with the booking details and fee", (kind) => {
    const grossLabel = "USD $1,234.50";
    const { subject, text } = bookingEmail(kind, { ...input, grossLabel });

    expect(subject).toContain(input.opportunityTitle);
    expect(subject).toContain(input.venueName);
    expect(text).toContain(input.bandName);
    expect(text).toContain(input.orgName);
    expect(text).toContain(input.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).toContain(grossLabel);
    expect(text.split("\n").at(-1)).toBe(input.link);
    expect(subject).not.toMatch(/insurance|escrow/i);
    expect(text).not.toMatch(/insurance|escrow/i);
  });

  test.each(kinds)("formats %s without optional details", (kind) => {
    const { text } = bookingEmail(kind, input);

    expect(text).toContain("Sat, Oct 17");
    expect(text).not.toContain("undefined");
    expect(text).not.toContain("Fee:");
    expect(text).not.toContain("Reason:");
    expect(text.split("\n").at(-1)).toBe(input.link);
  });

  test.each(kinds)("includes a supplied reason for %s", (kind) => {
    const reason = "The date no longer works for the band.";
    const { text } = bookingEmail(kind, { ...input, reason });

    expect(text).toContain(reason);
    expect(text.split("\n").at(-1)).toBe(input.link);
  });
});

describe("ticketEmail", () => {
  const ticketInput = {
    gigTitle: "Autumn Sessions",
    venueName: input.venueName,
    startsAt: input.startsAt,
    quantity: 3,
    totalLabel: "63.90 USD",
    link: "https://earplug.app/t/test-ticket",
  };

  test("formats the receipt with quantity, total, date, venue, and ticket link", () => {
    const { subject, text } = ticketEmail("ticketReceipt", ticketInput);
    expect(subject).toBe("Your tickets for Autumn Sessions");
    expect(text).toContain("3 tickets");
    expect(text).toContain(ticketInput.gigTitle);
    expect(text).toContain(ticketInput.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).toContain("63.90 USD");
    expect(text.endsWith(`\n\n${ticketInput.link}`)).toBe(true);
  });

  test("formats the refund notice with total, date, venue, and link", () => {
    const { subject, text } = ticketEmail("ticketRefunded", ticketInput);
    expect(subject).toBe("Refund on the way for Autumn Sessions");
    expect(text).toContain("was refunded");
    expect(text).toContain(ticketInput.gigTitle);
    expect(text).toContain(ticketInput.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).toContain("63.90 USD");
    expect(text.endsWith(`\n\n${ticketInput.link}`)).toBe(true);
  });
});

describe("sendTicketEmail", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(input.startsAt);
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  async function setupOrder() {
    const t = convexTest(schema, modules);
    const ids = await t.run(async (ctx) => {
      const buyerUserId = await ctx.db.insert("users", {
        clerkId: "ticket_buyer",
        name: "Buyer",
        email: "  buyer@tickets.test  ",
        genres: [],
        attendedCount: 0,
      });
      const organizationId = await ctx.db.insert("organizations", {
        name: "Ticket Collective",
        slug: "ticket-collective",
        orgType: "venueOperator",
        status: "verified",
        ownerUserId: buyerUserId,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      const venueId = await ctx.db.insert("venues", {
        name: input.venueName,
        area: "Oakland",
        addr: "100 Main Street",
        distSF: "8 mi",
        distOak: "1 mi",
        lat: 37.8,
        lng: -122.27,
      });
      const gigId = await ctx.db.insert("gigs", {
        title: "Autumn Sessions",
        venueId,
        price: 20,
        startsAt: input.startsAt,
        doorsTime: "7 PM",
        flyKey: "xerox",
        lineup: [],
        genres: [],
        desc: "Live music",
        ticketing: "paid",
        ticketPriceMinor: 2000,
        ticketCurrency: "usd",
        ticketCapacity: 20,
        createdByOrganization: organizationId,
        cap: "20",
        goingCount: 0,
      });
      const orderId = await ctx.db.insert("ticketOrders", {
        gigId,
        organizationId,
        buyerUserId,
        quantity: 3,
        unitPriceMinor: 2000,
        unitFeeMinor: 130,
        subtotalMinor: 6000,
        feeMinor: 390,
        totalMinor: 6390,
        currency: "usd",
        status: "paid",
        reservedUntil: Date.now(),
        attempt: 1,
        refundedMinor: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
      return { buyerUserId, venueId, gigId, orderId };
    });
    const send = async (): Promise<void> => {
      // Keep the helper's void result instead of Convex's serialized null.
      await t.run(async (ctx) =>
        sendTicketEmail(ctx, (await ctx.db.get(ids.orderId))!, "ticketReceipt"),
      );
    };
    const emails = () =>
      t.run(async (ctx) =>
        (await ctx.db.system.query("_scheduled_functions").take(100)).filter(
          (job) =>
            job.name === "emails:send" && job.args[0].kind === "ticketReceipt",
        ),
      );
    return { t, ...ids, send, emails };
  }

  test.each(["", " \t\n ", null])(
    "skips scheduling when the buyer email is %j or the buyer is missing",
    async (email) => {
      const f = await setupOrder();
      await f.t.run(async (ctx) => {
        if (email === null) {
          await ctx.db.delete(f.buyerUserId);
        } else {
          await ctx.db.patch(f.buyerUserId, { email });
        }
      });
      await f.send();
      expect(await f.emails()).toEqual([]);
    },
  );

  test("trims the buyer email before scheduling", async () => {
    const f = await setupOrder();
    await f.send();
    const emails = await f.emails();
    expect(emails).toHaveLength(1);
    expect(emails[0].args[0].to).toBe("buyer@tickets.test");
  });

  test.each(["gig", "venue"] as const)(
    "returns early without scheduling when the %s is missing",
    async (missing) => {
      const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
      const f = await setupOrder();
      await f.t.run((ctx) =>
        ctx.db.delete(missing === "gig" ? f.gigId : f.venueId),
      );
      await expect(f.send()).resolves.toBeUndefined();
      expect(await f.emails()).toEqual([]);
      expect(warn).toHaveBeenCalledExactlyOnceWith(
        `sendTicketEmail: ${missing} not found for order ${f.orderId}`,
      );
    },
  );
});

describe("send", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllEnvs();
  });

  test("disabled sending logs the kind and subject without the recipient address", async () => {
    vi.stubEnv("RESEND_API_KEY", undefined);
    vi.stubEnv("RESEND_SEND_ENABLED", undefined);
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const t = convexTest(schema, modules);
    const to = "someone-private@example.test";
    await expect(
      t.action(internal.emails.send, {
        kind: "bookingConfirmed",
        to,
        subject: "Booking confirmed",
        text: "Your booking is confirmed.",
      }),
    ).resolves.toBeNull();
    expect(log).toHaveBeenCalledWith(
      expect.stringContaining("bookingConfirmed"),
    );
    expect(log).toHaveBeenCalledWith(
      expect.stringContaining("Booking confirmed"),
    );
    expect(JSON.stringify(log.mock.calls)).not.toContain(to);
  });
});
