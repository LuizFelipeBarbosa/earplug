/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import { bookingEmail, type BookingEmailKind } from "./emails";
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
