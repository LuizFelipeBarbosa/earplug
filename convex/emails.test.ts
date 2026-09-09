/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import {
  bookingEmail,
  consentEmail,
  sendTicketEmail,
  ticketEmail,
  type BookingEmailKind,
} from "./emails";
import { appBaseUrl, deploymentName } from "./lib/env";
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

  test("formats a refund request with a category and requested amount", () => {
    const { subject, text } = bookingEmail("disputeOpened", {
      ...input,
      categoryLabel: "late or short set",
      amountLabel: "25.00 USD",
    });

    expect(subject).toBe("A dispute was opened on Autumn Sessions");
    expect(text).toContain("Category: late or short set.");
    expect(text).toContain("Requested refund: 25.00 USD");
    expect(text).toContain(input.bandName);
    expect(text).toContain(input.orgName);
    expect(text).toContain(input.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).not.toContain("Fee:");
    expect(text.endsWith(`\n\n${input.link}`)).toBe(true);
  });

  test("formats an artist dispute without a refund request", () => {
    const { subject, text } = bookingEmail("disputeOpened", {
      ...input,
      categoryLabel: "payment",
      venueName: "Private event",
    });

    expect(subject).toBe("A dispute was opened on Autumn Sessions");
    expect(text).toContain("Category: payment.");
    expect(text).toContain("Private event");
    expect(text).not.toContain("Requested refund:");
    expect(text).not.toContain("undefined");
    expect(`${subject} ${text}`).not.toMatch(/insurance|escrow/i);
  });

  test.each([
    { resolutionLabel: "artist payout released", amountLabel: undefined },
    { resolutionLabel: "dismissed", amountLabel: undefined },
    { resolutionLabel: "full refund", amountLabel: "100.00 USD" },
    { resolutionLabel: "partial refund", amountLabel: "20.00 USD" },
  ])("formats a resolution as $resolutionLabel", (details) => {
    const { subject, text } = bookingEmail("disputeResolved", {
      ...input,
      ...details,
      venueName: "Private event",
    });

    expect(subject).toBe("Dispute resolved on Autumn Sessions");
    expect(text).toContain(`Resolution: ${details.resolutionLabel}.`);
    expect(text).toContain("Private event");
    expect(text).toContain(input.bandName);
    expect(text).toContain(input.orgName);
    if (details.amountLabel) {
      expect(text).toContain(`Refund: ${details.amountLabel}`);
    } else {
      expect(text).not.toContain("Refund:");
    }
    expect(text).not.toContain("Fee:");
    expect(text).not.toContain("undefined");
    expect(`${subject} ${text}`).not.toMatch(/insurance|escrow/i);
    expect(text.endsWith(`\n\n${input.link}`)).toBe(true);
  });
});

describe("consentEmail", () => {
  const consentInput = {
    venueName: input.venueName,
    opportunityTitle: input.opportunityTitle,
    startsAt: input.startsAt,
    requestingOrganizationName: input.orgName,
  };
  const decisions = [
    ["granted", "approved"],
    ["declined", "declined"],
    ["revoked", "revoked"],
  ] as const;

  test("formats a venue request with the organization, event, and UTC date", () => {
    const { subject, text } = consentEmail("venueConsentRequested", {
      ...consentInput,
      status: "pending",
    });

    expect(subject).toContain(consentInput.requestingOrganizationName);
    expect(subject).toContain(consentInput.opportunityTitle);
    expect(subject).toContain("Sat, Oct 17");
    expect(text).toContain(consentInput.requestingOrganizationName);
    expect(text).toContain(consentInput.opportunityTitle);
    expect(text).toContain(consentInput.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).not.toContain("undefined");
  });

  test.each(decisions)("formats a %s decision with a note", (status, outcome) => {
    const note = "Please contact the venue team about the next steps.";
    const { subject, text } = consentEmail("venueConsentDecided", {
      ...consentInput,
      status,
      note,
    });

    expect(subject).toContain(outcome);
    expect(subject).toContain(consentInput.opportunityTitle);
    expect(text).toContain(consentInput.requestingOrganizationName);
    expect(text).toContain(consentInput.venueName);
    expect(text).toContain("Sat, Oct 17");
    expect(text).toContain(`Note: ${note}`);
    expect(text).not.toContain("undefined");
  });

  test.each(decisions)("formats a %s decision without a note", (status, outcome) => {
    const { subject, text } = consentEmail("venueConsentDecided", {
      ...consentInput,
      status,
    });

    expect(subject).toContain(outcome);
    expect(text).toContain("Sat, Oct 17");
    expect(text).not.toContain("undefined");
    expect(text).not.toContain("Note:");
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

describe("sendTest", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  test.each([undefined, "true"])(
    "skips without an API key when the sending flag is %s",
    async (enabled) => {
      vi.stubEnv("RESEND_API_KEY", undefined);
      vi.stubEnv("RESEND_SEND_ENABLED", enabled);
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      const t = convexTest(schema, modules);
      expect(
        await t.action(internal.emails.sendTest, { to: "ops@example.test" }),
      ).toEqual({ sent: false, reason: "RESEND_API_KEY unset" });
      expect(fetchMock).not.toHaveBeenCalled();
    },
  );

  test.each([undefined, "false"])(
    "skips with an API key when the sending flag is %s",
    async (enabled) => {
      vi.stubEnv("RESEND_API_KEY", "re_test_key");
      vi.stubEnv("RESEND_SEND_ENABLED", enabled);
      const fetchMock = vi.fn();
      vi.stubGlobal("fetch", fetchMock);
      const t = convexTest(schema, modules);
      expect(
        await t.action(internal.emails.sendTest, { to: "ops@example.test" }),
      ).toEqual({ sent: false, reason: "RESEND_SEND_ENABLED off" });
      expect(fetchMock).not.toHaveBeenCalled();
    },
  );

  test.each([
    {
      cloudUrl: "https://brilliant-cardinal-773.convex.cloud",
      baseUrl: "https://dev.earplug.example.test",
      deployment: "brilliant-cardinal-773",
    },
    { cloudUrl: undefined, baseUrl: undefined, deployment: "unknown" },
  ])(
    "sends a test email for $deployment",
    async ({ cloudUrl, baseUrl, deployment }) => {
      vi.stubEnv("RESEND_API_KEY", "re_test_key");
      vi.stubEnv("RESEND_SEND_ENABLED", "true");
      vi.stubEnv("CONVEX_CLOUD_URL", cloudUrl);
      vi.stubEnv("APP_BASE_URL", baseUrl);
      const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({ ok: true } as Response);
      vi.stubGlobal("fetch", fetchMock);
      const t = convexTest(schema, modules);
      const result = await t.action(internal.emails.sendTest, {
        to: "ops@example.test",
      });
      expect(result).toEqual({ sent: true });
      expect(fetchMock).toHaveBeenCalledOnce();
      const [url, request] = fetchMock.mock.calls[0];
      expect(url).toBe("https://api.resend.com/emails");
      expect(request).toMatchObject({
        method: "POST",
        headers: {
          Authorization: "Bearer re_test_key",
          "Content-Type": "application/json",
        },
      });
      const body = JSON.parse(request!.body as string);
      expect(body).toEqual({
        from: "EarPlug <no-reply@earplug.app>",
        to: ["ops@example.test"],
        subject: `EarPlug test email (${deployment})`,
        text: expect.stringContaining(appBaseUrl()),
      });
      expect(body.subject).toContain(deploymentName() ?? "unknown");
      expect(body.text).not.toContain("\n");
      expect(JSON.stringify(result)).not.toContain("re_test_key");
      expect(request!.body).not.toContain("re_test_key");
    },
  );

  test("propagates a failed Resend response", async () => {
    vi.stubEnv("RESEND_API_KEY", "re_test_key");
    vi.stubEnv("RESEND_SEND_ENABLED", "true");
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue({
      ok: false,
      status: 503,
    } as Response);
    vi.stubGlobal("fetch", fetchMock);
    const t = convexTest(schema, modules);
    await expect(
      t.action(internal.emails.sendTest, { to: "ops@example.test" }),
    ).rejects.toThrow("Resend send failed: 503");
    expect(fetchMock).toHaveBeenCalledOnce();
  });
});

describe("send", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllEnvs();
  });

  test.each(["disputeOpened", "disputeResolved"] as const)(
    "accepts the %s email kind",
    async (kind) => {
      vi.stubEnv("RESEND_SEND_ENABLED", "false");
      vi.spyOn(console, "log").mockImplementation(() => {});
      const t = convexTest(schema, modules);
      await expect(
        t.action(internal.emails.send, {
          kind,
          to: "party@disputes.test",
          ...bookingEmail(kind, {
            ...input,
            categoryLabel: "payment",
            resolutionLabel: "dismissed",
          }),
        }),
      ).resolves.toBeNull();
    },
  );

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
