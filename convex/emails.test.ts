import { describe, expect, test } from "vitest";
import { bookingEmail, type BookingEmailKind } from "./emails";

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
